import AppKit
import Combine

// Service contracts between modules (the store's are in Store.swift). Each protocol has one owning module, which
// registers its implementation in `Services` from `<Module>Module.install()`; everyone else only calls through it.

// MARK: - Clipboard monitoring (ClipboardKit)

public enum PauseState: Equatable, Sendable {
    case running
    /// Captures are skipped until the date, or until `resume()` when nil.
    case paused(until: Date?)
}

/// Watches the general pasteboard and saves every copy to the store (behaviour.md §2). Ignored apps and types come
/// from `Defaults[.ignoredBundleIdentifiers]` / `[.ignoredPasteboardTypes]`, read live.
@MainActor
public protocol ClipboardMonitoring: AnyObject {
    /// Starts polling (0.25 s, then a 0.3 s settle before reading). Content already on the pasteboard at launch is
    /// not captured again.
    func start()
    var pauseState: PauseState { get }
    var pauseChanges: AnyPublisher<PauseState, Never> { get }
    /// Pauses capturing until `date` (nil: until resumed). Pauses don't survive relaunch.
    func pause(until date: Date?)
    func resume()
    /// Every capture after the store saved it, new or moved to the front.
    var captures: AnyPublisher<ClipItem, Never> { get }
}

public extension ClipboardMonitoring {
    var isPaused: Bool { pauseState != .running }
}

// MARK: - Pasting (ClipboardKit)

/// The app a paste goes to.
public struct PasteTarget: Hashable, Sendable {
    public var bundleID: String?
    public var name: String
    public var processID: pid_t

    public init(bundleID: String?, name: String, processID: pid_t) {
        self.bundleID = bundleID; self.name = name; self.processID = processID
    }
}

public struct PasteStackState: Equatable, Sendable {
    public var isActive: Bool
    /// Snippets in the order they were copied.
    public var items: [ClipItem]
    public var direction: StackDirection

    public init(isActive: Bool = false, items: [ClipItem] = [], direction: StackDirection = .top) {
        self.isActive = isActive; self.items = items; self.direction = direction
    }
}

/// Writing items back (behaviour.md §3). Everything written carries `PasteboardType.itemID` and Super Paste's
/// `org.nspasteboard.source`, minus `PasteboardType.banned`.
@MainActor
public protocol Pasting: AnyObject {
    /// The app a paste goes to: the most recent frontmost app other than Super Paste ("Paste to %@"); nil when
    /// unknown ("current app").
    var target: PasteTarget? { get }
    /// Pastes: hides the strip, writes `items` to the general pasteboard and, when `isDirectPasteEnabled` is on and
    /// Accessibility is granted, activates `target` and sends ⌘V (asking first through `Services.permissions` when
    /// Accessibility is missing). Otherwise it only copies and shows "Copied". Plain text when `plainText` or
    /// `isPasteAsPlainTextEnabled`. Several items: texts join with newlines; mixed kinds paste one after another.
    func paste(_ items: [ClipItem], plainText: Bool)
    /// Writes `items` to the general pasteboard only (Copy, ⌘C). Showing "Copied" is the caller's choice.
    func copy(_ items: [ClipItem], plainText: Bool)
    /// Pasteboard writers for drag-out and sharing, with the same content `copy` writes.
    func pasteboardWriters(for items: [ClipItem], plainText: Bool) -> [NSPasteboardWriting]

    // Paste Stack (behaviour.md §3.6). StripKit shows the panel by observing `pasteStackChanges`.
    var pasteStack: PasteStackState { get }
    var pasteStackChanges: AnyPublisher<PasteStackState, Never> { get }
    /// Opens the stack: every copy is appended and ⌘V is taken over (globally) to paste the next snippet.
    func startPasteStack()
    /// Closes the stack, empties it and releases ⌘V.
    func stopPasteStack()
    /// Pastes the next snippet (from the top or bottom, per direction) and removes it from the stack.
    func pasteNextFromStack()
    func removeFromPasteStack(_ ids: [UUID])
    func setPasteStackDirection(_ direction: StackDirection)
}

public extension Pasting {
    var isPasteStackActive: Bool { pasteStack.isActive }
    func togglePasteStack() { isPasteStackActive ? stopPasteStack() : startPasteStack() }
}

// MARK: - Strip (StripKit)

/// What to show when the strip opens (also the `superpaste://` strip routes).
public enum StripRoute: Hashable, Sendable {
    case list(ListScope)
    /// Opens with this search text (`SearchQuery` syntax).
    case search(String)
    /// Opens on the item's list with its preview showing.
    case preview(UUID)
    /// Opens the item's preview in edit mode.
    case edit(UUID)
    /// The New Text Item window (⌘N).
    case newTextItem
}

/// The bottom-of-screen panel (behaviour.md §4).
@MainActor
public protocol StripPresenting: AnyObject {
    var isVisible: Bool { get }
    var visibilityChanges: AnyPublisher<Bool, Never> { get }
    /// Shows the strip on the active screen; nil restores where it was (selected list and focus).
    func show(_ route: StripRoute?)
    func hide()
    /// Shows when hidden, hides when shown (the activation shortcut, a status item click).
    func toggle()
}

