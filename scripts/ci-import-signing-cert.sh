#!/bin/bash
# CI only: imports the signing certificate from MACSLIDER_SIGNING_CERT /
# MACSLIDER_SIGNING_PASSWORD into a temporary keychain and exports
# SIGN_IDENTITY for scripts/build-app.sh.
set -euo pipefail

: "${MACSLIDER_SIGNING_CERT:?}" "${MACSLIDER_SIGNING_PASSWORD:?}"
NAME="MacSlider Self-Signed"  # the certificate's name; kept so existing secrets and permissions stay valid
TMP="${RUNNER_TEMP:-$(mktemp -d)}"
KEYCHAIN="$TMP/signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"

printf '%s' "$MACSLIDER_SIGNING_CERT" | base64 --decode > "$TMP/cert.p12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 21600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P "$MACSLIDER_SIGNING_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" > /dev/null
# Put the keychain on the search list so codesign can find the identity.
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

# Trust the self-signed certificate for code signing on this runner.
security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$TMP/cert.pem"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$TMP/cert.pem"
rm -f "$TMP/cert.p12"

HASH="$(security find-identity -p codesigning "$KEYCHAIN" | awk -v name="\"$NAME\"" 'index($0, name) {print $2; exit}')"
[ -n "$HASH" ] || { security find-identity -p codesigning "$KEYCHAIN"; echo "Signing identity not found" >&2; exit 1; }
echo "SIGN_IDENTITY=$HASH" >> "${GITHUB_ENV:-/dev/null}"
echo "Imported \"$NAME\" ($HASH)"
