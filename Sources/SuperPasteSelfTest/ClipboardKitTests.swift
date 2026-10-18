import AppKit
import Combine
import SuperPasteCore
import ClipboardKit

// Owned by ClipboardKit. Every pasteboard here is a uniquely named one, released at the end of its case; the general
// pasteboard is never read or written, no key event is posted, ⌘V is never registered, nothing is shown or played.
func registerClipboardKitTests() {
    SelfTest.cases.append(("ClipboardKit.install", { MainActor.assumeIsolated {
        ClipboardKitModule.install()
        check(Services.clipboard != nil && Services.pasting != nil, "monitor and pasting registered")
        registerInertServices()
    } }))
    SelfTest.cases.append(("ClipboardKit.ignoredApps", { clipboardIgnoredApps() }))
    SelfTest.cases.append(("ClipboardKit.captureFilter", { clipboardCaptureFilter() }))
    SelfTest.cases.append(("ClipboardKit.quirks", { clipboardQuirks() }))
    SelfTest.cases.append(("ClipboardKit.classify", { clipboardClassify() }))
    SelfTest.cases.append(("ClipboardKit.pasteContent", { clipboardPasteContent() }))
    SelfTest.cases.append(("ClipboardKit.multiPaste", { clipboardMultiPaste() }))
    SelfTest.cases.append(("ClipboardKit.pasteStackEngine", { clipboardPasteStackEngine() }))
    SelfTest.cases.append(("ClipboardKit.appRecords", { MainActor.assumeIsolated { clipboardAppRecords() } }))
    SelfTest.cases.append(("ClipboardKit.pasteboardIO", { clipboardPasteboardIO() }))
    SelfTest.cases.append(("ClipboardKit.monitor", { MainActor.assumeIsolated { clipboardMonitor() } }))
    SelfTest.cases.append(("ClipboardKit.pause", { MainActor.assumeIsolated { clipboardPause() } }))
    SelfTest.cases.append(("ClipboardKit.enrichment", { MainActor.assumeIsolated { clipboardEnrichment() } }))
    SelfTest.cases.append(("ClipboardKit.paste", { MainActor.assumeIsolated { clipboardPaste() } }))
    SelfTest.cases.append(("ClipboardKit.pasteStack", { MainActor.assumeIsolated { clipboardPasteStack() } }))
}

// MARK: - Fixtures

private let utf8 = PasteboardType.plainText
private let rtfType = NSPasteboard.PasteboardType.rtf.rawValue
private let htmlType = NSPasteboard.PasteboardType.html.rawValue
private let pngType = NSPasteboard.PasteboardType.png.rawValue
private let fileURLType = NSPasteboard.PasteboardType.fileURL.rawValue
private let utf16Type = "public.utf16-plain-text"

private func rep(_ type: String, _ text: String) -> RepData { RepData(type: type, data: Data(text.utf8)) }
private func entry(_ reps: RepData...) -> EntryData { EntryData(reps: reps) }
private func textEntry(_ text: String) -> EntryData { entry(rep(utf8, text)) }

private func rtfData(_ text: String, bold: Bool = true) -> Data {
    let attributed = NSAttributedString(string: text, attributes: [.font: bold ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13)])
    return attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                          documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])!
}

/// A solid-colour PNG.
private func pngData(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ImageEncoding.png(context.makeImage()!)!
}

private func pixelSize(of data: Data?) -> PixelSize? {
    guard let data, let image = NSBitmapImageRep(data: data) else { return nil }
    return PixelSize(width: image.pixelsWide, height: image.pixelsHigh)
}

private func testPasteboard() -> NSPasteboard { NSPasteboard(name: .init("SuperPasteSelfTest-\(UUID().uuidString)")) }

/// An in-memory `ItemStoring` with the parts ClipboardKit uses: insert (deduping on checksum), update, blobs, marks.
@MainActor
private final class FakeStore: ItemStoring {
    var byID: [UUID: ClipItem] = [:]
    var order: [UUID] = []
    var blobs: [String: Data] = [:]
    var used: [[UUID]] = []
    var updates = 0
    let subject = PassthroughSubject<StoreChange, Never>()

    var all: [ClipItem] { order.compactMap { byID[$0] } }

    func item(_ id: UUID) -> ClipItem? { byID[id] }
    func items(_ ids: [UUID]) -> [ClipItem] { ids.compactMap { byID[$0] } }
    func search(_ query: SearchQuery, in scope: ListScope, limit: Int, offset: Int) -> [ClipItem] { all }
    func count(_ query: SearchQuery, in scope: ListScope) -> Int { order.count }
    var apps: [AppRecord] { [] }
    var devices: [Device] { [] }

    func insert(_ draft: ClipDraft) throws -> InsertResult {
        let checksum = draft.checksum
        if var existing = byID.values.first(where: { $0.checksum == checksum }) {
            existing.copiedAt = draft.copiedAt
            existing.sourceApp = draft.sourceApp
            existing.device = draft.device
            byID[existing.id] = existing
            order.removeAll { $0 == existing.id }
            order.insert(existing.id, at: 0)
            subject.send(.updated([existing.id]))
            return InsertResult(item: existing, isNew: false)
        }
        let payload = draft.entries.map { PasteboardEntry(reps: $0.reps.map { PasteboardRep(type: $0.type, blob: save($0.data)) }) }
        let item = ClipItem(copiedAt: draft.copiedAt, kind: draft.kind, title: draft.title, text: draft.text,
                            sourceApp: draft.sourceApp, device: draft.device, byteSize: draft.byteSize, checksum: checksum,
                            payload: payload, imageSize: draft.imageSize, thumbnail: draft.thumbnail.map(save),
                            filePaths: draft.filePaths, link: draft.link)
        byID[item.id] = item
        order.insert(item.id, at: 0)
        subject.send(.inserted([item.id]))
        return InsertResult(item: item, isNew: true)
    }

    func update(_ item: ClipItem) throws {
        byID[item.id] = item
        updates += 1
        subject.send(.updated([item.id]))
    }

    func rename(_ id: UUID, to title: String?) throws {}
    func replaceContent(of id: UUID, with draft: ClipDraft) throws -> ClipItem { throw StoreError.itemNotFound(id) }
    func bump(_ id: UUID, at date: Date) throws {}
    func markUsed(_ ids: [UUID], at date: Date) throws { used.append(ids) }
    func delete(_ ids: [UUID]) throws {
        for id in ids { byID[id] = nil }
        order.removeAll { ids.contains($0) }
        subject.send(.deleted(ids))
    }
    var canUndoDelete: Bool { false }
    func undoLastDelete() throws -> [ClipItem] { [] }

