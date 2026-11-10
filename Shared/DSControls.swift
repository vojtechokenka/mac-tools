import AppKit

final class DSToggle: DSControl {
    static let size = NSSize(width: 30, height: 18)

    var onChange: ((Bool) -> Void)?
    var isOn: Bool {
        get { on }
        set {
            guard newValue != on else { return }
            on = newValue
            tween.set(newValue ? 1 : 0) {}
            needsDisplay = true
        }
    }

    private var on = false
    private let tween = DSTween()

    init(isOn: Bool = false, label: String? = nil, onChange: ((Bool) -> Void)? = nil) {
        super.init()
        on = isOn
        tween.set(isOn ? 1 : 0) {}
        self.onChange = onChange
        if let label { setAccessibilityLabel(label) }
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { Self.size }

    override func activate() {
        on.toggle()
        tween.set(on ? 1 : 0, duration: 0.14) { [weak self] in self?.needsDisplay = true }
        needsDisplay = true
        onChange?(on)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = NSRect(x: 0, y: ((bounds.height - Self.size.height) / 2).rounded(), width: Self.size.width, height: Self.size.height)
        DSDraw.dimmed(!isEnabled) {
            if on {
                DSDraw.fill(rect, radius: DS.radius, DS.blue)
            } else {
                DSDraw.border(rect, radius: DS.radius, DS.line)
            }
            let progress = tween.value
            let center = CGPoint(x: rect.minX + 9 + 12 * progress, y: rect.midY)
            if progress <= 0 {
                DSDraw.circle(center: center, radius: 5, DS.icon)
            } else if progress >= 1 {
                DSDraw.circle(center: center, radius: 5, DS.onBlue)
            } else {
                DSDraw.circle(center: center, radius: 5, DS.alpha(DS.icon, 1 - progress))
                DSDraw.circle(center: center, radius: 5, DS.onBlue.withAlphaComponent(progress))
            }
        }
        if showsFocus { DSDraw.focusRing(rect, radius: DS.radius) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilitySubrole() -> NSAccessibility.Subrole? { .switch }
    override func accessibilityValue() -> Any? { NSNumber(value: on ? 1 : 0) }
}

final class DSButton: DSControl {
    enum Style {
        case primary
        case secondary
        case quiet
    }

    var title: String { didSet { if title != oldValue { contentChanged() } } }
    var style: Style { didSet { if style != oldValue { needsDisplay = true } } }
    var isFullWidth: Bool { didSet { if isFullWidth != oldValue { contentChanged() } } }
    var onClick: (() -> Void)?

    init(_ title: String, style: Style = .secondary, fullWidth: Bool = false, onClick: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.isFullWidth = fullWidth
        self.onClick = onClick
        super.init()
        if fullWidth { setContentHuggingPriority(.defaultLow, for: .horizontal) }
    }

    required init?(coder: NSCoder) { nil }

    var fittingWidth: CGFloat { ceil(DSText.width(title, font: DS.bodyFont)) + 26 }

    override var intrinsicContentSize: NSSize {
        NSSize(width: isFullWidth ? NSView.noIntrinsicMetric : fittingWidth, height: DS.controlHeight)
    }

    override func activate() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        DSDraw.dimmed(!isEnabled) {
            var textColor = DS.text
            switch style {
            case .primary:
                DSDraw.fill(rect, radius: DS.radius, isPressed ? DS.bluePressed : (isHovered ? DS.blueHover : DS.blue))
                if !isEnabled { DSDraw.border(rect, radius: DS.radius, DS.line) }
                textColor = DS.onBlue
            case .secondary:
                if isPressed { DSDraw.fill(rect, radius: DS.radius, DS.sunken) }
                DSDraw.border(rect, radius: DS.radius, isHovered || isPressed ? DS.muted : DS.line)
            case .quiet:
                if isPressed {
                    DSDraw.fill(rect, radius: DS.radius, DS.line)
                } else if isHovered {
                    DSDraw.fill(rect, radius: DS.radius, DS.chip)
                }
                textColor = isHovered || isPressed ? DS.ink : DS.muted
            }
            DSText.draw(title, in: rect.insetBy(dx: 8, dy: 0), font: DS.bodyFont, color: textColor, alignment: .center)
        }
        if showsFocus { DSDraw.focusRing(rect, radius: DS.radius) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { super.accessibilityLabel() ?? title }
}

final class DSIconButton: DSControl {
    var icon: DSIcon { didSet { if icon != oldValue { needsDisplay = true } } }
    var isOn = false { didSet { if isOn != oldValue { needsDisplay = true } } }
    var iconSize: CGFloat = DS.iconSize { didSet { needsDisplay = true } }
    var tint: NSColor = DS.icon { didSet { needsDisplay = true } }
    var hoverTint: NSColor = DS.blue { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?

    init(_ icon: DSIcon, label: String, onClick: (() -> Void)? = nil) {
        self.icon = icon
        self.onClick = onClick
        super.init()
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: DS.iconButtonSize, height: DS.iconButtonSize)
    }

    override func activate() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = DS.iconButtonSize
        let rect = NSRect(x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        DSDraw.dimmed(!isEnabled) {
            var color = tint
            if isOn {
                DSDraw.fill(rect, radius: DS.radius, DS.chip)
                color = DS.text
            } else if isPressed {
                DSDraw.fill(rect, radius: DS.radius, DS.chip)
                color = hoverTint
            } else if isHovered {
                color = hoverTint
            }
            let glyph = NSRect(x: rect.midX - iconSize / 2, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize)
            icon.draw(in: glyph, color: color)
        }
        if showsFocus { DSDraw.focusRing(rect, radius: DS.radius) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityValue() -> Any? { isOn ? NSNumber(value: 1) : nil }
}

final class DSStepper: DSControl {
    static let buttonWidth: CGFloat = 28

    var value: Int { didSet { if value != oldValue { needsDisplay = true } } }
    var minValue: Int
    var maxValue: Int
    var step: Int
    var unit: String { didSet { needsDisplay = true } }
    var wraps = false
    var onChange: ((Int) -> Void)?

    private var hoverSide = 0 { didSet { if hoverSide != oldValue { needsDisplay = true } } }
    private var pressSide = 0 { didSet { if pressSide != oldValue { needsDisplay = true } } }
    private var repeatTimer: Timer?

    init(value: Int = 0, range: ClosedRange<Int> = 0...59, step: Int = 1, unit: String = "", label: String? = nil, onChange: ((Int) -> Void)? = nil) {
        self.value = min(max(value, range.lowerBound), range.upperBound)
        self.minValue = range.lowerBound
        self.maxValue = range.upperBound
        self.step = max(step, 1)
        self.unit = unit
        self.onChange = onChange
        super.init()
        if let label { setAccessibilityLabel(label) }
    }

    required init?(coder: NSCoder) { nil }

    override var tracksMouseMoves: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DS.controlHeight)
    }

    var minimumWidth: CGFloat {
        let widest = DSText.width("\(maxValue)", font: DS.bodyFont) + DSText.width(unit.isEmpty ? "" : " \(unit)", font: DS.bodyFont)
        return ceil(widest) + 2 * Self.buttonWidth + 2 + 12
    }

    private func side(at point: NSPoint?) -> Int {
        guard let point, bounds.contains(point) else { return 0 }
        if point.x < Self.buttonWidth + 1 { return -1 }
        if point.x > bounds.width - Self.buttonWidth - 1 { return 1 }
        return 0
    }

    private func bump(_ direction: Int) {
        var next = value + direction * step
        if next > maxValue { next = wraps ? minValue : maxValue }
        if next < minValue { next = wraps ? maxValue : minValue }
        guard next != value else { return }
        value = next
        onChange?(next)
    }

    private func stopRepeat() {
        repeatTimer?.invalidate()
        repeatTimer = nil
        pressSide = 0
    }

    override func pointerMoved(to point: NSPoint?) {
        hoverSide = isEnabled ? side(at: point) : 0
        if point == nil { stopRepeat() }
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        let direction = side(at: convert(event.locationInWindow, from: nil))
        guard direction != 0 else { return }
        pressSide = direction
        bump(direction)
        repeatTimer?.invalidate()
        let delay = Timer(timeInterval: 0.4, repeats: false) { [weak self] _ in
            guard let self, self.pressSide == direction else { return }
            let repeating = Timer(timeInterval: 0.09, repeats: true) { [weak self] _ in self?.bump(direction) }
            RunLoop.main.add(repeating, forMode: .common)
            self.repeatTimer = repeating
        }
        RunLoop.main.add(delay, forMode: .common)
        repeatTimer = delay
    }

    override func mouseDragged(with event: NSEvent) {
        guard pressSide != 0 else { return }
        if side(at: convert(event.locationInWindow, from: nil)) != pressSide { stopRepeat() }
    }

    override func mouseUp(with event: NSEvent) {
        stopRepeat()
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 125: bump(-1)
        case 124, 126: bump(1)
        default: return false
        }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let inner = rect.insetBy(dx: 1, dy: 1)
        let previewSide = previewState.contains(.hovered) ? 1 : 0
        DSDraw.dimmed(!isEnabled) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: inner, xRadius: DS.radius - 1, yRadius: DS.radius - 1).addClip()
            let glyphFont = DS.font(15)
            for direction in [-1, 1] {
                let box = direction < 0
                    ? NSRect(x: inner.minX, y: inner.minY, width: Self.buttonWidth, height: inner.height)
                    : NSRect(x: inner.maxX - Self.buttonWidth, y: inner.minY, width: Self.buttonWidth, height: inner.height)
                let hovered = hoverSide == direction || previewSide == direction
                if pressSide == direction {
                    DSDraw.fill(box, DS.chip)
                } else if hovered {
                    DSDraw.fill(box, DS.sunken)
                }
                DSText.draw(direction < 0 ? "\u{2212}" : "+", in: box, font: glyphFont, color: hovered || pressSide == direction ? DS.ink : DS.icon, alignment: .center, truncates: false)
            }
            NSGraphicsContext.restoreGraphicsState()
            DSDraw.border(rect, radius: DS.radius, DS.line)

            let font = DS.bodyFont
            let number = DSText.line("\(value)", font: font)
            let suffix = unit.isEmpty ? nil : DSText.line(" \(unit)", font: font)
            let numberWidth = DSText.width(of: number)
            let total = numberWidth + (suffix.map { DSText.width(of: $0) } ?? 0)
            let x = rect.midX - total / 2
            DSText.draw(number, x: x, top: rect.minY, height: rect.height, font: font, color: DS.text)
            if let suffix {
                DSText.draw(suffix, x: x + numberWidth, top: rect.minY, height: rect.height, font: font, color: DS.muted)
            }
        }
        if showsFocus { DSDraw.focusRing(rect, radius: DS.radius) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .incrementor }
    override func accessibilityValue() -> Any? { unit.isEmpty ? "\(value)" : "\(value) \(unit)" }

    override func accessibilityPerformIncrement() -> Bool {
        guard isEnabled else { return false }
        bump(1)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        guard isEnabled else { return false }
        bump(-1)
        return true
    }

    override func accessibilityPerformPress() -> Bool { false }
}

final class DSSegmented: DSControl {
    var items: [String] { didSet { rebuildAccessibility(); contentChanged() } }
    var selectedIndex: Int { didSet { if selectedIndex != oldValue { needsDisplay = true } } }
    var equalWidths = true { didSet { contentChanged() } }
    var isCompact = false { didSet { contentChanged() } }
    var onChange: ((Int) -> Void)?

    private var hoverIndex: Int? { didSet { if hoverIndex != oldValue { needsDisplay = true } } }
    private var accessibilityItems: [DSAccessibilityItem] = []

    init(_ items: [String], selectedIndex: Int = 0, label: String? = nil, onChange: ((Int) -> Void)? = nil) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.onChange = onChange
        super.init()
        if let label { setAccessibilityLabel(label) }
        rebuildAccessibility()
    }

    required init?(coder: NSCoder) { nil }

    override var tracksMouseMoves: Bool { true }

    private var naturalWidths: [CGFloat] {
        items.map { ceil(DSText.width($0, font: DS.bodyFont)) + 20 }
    }

    override var intrinsicContentSize: NSSize {
        let widths = naturalWidths
        let count = CGFloat(widths.count)
        let content = equalWidths ? (widths.max() ?? 0) * count : widths.reduce(0, +)
        return NSSize(width: content + max(count - 1, 0) + 2, height: isCompact ? 24 : DS.controlHeight)
    }

    private func segmentRects() -> [NSRect] {
        let inner = bounds.insetBy(dx: 1, dy: 1)
        let count = items.count
        guard count > 0 else { return [] }
        let available = inner.width - CGFloat(count - 1)
        var widths: [CGFloat]
        if equalWidths {
            widths = Array(repeating: available / CGFloat(count), count: count)
        } else {
            let natural = naturalWidths
            let extra = (available - natural.reduce(0, +)) / CGFloat(count)
            widths = natural.map { max($0 + extra, 0) }
        }
        var rects: [NSRect] = []
        var x = inner.minX
        for width in widths {
            let left = DSText.snap(x)
            let right = DSText.snap(x + width)
            rects.append(NSRect(x: left, y: inner.minY, width: right - left, height: inner.height))
            x += width + 1
        }
        return rects
    }

    private func index(at point: NSPoint?) -> Int? {
        guard let point, bounds.contains(point) else { return nil }
        let rects = segmentRects()
        return rects.firstIndex { point.x >= $0.minX - 0.5 && point.x < $0.maxX + 0.5 }
    }

    private func select(_ index: Int) {
        guard items.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        onChange?(index)
    }

    override func pointerMoved(to point: NSPoint?) {
        hoverIndex = isEnabled ? index(at: point) : nil
    }

    override func mouseUp(with event: NSEvent) {
        let target = index(at: convert(event.locationInWindow, from: nil))
        super.mouseUp(with: event)
        if isEnabled, let target { select(target) }
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126: select(max(selectedIndex - 1, 0))
        case 124, 125: select(min(selectedIndex + 1, items.count - 1))
        default: return false
        }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        let inner = rect.insetBy(dx: 1, dy: 1)
        let rects = segmentRects()
        DSDraw.dimmed(!isEnabled) {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: inner, xRadius: DS.radius - 1, yRadius: DS.radius - 1).addClip()
            for (index, segment) in rects.enumerated() where index == selectedIndex {
                DSDraw.fill(segment, DS.blue)
            }
            for segment in rects.dropFirst() {
                DSDraw.fill(NSRect(x: segment.minX - 1, y: inner.minY, width: 1, height: inner.height), DS.line)
            }
            NSGraphicsContext.restoreGraphicsState()
            DSDraw.border(rect, radius: DS.radius, DS.line)
            for (index, segment) in rects.enumerated() {
                let color = index == selectedIndex ? DS.onBlue : (index == hoverIndex ? DS.ink : DS.muted)
                DSText.draw(items[index], in: NSRect(x: segment.minX + 4, y: rect.minY, width: segment.width - 8, height: rect.height), font: DS.bodyFont, color: color, alignment: .center)
            }
        }
        if showsFocus { DSDraw.focusRing(rect, radius: DS.radius) }
    }

    private func rebuildAccessibility() {
        accessibilityItems = items.enumerated().map { index, title in
            let item = DSAccessibilityItem(role: .radioButton, label: title, parent: self)
            item.frameProvider = { [weak self] in
                guard let self else { return .zero }
                let rects = self.segmentRects()
                return rects.indices.contains(index) ? self.screenRect(rects[index]) : .zero
            }
            item.valueProvider = { [weak self] in NSNumber(value: self?.selectedIndex == index ? 1 : 0) }
            item.pressHandler = { [weak self] in self?.select(index) }
            return item
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }
    override func accessibilityChildren() -> [Any]? { accessibilityItems }
    override func accessibilityPerformPress() -> Bool { false }
}

