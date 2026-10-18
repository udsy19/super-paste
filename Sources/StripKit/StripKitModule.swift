import AppKit
import Combine
import SuperPasteCore

/// Registers this module's services in `Services` (called once at launch, after the services the strip uses).
public enum StripKitModule {
    @MainActor public static func install() {
        Services.strip = PlaceholderStrip()
    }
}

/// Stand-in until the strip lands: never visible. Delete it when `install()` registers the real strip.
@MainActor
final class PlaceholderStrip: StripPresenting {
    var isVisible: Bool { false }
    var visibilityChanges: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    func show(_ route: StripRoute?) { Log.strip.info("The strip isn't implemented yet") }
    func hide() {}
    func toggle() { show(nil) }
}
