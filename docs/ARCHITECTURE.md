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
                      paths, typed Defaults, Keychain, shortcuts & global hotkeys, alerts/HUD, permissions
  ClipStore/          SQLite store: items, pinboards, FTS5 search, content-addressed blobs, retention, undo,
                      sync journal, damaged-store recovery
  ClipboardKit/       pasteboard monitor and capture filters, classification, link previews, sounds, pasting
                      (direct paste, plain text, multi-item), Paste Stack engine
  StripKit/           the strip panel: toolbar, search field and filter suggestions, tab bar, cards, context menus,
                      preview and editors, New Text Item window, Paste Stack panel, sidecar cards
  SettingsKit/        Settings window and panes, onboarding, permission screens, open at login
  SyncKit/            end-to-end-encrypted folder sync
  MCPKit/             local MCP server: tools, OAuth (DCR + PKCE) and token clients, client config snippets
  UpdateKit/          background updates from GitHub Releases: check, SHA-256 and code-signature verification,
                      staging next to the app, swap on quit or while idle
  SuperPaste/         app target: launch sequence, module wiring, hidden main menu, menu bar item, global
                      shortcuts, URL scheme
  super-paste-mcp/    stdio ↔ HTTP bridge for MCP clients (Foundation only; ships in Contents/MacOS)
  SuperPasteSelfTest/ headless checks (`swift run SuperPasteSelfTest`)
```

## Rules

- Feature modules depend **only** on `SuperPasteCore`. They never import each other; they talk through the
  `Services` registry (`Services.store`, `Services.pasting`, …).
- Each protocol has one owning module. Its `<Module>Module.install()` registers the implementation in `Services`.
  Until the real one exists, a `Placeholder…` class stands in; **delete it in the change that registers the real
  implementation**.
- `SuperPasteCore` is the contract. Workers don't edit it; a needed change (a new method, a new field, a new
  setting) goes to the orchestrator, who changes Core for everyone. Module-private state (caches, change tokens)
  is declared in the module itself, with the module as key prefix: `Key<Int>("clipboardKit.changeToken", …)`.
- UI code is `@MainActor`; so are all service protocols and the store. Work off the main actor (SQLite on a queue,
  the MCP server's sockets, sync I/O) hops back before calling a service.
- Everything is local unless a privacy switch allows a network call (link previews, update checks). No telemetry.
- No dead code: superseded code, placeholders and their now-unused helpers go in the same change.

## Launch sequence

`Sources/SuperPaste/main.swift`:

1. `applicationWillFinishLaunching` installs modules in this order: ClipStore → ClipboardKit → SyncKit → MCPKit →
   UpdateKit → SettingsKit → StripKit, then sets the hidden main menu.
2. `applicationDidFinishLaunching`: menu bar item, global shortcuts (Activate ⇧⌘V → `Services.strip.toggle()`,
   Paste Stack ⇧⌘C → `Services.pasting.togglePasteStack()`, re-registered when changed), `Services.clipboard.start()`,
   `Services.mcp.start()` when `isMCPEnabled`, `Services.onboarding.show()` until completed, `Services.updates.start()`.
3. Reopening the app shows the strip; `superpaste://` URLs are parsed by `AppRoute` and dispatched to the strip or
   Settings.

## Contracts (SuperPasteCore)

