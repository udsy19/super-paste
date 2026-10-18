import AppKit
import Combine
import SuperPasteCore

/// The strip (behaviour.md §4, ui-reference §2–§4): the bottom panel, its list, search and actions.
@MainActor
final class StripController: NSObject, StripPresenting, NSWindowDelegate {
    let style: SPStyle
    private(set) var panel: StripPanel?
    private(set) var root: StripRootView?
    var cards: CardStripView? { root?.cards }
    var toolbar: ToolbarView? { root?.toolbar }

    // MARK: State

    /// The list shown: History or a pinboard.
    var scope: ListScope
    var query = SearchQuery.empty
    /// Loaded items (pages of `pageSize`) and the total the query matches.
    var items: [ClipItem] = []
    var total = 0
    var selection = SelectionState()
    var pinboards: [Pinboard] = []
    var panelHeight: CGFloat
    static let pageSize = 200

    let undo = UndoManager()
    let preview = PreviewController()
    lazy var newTextItem = NewTextItemController()
    let sidecar = SidecarModel()

    private let visibility = CurrentValueSubject<Bool, Never>(false)
    private var cancellables: Set<AnyCancellable> = []
    var needsReload = true
    var reloadScheduled = false
    private var resetWorkItem: DispatchWorkItem?
    private var flagsMonitor: Any?
    private var dateTimer: Timer?
    /// While > 0, the strip stays open when it loses key (alerts, menus, drags).
    var hideSuppression = 0
    private var hiding = false

    init(style: SPStyle = .current) {
        self.style = style
        scope = ListScope(id: Defaults[.selectedListIdentifier]) ?? .history
        if scope == .all { scope = .history }
        panelHeight = SPMetrics.Strip.clampedHeight(CGFloat(Defaults[.stripHeight]))
        super.init()
        preview.strip = self
        newTextItem.strip = self
        // One undo step per change, not per run-loop event (a change can register more than one step).
        undo.groupsByEvent = false
    }

    /// Hooks up store and pause changes. Called once from `StripKitModule.install()`.
    func start() {
        Services.store?.changes
            .sink { [weak self] change in self?.storeChanged(change) }
            .store(in: &cancellables)
        Services.clipboard?.pauseChanges
            .sink { [weak self] _ in self?.updateNotificationBar() }
            .store(in: &cancellables)
        Services.sync?.statusChanges
            .sink { [weak self] _ in self?.updateNotificationBar() }
            .store(in: &cancellables)
        Defaults.changes
            .filter { [Defaults.Keys.isLinkPreviewsEnabled.name, Defaults.Keys.isFileItemQLThumbnailImageEnabled.name].contains($0) }
            .sink { [weak self] _ in self?.cards?.refreshVisibleCards() }
            .store(in: &cancellables)
    }

    // MARK: StripPresenting

    var isVisible: Bool { visibility.value }
    var visibilityChanges: AnyPublisher<Bool, Never> { visibility.removeDuplicates().eraseToAnyPublisher() }

    func toggle() { isVisible ? hide() : show(nil) }

    func show(_ route: StripRoute?) {
        if case .newTextItem? = route { newTextItem.show(in: scope); return }
        loadViewsIfNeeded()
        resetWorkItem?.cancel()
        resetWorkItem = nil
        if let route { apply(route) } else if needsReload { reload(keepSelection: true) }
        if !isVisible || hiding { present() }
        if case .preview(let id)? = route { revealAndPreview(id, edit: false) }
        if case .edit(let id)? = route { revealAndPreview(id, edit: true) }
    }

