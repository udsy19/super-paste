import Foundation
import Network

// A small HTTP/1.1 server on Network.framework: just enough for the MCP endpoint, the OAuth endpoints and the
// consent page. Only origin-form targets, Content-Length or chunked bodies, persistent connections without
// pipelining, and server-sent event streams.

public struct HTTPRequest: Sendable {
    public var method: String
    /// The path without the query, e.g. "/mcp".
    public var path: String
    public var query: [String: String]
    /// Header names in lower case; repeated headers joined with ", ".
    public var headers: [String: String]
    public var body: Data
    /// HTTP/1.0, or `Connection: close`.
    public var wantsClose: Bool

    public func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// An `application/x-www-form-urlencoded` body (OAuth endpoints); the first value of a repeated name wins.
    public var form: [String: String] { Self.parseForm(String(decoding: body, as: UTF8.self)) }

    static func parseForm(_ text: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            func decode(_ s: Substring) -> String? { s.replacingOccurrences(of: "+", with: " ").removingPercentEncoding }
            guard let name = decode(parts[0]), let value = decode(parts.count > 1 ? parts[1] : "") else { continue }
            if fields[name] == nil { fields[name] = value }
        }
        return fields
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [(String, String)]
    public var body: Data

    public init(status: Int, headers: [(String, String)] = [], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }

    public static func json(_ value: JSON, status: Int = 200, headers: [(String, String)] = []) -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "application/json")] + headers, body: value.data)
    }

    public static func text(_ text: String, status: Int, headers: [(String, String)] = []) -> HTTPResponse {
        HTTPResponse(status: status, headers: [("Content-Type", "text/plain; charset=utf-8")] + headers, body: Data(text.utf8))
    }

    static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 202: "Accepted"
        case 204: "No Content"
        case 303: "See Other"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 406: "Not Acceptable"
        case 408: "Request Timeout"
        case 411: "Length Required"
        case 413: "Content Too Large"
        case 415: "Unsupported Media Type"
        case 421: "Misdirected Request"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 501: "Not Implemented"
        case 503: "Service Unavailable"
        case 505: "HTTP Version Not Supported"
        default: "Status"
        }
    }

    /// Headers every response carries: nothing is cached, sniffed, framed or leaked through referrers.
    static let baseHeaders: [(String, String)] = [
        ("Cache-Control", "no-store"), ("X-Content-Type-Options", "nosniff"), ("Referrer-Policy", "no-referrer"),
        ("X-Frame-Options", "DENY"),
    ]

    /// The status line and headers; `contentLength` nil leaves the body delimited by closing (event streams).
    func head(contentLength: Int?, close: Bool) -> Data {
        var lines = ["HTTP/1.1 \(status) \(Self.reason(status))"]
        var names = Set<String>()
        for (name, value) in headers + Self.baseHeaders where names.insert(name.lowercased()).inserted {
            lines.append("\(name): \(value)")
        }
        if let contentLength { lines.append("Content-Length: \(contentLength)") }
        lines.append("Connection: \(close ? "close" : "keep-alive")")
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }
}

// MARK: - Parsing

public enum HTTPParser {
    public enum Outcome {
        case needMore
        /// A complete request and how many bytes of the buffer it used.
        case request(HTTPRequest, consumed: Int)
        /// A malformed or oversized request: answer with this status and close.
        case failure(Int)
    }

    public static let maxHeaderBytes = 16 * 1024
    static let maxHeaderCount = 64
    private static let crlf = Data("\r\n".utf8)
    private static let headerEnd = Data("\r\n\r\n".utf8)