final class DSCheckbox: DSControl {
    static let boxSize: CGFloat = 16

    var title: String? { didSet { if title != oldValue { contentChanged() } } }
    var isOn: Bool { didSet { if isOn != oldValue { needsDisplay = true } } }
    var onChange: ((Bool) -> Void)?

    init(_ title: String? = nil, isOn: Bool = false, label: String? = nil, onChange: ((Bool) -> Void)? = nil) {
        self.title = title
        self.isOn = isOn
        self.onChange = onChange
        super.init()
        if let label { setAccessibilityLabel(label) }
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        guard let title, !title.isEmpty else { return NSSize(width: Self.boxSize, height: Self.boxSize) }
        return NSSize(width: Self.boxSize + DS.gapTight + ceil(DSText.width(title, font: DS.bodyFont)), height: Self.boxSize)
    }

    override func activate() {
        isOn.toggle()
        onChange?(isOn)
    }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSRect(x: 0, y: ((bounds.height - Self.boxSize) / 2).rounded(), width: Self.boxSize, height: Self.boxSize)
        DSDraw.dimmed(!isEnabled) {
            if isOn {
                DSDraw.fill(box, radius: 3, DS.blue)
                DSIcon.check.draw(in: box.insetBy(dx: 1, dy: 1), color: DS.onBlue)
            } else {
                DSDraw.border(box, radius: 3, DS.edge)
            }
            if let title, !title.isEmpty {
                let x = box.maxX + DS.gapTight
                DSText.draw(title, in: NSRect(x: x, y: 0, width: bounds.width - x, height: bounds.height), font: DS.bodyFont, color: DS.text)
            }
        }
        if showsFocus { DSDraw.focusRing(box, radius: 3) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .checkBox }
    override func accessibilityValue() -> Any? { NSNumber(value: isOn ? 1 : 0) }
    override func accessibilityLabel() -> String? { super.accessibilityLabel() ?? title }
}

