import Foundation

/// Copies the history of the direct-download edition into this one (the Mac App Store edition, whose files live in
/// its sandbox container). Nothing of the direct edition is moved or changed: the user picks its data folder in an
/// open panel (which is what grants the sandboxed app read access), its database and blobs are COPIED into a staging
/// folder, and the next launch swaps them in before the store opens. Whatever this edition had is kept in
/// `Backup/Before import <date>/`. MCP clients and sync state are not imported: each edition connects on its own.
public enum DirectEditionImport {
    /// The files that make up a history: the database (with its write-ahead log) and the blobs it references.
    static let items = ["clips.sqlite", "clips.sqlite-wal", "clips.sqlite-shm", "Blobs"]
    /// Written last into the staging folder: an import without it was interrupted and is discarded.
    static let completeMarker = ".complete"

    public enum ImportError: LocalizedError {
        case notAHistoryFolder(String)

        public var errorDescription: String? {
            switch self {
            case .notAHistoryFolder(let name):
                "“\(name)” doesn't contain a Super Paste history (clips.sqlite). Choose the “Super Paste” folder in Library › Application Support."
            }
        }
    }

    /// Next to the support folder, so a half-copied import can never be mistaken for the live store.
    public static func stagingFolder(base: URL = SuperPastePaths.base) -> URL {
        base.appendingPathComponent(SuperPastePaths.supportFolderName + " Import", isDirectory: true)
    }

    /// Copies the history in `source` (the direct edition's support folder) into the staging folder.
    public static func stage(from source: URL, base: URL = SuperPastePaths.base) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.appendingPathComponent("clips.sqlite").path) else {
            throw ImportError.notAHistoryFolder(source.lastPathComponent)
        }
        let staging = stagingFolder(base: base)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for name in items where fm.fileExists(atPath: source.appendingPathComponent(name).path) {
                try fm.copyItem(at: source.appendingPathComponent(name), to: staging.appendingPathComponent(name))
            }
            try Data().write(to: staging.appendingPathComponent(completeMarker))
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    public static func isStaged(base: URL = SuperPastePaths.base) -> Bool {
        FileManager.default.fileExists(atPath: stagingFolder(base: base).appendingPathComponent(completeMarker).path)
    }

    /// At launch, before the store opens: moves a complete staged import into the support folder, after moving the
    /// current history to `Backup/Before import <date>/`. Returns whether an import was applied.
    @discardableResult
    public static func applyStaged(base: URL = SuperPastePaths.base, now: Date = Date()) throws -> Bool {
        let fm = FileManager.default
        let staging = stagingFolder(base: base)
        guard fm.fileExists(atPath: staging.path) else { return false }
        guard isStaged(base: base) else { try? fm.removeItem(at: staging); return false }
        let support = SuperPastePaths.ensure(base.appendingPathComponent(SuperPastePaths.supportFolderName, isDirectory: true))
        let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate, .withTime])
        let backup = support.appendingPathComponent("Backup", isDirectory: true)
            .appendingPathComponent("Before import \(stamp)", isDirectory: true)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for name in items where fm.fileExists(atPath: support.appendingPathComponent(name).path) {
            try fm.moveItem(at: support.appendingPathComponent(name), to: backup.appendingPathComponent(name))
        }
        for name in items where fm.fileExists(atPath: staging.appendingPathComponent(name).path) {
            try fm.moveItem(at: staging.appendingPathComponent(name), to: support.appendingPathComponent(name))
        }
        try fm.removeItem(at: staging)
        return true
    }
}
