import AppKit

final class DemoSwatch: NSView {
    let color: NSColor

    init(_ color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.fill(bounds, radius: DS.radius, color)
    }
}

final class DemoRow: NSView {
    override var isFlipped: Bool { true }
}

final class DemoCard: NSView {
    let title: String
    let pad: CGFloat
    private var cursor: CGFloat
    private var lastGap: CGFloat = 0

    init(_ title: String, width: CGFloat = 300, pad: CGFloat = 16, top: CGFloat = 16) {
        self.title = title
        self.pad = pad
        self.cursor = top
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))
    }

    required init?(coder: NSCoder) { nil }

    override var isFlipped: Bool { true }

    var inner: CGFloat { bounds.width - 2 * pad }

    private func advance(_ height: CGFloat, _ gap: CGFloat) {
        cursor += height + gap
        lastGap = gap
    }

    private func size(of view: NSView) -> NSSize {
        let size = view.intrinsicContentSize
        return NSSize(width: size.width < 0 ? view.frame.width : size.width, height: size.height < 0 ? view.frame.height : size.height)
    }

    func stack(_ view: NSView, height: CGFloat? = nil, gap: CGFloat = 14) {
        let height = height ?? size(of: view).height
        view.frame = NSRect(x: pad, y: cursor, width: inner, height: height)
        addSubview(view)
        advance(height, gap)
    }

    func flow(_ views: [NSView], spacing: CGFloat = 10, height: CGFloat = 28, gap: CGFloat = 14) {
        var x = pad
        for view in views {
            let size = size(of: view)
            view.frame = NSRect(x: x, y: cursor + ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
            addSubview(view)
            x += size.width + spacing
        }
        advance(height, gap)
    }

    func split(_ views: [NSView], spacing: CGFloat = 10, height: CGFloat = 28, gap: CGFloat = 10) {
        let width = (inner - spacing * CGFloat(views.count - 1)) / CGFloat(views.count)
        for (index, view) in views.enumerated() {
            view.frame = NSRect(x: pad + CGFloat(index) * (width + spacing), y: cursor, width: width, height: height)
            addSubview(view)
        }
        advance(height, gap)
    }

    func line(_ name: String, _ control: NSView, nameWidth: CGFloat = 70, leading: NSView? = nil, gap: CGFloat = 14) {
        var x = pad
        if let leading {
            leading.frame = NSRect(x: x, y: cursor + 2, width: 16, height: 16)
            addSubview(leading)
            x += 16 + 10
        }
        let label = DSLabel(name)
        label.frame = NSRect(x: x, y: cursor, width: nameWidth, height: 20)
        addSubview(label)
        x += nameWidth + 10
        let height = size(of: control).height
        control.frame = NSRect(x: x, y: cursor + ((20 - height) / 2).rounded(), width: pad + inner - x, height: height)
        addSubview(control)
        advance(20, gap)
    }

    func between(_ left: NSView, _ right: [NSView], height: CGFloat = 20, gap: CGFloat = 14) {
        var x = pad + inner
        for view in right.reversed() {
            let size = size(of: view)
            x -= size.width
            view.frame = NSRect(x: x, y: cursor + ((height - size.height) / 2).rounded(), width: size.width, height: size.height)
            addSubview(view)
            x -= 10
        }
        let leftSize = size(of: left)
        left.frame = NSRect(x: pad, y: cursor + ((height - leftSize.height) / 2).rounded(), width: min(leftSize.width, x - pad), height: leftSize.height)
        addSubview(left)
        advance(height, gap)
    }

    func divider(above: CGFloat, below: CGFloat, inset: CGFloat = 0) {
        cursor += above - lastGap
        let rule = DSSeparator()
        rule.frame = NSRect(x: inset, y: cursor, width: bounds.width - 2 * inset, height: 1)
        addSubview(rule)
        cursor += 1 + below
        lastGap = 0
    }

    func finish(bottom: CGFloat = 16) {
        setFrameSize(NSSize(width: frame.width, height: cursor - lastGap + bottom))
    }
}

final class DemoGallery: NSView {
    private var cards: [DemoCard] = []

    override var isFlipped: Bool { true }

