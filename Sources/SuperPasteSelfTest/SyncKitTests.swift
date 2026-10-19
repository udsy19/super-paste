import Foundation
import Combine
import SuperPasteCore
import SyncKit

// Owned by SyncKit.
func registerSyncKitTests() {
    SelfTest.cases.append(("SyncKit.install", { MainActor.assumeIsolated {
        SyncKitModule.install()
        checkNow(Services.sync != nil, "sync registered")
        checkNow(Services.sync.status == .disabled && Services.sync.folder == nil, "off by default")
    } }))
    SelfTest.cases.append(("SyncKit.crypto", { syncCrypto() }))
    SelfTest.cases.append(("SyncKit.readingOrder", { syncReadingOrder() }))
    SelfTest.cases.append(("SyncKit.twoMacsConverge", { MainActor.assumeIsolated { syncTwoMacs() } }))
    SelfTest.cases.append(("SyncKit.tamperedFilesRejected", { MainActor.assumeIsolated { syncTampering() } }))
    SelfTest.cases.append(("SyncKit.keysAndDisabled", { MainActor.assumeIsolated { syncKeysAndDisabled() } }))
    SelfTest.cases.append(("SyncKit.pruneStaysLocal", { MainActor.assumeIsolated { syncPruneStaysLocal() } }))
    SelfTest.cases.append(("SyncKit.compaction", { MainActor.assumeIsolated { syncCompaction() } }))
    SelfTest.cases.append(("SyncKit.filesStillArriving", { MainActor.assumeIsolated { syncArrivingFiles() } }))
    SelfTest.cases.append(("SyncKit.pausedWhileStoreNotDurable", { MainActor.assumeIsolated { syncNotDurable() } }))
}

// MARK: - Helpers shared with MCPKitTests

/// `check` with the condition evaluated by the caller, so main-actor state can be checked from main-actor code.
func checkNow(_ cond: Bool, _ msg: String, file: String = #fileID, line: Int = #line) {
    check(cond, msg, file: file, line: line)
}

/// Runs async main-actor work to completion while the main run loop keeps turning.
@MainActor
func awaitMain<T>(_ seconds: TimeInterval = 30, _ work: @escaping @MainActor () async throws -> T) -> Result<T, Error>? {
    var result: Result<T, Error>?
    Task { @MainActor in
        do { result = .success(try await work()) } catch { result = .failure(error) }
    }
    let deadline = Date().addingTimeInterval(seconds)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    return result
}

