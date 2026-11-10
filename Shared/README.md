# Shared design kit

One look for Hub, Todo, Picker and Squeeze. Plain Swift/AppKit, no packages. Every public name starts with `DS`. The visual spec is the HTML mock (`iOS Appky/Design System/index.html` in the Claude Workspace); sizes here are the mock's CSS pixels as points.

Contents of this folder:

| File | What is in it |
|---|---|
| `Theme.swift` | `DS`: colors, metrics, fonts |
| `Icons.swift` | `DSIcon`: Material Symbols (filled) as vector paths |
| `DSText.swift` | `DSText`: text measuring and drawing used by every component |
| `DSBase.swift` | `DSView`, `DSControl`, `DSControlState`, `DSDraw`, `DSTween` |
| `DSSlider.swift` | `DSSlider` |
| `DSControls.swift` | `DSToggle`, `DSButton`, `DSIconButton`, `DSStepper`, `DSSegmented`, `DSCheckbox`, `DSRadioGroup`, `DSChip`, `DSLinkButton` |
| `DSDisplay.swift` | `DSLabel`, `DSTag`, `DSProgressBar`, `DSSeparator`, `DSSectionHeader` |
| `DSTextField.swift` | `DSTextField` |
| `DSPanel.swift` | `DSPanel`, `DSSurface` |
| `Snapshot.swift` | `DSSnapshot` |
| `DSBrand.swift` | `DSBrand`: logo and the "by Vojtěch Okénka" menu row |
| `DSBubble.swift` | `DSBubble`: small inverted note for "Copied" and hover hints |
| `Fonts/` | `GoogleSansFlex.ttf` (original variable font) and its `OFL.txt` |
| `Demo/main.swift`, `build-demo.sh` | gallery CLI, not compiled into the apps |
| `NOTICE.md` | font and icon credits |

## 1. Wiring the kit into an app

Changes to an app's `build.sh` (shown for Todo; the other three are the same idea):

```zsh
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SOURCES=(main.swift Model.swift ../Shared/*.swift)
FRAMEWORKS=(-framework AppKit -framework Carbon)
```

and, anywhere before the `codesign` line:

```zsh
cp ../Shared/Fonts/GoogleSansFlex.ttf "$APP/Contents/Resources/GoogleSansFlex.ttf"
cp ../Shared/Fonts/OFL.txt "$APP/Contents/Resources/GoogleSansFlex-OFL.txt"
```

- `../Shared/*.swift` does not descend into `Demo/`, so the demo's `main.swift` stays out. Do not add `../Shared/Demo/main.swift`.
- No extra frameworks are needed. AppKit is enough (CoreText is linked automatically).
- `swiftc` refuses two source files with the same base name. The kit uses `Theme.swift`, `Icons.swift`, `Snapshot.swift` and `DS*.swift`; do not create app files with those names.
- The kit declares no top-level code and nothing without the `DS` prefix, so it cannot collide with app types such as `PillButton`, `Section`, `Format` or the global `log`.
- Call `DS.registerFonts()` first thing in `applicationDidFinishLaunching` (and in the `--snapshot` path, see section 8). If the font file is missing the kit falls back to the system font and keeps working.
- Everything in the kit is main-thread only.

## 2. Theme: `DS`

### Colors

All colors are dynamic `NSColor`s. They follow the effective appearance of the view they are drawn in, so nothing needs to be re-set when the system switches between light and dark.

