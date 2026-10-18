import Foundation

// super-paste-mcp: bridges an MCP client that speaks stdio to Super Paste's local HTTP server. It reads newline-
// delimited JSON-RPC from stdin, POSTs each message to MCP_URL (Authorization: Bearer MCP_TOKEN, Accept:
// application/json, text/event-stream, carrying Mcp-Session-Id) and writes every JSON-RPC message that comes back —
// plain JSON or SSE `data:` events — to stdout, one per line (behaviour.md §14.1). Foundation only.
//
// When Super Paste restarts, its sessions are gone (404); the bridge then replays the client's `initialize` once and
// retries, so the client never notices. HTTP failures for requests come back as JSON-RPC errors, so a client never
// waits for an answer that won't arrive. At the end of stdin the session is closed (DELETE) and the bridge exits.

signal(SIGPIPE, SIG_IGN)

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("super-paste-mcp: \(message)\n".utf8))
    exit(code)
}

let environment = ProcessInfo.processInfo.environment
guard let endpoint = environment["MCP_URL"].flatMap(URL.init(string:)),
      let token = environment["MCP_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty else {
    fail("set MCP_URL and MCP_TOKEN (Super Paste → Settings → Integrations)", code: 64)
}
// The token only ever goes to this Mac, or over TLS.
switch endpoint.scheme?.lowercased() {
case "http" where ["127.0.0.1", "localhost", "::1"].contains(endpoint.host?.lowercased() ?? ""): break
case "https": break
default: fail("MCP_URL must be http://127.0.0.1:<port>/mcp (or an https URL)", code: 64)
}

/// Writes whole lines to stdout, one writer at a time.
enum Output {
    private static let lock = NSLock()

    static func line(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }

    /// Re-encodes a JSON message compactly so it fits on one line.
    static func message(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let compact = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]) else {
            FileHandle.standardError.write(Data("super-paste-mcp: dropped a reply that isn't JSON\n".utf8))
            return
        }
        line(compact)
    }

    /// A JSON-RPC error for every request id in a message that couldn't be delivered.
    static func errors(for ids: [Any], code: Int, _ text: String) {
        for id in ids {
            let reply: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]
            if let data = try? JSONSerialization.data(withJSONObject: reply, options: [.withoutEscapingSlashes]) { line(data) }
        }
        if ids.isEmpty { FileHandle.standardError.write(Data("super-paste-mcp: \(text)\n".utf8)) }
    }
}

/// Session state shared by concurrent requests.
actor Session {
    private(set) var id: String?
    private(set) var protocolVersion: String?
    private(set) var initialize: Data?

    func set(id: String?, protocolVersion: String?) {
        self.id = id
        if let protocolVersion { self.protocolVersion = protocolVersion }
    }

    func remember(initialize: Data) { self.initialize = initialize }
}

