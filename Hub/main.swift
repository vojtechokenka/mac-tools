import AppKit
import AudioToolbox
import CoreAudio

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[Hub] " + message + "\n").utf8))
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private let monitor = ProcessMonitor()
    private var bus: MixBus?
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let rightMenu = NSMenu()
    private let nightItem = NSMenuItem()
    private var nightRow: NightRow!
    private let noteItem = NSMenuItem()
    private var meterViews: [String: LevelSlider] = [:]
    private var meterTimer: Timer?
    private static let meterInterval = 0.05
    private var outputVolumeDBValue = 0.0
    private var volumeUnreadable = false
    private let emptyItem = NSMenuItem()
    private let audioHeaderItem = NSMenuItem()
    private let sleepItem = NSMenuItem()
    private var sleepRow: DurationRow!
    private let sleepMacItem = NSMenuItem(title: "Sleep Mac when timer ends", action: nil, keyEquivalent: "")
    private static let sleepMinutes: [Double] = [15, 30, 60, 90]
    private static let sleepFadeSeconds = 120.0
    private var sleepDeadline: Date?
    private var sleepActivity: NSObjectProtocol?
    private var sleepMuted = false
    private var sleepTimer: Timer?
    private var sleepRampTimer: Timer?
    private var sleepGainValue: Float = 1
    private var statusText = ""
    private var volumeLabels: [String: NSTextField] = [:]
    private var menuIsOpen = false
    private var trackingBundleID: String?
    private var outputDevice = unknownObject
    private var defaultDeviceAddress = propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
    private var defaultDeviceListener: AudioObjectPropertyListenerBlock?
    private var sampleRateAddress = propertyAddress(kAudioDevicePropertyNominalSampleRate)
    private var sampleRateListener: AudioObjectPropertyListenerBlock?
    private var sampleRateDevice = unknownObject
    private var outputVolumeAddresses: [AudioObjectPropertyAddress] = []
    private var outputVolumeListener: AudioObjectPropertyListenerBlock?
    private var outputVolumeDevice = unknownObject
    private var volumeFallbackLoggedDevice = unknownObject
    private var currentCeiling: Float = 1
    private var pendingRebuild: DispatchWorkItem?
    private var pendingRebuildDeviceGone = false
    private var signalSources: [DispatchSourceSignal] = []
    private var shutdownDone = false
    private let rowWidth: CGFloat = 280

    private let dimmer = GammaDimmer()
    private let brightnessKeys = BrightnessKeys()
    private let dimItem = NSMenuItem()
    private var dimRow: BrightnessRow!
    private var dimWatchdog: Timer?
    private let dimKey = "dimLevel"
    private let dimStep = 0.05

    private let awake = AwakeSession()
    private let awakeItem = NSMenuItem()
    private var awakeRow: DurationRow!

    private static let legacyBundleIDs = ["cz.vojtechokenka.mixer", "cz.vojtechokenka.dimmer", "cz.vojtechokenka.coffeein"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let legacyApps = terminateLegacyApps()
        migrateSettingsIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
        menu.delegate = self
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let permissions = NSMenuItem(title: "System audio permission…", action: #selector(openPermissions), keyEquivalent: "")
        permissions.target = self
        rightMenu.addItem(permissions)
        let accessibility = NSMenuItem(title: "Open Accessibility settings…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibility.target = self
        rightMenu.addItem(accessibility)
        sleepMacItem.target = self
        sleepMacItem.action = #selector(toggleSleepMac)
        sleepMacItem.state = sleepMacAfterTimer ? .on : .off
        rightMenu.addItem(sleepMacItem)
        rightMenu.addItem(.separator())
        rightMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        setupFixedItems()
        rebuildMenu()

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(macDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(macWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(awakeMacDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reapplyGammaAfterEvent), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reapplyGammaAfterEvent), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reapplyGammaAfterEvent), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reapplyGammaAfterEvent), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        installSignalHandlers()

        waitForLegacyApps(legacyApps)
        setDimLevel(defaults.double(forKey: dimKey))
        dimWatchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.dimmer.reapplyIfReset()
        }

        refreshOutputDevice()
        installDefaultDeviceListener()
        monitor.onChange = { [weak self] apps in self?.reconcile(apps) }
        monitor.start()

        brightnessKeys.onStep = { [weak self] delta in
            guard let self else { return }
            self.setDimLevel(self.dimmer.level + Double(delta) * self.dimStep)
        }
        brightnessKeys.registerHotKeys()
        brightnessKeys.installBrightnessTapWhenTrusted()

        awake.onChange = { [weak self] in self?.syncAwakeControls() }
        syncAwakeControls()
        log("started, output device \(outputDevice)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    private func shutdown() {
        guard !shutdownDone else { return }
        shutdownDone = true
        cancelSleepTimer(reason: "app quit")
        awake.shutdown()
        dimWatchdog?.invalidate()
        dimWatchdog = nil
        monitor.stop()
        removeSampleRateListener()
        removeOutputVolumeListener()
        if let block = defaultDeviceListener {
            check(AudioObjectRemovePropertyListenerBlock(systemObject, &defaultDeviceAddress, .main, block), "AudioObjectRemovePropertyListenerBlock(kAudioHardwarePropertyDefaultOutputDevice)")
            defaultDeviceListener = nil
        }
        bus?.teardown()
        bus = nil
        dimmer.restore()
        log("quit, mix bus torn down, gamma restored")
    }

    private func terminateLegacyApps() -> [NSRunningApplication] {
        var apps: [NSRunningApplication] = []
        for id in Self.legacyBundleIDs {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
                log("old app \(id) is running, quitting it")
                app.terminate()
                apps.append(app)
            }
        }
        return apps
    }

    private func waitForLegacyApps(_ apps: [NSRunningApplication]) {
        guard !apps.isEmpty else { return }
        let deadline = Date().addingTimeInterval(2)
        let running = { apps.filter { kill($0.processIdentifier, 0) == 0 } }
        while Date() < deadline, !running().isEmpty {
            usleep(100_000)
        }
        let remaining = running().compactMap(\.bundleIdentifier)
        log(remaining.isEmpty ? "old apps quit" : "old apps still running: \(remaining.joined(separator: ", "))")
    }

    private func migrateSettingsIfNeeded() {
        guard !defaults.bool(forKey: "migratedV1") else { return }
        var migrated: [String] = []
        if let mixer = UserDefaults(suiteName: "cz.vojtechokenka.mixer") {
            for (key, value) in mixer.dictionaryRepresentation() where key.hasPrefix("volume.") {
                defaults.set(value, forKey: key)
                migrated.append(key)
            }
            for key in ["nightMode", "nightCapDB", "sleepMacAfterTimer"] {
                guard let value = mixer.object(forKey: key) else { continue }
                defaults.set(value, forKey: key)
                migrated.append(key)
            }
        }
        if let dimmerDefaults = UserDefaults(suiteName: "cz.vojtechokenka.dimmer"), let value = dimmerDefaults.object(forKey: dimKey) {
            defaults.set(value, forKey: dimKey)
            migrated.append(dimKey)
        }
        defaults.set(true, forKey: "migratedV1")
        log(migrated.isEmpty ? "settings migration: nothing to import" : "settings migration: \(migrated.joined(separator: ", "))")
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                self?.shutdown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func refreshOutputDevice() {
        outputDevice = systemObject.readValue(kAudioHardwarePropertyDefaultOutputDevice, initial: unknownObject, name: "kAudioHardwarePropertyDefaultOutputDevice") ?? unknownObject
        installSampleRateListener(on: outputDevice)
        installOutputVolumeListener(on: outputDevice)
        recomputeCeiling()
    }

    private func installDefaultDeviceListener() {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            log("default output device changed")
            self.bus?.state?.masterGain.store(0, ordering: .relaxed)
            self.refreshOutputDevice()
            self.scheduleRebuild(deviceGone: true)
        }
        if check(AudioObjectAddPropertyListenerBlock(systemObject, &defaultDeviceAddress, .main, block), "AudioObjectAddPropertyListenerBlock(kAudioHardwarePropertyDefaultOutputDevice)") {
            defaultDeviceListener = block
        }
    }

    private func installSampleRateListener(on device: AudioDeviceID) {
        guard device != sampleRateDevice else { return }
        removeSampleRateListener()
        guard device.isValid else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            log("output device sample rate changed")
            self?.scheduleRebuild(deviceGone: true)
        }
        if check(AudioObjectAddPropertyListenerBlock(device, &sampleRateAddress, .main, block), "AudioObjectAddPropertyListenerBlock(kAudioDevicePropertyNominalSampleRate)") {
            sampleRateListener = block
            sampleRateDevice = device
        }
    }

    private func removeSampleRateListener() {
        guard let block = sampleRateListener, sampleRateDevice.isValid else { return }
        let status = AudioObjectRemovePropertyListenerBlock(sampleRateDevice, &sampleRateAddress, .main, block)
        if status != OSStatus(kAudioHardwareBadObjectError) {
            check(status, "AudioObjectRemovePropertyListenerBlock(kAudioDevicePropertyNominalSampleRate)")
        }
        sampleRateListener = nil
        sampleRateDevice = unknownObject
    }

    private func installOutputVolumeListener(on device: AudioDeviceID) {
        guard device != outputVolumeDevice else { return }
        removeOutputVolumeListener()
        guard device.isValid else { return }
        var addresses = [propertyAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 0)]
        if device.hasProperty(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 1) {
            addresses.append(propertyAddress(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: 1))
        }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.recomputeCeiling() }
        var installed: [AudioObjectPropertyAddress] = []
        for var address in addresses {
            if check(AudioObjectAddPropertyListenerBlock(device, &address, .main, block), "AudioObjectAddPropertyListenerBlock(kAudioDevicePropertyVolumeScalar element \(address.mElement))") {
                installed.append(address)
            }
        }
        guard !installed.isEmpty else { return }
        outputVolumeListener = block
        outputVolumeAddresses = installed
        outputVolumeDevice = device
    }

    private func removeOutputVolumeListener() {
        if let block = outputVolumeListener, outputVolumeDevice.isValid {
            for var address in outputVolumeAddresses {
                let status = AudioObjectRemovePropertyListenerBlock(outputVolumeDevice, &address, .main, block)
                if status != OSStatus(kAudioHardwareBadObjectError) {
                    check(status, "AudioObjectRemovePropertyListenerBlock(kAudioDevicePropertyVolumeScalar element \(address.mElement))")
                }
            }
        }
        outputVolumeListener = nil
        outputVolumeAddresses.removeAll()
        outputVolumeDevice = unknownObject
    }

    private func plausibleVolumeDB(_ value: Float32) -> Double? {
        let db = Double(value)
        guard db.isFinite, db >= -120, db <= 20 else { return nil }
        return db
    }

    private func readOutputVolumeDB() -> Double? {
        let device = outputDevice
        guard device.isValid else { return nil }
        let transport = device.readValue(kAudioDevicePropertyTransportType, initial: UInt32(0), name: "kAudioDevicePropertyTransportType") ?? 0
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE {
            if volumeFallbackLoggedDevice != device {
                volumeFallbackLoggedDevice = device
                log("output is Bluetooth, device volume is not counted in the cap (applies to full scale)")
            }
            return nil
        }
        let scope = kAudioObjectPropertyScopeOutput
        for element in [0, 1] as [AudioObjectPropertyElement] where device.hasProperty(kAudioDevicePropertyVolumeDecibels, scope: scope, element: element) {
            if let raw = device.readValue(kAudioDevicePropertyVolumeDecibels, scope: scope, element: element, initial: Float32(0), name: "kAudioDevicePropertyVolumeDecibels element \(element)") {
                if let db = plausibleVolumeDB(raw) { return db }
                log("volume in dB from element \(element) is nonsensical (\(raw)), ignoring")
            }
        }
        for element in [0, 1] as [AudioObjectPropertyElement] where device.hasProperty(kAudioDevicePropertyVolumeScalar, scope: scope, element: element) {
            guard let scalar = device.readValue(kAudioDevicePropertyVolumeScalar, scope: scope, element: element, initial: Float32(0), name: "kAudioDevicePropertyVolumeScalar element \(element)"), scalar.isFinite, scalar >= 0, scalar <= 1 else { continue }
            if device.hasProperty(kAudioDevicePropertyVolumeScalarToDecibels, scope: scope, element: element),
               let raw = device.readValue(kAudioDevicePropertyVolumeScalarToDecibels, scope: scope, element: element, initial: scalar, name: "kAudioDevicePropertyVolumeScalarToDecibels element \(element)"),
               let db = plausibleVolumeDB(raw) {
                return db
            }
            return 20 * log10(Double(max(scalar, 1e-4)))
        }
        if volumeFallbackLoggedDevice != device {
            volumeFallbackLoggedDevice = device
            log("cannot read volume of output device \(device), assuming 0 dB")
        }
        return nil
    }

    private func recomputeCeiling() {
        let readable = readOutputVolumeDB()
        volumeUnreadable = outputDevice.isValid && readable == nil
        let volumeDB = readable ?? 0
        outputVolumeDBValue = volumeDB
        syncVolumeNote()
        let capDB = nightCapDB
        let ceiling = Float(min(1, pow(10, (capDB - volumeDB) / 20)))
        bus?.state?.ceiling.store(ceiling, ordering: .relaxed)
        guard ceiling != currentCeiling else { return }
        currentCeiling = ceiling
        log(String(format: "effective cap %.1f dB (limit %.0f dB, output volume %.1f dB)", 20 * log10(Double(max(ceiling, 1e-6))), capDB, volumeDB))
    }

    private func scheduleRebuild(deviceGone: Bool) {
        if deviceGone { pendingRebuildDeviceGone = true }
        pendingRebuild?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.performPendingRebuild() }
        pendingRebuild = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private func performPendingRebuild() {
        pendingRebuild = nil
        let deviceGone = pendingRebuildDeviceGone
        pendingRebuildDeviceGone = false
        let playing = playingApps()
        if playing.isEmpty {
            bus?.teardown()
            bus = nil
            return
        }
        log("rebuilding mix bus")
        replaceBus(apps: playing, keepOldOnFailure: !deviceGone)
    }

    private func playingApps() -> [AudioApp] {
        monitor.apps.filter(\.isPlaying).sorted { $0.bundleID < $1.bundleID }
    }

    private func reconcile(_ apps: [AudioApp]) {
        let playing = playingApps()
        if playing.isEmpty {
            bus?.teardown()
            bus = nil
        } else if let bus, bus.isActive, bus.requestedApps.map(\.bundleID) == playing.prefix(RealtimeState.maxSlots).map(\.bundleID), bus.requestedApps.map(\.processObjectIDs) == playing.prefix(RealtimeState.maxSlots).map(\.processObjectIDs) {
        } else {
            replaceBus(apps: playing, keepOldOnFailure: true)
        }
        if menuIsOpen { updateOpenMenu() }
    }

    private func makeBus(for apps: [AudioApp]) -> MixBus {
        let bus = MixBus(apps: apps)
        bus.onFormatChanged = { [weak self] in
            log("tap format changed")
            self?.scheduleRebuild(deviceGone: false)
        }
        return bus
    }

    private func replaceBus(apps: [AudioApp], keepOldOnFailure: Bool) {
        let old = bus
        let oldAlive = old?.isActive == true
        let fresh = makeBus(for: apps)
        var nightSeed: (levelerDB: Float, compDB: Float)?
        if oldAlive, let oldState = old?.state, oldState.nightPrimed.load(ordering: .relaxed) {
            nightSeed = (oldState.levelerDB.load(ordering: .relaxed), oldState.compDB.load(ordering: .relaxed))
        }
        if startBus(fresh, silent: oldAlive, nightSeed: nightSeed) {
            bus = fresh
            old?.teardown()
            fresh.state?.masterGain.store(1, ordering: .relaxed)
            return
        }
        fresh.teardown()
        guard let old else { return }
        if !keepOldOnFailure || !oldAlive {
            old.teardown()
            bus = nil
            log("old mix bus torn down, apps play unmodified")
        } else {
            log("old mix bus stays in operation")
        }
    }

    @discardableResult
    private func startBus(_ bus: MixBus, silent: Bool = false, nightSeed: (levelerDB: Float, compDB: Float)? = nil) -> Bool {
        let gains = bus.requestedApps.map { Self.gain(forPercent: volume(for: $0.bundleID)) }
        let built = bus.build(
            outputDevice: outputDevice,
            gains: gains,
            masterGain: silent ? 0 : 1,
            sleepGain: sleepGainValue,
            nightEnabled: nightMode,
            ceiling: currentCeiling,
            nightSeed: nightSeed
        )
        if !built { log("creating mix bus failed") }
        return built
    }

    private var nightMode: Bool { defaults.bool(forKey: "nightMode") }

    private var sleepMacAfterTimer: Bool {
        guard defaults.object(forKey: "sleepMacAfterTimer") != nil else { return true }
        return defaults.bool(forKey: "sleepMacAfterTimer")
    }

    private var nightCapDB: Double {
        guard defaults.object(forKey: "nightCapDB") != nil else { return -30 }
        return min(max(defaults.double(forKey: "nightCapDB").rounded(), -60), 0)
    }

    private func volume(for bundleID: String) -> Double {
        guard defaults.object(forKey: "volume.\(bundleID)") != nil else { return 100 }
        return min(max(defaults.double(forKey: "volume.\(bundleID)"), 0), 150)
    }

    static func gain(forPercent pct: Double) -> Float {
        let unit = pct / 100
        return Float(pct <= 100 ? unit * unit : unit)
    }

    static func capText(_ db: Double) -> String {
        db < 0 ? "\u{2212}\(Int(-db)) dB" : "0 dB"
    }

    private static let iconSVG = "<svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"24\" height=\"24\" fill=\"white\" fill-opacity=\"0.25\"/><path transform=\"translate(12 12) scale(0.72) translate(-12 -12) scale(0.025) translate(0 960)\" fill=\"white\" d=\"M160-160v-320h160v320H160Zm240 0v-640h160v640H400Zm240 0v-440h160v440H640Z\"/></svg>"

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(data: Data(iconSVG.utf8)) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Hub"
        return image
    }


    private func setupFixedItems() {
        let emptyContainer = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 30))
        let emptyLabel = NSTextField(labelWithString: "Nothing is playing")
        emptyLabel.font = .menuFont(ofSize: 13)
        emptyLabel.textColor = .disabledControlTextColor
        emptyLabel.frame = NSRect(x: 16, y: 6, width: rowWidth - 32, height: 18)
        emptyContainer.addSubview(emptyLabel)
        emptyItem.view = emptyContainer

        audioHeaderItem.view = HeaderRow(width: rowWidth, icon: SectionIcon.speaker, title: "Audio")

        nightRow = NightRow(width: rowWidth)
        nightRow.toggle.target = self
        nightRow.toggle.action = #selector(toggleNightMode)
        nightRow.slider.onChange = { [weak self] value, _ in self?.capChanged(value) }
        nightItem.view = nightRow

        let noteContainer = NSView(frame: NSRect(x: 0, y: 0, width: rowWidth, height: 44))
        let noteLabel = NSTextField(wrappingLabelWithString: "This device doesn't report its volume: the cap and meter are relative to full scale — keep the headphone volume steady")
        noteLabel.font = .systemFont(ofSize: 11)
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.isSelectable = false
        noteLabel.maximumNumberOfLines = 3
        noteLabel.frame = NSRect(x: 16, y: 2, width: rowWidth - 32, height: 40)
        noteContainer.addSubview(noteLabel)
        noteItem.view = noteContainer

        sleepRow = DurationRow(width: rowWidth, icon: SectionIcon.clock, title: "Sleep timer", buttonTitle: "Start")
        sleepRow.hours.value = defaults.object(forKey: "sleepHours") as? Int ?? 0
        sleepRow.minutes.value = defaults.object(forKey: "sleepMinutes") as? Int ?? 30
        sleepRow.onChange = { [weak self] in
            guard let self else { return }
            self.defaults.set(self.sleepRow.hours.value, forKey: "sleepHours")
            self.defaults.set(self.sleepRow.minutes.value, forKey: "sleepMinutes")
            self.sleepRow.button.isEnabled = self.sleepRow.totalMinutes > 0
        }
        sleepRow.onButton = { [weak self] in self?.sleepButtonClicked() }
        sleepItem.view = sleepRow

        dimRow = BrightnessRow(width: rowWidth)
        dimRow.slider.onChange = { [weak self] value, _ in self?.setDimLevel((100 - value) / 100) }
        dimItem.view = dimRow

        awakeRow = DurationRow(width: rowWidth, icon: SectionIcon.mug, title: "Stay awake", buttonTitle: "Stay awake")
        awakeRow.hours.value = defaults.object(forKey: "awakeHours") as? Int ?? 0
        awakeRow.minutes.value = defaults.object(forKey: "awakeMinutes") as? Int ?? 30
        awakeRow.onChange = { [weak self] in
            guard let self else { return }
            self.defaults.set(self.awakeRow.hours.value, forKey: "awakeHours")
            self.defaults.set(self.awakeRow.minutes.value, forKey: "awakeMinutes")
            self.syncAwakeControls()
        }
        awakeRow.onButton = { [weak self] in self?.awakeButtonClicked() }
        awakeItem.view = awakeRow

        syncNightControls()
        syncSleepControls()
    }

    private func syncSleepControls() {
        let active = sleepDeadline != nil || sleepMuted
        var title = "Sleep timer"
        var value = ""
        if let deadline = sleepDeadline {
            let remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded(.up)))
            title = "Sleep in"
            value = String(format: "%d:%02d", remaining / 60, remaining % 60)
        } else if sleepMuted {
            title = "Muted"
        }
        let wasActive = sleepRow.hours.isHidden
        sleepRow.setActive(active, title: title, value: value, buttonTitle: active ? "Cancel" : "Start", buttonEnabled: active || sleepRow.totalMinutes > 0)
        if wasActive != active { relayoutMenuRows() }
        syncStatusText()
    }

    private func relayoutMenuRows() {
        for item in menu.items { if let view = item.view { view.needsLayout = true } }
        menu.update()
    }

    private func syncAwakeControls() {
        let wasActive = awakeRow.hours.isHidden
        let unlimited = awakeRow.totalMinutes == 0
        awakeRow.setActive(awake.active, title: awake.active ? "Awake for" : "Stay awake", value: awake.countdownText, buttonTitle: awake.active ? "Cancel" : (unlimited ? "Stay awake ∞" : "Stay awake"))
        if wasActive != awake.active { relayoutMenuRows() }
        syncStatusText()
    }

    private func syncStatusText() {
        var text = ""
        if let deadline = sleepDeadline {
            text = " \(max(0, Int(deadline.timeIntervalSinceNow / 60))) min"
        } else if sleepMuted {
            text = " 0 min"
        } else {
            text = awake.statusText
        }
        guard text != statusText, let button = statusItem.button else { return }
        statusText = text
        button.title = text
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.imagePosition = text.isEmpty ? .imageOnly : .imageLeading
        statusItem.length = text.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    private func setSleepGain(_ value: Float) {
        sleepGainValue = value
        bus?.state?.sleepGain.store(value, ordering: .relaxed)
    }

    private func startSleepTimer(minutes: Double) {
        if sleepActivity == nil { sleepActivity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Sleep timer") }
        if !CGPreflightPostEventAccess() {
            log("timer: requesting Accessibility permission to pause playback")
            CGRequestPostEventAccess()
        }
        sleepTimer?.invalidate()
        sleepMuted = false
        sleepDeadline = Date(timeIntervalSinceNow: minutes * 60)
        if sleepRampTimer == nil { restoreSleepGain() }
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in self?.sleepTimerTick() }
        RunLoop.main.add(timer, forMode: .common)
        sleepTimer = timer
        syncSleepControls()
        log("sleep timer started for \(Int(minutes)) min")
    }

    private func sleepTimerTick() {
        guard let deadline = sleepDeadline else { return }
        let remaining = deadline.timeIntervalSinceNow
        if remaining < -30 {
            cancelSleepTimer(reason: "missed deadline (sleep)")
            return
        }
        if remaining <= 0 {
            sleepTimerExpired()
            return
        }
        if remaining < Self.sleepFadeSeconds {
            setSleepGain(Float(remaining / Self.sleepFadeSeconds))
        }
        syncSleepControls()
    }

    private func sleepTimerExpired() {
        if let sleepActivity { ProcessInfo.processInfo.endActivity(sleepActivity) }
        sleepActivity = nil
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepDeadline = nil
        sleepMuted = true
        setSleepGain(0)
        log("sleep timer expired, mix muted")
        if playingApps().isEmpty {
            log("media pause skipped, nothing is playing")
        } else {
            postMediaPause()
        }
        if sleepMacAfterTimer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                guard let self, self.sleepMuted else { return }
                self.sleepMac()
            }
        }
        syncSleepControls()
    }

    private func cancelSleepTimer(reason: String) {
        let wasActive = sleepDeadline != nil || sleepMuted
        if let sleepActivity { ProcessInfo.processInfo.endActivity(sleepActivity) }
        sleepActivity = nil
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepDeadline = nil
        sleepMuted = false
        guard wasActive else { return }
        log("sleep timer cancelled (\(reason)), restoring audio")
        restoreSleepGain()
        syncSleepControls()
    }

    private func restoreSleepGain() {
        sleepRampTimer?.invalidate()
        let start = sleepGainValue
        guard start < 1 else { return }
        let began = Date()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = Float(min(1, Date().timeIntervalSince(began)))
            self.setSleepGain(start + (1 - start) * progress)
            if progress >= 1 {
                timer.invalidate()
                self.sleepRampTimer = nil
                log("audio restored")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        sleepRampTimer = timer
    }

    private func postMediaPause() {
        if !CGPreflightPostEventAccess() { log("media pause: missing Accessibility permission, event will most likely be ignored") }
        let keyType = 16
        for (flags, state) in [(NSEvent.ModifierFlags(rawValue: 0xA00), 0xA), (NSEvent.ModifierFlags(rawValue: 0xB00), 0xB)] {
            let data1 = (keyType << 16) | (state << 8)
            guard let event = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1), let cgEvent = event.cgEvent else {
                log("media pause: cannot create event (state \(state))")
                return
            }
            cgEvent.post(tap: .cghidEventTap)
        }
        log("media pause sent (NX_KEYTYPE_PLAY down+up)")
    }

    private func sleepMac() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["sleepnow"]
        do {
            try process.run()
            log("putting Mac to sleep (pmset sleepnow)")
        } catch {
            log("pmset sleepnow failed: \(error)")
        }
    }

    @objc private func macWillSleep() {
        guard sleepDeadline != nil else { return }
        cancelSleepTimer(reason: "Mac going to sleep")
    }

    @objc private func macDidWake() {
        guard sleepDeadline != nil || sleepMuted else { return }
        cancelSleepTimer(reason: "Mac woke up")
    }

    private func sleepButtonClicked() {
        if sleepDeadline != nil || sleepMuted {
            cancelSleepTimer(reason: "Cancel")
        } else if sleepRow.totalMinutes > 0 {
            startSleepTimer(minutes: Double(sleepRow.totalMinutes))
        }
    }

    @objc private func toggleSleepMac() {
        let enabled = !sleepMacAfterTimer
        defaults.set(enabled, forKey: "sleepMacAfterTimer")
        sleepMacItem.state = enabled ? .on : .off
        log("sleep Mac when timer ends: \(enabled ? "yes" : "no")")
    }

    private func syncNightControls() {
        let night = nightMode
        let capDB = nightCapDB
        nightRow.toggle.state = night ? .on : .off
        nightRow.slider.value = capDB
        nightRow.slider.isEnabled = night
        syncVolumeNote()
    }

    private func syncVolumeNote() {
        let wanted = nightMode && volumeUnreadable
        let noteIndex = menu.index(of: noteItem)
        if wanted, noteIndex < 0 {
            let nightIndex = menu.index(of: nightItem)
            guard nightIndex >= 0 else { return }
            menu.insertItem(noteItem, at: nightIndex + 1)
        } else if !wanted, noteIndex >= 0 {
            menu.removeItem(noteItem)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        syncAwakeControls()
        nightRow.slider.resetLevel()
        meterTick()
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: Self.meterInterval, repeats: true) { [weak self] _ in self?.meterTick() }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        trackingBundleID = nil
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func meterDB(_ meanSquare: Float) -> Double? {
        guard meanSquare >= 1e-10 else { return nil }
        return min(0, 10 * log10(Double(meanSquare)) + outputVolumeDBValue)
    }

    private func meterTick() {
        let state = bus?.state
        let capDB: Double? = nightMode ? nightCapDB : nil
        for (bundleID, meter) in meterViews {
            var meanSquare: Float = 0
            if let bus, let state, let index = bus.slotIndices[bundleID], index < state.slots.count {
                meanSquare = state.slots[index].meanSquare.load(ordering: .relaxed)
            }
            meter.showLevel(meterDB(meanSquare), capDB: capDB, interval: Self.meterInterval)
        }
        nightRow.slider.showLevel(meterDB(state?.outputMeanSquare.load(ordering: .relaxed) ?? 0), capDB: capDB, interval: Self.meterInterval)
        let shown = nightRow.slider.shownDB
        nightRow.outputLabel.stringValue = shown.isFinite ? Self.capText(shown.rounded()) : "\u{2014}"
    }

    private var audioStart: Int {
        max(0, menu.index(of: audioHeaderItem) + 1)
    }

    private func updateOpenMenu() {
        let playing = monitor.apps.filter(\.isPlaying)
        let playingIDs = Set(playing.map(\.bundleID))
        let protected = NSEvent.pressedMouseButtons != 0 ? trackingBundleID : nil
        let start = audioStart
        for item in menu.items.dropFirst(start) {
            if item.isSeparatorItem { break }
            guard let bundleID = item.representedObject as? String else { continue }
            if !playingIDs.contains(bundleID), bundleID != protected {
                menu.removeItem(item)
                volumeLabels[bundleID] = nil
                meterViews[bundleID] = nil
            }
        }
        for app in playing where volumeLabels[app.bundleID] == nil {
            if start < menu.items.count, menu.items[start] === emptyItem { menu.removeItem(emptyItem) }
            var index = start
            for item in menu.items.dropFirst(start) {
                if item.isSeparatorItem { break }
                guard item.representedObject is String, item.title.localizedCaseInsensitiveCompare(app.name) == .orderedAscending else { break }
                index += 1
            }
            menu.insertItem(makeAppRow(app), at: index)
        }
        if volumeLabels.isEmpty, start < menu.items.count, menu.items[start] !== emptyItem { menu.insertItem(emptyItem, at: start) }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        volumeLabels.removeAll()
        meterViews.removeAll()
        menu.addItem(dimItem)
        menu.addItem(.separator())
        menu.addItem(audioHeaderItem)
        let playing = monitor.apps.filter(\.isPlaying)
        if playing.isEmpty {
            menu.addItem(emptyItem)
        } else {
            for app in playing { menu.addItem(makeAppRow(app)) }
        }
        menu.addItem(.separator())
        menu.addItem(nightItem)
        menu.addItem(.separator())
        menu.addItem(awakeItem)
        menu.addItem(.separator())
        menu.addItem(sleepItem)
        syncNightControls()
        syncSleepControls()
        syncAwakeControls()
    }

    private func makeAppRow(_ app: AudioApp) -> NSMenuItem {
        let bundleID = app.bundleID
        let row = AppRow(width: rowWidth, name: app.name, icon: app.icon, percent: volume(for: bundleID))
        volumeLabels[bundleID] = row.valueLabel
        meterViews[bundleID] = row.slider
        row.slider.onChange = { [weak self, weak row] value, modifiers in
            guard let row else { return }
            self?.volumeChanged(bundleID, value: value, modifiers: modifiers, slider: row.slider)
        }

        let item = NSMenuItem()
        item.title = app.name
        item.representedObject = bundleID
        item.view = row
        return item
    }

    private func volumeChanged(_ bundleID: String, value: Double, modifiers: NSEvent.ModifierFlags, slider: LevelSlider) {
        trackingBundleID = bundleID
        var pct = value
        if !modifiers.contains(.command), pct > 100 {
            pct = 100
            slider.value = 100
        }
        defaults.set(pct, forKey: "volume.\(bundleID)")
        volumeLabels[bundleID]?.stringValue = "\(Int(pct.rounded())) %"
        if let bus, let index = bus.slotIndices[bundleID], let state = bus.state, index < state.slots.count {
            state.slots[index].gain.store(Self.gain(forPercent: pct), ordering: .relaxed)
        }
    }

    @objc private func statusItemClicked() {
        let right = NSApp.currentEvent?.type == .rightMouseUp
        statusItem.menu = right ? rightMenu : menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func toggleNightMode() {
        let night = nightRow.toggle.state == .on
        defaults.set(night, forKey: "nightMode")
        bus?.state?.nightEnabled.store(night, ordering: .relaxed)
        syncNightControls()
        recomputeCeiling()
        log("night mode \(night ? "on" : "off")")
    }

    private func capChanged(_ value: Double) {
        let capDB = min(max(value.rounded(), -60), 0)
        nightRow.slider.value = capDB
        defaults.set(capDB, forKey: "nightCapDB")
        recomputeCeiling()
    }

    @objc private func openPermissions() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    private func setDimLevel(_ value: Double) {
        dimmer.level = value
        let pct = Int((dimmer.level * 100).rounded())
        dimRow.slider.value = Double(100 - pct)
        dimRow.valueLabel.stringValue = "\(100 - pct) %"
        defaults.set(dimmer.level, forKey: dimKey)
    }

    @objc private func reapplyGammaAfterEvent() {
        dimmer.applyAll(force: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.dimmer.applyAll(force: true) }
    }

    private func awakeButtonClicked() {
        if awake.active {
            awake.stop(reason: "Cancel")
        } else {
            let minutes = Double(awakeRow.totalMinutes)
            awake.start(minutes: minutes > 0 ? minutes : nil)
        }
        syncAwakeControls()
    }

    @objc private func awakeMacDidWake() {
        awake.macDidWake()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
