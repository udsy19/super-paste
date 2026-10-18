import AppKit
import ImageIO
import UniformTypeIdentifiers
import SuperPasteCore

// Type detection (behaviour.md §2.5) and the text, files, link and image details capture stores with an item.

/// Text types that have no `NSPasteboard.PasteboardType` constant.
package enum TextTypes {
    package static let utf16 = "public.utf16-plain-text"
    package static let utf16External = "public.utf16-external-plain-text"
    package static let genericPlain = "public.plain-text"
    package static let webArchive = "com.apple.webarchive"
    static let rtf = NSPasteboard.PasteboardType.rtf.rawValue
    static let rtfd = NSPasteboard.PasteboardType.rtfd.rawValue
    static let html = NSPasteboard.PasteboardType.html.rawValue
    static let url = NSPasteboard.PasteboardType.URL.rawValue
    static let fileURL = NSPasteboard.PasteboardType.fileURL.rawValue

    /// Representations that make a copy text (or a link or colour, decided from its plain text).
    static let all: Set<String> = [PasteboardType.plainText, utf16, utf16External, genericPlain, rtf, rtfd, "com.apple.rtfd",
                                   html, webArchive, url]
    static let rich: Set<String> = [rtf, rtfd, "com.apple.rtfd"]
    static let markup: Set<String> = [html, webArchive]

    static func isImage(_ type: String) -> Bool {
        guard !type.hasPrefix("dyn."), let uti = UTType(type) else { return false }
        return uti.conforms(to: .image)
    }
}

/// Reading plain text out of a payload.
package enum PayloadText {
    /// The plain text of one pasteboard item: its string flavours (`preferred` first, then UTF-8, then UTF-16),
    /// else the text of its RTF/RTFD or HTML, else its web URL. Nil when it has none.
    package static func plainText(of entry: EntryData, preferring preferred: [String] = []) -> String? {
        let strings = preferred + [PasteboardType.plainText, TextTypes.utf16, TextTypes.utf16External, TextTypes.genericPlain]
        for type in strings {
            if let data = entry.data(type), let text = decodeString(data, type: type) { return text }
        }
        if let data = entry.data(TextTypes.rtf), let text = NSAttributedString(rtf: data, documentAttributes: nil)?.string {
            return text
        }
        for type in [TextTypes.rtfd, "com.apple.rtfd"] {
            if let data = entry.data(type), let text = NSAttributedString(rtfd: data, documentAttributes: nil)?.string {
                return text
            }
        }
        if let data = entry.data(TextTypes.html), let html = String(data: data, encoding: .utf8) { return htmlToText(html) }
        if let data = entry.data(TextTypes.url), let text = decodeString(data, type: TextTypes.url) { return text }
        return nil
    }

    /// Every item's text, joined with newlines; nil when no item has text.
    package static func plainText(of entries: [EntryData], preferring preferred: [String] = []) -> String? {
        let texts = entries.compactMap { plainText(of: $0, preferring: preferred) }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    static func decodeString(_ data: Data, type: String) -> String? {
        let text: String?
        if type == TextTypes.utf16 || type == TextTypes.utf16External {
            let hasBOM = data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF])
            text = String(data: data, encoding: hasBOM ? .utf16 : .utf16LittleEndian)
        } else {
            text = String(data: data, encoding: .utf8)
        }
        // Some apps end C strings with their terminator.
        return text.map { $0.hasSuffix("\0") ? String($0.dropLast()) : $0 }
    }

    /// A tag-stripping reading of HTML, for the rare copy that has no plain text of its own (WebKit's HTML import
    /// is avoided on purpose: it spins the run loop).
    package static func htmlToText(_ html: String) -> String {
        var s = html
        for pattern in ["(?is)<(script|style|head)[^>]*>.*?</\\1>", "(?s)<!--.*?-->"] {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        s = s.replacingOccurrences(of: "(?i)<br\\s*/?>|</(p|div|li|tr|h[1-6]|blockquote|pre)>", with: "\n",
                                   options: .regularExpression)
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = decodeEntities(s)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ text: String) -> String {
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "#39": "'", "nbsp": "\u{00A0}"]
        var out = "", rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = String(after[..<semi])
                var replacement = named[name.lowercased()]
                if replacement == nil, name.hasPrefix("#") {
                    let digits = name.dropFirst()
                    let code = digits.first == "x" || digits.first == "X" ? UInt32(digits.dropFirst(), radix: 16) : UInt32(digits)
                    replacement = code.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                }
                if let replacement {
                    out += replacement
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out += "&"
            rest = after
        }
        return out + rest
    }
}

/// What capture works out about a payload (behaviour.md §2.5).
package struct CaptureAnalysis: Sendable {
    package var kind: ItemKind
    /// The full plain text: the text, the link or colour as copied, file paths one per line; "" for images.
    package var text: String
    package var filePaths: [String] = []
    package var link: LinkMetadata?
    package var imageSize: PixelSize?
    /// Downscaled PNG preview for images.
    package var thumbnail: Data?
    /// The payload to store: file URLs resolved to path URLs (Finder copies file reference URLs).
    package var entries: [EntryData]
}

