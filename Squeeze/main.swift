import AppKit
import UniformTypeIdentifiers
import UserNotifications

enum Settings {
    private static let defaults = UserDefaults.standard

    static var format: OutputFormat {
        get { OutputFormat(rawValue: defaults.string(forKey: "format") ?? "") ?? .webp }
        set { defaults.set(newValue.rawValue, forKey: "format") }
    }

    static var quality: Int {
        get { defaults.object(forKey: "quality") == nil ? 80 : min(max(defaults.integer(forKey: "quality"), 1), 100) }
        set { defaults.set(newValue, forKey: "quality") }
    }

    static var maxEdge: Int {
        get { defaults.object(forKey: "maxEdge") == nil ? 1920 : max(defaults.integer(forKey: "maxEdge"), 0) }
        set { defaults.set(newValue, forKey: "maxEdge") }
    }

    static var destinationMode: String {
        get { defaults.string(forKey: "destination") ?? "subfolder" }
        set { defaults.set(newValue, forKey: "destination") }
    }

    static var chosenFolder: URL? {
        get { defaults.string(forKey: "chosenFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { defaults.set(newValue?.path, forKey: "chosenFolder") }
    }

    static var groupIntoSubfolder: Bool {
        get { defaults.object(forKey: "groupIntoSubfolder") == nil ? true : defaults.bool(forKey: "groupIntoSubfolder") }
        set { defaults.set(newValue, forKey: "groupIntoSubfolder") }
    }

    static var destination: Destination {
        switch destinationMode {
        case "replace": return .replace
        case "folder":
            guard let folder = chosenFolder else { return .subfolder }
            return .folder(groupIntoSubfolder ? folder.appendingPathComponent(ImageCollector.outputFolderName, isDirectory: true) : folder)
        default: return .subfolder
        }
    }

    static var pattern: String = NamePlanner.defaultPattern

    static var startNumber: Int {
        get { defaults.object(forKey: "startNumber") == nil ? 1 : max(defaults.integer(forKey: "startNumber"), 0) }
        set { defaults.set(newValue, forKey: "startNumber") }
    }

    static var options: OptimizeOptions {
        OptimizeOptions(format: format, quality: quality, maxEdge: maxEdge, destination: destination, pattern: pattern, startNumber: startNumber)
    }
}

enum DragHelper {
    static func urls(from info: NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return objects.filter { ImageCollector.accepts($0) }
    }
}

final class PillButton: NSView {
    var title = "" { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var isPrimary = true { didSet { needsDisplay = true } }
    var isEnabled = true { didSet { needsDisplay = true } }
    var fontSize: CGFloat = 12 { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }
    var horizontalPadding: CGFloat = 16 { didSet { invalidateIntrinsicContentSize() } }
    var height: CGFloat = 28 { didSet { invalidateIntrinsicContentSize() } }
    var onClick: (() -> Void)?
    private var hovered = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?

    init(title: String, primary: Bool = true) {
        self.title = title
        self.isPrimary = primary
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    private var font: NSFont { .systemFont(ofSize: fontSize, weight: .semibold) }

    override var intrinsicContentSize: NSSize {
        let width = ceil(NSAttributedString(string: title, attributes: [.font: font]).size().width) + horizontalPadding * 2
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        let base = NSColor.labelColor
        var fill: NSColor = isPrimary ? base.withAlphaComponent(0.85) : base.withAlphaComponent(0.12)
        if !isEnabled { fill = base.withAlphaComponent(0.08) }
        else if pressed { fill = isPrimary ? base.withAlphaComponent(0.7) : base.withAlphaComponent(0.3) }
        else if hovered { fill = isPrimary ? base : base.withAlphaComponent(0.2) }
        fill.setFill()
        path.fill()
        let textColor: NSColor = !isEnabled ? .tertiaryLabelColor : (isPrimary ? .windowBackgroundColor : base)
        let label = NSAttributedString(string: title, attributes: [.font: font, .foregroundColor: textColor])
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

final class FileRowView: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("FileRow")
    let nameLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .right
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(nameLabel)
        addSubview(detailLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: nameLabel.trailingAnchor, constant: 8),
        ])
    }

    required init?(coder: NSCoder) { nil }
}

final class DropZoneView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onOpen: (() -> Void)?
    var highlighted = false { didSet { needsDisplay = true } }
    let summaryLabel = NSTextField(labelWithString: "")
    let tableView = NSTableView()
    private let placeholder = NSStackView()
    private let list = NSStackView()
    private let scrollView = NSScrollView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        registerForDraggedTypes([.fileURL])

        let title = NSTextField(labelWithString: "Drop images or folders here")
        title.font = .systemFont(ofSize: 14, weight: .medium)
        title.textColor = .secondaryLabelColor
        let hint = NSTextField(labelWithString: "JPEG, PNG, HEIC, TIFF, GIF, WebP, AVIF, BMP")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .tertiaryLabelColor
        let open = PillButton(title: "Open files…", primary: false)
        open.onClick = { [weak self] in self?.onOpen?() }
        placeholder.orientation = .vertical
        placeholder.alignment = .centerX
        placeholder.spacing = 6
        placeholder.setViews([title, hint, open], in: .center)
        placeholder.setCustomSpacing(14, after: hint)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholder)

        summaryLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        tableView.headerView = nil
        tableView.rowHeight = 22
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .plain
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 6
        list.distribution = .fill
        summaryLabel.setContentHuggingPriority(.required, for: .vertical)
        scrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        let addButton = PillButton(title: "Add images…", primary: false)
        addButton.onClick = { [weak self] in self?.onOpen?() }
        let header = NSStackView(views: [summaryLabel, addButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.distribution = .fill
        summaryLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        addButton.setContentHuggingPriority(.required, for: .horizontal)
        header.translatesAutoresizingMaskIntoConstraints = false
        list.setViews([header, scrollView], in: .top)
        list.translatesAutoresizingMaskIntoConstraints = false
        list.isHidden = true
        addSubview(list)

        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: centerYAnchor),
            list.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            list.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            list.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            list.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            scrollView.widthAnchor.constraint(equalTo: list.widthAnchor),
            header.widthAnchor.constraint(equalTo: list.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func showList(_ show: Bool) {
        list.isHidden = !show
        placeholder.isHidden = show
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)
        let accent = NSColor.controlAccentColor
        if highlighted {
            accent.withAlphaComponent(0.08).setFill()
        } else {
            NSColor.labelColor.withAlphaComponent(list.isHidden ? 0.03 : 0.05).setFill()
        }
        path.fill()
        path.lineWidth = 1.5
        if list.isHidden || highlighted {
            path.setLineDash([5, 4], count: 2, phase: 0)
        }
        (highlighted ? accent : NSColor.labelColor.withAlphaComponent(0.25)).setStroke()
        path.stroke()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = !DragHelper.urls(from: sender).isEmpty
        highlighted = accepted
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { highlighted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { highlighted = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        highlighted = false
        let urls = DragHelper.urls(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

final class RootDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onHighlight: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = !DragHelper.urls(from: sender).isEmpty
        onHighlight?(accepted)
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onHighlight?(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onHighlight?(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHighlight?(false)
        let urls = DragHelper.urls(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

final class StatusDropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        DragHelper.urls(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = DragHelper.urls(from: sender)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }

    override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }
    override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
    override func rightMouseUp(with event: NSEvent) { superview?.rightMouseUp(with: event) }
    override func otherMouseDown(with event: NSEvent) { superview?.otherMouseDown(with: event) }
    override func otherMouseUp(with event: NSEvent) { superview?.otherMouseUp(with: event) }
}

final class SqueezeWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate {
    struct Item {
        let url: URL
        let bytes: Int
        var report: FileReport?
    }

    enum State {
        case idle
        case running
        case finished(BatchReport)
    }

    var onNotify: ((String) -> Void)?
    private(set) var items: [Item] = []
    private var state = State.idle
    private let optimizer = Optimizer()
    private let contentWidth: CGFloat = 420

    private let dropZone = DropZoneView()
    private let formatPopup = NSPopUpButton()
    private let qualitySlider = NSSlider(value: 80, minValue: 1, maxValue: 100, target: nil, action: nil)
    private let qualityLabel = NSTextField(labelWithString: "80")
    private var qualityRows: [NSView] = []
    private let maxEdgeField = NSTextField(string: "1920")
    private let subfolderRadio = NSButton(radioButtonWithTitle: "Next to originals (optimized/ subfolder)", target: nil, action: nil)
    private let replaceRadio = NSButton(radioButtonWithTitle: "Replace originals (moved to Trash)", target: nil, action: nil)
    private let folderRadio = NSButton(radioButtonWithTitle: "Choose folder…", target: nil, action: nil)
    private let folderLabel = NSTextField(labelWithString: "")
    private let groupCheckbox = NSButton(checkboxWithTitle: "Group into \"optimized\" subfolder", target: nil, action: nil)
    private var lastPatternSelection: NSRange?
    private let patternField = NSTextField(string: NamePlanner.defaultPattern)
    private let startField = NSTextField(string: "1")
    private let previewLabel = NSTextField(labelWithString: "")
    private let optionsStack = NSStackView()

    private let idleBar = NSStackView()
    private let runningBar = NSStackView()
    private let finishedBar = NSStackView()
    private let optimizeButton = PillButton(title: "Optimize")
    private let cancelButton = PillButton(title: "Cancel", primary: false)
    private let stopButton = PillButton(title: "Cancel", primary: false)
    private let progressBar = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let revealButton = PillButton(title: "Show in Finder", primary: false)
    private let doneButton = PillButton(title: "Done")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 520), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Squeeze"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildContent()
        loadSettings()
        applyState()
        if !window.setFrameUsingName("SqueezeWindow") { window.center() }
        window.setFrameAutosaveName("SqueezeWindow")
        if let content = window.contentView {
            content.layoutSubtreeIfNeeded()
            window.setContentSize(content.fittingSize)
        }
    }

    required init?(coder: NSCoder) { nil }

    private func buildContent() {
        let root = RootDropView()
        root.onDrop = { [weak self] urls in self?.add(urls) }
        root.onHighlight = { [weak self] on in self?.dropZone.highlighted = on }
        dropZone.onDrop = { [weak self] urls in self?.add(urls) }
        dropZone.onOpen = { [weak self] in self?.openFiles() }
        dropZone.tableView.dataSource = self
        dropZone.tableView.delegate = self
        dropZone.heightAnchor.constraint(equalToConstant: 176).isActive = true

        for format in OutputFormat.allCases {
            formatPopup.addItem(withTitle: format.title)
            formatPopup.lastItem?.representedObject = format.rawValue
        }
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)

        qualitySlider.target = self
        qualitySlider.action = #selector(qualityChanged)
        qualitySlider.isContinuous = true
        qualityLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        qualityLabel.alignment = .right
        qualityLabel.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let qualityRow = NSStackView(views: [qualitySlider, qualityLabel])
        qualityRow.orientation = .horizontal
        qualityRow.spacing = 6

        configureNumberField(maxEdgeField, width: 64)
        let pxLabel = NSTextField(labelWithString: "px")
        pxLabel.textColor = .secondaryLabelColor
        let keepLabel = NSTextField(labelWithString: "0 keeps the original size")
        keepLabel.font = .systemFont(ofSize: 11)
        keepLabel.textColor = .tertiaryLabelColor
        let edgeRow = NSStackView(views: [maxEdgeField, pxLabel])
        edgeRow.orientation = .horizontal
        edgeRow.spacing = 6
        edgeRow.setContentHuggingPriority(.required, for: .horizontal)

        let qualityHeading = Self.heading("Quality")
        qualityRows = [qualityHeading, qualityRow]
        let left = NSStackView(views: [Self.heading("Format"), formatPopup, qualityHeading, qualityRow, Self.heading("Max long edge"), edgeRow, keepLabel])
        left.orientation = .vertical
        left.alignment = .leading
        left.spacing = 6
        left.setCustomSpacing(12, after: formatPopup)
        left.setCustomSpacing(12, after: qualityRow)
        left.setCustomSpacing(3, after: edgeRow)
        left.widthAnchor.constraint(equalToConstant: 154).isActive = true
        formatPopup.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true
        qualityRow.widthAnchor.constraint(equalTo: left.widthAnchor).isActive = true

        for radio in [subfolderRadio, replaceRadio, folderRadio] {
            radio.target = self
            radio.action = #selector(destinationChanged(_:))
            radio.font = .systemFont(ofSize: 12)
        }
        folderLabel.font = .systemFont(ofSize: 11)
        folderLabel.textColor = .secondaryLabelColor
        folderLabel.lineBreakMode = .byTruncatingMiddle
        folderLabel.maximumNumberOfLines = 1
        folderLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(folderLabelClicked)))
        groupCheckbox.font = .systemFont(ofSize: 12)
        groupCheckbox.target = self
        groupCheckbox.action = #selector(groupChanged)
        let folderDetails = NSStackView(views: [folderLabel, groupCheckbox])
        folderDetails.orientation = .vertical
        folderDetails.alignment = .leading
        folderDetails.spacing = 4
        folderDetails.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        let right = NSStackView(views: [Self.heading("Destination"), subfolderRadio, replaceRadio, folderRadio, folderDetails])
        right.orientation = .vertical
        right.alignment = .leading
        right.spacing = 6
        right.setContentHuggingPriority(.required, for: .vertical)

        let columns = NSStackView(views: [left, right])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 16
        columns.distribution = .fill
        right.setContentHuggingPriority(.defaultLow, for: .horizontal)

        patternField.delegate = self
        patternField.font = .systemFont(ofSize: 12)
        patternField.placeholderString = NamePlanner.defaultPattern
        configureNumberField(startField, width: 52)
        let startLabel = NSTextField(labelWithString: "Start from")
        startLabel.font = .systemFont(ofSize: 12)
        startLabel.textColor = .secondaryLabelColor
        let patternRow = NSStackView(views: [patternField, startLabel, startField])
        patternRow.orientation = .horizontal
        patternRow.spacing = 6
        patternField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let chips = NSStackView()
        chips.orientation = .horizontal
        chips.spacing = 6
        chips.setContentHuggingPriority(.required, for: .horizontal)
        let reset = PillButton(title: "Default", primary: false)
        reset.fontSize = 11
        reset.height = 22
        reset.horizontalPadding = 10
        reset.toolTip = "Reset to opt-{name}"
        reset.onClick = { [weak self] in
            guard let self else { return }
            self.patternField.stringValue = NamePlanner.defaultPattern
            Settings.pattern = NamePlanner.defaultPattern
            self.lastPatternSelection = nil
            self.updatePreview()
        }
        chips.addArrangedSubview(reset)
        for (title, token) in [("Current name", "{name}"), ("Number ↑", "{n}"), ("Number ↓", "{n-}")] {
            let chip = PillButton(title: title, primary: false)
            chip.fontSize = 11
            chip.height = 22
            chip.horizontalPadding = 10
            chip.toolTip = "Insert \(token)"
            chip.onClick = { [weak self] in self?.insertToken(token) }
            chips.addArrangedSubview(chip)
        }
        previewLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        previewLabel.textColor = .secondaryLabelColor
        previewLabel.lineBreakMode = .byTruncatingMiddle
        let rename = NSStackView(views: [Self.heading("Rename"), patternRow, chips, previewLabel])
        rename.orientation = .vertical
        rename.alignment = .leading
        rename.spacing = 6

        optionsStack.orientation = .vertical
        optionsStack.alignment = .leading
        optionsStack.spacing = 14
        optionsStack.setViews([columns, rename], in: .top)

        buildBottomBars()
        let bottom = NSView()
        bottom.translatesAutoresizingMaskIntoConstraints = false
        for bar in [idleBar, runningBar, finishedBar] {
            bar.translatesAutoresizingMaskIntoConstraints = false
            bottom.addSubview(bar)
            NSLayoutConstraint.activate([
                bar.leadingAnchor.constraint(equalTo: bottom.leadingAnchor),
                bar.trailingAnchor.constraint(equalTo: bottom.trailingAnchor),
                bar.bottomAnchor.constraint(equalTo: bottom.bottomAnchor),
            ])
        }
        bottom.heightAnchor.constraint(equalToConstant: 60).isActive = true

        let stack = NSStackView(views: [dropZone, optionsStack, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 14, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        let inner = contentWidth - 32
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.widthAnchor.constraint(equalToConstant: contentWidth),
            dropZone.widthAnchor.constraint(equalToConstant: inner),
            columns.widthAnchor.constraint(equalToConstant: inner),
            rename.widthAnchor.constraint(equalToConstant: inner),
            patternRow.widthAnchor.constraint(equalToConstant: inner),
            previewLabel.widthAnchor.constraint(equalToConstant: inner),
            bottom.widthAnchor.constraint(equalToConstant: inner),
        ])
        window?.contentView = root
    }

    private func buildBottomBars() {
        optimizeButton.onClick = { [weak self] in self?.startBatch() }
        cancelButton.onClick = { [weak self] in self?.clearAndClose() }
        idleBar.orientation = .horizontal
        idleBar.spacing = 8
        idleBar.setViews([cancelButton, optimizeButton], in: .trailing)

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        progressLabel.alignment = .right
        progressLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
        stopButton.onClick = { [weak self] in self?.optimizer.cancel() }
        runningBar.orientation = .horizontal
        runningBar.spacing = 10
        runningBar.setViews([progressBar, progressLabel, stopButton], in: .leading)
        progressBar.setContentHuggingPriority(.defaultLow, for: .horizontal)

        summaryLabel.font = .systemFont(ofSize: 12, weight: .medium)
        summaryLabel.lineBreakMode = .byTruncatingMiddle
        revealButton.onClick = { [weak self] in self?.revealOutputs() }
        doneButton.onClick = { [weak self] in self?.reset() }
        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.setViews([revealButton, doneButton], in: .trailing)
        finishedBar.orientation = .vertical
        finishedBar.alignment = .leading
        finishedBar.spacing = 8
        finishedBar.setViews([summaryLabel, buttons], in: .top)
        buttons.widthAnchor.constraint(equalTo: finishedBar.widthAnchor).isActive = true
        summaryLabel.widthAnchor.constraint(equalTo: finishedBar.widthAnchor).isActive = true
    }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        return label
    }

    private func configureNumberField(_ field: NSTextField, width: CGFloat) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 100_000
        formatter.allowsFloats = false
        field.formatter = formatter
        field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.alignment = .right
        field.delegate = self
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func loadSettings() {
        formatPopup.selectItem(at: OutputFormat.allCases.firstIndex(of: Settings.format) ?? 0)
        qualitySlider.integerValue = Settings.quality
        qualityLabel.stringValue = "\(Settings.quality)"
        maxEdgeField.stringValue = "\(Settings.maxEdge)"
        syncDestinationControls()
        patternField.stringValue = Settings.pattern
        startField.stringValue = "\(Settings.startNumber)"
        updateQualityVisibility()
        updatePreview()
    }

    private var selectedFormat: OutputFormat {
        OutputFormat(rawValue: formatPopup.selectedItem?.representedObject as? String ?? "") ?? .webp
    }

    private func updateQualityVisibility() {
        let hidden = selectedFormat == .png
        for view in qualityRows { view.isHidden = hidden }
    }

    private func updatePreview() {
        let names = items.map { $0.url.deletingPathExtension().lastPathComponent }
        previewLabel.stringValue = "→ " + NamePlanner.preview(names: names, pattern: Settings.pattern, start: Settings.startNumber, format: Settings.format)
    }

    @objc private func formatChanged() {
        Settings.format = selectedFormat
        updateQualityVisibility()
        updatePreview()
    }

    @objc private func qualityChanged() {
        Settings.quality = qualitySlider.integerValue
        qualityLabel.stringValue = "\(qualitySlider.integerValue)"
    }

    @objc private func destinationChanged(_ sender: NSButton) {
        if sender === folderRadio {
            if Settings.chosenFolder == nil {
                chooseFolder()
            } else {
                Settings.destinationMode = "folder"
            }
        } else {
            Settings.destinationMode = sender === replaceRadio ? "replace" : "subfolder"
        }
        syncDestinationControls()
    }

    @objc private func groupChanged() {
        Settings.groupIntoSubfolder = groupCheckbox.state == .on
        syncDestinationControls()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = Settings.chosenFolder
        show()
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard let self else { return }
            if response == .OK, let url = panel.url {
                Settings.chosenFolder = url
                Settings.destinationMode = "folder"
            }
            self.syncDestinationControls()
        }
    }

