import AppKit
import SuperPasteCore

/// `BackgroundEffectView(cornerRadius:)` (ui-reference §2.4): Liquid Glass (`NSGlassEffectView`) on macOS 26, an opaque
/// `windowBackgroundColor` fill on macOS 14 and 15. Put content in `contentView`.
final class BackgroundEffectView: FlippedView {
    /// Where subviews go: the glass's content view, or a plain view on the flat fill.
    let contentView: NSView = FlippedView()
    private var effect: NSView?
    private let flat = FillView()

    /// Offscreen renders can't capture Liquid Glass (the window server composites it), so they draw a translucent
    /// stand-in instead. Only the render self-test sets this.
    nonisolated(unsafe) static var usesGlassStandIn = false

    init(style: SPStyle, cornerRadius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        contentView.autoresizingMask = [.width, .height]
        if style == .glass, !Self.usesGlassStandIn, let glass = Self.makeGlass(cornerRadius: cornerRadius, content: contentView) {
            glass.autoresizingMask = [.width, .height]
            addSubview(glass)
            effect = glass
        } else {
            flat.fillColor = style == .glass ? SPColor.windowBackground.withAlphaComponent(0.72) : .windowBackgroundColor
            if style == .glass {
                flat.borderColor = NSColor.white.withAlphaComponent(0.5)
                flat.borderWidth = 1
            }
            flat.cornerRadius = cornerRadius
            flat.cornerCurve = .continuous
            flat.clips = true
            flat.autoresizingMask = [.width, .height]
            flat.addSubview(contentView)
            addSubview(flat)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        effect?.frame = bounds
        flat.frame = bounds
        if effect == nil { contentView.frame = flat.bounds }
    }

    private static func makeGlass(cornerRadius: CGFloat, content: NSView) -> NSView? {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return glass
        }
        #endif
        return nil
    }
}
