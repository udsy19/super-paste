import AppKit
import SwiftUI
import SuperPasteCore

/// Onboarding's pages, in order (behaviour.md §8): Paste's Introduction and Quick Start, then Super Paste's
/// Accessibility step, privacy notes and the two shortcuts to remember.
enum OnboardingPage: Int, CaseIterable {
    case intro, quickStart, accessibility, privacy, ready
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var page: OnboardingPage
    /// Quick Start's "Run in background": on the first time through, the current setting after that.
    @Published var openAtLogin: Bool
    let accessibility = PermissionMonitor(.accessibility)
    let sync = SyncModel(service: Services.sync)
    var close: () -> Void = {}

    init(page: OnboardingPage = .intro) {
        self.page = page
        openAtLogin = Defaults[.isOnboardingCompleted] ? Defaults[.openAtLogin] : true
        if page == .accessibility { accessibility.start() }
    }

    func next() {
        if page == .quickStart { complete() }
        guard let following = OnboardingPage(rawValue: page.rawValue + 1) else { close(); return }
        following == .accessibility ? accessibility.start() : accessibility.stop()
        withAnimation(.easeInOut(duration: SPMotion.onboardingPageDuration)) { page = following }
    }

    /// Quick Start's Continue completes onboarding: it applies the login item and sets the flag.
    private func complete() {
        if openAtLogin != Defaults[.openAtLogin] { LoginItem.set(openAtLogin) }
        Defaults[.isOnboardingCompleted] = true
    }
}

/// Shows onboarding in its own 544 × 652 window (ui-reference §12): at launch until completed, and again from the
/// app menu.
@MainActor
final class OnboardingController: NSObject, OnboardingPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private var model: OnboardingModel?

    var isCompleted: Bool { Defaults[.isOnboardingCompleted] }

    func show() {
        let window = self.window ?? makeWindow(page: .intro, snapshot: false)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Builds the window on `page` without showing it.
    func makeWindow(page: OnboardingPage, snapshot: Bool) -> NSWindow {
        let model = OnboardingModel(page: page)
        let size = SPMetrics.Onboarding.windowSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: true)
        model.close = { [weak window] in window?.close() }
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model)
            .frame(width: size.width, height: size.height)
            .environment(\.spStyle, snapshot ? .classic : .current))
        window.title = Strings.appName
        PermissionsController.styleBare(window)
        window.delegate = self
        if !snapshot { window.center() }
        self.window = window
        self.model = model
        return window
    }

    func windowWillClose(_ notification: Notification) {
        model?.accessibility.stop()
        model = nil
        window = nil
    }
}

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let intro = model.page == .intro
        let metrics = SPMetrics.Onboarding.self
        VStack(spacing: 0) {
            AppIconView(size: intro ? metrics.introIconSize : metrics.setupIconSize)
                .padding(.top, intro ? 120 : 44)
                .padding(.bottom, 20)
            ZStack {
                page
                    .id(model.page)
                    .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading))
                        .combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .padding(.bottom, 40)
    }

    @ViewBuilder private var page: some View {
        switch model.page {
        case .intro:
            OnboardingPageLayout(title: Strings.Onboarding.introTitle, subtitle: Strings.Onboarding.introSubtitle) {
                EmptyView()
            } footer: {
                SPButton(title: Strings.Action.getStarted, action: model.next).keyboardShortcut(.defaultAction)
            }
        case .quickStart:
            OnboardingPageLayout(title: Strings.Onboarding.setupTitle, subtitle: Strings.Onboarding.setupSubtitle) {
                QuickStartCard(model: model, sync: model.sync)
            } footer: {
                SPButton(title: Strings.Action.continue, action: model.next).keyboardShortcut(.defaultAction)
            }
        case .accessibility:
            PermissionScreen(monitor: model.accessibility, embedded: true, done: model.next)
        case .privacy:
            OnboardingPageLayout(title: Strings.Onboarding.privateTitle, subtitle: Strings.Onboarding.privateSubtitle) {
                PrivacyCard()
            } footer: {
                SPButton(title: Strings.Action.continue, action: model.next).keyboardShortcut(.defaultAction)
            }
        case .ready:
            OnboardingPageLayout(title: Strings.Onboarding.readyTitle, subtitle: Strings.Onboarding.readySubtitle) {
                ReadyCard()
            } footer: {
                SPButton(title: Strings.Action.done, action: model.next).keyboardShortcut(.defaultAction)
            }
        }
    }
}