/// A throwaway folder under the system temporary directory, removed by the caller.
func scratchFolder(_ label: String) -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("superpaste-\(label)-\(UUID().uuidString)",
                                                                             isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// An in-memory `ItemStoring` + `SyncStoring` with the store contract's semantics (dedupe, pins, journal,
/// last-writer-wins apply with tombstones), for testing SyncKit and MCPKit without ClipStore.
@MainActor
final class MemoryClipStore: ItemStoring, SyncStoring {
    /// False to stand in for a store whose file couldn't be opened (`SyncStoring.isDurable`).
    var durable = true
    var isDurable: Bool { durable }
    private(set) var itemsByID: [UUID: ClipItem] = [:]
    private var fullText: [UUID: String] = [:]
    private var boards: [UUID: Pinboard] = [:]
    private(set) var blobs: [String: Data] = [:]
    private var tombstones: [String: Date] = [:]
    private var journalEntries: [JournalEntry] = []
    private var lastDeleted: [ClipItem] = []
    /// Shared by every store in the process, like one clock for all simulated Macs.
    private static var lastTime = Date()
    private let subject = PassthroughSubject<StoreChange, Never>()

    /// Strictly increasing timestamps, a millisecond apart, so last-writer-wins never sees a tie in tests.
    func tick() -> Date {
        Self.lastTime = max(Date(), Self.lastTime.addingTimeInterval(0.001))
        return Self.lastTime
    }

    private func journal(_ record: SyncRecord) {
        journalEntries.append(JournalEntry(sequence: Int64(journalEntries.count + 1), record: record))
    }

    private func save(_ item: ClipItem, journaled: Bool = true) {
        itemsByID[item.id] = item
        if journaled { journal(.item(item)) }
    }

    // MARK: Reading

    func item(_ id: UUID) -> ClipItem? { itemsByID[id] }
    func items(_ ids: [UUID]) -> [ClipItem] { ids.compactMap { itemsByID[$0] } }
    func text(of id: UUID) -> String? { fullText[id] }

    func search(_ query: SearchQuery, in scope: ListScope, limit: Int, offset: Int) -> [ClipItem] {
        Array(ordered(scope).filter { matches($0, query) }.dropFirst(offset).prefix(limit))
    }

    func count(_ query: SearchQuery, in scope: ListScope) -> Int { ordered(scope).filter { matches($0, query) }.count }

    var apps: [AppRecord] { Array(Set(itemsByID.values.compactMap(\.sourceApp))).sorted { $0.name < $1.name } }
    var devices: [Device] { Array(Set(itemsByID.values.compactMap(\.device))).sorted { $0.name < $1.name } }

    private func ordered(_ scope: ListScope) -> [ClipItem] {
        let all = Array(itemsByID.values)
        switch scope {
        case .history:
            return all.filter(\.isInHistory).sorted { $0.copiedAt! > $1.copiedAt! }
        case .all:
            return all.sorted { ($0.copiedAt ?? $0.createdAt) > ($1.copiedAt ?? $1.createdAt) }
        case .pinboard(let id):
            func order(_ item: ClipItem) -> Double { item.pins.first { $0.pinboardID == id }?.order ?? 0 }
            return all.filter { $0.isPinned(to: id) }.sorted { order($0) < order($1) }
        }
    }

    private func matches(_ item: ClipItem, _ query: SearchQuery) -> Bool {
        let haystack = ((item.title ?? "") + " " + (fullText[item.id] ?? item.text))
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for token in query.tokens where !haystack.contains(token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)) {
            return false
        }
        for type in SearchQuery.FilterType.allCases {
            let values = query.values(type)
            guard !values.isEmpty else { continue }
            let any = values.contains { value in
                let v = value.lowercased()
                switch type {
                case .app: return item.sourceApp.map { $0.name.lowercased().hasPrefix(v) || $0.bundleID == value } ?? false
                case .type: return ItemTypeFilter(filterValue: value)?.kinds.contains(item.kind) ?? false
                case .title: return item.title?.lowercased().contains(v) ?? false
                case .device: return item.device.map { $0.name.lowercased().hasPrefix(v) || $0.id == value } ?? false
                case .pinboard:
                    return boards.values.contains { ($0.name.lowercased() == v || $0.id.uuidString == value.uppercased()) && item.isPinned(to: $0.id) }
                case .date:
                    return DateRange.parse(value).map { $0.contains(item.copiedAt ?? item.createdAt) } ?? false
                }
            }
            if !any { return false }
        }
        return true
    }

    // MARK: Writing items

    @discardableResult func insert(_ draft: ClipDraft) throws -> InsertResult {
        if draft.copiedAt == nil, draft.pinboardID == nil { throw StoreError.invalidContent("A pinned-only item needs a pinboard.") }
        if let pinboardID = draft.pinboardID, boards[pinboardID] == nil { throw StoreError.pinboardNotFound(pinboardID) }
        let now = tick()
        if var existing = itemsByID.values.first(where: { $0.checksum == draft.checksum }) {
            if let copiedAt = draft.copiedAt {
                existing.copiedAt = copiedAt; existing.sourceApp = draft.sourceApp; existing.device = draft.device
            }
            if let pinboardID = draft.pinboardID, !existing.isPinned(to: pinboardID) {
                existing.pins.append(PinboardPin(pinboardID: pinboardID, order: nextOrder(in: pinboardID)))
            }
            existing.updatedAt = now
            save(existing)
            return InsertResult(item: existing, isNew: false)
        }
        var item = ClipItem(createdAt: now, copiedAt: draft.copiedAt, kind: draft.kind)
        fill(&item, from: draft)
        if let pinboardID = draft.pinboardID {
            item.pins = [PinboardPin(pinboardID: pinboardID, order: nextOrder(in: pinboardID))]
        }
        item.updatedAt = now
        save(item)
        return InsertResult(item: item, isNew: true)
    }

    private func fill(_ item: inout ClipItem, from draft: ClipDraft) {
        item.kind = draft.kind
        item.payload = draft.entries.map { entry in
            PasteboardEntry(reps: entry.reps.map { rep in
                blobs[ClipChecksum.hex(of: rep.data)] = rep.data
                return PasteboardRep(type: rep.type, blob: BlobRef(of: rep.data))
            })
        }
        item.text = String(draft.text.prefix(ClipItem.previewTextLimit))
        item.textLength = draft.text.count
        fullText[item.id] = draft.text
        if item.title == nil { item.title = draft.title }
        item.sourceApp = draft.sourceApp
        item.device = draft.device
        item.byteSize = draft.byteSize
        item.checksum = draft.checksum
        item.imageSize = draft.imageSize
        item.thumbnail = draft.thumbnail.map { data in blobs[ClipChecksum.hex(of: data)] = data; return BlobRef(of: data) }
        item.filePaths = draft.filePaths
        item.link = draft.link
    }

    private func nextOrder(in pinboardID: UUID) -> Double {
        (itemsByID.values.compactMap { $0.pins.first { $0.pinboardID == pinboardID }?.order }.max() ?? 0) + 1
    }

    private func existing(_ id: UUID) throws -> ClipItem {
        guard let item = itemsByID[id] else { throw StoreError.itemNotFound(id) }
        return item
    }

    func update(_ item: ClipItem) throws {
        var item = item
        _ = try existing(item.id)
        item.updatedAt = tick()
        save(item)
    }

    func rename(_ id: UUID, to title: String?) throws {
        var item = try existing(id)
        item.title = (title?.isEmpty ?? true) ? nil : title
        item.updatedAt = tick()
        save(item)
    }

    @discardableResult func replaceContent(of id: UUID, with draft: ClipDraft) throws -> ClipItem {
        var item = try existing(id)
        fill(&item, from: draft)
        item.updatedAt = tick()
        save(item)
        return item
    }

    func bump(_ id: UUID, at date: Date) throws {
        var item = try existing(id)
        item.copiedAt = date
        item.updatedAt = tick()
        save(item)
    }

    func markUsed(_ ids: [UUID], at date: Date) throws {
        for id in ids { itemsByID[id]?.lastUsedAt = date }
    }

    func delete(_ ids: [UUID]) throws {
        lastDeleted = ids.compactMap { itemsByID[$0] }
        for item in lastDeleted { remove(item.id) }
    }

    private func remove(_ id: UUID) {
        itemsByID[id] = nil
        let now = tick()
        tombstones["item/\(id.uuidString)"] = now
        journal(.tombstone(SyncTombstone(entity: .item, id: id, deletedAt: now)))
    }

    var canUndoDelete: Bool { !lastDeleted.isEmpty }

    @discardableResult func undoLastDelete() throws -> [ClipItem] {
        let restored = lastDeleted
        lastDeleted = []
        for var item in restored {
            item.updatedAt = tick()
            save(item)
        }
        return restored
    }

    // MARK: Pinboards

    var pinboards: [Pinboard] { boards.values.sorted { $0.order < $1.order } }

    @discardableResult func createPinboard(name: String, color: PinboardColor) throws -> Pinboard {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw StoreError.invalidName }
        let board = Pinboard(name: name, color: color, order: (boards.values.map(\.order).max() ?? -1) + 1, createdAt: tick())
        boards[board.id] = board
        journal(.pinboard(board))
        return board
    }

    func updatePinboard(_ pinboard: Pinboard) throws {
        guard boards[pinboard.id] != nil else { throw StoreError.pinboardNotFound(pinboard.id) }
        var board = pinboard
        board.name = board.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !board.name.isEmpty else { throw StoreError.invalidName }
        board.updatedAt = tick()
        boards[board.id] = board
        journal(.pinboard(board))
    }

    func deletePinboard(_ id: UUID) throws {
        guard boards[id] != nil else { throw StoreError.pinboardNotFound(id) }
        for item in itemsByID.values where item.isPinned(to: id) {
            if item.isInHistory || item.pins.count > 1 {
                var kept = item
                kept.pins.removeAll { $0.pinboardID == id }
                kept.updatedAt = tick()
                save(kept)
            } else {
                remove(item.id)
            }
        }
        boards[id] = nil
        let now = tick()
        tombstones["pinboard/\(id.uuidString)"] = now
        journal(.tombstone(SyncTombstone(entity: .pinboard, id: id, deletedAt: now)))
    }

    func reorderPinboards(_ ids: [UUID]) throws {
        for (index, id) in ids.enumerated() { boards[id]?.order = index }
    }

    func assign(_ itemIDs: [UUID], to pinboardID: UUID) throws {
        guard boards[pinboardID] != nil else { throw StoreError.pinboardNotFound(pinboardID) }
        for id in itemIDs {
            var item = try existing(id)
            guard !item.isPinned(to: pinboardID) else { continue }
            item.pins.append(PinboardPin(pinboardID: pinboardID, order: nextOrder(in: pinboardID)))
            item.updatedAt = tick()
            save(item)
        }
    }

    func unassign(_ itemIDs: [UUID], from pinboardID: UUID) throws {
        guard boards[pinboardID] != nil else { throw StoreError.pinboardNotFound(pinboardID) }
        for id in itemIDs {
            var item = try existing(id)
            guard item.isPinned(to: pinboardID) else { continue }
            item.pins.removeAll { $0.pinboardID == pinboardID }
            item.updatedAt = tick()
            // Nothing is deleted: an item that loses its last pin goes back to history with a fresh copy date.
            if item.pins.isEmpty && !item.isInHistory { item.copiedAt = item.updatedAt }
            save(item)
        }
    }

    func move(_ itemIDs: [UUID], in pinboardID: UUID, before beforeID: UUID?) throws {}

    // MARK: Retention

    private func prunable(retentionDays: Int, now: Date) -> [ClipItem] {
        guard retentionDays > 0 else { return [] }
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return itemsByID.values.filter { !$0.isPinned && ($0.copiedAt.map { $0 < cutoff } ?? false) }
    }

    func prunableCount(retentionDays: Int, now: Date) -> Int { prunable(retentionDays: retentionDays, now: now).count }

    /// Local only, like the store contract says: no tombstones.
    @discardableResult func prune(retentionDays: Int, now: Date) throws -> Int {
        let doomed = prunable(retentionDays: retentionDays, now: now)
        for item in doomed { itemsByID[item.id] = nil }
        return doomed.count
    }

    @discardableResult func eraseHistory() throws -> Int {
        let doomed = itemsByID.values.filter { $0.isInHistory && !$0.isPinned }
        for item in doomed { remove(item.id) }
        return doomed.count
    }

    func setRecognizedText(_ text: String, for id: UUID) throws {
        _ = try existing(id)
        fullText[id] = (fullText[id] ?? "") + "\n" + text
    }

    // MARK: Blobs

    func data(for blob: BlobRef) -> Data? { blobs[blob.digest] }
    func fileURL(for blob: BlobRef) -> URL? { nil }

    @discardableResult func saveBlob(_ data: Data) throws -> BlobRef {
        let ref = BlobRef(of: data)
        blobs[ref.digest] = data
        return ref
    }

    var changes: AnyPublisher<StoreChange, Never> { subject.eraseToAnyPublisher() }

    // MARK: SyncStoring

    var journalHead: Int64 { Int64(journalEntries.count) }

    func journal(after sequence: Int64, limit: Int) -> [JournalEntry] {
        var latest: [String: JournalEntry] = [:]
        for entry in journalEntries where entry.sequence > sequence { latest[key(entry.record)] = entry }
        return Array(latest.values.sorted { $0.sequence < $1.sequence }.prefix(limit))
    }

    private func key(_ record: SyncRecord) -> String {
        switch record {
        case .item(let item): "item/\(item.id.uuidString)"
        case .pinboard(let board): "pinboard/\(board.id.uuidString)"
        case .tombstone(let t): "\(t.entity.rawValue)/\(t.id.uuidString)"
        }
    }

    @discardableResult func apply(_ records: [SyncRecord]) throws -> Int {
        var changed = 0
        for record in records {
            let k = key(record)
            let local: Date? = switch record {
            case .item(let item): itemsByID[item.id]?.updatedAt
            case .pinboard(let board): boards[board.id]?.updatedAt
            case .tombstone(let t): t.entity == .item ? itemsByID[t.id]?.updatedAt : boards[t.id]?.updatedAt
            }
            let newest = [local, tombstones[k]].compactMap { $0 }.max()
            guard newest.map({ record.updatedAt > $0 }) ?? true else { continue }
            switch record {
            case .item(let item):
                for ref in item.blobRefs where blobs[ref.digest] == nil {
                    throw StoreError.invalidContent("blob \(ref.digest) missing")
                }
                itemsByID[item.id] = item
                tombstones[k] = nil
            case .pinboard(let board):
                boards[board.id] = board
                tombstones[k] = nil
            case .tombstone(let t):
                if t.entity == .item { itemsByID[t.id] = nil } else { boards[t.id] = nil }
                tombstones[k] = t.deletedAt
            }
            changed += 1
        }
        if changed > 0 { subject.send(.reloaded) }
        return changed
    }

    func hasBlob(_ digest: String) -> Bool { blobs[digest] != nil }

    /// What two stores must agree on after syncing.
    var snapshot: [String] {
        let items = itemsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }.map {
            "\($0.id) \($0.title ?? "-") \($0.text) \($0.pins.map(\.pinboardID.uuidString).sorted()) \($0.updatedAt.timeIntervalSince1970)"
        }
        return items + pinboards.map { "\($0.id) \($0.name)" }
    }
}

