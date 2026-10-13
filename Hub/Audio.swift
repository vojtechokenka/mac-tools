import AppKit
import AudioToolbox
import CoreAudio
import Synchronization

let unknownObject = AudioObjectID(kAudioObjectUnknown)
let systemObject = AudioObjectID(kAudioObjectSystemObject)

@discardableResult
func check(_ status: OSStatus, _ what: String) -> Bool {
    if status != noErr { log("\(what) failed: OSStatus \(status)") }
    return status == noErr
}

func propertyAddress(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
}

extension AudioObjectID {
    var isValid: Bool { self != unknownObject }

    func hasProperty(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> Bool {
        var address = propertyAddress(selector, scope: scope, element: element)
        return AudioObjectHasProperty(self, &address)
    }

    func readValue<T>(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain, initial: T, name: String) -> T? {
        var address = propertyAddress(selector, scope: scope, element: element)
        var size = UInt32(MemoryLayout<T>.size)
        var value = initial
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0) }
        guard check(status, "AudioObjectGetPropertyData(\(name))") else { return nil }
        return value
    }

    func readBool(_ selector: AudioObjectPropertySelector, name: String) -> Bool? {
        readValue(selector, initial: UInt32(0), name: name).map { $0 != 0 }
    }

    func readString(_ selector: AudioObjectPropertySelector, name: String) -> String? {
        var address = propertyAddress(selector)
        var unmanaged: Unmanaged<CFString>? = nil
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &unmanaged) { AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0) }
        guard check(status, "AudioObjectGetPropertyData(\(name))"), let unmanaged else { return nil }
        return unmanaged.takeRetainedValue() as String
    }

    func readArray<T>(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, initial: T, name: String) -> [T]? {
        var address = propertyAddress(selector, scope: scope)
        var size: UInt32 = 0
        guard check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "AudioObjectGetPropertyDataSize(\(name))") else { return nil }
        var items = [T](repeating: initial, count: Int(size) / MemoryLayout<T>.size)
        if items.isEmpty { return items }
        let status = items.withUnsafeMutableBufferPointer { AudioObjectGetPropertyData(self, &address, 0, nil, &size, $0.baseAddress!) }
        guard check(status, "AudioObjectGetPropertyData(\(name))") else { return nil }
        return Array(items.prefix(Int(size) / MemoryLayout<T>.size))
    }

    func streamCount(scope: AudioObjectPropertyScope) -> Int {
        var address = propertyAddress(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        guard check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "AudioObjectGetPropertyDataSize(kAudioDevicePropertyStreams)") else { return 0 }
        return Int(size) / MemoryLayout<AudioObjectID>.size
    }

    func bufferChannelCounts(scope: AudioObjectPropertyScope) -> [Int]? {
        var address = propertyAddress(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size: UInt32 = 0
        guard check(AudioObjectGetPropertyDataSize(self, &address, 0, nil, &size), "AudioObjectGetPropertyDataSize(kAudioDevicePropertyStreamConfiguration)") else { return nil }
        guard size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return [] }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        guard check(AudioObjectGetPropertyData(self, &address, 0, nil, &size, list), "AudioObjectGetPropertyData(kAudioDevicePropertyStreamConfiguration)") else { return nil }
        return UnsafeMutableAudioBufferListPointer(list).map { Int($0.mNumberChannels) }
    }
}

struct AudioApp {
    let bundleID: String
    let name: String
    let icon: NSImage?
    let processObjectIDs: [AudioObjectID]
    let isPlaying: Bool
}

final class ProcessMonitor {
    var onChange: (([AudioApp]) -> Void)?
    private(set) var apps: [AudioApp] = []
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private var listAddress = propertyAddress(kAudioHardwarePropertyProcessObjectList)
    private var listListener: AudioObjectPropertyListenerBlock?
    private var processListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var pendingRefresh: DispatchWorkItem?

