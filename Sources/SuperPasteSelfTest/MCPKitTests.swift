import Foundation
import SuperPasteCore
import MCPKit

// Owned by MCPKit.
func registerMCPKitTests() {
    SelfTest.cases.append(("MCPKit.install", { MainActor.assumeIsolated {
        MCPKitModule.install()
        check(Services.mcp != nil, "MCP server registered")
    } }))
}