    private func syncDestinationControls() {
        let mode = Settings.destinationMode
        subfolderRadio.state = mode == "subfolder" ? .on : .off
        replaceRadio.state = mode == "replace" ? .on : .off
        folderRadio.state = mode == "folder" ? .on : .off
        let folder = Settings.chosenFolder
        folderRadio.title = folder == nil ? "Choose folder…" : "Folder"
        folderLabel.stringValue = folder.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") + "  (change…)" } ?? ""
        folderLabel.isHidden = folder == nil
        groupCheckbox.isHidden = folder == nil
        groupCheckbox.isEnabled = mode == "folder"
        groupCheckbox.state = Settings.groupIntoSubfolder ? .on : .off
        updatePreview()
    }

    @objc private func folderLabelClicked() { chooseFolder() }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === patternField {
            Settings.pattern = patternField.stringValue
            if let editor = patternField.currentEditor() as? NSTextView { lastPatternSelection = editor.selectedRange() }
            updatePreview()
        } else if field === startField {
            Settings.startNumber = Int(startField.stringValue.filter(\.isNumber)) ?? 1
            updatePreview()
        } else if field === maxEdgeField {
            Settings.maxEdge = Int(maxEdgeField.stringValue.filter(\.isNumber)) ?? 0
        }
    }

    func control(_ control: NSControl, didFailToFormatString string: String, errorDescription error: String?) -> Bool { true }

    private func insertToken(_ token: String) {
        let current = patternField.stringValue as NSString
        var range = lastPatternSelection ?? NSRange(location: current.length, length: 0)
        if range.location + range.length > current.length || (range.length == current.length && current.length > 0) {
            range = NSRange(location: current.length, length: 0)
        }
        let updated = current.replacingCharacters(in: range, with: token)
        patternField.stringValue = updated
        Settings.pattern = updated
        let caret = NSRange(location: range.location + (token as NSString).length, length: 0)
        window?.makeFirstResponder(patternField)
        if let editor = patternField.currentEditor() as? NSTextView { editor.setSelectedRange(caret) }
        lastPatternSelection = caret
        updatePreview()
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard notification.object as? NSTextField === patternField else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(patternSelectionChanged(_:)), name: NSTextView.didChangeSelectionNotification, object: patternField.currentEditor())
    }

    @objc private func patternSelectionChanged(_ notification: Notification) {
        guard let editor = notification.object as? NSTextView, editor === patternField.currentEditor() else { return }
        lastPatternSelection = editor.selectedRange()
    }

    func add(_ urls: [URL]) {
        if case .running = state {
            NSSound.beep()
            return
        }
        if case .finished = state {
            items = []
            state = .idle
        }
        let existing = Set(items.map { $0.url.standardizedFileURL.path.lowercased() })
        let files = ImageCollector.collect(urls).filter { !existing.contains($0.standardizedFileURL.path.lowercased()) }
        for file in files {
            let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            items.append(Item(url: file, bytes: bytes))
        }
        log("added \(files.count) files, batch has \(items.count)")
        dropZone.tableView.reloadData()
        applyState()
        updatePreview()
        show()
    }

    func openFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .folder]
        panel.prompt = "Add"
        show()
        panel.beginSheetModal(for: window!) { [weak self] response in
            guard response == .OK else { return }
            self?.add(panel.urls)
        }
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func applyState() {
        var idle = false, running = false, finished = false
        switch state {
        case .idle: idle = true
        case .running: running = true
        case .finished: finished = true
        }
        idleBar.isHidden = !idle
        runningBar.isHidden = !running
        finishedBar.isHidden = !finished
        optimizeButton.isEnabled = !items.isEmpty
        optionsStack.alphaValue = running ? 0.5 : 1
        dropZone.showList(!items.isEmpty)
        let total = items.reduce(0) { $0 + $1.bytes }
        dropZone.summaryLabel.stringValue = "\(items.count) \(items.count == 1 ? "image" : "images") · \(Format.bytes(total))"
    }

    private func startBatch() {
        guard !items.isEmpty, !optimizer.isRunning else { return }
        window?.makeFirstResponder(nil)
        let options = Settings.options
        state = .running
        progressBar.maxValue = Double(items.count)
        progressBar.doubleValue = 0
        progressLabel.stringValue = "0 / \(items.count)"
        applyState()
        log("starting batch of \(items.count) → \(options.format.title)")
        optimizer.run(files: items.map(\.url), options: options, progress: { [weak self] completed, total, report in
            guard let self else { return }
            if let index = self.items.firstIndex(where: { $0.url == report.source }) {
                self.items[index].report = report
                self.dropZone.tableView.reloadData(forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0))
            }
            self.progressBar.doubleValue = Double(completed)
            self.progressLabel.stringValue = "\(completed) / \(total)"
        }, completion: { [weak self] report in
            guard let self else { return }
            self.state = .finished(report)
            self.summaryLabel.stringValue = report.summary
            self.summaryLabel.toolTip = report.summary
            self.revealButton.isEnabled = !report.outputs.isEmpty
            self.applyState()
            if self.window?.isKeyWindow != true { self.onNotify?(report.summary) }
        })
    }

    private func revealOutputs() {
        guard case .finished(let report) = state, !report.outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(report.outputs)
    }

    private func reset() {
        items = []
        state = .idle
        dropZone.tableView.reloadData()
        applyState()
        updatePreview()
    }

    private func clearAndClose() {
        reset()
        window?.close()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = tableView.makeView(withIdentifier: FileRowView.identifier, owner: nil) as? FileRowView ?? FileRowView(frame: .zero)
        let item = items[row]
        view.nameLabel.stringValue = item.url.lastPathComponent
        view.nameLabel.toolTip = item.url.path
        if let report = item.report {
            if let error = report.error {
                view.detailLabel.stringValue = "\(Format.bytes(item.bytes)) → failed"
                view.detailLabel.textColor = .systemRed
                view.detailLabel.toolTip = error
            } else {
                view.detailLabel.stringValue = "\(Format.bytes(item.bytes)) → \(Format.bytes(report.newBytes)) (\(Format.change(from: item.bytes, to: report.newBytes)))"
                view.detailLabel.textColor = .secondaryLabelColor
                view.detailLabel.toolTip = report.output?.path
            }
        } else {
            view.detailLabel.stringValue = "\(Format.bytes(item.bytes)) → …"
            view.detailLabel.textColor = .secondaryLabelColor
            view.detailLabel.toolTip = nil
        }
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let controller = SqueezeWindowController()

    private static let iconSVG = "<svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"24\" height=\"24\" fill=\"white\" fill-opacity=\"0.25\"/><path transform=\"translate(12 12) scale(0.72) translate(-12 -12) translate(3 3)\" fill-rule=\"evenodd\" clip-rule=\"evenodd\" fill=\"white\" d=\"M18 2C18 0.9 17.1 0 16 0H2C0.9 0 0 0.9 0 2V16C0 17.1 0.9 18 2 18H16C17.1 18 18 17.1 18 16V2ZM3 14L6 10L7 11L10 7L15 14H3Z\"/></svg>"

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(data: Data(iconSVG.utf8)) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Squeeze"
        return image
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let drop = StatusDropView(frame: button.bounds)
            drop.onDrop = { [weak self] urls in self?.controller.add(urls) }
            drop.translatesAutoresizingMaskIntoConstraints = false
            button.addSubview(drop)
            NSLayoutConstraint.activate([
                drop.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                drop.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                drop.topAnchor.constraint(equalTo: button.topAnchor),
                drop.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            ])
        }
        controller.onNotify = { [weak self] summary in self?.notify(summary) }
        log("started")
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        controller.add(filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    @objc private func statusItemClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            if controller.window?.isVisible == true, controller.window?.isKeyWindow == true {
                controller.window?.close()
            } else {
                controller.show()
            }
            return
        }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open files…", action: #selector(openFiles), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func openFiles() { controller.openFiles() }
    @objc private func openSettings() { controller.show() }

    private func notify(_ summary: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let post = {
            let content = UNMutableNotificationContent()
            content.title = "Squeeze"
            content.body = summary
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
                if let error { log("notification failed: \(error.localizedDescription)") }
            }
        }
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in if granted { post() } }
            case .authorized, .provisional:
                post()
            default:
                break
            }
        }
    }
}

if CommandLine.arguments.dropFirst().first == "--cli" {
    exit(CLI.run(Array(CommandLine.arguments.dropFirst(2))))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
