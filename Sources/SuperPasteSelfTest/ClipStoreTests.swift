import Foundation
import SuperPasteCore
import ClipStore

// Owned by ClipStore.
func registerClipStoreTests() {
    SelfTest.cases.append(("ClipStore.install", { MainActor.assumeIsolated {
        ClipStoreModule.install()
        check(Services.store != nil && Services.syncStore != nil, "store and sync store registered")
    } }))
}
