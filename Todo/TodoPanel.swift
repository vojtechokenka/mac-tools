import AppKit

enum TodoLayout {
    static let width: CGFloat = 420
    static let maxHeight: CGFloat = 640
    static var doubleClickWindow: TimeInterval { min(NSEvent.doubleClickInterval, 0.35) }
    static let toggleDelay: TimeInterval = 1.5
    static let top: CGFloat = 12
    static let bottom: CGFloat = 8
    static let side: CGFloat = 16
    static let addTrailing: CGFloat = 12
    static let fieldHeight: CGFloat = 32
    static let blockGap: CGFloat = 10
    static let optionsHeight: CGFloat = 24
    static let optionsBottom: CGFloat = 12
    static let groupPadding: CGFloat = 6
    static let headerHeight: CGFloat = 24
    static let rowPadding: CGFloat = 6
    static let lineHeight: CGFloat = 20
    static let tagGap: CGFloat = 3
    static let tagHeight: CGFloat = 15
    static let tagBottom: CGFloat = 2
    static let checkGap: CGFloat = 12
    static let minRowHeight: CGFloat = 30
    static let editInset: CGFloat = 12
    static let editPadding: CGFloat = 2
    static let actionsInset: CGFloat = 10
    static let actionsFade: CGFloat = 18
    static let projectMaxWidth: CGFloat = 120
}

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run(_ sender: Any?) { handler() }

    static func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = action
        item.representedObject = action
        return item
    }
}

final class GroupHeaderView: DSView {
    let title: String
    let count: Int

    init(title: String, count: Int) {
        self.title = title
        self.count = count
        super.init()
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let font = DS.smallFont
        let countFont = DS.font(11, .semibold)
        let countText = String(count)
        let countWidth = ceil(DSText.width(countText, font: countFont))
        let top = TodoLayout.groupPadding
        let available = bounds.width - 2 * TodoLayout.side - DS.gapTight - countWidth
        let titleWidth = DSText.draw(title, in: NSRect(x: TodoLayout.side, y: top, width: max(available, 0), height: 14), font: font, color: DS.muted)
        DSText.draw(countText, in: NSRect(x: TodoLayout.side + titleWidth + DS.gapTight, y: top, width: countWidth, height: 14), font: countFont, color: DS.text, truncates: false)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityValue() -> Any? { "\(title), \(count) open" }
}

final class RowActionsView: FlippedView {
    let dateButton = DSIconButton(.calendarToday, label: "Deadline")
    let editButton = DSIconButton(.edit, label: "Edit")
    let deleteButton = DSIconButton(.close, label: "Delete")

    static var size: NSSize {
        NSSize(width: TodoLayout.actionsFade + 3 * DS.iconButtonSize, height: DS.iconButtonSize)
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        dateButton.toolTip = "Deadline"
        editButton.toolTip = "Edit"
        deleteButton.toolTip = "Delete"
        for (index, button) in [dateButton, editButton, deleteButton].enumerated() {
            button.frame = NSRect(x: TodoLayout.actionsFade + CGFloat(index) * DS.iconButtonSize, y: 0, width: DS.iconButtonSize, height: DS.iconButtonSize)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let solid = DS.resolved(DS.sunken, for: effectiveAppearance)
        let fade = NSRect(x: 0, y: 0, width: TodoLayout.actionsFade, height: bounds.height)
        NSGradient(starting: solid.withAlphaComponent(0), ending: solid)?.draw(in: fade, angle: 0)
        DSDraw.fill(NSRect(x: TodoLayout.actionsFade, y: 0, width: bounds.width - TodoLayout.actionsFade, height: bounds.height), solid)
    }
}

final class TaskRowView: FlippedView, NSTextFieldDelegate {
    let ref: TaskRef
    let checkBox = DSCheckbox(label: "Done")
    let textLabel = DSLabel()
    let projectLabel = DSLabel("", size: 11, color: DS.muted)
    let actions = RowActionsView(frame: NSRect(origin: .zero, size: RowActionsView.size))
    private(set) var dueTag: DSTag?
    private(set) var editField: DSTextField?
    var onToggle: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDeadline: (() -> Void)?
    var onCommit: ((String) -> Void)?
    var onCancelEdit: (() -> Void)?
    var onResize: (() -> Void)?
    var contextMenu: (() -> NSMenu?)?
    var onPointerMove: (() -> Void)?
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var pendingToggle = false { didSet { if pendingToggle != oldValue { updateDoneLook() } } }
    private var pressed = false
    private var pressTime: TimeInterval = 0
    var previewHover = false { didSet { updateChrome() } }
    private(set) var editing = false
    private var hasActions: Bool { !ref.item.done }
    private var showsProject = false
    private var hovered = false { didSet { if hovered != oldValue { updateChrome() } } }
    private var editCancelled = false
    private var editAbandoned = false
    private var trackingArea: NSTrackingArea?