| Token | Light | Dark | Use |
|---|---|---|---|
| `DS.paper` | `#FFFFFF` | `#000000` | panel and window background |
| `DS.sunken` | `#F3F3F3` | `#161616` | row under the pointer |
| `DS.chip` | `#E6E6E6` | `#262626` | chips, slider track, separators |
| `DS.line` | `#D6D6D6` | `#363636` | control outlines |
| `DS.muted` | `#666666` | `#9A9A9A` | labels, secondary text |
| `DS.ink` | `#000000` | `#FFFFFF` | emphasis only (countdown) |
| `DS.text` | ink 84 % | ink 84 % | body text |
| `DS.icon` | ink 40 % | ink 40 % | icons, placeholder text |
| `DS.edge` | ink 30 % | ink 30 % | checkbox, radio and dashed outlines |
| `DS.blue` | `#146EF5` | `#146EF5` | primary action, selection, slider, today |
| `DS.blueText` | `#146EF5` | `#5C9DFF` | blue used as text on paper |
| `DS.pink` | `#B53A9A` | `#D457BB` | night mode cap only |
| `DS.red` | `#D3261A` | `#FF6A5C` | overdue, error |
| `DS.onRed` | `#FFFFFF` | `#000000` | text on red |
| `DS.amber` | `#F2A94A` | `#F2A94A` | due tomorrow / within 3 days |
| `DS.amberText` | `#A35A00` | `#F2A94A` | amber used as text on paper |

Derived tokens used by the components: `DS.onBlue` (white), `DS.onAmber` (black), `DS.blueHover` (primary button hover), `DS.bluePressed`, `DS.blueGhost` (blue 18 %, meter fill), `DS.blueWash` (blue 8 %, drop target), `DS.pinkGhost` (pink 22 %), `DS.floatBorder` and `DS.floatShadow` (panel ring and shadow).

Helpers:

```swift
DS.rgb(0x1DB954)                         // fixed sRGB color
DS.dynamic(light: 0xECECEC, dark: 0x1E1E1E)
DS.alpha(DS.muted, 0.5)                  // stays dynamic
DS.isDark(view.effectiveAppearance)
DS.resolved(DS.paper, for: appearance)   // concrete color, e.g. for a CGColor
```

`NSColor.cgColor` on a dynamic color resolves once, with the appearance that is current at that moment. Prefer drawing in `draw(_:)`. For layer colors set them in `updateLayer()` or use `DS.resolved`.

### Metrics

| Constant | Value | Meaning |
|---|---|---|
| `DS.controlHeight` | 28 | buttons, steppers, segmented controls, text fields |
| `DS.radius` | 4 | corner radius of controls |
| `DS.panelRadius` | 12 | corner radius of panels |
| `DS.margin` | 16 | panel side margin |
| `DS.gap` | 10 | gap between rows and between items in a row |
| `DS.gapTight` | 6 | icon to label, label to chip |
| `DS.gapLoose` | 14 | gap between blocks |
| `DS.rowHeight` | 20 | height of a label + control row |
| `DS.sectionTop` / `DS.sectionBottom` | 12 / 14 | padding inside a Hub section |
| `DS.panelInset` | 4 | top and bottom padding of the Hub panel |
| `DS.iconSize` / `DS.iconButtonSize` | 18 / 24 | glyph and hit box of an icon button |
| `DS.disabledOpacity` | 0.4 | every disabled control |

### Fonts

```swift
DS.registerFonts()                        // Bundle.main Resources/GoogleSansFlex.ttf, process scope
DS.registerFonts(at: url)                 // explicit file, used by the demo
DS.font(13)                               // Google Sans Flex, weight 400, tabular digits
DS.font(13, .semibold)                    // weight 600 through the wght axis
DS.font(11, .regular, tabular: false)     // proportional digits
DS.bodyFont   // 13 / 400      DS.smallFont  // 11 / 400
DS.titleFont  // 16 / 500      DS.countFont  // 13 / 600
DS.usesBundledFont                        // false when the fallback is active
```

`DS.font(_ size: CGFloat, _ weight: NSFont.Weight = .regular, tabular: Bool = true) -> NSFont`. The variation axes are set to `wght` = weight (100 to 900), `opsz` = point size, `wdth` 100, `ROND` 0, `slnt` 0, which is what the browser does for the mock. Tabular digits are on by default because the mock uses them everywhere. Fonts are cached, so calling this in `draw(_:)` is cheap.

Type scale of the mock: title 16/20 weight 500, text 13/16 weight 400, countdown 13/16 weight 600 in `DS.ink`, caption 11/14 in `DS.muted`.

## 3. Icons: `DSIcon`

Cases: `.contrast`, `.coffee`, `.volumeUp`, `.timer`, `.calendarToday`, `.edit`, `.close`, `.sort`, `.replay`, `.delete`, `.check`, `.image`, `.description`, `.info`. `DSIcon.allCases` lists them.

