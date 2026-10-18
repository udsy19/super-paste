import AppKit
import Carbon.HIToolbox
import SuperPasteCore

/// What a key press in the strip does (behaviour.md §4.4, ui-reference §4.6, §4.8).
enum StripCommand: Equatable {
    case move(Int, extend: Bool)
    case first(extend: Bool)
    case last(extend: Bool)
    case page(Int, extend: Bool)
    case selectAll
    case paste(plainText: Bool)
    /// Quick Paste: the Nth (1…9) visible card; with the plain-text modifiers too, as plain text.
    case quickPaste(Int, plainText: Bool)
    case preview
    case copy
    case edit
    case rename
    case open
    case delete
    /// "Show in …" for the first list holding the item (⌘G).
    case showInList
    case undo
    case redo
    case filters
    case previousList
    case nextList
    case newTextItem
    case settings
    case cancel
    /// Tab / ⇧Tab: between the search field and the cards.
    case switchFocus(backward: Bool)
}

/// What a click on a card does (behaviour.md §4.5): a single click only selects (⇧ range, ⌘ toggle); a double click
/// pastes that card, as plain text while the plain-text modifiers are held.
enum CardMouseAction: Equatable {
    case select(SelectionMode)
    case paste(plainText: Bool)
}

enum StripMouseMap {
    static func action(clickCount: Int, modifiers: NSEvent.ModifierFlags, bindings: StripKeyBindings) -> CardMouseAction {
        let mods = modifiers.intersection([.command, .option, .control, .shift])
        if clickCount >= 2 {
            let plain = bindings.plainTextModifiers.intersection([.command, .option, .control, .shift])
            return .paste(plainText: !plain.isEmpty && mods == plain)
        }
        if mods.contains(.shift) { return .select(.range) }
        if mods.contains(.command) { return .select(.toggle) }
        return .select(.single)
    }

    /// Which badges show for the modifiers held (ui-reference §4.4): the numbers while the quick-paste modifiers are
    /// down, the plain-text mark while the plain-text ones are, both while both are.
    static func badges(held modifiers: NSEvent.ModifierFlags, bindings: StripKeyBindings) -> (numbers: Bool, plainText: Bool) {
        let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
        let held = modifiers.intersection(relevant)
        let quick = bindings.quickPasteModifiers.intersection(relevant)
        let plain = bindings.plainTextModifiers.intersection(relevant)
        guard !held.isEmpty, held.isSubset(of: quick.union(plain)) else { return (false, false) }
        return (!quick.isEmpty && held.isSuperset(of: quick), !plain.isEmpty && held.isSuperset(of: plain))
    }
}

/// A key press, reduced to what the mapping needs.
struct KeyStroke: Equatable {
    var keyCode: Int
    var modifiers: NSEvent.ModifierFlags
    /// `charactersIgnoringModifiers`.
    var characters: String

    init(keyCode: Int, modifiers: NSEvent.ModifierFlags, characters: String = "") {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection([.command, .option, .control, .shift])
        self.characters = characters
    }

    init(event: NSEvent) {
        self.init(keyCode: Int(event.keyCode), modifiers: event.modifierFlags,
                  characters: event.charactersIgnoringModifiers ?? "")
    }
}

/// The user's configurable bindings (Settings › Shortcuts).
struct StripKeyBindings: Equatable {
    var quickPasteModifiers: NSEvent.ModifierFlags
    var plainTextModifiers: NSEvent.ModifierFlags
    var nextList: Shortcut?
    var previousList: Shortcut?

    static let defaults = StripKeyBindings(
        quickPasteModifiers: NSEvent.ModifierFlags(rawValue: Defaults.Keys.quickPasteModifierFlags.defaultValue),
        plainTextModifiers: NSEvent.ModifierFlags(rawValue: Defaults.Keys.plainTextModifierFlags.defaultValue),
        nextList: Defaults.Keys.nextPinboardShortcut.defaultValue,
        previousList: Defaults.Keys.previousPinboardShortcut.defaultValue)

