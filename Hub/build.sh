#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="build/Hub.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$APP/Contents/MacOS/Hub" main.swift Controls.swift Audio.swift NightChain.swift Display.swift Awake.swift -framework AppKit -framework AudioToolbox -framework CoreAudio -framework Carbon -framework IOKit
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Hub</string>
  <key>CFBundleIdentifier</key><string>cz.vojtechokenka.hub</string>
  <key>CFBundleExecutable</key><string>Hub</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Hub needs access to system audio to adjust the volume of individual apps.</string>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP"
