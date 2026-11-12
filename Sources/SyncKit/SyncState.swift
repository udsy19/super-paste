import Foundation
import SuperPasteCore

/// What this Mac remembers about the sync folder between passes (`SuperPastePaths.sync/state.json`). It belongs to
/// one folder identity; a different `key.check` identity starts it over.
struct SyncState: Codable, Equatable {
    var folderPath: String?
    var folderID: String?
    /// The newest journal sequence already written to this Mac's log.
    var shippedSequence: Int64 = 0
    /// The number of the last segment this Mac wrote (0 = none).
    var lastSegment = 0
    /// Per other device: every segment up to this number has been read.
    var cursors: [String: Int] = [:]
    /// Records from other Macs whose blobs haven't arrived yet, by "<entity>/<id>"; retried every pass.
    var deferred: [String: SyncRecord] = [:]
    var lastBlobSweep: Date?

    static func load(from file: URL) -> SyncState {
        guard let data = try? Data(contentsOf: file), let state = try? JSONDecoder().decode(SyncState.self, from: data)
        else { return SyncState() }
        return state
    }

    func save(to file: URL) {
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(self).write(to: file, options: .atomic)
        } catch {
            Log.sync.error("Couldn't save the sync state: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension SyncRecord {
    /// "item/<id>" or "pinboard/<id>": the record's identity across states and tombstones.
    var syncKey: String {
        switch self {
        case .item(let item): "item/\(item.id.uuidString)"
        case .pinboard(let pinboard): "pinboard/\(pinboard.id.uuidString)"
        case .tombstone(let tombstone): "\(tombstone.entity.rawValue)/\(tombstone.id.uuidString)"
        }
    }

    /// Blobs that must be in the store before the record is applied.
    var blobRefs: [BlobRef] {
        if case .item(let item) = self { return item.blobRefs }
        return []
    }
}

/// Where the enabled flag and the folder are remembered: `Defaults` in the app, memory in tests (two simulated Macs
/// in one process).
@MainActor
public protocol SyncSettingsStoring: AnyObject {
    var isEnabled: Bool { get set }
    /// POSIX path; "" when none was chosen.
    var folderPath: String { get set }
    var lastSync: Date? { get set }
}

@MainActor
public final class DefaultsSyncSettings: SyncSettingsStoring {
    public init() {}

    public var isEnabled: Bool {
        get { Defaults[.isSyncEnabled] }
        set { Defaults[.isSyncEnabled] = newValue }
    }

    public var folderPath: String {
        get {
            #if APP_STORE
            SecurityScopedFolder.resume(bookmark: Defaults[.syncFolderBookmark], path: Defaults[.syncFolderPath])
            #endif
            return Defaults[.syncFolderPath]
        }
        set {
            #if APP_STORE
            // `FolderSync.enable` has already checked that a bookmark can be made (and reported it if not).
            Defaults[.syncFolderBookmark] = (try? SecurityScopedFolder.bookmark(path: newValue)) ?? Data()
            #endif
            Defaults[.syncFolderPath] = newValue
        }
    }

    public var lastSync: Date? {
        get { Defaults[.lastSyncDate] > 0 ? Date(timeIntervalSince1970: Defaults[.lastSyncDate]) : nil }
        set { Defaults[.lastSyncDate] = newValue?.timeIntervalSince1970 ?? 0 }
    }
}

#if APP_STORE
/// The sync folder in the App Sandbox: the open panel grants access for this launch only, so a security-scoped
/// bookmark is kept next to the path and resolved (and access started, for the life of the process) on first use.
/// A bookmark that can't be made fails `FolderSync.enable`; one that no longer resolves sets `problem`, which the
/// Sync pane shows as the status; a stale one (the folder moved or was renamed) is made again, path included.
@MainActor
enum SecurityScopedFolder {
    /// The path whose access is currently held, and the path last resolved (so it is resolved once per path).
    private static var accessing: URL?
    private static var resolvedPath: String?
    /// Why the chosen folder can't be reached this launch; nil when it can (or none is chosen).
    private(set) static var problem: String?

    static let chooseAgain = "Super Paste can no longer open the sync folder. Choose it again in Settings › Sync."

    static func bookmark(path: String) throws -> Data {
        guard !path.isEmpty else { return Data() }
        return try URL(fileURLWithPath: path, isDirectory: true)
            .bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resume(bookmark: Data, path: String) {
        guard !path.isEmpty, resolvedPath != path else { return }
        resolvedPath = path
        problem = nil
        var stale = false
        guard !bookmark.isEmpty,
              let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            Log.sync.error("The sync folder's bookmark is missing or no longer resolves")
            problem = chooseAgain
            return
        }
        accessing?.stopAccessingSecurityScopedResource()
        accessing = url.startAccessingSecurityScopedResource() ? url : nil
        guard accessing != nil else {
            Log.sync.error("The sandbox refused access to the sync folder")
            problem = chooseAgain
            return
        }
        guard stale else { return }
        // The folder moved or was renamed: remember where it is now, with a fresh bookmark.
        do {
            Defaults[.syncFolderBookmark] = try Self.bookmark(path: url.path)
            if url.path != path {
                resolvedPath = url.path
                Defaults[.syncFolderPath] = url.path
                Log.sync.notice("The sync folder moved; following it")
            }
        } catch {
            Log.sync.error("Couldn't refresh the sync folder's bookmark: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
