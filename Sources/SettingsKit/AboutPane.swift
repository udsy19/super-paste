import AppKit
import SwiftUI
import SuperPasteCore

/// About (replaces Paste's Help/About, behaviour.md §7.5): icon, name, version, license and source link, automatic
/// updates and the privacy statement.
struct AboutPane: View {
    #if !APP_STORE
    @Default(.installUpdates) private var installUpdates
    @Default(.lastUpdateCheck) private var lastUpdateCheck
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 4) {
                AppIconView(size: 120)
                Text(Strings.appName).font(.sp(.title1, .bold)).padding(.top, 4)
                Text(Self.versionText).font(.sp(.callout)).foregroundStyle(.secondary).textSelection(.enabled)
                Text(Strings.About.license).font(.sp(.callout)).foregroundStyle(.secondary).padding(.top, 8)
                Link(Strings.About.github, destination: Strings.About.githubURL).font(.sp(.callout))
            }
            .frame(maxWidth: .infinity)
            #if APP_STORE
            SettingsGroup {
                SettingsRow(title: Strings.About.importTitle, subtitle: Strings.About.importInfo) {
                    Button(Strings.About.importAction) { DirectEditionImporter.run() }
                }
            }
            #else
            SettingsGroup {
                ToggleRow(title: Strings.About.updates, subtitle: updatesSubtitle, isOn: $installUpdates)
            }
            #endif
            SettingsGroup(title: Strings.About.privacy) {
                Text(Strings.About.privacyText).font(.sp(.callout)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    #if !APP_STORE
    private var updatesSubtitle: String {
        guard lastUpdateCheck > 0 else { return Strings.About.updatesInfo }
        let when = relativeDate(Date(timeIntervalSince1970: lastUpdateCheck))
        return Strings.About.updatesInfo + " " + Strings.About.lastChecked(when)
    }
    #endif

    /// "Version 1.2.0 (42)" from the bundle; "dev" outside one.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        return Strings.About.version(info?["CFBundleShortVersionString"] as? String ?? "dev",
                                     info?["CFBundleVersion"] as? String ?? "0")
    }
}

#if APP_STORE
/// About › Import from Super Paste (direct download): the user points the open panel at the direct edition's data
/// folder (which grants the sandbox read access), the history is copied into a staging folder, and the next launch
/// swaps it in (`DirectEditionImport`). The direct edition's files are only read.
@MainActor
enum DirectEditionImporter {
    static func run() {
        let direct = NSRunningApplication.runningApplications(withBundleIdentifier: Strings.About.directBundleID)
        if !direct.isEmpty, !Alerts.confirm(Strings.About.importDirectRunning, info: Strings.About.importDirectRunningInfo,
                                            confirmTitle: Strings.About.importAnyway) { return }
        guard Alerts.confirm(Strings.About.importConfirm, info: Strings.About.importConfirmInfo,
                             confirmTitle: Strings.About.importAction) else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        panel.prompt = Strings.About.importAction
        panel.message = Strings.About.importPanelMessage
        panel.directoryURL = SuperPastePaths.directEditionSupport
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DirectEditionImport.stage(from: url)
        } catch {
            return Alerts.error(Strings.About.importFailed, error)
        }
        if Alerts.confirm(Strings.About.importStaged, info: Strings.About.importStagedInfo,
                          confirmTitle: Strings.About.quitNow, cancelTitle: Strings.About.later) {
            NSApp.terminate(nil)
        }
    }
}
#endif
