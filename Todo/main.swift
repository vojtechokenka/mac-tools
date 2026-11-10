import AppKit
import Carbon.HIToolbox

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let defaults = UserDefaults.standard
    private let defaultDataPath = NSHomeDirectory() + "/Documents/tasks.md"
    private var store: TaskStore!
    private var controller: PanelController!
    private var panel: DSPanel!
    private var statusItem: NSStatusItem!
    private var settings: SettingsWindowController?
    private let statusMenu = NSMenu()
    private var hotKey: EventHotKeyRef?
    private var midnightTimer: Timer?
    private var sweepTimer: Timer?
    private var keyMonitor: Any?
    private var hideDoneMode = HideDoneMode.after24h

    func applicationDidFinishLaunching(_ notification: Notification) {
        DS.registerFonts()
        let path = defaults.string(forKey: "dataPath") ?? defaultDataPath
        defaults.removeObject(forKey: "hideDone")
        hideDoneMode = HideDoneMode(rawValue: defaults.string(forKey: HideDoneMode.defaultsKey) ?? "") ?? .after24h
        store = TaskStore(path: path)
        store.load()
        store.onExternalChange = { [weak self] in self?.refresh() }
        store.startWatching()

        let sortOrder = SortOrder(rawValue: defaults.string(forKey: SortOrder.defaultsKey) ?? "") ?? .deadline
        let grouped = defaults.object(forKey: SortOrder.groupingKey) as? Bool ?? true
        controller = PanelController(store: store, sortOrder: sortOrder, grouped: grouped)
        controller.hideDoneMode = hideDoneMode
        controller.onChange = { [weak self] in self?.updateCount() }
        controller.onViewOptionsChange = { [weak self] order, grouped in
            self?.defaults.set(order.rawValue, forKey: SortOrder.defaultsKey)
            self?.defaults.set(grouped, forKey: SortOrder.groupingKey)
        }

        panel = DSPanel(width: TodoLayout.width, content: controller.view)
        panel.maxHeight = TodoLayout.maxHeight
        panel.initialFirstResponder = controller.inputField
        panel.onClose = { [weak self] in self?.panelDidClose() }
        controller.onResize = { [weak self] in
            guard let self, self.panel.isShown else { return }
            self.panel.sizeToContent()
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusMenu.addItem(withTitle: "Settings\u{2026}", action: #selector(openSettings), keyEquivalent: "").target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(DSBrand.menuItem())
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        NSApp.mainMenu = buildMainMenu()
        installKeyMonitor()
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

    func applicationWillTerminate(_ notification: Notification) {
        controller?.endInlineEditing()
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

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isShown, self.panel.isKeyWindow,
                  event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w":
                self.closePanel()
                return nil
            case "q":
                NSApp.terminate(nil)
                return nil
            default:
                return event
            }
        }
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
        if panel?.isShown == true { controller.reload() } else { updateCount() }
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
        controller.hideDoneMode = mode
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
            closePanel()
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
            return
        }
        if panel.isShown {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button else { return }
        store.checkForExternalChange()
        performSweep()
        if let visible = (button.window?.screen ?? NSScreen.main)?.visibleFrame {
            controller.heightLimit = min(TodoLayout.maxHeight, visible.height - panel.gap - panel.screenMargin)
        }
        controller.reload()
        panel.show(under: button)
        controller.focusInput()
    }

    private func closePanel() {
        panel.dismiss()
    }

    private func panelDidClose() {
        controller.closeDatePicker()
        controller.endInlineEditing()
        updateCount()
    }

    @objc private func closeFrontmost() {
        if let window = settings?.window, window.isKeyWindow {
            window.performClose(nil)
        } else {
            closePanel()
        }
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
        if panel.isShown {
            panel.makeKey()
            controller.focusInput()
        } else {
            showPanel()
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

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot") {
    guard CommandLine.arguments.count > flag + 1 else {
        log("usage: Todo --snapshot <directory>")
        exit(2)
    }
    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
    _ = NSApplication.shared
    DS.registerFonts()
    exit(SnapshotSamples.writeAll(to: directory) ? 0 : 1)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
