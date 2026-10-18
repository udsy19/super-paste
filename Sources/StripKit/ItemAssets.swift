import AppKit
import SuperPasteCore

/// Decoded images and rich text for cards and previews, cached by blob digest.
@MainActor
final class ItemAssets {
    static let shared = ItemAssets()

    private let images = NSCache<NSString, NSImage>()
    private let richTexts = NSCache<NSString, RichTextBox>()

    private final class RichTextBox {
        let text: NSAttributedString
        let background: NSColor?
        init(text: NSAttributedString, background: NSColor?) { self.text = text; self.background = background }
    }

    init() {
        images.countLimit = 400
        richTexts.countLimit = 200
    }

    func image(_ blob: BlobRef?) -> NSImage? {
        guard let blob else { return nil }
        if let cached = images.object(forKey: blob.digest as NSString) { return cached }
        guard let data = Services.store?.data(for: blob), let image = NSImage(data: data) else { return nil }
        images.setObject(image, forKey: blob.digest as NSString)
        return image
    }

    /// The image an image card shows: the stored thumbnail, else the full image from the payload.
    func cardImage(for item: ClipItem) -> NSImage? {
        if let thumb = image(item.thumbnail) { return thumb }
        return image(Self.imageRep(in: item)?.blob)
    }

    /// The full-size image for previews and editing.
    func fullImage(for item: ClipItem) -> NSImage? {
        image(Self.imageRep(in: item)?.blob) ?? image(item.thumbnail)
    }

    static let imageTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.compuserve.gif",
                             "com.adobe.pdf", "NeXT TIFF v4.0 pasteboard type", "Apple PNG pasteboard type"]

    static func imageRep(in item: ClipItem) -> PasteboardRep? {
        for type in imageTypes {
            if let rep = item.payload.lazy.compactMap({ $0.rep(type) }).first { return rep }
        }
        return nil
    }

    static let rtfTypes = ["com.apple.flat-rtfd", "public.rtf", "NeXT RTFD pasteboard type", "NeXT Rich Text Format v1.0 pasteboard type"]

    /// Rich text for a text card or preview: the item's RTF/RTFD, cut to the card excerpt, and its dominant
    /// background colour (ui-reference §4.5). Nil for plain text, or HTML without an RTF flavour.
    func richText(for item: ClipItem, excerpt: Bool = true) -> (text: NSAttributedString, background: NSColor?)? {
        guard item.kind == .richText || item.kind == .html else { return nil }
        guard let rep = Self.rtfTypes.lazy.compactMap({ type in item.payload.lazy.compactMap { $0.rep(type) }.first }).first
        else { return nil }
        let key = "\(rep.blob.digest)-\(excerpt)" as NSString
        if let cached = richTexts.object(forKey: key) { return (cached.text, cached.background) }
        guard let data = Services.store?.data(for: rep.blob) else { return nil }
        let isRTFD = rep.type.lowercased().contains("rtfd")
        let parsed = isRTFD ? NSAttributedString(rtfd: data, documentAttributes: nil)
                            : NSAttributedString(rtf: data, documentAttributes: nil)
        guard let parsed else { return nil }
        let text = excerpt ? Self.cut(parsed) : parsed
        let box = RichTextBox(text: text, background: Self.dominantBackground(text))
        richTexts.setObject(box, forKey: key)
        return (box.text, box.background)
    }

    private static func cut(_ text: NSAttributedString) -> NSAttributedString {
        let excerpt = CardText.excerpt(text.string)
        return text.attributedSubstring(from: NSRange(location: 0, length: (excerpt as NSString).length))
    }

    /// The background colour covering most characters, when it covers at least half of them.
    static func dominantBackground(_ text: NSAttributedString) -> NSColor? {
        guard text.length > 0 else { return nil }
        var coverage: [NSColor: Int] = [:]
        text.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let color = value as? NSColor { coverage[color, default: 0] += range.length }
        }
        guard let best = coverage.max(by: { $0.value < $1.value }), best.value * 2 >= text.length else { return nil }
        return best.key
    }
}

extension NSColor {
    /// Perceived brightness 0…1 (sRGB luma), for picking light or dark ink over a colour.
    var luma: CGFloat {
        guard let c = usingColorSpace(.sRGB) else { return 1 }
        return 0.299 * c.redComponent + 0.587 * c.greenComponent + 0.114 * c.blueComponent
    }

    /// The appearance whose ink reads on this colour.
    var readableAppearance: NSAppearance? { NSAppearance(named: luma > 0.6 ? .aqua : .darkAqua) }
}
