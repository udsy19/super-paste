import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI
import SuperPasteCore
import SettingsKit
@testable import StripKit

// Owned by StripKit. Pure logic (layout math, selection, key and mouse mapping, dates, header colours, suggestions) and
// the strip driven against an in-memory store. Set STRIPKIT_RENDER_DIR to also write offscreen PNG renders there.
func registerStripKitTests() {
    SelfTest.cases.append(("StripKit.install", { MainActor.assumeIsolated { stripInstall() } }))
    SelfTest.cases.append(("StripKit.geometry", { MainActor.assumeIsolated { stripGeometry() } }))
    SelfTest.cases.append(("StripKit.headerLayout", { MainActor.assumeIsolated { stripHeaderLayout() } }))
    SelfTest.cases.append(("StripKit.selection", { stripSelection() }))
    SelfTest.cases.append(("StripKit.keyMap", { stripKeyMap() }))
    SelfTest.cases.append(("StripKit.mouseMap", { stripMouseMap() }))
    SelfTest.cases.append(("StripKit.dates", { stripDates() }))
    SelfTest.cases.append(("StripKit.headerColor", { MainActor.assumeIsolated { stripHeaderColor() } }))
    SelfTest.cases.append(("StripKit.presentation", { stripPresentation() }))
    SelfTest.cases.append(("StripKit.suggestions", { stripSuggestions() }))
    SelfTest.cases.append(("StripKit.controller", { MainActor.assumeIsolated { stripController() } }))
    SelfTest.cases.append(("StripKit.render", { MainActor.assumeIsolated { stripRender() } }))
}

// MARK: - Install

@MainActor private func stripInstall() {
    let saved = (Services.store, Services.pasting, Services.strip)
    defer { Services.store = saved.0; Services.pasting = saved.1; Services.strip = saved.2 }
    Services.store = StripFakeStore()
    Services.pasting = StripFakePasting()
    StripKitModule.install()
    check(Services.strip is StripController, "the real strip is registered")
    check(Services.strip.isVisible == false, "starts hidden")
}

// MARK: - Geometry (ui-reference §2.6)

@MainActor private func stripGeometry() {
    let table: [(SPStyle, CGFloat, CGFloat, CardSizeClass)] = [
        (.glass, 332, 232, .small), (.classic, 332, 240, .regular),
        (.glass, 252, 152, .compact), (.classic, 252, 160, .compact),
        (.glass, 412, 312, .large), (.classic, 412, 320, .large),
    ]
    for (style, height, side, sizeClass) in table {
        let g = StripGeometry(style: style, panelHeight: height)
        check(g.cardSide == side, "\(style) \(height): side \(g.cardSide) == \(side)")
        check(g.sizeClass == sizeClass, "\(style) \(height): \(g.sizeClass)")
    }
    check(StripGeometry(style: .glass, panelHeight: 500).panelHeight == 412, "height clamps to 412")
    check(StripGeometry(style: .glass, panelHeight: 100).panelHeight == 252, "height clamps to 252")

    let g = StripGeometry(style: .classic, panelHeight: 332)  // side 240, pitch 264
    let leading = g.leading(sidecarWidth: 0)
    check(leading == 24, "first card 24 from the leading edge")
    check(g.cardFrame(at: 0, leading: leading) == CGRect(x: 24, y: 8, width: 240, height: 240), "card 0 frame")
    check(g.cardFrame(at: 2, leading: leading).minX == 552, "spacing 24 between cards")
    let expectedWidth: CGFloat = 24 + 720 + 48 + 24
    check(g.contentWidth(count: 3, leading: leading) == expectedWidth, "content width with right inset")
    check(g.leading(sidecarWidth: 200) == 24 + 200 + 24, "cards start after the sidecar")
    check(g.indices(from: 0, to: 600, count: 10, leading: leading) == 0..<3, "visible indices")
    check(g.indices(from: 265, to: 300, count: 10, leading: leading) == 1..<2, "a gap-straddling window sees card 1")
    check(g.indices(from: 0, to: 600, count: 0, leading: leading).isEmpty, "no cards")
    check(g.index(at: 30, count: 5, leading: leading) == 0 && g.index(at: 270, count: 5, leading: leading) == nil,
          "hit test: card and gap")
    check(g.index(at: 300, count: 5, leading: leading) == 1, "hit test: second card")
    check(g.firstVisibleIndex(scrollX: 0, count: 5, leading: leading) == 0, "first visible at rest")
    check(g.firstVisibleIndex(scrollX: 154, count: 5, leading: leading) == 1, "half-hidden card isn't first")
    check(g.scrollX(revealing: 0, current: 0, viewportWidth: 800, count: 10, leading: leading) == nil, "already visible")
    check(g.scrollX(revealing: 4, current: 0, viewportWidth: 800, count: 10, leading: leading)
          == g.cardFrame(at: 4, leading: leading).maxX + 24 - 800, "reveal to the right keeps the 24 inset")
    check(g.scrollX(revealing: 0, current: 500, viewportWidth: 800, count: 10, leading: leading) == 0, "reveal the first card")
    check(g.cardsPerPage(viewportWidth: 1440) == 5, "page size")
    check(g.insertionIndex(at: 276, count: 5, leading: leading) == 1, "drop in the gap before card 1")
    check(g.insertionIndex(at: 10_000, count: 5, leading: leading) == 5, "drop past the end")
    check(g.gapCenterX(before: 1, leading: leading) == 276, "marker in the middle of the gap")
}

@MainActor private func stripHeaderLayout() {
    let glass = SPMetrics(style: .glass), classic = SPMetrics(style: .classic)
    let large = CardHeaderLayout(sizeClass: .large, metrics: glass, compactStyle: .transparent, appIconHidden: false)
    check(large.height == 56 && large.appIconHeight == 84 && large.appIconTrailing == 14, "large header")
    check(large.labelsTrailing == -70 && large.labelsVertical && large.labelsSpacing == -1, "large labels")
    check(large.titleFont.pointSize == SPFont.style(.title3).pointSize && large.dateFont.pointSize == SPFont.style(.callout).pointSize,
          "large fonts: title3 medium, callout")
    check(large.bandAlpha == 1 && large.gradientAlpha == 0 && large.pinboardIconTrailing == 8, "large band")
    let pinned = CardHeaderLayout(sizeClass: .regular, metrics: glass, compactStyle: .transparent, appIconHidden: true)
    check(pinned.height == 52 && pinned.labelsTrailing == -12 && pinned.appIconAlpha == 0, "pinned: no app icon, labels to −12")
    let small = CardHeaderLayout(sizeClass: .small, metrics: classic, compactStyle: .transparent, appIconHidden: false)
    check(small.height == 48 && small.appIconHeight == 76 && small.labelsTrailing == -62, "small header")
    let compactGlass = CardHeaderLayout(sizeClass: .compact, metrics: glass, compactStyle: .gradient, appIconHidden: false)
    check(compactGlass.height == 36 && compactGlass.appIconHeight == 20 && compactGlass.appIconTrailing == -8, "compact glass")
    check(compactGlass.appIconAlpha == 0.9 && compactGlass.bandAlpha == 0 && compactGlass.gradientAlpha == 1, "compact gradient")
    check(!compactGlass.labelsVertical && compactGlass.labelsTrailing == -30 && compactGlass.pinboardIconTrailing == -12,
          "compact labels")
    check(compactGlass.titleFont.pointSize == SPFont.style(.headline).pointSize, "compact title headline semibold")
    let compactClassic = CardHeaderLayout(sizeClass: .compact, metrics: classic, compactStyle: .transparent, appIconHidden: false)
    check(compactClassic.height == 34 && compactClassic.gradientAlpha == 0, "compact classic is 34, transparent")
}

