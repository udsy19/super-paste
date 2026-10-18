import AppKit
import Quartz
import WebKit
import SuperPasteCore

/// Preview and edit (behaviour.md §4.8, ui-reference §6): a transient popover above the selected card that can be
/// dragged off into its own floating window (one window per item).
@MainActor
final class PreviewController: NSObject, NSPopoverDelegate {
    weak var strip: StripController?
    private var popover: NSPopover?
    private var popoverController: PreviewViewController?
    private var windows: [UUID: ItemPreviewWindow] = [:]

    var isShowing: Bool { popover?.isShown == true }

    /// The preview size: a quarter of the screen plus (10, 76), at least 380 × 240 (ui-reference §6.1).
    static func initialSize(for screen: NSScreen?) -> NSSize {
        let frame = (screen ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let p = SPMetrics.Preview.self
        return NSSize(width: max(p.minWindowSize.width, round(frame.width * p.initialScreenFraction + p.initialExtra.width)),
                      height: max(p.minWindowSize.height, round(frame.height * p.initialScreenFraction + p.initialExtra.height)))
    }

    func toggle(_ items: [ClipItem], from card: NSView?) {
        if isShowing { closePopover() } else { show(items, from: card) }
    }

    func show(_ items: [ClipItem], from card: NSView?, editing: Bool = false) {
        guard let item = items.first else { return }
        if let window = windows[item.id] {
            window.orderFront(nil)
            if editing { window.previewController?.setEditing(true) }
            return
        }
        guard let anchor = card ?? strip?.root else { return }
        let controller = PreviewViewController(item: item, style: strip?.style ?? .current, editing: editing)
        controller.host = self
        let popover = self.popover ?? NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = Self.initialSize(for: anchor.window?.screen)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.topEdge)
        self.popover = popover
        popoverController = controller
    }

    func edit(_ item: ClipItem, from card: NSView?) {
        if isShowing, popoverController?.item.id == item.id { popoverController?.setEditing(true); return }
        closePopover()
        show([item], from: card, editing: true)
    }

    func closePopover() {
        popover?.close()
    }

    /// While the popover shows, it follows the keyboard selection.
    func selectionChanged(_ items: [ClipItem], anchor: NSView?) {
        guard isShowing, let item = items.first, popoverController?.item.id != item.id,
              popoverController?.isEditing != true, let anchor else { return }
        let controller = PreviewViewController(item: item, style: strip?.style ?? .current, editing: false)
        controller.host = self
        popover?.contentViewController = controller
        popoverController = controller
        popover?.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.topEdge)
    }

    func closed(_ controller: PreviewViewController) {
        if controller === popoverController { closePopover() }
        for (id, window) in windows where window.previewController === controller {
            window.close()
            windows[id] = nil
        }
    }

    func saved(_ item: ClipItem, draft: ClipDraft) {
        guard let strip else {
            _ = try? Services.store?.replaceContent(of: item.id, with: draft)
            return
        }
        strip.changeItems([item.id], actionName: L10n.edit) { try $0.replaceContent(of: item.id, with: draft) }
    }

    func renamed(_ item: ClipItem, to title: String?) {
        if let strip { strip.changeItems([item.id], actionName: L10n.rename) { try $0.rename(item.id, to: title) } }
        else { try? Services.store?.rename(item.id, to: title) }
    }

    // MARK: NSPopoverDelegate

    func popoverShouldDetach(_ popover: NSPopover) -> Bool { true }

    func detachableWindow(for popover: NSPopover) -> NSWindow? {
        guard let current = popoverController else { return nil }
        let controller = PreviewViewController(item: current.item, style: current.style, editing: current.isEditing)
        controller.host = self
        let window = ItemPreviewWindow(controller: controller)
        window.onClose = { [weak self] in self?.windows[current.item.id] = nil }
        windows[current.item.id] = window
        return window
    }

    func popoverDidClose(_ notification: Notification) {
        popoverController = nil
        popover = nil
        strip?.focusCards()
    }
}

/// `ItemPreviewWindow` (ui-reference §6.1): a floating utility panel with a hidden, transparent title bar, movable by
/// its background, at least 380 × 240.
final class ItemPreviewWindow: NSPanel, NSWindowDelegate {
    var onClose: (() -> Void)?
    var previewController: PreviewViewController? { contentViewController as? PreviewViewController }

