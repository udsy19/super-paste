#!/bin/bash
# Packages the Mac App Store edition.
#
#   ADHOC=1 scripts/package-appstore.sh     ad-hoc-signed, sandboxed build/appstore/Super Paste.app for local testing
#   scripts/package-appstore.sh             signed .pkg for App Store Connect, from these environment variables:
#     APPSTORE_APP_IDENTITY          "3rd Party Mac Developer Application: <Name> (<TEAMID>)" or "Apple Distribution: …"
#     APPSTORE_INSTALLER_IDENTITY    "3rd Party Mac Developer Installer: <Name> (<TEAMID>)"
#     APPSTORE_PROVISIONING_PROFILE  path to the Mac App Store provisioning profile of the Store bundle id
#
# SwiftPM build (UNIVERSAL=1 by default here) → .app (scripts/build-app.sh, DISTRIBUTION=appstore) → nested code signed
# inside-out with the Store entitlements plus the profile's application and team identifiers → productbuild → .pkg in
# dist/. Upload the .pkg with Transporter (no Xcode needed). Nothing here uploads.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
APP="$ROOT/build/appstore/Super Paste.app"

if [ "${ADHOC:-0}" = 1 ]; then
  DISTRIBUTION=appstore ./scripts/build-app.sh "$@"
  codesign --verify --strict --deep "$APP"
  echo "Ad-hoc Store build (sandboxed, not for submission): $APP"
  exit 0
fi

missing=()
[ -n "${APPSTORE_APP_IDENTITY:-}" ] || missing+=(APPSTORE_APP_IDENTITY)
[ -n "${APPSTORE_INSTALLER_IDENTITY:-}" ] || missing+=(APPSTORE_INSTALLER_IDENTITY)
[ -n "${APPSTORE_PROVISIONING_PROFILE:-}" ] || missing+=(APPSTORE_PROVISIONING_PROFILE)
if [ ${#missing[@]} -gt 0 ]; then
  echo "package-appstore.sh: missing ${missing[*]}." >&2
  echo "  Needs an Apple Distribution (or 3rd Party Mac Developer Application) identity, a 3rd Party Mac Developer" >&2
  echo "  Installer identity and a Mac App Store provisioning profile for the Store bundle id, all from the Apple" >&2
  echo "  Developer account. See docs/app-store/README.md. For a local sandboxed test build use ADHOC=1." >&2
  exit 78
fi
[ -f "$APPSTORE_PROVISIONING_PROFILE" ] || { echo "package-appstore.sh: no profile at $APPSTORE_PROVISIONING_PROFILE" >&2; exit 66; }
for identity in "$APPSTORE_APP_IDENTITY" "$APPSTORE_INSTALLER_IDENTITY"; do
  security find-identity -v | grep -qF "$identity" \
    || { echo "package-appstore.sh: identity not in the keychain: $identity" >&2; exit 67; }
done

UNIVERSAL="${UNIVERSAL:-1}" DISTRIBUTION=appstore ./scripts/build-app.sh
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/Info.plist")
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
security cms -D -i "$APPSTORE_PROVISIONING_PROFILE" > "$WORK/profile.plist"
APP_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.application-identifier" "$WORK/profile.plist")
TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :Entitlements:com.apple.developer.team-identifier" "$WORK/profile.plist")
[ "$APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] \
  || { echo "package-appstore.sh: the profile is for $APP_ID, the app is $TEAM_ID.$BUNDLE_ID" >&2; exit 65; }
cp "$APPSTORE_PROVISIONING_PROFILE" "$APP/Contents/embedded.provisionprofile"

# The Store entitlements plus the identifiers the profile grants.
cp "$ROOT/Resources/SuperPaste-AppStore.entitlements" "$WORK/app.entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $APP_ID" "$WORK/app.entitlements"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$WORK/app.entitlements"

# Nested code first, then the bundle that seals it.
codesign -f -s "$APPSTORE_APP_IDENTITY" -o runtime -i "$BUNDLE_ID.mcp" \
  --entitlements "$ROOT/Resources/super-paste-mcp-AppStore.entitlements" "$APP/Contents/MacOS/super-paste-mcp"
codesign -f -s "$APPSTORE_APP_IDENTITY" -o runtime --entitlements "$WORK/app.entitlements" "$APP"
codesign --verify --strict --deep "$APP"

mkdir -p dist
PKG="dist/SuperPaste-$VERSION-AppStore.pkg"
productbuild --component "$APP" /Applications --sign "$APPSTORE_INSTALLER_IDENTITY" "$PKG"
pkgutil --check-signature "$PKG"
echo "Created $PKG — upload it with Transporter, then check it in App Store Connect."
