# Test results — 2026-11-12, macOS 26.5.1 (arm64), Command Line Tools only

All runs on branch `release/macos-app-store`. Store app = `ADHOC=1 scripts/package-appstore.sh` →
`build/appstore/Super Paste.app`, ad-hoc signed with the Store entitlements (sandbox enforced), launched with `open`.
Other mission agents were using the same Mac and general pasteboard at the same time, so some captures in the
container came from them; results below only count items whose ids/contents were checked.

## 1. Self-tests

| Command | Result |
|---|---|
| `swift build && .build/debug/SuperPasteSelfTest` | warning-free, `All self-tests passed.` (incl. UpdateKit tests) |
| `swift build -Xswiftc -DAPP_STORE --scratch-path .build-appstore && .build-appstore/debug/SuperPasteSelfTest` | warning-free, `All self-tests passed.` (UpdateKit tests compiled out; adds `Core.directEditionImport`, `SyncKit.folderBookmark`) |

`ClipStore.performance` (a timing check) failed once on a loaded machine (0.188 s vs its bound) and passed on rerun.

## 2. Bundle checks

- `codesign --verify --strict -vv`: valid on disk, satisfies its Designated Requirement.
- App entitlements = the five keys in `entitlements.md`; bridge = app-sandbox + network.client,
  `Identifier=com.udsy.superpaste.appstore.mcp`, `Info.plist entries=4`.
- `Info.plist`: `CFBundleIdentifier = com.udsy.superpaste.appstore`; no `NSAppleEventsUsageDescription`.
- `nm SuperPaste | grep -i 'updatekit\|Updater'` → only `StripKit.CardView.updateRing` (a false match): no updater code is linked.

## 3. Clipboard capture, privacy filters, history, link previews (sandboxed) — PASS

- `pbcopy` of `sandbox-probe-<ts>` → row in the container's `clips.sqlite` (kind text, app `com.apple.Terminal`,
  app colour computed): pasteboard polling and frontmost-app lookup work sandboxed.
- A pasteboard item carrying `org.nspasteboard.ConcealedType` → not saved.
- A `public.file-url` → saved as a files item.
- `https://example.com/` → link item with `link_title = Example Domain` (network.client works).

## 4. MCP server and the sandboxed stdio bridge — PASS (after a fix)

- `lsof -nP -iTCP:39725 -sTCP:LISTEN` → `SuperPast … TCP 127.0.0.1:39725 (LISTEN)`; app log: `MCP server listening on 127.0.0.1:39725`.
- `curl` without a token → 401; wrong `Host` → 421.
- Bridge launched from an unsandboxed shell (as Claude Desktop would) — first build: **exit 133**, crash report
  `EXC_BREAKPOINT` in `_libsecinit_appsandbox`. Controlled experiment: the same sandboxed hello-world traps without an
  embedded Info.plist and runs with one (`-Xlinker -sectcreate __TEXT __info_plist`). Fixed in `build-app.sh`.
- After the fix: `initialize` → serverInfo `super-paste`; `tools/call search {"query":"sandbox-probe"}` → the item
  captured in §3; `create_item {"content":"created via sandboxed bridge"}` → new row in the app's database;
  `list_pinboards` → `{"pinboards":[]}`. The bridge got its own container (`com.udsy.superpaste.appstore.mcp`).
  The test client was seeded by writing a token hash into the container's `MCP/clients.json`.

## 5. Copied files across a relaunch — FAILED, fixed, PASS

- Finding: after a relaunch, choosing a files item put only Super Paste's two marker types on the pasteboard; the
  `public.file-url` was gone. Experiment: a sandboxed tool writing a `public.file-url` it cannot read → dropped; the
  same tool unsandboxed → kept. Reading the URL from the pasteboard makes it readable for that launch only; a
  security-scoped bookmark made then, resolved in a fresh process with access held during the write → kept
  (released immediately after `writeObjects` → dropped).
