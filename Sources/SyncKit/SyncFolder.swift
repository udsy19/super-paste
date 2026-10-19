import Foundation
import SuperPasteCore

/// One file of a device's change log: records that device wrote locally, in journal order. A snapshot holds the
/// latest state of everything the device ever wrote and supersedes its earlier segments (log compaction).
struct SyncSegment: Codable {
    var format = 1
    var device: String
    var number: Int
    var isSnapshot: Bool
    var createdAt: Date
    /// Who wrote it (name and app version), for diagnostics.
    var writer: Device?
    var records: [SyncRecord]
}

/// What `key.check` holds: proof that a key opens the folder, plus the folder's identity (a new identity after the
/// folder is wiped and set up again tells each Mac to ship everything again).
struct FolderIdentity: Codable {
    var check = "superpaste-sync"
    var format = 1
    var folderID: String
    var createdAt: Date
}

/// The sync folder on disk. Every file in it is sealed with `SyncCrypto`; plain file I/O, so any folder works (iCloud
/// Drive, Dropbox, Syncthing, a NAS share):
///
///     key.check                          FolderIdentity
///     devices/<device id>/<n>.log        SyncSegment, append-only: written once, never changed
///     devices/<device id>/<n>.snap       SyncSegment snapshot; segments below n are deleted after it is written
///     blobs/<xx>/<keyed name>.blob       payload bytes; the name is SyncKey.blobName(forDigest:)
///
/// Each Mac writes only its own `devices/<id>` folder, so no file ever has two writers and cloud services never see
/// a conflict. Blobs are content-addressed: writing an existing one is a no-op.
actor SyncFolder {
    nonisolated let root: URL
    nonisolated let key: SyncKey
    private let fm = FileManager.default
    nonisolated var devicesDir: URL { root.appendingPathComponent("devices", isDirectory: true) }
    nonisolated var blobsDir: URL { root.appendingPathComponent("blobs", isDirectory: true) }
    /// Sanity limits on what a sealed file may weigh before it is read into memory.
    static let maxSegmentBytes = 512 << 20
    static let maxBlobBytes = 2 << 30

    init(root: URL, key: SyncKey) {
        self.root = root
        self.key = key
    }

    // MARK: Key check

    enum KeyCheck: Equatable {
        /// No Super Paste data yet.
        case missing
        /// iCloud Drive hasn't downloaded `key.check` yet.
        case downloading
        case matches(folderID: String)
        case mismatch
    }

    nonisolated static func keyCheckFile(in root: URL) -> URL { root.appendingPathComponent("key.check") }

    nonisolated static func checkKey(root: URL, key: SyncKey?) -> KeyCheck {
        let file = keyCheckFile(in: root)
        guard let data = try? Data(contentsOf: file) else {
            if isPlaceholderPresent(for: file) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: file)
                return .downloading
            }
            return .missing
        }
        guard let key, let plain = try? SyncCrypto.open(data, key: key, context: "key.check"),
              let identity = try? JSONDecoder().decode(FolderIdentity.self, from: plain),
              identity.check == "superpaste-sync" else { return .mismatch }
        return .matches(folderID: identity.folderID)
    }

    /// Writes a new `key.check` (a new folder identity); returns the identity.
    nonisolated static func writeKeyCheck(root: URL, key: SyncKey) throws -> String {
        let identity = FolderIdentity(folderID: UUID().uuidString, createdAt: Date())
        let sealed = try SyncCrypto.seal(JSONEncoder().encode(identity), key: key, context: "key.check")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try sealed.write(to: keyCheckFile(in: root), options: .atomic)
        } catch {
            throw SyncError.folderUnavailable(error.localizedDescription)
        }
        return identity.folderID
    }

    /// iCloud Drive keeps a not-yet-downloaded file as `.<name>.icloud` next to where it will be.
    nonisolated static func isPlaceholderPresent(for file: URL) -> Bool {
        let placeholder = file.deletingLastPathComponent().appendingPathComponent(".\(file.lastPathComponent).icloud")
        return FileManager.default.fileExists(atPath: placeholder.path)
    }

    // MARK: Segments

    struct SegmentListing: Equatable {
        var logs: Set<Int> = []
        var snapshots: Set<Int> = []
        /// Numbers whose file iCloud Drive hasn't downloaded yet.
        var pending: Set<Int> = []
        var highest: Int { (logs.union(snapshots).union(pending)).max() ?? 0 }
    }

    /// Device ids with a folder under `devices/`.
    func deviceIDs() -> [String] {
        let names = (try? fm.contentsOfDirectory(atPath: devicesDir.path)) ?? []
        return names.filter(Self.isValidDeviceID).sorted()
    }

    nonisolated static func isValidDeviceID(_ id: String) -> Bool {
        (1...64).contains(id.count) && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// Segments by number. A placeholder (iCloud Drive hasn't downloaded the file) and an empty file (a cloud service
    /// that creates the file before filling it) both count as pending: reading stops there and tries again later,
    /// rather than reporting a damaged file.
    func listSegments(device: String) -> SegmentListing {
        let dir = devicesDir.appendingPathComponent(device, isDirectory: true)
        var listing = SegmentListing()
        let urls = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for url in urls {
            var file = url.lastPathComponent
            var placeholder = false
            if file.hasPrefix("."), file.hasSuffix(".icloud") {
                file = String(file.dropFirst().dropLast(".icloud".count))
                placeholder = true
            } else if ((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 1) == 0 {
                placeholder = true
            }
            let parts = file.split(separator: ".")
            guard parts.count == 2, let number = Int(parts[0]), number > 0 else { continue }
            if placeholder {
                listing.pending.insert(number)
                try? fm.startDownloadingUbiquitousItem(at: dir.appendingPathComponent(file))
            } else if parts[1] == "log" {
                listing.logs.insert(number)
            } else if parts[1] == "snap" {
                listing.snapshots.insert(number)
            }
        }
        return listing
    }

    nonisolated static func segmentName(_ number: Int, snapshot: Bool) -> String {
        String(format: "%08d", number) + (snapshot ? ".snap" : ".log")
    }

    private nonisolated func segmentContext(device: String, name: String) -> String { "devices/\(device)/\(name)" }

    func writeSegment(_ segment: SyncSegment) throws {
        let dir = devicesDir.appendingPathComponent(segment.device, isDirectory: true)
        let name = Self.segmentName(segment.number, snapshot: segment.isSnapshot)
        let plain = try JSONEncoder().encode(segment)
        let sealed = try SyncCrypto.seal(plain, key: key, context: segmentContext(device: segment.device, name: name),
                                         compress: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let file = dir.appendingPathComponent(name)
            // Segments are immutable; never replace one another Mac (or an earlier run) already wrote.
            guard !fm.fileExists(atPath: file.path) else {
                throw SyncError.folderUnavailable("segment \(name) already exists")
            }
            try sealed.write(to: file, options: .atomic)
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.folderUnavailable(error.localizedDescription)
        }
    }

    func readSegment(device: String, number: Int, snapshot: Bool) throws -> SyncSegment {
        let name = Self.segmentName(number, snapshot: snapshot)
        let file = devicesDir.appendingPathComponent(device, isDirectory: true).appendingPathComponent(name)
        let context = segmentContext(device: device, name: name)
        let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size <= Self.maxSegmentBytes, let data = try? Data(contentsOf: file) else {
            throw SyncError.unreadableFile(context)
        }
        let plain = try SyncCrypto.open(data, key: key, context: context)
        guard let segment = try? JSONDecoder().decode(SyncSegment.self, from: plain), segment.device == device,
              segment.number == number, segment.isSnapshot == snapshot else { throw SyncError.unreadableFile(context) }
        return segment
    }

    /// Deletes this device's segments numbered below `number` (after a snapshot at `number` was written).
    func deleteSegments(device: String, below number: Int) {
        let dir = devicesDir.appendingPathComponent(device, isDirectory: true)
        let listing = listSegments(device: device)
        for n in listing.logs where n < number {
            try? fm.removeItem(at: dir.appendingPathComponent(Self.segmentName(n, snapshot: false)))
        }
        for n in listing.snapshots where n < number {
            try? fm.removeItem(at: dir.appendingPathComponent(Self.segmentName(n, snapshot: true)))
        }
    }

    // MARK: Blobs

    private func blobFile(_ name: String) -> URL {
        blobsDir.appendingPathComponent(String(name.prefix(2)), isDirectory: true).appendingPathComponent(name + ".blob")
    }

    /// Whether the blob is in the folder (downloaded or not). A blob that is there gets its modification date
    /// renewed, so a sweep on another Mac doesn't delete it while a new record starts referencing it again.
    func hasBlob(digest: String) -> Bool {
        let file = blobFile(key.blobName(forDigest: digest))
        if fm.fileExists(atPath: file.path) {
            try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return true
        }
        return Self.isPlaceholderPresent(for: file)
    }

    func writeBlob(_ data: Data, digest: String) throws {
        let name = key.blobName(forDigest: digest)
        let file = blobFile(name)
        guard !fm.fileExists(atPath: file.path) else { return }
        let sealed = try SyncCrypto.seal(data, key: key, context: "blobs/\(name)")
        do {
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try sealed.write(to: file, options: .atomic)
        } catch {
            throw SyncError.folderUnavailable(error.localizedDescription)
        }
    }

    enum BlobRead {
        case data(Data)
        /// Not in the folder yet (or still downloading).
        case missing
        /// There, but it doesn't decrypt or its bytes don't hash to the digest.
        case corrupt
    }

    func readBlob(digest: String) -> BlobRead {
        let name = key.blobName(forDigest: digest)
        let file = blobFile(name)
        guard fm.fileExists(atPath: file.path) else {
            if Self.isPlaceholderPresent(for: file) { try? fm.startDownloadingUbiquitousItem(at: file) }
            return .missing
        }
        let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        // An empty file is still being written by whatever syncs the folder: not here yet, rather than damaged.
        guard size > 0, size <= Self.maxBlobBytes, let sealed = try? Data(contentsOf: file) else { return .missing }
        guard let plain = try? SyncCrypto.open(sealed, key: key, context: "blobs/\(name)"),
              ClipChecksum.hex(of: plain) == digest else { return .corrupt }
        return .data(plain)
    }

    /// Every blob digest some record in some device's log references; nil when a segment can't be read or is still
    /// downloading (a sweep then waits rather than guess).
    func referencedDigests() -> Set<String>? {
        var digests = Set<String>()
        for device in deviceIDs() {
            let listing = listSegments(device: device)
            guard listing.pending.isEmpty else { return nil }
            let segments = listing.logs.map { ($0, false) } + listing.snapshots.map { ($0, true) }
            for (number, snapshot) in segments {
                guard let segment = try? readSegment(device: device, number: number, snapshot: snapshot) else { return nil }
                for record in segment.records { digests.formUnion(record.blobRefs.map(\.digest)) }
            }
        }
        return digests
    }

    /// Deletes blobs whose digest isn't in `live` and that nobody wrote or reused for `grace` seconds. Returns the
    /// number deleted.
    func sweepBlobs(live: Set<String>, grace: TimeInterval, now: Date) -> Int {
        let liveNames = Set(live.map { key.blobName(forDigest: $0) })
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        guard let walker = fm.enumerator(at: blobsDir, includingPropertiesForKeys: keys) else { return 0 }
        var deleted = 0
        for case let file as URL in walker where file.pathExtension == "blob" {
            let name = file.deletingPathExtension().lastPathComponent
            guard !liveNames.contains(name),
                  let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let modified = values.contentModificationDate, now.timeIntervalSince(modified) > grace else { continue }
            if (try? fm.removeItem(at: file)) != nil { deleted += 1 }
        }
        return deleted
    }
}

// MARK: - Reading order

/// Which of a device's segments to read next, given that everything up to `through` has been read: the newest
/// snapshot above `through` when there is one (it supersedes everything before it), then consecutive segments.
/// Reading stops at the first number that isn't there or is still downloading, so nothing is skipped when files
/// arrive out of order.
public enum SegmentOrder {
    public struct Step: Equatable, Sendable {
        public let number: Int
        public let isSnapshot: Bool

        public init(_ number: Int, snapshot: Bool = false) {
            self.number = number; isSnapshot = snapshot
        }
    }

    public static func plan(through: Int, logs: Set<Int>, snapshots: Set<Int>, pending: Set<Int>) -> [Step] {
        var plan: [Step] = []
        var next = through + 1
        let readySnapshots = snapshots.subtracting(pending)
        if let snapshot = readySnapshots.filter({ $0 > through }).max() {
            plan.append(Step(snapshot, snapshot: true))
            next = snapshot + 1
        }
        while !pending.contains(next) {
            if logs.contains(next) {
                plan.append(Step(next))
            } else if readySnapshots.contains(next) {
                plan.append(Step(next, snapshot: true))
            } else {
                break
            }
            next += 1
        }
        return plan
    }
}
