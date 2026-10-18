import AppKit
import SuperPasteCore

/// What every card in a strip shares when it is configured.
struct CardContext {
    var style: SPStyle
    var side: CGFloat
    var sizeClass: CardSizeClass
    var scope: ListScope
    var pinboards: [Pinboard]
    var now: Date
    var linkPreviewsEnabled: Bool
    var fileThumbnailsEnabled: Bool

    var metrics: SPMetrics { SPMetrics(style: style) }
}

/// One card (`BaseCell` + `ItemCell`, ui-reference §4.1–§4.5): a rounded body with a coloured header, the content for
/// the item's kind, the quick-paste badge, and the 4 pt accent selection ring outside the body.
final class CardView: FlippedView {
    private(set) var item: ClipItem?
    private var context: CardContext?

    private let ring = FillView()
    private let plate = FillView()
    private let body = FillView()
    private let gradient = GradientView()
    let header = CardHeaderView()
    private var content: CardContentView?
    private let badge = QuickPasteBadge()
    private let sizePill = PillLabel()

    var isSelected = false { didSet { if isSelected != oldValue { updateRing() } } }
    var isDimmed = false { didSet { if isDimmed != oldValue { updateRing() } } }
    /// 1…9 while the card is among the first nine visible ones.
    var quickPasteNumber: Int? { didSet { updateBadge() } }
    var showsQuickPasteNumber = false { didSet { updateBadge() } }
    var showsPlainTextIndicator = false { didSet { updateBadge() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        ring.isHidden = true
        ring.borderWidth = SPMetrics.Cards.selectionRingInset
        body.clips = true
        gradient.colors = [NSColor.black.withAlphaComponent(0.4), .clear]
        addSubview(ring)
        addSubview(plate)
        addSubview(body)
        body.addSubview(gradient)
        body.addSubview(header)
        body.addSubview(sizePill)
        body.addSubview(badge)
        sizePill.isHidden = true
        badge.isHidden = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ item: ClipItem, context: CardContext) {
        let previousKind = self.item?.kind
        self.item = item
        self.context = context
        let metrics = context.metrics

        let radius = metrics.cardCornerRadius
        plate.cornerRadius = radius
        plate.cornerCurve = metrics.cardCornerCurve
        plate.fillColor = SPColor.cardBody
        let shadowSpec = metrics.cardShadow
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(shadowSpec.alpha)
        shadow.shadowOffset = shadowSpec.offset
        shadow.shadowBlurRadius = shadowSpec.blur
        plate.shadow = shadow
        body.cornerRadius = radius
        body.cornerCurve = metrics.cardCornerCurve
        body.fillColor = item.kind == .color ? ItemPresentation.colorHex(item).map { NSColor(hex: $0) } : SPColor.cardBody
        ring.cornerRadius = metrics.selectionRingRadius
        ring.cornerCurve = metrics.cardCornerCurve

        if content == nil || previousKind != item.kind || type(of: content!) != CardContentView.type(for: item.kind) {
            content?.removeFromSuperview()
            let view = CardContentView.type(for: item.kind).init(frame: .zero)
            body.addSubview(view, positioned: .below, relativeTo: gradient)
            content = view
        }

        let fullSize = context.sizeClass == .compact && ItemPresentation.isCompactContentFullSize(item)
        let compactStyle: CompactHeaderStyle = fullSize ? .gradient : .transparent
        let pinboard = AppIconProvider.shared.pinboard(for: item, scope: context.scope, pinboards: context.pinboards)
        let layout = CardHeaderLayout(sizeClass: context.sizeClass, metrics: metrics, compactStyle: compactStyle,
                                      appIconHidden: pinboard != nil)
        header.configure(item: item, layout: layout, context: context, pinboard: pinboard)
        // A compact header sits on the colour itself: its ink follows the colour's brightness.
        header.appearance = item.kind == .color && layout.isCompact ? body.fillColor?.readableAppearance : nil
        gradient.alphaValue = layout.gradientAlpha
        content?.contentTopInset = fullSize ? 0 : layout.height
        content?.configure(item, context: context)

        if item.kind == .image, let size = item.imageSize {
            sizePill.text = "\(size.width) × \(size.height)"
            sizePill.isHidden = false
        } else {
            sizePill.isHidden = true
        }
        updateRing()
        updateBadge()
        needsLayout = true
    }

    /// Refreshes the relative date (every 30 s).
    func refreshDate(now: Date) {
        guard let item, var context else { return }
        context.now = now
        self.context = context
        header.refreshDate(ItemPresentation.date(item), now: now)
    }

    override func layout() {
        super.layout()
        let inset = SPMetrics.Cards.selectionRingInset
        ring.frame = bounds.insetBy(dx: -inset, dy: -inset)
        plate.frame = bounds
        body.frame = bounds
        let headerHeight = header.layoutInfo?.height ?? 0
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        gradient.frame = NSRect(x: 0, y: 0, width: bounds.width, height: SPMetrics.Cards.headerGradientHeight)
        if let content {
            let top = content.contentTopInset
            content.frame = NSRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        }
        let pad = SPMetrics.Cards.badgeInset
        let badgeSize = badge.fittingSize
        badge.frame = NSRect(x: bounds.width - pad - badgeSize.width, y: bounds.height - pad - badgeSize.height,
                             width: badgeSize.width, height: badgeSize.height)
        let pillSize = sizePill.fittingSize
        sizePill.frame = NSRect(x: round((bounds.width - pillSize.width) / 2), y: bounds.height - pad - pillSize.height,
                                width: pillSize.width, height: pillSize.height)
    }

    private func updateRing() {
        ring.isHidden = !isSelected
        let accent = SPColor.accent
        ring.borderColor = isDimmed ? (accent.usingColorSpace(.genericGray) ?? .gray) : accent
    }

    private func updateBadge() {
        badge.number = showsQuickPasteNumber ? quickPasteNumber : nil
        badge.showsPlainText = showsPlainTextIndicator
        badge.isHidden = badge.number == nil && !badge.showsPlainText
        needsLayout = true
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilitySelected() -> Bool { isSelected }

    override func accessibilityLabel() -> String? {
        guard let item else { return nil }
        return "\(ItemPresentation.headerTitle(item)), \(ItemPresentation.summary(item))"
    }

    // MARK: Rename (⌘R)

    /// Edits the title in place; `onEnd` gets the new title (nil clears it) and whether it was committed.
    func beginRename(onEnd: @escaping (_ title: String?, _ committed: Bool) -> Void) {
        header.beginEditingTitle(onEnd: onEnd)
    }
}

// MARK: - Header

/// `ItemCell.HeaderView`: the coloured band with title and relative date, the big app icon bleeding off the right,
/// or (compact) a slim row over the card.
final class CardHeaderView: FlippedView, NSTextFieldDelegate {
    private let band = FillView()
    private let appIcon = NSImageView()
    private let pinboardIcon = NSImageView()
    private let titleLabel = Labels.make(font: .systemFont(ofSize: 13), color: .white)
    private let dateLabel = Labels.make(font: .systemFont(ofSize: 12), color: .white)
    private var editor: NSTextField?
    private var onEnd: ((String?, Bool) -> Void)?
    private(set) var layoutInfo: CardHeaderLayout?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        pinboardIcon.imageScaling = .scaleProportionallyUpOrDown
        [band, appIcon, pinboardIcon, titleLabel, dateLabel].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(item: ClipItem, layout: CardHeaderLayout, context: CardContext, pinboard: Pinboard?) {
        layoutInfo = layout
        band.fillColor = AppIconProvider.shared.headerColor(for: item, scope: context.scope, pinboards: context.pinboards,
                                                             style: context.style)
        band.alphaValue = layout.bandAlpha
        appIcon.image = AppIconProvider.shared.icon(for: item.sourceApp)
        appIcon.alphaValue = layout.appIconAlpha
        if let pinboard {
            pinboardIcon.image = Symbols.dot(SPColor.pinboard(pinboard.color, style: context.style),
                                             side: SPMetrics.Cards.pinboardIconSize)
            pinboardIcon.isHidden = false
        } else {
            pinboardIcon.isHidden = true
        }
        titleLabel.stringValue = ItemPresentation.headerTitle(item)
        titleLabel.font = layout.titleFont
        titleLabel.textColor = layout.titleColor
        dateLabel.font = layout.dateFont
        dateLabel.textColor = layout.dateColor
        let date = ItemPresentation.date(item)
        dateLabel.isHidden = !ItemPresentation.showsDate(item)
        dateLabel.stringValue = CardDateText.text(for: date, now: context.now, compact: layout.isCompact)
        toolTip = dateLabel.isHidden ? nil : CardDateText.tooltip(for: date)
        needsLayout = true
    }

    func refreshDate(_ date: Date, now: Date) {
        guard let layoutInfo else { return }
        dateLabel.stringValue = CardDateText.text(for: date, now: now, compact: layoutInfo.isCompact)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let l = layoutInfo else { return }
        band.frame = bounds
        let midY = bounds.midY
        let iconSide = l.appIconHeight
        appIcon.frame = NSRect(x: bounds.maxX + l.appIconTrailing - iconSide, y: round(midY - iconSide / 2),
                               width: iconSide, height: iconSide)
        let dot = SPMetrics.Cards.pinboardIconSize
        pinboardIcon.frame = NSRect(x: bounds.maxX + l.pinboardIconTrailing - dot, y: round(midY - dot / 2), width: dot, height: dot)

        let labelsMaxX = bounds.maxX + l.labelsTrailing
        let titleSize = titleLabel.labelSize
        let dateSize = dateLabel.isHidden ? .zero : dateLabel.labelSize
        let available = max(0, labelsMaxX - l.labelsLeading)
        if dateLabel.isHidden {
            titleLabel.frame = NSRect(x: l.labelsLeading, y: round(midY - titleSize.height / 2),
                                      width: min(titleSize.width, available), height: titleSize.height)
        } else if l.labelsVertical {
            let total = titleSize.height + l.labelsSpacing + dateSize.height
            let top = round(midY - total / 2)
            titleLabel.frame = NSRect(x: l.labelsLeading, y: top, width: min(titleSize.width, available), height: titleSize.height)
            dateLabel.frame = NSRect(x: l.labelsLeading, y: top + titleSize.height + l.labelsSpacing,
                                     width: min(dateSize.width, available), height: dateSize.height)
        } else {
            let dateWidth = min(dateSize.width, available)
            let titleWidth = min(titleSize.width, max(0, available - dateWidth - l.labelsSpacing))
            titleLabel.frame = NSRect(x: l.labelsLeading, y: round(midY - titleSize.height / 2), width: titleWidth,
                                      height: titleSize.height)
            dateLabel.frame = NSRect(x: titleLabel.frame.maxX + l.labelsSpacing, y: round(midY - dateSize.height / 2),
                                     width: dateWidth, height: dateSize.height)
        }
        if let editor {
            let height = editor.intrinsicContentSize.height
            editor.frame = NSRect(x: l.labelsLeading, y: l.labelsVertical ? titleLabel.frame.minY : round(midY - height / 2),
                                  width: available, height: height)
        }
    }

    // MARK: Inline title editing (`HeaderView.TitleLabel`)

    func beginEditingTitle(onEnd: @escaping (String?, Bool) -> Void) {
        guard editor == nil, let l = layoutInfo else { return }
        let field = NSTextField(string: titleLabel.stringValue)
        field.font = l.titleFont
        field.textColor = l.titleColor
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .exterior
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        titleLabel.isHidden = true
        addSubview(field)
        editor = field
        self.onEnd = onEnd
        layout()
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            finishEditing(commit: true); return true
        case #selector(NSResponder.cancelOperation(_:)):
            finishEditing(commit: false); return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        finishEditing(commit: true)
    }

    private func finishEditing(commit: Bool) {
        guard let field = editor else { return }
        editor = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        titleLabel.isHidden = false
        let handler = onEnd
        onEnd = nil
        handler?(text.isEmpty ? nil : text, commit)
    }
}

// MARK: - Badges

/// A frosted capsule label: the image size pill (ui-reference §4.5). It is always dark with light text, whatever
/// the picture or the appearance, so it reads on any image.
final class PillLabel: FlippedView {
    private let backdrop = BackdropView(frame: .zero)
    private let label = Labels.make(font: SPFont.style(.callout), color: SPColor.ink85)

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue; needsLayout = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        appearance = NSAppearance(named: .darkAqua)
        backdrop.cornerRadius = SPMetrics.Cards.badgeCornerRadius
        addSubview(backdrop)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var fittingSize: NSSize {
        let size = label.labelSize
        return NSSize(width: ceil(size.width) + 2 * SPMetrics.Cards.badgePadding, height: SPMetrics.Cards.badgeHeight)
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        let size = label.labelSize
        label.frame = NSRect(x: SPMetrics.Cards.badgePadding, y: round((bounds.height - size.height) / 2),
                             width: bounds.width - 2 * SPMetrics.Cards.badgePadding, height: size.height)
    }
}

/// `ItemCell.ShortcutIndicatorView` (ui-reference §4.4): the quick-paste number while its modifiers are held, and the
/// plain-text indicator while the plain-text modifiers are held.
final class QuickPasteBadge: FlippedView {
    private let backdrop = BackdropView(frame: .zero)
    private let plainText = NSImageView()
    private let numberLabel = Labels.make(font: SPFont.style(.callout), color: SPColor.ink50)

    var number: Int? { didSet { numberLabel.stringValue = number.map(String.init) ?? ""; needsLayout = true } }
    var showsPlainText = false { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        backdrop.cornerRadius = SPMetrics.Cards.badgeCornerRadius
        plainText.image = Symbols.image("text.alignleft", config: .init(textStyle: .footnote))
        plainText.contentTintColor = NSColor.secondaryLabelColor.withAlphaComponent(0.65)
        addSubview(backdrop)
        addSubview(plainText)
        addSubview(numberLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var parts: [NSView] {
        (showsPlainText ? [plainText as NSView] : []) + (number != nil ? [numberLabel] : [])
    }

    override var fittingSize: NSSize {
        let widths = parts.map { ceil($0.contentFittingSize.width) }
        let content = widths.reduce(0, +) + CGFloat(max(0, widths.count - 1)) * SPMetrics.Cards.badgeSpacing
        return NSSize(width: max(SPMetrics.Cards.badgeHeight, content + 2 * SPMetrics.Cards.badgePadding),
                      height: SPMetrics.Cards.badgeHeight)
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        plainText.isHidden = !showsPlainText
        numberLabel.isHidden = number == nil
        let content = fittingSize.width - 2 * SPMetrics.Cards.badgePadding
        var x = round((bounds.width - content) / 2)
        for view in parts {
            let size = view.contentFittingSize
            view.frame = NSRect(x: x, y: round((bounds.height - size.height) / 2), width: ceil(size.width), height: size.height)
            x += ceil(size.width) + SPMetrics.Cards.badgeSpacing
        }
    }
}