    init(ref: TaskRef, today: Day, showsProject: Bool) {
        self.ref = ref
        super.init(frame: NSRect(x: 0, y: 0, width: TodoLayout.width, height: 32))
        let item = ref.item
        checkBox.isOn = item.done
        checkBox.onChange = { [weak self] _ in self?.onToggle?() }
        textLabel.text = item.text
        textLabel.maxLines = 0
        textLabel.lineHeight = TodoLayout.lineHeight
        textLabel.color = item.done ? DS.muted : DS.text
        textLabel.isStruck = item.done
        if item.done {
            dueTag = DSTag(DateInput.doneLabel(item.completed, today: today), style: .plain, small: true)
        } else if let deadline = DateInput.countdown(due: item.due, today: today) {
            let style: DSTag.Style
            switch deadline.tone {
            case .overdue: style = .red
            case .today: style = .blue
            case .soon: style = .amber
            case .later: style = .neutral
            }
            let tag = DSTag(deadline.text, style: style, small: true)
            tag.toolTip = item.due?.fullLabel
            self.dueTag = tag
        }
        self.showsProject = showsProject && item.project != nil
        projectLabel.text = item.project ?? ""
        actions.dateButton.onClick = { [weak self] in self?.onDeadline?() }
        actions.editButton.onClick = { [weak self] in self?.onEdit?() }
        actions.deleteButton.onClick = { [weak self] in self?.onDelete?() }
        for view in [checkBox, textLabel, projectLabel] as [NSView] { addSubview(view) }
        if let dueTag { addSubview(dueTag) }
        addSubview(actions)
        updateChrome()
    }

    required init?(coder: NSCoder) { nil }

    private var projectWidth: CGFloat {
        guard showsProject else { return 0 }
        return min(ceil(DSText.width(projectLabel.text, font: projectLabel.font)), TodoLayout.projectMaxWidth)
    }