/// The bridge to one endpoint.
struct Bridge: Sendable {
    let endpoint: URL
    let token: String
    let session = Session()
    let http: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 600
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.connectionProxyDictionary = [:]  // never send the token through a proxy
        return URLSession(configuration: configuration)
    }()

    /// Request ids in a message (one, or several in a batch); notifications have none.
    static func requestIDs(in message: Any) -> [Any] {
        let messages = (message as? [Any]) ?? [message]
        return messages.compactMap { ($0 as? [String: Any]).flatMap { $0["method"] != nil ? $0["id"] : nil } }
    }

    /// Sends one message and returns the HTTP status; `deliver` gets every JSON-RPC message that comes back.
    func post(_ body: Data, deliver: (Data) async -> Void) async throws -> Int {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let id = await session.id { request.setValue(id, forHTTPHeaderField: "Mcp-Session-Id") }
        if let version = await session.protocolVersion { request.setValue(version, forHTTPHeaderField: "MCP-Protocol-Version") }
        let (bytes, response) = try await http.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { return status }
        if let id = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Mcp-Session-Id") {
            await session.set(id: id, protocolVersion: nil)
        }
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if type.hasPrefix("text/event-stream") {
            // SSE: `data:` lines accumulate until a blank line ends the event; only `message` events carry JSON-RPC.
            var line = Data(), data: [Data] = [], event = ""
            func dispatch() async {
                if !data.isEmpty && (event.isEmpty || event == "message") { await deliver(Data(data.joined(separator: Data("\n".utf8)))) }
                data = []; event = ""
            }
            func handle(_ raw: Data) async {
                let text = String(decoding: raw, as: UTF8.self)
                if text.isEmpty { await dispatch() }
                else if text.hasPrefix("data:") { data.append(Data(text.dropFirst(5).drop(while: { $0 == " " }).utf8)) }
                else if text.hasPrefix("event:") { event = text.dropFirst(6).trimmingCharacters(in: .whitespaces) }
            }
            for try await byte in bytes {
                if byte == UInt8(ascii: "\n") {
                    if line.last == UInt8(ascii: "\r") { line.removeLast() }
                    await handle(line)
                    line = Data()
                } else {
                    line.append(byte)
                }
            }
            if !line.isEmpty { await handle(line) }
            await dispatch()
        } else if status != 202 {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            if !body.isEmpty { await deliver(body) }
        }
        return status
    }

    /// Opens a new session by replaying the client's `initialize` (its reply isn't shown to the client again).
    func reinitialize() async -> Bool {
        guard let initialize = await session.initialize else { return false }
        await session.set(id: nil, protocolVersion: nil)
        guard (try? await post(initialize, deliver: { _ in })) == 200 else { return false }
        let initialized = Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
        _ = try? await post(initialized, deliver: { _ in })
        return true
    }

    /// Forwards one line from stdin.
    func forward(_ body: Data) async {
        guard let message = try? JSONSerialization.jsonObject(with: body) else {
            Output.errors(for: [NSNull()], code: -32700, "Parse error")
            return
        }
        let ids = Self.requestIDs(in: message)
        let isInitialize = (message as? [String: Any])?["method"] as? String == "initialize"
        if isInitialize { await session.remember(initialize: body) }
        let deliver: (Data) async -> Void = { reply in
            if isInitialize, let object = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
               let version = (object["result"] as? [String: Any])?["protocolVersion"] as? String {
                await session.set(id: await session.id, protocolVersion: version)
            }
            Output.message(reply)
        }
        do {
            var status = try await post(body, deliver: deliver)
            if status == 404, !isInitialize, await reinitialize() {
                status = try await post(body, deliver: deliver)
            }
            switch status {
            case 200..<300: break
            case 401: Output.errors(for: ids, code: -32001, "Super Paste refused the token. Create a new one in Settings → Integrations.")
            default: Output.errors(for: ids, code: -32000, "Super Paste answered HTTP \(status).")
            }
        } catch {
            Output.errors(for: ids, code: -32000, "Can't reach Super Paste at \(endpoint.absoluteString): \(error.localizedDescription)")
        }
    }

    /// Ends the session on the server.
    func close() async {
        guard let id = await session.id else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(id, forHTTPHeaderField: "Mcp-Session-Id")
        _ = try? await http.data(for: request)
    }
}

// stdin is read on its own thread; `initialize` is forwarded before anything else is read, other messages
// concurrently (a slow tool call doesn't hold up the next request).
let bridge = Bridge(endpoint: endpoint, token: token)
let inFlight = DispatchGroup()
Thread {
    while let line = readLine(strippingNewline: true) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let body = Data(trimmed.utf8)
        let isInitialize = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])?["method"] as? String == "initialize"
        inFlight.enter()
        let done = DispatchSemaphore(value: 0)
        Task {
            await bridge.forward(body)
            inFlight.leave()
            done.signal()
        }
        if isInitialize { done.wait() }
    }
    inFlight.wait()
    let closed = DispatchSemaphore(value: 0)
    Task {
        await bridge.close()
        closed.signal()
    }
    _ = closed.wait(timeout: .now() + 5)
    exit(0)
}.start()
dispatchMain()
