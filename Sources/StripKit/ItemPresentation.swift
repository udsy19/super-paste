import AppKit
import SuperPasteCore

/// Card date labels (ui-reference §4.3): "2 hours ago" in the larger classes, "2h" in compact, the absolute date as
/// the tooltip.
enum CardDateText {
    static func text(for date: Date, now: Date = Date(), compact: Bool, locale: Locale = .current) -> String {
        if compact {
            // One unit, truncated ("1m" for 90 s), like `DateComponentsFormatter` abbreviated with one unit.
            var calendar = Calendar.current
            calendar.locale = locale
            let units: [Calendar.Component] = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
            let parts = calendar.dateComponents(Set(units), from: min(date, now), to: now)
            var largest = DateComponents()
            if let unit = units.first(where: { (parts.value(for: $0) ?? 0) > 0 }) {
                largest.setValue(parts.value(for: unit), for: unit)
            } else {
                largest.second = 0
            }
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute, .second]
            formatter.calendar = calendar
            return formatter.string(from: largest) ?? ""
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        formatter.locale = locale
        return formatter.localizedString(for: min(date, now), relativeTo: now)
    }

    static func tooltip(for date: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

/// How an item reads on its card and in menus.
enum ItemPresentation {
    /// The header title: the user's title, else the type label (ui-reference §4.3).
    static func headerTitle(_ item: ClipItem) -> String {
        if let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        return typeLabel(item)
    }

    static func typeLabel(_ item: ClipItem) -> String {
        switch item.kind {
        case .text, .richText, .html: L10n.text
        case .link: L10n.link
        case .image: L10n.image
        case .color: L10n.color
        case .files: L10n.fileCount(max(1, item.filePaths.count))
        case .unknown: L10n.unknown
        }
    }

    /// The date the card shows: when it entered the history, else when it was created.
    static func date(_ item: ClipItem) -> Date { item.copiedAt ?? item.createdAt }

    /// Colour items: "#RRGGBB".
    static func colorHex(_ item: ClipItem) -> String? { TextClassifier.colorHex(in: item.text) }

    static func linkURL(_ item: ClipItem) -> URL? {
        if let s = item.link?.url, let url = URL(string: s) { return url }
        return TextClassifier.linkURL(in: item.text)
    }

    /// "airbnb.com": the host without "www.".
    static func displayHost(_ url: URL?) -> String {
        guard let host = url?.host else { return url?.absoluteString ?? "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// A link card's title: the page title, else the host.
    static func linkTitle(_ item: ClipItem) -> String {
        if let title = item.link?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty { return title }
        return displayHost(linkURL(item))
    }

    /// Files: the file name, or "Multiple files".
    static func filesTitle(_ item: ClipItem) -> String {
        guard item.filePaths.count == 1, let path = item.filePaths.first else {
            return item.filePaths.isEmpty ? L10n.fileCount(1) : L10n.multipleFiles
        }
        return FileManager.default.displayName(atPath: path)
    }

    /// Files: the folder path shown under the name (head-truncated on the card).
    static func filesPath(_ item: ClipItem) -> String {
        guard let first = item.filePaths.first else { return "" }
        let folder = (first as NSString).deletingLastPathComponent
        return (folder as NSString).abbreviatingWithTildeInPath
    }

    /// A one-line summary for menus, the Paste Stack and tooltips.
    static func summary(_ item: ClipItem) -> String {
        switch item.kind {
        case .image:
            if let size = item.imageSize { return "\(L10n.image) \(size.width) × \(size.height)" }
            return L10n.image
        case .files: return item.filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        case .link: return linkURL(item)?.absoluteString ?? item.text
        default:
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? typeLabel(item) : text
        }
    }

    /// "N characters · N words · N lines" (preview footer, §6.3).
    static func textCounts(_ text: String) -> (characters: Int, words: Int, lines: Int) {
        var words = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in words += 1 }
        let lines = text.isEmpty ? 0 : text.components(separatedBy: .newlines).count
        return (text.count, words, lines)
    }

    /// Whether the card shows its content full-size under a gradient header in the compact class (media cards).
    static func isCompactContentFullSize(_ item: ClipItem) -> Bool {
        switch item.kind {
        case .image: true
        case .link: item.link?.image != nil
        default: false
        }
    }
}

/// Text to show on a card: enough lines to overflow any card, so the visible result matches the full 20 000-character
/// preview while keeping text layout cheap.
enum CardText {
    static let maxLines = 40
    static let maxCharacters = 4_000

    static func excerpt(_ text: String) -> String {
        var lines = 0
        var end = text.startIndex
        var count = 0
        while end < text.endIndex, count < maxCharacters {
            if text[end] == "\n" {
                lines += 1
                if lines >= maxLines { break }
            }
            end = text.index(after: end)
            count += 1
        }
        return String(text[..<end])
    }
}