// MARK: - Selection

private func stripSelection() {
    var s = SelectionState()
    s.click(2, mode: .single)
    check(s.indices == [2] && s.lead == 2, "single click")
    s.click(5, mode: .range)
    check(s.indices == IndexSet(2...5) && s.anchor == 2 && s.lead == 5, "⇧-click selects the range")
    s.click(3, mode: .toggle)
    check(s.indices == [2, 4, 5], "⌘-click toggles off")
    s.click(7, mode: .toggle)
    check(s.indices == [2, 4, 5, 7] && s.lead == 7, "⌘-click toggles on")
    s.move(by: 1, extend: false, count: 10)
    check(s.indices == [8] && s.lead == 8, "→ moves and collapses")
    s.move(by: 1, extend: true, count: 10)
    s.move(by: 1, extend: true, count: 10)
    check(s.indices == [8, 9] && s.lead == 9, "⇧→ extends, clamped at the end")
    s.move(by: -3, extend: true, count: 10)
    check(s.indices == IndexSet(6...8) && s.anchor == 8, "⇧← extends the other way from the anchor")
    s.moveTo(0, extend: false, count: 10)
    check(s.indices == [0], "Home")
    s.move(by: -1, extend: false, count: 10)
    check(s.indices == [0], "← at the start stays")
    s.selectAll(count: 4)
    check(s.indices == IndexSet(0..<4), "Select All")
    s.clamp(to: 2)
    check(s.indices == [0, 1] && (s.lead ?? 9) < 2, "clamp after the list shrank")
    var empty = SelectionState()
    empty.move(by: 1, extend: false, count: 3)
    check(empty.indices == [0], "→ with nothing selected selects the first card")
    empty.move(by: 1, extend: false, count: 0)
    check(empty.isEmpty, "an empty list has no selection")
}

// MARK: - Keys (behaviour.md §4.4)

private func stripKeyMap() {
    let b = StripKeyBindings.defaults
    func cmd(_ code: Int, _ mods: NSEvent.ModifierFlags = [], _ chars: String = "") -> StripCommand? {
        StripKeyMap.command(for: KeyStroke(keyCode: code, modifiers: mods, characters: chars), bindings: b)
    }
    check(cmd(kVK_LeftArrow) == .move(-1, extend: false) && cmd(kVK_RightArrow, .shift) == .move(1, extend: true), "arrows")
    check(cmd(kVK_Home) == .first(extend: false) && cmd(kVK_End, .shift) == .last(extend: true), "Home / End")
    check(cmd(kVK_PageDown) == .page(1, extend: false) && cmd(kVK_PageUp) == .page(-1, extend: false), "page keys")
    check(cmd(kVK_Return) == .paste(plainText: false), "Return pastes")
    check(cmd(kVK_ANSI_KeypadEnter) == .paste(plainText: false), "Enter pastes")
    check(cmd(kVK_Return, .shift) == .paste(plainText: true), "⇧Return pastes plain text")
    check(cmd(kVK_Return, .option) == nil, "⌥Return does nothing")
    check(cmd(kVK_ANSI_1, .command, "1") == .quickPaste(1, plainText: false), "⌘1 quick paste")
    check(cmd(kVK_ANSI_9, .command, "9") == .quickPaste(9, plainText: false), "⌘9 quick paste")
    check(cmd(kVK_ANSI_3, [.command, .shift], "#") == .quickPaste(3, plainText: true), "⇧⌘3 quick paste as plain text")
    check(cmd(kVK_ANSI_0, .command, "0") == nil, "⌘0 isn't quick paste")
    check(cmd(kVK_Space) == .preview, "Space previews")
    check(cmd(kVK_ANSI_C, .command, "c") == .copy && cmd(kVK_ANSI_E, .command, "e") == .edit, "⌘C ⌘E")
    check(cmd(kVK_ANSI_R, .command, "r") == .rename && cmd(kVK_ANSI_O, .command, "o") == .open, "⌘R ⌘O")
    check(cmd(kVK_Delete) == .delete && cmd(kVK_Delete, .command) == .delete && cmd(kVK_ForwardDelete) == .delete, "delete keys")
    check(cmd(kVK_ANSI_Z, .command, "z") == .undo && cmd(kVK_ANSI_Z, [.command, .shift], "Z") == .redo, "undo / redo")
    check(cmd(kVK_ANSI_A, .command, "a") == .selectAll && cmd(kVK_ANSI_F, .command, "f") == .filters, "⌘A ⌘F")
    check(cmd(kVK_LeftArrow, .command) == .previousList && cmd(kVK_RightArrow, .command) == .nextList, "⌘← ⌘→ switch lists")
    check(cmd(kVK_ANSI_N, .command, "n") == .newTextItem && cmd(kVK_ANSI_Comma, .command, ",") == .settings, "⌘N ⌘,")
    check(cmd(kVK_ANSI_G, .command, "g") == .showInList, "⌘G")
    check(cmd(kVK_Escape) == .cancel, "Esc")
    check(cmd(kVK_Tab) == .switchFocus(backward: false) && cmd(kVK_Tab, .shift) == .switchFocus(backward: true), "Tab")
    check(cmd(kVK_ANSI_X) == nil, "plain letters aren't commands")

    var custom = b
    custom.quickPasteModifiers = [.control, .option]
    custom.nextList = Shortcut(key: kVK_ANSI_L, modifiers: [.control])
    check(StripKeyMap.command(for: KeyStroke(keyCode: kVK_ANSI_2, modifiers: [.control, .option], characters: "2"), bindings: custom)
          == .quickPaste(2, plainText: false), "custom quick-paste modifiers")
    check(StripKeyMap.command(for: KeyStroke(keyCode: kVK_ANSI_2, modifiers: .command, characters: "2"), bindings: custom) == nil,
          "⌘2 does nothing when Quick Paste uses ⌃⌥")
    check(StripKeyMap.command(for: KeyStroke(keyCode: kVK_ANSI_L, modifiers: .control, characters: "l"), bindings: custom)
          == .nextList, "custom next-pinboard shortcut")

    check(StripKeyMap.startsSearch(KeyStroke(keyCode: kVK_ANSI_A, modifiers: [], characters: "a")), "typing starts a search")
    check(StripKeyMap.startsSearch(KeyStroke(keyCode: kVK_ANSI_A, modifiers: .shift, characters: "A")), "capitals too")
    check(!StripKeyMap.startsSearch(KeyStroke(keyCode: kVK_ANSI_A, modifiers: .command, characters: "a")), "not ⌘ keys")
    check(!StripKeyMap.startsSearch(KeyStroke(keyCode: kVK_Space, modifiers: [], characters: " ")), "not Space")
    check(!StripKeyMap.startsSearch(KeyStroke(keyCode: kVK_LeftArrow, modifiers: [], characters: "\u{F702}")), "not arrows")
}