```swift
let template = DSIcon.timer.image(size: 18)                    // template NSImage, tint with contentTintColor
let tinted = DSIcon.coffee.image(size: 16, color: DS.muted, opacity: 0.5)
DSIcon.close.draw(in: rect, color: DS.icon)                    // inside draw(_:), flipped or not
```

- `image(size: CGFloat = 18) -> NSImage` returns a cached template image.
- `image(size:color:opacity:) -> NSImage` returns a tinted image. A dynamic color is resolved when the image is drawn.
- `draw(in:color:opacity:)` draws the vector directly.
- `opticalScale` carries the mock's corrections (`close` 1.14, `replay` 0.9) and is applied by all three.
- `path` is the raw `CGPath` in a 960 x 960 box, y down.

The menu bar icons of the apps are not part of this set and stay as they are.

## 4. What every control shares

`DSView` (base of the display components) and `DSControl` (base of the interactive ones):

- Flipped coordinates (origin top left).
- `intrinsicContentSize` is implemented everywhere, so the components work in stack views and with Auto Layout. With manual frames call `sizeToFit()` (sets the frame size to the intrinsic size, keeps a dimension that has no intrinsic value) or read `intrinsicContentSize`.
- `isEnabled: Bool`. Disabled controls draw at 40 % and ignore input.
- `previewState: DSControlState` (`.hovered`, `.pressed`, `.focused`). Forces a state without the mouse. Meant for snapshots.
- Hover, pressed and keyboard focus are handled inside. The focus ring (2 pt blue, 2 pt away) shows only for keyboard focus and is drawn outside the control's bounds, so leave about 5 pt of free space around focusable controls.
- Keyboard: Space or Return activates the focused control, arrow keys change sliders, steppers, segmented controls and radio groups. Controls join the Tab loop only when the system setting "Keyboard navigation" is on, like native controls.
- Clicking a control never steals focus from a text field, except the slider (it takes focus so the arrow keys work afterwards).
- Accessibility role, value and press action are set. Pass `label:` where the control has no visible text, or call `setAccessibilityLabel(_:)`.
- Tooltips: the normal `toolTip` property.

## 5. Components

### DSSlider

```swift
init(value: Double = 0, range: ClosedRange<Double> = 0...1, mode: Mode = .value, label: String? = nil, onChange: ((Double) -> Void)? = nil)
```

| Member | |
|---|---|
| `mode: Mode` | `.value` plain blue fill; `.meter` ghost-blue fill up to the value with the solid live level inside it; `.output` live level only, no knob, not interactive |
| `isCapped: Bool` | only in `.output`: shows the hollow pink knob at `value`, the pink region beyond it, and makes the slider interactive |
| `value`, `minValue`, `maxValue: Double` | setting `value` from code does not call `onChange` |
| `step: Double?` | snap while dragging |
| `keyboardStep: Double?` | arrow key step; default `step`, else 1/20 of the range |
| `onChange: ((Double) -> Void)?` | continuous, while dragging and on arrow keys |
| `onCommit: ((Double) -> Void)?` | on mouse up and after a key step |
| `modifierFlags` | modifier keys of the gesture that caused the latest `onChange` |
| `isDragging`, `fraction`, `liveLevel` | read-only state |
| `setLiveLevel(_ level: CGFloat)` | 0...1. Invalidates only the 4 pt track and skips changes smaller than a quarter point, fine at 10 to 20 Hz |

Height 20, width flexible. Home/End jump to the ends.

```swift
let volume = DSSlider(value: 80, range: 0...150, mode: .meter, label: "Spotify volume")
volume.onChange = { [weak self] value in self?.setVolume(value, commandHeld: volume.modifierFlags.contains(.command)) }
meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in volume.setLiveLevel(currentLevel) }

let output = DSSlider(value: -12, range: -60...0, mode: .output, label: "Night mode cap")
output.step = 1
output.isCapped = nightModeOn
```

### DSToggle

```swift
init(isOn: Bool = false, label: String? = nil, onChange: ((Bool) -> Void)? = nil)
```

