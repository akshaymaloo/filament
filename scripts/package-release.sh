#!/usr/bin/env bash
#
# package-release.sh — build a universal (arm64 + x86_64), ad-hoc-signed
# Release build of Filament and package it into dist/ as a .zip, a .dmg, and
# a SHA256SUMS.txt, ready to attach to a GitHub release.
#
# Usage:
#   scripts/package-release.sh [output-dir]     (default: dist)
#
# This is the same logic .github/workflows/release.yml runs in CI; run it
# locally to test packaging before tagging a release. No Apple Developer
# account is used or required — the build is ad-hoc signed to run locally,
# same as install.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${1:-$REPO_ROOT/dist}"
BUILD_DIR="$REPO_ROOT/.release-build"
APP_NAME="Filament.app"

if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; RESET=""
fi
step() { printf "%s==>%s %s%s\n" "$BOLD$GREEN" "$RESET" "$BOLD" "$1$RESET"; }
info() { printf "    %s\n" "$1"; }
die()  { printf "error: %s\n" "$1" >&2; exit 1; }

# Full Xcode (not just Command Line Tools) is needed to build app extensions.
if ! xcodebuild -version >/dev/null 2>&1; then
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
  if [ -n "$XCODE_APP" ] && [ -d "$XCODE_APP/Contents/Developer" ]; then
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
  else
    die "Full Xcode is required (Command Line Tools alone can't build app extensions)."
  fi
fi
step "Using $(xcodebuild -version | head -1)"

command -v xcodegen >/dev/null 2>&1 || die "xcodegen is required (brew install xcodegen)."

step "Generating Xcode project"
( cd "$REPO_ROOT" && xcodegen generate )

step "Building Filament + Quick Look extensions (Release, universal, ad-hoc)"
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
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=

APP_SRC="$BUILD_DIR/Build/Products/Release/$APP_NAME"
[ -d "$APP_SRC" ] || die "Build succeeded but $APP_NAME was not found at $APP_SRC"

# --- verify: code signing -----------------------------------------------
step "Verifying code signature"
codesign --verify --deep --strict "$APP_SRC"
info "codesign --verify --deep --strict passed"

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

PLUGINS_DIR="$APP_SRC/Contents/PlugIns"
THUMB_APPEX="$PLUGINS_DIR/ThumbnailExtension.appex"
PREVIEW_APPEX="$PLUGINS_DIR/PreviewExtension.appex"
[ -d "$THUMB_APPEX" ]   || die "ThumbnailExtension.appex not found under Contents/PlugIns"
[ -d "$PREVIEW_APPEX" ] || die "PreviewExtension.appex not found under Contents/PlugIns"
check_universal "$THUMB_APPEX/Contents/MacOS/ThumbnailExtension"
check_universal "$PREVIEW_APPEX/Contents/MacOS/PreviewExtension"

# --- package --------------------------------------------------------------
step "Packaging into $OUT_DIR"
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/Filament.zip" "$OUT_DIR/Filament.dmg" "$OUT_DIR/SHA256SUMS.txt"

ZIP_PATH="$OUT_DIR/Filament.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_SRC" "$ZIP_PATH"
info "Created $ZIP_PATH"

DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
ditto "$APP_SRC" "$DMG_STAGING/$APP_NAME"
ln -s /Applications "$DMG_STAGING/Applications"

DMG_PATH="$OUT_DIR/Filament.dmg"
rm -f "$DMG_PATH"
hdiutil create -volname "Filament" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
info "Created $DMG_PATH"

step "Writing SHA256SUMS.txt"
( cd "$OUT_DIR" && shasum -a 256 Filament.zip Filament.dmg > SHA256SUMS.txt )
cat "$OUT_DIR/SHA256SUMS.txt"

printf "\n%s%sPackaged Filament into %s%s\n" "$BOLD" "$GREEN" "$OUT_DIR" "$RESET"