// MARK: - Mouse (behaviour.md §4.5)

private func stripMouseMap() {
    let b = StripKeyBindings.defaults
    check(StripMouseMap.action(clickCount: 1, modifiers: [], bindings: b) == .select(.single), "a click only selects")
    check(StripMouseMap.action(clickCount: 1, modifiers: .shift, bindings: b) == .select(.range), "⇧-click selects a range")
    check(StripMouseMap.action(clickCount: 1, modifiers: .command, bindings: b) == .select(.toggle), "⌘-click toggles")
    check(StripMouseMap.action(clickCount: 2, modifiers: [], bindings: b) == .paste(plainText: false), "double click pastes")
    check(StripMouseMap.action(clickCount: 2, modifiers: .shift, bindings: b) == .paste(plainText: true),
          "⇧ double click pastes plain text")
    check(StripMouseMap.action(clickCount: 3, modifiers: [], bindings: b) == .paste(plainText: false), "triple click still pastes")
    check(StripMouseMap.action(clickCount: 2, modifiers: .command, bindings: b) == .paste(plainText: false),
          "⌘ double click pastes as is")

    let numbers = StripMouseMap.badges(held: .command, bindings: b)
    check(numbers.numbers && !numbers.plainText, "⌘ shows quick-paste numbers")
    let plain = StripMouseMap.badges(held: .shift, bindings: b)
    check(!plain.numbers && plain.plainText, "⇧ shows the plain-text mark")
    let both = StripMouseMap.badges(held: [.command, .shift], bindings: b)
    check(both.numbers && both.plainText, "⇧⌘ shows both")
    let none = StripMouseMap.badges(held: [.command, .option], bindings: b)
    check(!none.numbers && !none.plainText, "other modifiers hide the badges")
}

// MARK: - Dates (ui-reference §4.3)

private func stripDates() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let en = Locale(identifier: "en_US")
    check(CardDateText.text(for: now.addingTimeInterval(-7200), now: now, compact: true, locale: en) == "2h", "compact 2h")
    check(CardDateText.text(for: now.addingTimeInterval(-3 * 86_400), now: now, compact: true, locale: en) == "3d", "compact 3d")
    check(CardDateText.text(for: now.addingTimeInterval(-90), now: now, compact: true, locale: en) == "1m", "compact 1m")
    check(CardDateText.text(for: now.addingTimeInterval(-7200), now: now, compact: false, locale: en) == "2 hours ago",
          "relative: \(CardDateText.text(for: now.addingTimeInterval(-7200), now: now, compact: false, locale: en))")
    check(CardDateText.text(for: now.addingTimeInterval(-86_400), now: now, compact: false, locale: en) == "yesterday", "named style")
    check(CardDateText.text(for: now.addingTimeInterval(5), now: now, compact: false, locale: en) == "now", "future clamps to now")
    check(!CardDateText.tooltip(for: now, locale: en).isEmpty, "tooltip")
}

// MARK: - Header colour (ui-reference §4.3; the icon rule itself is `AppColor`, checked in CoreTests)

@MainActor private func stripHeaderColor() {
    // Header colour precedence: pinboard, stored app colour, then gray.
    let board = Pinboard(name: "Work", color: .green, order: 0)
    let pinned = ClipItem(kind: .text, pins: [PinboardPin(pinboardID: board.id, order: 1)])
    let provider = AppIconProvider.shared
    check(provider.headerColor(for: pinned, scope: .history, pinboards: [board], style: .classic)
          .isEqual(SPColor.pinboard(.green, style: .classic)), "a pinned item takes its pinboard's colour")
    let app = ClipItem(kind: .text, sourceApp: AppRecord(bundleID: "test.app", name: "Test", colorHex: "#62A9F5"))
    check(provider.headerColor(for: app, scope: .history, pinboards: [], style: .glass) == .systemBlue, "#62A9F5 → systemBlue")
}

// MARK: - Presentation

private func stripPresentation() {
    check(ItemPresentation.typeLabel(ClipItem(kind: .richText)) == "Text", "rich text reads Text")
    check(ItemPresentation.typeLabel(ClipItem(kind: .files, filePaths: ["/a"])) == "File", "one file")
    check(ItemPresentation.typeLabel(ClipItem(kind: .files, filePaths: ["/a", "/b", "/c"])) == "3 files", "several files")
    check(ItemPresentation.headerTitle(ClipItem(kind: .link, title: "Docs")) == "Docs", "custom title wins")
    check(ItemPresentation.headerTitle(ClipItem(kind: .link, title: "  ")) == "Link", "blank title falls back")
    let link = ClipItem(kind: .link, text: "https://www.airbnb.com/rooms/1", link: LinkMetadata(url: "https://www.airbnb.com/rooms/1"))
    check(ItemPresentation.displayHost(ItemPresentation.linkURL(link)) == "airbnb.com", "host without www")
    check(ItemPresentation.linkTitle(link) == "airbnb.com", "untitled link shows its host")
    check(ItemPresentation.filesTitle(ClipItem(kind: .files, filePaths: ["/x/a.txt", "/x/b.txt"])) == "Multiple files", "files title")
    let home = NSHomeDirectory()
    check(ItemPresentation.filesPath(ClipItem(kind: .files, filePaths: ["\(home)/Documents/website/backup.zip"]))
          == "Documents/website/backup.zip", "one file: its path with the name, without ~/")
    check(ItemPresentation.filesPath(ClipItem(kind: .files, filePaths: ["\(home)/Documents/a.txt", "\(home)/Documents/b.txt"]))
          == "Documents", "several files: the folder")
    check(ItemPresentation.filesPath(ClipItem(kind: .files, filePaths: ["/Volumes/Disk/x.txt"])) == "/Volumes/Disk/x.txt",
          "paths outside the home folder stay absolute")
    check(ItemPresentation.showsDate(ClipItem(copiedAt: Date(), kind: .text)), "history items show their date")
    check(!ItemPresentation.showsDate(ClipItem(copiedAt: nil, kind: .text)), "pinned-only items show the title alone")
    check(ItemPresentation.colorHex(ClipItem(kind: .color, text: "#ff8800")) == "#FF8800", "colour hex")
    check(L10n.characters(1) == "1 character" && L10n.characters(1200) == "\(1200.formatted()) characters", "character count")
    let counts = ItemPresentation.textCounts("Hello world\nsecond line")
    check(counts.characters == 23 && counts.words == 4 && counts.lines == 2, "text counts")
    let long = String(repeating: "line\n", count: 100)
    check(CardText.excerpt(long).components(separatedBy: "\n").count <= CardText.maxLines + 1, "excerpt caps lines")
    check(CardText.excerpt(String(repeating: "a", count: 9000)).count == CardText.maxCharacters, "excerpt caps characters")
    check(ItemPresentation.isCompactContentFullSize(ClipItem(kind: .image)), "images go full-size in compact")
    check(!ItemPresentation.isCompactContentFullSize(ClipItem(kind: .text)), "text doesn't")
    check(L10n.tabTooltip("Work", previous: "⌘←", next: "⌘→") == "Work (⌘←, ⌘→ to navigate)", "tab tooltip")
    check(L10n.pasteTo(nil) == "Paste to current app" && L10n.pasteTo("Mail") == "Paste to Mail", "Paste to")
}