    init(controller: PreviewViewController) {
        let size = PreviewController.initialSize(for: NSScreen.main)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .resizable, .utilityWindow, .fullSizeContentView],
                   backing: .buffered, defer: true)
        contentViewController = controller
        setContentSize(size)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        animationBehavior = .none
        minSize = SPMetrics.Preview.minWindowSize
        isReleasedWhenClosed = false
        delegate = self
    }

    func windowWillClose(_ notification: Notification) { onClose?() }
}

// MARK: - Preview content

/// One item's preview or editor: the 38 pt header, the content for its kind, and a footer.
final class PreviewViewController: NSViewController, NSTextFieldDelegate {
    let item: ClipItem
    let style: SPStyle
    weak var host: PreviewController?
    private(set) var isEditing: Bool

    private let header = FlippedView()
    private let closeButton = NSButton()
    private let titleField = NSTextField(labelWithString: "")
    private var trailing: [NSView] = []
    private var body: PreviewBody?
    private let footer = PreviewFooter()

    init(item: ClipItem, style: SPStyle, editing: Bool) {
        self.item = item
        self.style = style
        self.isEditing = editing
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func loadView() {
        let root = PreviewRootView()
        root.controller = self
        view = root
        closeButton.isBordered = false
        closeButton.image = Symbols.image("xmark.circle.fill", config: .init(textStyle: .body))
        closeButton.contentTintColor = SPColor.ink85.withAlphaComponent(0.6)
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        titleField.font = SPFont.style(.headline)
        titleField.textColor = .labelColor
        titleField.alignment = .center
        titleField.lineBreakMode = .byTruncatingTail
        titleField.delegate = self
        header.addSubview(closeButton)
        header.addSubview(titleField)
        root.addSubview(header)
        root.addSubview(footer)
        rebuild()
    }

    func setEditing(_ editing: Bool) {
        guard editing != isEditing else { return }
        isEditing = editing
        rebuild()
    }

    private func rebuild() {
        body?.removeFromSuperview()
        trailing.forEach { $0.removeFromSuperview() }
        let body = PreviewBody.make(for: item, style: style, editing: isEditing)
        view.addSubview(body, positioned: .below, relativeTo: footer)
        self.body = body
        body.onChange = { [weak self] in self?.updateFooter() }

        if isEditing {
            titleField.stringValue = Self.editTitle(item)
            titleField.isEditable = false
            let cancel = ToolbarButton(size: .regular, style: style, title: L10n.cancel)
            cancel.toolTip = L10n.discardChanges
            cancel.action = { [weak self] _ in self?.cancelEditing() }
            let save = ToolbarButton(size: .regular, style: style, title: L10n.save)
            save.isPrimary = true
            save.toolTip = "\(L10n.saveChanges) (⌘S)"
            save.action = { [weak self] _ in self?.save() }
            var buttons: [NSView] = [cancel]
            if let text = body as? TextPreviewBody, text.supportsWritingTools {
                let tools = ToolbarButton(size: .regular, style: style, symbol: "apple.writing.tools")
                tools.toolTip = L10n.writingTools
                tools.action = { _ in text.showWritingTools() }
                buttons.append(tools)
            }
            buttons.append(save)
            trailing = buttons
        } else {
            titleField.stringValue = ItemPresentation.headerTitle(item)
            titleField.isEditable = false
            let edit = ToolbarButton(size: .regular, style: style, title: L10n.edit)
            edit.action = { [weak self] _ in self?.setEditing(true) }
            let pin = ToolbarButton(size: .regular, style: style, symbol: item.isPinned ? "circle.fill" : "circle.dashed")
            if let board = pinboard { pin.symbolTint = SPColor.pinboard(board.color, style: style) }
            pin.toolTip = L10n.pin
            pin.menuProvider = { [weak self] in self?.pinMenu() }
            let share = ToolbarButton(size: .regular, style: style, symbol: "square.and.arrow.up")
            share.toolTip = L10n.share
            share.action = { [weak self] button in self?.share(from: button) }
            trailing = (StripController.isEditable(item) ? [edit] : []) + [pin, share]
        }
        trailing.forEach(header.addSubview)
        updateFooter()
        view.needsLayout = true
    }

    private var pinboard: Pinboard? {
        let boards = Services.store?.pinboards ?? []
        return item.pinboardIDs.lazy.compactMap { id in boards.first { $0.id == id } }.first
    }

    static func editTitle(_ item: ClipItem) -> String {
        switch item.kind {
        case .text, .richText, .html: L10n.editText
        case .image: L10n.editImage
        case .link: L10n.editLink
        case .color: L10n.editColor
        case .files, .unknown: L10n.editItem
        }
    }

    private func updateFooter() {
        footer.setContent(body?.footerViews(editing: isEditing) ?? ([], []))
        view.needsLayout = true
    }

    fileprivate func layout(in bounds: NSRect) {
        let h = SPMetrics.Preview.headerHeight
        header.frame = NSRect(x: 0, y: 0, width: bounds.width, height: h)
        let closeSize = closeButton.image?.size ?? NSSize(width: 16, height: 16)
        closeButton.frame = NSRect(x: 10, y: round((h - closeSize.height) / 2), width: closeSize.width, height: closeSize.height)
        var x = bounds.width - 8
        for view in trailing.reversed() {
            let size = view.contentFittingSize
            x -= size.width
            view.frame = NSRect(x: x, y: round((h - size.height) / 2), width: size.width, height: size.height)
            x -= 8
        }
        // Centred on the header when it fits between the close button and the trailing buttons, else as wide as it can.
        let titleSize = titleField.labelSize
        let minX = closeButton.frame.maxX + 8, maxX = x
        let width = min(titleSize.width, max(0, maxX - minX))
        let titleX = min(max(round((bounds.width - width) / 2), minX), maxX - width)
        titleField.frame = NSRect(x: titleX, y: round((h - titleSize.height) / 2), width: width, height: titleSize.height)
        let footerHeight = footer.isEmpty ? 0 : footer.fittingHeight
        footer.frame = NSRect(x: 0, y: bounds.height - footerHeight, width: bounds.width, height: footerHeight)
        body?.frame = NSRect(x: 0, y: h, width: bounds.width, height: max(0, bounds.height - h - footerHeight))
    }

    // MARK: Actions

    @objc private func closeClicked() { host?.closed(self) }

    private func cancelEditing() { setEditing(false) }

    func save() {
        guard isEditing, let draft = body?.draft(for: item) else { setEditing(false); return }
        host?.saved(item, draft: draft)
        host?.closed(self)
    }

    private func pinMenu() -> NSMenu? {
        guard let strip = host?.strip else { return nil }
        return strip.pinMenu(for: [item])
    }

    private func share(from view: NSView) {
        let object: Any? = switch item.kind {
        case .link: ItemPresentation.linkURL(item)
        case .files: item.filePaths.first.map { URL(fileURLWithPath: $0) }
        case .image: ItemAssets.shared.fullImage(for: item)
        default: item.text
        }
        guard let object else { return }
        NSSharingServicePicker(items: [object]).show(relativeTo: view.bounds, of: view, preferredEdge: view.topEdge)
    }

    // Double-click the title to rename (⌘R).
    fileprivate func beginTitleEditing() {
        guard !isEditing else { return }
        titleField.isEditable = true
        titleField.isSelectable = true
        view.window?.makeFirstResponder(titleField)
        titleField.currentEditor()?.selectAll(nil)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard titleField.isEditable, !isEditing else { return }
        titleField.isEditable = false
        let title = titleField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if title != ItemPresentation.headerTitle(item) { host?.renamed(item, to: title.isEmpty ? nil : title) }
    }

    fileprivate func handleKey(_ event: NSEvent) -> Bool {
        let key = KeyStroke(event: event)
        if isEditing, key.modifiers == .command, key.characters.lowercased() == "s" { save(); return true }
        if key.modifiers == .command, key.characters.lowercased() == "r" {
            if isEditing, let image = body as? ImagePreviewBody { image.rotate(clockwise: true); return true }
            beginTitleEditing(); return true
        }
        if isEditing, key.modifiers == .command, key.characters.lowercased() == "l", let image = body as? ImagePreviewBody {
            image.rotate(clockwise: false); return true
        }
        if isEditing, let text = body as? TextPreviewBody, key.modifiers == .command, text.handleFormatKey(key) { return true }
        if key.keyCode == 53 /* esc */, key.modifiers.isEmpty {
            if isEditing { setEditing(false) } else { host?.closed(self) }
            return true
        }
        if key.keyCode == 49 /* space */, key.modifiers.isEmpty, !isEditing, !(view.window?.firstResponder is NSText) {
            host?.closed(self); return true
        }
        return false
    }

    fileprivate func titleDoubleClicked() { beginTitleEditing() }
}

private final class PreviewRootView: FlippedView {
    weak var controller: PreviewViewController?