    var pinboards: [Pinboard] { [] }
    func createPinboard(name: String, color: PinboardColor) throws -> Pinboard { throw StoreError.invalidName }
    func updatePinboard(_ pinboard: Pinboard) throws {}
    func deletePinboard(_ id: UUID) throws {}
    func reorderPinboards(_ ids: [UUID]) throws {}
    func assign(_ itemIDs: [UUID], to pinboardID: UUID) throws {}
    func unassign(_ itemIDs: [UUID], from pinboardID: UUID) throws {}
    func move(_ itemIDs: [UUID], in pinboardID: UUID, before beforeID: UUID?) throws {}

    func prunableCount(retentionDays: Int, now: Date) -> Int { 0 }
    func prune(retentionDays: Int, now: Date) throws -> Int { 0 }
    func eraseHistory() throws -> Int { 0 }
    func setRecognizedText(_ text: String, for id: UUID) throws {}

    func data(for blob: BlobRef) -> Data? { blobs[blob.digest] }
    func fileURL(for blob: BlobRef) -> URL? { nil }
    func saveBlob(_ data: Data) throws -> BlobRef { save(data) }
    var changes: AnyPublisher<StoreChange, Never> { subject.eraseToAnyPublisher() }

    @discardableResult func save(_ data: Data) -> BlobRef {
        let ref = BlobRef(of: data)
        blobs[ref.digest] = data
        return ref
    }

    /// A stored item made the way capture makes one.
    func add(_ entries: [EntryData], bundleID: String = "com.example.editor") -> ClipItem {
        let analysis = Classifier.analyze(entries, bundleID: bundleID)
        let draft = ClipDraft(entries: analysis.entries, kind: analysis.kind, text: analysis.text,
                              sourceApp: AppRecord(bundleID: bundleID, name: "App"), device: nil,
                              imageSize: analysis.imageSize, filePaths: analysis.filePaths, link: analysis.link)
        return try! insert(draft).item
    }
}

/// A `ClipboardEnvironment` of fakes that records what ClipboardKit asked for.
@MainActor
private final class Harness {
    let pasteboard = testPasteboard()
    let store = FakeStore()
    let ownBundleID = "org.superpaste.selftest"
    let editor = PasteTarget(bundleID: "com.example.editor", name: "Editor", processID: 4242)
    let other = PasteTarget(bundleID: "com.example.other", name: "Other", processID: 4343)
    lazy var frontmost: PasteTarget? = editor
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// Delayed work runs at once unless this is false; then it waits in `deferred` for `flush()`.
    var runDelayedWorkAtOnce = true
    var deferred: [@MainActor () -> Void] = []
    var sounds: [SoundEffect] = []
    var huds: [(title: String, symbol: String, subtitle: String?)] = []
    var beeps = 0
    var needsAccess = false
    var accessScreens = 0
    var linkPreview: LinkPreview?
    var linkFetches: [URL] = []
    var thumbnail: Data?
    var thumbnailRequests: [URL] = []
    var trusted = false
    var activationWorks = true
    var activations: [PasteTarget] = []
    /// What the pasteboard held each time ⌘V was posted, and whether the stack's ⌘V was registered then.
    var keystrokes: [(types: [[String]], text: String?, hotkeyRegistered: Bool)] = []
    var stripHides = 0
    var directPasteAnswer: DirectPasteChoice = .copyToClipboard
    var directPasteQuestions: [String?] = []
    var accessibilityScreens = 0
    var hotkeyAvailable = true
    var hotkeyHandler: (@MainActor () -> Void)?
    var hotkeyRegistrations = 0

    var environment: ClipboardEnvironment {
        ClipboardEnvironment(
            pasteboard: pasteboard, ownBundleID: ownBundleID, store: { self.store }, frontmostApp: { self.frontmost },
            appRecord: { AppRecord(bundleID: $0.bundleID, name: $0.name ?? $0.bundleID) }, now: { self.now },
            after: { _, work in self.runDelayedWorkAtOnce ? work() : self.deferred.append(work) },
            playSound: { self.sounds.append($0) }, showHUD: { self.huds.append(($0, $1, $2)) }, beep: { self.beeps += 1 },
            needsPasteboardAccess: { self.needsAccess }, showPasteboardAccess: { self.accessScreens += 1 },
            fetchLinkPreview: { url, done in self.linkFetches.append(url); done(self.linkPreview) },
            fileThumbnail: { url, done in self.thumbnailRequests.append(url); done(self.thumbnail) },
            isAccessibilityTrusted: { self.trusted },
            activate: { target in
                self.activations.append(target)
                if self.activationWorks { self.frontmost = target }
            },
            postPasteKeystroke: {
                self.keystrokes.append((PasteboardIO.types(on: self.pasteboard),
                                        self.pasteboard.string(forType: .string), self.hotkeyHandler != nil))
            },
            hideStrip: { self.stripHides += 1 },
            askDirectPaste: { name, done in self.directPasteQuestions.append(name); done(self.directPasteAnswer) },
            showAccessibilityAccess: { self.accessibilityScreens += 1 },
            registerStackHotkey: { handler in
                guard self.hotkeyAvailable else { return false }
                self.hotkeyRegistrations += 1
                self.hotkeyHandler = handler
                return true
            },
            unregisterStackHotkey: { self.hotkeyHandler = nil })
    }

    /// Another app copies `entries`.
    func copy(_ entries: [EntryData]) { PasteboardIO.write(entries, to: pasteboard) }

    func flush() {
        while !deferred.isEmpty { deferred.removeFirst()() }
    }

    func finish() { pasteboard.releaseGlobally() }
}

/// The throwaway pasteboard behind the services later cases see; released when the self-test exits.
nonisolated(unsafe) private var inertPasteboard: NSPasteboard?

/// Replaces the real services `install()` registered with ones that only touch a throwaway pasteboard and the
/// registered store, and do nothing else, so a later case pasting through `Services.pasting` can't reach the general
/// pasteboard, type ⌘V or take over ⌘V.
@MainActor
private func registerInertServices() {
    let h = Harness()
    var environment = h.environment
    environment.store = { Services.store }
    let monitor = ClipboardMonitor(environment: environment)
    Services.clipboard = monitor
    Services.pasting = Paster(environment: environment, monitor: monitor)
    inertPasteboard = h.pasteboard
    atexit { inertPasteboard?.releaseGlobally() }
}

/// Runs `body` and puts back every setting ClipboardKit's cases change.
@MainActor
private func withCleanSettings(_ body: () -> Void) {
    body()
    for key: Defaults.Key<Bool> in [.isDirectPasteEnabled, .isPasteAsPlainTextEnabled, .isDirectPastePromptSuppressed,
                                    .isSoundEffectsEnabled, .isLinkPreviewsEnabled, .isFileItemQLThumbnailImageEnabled] {
        Defaults.reset(key)
    }
    Defaults.reset(.ignoredPasteboardTypes)
    Defaults.reset(.ignoredBundleIdentifiers)
    Defaults.reset(.pasteStackDirection)
    Defaults.reset(.clipboardKitChangeToken)
}

