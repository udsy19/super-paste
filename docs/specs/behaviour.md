# Paste 7.0.3 — Behaviour specification (reference for Super Paste)

What the installed **Paste 7.0.3** (Setapp build `com.wiheads.paste-setapp`, CFBundleVersion 29869049, macOS 14.0+) does on the Mac, reconstructed only from the shipped bundle. Super Paste reimplements this behaviour from scratch. It does not copy Paste's code or assets.

## 0. Evidence legend and method

| Tag | Meaning |
|---|---|
| **[S]** | String evidence: `en.lproj/Localizable.strings` and `.stringsdict`, plus C-string and Swift-literal strings in the `Paste` binary (`__cstring`, and ≤15-byte literals decoded from `mov`/`movk` immediates). |
| **[B]** | Binary evidence: disassembly (`objdump`), Swift reflection metadata (`__swift5_types`/`__swift5_fieldmd`: type, field and enum-case names), ObjC metadata (`dispatch.json`), constants and control flow, and localization-accessor call sites (which view calls which string key). |
| **[R]** | Resource evidence: `Info.plist`, entitlements, `PasteStack.storyboardc`, `Assets.car`, Core Data model `v5Paste.momd/v11.mom`, `Metadata.appintents`, the live DB **schema**, and `defaults` key names. |
| **[U]** | Unverified: inferred from naming, from conventions such as nspasteboard.org, or from general knowledge of Paste. Treat these as design decisions to make, not facts. |

Notes:

- The user's own clipboard rows, `paste-events.jsonl` and `item-classes.jsonl` were **not** read. Only the DB schema, preference key names and non-content setting values (shortcut encodings, booleans) were read.
- Source-file names compiled into the binary (e.g. `Paste/GeneralSettingsView.swift`) give the module and file layout used throughout this doc.
- Paste is built from ~30 SwiftPM modules: `Paste` (app), `PasteCore`, `PasteCoreUI`, `PasteUI`, `PasteConfig`, `PasteSearch`, `PasteShortcut`, `PasteSystemPermissions`, `PasteOnboarding`, `PasteWhatsNew`, `PasteInAppNotifications`, `PastePicks`, `PasteLanguageModel`, `PasteMCP`, `PasteHandoff`, `PasteRouting`, `PasteCollections`, `PastePlatform`, `PasteLocalization`, `PasteDI`, `PasteLogging`, `PasteTelemetry`, `PasteAnalytics`, `PasteLicensing`, `PasteLicensingDirect`, `PasteLicensingSetapp` [S].
- Third-party code: PostHog, Sentry (with KSCrash), PLCrashReporter, Setapp framework, swift-nio, Hummingbird, the MCP Swift SDK, swift-async-algorithms, swift-collections, ZIPFoundation [S][R].
- Apple frameworks linked: AppKit, SwiftUI, CoreData, CloudKit, CoreSpotlight, Vision, VisionKit, LinkPresentation, QuickLookUI, ScreenCaptureKit, FoundationModels (weak), AppIntents, Carbon (hot keys), ServiceManagement, UserNotifications, CryptoKit, Metal, WebKit, Network [B].

---

## 1. App shell and lifecycle

1. **Agent app.** `LSUIElement = true`: no Dock icon and no main menu bar of its own. A hidden main menu still exists so the panels get standard key equivalents: File › Close ⌘W; Edit › Undo ⌘Z / Redo ⇧⌘Z / Cut ⌘X / Copy ⌘C / Paste ⌘V / Select All ⌘A; Window › Minimize ⌘M; Quit Paste ⌘Q [R][S][B].
2. **Not sandboxed.** The entitlements have no `app-sandbox`. They contain iCloud/CloudKit containers `iCloud.com.wiheads.paste.container.v1` and `iCloud.com.wiheads.paste`, APS production, and a keychain group. Data lives in `~/Library/Application Support/com.wiheads.paste-setapp/` [R].
3. **Launch sequence** (AppDelegate / AppCoordinator) [B][S]:
   - Initialise logging (`Logging initialized (diagnostics: …)`).
   - Load the persistent stack (`Core initialized. N items`).
   - Run a V5 migration from Paste 4 if needed (`requireV5Migration()`).
   - Show onboarding if not completed (`showOnboarding()`), or What's New if the version changed (`lastLaunchedVersion`).
   - Register global hot keys: activation and Paste Stack.
   - Start pasteboard monitoring.
   - Start the MCP server if enabled (`isMCPEnabled`).
   - Register for remote notifications (CloudKit pushes).
4. **Reopen.** `applicationShouldHandleReopen` (launching the app again from Finder or Spotlight) opens the main strip [B][U].
5. **Open at login / Run in background.** `OpenAtLoginManager` uses ServiceManagement. Onboarding labels the toggle "Run in background — Open at login and always keep running". Settings labels it "Open at login" [S][B].
6. **Restart.** `sleep 0.25 && open "<bundle path>"` via `/bin/sh -c` is used by "Restart Paste" (shortcut reset and diagnostics) [S].
7. **Move to Applications** (direct-download build only). A LetsMove-style prompt: "Move to Applications folder?" / "…in your Home folder?". It handles App Translocation, DMG detach, quarantine xattr removal and admin authorization. A "Do not move" choice is remembered with `moveToApplicationsFolderAlertSuppress` [S]. Optional for Super Paste.
8. **Diagnostics.**
   - Help › Start Diagnostics shows "Paste will restart to begin collecting diagnostic logs. You can stop diagnostics at any time from the menu."
   - Stop shows "Diagnostic logs will be copied so you can send them to support." with "Stop and Copy Logs".
   - Logs are written to files named `paste-diagnostics-yyyy-MM-dd-HHmmss`, starting with a `--- Diagnostic Info ---` header (`App: …`, `OS: macOS … (hw.model)`).
   - Key `isDiagnosticsEnabled`, default false [S][B].
9. **Damaged store.** If the DB cannot open: "Paste Can't Open Its Data" → "Reset Local Data". The damaged files (`db.sqlite`, `-wal`, `-shm`, `_SUPPORT`) move to a `backup` folder next to it and the app starts over [S][B]. Super Paste goes further (docs/specs/reliability.md): only a file that is actually damaged (not SQLite, corrupt pages, a foreign schema) is moved aside, and what can still be read from it is copied into the fresh store, blob files included; a file that merely can't be opened (locked, no permission, a full disk) is left untouched and the store runs in memory for the launch. Either way nothing is deleted and the user is told after launch what happened, how much came back and where the old file is.

## 2. Clipboard monitoring (capture pipeline)

Implemented by `PasteCore.Pasteboard`, `PasteboardHistoryManager`, `PasteboardItemProcessor` and `PasteboardItemComposer` [B].

### 2.1 Change detection

- **Polling.** `Pasteboard` owns `pollTimer` and `syncTimer` [B].
  - `Start monitoring pasteboard` records the current `NSPasteboard.general.changeCount`, then schedules a repeating **0.25 s** `NSTimer` with **0.025 s tolerance** [B: `fmov d0,#0.25`; tolerance constant `0x3F9999999999999A`].
- **Debounce.** When the poll sees a new `changeCount` it logs `Pasteboard change detected, starting sync timer` and (re)starts a one-shot **0.3 s** `syncTimer` [B: `0x3FD3333333333333`]. Only when that fires (`Sync timer fired`) are the items read. This avoids reading half-written multi-type pasteboards.
- **Persistence.** The last processed `changeCount` is saved as `pasteboard-change-token`, and a running counter as `pasteboardSyncCount` [S][R]. After relaunch, the content that was already on the clipboard is not captured again [U].
- **Pause.** While paused (§6.3) monitoring keeps running but captures are skipped. `PausePasteManager` holds `pauseTimer` and `resumeDate` [B].

### 2.2 Reading

1. `Starting Pasteboard sync from <changeCount>` → read every `NSPasteboardItem` and every one of its types (`Retrieved N types: …`) [S].
2. If there are no items, log `No items in system pasteboard` and do nothing [S].
3. For each type, read the data. A type whose data exceeds the **storable item size** is skipped: `Skipping pasteboard type X: N bytes exceeds the storable item size` [S].
   - The limit is held in a property and its value was not recovered [U]. Super Paste should choose one, e.g. 50 MB per item.
4. `com.apple.is-remote-clipboard` (Universal Clipboard from another Apple device) is checked during processing [S]. Probable use: tag the item, or mark the device as remote [U].
5. A capture whose content is empty is dropped (`Empty pasteboard content`) [S].
6. Each item is stored as `[PasteboardItem]`, where `PasteboardItem = { types: [String], dataByType: [String: Data] }` (Codable). That array is the authoritative payload used when pasting back [B].

### 2.3 Filters (what is *not* captured)

1. **Frontmost/source app.**
   - The source is the frontmost app (`NSWorkspace.frontmostApplication`) at capture time.
   - If the pasteboard carries `org.nspasteboard.source` (nspasteboard.org convention), that bundle id is used instead [S][U on precedence].
   - If no frontmost app can be determined: `Undefined frontmost application, skipping pasteboard change` [S].
2. **Ignored applications.** If the source bundle id is in `ignoredBundleIdentifiers`: `Ignored application X, skipping pasteboard change` [S]. Defaults, in this order [B, decoded from `__DATA`]:
   `com.apple.Passwords`, `com.apple.keychainaccess`, `com.1password`, `com.agilebits.onepassword-osx`, `com.agilebits.onepassword4`, `com.agilebits.onepassword7`, `com.lastpass.LastPass`, `com.dashlane.Dashlane`, `com.bitwarden.desktop`, `in.sinew.Enpass-Desktop`, `com.SiberSystems.RoboForm`, `com.callpod.keepermac`, `com.keepersecurity`, `.nordpass`.
   - The last entry is a suffix-style pattern, so matching is probably by suffix or prefix for some entries [U].
