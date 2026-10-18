import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import SuperPasteCore
import MCPKit

// Owned by MCPKit.
func registerMCPKitTests() {
    SelfTest.cases.append(("MCPKit.install", { MainActor.assumeIsolated {
        MCPKitModule.install()
        checkNow(Services.mcp != nil, "MCP server registered")
        checkNow(Services.mcp.state == .off && !Defaults[.isMCPEnabled], "off by default")
    } }))
    SelfTest.cases.append(("MCPKit.httpParser", { mcpHTTPParser() }))
    SelfTest.cases.append(("MCPKit.secretsAndPKCE", { mcpSecretsAndPKCE() }))
    SelfTest.cases.append(("MCPKit.tools", { MainActor.assumeIsolated { mcpTools() } }))
    SelfTest.cases.append(("MCPKit.server", { MainActor.assumeIsolated { mcpServer() } }))
    SelfTest.cases.append(("MCPKit.stdioBridge", { MainActor.assumeIsolated { mcpBridge() } }))
}

// MARK: - HTTP parsing

private func parse(_ text: String, limit: Int = 1_024) -> HTTPParser.Outcome {
    HTTPParser.parse(Data(text.utf8), maxBody: { _ in limit })
}

private func status(_ outcome: HTTPParser.Outcome) -> Int? {
    if case .failure(let status) = outcome { return status }
    return nil
}

private func mcpHTTPParser() {
    if case .request(let r, let used) = parse("GET /authorize?client_id=a%20b&x=1 HTTP/1.1\r\nHost: 127.0.0.1:1\r\nX-A: 1\r\nx-a: 2\r\n\r\nGET") {
        check(r.method == "GET" && r.path == "/authorize" && r.query["client_id"] == "a b", "request line and query")
        check(r.header("HOST") == "127.0.0.1:1" && r.header("x-a") == "1, 2", "headers are case-insensitive, repeats join")
        check(used == 82 && !r.wantsClose, "consumed only the first request; keep-alive by default")
    } else { check(false, "simple GET parses") }
    if case .request(let r, _) = parse("POST /token HTTP/1.1\r\nHost: h\r\nContent-Length: 27\r\nConnection: close\r\n\r\ncode=a%2Bb&state=x+y&code=z") {
        check(r.form == ["code": "a+b", "state": "x y"] && r.wantsClose, "form body: %2B, + as space, first value wins")
    } else { check(false, "POST with a body parses") }
    if case .request(let r, _) = parse("POST /mcp HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n4\r\n{\"a\"\r\n3;x=y\r\n:1}\r\n0\r\n\r\n") {
        check(String(decoding: r.body, as: UTF8.self) == "{\"a\":1}", "chunked body")
    } else { check(false, "chunked parses") }
    if case .needMore = parse("POST /mcp HTTP/1.1\r\nHost: h\r\nContent-Length: 10\r\n\r\n12345") {} else { check(false, "partial body waits") }
    if case .needMore = parse("GET / HTTP/1.1\r\nHost:") {} else { check(false, "partial head waits") }
    check(status(parse("POST /mcp HTTP/1.1\r\nHost: h\r\nContent-Length: 2000\r\n\r\n")) == 413, "body over the limit")
    check(status(parse("POST /mcp HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n800\r\n")) == 413, "chunked body over the limit")
    check(status(parse("GET / HTTP/1.1\r\nHost: h\r\nX: " + String(repeating: "a", count: 20_000))) == 431, "header block too large")
    check(status(parse("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\nab")) == 400, "repeated Content-Length")
    check(status(parse("POST / HTTP/1.1\r\nHost: h\r\nContent-Length: 1\r\nTransfer-Encoding: chunked\r\n\r\n")) == 400, "length and chunked together")
    check(status(parse("GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n")) == 400, "repeated Host")
    check(status(parse("GET http://evil.com/ HTTP/1.1\r\nHost: h\r\n\r\n")) == 400, "absolute-form target")
    check(status(parse("GET / HTTP/2.0\r\nHost: h\r\n\r\n")) == 505, "unsupported version")
    check(status(parse("GET / HTTP/1.1\r\n\r\n")) == 400, "HTTP/1.1 without Host")
    check(status(parse("GET / HTTP/1.1\r\nHost: h\r\n folded\r\n\r\n")) == 400, "obsolete line folding")
}

// MARK: - Secrets, PKCE, redirect URIs

