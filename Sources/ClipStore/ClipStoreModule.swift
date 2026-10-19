import Foundation
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, first).
public enum ClipStoreModule {
    /// Prunes the history past Keep History hourly (and once now); behaviour.md §2.9.
    @MainActor private static var retentionTimer: Timer?
    @MainActor private static var installed: SQLiteStore?
    /// What opening the app's store did beyond the ordinary (behaviour.md §1.9), for the app to tell the user once.
    @MainActor public private(set) static var recovery: StoreRecovery?

    @MainActor public static func install() {
        let store = SQLiteStore(database: SuperPastePaths.database, blobs: SuperPastePaths.blobs,
                                backup: SuperPastePaths.backup, retentionDays: { Defaults[.historyRetentionDays] })
        installed = store
        recovery = store.recovery
        Services.store = store
        Services.syncStore = store
        retentionTimer?.invalidate()
        pruneHistory(store)
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 3_600, repeats: true) { [weak store] _ in
            MainActor.assumeIsolated { if let store { pruneHistory(store) } }
        }
    }

    /// Flushes every committed write into the database file: on quit, and before an update swaps the app bundle.
    @MainActor public static func shutdown() {
        installed?.flush()
    }

    /// A store over the given files, for the self-test (which keeps them in a temporary folder). `retentionDays` is
    /// the Keep History setting it consults when applying sync records.
    @MainActor public static func makeStore(database: URL, blobs: URL, backup: URL,
                                            retentionDays: @escaping () -> Int = { HistoryRetention.forever })
        -> any ItemStoring & SyncStoring {
        openStore(database: database, blobs: blobs, backup: backup, retentionDays: retentionDays).store
    }

    /// `makeStore` with what opening did (a damaged or unopenable file).
    @MainActor public static func openStore(database: URL, blobs: URL, backup: URL,
                                            retentionDays: @escaping () -> Int = { HistoryRetention.forever })
        -> (store: any ItemStoring & SyncStoring, recovery: StoreRecovery?) {
        let store = SQLiteStore(database: database, blobs: blobs, backup: backup, retentionDays: retentionDays)
        return (store, store.recovery)
    }

    // MARK: Fault injection (self-test)

    /// Caps the database at `pages` pages (nil lifts the cap): past it, writes fail the way they do on a full disk
    /// ("database or disk is full"), without filling a disk.
    @MainActor public static func limitDatabase(_ store: any ItemStoring, toPages pages: Int?) {
        guard let store = store as? SQLiteStore else { return }
        try? store.db.execute("PRAGMA max_page_count = \(pages ?? 1_073_741_823)")
    }

    /// Stamps the schema version a newer Super Paste would (the self-test's "opened by an older app" case).
    @MainActor public static func setSchemaVersion(_ store: any ItemStoring, _ version: Int) {
        try? (store as? SQLiteStore)?.db.execute("PRAGMA user_version = \(version)")
    }

    /// `shutdown()` for a self-test store.
    @MainActor public static func flush(_ store: any ItemStoring) {
        (store as? SQLiteStore)?.flush()
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