`isOn` (setting it from code neither animates nor calls back), `onChange`. Size 30 x 18.

```swift
let night = DSToggle(isOn: settings.nightMode, label: "Night mode") { [weak self] on in self?.setNightMode(on) }
```

### DSButton

```swift
init(_ title: String, style: Style = .secondary, fullWidth: Bool = false, onClick: (() -> Void)? = nil)
```

`style`: `.primary` (blue), `.secondary` (outline), `.quiet` (no outline, muted text). `title`, `isFullWidth`, `onClick`, `fittingWidth` (text + 26). Height 28. With `fullWidth: true` the intrinsic width is undefined and the button fills whatever frame it gets.

```swift
let start = DSButton("Keep awake", style: .primary, fullWidth: true) { [weak self] in self?.startAwake() }
start.frame = NSRect(x: 16, y: y, width: width - 32, height: DS.controlHeight)
let cancel = DSButton("Cancel")
cancel.sizeToFit()
```

### DSIconButton

```swift
init(_ icon: DSIcon, label: String, onClick: (() -> Void)? = nil)
```

24 x 24 with an 18 pt glyph. `icon`, `isOn` (chip background and text-colored glyph, for a button that shows something is open), `iconSize`, `tint` (default `DS.icon`), `hoverTint` (default `DS.blue`), `onClick`. `label` is the accessibility label; set `toolTip` yourself when you want one.

```swift
let sort = DSIconButton(.sort, label: "Sort and group")
sort.onClick = { [weak self, weak sort] in
    guard let self, let sort else { return }
    sort.isOn.toggle()
    self.setOptionsVisible(sort.isOn)
}
```

### DSStepper

```swift
init(value: Int = 0, range: ClosedRange<Int> = 0...59, step: Int = 1, unit: String = "", label: String? = nil, onChange: ((Int) -> Void)? = nil)
```

`value`, `minValue`, `maxValue`, `step`, `unit`, `wraps` (default false), `onChange`, `minimumWidth`. Height 28, width flexible. Holding a side repeats. Arrow keys step.

```swift
let hours = DSStepper(value: 1, range: 0...12, unit: "h", label: "Hours")
let minutes = DSStepper(value: 30, range: 0...55, step: 5, unit: "min", label: "Minutes")
minutes.wraps = true
minutes.onChange = { [weak self] _ in self?.durationChanged() }
```

### DSSegmented

```swift
init(_ items: [String], selectedIndex: Int = 0, label: String? = nil, onChange: ((Int) -> Void)? = nil)
```

`items`, `selectedIndex` (-1 for none; setting it from code does not call back), `equalWidths` (default true; false sizes each segment to its text, as in the Todo sort row), `isCompact` (height 24 instead of 28), `onChange`.

```swift
let format = DSSegmented(["WebP", "AVIF", "JPEG", "PNG"], selectedIndex: 0, label: "Format") { [weak self] index in self?.setFormat(index) }
let sort = DSSegmented(["Added", "Deadline", "A\u{2013}Z"], selectedIndex: 1, label: "Sort by")
sort.equalWidths = false
sort.isCompact = true
sort.sizeToFit()
```

### DSCheckbox

```swift
init(_ title: String? = nil, isOn: Bool = false, label: String? = nil, onChange: ((Bool) -> Void)? = nil)
```

16 x 16 box, optional title 6 pt to the right. `isOn`, `title`, `onChange`. Without a title pass `label:` for accessibility.

```swift
let done = DSCheckbox(isOn: task.isDone, label: "Done") { [weak self] on in self?.setDone(task, on) }
let group = DSCheckbox("Group by project", isOn: true) { [weak self] on in self?.setGrouping(on) }
```

### DSRadioGroup

```swift
init(_ items: [String], selectedIndex: Int = 0, label: String? = nil, onChange: ((Int) -> Void)? = nil)
```

Vertical list, rows 16 pt high with an 8 pt gap. `items`, `selectedIndex`, `onChange`.

```swift
let destination = DSRadioGroup(["Next to originals", "Replace originals", "Choose folder\u{2026}"], selectedIndex: 0, label: "Destination") { [weak self] index in
    self?.setDestination(index)
}
```