private func stripSuggestions() {
    let sources = FilterSources(apps: [AppRecord(bundleID: "com.apple.Safari", name: "Safari"),
                                       AppRecord(bundleID: "com.apple.mail", name: "Mail")],
                                pinboards: [Pinboard(name: "Links", color: .blue, order: 0)],
                                devices: [Device(id: "d", name: "Studio")])
    let li = sources.suggestions(for: "li", excluding: [])
    check(li.first?.filter == .init(.type, "link"), "types first: \(li.map(\.title))")
    check(li.contains { $0.filter == .init(.pinboard, "Links") }, "pinboards match too")
    check(sources.suggestions(for: "app:sa", excluding: []).map(\.filter) == [.init(.app, "Safari")], "key-scoped values")
    check(sources.suggestions(for: "app:", excluding: []).count == 2, "a bare key lists all its values")
    check(sources.suggestions(for: "sa", excluding: [.init(.app, "Safari")]).isEmpty, "applied filters are hidden")
    check(sources.suggestions(for: "tod", excluding: []).map(\.filter) == [.init(.date, "today")], "dates")
    check(sources.suggestions(for: "", excluding: []).isEmpty, "nothing for an empty word")
    check(sources.sections.map(\.type) == [.app, .date, .device, .pinboard, .type], "browser section order")
    check(sources.title(for: .init(.type, "links")) == "Link" && sources.title(for: .init(.date, "Today")) == "Today",
          "token titles")
}

// MARK: - The strip against an in-memory store

