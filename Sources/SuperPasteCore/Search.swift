import Foundation

/// A parsed search: free-text tokens plus filters (behaviour.md §4.7).
///
/// Text syntax, as typed in the strip's search field or sent by MCP:
///
///     meeting slides app:Mail type:link
///     "exact phrase" app:"Visual Studio Code" date:"last 7 days" pinboard:Work title:invoice device:"Studio Mac"
///
/// - Words separated by whitespace are tokens. Double quotes group words into one token (matched as a phrase).
/// - `key:value` with a key from `FilterType` (any case) is a filter; the value may be quoted. A key with no value
///   yet (`app:`) is ignored, so a half-typed filter doesn't narrow anything. A quoted word is never a filter.
///
/// Matching (implemented by the store):
/// - Tokens AND together; each matches the title or the full text by word prefix, ignoring case and diacritics.
/// - Filters of different types AND together; several filters of the same type OR together (`type:link type:image`).
/// - `app`: app name (case-insensitive, prefix) or exact bundle id. `device`: device name (prefix) or id.
///   `title`: substring of the user title. `pinboard`: pinboard name (case-insensitive) or id.
///   `type`: `ItemTypeFilter(filterValue:)`. `date`: `DateRange.parse(_:now:calendar:)` against `copiedAt`
///   (else `createdAt`).
/// - A filter value that can't match anything (unknown type, unparseable date) makes its filter match nothing.
public struct SearchQuery: Hashable, Codable, Sendable {
    public enum FilterType: String, Codable, CaseIterable, Hashable, Sendable {
        case app, type, title, date, device, pinboard
    }

    public struct Filter: Hashable, Codable, Sendable {
        public var type: FilterType
        public var value: String

        public init(_ type: FilterType, _ value: String) {
            self.type = type; self.value = value
        }
    }

    public enum Component: Hashable, Codable, Sendable {
        case token(String)
        case filter(Filter)
    }

    public var components: [Component]

    public init(components: [Component] = []) { self.components = components }

    public static let empty = SearchQuery()

    /// Parses the text syntax above.
    public init(parsing text: String) {
        var components: [Component] = []
        for word in Self.words(in: text) {
            if !word.quoted, let colon = word.text.firstIndex(of: ":"), colon != word.text.startIndex,
               let type = FilterType(rawValue: word.text[..<colon].lowercased()) {
                let value = word.text[word.text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { components.append(.filter(Filter(type, value))) }
            } else {
                components.append(.token(word.text))
            }
        }
        self.components = components
    }

    public var tokens: [String] {
        components.compactMap { if case .token(let t) = $0 { t } else { nil } }
    }

    public var filters: [Filter] {
        components.compactMap { if case .filter(let f) = $0 { f } else { nil } }
    }

    public func values(_ type: FilterType) -> [String] { filters.filter { $0.type == type }.map(\.value) }

    public var isEmpty: Bool { components.isEmpty }

    /// The canonical text form; `SearchQuery(parsing: q.text) == q`.
    public var text: String {
        components.map { component in
            switch component {
            case .token(let t):
                let needsQuotes = t.contains(where: \.isWhitespace)
                    || t.firstIndex(of: ":").map { FilterType(rawValue: t[..<$0].lowercased()) != nil } == true
                return needsQuotes ? "\"\(t)\"" : t
            case .filter(let f):
                return f.value.contains(where: \.isWhitespace) ? "\(f.type.rawValue):\"\(f.value)\"" : "\(f.type.rawValue):\(f.value)"
            }
        }.joined(separator: " ")
    }

    public func adding(_ filter: Filter) -> SearchQuery {
        filters.contains(filter) ? self : SearchQuery(components: components + [.filter(filter)])
    }

    public func removing(_ filter: Filter) -> SearchQuery {
        SearchQuery(components: components.filter { $0 != .filter(filter) })
    }

    /// The kinds the `type:` filters allow: nil without type filters; empty when none of their values is a type.
    public var kinds: Set<ItemKind>? {
        let values = values(.type)
        guard !values.isEmpty else { return nil }
        return values.reduce(into: Set<ItemKind>()) { $0.formUnion(ItemTypeFilter(filterValue: $1)?.kinds ?? []) }
    }

    /// The ranges the `date:` filters allow: nil without date filters; empty when none of their values parses.
    public func dateRanges(now: Date = Date(), calendar: Calendar = .current) -> [DateRange]? {
        let values = values(.date)
        guard !values.isEmpty else { return nil }
        return values.compactMap { DateRange.parse($0, now: now, calendar: calendar) }
    }

    // MARK: - Lexing

    private struct Word { var text: String; var quoted: Bool }

    /// Whitespace-separated words; double quotes group (and are removed). An unclosed quote runs to the end.
    private static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var current = "", inQuotes = false, startsQuoted = false, started = false
        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if started, !trimmed.isEmpty { words.append(Word(text: trimmed, quoted: startsQuoted)) }
            current = ""; startsQuoted = false; started = false
        }
        for ch in text {
            if ch == "\"" {
                if !started { startsQuoted = true; started = true }
                inQuotes.toggle()
            } else if ch.isWhitespace && !inQuotes {
                flush()
            } else {
                current.append(ch); started = true
            }
        }
        flush()
        return words
    }
}