    /// Parses one request from the start of `buffer`. `maxBody` gives the body limit for a path.
    public static func parse(_ buffer: Data, maxBody: (String) -> Int) -> Outcome {
        guard let end = buffer.range(of: headerEnd, in: buffer.startIndex..<buffer.endIndex) else {
            return buffer.count > maxHeaderBytes ? .failure(431) : .needMore
        }
        guard end.lowerBound - buffer.startIndex <= maxHeaderBytes else { return .failure(431) }
        guard let head = String(data: buffer[buffer.startIndex..<end.lowerBound], encoding: .utf8) else { return .failure(400) }
        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3 else { return .failure(400) }
        let method = String(requestLine[0]), target = String(requestLine[1]), version = String(requestLine[2])
        guard !method.isEmpty, method.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return .failure(400) }
        guard version == "HTTP/1.1" || version == "HTTP/1.0" else { return .failure(505) }
        // Only origin-form ("/path?query"): absolute URLs aimed at other hosts are refused.
        guard target.hasPrefix("/"), target.count <= 8_192, let components = URLComponents(string: "http://localhost" + target)
        else { return .failure(400) }

        guard lines.count - 1 <= maxHeaderCount else { return .failure(431) }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" "), !line.hasPrefix("\t") else { return .failure(400) }
            let name = line[..<colon].lowercased()
            guard !name.isEmpty, name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "-_.".contains($0)) }) else {
                return .failure(400)
            }
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if let existing = headers[name] {
                // A repeated Content-Length or Host is a smuggling or confusion attempt.
                if name == "content-length" || name == "host" { return .failure(400) }
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }
        guard headers["host"] != nil || version == "HTTP/1.0" else { return .failure(400) }

        let limit = maxBody(components.path)
        let bodyStart = end.upperBound
        let body: Data
        let consumed: Int
        if let encoding = headers["transfer-encoding"] {
            guard headers["content-length"] == nil, encoding.lowercased() == "chunked" else { return .failure(400) }
            switch decodeChunked(buffer[bodyStart...], limit: limit) {
            case .needMore: return .needMore
            case .failure(let status): return .failure(status)
            case .done(let data, let used): body = data; consumed = bodyStart - buffer.startIndex + used
            }
        } else if let lengthText = headers["content-length"] {
            guard let length = Int(lengthText), length >= 0 else { return .failure(400) }
            guard length <= limit else { return .failure(413) }
            guard buffer.endIndex - bodyStart >= length else { return .needMore }
            body = Data(buffer[bodyStart..<(bodyStart + length)])
            consumed = bodyStart - buffer.startIndex + length
        } else {
            body = Data()
            consumed = bodyStart - buffer.startIndex
        }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil { query[item.name] = item.value ?? "" }
        let connection = headers["connection"]?.lowercased() ?? ""
        let wantsClose = version == "HTTP/1.0" ? !connection.contains("keep-alive") : connection.contains("close")
        let request = HTTPRequest(method: method, path: components.path, query: query, headers: headers, body: body,
                                  wantsClose: wantsClose)
        return .request(request, consumed: consumed)
    }

    private enum Chunked { case needMore, failure(Int), done(Data, Int) }

    private static func decodeChunked(_ data: Data, limit: Int) -> Chunked {
        var body = Data()
        var index = data.startIndex
        while true {
            guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex) else {
                return data.endIndex - index > 64 ? .failure(400) : .needMore
            }
            let sizeText = String(decoding: data[index..<lineEnd.lowerBound], as: UTF8.self)
                .split(separator: ";", maxSplits: 1).first.map(String.init) ?? ""
            guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size >= 0 else { return .failure(400) }
            index = lineEnd.upperBound
            if size == 0 {
                // Trailers (ignored) end with an empty line.
                guard let trailerEnd = data.range(of: crlf, in: index..<data.endIndex) else { return .needMore }
                if trailerEnd.lowerBound == index { return .done(body, trailerEnd.upperBound - data.startIndex) }
                guard let end = data.range(of: headerEnd, in: index..<data.endIndex) else { return .needMore }
                return .done(body, end.upperBound - data.startIndex)
            }
            guard body.count + size <= limit else { return .failure(413) }
            guard data.endIndex - index >= size + 2 else { return .needMore }
            body.append(data[index..<(index + size)])
            guard data[(index + size)..<(index + size + 2)] == crlf else { return .failure(400) }
            index += size + 2
        }
    }
}