- Fix: `SandboxFileAccess`. Retest: file `zebrafile.txt` copied, app quit and reopened, item chosen in the strip →
  pasteboard had `public.file-url`, `public.utf8-plain-text`, `org.superpaste.item-id 8F392854…` (the item's id),
  `org.nspasteboard.source com.udsy.superpaste.appstore`.
- Items captured before this fix (or imported from the direct edition) have no bookmark and still paste without the
  file (known-blockers).

## 6. Global shortcut, strip, hot corner — PASS (synthetic input, see §10)

- ⇧⌘V (Carbon `RegisterEventHotKey`) opened the strip (a 1512×332 window owned by the app's pid).
- Return in the strip with the Store default (To clipboard) wrote the item to the pasteboard with the markers.
- Mouse moved to the bottom-left corner → the 220×70 peek window appeared: `NSEvent` global mouse monitor works sandboxed.

## 7. Direct paste permission — request path PASS; granted path NEEDS HUMAN RUN

- `superpaste://enable-direct-paste` showed the "Paste to Any App" screen, i.e. `CGPreflightPostEventAccess()` = false.
- Its Open System Settings button called `CGRequestPostEventAccess()`: the system TCC database then held
  `kTCCServicePostEvent|com.udsy.superpaste.appstore|0`.
- Not done: granting it and pasting into another app (no synthetic ⌘V was posted by me).

## 8. Sync folder bookmark — logic PASS; sandboxed picker NEEDS HUMAN RUN

- `SyncKit.folderBookmark` (Store self-test, unsandboxed process): enabling sync stores a security-scoped bookmark
  that resolves to the folder, and `key.check` is written through it.
- The sandboxed picker → bookmark → relaunch path was **not** completed: no folder was chosen (the scratch
  `syncfolder` stayed empty, no `syncFolderPath`/`syncFolderBookmark` in the container prefs).

## 9. Sandbox denials

`/usr/bin/log show --last 40m --style compact --predicate 'sender == "Sandbox" AND (eventMessage CONTAINS "SuperPaste(" OR eventMessage CONTAINS "super-paste-mcp(")'`:

```
  12 SuperPaste(pid) deny(1) user-preference-read com.apple.dock          # hot-corner conflict check -> skipped in Store builds
   3 SuperPaste(pid) deny(1) iokit-open-user-client AppleNVMeEANUC       # during file capture (system framework), harmless
   1 SuperPaste(pid) deny(1) mach-lookup com.apple.Safari.SafeBrowsing.Service  # LinkPresentation; preview still fetched
```

After the Dock fix, a relaunch + capture showed no new denials. None from `super-paste-mcp`. (Note: in zsh `log` is a
builtin; use `/usr/bin/log`.)

## 10. GUI and event automation actually run (disclosure)

Before the orchestrator's stop order I drove the UI with System Events / CGEvent from Terminal, ~18:02–18:11 EST:
`osascript` keystrokes ⇧⌘V, arrow keys, Return, Escape, typed "probe-file-2" and "zebrafile" into the strip search;
a CGEvent mouse-moved sequence to the bottom-left corner and back (~18:09); clicks on the Paste to Any App window
buttons (~18:09–18:10); a click on Settings › Sync › Folder sync (~18:10:53), followed by ⇧⌘G, the
`…/scratchpad/syncfolder` path and two Returns. Those last keystrokes went to the frontmost app (Terminal) instead of
the open panel — they are the "syncfolder path" that reached the orchestrator's session; it was not from the user.
No ⌘V was ever posted. After the stop order: no synthetic input of any kind.

## Needs a human run (exact steps)

1. `ADHOC=1 scripts/package-appstore.sh && open "build/appstore/Super Paste.app"`.
2. Settings › Sync › Folder sync → pick an empty folder → status reaches "Synced"; folder has `key.check` and a
   device folder. Quit, reopen: status "Synced" again with no picker (bookmark resumed); copy something, Sync Now,
   the folder gains a segment. `defaults read ~/Library/Containers/com.udsy.superpaste.appstore/Data/Library/Preferences/com.udsy.superpaste.appstore.plist syncFolderBookmark` is non-empty.
3. Settings › General › Paste items: To active app; paste from the strip into TextEdit → allow in the system
   prompt / Accessibility list → paste again: text lands in TextEdit.
4. About › Import… → pick `~/Library/Application Support/Super Paste` → Quit Now → reopen: the direct edition's
   history and pinboards appear; `Backup/Before import …` holds the previous Store history; the direct folder is unchanged.
5. Settings › Integrations › Add Client… → paste the snippet into Claude Desktop → its tools list Super Paste.
6. Check sandbox denials with the §9 command.