@MainActor private func stripController() {
    let saved = (Services.store, Services.pasting)
    let store = StripFakeStore()
    let pasting = StripFakePasting()
    Services.store = store
    Services.pasting = pasting
    defer { Services.store = saved.0; Services.pasting = saved.1 }

    let now = Date()
    let texts = (0..<30).map { i in
        try! store.insert(ClipDraft.text("Item \(i)", copiedAt: now.addingTimeInterval(TimeInterval(-i * 60)))).item
    }
    let strip = StripController(style: .classic)
    strip.start()
    strip.loadViewsIfNeeded()
    strip.layoutForFrame(NSRect(x: 0, y: 0, width: 1440, height: 332))
    strip.reload(keepSelection: false)
    check(strip.items.count == 30 && strip.total == 30, "loads the history")
    check(strip.items.first?.id == texts.first?.id, "newest first")
    check(strip.selection.indices == [0], "the first card is selected")
    check(strip.cards?.visibleIndices.isEmpty == false, "cards are laid out")
    check(strip.root?.emptyLabel.isHidden == true, "no empty state")

    // The panel (ui-reference §2.1): non-activating, above the Dock, not movable, no shadow, resized only by its handle.
    if let panel = strip.panel {
        check(panel.level == SPMetrics.Strip.windowLevel, "level 24 (above the Dock): \(panel.level.rawValue)")
        check(panel.styleMask.contains(.nonactivatingPanel) && panel.styleMask.contains(.resizable), "style mask 0x88")
        check(panel.canBecomeKey && !panel.isMovable && !panel.hasShadow, "key-capable, fixed, shadowless")
        check(panel.minSize == panel.frame.size && panel.maxSize == panel.frame.size, "window resizing is pinned")
    } else {
        check(false, "panel created")
    }

    // Keys → selection.
    strip.perform(.move(1, extend: false))
    strip.perform(.move(1, extend: true))
    check(strip.selection.indices == [1, 2], "→ then ⇧→")
    strip.perform(.paste(plainText: false))
    check(pasting.pasted.last?.ids == [texts[1].id, texts[2].id] && pasting.pasted.last?.plainText == false,
          "Return pastes the selection in list order")
    strip.perform(.paste(plainText: true))
    check(pasting.pasted.last?.plainText == true, "⇧Return pastes plain text")

    // Double click pastes that card only; ⇧ makes it plain text.
    strip.cardDoubleClicked(4, plainText: false)
    check(pasting.pasted.last?.ids == [texts[4].id] && pasting.pasted.last?.plainText == false, "double click pastes the card")
    strip.cardDoubleClicked(5, plainText: true)
    check(pasting.pasted.last?.ids == [texts[5].id] && pasting.pasted.last?.plainText == true, "⇧ double click: plain text")
    Defaults[.isPasteAsPlainTextEnabled] = true
    strip.cardDoubleClicked(6, plainText: false)
    check(pasting.pasted.last?.plainText == true, "Always paste as Plain Text applies to every paste")
    Defaults.reset(.isPasteAsPlainTextEnabled)

    // Quick paste numbers the visible cards from the first one shown.
    strip.perform(.quickPaste(3, plainText: false))
    check(pasting.pasted.last?.ids == [texts[2].id], "⌘3 pastes the third visible card")
    strip.perform(.quickPaste(1, plainText: true))
    check(pasting.pasted.last?.ids == [texts[0].id] && pasting.pasted.last?.plainText == true, "⇧⌘1 pastes plain text")

    // Copy, select all, end.
    strip.cardClicked(3, mode: .single)
    strip.perform(.copy)
    check(pasting.copied.last == [texts[3].id], "⌘C copies")
    strip.perform(.selectAll)
    check(strip.selection.count == 30, "⌘A")
    strip.perform(.first(extend: false))
    strip.perform(.last(extend: false))
    check(strip.selection.indices == [29], "End")

    // Delete with undo and redo.
    strip.cardClicked(0, mode: .single)
    strip.perform(.delete)
    check(store.deleted.last == [texts[0].id] && store.item(texts[0].id) == nil, "⌫ deletes")
    strip.reload(keepSelection: true)
    check(strip.selection.indices == [0] && strip.items.first?.id == texts[1].id, "selection moves to the next card")
    strip.perform(.undo)
    check(store.item(texts[0].id) != nil, "⌘Z restores")
    strip.perform(.redo)
    check(store.item(texts[0].id) == nil, "⇧⌘Z deletes again")
    strip.perform(.undo)
    strip.reload(keepSelection: false)

    // Pins: pin, move to another pinboard, undo.
    let work = try! store.createPinboard(name: "Work", color: .purple)
    let home = try! store.createPinboard(name: "Home", color: .green)
    strip.reload(keepSelection: true)
    check(strip.toolbar?.tabBar.entries.map(\.name) == ["Clipboard", "Work", "Home"], "tabs: Clipboard then pinboards")
    strip.pin([texts[1]], to: work.id)
    check(store.item(texts[1].id)?.pinboardIDs == [work.id], "pinned")
    strip.pin([store.item(texts[1].id)!], to: home.id)
    check(store.item(texts[1].id)?.pinboardIDs == [home.id], "one pinboard per item")
    strip.perform(.undo)
    check(store.item(texts[1].id)?.pinboardIDs == [work.id], "undo restores the previous pin")

    // Lists and search.
    strip.perform(.nextList)
    check(strip.scope == .pinboard(work.id) && strip.items.map(\.id) == [texts[1].id], "⌘→ shows the next pinboard")
    strip.perform(.nextList)
    check(strip.scope == .pinboard(home.id) && strip.items.isEmpty, "empty pinboard")
    check(strip.root?.emptyLabel.isHidden == false && strip.root?.emptyLabel.stringValue == "Pinboard is empty", "empty state")
    strip.perform(.previousList)
    strip.perform(.previousList)
    check(strip.scope == .history, "⌘← back to History")
    strip.toolbar?.search.setQuery(SearchQuery(parsing: "Item 2"))
    check(strip.query.tokens == ["Item", "2"], "search query")
    check(strip.items.allSatisfy { $0.text.contains("2") }, "search narrows the list")
    strip.toolbar?.search.setQuery(SearchQuery(parsing: "zzz"))
    check(strip.items.isEmpty && strip.root?.emptyLabel.stringValue == "Nothing found", "nothing found")
    strip.perform(.cancel)
    check(strip.query.isEmpty && strip.items.count == 30, "Esc clears the search")
    // While searching the tabs collapse to icon-only chips after the field and "+" folds away (§3.1, §3.4).
    if let toolbar = strip.toolbar {
        let expanded = toolbar.tabBar.contentWidth
        toolbar.setSearchActive(true, animated: false)
        toolbar.layoutSubtreeIfNeeded()
        let chips = toolbar.tabBar.chips
        check(toolbar.tabBar.isCollapsed && chips.allSatisfy { $0.fittingSize.width == SPMetrics.TabBar.chipHeight },
              "collapsed tabs are 28 pt squares")
        check(toolbar.tabBar.contentWidth < expanded && toolbar.tabBar.frame.width > 0,
              "the tab bar keeps its place, narrower: \(toolbar.tabBar.contentWidth) < \(expanded), frame \(toolbar.tabBar.frame), toolbar \(toolbar.bounds)")
        check(toolbar.tabBar.frame.minX == toolbar.search.frame.maxX + SPMetrics.Toolbar.itemSpacing, "tabs follow the field")
        check(toolbar.search.frame.width >= SPMetrics.Toolbar.activeSearchMinWidth, "the field is at least 400 wide")
        check(toolbar.plusButton.alphaValue == 0 && toolbar.plusButton.frame.maxX == toolbar.tabBar.frame.maxX, "+ snaps to the tabs, hidden")
        toolbar.setSearchActive(false, animated: false)
        toolbar.layoutSubtreeIfNeeded()
        check(!toolbar.tabBar.isCollapsed && toolbar.tabBar.contentWidth == expanded && toolbar.plusButton.alphaValue == 1,
              "closing the search restores the tabs: \(toolbar.tabBar.contentWidth) == \(expanded), alpha \(toolbar.plusButton.alphaValue)")
    }
    check(strip.showInTargets(for: store.item(texts[1].id)!) == [.pinboard(work.id)], "Show in the item's pinboard")

    // Context menu, per ui-reference §4.8.
    strip.cardClicked(1, mode: .single)
    let menu = strip.contextMenu(forCardAt: 1)
    let titles = menu?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? []
    check(titles == ["Show in Work", "—", "Paste to current app", "Paste as Plain Text", "Copy", "—", "Edit", "Rename", "Delete",
                     "—", "Pin", "—", "Preview", "Share"], "context menu: \(titles)")
    check(menu?.items.first { $0.title == "Delete" }?.keyEquivalent == "\u{8}", "Delete shows ⌫")
    check(menu?.items.first { $0.title == "Paste to current app" }?.keyEquivalent == "\r", "Paste shows ↩")
    let pin = menu?.items.first { $0.title == "Pin" }?.submenu?.items.map { $0.isSeparatorItem ? "—" : $0.title }
    check(pin == ["Work", "Home", "—", "Create Pinboard", "Unpin"], "pin submenu: \(pin ?? [])")
    strip.perform(.selectAll)
    check(strip.contextMenu(forCardAt: 0)?.items.first?.title == "30 Selected", "multi-selection header")

    // Rename and its undo.
    strip.changeItems([texts[2].id], actionName: "Rename") { try $0.rename(texts[2].id, to: "Greeting") }
    check(store.item(texts[2].id)?.title == "Greeting", "renamed")
    strip.perform(.undo)
    check(store.item(texts[2].id)?.title == nil, "rename undone")

    // Paste Stack panel (ui-reference §9).
    let stack = PasteStackPanelController()
    stack.update(PasteStackState(isActive: true, items: Array(texts.prefix(2)), direction: .bottom))
    check(stack.panel?.level == SPMetrics.PasteStack.windowLevel, "Paste Stack at status level")
    check(stack.panel?.frame.width == SPMetrics.PasteStack.windowSize.width, "322 wide")
    check(stack.contentHeight(rows: 0) == stack.contentHeight(rows: 1), "an empty stack keeps one row")
    check(stack.contentHeight(rows: 2) - stack.contentHeight(rows: 1) == SPMetrics.PasteStack.rowHeight, "44 pt rows")
    check(stack.contentHeight(rows: 50) == SPMetrics.PasteStack.windowSize.height, "capped at 372")
    stack.update(PasteStackState(isActive: false))
    check(stack.panel?.isVisible != true, "hidden when the stack ends")

    Defaults.reset(.selectedListIdentifier)
    Defaults.reset(.stripDismissedNotifications)
}

// MARK: - Offscreen renders