    override func layout() {
        super.layout()
        controller?.layout(in: bounds)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, controller?.handleKey(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) != true { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 2, point.y < SPMetrics.Preview.headerHeight { controller?.titleDoubleClicked(); return }
        super.mouseDown(with: event)
    }
}

/// The footer (ui-reference §6.3): insets 11 / 12 / 11 / 12 on a menu-material backdrop; leading and trailing views.
private final class PreviewFooter: FlippedView {
    private let backdrop = BackdropView(frame: .zero)
    private var leading: [NSView] = []
    private var trailing: [NSView] = []
    static let insets = NSEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)

    override init(frame: NSRect) {
        super.init(frame: frame)
        backdrop.cornerRadius = 0
        addSubview(backdrop)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var isEmpty: Bool { leading.isEmpty && trailing.isEmpty }

    var fittingHeight: CGFloat {
        let heights = (leading + trailing).map(\.contentFittingSize.height)
        return Self.insets.top + (heights.max() ?? 0) + Self.insets.bottom
    }

    func setContent(_ content: (leading: [NSView], trailing: [NSView])) {
        (leading + trailing).forEach { $0.removeFromSuperview() }
        leading = content.leading
        trailing = content.trailing
        (leading + trailing).forEach(addSubview)
        isHidden = isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        backdrop.frame = bounds
        var x = Self.insets.left
        for view in leading {
            let size = view.contentFittingSize
            view.frame = NSRect(x: x, y: round((bounds.height - size.height) / 2), width: size.width, height: size.height)
            x += size.width + 8
        }
        var right = bounds.width - Self.insets.right
        for view in trailing.reversed() {
            let size = view.contentFittingSize
            let width = min(size.width, max(0, right - x))
            right -= width
            view.frame = NSRect(x: right, y: round((bounds.height - size.height) / 2), width: width, height: size.height)
            right -= 8
        }
    }
}

// MARK: - Bodies

/// A preview's main area for one kind of item.
class PreviewBody: FlippedView {
    let style: SPStyle
    let editing: Bool
    var onChange: (() -> Void)?

