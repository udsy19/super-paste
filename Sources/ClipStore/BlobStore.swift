import Foundation
import SuperPasteCore

/// Content-addressed payload bytes. Every blob has a row in `blobs` keyed by its SHA-256 digest; small blobs live
/// inline in that row, larger ones as `<folder>/<first two hex digits>/<digest>` files. Equal bytes are stored once.
final class BlobStore {
    /// Blobs up to this size stay inline in SQLite (faster than a file each); larger ones become files, which Quick
    /// Look and drag-out can use directly.
    static let inlineLimit = 64 * 1024

    private let db: Database
    private let folder: URL

    init(db: Database, folder: URL) {
        self.db = db
        self.folder = folder
    }

    /// Stores `data` unless a blob with its digest is already there (rewriting a file that went missing).
    @discardableResult func save(_ data: Data) throws -> BlobRef {
        let ref = BlobRef(of: data)
        let stored = try db.first("SELECT data IS NULL FROM blobs WHERE digest = ?", [ref.digest]) { $0.int(0) == 1 }
        switch stored {
        case false?:
            return ref
        case true?:
            let url = fileURL(digest: ref.digest)
            if !FileManager.default.fileExists(atPath: url.path) { try writeFile(data, to: url) }
            return ref
        case nil:
            if data.count <= Self.inlineLimit {
                try db.run("INSERT INTO blobs (digest, size, data, created_at) VALUES (?, ?, ?, ?)",
                           [ref.digest, data.count, data, Date()])
            } else {
                try writeFile(data, to: fileURL(digest: ref.digest))
                try db.run("INSERT INTO blobs (digest, size, data, created_at) VALUES (?, ?, NULL, ?)",
                           [ref.digest, data.count, Date()])
            }
            return ref
        }
    }

    func data(for ref: BlobRef) -> Data? {
        do {
            guard let row = try db.first("SELECT data IS NULL, data FROM blobs WHERE digest = ?", [ref.digest], {
                ($0.int(0) == 1, $0.data(1))
            }) else { return nil }
            return row.0 ? try? Data(contentsOf: fileURL(digest: ref.digest), options: .mappedIfSafe) : row.1
        } catch {
            Log.store.error("Reading blob \(ref.digest, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The blob's file when it is kept as one (and present).
    func fileURL(for ref: BlobRef) -> URL? {
        guard (try? db.first("SELECT data IS NULL FROM blobs WHERE digest = ?", [ref.digest], { $0.int(0) == 1 })) == true
        else { return nil }
        let url = fileURL(digest: ref.digest)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Whether the blob's bytes are here (row and, for a file blob, the file).
    func has(_ digest: String) -> Bool {
        guard let isFile = try? db.first("SELECT data IS NULL FROM blobs WHERE digest = ?", [digest], { $0.int(0) == 1 })
        else { return false }
        return !isFile || FileManager.default.fileExists(atPath: fileURL(digest: digest).path)
    }

    /// Deletes those of `digests` that nothing references any more, except `protected` ones (the undo batch).
    func collect(_ digests: Set<String>, protecting protected: Set<String>) throws {
        for digest in digests.subtracting(protected) {
            let referenced = try db.first(Self.isReferenced, [digest]) { $0.int(0) == 1 } ?? true
            if !referenced { try remove(digest) }
        }
    }

    /// The launch sweep: removes unreferenced blobs saved before `cutoff` (younger ones may be waiting for the item
    /// that will use them, e.g. a link preview or a sync download) and files with no row at all that are older than
    /// `cutoff` (a file written moments before a crash may still get its row from the write that was rolled back
    /// and runs again).
    func sweep(savedBefore cutoff: Date) throws {
        let orphans = try db.query("""
            SELECT digest FROM blobs WHERE created_at < ? AND digest NOT IN (
                SELECT blob FROM representations
                UNION SELECT thumbnail FROM items WHERE thumbnail IS NOT NULL
                UNION SELECT link_icon FROM items WHERE link_icon IS NOT NULL
                UNION SELECT link_image FROM items WHERE link_image IS NOT NULL
                UNION SELECT icon FROM apps WHERE icon IS NOT NULL)
            """, [cutoff]) { $0.string(0) }
        for digest in orphans { try remove(digest) }

        let files = Set(try db.query("SELECT digest FROM blobs WHERE data IS NULL") { $0.string(0) })
        let fm = FileManager.default
        guard let shards = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for shard in shards {
            for file in (try? fm.contentsOfDirectory(at: shard, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where !files.contains(file.lastPathComponent) {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified >= cutoff { continue }
                try? fm.removeItem(at: file)
            }
        }
        if !orphans.isEmpty { Log.store.info("Removed \(orphans.count) unused blobs") }
    }

    // MARK: - Private

    private static let isReferenced = """
        SELECT EXISTS (SELECT 1 FROM representations WHERE blob = ?1)
            OR EXISTS (SELECT 1 FROM items WHERE thumbnail = ?1)
            OR EXISTS (SELECT 1 FROM items WHERE link_icon = ?1)
            OR EXISTS (SELECT 1 FROM items WHERE link_image = ?1)
            OR EXISTS (SELECT 1 FROM apps WHERE icon = ?1)
        """

    private func fileURL(digest: String) -> URL {
        folder.appendingPathComponent(String(digest.prefix(2)), isDirectory: true).appendingPathComponent(digest)
    }

    private func writeFile(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func remove(_ digest: String) throws {
        try db.run("DELETE FROM blobs WHERE digest = ?", [digest])
        try? FileManager.default.removeItem(at: fileURL(digest: digest))
    }
}
