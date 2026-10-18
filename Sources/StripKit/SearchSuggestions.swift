import AppKit
import SuperPasteCore

/// A filter the search field can offer or show as a token.
struct FilterSuggestion: Equatable {
    var filter: SearchQuery.Filter
    var title: String
    /// The section it belongs to ("App", "Type", …).
    var subtitle: String { L10n.filterSection(filter.type) }
}

/// What the suggestions and the filter browser can offer (behaviour.md §4.7).
struct FilterSources {
    var apps: [AppRecord] = []
    var pinboards: [Pinboard] = []
    var devices: [Device] = []

    @MainActor static var current: FilterSources {
        guard let store = Services.store else { return FilterSources() }
        return FilterSources(apps: store.apps, pinboards: store.pinboards, devices: store.devices)
    }

    /// Every filter, by section, in the browser's order: App, Date, Device, Pinboard, Type (ui-reference §3.3).
    var sections: [(type: SearchQuery.FilterType, items: [FilterSuggestion])] {
        [
            (.app, apps.map { FilterSuggestion(filter: .init(.app, $0.name), title: $0.name) }),
            (.date, Self.dates),
            (.device, devices.map { FilterSuggestion(filter: .init(.device, $0.name), title: $0.name) }),
            (.pinboard, pinboards.map { FilterSuggestion(filter: .init(.pinboard, $0.name), title: $0.name) }),
            (.type, ItemTypeFilter.allCases.map { FilterSuggestion(filter: .init(.type, $0.rawValue), title: L10n.typeFilterLabel($0)) }),
        ]
    }

    static let dates: [FilterSuggestion] = [
        FilterSuggestion(filter: .init(.date, "today"), title: L10n.today),
        FilterSuggestion(filter: .init(.date, "yesterday"), title: L10n.yesterday),
        FilterSuggestion(filter: .init(.date, "last 7 days"), title: L10n.last7Days),
        FilterSuggestion(filter: .init(.date, "last 30 days"), title: L10n.last30Days),
    ]

    /// Suggestions for the word being typed: values of `key:` when the word starts with a filter key, otherwise
    /// every filter whose title starts with the word. Applied filters are left out (`hideAppliedFilters`).
    func suggestions(for word: String, excluding applied: [SearchQuery.Filter], limit: Int = 8) -> [FilterSuggestion] {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var key: SearchQuery.FilterType?
        var prefix = trimmed
        if let colon = trimmed.firstIndex(of: ":"), let type = SearchQuery.FilterType(rawValue: trimmed[..<colon].lowercased()) {
            key = type
            prefix = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        let order: [SearchQuery.FilterType] = [.type, .app, .pinboard, .device, .date]
        let pool = order.flatMap { type in sections.first { $0.type == type }?.items ?? [] }
        let matches = pool.filter { suggestion in
            if let key, suggestion.filter.type != key { return false }
            if applied.contains(suggestion.filter) { return false }
            if prefix.isEmpty { return key != nil }
            return suggestion.title.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
                || suggestion.filter.value.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
        return Array(matches.prefix(limit))
    }

    /// The token label for a filter: its display title when one is known, else its value.
    func title(for filter: SearchQuery.Filter) -> String {
        if filter.type == .type, let type = ItemTypeFilter(filterValue: filter.value) { return L10n.typeFilterLabel(type) }
        if filter.type == .date, let date = Self.dates.first(where: { $0.filter.value.caseInsensitiveCompare(filter.value) == .orderedSame }) {
            return date.title
        }
        return filter.value
    }

    /// The 12 pt icon of a filter token or suggestion row.
    @MainActor func icon(for filter: SearchQuery.Filter, style: SPStyle, size: CGFloat) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.85, weight: .regular)
        switch filter.type {
        case .app:
            if let app = apps.first(where: { $0.name.caseInsensitiveCompare(filter.value) == .orderedSame || $0.bundleID == filter.value }) {
                let image = AppIconProvider.shared.icon(for: app).copy() as! NSImage
                image.size = NSSize(width: size, height: size)
                return image
            }
            return Symbols.image("app.dashed", config: config)
        case .type:
            switch ItemTypeFilter(filterValue: filter.value) {
            case .text?: return Symbols.image("text.alignleft", config: config)
            case .link?: return Symbols.image("link", config: config)
            case .image?: return Symbols.image("photo", config: config)
            case .file?: return Symbols.image("doc", config: config)
            case .color?: return Symbols.image("paintpalette", config: config)
            default: return Symbols.image("questionmark.circle", config: config)
            }
        case .date: return Symbols.image("calendar", config: config)
        case .device: return Symbols.image("laptopcomputer", config: config)
        case .title: return Symbols.image("pencil", config: config)
        case .pinboard:
            if let board = pinboards.first(where: { $0.name.caseInsensitiveCompare(filter.value) == .orderedSame }) {
                return Symbols.dot(SPColor.pinboard(board.color, style: style), side: size * 0.75)
            }
            return Symbols.image("circlebadge", config: config)
        }
    }
}
