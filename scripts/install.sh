#!/bin/bash
# Installs the latest MacSlider release into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/ashfordeOU/macslider/main/scripts/install.sh | bash
set -euo pipefail

REPO="ashfordeOU/macslider"
DEST="/Applications"

[ "$(uname -s)" = "Darwin" ] || { echo "MacSlider runs on macOS only." >&2; exit 1; }

echo "==> Finding the latest release"
URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')"
[ -n "$URL" ] || { echo "No release found." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "==> Downloading ${URL##*/}"
curl -fsSL "$URL" -o "$TMP/MacSlider.zip"
ditto -x -k "$TMP/MacSlider.zip" "$TMP"

if pgrep -xq MacSlider; then
    echo "==> Quitting the running copy"
    osascript -e 'quit app "MacSlider"' || true
    sleep 1
fi

echo "==> Installing to ${DEST}"
rm -rf "${DEST}/MacSlider.app"
ditto "$TMP/MacSlider.app" "${DEST}/MacSlider.app"
xattr -dr com.apple.quarantine "${DEST}/MacSlider.app" 2>/dev/null || true

echo "==> Opening MacSlider"
open "${DEST}/MacSlider.app"
echo "Done. Grant Accessibility access when asked."
