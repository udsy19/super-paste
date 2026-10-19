import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers
import SuperPasteCore

/// Folder sync through `Services.sync`, for the Sync pane and the onboarding switch.
@MainActor
final class SyncModel: ObservableObject {
    @Published private(set) var status: SyncStatus
    @Published private(set) var folder: URL?
    private let service: SyncServicing?
    private var cancellable: AnyCancellable?

    init(service: SyncServicing?) {
        self.service = service
        status = service?.status ?? .disabled
        folder = service?.folder
        cancellable = service?.statusChanges.receive(on: DispatchQueue.main).sink { [weak self] status in
            MainActor.assumeIsolated {
                self?.status = status
                self?.folder = self?.service?.folder
            }
        }
    }

    var isEnabled: Bool { status != .disabled }

    /// Turning on asks for the folder first; turning off asks for confirmation.
    func setEnabled(_ enabled: Bool) {
        guard let service, enabled != isEnabled else { return }
        if enabled {
            guard let folder = chooseFolder() else { return }
            start(service, in: folder)
        } else {
            guard Alerts.confirm(Strings.Sync.turnOffTitle, info: Strings.Sync.turnOffText,
                                 confirmTitle: Strings.Sync.turnOff, cancelTitle: Strings.Sync.keepOn) else { return }
            service.disable()
        }
        refresh()
    }

    /// Moves sync to another folder.
    func changeFolder() {
        guard let service, let folder = chooseFolder() else { return }
        service.disable()
        start(service, in: folder)
        refresh()
    }

    func syncNow() { service?.syncNow() }

    func exportKey() {
        guard let key = service?.exportKey() else { Alerts.notice(Strings.Sync.noKey); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = Strings.Sync.keyFileName
        panel.allowedContentTypes = [.plainText]
        panel.message = Strings.Sync.exportMessage
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(key.utf8).write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Alerts.error(Strings.Sync.exportFailed, error)
        }
    }

    func importKey() {
        guard let service else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.prompt = Strings.Action.choose
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            try service.importKey(text)
            Alerts.notice(Strings.Sync.imported)
        } catch {
            Alerts.error(Strings.Sync.importFailed, error)
        }
    }

    private func start(_ service: SyncServicing, in folder: URL) {
        do { try service.enable(folder: folder) } catch { Alerts.error(Strings.Sync.enableFailed, error) }
    }

    private func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = Strings.Action.choose
        panel.message = Strings.Sync.chooseFolderMessage
        panel.directoryURL = folder ?? service?.defaultFolder?.deletingLastPathComponent()
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func refresh() {
        status = service?.status ?? .disabled
        folder = service?.folder
    }
}

/// Sync (replaces Paste's iCloud rows, behaviour.md §17): the switch, the folder, the status and the key.
struct SyncPane: View {
    @StateObject private var model = SyncModel(service: Services.sync)

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup {
                ToggleRow(title: Strings.Sync.folderSync, subtitle: Strings.Sync.folderSyncInfo,
                          isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
                if model.isEnabled {
                    Divider()
                    SettingsRow(title: Strings.Sync.folder, subtitle: model.folder.map(Self.displayPath) ?? "") {
                        Button(Strings.Sync.change) { model.changeFolder() }
                    }
                    Divider()
                    SettingsRow(title: Strings.Sync.status, subtitle: model.status.statusLine(),
                                subtitleColor: model.status.isError ? .red : .secondary) {
                        Button(Strings.Sync.syncNow) { model.syncNow() }.disabled(model.status == .syncing)
                    }
                }
            }
            SettingsGroup(title: Strings.Sync.key, subtitle: Strings.Sync.keyInfo) {
                HStack(spacing: 8) {
                    Button(Strings.Sync.exportKey) { model.exportKey() }
                    Button(Strings.Sync.importKey) { model.importKey() }
                    Spacer()
                }
            }
        }
    }

    /// "~/Library/Mobile Documents/…" rather than the full home path.
    static func displayPath(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }
}

public extension SyncStatus {
    /// The Sync pane's status line: "Syncing", "Synced: 5 minutes ago", "Synced: never", or the error.
    func statusLine(now: Date = Date()) -> String {
        switch self {
        case .disabled: ""
        case .syncing: Strings.Sync.syncing
        case .synced(let date): Strings.Sync.synced(date.map { relativeDate($0, now: now) } ?? Strings.Sync.never)
        case .error(let message): message
        }
    }

    internal var isError: Bool { if case .error = self { true } else { false } }
}