@MainActor
final class MemorySyncKeyStore: SyncKeyStoring {
    var key: SyncKey?
    func load() -> SyncKey? { key }
    func save(_ key: SyncKey) throws { self.key = key }
}

@MainActor
final class MemorySyncSettings: SyncSettingsStoring {
    var isEnabled = false
    var folderPath = ""
    var lastSync: Date?
}

/// One simulated Mac: a store, a key, settings and a FolderSync that only syncs when told to.
@MainActor
private struct SimulatedMac {
    let store = MemoryClipStore()
    let keys = MemorySyncKeyStore()
    let sync: FolderSync

    init(_ name: String, stateRoot: URL) {
        sync = FolderSync(store: store, syncStore: store, keyStore: keys, settings: MemorySyncSettings(),
                          stateDirectory: stateRoot.appendingPathComponent(name), device: Device(id: "mac-\(name)", name: name),
                          observesChanges: false)
    }

    func pass() { _ = awaitMain { await sync.syncAndWait() } }
}

// MARK: - Cases

private func syncCrypto() {
    let key = SyncKey.generate()
    let plain = Data("clipboard secret".utf8)
    let sealed = try? SyncCrypto.seal(plain, key: key, context: "devices/a/00000001.log")
    checkNow(sealed != nil && (try? SyncCrypto.open(sealed!, key: key, context: "devices/a/00000001.log")) == plain, "round trip")
    checkNow(sealed.map { $0.range(of: plain) == nil } ?? false, "ciphertext doesn't contain the plaintext")
    checkNow((try? SyncCrypto.open(sealed!, key: key, context: "devices/a/00000002.log")) == nil, "a renamed file doesn't open")
    checkNow((try? SyncCrypto.open(sealed!, key: SyncKey.generate(), context: "devices/a/00000001.log")) == nil, "another key doesn't open it")
    for index in [4, 5, 10, sealed!.count / 2, sealed!.count - 1] {
        var tampered = sealed!
        tampered[index] ^= 0x01
        checkNow((try? SyncCrypto.open(tampered, key: key, context: "devices/a/00000001.log")) == nil, "flipped byte \(index) is rejected")
    }
    checkNow((try? SyncCrypto.open(sealed!.dropLast(), key: key, context: "devices/a/00000001.log")) == nil, "truncated file is rejected")
    checkNow((try? SyncCrypto.open(Data("SPS1".utf8), key: key, context: "x")) == nil, "header only is rejected")

    let big = Data(String(repeating: "abc ", count: 10_000).utf8)
    let packed = try? SyncCrypto.seal(big, key: key, context: "c", compress: true)
    checkNow(packed != nil && packed!.count < big.count / 4, "compressible data shrinks")
    checkNow(packed.flatMap { try? SyncCrypto.open($0, key: key, context: "c") } == big, "compressed round trip")

    let text = key.text
    checkNow(text.hasPrefix(SyncKey.textPrefix), "key text has its prefix")
    checkNow((try? SyncKey(text: text))?.matches(key) == true, "key text round trip")
    let wrapped = "  " + String(text.prefix(20)) + "\n" + String(text.dropFirst(20)) + " \n"
    checkNow((try? SyncKey(text: wrapped))?.matches(key) == true, "whitespace and line breaks are ignored")
    checkNow((try? SyncKey(text: String(text.dropFirst(SyncKey.textPrefix.count))))?.matches(key) == true, "prefix is optional")
    for bad in ["", "SPK1-", "SPK1-abc", "not a key", SyncKey.textPrefix + Data(count: 16).base64EncodedString()] {
        checkNow((try? SyncKey(text: bad)) == nil, "rejects \"\(bad)\"")
    }
    let digest = ClipChecksum.hex(of: plain)
    checkNow(key.blobName(forDigest: digest) == key.blobName(forDigest: digest), "blob names are stable")
    checkNow(key.blobName(forDigest: digest) != digest && key.blobName(forDigest: digest) != SyncKey.generate().blobName(forDigest: digest),
          "blob names are keyed, not the content digest")
}

