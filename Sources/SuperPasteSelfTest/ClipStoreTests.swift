import Foundation
import Combine
import SuperPasteCore
import ClipStore

// Owned by ClipStore. Every store here lives in its own folder under the self-test's temporary base.
func registerClipStoreTests() {
    let cases: [(String, @MainActor () -> Void)] = [
        ("ClipStore.install", storeInstall),
        ("ClipStore.insertAndRead", storeInsertAndRead),
        ("ClipStore.dedupe", storeDedupe),
        ("ClipStore.search", storeSearch),
        ("ClipStore.pinboards", storePinboards),
        ("ClipStore.pinOrder", storePinOrder),
        ("ClipStore.retention", storeRetention),
        ("ClipStore.undoDelete", storeUndoDelete),
        ("ClipStore.blobs", storeBlobs),
        ("ClipStore.edits", storeEdits),
        ("ClipStore.recognizedText", storeRecognizedText),
        ("ClipStore.changes", storeChanges),
        ("ClipStore.syncJournal", storeSyncJournal),
        ("ClipStore.syncApply", storeSyncApply),
        ("ClipStore.persistence", storePersistence),
        ("ClipStore.recovery", storeRecovery),
        ("ClipStore.performance", storePerformance),
    ]
    for (name, run) in cases {
        SelfTest.cases.append((name, { MainActor.assumeIsolated { run() } }))
    }
}

// MARK: - Fixtures

private typealias Store = any ItemStoring & SyncStoring

private let safari = AppRecord(bundleID: "com.apple.Safari", name: "Safari", colorHex: "#62A9F5")
private let vscode = AppRecord(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code")
private let studio = Device(id: "device-studio", name: "Studio Mac")
private let air = Device(id: "device-air", name: "MacBook Air")

@MainActor private func makeStore(in folder: URL? = nil, retentionDays: Int = HistoryRetention.forever) -> (Store, URL) {
    let folder = folder ?? SuperPastePaths.base.appendingPathComponent("clipstore-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = ClipStoreModule.makeStore(database: folder.appendingPathComponent("clips.sqlite"),
                                          blobs: folder.appendingPathComponent("Blobs", isDirectory: true),
                                          backup: folder.appendingPathComponent("Backup", isDirectory: true),
                                          retentionDays: { retentionDays })
    return (store, folder)
}

private func text(_ string: String, app: AppRecord? = nil, device: Device? = studio, at date: Date? = Date(),
                  pinboard: UUID? = nil, title: String? = nil) -> ClipDraft {
    var draft = ClipDraft.text(string, title: title, sourceApp: app, copiedAt: date, pinboardID: pinboard)
    draft.device = device
    return draft
}

@MainActor private func insert(_ store: Store, _ draft: ClipDraft) -> ClipItem {
    do { return try store.insert(draft).item } catch {
        check(false, "insert failed: \(error)")
        return ClipItem(kind: .unknown)
    }
}

@MainActor private func ids(_ store: Store, _ query: String, _ scope: ListScope = .history) -> [UUID] {
    store.search(SearchQuery(parsing: query), in: scope, limit: 100, offset: 0).map(\.id)
}

private func throwsError(_ expected: StoreError, _ body: () throws -> Void) -> Bool {
    do { try body(); return false } catch let error as StoreError { return error == expected } catch { return false }
}

private func bytes(_ count: Int, seed: UInt8) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 31) ^ seed }) }

// MARK: - Cases

@MainActor private func storeInstall() {
    ClipStoreModule.install()
    check(Services.store != nil && Services.syncStore != nil, "store and sync store registered")
    check(Services.store === Services.syncStore, "one object serves both protocols")
    check(SuperPastePaths.database.path.hasPrefix(SuperPastePaths.base.path), "the database lives under the temporary base")
    check(FileManager.default.fileExists(atPath: SuperPastePaths.database.path), "the database file exists")
}

