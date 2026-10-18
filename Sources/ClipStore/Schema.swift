import Foundation
import SuperPasteCore

/// The database schema, one migration per `user_version` step. Append new steps; never edit a shipped one.
///
/// - `items`: one row per clipboard item. `rid` is the internal key (FTS rowid, child tables); `id` the public UUID.
///   Dates are seconds since the reference date. Blob refs are a digest column plus a size column.
/// - `representations`: the payload, one row per pasteboard type, `(entry, position)` in pasteboard order.
/// - `apps`, `devices`: source records, unique by bundle id / device id, shared by the items that point at them.
/// - `pinboards`, `pins`: tabs and the item ↔ pinboard places (fractional `position`, ascending).
/// - `blobs`: every stored blob by SHA-256 digest; `data` holds small blobs inline, NULL means
///   `SuperPastePaths.blobs/<2 hex>/<digest>` holds the bytes.
/// - `tombstones`: deletions (local and from other Macs) so stale records can't come back.
/// - `journal`: one row per locally written record, re-sequenced on every write (`SyncStoring.journal`).
/// - `items_fts`: FTS5 over the user title, the full plain text, the source app name and recognised (OCR) text.
enum Schema {
    static let migrations: [String] = [
        """
        CREATE TABLE apps (
            bundle_id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            color_hex TEXT,
            icon TEXT,
            icon_size INTEGER
        ) WITHOUT ROWID;

        CREATE TABLE devices (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            family TEXT NOT NULL,
            app_version TEXT
        ) WITHOUT ROWID;

        CREATE TABLE items (
            rid INTEGER PRIMARY KEY,
            id TEXT NOT NULL UNIQUE,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            copied_at REAL,
            last_used_at REAL,
            kind TEXT NOT NULL,
            title TEXT,
            text TEXT NOT NULL,
            text_length INTEGER NOT NULL,
            app_id TEXT REFERENCES apps(bundle_id),
            device_id TEXT REFERENCES devices(id),
            byte_size INTEGER NOT NULL,
            checksum TEXT NOT NULL,
            image_width INTEGER,
            image_height INTEGER,
            thumbnail TEXT,
            thumbnail_size INTEGER,
            file_paths TEXT,
            link_url TEXT,
            link_title TEXT,
            link_icon TEXT,
            link_icon_size INTEGER,
            link_image TEXT,
            link_image_size INTEGER,
            link_fetched_at REAL
        );
        CREATE INDEX items_checksum ON items(checksum);
        CREATE INDEX items_copied ON items(copied_at);
        CREATE INDEX items_recency ON items(coalesce(copied_at, created_at));
        CREATE INDEX items_app ON items(app_id);
        CREATE INDEX items_device ON items(device_id);
        CREATE INDEX items_thumbnail ON items(thumbnail) WHERE thumbnail IS NOT NULL;
        CREATE INDEX items_link_icon ON items(link_icon) WHERE link_icon IS NOT NULL;
        CREATE INDEX items_link_image ON items(link_image) WHERE link_image IS NOT NULL;

        CREATE TABLE representations (
            item INTEGER NOT NULL REFERENCES items(rid) ON DELETE CASCADE,
            entry INTEGER NOT NULL,
            position INTEGER NOT NULL,
            type TEXT NOT NULL,
            blob TEXT NOT NULL,
            size INTEGER NOT NULL,
            PRIMARY KEY (item, entry, position)
        ) WITHOUT ROWID;
        CREATE INDEX representations_blob ON representations(blob);

        CREATE TABLE pinboards (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            color TEXT NOT NULL,
            position INTEGER NOT NULL,
            shortcut TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        ) WITHOUT ROWID;

        CREATE TABLE pins (
            pinboard TEXT NOT NULL REFERENCES pinboards(id) ON DELETE CASCADE,
            item INTEGER NOT NULL REFERENCES items(rid) ON DELETE CASCADE,
            position REAL NOT NULL,
            PRIMARY KEY (pinboard, item)
        ) WITHOUT ROWID;
        CREATE INDEX pins_item ON pins(item);

        CREATE TABLE blobs (
            digest TEXT NOT NULL UNIQUE,
            size INTEGER NOT NULL,
            data BLOB,
            created_at REAL NOT NULL
        );

        CREATE TABLE tombstones (
            entity TEXT NOT NULL,
            id TEXT NOT NULL,
            deleted_at REAL NOT NULL,
            PRIMARY KEY (entity, id)
        ) WITHOUT ROWID;

        CREATE TABLE journal (
            sequence INTEGER PRIMARY KEY AUTOINCREMENT,
            entity TEXT NOT NULL,
            id TEXT NOT NULL,
            UNIQUE (entity, id)
        );

        CREATE VIRTUAL TABLE items_fts USING fts5(title, body, app, ocr, tokenize = 'unicode61 remove_diacritics 2');
        """,
    ]

    static var currentVersion: Int { migrations.count }

    /// Opens the database at `url` and brings its schema up to date. A file that can't be opened or migrated is
    /// treated as damaged (behaviour.md §1.9): it moves, with its -wal/-shm files and the blob folder, to
    /// `backup/<timestamp>/` and a fresh store starts. If even that fails the store runs in memory for this launch.
    static func open(database url: URL, blobs: URL, backup: URL) -> Database {
        do {
            return try openAndMigrate(url)
        } catch {
            Log.store.error("The database can't be opened (\(String(describing: error), privacy: .public)); moving it aside")
        }
        moveAside(database: url, blobs: blobs, backup: backup)
        do {
            return try openAndMigrate(url)
        } catch {
            Log.store.fault("A new database can't be created (\(String(describing: error), privacy: .public)); using memory")
            return try! openAndMigrate(nil)
        }
    }

    private static func openAndMigrate(_ url: URL?) throws -> Database {
        let db = try Database(url: url)
        try db.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;")
        let version = try db.first("PRAGMA user_version") { $0.int(0) } ?? 0
        if version > currentVersion {
            Log.store.error("The database is from a newer version (\(version)); opening it as version \(currentVersion)")
        }
        for step in version..<max(version, currentVersion) {
            try db.transaction {
                try db.execute(migrations[step])
                try db.execute("PRAGMA user_version = \(step + 1)")
            }
        }
        // A cheap read of every table catches files that open but aren't (or are no longer) our database.
        _ = try db.first("SELECT (SELECT count(*) FROM items) + (SELECT count(*) FROM pinboards)") { $0.int(0) }
        return db
    }

    private static func moveAside(database url: URL, blobs: URL, backup: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = backup.appendingPathComponent(formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(8),
                                                   isDirectory: true)
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = ["", "-wal", "-shm"].map { URL(fileURLWithPath: url.path + $0) } + [blobs]
        for file in files where fm.fileExists(atPath: file.path) {
            do {
                try fm.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            } catch {
                Log.store.error("Couldn't move \(file.lastPathComponent, privacy: .public) aside: \(error.localizedDescription, privacy: .public)")
                try? fm.removeItem(at: file)
            }
        }
        try? fm.createDirectory(at: blobs, withIntermediateDirectories: true)
        Log.store.notice("Moved the damaged store to \(folder.path, privacy: .public) and started over")
    }
}
