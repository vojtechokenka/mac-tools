import AppKit
import Carbon.HIToolbox

enum Row {
    case header(title: String, open: Int)
    case task(TaskRef)
    case empty
}

final class RefBox: NSObject {
    let ref: TaskRef
    init(_ ref: TaskRef) { self.ref = ref }
}

func symbolButton(_ name: String, tooltip: String, size: CGFloat = 11) -> NSButton {
    let button = NSButton(title: "", target: nil, action: nil)
    button.image = NSImage(systemSymbolName: name, accessibilityDescription: tooltip)
    button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = tooltip
    return button
}

final class CheckBox: NSButton {
    var isDone = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    override func draw(_ dirtyRect: NSRect) {
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        if isDone {
            NSColor.controlAccentColor.setFill()
            box.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: 4, y: 8))
            check.line(to: NSPoint(x: 6.7, y: 10.7))
            check.line(to: NSPoint(x: 12, y: 5.3))
            check.lineWidth = 1.8
            check.lineCapStyle = .butt
            check.lineJoinStyle = .miter
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor.tertiaryLabelColor.setStroke()
            box.lineWidth = 1
            box.stroke()
        }
    }
}

final class TaskRowView: NSView, NSTextFieldDelegate {
    let checkBox = CheckBox(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    let textField = NSTextField(labelWithString: "")
    let metaButton = NSButton(title: "", target: nil, action: nil)
    let editButton = symbolButton("pencil", tooltip: "Edit")
    let dateButton = symbolButton("calendar", tooltip: "Deadline")
    let deleteButton = NSButton(title: "×", target: nil, action: nil)
    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDeadline: (() -> Void)?
    var onCommit: ((String, Bool) -> Void)?
    var onCancelEdit: (() -> Void)?
    private(set) var editing = false
    private(set) var source = ""
    private var metaText = ""
    private var hovered = false { didSet { updateChrome() } }
    private var editCancelled = false
    private var editAbandoned = false
    private var toggleAfterEdit = false
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        checkBox.isBordered = false
        checkBox.title = ""
        checkBox.target = self
        checkBox.action = #selector(toggle)
        textField.font = .systemFont(ofSize: 13)
        textField.lineBreakMode = .byTruncatingTail
        textField.focusRingType = .none
        textField.delegate = self
        metaButton.isBordered = false
        metaButton.alignment = .center
        metaButton.wantsLayer = true
        metaButton.layer?.cornerRadius = 5
        metaButton.target = self
        metaButton.action = #selector(deadline)
        editButton.target = self
        editButton.action = #selector(edit)
        editButton.isHidden = true
        dateButton.target = self
        dateButton.action = #selector(deadline)
        dateButton.isHidden = true
        deleteButton.isBordered = false
        deleteButton.font = .systemFont(ofSize: 14)
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.target = self
        deleteButton.action = #selector(remove)
        deleteButton.isHidden = true
        deleteButton.toolTip = "Delete"
        for view in [checkBox, textField, metaButton, dateButton, editButton, deleteButton] { addSubview(view) }
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ item: TodoItem, today: Day) {
        source = item.source
        checkBox.isDone = item.done
        if item.done {
            textField.attributedStringValue = NSAttributedString(string: item.text, attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: NSColor.secondaryLabelColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: NSColor.secondaryLabelColor,
            ])
        } else {
            textField.stringValue = item.text
            textField.textColor = .labelColor
        }
        let meta = DateInput.countdown(due: item.due, today: today)
        metaText = meta.text
        let tint: NSColor = meta.urgency == 2 ? .systemRed : (meta.urgency == 1 ? .systemOrange : .secondaryLabelColor)
        metaButton.attributedTitle = NSAttributedString(string: meta.text, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: tint,
        ])
        metaButton.layer?.backgroundColor = tint.withAlphaComponent(0.16).cgColor
        metaButton.toolTip = item.due?.fullLabel
        updateChrome()
        needsLayout = true
    }

    private func updateChrome() {
        needsLayout = true
        editButton.isHidden = !hovered || editing
        dateButton.isHidden = !hovered || editing
        deleteButton.isHidden = !hovered || editing
        metaButton.isHidden = metaText.isEmpty || editing
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let height = bounds.height
        checkBox.frame = NSRect(x: 8, y: (height - 16) / 2, width: 16, height: 16)
        deleteButton.frame = NSRect(x: width - 26, y: (height - 20) / 2, width: 20, height: 20)
        editButton.frame = NSRect(x: width - 48, y: (height - 20) / 2, width: 20, height: 20)
        dateButton.frame = NSRect(x: width - 70, y: (height - 20) / 2, width: 20, height: 20)
        let limit = (hovered && !editing) ? width - 74 : width - 8
        let metaWidth = metaButton.isHidden ? 0 : ceil(metaButton.intrinsicContentSize.width) + 12
        metaButton.frame = NSRect(x: 32, y: (height - 20) / 2, width: metaWidth, height: 20)
        let textX: CGFloat = 32 + (metaWidth > 0 ? metaWidth + 8 : 0)
        let textWidth = max(20, limit - textX)
        textField.frame = NSRect(x: textX, y: (height - 18) / 2, width: textWidth, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        syncHoverWithPointer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncHoverWithPointer()
    }

    private func syncHoverWithPointer() {
        guard let window else { return }
        let inside = visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        if inside != hovered { hovered = inside }
    }

    func hitsText(_ windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        var textRect = textField.frame
        textRect.size.width = min(textRect.width, ceil(textField.intrinsicContentSize.width) + 6)
        return textRect.contains(point)
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

    override func draw(_ dirtyRect: NSRect) {
        guard hovered || editing else { return }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 1), xRadius: 6, yRadius: 6).fill()
    }

    var editSelection: NSRange? { editing ? textField.currentEditor()?.selectedRange : nil }

    func beginEditing(text: String? = nil, selection: NSRange? = nil) {
        guard !editing, let window else { return }
        editing = true
        editCancelled = false
        editAbandoned = false
        toggleAfterEdit = false
        textField.stringValue = text ?? source
        textField.textColor = .labelColor
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBezeled = false
        textField.drawsBackground = false
        updateChrome()
        needsLayout = true
        layoutSubtreeIfNeeded()
        window.makeFirstResponder(textField)
        guard editing, let editor = textField.currentEditor() else {
            editAbandoned = true
            finishEditing()
            return
        }
        if let selection {
            editor.selectedRange = selection
        } else {
            editor.selectAll(nil)
        }
    }

    func abandonEditing() {
        guard editing else { return }
        editAbandoned = true
        window?.makeFirstResponder(nil)
        finishEditing()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        finishEditing()
    }

    private func finishEditing() {
        guard editing else { return }
        editing = false
        textField.isEditable = false
        textField.isSelectable = false
        let text = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let toggle = toggleAfterEdit
        toggleAfterEdit = false
        updateChrome()
        needsLayout = true
        if editAbandoned { return }
        if editCancelled {
            onCancelEdit?()
            if toggle { onToggle?() }
        } else {
            onCommit?(text, toggle)
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            editCancelled = true
            window?.makeFirstResponder(nil)
            return true
        }
        if selector == #selector(NSResponder.insertNewline(_:)) {
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    @objc private func toggle() {
        if editing {
            toggleAfterEdit = true
            window?.makeFirstResponder(nil)
            return
        }
        onToggle?()
    }
    @objc private func remove() { onDelete?() }
    @objc private func edit() { onEdit?() }
    @objc private func deadline() { onDeadline?() }
}

