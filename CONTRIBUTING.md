# Contributing to Super Paste

Thanks for helping. Bug reports, feature ideas, documentation and code are all welcome. This page covers the dev
setup, how the project is laid out, the conventions the code follows, how to run the self-tests and renders, and how
releases are made.

## Dev setup

You need macOS 14 or later and the Swift toolchain from the Command Line Tools (`xcode-select --install`). Xcode is
optional; there's no Xcode project.

```sh
git clone https://github.com/udsy19/super-paste.git && cd super-paste
./scripts/signing-setup.sh      # once: a project-local signing identity in .signing/, so Accessibility and
                                # Keychain access survive rebuilds
./scripts/build-app.sh --debug  # → build/Super Paste.app
open "build/Super Paste.app"
```

`swift build` alone compiles everything (including the self-tests) without making an app bundle.

## Project layout

```
Package.swift            SwiftPM manifest: one contracts module, seven feature modules, the app, the bridge, the tests
Sources/
  SuperPasteCore/        contracts and shared utilities: model, store and service protocols, SearchQuery, settings
                         keys, design tokens, Services registry, Defaults, Keychain, hotkeys, alerts, app menu
  ClipStore/             SQLite + FTS5 store, blobs, retention, undo, sync journal
  ClipboardKit/          pasteboard monitor and filters, classification, link previews, pasting, Paste Stack engine
  StripKit/              the strip panel: toolbar, search, tabs, cards, context menus, preview and editors
  SettingsKit/           Settings window and panes, onboarding, permission screens
  SyncKit/               encrypted folder sync
  MCPKit/                MCP server, OAuth, token clients
  UpdateKit/             background updates
  SuperPaste/            app target: launch, wiring, menu bar item, global shortcuts, URL routing
  super-paste-mcp/       stdio ↔ HTTP bridge for MCP clients
  SuperPasteSelfTest/    headless checks: one file per module plus end to end
Resources/               Info.plist, entitlements
scripts/                 build-app, make-dmg, release, install, signing-setup, make-icon
docs/                    ARCHITECTURE.md, USAGE.md, MCP.md, images/, specs/ (the behaviour and UI the app follows)
website/                 the GitHub Pages site (static HTML, CSS and JS; fonts self-hosted; og.html renders og.png)
.github/                 CI (build + self-tests on macOS), Pages deployment, issue and PR templates
```

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) explains how the modules fit together, the launch sequence, the data
model and the sync rules.

## Conventions

- **Modules depend only on `SuperPasteCore`** and talk through the `Services` registry; they never import each
  other. A new contract goes in Core with every implementation and fake updated in the same change.
- **Settings are typed `Defaults` keys** in `SuperPasteCore/Settings.swift` with their default values. Module-private
  state uses the module name as a prefix (`clipboardKit.changeToken`).
- **UI code is `@MainActor`**, as are the service protocols and the store. Work off the main actor hops back before
  calling a service.
- **Everything is local unless a privacy switch allows a network call.** Anything new that touches the network gets
  its own switch, stays off by default unless the app depends on it, and is documented in PRIVACY.md.
- **No third-party dependencies.** Apple frameworks only.
- **Design tokens come from `SuperPasteCore/Theme.swift`**, which mirrors `docs/specs/ui-reference.md`. Don't put
  literal sizes or colours in views.
- **No dead code.** When you replace or remove behaviour, delete the old implementation, its helpers and its tests
  in the same change.
- **Wording** follows `docs/specs/strings.md`; user-facing strings live in each module's `Strings.swift`.
- `swift build` must be **warning-free**.

## Self-tests and renders

The Command Line Tools ship no XCTest, so tests are an executable with a small `check(_:_:)` harness:

```sh
swift run SuperPasteSelfTest
```

Each module registers its cases in `Sources/SuperPasteSelfTest/<Module>Tests.swift`; `EndToEndTests.swift` runs the
real modules together, from a copy on a private pasteboard to an MCP client over loopback. Tests never touch the
general pasteboard, post key events, show windows or use your real Application Support folder: use the private named
`NSPasteboard`, throwaway folders and the defaults suite the harness provides. Add cases for any new logic.

Offscreen renders of the real UI, for checking the look and for the screenshots in the README:

```sh
STRIPKIT_RENDER_DIR=/tmp/strip SUPERPASTE_RENDER_DIR=/tmp/settings swift run SuperPasteSelfTest
```

writes PNGs of the strip at every height in light and dark, the search state, the filter browser, previews and
editors, the Paste Stack panel, every Settings pane, onboarding and the permission screens. Liquid Glass can't be
captured offscreen, so those renders use a translucent stand-in.

`UpdateKit.endToEnd` runs against `build/Super Paste.app` when it exists; build it first to exercise that path.

## Pull requests

1. One change per pull request, with a clear description of what it does and why. Link the issue if there is one.
2. `swift build` compiles without warnings and `swift run SuperPasteSelfTest` passes.
3. UI changes come with a render or a short recording, and follow `docs/specs/ui-reference.md`.
4. Behaviour changes update `docs/specs/behaviour.md` (and USAGE.md if users will notice), and get a line in
   CHANGELOG.md under *Unreleased*.
5. Network or data-handling changes update PRIVACY.md.

The pull request template has this as a checklist.

## Reporting bugs

Use the [bug report template](https://github.com/udsy19/super-paste/issues/new/choose). It asks for your Super Paste
and macOS versions, your Mac (Apple silicon or Intel), the app you copied from or pasted into, steps to reproduce and
what you expected. Logs are in Console.app, filtered by `com.udsy.superpaste`. Please don't paste clipboard contents
you wouldn't want public. Security issues go through [SECURITY.md](SECURITY.md), not the tracker.

## Releases

Maintainers only. Releases are built on the maintainer's Mac and published to GitHub Releases:

1. Add the version's section to CHANGELOG.md (the release notes come from it).
2. `./scripts/release.sh <version>` bumps `Resources/Info.plist`, commits, builds the universal DMG with
   `make-dmg.sh`, tags `v<version>`, and creates the GitHub release with `SuperPaste-<version>.dmg` and a stable
   `SuperPaste.dmg` (which the installer and the website link to) plus the DMG's SHA-256 in the notes.
3. Running copies pick the release up through UpdateKit, which checks that SHA-256 and the code signature before
   installing.

The website deploys from `website/` on every push to `main` (`.github/workflows/pages.yml`); `scripts/install.sh`
is published at the site root.

## Code of conduct

Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
