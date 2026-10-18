import Foundation
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore).
public enum SyncKitModule {
    @MainActor public static func install() {
        let sync = FolderSync()
        Services.sync = sync
        // Resume once launching has finished (the store and the other services are in place by then).
        DispatchQueue.main.async { MainActor.assumeIsolated { sync.resume() } }
    }
}