    required init(item: ClipItem, style: SPStyle, editing: Bool) {
        self.style = style
        self.editing = editing
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func make(for item: ClipItem, style: SPStyle, editing: Bool) -> PreviewBody {
        let type: PreviewBody.Type = switch item.kind {
        case .text, .richText, .html: TextPreviewBody.self
        case .image: ImagePreviewBody.self
        case .link: LinkPreviewBody.self
        case .color: ColorPreviewBody.self
        case .files: FilesPreviewBody.self
        case .unknown: UnknownPreviewBody.self
        }
        return type.init(item: item, style: style, editing: editing)
    }

    /// Footer content: leading and trailing views.
    func footerViews(editing: Bool) -> (leading: [NSView], trailing: [NSView]) { ([], []) }

    /// The new content when saving an edit.
    func draft(for item: ClipItem) -> ClipDraft? { nil }

    static func footerLabel(_ text: String) -> NSTextField {
        let label = Labels.make(text, font: .monospacedDigitSystemFont(ofSize: SPFont.style(.body).pointSize, weight: .regular),
                                color: SPColor.ink50)
        return label
    }
}

/// Text: a scrolling text view (rich text keeps its formatting), "N characters · N words · N lines", and in edit
/// mode Bold / Italic / Underline / Strikethrough (ui-reference §6.3).
final class TextPreviewBody: PreviewBody, NSTextViewDelegate {
    private let scroll = NSTextView.scrollableTextView()
    private var textView: NSTextView { scroll.documentView as! NSTextView }
    private let isRich: Bool
    private let border = FillView()