### DSTag

```swift
init(_ text: String, style: Style = .neutral, small: Bool = false, icon: DSIcon? = nil, minWidth: CGFloat? = nil)
```

`style`: `.neutral` (chip background), `.red`, `.blue`, `.amber`, `.plain` (no background, muted text, no padding; the "Done today" look). Regular is 18 pt high with 11 pt text, `small` is 15 pt with 9.5 pt text. `icon` adds an 11 pt glyph in front. `minWidth` centers the content in a fixed width. `isMuted` switches a neutral tag to muted text (the file type tags in Squeeze). Not interactive.

```swift
let due = DSTag("2 days ago", style: .red, small: true)
due.sizeToFit()
let type = DSTag("JPG", icon: .image, minWidth: 52)
type.isMuted = true
```

Todo deadlines in the mock: overdue `.red`, today `.blue`, tomorrow and up to 3 days `.amber`, later `.neutral`, all `small`.

### DSChip

```swift
init(_ title: String, style: Style = .dashed, label: String? = nil, onClick: (() -> Void)? = nil)
```

`style`: `.dashed` is the copy chip (dashed outline, minimum width 40), `.solid` is the filled preset chip from Squeeze. `title`, `isCopied` (stays blue until you clear it), `onClick`. Height 24.

```swift
let chips = values.map { DSChip($0) }
for chip in chips {
    chip.onClick = { [weak chip] in
        guard let chip else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(chip.title, forType: .string)
        chips.forEach { $0.isCopied = $0 === chip }
    }
}
```

### DSTextField

A real `NSTextField` subclass, so `stringValue`, `delegate`, `target`/`action`, `placeholderString`, the field editor and all `NSTextFieldDelegate` code keep working.

```swift
init(placeholder: String = "", text: String = "")
```

1 pt outline, radius 4, blue outline while editing, placeholder in `DS.icon`. `unit: String?` (muted suffix inside the field, e.g. "px"), `showsFocusStyle` (forces the blue outline, for snapshots), `isFocused`, `onChange: ((String) -> Void)?` (every edit), `onSubmit: ((String) -> Void)?` (Return; assigning it takes over `target`/`action`). Intrinsic height 28; give it a 32 pt frame for the Todo add field.

```swift
let add = DSTextField(placeholder: "Add a task\u{2026}")
add.frame = NSRect(x: 16, y: 12, width: 340, height: 32)
add.onSubmit = { [weak self, weak add] text in
    self?.addTask(text)
    add?.stringValue = ""
}
let edge = DSTextField(text: "1920")
edge.unit = "px"
```

### DSProgressBar

```swift
init(progress: Double = 0)
```

`progress` 0...1. Height 4, width flexible.

```swift
let bar = DSProgressBar(progress: 0)
bar.progress = Double(finished) / Double(total)
```

### DSSeparator

```swift
init(color: NSColor = DS.chip)
```

Fills its frame. Give it a height (or width) of 1.

```swift
let rule = DSSeparator()
rule.frame = NSRect(x: 0, y: y, width: width, height: 1)
```

### DSSectionHeader

```swift
init(icon: DSIcon? = nil, title: String, value: String? = nil)
```

16 pt row: 16 pt icon at 50 %, 11 pt muted title, optional value on the right in `DS.text`. `icon`, `title`, `value`, `valueColor`. Setting `value` only redraws this row.

```swift
let header = DSSectionHeader(icon: .contrast, title: "Brightness", value: "62 %")
header.frame = NSRect(x: 16, y: y, width: width - 32, height: 16)
slider.onChange = { value in header.value = "\(Int(value.rounded())) %" }
```

### DSLinkButton

```swift
init(_ title: String, onClick: (() -> Void)? = nil)
```

11 pt muted text with a thin underline, blue on hover. `title`, `onClick`. Height 16.

```swift
let formats = DSLinkButton("Supported formats") { [weak self] in self?.toggleFormats() }
formats.sizeToFit()
```

### DSLabel

```swift
init(_ text: String = "", size: CGFloat = 13, weight: NSFont.Weight = .regular, color: NSColor = DS.text)
```

