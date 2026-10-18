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
final class DefaultsSyncSettings: SyncSettingsStoring {
    var isEnabled: Bool {
        get { Defaults[.isSyncEnabled] }
        set { Defaults[.isSyncEnabled] = newValue }
    }

    var folderPath: String {
        get { Defaults[.syncFolderPath] }
        set { Defaults[.syncFolderPath] = newValue }
    }

    var lastSync: Date? {
        get { Defaults[.lastSyncDate] > 0 ? Date(timeIntervalSince1970: Defaults[.lastSyncDate]) : nil }
        set { Defaults[.lastSyncDate] = newValue?.timeIntervalSince1970 ?? 0 }
    }
}