// MARK: - Pure rules

private func clipboardIgnoredApps() {
    check(IgnoredApps.matches("com.1password.1password", entry: "com.1password"), "dotted prefix")
    check(IgnoredApps.matches("com.1password", entry: "com.1password"), "exact")
    check(!IgnoredApps.matches("com.1passwordx", entry: "com.1password"), "a longer name is not a dotted prefix")
    check(!IgnoredApps.matches("com", entry: "com.1password"), "a shorter name doesn't match")
    check(IgnoredApps.matches("com.nordsec.nordpass", entry: ".nordpass"), "leading dot: suffix")
    check(!IgnoredApps.matches("nordpass", entry: ".nordpass") && !IgnoredApps.matches("com.nordpassx", entry: ".nordpass"),
          "suffix needs the dot")
    check(IgnoredApps.matches("com.apple.passwords", entry: "com.apple.Passwords"), "case-insensitive")
    check(!IgnoredApps.matches("com.apple.Safari", entry: "") && !IgnoredApps.matches("com.apple.Safari", entry: "."),
          "empty entries match nothing")
    check(CaptureDefaults.ignoredApps.count == 14, "14 password managers by default")
    check(IgnoredApps.match("com.agilebits.onepassword7", in: CaptureDefaults.ignoredApps) == "com.agilebits.onepassword7",
          "default list lookup")
    check(IgnoredApps.match("com.apple.Safari", in: CaptureDefaults.ignoredApps) == nil, "Safari isn't ignored")
}

private func clipboardCaptureFilter() {
    let editor = PasteTarget(bundleID: "com.example.editor", name: "Editor", processID: 1)
    func decide(_ types: [[String]], itemID: String? = nil, source: String? = nil, frontmost: PasteTarget? = editor,
                ignoredTypes: [String] = CaptureDefaults.ignoredTypes) -> CaptureDecision {
        CaptureFilter.evaluate(types: types, itemIDMarker: itemID, sourceMarker: source, frontmost: frontmost,
                               ownBundleID: "org.superpaste.selftest", ignoredApps: CaptureDefaults.ignoredApps,
                               ignoredTypes: ignoredTypes)
    }
    check(decide([[utf8]]) == .capture(CaptureSource(bundleID: "com.example.editor", name: "Editor")), "a plain copy is captured")
    check(decide([]) == .noItems && decide([[]]) == .noItems, "no items")
    check(decide([[utf8]], frontmost: nil) == .noSource, "no frontmost app and no source marker")
    check(decide([[utf8, PasteboardType.source]], source: "com.example.writer") ==
          .capture(CaptureSource(bundleID: "com.example.writer", name: nil)), "org.nspasteboard.source names the source")
    check(decide([[utf8, PasteboardType.source]], source: "com.example.editor") ==
          .capture(CaptureSource(bundleID: "com.example.editor", name: "Editor")), "the marker's app keeps its running name")
    let id = UUID()
    check(decide([[utf8, PasteboardType.itemID]], itemID: id.uuidString) == .ownWrite(itemID: id), "self-marker with item id")
    check(decide([[utf8, PasteboardType.source]], source: "org.superpaste.selftest") == .ownWrite(itemID: nil),
          "own bundle id as source")
    for type in CaptureDefaults.ignoredTypes {
        check(decide([[utf8], [type]]) == .ignoredType(type), "ignored type \(type) in any item")
    }
    check(CaptureDefaults.ignoredTypes.count == 6, "six ignored types by default")
    let onePassword = PasteTarget(bundleID: "com.1password.1password", name: "1Password", processID: 2)
    check(decide([[utf8]], frontmost: onePassword) == .ignoredApp("com.1password.1password"), "frontmost password manager")
    check(decide([[utf8, PasteboardType.source]], source: "com.bitwarden.desktop") == .ignoredApp("com.bitwarden.desktop"),
          "password manager named by the source marker")
    check(decide([[utf8, PasteboardType.source]], source: "com.example.writer", frontmost: onePassword) ==
          .ignoredApp("com.1password.1password"), "a frontmost password manager is skipped whatever the marker says")
    // The privacy toggles edit the ignored types.
    MainActor.assumeIsolated {
        withCleanSettings {
            Defaults.ignoresTransientContent = false
            let types = Defaults[.ignoredPasteboardTypes]
            check(decide([[utf8, PasteboardType.transient]], ignoredTypes: types) != .ignoredType(PasteboardType.transient),
                  "transient content is captured once the toggle is off")
            check(decide([[utf8, PasteboardType.concealed]], ignoredTypes: types) == .ignoredType(PasteboardType.concealed),
                  "confidential content is still skipped")
        }
    }
}

private func clipboardQuirks() {
    check(QuirkRule.droppedTypes(for: nil) == PasteboardType.banned, "banned types for every app")
    let firefox = QuirkRule.droppedTypes(for: "org.mozilla.firefoxdeveloperedition")
    check(firefox.isSuperset(of: PasteboardType.banned) && firefox.contains(fileURLType) && firefox.contains(pngType),
          "Firefox Developer Edition drops its file URL and PNG")
    check(QuirkRule.droppedTypes(for: "org.mozilla.firefox") == PasteboardType.banned, "only the Developer Edition")
    check(QuirkRule.textTypes(for: "com.microsoft.excel") == [utf16Type, utf8], "Excel's text types, case-insensitively")
    check(QuirkRule.textTypes(for: "com.apple.Numbers").isEmpty, "no text quirk elsewhere")

    let cleaned = CapturePayload.clean([
        entry(rep(utf8, "a"), rep("com.microsoft.ole.source", "x"), rep(PasteboardType.itemID, "id"), rep(PasteboardType.source, "s"),
              rep(PasteboardType.remoteClipboard, "1"), RepData(type: htmlType, data: Data())),
        entry(rep("com.microsoft.DataObject", "x")),
    ], dropping: PasteboardType.banned)
    check(cleaned == [entry(rep(utf8, "a"))], "banned, volatile and empty representations go, then empty items")
    check(CapturePayload.clean([entry(RepData(type: utf8, data: Data()))], dropping: []).isEmpty, "an empty copy is empty")
    check(CapturePayload.isRemote(types: [[utf8], [PasteboardType.remoteClipboard]]) && !CapturePayload.isRemote(types: [[utf8]]),
          "Universal Clipboard marker")
}