    private typealias ResponsibilityFunction = @convention(c) (pid_t) -> pid_t
    private static let responsibilityFunction: ResponsibilityFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -1), "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsibilityFunction.self)
    }()

    func start() {
        guard listListener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh() }
        listListener = block
        check(AudioObjectAddPropertyListenerBlock(systemObject, &listAddress, .main, block), "AudioObjectAddPropertyListenerBlock(kAudioHardwarePropertyProcessObjectList)")
        refresh()
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        if let block = listListener {
            check(AudioObjectRemovePropertyListenerBlock(systemObject, &listAddress, .main, block), "AudioObjectRemovePropertyListenerBlock(kAudioHardwarePropertyProcessObjectList)")
            listListener = nil
        }
        for objectID in Array(processListeners.keys) { removeProcessListener(objectID) }
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.refresh() }
        pendingRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func refresh() {
        pendingRefresh = nil
        guard let objectIDs = systemObject.readArray(kAudioHardwarePropertyProcessObjectList, initial: unknownObject, name: "kAudioHardwarePropertyProcessObjectList") else { return }
        syncProcessListeners(objectIDs)

        let runningByPID = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { _, latest in latest })
        var grouped: [String: (app: NSRunningApplication, objectIDs: [AudioObjectID], playing: Bool)] = [:]

        for objectID in objectIDs {
            guard let pid = objectID.readValue(kAudioProcessPropertyPID, initial: pid_t(0), name: "kAudioProcessPropertyPID"), pid != ownPID else { continue }
            let coreAudioBundleID = objectID.readString(kAudioProcessPropertyBundleID, name: "kAudioProcessPropertyBundleID")
            guard let app = responsibleApp(for: pid, in: runningByPID, coreAudioBundleID: coreAudioBundleID), let bundleID = app.bundleIdentifier else { continue }
            let playing = objectID.readBool(kAudioProcessPropertyIsRunningOutput, name: "kAudioProcessPropertyIsRunningOutput") ?? false
            if var entry = grouped[bundleID] {
                entry.objectIDs.append(objectID)
                entry.playing = entry.playing || playing
                grouped[bundleID] = entry
            } else {
                grouped[bundleID] = (app, [objectID], playing)
            }
        }

        apps = grouped.map { bundleID, entry in
            AudioApp(bundleID: bundleID, name: entry.app.localizedName ?? bundleID, icon: entry.app.icon, processObjectIDs: entry.objectIDs.sorted(), isPlaying: entry.playing)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onChange?(apps)
    }

    private func responsibleApp(for pid: pid_t, in runningByPID: [pid_t: NSRunningApplication], coreAudioBundleID: String?) -> NSRunningApplication? {
        if let function = Self.responsibilityFunction {
            let responsible = function(pid)
            if responsible > 0, let app = runningByPID[responsible], app.bundleURL?.pathExtension == "app" { return app }
        }
        var current = pid
        var visited = Set<pid_t>()
        while current > 1, !visited.contains(current) {
            visited.insert(current)
            if let app = runningByPID[current], app.bundleURL?.pathExtension == "app" { return app }
            guard let parent = parentPID(of: current), parent != current else { break }
            current = parent
        }
        if let coreAudioBundleID, !coreAudioBundleID.isEmpty {
            return NSRunningApplication.runningApplications(withBundleIdentifier: coreAudioBundleID).first { $0.bundleURL?.pathExtension == "app" }
        }
        return nil
    }

    private func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    private func syncProcessListeners(_ objectIDs: [AudioObjectID]) {
        let current = Set(objectIDs)
        for objectID in processListeners.keys where !current.contains(objectID) { removeProcessListener(objectID) }
        for objectID in current where processListeners[objectID] == nil { addProcessListener(objectID) }
    }

    private func addProcessListener(_ objectID: AudioObjectID) {
        var address = propertyAddress(kAudioProcessPropertyIsRunningOutput)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh() }
        if check(AudioObjectAddPropertyListenerBlock(objectID, &address, .main, block), "AudioObjectAddPropertyListenerBlock(kAudioProcessPropertyIsRunningOutput)") {
            processListeners[objectID] = block
        }
    }

    private func removeProcessListener(_ objectID: AudioObjectID) {
        guard let block = processListeners.removeValue(forKey: objectID) else { return }
        var address = propertyAddress(kAudioProcessPropertyIsRunningOutput)
        let status = AudioObjectRemovePropertyListenerBlock(objectID, &address, .main, block)
        if status != OSStatus(kAudioHardwareBadObjectError) {
            check(status, "AudioObjectRemovePropertyListenerBlock(kAudioProcessPropertyIsRunningOutput)")
        }
    }
}

