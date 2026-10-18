import Foundation
import SuperPasteCore

// The store's side of folder sync (behaviour.md §17 replacement). Every local write puts its record in `journal`
// (one row per record, re-sequenced on each write, so a cursor sees only the latest state); `apply` merges records
// from other Macs last-writer-wins on `updatedAt`, with tombstones that keep deleted records from coming back.
//
// Retention is local: pruning leaves no tombstone and drops the item's journal row. So that sync doesn't bring a
// pruned item straight back, an item record for an id this Mac doesn't have is skipped when it is unpinned history
// (no pin to a pinboard that exists here) whose `copiedAt` is before this Mac's Keep History cutoff: retention would
// prune it on arrival. It comes back once another Mac copies it again (a newer `copiedAt`) or pins it.
extension SQLiteStore {
    var journalHead: Int64 {
        reading(0) { try db.first("SELECT coalesce(max(sequence), 0) FROM journal") { $0.int64(0) } ?? 0 }
    }

    func journal(after sequence: Int64, limit: Int) -> [JournalEntry] {
        guard limit > 0 else { return [] }
        return reading([]) {
            let rows = try db.query("SELECT sequence, entity, id FROM journal WHERE sequence > ? ORDER BY sequence LIMIT ?",
                                    [sequence, limit]) { ($0.int64(0), SyncTombstone.Entity(rawValue: $0.string(1)), $0.uuid(2)) }
            return try rows.compactMap { sequence, entity, id in
                guard let entity, let id else { return nil }
                return try record(entity, id).map { JournalEntry(sequence: sequence, record: $0) }
            }
        }
    }

    @discardableResult func apply(_ records: [SyncRecord]) throws -> Int {
        var pinboards: [Pinboard] = [], items: [ClipItem] = [], tombstones: [SyncTombstone] = []
        for record in records {
            switch record {
            case .pinboard(let pinboard): pinboards.append(pinboard)
            case .item(let item): items.append(item)
            case .tombstone(let tombstone): tombstones.append(tombstone)
            }
        }
        var digests = Set<String>()
        // Pinboards first so items can pin to them; tombstones last so a deletion wins over an older record in the
        // same batch.
        let changed: Int = try writing {
            var changed = 0
            for pinboard in pinboards where try applyPinboard(pinboard) { changed += 1 }
            for item in items {
                if let replaced = try applyItem(item) { digests.formUnion(replaced); changed += 1 }
            }
            for tombstone in tombstones {
                if let removed = try applyTombstone(tombstone) { digests.formUnion(removed); changed += 1 }
            }
            return changed
        }
        collectGarbage(digests)
        if changed > 0 { subject.send(.reloaded) }
        return changed
    }

    // MARK: - Journal

    /// Puts a record (by entity and id) at the head of the journal.
    func journal(_ entity: SyncTombstone.Entity, _ id: UUID) throws {
        try db.run("INSERT OR REPLACE INTO journal (entity, id) VALUES (?, ?)", [entity.rawValue, id])
    }

    func recordTombstone(_ entity: SyncTombstone.Entity, _ id: UUID, at date: Date) throws {
        try db.run("""
            INSERT INTO tombstones (entity, id, deleted_at) VALUES (?, ?, ?)
            ON CONFLICT (entity, id) DO UPDATE SET deleted_at = max(deleted_at, excluded.deleted_at)
            """, [entity.rawValue, id, date])
    }

    /// The current state of a journaled record: the item or pinboard, else its tombstone.
    private func record(_ entity: SyncTombstone.Entity, _ id: UUID) throws -> SyncRecord? {
        switch entity {
        case .item: if let item = try loadItem(id) { return .item(item) }
        case .pinboard: if let pinboard = try loadPinboard(id) { return .pinboard(pinboard) }
        }
        return try tombstoneDate(entity, id).map { .tombstone(SyncTombstone(entity: entity, id: id, deletedAt: $0)) }
    }

