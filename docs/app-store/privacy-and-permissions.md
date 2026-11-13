# Privacy and permissions (Store edition)

| Permission / access | Used for | When asked | Without it |
|---|---|---|---|
| Pasteboard (macOS 15.4+ "Paste from Other Apps") | reading what you copy — the core feature | existing in-app screen when `accessBehavior` is ask/deny | nothing is captured; the screen explains how to allow it |
| Post events (System Settings › Privacy & Security › Accessibility) | typing ⌘V into the front app (direct paste) | only when the user turns on "Paste items: To active app" and pastes | items go to the clipboard and a HUD says "Copied" — fully usable |
| User-selected files | sync folder, key export/import, Ignore Applications picker, import from the direct edition | open/save panels | the feature isn't set up |
| Local network server | MCP server on 127.0.0.1 | off until Settings › Integrations › Enable MCP | no MCP |
| Outgoing network | link previews of copied links | on by default, switch in Settings › Privacy | no previews |

TCC grants do not transfer between editions (different bundle id): users moving from the direct download grant the
pasteboard and Accessibility again. Verified: the system TCC database lists `kTCCServicePostEvent` for
`com.udsy.superpaste.appstore` (auth 0 until enabled) separately from the direct edition's `kTCCServiceAccessibility`.

No data collection, no analytics, no accounts, no servers (see `/PRIVACY.md`). App Store privacy label: **Data Not
Collected**. Sync is end-to-end encrypted (AES-GCM via CryptoKit) into a folder the user picks (iCloud Drive,
Dropbox, NAS…); the developer receives nothing. No `PrivacyInfo.xcprivacy` (required-reason APIs don't apply on
macOS; nothing collected). `/PRIVACY.md`'s Updates section describes the direct edition only.
