import AppKit
import SuperPasteCore
import ClipStore
import ClipboardKit
import StripKit
import SettingsKit
import SyncKit
import MCPKit
import UpdateKit

/// The app shell (behaviour.md §1): an agent app (`LSUIElement`) with a menu bar item, global shortcuts and the
/// `superpaste://` URL scheme. Everything else lives in the feature modules, reached through `Services`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var shortcuts: GlobalShortcuts?

    /// Installs the modules in dependency order: the store first (it prunes past Keep History now and then hourly),
    /// then the services that read and write it, the windows that show them last. URLs that launched the app are
    /// routed after this, so every service is in place for them.
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Before the store's first prune: an install still on the old 30-day default keeps everything from now on.
        if HistoryRetention.migrateLegacyDefault() { Log.app.info("Keep History moved from the old 30-day default to Forever") }
        ClipStoreModule.install()
        ClipboardKitModule.install()
        SyncKitModule.install()
        MCPKitModule.install()
        UpdateKitModule.install()
        SettingsKitModule.install()
        StripKitModule.install()
        NSApp.mainMenu = MainMenu.make()
    }

    /// The launch sequence (behaviour.md §1.3): menu bar item and global shortcuts, pasteboard monitoring, the MCP
    /// server when enabled, onboarding until completed, background updates. Sync resumes on its own (SyncKit).
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.app.info("Super Paste \(version, privacy: .public) launched")
        statusItem = StatusItemController()
        shortcuts = GlobalShortcuts()
        Services.clipboard.start()
        if Defaults[.isMCPEnabled] { Services.mcp.start() }
        if !Services.onboarding.isCompleted { Services.onboarding.show() }
        Services.updates.start()
        StripKitModule.startHotCorner()
    }

    /// Opening the app again (Finder, Spotlight, the Dock while installing) shows the strip (behaviour.md §1.4).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Services.strip.show(nil)
        return false
    }

    /// `superpaste://` URLs (behaviour.md §15, `AppRoute`).
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch AppRoute(url: url) {
            case .strip(let route)?:
                Services.strip.show(route)
            case .settings(let pane)?:
                Services.settings.show(pane: pane)
            case .enableDirectPaste?:
                Defaults[.isDirectPasteEnabled] = true
                if !Permissions.isAccessibilityTrusted { Services.permissions.showAccessibilityAccess() }
            case .enableOpenAtLogin?:
                Services.settings.setOpenAtLogin(true)
            case nil:
                Log.app.error("Ignored an unknown URL: \(url.absoluteString, privacy: .public)")
            }
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