@MainActor private func storeInsertAndRead() {
    let (store, _) = makeStore()
    let result = try? store.insert(text("Hello Wörld", app: safari))
    check(result?.isNew == true, "a new item is new")
    guard let item = result?.item else { return }
    check(store.item(item.id) == item, "the stored item reads back field for field")
    check(item.kind == .text && item.text == "Hello Wörld" && item.textLength == 11, "kind and text")
    check(item.byteSize == 12 && item.checksum == ClipDraft.text("Hello Wörld").checksum, "size and checksum")
    check(store.data(for: item.payload[0].reps[0].blob) == Data("Hello Wörld".utf8), "payload bytes")
    check(store.apps == [safari] && store.devices == [studio], "apps and devices with items")

    let long = String(repeating: "lorem ipsum ", count: 2_500) + "needle"
    let big = insert(store, text(long))
    check(big.text.count == ClipItem.previewTextLimit && big.textLength == long.count, "preview capped, length kept")
    check(store.item(big.id)?.text.count == ClipItem.previewTextLimit, "stored preview capped")
    check(ids(store, "needle") == [big.id], "search reaches past the preview")

    let pixels = bytes(150_000, seed: 7)
    let thumb = bytes(2_000, seed: 9)
    let image = insert(store, ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: pixels)])], kind: .image,
                                        sourceApp: vscode, imageSize: PixelSize(width: 640, height: 480), thumbnail: thumb))
    check(store.item(image.id) == image, "image item reads back")
    check(image.imageSize == PixelSize(width: 640, height: 480) && image.thumbnail.flatMap(store.data(for:)) == thumb, "image fields")
    let pixelRef = image.payload[0].reps[0].blob
    check(store.fileURL(for: pixelRef).flatMap { try? Data(contentsOf: $0) } == pixels, "a large blob is a file")
    check(store.fileURL(for: image.thumbnail!) == nil, "a small blob stays inline")

    let files = insert(store, ClipDraft(entries: [EntryData(reps: [RepData(type: "public.file-url", data: Data("file:///a".utf8))]),
                                                  EntryData(reps: [RepData(type: "public.file-url", data: Data("file:///b%20c".utf8))])],
                                        kind: .files, text: "a\nb c", filePaths: ["/a", "/b c"]))
    check(store.item(files.id) == files && files.payload.count == 2 && files.filePaths == ["/a", "/b c"], "files item, two entries")

    let icon = try? store.saveBlob(bytes(500, seed: 1))
    var linkDraft = text("https://example.com/page")
    linkDraft.link = LinkMetadata(url: "https://example.com/page", title: "Example", icon: icon, fetchedAt: Date())
    let link = insert(store, linkDraft)
    check(link.kind == .link && store.item(link.id) == link, "link item with metadata reads back")

    let missing = UUID()
    check(store.items([link.id, missing, item.id]).map(\.id) == [link.id, item.id], "items(_:) keeps the given order")
}

@MainActor private func storeDedupe() {
    let (store, _) = makeStore()
    let first = Date(timeIntervalSinceReferenceDate: 700_000_000)
    let second = first.addingTimeInterval(60)
    let original = insert(store, text("same text", app: safari, at: first))
    _ = insert(store, text("other", at: first.addingTimeInterval(30)))
    let again = try? store.insert(text("same text", app: vscode, device: air, at: second))
    check(again?.isNew == false && again?.item.id == original.id, "the same content reuses the item")
    check(again?.item.copiedAt == second && again?.item.lastUsedAt == second, "moved to the front, last used updated")
    check(again?.item.sourceApp == vscode && again?.item.device == air, "takes the new source app and device")
    check(ids(store, "") == [original.id, ids(store, "other")[0]], "it is first in the history")
    check(store.count(.empty, in: .history) == 2, "no copy was added")

    var marked = text("same text", at: second)
    marked.entries[0].reps.append(RepData(type: PasteboardType.itemID, data: Data(original.id.uuidString.utf8)))
    check((try? store.insert(marked))?.isNew == false, "volatile types don't defeat dedupe")

    guard let board = try? store.createPinboard(name: "Work", color: .blue) else { return check(false, "pinboard") }
    let pinned = try? store.insert(text("same text", at: nil, pinboard: board.id))
    check(pinned?.isNew == false && pinned?.item.pinboardIDs == [board.id], "a pinned-only draft pins the existing item")
    check(pinned?.item.copiedAt == second, "pinning doesn't move it in the history")
    check(throwsError(.invalidContent("A pinned-only item needs a pinboard.")) { try store.insert(text("x", at: nil)) },
          "a pinned-only draft needs a pinboard")
    let unknown = UUID()
    check(throwsError(.pinboardNotFound(unknown)) { try store.insert(text("y", pinboard: unknown)) }, "unknown pinboard")
}