final class ChipView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton(title: "×", target: nil, action: nil)
    var onClear: (() -> Void)?

    init() {
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .labelColor
        clearButton.isBordered = false
        clearButton.font = .systemFont(ofSize: 13)
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clear)
        clearButton.toolTip = "Clear deadline"
        addSubview(label)
        addSubview(clearButton)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(label.intrinsicContentSize.width) + 30, height: 20)
    }

    func set(text: String) {
        label.stringValue = text
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 8, y: 2, width: ceil(label.intrinsicContentSize.width), height: 16)
        clearButton.frame = NSRect(x: bounds.width - 20, y: 0, width: 18, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
    }

    @objc private func clear() { onClear?() }
}

final class DatePickerController: NSViewController {
    private let picker = NSDatePicker()
    private let clearButton = NSButton(title: "No deadline", target: nil, action: nil)
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private var lastValue: Day?
    var onPick: ((Day?) -> Void)?

    func prepare(current: Day?) {
        loadViewIfNeeded()
        lastValue = current ?? Day.today
        picker.dateValue = lastValue!.date
    }

    private static func isMonthStep(from old: Day, to new: Day) -> Bool {
        old.day == new.day && abs((new.year * 12 + new.month) - (old.year * 12 + old.month)) == 1
    }

    override func loadView() {
        picker.datePickerStyle = .clockAndCalendar
        picker.datePickerElements = .yearMonthDay
        picker.datePickerMode = .single
        picker.calendar = Day.calendar
        picker.locale = Locale(identifier: "en_GB")
        picker.timeZone = Day.calendar.timeZone
        picker.isBezeled = false
        picker.drawsBackground = false
        picker.target = self
        picker.action = #selector(picked)
        for (button, action) in [(clearButton, #selector(clear)), (applyButton, #selector(apply))] {
            button.bezelStyle = .rounded
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.action = action
        }
        let buttons = NSStackView(views: [clearButton, applyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 6
        let stack = NSStackView(views: [picker, buttons])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        view = stack
        preferredContentSize = stack.fittingSize
    }

    private func commit(_ day: Day?) {
        DispatchQueue.main.async { [weak self] in self?.onPick?(day) }
    }

    @objc private func picked() {
        let day = Day(picker.dateValue)
        let previous = lastValue
        lastValue = day
        if let previous, Self.isMonthStep(from: previous, to: day) { return }
        commit(day)
    }

    @objc private func apply() { commit(Day(picker.dateValue)) }

    @objc private func clear() { commit(nil) }
}

final class PanelView: NSView {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onCancel?() } else { super.keyDown(with: event) }
    }
}

final class PanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    let store: TaskStore
    var onChange: (() -> Void)?
    var onClose: (() -> Void)?
    var hideDoneMode: HideDoneMode = .after24h

