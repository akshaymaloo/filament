#!/usr/bin/env bash
#
# set-release-secrets.sh — store the Developer ID certificate and the App Store
# Connect API key as GitHub Actions secrets, so release.yml can sign and
# notarize. Run once (and again when the certificate or key changes).
#
# Usage:
#   scripts/set-release-secrets.sh <DeveloperID.p12> <AuthKey_XXXXXXXXXX.p8> <issuer-id>
#
# The .p12 password is prompted for (not echoed). The API key ID is taken from
# the .p8 file name. Values are piped straight to `gh secret set`; nothing is
# written to disk or printed. Requires the GitHub CLI with access to the repo.

set -euo pipefail

[ $# -eq 3 ] || { sed -n '3,12p' "$0" >&2; exit 2; }
P12="$1"; P8="$2"; ISSUER_ID="$3"
REPO="${REPO:-akshaymaloo/filament}"

[ -f "$P12" ] || { echo "error: $P12 not found" >&2; exit 1; }
[ -f "$P8" ]  || { echo "error: $P8 not found" >&2; exit 1; }
KEY_ID="$(basename "$P8" | sed -n 's/^AuthKey_\([A-Z0-9]*\)\.p8$/\1/p')"
[ -n "$KEY_ID" ] || { echo "error: expected the key file to be named AuthKey_<KEYID>.p8" >&2; exit 1; }
command -v gh >/dev/null 2>&1 || { echo "error: GitHub CLI (gh) is required" >&2; exit 1; }

read -r -s -p "Password for $(basename "$P12"): " P12_PASSWORD; echo
identity="$(openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys -legacy 2>/dev/null \
  || openssl pkcs12 -in "$P12" -passin "pass:$P12_PASSWORD" -nokeys 2>/dev/null || true)"
case "$identity" in
  *"Developer ID Application"*) echo "Certificate: Developer ID Application ✓" ;;
  "") echo "error: could not open $P12 (wrong password?)" >&2; exit 1 ;;
  *) echo "error: $P12 is not a Developer ID Application certificate" >&2; exit 1 ;;
esac

base64 -i "$P12" | gh secret set MACOS_CERTIFICATE_P12_BASE64 -R "$REPO"
printf '%s' "$P12_PASSWORD" | gh secret set MACOS_CERTIFICATE_PASSWORD -R "$REPO"
base64 -i "$P8" | gh secret set NOTARY_KEY_P8_BASE64 -R "$REPO"
printf '%s' "$KEY_ID" | gh secret set NOTARY_KEY_ID -R "$REPO"
printf '%s' "$ISSUER_ID" | gh secret set NOTARY_ISSUER_ID -R "$REPO"
echo "Stored 5 secrets in $REPO. Push a vX.Y.Z tag to build a signed, notarized release."
