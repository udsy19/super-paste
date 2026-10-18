import Foundation
import Combine
import SuperPasteCore

/// End-to-end-encrypted sync through a folder (behaviour.md §17 replacement). Off by default; while off it never
/// reads or writes the folder.
///
/// A pass: (1) local journal entries go into a new segment of this Mac's append-only log, with the blobs they
/// reference; (2) other Macs' new segments are read in order and applied through `SyncStoring.apply`, which keeps
/// the record with the newer `updatedAt` (tombstones delete), so every Mac converges whatever order files arrive in;
/// (3) records whose blobs haven't arrived wait and are retried; (4) once a day, blobs no record references any more
/// are swept. Passes run after local edits (debounced), when the folder changes (file presenter) and every minute.
///
/// Only what the store journals travels: explicit deletes and Erase History become tombstones, retention pruning
/// stays on the Mac that pruned (`ItemStoring.prune` doesn't journal).
@MainActor
public final class FolderSync: SyncServicing {
    /// "Super Paste" in iCloud Drive when iCloud Drive is set up on this Mac; nil otherwise.
    public var defaultFolder: URL? { Self.defaultFolder }

    public nonisolated static var defaultFolder: URL? {
        let drive = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: drive.path) else { return nil }
        return drive.appendingPathComponent("Super Paste", isDirectory: true)
    }

    private let injectedStore: ItemStoring?
    private let injectedSyncStore: SyncStoring?
    private var store: ItemStoring { injectedStore ?? Services.store }
    private var syncStore: SyncStoring { injectedSyncStore ?? Services.syncStore }
    private let keyStore: SyncKeyStoring
    private let settings: SyncSettingsStoring
    private let stateFile: URL
    private let device: Device
    private let observesChanges: Bool

    /// Own log segments before they are folded into a snapshot.
    public var compactionThreshold = 200
    public var recordsPerSegment = 500
    /// How long an unreferenced blob stays in the folder (another Mac may be about to reference it again).
    public var blobGracePeriod: TimeInterval = 30 * 86_400
    public var blobSweepInterval: TimeInterval = 86_400
    /// How often the folder is checked when nothing announced a change.
    public var pollInterval: TimeInterval = 60

    private let statusSubject = CurrentValueSubject<SyncStatus, Never>(.disabled)
    private var state: SyncState
    private var passTask: Task<Void, Never>?
    private var needsAnotherPass = false
    /// Problems met during the current pass (unreadable files); the pass ends in `.error` when there are any.
    private var problems: [String] = []
    private var observers: Set<AnyCancellable> = []
    private var pollTimer: Timer?
    private var presenter: FolderPresenter?

    public init(store: ItemStoring?, syncStore: SyncStoring?, keyStore: SyncKeyStoring, settings: SyncSettingsStoring,
                stateDirectory: URL, device: Device = .current, observesChanges: Bool = true) {
        injectedStore = store
        injectedSyncStore = syncStore
        self.keyStore = keyStore
        self.settings = settings
        stateFile = stateDirectory.appendingPathComponent("state.json")
        self.device = device
        self.observesChanges = observesChanges
        state = SyncState.load(from: stateFile)
    }

    /// The app's instance: the store from `Services`, the key in the Keychain, settings in `Defaults`, state in
    /// `SuperPastePaths.sync`.
    convenience init() {
        self.init(store: nil, syncStore: nil, keyStore: KeychainSyncKeyStore(), settings: DefaultsSyncSettings(),
                  stateDirectory: SuperPastePaths.sync)
    }

    // MARK: SyncServicing

    public var status: SyncStatus { statusSubject.value }
    public var statusChanges: AnyPublisher<SyncStatus, Never> { statusSubject.removeDuplicates().eraseToAnyPublisher() }

    public var folder: URL? {
        guard settings.isEnabled, !settings.folderPath.isEmpty else { return nil }
        return URL(fileURLWithPath: settings.folderPath, isDirectory: true)
    }

    public func enable(folder: URL) throws {
        let root = folder.standardizedFileURL
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        if !fm.fileExists(atPath: root.path, isDirectory: &isDirectory) {
            // Only the folder itself is created: a missing parent (iCloud Drive turned off) is an error, not
            // something to recreate locally.
            do { try fm.createDirectory(at: root, withIntermediateDirectories: false) } catch {
                throw SyncError.folderUnavailable(error.localizedDescription)
            }
        } else if !isDirectory.boolValue {
            throw SyncError.folderUnavailable("“\(root.lastPathComponent)” isn't a folder.")
        }
        guard fm.isWritableFile(atPath: root.path) else {
            throw SyncError.folderUnavailable("Super Paste can't write to “\(root.lastPathComponent)”.")
        }
        _ = try keyAndIdentity(root)
        settings.folderPath = root.path
        settings.isEnabled = true
        Log.sync.info("Sync enabled")
        statusSubject.send(.syncing)
        startObserving()
        syncNow()
    }

    public func disable() {
        settings.isEnabled = false
        stopObserving()
        needsAnotherPass = false
        passTask?.cancel()
        statusSubject.send(.disabled)
        Log.sync.info("Sync disabled")
    }

    public func syncNow() {
        guard folder != nil else { statusSubject.send(.disabled); return }
        guard passTask == nil else { needsAnotherPass = true; return }
        passTask = Task { [weak self] in
            await self?.runPass()
            self?.passFinished()
        }
    }

    public func exportKey() -> String? { keyStore.load()?.text }

    public func importKey(_ text: String) throws {
        let key = try SyncKey(text: text)
        if let root = folder, SyncFolder.checkKey(root: root, key: key) == .mismatch { throw SyncError.keyMismatch }
        try keyStore.save(key)
        if folder != nil { syncNow() }
    }

    /// Picks syncing up again after launch when it was on.
    public func resume() {
        guard folder != nil else { statusSubject.send(.disabled); return }
        statusSubject.send(.synced(settings.lastSync))
        startObserving()
        syncNow()
    }

    /// Runs a pass (after the one in progress, if any) and returns when no pass is running or queued.
    public func syncAndWait() async {
        syncNow()
        while let task = passTask { await task.value }
    }

    private func passFinished() {
        passTask = nil
        if needsAnotherPass {
            needsAnotherPass = false
            syncNow()
        }
    }

    // MARK: A pass

    /// One full pass; only `syncNow()` starts one, so passes never overlap.
    private func runPass() async {
        guard let root = folder else { statusSubject.send(.disabled); return }
        statusSubject.send(.syncing)
        problems = []
        do {
            guard let io = try resolve(root) else { return }  // key.check still downloading: stay "syncing"
            // Every step re-checks that sync is still on: turning it off stops the pass between steps.
            try await ship(io, root: root)
            guard isActive(root) else { return }
            try await retryDeferred(io)
            guard isActive(root) else { return }
            let caughtUp = try await pull(io, root: root)
            if caughtUp && isActive(root) { await sweepBlobsIfDue(io) }
            guard isActive(root) else { return }
            state.save(to: stateFile)
            if let problem = problems.first {
                statusSubject.send(.error(problem))
            } else {
                let now = Date()
                settings.lastSync = now
                statusSubject.send(.synced(now))
            }
        } catch {
            state.save(to: stateFile)
            Log.sync.error("Sync failed: \(error.localizedDescription, privacy: .public)")
            if isActive(root) { statusSubject.send(.error(error.localizedDescription)) }
        }
    }

    /// Still enabled on the same folder (a pass stops as soon as sync is turned off or moved).
    private func isActive(_ root: URL) -> Bool { folder == root && !Task.isCancelled }

    /// Checks this Mac's key against the folder's `key.check`. A folder without Super Paste data is set up (with a
    /// new key when this Mac has none); nil while iCloud Drive is still downloading `key.check`.
    private func keyAndIdentity(_ root: URL) throws -> (key: SyncKey, folderID: String)? {
        let key = keyStore.load()
        switch SyncFolder.checkKey(root: root, key: key) {
        case .downloading:
            return nil
        case .mismatch:
            throw key == nil ? SyncError.missingKey : SyncError.keyMismatch
        case .matches(let id):
            return (key!, id)
        case .missing:
            let key = key ?? SyncKey.generate()
            try keyStore.save(key)
            return (key, try SyncFolder.writeKeyCheck(root: root, key: key))
        }
    }

    /// The folder to sync with; nil while `key.check` is downloading.
    private func resolve(_ root: URL) throws -> SyncFolder? {
        guard let (key, folderID) = try keyAndIdentity(root) else { return nil }
        if state.folderID != folderID || state.folderPath != root.path {
            // A new folder, or one that was wiped and set up again: send everything, read everything.
            state = SyncState(folderPath: root.path, folderID: folderID)
        }
        return SyncFolder(root: root, key: key)
    }

    // MARK: Shipping local changes

    private func ship(_ io: SyncFolder, root: URL) async throws {
        let mine = await io.listSegments(device: device.id)
        var next = max(state.lastSegment, mine.highest) + 1
        let last = state.lastSegment
        let lostOwnLog = last > 0 && !mine.logs.contains(last) && !mine.snapshots.contains(last) && !mine.pending.contains(last)
        if lostOwnLog || syncStore.journalHead < state.shippedSequence {
            // The folder lost this Mac's log, or the store started over: write everything again as a snapshot.
            try await writeSnapshot(io, number: next)
            return
        }
        var written = 0
        while isActive(root) {
            let entries = syncStore.journal(after: state.shippedSequence, limit: recordsPerSegment)
            guard let newest = entries.last else { break }
            let records = entries.map(\.record)
            try await uploadBlobs(for: records, io)
            try await io.writeSegment(SyncSegment(device: device.id, number: next, isSnapshot: false, createdAt: Date(),
                                                  writer: device, records: records))
            state.lastSegment = next
            state.shippedSequence = newest.sequence
            state.save(to: stateFile)
            next += 1
            written += 1
        }
        if written > 0, mine.logs.count + written >= compactionThreshold, isActive(root) {
            try await writeSnapshot(io, number: next)
        }
    }

    /// Writes the latest state of everything this Mac ever wrote as snapshot `number`, then deletes the segments
    /// before it.
    private func writeSnapshot(_ io: SyncFolder, number: Int) async throws {
        var records: [SyncRecord] = []
        var sequence: Int64 = 0
        while true {
            let entries = syncStore.journal(after: sequence, limit: 1_000)
            guard let newest = entries.last else { break }
            records += entries.map(\.record)
            sequence = newest.sequence
        }
        try await uploadBlobs(for: records, io)
        try await io.writeSegment(SyncSegment(device: device.id, number: number, isSnapshot: true, createdAt: Date(),
                                              writer: device, records: records))
        state.lastSegment = number
        state.shippedSequence = sequence
        state.save(to: stateFile)
        await io.deleteSegments(device: device.id, below: number)
        Log.sync.info("Wrote snapshot \(number) with \(records.count) records")
    }

    private func uploadBlobs(for records: [SyncRecord], _ io: SyncFolder) async throws {
        var seen = Set<String>()
        for ref in records.flatMap(\.blobRefs) where seen.insert(ref.digest).inserted {
            if await io.hasBlob(digest: ref.digest) { continue }
            guard let data = store.data(for: ref) else {
                Log.sync.error("Blob \(ref.digest.prefix(12), privacy: .public) is missing locally; not uploaded")
                continue
            }
            try await io.writeBlob(data, digest: ref.digest)
        }
    }

    // MARK: Applying other Macs' changes

    /// Reads every other Mac's new segments. Returns whether everything there was read (nothing downloading, no
    /// unreadable file), which the blob sweep requires.
    private func pull(_ io: SyncFolder, root: URL) async throws -> Bool {
        var caughtUp = true
        for deviceID in await io.deviceIDs() where deviceID != device.id {
            let listing = await io.listSegments(device: deviceID)
            let plan = SegmentOrder.plan(through: state.cursors[deviceID] ?? 0, logs: listing.logs,
                                         snapshots: listing.snapshots, pending: listing.pending)
            for step in plan {
                let number = step.number
                guard isActive(root) else { return false }
                let segment: SyncSegment
                do {
                    segment = try await io.readSegment(device: deviceID, number: number, snapshot: step.isSnapshot)
                } catch {
                    Log.sync.error("Skipped \(deviceID, privacy: .public)/\(number): \(error.localizedDescription, privacy: .public)")
                    problems.append(error.localizedDescription)
                    caughtUp = false
                    break
                }
                try await apply(segment.records, io)
                state.cursors[deviceID] = number
                state.save(to: stateFile)
            }
            if (state.cursors[deviceID] ?? 0) < listing.highest { caughtUp = false }
        }
        return caughtUp && state.deferred.isEmpty
    }

    private func apply(_ records: [SyncRecord], _ io: SyncFolder) async throws {
        var ready: [SyncRecord] = []
        for record in records {
            let key = record.syncKey
            if try await fetchBlobs(for: record, io) {
                ready.append(record)
                if let waiting = state.deferred[key], waiting.updatedAt <= record.updatedAt { state.deferred[key] = nil }
            } else if (state.deferred[key]?.updatedAt ?? .distantPast) < record.updatedAt {
                state.deferred[key] = record
            }
        }
        if !ready.isEmpty { try syncStore.apply(ready) }
    }

    private func retryDeferred(_ io: SyncFolder) async throws {
        var ready: [SyncRecord] = []
        for (key, record) in state.deferred.sorted(by: { $0.key < $1.key }) {
            guard try await fetchBlobs(for: record, io) else { continue }
            ready.append(record)
            state.deferred[key] = nil
        }
        if !ready.isEmpty { try syncStore.apply(ready) }
    }

    /// Saves the record's blobs from the folder into the store; false when one isn't available (yet).
    private func fetchBlobs(for record: SyncRecord, _ io: SyncFolder) async throws -> Bool {
        var seen = Set<String>()
        for ref in record.blobRefs where seen.insert(ref.digest).inserted && !syncStore.hasBlob(ref.digest) {
            switch await io.readBlob(digest: ref.digest) {
            case .data(let data):
                try store.saveBlob(data)
            case .missing:
                return false
            case .corrupt:
                let problem = SyncError.unreadableFile("blob \(ref.digest.prefix(12))").localizedDescription
                if !problems.contains(problem) { problems.append(problem) }
                return false
            }
        }
        return true
    }

    // MARK: Blob sweep

    /// Deletes folder blobs that no record in any Mac's log references any more. Liveness comes from the folder,
    /// never from this Mac's store: pruning is local (it doesn't journal), so an item pruned here may still live on
    /// a Mac that keeps history longer, and its blobs must stay.
    private func sweepBlobsIfDue(_ io: SyncFolder) async {
        let now = Date()
        if let last = state.lastBlobSweep, now.timeIntervalSince(last) < blobSweepInterval { return }
        guard let live = await io.referencedDigests() else { return }  // something unreadable or downloading: wait
        let deleted = await io.sweepBlobs(live: live, grace: blobGracePeriod, now: now)
        if deleted > 0 { Log.sync.info("Swept \(deleted) unused blobs from the sync folder") }
        state.lastBlobSweep = now
    }

    // MARK: Watching for changes

    private func startObserving() {
        guard observesChanges, observers.isEmpty, let root = folder else { return }
        store.changes
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.syncNow() } }
            .store(in: &observers)
        let folderChanged = PassthroughSubject<Void, Never>()
        folderChanged
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] in MainActor.assumeIsolated { self?.syncNow() } }
            .store(in: &observers)
        let presenter = FolderPresenter(url: root) { folderChanged.send() }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncNow() }
        }
    }

    private func stopObserving() {
        observers.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
    }
}

/// Hears about changes iCloud Drive (and other coordinated writers) make inside the sync folder.
private final class FolderPresenter: NSObject, NSFilePresenter {
    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue.main
    private let onChange: () -> Void

    init(url: URL, onChange: @escaping () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
    }

    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { onChange() }
}
