import AppKit
import Carbon.HIToolbox
import SuperPasteCore

/// Why a recorded shortcut can't be used (behaviour.md §7.3).
public enum ShortcutConflict: Equatable {
    /// ⌥ without ⌘ or ⌃ before macOS 15.2.
    case optionOnly
    /// Another Super Paste shortcut or a pinboard has it.
    case inUse(String)
    case menuItem(String)
    case system

    public var message: String {
        switch self {
        case .optionOnly: Strings.Shortcuts.optionKey
        case .inUse(let name): Strings.Shortcuts.usedInApp(name)
        case .menuItem(let title): Strings.Shortcuts.usedInMenu(title)
        case .system: Strings.Shortcuts.usedInSystem
        }
    }
}

/// A system-wide keyboard shortcut (Carbon key code and modifiers).
public struct SystemHotkey: Hashable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32

    public init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode; self.carbonModifiers = carbonModifiers
    }
}

/// The checks a recorded shortcut goes through, in Paste's order with Super Paste's own shortcuts added: the Option
/// warning, the other shortcuts and pinboards, the menu items, then the system-wide shortcuts.
public struct ShortcutRules {
    /// The other shortcuts already assigned, by name (not the one being recorded).
    public var assigned: [(name: String, shortcut: Shortcut)]
    public var menuItems: [(title: String, shortcut: Shortcut)]
    public var systemHotkeys: Set<SystemHotkey>
    public var osVersion: OperatingSystemVersion

    static let carbonModifierMask = UInt32(cmdKey | optionKey | controlKey | shiftKey)

    public init(assigned: [(name: String, shortcut: Shortcut)], menuItems: [(title: String, shortcut: Shortcut)],
                systemHotkeys: Set<SystemHotkey>, osVersion: OperatingSystemVersion) {
        self.assigned = assigned; self.menuItems = menuItems; self.systemHotkeys = systemHotkeys; self.osVersion = osVersion
    }

    public func conflict(for shortcut: Shortcut) -> ShortcutConflict? {
        let modifiers = shortcut.modifiers
        let beforeOptionFix = (osVersion.majorVersion, osVersion.minorVersion) < (15, 2)
        if beforeOptionFix, modifiers.contains(.option), modifiers.isDisjoint(with: [.command, .control]) {
            return .optionOnly
        }
        if let other = assigned.first(where: { $0.shortcut == shortcut }) { return .inUse(other.name) }
        if let item = menuItems.first(where: { $0.shortcut == shortcut }) { return .menuItem(item.title) }
        let key = SystemHotkey(keyCode: shortcut.keyCode, carbonModifiers: shortcut.carbonModifiers & Self.carbonModifierMask)
        if systemHotkeys.contains(key) { return .system }
        return nil
    }
}

/// One of the shortcut settings, for the Shortcuts pane and the onboarding recorder.
enum ShortcutSetting: CaseIterable {
    case activation, pasteStack, nextPinboard, previousPinboard

    var key: Defaults.Key<Shortcut?> {
        switch self {
        case .activation: .activationShortcut
        case .pasteStack: .pasteStackShortcut
        case .nextPinboard: .nextPinboardShortcut
        case .previousPinboard: .previousPinboardShortcut
        }
    }

    /// One line under the title for a feature that isn't self-explanatory.
    var subtitle: String? {
        self == .pasteStack ? Strings.Shortcuts.pasteStackInfo : nil
    }

    var title: String {
        switch self {
        case .activation: Strings.Shortcuts.activate
        case .pasteStack: Strings.Shortcuts.pasteStack
        case .nextPinboard: Strings.Shortcuts.nextPinboard
        case .previousPinboard: Strings.Shortcuts.previousPinboard
        }
    }

    /// The live rules for recording this setting: the other settings and the pinboards' shortcuts, the app's menus
    /// and the system's symbolic hot keys.
    @MainActor var rules: ShortcutRules {
        var assigned = ShortcutSetting.allCases.filter { $0 != self }
            .compactMap { other in Defaults[other.key].map { (name: other.title, shortcut: $0) } }
        for pinboard in Services.store?.pinboards ?? [] {
            if let shortcut = pinboard.shortcut { assigned.append((Strings.Shortcuts.pinboard(pinboard.name), shortcut)) }
        }
        return ShortcutRules(assigned: assigned, menuItems: ShortcutSources.menuItems(NSApp?.mainMenu),
                             systemHotkeys: ShortcutSources.systemHotkeys(),
                             osVersion: ProcessInfo.processInfo.operatingSystemVersion)
    }

    /// The validator `ShortcutRecorder` calls: a reason to reject, or nil.
    @MainActor func validate(_ shortcut: Shortcut) -> String? { rules.conflict(for: shortcut)?.message }
}

/// Where the conflict checks get their data.
public enum ShortcutSources {
    /// Every menu item with a key equivalent, depth first.
    @MainActor public static func menuItems(_ menu: NSMenu?) -> [(title: String, shortcut: Shortcut)] {
        guard let menu else { return [] }
        return menu.items.flatMap { item -> [(title: String, shortcut: Shortcut)] in
            var found: [(title: String, shortcut: Shortcut)] = []
            if !item.keyEquivalent.isEmpty,
               let shortcut = Shortcut(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask) {
                found.append((item.title, shortcut))
            }
            return found + menuItems(item.submenu)
        }
    }

    /// The enabled system-wide shortcuts (Keyboard Shortcuts in System Settings).
    public static func systemHotkeys() -> Set<SystemHotkey> {
        var unmanaged: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&unmanaged) == noErr, let array = unmanaged?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        var result = Set<SystemHotkey>()
        for entry in array {
            guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
                  let code = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
                  let modifiers = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value
            else { continue }
            result.insert(SystemHotkey(keyCode: code, carbonModifiers: modifiers & ShortcutRules.carbonModifierMask))
        }
        return result
    }
}

/// The modifier picked for Quick Paste (with 1…9) or Plain Text mode (with Return). The two must differ.
public enum ModifierChoice: UInt, CaseIterable, Identifiable {
    case command, option, control, shift

    public init?(flags: UInt) {
        guard let match = Self.allCases.first(where: { $0.flags.rawValue == flags }) else { return nil }
        self = match
    }

    public var id: UInt { rawValue }

    public var flags: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }

    var label: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .shift: "⇧ Shift"
        }
    }

    /// Whether this choice may be picked while the other setting uses `other`.
    public func isAllowed(besides other: ModifierChoice?) -> Bool { self != other }
}
