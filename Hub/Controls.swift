import AppKit

func sectionIcon(_ paths: String) -> NSImage {
    let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"black\">\(paths)</svg>"
    let image = NSImage(data: Data(svg.utf8)) ?? NSImage(size: NSSize(width: 15, height: 15))
    image.size = NSSize(width: 15, height: 15)
    image.isTemplate = true
    return image
}

enum SectionIcon {
    static let brightness = sectionIcon("<path d=\"M12 2a10 10 0 1 0 0 20V2z\"/><path d=\"M12 2a10 10 0 0 1 0 20V2z\" opacity=\".45\"/>")
    static let speaker = sectionIcon("<path d=\"M4 9v6h4l5 4V5L8 9H4zm11.5 3a3.5 3.5 0 0 0-2-3.15v6.3a3.5 3.5 0 0 0 2-3.15zm-2-7.45v2.1a5.5 5.5 0 0 1 0 10.7v2.1a7.5 7.5 0 0 0 0-14.9z\"/>")
    static let moon = sectionIcon("<path d=\"M12.3 4.9a7.5 7.5 0 0 0 7 11.6A8.5 8.5 0 1 1 12.3 4.9z\"/>")
    static let mug = sectionIcon("<path d=\"M5 2h2v3H5zm4 0h2v3H9zm4 0h2v3h-2zm6 7h-2V8a1 1 0 0 0-1-1H4a1 1 0 0 0-1 1v10a3 3 0 0 0 3 3h8a3 3 0 0 0 3-3h2c1.103 0 2-.897 2-2v-5c0-1.103-.897-2-2-2m-2 7v-5h2l.002 5z\"/>")
    static let clock = sectionIcon("<path d=\"M12 22a10 10 0 1 1 0-20 10 10 0 0 1 0 20zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16zm1-13v5.6l3.5 2.1-1 1.7L11 13.5V7h2z\"/>")
}

final class TitleLine: NSView {
    let icon = NSImageView()
    let label = NSTextField(labelWithString: "")
    var showsIcon = true {
        didSet {
            icon.isHidden = !showsIcon
            label.frame.origin.x = showsIcon ? 23 : 0
            label.frame.size.width = bounds.width - label.frame.origin.x
        }
    }

    init(x: CGFloat, y: CGFloat, width: CGFloat, icon image: NSImage, title: String) {
        super.init(frame: NSRect(x: x, y: y, width: width, height: 18))
        icon.image = image
        icon.imageScaling = .scaleNone
        icon.contentTintColor = .labelColor
        icon.frame = NSRect(x: 0, y: 1, width: 15, height: 15)
        label.stringValue = title
        label.font = .menuFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 23, y: 0, width: width - 23, height: 18)
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }
}

struct MeterLevel {
    enum Tone { case neutral, orange, red }
    static let floorDB = -60.0
    private(set) var shownDB: Double = -.infinity
    private(set) var tone = Tone.neutral

    var fraction: CGFloat { shownDB.isFinite ? CGFloat((shownDB - Self.floorDB) / -Self.floorDB) : 0 }

    mutating func reset() {
        shownDB = -.infinity
        tone = .neutral
    }

    mutating func show(_ measuredDB: Double?, capDB: Double?, interval: Double) {
        var shown = shownDB
        let target = measuredDB.flatMap { $0 >= Self.floorDB ? $0 : nil } ?? -.infinity
        if target >= shown {
            shown = target
        } else {
            shown = max(target, shown - 20 * interval)
        }
        if shown < Self.floorDB { shown = -.infinity }
        shownDB = shown
        if let capDB, shown.isFinite, shown >= capDB {
            tone = .red
        } else if let capDB, shown.isFinite, shown >= capDB - 3 {
            tone = .orange
        } else {
            tone = .neutral
        }
    }
}

final class LevelSlider: NSView {
    enum Mode { case value, meter }
    enum KnobStyle { case filled, hollow }
    static let knobSize: CGFloat = 18
    static let tickHeight: CGFloat = 14

    var value = 0.0 { didSet { if value != oldValue { needsDisplay = true } } }
    var minValue = 0.0
    var maxValue = 100.0
    var step: Double?
    var meterFraction: CGFloat = 0 { didSet { if meterFraction != oldValue { needsDisplay = true } } }
    var meterTone = MeterLevel.Tone.neutral { didSet { if meterTone != oldValue { needsDisplay = true } } }
    var mode = Mode.value { didSet { needsDisplay = true } }
    var knobStyle = KnobStyle.filled { didSet { needsDisplay = true } }
    var ticks: [(fraction: CGFloat, label: String)] = [] { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { alphaValue = isEnabled ? 1 : 0.5 } }
    var onChange: ((Double, NSEvent.ModifierFlags) -> Void)?
    let trackHeight: CGFloat
    private(set) var level = MeterLevel()

