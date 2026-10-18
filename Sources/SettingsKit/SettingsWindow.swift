import AppKit
import Combine
import SwiftUI
import SuperPasteCore

extension Defaults.Keys {
    /// The pane Settings shows when opened without one.
    static let settingsKitLastPane = Key<SettingsPane>("settingsKit.lastPane", default: .general)
}

extension SettingsPane {
    var title: String { Strings.paneTitle(self) }

    /// Sidebar symbols: Paste's for General, Privacy and Shortcuts (ui-reference §11); the rest from Paste's symbol
    /// set (§1.3) for the panes Super Paste adds.
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .privacy: "hand.raised"
        case .shortcuts: "keyboard"
        case .sync: "arrow.triangle.2.circlepath"
        case .integrations: "puzzlepiece.extension"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var pane: SettingsPane {
        didSet { if pane != oldValue { Defaults[.settingsKitLastPane] = pane } }
    }
    /// The shown pane's full height (title bar, padding and content), measured by SwiftUI.
    @Published var contentHeight: CGFloat = 0
    /// Polls Accessibility while Settings is open, for the General row and the sidebar badge.
    let accessibility = PermissionMonitor(.accessibility)

    init() { pane = Defaults[.settingsKitLastPane] }
}

/// The Settings window (behaviour.md §7, ui-reference §11): a 200 pt sidebar and a 440 pt pane in a split view, a
/// transparent title bar over both, and a height that follows the pane.
@MainActor
final class SettingsWindowController: NSObject, SettingsPresenting, NSWindowDelegate {
    private(set) var window: NSWindow?
    let model = SettingsModel()
    private var cancellables: Set<AnyCancellable> = []

    func show(pane: SettingsPane?) {
        let window = self.window ?? makeWindow(snapshot: false)
        if let pane { model.pane = pane }
        // Measure the pane before the window appears, so it opens at the right height.
        if !window.isVisible { window.layoutIfNeeded() }
        LoginItem.refresh()
        model.accessibility.start()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window without showing it. The snapshot renderer gets a borderless window and a plain split item
    /// for the sidebar: scroll views under a transparent title bar and the system sidebar material don't draw off
    /// screen.
    func makeWindow(snapshot: Bool) -> NSWindow {
        let metrics = SPMetrics.Settings.self
        let style: SPStyle = snapshot ? .classic : .current

        let sidebar = NSHostingController(rootView: SettingsSidebar(model: model, opaque: snapshot)
            .environment(\.spStyle, style))
        sidebar.sizingOptions = []
        let sidebarItem = snapshot ? NSSplitViewItem(viewController: sidebar) : NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.canCollapse = false
        sidebarItem.minimumThickness = metrics.sidebarWidth
        sidebarItem.maximumThickness = metrics.sidebarWidth

        let content = NSHostingController(rootView: PaneContainer(model: model).environment(\.spStyle, style))
        content.sizingOptions = []
        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = metrics.contentWidth
        contentItem.maximumThickness = metrics.contentWidth

        let split = NSSplitViewController()
        split.splitView.dividerStyle = .thin
        split.splitViewItems = [sidebarItem, contentItem]

        let width = metrics.sidebarWidth + metrics.contentWidth
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 480),
                              styleMask: snapshot ? [.borderless] : [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: true)
        window.contentViewController = split
        window.title = "\(Strings.appName) Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        if !snapshot {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.toolbar = NSToolbar(identifier: "superpaste.settings")
            window.toolbarStyle = .unified
        }
        window.setContentSize(NSSize(width: width, height: 480))
        if !snapshot {
            window.center()
            window.setFrameAutosaveName("SuperPasteSettings")
        }
        model.$contentHeight.removeDuplicates().filter { $0 > 0 }
            .sink { [weak self, weak window] height in
                guard let window else { return }
                self?.fit(window, height: height)
            }
            .store(in: &cancellables)
        self.window = window
        return window
    }

    /// Keeps the top edge where it is and sizes the window to the pane, within the screen.
    private func fit(_ window: NSWindow, height: CGFloat) {
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 900
        let target = min(max(height.rounded(), 240), screenHeight - 40)
        guard abs(window.frame.height - target) >= 1 else { return }
        var frame = window.frame
        frame.origin.y = frame.maxY - target
        frame.size.height = target
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    func windowWillClose(_ notification: Notification) {
        model.accessibility.stop()
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @ObservedObject var model: SettingsModel
    /// Draws its own background and leaves room for the title bar (snapshots, which have neither).
    var opaque = false
    @ObservedObject private var accessibility: PermissionMonitor
    @Default(.isDirectPasteEnabled) private var directPaste

    init(model: SettingsModel, opaque: Bool) {
        self.model = model
        self.opaque = opaque
        accessibility = model.accessibility
    }

    var body: some View {
        List(selection: Binding(get: { model.pane }, set: { if let pane = $0 { model.pane = pane } })) {
            ForEach(SettingsPane.allCases, id: \.self) { pane in
                HStack(spacing: 6) {
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol).font(.system(size: SPMetrics.Settings.sidebarSymbolSize))
                    }
                    Spacer(minLength: 0)
                    if showsWarning(pane) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white, .red)
                    }
                }
                .tag(pane)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: opaque ? SPMetrics.Settings.titleBarHeight : 0)
        }
        .scrollContentBackground(opaque ? .hidden : .automatic)
        .background(opaque ? Color(nsColor: SPColor.surface1) : Color.clear)
    }

    private func showsWarning(_ pane: SettingsPane) -> Bool {
        pane == .general && directPaste && !accessibility.flow.isGranted
    }
}

// MARK: - Pane container

private struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The selected pane under its title bar. The content scrolls beneath the title bar when the screen is too short.
struct PaneContainer: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        let header = SPMetrics.Settings.titleBarHeight
        let padding = SPMetrics.Settings.contentPadding
        ZStack(alignment: .top) {
            ScrollView {
                pane
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, padding)
                    .padding(.top, header + padding)
                    .padding(.bottom, padding)
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                    })
                    .id(model.pane)
            }
            PaneHeader(title: model.pane.title)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onPreferenceChange(ContentHeightKey.self) { height in
            MainActor.assumeIsolated { model.contentHeight = height }
        }
    }

    @ViewBuilder private var pane: some View {
        switch model.pane {
        case .general: GeneralPane(accessibility: model.accessibility)
        case .privacy: PrivacyPane()
        case .shortcuts: ShortcutsPane()
        case .sync: SyncPane()
        case .integrations: IntegrationsPane()
        case .about: AboutPane()
        }
    }
}
