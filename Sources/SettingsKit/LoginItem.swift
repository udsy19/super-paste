import AppKit
import ServiceManagement
import SuperPasteCore

/// Open at login through `SMAppService.mainApp` (behaviour.md §1.5). `Defaults[.openAtLogin]` mirrors it.
@MainActor
enum LoginItem {
    /// Only an app bundle can be a login item (`swift run` can't).
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Registers or unregisters the login item and stores the result. When macOS wants the user's approval, Login
    /// Items in System Settings opens.
    static func set(_ enabled: Bool) {
        guard isAvailable else {
            Log.settings.info("Open at login needs the app bundle; not running from one")
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Alerts.error(Strings.General.openAtLoginFailed, error)
        }
        refresh()
    }

    /// Brings the setting in line with the system (the user may have removed the item in System Settings).
    static func refresh() {
        guard isAvailable else { return }
        let enabled = SMAppService.mainApp.status == .enabled
        if Defaults[.openAtLogin] != enabled { Defaults[.openAtLogin] = enabled }
    }
}