    static func height(ticks: Bool) -> CGFloat { knobSize + (ticks ? tickHeight : 0) }

    init(x: CGFloat, y: CGFloat, width: CGFloat, trackHeight: CGFloat = 8, ticks: [(fraction: CGFloat, label: String)] = []) {
        self.trackHeight = trackHeight
        self.ticks = ticks
        super.init(frame: NSRect(x: x, y: y, width: width, height: Self.height(ticks: !ticks.isEmpty)))
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    var shownDB: Double { level.shownDB }

    func resetLevel() {
        level.reset()
        meterFraction = 0
        meterTone = level.tone
    }

    func showLevel(_ measuredDB: Double?, capDB: Double?, interval: Double) {
        level.show(measuredDB, capDB: capDB, interval: interval)
        meterFraction = level.fraction
        meterTone = level.tone
    }

    private var tickBand: CGFloat { ticks.isEmpty ? 0 : Self.tickHeight }
    private var trackCenterY: CGFloat { tickBand + Self.knobSize / 2 }
    private var knobMinX: CGFloat { Self.knobSize / 2 }
    private var knobMaxX: CGFloat { bounds.width - Self.knobSize / 2 }

    private func fraction(of value: Double) -> CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat(min(max((value - minValue) / (maxValue - minValue), 0), 1))
    }

    private func knobX(for fraction: CGFloat) -> CGFloat {
        knobMinX + (knobMaxX - knobMinX) * fraction
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: trackCenterY - trackHeight / 2, width: bounds.width, height: trackHeight)
        let radius = trackHeight / 2
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        let knobCenter = knobX(for: fraction(of: value))
        let fillWidth: CGFloat
        let fillColor: NSColor
        switch mode {
        case .value:
            fillWidth = knobCenter
            fillColor = NSColor.labelColor.withAlphaComponent(0.55)
        case .meter:
            let fraction = min(max(meterFraction, 0), 1)
            fillWidth = fraction > 0 ? knobX(for: fraction) : 0
            switch meterTone {
            case .neutral: fillColor = NSColor.labelColor.withAlphaComponent(0.38)
            case .orange: fillColor = .systemOrange
            case .red: fillColor = .systemRed
            }
        }
        if fillWidth > 0 {
            fillColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: 0, y: track.minY, width: max(fillWidth, trackHeight), height: trackHeight), xRadius: radius, yRadius: radius).fill()
        }

        if !ticks.isEmpty {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
            for tick in ticks {
                let text = NSAttributedString(string: tick.label, attributes: attributes)
                let size = text.size()
                var x = knobX(for: tick.fraction) - size.width / 2
                x = min(max(x, 0), bounds.width - size.width)
                text.draw(at: NSPoint(x: x.rounded(), y: 0))
            }
        }

        let knobRect = NSRect(x: knobCenter - Self.knobSize / 2, y: trackCenterY - Self.knobSize / 2, width: Self.knobSize, height: Self.knobSize)
        switch knobStyle {
        case .filled:
            let knob = NSBezierPath(ovalIn: knobRect.insetBy(dx: 0.25, dy: 0.25))
            NSColor.labelColor.setFill()
            knob.fill()
            NSColor.windowBackgroundColor.setStroke()
            knob.lineWidth = 0.5
            knob.stroke()
        case .hollow:
            let ring = NSBezierPath(ovalIn: knobRect.insetBy(dx: 1, dy: 1))
            NSColor.labelColor.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { apply(event) }
    override func mouseDragged(with event: NSEvent) { apply(event) }

    private func apply(_ event: NSEvent) {
        guard isEnabled, knobMaxX > knobMinX else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let fraction = min(max((x - knobMinX) / (knobMaxX - knobMinX), 0), 1)
        var next = minValue + Double(fraction) * (maxValue - minValue)
        if let step, step > 0 { next = (next / step).rounded() * step }
        next = min(max(next, minValue), maxValue)
        value = next
        onChange?(next, event.modifierFlags)
    }
}

final class PillButton: NSView {
    var title = "" { didSet { needsDisplay = true } }
    var isPrimary = true { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        let base = NSColor.labelColor
        var fill: NSColor = isPrimary ? base.withAlphaComponent(0.85) : base.withAlphaComponent(0.16)
        if !isEnabled { fill = base.withAlphaComponent(0.08) }
        else if pressed { fill = isPrimary ? base.withAlphaComponent(0.7) : base.withAlphaComponent(0.3) }
        else if hovered { fill = isPrimary ? base : base.withAlphaComponent(0.24) }
        fill.setFill()
        path.fill()
        let textColor: NSColor = !isEnabled ? .tertiaryLabelColor : (isPrimary ? .windowBackgroundColor : base)
        let label = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: textColor])
        let size = label.size()
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false; pressed = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if isEnabled { pressed = true } }
    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if isEnabled && inside { onClick?() }
    }
}

