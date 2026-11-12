# Compliance matrix (Store edition)

| Feature | Implementation | Classification | Store status | Evidence |
|---|---|---|---|---|
| Clipboard monitoring | `NSPasteboard.general` polling (`changeCount`) | compatible | works sandboxed | test-results §3 |
| Privacy exclusions | frontmost app via `NSWorkspace`, `org.nspasteboard.*` markers, ignored-app list | compatible | works sandboxed | §3 (concealed item skipped) |
| History, search, pinboards, Paste Stack, editors | SQLite+FTS5 in the container | compatible | works sandboxed | §3, §4 (MCP search/create), self-tests |
| Global shortcuts | Carbon `RegisterEventHotKey` (no event tap, no Input Monitoring) | compatible | works sandboxed | §6 |
| Hot corner peek | `NSEvent` global mouse monitor | compatible (contrary to brief addendum §1; observed working) | works sandboxed; Dock conflict check skipped | §6, §9 |
| Copy to clipboard (default) | pasteboard write | compatible | works sandboxed | §6 |
| Direct paste (⌘V into the front app) | `CGEvent` post at HID tap, gated by `CGPreflight/RequestPostEventAccess` | compatible-with-config; **review risk 2.4.5** | request path verified; granted path needs human run; off by default | §7 |
| Copied files (paste/open/preview/share) | security-scoped bookmarks per path | compatible-after-architecture-change | works across relaunch | §5 |
| Link previews | LinkPresentation over network.client | compatible-with-config | works | §3 |
| Encrypted folder sync | AES-256-GCM files in a user-chosen folder; folder kept by security-scoped bookmark | compatible-after-architecture-change | logic verified; sandboxed picker+relaunch needs human run | §8 |
| Local MCP server | Network.framework on 127.0.0.1, OAuth/PKCE or tokens | compatible-with-config (network.server) | works sandboxed | §4 |
| MCP stdio bridge | own sandbox + network.client + embedded Info.plist; HTTP to 127.0.0.1 | compatible-after-architecture-change | works when launched by an outside process | §4 |
| Open at login | `SMAppService.mainApp` | compatible | not exercised (needs click) | — |
| Updater (GitHub Releases) | UpdateKit | incompatible-confirmed (2.4.5(vii)/App Store updates) | compiled out | §2 |
| Import from direct edition | NSOpenPanel → copy → apply at next launch | compatible | logic self-tested; panel needs human run | `Core.directEditionImport` |
| Sounds, HUD, menu bar item, onboarding | AppKit, `/System/Library/Sounds` | compatible | works | launch logs, no denials |

Guideline notes: 2.4.5(i) sandbox ✓; 2.4.5(ii) nothing outside the container except user-selected folders, no
symlinks/installs, no other apps' config written ✓; 2.4.5(iv) no downloaded code ✓; 2.4.5(vii) updates via the App
Store only ✓; 2.5.2 no executable downloads ✓; 4.2 substantial native app ✓. Risk: 2.4.5 "Accessibility for
non-accessibility purposes" for direct paste — mitigated by copy-only default and review notes; owner decision.