    static var current: StripKeyBindings {
        StripKeyBindings(quickPasteModifiers: NSEvent.ModifierFlags(rawValue: Defaults[.quickPasteModifierFlags]),
                         plainTextModifiers: NSEvent.ModifierFlags(rawValue: Defaults[.plainTextModifierFlags]),
                         nextList: Defaults[.nextPinboardShortcut], previousList: Defaults[.previousPinboardShortcut])
    }
}

enum StripKeyMap {
    private static let relevant: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// The command for a key press while the cards have focus; nil lets it through (typing starts a search).
    static func command(for key: KeyStroke, bindings: StripKeyBindings) -> StripCommand? {
        let mods = key.modifiers.intersection(relevant)
        let shift = mods == .shift

        // Configurable bindings first, so they win over the fixed keys they may share.
        if let next = bindings.nextList, Int(next.keyCode) == key.keyCode, next.modifiers.intersection(relevant) == mods {
            return .nextList
        }
        if let previous = bindings.previousList, Int(previous.keyCode) == key.keyCode,
           previous.modifiers.intersection(relevant) == mods {
            return .previousList
        }
        if let n = quickPasteNumber(key), !bindings.quickPasteModifiers.isEmpty {
            let quick = bindings.quickPasteModifiers.intersection(relevant)
            let plain = bindings.plainTextModifiers.intersection(relevant)
            if mods == quick { return .quickPaste(n, plainText: false) }
            if !plain.isEmpty, !plain.isSubset(of: quick), mods == quick.union(plain) { return .quickPaste(n, plainText: true) }
        }

        switch key.keyCode {
        case kVK_LeftArrow where mods.isEmpty || shift: return .move(-1, extend: shift)
        case kVK_RightArrow where mods.isEmpty || shift: return .move(1, extend: shift)
        case kVK_Home where mods.isEmpty || shift: return .first(extend: shift)
        case kVK_End where mods.isEmpty || shift: return .last(extend: shift)
        case kVK_PageUp where mods.isEmpty || shift: return .page(-1, extend: shift)
        case kVK_PageDown where mods.isEmpty || shift: return .page(1, extend: shift)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if mods.isEmpty { return .paste(plainText: false) }
            if !bindings.plainTextModifiers.isEmpty, mods == bindings.plainTextModifiers.intersection(relevant) {
                return .paste(plainText: true)
            }
            return nil
        case kVK_Space where mods.isEmpty: return .preview
        case kVK_Delete, kVK_ForwardDelete:
            return mods.isEmpty || mods == .command ? .delete : nil
        case kVK_Escape where mods.isEmpty: return .cancel
        case kVK_Tab where mods.isEmpty || shift: return .switchFocus(backward: shift)
        default: break
        }

        guard mods.contains(.command) else { return nil }
        switch (key.characters.lowercased(), mods) {
        case ("a", .command): return .selectAll
        case ("c", .command): return .copy
        case ("e", .command): return .edit
        case ("r", .command): return .rename
        case ("o", .command): return .open
        case ("g", .command): return .showInList
        case ("f", .command): return .filters
        case ("n", .command): return .newTextItem
        case (",", .command): return .settings
        case ("z", .command): return .undo
        case ("z", [.command, .shift]): return .redo
        default: return nil
        }
    }

    /// 1…9 from the main row or the keypad.
    static func quickPasteNumber(_ key: KeyStroke) -> Int? {
        let row = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        let pad = [kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4, kVK_ANSI_Keypad5,
                   kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9]
        if let i = row.firstIndex(of: key.keyCode) ?? pad.firstIndex(of: key.keyCode) { return i + 1 }
        return nil
    }

    /// Whether a key press should start a search: printable text without ⌘ or ⌃.
    static func startsSearch(_ key: KeyStroke) -> Bool {
        guard key.modifiers.isDisjoint(with: [.command, .control]) else { return false }
        guard let scalar = key.characters.unicodeScalars.first else { return false }
        if (0xF700...0xF8FF).contains(scalar.value) { return false }  // function keys, arrows
        return !CharacterSet.controlCharacters.contains(scalar) && key.keyCode != kVK_Space
    }
}