private func clipboardClassify() {
    func analyze(_ entries: [EntryData], app: String? = "com.example.editor") -> CaptureAnalysis {
        Classifier.analyze(entries, bundleID: app)
    }
    let text = analyze([textEntry("hello")])
    check(text.kind == .text && text.text == "hello" && text.link == nil, "plain text")
    check(analyze([textEntry("  #ff8800 \n")]).kind == .color, "hex colour")
    check(analyze([textEntry("ff8800")]).kind == .color && analyze([textEntry("#ff880")]).kind == .text, "six hex digits only")

    let link = analyze([entry(rep(utf8, "https://example.com/a?b=1"), rep(PasteboardType.urlName, " Example "))])
    check(link.kind == .link && link.link == LinkMetadata(url: "https://example.com/a?b=1", title: "Example"),
          "a link takes its title from public.url-name")
    check(analyze([textEntry("www.example.com")]).link?.url == "https://www.example.com", "www. links get https")
    check(analyze([textEntry("see https://example.com")]).kind == .text, "text containing a link is text")

    let rich = analyze([entry(RepData(type: rtfType, data: rtfData("Bold")), rep(utf8, "Bold"))])
    check(rich.kind == .richText && rich.text == "Bold", "RTF first: rich text")
    let rtfOnly = analyze([entry(RepData(type: rtfType, data: rtfData("Only RTF")))])
    check(rtfOnly.kind == .richText && rtfOnly.text == "Only RTF", "text read from RTF")
    let html = analyze([entry(rep(htmlType, "<p>a &amp; b</p>"), rep(utf8, "a & b"))])
    check(html.kind == .html && html.text == "a & b", "HTML")
    let htmlOnly = analyze([entry(rep(htmlType, "<style>p{}</style><p>a &amp; b</p><p>c&#33; &#x41;</p>"))])
    check(htmlOnly.kind == .html && htmlOnly.text == "a & b\nc! A", "text read from HTML: \(htmlOnly.text)")
    check(analyze([entry(rep(utf8, "https://example.com"), RepData(type: rtfType, data: rtfData("https://example.com")))]).kind == .link,
          "a rich link is a link")

    let png = pngData(width: 40, height: 20)
    let image = analyze([entry(RepData(type: pngType, data: png))])
    check(image.kind == .image && image.imageSize == PixelSize(width: 40, height: 20) && image.text.isEmpty, "image with its size")
    check(pixelSize(of: image.thumbnail) == PixelSize(width: 40, height: 20), "small images keep their size in the thumbnail")
    let big = analyze([entry(RepData(type: pngType, data: pngData(width: 2000, height: 1000)))])
    check(pixelSize(of: big.thumbnail) == PixelSize(width: Classifier.thumbnailMaxPixels, height: Classifier.thumbnailMaxPixels / 2),
          "thumbnails are downscaled")
    check(analyze([entry(RepData(type: pngType, data: png), rep(utf8, "caption"))]).kind == .image, "image listed first: image")
    check(analyze([entry(rep(utf8, "cell"), RepData(type: pngType, data: png))]).kind == .text, "text listed first: text")
    check(analyze([entry(RepData(type: pngType, data: Data("not an image".utf8)), rep(utf8, "fallback"))]).kind == .text,
          "an image that doesn't decode falls back to the text")

    // Excel puts a picture of the cells first; its UTF-16 text is what counts.
    var utf16 = Data([0xFF, 0xFE]); utf16.append("Zelle ü".data(using: .utf16LittleEndian)!)
    let excel = analyze([entry(RepData(type: pngType, data: png), RepData(type: utf16Type, data: utf16), rep(utf8, "Zelle ?"))],
                        app: "com.microsoft.Excel")
    check(excel.kind == .text && excel.text == "Zelle ü", "Excel: text wins and comes from UTF-16")
    check(PayloadText.plainText(of: entry(RepData(type: utf16Type, data: "ohne BOM".data(using: .utf16LittleEndian)!))) == "ohne BOM",
          "UTF-16 without a byte order mark")
    check(PayloadText.plainText(of: textEntry("c string\0")) == "c string", "a C string terminator is dropped")

    let files = analyze([entry(rep(fileURLType, "file:///tmp/a%20b.txt"), rep(utf8, "a b.txt")),
                         entry(rep(fileURLType, "file:///tmp/c.txt"))])
    check(files.kind == .files && files.filePaths == ["/tmp/a b.txt", "/tmp/c.txt"] && files.text == "/tmp/a b.txt\n/tmp/c.txt",
          "file URLs make a files item with paths")
    check(analyze([entry(rep(fileURLType, "https://example.com/x"))]).kind != .files, "web URLs aren't files")

    check(analyze([entry(rep("com.example.private", "x"))]).kind == .unknown, "unknown data")
    let multi = analyze([textEntry("one"), textEntry("two")])
    check(multi.kind == .text && multi.text == "one\ntwo", "several text items join with newlines")
}

private func clipboardPasteContent() {
    MainActor.assumeIsolated {
        let store = FakeStore()
        let item = store.add([entry(rep(utf8, "a"), RepData(type: rtfType, data: rtfData("a"))), textEntry("b")])
        var withMarkers = item
        withMarkers.payload[0].reps += [PasteboardRep(type: "com.microsoft.ole.source", blob: store.save(Data("x".utf8))),
                                        PasteboardRep(type: PasteboardType.itemID, blob: store.save(Data("old".utf8)))]
        withMarkers.payload.append(PasteboardEntry(reps: [PasteboardRep(type: utf8, blob: BlobRef(of: Data("missing".utf8)))]))
        let loaded = PasteContent.entries(for: withMarkers) { store.data(for: $0) }
        check(loaded.count == 2 && loaded[0].reps.map(\.type) == [utf8, rtfType] && loaded[1] == textEntry("b"),
              "bytes loaded; banned, volatile and missing representations left out")

        let plain = PasteContent.plainText(loaded + [entry(RepData(type: rtfType, data: rtfData("rtf only"))),
                                                     entry(RepData(type: pngType, data: Data("png".utf8)))])
        check(plain == [textEntry("a"), textEntry("b"), textEntry("rtf only"), entry(RepData(type: pngType, data: Data("png".utf8)))],
              "plain text keeps only strings; items without text stay")

        let id = UUID()
        let marked = PasteContent.marked([entry(rep(utf8, "a"), rep(PasteboardType.source, "com.other")), textEntry("b")],
                                         itemID: id, sourceBundleID: "org.superpaste.selftest")
        check(marked[0].data(PasteboardType.itemID) == Data(id.uuidString.utf8)
              && marked[0].data(PasteboardType.source) == Data("org.superpaste.selftest".utf8)
              && marked[0].reps.filter { $0.type == PasteboardType.source }.count == 1 && marked[1] == textEntry("b"),
              "markers on the first item, replacing old ones")
        check(PasteContent.marked([], itemID: id, sourceBundleID: "x").isEmpty, "nothing to mark")
    }
}

