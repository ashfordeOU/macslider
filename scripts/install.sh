#!/bin/bash
# Installs the latest Monorail release into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/ashfordeOU/monorail/main/scripts/install.sh | bash
set -euo pipefail

REPO="ashfordeOU/monorail"
DEST="/Applications"

[ "$(uname -s)" = "Darwin" ] || { echo "Monorail runs on macOS only." >&2; exit 1; }

echo "==> Finding the latest release"
URL="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
    | grep -o '"browser_download_url": *"[^"]*/Monorail-[^"]*\.zip"' | head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')"
[ -n "$URL" ] || { echo "No release found." >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
echo "==> Downloading ${URL##*/}"
curl -fsSL "$URL" -o "$TMP/Monorail.zip"
ditto -x -k "$TMP/Monorail.zip" "$TMP"

for name in Monorail MacSlider; do
    if pgrep -xq "$name"; then
        echo "==> Quitting the running copy"
        osascript -e "quit app id \"org.ashforde.macslider\"" || pkill -x "$name" || true
        sleep 1
    fi
done

echo "==> Installing to ${DEST}"
rm -rf "${DEST}/Monorail.app" "${DEST}/MacSlider.app"  # MacSlider was Monorail's earlier name
ditto "$TMP/Monorail.app" "${DEST}/Monorail.app"
xattr -dr com.apple.quarantine "${DEST}/Monorail.app" 2>/dev/null || true

echo "==> Opening Monorail"
open "${DEST}/Monorail.app"
echo "Done. Grant Accessibility access when asked."
