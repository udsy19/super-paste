import Foundation
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore). The server stays off
/// until the app starts it (when `isMCPEnabled` is on).
public enum MCPKitModule {
    @MainActor public static func install() {
        Services.mcp = MCPServer()
    }
}
