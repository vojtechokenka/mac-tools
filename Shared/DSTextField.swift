import AppKit

final class DSFieldEditor: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        super.draw(dirtyRect)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class DSTextFieldCell: NSTextFieldCell {
    static let measure = NSLayoutManager()

    var leadingInset: CGFloat = 7
    var trailingInset: CGFloat = 7

    private var passesThrough = false
    private var editor: DSFieldEditor?

    func textRect(forBounds rect: NSRect) -> NSRect {
        let font = self.font ?? DS.bodyFont
        let lineHeight = ceil(Self.measure.defaultLineHeight(for: font))
        let baseline = DSText.baseline(top: rect.minY, height: rect.height, font: font)
        let top = baseline - Self.measure.defaultBaselineOffset(for: font).rounded()
        return NSRect(x: rect.minX + leadingInset, y: top, width: max(rect.width - leadingInset - trailingInset, 0), height: lineHeight)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let base = super.drawingRect(forBounds: rect)
        return passesThrough ? base : textRect(forBounds: base)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let target = textRect(forBounds: rect)
        passesThrough = true
        super.edit(withFrame: target, in: controlView, editor: textObj, delegate: delegate, event: event)
        passesThrough = false
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let target = textRect(forBounds: rect)
        passesThrough = true
        super.select(withFrame: target, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
        passesThrough = false
    }

    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if let editor { return editor }
        let created = DSFieldEditor(frame: .zero)
        created.isFieldEditor = true
        created.isRichText = false
        created.drawsBackground = false
        created.allowsUndo = true
        created.usesFontPanel = false
        editor = created
        return created
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        super.drawInterior(withFrame: cellFrame, in: controlView)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class DSTextField: NSTextField {
    static let height: CGFloat = 28

    var unit: String? { didSet { updateInsets() } }
    var showsFocusStyle = false { didSet { needsDisplay = true } }
    var onChange: ((String) -> Void)?
    var onSubmit: ((String) -> Void)? {
        didSet {
            target = self
            action = #selector(submitted)
        }
    }

    override class var cellClass: AnyClass? {
        get { DSTextFieldCell.self }
        set {}
    }

    init(placeholder: String = "", text: String = "") {
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: Self.height))
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        cell?.wraps = false
        cell?.isScrollable = true
        cell?.allowsUndo = true
        cell?.sendsActionOnEndEditing = false
        font = DS.bodyFont
        textColor = DS.text
        stringValue = text
        placeholderString = placeholder
    }

    required init?(coder: NSCoder) { nil }

    override var placeholderString: String? {
        didSet { stylePlaceholder() }
    }

    override var font: NSFont? {
        didSet { stylePlaceholder() }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: Self.height)
    }

    var isFocused: Bool { currentEditor() != nil }

    private func stylePlaceholder() {
        guard let placeholderString, !placeholderString.isEmpty else {
            placeholderAttributedString = nil
            return
        }
        placeholderAttributedString = NSAttributedString(string: placeholderString, attributes: [.font: font ?? DS.bodyFont, .foregroundColor: DS.icon])
    }

    private func updateInsets() {
        if let cell = cell as? DSTextFieldCell {
            if let unit, !unit.isEmpty {
                cell.trailingInset = 8 + ceil(DSText.width(unit, font: DS.bodyFont)) + 4
            } else {
                cell.trailingInset = 7
            }
        }
        needsDisplay = true
    }

    @objc private func submitted() {
        onSubmit?(stringValue)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        needsDisplay = true
        return accepted
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onChange?(stringValue)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.dimmed(!isEnabled) {
            DSDraw.border(bounds, radius: DS.radius, showsFocusStyle || isFocused ? DS.blue : DS.line)
            if let unit, !unit.isEmpty {
                let width = DSText.width(unit, font: DS.bodyFont)
                DSText.draw(unit, in: NSRect(x: bounds.maxX - 8 - width, y: 0, width: width, height: bounds.height), font: DS.bodyFont, color: DS.muted, truncates: false)
            }
        }
        super.draw(dirtyRect)
    }
}