3. **Ignored pasteboard types.** If any item contains a type in `ignoredPasteboardTypes`: `Ignored pasteboard type X, skipping pasteboard change` [S]. Defaults [B]:
   `org.nspasteboard.TransientType`, `org.nspasteboard.AutoGeneratedType`, `org.nspasteboard.ConcealedType`, `de.petermaurer.TransientPasteboardType`, `com.typeit4me.clipping`, `Pasteboard generator type`.
4. **Privacy toggles.**
   - *Ignore confidential content* edits this set (`ConcealedType`) [U on the exact mapping].
   - *Ignore transient content* edits the transient/auto-generated markers [U].
   - Both toggles are backed by `PrivacySettingsViewModel._ignoredPasteboardTypes` [B].
5. **Pasteboard privacy (macOS 26).**
   - Paste checks whether it may read the pasteboard ("Pasteboard has access") and can send the user to `x-apple.systempreferences:com.apple.preference.security?Privacy_Pasteboard`.
   - Prompt title "Allow Pasteboard Access" [S][B].
   - Super Paste must handle macOS 26's programmatic-paste privacy (`NSPasteboard.accessBehavior`) when present.
6. **Paste's own writes.**
   - When Paste puts an item on the pasteboard it adds the private type `com.wiheads.paste.item-id`, and the processor stamps `org.nspasteboard.source = com.wiheads.paste` [S][B].
   - On the next poll this lets the manager recognise "restore of an existing item" (`pasteboardHistoryManagerDidRestoreItem`) instead of creating a duplicate [B].

### 2.4 Per-app quirk rules [B]

Static tables pair a source app (or `*`) with pasteboard types:

| Rule | Data | Likely effect |
|---|---|---|
| `bannedTypes` (all apps) | `com.microsoft.ole.source`, `com.microsoft.ObjectLink`, `com.microsoft.Link-Source`, `com.microsoft.DataObject` | Stripped from stored or re-pasted items [U] |
| `org.mozilla.firefoxdeveloperedition` | `public.file-url`, `public.png` | Not stored for that app [U] |
| `com.microsoft.excel` | `public.utf16-plain-text`, `public.utf8-plain-text` | Special handling of Excel copies [U] |

### 2.5 Item type detection

`ItemType` = `unknown, image, color, files, link, text` (stored as `rawType`, raw values 0…5 in declaration order [U on numbering]) [B]. Classification [B][S][U]:

| Type | Rule |
|---|---|
| **files** | Item(s) contain file URLs. Card shows "File" / "%d files" / "Multiple files". Preview is `FilesPreview(paths, totalSize, imageData)` with a Quick Look thumbnail (`isFileItemQLThumbnailImageEnabled`, default true). |
| **image** | Image data present (TIFF/PNG/JPEG…). Preview is `ImagePreview(imageSize, imageData)`, a downscaled thumbnail. |
| **link** | The plain text parses as a single URL (`http`, `www.` normalisation seen). Title comes from `public.url-name` if present. Preview is `LinkPreview(url, urlName, iconData, imageData)`. |
| **color** | Text matching `^#?[A-Fa-f0-9]{6}$`. Preview is `ColorPreview(colorCode)`. Footer shows hex (`#%06X`) or `RGB`. |
| **text** | Everything else with string/RTF/HTML. Preview is `TextPreview(textLength, text)`, where `text` may be attributed (rich). |
| **unknown** | Payload with none of the above. The card shows "Preview unavailable — Preview can't be shown, but the content is saved, and you're able to paste it". |

MCP `create_item`/`update_item` use the same auto-detection (text/color/link) [S].

### 2.6 Dedupe

- `ItemEntity.checksum` (indexed) is a content hash of the stored payload [R]. The algorithm is probably SHA-256 hex via CryptoKit [U].
- If a capture hashes to an existing item, that item is bumped to the top (new `timestamp`) rather than inserted again. `PasteboardCapture { didChangeNewestItem, itemIdentifier }` reports whether the newest item changed [B][U for the details].

### 2.7 Source app and device records

- **ApplicationEntity** (unique `bundleIdentifier`) stores `name`, `rawIcon` (icon PNG data) and `rawColor` (Int RGB), which tints the card header [R][B].
  - Known apps use a built-in colour table [B]. Examples: Photoshop `#005C90`, Illustrator `#E58B00`, Acrobat `#9B0A00`, Numbers `#52CC64`, Pages and iBooks `#FA9214`, Safari/Finder/Mail/Xcode/Keynote `#62A9F5`, Calendar/Photos/Reminders `#F0554D`, Terminal `#454D4D`.
  - The table also covers Figma, Sketch, Framer, Chrome, Office, VS Code, Slack and Telegram.
  - Other apps get a colour derived from their icon [U].
- **DeviceEntity** (unique `identifier`) stores `name`, `rawType` (`Device.Family`: iPhone, iPad, mac) and `appVersion`. Each item references the device it was copied on [R][B].
  - On the Mac, the identifier comes from the IOKit platform serial number (`IOPlatformSerialNumber`) [S].

### 2.8 Link previews

- If **Generate Link Previews** is on (`isLinkPreviewsEnabled`, default **true**), LinkPresentation fetches title, favicon and image for link items (`LinkMetadataResult(title, iconData, imageData)`) [B].
- Settings copy: "Download web content for previews; may activate one-time or analytics-sensitive links." [S]

### 2.9 Retention ("Keep History")

- Stored as `ClipboardAttributes.capacity` (Int, **days**, `0` = unlimited/"Forever") inside the clipboard-history `ListEntity.rawAttributes` [B].
- **Slider ↔ days mapping** (decoded from `HistoryCapacitySlider`) [B]. The slider value `v` runs from 1.0 to 5.0:

| Slider range | Days stored | Label (U on wording) |
|---|---|---|
| 1 ≤ v < 2 | `round((v−1)·6 + 1)`, so 1…7 | 1–6 days |
| 2 ≤ v < 3 | `round((v−2)·3 + 1)·7`, so 7…28; values above 27 snap to 30 | 1–3 weeks |
| 3 ≤ v < 4 | `round((v−3)·11 + 1)·30`, so 30…360; values above 345 snap to 365 | 1–11 months |
| v = 4 | 365 | 1 year |
| v = 5 | 0 | **Forever** [S `settings.history.forever`] |

- The reverse mapping places stored values on the same scale.
- In onboarding, choosing unlimited shows the tooltip "Unlimited history may increase your disk space usage" [S].
- **Pruning.** Items that are not pinned (`list == nil`) with `timestamp` older than *now − capacity* are deleted [B: predicate `%K == nil && %K < %@`; U on schedule, probably at launch, on change and periodically]. Pinned items are never pruned.
- **Super Paste note.** The default is **Forever** (0). Installs that still hold the earlier 30-day default, never
  having moved the slider (`historyRetentionUserSet` false), are migrated to Forever once at launch, before the
  first prune. Pruning runs at launch and hourly, and never touches pinned items.
- **Reducing the limit** asks: "You have items older than the new history limit. Do you want to delete these older items and apply the new limit?" — "Pinned items and Pinboards won't be deleted. This action cannot be undone." [S]
- **Erase History…** asks "Are you sure you want to erase your Clipboard History?" with the same subtitle, and buttons Erase / Cancel. It is reachable from General settings and the Clipboard tab's context menu [S][B].

### 2.10 Capture feedback

- **Sound.** `SoundFeedback` loads `Copy.aiff` (0.21 s) and `Paste.aiff` (0.08 s). It plays Copy on capture and Paste on paste when **Sound effects** is on (`isSoundEffectsEnabled`, default **true**) [R][B].
- **Menu bar icon.** Animates through `StatusItem/0` … `StatusItem/16` (17 frames) on capture. `StatusItem/paused` is shown while paused [R][B][U on the trigger].
- **A copy that can't be saved** (the disk is full, the store is read-only) is reported once per run of failures, in words that name the cause and say that copying and pasting still work; the next save that works resets the notice. No sound plays for a copy that wasn't kept. Super Paste addition; docs/specs/reliability.md.

## 3. Pasting

### 3.1 Paste destination ("Paste Items")

| Setting | Label | Behaviour |
|---|---|---|
| `isDirectPasteEnabled` = true (default) [B] | **To active app** — "Paste selected items directly to the application you are currently using." | Write the item to the pasteboard, hide the strip, re-activate the previously frontmost app, then synthesise ⌘V. This needs Accessibility (CGEvent posting) [S][U on the mechanism]. Super Paste: the ⌘V waits until the strip is off screen (it is the key window while it shows and would receive the keystroke itself), then for the target to be frontmost, then settles 50 ms; the keystroke uses the V key of the current layout, carries only ⌘, and is posted at the HID tap. |
| false | **To clipboard** — "Copy selected items to the system clipboard to paste manually later." | Only write to the pasteboard. An OSD shows "Copied" [S]. |

- If direct paste is on but Accessibility is not granted, the first paste shows the sheet **"Do you want to paste directly to %@?"**. Body: "Paste needs accessibility access to paste directly to other apps." Buttons: **Allow Accessibility Access** / **Not Now, Copy to Clipboard**, plus a **Do not ask again** checkbox [S].
  - Results are reported as `enable_accessibility_access`, `copy_to_clipboard`, `copy_to_clipboard_and_dont_ask_again` [S].
  - A strip footer link "Enable Direct Paste ›" brings it back [S].
- The context menu and tooltips name the target as "Paste to %@" (app name), falling back to "current app" [S].

