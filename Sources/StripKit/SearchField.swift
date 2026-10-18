import AppKit
import SuperPasteCore

@MainActor
protocol SearchFieldDelegate: AnyObject {
    func searchQueryChanged(_ query: SearchQuery)
    /// The field opened (focused or holding a query) or closed.
    func searchActiveChanged(_ active: Bool)
    /// Keys the field doesn't handle itself (Return, Tab, quick paste, …): true when the strip handled it.
    func searchForwardKey(_ event: NSEvent) -> Bool
    /// Esc with nothing left to clear in the field.
    func searchCancelled()
    func searchShowFilters()
    var filterSources: FilterSources { get }
}

/// The search bar (ui-reference §3.3): a magnifier at +8, a 20 pt text input with inline filter tokens, a 16 pt clear
/// button and the filters button. Inactive and empty it collapses to its magnifier.
final class SearchFieldView: FillView, NSTextViewDelegate {
    weak var delegate: SearchFieldDelegate?
    var style: SPStyle = .current { didSet { updateLook() } }

    private let magnifier = NSImageView()
    private let scroll = NSScrollView()
    let textView = SearchTextView(frame: .zero)
    private let clearButton = NSButton()
    private let filtersButton = NSButton()
    private let suggestions = SuggestionsWindowController()
    private var suppressChange = false

    private(set) var query = SearchQuery.empty
    /// Open: focused or holding a query.
    private(set) var isActive = false {
        didSet { if isActive != oldValue { updateLook(); delegate?.searchActiveChanged(isActive) } }
    }

    static let height: CGFloat = 28