    @discardableResult
    func fit(width: CGFloat) -> CGFloat {
        if editing {
            let height = DS.controlHeight + 2 * TodoLayout.editPadding
            editField?.frame = NSRect(x: TodoLayout.editInset, y: TodoLayout.editPadding, width: width - 2 * TodoLayout.editInset, height: DS.controlHeight)
            setFrameSize(NSSize(width: width, height: height))
            return height
        }
        let pad = TodoLayout.rowPadding
        let textX = TodoLayout.side + DSCheckbox.boxSize + TodoLayout.checkGap
        let project = projectWidth
        let textRight = width - TodoLayout.side - (project > 0 ? project + TodoLayout.checkGap : 0)
        let textWidth = max(textRight - textX, 40)
        let textHeight = max(textLabel.height(forWidth: textWidth), TodoLayout.lineHeight)
        textLabel.frame = NSRect(x: textX, y: pad, width: textWidth, height: textHeight)
        var contentHeight = textHeight
        if let tag = dueTag {
            tag.sizeToFit()
            tag.frame.origin = NSPoint(x: textX, y: pad + textHeight + TodoLayout.tagGap)
            contentHeight += TodoLayout.tagGap + TodoLayout.tagHeight + TodoLayout.tagBottom
        }
        projectLabel.frame = NSRect(x: width - TodoLayout.side - project, y: pad, width: project, height: TodoLayout.lineHeight)
        let height = max(contentHeight + 2 * pad, TodoLayout.minRowHeight)
        checkBox.frame = NSRect(x: TodoLayout.side, y: (pad + (contentHeight - DSCheckbox.boxSize) / 2).rounded(), width: DSCheckbox.boxSize, height: DSCheckbox.boxSize)
        let size = RowActionsView.size
        actions.frame = NSRect(x: width - TodoLayout.actionsInset - size.width, y: ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
        setFrameSize(NSSize(width: width, height: height))
        return height
    }

    private var showsHover: Bool { (hovered || previewHover) && !editing }

    private func updateChrome() {
        let hover = showsHover
        actions.isHidden = !hover || !hasActions
        projectLabel.isHidden = !showsProject || editing || (hover && hasActions)
        for view in [checkBox, textLabel] as [NSView] { view.isHidden = editing }
        dueTag?.isHidden = editing
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        if showsHover { DSDraw.fill(bounds, DS.sunken) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingArea == nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    func syncHoverWithPointer() {
        guard let window else { return }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        hovered = window.isVisible && bounds.intersection(visibleRect).contains(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncHoverWithPointer()
    }

    override func mouseEntered(with event: NSEvent) { pointerMoved() }
    override func mouseExited(with event: NSEvent) { pointerMoved() }

    private func pointerMoved() {
        if let onPointerMove {
            onPointerMove()
        } else {
            syncHoverWithPointer()
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !editing else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        if !ref.item.done, let tag = dueTag, tag.frame.contains(point) {
            pressed = false
            onDeadline?()
            return
        }
        if pendingToggle, event.timestamp - pressTime <= TodoLayout.doubleClickWindow {
            pressed = false
            onDoubleClick?()
            return
        }
        pressed = true
        pressTime = event.timestamp
    }

    private func updateDoneLook() {
        let done = ref.item.done != pendingToggle
        checkBox.isOn = done
        textLabel.color = done ? DS.muted : DS.text
        textLabel.isStruck = done
    }

    override func mouseUp(with event: NSEvent) {
        guard pressed else { return super.mouseUp(with: event) }
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu?()
    }

    var editText: String? { editField?.stringValue }
    var editSelection: NSRange? { editing ? editField?.currentEditor()?.selectedRange : nil }

    private func installEditField(text: String) -> DSTextField {
        let field = DSTextField(text: text)
        field.delegate = self
        field.setAccessibilityLabel("Edit task")
        addSubview(field)
        editField = field
        editing = true
        updateChrome()
        fit(width: bounds.width)
        onResize?()
        return field
    }

    func showEditPreview(text: String? = nil) {
        guard !editing else { return }
        installEditField(text: text ?? ref.item.editLine).showsFocusStyle = true
    }

    func beginEditing(text: String? = nil, selection: NSRange? = nil) {
        guard !editing, let window else { return }
        editCancelled = false
        editAbandoned = false
        let field = installEditField(text: text ?? ref.item.editLine)
        scrollToVisible(bounds)
        window.makeFirstResponder(field)
        guard editing, let editor = field.currentEditor() else {
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

    func commitEditing() {
        guard editing else { return }
        if let window, let editor = window.firstResponder as? NSTextView, editor.delegate === editField {
            window.makeFirstResponder(nil)
        }
        finishEditing()
    }

    private func finishEditing() {
        guard editing, let field = editField else { return }
        editing = false
        field.delegate = nil
        field.removeFromSuperview()
        editField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        updateChrome()
        fit(width: bounds.width)
        onResize?()
        if editAbandoned { return }
        if editCancelled {
            onCancelEdit?()
        } else {
            onCommit?(text)
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

    override func isAccessibilityElement() -> Bool { false }
}

final class DatePickerController: NSViewController {
    private let picker = NSDatePicker()
    private lazy var clearButton = DSButton("No deadline") { [weak self] in self?.clear() }
    private lazy var applyButton = DSButton("Apply", style: .primary) { [weak self] in self?.apply() }
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
        picker.sizeToFit()
        clearButton.sizeToFit()
        applyButton.sizeToFit()
        let margin: CGFloat = 12
        let pickerSize = picker.frame.size
        let buttonsWidth = clearButton.frame.width + DS.gapTight + applyButton.frame.width
        let width = max(pickerSize.width, buttonsWidth) + 2 * margin
        let root = FlippedView(frame: NSRect(x: 0, y: 0, width: width, height: margin + pickerSize.height + DS.gap + DS.controlHeight + margin))
        picker.frame.origin = NSPoint(x: ((width - pickerSize.width) / 2).rounded(), y: margin)
        let buttonsY = margin + pickerSize.height + DS.gap
        clearButton.frame.origin = NSPoint(x: ((width - buttonsWidth) / 2).rounded(), y: buttonsY)
        applyButton.frame.origin = NSPoint(x: clearButton.frame.maxX + DS.gapTight, y: buttonsY)
        for view in [picker, clearButton, applyButton] as [NSView] { root.addSubview(view) }
        view = root
        preferredContentSize = root.frame.size
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

    private func apply() { commit(Day(picker.dateValue)) }

    private func clear() { commit(nil) }
}

final class PanelController: NSObject, NSTextFieldDelegate, NSPopoverDelegate {
    let store: TaskStore
    let view = FlippedView(frame: NSRect(x: 0, y: 0, width: TodoLayout.width, height: 120))
    let inputField = DSTextField(placeholder: "Add a task\u{2026}")
    var onChange: (() -> Void)?
    var onResize: (() -> Void)?
    var onViewOptionsChange: ((SortOrder, Bool) -> Void)?
    var hideDoneMode: HideDoneMode = .after24h
    var heightLimit: CGFloat = TodoLayout.maxHeight
    var today: () -> Day = { Day.today }
    private(set) var sortOrder: SortOrder
    private(set) var grouped: Bool
    private(set) var optionsOpen = false

    private let calendarButton = DSIconButton(.calendarToday, label: "Pick a date")
    private let sortButton = DSIconButton(.sort, label: "Sort and group")
    private let pendingTag = DSTag("", style: .neutral, icon: .calendarToday)
    private let pendingClear = DSIconButton(.close, label: "Clear deadline")
    private let sortLabel = DSLabel("Sort by", color: DS.muted)
    private let sortControl: DSSegmented
    private let groupCheckbox: DSCheckbox
    private let scrollView = NSScrollView()
    private let listView = FlippedView(frame: NSRect(x: 0, y: 0, width: TodoLayout.width, height: 0))
    private let datePopover = NSPopover()
    private let datePicker = DatePickerController()
    private var rowViews: [TaskRowView] = []
    private var pendingToggle: (ref: TaskRef, timer: Timer)?
    private var pendingDue: Day?
    private var lastTypedLength = 0
    private var suggesting = false
    private var suggestionRange: NSRange?
    private var pickerFromInput = false

    init(store: TaskStore, sortOrder: SortOrder, grouped: Bool) {
        self.store = store
        self.sortOrder = sortOrder
        self.grouped = grouped
        sortControl = DSSegmented(SortOrder.allCases.map(\.title), selectedIndex: SortOrder.allCases.firstIndex(of: sortOrder) ?? 1, label: "Sort by")
        groupCheckbox = DSCheckbox("Group by project", isOn: grouped)
        super.init()

        inputField.setAccessibilityLabel("Add a task")
        inputField.delegate = self
        inputField.target = self
        inputField.action = #selector(addTask)
        calendarButton.toolTip = "Deadline"
        calendarButton.onClick = { [weak self] in self?.pickInputDate() }
        sortButton.toolTip = "Sort and group"
        sortButton.onClick = { [weak self] in self?.setOptionsOpen(!(self?.optionsOpen ?? false)) }
        pendingClear.iconSize = 14
        pendingClear.toolTip = "Clear deadline"
        pendingClear.onClick = { [weak self] in self?.setPendingDue(nil) }
        sortControl.equalWidths = false
        sortControl.isCompact = true
        sortControl.sizeToFit()
        sortControl.onChange = { [weak self] index in self?.setSortOrder(SortOrder.allCases[index]) }
        groupCheckbox.sizeToFit()
        groupCheckbox.onChange = { [weak self] on in self?.setGrouped(on) }
        sortLabel.sizeToFit()

        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.documentView = listView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(pointerContextChanged), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        scrollView.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))

        datePopover.behavior = .transient
        datePopover.animates = true
        datePopover.contentViewController = datePicker
        datePopover.delegate = self

        for subview in [inputField, calendarButton, sortButton, pendingTag, pendingClear, sortLabel, sortControl, groupCheckbox, scrollView] as [NSView] {
            view.addSubview(subview)
        }
        reload()
    }

    func reload() {
        let pending = captureEdit()
        rebuildRows()
        if let toggling = pendingToggle {
            if let row = rowView(of: toggling.ref) {
                row.pendingToggle = true
            } else {
                toggling.timer.invalidate()
                pendingToggle = nil
            }
        }
        layout()
        restoreEdit(pending)
        onChange?()
    }

    private func rebuildRows() {
        for subview in listView.subviews { subview.removeFromSuperview() }
        rowViews = []
        let document = store.document
        let day = today()
        var sections: [(header: GroupHeaderView?, indices: [Int])] = []
        if grouped {
            for group in document.groups(sortedBy: sortOrder) {
                sections.append((GroupHeaderView(title: group.title, count: group.openCount), group.indices))
            }
        } else if !document.tasks.isEmpty {
            sections.append((nil, document.sortedTaskIndices(by: sortOrder)))
        }
        if sections.isEmpty {
            listView.addSubview(DSSeparator())
            let empty = DSLabel("Nothing to do", color: DS.muted)
            empty.identifier = NSUserInterfaceItemIdentifier("empty")
            listView.addSubview(empty)
            return
        }
        for section in sections {
            listView.addSubview(DSSeparator())
            if let header = section.header { listView.addSubview(header) }
            for index in section.indices {
                let ref = document.ref(.tasks, index)
                let row = TaskRowView(ref: ref, today: day, showsProject: !grouped)
                wire(row)
                rowViews.append(row)
                listView.addSubview(row)
            }
        }
    }

    private func wire(_ row: TaskRowView) {
        let ref = row.ref
        row.onToggle = { [weak self] in
            self?.endInlineEditing()
            self?.scheduleToggle(ref)
        }
        row.onClick = { [weak self] in self?.rowClicked(ref) }
        row.onDoubleClick = { [weak self] in self?.startEditing(ref) }
        row.onDelete = { [weak self] in self?.delete(ref) }
        row.onEdit = { [weak self] in self?.startEditing(ref) }
        row.onDeadline = { [weak self, weak row] in
            guard let self, let row else { return }
            self.editDeadline(ref, anchor: row)
        }
        row.onCommit = { [weak self] source in self?.rename(ref, to: source) }
        row.onCancelEdit = { [weak self] in self?.reload() }
        row.onResize = { [weak self] in self?.layout() }
        row.contextMenu = { [weak self] in self?.contextMenu(for: ref) }
        row.onPointerMove = { [weak self] in self?.syncHover() }
    }

    func syncHover() {
        for row in rowViews { row.syncHoverWithPointer() }
    }

    private func rowClicked(_ ref: TaskRef) {
        if editingRow() != nil {
            endInlineEditing()
            return
        }
        scheduleToggle(ref)
    }

    private func scheduleToggle(_ ref: TaskRef) {
        if settlePendingToggle(for: ref) { return }
        let timer = Timer(timeInterval: TodoLayout.toggleDelay, repeats: false) { [weak self] _ in self?.flushPendingToggle() }
        RunLoop.main.add(timer, forMode: .common)
        pendingToggle = (ref, timer)
        rowView(of: ref)?.pendingToggle = true
    }

    @discardableResult
    private func settlePendingToggle(for ref: TaskRef) -> Bool {
        guard let pending = pendingToggle else { return false }
        guard pending.ref.section == ref.section, pending.ref.item == ref.item, pending.ref.occurrence == ref.occurrence else {
            flushPendingToggle()
            return false
        }
        pending.timer.invalidate()
        pendingToggle = nil
        rowView(of: ref)?.pendingToggle = false
        return true
    }

    func flushPendingToggle() {
        guard let pending = pendingToggle else { return }
        pending.timer.invalidate()
        pendingToggle = nil
        toggle(pending.ref)
    }

    @objc private func pointerContextChanged() {
        syncHover()
    }

    @objc func mouseEntered(with event: NSEvent) {
        syncHover()
    }

    @objc func mouseExited(with event: NSEvent) {
        syncHover()
    }

    private func layoutList() -> CGFloat {
        let width = TodoLayout.width
        var y: CGFloat = 0
        for subview in listView.subviews {
            switch subview {
            case is DSSeparator:
                if y > 0 { y += TodoLayout.groupPadding }
                subview.frame = NSRect(x: 0, y: y, width: width, height: 1)
                y += 1 + TodoLayout.groupPadding
            case is GroupHeaderView:
                subview.frame = NSRect(x: 0, y: y, width: width, height: TodoLayout.headerHeight)
                y += TodoLayout.headerHeight
            case let row as TaskRowView:
                let height = row.fit(width: width)
                row.frame.origin = NSPoint(x: 0, y: y)
                y += height
            default:
                subview.frame = NSRect(x: TodoLayout.side, y: y + TodoLayout.rowPadding, width: width - 2 * TodoLayout.side, height: TodoLayout.lineHeight)
                y += TodoLayout.lineHeight + 2 * TodoLayout.rowPadding
            }
        }
        if y > 0 { y += TodoLayout.groupPadding }
        listView.frame = NSRect(x: 0, y: 0, width: width, height: y)
        return y
    }

    func layout() {
        let width = TodoLayout.width
        var y = TodoLayout.top
        let buttonsWidth = 2 * DS.iconButtonSize + 2 * DS.gapTight
        inputField.frame = NSRect(x: TodoLayout.side, y: y, width: width - TodoLayout.side - TodoLayout.addTrailing - buttonsWidth, height: TodoLayout.fieldHeight)
        let buttonY = y + (TodoLayout.fieldHeight - DS.iconButtonSize) / 2
        calendarButton.frame = NSRect(x: inputField.frame.maxX + DS.gapTight, y: buttonY, width: DS.iconButtonSize, height: DS.iconButtonSize)
        sortButton.frame = NSRect(x: calendarButton.frame.maxX + DS.gapTight, y: buttonY, width: DS.iconButtonSize, height: DS.iconButtonSize)
        y += TodoLayout.fieldHeight + TodoLayout.blockGap

        pendingTag.isHidden = pendingDue == nil
        pendingClear.isHidden = pendingDue == nil
        if pendingDue != nil {
            pendingTag.sizeToFit()
            pendingTag.frame.origin = NSPoint(x: TodoLayout.side, y: y + (DS.iconButtonSize - pendingTag.frame.height) / 2)
            pendingClear.frame = NSRect(x: pendingTag.frame.maxX + 2, y: y, width: DS.iconButtonSize, height: DS.iconButtonSize)
            y += DS.iconButtonSize + TodoLayout.blockGap
        }

        for control in [sortLabel, sortControl, groupCheckbox] as [NSView] { control.isHidden = !optionsOpen }
        if optionsOpen {
            let rowHeight = TodoLayout.optionsHeight
            sortLabel.frame = NSRect(x: TodoLayout.side, y: y, width: sortLabel.frame.width, height: rowHeight)
            sortControl.frame.origin = NSPoint(x: sortLabel.frame.maxX + DS.gap, y: y)
            groupCheckbox.frame.origin = NSPoint(x: width - TodoLayout.side - groupCheckbox.frame.width, y: y + (rowHeight - groupCheckbox.frame.height) / 2)
            y += rowHeight + TodoLayout.optionsBottom
        }

        let listHeight = layoutList()
        let chrome = y + TodoLayout.bottom
        let visibleList = max(min(listHeight, heightLimit - chrome), min(listHeight, 120))
        scrollView.frame = NSRect(x: 0, y: y, width: width, height: visibleList)
        y += visibleList + TodoLayout.bottom
        view.setFrameSize(NSSize(width: width, height: y))
        syncHover()
        onResize?()
    }

    func focusInput() {
        view.window?.makeFirstResponder(inputField)
    }

    func endInlineEditing() {
        editingRow()?.commitEditing()
    }

    func closeDatePicker() {
        if datePopover.isShown { datePopover.performClose(nil) }
    }

    func setOptionsOpen(_ open: Bool) {
        optionsOpen = open
        sortButton.isOn = open
        layout()
    }

    private func setSortOrder(_ order: SortOrder) {
        sortOrder = order
        onViewOptionsChange?(sortOrder, grouped)
        reload()
    }

    private func setGrouped(_ on: Bool) {
        grouped = on
        onViewOptionsChange?(sortOrder, grouped)
        reload()
    }

    func previewRow(_ text: String) -> TaskRowView? {
        rowViews.first { $0.ref.item.text == text }
    }

    private func editingRow() -> TaskRowView? {
        rowViews.first { $0.editing }
    }

    private func captureEdit() -> (ref: TaskRef, text: String, selection: NSRange?)? {
        guard let row = editingRow(), let text = row.editText else { return nil }
        let state = (row.ref, text, row.editSelection)
        row.abandonEditing()
        return state
    }

    private func restoreEdit(_ pending: (ref: TaskRef, text: String, selection: NSRange?)?) {
        guard let pending, let row = rowView(of: pending.ref) else { return }
        row.beginEditing(text: pending.text, selection: pending.selection)
    }

    private func rowView(of ref: TaskRef) -> TaskRowView? {
        rowViews.first { $0.ref.item == ref.item && $0.ref.occurrence == ref.occurrence }
    }

    private func apply(_ change: (inout Document) -> Bool) {
        flushPendingToggle()
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
        let parsed = DateInput.split(raw, today: today())
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

    func setPendingDue(_ day: Day?, focus: Bool = true) {
        pendingDue = day
        if let day { pendingTag.text = day.shortLabel }
        pendingTag.toolTip = day?.fullLabel
        layout()
        guard focus else { return }
        if inputField.currentEditor() != nil {
            view.window?.makeKey()
        } else {
            focusInput()
            inputField.currentEditor()?.selectedRange = NSRange(location: (inputField.stringValue as NSString).length, length: 0)
        }
    }

    private func pickInputDate() {
        pickerFromInput = true
        showDatePicker(relativeTo: calendarButton, current: pendingDue) { [weak self] day in self?.setPendingDue(day) }
    }

    private func showDatePicker(relativeTo anchor: NSView, current: Day?, completion: @escaping (Day?) -> Void) {
        let fromInput = pickerFromInput
        pickerFromInput = false
        closeDatePicker()
        pickerFromInput = fromInput
        datePicker.prepare(current: current)
        datePicker.onPick = { [weak self] day in
            self?.datePopover.performClose(nil)
            completion(day)
            self?.regainKey()
        }
        datePopover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    func popoverDidClose(_ notification: Notification) {
        regainKey()
        pickerFromInput = false
    }

    private func regainKey() {
        guard let window = view.window, window.isVisible else { return }
        if !window.isKeyWindow { window.makeKey() }
        if pickerFromInput, !(window.firstResponder is NSText) { focusInput() }
    }

    var datePickerView: NSView {
        datePicker.prepare(current: today())
        return datePicker.view
    }

    private func startEditing(_ ref: TaskRef) {
        settlePendingToggle(for: ref)
        endInlineEditing()
        rowView(of: ref)?.beginEditing()
    }

    private func locator(for ref: TaskRef) -> (Document) -> Int? {
        let expected = store.document.index(of: ref)
        return { document in
            let items = document[ref.section]
            if let expected, items.indices.contains(expected), items[expected] == ref.item { return expected }
            let matches = items.indices.filter { items[$0] == ref.item }
            return matches.count == 1 ? matches[0] : nil
        }
    }

    private func toggle(_ ref: TaskRef) {
        let now = Date()
        let locate = locator(for: ref)
        apply { document in
            guard let index = locate(document) else { return false }
            document[ref.section][index].setDone(!ref.item.done, now: now)
            return true
        }
    }

    private func delete(_ ref: TaskRef) {
        settlePendingToggle(for: ref)
        let locate = locator(for: ref)
        apply { document in
            guard let index = locate(document) else { return false }
            document[ref.section].remove(at: index)
            return true
        }
    }

    private func rename(_ ref: TaskRef, to source: String) {
        guard let edited = ref.item.applyingEdit(source) else { return }
        apply { document in
            guard let index = document.index(of: ref) else { return false }
            document[ref.section][index].project = edited.project
            document[ref.section][index].text = edited.text
            document[ref.section][index].due = edited.due
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
        settlePendingToggle(for: ref)
        endInlineEditing()
        let target: NSView = anchor.window != nil ? anchor : (rowView(of: ref) ?? scrollView)
        showDatePicker(relativeTo: target, current: ref.item.due) { [weak self] day in self?.setDue(ref, day) }
    }

    private func contextMenu(for ref: TaskRef) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(MenuAction.item("Edit") { [weak self] in self?.startEditing(ref) })
        menu.addItem(MenuAction.item("Deadline\u{2026}") { [weak self] in
            guard let self else { return }
            self.editDeadline(ref, anchor: self.rowView(of: ref) ?? self.scrollView)
        })
        menu.addItem(MenuAction.item("Delete") { [weak self] in self?.delete(ref) })
        return menu
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
        return false
    }
}
