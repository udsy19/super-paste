#!/bin/bash
# Super Paste installer.
#
#   Install / update:  curl -fsSL https://udsy19.github.io/super-paste/install.sh | bash
#   Uninstall:         curl -fsSL https://udsy19.github.io/super-paste/install.sh | bash -s -- --uninstall
#
# Downloads the latest release from GitHub, installs it into /Applications (or ~/Applications when /Applications
# isn't writable) and opens it. Nothing else on your system is changed.
# Options (environment): SUPERPASTE_INSTALL_DIR=<folder> to install elsewhere, SUPERPASTE_NO_OPEN=1 to skip launching.
set -euo pipefail

REPO="udsy19/super-paste"
APP="Super Paste.app"
DMG_URL="https://github.com/$REPO/releases/latest/download/SuperPaste.dmg"

bold=$'\033[1m'; dim=$'\033[2m'; green=$'\033[32m'; red=$'\033[31m'; reset=$'\033[0m'
say()  { printf '%s\n' "$*"; }
step() { printf '%s→%s %s\n' "$bold" "$reset" "$*"; }
fail() { printf '%s✗ %s%s\n' "$red" "$*" "$reset" >&2; exit 1; }

# Asks a running copy to quit and waits up to five seconds for it.
quit_running() {
  pgrep -x SuperPaste >/dev/null 2>&1 || return 0
  step "Quitting the running copy of Super Paste"
  osascript -e 'tell application id "com.udsy.superpaste" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x SuperPaste >/dev/null 2>&1 || return 0; sleep 0.5; done
  fail "Super Paste is still running. Quit it from its menu bar icon and run the installer again."
}

# Every installed copy, one path per line.
installed_paths() {
  for dir in "/Applications" "$HOME/Applications"; do
    [ -d "$dir/$APP" ] && printf '%s\n' "$dir/$APP"
  done
  return 0
}

[ "$(uname -s)" = "Darwin" ] || fail "Super Paste runs on macOS only."

if [ "${1:-}" = "--uninstall" ]; then
  paths="$(installed_paths)"
  [ -n "$paths" ] || fail "Super Paste isn't installed."
  quit_running
  while IFS= read -r path; do
    step "Removing $path"
    rm -rf "$path"
  done <<< "$paths"
  say "${green}✓ Super Paste was uninstalled.${reset}"
  say "${dim}Your clipboard history and settings were kept in ~/Library/Application Support/Super Paste and${reset}"
  say "${dim}~/Library/Preferences/com.udsy.superpaste.plist — delete them to remove everything.${reset}"
  exit 0
fi

major="$(sw_vers -productVersion | cut -d. -f1)"
[ "$major" -ge 14 ] || fail "Super Paste needs macOS 14 Sonoma or later (you have $(sw_vers -productVersion))."

say "${bold}Installing Super Paste${reset} ${dim}— a clipboard manager for your Mac${reset}"
tmp="$(mktemp -d -t superpaste-install)"
mnt="$tmp/mount"
cleanup() { hdiutil detach "$mnt" -quiet >/dev/null 2>&1 || true; rm -rf "$tmp"; }
trap cleanup EXIT

step "Downloading the latest release"
curl -fL --progress-bar -o "$tmp/SuperPaste.dmg" "$DMG_URL" || fail "Download failed — check your connection and try again."

step "Verifying the disk image"
hdiutil verify "$tmp/SuperPaste.dmg" -quiet || fail "The download is damaged. Please try again."
mkdir -p "$mnt"
hdiutil attach "$tmp/SuperPaste.dmg" -nobrowse -readonly -mountpoint "$mnt" -quiet || fail "Couldn't open the disk image."
[ -d "$mnt/$APP" ] || fail "The disk image doesn't contain $APP."

dest="${SUPERPASTE_INSTALL_DIR:-/Applications}"
mkdir -p "$dest" 2>/dev/null || true
if [ ! -w "$dest" ]; then
  dest="$HOME/Applications"; mkdir -p "$dest"
fi

[ "${SUPERPASTE_NO_OPEN:-0}" = 1 ] || quit_running
step "Installing to $dest"
rm -rf "$dest/$APP"
ditto "$mnt/$APP" "$dest/$APP"
# Downloads made with curl aren't quarantined; clear the flag anyway in case the image was cached by a browser.
xattr -dr com.apple.quarantine "$dest/$APP" 2>/dev/null || true

version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$dest/$APP/Contents/Info.plist" 2>/dev/null || echo "")"
if [ "${SUPERPASTE_NO_OPEN:-0}" = 1 ]; then
  say "${green}✓ Super Paste ${version} is installed in $dest.${reset}"
else
  say "${green}✓ Super Paste ${version} is installed.${reset} Opening it now — look for the icon in your menu bar."
  open "$dest/$APP"
fi