@MainActor private func stripRender() {
    let saved = (Services.store, Services.pasting)
    let store = StripFakeStore()
    Services.store = store
    Services.pasting = StripFakePasting()
    defer { Services.store = saved.0; Services.pasting = saved.1 }
    StripSamples.fill(store)
    let directory = ProcessInfo.processInfo.environment["STRIPKIT_RENDER_DIR"].map { URL(fileURLWithPath: $0) }
    if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }

    BackgroundEffectView.usesGlassStandIn = true
    defer { BackgroundEffectView.usesGlassStandIn = false }

    /// Renders `view` with `cacheDisplay` and, for the strip, over a desktop-like gradient so translucency shows.
    func write(_ view: NSView, _ name: String, wallpaper: Bool = false, dark: Bool = false) -> Bool {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return false }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let directory else { return rep.pixelsWide > 0 }
        var output = rep
        if wallpaper, let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
            let rect = NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
            let colors = dark ? [NSColor(hex: "#2B2340"), NSColor(hex: "#4A2F3A")] : [NSColor(hex: "#E9D9EF"), NSColor(hex: "#F4DCCB")]
            NSGradient(colors: colors)?.draw(in: rect, angle: 0)
            rep.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            output = canvas
        }
        if let png = output.representation(using: .png, properties: [:]) {
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
        }
        return rep.pixelsWide > 0
    }

    var rendered = 0
    let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
    for style in [SPStyle.glass, .classic] {
        for (mode, appearance) in appearances {
            for height in directory == nil ? [CGFloat(332)] : [332, 252, 412] {
                let strip = StripController(style: style)
                strip.loadViewsIfNeeded()
                strip.panel?.appearance = NSAppearance(named: appearance)
                Defaults[.isDirectPasteEnabled] = height == 332 && mode == "light"
                strip.sidecar.refresh()
                strip.layoutForFrame(NSRect(x: 0, y: 0, width: 1440, height: height))
                strip.reload(keepSelection: false)
                strip.updateSidecar()
                strip.selection.click(1, mode: .single)
                strip.cards?.updateSelection()
                if height == 412 { strip.cards?.showsQuickPasteNumbers = true }
                guard let content = strip.panel?.contentView else { continue }
                content.layoutSubtreeIfNeeded()
                content.displayIfNeeded()
                if write(content, "strip-\(style.rawValue)-\(mode)-\(Int(height))", wallpaper: true, dark: mode == "dark") {
                    rendered += 1
                }
                Defaults.reset(.isDirectPasteEnabled)
            }
        }
    }
    check(rendered > 0, "renders the strip offscreen")
    guard directory != nil else { return }

    // Further along the history (files, colour, unknown cards) and the seeded Welcome pinboard.
    for (name, setup) in [("strip-glass-light-332-page2", { (strip: StripController) in strip.cards?.scrollToReveal(9, animated: false) }),
                          ("strip-glass-light-332-welcome", { (strip: StripController) in
                              if let board = WelcomeContent.seedIfNeeded() { strip.setScope(.pinboard(board.id)) }
                          })] {
        let strip = StripController(style: .glass)
        strip.loadViewsIfNeeded()
        strip.panel?.appearance = NSAppearance(named: .aqua)
        strip.layoutForFrame(NSRect(x: 0, y: 0, width: 1440, height: 332))
        strip.reload(keepSelection: false)
        setup(strip)
        strip.cards?.tile()
        strip.root?.layoutSubtreeIfNeeded()
        if let content = strip.panel?.contentView { _ = write(content, name, wallpaper: true) }
    }
    Defaults.reset(.welcomePinboardID)

    // Paused: the notification bar's pause item.
    let savedClipboard = Services.clipboard
    Services.clipboard = StripFakeClipboard(state: .paused(until: Date().addingTimeInterval(3600)))
    for style in [SPStyle.glass, .classic] {
        let strip = StripController(style: style)
        strip.loadViewsIfNeeded()
        strip.panel?.appearance = NSAppearance(named: .aqua)
        strip.layoutForFrame(NSRect(x: 0, y: 0, width: 1440, height: 332))
        strip.reload(keepSelection: false)
        strip.root?.layoutSubtreeIfNeeded()
        if let content = strip.panel?.contentView { _ = write(content, "strip-\(style.rawValue)-paused", wallpaper: true) }
    }
    Services.clipboard = savedClipboard

    // Toolbar with an open search (tokens).
    for style in [SPStyle.glass, .classic] {
        let strip = StripController(style: style)
        strip.loadViewsIfNeeded()
        strip.panel?.appearance = NSAppearance(named: .aqua)
        strip.layoutForFrame(NSRect(x: 0, y: 0, width: 1440, height: 332))
        strip.reload(keepSelection: false)
        strip.toolbar?.search.setQuery(SearchQuery(parsing: "type:link app:Safari cabin"))
        strip.toolbar?.setSearchActive(true, animated: false)
        strip.root?.layoutSubtreeIfNeeded()
        if let content = strip.panel?.contentView { _ = write(content, "strip-\(style.rawValue)-search", wallpaper: true) }
    }

    // Previews and editors, one per kind, on the window background (the popover material doesn't render offscreen).
    Defaults[.isLinkPreviewsEnabled] = false
    var kinds: Set<ItemKind> = []
    for item in store.all where kinds.insert(item.kind).inserted {
        for (mode, appearance) in appearances {
            for editing in StripController.isEditable(item) ? [false, true] : [false] {
                let controller = PreviewViewController(item: item, style: .glass, editing: editing)
                let size = PreviewController.initialSize(for: nil)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered,
                                      defer: false)
                window.appearance = NSAppearance(named: appearance)
                let background = FillView(frame: NSRect(origin: .zero, size: size))
                background.fillColor = .windowBackgroundColor
                window.contentView = background
                controller.view.frame = background.bounds
                background.addSubview(controller.view)
                background.layoutSubtreeIfNeeded()
                _ = write(background, "preview-\(item.kind.rawValue)\(editing ? "-edit" : "")-\(mode)")
            }
        }
    }
    Defaults.reset(.isLinkPreviewsEnabled)

    // The Filters popover content and the New Text Item window.
    for (mode, appearance) in appearances {
        let sources = FilterSources.current
        let browser = NSHostingView(rootView: FilterBrowserView(sources: sources, applied: [.init(.type, "link")], style: .glass) { _ in })
        let size = browser.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        let background = FillView(frame: NSRect(origin: .zero, size: size))
        background.fillColor = .windowBackgroundColor
        browser.frame = background.bounds
        background.addSubview(browser)
        window.contentView = background
        background.layoutSubtreeIfNeeded()
        _ = write(background, "filters-\(mode)")

        let creator = NewTextItemController()
        creator.show(in: .history, activating: false)
        if let content = creator.window?.contentView {
            creator.window?.appearance = NSAppearance(named: appearance)
            content.layoutSubtreeIfNeeded()
            _ = write(content, "new-text-item-\(mode)")
        }
        creator.close()
    }

    // Paste Stack panel.
    for (mode, appearance) in appearances {
        for count in [4, 0] {
            let stack = PasteStackPanelController()
            stack.update(PasteStackState(isActive: true, items: Array(store.all.prefix(count)), direction: .top))
            stack.panel?.appearance = NSAppearance(named: appearance)
            if let content = stack.panel?.contentView {
                content.layoutSubtreeIfNeeded()
                _ = write(content, "paste-stack-\(count)-\(mode)", wallpaper: true, dark: mode == "dark")
            }
            stack.update(PasteStackState(isActive: false))
        }
    }
}

// MARK: - Fakes