Text drawn with the same metrics as the controls, so baselines line up. `text`, `font`, `color`, `alignment`, `maxLines` (1 = one line cut with an ellipsis, the default; 0 = wrap without limit), `lineHeight` (default 1.25 x size, rounded), `isStruck` (line through, for done tasks), `height(forWidth:)`. A one-line label centers its text vertically in whatever frame height it gets, so a 20 pt high frame lines up with a slider or toggle in the same row.

```swift
let name = DSLabel("MacBook Speakers")
name.frame = NSRect(x: 16, y: y, width: 126, height: DS.rowHeight)
let count = DSLabel("24:10", weight: .semibold, color: DS.ink)
let task = DSLabel(item.text)
task.maxLines = 0
task.lineHeight = 20
task.frame = NSRect(x: 44, y: 6, width: textWidth, height: task.height(forWidth: textWidth))
```

### DSBubble

```swift
init(_ text: String, title: String? = nil)
```

A small inverted note (ink background, paper text, 11 pt, radius 4) for transient feedback and hover hints. Without a title it is one line, 18 pt high ("Copied"). With a title it shows the muted title over the text, which wraps at `maxWidth` (default 220). It sizes itself (`frame.size` is set on init and whenever `text` or `maxWidth` changes), never receives mouse events, and is not shown or hidden by the kit: add it as a subview above the content, position it, and remove or hide it yourself.

```swift
let note = DSBubble("Copied")
note.setFrameOrigin(NSPoint(x: chip.frame.midX - note.frame.width / 2, y: chip.frame.minY - 4 - note.frame.height))
content.addSubview(note)
DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak note] in note?.removeFromSuperview() }

let formats = DSBubble("JPEG, PNG, HEIC, TIFF, GIF, WebP, AVIF, BMP and PDF", title: "Supported formats")
```

### DSBrand

The maker's credit for the right-click menu of every app. The menu itself stays a native `NSMenu`.

```swift
menu.addItem(.separator())
menu.addItem(DSBrand.menuItem())
menu.addItem(.separator())
menu.addItem(quitItem)
```

`DSBrand.menuItem()` returns the row "by Vojtěch Okénka" with the logo (blue rounded square, white dot); clicking it opens `DSBrand.url`. `DSBrand.logo(size:)` gives the logo as an image, `DSBrand.credit` the text.

## 6. DSPanel

A borderless floating panel for menu bar apps: paper background, 12 pt corners, hairline ring and soft shadow (drawn by a click-through child window, the system window shadow is off).

```swift
init(width: CGFloat, content: NSView? = nil)
```

| Member | |
|---|---|
| `content: NSView?` | the app's root view; assigning it re-measures the panel |
| `show(under: NSStatusBarButton)` | below the status item, centered on it, clamped to the screen |
| `toggle(under: NSStatusBarButton)` | show or dismiss; use this in the status item action |
| `show(below: NSRect, screen: NSScreen? = nil)` | below any rect given in screen coordinates |
| `show(at: NSPoint, screen: NSScreen? = nil)` | top left corner at a screen point, clamped (Picker) |
| `dismiss()` | hides the panel and calls `onClose`; `close()` does the same |
| `isShown: Bool` | |
| `onClose: (() -> Void)?`, `onShow: (() -> Void)?` | called once per show / dismiss |
| `onEscape: (() -> Bool)?` | return true to consume Esc and keep the panel open |
| `sizeToContent()` | call after the content's height changed; the top edge stays where it is |
| `setContentHeight(_: CGFloat?)` | set the height yourself; nil goes back to measuring |
| `maxHeight: CGFloat?` | taller content scrolls inside the panel |
| `setWidth(_:)`, `panelWidth` | |
| `closesOnOutsideClick` (true), `closesOnEscape` (true), `takesKeyFocus` (true) | |
| `alignment` (`.center`, `.leading`, `.trailing`), `gap` (4), `screenMargin` (8) | placement under the anchor |

How the height is found: `contentHeight` if you set it; otherwise `fittingSize.height` when the content uses Auto Layout (`translatesAutoresizingMaskIntoConstraints == false`); otherwise the content's `frame.height`. The panel sets the content's width. The height is also limited by `maxHeight` and by the space between the menu bar and the bottom of the screen.

