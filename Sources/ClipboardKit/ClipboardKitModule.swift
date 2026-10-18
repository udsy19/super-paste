import AppKit
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore). The app calls
/// `Services.clipboard.start()` once it has finished launching.
public enum ClipboardKitModule {
    @MainActor public static func install() {
        let environment = ClipboardEnvironment.live()
        let monitor = ClipboardMonitor(environment: environment)
        let paster = Paster(environment: environment, monitor: monitor)
        paster.trackActivations()
        Services.clipboard = monitor
        Services.pasting = paster
    }
}
