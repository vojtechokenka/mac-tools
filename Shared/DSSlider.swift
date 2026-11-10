import AppKit

final class DSSlider: DSControl {
    enum Mode {
        case value
        case meter
        case output
    }

    static let height: CGFloat = 20
    static let trackHeight: CGFloat = 4
    static let knobSize: CGFloat = 16

    var mode: Mode = .value { didSet { if mode != oldValue { redrawAll() } } }
    var minValue = 0.0 { didSet { if minValue != oldValue { redrawAll() } } }
    var maxValue = 1.0 { didSet { if maxValue != oldValue { redrawAll() } } }
    var value = 0.0 { didSet { if value != oldValue { redrawAll() } } }
    var step: Double?
    var keyboardStep: Double?
    var isCapped = false { didSet { if isCapped != oldValue { redrawAll() } } }
    var onChange: ((Double) -> Void)?
    var onCommit: ((Double) -> Void)?

    private(set) var liveLevel: CGFloat = 0
    private(set) var modifierFlags: NSEvent.ModifierFlags = []
    private(set) var isDragging = false
    private let knobTween = DSTween()

    init(value: Double = 0, range: ClosedRange<Double> = 0...1, mode: Mode = .value, label: String? = nil, onChange: ((Double) -> Void)? = nil) {
        super.init()
        self.minValue = range.lowerBound
        self.maxValue = range.upperBound
        self.value = min(max(value, range.lowerBound), range.upperBound)
        self.mode = mode
        self.onChange = onChange
        if let label { setAccessibilityLabel(label) }
    }

    required init?(coder: NSCoder) { nil }

    var isInteractive: Bool { isEnabled && (mode != .output || isCapped) }

    var fraction: CGFloat {
        guard maxValue > minValue else { return 0 }
        return CGFloat(min(max((value - minValue) / (maxValue - minValue), 0), 1))
    }

    func setLiveLevel(_ level: CGFloat) {
        let next = min(max(level, 0), 1)
        guard abs(next - liveLevel) * max(bounds.width, 1) >= 0.25 || (next == 0) != (liveLevel == 0) else { return }
        liveLevel = next
        setNeedsDisplay(trackRect)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    override var isFocusable: Bool { mode != .output || isCapped }
    override var outset: CGFloat { 6 }

    private var trackRect: NSRect {
        NSRect(x: 0, y: ((bounds.height - Self.trackHeight) / 2).rounded(), width: bounds.width, height: Self.trackHeight)
    }

    private var travel: CGFloat { max(bounds.width - Self.knobSize, 0) }

    private func redrawAll() {
        invalidateOutset()
    }

    override func stateChanged() {
        let target: CGFloat = isInteractive && (isHovered || isDragging) ? 1 : 0
        knobTween.set(target, duration: 0.12) { [weak self] in self?.invalidateOutset() }
        invalidateOutset()
    }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.dimmed(!isEnabled) { drawContent() }
    }

    private func drawContent() {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let track = trackRect
        let knobX = fraction * travel
        let edge = knobX + Self.knobSize / 2
        let hasKnob = mode != .output || isCapped

        context.saveGState()
        NSBezierPath(roundedRect: track, xRadius: 1, yRadius: 1).addClip()
        DSDraw.fill(track, DS.chip)
        func bar(from: CGFloat, to: CGFloat, _ color: NSColor) {
            guard to > from else { return }
            DSDraw.fill(NSRect(x: from, y: track.minY, width: to - from, height: track.height), color)
        }
        switch mode {
        case .value:
            bar(from: 0, to: edge, DS.blue)
        case .meter:
            bar(from: 0, to: edge, DS.blueGhost)
            bar(from: 0, to: liveLevel * knobX, DS.blue)
        case .output:
            if isCapped {
                bar(from: 0, to: liveLevel * edge, DS.blue)
                bar(from: edge, to: track.maxX, DS.pinkGhost)
            } else {
                bar(from: 0, to: liveLevel * track.width, DS.blue)
            }
        }
        context.restoreGState()

        guard hasKnob else { return }
        let grow = max(knobTween.value, previewState.contains(.hovered) && isInteractive ? 1 : 0)
        let scale = 1 + 0.12 * grow
        let center = CGPoint(x: edge, y: bounds.midY)
        func square(_ half: CGFloat, _ radius: CGFloat, _ color: NSColor) {
            let side = half * 2 * scale
            DSDraw.fill(NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), radius: radius * scale, color)
        }
        if showsFocus { square(12, 8, DS.blue) }
        square(10, 6, DS.paper)
        if mode == .output {
            square(8, 4, DS.pink)
            square(6.5, 2.5, DS.paper)
            DSDraw.circle(center: center, radius: 2.9 * scale, DS.pink)
        } else {
            square(8, 4, DS.blue)
            DSDraw.circle(center: center, radius: 3.3 * scale, DS.onBlue)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else { return }
        window?.makeFirstResponder(self)
        isDragging = true
        stateChanged()
        apply(event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        apply(event)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        stateChanged()
        onCommit?(value)
    }

    override func cancelInteraction() {
        super.cancelInteraction()
        guard isDragging else { return }
        isDragging = false
        stateChanged()
        onCommit?(value)
    }

    private func apply(_ event: NSEvent) {
        guard travel > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        let position = min(max((x - Self.knobSize / 2) / travel, 0), 1)
        setFromUser(minValue + Double(position) * (maxValue - minValue), modifiers: event.modifierFlags)
    }

    private func setFromUser(_ raw: Double, modifiers: NSEvent.ModifierFlags) {
        var next = raw
        if let step, step > 0 { next = minValue + ((next - minValue) / step).rounded() * step }
        next = min(max(next, minValue), maxValue)
        modifierFlags = modifiers
        guard next != value else { return }
        value = next
        onChange?(next)
    }

    private func nudge(_ delta: Double, modifiers: NSEvent.ModifierFlags) {
        let before = value
        setFromUser(value + delta, modifiers: modifiers)
        if value != before { onCommit?(value) }
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        guard isInteractive else { return false }
        let delta = keyboardStep ?? step ?? (maxValue - minValue) / 20
        switch event.keyCode {
        case 123, 125: nudge(-delta, modifiers: event.modifierFlags)
        case 124, 126: nudge(delta, modifiers: event.modifierFlags)
        case 115: nudge(minValue - value, modifiers: event.modifierFlags)
        case 119: nudge(maxValue - value, modifiers: event.modifierFlags)
        default: return false
        }
        return true
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityValue() -> Any? { NSNumber(value: value) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: minValue) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: maxValue) }
    override func isAccessibilityEnabled() -> Bool { isInteractive }

    override func accessibilityPerformIncrement() -> Bool {
        guard isInteractive else { return false }
        nudge(keyboardStep ?? step ?? (maxValue - minValue) / 20, modifiers: [])
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isInteractive else { return false }
        nudge(-(keyboardStep ?? step ?? (maxValue - minValue) / 20), modifiers: [])
        return true
    }

    override func accessibilityPerformPress() -> Bool { false }
}