// MARK: - Server

/// Listens on 127.0.0.1 only and hands complete requests to `onRequest` (on the server's queue).
final class HTTPServer: @unchecked Sendable {
    let queue = DispatchQueue(label: "org.superpaste.mcp.http")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    static let maxConnections = 32
    /// The body limit for a path.
    let maxBody: (String) -> Int
    /// Called on `queue` for every complete request.
    var onRequest: ((HTTPRequest, HTTPConnection) -> Void)?

    init(maxBody: @escaping (String) -> Int) {
        self.maxBody = maxBody
        queue.setSpecific(key: Self.queueKey, value: ObjectIdentifier(self))
    }

    private static let queueKey = DispatchSpecificKey<ObjectIdentifier>()

    /// Runs `work` on the queue, inline when already there.
    func onQueue(_ work: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self) { work() } else { queue.async(execute: work) }
    }

    enum Event { case ready(port: Int), failed(String) }

    /// Starts listening on 127.0.0.1:`port` (0 picks a free port). `onEvent` is called on `queue`.
    func start(port: Int, onEvent: @escaping (Event) -> Void) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else { throw POSIXError(.EINVAL) }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: nwPort)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        let released = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                onEvent(.ready(port: Int(listener?.port?.rawValue ?? 0)))
            case .failed(let error):
                onEvent(.failed(error.localizedDescription))
                self?.stop()
            case .cancelled:
                released.signal()
            default:
                break
            }
        }
        queue.sync {
            self.listener = listener
            self.listenerReleased = released
        }
        listener.start(queue: queue)
    }

    /// Stops listening and drops every connection; returns once the listener is cancelled.
    func stop() {
        var released: DispatchSemaphore?
        let work = {
            released = self.listener == nil ? nil : self.listenerReleased
            self.listener?.cancel()
            self.listener = nil
            let open = Array(self.connections.values)
            self.connections.removeAll()
            for connection in open { connection.close() }
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) == ObjectIdentifier(self) {
            work()
        } else {
            queue.sync(execute: work)
            // Wait for the socket to be released, so the port can be listened on again right away.
            _ = released?.wait(timeout: .now() + 2)
        }
    }

    /// Signalled when the current listener, once cancelled, has let go of its port.
    private var listenerReleased: DispatchSemaphore?

    private func accept(_ nw: NWConnection) {
        guard connections.count < Self.maxConnections else { nw.cancel(); return }
        let connection = HTTPConnection(nw, server: self)
        connections[ObjectIdentifier(connection)] = connection
        connection.start()
    }

    func closed(_ connection: HTTPConnection) {
        connections[ObjectIdentifier(connection)] = nil
    }
}

/// One client connection. Requests are handled one at a time; a response either completes the request (and the
/// connection waits for the next one) or turns the connection into an event stream until it closes.
final class HTTPConnection: @unchecked Sendable {
    private let nw: NWConnection
    private weak var server: HTTPServer?
    private let queue: DispatchQueue
    private var buffer = Data()
    private var handling = false
    private var streaming = false
    private var isClosed = false
    private var idleTimer: DispatchWorkItem?
    private var keepAliveTimer: DispatchSourceTimer?
    /// Called once when the connection ends (event streams use it to unregister).
    var onClose: (() -> Void)?
    static let idleTimeout: TimeInterval = 30
    static let keepAliveInterval: TimeInterval = 20

    init(_ nw: NWConnection, server: HTTPServer) {
        self.nw = nw
        self.server = server
        queue = server.queue
    }

    func start() {
        nw.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        nw.start(queue: queue)
        armIdleTimer()
        receive()
    }

