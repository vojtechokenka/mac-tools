import AppKit
import AudioToolbox
import CoreAudio

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[Hub] " + message + "\n").utf8))
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let monitor = ProcessMonitor()
    private var bus: MixBus?
    private var statusItem: NSStatusItem!
    private var panel: DSPanel!
    private var panelView: HubPanelView!
    private let rightMenu = NSMenu()
    private var meterTimer: Timer?
    private static let meterInterval = 0.05
    private var outputVolumeDBValue = 0.0
    private var volumeUnreadable = false
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

    private let dimmer = GammaDimmer()
    private let brightnessKeys = BrightnessKeys()
    private let figmaPivotKey = FigmaPivotKey()
    private var dimWatchdog: Timer?
    private let dimKey = "dimLevel"
    private let dimStep = 0.05

    private let awake = AwakeSession()

    private static let legacyBundleIDs = ["cz.vojtechokenka.mixer", "cz.vojtechokenka.dimmer", "cz.vojtechokenka.coffeein"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        DS.registerFonts()
        let legacyApps = terminateLegacyApps()
        migrateSettingsIfNeeded()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.menuBarIcon()
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
        rightMenu.addItem(DSBrand.menuItem())
        rightMenu.addItem(.separator())
        rightMenu.addItem(NSMenuItem(title: "Quit Hub", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        setupPanel()

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
        figmaPivotKey.installWhenTrusted()

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
        panelView.audio.showOutput(name: outputDeviceName())
        installSampleRateListener(on: outputDevice)
        installOutputVolumeListener(on: outputDevice)
        recomputeCeiling()
    }

    private func outputDeviceName() -> String {
        guard outputDevice.isValid, let name = outputDevice.readString(kAudioObjectPropertyName, name: "kAudioObjectPropertyName"), !name.isEmpty else { return "Output" }
        return name
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
        syncAppRows()
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

    private static let iconSVG = "<svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"24\" height=\"24\" fill=\"white\" fill-opacity=\"0.25\"/><path transform=\"translate(12 12) scale(0.72) translate(-12 -12) scale(0.025) translate(0 960)\" fill=\"white\" d=\"M160-160v-320h160v320H160Zm240 0v-640h160v640H400Zm240 0v-440h160v440H640Z\"/></svg>"

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(data: Data(iconSVG.utf8)) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Hub"
        return image
    }


    private func setupPanel() {
        let view = HubPanelView()
        panelView = view
        view.brightness.slider.onChange = { [weak self] value in self?.setDimLevel((100 - value) / 100) }

        view.awake.hours.value = defaults.object(forKey: "awakeHours") as? Int ?? 0
        view.awake.minutes.value = defaults.object(forKey: "awakeMinutes") as? Int ?? 30
        view.awake.onChange = { [weak self] in
            guard let self else { return }
            self.defaults.set(self.panelView.awake.hours.value, forKey: "awakeHours")
            self.defaults.set(self.panelView.awake.minutes.value, forKey: "awakeMinutes")
            self.syncAwakeControls()
        }
        view.awake.onButton = { [weak self] in self?.awakeButtonClicked() }

        view.audio.night.onChange = { [weak self] night in self?.setNightMode(night) }
        view.audio.output.onChange = { [weak self] value in self?.capChanged(value) }
        view.audio.onVolume = { [weak self] bundleID, pct in self?.volumeChanged(bundleID, pct: pct) }
        view.audio.onVolumeCommit = { [weak self] in self?.syncAppRows() }

        view.sleep.hours.value = defaults.object(forKey: "sleepHours") as? Int ?? 0
        view.sleep.minutes.value = defaults.object(forKey: "sleepMinutes") as? Int ?? 30
        view.sleep.onChange = { [weak self] in
            guard let self else { return }
            self.defaults.set(self.panelView.sleep.hours.value, forKey: "sleepHours")
            self.defaults.set(self.panelView.sleep.minutes.value, forKey: "sleepMinutes")
            self.syncSleepControls()
        }
        view.sleep.onButton = { [weak self] in self?.sleepButtonClicked() }

        syncPanel()
        panel = DSPanel(width: HubPanelView.width, content: view)
        panel.onShow = { [weak self] in self?.panelDidShow() }
        panel.onClose = { [weak self] in self?.panelDidClose() }
        view.onResize = { [weak self] in
            guard let self, self.panel.isShown else { return }
            self.panel.sizeToContent()
        }
    }

    private func syncPanel() {
        syncAppRows()
        syncNightControls()
        syncSleepControls()
        syncAwakeControls()
    }

    private func syncSleepControls() {
        let remaining = sleepDeadline.map { max(0, Int($0.timeIntervalSinceNow.rounded(.up))) }
        panelView.showSleep(remaining: remaining, muted: sleepMuted)
        syncStatusText()
    }

    private func syncAwakeControls() {
        panelView.showAwake(active: awake.active, remaining: awake.remainingSeconds())
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
        } else if panelView.sleep.totalMinutes > 0 {
            startSleepTimer(minutes: Double(panelView.sleep.totalMinutes))
        }
    }

    @objc private func toggleSleepMac() {
        let enabled = !sleepMacAfterTimer
        defaults.set(enabled, forKey: "sleepMacAfterTimer")
        sleepMacItem.state = enabled ? .on : .off
        log("sleep Mac when timer ends: \(enabled ? "yes" : "no")")
    }

    private func syncNightControls() {
        panelView.audio.showNight(nightMode, capDB: nightCapDB)
        syncVolumeNote()
    }

    private func syncVolumeNote() {
        panelView.audio.showNote(nightMode && volumeUnreadable)
    }

    private func panelDidShow() {
        panelView.audio.resetLevels()
        meterTick()
        meterTimer?.invalidate()
        let timer = Timer(timeInterval: Self.meterInterval, repeats: true) { [weak self] _ in self?.meterTick() }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func panelDidClose() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func meterDB(_ meanSquare: Float) -> Double? {
        guard meanSquare >= 1e-10 else { return nil }
        return min(0, 10 * log10(Double(meanSquare)) + outputVolumeDBValue)
    }

    private func meterTick() {
        let state = bus?.state
        for row in panelView.audio.rows {
            var meanSquare: Float = 0
            if let bus, let state, let index = bus.slotIndices[row.bundleID], index < state.slots.count {
                meanSquare = state.slots[index].meanSquare.load(ordering: .relaxed)
            }
            let gain = Self.gain(forPercent: volume(for: row.bundleID))
            row.showLevel(meterDB(row.sourceMeanSquare(meanSquare, gain: gain, interval: Self.meterInterval)), interval: Self.meterInterval)
        }
        panelView.audio.showOutputLevel(meterDB(state?.outputMeanSquare.load(ordering: .relaxed) ?? 0), interval: Self.meterInterval)
    }

    private func syncAppRows() {
        panelView.audio.showApps(monitor.apps.filter(\.isPlaying), keepDragged: NSEvent.pressedMouseButtons != 0) { volume(for: $0) }
    }

    private func volumeChanged(_ bundleID: String, pct: Double) {
        defaults.set(pct, forKey: "volume.\(bundleID)")
        if let bus, let index = bus.slotIndices[bundleID], let state = bus.state, index < state.slots.count {
            state.slots[index].gain.store(Self.gain(forPercent: pct), ordering: .relaxed)
        }
    }

    @objc private func statusItemClicked() {
        guard let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            panel.dismiss()
            statusItem.menu = rightMenu
            button.performClick(nil)
            DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
        } else {
            if !panel.isShown { syncPanel() }
            panel.toggle(under: button)
        }
    }

    private func setNightMode(_ night: Bool) {
        defaults.set(night, forKey: "nightMode")
        bus?.state?.nightEnabled.store(night, ordering: .relaxed)
        syncNightControls()
        recomputeCeiling()
        log("night mode \(night ? "on" : "off")")
    }

    private func capChanged(_ value: Double) {
        let capDB = min(max(value.rounded(), -60), 0)
        defaults.set(capDB, forKey: "nightCapDB")
        syncNightControls()
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
        panelView.brightness.show(percent: 100 - pct)
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
            let minutes = Double(panelView.awake.totalMinutes)
            awake.start(minutes: minutes > 0 ? minutes : nil)
        }
        syncAwakeControls()
    }

    @objc private func awakeMacDidWake() {
        awake.macDidWake()
    }
}

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
    guard CommandLine.arguments.count > flag + 1 else {
        FileHandle.standardError.write(Data("usage: Hub --snapshot <directory>\n".utf8))
        exit(2)
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
    _ = NSApplication.shared
    DS.registerFonts()
    for sample in HubPanelView.Sample.allCases {
        for dark in [false, true] {
            let file = directory.appendingPathComponent("\(sample.rawValue)-\(dark ? "dark" : "light").png")
            if !DSSnapshot.write(view: HubPanelView.sample(sample), to: file, dark: dark, panel: true) { exit(1) }
        }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
