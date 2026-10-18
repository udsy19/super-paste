import AppKit
import SuperPasteCore

// Source app records (behaviour.md §2.7): name, header colour and icon of the app a copy came from.

/// The card header colour of an app (ui-reference §4.3).
package enum AppColor {
    /// Built-in colours of well-known apps, by lower-cased bundle id (behaviour.md §2.7).
    package static let known: [String: String] = {
        let table: [(String, [String])] = [
            ("#005C90", ["com.adobe.Photoshop"]),
            ("#E58B00", ["com.adobe.illustrator"]),
            ("#9B0A00", ["com.adobe.Acrobat.Pro", "com.adobe.Reader"]),
            ("#52CC64", ["com.apple.iWork.Numbers"]),
            ("#FA9214", ["com.apple.iWork.Pages", "com.apple.iBooksX"]),
            ("#62A9F5", ["com.apple.Safari", "com.apple.finder", "com.apple.mail", "com.apple.dt.Xcode", "com.apple.iWork.Keynote"]),
            ("#F0554D", ["com.apple.iCal", "com.apple.Photos", "com.apple.reminders"]),
            ("#454D4D", ["com.apple.Terminal"]),
        ]
        return Dictionary(uniqueKeysWithValues: table.flatMap { hex, ids in ids.map { ($0.lowercased(), hex) } })
    }()

    package static func known(_ bundleID: String) -> String? { known[bundleID.lowercased()] }

    /// The icon side the colour is derived at.
    package static let sampleSide = 128

    /// Derives "#RRGGBB" from an icon rendered as RGBA bytes (8 bits per channel): the most frequent colour among
    /// fully opaque pixels with saturation above 0.25, its saturation capped at 0.85 and, when its brightness is
    /// above 0.4, its brightness clamped to 0.75…0.96. Nil (gray) when no pixel qualifies.
    package static func derive(rgba: [UInt8]) -> String? {
        var counts: [UInt32: Int] = [:]
        var i = 0
        while i + 3 < rgba.count {
            if rgba[i + 3] == 255 {
                let (r, g, b) = (rgba[i], rgba[i + 1], rgba[i + 2])
                if hsb(Double(r) / 255, Double(g) / 255, Double(b) / 255).s > 0.25 {
                    counts[UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b), default: 0] += 1
                }
            }
            i += 4
        }
        // Ties go to the lowest value so the result never depends on dictionary order.
        guard let top = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else { return nil }
        var (h, s, v) = hsb(Double(top >> 16 & 0xFF) / 255, Double(top >> 8 & 0xFF) / 255, Double(top & 0xFF) / 255)
        s = min(s, 0.85)
        if v > 0.4 { v = min(max(v, 0.75), 0.96) }
        let (r, g, b) = rgb(h, s, v)
        return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    /// Renders `image` into a square sRGB RGBA bitmap.
    package static func render(_ image: NSImage, side: Int) -> (rgba: [UInt8], image: CGImage)? {
        var rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = context.data, let rendered = context.makeImage() else { return nil }
        let bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: side * side * 4))
        return (bytes, rendered)
    }

    private static func hsb(_ r: Double, _ g: Double, _ b: Double) -> (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r { h = (g - b) / delta } else if maxC == g { h = 2 + (b - r) / delta } else { h = 4 + (r - g) / delta }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        guard s > 0 else { return (v, v, v) }
        let sector = (h * 6).truncatingRemainder(dividingBy: 6), i = Int(sector), f = sector - Double(i)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}

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
        if record.colorHex == nil, let sample = AppColor.render(icon, side: AppColor.sampleSide) {
            record.colorHex = AppColor.derive(rgba: sample.rgba)
        }
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
