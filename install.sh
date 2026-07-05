#!/usr/bin/env bash
#
# install.sh — build, install, and register Filament (a macOS Quick Look app
# for 3MF/STL/OBJ/PLY files) on this Mac.
#
# Usage:
#   ./install.sh                 Build (signed to run locally) and install
#   DEVELOPMENT_TEAM=ABCDE12345 ./install.sh
#                                Build with your Apple Developer Team instead
#   ./install.sh --uninstall     Remove the installed app and reset Quick Look
#
# No Apple Developer account is required for local use: by default the app is
# ad-hoc "signed to run locally", which is enough for macOS to load its Quick
# Look extensions on this machine.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
BUILD_DIR="$REPO_ROOT/build"
APP_NAME="Filament.app"
INSTALL_DIR="$HOME/Applications"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

# --- pretty output -----------------------------------------------------------
if [ -t 1 ]; then
  BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BOLD=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
fi
step()  { printf "%s==>%s %s%s\n" "$BOLD$GREEN" "$RESET" "$BOLD" "$1$RESET"; }
info()  { printf "    %s\n" "$1"; }
warn()  { printf "%s!  %s%s\n" "$YELLOW" "$1" "$RESET"; }
die()   { printf "%serror:%s %s\n" "$RED$BOLD" "$RESET" "$1" >&2; exit 1; }

# --- uninstall ---------------------------------------------------------------
if [ "${1:-}" = "--uninstall" ]; then
  step "Uninstalling Filament"
  osascript -e 'tell application "Filament" to quit' >/dev/null 2>&1 || true
  rm -rf "$INSTALL_DIR/$APP_NAME"
  "$LSREGISTER" -u "$INSTALL_DIR/$APP_NAME" >/dev/null 2>&1 || true
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true
  info "Removed $INSTALL_DIR/$APP_NAME and reset Quick Look."
  exit 0
fi

# --- 1. prerequisites --------------------------------------------------------
step "Checking prerequisites"

[ "$(uname -s)" = "Darwin" ] || die "Filament only runs on macOS."

os_major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$os_major" -ge 14 ] || die "macOS 14 (Sonoma) or later is required (found $(sw_vers -productVersion))."
info "macOS $(sw_vers -productVersion)"

# Full Xcode (not just Command Line Tools) is needed to build app extensions.
if ! /usr/bin/xcrun --find xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -1 || true)"
  if [ -n "$XCODE_APP" ] && [ -d "$XCODE_APP/Contents/Developer" ]; then
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    info "Using Xcode at $XCODE_APP"
  else
    die "Full Xcode is required (Command Line Tools alone can't build app extensions).
       Install Xcode from the App Store, then run:
         sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  fi
fi
info "$(xcodebuild -version | head -1)"

# XcodeGen generates the .xcodeproj from project.yml.
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    step "Installing XcodeGen (via Homebrew)"
    brew install xcodegen
  else
    die "XcodeGen is required but not installed, and Homebrew was not found.
       Install Homebrew from https://brew.sh and re-run, or install XcodeGen manually:
       https://github.com/yonaskolb/XcodeGen"
  fi
fi

# --- 2. generate the Xcode project ------------------------------------------
step "Generating Xcode project"
( cd "$REPO_ROOT" && xcodegen generate )

# --- 3. build ----------------------------------------------------------------
step "Building Filament + Quick Look extensions (Release)"
SIGN_ARGS=(CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES)
if [ -n "${DEVELOPMENT_TEAM:-}" ]; then
  info "Signing with Development Team ${DEVELOPMENT_TEAM}"
  SIGN_ARGS+=(CODE_SIGN_STYLE=Automatic "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM}")
else
  info "Signing to run locally (ad-hoc). Set DEVELOPMENT_TEAM=... to use your Apple team."
  SIGN_ARGS+=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
fi

xcodebuild build \
  -project "$REPO_ROOT/Filament.xcodeproj" \
  -scheme Filament \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  "${SIGN_ARGS[@]}"

APP_SRC="$BUILD_DIR/Build/Products/Release/$APP_NAME"
[ -d "$APP_SRC" ] || die "Build succeeded but $APP_NAME was not found at $APP_SRC"

# --- 4. install --------------------------------------------------------------
step "Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
osascript -e 'tell application "Filament" to quit' >/dev/null 2>&1 || true
rm -rf "$INSTALL_DIR/$APP_NAME"
cp -R "$APP_SRC" "$INSTALL_DIR/"
info "Installed $INSTALL_DIR/$APP_NAME"

# --- 5. register + reset Quick Look -----------------------------------------
step "Registering the app and its Quick Look extensions"
"$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME" >/dev/null 2>&1 || true
# Launching the app once is what makes macOS load its embedded extensions.
open "$INSTALL_DIR/$APP_NAME"
sleep 3
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

# --- 6. verify ---------------------------------------------------------------
step "Verifying"
registered=""
for _ in 1 2 3 4 5 6 7 8; do
  if pluginkit -m 2>/dev/null | grep -qi "filament"; then registered=1; break; fi
  sleep 2
done
if [ -n "$registered" ]; then
  info "Quick Look extensions are registered:"
  pluginkit -m 2>/dev/null | grep -i "filament" | sed 's/^/      /'
else
  warn "Extensions not listed yet — they may take a moment. Try re-running, or log out/in once."
fi

printf "\n%s%sFilament is installed.%s\n" "$BOLD" "$GREEN" "$RESET"
cat <<EOF
${DIM}
  • Select a .3mf, .stl, .obj, or .ply file in Finder and press Space for the preview.
  • Double-click a file (or open the Filament app) to view it in a window.
  • If Space-bar previews don't appear immediately, log out/in once so Finder
    reloads the Quick Look extensions.
  • To remove: ./install.sh --uninstall${RESET}
EOF
