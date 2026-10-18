import AppKit
import Combine
import SuperPasteCore

/// The menu bar item (behaviour.md §6.1, ui-reference §10), shown while Show in Menu Bar is on.
///
/// Clicks: a left click toggles the strip; a right click, Control-click or Option-click opens the app menu
/// (`AppMenu`, the same menu as the strip's "…" button). The reference app's mapping wasn't confirmed (behaviour.md
/// §22.3 gap 5); this follows ui-reference §10 and adds Option-click from behaviour.md §6.1.
///
/// The icon is the app icon's stack of cards (see `glyph`), drawn dimmed while capturing is paused.
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

    /// The app icon's stack of cards as a 16 pt template: two thin card tops above a full card.
    private static let glyph: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 4.5, y: 2.5, width: 7, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 3.5, y: 5, width: 9, height: 1.5), xRadius: 0.75, yRadius: 0.75).fill()
            NSBezierPath(roundedRect: NSRect(x: 2.5, y: 7.5, width: 11, height: 6.5), xRadius: 2, yRadius: 2).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Super Paste"
        return image
    }()

    private func setShown(_ shown: Bool) {
        if !shown, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        } else if shown, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = item.button {
                button.image = Self.glyph
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
