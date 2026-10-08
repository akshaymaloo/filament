#!/usr/bin/env bash
#
# package-release.sh — build a universal (arm64 + x86_64) Release build of
# Filament and package it into a .zip, a .dmg and a SHA256SUMS.txt, ready to
# attach to a GitHub release.
#
# Usage:
#   scripts/package-release.sh [output-dir]     (default: dist)
#
# Signing is controlled by environment variables:
#
#   (none)                  Ad-hoc signed ("sign to run locally"). Works for
#                           forks and local testing; Gatekeeper will warn.
#   SIGN_IDENTITY           A "Developer ID Application: … (TEAMID)" identity
#                           in the keychain. Signs with hardened runtime and a
#                           secure timestamp.
#   DEVELOPMENT_TEAM        Team ID for SIGN_IDENTITY (optional; inferred from
#                           the identity name when omitted).
#
# Notarization (only with SIGN_IDENTITY) — either:
#   NOTARY_KEYCHAIN_PROFILE a profile created with
#                           `xcrun notarytool store-credentials`, or
#   NOTARY_KEY_PATH + NOTARY_KEY_ID + NOTARY_ISSUER_ID
#                           an App Store Connect API key (.p8).
# When notarization credentials are present the app and the DMG are
# notarized and stapled, and Gatekeeper acceptance is verified.
#
# .github/workflows/release.yml runs this same script.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/dist}"
BUILD_DIR="$REPO_ROOT/.release-build"
APP_NAME="Filament.app"

if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RESET=""
fi
step() { printf "%s==>%s %s%s\n" "$BOLD$GREEN" "$RESET" "$BOLD" "$1$RESET"; }
info() { printf "    %s\n" "$1"; }
warn() { printf "%s!   %s%s\n" "$YELLOW" "$1" "$RESET" >&2; }
die()  { printf "error: %s\n" "$1" >&2; exit 1; }

SIGN_IDENTITY="${SIGN_IDENTITY:-}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
if [ -n "$SIGN_IDENTITY" ] && [ -z "$DEVELOPMENT_TEAM" ]; then
  DEVELOPMENT_TEAM="$(printf '%s' "$SIGN_IDENTITY" | sed -n 's/.*(\([A-Z0-9]\{10\}\))$/\1/p')"
fi

NOTARY_ARGS=()
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
elif [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
  [ -f "$NOTARY_KEY_PATH" ] || die "NOTARY_KEY_PATH does not exist: $NOTARY_KEY_PATH"
  NOTARY_ARGS=(--key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")
fi

if [ -z "$SIGN_IDENTITY" ]; then
  MODE="ad-hoc"
  [ ${#NOTARY_ARGS[@]} -eq 0 ] || warn "Notarization credentials ignored: ad-hoc builds can't be notarized (set SIGN_IDENTITY)."
  NOTARY_ARGS=()
elif [ ${#NOTARY_ARGS[@]} -gt 0 ]; then
  MODE="developer-id + notarized"
else
  MODE="developer-id (not notarized)"
  warn "No notarization credentials: the build will be signed but Gatekeeper will still warn."
fi

# Full Xcode (not just Command Line Tools) is needed to build app extensions.
if ! xcodebuild -version >/dev/null 2>&1; then
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
  if [ -n "$XCODE_APP" ] && [ -d "$XCODE_APP/Contents/Developer" ]; then
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
  else
    die "Full Xcode is required (Command Line Tools alone can't build app extensions)."
  fi
fi
step "Using $(xcodebuild -version | head -1) — signing: $MODE"

command -v xcodegen >/dev/null 2>&1 || die "xcodegen is required (brew install xcodegen)."

if [ -n "$SIGN_IDENTITY" ]; then
  identities="$(security find-identity -v -p codesigning)"
  case "$identities" in
    *"\"$SIGN_IDENTITY\""*) info "Found signing identity: $SIGN_IDENTITY" ;;
    *) die "Signing identity not found in keychain: $SIGN_IDENTITY" ;;
  esac
  SIGN_ARGS=(
    CODE_SIGN_STYLE=Manual
    "CODE_SIGN_IDENTITY=$SIGN_IDENTITY"
    "DEVELOPMENT_TEAM=$DEVELOPMENT_TEAM"
    ENABLE_HARDENED_RUNTIME=YES
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    "OTHER_CODE_SIGN_FLAGS=--timestamp"
  )
else
  SIGN_ARGS=(CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM=)
fi

step "Generating Xcode project"
( cd "$REPO_ROOT" && xcodegen generate )

step "Building Filament + Quick Look extensions (Release, universal)"
rm -rf "$BUILD_DIR"
xcodebuild build \
  -project "$REPO_ROOT/Filament.xcodeproj" \
  -scheme Filament \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  "${SIGN_ARGS[@]}"

APP_SRC="$BUILD_DIR/Build/Products/Release/$APP_NAME"
[ -d "$APP_SRC" ] || die "Build succeeded but $APP_NAME was not found at $APP_SRC"

PLUGINS_DIR="$APP_SRC/Contents/PlugIns"
THUMB_APPEX="$PLUGINS_DIR/ThumbnailExtension.appex"
PREVIEW_APPEX="$PLUGINS_DIR/PreviewExtension.appex"
[ -d "$THUMB_APPEX" ]   || die "ThumbnailExtension.appex not found under Contents/PlugIns"
[ -d "$PREVIEW_APPEX" ] || die "PreviewExtension.appex not found under Contents/PlugIns"

# --- verify: code signing -----------------------------------------------
step "Verifying code signature"
codesign --verify --deep --strict "$APP_SRC"
info "codesign --verify --deep --strict passed"
if [ -n "$SIGN_IDENTITY" ]; then
  for bundle in "$APP_SRC" "$THUMB_APPEX" "$PREVIEW_APPEX"; do
    details="$(codesign -dvv "$bundle" 2>&1)"
    case "$details" in *"Authority=Developer ID Application"*) ;; *) die "$(basename "$bundle") is not signed with a Developer ID Application certificate" ;; esac
    case "$details" in *"Timestamp="*) ;; *) die "$(basename "$bundle") has no secure timestamp" ;; esac
    case "$details" in *"(runtime)"*) ;; *) die "$(basename "$bundle") is missing the hardened runtime flag" ;; esac
    entitlements="$(codesign -d --entitlements - --xml "$bundle" 2>/dev/null || true)"
    case "$entitlements" in *get-task-allow*) die "$(basename "$bundle") has the get-task-allow entitlement (notarization would reject it)" ;; esac
    info "$(basename "$bundle"): Developer ID, hardened runtime, timestamped"
  done