private func syncReadingOrder() {
    typealias Step = SegmentOrder.Step
    func plan(_ through: Int, logs: Set<Int>, snaps: Set<Int> = [], pending: Set<Int> = []) -> [Step] {
        SegmentOrder.plan(through: through, logs: logs, snapshots: snaps, pending: pending)
    }
    checkNow(plan(0, logs: [1, 2, 3]) == [Step(1), Step(2), Step(3)], "consecutive segments in order")
    checkNow(plan(2, logs: [1, 2, 3]) == [Step(3)], "only what's new")
    checkNow(plan(0, logs: [1, 2, 4]) == [Step(1), Step(2)], "a gap (3 hasn't arrived) stops reading")
    checkNow(plan(0, logs: [1, 3], pending: [2]) == [Step(1)], "a download in progress stops reading")
    checkNow(plan(1, logs: [5, 6], snaps: [4]) == [Step(4, snapshot: true), Step(5), Step(6)], "a snapshot supersedes what precedes it")
    checkNow(plan(1, logs: [2, 3, 5], snaps: [4]) == [Step(4, snapshot: true), Step(5)], "logs not yet deleted before a snapshot are skipped")
    checkNow(plan(6, logs: [7], snaps: [4]) == [Step(7)], "an older snapshot is ignored")
    checkNow(plan(1, logs: [2], snaps: [4], pending: [4]) == [Step(2)], "a snapshot still downloading isn't used yet")
    checkNow(plan(3, logs: []) == [], "nothing new")
}

