# mac-tools

Three small menu bar utilities for macOS, written in plain Swift and built with `swiftc` — no Xcode project, no dependencies.

| App | What it does |
|---|---|
| **Hub** | Per-app volume mixer with live meters, a night mode that hard-caps loudness, a sleep timer that fades audio out and puts the Mac to sleep, screen dimming below the system minimum (⌘ + brightness keys), and a stay-awake timer. |
| **Todo** | A to-do list in the menu bar backed by a plain Markdown file. Projects (`Project; task`), deadlines with a countdown, ⌃⌥N to add a task from anywhere. |
| **Picker** | Color picker: click the icon or press ⌃⌥C to sample any pixel with the system loupe; HEX / RGB / HSL in copyable chips, history of the last 12 colors. |

## Requirements

- macOS 14 or newer for Todo and Picker, macOS 15 or newer for Hub (Core Audio process taps + the `Synchronization` module).
- Apple Silicon or Intel.

## Install (prebuilt, no developer tools needed)

Paste this into Terminal — it downloads the latest universal builds (Apple Silicon + Intel) into `/Applications`:

```bash
curl -fsSL https://raw.githubusercontent.com/vojtechokenka/mac-tools/main/get.sh | zsh
```

To install only some of the apps: `curl -fsSL https://raw.githubusercontent.com/vojtechokenka/mac-tools/main/get.sh | zsh -s Hub Picker`

Or download a `.zip` from [Releases](https://github.com/vojtechokenka/mac-tools/releases), unzip it into `/Applications` and, because the apps are not notarized, clear the quarantine flag once:

```bash
xattr -dr com.apple.quarantine /Applications/Hub.app
```

Launch the apps from Finder or Spotlight (not directly from a terminal — macOS attributes privacy permissions to the terminal otherwise). To start them at login, add them in System Settings → General → Login Items.

## Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`); full Xcode is not needed.

```bash
git clone https://github.com/vojtechokenka/mac-tools.git
cd mac-tools
./install.sh
```

`install.sh` builds every app into `<App>/build/<App>.app` and copies it to `/Applications`. A single app: `cd Hub && ./build.sh && cp -R build/Hub.app /Applications/`. `UNIVERSAL=1 ./build.sh` produces a universal binary; `./release.sh vX.Y.Z` builds all three and publishes a GitHub release.

## Permissions

- **Hub** asks for *System Audio Recording* (needed for per-app volume — it captures each app's audio, adjusts it and plays it back) and *Accessibility* (⌘ + brightness keys, pausing media when the sleep timer ends).
- **Todo** and **Picker** need nothing.

The apps are ad-hoc signed, not notarized. Prebuilt downloads therefore need the quarantine flag removed (`get.sh` does it for you); building from source avoids it entirely. A rebuilt or updated app gets a new identity, so re-grant the permissions after updating.

## Hub

- Left click: Brightness slider, Stay awake (hours/minutes + button), the audio section (one row per playing app with the live level drawn inside the volume slider; hold ⌘ to push a slider above 100 %), Night mode (toggle; the hollow knob on the output meter sets the cap — nothing gets louder than that, quieter content is left alone), Sleep timer (fades the mix out over the last two minutes, pauses playback, optionally sleeps the Mac).
- Right click: permissions, "Sleep Mac when timer ends", Quit.
- Shortcuts: ⌘ + brightness up/down (with Accessibility), ⌃⌥⌘↑/↓ and ⌘F1/⌘F2.
- Night mode internals are documented in `Hub/docs/night-mode-dsp.md` (in Czech).

## Todo

- The task file is `~/Documents/tasks.md` by default (change it in Settings…). Format:

```
# Tasks

## Tasks
- [ ] Project; Do the thing @2026-10-20
- [x] Done thing ✓2026-10-12T14:05

## Archive
- [x] Older thing ✓2026-09-26
```

- Type `Project; task text` to group tasks; end with a date token (`tomorrow`, `fri`, `3.10.`, `@2026-10-03`) or pick one in the calendar. Tasks sort by project, then deadline. Completed tasks move to the archive immediately or after 24 h (Settings…).
- Right click the icon for Settings… and Quit. ⌃⌥N opens the panel.

## Picker

- Click the icon or press ⌃⌥C, pick a color. The preferred format (HEX by default, set via right click → Copy as) is copied automatically; click any chip to copy that single value, click the HEX/RGB/HSL label to copy the full notation. The panel stays until you close it and can be dragged around.

## License

MIT — see `LICENSE`.
