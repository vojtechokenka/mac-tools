import AppKit
import CoreText

final class DSLabel: DSView {
    var text: String { didSet { if text != oldValue { contentChanged() } } }
    var font: NSFont { didSet { contentChanged() } }
    var color: NSColor { didSet { needsDisplay = true } }
    var alignment: NSTextAlignment = .left { didSet { needsDisplay = true } }
    var lineHeight: CGFloat? { didSet { contentChanged() } }
    var maxLines = 1 { didSet { contentChanged() } }
    var isStruck = false { didSet { needsDisplay = true } }

    init(_ text: String = "", size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = DS.text) {
        self.text = text
        self.font = DS.font(size, weight)
        self.color = color
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    var resolvedLineHeight: CGFloat {
        lineHeight ?? (font.pointSize * 1.25).rounded()
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        guard maxLines != 1 else { return resolvedLineHeight }
        return CGFloat(max(DSText.wrap(text, font: font, width: width, maxLines: maxLines).count, 1)) * resolvedLineHeight
    }

    override var intrinsicContentSize: NSSize {
        if maxLines == 1 {
            return NSSize(width: ceil(DSText.width(text, font: font)), height: resolvedLineHeight)
        }
        guard bounds.width > 0 else { return NSSize(width: NSView.noIntrinsicMetric, height: resolvedLineHeight) }
        return NSSize(width: NSView.noIntrinsicMetric, height: height(forWidth: bounds.width))
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        if widthChanged, maxLines != 1 { invalidateIntrinsicContentSize() }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else { return }
        let lines = DSText.wrap(text, font: font, width: bounds.width, maxLines: maxLines)
        let lineBox = resolvedLineHeight
        var top = maxLines == 1 ? ((bounds.height - lineBox) / 2) : 0
        for line in lines {
            let width = DSText.width(of: line)
            var x: CGFloat = 0
            if alignment == .center {
                x = (bounds.width - width) / 2
            } else if alignment == .right {
                x = bounds.width - width
            }
            DSText.draw(line, x: x, top: top, height: lineBox, font: font, color: color, lineHeight: lineHeight)
            if isStruck {
                let baseline = DSText.baseline(top: top, height: lineBox, font: font, lineHeight: lineHeight)
                DSDraw.fill(NSRect(x: DSText.snap(x), y: DSText.snap(baseline - font.xHeight / 2 - 0.5), width: min(width, bounds.width), height: 1), color)
            }
            top += lineBox
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { text }
}

final class DSTag: DSView {
    enum Style {
        case neutral
        case red
        case blue
        case amber
        case plain
    }

    var text: String { didSet { if text != oldValue { contentChanged() } } }
    var style: Style { didSet { if style != oldValue { contentChanged() } } }
    var isSmall: Bool { didSet { if isSmall != oldValue { contentChanged() } } }
    var icon: DSIcon? { didSet { if icon != oldValue { contentChanged() } } }
    var minWidth: CGFloat? { didSet { contentChanged() } }
    var isMuted = false { didSet { needsDisplay = true } }

    init(_ text: String, style: Style = .neutral, small: Bool = false, icon: DSIcon? = nil, minWidth: CGFloat? = nil) {
        self.text = text
        self.style = style
        self.isSmall = small
        self.icon = icon
        self.minWidth = minWidth
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    private var tagFont: NSFont { DS.font(isSmall ? 9.5 : 11) }
    private var tagHeight: CGFloat { isSmall ? 15 : 18 }
    private var padding: CGFloat { style == .plain ? 0 : (isSmall ? 5 : 6) }
    private var iconSide: CGFloat { isSmall ? 9.5 : 11 }
    private var iconGap: CGFloat { 4 }

    private var contentWidth: CGFloat {
        DSText.width(text, font: tagFont) + (icon == nil ? 0 : iconSide + iconGap)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(minWidth ?? 0, ceil(contentWidth) + padding * 2), height: tagHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: ((bounds.height - tagHeight) / 2).rounded(), width: bounds.width, height: tagHeight)
        let radius: CGFloat = isSmall ? 3 : DS.radius
        var foreground = isMuted ? DS.muted : DS.text
        switch style {
        case .neutral:
            DSDraw.fill(rect, radius: radius, DS.chip)
        case .red:
            DSDraw.fill(rect, radius: radius, DS.red)
            foreground = DS.onRed
        case .blue:
            DSDraw.fill(rect, radius: radius, DS.blue)
            foreground = DS.onBlue
        case .amber:
            DSDraw.fill(rect, radius: radius, DS.amber)
            foreground = DS.onAmber
        case .plain:
            foreground = DS.muted
        }
        let font = tagFont
        let textWidth = DSText.width(text, font: font)
        var x = style == .plain ? rect.minX : rect.minX + max((rect.width - contentWidth) / 2, padding)
        if let icon {
            icon.draw(in: NSRect(x: DSText.snap(x), y: rect.midY - iconSide / 2, width: iconSide, height: iconSide), color: foreground, opacity: 0.75)
            x += iconSide + iconGap
        }
        DSText.draw(text, in: NSRect(x: x, y: rect.minY, width: max(min(textWidth, rect.maxX - x), 0), height: rect.height), font: font, color: foreground)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { text }
}

final class DSProgressBar: DSView {
    static let height: CGFloat = 4

    var progress: Double { didSet { if progress != oldValue { needsDisplay = true } } }

    init(progress: Double = 0) {
        self.progress = progress
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: ((bounds.height - Self.height) / 2).rounded(), width: bounds.width, height: Self.height)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).addClip()
        DSDraw.fill(rect, DS.chip)
        let amount = CGFloat(min(max(progress, 0), 1))
        if amount > 0 { DSDraw.fill(NSRect(x: rect.minX, y: rect.minY, width: rect.width * amount, height: rect.height), DS.blue) }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .progressIndicator }
    override func accessibilityValue() -> Any? { NSNumber(value: min(max(progress, 0), 1)) }
    override func accessibilityMinValue() -> Any? { NSNumber(value: 0) }
    override func accessibilityMaxValue() -> Any? { NSNumber(value: 1) }
}

final class DSSeparator: DSView {
    var color: NSColor { didSet { needsDisplay = true } }

    init(color: NSColor = DS.chip) {
        self.color = color
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.fill(bounds, color)
    }
}

final class DSSectionHeader: DSView {
    static let height: CGFloat = 16

    var icon: DSIcon? { didSet { if icon != oldValue { needsDisplay = true } } }
    var title: String { didSet { if title != oldValue { needsDisplay = true } } }
    var value: String? { didSet { if value != oldValue { needsDisplay = true } } }
    var valueColor: NSColor = DS.text { didSet { needsDisplay = true } }

    init(icon: DSIcon? = nil, title: String, value: String? = nil) {
        self.icon = icon
        self.title = title
        self.value = value
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: ((bounds.height - Self.height) / 2).rounded(), width: bounds.width, height: Self.height)
        let font = DS.smallFont
        var x = rect.minX
        if let icon {
            icon.draw(in: NSRect(x: x, y: rect.minY, width: 16, height: 16), color: DS.muted, opacity: 0.5)
            x += 16 + DS.gapTight
        }
        var trailing = rect.maxX
        if let value, !value.isEmpty {
            let width = DSText.width(value, font: font)
            DSText.draw(value, in: NSRect(x: rect.maxX - width, y: rect.minY, width: width, height: rect.height), font: font, color: valueColor, truncates: false)
            trailing = rect.maxX - width - DS.gapTight
        }
        DSText.draw(title, in: NSRect(x: x, y: rect.minY, width: max(trailing - x, 0), height: rect.height), font: font, color: DS.muted)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }

    override func accessibilityValue() -> Any? {
        if let value, !value.isEmpty { return "\(title), \(value)" }
        return title
    }
}