private func mcpSecretsAndPKCE() {
    // Vectors computed independently (Python hashlib).
    check(MCPSecrets.hash("spm_example-token") == "2844bd0805eef77344b2ed1417be05eb4e5c6c01e86bc30a8b2966bb736873af", "token hash is SHA-256 hex")
    let a = MCPSecrets.generate(), b = MCPSecrets.generate()
    check(a.hasPrefix("spm_") && a.count == 47 && a != b, "tokens: prefix and 256 random bits")
    check(MCPSecrets.hash(a) != a && MCPSecrets.hash(a) != MCPSecrets.hash(b) && MCPSecrets.hash(a).count == 64, "hashes")
    check(MCPSecrets.constantTimeEquals("abc", "abc") && !MCPSecrets.constantTimeEquals("abc", "abd")
          && !MCPSecrets.constantTimeEquals("abc", "abcd"), "constant-time comparison")

    let verifier = "superpaste-pkce-test-verifier-0123456789_abcdef~ghij.k"
    let challenge = "32sTcKTbYoKEY9n6JbpN4hE5NYg8wDCJ3GWBZf3zxxg"
    check(PKCE.challenge(for: verifier) == challenge, "S256 challenge")
    check(PKCE.verify(verifier: verifier, challenge: challenge), "matching verifier")
    check(!PKCE.verify(verifier: verifier + "x", challenge: challenge), "another verifier")
    check(!PKCE.isValidVerifier("short") && !PKCE.isValidVerifier(String(repeating: "a", count: 129))
          && !PKCE.isValidVerifier(String(repeating: "a", count: 42) + " ") && PKCE.isValidVerifier(String(repeating: "a", count: 43)),
          "verifier length and characters")
    check(PKCE.isValidChallenge(challenge) && !PKCE.isValidChallenge("plain-text-challenge"), "challenge shape")

    for ok in ["https://app.example.com/callback", "http://127.0.0.1:33418/", "http://localhost:6274/oauth/callback",
               "http://[::1]:8080/cb", "editorapp://oauth/callback", "com.example.app:/oauth"] {
        check(RedirectPolicy.isAllowed(ok), "allowed redirect \(ok)")
    }
    for bad in ["http://example.com/cb", "http://127.0.0.1.evil.com/cb", "javascript:alert(1)", "data:text/html,hi",
                "file:///etc/passwd", "https://app.example.com/cb#frag", "https:///nohost", "not a url", "https://a.com/\n"] {
        check(!RedirectPolicy.isAllowed(bad), "refused redirect \(bad)")
    }
}

// MARK: - Tools

/// A PNG of the given size (an opaque gradient-free fill is enough).
private func pngData(width: Int, height: Int) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.5)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return output as Data
}