    required init(item: ClipItem, style: SPStyle, editing: Bool) {
        let rich = ItemAssets.shared.richText(for: item, excerpt: false)
        isRich = rich != nil
        super.init(item: item, style: style, editing: editing)
        let tv = textView
        tv.isEditable = editing
        tv.isSelectable = true
        tv.isRichText = isRich
        tv.allowsUndo = true
        tv.textContainerInset = NSSize(width: 8, height: 10)
        tv.drawsBackground = false
        tv.delegate = self
        if let rich {
            tv.textStorage?.setAttributedString(rich.text)
        } else {
            tv.font = SPFont.style(.body)
            tv.textColor = .labelColor
            tv.string = Self.fullText(item)
        }
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        border.borderColor = SPColor.ink10
        border.borderWidth = editing ? SPMetrics.Preview.contentBorderWidth : 0
        border.cornerRadius = SPMetrics.Preview.contentBorderRadius
        addSubview(scroll)
        addSubview(border)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The full text from the payload (the item's `text` is capped).
    static func fullText(_ item: ClipItem) -> String {
        if item.textLength > item.text.count,
           let rep = item.payload.lazy.compactMap({ $0.rep(PasteboardType.plainText) }).first,
           let data = Services.store?.data(for: rep.blob), let text = String(data: data, encoding: .utf8) {
            return text
        }
        return item.text
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = editing ? 8 : 0
        scroll.frame = bounds.insetBy(dx: inset, dy: inset)
        border.frame = scroll.frame
    }

    func textDidChange(_ notification: Notification) { onChange?() }

    var supportsWritingTools: Bool {
        if #available(macOS 15.2, *) { return true }
        return false
    }

    func showWritingTools() {
        if #available(macOS 15.2, *) { textView.showWritingTools(nil) }
    }

    override func footerViews(editing: Bool) -> (leading: [NSView], trailing: [NSView]) {
        let counts = ItemPresentation.textCounts(textView.string)
        let label = Self.footerLabel([L10n.characters(counts.characters), L10n.words(counts.words), L10n.lines(counts.lines)]
            .joined(separator: " · "))
        guard editing, isRich else { return ([], [label]) }
        let formats: [(String, String, String)] = [("bold", L10n.bold, "⌘B"), ("italic", L10n.italic, "⌘I"),
                                                    ("underline", L10n.underline, "⌘U"), ("strikethrough", L10n.strikethrough, "")]
        let buttons = formats.map { symbol, title, shortcut in
            let button = ToolbarButton(size: .regular, style: style, symbol: symbol)
            button.toolTip = shortcut.isEmpty ? title : "\(title) (\(shortcut))"
            button.action = { [weak self] _ in self?.applyFormat(symbol) }
            return button as NSView
        }
        return (buttons, [label])
    }

    func handleFormatKey(_ key: KeyStroke) -> Bool {
        guard isRich else { return false }
        switch key.characters.lowercased() {
        case "b": applyFormat("bold")
        case "i": applyFormat("italic")
        case "u": applyFormat("underline")
        default: return false
        }
        return true
    }

    private func applyFormat(_ format: String) {
        let tv = textView
        switch format {
        case "bold": NSFontManager.shared.addFontTrait(TraitSender.sender(.boldFontMask))
        case "italic": NSFontManager.shared.addFontTrait(TraitSender.sender(.italicFontMask))
        case "underline": tv.underline(nil)
        default:
            let range = tv.selectedRange()
            guard range.length > 0, let storage = tv.textStorage else { return }
            let current = storage.attribute(.strikethroughStyle, at: range.location, effectiveRange: nil) as? Int ?? 0
            storage.addAttribute(.strikethroughStyle, value: current == 0 ? NSUnderlineStyle.single.rawValue : 0, range: range)
        }
        onChange?()
    }

    override func draft(for item: ClipItem) -> ClipDraft? {
        let plain = textView.string
        guard isRich, let storage = textView.textStorage else {
            return ClipDraft.text(plain, title: item.title, sourceApp: item.sourceApp, copiedAt: item.copiedAt ?? Date())
        }
        let rtf = storage.rtf(from: NSRange(location: 0, length: storage.length), documentAttributes: [:]) ?? Data()
        return ClipDraft(entries: [EntryData(reps: [RepData(type: "public.rtf", data: rtf),
                                                    RepData(type: PasteboardType.plainText, data: Data(plain.utf8))])],
                         kind: .richText, text: plain, title: item.title, sourceApp: item.sourceApp, device: item.device,
                         copiedAt: item.copiedAt)
    }
}

/// `addFontTrait:` reads the trait from its sender's tag.
private final class TraitSender: NSObject {
    let tag: Int
    init(_ tag: Int) { self.tag = tag }
    static func sender(_ mask: NSFontTraitMask) -> TraitSender { TraitSender(Int(mask.rawValue)) }
}

/// Images: zoomable on a checkerboard, "W × H" in the footer; Rotate Left ⌘L / Rotate Right ⌘R in edit mode.
final class ImagePreviewBody: PreviewBody {
    private let scroll = NSScrollView()
    private let checkerboard = CheckerboardView()
    private let imageView = NSImageView()
    private var image: NSImage?
    private let originalSize: PixelSize?

    required init(item: ClipItem, style: SPStyle, editing: Bool) {
        image = ItemAssets.shared.fullImage(for: item)
        originalSize = item.imageSize
        super.init(item: item, style: style, editing: editing)
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        checkerboard.addSubview(imageView)
        scroll.documentView = checkerboard
        scroll.allowsMagnification = true
        scroll.minMagnification = 1
        scroll.maxMagnification = 8
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        scroll.frame = bounds
        checkerboard.frame = NSRect(origin: .zero, size: scroll.contentSize)
        imageView.frame = checkerboard.bounds
    }

    func rotate(clockwise: Bool) {
        guard let image, let rotated = Self.rotated(image, clockwise: clockwise) else { return }
        self.image = rotated
        imageView.image = rotated
        onChange?()
    }

    static func rotated(_ image: NSImage, clockwise: Bool) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = cg.height, height = cg.width
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: clockwise ? -.pi / 2 : .pi / 2)
        context.draw(cg, in: CGRect(x: -CGFloat(cg.width) / 2, y: -CGFloat(cg.height) / 2, width: CGFloat(cg.width),
                                    height: CGFloat(cg.height)))
        guard let result = context.makeImage() else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: width, height: height))
    }

