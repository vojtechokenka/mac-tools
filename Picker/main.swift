import AppKit
import Carbon.HIToolbox

func log(_ message: String) {
    FileHandle.standardError.write(Data(("[Picker] " + message + "\n").utf8))
}

enum CopyFormat: String, CaseIterable {
    case hex, rgb, hsl

    var title: String { rawValue.uppercased() }

    static var preferred: CopyFormat {
        get { CopyFormat(rawValue: UserDefaults.standard.string(forKey: "copyFormat") ?? "") ?? .hex }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "copyFormat") }
    }
}

struct PickedColor: Equatable {
    let r: Int
    let g: Int
    let b: Int

    init(r: Int, g: Int, b: Int) {
        self.r = min(max(r, 0), 255)
        self.g = min(max(g, 0), 255)
        self.b = min(max(b, 0), 255)
    }

    init?(_ color: NSColor) {
        guard let srgb = color.usingColorSpace(.sRGB) else { return nil }
        self.init(r: Int((srgb.redComponent * 255).rounded()), g: Int((srgb.greenComponent * 255).rounded()), b: Int((srgb.blueComponent * 255).rounded()))
    }

    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = Int(text, radix: 16) else { return nil }
        self.init(r: value >> 16 & 0xFF, g: value >> 8 & 0xFF, b: value & 0xFF)
    }

    var hex: String { String(format: "#%02X%02X%02X", r, g, b) }

    var nsColor: NSColor { NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1) }

    var hsl: (h: Int, s: Int, l: Int) {
        let rf = Double(r) / 255, gf = Double(g) / 255, bf = Double(b) / 255
        let mx = max(rf, gf, bf), mn = min(rf, gf, bf)
        let l = (mx + mn) / 2
        let d = mx - mn
        var h = 0.0, s = 0.0
        if d > 0 {
            s = min(d / (1 - abs(2 * l - 1)), 1)
            if mx == rf {
                h = ((gf - bf) / d).truncatingRemainder(dividingBy: 6)
            } else if mx == gf {
                h = (bf - rf) / d + 2
            } else {
                h = (rf - gf) / d + 4
            }
            h *= 60
            if h < 0 { h += 360 }
        }
        var hue = Int(h.rounded())
        if hue == 360 { hue = 0 }
        return (hue, Int((s * 100).rounded()), Int((l * 100).rounded()))
    }

    func value(_ format: CopyFormat) -> String {
        switch format {
        case .hex: return hex
        case .rgb: return "rgb(\(r), \(g), \(b))"
        case .hsl: let c = hsl; return "hsl(\(c.h), \(c.s)%, \(c.l)%)"
        }
    }

    func display(_ format: CopyFormat) -> String {
        switch format {
        case .hex: return hex
        case .rgb: return "\(r), \(g), \(b)"
        case .hsl: let c = hsl; return "\(c.h)°, \(c.s) %, \(c.l) %"
        }
    }
}

final class SwatchView: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.fill(bounds, color)
        DSDraw.fill(NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height), DS.alpha(DS.ink, 0.12))
    }
}

final class FormatLabel: DSControl {
    static let width: CGFloat = 30

    let title: String
    var onClick: (() -> Void)?

    init(title: String) {
        self.title = title
        super.init()
        toolTip = "Copy full value"
        setAccessibilityLabel("Copy \(title)")
    }

    required init?(coder: NSCoder) { nil }

    override var isFocusable: Bool { false }

    override var intrinsicContentSize: NSSize { NSSize(width: Self.width, height: DSChip.height) }

    override func activate() { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        DSText.draw(title, in: bounds, font: DS.smallFont, color: isHovered ? DS.text : DS.muted, alignment: .left)
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }
}

final class HUDContentView: NSView {
    static let size = NSSize(width: 360, height: 132)
    static let swatchWidth: CGFloat = 132
    static let gap: CGFloat = 20
    static let rowGap: CGFloat = 8
    static let chipGap: CGFloat = 6
    static let closeInset: CGFloat = 8

