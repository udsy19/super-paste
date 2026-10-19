import AppKit
import SwiftUI
import SuperPasteCore

// Building blocks shared by the Settings panes, onboarding and the permission screens (ui-reference §11, §12, §14,
// §15).

// MARK: - Style

private struct SPStyleKey: EnvironmentKey {
    static let defaultValue = SPStyle.current
}

extension EnvironmentValues {
    /// The look to draw. The snapshot renderer sets `.classic`, since glass doesn't render off screen.
    var spStyle: SPStyle {
        get { self[SPStyleKey.self] }
        set { self[SPStyleKey.self] = newValue }
    }
}

extension Font {
    /// A system text style, optionally re-weighted at the same size (`SPFont.style`).
    static func sp(_ style: NSFont.TextStyle, _ weight: NSFont.Weight? = nil) -> Font {
        Font(SPFont.style(style, weight: weight))
    }
}

/// The app icon. The snapshot renderer has no app bundle, so it can supply one.
@MainActor
enum AppIcon {
    static var override: NSImage?
    static var image: NSImage { override ?? NSApp?.applicationIconImage ?? NSImage() }
}

struct AppIconView: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: AppIcon.image).resizable().interpolation(.high).frame(width: size, height: size)
    }
}

// MARK: - Buttons (ui-reference §15)

enum SPButtonKind { case filled, gray, plain }
enum SPButtonSize { case medium, large }

/// Paste's SwiftUI button: glass on macOS 26, a radius-10 rounded rectangle on 14 and 15. Label 13 medium.
struct SPButton: View {
    let title: String
    var kind: SPButtonKind = .filled
    var size: SPButtonSize = .large
    var symbol: String? = nil
    /// Fills the available width.
    var stretch = false
    let action: () -> Void
    @Environment(\.spStyle) private var style

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .frame(maxWidth: stretch ? .infinity : nil)
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, size == .large ? 20 : 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        if #available(macOS 26, *), style == .glass {
            switch kind {
            case .filled: button.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
            case .gray: button.buttonStyle(.glass).buttonBorderShape(.capsule)
            case .plain: button.buttonStyle(.plain)
            }
        } else {
            button.buttonStyle(ClassicButtonStyle(kind: kind))
        }
    }
}

private struct ClassicButtonStyle: ButtonStyle {
    let kind: SPButtonKind

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return configuration.label
            .foregroundStyle(kind == .filled ? Color.white.opacity(0.9) : Color.primary)
            .background(RoundedRectangle(cornerRadius: SPMetrics.classicButtonRadius, style: .continuous).fill(fill))
            .scaleEffect(pressed ? 0.99 : 1)
            .brightness(pressed ? -0.1 : 0)
            .opacity(pressed ? 0.5 : 1)
    }

    private var fill: Color {
        switch kind {
        case .filled: Color(nsColor: .systemBlue)
        case .gray: Color(nsColor: SPColor.fill)
        case .plain: .clear
        }
    }
}

// MARK: - Settings chrome (ui-reference §11)

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .withinWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// A pane's 52 pt title bar: the title in title3 medium, 30 from the leading edge, on the window-background material.
struct PaneHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.sp(.title3, .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, SPMetrics.Settings.titleLeading)
            .frame(height: SPMetrics.Settings.titleBarHeight)
            .background(VisualEffect(material: .windowBackground))
    }
}

private let groupBoxFill = SPColor.dynamic(
    "settingsGroupBox", light: .black.withAlphaComponent(SPMetrics.Settings.groupBoxFillAlpha),
    dark: .white.withAlphaComponent(SPMetrics.Settings.groupBoxFillAlpha))

/// A titled group: title (body semibold) and subtitle (subheadline, secondary) above a radius-12 box filled with
/// ink85 at alpha 0.03, padded 10.
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: SPMetrics.Settings.groupBoxSpacing) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).font(.sp(.body, .semibold)) }
                    if let subtitle {
                        Text(subtitle).font(.sp(.subheadline)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, SPMetrics.Settings.groupBoxPadding)
            }
            VStack(alignment: .leading, spacing: SPMetrics.Settings.groupBoxSpacing) { content }
                .padding(SPMetrics.Settings.groupBoxPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: SPMetrics.Settings.groupBoxCornerRadius, style: .continuous)
                    .fill(Color(nsColor: groupBoxFill)))
        }
    }
}

/// `SettingsRowView(title, subtitle, content)`: the labels on the leading side (body; the description in callout,
/// secondary), the control on the trailing side.
struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    var subtitleColor: Color = .secondary
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.sp(.body))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.sp(.callout)).foregroundStyle(subtitleColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            accessory
        }
    }
}

/// A row with a switch.
struct ToggleRow: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
    }
}

// MARK: - Panels and alerts

/// Small AppKit dialogs the panes share (confirmations go through `Alerts.confirm`).
@MainActor
enum Dialogs {
    /// A text prompt with a placeholder and custom buttons; nil when cancelled or left empty.
    static func ask(_ title: String, message: String, placeholder: String, confirm: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = placeholder
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: Strings.Action.cancel)
        alert.window.initialFirstResponder = field
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Writes text to the general pasteboard. A secret also gets the nspasteboard.org concealed and transient
    /// markers, so clipboard managers (Super Paste included) don't keep it.
    static func copy(_ text: String, secret: Bool) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if secret {
            for type in [PasteboardType.concealed, PasteboardType.transient] {
                pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            }
        }
    }
}

/// "5 minutes ago", for sync and MCP status lines.
func relativeDate(_ date: Date, now: Date = Date()) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return now.timeIntervalSince(date) < 60 ? Strings.justNow : formatter.localizedString(for: date, relativeTo: now)
}
