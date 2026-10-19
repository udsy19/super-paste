import AppKit
import Carbon.HIToolbox
import Combine
import SuperPasteCore

/// The Paste Stack panel (behaviour.md §3.6, ui-reference §9): shown while the stack is active. A 322 pt wide
/// non-activating status-level panel on popover material: close (leading), "Paste Stack" (bold 13, centred),
/// direction toggle (trailing), then 44 pt rows. Empty, it explains itself instead of showing a blank box: what
/// the stack does, and that copying something starts it. Esc (once the panel was clicked) and × end the stack.
@MainActor
final class PasteStackPanelController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = PasteStackPanelController()

    private(set) var panel: NSPanel?
    private(set) var state = PasteStackState()
    private var cancellable: AnyCancellable?
    private let table = NSTableView()
    private let closeButton = NSButton()
    private let directionButton = NSButton()
    private let titleLabel = Labels.make(L10n.pasteStack, font: .boldSystemFont(ofSize: 13), color: .labelColor, alignment: .center)
    private let emptyLabel = Labels.make(L10n.pasteStackEmptyText, font: .systemFont(ofSize: 13), color: .secondaryLabelColor,
                                         lines: 3, alignment: .center)
    private let emptyHint = Labels.make(L10n.pasteStackEmptyHint, font: .systemFont(ofSize: 11), color: .tertiaryLabelColor,
                                        lines: 2, alignment: .center)

    static let width = SPMetrics.PasteStack.windowSize.width
    static let titleTop: CGFloat = 8
    static let autosaveName = "org.superpaste.paste-stack-frame"

    func start() {
        cancellable = Services.pasting?.pasteStackChanges
            .sink { [weak self] state in self?.update(state) }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func update(_ state: PasteStackState) {
        self.state = state
        guard state.isActive else { panel?.orderOut(nil); return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        table.reloadData()
        emptyLabel.isHidden = !state.items.isEmpty
        emptyHint.isHidden = !state.items.isEmpty
        updateDirection()
        resize(panel)
        if panel.screen == nil { placeOnMainScreen(panel) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// A display went away under the panel (its saved frame may be on a screen that is no longer there).
    @objc private func screensChanged() {
        guard let panel, panel.isVisible, panel.screen == nil else { return }
        placeOnMainScreen(panel)
    }

    /// The top-right corner of the main screen, clear of the menu bar.
    private func placeOnMainScreen(_ panel: NSPanel) {
        let visible = (NSScreen.main ?? NSScreen.active).visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 20, y: visible.maxY - panel.frame.height - 20))
    }

    /// Header height: the title 8 from the top, the list 8 below it.
    private var headerHeight: CGFloat { Self.titleTop + titleLabel.labelSize.height + 8 }

    /// The empty state's block: the explanation, the hint, and 12 pt around and between them.
    static let emptyInset: CGFloat = 12
    private var emptyHeight: CGFloat {
        let width = Self.width - 2 * Self.emptyInset
        return Self.emptyInset + Labels.height(of: emptyLabel, width: width) + 8 + Labels.height(of: emptyHint, width: width)
            + Self.emptyInset
    }

    /// The window follows the row count, up to the storyboard's 372 pt; empty, it holds the explanation.
    func contentHeight(rows: Int) -> CGFloat {
        let p = SPMetrics.PasteStack.self
        let body = rows == 0 ? max(p.rowHeight, emptyHeight) : CGFloat(rows) * p.rowHeight
        return min(p.windowSize.height, headerHeight + body)
    }

    private func resize(_ panel: NSPanel) {
        let height = contentHeight(rows: state.items.count)
        var frame = panel.frame
        let newFrame = panel.frameRect(forContentRect: NSRect(x: 0, y: 0, width: Self.width, height: height))
        frame.origin.y += frame.height - newFrame.height
        frame.size = newFrame.size
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: Self.width, height: contentHeight(rows: state.items.count))
        let panel = PasteStackPanel(contentRect: NSRect(origin: .zero, size: size),
                                    styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: true)
        panel.onCancel = { Services.pasting?.stopPasteStack() }
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.level = SPMetrics.PasteStack.windowLevel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        if !panel.setFrameUsingName(Self.autosaveName) { placeOnMainScreen(panel) }
        panel.setFrameAutosaveName(Self.autosaveName)

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        panel.contentView = background
        let content = PasteStackContentView()
        content.autoresizingMask = [.width, .height]
        content.frame = background.bounds
        content.controller = self
        background.addSubview(content)

        closeButton.isBordered = false
        closeButton.image = NSImage(named: NSImage.stopProgressFreestandingTemplateName)
        closeButton.imageScaling = .scaleProportionallyDown
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        directionButton.isBordered = false
        directionButton.imageScaling = .scaleNone
        directionButton.target = self
        directionButton.action = #selector(toggleDirection)

        let column = NSTableColumn(identifier: .init("snippet"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = SPMetrics.PasteStack.rowHeight
        table.intercellSpacing = .zero
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = .separatorColor
        table.backgroundColor = .clear
        table.style = .plain
        table.selectionHighlightStyle = .none
        table.dataSource = self
        table.delegate = self
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        content.scroll = scroll
        [scroll, closeButton, titleLabel, directionButton, emptyLabel, emptyHint].forEach(content.addSubview)
        return panel
    }

    fileprivate func layout(in bounds: NSRect, scroll: NSScrollView?) {
        let side = SPMetrics.PasteStack.headerButtonSize
        let inset = SPMetrics.PasteStack.headerInset
        let titleHeight = titleLabel.labelSize.height
        titleLabel.frame = NSRect(x: inset + side + 8, y: Self.titleTop, width: max(0, bounds.width - 2 * (inset + side + 8)),
                                  height: titleHeight)
        closeButton.frame = NSRect(x: inset, y: titleLabel.frame.midY - side / 2, width: side, height: side)
        directionButton.frame = NSRect(x: bounds.width - inset - side, y: closeButton.frame.minY, width: side, height: side)
        let top = titleLabel.frame.maxY + 8
        scroll?.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        let width = bounds.width - 2 * Self.emptyInset
        let textHeight = Labels.height(of: emptyLabel, width: width)
        emptyLabel.frame = NSRect(x: Self.emptyInset, y: top + Self.emptyInset, width: width, height: textHeight)
        let hintHeight = Labels.height(of: emptyHint, width: width)
        emptyHint.frame = NSRect(x: Self.emptyInset, y: emptyLabel.frame.maxY + 8, width: width, height: hintHeight)
    }

    private func updateDirection() {
        directionButton.image = Self.directionImage(state.direction)
        directionButton.toolTip = state.direction == .top ? "Top" : "Bottom"
    }

    /// Stands in for `icon.sort-up` / `icon.sort-down`: an up and a down arrow, the active one in full ink.
    static func directionImage(_ direction: StackDirection) -> NSImage {
        let side = SPMetrics.PasteStack.headerButtonSize
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            func arrow(x: CGFloat, up: Bool, color: NSColor) {
                let top: CGFloat = 13.5, bottom: CGFloat = 2.5, head: CGFloat = 3
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x, y: bottom))
                path.line(to: NSPoint(x: x, y: top))
                let tip = up ? top : bottom, dir: CGFloat = up ? -1 : 1
                path.move(to: NSPoint(x: x - head, y: tip + dir * head))
                path.line(to: NSPoint(x: x, y: tip))
                path.line(to: NSPoint(x: x + head, y: tip + dir * head))
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                color.setStroke()
                path.stroke()
            }
            arrow(x: 4.5, up: true, color: direction == .top ? .labelColor : .tertiaryLabelColor)
            arrow(x: 11.5, up: false, color: direction == .bottom ? .labelColor : .tertiaryLabelColor)
            return true
        }
    }

    @objc private func closeClicked() { Services.pasting?.stopPasteStack() }

    @objc private func toggleDirection() {
        let next: StackDirection = state.direction == .top ? .bottom : .top
        Defaults[.pasteStackDirection] = next
        Services.pasting?.setPasteStackDirection(next)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { state.items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard state.items.indices.contains(row) else { return nil }
        let cell = (tableView.makeView(withIdentifier: PasteStackCell.identifier, owner: nil) as? PasteStackCell) ?? PasteStackCell()
        cell.configure(state.items[row])
        return cell
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard edge == .trailing, state.items.indices.contains(row) else { return [] }
        let id = state.items[row].id
        return [NSTableViewRowAction(style: .destructive, title: L10n.delete) { _, _ in
            MainActor.assumeIsolated { Services.pasting?.removeFromPasteStack([id]) }
        }]
    }

    static func symbol(for kind: ItemKind) -> String {
        switch kind {
        case .text, .richText, .html, .color: "text.alignleft"
        case .link: "link"
        case .files, .image: "doc"
        case .unknown: "questionmark.circle"
        }
    }
}