@MainActor
private func mcpTools() {
    let store = MemoryClipStore()
    let tools = MCPToolbox(store: store)
    func call(_ name: String, _ args: [String: JSON] = [:]) -> Result<MCPToolbox.Output, MCPToolbox.ToolError> {
        do { return .success(try tools.call(name, arguments: args)) } catch let error as MCPToolbox.ToolError {
            return .failure(error)
        } catch { return .failure(.failed("\(error)")) }
    }
    func value(_ name: String, _ args: [String: JSON] = [:]) -> JSON? { try? call(name, args).get().structured }
    func message(_ name: String, _ args: [String: JSON] = [:]) -> String? {
        if case .failure(let error) = call(name, args) { return error.message }
        return nil
    }

    let mail = AppRecord(bundleID: "com.apple.mail", name: "Mail")
    let text = try! store.insert(.text("Quarterly report draft", sourceApp: mail)).item
    let link = try! store.insert(.text("https://example.com/docs")).item
    let color = try! store.insert(.text("#ff8800")).item
    let png = pngData(width: 2048, height: 1024)
    let image = try! store.insert(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: png)])], kind: .image,
                                            imageSize: PixelSize(width: 2048, height: 1024))).item
    let files = try! store.insert(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.file-url", data: Data("file:///a".utf8))])],
                                            kind: .files, filePaths: ["/Users/me/a.txt", "/Users/me/b b.pdf"])).item
    let long = String(repeating: "x", count: MCPToolbox.readTextLimit + 5)
    let longItem = try! store.insert(.text(long)).item

    // search
    let all = value("search")
    let items = all?["items"]?.array ?? []
    checkNow(items.count == 6 && all?["hasMore"] == false, "no arguments: everything recent")
    checkNow(items.first?["id"]?.string == longItem.id.uuidString, "newest first")
    let summary = items.first { $0["id"]?.string == text.id.uuidString }
    checkNow(summary?["type"] == "text" && summary?["preview"] == "Quarterly report draft" && summary?["app"] == "Mail"
             && summary?["timestamp"]?.string?.hasSuffix("Z") == true && summary?["device"] != nil, "MCPItem shape")
    checkNow(Set(summary?.object?.keys.map { $0 } ?? []).isSubset(of: ["id", "type", "preview", "timestamp", "app", "device"]),
             "no extra fields")
    checkNow(value("search", ["type": "link"])?["items"]?.array?.map { $0["id"] } == [.string(link.id.uuidString)], "type filter")
    checkNow(value("search", ["query": "quarterly"])?["items"]?.array?.count == 1, "free text")
    checkNow(value("search", ["app": "Mail"])?["items"]?.array?.count == 1, "app filter")
    let limited = value("search", ["limit": 2])
    checkNow(limited?["items"]?.array?.count == 2 && limited?["hasMore"] == true, "limit and hasMore")
    checkNow(value("search", ["limit": 500])?["items"]?.array?.count == 6, "limit is capped, not refused")
    checkNow(message("search", ["type": "video"])?.hasPrefix("Invalid arguments:") == true, "unknown type")
    checkNow(message("search", ["limit": "ten"]) == "Invalid arguments: `limit` must be an integer.", "wrong argument type")
    checkNow(message("search", ["colour": "red"]) == "Invalid arguments: unknown argument `colour`.", "unknown argument")
    checkNow(message("search", ["pinboard_id": "nope"]) == "No pinboard found with id nope. Use list_pinboards to see valid ids.",
             "unknown pinboard")
    checkNow(message("search", ["date_from": "yesterday"]) == "`date_from` must be an ISO-8601 date or date-time: yesterday", "bad date")
    checkNow(message("search", ["date_from": "2026-05-02", "date_to": "2026-05-01"]) == "`date_from` must be before `date_to`.",
             "reversed range")
    checkNow(value("search", ["date_from": "2000-01-01", "date_to": "2000-01-01"])?["items"]?.array?.isEmpty == true,
             "a date-only range covers that day (nothing then)")
    let day = DateFormatter()
    day.dateFormat = "yyyy-MM-dd"
    checkNow(value("search", ["date_from": .string(day.string(from: Date()))])?["items"]?.array?.count == 6, "from the start of today")
    checkNow(value("search", ["date_to": "2000-01-01T00:00:00Z"])?["items"]?.array?.isEmpty == true, "date-time upper bound")

    // read_item
    checkNow(value("read_item", ["id": .string(text.id.uuidString)])?["text"] == "Quarterly report draft", "text verbatim")
    let longRead = value("read_item", ["id": .string(longItem.id.uuidString.lowercased())])
    checkNow(longRead?["truncated"] == true && longRead?["totalLength"]?.int == long.count
             && longRead?["text"]?.string?.count == MCPToolbox.readTextLimit, "long text is cut, with its length")
    checkNow(value("read_item", ["id": .string(link.id.uuidString)])?["url"] == "https://example.com/docs", "link URL")
    checkNow(value("read_item", ["id": .string(color.id.uuidString)])?["color"] == "#FF8800", "colour as #RRGGBB")
    if case .success(let out) = call("read_item", ["id": .string(files.id.uuidString)]) {
        checkNow(out.content.first?["text"] == "/Users/me/a.txt\n/Users/me/b b.pdf", "file paths one per line")
    } else { checkNow(false, "files read") }
    if case .success(let out) = call("read_item", ["id": .string(image.id.uuidString)]),
       let block = out.content.first, block["type"] == "image",
       let data = block["data"]?.string.flatMap({ Data(base64Encoded: $0) }),
       let source = CGImageSourceCreateWithData(data as CFData, nil),
       let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        checkNow(w == 1024 && h == 512 && block["mimeType"] == "image/png", "image downscaled to 1024 px, PNG with alpha (\(w)×\(h))")
    } else { checkNow(false, "image read") }
    checkNow(message("read_item", ["id": "missing"]) == "No clipboard item found with id missing. Use search to find valid item ids.",
             "unknown item")
    checkNow(message("read_item") == "Invalid arguments: `id` is required.", "missing id")

    // create_item
    let created = value("create_item", ["content": "#00FF00"])
    checkNow(created?["type"] == "color" && created?["timestamp"] != nil, "colour detected, in history")
    checkNow(value("create_item", ["content": "https://swift.org"])?["type"] == "link", "link detected")
    checkNow(message("create_item", ["content": "   "]) == "`content` cannot be empty.", "empty content")
    let board = value("create_pinboard", ["name": "  Work  "])
    let boardID = board?["id"] ?? .null
    checkNow(board?["name"] == "Work" && board?["itemCount"] == 0, "pinboard created, name trimmed")
    checkNow(message("create_pinboard", ["name": " "]) == "`name` cannot be empty.", "empty pinboard name")
    let pinnedOnly = value("create_item", ["content": "Only in Work", "list_id": boardID])
    checkNow(pinnedOnly?["timestamp"] == nil, "pinned-only item has no timestamp")
    let reused = value("create_item", ["content": "Quarterly report draft", "list_id": boardID])
    checkNow(reused?["id"]?.string == text.id.uuidString && reused?["timestamp"] != nil, "existing history item pinned, not duplicated")
    checkNow(message("create_item", ["content": "x", "list_id": "nope"])?.hasPrefix("No pinboard found") == true, "unknown list_id")

    // update_item
    checkNow(value("update_item", ["id": .string(text.id.uuidString), "title": "Report"])?["preview"] == "Report — Quarterly report draft",
             "title set")
    checkNow(store.item(text.id)?.title == "Report", "title stored")
    _ = value("update_item", ["id": .string(text.id.uuidString), "title": ""])
    checkNow(store.item(text.id)?.title == nil, "empty title clears")
    checkNow(value("update_item", ["id": .string(text.id.uuidString), "content": "#123456"])?["type"] == "color", "content re-detects the type")
    checkNow(message("update_item", ["id": .string(image.id.uuidString), "content": "x"])
             == "Cannot edit the content of an image or file item. You can still change its title.", "image content refused")
    checkNow(value("update_item", ["id": .string(image.id.uuidString), "title": "Screenshot"]) != nil, "image title allowed")
    checkNow(message("update_item", ["id": .string(text.id.uuidString)]) == "Pass at least one of `title` or `content` to update.",
             "nothing to update")

    // pinboards
    checkNow(value("add_item_to_pinboard", ["item_id": .string(link.id.uuidString), "pinboard_id": boardID])?["itemCount"] == 3,
             "add returns the updated pinboard")
    checkNow(value("add_item_to_pinboard", ["item_id": .string(link.id.uuidString), "pinboard_id": boardID])?["itemCount"] == 3,
             "adding twice is idempotent")
    checkNow(value("remove_item_from_pinboard", ["item_id": .string(link.id.uuidString), "pinboard_id": boardID])?["itemCount"] == 2,
             "remove")
    checkNow(value("search", ["pinboard_id": boardID])?["items"]?.array?.count == 2, "search within a pinboard")
    checkNow(value("rename_pinboard", ["id": boardID, "name": "Projects"])?["name"] == "Projects", "rename")
    checkNow(value("list_pinboards")?["pinboards"]?.array?.map { $0["name"] } == ["Projects"], "list")
    let preview = value("delete_pinboard", ["id": boardID])
    checkNow(preview?["deleted"] == false && store.pinboards.count == 1
             && preview?["message"]?.string?.hasPrefix("Preview — would delete pinboard \"Projects\" (2 items).") == true,
             "delete_pinboard previews first")
    checkNow(value("delete_pinboard", ["id": boardID, "confirm": true])?["message"] == "Deleted pinboard \"Projects\".", "then deletes")
    checkNow(store.pinboards.isEmpty && store.item(text.id) != nil, "pinned history items stay")

    // delete_item
    let doomed = value("delete_item", ["id": .string(color.id.uuidString)])
    checkNow(doomed?["deleted"] == false && store.item(color.id) != nil, "delete_item previews first")
    checkNow(value("delete_item", ["id": .string(color.id.uuidString), "confirm": true])?["message"] == "Deleted item."
             && store.item(color.id) == nil, "then deletes")

    if case .failure(let error) = call("paste_everything") { checkNow(error == .unknownTool("paste_everything"), "unknown tool") }
}

