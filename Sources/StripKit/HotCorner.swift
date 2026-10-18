import AppKit
import Combine
import SuperPasteCore

// The hot corner: rest the pointer in a screen corner and a small peek of the latest items slides out; click it to
// open the strip. The geometry and timing are plain values (`HotCornerDetector`), the monitor drives them from
// global mouse events (no Accessibility needed for mouse-moved monitors), and `PeekPanel` is the tab itself.

/// Where the pointer is in relation to the watched corner, step by step.
struct HotCornerDetector: Equatable {
    /// How long the pointer rests in the corner before the peek shows.
    static let dwell: TimeInterval = 0.15
    /// How close to the corner's point counts, in points.
    static let tolerance: CGFloat = 2

    enum Event: Equatable {
        case none
        /// The pointer reached the corner zone; `rested` follows if it stays `dwell` long.
        case entered
        /// The pointer has rested in the corner: show the peek on `screen`.
        case rested(screen: NSRect)
        /// The pointer left the corner zone.
        case left
    }

    var corner: HotCorner
    private(set) var insideSince: Date?
    private(set) var rested = false

    init(corner: HotCorner) { self.corner = corner }

    /// The screen (as its frame) whose `corner` is under `point`: a screen containing the point, with the point
    /// within `tolerance` of that corner, where no other screen continues past either edge (a corner two screens
    /// share isn't a corner of the desktop; the pointer crosses it).
    static func screen(withCorner corner: HotCorner, at point: NSPoint, screens: [NSRect],
                       tolerance: CGFloat = tolerance) -> NSRect? {
        guard corner != .off, let frame = screens.first(where: { contains($0, point) }) else { return nil }
        let x = corner == .bottomLeft || corner == .topLeft ? frame.minX : frame.maxX
        let y = corner == .bottomLeft || corner == .bottomRight ? frame.minY : frame.maxY
        guard abs(point.x - x) <= tolerance, abs(point.y - y) <= tolerance else { return nil }
        let beyondX = NSPoint(x: x + (x == frame.minX ? -1 : 1), y: min(max(point.y, frame.minY), frame.maxY))
        let beyondY = NSPoint(x: min(max(point.x, frame.minX), frame.maxX), y: y + (y == frame.minY ? -1 : 1))
        let continues = screens.contains { other in
            other != frame && (contains(other, beyondX) || contains(other, beyondY))
        }
        return continues ? nil : frame
    }

    /// Edges included: the pointer sits on a screen's edge pixel when it is pushed into a corner.
    private static func contains(_ rect: NSRect, _ point: NSPoint) -> Bool {
        point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }

    /// Feeds a pointer position. `dragging` (a mouse button held) never counts as resting. Call again at
    /// `insideSince + dwell` with the same point to get `rested`.
    mutating func update(point: NSPoint, screens: [NSRect], now: Date, dragging: Bool = false) -> Event {
        guard !dragging, let screen = Self.screen(withCorner: corner, at: point, screens: screens) else {
            let wasInside = insideSince != nil
            insideSince = nil
            rested = false
            return wasInside ? .left : .none
        }
        guard let since = insideSince else {
            insideSince = now
            return .entered
        }
        // A hair under the dwell counts: a timer set for the dwell fires at it, and date arithmetic rounds.
        guard !rested, now.timeIntervalSince(since) >= Self.dwell - 0.001 else { return .none }
        rested = true
        return .rested(screen: screen)
    }

    /// Forgets the pointer (the corner changed, the monitor stopped).
    mutating func reset() {
        insideSince = nil
        rested = false
    }
}

/// Where the peek sits for a corner on a screen, and where it slides in from.
enum PeekLayout {
    static let size = NSSize(width: 220, height: 70)
    static let margin: CGFloat = 8

    static func frame(for corner: HotCorner, on screen: NSRect) -> NSRect {
        let x = corner == .bottomLeft || corner == .topLeft ? screen.minX + margin : screen.maxX - margin - size.width
        let y = corner == .bottomLeft || corner == .bottomRight ? screen.minY + margin : screen.maxY - margin - size.height
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    /// The resting frame pushed off the screen's side edge, where the slide starts.
    static func hiddenFrame(for corner: HotCorner, on screen: NSRect) -> NSRect {
        var frame = frame(for: corner, on: screen)
        frame.origin.x += corner == .bottomLeft || corner == .topLeft ? -(size.width + margin) : size.width + margin
        return frame
    }
}

/// Watches the pointer for the corner in Settings and shows the peek (`PeekPanel`) when it rests there.
@MainActor
final class HotCornerMonitor {
    /// The peek stays this long after the pointer leaves it and the corner.
    static let lingerDelay: TimeInterval = 0.6

