import Foundation
import SuperPasteCore
import ClipboardKit

// Owned by ClipboardKit.
func registerClipboardKitTests() {
    SelfTest.cases.append(("ClipboardKit.install", { MainActor.assumeIsolated {
        ClipboardKitModule.install()
        check(Services.clipboard != nil && Services.pasting != nil, "monitor and pasting registered")
    } }))
}
