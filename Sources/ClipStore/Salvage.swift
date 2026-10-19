import Foundation
import SuperPasteCore

/// Copies what can still be read out of a damaged database into a fresh one (behaviour.md §1.9). Best effort, table
/// by table and in chunks, so a few bad pages cost a few rows rather than everything: a chunk that fails to read is
/// skipped and the next one tried. The journal isn't copied (sync notices the fresh start and ships a snapshot), and
/// the search index is taken whole when it reads, else rebuilt from the items' preview text.
enum Salvage {
    static let chunk = 200
    /// Consecutive unreadable chunks before a table is given up on.
    static let patience = 50

    struct Result: Equatable {
        var items = 0
        var pinboards = 0
    }

    static func copy(from damaged: URL, blobsFrom oldBlobs: URL, into db: Database, blobs: URL) -> Result {
        var result = Result()
        guard FileManager.default.fileExists(atPath: damaged.path) else { return result }
        do {
            try db.run("ATTACH DATABASE ? AS old", [damaged.path])
        } catch {
            Log.store.error("The damaged database can't be attached for salvage: \(String(describing: error), privacy: .public)")
            return result
        }
        defer { try? db.execute("DETACH DATABASE old") }
        // Rows are copied without their foreign keys enforced (a parent row may be among the unreadable ones), then
        // the orphans are cut away.
        try? db.execute("PRAGMA foreign_keys = OFF")
        defer { try? db.execute("PRAGMA foreign_keys = ON") }

        whole("apps", columns: "bundle_id, name, color_hex, icon, icon_size", db)
        whole("devices", columns: "id, name, family, app_version", db)
        whole("pinboards", columns: "id, name, color, position, shortcut, created_at, updated_at", db)
        chunked("items", key: "rid", columns: "rid, " + SQLiteStore.itemColumnNames, db)
        chunked("representations", key: "item", columns: "item, entry, position, type, blob, size", db)
        whole("pins", columns: "pinboard, item, position", db)
        chunked("blobs", key: "rowid", columns: "rowid, digest, size, data, created_at", db)
        whole("tombstones", columns: "entity, id, deleted_at", db)
        index(db)

        try? db.transaction {
            try db.run("UPDATE items SET app_id = NULL WHERE app_id IS NOT NULL AND app_id NOT IN (SELECT bundle_id FROM apps)")
            try db.run("UPDATE items SET device_id = NULL WHERE device_id IS NOT NULL AND device_id NOT IN (SELECT id FROM devices)")
            try db.run("DELETE FROM representations WHERE item NOT IN (SELECT rid FROM items)")
            try db.run("DELETE FROM pins WHERE item NOT IN (SELECT rid FROM items) OR pinboard NOT IN (SELECT id FROM pinboards)")
            // An item needs a place: the history or a pinboard.
            try db.run("DELETE FROM items WHERE copied_at IS NULL AND rid NOT IN (SELECT item FROM pins)")
            try db.run("DELETE FROM items_fts WHERE rowid NOT IN (SELECT rid FROM items)")
            // Everything salvaged is journaled: sync sees a store that started over and ships it whole as a
            // snapshot, instead of an empty one that would replace this Mac's log in the shared folder.
            try db.run("INSERT OR REPLACE INTO journal (entity, id) SELECT 'pinboard', id FROM pinboards ORDER BY position")
            try db.run("INSERT OR REPLACE INTO journal (entity, id) SELECT 'item', id FROM items ORDER BY rid")
            try db.run("INSERT OR REPLACE INTO journal (entity, id) SELECT entity, id FROM tombstones")
        }
        result.items = (try? db.first("SELECT count(*) FROM items") { $0.int(0) }) ?? 0
        result.pinboards = (try? db.first("SELECT count(*) FROM pinboards") { $0.int(0) }) ?? 0
        moveBlobFiles(from: oldBlobs, to: blobs, db)
        Log.store.notice("Salvaged \(result.items) items and \(result.pinboards) pinboards from the damaged database")
        return result
    }

    /// One statement for a small table.
    private static func whole(_ table: String, columns: String, _ db: Database) {
        do {
            try db.transaction { try db.run("INSERT OR IGNORE INTO main.\(table) (\(columns)) SELECT \(columns) FROM old.\(table)") }
        } catch {
            Log.store.error("Couldn't salvage \(table, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Ranges of `chunk` key values at a time (a range keeps an item's rows together); an unreadable range is skipped.
    /// When even the table's highest key can't be read, copying stops after a long run of empty ranges.
    private static func chunked(_ table: String, key: String, columns: String, _ db: Database) {
        let highest = try? db.first("SELECT max(\(key)) FROM old.\(table)") { $0.isNull(0) ? nil : $0.int64(0) } ?? nil
        guard highest != nil || db.canRead("old.\(table)") else { return }
        var cursor: Int64 = 0
        var failures = 0, empties = 0
        while cursor < (highest ?? Int64.max), failures < patience, empties < patience * 10 {
            do {
                let copied: Int = try db.transaction {
                    try db.run("""
                        INSERT OR IGNORE INTO main.\(table) (\(columns))
                        SELECT \(columns) FROM old.\(table) WHERE \(key) > ? AND \(key) <= ?
                        """, [cursor, cursor + Int64(chunk)])
                    return db.changes
                }
                failures = 0
                empties = copied == 0 ? empties + 1 : 0
            } catch {
                failures += 1
                Log.store.error("Skipped unreadable rows of \(table, privacy: .public) with \(key, privacy: .public) in \(cursor + 1)…\(cursor + Int64(chunk)): \(String(describing: error), privacy: .public)")
            }
            cursor += Int64(chunk)
        }
    }

    /// The search index: the old one whole when it reads, else rebuilt from what the items carry.
    private static func index(_ db: Database) {
        do {
            try db.transaction {
                try db.run("""
                    INSERT INTO main.items_fts (rowid, title, body, app, ocr)
                    SELECT rowid, title, body, app, ocr FROM old.items_fts WHERE rowid IN (SELECT rid FROM main.items)
                    """)
            }
            return
        } catch {
            Log.store.error("The search index couldn't be salvaged; rebuilding it from the items")
        }
        try? db.transaction {
            try db.run("DELETE FROM main.items_fts")
            try db.run("""
                INSERT INTO main.items_fts (rowid, title, body, app, ocr)
                SELECT i.rid, coalesce(i.title, ''), i.text, coalesce(a.name, ''), ''
                FROM main.items i LEFT JOIN main.apps a ON a.bundle_id = i.app_id
                """)
        }
    }

    /// Blob files belong with the rows that name them: those of salvaged rows come back from the backup folder, the
    /// rest stay there with the damaged database.
    private static func moveBlobFiles(from oldBlobs: URL, to blobs: URL, _ db: Database) {
        let fm = FileManager.default
        let digests = (try? db.query("SELECT digest FROM blobs WHERE data IS NULL") { $0.string(0) }) ?? []
        for digest in digests {
            let shard = String(digest.prefix(2))
            let source = oldBlobs.appendingPathComponent(shard, isDirectory: true).appendingPathComponent(digest)
            guard fm.fileExists(atPath: source.path) else { continue }
            let folder = blobs.appendingPathComponent(shard, isDirectory: true)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fm.moveItem(at: source, to: folder.appendingPathComponent(digest))
        }
    }
}