@MainActor private func storeSearch() {
    let (store, _) = makeStore()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    let base = calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 12))!
    let hour: TimeInterval = 3_600
    let a = insert(store, text("Meeting slides for Monday", app: safari, device: studio, at: base))
    let b = insert(store, text("Café menu", app: vscode, device: air, at: base - hour, title: "Lunch Invoice"))
    let c = insert(store, text("https://example.com/docs", app: safari, at: base - 2 * hour))
    let e = insert(store, text("a -> b arrow", at: base - 3 * hour))
    let d = insert(store, text("#FF8800", at: base - 50 * 24 * hour))
    guard let work = try? store.createPinboard(name: "Work", color: .green) else { return check(false, "pinboard") }
    let f = insert(store, text("Pinned note", at: nil, pinboard: work.id))

    check(ids(store, "") == [a.id, b.id, c.id, e.id, d.id], "history: newest first, pinned-only left out")
    check(ids(store, "", .all).first == f.id && ids(store, "", .all).count == 6, "all: pinned-only included")
    check(ids(store, "", .pinboard(work.id)) == [f.id], "pinboard scope")

    check(ids(store, "meet") == [a.id] && ids(store, "MEET") == [a.id], "word prefix, any case")
    check(ids(store, "cafe") == [b.id] && ids(store, "café") == [b.id], "diacritics ignored")
    check(ids(store, "slides monday") == [a.id] && ids(store, "slides tuesday").isEmpty, "tokens AND together")
    check(ids(store, "\"meeting slides\"") == [a.id] && ids(store, "\"slides meeting\"").isEmpty, "quoted phrase")
    check(ids(store, "lunch") == [b.id], "tokens match the title")
    check(ids(store, "->") == [e.id], "punctuation-only token matches as a substring")
    check(ids(store, "safari").isEmpty, "free text doesn't match the app name")
    check(ids(store, "note", .all) == [f.id] && ids(store, "note").isEmpty, "scope applies to tokens")

    check(ids(store, "type:link") == [c.id], "type filter")
    check(ids(store, "type:links type:colour") == [c.id, d.id], "type filters OR together")
    check(ids(store, "type:bogus").isEmpty, "unknown type matches nothing")
    check(ids(store, "app:Safari") == [a.id, c.id] && ids(store, "app:safari") == [a.id, c.id], "app by name")
    check(ids(store, "app:com.apple.Safari") == [a.id, c.id], "app by bundle id")
    check(ids(store, "app:Visual") == [b.id] && ids(store, "app:\"Visual Studio\"") == [b.id], "app name prefix")
    check(ids(store, "app:Studio").isEmpty && ids(store, "app:Nope").isEmpty, "app name must match from the start")
    check(ids(store, "app:Safari app:Visual") == [a.id, b.id, c.id], "app filters OR together")
    check(ids(store, "device:studio").contains(a.id) && !ids(store, "device:studio").contains(b.id), "device by name prefix")
    check(ids(store, "device:device-air") == [b.id] && ids(store, "device:zzz").isEmpty, "device by id")
    check(ids(store, "date:2024-03-10") == [a.id, b.id, c.id, e.id], "date: one day")
    check(ids(store, "date:2024-01-01..2024-02-01") == [d.id], "date: range")
    check(ids(store, "date:2024-03-10 date:2024-01-20") == [a.id, b.id, c.id, e.id, d.id], "date filters OR together")
    check(ids(store, "date:someday").isEmpty, "unparseable date matches nothing")
    check(ids(store, "title:invoice") == [b.id] && ids(store, "title:VOIC") == [b.id], "title substring, any case")
    check(ids(store, "title:zzz").isEmpty, "title filter")
    check(ids(store, "pinboard:work", .all) == [f.id] && ids(store, "pinboard:\(work.id.uuidString)", .all) == [f.id],
          "pinboard by name or id")
    check(ids(store, "pinboard:nope", .all).isEmpty, "unknown pinboard matches nothing")
    check(ids(store, "meeting app:Safari type:text") == [a.id] && ids(store, "meeting type:link").isEmpty, "tokens and filters AND")

    let query = SearchQuery(parsing: "app:Safari")
    check(store.count(query, in: .history) == 2 && store.count(.empty, in: .all) == 6, "count")
    check(store.count(SearchQuery(parsing: "type:bogus"), in: .history) == 0, "count of an impossible query")
    check(store.search(.empty, in: .history, limit: 2, offset: 1).map(\.id) == [b.id, c.id], "limit and offset")
}