/// Esc ends the stack once the panel has keyboard focus (a click on it gives it that without activating the app).
private final class PasteStackPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { onCancel?() } else { super.keyDown(with: event) }
    }
}

private final class PasteStackContentView: FlippedView {
    weak var controller: PasteStackPanelController?
    var scroll: NSScrollView?

    override func layout() {
        super.layout()
        controller?.layout(in: bounds, scroll: scroll)
    }
}

/// A snippet row: the 20 pt type icon and up to two lines of text.
private final class PasteStackCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("PasteStackCell")
    private let icon = NSImageView()
    private let label = Labels.make(font: .systemFont(ofSize: 13), color: .labelColor, lines: 2)

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        icon.contentTintColor = .secondaryLabelColor
        addSubview(icon)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ item: ClipItem) {
        icon.image = Symbols.image(PasteStackPanelController.symbol(for: item.kind),
                                   config: .init(pointSize: 15, weight: .regular))
        label.stringValue = ItemPresentation.summary(item)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let side = SPMetrics.PasteStack.rowIconSize
        icon.frame = NSRect(x: 12, y: round((bounds.height - side) / 2), width: side, height: side)
        let width = max(0, bounds.width - icon.frame.maxX - 8 - 12)
        let height = min(Labels.height(of: label, width: width), bounds.height - 4)
        label.frame = NSRect(x: icon.frame.maxX + 8, y: round((bounds.height - height) / 2), width: width, height: height)
    }
}