| File | Contents |
|---|---|
| `Model.swift` | `ClipItem`, `ItemKind`/`ItemTypeFilter`, `BlobRef`, `PasteboardRep`/`PasteboardEntry` (stored payload), `RepData`/`EntryData` (payload with bytes), `AppRecord`, `Device`, `LinkMetadata`, `PixelSize`, `PinboardPin`, `Pinboard`, `PinboardColor`, `ListScope` |
| `Store.swift` | `ItemStoring`, `SyncStoring`, `ClipDraft`, `InsertResult`, `StoreChange`, `StoreError`, `SyncRecord`, `SyncTombstone`, `JournalEntry` |
| `Contracts.swift` | `ClipboardMonitoring`, `Pasting`, `StripPresenting`, `SettingsPresenting`, `OnboardingPresenting`, `PermissionsPresenting`, `SyncServicing`, `MCPServing`, `Updating` and their value types |
| `Search.swift` | `SearchQuery` (parser, canonical text, `kinds`, `dateRanges`), `DateRange` |
| `Content.swift` | `PasteboardType` names (self-marker `org.superpaste.item-id`, banned and volatile types), `ClipChecksum`, `TextClassifier`, `Device.current` |
| `Retention.swift` | `HistoryRetention`: Keep History slider ↔ days |
| `Settings.swift` | every setting as a `Defaults.Keys` member with its spec default, `CaptureDefaults`, `PauseDurations`, `StackDirection`, the two privacy toggles over `ignoredPasteboardTypes` |
| `Theme.swift` | `SPStyle` (glass on macOS 26+, classic on 14/15), `SPColor`, `SPFont`, `CardSizeClass`, `SPMetrics`, `SPMotion` |
| `Routes.swift` | `AppRoute`: `superpaste://` URLs |
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
  (`SyncStoring`), SyncKit ships records and blobs.
- Search: `SearchQuery` syntax and matching rules are documented on the type; the store implements matching with
  FTS5 (tokens) and SQL (filters).

## Ownership map (parallel work)

Each worker owns only the files listed for it. Anything else, including `Package.swift`, is a request to the
orchestrator.

| Owner | Files | Implements | Spec |
|---|---|---|---|
| Orchestrator | `Package.swift`, `Sources/SuperPasteCore/**`, `Sources/SuperPaste/**`, `Sources/SuperPasteSelfTest/main.swift`, `Sources/SuperPasteSelfTest/CoreTests.swift`, `Resources/**`, `scripts/**`, `docs/**`, `README.md`, `CHANGELOG.md` | contracts, app shell (menu bar item and app menu, Pause menu, URL routes, launch) | §1, §6, §15 |
| ClipStore | `Sources/ClipStore/**`, `Sources/SuperPasteSelfTest/ClipStoreTests.swift` | `ItemStoring`, `SyncStoring` | §2.6, §2.9, §4.7 engine, §4.10, §5 data, §21 |
| ClipboardKit | `Sources/ClipboardKit/**`, `Sources/SuperPasteSelfTest/ClipboardKitTests.swift` | `ClipboardMonitoring`, `Pasting` | §2, §3 |
| StripKit | `Sources/StripKit/**`, `Sources/SuperPasteSelfTest/StripKitTests.swift` | `StripPresenting` | §4, §5 UI, §3.6 panel, §11 |
| SettingsKit | `Sources/SettingsKit/**`, `Sources/SuperPasteSelfTest/SettingsKitTests.swift` | `SettingsPresenting`, `OnboardingPresenting`, `PermissionsPresenting` | §7, §8, §9 |
| SyncKit | `Sources/SyncKit/**`, `Sources/SuperPasteSelfTest/SyncKitTests.swift` | `SyncServicing` | §17 (replacement) |
| MCPKit | `Sources/MCPKit/**`, `Sources/super-paste-mcp/**`, `Sources/SuperPasteSelfTest/MCPKitTests.swift` | `MCPServing`, the stdio bridge | §14 |
| UpdateKit | `Sources/UpdateKit/**`, `Sources/SuperPasteSelfTest/UpdateKitTests.swift` | `Updating` (complete) | — |

Module resources (sounds, images) are declared in `Package.swift` by the orchestrator on request;
`scripts/build-app.sh` copies every `SuperPaste_*.bundle` into `Contents/Resources`. Load them from
`Bundle.main.resourceURL` (falling back to the executable's folder for `swift run`), never `Bundle.module`.

## Tests

The Command Line Tools ship no XCTest. `SuperPasteSelfTest` is an executable with a `check(_:_:)` harness: each
module appends cases to `SelfTest.cases` from `register<Module>Tests()` in its own file. Files and settings go to a
throwaway folder and defaults suite, never the real ones. `UpdateKit.endToEnd` runs against `build/Super Paste.app`
when it exists (build it first with `scripts/build-app.sh`).

```
swift build                       # warning-free
swift run SuperPasteSelfTest      # all checks
scripts/signing-setup.sh          # once: project-local signing identity in .signing/
scripts/build-app.sh              # build/Super Paste.app, signed
```
