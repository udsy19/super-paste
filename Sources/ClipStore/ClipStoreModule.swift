import Foundation
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, first).
public enum ClipStoreModule {
    /// Prunes the history past Keep History hourly (and once now); behaviour.md §2.9.
    @MainActor private static var retentionTimer: Timer?

    @MainActor public static func install() {
        let store = SQLiteStore(database: SuperPastePaths.database, blobs: SuperPastePaths.blobs,
                                backup: SuperPastePaths.backup, retentionDays: { Defaults[.historyRetentionDays] })
        Services.store = store
        Services.syncStore = store
        retentionTimer?.invalidate()
        pruneHistory(store)
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak store] _ in
            MainActor.assumeIsolated { if let store { pruneHistory(store) } }
        }
    }

    /// A store over the given files, for the self-test (which keeps them in a temporary folder). `retentionDays` is
    /// the Keep History setting it consults when applying sync records.
    @MainActor public static func makeStore(database: URL, blobs: URL, backup: URL,
                                            retentionDays: @escaping () -> Int = { HistoryRetention.forever })
        -> any ItemStoring & SyncStoring {
        SQLiteStore(database: database, blobs: blobs, backup: backup, retentionDays: retentionDays)
    }

    @MainActor private static func pruneHistory(_ store: SQLiteStore) {
        do {
            let pruned = try store.prune(retentionDays: store.retentionDays(), now: Date())
            if pruned > 0 { Log.store.info("Pruned \(pruned) items past the history limit") }
        } catch {
            Log.store.error("Pruning failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
