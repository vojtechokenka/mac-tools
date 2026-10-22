#!/bin/zsh
set -e
cd "$(dirname "$0")"
VERSION="$1"
[[ -z "$VERSION" ]] && { echo "usage: ./release.sh v0.1.0"; exit 1; }
rm -rf dist && mkdir -p dist
for app in Hub Todo Picker Squeeze; do
  (cd "$app" && UNIVERSAL=1 ./build.sh)
  ditto -c -k --keepParent "$app/build/$app.app" "dist/$app.zip"
  echo "dist/$app.zip"
done
gh release create "$VERSION" dist/*.zip --title "$VERSION" --notes "Universal (Apple Silicon + Intel) builds of Hub, Todo, Picker and Squeeze. Install with get.sh or unzip into /Applications and remove quarantine: xattr -dr com.apple.quarantine /Applications/<App>.app"
