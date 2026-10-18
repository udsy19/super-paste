import AppKit
import Carbon.HIToolbox
import Combine
import SuperPasteCore
import SettingsKit

// Owned by SettingsKit.
func registerSettingsKitTests() {
    SelfTest.cases.append(("SettingsKit.install", { MainActor.assumeIsolated {
        SettingsKitModule.install()
        check(Services.settings != nil && Services.onboarding != nil && Services.permissions != nil,
              "settings, onboarding and permissions registered")
        let names = [Services.settings as AnyObject, Services.onboarding as AnyObject, Services.permissions as AnyObject]
            .map { String(describing: type(of: $0)) }
        check(names == ["SettingsWindowController", "OnboardingController", "PermissionsController"], "the real services: \(names)")
        check(Services.onboarding.isCompleted == Defaults[.isOnboardingCompleted], "isCompleted reads the flag")
    } }))
    SelfTest.cases.append(("SettingsKit.shortcutRules", { MainActor.assumeIsolated { settingsShortcutRules() } }))
    SelfTest.cases.append(("SettingsKit.modifierChoices", { settingsModifierChoices() }))
    SelfTest.cases.append(("SettingsKit.historySlider", { settingsHistorySlider() }))
    SelfTest.cases.append(("SettingsKit.permissionFlow", { settingsPermissionFlow() }))
    SelfTest.cases.append(("SettingsKit.mcpConfig", { settingsMCPConfig() }))
    SelfTest.cases.append(("SettingsKit.syncStatus", { settingsSyncStatus() }))
    SelfTest.cases.append(("SettingsKit.ignoredApps", { settingsIgnoredApps() }))
    SelfTest.cases.append(("SettingsKit.welcomePinboard", { MainActor.assumeIsolated { settingsWelcomePinboard() } }))
    // Off-screen renders of every pane and screen, for checking the look: SUPERPASTE_RENDER_DIR=<folder>.
    if let folder = ProcessInfo.processInfo.environment["SUPERPASTE_RENDER_DIR"] {
        SelfTest.cases.append(("SettingsKit.render", { MainActor.assumeIsolated { settingsRender(to: URL(fileURLWithPath: folder)) } }))
    }
}