Behavior:

- The panel becomes key without activating the app, so text fields work while the app in front stays in front. Cut, copy, paste, select all, undo and redo work in text fields even if the app has no Edit menu.
- A click in another app, in another window of the same app, or a change of the key window dismisses it. A click on the status item it was shown under is left to your action, so `toggle(under:)` does not reopen the panel it just closed. Popovers and menus opened from inside the panel do not dismiss it.
- Esc: an input method composing text gets it first; then a text field delegate that returns true from `control(_:textView:doCommandBy:)` for `cancelOperation(_:)`; then `onEscape`; otherwise the panel dismisses.
- Set `initialFirstResponder` to focus a field when the panel opens.
- For the Picker HUD: `takesKeyFocus = false`, `closesOnOutsideClick = false`, optionally `isMovable = true` and `isMovableByWindowBackground = true`, then `show(at:)`.

```swift
let panel = DSPanel(width: 360, content: rootView)
panel.maxHeight = 640
panel.onClose = { [weak self] in self?.stopMeters() }

@objc func statusItemClicked() {
    guard let button = statusItem.button else { return }
    if NSApp.currentEvent?.type == .rightMouseUp {
        panel.dismiss()
        showMenu()
    } else {
        panel.toggle(under: button)
    }
}

func rowsChanged() {
    rootView.setFrameSize(NSSize(width: 360, height: newHeight))
    panel.sizeToContent()
}
```

`DSSurface.draw(around:radius:)` draws the same paper + ring + shadow into any view (it needs free space around the rect: `DSSurface.outset` is top 24, sides 40, bottom 52). `DSPanel.frame(size:below:in:gap:margin:alignment:)` is the pure placement function.

A regular titled window (Squeeze) does not need `DSPanel`: set `window.backgroundColor = DS.paper` and use the components.

## 7. Drawing your own views

For rows and one-off views use the same helpers the kit uses, inside `draw(_:)`:

```swift
DSDraw.fill(bounds, DS.sunken)                                   // hover row
DSDraw.fill(rect, radius: DS.radius, DS.chip)
DSDraw.border(rect, radius: DS.radius, DS.line)                   // 1 pt, inside the rect
DSDraw.dashedBorder(rect, radius: DS.radius, DS.line)             // drop zone at rest
DSDraw.fill(rect, radius: DS.radius, DS.blueWash)                 // drop zone with files over it,
DSDraw.border(rect, radius: DS.radius, DS.blue)                   // together with a solid blue border
DSDraw.circle(center: point, radius: 5, DS.icon)
DSDraw.focusRing(rect, radius: DS.radius)
DSDraw.dimmed(!isEnabled) { drawContent() }                       // 40 % group opacity

DSText.width("Optimize", font: DS.bodyFont)
DSText.draw("Optimize", in: rect, font: DS.bodyFont, color: DS.text, alignment: .center)
DSText.baseline(top: rect.minY, height: rect.height, font: DS.bodyFont)
```

`DSText.draw` centers one line vertically the way the browser does in the mock, truncates with an ellipsis, and works in flipped and unflipped views. Use `DSDraw.fill` rather than `NSRect.fill()` for translucent colors (`NSRect.fill()` replaces instead of blending). `DSTween` is the small timer animation behind the toggle and the slider knob; it respects Reduce Motion.

## 8. DSSnapshot

Renders any view into a PNG offscreen, in a forced appearance, without showing a window.

```swift
DSSnapshot.write(view: NSView, to: URL, dark: Bool, scale: CGFloat = 2, background: NSColor? = DS.paper, panel: Bool = false) -> Bool
DSSnapshot.render(view:dark:scale:background:panel:) -> NSBitmapImageRep?
```

- A view without a size gets its `fittingSize`. Views that are not in a window are hosted in a hidden one for the render and put back afterwards.
- `background: nil` keeps transparency.
- `panel: true` renders the view as it looks inside a `DSPanel`: clipped to the 12 pt corners, with ring and shadow, on a neutral backdrop.
- Use `previewState` on controls and `showsFocusStyle` on text fields to show hover, pressed and focus states.

