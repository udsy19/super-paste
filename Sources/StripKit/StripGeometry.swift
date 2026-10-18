import AppKit
import SuperPasteCore

/// Layout math for the strip and its cards (ui-reference §2.5, §2.6, §4.2). Pure, so it is unit-tested.
///
/// The card row lives in a flipped document view: x grows to the right from the collection's leading edge, y grows
/// down from the collection's top.
struct StripGeometry: Equatable {
    let style: SPStyle
    /// The panel height, clamped to 252…412.
    let panelHeight: CGFloat

    init(style: SPStyle, panelHeight: CGFloat) {
        self.style = style
        self.panelHeight = SPMetrics.Strip.clampedHeight(panelHeight)
    }

    var metrics: SPMetrics { SPMetrics(style: style) }
    var collectionHeight: CGFloat { metrics.collectionHeight(panelHeight: panelHeight) }
    var cardSide: CGFloat { metrics.cardSide(panelHeight: panelHeight) }
    var sizeClass: CardSizeClass { CardSizeClass(cardSide: cardSide) }

    private var insets: NSEdgeInsets { SPMetrics.Cards.contentInsets }
    private var spacing: CGFloat { SPMetrics.Cards.spacing }
    private var pitch: CGFloat { cardSide + spacing }

    /// Where the first card starts: the left content inset, or after the sidecar column (§2.6, §5).
    func leading(sidecarWidth: CGFloat) -> CGFloat {
        sidecarWidth > 0 ? insets.left + sidecarWidth + spacing : insets.left
    }

    func cardFrame(at index: Int, leading: CGFloat) -> CGRect {
        CGRect(x: leading + CGFloat(index) * pitch, y: insets.top, width: cardSide, height: cardSide)
    }

    func contentWidth(count: Int, leading: CGFloat) -> CGFloat {
        guard count > 0 else { return leading + insets.right }
        return cardFrame(at: count - 1, leading: leading).maxX + insets.right
    }

    /// Indices whose cards intersect `minX..<maxX`.
    func indices(from minX: CGFloat, to maxX: CGFloat, count: Int, leading: CGFloat) -> Range<Int> {
        guard count > 0, maxX > minX else { return 0..<0 }
        let first = max(0, Int(floor((minX - leading + spacing) / pitch)))
        let last = min(count - 1, Int(floor((maxX - leading) / pitch)))
        return first <= last ? first..<(last + 1) : 0..<0
    }

    /// The card under `x`, or nil in a gap or past the ends.
    func index(at x: CGFloat, count: Int, leading: CGFloat) -> Int? {
        guard x >= leading else { return nil }
        let i = Int(floor((x - leading) / pitch))
        guard i < count, x <= cardFrame(at: i, leading: leading).maxX else { return nil }
        return i
    }

    /// The first card at least half visible: Quick Paste numbers start there (§4.4 "first nine visible").
    func firstVisibleIndex(scrollX: CGFloat, count: Int, leading: CGFloat) -> Int? {
        guard count > 0 else { return nil }
        let i = max(0, Int(ceil((scrollX - leading - cardSide / 2) / pitch)))
        return i < count ? i : nil
    }

    /// The scroll offset that brings a card fully into view with the content inset around it, or nil when it
    /// already is.
    func scrollX(revealing index: Int, current: CGFloat, viewportWidth: CGFloat, count: Int, leading: CGFloat) -> CGFloat? {
        let frame = cardFrame(at: index, leading: leading)
        let maxScroll = max(0, contentWidth(count: count, leading: leading) - viewportWidth)
        var target = current
        if frame.minX - insets.left < current {
            target = index == 0 ? 0 : frame.minX - insets.left
        } else if frame.maxX + insets.right > current + viewportWidth {
            target = frame.maxX + insets.right - viewportWidth
        }
        target = min(max(0, target), maxScroll)
        return target == current ? nil : target
    }

    /// How many whole cards fit in the viewport (PageUp / PageDown step).
    func cardsPerPage(viewportWidth: CGFloat) -> Int {
        max(1, Int(floor((viewportWidth - insets.left - insets.right + spacing) / pitch)))
    }

    /// Where a dragged card would land: the gap nearest to `x` (0 … count).
    func insertionIndex(at x: CGFloat, count: Int, leading: CGFloat) -> Int {
        let raw = (x - leading + spacing / 2) / pitch
        return min(max(0, Int(raw.rounded(.toNearestOrAwayFromZero))), count)
    }

    /// The centre of the gap before `index` (the reorder marker sits there).
    func gapCenterX(before index: Int, leading: CGFloat) -> CGFloat {
        cardFrame(at: index, leading: leading).minX - spacing / 2
    }
}

// MARK: - Card header

/// The compact header look: no band; white text over a dark gradient on full-size media, ink on the card otherwise.
enum CompactHeaderStyle: Equatable {
    case transparent, gradient
}

/// `ItemCell.HeaderView.Layout` (ui-reference §4.2): fonts, colours and offsets per size class.
struct CardHeaderLayout {
    let sizeClass: CardSizeClass
    let height: CGFloat
    var isCompact: Bool { sizeClass == .compact }
    let titleFont: NSFont
    let titleColor: NSColor
    let dateFont: NSFont
    let dateColor: NSColor
    /// Vertical title-over-date in the larger classes, side by side in compact.
    var labelsVertical: Bool { !isCompact }
    var labelsSpacing: CGFloat { isCompact ? 0 : -1 }
    let labelsLeading: CGFloat = SPMetrics.Cards.headerLabelsInset
    /// The labels' trailing edge, from the header's trailing edge.
    let labelsTrailing: CGFloat
    let appIconHeight: CGFloat
    /// The app icon's trailing edge, from the header's trailing edge (+14 overhangs and is clipped).
    let appIconTrailing: CGFloat
    let appIconAlpha: CGFloat
    /// The pinboard icon's trailing edge, from the header's trailing edge (+8 puts it out of sight: the band shows
    /// the pinboard there).
    let pinboardIconTrailing: CGFloat
    let bandAlpha: CGFloat
    let gradientAlpha: CGFloat

    init(sizeClass: CardSizeClass, metrics: SPMetrics, compactStyle: CompactHeaderStyle, appIconHidden: Bool) {
        self.sizeClass = sizeClass
        height = metrics.headerHeight(sizeClass)
        appIconHeight = sizeClass.appIconHeight
        if sizeClass == .compact {
            titleFont = SPFont.style(.headline, weight: .semibold)
            dateFont = SPFont.style(.body)
            switch compactStyle {
            case .gradient:
                titleColor = .white.withAlphaComponent(0.85)
                dateColor = .white.withAlphaComponent(0.55)
                gradientAlpha = 1
            case .transparent:
                titleColor = SPColor.ink85
                dateColor = SPColor.ink50
                gradientAlpha = 0
            }
            labelsTrailing = sizeClass.labelsXOffset
            appIconTrailing = -8
            appIconAlpha = appIconHidden ? 0 : 0.9
            pinboardIconTrailing = -12
            bandAlpha = 0
        } else {
            titleFont = SPFont.style(.title3, weight: .medium)
            titleColor = .white
            dateFont = SPFont.style(.callout)
            dateColor = .white.withAlphaComponent(0.8)
            labelsTrailing = appIconHidden ? -SPMetrics.Cards.headerLabelsInset : sizeClass.labelsXOffset
            appIconTrailing = 14
            appIconAlpha = appIconHidden ? 0 : 1
            pinboardIconTrailing = 8
            bandAlpha = 1
            gradientAlpha = 0
        }
    }
}
