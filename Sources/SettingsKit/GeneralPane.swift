import AppKit
import SwiftUI
import SuperPasteCore

/// General (behaviour.md §7.1): login item, menu bar icon, sounds, where pasting goes, plain text, Keep History,
/// Erase History, the hot corner, strip height.
struct GeneralPane: View {
    @ObservedObject var accessibility: PermissionMonitor
    @Default(.openAtLogin) private var openAtLogin
    @Default(.isStatusItemEnabled) private var showInMenuBar
    @Default(.isSoundEffectsEnabled) private var soundEffects
    @Default(.isDirectPasteEnabled) private var directPaste
    @Default(.isPasteAsPlainTextEnabled) private var plainText
    @Default(.stripHeight) private var stripHeight
    @Default(.hotCorner) private var hotCorner

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                ToggleRow(title: Strings.General.openAtLogin,
                          isOn: Binding(get: { openAtLogin }, set: { LoginItem.set($0) }))
                Divider()
                ToggleRow(title: Strings.General.showInMenuBar, isOn: $showInMenuBar)
                Divider()
                ToggleRow(title: Strings.General.soundEffects, isOn: $soundEffects)
            }
            SettingsGroup(title: Strings.General.pasteItems) {
                PasteItemsPicker(directPaste: $directPaste)
                if directPaste && !accessibility.flow.isGranted {
                    Divider()
                    AccessibilityRequestRow()
                }
                Divider()
                Toggle(Strings.General.plainText, isOn: $plainText).toggleStyle(.checkbox).font(.sp(.body))
            }
            SettingsGroup(title: Strings.General.keepHistory, subtitle: Strings.General.keepHistoryInfo) {
                HistorySlider()
                Divider()
                HStack {
                    Spacer()
                    Button(Strings.General.eraseHistory, action: eraseHistory)
                }
            }
            SettingsGroup {
                SettingsRow(title: Strings.General.hotCorner, subtitle: Strings.General.hotCornerInfo) {
                    Picker("", selection: $hotCorner) {
                        ForEach(HotCorner.allCases, id: \.self) { corner in Text(corner.title).tag(corner) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                if HotCornerPolicy.systemUsesCorner(HotCornerPolicy.systemAction(for: hotCorner)) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                        Text(Strings.General.hotCornerTaken).font(.sp(.callout)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider()
                SettingsRow(title: Strings.General.stripHeight, subtitle: Strings.General.stripHeightInfo) {
                    Slider(value: Binding(get: { stripHeight },
                                          set: { stripHeight = Double(SPMetrics.Strip.clampedHeight(CGFloat($0))) }),
                           in: Double(SPMetrics.Strip.heightRange.lowerBound)...Double(SPMetrics.Strip.heightRange.upperBound))
                        .controlSize(.small)
                        .frame(width: 160)
                }
            }
        }
    }

    private func eraseHistory() {
        guard Alerts.confirm(Strings.General.eraseTitle, info: Strings.General.eraseText,
                             confirmTitle: Strings.Action.erase, destructive: true) else { return }
        do { try Services.store?.eraseHistory() } catch { Alerts.error(Strings.General.eraseTitle, error) }
    }
}

/// "Paste Items": two choices with an illustration each, the selected one's description below (ui-reference §11:
/// illustrations 64 tall with radius 8, selection background radius 5 with padding 6).
struct PasteItemsPicker: View {
    @Binding var directPaste: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                option(Strings.General.toActiveApp, selected: directPaste) { directPaste = true } art: {
                    PasteToAppArt()
                }
                option(Strings.General.toClipboard, selected: !directPaste) { directPaste = false } art: {
                    PasteToClipboardArt()
                }
            }
            .frame(maxWidth: .infinity)
            Text(directPaste ? Strings.General.toActiveAppInfo : Strings.General.toClipboardInfo)
                .font(.sp(.subheadline)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func option<Art: View>(_ title: String, selected: Bool, select: @escaping () -> Void,
                                   @ViewBuilder art: () -> Art) -> some View {
        Button(action: select) {
            VStack(spacing: 6) {
                art()
                    .frame(width: 96, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color(nsColor: .separatorColor),
                                      lineWidth: selected ? 3 : 1))
                Text(title)
                    .font(.sp(.callout))
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.clear))
            }
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Shown while direct paste is on but Accessibility isn't granted: opens the "Paste to Any App" screen.
struct AccessibilityRequestRow: View {
    var body: some View {
        Button {
            Services.permissions?.showAccessibilityAccess()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.white, .red)
                Text(Strings.General.allowAccessibility).font(.sp(.body))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