// MARK: - Server

/// A raw HTTP exchange over a blocking socket, run off the main thread while the main run loop keeps turning (the
/// server answers on the main actor). Every request asks the server to close the connection afterwards.
private struct RawResponse {
    var status: Int
    var headers: [String: String]
    var body: Data
    var text: String { String(decoding: body, as: UTF8.self) }
    var json: JSON? { try? JSON(parsing: body) }
}

@MainActor
private func raw(_ port: Int, _ request: String, body: Data = Data(), readFor seconds: Double = 5,
                 halfClose: Bool = false) -> RawResponse? {
    var result: RawResponse??
    let payload = Data(request.utf8) + body
    DispatchQueue.global().async {
        let response = rawExchange(port: port, payload: payload, seconds: seconds, halfClose: halfClose)
        DispatchQueue.main.async { result = .some(response) }
    }
    let deadline = Date().addingTimeInterval(seconds + 5)
    while result == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    return result ?? nil
}

private func rawExchange(port: Int, payload: Data, seconds: Double, halfClose: Bool) -> RawResponse? {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var on: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))  // the server may close first
    var timeout = timeval(tv_sec: 0, tv_usec: 300_000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(port).bigEndian
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
    }
    guard connected == 0 else { return nil }
    _ = payload.withUnsafeBytes { send(fd, $0.baseAddress, payload.count, 0) }
    if halfClose { shutdown(fd, SHUT_WR) }
    var received = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        let n = recv(fd, &buffer, buffer.count, 0)
        if n > 0 { received.append(contentsOf: buffer[0..<n]) } else if n == 0 { break }
        if let response = parseResponse(received), response.complete { return response.value }
    }
    return parseResponse(received)?.value
}

