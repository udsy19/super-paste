import AppKit
import SuperPasteCore

/// The body of a card below its header, one subclass per kind (ui-reference §4.5).
class CardContentView: FlippedView {
    /// Where the content starts in the card: the header height, or 0 for full-size compact media.
    var contentTopInset: CGFloat = 0

    required override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(_ item: ClipItem, context: CardContext) {}

    static func type(for kind: ItemKind) -> CardContentView.Type {
        switch kind {
        case .text, .richText, .html: TextCardContent.self
        case .link: LinkCardContent.self
        case .image: ImageCardContent.self
        case .color: ColorCardContent.self
        case .files: FilesCardContent.self
        case .unknown: UnknownCardContent.self
        }
    }
}

// MARK: - Text

/// Text and rich text: the first lines in body type over `linkBg` (or the rich text's own background), with an
/// "N characters" footer over a fade.
final class TextCardContent: CardContentView {
    private let background = FillView()
    private let textLabel = NSTextField(wrappingLabelWithString: "")
    private let fade = GradientView()
    private let opaqueStrip = FillView()
    private let footer = Labels.make(font: SPFont.style(.callout), color: SPColor.ink50, alignment: .center)
    private var opaqueHeight = SPMetrics.Cards.footerOpaqueHeight

    required init(frame: NSRect) {
        super.init(frame: frame)
        textLabel.isSelectable = false
        textLabel.drawsBackground = false
        textLabel.maximumNumberOfLines = 0
        textLabel.cell?.truncatesLastVisibleLine = false
        [background, textLabel, fade, opaqueStrip, footer].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func configure(_ item: ClipItem, context: CardContext) {
        let fill: NSColor
        if let rich = ItemAssets.shared.richText(for: item) {
            textLabel.attributedStringValue = Self.defaultingColors(rich.text)
            fill = rich.background ?? SPColor.linkBackground
            appearance = rich.background?.readableAppearance
        } else {
            textLabel.font = SPFont.style(.body)
            textLabel.textColor = .labelColor
            textLabel.stringValue = CardText.excerpt(item.text)
            fill = SPColor.linkBackground
            appearance = nil
        }
        textLabel.alignment = .natural
        background.fillColor = fill
        fade.colors = [fill.withAlphaComponent(0), fill]
        opaqueStrip.fillColor = fill
        opaqueHeight = context.sizeClass == .compact ? 0 : SPMetrics.Cards.footerOpaqueHeight
        // Without the opaque strip (compact) the fade turns solid above the footer label, so text never shows
        // through it.
        fade.locations = opaqueHeight == 0 ? [0, 0.2] : nil
        footer.stringValue = L10n.characters(item.textLength)
        needsLayout = true
    }

    /// Rich text without a colour of its own reads in the card's ink.
    private static func defaultingColors(_ text: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: text)
        copy.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
            if value == nil { copy.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range) }
        }
        return copy
    }

    override func layout() {
        super.layout()
        let insets = SPMetrics.Cards.textInsets
        background.frame = bounds
        textLabel.frame = NSRect(x: insets.left, y: insets.top, width: max(0, bounds.width - insets.left - insets.right),
                                 height: max(0, bounds.height - insets.top))
        let footerHeight = footer.labelSize.height
        opaqueStrip.frame = NSRect(x: 0, y: bounds.height - opaqueHeight, width: bounds.width, height: opaqueHeight)
        fade.frame = NSRect(x: 0, y: opaqueStrip.frame.minY - SPMetrics.Cards.footerFadeHeight, width: bounds.width,
                            height: SPMetrics.Cards.footerFadeHeight)
        footer.frame = NSRect(x: insets.left, y: bounds.height - SPMetrics.Cards.footerBottom - footerHeight,
                              width: max(0, bounds.width - insets.left - insets.right), height: footerHeight)
    }
}

// MARK: - Link

/// Links: the preview image (or the favicon) above a footer with the page title and the host.
final class LinkCardContent: CardContentView {
    private let background = FillView()
    private let preview = AspectFillImageView()
    private let favicon = NSImageView()
    private let title = Labels.make(font: SPFont.style(.body, weight: .semibold), color: .labelColor)
    private let url = Labels.make(font: SPFont.style(.callout), color: SPColor.ink50, truncation: .byTruncatingTail)
    private var hasPreviewImage = false

