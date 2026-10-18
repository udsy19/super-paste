import AppKit
import Combine
import SuperPasteCore

/// The global shortcuts (behaviour.md §7.3), from `Defaults` and re-registered whenever one changes in Settings:
/// Activate Super Paste toggles the strip, Activate Paste Stack toggles the stack. Show next / previous Pinboard
/// (⌘→ / ⌘←) work only while the strip has focus (behaviour.md §4.4): StripKit reads them live, and registering
/// them system-wide would take ⌘← / ⌘→ away from every text field on the Mac.
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
