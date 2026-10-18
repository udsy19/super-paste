import Foundation

/// The MCP client configuration snippets the Integrations pane shows (behaviour.md §14.4, "custom" kind): the server
/// URL for clients that sign in through the browser (OAuth), and with a token for the stdio bridge.
public enum MCPConfig {
    public static let serverName = "super-paste"

    /// The `/mcp` endpoint on this Mac.
    public static func serverURL(port: Int) -> URL { URL(string: "http://127.0.0.1:\(port)/mcp")! }

    /// The stdio bridge inside the app bundle (`Contents/MacOS/super-paste-mcp`).
    public static var bridgePath: String {
        let folder = Bundle.main.executableURL?.deletingLastPathComponent()
            ?? URL(fileURLWithPath: "/Applications/Super Paste.app/Contents/MacOS")
        return folder.appendingPathComponent("super-paste-mcp").path
    }

    /// A valid new port typed in the field (1024…65535), if it differs from the current one.
    public static func newPort(from text: String, current: Int) -> Int? {
        guard let port = Int(text.trimmingCharacters(in: .whitespaces)), (1024...65535).contains(port), port != current
        else { return nil }
        return port
    }

    /// `{"mcpServers": {"super-paste": {"url": …}}}`
    public static func httpSnippet(url: URL) -> String {
        json(["url": .string(url.absoluteString)])
    }

    /// The stdio bridge with the token in its environment (`MCP_URL`, `MCP_TOKEN`).
    public static func stdioSnippet(url: URL, token: String, bridge: String = bridgePath) -> String {
        json(["command": .string(bridge),
              "env": .object([("MCP_URL", url.absoluteString), ("MCP_TOKEN", token)])])
    }

    private enum Value {
        case string(String)
        case object([(String, String)])
    }

    /// Two-space indented JSON with keys in the given order (JSONSerialization neither keeps order nor writes
    /// `"key": value` the way configs are usually written).
    private static func json(_ server: KeyValuePairs<String, Value>) -> String {
        var lines = ["{", "  \"mcpServers\": {", "    \(quote(serverName)): {"]
        for (index, (key, value)) in server.enumerated() {
            let comma = index == server.count - 1 ? "" : ","
            switch value {
            case .string(let text):
                lines.append("      \(quote(key)): \(quote(text))\(comma)")
            case .object(let pairs):
                lines.append("      \(quote(key)): {")
                for (inner, (name, text)) in pairs.enumerated() {
                    lines.append("        \(quote(name)): \(quote(text))\(inner == pairs.count - 1 ? "" : ",")")
                }
                lines.append("      }\(comma)")
            }
        }
        lines += ["    }", "  }", "}"]
        return lines.joined(separator: "\n")
    }

    private static func quote(_ text: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(text)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
}
