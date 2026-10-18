import AppKit
import SuperPasteCore
import ClipStore
import ClipboardKit
import StripKit
import SettingsKit
import SyncKit
import MCPKit
import UpdateKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var shortcuts: GlobalShortcuts?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Order matters: the store first, then the services that read and write it, the windows that show them last.
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
    /// server when enabled, onboarding until completed, background updates.
    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        Log.app.info("Super Paste \(version, privacy: .public) launched")
        statusItem = StatusItemController()
        shortcuts = GlobalShortcuts()
        Services.clipboard.start()
        if Defaults[.isMCPEnabled] { Services.mcp.start() }
        if !Services.onboarding.isCompleted { Services.onboarding.show() }
        Services.updates.start()
    }

    /// Opening the app again (Finder, Spotlight) shows the strip.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Services.strip.show(nil)
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            switch AppRoute(url: url) {
            case .strip(let route)?: Services.strip.show(route)
            case .settings(let pane)?: Services.settings.show(pane: pane)
            case nil: Log.app.error("Ignored an unknown URL: \(url.absoluteString, privacy: .public)")
            }
        }
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
