import AppKit
import Carbon.HIToolbox
import SuperPasteCore

// Owned with SuperPasteCore: the contracts every module builds on.
func registerCoreTests() {
    SelfTest.cases.append(("Core.modelCodable", { coreModelCodable() }))
    SelfTest.cases.append(("Core.settingsDefaults", { coreSettingsDefaults() }))
    SelfTest.cases.append(("Core.searchQuery", { coreSearchQuery() }))
    SelfTest.cases.append(("Core.dateRanges", { coreDateRanges() }))
    SelfTest.cases.append(("Core.retentionSlider", { coreRetention() }))
    SelfTest.cases.append(("Core.retentionMigration", { coreRetentionMigration() }))
    SelfTest.cases.append(("Core.singleInstance", { coreSingleInstance() }))
    SelfTest.cases.append(("Core.hotCornerPolicy", { coreHotCornerPolicy() }))
    SelfTest.cases.append(("Core.themeMetrics", { coreThemeMetrics() }))
    SelfTest.cases.append(("Core.contentRules", { coreContentRules() }))
    SelfTest.cases.append(("Core.routes", { coreRoutes() }))
    SelfTest.cases.append(("Core.appColor", { MainActor.assumeIsolated { coreAppColor() } }))
    SelfTest.cases.append(("Core.appMenu", { MainActor.assumeIsolated { coreAppMenu() } }))
    SelfTest.cases.append(("Core.hotkeyConflicts", { MainActor.assumeIsolated { coreHotkeyConflicts() } }))
}

/// A combination another registration already holds fails and is listed as unavailable until it registers or is
/// forgotten; the wording names the shortcut.
@MainActor private func coreHotkeyConflicts() {
    let center = HotkeyCenter.shared
    let shortcut = Shortcut(key: kVK_F19, modifiers: [.command, .option, .control, .shift])
    var seen: [Set<Shortcut>] = []
    let watch = center.unavailableChanges.sink { seen.append($0) }
    defer { watch.cancel() }
    guard let first = center.register(shortcut, handler: {}) else { check(false, "a free combination registers"); return }
    check(center.unavailable.isEmpty, "nothing unavailable yet")
    let second = center.register(shortcut, handler: {})
    check(second == nil && center.unavailable == [shortcut], "the same combination again is unavailable")
    center.unregister(first)
    if let second { center.unregister(second) }
    check(center.register(shortcut, handler: {}).map { center.unregister($0); return true } == true && center.unavailable.isEmpty,
          "registering it again clears the mark")
    _ = center.register(shortcut, handler: {})  // held
    check(center.register(shortcut, handler: {}) == nil && !center.unavailable.isEmpty, "held again")
    center.forgetUnavailable()
    check(center.unavailable.isEmpty && seen.last == [], "forgetUnavailable clears it and publishes")
    center.unregisterAll()
    check(HotkeyConflict.title(shortcut) == "⌃⌥⇧⌘F19 is used by another app", "the notice names the shortcut")
}

private func roundTrip<T: Codable & Equatable>(_ value: T) -> Bool {
    guard let data = try? JSONEncoder().encode(value), let back = try? JSONDecoder().decode(T.self, from: data) else { return false }
    return back == value
}

