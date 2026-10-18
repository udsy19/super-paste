import AppKit
import Combine
import SuperPasteCore

/// The menu bar item (behaviour.md §6.1, ui-reference §10), shown while Show in Menu Bar is on.
///
/// Clicks: a left click toggles the strip; a right click, Control-click or Option-click opens the app menu
/// (`AppMenu`, the same menu as the strip's "…" button). The reference app's mapping wasn't confirmed (behaviour.md
/// §22.3 gap 5); this follows ui-reference §10 and adds Option-click from behaviour.md §6.1.
///
/// The icon is the app icon's stack of cards (see `glyph`), drawn dimmed while capturing is paused. Every capture
/// plays a short animation on it (ui-reference §10): the glyph fades out, a tilted card drops in, the glyph scales
/// back; 17 frames at 1/48 s.
@MainActor
final class StatusItemController: NSObject {
    private var item: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var animation: Timer?
    private var frame = 0

    override init() {
        super.init()
        Defaults.publisher(.isStatusItemEnabled)
            .sink { [weak self] shown in self?.setShown(shown) }
            .store(in: &cancellables)
        Services.clipboard.pauseChanges
            .sink { [weak self] state in self?.item?.button?.appearsDisabled = state != .running }
            .store(in: &cancellables)
        Services.clipboard.captures
            .sink { [weak self] _ in self?.animateCapture() }
            .store(in: &cancellables)
    }

    /// The app icon's stack of cards as a 16 pt template: two thin card tops above a full card.
    private static let glyph = frameImage(0)

    /// Frame `n` of the capture animation (0 is the resting glyph): 1–5 fade the glyph out, 6–9 drop a tilted card in
    /// from the top, 10–16 scale the glyph back up.
    static func frameImage(_ n: Int) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: true) { _ in
            switch n {
            case 1...5:
                drawGlyph(alpha: 1 - CGFloat(n) / 5, scale: 1)
            case 6...9:
                let progress = CGFloat(n - 5) / 4
                let card = NSBezierPath(roundedRect: NSRect(x: 3, y: 3, width: 10, height: 8), xRadius: 2, yRadius: 2)
                var transform = AffineTransform(translationByX: 8, byY: 8 - (1 - progress) * 10)
                transform.rotate(byDegrees: -14 * (1 - progress))
                transform.translate(x: -8, y: -8)
                card.transform(using: transform)
                NSColor.black.withAlphaComponent(0.35 + 0.65 * progress).setFill()
                card.fill()
            case 10...16:
                drawGlyph(alpha: 1, scale: 0.6 + 0.4 * CGFloat(n - 9) / 7)
            default:
                drawGlyph(alpha: 1, scale: 1)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Super Paste"
        return image
    }

    private static func drawGlyph(alpha: CGFloat, scale: CGFloat) {
        NSColor.black.withAlphaComponent(alpha).setFill()
        var transform = AffineTransform(translationByX: 8, byY: 8)
        transform.scale(scale)
        transform.translate(x: -8, y: -8)
        for (rect, radius) in [(NSRect(x: 4.5, y: 2.5, width: 7, height: 1.5), 0.75),
                               (NSRect(x: 3.5, y: 5, width: 9, height: 1.5), 0.75),
                               (NSRect(x: 2.5, y: 7.5, width: 11, height: 6.5), 2)] {
            let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
            path.transform(using: transform)
            path.fill()
        }
    }

    private func animateCapture() {
        guard let button = item?.button else { return }
        animation?.invalidate()
        frame = 0
        animation = Timer.scheduledTimer(withTimeInterval: SPMotion.statusItemFrameDuration, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                self.frame += 1
                if self.frame >= SPMetrics.StatusItem.animationFrames {
                    timer.invalidate()
                    self.animation = nil
                    button.image = Self.glyph
                } else {
                    button.image = Self.frameImage(self.frame)
                }
            }
        }
    }

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