private func parseResponse(_ data: Data) -> (value: RawResponse, complete: Bool)? {
    guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
    let status = Int(head[0].split(separator: " ").dropFirst().first ?? "") ?? 0
    var headers: [String: String] = [:]
    for line in head.dropFirst() {
        guard let colon = line.firstIndex(of: ":") else { continue }
        headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    let body = Data(data[end.upperBound...])
    let complete = headers["content-length"].flatMap(Int.init).map { body.count >= $0 } ?? false
    return (RawResponse(status: status, headers: headers, body: body), complete)
}

/// Builds a request with `Connection: close`.
private func request(_ method: String, _ path: String, port: Int, host: String? = nil, headers: [(String, String)] = [],
                     body: Data = Data()) -> String {
    var lines = ["\(method) \(path) HTTP/1.1"]
    if let host { if !host.isEmpty { lines.append("Host: \(host)") } } else { lines.append("Host: 127.0.0.1:\(port)") }
    lines += headers.map { "\($0.0): \($0.1)" }
    if !body.isEmpty || method == "POST" { lines.append("Content-Length: \(body.count)") }
    lines.append("Connection: close")
    return lines.joined(separator: "\r\n") + "\r\n\r\n"
}

@MainActor
private func mcpServer() {
    let directory = scratchFolder("mcp-server")
    defer { try? FileManager.default.removeItem(at: directory); Defaults.reset(.mcpPort) }
    Defaults[.mcpPort] = 0  // any free port
    let store = MemoryClipStore()
    _ = try? store.insert(.text("hello from the clipboard"))
    let server = MCPServer(store: store, directory: directory)
    server.start()
    let deadline = Date().addingTimeInterval(5)
    while !server.isRunning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    guard case .running(let url) = server.state, let port = url.port, url.host == "127.0.0.1", url.path == "/mcp" else {
        checkNow(false, "server running: \(server.state)")
        return
    }

    func send(_ method: String, _ path: String, host: String? = nil, headers: [(String, String)] = [], body: Data = Data(),
              readFor: Double = 5) -> RawResponse? {
        raw(port, request(method, path, port: port, host: host, headers: headers, body: body), body: body, readFor: readFor)
    }

    // DNS rebinding and cross-site protection.
    checkNow(send("GET", "/.well-known/oauth-authorization-server", host: "evil.example:\(port)")?.status == 421, "foreign Host refused")
    checkNow(send("GET", "/.well-known/oauth-authorization-server", host: "127.0.0.1:\(port + 1)")?.status == 421, "wrong port in Host")
    checkNow(send("GET", "/.well-known/oauth-authorization-server", host: "")?.status == 400, "missing Host")
    checkNow(send("GET", "/.well-known/oauth-authorization-server", headers: [("Origin", "https://evil.example")])?.status == 403,
             "foreign Origin refused")
    checkNow(send("GET", "/.well-known/oauth-authorization-server", headers: [("Origin", "null")])?.status == 403, "null Origin refused")
    let metadata = send("GET", "/.well-known/oauth-authorization-server", host: "localhost:\(port)",
                        headers: [("Origin", "http://localhost:\(port)")])
    checkNow(metadata?.status == 200 && metadata?.json?["issuer"]?.string == "http://localhost:\(port)"
             && metadata?.json?["code_challenge_methods_supported"] == ["S256"]
             && metadata?.json?["registration_endpoint"]?.string == "http://localhost:\(port)/register", "AS metadata")
    checkNow(metadata?.headers["cache-control"] == "no-store" && metadata?.headers["x-content-type-options"] == "nosniff", "base headers")
    checkNow(send("GET", "/.well-known/oauth-protected-resource/mcp")?.json?["resource"]?.string == "http://127.0.0.1:\(port)/mcp",
             "protected resource metadata")
    checkNow(send("GET", "/nothing")?.status == 404, "unknown path")
    checkNow(raw(port, request("GET", "/.well-known/oauth-protected-resource", port: port), halfClose: true)?.status == 200,
             "a client that stops sending after its request still gets the answer")

    // Bearer tokens.
    let unauthorized = send("POST", "/mcp", headers: [("Content-Type", "application/json")], body: Data("{}".utf8))
    checkNow(unauthorized?.status == 401 && unauthorized?.headers["www-authenticate"]?.contains("resource_metadata=") == true,
             "no token: 401 pointing at the metadata")
    checkNow(send("POST", "/mcp", headers: [("Authorization", "Bearer spm_wrong"), ("Content-Type", "application/json")],
                  body: Data("{}".utf8))?.headers["www-authenticate"]?.contains("invalid_token") == true, "wrong token")
    guard let (client, token) = try? server.addTokenClient(name: "Editor") else { checkNow(false, "token client"); return }
    checkNow(server.clients.map(\.name) == ["Editor"] && client.connection == .token, "token client listed")
    let saved = (try? String(contentsOf: directory.appendingPathComponent("clients.json"), encoding: .utf8)) ?? ""
    checkNow(saved.contains(MCPSecrets.hash(token)) && !saved.contains(token), "only the token's hash is on disk")
    checkNow((try? server.addTokenClient(name: "  ")) == nil, "a token client needs a name")

    func rpc(_ body: JSON, session: String? = nil, token: String = token, accept: String = "application/json, text/event-stream",
             extra: [(String, String)] = []) -> RawResponse? {
        var headers = [("Authorization", "Bearer \(token)"), ("Content-Type", "application/json"), ("Accept", accept)] + extra
        if let session { headers.append(("Mcp-Session-Id", session)) }
        return send("POST", "/mcp", headers: headers, body: body.data)
    }
    let initialize: JSON = ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                            "params": ["protocolVersion": "2025-03-26", "capabilities": [:], "clientInfo": ["name": "t", "version": "1"]]]
    let opened = rpc(initialize)
    let session = opened?.headers["mcp-session-id"] ?? ""
    checkNow(opened?.status == 200 && !session.isEmpty, "initialize opens a session")
    checkNow(opened?.json?["result"]?["protocolVersion"] == "2025-03-26" && opened?.json?["result"]?["serverInfo"]?["name"] == "super-paste"
             && opened?.json?["result"]?["capabilities"]?["tools"] != nil && opened?.json?["id"] == 1, "initialize result")
    checkNow(rpc(["jsonrpc": "2.0", "method": "notifications/initialized"], session: session)?.status == 202, "notification: 202")
    let listRequest: JSON = ["jsonrpc": "2.0", "id": "list", "method": "tools/list"]
    checkNow(rpc(listRequest)?.status == 400, "no session: 400")
    checkNow(rpc(listRequest, session: "unknown")?.status == 404, "unknown session: 404")
    checkNow(rpc(listRequest, session: session, extra: [("MCP-Protocol-Version", "1999-01-01")])?.status == 400, "unsupported version")
    let names = rpc(listRequest, session: session)?.json?["result"]?["tools"]?.array?.compactMap { $0["name"]?.string } ?? []
    checkNow(names == ["search", "read_item", "create_item", "update_item", "delete_item", "list_pinboards", "create_pinboard",
                       "rename_pinboard", "delete_pinboard", "add_item_to_pinboard", "remove_item_from_pinboard"], "the eleven tools")
    let found = rpc(["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "search", "arguments": ["query": "hello"]]],
                    session: session)?.json?["result"]
    checkNow(found?["isError"] == false && found?["structuredContent"]?["items"]?.array?.count == 1
             && found?["content"]?.array?.first?["type"] == "text", "tools/call search")
    let failed = rpc(["jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": ["name": "read_item", "arguments": ["id": "x"]]],
                     session: session)?.json?["result"]
    checkNow(failed?["isError"] == true && failed?["content"]?.array?.first?["text"]?.string?.hasPrefix("No clipboard item") == true,
             "tool errors are results with isError")
    checkNow(rpc(["jsonrpc": "2.0", "id": 5, "method": "tools/call", "params": ["name": "nope"]], session: session)?.json?["error"]?["code"]
             == -32602, "unknown tool: JSON-RPC error")
    checkNow(rpc(["jsonrpc": "2.0", "id": 6, "method": "resources/list"], session: session)?.json?["error"]?["code"] == -32601,
             "unknown method")
    checkNow(rpc(["jsonrpc": "2.0", "id": 7, "method": "ping"], session: session)?.json?["result"] == [:], "ping")
    let batch = rpc([["jsonrpc": "2.0", "id": 8, "method": "ping"], ["jsonrpc": "2.0", "method": "notifications/cancelled"]],
                    session: session)?.json
    checkNow(batch?.array?.count == 1 && batch?.array?.first?["id"] == 8, "batches answer each request")
    let streamed = rpc(["jsonrpc": "2.0", "id": 9, "method": "ping"], session: session, accept: "text/event-stream")
    checkNow(streamed?.headers["content-type"] == "text/event-stream"
             && streamed?.text.contains("event: message\ndata: {\"id\":9,\"jsonrpc\":\"2.0\",\"result\":{}}") == true,
             "SSE reply when only event streams are accepted")
    let badJSON = send("POST", "/mcp", headers: [("Authorization", "Bearer \(token)"), ("Content-Type", "application/json"),
                                                 ("Mcp-Session-Id", session)], body: Data("{oops".utf8))
    checkNow(badJSON?.status == 400 && badJSON?.json?["error"]?["code"] == -32700, "parse error")
    let huge = Data(repeating: 0x20, count: (4 << 20) + 1)
    checkNow(send("POST", "/mcp", headers: [("Authorization", "Bearer \(token)"), ("Content-Type", "application/json")], body: huge)?
                .status == 413, "oversized body")
    checkNow(send("POST", "/register", headers: [("Content-Type", "application/json")],
                  body: Data(repeating: 0x20, count: 70_000))?.status == 413, "OAuth endpoints take small bodies only")
    let stream = send("GET", "/mcp", headers: [("Authorization", "Bearer \(token)"), ("Accept", "text/event-stream"),
                                               ("Mcp-Session-Id", session)], readFor: 0.8)
    checkNow(stream?.status == 200 && stream?.headers["content-type"] == "text/event-stream" && stream?.text.hasPrefix(":") == true,
             "GET opens an event stream")

    // Sessions belong to their client.
    let (other, otherToken) = try! server.addTokenClient(name: "Other")
    checkNow(rpc(listRequest, session: session, token: otherToken)?.status == 404, "another client's session")
    checkNow(send("DELETE", "/mcp", headers: [("Authorization", "Bearer \(token)"), ("Mcp-Session-Id", session)])?.status == 200,
             "DELETE ends the session")
    checkNow(rpc(listRequest, session: session)?.status == 404, "ended session")
    server.revoke(other.id)
    checkNow(rpc(initialize, token: otherToken)?.status == 401 && server.clients.count == 1, "revoked token client")

    // OAuth: registration, consent, PKCE, token, revocation.
    func register(_ body: JSON) -> RawResponse? { send("POST", "/register", headers: [("Content-Type", "application/json")], body: body.data) }
    checkNow(register(["redirect_uris": ["http://127.0.0.1:9/cb"]])?.json?["error"] == "invalid_client_metadata", "name required")
    checkNow(register(["client_name": "X", "redirect_uris": ["http://evil.example/cb"]])?.json?["error"] == "invalid_redirect_uri",
             "remote http redirect refused")
    let registered = register(["client_name": "Desk <Assistant>", "redirect_uris": ["http://127.0.0.1:9/cb"],
                               "grant_types": ["authorization_code", "refresh_token"], "token_endpoint_auth_method": "none"])
    let clientID = registered?.json?["client_id"]?.string ?? ""
    checkNow(registered?.status == 201 && !clientID.isEmpty && registered?.json?["client_secret"] == nil, "public client registered")
    let verifier = "superpaste-pkce-test-verifier-0123456789_abcdef~ghij.k"
    let challenge = PKCE.challenge(for: verifier)
    func authorize(_ extra: String = "") -> RawResponse? {
        send("GET", "/authorize?response_type=code&client_id=\(clientID)&redirect_uri=http%3A%2F%2F127.0.0.1%3A9%2Fcb"
             + "&code_challenge=\(challenge)&code_challenge_method=S256&state=xyz\(extra)")
    }
    func field(_ name: String, in page: String) -> String? {
        guard let range = page.range(of: "name=\"\(name)\" value=\"") else { return nil }
        return String(page[range.upperBound...].prefix { $0 != "\"" })
    }
    let page = authorize()
    let html = page?.text ?? ""
    checkNow(page?.status == 200 && html.contains("<h1>Connect Desk &lt;Assistant&gt;</h1>") && !html.contains("<Assistant>"),
             "consent page names the client, escaped")
    checkNow(html.contains("View and manage your clipboard items") && html.contains("View and manage your pinboards")
             && html.contains(">Cancel</button>") && html.contains(">Connect</button>"), "consent page text")
    let csp = page?.headers["content-security-policy"] ?? ""
    checkNow(csp.contains("default-src 'none'") && csp.contains("frame-ancestors 'none'") && csp.contains("form-action 'self' http://127.0.0.1:9")
             && !csp.contains("script-src") && page?.headers["x-frame-options"] == "DENY", "strict CSP: \(csp)")
    checkNow(send("GET", "/authorize?response_type=code&client_id=unknown&code_challenge=\(challenge)&code_challenge_method=S256")?.status
             == 400, "unknown client gets an error page, not a redirect")
    checkNow(authorize("&resource=https%3A%2F%2Fevil.example")?.headers["location"]?.contains("error=invalid_target") == true,
             "foreign resource")
    let noPKCE = send("GET", "/authorize?response_type=code&client_id=\(clientID)&state=s")
    checkNow(noPKCE?.status == 303 && noPKCE?.headers["location"]?.hasPrefix("http://127.0.0.1:9/cb?error=invalid_request") == true,
             "PKCE is required")

    func decide(_ page: RawResponse?, _ decision: String, csrf: String? = nil, origin: String? = nil) -> RawResponse? {
        let text = page?.text ?? ""
        let form = "request_id=\(field("request_id", in: text) ?? "")&csrf=\(csrf ?? field("csrf", in: text) ?? "")&decision=\(decision)"
        var headers = [("Content-Type", "application/x-www-form-urlencoded")]
        if let origin { headers.append(("Origin", origin)) }
        return send("POST", "/authorize", headers: headers, body: Data(form.utf8))
    }
    let crossSite = authorize()
    checkNow(decide(crossSite, "approve", origin: "https://evil.example")?.status == 403, "cross-site approval refused")
    checkNow(decide(authorize(), "approve", csrf: "forged")?.status == 403, "forged CSRF token refused")
    let denied = decide(authorize(), "deny", origin: "http://127.0.0.1:\(port)")
    checkNow(denied?.status == 303 && denied?.headers["location"] == "http://127.0.0.1:9/cb?error=access_denied&state=xyz", "Cancel")
    let consent = authorize()
    let approved = decide(consent, "approve", origin: "http://127.0.0.1:\(port)")
    let location = approved?.headers["location"] ?? ""
    let code = URLComponents(string: location)?.queryItems?.first { $0.name == "code" }?.value ?? ""
    checkNow(approved?.status == 303 && location.hasPrefix("http://127.0.0.1:9/cb?code=") && location.hasSuffix("&state=xyz"), "Connect")
    checkNow(decide(consent, "approve")?.status == 400, "a consent can't be used twice")

    func exchange(_ code: String, verifier: String, redirect: String = "http%3A%2F%2F127.0.0.1%3A9%2Fcb") -> RawResponse? {
        let form = "grant_type=authorization_code&code=\(code)&redirect_uri=\(redirect)&client_id=\(clientID)&code_verifier=\(verifier)"
        return send("POST", "/token", headers: [("Content-Type", "application/x-www-form-urlencoded")], body: Data(form.utf8))
    }
    checkNow(exchange(code, verifier: verifier + "x")?.json?["error"] == "invalid_grant", "wrong verifier refused")
    checkNow(exchange(code, verifier: verifier)?.json?["error"] == "invalid_grant", "a code is burnt by a failed attempt")
    let second = URLComponents(string: decide(authorize(), "approve")?.headers["location"] ?? "")?.queryItems?
        .first { $0.name == "code" }?.value ?? ""
    checkNow(exchange(second, verifier: verifier, redirect: "http%3A%2F%2F127.0.0.1%3A9%2Fother")?.json?["error"] == "invalid_grant",
             "redirect URI must match")
    let third = URLComponents(string: decide(authorize(), "approve")?.headers["location"] ?? "")?.queryItems?
        .first { $0.name == "code" }?.value ?? ""
    let issued = exchange(third, verifier: verifier)
    let accessToken = issued?.json?["access_token"]?.string ?? ""
    checkNow(issued?.status == 200 && issued?.json?["token_type"] == "Bearer" && accessToken.hasPrefix("spm_")
             && issued?.headers["cache-control"] == "no-store", "token issued")
    checkNow(server.clients.contains { $0.name == "Desk <Assistant>" && $0.connection == .oauth }, "OAuth client listed")
    checkNow(rpc(initialize, token: accessToken)?.status == 200, "the OAuth token works")
    let revoked = send("POST", "/revoke", headers: [("Content-Type", "application/x-www-form-urlencoded")],
                       body: Data("token=\(accessToken)&token_type_hint=access_token".utf8))
    checkNow(revoked?.status == 200 && rpc(initialize, token: accessToken)?.status == 401, "revoked through /revoke")
    checkNow(!server.clients.contains { $0.connection == .oauth }, "and gone from the list")
    checkNow(send("POST", "/revoke", headers: [("Content-Type", "application/x-www-form-urlencoded")],
                  body: Data("token=whatever".utf8))?.status == 200, "revoking an unknown token says nothing")

    // Port changes.
    checkNow((try? server.changePort(to: 80)) == nil, "privileged ports refused")
    let blocker = socket(AF_INET, SOCK_STREAM, 0)
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
    listen(blocker, 1)
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(blocker, $0, &length) } }
    let busy = Int(UInt16(bigEndian: address.sin_port))
    var busyError: Error?
    do { try server.changePort(to: busy) } catch { busyError = error }
    checkNow((busyError as? MCPServerError) == .portUnavailable(busy) && server.isRunning && server.clients.count == 1,
             "a port in use is refused and nothing changes")
    close(blocker)  // the port is free now
    checkNow((try? server.changePort(to: busy)) != nil, "port changed")
    let restart = Date().addingTimeInterval(5)
    while server.state != .running(URL(string: "http://127.0.0.1:\(busy)/mcp")!) && Date() < restart {
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    checkNow(server.port == busy && server.isRunning && server.clients.isEmpty, "restarted on the new port, clients removed")
    checkNow(raw(port, request("GET", "/.well-known/oauth-authorization-server", port: port), readFor: 1) == nil, "old port closed")

    server.stop()
    checkNow(server.state == .off, "stopped")
    checkNow(raw(busy, request("GET", "/.well-known/oauth-authorization-server", port: busy), readFor: 1) == nil, "nothing listens")
}

