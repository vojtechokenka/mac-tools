import AppKit

struct MeterLevel {
    static let floorDB = -60.0
    private(set) var shownDB: Double = -.infinity

    var fraction: CGFloat { shownDB.isFinite ? CGFloat((shownDB - Self.floorDB) / -Self.floorDB) : 0 }

    mutating func reset() {
        shownDB = -.infinity
    }

    mutating func show(_ measuredDB: Double?, interval: Double) {
        var shown = shownDB
        let target = measuredDB.flatMap { $0 >= Self.floorDB ? $0 : nil } ?? -.infinity
        if target >= shown {
            shown = target
        } else {
            shown = max(target, shown - 20 * interval)
        }
        if shown < Self.floorDB { shown = -.infinity }
        shownDB = shown
    }
}

class PanelSection: NSView {
    let header: DSSectionHeader
    var onResize: (() -> Void)?

    init(icon: DSIcon, title: String) {
        header = DSSectionHeader(icon: icon, title: title)
        super.init(frame: NSRect(x: 0, y: 0, width: HubPanelView.width, height: 0))
        header.frame = NSRect(x: DS.margin, y: DS.sectionTop, width: inner, height: DSSectionHeader.height)
        addSubview(header)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    var inner: CGFloat { HubPanelView.width - 2 * DS.margin }
    var contentTop: CGFloat { DS.sectionTop + DSSectionHeader.height + DS.gap }

    func finish(at bottom: CGFloat) {
        let height = bottom + DS.sectionBottom
        guard height != frame.height else { return }
        setFrameSize(NSSize(width: frame.width, height: height))
        onResize?()
    }
}

final class BrightnessSection: PanelSection {
    let slider = DSSlider(value: 100, range: 10...100, label: "Brightness")

    init() {
        super.init(icon: .contrast, title: "Brightness")
        slider.keyboardStep = 5
        slider.frame = NSRect(x: DS.margin, y: contentTop, width: inner, height: DS.rowHeight)
        addSubview(slider)
        show(percent: 100)
        finish(at: slider.frame.maxY)
    }

    required init?(coder: NSCoder) { nil }

    func show(percent: Int) {
        slider.value = Double(percent)
        header.value = "\(percent) %"
    }
}

final class TimerSection: PanelSection {
    static let countWidth: CGFloat = 110
    let hours = DSStepper(value: 0, range: 0...23, unit: "h", label: "Hours")
    let minutes = DSStepper(value: 30, range: 0...55, step: 5, unit: "min", label: "Minutes")
    let button = DSButton("", style: .primary, fullWidth: true)
    private let status = DSLabel("", color: DS.muted)
    private let count = DSLabel("", weight: .semibold, color: DS.ink)
    private(set) var isRunning = false
    var onChange: (() -> Void)?
    var onButton: (() -> Void)?

    override init(icon: DSIcon, title: String) {
        super.init(icon: icon, title: title)
        minutes.wraps = true
        hours.onChange = { [weak self] _ in self?.onChange?() }
        minutes.onChange = { [weak self] _ in self?.onChange?() }
        button.onClick = { [weak self] in self?.onButton?() }
        count.alignment = .right
        let half = (inner - DS.gap) / 2
        hours.frame = NSRect(x: DS.margin, y: contentTop, width: half, height: DS.controlHeight)
        minutes.frame = NSRect(x: DS.margin + half + DS.gap, y: contentTop, width: half, height: DS.controlHeight)
        status.frame = NSRect(x: DS.margin, y: contentTop, width: inner - Self.countWidth - DS.gap, height: DS.rowHeight)
        count.frame = NSRect(x: DS.margin + inner - Self.countWidth, y: contentTop, width: Self.countWidth, height: DS.rowHeight)
        for view in [hours, minutes, status, count, button] { addSubview(view) }
        layoutRows()
    }

    required init?(coder: NSCoder) { nil }

    var totalMinutes: Int { hours.value * 60 + minutes.value }

    func showIdle(title: String, enabled: Bool = true) {
        button.title = title
        button.style = .primary
        button.isEnabled = enabled
        guard isRunning else { return }
        isRunning = false
        layoutRows()
    }

