import AppKit
import SuperPasteCore

// Menus: the card context menu (ui-reference §4.8), the tab menu (§3.4), the "…" app menu (behaviour.md §6.2) and
// the pause item's menu.
extension StripController {
    // MARK: Card context menu

    func contextMenu(forCardAt index: Int) -> NSMenu? {
        let items = selectedItems
        guard let first = items.first else { return nil }
        let single = items.count == 1
        let menu = NSMenu()
        menu.autoenablesItems = false
        if !single { menu.addItem(.sectionHeader(title: L10n.selected(items.count))) }

        // Open, Reveal in Finder, Show in …
        var group: [NSMenuItem] = []
        if single, let title = Self.openTitle(first) {
            group.append(.make(title, symbol: "arrow.up.forward.square", key: "o") { [weak self] in self?.open(items) })
        }
        if single, first.kind == .files {
            group.append(.make(L10n.revealInFinder, symbol: "finder") { [weak self] in self?.revealInFinder(first) })
        }
        if single {
            for (offset, target) in showInTargets(for: first).enumerated() {
                let symbol = target == .history ? "clock.arrow.circlepath" : "circlebadge"
                group.append(.make(L10n.showIn(listName(target)), symbol: symbol, key: offset == 0 ? "g" : "") { [weak self] in
                    self?.reveal(first, in: target)
                })
            }
        }
        addGroup(group, to: menu)

        // Paste, Paste as Plain Text, Copy
        let target = Services.pasting?.target?.name
        let plainMods = StripKeyBindings.current.plainTextModifiers
        addGroup([
            .make(L10n.pasteTo(target), symbol: "doc.on.clipboard", key: "\r", modifiers: []) { [weak self] in
                self?.paste(items, plainText: false)
            },
            .make(L10n.pasteAsPlainText, symbol: "text.justify.leading", key: plainMods.isEmpty ? "" : "\r",
                    modifiers: plainMods) { [weak self] in self?.paste(items, plainText: true) },
            .make(L10n.copy, symbol: "doc.on.doc", key: "c") { [weak self] in self?.copy(items, plainText: false) },
        ], to: menu)

        // Edit, Rename, Delete
        addGroup([
            .make(L10n.edit, symbol: "pencil", key: "e", enabled: single && Self.isEditable(first)) { [weak self] in
                self?.perform(.edit)
            },
            .make(L10n.rename, symbol: "pencil.and.ellipsis.rectangle", key: "r", enabled: single) { [weak self] in
                self?.beginRename()
            },
            .make(L10n.delete, symbol: "trash", key: "\u{8}", modifiers: []) { [weak self] in self?.delete(items) },
        ], to: menu)

        // Pin ▸
        let pin = NSMenuItem(title: L10n.pin, action: nil, keyEquivalent: "").withSymbol("pin")
        pin.submenu = pinMenu(for: items)
        addGroup([pin], to: menu)

        // Preview, Share ▸
        var last: [NSMenuItem] = [
            .make(L10n.preview, symbol: "eye", key: " ", modifiers: []) { [weak self] in
                guard let self else { return }
                self.preview.toggle(items, from: self.leadCard)
            },
        ]
        if let share = shareItem(for: items) { last.append(share) }
        addGroup(last, to: menu)
        return menu
    }

    private func addGroup(_ group: [NSMenuItem], to menu: NSMenu) {
        guard !group.isEmpty else { return }
        if menu.items.contains(where: { !$0.isSectionHeader }) { menu.addItem(.separator()) }
        group.forEach(menu.addItem)
    }

    /// One item per pinboard (with its colour dot), then Create Pinboard and Unpin.
    func pinMenu(for items: [ClipItem]) -> NSMenu {
        let menu = NSMenu(title: L10n.pin)
        menu.autoenablesItems = false
        for board in pinboards {
            let item = NSMenuItem.make(board.name) { [weak self] in self?.pin(items, to: board.id) }
            item.image = Symbols.dot(SPColor.pinboard(board.color, style: style), side: SPMetrics.Cards.pinboardIconSize)
            item.state = !items.isEmpty && items.allSatisfy { $0.isPinned(to: board.id) } ? .on : .off
            menu.addItem(item)
        }
        if !pinboards.isEmpty { menu.addItem(.separator()) }
        menu.addItem(.make(L10n.createPinboard, symbol: "plus") { [weak self] in self?.createPinboard(pinning: items) })
        menu.addItem(.make(L10n.unpin, enabled: items.contains { $0.isPinned }) { [weak self] in self?.unpin(items) })
        return menu
    }

    /// The system share menu for what the items are: URLs, files, images or text.
    private func shareItem(for items: [ClipItem]) -> NSMenuItem? {
        let objects: [Any] = items.compactMap { item -> Any? in
            switch item.kind {
            case .link: return ItemPresentation.linkURL(item)
            case .files: return item.filePaths.first.map { URL(fileURLWithPath: $0) }
            case .image: return ItemAssets.shared.fullImage(for: item)
            case .unknown: return nil
            default: return item.text.isEmpty ? nil : item.text
            }
        }
        guard !objects.isEmpty else { return nil }
        let picker = NSSharingServicePicker(items: objects)
        let item = picker.standardShareMenuItem
        item.title = L10n.share
        _ = item.withSymbol("square.and.arrow.up")
        return item
    }

    // MARK: Tab menu

