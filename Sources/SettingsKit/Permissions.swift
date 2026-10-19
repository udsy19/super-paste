import AppKit
import SwiftUI
import SuperPasteCore

/// The permission screens (behaviour.md §9, ui-reference §14): Accessibility for direct paste, pasteboard access on
/// newer macOS, and the "paste directly?" prompt.
@MainActor
final class PermissionsController: NSObject, PermissionsPresenting, NSWindowDelegate {
    private var screens: [PermissionKind: (window: NSWindow, monitor: PermissionMonitor)] = [:]
    private var prompt: (panel: NSPanel, completion: @MainActor (DirectPasteChoice) -> Void)?

    func showAccessibilityAccess() { present(.accessibility) }
    func showPasteboardAccess() { present(.pasteboard) }

    private func present(_ kind: PermissionKind) {
        let screen = screens[kind] ?? makeScreen(kind, snapshot: false)
        screens[kind] = screen
        screen.monitor.check()
        screen.monitor.start()
        NSApp.activate()
        screen.window.makeKeyAndOrderFront(nil)
    }

    /// Builds a permission window without showing it.
    func makeScreen(_ kind: PermissionKind, snapshot: Bool) -> (window: NSWindow, monitor: PermissionMonitor) {
        let monitor = PermissionMonitor(kind)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: SPMetrics.Permissions.windowSize),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        let view = PermissionScreen(monitor: monitor) { [weak window] in window?.close() }
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(width: SPMetrics.Permissions.windowSize.width, height: SPMetrics.Permissions.windowSize.height)
            .environment(\.spStyle, snapshot ? .classic : .current)
        window.contentViewController = NSHostingController(rootView: view)
        window.title = kind == .accessibility ? Strings.Permissions.accessibilityTitle : Strings.Permissions.pasteboardTitle
        Self.styleBare(window)
        window.delegate = self
        if !snapshot { window.center() }
        // Bring the screen back when the grant arrives while System Settings is in front.
        monitor.onGrant = { [weak window] in
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
        return (window, monitor)
    }

    /// A titled window with only a close button, no visible title bar, movable by its background.
    static func styleBare(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
    }

    // MARK: Direct paste prompt

    func requestDirectPaste(into appName: String?, completion: @escaping @MainActor (DirectPasteChoice) -> Void) {
        finishPrompt(.copyToClipboard)
        let panel = makePrompt(appName: appName, snapshot: false)
        prompt = (panel, completion)
        panel.center()
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func makePrompt(appName: String?, snapshot: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 420),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        let view = DirectPastePrompt(appName: appName ?? Strings.Permissions.currentApp) { [weak self] choice in
            self?.finishPrompt(choice)
        }
        .padding(.top, 12)
        .environment(\.spStyle, snapshot ? .classic : .current)
        let host = NSHostingController(rootView: view)
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)
        Self.styleBare(panel)
        // Above the strip, which sits at the main menu level.
        panel.level = .statusBar
        panel.delegate = self
        return panel
    }

    /// Answers the open prompt (once) and closes it.
    private func finishPrompt(_ choice: DirectPasteChoice) {
        guard let current = prompt else { return }
        prompt = nil
        current.panel.close()
        if choice == .copyToClipboardAndDontAskAgain { Defaults[.isDirectPastePromptSuppressed] = true }
        current.completion(choice)
        if choice == .enableAccessibility { showAccessibilityAccess() }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if prompt?.panel === window { finishPrompt(.copyToClipboard); return }
        for (kind, screen) in screens where screen.window === window {
            screen.monitor.stop()
            screens[kind] = nil
        }
    }
}

extension PermissionKind {
    var title: String {
        switch self {
        case .accessibility: Strings.Permissions.accessibilityTitle
        case .pasteboard: Strings.Permissions.pasteboardTitle
        }
    }

    var subtitle: String {
        switch self {
        case .accessibility: Strings.Permissions.accessibilitySubtitle
        case .pasteboard: Strings.Permissions.pasteboardSubtitle
        }
    }

    var grantedText: String {
        switch self {
        case .accessibility: Strings.Permissions.accessibilityGranted
        case .pasteboard: Strings.Permissions.pasteboardGranted
        }
    }
}

/// A permission screen: icon, title, subtitle, a System Settings illustration (a green check once granted), then
/// Not Now and Open System Settings.
struct PermissionScreen: View {
    @ObservedObject var monitor: PermissionMonitor
    let done: () -> Void

    var body: some View {
        let kind = monitor.kind
        let flow = monitor.flow
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            AppIconView(size: SPMetrics.Permissions.iconSize).padding(.bottom, 20)
            Text(kind.title).font(.system(size: SPMetrics.Onboarding.titleFontSize, weight: .bold))
                .multilineTextAlignment(.center)
            Text(flow.isGranted ? kind.grantedText : kind.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: SPMetrics.Onboarding.cardWidth)
                .padding(.top, 8)
            ZStack {
                if flow.isGranted {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: SPMetrics.Permissions.grantedSymbolSize, weight: .regular))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    SystemSettingsArt(paneTitle: kind == .accessibility ? Strings.Permissions.accessibilityPane
                                                                        : Strings.Permissions.pasteboardPane,
                                      control: kind == .accessibility ? .toggle : .alwaysAllow)
                }
            }
            .frame(width: SPMetrics.Permissions.illustrationSize.width, height: SPMetrics.Permissions.illustrationSize.height)
            .padding(.top, 24)
            .animation(.easeInOut(duration: 0.25), value: flow.isGranted)
            Spacer(minLength: 0)
            if flow.isGranted {
                SPButton(title: Strings.Action.done, action: done)
                    .keyboardShortcut(.defaultAction)
            } else {
                HStack(spacing: 8) {
                    SPButton(title: Strings.Action.notNow, kind: .gray, action: done)
                        .keyboardShortcut(.cancelAction)
                    SPButton(title: Strings.Action.openSystemSettings) { monitor.openSettings() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            Button(Strings.Permissions.issue) {
                Alerts.notice(Strings.Permissions.issueTitle, Strings.Permissions.issueText)
            }
            .buttonStyle(.link)
            .font(.sp(.callout))
            .padding(.top, 12)
            .opacity(flow.showsIssueHelp ? 1 : 0)
            .disabled(!flow.showsIssueHelp)
        }
        .frame(maxWidth: .infinity)
    }
}

/// "Do you want to paste directly to %@?" (ui-reference §14: 280 wide, 280 × 160 illustration).
struct DirectPastePrompt: View {
    let appName: String
    let answer: (DirectPasteChoice) -> Void
    @State private var doNotAskAgain = false

    var body: some View {
        VStack(spacing: 12) {
            PasteToAppArt()
                .frame(width: 280, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: SPMetrics.Permissions.illustrationCornerRadius, style: .continuous))
            Text(Strings.Permissions.directPasteTitle(appName)).font(.sp(.title2, .bold))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            Text(Strings.Permissions.directPasteText).font(.sp(.body)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                SPButton(title: Strings.Permissions.allowAccessibility, stretch: true) { answer(.enableAccessibility) }
                    .keyboardShortcut(.defaultAction)
                SPButton(title: Strings.Permissions.copyToClipboard, kind: .gray, stretch: true) {
                    answer(doNotAskAgain ? .copyToClipboardAndDontAskAgain : .copyToClipboard)
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.top, 4)
            Toggle(Strings.Permissions.doNotAskAgain, isOn: $doNotAskAgain).toggleStyle(.checkbox).font(.sp(.callout))
        }
        .frame(width: 280)
        .padding(20)
    }
}
