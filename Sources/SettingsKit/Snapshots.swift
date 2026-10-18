import AppKit
import SuperPasteCore

/// Renders the Settings panes, onboarding pages and permission screens to PNG files without putting a window on
/// screen: each window is built, laid out and drawn with `cacheDisplay`, never ordered in. The self-test calls it
/// when `SUPERPASTE_RENDER_DIR` is set. Glass and the system sidebar material don't draw off screen, so snapshots
/// use the classic look and an opaque sidebar.
@MainActor
public enum SettingsKitSnapshots {
    /// Stands in for the app icon (there is no app bundle under `swift run`).
    public static var appIcon: NSImage? {
        get { AppIcon.override }
        set { AppIcon.override = newValue }
    }

    static let appearances: [(name: NSAppearance.Name, suffix: String)] = [(.aqua, "light"), (.darkAqua, "dark")]

    /// `settings-<pane><tag>-<light|dark>.png` for each pane.
    public static func renderSettings(_ panes: [SettingsPane] = SettingsPane.allCases, tag: String = "",
                                      to folder: URL) throws -> [URL] {
        var urls: [URL] = []
        for pane in panes {
            for appearance in appearances {
                let controller = SettingsWindowController()
                let window = controller.makeWindow(snapshot: true)
                controller.model.pane = pane
                let url = folder.appendingPathComponent("settings-\(pane.rawValue)\(tag)-\(appearance.suffix).png")
                try capture(window, appearance.name, to: url)
                urls.append(url)
            }
        }
        return urls
    }

    /// `onboarding-<n>-<page>-<light|dark>.png` for each page.
    public static func renderOnboarding(to folder: URL) throws -> [URL] {
        var urls: [URL] = []
        for page in OnboardingPage.allCases {
            for appearance in appearances {
                let controller = OnboardingController()
                let window = controller.makeWindow(page: page, snapshot: true)
                let url = folder.appendingPathComponent("onboarding-\(page.rawValue + 1)-\(page)-\(appearance.suffix).png")
                try capture(window, appearance.name, to: url)
                urls.append(url)
            }
        }
        return urls
    }

    /// The Accessibility screen in each phase, the pasteboard screen and the direct-paste prompt.
    public static func renderPermissions(to folder: URL) throws -> [URL] {
        var urls: [URL] = []
        let screens: [(PermissionKind, PermissionFlow.Phase, String)] = [
            (.accessibility, .needed, "accessibility"), (.accessibility, .issue, "accessibility-issue"),
            (.accessibility, .granted, "accessibility-granted"), (.pasteboard, .needed, "pasteboard"),
        ]
        for appearance in appearances {
            let controller = PermissionsController()
            for (kind, phase, name) in screens {
                let screen = controller.makeScreen(kind, snapshot: true)
                screen.monitor.show(phase)
                let url = folder.appendingPathComponent("permission-\(name)-\(appearance.suffix).png")
                try capture(screen.window, appearance.name, to: url)
                urls.append(url)
            }
            let prompt = controller.makePrompt(appName: "Notes", snapshot: true)
            let url = folder.appendingPathComponent("permission-direct-paste-\(appearance.suffix).png")
            try capture(prompt, appearance.name, to: url)
            urls.append(url)
        }
        return urls
    }

    /// Lays the window out, lets SwiftUI settle (window height follows content), draws the frame view (title bar
    /// included) and closes the window.
    private static func capture(_ window: NSWindow, _ appearance: NSAppearance.Name, to url: URL) throws {
        window.appearance = NSAppearance(named: appearance)
        for _ in 0..<4 {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        guard let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        window.close()
    }
}