    func showRunning(label: String, count text: String) {
        status.text = label
        count.text = text
        button.title = "Cancel"
        button.style = .secondary
        button.isEnabled = true
        guard !isRunning else { return }
        isRunning = true
        layoutRows()
    }

    private func layoutRows() {
        hours.isHidden = isRunning
        minutes.isHidden = isRunning
        status.isHidden = !isRunning
        count.isHidden = !isRunning
        let top = contentTop + (isRunning ? DS.rowHeight : DS.controlHeight) + DS.gap
        button.frame = NSRect(x: DS.margin, y: top, width: inner, height: DS.controlHeight)
        finish(at: button.frame.maxY)
    }
}

final class AppRow {
    static let meterSeconds = 0.3
    let bundleID: String
    let icon = NSImageView()
    let label: DSLabel
    let slider: DSSlider
    private var level = MeterLevel()
    private var gainSquare: Float?

    init(app: AudioApp, percent: Double) {
        bundleID = app.bundleID
        label = DSLabel(app.name)
        slider = DSSlider(value: percent, range: 0...150, mode: .meter, label: "\(app.name) volume")
        slider.keyboardStep = 5
        icon.image = app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        showPercent(percent)
    }

    var views: [NSView] { [icon, label, slider] }

    func showPercent(_ percent: Double) {
        slider.value = percent
        slider.toolTip = "\(Int(percent.rounded())) %"
    }

    func resetLevel() {
        level.reset()
        gainSquare = nil
        slider.setLiveLevel(0)
    }

    func sourceMeanSquare(_ meanSquare: Float, gain: Float, interval: Double) -> Float {
        let target = gain * gain
        let averaged = gainSquare.map { $0 + Float(1 - exp(-interval / Self.meterSeconds)) * (target - $0) } ?? target
        gainSquare = averaged
        return gain > 0 && averaged > 0 ? meanSquare / averaged : 0
    }

    func showLevel(_ measuredDB: Double?, interval: Double) {
        level.show(measuredDB, interval: interval)
        slider.setLiveLevel(level.fraction)
    }
}

final class AudioSection: PanelSection {
    static let nameWidth: CGFloat = 126
    static let iconSize: CGFloat = 16
    static let valueWidth: CGFloat = 60
    static let noteText = "This device doesn't report its volume: the cap and meter are relative to full scale — keep the headphone volume steady"

    let outputName = DSLabel("Output")
    let output = DSSlider(value: -30, range: MeterLevel.floorDB...0, mode: .output, label: "Night mode cap")
    let night = DSToggle(label: "Night mode")
    private let nightLabel = DSLabel("Night mode")
    private let nightValue = DSLabel("", color: DS.icon)
    private let empty = DSLabel("Nothing is playing", color: DS.muted)
    private let note = DSLabel(AudioSection.noteText, size: 11, color: DS.muted)
    private(set) var rows: [AppRow] = []
    private var outputLevel = MeterLevel()
    var onVolume: ((String, Double) -> Void)?
    var onVolumeCommit: (() -> Void)?

    init() {
        super.init(icon: .volumeUp, title: "Audio")
        output.step = 1
        nightValue.alignment = .right
        note.maxLines = 0
        note.lineHeight = 14
        note.isHidden = true
        for view in [outputName, output, empty, nightLabel, nightValue, night, note] { addSubview(view) }
        layoutRows()
    }

    required init?(coder: NSCoder) { nil }

    static func capText(_ db: Double) -> String {
        db < 0 ? "\u{2212}\(Int(-db)) dB" : "0 dB"
    }

    func showOutput(name: String) {
        outputName.text = name
        outputName.toolTip = name
    }

    func showNight(_ on: Bool, capDB: Double) {
        night.isOn = on
        output.isCapped = on
        output.value = capDB
        nightValue.text = Self.capText(capDB)
        nightValue.isHidden = !on
    }

    func showNote(_ visible: Bool) {
        guard note.isHidden == visible else { return }
        note.isHidden = !visible
        layoutRows()
    }