    func hide() {
        guard isVisible, let panel, let root else { return }
        hiding = true
        visibility.send(false)
        preview.closePopover()
        endModifierMonitoring()
        dateTimer?.invalidate()
        dateTimer = nil
        panel.makeFirstResponder(nil)
        if style == .classic { panel.backgroundColor = .clear }
        let height = panel.frame.height
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = SPMotion.stripHideDuration
            context.timingFunction = SPMotion.stripHideTiming
            root.animator().setFrameOrigin(NSPoint(x: 0, y: -height))
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.hiding else { return }
                self.hiding = false
                panel.orderOut(nil)
                self.scheduleClosedStateReset()
            }
        })
    }

    // MARK: Panel

    func loadViewsIfNeeded() {
        guard panel == nil else { return }
        let panel = StripPanel()
        let root = StripRootView(style: style)
        // Not flipped: the root slides in from y = −height (below the screen edge) to 0.
        let container = NSView()
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.addSubview(root)
        panel.contentView = container
        panel.delegate = self
        root.keyHandler = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        root.cards.delegate = self
        root.toolbar.tabBar.delegate = self
        root.toolbar.search.delegate = self
        root.resizeHandle.onResize = { [weak self] height in self?.resize(to: height, save: false, animated: false) }
        root.resizeHandle.onEnd = { [weak self] height in self?.resize(to: height, save: true, animated: true) }
        root.resizeHandle.onReset = { [weak self] in self?.resize(to: SPMetrics.Strip.defaultHeight, save: true, animated: true) }
        NotificationCenter.default.addObserver(self, selector: #selector(clipScrolled),
                                               name: NSView.boundsDidChangeNotification, object: root.scrollView.contentView)
        self.panel = panel
        self.root = root
        configureToolbar()
        updateNotificationBar()
        reloadPinboards()
    }

    /// Lays the views out for `frame` without animating (also used for offscreen renders).
    func layoutForFrame(_ frame: NSRect) {
        guard let panel, let root else { return }
        panel.setFrame(frame, display: false)
        pinSize(of: panel)
        panelHeight = frame.height
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        root.frame = NSRect(origin: .zero, size: frame.size)
        root.layoutSubtreeIfNeeded()
        updateGeometry()
    }

    private func present() {
        guard let panel, let root else { return }
        hiding = false
        let screen = NSScreen.main ?? NSScreen.active
        let height = SPMetrics.Strip.clampedHeight(CGFloat(Defaults[.stripHeight]))
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
        panel.sharingType = Defaults[.isScreenSharingContentVisible] ? .readOnly : .none
        layoutForFrame(frame)
        if needsReload { reload(keepSelection: true) }
        cards?.reloadData()
        root.setFrameOrigin(NSPoint(x: 0, y: -height))
        panel.backgroundColor = .clear
        panel.orderFrontRegardless()
        panel.makeKey()
        focusCards()
        visibility.send(true)
        beginModifierMonitoring()
        startDateTimer()
        updateSidecar()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = SPMotion.stripShowDuration
            context.timingFunction = SPMotion.stripShowTiming
            root.animator().setFrameOrigin(.zero)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.style == .classic, self.isVisible else { return }
                self.panel?.backgroundColor = .windowBackgroundColor
            }
        })
        if let selected = selection.lead { cards?.scrollToReveal(selected, animated: false) }
    }

    private func resize(to height: CGFloat, save: Bool, animated: Bool) {
        guard let panel else { return }
        let clamped = SPMetrics.Strip.clampedHeight(height)
        var frame = panel.frame
        frame.size.height = clamped
        if save { Defaults[.stripHeight] = Double(clamped) }
        panelHeight = clamped
        panel.setFrame(frame, display: true, animate: animated)
        pinSize(of: panel)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        root?.frame = NSRect(origin: .zero, size: frame.size)
        root?.layoutSubtreeIfNeeded()
        updateGeometry()
        cards?.reloadData()
    }

    /// Only the resize handle changes the height: the window's own resizing is pinned to the current size (§2.1).
    private func pinSize(of panel: NSPanel) {
        panel.minSize = panel.frame.size
        panel.maxSize = panel.frame.size
    }

    private func updateGeometry() {
        guard let cards else { return }
        cards.geometry = StripGeometry(style: style, panelHeight: panelHeight)
        cards.leading = cards.geometry.leading(sidecarWidth: sidecarWidth)
    }

    /// The closed-state reset ~10 s after the strip closes: clear the search and go back to the first card.
    private func scheduleClosedStateReset() {
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isVisible else { return }
                self.toolbar?.search.clear()
                self.selection.clear()
                if !self.items.isEmpty { self.selection.click(0, mode: .single) }
                self.cards?.scrollToStart()
            }
        }
        resetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SPMotion.closedStateResetDelay, execute: work)
    }

    // MARK: Window delegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { undo }

    func windowDidResignKey(_ notification: Notification) {
        cards?.isDimmed = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.closeIfFocusLeft() }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        cards?.isDimmed = false
    }

    /// Closes when focus went to another app; stays while one of Super Paste's own windows took it (preview, New Text
    /// Item, alerts) or while something holds the strip open (behaviour.md §4.1).
    private func closeIfFocusLeft() {
        guard isVisible, !hiding, hideSuppression == 0, panel?.isKeyWindow == false else { return }
        if let key = NSApp.keyWindow, key !== panel { return }
        if preview.isShowing || NSApp.modalWindow != nil { return }
        hide()
    }

    // MARK: Focus

    func focusCards() {
        guard let panel, let cards else { return }
        panel.makeFirstResponder(cards)
    }

    var isSearchFocused: Bool {
        guard let responder = panel?.firstResponder, let textView = toolbar?.search.textView else { return false }
        return responder === textView
    }

    // MARK: Modifier keys (quick-paste badges)

    private func beginModifierMonitoring() {
        guard flagsMonitor == nil else { return }
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated { self?.modifiersChanged(event.modifierFlags) }
            return event
        }
    }

    private func endModifierMonitoring() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        flagsMonitor = nil
        cards?.showsQuickPasteNumbers = false
        cards?.showsPlainTextIndicator = false
    }

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let badges = StripMouseMap.badges(held: flags, bindings: .current)
        cards?.showsQuickPasteNumbers = badges.numbers
        cards?.showsPlainTextIndicator = badges.plainText
    }

    private func startDateTimer() {
        dateTimer?.invalidate()
        dateTimer = Timer.scheduledTimer(withTimeInterval: SPMotion.dateRefreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.cards?.refreshDates(now: Date()) }
        }
    }

    @objc private func clipScrolled() {
        cards?.tile()
    }

    // MARK: Routes

    private func apply(_ route: StripRoute) {
        switch route {
        case .list(let scope):
            toolbar?.search.clear()
            setScope(scope == .all ? .history : scope)
        case .search(let text):
            toolbar?.search.setQuery(SearchQuery(parsing: text))
            toolbar?.search.activate()
        case .preview, .edit, .newTextItem:
            if needsReload { reload(keepSelection: true) }
        }
    }

    private func revealAndPreview(_ id: UUID, edit: Bool) {
        guard let item = Services.store?.item(id) else { return }
        reveal(item)
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        cards?.scrollToReveal(index, animated: false)
        cards?.tile()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let card = self.cards?.cardView(at: index) else { return }
                if edit { self.preview.edit(item, from: card) } else { self.preview.show([item], from: card) }
            }
        }
    }

    // MARK: Notification bar

    func updateNotificationBar() {
        guard let toolbar else { return }
        var items: [ToolbarButton] = []
        if Services.clipboard?.isPaused == true {
            let pause = ToolbarButton(size: .large, style: style, symbol: "pause.circle")
            pause.toolTip = AppMenu.pauseStatus
            pause.menuOffsetY = -10
            pause.menuProvider = { AppMenu.makePauseMenu() }
            items.append(pause)
        }
        if case .syncing? = Services.sync?.status {
            let sync = ToolbarButton(size: .large, style: style, symbol: "arrow.triangle.2.circlepath")
            sync.toolTip = L10n.syncing
            sync.action = { _ in Services.settings?.show(pane: .sync) }
            items.append(sync)
        }
        toolbar.notificationBar.setItems(items)
        toolbar.needsLayout = true
    }

    // MARK: Sidecar

    var sidecarWidth: CGFloat { sidecar.width(cardSide: cards?.geometry.cardSide ?? 0) }

    func updateSidecar() {
        sidecar.refresh()
        guard let cards else { return }
        sidecar.install(in: cards, geometry: cards.geometry) { [weak self] in
            self?.updateGeometry()
            self?.cards?.reloadData()
        }
        updateGeometry()
        cards.reloadData()
    }
}
