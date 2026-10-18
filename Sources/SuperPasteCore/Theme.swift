import AppKit
import QuartzCore

// Design tokens from docs/specs/ui-reference.md, shared so every module draws with the same numbers. Values that
// differ between macOS 26 (Liquid Glass) and macOS 14/15 are instance members of `SPMetrics`, chosen by `SPStyle`;
// the rest are static. Section numbers below refer to ui-reference.md.

/// The visual generation to draw: `.glass` on macOS 26 and later, `.classic` on macOS 14 and 15.
public enum SPStyle: String, CaseIterable, Sendable {
    case glass, classic

    public static func forSystem(majorVersion: Int) -> SPStyle { majorVersion >= 26 ? .glass : .classic }
    public static let current = forSystem(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
}

// MARK: - Colours (§1.1, §3.5)

public extension NSColor {
    /// "#RRGGBB" or "#RRGGBBAA" (the "#" is optional); malformed input gives magenta so it shows.
    convenience init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else {
            self.init(srgbRed: 1, green: 0, blue: 1, alpha: 1); return
        }
        let rgba = digits.count == 6 ? value << 8 | 0xFF : value
        self.init(srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255, green: CGFloat((rgba >> 16) & 0xFF) / 255,
                  blue: CGFloat((rgba >> 8) & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }

    /// "#RRGGBB" in sRGB (alpha dropped).
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

/// Named colours. Light/dark pairs resolve per appearance (dark for any dark or high-contrast-dark appearance).
public enum SPColor {
    public static func dynamic(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name("superpaste." + name)) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func ink(_ name: String, _ light: CGFloat, _ dark: CGFloat) -> NSColor {
        dynamic(name, light: .black.withAlphaComponent(light), dark: .white.withAlphaComponent(dark))
    }

    /// Primary ink: toolbar icons (glass), search text, compact header title.
    public static let ink85 = ink("ink85", 0.85, 0.85)
    /// Secondary ink: footers, classic toolbar tint.
    public static let ink50 = ink("ink50", 0.50, 0.55)
    /// Colour-picker ring, sidecar close button, empty-state text.
    public static let ink26 = ink("ink26", 0.26, 0.26)
    /// Search field, selected tab or button, editor border; pressed state uses it at alpha 0.15.
    public static let ink10 = ink("ink10", 0.10, 0.10)
    /// Hover background for tabs and buttons, button borders.
    public static let ink05 = ink("ink05", 0.05, 0.05)
    /// Onboarding setup card.
    public static let ink02 = ink("ink02", 0.02, 0.02)

    public static let gray = dynamic("gray", light: NSColor(hex: "#8E8E93"), dark: NSColor(hex: "#98989D"))
    public static let yellow = NSColor(hex: "#F2B600")
    public static let surface1 = dynamic("surface1", light: NSColor(hex: "#F2F2F7"), dark: NSColor(hex: "#1C1C1E"))
    public static let surface2 = dynamic("surface2", light: NSColor(hex: "#FFFFFF"), dark: NSColor(hex: "#2C2C2E"))
    public static let surface3 = dynamic("surface3", light: NSColor(hex: "#F2F2F7"), dark: NSColor(hex: "#2C2C2E"))
    /// Link cards and text cards without a background of their own.
    public static let linkBackground = dynamic("linkBackground", light: .white, dark: NSColor(hex: "#141414"))
    public static let windowBackground = dynamic("windowBackground", light: .white, dark: .windowBackgroundColor)
    public static let fill = dynamic("fill", light: NSColor(hex: "#767680").withAlphaComponent(0.12),
                                     dark: NSColor(hex: "#767680").withAlphaComponent(0.24))
    /// Selection ring, primary buttons, selected filter items.
    public static var accent: NSColor { .controlAccentColor }
    /// Card body.
    public static var cardBody: NSColor { .textBackgroundColor }

    /// A pinboard's colour: system colours on glass, the stored hex codes on classic.
    public static func pinboard(_ color: PinboardColor, style: SPStyle = .current) -> NSColor {
        switch style {
        case .glass:
            switch color {
            case .red: .systemRed
            case .orange: .systemOrange
            case .yellow: yellow
            case .green: .systemGreen
            case .blue: .systemBlue
            case .purple: .systemPurple
            case .pink: .systemPink
            case .gray: gray
            }
        case .classic: NSColor(hex: pinboardHex(color))
        }
    }

    /// The stored hex code of a pinboard colour (classic look, sync, MCP).
    public static func pinboardHex(_ color: PinboardColor) -> String {
        switch color {
        case .red: "#F0554D"
        case .orange: "#FA9214"
        case .yellow: "#FAB700"
        case .green: "#52CC64"
        case .blue: "#62A9F5"
        case .purple: "#B663E0"
        case .pink: "#FA506F"
        case .gray: "#8F8F93"
        }
    }

    /// A card header band for an app colour ("#RRGGBB"; nil → gray). #62A9F5 and #F0554D become systemBlue and
    /// systemRed (§4.3).
    public static func header(appColorHex hex: String?) -> NSColor {
        switch hex?.uppercased() {
        case nil: gray
        case "#62A9F5"?: .systemBlue
        case "#F0554D"?: .systemRed
        case let hex?: NSColor(hex: hex)
        }
    }
}

// MARK: - Type (§1.2)

public enum SPFont {
    /// A system text style (title2 17, title3 15, headline 13 bold, subheadline 11, body 13, callout 12, footnote 10,
    /// caption1 10 on a default Mac), optionally re-weighted at the same size.
    public static func style(_ style: NSFont.TextStyle, weight: NSFont.Weight? = nil) -> NSFont {
        let font = NSFont.preferredFont(forTextStyle: style)
        guard let weight else { return font }
        return .systemFont(ofSize: font.pointSize, weight: weight)
    }
}

// MARK: - Card size classes (§2.6, §4.2)

/// Drives most card metrics; chosen from the card's side length.
public enum CardSizeClass: String, CaseIterable, Sendable {
    case large, regular, small, compact

    /// ≥ 280 large, 240–280 regular, 200–240 small, < 200 compact.
    public init(cardSide: CGFloat) {
        switch cardSide {
        case 280...: self = .large
        case 240..<280: self = .regular
        case 200..<240: self = .small
        default: self = .compact
        }
    }

    /// Height of the source-app icon that bleeds off the header's right edge.
    public var appIconHeight: CGFloat {
        switch self {
        case .large: 84
        case .regular: 80
        case .small: 76
        case .compact: 20
        }
    }

    /// Title/date stack x offset from the header's trailing edge while the app icon shows (−12 without it in the
    /// three larger classes).
    public var labelsXOffset: CGFloat {
        switch self {
        case .large: -70
        case .regular: -66
        case .small: -62
        case .compact: -30
        }
    }
}

// MARK: - Metrics

public struct ShadowSpec: Equatable, Sendable {
    public var alpha: CGFloat
    public var offset: CGSize
    public var blur: CGFloat
}

/// Sizes in points. `SPMetrics.current` matches the running macOS; build one with another style to preview it.
public struct SPMetrics: Sendable {
    public let style: SPStyle

    public init(style: SPStyle) { self.style = style }

    public static let current = SPMetrics(style: .current)

    private var glass: Bool { style == .glass }

    // MARK: Strip (§2.1–2.5)

    public enum Strip {
        public static let defaultHeight: CGFloat = 332
        public static let heightRange: ClosedRange<CGFloat> = 252...412
        /// Above the Dock: `NSMainMenuWindowLevel`.
        public static let windowLevel = NSWindow.Level(rawValue: 24)
        public static let toolbarHeight: CGFloat = 60
        /// The drag strip along the top edge; a double-click returns to `defaultHeight`.
        public static let resizeHandleHeight: CGFloat = 10

        public static func clampedHeight(_ height: CGFloat) -> CGFloat {
            min(max(height, heightRange.lowerBound), heightRange.upperBound)
        }
    }

    /// The panel spans the screen's full width at the bottom; on glass the visible slab is inset inside it.
    public var panelInsets: NSEdgeInsets { glass ? NSEdgeInsets(top: 0, left: 8, bottom: 8, right: 8) : NSEdgeInsets() }
    public var panelCornerRadius: CGFloat { glass ? 26 : 0 }
    public var collectionBottomInset: CGFloat { glass ? 8 : 0 }

    public func collectionHeight(panelHeight: CGFloat) -> CGFloat {
        panelHeight - Strip.toolbarHeight - collectionBottomInset
    }

    /// Cards are square: the collection height less its top and bottom content insets.
    public func cardSide(panelHeight: CGFloat) -> CGFloat {
        collectionHeight(panelHeight: panelHeight) - Cards.contentInsets.top - Cards.contentInsets.bottom
    }

    public func sizeClass(panelHeight: CGFloat) -> CardSizeClass { CardSizeClass(cardSide: cardSide(panelHeight: panelHeight)) }

    // MARK: Cards (§2.6, §4)

    public enum Cards {
        public static let contentInsets = NSEdgeInsets(top: 8, left: 24, bottom: 24, right: 24)
        public static let spacing: CGFloat = 24
        /// The selection ring sits this far outside the body.
        public static let selectionRingInset: CGFloat = 4
        public static let textInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        /// The "N characters" footer: distance from the bottom, the fade above it and the opaque strip under it.
        public static let footerBottom: CGFloat = 10
        public static let footerFadeHeight: CGFloat = 32
        public static let footerOpaqueHeight: CGFloat = 18
        /// Header gradient (gradient style): black @ 0.4 → clear.
        public static let headerGradientHeight: CGFloat = 64
        /// Quick-paste number and size pills.
        public static let badgeHeight: CGFloat = 18
        public static let badgeCornerRadius: CGFloat = 9
        public static let badgePadding: CGFloat = 6
        public static let badgeSpacing: CGFloat = 4
        public static let badgeInset: CGFloat = 8
        /// Quick Paste numbers the first nine visible cards.
        public static let quickPasteCount = 9
        public static let linkFaviconSize: CGFloat = 42
        public static let pinboardIconSize: CGFloat = 12
        public static let headerLabelsInset: CGFloat = 12
        public static let lockSize: CGFloat = 56
    }

    public var cardCornerRadius: CGFloat { glass ? 16 : 10 }
    public var cardCornerCurve: CALayerCornerCurve { glass ? .continuous : .circular }
    public var selectionRingRadius: CGFloat { cardCornerRadius + Cards.selectionRingInset }
    public var cardShadow: ShadowSpec {
        glass ? ShadowSpec(alpha: 0.08, offset: .zero, blur: 2) : ShadowSpec(alpha: 0.10, offset: CGSize(width: 0, height: -1), blur: 2)
    }

    /// Header height, which is also where the content starts.
    public func headerHeight(_ sizeClass: CardSizeClass) -> CGFloat {
        switch sizeClass {
        case .large: 56
        case .regular: 52
        case .small: 48
        case .compact: glass ? 36 : 34
        }
    }

    public var linkFaviconRadius: CGFloat { glass ? 12 : 10 }
    /// `exclamationmark.triangle` on unknown cards.
    public var unknownSymbolSize: CGFloat { glass ? 32 : 48 }

    // MARK: Toolbar, search, tabs (§3)

    public enum Toolbar {
        public static let edgeInset: CGFloat = 16
        public static let itemSpacing: CGFloat = 8
        public static let largeButtonSize: CGFloat = 32
        public static let regularButtonHeight: CGFloat = 22
        public static let regularButtonMinWidth: CGFloat = 32
        public static let regularButtonPadding: CGFloat = 8
        public static let regularButtonSpacing: CGFloat = 4
        /// While searching the field centres and grows to at least this width and this share of the toolbar.
        public static let activeSearchMinWidth: CGFloat = 400
        public static let activeSearchMinFraction: CGFloat = 0.25
        public static let searchIconInset: CGFloat = 8
        public static let searchTextHeight: CGFloat = 20
        public static let searchClearButtonSize: CGFloat = 16
        public static let filterTokenPadding = NSEdgeInsets(top: 2, left: 6, bottom: 2, right: 6)
        public static let filterTokenIconSize: CGFloat = 12
        public static let filterTokenSpacing: CGFloat = 2
        public static let suggestionsCornerRadius: CGFloat = 10
        public static let suggestionsRowPadding = NSEdgeInsets(top: 3, left: 8, bottom: 3, right: 8)
        public static let suggestionsIconSize: CGFloat = 18
        public static let suggestionsSpacing: CGFloat = 7
        public static let suggestionsListInset: CGFloat = 5
        public static let suggestionsScreenMargin: CGFloat = 6
    }

    /// Toolbar buttons: capsules on glass; 6 (large) or 5 (regular) on classic.
    public func toolbarButtonRadius(height: CGFloat, large: Bool) -> CGFloat { glass ? height / 2 : (large ? 6 : 5) }
    public func searchFieldRadius(height: CGFloat) -> CGFloat { glass ? height / 2 : 6 }
    /// Gap between the "+" button and the "…" menu.
    public var toolbarMenuGap: CGFloat { glass ? 8 : 16 }

    public enum TabBar {
        public static let verticalInset: CGFloat = 10
        public static let chipHeight: CGFloat = 28
        public static let chipSpacing: CGFloat = 8
        public static let chipIconInset: CGFloat = 8
        public static let chipLabelGap: CGFloat = 4
        public static let labelMaxWidth: CGFloat = 200
        public static let pinboardIconBox: CGFloat = 16
        public static let pinboardGlyphSize: CGFloat = 12
        public static let historyIconBox: CGFloat = 18
        /// Edge shadows appear once the tabs have scrolled this far.
        public static let edgeShadowThreshold: CGFloat = 7
        public static let colorRowHeight: CGFloat = 26
        public static let colorCellSize: CGFloat = 22
        public static let colorSwatchSize: CGFloat = 14
    }

    public func tabChipRadius(height: CGFloat) -> CGFloat { glass ? height / 2 : 6 }
    public var historyTabSymbolSize: CGFloat { glass ? 13 : 15 }

    // MARK: Sidecar (§5)

    public enum Sidecar {
        public static let width: CGFloat = 200
        public static let minSide: CGFloat = 80
    }

    public var sidecarCornerRadius: CGFloat { glass ? 16 : 10 }

    // MARK: Windows (§6–§14)

    public enum Preview {
        public static let headerHeight: CGFloat = 38
        public static let minWindowSize = NSSize(width: 380, height: 240)
        /// A detached preview starts at a quarter of the screen plus this.
        public static let initialScreenFraction: CGFloat = 0.25
        public static let initialExtra = NSSize(width: 10, height: 76)
        public static let contentBorderRadius: CGFloat = 5
        public static let contentBorderWidth: CGFloat = 0.5
    }

    public enum CreateItem {
        public static let minWindowSize = NSSize(width: 500, height: 360)
    }

    /// The OSD toast ("Copied", "Paused").
    public enum HUD {
        public static let size: CGFloat = 200
        public static let cornerRadius: CGFloat = 20
        public static let symbolSize: CGFloat = 86
        /// Centre-bottom of the screen plus this.
        public static let bottomOffset: CGFloat = 140
        public static let windowLevel = NSWindow.Level(rawValue: 1000)
    }

    /// The hot-corner peek (behaviour notes: hot corner).
    public enum Peek {
        public static let cornerRadius: CGFloat = 16
        public static let cardCornerRadius: CGFloat = 8
    }

    public enum PasteStack {
        public static let windowSize = NSSize(width: 322, height: 372)
        /// `NSStatusWindowLevel`.
        public static let windowLevel = NSWindow.Level(rawValue: 25)
        public static let rowHeight: CGFloat = 44
        public static let rowIconSize: CGFloat = 20
        public static let headerButtonSize: CGFloat = 16
        public static let headerInset: CGFloat = 8
    }

    public enum StatusItem {
        public static let iconSize: CGFloat = 22
        public static let animationFrames = 17
    }

    public enum Settings {
        public static let sidebarWidth: CGFloat = 200
        public static let contentWidth: CGFloat = 440
        public static let titleBarHeight: CGFloat = 52
        public static let titleLeading: CGFloat = 30
        public static let contentPadding: CGFloat = 20
        public static let groupBoxCornerRadius: CGFloat = 12
        public static let groupBoxPadding: CGFloat = 10
        public static let groupBoxSpacing: CGFloat = 10
        /// Group box fill: `ink85` at this alpha.
        public static let groupBoxFillAlpha: CGFloat = 0.03
        public static let sidebarSymbolSize: CGFloat = 14
    }

    public enum Onboarding {
        public static let windowSize = NSSize(width: 544, height: 652)
        public static let introIconSize: CGFloat = 160
        public static let setupIconSize: CGFloat = 80
        public static let titleFontSize: CGFloat = 22
        public static let cardWidth: CGFloat = 400
        public static let cardCornerRadius: CGFloat = 10
        public static let rowPadding = NSSize(width: 12, height: 10)
        public static let shortcutRecorderWidth: CGFloat = 120
    }

    public enum Permissions {
        public static let windowSize = NSSize(width: 544, height: 680)
        public static let iconSize: CGFloat = 80
        public static let illustrationSize = NSSize(width: 400, height: 200)
        public static let illustrationCornerRadius: CGFloat = 10
        public static let grantedSymbolSize: CGFloat = 64
    }

    public enum EmptyState {
        public static let fontSize: CGFloat = 26
        public static let verticalOffset: CGFloat = -17
    }

    /// SwiftUI buttons: rounded rectangles of this radius on classic (glass uses the system glass styles).
    public static let classicButtonRadius: CGFloat = 10
}

// MARK: - Motion (§2.3, §3.3, §4.7, §8, §10, §12)

public enum SPMotion {
    /// Strip slides up its full height.
    public static let stripShowDuration: TimeInterval = 0.15
    public static var stripShowTiming: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1.0) }
    /// Strip slides down its full height.
    public static let stripHideDuration: TimeInterval = 0.20
    public static var stripHideTiming: CAMediaTimingFunction { CAMediaTimingFunction(name: .easeInEaseOut) }
    /// After the strip closes, its closed-state reset (search, scroll) runs this much later.
    public static let closedStateResetDelay: TimeInterval = 10
    /// The hot-corner peek slides out of its corner and back (a fade with Reduce Motion).
    public static let peekShowDuration: TimeInterval = 0.18
    public static let peekHideDuration: TimeInterval = 0.15