    var onCopyText: ((String) -> Void)?
    var onClose: (() -> Void)?
    private(set) var color: PickedColor?
    private let swatch = SwatchView()
    private let closeButton = DSIconButton(.close, label: "Close")
    private var labels: [CopyFormat: FormatLabel] = [:]
    private var chips: [CopyFormat: [DSChip]] = [:]

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        swatch.frame = NSRect(x: 0, y: 0, width: Self.swatchWidth, height: Self.size.height)
        addSubview(swatch)

        closeButton.frame = NSRect(x: Self.size.width - Self.closeInset - DS.iconButtonSize, y: Self.closeInset, width: DS.iconButtonSize, height: DS.iconButtonSize)
        closeButton.onClick = { [weak self] in self?.onClose?() }
        addSubview(closeButton)

        for format in CopyFormat.allCases {
            let label = FormatLabel(title: format.title)
            label.onClick = { [weak self] in
                guard let self, let color = self.color else { return }
                self.onCopyText?(color.value(format))
                self.markCopied(format)
            }
            addSubview(label)
            labels[format] = label
            var row: [DSChip] = []
            for _ in 0..<(format == .hex ? 1 : 3) {
                let chip = DSChip("")
                chip.onClick = { [weak self, weak chip] in
                    guard let self, let chip else { return }
                    self.onCopyText?(chip.title)
                    self.markCopied(format, only: chip)
                }
                addSubview(chip)
                row.append(chip)
            }
            chips[format] = row
        }
    }

    required init?(coder: NSCoder) { nil }

    func configure(_ picked: PickedColor, copied: CopyFormat? = nil, only index: Int? = nil) {
        color = picked
        swatch.color = picked.nsColor
        let hsl = picked.hsl
        let values: [CopyFormat: [String]] = [
            .hex: [picked.hex],
            .rgb: ["\(picked.r)", "\(picked.g)", "\(picked.b)"],
            .hsl: ["\(hsl.h)", "\(hsl.s)%", "\(hsl.l)%"],
        ]
        for format in CopyFormat.allCases {
            for (chip, value) in zip(chips[format] ?? [], values[format] ?? []) {
                chip.title = value
                chip.toolTip = "Copy \(value)"
            }
        }
        layoutRows()
        if let copied {
            let row = chips[copied] ?? []
            markCopied(copied, only: index.flatMap { row.indices.contains($0) ? row[$0] : nil })
        }
    }

    private func markCopied(_ format: CopyFormat, only chip: DSChip? = nil) {
        for (key, row) in chips {
            for item in row { item.isCopied = chip == nil ? key == format : item === chip }
        }
    }

    private func layoutRows() {
        let rows = CGFloat(CopyFormat.allCases.count)
        let height = DSChip.height
        let total = rows * height + (rows - 1) * Self.rowGap
        let left = Self.swatchWidth + Self.gap
        var y = ((Self.size.height - total) / 2).rounded()
        for format in CopyFormat.allCases {
            labels[format]?.frame = NSRect(x: left, y: y, width: FormatLabel.width, height: height)
            var x = left + FormatLabel.width + Self.chipGap
            for chip in chips[format] ?? [] {
                chip.sizeToFit()
                chip.frame = NSRect(x: x, y: y, width: chip.frame.width, height: height)
                x += chip.frame.width + Self.chipGap
            }
            y += height + Self.rowGap
        }
    }

    static func sample(copied: CopyFormat = .hex, only index: Int? = nil) -> HUDContentView {
        let view = HUDContentView()
        view.configure(PickedColor(r: 0xB5, g: 0x3A, b: 0x9A), copied: copied, only: index)
        return view
    }
}

final class HUDController {
    var onCopyText: ((String) -> Void)?
    var onHide: (() -> Void)?
    private let content = HUDContentView()
    private let panel: DSPanel

    var color: PickedColor? { content.color }