@MainActor
private func syncTwoMacs() {
    let root = scratchFolder("sync-two")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Shared", isDirectory: true)
    let a = SimulatedMac("A", stateRoot: root)
    let b = SimulatedMac("B", stateRoot: root)

    let image = Data((0..<4096).map { UInt8($0 % 251) })
    let text = try! a.store.insert(.text("Meeting notes for Thursday")).item
    let picture = try! a.store.insert(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: image)])], kind: .image,
                                                imageSize: PixelSize(width: 32, height: 32))).item
    let board = try! a.store.createPinboard(name: "Work", color: .blue)
    try! a.store.assign([text.id], to: board.id)

    checkNow((try? a.sync.enable(folder: folder)) != nil, "A enables sync on a new folder")
    checkNow(a.keys.key != nil, "a key is generated")
    a.pass()
    checkNow(a.sync.status.isSynced, "A synced: \(a.sync.status)")

    // B can't join without A's key.
    checkNow(throwsError(SyncError.missingKey) { try b.sync.enable(folder: folder) }, "B needs the key first")
    checkNow((try? b.sync.importKey(a.sync.exportKey() ?? "")) != nil, "B imports A's key")
    checkNow((try? b.sync.enable(folder: folder)) != nil, "B joins the folder")
    b.pass()
    checkNow(b.sync.status.isSynced, "B synced: \(b.sync.status)")
    checkNow(b.store.snapshot == a.store.snapshot, "B has A's items and pinboard")
    checkNow(b.store.data(for: BlobRef(of: image)) == image, "B has the image bytes")
    checkNow(b.store.item(text.id)?.isPinned(to: board.id) == true, "pins travel")

    // Edits on both sides, including deletes and a conflict.
    try! b.store.delete([text.id])
    try! b.store.rename(picture.id, to: "Diagram")
    let fromB = try! b.store.insert(.text("Written on B")).item
    try! a.store.rename(picture.id, to: "Older title")  // A's rename happens first…
    try! b.store.rename(picture.id, to: "Newest title")  // …B's later one wins everywhere.
    let doomed = try! a.store.insert(.text("Edited on A, deleted on B")).item
    a.pass(); b.pass()
    try! a.store.rename(doomed.id, to: "A's edit")
    try! b.store.delete([doomed.id])  // later than A's edit
    a.pass(); b.pass(); a.pass()
    checkNow(a.store.item(text.id) == nil && b.store.item(text.id) == nil, "a delete on B reaches A")
    checkNow(a.store.item(picture.id)?.title == "Newest title" && b.store.item(picture.id)?.title == "Newest title", "the later edit wins on both")
    checkNow(a.store.item(fromB.id)?.text == "Written on B", "B's new item reaches A")
    checkNow(a.store.item(doomed.id) == nil && b.store.item(doomed.id) == nil, "a later delete beats an earlier edit")
    checkNow(a.store.snapshot == b.store.snapshot, "both Macs converge")

    // A delete that is older than an edit loses on both sides.
    let survivor = try! a.store.insert(.text("Deleted on A, then edited on B")).item
    a.pass(); b.pass()
    try! a.store.delete([survivor.id])
    try! b.store.rename(survivor.id, to: "Kept")
    b.pass(); a.pass(); b.pass()
    checkNow(a.store.item(survivor.id)?.title == "Kept" && b.store.item(survivor.id)?.title == "Kept", "a later edit beats an earlier delete")
    checkNow(a.store.snapshot == b.store.snapshot, "still converged")

    // Nothing readable in the folder.
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
    let plaintexts = ["Meeting notes", "Written on B", "Work", "Diagram", "public.png"].map { Data($0.utf8) }
    let leaks = files.filter { file in
        guard let data = try? Data(contentsOf: file) else { return false }
        return data.range(of: image) != nil || plaintexts.contains { data.range(of: $0) != nil }
    }
    checkNow(!files.isEmpty && leaks.isEmpty, "no plaintext in the folder (\(leaks.map(\.lastPathComponent)))")
    let blobFiles = files.filter { $0.pathExtension == "blob" }.map { $0.deletingPathExtension().lastPathComponent }
    checkNow(!blobFiles.isEmpty && !blobFiles.contains(ClipChecksum.hex(of: image)), "blob names don't reveal the content digest")
}