    /// Scroll-to-selection lasts the time since the previous move, capped here, and is instant below the minimum.
    public static let scrollToSelectionMax: TimeInterval = 0.25
    public static let scrollToSelectionInstantBelow: TimeInterval = 0.1
    /// Scroll-to-selection and size-class changes.
    public static var standardTiming: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1) }
    public static let sizeClassChangeDuration: TimeInterval = 0.2

    /// A filter token bouncing into the search field.
    public static let filterTokenBounceDuration: TimeInterval = 0.28
    public static let filterTokenBounceScales: [CGFloat] = [1, 1.16, 0.98, 1]
    public static let filterTokenBounceKeyTimes: [CGFloat] = [0, 0.35, 0.7, 1]

    /// Pressing a selected card waits this long before a drag may start; the pointer must move this far.
    public static let dragDelay: TimeInterval = 0.45
    public static let dragThreshold: CGFloat = 3
    public static let dragImageAlpha: CGFloat = 0.8
    public static let reorderMarkerWidth: CGFloat = 4
    public static let reorderMarkerRadius: CGFloat = 2
    /// Auto-scroll while dragging within this distance of an edge, at (edge − d) / edge × step points per tick.
    public static let autoScrollEdge: CGFloat = 30
    public static let autoScrollStep: CGFloat = 15

    /// The HUD stays, then fades out (ease-out).
    public static let hudHoldDuration: TimeInterval = 1.0
    public static let hudFadeDuration: TimeInterval = 0.5

    public static let onboardingPageDuration: TimeInterval = 0.3
    /// Menu bar icon animation on capture.
    public static let statusItemFrameDuration: TimeInterval = 1.0 / 48
    /// Card relative dates refresh this often.
    public static let dateRefreshInterval: TimeInterval = 30
}
