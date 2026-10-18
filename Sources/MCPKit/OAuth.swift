import Foundation
import CryptoKit
import SuperPasteCore

/// Proof Key for Code Exchange (RFC 7636), S256 only.
public enum PKCE {
    /// BASE64URL(SHA256(verifier)).
    public static func challenge(for verifier: String) -> String {
        MCPSecrets.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// 43–128 characters from the unreserved set.
    public static func isValidVerifier(_ verifier: String) -> Bool {
        (43...128).contains(verifier.count) && verifier.allSatisfy(isUnreserved)
    }

    /// A SHA-256 in unpadded Base64URL: 43 characters.
    public static func isValidChallenge(_ challenge: String) -> Bool {
        challenge.count == 43 && challenge.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public static func verify(verifier: String, challenge: String) -> Bool {
        isValidVerifier(verifier) && MCPSecrets.constantTimeEquals(Self.challenge(for: verifier), challenge)
    }

    private static func isUnreserved(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber || "-._~".contains(c))
    }
}

/// Which redirect URIs a client may register: https anywhere, http only to this Mac (RFC 8252 loopback redirects),
/// and private-use schemes of native apps. Never script, data or file URLs.
public enum RedirectPolicy {
    static let refusedSchemes: Set<String> = ["javascript", "data", "file", "vbscript", "about", "blob", "filesystem", "ftp"]

    public static func isAllowed(_ uri: String) -> Bool {
        guard uri.count <= 2_048, !uri.contains(where: { $0.isWhitespace || $0.asciiValue.map { $0 < 0x20 || $0 == 0x7F } == true }),
              let components = URLComponents(string: uri), let scheme = components.scheme?.lowercased(),
              components.fragment == nil,
              scheme.first?.isLetter == true, scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+.-".contains($0)) })
        else { return false }
        switch scheme {
        case "https":
            return !(components.host ?? "").isEmpty
        case "http":
            return ["127.0.0.1", "localhost", "::1", "[::1]"].contains((components.host ?? "").lowercased())
        default:
            return !refusedSchemes.contains(scheme)
        }
    }

    /// The CSP source that lets the consent form's redirect reach `uri`.
    static func formActionSource(_ uri: String) -> String? {
        guard let components = URLComponents(string: uri), let scheme = components.scheme?.lowercased() else { return nil }
        guard scheme == "http" || scheme == "https", let host = components.host else { return scheme + ":" }
        let hostPart = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return "\(scheme)://\(hostPart)" + (components.port.map { ":\($0)" } ?? "")
    }
}

/// The OAuth 2.1 authorization server built into the MCP server (behaviour.md §14.1): metadata, dynamic client
/// registration, the consent page, the token and revocation endpoints. Codes and pending consents live only in
/// memory; registrations and token hashes in `ClientRegistry`.
@MainActor
final class OAuthService {
    private let registry: ClientRegistry
    /// Disconnects a client everywhere (`/revoke`).
    private let revokeClient: (UUID) -> Void
    private var consents: [String: Consent] = [:]
    private var codes: [String: Grant] = [:]
    static let consentLifetime: TimeInterval = 600
    static let codeLifetime: TimeInterval = 300
    static let maxPending = 50

    private struct Consent {
        var clientID: String
        var redirectURI: String
        /// Whether the request named the redirect URI; the token request must then repeat it.
        var redirectGiven: Bool
        var challenge: String
        var state: String?
        var csrf: String
        var created: Date
    }

    private struct Grant {
        var clientID: String
        var redirectURI: String
        var redirectGiven: Bool
        var challenge: String
        var created: Date
    }

    init(registry: ClientRegistry, revokeClient: @escaping (UUID) -> Void) {
        self.registry = registry
        self.revokeClient = revokeClient
    }

    /// Forgets every pending consent and unused code (the port changed).
    func reset() {
        consents = [:]
        codes = [:]
    }

    // MARK: Metadata

    /// RFC 9728: the MCP endpoint and who issues tokens for it.
    func protectedResourceMetadata(base: String) -> JSON {
        ["resource": .string(base + "/mcp"), "authorization_servers": [.string(base)], "bearer_methods_supported": ["header"],
         "resource_name": "Super Paste"]
    }

    /// RFC 8414.
    func authorizationServerMetadata(base: String) -> JSON {
        let methods: JSON = ["none", "client_secret_post", "client_secret_basic"]
        return [
            "issuer": .string(base),
            "authorization_endpoint": .string(base + "/authorize"),
            "token_endpoint": .string(base + "/token"),
            "registration_endpoint": .string(base + "/register"),
            "revocation_endpoint": .string(base + "/revoke"),
            "response_types_supported": ["code"],
            "response_modes_supported": ["query"],
            "grant_types_supported": ["authorization_code"],
            "code_challenge_methods_supported": ["S256"],
            "token_endpoint_auth_methods_supported": methods,
            "revocation_endpoint_auth_methods_supported": methods,
        ]
    }

    // MARK: Registration (RFC 7591)