private func clipboardMultiPaste() {
    MainActor.assumeIsolated {
        let store = FakeStore()
        let data: (BlobRef) -> Data? = { store.data(for: $0) }
        let a = store.add([textEntry("alpha")])
        let b = store.add([entry(RepData(type: rtfType, data: rtfData("beta")), rep(utf8, "beta"))])
        let link = store.add([textEntry("https://example.com")])
        let color = store.add([textEntry("#FFFFFF")])
        let image = store.add([entry(RepData(type: pngType, data: pngData(width: 4, height: 4)))])
        let file1 = store.add([entry(rep(fileURLType, "file:///tmp/one.txt"))])
        let file2 = store.add([entry(rep(fileURLType, "file:///tmp/two.txt"))])

        let one = PastePlan.steps(for: [a], plainText: false, data: data)
        check(one.count == 1 && one[0].entries == [textEntry("alpha")] && one[0].itemIDs == [a.id], "one item, as stored")

        let joined = PastePlan.steps(for: [a, b], plainText: false, data: data)
        check(joined.count == 1 && joined[0].itemIDs == [a.id, b.id], "texts join into one write")
        check(joined.first?.entries.first?.data(utf8) == Data("alpha\nbeta".utf8), "joined with a newline")
        let joinedRTF = joined.first?.entries.first?.data(rtfType).flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
        check(joinedRTF?.string == "alpha\nbeta", "formatting kept as RTF")
        let plainJoined = PastePlan.steps(for: [a, b], plainText: true, data: data)
        check(plainJoined.first?.entries == [textEntry("alpha\nbeta")], "plain text: only the joined string")
        check(PastePlan.steps(for: [a, a], plainText: false, data: data).first?.entries.first?.data(rtfType) == nil,
              "no RTF when nothing was rich")
        check(PastePlan.steps(for: [link, color], plainText: false, data: data).first?.entries == [textEntry("https://example.com\n#FFFFFF")],
              "links and colours join as text")

        let mixed = PastePlan.steps(for: [a, image, b], plainText: false, data: data)
        check(mixed.count == 3 && mixed.map(\.itemIDs) == [[a.id], [image.id], [b.id]], "mixed kinds paste one after another")
        let files = PastePlan.steps(for: [file1, file2], plainText: false, data: data)
        check(files.count == 1 && files[0].entries.count == 2, "files share one write")
        check(PastePlan.steps(for: [file1, a, file2], plainText: false, data: data).count == 3, "only consecutive files share")

        var gone = a
        gone.payload = [PasteboardEntry(reps: [PasteboardRep(type: utf8, blob: BlobRef(of: Data("gone".utf8)))])]
        check(PastePlan.steps(for: [gone], plainText: false, data: data).isEmpty, "items without bytes are skipped")
        check(PastePlan.steps(for: [gone, b], plainText: false, data: data).map(\.itemIDs) == [[b.id]], "the rest still pastes")
        let merged = PastePlan.merged(mixed)
        check(merged.entries.count == 3 && merged.itemIDs == [a.id, image.id, b.id], "merged: every item on one pasteboard")
    }
}

private func clipboardPasteStackEngine() {
    let a = ClipItem(kind: .text, text: "a"), b = ClipItem(kind: .text, text: "b"), c = ClipItem(kind: .text, text: "c")
    var engine = PasteStackEngine()
    engine.append(a)
    check(engine.state == PasteStackState(), "nothing is appended while closed")
    check(engine.popNext() == nil, "nothing to pop while closed")
    engine.start(direction: .top)
    [a, b, c].forEach { engine.append($0) }
    check(engine.state.isActive && engine.state.items.map(\.id) == [a.id, b.id, c.id], "copies append in order")
    check(engine.popNext()?.id == a.id, "top: the first copied comes first")
    engine.setDirection(.bottom)
    check(engine.popNext()?.id == c.id && engine.state.items.map(\.id) == [b.id], "bottom: the last copied comes first")
    engine.append(a); engine.append(b)
    check(engine.state.items.map(\.id) == [a.id, b.id], "a copy already in the stack moves to the end")
    engine.start(direction: .top)
    check(engine.state.items.count == 2 && engine.state.direction == .bottom, "starting again keeps the open stack")
    engine.remove([a.id])
    check(engine.state.items.map(\.id) == [b.id], "remove")
    var edited = b; edited.title = "Edited"
    engine.refresh { $0 == b.id ? edited : nil }
    check(engine.state.items == [edited], "refresh keeps current content")
    engine.refresh { _ in nil }
    check(engine.state.items.isEmpty && engine.popNext() == nil, "deleted items leave; an empty stack has nothing next")
    engine.append(a)
    engine.stop()
    check(!engine.state.isActive && engine.state.items.isEmpty && engine.state.direction == .bottom, "stop empties and closes")
}

@MainActor
private func clipboardAppRecords() {
    let store = FakeStore()
    let records = AppRecords(store: { store })
    let finder = records.record(for: CaptureSource(bundleID: "com.apple.finder", name: nil))
    check(finder.name == "Finder" && finder.colorHex == "#62A9F5", "Finder: name and built-in colour")
    check(finder.icon.flatMap { pixelSize(of: store.data(for: $0)) } == PixelSize(width: AppRecords.iconSide, height: AppRecords.iconSide),
          "the icon is stored as a PNG blob")
    store.blobs = [:]
    let again = records.record(for: CaptureSource(bundleID: "com.apple.finder", name: "Finder"))
    check(again == finder && again.icon.flatMap { store.data(for: $0) } != nil, "cached, and the icon saved again")
    let missing = records.record(for: CaptureSource(bundleID: "org.superpaste.selftest.missing", name: nil))
    check(missing == AppRecord(bundleID: "org.superpaste.selftest.missing", name: "org.superpaste.selftest.missing"),
          "an app that isn't installed: its bundle id, no colour, no icon")
}

private func clipboardPasteboardIO() {
    let pasteboard = testPasteboard()
    defer { pasteboard.releaseGlobally() }
    let entries = [entry(rep(utf8, "first"), rep(htmlType, "<b>first</b>"), rep(PasteboardType.source, "com.example.source")),
                   textEntry("second")]
    let count = PasteboardIO.write(entries, to: pasteboard)
    check(count == pasteboard.changeCount, "write returns the new change count")
    check(PasteboardIO.types(on: pasteboard).count == 2, "two items")
    check(PasteboardIO.marker(PasteboardType.source, on: pasteboard) == "com.example.source", "marker string")
    check(PasteboardIO.marker(PasteboardType.itemID, on: pasteboard) == nil, "missing marker")
    let read = PasteboardIO.read(from: pasteboard, skipping: [])
    check(read.count == 2 && read[0].data(utf8) == Data("first".utf8) && read[0].data(htmlType) == Data("<b>first</b>".utf8)
          && read[1].data(utf8) == Data("second".utf8), "every item and type read back")
    check(PasteboardIO.read(from: pasteboard, skipping: [htmlType])[0].data(htmlType) == nil, "skipped types aren't read")
    check(PasteboardIO.read(from: pasteboard, skipping: [], maxTypeSize: 5)[0].data(htmlType) == nil
          && PasteboardIO.read(from: pasteboard, skipping: [], maxTypeSize: 5)[0].data(utf8) != nil,
          "a type over the size limit is skipped")
    check(PasteboardIO.pasteboardItems(for: entries).first?.data(forType: .init(htmlType)) == Data("<b>first</b>".utf8),
          "pasteboard items for drag-out")
}

