import AppKit
import SuperPasteCore

extension Defaults.Keys {
    /// Sidecar notification cards the user closed.
    static let stripDismissedNotifications = Key<[String]>("stripKit.dismissedNotifications", default: [])
}

/// In-app notification cards at the start of the card row (behaviour.md §11, ui-reference §5): Enable Direct Paste
/// while Accessibility is missing, Open at Login while it's off. Each can be closed for good.
@MainActor
final class SidecarModel {
    struct Note: Equatable {
        var id: String
        var symbol: String
        var title: String
        var text: String
        var actionTitle: String
    }

    private(set) var notes: [Note] = []
    private var views: [SidecarCardView] = []

    static let enableDirectPaste = Note(id: "enable-direct-paste", symbol: "doc.on.clipboard", title: L10n.enableDirectPasteTitle,
                                        text: L10n.enableDirectPasteText, actionTitle: L10n.enable)
    static let openAtLogin = Note(id: "open-at-login", symbol: "power", title: L10n.openAtLoginTitle,
                                  text: L10n.openAtLoginText, actionTitle: L10n.enable)

    func refresh() {
        let dismissed = Set(Defaults[.stripDismissedNotifications])
        var notes: [Note] = []
        if Defaults[.isDirectPasteEnabled], !Permissions.isAccessibilityTrusted { notes.append(Self.enableDirectPaste) }
        if !Defaults[.openAtLogin] { notes.append(Self.openAtLogin) }
        self.notes = notes.filter { !dismissed.contains($0.id) }
    }

    /// Card width: 200 when taller than 200, otherwise square; at least 80 (ui-reference §5).
    static func cardWidth(height: CGFloat) -> CGFloat {
        max(SPMetrics.Sidecar.minSide, height > SPMetrics.Sidecar.width ? SPMetrics.Sidecar.width : height)
    }

    /// The column's width (0 without notes).
    func width(cardSide: CGFloat) -> CGFloat {
        guard !notes.isEmpty else { return 0 }
        let w = Self.cardWidth(height: cardSide)
        return CGFloat(notes.count) * w + CGFloat(notes.count - 1) * SPMetrics.Cards.spacing
    }

    func install(in cards: CardStripView, geometry: StripGeometry, onChange: @escaping () -> Void) {
        views.forEach { $0.removeFromSuperview() }
        let side = geometry.cardSide
        let width = Self.cardWidth(height: side)
        views = notes.enumerated().map { index, note in
            let view = SidecarCardView(note: note, style: geometry.style, compact: CardSizeClass(cardSide: side) == .compact)
            view.frame = NSRect(x: SPMetrics.Cards.contentInsets.left + CGFloat(index) * (width + SPMetrics.Cards.spacing),
                                y: SPMetrics.Cards.contentInsets.top, width: width, height: side)
            view.onAction = { [weak self] in self?.run(note) }
            view.onClose = { [weak self] in
                Defaults[.stripDismissedNotifications].append(note.id)
                self?.refresh()
                onChange()
            }
            cards.addSubview(view)
            return view
        }
    }

    private func run(_ note: Note) {
        switch note.id {
        case Self.enableDirectPaste.id: Services.permissions?.showAccessibilityAccess()
        default: Services.settings?.show(pane: .general)
        }
    }
}

/// A sidecar card: icon, title, description, a capsule button and a close button (ui-reference §5 base cell).
final class SidecarCardView: FlippedView {
    var onAction: (() -> Void)?
    var onClose: (() -> Void)?
    private let compact: Bool
    private let plate = FillView()
    private let icon = NSImageView()
    private let title: NSTextField
    private let text: NSTextField
    private let button: ToolbarButton
    private let close: ToolbarButton

    init(note: SidecarModel.Note, style: SPStyle, compact: Bool) {
        self.compact = compact
        title = Labels.make(note.title, font: compact ? SPFont.style(.body, weight: .semibold) : SPFont.style(.title3, weight: .semibold),
                            color: .labelColor, lines: 2)
        text = Labels.make(note.text, font: SPFont.style(.callout, weight: .medium), color: .secondaryLabelColor, lines: 4)
        button = ToolbarButton(size: .regular, style: style, title: note.actionTitle)
        close = ToolbarButton(size: .regular, style: style, symbol: "xmark")
        super.init(frame: .zero)
        let metrics = SPMetrics(style: style)
        plate.fillColor = SPColor.linkBackground
        plate.cornerRadius = metrics.sidecarCornerRadius
        plate.cornerCurve = metrics.cardCornerCurve
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(metrics.cardShadow.alpha)
        shadow.shadowOffset = metrics.cardShadow.offset
        shadow.shadowBlurRadius = metrics.cardShadow.blur
        plate.shadow = shadow
        icon.image = Symbols.image(note.symbol, config: .init(pointSize: compact ? 15 : 22, weight: .regular))
        icon.contentTintColor = .controlAccentColor
        icon.imageScaling = .scaleNone
        button.action = { [weak self] _ in self?.onAction?() }
        close.symbolTint = style == .glass ? SPColor.ink26 : SPColor.ink50
        close.action = { [weak self] _ in self?.onClose?() }
        [plate, icon, title, text, button, close].forEach(addSubview)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        plate.frame = bounds
        let inset: CGFloat = compact ? 10 : 12
        let iconSide: CGFloat = compact ? 20 : 28
        let gap: CGFloat = compact ? 4 : 8
        icon.frame = NSRect(x: inset, y: inset, width: iconSide, height: iconSide)
        let closeSize = close.fittingSize
        close.frame = NSRect(x: bounds.width - 6 - closeSize.width, y: 6, width: closeSize.width, height: closeSize.height)
        let width = max(0, bounds.width - 2 * inset)
        let titleHeight = Labels.height(of: title, width: width)
        title.frame = NSRect(x: inset, y: icon.frame.maxY + gap, width: width, height: titleHeight)
        let buttonSize = button.fittingSize
        button.frame = NSRect(x: inset, y: bounds.height - inset - buttonSize.height, width: buttonSize.width, height: buttonSize.height)
        let textHeight = min(Labels.height(of: text, width: width), max(0, button.frame.minY - 4 - title.frame.maxY - 2))
        text.frame = NSRect(x: inset, y: title.frame.maxY + 2, width: width, height: textHeight)
        text.isHidden = textHeight < 12
    }
}
