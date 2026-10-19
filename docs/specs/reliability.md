# Reliability and data loss

What can go wrong, what the user should see, and what Super Paste does about it. One row per failure mode: the
area, the scenario, the expected outcome, how the code behaved before this review, the fix, and the self-test that
pins it down (`swift run SuperPasteSelfTest`; the test name is the case's label). "Accepted" rows are risks that
were weighed and left as they are, with the reason.

The rule behind every row: **nothing the user wrote or copied disappears without being told, in plain words, what
happened and where it went.** A failure may stop something new from being kept; it may never take what is already
kept, and it may never pretend everything is fine.

## Storage

| Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|
| The database file is damaged (not SQLite, corrupt pages, a foreign schema) | A fresh store starts; the damaged file is kept; what can be read from it comes back; the user is told | The file and the blob folder were moved aside and the app started empty, silently; nothing was read back | `Schema.open` runs `PRAGMA quick_check` at launch; a damaged file moves to `Backup/<date>-<id>/` with its `-wal`/`-shm` and blob folder; `Salvage` copies every table back in key ranges (an unreadable range is skipped, not the table), takes the search index whole or rebuilds it, cuts orphans, and moves the blob files of salvaged rows back; the sweep is skipped on that launch; `StoreRecovery` is shown after launch with the counts and the path | `ClipStore.salvage`, `ClipStore.recovery` |
| The file can't be opened for a reason unrelated to its contents (locked by another process, no read permission, the disk is full or failing) | The file is left exactly as it is; the app keeps working for the session; the user is told that copies aren't being saved | Treated as damage: moved aside and started over, or deleted when the move failed | `Database.Failure.isTransient` (busy, locked, cantopen, full, ioerr, perm, readonly, nomem…) runs the store in memory for this launch with a notice; busy/locked is retried four times first; nothing is moved; a damaged file that can't be moved is never written over | `ClipStore.unopenableLeftAlone` |
| A move-aside fails halfway | No file is deleted | `moveAside` deleted a file it couldn't move | The fallback `removeItem` is gone; a failed move means memory for the session and a notice | `ClipStore.unopenableLeftAlone` (nothing in `Backup/`) |
| Power cut after a confirmed write | The write is on disk | `synchronous = NORMAL` under WAL: the last transactions before a power cut could be lost (the file stays intact) | `synchronous = FULL`: every commit is fsynced before the call returns | `ClipStore.flushAndReopen` (behaviour under power loss can't be tested in-process) |
| Quit, or an auto-update swapping the bundle, with writes still in the write-ahead log | The main file alone holds everything | The WAL was left for the next open to replay (fine for SQLite, but a copy of `clips.sqlite` alone was behind) | `applicationWillTerminate` → `ClipStoreModule.shutdown()` → `PRAGMA wal_checkpoint(TRUNCATE)`; the update helper waits for the process to exit, so the checkpoint comes first | `ClipStore.flushAndReopen` (WAL empty after a flush; reopening the main file alone has the data) |
| Disk full while capturing | The capture fails whole (no half item), the store stays consistent, the user is told once, captures resume when there is room | The insert rolled back correctly but failed silently on every copy | `StoreError.database(diskFullMessage)` names a full disk whichever layer saw it (SQLITE_FULL, ENOSPC, NSFileWriteOutOfSpaceError); the monitor reports once per run of failures | `ClipStore.diskFull` (a page-capped database stands in for a full disk), `ClipboardKit.saveFailure` |
| The blob folder can't be written (permissions, a read-only volume) | The insert fails whole; small (inline) items still save; large ones resume once writable | Correct, untested | Unchanged; now pinned by a test | `ClipStore.blobFolderUnwritable` |
| A blob file is missing for an item (deleted by hand, a failed restore) | The card shows what it can (preview text, thumbnail); paste skips the missing representation; nothing crashes; re-copying the content rewrites the file | Correct: `BlobStore.save` rewrites a missing file; `PasteContent.entries` skips a missing blob; cards fall back to "Preview unavailable" | Unchanged | `ClipStore.blobs`, `ClipboardKit.pasteContent` |
| Orphaned blob files (a crash between the file write and the row) | Cleaned up, but never a file that a write about to be retried will need | Row-less files were deleted at the next launch regardless of age | Row-less files younger than the sweep grace (24 h) are kept | `ClipStore.blobs` |
| Two copies of the app running | One watcher, one writer | Both polled the pasteboard and wrote the same database (SQLite kept it intact; captures doubled; writes could collide with "database is locked") | The second copy activates the first and exits before touching anything (`SingleInstance`) | `Core.singleInstance` |
| Migration from an older schema | Migrates in place, once | Correct (one shipped version so far; `user_version` steps run in a transaction each) | Unchanged | `ClipStore.persistence` |
| A database from a newer Super Paste (a downgrade) | Opened as it is; nothing moved or lost | Correct (logged) | Unchanged; pinned by a test | `ClipStore.newerSchema` |
| Keep History migration 30 → Forever | An untouched 30-day default becomes Forever before the first prune; a limit the user chose stays | Correct | Unchanged | `Core.retentionMigration` |
| Erase History | Unpinned history goes; pinned items and pinboards stay; the pending undo is dropped | Correct; the confirmation didn't mention that, with sync on, the other Macs' history goes too | The confirmation adds that sentence when sync is on | `ClipStore.retention` |
| Undo delete | The last delete batch comes back until the next delete or quit; its blobs are protected meanwhile | Correct | Unchanged | `ClipStore.undoDelete` |
| Delete a pinboard | Items also in the history stay there; items that live only in that pinboard go with it | Correct; the MCP preview said "pinned items stay in clipboard history", which is wrong for pinned-only items | Wording fixed in the tool, `docs/MCP.md` and `strings.md` | `ClipStore.pinboards`, `MCPKit.tools` |

Accepted:

- **Mid-session corruption.** `quick_check` runs at open; a page that goes bad while the app runs fails the write
  that touches it (the user sees the alert from that action) and is caught at the next launch. A check on every
  write would cost more than it saves.
- **A newer schema opened by an older app** could hit constraints the older app doesn't know. Auto-updates only go
  forward; nothing is wiped either way.
- **Undo after quit.** The undo batch is in memory by design.

## Capture

| Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|
| Huge copies (a 500 MB image, a 1 GB file list, 50k lines of text) | Captured when within the per-type cap (50 MB), else that type is skipped; the app stays responsive | A type over the cap is skipped after being read once (the pasteboard gives no size ahead); text of any length is indexed with a capped preview; file lists are small (paths) | Unchanged | `ClipboardKit.pasteboardIO` |
| Rapid copies (100/s) | The settled content is captured; intermediate states are not | Each change restarted a 0.3 s settle: an app that rewrites the pasteboard without pause starved capture forever | `maxSettle` (1.5 s from the first change) reads the pasteboard as it is | `ClipboardKit.chatteringPasteboard` |
| Copies during sleep/wake | Nothing lost: the change count is compared on the next poll; an expired pause ends on wake | Correct | App Nap is now kept off the process (`beginActivity`), so the poll timer isn't slowed while no window shows | `ClipboardKit.monitor` |
| The pasteboard owner crashes mid-read | The types that can't be read are skipped; an item left empty isn't captured | Correct (`data(forType:)` returns nil) | Unchanged | `ClipboardKit.monitor` |
| Lazy/promised data that fails to materialise | Same as above | Correct | Unchanged | — |
| Concealed / transient types | Not captured while the two privacy switches are on | Correct | Unchanged | `ClipboardKit.captureFilter` |
| Apps that write many types | Every type stored in pasteboard order; banned OLE plumbing dropped | Correct | Unchanged | `ClipboardKit.quirks` |
| Duplicate detection race (the same content twice in quick succession) | One item, moved to the front | Correct: the checksum lookup and the write are one transaction on the main actor | Unchanged | `ClipStore.dedupe` |
| The monitor stalls | Captures resume with the next change | The timer runs in `.common` modes (alerts and menus don't stop it); a stall of the main thread stalls the whole app, which nothing in-process can fix | Unchanged; a chattering pasteboard (above) was the one real starvation | — |
| Our own writes captured again (a loop) | A paste or copy-out is seen as a restore, never a new capture | Correct: the item-id marker and the change count of own writes | Unchanged | `ClipboardKit.paste`, `ClipboardKit.pasteStack` |
| Universal Clipboard | Captured with no device (it came from elsewhere) | Correct | Unchanged | `ClipboardKit.captureFilter` |
| A copy can't be saved (disk full, read-only store) | The copy itself still works; the user is told once, in words that name the cause; saving resumes on its own | Silent: logged only, on every copy | `SaveFailure` notice once per run of failures, reset by the next save that works | `ClipboardKit.saveFailure` |
| Crash in the middle of a capture | No crash loop on relaunch | The change token is written before the capture, so a copy that crashes the classifier isn't retried at every launch (that copy is lost; the next one is captured) | Unchanged, now documented as deliberate | `ClipboardKit.monitor` |

Accepted:

- **Reading a promised type from a hung owner app** blocks the main thread until the pasteboard server gives up.
  There is no way to tell a promise from data ahead of the read.
- **Universal Clipboard** content is attributed to whatever app is frontmost on this Mac.

## Paste

| Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|
| The target app quits between selection and paste | The content is on the clipboard; "Copied — Press ⌘V to paste" | Correct: the activation wait times out after 1 s and falls back | Unchanged | `ClipboardKit.paste` |
| Secure keyboard entry on (a password field, a terminal) | No synthetic ⌘V (it would be swallowed); copied with the hint | ⌘V was typed and lost | `isSecureInputEnabled` check before typing | `ClipboardKit.secureInput` |
| Accessibility revoked mid-session | Falls back to copying, asks once (unless suppressed) | Correct: checked on every paste | Unchanged | `ClipboardKit.paste` |
| Keyboard layout changes | ⌘V types the V of the current layout; the Paste Stack's ⌘V follows | The stack's ⌘V stayed on the old key code | Re-registered on `keyboardSelectionDidChangeNotification` | `ClipboardKit.layoutChange` |
| Paste Stack across app switches and sleep | The stack holds; ⌘V goes to the frontmost app | Correct | Unchanged | `ClipboardKit.pasteStack` |
| ⌘V stuck registered after a crash | Never: Carbon hot keys die with the process; in-process, every stack change re-syncs the registration | Correct | Unchanged | `ClipboardKit.pasteStack` |
| Pasting very large items | Within the per-type cap; written whole | Correct | Unchanged | `ClipboardKit.multiPaste` |
| Plain-text conversion of exotic types | Text flavours become one UTF-8 string; images stay images; a file list without text stays a file list | Correct | Unchanged | `ClipboardKit.pasteContent` |
| Hot corner across displays and full-screen spaces | A corner two screens share isn't a corner; no peek over a full-screen app | Correct | Unchanged | `StripKit.hotCorner` |

## Editing (what the user typed)

| Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|
| The store refuses an edit (disk full, locked) | The editor stays open with the text; the alert says why | The editor closed anyway: the text was gone | `save()` closes only when `saved()` returned true | `StripKit.editorKeepsText` |
| The item is deleted while being edited (here, by sync, by an MCP client) | The text is kept | `replaceContent` failed with "The item doesn't exist" and the editor closed | The draft is written as a new history item (pinned too when its pinboard still exists) with a toast saying so | `StripKit.editorKeepsText` |
| The editor goes away with unsaved changes (a click elsewhere closes the popover, the strip hides, the close button, the detached window closes) | Saved | Discarded silently | `commitPendingEdit()` from `popoverWillClose`, `windowWillClose` and the close button | `StripKit.editorKeepsText` |
| Cancel or Esc with unsaved changes | Asked: Discard / Keep Editing | Discarded at once | `cancelEditing()` confirms when `hasChanges` | (modal; checked by hand) |
| New Text Item: quit, crash or a stray Esc with text typed | The text is there next time | Lost | A draft in `Defaults` on every change; put back when the window opens; cleared by Create or a confirmed discard | `StripKit.newTextItemDraft` |

## Sync

| Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|
| Two Macs edit the same item | Last writer wins on `updatedAt`; ties break the same way everywhere | Correct | Unchanged | `SyncKit.twoMacsConverge`, `ClipStore.syncTies` |
| A file is still being uploaded or downloaded (iCloud placeholder, an empty file a service created first) | Wait; read once whole; no error | Placeholders handled; an empty file failed decryption and was reported as damaged or tampered with | An empty segment counts as pending (reading stops there); an empty blob is "missing", so the record waits | `SyncKit.filesStillArriving` |
| A segment or blob was changed by someone without the key, or truncated | Refused; reported by name; nothing from it applied; read once restored | Correct | Unchanged | `SyncKit.tamperedFilesRejected`, `SyncKit.crypto` |
| Clock skew between Macs | Converges; a Mac with a clock far ahead wins conflicts until its clock is fixed | Silent | Logged when a record is more than an hour in the future | — |
| The sync key is lost (new Mac, Keychain reset) | Clear instructions; the local history is untouched | The error said to import the key, not where from or how to start over | `missingKey` / `keyMismatch` name Settings › Sync › Import Key and the empty-folder way out, and say the local history is unaffected | `SyncKit.keysAndDisabled` |
| `state.json` corrupt or missing | Starts from a clean cursor: re-reads others' segments (idempotent) and re-ships its own | Correct | Unchanged | `SyncKit.compaction` |
| A pass fails midway | Cursors advance only after a segment is applied in one transaction | Correct | Unchanged | `SyncKit.tamperedFilesRejected` |
| Retention on one Mac | Never deletes on another | Correct | Unchanged | `SyncKit.pruneStaysLocal` |

Accepted:

- **Clock skew** can't be corrected without vector clocks; the log names it.
- **A damaged segment blocks everything after it from that Mac** until it is fixed or that Mac writes a snapshot
  past it. Skipping it would lose records.

## MCP

| Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|
| Malformed requests (bad request line, repeated Host/Content-Length, bad chunking, non-JSON, bad JSON-RPC) | Refused with the right status; the connection closed | Correct | Unchanged | `MCPKit.httpParser`, `MCPKit.server` |
| Huge payloads | 4 MB on `/mcp`, 64 KB on OAuth paths, 16 KB headers; 413/431 | Correct | Unchanged | `MCPKit.httpParser` |
| Concurrent clients | 32 connections; one request at a time per connection; sessions per client | Correct | Unchanged | `MCPKit.server` |
| Port in use | `.failed` with the reason in Settings › Integrations; a port change checks the new port first and reverts on failure | Correct | Unchanged | `MCPKit.server` |
| Token theft | Tokens shown once, stored as SHA-256, files 0600, loopback only, Host and Origin checked | Correct | Unchanged | `MCPKit.secretsAndPKCE`, `MCPKit.server` |
| Tool calls that delete | Preview without `confirm`, delete only with `confirm: true` | Correct; the pinboard preview's wording was wrong | Wording fixed | `MCPKit.tools` |

## Lifecycle

| Scenario | Expected | Before | Fix | Test |
|---|---|---|---|---|
| Auto-update swaps the bundle mid-capture or mid-paste | Never mid-anything: the idle install needs 10 min without input, no strip, no stack; the quit install runs after `applicationWillTerminate` flushed the store | Correct apart from the flush | The flush (above) | `UpdateKit.endToEnd`, `UpdateKit.schedule` |
| Settings corruption | An undecodable value reads as its default | Correct | Unchanged | `Core.settingsDefaults` |
| Permissions denied at onboarding, granted later | Checked live on every paste; the permission screen polls | Correct | Unchanged | `SettingsKit.permissionFlow` |
| A display is removed or resized while the strip shows | The strip moves to the main screen rather than staying key on a screen that is gone | Stayed where it was | `didChangeScreenParametersNotification` re-lays the strip out on the main screen; the Paste Stack panel comes back on screen too | `StripKit.controller` (geometry) |
| Hotkey conflicts after launch | Retried every 30 s; noticed once | Correct | Unchanged | — |

## Fault injection in the self-test

- A real SQLite database with a page overwritten in the middle (`ClipStore.salvage`).
- A database file with no read permission (`ClipStore.unopenableLeftAlone`).
- `PRAGMA max_page_count` as a stand-in for a full disk (`ClipStoreModule.limitDatabase`).
- A blob folder with no write permission (`ClipStore.blobFolderUnwritable`).
- A fake clock and deferred timers in the ClipboardKit harness (`ClipboardKit.chatteringPasteboard`).
- A store that throws on insert (`ClipboardKit.saveFailure`).
- Private named pasteboards everywhere; the general pasteboard is never touched; no key event is ever posted.
- Empty segment and blob files in a sync folder (`SyncKit.filesStillArriving`); flipped bytes and forged blobs
  (`SyncKit.tamperedFilesRejected`).