// MARK: - Monitor

@MainActor
private func clipboardMonitor() {
    withCleanSettings {
        let h = Harness()
        defer { h.finish() }
        let monitor = ClipboardMonitor(environment: h.environment)
        var published: [ClipItem] = []
        let subscription = monitor.captures.sink { published.append($0) }
        defer { subscription.cancel() }

        // Launch: the first launch takes nothing; a change made while Super Paste wasn't running is captured.
        h.copy([textEntry("before first launch")])
        Defaults.reset(.clipboardKitChangeToken)
        monitor.start()
        monitor.stop()
        check(h.store.order.isEmpty && Defaults[.clipboardKitChangeToken] == h.pasteboard.changeCount,
              "first launch: nothing captured, the change count remembered")
        monitor.start()
        monitor.stop()
        check(h.store.order.isEmpty, "unchanged since the last run: not captured again")
        h.copy([textEntry("copied while quit")])
        monitor.start()
        monitor.stop()
        check(h.store.all.map(\.text) == ["copied while quit"], "a copy made while not running is captured at launch")

        // A copy in another app.
        h.copy([entry(rep(utf8, "hello"), rep("com.microsoft.ole.source", "ole"))])
        monitor.poll()
        let hello = h.store.all.first
        check(hello?.text == "hello" && hello?.kind == .text, "captured after the settle delay")
        check(hello?.sourceApp == AppRecord(bundleID: "com.example.editor", name: "Editor") && hello?.device == .current,
              "source app and this Mac")
        check(hello?.payload.flatMap { $0.reps.map(\.type) } == [utf8], "banned types aren't stored")
        check(published.last?.id == hello?.id && h.sounds == [.copy, .copy], "published, with the copy sound")
        check(Defaults[.clipboardKitChangeToken] == h.pasteboard.changeCount, "the change count is persisted")
        monitor.poll()
        check(h.store.order.count == 2 && published.count == 2, "an unchanged pasteboard isn't read again")

        // The same content again moves the item to the front.
        h.copy([textEntry("hello")])
        monitor.poll()
        check(h.store.order.count == 2 && published.count == 3 && published.last?.id == hello?.id, "dedupe: moved to the front")

        // Changes during the settle delay restart it: only the settled content is read.
        h.runDelayedWorkAtOnce = false
        let publishedBefore = published.count
        h.copy([textEntry("partial")])
        monitor.poll()
        h.copy([textEntry("settled")])
        monitor.poll()
        check(published.count == publishedBefore, "nothing is read before the pasteboard settles")
        h.flush()
        h.runDelayedWorkAtOnce = true
        check(published.count == publishedBefore + 1 && h.store.all.first?.text == "settled"
              && !h.store.all.contains { $0.text == "partial" }, "debounced: read once, after the last change")

        // Super Paste's own writes are restores.
        let restored = h.store.order.count
        let own = PasteContent.marked([textEntry("hello")], itemID: hello?.id, sourceBundleID: h.ownBundleID)
        monitor.noteOwnWrite(changeCount: PasteboardIO.write(own, to: h.pasteboard))
        monitor.poll()
        h.copy(PasteContent.marked([textEntry("hello")], itemID: hello?.id, sourceBundleID: "com.other.superpaste"))
        monitor.poll()
        h.copy([entry(rep(utf8, "own"), rep(PasteboardType.source, h.ownBundleID))])
        monitor.poll()
        check(h.store.order.count == restored && h.store.all.first?.text == "settled", "own writes and self-marked content skipped")
        h.copy(PasteContent.marked([textEntry("from another Mac")], itemID: UUID(), sourceBundleID: h.ownBundleID))
        monitor.poll()
        check(h.store.all.first?.text == "from another Mac"
              && h.store.all.first?.payload.flatMap { $0.reps.map(\.type) } == [utf8],
              "marked for an item this Mac doesn't have: captured, markers not stored")

        // Filters.
        let before = h.store.order.count
        h.frontmost = PasteTarget(bundleID: "com.agilebits.onepassword7", name: "1Password", processID: 77)
        h.copy([textEntry("secret")])
        monitor.poll()
        h.frontmost = h.editor
        h.copy([entry(rep(utf8, "concealed"), rep(PasteboardType.concealed, ""))])
        monitor.poll()
        h.frontmost = nil
        h.copy([textEntry("nobody")])
        monitor.poll()
        h.frontmost = h.editor
        h.copy([entry(RepData(type: utf8, data: Data()))])
        monitor.poll()
        check(h.store.order.count == before, "ignored app, ignored type, unknown source and empty content aren't captured")

        // Universal Clipboard and the sound setting.
        Defaults[.isSoundEffectsEnabled] = false
        let soundsBefore = h.sounds.count
        h.copy([entry(rep(utf8, "from iPhone"), rep(PasteboardType.remoteClipboard, "1"))])
        monitor.poll()
        let remote = h.store.all.first
        check(remote?.text == "from iPhone" && remote?.device == nil
              && remote?.payload.flatMap { $0.reps.map(\.type) } == [utf8], "remote content: no device, marker not stored")
        check(h.sounds.count == soundsBefore, "no sound with Sound effects off")

        // Pasteboard privacy (macOS 26): asked once per launch.
        h.needsAccess = true
        monitor.start()
        h.copy([textEntry("after access check")])
        monitor.sync()
        monitor.stop()
        check(h.accessScreens == 1, "pasteboard access asked once")
    }
}

@MainActor
private func clipboardPause() {
    withCleanSettings {
        let h = Harness()
        defer { h.finish() }
        let monitor = ClipboardMonitor(environment: h.environment)
        var states: [PauseState] = []
        let subscription = monitor.pauseChanges.sink { states.append($0) }
        defer { subscription.cancel() }

        monitor.pause(until: nil)
        check(monitor.isPaused && monitor.pauseState == .paused(until: nil), "paused until resumed")
        check(h.huds.last?.title == "Super Paste Paused" && h.huds.last?.symbol == "pause", "Paused toast")
        h.copy([textEntry("while paused")])
        monitor.poll()
        check(h.store.order.isEmpty && Defaults[.clipboardKitChangeToken] == h.pasteboard.changeCount,
              "paused: nothing captured, the change still consumed")
        monitor.resume()
        monitor.poll()
        check(!monitor.isPaused && h.store.order.isEmpty, "resuming doesn't capture what was copied while paused")
        check(h.huds.last?.title == "Super Paste Resumed" && h.huds.last?.symbol == "arrow.clockwise", "Resumed toast")
        let toasts = h.huds.count
        monitor.resume()
        check(h.huds.count == toasts, "resuming while running does nothing")

        let until = h.now.addingTimeInterval(PauseDurations.all[0])
        monitor.pause(until: until)
        h.now = until.addingTimeInterval(-1)
        monitor.poll()
        check(monitor.pauseState == .paused(until: until), "still paused before the date")
        h.now = until
        monitor.poll()
        check(monitor.pauseState == .running, "resumed when the date passes")
        monitor.pause(until: h.now.addingTimeInterval(-5))
        check(monitor.pauseState == .running, "a date in the past doesn't pause")
        check(states == [.running, .paused(until: nil), .running, .paused(until: until), .running], "pause changes published")
    }
}

