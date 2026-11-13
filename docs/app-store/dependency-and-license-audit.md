# Dependency and license audit

`Package.swift` has **no package dependencies**. Everything is Apple SDK frameworks plus the system `libsqlite3`.

| Component | Version | License | Kind | Bundled | Sandbox OK |
|---|---|---|---|---|---|
| Super Paste source | 1.0.3 | MIT (`/LICENSE`) | first-party | yes | yes |
| AppKit, SwiftUI, Combine, Foundation, Network, CryptoKit, Security, LinkPresentation, QuickLookThumbnailing, Quartz, WebKit (link preview pane), IOKit (platform UUID for the device id), SystemConfiguration (computer name), ServiceManagement, Carbon.HIToolbox, AudioToolbox, ImageIO, UniformTypeIdentifiers | macOS SDK 26.5 | Apple SDK | system framework | no (OS) | yes |
| SQLite (`libsqlite3.tbd`) | system | public domain | system library | no (OS) | yes |
| `super-paste-mcp` | same build | MIT | first-party helper executable | yes (`Contents/MacOS`) | yes (own sandbox) |

No GPL/LGPL code, no Homebrew or `/usr/local` references, no downloaded assets or models. Fonts: system fonts only.
Export compliance: the app implements file encryption for sync (AES-256-GCM, HKDF-SHA256, via CryptoKit) — see
`app-store-connect.md`; do not set `ITSAppUsesNonExemptEncryption` without the owner's answer.
