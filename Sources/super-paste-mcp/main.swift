import Foundation

// super-paste-mcp: bridges an MCP client that speaks stdio to Super Paste's local HTTP server. It reads newline-
// delimited JSON-RPC from stdin, POSTs each message to MCP_URL (Authorization: Bearer MCP_TOKEN, Accept:
// application/json, text/event-stream, carrying Mcp-Session-Id) and writes every JSON-RPC response — plain JSON or
// SSE `data:` events — to stdout, one per line (behaviour.md §14.1). Foundation only; owned by MCPKit's worker.

let environment = ProcessInfo.processInfo.environment
guard let endpoint = environment["MCP_URL"].flatMap(URL.init(string:)), environment["MCP_TOKEN"] != nil else {
    FileHandle.standardError.write(Data("super-paste-mcp: set MCP_URL and MCP_TOKEN (Super Paste → Settings → Integrations)\n".utf8))
    exit(64)
}
FileHandle.standardError.write(Data("super-paste-mcp: the bridge to \(endpoint.absoluteString) isn't implemented yet\n".utf8))
exit(69)