@MainActor private func storePinboards() {
    let (store, _) = makeStore()
    guard let work = try? store.createPinboard(name: "  Work ", color: .blue),
          let home = try? store.createPinboard(name: "Home", color: .red) else { return check(false, "create pinboards") }
    check(work.name == "Work" && work.order == 0 && home.order == 1, "name trimmed, appended to the tab bar")
    check(throwsError(.invalidName) { try store.createPinboard(name: "  ", color: .gray) }, "empty name")
    var renamed = work
    renamed.name = "Office"
    renamed.color = .purple
    renamed.shortcut = Shortcut(key: 18, modifiers: [.control, .option])
    check((try? store.updatePinboard(renamed)) != nil, "update pinboard")
    let stored = store.pinboards.first
    check(stored?.name == "Office" && stored?.color == .purple && stored?.shortcut == renamed.shortcut, "update saved")
    check(throwsError(.pinboardNotFound(renamed.id)) {
        try store.deletePinboard(renamed.id); try store.updatePinboard(renamed)
    } && store.pinboards.map(\.id) == [home.id], "deleted pinboard can't be updated")

    let a = try! store.createPinboard(name: "A", color: .green)
    let b = try! store.createPinboard(name: "B", color: .yellow)
    check((try? store.reorderPinboards([b.id, home.id, a.id])) != nil && store.pinboards.map(\.id) == [b.id, home.id, a.id], "reorder")
    let stray = UUID()
    check(throwsError(.pinboardNotFound(stray)) { try store.reorderPinboards([stray]) }, "reorder with an unknown id")

    let history = insert(store, text("history item"))
    let pinnedOnly = insert(store, text("pinned only", at: nil, pinboard: a.id))
    let shared = insert(store, text("in two pinboards", at: nil, pinboard: a.id))
    try? store.assign([history.id, shared.id], to: b.id)
    try? store.assign([history.id], to: a.id)
    try? store.assign([history.id], to: a.id)
    check(store.item(shared.id)?.pinboardIDs == [b.id, a.id], "pins listed in tab order")
    check(ids(store, "", .pinboard(a.id)) == [pinnedOnly.id, shared.id, history.id], "assign appends, idempotently")
    check(throwsError(.itemNotFound(stray)) { try store.assign([stray], to: a.id) }, "assign an unknown item")

    try? store.unassign([history.id], from: b.id)
    check(store.item(history.id)?.pinboardIDs == [a.id], "unassign keeps other pins")
    let unpinTime = Date()
    try? store.unassign([pinnedOnly.id], from: a.id)
    let unpinned = store.item(pinnedOnly.id)
    check(unpinned?.isPinned == false && (unpinned?.copiedAt ?? .distantPast) >= unpinTime && ids(store, "").first == pinnedOnly.id,
          "a pinned-only item losing its last pin goes to the front of the history")
    let aged = insert(store, text("aged", at: Date() - 40 * 86_400))
    try? store.assign([aged.id], to: b.id)
    try? store.unassign([aged.id], from: b.id)
    check(store.item(aged.id) != nil && store.prunableCount(retentionDays: 30, now: Date()) == 0,
          "unpinning refreshes the copy date, so retention keeps the item")

    let onlyInA = insert(store, text("only in A", at: nil, pinboard: a.id))
    let agedInA = insert(store, text("aged in A", at: Date() - 40 * 86_400))
    try? store.assign([agedInA.id], to: a.id)
    let deleteTime = Date()
    try? store.deletePinboard(a.id)
    check(store.item(onlyInA.id) == nil, "deleting a pinboard deletes its pinned-only items")
    check(store.item(history.id)?.isPinned == false && store.item(history.id)?.isInHistory == true, "history items stay")
    check((store.item(agedInA.id)?.copiedAt ?? .distantPast) >= deleteTime && store.prunableCount(retentionDays: 30, now: Date()) == 0,
          "items losing their last pin get a fresh copy date, so retention keeps them")
    check(store.item(shared.id)?.pinboardIDs == [b.id], "items pinned elsewhere keep those pins")
    check(store.pinboards.map(\.id) == [b.id, home.id], "pinboard gone")
}

@MainActor private func storePinOrder() {
    let (store, _) = makeStore()
    guard let board = try? store.createPinboard(name: "Order", color: .orange) else { return check(false, "pinboard") }
    let items = (0..<5).map { insert(store, text("item \($0)", at: nil, pinboard: board.id)) }
    func order() -> [UUID] { ids(store, "", .pinboard(board.id)) }
    let (i0, i1, i2, i3, i4) = (items[0].id, items[1].id, items[2].id, items[3].id, items[4].id)
    check(order() == [i0, i1, i2, i3, i4], "pin order follows assignment")
    try? store.move([i4], in: board.id, before: i0)
    check(order() == [i4, i0, i1, i2, i3], "move to the front")
    try? store.move([i4], in: board.id, before: nil)
    check(order() == [i0, i1, i2, i3, i4], "move to the end")
    try? store.move([i3, i1], in: board.id, before: i0)
    check(order() == [i3, i1, i0, i2, i4], "move several, in the given order")
    try? store.move([i2], in: board.id, before: i2)
    check(order() == [i3, i1, i0, i2, i4], "before itself keeps the place")
    let stray = UUID()
    check(throwsError(.itemNotFound(stray)) { try store.move([stray], in: board.id, before: nil) }, "move an unpinned item")
    // Halving the same gap again and again exhausts it; the pinboard is renumbered and the order holds.
    var consistent = true
    for _ in 0..<80 {
        let current = order()
        try? store.move([current[4]], in: board.id, before: current[1])
        consistent = consistent && order() == [current[0], current[4], current[1], current[2], current[3]]
    }
    check(consistent, "every move lands just before its anchor")
    let final = order()
    check(final.count == 5 && Set(final) == Set(items.map(\.id)), "order survives many moves")
    let pins = store.items(final).compactMap { $0.pins.first?.order }
    check(pins == pins.sorted() && Set(pins).count == 5, "positions stay distinct and ascending")
}

