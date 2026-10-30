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
if command -v dmgbuild > /dev/null; then
    # The styled installer: app and Applications side by side over a background
    # that says "drag Monorail into Applications".
    BACKGROUND="$(mktemp -d)/background.tiff"
    tiffutil -cathidpicheck assets/dmg/background.png assets/dmg/background@2x.png -out "$BACKGROUND" > /dev/null
    dmgbuild -s scripts/dmg-settings.py \
        -D app="$APP" -D background="$BACKGROUND" \
        -D volume_icon="$APP/Contents/Resources/AppIcon.icns" \
        "Monorail by Ashforde® ${VERSION}" "$DMG"
else
    echo "    (dmgbuild not found: making a plain disk image; pip install dmgbuild for the styled one)"
    STAGING="$(mktemp -d)"
    cp -R "$APP" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"
    hdiutil create -volname "Monorail by Ashforde® ${VERSION}" -srcfolder "$STAGING" -ov -format UDZO "$DMG" > /dev/null
    rm -rf "$STAGING"
fi

(cd dist && shasum -a 256 "$(basename "$ZIP")" "$(basename "$DMG")" "$(basename "$LEGACY_ZIP")" > SHA256SUMS)
cat dist/SHA256SUMS