    required init(frame: NSRect) {
        super.init(frame: frame)
        favicon.imageScaling = .scaleProportionallyUpOrDown
        favicon.wantsLayer = true
        favicon.layer?.masksToBounds = true
        background.fillColor = SPColor.linkBackground
        [background, preview, favicon, title, url].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func configure(_ item: ClipItem, context: CardContext) {
        let previews = context.linkPreviewsEnabled
        let image = previews ? ItemAssets.shared.image(item.link?.image) : nil
        hasPreviewImage = image != nil
        preview.image = image
        preview.isHidden = image == nil
        let icon = previews ? ItemAssets.shared.image(item.link?.icon) : nil
        favicon.image = icon ?? Symbols.image("safari", config: .init(pointSize: SPMetrics.Cards.linkFaviconSize, weight: .regular))
        favicon.contentTintColor = icon == nil ? SPColor.ink50 : nil
        favicon.layer?.cornerRadius = icon == nil ? 0 : context.metrics.linkFaviconRadius
        favicon.layer?.cornerCurve = context.style == .glass ? .continuous : .circular
        favicon.isHidden = image != nil
        title.stringValue = ItemPresentation.linkTitle(item)
        url.stringValue = ItemPresentation.displayHost(ItemPresentation.linkURL(item))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        let insets = SPMetrics.Cards.textInsets
        let width = max(0, bounds.width - insets.left - insets.right)
        let urlHeight = url.labelSize.height
        let titleHeight = Labels.height(of: title, width: width)
        let urlY = bounds.height - insets.bottom - urlHeight
        url.frame = NSRect(x: insets.left, y: urlY, width: width, height: urlHeight)
        title.frame = NSRect(x: insets.left, y: urlY - 3 - titleHeight, width: width, height: titleHeight)
        let footerTop = max(0, title.frame.minY - insets.top)
        preview.frame = NSRect(x: 0, y: 0, width: bounds.width, height: footerTop)
        let side = SPMetrics.Cards.linkFaviconSize
        favicon.frame = NSRect(x: round((bounds.width - side) / 2), y: round((footerTop - side) / 2), width: side, height: side)
    }
}

// MARK: - Image

/// Images: the picture filling the card over a checkerboard (transparent pixels show it).
final class ImageCardContent: CardContentView {
    private let checkerboard = CheckerboardView()
    private let picture = AspectFillImageView()

    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(checkerboard)
        addSubview(picture)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func configure(_ item: ClipItem, context: CardContext) {
        picture.image = ItemAssets.shared.cardImage(for: item)
    }

    override func layout() {
        super.layout()
        checkerboard.frame = bounds
        picture.frame = bounds
    }
}

/// An image layer that fills its bounds, cropping to keep the aspect ratio.
final class AspectFillImageView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var gravity: CALayerContentsGravity = .resizeAspectFill { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer else { return }
        layer.contentsGravity = gravity
        layer.masksToBounds = true
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        layer.contents = image?.layerContents(forContentsScale: scale)
        layer.contentsScale = scale
    }
}

/// `CheckerboardView`: 8 pt squares behind images.
final class CheckerboardView: NSView {
    static let square: CGFloat = 8
    static let light = SPColor.dynamic("checkerLight", light: .white, dark: NSColor(hex: "#2C2C2E"))
    static let dark = SPColor.dynamic("checkerDark", light: NSColor(hex: "#E5E5EA"), dark: NSColor(hex: "#3A3A3C"))

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        Self.light.setFill()
        dirtyRect.fill()
        Self.dark.setFill()
        let s = Self.square
        let firstRow = Int(floor(dirtyRect.minY / s)), lastRow = Int(ceil(dirtyRect.maxY / s))
        let firstCol = Int(floor(dirtyRect.minX / s)), lastCol = Int(ceil(dirtyRect.maxX / s))
        for row in firstRow..<lastRow {
            for col in firstCol..<lastCol where (row + col) % 2 == 1 {
                NSRect(x: CGFloat(col) * s, y: CGFloat(row) * s, width: s, height: s).fill()
            }
        }
    }
}

// MARK: - Colour

