import Foundation
import SuperPasteCore

// Search (behaviour.md §4.7): `SearchQuery` compiled to one SQL statement. Tokens go to FTS5 (word prefix over the
// title, the full text and recognised text; case and diacritics folded by the tokenizer); filters are SQL. Results
// keep the scope's order: recency for history and all, pin order for a pinboard. Match strength (bm25) is not a
// tie-break: copy times practically never tie, and ranking every match costs about three times the query.
extension SQLiteStore {
    func search(_ query: SearchQuery, in scope: ListScope, limit: Int, offset: Int) -> [ClipItem] {
        guard limit > 0, let compiled = compile(query, scope: scope) else { return [] }
        return reading([]) {
            // Order and page on row ids alone (sorting whole rows is several times slower), then load the page.
            let page = try db.query("""
                SELECT i.rid FROM items i \(compiled.joins) WHERE \(compiled.condition)
                ORDER BY \(compiled.order) LIMIT ? OFFSET ?
                """, compiled.arguments + [limit, max(offset, 0)]) { $0.int64(0) }
            let items = try loadItems(where: "i.rid IN (SELECT value FROM json_each(?))", [json(page)])
            let byRowID = Dictionary(uniqueKeysWithValues: items.map { ($0.0, $0.1) })
            return page.compactMap { byRowID[$0] }
        }
    }

    func count(_ query: SearchQuery, in scope: ListScope) -> Int {
        guard let compiled = compile(query, scope: scope) else { return 0 }
        return reading(0) {
            try db.first("SELECT count(*) FROM items i \(compiled.joins) WHERE \(compiled.condition)", compiled.arguments) {
                $0.int(0)
            } ?? 0
        }
    }

    struct CompiledQuery {
        var joins = ""
        var conditions: [String] = []
        var arguments: [any SQLBindable] = []
        var order = ""

        var condition: String { conditions.isEmpty ? "1" : conditions.joined(separator: " AND ") }
    }

    /// The SQL for a query in a scope; nil when it can't match anything (a filter none of whose values can match).
    func compile(_ query: SearchQuery, scope: ListScope, now: Date = Date()) -> CompiledQuery? {
        var compiled = CompiledQuery()
        switch scope {
        case .history:
            compiled.conditions.append("i.copied_at IS NOT NULL")
            compiled.order = "i.copied_at DESC, i.rid DESC"
        case .all:
            compiled.order = "coalesce(i.copied_at, i.created_at) DESC, i.rid DESC"
        case .pinboard(let id):
            // The join's parameter comes first in the statement, so first in the arguments.
            compiled.joins = "JOIN pins sp ON sp.item = i.rid AND sp.pinboard = ?"
            compiled.arguments.append(id)
            compiled.order = "sp.position, i.rid"
        }

        // Tokens: those with letters or digits go to FTS as word-prefix phrases; the rest (punctuation such as "->")
        // have no FTS terms and match as substrings of the title or the preview text.
        let tokens = query.tokens
        let indexed = tokens.filter(Self.hasTerms)
        if !indexed.isEmpty {
            compiled.conditions.append("i.rid IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)")
            compiled.arguments.append("{title body ocr} : (" + indexed.map { Self.phrase($0) + " *" }.joined(separator: " AND ") + ")")
        }
        for token in tokens where !Self.hasTerms(token) {
            // No letters, so no case to fold: a plain substring test.
            compiled.conditions.append("(instr(i.title, ?) > 0 OR instr(i.text, ?) > 0)")
            compiled.arguments += [token, token]
        }

        // Filters: values of one type OR together, types AND together.
        if let kinds = query.kinds {
            guard !kinds.isEmpty else { return nil }
            compiled.conditions.append("i.kind IN (SELECT value FROM json_each(?))")
            compiled.arguments.append(json(kinds.map(\.rawValue).sorted()))
        }
        if let ranges = query.dateRanges(now: now) {
            guard !ranges.isEmpty else { return nil }
            var alternatives: [String] = []
            for range in ranges {
                var bounds: [String] = []
                if let start = range.start { bounds.append("coalesce(i.copied_at, i.created_at) >= ?"); compiled.arguments.append(start) }
                if let end = range.end { bounds.append("coalesce(i.copied_at, i.created_at) < ?"); compiled.arguments.append(end) }
                alternatives.append(bounds.isEmpty ? "1" : "(" + bounds.joined(separator: " AND ") + ")")
            }
            compiled.conditions.append("(" + alternatives.joined(separator: " OR ") + ")")
        }
        let titles = query.values(.title)
        if !titles.isEmpty {
            compiled.conditions.append("i.title IS NOT NULL AND (" + titles.map { _ in "sp_contains(i.title, ?)" }.joined(separator: " OR ") + ")")
            compiled.arguments += titles
        }
        let apps = query.values(.app)
        if !apps.isEmpty {
            // Exact bundle id, or the app name by prefix: the name's first words, the last one possibly partial.
            var alternatives = ["i.app_id IN (SELECT value FROM json_each(?))"]
            compiled.arguments.append(json(apps))
            let names = apps.filter(Self.hasTerms)
            if !names.isEmpty {
                alternatives.append("i.rid IN (SELECT rowid FROM items_fts WHERE items_fts MATCH ?)")
                compiled.arguments.append("{app} : (" + names.map { "^" + Self.phrase($0) + " *" }.joined(separator: " OR ") + ")")
            }
            compiled.conditions.append("(" + alternatives.joined(separator: " OR ") + ")")
        }
        let deviceValues = query.values(.device)
        if !deviceValues.isEmpty {
            let all = (try? db.query("SELECT id, name FROM devices") { ($0.string(0), $0.string(1)) }) ?? []
            let ids = all.filter { id, name in
                deviceValues.contains { $0 == id || name.range(of: $0, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil }
            }.map(\.0)
            guard !ids.isEmpty else { return nil }
            compiled.conditions.append("i.device_id IN (SELECT value FROM json_each(?))")
            compiled.arguments.append(json(ids))
        }
        let pinboardValues = query.values(.pinboard)
        if !pinboardValues.isEmpty {
            let ids = pinboards.filter { board in
                pinboardValues.contains {
                    UUID(uuidString: $0) == board.id || board.name.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }
            }.map(\.id.uuidString)
            guard !ids.isEmpty else { return nil }
            compiled.conditions.append("EXISTS (SELECT 1 FROM pins WHERE pins.item = i.rid AND pins.pinboard IN (SELECT value FROM json_each(?)))")
            compiled.arguments.append(json(ids))
        }
        return compiled
    }

    /// Whether the FTS tokenizer finds any term in `text` (letters or digits).
    static func hasTerms(_ text: String) -> Bool { text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) } }

    /// `text` as an FTS5 string (a phrase when it has several words).
    static func phrase(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
}