    init() {
        panel = DSPanel(width: HUDContentView.size.width, content: content)
        panel.takesKeyFocus = false
        panel.closesOnOutsideClick = false
        panel.closesOnEscape = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.setContentHeight(HUDContentView.size.height)
        panel.onClose = { [weak self] in self?.onHide?() }
        content.onClose = { [weak self] in self?.hide() }
        content.onCopyText = { [weak self] text in self?.onCopyText?(text) }
    }

    func show(_ picked: PickedColor, copied: CopyFormat) {
        content.configure(picked, copied: copied)
        if panel.isShown {
            panel.orderFrontRegardless()
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        panel.show(at: NSPoint(x: mouse.x + 14, y: mouse.y - 14), screen: screen)
    }

    func hide() {
        panel.dismiss()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private lazy var hud = HUDController()
    private var sampler: NSColorSampler?
    private var hotKey: EventHotKeyRef?
    private var escHotKey: EventHotKeyRef?
    private let signature = OSType(0x5049434B)
    private let historyKey = "history"
    private let historyLimit = 12

    private var history: [PickedColor] {
        get { (UserDefaults.standard.stringArray(forKey: historyKey) ?? []).compactMap { PickedColor(hex: $0) } }
        set { UserDefaults.standard.set(newValue.prefix(historyLimit).map(\.hex), forKey: historyKey) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DS.registerFonts()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarIcon()
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        hud.onCopyText = { [weak self] text in self?.copyText(text) }
        registerHotKey()
        log("started")
    }

    private static let iconSVG = "<svg width=\"20\" height=\"20\" viewBox=\"2 2 20 20\" fill=\"none\" xmlns=\"http://www.w3.org/2000/svg\"><rect width=\"20\" height=\"20\" transform=\"translate(2 2)\" fill=\"white\" fill-opacity=\"0.25\"/><path d=\"M17.4303 6.57157C17.6102 6.75148 17.7542 6.96538 17.8501 7.20126H17.8521C17.9501 7.43714 17.999 7.69002 17.999 7.94489C18.0074 8.21365 17.961 8.4813 17.8625 8.73151C17.7641 8.98172 17.6156 9.20924 17.4263 9.40018L16.7267 10.0998L16.9765 10.3597C17.1872 10.5725 17.3054 10.8599 17.3054 11.1593C17.3054 11.4588 17.1872 11.7461 16.9765 11.9589L16.3938 12.5416C16.181 12.7523 15.8937 12.8705 15.5942 12.8705C15.2948 12.8705 15.0074 12.7523 14.7946 12.5416L14.5397 12.2868L14.5377 12.2848L9.60516 17.2173C9.55867 17.2637 9.50349 17.3005 9.44277 17.3255C9.38206 17.3505 9.31701 17.3634 9.25134 17.3633H8.7196L7.43423 17.915C7.24564 17.9973 7.03663 18.0209 6.83443 17.9827C6.63223 17.9445 6.44621 17.8464 6.30061 17.701C6.155 17.5556 6.05654 17.3697 6.01807 17.1676C5.97959 16.9654 6.00288 16.7564 6.0849 16.5676L6.63763 15.2813V14.7495C6.63765 14.6173 6.69013 14.4904 6.78355 14.3967L11.7161 9.45415L11.4622 9.20028C11.2513 8.98761 11.1329 8.70021 11.1329 8.40067C11.1329 8.10113 11.2513 7.81373 11.4622 7.60106L12.052 7.01635C12.2108 6.85902 12.4125 6.75191 12.6318 6.70837C12.8511 6.66482 13.0784 6.68677 13.2854 6.77147C13.4233 6.82944 13.5456 6.91107 13.6522 7.01635L13.908 7.27023L14.6077 6.57057C14.9725 6.20642 15.4666 6.00157 15.982 6.00085C16.2494 5.99301 16.5156 6.03945 16.7645 6.13737C17.0134 6.23529 17.2399 6.38366 17.4303 6.57157ZM12.4248 10.1648L7.64213 14.9504V15.3782C7.64268 15.4469 7.62907 15.515 7.60215 15.5781L7.00245 16.9575L8.41675 16.4007C8.47993 16.3738 8.54798 16.3602 8.61665 16.3608H9.04444L13.8301 11.5741L12.4248 10.1648Z\" fill=\"white\"/></svg>"

    private static func menuBarIcon() -> NSImage {
        let image = NSImage(data: Data(iconSVG.utf8)) ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        image.accessibilityDescription = "Picker"
        return image
    }

    private static func swatchImage(_ color: PickedColor) -> NSImage {
        NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            color.nsColor.setFill()
            path.fill()
            NSColor.labelColor.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }

    @objc private func statusItemClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else {
            startSampling()
            return
        }
        statusItem.menu = buildMenu()
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let colors = history
        if colors.isEmpty {
            let empty = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for color in colors {
            let item = NSMenuItem(title: color.hex, action: #selector(historyClicked(_:)), keyEquivalent: "")
            item.target = self
            item.image = Self.swatchImage(color)
            item.representedObject = color.hex
            menu.addItem(item)
        }
        let clear = NSMenuItem(title: "Clear history", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !colors.isEmpty
        menu.addItem(clear)
        menu.addItem(.separator())

        let formatItem = NSMenuItem(title: "Copy as", action: nil, keyEquivalent: "")
        let formatMenu = NSMenu()
        formatMenu.autoenablesItems = false
        for format in CopyFormat.allCases {
            let item = NSMenuItem(title: format.title, action: #selector(formatSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = format.rawValue
            item.state = format == CopyFormat.preferred ? .on : .off
            formatMenu.addItem(item)
        }
        formatItem.submenu = formatMenu
        menu.addItem(formatItem)
        menu.addItem(.separator())
        menu.addItem(DSBrand.menuItem())
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc private func historyClicked(_ sender: NSMenuItem) {
        guard let hex = sender.representedObject as? String, let color = PickedColor(hex: hex) else { return }
        present(color)
    }

    @objc private func clearHistory() {
        history = []
        log("history cleared")
    }

    @objc private func formatSelected(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let format = CopyFormat(rawValue: raw) else { return }
        CopyFormat.preferred = format
    }

    private func startSampling() {
        guard sampler == nil else { return }
        hud.hide()
        let sampler = NSColorSampler()
        self.sampler = sampler
        sampler.show { [weak self] color in
            DispatchQueue.main.async {
                guard let self else { return }
                self.sampler = nil
                guard let color else { return }
                guard let picked = PickedColor(color) else {
                    log("failed to convert color to sRGB")
                    return
                }
                self.remember(picked)
                self.present(picked)
                log("picked \(picked.hex)")
            }
        }
    }

    private func remember(_ color: PickedColor) {
        var colors = history.filter { $0 != color }
        colors.insert(color, at: 0)
        history = colors
    }

    private func present(_ color: PickedColor) {
        let format = CopyFormat.preferred
        copy(color, format: format)
        hud.show(color, copied: format)
    }

    private func copy(_ color: PickedColor, format: CopyFormat) {
        copyText(color.value(format))
    }

    private func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    fileprivate func handleHotKey(id: UInt32) {
        switch id {
        case 1: startSampling()
        default: break
        }
    }

    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            delegate.handleHotKey(id: hotKeyID.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(controlKey | optionKey), EventHotKeyID(signature: signature, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { log("failed to register the ⌃⌥C shortcut (\(status))") }
    }

}

if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
    _ = NSApplication.shared
    DS.registerFonts()
    for dark in [false, true] {
        let file = directory.appendingPathComponent(dark ? "picker-dark.png" : "picker-light.png")
        if !DSSnapshot.write(view: HUDContentView.sample(), to: file, dark: dark, panel: true) { exit(1) }
    }
    let rgb = directory.appendingPathComponent("picker-rgb-copied-light.png")
    if !DSSnapshot.write(view: HUDContentView.sample(copied: .rgb, only: 1), to: rgb, dark: false, panel: true) { exit(1) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