/// An in-memory `ItemStoring` for the strip's tests and renders.
@MainActor
final class StripFakeStore: ItemStoring {
    private(set) var all: [ClipItem] = []
    private var boards: [Pinboard] = []
    private var blobs: [String: Data] = [:]
    private var lastDeleted: [ClipItem] = []
    private(set) var deleted: [[UUID]] = []
    private let subject = PassthroughSubject<StoreChange, Never>()

    func item(_ id: UUID) -> ClipItem? { all.first { $0.id == id } }
    func items(_ ids: [UUID]) -> [ClipItem] { ids.compactMap(item) }

    private func matches(_ item: ClipItem, _ query: SearchQuery, _ scope: ListScope) -> Bool {
        switch scope {
        case .history: if !item.isInHistory { return false }
        case .pinboard(let id): if !item.isPinned(to: id) { return false }
        case .all: break
        }
        let haystack = ((item.title ?? "") + " " + item.text).lowercased()
        for token in query.tokens where !haystack.contains(token.lowercased()) { return false }
        if let kinds = query.kinds, !kinds.contains(item.kind) { return false }
        let apps = query.values(.app)
        if !apps.isEmpty, !apps.contains(where: { $0.caseInsensitiveCompare(item.sourceApp?.name ?? "") == .orderedSame }) { return false }
        return true
    }

    private func sorted(_ items: [ClipItem], _ scope: ListScope) -> [ClipItem] {
        if case .pinboard(let id) = scope {
            return items.sorted { ($0.pins.first { $0.pinboardID == id }?.order ?? 0) < ($1.pins.first { $0.pinboardID == id }?.order ?? 0) }
        }
        return items.sorted { ($0.copiedAt ?? $0.createdAt) > ($1.copiedAt ?? $1.createdAt) }
    }

    func search(_ query: SearchQuery, in scope: ListScope, limit: Int, offset: Int) -> [ClipItem] {
        let list = sorted(all.filter { matches($0, query, scope) }, scope)
        guard offset < list.count else { return [] }
        return Array(list[offset..<min(list.count, offset + limit)])
    }

    func count(_ query: SearchQuery, in scope: ListScope) -> Int { all.filter { matches($0, query, scope) }.count }
    var apps: [AppRecord] { Array(Set(all.compactMap(\.sourceApp))).sorted { $0.name < $1.name } }
    var devices: [Device] { Array(Set(all.compactMap(\.device))).sorted { $0.name < $1.name } }

    @discardableResult func insert(_ draft: ClipDraft) throws -> InsertResult {
        var refs: [PasteboardEntry] = []
        for entry in draft.entries {
            refs.append(PasteboardEntry(reps: try entry.reps.map { PasteboardRep(type: $0.type, blob: try saveBlob($0.data)) }))
        }
        var item = ClipItem(createdAt: draft.copiedAt ?? Date(), copiedAt: draft.copiedAt, kind: draft.kind, title: draft.title,
                            text: draft.text, sourceApp: draft.sourceApp, device: draft.device, byteSize: draft.byteSize,
                            checksum: draft.checksum, payload: refs, imageSize: draft.imageSize,
                            thumbnail: try draft.thumbnail.map(saveBlob), filePaths: draft.filePaths, link: draft.link)
        if let board = draft.pinboardID { item.pins = [PinboardPin(pinboardID: board, order: Double(all.count))] }
        all.append(item)
        subject.send(.inserted([item.id]))
        return InsertResult(item: item, isNew: true)
    }

    func add(_ item: ClipItem) { all.append(item) }

    func update(_ item: ClipItem) throws {
        guard let i = all.firstIndex(where: { $0.id == item.id }) else { throw StoreError.itemNotFound(item.id) }
        all[i] = item
        subject.send(.updated([item.id]))
    }

    func rename(_ id: UUID, to title: String?) throws {
        guard var item = item(id) else { throw StoreError.itemNotFound(id) }
        item.title = title?.isEmpty == true ? nil : title
        try update(item)
    }

    func replaceContent(of id: UUID, with draft: ClipDraft) throws -> ClipItem {
        guard var item = item(id) else { throw StoreError.itemNotFound(id) }
        item.kind = draft.kind
        item.text = draft.text
        try update(item)
        return item
    }

    func bump(_ id: UUID, at date: Date) throws {}
    func markUsed(_ ids: [UUID], at date: Date) throws {}

    func delete(_ ids: [UUID]) throws {
        lastDeleted = all.filter { ids.contains($0.id) }
        all.removeAll { ids.contains($0.id) }
        deleted.append(ids)
        subject.send(.deleted(ids))
    }

    var canUndoDelete: Bool { !lastDeleted.isEmpty }

    func undoLastDelete() throws -> [ClipItem] {
        let restored = lastDeleted
        all += restored
        lastDeleted = []
        subject.send(.inserted(restored.map(\.id)))
        return restored
    }

    var pinboards: [Pinboard] { boards.sorted { $0.order < $1.order } }

    func createPinboard(name: String, color: PinboardColor) throws -> Pinboard {
        let board = Pinboard(name: name, color: color, order: boards.count)
        boards.append(board)
        subject.send(.pinboards)
        return board
    }

    func updatePinboard(_ pinboard: Pinboard) throws {
        guard let i = boards.firstIndex(where: { $0.id == pinboard.id }) else { throw StoreError.pinboardNotFound(pinboard.id) }
        boards[i] = pinboard
        subject.send(.pinboards)
    }

    func deletePinboard(_ id: UUID) throws {
        boards.removeAll { $0.id == id }
        all.removeAll { $0.isPinned(to: id) && !$0.isInHistory }
        subject.send(.pinboards)
    }

    func reorderPinboards(_ ids: [UUID]) throws {
        for (order, id) in ids.enumerated() { if let i = boards.firstIndex(where: { $0.id == id }) { boards[i].order = order } }
        subject.send(.pinboards)
    }

    func assign(_ itemIDs: [UUID], to pinboardID: UUID) throws {
        for id in itemIDs {
            guard var item = item(id), !item.isPinned(to: pinboardID) else { continue }
            item.pins.append(PinboardPin(pinboardID: pinboardID, order: Double(all.count + item.pins.count)))
            try update(item)
        }
    }

    func unassign(_ itemIDs: [UUID], from pinboardID: UUID) throws {
        for id in itemIDs {
            guard var item = item(id) else { continue }
            item.pins.removeAll { $0.pinboardID == pinboardID }
            if item.pins.isEmpty, item.copiedAt == nil { item.copiedAt = Date() }
            try update(item)
        }
    }

    func move(_ itemIDs: [UUID], in pinboardID: UUID, before beforeID: UUID?) throws {}
    func prunableCount(retentionDays: Int, now: Date) -> Int { 0 }
    func prune(retentionDays: Int, now: Date) throws -> Int { 0 }

    func eraseHistory() throws -> Int {
        let before = all.count
        all.removeAll { !$0.isPinned }
        subject.send(.reloaded)
        return before - all.count
    }

