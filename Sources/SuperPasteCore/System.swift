import AppKit
import ApplicationServices
import os

public enum Log {
    public static let app = Logger(subsystem: SuperPastePaths.bundleID, category: "app")
    public static let store = Logger(subsystem: SuperPastePaths.bundleID, category: "store")
    public static let clipboard = Logger(subsystem: SuperPastePaths.bundleID, category: "clipboard")
    public static let paste = Logger(subsystem: SuperPastePaths.bundleID, category: "paste")
    public static let strip = Logger(subsystem: SuperPastePaths.bundleID, category: "strip")
    public static let settings = Logger(subsystem: SuperPastePaths.bundleID, category: "settings")
    public static let sync = Logger(subsystem: SuperPastePaths.bundleID, category: "sync")
    public static let mcp = Logger(subsystem: SuperPastePaths.bundleID, category: "mcp")
    public static let updates = Logger(subsystem: SuperPastePaths.bundleID, category: "updates")
}

// MARK: - Alerts & HUD

@MainActor
public enum Alerts {
    public static func error(_ message: String, _ error: Error? = nil) {
        Log.app.error("\(message, privacy: .public) \(error?.localizedDescription ?? "", privacy: .public)")
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = message
        if let error { a.informativeText = error.localizedDescription }
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }

    /// Confirmation with optional "Don't ask again" suppression (remembered in `suppressedWarnings`).
    public static func confirm(_ message: String, info: String = "", confirmTitle: String = "OK",
                               cancelTitle: String = "Cancel", destructive: Bool = false, suppressionID: String? = nil) -> Bool {
        if let id = suppressionID, Defaults[.suppressedWarnings].contains(id) { return true }
        let a = NSAlert()
        a.messageText = message
        a.informativeText = info
        let ok = a.addButton(withTitle: confirmTitle)
        if destructive { ok.hasDestructiveAction = true }
        a.addButton(withTitle: cancelTitle)
        if suppressionID != nil { a.showsSuppressionButton = true; a.suppressionButton?.title = "Don't ask again." }
        NSApp.activate(ignoringOtherApps: true)
        let result = a.runModal() == .alertFirstButtonReturn
        if result, let id = suppressionID, a.suppressionButton?.state == .on { Defaults[.suppressedWarnings].insert(id) }
        return result
    }

    /// Text prompt; returns nil on cancel.
    public static func prompt(title: String, message: String = "", defaultValue: String = "") -> String? {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = defaultValue
        a.accessoryView = field
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? defaultValue : v
    }
}

/// The on-screen toast ("Copied", "Paste Paused", "Paste Resumed"; ui-reference §8): a HUD-material square with a
/// large SF Symbol, a title and an optional subtitle, centred low on the active screen. It holds for a second,
/// fades out and never takes clicks. A new toast replaces the one showing.
@MainActor
public enum HUD {
    private static var window: NSWindow?

    public static func show(_ title: String, symbol: String = "checkmark", subtitle: String? = nil) {
        window?.orderOut(nil)
        let side = SPMetrics.HUD.size
        let backdrop = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.wantsLayer = true
        backdrop.layer?.cornerRadius = SPMetrics.HUD.cornerRadius
        backdrop.layer?.masksToBounds = true

        let image = NSImageView()
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: SPMetrics.HUD.symbolSize, weight: .regular))
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .preferredFont(forTextStyle: .title1)
        titleLabel.alignment = .center
        var views: [NSView] = [image, titleLabel]
        if let subtitle {
            let sub = NSTextField(labelWithString: subtitle)
            sub.font = .preferredFont(forTextStyle: .body)
            sub.alignment = .center
            views.append(sub)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualTo: backdrop.widthAnchor, constant: -16),
        ])

        let screen = NSScreen.active.frame
        let frame = NSRect(x: screen.midX - side / 2, y: screen.minY + SPMetrics.HUD.bottomOffset, width: side, height: side)
        let w = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = SPMetrics.HUD.windowLevel; w.ignoresMouseEvents = true; w.isReleasedWhenClosed = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        w.contentView = backdrop
        w.orderFrontRegardless()
        window = w
        DispatchQueue.main.asyncAfter(deadline: .now() + SPMotion.hudHoldDuration) {
            MainActor.assumeIsolated {
                guard window === w else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = SPMotion.hudFadeDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    w.animator().alphaValue = 0
                }, completionHandler: {
                    MainActor.assumeIsolated {
                        w.orderOut(nil)
                        if window === w { window = nil }
                    }
                })
            }
        }
    }
}

// MARK: - Screens & permissions

public extension NSScreen {
    /// The screen containing the mouse cursor.
    static var active: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }
    static func with(displayID: CGDirectDisplayID) -> NSScreen? { screens.first { $0.displayID == displayID } }
}

/// Privacy permissions Super Paste checks (behaviour.md §9).
public enum Permissions {
    /// Privacy & Security panes in System Settings.
    public enum Pane: String, Sendable {
        case accessibility = "Privacy_Accessibility"
        case pasteboard = "Privacy_Pasteboard"
    }

    /// Whether Super Paste may post keyboard events (direct paste).
    public static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt when not yet trusted; returns the current trust.
    @discardableResult public static func requestAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @MainActor public static func open(_ pane: Pane) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") {
            NSWorkspace.shared.open(url)
        }
    }
}
