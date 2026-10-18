import AppKit
import Combine
import SuperPasteCore

/// The two global shortcuts (behaviour.md §7.3): Activate Super Paste toggles the strip, Activate Paste Stack toggles
/// the stack. Re-registered whenever either setting changes. (Next/previous pinboard are strip-local, not global.)
@MainActor
final class GlobalShortcuts {
    private var tokens: [UInt32] = []
    private var cancellable: AnyCancellable?

    init() {
        let names: Set = [Defaults.Keys.activationShortcut.name, Defaults.Keys.pasteStackShortcut.name]
        cancellable = Defaults.changes.filter { names.contains($0) }.sink { [weak self] _ in self?.register() }
        register()
    }

    private func register() {
        tokens.forEach(HotkeyCenter.shared.unregister)
        tokens = []
        bind(Defaults[.activationShortcut], "Activate Super Paste") { Services.strip.toggle() }
        bind(Defaults[.pasteStackShortcut], "Activate Paste Stack") { Services.pasting.togglePasteStack() }
    }

    private func bind(_ shortcut: Shortcut?, _ name: String, _ action: @escaping () -> Void) {
        guard let shortcut else { return }
        if let token = HotkeyCenter.shared.register(shortcut, handler: action) {
            tokens.append(token)
        } else {
            Log.app.error("\(name, privacy: .public): \(shortcut.displayString, privacy: .public) is taken by another app")
        }
    }
}