@MainActor private func storeRetention() {
    let (store, _) = makeStore(retentionDays: 30)
    let now = Date()
    let day: TimeInterval = 86_400
    guard let board = try? store.createPinboard(name: "Keep", color: .gray) else { return check(false, "pinboard") }
    let old = insert(store, text("old", at: now - 40 * day))
    let oldPinned = insert(store, text("old pinned", at: now - 40 * day))
    try? store.assign([oldPinned.id], to: board.id)
    let recent = insert(store, text("recent", at: now - day))
    let pinnedOnly = insert(store, text("pinned only", at: nil, pinboard: board.id))
    check(store.prunableCount(retentionDays: 30, now: now) == 1, "one prunable item")
    check(store.prunableCount(retentionDays: HistoryRetention.forever, now: now) == 0, "forever prunes nothing")
    check((try? store.prune(retentionDays: 0, now: now)) == 0, "prune forever")
    check((try? store.prune(retentionDays: 30, now: now)) == 1, "prune deletes the old unpinned item")
    check(store.item(old.id) == nil && store.item(oldPinned.id) != nil && store.item(recent.id) != nil, "pinned and recent stay")
    func mentions(_ id: UUID) -> Bool {
        store.journal(after: 0, limit: 100).contains {
            switch $0.record {
            case .item(let item): item.id == id
            case .tombstone(let tombstone): tombstone.id == id
            case .pinboard: false
            }
        }
    }
    check(!mentions(old.id), "pruning is local: no tombstone, nothing journaled")

    // Sync can't bring a pruned item straight back; a newer copy or a pin here can.
    var stale = old
    stale.updatedAt = now + 1
    check((try? store.apply([.item(stale)])) == 0 && store.item(old.id) == nil, "an old remote copy stays pruned")
    var pinnedHere = stale
    pinnedHere.id = UUID()
    pinnedHere.pins = [PinboardPin(pinboardID: board.id, order: 9)]
    check((try? store.apply([.item(pinnedHere)])) == 1 && store.item(pinnedHere.id) != nil, "an old item pinned here is applied")
    var recopied = stale
    recopied.copiedAt = now
    recopied.updatedAt = now + 2
    check((try? store.apply([.item(recopied)])) == 1 && store.item(old.id) != nil, "a copy made again elsewhere comes back")

    check((try? store.eraseHistory()) == 2, "erase deletes unpinned history")
    check(store.item(recent.id) == nil && store.item(oldPinned.id)?.isInHistory == true && store.item(pinnedOnly.id) != nil,
          "erase keeps pinned items")
    check(mentions(recent.id) && mentions(old.id), "erasing syncs its deletions")
    check(store.pinboards.count == 1, "erase keeps pinboards")
}

@MainActor private func storeUndoDelete() {
    let (store, _) = makeStore()
    guard let board = try? store.createPinboard(name: "Board", color: .pink) else { return check(false, "pinboard") }
    let payload = bytes(120_000, seed: 3)
    var draft = ClipDraft(entries: [EntryData(reps: [RepData(type: PasteboardType.plainText, data: Data("unique words zebra".utf8)),
                                                       RepData(type: "com.example.big", data: payload)])],
                          kind: .text, text: "unique words zebra")
    draft.pinboardID = board.id
    let a = insert(store, draft)
    let b = insert(store, text("second item"))
    check(!store.canUndoDelete, "nothing to undo yet")
    try? store.delete([UUID()])
    check(!store.canUndoDelete, "deleting nothing leaves no undo")

    try? store.delete([a.id])
    let bigRef = a.payload[0].reps[1].blob
    check(store.item(a.id) == nil && store.canUndoDelete, "deleted, undo available")
    check(store.data(for: bigRef) == payload, "blobs kept while undo is possible")
    let restored = (try? store.undoLastDelete()) ?? []
    check(restored.map(\.id) == [a.id] && !store.canUndoDelete, "undo restores the batch once")
    let back = store.item(a.id)
    check(back?.payload == a.payload && back?.pinboardIDs == [board.id] && back?.copiedAt == a.copiedAt, "restored as it was")
    check(ids(store, "zebra") == [a.id], "restored item is searchable again")
    check(store.journal(after: 0, limit: 100).last?.record == back.map { .item($0) }, "restore journals the item")

    try? store.delete([a.id])
    try? store.delete([b.id])
    check(store.data(for: bigRef) == nil && store.fileURL(for: bigRef) == nil, "a newer delete releases the older batch's blobs")
    check(((try? store.undoLastDelete()) ?? []).map(\.id) == [b.id] && store.item(a.id) == nil, "undo restores the latest batch")
    check(((try? store.undoLastDelete()) ?? []).isEmpty, "undo twice does nothing")
}

