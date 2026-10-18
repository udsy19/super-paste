import AppKit
import SwiftUI
import SuperPasteCore

/// Shortcuts (behaviour.md §7.3): the four recorders, the Quick Paste and Plain Text modifiers, and the reset.
struct ShortcutsPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                ForEach(Array(ShortcutSetting.allCases.enumerated()), id: \.offset) { index, setting in
                    if index > 0 { Divider() }
                    SettingsRow(title: setting.title) { ShortcutField(setting: setting) }
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

/// Core's recorder bound to one shortcut setting, checked against the conflict rules. It keeps the recorder's own
/// width (150), which doesn't shrink to onboarding's 120.
struct ShortcutField: View {
    let setting: ShortcutSetting
    @Default private var shortcut: Shortcut?

    init(setting: ShortcutSetting) {
        self.setting = setting
        _shortcut = Default(setting.key)
    }

    var body: some View {
        ShortcutRecorder(shortcut: $shortcut, validator: { setting.validate($0) })
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
