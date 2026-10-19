import Foundation
import Combine
import SuperPasteCore

/// The item store: SQLite (WAL) for items, pinboards, search and the sync journal, `BlobStore` for payload bytes.
/// Every call runs synchronously on the main actor; one connection serves them all.
@MainActor
final class SQLiteStore: ItemStoring, SyncStoring {
    let db: Database
    let blobStore: BlobStore
    let subject = PassthroughSubject<StoreChange, Never>()

    /// The most recent `delete` batch, kept with its indexed text so `undoLastDelete` can put it back as it was.
    /// Its blobs are protected from collection while it is here.
    var undoBatch: [DeletedItem] = []

    struct DeletedItem {
        var item: ClipItem
        var body: String
        var ocr: String
    }

    /// What a removed item leaves behind for sync.
    enum Trace {
        /// Nothing: retention pruning is local policy, and other Macs keep their copies.
        case none
        /// A tombstone, so an older copy arriving later can't bring the item back (deletions applied from sync).
        case tombstone
        /// A tombstone the journal ships to other Macs (deletions the user made here).
        case journaled
    }

    /// How long an unreferenced blob survives the launch sweep: long enough for a saved blob to meet its item.
    static let sweepGrace: TimeInterval = 86_400

    /// Keep History in days (0 = forever), read when pruning and when deciding what sync may bring back.
    let retentionDays: () -> Int
    /// What opening did when it wasn't the ordinary open (`Schema.open`); nil otherwise.
    let recovery: StoreRecovery?

