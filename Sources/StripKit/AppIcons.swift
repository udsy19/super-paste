import AppKit
import UniformTypeIdentifiers
import SuperPasteCore

/// App icons and header colours for cards, cached by bundle id.
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private var icons: [String: NSImage] = [:]
    private var derivedColors: [String: String?] = [:]

    /// The generic app icon, for items without a known source app (stands in for `icon.unknown-app`).
    lazy var unknownAppIcon: NSImage = NSWorkspace.shared.icon(for: .applicationBundle)

    func icon(for app: AppRecord?) -> NSImage {
        guard let app else { return unknownAppIcon }
        if let cached = icons[app.bundleID] { return cached }
        var image: NSImage?
        if let blob = app.icon, let data = Services.store?.data(for: blob) { image = NSImage(data: data) }
        if image == nil, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        }
        let result = image ?? unknownAppIcon
        icons[app.bundleID] = result
        return result
    }

    /// The header band colour (ui-reference §4.3): the pinboard's colour for a pinned item (the shown pinboard
    /// first), else the app's stored colour, else one derived from its icon, else gray.
    func headerColor(for item: ClipItem, scope: ListScope, pinboards: [Pinboard], style: SPStyle) -> NSColor {
        if let board = pinboard(for: item, scope: scope, pinboards: pinboards) {
            return SPColor.pinboard(board.color, style: style)
        }
        return SPColor.header(appColorHex: appColorHex(item.sourceApp))
    }

    func pinboard(for item: ClipItem, scope: ListScope, pinboards: [Pinboard]) -> Pinboard? {
        guard item.isPinned else { return nil }
        if case .pinboard(let id) = scope, item.isPinned(to: id), let board = pinboards.first(where: { $0.id == id }) {
            return board
        }
        return item.pins.lazy.compactMap { pin in pinboards.first { $0.id == pin.pinboardID } }.first
    }

    private func appColorHex(_ app: AppRecord?) -> String? {
        guard let app else { return nil }
        if let hex = app.colorHex { return hex }
        if let cached = derivedColors[app.bundleID] { return cached }
        let icon = icon(for: app)
        let hex = icon === unknownAppIcon ? nil : AppColor.derive(from: icon)
        derivedColors[app.bundleID] = hex
        return hex
    }
}
