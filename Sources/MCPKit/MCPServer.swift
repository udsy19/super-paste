import Foundation
import Combine
import SuperPasteCore

public enum MCPServerError: LocalizedError, Equatable {
    case invalidPort
    case portUnavailable(Int)
    case invalidName

    public var errorDescription: String? {
        switch self {
        case .invalidPort: "Choose a port between 1024 and 65535."
        case .portUnavailable(let port): "Port \(port) is already in use."
        case .invalidName: "The name can't be empty."
        }
    }
}

/// The local MCP server (behaviour.md §14): Streamable HTTP on 127.0.0.1 only, OAuth 2.1 with dynamic client
/// registration and PKCE, static tokens for hand-made clients, and the eleven tools over `ItemStoring`.
///
/// Every request must name this server in `Host` (127.0.0.1 or localhost with the bound port) and, when it carries
/// an `Origin`, come from this server's own origin; anything else is refused before routing, which defeats DNS
/// rebinding and cross-site requests from web pages. `/mcp` needs a bearer token; sessions belong to the client that
/// opened them.
@MainActor
public final class MCPServer: MCPServing {
    public static let protocolVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
    static let serverVersion = "1.0.0"
    static let maxMessageBytes = 4 << 20
    static let maxOAuthBytes = 64 << 10
    static let maxSessionsPerClient = 16
    static let sessionIdleLifetime: TimeInterval = 86_400

    private let injectedStore: ItemStoring?
    private var store: ItemStoring { injectedStore ?? Services.store }
    private let registry: ClientRegistry
    private var oauth: OAuthService!
    private let stateSubject = CurrentValueSubject<MCPServerState, Never>(.off)
    private let clientsSubject: CurrentValueSubject<[MCPClientInfo], Never>
    private var http: HTTPServer?
    private var boundPort: Int?
    /// Set while a port change waits for the new listener: the port to go back to if it fails.
    private var revertPort: Int?
    private var sessions: [String: Session] = [:]
    private var settingObserver: AnyCancellable?

    private struct Session {
        var clientID: UUID
        var lastSeen: Date
        /// The open `GET /mcp` event stream, if any.
        var stream: HTTPConnection?
    }

    /// `directory` holds `clients.json` and `dcr.json`.
    public init(store: ItemStoring?, directory: URL) {
        injectedStore = store
        registry = ClientRegistry(directory: directory)
        clientsSubject = CurrentValueSubject(registry.infos)
        oauth = OAuthService(registry: registry) { [weak self] id in self?.revoke(id) }
        registry.onChange = { [weak self] infos in self?.clientsSubject.send(infos) }
    }

    /// The app's server: the store from `Services`, files in `SuperPastePaths.mcp`, and it follows
    /// `Defaults[.isMCPEnabled]` (turning it off stops the server; on starts it).
    convenience init() {
        self.init(store: nil, directory: SuperPastePaths.mcp)
        settingObserver = Defaults.publisher(.isMCPEnabled).dropFirst().removeDuplicates()
            .sink { [weak self] enabled in MainActor.assumeIsolated { enabled ? self?.start() : self?.stop() } }
    }

    // MARK: MCPServing

    public var state: MCPServerState { stateSubject.value }
    public var stateChanges: AnyPublisher<MCPServerState, Never> { stateSubject.removeDuplicates().eraseToAnyPublisher() }
    public var port: Int { Defaults[.mcpPort] }
    public var clients: [MCPClientInfo] { registry.infos }
    public var clientChanges: AnyPublisher<[MCPClientInfo], Never> { clientsSubject.eraseToAnyPublisher() }

