import Foundation
import CryptoKit
import Security
import SuperPasteCore

/// Random secrets and how they are kept: only a SHA-256 of each bearer token or client secret is ever written to
/// disk, so the files in `SuperPastePaths.mcp` can't be used to connect. Tokens carry 256 random bits, which makes a
/// plain (unsalted, fast) hash the right tool.
public enum MCPSecrets {
    /// 32 random bytes as unpadded Base64URL with a recognisable prefix.
    public static func generate(prefix: String = "spm_") -> String { prefix + base64URL(randomBytes(32)) }

    public static func hash(_ secret: String) -> String {
        SHA256.hash(data: Data(secret.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Compares without an early exit, so the time taken says nothing about where two values differ.
    public static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        return zip(x, y).reduce(0) { $0 | ($1.0 ^ $1.1) } == 0
    }

    static func randomBytes(_ count: Int) -> Data {
        var bytes = Data(count: count)
        let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        precondition(status == errSecSuccess, "no system randomness")
        return bytes
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Connected clients and dynamic client registrations, persisted as `clients.json` and `dcr.json`
/// (behaviour.md §14.1).
@MainActor
final class ClientRegistry {
    struct StoredClient: Codable, Equatable {
        var info: MCPClientInfo
        var tokenHash: String
        /// The registration an OAuth client was approved under.
        var oauthClientID: String?
    }

    /// A client that registered itself (RFC 7591). It can't do anything until the user approves it on the consent
    /// page and it exchanges the code for a token.
    struct Registration: Codable, Equatable {
        var clientID: String
        var name: String
        var redirectURIs: [String]
        /// "none" (public client with PKCE), "client_secret_post" or "client_secret_basic".
        var authMethod: String
        var secretHash: String?
        var createdAt: Date
    }

    private let clientsFile: URL
    private let registrationsFile: URL
    private(set) var clients: [StoredClient]
    private(set) var registrations: [String: Registration]
    /// Called after every change to `clients`.
    var onChange: (([MCPClientInfo]) -> Void)?
    static let maxRegistrations = 100
    /// Registrations nobody approved are forgotten after a day.
    static let unapprovedLifetime: TimeInterval = 86_400
    /// `lastUsedAt` is written to disk at most this often per client.
    static let lastUsedResolution: TimeInterval = 60

    init(directory: URL) {
        clientsFile = directory.appendingPathComponent("clients.json")
        registrationsFile = directory.appendingPathComponent("dcr.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        clients = (try? Data(contentsOf: clientsFile)).flatMap { try? decoder.decode([StoredClient].self, from: $0) } ?? []
        registrations = (try? Data(contentsOf: registrationsFile))
            .flatMap { try? decoder.decode([String: Registration].self, from: $0) } ?? [:]
    }

    var infos: [MCPClientInfo] { clients.map(\.info) }

    // MARK: Tokens

    /// A hand-made client with a static bearer token; the token is returned once.
    func addTokenClient(name: String) -> (MCPClientInfo, String) {
        let token = MCPSecrets.generate()
        let info = MCPClientInfo(name: name, connection: .token)
        clients.append(StoredClient(info: info, tokenHash: MCPSecrets.hash(token)))
        saveClients()
        return (info, token)
    }

    /// The access token for an approved registration. A client that authorizes again keeps its entry and gets a new
    /// token (the old one stops working).
    func issueToken(for registration: Registration) -> (MCPClientInfo, String) {
        let token = MCPSecrets.generate()
        if let index = clients.firstIndex(where: { $0.oauthClientID == registration.clientID }) {
            clients[index].tokenHash = MCPSecrets.hash(token)
            clients[index].info.name = registration.name
            saveClients()
            return (clients[index].info, token)
        }
        let info = MCPClientInfo(name: registration.name, connection: .oauth)
        clients.append(StoredClient(info: info, tokenHash: MCPSecrets.hash(token), oauthClientID: registration.clientID))
        saveClients()
        return (info, token)
    }

    /// The client a bearer token belongs to; records the use.
    func authenticate(_ token: String, now: Date = Date()) -> MCPClientInfo? {
        let hash = MCPSecrets.hash(token)
        guard let index = clients.firstIndex(where: { MCPSecrets.constantTimeEquals($0.tokenHash, hash) }) else { return nil }
        let last = clients[index].info.lastUsedAt
        clients[index].info.lastUsedAt = now
        if last.map({ now.timeIntervalSince($0) >= Self.lastUsedResolution }) ?? true { saveClients() }
        return clients[index].info
    }

    /// Forgets a client, its token and its registration. Returns whether it existed.
    @discardableResult func revoke(_ clientID: UUID) -> Bool {
        guard let index = clients.firstIndex(where: { $0.info.id == clientID }) else { return false }
        let removed = clients.remove(at: index)
        if let registration = removed.oauthClientID {
            registrations[registration] = nil
            saveRegistrations()
        }
        saveClients()
        return true
    }

    /// The client a token belongs to, without recording a use (for `/revoke`).
    func client(forToken token: String) -> MCPClientInfo? {
        let hash = MCPSecrets.hash(token)
        return clients.first { MCPSecrets.constantTimeEquals($0.tokenHash, hash) }?.info
    }

    func removeAll() {
        clients = []
        registrations = [:]
        saveClients()
        saveRegistrations()
    }

    // MARK: Registrations

    func register(name: String, redirectURIs: [String], authMethod: String, now: Date = Date()) -> (Registration, String?) {
        pruneRegistrations(now: now)
        let secret = authMethod == "none" ? nil : MCPSecrets.generate(prefix: "sps_")
        let registration = Registration(clientID: MCPSecrets.generate(prefix: "spc_"), name: name, redirectURIs: redirectURIs,
                                        authMethod: authMethod, secretHash: secret.map(MCPSecrets.hash), createdAt: now)
        registrations[registration.clientID] = registration
        saveRegistrations()
        return (registration, secret)
    }

    func registration(_ clientID: String) -> Registration? { registrations[clientID] }

    /// Drops registrations nobody approved within a day, and the oldest unapproved ones beyond the cap.
    private func pruneRegistrations(now: Date) {
        let approved = Set(clients.compactMap(\.oauthClientID))
        var unapproved = registrations.values.filter { !approved.contains($0.clientID) }
        for registration in unapproved where now.timeIntervalSince(registration.createdAt) > Self.unapprovedLifetime {
            registrations[registration.clientID] = nil
        }
        unapproved = registrations.values.filter { !approved.contains($0.clientID) }.sorted { $0.createdAt < $1.createdAt }
        for registration in unapproved.prefix(max(0, unapproved.count - Self.maxRegistrations + 1)) {
            registrations[registration.clientID] = nil
        }
    }

    // MARK: Persistence

    private func saveClients() {
        write(clients, to: clientsFile)
        onChange?(infos)
    }

    private func saveRegistrations() { write(registrations, to: registrationsFile) }

    private func write<T: Encodable>(_ value: T, to file: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(value).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch {
            Log.mcp.error("Couldn't save \(file.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}