@MainActor private func storeBlobs() {
    let (store, folder) = makeStore()
    let small = Data("small blob".utf8)
    let ref = try? store.saveBlob(small)
    check(ref == BlobRef(of: small) && (try? store.saveBlob(small)) == ref, "saveBlob is idempotent and content-addressed")
    check(ref.map { store.hasBlob($0.digest) } == true && ref.flatMap(store.data(for:)) == small, "inline blob")
    check(ref.flatMap(store.fileURL(for:)) == nil, "inline blobs have no file")
    let large = bytes(200_000, seed: 5)
    guard let largeRef = try? store.saveBlob(large), let url = store.fileURL(for: largeRef) else { return check(false, "large blob") }
    check(url.lastPathComponent == largeRef.digest && url.deletingLastPathComponent().lastPathComponent == String(largeRef.digest.prefix(2)),
          "file named by digest in a two-digit shard")
    check(url.path.hasPrefix(folder.path) && (try? Data(contentsOf: url)) == large, "file blob contents")
    check(!store.hasBlob(String(repeating: "0", count: 64)), "unknown digest")
    try? FileManager.default.removeItem(at: url)
    check(!store.hasBlob(largeRef.digest), "a file blob whose file is gone isn't there")
    check((try? store.saveBlob(large)) == largeRef && store.hasBlob(largeRef.digest), "saving again restores the file")

    // Two items sharing one blob: deleting one keeps the bytes the other needs.
    let x = insert(store, text("shared bytes"))
    var other = text("shared bytes")
    other.entries[0].reps.append(RepData(type: "public.text", data: Data("extra".utf8)))
    let y = insert(store, other)
    try? store.delete([x.id])
    try? store.delete([UUID()])
    _ = insert(store, text("unrelated"))
    try? store.delete([ids(store, "unrelated")[0]])
    check(store.data(for: y.payload[0].reps[0].blob) == Data("shared bytes".utf8), "shared blob survives")
}

@MainActor private func storeEdits() {
    let (store, _) = makeStore()
    guard let board = try? store.createPinboard(name: "Edits", color: .blue) else { return check(false, "pinboard") }
    let original = insert(store, text("original words", app: safari, pinboard: board.id, title: "Note"))
    let older = insert(store, text("older item", at: Date() - 100))
    guard let edited = try? store.replaceContent(of: original.id, with: ClipDraft.text("#00FF00")) else { return check(false, "edit") }
    check(edited.id == original.id && edited.title == "Note" && edited.pins == original.pins && edited.copiedAt == original.copiedAt,
          "replaceContent keeps id, title, pins and history place")
    check(edited.kind == .color && edited.text == "#00FF00" && edited.checksum != original.checksum, "new content")
    check(store.item(original.id) == edited, "edit saved")
    check(ids(store, "original").isEmpty && ids(store, "00ff00") == [original.id], "index follows the content")

    check((try? store.update(original)) != nil, "update restores the old item (edit undo)")
    let undone = store.item(original.id)
    check(undone?.text == "original words" && undone.flatMap { store.data(for: $0.payload[0].reps[0].blob) } == Data("original words".utf8),
          "old blobs still there")
    check((undone?.updatedAt ?? .distantPast) > original.updatedAt && ids(store, "original") == [original.id], "update bumps updatedAt, reindexes")
    var homeless = original
    homeless.copiedAt = nil
    homeless.pins = []
    check(throwsError(.invalidContent("An item needs a place in the history or a pinboard.")) { try store.update(homeless) }, "update needs a place")
    let ghost = ClipItem(copiedAt: Date(), kind: .text)
    check(throwsError(.itemNotFound(ghost.id)) { try store.update(ghost) }, "update of a missing item")

    try? store.rename(original.id, to: "  Renamed  ")
    check(store.item(original.id)?.title == "Renamed" && ids(store, "renamed") == [original.id], "rename trims and indexes")
    try? store.rename(original.id, to: "   ")
    check(store.item(original.id)?.title == nil && ids(store, "renamed").isEmpty, "blank rename clears")
    check(throwsError(.itemNotFound(ghost.id)) { try store.rename(ghost.id, to: "x") }, "rename of a missing item")

    let used = Date(timeIntervalSinceReferenceDate: 750_000_000)
    let before = store.item(older.id)
    try? store.markUsed([older.id], at: used)
    check(store.item(older.id)?.lastUsedAt == used && store.item(older.id)?.updatedAt == before?.updatedAt, "markUsed records, no sync bump")
    check(ids(store, "").first == original.id, "markUsed doesn't reorder")
    try? store.bump(older.id, at: Date() + 10)
    check(ids(store, "").first == older.id, "bump moves to the front")
}

@MainActor private func storeRecognizedText() {
    let (store, _) = makeStore()
    let png = { (seed: UInt8) in ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: bytes(1_000, seed: seed))])],
                                           kind: .image) }
    let image = insert(store, png(4))
    check(ids(store, "invoice").isEmpty, "nothing recognised yet")
    var events: [StoreChange] = []
    let subscription = store.changes.sink { events.append($0) }
    let head = store.journalHead
    check((try? store.setRecognizedText("Invoice total 42 €", for: image.id)) != nil, "set recognised text")
    check(ids(store, "invoice") == [image.id] && ids(store, "TOTAL 42") == [image.id], "recognised text is searchable")
    check(events == [.updated([image.id])], "publishes an update")
    check(store.journal(after: head, limit: 10).map(\.record) == store.item(image.id).map { [.item($0)] }, "journaled")
    check(store.item(image.id)?.updatedAt == image.updatedAt, "updatedAt unchanged (the text doesn't travel)")
    let ghost = UUID()
    check(throwsError(.itemNotFound(ghost)) { try store.setRecognizedText("x", for: ghost) }, "unknown item")
    try? store.rename(image.id, to: "Scan")
    check(ids(store, "invoice") == [image.id], "kept across a rename")
    _ = try? store.replaceContent(of: image.id, with: png(8))
    check(ids(store, "invoice").isEmpty, "new content drops the old recognised text")
    subscription.cancel()
}

