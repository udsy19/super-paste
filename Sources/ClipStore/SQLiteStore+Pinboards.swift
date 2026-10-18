import Foundation
import SuperPasteCore

// Pinboards and pins (behaviour.md §5). An item may be pinned to several pinboards; `pins.position` orders a
// pinboard ascending and is fractional, so a move rewrites only the moved items.
extension SQLiteStore {
    var pinboards: [Pinboard] {
        reading([]) {
            try db.query("""
                SELECT id, name, color, position, shortcut, created_at, updated_at FROM pinboards
                ORDER BY position, created_at
                """) { Self.decodePinboard($0) }
        }.compactMap { $0 }
    }

    @discardableResult func createPinboard(name: String, color: PinboardColor) throws -> Pinboard {
        let name = try Self.validName(name)
        let pinboard: Pinboard = try writing {
            let order = try db.first("SELECT coalesce(max(position) + 1, 0) FROM pinboards") { $0.int(0) } ?? 0
            let pinboard = Pinboard(name: name, color: color, order: order)
            try writePinboard(pinboard)
            try journal(.pinboard, pinboard.id)
            return pinboard
        }
        subject.send(.pinboards)
        return pinboard
    }

    func updatePinboard(_ pinboard: Pinboard) throws {
        let name = try Self.validName(pinboard.name)
        try writing {
            try requirePinboard(pinboard.id)
            try db.run("UPDATE pinboards SET name = ?, color = ?, shortcut = ?, updated_at = ? WHERE id = ?",
                       [name, pinboard.color.rawValue, pinboard.shortcut.map { json($0) }, Date(), pinboard.id])
            try journal(.pinboard, pinboard.id)
        }
        subject.send(.pinboards)
    }

    func deletePinboard(_ id: UUID) throws {
        let now = Date()
        var deleted: [UUID] = [], updated: [UUID] = [], digests = Set<String>()
        try writing {
            try requirePinboard(id)
            let pinned = try db.query("""
                SELECT i.rid, i.id, i.copied_at IS NULL AND (SELECT count(*) FROM pins WHERE item = i.rid) = 1
                FROM pins JOIN items i ON i.rid = pins.item WHERE pins.pinboard = ?
                """, [id]) { ($0.int64(0), $0.uuid(1), $0.int(2) == 1) }
            for (rid, itemID, onlyHere) in pinned {
                guard let itemID else { continue }
                if onlyHere {
                    // A pinned-only item lives in this pinboard alone: it goes with it.
                    digests.formUnion(try removeItem(rid: rid, id: itemID, at: now, trace: .journaled))
                    deleted.append(itemID)
                } else {
                    try unpin(rid: rid, id: itemID, from: id, at: now)
                    updated.append(itemID)
                }
            }
            try db.run("DELETE FROM pinboards WHERE id = ?", [id])
            try recordTombstone(.pinboard, id, at: now)
            try journal(.pinboard, id)
        }
        collectGarbage(digests)
        if !deleted.isEmpty { subject.send(.deleted(deleted)) }
        if !updated.isEmpty { subject.send(.updated(updated)) }
        subject.send(.pinboards)
    }

    func reorderPinboards(_ ids: [UUID]) throws {
        let now = Date()
        let changed: Bool = try writing {
            let current = try db.query("SELECT id, position FROM pinboards ORDER BY position, created_at") {
                ($0.uuid(0), $0.int(1))
            }.compactMap { id, position in id.map { ($0, position) } }
            let known = Set(current.map(\.0))
            if let unknown = ids.first(where: { !known.contains($0) }) { throw StoreError.pinboardNotFound(unknown) }
            // Pinboards the list leaves out keep their relative order after the listed ones.
            let listed = Self.unique(ids)
            let order = listed + current.map(\.0).filter { !listed.contains($0) }
            let positions = Dictionary(uniqueKeysWithValues: current)
            var changed = false
            for (index, id) in order.enumerated() where positions[id] != index {
                try db.run("UPDATE pinboards SET position = ?, updated_at = ? WHERE id = ?", [index, now, id])
                try journal(.pinboard, id)
                changed = true
            }
            return changed
        }
        if changed { subject.send(.pinboards) }
    }

    func assign(_ itemIDs: [UUID], to pinboardID: UUID) throws {
        let now = Date()
        let changed: [UUID] = try writing {
            try requirePinboard(pinboardID)
            let rows = try rowIDs(Self.unique(itemIDs))
            var position = try nextPinPosition(in: pinboardID)
            var changed: [UUID] = []
            for (rid, id) in rows {
                try db.run("INSERT OR IGNORE INTO pins (pinboard, item, position) VALUES (?, ?, ?)", [pinboardID, rid, position])
                guard db.changes > 0 else { continue }
                position += 1
                try touch(rid: rid, id: id, at: now)
                changed.append(id)
            }
            return changed
        }
        if !changed.isEmpty { subject.send(.updated(changed)) }
    }

    func unassign(_ itemIDs: [UUID], from pinboardID: UUID) throws {
        let now = Date()
        let updated: [UUID] = try writing {
            try requirePinboard(pinboardID)
            var updated: [UUID] = []
            for (rid, id) in try rowIDs(Self.unique(itemIDs)) where try unpin(rid: rid, id: id, from: pinboardID, at: now) {
                updated.append(id)
            }
            return updated
        }
        if !updated.isEmpty { subject.send(.updated(updated)) }
    }