final class MixSlot: @unchecked Sendable {
    let gain: Atomic<Float>
    let inputPeak = Atomic<Float>(0)
    let meanSquare = Atomic<Float>(0)
    let channels: Int
    let interleaved: Bool
    let bufferCount: Int
    let bufferOffset: Int
    var currentGain: Float

    init(channels: Int, interleaved: Bool, bufferOffset: Int, gain: Float) {
        self.gain = Atomic(gain)
        self.channels = max(1, channels)
        self.interleaved = interleaved
        bufferCount = interleaved ? 1 : self.channels
        self.bufferOffset = bufferOffset
        currentGain = gain
    }
}

final class RealtimeState: @unchecked Sendable {
    static let scratchFrames = 4096
    static let maxSlots = 16

    let slots: [MixSlot]
    let masterGain: Atomic<Float>
    let sleepGain: Atomic<Float>
    let nightEnabled: Atomic<Bool>
    let ceiling: Atomic<Float>
    let renderedFrames = Atomic<Int>(0)
    let layoutMismatches = Atomic<Int>(0)
    let observedInputBuffers = Atomic<Int>(0)
    let observedOutputBuffers = Atomic<Int>(0)
    let observedOutputChannels = Atomic<Int>(0)
    let outputPeak = Atomic<Float>(0)
    let outputMeanSquare = Atomic<Float>(0)
    let levelerDB = Atomic<Float>(0)
    let compDB = Atomic<Float>(0)
    let nightPrimed = Atomic<Bool>(false)

    private let night: NightChain
    private let scratchLeft: UnsafeMutablePointer<Float>
    private let scratchRight: UnsafeMutablePointer<Float>
    private let smoothingCoefficient: Float
    private let meterRate: Float
    private let tapBufferCount: Int
    private let outputChannels: Int
    private let outputBufferCount: Int
    private let fadeStep: Float
    private var currentMaster: Float
    private var currentSleep: Float
    private var activeNight: Bool
    private var fade: Float = 1
    private var fadeDirection = 0
    private var holdZero = 0

    init(sampleRate: Double, slots: [MixSlot], outputChannels: Int, outputBufferCount: Int, masterGain: Float, sleepGain: Float, nightEnabled: Bool, ceiling: Float, nightSeed: (levelerDB: Float, compDB: Float)?) {
        self.slots = slots
        self.masterGain = Atomic(masterGain)
        self.sleepGain = Atomic(sleepGain)
        self.nightEnabled = Atomic(nightEnabled)
        self.ceiling = Atomic(ceiling)
        night = NightChain(sampleRate: sampleRate, maxFrames: Self.scratchFrames)
        if nightEnabled, let nightSeed {
            night.prime(levelerGainDB: nightSeed.levelerDB, compressorGainDB: nightSeed.compDB)
            levelerDB.store(night.levelerGainDB, ordering: .relaxed)
            compDB.store(night.compressorGainDB, ordering: .relaxed)
        }
        scratchLeft = .allocate(capacity: Self.scratchFrames)
        scratchRight = .allocate(capacity: Self.scratchFrames)
        scratchLeft.initialize(repeating: 0, count: Self.scratchFrames)
        scratchRight.initialize(repeating: 0, count: Self.scratchFrames)
        smoothingCoefficient = Float(1 - exp(-1 / (sampleRate * 0.010)))
        meterRate = Float(1 / (sampleRate * 0.3))
        fadeStep = 1 / Float(max(1, (0.008 * sampleRate).rounded()))
        activeNight = nightEnabled
        tapBufferCount = slots.reduce(0) { $0 + $1.bufferCount }
        self.outputChannels = max(1, outputChannels)
        self.outputBufferCount = outputBufferCount
        currentMaster = masterGain
        currentSleep = sleepGain
    }

