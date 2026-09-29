#!/usr/bin/env bash
#
# install-release.sh — download and install a prebuilt Filament.app release
# from GitHub, without needing Xcode or a source checkout.
#
# Usage (recommended):
#   curl -fsSL https://raw.githubusercontent.com/akshaymaloo/filament/main/scripts/install-release.sh | bash
#
# Optional arguments (pass with `bash -s --`, e.g. via
#   curl -fsSL .../install-release.sh | bash -s -- --prefer-filament-stl
# ):
#   --version X.Y.Z        Install a specific release instead of latest.
#   --uninstall             Remove Filament and reset Quick Look.
#   --prefer-filament-stl   Use Filament (not Apple's Hydra) for STL/OBJ/PLY.
#   --restore-apple-stl     Undo --prefer-filament-stl.
#
# Everything below is wrapped in a `main` function invoked at the very end so
# that a truncated download (e.g. a network failure mid-`curl | bash`) can
# never execute a partial script.

set -euo pipefail

main() {
  local INSTALL_DIR="$HOME/Applications"
  local APP_NAME="Filament.app"
  local LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  # Overridable for local testing (e.g. against a `python3 -m http.server`);
  # end users never need to set this.
  local BASE_URL="${FILAMENT_RELEASE_BASE_URL:-https://github.com/akshaymaloo/filament/releases}"

  if [ -t 1 ]; then
    BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  else
    BOLD=""; GREEN=""; YELLOW=""; RED=""; DIM=""; RESET=""
  fi
  step()  { printf "%s==>%s %s%s\n" "$BOLD$GREEN" "$RESET" "$BOLD" "$1$RESET"; }
  info()  { printf "    %s\n" "$1"; }
  warn()  { printf "%s!  %s%s\n" "$YELLOW" "$1" "$RESET"; }
  die()   { printf "%serror:%s %s\n" "$RED$BOLD" "$RESET" "$1" >&2; exit 1; }

  # --- Apple's built-in 3D Quick Look (Hydra) — mirrors install.sh ---------
  local HYDRA_ID="com.apple.HydraQLPreviewExtension"
  plugin_list() { pluginkit "$@" 2>/dev/null || true; }
  hydra_present() { [ -n "$(plugin_list -mA -i "$HYDRA_ID")" ]; }
  hydra_ignored() {
    local state
    state="$(plugin_list -mAv -i "$HYDRA_ID")"
    [[ "$state" =~ ^[[:space:]]*- ]]
  }
  prefer_filament_stl() {
    if ! hydra_present; then
      info "Apple's Hydra 3D preview isn't present on this macOS — nothing to change."
      return 0
    fi
    pluginkit -e ignore -i "$HYDRA_ID" || { warn "pluginkit could not disable $HYDRA_ID"; return 0; }
    qlmanage -r >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true
    info "Disabled $HYDRA_ID for this user; Filament now previews STL/OBJ/PLY."
    info "Undo any time with: --restore-apple-stl"
  }
  restore_apple_stl() {
    if hydra_present && hydra_ignored; then
      pluginkit -e default -i "$HYDRA_ID" || true
      qlmanage -r >/dev/null 2>&1 || true
      qlmanage -r cache >/dev/null 2>&1 || true
      info "Re-enabled Apple's $HYDRA_ID."
    fi
  }

  # --- option parsing --------------------------------------------------------
  local MODE=install
  local VERSION=""
  local PREFER_FILAMENT_STL=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --version)
        [ $# -ge 2 ] || die "--version requires an argument, e.g. --version 0.3.0"
        VERSION="$2"; shift 2 ;;
      --uninstall) MODE=uninstall; shift ;;
      --prefer-filament-stl) PREFER_FILAMENT_STL=1; shift ;;
      --restore-apple-stl) MODE=restore-stl; shift ;;
      *) die "unknown option: $1 (use --version X.Y.Z, --uninstall, --prefer-filament-stl, or --restore-apple-stl)" ;;
    esac
  done

  # --- uninstall ---------------------------------------------------------
  if [ "$MODE" = "uninstall" ]; then
    step "Uninstalling Filament"
    osascript -e 'tell application "Filament" to quit' >/dev/null 2>&1 || true
    restore_apple_stl
    local copy
    for copy in "$INSTALL_DIR/$APP_NAME" "/Applications/$APP_NAME"; do
      [ -e "$copy" ] || continue
      "$LSREGISTER" -u "$copy" >/dev/null 2>&1 || true
      if rm -rf "$copy" 2>/dev/null; then
        info "Removed $copy"
      else
        warn "Could not remove $copy — drag it to the Trash in Finder."
      fi
    done
    qlmanage -r >/dev/null 2>&1 || true
    qlmanage -r cache >/dev/null 2>&1 || true
    info "Quick Look reset."
    return 0
  fi

  if [ "$MODE" = "restore-stl" ]; then
    step "Restoring Apple's built-in STL/OBJ/PLY Quick Look"
    if hydra_present && hydra_ignored; then
      restore_apple_stl
    else
      info "Apple's Hydra preview is already enabled — nothing to change."
    fi
    return 0
  fi

  # --- 1. prerequisites --------------------------------------------------
  step "Checking prerequisites"
  [ "$(uname -s)" = "Darwin" ] || die "Filament only runs on macOS."
  local os_major
  os_major="$(sw_vers -productVersion | cut -d. -f1)"
  [ "$os_major" -ge 14 ] || die "macOS 14 (Sonoma) or later is required (found $(sw_vers -productVersion))."
  info "macOS $(sw_vers -productVersion)"

  # --- 2. download ---------------------------------------------------------
  local download_url
  if [ -n "$VERSION" ]; then
    download_url="$BASE_URL/download/v$VERSION"
    step "Downloading Filament $VERSION"
  else
    download_url="$BASE_URL/latest/download"
    step "Downloading the latest Filament release"
  fi

  # Not `local`: the EXIT trap fires after main() returns, when a local
  # variable's scope would already be gone, which trips `set -u` below.
  TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/filament-install.XXXXXX")"
  trap 'rm -rf "$TMP_DIR"' EXIT

  curl -fL --progress-bar -o "$TMP_DIR/Filament.zip" "$download_url/Filament.zip" \
    || die "Could not download Filament.zip from $download_url — check your connection or --version."
  curl -fL --progress-bar -o "$TMP_DIR/SHA256SUMS.txt" "$download_url/SHA256SUMS.txt" \
    || die "Could not download SHA256SUMS.txt from $download_url."

  step "Verifying checksum"
  local expected actual
  expected="$(grep 'Filament\.zip$' "$TMP_DIR/SHA256SUMS.txt" | awk '{print $1}')"
  [ -n "$expected" ] || die "SHA256SUMS.txt did not contain an entry for Filament.zip"
  actual="$(shasum -a 256 "$TMP_DIR/Filament.zip" | awk '{print $1}')"
  if [ "$expected" != "$actual" ]; then
    die "Checksum mismatch for Filament.zip (expected $expected, got $actual) — download may be corrupt or tampered with."
  fi
  info "Checksum OK ($actual)"

  step "Extracting"
  ditto -x -k "$TMP_DIR/Filament.zip" "$TMP_DIR"
  [ -d "$TMP_DIR/$APP_NAME" ] || die "Filament.zip did not contain $APP_NAME"

  # --- 3. install ----------------------------------------------------------
  step "Installing to $INSTALL_DIR"
  mkdir -p "$INSTALL_DIR"
  osascript -e 'tell application "Filament" to quit' >/dev/null 2>&1 || true
  rm -rf "$INSTALL_DIR/$APP_NAME"
  ditto "$TMP_DIR/$APP_NAME" "$INSTALL_DIR/$APP_NAME"
  # Downloaded files carry a quarantine flag; the app is ad-hoc signed (not
  # notarized), so remove it ourselves after the user has chosen to install.
  xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true
  info "Installed $INSTALL_DIR/$APP_NAME"
  if [ -d "/Applications/$APP_NAME" ]; then
    # Two copies register competing Quick Look extensions; macOS may pick either.
    warn "Another copy exists at /Applications/$APP_NAME (e.g. from the DMG)."
    warn "Delete one of them so Finder uses a single version."
  fi

  # --- 4. register + reset Quick Look ---------------------------------------
  step "Registering the app and its Quick Look extensions"
  # Unregister any stale Filament copies (e.g. a previous build-from-source at
  # a different path) so they don't shadow the freshly installed app, then
  # register only the installed copy — same approach as install.sh.
  while IFS= read -r stale; do
    [ -n "$stale" ] || continue
    case "$stale" in
      "$INSTALL_DIR/$APP_NAME") ;;   # keep the installed copy
      *) [ -e "$stale" ] || "$LSREGISTER" -u "$stale" >/dev/null 2>&1 || true ;;
    esac
  done < <("$LSREGISTER" -dump 2>/dev/null \
            | sed -n 's/^[[:space:]]*path:[[:space:]]*\(.*Filament\.app\) (0x.*/\1/p' \
            | sort -u)

  "$LSREGISTER" -f "$INSTALL_DIR/$APP_NAME" >/dev/null 2>&1 || true
  # Launching the app once is what makes macOS load its embedded extensions.
  open "$INSTALL_DIR/$APP_NAME"
  sleep 3
  qlmanage -r >/dev/null 2>&1 || true
  qlmanage -r cache >/dev/null 2>&1 || true

  # --- 5. verify -------------------------------------------------------------
  step "Verifying"
  local registered="" filament_plugins=""
  for _ in 1 2 3 4 5 6 7 8; do
    filament_plugins="$(plugin_list -m | grep -i "filament" || true)"
    if [ -n "$filament_plugins" ]; then registered=1; break; fi
    sleep 2
  done
  if [ -n "$registered" ]; then
    info "Quick Look extensions are registered:"
    printf '%s\n' "$filament_plugins" | sed 's/^/      /'
  else
    warn "Extensions not listed yet — they may take a moment. Try re-running, or log out/in once."
  fi

  # --- 6. optionally take over STL/OBJ/PLY previews from Apple ---------------
  if [ "$PREFER_FILAMENT_STL" = "1" ]; then
    step "Using Filament for STL/OBJ/PLY Quick Look"
    prefer_filament_stl
  fi

  printf "\n%s%sFilament is installed.%s\n" "$BOLD" "$GREEN" "$RESET"
  if [ "$PREFER_FILAMENT_STL" != "1" ] && hydra_present && ! hydra_ignored; then
    info "Note: Apple's built-in preview handles STL/OBJ/PLY on this macOS."
    info "To use Filament for those too, re-run with --prefer-filament-stl."
  fi
  cat <<EOF
${DIM}
  • Select a .3mf, .stl, .obj, or .ply file in Finder and press Space for the preview.
  • Double-click a file (or open the Filament app) to view it in a window.
  • If Space-bar previews don't appear immediately, log out/in once so Finder
    reloads the Quick Look extensions.
  • To make Filament the default app: select a file in Finder, ⌘I (Get Info),
    "Open with" > Filament > Change All.
  • To remove: curl -fsSL https://raw.githubusercontent.com/akshaymaloo/filament/main/scripts/install-release.sh | bash -s -- --uninstall${RESET}
EOF
}

main "$@"
