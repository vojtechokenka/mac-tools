import AppKit
import Carbon.HIToolbox

final class GammaDimmer {
    private let tableSize: UInt32 = 256
    private var applied: [CGDirectDisplayID: [CGGammaValue]] = [:]
    private var base: [CGDirectDisplayID: (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])] = [:]

    var level: Double = 0 {
        didSet { level = min(max(level, 0), 0.9); applyAll(force: false) }
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    private func readTable(_ id: CGDirectDisplayID) -> (r: [CGGammaValue], g: [CGGammaValue], b: [CGGammaValue])? {
        var r = [CGGammaValue](repeating: 0, count: Int(tableSize))
        var g = r, b = r
        var sampleCount: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, tableSize, &r, &g, &b, &sampleCount) == .success, sampleCount > 0 else { return nil }
        let n = Int(sampleCount)
        return (Array(r.prefix(n)), Array(g.prefix(n)), Array(b.prefix(n)))
    }

    private func refreshBase() {
        CGDisplayRestoreColorSyncSettings()
        base.removeAll()
        for id in onlineDisplays() {
            if let table = readTable(id) { base[id] = table }
        }
    }

    func applyAll(force: Bool) {
        let ids = onlineDisplays()
        if force || base.isEmpty || !Set(ids).isSubset(of: Set(base.keys)) { refreshBase() }
        applied.removeAll()
        guard level > 0 else { CGDisplayRestoreColorSyncSettings(); return }
        let factor = CGGammaValue(1 - level)
        for id in ids {
            guard let base = base[id] else { continue }
            let r = base.r.map { $0 * factor }
            let g = base.g.map { $0 * factor }
            let b = base.b.map { $0 * factor }
            if CGSetDisplayTransferByTable(id, UInt32(r.count), r, g, b) == .success {
                applied[id] = r
            }
        }
    }

    func reapplyIfReset() {
        guard level > 0 else { return }
        let ids = onlineDisplays()
        let drifted = Set(ids) != Set(applied.keys) || ids.contains { id in
            guard let current = readTable(id)?.r, let expected = applied[id], current.count == expected.count else { return true }
            return zip(current, expected).contains { abs($0 - $1) > 0.002 }
        }
        if drifted { applyAll(force: true) }
    }

    func restore() {
        CGDisplayRestoreColorSyncSettings()
    }
}

final class BrightnessKeys {
    var onStep: ((Int) -> Void)?
    private var hotKeys: [EventHotKeyRef?] = []
    private var brightnessTap: CFMachPort?
    private var trustPoll: Timer?

    func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let keys = Unmanaged<BrightnessKeys>.fromOpaque(userData!).takeUnretainedValue()
            keys.handleHotKey(id: hk.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)

        let arrowMods = UInt32(controlKey | optionKey | cmdKey)
        let signature = OSType(0x444D4D52)
        for (id, key, mods) in [(UInt32(1), kVK_UpArrow, arrowMods), (UInt32(2), kVK_DownArrow, arrowMods), (UInt32(1), kVK_F2, UInt32(cmdKey)), (UInt32(2), kVK_F1, UInt32(cmdKey))] {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(key), mods, EventHotKeyID(signature: signature, id: id), GetApplicationEventTarget(), 0, &ref)
            if status != noErr { log("RegisterEventHotKey \(key) failed: \(status)") }
            hotKeys.append(ref)
        }
    }

    fileprivate func handleHotKey(id: UInt32) {
        switch id {
        case 1: onStep?(-1)
        case 2: onStep?(1)
        default: break
        }
    }

    func installBrightnessTapWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            installBrightnessTap()
            return
        }
        log("missing Accessibility permission, ⌘ + brightness keys do not work yet")
        trustPoll = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.trustPoll = nil
            self?.installBrightnessTap()
        }
    }

    private func installBrightnessTap() {
        guard brightnessTap == nil else { return }
        let mask = CGEventMask(1 << 14)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let keys = Unmanaged<BrightnessKeys>.fromOpaque(userInfo).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = keys.brightnessTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            return keys.handleSystemDefined(event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            log("could not create event tap for brightness keys")
            return
        }
        brightnessTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("⌘ + brightness keys active")
    }

    fileprivate func handleSystemDefined(_ cgEvent: CGEvent) -> Bool {
        guard let event = NSEvent(cgEvent: cgEvent), event.subtype.rawValue == 8 else { return false }
        let keyType = (event.data1 >> 16) & 0xFFFF
        guard keyType == 2 || keyType == 3 else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard modifiers == [.command] else { return false }
        let isDown = ((event.data1 >> 8) & 0xFF) == 0xA
        if isDown { onStep?(keyType == 3 ? 1 : -1) }
        return true
    }
}