final class DSRadioGroup: DSControl {
    static let rowHeight: CGFloat = 16
    static let rowGap: CGFloat = 8
    static let dotSize: CGFloat = 14

    var items: [String] { didSet { rebuildAccessibility(); contentChanged() } }
    var selectedIndex: Int { didSet { if selectedIndex != oldValue { needsDisplay = true } } }
    var onChange: ((Int) -> Void)?

    private var accessibilityItems: [DSAccessibilityItem] = []

    init(_ items: [String], selectedIndex: Int = 0, label: String? = nil, onChange: ((Int) -> Void)? = nil) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.onChange = onChange
        super.init()
        if let label { setAccessibilityLabel(label) }
        rebuildAccessibility()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let widest = items.map { DSText.width($0, font: DS.bodyFont) }.max() ?? 0
        let count = CGFloat(items.count)
        return NSSize(width: Self.dotSize + 8 + ceil(widest), height: count * Self.rowHeight + max(count - 1, 0) * Self.rowGap)
    }

    private func rowRect(_ index: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(index) * (Self.rowHeight + Self.rowGap), width: bounds.width, height: Self.rowHeight)
    }

    private func select(_ index: Int) {
        guard items.indices.contains(index), index != selectedIndex else { return }
        selectedIndex = index
        onChange?(index)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        super.mouseUp(with: event)
        guard isEnabled, bounds.contains(point) else { return }
        let pitch = Self.rowHeight + Self.rowGap
        let index = Int(((point.y + Self.rowGap / 2) / pitch).rounded(.down))
        select(min(max(index, 0), items.count - 1))
    }

    override func handleKey(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 123, 126: select(max(selectedIndex - 1, 0))
        case 124, 125: select(min(selectedIndex + 1, items.count - 1))
        default: return false
        }
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.dimmed(!isEnabled) {
            for (index, title) in items.enumerated() {
                let row = rowRect(index)
                let dot = NSRect(x: 0, y: row.midY - Self.dotSize / 2, width: Self.dotSize, height: Self.dotSize)
                let selected = index == selectedIndex
                DSDraw.border(dot, radius: Self.dotSize / 2, selected ? DS.blue : DS.edge)
                if selected { DSDraw.circle(center: CGPoint(x: dot.midX, y: dot.midY), radius: 4, DS.blue) }
                let x = dot.maxX + 8
                DSText.draw(title, in: NSRect(x: x, y: row.minY, width: row.width - x, height: row.height), font: DS.bodyFont, color: DS.text)
                if selected, showsFocus { DSDraw.focusRing(dot, radius: Self.dotSize / 2) }
            }
        }
    }

    private func rebuildAccessibility() {
        accessibilityItems = items.enumerated().map { index, title in
            let item = DSAccessibilityItem(role: .radioButton, label: title, parent: self)
            item.frameProvider = { [weak self] in
                guard let self else { return .zero }
                return self.screenRect(self.rowRect(index))
            }
            item.valueProvider = { [weak self] in NSNumber(value: self?.selectedIndex == index ? 1 : 0) }
            item.pressHandler = { [weak self] in self?.select(index) }
            return item
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }
    override func accessibilityChildren() -> [Any]? { accessibilityItems }
    override func accessibilityPerformPress() -> Bool { false }
}

