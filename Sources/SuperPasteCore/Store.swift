import Foundation
import Combine

// The store contract. ClipStore implements `ItemStoring` and `SyncStoring` on one object; everything else reads and
// writes items only through these protocols (via `Services.store` / `Services.syncStore`).

/// A new item before the store has saved it: the payload with its bytes plus what capture worked out about it.
public struct ClipDraft: Sendable {
    public var entries: [EntryData]
    public var kind: ItemKind
    /// The full plain text ("" when there is none). The store keeps a preview on the item and indexes all of it.
    public var text: String
    public var title: String?
    public var sourceApp: AppRecord?
    public var device: Device?
    /// When it entered the history (normally now). Nil makes a pinned-only item and needs `pinboardID`.
    public var copiedAt: Date?
    /// Pin the item (new or existing) to this pinboard, at the end.
    public var pinboardID: UUID?
    public var imageSize: PixelSize?
    /// Downscaled preview as PNG; the store saves it as a blob.
    public var thumbnail: Data?
    public var filePaths: [String]
    public var link: LinkMetadata?

    public init(entries: [EntryData], kind: ItemKind, text: String = "", title: String? = nil,
                sourceApp: AppRecord? = nil, device: Device? = .current, copiedAt: Date? = Date(),
                pinboardID: UUID? = nil, imageSize: PixelSize? = nil, thumbnail: Data? = nil, filePaths: [String] = [],
                link: LinkMetadata? = nil) {
        self.entries = entries; self.kind = kind; self.text = text; self.title = title; self.sourceApp = sourceApp
        self.device = device; self.copiedAt = copiedAt; self.pinboardID = pinboardID; self.imageSize = imageSize
        self.thumbnail = thumbnail; self.filePaths = filePaths; self.link = link
    }

    /// A plain-text item (New Text Item, text edits, MCP `create_item`): one `public.utf8-plain-text`
    /// representation, kind from `TextClassifier`. With `pinboardID` and no `copiedAt` it is pinned-only.
    public static func text(_ string: String, title: String? = nil, sourceApp: AppRecord? = nil,
                            copiedAt: Date? = Date(), pinboardID: UUID? = nil) -> ClipDraft {
        let kind = TextClassifier.kind(of: string)
        let link = kind == .link ? TextClassifier.linkURL(in: string).map { LinkMetadata(url: $0.absoluteString) } : nil
        return ClipDraft(entries: [EntryData(reps: [RepData(type: PasteboardType.plainText, data: Data(string.utf8))])],
                         kind: kind, text: string, title: title, sourceApp: sourceApp, copiedAt: copiedAt,
                         pinboardID: pinboardID, link: link)
    }

    /// `ClipChecksum.of(entries)`: what the store dedupes on.
    public var checksum: String { ClipChecksum.of(entries) }
    public var byteSize: Int { entries.reduce(0) { $0 + $1.reps.reduce(0) { $0 + $1.data.count } } }
}

/// What `ItemStoring.insert` did.
public struct InsertResult: Sendable {
    public var item: ClipItem
    /// False when an item with the same checksum already existed and was moved to the front (and/or pinned) instead.
    public var isNew: Bool

    public init(item: ClipItem, isNew: Bool) {
        self.item = item; self.isNew = isNew
    }
}

/// Published after every committed write, on the main actor.
public enum StoreChange: Equatable, Sendable {
    case inserted([UUID])
    case updated([UUID])
    case deleted([UUID])
    /// Pinboards were created, renamed, recoloured, reordered or deleted.
    case pinboards
    /// Many things changed at once (erase, prune, sync import, reset): reload everything.
    case reloaded
}

public enum StoreError: LocalizedError, Equatable {
    case itemNotFound(UUID)
    case pinboardNotFound(UUID)
    case invalidName
    /// A pinned-only draft (no `copiedAt`) without a pinboard, or an edit that isn't allowed for the item's kind.
    case invalidContent(String)
    /// The database couldn't be opened or written.
    case database(String)