@MainActor private func storeChanges() {
    let (store, _) = makeStore()
    var events: [StoreChange] = []
    let subscription = store.changes.sink { events.append($0) }
    let item = insert(store, text("observed"))
    _ = insert(store, text("observed"))
    try? store.rename(item.id, to: "Title")
    let board = try? store.createPinboard(name: "Seen", color: .red)
    try? store.assign([item.id], to: board!.id)
    try? store.markUsed([item.id], at: Date())
    let other = insert(store, text("doomed"))
    try? store.delete([other.id])
    _ = try? store.undoLastDelete()
    _ = try? store.eraseHistory()
    check(events == [.inserted([item.id]), .updated([item.id]), .updated([item.id]), .pinboards, .updated([item.id]),
                     .updated([item.id]), .inserted([other.id]), .deleted([other.id]), .inserted([other.id]), .reloaded],
          "precise change events: \(events)")
    subscription.cancel()
}

@MainActor private func storeSyncJournal() {
    let (store, _) = makeStore()
    check(store.journalHead == 0 && store.journal(after: 0, limit: 10).isEmpty, "empty journal")
    let item = insert(store, text("journaled"))
    check(store.journalHead == 1, "insert journals")
    try? store.rename(item.id, to: "Latest")
    let entries = store.journal(after: 0, limit: 10)
    check(entries.count == 1 && entries[0].sequence == 2, "one entry per record, re-sequenced")
    if case .item(let journaled)? = entries.first?.record { check(journaled.title == "Latest", "latest state") }
    else { check(false, "item record") }
    let board = try? store.createPinboard(name: "Synced", color: .green)
    check(store.journal(after: 2, limit: 10).map(\.record) == board.map { [.pinboard($0)] }, "pinboard journaled")
    check(store.journal(after: 0, limit: 1).count == 1 && store.journal(after: store.journalHead, limit: 10).isEmpty, "limit and cursor")
    try? store.delete([item.id])
    guard case .tombstone(let tombstone)? = store.journal(after: 0, limit: 10).last?.record else { return check(false, "tombstone") }
    check(tombstone.entity == .item && tombstone.id == item.id, "deletes journal tombstones")
    try? store.markUsed([item.id], at: Date())
    check(store.journalHead == 4, "head counts every journaled write")
}

@MainActor private func storeSyncApply() {
    let (source, _) = makeStore()
    let (target, _) = makeStore()
    let icon = bytes(300, seed: 2)
    guard let board = try? source.createPinboard(name: "Remote", color: .purple) else { return check(false, "pinboard") }
    var draft = text("from another mac", app: AppRecord(bundleID: "com.example.app", name: "Example", icon: try? source.saveBlob(icon)),
                     pinboard: board.id)
    draft.copiedAt = Date()
    let item = insert(source, draft)
    let records = source.journal(after: 0, limit: 100).map(\.record)
    check(!target.hasBlob(item.payload[0].reps[0].blob.digest), "the target lacks the blobs at first")
    for ref in item.blobRefs { _ = try? target.saveBlob(source.data(for: ref)!) }
    check(item.blobRefs.allSatisfy { target.hasBlob($0.digest) }, "blobs saved first")

    var events: [StoreChange] = []
    let subscription = target.changes.sink { events.append($0) }
    check((try? target.apply(records)) == 2, "pinboard and item applied")
    check(target.item(item.id) == item && target.pinboards == [board], "records arrive whole")
    check(ids(target, "another") == [item.id], "applied items are searchable")
    check(target.journalHead == 0, "applying doesn't journal")
    check(events == [.reloaded], "apply publishes a reload")
    check((try? target.apply(records)) == 0, "applying again changes nothing")

    var older = item
    older.title = "Older"
    older.updatedAt = item.updatedAt - 10
    check((try? target.apply([.item(older)])) == 0 && target.item(item.id)?.title == nil, "an older record loses")
    var newer = item
    newer.title = "Newer"
    newer.updatedAt = item.updatedAt + 10
    check((try? target.apply([.item(newer)])) == 1 && target.item(item.id)?.title == "Newer", "a newer record wins")
    check(ids(target, "newer") == [item.id], "title reindexed")

    let staleDelete = SyncTombstone(entity: .item, id: item.id, deletedAt: newer.updatedAt - 1)
    check((try? target.apply([.tombstone(staleDelete)])) == 0 && target.item(item.id) != nil, "an older tombstone loses")
    let delete = SyncTombstone(entity: .item, id: item.id, deletedAt: newer.updatedAt + 5)
    check((try? target.apply([.tombstone(delete)])) == 1 && target.item(item.id) == nil, "a newer tombstone deletes")
    check((try? target.apply([.item(newer)])) == 0 && target.item(item.id) == nil, "a deleted record doesn't come back")
    var revived = newer
    revived.updatedAt = delete.deletedAt + 5
    check((try? target.apply([.item(revived)])) == 1 && target.item(item.id) != nil, "a record newer than the tombstone returns")

    let pinnedOnly = insert(source, text("only pinned", at: nil, pinboard: board.id))
    _ = try? target.apply([.item(pinnedOnly)])
    check(target.item(pinnedOnly.id)?.pinboardIDs == [board.id], "pinned-only item applied")
    let boardGone = SyncTombstone(entity: .pinboard, id: board.id, deletedAt: Date() + 60)
    check((try? target.apply([.tombstone(boardGone)])) == 1 && target.pinboards.isEmpty, "pinboard tombstone deletes")
    check(target.item(pinnedOnly.id) == nil && target.item(item.id)?.isPinned == false, "its pinned-only items go, history stays")
    subscription.cancel()
}

