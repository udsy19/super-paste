import AppKit

// MARK: - Menu items

/// A menu item that runs a closure.
public final class ClosureMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    public init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { MainActor.assumeIsolated { handler() } }
}

public extension NSMenuItem {
    /// Menu item icons appear only on macOS 26 (ui-reference §4.8).
    static var showsIcons: Bool { SPStyle.current == .glass }

    /// Sets the SF Symbol icon on macOS 26 only (older systems show menus without icons).
    func withSymbol(_ name: String) -> NSMenuItem {
        if Self.showsIcons { image = NSImage(systemSymbolName: name, accessibilityDescription: nil) }
        return self
    }

    static func make(_ title: String, symbol: String? = nil, key: String = "", modifiers: NSEvent.ModifierFlags = .command,
                     enabled: Bool = true, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ClosureMenuItem(title: title, handler: handler)
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.isEnabled = enabled
        if let symbol { _ = item.withSymbol(symbol) }
        return item
    }

    /// An item showing a global shortcut (the user's, read when the menu is built); none when it was removed.
    static func make(_ title: String, symbol: String? = nil, shortcut: Shortcut?,
                     handler: @escaping @MainActor () -> Void) -> NSMenuItem {
        make(title, symbol: symbol, key: shortcut?.keyEquivalent ?? "", modifiers: shortcut?.modifiers ?? [], handler: handler)
    }
}

// MARK: - App menu

/// The app menu (behaviour.md §6.2, ui-reference §10), shared by the menu bar item and the strip's "…" button.
/// Built fresh each time it opens, so the pause state is current:
///
///     About Super Paste
///     ─
///     New Text Item           ⌘N
///     Settings…               ⌘,
///     ─
///     Help ▸                        Getting Started, Keyboard Shortcuts, Help Center, Feature Request, Contact Support
///     ─
///     Pause ▸                       (titled "Paused until HH:mm" while paused)
///     ─
///     Quit Super Paste        ⌘Q
///
/// There is no Check for Updates: updates install automatically (UpdateKit).
@MainActor
public enum AppMenu {
    public enum Title {
        public static let about = "About Super Paste"
        public static let newTextItem = "New Text Item"
        public static let settings = "Settings…"
        public static let help = "Help"
        public static let gettingStarted = "Getting Started"
        public static let keyboardShortcuts = "Keyboard Shortcuts"
        public static let helpCenter = "Help Center"
        public static let featureRequest = "Feature Request"
        public static let contactSupport = "Contact Support"
        public static let pause = "Pause"
        public static let paused = "Paused"
        public static func pausedUntil(_ time: String) -> String { "Paused until \(time)" }
        public static let resume = "Resume"
        public static func pauseFor(_ duration: String) -> String { "Pause for \(duration)" }
        public static let untilResumed = "Until I Resume"
        public static let quit = "Quit Super Paste"
    }

    /// Where the Help items go.
    public enum Links {
        public static let helpCenter = URL(string: "https://udsy19.github.io/super-paste/")!
        public static let featureRequest = URL(string: "https://github.com/udsy19/super-paste/issues/new")!
        public static let contactSupport = URL(string: "https://github.com/udsy19/super-paste/issues")!
    }

    public static func make() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.make(Title.about, symbol: "info.circle") { Services.settings?.show(pane: .about) })
        menu.addItem(.separator())
        menu.addItem(.make(Title.newTextItem, symbol: "square.and.pencil", key: "n") { Services.strip?.show(.newTextItem) })
        menu.addItem(.make(Title.settings, symbol: "gear", key: ",") { Services.settings?.show(pane: nil) })
        menu.addItem(.separator())
        let help = NSMenuItem(title: Title.help, action: nil, keyEquivalent: "").withSymbol("questionmark.circle")
        help.submenu = makeHelpMenu()
        menu.addItem(help)
        menu.addItem(.separator())
        let pause = NSMenuItem(title: pauseStatus ?? Title.pause, action: nil, keyEquivalent: "").withSymbol("pause.circle")
        pause.submenu = makePauseMenu()
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(.make(Title.quit, symbol: "xmark.app", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    /// Help ▸: onboarding again, the Shortcuts pane, the website, then the GitHub issue pages.
    public static func makeHelpMenu() -> NSMenu {
        let menu = NSMenu(title: Title.help)
        menu.autoenablesItems = false
        menu.addItem(.make(Title.gettingStarted, symbol: "flag") { Services.onboarding?.show() })
        menu.addItem(.make(Title.keyboardShortcuts, symbol: "keyboard") { Services.settings?.show(pane: .shortcuts) })
        menu.addItem(.make(Title.helpCenter, symbol: "lifepreserver") { NSWorkspace.shared.open(Links.helpCenter) })
        menu.addItem(.separator())
        menu.addItem(.make(Title.featureRequest, symbol: "lightbulb") { NSWorkspace.shared.open(Links.featureRequest) })
        menu.addItem(.make(Title.contactSupport, symbol: "paperplane") { NSWorkspace.shared.open(Links.contactSupport) })
        return menu
    }

    /// Pause (behaviour.md §6.3). While capturing: Pause for 15m … 8h, then Until I Resume (⌘T). While paused: the
    /// pause status, Resume (⌘T), then the durations to pause for again from now. Also the strip's notification-bar
    /// pause button.
    public static func makePauseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let clipboard = Services.clipboard
        if let status = pauseStatus {
            menu.addItem(.make(status, enabled: false) {})
            menu.addItem(.make(Title.resume, symbol: "play.circle", key: "t") { clipboard?.resume() })
            menu.addItem(.separator())
        }
        let symbols = ["15.circle", "30.circle", "1.circle", "3.circle", "8.circle"]
        for (duration, symbol) in zip(PauseDurations.all, symbols) {
            menu.addItem(.make(Title.pauseFor(durationTitle(duration)), symbol: symbol) {
                clipboard?.pause(until: Date().addingTimeInterval(duration))
            })
        }
        if pauseStatus == nil {
            menu.addItem(.separator())
            menu.addItem(.make(Title.untilResumed, symbol: "pause.circle", key: "t") { clipboard?.pause(until: nil) })
        }
        return menu
    }

    /// "Paused until 14:30" (or "Paused" until resumed) while paused; nil while capturing.
    public static var pauseStatus: String? {
        switch Services.clipboard?.pauseState {
        case .paused(let until?)?: Title.pausedUntil(until.formatted(date: .omitted, time: .shortened))
        case .paused(nil)?: Title.paused
        case .running?, nil: nil
        }
    }

    /// Whether a click on the menu bar item opens this menu rather than toggling the strip: a right click, or a
    /// left click with Control or Option held (ui-reference §10, behaviour.md §6.1).
    public static func opensFromStatusItem(_ type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseUp || type == .rightMouseDown || !modifiers.intersection([.control, .option]).isEmpty
    }

    /// "15m", "1h": the abbreviated duration (ui-reference §10).
    public static func durationTitle(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        return formatter.string(from: seconds) ?? ""
    }
}
