import AppKit
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after the services the strip uses).
public enum StripKitModule {
    @MainActor private static var hotCorner: HotCornerMonitor?

    @MainActor public static func install() {
        let strip = StripController()
        Services.strip = strip
        strip.start()
        PasteStackPanelController.shared.start()
    }

    /// Starts watching the hot corner (after launch: it installs global mouse monitors and shows a panel).
    @MainActor public static func startHotCorner() {
        let monitor = hotCorner ?? HotCornerMonitor()
        hotCorner = monitor
        monitor.start()
    }
}
