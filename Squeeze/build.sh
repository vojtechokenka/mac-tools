#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="build/Squeeze.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
SOURCES=(main.swift Optimizer.swift)
FRAMEWORKS=(-framework AppKit -framework ImageIO -framework CoreGraphics -framework UniformTypeIdentifiers -framework UserNotifications)
WEBP=(-import-objc-header webp-bridge.h -I vendor/libwebp/include)
ARM_LIBS=(vendor/libwebp/lib/arm64/libwebp.a vendor/libwebp/lib/arm64/libsharpyuv.a)
X86_LIBS=(vendor/libwebp/lib/x86_64/libwebp.a vendor/libwebp/lib/x86_64/libsharpyuv.a)
if [[ "$UNIVERSAL" == "1" && ! -f "${X86_LIBS[1]}" ]]; then
  echo "UNIVERSAL=1 requested, but ${X86_LIBS[1]} is missing – building arm64 only"
  UNIVERSAL=0
fi
if [[ "$UNIVERSAL" == "1" ]]; then
  swiftc -O -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Squeeze-arm64" "${SOURCES[@]}" "${FRAMEWORKS[@]}" "${WEBP[@]}" "${ARM_LIBS[@]}"
  swiftc -O -target x86_64-apple-macos14.0 -o "$APP/Contents/MacOS/Squeeze-x86_64" "${SOURCES[@]}" "${FRAMEWORKS[@]}" "${WEBP[@]}" "${X86_LIBS[@]}"
  lipo -create -output "$APP/Contents/MacOS/Squeeze" "$APP/Contents/MacOS/Squeeze-arm64" "$APP/Contents/MacOS/Squeeze-x86_64"
  rm "$APP/Contents/MacOS/Squeeze-arm64" "$APP/Contents/MacOS/Squeeze-x86_64"
else
  swiftc -O -o "$APP/Contents/MacOS/Squeeze" "${SOURCES[@]}" "${FRAMEWORKS[@]}" "${WEBP[@]}" "${ARM_LIBS[@]}"
fi
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Squeeze</string>
  <key>CFBundleIdentifier</key><string>cz.vojtechokenka.squeeze</string>
  <key>CFBundleExecutable</key><string>Squeeze</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
