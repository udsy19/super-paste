import AppKit
import SuperPasteCore

// Source app records (behaviour.md §2.7): name, header colour and icon of the app a copy came from.

/// Builds and caches `AppRecord`s for the apps copies come from.
@MainActor
package final class AppRecords {
    /// Side of the stored icon PNG (the largest header icon at 2×).
    package static let iconSide = 256

    private var cache: [String: (record: AppRecord, iconPNG: Data?)] = [:]
    private let store: () -> ItemStoring?

    package init(store: @escaping () -> ItemStoring?) {
        self.store = store
    }

    /// The app's record, its icon saved to the store as a blob.
    package func record(for source: CaptureSource) -> AppRecord {
        let key = source.bundleID.lowercased()
        let entry = cache[key] ?? make(source)
        cache[key] = entry
        var record = entry.record
        // Saving is idempotent; doing it every time keeps the icon present even after the store dropped it.
        if let png = entry.iconPNG { record.icon = try? store()?.saveBlob(png) }
        return record
    }

    private func make(_ source: CaptureSource) -> (record: AppRecord, iconPNG: Data?) {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID)
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).first
        let name = source.name ?? running?.localizedName ?? url.flatMap(Self.bundleName) ?? source.bundleID
        var record = AppRecord(bundleID: source.bundleID, name: name, colorHex: AppColor.known(source.bundleID))
        guard let icon = running?.icon ?? url.map({ NSWorkspace.shared.icon(forFile: $0.path) }) else { return (record, nil) }
        if record.colorHex == nil { record.colorHex = AppColor.derive(from: icon) }
        let png = AppColor.render(icon, side: Self.iconSide).flatMap { ImageEncoding.png($0.image) }
        return (record, png)
    }

    private static func bundleName(_ url: URL) -> String? {
        let bundle = Bundle(url: url)
        let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
        return name ?? url.deletingPathExtension().lastPathComponent
    }
}