### Adding `--snapshot` to an app

Put this in the app's `main.swift` before the `NSApplication` run loop starts, and build the root view with the same function the panel uses, filled with sample data:

```swift
if let flag = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > flag + 1 {
    let directory = URL(fileURLWithPath: CommandLine.arguments[flag + 1], isDirectory: true)
    _ = NSApplication.shared
    DS.registerFonts()
    for dark in [false, true] {
        let view = HubPanelView.sample()
        let file = directory.appendingPathComponent(dark ? "hub-dark.png" : "hub-light.png")
        if !DSSnapshot.write(view: view, to: file, dark: dark, panel: true) { exit(1) }
    }
    exit(0)
}
```

```zsh
./build.sh && build/Hub.app/Contents/MacOS/Hub --snapshot /path/to/output
```

The branch exits before any status item, hot key or audio setup runs, so it has no side effects. The font is found because the binary runs from inside the app bundle.

## 9. Layout numbers from the mock

- Hub panel, width 360: 4 pt above the first and below the last section. Section: 12 pt top padding, rows 10 pt apart, 14 pt bottom padding, a 1 pt `DSSeparator` between sections. Row order in a section: `DSSectionHeader` (16), then controls. Label + control rows are 20 pt high; the name column is 126 pt wide (or a 16 pt app icon, 10 pt gap and a 100 pt name), then a 10 pt gap, then the slider (150 pt), then 6 pt and a 36 pt value column (app volume in percent, 11 pt muted, right-aligned; empty in the output row), so all sliders share one column.
- Timer block: two `DSStepper`s side by side with a 10 pt gap, 10 pt below them a full-width primary `DSButton`. Running state: a row with a muted label on the left and the countdown (13 pt, weight 600, `DS.ink`) on the right, then a full-width secondary "Cancel".
- Todo panel, width 420: 12 pt top and 8 pt bottom padding. Add row: text field 32 pt high, 6 pt gaps, two icon buttons. Task row: 6 pt vertical and 16 pt side padding, 16 pt checkbox, 12 pt gap, text with a 20 pt line height, small deadline tag 3 pt below the text, checkbox centered on text + tag. Row hover is `DS.sunken`.
- Picker HUD: 360 x 132, the swatch fills the left 132 pt, then a 20 pt gap, value rows 8 pt apart, an 11 pt muted format label 30 pt wide, chips 6 pt apart, close icon button 8 pt from the top right corner.
- Squeeze window, width 500: body padding 16 / 20 / 20, blocks 24 pt apart, form rows 20 pt apart with a 96 pt muted label column and a 16 pt gap. File rows: 11 pt vertical padding, a 52 pt wide type tag, 10 pt gap, name (13) over details (11, muted) 3 pt apart.

## 10. Demo gallery

```zsh
cd Shared
./build-demo.sh /absolute/path/to/output
/absolute/path/to/output/ds-demo /absolute/path/to/output
```

`build-demo.sh [dir]` compiles `Demo/main.swift` with the kit into `dir/ds-demo` (default `Shared/build`, which is git-ignored). `ds-demo <dir>` writes `gallery-light.png` and `gallery-dark.png` with every component in its states, plus a sample Hub panel. It never shows a window.

## 11. Where the kit differs from the mock on purpose

- Pressed states (button, chip, icon button, stepper side) are added; the mock defines only hover.
- Disabled look for controls the mock never shows disabled (slider, toggle, stepper, checkbox, chip) uses the mock's 40 % rule for buttons.
- The capped output level is `live x (knob center)`, so silence draws nothing. The mock's formula leaves an 8 pt blue stub at zero.
- No pointing-hand cursor. Native menu bar apps keep the arrow.
- Hover and toggle transitions are short timer animations; the stepper and buttons switch instantly.
- A one-line `DSLinkButton` is 16 pt high instead of 13.75 so the underline stays inside its bounds.
- Text is drawn without font smoothing, which matches the mock's `-webkit-font-smoothing: antialiased`. System controls next to it (menus, title bars) look slightly heavier.
