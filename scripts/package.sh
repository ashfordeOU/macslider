#!/bin/bash
# Packages dist/MacSlider.app into a .zip and a .dmg with SHA-256 checksums.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/MacSlider.app"
[ -d "$APP" ] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

ZIP="dist/MacSlider-${VERSION}.zip"
DMG="dist/MacSlider-${VERSION}.dmg"
rm -f "$ZIP" "$DMG" dist/SHA256SUMS

echo "==> $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "MacSlider ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGING"

(cd dist && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" > SHA256SUMS)
cat dist/SHA256SUMS
