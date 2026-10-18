import Foundation
import SuperPasteCore
import StripKit

// Owned by StripKit.
func registerStripKitTests() {
    SelfTest.cases.append(("StripKit.install", { MainActor.assumeIsolated {
        StripKitModule.install()
        check(Services.strip != nil, "strip registered")
    } }))
}
