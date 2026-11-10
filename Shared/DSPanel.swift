import AppKit

enum DSSurface {
    static let outset = NSEdgeInsets(top: 24, left: 40, bottom: 52, right: 40)

    static func draw(around rect: NSRect, radius: CGFloat = DS.panelRadius) {
        guard let current = NSGraphicsContext.current else { return }
        let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = DS.resolved(DS.floatShadow, for: NSAppearance.currentDrawing())
        shadow.shadowBlurRadius = DS.floatShadowBlur
        shadow.shadowOffset = NSSize(width: 0, height: current.isFlipped ? DS.floatShadowDrop : -DS.floatShadowDrop)
        shadow.set()
        DS.paper.setFill()
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -1, dy: -1), xRadius: radius + 1, yRadius: radius + 1)
        ring.append(shape)
        ring.windingRule = .evenOdd
        DS.floatBorder.setFill()
        ring.fill()
    }

    static func frame(around rect: NSRect, flipped: Bool = false) -> NSRect {
        NSRect(
            x: rect.minX - outset.left,
            y: rect.minY - (flipped ? outset.top : outset.bottom),
            width: rect.width + outset.left + outset.right,
            height: rect.height + outset.top + outset.bottom
        )
    }
}

private final class DSPanelShadowView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let outset = DSSurface.outset
        let rect = NSRect(x: outset.left, y: outset.bottom, width: bounds.width - outset.left - outset.right, height: bounds.height - outset.top - outset.bottom)
        DSSurface.draw(around: rect)
    }
}

private final class DSPanelRootView: NSView {
    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = DS.panelRadius
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.fill(bounds, DS.paper)
    }
}

private final class DSPanelDocumentView: NSView {
    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

final class DSPanel: NSPanel {
    enum Alignment {
        case center
        case leading
        case trailing
    }

    var onClose: (() -> Void)?
    var onShow: (() -> Void)?
    var onEscape: (() -> Bool)?
    var maxHeight: CGFloat?
    var contentHeight: CGFloat?
    var closesOnOutsideClick = true
    var closesOnEscape = true
    var takesKeyFocus = true
    var gap: CGFloat = 4
    var screenMargin: CGFloat = 8
    var alignment: Alignment = .center

    private(set) var isShown = false
    private(set) var panelWidth: CGFloat

    var content: NSView? {
        didSet {
            guard content !== oldValue else { return }
            install()
        }
    }

    private let root = DSPanelRootView()
    private let scroll = NSScrollView()
    private let document = DSPanelDocumentView()
    private let shadowWindow: NSPanel
    private var widthConstraint: NSLayoutConstraint?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private weak var anchorWindow: NSWindow?
    private var heightLimit: CGFloat?

    init(width: CGFloat, content: NSView? = nil) {
        panelWidth = width
        shadowWindow = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        super.init(contentRect: NSRect(x: 0, y: 0, width: width, height: 120), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]

        shadowWindow.level = .statusBar
        shadowWindow.hasShadow = false
        shadowWindow.isOpaque = false
        shadowWindow.backgroundColor = .clear
        shadowWindow.ignoresMouseEvents = true
        shadowWindow.hidesOnDeactivate = false
        shadowWindow.isReleasedWhenClosed = false
        shadowWindow.animationBehavior = .none
        shadowWindow.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        shadowWindow.contentView = DSPanelShadowView()

        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = document
        scroll.frame = NSRect(x: 0, y: 0, width: width, height: 120)
        scroll.autoresizingMask = [.width, .height]
        root.frame = NSRect(x: 0, y: 0, width: width, height: 120)
        root.addSubview(scroll)
        contentView = root

        self.content = content
        install()
    }

    deinit {
        removeMonitors()
    }

    override var canBecomeKey: Bool { takesKeyFocus }
    override var canBecomeMain: Bool { false }

    override var level: NSWindow.Level {
        didSet { shadowWindow.level = level }
    }

    static func frame(size: NSSize, below anchor: NSRect, in visible: NSRect, gap: CGFloat = 4, margin: CGFloat = 8, alignment: Alignment = .center) -> NSRect {
        var x: CGFloat
        switch alignment {
        case .center: x = anchor.midX - size.width / 2
        case .leading: x = anchor.minX
        case .trailing: x = anchor.maxX - size.width
        }
        x = max(min(x, visible.maxX - margin - size.width), visible.minX + margin)
        let top = min(anchor.minY, visible.maxY) - gap
        let y = max(top - size.height, visible.minY + margin)
        return NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }

    func setWidth(_ width: CGFloat) {
        guard width != panelWidth else { return }
        panelWidth = width
        widthConstraint?.constant = width
        sizeToContent()
    }

    func setContentHeight(_ height: CGFloat?) {
        contentHeight = height
        sizeToContent()
    }

    func sizeToContent() {
        let height = fittedHeight()
        let top = frame.maxY
        applyFrame(NSRect(x: frame.minX, y: top - height, width: panelWidth, height: height))
    }

    func show(under button: NSStatusBarButton) {
        guard let host = button.window else { return }
        anchorWindow = host
        place(below: host.convertToScreen(button.convert(button.bounds, to: nil)), screen: host.screen)
    }

    func toggle(under button: NSStatusBarButton) {
        if isShown {
            dismiss()
        } else {
            show(under: button)
        }
    }

    func show(below anchor: NSRect, screen: NSScreen? = nil) {
        anchorWindow = nil
        place(below: anchor, screen: screen)
    }