/// A half-open span of time: `start` inclusive, `end` exclusive; nil means unbounded on that side.
public struct DateRange: Hashable, Sendable {
    public var start: Date?
    public var end: Date?

    public init(start: Date?, end: Date?) {
        self.start = start; self.end = end
    }

    public func contains(_ date: Date) -> Bool {
        (start.map { date >= $0 } ?? true) && (end.map { date < $0 } ?? true)
    }

    /// Parses a `date:` value. Days follow `calendar` (its time zone):
    ///
    /// - `today`, `yesterday`; `this week` / `this month` / `this year`;
    /// - `last N days|weeks|months` (also `past …`, `last7days`, `last-30-days`): today and the N−1 days (weeks,
    ///   months) before it;
    /// - an ISO date `2026-10-01` (that whole day);
    /// - a range `A..B` or `A to B` whose sides are any of the above or ISO date-times (`2026-10-01T09:00:00Z`): from
    ///   the start of A to the end of B. A side may be empty (`2026-10-01..`). A range that ends before it starts is
    ///   nil, as is anything unrecognised.
    public static func parse(_ value: String, now: Date = Date(), calendar: Calendar = .current) -> DateRange? {
        let v = value.trimmingCharacters(in: .whitespaces)
        if let range = v.range(of: "..") ?? v.range(of: " to ", options: .caseInsensitive) {
            let lhs = v[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let rhs = v[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard !(lhs.isEmpty && rhs.isEmpty) else { return nil }
            var result = DateRange(start: nil, end: nil)
            if !lhs.isEmpty {
                guard let span = span(lhs, now: now, calendar: calendar) else { return nil }
                result.start = span.start
            }
            if !rhs.isEmpty {
                guard let span = span(rhs, now: now, calendar: calendar) else { return nil }
                result.end = span.end
            }
            if let s = result.start, let e = result.end, s >= e { return nil }
            return result
        }
        guard let span = span(v, now: now, calendar: calendar), span.start != span.end else { return nil }
        return span
    }

    /// One side of a range: the span a keyword or date covers, or a zero-length span at a date-time.
    private static func span(_ text: String, now: Date, calendar: Calendar) -> DateRange? {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, from date: Date = today) -> Date { calendar.date(byAdding: .day, value: offset, to: date)! }
        let key = text.lowercased().filter { !$0.isWhitespace && $0 != "-" && $0 != "_" }
        switch key {
        case "today": return DateRange(start: today, end: day(1))
        case "yesterday": return DateRange(start: day(-1), end: today)
        case "thisweek", "thismonth", "thisyear":
            let unit: Calendar.Component = key == "thisweek" ? .weekOfYear : key == "thismonth" ? .month : .year
            guard let interval = calendar.dateInterval(of: unit, for: now) else { return nil }
            return DateRange(start: interval.start, end: interval.end)
        default: break
        }
        if let match = key.wholeMatch(of: #/(?:last|past)(\d{1,4})(days?|d|weeks?|w|months?|m)/#), let n = Int(match.1), n > 0 {
            let unit = match.2.first!
            let start: Date
            switch unit {
            case "w": start = day(-(n * 7 - 1))
            case "m": start = calendar.date(byAdding: .month, value: -n, to: day(1))!
            default: start = day(-(n - 1))
            }
            return DateRange(start: start, end: day(1))
        }
        let dateOnly = DateFormatter()
        dateOnly.calendar = calendar
        dateOnly.timeZone = calendar.timeZone
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.dateFormat = "yyyy-MM-dd"
        if text.count == 10, let date = dateOnly.date(from: text) {
            let start = calendar.startOfDay(for: date)
            return DateRange(start: start, end: day(1, from: start))
        }
        let iso = ISO8601DateFormatter()
        if let instant = iso.date(from: text) { return DateRange(start: instant, end: instant) }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let instant = iso.date(from: text) { return DateRange(start: instant, end: instant) }
        return nil
    }
}