@MainActor
private func clipboardEnrichment() {
    withCleanSettings {
        let h = Harness()
        defer { h.finish() }
        let monitor = ClipboardMonitor(environment: h.environment)
        let icon = pngData(width: 8, height: 8)
        h.linkPreview = LinkPreview(title: "Fetched title", icon: icon, image: nil)

        h.copy([textEntry("https://example.com/page")])
        monitor.poll()
        var link = h.store.all.first?.link
        check(h.linkFetches == [URL(string: "https://example.com/page")!], "a new link is fetched")
        check(link?.title == "Fetched title" && link?.fetchedAt == h.now && link?.image == nil
              && link?.icon.flatMap { h.store.data(for: $0) } == icon, "preview saved on the item")
        h.copy([textEntry("https://example.com/page")])
        monitor.poll()
        check(h.linkFetches.count == 1, "an item that has its preview isn't fetched again")
        h.copy([entry(rep(utf8, "https://example.com/page"), rep(PasteboardType.urlName, "Pasteboard title"))])
        monitor.poll()
        link = h.store.all.first?.link
        check(h.linkFetches.count == 1 && link?.title == "Pasteboard title" && link?.fetchedAt != nil,
              "same URL: from the cache, the pasteboard's title kept")

        h.linkPreview = nil
        h.copy([textEntry("https://example.org")])
        monitor.poll()
        check(h.linkFetches.count == 2 && h.store.all.first?.link?.fetchedAt == nil, "a failed fetch leaves the link as it was")
        Defaults[.isLinkPreviewsEnabled] = false
        h.copy([textEntry("https://example.net")])
        monitor.poll()
        check(h.linkFetches.count == 2, "Generate Link Previews off: no fetch")

        h.thumbnail = pngData(width: 16, height: 16)
        h.copy([entry(rep(NSPasteboard.PasteboardType.fileURL.rawValue, "file:///tmp/selftest-thumb.txt"))])
        monitor.poll()
        let file = h.store.all.first
        check(h.thumbnailRequests == [URL(fileURLWithPath: "/tmp/selftest-thumb.txt")]
              && file?.thumbnail.flatMap { h.store.data(for: $0) } == h.thumbnail, "file thumbnail saved")
        Defaults[.isFileItemQLThumbnailImageEnabled] = false
        h.copy([entry(rep(NSPasteboard.PasteboardType.fileURL.rawValue, "file:///tmp/selftest-other.txt"))])
        monitor.poll()
        check(h.thumbnailRequests.count == 1 && h.store.all.first?.thumbnail == nil, "thumbnails off: none made")
    }
}

// MARK: - Pasting