    func register(_ request: HTTPRequest) -> HTTPResponse {
        guard let body = try? JSON(parsing: request.body), body.object != nil else {
            return oauthError("invalid_client_metadata", "The body must be a JSON object.")
        }
        let rawName = body["client_name"]?.string ?? ""
        let name = String(rawName.filter { !($0.asciiValue.map { $0 < 0x20 || $0 == 0x7F } ?? false) }
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(100))
        guard !name.isEmpty else { return oauthError("invalid_client_metadata", "client_name is required.") }
        guard let uris = body["redirect_uris"]?.array?.compactMap(\.string), !uris.isEmpty, uris.count <= 10,
              uris.count == body["redirect_uris"]?.array?.count else {
            return oauthError("invalid_redirect_uri", "redirect_uris must list one to ten URIs.")
        }
        guard uris.allSatisfy(RedirectPolicy.isAllowed) else {
            return oauthError("invalid_redirect_uri", "Redirect URIs must be https, http on this Mac, or an app's own scheme.")
        }
        if let grants = body["grant_types"], !(grants.array?.contains("authorization_code") ?? false) {
            return oauthError("invalid_client_metadata", "Only the authorization_code grant is supported.")
        }
        if let types = body["response_types"], !(types.array?.contains("code") ?? false) {
            return oauthError("invalid_client_metadata", "Only the code response type is supported.")
        }
        let method = body["token_endpoint_auth_method"]?.string ?? "none"
        guard ["none", "client_secret_post", "client_secret_basic"].contains(method) else {
            return oauthError("invalid_client_metadata", "Unsupported token_endpoint_auth_method.")
        }
        let (registration, secret) = registry.register(name: name, redirectURIs: uris, authMethod: method)
        var reply: [String: JSON] = [
            "client_id": .string(registration.clientID),
            "client_id_issued_at": .int(Int(registration.createdAt.timeIntervalSince1970)),
            "client_name": .string(name),
            "redirect_uris": .array(uris.map { .string($0) }),
            "grant_types": ["authorization_code"],
            "response_types": ["code"],
            "token_endpoint_auth_method": .string(method),
        ]
        if let secret {
            reply["client_secret"] = .string(secret)
            reply["client_secret_expires_at"] = 0
        }
        return .json(.object(reply), status: 201)
    }

    // MARK: Authorization and consent

    /// `GET /authorize`: checks the request and shows the consent page.
    func authorizePage(_ request: HTTPRequest, base: String) -> HTTPResponse {
        let q = request.query
        guard let clientID = q["client_id"], let registration = registry.registration(clientID) else {
            return ConsentPage.error("This connection request comes from an app Super Paste doesn't know. Start connecting again from the app.")
        }
        let redirectURI: String
        if let given = q["redirect_uri"] {
            guard registration.redirectURIs.contains(given) else {
                return ConsentPage.error("This connection request doesn't match how the app registered. Start connecting again from the app.")
            }
            redirectURI = given
        } else if registration.redirectURIs.count == 1 {
            redirectURI = registration.redirectURIs[0]
        } else {
            return ConsentPage.error("This connection request doesn't say where to return. Start connecting again from the app.")
        }
        // From here on, problems go back to the client.
        let state = q["state"]
        guard q["response_type"] == "code" else {
            return redirect(redirectURI, ["error": "unsupported_response_type", "state": state])
        }
        guard let challenge = q["code_challenge"], PKCE.isValidChallenge(challenge), q["code_challenge_method"] == "S256" else {
            return redirect(redirectURI, ["error": "invalid_request", "error_description": "PKCE with S256 is required.",
                                          "state": state])
        }
        if let resource = q["resource"], !Self.isOwnResource(resource, base: base) {
            return redirect(redirectURI, ["error": "invalid_target", "state": state])
        }
        prune()
        let requestID = MCPSecrets.generate(prefix: "")
        let csrf = MCPSecrets.generate(prefix: "")
        consents[requestID] = Consent(clientID: clientID, redirectURI: redirectURI, redirectGiven: q["redirect_uri"] != nil,
                                      challenge: challenge, state: state, csrf: csrf, created: Date())
        return ConsentPage.consent(clientName: registration.name, requestID: requestID, csrf: csrf,
                                   formTarget: RedirectPolicy.formActionSource(redirectURI))
    }

    /// `POST /authorize`: the user pressed Connect or Cancel.
    func authorizeDecision(_ request: HTTPRequest) -> HTTPResponse {
        if let site = request.header("sec-fetch-site"), site != "same-origin" && site != "none" {
            return ConsentPage.error("This approval didn't come from the consent page.", status: 403)
        }
        let form = request.form
        guard let requestID = form["request_id"], let consent = consents.removeValue(forKey: requestID),
              Date().timeIntervalSince(consent.created) < Self.consentLifetime else {
            return ConsentPage.error("This connection request has expired. Start connecting again from the app.")
        }
        guard let csrf = form["csrf"], MCPSecrets.constantTimeEquals(csrf, consent.csrf) else {
            return ConsentPage.error("This approval didn't come from the consent page.", status: 403)
        }
        guard registry.registration(consent.clientID) != nil else {
            return ConsentPage.error("This app was disconnected. Start connecting again from the app.")
        }
        guard form["decision"] == "approve" else {
            return redirect(consent.redirectURI, ["error": "access_denied", "state": consent.state])
        }
        let code = MCPSecrets.generate(prefix: "")
        codes[code] = Grant(clientID: consent.clientID, redirectURI: consent.redirectURI, redirectGiven: consent.redirectGiven,
                            challenge: consent.challenge, created: Date())
        return redirect(consent.redirectURI, ["code": code, "state": consent.state])
    }

