#!/bin/bash
# Creates Monorail's self-signed code-signing certificate and hands it to
# GitHub, so every release is signed with the same identity and macOS keeps
# the Accessibility permission across updates.
#
#   scripts/make-signing-cert.sh            create it and add the two secrets
#   scripts/make-signing-cert.sh --out DIR  just write cert.p12.b64 and password to DIR
#
# Run it once, on your own Mac. The private key never leaves your machine
# except as an encrypted GitHub secret.
set -euo pipefail

NAME="MacSlider Self-Signed"  # the certificate's name; kept so existing secrets and permissions stay valid
REPO="ashfordeOU/macslider"
OPENSSL=/usr/bin/openssl   # macOS LibreSSL writes .p12 files the keychain can import
[ -x "$OPENSSL" ] || OPENSSL=openssl

OUT=""
if [ "${1:-}" = "--out" ]; then
    OUT="${2:?usage: $0 --out DIR}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 7300 -sha256 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2> /dev/null
PASSWORD="$("$OPENSSL" rand -hex 16)"
LEGACY=""
"$OPENSSL" version | grep -q '^OpenSSL 3' && LEGACY="-legacy"
"$OPENSSL" pkcs12 -export $LEGACY -name "$NAME" -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -out "$WORK/cert.p12" -passout "pass:$PASSWORD"
CERT_B64="$(base64 < "$WORK/cert.p12" | tr -d '\n')"

if [ -n "$OUT" ]; then
    mkdir -p "$OUT"
    printf '%s' "$CERT_B64" > "$OUT/cert.p12.b64"
    printf '%s' "$PASSWORD" > "$OUT/password"
    echo "Wrote $OUT/cert.p12.b64 and $OUT/password"
    exit 0
fi

if command -v gh > /dev/null && gh auth status > /dev/null 2>&1; then
    printf '%s' "$CERT_B64" | gh secret set MACSLIDER_SIGNING_CERT --repo "$REPO"
    printf '%s' "$PASSWORD" | gh secret set MACSLIDER_SIGNING_PASSWORD --repo "$REPO"
    echo "Done: both secrets are set on $REPO. The next build is signed as \"$NAME\"."
    exit 0
fi

# No GitHub CLI: walk through adding the two secrets by hand.
URL="https://github.com/$REPO/settings/secrets/actions/new"
cat <<MSG

Add two repository secrets at:
  $URL

MSG
printf '%s' "$CERT_B64" | pbcopy
echo "1) Name: MACSLIDER_SIGNING_CERT   Value: copied to your clipboard — paste it and click Add secret."
open "$URL" 2> /dev/null || true
read -r -p "   Press Return when that's saved… "
printf '%s' "$PASSWORD" | pbcopy
echo "2) Name: MACSLIDER_SIGNING_PASSWORD   Value: copied to your clipboard — paste it and click Add secret."
open "$URL" 2> /dev/null || true
read -r -p "   Press Return when that's saved… "
printf '' | pbcopy
echo "Done. The next build is signed as \"$NAME\"."
