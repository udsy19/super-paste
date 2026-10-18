<h1 align="center">Super Paste</h1>

<p align="center">
  <b>A clipboard manager for your Mac.</b><br>
  Everything you copy, one shortcut away: searchable history, pinboards, a Paste Stack for pasting in sequence,
  encrypted sync through a folder you choose, and a local MCP server for your AI tools.<br>
  Free, open source and local-first.
</p>

<p align="center">
  <a href="https://github.com/udsy19/super-paste/releases/latest/download/SuperPaste.dmg"><b>Download</b></a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="PRIVACY.md">Privacy</a> ·
  <a href="docs/ARCHITECTURE.md">Architecture</a>
</p>

<p align="center">
  <a href="https://github.com/udsy19/super-paste/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/udsy19/super-paste?label=release"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple">
  <img alt="Apple silicon and Intel" src="https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-111">
  <a href="https://github.com/udsy19/super-paste/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/udsy19/super-paste/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-1f4e47"></a>
</p>

---

## Install

**One line.** Downloads the latest release, installs it into Applications and opens it:

```bash
curl -fsSL https://udsy19.github.io/super-paste/install.sh | bash
```

**Or download the [DMG](https://github.com/udsy19/super-paste/releases/latest/download/SuperPaste.dmg)**, drag Super
Paste to Applications and open it. Super Paste isn't notarized by Apple, so the first launch of a browser-downloaded
copy needs **System Settings → Privacy & Security → Open Anyway** (only once). The one-line installer doesn't need
this step.

Requires macOS 14 Sonoma or later, Apple silicon or Intel. Super Paste then keeps itself up to date in the background
(switch it off in **Settings → About**). Run the same command to update by hand; add `-s -- --uninstall` after `bash`
to remove it.

## Quick start

1. Open Super Paste. It lives in the menu bar: no Dock icon, no main window.
2. Copy things as usual. Press <kbd>⇧⌘V</kbd> in any app to open the strip along the bottom of the screen.
3. Type to search, use the arrow keys to pick, and press <kbd>Return</kbd> to paste into the app you were in.
   <kbd>⌘1</kbd>…<kbd>⌘9</kbd> pastes one of the first nine at once.
4. To paste straight into other apps, allow Accessibility when Super Paste asks. Without it, items are copied to the
   clipboard and you press <kbd>⌘V</kbd> yourself.

Click the menu bar icon to open or close the strip; right-click it (or Control- or Option-click) for the menu:
Open Super Paste, Paste Stack, New Text Item, Pause, Settings, Getting Started, About and Quit.

## Features

- **History.** Text, rich text, images, files, links and colours, with the app each came from. Copying the same thing
  again moves it to the front instead of adding a duplicate. Keep History from a day up to a year, or forever;
  pinned items are never deleted.
- **Search.** Type anywhere in the strip. Narrow it down with filters such as `app:Safari`, `type:image`,
  `date:today`, `device:`, `pinboard:` and `title:`, or press <kbd>⌘F</kbd> for the filter browser.
- **Pinboards.** Keep snippets, addresses and templates in coloured pinboards next to the history. Rename, recolour
  and reorder them from the tab bar.
- **Paste Stack.** Press <kbd>⇧⌘C</kbd>, copy a few things in a row, then press <kbd>⌘V</kbd> to paste them one by one,
  in order. Press <kbd>⇧⌘C</kbd> again to close it.
- **Preview and edit.** <kbd>Space</kbd> previews an item, <kbd>⌘E</kbd> edits text, <kbd>⌘R</kbd> gives it a title,
  <kbd>⌘N</kbd> writes a new one.
- **Plain text.** Hold <kbd>⇧</kbd> with <kbd>Return</kbd> (or with the Quick Paste number) to paste without
  formatting, or make it the default in Settings.
- **Privacy filters.** Nothing from password managers, and nothing marked confidential or temporary, is ever saved.
  Add your own apps to ignore, and pause capturing for 15 minutes to 8 hours or until you resume.
- **Folder sync.** Keep several Macs in step through a folder they share, such as one in iCloud Drive or Dropbox.
  Everything is encrypted on your Mac before it is written there.
- **MCP server.** Let AI tools on your Mac search, read and add clipboard items and manage pinboards, once you approve
  each one.
- **Native and light.** Swift and AppKit, no Electron, no third-party dependencies, no account.

## Keyboard shortcuts

The global shortcuts, next/previous pinboard and both modifiers can be changed in **Settings → Shortcuts**.

| Shortcut | Action |
|---|---|
| <kbd>⇧⌘V</kbd> | Open or close Super Paste (global) |
| <kbd>⇧⌘C</kbd> | Start or close the Paste Stack (global); while it's open, <kbd>⌘V</kbd> pastes the next item |
| <kbd>Return</kbd> · <kbd>⇧Return</kbd> | Paste the selection · as plain text |
| <kbd>⌘1</kbd>…<kbd>⌘9</kbd> · <kbd>⇧⌘1</kbd>…<kbd>⇧⌘9</kbd> | Quick Paste one of the first nine items · as plain text |
| <kbd>⌘→</kbd> / <kbd>⌘←</kbd> | Next / previous pinboard |
| <kbd>←</kbd> <kbd>→</kbd> · <kbd>⇧←</kbd> <kbd>⇧→</kbd> · <kbd>⌘A</kbd> | Move · extend the selection · select all |
| <kbd>Space</kbd> | Preview |
| <kbd>⌘C</kbd> | Copy to the clipboard without pasting |
| <kbd>⌘E</kbd> · <kbd>⌘R</kbd> · <kbd>⌘O</kbd> | Edit · rename · open (link in the browser, file in its app) |
| <kbd>⌘⌫</kbd> · <kbd>⌘Z</kbd> / <kbd>⇧⌘Z</kbd> | Delete · undo / redo |
| <kbd>⌘F</kbd> | Search filters |
| <kbd>⌘N</kbd> | New text item |
| <kbd>⌘,</kbd> | Settings |
| <kbd>Tab</kbd> | Switch between the search field and the items |
| <kbd>Esc</kbd> | Clear the search, close the preview, close the strip |

<details>
<summary><b>URL scheme</b></summary>

Automate Super Paste from Shortcuts, Raycast, Alfred or Terminal (`open "superpaste://…"`).

| URL | Action |
|---|---|
| `superpaste://` | Open the strip as it was |
| `superpaste://search?q=…` | Open the strip with a search (filters included) |
| `superpaste://list/history`, `superpaste://list/<pinboard id>` | Open the history or a pinboard |
| `superpaste://preview-item/<id>`, `superpaste://edit-item/<id>` | Preview or edit an item |
| `superpaste://new-text-item` | New text item |
| `superpaste://settings`, `superpaste://settings/<pane>` | Settings (`general`, `privacy`, `shortcuts`, `sync`, `integrations`, `about`) |
| `superpaste://about` | About |
| `superpaste://enable-direct-paste` | Paste to the active app (asks for Accessibility) |
| `superpaste://enable-open-at-login` | Open at login |

Example: `open "superpaste://search?q=type%3Alink%20app%3ASafari"`

</details>

## Privacy

Super Paste is local-first. Your history lives in a SQLite database in `~/Library/Application Support/Super Paste`,
with no account, no analytics and no telemetry. Nothing leaves your Mac unless one of these is on:

| Feature | Default | What it does |
|---|---|---|
| Install updates automatically | **On** | An anonymous HTTPS request to GitHub Releases every few hours; a newer version is downloaded, verified and installed in the background. Turn it off in **Settings → About**. |
| Generate Link Previews | **On** | When you copy a link, fetches that page's title and icon, the way a browser would. Turn it off in **Settings → Privacy**. |
| Folder sync | Off | Writes your history, encrypted on this Mac, to a folder you choose. |
| MCP server | Off | Listens on `127.0.0.1` only. The AI tools you approve can read and change your items; what they do with them is up to them. |

Details in [PRIVACY.md](PRIVACY.md).

## MCP setup

1. Turn on **Settings → Integrations → Enable MCP**. The server listens on `http://127.0.0.1:39725/mcp` (the port can
   be changed there).
2. Add it to your client. Clients that sign in through the browser (OAuth) only need the URL; you approve each one on
   Super Paste's consent page when the client opens it. Most clients take a JSON config like this:

   ```json
   {
     "mcpServers": {
       "super-paste": {
         "url": "http://127.0.0.1:39725/mcp"
       }
     }
   }
   ```

3. For a client that only starts MCP servers as commands, choose **Add Client…** in the same pane. It shows a token
   once, and a config for the bundled stdio bridge:

   ```json
   {
     "mcpServers": {
       "super-paste": {
         "command": "/Applications/Super Paste.app/Contents/MacOS/super-paste-mcp",
         "env": {
           "MCP_URL": "http://127.0.0.1:39725/mcp",
           "MCP_TOKEN": "<the token>"
         }
       }
     }
   }
   ```

Tools: `search`, `read_item`, `create_item`, `update_item`, `delete_item`, `list_pinboards`, `create_pinboard`,
`rename_pinboard`, `delete_pinboard`, `add_item_to_pinboard`, `remove_item_from_pinboard`. Deletions ask for
confirmation first, and nothing is ever written to your clipboard. Connected clients are listed in Settings, where you
can disconnect them.

## Build from source

Only the Command Line Tools are needed (`xcode-select --install`). No Xcode project, no dependencies.

```bash
git clone https://github.com/udsy19/super-paste.git && cd super-paste
./scripts/signing-setup.sh        # once: local signing identity, so permissions and Keychain access survive rebuilds
./scripts/build-app.sh            # → build/Super Paste.app   (--debug for a faster build)
open "build/Super Paste.app"
swift run SuperPasteSelfTest      # self-tests, including an end-to-end run of the modules
./scripts/make-dmg.sh             # universal DMG in dist/
```

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the modules fit together.

## Contributing

Issues and pull requests are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) to get started, and please report
security issues privately as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © Udaya Vijay Anand.

Super Paste is an independent project inspired by [Paste](https://pasteapp.io); it is not affiliated with or endorsed
by Paste or its makers.