    private func receive() {
        nw.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            // On an event stream the client has nothing more to say; reading only notices it going away.
            if let data, !data.isEmpty, !self.streaming {
                self.buffer.append(data)
                self.processBuffer()
            }
            if error != nil || (isComplete && !self.handling) {
                self.close()
            } else if isComplete {
                self.pendingClose = true  // the client finished sending: answer, then close
            } else if self.streaming || !self.handling {
                self.receive()
            }
        }
    }

    private func processBuffer() {
        guard !handling, !streaming, !isClosed, !buffer.isEmpty, let server else { return }
        switch HTTPParser.parse(buffer, maxBody: server.maxBody) {
        case .needMore:
            if buffer.count > HTTPParser.maxHeaderBytes + 8 * 1024 * 1024 { finish(.text("Too large", status: 413), close: true) }
        case .failure(let status):
            finish(.text(HTTPResponse.reason(status), status: status), close: true)
        case .request(let request, let consumed):
            buffer.removeFirst(consumed)
            handling = true
            idleTimer?.cancel()
            pendingClose = request.wantsClose
            server.onRequest?(request, self)
        }
    }

    private var pendingClose = false

    /// Sends a complete response; thread-safe.
    func respond(_ response: HTTPResponse) {
        queue.async { self.finish(response, close: self.pendingClose) }
    }

    private func finish(_ response: HTTPResponse, close: Bool) {
        guard !isClosed else { return }
        let data = response.head(contentLength: response.body.count, close: close) + response.body
        // A closing response ends with FIN, so everything is delivered before the connection goes away.
        nw.send(content: data, contentContext: close ? .finalMessage : .defaultMessage, isComplete: close,
                completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            if close {
                self.close()
            } else {
                self.handling = false
                self.armIdleTimer()
                self.processBuffer()
                if !self.handling { self.receive() }
            }
        })
    }

    /// Starts an event stream: the head without a length, then `send(event:)` until either side closes. Comments
    /// keep idle proxies and clients from timing out.
    func startStream(_ response: HTTPResponse, keepAlive: Bool) {
        queue.async {
            guard !self.isClosed else { return }
            self.streaming = true
            self.handling = false
            self.idleTimer?.cancel()
            self.nw.send(content: response.head(contentLength: nil, close: true) + response.body,
                         completion: .contentProcessed { _ in })
            // A one-shot stream (a POST answered as events) ends by itself; a long-lived one watches for the client
            // going away.
            guard keepAlive else { return }
            self.receive()
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.keepAliveInterval, repeating: Self.keepAliveInterval)
            timer.setEventHandler { [weak self] in self?.sendRaw(Data(": keep-alive\n\n".utf8)) }
            timer.resume()
            self.keepAliveTimer = timer
        }
    }

    /// One SSE `message` event carrying a JSON-RPC message.
    func send(event: JSON) {
        queue.async { self.sendRaw(Data("event: message\ndata: \(event.text)\n\n".utf8)) }
    }

    private func sendRaw(_ data: Data) {
        guard !isClosed else { return }
        nw.send(content: data, completion: .contentProcessed { [weak self] error in if error != nil { self?.close() } })
    }

    /// Ends a stream after what was queued has been sent.
    func endStream() {
        queue.async {
            guard !self.isClosed else { return }
            self.nw.send(content: nil, contentContext: .finalMessage, isComplete: true,
                         completion: .contentProcessed { [weak self] _ in self?.close() })
        }
    }

    /// Closes now (or as soon as the queue is free); safe to call more than once and from any queue.
    func close() {
        let work = {
            guard !self.isClosed else { return }
            self.isClosed = true
            self.idleTimer?.cancel()
            self.keepAliveTimer?.cancel()
            self.nw.cancel()
            self.server?.closed(self)
            self.onClose?()
            self.onClose = nil
        }
        if let server { server.onQueue(work) } else { queue.async(execute: work) }
    }

    private func armIdleTimer() {
        idleTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in
            guard let self, !self.handling, !self.streaming else { return }
            self.close()
        }
        idleTimer = timer
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: timer)
    }
}
