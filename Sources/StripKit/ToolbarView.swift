import AppKit
import SuperPasteCore

/// The strip's top bar (ui-reference §3.1), 60 pt: notification bar, search, tab bar (centred), "+", "…".
final class ToolbarView: FlippedView {
    let style: SPStyle
    let notificationBar = NotificationBarView()
    let search = SearchFieldView()
    let tabBar = TabBarView()
    let plusButton: ToolbarButton
    let menuButton: ToolbarButton

    private(set) var isSearchActive = false

    init(style: SPStyle) {
        self.style = style
        plusButton = ToolbarButton(size: .large, style: style, symbol: "plus")
        menuButton = ToolbarButton(size: .large, style: style, symbol: "ellipsis")
        super.init(frame: .zero)
        plusButton.toolTip = L10n.createPinboard
        notificationBar.style = style
        search.style = style
        tabBar.style = style
        [notificationBar, search, tabBar, plusButton, menuButton].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Opens or closes the search layout: the field centred, ≥ 400 pt and ≥ 25 % wide, the tabs collapsed to their
    /// icons after it and "+" folded away; animated with ease-out (ui-reference §3.1, §3.4).
    func setSearchActive(_ active: Bool, animated: Bool) {
        guard active != isSearchActive else { return }
        isSearchActive = active
        tabBar.isCollapsed = active
        let frames = self.frames(searchActive: active)
        guard animated, window?.isVisible == true else {
            apply(frames, alpha: active ? 0 : 1)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            apply(frames, alpha: active ? 0 : 1, animator: true)
        }
    }

    override func layout() {
        super.layout()
        apply(frames(searchActive: isSearchActive), alpha: isSearchActive ? 0 : 1)
    }

    private struct Frames {
        var bar, search, tabs, plus, menu: NSRect
    }

    private func apply(_ f: Frames, alpha: CGFloat, animator: Bool = false) {
        func set(_ view: NSView, _ frame: NSRect) { if animator { view.animator().frame = frame } else { view.frame = frame } }
        set(notificationBar, f.bar)
        set(search, f.search)
        set(tabBar, f.tabs)
        set(plusButton, f.plus)
        set(menuButton, f.menu)
        if animator {
            plusButton.animator().alphaValue = alpha
        } else {
            plusButton.alphaValue = alpha
        }
    }

    private func frames(searchActive: Bool) -> Frames {
        let t = SPMetrics.Toolbar.self
        let metrics = SPMetrics(style: style)
        let width = bounds.width, height = bounds.height
        let button = t.largeButtonSize
        let buttonY = round((height - button) / 2)
        let barWidth = notificationBar.contentWidth
        let bar = NSRect(x: t.edgeInset, y: 0, width: barWidth, height: height)
        let menu = NSRect(x: width - t.edgeInset - button, y: buttonY, width: button, height: button)
        let leftLimit = barWidth > 0 ? bar.maxX + t.itemSpacing : t.edgeInset
        let rightLimit = menu.minX - metrics.toolbarMenuGap
        let searchHeight = SearchFieldView.height
        let searchY = round((height - searchHeight) / 2)
        let tabsY = SPMetrics.TabBar.verticalInset
        let tabsHeight = TabBarView.height

        if searchActive {
            // The collapsed tabs keep their place after the field; the field centres as far as that allows.
            let tabsWidth = max(0, min(tabBar.contentWidth, rightLimit - leftLimit - t.activeSearchMinWidth - t.itemSpacing))
            let w = min(max(t.activeSearchMinWidth, width * t.activeSearchMinFraction),
                        max(0, rightLimit - leftLimit - t.itemSpacing - tabsWidth))
            var x = round((width - w) / 2)
            x = min(max(x, leftLimit), rightLimit - tabsWidth - t.itemSpacing - w)
            let search = NSRect(x: x, y: searchY, width: w, height: searchHeight)
            let tabs = NSRect(x: search.maxX + t.itemSpacing, y: tabsY, width: tabsWidth, height: tabsHeight)
            // "+" snaps to the tab bar's trailing edge, hidden.
            let plus = NSRect(x: tabs.maxX - button, y: buttonY, width: button, height: button)
            return Frames(bar: bar, search: search, tabs: tabs, plus: plus, menu: menu)
        }

        let searchWidth = search.collapsedWidth
        let fixed = searchWidth + t.itemSpacing + t.itemSpacing + button
        let tabsWidth = max(0, min(tabBar.contentWidth, rightLimit - leftLimit - fixed))
        var tabsX = round((width - tabsWidth) / 2)
        tabsX = min(max(tabsX, leftLimit + searchWidth + t.itemSpacing), rightLimit - button - t.itemSpacing - tabsWidth)
        let tabs = NSRect(x: tabsX, y: tabsY, width: tabsWidth, height: tabsHeight)
        let search = NSRect(x: tabs.minX - t.itemSpacing - searchWidth, y: searchY, width: searchWidth, height: searchHeight)
        let plus = NSRect(x: tabs.maxX + t.itemSpacing, y: buttonY, width: button, height: button)
        return Frames(bar: bar, search: search, tabs: tabs, plus: plus, menu: menu)
    }
}

/// `NotificationBar` (ui-reference §3.1 item 2): a row of 28 pt status items 8 apart — Paste Paused (`pause.circle`,
/// a menu with "Paused until …" and Resume) and Syncing (`arrow.triangle.2.circlepath`).
final class NotificationBarView: FlippedView {
    var style: SPStyle = .current { didSet { items.forEach { $0.style = style } } }
    private(set) var items: [ToolbarButton] = []
    static let itemSize: CGFloat = 28

    /// Replaces the items; each is a symbol with a tooltip and either a menu or an action.
    func setItems(_ items: [ToolbarButton]) {
        self.items.forEach { $0.removeFromSuperview() }
        self.items = items
        items.forEach { $0.style = style; addSubview($0) }
        superview?.needsLayout = true
        needsLayout = true
    }

    var contentWidth: CGFloat {
        items.isEmpty ? 0 : CGFloat(items.count) * Self.itemSize + CGFloat(items.count - 1) * SPMetrics.Toolbar.itemSpacing
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for item in items {
            item.frame = NSRect(x: x, y: round((bounds.height - Self.itemSize) / 2), width: Self.itemSize, height: Self.itemSize)
            x += Self.itemSize + SPMetrics.Toolbar.itemSpacing
        }
    }
}
