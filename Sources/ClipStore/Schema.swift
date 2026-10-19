import Foundation
import SQLite3
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

    /// Opening the store (behaviour.md §1.9) in one of three ways:
    ///
    /// - The usual: the file opens and migrates. Nothing to report.
    /// - The file is damaged (not a database, corrupt pages, a foreign schema): it is moved, with its -wal/-shm files
    ///   and the blob folder, to `backup/<timestamp>-<id>/`, a fresh store starts, and whatever can still be read
    ///   from the damaged file is copied into it (`Salvage`). Nothing is ever deleted.
    /// - The file can't be opened for a reason that has nothing to do with its contents (locked by another process,
    ///   no permission, the disk is full or failing): it is left exactly as it is and the store runs in memory for
    ///   this launch, so the app keeps working without ever writing over a file it couldn't read.
    ///
    /// Both unusual outcomes come back as a `StoreRecovery` for the app to tell the user about in plain words.
    static func open(database url: URL, blobs: URL, backup: URL) -> (Database, StoreRecovery?) {
        let failure: Database.Failure
        do {
            return (try openWithRetry(url), nil)
        } catch let error as Database.Failure {
            failure = error
        } catch {
            failure = Database.Failure(code: SQLITE_ERROR, message: String(describing: error))
        }
        guard failure.isDamage || !failure.isTransient else {
            Log.store.error("The database can't be opened right now (\(failure.description, privacy: .public)); leaving it alone and using memory for this launch")
            return (memory(), StoreRecovery(outcome: .inMemory(reason: failure.message)))
        }
        Log.store.error("The database is damaged (\(failure.description, privacy: .public)); moving it aside")
        guard let moved = moveAside(database: url, blobs: blobs, backup: backup) else {
            // The damaged file can't even be moved: never start a fresh file over it.
            return (memory(), StoreRecovery(outcome: .inMemory(reason: "the damaged history file couldn't be moved aside")))
        }
        do {
            let db = try openWithRetry(url)
            let salvaged = Salvage.copy(from: moved.database, blobsFrom: moved.blobs, into: db, blobs: blobs)
            return (db, StoreRecovery(outcome: .startedOver(backup: moved.folder, salvagedItems: salvaged.items,
                                                            salvagedPinboards: salvaged.pinboards)))
        } catch {
            Log.store.fault("A new database can't be created (\(String(describing: error), privacy: .public)); using memory")
            return (memory(), StoreRecovery(outcome: .inMemory(reason: String(describing: error))))
        }
    }

    /// A busy or locked file (another process writing it) gets a few more tries before it counts as unopenable.
    private static func openWithRetry(_ url: URL) throws -> Database {
        var attempt = 0
        while true {
            do {
                return try openAndMigrate(url)
            } catch let error as Database.Failure where error.isBusy && attempt < 4 {
                attempt += 1
                Thread.sleep(forTimeInterval: 0.4)
            }
        }
    }

    /// A private in-memory database (which can't fail: no file, no permissions, no disk).
    private static func memory() -> Database {
        do { return try openAndMigrate(nil) } catch { preconditionFailure("in-memory SQLite failed: \(error)") }
    }

    private static func openAndMigrate(_ url: URL?) throws -> Database {
        let db = try Database(url: url)
        // WAL for readers alongside the writer; FULL so every committed write is on disk before the call returns
        // (a power cut loses nothing that was confirmed).
        try db.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = FULL; PRAGMA foreign_keys = ON;")
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
        // A cheap read of every table catches files that open but aren't (or are no longer) our database; the page
        // check catches damaged pages now, at launch, where the file can be moved aside and salvaged, rather than
        // on a write weeks later.
        _ = try db.first("SELECT (SELECT count(*) FROM items) + (SELECT count(*) FROM pinboards)") { $0.int(0) }
        let verdict = try db.query("PRAGMA quick_check") { $0.string(0) }
        guard verdict == ["ok"] else {
            throw Database.Failure(code: SQLITE_CORRUPT, message: verdict.prefix(3).joined(separator: "; "))
        }
        return db
    }

    /// Moves the database (with -wal/-shm) and the blob folder into a new backup folder; nil when any of them can't be
    /// moved (nothing is ever deleted).
    private static func moveAside(database url: URL, blobs: URL, backup: URL) -> (folder: URL, database: URL, blobs: URL)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let folder = backup.appendingPathComponent(formatter.string(from: Date()) + "-" + UUID().uuidString.prefix(8),
                                                   isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let files = ["", "-wal", "-shm"].map { URL(fileURLWithPath: url.path + $0) } + [blobs]
            for file in files where fm.fileExists(atPath: file.path) {
                try fm.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
            }
            try fm.createDirectory(at: blobs, withIntermediateDirectories: true)
        } catch {
            Log.store.fault("Couldn't move the damaged store aside: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        Log.store.notice("Moved the damaged store to \(folder.path, privacy: .public) and started over")
        return (folder, folder.appendingPathComponent(url.lastPathComponent), folder.appendingPathComponent(blobs.lastPathComponent))
    }
}

/// What opening the store did beyond the ordinary (behaviour.md §1.9), for the app to show once after launch.
public struct StoreRecovery: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// The file was damaged: it was moved to `backup` and a fresh store started, with this much copied back from it.
        case startedOver(backup: URL, salvagedItems: Int, salvagedPinboards: Int)
        /// The file couldn't be opened for a reason unrelated to its contents; it was left untouched, and this launch
        /// keeps its captures in memory only.
        case inMemory(reason: String)
    }

    public var outcome: Outcome

    public init(outcome: Outcome) { self.outcome = outcome }

    public var title: String {
        switch outcome {
        case .startedOver: "Your clipboard history couldn't be read, so Super Paste started a fresh one."
        case .inMemory: "Super Paste can't open your clipboard history right now."
        }
    }

    /// Plain words: what happened, where the old file is, and what it means for this session.
    public var message: String {
        switch outcome {
        case .startedOver(let backup, let items, let pinboards):
            let kept = "The old history file was kept, untouched, in \(backup.path)."
            if items == 0 && pinboards == 0 {
                return "\(kept) Nothing could be read back from it; if it matters, the file can be examined with another tool."
            }
            func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
            return "\(count(items, "item")) and \(count(pinboards, "pinboard")) were recovered from it. \(kept)"
        case .inMemory(let reason):
            return "Reason: \(reason). The history file was left exactly as it is. Until Super Paste is relaunched, what you copy is kept only for this session and not saved."
        }
    }
}
