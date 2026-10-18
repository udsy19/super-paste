# Architecture

Super Paste is a native macOS clipboard manager written in Swift (Swift 5 language mode), built with SwiftPM and
Apple frameworks only: no third-party dependencies, no Xcode project. Deployment target: macOS 14. It is an agent
app (`LSUIElement`): no Dock icon, a menu bar item, global shortcuts.

The behaviour to build is specified in `docs/specs/behaviour.md`, the look in `docs/specs/ui-reference.md` and the
wording in `docs/specs/strings.md`. Section numbers in code comments point into those files.

```
Sources/
  SuperPasteCore/     contracts & shared utilities (no feature logic): domain model, store and service
                      protocols, SearchQuery, retention mapping, settings keys, design tokens, Services registry,
                      paths, typed Defaults, Keychain, shortcuts & global hotkeys, alerts/HUD, permissions, the
                      shared app menu, the app-icon header colour
  ClipStore/          SQLite store: items, pinboards, FTS5 search, content-addressed blobs, retention, undo,
                      sync journal, damaged-store recovery
  ClipboardKit/       pasteboard monitor and capture filters, classification, link previews, sounds, pasting
                      (direct paste, plain text, multi-item), Paste Stack engine
  StripKit/           the strip panel: toolbar, search field and filter suggestions, tab bar, cards, context menus,
                      preview and editors, New Text Item window, Paste Stack panel, sidecar cards
  SettingsKit/        Settings window and panes, onboarding, permission screens, open at login, MCP client
                      config snippets (Integrations pane)
  SyncKit/            end-to-end-encrypted folder sync
  MCPKit/             local MCP server: tools, OAuth (DCR + PKCE) and token clients, client kinds
  UpdateKit/          background updates from GitHub Releases: check, SHA-256 and code-signature verification,
                      staging next to the app, swap on quit or while idle
  SuperPaste/         app target: launch sequence, module wiring, hidden main menu, menu bar item, global
                      shortcuts, URL routing
  super-paste-mcp/    stdio ↔ HTTP bridge for MCP clients (Foundation only; ships in Contents/MacOS)
  SuperPasteSelfTest/ headless checks (`swift run SuperPasteSelfTest`), per module and end to end
```

## Rules

- Feature modules depend **only** on `SuperPasteCore`. They never import each other; they talk through the
  `Services` registry (`Services.store`, `Services.pasting`, …).
- Each protocol has one owning module. Its `<Module>Module.install()` registers the implementation in `Services`.
- `SuperPasteCore` is the contract. A change to it (a new method, a new field, a new setting) updates every
  implementation and fake in the same change. Code two modules need (the app menu, the app-icon colour, closure
  menu items) lives in Core once rather than in each module. Module-private state (caches, change tokens) is
  declared in the module itself, with the module as key prefix: `Key<Int>("clipboardKit.changeToken", …)`.
