import AppKit
import SuperPasteCore

/// A tab: the clipboard history or a pinboard.
struct TabEntry: Equatable {
    var scope: ListScope
    var name: String
    var color: PinboardColor?

    var pinboardID: UUID? { if case .pinboard(let id) = scope { id } else { nil } }
}

@MainActor
protocol TabBarDelegate: AnyObject {
    func tabSelected(_ scope: ListScope)
    func tabMenu(for scope: ListScope) -> NSMenu?
    /// Inline rename ended; nil title when cancelled.
    func tabRenamed(_ pinboardID: UUID, to name: String?)
    func tabAcceptsDrop(_ scope: ListScope) -> Bool
    func tabDropped(_ itemIDs: [UUID], on scope: ListScope)
    func tabsReordered(_ pinboardIDs: [UUID])
    func tabTooltip(_ entry: TabEntry) -> String
}

/// `TabBar` (ui-reference §3.4): History and pinboard chips in a horizontally scrolling row, 1 pt edge shadows once
/// scrolled, 28 pt chips 8 apart.
final class TabBarView: FlippedView {
    weak var delegate: TabBarDelegate?
    var style: SPStyle = .current { didSet { chips.forEach { $0.style = style } } }

    private let scroll = NSScrollView()
    private let content = TabStripContent()
    private let leftShadow = GradientView()
    private let rightShadow = GradientView()
    private(set) var chips: [TabChipView] = []
    private(set) var entries: [TabEntry] = []
    var selected: ListScope = .history { didSet { chips.forEach { $0.isSelected = $0.entry.scope == selected } } }

    /// Insets of `TabBarScrollView` (6 / 7 / 6 / 7): 40 high, so chips are 28.
    static let insets = NSEdgeInsets(top: 6, left: 7, bottom: 6, right: 7)
    static let height: CGFloat = SPMetrics.TabBar.chipHeight + insets.top + insets.bottom

    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.drawsBackground = false
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = content
        scroll.contentView.postsBoundsChangedNotifications = true
        content.bar = self
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                               object: scroll.contentView)
        for shadow in [leftShadow, rightShadow] {
            shadow.colors = [.clear, NSColor.labelColor.withAlphaComponent(0.16), .clear]
            shadow.isHidden = true
        }
        addSubview(scroll)
        addSubview(leftShadow)
        addSubview(rightShadow)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func setEntries(_ entries: [TabEntry]) {
        guard entries != self.entries else { return }
        self.entries = entries
        chips.forEach { $0.removeFromSuperview() }
        chips = entries.map { entry in
            let chip = TabChipView(entry: entry, style: style)
            chip.bar = self
            chip.isSelected = entry.scope == selected
            chip.toolTip = delegate?.tabTooltip(entry)
            content.addSubview(chip)
            return chip
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    func chip(for scope: ListScope) -> TabChipView? { chips.first { $0.entry.scope == scope } }

    override var intrinsicContentSize: NSSize {
        NSSize(width: contentWidth, height: Self.height)
    }

    var contentWidth: CGFloat {
        let widths = chips.map(\.fittingSize.width)
        return Self.insets.left + widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * SPMetrics.TabBar.chipSpacing
            + Self.insets.right
    }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        var x = Self.insets.left
        for chip in chips {
            let size = chip.fittingSize
            chip.frame = NSRect(x: x, y: Self.insets.top, width: size.width, height: SPMetrics.TabBar.chipHeight)
            x += size.width + SPMetrics.TabBar.chipSpacing
        }
        content.frame = NSRect(x: 0, y: 0, width: max(contentWidth, bounds.width), height: bounds.height)
        leftShadow.frame = NSRect(x: 0, y: 0, width: 1, height: bounds.height)
        rightShadow.frame = NSRect(x: bounds.width - 1, y: 0, width: 1, height: bounds.height)
        scrolled()
    }

    @objc private func scrolled() {
        let offset = scroll.contentView.bounds.minX
        let threshold = SPMetrics.TabBar.edgeShadowThreshold
        leftShadow.isHidden = offset < threshold
        rightShadow.isHidden = content.frame.width - (offset + scroll.contentView.bounds.width) < threshold
    }

    func scrollToSelected() {
        guard let chip = chip(for: selected) else { return }
        content.scrollToVisible(chip.frame.insetBy(dx: -Self.insets.left, dy: 0))
    }

    // MARK: Chip events

    fileprivate func chipClicked(_ chip: TabChipView) { delegate?.tabSelected(chip.entry.scope) }
    fileprivate func chipMenu(_ chip: TabChipView) -> NSMenu? { delegate?.tabMenu(for: chip.entry.scope) }
    fileprivate func chipRenamed(_ chip: TabChipView, to name: String?) {
        if let id = chip.entry.pinboardID { delegate?.tabRenamed(id, to: name) }
    }
    fileprivate func chipAcceptsDrop(_ chip: TabChipView) -> Bool { delegate?.tabAcceptsDrop(chip.entry.scope) ?? false }
    fileprivate func chipDropped(_ ids: [UUID], on chip: TabChipView) { delegate?.tabDropped(ids, on: chip.entry.scope) }

    /// Moves a dragged pinboard tab to the chip gap nearest `x` (content coordinates).
    fileprivate func reorder(_ pinboardID: UUID, toX x: CGFloat) {
        var ids = entries.compactMap(\.pinboardID)
        guard let from = ids.firstIndex(of: pinboardID) else { return }
        let pinboardChips = chips.filter { $0.entry.pinboardID != nil }
        var to = pinboardChips.firstIndex { x < $0.frame.midX } ?? pinboardChips.count
        ids.remove(at: from)
        if to > from { to -= 1 }
        ids.insert(pinboardID, at: min(max(0, to), ids.count))
        delegate?.tabsReordered(ids)
    }

    /// Starts inline editing of a pinboard's name (new pinboards start this way, titled "Untitled").
    func beginRename(_ pinboardID: UUID) {
        chip(for: .pinboard(pinboardID))?.beginRename()
    }
}

