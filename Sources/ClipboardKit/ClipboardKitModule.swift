import AppKit
import Combine
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore).
public enum ClipboardKitModule {
    @MainActor public static func install() {
        let clipboard = PlaceholderClipboard()
        Services.clipboard = clipboard
        Services.pasting = clipboard
    }
}

/// Stand-in until monitoring and pasting land: captures nothing, pastes nothing. Delete it when `install()`
/// registers the real services.
@MainActor
final class PlaceholderClipboard: ClipboardMonitoring, Pasting {
    func start() { Log.clipboard.info("Clipboard monitoring isn't implemented yet") }
    var pauseState: PauseState { .running }
    var pauseChanges: AnyPublisher<PauseState, Never> { Just(.running).eraseToAnyPublisher() }
    func pause(until date: Date?) {}
    func resume() {}
    var captures: AnyPublisher<ClipItem, Never> { Empty().eraseToAnyPublisher() }

    var target: PasteTarget? { nil }
    func paste(_ items: [ClipItem], plainText: Bool) {}
    func copy(_ items: [ClipItem], plainText: Bool) {}
    func pasteboardWriters(for items: [ClipItem], plainText: Bool) -> [NSPasteboardWriting] { [] }
    var pasteStack: PasteStackState { PasteStackState() }
    var pasteStackChanges: AnyPublisher<PasteStackState, Never> { Just(PasteStackState()).eraseToAnyPublisher() }
    func startPasteStack() {}
    func stopPasteStack() {}
    func pasteNextFromStack() {}
    func removeFromPasteStack(_ ids: [UUID]) {}
    func setPasteStackDirection(_ direction: StackDirection) {}
}