    public func start() {
        guard http == nil else { return }
        let port = Defaults[.mcpPort]
        stateSubject.send(.starting)
        let server = HTTPServer { $0 == "/mcp" ? Self.maxMessageBytes : Self.maxOAuthBytes }
        server.onRequest = { [weak self] request, connection in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.handle(request, on: connection, from: server) } }
        }
        http = server
        do {
            try server.start(port: port) { [weak self] event in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.listener(server, event) } }
            }
        } catch {
            http = nil
            fail(error.localizedDescription)
        }
    }

    public func stop() {
        http?.stop()
        http = nil
        boundPort = nil
        sessions.removeAll()
        stateSubject.send(.off)
    }

    public func changePort(to newPort: Int) throws {
        guard (1024...65535).contains(newPort) else { throw MCPServerError.invalidPort }
        let oldPort = Defaults[.mcpPort]
        guard newPort != oldPort else { return }
        guard Self.canBind(newPort) else { throw MCPServerError.portUnavailable(newPort) }
        let wasRunning = http != nil
        stop()
        // A new port means new URLs everywhere: every client connects again (strings.md settings.mcp.port.warning).
        registry.removeAll()
        oauth.reset()
        Defaults[.mcpPort] = newPort
        Log.mcp.info("MCP port changed to \(newPort)")
        if wasRunning {
            revertPort = oldPort
            start()
        }
    }

    public func addTokenClient(name: String) throws -> (client: MCPClientInfo, token: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MCPServerError.invalidName }
        let (client, token) = registry.addTokenClient(name: String(trimmed.prefix(100)))
        return (client, token)
    }

    public func revoke(_ clientID: UUID) {
        for (id, session) in sessions where session.clientID == clientID {
            session.stream?.close()
            sessions[id] = nil
        }
        if registry.revoke(clientID) { Log.mcp.info("Disconnected a client") }
    }

    // MARK: Listener

    private func listener(_ server: HTTPServer, _ event: HTTPServer.Event) {
        guard http === server else { return }
        switch event {
        case .ready(let port):
            boundPort = port
            revertPort = nil
            stateSubject.send(.running(URL(string: "http://127.0.0.1:\(port)/mcp")!))
            Log.mcp.info("MCP server listening on 127.0.0.1:\(port)")
        case .failed(let message):
            http = nil
            boundPort = nil
            if let old = revertPort {
                // The new port failed after all: go back to the one that worked.
                revertPort = nil
                Defaults[.mcpPort] = old
                start()
            } else {
                fail(message)
            }
        }
    }

    private func fail(_ message: String) {
        Log.mcp.error("MCP server failed: \(message, privacy: .public)")
        stateSubject.send(.failed(message))
    }

    /// Whether 127.0.0.1:`port` is free to listen on (bound and released at once).
    static func canBind(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        } == 0
    }

    // MARK: Routing

    private func handle(_ request: HTTPRequest, on connection: HTTPConnection, from server: HTTPServer) {
        guard http === server, let port = boundPort else {
            connection.respond(.text("Not running", status: 503))
            return
        }
        let host = request.header("host")?.lowercased() ?? ""
        guard ["127.0.0.1:\(port)", "localhost:\(port)"].contains(host) else {
            connection.respond(.text("This server only answers requests addressed to it.", status: 421))
            return
        }
        if let origin = request.header("origin")?.lowercased(),
           !["http://127.0.0.1:\(port)", "http://localhost:\(port)"].contains(origin) {
            connection.respond(.text("Requests from web pages aren't allowed.", status: 403))
            return
        }
        let base = "http://\(host)"
        let response = route(request, base: base, connection: connection) ?? .text("Not found", status: 404)
        if response.status != Self.streamed.status { connection.respond(response) }
    }

    /// The response for a request (nil: unknown path), or `streamed` when it was answered as an event stream.
    private func route(_ request: HTTPRequest, base: String, connection: HTTPConnection) -> HTTPResponse? {
        switch (request.method, request.path) {
        case ("GET", "/.well-known/oauth-protected-resource"), ("GET", "/.well-known/oauth-protected-resource/mcp"):
            return .json(oauth.protectedResourceMetadata(base: base))
        case ("GET", "/.well-known/oauth-authorization-server"), ("GET", "/.well-known/oauth-authorization-server/mcp"):
            return .json(oauth.authorizationServerMetadata(base: base))
        case ("POST", "/register"):
            return oauth.register(request)
        case ("GET", "/authorize"):
            return oauth.authorizePage(request, base: base)
        case ("POST", "/authorize"):
            return oauth.authorizeDecision(request)
        case ("POST", "/token"):
            return oauth.token(request)
        case ("POST", "/revoke"):
            return oauth.revoke(request)
        case (_, "/mcp"):
            return mcp(request, base: base, connection: connection)
        case (_, "/register"), (_, "/authorize"), (_, "/token"), (_, "/revoke"):
            return .text("Method not allowed", status: 405)
        default:
            return nil
        }
    }

    // MARK: MCP endpoint (Streamable HTTP)

    private func mcp(_ request: HTTPRequest, base: String, connection: HTTPConnection) -> HTTPResponse {
        let token = Self.bearerToken(request.header("authorization"))
        guard let token, let client = registry.authenticate(token) else {
            var challenge = "Bearer resource_metadata=\"\(base)/.well-known/oauth-protected-resource/mcp\""
            if token != nil { challenge += ", error=\"invalid_token\"" }
            return .json(Self.rpcError(nil, -32001, "Unauthorized"), status: 401, headers: [("WWW-Authenticate", challenge)])
        }
        switch request.method {
        case "POST": return post(request, client: client, connection: connection)
        case "GET": return openStream(request, client: client, connection: connection)
        case "DELETE": return endSession(request, client: client)
        default: return .text("Method not allowed", status: 405, headers: [("Allow", "GET, POST, DELETE")])
        }
    }

    private func post(_ request: HTTPRequest, client: MCPClientInfo, connection: HTTPConnection) -> HTTPResponse {
        guard request.header("content-type")?.lowercased().hasPrefix("application/json") == true else {
            return .json(Self.rpcError(nil, -32700, "Content-Type must be application/json"), status: 415)
        }
        let accept = request.header("accept")?.lowercased() ?? "*/*"
        let acceptsJSON = accept.contains("application/json") || accept.contains("*/*") || accept.contains("application/*")
        let acceptsStream = accept.contains("text/event-stream")
        guard acceptsJSON || acceptsStream else {
            return .json(Self.rpcError(nil, -32000, "Accept must allow application/json or text/event-stream"), status: 406)
        }
        guard let body = try? JSON(parsing: request.body) else {
            return .json(Self.rpcError(nil, -32700, "Parse error"), status: 400)
        }
        let isBatch = body.array != nil
        let messages = body.array ?? [body]
        guard !messages.isEmpty else { return .json(Self.rpcError(nil, -32600, "Invalid Request"), status: 400) }

        let isInitialize = messages.contains { $0["method"]?.string == "initialize" }
        if isInitialize {
            guard !isBatch else {
                return .json(Self.rpcError(nil, -32600, "initialize must be sent on its own"), status: 400)
            }
        } else {
            if case .failure(let failure) = session(for: request, client: client) { return failure.response }
        }

        var newSession: String?
        let replies = messages.compactMap { process($0, client: client, newSession: &newSession) }
        guard !replies.isEmpty else { return HTTPResponse(status: 202) }
        let reply = isBatch ? JSON.array(replies) : replies[0]
        var headers: [(String, String)] = []
        if let newSession { headers.append(("Mcp-Session-Id", newSession)) }
        if acceptsJSON { return .json(reply, headers: headers) }
        // The client only takes event streams: one event per reply, then the stream ends.
        connection.startStream(HTTPResponse(status: 200, headers: [("Content-Type", "text/event-stream")] + headers),
                               keepAlive: false)
        for message in replies { connection.send(event: message) }
        connection.endStream()
        return Self.streamed
    }

    /// Marks a request whose answer went out as an event stream: nothing more is sent.
    static let streamed = HTTPResponse(status: -1)

    private func session(for request: HTTPRequest, client: MCPClientInfo) -> Result<String, ResponseFailure> {
        guard let id = request.header("mcp-session-id") else {
            return .failure(ResponseFailure(.json(Self.rpcError(nil, -32000, "Bad Request: Mcp-Session-Id header is required"),
                                                  status: 400)))
        }
        pruneSessions()
        guard var session = sessions[id], session.clientID == client.id else {
            return .failure(ResponseFailure(.json(Self.rpcError(nil, -32001, "Session not found"), status: 404)))
        }
        if let version = request.header("mcp-protocol-version"), !Self.protocolVersions.contains(version) {
            return .failure(ResponseFailure(.json(Self.rpcError(nil, -32000, "Unsupported MCP-Protocol-Version: \(version)"),
                                                  status: 400)))
        }
        session.lastSeen = Date()
        sessions[id] = session
        return .success(id)
    }

    private struct ResponseFailure: Error {
        var response: HTTPResponse
        init(_ response: HTTPResponse) { self.response = response }
    }

    private func openStream(_ request: HTTPRequest, client: MCPClientInfo, connection: HTTPConnection) -> HTTPResponse {
        guard request.header("accept")?.lowercased().contains("text/event-stream") == true else {
            return .text("Accept must allow text/event-stream", status: 406)
        }
        let id: String
        switch session(for: request, client: client) {
        case .failure(let failure): return failure.response
        case .success(let sessionID): id = sessionID
        }
        sessions[id]?.stream?.close()
        sessions[id]?.stream = connection
        connection.onClose = { [weak self, weak connection] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let self, self.sessions[id]?.stream === connection { self.sessions[id]?.stream = nil }
                }
            }
        }
        // The server has nothing to push yet; the stream stays open (with keep-alive comments) for when it does.
        connection.startStream(HTTPResponse(status: 200, headers: [("Content-Type", "text/event-stream")],
                                            body: Data(": stream open\n\n".utf8)), keepAlive: true)
        return Self.streamed
    }

    private func endSession(_ request: HTTPRequest, client: MCPClientInfo) -> HTTPResponse {
        switch session(for: request, client: client) {
        case .failure(let failure):
            return failure.response
        case .success(let id):
            sessions[id]?.stream?.close()
            sessions[id] = nil
            return HTTPResponse(status: 200)
        }
    }

    private func pruneSessions() {
        let now = Date()
        for (id, session) in sessions where now.timeIntervalSince(session.lastSeen) > Self.sessionIdleLifetime {
            session.stream?.close()
            sessions[id] = nil
        }
    }

    // MARK: JSON-RPC

    /// The reply to one message; nil for notifications and for responses the client sends.
    private func process(_ message: JSON, client: MCPClientInfo, newSession: inout String?) -> JSON? {
        guard let object = message.object else { return Self.rpcError(nil, -32600, "Invalid Request") }
        guard let method = object["method"]?.string else {
            return object["result"] != nil || object["error"] != nil ? nil : Self.rpcError(nil, -32600, "Invalid Request")
        }
        guard object["jsonrpc"] == "2.0" else { return Self.rpcError(object["id"], -32600, "Invalid Request") }
        guard let id = object["id"] else { return nil }  // a notification (initialized, cancelled): nothing to say
        guard id.string != nil || id.int != nil else { return Self.rpcError(nil, -32600, "Invalid Request: bad id") }
        let params = object["params"]
        switch method {
        case "initialize":
            let requested = params?["protocolVersion"]?.string ?? ""
            let version = Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0]
            let sessionID = MCPSecrets.generate(prefix: "")
            let owned = sessions.filter { $0.value.clientID == client.id }.sorted { $0.value.lastSeen < $1.value.lastSeen }
            for (old, session) in owned.prefix(max(0, owned.count - Self.maxSessionsPerClient + 1)) {
                session.stream?.close()
                sessions[old] = nil
            }
            sessions[sessionID] = Session(clientID: client.id, lastSeen: Date())
            newSession = sessionID
            return Self.rpcResult(id, [
                "protocolVersion": .string(version),
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "super-paste", "title": "Super Paste", "version": .string(Self.serverVersion)],
                "instructions": .string(MCPToolbox.instructions),
            ])
        case "ping":
            return Self.rpcResult(id, [:])
        case "tools/list":
            return Self.rpcResult(id, ["tools": .array(MCPToolbox.tools.map(\.json))])
        case "tools/call":
            guard let name = params?["name"]?.string else { return Self.rpcError(id, -32602, "Invalid params: name is required") }
            let arguments = params?["arguments"]
            guard arguments == nil || arguments == .null || arguments?.object != nil else {
                return Self.rpcError(id, -32602, "Invalid params: arguments must be an object")
            }
            do {
                let output = try MCPToolbox(store: store).call(name, arguments: arguments?.object ?? [:])
                Log.mcp.info("\(client.name, privacy: .public) used \(name, privacy: .public)")
                return Self.rpcResult(id, ["content": .array(output.content), "structuredContent": output.structured,
                                           "isError": false])
            } catch MCPToolbox.ToolError.unknownTool(let name) {
                return Self.rpcError(id, -32602, MCPToolbox.ToolError.unknownTool(name).message)
            } catch let error as MCPToolbox.ToolError {
                return Self.rpcResult(id, ["content": [["type": "text", "text": .string(error.message)]], "isError": true])
            } catch {
                return Self.rpcResult(id, ["content": [["type": "text", "text": .string(error.localizedDescription)]],
                                           "isError": true])
            }
        default:
            return Self.rpcError(id, -32601, "Method not found: \(method)")
        }
    }

    static func rpcResult(_ id: JSON, _ result: JSON) -> JSON { ["jsonrpc": "2.0", "id": id, "result": result] }

    static func rpcError(_ id: JSON?, _ code: Int, _ message: String) -> JSON {
        ["jsonrpc": "2.0", "id": id ?? .null, "error": ["code": .int(code), "message": .string(message)]]
    }

    static func bearerToken(_ header: String?) -> String? {
        guard let header, header.count > 7, header.prefix(7).lowercased() == "bearer " else { return nil }
        let token = header.dropFirst(7).trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }
}
