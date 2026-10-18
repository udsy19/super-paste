import AppKit
import SwiftUI
import UniformTypeIdentifiers
import SuperPasteCore

/// Privacy (behaviour.md §7.2): ignored apps, screen sharing, link previews and the two content filters.
struct PrivacyPane: View {
    @Default(.isScreenSharingContentVisible) private var screenSharing
    @Default(.isLinkPreviewsEnabled) private var linkPreviews
    /// Re-renders the two filter switches, which read and write this list.
    @Default(.ignoredPasteboardTypes) private var ignoredTypes

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsGroup(title: Strings.Privacy.ignoreApps, subtitle: Strings.Privacy.ignoreAppsInfo) {
                IgnoredAppsEditor()
            }
            SettingsGroup {
                ToggleRow(title: Strings.Privacy.screenSharing, subtitle: Strings.Privacy.screenSharingInfo,
                          isOn: $screenSharing)
                Divider()
                ToggleRow(title: Strings.Privacy.linkPreviews, subtitle: Strings.Privacy.linkPreviewsInfo,
                          isOn: $linkPreviews)
                Divider()
                ToggleRow(title: Strings.Privacy.confidential, subtitle: Strings.Privacy.confidentialInfo,
                          isOn: Binding(get: { _ = ignoredTypes; return Defaults.ignoresConfidentialContent },
                                        set: { Defaults.ignoresConfidentialContent = $0 }))
                Divider()
                ToggleRow(title: Strings.Privacy.transient, subtitle: Strings.Privacy.transientInfo,
                          isOn: Binding(get: { _ = ignoredTypes; return Defaults.ignoresTransientContent },
                                        set: { Defaults.ignoresTransientContent = $0 }))
            }
        }
    }
}

/// An ignored-app entry as shown: the app's name and icon when it is installed, else the identifier itself (prefix
/// and suffix patterns such as ".nordpass" never resolve to one app).
struct IgnoredApp: Hashable {
    let identifier: String
    let name: String
    let icon: NSImage

    @MainActor private static var cache: [String: IgnoredApp] = [:]

    @MainActor static func resolve(_ identifier: String) -> IgnoredApp {
        if let known = cache[identifier] { return known }
        let workspace = NSWorkspace.shared
        let app: IgnoredApp
        if let url = workspace.urlForApplication(withBundleIdentifier: identifier) {
            let name = FileManager.default.displayName(atPath: url.path)
            app = IgnoredApp(identifier: identifier, name: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
                             icon: workspace.icon(forFile: url.path))
        } else {
            app = IgnoredApp(identifier: identifier, name: identifier, icon: workspace.icon(for: .applicationBundle))
        }
        cache[identifier] = app
        return app
    }

}

public enum IgnoredApps {
    /// Adds the bundle identifiers of the chosen apps that aren't in the list yet, in order.
    public static func adding(_ urls: [URL], to list: [String]) -> [String] {
        var result = list
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !result.contains(id) else { continue }
            result.append(id)
        }
        return result
    }
}

/// The Ignore Applications list: icon and name rows, "No items" when empty, + and − below (24 × 24).
struct IgnoredAppsEditor: View {
    @Default(.ignoredBundleIdentifiers) private var identifiers
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(identifiers, id: \.self) { identifier in
                        row(IgnoredApp.resolve(identifier), selected: selection == identifier)
                            .onTapGesture { selection = identifier }
                    }
                }
            }
            .frame(height: 168)
            .overlay {
                if identifiers.isEmpty {
                    Text(Strings.Privacy.noItems).font(.sp(.body)).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack(spacing: 0) {
                footerButton("plus", action: add)
                Divider().frame(height: 14)
                footerButton("minus", action: remove).disabled(selection == nil)
                Spacer()
            }
            .frame(height: 24)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private func row(_ app: IgnoredApp, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
            Text(app.name).font(.sp(.body)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(selected ? Color(nsColor: .selectedContentBackgroundColor) : Color.clear)
        .contentShape(Rectangle())
    }

    private func footerButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = Strings.Action.choose
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        identifiers = IgnoredApps.adding(panel.urls, to: identifiers)
    }

    private func remove() {
        guard let selection else { return }
        identifiers.removeAll { $0 == selection }
        self.selection = nil
    }
}
