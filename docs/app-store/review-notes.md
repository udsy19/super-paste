# Notes for App Review

Super Paste is a clipboard manager. No account or sign-in is needed.

- **Try it:** copy some text in any app, press **Shift-Command-V**, the strip appears at the bottom of the screen;
  choose an item and press Return — it goes to the clipboard (the default). The menu bar icon opens the same strip.
- **Accessibility (optional):** only if the user switches Settings › General › Paste items to "To active app" does
  Super Paste ask to post events (listed under Accessibility). It is used for one thing: pressing ⌘V in the app the
  user was working in, right after they pick an item. It never reads other apps' interfaces or keystrokes. Without
  it everything works and items are copied to the clipboard instead.
- **Clipboard access:** reading the pasteboard is the app's core function; on macOS 15.4+ the app shows how to allow it.
- **Local MCP server (optional, off by default):** Settings › Integrations › Enable MCP. It listens only on
  127.0.0.1 and requires the user's approval (OAuth consent page or a token they create). The bundled
  `Contents/MacOS/super-paste-mcp` is a sandboxed helper that MCP clients launch; it only connects to that local
  server. The app never edits other apps' configuration files; it shows a snippet the user copies.
- **Sync (optional):** encrypted files in a folder the user picks; no server of ours.
- **Network:** only link previews of links the user copies (can be turned off) and the local MCP server.
- **Updates:** come only from the App Store; the direct-download updater is not in this build.