### 3.2 Plain text

- **Always paste as Plain Text** (`isPasteAsPlainTextEnabled`, default false) [S][B].
- Per paste, the **Plain Text mode** modifier + Return pastes as plain text. Default modifier is **⇧** (`plainTextModifierFlags` = 0x20000), configurable in Shortcuts [B].
- Context menu items: "Paste as Plain Text", "Copy as Plain Text" [S].
- Plain-text paste writes only the string flavours [U].

### 3.3 Quick Paste

- The **Quick Paste** modifier (default **⌘**, `quickPasteModifierFlags` = 0x100000) + **1…9** pastes the Nth visible item [B][S "+ 1...9"].
- While the modifier is held, cards show their number badge (`ItemCell.ShortcutIndicatorView`) [B].

### 3.4 Multiple items

- Several items can be selected and pasted together with Return ("select the items, and press the return key to paste them into any app") [S].
- Whether they are joined into one paste or pasted sequentially was not determined [U]. Recommendation: join text with newlines; paste mixed types sequentially.

### 3.5 What is written to the pasteboard

- `PasteboardWriter` writes every stored type of the item except `bannedTypes` [B][U].
- It adds `com.wiheads.paste.item-id` = item identifier, used for restore detection (§2.3) [S].
- Writing marks the item as most recent ("restore") [B `pasteboardHistoryManagerDidRestoreItem`, `RestoreOptions`][U on whether it reorders].

### 3.6 Paste Stack (sequential paste)

- **Activate Paste Stack** global shortcut: default **⇧⌘C** (keyCode 8 'c' + ⇧⌘) [B][R].
- Opens a floating panel `PasteStackWindow`: an NSPanel titled **"Paste Stack"**, ~264×438 content, frame autosave `com.wiheads.paste.paste-stack-frame` [R][S]. Its contents:
  - Close button (left).
  - **Stack direction** toggle (`icon.sort-up` / `icon.sort-down`, `StackDirection` = `top` default / `bottom`, key `pasteStackDirection`).
  - Table of snippets (`PasteStackSnippetCell` with type icon `icon.text`/`icon.link`/`icon.file`/`icon.unknown`).
  - Placeholder **"Empty"** when there are no snippets.
- **Behaviour** [B][U]:
  - While the stack is open, each copy is appended to it.
  - The stack registers a temporary global hot key **⌘V** (`pasteStackPasteShortcut`). Each ⌘V puts the next snippet (from the top or bottom, per direction) on the pasteboard and pastes it into the frontmost app (direct paste), then removes it from the stack.
  - Rows support a swipe/row action **Delete** (`tableView:rowActionsForRow:edge:`) and Deselect All.
  - Closing the panel (×) ends stack mode and releases ⌘V.
- **Super Paste notes.** ⌘V is taken only while the stack holds a snippet (an open, empty stack leaves ⌘V to the
  app), pasting the last snippet ends the stack, Esc ends it once the panel was clicked, and the empty panel explains
  itself ("Copy several things, then paste them in order with ⌘V." / "Copy something to start. Esc to close.").

## 4. The main UI: the strip panel

### 4.1 Window

- **Opening.** **Activate Paste** global shortcut, default **⇧⌘V** (keyCode 9 + ⇧⌘, stored as JSON `{"keyCode":9,"internalModifiers":1179648}`) [B][R]. Also opened by clicking the menu bar icon and by reopening the app [U].
- Global shortcuts are registered with Carbon `RegisterEventHotKey` (`GlobalShortcutMonitor`, "Carbon hot key is already held by another caller") [S][B].
- **Window class.** `MainWindow` is a borderless, non-activating-style **NSPanel** spanning the active screen's width at the bottom (Paste's "strip") [B][U on edge and width].
- **Height.** Default **332 pt**, clamped to **252–412 pt**, resizable with a top `ResizeHandle` (rounded on drag). Persisted with autosave name `PasteAppMainWindow_NSWindowFrameAutosaveName` [B].
- **Screen.** Opens on the screen of the current focus. `originalScreen` is tracked, and `windowDidChangeScreen` re-lays out the panel [B][U].
- **Closing.**
  - When the panel resigns key (`windowDidResignKey` → close), unless suppression is pending (e.g. while a menu, sheet, popover or preview is open) [B].
  - Esc (`cancelOperation:`) first clears search or closes the preview, then closes the strip [B][U on the order].
  - Opening and closing use transitions (`transitionGeneration`, `fade`, `transform`, `bounce`) [S][B].
- **ClosedStateManager** restores state between openings: selected list (`selectedListIdentifier`) and focus [B][U].
- **Screen sharing.** If **Show During Screen Sharing** is off, the panel's `sharingType` is set so it is hidden from screen sharing and recording. Key `isScreenSharingContentVisible`, default **true** [B][S].

- **Super Paste: hot corner.** Resting the pointer for 150 ms within 2 pt of a screen corner (bottom-left by
  default; Settings › General offers the four corners or Off) slides out a 220 × 70 peek with the three latest
  cards and the activation shortcut; a click on it opens the strip. The peek never takes keyboard focus, stays while
  hovered, hides 0.6 s after the pointer leaves, fades instead of sliding under Reduce Motion, doesn't show while
  the strip is up, while a button is held or over a full-screen app, and is off for a corner macOS's own Hot
  Corners use (`com.apple.dock wvous-*-corner`).

### 4.2 Layout (top to bottom)

1. **Toolbar** (`Toolbar`):
   - **Search bar** (magnifier). Typing filters.
   - **Filters button** (tooltip "Filters (⌘F)").
   - **Tab bar** (`TabBar`): **Clipboard** history tab (icon `clock.arrow.circlepath`), optional **Suggestions** tab (Intelligent Clipboard, §12), then one tab per **pinboard** (coloured circle `circlebadge`, shared pinboards marked).
   - "+" **Create Pinboard**.
   - Overflow (app) menu.
   - Tab tooltip: "<name> (⌘←, ⌘→ to navigate)" [S][B].
2. **Notification bar** (`NotificationBar`): inline status chips [S][B].
   - **Paste Paused** "Paused until HH:mm" + **Resume**.
   - **Syncing** / sync status.
3. **Item collection** (`ItemCollectionView`, horizontal `CollectionView` of cards, `NoShiftHorizontalScrollView`).
4. **Sidecar** (`PasteCoreUI.Sidecar.CollectionView`): a card column for in-app notifications (§11) and shared-pinboard collaborators [B].

### 4.3 Cards

| Part | Content |
|---|---|
| **Header** (`ItemCell.HeaderView`) | Source app icon (fallback `icon.unknown-app`), title (custom title if renamed, else the app name), relative date (`ItemDateFormatter.Style`: relative / relativeAbbreviated / absolute). Background is the app's `rawColor` [B][R]. |
| **Body** | Per type: text excerpt (rich text rendered), link (preview image + title + domain), image thumbnail on a checkerboard, colour swatch, file icon or Quick Look thumbnail [B]. |
| **Footer** (`ItemContent.Footer`) | Text: "N characters" (plural). Image: "W × H" (`SizeLabel`). Files: "File" / "%d files" + size. Link: URL/host. Colour: hex/RGB toggle (`ColorFormatView`) [S][B]. |
| **Badges** | Quick-paste number (while the modifier is held). `LockView` for read-only shared-pinboard items [B][U]. |

### 4.4 Keyboard (strip focused)

| Key | Action | Evidence |
|---|---|---|
| ← / → | Move selection | [B `PasteUI.Key` enum] |
| ⇧← / ⇧→, ⇧-click, ⌘-click | Extend / toggle multi-selection | [U] |
| Home / End / PageUp / PageDown | Jump to first / last item, page | [B Key enum] |
| ⌘A | Select All | [B `selectAll:`][S] |
| Return | Paste the selection (to active app or clipboard, §3.1) | [S][B] |
| ⇧Return (plain-text modifier + Return) | Paste as plain text | [B] |
| ⌘1…⌘9 (quick-paste modifier) | Quick Paste the Nth item | [B][S] |
| Space | Preview (toggle) | [B: context-menu key equivalent " "] |
| ⌘C | Copy to clipboard (no paste) | [B] |
| ⌘E | Edit | [B] |
| ⌘R | Rename (set title) | [B] |
| ⌘O | Open (link in browser, file in its app) | [B][S "use ⌘O shortcut"] |
| ⌫ (with the context-menu modifier, probably ⌘⌫) | Delete selected items (undoable) | [B: char 0x08][U modifier] |
| ⌘Z / ⇧⌘Z | Undo / Redo (deletes, edits; also inside search) | [B] |
| ⌘F | Show search filters | [B] |
| ⌘← / ⌘→ | Previous / next pinboard (configurable) | [B][R] |
| ⌘V, ⌘G | Handled by `ItemCollectionView.performKeyEquivalent`. Exact actions unknown | [B][U] |
| ⌘N | New Text Item (app menu) | [B] |
| ⌘, | Settings | [B] |
| Esc | Clear search / close preview / close strip | [B][U order] |
| Typing printable characters | Starts search (type-to-search: `MainView.insertText:` forwards to the search field) | [B] |

### 4.5 Mouse and drag-and-drop

- Click selects. Double-click pastes [U]. Right-click opens the item context menu (`rightMouseDown:`) [B].
- **Drag out** of the strip into other apps (`CollectionView+Dragging`) [B].
  - Images are written to a temporary file in an `images` temp folder named with `yyyy-MM-dd HH.mm.ss`, so receivers that want a file URL get one [S].
