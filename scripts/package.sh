#!/bin/bash
# Packages dist/Monorail.app into a .zip and a .dmg with SHA-256 checksums.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/Monorail.app"
[ -d "$APP" ] || { echo "Run scripts/build-app.sh first" >&2; exit 1; }

ZIP="dist/Monorail-${VERSION}.zip"
DMG="dist/Monorail-${VERSION}.dmg"
# MacSlider 0.2.x updaters look for "MacSlider-*.zip" holding MacSlider.app.
LEGACY_ZIP="dist/MacSlider-${VERSION}.zip"
rm -f "$ZIP" "$DMG" "$LEGACY_ZIP" dist/SHA256SUMS

echo "==> $ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> $LEGACY_ZIP (for updating from MacSlider 0.2.x)"
LEGACY="$(mktemp -d)"
ditto "$APP" "$LEGACY/MacSlider.app"
ditto -c -k --sequesterRsrc --keepParent "$LEGACY/MacSlider.app" "$LEGACY_ZIP"
rm -rf "$LEGACY"

echo "==> $DMG"
STAGING="$(mktemp -d)"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Monorail ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG" > /dev/null
rm -rf "$STAGING"

(cd dist && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" "$(basename "$LEGACY_ZIP")" > SHA256SUMS)
cat dist/SHA256SUMS