    func layout(columns: [[DemoCard]]) {
        var x: CGFloat = 48
        var tallest: CGFloat = 0
        for column in columns {
            var y: CGFloat = 64
            var widest: CGFloat = 0
            for card in column {
                card.setFrameOrigin(NSPoint(x: x, y: y))
                addSubview(card)
                cards.append(card)
                y += card.frame.height + 72
                widest = max(widest, card.frame.width)
            }
            tallest = max(tallest, y)
            x += widest + 56
        }
        setFrameSize(NSSize(width: x - 8, height: tallest))
    }

    override func draw(_ dirtyRect: NSRect) {
        DSDraw.fill(bounds, DSSnapshot.desk)
        for card in cards {
            DSSurface.draw(around: card.frame)
            DSText.draw(card.title, in: NSRect(x: card.frame.minX, y: card.frame.minY - 28, width: card.frame.width, height: 16), font: DS.font(12), color: DS.muted)
        }
    }
}

func demoSliders() -> DemoCard {
    let card = DemoCard("Slider")
    card.line("Value", DSSlider(value: 0.62, label: "Value"))
    let meter = DSSlider(value: 0.74, mode: .meter, label: "Volume")
    meter.setLiveLevel(0.6)
    card.line("With level", meter)
    let capped = DSSlider(value: 0.7, mode: .output, label: "Night mode cap")
    capped.isCapped = true
    capped.setLiveLevel(0.6)
    card.line("Capped", capped)
    let output = DSSlider(value: 0.7, mode: .output, label: "Output level")
    output.setLiveLevel(0.45)
    card.line("Output", output)
    let hovered = DSSlider(value: 0.4)
    hovered.previewState = [.hovered]
    card.line("Hover", hovered)
    let focused = DSSlider(value: 0.3)
    focused.previewState = [.focused]
    card.line("Focus", focused)
    let disabled = DSSlider(value: 0.5)
    disabled.isEnabled = false
    card.line("Disabled", disabled)
    card.finish()
    return card
}

func demoToggles() -> DemoCard {
    let card = DemoCard("Toggle")
    card.between(DSLabel("Night mode"), [DSToggle(isOn: true, label: "Night mode")])
    card.between(DSLabel("Sleep Mac when timer ends"), [DSToggle(isOn: false, label: "Sleep Mac when timer ends")])
    let disabled = DSToggle(isOn: true)
    disabled.isEnabled = false
    card.between(DSLabel("Disabled"), [disabled])
    let focused = DSToggle(isOn: false)
    focused.previewState = [.focused]
    card.between(DSLabel("Focus"), [focused])
    card.finish()
    return card
}

func demoButtons() -> DemoCard {
    let card = DemoCard("Buttons", width: 340)
    func trio(_ state: DSControlState) -> [NSView] {
        let buttons = [DSButton("Optimize", style: .primary), DSButton("Add files\u{2026}"), DSButton("Show in Finder", style: .quiet)]
        buttons.forEach { $0.previewState = state }
        return buttons
    }
    card.flow(trio([]), spacing: 6, gap: 10)
    card.flow(trio([.hovered]), spacing: 6, gap: 10)
    card.flow(trio([.pressed]), spacing: 6, gap: 10)
    let disabled = [DSButton("Optimize", style: .primary), DSButton("Add files\u{2026}"), DSButton("Show in Finder", style: .quiet)]
    disabled.forEach { $0.isEnabled = false }
    card.flow(disabled, spacing: 6)
    card.stack(DSButton("Optimize 4 files", style: .primary, fullWidth: true), height: 28)
    let focused = DSButton("Cancel", fullWidth: true)
    focused.previewState = [.focused]
    card.stack(focused, height: 28)
    card.finish()
    return card
}