    private var pixelSize: PixelSize? {
        guard let image, let rep = image.representations.first else { return originalSize }
        return PixelSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    override func footerViews(editing: Bool) -> (leading: [NSView], trailing: [NSView]) {
        let size = pixelSize.map { "\($0.width) × \($0.height)" } ?? ""
        let label = Labels.make(size, font: SPFont.style(.body), color: SPColor.ink50)
        guard editing else { return ([], [label]) }
        let left = ToolbarButton(size: .regular, style: style, symbol: "rotate.left")
        left.toolTip = "\(L10n.rotateLeft) (⌘L)"
        left.action = { [weak self] _ in self?.rotate(clockwise: false) }
        let right = ToolbarButton(size: .regular, style: style, symbol: "rotate.right")
        right.toolTip = "\(L10n.rotateRight) (⌘R)"
        right.action = { [weak self] _ in self?.rotate(clockwise: true) }
        return ([left, right], [label])
    }

    override func draft(for item: ClipItem) -> ClipDraft? {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let thumb = Self.thumbnail(of: image, maxSide: 512)
        return ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: png)])], kind: .image,
                         title: item.title, sourceApp: item.sourceApp, device: item.device, copiedAt: item.copiedAt,
                         imageSize: PixelSize(width: rep.pixelsWide, height: rep.pixelsHigh), thumbnail: thumb)
    }

    static func thumbnail(of image: NSImage, maxSide: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1, maxSide / max(size.width, size.height, 1))
        let target = NSSize(width: max(1, round(size.width * scale)), height: max(1, round(size.height * scale)))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(target.width), pixelsHigh: Int(target.height),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: target))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}

/// Links: the page in a web view when link previews are on (otherwise the card's image or favicon), the title and URL
/// in the footer; in edit mode, the URL in a field.
final class LinkPreviewBody: PreviewBody {
    private var web: WKWebView?
    private let fallback = AspectFillImageView()
    private let field = NSTextField()
    private let item: ClipItem