@MainActor private func settingsShortcutRules() {
    let pasteStack = Shortcut(key: kVK_ANSI_C, modifiers: [.shift, .command])
    let quit = Shortcut(key: kVK_ANSI_Q, modifiers: .command)
    let spotlight = SystemHotkey(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(cmdKey))
    var rules = ShortcutRules(assigned: [("Activate Paste Stack", pasteStack)], menuItems: [("Quit Super Paste", quit)],
                              systemHotkeys: [spotlight],
                              osVersion: OperatingSystemVersion(majorVersion: 15, minorVersion: 1, patchVersion: 0))
    check(rules.conflict(for: Shortcut(key: kVK_ANSI_V, modifiers: [.shift, .command])) == nil, "a free shortcut passes")
    check(rules.conflict(for: Shortcut(key: kVK_ANSI_V, modifiers: .option)) == .optionOnly, "⌥ alone warns before 15.2")
    check(rules.conflict(for: Shortcut(key: kVK_ANSI_V, modifiers: [.option, .shift])) == .optionOnly, "⌥⇧ too")
    check(rules.conflict(for: Shortcut(key: kVK_ANSI_V, modifiers: [.option, .command])) == nil
          && rules.conflict(for: Shortcut(key: kVK_ANSI_V, modifiers: [.option, .control])) == nil, "⌥ with ⌘ or ⌃ is fine")
    check(rules.conflict(for: pasteStack) == .inUse("Activate Paste Stack"), "another Super Paste shortcut")
    check(rules.conflict(for: quit) == .menuItem("Quit Super Paste"), "a menu item")
    check(rules.conflict(for: Shortcut(key: kVK_Space, modifiers: .command)) == .system, "a system-wide shortcut")
    check(rules.conflict(for: Shortcut(key: kVK_Space, modifiers: [.command, .option])) == nil, "modifiers must match exactly")
    rules.menuItems.append(("Copy", pasteStack))
    check(rules.conflict(for: pasteStack) == .inUse("Activate Paste Stack"), "own shortcuts are checked before menus")
    rules.osVersion = OperatingSystemVersion(majorVersion: 15, minorVersion: 2, patchVersion: 0)
    check(rules.conflict(for: Shortcut(key: kVK_ANSI_V, modifiers: .option)) == nil, "⌥ alone is fine from 15.2")
    check(ShortcutConflict.menuItem("Quit Super Paste").message.contains("‘Quit Super Paste’")
          && ShortcutConflict.inUse("Activate Paste Stack").message.contains("Activate Paste Stack")
          && ShortcutConflict.system.message.hasPrefix("This combination cannot be used"), "messages")

    let menu = NSMenu()
    let app = NSMenuItem(title: "Super Paste", action: nil, keyEquivalent: "")
    app.submenu = NSMenu()
    app.submenu?.addItem(NSMenuItem(title: "Quit Super Paste", action: nil, keyEquivalent: "q"))
    let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    edit.submenu = NSMenu()
    let redo = NSMenuItem(title: "Redo", action: nil, keyEquivalent: "z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.submenu?.addItem(redo)
    edit.submenu?.addItem(NSMenuItem(title: "No Key", action: nil, keyEquivalent: ""))
    menu.addItem(app); menu.addItem(edit)
    let items = ShortcutSources.menuItems(menu)
    check(items.map(\.title) == ["Quit Super Paste", "Redo"], "menu items with key equivalents, depth first")
    check(items.first?.shortcut == quit && items.last?.shortcut == Shortcut(key: kVK_ANSI_Z, modifiers: [.command, .shift]),
          "their shortcuts")
    let mask = UInt32(cmdKey | optionKey | controlKey | shiftKey)
    check(ShortcutSources.systemHotkeys().allSatisfy { $0.carbonModifiers & ~mask == 0 }, "system shortcuts keep only modifier bits")
}

private func settingsModifierChoices() {
    check(ModifierChoice(flags: Defaults[.quickPasteModifierFlags]) == .command
          && ModifierChoice(flags: Defaults[.plainTextModifierFlags]) == .shift, "defaults: ⌘ quick paste, ⇧ plain text")
    check(ModifierChoice(flags: NSEvent.ModifierFlags([.command, .option]).rawValue) == nil, "combinations aren't a choice")
    check(Set(ModifierChoice.allCases.map(\.flags.rawValue)).count == ModifierChoice.allCases.count, "distinct flags")
    check(!ModifierChoice.command.isAllowed(besides: .command) && ModifierChoice.option.isAllowed(besides: .command)
          && ModifierChoice.shift.isAllowed(besides: nil), "the other setting's modifier isn't offered")
}

private func settingsHistorySlider() {
    let stops: [(Double, String)] = [(1, "1 day"), (2, "1 week"), (3, "1 month"), (4, "1 year"), (5, "Forever")]
    for (value, label) in stops {
        check(HistoryLabel.text(forDays: HistoryRetention.days(forSlider: value)) == label, "slider stop \(value) reads \(label)")
    }
    check(HistoryLabel.text(forDays: 6) == "6 days" && HistoryLabel.text(forDays: 21) == "3 weeks"
          && HistoryLabel.text(forDays: 30) == "1 month" && HistoryLabel.text(forDays: 330) == "11 months", "between stops")
    for step in 0...400 {
        let days = HistoryRetention.days(forSlider: 1 + Double(step) / 100)
        if HistoryLabel.text(forDays: days).isEmpty { check(false, "every slider position has a label (\(days))") }
    }

    check(RetentionChange.evaluate(from: 30, to: 30) { _ in 9 } == RetentionChange.none, "no change")
    check(RetentionChange.evaluate(from: 30, to: 365) { _ in 9 } == .apply(days: 365), "a longer limit applies at once")
    check(RetentionChange.evaluate(from: 30, to: 0) { _ in 9 } == .apply(days: 0), "Forever applies at once")
    check(RetentionChange.evaluate(from: 30, to: 7) { $0 == 7 ? 12 : 0 } == .confirmPrune(days: 7, count: 12),
          "a shorter limit with older items asks first")
    check(RetentionChange.evaluate(from: 30, to: 7) { _ in 0 } == .apply(days: 7), "nothing older: no question")
    check(RetentionChange.evaluate(from: 0, to: 365) { _ in 3 } == .confirmPrune(days: 365, count: 3), "Forever to a limit asks")
}

private func settingsPermissionFlow() {
    let start = Date(timeIntervalSince1970: 1_000)
    var flow = PermissionFlow(granted: false)
    check(flow.phase == .needed && !flow.isGranted && !flow.showsIssueHelp, "starts by asking")
    flow.poll(granted: false, at: start)
    check(flow.phase == .needed, "polling alone doesn't start the wait")
    flow.openedSettings(at: start)
    check(flow.phase == .waiting(since: start), "System Settings opened: waiting")
    flow.poll(granted: false, at: start.addingTimeInterval(PermissionFlow.issueDelay - 1))
    check(flow.phase == .waiting(since: start), "still waiting before the delay")
    flow.poll(granted: false, at: start.addingTimeInterval(PermissionFlow.issueDelay))
    check(flow.phase == .issue && flow.showsIssueHelp, "no grant after the delay: offer help")
    flow.openedSettings(at: start.addingTimeInterval(60))
    check(flow.phase == .waiting(since: start.addingTimeInterval(60)), "opening again waits again")
    flow.poll(granted: true, at: start.addingTimeInterval(61))
    check(flow.isGranted, "granted")
    flow.openedSettings(at: start.addingTimeInterval(62))
    check(flow.isGranted, "stays granted")
    flow.poll(granted: false, at: start.addingTimeInterval(63))
    check(flow.phase == .needed, "a revoked grant asks again")
    check(PermissionFlow(granted: true).phase == .granted, "already granted")
}

private func settingsMCPConfig() {
    let url = MCPConfig.serverURL(port: 39725)
    check(url.absoluteString == "http://127.0.0.1:39725/mcp", "server URL")
    let http = MCPConfig.httpSnippet(url: url)
    let server = (jsonObject(http)?["mcpServers"] as? [String: Any])?[MCPConfig.serverName] as? [String: Any]
    check(server?["url"] as? String == url.absoluteString, "HTTP snippet is valid JSON with the URL")
    check(http.contains("\"url\": \"http://127.0.0.1:39725/mcp\""), "written the way configs usually are")
    let bridge = "/Applications/Super Paste.app/Contents/MacOS/super-paste-mcp"
    let stdio = MCPConfig.stdioSnippet(url: url, token: "to\"ken\\1", bridge: bridge)
    let command = (jsonObject(stdio)?["mcpServers"] as? [String: Any])?[MCPConfig.serverName] as? [String: Any]
    let env = command?["env"] as? [String: String]
    check(command?["command"] as? String == bridge && env?["MCP_URL"] == url.absoluteString && env?["MCP_TOKEN"] == "to\"ken\\1",
          "stdio snippet: bridge path and environment, escaped")
    check(MCPConfig.newPort(from: "40000", current: 39725) == 40000 && MCPConfig.newPort(from: " 40001 ", current: 39725) == 40001,
          "a new port")
    check(["39725", "80", "70000", "abc", ""].allSatisfy { MCPConfig.newPort(from: $0, current: 39725) == nil },
          "the same, privileged, out-of-range or non-numeric ports are refused")
}

private func jsonObject(_ text: String) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
}

