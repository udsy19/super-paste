# Changelog

All notable changes to Super Paste are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org).

## [1.0.3] — 2026-10-19

### Fixed
- A damaged history file is never a silent fresh start. Only a file that is actually damaged is moved aside, and
  what can still be read from it (items, pinboards, the search index, blob files) is copied into the fresh store;
  a file that merely can't be opened (locked, unreadable, a full disk) is left untouched and the session runs from
  memory. The old fallback could delete a file it failed to move. Either way an alert says what happened, how much
  came back and where the old file is.
- A copy the store can't save (the disk is full, the file is read-only) is reported once, in words that name the
  cause; it used to fail silently on every copy. Writes are fsynced on commit and the write-ahead log is folded
  into the file on quit, before an update swaps the app.
- An edit the store refused closed the editor and took the text with it; the editor now stays open. An item
  deleted while it was being edited comes back as a new item instead of vanishing; closing an editor with unsaved
  changes saves them; Cancel and Esc ask first. New Text Item keeps a draft across a quit or crash.
- A direct paste with secure keyboard entry on (a password field, a terminal) copies and says "Press ⌘V to paste"
  instead of typing a ⌘V that would be swallowed. The Paste Stack's ⌘V follows a keyboard layout change. An app
  that rewrites the pasteboard without pause no longer starves capture.
- A sync file that a cloud service has created but not yet filled is waited for rather than reported as damaged.
  Lost-key errors say where to import the key from and that an empty folder starts over.
- A second copy of Super Paste hands over to the running one instead of watching and writing alongside it. The
  strip and the Paste Stack panel move back on screen when a display is removed or resized under them.

### Added
- `docs/specs/reliability.md`: every failure mode considered, what the user sees, and the self-test that injects
  it (damaged database pages, a locked file, a full disk, an unwritable blob folder, a chattering pasteboard,
  empty and tampered sync files).

## [1.0.2] — 2026-10-18

### Fixed
- Double-clicking a card (and Return) pastes again. The ⌘V was typed while the strip was still sliding away and
  still the key window, so the strip swallowed it. A paste now waits until the strip is off screen and keyboard
  focus is back with the app, then types ⌘V at the HID event tap with only ⌘ held.
- Typing into the search field. The strip is made key with `makeKeyAndOrderFront` and, should AppKit refuse to
  make an inactive app's panel key, Super Paste comes forward instead and takes the typing. A click on the magnifier
  opens the field (the icon no longer eats the click), the first click on a card counts even before the panel is
  key, and on macOS 26 the glass's content view always spans the slab so every card and button is clickable.
- ⌘V stays the app's own while a Paste Stack is open but empty: the stack only takes ⌘V while it holds a snippet
  and gives it back when the last one is pasted, deleted or the stack closes. ⌘C is never registered globally.

### Changed
- Keep History defaults to Forever: what you copy stays until you delete it. Installs still on the old 30-day
  default move to Forever once (a limit you chose yourself stays). Pinned items were, and are, never pruned.
- The Paste Stack explains itself when empty ("Copy several things, then paste them in order with ⌘V."), ends
  itself after its last snippet is pasted, closes with Esc once clicked, and is listed as "Paste Stack" with a line
  about what it does in Settings › Shortcuts.
- "Copied" toasts say "Press ⌘V to paste" when the content went to the clipboard instead of into the app.

### Added
- A hot corner: rest the pointer in the bottom-left corner (Settings › General lets you pick another corner or turn
  it off) and a small peek of your three latest items slides out; click it to open Super Paste. The peek never
  takes focus, stays while you hover, hides 0.6 s after you move away, fades instead of sliding with Reduce
  Motion, stays away from full-screen apps, and leaves a corner alone when macOS's own Hot Corners use it.

## [1.0.1] — 2026-10-18

### Changed
- Onboarding is two pages, like Paste's, and ends with the strip open on a Welcome pinboard.
- If another app already uses ⇧⌘V (or any Super Paste shortcut), you're told once and Settings › Shortcuts shows
  a warning; Super Paste keeps retrying and takes the shortcut as soon as it's free.
- Menu bar menu in Paste's order, with an icon that animates on every capture.
- Cards closer to Paste: file paths, image size pill, colour codes, pinned-only titles, icon-only tabs while
  searching, and the preview footer.

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
