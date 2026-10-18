import Foundation
import SuperPasteCore
import SyncKit

// Owned by SyncKit.
func registerSyncKitTests() {
    SelfTest.cases.append(("SyncKit.install", { MainActor.assumeIsolated {
        SyncKitModule.install()
        check(Services.sync != nil, "sync registered")
    } }))
}