    deinit {
        scratchLeft.deallocate()
        scratchRight.deallocate()
    }

    func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>) {
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        let outputCount = outputs.count
        for i in 0..<outputCount {
            let buffer = outputs[i]
            if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
        }

        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let inputCount = inputs.count
        observedInputBuffers.store(inputCount, ordering: .relaxed)
        observedOutputBuffers.store(outputCount, ordering: .relaxed)
        guard outputCount > 0, inputCount >= tapBufferCount else {
            layoutMismatches.wrappingAdd(1, ordering: .relaxed)
            return
        }

        let tapStart = inputCount - tapBufferCount
        let outBuffer = outputs[0]
        observedOutputChannels.store(Int(outBuffer.mNumberChannels), ordering: .relaxed)
        guard let outData = outBuffer.mData, Int(outBuffer.mNumberChannels) == outputChannels else {
            layoutMismatches.wrappingAdd(1, ordering: .relaxed)
            return
        }

        let sampleSize = MemoryLayout<Float>.size
        var frames = Int(outBuffer.mDataByteSize) / (sampleSize * outputChannels)
        for slot in slots {
            let buffer = inputs[tapStart + slot.bufferOffset]
            let bufferChannels = Int(buffer.mNumberChannels)
            guard buffer.mData != nil, bufferChannels == (slot.interleaved ? slot.channels : 1) else {
                layoutMismatches.wrappingAdd(1, ordering: .relaxed)
                return
            }
            frames = min(frames, Int(buffer.mDataByteSize) / (sampleSize * bufferChannels))
            if !slot.interleaved, slot.channels > 1 {
                let rightBuffer = inputs[tapStart + slot.bufferOffset + 1]
                guard rightBuffer.mData != nil, rightBuffer.mNumberChannels == 1 else {
                    layoutMismatches.wrappingAdd(1, ordering: .relaxed)
                    return
                }
                frames = min(frames, Int(rightBuffer.mDataByteSize) / sampleSize)
            }
        }

        let outLeft = outData.assumingMemoryBound(to: Float.self)
        var outRight = outLeft
        var outStride = outputChannels
        var monoOutput = false
        if outputChannels >= 2 {
            outRight = outLeft + 1
        } else if outputCount >= 2, outputBufferCount >= 2 {
            let rightBuffer = outputs[1]
            guard let rightData = rightBuffer.mData, rightBuffer.mNumberChannels == 1 else {
                layoutMismatches.wrappingAdd(1, ordering: .relaxed)
                return
            }
            outRight = rightData.assumingMemoryBound(to: Float.self)
            outStride = 1
            frames = min(frames, Int(rightBuffer.mDataByteSize) / sampleSize)
        } else {
            monoOutput = true
            outStride = 1
        }
        guard frames > 0 else { return }

        let nightOn = nightEnabled.load(ordering: .relaxed)
        let masterTarget = masterGain.load(ordering: .relaxed)
        let sleepTarget = sleepGain.load(ordering: .relaxed)
        let ceilingValue = ceiling.load(ordering: .relaxed)
        if nightOn != activeNight && fadeDirection == 0 { fadeDirection = -1 }

        var m = currentMaster
        var s = currentSleep
        let coefficient = smoothingCoefficient
        let step = fadeStep
        var offset = 0
        var outPeak = outputPeak.load(ordering: .relaxed)
        var outMeanSquare = outputMeanSquare.load(ordering: .relaxed)
        let meterRate = self.meterRate
        while offset < frames {
            var n = min(Self.scratchFrames, frames - offset)
            if fadeDirection < 0 { n = min(n, max(1, Int((fade / step).rounded(.up)))) }
            for i in 0..<n {
                scratchLeft[i] = 0
                scratchRight[i] = 0
            }
            for slot in slots {
                guard let data = inputs[tapStart + slot.bufferOffset].mData else { continue }
                let inLeft = data.assumingMemoryBound(to: Float.self)
                var inRight = inLeft
                var inStride = 1
                if slot.interleaved {
                    inStride = slot.channels
                    if slot.channels > 1 { inRight = inLeft + 1 }
                } else if slot.channels > 1, let rightData = inputs[tapStart + slot.bufferOffset + 1].mData {
                    inRight = rightData.assumingMemoryBound(to: Float.self)
                }
                let target = slot.gain.load(ordering: .relaxed)
                var g = slot.currentGain
                var peak = slot.inputPeak.load(ordering: .relaxed)
                var energy: Float = 0
                for i in 0..<n {
                    let f = (offset + i) * inStride
                    let l = inLeft[f]
                    let r = inRight[f]
                    let a = max(l.magnitude, r.magnitude)
                    if a > peak { peak = a }
                    g += (target - g) * coefficient
                    let sl = l * g
                    let sr = r * g
                    scratchLeft[i] += sl
                    scratchRight[i] += sr
                    energy += sl * sl + sr * sr
                }
                if (target - g).magnitude < 1e-6 { g = target }
                slot.currentGain = g
                slot.inputPeak.store(peak, ordering: .relaxed)
                let blockCoefficient = 1 - exp(-Float(n) * meterRate)
                var slotMeanSquare = slot.meanSquare.load(ordering: .relaxed)
                slotMeanSquare += blockCoefficient * (energy / Float(2 * n) - slotMeanSquare)
                if !slotMeanSquare.isFinite { slotMeanSquare = 0 }
                slot.meanSquare.store(slotMeanSquare, ordering: .relaxed)
            }
            if activeNight {
                night.process(left: scratchLeft, right: scratchRight, frames: n, ceiling: ceilingValue)
                levelerDB.store(night.levelerGainDB, ordering: .relaxed)
                compDB.store(night.compressorGainDB, ordering: .relaxed)
            }
            var outEnergy: Float = 0
            for i in 0..<n {
                m += (masterTarget - m) * coefficient
                s += (sleepTarget - s) * coefficient
                let gain = m * s
                var l = scratchLeft[i] * gain
                var r = scratchRight[i] * gain
                if activeNight {
                    if l > ceilingValue { l = ceilingValue } else if l < -ceilingValue { l = -ceilingValue }
                    if r > ceilingValue { r = ceilingValue } else if r < -ceilingValue { r = -ceilingValue }
                }
                if fadeDirection < 0 {
                    fade -= step
                    if fade < 0 { fade = 0 }
                } else if fadeDirection > 0 {
                    if holdZero > 0 {
                        holdZero -= 1
                    } else {
                        fade += step
                        if fade >= 1 { fade = 1; fadeDirection = 0 }
                    }
                }
                let ol = l * fade
                let orr = r * fade
                scratchLeft[i] = ol
                scratchRight[i] = orr
                let o = max(ol.magnitude, orr.magnitude)
                if o > outPeak { outPeak = o }
                outEnergy += ol * ol + orr * orr
            }
            outMeanSquare += (1 - exp(-Float(n) * meterRate)) * (outEnergy / Float(2 * n) - outMeanSquare)
            if !outMeanSquare.isFinite { outMeanSquare = 0 }
            if fadeDirection < 0 && fade == 0 {
                activeNight = nightOn
                holdZero = 0
                if activeNight {
                    night.reset()
                    holdZero = night.latencySamples
                }
                fadeDirection = 1
            }
            if monoOutput {
                for i in 0..<n { outLeft[offset + i] = 0.5 * (scratchLeft[i] + scratchRight[i]) }
            } else {
                for i in 0..<n {
                    let f = (offset + i) * outStride
                    outLeft[f] = scratchLeft[i]
                    outRight[f] = scratchRight[i]
                }
            }
            offset += n
        }
        if (masterTarget - m).magnitude < 1e-6 { m = masterTarget }
        if (sleepTarget - s).magnitude < 1e-6 { s = sleepTarget }
        currentMaster = m
        currentSleep = s
        outputPeak.store(outPeak, ordering: .relaxed)
        outputMeanSquare.store(outMeanSquare, ordering: .relaxed)
        nightPrimed.store(activeNight && fadeDirection == 0, ordering: .relaxed)
        renderedFrames.wrappingAdd(frames, ordering: .relaxed)
    }
}