func demoTimer() -> DemoCard {
    let card = DemoCard("Timer")
    card.split([DSStepper(value: 1, range: 0...12, unit: "h", label: "Hours"), DSStepper(value: 30, range: 0...55, step: 5, unit: "min", label: "Minutes")])
    card.stack(DSButton("Keep awake", style: .primary, fullWidth: true), height: 28, gap: 20)
    let hovered = DSStepper(value: 0, range: 0...12, unit: "h")
    hovered.previewState = [.hovered]
    let disabled = DSStepper(value: 25, range: 0...55, step: 5, unit: "min")
    disabled.isEnabled = false
    card.split([hovered, disabled], gap: 20)
    let count = DSLabel("24:10", weight: .semibold, color: DS.ink)
    card.between(DSLabel("Sleeping in", color: DS.muted), [count], gap: 10)
    card.stack(DSButton("Cancel", fullWidth: true), height: 28)
    card.finish()
    return card
}

func demoChecks() -> DemoCard {
    let card = DemoCard("Checkbox and tags")
    let focused = DSCheckbox(label: "Focus")
    focused.previewState = [.focused]
    let disabled = DSCheckbox("Disabled", isOn: true)
    disabled.isEnabled = false
    card.flow([DSCheckbox(label: "Not done"), DSCheckbox(isOn: true, label: "Done"), focused, DSCheckbox("Group by project", isOn: true)], spacing: 14, height: 16)
    card.flow([disabled], height: 16)
    card.flow([
        DSTag("2 days ago", style: .red, small: true), DSTag("Today", style: .blue, small: true),
        DSTag("Tomorrow", style: .amber, small: true), DSTag("3 days", style: .amber, small: true), DSTag("12 days", small: true),
    ], spacing: 6, height: 16)
    card.flow([DSTag("12 days"), DSTag("2 days ago", style: .red), DSTag("Today", style: .blue), DSTag("Tomorrow", style: .amber)], spacing: 6, height: 18)
    let image = DSTag("JPG", icon: .image, minWidth: 52)
    image.isMuted = true
    let document = DSTag("PDF", icon: .description, minWidth: 52)
    document.isMuted = true
    card.flow([image, document, DSTag("Done today", style: .plain, small: true)], spacing: 6, height: 18)
    card.finish()
    return card
}

func demoChips() -> DemoCard {
    let card = DemoCard("Copy chip")
    let copied = DSChip("#B53A9A")
    copied.isCopied = true
    card.flow([copied, DSChip("181"), DSChip("58"), DSChip("154")], spacing: 6, height: 24)
    let hovered = DSChip("313")
    hovered.previewState = [.hovered]
    let pressed = DSChip("51%")
    pressed.previewState = [.pressed]
    let focused = DSChip("47%")
    focused.previewState = [.focused]
    card.flow([hovered, pressed, focused], spacing: 6, height: 24)
    let solidHover = DSChip("Number \u{2191}", style: .solid)
    solidHover.previewState = [.hovered]
    card.flow([DSChip("Default", style: .solid), DSChip("Current name", style: .solid), solidHover], spacing: 6, height: 24)
    card.finish()
    return card
}

func demoFields() -> DemoCard {
    let card = DemoCard("Fields and options")
    card.stack(DSTextField(placeholder: "Add a task\u{2026}"), height: 28)
    let editing = DSTextField(text: "Studio; Order new fabric samples @2026-11-11")
    editing.showsFocusStyle = true
    card.stack(editing, height: 28)
    let sized = DSTextField(text: "1920")
    sized.unit = "px"
    sized.setFrameSize(NSSize(width: 120, height: 28))
    let disabled = DSTextField(text: "Disabled")
    disabled.isEnabled = false
    disabled.setFrameSize(NSSize(width: 138, height: 28))
    card.flow([sized, disabled])
    card.stack(DSSegmented(["WebP", "AVIF", "JPEG", "PNG"], selectedIndex: 0, label: "Format"), height: 28)
    let sort = DSSegmented(["Added", "Deadline", "A\u{2013}Z"], selectedIndex: 1, label: "Sort by")
    sort.equalWidths = false
    sort.isCompact = true
    card.flow([DSLabel("Sort by", color: DS.muted), sort], height: 24)
    card.stack(DSRadioGroup(["Next to originals", "Replace originals", "Choose folder\u{2026}"], selectedIndex: 0, label: "Destination"))
    card.finish()
    return card
}

