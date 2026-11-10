import AppKit

final class DSBubble: DSView {
    private let titleLabel: DSLabel?
    private let textLabel: DSLabel
    private var contentSize = NSSize.zero

    var maxWidth: CGFloat = 220 { didSet { arrange() } }

    var text: String {
        get { textLabel.text }
        set { textLabel.text = newValue; arrange() }
    }

    init(_ text: String, title: String? = nil) {
        textLabel = DSLabel(text, size: 11, color: DS.paper)
        titleLabel = title.map { DSLabel($0, size: 11, color: DS.alpha(DS.paper, 0.6)) }
        super.init()
        if let titleLabel {
            titleLabel.lineHeight = 16
            addSubview(titleLabel)
            textLabel.maxLines = 0
            textLabel.lineHeight = 16
        } else {
            textLabel.lineHeight = 18
        }
        addSubview(textLabel)
        arrange()
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { contentSize }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.fill(bounds, radius: DS.radius, DS.ink)
    }

    private func arrange() {
        let font = DS.font(11)
        guard let titleLabel else {
            let width = ceil(DSText.width(textLabel.text, font: font))
            contentSize = NSSize(width: width + 12, height: 18)
            textLabel.frame = NSRect(x: 6, y: 0, width: width, height: 18)
            finishArranging()
            return
        }
        let limit = maxWidth - 16
        let natural = max(DSText.width(textLabel.text, font: font), DSText.width(titleLabel.text, font: font))
        let width = ceil(min(natural, limit))
        let textHeight = textLabel.height(forWidth: width)
        titleLabel.frame = NSRect(x: 8, y: 6, width: width, height: 16)
        textLabel.frame = NSRect(x: 8, y: 22, width: width, height: textHeight)
        contentSize = NSSize(width: width + 16, height: 28 + textHeight)
        finishArranging()
    }

    private func finishArranging() {
        setFrameSize(contentSize)
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }
}