@MainActor
private func syncTampering() {
    let root = scratchFolder("sync-tamper")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Shared", isDirectory: true)
    let a = SimulatedMac("A", stateRoot: root)
    let item = try! a.store.insert(.text("first")).item
    try? a.sync.enable(folder: folder)
    a.pass()

    // A byte flipped in A's log segment: C refuses it and reports, applies nothing from it.
    let segment = folder.appendingPathComponent("devices/mac-A/00000001.log")
    var bytes = try! Data(contentsOf: segment)
    let original = bytes
    bytes[bytes.count / 2] ^= 0xFF
    try! bytes.write(to: segment)
    let c = SimulatedMac("C", stateRoot: root)
    try? c.sync.importKey(a.sync.exportKey()!)
    checkNow((try? c.sync.enable(folder: folder)) != nil, "C joins")
    c.pass()
    checkNow(c.store.item(item.id) == nil, "nothing from a tampered segment is applied")
    if case .error(let message) = c.sync.status { checkNow(message.contains("couldn't be decrypted"), "status explains: \(message)") } else {
        checkNow(false, "status is an error: \(c.sync.status)")
    }
    try! original.write(to: segment)
    c.pass()
    checkNow(c.store.item(item.id)?.text == "first" && c.sync.status.isSynced, "the restored segment is read")

    // A blob replaced with other bytes sealed under the right key: the item waits instead of getting wrong content.
    let real = Data("the real image".utf8)
    let picture = try! a.store.insert(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: real)])], kind: .image)).item
    a.pass()
    let key = try! SyncKey(text: a.sync.exportKey()!)
    let name = key.blobName(forDigest: ClipChecksum.hex(of: real))
    let blob = folder.appendingPathComponent("blobs/\(name.prefix(2))/\(name).blob")
    let genuine = try! Data(contentsOf: blob)
    try! SyncCrypto.seal(Data("forged".utf8), key: key, context: "blobs/\(name)").write(to: blob)
    c.pass()
    checkNow(c.store.item(picture.id) == nil && !c.store.hasBlob(ClipChecksum.hex(of: Data("forged".utf8))), "a forged blob is refused")
    checkNow({ if case .error = c.sync.status { true } else { false } }(), "and reported")
    try! genuine.write(to: blob)
    c.pass()
    checkNow(c.store.item(picture.id) != nil && c.store.data(for: BlobRef(of: real)) == real, "the item arrives once the blob is genuine")
    checkNow(c.sync.status.isSynced, "status recovers")
}

