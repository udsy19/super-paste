import AppKit
import SwiftUI
import SuperPasteCore

/// About (replaces Paste's Help/About, behaviour.md §7.5): icon, name, version, license and source link, automatic
/// updates and the privacy statement.
struct AboutPane: View {
    @Default(.installUpdates) private var installUpdates
    @Default(.lastUpdateCheck) private var lastUpdateCheck

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
            SettingsGroup {
                ToggleRow(title: Strings.About.updates, subtitle: updatesSubtitle, isOn: $installUpdates)
            }
            SettingsGroup(title: Strings.About.privacy) {
                Text(Strings.About.privacyText).font(.sp(.callout)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var updatesSubtitle: String {
        guard lastUpdateCheck > 0 else { return Strings.About.updatesInfo }
        let when = relativeDate(Date(timeIntervalSince1970: lastUpdateCheck))
        return Strings.About.updatesInfo + " " + Strings.About.lastChecked(when)
    }

    /// "Version 1.2.0 (42)" from the bundle; "dev" outside one.
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        return Strings.About.version(info?["CFBundleShortVersionString"] as? String ?? "dev",
                                     info?["CFBundleVersion"] as? String ?? "0")
    }
}
