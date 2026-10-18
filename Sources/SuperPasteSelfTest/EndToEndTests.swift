import AppKit
import SuperPasteCore
import ClipStore
import ClipboardKit
import SyncKit
import MCPKit

// The modules wired together the way the app wires them, headless: real stores in temporary folders, the real monitor
// and paster on private named pasteboards (never the general one, no key events), real folder sync between two
// stores, and the real MCP server on a loopback port. Nothing is shown, played or sent off this Mac.
func registerEndToEndTests() {
    SelfTest.cases.append(("EndToEnd.copyToMCP", { MainActor.assumeIsolated { endToEnd() } }))
}

@MainActor
private final class EndToEndMac {
    let folder: URL
    let store: any ItemStoring & SyncStoring
    let sync: FolderSync
    let keys = MemorySyncKeyStore()

    init(_ name: String, root: URL) {
        folder = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = ClipStoreModule.makeStore(database: folder.appendingPathComponent("clips.sqlite"),
                                          blobs: folder.appendingPathComponent("Blobs", isDirectory: true),
                                          backup: folder.appendingPathComponent("Backup", isDirectory: true),
                                          retentionDays: { 30 })
        sync = FolderSync(store: store, syncStore: store, keyStore: keys, settings: MemorySyncSettings(),
                          stateDirectory: folder.appendingPathComponent("Sync", isDirectory: true),
                          device: Device(id: "e2e-\(name)", name: name), observesChanges: false)
    }

    func pass() { _ = awaitMain { await self.sync.syncAndWait() } }

    var history: [ClipItem] { store.search(.empty, in: .history, limit: 100, offset: 0) }
}

/// A ClipboardKit environment over `pasteboard` that never reaches outside the process: link previews and file
/// thumbnails answer nothing, sounds, toasts and permission screens are no-ops, ⌘V is never posted or registered.
@MainActor
private func environment(_ pasteboard: NSPasteboard, store: any ItemStoring, frontmost: PasteTarget,
                         now: @escaping () -> Date, keystrokes: @escaping () -> Void) -> ClipboardEnvironment {
    let records = AppRecords(store: { store })
    return ClipboardEnvironment(
        pasteboard: pasteboard, ownBundleID: SuperPastePaths.bundleID, store: { store }, frontmostApp: { frontmost },
        appRecord: { records.record(for: $0) }, now: now, after: { _, work in work() },
        playSound: { _ in }, showHUD: { _, _, _ in }, beep: {}, needsPasteboardAccess: { false }, showPasteboardAccess: {},
        fetchLinkPreview: { _, done in done(nil) }, fileThumbnail: { _, done in done(nil) },
        isAccessibilityTrusted: { false }, activate: { _ in }, postPasteKeystroke: keystrokes, hideStrip: { $0() },
        askDirectPaste: { _, done in done(.copyToClipboard) }, showAccessibilityAccess: {},
        registerStackHotkey: { _ in false }, unregisterStackHotkey: {})
}

