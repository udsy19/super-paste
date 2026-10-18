import AppKit
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after the services the strip uses).
public enum StripKitModule {
    @MainActor public static func install() {
        let strip = StripController()
        Services.strip = strip
        strip.start()
        PasteStackPanelController.shared.start()
    }
}