func demoProgress() -> DemoCard {
    let card = DemoCard("Progress", width: 340)
    let files: [(DSIcon, String, String, String, String, Bool)] = [
        (.image, "JPG", "hero-homepage", "4.8 MB \u{2192} 412 KB", "\u{2212}91 %", false),
        (.description, "PDF", "pricing-deck", "12 pages, 3.9 MB \u{2192} 1.1 MB", "\u{2212}72 %", false),
        (.image, "PNG", "logo-sheet", "620 KB", "Optimizing\u{2026}", true),
    ]
    card.divider(above: 0, below: 11, inset: 16)
    for (index, file) in files.enumerated() {
        let row = DemoRow(frame: NSRect(x: 0, y: 0, width: card.inner, height: 33))
        let tag = DSTag(file.1, icon: file.0, minWidth: 52)
        tag.isMuted = true
        tag.frame = NSRect(x: 0, y: -1, width: 52, height: 18)
        let name = DSLabel(file.2)
        name.frame = NSRect(x: 62, y: 0, width: 190, height: 16)
        let detail = DSLabel(file.3, size: 11, color: DS.muted)
        detail.frame = NSRect(x: 62, y: 19, width: 190, height: 14)
        let saved = DSLabel(file.4, color: file.5 ? DS.muted : DS.text)
        saved.alignment = .right
        saved.frame = NSRect(x: card.inner - 90, y: 8, width: 90, height: 16)
        for view in [tag, name, detail, saved] { row.addSubview(view) }
        card.stack(row, height: 33, gap: 0)
        if index < files.count - 1 { card.divider(above: 11, below: 11, inset: 16) }
    }
    card.divider(above: 11, below: 18, inset: 16)
    let cancel = DSButton("Cancel")
    let bar = DSProgressBar(progress: 0.68)
    let count = DSLabel("2 of 3", color: DS.muted)
    let row = DemoRow(frame: NSRect(x: 0, y: 0, width: card.inner, height: 28))
    let cancelWidth = cancel.fittingWidth
    let countWidth = count.intrinsicContentSize.width
    cancel.frame = NSRect(x: card.inner - cancelWidth, y: 0, width: cancelWidth, height: 28)
    count.frame = NSRect(x: card.inner - cancelWidth - 10 - countWidth, y: 6, width: countWidth, height: 16)
    bar.frame = NSRect(x: 0, y: 12, width: count.frame.minX - 10, height: 4)
    for view in [bar, count, cancel] { row.addSubview(view) }
    card.stack(row, height: 28)
    card.finish()
    return card
}

func demoSmallParts() -> DemoCard {
    let card = DemoCard("Icons and small parts", width: 340)
    let icons = DSIcon.allCases
    card.flow(icons.prefix(7).map { DSIconButton($0, label: $0.accessibilityName) }, spacing: 8, height: 24, gap: 8)
    card.flow(icons.suffix(from: 7).map { DSIconButton($0, label: $0.accessibilityName) }, spacing: 8, height: 24)
    let hovered = DSIconButton(.calendarToday, label: "Pick a date")
    hovered.previewState = [.hovered]
    let on = DSIconButton(.sort, label: "Sort and group")
    on.isOn = true
    let focused = DSIconButton(.edit, label: "Edit")
    focused.previewState = [.focused]
    let disabled = DSIconButton(.delete, label: "Delete")
    disabled.isEnabled = false
    let tinted = NSImageView(image: DSIcon.coffee.image(size: 18, color: DS.pink))
    tinted.frame.size = NSSize(width: 18, height: 18)
    let template = NSImageView(image: DSIcon.timer.image(size: 18))
    template.contentTintColor = DS.blueText
    template.frame.size = NSSize(width: 18, height: 18)
    card.flow([hovered, on, focused, disabled, tinted, template], spacing: 8, height: 24)
    card.stack(DSSectionHeader(icon: .contrast, title: "Brightness", value: "62 %"))
    card.stack(DSSeparator())
    card.stack(DSSectionHeader(icon: .timer, title: "Sleep timer"))
    let link = DSLinkButton("Supported formats")
    let linkHover = DSLinkButton("Hide formats")
    linkHover.previewState = [.hovered]
    card.flow([link, linkHover], spacing: 14, height: 16)
    card.stack(DSLabel("Squeeze settings", size: 16, weight: .medium), height: 20, gap: 8)
    card.stack(DSLabel("Nothing gets louder than the cap"), height: 16, gap: 8)
    card.stack(DSLabel("1:29:58", weight: .semibold, color: DS.ink), height: 16, gap: 8)
    card.stack(DSLabel("Sleep timer", size: 11, color: DS.muted), height: 14, gap: 12)
    let wrapped = DSLabel("Rewrite the pricing page copy so it explains all three packages without any jargon")
    wrapped.maxLines = 0
    wrapped.lineHeight = 20
    card.stack(wrapped, height: wrapped.height(forWidth: card.inner), gap: 8)
    let done = DSLabel("Renew the domain", color: DS.muted)
    done.isStruck = true
    card.stack(done, height: 20)
    card.finish()
    return card
}

