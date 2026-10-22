#!/bin/zsh
set -e
cd "$(dirname "$0")"
for app in Hub Todo Picker Squeeze; do
  echo "Building $app…"
  (cd "$app" && ./build.sh)
  osascript -e "quit app \"$app\"" >/dev/null 2>&1 || true
  rm -rf "/Applications/$app.app"
  cp -R "$app/build/$app.app" /Applications/
  echo "Installed /Applications/$app.app"
done
echo "Done. Launch the apps from Finder or Spotlight and grant the permissions they ask for."