    func setRecognizedText(_ text: String, for id: UUID) throws {}
    func data(for blob: BlobRef) -> Data? { blobs[blob.digest] }
    func fileURL(for blob: BlobRef) -> URL? { nil }

    func saveBlob(_ data: Data) throws -> BlobRef {
        let ref = BlobRef(of: data)
        blobs[ref.digest] = data
        return ref
    }

    var changes: AnyPublisher<StoreChange, Never> { subject.eraseToAnyPublisher() }
}

/// A clipboard monitor stuck in one pause state.
@MainActor
final class StripFakeClipboard: ClipboardMonitoring {
    let pauseState: PauseState
    /// What `pause(until:)` and `resume()` were asked (the app menu's checks in CoreTests).
    private(set) var pauses: [Date?] = []
    private(set) var resumes = 0
    init(state: PauseState) { pauseState = state }
    func start() {}
    var pauseChanges: AnyPublisher<PauseState, Never> { Just(pauseState).eraseToAnyPublisher() }
    func pause(until date: Date?) { pauses.append(date) }
    func resume() { resumes += 1 }
    var captures: AnyPublisher<ClipItem, Never> { Empty().eraseToAnyPublisher() }
}

/// Records what the strip asks ClipboardKit to do.
@MainActor
final class StripFakePasting: Pasting {
    private(set) var pasted: [(ids: [UUID], plainText: Bool)] = []
    private(set) var copied: [[UUID]] = []
    var target: PasteTarget? { nil }
    func paste(_ items: [ClipItem], plainText: Bool) { pasted.append((items.map(\.id), plainText)) }
    func copy(_ items: [ClipItem], plainText: Bool) { copied.append(items.map(\.id)) }
    func pasteboardWriters(for items: [ClipItem], plainText: Bool) -> [NSPasteboardWriting] { items.map { $0.text as NSString } }
    var pasteStack: PasteStackState { PasteStackState() }
    var pasteStackChanges: AnyPublisher<PasteStackState, Never> { Just(PasteStackState()).eraseToAnyPublisher() }
    func startPasteStack() {}
    func stopPasteStack() {}
    func pasteNextFromStack() {}
    func removeFromPasteStack(_ ids: [UUID]) {}
    func setPasteStackDirection(_ direction: StackDirection) {}
}

/// Sample items of every kind for renders: real app icons, generated pictures.
@MainActor
enum StripSamples {
    static func picture(_ colors: [NSColor], size: NSSize, sun: Bool = true) -> Data {
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: colors)?.draw(in: rect, angle: -90)
            if sun {
                NSColor.white.withAlphaComponent(0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: rect.width * 0.62, y: rect.height * 0.55, width: rect.height * 0.22,
                                            height: rect.height * 0.22)).fill()
            }
            NSColor.black.withAlphaComponent(0.35).setFill()
            let hills = NSBezierPath()
            hills.move(to: .zero)
            hills.curve(to: NSPoint(x: rect.width, y: rect.height * 0.25), controlPoint1: NSPoint(x: rect.width * 0.3, y: rect.height * 0.5),
                        controlPoint2: NSPoint(x: rect.width * 0.6, y: 0))
            hills.line(to: NSPoint(x: rect.width, y: 0))
            hills.close()
            hills.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        return rep.representation(using: .png, properties: [:])!
    }

    static func fill(_ store: StripFakeStore) {
        let now = Date()
        func app(_ id: String, _ name: String, _ color: String? = nil) -> AppRecord { AppRecord(bundleID: id, name: name, colorHex: color) }
        let notes = app("com.apple.Notes", "Notes"), safari = app("com.apple.Safari", "Safari"), mail = app("com.apple.mail", "Mail")
        let terminal = app("com.apple.Terminal", "Terminal"), preview = app("com.apple.Preview", "Preview")
        let finder = app("com.apple.finder", "Finder"), photos = app("com.apple.Photos", "Photos")
        func at(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        var drafts: [ClipDraft] = []
        drafts.append(.text("UA 1931 — SFO → EWR\nSeptember 12, 7:05 AM\nConfirmation: K7Q2LM\n\nUnited Airlines", sourceApp: mail,
                            copiedAt: at(2)))
        var link = ClipDraft.text("https://www.airbnb.com/rooms/48213", sourceApp: safari, copiedAt: at(120))
        let og = picture([NSColor(hex: "#F6A04D"), NSColor(hex: "#7A3E2B")], size: NSSize(width: 800, height: 420))
        link.link = LinkMetadata(url: "https://www.airbnb.com/rooms/48213", title: "Cabin near Muir Woods with a view",
                                 image: try? store.saveBlob(og))
        drafts.append(link)
        let photo = picture([NSColor(hex: "#F3B27A"), NSColor(hex: "#5C6E91")], size: NSSize(width: 1200, height: 900))
        drafts.append(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.png", data: photo)])], kind: .image,
                                sourceApp: photos, copiedAt: at(240), imageSize: PixelSize(width: 4032, height: 3024),
                                thumbnail: photo))
        drafts.append(.text("#FF6B35", sourceApp: preview, copiedAt: at(300)))
        drafts.append(.text("git rebase -i HEAD~3 && git push --force-with-lease origin feature/strip", sourceApp: terminal,
                            copiedAt: at(400)))
        drafts.append(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.file-url", data: Data("file:///etc/hosts".utf8))])],
                                kind: .files, sourceApp: finder, copiedAt: at(600), filePaths: ["/etc/hosts"]))
        drafts.append(.text("Remember to bring the charger, the blue notebook and the tickets for Saturday.", sourceApp: notes,
                            copiedAt: at(1500)))
        var bare = ClipDraft.text("https://developer.apple.com/documentation/appkit", sourceApp: safari, copiedAt: at(2000))
        bare.link?.title = "AppKit | Apple Developer Documentation"
        drafts.append(bare)
        drafts.append(ClipDraft(entries: [EntryData(reps: [RepData(type: "com.example.custom", data: Data([1, 2, 3]))])],
                                kind: .unknown, copiedAt: at(3000)))
        drafts.append(.text("#2E86DE", copiedAt: at(4000)))
        drafts.append(ClipDraft(entries: [EntryData(reps: [RepData(type: "public.file-url", data: Data())])], kind: .files,
                                sourceApp: finder, copiedAt: at(5000), filePaths: ["/etc/hosts", "/etc/shells", "/etc/zshrc"]))
        for i in 0..<12 {
            drafts.append(.text("Note \(i + 1): lorem ipsum dolor sit amet, consectetur adipiscing elit.", sourceApp: notes,
                                copiedAt: at(6000 + Double(i) * 60)))
        }
        for draft in drafts { _ = try? store.insert(draft) }
        if let board = try? store.createPinboard(name: "Travel", color: .orange), let first = store.all.first {
            try? store.assign([first.id], to: board.id)
        }
        _ = try? store.createPinboard(name: "Work", color: .purple)
        _ = try? store.createPinboard(name: "Snippets", color: .green)
    }
}