    public var errorDescription: String? {
        switch self {
        case .itemNotFound: "The item doesn't exist."
        case .pinboardNotFound: "The pinboard doesn't exist."
        case .invalidName: "The name can't be empty."
        case .invalidContent(let why): why
        case .database(let message): message
        }
    }
}

/// Items, pinboards, search and blobs (behaviour.md §2.6, §2.9, §4.7, §4.10, §5, §21).
@MainActor
public protocol ItemStoring: AnyObject {
    // MARK: Reading

    func item(_ id: UUID) -> ClipItem?
    /// The items that exist, in the order of `ids`.
    func items(_ ids: [UUID]) -> [ClipItem]
    /// Items in `scope` matching `query`, in the scope's order (see `ListScope`). Tokens AND together and match the
    /// title or full text by word prefix, ignoring case and diacritics; filters work as `SearchQuery` documents.
    func search(_ query: SearchQuery, in scope: ListScope, limit: Int, offset: Int) -> [ClipItem]
    func count(_ query: SearchQuery, in scope: ListScope) -> Int
    /// Every source app with at least one item, by name (filter suggestions).
    var apps: [AppRecord] { get }
    /// Every device with at least one item, by name.
    var devices: [Device] { get }

    // MARK: Writing items

    /// Saves a capture or a created item. When an item with the same checksum exists it is reused: a draft with
    /// `copiedAt` moves it to the front (new `copiedAt`, the draft's source app and device); a draft with
    /// `pinboardID` pins it there. Otherwise a new item is created. Throws `invalidContent` for a pinned-only draft
    /// without a pinboard.
    @discardableResult func insert(_ draft: ClipDraft) throws -> InsertResult
    /// Writes an item's fields as given (title, kind, text, pins, link, …); its blobs must already be stored.
    /// Bumps `updatedAt`. Used for undo of edits and for small changes such as link metadata.
    func update(_ item: ClipItem) throws
    /// Sets or clears (nil / empty) the user title.
    func rename(_ id: UUID, to title: String?) throws
    /// Replaces the content of an item (editor save, image rotation), keeping its id, title, pins and history place.
    @discardableResult func replaceContent(of id: UUID, with draft: ClipDraft) throws -> ClipItem
    /// Moves an item to the front of the history (`copiedAt = date`).
    func bump(_ id: UUID, at date: Date) throws
    /// Records a paste or copy-out (`lastUsedAt`); doesn't reorder.
    func markUsed(_ ids: [UUID], at date: Date) throws
    /// Deletes items, keeping them restorable with `undoLastDelete()` until the next delete or quit.
    func delete(_ ids: [UUID]) throws
    var canUndoDelete: Bool { get }
    /// Restores the most recent `delete` batch; returns the restored items.
    @discardableResult func undoLastDelete() throws -> [ClipItem]

    // MARK: Pinboards

    /// All pinboards in tab order.
    var pinboards: [Pinboard] { get }
    /// Creates a pinboard at the end of the tab bar. The name is trimmed; empty throws `invalidName`.
    @discardableResult func createPinboard(name: String, color: PinboardColor) throws -> Pinboard
    /// Saves name, colour and shortcut changes (order changes go through `reorderPinboards`).
    func updatePinboard(_ pinboard: Pinboard) throws
    /// Deletes the pinboard. Its pinned-only items are deleted; items that are also in the history stay there, and
    /// those that lose their last pin get a fresh copy date (front of the history), as with `unassign`, so retention
    /// doesn't remove them straight away.
    func deletePinboard(_ id: UUID) throws
    /// New tab order; `ids` lists every pinboard.
    func reorderPinboards(_ ids: [UUID]) throws
    /// Pins items to a pinboard, at the end, keeping their other pins. Idempotent.
    func assign(_ itemIDs: [UUID], to pinboardID: UUID) throws
    /// Unpins items from a pinboard. An item that loses its last pin goes back to history (its copy date is
    /// refreshed so retention doesn't remove it straight away); nothing is deleted.
    func unassign(_ itemIDs: [UUID], from pinboardID: UUID) throws
    /// Moves items (in the given order) to just before `beforeID` in the pinboard, or to the end when nil.
    func move(_ itemIDs: [UUID], in pinboardID: UUID, before beforeID: UUID?) throws

