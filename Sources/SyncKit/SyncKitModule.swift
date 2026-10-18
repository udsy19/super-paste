import Foundation
import Combine
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after ClipStore).
public enum SyncKitModule {
    @MainActor public static func install() {
        Services.sync = PlaceholderSync()
    }
}

/// Stand-in until folder sync lands: always off. Delete it when `install()` registers the real service.
@MainActor
final class PlaceholderSync: SyncServicing {
    private struct NotImplemented: LocalizedError {
        var errorDescription: String? { "Folder sync isn't implemented yet." }
    }

    var status: SyncStatus { .disabled }
    var statusChanges: AnyPublisher<SyncStatus, Never> { Just(.disabled).eraseToAnyPublisher() }
    var folder: URL? { nil }
    func enable(folder: URL) throws { throw NotImplemented() }
    func disable() {}
    func syncNow() {}
    func exportKey() -> String? { nil }
    func importKey(_ text: String) throws { throw NotImplemented() }
}