    private func tombstoneDate(_ entity: SyncTombstone.Entity, _ id: UUID) throws -> Date? {
        try db.first("SELECT deleted_at FROM tombstones WHERE entity = ? AND id = ?", [entity.rawValue, id]) { $0.date(0) }
    }

    // MARK: - Applying

    private func applyPinboard(_ pinboard: Pinboard) throws -> Bool {
        if let local = try loadPinboard(pinboard.id) {
            guard pinboard.updatedAt > local.updatedAt else { return false }
        } else if let deletedAt = try tombstoneDate(.pinboard, pinboard.id), deletedAt >= pinboard.updatedAt {
            return false
        }
        try writePinboard(pinboard)
        try db.run("DELETE FROM tombstones WHERE entity = ? AND id = ?", [SyncTombstone.Entity.pinboard.rawValue, pinboard.id])
        return true
    }

    /// Applies an item record when it wins; returns the blob digests the replaced copy referenced (nil: no change).
    private func applyItem(_ item: ClipItem) throws -> Set<String>? {
        var replaced = Set<String>()
        var indexed = (body: "", ocr: "")
        if let local = try loadItem(item.id) {
            guard item.updatedAt > local.updatedAt else { return nil }
            replaced = Set(local.blobRefs.map(\.digest))
            let current = try indexedText(of: item.id)
            indexed.body = local.text == item.text && local.checksum == item.checksum
                ? current.body : Self.fullText(of: item, blobs: blobStore)
            indexed.ocr = local.checksum == item.checksum ? current.ocr : ""
        } else {
            if let deletedAt = try tombstoneDate(.item, item.id), deletedAt >= item.updatedAt { return nil }
            if let copiedAt = item.copiedAt, let cutoff = HistoryRetention.cutoff(days: retentionDays(), now: Date()),
               copiedAt < cutoff, try !item.pins.contains(where: { try pinboardExists($0.pinboardID) }) {
                return nil
            }
            indexed.body = Self.fullText(of: item, blobs: blobStore)
        }
        try write(item, body: indexed.body, ocr: indexed.ocr)
        try db.run("DELETE FROM tombstones WHERE entity = ? AND id = ?", [SyncTombstone.Entity.item.rawValue, item.id])
        return replaced
    }

    /// Applies a deletion when it is newer than the local copy; returns the blob digests to collect (nil: no change).
    private func applyTombstone(_ tombstone: SyncTombstone) throws -> Set<String>? {
        switch tombstone.entity {
        case .item:
            guard let found = try loadItemWithRowID(tombstone.id) else {
                try recordTombstone(.item, tombstone.id, at: tombstone.deletedAt)
                return nil
            }
            guard found.1.updatedAt < tombstone.deletedAt else { return nil }
            return try removeItem(rid: found.0, id: tombstone.id, at: tombstone.deletedAt, trace: .tombstone)
        case .pinboard:
            guard let local = try loadPinboard(tombstone.id) else {
                try recordTombstone(.pinboard, tombstone.id, at: tombstone.deletedAt)
                return nil
            }
            guard local.updatedAt < tombstone.deletedAt else { return nil }
            try db.run("DELETE FROM pinboards WHERE id = ?", [tombstone.id])
            try recordTombstone(.pinboard, tombstone.id, at: tombstone.deletedAt)
            // Pinned-only items left without a pin can't show anywhere; the other Mac deleted them too.
            var digests = Set<String>()
            let orphans = try db.query("""
                SELECT rid, id FROM items WHERE copied_at IS NULL AND NOT EXISTS (SELECT 1 FROM pins WHERE pins.item = items.rid)
                """) { ($0.int64(0), $0.uuid(1)) }
            for (rid, id) in orphans {
                guard let id else { continue }
                digests.formUnion(try removeItem(rid: rid, id: id, at: tombstone.deletedAt, trace: .tombstone))
            }
            return digests
        }
    }
}
