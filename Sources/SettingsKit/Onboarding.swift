import AppKit
import SwiftUI
import SuperPasteCore

/// Onboarding's pages, in order (behaviour.md §8): Introduction, then Quick Start. Permissions are asked for on
/// demand (the first direct paste), not as onboarding pages.
enum OnboardingPage: Int, CaseIterable {
    case intro, quickStart
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published var page: OnboardingPage
    /// Quick Start's "Run in background": on the first time through, the current setting after that.
    @Published var openAtLogin: Bool
    let sync = SyncModel(service: Services.sync)
    /// Closes the window; `finished` says whether Quick Start completed (then the strip opens on the Welcome pinboard).
    var close: (_ finished: Bool) -> Void = { _ in }

    init(page: OnboardingPage = .intro) {
        self.page = page
        openAtLogin = Defaults[.isOnboardingCompleted] ? Defaults[.openAtLogin] : true
    }

    func next() {
        switch page {
        case .intro:
            withAnimation(.easeInOut(duration: SPMotion.onboardingPageDuration)) { page = .quickStart }
        case .quickStart:
            complete()
            close(true)
        }
    }

    /// Quick Start's Continue completes onboarding: it applies the login item and sets the flag.
    private func complete() {
        if openAtLogin != Defaults[.openAtLogin] { LoginItem.set(openAtLogin) }
        Defaults[.isOnboardingCompleted] = true
    }
}

/// Shows onboarding in its own 544 × 652 window (ui-reference §12): at launch until completed, and again from the
/// app menu. When Quick Start completes, the window closes, the Welcome pinboard is seeded (once) and the strip
/// slides up on it, so the first thing after onboarding is Super Paste itself (behaviour.md §8.4).
@MainActor
final class OnboardingController: NSObject, OnboardingPresenting, NSWindowDelegate {
    private var window: NSWindow?
    private var model: OnboardingModel?
    /// How long after the window closes the strip comes up.
    static let stripDelay: TimeInterval = 0.35

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
        model.close = { [weak self, weak window] finished in
            window?.close()
            if finished { self?.openStrip() }
        }
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

    /// The Welcome pinboard (seeded the first time) in the strip, once the window has gone.
    private func openStrip() {
        let scope = WelcomeContent.seedIfNeeded().map { ListScope.pinboard($0.id) } ?? .history
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stripDelay) {
            MainActor.assumeIsolated { Services.strip?.show(.list(scope)) }
        }
    }

    func windowWillClose(_ notification: Notification) {
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
    let title: String
    let subtitle: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
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
                ShortcutField(setting: .activation, width: SPMetrics.Onboarding.shortcutRecorderWidth)
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
