import AppKit
import UniformTypeIdentifiers
import UserNotifications

enum Settings {
    private static let defaults = UserDefaults.standard
    static var memory: [String: Any]?

    private static func object(_ key: String) -> Any? {
        if let memory { return memory[key] }
        return defaults.object(forKey: key)
    }

    private static func string(_ key: String) -> String? { object(key) as? String }
    private static func integer(_ key: String) -> Int { (object(key) as? NSNumber)?.intValue ?? 0 }
    private static func bool(_ key: String) -> Bool { (object(key) as? NSNumber)?.boolValue ?? false }

    private static func set(_ value: Any?, _ key: String) {
        if memory != nil {
            memory?[key] = value
        } else {
            defaults.set(value, forKey: key)
        }
    }

    static var format: OutputFormat {
        get { OutputFormat(rawValue: string("format") ?? "") ?? .webp }
        set { set(newValue.rawValue, "format") }
    }

    static var quality: Int {
        get { object("quality") == nil ? 80 : min(max(integer("quality"), 1), 100) }
        set { set(newValue, "quality") }
    }

    static var maxEdge: Int {
        get { object("maxEdge") == nil ? 1920 : max(integer("maxEdge"), 0) }
        set { set(newValue, "maxEdge") }
    }

    static var pdfDpi: PDFResolution {
        get { PDFResolution(rawValue: string("pdfDpi") ?? "") ?? .dpi150 }
        set { set(newValue.rawValue, "pdfDpi") }
    }

    static var destinationMode: String {
        get { string("destination") ?? "subfolder" }
        set { set(newValue, "destination") }
    }

    static var chosenFolder: URL? {
        get { string("chosenFolder").map { URL(fileURLWithPath: $0, isDirectory: true) } }
        set { set(newValue?.path, "chosenFolder") }
    }

    static var groupIntoSubfolder: Bool {
        get { object("groupIntoSubfolder") == nil ? true : bool("groupIntoSubfolder") }
        set { set(newValue, "groupIntoSubfolder") }
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
        get { object("startNumber") == nil ? 1 : max(integer("startNumber"), 0) }
        set { set(newValue, "startNumber") }
    }

    static var options: OptimizeOptions {
        OptimizeOptions(format: format, quality: quality, maxEdge: maxEdge, pdfDpi: pdfDpi, destination: destination, pattern: pattern, startNumber: startNumber)
    }
}

enum DragHelper {
    static func urls(from info: NSDraggingInfo) -> [URL] {
        let objects = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return objects.filter { ImageCollector.accepts($0) }
    }

    static func title(for urls: [URL]) -> String {
        if urls.contains(where: { ImageCollector.isDirectory($0) }) {
            return "\(urls.count) \(urls.count == 1 ? "item" : "items")"
        }
        return Format.count(urls.count, images: !urls.contains { ImageCollector.isPDF($0) })
    }
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class InfoButton: DSControl {
    var onHoverChange: ((Bool) -> Void)?
    private var wasShowing = false

    init(label: String) {
        super.init()
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: DS.iconButtonSize, height: DS.iconButtonSize) }

    private var isShowing: Bool { isHovered || showsFocus }

    override func stateChanged() {
        super.stateChanged()
        notify()
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        notify()
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        notify()
        return accepted
    }

    private func notify() {
        let showing = isShowing
        guard showing != wasShowing else { return }
        wasShowing = showing
        needsDisplay = true
        onHoverChange?(showing)
    }

