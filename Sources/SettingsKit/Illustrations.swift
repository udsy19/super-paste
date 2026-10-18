import AppKit
import SwiftUI
import SuperPasteCore

// Super Paste's own illustrations, drawn in code (no image assets): the Paste Items choices, the direct-paste prompt
// and the System Settings hints on the permission screens.

private extension Color {
    static let artInk = Color(nsColor: SPColor.ink85)
    static let artLine = Color(nsColor: SPColor.ink10)
    static let artCard = Color(nsColor: SPColor.surface2)
    static let artBackdrop = Color(nsColor: SPColor.surface3)
}

/// A light backdrop with a tiny strip of cards along the bottom.
private func drawStrip(_ context: inout GraphicsContext, size: CGSize) -> [CGRect] {
    let height = size.height * 0.34
    let strip = CGRect(x: 0, y: size.height - height, width: size.width, height: height)
    context.fill(Path(strip), with: .color(Color(nsColor: SPColor.ink05)))
    let side = height * 0.68
    let gap = side * 0.22
    let headers: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPurple, .systemPink, .systemTeal]
    var cards: [CGRect] = []
    var x = gap
    var index = 0
    while x + side <= size.width - gap / 2 {
        let card = CGRect(x: x, y: strip.midY - side / 2, width: side, height: side)
        let radius = side * 0.12
        context.fill(Path(roundedRect: card, cornerRadius: radius), with: .color(.artCard))
        let header = CGRect(x: card.minX, y: card.minY, width: side, height: side * 0.28)
        context.fill(Path(roundedRect: header, cornerSize: CGSize(width: radius, height: radius)).intersection(Path(card)),
                     with: .color(Color(nsColor: headers[index % headers.count])))
        for line in 0..<2 {
            let y = card.minY + side * (0.45 + Double(line) * 0.2)
            let width = side * (line == 0 ? 0.7 : 0.45)
            context.fill(Path(roundedRect: CGRect(x: card.minX + side * 0.12, y: y, width: width, height: side * 0.08),
                              cornerRadius: side * 0.04), with: .color(.artLine))
        }
        cards.append(card)
        x += side + gap
        index += 1
    }
    return cards
}

/// A window sketch: traffic lights and a few lines of text with a caret.
private func drawWindow(_ context: inout GraphicsContext, in rect: CGRect) {
    let radius = rect.height * 0.12
    context.drawLayer { layer in
        layer.addFilter(.shadow(color: .black.opacity(0.18), radius: rect.height * 0.06, y: rect.height * 0.02))
        layer.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(.artCard))
    }
    let dot = rect.height * 0.09
    for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
        let center = CGPoint(x: rect.minX + dot * (1.4 + Double(index) * 1.5), y: rect.minY + dot * 1.4)
        context.fill(Path(ellipseIn: CGRect(x: center.x - dot / 2, y: center.y - dot / 2, width: dot, height: dot)),
                     with: .color(Color(nsColor: color)))
    }
    let lineHeight = rect.height * 0.07
    let widths = [0.72, 0.58, 0.34]
    for (index, fraction) in widths.enumerated() {
        let y = rect.minY + rect.height * (0.36 + Double(index) * 0.18)
        context.fill(Path(roundedRect: CGRect(x: rect.minX + rect.width * 0.1, y: y,
                                              width: rect.width * fraction * 0.85, height: lineHeight),
                          cornerRadius: lineHeight / 2), with: .color(.artLine))
    }
    let caretX = rect.minX + rect.width * 0.1 + rect.width * widths[2] * 0.85 + lineHeight
    let caretY = rect.minY + rect.height * 0.72
    context.fill(Path(CGRect(x: caretX, y: caretY - lineHeight * 0.6, width: max(1, lineHeight * 0.25), height: lineHeight * 2.2)),
                 with: .color(.accentColor))
}

/// Paste Items › To active app: an item travels from the strip into the window.
struct PasteToAppArt: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.artBackdrop))
            let cards = drawStrip(&context, size: size)
            let window = CGRect(x: size.width * 0.3, y: size.height * 0.08, width: size.width * 0.62, height: size.height * 0.46)
            drawWindow(&context, in: window)
            guard let card = cards.first else { return }
            var arrow = Path()
            let start = CGPoint(x: card.midX, y: card.minY - size.height * 0.03)
            let end = CGPoint(x: window.minX - size.width * 0.01, y: window.midY)
            arrow.move(to: start)
            arrow.addQuadCurve(to: end, control: CGPoint(x: start.x, y: end.y))
            let line = max(1.2, size.height * 0.03)
            context.stroke(arrow, with: .color(.accentColor), style: StrokeStyle(lineWidth: line, lineCap: .round))
            var head = Path()
            head.move(to: CGPoint(x: end.x - line * 2.2, y: end.y - line * 1.8))
            head.addLine(to: end)
            head.addLine(to: CGPoint(x: end.x - line * 2.2, y: end.y + line * 1.8))
            context.stroke(head, with: .color(.accentColor), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        }
    }
}