- UI code is `@MainActor`; so are all service protocols and the store. Work off the main actor (SQLite on a queue,
  the MCP server's sockets, sync I/O) hops back before calling a service.
- Everything is local unless a privacy switch allows a network call (link previews, update checks). No telemetry.
- No dead code: superseded code, placeholders and their now-unused helpers go in the same change.

## Launch sequence

`Sources/SuperPaste/main.swift`:

1. `applicationWillFinishLaunching` installs modules in dependency order: ClipStore (prunes past Keep History now,
   then hourly) → ClipboardKit → SyncKit (resumes syncing once launched) → MCPKit → UpdateKit → SettingsKit →
   StripKit, then sets the hidden main menu (File › Close, Edit › Undo/Redo/Cut/Copy/Paste/Select All, Window ›
   Minimize, Quit) so text fields get their standard key equivalents.
2. `applicationDidFinishLaunching`: menu bar item, global shortcuts (Activate ⇧⌘V → `Services.strip.toggle()`,
   Paste Stack ⇧⌘C → `Services.pasting.togglePasteStack()`, re-registered when changed; next/previous pinboard
   ⌘→/⌘← are strip-local, read live by StripKit), `Services.clipboard.start()`, `Services.mcp.start()` when
   `isMCPEnabled`, `Services.onboarding.show()` until completed, `Services.updates.start()`.
3. Reopening the app shows the strip. `superpaste://` URLs are parsed by `AppRoute` and dispatched to the strip,
   Settings, the Accessibility screen or the login item.

### Menu bar item and app menu

`AppMenu` (Core) builds the app menu fresh each time it opens; the menu bar item and the strip's "…" button both
show it, and the strip's paused indicator shows its Pause submenu:

```
About Super Paste             (Settings › About)
─
New Text Item           ⌘N
Settings…               ⌘,
─
Help ▸                        Getting Started (onboarding again), Keyboard Shortcuts (Settings › Shortcuts),
                              Help Center, Feature Request, Contact Support (the website and GitHub issues)
─
Pause ▸                       Pause for 15m / 30m / 1h / 3h / 8h, Until I Resume ⌘T
                              (titled "Paused until HH:mm" while paused: Resume ⌘T, then the durations)
─
Quit Super Paste        ⌘Q
```

No Check for Updates: UpdateKit installs updates by itself. The menu bar item (shown while Show in Menu Bar is on)
toggles the strip on a left click and opens the menu on a right, Control- or Option-click; it plays a short card
animation on every capture and is dimmed while capturing is paused.

### Global shortcuts

`GlobalShortcuts` (app target) registers Activate Super Paste and Activate Paste Stack through `HotkeyCenter`
(Core, Carbon `RegisterEventHotKey`) and again whenever either setting changes. A combination another app already
holds can't be registered: `HotkeyCenter.unavailable` lists it, the app shows a one-time alert per shortcut, retries
every 30 s (and 1.5 s after onboarding completes), and Settings › Shortcuts shows a warning row and a sidebar badge.

### Onboarding

Introduction → Quick Start (Run in background, Folder sync, Activation shortcut, Clipboard history). Continue sets
`isOnboardingCompleted`, closes the window, seeds the Welcome pinboard once (`WelcomeContent`: four notes and three
links with drawn preview art, all pinned-only) and shows the strip on it. Permissions are asked for on demand.

## Contracts (SuperPasteCore)

| File | Contents |
|---|---|
| `Model.swift` | `ClipItem`, `ItemKind`/`ItemTypeFilter`, `BlobRef`, `PasteboardRep`/`PasteboardEntry` (stored payload), `RepData`/`EntryData` (payload with bytes), `AppRecord`, `Device`, `LinkMetadata`, `PixelSize`, `PinboardPin`, `Pinboard`, `PinboardColor`, `ListScope` |
| `Store.swift` | `ItemStoring`, `SyncStoring`, `ClipDraft`, `InsertResult`, `StoreChange`, `StoreError`, `SyncRecord`, `SyncTombstone`, `JournalEntry` |
| `Contracts.swift` | `ClipboardMonitoring`, `Pasting`, `StripPresenting`, `SettingsPresenting` (with `setOpenAtLogin`), `OnboardingPresenting`, `PermissionsPresenting`, `SyncServicing`, `MCPServing` (`MCPClientInfo`), `Updating` and their value types |
| `Search.swift` | `SearchQuery` (parser, canonical text, `kinds`, `dateRanges`), `DateRange` |
| `Content.swift` | `PasteboardType` names (self-marker `org.superpaste.item-id`, banned and volatile types), `ClipChecksum`, `TextClassifier`, `Device.current` |
| `Retention.swift` | `HistoryRetention`: Keep History slider ↔ days |
| `Settings.swift` | every setting as a `Defaults.Keys` member with its spec default, `CaptureDefaults`, `PauseDurations`, `StackDirection`, the two privacy toggles over `ignoredPasteboardTypes` |
| `Theme.swift` | `SPStyle` (glass on macOS 26+, classic on 14/15), `SPColor`, `SPFont`, `CardSizeClass`, `SPMetrics`, `SPMotion` |
| `Routes.swift` | `AppRoute`: `superpaste://` URLs |
| `AppMenu.swift` | `AppMenu` (the shared app menu and Pause submenu), `ClosureMenuItem`, `NSMenuItem.make` |
| `AppColor.swift` | `AppColor`: built-in app colours and the header colour derived from an app icon |
| `Services.swift` | `Services` registry, `SuperPastePaths` |
| `System.swift` | `Log`, `Alerts`, `HUD` (the OSD toast), `NSScreen.active`, `Permissions` |
| `Defaults.swift`, `Keychain.swift`, `Hotkeys.swift` | typed UserDefaults, generic passwords, `Shortcut` + `HotkeyCenter` + `ShortcutRecorder` |

### Data model in short

- An item's payload is every pasteboard item it had, each with every type, in pasteboard order. Payload bytes are
  content-addressed blobs (`BlobRef`, SHA-256); the item itself carries only refs and display fields, so lists are
  cheap. Read bytes with `Services.store.data(for:)`.
- `copiedAt` places an item in the history (nil = pinned-only); `pins` place it in pinboards (an item may be in
  several; Paste allows one, so the UI may still offer a single choice). Pinned items survive pruning and
  Erase History.
- Dedupe: captures with an equal `ClipChecksum` reuse the existing item and move it to the front.
- Sync is record-level last-writer-wins on `updatedAt`, with tombstones; the store journals local writes
  (`SyncStoring`), SyncKit ships records and blobs. Equal `updatedAt`s go to the item's greater device id, then the
  greater digest of the record, so every Mac picks the same version; a deletion wins a tie with an edit.
- Search: `SearchQuery` syntax and matching rules are documented on the type; the store implements matching with
  FTS5 (tokens) and SQL (filters).

## Module ownership

Each module owns its folder and its `Sources/SuperPasteSelfTest/<Module>Tests.swift`. Core, the app target, the
end-to-end test, resources, scripts and docs are shared.

| Module | Files | Implements | Spec |
|---|---|---|---|
| Core and app shell | `Package.swift`, `Sources/SuperPasteCore/**`, `Sources/SuperPaste/**`, `Sources/SuperPasteSelfTest/{main,CoreTests,EndToEndTests}.swift`, `Resources/**`, `scripts/**`, `docs/**` | contracts, menu bar item and app menu, Pause menu, URL routes, launch | §1, §6, §15 |
| ClipStore | `Sources/ClipStore/**` | `ItemStoring`, `SyncStoring` | §2.6, §2.9, §4.7 engine, §4.10, §5 data, §21 |
| ClipboardKit | `Sources/ClipboardKit/**` | `ClipboardMonitoring`, `Pasting` | §2, §3 |
| StripKit | `Sources/StripKit/**` | `StripPresenting` | §4, §5 UI, §3.6 panel, §11 |
| SettingsKit | `Sources/SettingsKit/**` | `SettingsPresenting`, `OnboardingPresenting`, `PermissionsPresenting`, MCP config snippets | §7, §8, §9, §14.4 |
| SyncKit | `Sources/SyncKit/**` | `SyncServicing` | §17 (replacement) |
| MCPKit | `Sources/MCPKit/**`, `Sources/super-paste-mcp/**` | `MCPServing`, client kinds, the stdio bridge | §14 |
| UpdateKit | `Sources/UpdateKit/**` | `Updating` | — |

Module resources (sounds, images) are declared in `Package.swift`; `scripts/build-app.sh` copies every
`SuperPaste_*.bundle` into `Contents/Resources`. Load them from `Bundle.main.resourceURL` (falling back to the
executable's folder for `swift run`), never `Bundle.module`.

## Tests

The Command Line Tools ship no XCTest. `SuperPasteSelfTest` is an executable with a `check(_:_:)` harness: each
module appends cases to `SelfTest.cases` from `register<Module>Tests()` in its own file. Files and settings go to a
throwaway folder and defaults suite, never the real ones; pasteboards are private named ones, never the general
pasteboard, and no key event is posted. `EndToEnd.copyToMCP` runs the real modules together: copies on a private
pasteboard are captured, searched, pasted back to another private pasteboard, pinned, pruned, synced to a second
store through a folder and listed by an MCP client over loopback. `UpdateKit.endToEnd` runs against
`build/Super Paste.app` when it exists (build it first with `scripts/build-app.sh`).

```
swift build                       # warning-free
swift run SuperPasteSelfTest      # all checks
scripts/signing-setup.sh          # once: project-local signing identity in .signing/
scripts/build-app.sh              # build/Super Paste.app, signed
```
