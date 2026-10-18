import Foundation
import Combine
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore).
public enum MCPKitModule {
    @MainActor public static func install() {
        Services.mcp = PlaceholderMCP()
    }
}

/// Stand-in until the MCP server lands: always off. Delete it when `install()` registers the real server.
@MainActor
final class PlaceholderMCP: MCPServing {
    private struct NotImplemented: LocalizedError {
        var errorDescription: String? { "The MCP server isn't implemented yet." }
    }

    var state: MCPServerState { .off }
    var stateChanges: AnyPublisher<MCPServerState, Never> { Just(.off).eraseToAnyPublisher() }
    var port: Int { Defaults[.mcpPort] }
    func start() { Log.mcp.info("The MCP server isn't implemented yet") }
    func stop() {}
    func changePort(to port: Int) throws { throw NotImplemented() }
    var clients: [MCPClientInfo] { [] }
    var clientChanges: AnyPublisher<[MCPClientInfo], Never> { Just([]).eraseToAnyPublisher() }
    func addTokenClient(name: String) throws -> (client: MCPClientInfo, token: String) { throw NotImplemented() }
    func revoke(_ clientID: UUID) {}
}