private func settingsSyncStatus() {
    let now = Date()
    check(SyncStatus.syncing.statusLine(now: now) == "Syncing", "syncing")
    check(SyncStatus.synced(nil).statusLine(now: now) == "Synced: never", "never synced")
    check(SyncStatus.synced(now.addingTimeInterval(-10)).statusLine(now: now) == "Synced: just now", "just now")
    let hours = SyncStatus.synced(now.addingTimeInterval(-7_200)).statusLine(now: now)
    check(hours.hasPrefix("Synced: ") && hours.contains("2"), "relative date: \(hours)")
    check(SyncStatus.error("The folder is gone.").statusLine(now: now) == "The folder is gone.", "errors as they come")
    check(SyncStatus.disabled.statusLine(now: now).isEmpty, "nothing while off")
}

private func settingsIgnoredApps() {
    let calculator = URL(fileURLWithPath: "/System/Applications/Calculator.app")
    let list = IgnoredApps.adding([calculator, calculator, URL(fileURLWithPath: "/nonexistent/Nothing.app")],
                                  to: ["com.apple.Passwords"])
    check(list == ["com.apple.Passwords", "com.apple.calculator"], "adds each new bundle id once, skips non-apps: \(list)")
}

// MARK: - Off-screen renders

@MainActor private func settingsRender(to folder: URL) {
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    _ = NSApplication.shared
    let icon = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/AppIcon.icns")
    SettingsKitSnapshots.appIcon = NSImage(contentsOf: icon)
    let saved: (SyncServicing?, MCPServing?) = (Services.sync, Services.mcp)
    defer {
        Services.sync = saved.0
        Services.mcp = saved.1
        SettingsKitSnapshots.appIcon = nil
    }
    let sync = FakeSync()
    let mcp = FakeMCP()
    // The Shortcuts pane with its warning row: hold the activation shortcut, then try to register it again.
    if let activation = Defaults[.activationShortcut] {
        _ = HotkeyCenter.shared.register(activation, handler: {})
        _ = HotkeyCenter.shared.register(activation, handler: {})
    }
    defer {
        HotkeyCenter.shared.unregisterAll()
        HotkeyCenter.shared.forgetUnavailable()
    }
    Services.sync = sync
    Services.mcp = mcp
    do {
        var urls = try SettingsKitSnapshots.renderSettings(to: folder)
        sync.status = .synced(Date().addingTimeInterval(-300))
        sync.folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Super Paste")
        mcp.state = .running(MCPConfig.serverURL(port: 39725))
        Defaults[.isMCPEnabled] = true
        defer { Defaults.reset(.isMCPEnabled) }
        mcp.clients = [MCPClientInfo(name: "Editor", connection: .oauth, lastUsedAt: Date().addingTimeInterval(-3_600)),
                       MCPClientInfo(name: "Terminal Tool", connection: .token)]
        urls += try SettingsKitSnapshots.renderSettings([.sync, .integrations], tag: "-on", to: folder)
        urls += try SettingsKitSnapshots.renderOnboarding(to: folder)
        urls += try SettingsKitSnapshots.renderPermissions(to: folder)
        let sizes = urls.map { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? 0 }
        check(!urls.isEmpty && sizes.allSatisfy { $0 > 10_000 }, "every render wrote a PNG")
        print("  rendered \(urls.count) PNGs to \(folder.path)")
    } catch {
        check(false, "render failed: \(error)")
    }
}