@MainActor
private func clipboardPaste() {
    withCleanSettings {
        let h = Harness()
        defer { h.finish() }
        let monitor = ClipboardMonitor(environment: h.environment)
        let paster = Paster(environment: h.environment, monitor: monitor)
        let alpha = h.store.add([textEntry("alpha")])
        let beta = h.store.add([textEntry("beta")])
        let rich = h.store.add([entry(RepData(type: rtfType, data: rtfData("rich")), rep(utf8, "rich"))])
        let image = h.store.add([entry(RepData(type: pngType, data: pngData(width: 4, height: 4)))])
        let stored = h.store.order.count

        check(paster.target == h.editor, "the frontmost app at launch is the target")
        paster.noteActivation(PasteTarget(bundleID: h.ownBundleID, name: "Super Paste", processID: 1))
        paster.noteActivation(PasteTarget(bundleID: "x", name: "self", processID: getpid()))
        check(paster.target == h.editor, "Super Paste itself is never the target")

        // To clipboard.
        Defaults[.isDirectPasteEnabled] = false
        paster.paste([alpha], plainText: false)
        check(h.pasteboard.string(forType: .string) == "alpha", "written to the pasteboard")
        check(PasteboardIO.marker(PasteboardType.itemID, on: h.pasteboard) == alpha.id.uuidString
              && PasteboardIO.marker(PasteboardType.source, on: h.pasteboard) == h.ownBundleID, "with Super Paste's markers")
        check(h.huds.last?.title == "Copied" && h.huds.last?.subtitle == nil && h.keystrokes.isEmpty && h.stripHides == 1,
              "To clipboard: strip hidden, Copied, no keystroke")
        check(h.store.used.last == [alpha.id] && h.sounds.last == .paste, "marked used, paste sound")
        monitor.poll()
        check(h.store.order.count == stored, "the monitor sees a restore, not a copy")

        // Direct paste without Accessibility.
        Defaults[.isDirectPasteEnabled] = true
        paster.paste([beta], plainText: false)
        check(h.directPasteQuestions == ["Editor"] && h.pasteboard.string(forType: .string) == "beta" && h.keystrokes.isEmpty,
              "asks about direct paste to the target; content copied")
        check(h.huds.last?.title == "Copied" && h.huds.last?.subtitle == Paster.enableDirectPasteHint, "Copied with the hint")
        h.directPasteAnswer = .enableAccessibility
        let toasts = h.huds.count
        paster.paste([alpha], plainText: false)
        check(h.accessibilityScreens == 1 && h.huds.count == toasts, "Allow Accessibility Access opens the screen")
        h.directPasteAnswer = .copyToClipboardAndDontAskAgain
        paster.paste([alpha], plainText: false)
        check(Defaults[.isDirectPastePromptSuppressed], "Do not ask again is remembered")
        paster.paste([beta], plainText: false)
        check(h.directPasteQuestions.count == 3 && h.huds.last?.subtitle == Paster.enableDirectPasteHint, "not asked again")

        // Direct paste.
        h.trusted = true
        h.frontmost = h.other
        paster.paste([alpha], plainText: false)
        check(h.activations == [h.editor] && h.keystrokes.count == 1 && h.keystrokes.last?.text == "alpha",
              "brings the target forward, then ⌘V")
        h.frontmost = h.editor
        paster.paste([rich], plainText: false)
        check(h.activations.count == 1 && h.keystrokes.last?.types.first?.contains(rtfType) == true,
              "target already in front: straight to ⌘V, formatting kept")
        paster.paste([rich], plainText: true)
        check(h.keystrokes.last?.types.first?.contains(rtfType) == false && h.keystrokes.last?.text == "rich", "plain text")
        Defaults[.isPasteAsPlainTextEnabled] = true
        paster.paste([rich], plainText: false)
        check(h.keystrokes.last?.types.first?.contains(rtfType) == false, "Always paste as Plain Text")
        Defaults[.isPasteAsPlainTextEnabled] = false

        // Several items.
        let pressed = h.keystrokes.count
        paster.paste([alpha, beta], plainText: false)
        check(h.keystrokes.count == pressed + 1 && h.keystrokes.last?.text == "alpha\nbeta", "texts: one paste, joined")
        paster.paste([alpha, image, beta], plainText: false)
        let sequence = h.keystrokes.suffix(3)
        check(h.keystrokes.count == pressed + 4 && sequence.map(\.text) == ["alpha", nil, "beta"]
              && sequence.dropFirst().first?.types.first?.contains(pngType) == true, "mixed: one ⌘V per item, in order")

        // The target doesn't come forward: copied instead of typing into the wrong app.
        h.frontmost = h.other
        h.activationWorks = false
        let typed = h.keystrokes.count
        paster.paste([beta], plainText: false)
        check(h.keystrokes.count == typed && h.huds.last?.title == "Copied" && h.pasteboard.string(forType: .string) == "beta",
              "activation timeout copies")
        h.activationWorks = true
        h.frontmost = h.editor

        // A newer paste cancels a sequence still in progress.
        h.runDelayedWorkAtOnce = false
        paster.paste([alpha, image, beta], plainText: false)
        paster.paste([beta], plainText: false)
        h.flush()
        h.runDelayedWorkAtOnce = true
        check(h.keystrokes.suffix(2).map(\.text) == ["alpha", "beta"], "the old sequence stops after its first step")

        // Copy, writers, nothing to paste.
        let hides = h.stripHides, used = h.store.used.count
        paster.copy([rich], plainText: false)
        check(h.pasteboard.data(forType: .rtf) != nil && h.stripHides == hides && h.store.used.count == used + 1,
              "copy writes with formatting, leaves the strip")
        paster.copy([rich], plainText: true)
        check(h.pasteboard.data(forType: .rtf) == nil && h.pasteboard.string(forType: .string) == "rich", "copy as plain text")
        let writers = paster.pasteboardWriters(for: [alpha, image], plainText: false).compactMap { $0 as? NSPasteboardItem }
        check(writers.count == 2 && writers[0].string(forType: .init(PasteboardType.itemID)) == alpha.id.uuidString
              && writers[1].data(forType: .png) != nil, "drag-out writers carry the same content")
        var empty = alpha
        empty.payload = []
        paster.paste([empty], plainText: false)
        paster.copy([], plainText: false)
        check(h.beeps == 2, "nothing to paste beeps")

        paster.noteTermination(processID: h.editor.processID)
        check(paster.target == nil, "a quit target is forgotten")

        // No target ("current app"): ⌘V goes to whichever other app is in front, never into Super Paste.
        let activations = h.activations.count, pastes = h.keystrokes.count
        h.frontmost = PasteTarget(bundleID: h.ownBundleID, name: "Super Paste", processID: 99)
        paster.paste([alpha], plainText: false)
        check(h.keystrokes.count == pastes && h.huds.last?.title == "Copied", "Super Paste in front: copied instead")
        h.frontmost = h.other
        paster.paste([alpha], plainText: false)
        check(h.keystrokes.count == pastes + 1 && h.activations.count == activations, "another app in front: pasted there")
    }
}

@MainActor
private func clipboardPasteStack() {
    withCleanSettings {
        let h = Harness()
        defer { h.finish() }
        h.trusted = true
        let monitor = ClipboardMonitor(environment: h.environment)
        let paster = Paster(environment: h.environment, monitor: monitor)
        var states: [PasteStackState] = []
        let subscription = paster.pasteStackChanges.sink { states.append($0) }
        defer { subscription.cancel() }

        h.copy([textEntry("before")])
        monitor.poll()
        paster.startPasteStack()
        check(paster.isPasteStackActive && paster.pasteStack.items.isEmpty && h.hotkeyRegistrations == 1, "open, ⌘V taken")
        for text in ["one", "two", "three"] {
            h.copy([textEntry(text)])
            monitor.poll()
        }
        check(paster.pasteStack.items.map(\.text) == ["one", "two", "three"], "each copy is appended")

        h.hotkeyHandler?()
        check(h.keystrokes.last?.text == "one" && h.keystrokes.last?.hotkeyRegistered == false,
              "⌘V pastes the first copy, with the stack's ⌘V out of the way")
        check(h.hotkeyHandler != nil && h.hotkeyRegistrations == 2, "the stack's ⌘V comes back")
        monitor.poll()
        check(paster.pasteStack.items.map(\.text) == ["two", "three"], "the pasted snippet leaves; its write isn't appended")

        paster.setPasteStackDirection(.bottom)
        check(Defaults[.pasteStackDirection] == .bottom && paster.pasteStack.direction == .bottom, "direction saved")
        paster.pasteNextFromStack()
        check(h.keystrokes.last?.text == "three" && paster.pasteStack.items.map(\.text) == ["two"], "bottom: the last copy")

        try? h.store.delete([paster.pasteStack.items[0].id])
        check(paster.pasteStack.items.isEmpty, "deleted items leave the stack")
        let beeps = h.beeps
        h.hotkeyHandler?()
        check(h.beeps == beeps + 1 && paster.isPasteStackActive, "empty: beep, the stack stays open")

        h.copy([textEntry("four")])
        monitor.poll()
        paster.removeFromPasteStack(paster.pasteStack.items.map(\.id))
        check(paster.pasteStack.items.isEmpty, "remove")

        paster.togglePasteStack()
        check(!paster.isPasteStackActive && h.hotkeyHandler == nil, "closing releases ⌘V")
        h.copy([textEntry("five")])
        monitor.poll()
        paster.pasteNextFromStack()
        check(paster.pasteStack.items.isEmpty && h.keystrokes.last?.text == "three", "closed: nothing appended or pasted")
        check(states.first == PasteStackState() && states.last == PasteStackState(isActive: false, items: [], direction: .bottom),
              "state changes published")

        // Without Accessibility the snippet is copied (the same question as any paste).
        h.trusted = false
        h.hotkeyAvailable = false
        paster.startPasteStack()
        check(paster.isPasteStackActive && h.hotkeyHandler == nil, "open even when ⌘V is taken")
        h.copy([textEntry("six")])
        monitor.poll()
        paster.pasteNextFromStack()
        check(h.pasteboard.string(forType: .string) == "six" && h.directPasteQuestions.count == 1, "copied, asked")
        paster.stopPasteStack()
    }
}