@MainActor
private func syncKeysAndDisabled() {
    let root = scratchFolder("sync-keys")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Shared", isDirectory: true)
    let a = SimulatedMac("A", stateRoot: root)
    _ = try? a.store.insert(.text("never leaves"))

    // Off: no pass touches the folder.
    a.sync.syncNow()
    a.pass()
    checkNow(a.sync.status == .disabled && a.sync.folder == nil, "disabled by default")
    checkNow(!FileManager.default.fileExists(atPath: folder.path), "nothing written while disabled")
    checkNow(a.sync.exportKey() == nil, "no key until sync is set up")

    try? a.sync.enable(folder: folder)
    a.pass()
    a.sync.disable()
    checkNow(a.sync.status == .disabled && a.sync.folder == nil, "disabled again")
    let before = Set(FileManager.default.enumerator(atPath: folder.path)?.compactMap { $0 as? String } ?? [])
    _ = try? a.store.insert(.text("written while off"))
    a.sync.syncNow()
    a.pass()
    let after = Set(FileManager.default.enumerator(atPath: folder.path)?.compactMap { $0 as? String } ?? [])
    checkNow(before == after, "no files change while disabled")

    // A Mac with a different key can't join, and can't import a key that doesn't fit the folder it syncs.
    let d = SimulatedMac("D", stateRoot: root)
    d.keys.key = SyncKey.generate()
    checkNow(throwsError(SyncError.keyMismatch) { try d.sync.enable(folder: folder) }, "a different key is refused")
    checkNow(throwsError(SyncError.invalidKey) { try d.sync.importKey("hello") }, "garbage isn't a key")
    try? a.sync.enable(folder: folder)
    checkNow(throwsError(SyncError.keyMismatch) { try a.sync.importKey(SyncKey.generate().text) }, "a key that doesn't open the folder")
    checkNow(throwsError(SyncError.folderUnavailable("")) { try a.sync.enable(folder: root.appendingPathComponent("missing/deeper")) },
          "a folder whose parent is missing")
    a.sync.disable()
}

@MainActor
private func syncPruneStaysLocal() {
    let root = scratchFolder("sync-prune")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Shared", isDirectory: true)
    let a = SimulatedMac("A", stateRoot: root)
    let b = SimulatedMac("B", stateRoot: root)
    let bytes = Data("an old screenshot".utf8)
    let old = try! a.store.insert(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: bytes)])], kind: .image,
                                            copiedAt: Date().addingTimeInterval(-40 * 86_400))).item
    let erased = try! a.store.insert(.text("erase me")).item
    try? a.sync.enable(folder: folder)
    a.pass()
    try? b.sync.importKey(a.sync.exportKey()!)
    try? b.sync.enable(folder: folder)
    b.pass()
    checkNow(b.store.item(old.id) != nil, "B has the old item")

    // A keeps a week of history and prunes; B keeps everything.
    checkNow((try? a.store.prune(retentionDays: 7, now: Date())) == 1 && a.store.item(old.id) == nil, "A pruned locally")
    // An orphan blob nobody references, old enough to sweep.
    let key = try! SyncKey(text: a.sync.exportKey()!)
    let orphanName = key.blobName(forDigest: ClipChecksum.hex(of: Data("orphan".utf8)))
    let orphan = folder.appendingPathComponent("blobs/\(orphanName.prefix(2))/\(orphanName).blob")
    try? FileManager.default.createDirectory(at: orphan.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? SyncCrypto.seal(Data("orphan".utf8), key: key, context: "blobs/\(orphanName)").write(to: orphan)
    a.sync.blobGracePeriod = 0
    a.sync.blobSweepInterval = 0
    a.pass(); b.pass()
    checkNow(b.store.item(old.id) != nil, "pruning on A doesn't delete on B")
    let imageName = key.blobName(forDigest: ClipChecksum.hex(of: bytes))
    checkNow(FileManager.default.fileExists(atPath: folder.appendingPathComponent("blobs/\(imageName.prefix(2))/\(imageName).blob").path),
             "the sweep keeps a blob another Mac's item still uses")
    checkNow(!FileManager.default.fileExists(atPath: orphan.path), "the sweep removes a blob nothing references")

    // Erase History does travel.
    _ = try? a.store.eraseHistory()
    a.pass(); b.pass()
    checkNow(b.store.item(erased.id) == nil, "Erase History on A reaches B")
}

