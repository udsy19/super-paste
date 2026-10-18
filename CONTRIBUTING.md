# Contributing to Super Paste

Thanks for helping make Super Paste better! Bug reports, feature ideas, docs and code are all welcome.

## Getting started

```sh
git clone https://github.com/udsy19/super-paste.git && cd super-paste
./scripts/signing-setup.sh      # once: local signing identity, so permissions and Keychain access survive rebuilds
./scripts/build-app.sh --debug  # → build/Super Paste.app
open "build/Super Paste.app"
```

You only need macOS 14+ and the Swift toolchain from the Command Line Tools (`xcode-select --install`).
Xcode is optional.

## Before you open a pull request

1. `swift build` compiles with **no warnings**.
2. `swift run SuperPasteSelfTest` passes. Add cases for new logic in `Sources/SuperPasteSelfTest/<Module>Tests.swift`.
   Tests never touch the general pasteboard, post key events, show windows or use your real Application Support
   folder: use a private named `NSPasteboard`, the throwaway folders and the defaults suite the harness sets up.
3. For UI changes, include a screenshot or a short recording.
4. Follow the conventions in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): feature modules depend only on
   `SuperPasteCore` and talk through `Services`, settings use typed `Defaults` keys, no third-party dependencies.
   The behaviour Super Paste follows is described in `docs/specs/`.
5. Anything that touches the network gets its own switch and stays off by default unless the app depends on it
   (automatic updates and link previews start on; say so in PRIVACY.md).
6. Keep changes focused and remove any code your change makes obsolete.

## Reporting bugs

Open an [issue](https://github.com/udsy19/super-paste/issues/new/choose) with your Super Paste and macOS versions,
your Mac (Apple silicon or Intel), the app you copied from or pasted into, steps to reproduce and what you expected.
Please don't paste clipboard contents you wouldn't want public. Logs are in Console.app (filter by
`com.udsy.superpaste`).

## Code of conduct

Everyone participating is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