    func move(_ itemIDs: [UUID], in pinboardID: UUID, before beforeID: UUID?) throws {
        let now = Date()
        let changed: [UUID] = try writing {
            try requirePinboard(pinboardID)
            let pins = try db.query("""
                SELECT pins.item, i.id, pins.position FROM pins JOIN items i ON i.rid = pins.item
                WHERE pins.pinboard = ? ORDER BY pins.position, pins.item
                """, [pinboardID]) { ($0.int64(0), $0.uuid(1), $0.double(2)) }
                .compactMap { rid, id, position in id.map { (rid: rid, id: $0, position: position) } }
            let moving = Self.unique(itemIDs)
            let movingSet = Set(moving)
            for id in moving where !pins.contains(where: { $0.id == id }) { throw StoreError.itemNotFound(id) }
            let rest = pins.filter { !movingSet.contains($0.id) }

            var index = rest.count
            if let beforeID {
                guard let anchor = pins.firstIndex(where: { $0.id == beforeID }) else { throw StoreError.itemNotFound(beforeID) }
                // Before a moving item means before the first item after it that stays put.
                if let next = pins[anchor...].first(where: { !movingSet.contains($0.id) }) {
                    index = rest.firstIndex { $0.id == next.id } ?? rest.count
                }
            }
            let lower = index > 0 ? rest[index - 1].position : nil
            let upper = index < rest.count ? rest[index].position : nil
            let rowsByID = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0.rid) })

            var assignments: [(rid: Int64, id: UUID, position: Double)]
            if let positions = Self.positions(count: moving.count, between: lower, and: upper) {
                assignments = zip(moving, positions).map { (rowsByID[$0]!, $0, $1) }
            } else {
                // The gap is exhausted: renumber the whole pinboard 1, 2, 3, … in the new order.
                let order = rest[..<index].map(\.id) + moving + rest[index...].map(\.id)
                let old = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0.position) })
                assignments = order.enumerated().map { (rowsByID[$1]!, $1, Double($0 + 1)) }
                    .filter { movingSet.contains($0.1) || old[$0.1] != $0.2 }
            }
            for assignment in assignments {
                try db.run("UPDATE pins SET position = ? WHERE pinboard = ? AND item = ?",
                           [assignment.position, pinboardID, assignment.rid])
                try touch(rid: assignment.rid, id: assignment.id, at: now)
            }
            return assignments.map(\.id)
        }
        if !changed.isEmpty { subject.send(.updated(changed)) }
    }

    // MARK: - Helpers

    func writePinboard(_ pinboard: Pinboard) throws {
        try db.run("""
            INSERT INTO pinboards (id, name, color, position, shortcut, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (id) DO UPDATE SET name = excluded.name, color = excluded.color, position = excluded.position,
                shortcut = excluded.shortcut, created_at = excluded.created_at, updated_at = excluded.updated_at
            """, [pinboard.id, pinboard.name, pinboard.color.rawValue, pinboard.order, pinboard.shortcut.map { json($0) },
                  pinboard.createdAt, pinboard.updatedAt])
    }

    func loadPinboard(_ id: UUID) throws -> Pinboard? {
        try db.first("""
            SELECT id, name, color, position, shortcut, created_at, updated_at FROM pinboards WHERE id = ?
            """, [id]) { Self.decodePinboard($0) } ?? nil
    }

    static func decodePinboard(_ row: Row) -> Pinboard? {
        guard let id = row.uuid(0) else { return nil }
        let shortcut = row.optionalString(4).flatMap { try? JSONDecoder().decode(Shortcut.self, from: Data($0.utf8)) }
        return Pinboard(id: id, name: row.string(1), color: PinboardColor(rawValue: row.string(2)) ?? .gray,
                        order: row.int(3), shortcut: shortcut, createdAt: row.date(5), updatedAt: row.date(6))
    }

    /// Removes an item's pin; false when it wasn't pinned there. An item that loses its last pin goes (back) to the
    /// front of the history with a fresh copy date, so retention doesn't remove it straight away.
    @discardableResult
    private func unpin(rid: Int64, id: UUID, from pinboardID: UUID, at date: Date) throws -> Bool {
        try db.run("DELETE FROM pins WHERE pinboard = ? AND item = ?", [pinboardID, rid])
        guard db.changes > 0 else { return false }
        try db.run("UPDATE items SET copied_at = ?1 WHERE rid = ?2 AND NOT EXISTS (SELECT 1 FROM pins WHERE item = ?2)",
                   [date, rid])
        try touch(rid: rid, id: id, at: date)
        return true
    }

    /// Marks an item changed (a pin was added, removed or moved): new `updatedAt`, journaled.
    private func touch(rid: Int64, id: UUID, at date: Date) throws {
        try db.run("UPDATE items SET updated_at = ? WHERE rid = ?", [date, rid])
        try journal(.item, id)
    }

    /// Row ids for items, in the given order; throws `itemNotFound` for the first missing one.
    private func rowIDs(_ ids: [UUID]) throws -> [(Int64, UUID)] {
        try ids.map { id in
            guard let rid = try db.first("SELECT rid FROM items WHERE id = ?", [id], { $0.int64(0) }) else {
                throw StoreError.itemNotFound(id)
            }
            return (rid, id)
        }
    }

    private static func validName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw StoreError.invalidName }
        return trimmed
    }

    /// `count` ascending positions strictly between `lower` and `upper` (either may be open); nil when the gap is too
    /// narrow to split without losing precision.
    static func positions(count: Int, between lower: Double?, and upper: Double?) -> [Double]? {
        guard count > 0 else { return [] }
        switch (lower, upper) {
        case (nil, nil): return (1...count).map(Double.init)
        case (let lower?, nil): return (1...count).map { lower + Double($0) }
        case (nil, let upper?): return (0..<count).map { upper - Double(count - $0) }
        case (let lower?, let upper?):
            let step = (upper - lower) / Double(count + 1)
            guard step > max(abs(lower), abs(upper), 1) * 1e-9 else { return nil }
            return (1...count).map { lower + step * Double($0) }
        }
    }
}