/// The scrolling document of the tab bar; it takes pinboard-tab drops for reordering.
private final class TabStripContent: FlippedView {
    weak var bar: TabBarView?
    static let tabType = NSPasteboard.PasteboardType("org.superpaste.pinboard-tab")

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([Self.tabType])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.string(forType: Self.tabType) != nil ? .move : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let raw = sender.draggingPasteboard.string(forType: Self.tabType), let id = UUID(uuidString: raw) else { return false }
        bar?.reorder(id, toX: convert(sender.draggingLocation, from: nil).x)
        return true
    }
}

/// One tab chip: a 16 pt pinboard dot (or the History clock) and the name, on a capsule (glass) or 6 pt rectangle.
final class TabChipView: FillView, NSTextFieldDelegate, NSDraggingSource {
    let entry: TabEntry
    var style: SPStyle { didSet { update() } }
    fileprivate weak var bar: TabBarView?
    var isSelected = false { didSet { update() } }
    private var isHovered = false { didSet { update() } }
    private var isPressed = false { didSet { update() } }
    private var isDropTarget = false { didSet { update() } }
    private var editor: NSTextField?
    private var tracking: NSTrackingArea?
    private var pressPoint: NSPoint?

    private let icon = NSImageView()
    private let label = Labels.make(font: SPFont.style(.body), color: SPColor.ink85)

