#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# Betfair non-interactive (cert-based) login — cert generation
#
# Betfair requires a self-signed client certificate for the
# /api/certlogin endpoint. This script produces a matching
# .crt / .key pair and prints the values in the exact shape
# needed for Vercel environment variables.
#
# Usage:
#   bash betfair/setup-cert.sh [output-dir]
#
# After running:
#   1. Log in to https://myaccount.betfair.com.au/account/mysecurity
#      -> "Automated login" section -> upload client-2026.crt
#   2. Copy the BETFAIR_CERT_PEM / BETFAIR_KEY_PEM values into
#      Vercel env vars (production + preview + development).
#   3. Keep client-2026.key OUT of git. It is the private half
#      of the pair; anyone holding it can act as your login.
# ──────────────────────────────────────────────────────────────

set -euo pipefail

OUT_DIR="${1:-$(dirname "$0")/.secrets}"
mkdir -p "$OUT_DIR"

CERT_PATH="$OUT_DIR/client-2026.crt"
KEY_PATH="$OUT_DIR/client-2026.key"

if [[ -f "$CERT_PATH" || -f "$KEY_PATH" ]]; then
  echo "Refusing to overwrite existing cert/key in $OUT_DIR"
  echo "Delete them first if you really want to rotate."
  exit 1
fi

echo "→ generating self-signed cert (2048-bit RSA, 730-day validity)"
openssl req \
  -x509 \
  -newkey rsa:2048 \
  -keyout "$KEY_PATH" \
  -out "$CERT_PATH" \
  -days 730 \
  -nodes \
  -subj "/CN=equiedge-betfair-client"

chmod 600 "$KEY_PATH"
chmod 644 "$CERT_PATH"

echo
echo "Files created:"
echo "  $CERT_PATH   (upload this to Betfair)"
echo "  $KEY_PATH   (KEEP SECRET — do not commit)"
echo
echo "──────────────────────────────────────────────────────────"
echo "Vercel env var values (copy/paste — multi-line is fine):"
echo "──────────────────────────────────────────────────────────"
echo
echo "BETFAIR_CERT_PEM:"
cat "$CERT_PATH"
echo
echo "BETFAIR_KEY_PEM:"
cat "$KEY_PATH"
echo
echo "──────────────────────────────────────────────────────────"
echo "Next steps:"
echo "  1. Upload $CERT_PATH at https://myaccount.betfair.com.au/account/mysecurity"
echo "     (Betfair Account > My Security > Automated login)."
echo "  2. Wait ~1 minute for Betfair to activate the cert."
echo "  3. Paste the two PEM blobs above into Vercel env vars."
echo "  4. Redeploy, then hit GET /betfair/health to confirm loginOk=true."
echo "──────────────────────────────────────────────────────────"
