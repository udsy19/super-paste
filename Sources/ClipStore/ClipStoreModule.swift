import Foundation
import Combine
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, first).
public enum ClipStoreModule {
    @MainActor public static func install() {
        let store = PlaceholderStore()
        Services.store = store
        Services.syncStore = store
    }
}

/// Stand-in until the SQLite store lands: holds nothing and refuses writes. Delete it when `install()` registers the
/// real store.
@MainActor
final class PlaceholderStore: ItemStoring, SyncStoring {
    private let notImplemented = StoreError.database("The item store isn't implemented yet.")

    func item(_ id: UUID) -> ClipItem? { nil }
    func items(_ ids: [UUID]) -> [ClipItem] { [] }
    func search(_ query: SearchQuery, in scope: ListScope, limit: Int, offset: Int) -> [ClipItem] { [] }
    func count(_ query: SearchQuery, in scope: ListScope) -> Int { 0 }
    var apps: [AppRecord] { [] }
    var devices: [Device] { [] }

    func insert(_ draft: ClipDraft) throws -> InsertResult { throw notImplemented }
    func update(_ item: ClipItem) throws { throw notImplemented }
    func rename(_ id: UUID, to title: String?) throws { throw notImplemented }
    func replaceContent(of id: UUID, with draft: ClipDraft) throws -> ClipItem { throw notImplemented }
    func bump(_ id: UUID, at date: Date) throws { throw notImplemented }
    func markUsed(_ ids: [UUID], at date: Date) throws { throw notImplemented }
    func delete(_ ids: [UUID]) throws { throw notImplemented }
    var canUndoDelete: Bool { false }
    func undoLastDelete() throws -> [ClipItem] { throw notImplemented }

    var pinboards: [Pinboard] { [] }
    func createPinboard(name: String, color: PinboardColor) throws -> Pinboard { throw notImplemented }
    func updatePinboard(_ pinboard: Pinboard) throws { throw notImplemented }
    func deletePinboard(_ id: UUID) throws { throw notImplemented }
    func reorderPinboards(_ ids: [UUID]) throws { throw notImplemented }
    func assign(_ itemIDs: [UUID], to pinboardID: UUID) throws { throw notImplemented }
    func unassign(_ itemIDs: [UUID], from pinboardID: UUID) throws { throw notImplemented }
    func move(_ itemIDs: [UUID], in pinboardID: UUID, before beforeID: UUID?) throws { throw notImplemented }

    func prunableCount(retentionDays: Int, now: Date) -> Int { 0 }
    func prune(retentionDays: Int, now: Date) throws -> Int { 0 }
    func eraseHistory() throws -> Int { 0 }

    func data(for blob: BlobRef) -> Data? { nil }
    func fileURL(for blob: BlobRef) -> URL? { nil }
    func saveBlob(_ data: Data) throws -> BlobRef { throw notImplemented }

    var changes: AnyPublisher<StoreChange, Never> { Empty().eraseToAnyPublisher() }

    var journalHead: Int64 { 0 }
    func journal(after sequence: Int64, limit: Int) -> [JournalEntry] { [] }
    func apply(_ records: [SyncRecord]) throws -> Int { throw notImplemented }
    func hasBlob(_ digest: String) -> Bool { false }
}