/// Title (22 bold) and subtitle (13), the page's content, and its button at the bottom.
private struct OnboardingPageLayout<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            Text(title).font(.system(size: SPMetrics.Onboarding.titleFontSize, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: SPMetrics.Onboarding.cardWidth)
                .padding(.top, 8)
            content.padding(.top, 24)
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity)
    }
}

/// A 400-wide card on ink02, radius 10, rows padded 12 × 10 with dividers between them.
private struct OnboardingCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(width: SPMetrics.Onboarding.cardWidth)
        .background(RoundedRectangle(cornerRadius: SPMetrics.Onboarding.cardCornerRadius, style: .continuous)
            .fill(Color(nsColor: SPColor.ink02)))
    }
}

private struct CardRow<Accessory: View>: View {
    var symbol: String? = nil
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: symbol == nil ? .center : .top, spacing: 10) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Color.accentColor)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sp(.body, .medium))
                Text(subtitle).font(.sp(.callout)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            accessory
        }
        .padding(.horizontal, SPMetrics.Onboarding.rowPadding.width)
        .padding(.vertical, SPMetrics.Onboarding.rowPadding.height)
    }
}

private extension CardRow where Accessory == EmptyView {
    init(symbol: String, title: String, subtitle: String) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Quick Start: Run in background, Folder sync, Activation shortcut and Clipboard history.
private struct QuickStartCard: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var sync: SyncModel

    var body: some View {
        OnboardingCard {
            CardRow(title: Strings.Onboarding.runInBackground, subtitle: Strings.Onboarding.runInBackgroundInfo) {
                Toggle(Strings.Onboarding.runInBackground, isOn: $model.openAtLogin)
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider()
            CardRow(title: Strings.Onboarding.sync, subtitle: Strings.Onboarding.syncInfo) {
                Toggle(Strings.Onboarding.sync, isOn: Binding(get: { sync.isEnabled }, set: { sync.setEnabled($0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            Divider()
            CardRow(title: Strings.Onboarding.shortcut, subtitle: Strings.Onboarding.shortcutInfo) {
                ShortcutField(setting: .activation)
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                CardRow(title: Strings.Onboarding.history, subtitle: Strings.Onboarding.historyInfo) { EmptyView() }
                    .padding(.bottom, -SPMetrics.Onboarding.rowPadding.height)
                HistorySlider()
                    .padding(.horizontal, SPMetrics.Onboarding.rowPadding.width)
                    .padding(.bottom, SPMetrics.Onboarding.rowPadding.height)
            }
        }
    }
}

/// What stays local and what can leave the Mac, plus why macOS warned about the download.
private struct PrivacyCard: View {
    var body: some View {
        OnboardingCard {
            CardRow(symbol: "lock.laptopcomputer", title: Strings.Onboarding.localTitle, subtitle: Strings.Onboarding.localInfo)
            Divider()
            CardRow(symbol: "arrow.triangle.2.circlepath", title: Strings.Onboarding.syncTitle,
                    subtitle: Strings.Onboarding.syncDetail)
            Divider()
            CardRow(symbol: "arrow.down.circle", title: Strings.Onboarding.updatesTitle,
                    subtitle: Strings.Onboarding.updatesInfo)
            Divider()
            CardRow(symbol: "puzzlepiece.extension", title: Strings.Onboarding.mcpTitle, subtitle: Strings.Onboarding.mcpInfo)
            Divider()
            CardRow(symbol: "checkmark.shield", title: Strings.Onboarding.notarizedTitle,
                    subtitle: Strings.Onboarding.notarizedInfo)
        }
    }
}

/// The two shortcuts to remember, as keys.
private struct ReadyCard: View {
    @Default(.activationShortcut) private var activation
    @Default(.pasteStackShortcut) private var pasteStack

    var body: some View {
        OnboardingCard {
            row(activation, title: Strings.Shortcuts.activate, subtitle: Strings.Onboarding.activateInfo)
            Divider()
            row(pasteStack, title: Strings.Shortcuts.pasteStack, subtitle: Strings.Onboarding.stackInfo)
        }
    }

    private func row(_ shortcut: Shortcut?, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ShortcutKeys(shortcut: shortcut).frame(width: 98, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sp(.body, .medium))
                Text(subtitle).font(.sp(.callout)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, SPMetrics.Onboarding.rowPadding.width)
        .padding(.vertical, 14)
    }
}
