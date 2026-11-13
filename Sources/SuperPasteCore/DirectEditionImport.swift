import Foundation

/// Copies the history of the direct-download edition into this one (the Mac App Store edition, whose files live in
/// its sandbox container). Nothing of the direct edition is moved or changed: the user picks its data folder in an
/// open panel (which is what grants the sandboxed app read access), its database and blobs are COPIED into a staging
/// folder, and the next launch swaps them in before the store opens. Whatever this edition had is kept in
/// `Backup/Before import <date>/`, including its sync state and file bookmarks, which belong to the old history:
/// sync starts over (sends and reads everything) with the imported one. MCP clients are not imported.
///
/// The swap is a sequence of renames that a relaunch finishes if it was interrupted: `.applying` (naming the backup
/// folder) is written first, `.moved-out` once the current history is in the backup, and the staging folder goes
/// last.
public enum DirectEditionImport {
    /// The files that make up a history: the database (with its write-ahead log) and the blobs it references.
    static let items = ["clips.sqlite", "clips.sqlite-wal", "clips.sqlite-shm", "Blobs"]
    /// State tied to this edition's current history; moved to the backup with it and not replaced.
    static let resetItems = ["Sync", "File Access.plist"]
    /// Written last into the staging folder: an import without it was interrupted and is discarded.
    static let completeMarker = ".complete"
    static let applyingMarker = ".applying"
    static let movedOutMarker = ".moved-out"

    public enum ImportError: LocalizedError, Equatable {
        case notAHistoryFolder(String)
        case symbolicLink(String)

        public var errorDescription: String? {
            switch self {
            case .notAHistoryFolder(let name):
                "“\(name)” doesn't contain a Super Paste history (clips.sqlite). Choose the “Super Paste” folder in Library › Application Support."
            case .symbolicLink(let path):
                "“\(path)” is a symbolic link. Super Paste only imports a history whose files are all inside the folder you choose."
            }
        }
    }

    /// Next to the support folder, so a half-copied import can never be mistaken for the live store.
    public static func stagingFolder(base: URL = SuperPastePaths.base) -> URL {
        base.appendingPathComponent(SuperPastePaths.supportFolderName + " Import", isDirectory: true)
    }

    /// Copies the history in `source` (the direct edition's support folder) into the staging folder. Refuses a
    /// history with symbolic links among its files rather than copying links that point outside it.
    public static func stage(from source: URL, base: URL = SuperPastePaths.base) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.appendingPathComponent("clips.sqlite").path) else {
            throw ImportError.notAHistoryFolder(source.lastPathComponent)
        }
        let present = items.filter { isPresent(source.appendingPathComponent($0)) }
        for name in present { try refuseSymbolicLinks(in: source.appendingPathComponent(name)) }
        let staging = stagingFolder(base: base)
        try? fm.removeItem(at: staging)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            for name in present {
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
    /// current history (and its sync state and file bookmarks) to `Backup/Before import <date>/`; finishes an
    /// interrupted swap. Returns whether an import was applied.
    @discardableResult
    public static func applyStaged(base: URL = SuperPastePaths.base, now: Date = Date()) throws -> Bool {
        let fm = FileManager.default
        let staging = stagingFolder(base: base)
        guard fm.fileExists(atPath: staging.path) else { return false }
        guard isStaged(base: base) else { try? fm.removeItem(at: staging); return false }
        let support = SuperPastePaths.ensure(base.appendingPathComponent(SuperPastePaths.supportFolderName, isDirectory: true))
        let applying = staging.appendingPathComponent(applyingMarker)
        let backupName: String
        if let name = try? String(contentsOf: applying, encoding: .utf8), !name.isEmpty {
            backupName = name  // resuming an interrupted swap
        } else {
            let stamp = ISO8601DateFormatter.string(from: now, timeZone: .current, formatOptions: [.withFullDate, .withTime])
            backupName = "Before import \(stamp)"
            try Data(backupName.utf8).write(to: applying, options: .atomic)
        }
        let backup = support.appendingPathComponent("Backup", isDirectory: true).appendingPathComponent(backupName, isDirectory: true)
        let movedOut = staging.appendingPathComponent(movedOutMarker)
        if !fm.fileExists(atPath: movedOut.path) {
            try fm.createDirectory(at: backup, withIntermediateDirectories: true)
            for name in items + resetItems where isPresent(support.appendingPathComponent(name))
                && !isPresent(backup.appendingPathComponent(name)) {
                try fm.moveItem(at: support.appendingPathComponent(name), to: backup.appendingPathComponent(name))
            }
            try Data().write(to: movedOut)
        }
        for name in items where isPresent(staging.appendingPathComponent(name)) {
            try fm.moveItem(at: staging.appendingPathComponent(name), to: support.appendingPathComponent(name))
        }
        try fm.removeItem(at: staging)
        return true
    }

    private static func isPresent(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || isSymbolicLink(url)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func refuseSymbolicLinks(in url: URL) throws {
        let name = url.lastPathComponent
        if isSymbolicLink(url) { throw ImportError.symbolicLink(name) }
        guard let walker = FileManager.default.enumerator(atPath: url.path) else { return }
        while let child = walker.nextObject() as? String {
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeSymbolicLink {
                throw ImportError.symbolicLink(name + "/" + child)
            }
        }
    }
}
