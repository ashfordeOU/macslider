#!/bin/bash
# Builds dist/MacSlider.app as a universal (Apple silicon + Intel) binary.
#
# Signing: set SIGN_IDENTITY to a codesigning identity (name or SHA-1) to
# sign with it, e.g. the "MacSlider Self-Signed" certificate CI imports or a
# "Developer ID Application: …" identity. Otherwise the app is signed ad hoc.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="dist/MacSlider.app"

echo "==> Building MacSlider ${VERSION} (${BUILD})"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MacSlider" "$APP/Contents/MacOS/MacSlider"
cp scripts/macslider "$APP/Contents/Resources/macslider"
cp LICENSE "$APP/Contents/Resources/LICENSE"
sed -e "s/__VERSION__/${VERSION}/" -e "s/__BUILD__/${BUILD}/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icon"
# assets/icon.png is the 1024px master (re-render with scripts/render-icon.py).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" assets/icon.png --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    double=$((size * 2))
    sips -z "$double" "$double" assets/icon.png --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Signing"
if [ -n "${SIGN_IDENTITY:-}" ]; then
    # Apple's timestamp server only serves Apple-issued certificates.
    TIMESTAMP="--timestamp=none"
    case "$SIGN_IDENTITY" in "Developer ID"*) TIMESTAMP="--timestamp" ;; esac
    codesign --force --options runtime $TIMESTAMP --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
# The designated requirement is what macOS ties permissions to; a stable
# certificate keeps it the same across builds.
codesign --display --requirements - "$APP" 2>&1 | grep designated || true

echo "==> Done: $APP"
lipo -info "$APP/Contents/MacOS/MacSlider"