private func pngData(side: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.systemTeal.setFill()
    NSRect(x: 0, y: 0, width: side, height: side).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

/// One JSON-RPC call to the MCP endpoint over loopback (URLSession, while the main run loop keeps turning so the
/// server can reach the store).
@MainActor
private func mcpCall(_ url: URL, token: String, session: String?, _ body: [String: Any]) -> (json: [String: Any]?, session: String?) {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    if let session { request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
    request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    var result: (Data?, HTTPURLResponse?)?
    let task = URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, _ in
        DispatchQueue.main.async { result = (data, response as? HTTPURLResponse) }
    }
    task.resume()
    let deadline = Date().addingTimeInterval(10)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    let json = result?.0.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    return (json, result?.1?.value(forHTTPHeaderField: "Mcp-Session-Id"))
}

@MainActor
private func endToEnd() {
    let root = scratchFolder("end-to-end")
    let source = NSPasteboard(name: .init("SuperPasteE2E-source-\(UUID().uuidString)"))
    let target = NSPasteboard(name: .init("SuperPasteE2E-target-\(UUID().uuidString)"))
    defer {
        source.releaseGlobally()
        target.releaseGlobally()
        try? FileManager.default.removeItem(at: root)
        for key: Defaults.Key<Bool> in [.isDirectPasteEnabled, .isSoundEffectsEnabled, .isLinkPreviewsEnabled] { Defaults.reset(key) }
        Defaults.reset(.clipboardKitChangeToken)
        Defaults.reset(.mcpPort)
    }
    Defaults[.isSoundEffectsEnabled] = false
    Defaults[.isLinkPreviewsEnabled] = false
    let a = EndToEndMac("A", root: root)
    let b = EndToEndMac("B", root: root)

    // 1. Copies in another app land in the store, with their kinds and source app.
    let textEdit = PasteTarget(bundleID: "com.apple.TextEdit", name: "TextEdit", processID: 1)
    var clock = Date().addingTimeInterval(-40 * 86_400)
    let monitor = ClipboardMonitor(environment: environment(source, store: a.store, frontmost: textEdit, now: { clock },
                                                            keystrokes: {}))
    Defaults.reset(.clipboardKitChangeToken)
    monitor.start()
    monitor.stop()
    func copy(_ write: (NSPasteboard) -> Void) {
        source.clearContents()
        write(source)
        monitor.poll()
        clock = clock.addingTimeInterval(1)
    }
    copy { _ = $0.setString("Forty days old, past Keep History", forType: .string) }
    clock = Date().addingTimeInterval(-60)
    let image = pngData(side: 24)
    let file = root.appendingPathComponent("Quarterly Report.txt")
    try? Data("report".utf8).write(to: file)
    copy { _ = $0.setString("Quarterly numbers look good", forType: .string) }
    copy { _ = $0.setData(image, forType: .png) }
    copy { _ = $0.writeObjects([file as NSURL]) }
    copy { _ = $0.writeObjects([URL(string: "https://example.com/super-paste")! as NSURL]) }
    copy { _ = $0.setString("#3366FF", forType: .string) }
    let captured = a.history
    checkNow(captured.map(\.kind.typeFilter) == [.color, .link, .file, .image, .text, .text],
             "kinds, newest first: \(captured.map(\.kind.rawValue))")
    checkNow(captured.allSatisfy { $0.sourceApp?.bundleID == "com.apple.TextEdit" && $0.sourceApp?.name == "TextEdit" },
             "every copy is from TextEdit")
    checkNow(captured.allSatisfy { $0.device == .current }, "and from this Mac")
    guard captured.count == 6 else { return }
    let (color, link, files, picture, text, old) = (captured[0], captured[1], captured[2], captured[3], captured[4], captured[5])
    checkNow(files.filePaths == [file.path] && link.text == "https://example.com/super-paste" && color.text == "#3366FF",
             "file path, link and colour text")
    checkNow(picture.imageSize == PixelSize(width: 24, height: 24), "image size")

    // 2. Search finds them.
    func search(_ query: String, _ scope: ListScope = .history) -> [UUID] {
        a.store.search(SearchQuery(parsing: query), in: scope, limit: 100, offset: 0).map(\.id)
    }
    checkNow(search("numbers") == [text.id], "a word finds the text")
    checkNow(search("type:image") == [picture.id] && search("type:link") == [link.id] && search("type:color") == [color.id],
             "type filters")
    checkNow(search("app:TextEdit").count == 6, "app filter")

    // 3. Pasting writes each item's stored representations to another pasteboard; no key event (direct paste off).
    Defaults[.isDirectPasteEnabled] = false
    var keystrokes = 0
    let pasteEnvironment = environment(target, store: a.store, frontmost: textEdit, now: { Date() }, keystrokes: { keystrokes += 1 })
    let paster = Paster(environment: pasteEnvironment, monitor: ClipboardMonitor(environment: pasteEnvironment))
    for item in [text, picture, files, link, color] {
        paster.paste([item], plainText: false)
        let written = target.pasteboardItems?.first
        let stored = item.payload.first?.reps ?? []
        let same = !stored.isEmpty && stored.allSatisfy { rep in
            written?.data(forType: .init(rep.type)) == a.store.data(for: rep.blob)
        }
        checkNow(same, "\(item.kind.rawValue): every stored representation written back (\(stored.map(\.type)))")
        checkNow(written?.string(forType: .init(PasteboardType.itemID)) == item.id.uuidString
                 && written?.string(forType: .init(PasteboardType.source)) == SuperPastePaths.bundleID, "with Super Paste's markers")
    }
    checkNow(keystrokes == 0, "no keystroke posted")
    checkNow(source.string(forType: .string) == "#3366FF", "the copy pasteboard is untouched")

    // 4. Pinboards.
    guard let board = try? a.store.createPinboard(name: "Work", color: .blue) else { return checkNow(false, "pinboard") }
    try? a.store.assign([text.id, picture.id], to: board.id)
    checkNow(Set(search("", .pinboard(board.id))) == [text.id, picture.id], "assigned to the pinboard")
    try? a.store.unassign([picture.id], from: board.id)
    checkNow(search("", .pinboard(board.id)) == [text.id] && a.store.item(picture.id)?.isPinned == false, "unassigned")
    checkNow(a.history.first?.id == picture.id, "an unpinned item goes back to the front of the history")

    // 5. Keep History: the copy from forty days ago goes, the rest stays.
    checkNow((try? a.store.prune(retentionDays: 30, now: Date())) == 1 && a.store.item(old.id) == nil, "pruned past 30 days")
    let kept = a.history.map(\.id)
    checkNow(kept == [picture.id, color.id, link.id, files.id, text.id], "the rest stays")

    // 6. Sync to a second Mac's store through a shared folder, and an edit back.
    let shared = root.appendingPathComponent("Shared", isDirectory: true)
    checkNow((try? a.sync.enable(folder: shared)) != nil, "A turns sync on")
    a.pass()
    checkNow((try? b.sync.importKey(a.sync.exportKey() ?? "")) != nil && (try? b.sync.enable(folder: shared)) != nil, "B joins")
    b.pass()
    checkNow(b.history.map(\.id) == kept && b.history.map(\.kind) == a.history.map(\.kind), "B has A's history, in order")
    checkNow(b.store.item(text.id)?.isPinned(to: board.id) == true && b.store.pinboards.map(\.name) == ["Work"], "and the pinboard")
    checkNow(picture.payload.first?.reps.first.flatMap { b.store.data(for: $0.blob) } == image, "and the image bytes")
    try? b.store.rename(link.id, to: "Project page")
    b.pass()
    a.pass()
    checkNow(a.store.item(link.id)?.title == "Project page", "a rename on B reaches A")
    a.sync.disable()
    b.sync.disable()

    // 7. An MCP client lists the items over loopback.
    Defaults[.mcpPort] = 0
    let server = MCPServer(store: b.store, directory: root.appendingPathComponent("MCP", isDirectory: true))
    server.start()
    defer { server.stop() }
    let deadline = Date().addingTimeInterval(5)
    while !server.isRunning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    guard case .running(let url) = server.state, let (_, token) = try? server.addTokenClient(name: "End to end") else {
        return checkNow(false, "MCP server running: \(server.state)")
    }
    let opened = mcpCall(url, token: token, session: nil, [
        "jsonrpc": "2.0", "id": 1, "method": "initialize",
        "params": ["protocolVersion": "2025-03-26", "capabilities": [String: Any](), "clientInfo": ["name": "e2e", "version": "1"]],
    ])
    checkNow(opened.session != nil, "MCP session opened")
    let listed = mcpCall(url, token: token, session: opened.session, [
        "jsonrpc": "2.0", "id": 2, "method": "tools/call", "params": ["name": "search", "arguments": ["limit": 100]],
    ])
    let result = listed.json?["result"] as? [String: Any]
    let items = (result?["structuredContent"] as? [String: Any])?["items"] as? [[String: Any]] ?? []
    checkNow(items.compactMap { $0["id"] as? String } == kept.map(\.uuidString), "search lists every item, newest first")
    checkNow(items.compactMap { $0["type"] as? String } == ["image", "color", "link", "file", "text"]
             && items.allSatisfy { $0["app"] as? String == "TextEdit" }, "with types and app")
}