    // MARK: Retention

    /// How many unpinned history items are older than the cutoff for `retentionDays` (0 = forever: none).
    func prunableCount(retentionDays: Int, now: Date) -> Int
    /// Deletes unpinned history items whose `copiedAt` is before `now − retentionDays` days. Returns the count.
    /// Local only: pruning never syncs deletions, so a short retention on one Mac can't empty another Mac's history.
    @discardableResult func prune(retentionDays: Int, now: Date) throws -> Int
    /// Erase History: deletes every unpinned history item. Pinned items and pinboards stay. Returns the count.
    @discardableResult func eraseHistory() throws -> Int

    // MARK: Recognised text

    /// Stores text recognised in an image item (on-device OCR) so search can find it.
    func setRecognizedText(_ text: String, for id: UUID) throws

    // MARK: Blobs

    /// The bytes of a stored blob; nil when it's missing.
    func data(for blob: BlobRef) -> Data?
    /// The blob's file when the store keeps it as a file (large payloads), for Quick Look and drag-out; else nil.
    func fileURL(for blob: BlobRef) -> URL?
    /// Stores bytes (icons, previews fetched after capture); returns their ref. Idempotent.
    @discardableResult func saveBlob(_ data: Data) throws -> BlobRef

    // MARK: Changes

    var changes: AnyPublisher<StoreChange, Never> { get }
}

// MARK: - Sync

/// A record as it travels between Macs. Items and pinboards travel whole (last writer on `updatedAt` wins);
/// deletions travel as tombstones.
public enum SyncRecord: Codable, Hashable, Sendable {
    case item(ClipItem)
    case pinboard(Pinboard)
    case tombstone(SyncTombstone)

    public var updatedAt: Date {
        switch self {
        case .item(let item): item.updatedAt
        case .pinboard(let pinboard): pinboard.updatedAt
        case .tombstone(let tombstone): tombstone.deletedAt
        }
    }
}

public struct SyncTombstone: Codable, Hashable, Sendable {
    public enum Entity: String, Codable, Sendable { case item, pinboard }
    public var entity: Entity
    public var id: UUID
    public var deletedAt: Date

    public init(entity: Entity, id: UUID, deletedAt: Date) {
        self.entity = entity; self.id = id; self.deletedAt = deletedAt
    }
}

/// One local change in the store's journal.
public struct JournalEntry: Codable, Hashable, Sendable {
    /// Increases by one with every local write.
    public var sequence: Int64
    public var record: SyncRecord

    public init(sequence: Int64, record: SyncRecord) {
        self.sequence = sequence; self.record = record
    }
}

/// The store's side of folder sync (behaviour.md §17 replacement). The store journals every local write; SyncKit
/// reads the journal, ships records and blobs, and applies what other Macs wrote.
@MainActor
public protocol SyncStoring: AnyObject {
    /// The sequence of the newest journal entry (0 when empty).
    var journalHead: Int64 { get }
    /// Local changes with `sequence > after`, oldest first; only the latest state of each record.
    func journal(after sequence: Int64, limit: Int) -> [JournalEntry]
    /// Applies records from other Macs: a record wins when its `updatedAt` is newer than the local copy's (a
    /// tombstone deletes). Blobs the records reference must be saved first (`ItemStoring.saveBlob`). Applying
    /// doesn't journal. Returns how many records changed something.
    @discardableResult func apply(_ records: [SyncRecord]) throws -> Int
    /// Whether a blob with this digest is stored.
    func hasBlob(_ digest: String) -> Bool
}