    init(entry: TabEntry, style: SPStyle) {
        self.entry = entry
        self.style = style
        super.init(frame: .zero)
        label.stringValue = entry.name
        icon.imageScaling = .scaleNone
        addSubview(icon)
        addSubview(label)
        registerForDraggedTypes(CardStripView.reorderTypes)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var iconBox: CGFloat {
        entry.color == nil ? SPMetrics.TabBar.historyIconBox : SPMetrics.TabBar.pinboardIconBox
    }

    private var labelWidth: CGFloat {
        let text = editor?.stringValue ?? entry.name
        let width = (text as NSString).size(withAttributes: [.font: label.font!]).width + 4
        return min(ceil(width), SPMetrics.TabBar.labelMaxWidth)
    }

    override var fittingSize: NSSize {
        let t = SPMetrics.TabBar.self
        return NSSize(width: t.chipIconInset + iconBox + t.chipLabelGap + labelWidth + t.chipIconInset, height: t.chipHeight)
    }

    private func update() {
        let metrics = SPMetrics(style: style)
        cornerRadius = metrics.tabChipRadius(height: SPMetrics.TabBar.chipHeight)
        cornerCurve = style == .glass ? .continuous : .circular
        if isPressed { fillColor = SPColor.ink10.withAlphaComponent(0.15) }
        else if isSelected || isDropTarget { fillColor = SPColor.ink10 }
        else if isHovered || editor != nil { fillColor = SPColor.ink05 }
        else { fillColor = nil }
        if let color = entry.color {
            let glyph = SPMetrics.TabBar.pinboardGlyphSize
            let box = SPMetrics.TabBar.pinboardIconBox
            let resolved = SPColor.pinboard(color, style: style)
            icon.image = NSImage(size: NSSize(width: box, height: box), flipped: false) { rect in
                resolved.setFill()
                NSBezierPath(ovalIn: NSRect(x: (rect.width - glyph) / 2, y: (rect.height - glyph) / 2, width: glyph,
                                            height: glyph)).fill()
                return true
            }
            icon.contentTintColor = nil
        } else {
            icon.image = Symbols.image("clock.arrow.circlepath",
                                       config: .init(pointSize: metrics.historyTabSymbolSize, weight: .regular))
            icon.contentTintColor = style == .glass ? SPColor.ink85 : SPColor.ink50
        }
    }

    override func layout() {
        super.layout()
        let t = SPMetrics.TabBar.self
        icon.frame = NSRect(x: t.chipIconInset, y: round((bounds.height - iconBox) / 2), width: iconBox, height: iconBox)
        let labelHeight = label.labelSize.height
        let labelFrame = NSRect(x: icon.frame.maxX + t.chipLabelGap, y: round((bounds.height - labelHeight) / 2),
                                width: max(0, bounds.width - icon.frame.maxX - t.chipLabelGap - t.chipIconInset),
                                height: labelHeight)
        label.frame = labelFrame
        editor?.frame = labelFrame
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard editor == nil else { return }
        if event.clickCount == 2, entry.pinboardID != nil { beginRename(); return }
        isPressed = true
        pressPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = pressPoint, let id = entry.pinboardID else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) >= SPMotion.dragThreshold else { return }
        pressPoint = nil
        isPressed = false
        let pbItem = NSPasteboardItem()
        pbItem.setString(id.uuidString, forType: TabStripContent.tabType)
        let item = NSDraggingItem(pasteboardWriter: pbItem)
        item.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        let wasPressed = isPressed
        isPressed = false
        pressPoint = nil
        if wasPressed, bounds.contains(convert(event.locationInWindow, from: nil)) { bar?.chipClicked(self) }
    }

    override func menu(for event: NSEvent) -> NSMenu? { bar?.chipMenu(self) }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    // MARK: Card drops (pin by dragging onto a tab)

    private func acceptsCards(_ info: NSDraggingInfo) -> Bool {
        guard let source = info.draggingSource as? CardStripView, !source.draggedIDs.isEmpty else { return false }
        return bar?.chipAcceptsDrop(self) ?? false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard acceptsCards(sender) else { return [] }
        isDropTarget = true
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { acceptsCards(sender) ? .copy : [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { isDropTarget = false }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDropTarget = false
        guard acceptsCards(sender), let source = sender.draggingSource as? CardStripView else { return false }
        bar?.chipDropped(source.draggedIDs, on: self)
        return true
    }

    // MARK: Rename (`TabBarCellLabel`)

    func beginRename() {
        guard editor == nil, entry.pinboardID != nil else { return }
        let field = NSTextField(string: entry.name)
        field.font = label.font
        field.textColor = label.textColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        label.isHidden = true
        addSubview(field)
        editor = field
        update()
        bar?.invalidateIntrinsicContentSize()
        bar?.superview?.needsLayout = true
        layout()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func controlTextDidChange(_ obj: Notification) {
        bar?.invalidateIntrinsicContentSize()
        bar?.superview?.needsLayout = true
        bar?.needsLayout = true
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): endRename(commit: true); return true
        case #selector(NSResponder.cancelOperation(_:)): endRename(commit: false); return true
        default: return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) { endRename(commit: true) }

    private func endRename(commit: Bool) {
        guard let field = editor else { return }
        editor = nil
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        label.isHidden = false
        update()
        bar?.chipRenamed(self, to: commit && !name.isEmpty ? name : nil)
    }
}
