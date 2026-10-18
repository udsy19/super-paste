import AppKit
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch).
public enum SettingsKitModule {
    @MainActor public static func install() {
        let settings = PlaceholderSettings()
        Services.settings = settings
        Services.onboarding = settings
        Services.permissions = settings
    }
}

/// Stand-in until Settings, onboarding and the permission screens land: shows nothing. Delete it when `install()`
/// registers the real services.
@MainActor
final class PlaceholderSettings: SettingsPresenting, OnboardingPresenting, PermissionsPresenting {
    func show(pane: SettingsPane?) { Log.settings.info("Settings aren't implemented yet") }
    var isCompleted: Bool { Defaults[.isOnboardingCompleted] }
    func show() { Log.settings.info("Onboarding isn't implemented yet") }
    func requestDirectPaste(into appName: String?, completion: @escaping @MainActor (DirectPasteChoice) -> Void) {
        completion(.copyToClipboard)
    }
    func showAccessibilityAccess() {}
    func showPasteboardAccess() {}
}