private func coreModelCodable() {
    let pinboardID = UUID()
    let payload = Data("https://example.com".utf8)
    let app = AppRecord(bundleID: "com.apple.Safari", name: "Safari", colorHex: "#62A9F5", icon: BlobRef(of: Data("icon".utf8)))
    let item = ClipItem(
        createdAt: Date(timeIntervalSince1970: 1_800_000_000), updatedAt: Date(timeIntervalSince1970: 1_800_000_100),
        copiedAt: Date(timeIntervalSince1970: 1_800_000_050), lastUsedAt: Date(timeIntervalSince1970: 1_800_000_200),
        kind: .link, title: "Docs", text: "https://example.com", sourceApp: app,
        device: Device(id: "abc", name: "Studio", family: .mac, appVersion: "0.1.0"), byteSize: payload.count,
        checksum: "c0ffee", pins: [PinboardPin(pinboardID: pinboardID, order: 1.5)],
        payload: [PasteboardEntry(reps: [PasteboardRep(type: PasteboardType.plainText, blob: BlobRef(of: payload)),
                                         PasteboardRep(type: PasteboardType.urlName, blob: BlobRef(of: Data("Example".utf8)))])],
        imageSize: PixelSize(width: 640, height: 480), thumbnail: BlobRef(of: Data("thumb".utf8)), filePaths: ["/tmp/a b.txt"],
        link: LinkMetadata(url: "https://example.com", title: "Example", icon: BlobRef(of: Data("fav".utf8)),
                           image: BlobRef(of: Data("og".utf8)), fetchedAt: Date(timeIntervalSince1970: 1_800_000_300)))
    check(roundTrip(item), "ClipItem with every field")
    check(roundTrip(ClipItem(kind: .unknown)), "ClipItem with only defaults")
    check(item.pinboardIDs == [pinboardID] && item.isPinned && item.isPinned(to: pinboardID) && item.isInHistory, "pin helpers")
    check(item.blobRefs.count == 6, "blobRefs: two reps, thumbnail, favicon, link image, app icon")
    check(item.payload[0].rep(PasteboardType.urlName) != nil && item.payload[0].rep("public.png") == nil, "rep lookup")

    let long = String(repeating: "a", count: 25_000)
    let big = ClipItem(kind: .text, text: long)
    check(big.text.count == ClipItem.previewTextLimit && big.textLength == 25_000, "text is capped, length kept")
    check(ClipItem(copiedAt: nil, kind: .text).isInHistory == false, "pinned-only items aren't in history")

    let board = Pinboard(name: "Work", color: .purple, order: 2, shortcut: Shortcut(key: kVK_ANSI_1, modifiers: [.control, .option]))
    check(roundTrip(board), "Pinboard with a shortcut")
    check(roundTrip(SyncRecord.item(item)) && roundTrip(SyncRecord.pinboard(board)), "sync records")
    let tombstone = SyncRecord.tombstone(SyncTombstone(entity: .item, id: item.id, deletedAt: Date(timeIntervalSince1970: 1)))
    check(roundTrip(tombstone) && tombstone.updatedAt == Date(timeIntervalSince1970: 1), "tombstone")
    check(roundTrip(JournalEntry(sequence: 42, record: tombstone)), "journal entry")
    check(roundTrip(SearchQuery(parsing: "meeting app:Mail")), "SearchQuery")
    check(roundTrip(MCPClientInfo(name: "Editor", connection: .token)), "MCP client")
    check(roundTrip(MCPClientInfo(name: "Desk Assistant", connection: .oauth, lastUsedAt: Date())), "MCP client kind")
    let legacy = Data(#"{"id":"\#(UUID().uuidString)","name":"Old","connection":"token","createdAt":0}"#.utf8)
    check((try? JSONDecoder().decode(MCPClientInfo.self, from: legacy))?.name == "Old", "a saved client reads back")
    for scope in [ListScope.history, .all, .pinboard(pinboardID)] {
        check(ListScope(id: scope.id) == scope && roundTrip(scope), "ListScope \(scope.id)")
    }
    check(ListScope(id: "clipboard") == .history && ListScope(id: "nope") == nil, "list ids")
}

private func coreSettingsDefaults() {
    check(Defaults[.openAtLogin] == false && Defaults[.isStatusItemEnabled] && Defaults[.isSoundEffectsEnabled], "general toggles")
    check(Defaults[.isDirectPasteEnabled] && !Defaults[.isPasteAsPlainTextEnabled], "paste to active app, rich text")
    check(Defaults[.historyRetentionDays] == HistoryRetention.forever && !Defaults[.historyRetentionUserSet]
          && !Defaults[.isDirectPastePromptSuppressed], "Keep History forever, untouched; direct-paste prompt")
    check(Defaults[.hotCorner] == .bottomLeft, "the hot corner is the bottom-left one")
    let apps = Defaults[.ignoredBundleIdentifiers]
    check(apps.count == 14 && apps.first == "com.apple.Passwords" && apps.last == ".nordpass", "14 password managers, in order")
    let types = Defaults[.ignoredPasteboardTypes]
    check(types.count == 6 && Set(types) == Set(CaptureDefaults.confidentialTypes + CaptureDefaults.transientTypes),
          "six ignored types: the confidential and transient sets")
    check(Defaults.ignoresConfidentialContent && Defaults.ignoresTransientContent, "both privacy toggles on")
    check(Defaults[.isLinkPreviewsEnabled] && Defaults[.isScreenSharingContentVisible] && Defaults[.isFileItemQLThumbnailImageEnabled],
          "privacy defaults")

    let activation = Defaults[.activationShortcut]
    check(activation?.keyCode == 9 && activation?.modifierFlags == 1_179_648, "⇧⌘V, stored like the reference ({9, 1179648})")
    check(Defaults[.pasteStackShortcut] == Shortcut(key: kVK_ANSI_C, modifiers: [.shift, .command]), "⇧⌘C")
    check(Defaults[.nextPinboardShortcut] == Shortcut(key: kVK_RightArrow, modifiers: [.command])
          && Defaults[.previousPinboardShortcut] == Shortcut(key: kVK_LeftArrow, modifiers: [.command]), "⌘→ / ⌘←")
    check(Defaults[.quickPasteModifierFlags] == 0x100000 && Defaults[.plainTextModifierFlags] == 0x20000, "⌘ quick paste, ⇧ plain text")
    check(Defaults[.pasteStackDirection] == .top && Defaults[.stripHeight] == 332, "stack direction, strip height")
    check(Defaults[.selectedListIdentifier] == "history", "opens on the history")
    check(!Defaults[.isSyncEnabled] && Defaults[.syncFolderPath].isEmpty && Defaults[.lastSyncDate] == 0, "sync off")
    check(!Defaults[.isMCPEnabled] && Defaults[.mcpPort] == 39725, "MCP off on 39725")
    check(Defaults[.installUpdates] && !Defaults[.isOnboardingCompleted] && Defaults[.suppressedWarnings].isEmpty, "updates on")

    // Writes read back with their types.
    Defaults[.quickPasteModifierFlags] = NSEvent.ModifierFlags.option.rawValue
    check(Defaults[.quickPasteModifierFlags] == NSEvent.ModifierFlags.option.rawValue, "UInt modifier flags")
    Defaults[.pasteStackDirection] = .bottom
    check(Defaults[.pasteStackDirection] == .bottom, "enum setting")
    Defaults[.activationShortcut] = Shortcut(key: kVK_ANSI_P, modifiers: [.option, .command])
    check(Defaults[.activationShortcut] == Shortcut(key: kVK_ANSI_P, modifiers: [.option, .command]), "shortcut setting")
    Defaults[.activationShortcut] = nil
    check(Defaults[.activationShortcut] == nil, "a removed shortcut stays removed")
    Defaults.reset(.activationShortcut)
    check(Defaults[.activationShortcut]?.keyCode == 9, "reset brings the default back")
    Defaults.ignoresConfidentialContent = false
    check(!Defaults[.ignoredPasteboardTypes].contains(PasteboardType.concealed) && Defaults.ignoresTransientContent,
          "turning off confidential leaves transient")
    Defaults.ignoresConfidentialContent = true
    check(Defaults.ignoresConfidentialContent && Defaults[.ignoredPasteboardTypes].count == 6, "and back on")
    for key in [Defaults.Keys.quickPasteModifierFlags.name, Defaults.Keys.pasteStackDirection.name,
                Defaults.Keys.ignoredPasteboardTypes.name] {
        Defaults.store.removeObject(forKey: key)
    }
}

private func coreSearchQuery() {
    let q = SearchQuery(parsing: "meeting slides app:Mail type:link")
    check(q.tokens == ["meeting", "slides"], "tokens")
    check(q.filters == [.init(.app, "Mail"), .init(.type, "link")], "filters")
    check(q.kinds == [.link], "type filter resolves to kinds")

    let quoted = SearchQuery(parsing: #"app:"Visual Studio Code" "exact phrase"  title:invoice"#)
    check(quoted.values(.app) == ["Visual Studio Code"] && quoted.tokens == ["exact phrase"] && quoted.values(.title) == ["invoice"],
          "quoted values and phrases")
    check(SearchQuery(parsing: "APP:Safari").values(.app) == ["Safari"], "keys ignore case")
    check(SearchQuery(parsing: "app:").isEmpty && SearchQuery(parsing: "  \t ").isEmpty && SearchQuery(parsing: "").isEmpty,
          "half-typed filter and blanks")
    check(SearchQuery(parsing: "https://example.com").tokens == ["https://example.com"], "URLs are tokens")
    check(SearchQuery(parsing: #""app:Mail""#).tokens == ["app:Mail"], "a quoted word is never a filter")
    check(SearchQuery(parsing: "foo:bar").tokens == ["foo:bar"], "unknown keys are tokens")
    check(SearchQuery(parsing: #"date:"last 7 days" pinboard:Work device:Studio"#).filters
          == [.init(.date, "last 7 days"), .init(.pinboard, "Work"), .init(.device, "Studio")], "date, pinboard, device")
    check(SearchQuery(parsing: #""open ended phrase"#).tokens == ["open ended phrase"], "an unclosed quote runs to the end")

    for text in ["meeting app:Mail", #"app:"Visual Studio Code" "two words""#, #""app:Mail" type:image date:today"#] {
        let parsed = SearchQuery(parsing: text)
        check(SearchQuery(parsing: parsed.text) == parsed, "canonical text round-trips: \(text)")
    }
    check(SearchQuery(parsing: "  meeting   app:Mail ").text == "meeting app:Mail", "canonical text")

    check(SearchQuery(parsing: "type:links type:image").kinds == [.link, .image], "same-type filters OR together")
    check(SearchQuery(parsing: "type:text").kinds == [.text, .richText, .html], "text covers rich text and HTML")
    check(SearchQuery(parsing: "type:bogus").kinds == [], "an unknown type matches nothing")
    check(SearchQuery(parsing: "hello").kinds == nil, "no type filter")

    let added = q.adding(.init(.app, "Notes")).adding(.init(.app, "Notes"))
    check(added.values(.app) == ["Mail", "Notes"], "adding is idempotent")
    check(added.removing(.init(.app, "Mail")).values(.app) == ["Notes"], "removing")
}

private func coreDateRanges() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let iso = ISO8601DateFormatter()
    func d(_ s: String) -> Date { iso.date(from: s.count == 10 ? s + "T00:00:00Z" : s)! }
    let now = d("2026-10-17T15:30:00Z")
    func r(_ value: String) -> DateRange? { DateRange.parse(value, now: now, calendar: calendar) }

    check(r("today") == DateRange(start: d("2026-10-17"), end: d("2026-10-18")), "today")
    check(r("Yesterday") == DateRange(start: d("2026-10-16"), end: d("2026-10-17")), "yesterday")
    check(r("last 7 days") == DateRange(start: d("2026-10-11"), end: d("2026-10-18")), "last 7 days")
    check(r("last7days") == r("last 7 days") && r("past-7-days") == r("last 7 days"), "spellings")
    check(r("last 30 days")?.start == d("2026-09-18"), "last 30 days")
    check(r("last 2 weeks")?.start == d("2026-10-04"), "last 2 weeks")
    check(r("this month") == DateRange(start: d("2026-10-01"), end: d("2026-11-01")), "this month")
    check(r("2026-10-01") == DateRange(start: d("2026-10-01"), end: d("2026-10-02")), "a date is that whole day")
    check(r("2026-10-01..2026-10-05") == DateRange(start: d("2026-10-01"), end: d("2026-10-06")), "a range covers its last day")
    check(r("2026-10-01 to 2026-10-05") == r("2026-10-01..2026-10-05"), "X to Y")
    check(r("2026-10-01..") == DateRange(start: d("2026-10-01"), end: nil), "open end")
    check(r("..2026-10-05") == DateRange(start: nil, end: d("2026-10-06")), "open start")
    check(r("yesterday..today") == DateRange(start: d("2026-10-16"), end: d("2026-10-18")), "keywords in ranges")
    check(r("2026-10-01T09:00:00Z..2026-10-01T10:00:00Z") == DateRange(start: d("2026-10-01T09:00:00Z"),
                                                                      end: d("2026-10-01T10:00:00Z")), "date-times")
    check(r("2026-10-05..2026-10-01") == nil, "a range ending before it starts")
    check(r("2026-10-01T09:00:00Z") == nil && r("garbage") == nil && r("..") == nil && r("last 0 days") == nil, "rejected")

    let today = r("today")!
    check(today.contains(d("2026-10-17")) && today.contains(d("2026-10-17T23:59:59Z")) && !today.contains(d("2026-10-18")),
          "start inclusive, end exclusive")
    check(SearchQuery(parsing: "date:today date:bogus").dateRanges(now: now, calendar: calendar)?.count == 1, "bad values drop out")
    check(SearchQuery(parsing: "x").dateRanges(now: now, calendar: calendar) == nil, "no date filter")
}

/// An install left on 1.0.1's 30-day default moves to Forever once; a value the user chose stays, 30 included.
private func coreRetentionMigration() {
    defer { Defaults.reset(.historyRetentionDays); Defaults.reset(.historyRetentionUserSet) }
    check(!HistoryRetention.migrateLegacyDefault() && Defaults[.historyRetentionDays] == 0, "a fresh install has nothing to migrate")
    Defaults[.historyRetentionDays] = 30
    check(HistoryRetention.migrateLegacyDefault() && Defaults[.historyRetentionDays] == 0, "the old default becomes Forever")
    check(!HistoryRetention.migrateLegacyDefault(), "only once")
    Defaults[.historyRetentionDays] = 30
    Defaults[.historyRetentionUserSet] = true
    check(!HistoryRetention.migrateLegacyDefault() && Defaults[.historyRetentionDays] == 30, "30 days the user chose stays")
    Defaults[.historyRetentionUserSet] = false
    Defaults[.historyRetentionDays] = 7
    check(!HistoryRetention.migrateLegacyDefault() && Defaults[.historyRetentionDays] == 7, "other values aren't touched")
}

/// The hot corner steps aside when macOS's own Hot Corners use the same corner.
private func coreHotCornerPolicy() {
    check(!HotCornerPolicy.systemUsesCorner(nil) && !HotCornerPolicy.systemUsesCorner(0) && !HotCornerPolicy.systemUsesCorner(1),
          "unset, 0 and 1 mean no macOS action")
    check(HotCornerPolicy.systemUsesCorner(2) && HotCornerPolicy.systemUsesCorner(14), "any other value is an action")
    check(HotCornerPolicy.effective(.bottomLeft) { _ in nil } == .bottomLeft, "free corner: watched")
    check(HotCornerPolicy.effective(.bottomLeft) { $0 == .bottomLeft ? 5 : nil } == .off, "a corner macOS uses: off")
    check(HotCornerPolicy.effective(.topRight) { $0 == .bottomLeft ? 5 : nil } == .topRight, "another corner is fine")
    check(HotCornerPolicy.effective(.off) { _ in 5 } == .off, "off stays off")
    check(HotCorner.off.dockDefaultsKey == nil && HotCorner.bottomLeft.dockDefaultsKey == "wvous-bl-corner"
          && HotCorner.topRight.dockDefaultsKey == "wvous-tr-corner", "Dock keys")
    check(HotCorner.allCases.map(\.rawValue) == ["off", "bottomLeft", "bottomRight", "topLeft", "topRight"], "stored names")
}

private func coreRetention() {
    let days = HistoryRetention.days(forSlider:)
    check(days(1) == 1 && days(1.5) == 4 && days(2) == 7, "days segment")
    check(days(2.34) == 14 && days(2.67) == 21 && days(2.99) == 30, "weeks segment; 28 snaps to 30")
    check(days(3) == 30 && days(3.5) == 210 && days(3.99) == 365, "months segment; 360 snaps to 365")
    check(days(4) == 365 && days(4.4) == 365 && days(4.5) == 0 && days(5) == 0, "a year, then Forever")
    check(days(0) == 1 && days(9) == 0, "clamped to the slider")

    var produced = Set<Int>()
    for step in 0...400 { produced.insert(days(1 + Double(step) / 100)) }
    check(produced.allSatisfy { days(HistoryRetention.sliderValue(forDays: $0)) == $0 }, "every stored value maps back to itself")
    check(produced.contains(30) && !produced.contains(28) && !produced.contains(360), "snapped values")
    check(HistoryRetention.sliderValue(forDays: 0) == 5 && HistoryRetention.sliderValue(forDays: 365) == 4
          && HistoryRetention.sliderValue(forDays: 7) == 2 && HistoryRetention.sliderValue(forDays: 30) == 3, "stops")
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    check(HistoryRetention.cutoff(days: 0, now: now) == nil && HistoryRetention.cutoff(days: 1, now: now) == now.addingTimeInterval(-86_400),
          "cutoff")
}

private func coreThemeMetrics() {
    check(SPStyle.forSystem(majorVersion: 26) == .glass && SPStyle.forSystem(majorVersion: 27) == .glass, "macOS 26+: glass")
    check(SPStyle.forSystem(majorVersion: 15) == .classic && SPStyle.forSystem(majorVersion: 14) == .classic, "macOS 14/15: classic")
    check(SPStyle.current == SPStyle.forSystem(majorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
          && SPMetrics.current.style == SPStyle.current, "current follows the running system")

    let glass = SPMetrics(style: .glass), classic = SPMetrics(style: .classic)
    check(glass.panelCornerRadius == 26 && classic.panelCornerRadius == 0, "panel radius")
    check(glass.cardCornerRadius == 16 && classic.cardCornerRadius == 10, "card radius")
    check(glass.selectionRingRadius == 20 && classic.selectionRingRadius == 14, "selection ring = card + 4")
    check(glass.panelInsets.left == 8 && glass.panelInsets.bottom == 8 && glass.panelInsets.top == 0
          && classic.panelInsets.left == 0, "glass slab inset")
    check(glass.cardSide(panelHeight: 332) == 232 && classic.cardSide(panelHeight: 332) == 240, "card side at the default height")
    check(glass.sizeClass(panelHeight: 332) == .small && classic.sizeClass(panelHeight: 332) == .regular, "default size class")
    check(glass.sizeClass(panelHeight: 252) == .compact && classic.sizeClass(panelHeight: 252) == .compact, "minimum height")
    check(glass.sizeClass(panelHeight: 412) == .large && classic.sizeClass(panelHeight: 412) == .large, "maximum height")
    check(CardSizeClass(cardSide: 280) == .large && CardSizeClass(cardSide: 279.5) == .regular && CardSizeClass(cardSide: 240) == .regular
          && CardSizeClass(cardSide: 239) == .small && CardSizeClass(cardSide: 200) == .small && CardSizeClass(cardSide: 199) == .compact,
          "size-class thresholds")
    check(glass.headerHeight(.compact) == 36 && classic.headerHeight(.compact) == 34 && glass.headerHeight(.large) == 56,
          "header heights")
    check(glass.cardShadow.alpha == 0.08 && glass.cardShadow.offset == .zero
          && classic.cardShadow.alpha == 0.10 && classic.cardShadow.offset.height == -1, "card shadow")
    check(glass.toolbarButtonRadius(height: 32, large: true) == 16 && classic.toolbarButtonRadius(height: 32, large: true) == 6
          && classic.toolbarButtonRadius(height: 22, large: false) == 5, "toolbar buttons")
    check(SPMetrics.Strip.clampedHeight(100) == 252 && SPMetrics.Strip.clampedHeight(500) == 412
          && SPMetrics.Strip.clampedHeight(300) == 300, "strip height clamp")
    check(SPColor.pinboardHex(.yellow) == "#FAB700" && SPColor.pinboardHex(.gray) == "#8F8F93", "pinboard hex codes")
    let yellow = NSColor(hex: "#F2B600").usingColorSpace(.sRGB)!
    check(abs(yellow.redComponent - 0.949) < 0.001 && abs(yellow.greenComponent - 0.714) < 0.001 && yellow.blueComponent == 0,
          "hex colours")
    check(NSColor(hex: "#00000080").alphaComponent > 0.5 && NSColor(hex: "#00000080").alphaComponent < 0.51, "#RRGGBBAA")
    let darkInk = SPColor.ink50.resolved(for: .darkAqua), lightInk = SPColor.ink50.resolved(for: .aqua)
    check(abs(darkInk.alphaComponent - 0.55) < 0.001 && abs(lightInk.alphaComponent - 0.5) < 0.001, "light/dark ink")
}

private extension NSColor {
    func resolved(for name: NSAppearance.Name) -> NSColor {
        var color = self
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance { color = self.usingColorSpace(.sRGB)! }
        return color
    }
}

private func coreContentRules() {
    check(TextClassifier.kind(of: "#ff00AA") == .color && TextClassifier.colorHex(in: "  ff00aa\n") == "#FF00AA", "colours")
    check(TextClassifier.kind(of: "#ff00a") == .text && TextClassifier.kind(of: "#ff00aag") == .text, "not colours")
    check(TextClassifier.kind(of: "https://example.com/a?b=1") == .link && TextClassifier.kind(of: "http://localhost:8080") == .link,
          "links")
    check(TextClassifier.linkURL(in: "www.example.com")?.absoluteString == "https://www.example.com", "www. gets https")
    check(TextClassifier.kind(of: "example.com") == .text && TextClassifier.kind(of: "see https://example.com") == .text
          && TextClassifier.kind(of: "https://") == .text, "not links")
    let draft = ClipDraft.text("https://example.com")
    check(draft.kind == .link && draft.link?.url == "https://example.com" && draft.copiedAt != nil, "text draft")
    check(ClipDraft.text("note", pinboardID: UUID()).copiedAt != nil, "a text draft is in history unless told otherwise")
    check(draft.byteSize == 19 && draft.checksum == ClipChecksum.of(draft.entries), "draft size and checksum")

    func entry(_ reps: [(String, String)]) -> EntryData { EntryData(reps: reps.map { RepData(type: $0.0, data: Data($0.1.utf8)) }) }
    let a = ClipChecksum.of([entry([("public.utf8-plain-text", "hi"), ("public.html", "<b>hi</b>")])])
    check(a == ClipChecksum.of([entry([("public.html", "<b>hi</b>"), ("public.utf8-plain-text", "hi")])]), "type order doesn't matter")
    check(a == ClipChecksum.of([entry([("public.utf8-plain-text", "hi"), (PasteboardType.source, "com.apple.Safari"),
                                       ("public.html", "<b>hi</b>"), (PasteboardType.itemID, "x")])]), "volatile types ignored")
    check(a != ClipChecksum.of([entry([("public.utf8-plain-text", "hi")]), entry([("public.html", "<b>hi</b>")])]),
          "entry boundaries count")
    check(a != ClipChecksum.of([entry([("public.utf8-plain-text", "ho"), ("public.html", "<b>hi</b>")])]), "content counts")
    check(BlobRef(of: Data("abc".utf8)) == BlobRef(digest: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", size: 3),
          "blob digests are SHA-256")

    check(ItemTypeFilter(filterValue: "Colours") == .color && ItemTypeFilter(filterValue: "url") == .link
          && ItemTypeFilter(filterValue: "nope") == nil, "type filter values")
    check(ItemKind.richText.typeFilter == .text && ItemKind.files.typeFilter == .file && ItemKind.html.isText, "kind groups")
    let device = Device.current
    check(device.id.count == 32 && device.id.allSatisfy(\.isHexDigit) && !device.name.isEmpty && device.family == .mac, "this Mac")
}

private func coreRoutes() {
    func route(_ s: String) -> AppRoute? { AppRoute(url: URL(string: s)!) }
    let id = UUID()
    check(route("superpaste://") == .strip(nil) && route("SuperPaste://") == .strip(nil), "bare scheme shows the strip")
    check(route("superpaste://new-text-item") == .strip(.newTextItem), "new text item")
    check(route("superpaste://search?q=app%3AMail%20link") == .strip(.search("app:Mail link")), "search")
    check(route("superpaste://list/history") == .strip(.list(.history)), "history")
    check(route("superpaste://list/\(id.uuidString)") == .strip(.list(.pinboard(id))), "pinboard")
    check(route("superpaste://preview-item/\(id.uuidString)") == .strip(.preview(id)), "preview")
    check(route("superpaste://edit-item/\(id.uuidString)") == .strip(.edit(id)), "edit")
    check(route("superpaste://settings") == .settings(nil) && route("superpaste://settings/privacy") == .settings(.privacy), "settings")
    check(route("superpaste://about") == .settings(.about) && route("superpaste://enable-sync") == .settings(.sync), "about, sync")
    check(route("superpaste://enable-direct-paste") == .enableDirectPaste, "enable direct paste")
    check(route("superpaste://enable-open-at-login") == .enableOpenAtLogin
          && route("superpaste://enable-run-in-background") == .enableOpenAtLogin, "enable open at login")
    check(route("superpaste://settings/bogus") == nil && route("superpaste://bogus") == nil && route("https://example.com") == nil
          && route("superpaste://preview-item/nope") == nil && route("superpaste://list") == nil, "rejected")
}

/// The header colour rule shared by ClipboardKit (at capture) and StripKit (for records without one).
@MainActor private func coreAppColor() {
    check(AppColor.known("com.apple.Safari") == "#62A9F5" && AppColor.known("COM.APPLE.FINDER") == "#62A9F5", "known apps")
    check(AppColor.known("com.adobe.Photoshop") == "#005C90" && AppColor.known("com.apple.Terminal") == "#454D4D", "table entries")
    check(AppColor.known("com.example.unknown") == nil, "unknown apps have no built-in colour")

    func pixels(_ list: [(UInt8, UInt8, UInt8, UInt8, Int)]) -> [UInt8] {
        list.flatMap { r, g, b, a, n in Array(repeating: [r, g, b, a], count: n).flatMap { $0 } }
    }
    // Pure red: saturation capped at 0.85, brightness clamped to 0.96.
    check(AppColor.derive(rgba: pixels([(255, 0, 0, 255, 10), (128, 128, 128, 255, 50)])) == "#F52525",
          "most frequent saturated colour, gray ignored")
    check(AppColor.derive(rgba: pixels([(0, 0, 100, 255, 5), (255, 0, 0, 128, 50)])) == "#0F0F64",
          "dark colours keep their brightness; translucent pixels don't count")
    check(AppColor.derive(rgba: pixels([(130, 40, 40, 255, 10)])) == "#BF3B3B", "brightness over 0.4 rises to at least 0.75")
    check(AppColor.derive(rgba: pixels([(200, 140, 140, 255, 3)])) == "#C88C8C", "saturation 0.3, brightness in range: unchanged")
    check(AppColor.derive(rgba: pixels([(200, 150, 150, 255, 3)])) == nil, "saturation 0.25 is not above 0.25")
    check(AppColor.derive(rgba: pixels([(128, 128, 128, 255, 9), (255, 255, 255, 255, 9)])) == nil, "all gray: nil")
    check(AppColor.derive(rgba: []) == nil, "no pixels: nil")
    check(AppColor.derive(rgba: pixels([(0, 0, 255, 255, 2), (255, 0, 0, 255, 2)])) ==
          AppColor.derive(rgba: pixels([(255, 0, 0, 255, 2), (0, 0, 255, 255, 2)])), "ties don't depend on order")

    // A real image goes through the same rule.
    let icon = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
        NSColor(srgbRed: 0.1, green: 0.4, blue: 0.9, alpha: 1).setFill()
        rect.fill()
        return true
    }
    let blue = AppColor.derive(from: icon).map { NSColor(hex: $0) }
    var hue: CGFloat = 0
    blue?.getHue(&hue, saturation: nil, brightness: nil, alpha: nil)
    check(blue != nil && abs(hue - 0.6) < 0.03, "image → blue (\(blue?.hexString ?? "nil"))")
    check(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1).hexString == "#FF8000" && NSColor(hex: "#62A9F5").hexString == "#62A9F5",
          "hexString")
}

/// The app menu shared by the menu bar item and the strip's "…" button (behaviour.md §6.2, §6.3).
@MainActor private func coreAppMenu() {
    let saved = Services.clipboard
    defer { Services.clipboard = saved }
    func titles(_ menu: NSMenu) -> [String] { menu.items.map { $0.isSeparatorItem ? "—" : $0.title } }
    func choose(_ menu: NSMenu, _ index: Int) {
        let item = menu.items[index]
        if let action = item.action { _ = (item.target as AnyObject?)?.perform(action, with: item) }
    }

    let running = StripFakeClipboard(state: .running)
    Services.clipboard = running
    let menu = AppMenu.make()
    check(titles(menu) == ["About Super Paste", "—", "New Text Item", "Settings…", "—", "Help", "—", "Pause", "—", "Quit Super Paste"],
          "items and order: \(titles(menu))")
    check(!titles(menu).contains { $0.localizedCaseInsensitiveContains("update") }, "no update item: updates are automatic")
    func key(_ title: String) -> String? {
        menu.items.first { $0.title == title }.map { item in
            Shortcut(keyEquivalent: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)?.displayString ?? ""
        }
    }
    check(key("New Text Item") == "⌘N" && key("Settings…") == "⌘," && key("Quit Super Paste") == "⌘Q" && key("About Super Paste") == "",
          "shortcuts")
    let help = menu.items.first { $0.title == "Help" }?.submenu
    check(help.map(titles) == ["Getting Started", "Keyboard Shortcuts", "Help Center", "—", "Feature Request", "Contact Support"],
          "Help submenu: \(help.map(titles) ?? [])")
    check(help?.items.allSatisfy { $0.isSeparatorItem || $0.keyEquivalent.isEmpty } == true, "help items have no shortcuts")

    let pause = AppMenu.makePauseMenu()
    check(titles(pause) == ["Pause for 15m", "Pause for 30m", "Pause for 1h", "Pause for 3h", "Pause for 8h", "—", "Until I Resume"],
          "pause menu while capturing: \(titles(pause))")
    check(pause.items.last?.keyEquivalent == "t", "Until I Resume is ⌘T")
    let before = Date()
    choose(pause, 2)
    choose(pause, 6)
    check(running.pauses.count == 2 && running.pauses.last == .some(nil), "until resumed: no end date")
    check(running.pauses.first.flatMap { $0 }.map { abs($0.timeIntervalSince(before) - 3600) < 5 } ?? false,
          "Pause for 1h ends in an hour")

    let until = Calendar.current.date(bySettingHour: 14, minute: 30, second: 0, of: Date())!
    let paused = StripFakeClipboard(state: .paused(until: until))
    Services.clipboard = paused
    let status = "Paused until \(until.formatted(date: .omitted, time: .shortened))"
    check(AppMenu.pauseStatus == status && AppMenu.make().items[7].title == status, "the Pause item shows when it ends")
    let resume = AppMenu.makePauseMenu()
    check(titles(resume).prefix(3) == [status, "Resume", "—"] && resume.items[0].isEnabled == false
          && resume.items[1].keyEquivalent == "t" && resume.items.count == 8, "while paused: status, Resume ⌘T, the durations")
    choose(resume, 1)
    check(paused.resumes == 1, "Resume resumes")
    Services.clipboard = StripFakeClipboard(state: .paused(until: nil))
    check(AppMenu.pauseStatus == "Paused", "paused until resumed")

    check(!AppMenu.opensFromStatusItem(.leftMouseUp, modifiers: []), "left click toggles the strip")
    check(AppMenu.opensFromStatusItem(.rightMouseUp, modifiers: []) && AppMenu.opensFromStatusItem(.leftMouseUp, modifiers: .control)
          && AppMenu.opensFromStatusItem(.leftMouseUp, modifiers: .option), "right, Control- and Option-click open the menu")
    check(!AppMenu.opensFromStatusItem(.leftMouseUp, modifiers: .command), "Command-click doesn't")
}

private func coreSingleInstance() {
    check(SingleInstance.other(among: [(10, false)], own: 10) == nil, "alone")
    check(SingleInstance.other(among: [(10, false), (20, true)], own: 10) == nil, "a copy that already quit doesn't count")
    check(SingleInstance.other(among: [(20, false), (10, false)], own: 10) == 20, "the other running copy")
    check(SingleInstance.other(among: [], own: 10) == nil, "not even itself listed yet")
}