    private func place(below anchor: NSRect, screen: NSScreen?) {
        let target = screen ?? NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        let visible = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        heightLimit = max(min(anchor.minY, visible.maxY) - gap - visible.minY - screenMargin, 80)
        let size = NSSize(width: panelWidth, height: fittedHeight())
        present(Self.frame(size: size, below: anchor, in: visible, gap: gap, margin: screenMargin, alignment: alignment))
    }

    func show(at topLeft: NSPoint, screen: NSScreen? = nil) {
        anchorWindow = nil
        let target = screen ?? NSScreen.screens.first(where: { $0.frame.contains(topLeft) }) ?? NSScreen.main
        let visible = target?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        heightLimit = max(visible.height - 2 * screenMargin, 80)
        let size = NSSize(width: panelWidth, height: fittedHeight())
        let x = max(min(topLeft.x, visible.maxX - screenMargin - size.width), visible.minX + screenMargin)
        let y = max(min(topLeft.y, visible.maxY - screenMargin) - size.height, visible.minY + screenMargin)
        present(NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height))
    }

    func dismiss() {
        guard isShown else { return }
        isShown = false
        removeMonitors()
        if shadowWindow.parent != nil { removeChildWindow(shadowWindow) }
        shadowWindow.orderOut(nil)
        orderOut(nil)
        onClose?()
    }

    override func close() {
        if isShown {
            dismiss()
        } else {
            orderOut(nil)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if closesOnEscape { dismiss() }
    }

    override func resignKey() {
        super.resignKey()
        guard isShown, closesOnOutsideClick, takesKeyFocus else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShown, !self.isKeyWindow, self.closesOnOutsideClick else { return }
            if let key = NSApp.keyWindow, self.owns(key) { return }
            if self.attachedSheet != nil { return }
            self.dismiss()
        }
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, isShown, closesOnEscape {
            if let editor = firstResponder as? NSTextView {
                if editor.hasMarkedText() {
                    super.sendEvent(event)
                    return
                }
                if let field = editor.delegate as? NSTextField, let handler = field.delegate,
                   handler.control?(field, textView: editor, doCommandBy: #selector(NSResponder.cancelOperation(_:))) == true {
                    return
                }
            }
            if onEscape?() == true { return }
            dismiss()
            return
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        guard event.type == .keyDown, let editor = firstResponder as? NSText else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags == .command {
            switch key {
            case "x": editor.cut(nil)
            case "c": editor.copy(nil)
            case "v": editor.paste(nil)
            case "a": editor.selectAll(nil)
            case "z": editor.undoManager?.undo()
            default: return false
            }
            return true
        }
        if flags == [.command, .shift], key == "z" {
            editor.undoManager?.redo()
            return true
        }
        return false
    }

    private func install() {
        for view in document.subviews { view.removeFromSuperview() }
        widthConstraint = nil
        guard let content else { return }
        document.addSubview(content)
        if !content.translatesAutoresizingMaskIntoConstraints {
            let width = content.widthAnchor.constraint(equalToConstant: panelWidth)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
                content.topAnchor.constraint(equalTo: document.topAnchor),
                width,
            ])
            widthConstraint = width
        }
        sizeToContent()
    }

    private func measuredContentHeight() -> CGFloat {
        guard let content else { return 0 }
        if let contentHeight { return contentHeight }
        if content.translatesAutoresizingMaskIntoConstraints { return content.frame.height }
        return ceil(content.fittingSize.height)
    }

    private func fittedHeight() -> CGFloat {
        let height = max(measuredContentHeight(), 1)
        if let content, content.translatesAutoresizingMaskIntoConstraints {
            content.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        }
        document.frame = NSRect(x: 0, y: 0, width: panelWidth, height: height)
        var visible = height
        if let maxHeight { visible = min(visible, maxHeight) }
        if let heightLimit { visible = min(visible, heightLimit) }
        return max(visible, 1)
    }

    private func applyFrame(_ frame: NSRect) {
        setFrame(frame, display: true)
        shadowWindow.setFrame(DSSurface.frame(around: frame), display: true)
    }

    private func present(_ frame: NSRect) {
        applyFrame(frame)
        document.scroll(.zero)
        Self.resetControls(in: root)
        orderFrontRegardless()
        if shadowWindow.parent == nil { addChildWindow(shadowWindow, ordered: .below) }
        if takesKeyFocus {
            makeKey()
            if let first = initialFirstResponder { makeFirstResponder(first) }
        }
        installMonitors()
        let wasShown = isShown
        isShown = true
        if !wasShown { onShow?() }
    }

    private static func resetControls(in view: NSView) {
        (view as? DSControl)?.cancelInteraction()
        for child in view.subviews { resetControls(in: child) }
    }

    private func owns(_ window: NSWindow) -> Bool {
        var candidate: NSWindow? = window
        while let current = candidate {
            if current === self { return true }
            candidate = current.parent
        }
        return false
    }

    private func installMonitors() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            guard let self, self.closesOnOutsideClick else { return }
            self.dismiss()
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            if let self, self.isShown, self.closesOnOutsideClick, let window = event.window, !self.owns(window), window !== self.anchorWindow {
                self.dismiss()
            }
            return event
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.closesOnOutsideClick else { return }
            self.dismiss()
        }
    }

    private func removeMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        globalMonitor = nil
        localMonitor = nil
        spaceObserver = nil
    }
}
