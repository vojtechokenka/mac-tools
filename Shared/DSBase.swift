import AppKit

struct DSControlState: OptionSet {
    let rawValue: Int
    static let hovered = DSControlState(rawValue: 1)
    static let pressed = DSControlState(rawValue: 2)
    static let focused = DSControlState(rawValue: 4)
}

enum DSDraw {
    static func fill(_ rect: NSRect, _ color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        color.setFill()
        context.fill(rect)
    }

    static func fill(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    static func circle(center: CGPoint, radius: CGFloat, _ color: NSColor) {
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    static func border(_ rect: NSRect, radius: CGFloat, _ color: NSColor, width: CGFloat = 1, dash: [CGFloat]? = nil) {
        let inset = width / 2
        let corner = max(radius - inset, 0)
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: corner, yRadius: corner)
        path.lineWidth = width
        if let dash { path.setLineDash(dash, count: dash.count, phase: 0) }
        color.setStroke()
        path.stroke()
    }

    static func dashedBorder(_ rect: NSRect, radius: CGFloat, _ color: NSColor) {
        let inner = rect.insetBy(dx: 0.5, dy: 0.5)
        let corner = max(radius - 0.5, 0)
        let perimeter = 2 * (inner.width + inner.height) - 8 * corner + 2 * .pi * corner
        let dash: CGFloat = 2
        let gap: CGFloat = 1
        let fewer = max((perimeter / (dash + gap)).rounded(.down), 1)
        let more = fewer + 1
        let wideGap = (perimeter - fewer * dash) / fewer
        let tightGap = (perimeter - more * dash) / more
        let best = (tightGap <= 0 || abs(wideGap - gap) < abs(tightGap - gap)) ? wideGap : tightGap
        border(rect, radius: radius, color, dash: [dash, max(best, 0.5)])
    }

    static func focusRing(_ rect: NSRect, radius: CGFloat) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: radius + 3, yRadius: radius + 3)
        path.lineWidth = 2
        DS.blue.setStroke()
        path.stroke()
    }

    static func dimmed(_ dimmed: Bool, _ body: () -> Void) {
        guard dimmed, let context = NSGraphicsContext.current?.cgContext else {
            body()
            return
        }
        context.saveGState()
        context.setAlpha(DS.disabledOpacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        body()
        context.endTransparencyLayer()
        context.restoreGState()
    }
}

final class DSTween {
    private(set) var value: CGFloat
    private var timer: Timer?

    init(_ value: CGFloat = 0) {
        self.value = value
    }

    func set(_ target: CGFloat, duration: TimeInterval = 0, onUpdate: @escaping () -> Void) {
        timer?.invalidate()
        timer = nil
        guard target != value else { return }
        guard duration > 0, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            value = target
            onUpdate()
            return
        }
        let from = value
        let began = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            let progress = min(1, (ProcessInfo.processInfo.systemUptime - began) / duration)
            let rest = 1 - progress
            let eased = 1 - rest * rest * rest
            self.value = from + (target - from) * CGFloat(eased)
            if progress >= 1 {
                timer.invalidate()
                self.timer = nil
            }
            onUpdate()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

final class DSAccessibilityItem: NSAccessibilityElement {
    var frameProvider: (() -> NSRect)?
    var valueProvider: (() -> Any?)?
    var pressHandler: (() -> Void)?

    init(role: NSAccessibility.Role, label: String, parent: Any) {
        super.init()
        setAccessibilityRole(role)
        setAccessibilityLabel(label)
        setAccessibilityParent(parent)
    }

    override func accessibilityFrame() -> NSRect {
        frameProvider?() ?? .zero
    }

    override func accessibilityValue() -> Any? {
        valueProvider?()
    }

    override func accessibilityPerformPress() -> Bool {
        guard let pressHandler else { return false }
        pressHandler()
        return true
    }
}

class DSView: NSView {
    init() {
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    func sizeToFit() {
        let size = intrinsicContentSize
        setFrameSize(NSSize(
            width: size.width == NSView.noIntrinsicMetric ? frame.width : size.width,
            height: size.height == NSView.noIntrinsicMetric ? frame.height : size.height
        ))
    }

    func contentChanged() {
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
}

class DSControl: DSView {
    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { cancelInteraction() }
            needsDisplay = true
        }
    }

    var previewState: DSControlState = [] {
        didSet {
            stateChanged()
            invalidateOutset()
        }
    }

    private var mouseInside = false
    private var mousePressed = false
    private var trackingPress = false
    private var keyboardFocus = false
    private var trackingArea: NSTrackingArea?

    var isHovered: Bool { isEnabled && (mouseInside || previewState.contains(.hovered)) }
    var isPressed: Bool { isEnabled && (mousePressed || previewState.contains(.pressed)) }
    var showsFocus: Bool { isEnabled && ((keyboardFocus && window?.firstResponder === self) || previewState.contains(.focused)) }

    var tracksMouseMoves: Bool { false }
    var isFocusable: Bool { true }
    var outset: CGFloat { 5 }

    func activate() {}

    func stateChanged() {
        needsDisplay = true
    }

    func pointerMoved(to point: NSPoint?) {}

    func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 49 || event.keyCode == 36 || event.keyCode == 76 {
            activate()
            return true
        }
        return false
    }

    func noteKeyboardUse() {
        guard !keyboardFocus else { return }
        keyboardFocus = true
        invalidateOutset()
    }

    func invalidateOutset() {
        let amount = outset
        setNeedsDisplay(bounds.insetBy(dx: -amount, dy: -amount))
        superview?.setNeedsDisplay(frame.insetBy(dx: -amount, dy: -amount))
    }

    func cancelInteraction() {
        let changed = mouseInside || mousePressed || trackingPress
        mouseInside = false
        mousePressed = false
        trackingPress = false
        pointerMoved(to: nil)
        if changed { stateChanged() }
    }

    func screenRect(_ rect: NSRect) -> NSRect {
        guard let window else { return .zero }
        return window.convertToScreen(convert(rect, to: nil))
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { isEnabled && isFocusable }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && (NSApp?.isFullKeyboardAccessEnabled ?? false) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let type = NSApp?.currentEvent?.type
        keyboardFocus = !(type == .leftMouseDown || type == .leftMouseUp || type == .leftMouseDragged || type == .rightMouseDown)
        invalidateOutset()
        return true
    }

    override func resignFirstResponder() -> Bool {
        keyboardFocus = false
        invalidateOutset()
        return true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        var options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        if tracksMouseMoves { options.insert(.mouseMoved) }
        let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelInteraction()
    }

    override func viewDidHide() {
        super.viewDidHide()
        cancelInteraction()
    }

    override func mouseEntered(with event: NSEvent) {
        mouseInside = true
        pointerMoved(to: convert(event.locationInWindow, from: nil))
        stateChanged()
    }

    override func mouseExited(with event: NSEvent) {
        mouseInside = false
        pointerMoved(to: nil)
        stateChanged()
    }

    override func mouseMoved(with event: NSEvent) {
        pointerMoved(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        keyboardFocus = false
        trackingPress = true
        mousePressed = true
        stateChanged()
    }

    override func mouseDragged(with event: NSEvent) {
        guard trackingPress else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if inside != mousePressed {
            mousePressed = inside
            stateChanged()
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard trackingPress else { return }
        trackingPress = false
        mousePressed = false
        stateChanged()
        if isEnabled, bounds.contains(convert(event.locationInWindow, from: nil)) { activate() }
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, handleKey(event) else {
            super.keyDown(with: event)
            return
        }
        noteKeyboardUse()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        activate()
        return true
    }
}
