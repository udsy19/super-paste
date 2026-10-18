# Super Paste user guide

Everything Super Paste does, in the order you'll meet it. Short on time? The [README](../README.md#usage) has the
three-step version and the shortcut table.

- [First launch](#first-launch)
- [The menu bar](#the-menu-bar)
- [The strip](#the-strip)
- [Cards](#cards)
- [Pasting](#pasting)
- [Search](#search)
- [Pinboards](#pinboards)
- [Paste Stack](#paste-stack)
- [Hot corner](#hot-corner)
- [Preview, edit, rename, open, delete](#preview-edit-rename-open-delete)
- [New Text Item](#new-text-item)
- [Pause](#pause)
- [Settings](#settings)
- [Sync](#sync)
- [Integrations (MCP)](#integrations-mcp)
- [URL scheme](#url-scheme)
- [Updates](#updates)
- [Troubleshooting](#troubleshooting)
- [Uninstall](#uninstall)

## First launch

Two onboarding pages. **Introduction** explains what Super Paste does. **Quick Start** has four settings you can
change later:

| Setting | What it does |
|---|---|
| Run in background | Opens Super Paste at login and keeps it running (Settings → General → Open at login). |
| Folder sync | Keeps your history the same on all your Macs through a folder they share. Off until you choose a folder in Settings → Sync. |
| Activation shortcut | The global shortcut that opens the strip. ⇧⌘V by default. |
| Clipboard history | How long items are kept. Forever by default; pinned items are never deleted. |

Continue closes onboarding and opens the strip on a **Welcome** pinboard with a few cards to try: paste one with
Return, open a link with ⌘O. Delete the pinboard whenever you like.

**Permissions.** Super Paste asks for Accessibility the first time you paste into another app (see [Pasting](#pasting)).
Nothing else is needed.

## The menu bar

Super Paste has no Dock icon and no main window; it lives in the menu bar. The icon plays a short card animation on
every capture and is dimmed while capturing is paused.

- **Left click** opens or closes the strip.
- **Right-click** (or Control- or Option-click) opens the menu: About, New Text Item (⌘N), Settings… (⌘,), Help ▸
  (Getting Started replays onboarding; Keyboard Shortcuts opens Settings → Shortcuts; Help Center, Feature Request
  and Contact Support open the website and GitHub), Pause ▸, Quit (⌘Q).
- The same menu is behind the **…** button at the right of the strip.

Hide the menu bar icon with Settings → General → Show in Menu Bar; the shortcut still works.

## The strip

Press **⇧⌘V** in any app. The strip slides up along the bottom of the screen you're using (over the Dock) and
slides back down when you press ⇧⌘V again, press Esc, click outside it, or paste. It never takes focus away from
the app you were in, so what you paste lands where your cursor was.

Left to right along the top: the search button, the **Clipboard** tab (your history), one tab per pinboard, **+** to
create a pinboard, and the **…** menu. While capturing is paused, a pause indicator appears at the left.

**Height.** Drag the strip's top edge to make it taller or shorter (252 to 412 points); the cards grow with it, from
compact to large. Double-click the edge to return to the default height. There's also a slider in Settings →
General.

**Keyboard.** ← → move the selection; ⇧← ⇧→ extend it; Home and End jump to the first and last card; Page Up and
Page Down move a page; ⌘A selects all. Tab moves between the search field and the cards. Typing any printable
character starts a search.

**Mouse.** Scroll horizontally, or scroll vertically: the strip turns that into horizontal scrolling. A click
selects (⇧-click for a range, ⌘-click to toggle); a double-click pastes. Right-click a card for its menu.

## Cards

Each card has a coloured header with the type (Text, Link, Image, Color, the file's name, or "N files"), how long
ago it was copied, and the source app's icon. The colour is the app's: Safari, Mail, Finder, Xcode and Keynote are
blue; Calendar, Photos and Reminders red; Pages and Books orange; Numbers green; Terminal dark grey; Photoshop,
Illustrator and Acrobat their brand colours; any other app gets a colour derived from its icon. A card pinned to a
pinboard takes the pinboard's colour instead and shows a pin dot in place of the app icon.

| Type | Body | Footer |
|---|---|---|
| Text | The text (first 20 000 characters), with the rich text's own background colour if it has one | Character count |
| Link | The page's preview image, favicon, title and domain (needs Generate Link Previews) | |
| Image | The image on a checkerboard | Pixel size pill |
| Colour | The colour, edge to edge | The #RRGGBB code |
| File(s) | Icon or thumbnail, name, path (truncated at the start) | |

While you hold ⌘, the first nine cards show their Quick Paste number. While you hold ⇧, cards show a plain-text
mark. Both modifiers can be changed in Settings → Shortcuts.

**Duplicates.** Copying something that's already in the history moves the existing card to the front rather than
adding another.

**What isn't captured.** Anything copied in a password manager; content an app marks concealed or transient; and
anything while capturing is paused. See [Settings → Privacy](#privacy).

## Pasting

- **Return** pastes the selected card(s) and closes the strip. A double-click does the same for that card.
- **⌘1 … ⌘9** paste one of the first nine visible cards (Quick Paste).
- **⇧Return** or **⇧⌘1 … ⇧⌘9** paste as plain text: fonts, colours and links are dropped. Settings → General →
  Always paste as Plain Text makes that the default.
- **Several cards** selected paste one after another, in strip order.
- **⌘C** copies the card to the clipboard without pasting or closing the strip.

**Where it goes.** Settings → General → Paste Items:

- **To active app** (default): Super Paste puts the item on the clipboard and sends ⌘V to the app in front. This
  needs **Accessibility** (System Settings → Privacy & Security → Accessibility). Super Paste asks the first time; the
  screen it shows has a button that opens the right System Settings pane. Until it's allowed, the item is copied and
  you paste it yourself.
- **To clipboard**: the item is copied and the strip closes; press ⌘V yourself. No permission needed.

## Search

Click the search button or just start typing while the strip is open. Results update as you type; Esc clears the
search, and a second Esc closes the strip.

**Words** match by prefix in the title and the full text, ignoring case and accents: `lis` finds "Lisboa" and
"Lisbon". All words must match. Put a phrase in double quotes to match the words in that order.

**Filters** narrow the results. Type them, pick them from the suggestions that appear as you type, or press **⌘F**
for the filter browser, which lists the apps, dates, devices, pinboards and types in your history. Filters appear as
tokens in the search field; click a token's × to remove it.

| Filter | Value | Notes |
|---|---|---|
| `app:` | App name by prefix (`app:Saf`), or an exact bundle id (`app:com.apple.Safari`) | Quote names with spaces: `app:"Visual Studio Code"` |
| `type:` | `text`, `link`, `image`, `file`, `color`, `unknown` | Plurals and synonyms work: `links`, `url`, `photo`, `colour`, `rich` |
| `date:` | `today`, `yesterday`, `this week`, `this month`, `this year`, `last 7 days`, `last 2 weeks`, `last 3 months`, a date `2026-10-01`, or a range `2026-10-01..2026-10-14` / `2026-10-01 to today`. A range side may be empty: `2026-10-01..` | Applies to when the item was copied |
| `device:` | The name of the Mac it was copied on, by prefix | Useful with sync |
| `pinboard:` | A pinboard's name | `pinboard:Work` |
| `title:` | Part of a title you gave the item with ⌘R | |

Filters of different kinds AND together; several of the same kind OR together: `type:image type:color app:Safari`
finds images and colours from Safari. A half-typed filter (`app:`) doesn't narrow anything; a value that can't match
(`type:video`) matches nothing.

The same syntax works in `superpaste://search?q=…` and in the MCP `search` tool's `query`.

## Pinboards

Pinboards are named, colour-coded boards next to the history for things you paste again and again: addresses,
replies, commands, colours. Cards on a pinboard keep their place when history is pruned or erased.

- **Create** with the + button or ⌘N while on a pinboard; **rename**, **recolour** (eight colours) or **delete** from
  the tab's context menu. Drag tabs to reorder them.
- **Pin** a card from its context menu (Pin ▸ lists your pinboards and offers Create Pinboard), or drag the card
  onto a tab. An item can be in several pinboards and in the history at the same time.
- **Unpin** from the same submenu. Unpinning never deletes: an item that's also in the history stays there; one that
  lived only in that pinboard moves to the history.
- **Reorder** cards within a pinboard by dragging (not while searching).
- **Switch** with ⌘← and ⌘→ (configurable), or click the tabs. `pinboard:` finds a board's items from anywhere.
- **Show in …** (⌘G) jumps from a card to the list it belongs to.

**Erase History** (right-click the Clipboard tab) clears the history. Pinned items and pinboards are kept, and the
erase can't be undone.

## Paste Stack

A Paste Stack turns ⌘V into a queue, for the moments one clipboard holds too little: moving a name, an email and an
address from a sheet into a form; pulling quotes out of a PDF; filling fields in one app from another.

1. Press **⇧⌘C**. A small Paste Stack panel appears at the top right of the screen, empty.
2. Copy the things you need, in order. Each lands in the panel as a row.
3. Click where the first one goes and press **⌘V**. The first item is pasted and leaves the stack. Keep pressing ⌘V
   for the rest; ⇥ between fields as usual.
4. Press **⇧⌘C** again (or close the panel) to end the stack. ⌘V is a normal paste again.

The arrow at the panel's top right flips the order between top-first and bottom-first. Swipe a row to delete it.
While the stack is empty it explains itself and ⌘V stays the app's own; it ends itself after the last snippet is
pasted, and Esc closes it once clicked. Items copied into a stack are also saved to the history as usual.

## Hot corner

Rest the pointer in the **bottom-left corner** of the screen and a peek of your three latest items slides out from
the edge. It never takes focus: click it to open the strip, or move the pointer away and it hides 0.6 seconds
later. It stays away from full-screen apps and fades instead of sliding when Reduce Motion is on. Settings → General
→ Hot corner chooses another corner or turns it off. If macOS already uses that corner for one of its own Hot Corners (System Settings → Desktop &
Dock → Hot Corners), Super Paste leaves it alone and says so in Settings.

## Preview, edit, rename, open, delete

All from the card's context menu, with these shortcuts:

| | Shortcut | Notes |
|---|---|---|
| Preview | Space | A window with the full content: text at full size, the image, the link's page metadata, the file's icon and path. Close with Space or Esc. |
| Edit | ⌘E | Edits text in place (not images or files); Save keeps the change. |
| Rename | ⌘R | Gives the item a title, shown in the card header and found by `title:`. |
| Open | ⌘O | A link in your browser; a file in its app ("Open with …"). Reveal in Finder is in the menu for files. |
| Copy | ⌘C | To the clipboard, without pasting. |
| Delete | ⌫ | Undo with ⌘Z, redo with ⇧⌘Z. |
| Share | | The system share sheet. |

## New Text Item

⌘N (in the strip or from the menu bar menu) opens a small window to write an item from scratch. It goes into the
list you're on: the history, or straight into the current pinboard without ever passing through the clipboard.

## Pause

Pause ▸ in the menu bar menu (or the pause indicator in the strip): for 15 minutes, 30 minutes, 1, 3 or 8 hours, or
**Until I Resume** (⌘T). While paused, nothing is captured, the menu bar icon is dimmed, and the menu shows when the
pause ends. Resume with ⌘T or from the same menu.

## Settings

⌘, or the menu bar menu. Panes:

**General** — Open at login · Show in Menu Bar · Sound effects · Paste Items: To active app / To clipboard, with
the Accessibility row · Always paste as Plain Text · Keep History (a day to a year, or Forever; pinned items are
never deleted) and Erase History… · Strip height · Hot corner.

**Privacy** — Ignore Applications (password managers are listed by default; add any app with +) · Show During
Screen Sharing (off hides the strip from screen sharing and recordings) · Generate Link Previews · Ignore
confidential content · Ignore transient content.

**Shortcuts** — Activate Super Paste · Activate Paste Stack · Show next / previous Pinboard · Quick Paste modifier
(+ 1…9) · Plain Text modifier · Reset shortcuts to default. A shortcut another app already holds shows a warning
here; Super Paste keeps trying and takes it as soon as it's free.

**Sync** — see [Sync](#sync).

**Integrations** — see [Integrations (MCP)](#integrations-mcp).

**About** — version, Install updates automatically, links.

## Sync

Keeps your history and pinboards the same on all your Macs through a folder they share: iCloud Drive, Dropbox, a
NAS, a USB drive. No account, no server; everything is encrypted on your Mac before it's written.

1. On the first Mac: Settings → Sync → **Folder sync** on, then choose the folder. A 256-bit key is generated and
   kept in this Mac's Keychain.
2. **Export Key…** saves the key as a file. Move it to your other Mac privately (AirDrop, a USB stick), not through
   the sync folder itself.
3. On the other Mac: **Import Key…**, then Folder sync on with the same folder. Both histories merge.

The pane shows the folder, the last sync time and a **Sync Now** button. Edits made on two Macs resolve the same
way everywhere: the newest change wins, and a deletion wins a tie with an edit. Pinned items stay pinned. Each Mac's
items carry that Mac's name, so `device:` finds what came from where.

Anyone who can read the folder sees only ciphertext with opaque file names. Anyone with the folder **and** your key
file can read your history: keep the key file to yourself.

## Integrations (MCP)

Settings → Integrations → **Enable MCP** lets editors and assistants on your Mac search and read your items, save
new ones and manage pinboards, once you approve each client. The server listens on `127.0.0.1` only. The pane lists
connected clients and offers **Add Client…** for tools that need a token. The full reference, including every tool's
parameters and results, is [docs/MCP.md](MCP.md).

## URL scheme

Open `superpaste://…` URLs from Shortcuts, Raycast, Alfred or Terminal (`open "superpaste://search?q=type%3Alink"`):

| URL | Action |
|---|---|
| `superpaste://` | Open the strip as it was |
| `superpaste://search?q=…` | Open the strip with a search (percent-encode the query; filters work) |
| `superpaste://list/history` · `superpaste://list/<pinboard id>` | Open the history or a pinboard |
| `superpaste://preview-item/<id>` · `superpaste://edit-item/<id>` | Preview or edit an item |
| `superpaste://new-text-item` | New Text Item |
| `superpaste://settings` · `superpaste://settings/<general\|privacy\|shortcuts\|sync\|integrations\|about>` | Settings |
| `superpaste://about` | About |
| `superpaste://enable-direct-paste` | The Accessibility screen |
| `superpaste://enable-open-at-login` | Turns Open at login on |
| `superpaste://enable-sync` | Settings → Sync |

## Updates

Super Paste checks GitHub Releases a minute after launch and then every six hours. A newer release is downloaded,
verified (its SHA-256 must match the release notes and its code signature must match the running copy), and staged
next to the app. It's installed when you quit, or when your Mac has been idle for ten minutes with the strip closed
and no Paste Stack open; Super Paste then quits and reopens in the background. Turn this off in Settings → About and
update with the one-line installer or the DMG instead.

## Troubleshooting

**⇧⌘V does nothing.** Another app holds the shortcut (another clipboard manager, often). Super Paste says so once and
shows a warning in Settings → Shortcuts. Record another shortcut there, or quit the other app.

**Return copies but doesn't paste.** Accessibility isn't allowed, or Paste Items is set to To clipboard. Check System
Settings → Privacy & Security → Accessibility, and Settings → General. After a rebuild from source, macOS may need
the permission granted again (hence `scripts/signing-setup.sh`).

**A copy didn't show up.** Capturing is paused; the app is in Ignore Applications; or the app marked the content
concealed or transient (Settings → Privacy shows the two switches).

**Link cards show no preview.** Generate Link Previews is off, or the page didn't offer one.

**The strip shows "Nothing found".** A filter can't match: check the tokens in the search field.

**Logs.** Console.app, filtered by `com.udsy.superpaste`.

## Uninstall

Quit Super Paste from its menu bar icon and delete it from Applications, or run

```bash
curl -fsSL https://udsy19.github.io/super-paste/install.sh | bash -s -- --uninstall
```

Your data stays in `~/Library/Application Support/Super Paste` and your settings in
`~/Library/Preferences/com.udsy.superpaste.plist`; delete those to remove everything. If you used sync, also delete the
Super Paste data in your sync folder.
