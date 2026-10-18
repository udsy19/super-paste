import AppKit
import SuperPasteCore

/// `PasteUI.ToolbarButton` (ui-reference §3.2): a symbol and/or title on a shape that shows hover (`ink05`), press
/// (`ink10` @ 0.15) and selection (`ink10`). Large buttons are 32×32; regular ones 22 high, ≥ 32 wide.
final class ToolbarButton: FillView {
    enum Size { case large, regular }

    let size: Size
    var style: SPStyle { didSet { updateAppearance() } }
    var symbolName: String? { didSet { updateContent() } }
    var title: String? { didSet { updateContent() } }
    /// Tint for the symbol, overriding the default ink.
    var symbolTint: NSColor? { didSet { updateAppearance() } }
    var isPrimary = false { didSet { updateAppearance() } }
    var isSelected = false { didSet { updateAppearance() } }
    var isEnabled = true { didSet { updateAppearance() } }
    var action: (@MainActor (ToolbarButton) -> Void)?
    /// When set, a press pops this menu below the button (y offset as given) instead of running `action`.
    var menuProvider: (@MainActor () -> NSMenu?)?
    var menuOffsetY: CGFloat = 4

    private let imageView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var isHovered = false { didSet { updateAppearance() } }
    private var isPressed = false { didSet { updateAppearance() } }
    private var tracking: NSTrackingArea?

    init(size: Size, style: SPStyle = .current, symbol: String? = nil, title: String? = nil) {
        self.size = size
        self.style = style
        self.symbolName = symbol
        self.title = title
        super.init(frame: .zero)
        imageView.imageScaling = .scaleNone
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byClipping
        addSubview(imageView)
        addSubview(titleLabel)
        updateContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // MARK: Content

    private var symbolConfig: NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(textStyle: size == .large ? .title2 : .body)
    }

    private func updateContent() {
        imageView.image = symbolName.map { Symbols.image($0, config: symbolConfig, description: title ?? toolTip) }
        imageView.isHidden = symbolName == nil
        titleLabel.stringValue = title ?? ""
        titleLabel.font = size == .large ? SPFont.style(.title3) : SPFont.style(.body)
        titleLabel.isHidden = title == nil
        updateAppearance()
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private var tint: NSColor {
        if !isEnabled { return .secondaryLabelColor }
        if isPrimary { return .white }
        return symbolTint ?? (style == .glass ? SPColor.ink85 : SPColor.ink50)
    }

    private func updateAppearance() {
        let ink = tint
        imageView.contentTintColor = ink
        titleLabel.textColor = isPrimary ? .white : (isEnabled ? (style == .glass ? SPColor.ink85 : NSColor.labelColor) : .secondaryLabelColor)
        if isPrimary {
            fillColor = .controlAccentColor
        } else if isPressed {
            fillColor = SPColor.ink10.withAlphaComponent(0.15)
        } else if isSelected {
            fillColor = SPColor.ink10
        } else if isHovered && isEnabled {
            fillColor = SPColor.ink05
        } else {
            fillColor = nil
        }
        borderColor = title != nil && !isPrimary ? SPColor.ink05 : nil
        borderWidth = title != nil && !isPrimary ? 1 : 0
        let metrics = SPMetrics(style: style)
        cornerRadius = metrics.toolbarButtonRadius(height: intrinsicContentSize.height, large: size == .large)
        cornerCurve = style == .glass ? .continuous : .circular
    }

    override var intrinsicContentSize: NSSize {
        switch size {
        case .large where title == nil:
            return NSSize(width: SPMetrics.Toolbar.largeButtonSize, height: SPMetrics.Toolbar.largeButtonSize)
        case .large:
            let width = contentWidth + 2 * SPMetrics.Toolbar.regularButtonPadding
            return NSSize(width: max(SPMetrics.Toolbar.largeButtonSize, width), height: SPMetrics.Toolbar.largeButtonSize)
        case .regular:
            let width = contentWidth + 2 * SPMetrics.Toolbar.regularButtonPadding
            return NSSize(width: max(SPMetrics.Toolbar.regularButtonMinWidth, width), height: SPMetrics.Toolbar.regularButtonHeight)
        }
    }

    override var fittingSize: NSSize { intrinsicContentSize }

    private var contentWidth: CGFloat {
        var parts: [CGFloat] = []
        if symbolName != nil { parts.append(imageView.image?.size.width ?? 0) }
        if title != nil { parts.append(ceil(titleLabel.labelSize.width)) }
        return parts.reduce(0, +) + CGFloat(max(0, parts.count - 1)) * SPMetrics.Toolbar.regularButtonSpacing
    }

    override func layout() {
        super.layout()
        let imageSize = symbolName == nil ? .zero : (imageView.image?.size ?? .zero)
        let titleSize = title == nil ? .zero : titleLabel.labelSize
        let gap = symbolName != nil && title != nil ? SPMetrics.Toolbar.regularButtonSpacing : 0
        let total = imageSize.width + gap + ceil(titleSize.width)
        var x = round((bounds.width - total) / 2)
        imageView.frame = NSRect(x: x, y: round((bounds.height - imageSize.height) / 2), width: imageSize.width,
                                 height: imageSize.height)
        x += imageSize.width + gap
        titleLabel.frame = NSRect(x: x, y: round((bounds.height - titleSize.height) / 2), width: ceil(titleSize.width),
                                  height: titleSize.height)
        updateAppearance()
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
        guard isEnabled else { return }
        if let menu = menuProvider?() {
            isPressed = true
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + menuOffsetY), in: self)
            isPressed = false
            return
        }
        isPressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, menuProvider == nil else { return }
        isPressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEnabled, menuProvider == nil else { return }
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        if inside { action?(self) }
    }

    /// Runs the action as if clicked (keyboard shortcuts).
    func performClick() {
        if let menu = menuProvider?() {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + menuOffsetY), in: self)
        } else {
            action?(self)
        }
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { title ?? toolTip }
    override func accessibilityPerformPress() -> Bool { performClick(); return true }
}
