import AppKit
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch): the Settings window, onboarding and the
/// permission screens.
public enum SettingsKitModule {
    @MainActor public static func install() {
        Services.settings = SettingsWindowController()
        Services.onboarding = OnboardingController()
        Services.permissions = PermissionsController()
    }
}
