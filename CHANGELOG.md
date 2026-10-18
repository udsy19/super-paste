# Changelog

All notable changes to Super Paste are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

## [1.0.0] — 2026-10-18

The first release.

### Added
- Clipboard history: text, rich text, images, files, links and colours, with the app and Mac each came from.
  Duplicates move to the front, Keep History from a day to a year or forever, pinned items are never deleted.
- The strip: open it with ⇧⌘V, type to search with filters (`app:`, `type:`, `date:`, `device:`, `pinboard:`,
  `title:`), paste with Return, ⌘1…⌘9 or a double click, as plain text with ⇧. Preview, edit, rename, open and
  delete with undo.
- Pinboards in colours, next to the history, with ⌘← / ⌘→ to move between them.
- Paste Stack (⇧⌘C): copy several things, then paste them one by one with ⌘V.
- Paste directly into the active app (with Accessibility), or to the clipboard.
- Privacy filters: password managers and confidential or temporary content are never saved; ignore your own apps;
  pause capturing for 15 minutes to 8 hours or until you resume.
- Menu bar item and app menu: About, New Text Item, Settings, Help, Pause, Quit. Left click opens the strip,
  right-click opens the menu; the icon animates on every capture.
- Onboarding (Introduction, Quick Start) ends with the strip open on a Welcome pinboard. A shortcut another app
  holds is reported once and flagged in Settings › Shortcuts instead of failing silently.
- Folder sync between Macs, end-to-end encrypted, through iCloud Drive, Dropbox or any folder they share.
- A local MCP server with eleven tools for clipboard items and pinboards, OAuth sign-in with your approval, token
  clients and a bundled stdio bridge (`super-paste-mcp`).
- The `superpaste://` URL scheme.
- Automatic background updates from GitHub Releases, verified by SHA-256 and code signature.
- One-line installer and a universal DMG.
