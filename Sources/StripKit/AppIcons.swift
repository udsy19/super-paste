import AppKit
import UniformTypeIdentifiers
import SuperPasteCore

/// The card header colour from an app icon (ui-reference §4.3): render at 128 px, keep fully opaque pixels with
/// saturation > 0.25, take the most frequent colour, cap its saturation at 0.85 and, when its brightness is over 0.4,
/// clamp the brightness to 0.75…0.96. Nil when no pixel qualifies (the caller falls back to gray).
enum IconColorExtractor {
    static let renderSize = 128

    static func dominantColor(of image: NSImage) -> NSColor? {
        let side = renderSize
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            var rect = CGRect(x: 0, y: 0, width: side, height: side)
            guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return false }
            context.interpolationQuality = .high
            context.draw(cgImage, in: rect)
            return true
        }
        return drawn ? dominantColor(rgba: pixels) : nil
    }

    /// The same rule over raw sRGB RGBA bytes (premultiplied; only fully opaque pixels count, so it doesn't matter).
    static func dominantColor(rgba pixels: [UInt8]) -> NSColor? {
        var counts: [UInt32: Int] = [:]
        var i = 0
        while i + 3 < pixels.count {
            if pixels[i + 3] == 255 {
                let r = pixels[i], g = pixels[i + 1], b = pixels[i + 2]
                if saturation(r, g, b) > 0.25 {
                    counts[UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b), default: 0] += 1
                }
            }
            i += 4
        }
        guard let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key
        else { return nil }
        let color = NSColor(srgbRed: CGFloat(best >> 16 & 0xFF) / 255, green: CGFloat(best >> 8 & 0xFF) / 255,
                            blue: CGFloat(best & 0xFF) / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        color.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        s = min(s, 0.85)
        if v > 0.4 { v = min(max(v, 0.75), 0.96) }
        return NSColor(colorSpace: .sRGB, hue: h, saturation: s, brightness: v, alpha: 1)
    }

    /// HSB saturation of an 8-bit colour.
    static func saturation(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> CGFloat {
        let maxC = CGFloat(max(r, g, b)), minC = CGFloat(min(r, g, b))
        return maxC == 0 ? 0 : (maxC - minC) / maxC
    }

    /// "#RRGGBB" in sRGB.
    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.redComponent), byte(c.greenComponent), byte(c.blueComponent))
    }
}

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
        let hex = icon === unknownAppIcon ? nil : IconColorExtractor.dominantColor(of: icon).map(IconColorExtractor.hex)
        derivedColors[app.bundleID] = hex
        return hex
    }
}
