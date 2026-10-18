// swift-tools-version:5.10
import PackageDescription

// Super Paste — a clipboard manager for macOS. Feature modules depend only on SuperPasteCore (the contracts); the app
// target wires them together through the `Services` registry. See docs/ARCHITECTURE.md for who owns what.
let modules = [
    "ClipStore",      // SQLite store: items, pinboards, FTS5 search, content-addressed blobs, retention, undo, sync journal
    "ClipboardKit",   // pasteboard monitor and filters, capture, link previews, sounds, pasting, Paste Stack engine
    "StripKit",       // the strip panel: toolbar, search, tabs, cards, context menus, preview and editors, Paste Stack panel
    "SettingsKit",    // settings window and panes, onboarding, permission screens
    "SyncKit",        // end-to-end-encrypted folder sync
    "MCPKit",         // local MCP server: tools, OAuth and token clients
    "UpdateKit",      // background updates from GitHub Releases: check, verify, stage, swap on quit or when idle
]

let package = Package(
    name: "SuperPaste",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SuperPaste", targets: ["SuperPaste"]),
        .executable(name: "super-paste-mcp", targets: ["super-paste-mcp"]),
    ],
    targets: [
        .target(name: "SuperPasteCore", path: "Sources/SuperPasteCore"),
        .executableTarget(name: "SuperPaste", dependencies: ["SuperPasteCore"] + modules.map { .target(name: $0) },
                          path: "Sources/SuperPaste"),
        // stdio ↔ HTTP bridge for MCP clients that only speak stdio; Foundation only, bundled in Contents/MacOS.
        .executableTarget(name: "super-paste-mcp", path: "Sources/super-paste-mcp"),
        // Headless checks (Command Line Tools have no XCTest): `swift run SuperPasteSelfTest`.
        .executableTarget(name: "SuperPasteSelfTest", dependencies: ["SuperPasteCore"] + modules.map { .target(name: $0) },
                          path: "Sources/SuperPasteSelfTest"),
    ] + modules.map { name -> Target in
        name == "ClipStore"
            ? .target(name: name, dependencies: ["SuperPasteCore"], path: "Sources/\(name)",
                      linkerSettings: [.linkedLibrary("sqlite3")])
            : .target(name: name, dependencies: ["SuperPasteCore"], path: "Sources/\(name)")
    }
)
