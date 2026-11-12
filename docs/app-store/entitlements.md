# Entitlements

## App — `Resources/SuperPaste-AppStore.entitlements`

| Key | Why | Evidence |
|---|---|---|
| `com.apple.security.app-sandbox` | required | container `~/Library/Containers/com.udsy.superpaste.appstore` created at launch |
| `com.apple.security.network.client` | link previews (LinkPresentation) of copied links; Settings › Privacy can turn them off | `https://example.com/` captured with title "Example Domain" in the sandboxed build |
| `com.apple.security.network.server` | local MCP server, `127.0.0.1` only, off by default | `lsof`: `TCP 127.0.0.1:39725 (LISTEN)` from the sandboxed app |
| `com.apple.security.files.user-selected.read-write` | sync folder, sync key export/import, Ignore Applications picker, Import from the direct edition | open panels; the picker paths need a human run |
| `com.apple.security.files.bookmarks.app-scope` | security-scoped bookmarks: the sync folder and copied files | `SyncKit.folderBookmark` self-test; copied-file paste after relaunch (test-results §5) |

Not present, deliberately: `automation.apple-events` (neither edition sends Apple events; the direct edition's
entitlement is vestigial and left as is), `inherit` (no child processes), any `temporary-exception`,
`disable-library-validation`, `allow-unsigned-executable-memory`. `package-appstore.sh` adds
`com.apple.application-identifier` and `com.apple.developer.team-identifier` from the provisioning profile.

## Stdio bridge — `Resources/super-paste-mcp-AppStore.entitlements`

`app-sandbox` + `network.client`, signing identifier `com.udsy.superpaste.appstore.mcp`. MCP clients (Claude
Desktop, editors) launch it themselves, so `inherit` would crash it (it is not a child of the sandboxed app). It
carries an embedded `__TEXT,__info_plist` (bundle id, version): without one a sandboxed bare executable traps in
`_libsecinit_appsandbox` (exit 133) — reproduced and fixed, see test-results §4. It talks to the app only over
`http://127.0.0.1:<port>/mcp` with a bearer token; it shares no files with the app (no app group needed).

## Direct edition

Unchanged: `Resources/SuperPaste.entitlements` (apple-events), signed with the project-local identity and hardened
runtime by `build-app.sh`. Developer ID signing and notarization of the direct edition are not part of this branch
(no Developer ID certificate on this Mac; owner decision in `known-blockers.md`).
