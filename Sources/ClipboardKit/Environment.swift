import AppKit
import SuperPasteCore

/// A sound Super Paste plays (behaviour.md §2.10).
package enum SoundEffect: Hashable, Sendable {
    /// A copy was captured.
    case copy
    /// Something was pasted or copied out of Super Paste.
    case paste
}

/// What LinkPresentation answered for a link (behaviour.md §2.8), images already downscaled.
package struct LinkPreview: Sendable {
    package var title: String?
    /// Favicon, PNG.
    package var icon: Data?
    /// Preview image, JPEG.
    package var image: Data?

    package init(title: String?, icon: Data?, image: Data?) {
        self.title = title; self.icon = icon; self.image = image
    }
}

/// Everything ClipboardKit needs from macOS and from other modules, as replaceable pieces. `live()` is what the app
/// uses; the self-test builds its own, so it never touches the general pasteboard, posts key events, registers ⌘V,
/// shows windows or plays sounds.
@MainActor
package struct ClipboardEnvironment {
    /// The pasteboard watched and written.
    package var pasteboard: NSPasteboard
    /// Stamped as `org.nspasteboard.source` on everything Super Paste writes.
    package var ownBundleID: String
    package var store: () -> ItemStoring?
    package var frontmostApp: () -> PasteTarget?
    /// The record of the app a copy came from (name, colour, icon blob).
    package var appRecord: (CaptureSource) -> AppRecord?
    package var now: () -> Date
    /// Runs `work` on the main actor after `delay` seconds.
    package var after: (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void
    /// Plays a sound (whether sounds are on is checked by the caller).
    package var playSound: (SoundEffect) -> Void
    package var showHUD: (_ title: String, _ symbol: String, _ subtitle: String?) -> Void
    package var beep: () -> Void
    /// Whether macOS's pasteboard privacy makes Super Paste ask (or keeps it from reading) on every capture.
    package var needsPasteboardAccess: () -> Bool
    package var showPasteboardAccess: () -> Void
    /// Fetches a link preview; calls back on the main actor, nil when it failed.
    package var fetchLinkPreview: (_ url: URL, _ completion: @escaping @MainActor (LinkPreview?) -> Void) -> Void
    /// Makes a Quick Look thumbnail (PNG) of a file; calls back on the main actor.
    package var fileThumbnail: (_ url: URL, _ completion: @escaping @MainActor (Data?) -> Void) -> Void

    // MARK: Pasting

    package var isAccessibilityTrusted: () -> Bool
    /// Asks the app to come forward; the paste then waits until it is frontmost.
    package var activate: (PasteTarget) -> Void
    /// Posts ⌘V to the frontmost app.
    package var postPasteKeystroke: () -> Void
    /// Hides the strip and calls back once it is off screen and no longer key (at once when it isn't showing).
    package var hideStrip: (_ completion: @escaping @MainActor () -> Void) -> Void
    package var askDirectPaste: (_ appName: String?, _ completion: @escaping @MainActor (DirectPasteChoice) -> Void) -> Void
    package var showAccessibilityAccess: () -> Void
    /// Takes over ⌘V globally for the Paste Stack; false when it couldn't be registered.
    package var registerStackHotkey: (_ handler: @escaping @MainActor () -> Void) -> Bool
    package var unregisterStackHotkey: () -> Void

    package init(pasteboard: NSPasteboard, ownBundleID: String, store: @escaping () -> ItemStoring?,
                 frontmostApp: @escaping () -> PasteTarget?, appRecord: @escaping (CaptureSource) -> AppRecord?,
                 now: @escaping () -> Date, after: @escaping (TimeInterval, @escaping @MainActor () -> Void) -> Void,
                 playSound: @escaping (SoundEffect) -> Void, showHUD: @escaping (String, String, String?) -> Void,
                 beep: @escaping () -> Void, needsPasteboardAccess: @escaping () -> Bool,
                 showPasteboardAccess: @escaping () -> Void,
                 fetchLinkPreview: @escaping (URL, @escaping @MainActor (LinkPreview?) -> Void) -> Void,
                 fileThumbnail: @escaping (URL, @escaping @MainActor (Data?) -> Void) -> Void,
                 isAccessibilityTrusted: @escaping () -> Bool, activate: @escaping (PasteTarget) -> Void,
                 postPasteKeystroke: @escaping () -> Void, hideStrip: @escaping (@escaping @MainActor () -> Void) -> Void,
                 askDirectPaste: @escaping (String?, @escaping @MainActor (DirectPasteChoice) -> Void) -> Void,
                 showAccessibilityAccess: @escaping () -> Void,
                 registerStackHotkey: @escaping (@escaping @MainActor () -> Void) -> Bool,
                 unregisterStackHotkey: @escaping () -> Void) {
        self.pasteboard = pasteboard; self.ownBundleID = ownBundleID; self.store = store; self.frontmostApp = frontmostApp
        self.appRecord = appRecord; self.now = now; self.after = after; self.playSound = playSound; self.showHUD = showHUD
        self.beep = beep; self.needsPasteboardAccess = needsPasteboardAccess; self.showPasteboardAccess = showPasteboardAccess
        self.fetchLinkPreview = fetchLinkPreview; self.fileThumbnail = fileThumbnail
        self.isAccessibilityTrusted = isAccessibilityTrusted; self.activate = activate
        self.postPasteKeystroke = postPasteKeystroke; self.hideStrip = hideStrip; self.askDirectPaste = askDirectPaste
        self.showAccessibilityAccess = showAccessibilityAccess; self.registerStackHotkey = registerStackHotkey
        self.unregisterStackHotkey = unregisterStackHotkey
    }
}