- **Drag onto a pinboard tab** to pin (`TabBarCell draggingEntered/performDragOperation`) [B]. Onboarding copy: "Pin items to pinboards using the context menu or drag-and-drop." [S]
- **Reorder inside a pinboard** by drag. Order is stored in `ItemEntity.displayOrderInPinboard` [R][U on gesture].
- **Reorder pinboard tabs** by drag. Order is stored in `ListMetadataEntity.index` (`ReorderableStackView`) [R][B].

### 4.6 Item context menu

Built by `ItemCollectionView.ContextMenu`, in code order [B][S]:

| Item | Key equiv. | Notes |
|---|---|---|
| Open / "Open in %@" / "Open with %@" | ⌘O | For links and files. Opens in the default browser or app |
| Reveal in Finder / "Show in %@" | — | File items |
| Paste to %@ | ↩ | Target app name or "current app" |
| Paste as Plain Text | ⇧↩ (plain-text modifier) | |
| Copy | ⌘C | Plus "Copy as Plain Text" [S][U placement] |
| Edit | ⌘E | Opens the preview in edit mode |
| Rename | ⌘R | Edits the card title |
| Delete | ⌫ (+modifier) | Multi-select title "Delete %d items?" [S] |
| Pin › (submenu "Pin to") | — | Lists pinboards + **Create Pinboard**. "Unpin" when already pinned |
| Share › | — | `NSSharingServicePicker` |
| Preview | Space | |

Multi-selection shows "%@ Selected" and supports **Select All / Deselect All** [S].

### 4.7 Search

- **Field.** `SearchField` is an `NSTextView`-based input with inline **filter tokens** (`FilterTextAttachment`). It has its own undo manager (⌘Z / ⇧⌘Z) and coalesces typing [B].
- **Query model.** `SearchQuery.components = [.token(String) | .filter(type, value)]` [B].
  - `FilterType` = **app, type, title, date, device, pinboard**.
  - Tokens are AND-ed. Each token matches title or content, case- and diacritic-insensitive, word-prefix (`*tok*`cd / `cwdt`) [B].
  - Example from the docs: "mail link meeting slides" → app = Mail, type = link, text "meeting slides" [S].
- **Suggestions.** `FilterSuggestionsMenu` (floating list under the field) suggests filters while typing: matching app names, types, pinboards, devices, and dates such as **Today**, **Last 30 days** or explicit ranges "X to Y". Navigate with ↑/↓, accept with Return, close with Esc [S][B].
- **Filter browser.** **Filters** popover (`FilterBrowserPopover`, title "Filters") with sections **Type, App, Date, Device, Pinboard** [S][B].
  - Each section collapses to a few items, then shows "_more" to expand (`collapsedItemLimit`).
  - Selecting an item toggles a filter token.
  - Already-applied filters are hidden (`hideAppliedFilters`).
- **Engine.** CoreSpotlight `CSSearchableIndex` named `com.wiheads.paste.items` [S][B]:
  - Custom attributes `pasteApp`, `pasteType`, `pasteDevice`, `pastePinboard`, plus `title`, `textContent` and `contentDescription`.
  - Date filters use `contentModificationDate` ranges.
  - Hits are mapped back to Core Data by `identifier IN %@`.
  - Images get **OCR via Vision** (`SpotlightIndexer+OCR`) so text inside images is searchable. OCR is throttled (`ocrCooldown`, thermal and low-power checks).
  - The indexer is incremental via persistent-history tracking (`indexHistoryTokenData`). It re-indexes fully on schema or store change (`indexedStoreID`, `indexingState`) and handles system reindex requests.
  - Super Paste replaces this with SQLite FTS5 (§21).
- **Empty states.** "History is empty", "Pinboard is empty", "Nothing found" [S].

### 4.8 Preview and editing

- **Preview popover.** Space or the menu opens a `PreviewPopover` anchored to the card. It is **detachable**: dragging it out turns it into a standalone `ItemPreviewWindow` panel; several can be open (`ItemPreviewWindowManager.entries`) [B].
- **Preview header.** Click the title to rename it (⌘R). Buttons **Edit**, **Pin**, **Share**, close [S][B].
- **Editor titles.** "Edit Text", "Edit Link", "Edit Color", "Edit Image", "Edit Item" [S].
  - Buttons **Save** (⌘S) / **Cancel**, toolbar "Save changes" / "Discard changes" [S][B].
- **Text editor** (`PasteUI.TextEditor`):
  - Rich text with **Bold, Italic, Underline, Strikethrough**, and **Writing Tools** (macOS Apple Intelligence).
  - Meta line shows "N characters · N words · N lines" (plural strings) [S][B].
- **Image editor:**
  - **Rotate Left** (⌘L?) and **Rotate Right** (⌘R?) [S][B][U on modifier].
  - **Remove Background** / **Restore Background** using Vision foreground masking (`ImageBackgroundRemovalState`) [S][B].
  - Zoomable image view [B].
- **Files** use Quick Look (QuickLookUI) and **Reveal in Finder** [S][B].
- **Unpreviewable items** show "Preview unavailable" [S].
- Editing content re-runs type detection (MCP doc) [S].

### 4.9 New text item

- App menu **New Text Item** (⌘N) opens `CreateItemWindow` with a text editor and buttons **Create** (⌘S) / Cancel / "Discard changes" [S][B].
- The new item goes to the currently shown list (history or pinboard) [B: `CreateItemViewModel.listIdentifier`].

### 4.10 Undo

The strip window returns a content undo manager (`windowWillReturnUndoManager`), shared with `PersistentStack.undoManager`. Deletes, edits and pin changes are undoable with ⌘Z while the strip is open [B][U on scope].

## 5. Pinboards

- **Lists.** `ListType` = `unknown, clipboard, pinboard` [B].
  - The single clipboard-history list holds `ClipboardAttributes(capacity)`.
  - Pinboards hold `PinboardAttributes(colorCode)` with `Color` = **red, orange, yellow, green, blue, purple, pink, gray**, chosen with an inline `ColorPicker` in the tab menu [B].
- **Pinned vs history.** `ItemEntity` has one `list` relationship [R]. A history item has `list == nil` and a `timestamp`. Pinning sets `list` to the pinboard. The item keeps its `timestamp`, so it still appears in history, and it is protected from pruning and Erase History [B][S MCP docs]. An item can be "pinned-only" (no timestamp) when created directly in a pinboard. An item belongs to at most one pinboard [R].
- **Create.** "+" or "Create Pinboard" opens an inline new tab named "Untitled", in edit mode (title "New Pinboard") [S][B]. Also via App Intents, MCP and the Pin submenu.
- **Rename.** Double-click the tab or tab menu **Rename** (inline `TabBarCellLabel` text field, Return commits, Esc cancels) [B].
- **Recolour.** Tab context menu colour row [B].
- **Reorder.** Drag tabs [B].
- **Delete.** Tab menu **Delete** → "Delete "%@"?" / "The Pinboard and all its content will be deleted. This action cannot be undone." [S]
- **Tab context menu** (`TabBarCellMenu`): Rename, colour picker, Share Pinboard / Manage Shared Pinboard (iCloud sharing, drop), **Erase History** (Clipboard tab only), Delete, Remove (leave a shared pinboard) [S][B].
- **Navigation.** **Show next Pinboard** default **⌘→**, **Show previous Pinboard** default **⌘←** (Shortcuts pane) [B][R].
- **Initial content.** On first run Paste seeds a **"Useful Links"** pinboard [S `general.useful-links`][B `InitialContent`]:
  - Links: *Getting Started — Start using Paste*, *Help and Support — Explore Help Center*, *Stay Tuned — Follow Paste on X*.
  - Welcome text items: *Welcome Aboard*, *Keep*, *Organize*, *Search*, with macOS bodies (see strings.md).
  - Super Paste can seed its own short welcome pinboard or nothing.
- **Shared pinboards** (CloudKit `CKShare`, roles Owner/Editor/Viewer, "Invited", "%d people collaborate", duplicate-on-pin alerts) → **drop** [S][B].

## 6. Menu bar item and app menu

### 6.1 Status item

- `StatusItem` shows when **Show in Menu Bar** is on (`isStatusItemEnabled`, default **true**) [S][B].
- The icon animates on copy (17 frames). It shows `StatusItem/paused` while paused [R].
- Click (`statusItemAction`) toggles the strip. The app menu is shown on right-click or ⌥-click [B][U on the button mapping].

### 6.2 App menu (`AppMenuProvider`)

Shared by the status item and the strip's overflow button. Order follows the code; grouping is [U]:

1. **About Paste**
2. **New Text Item** ⌘N
3. **Settings…** ⌘,
4. **Pause** submenu (§6.3) / **Resume**
5. **Help** submenu: Getting Started, Keyboard Shortcuts, Help Center, Product Updates, Feature Request, Contact Support, Start Diagnostics / Stop Diagnostics
6. (Paste on Twitter — drop)
7. **Quit Paste** ⌘Q

[S][B]

An item with key equivalent ⌘T exists in this menu. What it does was not resolved [U].

### 6.3 Pause

- Durations **15 minutes, 30 minutes, 1 hour, 3 hours, 8 hours** [B: constants 900/1800/3600/10800/28800 s]. Titles use "Pause for %@" [S].
- An indefinite **Pause Paste** option exists [S][U].
- While paused:
  - OSD "Paste Paused". The notification bar reads "Paused until %@" (HH:mm) with **Resume**.
  - The status icon switches to the paused image.
  - On expiry or Resume, OSD "Paste Resumed" [S][B].
- Pause is not persisted across relaunch [U].

## 7. Settings window

`SettingsWindowController` is an `NSSplitViewController` with a sidebar (`SidebarView`) and panes. `SettingsPaneID` = **general, privacy, shortcuts, intelligence, subscription, help** [B].

