import Foundation
import SQLite3

/// A value that can be bound to a statement parameter.
protocol SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32)
}

/// SQL NULL, for parameter lists that need an explicit null.
struct SQLNull: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) { sqlite3_bind_null(statement, index) }
}

private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension Int: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) { sqlite3_bind_int64(statement, index, Int64(self)) }
}

extension Int64: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) { sqlite3_bind_int64(statement, index, self) }
}

extension Double: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) { sqlite3_bind_double(statement, index, self) }
}

extension String: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) { sqlite3_bind_text(statement, index, self, -1, transient) }
}

extension Data: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) {
        _ = withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress ?? UnsafeRawPointer(bitPattern: 1), Int32(count), transient) }
    }
}

/// Dates are stored as seconds since the reference date, which round-trips a `Date` exactly.
extension Date: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_double(statement, index, timeIntervalSinceReferenceDate)
    }
}

extension UUID: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) { uuidString.bind(to: statement, at: index) }
}

extension Optional: SQLBindable where Wrapped: SQLBindable {
    func bind(to statement: OpaquePointer, at index: Int32) {
        switch self {
        case .some(let value): value.bind(to: statement, at: index)
        case .none: sqlite3_bind_null(statement, index)
        }
    }
}

/// One result row; columns are read by index in select-list order.
struct Row {
    let statement: OpaquePointer

    func isNull(_ i: Int32) -> Bool { sqlite3_column_type(statement, i) == SQLITE_NULL }
    func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(statement, i)) }
    func int64(_ i: Int32) -> Int64 { sqlite3_column_int64(statement, i) }
    func double(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }
    func string(_ i: Int32) -> String { sqlite3_column_text(statement, i).map { String(cString: $0) } ?? "" }
    func optionalString(_ i: Int32) -> String? { isNull(i) ? nil : string(i) }
    func optionalInt(_ i: Int32) -> Int? { isNull(i) ? nil : int(i) }
    func date(_ i: Int32) -> Date { Date(timeIntervalSinceReferenceDate: double(i)) }
    func optionalDate(_ i: Int32) -> Date? { isNull(i) ? nil : date(i) }
    func uuid(_ i: Int32) -> UUID? { UUID(uuidString: string(i)) }

    func data(_ i: Int32) -> Data? {
        guard !isNull(i) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, i))
        guard count > 0, let bytes = sqlite3_column_blob(statement, i) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}

/// One SQLite connection: cached prepared statements, typed binding, nested-safe transactions. Not thread-safe; the
/// store uses it from the main actor only.
final class Database {
    struct Failure: Error, CustomStringConvertible {
        let code: Int32
        let message: String
        var description: String { "SQLite error \(code): \(message)" }
        /// The file isn't a usable database (garbage, truncated, or damaged pages).
        var isDamage: Bool { [SQLITE_CORRUPT, SQLITE_NOTADB].contains(code & 0xFF) }
    }

    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]
    private var transactionDepth = 0

    /// Opens (creating when needed) the database at `url`, or a private in-memory one when nil.
    init(url: URL?) throws {
        var db: OpaquePointer?
        let path = url?.path ?? ":memory:"
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let code = sqlite3_open_v2(path, &db, flags, nil)
        guard code == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open \(path)"
            sqlite3_close_v2(db)
            throw Failure(code: code, message: message)
        }
        handle = db
        sqlite3_extended_result_codes(db, 1)
        sqlite3_busy_timeout(db, 2_000)
        registerFunctions()
    }

    deinit {
        for statement in statements.values { sqlite3_finalize(statement) }
        sqlite3_close_v2(handle)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    /// Rows changed by the most recent statement.
    var changes: Int { Int(sqlite3_changes(handle)) }

    /// Runs one or more statements without parameters (schema, pragmas).
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &error)
        if code != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(handle))
            sqlite3_free(error)
            throw Failure(code: code, message: message)
        }
    }

    /// Runs a statement that returns no rows.
    func run(_ sql: String, _ arguments: [any SQLBindable] = []) throws {
        let statement = try prepared(sql, arguments)
        defer { sqlite3_reset(statement) }
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW { code = sqlite3_step(statement) }
        guard code == SQLITE_DONE else { throw failure(code) }
    }

    /// Runs a query and maps each row.
    func query<T>(_ sql: String, _ arguments: [any SQLBindable] = [], _ map: (Row) throws -> T) throws -> [T] {
        let statement = try prepared(sql, arguments)
        defer { sqlite3_reset(statement) }
        var results: [T] = []
        var code = sqlite3_step(statement)
        while code == SQLITE_ROW {
            results.append(try map(Row(statement: statement)))
            code = sqlite3_step(statement)
        }
        guard code == SQLITE_DONE else { throw failure(code) }
        return results
    }

    /// The first row of a query, mapped; nil when there is none.
    func first<T>(_ sql: String, _ arguments: [any SQLBindable] = [], _ map: (Row) throws -> T) throws -> T? {
        let statement = try prepared(sql, arguments)
        defer { sqlite3_reset(statement) }
        let code = sqlite3_step(statement)
        if code == SQLITE_ROW { return try map(Row(statement: statement)) }
        guard code == SQLITE_DONE else { throw failure(code) }
        return nil
    }

    /// Runs `body` in a transaction (BEGIN IMMEDIATE … COMMIT, ROLLBACK on a throw). Nested calls join the outer one.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        if transactionDepth > 0 {
            transactionDepth += 1
            defer { transactionDepth -= 1 }
            return try body()
        }
        try execute("BEGIN IMMEDIATE")
        transactionDepth = 1
        defer { transactionDepth = 0 }
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    // MARK: - Private

    private func prepared(_ sql: String, _ arguments: [any SQLBindable]) throws -> OpaquePointer {
        let statement: OpaquePointer
        if let cached = statements[sql] {
            statement = cached
            sqlite3_clear_bindings(statement)
        } else {
            var new: OpaquePointer?
            let code = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &new, nil)
            guard code == SQLITE_OK, let new else { throw failure(code) }
            statements[sql] = new
            statement = new
        }
        for (offset, argument) in arguments.enumerated() {
            argument.bind(to: statement, at: Int32(offset + 1))
        }
        return statement
    }

    private func failure(_ code: Int32) -> Failure {
        Failure(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }

    /// `sp_contains(haystack, needle)`: 1 when `needle` occurs in `haystack`, ignoring case and diacritics (the
    /// `title:` filter). SQLite's own LIKE folds ASCII only.
    private func registerFunctions() {
        sqlite3_create_function_v2(handle, "sp_contains", 2, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { context, _, values in
            guard let values, let haystack = sqlite3_value_text(values[0]), let needle = sqlite3_value_text(values[1]) else {
                sqlite3_result_int(context, 0)
                return
            }
            let found = String(cString: haystack).range(of: String(cString: needle),
                                                         options: [.caseInsensitive, .diacriticInsensitive]) != nil
            sqlite3_result_int(context, found ? 1 : 0)
        }, nil, nil, nil)
    }
}