    private let inputField = NSTextField()
    private let calendarButton = symbolButton("calendar", tooltip: "Deadline", size: 13)
    private let chip = ChipView()
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let datePopover = NSPopover()
    var isDatePickerShown: Bool { datePopover.isShown }
    private let datePicker = DatePickerController()
    private var tableHeight: NSLayoutConstraint!
    private var chipTop: NSLayoutConstraint!
    private var chipHeight: NSLayoutConstraint!
    private var rows: [Row] = []
    private var pendingDue: Day?
    private var lastTypedLength = 0
    private var suggesting = false
    private var suggestionRange: NSRange?
    private let panelWidth: CGFloat = 420
    private let maxPanelHeight: CGFloat = 560

    private var chromeHeight: CGFloat { 12 + 24 + (pendingDue == nil ? 0 : 26) + 10 + 12 }

    init(store: TaskStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let panel = PanelView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: 200))
        panel.onCancel = { [weak self] in self?.onClose?() }
        view = panel

        inputField.placeholderString = "Add a task…"
        inputField.font = .systemFont(ofSize: 13)
        inputField.usesSingleLineMode = true
        inputField.cell?.wraps = false
        inputField.cell?.isScrollable = true
        inputField.bezelStyle = .roundedBezel
        inputField.focusRingType = .none
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(addTask)
        calendarButton.target = self
        calendarButton.action = #selector(pickInputDate)
        chip.isHidden = true
        chip.onClear = { [weak self] in self?.setPendingDue(nil) }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("task"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.intercellSpacing = .zero
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        let contextMenu = NSMenu()
        contextMenu.delegate = self
        tableView.menu = contextMenu

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.verticalScrollElasticity = .none

        datePopover.behavior = .transient
        datePopover.animates = true
        datePopover.contentViewController = datePicker

        for subview in [inputField, calendarButton, chip, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            panel.addSubview(subview)
        }
        tableHeight = scrollView.heightAnchor.constraint(equalToConstant: 100)
        chipTop = chip.topAnchor.constraint(equalTo: inputField.bottomAnchor, constant: 0)
        chipHeight = chip.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            inputField.topAnchor.constraint(equalTo: panel.topAnchor, constant: 12),
            inputField.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            inputField.heightAnchor.constraint(equalToConstant: 24),
            inputField.trailingAnchor.constraint(equalTo: calendarButton.leadingAnchor, constant: -6),
            calendarButton.centerYAnchor.constraint(equalTo: inputField.centerYAnchor),
            calendarButton.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            calendarButton.widthAnchor.constraint(equalToConstant: 24),
            calendarButton.heightAnchor.constraint(equalToConstant: 24),
            chipTop,
            chipHeight,
            chip.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            scrollView.topAnchor.constraint(equalTo: chip.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -12),
            tableHeight,
        ])
        reload()
    }

    var today: Day { Day.today }

    func reload() {
        guard isViewLoaded else { onChange?(); return }
        let pending = captureEdit()
        let document = store.document
        rows = []
        for group in document.groups() {
            rows.append(.header(title: group.title, open: group.openCount))
            for index in group.indices { rows.append(.task(document.ref(.tasks, index))) }
        }
        if rows.isEmpty { rows.append(.empty) }
        tableView.reloadData()
        updateSize()
        restoreEdit(pending)
        onChange?()
    }

    private func updateSize() {
        let total = (0..<rows.count).reduce(CGFloat(0)) { $0 + height(ofRow: $1) }
        let listHeight = min(total, maxPanelHeight - chromeHeight)
        tableHeight.constant = listHeight
        preferredContentSize = NSSize(width: panelWidth, height: listHeight + chromeHeight)
    }

    func focusInput() {
        view.window?.makeFirstResponder(inputField)
    }

    func endInlineEditing() {
        guard isViewLoaded, let editor = view.window?.firstResponder as? NSTextView, editor.delegate !== inputField, view.window?.fieldEditor(false, for: nil) === editor else { return }
        view.window?.makeFirstResponder(nil)
    }

    private func editingRowView() -> (Int, TaskRef, TaskRowView)? {
        for (row, entry) in rows.enumerated() {
            guard case .task(let ref) = entry, let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TaskRowView, rowView.editing else { continue }
            return (row, ref, rowView)
        }
        return nil
    }

    private func captureEdit() -> (ref: TaskRef, text: String, selection: NSRange?)? {
        guard let (_, ref, rowView) = editingRowView() else { return nil }
        let state = (ref, rowView.textField.stringValue, rowView.editSelection)
        rowView.abandonEditing()
        return state
    }

    private func restoreEdit(_ pending: (ref: TaskRef, text: String, selection: NSRange?)?) {
        guard let pending, let row = rowIndex(of: pending.ref) else { return }
        tableView.layoutSubtreeIfNeeded()
        tableView.scrollRowToVisible(row)
        guard let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? TaskRowView else { return }
        rowView.beginEditing(text: pending.text, selection: pending.selection)
    }

    private func rowIndex(of ref: TaskRef) -> Int? {
        rows.firstIndex { entry in
            guard case .task(let candidate) = entry else { return false }
            return candidate.item == ref.item && candidate.occurrence == ref.occurrence
        }
    }

    private func rowView(of ref: TaskRef) -> TaskRowView? {
        guard let row = rowIndex(of: ref) else { return nil }
        return tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TaskRowView
    }

    private func height(ofRow row: Int) -> CGFloat {
        switch rows[row] {
        case .header: return row == 0 ? 22 : 28
        case .task, .empty: return 28
        }
    }

    private func apply(_ change: (inout Document) -> Bool) {
        endInlineEditing()
        var found = true
        let threshold = hideDoneMode.threshold
        let now = Date()
        let written = store.mutate { document in
            found = change(&document)
            document.sweep(now: now, threshold: threshold)
        }
        if !found { log("task is no longer in the file, change discarded") }
        if !found || !written { NSSound.beep() }
        reload()
    }

    @objc private func addTask() {
        var raw = inputField.stringValue
        if let range = suggestionRange, let editor = inputField.currentEditor(), editor.selectedRange == range, range.location + range.length == (raw as NSString).length {
            raw = (raw as NSString).replacingCharacters(in: range, with: "")
        }
        let parsed = DateInput.split(raw, today: today)
        let item = pendingDue.map { TodoItem(source: raw, due: $0) } ?? TodoItem(source: parsed.text, due: parsed.due)
        guard !item.text.isEmpty, item.text != ";" else {
            NSSound.beep()
            return
        }
        apply { document in
            document.tasks.append(item)
            return true
        }
        inputField.stringValue = ""
        lastTypedLength = 0
        suggestionRange = nil
        setPendingDue(nil)
    }

    private func setPendingDue(_ day: Day?) {
        pendingDue = day
        chip.isHidden = day == nil
        chip.set(text: day?.shortLabel ?? "")
        chipTop.constant = day == nil ? 0 : 6
        chipHeight.constant = day == nil ? 0 : 20
        updateSize()
        if inputField.currentEditor() != nil {
            view.window?.makeKey()
        } else {
            focusInput()
            inputField.currentEditor()?.selectedRange = NSRange(location: (inputField.stringValue as NSString).length, length: 0)
        }
    }

    @objc private func pickInputDate() {
        showDatePicker(relativeTo: calendarButton, current: pendingDue) { [weak self] day in self?.setPendingDue(day) }
    }

    private func showDatePicker(relativeTo anchor: NSView, current: Day?, completion: @escaping (Day?) -> Void) {
        if datePopover.isShown { datePopover.performClose(nil) }
        datePicker.prepare(current: current)
        datePicker.onPick = { [weak self] day in
            self?.datePopover.performClose(nil)
            completion(day)
        }
        datePopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    private func clickedRow() -> (TaskRef, TaskRowView)? {
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, case .task(let ref) = rows[row],
              let rowView = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? TaskRowView else { return nil }
        return (ref, rowView)
    }

    @objc private func rowDoubleClicked() {
        guard let (ref, rowView) = clickedRow(), let event = NSApp.currentEvent, rowView.hitsText(event.locationInWindow) else { return }
        startEditing(ref)
    }

    private func startEditing(_ ref: TaskRef) {
        endInlineEditing()
        guard let row = rowIndex(of: ref) else { return }
        tableView.layoutSubtreeIfNeeded()
        tableView.scrollRowToVisible(row)
        (tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? TaskRowView)?.beginEditing()
    }

    private func toggle(_ ref: TaskRef) {
        let now = Date()
        apply { document in
            guard let index = document.index(of: ref) else { return false }
            document[ref.section][index].setDone(!ref.item.done, now: now)
            return true
        }
    }

    private func delete(_ ref: TaskRef) {
        apply { document in
            guard let index = document.index(of: ref) else { return false }
            document[ref.section].remove(at: index)
            return true
        }
    }

    private func rename(_ ref: TaskRef, to source: String, toggling: Bool) {
        let edited = TodoItem(source: source)
        let now = Date()
        apply { document in
            guard let index = document.index(of: ref) else { return false }
            if !edited.text.isEmpty {
                document[ref.section][index].project = edited.project
                document[ref.section][index].text = edited.text
                document[ref.section][index].due = edited.due ?? ref.item.due
            }
            if toggling { document[ref.section][index].setDone(!ref.item.done, now: now) }
            return true
        }
    }

    private func setDue(_ ref: TaskRef, _ day: Day?) {
        apply { document in
            guard let index = document.index(of: ref) else { return false }
            document[ref.section][index].due = day
            return true
        }
    }

    private func editDeadline(_ ref: TaskRef, anchor: NSView) {
        endInlineEditing()
        let target: NSView = anchor.window != nil ? anchor : (rowView(of: ref) ?? tableView)
        showDatePicker(relativeTo: target, current: ref.item.due) { [weak self] day in self?.setDue(ref, day) }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { height(ofRow: row) }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let title, let open):
            let label = NSTextField(labelWithString: title)
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.lineBreakMode = .byTruncatingTail
            let count = NSTextField(labelWithString: open > 0 ? String(open) : "")
            count.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
            count.textColor = .tertiaryLabelColor
            let container = NSView()
            for view in [label, count] {
                view.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(view)
            }
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
                label.trailingAnchor.constraint(lessThanOrEqualTo: count.leadingAnchor, constant: -8),
                count.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                count.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            ])
            return container
        case .empty:
            let label = NSTextField(labelWithString: "Nothing to do")
            label.font = .systemFont(ofSize: 12)
            label.textColor = .tertiaryLabelColor
            let container = NSView()
            label.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
                label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            return container
        case .task(let ref):
            let rowView = TaskRowView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 28))
            rowView.configure(ref.item, today: today)
            rowView.onToggle = { [weak self] in self?.toggle(ref) }
            rowView.onDelete = { [weak self] in self?.delete(ref) }
            rowView.onEdit = { [weak self] in self?.startEditing(ref) }
            rowView.onDeadline = { [weak self, weak rowView] in
                guard let rowView else { return }
                self?.editDeadline(ref, anchor: rowView)
            }
            rowView.onCommit = { [weak self] source, toggling in self?.rename(ref, to: source, toggling: toggling) }
            rowView.onCancelEdit = { [weak self] in self?.reload() }
            return rowView
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, row < rows.count, case .task(let ref) = rows[row] else { return }
        for (title, action) in [("Edit", #selector(contextEdit(_:))), ("Deadline…", #selector(contextDeadline(_:))), ("Delete", #selector(contextDelete(_:)))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = RefBox(ref)
            menu.addItem(item)
        }
    }

    private func contextTarget(_ sender: NSMenuItem) -> (TaskRef, TaskRowView?)? {
        guard let box = sender.representedObject as? RefBox else { return nil }
        return (box.ref, rowView(of: box.ref))
    }

    @objc private func contextEdit(_ sender: NSMenuItem) {
        guard let (ref, _) = contextTarget(sender) else { return }
        startEditing(ref)
    }

    @objc private func contextDeadline(_ sender: NSMenuItem) {
        guard let (ref, rowView) = contextTarget(sender) else { return }
        editDeadline(ref, anchor: rowView ?? tableView)
    }

    @objc private func contextDelete(_ sender: NSMenuItem) {
        guard let (ref, _) = contextTarget(sender) else { return }
        delete(ref)
    }

    func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === inputField, !suggesting, let editor = inputField.currentEditor() as? NSTextView else { return }
        let typed = editor.string
        let previous = lastTypedLength
        lastTypedLength = typed.count
        suggestionRange = nil
        let end = (typed as NSString).length
        guard typed.count > previous, !typed.isEmpty, !typed.contains(";"), editor.selectedRange() == NSRange(location: end, length: 0) else { return }
        guard let match = store.document.projectNames.first(where: { $0.range(of: typed, options: [.caseInsensitive, .anchored]) != nil }),
              let range = match.range(of: typed, options: [.caseInsensitive, .anchored]) else { return }
        let completion = String(match[range.upperBound...]) + "; "
        suggesting = true
        editor.insertText(completion, replacementRange: NSRange(location: end, length: 0))
        let suggested = NSRange(location: end, length: (completion as NSString).length)
        editor.setSelectedRange(suggested)
        suggestionRange = suggested
        suggesting = false
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === inputField else { return false }
        if selector == #selector(NSResponder.insertTab(_:)), let range = suggestionRange, textView.selectedRange() == range {
            textView.setSelectedRange(NSRange(location: range.location + range.length, length: 0))
            suggestionRange = nil
            lastTypedLength = textView.string.count
            return true
        }
        guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        onClose?()
        return true
    }
}

