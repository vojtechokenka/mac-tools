#!/bin/zsh
set -e
REPO="vojtechokenka/mac-tools"
APPS=("$@")
[[ ${#APPS[@]} -eq 0 ]] && APPS=(Hub Todo Picker Squeeze)
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MAJOR" -lt 14 ]]; then echo "macOS 14 or newer is required (you have $(sw_vers -productVersion))."; exit 1; fi
TMP=$(mktemp -d)
for app in "${APPS[@]}"; do
  if [[ "$app" == "Hub" && "$MAJOR" -lt 15 ]]; then echo "Hub needs macOS 15 or newer, skipping."; continue; fi
  echo "Downloading $app…"
  curl -fsSL "https://github.com/$REPO/releases/latest/download/$app.zip" -o "$TMP/$app.zip"
  osascript -e "quit app \"$app\"" >/dev/null 2>&1 || true
  rm -rf "/Applications/$app.app"
  ditto -x -k "$TMP/$app.zip" /Applications
  xattr -dr com.apple.quarantine "/Applications/$app.app" 2>/dev/null || true
  echo "Installed /Applications/$app.app"
done
rm -rf "$TMP"
echo "Done. Open the apps from Finder or Spotlight and grant the permissions they ask for."