@MainActor
private func syncCompaction() {
    let root = scratchFolder("sync-compact")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Shared", isDirectory: true)
    let a = SimulatedMac("A", stateRoot: root)
    a.sync.compactionThreshold = 3
    a.sync.recordsPerSegment = 1
    try? a.sync.enable(folder: folder)
    a.pass()
    for n in 1...5 { _ = try? a.store.insert(.text("note \(n)")) }
    let first = a.store.search(.empty, in: .all, limit: 10, offset: 0).last!
    try? a.store.delete([first.id])
    a.pass()
    let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("devices/mac-A").path)) ?? []
    checkNow(names.count == 1 && names[0].hasSuffix(".snap"), "logs folded into one snapshot: \(names)")

    let e = SimulatedMac("E", stateRoot: root)
    try? e.sync.importKey(a.sync.exportKey()!)
    try? e.sync.enable(folder: folder)
    e.pass()
    checkNow(e.store.snapshot == a.store.snapshot && e.store.itemsByID.count == 4, "a new Mac converges from the snapshot")
    _ = try? a.store.insert(.text("after the snapshot"))
    a.pass(); e.pass()
    checkNow(e.store.snapshot == a.store.snapshot, "and keeps up with segments after it")
}

private func throwsError(_ expected: SyncError, _ body: () throws -> Void) -> Bool {
    do { try body(); return false } catch let error as SyncError {
        if case .folderUnavailable = expected, case .folderUnavailable = error { return true }
        return error == expected
    } catch { return false }
}

private extension SyncStatus {
    var isSynced: Bool { if case .synced = self { true } else { false } }
}

/// A segment or blob file a cloud service has created but not yet filled is "not here yet", never "damaged": nothing
/// is reported, nothing is skipped, and it is read once it is whole.
@MainActor
private func syncArrivingFiles() {
    let root = scratchFolder("sync-arriving")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Shared", isDirectory: true)
    let fm = FileManager.default
    let a = SimulatedMac("A", stateRoot: root)
    let first = try! a.store.insert(.text("first")).item
    try? a.sync.enable(folder: folder)
    a.pass()

    // A's next segment exists but is empty (being uploaded): C reads up to it and waits.
    let arriving = folder.appendingPathComponent("devices/mac-A/00000002.log")
    fm.createFile(atPath: arriving.path, contents: Data())
    let c = SimulatedMac("C", stateRoot: root)
    try? c.sync.importKey(a.sync.exportKey()!)
    try? c.sync.enable(folder: folder)
    c.pass()
    checkNow(c.store.item(first.id)?.text == "first", "what is whole is read")
    checkNow(c.sync.status.isSynced, "an empty file isn't an error: \(c.sync.status)")
    try? fm.removeItem(at: arriving)
    let second = try! a.store.insert(.text("second")).item
    a.pass()
    c.pass()
    checkNow(c.store.item(second.id)?.text == "second" && c.sync.status.isSynced, "read once it is whole")

    // A blob file that is empty: the record waits for it instead of being refused as forged.
    let image = Data("a screenshot".utf8)
    let picture = try! a.store.insert(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: image)])], kind: .image)).item
    a.pass()
    let key = try! SyncKey(text: a.sync.exportKey()!)
    let name = key.blobName(forDigest: ClipChecksum.hex(of: image))
    let blob = folder.appendingPathComponent("blobs/\(name.prefix(2))/\(name).blob")
    let sealedBlob = try! Data(contentsOf: blob)
    try! Data().write(to: blob)
    c.pass()
    checkNow(c.store.item(picture.id) == nil && c.sync.status.isSynced, "the item waits for its bytes, without an error")
    try! sealedBlob.write(to: blob)
    c.pass()
    checkNow(c.store.item(picture.id) != nil && c.store.hasBlob(ClipChecksum.hex(of: image)), "applied once the blob is whole")
}

/// A store running from memory (its file couldn't be opened) never ships: an empty journal would otherwise become an
/// empty snapshot that replaces this Mac's log in the folder.
@MainActor
private func syncNotDurable() {
    let root = scratchFolder("sync-durable")
    defer { try? FileManager.default.removeItem(at: root) }
    let folder = root.appendingPathComponent("Shared", isDirectory: true)
    let a = SimulatedMac("A", stateRoot: root)
    _ = try! a.store.insert(.text("shipped while durable"))
    try? a.sync.enable(folder: folder)
    a.pass()
    let device = folder.appendingPathComponent("devices/mac-A")
    let before = (try? FileManager.default.contentsOfDirectory(atPath: device.path)) ?? []
    checkNow(before == ["00000001.log"], "one segment shipped: \(before)")

    a.store.durable = false
    _ = try? a.store.insert(.text("only in memory"))
    a.pass()
    let after = (try? FileManager.default.contentsOfDirectory(atPath: device.path)) ?? []
    checkNow(after == before, "nothing written while the store isn't durable: \(after)")
    if case .error(let message) = a.sync.status { checkNow(message.contains("paused"), "status says why: \(message)") } else {
        checkNow(false, "status is the pause: \(a.sync.status)")
    }
    a.store.durable = true
    a.pass()
    checkNow(a.sync.status.isSynced, "resumes once durable again")
}
