import AppKit
import Combine
import SuperPasteCore

/// The menu bar item (behaviour.md §6.1, ui-reference §10), shown while Show in Menu Bar is on.
///
/// Clicks: a left click toggles the strip; a right click, Control-click or Option-click opens the app menu
/// (`AppMenu`, the same menu as the strip's "…" button). The reference app's mapping wasn't confirmed (behaviour.md
/// §22.3 gap 5); this follows ui-reference §10 and adds Option-click from behaviour.md §6.1.
///
/// While capturing is paused the icon is drawn dimmed. The icon is the `doc.on.clipboard` symbol from Paste's symbol
/// set until Super Paste has its own menu bar artwork (and the copy animation that goes with it).
@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    override init() {
        super.init()
        Defaults.publisher(.isStatusItemEnabled)
            .sink { [weak self] shown in self?.setShown(shown) }
            .store(in: &cancellables)
        Services.clipboard.pauseChanges
            .sink { [weak self] state in self?.item?.button?.appearsDisabled = state != .running }
            .store(in: &cancellables)
    }

    private func setShown(_ shown: Bool) {
        if !shown, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        } else if shown, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Super Paste")
                button.image?.isTemplate = true
                button.appearsDisabled = Services.clipboard.isPaused
                button.target = self
                button.action = #selector(clicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            self.item = item
        }
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent, let item else { return }
        if AppMenu.opensFromStatusItem(event.type, modifiers: event.modifierFlags) {
            // A menu attached only for this click, so a left click keeps toggling the strip.
            item.menu = AppMenu.make()
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            Services.strip.toggle()
        }
    }
}