package enum Classifier {
    /// Longest side of the image thumbnail capture stores (twice the largest card).
    package static let thumbnailMaxPixels = 720

    /// Decides the kind: file URLs make files; otherwise the first image or text representation in pasteboard order
    /// decides (an app's quirk text types win over its images), text further splitting into colour, link, rich text,
    /// HTML and plain text; anything else is unknown.
    package static func analyze(_ entries: [EntryData], bundleID: String?) -> CaptureAnalysis {
        let (resolved, paths) = resolvingFileURLs(entries)
        if !paths.isEmpty {
            return CaptureAnalysis(kind: .files, text: paths.joined(separator: "\n"), filePaths: paths, entries: resolved)
        }
        let preferred = QuirkRule.textTypes(for: bundleID)
        let reps = entries.flatMap(\.reps)
        let prefersText = reps.contains { preferred.contains($0.type) }
        for rep in reps {
            if !prefersText, TextTypes.isImage(rep.type), let image = imageInfo(rep.data) {
                return CaptureAnalysis(kind: .image, text: "", imageSize: image.size, thumbnail: image.thumbnail, entries: entries)
            }
            if TextTypes.all.contains(rep.type), let text = PayloadText.plainText(of: entries, preferring: preferred) {
                return textAnalysis(text, entries: entries)
            }
        }
        // Text types the reader couldn't decode, or images that don't decode: fall back to whatever text exists.
        if let text = PayloadText.plainText(of: entries, preferring: preferred) { return textAnalysis(text, entries: entries) }
        return CaptureAnalysis(kind: .unknown, text: "", entries: entries)
    }

    private static func textAnalysis(_ text: String, entries: [EntryData]) -> CaptureAnalysis {
        switch TextClassifier.kind(of: text) {
        case .color:
            return CaptureAnalysis(kind: .color, text: text, entries: entries)
        case .link:
            let url = TextClassifier.linkURL(in: text)!
            let name = entries.lazy.compactMap { $0.data(PasteboardType.urlName) }.first
                .flatMap { String(data: $0, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            return CaptureAnalysis(kind: .link, text: text, link: LinkMetadata(url: url.absoluteString,
                                                                              title: name?.isEmpty == false ? name : nil),
                                   entries: entries)
        default:
            let richest = entries.flatMap(\.reps).first { TextTypes.rich.contains($0.type) || TextTypes.markup.contains($0.type) }
            let kind: ItemKind = richest.map { TextTypes.rich.contains($0.type) ? .richText : .html } ?? .text
            return CaptureAnalysis(kind: kind, text: text, entries: entries)
        }
    }

    /// File URLs (`public.file-url`) with their paths; reference URLs ("file:///.file/id=…") become path URLs in the
    /// returned payload so it pastes anywhere and syncs.
    package static func resolvingFileURLs(_ entries: [EntryData]) -> (entries: [EntryData], paths: [String]) {
        var paths: [String] = []
        let resolved = entries.map { entry -> EntryData in
            var entry = entry
            for (i, rep) in entry.reps.enumerated() where rep.type == TextTypes.fileURL {
                guard let string = PayloadText.decodeString(rep.data, type: rep.type),
                      let url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines)), url.isFileURL
                else { continue }
                let pathURL = (url as NSURL).filePathURL ?? url
                paths.append(pathURL.path)
                entry.reps[i].data = Data(pathURL.absoluteString.utf8)
            }
            return entry
        }
        return (resolved, paths)
    }

    /// Pixel size and a PNG thumbnail (longest side at most `maxPixels`), or nil when the data isn't an image.
    package static func imageInfo(_ data: Data, maxPixels: Int = thumbnailMaxPixels) -> (size: PixelSize, thumbnail: Data?)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue, width > 0, height > 0
        else { return nil }
        // EXIF orientations 5–8 rotate by 90°: the image shows with its sides swapped.
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixels, max(width, height)),
        ]
        let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).flatMap(ImageEncoding.png)
        return (PixelSize(width: width, height: height), thumbnail)
    }
}

/// Encoding images for blobs.
package enum ImageEncoding {
    package static func png(_ image: CGImage) -> Data? { encode(image, as: .png, quality: nil) }

    package static func jpeg(_ image: CGImage, quality: Double = 0.8) -> Data? { encode(image, as: .jpeg, quality: quality) }

    /// Re-encodes `data` with its longest side at most `maxPixels`: PNG when `png`, else JPEG.
    package static func downscaled(_ data: Data, maxPixels: Int, png: Bool) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return png ? self.png(image) : jpeg(image)
    }

    private static func encode(_ image: CGImage, as type: UTType, quality: Double?) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil) else { return nil }
        let properties = quality.map { [kCGImageDestinationLossyCompressionQuality: $0] as CFDictionary }
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}
