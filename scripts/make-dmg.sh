#!/bin/bash
# Produces dist/SuperPaste-<version>.dmg: universal (Apple silicon + Intel) app, drag-to-Applications layout,
# and install notes for Gatekeeper (the app is self-signed, not notarized).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

UNIVERSAL=1 ./scripts/build-app.sh

STAGE="$ROOT/build/dmg"; rm -rf "$STAGE"; mkdir -p "$STAGE"
cp -R "build/Super Paste.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/Install Super Paste.txt" <<TXT
Installing Super Paste $VERSION
=============================

1. Drag Super Paste into the Applications folder.
2. Open Super Paste from Applications. macOS will say it "cannot be opened" because the app
   is not notarized by Apple. Click Done.
3. Open System Settings → Privacy & Security, scroll down and click "Open Anyway" next to
   the Super Paste message, then confirm with your password.
   (Alternatively, in Terminal: xattr -dr com.apple.quarantine "/Applications/Super Paste.app")
4. Super Paste lives in the menu bar. Press Shift-Command-V anywhere to open your clipboard history.

Requirements: macOS 14 Sonoma or later, Apple silicon or Intel.
TXT

mkdir -p dist
DMG="dist/SuperPaste-$VERSION.dmg"; rm -f "$DMG"
hdiutil create -volname "Super Paste $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null && echo "Created $DMG ($(du -h "$DMG" | cut -f1))"
