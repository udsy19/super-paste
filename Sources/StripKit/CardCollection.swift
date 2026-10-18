import AppKit
import SuperPasteCore

/// What the card row asks of the strip.
@MainActor
protocol CardCollectionDelegate: AnyObject {
    var cardCount: Int { get }
    func item(at index: Int) -> ClipItem?
    func cardContext() -> CardContext
    func isCardSelected(_ index: Int) -> Bool
    func cardClicked(_ index: Int, mode: SelectionMode)
    /// A double click pastes the card (as plain text while the plain-text modifiers are held).
    func cardDoubleClicked(_ index: Int, plainText: Bool)
    func emptyAreaClicked()
    func contextMenu(forCardAt index: Int) -> NSMenu?
    /// The items a drag that starts on `index` carries: the selection when the card is selected.
    func dragItems(startingAt index: Int) -> [ClipItem]
    /// Whether the list can be reordered by dragging (a pinboard without a search).
    var canReorderCards: Bool { get }
    func moveCards(_ ids: [UUID], toIndex index: Int)
    /// Cards became visible up to this index (more pages load near the end).
    func cardsVisible(through index: Int)
    func handleKey(_ event: NSEvent) -> Bool
    func dragSessionChanged(active: Bool)
}

/// `NoShiftHorizontalScrollView` (ui-reference §4.7): scrolls horizontally only, turning vertical wheel deltas into
/// horizontal ones; elastic sideways, never vertically; no scrollers, no background.
final class CardScrollView: NSScrollView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        drawsBackground = false
        contentView.drawsBackground = false
        contentView.postsBoundsChangedNotifications = true
        usesPredominantAxisScrolling = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func scrollWheel(with event: NSEvent) {
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let cg = event.cgEvent?.copy() else {
            super.scrollWheel(with: event); return
        }
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: cg.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: cg.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
        cg.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: cg.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        cg.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        super.scrollWheel(with: NSEvent(cgEvent: cg) ?? event)
    }
}

/// The card row: lays out square cards in a line and keeps views only for the visible ones.
final class CardStripView: FlippedView, NSDraggingSource {
    weak var delegate: CardCollectionDelegate?
    var geometry = StripGeometry(style: .current, panelHeight: SPMetrics.Strip.defaultHeight)
    /// Where the first card starts (after the sidecar when it shows).
    var leading: CGFloat = SPMetrics.Cards.contentInsets.left

    private var visible: [Int: CardView] = [:]
    private var pool: [CardView] = []
    private var count = 0

    /// Quick-paste numbers show while the quick-paste modifiers are held; the plain-text mark while those are.
    var showsQuickPasteNumbers = false { didSet { if showsQuickPasteNumbers != oldValue { updateBadges() } } }
    var showsPlainTextIndicator = false { didSet { if showsPlainTextIndicator != oldValue { updateBadges() } } }
    var isDimmed = false { didSet { if isDimmed != oldValue { updateSelection() } } }

    private let reorderMarker = FillView()
    private var lastSelectionMove = Date.distantPast