    func showApps(_ apps: [AudioApp], keepDragged: Bool, percent: (String) -> Double) {
        let wanted = Set(apps.map(\.bundleID))
        guard apps.map(\.bundleID) != rows.map(\.bundleID) else { return }
        var next = apps.map { app in
            rows.first { $0.bundleID == app.bundleID } ?? makeRow(app, percent: percent(app.bundleID))
        }
        for (index, row) in rows.enumerated() where keepDragged && row.slider.isDragging && !wanted.contains(row.bundleID) {
            next.insert(row, at: min(index, next.count))
        }
        guard next.map(\.bundleID) != rows.map(\.bundleID) else { return }
        for row in rows where !next.contains(where: { $0 === row }) {
            for view in row.views { view.removeFromSuperview() }
        }
        rows = next
        layoutRows()
    }

    func resetLevels() {
        outputLevel.reset()
        output.setLiveLevel(0)
        for row in rows { row.resetLevel() }
    }

    func showOutputLevel(_ measuredDB: Double?, interval: Double) {
        outputLevel.show(measuredDB, interval: interval)
        var live = outputLevel.fraction
        if output.isCapped {
            let cap = output.fraction
            live = cap > 0 ? min(live / cap, 1) : (live > 0 ? 1 : 0)
        }
        output.setLiveLevel(live)
    }

    private func makeRow(_ app: AudioApp, percent: Double) -> AppRow {
        let row = AppRow(app: app, percent: percent)
        row.slider.onChange = { [weak self, weak row] value in
            guard let row else { return }
            let percent = row.slider.modifierFlags.contains(.command) ? value : min(value, 100)
            row.showPercent(percent)
            self?.onVolume?(row.bundleID, percent)
        }
        row.slider.onCommit = { [weak self] _ in self?.onVolumeCommit?() }
        for view in row.views { addSubview(view) }
        return row
    }

    private func layoutRows() {
        let left = DS.margin
        let sliderX = left + Self.nameWidth + DS.gap
        let sliderWidth = left + inner - sliderX
        let nameX = left + Self.iconSize + DS.gap
        var y = contentTop
        outputName.frame = NSRect(x: left, y: y, width: Self.nameWidth, height: DS.rowHeight)
        output.frame = NSRect(x: sliderX, y: y, width: sliderWidth, height: DS.rowHeight)
        y += DS.rowHeight + DS.gap
        empty.isHidden = !rows.isEmpty
        if rows.isEmpty {
            empty.frame = NSRect(x: left, y: y, width: inner, height: DS.rowHeight)
            y += DS.rowHeight + DS.gap
        }
        for row in rows {
            row.icon.frame = NSRect(x: left, y: y + (DS.rowHeight - Self.iconSize) / 2, width: Self.iconSize, height: Self.iconSize)
            row.label.frame = NSRect(x: nameX, y: y, width: sliderX - DS.gap - nameX, height: DS.rowHeight)
            row.slider.frame = NSRect(x: sliderX, y: y, width: sliderWidth, height: DS.rowHeight)
            y += DS.rowHeight + DS.gap
        }
        let toggleX = left + inner - DSToggle.size.width
        night.frame = NSRect(x: toggleX, y: y, width: DSToggle.size.width, height: DS.rowHeight)
        nightValue.frame = NSRect(x: toggleX - DS.gap - Self.valueWidth, y: y, width: Self.valueWidth, height: DS.rowHeight)
        nightLabel.frame = NSRect(x: left, y: y, width: nightValue.frame.minX - DS.gap - left, height: DS.rowHeight)
        y += DS.rowHeight
        if !note.isHidden {
            let height = note.height(forWidth: inner)
            note.frame = NSRect(x: left, y: y + DS.gap, width: inner, height: height)
            y += DS.gap + height
        }
        finish(at: y)
    }
}

final class HubPanelView: NSView {
    static let width: CGFloat = 300
    let brightness = BrightnessSection()
    let awake = TimerSection(icon: .coffee, title: "Stay awake")
    let audio = AudioSection()
    let sleep = TimerSection(icon: .timer, title: "Sleep timer")
    var onResize: (() -> Void)?
    private var sections: [PanelSection] { [brightness, awake, audio, sleep] }
    private var separators: [DSSeparator] = []

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 0))
        for (index, section) in sections.enumerated() {
            if index > 0 {
                let separator = DSSeparator()
                separators.append(separator)
                addSubview(separator)
            }
            section.onResize = { [weak self] in self?.layoutSections() }
            addSubview(section)
        }
        showAwake(active: false, remaining: nil)
        showSleep(remaining: nil, muted: false)
        layoutSections()
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    static func clock(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60) : String(format: "%d:%02d", minutes, seconds % 60)
    }

    func showAwake(active: Bool, remaining: Int?) {
        if active {
            awake.showRunning(label: "Awake for", count: remaining.map(Self.clock) ?? "unlimited")
        } else {
            awake.showIdle(title: awake.totalMinutes == 0 ? "Keep awake \u{221E}" : "Keep awake")
        }
    }

    func showSleep(remaining: Int?, muted: Bool) {
        if let remaining {
            sleep.showRunning(label: "Sleeping in", count: Self.clock(remaining))
        } else if muted {
            sleep.showRunning(label: "Muted", count: "")
        } else {
            sleep.showIdle(title: "Start sleep timer", enabled: sleep.totalMinutes > 0)
        }
    }

    private func layoutSections() {
        var y = DS.panelInset
        for (index, section) in sections.enumerated() {
            if index > 0 {
                separators[index - 1].frame = NSRect(x: 0, y: y, width: Self.width, height: 1)
                y += 1
            }
            section.setFrameOrigin(NSPoint(x: 0, y: y))
            y += section.frame.height
        }
        y += DS.panelInset
        guard y != frame.height else { return }
        setFrameSize(NSSize(width: Self.width, height: y))
        onResize?()
    }
}