final class SettingsWindowController: NSWindowController {
    private let immediatelyButton: NSButton
    private let after24Button: NSButton
    var onModeChange: ((HideDoneMode) -> Void)?
    var onOpenFile: (() -> Void)?
    var onRevealFile: (() -> Void)?

    init(path: String, mode: HideDoneMode) {
        immediatelyButton = NSButton(radioButtonWithTitle: "Hide immediately", target: nil, action: nil)
        after24Button = NSButton(radioButtonWithTitle: "Hide after 24 h", target: nil, action: nil)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 100), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.level = .floating
        window.isReleasedWhenClosed = false
        super.init(window: window)

        for button in [immediatelyButton, after24Button] {
            button.target = self
            button.action = #selector(modeChanged(_:))
        }
        select(mode)

        let pathLabel = NSTextField(wrappingLabelWithString: path)
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.isSelectable = true
        pathLabel.preferredMaxLayoutWidth = 352

        let openButton = NSButton(title: "Open file", target: self, action: #selector(openFile))
        let revealButton = NSButton(title: "Show in Finder", target: self, action: #selector(revealFile))
        let buttons = NSStackView(views: [openButton, revealButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let radios = NSStackView(views: [immediatelyButton, after24Button])
        radios.orientation = .vertical
        radios.alignment = .leading
        radios.spacing = 4

        let shortcut = NSTextField(labelWithString: "⌃⌥N opens the panel")
        shortcut.font = .systemFont(ofSize: 13)
        shortcut.textColor = .secondaryLabelColor

        let root = NSStackView(views: [
            Self.heading("Completed tasks"), radios,
            Self.spacer(), Self.heading("Task file"), pathLabel, buttons,
            Self.spacer(), Self.heading("Shortcut"), shortcut,
        ])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 6
        root.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        root.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            root.widthAnchor.constraint(equalToConstant: 380),
        ])
        window.contentView = content
        content.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    private static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private static func spacer() -> NSView {
        let view = NSView()
        view.heightAnchor.constraint(equalToConstant: 6).isActive = true
        return view
    }

    func select(_ mode: HideDoneMode) {
        immediatelyButton.state = mode == .immediately ? .on : .off
        after24Button.state = mode == .after24h ? .on : .off
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func modeChanged(_ sender: NSButton) {
        let mode: HideDoneMode = sender === immediatelyButton ? .immediately : .after24h
        select(mode)
        onModeChange?(mode)
    }

    @objc private func openFile() { onOpenFile?() }
    @objc private func revealFile() { onRevealFile?() }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let defaults = UserDefaults.standard
    private let defaultDataPath = NSHomeDirectory() + "/Documents/tasks.md"
    private var store: TaskStore!
    private var panel: PanelViewController!
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController?
    private let statusMenu = NSMenu()
    private let popover = NSPopover()
    private var hotKey: EventHotKeyRef?
    private var midnightTimer: Timer?
    private var sweepTimer: Timer?
    private var lastClosed = Date.distantPast
    private var outsideMonitor: Any?
    private var hideDoneMode = HideDoneMode.after24h

    func applicationDidFinishLaunching(_ notification: Notification) {
        let path = defaults.string(forKey: "dataPath") ?? defaultDataPath
        defaults.removeObject(forKey: "hideDone")
        hideDoneMode = HideDoneMode(rawValue: defaults.string(forKey: HideDoneMode.defaultsKey) ?? "") ?? .after24h
        store = TaskStore(path: path)
        store.load()
        store.onExternalChange = { [weak self] in self?.refresh() }
        store.startWatching()

        panel = PanelViewController(store: store)
        panel.hideDoneMode = hideDoneMode
        panel.onChange = { [weak self] in self?.updateCount() }
        panel.onClose = { [weak self] in self?.closePopover() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = panel
        popover.delegate = self

        NSApp.mainMenu = buildMainMenu()
        performSweep()
        scheduleMidnight()
        scheduleHourlySweep()
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(clockChanged), name: NSWorkspace.didWakeNotification, object: nil)
        registerHotKey()
        updateCount()
        log("started, task file \(path), completed mode \(hideDoneMode.rawValue)")
    }

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let closeItem = NSMenuItem(title: "Close", action: #selector(closeFrontmost), keyEquivalent: "w")
        closeItem.target = self
        appMenu.addItem(closeItem)
        appMenu.addItem(NSMenuItem(title: "Quit Todo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        return mainMenu
    }

    private static let iconSVG = "<svg width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"24\" height=\"24\" fill=\"white\" fill-opacity=\"0.25\"/><path transform=\"translate(12 12) scale(0.72) translate(-12 -12) scale(0.025) translate(0 960)\" fill=\"white\" d=\"M200-120q-33 0-56.5-23.5T120-200v-560q0-33 23.5-56.5T200-840h560q33 0 56.5 23.5T840-760v308L694-306l-85-85-170 169 102 102H200Zm240-320h240v-80H440v80Zm0-160h240v-80H440v80ZM694-80 552-222l57-56 85 85 170-170 56 57L694-80ZM348.5-451.5Q360-463 360-480t-11.5-28.5Q337-520 320-520t-28.5 11.5Q280-497 280-480t11.5 28.5Q303-440 320-440t28.5-11.5Zm0-160Q360-623 360-640t-11.5-28.5Q337-680 320-680t-28.5 11.5Q280-657 280-640t11.5 28.5Q303-600 320-600t28.5-11.5Z\"/></svg>"

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(data: Data(iconSVG.utf8)) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Todo"
        return image
    }

    private func updateCount() {
        guard let button = statusItem?.button else { return }
        let count = store.document.dueCount(today: Day.today)
        button.title = count > 0 ? " \(count)" : ""
        button.imagePosition = count > 0 ? .imageLeading : .imageOnly
    }

    private func refresh() {
        if popover.isShown { panel.reload() } else { updateCount() }
    }

    private func performSweep() {
        let threshold = hideDoneMode.threshold
        let now = Date()
        store.mutate { $0.sweep(now: now, threshold: threshold) }
        refresh()
    }

    private func setHideDoneMode(_ mode: HideDoneMode) {
        hideDoneMode = mode
        defaults.set(mode.rawValue, forKey: HideDoneMode.defaultsKey)
        panel.hideDoneMode = mode
        performSweep()
        log("completed tasks mode: \(mode.rawValue)")
    }

    @objc private func openSettings() {
        if settings == nil {
            let controller = SettingsWindowController(path: store.path, mode: hideDoneMode)
            controller.onModeChange = { [weak self] mode in self?.setHideDoneMode(mode) }
            controller.onOpenFile = { [weak self] in self?.openDataFile() }
            controller.onRevealFile = { [weak self] in self?.revealDataFile() }
            settings = controller
        }
        settings?.select(hideDoneMode)
        settings?.show()
    }

    private func openDataFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: store.path))
    }

    private func revealDataFile() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: store.path)])
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            closePopover()
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
            return
        }
        togglePopover()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else if Date().timeIntervalSince(lastClosed) > 0.25 {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        store.checkForExternalChange()
        panel.loadViewIfNeeded()
        performSweep()
        panel.reload()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        panel.focusInput()
        if outsideMonitor == nil {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                guard let self, self.popover.isShown, self.settings?.window?.isKeyWindow != true, self.datePopoverIsShown == false else { return }
                self.closePopover()
            }
        }
    }

    private var datePopoverIsShown: Bool { panel.isDatePickerShown }

    @objc private func closePopover() {
        guard popover.isShown else { return }
        panel.endInlineEditing()
        popover.performClose(nil)
    }

    func popoverWillClose(_ notification: Notification) {
        panel.endInlineEditing()
    }

    @objc private func closeFrontmost() {
        if let window = settings?.window, window.isKeyWindow {
            window.performClose(nil)
        } else {
            closePopover()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastClosed = Date()
        updateCount()
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
    }

    func popoverDidShow(_ notification: Notification) {
        panel.focusInput()
    }

    private func scheduleMidnight() {
        midnightTimer?.invalidate()
        guard let midnight = Day.calendar.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) else { return }
        let timer = Timer(fire: midnight.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            self?.performSweep()
            self?.scheduleMidnight()
        }
        RunLoop.main.add(timer, forMode: .common)
        midnightTimer = timer
    }

    private func scheduleHourlySweep() {
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in self?.performSweep() }
        timer.tolerance = 120
        RunLoop.main.add(timer, forMode: .common)
        sweepTimer = timer
    }

    @objc private func clockChanged() {
        performSweep()
        scheduleMidnight()
    }

    fileprivate func handleHotKey() {
        if popover.isShown {
            NSApp.activate(ignoringOtherApps: true)
            panel.focusInput()
        } else {
            showPopover()
        }
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            delegate.handleHotKey()
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let signature = OSType(0x544F444F)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey), EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &hotKey)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