    static func isOwnResource(_ resource: String, base: String) -> Bool {
        let normalized = resource.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let own = base.lowercased()
        let alternate = own.contains("://localhost:") ? own.replacingOccurrences(of: "://localhost:", with: "://127.0.0.1:")
            : own.replacingOccurrences(of: "://127.0.0.1:", with: "://localhost:")
        return [own, own + "/mcp", alternate, alternate + "/mcp"].contains(normalized)
    }

    // MARK: Token and revocation

    /// `POST /token`: the authorization_code grant with PKCE.
    func token(_ request: HTTPRequest) -> HTTPResponse {
        let form = request.form
        var clientID = form["client_id"]
        var secret = form["client_secret"]
        if let basic = Self.basicCredentials(request.header("authorization")) {
            clientID = basic.id
            secret = basic.secret
        }
        guard let clientID, let registration = registry.registration(clientID) else {
            return oauthError("invalid_client", "Unknown client.", status: 401)
        }
        if let hash = registration.secretHash {
            guard let secret, MCPSecrets.constantTimeEquals(MCPSecrets.hash(secret), hash) else {
                return oauthError("invalid_client", "Client authentication failed.", status: 401)
            }
        }
        guard form["grant_type"] == "authorization_code" else {
            return oauthError("unsupported_grant_type", "Only authorization_code is supported.")
        }
        // A code is single-use: it is gone after this request, whatever the outcome.
        guard let code = form["code"], let grant = codes.removeValue(forKey: code),
              Date().timeIntervalSince(grant.created) < Self.codeLifetime else {
            return oauthError("invalid_grant", "The code is invalid, used or expired.")
        }
        let redirectMatches = form["redirect_uri"].map { $0 == grant.redirectURI } ?? !grant.redirectGiven
        guard grant.clientID == clientID, redirectMatches else {
            return oauthError("invalid_grant", "The code was issued to another client or redirect URI.")
        }
        guard let verifier = form["code_verifier"], PKCE.verify(verifier: verifier, challenge: grant.challenge) else {
            return oauthError("invalid_grant", "PKCE verification failed.")
        }
        let (client, token) = registry.issueToken(for: registration)
        Log.mcp.info("Connected \(client.name, privacy: .public)")
        return .json(["access_token": .string(token), "token_type": "Bearer"], headers: [("Pragma", "no-cache")])
    }

    /// `POST /revoke` (RFC 7009): disconnects the client the access token belongs to. Always 200 for a well-formed
    /// request, so it says nothing about which tokens exist.
    func revoke(_ request: HTTPRequest) -> HTTPResponse {
        let form = request.form
        guard let token = form["token"] else { return oauthError("invalid_request", "token is required.") }
        if let hint = form["token_type_hint"], hint != "access_token" {
            return oauthError("unsupported_token_type", "Only access tokens can be revoked.")
        }
        if let client = registry.client(forToken: token) { revokeClient(client.id) }
        return HTTPResponse(status: 200)
    }

    // MARK: Helpers

    private func prune() {
        let now = Date()
        consents = consents.filter { now.timeIntervalSince($0.value.created) < Self.consentLifetime }
        codes = codes.filter { now.timeIntervalSince($0.value.created) < Self.codeLifetime }
        while consents.count >= Self.maxPending, let oldest = consents.min(by: { $0.value.created < $1.value.created }) {
            consents[oldest.key] = nil
        }
    }

    private static func basicCredentials(_ header: String?) -> (id: String, secret: String)? {
        guard let header, header.lowercased().hasPrefix("basic "),
              let data = Data(base64Encoded: String(header.dropFirst(6)).trimmingCharacters(in: .whitespaces)),
              let text = String(data: data, encoding: .utf8), let colon = text.firstIndex(of: ":") else { return nil }
        let decode = { (s: Substring) in String(s).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(s) }
        return (decode(text[..<colon]), decode(text[text.index(after: colon)...]))
    }

    private func oauthError(_ code: String, _ description: String, status: Int = 400) -> HTTPResponse {
        .json(["error": .string(code), "error_description": .string(description)], status: status,
              headers: [("Pragma", "no-cache")])
    }

    /// 303 to the client's redirect URI with `parameters` added to its query (nil values left out).
    private func redirect(_ uri: String, _ parameters: [String: String?]) -> HTTPResponse {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let added = parameters.sorted { $0.key < $1.key }.compactMap { name, value in
            value.map { "\(name)=\($0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
        }.joined(separator: "&")
        var target = uri
        if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
        target += (target.contains("?") ? "&" : "?") + added
        return HTTPResponse(status: 303, headers: [("Location", target)])
    }
}