final class StepperPill: NSView {
    var value = 0 { didSet { needsDisplay = true } }
    var minValue = 0
    var maxValue = 59
    var step = 1
    var wraps = false
    var unit = ""
    var onChange: (() -> Void)?
    private var hoverSide = 0 { didSet { needsDisplay = true } }
    private var pressSide = 0 { didSet { needsDisplay = true } }
    private var repeatTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private let buttonWidth: CGFloat = 28

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        let base = NSColor.labelColor
        base.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius).fill()
        for side in [-1, 1] {
            let rect = side < 0 ? NSRect(x: 0, y: 0, width: buttonWidth, height: bounds.height) : NSRect(x: bounds.width - buttonWidth, y: 0, width: buttonWidth, height: bounds.height)
            if pressSide == side {
                base.withAlphaComponent(0.3).setFill()
            } else if hoverSide == side {
                base.withAlphaComponent(0.16).setFill()
            } else {
                continue
            }
            let clip = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
            NSGraphicsContext.saveGraphicsState()
            clip.addClip()
            rect.fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        let glyphAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .medium), .foregroundColor: base.withAlphaComponent(0.85)]
        let minus = NSAttributedString(string: "−", attributes: glyphAttributes)
        let plus = NSAttributedString(string: "+", attributes: glyphAttributes)
        minus.draw(at: NSPoint(x: (buttonWidth - minus.size().width) / 2, y: (bounds.height - minus.size().height) / 2))
        plus.draw(at: NSPoint(x: bounds.width - buttonWidth + (buttonWidth - plus.size().width) / 2, y: (bounds.height - plus.size().height) / 2))
        let label = NSAttributedString(string: "\(value) \(unit)", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .medium), .foregroundColor: base])
        let size = label.size()
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
    }

    private func side(for event: NSEvent) -> Int {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return 0 }
        if point.x < buttonWidth { return -1 }
        if point.x > bounds.width - buttonWidth { return 1 }
        return 0
    }

    private func bump(_ direction: Int) {
        var next = value + direction * step
        if next > maxValue { next = wraps ? minValue : maxValue }
        if next < minValue { next = wraps ? maxValue : minValue }
        guard next != value else { return }
        value = next
        onChange?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) { hoverSide = side(for: event) }
    override func mouseEntered(with event: NSEvent) { hoverSide = side(for: event) }
    override func mouseExited(with event: NSEvent) { hoverSide = 0; stopRepeat() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let direction = side(for: event)
        guard direction != 0 else { return }
        pressSide = direction
        bump(direction)
        repeatTimer?.invalidate()
        repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self] _ in self?.bump(direction) }
            RunLoop.main.add(self.repeatTimer!, forMode: .common)
        }
        RunLoop.main.add(repeatTimer!, forMode: .common)
    }

    override func mouseUp(with event: NSEvent) { stopRepeat() }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        pressSide = 0
    }
}

final class DurationRow: NSView {
    static let idleHeight: CGFloat = 104
    static let activeHeight: CGFloat = 72
    let title: TitleLine
    let valueLabel = NSTextField(labelWithString: "")
    let button = PillButton()
    let hours = StepperPill()
    let minutes = StepperPill()
    var onChange: (() -> Void)?
    var onButton: (() -> Void)?