    required init(item: ClipItem, style: SPStyle, editing: Bool) {
        self.item = item
        super.init(item: item, style: style, editing: editing)
        if editing {
            field.stringValue = ItemPresentation.linkURL(item)?.absoluteString ?? item.text
            field.font = SPFont.style(.body)
            field.bezelStyle = .roundedBezel
            addSubview(field)
        } else if Defaults[.isLinkPreviewsEnabled], let url = ItemPresentation.linkURL(item) {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .nonPersistent()
            let web = WKWebView(frame: .zero, configuration: config)
            web.load(URLRequest(url: url))
            addSubview(web)
            self.web = web
        } else {
            // Without previews: the stored preview image, else the favicon, else `safari`, centred.
            let previews = Defaults[.isLinkPreviewsEnabled]
            if previews, let image = ItemAssets.shared.image(item.link?.image) {
                fallback.image = image
            } else {
                fallback.image = (previews ? ItemAssets.shared.image(item.link?.icon) : nil)
                    ?? Symbols.image("safari", config: .init(pointSize: SPMetrics.Cards.linkFaviconSize, weight: .regular))
                        .tinted(SPColor.ink50)
                fallback.gravity = .center
            }
            addSubview(fallback)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        web?.frame = bounds
        fallback.frame = bounds
        let height = field.intrinsicContentSize.height
        field.frame = NSRect(x: 12, y: 12, width: max(0, bounds.width - 24), height: height)
    }

    override func footerViews(editing: Bool) -> (leading: [NSView], trailing: [NSView]) {
        guard !editing else { return ([], []) }
        let title = Labels.make(ItemPresentation.linkTitle(item), font: SPFont.style(.body, weight: .semibold), color: .labelColor)
        let url = Labels.make(ItemPresentation.linkURL(item)?.absoluteString ?? item.text, font: SPFont.style(.body),
                              color: SPColor.ink50, truncation: .byTruncatingMiddle)
        return ([title], [url])
    }

    override func draft(for item: ClipItem) -> ClipDraft? {
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return ClipDraft.text(text, title: item.title, sourceApp: item.sourceApp, copiedAt: item.copiedAt ?? Date())
    }
}

/// Colours: a large swatch and HEX / RGB / HSL rows; in edit mode the hex in a fixed-pitch 22 pt field with a colour
/// well (the system colour panel).
final class ColorPreviewBody: PreviewBody, NSTextFieldDelegate {
    private let swatch = FillView()
    private var rows: [NSTextField] = []
    private let field = NSTextField()
    private let well = NSColorWell()
    private var color: NSColor

    required init(item: ClipItem, style: SPStyle, editing: Bool) {
        color = NSColor(hex: ItemPresentation.colorHex(item) ?? "#000000")
        super.init(item: item, style: style, editing: editing)
        swatch.cornerRadius = SPMetrics(style: style).cardCornerRadius
        swatch.cornerCurve = SPMetrics(style: style).cardCornerCurve
        addSubview(swatch)
        if editing {
            field.font = .userFixedPitchFont(ofSize: 22)
            field.alignment = .center
            field.delegate = self
            well.target = self
            well.action = #selector(wellChanged)
            addSubview(field)
            addSubview(well)
        }
        update()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    static func formats(_ color: NSColor) -> [(String, String)] {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded()), b = Int((c.blueComponent * 255).rounded())
        let hex = String(format: "#%06X", r << 16 | g << 8 | b)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        c.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lightness = brightness * (1 - saturation / 2)
        let hslSaturation = lightness == 0 || lightness == 1 ? 0 : (brightness - lightness) / min(lightness, 1 - lightness)
        let hsl = "\(Int((hue * 360).rounded())), \(Int((hslSaturation * 100).rounded())), \(Int((lightness * 100).rounded()))"
        return [("HEX", hex), ("RGB", "\(r), \(g), \(b)"), ("HSL", hsl)]
    }

    private func update() {
        swatch.fillColor = color
        rows.forEach { $0.removeFromSuperview() }
        rows = Self.formats(color).map { label, value in
            let row = Labels.make("\(label) · \(value)", font: SPFont.style(.body), color: .labelColor)
            addSubview(row)
            return row
        }
        if editing {
            field.stringValue = Self.formats(color)[0].1
            well.color = color
        }
        needsLayout = true
        onChange?()
    }

    @objc private func wellChanged() {
        color = well.color
        update()
    }

    func controlTextDidChange(_ obj: Notification) {
        if let hex = TextClassifier.colorHex(in: field.stringValue) {
            color = NSColor(hex: hex)
            swatch.fillColor = color
            well.color = color
        }
    }