    override init(frame: NSRect) {
        super.init(frame: frame)
        magnifier.imageScaling = .scaleNone

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        scroll.documentView = textView
        textView.field = self
        textView.delegate = self

        clearButton.isBordered = false
        clearButton.image = Symbols.image("xmark.circle.fill", config: .init(pointSize: 13, weight: .regular))
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        clearButton.isHidden = true

        filtersButton.isBordered = false
        filtersButton.image = Symbols.image("line.3.horizontal.decrease", config: .init(textStyle: .body))
        filtersButton.toolTip = L10n.filtersTooltip
        filtersButton.target = self
        filtersButton.action = #selector(filtersClicked)

        suggestions.onAccept = { [weak self] suggestion in self?.accept(suggestion) }
        [magnifier, scroll, clearButton, filtersButton].forEach(addSubview)
        updateLook()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The collapsed width: just the magnifier.
    var collapsedWidth: CGFloat { SPMetrics.Toolbar.largeButtonSize }

    private func updateLook() {
        let metrics = SPMetrics(style: style)
        fillColor = isActive ? SPColor.ink10 : nil
        cornerRadius = metrics.searchFieldRadius(height: Self.height)
        cornerCurve = .circular
        magnifier.image = Symbols.image("magnifyingglass", config: .init(textStyle: style == .glass ? .body : .title2))
        magnifier.contentTintColor = style == .glass ? SPColor.ink85 : SPColor.ink50
        filtersButton.contentTintColor = style == .glass ? SPColor.ink85 : SPColor.ink50
        scroll.isHidden = !isActive
        filtersButton.isHidden = !isActive
        clearButton.isHidden = !isActive || query.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let t = SPMetrics.Toolbar.self
        let iconSize = magnifier.image?.size ?? NSSize(width: 16, height: 16)
        if !isActive {
            magnifier.frame = NSRect(x: round((bounds.width - iconSize.width) / 2), y: round((bounds.height - iconSize.height) / 2),
                                     width: iconSize.width, height: iconSize.height)
            return
        }
        magnifier.frame = NSRect(x: t.searchIconInset, y: round((bounds.height - iconSize.height) / 2),
                                 width: iconSize.width, height: iconSize.height)
        let filtersSize = filtersButton.image?.size ?? NSSize(width: 16, height: 16)
        filtersButton.frame = NSRect(x: bounds.width - t.searchIconInset - filtersSize.width,
                                     y: round((bounds.height - filtersSize.height) / 2), width: filtersSize.width,
                                     height: filtersSize.height)
        let clear = t.searchClearButtonSize
        let textX = magnifier.frame.maxX + 4
        let clearX = filtersButton.frame.minX - 4 - clear
        clearButton.frame = NSRect(x: clearX, y: round((bounds.height - clear) / 2), width: clear, height: clear)
        let textRight = clearButton.isHidden ? filtersButton.frame.minX - 4 : clearX - 4
        scroll.frame = NSRect(x: textX, y: round((bounds.height - t.searchTextHeight) / 2), width: max(0, textRight - textX),
                              height: t.searchTextHeight)
        textView.minSize = NSSize(width: scroll.frame.width, height: t.searchTextHeight)
        textView.frame.size.height = t.searchTextHeight
        if textView.frame.width < scroll.frame.width { textView.frame.size.width = scroll.frame.width }
    }

    // MARK: Activation

    /// Opens the field and focuses it (typing in the strip, a click on the magnifier, Tab).
    func activate() {
        isActive = true
        layoutSubtreeIfNeeded()
        window?.makeFirstResponder(textView)
    }

    fileprivate func focusChanged(_ focused: Bool) {
        if focused { isActive = true } else if query.isEmpty, !hasText { isActive = false; suggestions.close() }
        if !focused { suggestions.close() }
    }

    private var hasText: Bool { textView.textStorage?.length ?? 0 > 0 }

    override func mouseDown(with event: NSEvent) {
        if !isActive { activate() } else { window?.makeFirstResponder(textView) }
    }

    /// Types `text` into the field, opening it (type-to-search).
    func insertTyped(_ text: String) {
        activate()
        textView.insertText(text, replacementRange: textView.selectedRange())
    }

    /// Replaces the whole query.
    func setQuery(_ query: SearchQuery) {
        suppressChange = true
        textView.setQuery(query, sources: delegate?.filterSources ?? FilterSources(), style: style)
        suppressChange = false
        self.query = query
        if !query.isEmpty { isActive = true }
        updateLook()
        delegate?.searchQueryChanged(query)
    }

    func clear() {
        setQuery(.empty)
        suggestions.close()
        if window?.firstResponder !== textView { isActive = false }
    }

    func toggleFilter(_ filter: SearchQuery.Filter) {
        let applied = query.filters.contains(filter)
        var next = applied ? query.removing(filter) : query.adding(filter)
        if !applied { next = SearchQuery(components: next.components) }
        setQuery(next)
        if !applied { textView.bounceLastToken() }
    }

    @objc private func clearClicked() {
        clear()
        window?.makeFirstResponder(textView)
        isActive = true
    }

    @objc private func filtersClicked() { delegate?.searchShowFilters() }

    var filtersAnchor: NSView { filtersButton.isHidden ? magnifier : filtersButton }

    // MARK: Text changes

    func textDidChange(_ notification: Notification) {
        guard !suppressChange else { return }
        textView.tokenizeTypedFilters(sources: delegate?.filterSources ?? FilterSources(), style: style)
        query = textView.query
        clearButton.isHidden = query.isEmpty && !hasText
        needsLayout = true
        delegate?.searchQueryChanged(query)
        updateSuggestions()
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if window?.firstResponder === textView { updateSuggestions() }
    }

    private func updateSuggestions() {
        let sources = delegate?.filterSources ?? FilterSources()
        let items = sources.suggestions(for: textView.currentWord, excluding: query.filters)
        guard !items.isEmpty, let window else { suggestions.close(); return }
        suggestions.show(items, sources: sources, style: style, below: false,
                         anchor: window.convertToScreen(convert(bounds, to: nil)), parent: window)
    }

    private func accept(_ suggestion: FilterSuggestion) {
        textView.replaceCurrentWord(with: suggestion.filter, sources: delegate?.filterSources ?? FilterSources(), style: style)
        suggestions.close()
    }

    // MARK: Keys from the text view

    fileprivate func handle(command selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)) where suggestions.isVisible:
            suggestions.moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)) where suggestions.isVisible:
            suggestions.moveSelection(-1); return true
        case #selector(NSResponder.insertNewline(_:)) where suggestions.isVisible:
            if let s = suggestions.selected { accept(s) }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if suggestions.isVisible { suggestions.close() }
            else if hasText { clear(); window?.makeFirstResponder(textView); isActive = true }
            else { delegate?.searchCancelled() }
            return true
        default:
            return false
        }
    }

    fileprivate func forward(_ event: NSEvent) -> Bool { delegate?.searchForwardKey(event) ?? false }
}