    func tabMenu(for scope: ListScope) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch scope {
        case .history, .all:
            menu.addItem(.make(L10n.eraseHistory, symbol: "trash") { [weak self] in self?.eraseHistory() })
        case .pinboard(let id):
            guard let board = pinboards.first(where: { $0.id == id }) else { return nil }
            menu.addItem(.make(L10n.rename, symbol: "pencil") { [weak self] in self?.toolbar?.tabBar.beginRename(id) })
            let colors = NSMenuItem()
            let row = ColorRowView(selected: board.color, style: style)
            row.onPick = { [weak self, weak menu] color in
                menu?.cancelTracking()
                self?.recolorPinboard(id, to: color)
            }
            colors.view = row
            menu.addItem(colors)
            menu.addItem(.separator())
            menu.addItem(.make(L10n.delete, symbol: "trash") { [weak self] in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.deletePinboard(id) } }
            })
        }
        return menu
    }

    // MARK: "…" menu

    func overflowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.make(L10n.about, symbol: "info.circle") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(.separator())
        menu.addItem(.make(L10n.newTextItem, symbol: "square.and.pencil", key: "n") { [weak self] in
            guard let self else { return }
            self.newTextItem.show(in: self.scope)
        })
        menu.addItem(.make(L10n.settings, symbol: "gear", key: ",") { [weak self] in self?.perform(.settings) })
        menu.addItem(.separator())
        let pause = NSMenuItem(title: Services.clipboard?.isPaused == true ? pausedTitle : L10n.pause, action: nil,
                               keyEquivalent: "").withSymbol("pause.circle")
        pause.submenu = pauseMenu()
        menu.addItem(pause)
        menu.addItem(.separator())
        menu.addItem(.make(L10n.quit, symbol: "xmark.app", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    /// Pause Super Paste / Resume, then Pause for 15m … 8h (behaviour.md §6.3).
    func pauseMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let clipboard = Services.clipboard
        if clipboard?.isPaused == true {
            let status = NSMenuItem(title: pausedTitle, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
            menu.addItem(.make(L10n.resume, symbol: "play.circle", key: "t") { clipboard?.resume() })
        } else {
            menu.addItem(.make(L10n.pauseSuperPaste, symbol: "pause.circle", key: "t") { clipboard?.pause(until: nil) })
        }
        menu.addItem(.separator())
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        let symbols = ["15.circle", "30.circle", "1.circle", "3.circle", "8.circle"]
        for (duration, symbol) in zip(PauseDurations.all, symbols) {
            let title = L10n.pauseFor(formatter.string(from: duration) ?? "")
            menu.addItem(.make(title, symbol: symbol) { clipboard?.pause(until: Date().addingTimeInterval(duration)) })
        }
        return menu
    }

    func configureToolbar() {
        guard let toolbar else { return }
        toolbar.plusButton.action = { [weak self] _ in self?.createPinboard() }
        toolbar.menuButton.menuProvider = { [weak self] in self?.overflowMenu() }
    }
}

// MARK: - Colour row

/// The tab menu's colour picker (ui-reference §3.4): eight 22 pt cells 2 apart, insets 2 / 10 / 2 / 10, 26 high; a
/// 1 pt ring around a 14 pt swatch, filled with `textBackgroundColor` and bordered `ink26` when selected or hovered.
final class ColorRowView: FlippedView {
    var onPick: ((PinboardColor) -> Void)?
    private let selected: PinboardColor
    private let style: SPStyle
    private var hovered: PinboardColor?
    private var tracking: NSTrackingArea?

    static let insets = NSEdgeInsets(top: 2, left: 10, bottom: 2, right: 10)

    init(selected: PinboardColor, style: SPStyle) {
        self.selected = selected
        self.style = style
        let t = SPMetrics.TabBar.self
        let count = CGFloat(PinboardColor.allCases.count)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.insets.left + count * t.colorCellSize + (count - 1) * 2 + Self.insets.right,
                                 height: t.colorRowHeight))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func cellRect(_ index: Int) -> NSRect {
        let t = SPMetrics.TabBar.self
        return NSRect(x: Self.insets.left + CGFloat(index) * (t.colorCellSize + 2), y: Self.insets.top,
                      width: t.colorCellSize, height: t.colorCellSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = (SPMetrics.TabBar.colorCellSize - SPMetrics.TabBar.colorSwatchSize) / 2
        for (index, color) in PinboardColor.allCases.enumerated() {
            let cell = cellRect(index)
            let ring = NSBezierPath(ovalIn: cell.insetBy(dx: 0.5, dy: 0.5))
            if color == selected {
                NSColor.textBackgroundColor.setFill()
                ring.fill()
            }
            if color == selected || color == hovered {
                SPColor.ink26.setStroke()
                ring.lineWidth = 1
                ring.stroke()
            }
            SPColor.pinboard(color, style: style).setFill()
            NSBezierPath(ovalIn: cell.insetBy(dx: inset, dy: inset)).fill()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    private func color(at event: NSEvent) -> PinboardColor? {
        let point = convert(event.locationInWindow, from: nil)
        return PinboardColor.allCases.indices.first { cellRect($0).contains(point) }.map { PinboardColor.allCases[$0] }
    }

    override func mouseMoved(with event: NSEvent) { hovered = color(at: event); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }
    override func mouseUp(with event: NSEvent) { if let color = color(at: event) { onPick?(color) } }
}
