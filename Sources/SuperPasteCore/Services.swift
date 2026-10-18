import Foundation

/// Late-bound registry: each module's `install()` assigns its implementations at launch, in the order the app
/// target calls them (see Sources/SuperPaste/main.swift). Modules call each other only through these.
@MainActor
public enum Services {
    /// ClipStore.
    public static var store: ItemStoring!
    /// ClipStore (the same object as `store`).
    public static var syncStore: SyncStoring!
    /// ClipboardKit.
    public static var clipboard: ClipboardMonitoring!
    /// ClipboardKit.
    public static var pasting: Pasting!
    /// StripKit.
    public static var strip: StripPresenting!
    /// SettingsKit.
    public static var settings: SettingsPresenting!
    /// SettingsKit.
    public static var onboarding: OnboardingPresenting!
    /// SettingsKit.
    public static var permissions: PermissionsPresenting!
    /// SyncKit.
    public static var sync: SyncServicing!
    /// MCPKit.
    public static var mcp: MCPServing!
    /// UpdateKit.
    public static var updates: Updating!
}

/// Where Super Paste keeps its files: ~/Library/Application Support/Super Paste/.
public enum SuperPastePaths {
    public static let bundleID = Bundle.main.bundleIdentifier ?? "com.udsy.superpaste"
    /// The folder `support` lives in: Application Support. The self-test points it at a temporary folder so it never
    /// creates or touches the real one.
    nonisolated(unsafe) public static var base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    public static let supportFolderName = "Super Paste"
    public static var support: URL { ensure(base.appendingPathComponent(supportFolderName, isDirectory: true)) }
    /// The SQLite database (with -wal and -shm next to it).
    public static var database: URL { support.appendingPathComponent("clips.sqlite") }
    /// Content-addressed blob files, `Blobs/<first two hex digits>/<digest>`.
    public static var blobs: URL { ensure(support.appendingPathComponent("Blobs", isDirectory: true)) }
    /// Local sync state (cursors, the folder's last-seen manifests). The shared folder itself is chosen by the user.
    public static var sync: URL { ensure(support.appendingPathComponent("Sync", isDirectory: true)) }
    /// MCP clients (token hashes) and dynamic client registrations.
    public static var mcp: URL { ensure(support.appendingPathComponent("MCP", isDirectory: true)) }
    /// A damaged database is moved here before starting over.
    public static var backup: URL { ensure(support.appendingPathComponent("Backup", isDirectory: true)) }

    @discardableResult public static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
