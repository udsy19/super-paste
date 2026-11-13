# Architecture of the Store edition

Everything is the existing SwiftPM package (`docs/ARCHITECTURE.md`); `APP_STORE` switches a handful of places.
No Xcode project, no new targets, no new dependencies.

| Area | Direct | Store (`#if APP_STORE`) | Where |
|---|---|---|---|
| Build | `.build`, `build/Super Paste.app` | `.build-appstore`, `build/appstore/Super Paste.app`, bundle id rewritten in the copied Info.plist, `NSAppleEventsUsageDescription` removed | `scripts/build-app.sh` |
| Updater | UpdateKit installed and started | every UpdateKit file is wrapped in `#if !APP_STORE`; the module links empty; no update UI | `Sources/UpdateKit/*`, `Sources/SuperPaste/main.swift`, `AboutPane` |
| Direct paste permission | `AXIsProcessTrusted[WithOptions]` | `CGPreflightPostEventAccess` / `CGRequestPostEventAccess` (only posting ⌘V is needed) | `Permissions` in `SuperPasteCore/System.swift` |
| Direct paste default | on | off (To clipboard); copy-only works with no permission | `Settings.swift` |
| Sync folder | path in Defaults | path + security-scoped bookmark (`syncFolderBookmark`), resolved and accessed on first use each launch | `SyncKit/SyncState.swift` |
| iCloud Drive default folder | `homeDirectoryForCurrentUser` | real home from `getpwuid` (`SuperPastePaths.userHome`) — used by both editions | `SuperPasteCore/Services.swift` |
| Copied files | paths only | `SandboxFileAccess`: a bookmark per captured path (last 2,000) in `File Access.plist`, pruned when items are deleted/erased/pruned, written off the main thread; access resumed before paste/open/preview/share and held for the 64 most recently used | `SuperPasteCore/SandboxFileAccess.swift` |
| Dock hot-corner conflict check | reads `com.apple.dock` | skipped (sandbox denies the read) | `HotCornerPolicy.systemAction` |
| Data import | — | About › Import from Super Paste (direct download) | `DirectEditionImport` (Core), `DirectEditionImporter` (SettingsKit) |
| MCP stdio bridge | plain executable | own sandbox + network.client + embedded Info.plist | `build-app.sh` `product_flags` |

## Import from the direct edition

User-initiated, non-destructive. About › Import… → confirmation → `NSOpenPanel` pre-pointed at
`~/Library/Application Support/Super Paste` (the panel is what grants the sandbox read access) → `clips.sqlite`,
`-wal`, `-shm` and `Blobs/` are **copied** (a history containing symbolic links is refused) into
`<container>/Application Support/Super Paste Import/` with a completion marker → the user quits and reopens →
before the store opens, the current Store history, its `Sync/` state and `File Access.plist` move to
`Backup/Before import <date>/` and the staged copy moves in. The swap is renames with `.applying`/`.moved-out`
markers, so a relaunch finishes an interrupted one; sync starts over with the imported history. The direct edition's files are only read. MCP clients
and sync state are not imported; preferences are not imported (each edition keeps its own). If the direct edition is
running it warns first. Covered by `Core.directEditionImport` (fixture layout); the panel step needs a human run.

## MCP

Unchanged design: HTTP server in the app on `127.0.0.1:<port>` (Network.framework, Host/Origin checks, OAuth 2.1 +
PKCE or static tokens). Clients either connect by URL (no bridge) or launch the bundled stdio bridge, which forwards
to the same URL with `MCP_TOKEN`. Super Paste never writes any client's config file; Settings › Integrations shows a
snippet to paste (both editions). Both editions default to port 39725: if both run, the second one's server fails to
bind and says so in Integrations — change one port.

## Deviations from the shared brief

- Brief addendum §1 says NSEvent global monitors don't work sandboxed. The hot corner uses a global mouse-moved
  monitor and is kept unchanged; the only observation that it works used a synthetic mouse-move, so it needs a human
  re-run (test-results §6). If it fails, the fallback is polling `NSEvent.mouseLocation` on a timer.
- Import requires a quit and reopen (the open SQLite store can't be swapped live); the app offers Quit Now.
