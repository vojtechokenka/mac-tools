#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="build/Picker.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
SOURCES=(main.swift)
FRAMEWORKS=(-framework AppKit -framework Carbon)
if [[ "$UNIVERSAL" == "1" ]]; then
  swiftc -O -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Picker-arm64" "${SOURCES[@]}" "${FRAMEWORKS[@]}"
  swiftc -O -target x86_64-apple-macos14.0 -o "$APP/Contents/MacOS/Picker-x86_64" "${SOURCES[@]}" "${FRAMEWORKS[@]}"
  lipo -create -output "$APP/Contents/MacOS/Picker" "$APP/Contents/MacOS/Picker-arm64" "$APP/Contents/MacOS/Picker-x86_64"
  rm "$APP/Contents/MacOS/Picker-arm64" "$APP/Contents/MacOS/Picker-x86_64"
else
  swiftc -O -o "$APP/Contents/MacOS/Picker" "${SOURCES[@]}" "${FRAMEWORKS[@]}"
fi
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Picker</string>
  <key>CFBundleIdentifier</key><string>cz.vojtechokenka.picker</string>
  <key>CFBundleExecutable</key><string>Picker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$APP"
echo "Built $APP"