/// Colours: the body is the colour (the card sets it); the hex code sits in the middle, fixed-pitch, in secondary ink
/// that reads on the colour.
final class ColorCardContent: CardContentView {
    private let label = Labels.make(font: .monospacedSystemFont(ofSize: SPFont.style(.callout).pointSize, weight: .regular),
                                    color: SPColor.ink50, lines: 2, alignment: .center)

    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func configure(_ item: ClipItem, context: CardContext) {
        let hex = ItemPresentation.colorHex(item) ?? item.text
        label.stringValue = hex.uppercased()
        appearance = NSColor(hex: hex).readableAppearance
    }

    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 24)
        let height = Labels.height(of: label, width: width)
        label.frame = NSRect(x: 12, y: round((bounds.height - height) / 2), width: width, height: height)
    }
}

// MARK: - Files

/// Files: the file's icon or Quick Look thumbnail over its path (head-truncated); several files add "Multiple files"
/// above the folder.
final class FilesCardContent: CardContentView {
    private let background = FillView()
    private let icon = NSImageView()
    private let name = Labels.make(font: SPFont.style(.body, weight: .medium), color: .labelColor, alignment: .center,
                                   truncation: .byTruncatingMiddle)
    private let path = Labels.make(font: SPFont.style(.callout), color: SPColor.ink50, alignment: .center,
                                   truncation: .byTruncatingHead)

    required init(frame: NSRect) {
        super.init(frame: frame)
        icon.imageScaling = .scaleProportionallyUpOrDown
        background.fillColor = SPColor.linkBackground
        [background, icon, name, path].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func configure(_ item: ClipItem, context: CardContext) {
        let thumbnail = context.fileThumbnailsEnabled ? ItemAssets.shared.image(item.thumbnail) : nil
        if let thumbnail {
            icon.image = thumbnail
        } else if let first = item.filePaths.first, FileManager.default.fileExists(atPath: first) {
            icon.image = NSWorkspace.shared.icon(forFile: first)
        } else {
            icon.image = NSWorkspace.shared.icon(for: .data)
        }
        name.isHidden = item.filePaths.count <= 1
        name.stringValue = name.isHidden ? "" : ItemPresentation.filesTitle(item)
        path.stringValue = ItemPresentation.filesPath(item)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        let insets = SPMetrics.Cards.textInsets
        let width = max(0, bounds.width - insets.left - insets.right)
        let pathHeight = path.labelSize.height
        let nameHeight = name.isHidden ? 0 : name.labelSize.height
        path.frame = NSRect(x: insets.left, y: bounds.height - insets.bottom - pathHeight, width: width, height: pathHeight)
        name.frame = NSRect(x: insets.left, y: path.frame.minY - nameHeight, width: width, height: nameHeight)
        let available = max(0, name.frame.minY - insets.top - 6)
        let side = min(available, width, 128)
        icon.frame = NSRect(x: round((bounds.width - side) / 2), y: insets.top + round((available - side) / 2),
                            width: side, height: side)
    }
}

// MARK: - Unknown

/// Items of an unrecognised type: a warning symbol and "Preview unavailable" (behaviour.md §2.5).
final class UnknownCardContent: CardContentView {
    private let symbol = NSImageView()
    private let label = Labels.make(font: SPFont.style(.callout), color: .secondaryLabelColor, lines: 2, alignment: .center)

    required init(frame: NSRect) {
        super.init(frame: frame)
        symbol.contentTintColor = .secondaryLabelColor
        addSubview(symbol)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func configure(_ item: ClipItem, context: CardContext) {
        symbol.image = Symbols.image("exclamationmark.triangle",
                                     config: .init(pointSize: context.metrics.unknownSymbolSize, weight: .regular))
        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        label.stringValue = text.isEmpty ? L10n.previewUnavailable : text
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let symbolSize = symbol.intrinsicContentSize
        let width = max(0, bounds.width - 24)
        let labelHeight = Labels.height(of: label, width: width)
        let total = symbolSize.height + 8 + labelHeight
        let top = round((bounds.height - total) / 2)
        symbol.frame = NSRect(x: round((bounds.width - symbolSize.width) / 2), y: top, width: symbolSize.width,
                              height: symbolSize.height)
        label.frame = NSRect(x: 12, y: symbol.frame.maxY + 8, width: width, height: labelHeight)
    }
}