    init(width: CGFloat, icon: NSImage, title: String, buttonTitle: String) {
        self.title = TitleLine(x: 16, y: Self.idleHeight - 8 - 18, width: width - 32 - 100, icon: icon, title: title)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Self.idleHeight))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - 16 - 100, y: self.title.frame.origin.y, width: 100, height: 18)
        valueLabel.isHidden = true
        button.title = buttonTitle
        button.frame = NSRect(x: 16, y: 8, width: width - 32, height: 26)
        button.onClick = { [weak self] in self?.onButton?() }
        hours.unit = "h"
        hours.maxValue = 23
        hours.frame = NSRect(x: 16, y: 44, width: 112, height: 26)
        minutes.unit = "min"
        minutes.maxValue = 55
        minutes.step = 5
        minutes.wraps = true
        minutes.frame = NSRect(x: 16 + 112 + 10, y: 44, width: 126, height: 26)
        hours.onChange = { [weak self] in self?.onChange?() }
        minutes.onChange = { [weak self] in self?.onChange?() }
        for view in [self.title, valueLabel, button, hours, minutes] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }

    var totalMinutes: Int { hours.value * 60 + minutes.value }

    func setActive(_ active: Bool, title text: String, value: String, buttonTitle: String, buttonEnabled: Bool = true) {
        title.label.stringValue = text
        title.label.textColor = active ? .secondaryLabelColor : .labelColor
        title.showsIcon = !active
        valueLabel.stringValue = value
        valueLabel.isHidden = !active
        button.title = buttonTitle
        button.isPrimary = !active
        button.isEnabled = buttonEnabled
        hours.isHidden = active
        minutes.isHidden = active
        frame.size.height = active ? Self.activeHeight : Self.idleHeight
        let titleY = frame.size.height - 8 - 18
        title.frame.origin.y = titleY
        valueLabel.frame.origin.y = titleY
    }
}

final class BrightnessRow: NSView {
    let valueLabel = NSTextField(labelWithString: "100 %")
    let slider: LevelSlider

    init(width: CGFloat) {
        slider = LevelSlider(x: 16, y: 6, width: width - 32, ticks: [(0, "10"), (CGFloat(40.0 / 90.0), "50"), (1, "100 %")])
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 64))
        let title = TitleLine(x: 16, y: 40, width: width - 32 - 70, icon: SectionIcon.brightness, title: "Brightness")
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - 16 - 60, y: 40, width: 60, height: 18)
        slider.minValue = 10
        slider.maxValue = 100
        slider.value = 100
        slider.mode = .value
        addSubview(title)
        addSubview(valueLabel)
        addSubview(slider)
    }

    required init?(coder: NSCoder) { nil }
}

final class HeaderRow: NSView {
    init(width: CGFloat, icon: NSImage, title: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 26))
        addSubview(TitleLine(x: 16, y: 4, width: width - 32, icon: icon, title: title))
    }

    required init?(coder: NSCoder) { nil }
}

final class AppRow: NSView {
    let valueLabel: NSTextField
    let slider: LevelSlider

    init(width: CGFloat, name: String, icon: NSImage?, percent: Double) {
        valueLabel = NSTextField(labelWithString: "\(Int(percent.rounded())) %")
        slider = LevelSlider(x: 16, y: 6, width: width - 32, ticks: [(0, "0"), (CGFloat(1.0 / 3.0), "50"), (CGFloat(2.0 / 3.0), "100"), (1, "150")])
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 70))
        let iconView = NSImageView(frame: NSRect(x: 16, y: 47, width: 16, height: 16))
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        let nameLabel = NSTextField(labelWithString: name)
        nameLabel.font = .menuFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.frame = NSRect(x: 38, y: 46, width: width - 38 - 80, height: 18)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: width - 76, y: 46, width: 60, height: 18)
        slider.minValue = 0
        slider.maxValue = 150
        slider.value = percent
        slider.mode = .meter
        for view in [iconView, nameLabel, valueLabel, slider] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }
}

final class NightRow: NSView {
    let toggle = NSSwitch()
    let outputLabel = NSTextField(labelWithString: "\u{2014}")
    let slider: LevelSlider

    init(width: CGFloat) {
        slider = LevelSlider(x: 16, y: 6, width: width - 32, trackHeight: 10, ticks: [(0, "\u{2212}60"), (CGFloat(1.0 / 3.0), "\u{2212}40"), (CGFloat(2.0 / 3.0), "\u{2212}20"), (1, "0 dB")])
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 92))
        let title = TitleLine(x: 16, y: 68, width: width - 32 - 60, icon: SectionIcon.moon, title: "Night mode")
        toggle.controlSize = .small
        toggle.sizeToFit()
        toggle.frame.origin = NSPoint(x: width - 16 - toggle.frame.width, y: (77 - toggle.frame.height / 2).rounded())
        let outputTitle = NSTextField(labelWithString: "Output")
        outputTitle.font = .systemFont(ofSize: 11)
        outputTitle.textColor = .secondaryLabelColor
        outputTitle.frame = NSRect(x: 16, y: 46, width: 120, height: 14)
        outputLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        outputLabel.textColor = .secondaryLabelColor
        outputLabel.alignment = .right
        outputLabel.frame = NSRect(x: width - 16 - 80, y: 46, width: 80, height: 14)
        slider.minValue = -60
        slider.maxValue = 0
        slider.step = 1
        slider.value = -30
        slider.mode = .meter
        slider.knobStyle = .hollow
        for view in [title, toggle, outputTitle, outputLabel, slider] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }
}