    override func draw(_ dirtyRect: NSRect) {
        let side: CGFloat = 16
        let rect = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        DSIcon.info.draw(in: rect, color: isShowing ? DS.blue : DS.icon)
        if showsFocus { DSDraw.focusRing(bounds, radius: DS.radius) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
}

final class DropZoneView: DSControl {
    static let formatsText = "JPEG, PNG, HEIC, TIFF, GIF, WebP, AVIF, BMP and PDF"
    static let minHeight: CGFloat = 112
    static let restTitle = "Drop images, PDFs or folders here"

    var onClick: (() -> Void)?
    var dragTitle: String? { didSet { updateContent() } }
    let info = InfoButton(label: "Supported formats")

    private let title = DSLabel(DropZoneView.restTitle)
    private let detail = DSLabel("or click to browse", color: DS.muted)

    override init() {
        super.init()
        setAccessibilityLabel("Add files")
        info.setAccessibilityHelp(Self.formatsText)
        title.alignment = .center
        detail.alignment = .center
        for view in [title, detail, info] { addSubview(view) }
        updateContent()
    }

    required init?(coder: NSCoder) { nil }

    private var isOver: Bool { dragTitle != nil }

    func height(forWidth width: CGFloat) -> CGFloat { Self.minHeight }

    private func updateContent() {
        title.text = dragTitle ?? Self.restTitle
        detail.text = isOver ? "Release to add them to the batch" : "or click to browse"
        info.isHidden = isOver
        layoutContent()
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    private func layoutContent() {
        let inner = max(bounds.width - 48, 1)
        let top = ((bounds.height - 38) / 2).rounded()
        title.frame = NSRect(x: 24, y: top, width: inner, height: 16)
        detail.frame = NSRect(x: 24, y: top + 22, width: inner, height: 16)
        info.frame = NSRect(x: bounds.width - 8 - DS.iconButtonSize, y: 8, width: DS.iconButtonSize, height: DS.iconButtonSize)
    }

    override func activate() {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        if isOver {
            DSDraw.fill(bounds, radius: DS.radius, DS.blueWash)
            DSDraw.border(bounds, radius: DS.radius, DS.blue)
        } else if isHovered || isPressed {
            DSDraw.fill(bounds, radius: DS.radius, DS.sunken)
            DSDraw.dashedBorder(bounds, radius: DS.radius, DS.edge)
        } else {
            DSDraw.dashedBorder(bounds, radius: DS.radius, DS.line)
        }
        if showsFocus { DSDraw.focusRing(bounds, radius: DS.radius) }
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
}

final class DropOverlayView: FlippedView {
    override func draw(_ dirtyRect: NSRect) {
        DSDraw.fill(bounds, radius: DS.radius, DS.blueWash)
        DSDraw.border(bounds, radius: DS.radius, DS.blue)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class FileRowView: FlippedView {
    static let height: CGFloat = 55

    enum Phase {
        case idle
        case running
        case finished
    }

    var onReplace: (() -> Void)?
    var onRemove: (() -> Void)?
    var actionsEnabled = true { didSet { updateActions() } }
    var forcesHover = false { didSet { updateActions() } }

    private let typeTag = DSTag("", icon: .image, minWidth: 52)
    private let name = DSLabel()
    private let details = DSLabel("", size: 11, color: DS.muted)
    private let result = DSLabel()
    private let replaceButton = DSIconButton(.replay, label: "Replace file")
    private let removeButton = DSIconButton(.close, label: "Remove from list")
    private var hovered = false
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        typeTag.isMuted = true
        result.alignment = .right
        replaceButton.toolTip = "Replace file"
        removeButton.toolTip = "Remove from list"
        replaceButton.onClick = { [weak self] in self?.onReplace?() }
        removeButton.onClick = { [weak self] in self?.onRemove?() }
        for view in [typeTag, name, details, result, replaceButton, removeButton] { addSubview(view) }
        updateActions()
    }

    required init?(coder: NSCoder) { nil }

    static func tagText(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpeg", "jpe": return "JPG"
        case "tiff": return "TIF"
        default: return url.pathExtension.uppercased()
        }
    }

    func configure(_ item: SqueezeWindowController.Item, phase: Phase) {
        let isPDF = ImageCollector.isPDF(item.url)
        typeTag.text = Self.tagText(for: item.url)
        typeTag.icon = isPDF ? .description : .image
        name.text = item.url.deletingPathExtension().lastPathComponent
        let pages = item.report?.pageCount ?? item.pages
        let prefix = pages.map { "\($0) \($0 == 1 ? "page" : "pages"), " } ?? ""
        result.color = DS.text
        if let report = item.report {
            if let error = report.error {
                details.text = prefix + Format.bytes(item.bytes)
                result.text = "Failed"
                result.color = DS.red
                toolTip = error
            } else {
                details.text = prefix + "\(Format.bytes(report.originalBytes)) \u{2192} \(Format.bytes(report.newBytes))" + (report.noGain ? " (no gain)" : "")
                result.text = Format.change(from: report.originalBytes, to: report.newBytes)
                toolTip = report.output?.path ?? "Original kept"
            }
        } else {
            details.text = prefix + Format.bytes(item.bytes)
            switch phase {
            case .idle: result.text = ""
            case .running: result.text = "Optimizing\u{2026}"
            case .finished: result.text = "Skipped"
            }
            result.color = DS.muted
            toolTip = item.url.path
        }
        updateActions()
    }

    private func updateActions() {
        let shown = actionsEnabled && (hovered || forcesHover)
        replaceButton.isHidden = !shown
        removeButton.isHidden = !shown
        result.isHidden = shown || result.text.isEmpty
        layoutContent()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    private func layoutContent() {
        let width = bounds.width
        let tagWidth = max(52, ceil(typeTag.intrinsicContentSize.width))
        typeTag.frame = NSRect(x: 0, y: 10, width: tagWidth, height: 18)
        let resultWidth = result.isHidden ? 0 : min(ceil(result.intrinsicContentSize.width), 160)
        let reserve: CGFloat = !replaceButton.isHidden ? 60 : (resultWidth > 0 ? resultWidth + 10 : 0)
        let textX = tagWidth + 10
        let textWidth = max(width - textX - reserve, 20)
        name.frame = NSRect(x: textX, y: 11, width: textWidth, height: 16)
        details.frame = NSRect(x: textX, y: 30, width: textWidth, height: 14)
        result.frame = NSRect(x: width - resultWidth, y: 19.5, width: resultWidth, height: 16)
        removeButton.frame = NSRect(x: width - 24, y: 15.5, width: 24, height: 24)
        replaceButton.frame = NSRect(x: width - 50, y: 15.5, width: 24, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        syncHover()
    }

    func syncHover() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(visibleRect.contains(point))
    }

    private func setHovered(_ value: Bool) {
        guard hovered != value else { return }
        hovered = value
        updateActions()
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }
}

final class RootDropView: FlippedView {
    var onDrop: (([URL]) -> Void)?
    var onHighlight: (([URL]?) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let urls = DragHelper.urls(from: sender)
        onHighlight?(urls.isEmpty ? nil : urls)
        return urls.isEmpty ? [] : .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { onHighlight?(nil) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onHighlight?(nil) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHighlight?(nil)
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

final class SqueezeWindowController: NSWindowController, NSTextFieldDelegate, NSWindowDelegate, NSViewToolTipOwner {
    struct Item {
        let url: URL
        let bytes: Int
        var pages: Int?
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
    private let isSnapshot: Bool

    private let contentWidth: CGFloat = 500
    private let side: CGFloat = 20
    private let labelWidth: CGFloat = 96
    private let blockGap: CGFloat = 24
    private let rowGap: CGFloat = 20
    private let maxVisibleRows = 6

    private let root = RootDropView()
    private let summaryLabel = DSLabel()
    private let addButton = DSButton("Add files\u{2026}")
    private let clearButton = DSButton("Clear", style: .quiet)
    private var keyLoopSignature = ""
    private let dropZone = DropZoneView()
    private let formatsBubble = DSBubble(DropZoneView.formatsText, title: "Supported formats")
    private let dropOverlay = DropOverlayView()
    private let topRule = DSSeparator()
    private let bottomRule = DSSeparator()
    private let scrollView = NSScrollView()
    private let listView = FlippedView()
    private var rows: [FileRowView] = []
    private var rowRules: [DSSeparator] = []

    private let formatLabel = SqueezeWindowController.formLabel("Format")
    private let pdfLabel = SqueezeWindowController.formLabel("PDF images")
    private let qualityLabel = SqueezeWindowController.formLabel("Quality")
    private let edgeLabel = SqueezeWindowController.formLabel("Max long edge")
    private let destinationLabel = SqueezeWindowController.formLabel("Destination")
    private let renameLabel = SqueezeWindowController.formLabel("Rename")
    private let formatControl = DSSegmented(OutputFormat.allCases.map(\.title), label: "Format")
    private let pdfControl = DSSegmented(PDFResolution.allCases.map(\.title), label: "PDF images")
    private let qualitySlider = DSSlider(value: 80, range: 1...100, label: "Quality")
    private let qualityValue = DSLabel("80")
    private let maxEdgeField = DSTextField(text: "1920")
    private let edgeHint = DSLabel("0 keeps the original size", size: 11, color: DS.muted)
    private let destinationRadio = DSRadioGroup(["Next to originals", "Replace originals", "Choose folder\u{2026}"], label: "Destination")
    private let folderLink = DSLinkButton("")
    private let groupCheckbox = DSCheckbox("Group into \u{201C}optimized\u{201D} subfolder")
    private var lastPatternSelection: NSRange?
    private let patternField = DSTextField(placeholder: NamePlanner.defaultPattern, text: NamePlanner.defaultPattern)
    private let startLabel = DSLabel("Start from", color: DS.muted)
    private let startField = DSTextField(text: "1")
    private var chips: [DSChip] = []
    private let previewLabel = DSLabel("", size: 11, color: DS.muted)

    private let optimizeButton = DSButton("Optimize", style: .primary, fullWidth: true)
    private let progressBar = DSProgressBar()
    private let progressLabel = DSLabel("", color: DS.muted)
    private let stopButton = DSButton("Cancel")
    private let resultLabel = DSLabel()
    private let revealButton = DSButton("Show in Finder")
    private let doneButton = DSButton("Done", style: .primary)

    private var imageRowsVisible = true
    private var pdfRowsVisible = false
    private var qualityRowVisible = true
    private var forcedHoverRow: Int?

    init(snapshot: Bool = false) {
        isSnapshot = snapshot
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: 600), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Squeeze"
        window.isReleasedWhenClosed = false
        window.backgroundColor = DS.paper
        super.init(window: window)
        window.delegate = self
        buildContent()
        loadSettings()
        refresh()
        if !snapshot {
            if !window.setFrameUsingName("SqueezeWindow") { window.center() }
            window.setFrameAutosaveName("SqueezeWindow")
            relayout()
            window.recalculateKeyViewLoop()
        }
    }

    required init?(coder: NSCoder) { nil }

    private static func formLabel(_ text: String) -> DSLabel {
        DSLabel(text, color: DS.muted)
    }

    private func buildContent() {
        root.frame = NSRect(x: 0, y: 0, width: contentWidth, height: 600)
        root.onDrop = { [weak self] urls in self?.add(urls) }
        root.onHighlight = { [weak self] urls in self?.setDragHighlight(urls) }

        addButton.onClick = { [weak self] in self?.openFiles() }
        clearButton.onClick = { [weak self] in self?.reset() }
        dropZone.onClick = { [weak self] in self?.openFiles() }
        dropZone.info.onHoverChange = { [weak self] on in self?.setFormatsBubble(on) }
        formatsBubble.isHidden = true

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = listView
        dropOverlay.isHidden = true

        formatControl.onChange = { [weak self] _ in self?.formatChanged() }
        pdfControl.onChange = { [weak self] index in
            Settings.pdfDpi = PDFResolution.allCases[index]
            self?.refresh()
        }
        qualitySlider.step = 1
        qualitySlider.onChange = { [weak self] value in
            let quality = Int(value.rounded())
            Settings.quality = quality
            self?.qualityValue.text = "\(quality)"
        }
        qualityValue.alignment = .right

        configureNumberField(maxEdgeField)
        maxEdgeField.unit = "px"
        configureNumberField(startField)

        destinationRadio.onChange = { [weak self] index in self?.destinationChanged(index) }
        folderLink.onClick = { [weak self] in self?.chooseFolder() }
        groupCheckbox.onChange = { [weak self] on in
            Settings.groupIntoSubfolder = on
            self?.syncDestinationControls()
        }

        patternField.delegate = self
        let reset = DSChip("Default", style: .solid) { [weak self] in
            guard let self else { return }
            self.patternField.stringValue = NamePlanner.defaultPattern
            Settings.pattern = NamePlanner.defaultPattern
            self.lastPatternSelection = nil
            self.updatePreview()
        }
        reset.toolTip = "Reset to opt-{name}"
        chips = [reset]
        for (title, token) in [("Current name", "{name}"), ("Number \u{2191}", "{n}"), ("Number \u{2193}", "{n-}")] {
            let chip = DSChip(title, style: .solid) { [weak self] in self?.insertToken(token) }
            chip.toolTip = "Insert \(token)"
            chips.append(chip)
        }

        optimizeButton.onClick = { [weak self] in self?.startBatch() }
        stopButton.onClick = { [weak self] in self?.optimizer.cancel() }
        revealButton.onClick = { [weak self] in self?.revealOutputs() }
        doneButton.onClick = { [weak self] in self?.reset() }

        let views: [NSView] = [summaryLabel, clearButton, addButton, dropZone, topRule, scrollView, bottomRule, dropOverlay,
                               formatLabel, formatControl, pdfLabel, pdfControl, qualityLabel, qualitySlider, qualityValue,
                               edgeLabel, maxEdgeField, edgeHint, destinationLabel, destinationRadio, folderLink, groupCheckbox,
                               renameLabel, patternField, startLabel, startField, previewLabel,
                               optimizeButton, progressBar, progressLabel, stopButton, resultLabel, revealButton, doneButton]
        for view in views { root.addSubview(view) }
        for chip in chips { root.addSubview(chip) }
        root.addSubview(dropOverlay)
        root.addSubview(formatsBubble)
        window?.contentView = root
        window?.initialFirstResponder = root
    }

    private func configureNumberField(_ field: DSTextField) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximum = 100_000
        formatter.allowsFloats = false
        field.formatter = formatter
        field.delegate = self
    }

    private func loadSettings() {
        formatControl.selectedIndex = OutputFormat.allCases.firstIndex(of: Settings.format) ?? 0
        pdfControl.selectedIndex = PDFResolution.allCases.firstIndex(of: Settings.pdfDpi) ?? 0
        qualitySlider.value = Double(Settings.quality)
        qualityValue.text = "\(Settings.quality)"
        maxEdgeField.stringValue = "\(Settings.maxEdge)"
        patternField.stringValue = Settings.pattern
        startField.stringValue = "\(Settings.startNumber)"
        syncDestinationControls()
    }

    private var selectedFormat: OutputFormat {
        OutputFormat.allCases.indices.contains(formatControl.selectedIndex) ? OutputFormat.allCases[formatControl.selectedIndex] : .webp
    }

    private var hasPDF: Bool { items.contains { ImageCollector.isPDF($0.url) } }
    private var hasImage: Bool { items.contains { !ImageCollector.isPDF($0.url) } }

    private var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    private var phase: FileRowView.Phase {
        switch state {
        case .idle: return .idle
        case .running: return .running
        case .finished: return .finished
        }
    }

    private func updatePreview() {
        previewLabel.text = "\u{2192} " + NamePlanner.preview(files: items.map(\.url), pattern: Settings.pattern, start: Settings.startNumber, format: Settings.format)
    }

    private func formatChanged() {
        Settings.format = selectedFormat
        refresh()
    }

    private func destinationChanged(_ index: Int) {
        switch index {
        case 2:
            if Settings.chosenFolder == nil {
                chooseFolder()
            } else {
                Settings.destinationMode = "folder"
            }
        case 1: Settings.destinationMode = "replace"
        default: Settings.destinationMode = "subfolder"
        }
        syncDestinationControls()
    }

    private func chooseFolder() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = Settings.chosenFolder
        show()
        panel.beginSheetModal(for: window) { [weak self] response in
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
        destinationRadio.selectedIndex = mode == "replace" ? 1 : (mode == "folder" ? 2 : 0)
        let folder = Settings.chosenFolder
        destinationRadio.items = ["Next to originals", "Replace originals", folder == nil ? "Choose folder\u{2026}" : "Folder"]
        let path = folder.map { $0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") } ?? ""
        folderLink.title = folder == nil ? "" : path + "  (change\u{2026})"
        folderLink.toolTip = folder?.path
        groupCheckbox.isOn = Settings.groupIntoSubfolder
        updateDestinationTooltips()
        refresh()
    }

    private func updateDestinationTooltips() {
        destinationRadio.removeAllToolTips()
        let pitch = DSRadioGroup.rowHeight + DSRadioGroup.rowGap
        for index in destinationRadio.items.indices {
            destinationRadio.addToolTip(NSRect(x: 0, y: CGFloat(index) * pitch, width: max(destinationRadio.frame.width, 1), height: DSRadioGroup.rowHeight), owner: self, userData: nil)
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        let pitch = DSRadioGroup.rowHeight + DSRadioGroup.rowGap
        switch Int((point.y + DSRadioGroup.rowGap / 2) / pitch) {
        case 0: return "Saves into an \u{201C}\(ImageCollector.outputFolderName)\u{201D} subfolder next to each file"
        case 1: return "Originals are moved to the Trash"
        default: return Settings.chosenFolder?.path ?? "Pick a folder for the results"
        }
    }

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
        let editing = (patternField.currentEditor() as? NSTextView)?.selectedRange()
        var range = editing ?? lastPatternSelection ?? NSRange(location: current.length, length: 0)
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

    private static func makeItem(_ url: URL) -> Item {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        var pages: Int?
        if ImageCollector.isPDF(url), let document = CGPDFDocument(url as CFURL) { pages = document.numberOfPages }
        return Item(url: url, bytes: bytes, pages: pages)
    }

    private static func key(_ url: URL) -> String { url.standardizedFileURL.path.lowercased() }

    func add(_ urls: [URL]) {
        if isRunning {
            NSSound.beep()
            return
        }
        if case .finished = state {
            items = []
            state = .idle
        }
        let existing = Set(items.map { Self.key($0.url) })
        let files = ImageCollector.collect(urls).filter { !existing.contains(Self.key($0)) }
        items.append(contentsOf: files.map(Self.makeItem))
        log("added \(files.count) files, batch has \(items.count)")
        rebuildRows()
        show()
    }

    private func remove(_ url: URL) {
        guard !isRunning, let index = items.firstIndex(where: { $0.url == url }) else { return }
        items.remove(at: index)
        rebuildRows()
    }

    private func replace(_ url: URL) {
        guard !isRunning, let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf]
        panel.directoryURL = url.deletingLastPathComponent()
        panel.prompt = "Replace"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let picked = panel.url, !self.isRunning else { return }
            guard let index = self.items.firstIndex(where: { $0.url == url }) else { return }
            guard ImageCollector.isSupported(picked) else {
                NSSound.beep()
                return
            }
            let pickedKey = Self.key(picked)
            if pickedKey == Self.key(url) { return }
            if self.items.contains(where: { Self.key($0.url) == pickedKey }) {
                NSSound.beep()
                return
            }
            self.items[index] = Self.makeItem(picked)
            log("replaced \(url.lastPathComponent) with \(picked.lastPathComponent)")
            self.rebuildRows()
        }
    }

    func openFiles() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image, .pdf, .folder]
        panel.prompt = "Add"
        show()
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.add(panel.urls)
        }
    }

    func show() {
        guard !isSnapshot else { return }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func setFormatsBubble(_ show: Bool) {
        guard show, items.isEmpty, !dropZone.isHidden, !dropZone.info.isHidden else {
            formatsBubble.isHidden = true
            return
        }
        let anchor = root.convert(dropZone.info.bounds, from: dropZone.info)
        formatsBubble.setFrameOrigin(NSPoint(x: anchor.maxX - formatsBubble.frame.width, y: anchor.maxY + 4))
        formatsBubble.isHidden = false
    }

    private func setDragHighlight(_ urls: [URL]?) {
        if urls != nil { formatsBubble.isHidden = true }
        if items.isEmpty {
            dropZone.dragTitle = urls.map(DragHelper.title(for:))
            dropOverlay.isHidden = true
        } else {
            dropZone.dragTitle = nil
            dropOverlay.isHidden = urls == nil || isRunning
        }
        relayout()
    }

    private func rebuildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rowRules.forEach { $0.removeFromSuperview() }
        rows = items.map { item in
            let row = FileRowView(frame: .zero)
            row.onReplace = { [weak self] in self?.replace(item.url) }
            row.onRemove = { [weak self] in self?.remove(item.url) }
            return row
        }
        rowRules = rows.count > 1 ? (1..<rows.count).map { _ in DSSeparator() } : []
        rows.forEach { listView.addSubview($0) }
        rowRules.forEach { listView.addSubview($0) }
        refresh()
    }

    private func refresh() {
        let pdf = hasPDF
        imageRowsVisible = hasImage || !pdf
        pdfRowsVisible = pdf
        qualityRowVisible = !(selectedFormat == .png && !pdf)
        let total = items.reduce(0) { $0 + $1.bytes }
        if items.isEmpty {
            summaryLabel.text = "No files yet"
            summaryLabel.color = DS.muted
        } else {
            summaryLabel.text = "\(Format.count(items.count, images: !pdf)), \(Format.bytes(total))"
            summaryLabel.color = DS.text
        }
        let running = isRunning
        let currentPhase = phase
        for (index, row) in rows.enumerated() where items.indices.contains(index) {
            row.configure(items[index], phase: currentPhase)
            row.actionsEnabled = currentPhase == .idle
            row.forcesHover = forcedHoverRow == index
        }
        addButton.isEnabled = !running
        let controls: [DSControl] = [formatControl, pdfControl, qualitySlider, destinationRadio, folderLink, groupCheckbox] + chips
        controls.forEach { $0.isEnabled = !running }
        groupCheckbox.isEnabled = !running && Settings.destinationMode == "folder"
        for field in [maxEdgeField, patternField, startField] { field.isEnabled = !running }
        for label in [edgeHint, startLabel] { label.alphaValue = running ? DS.disabledOpacity : 1 }
        optimizeButton.title = items.isEmpty ? "Optimize" : "Optimize \(Format.count(items.count, images: !pdf))"
        optimizeButton.isEnabled = !items.isEmpty
        updatePreview()
        relayout()
    }

    private func place(_ view: NSView, _ rect: NSRect, visible: Bool = true) {
        view.isHidden = !visible
        if visible { view.frame = rect }
    }

    private func relayout() {
        let inner = contentWidth - side * 2
        let fieldX = side + labelWidth + 16
        let fieldWidth = contentWidth - side - fieldX
        var y: CGFloat = 16

        let addWidth = addButton.fittingWidth
        let clearWidth = clearButton.fittingWidth
        let showsHeader = !items.isEmpty
        let showsClear = showsHeader && phase == .idle
        place(addButton, NSRect(x: contentWidth - side - addWidth, y: y, width: addWidth, height: 28), visible: showsHeader)
        place(clearButton, NSRect(x: contentWidth - side - addWidth - 10 - clearWidth, y: y, width: clearWidth, height: 28), visible: showsClear)
        place(summaryLabel, NSRect(x: side, y: y, width: inner - addWidth - 10 - (showsClear ? clearWidth + 10 : 0), height: 28), visible: showsHeader)
        if showsHeader { y += 28 + blockGap }

        let empty = items.isEmpty
        let listTop = y
        let formHeight = layoutForm(top: 0, fieldX: fieldX, fieldWidth: fieldWidth, apply: false)
        let bottomHeight: CGFloat = 28 + 20
        topRule.isHidden = empty
        scrollView.isHidden = empty
        bottomRule.isHidden = empty

        if empty {
            let height = dropZone.height(forWidth: inner)
            place(dropZone, NSRect(x: side, y: y, width: inner, height: height))
            dropOverlay.isHidden = true
            y += height + blockGap
        } else {
            dropZone.isHidden = true
            formatsBubble.isHidden = true
            let rowPitch = FileRowView.height + 1
            let content = CGFloat(rows.count) * rowPitch - 1
            var limit = CGFloat(maxVisibleRows) * rowPitch - 1
            if !isSnapshot, let screen = window?.screen ?? NSScreen.main {
                let chrome = (window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 32)
                let available = screen.visibleFrame.height - chrome - (listTop + 2 + blockGap + formHeight + blockGap + bottomHeight)
                limit = max(min(limit, available), 2 * rowPitch - 1)
            }
            let listHeight = min(content, limit)
            topRule.frame = NSRect(x: side, y: listTop, width: inner, height: 1)
            listView.frame = NSRect(x: 0, y: 0, width: listView.frame.width, height: content)
            scrollView.frame = NSRect(x: side, y: listTop + 1, width: inner, height: listHeight)
            scrollView.tile()
            bottomRule.frame = NSRect(x: side, y: listTop + 1 + listHeight, width: inner, height: 1)
            let listWidth = min(scrollView.contentSize.width, inner)
            listView.frame = NSRect(x: 0, y: 0, width: listWidth, height: content)
            for (index, row) in rows.enumerated() {
                row.frame = NSRect(x: 0, y: CGFloat(index) * rowPitch, width: listWidth, height: FileRowView.height)
                if index > 0 { rowRules[index - 1].frame = NSRect(x: 0, y: CGFloat(index) * rowPitch - 1, width: listWidth, height: 1) }
            }
            dropOverlay.frame = NSRect(x: side, y: listTop, width: inner, height: listHeight + 2)
            y = listTop + listHeight + 2 + blockGap
        }

        y = layoutForm(top: y, fieldX: fieldX, fieldWidth: fieldWidth, apply: true)
        y += blockGap
        layoutBottom(top: y, inner: inner)
        y += 28 + 20

        root.setFrameSize(NSSize(width: contentWidth, height: y))
        resizeWindow(contentHeight: y)
        rows.forEach { $0.syncHover() }
        updateKeyViewLoop()
    }

    private func updateKeyViewLoop() {
        guard !isSnapshot, let window else { return }
        let rowIDs = rows.map { "\(ObjectIdentifier($0).hashValue)" }.joined(separator: ",")
        let flags = [imageRowsVisible, pdfRowsVisible, qualityRowVisible, Settings.chosenFolder != nil, items.isEmpty, !clearButton.isHidden, phase == .idle]
        let signature = rowIDs + flags.map { $0 ? "1" : "0" }.joined()
        guard signature != keyLoopSignature else { return }
        keyLoopSignature = signature
        window.recalculateKeyViewLoop()
    }

    private func layoutForm(top: CGFloat, fieldX: CGFloat, fieldWidth: CGFloat, apply: Bool) -> CGFloat {
        var y = top
        var first = true
        func row(_ height: CGFloat, _ body: (CGFloat) -> Void) {
            if !first { y += rowGap }
            first = false
            if apply { body(y) }
            y += height
        }
        func label(_ view: DSLabel, _ rowTop: CGFloat, _ rowHeight: CGFloat) {
            place(view, NSRect(x: side, y: rowTop + ((rowHeight - 16) / 2).rounded(), width: labelWidth, height: 16))
        }

        if apply {
            for view in [formatLabel, formatControl, edgeLabel, maxEdgeField, edgeHint] as [NSView] { view.isHidden = !imageRowsVisible }
            for view in [pdfLabel, pdfControl] as [NSView] { view.isHidden = !pdfRowsVisible }
            for view in [qualityLabel, qualitySlider, qualityValue] as [NSView] { view.isHidden = !qualityRowVisible }
        }

        if imageRowsVisible {
            row(28) { top in
                label(formatLabel, top, 28)
                place(formatControl, NSRect(x: fieldX, y: top, width: fieldWidth, height: 28))
            }
        }
        if pdfRowsVisible {
            row(28) { top in
                label(pdfLabel, top, 28)
                place(pdfControl, NSRect(x: fieldX, y: top, width: fieldWidth, height: 28))
            }
        }
        if qualityRowVisible {
            row(20) { top in
                label(qualityLabel, top, 20)
                place(qualitySlider, NSRect(x: fieldX, y: top, width: fieldWidth - 40, height: 20))
                place(qualityValue, NSRect(x: fieldX + fieldWidth - 30, y: top + 2, width: 30, height: 16))
            }
        }
        if imageRowsVisible {
            row(28) { top in
                label(edgeLabel, top, 28)
                place(maxEdgeField, NSRect(x: fieldX, y: top, width: 120, height: 28))
                place(edgeHint, NSRect(x: fieldX + 130, y: top + 7, width: fieldWidth - 130, height: 14))
            }
        }
        let hasFolder = Settings.chosenFolder != nil
        let radioHeight = destinationRadio.intrinsicContentSize.height
        let destinationHeight = radioHeight + (hasFolder ? 8 + 16 + 8 + 16 : 0)
        row(destinationHeight) { top in
            place(destinationLabel, NSRect(x: side, y: top, width: labelWidth, height: 16))
            place(destinationRadio, NSRect(x: fieldX, y: top, width: fieldWidth, height: radioHeight))
            let indent = DSRadioGroup.dotSize + 8
            let linkWidth = min(ceil(folderLink.intrinsicContentSize.width), fieldWidth - indent)
            place(folderLink, NSRect(x: fieldX + indent, y: top + radioHeight + 8, width: linkWidth, height: 16), visible: hasFolder)
            place(groupCheckbox, NSRect(x: fieldX + indent, y: top + radioHeight + 32, width: min(ceil(groupCheckbox.intrinsicContentSize.width), fieldWidth - indent), height: 16), visible: hasFolder)
            updateDestinationTooltips()
        }
        let chipRows = layoutChips(x: fieldX, width: fieldWidth, top: 0, apply: false)
        let chipsHeight = CGFloat(chipRows) * 24 + CGFloat(chipRows - 1) * 6
        row(28 + 8 + chipsHeight + 8 + 14) { top in
            place(renameLabel, NSRect(x: side, y: top + 6, width: labelWidth, height: 16))
            let startWidth: CGFloat = 56
            let startLabelWidth = ceil(startLabel.intrinsicContentSize.width)
            let patternWidth = fieldWidth - startWidth - 10 - startLabelWidth - 10
            place(patternField, NSRect(x: fieldX, y: top, width: patternWidth, height: 28))
            place(startLabel, NSRect(x: fieldX + patternWidth + 10, y: top + 6, width: startLabelWidth, height: 16))
            place(startField, NSRect(x: fieldX + fieldWidth - startWidth, y: top, width: startWidth, height: 28))
            _ = layoutChips(x: fieldX, width: fieldWidth, top: top + 36, apply: true)
            place(previewLabel, NSRect(x: fieldX, y: top + 36 + chipsHeight + 8, width: fieldWidth, height: 14))
        }
        return y
    }

    private func layoutChips(x: CGFloat, width: CGFloat, top: CGFloat, apply: Bool) -> Int {
        var lineCount = 1
        var cursor: CGFloat = 0
        var lineTop = top
        for chip in chips {
            let chipWidth = ceil(chip.intrinsicContentSize.width)
            if cursor > 0 && cursor + chipWidth > width {
                lineCount += 1
                cursor = 0
                lineTop += 24 + 6
            }
            if apply { chip.frame = NSRect(x: x + cursor, y: lineTop, width: chipWidth, height: 24) }
            cursor += chipWidth + 6
        }
        return lineCount
    }

    private func layoutBottom(top: CGFloat, inner: CGFloat) {
        let right = side + inner
        var idle = false, running = false, finished = false
        switch state {
        case .idle: idle = true
        case .running: running = true
        case .finished: finished = true
        }
        place(optimizeButton, NSRect(x: side, y: top, width: inner, height: 28), visible: idle)

        let stopWidth = stopButton.fittingWidth
        let countWidth = ceil(DSText.width(progressLabel.text, font: progressLabel.font))
        place(stopButton, NSRect(x: right - stopWidth, y: top, width: stopWidth, height: 28), visible: running)
        place(progressLabel, NSRect(x: right - stopWidth - 10 - countWidth, y: top + 6, width: countWidth, height: 16), visible: running)
        place(progressBar, NSRect(x: side, y: top + 12, width: max(right - stopWidth - 20 - countWidth - side, 20), height: 4), visible: running)

        let doneWidth = doneButton.fittingWidth
        let revealWidth = revealButton.fittingWidth
        place(doneButton, NSRect(x: right - doneWidth, y: top, width: doneWidth, height: 28), visible: finished)
        place(revealButton, NSRect(x: right - doneWidth - 10 - revealWidth, y: top, width: revealWidth, height: 28), visible: finished)
        place(resultLabel, NSRect(x: side, y: top + 6, width: max(inner - doneWidth - revealWidth - 30, 20), height: 16), visible: finished)
    }

    private func resizeWindow(contentHeight: CGFloat) {
        guard let window else { return }
        let current = window.contentRect(forFrameRect: window.frame)
        guard abs(current.height - contentHeight) > 0.5 || abs(current.width - contentWidth) > 0.5 else { return }
        var frame = window.frameRect(forContentRect: NSRect(x: current.minX, y: current.maxY - contentHeight, width: contentWidth, height: contentHeight))
        frame.origin.y = window.frame.maxY - frame.height
        let screen = window.screen ?? NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main
        if !isSnapshot, let visible = screen?.visibleFrame, frame.minY < visible.minY {
            frame.origin.y = max(visible.minY, visible.maxY - frame.height)
        }
        window.setFrame(frame, display: window.isVisible)
    }

    private func startBatch() {
        guard !items.isEmpty, !optimizer.isRunning else { return }
        window?.makeFirstResponder(root)
        let options = Settings.options
        for index in items.indices { items[index].report = nil }
        state = .running
        progressBar.progress = 0
        progressLabel.text = "0 of \(items.count)"
        refresh()
        log("starting batch of \(items.count) → \(options.format.title)")
        optimizer.run(files: items.map(\.url), options: options, progress: { [weak self] completed, total, report in
            guard let self else { return }
            if let index = self.items.firstIndex(where: { $0.url == report.source }) {
                self.items[index].report = report
                if self.rows.indices.contains(index) { self.rows[index].configure(self.items[index], phase: self.phase) }
            }
            self.progressBar.progress = total > 0 ? Double(completed) / Double(total) : 0
            self.progressLabel.text = "\(completed) of \(total)"
            self.relayout()
        }, completion: { [weak self] report in
            guard let self else { return }
            self.finish(report)
            if self.window?.isKeyWindow != true { self.onNotify?(report.summary) }
        })
    }

    private func finish(_ report: BatchReport) {
        state = .finished(report)
        resultLabel.text = report.summary
        resultLabel.toolTip = report.summary
        revealButton.isEnabled = !report.outputs.isEmpty
        refresh()
    }

    private func revealOutputs() {
        guard case .finished(let report) = state, !report.outputs.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(report.outputs)
    }

    private func reset() {
        items = []
        state = .idle
        rebuildRows()
    }

    func windowWillClose(_ notification: Notification) {
        if case .finished = state { reset() }
    }

    enum Sample: String, CaseIterable {
        case main = "squeeze"
        case empty = "squeeze-empty"
        case emptyHover = "squeeze-empty-hover"
        case info = "squeeze-empty-info"
        case drop = "squeeze-empty-drop"
        case hover = "squeeze-hover"
        case running = "squeeze-running"
        case finished = "squeeze-finished"
        case folder = "squeeze-folder"
    }

    func loadSample(_ sample: Sample) {
        let folder = URL(fileURLWithPath: "/Users/sample/Desktop", isDirectory: true)
        func item(_ name: String, _ bytes: Int, pages: Int? = nil) -> Item {
            Item(url: folder.appendingPathComponent(name), bytes: bytes, pages: pages)
        }
        func report(_ item: Item, _ newBytes: Int) -> FileReport {
            var report = FileReport(source: item.url)
            report.originalBytes = item.bytes
            report.newBytes = newBytes
            report.pageCount = item.pages
            report.output = item.url.deletingLastPathComponent().appendingPathComponent(ImageCollector.outputFolderName).appendingPathComponent(item.url.lastPathComponent)
            return report
        }
        let batch = [item("hero-homepage.jpg", 4_800_000), item("team-photo.png", 3_100_000), item("pricing-deck.pdf", 3_900_000, pages: 12), item("logo-sheet.png", 620_000)]
        let progress = [item("hero-homepage.jpg", 4_800_000), item("pricing-deck.pdf", 3_900_000, pages: 12), item("logo-sheet.png", 620_000)]
        switch sample {
        case .folder:
            Settings.chosenFolder = URL(fileURLWithPath: NSHomeDirectory() + "/Desktop/Web exports", isDirectory: true)
            Settings.destinationMode = "folder"
            items = [batch[0], batch[1]]
            syncDestinationControls()
        case .main, .hover:
            items = batch
            forcedHoverRow = sample == .hover ? 1 : nil
        case .empty, .emptyHover, .info, .drop:
            items = []
            dropZone.dragTitle = sample == .drop ? "3 files" : nil
            dropZone.previewState = sample == .emptyHover || sample == .info ? .hovered : []
            if sample == .info {
                rebuildRows()
                dropZone.info.previewState = .hovered
                return
            }
        case .running:
            items = progress
            items[0].report = report(items[0], 412_000)
            items[1].report = report(items[1], 1_100_000)
            state = .running
            progressBar.progress = 2.0 / 3.0
            progressLabel.text = "2 of 3"
        case .finished:
            items = progress
            items[0].report = report(items[0], 412_000)
            items[1].report = report(items[1], 1_100_000)
            items[2].report = report(items[2], 188_000)
            rebuildRows()
            finish(BatchReport(files: items.compactMap(\.report), cancelled: false, duration: 2.4))
            return
        }
        rebuildRows()
    }
}

enum Snapshots {
    static func run(directory: URL) -> Int32 {
        _ = NSApplication.shared
        _ = DS.registerFonts()
        Settings.memory = [:]
        for sample in SqueezeWindowController.Sample.allCases {
            for dark in [false, true] {
                Settings.memory = [:]
                let controller = SqueezeWindowController(snapshot: true)
                controller.loadSample(sample)
                guard let view = controller.window?.contentView else { return 1 }
                let file = directory.appendingPathComponent("\(sample.rawValue)-\(dark ? "dark" : "light").png")
                if !DSSnapshot.write(view: view, to: file, dark: dark) { return 1 }
            }
        }
        return 0
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var controller: SqueezeWindowController!

    private static let iconSVG = "<svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"24\" height=\"24\" fill=\"white\" fill-opacity=\"0.25\"/><path transform=\"translate(12 12) scale(0.72) translate(-12 -12) translate(3 3)\" fill-rule=\"evenodd\" clip-rule=\"evenodd\" fill=\"white\" d=\"M18 2C18 0.9 17.1 0 16 0H2C0.9 0 0 0.9 0 2V16C0 17.1 0.9 18 2 18H16C17.1 18 18 17.1 18 16V2ZM3 14L6 10L7 11L10 7L15 14H3Z\"/></svg>"

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(data: Data(iconSVG.utf8)) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Squeeze"
        return image
    }

    private var pendingFiles: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = DS.registerFonts()
        controller = SqueezeWindowController()
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
        if !pendingFiles.isEmpty {
            controller.add(pendingFiles)
            pendingFiles = []
        }
        log("started")
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let controller {
            controller.add(urls)
        } else {
            pendingFiles.append(contentsOf: urls)
        }
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
        menu.addItem(DSBrand.menuItem())
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

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    exit(Snapshots.run(directory: URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)))
}
if CommandLine.arguments.contains("--snapshot") {
    FileHandle.standardError.write(Data("usage: Squeeze --snapshot <directory>\n".utf8))
    exit(2)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