    private var detector: HotCornerDetector
    private var monitors: [Any] = []
    private var dwellTimer: Timer?
    private var lingerTimer: Timer?
    private var dragging = false
    private var cancellables: Set<AnyCancellable> = []
    private let peek = PeekPanelController()

    init() {
        detector = HotCornerDetector(corner: Self.effectiveCorner)
        Defaults.publisher(.hotCorner)
            .dropFirst()
            .sink { [weak self] _ in self?.cornerChanged() }
            .store(in: &cancellables)
    }

    /// The corner to watch now: the setting, unless macOS's own Hot Corners use that corner.
    static var effectiveCorner: HotCorner {
        HotCornerPolicy.effective(Defaults[.hotCorner], systemAction: HotCornerPolicy.systemAction(for:))
    }

    func start() {
        guard monitors.isEmpty else { return }
        let types: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseUp, .rightMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: types, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: types, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }) { monitors.append(local) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        dwellTimer?.invalidate()
        lingerTimer?.invalidate()
        detector.reset()
        peek.hide(animated: false)
    }

    private func cornerChanged() {
        detector = HotCornerDetector(corner: Self.effectiveCorner)
        dwellTimer?.invalidate()
        peek.hide(animated: false)
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDragged, .rightMouseDragged: dragging = true
        case .leftMouseUp, .rightMouseUp: dragging = false
        default: break
        }
        pointerMoved(NSEvent.mouseLocation, now: Date())
    }

    private func pointerMoved(_ point: NSPoint, now: Date) {
        guard detector.corner != .off else { return }
        let screens = NSScreen.screens.map(\.frame)
        switch detector.update(point: point, screens: screens, now: now, dragging: dragging) {
        case .entered:
            dwellTimer?.invalidate()
            dwellTimer = Timer.scheduledTimer(withTimeInterval: HotCornerDetector.dwell, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.pointerMoved(NSEvent.mouseLocation, now: Date()) }
            }
        case .rested(let screen):
            if Self.mayShowPeek { peek.show(corner: detector.corner, on: screen) }
        case .left, .none:
            break
        }
        // Over the corner or the peek: it stays. Elsewhere: it goes after the linger delay.
        if peek.isShowing {
            if detector.insideSince != nil || peek.contains(point) {
                lingerTimer?.invalidate()
                lingerTimer = nil
            } else if lingerTimer == nil {
                lingerTimer = Timer.scheduledTimer(withTimeInterval: Self.lingerDelay, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.lingerTimer = nil
                        self?.peek.hide(animated: true)
                    }
                }
            }
        }
    }

    /// Not while the strip is up, and not over a full-screen app (its space is the app's; hot corners are off there).
    private static var mayShowPeek: Bool {
        if Services.strip?.isVisible == true { return false }
        return !FullScreenCheck.isFrontmostAppFullScreen()
    }
}

/// Whether the frontmost app has a window covering a whole screen (a full-screen space), from the window list.
enum FullScreenCheck {
    @MainActor static func isFrontmostAppFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(),
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let sizes = NSScreen.screens.map(\.frame.size)
        return isFullScreen(windows: windows, pid: app.processIdentifier, screenSizes: sizes)
    }

    /// A window of `pid` at the normal layer whose bounds are the size of a screen.
    static func isFullScreen(windows: [[String: Any]], pid: pid_t, screenSizes: [NSSize]) -> Bool {
        windows.contains { info in
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid, (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            return screenSizes.contains { abs($0.width - width) < 1 && abs($0.height - height) < 1 }
        }
    }
}

// MARK: - Peek panel

/// The peek: a 220 × 70 glass tab with the three most recent cards in miniature and the activation shortcut. It
/// never takes keyboard focus (a borderless panel that can't become key); a click opens the strip.
@MainActor
final class PeekPanelController {
    private var panel: NSPanel?
    private var view: PeekView?
    private var corner: HotCorner = .off
    private var screen: NSRect = .zero
    private(set) var isShowing = false

