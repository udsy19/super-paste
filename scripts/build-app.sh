#!/bin/bash
# Builds build/Super Paste.app (release by default; `--debug` for a fast debug build; UNIVERSAL=1 for Apple silicon +
# Intel) and signs it with the project-local identity from scripts/signing-setup.sh (falls back to ad-hoc).
# The MCP stdio bridge ships inside the bundle as Contents/MacOS/super-paste-mcp.
#
# DISTRIBUTION=appstore builds the Mac App Store edition instead: compiled with APP_STORE (no updater), in its own
# scratch folder (.build-appstore), bundle id $APPSTORE_BUNDLE_ID, sandbox entitlements, ad-hoc signed into
# build/appstore/Super Paste.app for local testing. scripts/package-appstore.sh re-signs it for submission.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
CONFIG=release; [ "${1:-}" = "--debug" ] && CONFIG=debug
PRODUCTS=(SuperPaste super-paste-mcp)
DISTRIBUTION="${DISTRIBUTION:-direct}"
# The Store edition's bundle id: the one place it is defined (change it before registering in App Store Connect).
APPSTORE_BUNDLE_ID="com.udsy.superpaste.appstore"
case "$DISTRIBUTION" in
  direct)   SWIFT_FLAGS=(); OUT="$ROOT/build" ;;
  appstore) SWIFT_FLAGS=(-Xswiftc -DAPP_STORE --scratch-path "$ROOT/.build-appstore"); OUT="$ROOT/build/appstore" ;;
  *) echo "DISTRIBUTION must be direct or appstore (got: $DISTRIBUTION)" >&2; exit 64 ;;
esac
# Extra flags for one product. In the Store edition the bridge is a sandboxed tool that MCP clients launch directly,
# and the sandbox refuses to start a bare executable without a bundle identifier, so an Info.plist is linked in.
product_flags() {
  [ "$DISTRIBUTION" = appstore ] && [ "$1" = super-paste-mcp ] || return 0
  mkdir -p "$OUT"
  local plist="$OUT/super-paste-mcp-Info.plist"
  local version; version=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/Resources/Info.plist")
  /usr/bin/plutil -create xml1 "$plist"
  /usr/bin/plutil -insert CFBundleIdentifier -string "$APPSTORE_BUNDLE_ID.mcp" "$plist"
  /usr/bin/plutil -insert CFBundleName -string super-paste-mcp "$plist"
  /usr/bin/plutil -insert CFBundleShortVersionString -string "$version" "$plist"
  /usr/bin/plutil -insert CFBundleVersion -string "$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$ROOT/Resources/Info.plist")" "$plist"
  echo -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$plist"
}
if [ "${UNIVERSAL:-0}" = 1 ]; then
  # Build each architecture separately (the CLT toolchain has no multi-arch build) and merge with lipo.
  for arch in arm64 x86_64; do
    for product in "${PRODUCTS[@]}"; do
      # shellcheck disable=SC2046  # product_flags prints separate words (paths without spaces)
      swift build -c "$CONFIG" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} $(product_flags "$product") --product "$product" --triple "$arch-apple-macosx14.0"
    done
  done
  ARM="$(swift build -c "$CONFIG" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --triple arm64-apple-macosx14.0 --show-bin-path)"
  INTEL="$(swift build -c "$CONFIG" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --triple x86_64-apple-macosx14.0 --show-bin-path)"
  BIN="$OUT/universal"; mkdir -p "$BIN"; RES_BIN="$ARM"
  for product in "${PRODUCTS[@]}"; do lipo -create -output "$BIN/$product" "$ARM/$product" "$INTEL/$product"; done
else
  for product in "${PRODUCTS[@]}"; do
    # shellcheck disable=SC2046  # product_flags prints separate words (paths without spaces)
    swift build -c "$CONFIG" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} $(product_flags "$product") --product "$product"
  done
  BIN="$(swift build -c "$CONFIG" ${SWIFT_FLAGS[@]+"${SWIFT_FLAGS[@]}"} --show-bin-path)"; RES_BIN="$BIN"
fi

APP="$OUT/Super Paste.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for product in "${PRODUCTS[@]}"; do cp "$BIN/$product" "$APP/Contents/MacOS/$product"; done
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ "$DISTRIBUTION" = appstore ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $APPSTORE_BUNDLE_ID" "$APP/Contents/Info.plist"
  # The Store edition sends no Apple events (neither edition does; the direct one keeps its entitlement as is).
  /usr/libexec/PlistBuddy -c "Delete :NSAppleEventsUsageDescription" "$APP/Contents/Info.plist"
fi
# SwiftPM resource bundles of modules that declare resources (load them from Bundle.main.resourceURL, not
# Bundle.module, which traps when the bundle isn't next to the executable).
find "$RES_BIN" -maxdepth 1 -name 'SuperPaste_*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

ICONSET="$ROOT/build/AppIcon.iconset"
if [ ! -f "$ROOT/build/AppIcon.icns" ]; then
  swift "$ROOT/scripts/make-icon.swift" "$ICONSET" && iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Uploads with quarantined files are rejected; nothing in the bundle should carry the attribute anyway.
xattr -cr "$APP"

KC="$ROOT/.signing/super-paste.keychain-db"
ENT="$ROOT/Resources/SuperPaste.entitlements"
if [ "$DISTRIBUTION" = appstore ]; then
  # Ad-hoc, for local sandbox testing (the sandbox is enforced for ad-hoc signatures). Nested code first; the bridge
  # gets its own identifier, which names its sandbox container.
  codesign -f -s - -o runtime -i "$APPSTORE_BUNDLE_ID.mcp" \
    --entitlements "$ROOT/Resources/super-paste-mcp-AppStore.entitlements" "$APP/Contents/MacOS/super-paste-mcp"
  codesign -f -s - -o runtime --entitlements "$ROOT/Resources/SuperPaste-AppStore.entitlements" "$APP"
elif [ -f "$KC" ]; then
  security unlock-keychain -p superpaste "$KC"
  ORIG=()
  while IFS= read -r line; do line="${line#"${line%%[![:space:]]*}"}"; line="${line//\"/}"; [ -n "$line" ] && ORIG+=("$line"); done < <(security list-keychains -d user)
  restore() { security list-keychains -d user -s "${ORIG[@]}"; }
  trap restore EXIT
  security list-keychains -d user -s "${ORIG[@]}" "$KC"
  # Nested code first, then the bundle that seals it.
  codesign -f -s "Super Paste Local Signing" --keychain "$KC" -o runtime "$APP/Contents/MacOS/super-paste-mcp"
  codesign -f -s "Super Paste Local Signing" --keychain "$KC" -o runtime --entitlements "$ENT" "$APP"
  restore; trap - EXIT
else
  codesign -f -s - "$APP/Contents/MacOS/super-paste-mcp"
  codesign -f -s - --entitlements "$ENT" "$APP"
fi
echo "Built $APP"