Pane titles: "General", "Privacy", "Shortcuts", "Intelligence", "Subscription" (drop); the help pane is labelled "Help" [S][U]. Each row is a `SettingsRowView(title, subtitle, content)`, grouped in `GroupBoxView`s [B]. Rows are listed below in the order the code builds them; the visual order is [U].

### 7.1 General

| Control | Label (verbatim) | Default | Evidence |
|---|---|---|---|
| Toggle | Open at login | off until onboarding sets it | [S][B] |
| Toggle + status | iCloud sync. Status: "Syncing", "Synced <date>", "never", "Check your iCloud settings", errors "iCloud storage quota exceeded" / "iCloud account unavailable" / "iCloud error (code %@)" / "Network error". Turning it off asks "Turn Sync Off?" — "Your local and iCloud data remain unchanged…" with **Keep Sync On** / **Turn Sync Off** | `isSyncEnabled` false | [S][B] → replaced by Folder Sync |
| Toggle | Show in Menu Bar | on | [S][B] |
| Toggle | Sound effects | on | [S][B] |
| Radio group "Paste Items" | **To active app** — "Paste selected items directly to the application you are currently using." / **To clipboard** — "Copy selected items to the system clipboard to paste manually later." Images `copy-to-app`, `copy-to-clipboard`. Button **Allow Accessibility Access** when needed | To active app | [S][R][B] |
| Checkbox | Always paste as Plain Text | off | [S][B] |
| Slider "Keep History" | 5 stops: Day(s) / Week(s) / Month(s) / Year / **Forever** (§2.9). Unlimited tooltip | not determined (written by onboarding) [U] | [S][B] |
| Button | Erase History… → confirmation alert | — | [S][B] |

### 7.2 Privacy

| Control | Label | Default |
|---|---|---|
| List + "+"/"−" | **Ignore Applications** — "Do not save content copied from the applications below." Empty state "No items". "+" opens an `NSOpenPanel` at `/Applications` with prompt "Choose" | 14 password managers (§2.3) [S][B] |
| Toggle | **Ignore confidential content** — "Do not save passwords and sensitive data when detected." | on [U] |
| Toggle | **Ignore transient content** — "Do not save temporary data generated by other apps." | on [U] |
| Toggle | **Generate Link Previews** — "Download web content for previews; may activate one-time or analytics-sensitive links." | on [B] |
| Toggle | **Show During Screen Sharing** — "Allow Paste to appear to others when you share your screen." | on [B] |

### 7.3 Shortcuts

| Row | Default | Evidence |
|---|---|---|
| Activate Paste | ⇧⌘V | [B][R] |
| Activate Paste Stack | ⇧⌘C | [B][R] |
| Show next Pinboard | ⌘→ | [B][R] |
| Show previous Pinboard | ⌘← | [B][R] |
| Quick Paste | modifier popup (default ⌘) + "1...9" | [B][S] |
| Plain Text mode | modifier popup (default ⇧) | [B] |
| Button | **Reset shortcuts to default** → "Are you sure you want to reset all shortcuts to their default values?" → Reset / Cancel (then **Restart Paste**) | [S][B] |

**Shortcut recorder** (`ShortcutRecorderButton`) [S][B]:

- States: shows the shortcut, "Recording", or "None". "Remove" clears it.
- Validation errors (verbatim in strings.md):
  - Option-only combos warning before macOS 15.2.
  - "already used by the menu item '%@'".
  - "already used by a system-wide keyboard shortcut…" (checked against `kHISymbolicHotKey*` system hot keys).
- Storage: Codable JSON `{"keyCode": Int, "internalModifiers": UInt}`. `internalModifiers` uses `NSEvent.ModifierFlags` raw bits (⌘ 0x100000, ⇧ 0x20000, ⌥ 0x80000, ⌃ 0x40000) [R].

### 7.4 Intelligence

**Clipboard section:**

- **Intelligent Clipboard** toggle — "Get suggestions for what you're about to paste, based on what you're working on. Everything stays on your Mac." `isPicksEnabled`, default true, but it only runs when supported.
- When Apple Intelligence is unavailable: "Requires Apple Intelligence".
- **Allow Screen Access** button when Screen Recording is missing.

[S][B]

**MCP & AI tools section:**

- **Enable MCP** toggle — "Allow AI apps to connect to Paste. Only apps you approve can access your clipboard items and pinboards." `isMCPEnabled`, default **false** [S][B].
- **MCP Server Port**: shows the port (default **39725**, key `mcpPort`) and a **Change** button.
  - Warning: "Changing the port disconnects and removes all connected AI tools."
  - Failure: "Couldn't change the port" (with rollback) [S][B].
- **Connected AI Tools** list:
  - Each row shows "Last used %@" / "Never used" and a **Disconnect…** button.
  - Disconnect confirms with "Disconnect "%@"?" — "%@ will no longer be able to access Paste."
  - Empty state: "Nothing connected yet".
- **Connect AI Tool…** menu: the client kinds in §14.4 plus **Custom Tool**.
  - Custom asks for a name ("Add an AI Tool", placeholder "Name (e.g. My AI Tool)", Create / Cancel).
  - The connection sheet "Connect %@" shows per-client instructions, **Copy** buttons, **Connect** / **Install Extension**, and **Done** [S][B].

### 7.5 Help / About

- `AboutView` shows the app icon, "Paste", "Version %@ (build)", social buttons (X/Twitter, Facebook, Mastodon, LinkedIn), Privacy Policy, Terms of Use, and "Made with {icon:heart} by Paste Team" [S][B][R].
- The Help pane lists: Getting Started, Keyboard Shortcuts, Help Center, Product Updates, Feature Request, Contact Support [S][U on pane vs menu placement].

### 7.6 Subscription (drop)

"One Subscription, Endless Productivity", "You're not subscribed yet.", Manage. Setapp builds point to `my.setapp.com/subscription` [S].

## 8. Onboarding (macOS)

`PasteOnboarding` uses a `NavigationContainerView` with screens `intro` → `setup`. State is persisted as `onboardingState` = `{"inProgress": {"navigationPath": [...]}}` or `{"completed": {}}`, and `isOnboardingCompleted`. A `onboarding_screen_presented` analytics event fires per screen [B][R].

1. **Introduction** (`IntroductionView.macOS`) [S]:
   - Animated icon.
   - Title "A Better Way to Copy and Paste".
   - Subtitle "Paste is a time machine for your Clipboard that lets you instantly find anything you've ever copied and use it whenever you need it again."
   - Button **Get Started**.
2. **Quick Start** (`SetupView`) — "Set up and start using Paste." [S][B]

   | Row | Title / subtitle | Control |
   |---|---|---|
   | Run in background | "Open at login and always keep running" | toggle (`openAtLoginIsEnabled`) |
   | iCloud sync | "Securely sync your data across all devices" | toggle (`syncIsEnabled`) |
   | Activation shortcut | "Instantly access Paste in any app" | shortcut recorder (⇧⌘V) |
   | Clipboard history | "How long to retain copied content" | history slider + unlimited tooltip |

   Button **Continue** → completes onboarding (`onComplete(shortcut, openAtLogin, sync)`).
3. **Permissions** are requested on demand, not as fixed onboarding pages (§9). The `Configuration.onboarding` variants of the Accessibility and Pasteboard views exist, so a permission step can be embedded during onboarding [B].
4. After completion, seed the initial content (§5) and show the strip or a hint [U].

## 9. Permissions

| Permission | Screen (verbatim title / subtitle) | Buttons | Mechanism |
|---|---|---|---|
| **Accessibility** (direct paste) | "Paste to Any App" / "To paste directly into other apps, allow Paste to use the accessibility features of your Mac in System Settings." | **Open System Settings** / **Allow Access**, **Not Now**, **I'm Having an Issue** (→ help article "can't paste to other apps") | `AXIsProcessTrustedWithOptions` prompt and opening `Privacy_Accessibility`. Polls until granted. `isPotentialIssueDetected` shows help when the toggle is on but trust is still false (stale TCC entry) [S][B] |
| **Pasteboard access** (macOS 26) | "Allow Pasteboard Access" / "Paste needs access to your clipboard to save what you copy and keep everything in sync automatically." | open `Privacy_Pasteboard` | [S][B] |
| **Screen Recording** (Intelligent Clipboard only) | "Get Suggestions as You Paste" / "To get suggestions for what you're about to paste, allow Paste to see your screen in System Settings. Everything stays on your Mac." | **Open System Settings**, **Help** | `Privacy_ScreenCapture`. Usage string in Info.plist [S][R] |
| **Paste to other apps** prompt | "Do you want to paste directly to %@?" | see §3.1 | [S] |

## 10. What's New

- `PasteWhatsNew.WhatsNewView` is shown once after an update (`lastLaunchedVersion`). Media is loaded from `hub.pasteapp.io/r/whats-new/media/macOS/` [S][B].
- 7.0 content: title "Intelligent Clipboard", body "Paste now suggests the item you'll most likely paste next, based on what you're working on." CTAs: **See it in action**, **Learn More**, **Rate on App Store**, **Continue** [S].
- A separate V5 screen covers the Paste 4→5 data migration (progress, success, warning, failure) [S]. Drop.
- Super Paste: a simple local "What's New" sheet driven by the bundled version, optional.

## 11. In-app notifications (sidecar)

`InAppNotificationRepository` stores dismissible cards (`inAppNotifications` key). Each card is `{id, symbol, title, description, primaryAction, secondaryAction}`, with actions as `paste://` routes [B][S].