    init(database: URL, blobs: URL, backup: URL, retentionDays: @escaping () -> Int) {
        self.retentionDays = retentionDays
        (db, recovery) = Schema.open(database: database, blobs: blobs, backup: backup)
        blobStore = BlobStore(db: db, folder: blobs)
        // After a recovery the blob folder is exactly what salvage put there: nothing to sweep, and no file is
        // touched on a launch that already had enough go wrong.
        guard recovery == nil else { return }
        do {
            try db.transaction {
                try db.run("DELETE FROM apps WHERE NOT EXISTS (SELECT 1 FROM items WHERE app_id = apps.bundle_id)")
                try db.run("DELETE FROM devices WHERE NOT EXISTS (SELECT 1 FROM items WHERE device_id = devices.id)")
                try blobStore.sweep(savedBefore: Date().addingTimeInterval(-Self.sweepGrace))
            }
        } catch {
            Log.store.error("Launch cleanup failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Puts every committed write into the main database file (quit, and before an update replaces the app).
    func flush() {
        do { try db.checkpoint() } catch {
            Log.store.error("Checkpoint failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Reading

    func item(_ id: UUID) -> ClipItem? { items([id]).first }

    func items(_ ids: [UUID]) -> [ClipItem] {
        guard !ids.isEmpty else { return [] }
        let found = reading([]) {
            try loadItems(where: "i.id IN (SELECT value FROM json_each(?))", [json(ids.map(\.uuidString))]).map(\.1)
        }
        let byID = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    var apps: [AppRecord] {
        reading([]) {
            try db.query("""
                SELECT bundle_id, name, color_hex, icon, icon_size FROM apps
                WHERE EXISTS (SELECT 1 FROM items WHERE app_id = apps.bundle_id)
                """) { row in
                AppRecord(bundleID: row.string(0), name: row.string(1), colorHex: row.optionalString(2),
                          icon: Self.blobRef(row, 3))
            }
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var devices: [Device] {
        reading([]) {
            try db.query("""
                SELECT id, name, family, app_version FROM devices
                WHERE EXISTS (SELECT 1 FROM items WHERE device_id = devices.id)
                """) { Self.device($0, 0) }
        }.compactMap { $0 }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: - Writing items

    @discardableResult func insert(_ draft: ClipDraft) throws -> InsertResult {
        guard draft.copiedAt != nil || draft.pinboardID != nil else {
            throw StoreError.invalidContent("A pinned-only item needs a pinboard.")
        }
        let now = Date()
        let checksum = draft.checksum
        let result: InsertResult = try writing {
            if let pinboardID = draft.pinboardID { try requirePinboard(pinboardID) }
            if let existing = try db.first("""
                SELECT id FROM items WHERE checksum = ? ORDER BY coalesce(copied_at, created_at) DESC, rid DESC LIMIT 1
                """, [checksum], { $0.uuid(0) }), let id = existing, var item = try loadItem(id) {
                // §2.6: the same content again moves the existing item to the front instead of adding a copy.
                if let copiedAt = draft.copiedAt {
                    item.copiedAt = copiedAt
                    item.lastUsedAt = copiedAt
                    if let app = draft.sourceApp { item.sourceApp = app }
                    if let device = draft.device { item.device = device }
                }
                if let pinboardID = draft.pinboardID, !item.isPinned(to: pinboardID) {
                    item.pins.append(PinboardPin(pinboardID: pinboardID, order: try nextPinPosition(in: pinboardID)))
                }
                item.updatedAt = now
                let indexed = try indexedText(of: item.id)
                try write(item, body: indexed.body, ocr: indexed.ocr)
                try journal(.item, item.id)
                return InsertResult(item: item, isNew: false)
            }
            let payload = try draft.entries.map { entry in
                PasteboardEntry(reps: try entry.reps.map { PasteboardRep(type: $0.type, blob: try blobStore.save($0.data)) })
            }
            var pins: [PinboardPin] = []
            if let pinboardID = draft.pinboardID {
                pins = [PinboardPin(pinboardID: pinboardID, order: try nextPinPosition(in: pinboardID))]
            }
            let item = ClipItem(createdAt: now, updatedAt: now, copiedAt: draft.copiedAt, kind: draft.kind,
                                title: Self.normalizedTitle(draft.title), text: draft.text, textLength: draft.text.count,
                                sourceApp: draft.sourceApp, device: draft.device, byteSize: draft.byteSize,
                                checksum: checksum, pins: pins, payload: payload, imageSize: draft.imageSize,
                                thumbnail: try draft.thumbnail.map { try blobStore.save($0) }, filePaths: draft.filePaths,
                                link: draft.link)
            try write(item, body: draft.text, ocr: "")
            try journal(.item, item.id)
            return InsertResult(item: item, isNew: true)
        }
        subject.send(result.isNew ? .inserted([result.item.id]) : .updated([result.item.id]))
        return result
    }

    func update(_ item: ClipItem) throws {
        guard item.copiedAt != nil || !item.pins.isEmpty else {
            throw StoreError.invalidContent("An item needs a place in the history or a pinboard.")
        }
        try writing {
            guard let current = try loadItem(item.id) else { throw StoreError.itemNotFound(item.id) }
            for pin in item.pins { try requirePinboard(pin.pinboardID) }
            var updated = item
            updated.createdAt = current.createdAt
            updated.updatedAt = Date()
            updated.text = String(item.text.prefix(ClipItem.previewTextLimit))
            let indexed = try indexedText(of: item.id)
            let body = updated.text == current.text && updated.checksum == current.checksum
                ? indexed.body : Self.fullText(of: updated, blobs: blobStore)
            try write(updated, body: body, ocr: updated.checksum == current.checksum ? indexed.ocr : "")
            try journal(.item, item.id)
        }
        subject.send(.updated([item.id]))
    }

    func rename(_ id: UUID, to title: String?) throws {
        try writing {
            guard try exists(id) else { throw StoreError.itemNotFound(id) }
            let title = Self.normalizedTitle(title)
            try db.run("UPDATE items SET title = ?, updated_at = ? WHERE id = ?", [title, Date(), id])
            try db.run("UPDATE items_fts SET title = ? WHERE rowid = (SELECT rid FROM items WHERE id = ?)", [title ?? "", id])
            try journal(.item, id)
        }
        subject.send(.updated([id]))
    }

    @discardableResult func replaceContent(of id: UUID, with draft: ClipDraft) throws -> ClipItem {
        let item: ClipItem = try writing {
            guard var item = try loadItem(id) else { throw StoreError.itemNotFound(id) }
            // The old blobs stay until the next launch sweep, so undoing the edit (`update` with the old item) works.
            item.payload = try draft.entries.map { entry in
                PasteboardEntry(reps: try entry.reps.map { PasteboardRep(type: $0.type, blob: try blobStore.save($0.data)) })
            }
            item.kind = draft.kind
            item.text = String(draft.text.prefix(ClipItem.previewTextLimit))
            item.textLength = draft.text.count
            item.byteSize = draft.byteSize
            item.checksum = draft.checksum
            item.imageSize = draft.imageSize
            item.thumbnail = try draft.thumbnail.map { try blobStore.save($0) }
            item.filePaths = draft.filePaths
            item.link = draft.link
            item.updatedAt = Date()
            try write(item, body: draft.text, ocr: "")
            try journal(.item, id)
            return item
        }
        subject.send(.updated([id]))
        return item
    }

    func bump(_ id: UUID, at date: Date) throws {
        try writing {
            guard try exists(id) else { throw StoreError.itemNotFound(id) }
            try db.run("UPDATE items SET copied_at = ?, updated_at = ? WHERE id = ?", [date, Date(), id])
            try journal(.item, id)
        }
        subject.send(.updated([id]))
    }

    func markUsed(_ ids: [UUID], at date: Date) throws {
        // Not a synced change (`updatedAt` stays): the time travels with the item's next real change.
        let changed: [UUID] = try writing {
            try Self.unique(ids).filter { id in
                try db.run("UPDATE items SET last_used_at = ? WHERE id = ?", [date, id])
                return db.changes > 0
            }
        }
        if !changed.isEmpty { subject.send(.updated(changed)) }
    }

    func delete(_ ids: [UUID]) throws {
        let now = Date()
        let batch: [DeletedItem] = try writing {
            try Self.unique(ids).compactMap { id in
                guard let found = try loadItemWithRowID(id) else { return nil }
                let (rid, item) = found
                let indexed = try indexedText(of: id)
                try removeItem(rid: rid, id: id, at: now, trace: .journaled)
                return DeletedItem(item: item, body: indexed.body, ocr: indexed.ocr)
            }
        }
        guard !batch.isEmpty else { return }
        let dropped = undoBatch
        undoBatch = batch
        collectGarbage(Set(dropped.flatMap { $0.item.blobRefs.map(\.digest) }))
        subject.send(.deleted(batch.map(\.item.id)))
    }

    var canUndoDelete: Bool { !undoBatch.isEmpty }

    @discardableResult func undoLastDelete() throws -> [ClipItem] {
        guard !undoBatch.isEmpty else { return [] }
        let now = Date()
        let restored: [ClipItem] = try writing {
            try undoBatch.compactMap { deleted in
                guard try !exists(deleted.item.id) else { return nil }
                var item = deleted.item
                item.pins = try item.pins.filter { try pinboardExists($0.pinboardID) }
                item.updatedAt = now
                try write(item, body: deleted.body, ocr: deleted.ocr)
                try db.run("DELETE FROM tombstones WHERE entity = ? AND id = ?", [SyncTombstone.Entity.item.rawValue, item.id])
                try journal(.item, item.id)
                return item
            }
        }
        undoBatch = []
        if !restored.isEmpty { subject.send(.inserted(restored.map(\.id))) }
        return restored
    }

    // MARK: - Retention

    private static let prunable = """
        copied_at IS NOT NULL AND copied_at < ? AND NOT EXISTS (SELECT 1 FROM pins WHERE pins.item = items.rid)
        """

    func prunableCount(retentionDays: Int, now: Date) -> Int {
        guard let cutoff = HistoryRetention.cutoff(days: retentionDays, now: now) else { return 0 }
        return reading(0) { try db.first("SELECT count(*) FROM items WHERE \(Self.prunable)", [cutoff]) { $0.int(0) } ?? 0 }
    }

    /// Local only: no tombstones, nothing journaled (other Macs apply their own Keep History). `apply` keeps sync
    /// from bringing pruned items straight back.
    @discardableResult func prune(retentionDays: Int, now: Date) throws -> Int {
        guard let cutoff = HistoryRetention.cutoff(days: retentionDays, now: now) else { return 0 }
        return try deleteHistory(where: Self.prunable, [cutoff], trace: .none)
    }

    @discardableResult func eraseHistory() throws -> Int {
        // Erasing also forgets the pending undo batch: Erase History can't be undone (§2.9).
        let dropped = undoBatch
        undoBatch = []
        collectGarbage(Set(dropped.flatMap { $0.item.blobRefs.map(\.digest) }))
        return try deleteHistory(where: "copied_at IS NOT NULL AND NOT EXISTS (SELECT 1 FROM pins WHERE pins.item = items.rid)", [],
                                 trace: .journaled)
    }

    /// Deletes the unpinned history items matching `condition`.
    private func deleteHistory(where condition: String, _ arguments: [any SQLBindable], trace: Trace) throws -> Int {
        let now = Date()
        var digests = Set<String>()
        let count: Int = try writing {
            let rows = try db.query("SELECT rid, id FROM items WHERE \(condition)", arguments) { ($0.int64(0), $0.uuid(1)) }
            for (rid, id) in rows {
                guard let id else { continue }
                digests.formUnion(try removeItem(rid: rid, id: id, at: now, trace: trace))
            }
            return rows.count
        }
        guard count > 0 else { return 0 }
        collectGarbage(digests)
        subject.send(.reloaded)
        return count
    }

    // MARK: - Recognised text

    /// Fills the item's `ocr` index column. Journaled, but `updatedAt` stays: `ClipItem` doesn't carry the text, so
    /// a bump would only make other Macs rewrite an identical record (each Mac recognises its own images).
    func setRecognizedText(_ text: String, for id: UUID) throws {
        try writing {
            guard try exists(id) else { throw StoreError.itemNotFound(id) }
            try db.run("UPDATE items_fts SET ocr = ? WHERE rowid = (SELECT rid FROM items WHERE id = ?)", [text, id])
            try journal(.item, id)
        }
        subject.send(.updated([id]))
    }

    // MARK: - Blobs

    func data(for blob: BlobRef) -> Data? { blobStore.data(for: blob) }

    func fileURL(for blob: BlobRef) -> URL? { blobStore.fileURL(for: blob) }

    @discardableResult func saveBlob(_ data: Data) throws -> BlobRef {
        try writing { try blobStore.save(data) }
    }

    func hasBlob(_ digest: String) -> Bool { blobStore.has(digest) }

    // MARK: - Changes

    var changes: AnyPublisher<StoreChange, Never> { subject.eraseToAnyPublisher() }
}

// MARK: - Shared helpers

extension SQLiteStore {
    /// Runs a write in one transaction, mapping SQLite and file failures to `StoreError.database` with a message in
    /// plain words (a full disk is named as such, whichever layer noticed it first).
    func writing<T>(_ body: () throws -> T) throws -> T {
        do {
            return try db.transaction(body)
        } catch let error as StoreError {
            throw error
        } catch {
            Log.store.error("Write failed: \(String(describing: error), privacy: .public)")
            throw StoreError.database(Self.describe(error))
        }
    }

    /// What went wrong, for the user: "the disk is full", else SQLite's or the file system's own words.
    static func describe(_ error: Error) -> String {
        if let failure = error as? Database.Failure {
            return failure.isFull ? StoreError.diskFullMessage : failure.message
        }
        let nsError = error as NSError
        let full = (nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteOutOfSpaceError)
            || (nsError.domain == NSPOSIXErrorDomain && nsError.code == Int(ENOSPC))
            || ((nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { $0.domain == NSPOSIXErrorDomain && $0.code == Int(ENOSPC) } ?? false)
        return full ? StoreError.diskFullMessage : error.localizedDescription
    }

    /// Runs a read; a failure is logged and gives `fallback`.
    func reading<T>(_ fallback: T, _ body: () throws -> T) -> T {
        do {
            return try body()
        } catch {
            Log.store.error("Read failed: \(String(describing: error), privacy: .public)")
            return fallback
        }
    }

    /// Deletes blobs among `digests` that nothing references any more (the undo batch's stay).
    func collectGarbage(_ digests: Set<String>) {
        guard !digests.isEmpty else { return }
        let protected = Set(undoBatch.flatMap { $0.item.blobRefs.map(\.digest) })
        do {
            try db.transaction { try blobStore.collect(digests, protecting: protected) }
        } catch {
            Log.store.error("Collecting blobs failed: \(String(describing: error), privacy: .public)")
        }
    }

    func exists(_ id: UUID) throws -> Bool {
        try db.first("SELECT 1 FROM items WHERE id = ?", [id]) { _ in true } ?? false
    }

    func pinboardExists(_ id: UUID) throws -> Bool {
        try db.first("SELECT 1 FROM pinboards WHERE id = ?", [id]) { _ in true } ?? false
    }

    func requirePinboard(_ id: UUID) throws {
        guard try pinboardExists(id) else { throw StoreError.pinboardNotFound(id) }
    }

    /// Just past the last pin of the pinboard.
    func nextPinPosition(in pinboardID: UUID) throws -> Double {
        try db.first("SELECT coalesce(max(position), 0) + 1 FROM pins WHERE pinboard = ?", [pinboardID]) { $0.double(0) } ?? 1
    }

    /// The indexed full text and recognised text of an item ("" when it has none).
    func indexedText(of id: UUID) throws -> (body: String, ocr: String) {
        try db.first("SELECT body, ocr FROM items_fts WHERE rowid = (SELECT rid FROM items WHERE id = ?)", [id]) {
            ($0.string(0), $0.string(1))
        } ?? ("", "")
    }

    /// Removes an item and its payload, pin and index rows, leaving `trace` for sync. Returns the blob digests it
    /// referenced, for collection.
    @discardableResult
    func removeItem(rid: Int64, id: UUID, at date: Date, trace: Trace) throws -> Set<String> {
        let digests = try db.query("""
            SELECT blob FROM representations WHERE item = ?1
            UNION SELECT thumbnail FROM items WHERE rid = ?1 AND thumbnail IS NOT NULL
            UNION SELECT link_icon FROM items WHERE rid = ?1 AND link_icon IS NOT NULL
            UNION SELECT link_image FROM items WHERE rid = ?1 AND link_image IS NOT NULL
            """, [rid]) { $0.string(0) }
        try db.run("DELETE FROM items_fts WHERE rowid = ?", [rid])
        try db.run("DELETE FROM items WHERE rid = ?", [rid])
        switch trace {
        case .none:
            // Nothing for other Macs, not even an earlier pending change of this item.
            try db.run("DELETE FROM journal WHERE entity = ? AND id = ?", [SyncTombstone.Entity.item.rawValue, id])
        case .tombstone:
            try recordTombstone(.item, id, at: date)
        case .journaled:
            try recordTombstone(.item, id, at: date)
            try journal(.item, id)
        }
        return Set(digests)
    }

    /// Writes every column of `item` (inserting or replacing by id) with its payload, pins and index row. Pins to
    /// pinboards that don't exist are dropped.
    @discardableResult
    func write(_ item: ClipItem, body: String, ocr: String) throws -> Int64 {
        try upsert(item.sourceApp)
        try upsert(item.device)
        let columns = Self.itemArguments(item)
        let rid: Int64
        if let existing = try db.first("SELECT rid FROM items WHERE id = ?", [item.id], { $0.int64(0) }) {
            rid = existing
            try db.run("UPDATE items SET (\(Self.itemColumnNames)) = (\(Self.placeholders(columns.count))) WHERE rid = ?",
                       columns + [rid])
            try db.run("DELETE FROM representations WHERE item = ?", [rid])
            try db.run("DELETE FROM pins WHERE item = ?", [rid])
            try db.run("DELETE FROM items_fts WHERE rowid = ?", [rid])
        } else {
            try db.run("INSERT INTO items (\(Self.itemColumnNames)) VALUES (\(Self.placeholders(columns.count)))", columns)
            rid = db.lastInsertRowID
        }
        for (entryIndex, entry) in item.payload.enumerated() {
            for (position, rep) in entry.reps.enumerated() {
                try db.run("INSERT INTO representations (item, entry, position, type, blob, size) VALUES (?, ?, ?, ?, ?, ?)",
                           [rid, entryIndex, position, rep.type, rep.blob.digest, rep.blob.size])
            }
        }
        for pin in item.pins {
            try db.run("""
                INSERT OR IGNORE INTO pins (pinboard, item, position)
                SELECT ?1, ?2, ?3 WHERE EXISTS (SELECT 1 FROM pinboards WHERE id = ?1)
                """, [pin.pinboardID, rid, pin.order])
        }
        try db.run("INSERT INTO items_fts (rowid, title, body, app, ocr) VALUES (?, ?, ?, ?, ?)",
                   [rid, item.title ?? "", body, item.sourceApp?.name ?? "", ocr])
        return rid
    }

    private func upsert(_ app: AppRecord?) throws {
        guard let app else { return }
        let oldName = try db.first("SELECT name FROM apps WHERE bundle_id = ?", [app.bundleID]) { $0.string(0) }
        try db.run("""
            INSERT INTO apps (bundle_id, name, color_hex, icon, icon_size) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT (bundle_id) DO UPDATE SET name = excluded.name,
                color_hex = coalesce(excluded.color_hex, apps.color_hex),
                icon_size = CASE WHEN excluded.icon IS NULL THEN apps.icon_size ELSE excluded.icon_size END,
                icon = coalesce(excluded.icon, apps.icon)
            """, [app.bundleID, app.name, app.colorHex, app.icon?.digest, app.icon?.size])
        if let oldName, oldName != app.name {
            try db.run("UPDATE items_fts SET app = ? WHERE rowid IN (SELECT rid FROM items WHERE app_id = ?)",
                       [app.name, app.bundleID])
        }
    }

    private func upsert(_ device: Device?) throws {
        guard let device else { return }
        try db.run("""
            INSERT INTO devices (id, name, family, app_version) VALUES (?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET name = excluded.name, family = excluded.family,
                app_version = coalesce(excluded.app_version, devices.app_version)
            """, [device.id, device.name, device.family.rawValue, device.appVersion])
    }

    // MARK: Loading

    static let selectColumns = """
        i.rid, i.id, i.created_at, i.updated_at, i.copied_at, i.last_used_at, i.kind, i.title, i.text, i.text_length,
        i.byte_size, i.checksum, i.image_width, i.image_height, i.thumbnail, i.thumbnail_size, i.file_paths,
        i.link_url, i.link_title, i.link_icon, i.link_icon_size, i.link_image, i.link_image_size, i.link_fetched_at,
        a.bundle_id, a.name, a.color_hex, a.icon, a.icon_size, d.id, d.name, d.family, d.app_version
        """
    static let selectJoins = "LEFT JOIN apps a ON a.bundle_id = i.app_id LEFT JOIN devices d ON d.id = i.device_id"

    func loadItem(_ id: UUID) throws -> ClipItem? { try loadItemWithRowID(id)?.1 }

    func loadItemWithRowID(_ id: UUID) throws -> (Int64, ClipItem)? {
        let rows = try db.query("SELECT \(Self.selectColumns) FROM items i \(Self.selectJoins) WHERE i.id = ?", [id]) {
            ($0.int64(0), try Self.decodeItem($0))
        }
        guard let row = rows.first else { return nil }
        return (row.0, try hydrate([row])[0])
    }

    /// Items matching a WHERE condition over `items i`, unordered, with their row ids.
    func loadItems(where condition: String, _ arguments: [any SQLBindable]) throws -> [(Int64, ClipItem)] {
        let rows = try db.query("SELECT \(Self.selectColumns) FROM items i \(Self.selectJoins) WHERE \(condition)", arguments) {
            ($0.int64(0), try Self.decodeItem($0))
        }
        return zip(rows.map(\.0), try hydrate(rows)).map { ($0, $1) }
    }

    /// Fills in pins (in tab order) and payloads for decoded item rows.
    func hydrate(_ rows: [(Int64, ClipItem)]) throws -> [ClipItem] {
        guard !rows.isEmpty else { return [] }
        let rids = json(rows.map(\.0))
        var pins: [Int64: [PinboardPin]] = [:]
        for (rid, pin) in try db.query("""
            SELECT pins.item, pins.pinboard, pins.position FROM pins JOIN pinboards p ON p.id = pins.pinboard
            WHERE pins.item IN (SELECT value FROM json_each(?)) ORDER BY p.position, p.created_at
            """, [rids], { row in (row.int64(0), row.uuid(1).map { PinboardPin(pinboardID: $0, order: row.double(2)) }) }) {
            if let pin { pins[rid, default: []].append(pin) }
        }
        var payloads: [Int64: [PasteboardEntry]] = [:]
        for (rid, entry, rep) in try db.query("""
            SELECT item, entry, type, blob, size FROM representations WHERE item IN (SELECT value FROM json_each(?))
            ORDER BY item, entry, position
            """, [rids], { ($0.int64(0), $0.int(1), PasteboardRep(type: $0.string(2), blob: BlobRef(digest: $0.string(3), size: $0.int(4)))) }) {
            var entries = payloads[rid] ?? []
            while entries.count <= entry { entries.append(PasteboardEntry(reps: [])) }
            entries[entry].reps.append(rep)
            payloads[rid] = entries
        }
        return rows.map { rid, item in
            var item = item
            item.pins = pins[rid] ?? []
            item.payload = payloads[rid] ?? []
            return item
        }
    }

    static func decodeItem(_ row: Row) throws -> ClipItem {
        guard let id = row.uuid(1) else { throw StoreError.database("An item has a malformed id.") }
        var item = ClipItem(id: id, createdAt: row.date(2), updatedAt: row.date(3), copiedAt: row.optionalDate(4),
                            lastUsedAt: row.optionalDate(5), kind: ItemKind(rawValue: row.string(6)) ?? .unknown,
                            title: row.optionalString(7), text: "", textLength: row.int(9),
                            byteSize: row.int(10), checksum: row.string(11))
        item.text = row.string(8)
        if let width = row.optionalInt(12), let height = row.optionalInt(13) {
            item.imageSize = PixelSize(width: width, height: height)
        }
        item.thumbnail = blobRef(row, 14)
        if let paths = row.optionalString(16), let decoded = try? JSONDecoder().decode([String].self, from: Data(paths.utf8)) {
            item.filePaths = decoded
        }
        if let url = row.optionalString(17) {
            item.link = LinkMetadata(url: url, title: row.optionalString(18), icon: blobRef(row, 19), image: blobRef(row, 21),
                                     fetchedAt: row.optionalDate(23))
        }
        if let bundleID = row.optionalString(24) {
            item.sourceApp = AppRecord(bundleID: bundleID, name: row.string(25), colorHex: row.optionalString(26),
                                       icon: blobRef(row, 27))
        }
        item.device = device(row, 29)
        return item
    }

    static func blobRef(_ row: Row, _ column: Int32) -> BlobRef? {
        row.optionalString(column).map { BlobRef(digest: $0, size: row.int(column + 1)) }
    }

    static func device(_ row: Row, _ column: Int32) -> Device? {
        guard let id = row.optionalString(column) else { return nil }
        return Device(id: id, name: row.string(column + 1), family: DeviceFamily(rawValue: row.string(column + 2)) ?? .mac,
                      appVersion: row.optionalString(column + 3))
    }

    // MARK: Item columns

    nonisolated static let itemColumnNames = """
        id, created_at, updated_at, copied_at, last_used_at, kind, title, text, text_length, app_id, device_id, byte_size,
        checksum, image_width, image_height, thumbnail, thumbnail_size, file_paths, link_url, link_title, link_icon,
        link_icon_size, link_image, link_image_size, link_fetched_at
        """

    static func itemArguments(_ item: ClipItem) -> [any SQLBindable] {
        let paths: String? = item.filePaths.isEmpty ? nil : json(item.filePaths)
        return [
            item.id, item.createdAt, item.updatedAt, item.copiedAt, item.lastUsedAt, item.kind.rawValue, item.title,
            String(item.text.prefix(ClipItem.previewTextLimit)), item.textLength, item.sourceApp?.bundleID, item.device?.id,
            item.byteSize, item.checksum, item.imageSize?.width, item.imageSize?.height, item.thumbnail?.digest,
            item.thumbnail?.size, paths, item.link?.url, item.link?.title, item.link?.icon?.digest, item.link?.icon?.size,
            item.link?.image?.digest, item.link?.image?.size, item.link?.fetchedAt,
        ]
    }

    static func placeholders(_ count: Int) -> String { Array(repeating: "?", count: count).joined(separator: ", ") }

    /// A user title as stored: trimmed, nil when empty.
    static func normalizedTitle(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The text to index for an item whose full text the store doesn't have (sync, edit undo): the payload's plain
    /// text when it extends the preview, else the preview.
    static func fullText(of item: ClipItem, blobs: BlobStore) -> String {
        for entry in item.payload {
            guard let rep = entry.rep(PasteboardType.plainText), let data = blobs.data(for: rep.blob),
                  let text = String(data: data, encoding: .utf8) else { continue }
            if String(text.prefix(ClipItem.previewTextLimit)) == item.text { return text }
        }
        return item.text
    }

    static func unique(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}

/// A JSON array for `json_each(?)` parameters.
func json<T: Encodable>(_ values: T) -> String {
    (try? String(data: JSONEncoder().encode(values), encoding: .utf8)) ?? "[]"
}