@MainActor private func storePersistence() {
    let folder: URL
    let id: UUID
    do {
        let (store, f) = makeStore()
        folder = f
        id = insert(store, text("survives a relaunch")).id
        _ = try? store.createPinboard(name: "Kept", color: .yellow)
    }
    let (reopened, _) = makeStore(in: folder)
    check(reopened.item(id)?.text == "survives a relaunch" && reopened.pinboards.map(\.name) == ["Kept"], "data persists")
    check(ids(reopened, "relaunch") == [id] && reopened.journalHead == 2, "index and journal persist")
}

@MainActor private func storeRecovery() {
    let folder = SuperPastePaths.base.appendingPathComponent("clipstore-damaged-\(UUID().uuidString)", isDirectory: true)
    let fm = FileManager.default
    try? fm.createDirectory(at: folder.appendingPathComponent("Blobs/ab", isDirectory: true), withIntermediateDirectories: true)
    let garbage = Data(String(repeating: "this is not a database ", count: 400).utf8)
    try? garbage.write(to: folder.appendingPathComponent("clips.sqlite"))
    try? Data("old".utf8).write(to: folder.appendingPathComponent("Blobs/ab/abc"))
    let (store, _) = makeStore(in: folder)
    check((try? store.insert(text("fresh start"))) != nil && ids(store, "fresh").count == 1, "a fresh store works")
    let backups = (try? fm.contentsOfDirectory(at: folder.appendingPathComponent("Backup"), includingPropertiesForKeys: nil)) ?? []
    check(backups.count == 1, "the damaged store moved to one backup folder")
    if let backup = backups.first {
        check((try? Data(contentsOf: backup.appendingPathComponent("clips.sqlite"))) == garbage, "damaged database kept as it was")
        check(fm.fileExists(atPath: backup.appendingPathComponent("Blobs/ab/abc").path), "its blobs moved with it")
    }
}

@MainActor private func storePerformance() {
    let (store, _) = makeStore()
    let words = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliet", "kilo",
                 "lima", "mike", "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform", "victor"]
    let apps = [safari, vscode, AppRecord(bundleID: "com.apple.mail", name: "Mail")]
    let start = Date(timeIntervalSinceReferenceDate: 700_000_000)
    let clock = ContinuousClock()
    let insertTime = clock.measure {
        for n in 0..<2_000 {
            let body = (0..<12).map { words[($0 * 7 + n * 13 + $0 * n) % words.count] }.joined(separator: " ") + " item\(n)"
            _ = try? store.insert(text(body, app: apps[n % 3], device: n % 2 == 0 ? studio : air, at: start + Double(n) * 60))
        }
    }
    check(store.count(.empty, in: .history) == 2_000, "2,000 items inserted")
    check(insertTime < .seconds(20), "inserting 2,000 items took \(insertTime)")
    let queries = ["alpha", "a", "tango victor", "item1999", "app:Mail", "type:text app:Visual", "\"echo foxtrot\"",
                   "sierra device:Studio date:2023-03-07..2024-01-01", "title:x", "zzz", "->"]
    var slowest = Duration.zero
    for text in queries {
        let query = SearchQuery(parsing: text)
        let elapsed = clock.measure {
            _ = store.search(query, in: .history, limit: 100, offset: 0)
            _ = store.count(query, in: .history)
        }
        slowest = max(slowest, elapsed)
        check(elapsed < .milliseconds(50), "search \"\(text)\" took \(elapsed)")
    }
    check(ids(store, "item1999") == [ids(store, "")[0]], "search finds the newest item")
    print("  ClipStore.performance: 2,000 inserts in \(insertTime), slowest search + count \(slowest)")
}
