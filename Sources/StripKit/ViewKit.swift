import AppKit
import SuperPasteCore

/// A flipped, layer-backed view whose fill and border colours resolve for its effective appearance.
class FillView: NSView {
    var fillColor: NSColor? { didSet { needsDisplay = true } }
    var borderColor: NSColor? { didSet { needsDisplay = true } }
    var borderWidth: CGFloat = 0 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 0 { didSet { needsDisplay = true } }
    var cornerCurve: CALayerCornerCurve = .circular { didSet { needsDisplay = true } }
    var clips = false { didSet { needsDisplay = true } }

    override init(frame: NSRect = .zero) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    /// Frame-based layout: a new size lays the subviews out again.
    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsLayout = true }
    }

    override func updateLayer() {
        guard let layer else { return }
        layer.backgroundColor = fillColor?.cgColor
        layer.borderColor = borderColor?.cgColor
        layer.borderWidth = borderWidth
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = cornerCurve
        layer.masksToBounds = clips
    }
}

/// A vertical gradient, first colour at the top, resolving its colours for the view's appearance.
final class GradientView: NSView {
    var colors: [NSColor] = [] { didSet { needsDisplay = true } }
    /// Stops for `colors`, 0…1; evenly spaced when nil.
    var locations: [CGFloat]? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard colors.count > 1 else { colors.first?.setFill(); bounds.fill(); return }
        let stops = locations ?? colors.indices.map { CGFloat($0) / CGFloat(colors.count - 1) }
        let gradient = stops.withUnsafeBufferPointer { buffer in
            NSGradient(colors: colors, atLocations: buffer.baseAddress, colorSpace: .sRGB)
        }
        // In a flipped view angle 90 runs top → bottom.
        gradient?.draw(in: bounds, angle: 90)
    }
}

/// `ItemCell.BackdropView`: the frosted pill behind badges (material .menu, within window, always active).
final class BackdropView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .menu
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var cornerRadius: CGFloat {
        get { layer?.cornerRadius ?? 0 }
        set { layer?.cornerRadius = newValue }
    }
}

/// An image that never takes clicks: they go to the view under it (a search field's magnifier, a peek's thumbnail).
final class PassiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// A flipped plain container with frame-based layout: a new size lays the subviews out again.
class FlippedView: NSView {
    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsLayout = true }
    }
}

enum Labels {
    /// A non-editable, non-selectable single-line label.
    static func make(_ text: String = "", font: NSFont, color: NSColor, lines: Int = 1,
                     alignment: NSTextAlignment = .natural, truncation: NSLineBreakMode = .byTruncatingTail) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.maximumNumberOfLines = lines
        label.lineBreakMode = lines == 1 ? truncation : .byWordWrapping
        label.cell?.truncatesLastVisibleLine = true
        label.cell?.lineBreakMode = lines == 1 ? truncation : .byWordWrapping
        label.isSelectable = false
        label.allowsDefaultTighteningForTruncation = false
        return label
    }

    /// Fitting height for `width` (multi-line labels).
    static func height(of label: NSTextField, width: CGFloat) -> CGFloat {
        label.preferredMaxLayoutWidth = width
        return ceil(label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height
                    ?? label.intrinsicContentSize.height)
    }
}

extension NSTextField {
    /// The size the label needs to draw without truncating: its cell size, which includes the cell's 2 pt side
    /// padding (on macOS 26 `intrinsicContentSize` leaves that padding out).
    var labelSize: NSSize {
        let size = cell?.cellSize ?? intrinsicContentSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }
}

extension NSView {
    /// `labelSize` for labels, `fittingSize` for everything else.
    var contentFittingSize: NSSize { (self as? NSTextField)?.labelSize ?? fittingSize }
}

enum Symbols {
    /// An SF Symbol (falling back to `questionmark.square`, ui-reference §1.3).
    static func image(_ name: String, config: NSImage.SymbolConfiguration? = nil, description: String? = nil) -> NSImage {
        let base = NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: description)!
        guard let config else { return base }
        return base.withSymbolConfiguration(config) ?? base
    }

    /// A filled circle of `color`, `side` points (pinboard dots in menus).
    static func dot(_ color: NSColor, side: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            return true
        }
        return image
    }

}

extension NSView {
    /// The edge facing up on screen, for popovers that open above the strip.
    var topEdge: NSRectEdge { isFlipped ? .minY : .maxY }

    /// A bitmap of the view as drawn now (drag images, offscreen renders).
    func snapshot() -> NSImage {
        let rep = bitmapImageRepForCachingDisplay(in: bounds) ?? NSBitmapImageRep()
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}
