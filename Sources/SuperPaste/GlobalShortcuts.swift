import AppKit
import Combine
import SuperPasteCore

/// The global shortcuts (behaviour.md §7.3), from `Defaults` and re-registered whenever one changes in Settings:
/// Activate Super Paste toggles the strip, Activate Paste Stack toggles the stack. Show next / previous Pinboard
/// (⌘→ / ⌘←) work only while the strip has focus (behaviour.md §4.4): StripKit reads them live, and registering
/// them system-wide would take ⌘← / ⌘→ away from every text field on the Mac.
///
/// A shortcut another app already holds (the reference app running alongside, say) can't be registered. That is
/// never silent: the shortcut is listed in `HotkeyCenter.unavailable` (Settings → Shortcuts shows a warning row), a
/// notice explains it once per shortcut, and registration is retried every half minute so the shortcut starts
/// working as soon as the other app quits.
@MainActor
final class GlobalShortcuts {
    private var tokens: [UInt32] = []
    private var cancellable: AnyCancellable?
    private var retry: Timer?
    static let retryInterval: TimeInterval = 30

    init() {
        let names: Set = [Defaults.Keys.activationShortcut.name, Defaults.Keys.pasteStackShortcut.name]
        cancellable = Defaults.changes.filter { names.contains($0) }.sink { [weak self] _ in self?.register() }
        register()
    }

    private func register() {
        let center = HotkeyCenter.shared
        tokens.forEach(center.unregister)
        tokens = []
        center.forgetUnavailable()
        var failed: [(name: String, shortcut: Shortcut)] = []
        bind(Defaults[.activationShortcut], "Activate Super Paste", failures: &failed) { Services.strip.toggle() }
        bind(Defaults[.pasteStackShortcut], "Activate Paste Stack", failures: &failed) { Services.pasting.togglePasteStack() }
        scheduleRetry(failed.isEmpty ? nil : Self.retryInterval)
        if let first = failed.first { notice(first.name, first.shortcut) }
    }

    private func bind(_ shortcut: Shortcut?, _ name: String, failures: inout [(name: String, shortcut: Shortcut)],
                      _ action: @escaping () -> Void) {
        guard let shortcut else { return }
        if let token = HotkeyCenter.shared.register(shortcut, handler: action) {
            tokens.append(token)
        } else {
            Log.app.error("\(name, privacy: .public): \(shortcut.displayString, privacy: .public) is taken by another app")
            failures.append((name, shortcut))
        }
    }

    private func scheduleRetry(_ interval: TimeInterval?) {
        retry?.invalidate()
        retry = nil
        guard let interval else { return }
        retry = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.register() }
        }
    }

    /// The one-time notice: an alert, since nothing else of Super Paste may be on screen. Shown once per shortcut
    /// (a changed shortcut that conflicts too gets its own), never while onboarding is still up.
    private func notice(_ name: String, _ shortcut: Shortcut) {
        let key = shortcut.displayString
        guard !Defaults[.hotkeyConflictsNoticed].contains(key), Services.onboarding.isCompleted else { return }
        Defaults[.hotkeyConflictsNoticed].insert(key)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = HotkeyConflict.title(shortcut)
        alert.informativeText = HotkeyConflict.text(name)
        alert.addButton(withTitle: HotkeyConflict.openSettings)
        alert.addButton(withTitle: HotkeyConflict.later)
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn { Services.settings.show(pane: .shortcuts) }
    }
}