    override func layout() {
        super.layout()
        let rowHeight = rows.first?.labelSize.height ?? 16
        let editHeight: CGFloat = editing ? 40 : 0
        let side = max(0, min(bounds.width - 48, bounds.height - 48 - CGFloat(rows.count) * (rowHeight + 4) - editHeight))
        swatch.frame = NSRect(x: round((bounds.width - side) / 2), y: 24, width: side, height: side)
        var y = swatch.frame.maxY + 12
        if editing {
            field.frame = NSRect(x: round(bounds.width / 2 - 100), y: y, width: 150, height: 30)
            well.frame = NSRect(x: field.frame.maxX + 8, y: y, width: 42, height: 30)
            y += editHeight
        }
        for row in rows {
            let width = row.labelSize.width
            row.frame = NSRect(x: round((bounds.width - width) / 2), y: y, width: width, height: rowHeight)
            y += rowHeight + 4
        }
    }

    override func draft(for item: ClipItem) -> ClipDraft? {
        let hex = TextClassifier.colorHex(in: field.stringValue) ?? color.hexString
        return ClipDraft.text(hex, title: item.title, sourceApp: item.sourceApp, copiedAt: item.copiedAt ?? Date())
    }
}

/// Files: Quick Look, with the size and Reveal in Finder in the footer.
final class FilesPreviewBody: PreviewBody {
    private var quickLook: QLPreviewView?
    private let item: ClipItem

    required init(item: ClipItem, style: SPStyle, editing: Bool) {
        self.item = item
        super.init(item: item, style: style, editing: editing)
        if let first = item.filePaths.first, let view = QLPreviewView(frame: .zero, style: .normal) {
            view.previewItem = URL(fileURLWithPath: first) as NSURL
            view.autostarts = true
            addSubview(view)
            quickLook = view
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        quickLook?.frame = bounds
    }

    override func footerViews(editing: Bool) -> (leading: [NSView], trailing: [NSView]) {
        let bytes = item.filePaths.reduce(Int64(0)) { total, path in
            total + ((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64) ?? 0)
        }
        // "Documents/website/backup.zip · 12.4 MB": the path (head-truncated) and the size.
        let path = ItemPresentation.filesPath(item)
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let label = Labels.make(path.isEmpty ? size : "\(path) · \(size)", font: SPFont.style(.body), color: SPColor.ink50,
                                truncation: .byTruncatingHead)
        let reveal = ToolbarButton(size: .regular, style: style, title: L10n.revealInFinder)
        let urls = item.filePaths.map { URL(fileURLWithPath: $0) }
        reveal.action = { _ in NSWorkspace.shared.activateFileViewerSelecting(urls) }
        return ([label], [reveal])
    }
}

/// Anything else: "Preview unavailable" (title2 medium) and why, in `ink50` (ui-reference §6.3).
final class UnknownPreviewBody: PreviewBody {
    private let symbol = NSImageView()
    private let title = Labels.make(L10n.previewUnavailable, font: SPFont.style(.title2, weight: .medium), color: .labelColor,
                                    alignment: .center)
    private let subtitle = Labels.make(L10n.previewUnavailableSubtitle, font: SPFont.style(.body), color: SPColor.ink50, lines: 3,
                                       alignment: .center)

    required init(item: ClipItem, style: SPStyle, editing: Bool) {
        super.init(item: item, style: style, editing: editing)
        symbol.image = Symbols.image("exclamationmark.triangle", config: .init(pointSize: 32, weight: .regular))
        symbol.contentTintColor = .secondaryLabelColor
        [symbol, title, subtitle].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        let width = min(bounds.width - 48, 360)
        let symbolSize = symbol.intrinsicContentSize
        let titleHeight = title.labelSize.height
        let subtitleHeight = Labels.height(of: subtitle, width: width)
        let total = symbolSize.height + 10 + titleHeight + 6 + subtitleHeight
        var y = round((bounds.height - total) / 2)
        symbol.frame = NSRect(x: round((bounds.width - symbolSize.width) / 2), y: y, width: symbolSize.width, height: symbolSize.height)
        y = symbol.frame.maxY + 10
        title.frame = NSRect(x: round((bounds.width - width) / 2), y: y, width: width, height: titleHeight)
        y = title.frame.maxY + 6
        subtitle.frame = NSRect(x: round((bounds.width - width) / 2), y: y, width: width, height: subtitleHeight)
    }
}