@MainActor private final class FakeSync: SyncServicing {
    private let subject = CurrentValueSubject<SyncStatus, Never>(.disabled)
    var status: SyncStatus {
        get { subject.value }
        set { subject.value = newValue }
    }
    var statusChanges: AnyPublisher<SyncStatus, Never> { subject.eraseToAnyPublisher() }
    var folder: URL?
    var defaultFolder: URL? { nil }
    func enable(folder: URL) throws { self.folder = folder; status = .synced(nil) }
    func disable() { folder = nil; status = .disabled }
    func syncNow() {}
    func exportKey() -> String? { "key" }
    func importKey(_ text: String) throws {}
}

@MainActor private final class FakeMCP: MCPServing {
    private let stateSubject = CurrentValueSubject<MCPServerState, Never>(.off)
    private let clientSubject = CurrentValueSubject<[MCPClientInfo], Never>([])
    var state: MCPServerState {
        get { stateSubject.value }
        set { stateSubject.value = newValue }
    }
    var stateChanges: AnyPublisher<MCPServerState, Never> { stateSubject.eraseToAnyPublisher() }
    var port = 39725
    func start() { state = .running(MCPConfig.serverURL(port: port)) }
    func stop() { state = .off }
    func changePort(to port: Int) throws { self.port = port }
    var clients: [MCPClientInfo] {
        get { clientSubject.value }
        set { clientSubject.value = newValue }
    }
    var clientChanges: AnyPublisher<[MCPClientInfo], Never> { clientSubject.eraseToAnyPublisher() }
    func addTokenClient(name: String) throws -> (client: MCPClientInfo, token: String) {
        let client = MCPClientInfo(name: name, connection: .token)
        clients.append(client)
        return (client, "token")
    }
    func revoke(_ clientID: UUID) { clients.removeAll { $0.id == clientID } }
}

/// Quick Start's Continue seeds the Welcome pinboard once: four notes and three links with preview art, all
/// pinned-only; a second run (Help › Getting Started) reuses it; a deleted one is not recreated.
@MainActor private func settingsWelcomePinboard() {
    let saved = Services.store
    let store = StripFakeStore()
    Services.store = store
    defer { Services.store = saved; Defaults.reset(.welcomePinboardID) }
    _ = NSApplication.shared

    guard let board = WelcomeContent.seedIfNeeded() else { check(false, "seeds a pinboard"); return }
    check(board.name == WelcomeContent.pinboardName && Defaults[.welcomePinboardID] == board.id.uuidString, "remembered by id")
    let items = store.search(.empty, in: .pinboard(board.id), limit: 50, offset: 0)
    check(items.count == WelcomeContent.notes.count + WelcomeContent.links.count, "7 items: \(items.count)")
    check(items.allSatisfy { $0.copiedAt == nil && $0.isPinned(to: board.id) }, "pinned-only, so history stays empty")
    check(store.count(.empty, in: .history) == 0, "nothing in history")
    let texts = items.filter { $0.kind == .text }
    check(texts.map(\.title) == WelcomeContent.notes.map(\.title) && texts.first?.text.contains("⌘O") == true, "the notes, in order")
    let links = items.filter { $0.kind == .link }
    check(links.map(\.title) == WelcomeContent.links.map(\.title), "the links, in order")
    check(links.allSatisfy { $0.link?.image != nil && $0.link?.title != nil }, "links carry a title and preview art")
    if let art = links.first?.link?.image, let data = store.data(for: art), let image = NSImage(data: data) {
        check(image.size.width / image.size.height == 640.0 / 360.0, "16:9 art: \(image.size)")
    } else {
        check(false, "the art is stored as a blob")
    }
    check(WelcomeContent.seedIfNeeded()?.id == board.id && store.pinboards.count == 1, "a second run reuses the pinboard")
    try? store.deletePinboard(board.id)
    check(WelcomeContent.seedIfNeeded() == nil && store.pinboards.isEmpty, "a deleted Welcome pinboard stays deleted")
}