// MARK: - stdio bridge

/// Runs the built `super-paste-mcp` (next to this executable; `swift build` builds it) against a live server.
@MainActor
private func mcpBridge() {
    let binary = Bundle.main.executableURL!.deletingLastPathComponent().appendingPathComponent("super-paste-mcp")
    guard FileManager.default.isExecutableFile(atPath: binary.path) else {
        print("  (skipped: build super-paste-mcp first with `swift build`)")
        return
    }
    let directory = scratchFolder("mcp-bridge")
    defer { try? FileManager.default.removeItem(at: directory); Defaults.reset(.mcpPort) }
    Defaults[.mcpPort] = 0
    let store = MemoryClipStore()
    _ = try? store.insert(.text("bridged item"))
    let server = MCPServer(store: store, directory: directory)
    func waitUntilRunning() -> Int? {
        let deadline = Date().addingTimeInterval(5)
        while !server.isRunning && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        if case .running(let url) = server.state { return url.port }
        return nil
    }
    server.start()
    guard let port = waitUntilRunning(), let (_, token) = try? server.addTokenClient(name: "Bridge") else {
        checkNow(false, "server for the bridge")
        return
    }

    func launch(_ environment: [String: String]) -> (Process, Pipe, Pipe, () -> [JSON]) {
        let process = Process()
        process.executableURL = binary
        process.environment = environment
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let buffer = LockedData()
        output.fileHandleForReading.readabilityHandler = { handle in buffer.append(handle.availableData) }
        try? process.run()
        let lines: () -> [JSON] = {
            buffer.value.split(separator: UInt8(ascii: "\n")).compactMap { try? JSON(parsing: Data($0)) }
        }
        return (process, input, output, lines)
    }
    func wait(until condition: () -> Bool, seconds: TimeInterval = 10) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    }
    func write(_ pipe: Pipe, _ message: JSON) { pipe.fileHandleForWriting.write(message.data + Data("\n".utf8)) }

    let (missing, _, _, _) = launch([:])
    wait(until: { !missing.isRunning })
    checkNow(missing.terminationStatus == 64, "MCP_URL and MCP_TOKEN are required")
    let (remote, _, _, _) = launch(["MCP_URL": "http://example.com/mcp", "MCP_TOKEN": token])
    wait(until: { !remote.isRunning })
    checkNow(remote.terminationStatus == 64, "plain http only to this Mac")

    let (process, input, _, lines) = launch(["MCP_URL": "http://127.0.0.1:\(port)/mcp", "MCP_TOKEN": token])
    write(input, ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2025-06-18", "capabilities": [:], "clientInfo": ["name": "t", "version": "1"]]])
    write(input, ["jsonrpc": "2.0", "method": "notifications/initialized"])
    write(input, ["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
    input.fileHandleForWriting.write(Data("not json\n".utf8))
    wait(until: { lines().count >= 3 })
    var replies = lines()
    checkNow(replies.first { $0["id"] == 1 }?["result"]?["protocolVersion"] == "2025-06-18", "initialize through the bridge")
    checkNow(replies.first { $0["id"] == 2 }?["result"]?["tools"]?.array?.count == 11, "tools/list through the bridge")
    checkNow(replies.contains { $0["id"] == .null && $0["error"]?["code"] == -32700 }, "a line that isn't JSON gets a parse error")

    // Super Paste restarts on the same port: the bridge opens a new session by itself.
    Defaults[.mcpPort] = port
    server.stop()
    server.start()
    checkNow(waitUntilRunning() == port, "server back on the same port")
    write(input, ["jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": ["name": "search", "arguments": ["query": "bridged"]]])
    wait(until: { lines().contains { $0["id"] == 3 } })
    replies = lines()
    checkNow(replies.first { $0["id"] == 3 }?["result"]?["structuredContent"]?["items"]?.array?.count == 1,
             "the bridge re-initializes after a restart and retries")
    checkNow(replies.filter { $0["id"] == 1 }.count == 1, "the replayed initialize isn't shown to the client again")

    server.revoke(server.clients[0].id)
    write(input, ["jsonrpc": "2.0", "id": 4, "method": "ping"])
    wait(until: { lines().contains { $0["id"] == 4 } })
    checkNow(lines().first { $0["id"] == 4 }?["error"]?["code"] == -32001, "a refused token becomes a JSON-RPC error")

    input.fileHandleForWriting.closeFile()
    wait(until: { !process.isRunning })
    checkNow(!process.isRunning && process.terminationStatus == 0, "exits at the end of input")
    if process.isRunning { process.terminate() }
    server.stop()
}

/// Bytes appended from a reader thread and read on the main thread.
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}
