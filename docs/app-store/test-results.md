# Test results — 2026-11-12, macOS 26.5.1 (arm64), Command Line Tools only

All runs on branch `release/macos-app-store`. Store app = `ADHOC=1 scripts/package-appstore.sh` →
`build/appstore/Super Paste.app`, ad-hoc signed with the Store entitlements (sandbox enforced), launched with `open`.
Other mission agents were using the same Mac and general pasteboard at the same time, so some captures in the
container came from them; results below only count items whose ids/contents were checked.

## 1. Self-tests

| Command | Result |
|---|---|
| `swift build && .build/debug/SuperPasteSelfTest` | warning-free, `All self-tests passed.` (incl. UpdateKit tests) |
| `swift build -Xswiftc -DAPP_STORE --scratch-path .build-appstore && .build-appstore/debug/SuperPasteSelfTest` | warning-free, `All self-tests passed.` (UpdateKit tests compiled out; adds `Core.directEditionImport`, `ClipboardKit.fileBookmarks`, `SyncKit.folderBookmark`) |

Store-only checks: import (copy, staged swap, backup, sync-state reset, resumed interrupted swap, symlink refusal),
file bookmarks (LRU of 64 held paths, pruning to existing items, persisted book), sync folder bookmark (resolves,
moved folder followed, missing bookmark reported as "Choose it again"). `ClipStore.performance` (a timing check)
failed once on a loaded machine and passed on rerun.

**Rule for the rest of this file:** results obtained with synthetic keyboard/mouse input or AX presses (§10) are not
counted as verified; those items are listed as NEEDS HUMAN RE-RUN.

## 2. Bundle checks

- `codesign --verify --strict -vv`: valid on disk, satisfies its Designated Requirement.
- App entitlements = the five keys in `entitlements.md`; bridge = app-sandbox + network.client,
  `Identifier=com.udsy.superpaste.appstore.mcp`, `Info.plist entries=4`.
- `Info.plist`: `CFBundleIdentifier = com.udsy.superpaste.appstore`; no `NSAppleEventsUsageDescription`.
- `nm SuperPaste | grep -i 'updatekit\|Updater'` → only `StripKit.CardView.updateRing` (a false match): no updater code is linked.

## 3. Clipboard capture, concealed-type filter, history, link previews (sandboxed) — PASS (CLI only)

- `pbcopy` of `sandbox-probe-<ts>` → row in the container's `clips.sqlite` (kind text, app `com.apple.Terminal`,
  app colour computed): pasteboard polling and frontmost-app lookup work sandboxed.
- A pasteboard item carrying `org.nspasteboard.ConcealedType` → not saved.
- A `public.file-url` → saved as a files item.
- Ignored-apps exclusion was **not** exercised sandboxed (only the concealed type was); it uses the same frontmost
  app lookup that §3 shows working. NEEDS HUMAN RE-RUN: copy in an ignored app (e.g. Passwords), check nothing is saved.
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

## 5. Copied files across a relaunch — defect found and fixed; in-app retest NEEDS HUMAN RE-RUN

- Finding: after a relaunch, choosing a files item put only Super Paste's two marker types on the pasteboard; the
  `public.file-url` was gone. Experiment: a sandboxed tool writing a `public.file-url` it cannot read → dropped; the
  same tool unsandboxed → kept. Reading the URL from the pasteboard makes it readable for that launch only; a
  security-scoped bookmark made then, resolved in a fresh process with access held during the write → kept
  (released immediately after `writeObjects` → dropped).
- Fix: `SandboxFileAccess`. The finding and the fix's mechanism were shown with standalone sandboxed CLI tools (no
  input automation). The in-app retest below chose the item with synthetic keystrokes, so it does not count: file
  `zebrafile.txt` copied, app quit and reopened, item chosen in the strip →
  pasteboard had `public.file-url`, `public.utf8-plain-text`, `org.superpaste.item-id 8F392854…` (the item's id),
  `org.nspasteboard.source com.udsy.superpaste.appstore`.
- Items captured before this fix (or imported from the direct edition) have no bookmark and still paste without the
  file (known-blockers).

## 6. Global shortcut, strip, copy-to-clipboard, hot corner — NEEDS HUMAN RE-RUN

These were observed only with synthetic input (System Events keystrokes and a posted mouse-move, §10): ⇧⌘V showed
the strip window, Return wrote the item with its markers, the corner showed the peek. Not counted as verified.
Re-run by hand: ⇧⌘V opens the strip; Return puts the item on the clipboard (Store default); moving the pointer into
the bottom-left corner shows the peek; check `/usr/bin/log show` (§9) for denials.

## 7. Direct paste permission — NEEDS HUMAN RE-RUN

- `superpaste://enable-direct-paste` showed the "Paste to Any App" screen, i.e. `CGPreflightPostEventAccess()` = false.
- Its Open System Settings button (pressed by an AX click, §10 — so not counted) called `CGRequestPostEventAccess()`:
  the system TCC database then held `kTCCServicePostEvent|com.udsy.superpaste.appstore|0` (since reset with
  `tccutil reset PostEvent com.udsy.superpaste.appstore`).
- Not done: granting it and pasting into another app (no synthetic ⌘V was posted by me).

## 8. Sync folder bookmark — logic PASS (self-test); sandboxed picker NEEDS HUMAN RUN

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

## Needs a human run (exact steps; no automation)

1. `ADHOC=1 scripts/package-appstore.sh && open "build/appstore/Super Paste.app"`.
2. Settings › Sync › Folder sync → pick an empty folder → status reaches "Synced"; folder has `key.check` and a
   device folder. Quit, reopen: status "Synced" again with no picker (bookmark resumed); copy something, Sync Now,
   the folder gains a segment. `defaults read ~/Library/Containers/com.udsy.superpaste.appstore/Data/Library/Preferences/com.udsy.superpaste.appstore.plist syncFolderBookmark` is non-empty.
3. Settings › General › Paste items: To active app; paste from the strip into TextEdit → allow in the system
   prompt / Accessibility list → paste again: text lands in TextEdit.
4. About › Import… → pick `~/Library/Application Support/Super Paste` → Quit Now → reopen: the direct edition's
   history and pinboards appear; `Backup/Before import …` holds the previous Store history; the direct folder is unchanged.
5. Settings › Integrations › Add Client… → paste the snippet into Claude Desktop → its tools list Super Paste.
6. §6: ⇧⌘V, Return, hot corner. §3: copy in an ignored app (Passwords) — not saved.
7. §5: copy a file in Finder, quit and reopen, choose it in the strip, paste in Finder — the file is pasted.
8. Check sandbox denials with the §9 command.
