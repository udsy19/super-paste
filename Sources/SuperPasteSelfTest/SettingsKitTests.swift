import Foundation
import SuperPasteCore
import SettingsKit

// Owned by SettingsKit.
func registerSettingsKitTests() {
    SelfTest.cases.append(("SettingsKit.install", { MainActor.assumeIsolated {
        SettingsKitModule.install()
        check(Services.settings != nil && Services.onboarding != nil && Services.permissions != nil,
              "settings, onboarding and permissions registered")
    } }))
}