final class DSChip: DSControl {
    enum Style {
        case dashed
        case solid
    }

    static let height: CGFloat = 24

    var title: String { didSet { if title != oldValue { contentChanged() } } }
    var style: Style { didSet { if style != oldValue { contentChanged() } } }
    var isCopied = false { didSet { if isCopied != oldValue { needsDisplay = true } } }
    var onClick: (() -> Void)?

    init(_ title: String, style: Style = .dashed, label: String? = nil, onClick: (() -> Void)? = nil) {
        self.title = title
        self.style = style
        self.onClick = onClick
        super.init()
        if let label { setAccessibilityLabel(label) }
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let textWidth = ceil(DSText.width(title, font: DS.bodyFont))
        switch style {
        case .dashed: return NSSize(width: max(40, textWidth + 18), height: Self.height)
        case .solid: return NSSize(width: textWidth + 16, height: Self.height)
        }
    }

    override func activate() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        DSDraw.dimmed(!isEnabled) {
            var textColor = DS.text
            if isCopied {
                DSDraw.fill(rect, radius: DS.radius, DS.blue)
                textColor = DS.onBlue
            } else {
                switch style {
                case .dashed:
                    if isPressed {
                        DSDraw.fill(rect, radius: DS.radius, DS.chip)
                    } else if isHovered {
                        DSDraw.fill(rect, radius: DS.radius, DS.sunken)
                    }
                    DSDraw.dashedBorder(rect, radius: DS.radius, isHovered || isPressed ? DS.muted : DS.edge)
                case .solid:
                    DSDraw.fill(rect, radius: DS.radius, isHovered || isPressed ? DS.line : DS.chip)
                }
            }
            DSText.draw(title, in: rect.insetBy(dx: 4, dy: 0), font: DS.bodyFont, color: textColor, alignment: .center)
        }
        if showsFocus { DSDraw.focusRing(rect, radius: DS.radius) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { super.accessibilityLabel() ?? title }
}

final class DSLinkButton: DSControl {
    static let height: CGFloat = 16

    var title: String { didSet { if title != oldValue { contentChanged() } } }
    var onClick: (() -> Void)?

    init(_ title: String, onClick: (() -> Void)? = nil) {
        self.title = title
        self.onClick = onClick
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(DSText.width(title, font: DS.smallFont)), height: Self.height)
    }

    override func activate() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let font = DS.smallFont
        DSDraw.dimmed(!isEnabled) {
            let width = DSText.draw(title, in: bounds, font: font, color: isHovered || isPressed ? DS.blue : DS.muted, truncates: true)
            let baseline = DSText.baseline(top: bounds.minY, height: bounds.height, font: font)
            DSDraw.fill(NSRect(x: 0, y: baseline + 2.5, width: min(width, bounds.width), height: 1), DS.edge)
        }
        if showsFocus { DSDraw.focusRing(bounds, radius: 2) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .link }
    override func accessibilityLabel() -> String? { super.accessibilityLabel() ?? title }
}