extension HubPanelView {
    enum Sample: String, CaseIterable {
        case hub
        case timers = "hub-timers"
        case nightOff = "hub-night-off"
        case noApps = "hub-no-apps"
        case edge = "hub-edge"
    }

    private static func sampleApp(_ name: String, _ color: UInt32) -> AudioApp {
        let icon = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            DSDraw.fill(rect, radius: DS.radius, DS.rgb(color))
            return true
        }
        return AudioApp(bundleID: "sample.\(name)", name: name, icon: icon, processObjectIDs: [], isPlaying: true)
    }

    static func sample(_ sample: Sample) -> HubPanelView {
        let view = HubPanelView()
        var apps = [sampleApp("Spotify", 0x1DB954), sampleApp("Chrome", 0xE8453C), sampleApp("Figma", 0xA259FF)]
        var volumes = ["sample.Spotify": 120.0, "sample.Chrome": 67.5, "sample.Figma": 90.0]
        var levels: [CGFloat] = [0.7, 0.5, 0]
        var outputName = "MacBook Speakers"
        var night = true
        var awakeTime = (hours: 1, minutes: 30)
        var awakeState: (active: Bool, remaining: Int?) = (false, nil)
        var sleepState: (remaining: Int?, muted: Bool) = (1450, false)

        switch sample {
        case .hub:
            break
        case .timers:
            awakeState = (true, 5400)
            sleepState = (nil, false)
        case .nightOff:
            night = false
        case .noApps:
            apps = []
        case .edge:
            apps = [sampleApp("Microsoft Teams (work or school)", 0x4B53BC), sampleApp("Music", 0xFA2D48)]
            volumes = ["sample.Microsoft Teams (work or school)": 100, "sample.Music": 0]
            levels = [0.4, 0]
            outputName = "External Headphones (Bluetooth)"
            awakeTime = (0, 0)
            sleepState = (nil, true)
            view.audio.showNote(true)
        }

        view.brightness.show(percent: 62)
        view.awake.hours.value = awakeTime.hours
        view.awake.minutes.value = awakeTime.minutes
        view.showAwake(active: awakeState.active, remaining: awakeState.remaining)
        view.audio.showOutput(name: outputName)
        view.audio.showNight(night, capDB: -12)
        view.audio.showApps(apps, keepDragged: false) { volumes[$0] ?? 100 }
        view.audio.output.setLiveLevel(0.55)
        for (row, level) in zip(view.audio.rows, levels) { row.slider.setLiveLevel(level) }
        view.sleep.hours.value = 0
        view.sleep.minutes.value = 25
        view.showSleep(remaining: sleepState.remaining, muted: sleepState.muted)
        return view
    }
}