    static let reorderTypes: [NSPasteboard.PasteboardType] = [.string, .URL, .fileURL, .tiff, .png, .rtf, .html,
                                                               .init(PasteboardType.itemID)]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        reorderMarker.fillColor = .keyboardFocusIndicatorColor
        reorderMarker.cornerRadius = SPMotion.reorderMarkerRadius
        reorderMarker.isHidden = true
        addSubview(reorderMarker)
        registerForDraggedTypes(Self.reorderTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    var scrollView: NSScrollView? { enclosingScrollView }
    var visibleIndices: [Int] { visible.keys.sorted() }

    func cardView(at index: Int) -> CardView? { visible[index] }

    // MARK: Data

    /// Rebuilds every visible card (new list, new search, size change).
    func reloadData() {
        count = delegate?.cardCount ?? 0
        for (_, card) in visible { recycle(card) }
        visible.removeAll()
        updateFrameSize()
        tile()
    }

    /// Re-configures the visible cards in place (item edits, pins, renames) after the count stayed the same.
    func refreshVisibleCards() {
        count = delegate?.cardCount ?? 0
        updateFrameSize()
        guard let delegate else { return }
        let context = delegate.cardContext()
        for (index, card) in visible {
            guard index < count, let item = delegate.item(at: index) else { continue }
            card.configure(item, context: context)
        }
        tile()
    }

    func refreshDates(now: Date) {
        visible.values.forEach { $0.refreshDate(now: now) }
    }

    private func updateFrameSize() {
        let height = scrollView?.contentView.bounds.height ?? geometry.collectionHeight
        let width = max(geometry.contentWidth(count: count, leading: leading), scrollView?.contentView.bounds.width ?? 0)
        if frame.size != NSSize(width: width, height: height) { setFrameSize(NSSize(width: width, height: height)) }
    }

    /// Lays out views for the cards in (and one card around) the visible rect.
    func tile() {
        guard let delegate, let clip = scrollView?.contentView else { return }
        let rect = clip.bounds
        let pitch = geometry.cardSide + SPMetrics.Cards.spacing
        let range = geometry.indices(from: rect.minX - pitch, to: rect.maxX + pitch, count: count, leading: leading)
        for (index, card) in visible where !range.contains(index) {
            recycle(card)
            visible[index] = nil
        }
        let context = delegate.cardContext()
        for index in range where visible[index] == nil {
            guard let item = delegate.item(at: index) else { continue }
            let card = pool.popLast() ?? CardView(frame: .zero)
            card.frame = geometry.cardFrame(at: index, leading: leading)
            card.configure(item, context: context)
            addSubview(card, positioned: .below, relativeTo: reorderMarker)
            visible[index] = card
        }
        for (index, card) in visible {
            let frame = geometry.cardFrame(at: index, leading: leading)
            if card.frame != frame { card.frame = frame }
        }
        updateSelection()
        updateBadges()
        if let last = range.last { delegate.cardsVisible(through: last) }
    }

    private func recycle(_ card: CardView) {
        card.removeFromSuperview()
        card.isSelected = false
        if pool.count < 12 { pool.append(card) }
    }

    func updateSelection() {
        guard let delegate else { return }
        for (index, card) in visible {
            card.isSelected = delegate.isCardSelected(index)
            card.isDimmed = isDimmed
        }
    }

    /// The first nine visible cards get 1…9 (ui-reference §4.4).
    var firstVisibleIndex: Int? {
        geometry.firstVisibleIndex(scrollX: scrollView?.contentView.bounds.minX ?? 0, count: count, leading: leading)
    }

    private func updateBadges() {
        let first = firstVisibleIndex
        for (index, card) in visible {
            let n = first.map { index - $0 + 1 }
            card.quickPasteNumber = n.flatMap { (1...SPMetrics.Cards.quickPasteCount).contains($0) ? $0 : nil }
            card.showsQuickPasteNumber = showsQuickPasteNumbers
            card.showsPlainTextIndicator = showsPlainTextIndicator && (delegate?.isCardSelected(index) ?? false)
        }
    }

    // MARK: Scrolling

    /// Brings a card into view. Keyboard moves animate for the time since the previous move (≤ 0.25 s, instant under
    /// 0.1 s) on the standard curve (ui-reference §4.7).
    func scrollToReveal(_ index: Int, animated: Bool = true) {
        guard let scrollView, index >= 0, index < count else { return }
        let clip = scrollView.contentView
        guard let x = geometry.scrollX(revealing: index, current: clip.bounds.minX, viewportWidth: clip.bounds.width,
                                       count: count, leading: leading) else { return }
        let now = Date()
        let duration = min(now.timeIntervalSince(lastSelectionMove), SPMotion.scrollToSelectionMax)
        lastSelectionMove = now
        let origin = NSPoint(x: x, y: clip.bounds.minY)
        if !animated || duration < SPMotion.scrollToSelectionInstantBelow {
            clip.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clip)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = SPMotion.standardTiming
                clip.animator().setBoundsOrigin(origin)
            }
        }
    }

    func scrollToStart() {
        guard let clip = scrollView?.contentView else { return }
        clip.setBoundsOrigin(NSPoint(x: 0, y: clip.bounds.minY))
        scrollView?.reflectScrolledClipView(clip)
    }

    var cardsPerPage: Int { geometry.cardsPerPage(viewportWidth: scrollView?.contentView.bounds.width ?? bounds.width) }

    // MARK: Mouse

    private var pressIndex: Int?
    private var pressPoint: NSPoint = .zero
    private var pressTime = Date()
    private var pressWasSelected = false
    private var pressDeferredSingle = false
    private var dragStarted = false

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let index = geometry.index(at: point.x, count: count, leading: leading),
              geometry.cardFrame(at: index, leading: leading).contains(point) else {
            pressIndex = nil
            delegate?.emptyAreaClicked()
            return
        }
        pressIndex = index
        pressPoint = point
        pressTime = Date()
        dragStarted = false
        pressWasSelected = delegate?.isCardSelected(index) ?? false
        let mode: SelectionMode
        switch StripMouseMap.action(clickCount: event.clickCount, modifiers: event.modifierFlags, bindings: .current) {
        case .paste(let plainText):
            // The first click of the pair already selected the card; no drag can start from a double click.
            pressIndex = nil
            delegate?.cardDoubleClicked(index, plainText: plainText)
            return
        case .select(let selectionMode):
            mode = selectionMode
        }
        // Clicking a card that is part of a multi-selection keeps the selection until mouse-up, so it can be dragged.
        pressDeferredSingle = mode == .single && pressWasSelected
        if !pressDeferredSingle { delegate?.cardClicked(index, mode: mode) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = pressIndex, !dragStarted, let delegate else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - pressPoint.x, point.y - pressPoint.y) >= SPMotion.dragThreshold else { return }
        if pressWasSelected, Date().timeIntervalSince(pressTime) < SPMotion.dragDelay { return }
        dragStarted = true
        startDrag(items: delegate.dragItems(startingAt: index), from: index, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        if let index = pressIndex, pressDeferredSingle, !dragStarted {
            delegate?.cardClicked(index, mode: .single)
        }
        pressIndex = nil
        pressDeferredSingle = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = geometry.index(at: point.x, count: count, leading: leading),
              geometry.cardFrame(at: index, leading: leading).contains(point) else { return nil }
        if !(delegate?.isCardSelected(index) ?? false) { delegate?.cardClicked(index, mode: .single) }
        return delegate?.contextMenu(forCardAt: index)
    }

    override func keyDown(with event: NSEvent) {
        if delegate?.handleKey(event) != true { super.keyDown(with: event) }
    }

    // MARK: Drag out (CollectionView+Dragging)

    private(set) var draggedIDs: [UUID] = []

    private func startDrag(items: [ClipItem], from index: Int, event: NSEvent) {
        guard !items.isEmpty else { return }
        draggedIDs = items.map(\.id)
        let writers = Services.pasting?.pasteboardWriters(for: items, plainText: false) ?? []
        let fallback: [NSPasteboardWriting] = items.map { item in
            let pbItem = NSPasteboardItem()
            pbItem.setString(ItemPresentation.summary(item), forType: .string)
            return pbItem
        }
        let origin = geometry.cardFrame(at: index, leading: leading)
        let image = visible[index].map(dragImage(of:))
        let draggingItems = (writers.isEmpty ? fallback : writers).enumerated().map { offset, writer in
            let item = NSDraggingItem(pasteboardWriter: writer)
            let frame = origin.offsetBy(dx: CGFloat(offset) * 6, dy: CGFloat(offset) * 6)
            item.setDraggingFrame(frame, contents: offset == 0 ? image : nil)
            return item
        }
        let session = beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .stack
        delegate?.dragSessionChanged(active: true)
    }

    private func dragImage(of card: CardView) -> NSImage {
        let snapshot = card.snapshot()
        let image = NSImage(size: snapshot.size, flipped: false) { rect in
            snapshot.draw(in: rect, from: .zero, operation: .sourceOver, fraction: SPMotion.dragImageAlpha)
            return true
        }
        return image
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy, .generic] : .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        draggedIDs = []
        reorderMarker.isHidden = true
        delegate?.dragSessionChanged(active: false)
    }

    // MARK: Reorder inside a pinboard

    private func ownDrag(_ info: NSDraggingInfo) -> Bool {
        (info.draggingSource as? CardStripView) === self && delegate?.canReorderCards == true && !draggedIDs.isEmpty
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard ownDrag(sender) else { return [] }
        let point = convert(sender.draggingLocation, from: nil)
        autoScroll(near: point)
        let index = geometry.insertionIndex(at: point.x, count: count, leading: leading)
        let side = geometry.cardSide
        let x = index < count ? geometry.gapCenterX(before: index, leading: leading)
                              : geometry.cardFrame(at: count - 1, leading: leading).maxX + SPMetrics.Cards.spacing / 2
        reorderMarker.frame = NSRect(x: round(x - SPMotion.reorderMarkerWidth / 2), y: SPMetrics.Cards.contentInsets.top,
                                     width: SPMotion.reorderMarkerWidth, height: side)
        reorderMarker.isHidden = false
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        reorderMarker.isHidden = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        reorderMarker.isHidden = true
        guard ownDrag(sender) else { return false }
        let point = convert(sender.draggingLocation, from: nil)
        delegate?.moveCards(draggedIDs, toIndex: geometry.insertionIndex(at: point.x, count: count, leading: leading))
        return true
    }

    /// Within 30 pt of an edge, scrolls (30 − d) / 30 × 15 pt per update (ui-reference §4.7).
    private func autoScroll(near point: NSPoint) {
        guard let scrollView else { return }
        let clip = scrollView.contentView
        let visibleRect = clip.bounds
        let edge = SPMotion.autoScrollEdge
        var dx: CGFloat = 0
        let fromLeft = point.x - visibleRect.minX, fromRight = visibleRect.maxX - point.x
        if fromLeft < edge { dx = -(edge - max(0, fromLeft)) / edge * SPMotion.autoScrollStep }
        else if fromRight < edge { dx = (edge - max(0, fromRight)) / edge * SPMotion.autoScrollStep }
        guard dx != 0 else { return }
        let maxX = max(0, bounds.width - visibleRect.width)
        clip.setBoundsOrigin(NSPoint(x: min(max(0, visibleRect.minX + dx), maxX), y: visibleRect.minY))
        scrollView.reflectScrolledClipView(clip)
    }
}