fi

# --- verify: universal (arm64 + x86_64) binaries -------------------------
step "Verifying universal binaries"
check_universal() {
  local bin="$1" archs
  [ -f "$bin" ] || die "expected binary not found: $bin"
  archs="$(lipo -archs "$bin")"
  case "$archs" in
    *arm64*x86_64*|*x86_64*arm64*) info "$(basename "$bin"): $archs" ;;
    *) die "$bin is not universal (arm64 + x86_64): got '$archs'" ;;
  esac
}
check_universal "$APP_SRC/Contents/MacOS/Filament"
check_universal "$THUMB_APPEX/Contents/MacOS/ThumbnailExtension"
check_universal "$PREVIEW_APPEX/Contents/MacOS/PreviewExtension"

notarize() {
  local file="$1" result status submission_id
  step "Notarizing $(basename "$file") (this usually takes a few minutes)"
  result="$(xcrun notarytool submit "$file" "${NOTARY_ARGS[@]}" --wait --output-format json)" || true
  status="$(printf '%s' "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))' 2>/dev/null || true)"
  submission_id="$(printf '%s' "$result" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))' 2>/dev/null || true)"
  if [ "$status" != "Accepted" ]; then
    printf '%s\n' "$result" >&2
    if [ -n "$submission_id" ]; then
      xcrun notarytool log "$submission_id" "${NOTARY_ARGS[@]}" >&2 || true
    fi
    die "Notarization of $(basename "$file") failed (status: ${status:-unknown})"
  fi
  info "Accepted (submission $submission_id)"
}

# --- notarize + staple the app ---------------------------------------------
STAGE_DIR="$BUILD_DIR/stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$APP_SRC" "$STAGE_DIR/$APP_NAME"
APP="$STAGE_DIR/$APP_NAME"

if [ ${#NOTARY_ARGS[@]} -gt 0 ]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$BUILD_DIR/notarize-app.zip"
  notarize "$BUILD_DIR/notarize-app.zip"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  info "Gatekeeper accepts the app"
fi

# --- package --------------------------------------------------------------
step "Packaging into $OUT_DIR"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/Filament.zip" "$OUT_DIR/Filament.dmg" "$OUT_DIR/SHA256SUMS.txt"

ZIP_PATH="$OUT_DIR/Filament.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP_PATH"
info "Created $ZIP_PATH"

DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
ditto "$APP" "$DMG_STAGING/$APP_NAME"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_PATH="$OUT_DIR/Filament.dmg"
hdiutil create -volname "Filament" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
if [ -n "$SIGN_IDENTITY" ]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
fi
if [ ${#NOTARY_ARGS[@]} -gt 0 ]; then
  notarize "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
  info "Gatekeeper accepts the DMG"
fi
info "Created $DMG_PATH"

step "Writing SHA256SUMS.txt"
( cd "$OUT_DIR" && shasum -a 256 Filament.zip Filament.dmg > SHA256SUMS.txt )
cat "$OUT_DIR/SHA256SUMS.txt"

printf "\n%s%sPackaged Filament (%s) into %s%s\n" "$BOLD" "$GREEN" "$MODE" "$OUT_DIR" "$RESET"