final class MixBus {
    let requestedApps: [AudioApp]
    private(set) var apps: [AudioApp] = []
    private(set) var slotIndices: [String: Int] = [:]
    var onFormatChanged: (() -> Void)?
    private(set) var state: RealtimeState?
    private var tapIDs: [AudioObjectID] = []
    private var tapDescriptions: [CATapDescription] = []
    private var aggregateID = unknownObject
    private var procID: AudioDeviceIOProcID?
    private var formatAddress = propertyAddress(kAudioTapPropertyFormat)
    private var formatListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]

    var isActive: Bool { aggregateID.isValid }

    init(apps: [AudioApp]) {
        let sorted = apps.sorted { $0.bundleID < $1.bundleID }
        if sorted.count > RealtimeState.maxSlots {
            log("\(sorted.count) apps playing, mix bus takes only the first \(RealtimeState.maxSlots)")
        }
        requestedApps = Array(sorted.prefix(RealtimeState.maxSlots))
    }

    func build(outputDevice: AudioDeviceID, gains: [Float], masterGain: Float, sleepGain: Float, nightEnabled: Bool, ceiling: Float, nightSeed: (levelerDB: Float, compDB: Float)?) -> Bool {
        guard outputDevice.isValid else {
            log("mix bus: no output device, bus not created")
            return false
        }
        guard let outputUID = outputDevice.readString(kAudioDevicePropertyDeviceUID, name: "kAudioDevicePropertyDeviceUID") else { return false }
        let transport = outputDevice.readValue(kAudioDevicePropertyTransportType, initial: UInt32(0), name: "kAudioDevicePropertyTransportType") ?? 0
        let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
        guard transport != kAudioDeviceTransportTypeAggregate else {
            log("mix bus: default output is an aggregate or Multi-Output device, it cannot be nested into the bus")
            return false
        }

        var slots: [MixSlot] = []
        var tapList: [[String: Any]] = []
        var bufferOffset = 0
        var tapSampleRate = 0.0
        var slotDescriptions: [String] = []
        var builtApps: [AudioApp] = []
        for (index, app) in requestedApps.enumerated() {
            let description = CATapDescription(stereoMixdownOfProcesses: app.processObjectIDs)
            description.uuid = UUID()
            description.muteBehavior = .mutedWhenTapped
            description.isPrivate = true
            var tap = unknownObject
            guard check(AudioHardwareCreateProcessTap(description, &tap), "AudioHardwareCreateProcessTap(\(app.name))") else {
                log("\(app.name): cannot create tap, app skipped in the mix")
                continue
            }
            guard let format = tap.readValue(kAudioTapPropertyFormat, initial: AudioStreamBasicDescription(), name: "kAudioTapPropertyFormat") else {
                log("\(app.name): cannot read tap format, app skipped in the mix")
                check(AudioHardwareDestroyProcessTap(tap), "AudioHardwareDestroyProcessTap(\(tap))")
                continue
            }
            guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
                log("\(app.name): tap has no Float32 format (id \(format.mFormatID), flags \(format.mFormatFlags), bits \(format.mBitsPerChannel)), app skipped in the mix")
                check(AudioHardwareDestroyProcessTap(tap), "AudioHardwareDestroyProcessTap(\(tap))")
                continue
            }
            tapIDs.append(tap)
            tapDescriptions.append(description)
            builtApps.append(app)
            let channels = Int(format.mChannelsPerFrame)
            let interleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0
            let slot = MixSlot(channels: channels, interleaved: interleaved, bufferOffset: bufferOffset, gain: index < gains.count ? gains[index] : 1)
            slots.append(slot)
            bufferOffset += slot.bufferCount
            if tapSampleRate == 0 { tapSampleRate = format.mSampleRate }
            slotDescriptions.append("\(app.name) (tap \(tap), \(slot.channels) ch \(interleaved ? "interleaved" : "non-interleaved"), processes \(app.processObjectIDs))")
            tapList.append([
                kAudioSubTapDriftCompensationKey: !isBluetooth,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ])
        }
        guard !slots.isEmpty else {
            log("mix bus: no tap could be created, bus not created")
            teardown()
            return false
        }
        apps = builtApps
        slotIndices = Dictionary(uniqueKeysWithValues: builtApps.enumerated().map { ($1.bundleID, $0) })

        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Hub",
            kAudioAggregateDeviceUIDKey: "cz.vojtechokenka.hub.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceClockDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: tapList,
        ]
        var aggregate = unknownObject
        guard check(AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate), "AudioHardwareCreateAggregateDevice(Hub)") else { teardown(); return false }
        aggregateID = aggregate

        let sampleRate = aggregate.readValue(kAudioDevicePropertyNominalSampleRate, initial: Float64(0), name: "kAudioDevicePropertyNominalSampleRate") ?? tapSampleRate
        var outputLayout = aggregate.bufferChannelCounts(scope: kAudioObjectPropertyScopeOutput) ?? []
        var readinessAttempts = 0
        while outputLayout.reduce(0, +) == 0, readinessAttempts < 20 {
            usleep(50_000)
            readinessAttempts += 1
            outputLayout = aggregate.bufferChannelCounts(scope: kAudioObjectPropertyScopeOutput) ?? []
        }
        guard let outputChannels = outputLayout.first, outputLayout.reduce(0, +) > 0 else {
            log("mix bus: aggregate has no output streams \(outputLayout), bus not created")
            teardown()
            return false
        }
        let realtime = RealtimeState(
            sampleRate: sampleRate > 0 ? sampleRate : tapSampleRate,
            slots: slots,
            outputChannels: outputChannels,
            outputBufferCount: max(1, outputLayout.count),
            masterGain: masterGain,
            sleepGain: sleepGain,
            nightEnabled: nightEnabled,
            ceiling: ceiling,
            nightSeed: nightSeed
        )
        state = realtime

        var proc: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregate, nil) { _, input, _, output, _ in
            realtime.render(input: input, output: output)
        }
        guard check(status, "AudioDeviceCreateIOProcIDWithBlock(Hub)"), let proc else { teardown(); return false }
        procID = proc

        disableHardwareInputStreams(tapBufferCount: bufferOffset)
        addFormatListeners()

        guard check(AudioDeviceStart(aggregate, proc), "AudioDeviceStart(Hub)") else { teardown(); return false }
        log("mix bus started (aggregate \(aggregate), \(tapIDs.count) taps, \(Int(sampleRate)) Hz, output \(outputLayout), BT \(isBluetooth), slots: \(slotDescriptions.joined(separator: "; ")))")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.logHealth(for: realtime) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.logHealth(for: realtime) }
        return true
    }

    private func logHealth(for realtime: RealtimeState) {
        guard state === realtime else { return }
        let frames = realtime.renderedFrames.load(ordering: .relaxed)
        let mismatches = realtime.layoutMismatches.load(ordering: .relaxed)
        var slotReports: [String] = []
        for (index, slot) in realtime.slots.enumerated() {
            let name = index < apps.count ? apps[index].name : "slot \(index)"
            slotReports.append(String(format: "%@ %d ch %@ gain %.2f input peak %.4f RMS %.1f dBFS", name, slot.channels, slot.interleaved ? "interleaved" : "non-interleaved", slot.gain.load(ordering: .relaxed), slot.inputPeak.load(ordering: .relaxed), 10 * log10(Double(max(slot.meanSquare.load(ordering: .relaxed), 1e-12)))))
            slot.inputPeak.store(0, ordering: .relaxed)
        }
        let ceilingValue = realtime.ceiling.load(ordering: .relaxed)
        let summary = String(format: "output peak %.4f, output RMS %.1f dBFS, master gain %.2f, night mode %@, cap %.1f dB", realtime.outputPeak.load(ordering: .relaxed), 10 * log10(Double(max(realtime.outputMeanSquare.load(ordering: .relaxed), 1e-12))), realtime.masterGain.load(ordering: .relaxed), realtime.nightEnabled.load(ordering: .relaxed) ? "on" : "off", 20 * log10(Double(max(ceilingValue, 1e-6))))
        realtime.outputPeak.store(0, ordering: .relaxed)
        let layout = "\(realtime.slots.count) taps, input buffers \(realtime.observedInputBuffers.load(ordering: .relaxed)), output buffers \(realtime.observedOutputBuffers.load(ordering: .relaxed)), output channels \(realtime.observedOutputChannels.load(ordering: .relaxed)), slots: \(slotReports.joined(separator: "; ")), \(summary)"
        if mismatches > 0 && frames == 0 {
            log("mix bus: IO block does not match the expected layout (\(mismatches)x), output is silent, bus is being torn down: \(layout)")
            teardown()
        } else if mismatches > 0 {
            log("mix bus: IO block does not match the expected layout (\(mismatches)x): \(layout)")
        } else if frames == 0 {
            log("mix bus: IO block rendered no frames in 1 s: \(layout)")
        } else {
            log("mix bus: IO block running, \(frames) frames in 1 s, \(layout)")
        }
    }

    func teardown() {
        removeFormatListeners()
        if aggregateID.isValid, let proc = procID {
            check(AudioDeviceStop(aggregateID, proc), "AudioDeviceStop(Hub)")
            check(AudioDeviceDestroyIOProcID(aggregateID, proc), "AudioDeviceDestroyIOProcID(Hub)")
        }
        procID = nil
        if aggregateID.isValid {
            check(AudioHardwareDestroyAggregateDevice(aggregateID), "AudioHardwareDestroyAggregateDevice(Hub)")
            aggregateID = unknownObject
        }
        for tap in tapIDs where tap.isValid {
            check(AudioHardwareDestroyProcessTap(tap), "AudioHardwareDestroyProcessTap(\(tap))")
        }
        tapIDs.removeAll()
        tapDescriptions.removeAll()
        if state != nil { log("mix bus torn down") }
        state = nil
    }

    private func disableHardwareInputStreams(tapBufferCount: Int) {
        guard let proc = procID else { return }
        let inputCount = aggregateID.streamCount(scope: kAudioObjectPropertyScopeInput)
        let used = min(tapBufferCount, inputCount)
        guard inputCount > used, used > 0 else { return }

        let headerSize = MemoryLayout<UnsafeMutableRawPointer>.size + MemoryLayout<UInt32>.size
        let totalSize = headerSize + inputCount * MemoryLayout<UInt32>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: totalSize, alignment: MemoryLayout<UnsafeMutableRawPointer>.alignment)
        defer { raw.deallocate() }
        raw.storeBytes(of: unsafeBitCast(proc, to: UnsafeMutableRawPointer.self), as: UnsafeMutableRawPointer.self)
        raw.storeBytes(of: UInt32(inputCount), toByteOffset: MemoryLayout<UnsafeMutableRawPointer>.size, as: UInt32.self)
        for i in 0..<inputCount {
            let isUsed: UInt32 = i >= inputCount - used ? 1 : 0
            raw.storeBytes(of: isUsed, toByteOffset: headerSize + i * MemoryLayout<UInt32>.size, as: UInt32.self)
        }
        var address = propertyAddress(kAudioDevicePropertyIOProcStreamUsage, scope: kAudioObjectPropertyScopeInput)
        if check(AudioObjectSetPropertyData(aggregateID, &address, 0, nil, UInt32(totalSize), raw), "AudioObjectSetPropertyData(kAudioDevicePropertyIOProcStreamUsage)") {
            log("mix bus: disabled \(inputCount - used) hardware input streams")
        }
    }

    private func addFormatListeners() {
        for tap in tapIDs {
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onFormatChanged?() }
            if check(AudioObjectAddPropertyListenerBlock(tap, &formatAddress, .main, block), "AudioObjectAddPropertyListenerBlock(kAudioTapPropertyFormat)") {
                formatListeners[tap] = block
            }
        }
    }

    private func removeFormatListeners() {
        for (tap, block) in formatListeners where tap.isValid {
            let status = AudioObjectRemovePropertyListenerBlock(tap, &formatAddress, .main, block)
            if status != OSStatus(kAudioHardwareBadObjectError) {
                check(status, "AudioObjectRemovePropertyListenerBlock(kAudioTapPropertyFormat)")
            }
        }
        formatListeners.removeAll()
    }
}