    func show(corner: HotCorner, on screen: NSRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        self.corner = corner
        self.screen = screen
        guard !isShowing else { return }
        view?.load(Services.store, style: .current)
        isShowing = true
        let frame = PeekLayout.frame(for: corner, on: screen)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(reduceMotion ? frame : PeekLayout.hiddenFrame(for: corner, on: screen), display: false)
        panel.alphaValue = reduceMotion ? 0 : 1
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SPMotion.peekShowDuration
            context.timingFunction = SPMotion.stripShowTiming
            if reduceMotion { panel.animator().alphaValue = 1 } else { panel.animator().setFrame(frame, display: true) }
        }
    }

    func hide(animated: Bool) {
        guard isShowing, let panel else { return }
        isShowing = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated else { panel.orderOut(nil); return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = SPMotion.peekHideDuration
            context.timingFunction = SPMotion.stripHideTiming
            if reduceMotion { panel.animator().alphaValue = 0 }
            else { panel.animator().setFrame(PeekLayout.hiddenFrame(for: self.corner, on: self.screen), display: true) }
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isShowing else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        })
    }

    /// Whether a screen point is over the peek (with a little slack around it).
    func contains(_ point: NSPoint) -> Bool {
        guard isShowing, let panel else { return false }
        return NSMouseInRect(point, panel.frame.insetBy(dx: -PeekLayout.margin, dy: -PeekLayout.margin), false)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: PeekLayout.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = SPMetrics.Strip.windowLevel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let view = PeekView(style: .current)
        view.onClick = { [weak self] in
            self?.hide(animated: false)
            Services.strip?.show(nil)
        }
        panel.contentView = view
        self.view = view
        return panel
    }
}

/// The peek's content: three miniature cards (header band in the app's colour, a line of the content) and "⇧⌘V".
final class PeekView: FlippedView {
    var onClick: (() -> Void)?
    private let background: BackgroundEffectView
    private var cards: [PeekCardView] = []
    private let shortcut = Labels.make(font: SPFont.style(.caption1, weight: .semibold), color: SPColor.ink50, alignment: .center)
    private let empty = Labels.make(L10n.historyEmpty, font: SPFont.style(.caption1), color: SPColor.ink50)

    static let cardSide: CGFloat = 46
    static let inset: CGFloat = 12
    static let spacing: CGFloat = 8

    init(style: SPStyle) {
        background = BackgroundEffectView(style: style, cornerRadius: SPMetrics.Peek.cornerRadius)
        super.init(frame: NSRect(origin: .zero, size: PeekLayout.size))
        addSubview(background)
        background.contentView.addSubview(shortcut)
        background.contentView.addSubview(empty)
        empty.isHidden = true
        shortcut.stringValue = Defaults[.activationShortcut]?.displayString ?? ""
        toolTip = "Open Super Paste"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open Super Paste")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the three most recent history items.
    func load(_ store: ItemStoring?, style: SPStyle) {
        let items = store?.search(.empty, in: .history, limit: 3, offset: 0) ?? []
        cards.forEach { $0.removeFromSuperview() }
        cards = items.map { item in
            let card = PeekCardView(item: item, style: style)
            background.contentView.addSubview(card)
            return card
        }
        empty.isHidden = !items.isEmpty
        shortcut.stringValue = Defaults[.activationShortcut]?.displayString ?? ""
        needsLayout = true
    }

    override func layout() {
        super.layout()
        background.frame = bounds
        let side = Self.cardSide
        var x = Self.inset
        for card in cards {
            card.frame = NSRect(x: x, y: round((bounds.height - side) / 2), width: side, height: side)
            x += side + Self.spacing
        }
        let labelSize = shortcut.labelSize
        shortcut.frame = NSRect(x: bounds.width - Self.inset - labelSize.width, y: round((bounds.height - labelSize.height) / 2),
                                width: labelSize.width, height: labelSize.height)
        let emptySize = empty.labelSize
        empty.frame = NSRect(x: Self.inset, y: round((bounds.height - emptySize.height) / 2),
                             width: max(0, shortcut.frame.minX - Self.spacing - Self.inset), height: emptySize.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { onClick?() }
}

/// One miniature card: the header band in the item's colour over a thumbnail or the first words.
final class PeekCardView: FillView {
    private let band = FillView()
    private let text = Labels.make(font: SPFont.style(.caption2), color: SPColor.ink85, lines: 3)
    private let picture = PassiveImageView()
    static let bandHeight: CGFloat = 8

    init(item: ClipItem, style: SPStyle) {
        super.init(frame: .zero)
        let metrics = SPMetrics(style: style)
        fillColor = item.kind == .color ? ItemPresentation.colorHex(item).map { NSColor(hex: $0) } : SPColor.cardBody
        cornerRadius = SPMetrics.Peek.cardCornerRadius
        cornerCurve = metrics.cardCornerCurve
        clips = true
        band.fillColor = AppIconProvider.shared.headerColor(for: item, scope: .history, pinboards: [], style: style)
        picture.imageScaling = .scaleProportionallyUpOrDown
        picture.image = item.kind == .image || item.kind == .link ? ItemAssets.shared.cardImage(for: item) : nil
        text.stringValue = picture.image == nil && item.kind != .color ? ItemPresentation.summary(item) : ""
        text.lineBreakMode = .byTruncatingTail
        [picture, text, band].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        band.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.bandHeight)
        picture.frame = bounds
        text.frame = NSRect(x: 4, y: Self.bandHeight + 2, width: bounds.width - 8, height: bounds.height - Self.bandHeight - 4)
    }
}