// MARK: - Text view with tokens

/// `SearchField`: an `NSTextView` single-line input whose filters are `FilterTextAttachment` tokens.
final class SearchTextView: NSTextView {
    fileprivate weak var field: SearchFieldView?

    override init(frame: NSRect) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: CGFloat.greatestFiniteMagnitude, height: SPMetrics.Toolbar.searchTextHeight))
        container.widthTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        super.init(frame: frame, textContainer: container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isHorizontallyResizable = true
        isVerticallyResizable = false
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: SPMetrics.Toolbar.searchTextHeight)
        textContainerInset = NSSize(width: 0, height: 2)
        drawsBackground = false
        font = SPFont.style(.body)
        textColor = SPColor.ink85
        typingAttributes = [.font: SPFont.style(.body), .foregroundColor: SPColor.ink85]
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        focusRingType = .none
        setAccessibilityLabel(L10n.search)
        setAccessibilityPlaceholderValue(L10n.search)
    }

    override init(frame: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { field?.focusChanged(true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { field?.focusChanged(false) }
        return ok
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if (textStorage?.length ?? 0) == 0 {
            let attrs: [NSAttributedString.Key: Any] = [.font: SPFont.style(.body), .foregroundColor: NSColor.placeholderTextColor]
            (L10n.search as NSString).draw(at: NSPoint(x: textContainerOrigin.x, y: textContainerOrigin.y), withAttributes: attrs)
        }
    }

    override func keyDown(with event: NSEvent) {
        let key = KeyStroke(event: event)
        // Keys the strip owns even while typing: Quick Paste, Return (paste), Tab, the list shortcuts with no text.
        if StripKeyMap.quickPasteNumber(key) != nil, !key.modifiers.isEmpty, field?.forward(event) == true { return }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if field?.handle(command: selector) == true { return }
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)),
             #selector(NSResponder.insertBacktab(_:)), #selector(NSResponder.insertLineBreak(_:)):
            if let event = NSApp.currentEvent, field?.forward(event) == true { return }
            return
        default:
            super.doCommand(by: selector)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let key = KeyStroke(event: event)
        if StripKeyMap.quickPasteNumber(key) != nil, field?.forward(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: Query

    var query: SearchQuery {
        guard let storage = textStorage else { return .empty }
        var components: [SearchQuery.Component] = []
        var pending = ""
        let ns = storage.string as NSString
        var index = 0
        while index < storage.length {
            var range = NSRange()
            let attachment = storage.attribute(.attachment, at: index, effectiveRange: &range) as? FilterTokenAttachment
            if let attachment {
                components += SearchQuery(parsing: pending).components
                pending = ""
                components.append(.filter(attachment.filter))
            } else {
                pending += ns.substring(with: range)
            }
            index = NSMaxRange(range)
        }
        components += SearchQuery(parsing: pending).components
        return SearchQuery(components: components)
    }

    /// The word being typed: from the last space or token to the caret.
    var currentWord: String {
        guard let storage = textStorage else { return "" }
        let caret = selectedRange().location
        guard caret != NSNotFound, caret <= storage.length else { return "" }
        let range = currentWordRange(caret: caret)
        return (storage.string as NSString).substring(with: range)
    }

    private func currentWordRange(caret: Int) -> NSRange {
        let ns = (textStorage?.string ?? "") as NSString
        var start = caret
        var inQuotes = false
        // A quoted value (app:"Visual Studio") stays one word.
        for i in stride(from: caret - 1, through: 0, by: -1) {
            let ch = ns.character(at: i)
            if ch == 0x22 { inQuotes.toggle() }
            if !inQuotes, ch == 0x20 || ch == 0xFFFC { break }
            start = i
        }
        return NSRange(location: start, length: caret - start)
    }

    private func tokenString(_ filter: SearchQuery.Filter, sources: FilterSources, style: SPStyle) -> NSAttributedString {
        let attachment = FilterTokenAttachment(filter: filter, title: sources.title(for: filter),
                                               icon: sources.icon(for: filter, style: style, size: SPMetrics.Toolbar.filterTokenIconSize))
        let string = NSMutableAttributedString(attachment: attachment)
        string.addAttributes(typingAttributes, range: NSRange(location: 0, length: string.length))
        return string
    }

    func replaceCurrentWord(with filter: SearchQuery.Filter, sources: FilterSources, style: SPStyle) {
        let range = currentWordRange(caret: selectedRange().location)
        let token = tokenString(filter, sources: sources, style: style)
        guard shouldChangeText(in: range, replacementString: token.string) else { return }
        textStorage?.replaceCharacters(in: range, with: token)
        setSelectedRange(NSRange(location: range.location + token.length, length: 0))
        didChangeText()
        bounceLastToken()
    }

    /// `key:value` followed by a space becomes a token.
    func tokenizeTypedFilters(sources: FilterSources, style: SPStyle) {
        guard let storage = textStorage else { return }
        let caret = selectedRange().location
        guard caret > 0, caret <= storage.length, (storage.string as NSString).character(at: caret - 1) == 0x20 else { return }
        let wordRange = currentWordRange(caret: caret - 1)
        let word = (storage.string as NSString).substring(with: wordRange)
        let parsed = SearchQuery(parsing: word)
        guard parsed.components.count == 1, case .filter(let filter)? = parsed.components.first else { return }
        let token = tokenString(filter, sources: sources, style: style)
        let replaced = NSRange(location: wordRange.location, length: wordRange.length + 1)
        storage.replaceCharacters(in: replaced, with: token)
        setSelectedRange(NSRange(location: wordRange.location + token.length, length: 0))
        bounceLastToken()
    }

    func setQuery(_ query: SearchQuery, sources: FilterSources, style: SPStyle) {
        let result = NSMutableAttributedString()
        for component in query.components {
            switch component {
            case .filter(let filter):
                result.append(tokenString(filter, sources: sources, style: style))
            case .token:
                if result.length > 0, !(result.string.hasSuffix(" ")) { result.append(NSAttributedString(string: " ", attributes: typingAttributes)) }
                result.append(NSAttributedString(string: SearchQuery(components: [component]).text, attributes: typingAttributes))
            }
        }
        textStorage?.setAttributedString(result)
        setSelectedRange(NSRange(location: result.length, length: 0))
        undoManager?.removeAllActions(withTarget: self)
    }

    /// "filtersBounce": 1 → 1.16 → 0.98 → 1 over 0.28 s (ui-reference §3.3). Text attachments draw in the text view's
    /// layer, so the bounce plays on the whole field content.
    func bounceLastToken() {
        guard let layer = enclosingScrollView?.layer ?? layer else { return }
        let bounce = CAKeyframeAnimation(keyPath: "transform.scale")
        bounce.values = SPMotion.filterTokenBounceScales
        bounce.keyTimes = SPMotion.filterTokenBounceKeyTimes.map { NSNumber(value: Double($0)) }
        bounce.duration = SPMotion.filterTokenBounceDuration
        layer.add(bounce, forKey: "filtersBounce")
    }
}

// MARK: - Tokens

/// `FilterTextAttachment`: a filter shown as a capsule chip in the search text.
final class FilterTokenAttachment: NSTextAttachment {
    let filter: SearchQuery.Filter

    init(filter: SearchQuery.Filter, title: String, icon: NSImage) {
        self.filter = filter
        super.init(data: nil, ofType: nil)
        attachmentCell = FilterTokenCell(title: title, icon: icon)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// Padding 2 / 6 / 2 / 6, a 12 pt icon, 2 pt gap, the label in body `labelColor`, on an `ink10` continuous capsule.
final class FilterTokenCell: NSTextAttachmentCell {
    private let label: String
    private let icon: NSImage
    /// Space kept on either side of the chip so it doesn't touch neighbouring text.
    static let margin: CGFloat = 2

    init(title: String, icon: NSImage) {
        self.label = title
        self.icon = icon
        super.init(textCell: "")
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var labelAttributes: [NSAttributedString.Key: Any] {
        [.font: SPFont.style(.body), .foregroundColor: NSColor.labelColor]
    }

    private var labelSize: NSSize { (label as NSString).size(withAttributes: labelAttributes) }

    override func cellSize() -> NSSize {
        let p = SPMetrics.Toolbar.filterTokenPadding
        let width = p.left + SPMetrics.Toolbar.filterTokenIconSize + SPMetrics.Toolbar.filterTokenSpacing
            + ceil(labelSize.width) + p.right
        return NSSize(width: width + 2 * Self.margin, height: SPMetrics.Toolbar.searchTextHeight - 2)
    }

    override func cellBaselineOffset() -> NSPoint {
        let font = SPFont.style(.body)
        return NSPoint(x: 0, y: floor(font.descender - (cellSize().height - font.ascender + font.descender) / 2))
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        let p = SPMetrics.Toolbar.filterTokenPadding
        let chip = cellFrame.insetBy(dx: Self.margin, dy: 0)
        let path = NSBezierPath(roundedRect: chip, xRadius: chip.height / 2, yRadius: chip.height / 2)
        SPColor.ink10.setFill()
        path.fill()
        let iconSide = SPMetrics.Toolbar.filterTokenIconSize
        let flipped = controlView?.isFlipped ?? true
        let iconRect = NSRect(x: chip.minX + p.left, y: chip.midY - iconSide / 2, width: iconSide, height: iconSide)
        let tinted = icon.isTemplate ? icon.tinted(NSColor.labelColor) : icon
        tinted.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        let size = labelSize
        let labelOrigin = NSPoint(x: iconRect.maxX + SPMetrics.Toolbar.filterTokenSpacing,
                                  y: flipped ? chip.midY - size.height / 2 : chip.midY - size.height / 2)
        (label as NSString).draw(at: labelOrigin, withAttributes: labelAttributes)
    }

    override func wantsToTrackMouse() -> Bool { false }
}

extension NSImage {
    /// A template image filled with `color`.
    func tinted(_ color: NSColor) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        return image
    }
}

// MARK: - Suggestions menu

/// `FilterSuggestionsMenu` (ui-reference §3.3): a floating list above the field, clamped to the visible frame − 6;
/// rows 3 / 8 / 3 / 8 with an 18 pt icon 7 from the text; the selected row on the accent colour.
@MainActor
final class SuggestionsWindowController {
    private var panel: NSPanel?
    private let list = SuggestionListView()
    var onAccept: ((FilterSuggestion) -> Void)?
    var isVisible: Bool { panel?.isVisible ?? false }
    var selected: FilterSuggestion? { list.selectedItem }

    init() {
        list.onAccept = { [weak self] item in self?.onAccept?(item) }
    }

    func show(_ items: [FilterSuggestion], sources: FilterSources, style: SPStyle, below: Bool, anchor: NSRect, parent: NSWindow) {
        list.set(items, sources: sources, style: style)
        let size = list.fittingSize(width: max(anchor.width, 240))
        let panel = self.panel ?? makePanel(style: style)
        self.panel = panel
        let screen = (parent.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: SPMetrics.Toolbar.suggestionsScreenMargin,
                                                                            dy: SPMetrics.Toolbar.suggestionsScreenMargin)
        var frame = NSRect(x: anchor.minX, y: below ? anchor.minY - 4 - size.height : anchor.maxY + 4,
                           width: size.width, height: size.height)
        if let screen {
            frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
        if panel.parent == nil { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func moveSelection(_ delta: Int) { list.moveSelection(delta) }

    private func makePanel(style: SPStyle) -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = NSWindow.Level(rawValue: SPMetrics.Strip.windowLevel.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let background = BackgroundEffectView(style: style, cornerRadius: SPMetrics.Toolbar.suggestionsCornerRadius)
        background.contentView.addSubview(list)
        list.autoresizingMask = [.width, .height]
        panel.contentView = background
        return panel
    }
}

final class SuggestionListView: FlippedView {
    private var items: [FilterSuggestion] = []
    private var rows: [SuggestionRow] = []
    private(set) var selectedIndex = 0
    var onAccept: ((FilterSuggestion) -> Void)?

    static let rowHeight: CGFloat = SPMetrics.Toolbar.suggestionsRowPadding.top + SPMetrics.Toolbar.suggestionsIconSize
        + SPMetrics.Toolbar.suggestionsRowPadding.bottom

    var selectedItem: FilterSuggestion? { items.indices.contains(selectedIndex) ? items[selectedIndex] : nil }

    func set(_ items: [FilterSuggestion], sources: FilterSources, style: SPStyle) {
        self.items = items
        selectedIndex = 0
        rows.forEach { $0.removeFromSuperview() }
        rows = items.enumerated().map { index, item in
            let row = SuggestionRow(item: item, icon: sources.icon(for: item.filter, style: style,
                                                                     size: SPMetrics.Toolbar.suggestionsIconSize))
            row.onClick = { [weak self] in self?.onAccept?(item) }
            row.onHover = { [weak self] in self?.select(index) }
            addSubview(row)
            return row
        }
        select(0)
        needsLayout = true
    }

    func fittingSize(width: CGFloat) -> NSSize {
        let inset = SPMetrics.Toolbar.suggestionsListInset
        return NSSize(width: width, height: CGFloat(items.count) * Self.rowHeight + 2 * inset)
    }

    func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        select((selectedIndex + delta + items.count) % items.count)
    }

    private func select(_ index: Int) {
        selectedIndex = index
        for (i, row) in rows.enumerated() { row.isSelected = i == index }
    }

    override func layout() {
        super.layout()
        let inset = SPMetrics.Toolbar.suggestionsListInset
        for (i, row) in rows.enumerated() {
            row.frame = NSRect(x: inset, y: inset + CGFloat(i) * Self.rowHeight, width: bounds.width - 2 * inset,
                               height: Self.rowHeight)
        }
    }
}

private final class SuggestionRow: FillView {
    private let icon = NSImageView()
    private let title = Labels.make(font: SPFont.style(.body), color: .labelColor)
    private let subtitle = Labels.make(font: SPFont.style(.body), color: .secondaryLabelColor)
    var onClick: (() -> Void)?
    var onHover: (() -> Void)?
    var isSelected = false { didSet { update() } }
    private var tracking: NSTrackingArea?

    init(item: FilterSuggestion, icon image: NSImage) {
        super.init(frame: .zero)
        icon.image = image
        icon.imageScaling = .scaleProportionallyDown
        title.stringValue = item.title
        subtitle.stringValue = item.subtitle
        cornerRadius = 5
        [icon, title, subtitle].forEach(addSubview)
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func update() {
        fillColor = isSelected ? .controlAccentColor : nil
        title.textColor = isSelected ? .white : .labelColor
        subtitle.textColor = isSelected ? .white.withAlphaComponent(0.6) : .secondaryLabelColor
        icon.contentTintColor = isSelected ? .white : .labelColor
    }

    override func layout() {
        super.layout()
        let p = SPMetrics.Toolbar.suggestionsRowPadding
        let side = SPMetrics.Toolbar.suggestionsIconSize
        icon.frame = NSRect(x: p.left, y: p.top, width: side, height: side)
        let titleSize = title.labelSize
        let subtitleSize = subtitle.labelSize
        let x = icon.frame.maxX + SPMetrics.Toolbar.suggestionsSpacing
        subtitle.frame = NSRect(x: bounds.width - p.right - subtitleSize.width, y: round((bounds.height - subtitleSize.height) / 2),
                                width: subtitleSize.width, height: subtitleSize.height)
        title.frame = NSRect(x: x, y: round((bounds.height - titleSize.height) / 2),
                             width: max(0, min(titleSize.width, subtitle.frame.minX - 8 - x)), height: titleSize.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseUp(with event: NSEvent) { onClick?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