| Card | Keep? |
|---|---|
| **Enable Direct Paste** — "Paste items directly to any app." [Enable] | Keep |
| **Open at Login** — "Automatically launch Paste when you restart your Mac." [Enable] | Keep |
| **Run in Background** — "Ensure Paste is always running." [Enable] | Keep |
| Enable iCloud Sync | Replace with Folder Sync |
| Meet Intelligent Clipboard | Drop |
| Paste in Liquid Glass | Drop |
| Shared Pinboards | Drop |
| Trial, offer and rate cards | Drop |

## 12. Intelligent Clipboard ("Picks" / Suggestions tab)

New in 7.0. Needs macOS 26, Apple Intelligence (FoundationModels) and Screen Recording [S][B].

- **When the strip opens**, `PicksProvider`:
  1. Captures the destination window (the app you're about to paste into, *not* frontmost because the strip is) with ScreenCaptureKit.
  2. Asks the on-device model to classify the input field. Prompt: "You are shown a screenshot of the window a person is about to paste text into… Which kind of input is the pasted text most likely headed for?"
  3. The answer is a `FieldKind` = url, search, password, chat, code, terminal, cell, canvas, text, unknown.
  4. Also uses the destination bundle id (built-in hints for terminals iTerm2/Ghostty/kitty/WezTerm, editors Cursor/Sublime, Freeform, Messages, Telegram, WhatsApp, and a desktop LLM chat client) and `isSecureInput`.
- **Item classes.** Each captured text is classified once into `ItemClass` (link, email, phone, date, address, money, trackingNumber, personName, organizationName, code, command, filePath, message, prompt, quote, secret, unclassified):
  - First by regex rules: JWT `eyJ…`; API keys `sk-`, `ghp_/gho_`, `xox?-`, `AKIA…`; `password=`-style assignments; `Bearer`/`Basic` auth; UUID/hex/base64; paths; tracking numbers; currency amounts.
  - Then by the language model ("Classify the kind of text a person copied to their clipboard… Use secret for passwords, API keys, tokens and private keys…").
  - Results are stored in `item-classes.jsonl`.
- **Ranking.** `PickRanker` with `PickWeights` (recencyRank, pasteCount, pairPasteCount (source→destination app), taskRhythm, fieldAffinity, threshold, stripSize):
  - Paste events (item, source app, destination app, time) are journalled to `paste-events.jsonl`.
  - Every open, the shown candidates and the choice (from strip / list / search) are logged to `paste-picks.jsonl`.
- **UI.**
  - Suggestions tab with a Metal "glow" (`IntelligenceGlowView`) and an animated icon (`PicksIconView`).
  - Placeholder asks for screen access ("Get suggestions for what you're about to paste… Allow Screen Access") or shows "No suggestions".
  - "Turn off Intelligent Clipboard?" — "You can turn it back on any time in Paste Settings, under Intelligence."
- **Super Paste:** defer. A non-AI version is possible: rank by recency, paste count and source→destination pair counts from a local journal. The secret regexes are worth reusing as an optional "detect secrets" privacy filter.

## 13. App Intents (Shortcuts) [R Metadata.appintents][B]

| Intent | Parameters | Output | Notes |
|---|---|---|---|
| **Create Item** — "Create a new item in the specified list using the content passed as input." | `content`: String, `list`: ListIntentEntity | String | Summary "Create item with ${content} in ${list}". Errors: Content is empty / List not found / Can't create item. App Shortcut with 7 Siri phrases ("Create ${applicationName} item", …, "Add to ${applicationName}"), symbol `square.and.pencil` |
| **Create Pinboard** — "Create a pinboard with the name provided as input." | `name`: String | ListIntentEntity | Error: Name must not be empty |
| **Get Item at Index** — "Retrieve an item from a specified position in a list." | `index`: Int ("Item Index"), `list` | String | Errors: List not found / Index out of bounds |
| **Get Latest Item** — "Retrieve the latest item of a specified type from a list." | `type`: ItemIntentType {text "Text", link "Link"}, `list` | String | "Get latest ${type} item from ${list}" |

- **ListIntentEntity**: `{id, displayString, imageName, color}`. The default query `ListIntentQuery` lists Clipboard History (`clock.arrow.circlepath`) plus pinboards (`circlebadge.2.fill`, tinted).
- None of the intents open the app. Shortcut tile colour index 14.

## 14. MCP server (`PasteMCP`)

### 14.1 Transport

- **Server.** Local Streamable-HTTP MCP server (Hummingbird on swift-nio) bound to **127.0.0.1:39725** (configurable). Endpoint `POST/GET/DELETE /mcp` with `Mcp-Session-Id` sessions and SSE. Server name "Paste", version 1.0.0 [S][B].
- **Authorization.** OAuth 2.1, so any client can connect after user approval:
  - `/.well-known/oauth-protected-resource` and `/.well-known/oauth-authorization-server`.
  - **Dynamic Client Registration** at `/register` (requires `client_name` and `redirect_uris`).
  - `/authorize` serves an HTML consent page "Connect <client> — <client> wants to use Paste on this Mac. This will allow access to: View and manage your clipboard items; View and manage your pinboards" with Cancel / Connect. It is CSRF-protected, with a strict CSP.
  - `/token`: `authorization_code` grant only, **PKCE S256 required**.
  - `/revoke`: `access_token` hint only.
  - Clients and token **hashes** are kept in `~/Library/Application Support/…/mcp/clients.json`, and DCR registrations in `dcr.json`. Each `Client` = `{id, name, kind, createdAt, lastUsedAt, tokenHash, oauth?}`.
  - A static bearer **token** mode exists for manual/custom clients and the stdio bridge [S][B].
- **Stdio bridge.** `Contents/MacOS/paste-mcp-stdio` is a tiny universal binary. It reads `MCP_URL` and `MCP_TOKEN` from the environment and proxies stdio JSON-RPC to the HTTP endpoint (`application/json, text/event-stream`). It is used by the `.mcpb` bundle that Paste generates (`manifest.json`, `paste-icon.png`) [S][B].
- **Server instructions:** "Paste is a clipboard manager for macOS. Use these tools to search and read clipboard history, save new items, and manage Pinboards on the user's behalf." [S]

### 14.2 Tools (names exact; parameter names as in the JSON schema)

| Tool | Params | Result |
|---|---|---|
| `search` | `query?`, `type?` (text, image, file, color, link), `app?`, `device?`, `title?`, `pinboard_id?`, `date_from?`, `date_to?` (ISO-8601; date-only covers the day; `date_from` must precede `date_to`), `limit?` (default **20**, max **100**) | `{items: [MCPItem], hasMore}`, newest first. Resolves at most the 100 most recent matches |
| `read_item` | `id` | `ReadItemContent`: text (verbatim, truncated at N chars with `truncated` + `totalLength`), link URL, colour `#RRGGBB`, file paths one per line, or the **image** itself (downscaled, re-encoded; ~1024 px [U]) |
| `create_item` | `content`, `list_id?` (private pinboard only) | MCPItem. Auto type detection. Never writes the system clipboard. With `list_id`: pins the existing history item if the content matches, else creates a pinned-only item |
| `update_item` | `id`, `title?`, `content?` (at least one; content not allowed for image/file) | MCPItem |
| `delete_item` | `id`, `confirm?` | Two-step: preview message unless `confirm: true`. `{deleted, item, message}` |
| `list_pinboards` | — | `{pinboards: [MCPPinboard]}` |
| `create_pinboard` | `name` (trimmed, non-empty) | MCPPinboard |
| `rename_pinboard` | `id`, `name` | MCPPinboard |
| `delete_pinboard` | `id`, `confirm?` | Two-step. Pinned items stay in history. `{deleted, pinboard, message}` |
| `add_item_to_pinboard` | `item_id`, `pinboard_id` | MCPPinboard (idempotent) |
| `remove_item_from_pinboard` | `item_id`, `pinboard_id` | MCPPinboard |

- `MCPItem` = `{id, type, preview, timestamp?, app?, device?}`. `MCPPinboard` = `{id, name, itemCount}`.
- Errors (`ToolError`): pinboardNotFound, pinboardSharedNotSupported, clipboardItemNotFound, invalidName, invalidContent, invalidDate, invalidArguments. Message texts are in strings.md [S][B].

### 14.3 Settings and lifecycle

- Server state is `off` / `running(url)`. Start phases queued → binding → listening, with a readiness probe [B].
- Changing the port restarts the server, revokes all clients, and rolls back on failure [S][B].
- Analytics events `mcp_client_connected` and `mcp_tool_used` [S]. Drop.

### 14.4 Client connection kinds (`Client.Kind`)

| Kind | How Paste connects it |
|---|---|
| `desktopAssistant` | Builds and opens `paste.mcpb`. "…Install the Paste extension there to finish connecting." |
| `cliAssistant` | Shows the CLI command `client mcp add --transport http --scope user paste <url>`, then "…type /mcp, then select Paste and authenticate." |
| `codex` | `codex mcp add paste --url <url>` |
| `cursor` | Deep link `cursor://anysphere.cursor-deeplink/mcp/install?name=Paste&config=…` |
| `vscode` | Deep link `vscode:mcp/install?{"name":"Paste","type":"http","url":…}` |
| `windsurf` | Writes `~/.codeium/windsurf/mcp_config.json` (`{"mcpServers":{"paste":{"url":…}}}`) |
| `custom` | Server URL + Token. Snippet in JSON or TOML (`ConfigFormat`) |

[S][B]

## 15. URL scheme `paste://` [R Info.plist][S]

Registered scheme `paste` (`CFBundleURLName com.wiheads.paste`). Routes found:

| Route | Action |
|---|---|
| `new-text-item` | Open the New Text Item window |
| `search` | Open the strip with search |
| `list/<id>` | Open the strip on a list |
| `preview-item/<id>` | Open an item's preview |
| `edit-item/<id>` | Open an item in edit mode |
| `preferences` | Open Settings |
| `about` | Open About |
| `enable-direct-paste` | Notification action |
| `enable-open-at-login` | Notification action |
| `enable-run-in-background` | Notification action |
| `enable-icloud-sync` | Notification action |
| `enable-keyboard`, `allow-full-access`, `scan-document` | iOS |
| `activate-license`, `paywall`, `start-free-trial`, `show-offer-paywall` | Licensing (drop) |

Super Paste should support `superpaste://new-text-item|search?q=|list/<id>|preview-item/<id>|edit-item/<id>|settings[/pane]`.

## 16. Import / export

None found [S]. The only data-transfer paths are iCloud sync and the Paste 4→5 store migration (`Paste.db` → `db.sqlite`). **Gap.** Super Paste should add JSON/ZIP export and import (also useful as a migration path).

## 17. iCloud sync (Paste's implementation, to be replaced)

- **Engine.** `PasteCore.SyncEngine` wraps **CKSyncEngine** for both the private and shared databases (`CKSyncEngineState.2/.3` persisted in defaults). Container `iCloud.com.wiheads.paste.container.v1`; the legacy V4 zone is deleted after migration [S][R].
- **Mapping.** Each syncable managed object (`SyncableManagedObject`) maps to a CKRecord. `ObjectMetadata` keeps `cloudKitRecordName/ZoneName/ZoneOwnerName`, archived system fields (`cloudKitRecordData`), and `isPendingDeletion` [R][B].
  - Pasteboard payloads go up as `CKAsset` (`SyncAssetData`).
  - Children whose parent is not yet confirmed wait in `ObjectPendingMapping` ("DEFER … parent reference unavailable").
- **Change tracking.** Local changes come from Core Data persistent-history transactions. Remote changes merge into the view context [S][B].
- **Conflicts.** `SyncConflictResolver` compares `updatedAt` ("server won, accepting" / "local won, retrying") [S].
- **Recovery and account changes.** Repair and heal paths: missing checksums, partial records, orphaned metadata. It also handles iCloud account sign-in, sign-out and switching, zone deletion, quota exceeded, and network errors [S].
- **Sharing.** Pinboards are shared via `CKShare` (`ObjectShare`, `mirrorSharesOntoRoots`) [S][R].
- **Pushes.** APNs remote notifications trigger fetches [B].

**Super Paste replacement: end-to-end-encrypted folder sync** (any folder: iCloud Drive, Dropbox, Syncthing, NAS). Model it on the same concepts: per-record change log plus content-addressed blobs (§21).

## 18. Other system integrations

- **Handoff.** `NSUserActivity` type `com.wiheads.paste.activity` carries `{listId, itemIds, previewedItemId, isPreviewEditing}` to resume the same view on another device [S][R]. Drop (no iOS counterpart).
- **Spotlight.** Items are indexed in CoreSpotlight (§4.7). They may also surface in system Spotlight [U]. Optional for Super Paste.
- **Sharing.** Items can be shared via `NSSharingServicePicker`. Paste excludes some services for pinboard sharing (Messages window, Safari reading list, Notes, Freeform, Reminders, Shortcuts) [S].
- **Help links.** All point to `https://pasteapp.io/...`: `/help`, `/help/sync`, `/help/keyboard-shortcuts`, `/help/intelligent-clipboard`, `/help/shared-pinboards`, `/help/can-t-paste-to-other-apps`, `/help/paste-on-mac`, `/feature-requests`, `/contact`, `/updates`, `/blog`, `/privacy`, `/terms`, plus `utm_source=app` [S].

## 19. Privacy features (summary)

| Feature | How it works |
|---|---|
| Pause | 15 min / 30 min / 1 h / 3 h / 8 h, or until resumed |
| Ignore Applications | Password managers by default |
| Ignore confidential content | `ConcealedType` |
| Ignore transient content | Transient / AutoGenerated / TypeIt4Me / generator markers |
| Generate Link Previews | Can be turned off (network fetches) |
| Show During Screen Sharing | Can hide the strip from screen capture |
| Erase History | Keeps pinned items |
| Retention limit | §2.9 |
| On-device only | Intelligent Clipboard |
| Local-only MCP | 127.0.0.1, OAuth approval per client, revocable |

Not present: lock with password/Touch ID; auto-clear on sleep; per-item expiry of secrets. Candidates for Super Paste.

## 20. Licensing, Setapp and telemetry (drop all)

- **Setapp.** `Setapp.framework` (`SetappManager`), XPC to `com.setapp.ProvisioningService`, `setappPublicKey.pem`, vendor-API auth, desktop health metrics (`stats.setapp.com`), `SetappAI_URLSessionConnector` (Setapp's AI gateway), and `NSUpdateSecurityPolicy` for the Setapp agent [S][R].
- **PasteLicensingDirect.** License keys validated against `hub.pasteapp.io/api/licenses/{activate,validate}`. The license is cached in the Keychain with an offline fallback. A 7-day app-managed trial (`com.wiheads.trial`), a paywall, and "Activate Your License" [S].
- **App Store / StoreKit.** Paywall, plans (monthly/annual/lifetime/family), intro offers, restore. Strings only on this build [S].
- **PostHog analytics.** Project key `phc_eXJD…`. Events include app_launched, paste/copy interaction counters, weekly_usage_report, onboarding/permission funnels, paywall/checkout, MCP and intelligent-clipboard usage. Also feature flags, remote config, surveys, and session-replay plumbing. Data lives in `~/Library/Application Support/com.wiheads.paste-setapp/phc_*` [S][R].
- **Sentry** (+ SentryCrash/KSCrash), **PLCrashReporter** (PostHog crash reporting), **MetricKit** [S][B].
- **Marketing.** In-app trial/offer notifications, "Rate on App Store", "Leave review", "Paste on Twitter", social links, What's New media from `hub.pasteapp.io` [S].

## 21. Data model and storage

### 21.1 Locations [R]

| Path (under `~/Library/Application Support/com.wiheads.paste-setapp/`) | Content |
|---|---|
| `db.sqlite` (+ `-wal`, `-shm`) | Core Data SQLite store, model `v5Paste` **v11**. Persistent history tracking is on (tables `ACHANGE`, `ATRANSACTION`, `ATRANSACTIONSTRING`) |
| `.db_SUPPORT/_EXTERNAL_DATA/<UUID>` | Large blobs stored outside SQLite (Core Data "allows external storage" on `rawPasteboardItems` and `rawPreview`) |
| `paste-events.jsonl`, `paste-picks.jsonl`, `item-classes.jsonl` | Intelligent Clipboard journals |
| `phc_<key>/…` | PostHog state (drop) |
| `…/mcp/clients.json`, `…/mcp/dcr.json` | MCP clients (token hashes) and dynamic client registrations [S] |
| `backup/` | Damaged-store quarantine (§1.9) |
| temp `images/` | Drag-out image files |

Preferences are in `~/Library/Preferences/com.wiheads.paste-setapp.plist`. The license cache is in the Keychain (group `4788TTJ39Y.com.wiheads.paste`).

### 21.2 Entities (Core Data `v11.mom`, mirrored by the live schema) [R]

| Entity | Attributes | Relationships |
|---|---|---|
| **ItemEntity** | `identifier` String (unique, indexed), `checksum` String (indexed), `title` String?, `rawType` Int64 (ItemType), `rawPreview` Binary (external; encoded `ItemPreview`), `timestamp` Date? (entered history; nil = pinned-only), `createdAt`, `updatedAt` Date, `displayOrderInPinboard` Int64 | `data` → ItemDataEntity (to-one, cascade), `list` → ListEntity? (pinboard), `sourceApplication` → ApplicationEntity?, `device` → DeviceEntity? |
| **ItemDataEntity** | `rawPasteboardItems` Binary (external; `[PasteboardItem]` as binary plist (`useBinaryPlist`) or a legacy archive) | `item` → ItemEntity |
| **ListEntity** | `identifier` (unique), `name`, `rawType` (ListType), `rawAttributes` Binary (`ListAttributes`: clipboard{capacity days} \| pinboard{colorCode}), `rawShareRecord` Binary (CKShare), `createdAt`, `updatedAt` | `items` ↔ ItemEntity.list (nullify), `metadata` → ListMetadataEntity (cascade) |
| **ListMetadataEntity** | `identifier`, `index` Int64 (tab order), `createdAt`, `updatedAt` | `list` |
| **ApplicationEntity** | `bundleIdentifier` (unique), `name`, `rawIcon` Binary, `rawColor` Int64, `createdAt`, `updatedAt` | `items` |
| **DeviceEntity** | `identifier` (unique), `name`, `rawType` (iPhone, iPad, mac), `appVersion`, `createdAt`, `updatedAt` | `items` |
| **ObjectMetadata** | `objectURI` (unique), `cloudKitRecordName/ZoneName/ZoneOwnerName` (unique together), `cloudKitRecordData`, `isPendingDeletion` | — (sync bookkeeping) |
| **ObjectPendingMapping** | `objectURI` (unique), `pendingMappings`, `cloudKitRecordData` | — (sync) |
| **ObjectShare** | `rootRecordName/Type`, `shareRecordName/Owner`, `shareRecordData` | — (CloudKit sharing) |

### 21.3 Value types [B]

| Type | Definition |
|---|---|
| `ItemType` | unknown, image, color, files, link, text |
| `ListType` | unknown, clipboard, pinboard |
| `PinboardAttributes.Color` | red, orange, yellow, green, blue, purple, pink, gray |
| `ItemPreview` | `.text(TextPreview{textLength, text})`, `.link(LinkPreview{url, urlName?, iconData?, imageData?})`, `.image(ImagePreview{imageSize, imageData})`, `.color(ColorPreview{colorCode})`, `.files(FilesPreview{paths, totalSize, imageData?})` |
| `PasteboardItem` | `{types: [String], dataByType: [String: Data]}` |
| `Shortcut` | `{keyCode: Int, internalModifiers: UInt}` (Carbon registration via `CarbonCombination`) |
| `SearchQuery.FilterType` | app, type, title, date, device, pinboard |
| `StackDirection` | top, bottom |
| `SyncStatus` | synced(date?), error, inProgress, enabling, disabling, disabled |

The in-memory preview cache (`ItemPreviewCache`, `NSCache`) has an 8 MB cost limit (2 MB in app extensions) [B].

### 21.4 Preference keys (UserDefaults) [R names][B defaults]

| Key | Type / default |
|---|---|
| `activationShortcut` | Shortcut JSON, ⇧⌘V |
| `pasteStackShortcut` | Shortcut JSON, ⇧⌘C |
| `pasteStackPasteShortcut` | ⌘V (while the stack is open) |
| `nextPinboardShortcut` | ⌘→ |
| `previousPinboardShortcut` | ⌘← |
| `quickPasteModifierFlags` | ⌘ |
| `plainTextModifierFlags` | ⇧ |
| `isDirectPasteEnabled` | true |
| `isPasteAsPlainTextEnabled` | false |
| `isSoundEffectsEnabled` | true |
| `isStatusItemEnabled` | true |
| `isLinkPreviewsEnabled` | true |
| `isScreenSharingContentVisible` | true |
| `isFileItemQLThumbnailImageEnabled` | true |
| `ignoredPasteboardTypes` | 6 types (§2.3) |
| `ignoredBundleIdentifiers` | 14 ids (§2.3) |
| `pasteStackDirection` | top |
| `isSyncEnabled` | false |
| `isMCPEnabled` | false |
| `mcpPort` | 39725 |
| `isPicksEnabled` | true |
| `isDiagnosticsEnabled` | false |
| `onboardingState`, `isOnboardingCompleted` | — |
| `selectedListIdentifier`, `lastShownListIdentifier`, `searchQueryFilter` | — |
| `lastLaunchedVersion` | — |
| `inAppNotifications` | — |
| `pasteboard-change-token`, `pasteboardSyncCount` | — |
| `indexHistoryTokenData/Date`, `indexedStoreID`, `indexingState` | — |
| `useBinaryPlist` | — |
| `moveToApplicationsFolderAlertSuppress` | — |
| `usage-period-data`, `cached-user-id`, `active-license` | (drop) |
| `CKSyncEngineState.*`, `CloudKitAccountInfoCache` | (drop) |

Legacy Paste 4 names are migrated (`kPSTPreferences*`, `direct-paste-enabled`, `sound-effects-enabled`, …), tracked by `paste_config_migration_completed` and `paste_config_camelcase_migration_completed` [S].

---

## 22. Super Paste plan

### 22.1 SwiftPM targets

Swift 6, macOS 14+, built with `swift build` (Command Line Tools only), app bundle assembled by a script.

| Target | Kind | Responsibility | Covers spec § |
|---|---|---|---|
| `SuperPasteApp` | executable | `NSApplication` agent (LSUIElement), AppDelegate, coordinator and wiring, hidden main menu, URL scheme, launch sequence, restart, open-at-login (`SMAppService`) | 1, 6, 15 |
| `SPCore` | library | Domain model (Item, ItemPayload `[PasteboardItem]`, ItemPreview, List/Pinboard, App, Device), `ItemType` classification (§2.5), checksum (SHA-256), app-colour table, retention mapping (§2.9) | 2.5–2.9, 5, 21 |
| `SPStore` | library | SQLite persistence (system `SQLite3`, no Core Data, so it is portable for sync). Migrations, WAL, blobs as content-addressed files, FTS5 search index, pruning, undo log, damaged-store recovery, change journal for sync | 2.6, 2.9, 4.7, 4.10, 21 |
| `SPPasteboard` | library | Monitor (0.25 s poll + 0.3 s debounce, persisted change token), reader (all items/types, size cap), filters (ignored apps/types, `org.nspasteboard.source`, self-marker), per-app quirk rules, writer (all types minus banned + `org.superpaste.item-id` + `org.nspasteboard.source`) | 2.1–2.4, 3.5 |
| `SPPasting` | library | Direct paste (AX trust check, re-activate the target app, CGEvent ⌘V), plain-text mode, quick paste, multi-paste, Paste Stack engine (temporary ⌘V hot key) | 3 |
| `SPHotKeys` | library | Carbon `RegisterEventHotKey` monitor, `Shortcut` codec, conflict checks (menu, system symbolic hot keys), recorder control | 4.1, 7.3 |
| `SPLinkPreview` | library | LinkPresentation metadata fetch (title, favicon, image) behind the privacy toggle, with a cache | 2.8 |
| `SPSearch` | library | Query parser (tokens + `app:`/`type:`/`date:`/`device:`/`pinboard:`/`title:` filters), suggestion provider, FTS5 query builder, optional Vision OCR for images | 4.7 |
| `SPUI` | library | Strip panel (NSPanel, height 252–412, default 332), toolbar, tab bar, search field with tokens, card collection, cards per type, context menus, preview popover/window, editors (text/image/colour/link), New Text Item, Paste Stack panel, OSD/HUD, notification bar, sidecar | 4, 5, 6.1 |
| `SPSettings` | library | Settings window and panes (General, Privacy, Shortcuts, Sync, Integrations (MCP), About) | 7 |
| `SPOnboarding` | library | Intro + Quick Start screens, permission screens (Accessibility, Pasteboard access, optional Screen Recording) | 8, 9 |
| `SPSync` | library | E2E-encrypted folder sync: per-device append-only change logs + encrypted content-addressed blobs. CryptoKit: ChaChaPoly/AES-GCM with keys from a passphrase (HKDF/scrypt) or Keychain-stored key; last-writer-wins on `updatedAt`, tombstones | 17 (replacement) |
| `SPMCP` | library | Local MCP server (Network.framework HTTP/1.1 + SSE, JSON-RPC), 11 tools with the same names and semantics, OAuth DCR + PKCE consent page, token store (hashes), client config snippets | 14 |
| `super-paste-mcp` | executable | stdio ↔ HTTP bridge (`MCP_URL`, `MCP_TOKEN`) | 14.1 |
| `SPIntents` | library | App Intents: Create Item, Create Pinboard, Get Item at Index, Get Latest Item + List entity/query | 13 |
| `SPSupport` | library | `os.Logger` logging, diagnostics bundle export, config/UserDefaults wrapper with typed keys and defaults, local-only usage counters (no network) | 1.8, 21.4 |
| Tests | test targets | `SPCoreTests`, `SPStoreTests`, `SPPasteboardTests` (fake pasteboard), `SPSearchTests`, `SPMCPTests`, `SPSyncTests` | — |

### 22.2 Features to drop

1. Setapp framework, direct licensing, StoreKit paywall, trials, offers, subscription pane, "Activate license" routes.
2. Telemetry: PostHog (analytics, feature flags, remote config, surveys, replay), Sentry/KSCrash, PLCrashReporter, MetricKit upload, Setapp health metrics.
3. iCloud/CloudKit sync, CKShare shared pinboards (owner/editor/viewer, collaborator sidecar), APNs registration (replaced by folder sync).
4. Marketing: rate/review prompts, "Paste on Twitter", social buttons, remote What's New media, liquid-glass and Intelligent Clipboard promo cards.
5. Paste 4→5 migration, legacy preference migration, legacy duplicate cleanup.
6. All iOS-only strings and flows (keyboard extension, widget, action extension, "Paste from Other Apps" iOS setting).
7. Handoff (`NSUserActivity`); no companion app.
8. Intelligent Clipboard (screen capture + FoundationModels): defer, optionally replaced later by a non-AI recency/pair-frequency ranker.
9. CoreSpotlight system index (replaced by FTS5; system Spotlight exposure optional).
10. Move-to-Applications self-relocation (optional; not needed if distributed via DMG with instructions).

### 22.3 Gaps and open questions

| # | Gap | Proposed decision |
|---|---|---|
| 1 | Max storable size per pasteboard type (value not recovered) | Choose one, e.g. 50 MB per type |
| 2 | Exact multi-item paste semantics | Join text with newlines; paste mixed types sequentially |
| 3 | Mapping of the two privacy toggles to type lists; default state of those toggles | Not fully recovered |
| 4 | Actions bound to ⌘V and ⌘G in the strip, and ⌘T in the app menu | Not resolved |
| 5 | Status-item click mapping (left = strip, right = menu?) | Not confirmed |
| 6 | Visual order of controls in Settings panes | Code order is known, layout is not |
| 7 | Date-filter suggestion list beyond "Today" / "Last 30 days" | Partial |
| 8 | `read_item` text truncation length | Not recovered |
| 9 | Pruning schedule | Not recovered |
| 10 | Whether pasting an old item moves it to the front | Not recovered |
| 11 | Visual/UI decisions (card sizes, colours, animations) | Intentionally not specified here; for the design spec |
| 12 | Tooling risk: App Intents metadata extraction (`appintentsmetadataprocessor`) and asset catalogs normally need Xcode | With Command Line Tools only, plan to bundle PNG/PDF resources and verify intents discovery early |
