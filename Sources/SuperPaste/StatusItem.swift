import AppKit
import Combine
import SuperPasteCore

/// The menu bar item (behaviour.md §6.1, ui-reference §10): shown while Show in Menu Bar is on; a left click toggles
/// the strip, a right or Control click opens the menu. Placeholder icon and menu until the app shell is designed
/// (animation frames, paused image, the full app menu).
@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private var cancellable: AnyCancellable?
    private let menu = NSMenu()

    override init() {
        super.init()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Super Paste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        cancellable = Defaults.publisher(.isStatusItemEnabled).sink { [weak self] shown in self?.setShown(shown) }
    }

    private func setShown(_ shown: Bool) {
        if !shown, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        } else if shown, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Super Paste")
            item.button?.image?.isTemplate = true
            item.button?.target = self
            item.button?.action = #selector(clicked)
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            self.item = item
        }
    }

    @objc private func clicked() {
        guard let event = NSApp.currentEvent, let item else { return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            item.menu = menu
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            Services.strip.toggle()
        }
    }

    @objc private func openSettings() { Services.settings.show(pane: nil) }
}