/// Paste Items › To clipboard: the "Copied" toast over the strip.
struct PasteToClipboardArt: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.artBackdrop))
            _ = drawStrip(&context, size: size)
            let side = size.height * 0.5
            let toast = CGRect(x: (size.width - side) / 2, y: size.height * 0.07, width: side, height: side)
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: .black.opacity(0.2), radius: side * 0.08, y: side * 0.03))
                layer.fill(Path(roundedRect: toast, cornerRadius: side * 0.2), with: .color(Color(nsColor: SPColor.surface2)))
            }
            var check = Path()
            check.move(to: CGPoint(x: toast.minX + side * 0.28, y: toast.minY + side * 0.52))
            check.addLine(to: CGPoint(x: toast.minX + side * 0.44, y: toast.minY + side * 0.68))
            check.addLine(to: CGPoint(x: toast.minX + side * 0.74, y: toast.minY + side * 0.34))
            context.stroke(check, with: .color(.artInk),
                           style: StrokeStyle(lineWidth: side * 0.09, lineCap: .round, lineJoin: .round))
        }
    }
}

/// A crop of System Settings over a warm wallpaper, pointing at Super Paste's row in a Privacy & Security list.
struct SystemSettingsArt: View {
    enum Control { case toggle, alwaysAllow }
    let paneTitle: String
    let control: Control

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(nsColor: NSColor(hex: "#F7A54A")), Color(nsColor: NSColor(hex: "#E8566C"))],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 0) {
                sidebar.frame(width: 120)
                Divider()
                pane
            }
            .frame(width: 380, height: 230, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .offset(x: 40, y: 26)
        }
        .frame(width: SPMetrics.Permissions.illustrationSize.width, height: SPMetrics.Permissions.illustrationSize.height)
        .clipShape(RoundedRectangle(cornerRadius: SPMetrics.Permissions.illustrationCornerRadius, style: .continuous))
        .environment(\.colorScheme, .light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                ForEach([NSColor.systemRed, .systemYellow, .systemGreen], id: \.self) { color in
                    Circle().fill(Color(nsColor: color)).frame(width: 8, height: 8)
                }
            }
            .padding(.bottom, 6)
            ForEach(0..<3, id: \.self) { index in
                sidebarRow(color: [NSColor.systemBlue, .systemGray, .systemOrange][index], width: [52, 40, 46][index])
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: .systemBlue)).frame(width: 12, height: 12)
                    .overlay(Image(systemName: "hand.raised.fill").font(.system(size: 7)).foregroundStyle(.white))
                Text(Strings.Permissions.privacyAndSecurity).font(.system(size: 9, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor))
            sidebarRow(color: .systemPurple, width: 38)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: SPColor.surface1))
    }

    private func sidebarRow(color: NSColor, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: color)).frame(width: 12, height: 12)
            Capsule().fill(Color(nsColor: SPColor.ink10)).frame(width: width, height: 5)
        }
        .padding(.horizontal, 5)
    }

    private var pane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                Text(paneTitle).font(.system(size: 11, weight: .bold))
            }
            VStack(spacing: 0) {
                appRow(icon: AnyView(AppIconView(size: 16)), name: Text(Strings.appName).font(.system(size: 10)),
                       highlighted: true)
                Divider().padding(.leading, 30)
                appRow(icon: AnyView(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .systemGray)).frame(width: 16, height: 16)),
                       name: Text(""), highlighted: false)
            }
            .background(RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: SPColor.ink02)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: SPColor.ink05)))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func appRow(icon: AnyView, name: Text, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            icon
            if highlighted { name } else {
                Capsule().fill(Color(nsColor: SPColor.ink10)).frame(width: 60, height: 5)
            }
            Spacer()
            switch control {
            case .toggle:
                Capsule().fill(highlighted ? Color.accentColor : Color(nsColor: SPColor.ink10))
                    .frame(width: 22, height: 13)
                    .overlay(Circle().fill(.white).padding(1.5).shadow(radius: 0.5),
                             alignment: highlighted ? .trailing : .leading)
                    .padding(3)
                    .overlay(highlighted ? Capsule().strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 2) : nil)
            case .alwaysAllow:
                HStack(spacing: 3) {
                    Text(highlighted ? Strings.Permissions.alwaysAllow : Strings.Permissions.ask).font(.system(size: 9))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 6, weight: .semibold))
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: SPColor.surface2)).shadow(radius: 0.5))
                .padding(3)
                .overlay(highlighted ? RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 2) : nil)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

/// A key on the keyboard, for teaching shortcuts.
struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, label.count > 1 ? 6 : 0)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(nsColor: SPColor.surface2))
                .shadow(color: .black.opacity(0.18), radius: 0.5, y: 1))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(nsColor: SPColor.ink10)))
    }
}

/// A shortcut as separate keys: "⇧⌘V" → ⇧ ⌘ V.
struct ShortcutKeys: View {
    let shortcut: Shortcut?

    var body: some View {
        HStack(spacing: 4) {
            if let shortcut {
                ForEach(Array(Self.keys(of: shortcut).enumerated()), id: \.offset) { _, key in Keycap(label: key) }
            } else {
                Text(Strings.Onboarding.notSet).font(.sp(.body)).foregroundStyle(.secondary)
            }
        }
    }

    /// The modifier glyphs one by one, then the key's name.
    static func keys(of shortcut: Shortcut) -> [String] {
        let name = Shortcut.keyName(shortcut.keyCode)
        return shortcut.displayString.dropLast(name.count).map(String.init) + [name]
    }
}