func demoHub() -> DemoCard {
    let card = DemoCard("Hub panel sample", width: 300, pad: 16, top: 16)
    card.stack(DSSectionHeader(icon: .contrast, title: "Brightness", value: "62 %"), gap: 10)
    card.stack(DSSlider(value: 0.62, label: "Brightness"))
    card.divider(above: 14, below: 12)
    card.stack(DSSectionHeader(icon: .coffee, title: "Stay awake"), gap: 10)
    card.split([DSStepper(value: 1, range: 0...12, unit: "h"), DSStepper(value: 30, range: 0...55, step: 5, unit: "min")])
    card.stack(DSButton("Keep awake", style: .primary, fullWidth: true), height: 28)
    card.divider(above: 14, below: 12)
    card.stack(DSSectionHeader(icon: .volumeUp, title: "Audio"), gap: 10)
    let output = DSSlider(value: 0.7, mode: .output, label: "Night mode cap")
    output.isCapped = true
    output.setLiveLevel(0.55)
    card.line("MacBook Speakers", output, nameWidth: 126, gap: 10)
    let apps: [(String, UInt32, Double, CGFloat)] = [("Spotify", 0x1DB954, 0.8, 0.7), ("Chrome", 0xE8453C, 0.45, 0.5), ("Figma", 0xA259FF, 0.6, 0)]
    for app in apps {
        let slider = DSSlider(value: app.2, mode: .meter, label: "\(app.0) volume")
        slider.setLiveLevel(app.3)
        card.line(app.0, slider, nameWidth: 100, leading: DemoSwatch(DS.rgb(app.1)), gap: 10)
    }
    card.between(DSLabel("Night mode"), [DSLabel("\u{2212}12 dB", color: DS.icon), DSToggle(isOn: true, label: "Night mode")])
    card.divider(above: 14, below: 12)
    card.stack(DSSectionHeader(icon: .timer, title: "Sleep timer"), gap: 10)
    card.between(DSLabel("Sleeping in", color: DS.muted), [DSLabel("24:10", weight: .semibold, color: DS.ink)], gap: 10)
    card.stack(DSButton("Cancel", fullWidth: true), height: 28)
    card.finish(bottom: 18)
    return card
}

func demoGallery() -> DemoGallery {
    let gallery = DemoGallery(frame: .zero)
    gallery.layout(columns: [
        [demoSliders(), demoToggles(), demoButtons()],
        [demoTimer(), demoChecks(), demoChips(), demoFields()],
        [demoProgress(), demoSmallParts()],
        [demoHub()],
    ])
    return gallery
}

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: ds-demo <output-directory>\n".utf8))
    exit(64)
}

let demoOutput = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
NSApplication.shared.setActivationPolicy(.prohibited)
if !DS.registerFonts() {
    let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    DS.registerFonts(at: source.appendingPathComponent("Fonts/GoogleSansFlex.ttf"))
}
if !DS.usesBundledFont {
    FileHandle.standardError.write(Data("warning: Google Sans Flex not found, using the system font\n".utf8))
}

for dark in [false, true] {
    let target = demoOutput.appendingPathComponent(dark ? "gallery-dark.png" : "gallery-light.png")
    if DSSnapshot.write(view: demoGallery(), to: target, dark: dark, background: nil) {
        print(target.path)
    } else {
        FileHandle.standardError.write(Data("failed to write \(target.path)\n".utf8))
        exit(1)
    }
}
