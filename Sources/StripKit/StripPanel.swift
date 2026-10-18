import AppKit
import SuperPasteCore

/// `MainWindow` (ui-reference §2.1): a borderless, non-activating, resizable NSPanel at `NSMainMenuWindowLevel`, not
/// movable, no shadow, that can become key without activating Super Paste (so the frontmost app stays the paste
/// target).
final class StripPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 800, height: SPMetrics.Strip.defaultHeight),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: true)
        level = SPMetrics.Strip.windowLevel
        isMovable = false
        hasShadow = false
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        autorecalculatesKeyViewLoop = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The 10 pt strip along the top edge that resizes the panel between 252 and 412 pt, anchored to the bottom; a
/// double-click returns to 332 (ui-reference §2.5).
final class ResizeHandleView: NSView {
    var onResize: ((CGFloat) -> Void)?
    var onEnd: ((CGFloat) -> Void)?
    var onReset: (() -> Void)?
    private var startY: CGFloat = 0
    private var startHeight: CGFloat = 0

    private static let cursor: NSCursor = {
        let name = ["_", "window", "Resize", "North", "South", "Cursor"].joined()
        let selector = NSSelectorFromString(name)
        if NSCursor.responds(to: selector), let cursor = NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor {
            return cursor
        }
        return .resizeUpDown
    }()

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.cursor)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onReset?(); return }
        startY = NSEvent.mouseLocation.y
        startHeight = window?.frame.height ?? SPMetrics.Strip.defaultHeight
    }

    override func mouseDragged(with event: NSEvent) {
        onResize?(SPMetrics.Strip.clampedHeight(startHeight + NSEvent.mouseLocation.y - startY))
    }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount < 2 else { return }
        onEnd?(SPMetrics.Strip.clampedHeight(startHeight + NSEvent.mouseLocation.y - startY))
    }
}

/// `MainView`: the background slab (inset 8 on glass), the toolbar, the card row, the empty-state label and the
/// resize handle. It slides as one piece when the strip shows and hides.
final class StripRootView: FlippedView {
    let style: SPStyle
    let background: BackgroundEffectView
    let toolbar: ToolbarView
    let scrollView = CardScrollView(frame: .zero)
    let cards = CardStripView(frame: .zero)
    let emptyLabel = Labels.make(font: .systemFont(ofSize: SPMetrics.EmptyState.fontSize), color: SPColor.ink26,
                                 alignment: .center)
    let resizeHandle = ResizeHandleView()
    var keyHandler: ((NSEvent) -> Bool)?

    init(style: SPStyle) {
        self.style = style
        let metrics = SPMetrics(style: style)
        background = BackgroundEffectView(style: style, cornerRadius: metrics.panelCornerRadius)
        toolbar = ToolbarView(style: style)
        super.init(frame: .zero)
        wantsLayer = true
        scrollView.documentView = cards
        emptyLabel.isHidden = true
        addSubview(background)
        background.contentView.addSubview(toolbar)
        background.contentView.addSubview(scrollView)
        background.contentView.addSubview(emptyLabel)
        addSubview(resizeHandle)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let metrics = SPMetrics(style: style)
        let insets = metrics.panelInsets
        background.frame = NSRect(x: insets.left, y: insets.top, width: max(0, bounds.width - insets.left - insets.right),
                                  height: max(0, bounds.height - insets.top - insets.bottom))
        let slab = background.bounds
        toolbar.frame = NSRect(x: 0, y: 0, width: slab.width, height: SPMetrics.Strip.toolbarHeight)
        // The collection ends at MainView's bottom − 8 on glass, which is the slab's bottom.
        let collectionHeight = max(0, slab.height - SPMetrics.Strip.toolbarHeight)
        scrollView.frame = NSRect(x: 0, y: SPMetrics.Strip.toolbarHeight, width: slab.width, height: collectionHeight)
        let labelSize = emptyLabel.labelSize
        emptyLabel.frame = NSRect(x: 0, y: round(scrollView.frame.midY - labelSize.height / 2 + SPMetrics.EmptyState.verticalOffset),
                                  width: slab.width, height: labelSize.height)
        resizeHandle.frame = NSRect(x: 0, y: 0, width: bounds.width, height: SPMetrics.Strip.resizeHandleHeight)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) != true { super.keyDown(with: event) }
    }
}
