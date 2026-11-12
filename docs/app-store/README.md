# Super Paste — Mac App Store edition

**Status: CODE COMPLETE / CREDENTIALS REQUIRED** (branch `release/macos-app-store`). The sandboxed Store build
compiles, passes the self-tests and was exercised as an ad-hoc-signed sandboxed app on macOS 26.5.1. It has never
been signed with a distribution identity, validated or uploaded: this Mac has no Apple certificates or profiles.
The strip, shortcuts, hot corner, pickers and granted-permission paths still need a human run; observations made
earlier with synthetic input are not counted (see `test-results.md`).

One codebase, two editions:

| | Direct (unchanged) | Mac App Store |
|---|---|---|
| Build flag | none | `-Xswiftc -DAPP_STORE` |
| Bundle id | `com.udsy.superpaste` | `com.udsy.superpaste.appstore` (one variable: `APPSTORE_BUNDLE_ID` in `scripts/build-app.sh`) |
| Sandbox | no | yes (`Resources/SuperPaste-AppStore.entitlements`) |
| Updates | UpdateKit (GitHub Releases) | App Store; UpdateKit compiled out |
| Direct paste default | on (Accessibility) | off (To clipboard); opt-in uses post-event access |
| Data | `~/Library/Application Support/Super Paste` | the container; About › Import copies the direct edition's history |

## Commands

```bash
swift build && .build/debug/SuperPasteSelfTest                       # direct edition, all self-tests
swift build -Xswiftc -DAPP_STORE --scratch-path .build-appstore \
  && .build-appstore/debug/SuperPasteSelfTest                        # Store edition self-tests
ADHOC=1 scripts/package-appstore.sh                                  # sandboxed ad-hoc build/appstore/Super Paste.app
DISTRIBUTION=appstore scripts/build-app.sh                           # same, without the verify step
APPSTORE_APP_IDENTITY="Apple Distribution: … (TEAMID)" \
APPSTORE_INSTALLER_IDENTITY="3rd Party Mac Developer Installer: … (TEAMID)" \
APPSTORE_PROVISIONING_PROFILE=/path/SuperPaste_AppStore.provisionprofile \
  scripts/package-appstore.sh                                        # dist/SuperPaste-<ver>-AppStore.pkg (universal)
```

Without the three variables `package-appstore.sh` exits 78 naming the missing ones. Upload the `.pkg` with
Transporter (no Xcode on this Mac). `scripts/build-app.sh` with no `DISTRIBUTION` builds the direct edition exactly as
before; `release.sh`/`make-dmg.sh` are untouched.

There are no models or downloaded assets (`model-and-asset-strategy.md` is not applicable).

Documents: `compliance-matrix.md`, `architecture.md`, `entitlements.md`, `privacy-and-permissions.md`,
`dependency-and-license-audit.md`, `test-results.md`, `app-store-connect.md`, `review-notes.md`, `known-blockers.md`,
`inventory.json`.