// MARK: - Settings, onboarding, permissions (SettingsKit)

public enum SettingsPane: String, Codable, CaseIterable, Sendable {
    case general, privacy, shortcuts, sync, integrations, about
}

@MainActor
public protocol SettingsPresenting: AnyObject {
    /// Opens Settings and brings it forward; nil keeps the pane shown last.
    func show(pane: SettingsPane?)
    /// Registers or removes the login item (behaviour.md §1.5) and updates `Defaults[.openAtLogin]`; for the strip's
    /// Open at Login notification and `superpaste://enable-open-at-login`.
    func setOpenAtLogin(_ enabled: Bool)
}

@MainActor
public protocol OnboardingPresenting: AnyObject {
    /// `Defaults[.isOnboardingCompleted]`.
    var isCompleted: Bool { get }
    /// Shows Introduction → Quick Start; Continue completes it (behaviour.md §8).
    func show()
}

/// The answer to "Do you want to paste directly to %@?" (behaviour.md §3.1).
public enum DirectPasteChoice: Sendable {
    case enableAccessibility
    case copyToClipboard
    /// Also sets `isDirectPastePromptSuppressed`.
    case copyToClipboardAndDontAskAgain
}

/// Permission screens (behaviour.md §9).
@MainActor
public protocol PermissionsPresenting: AnyObject {
    /// Asks whether to paste directly into `appName` (nil: "current app") when Accessibility is missing.
    func requestDirectPaste(into appName: String?, completion: @escaping @MainActor (DirectPasteChoice) -> Void)
    /// The "Paste to Any App" screen: opens System Settings and waits for the grant.
    func showAccessibilityAccess()
    /// The "Allow Pasteboard Access" screen (macOS 26 pasteboard privacy).
    func showPasteboardAccess()
}

// MARK: - Sync (SyncKit)

public enum SyncStatus: Equatable, Sendable {
    case disabled
    case syncing
    /// Idle and up to date as of the date (nil: never synced yet).
    case synced(Date?)
    case error(String)
}

/// End-to-end-encrypted sync through a folder the user picks (behaviour.md §17 replacement).
@MainActor
public protocol SyncServicing: AnyObject {
    var status: SyncStatus { get }
    var statusChanges: AnyPublisher<SyncStatus, Never> { get }
    /// The sync folder while enabled.
    var folder: URL? { get }
    /// Where sync suggests putting its data ("Super Paste" in iCloud Drive), when iCloud Drive is available.
    var defaultFolder: URL? { get }
    /// Starts syncing through `folder` (creating or joining the Super Paste data in it).
    func enable(folder: URL) throws
    /// Stops syncing; local and folder data stay as they are.
    func disable()
    func syncNow()
    /// The encryption key as text, for moving it to another Mac by hand.
    func exportKey() -> String?
    func importKey(_ text: String) throws
}

// MARK: - MCP (MCPKit)

public enum MCPServerState: Equatable, Sendable {
    case off
    case starting
    /// Listening on 127.0.0.1; the URL is the `/mcp` endpoint.
    case running(URL)
    case failed(String)
}

/// How a client authenticates.
public enum MCPConnection: String, Codable, Sendable {
    /// Registered itself (dynamic client registration) and was approved on the consent page.
    case oauth
    /// Added by hand with a static bearer token (also the stdio bridge).
    case token
}

public struct MCPClientInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// The name the client registered with (or the name given to a token client).
    public var name: String
    public var connection: MCPConnection
    public var createdAt: Date
    public var lastUsedAt: Date?

    public init(id: UUID = UUID(), name: String, connection: MCPConnection, createdAt: Date = Date(), lastUsedAt: Date? = nil) {
        self.id = id; self.name = name; self.connection = connection; self.createdAt = createdAt; self.lastUsedAt = lastUsedAt
    }
}

/// The local MCP server (behaviour.md §14).
@MainActor
public protocol MCPServing: AnyObject {
    var state: MCPServerState { get }
    var stateChanges: AnyPublisher<MCPServerState, Never> { get }
    /// `Defaults[.mcpPort]`.
    var port: Int { get }
    func start()
    func stop()
    /// Restarts on the new port and disconnects every client; on failure goes back to the old port and throws.
    func changePort(to port: Int) throws
    var clients: [MCPClientInfo] { get }
    var clientChanges: AnyPublisher<[MCPClientInfo], Never> { get }
    /// Adds a token client ("Custom"); the token is returned once and only its hash is kept.
    func addTokenClient(name: String) throws -> (client: MCPClientInfo, token: String)
    /// Disconnects a client and forgets its tokens.
    func revoke(_ clientID: UUID)
}

public extension MCPServing {
    var isRunning: Bool { if case .running = state { true } else { false } }
}

// MARK: - Updates (UpdateKit)

@MainActor
public protocol Updating: AnyObject {
    /// Starts the background check/stage/install cycle (a no-op outside a properly signed app bundle).
    func start()
}
