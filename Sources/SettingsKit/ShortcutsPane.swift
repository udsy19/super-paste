import AppKit
import Combine
import SwiftUI
import SuperPasteCore

/// Shortcuts (behaviour.md §7.3): the four recorders, the Quick Paste and Plain Text modifiers, and the reset. A
/// recorder whose shortcut another app holds (`HotkeyCenter.unavailable`) gets a warning row under it.
struct ShortcutsPane: View {
    @ObservedObject private var conflicts = HotkeyConflicts.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                ForEach(Array(ShortcutSetting.allCases.enumerated()), id: \.offset) { index, setting in
                    if index > 0 { Divider() }
                    SettingsRow(title: setting.title) { ShortcutField(setting: setting) }
                    if let shortcut = Defaults[setting.key], conflicts.unavailable.contains(shortcut) {
                        HotkeyConflictRow(shortcut: shortcut)
                    }
                }
            }
            SettingsGroup {
                SettingsRow(title: Strings.Shortcuts.quickPaste) {
                    ModifierPicker(key: .quickPasteModifierFlags, other: .plainTextModifierFlags,
                                   suffix: Strings.Shortcuts.quickPasteSuffix)
                }
                Divider()
                SettingsRow(title: Strings.Shortcuts.plainText) {
                    ModifierPicker(key: .plainTextModifierFlags, other: .quickPasteModifierFlags,
                                   suffix: Strings.Shortcuts.plainTextSuffix)
                }
            }
            HStack {
                Spacer()
                Button(Strings.Shortcuts.reset, action: Self.resetAll)
            }
        }
    }

    static func resetAll() {
        guard Alerts.confirm(Strings.Shortcuts.resetConfirmation, confirmTitle: Strings.Action.reset) else { return }
        ShortcutSetting.allCases.forEach { Defaults.reset($0.key) }
        Defaults.reset(.quickPasteModifierFlags)
        Defaults.reset(.plainTextModifierFlags)
    }
}

/// Core's recorder bound to one shortcut setting, checked against the conflict rules; 150 wide in Settings, 120 in
/// onboarding's Quick Start card (ui-reference §12).
struct ShortcutField: View {
    let setting: ShortcutSetting
    var width: CGFloat = 150
    @Default private var shortcut: Shortcut?

    init(setting: ShortcutSetting, width: CGFloat = 150) {
        self.setting = setting
        self.width = width
        _shortcut = Default(setting.key)
    }

    var body: some View {
        ShortcutRecorder(shortcut: $shortcut, validator: { setting.validate($0) }, width: width)
            .fixedSize()
    }
}

/// A modifier popup; the other modifier setting's choice isn't offered, so the two never match.
struct ModifierPicker: View {
    @Default private var flags: UInt
    @Default private var other: UInt
    let suffix: String

    init(key: Defaults.Key<UInt>, other: Defaults.Key<UInt>, suffix: String) {
        _flags = Default(key)
        _other = Default(other)
        self.suffix = suffix
    }

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(get: { ModifierChoice(flags: flags) },
                                          set: { if let choice = $0 { flags = choice.flags.rawValue } })) {
                ForEach(ModifierChoice.allCases.filter { $0.isAllowed(besides: ModifierChoice(flags: other)) }) { choice in
                    Text(choice.label).tag(Optional(choice))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .frame(width: 120, alignment: .trailing)
            Text(suffix).font(.sp(.body)).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
        }
    }
}

/// The shortcuts `HotkeyCenter` couldn't register, for the Shortcuts pane and the sidebar badge.
@MainActor
final class HotkeyConflicts: ObservableObject {
    static let shared = HotkeyConflicts()
    @Published private(set) var unavailable: Set<Shortcut> = []
    private var cancellable: AnyCancellable?

    private init() {
        cancellable = HotkeyCenter.shared.unavailableChanges.sink { [weak self] in self?.unavailable = $0 }
    }
}

/// "⇧⌘V is used by another app" with what to do about it, under the recorder it concerns.
struct HotkeyConflictRow: View {
    let shortcut: Shortcut

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: .systemOrange))
            VStack(alignment: .leading, spacing: 2) {
                Text(HotkeyConflict.title(shortcut)).font(.sp(.body, .medium))
                Text(Strings.Shortcuts.conflictInfo).font(.sp(.callout)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }
}
