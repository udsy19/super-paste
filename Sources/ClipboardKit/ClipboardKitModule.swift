import AppKit
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore). The app calls
/// `Services.clipboard.start()` once it has finished launching.
public enum ClipboardKitModule {
    /// Keeps App Nap off: a napped agent app's timers slow to a crawl, and the pasteboard would be read seconds late.
    @MainActor private static var activity: NSObjectProtocol?

    @MainActor public static func install() {
        activity = activity ?? ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                                                                     reason: "Watching the clipboard")
        let environment = ClipboardEnvironment.live()
        let monitor = ClipboardMonitor(environment: environment)
        let paster = Paster(environment: environment, monitor: monitor)
        paster.trackActivations()
        Services.clipboard = monitor
        Services.pasting = paster
    }
}
