# App Store Connect draft

- **Name:** Super Paste · **Bundle ID:** `com.udsy.superpaste.appstore` (owner may change before registering) ·
  **SKU:** superpaste-mac · **Category:** Productivity · **Price:** owner decision (the direct edition is free/MIT).
- **Minimum macOS:** 14.0 · **Architectures:** universal (arm64 + x86_64) via `package-appstore.sh`.
- **Subtitle (30):** Clipboard history that's fast
- **Promotional text:** Everything you copy, searchable in an instant. Pin favourites to pinboards, paste several items
  in order with Paste Stack, and keep it all on your Mac.
- **Description:**
  Super Paste remembers what you copy — text, links, images, files and colours — so you can find it again and
  paste it anywhere. Press ⇧⌘V to open the strip at the bottom of the screen, type to search (filters like
  `app:Mail type:link`), and press Return.
  • Clipboard history that you keep for as long as you like
  • Pinboards for snippets you reuse
  • Paste Stack (⇧⌘C): collect several items, paste them one after another
  • Plain-text pasting, previews and in-place editing
  • Skips password managers and content apps mark as confidential
  • Optional end-to-end-encrypted sync through a folder you choose (iCloud Drive, Dropbox, a NAS)
  • Optional local MCP server so AI assistants on your Mac can search your history — only with your approval
  • Optional direct paste into the app you're using (needs Accessibility; off by default)
  No account, no tracking, no servers.
- **Keywords:** clipboard,history,paste,pinboard,snippets,copy,manager,productivity,MCP,stack
- **Support URL:** https://github.com/udsy19/super-paste/issues · **Marketing URL:** https://udsy19.github.io/super-paste/
- **Privacy policy URL:** the repository's `PRIVACY.md` (host it on the website) · **Privacy label:** Data Not Collected.
- **Age rating:** 4+.
- **Screenshots:** to be captured on a signed build (strip, search, pinboards, Paste Stack, Settings).
- **Export compliance (owner decision):** the app encrypts sync files with AES-256-GCM (CryptoKit) to protect the
  user's own data. This is typically answered "uses encryption, exempt" (standard algorithms from the OS, user-data
  protection) — the owner must confirm and answer in App Store Connect; `ITSAppUsesNonExemptEncryption` is
  deliberately not set in Info.plist.
