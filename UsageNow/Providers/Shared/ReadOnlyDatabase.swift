import Foundation
import SQLite3

/// A read-only connection to another app's SQLite database. Never writes,
/// never migrates, and never creates a database that isn't there.
///
/// Used for tools that keep their history in SQLite (Warp, OpenCode).
/// Queries select the columns they need by name, so text a tool stores
/// beside them — prompts, replies — is never read.
final class ReadOnlyDatabase {
    enum Failure: Error, Equatable {
        case open(Int32)
        case query(Int32)
    }

    /// A value bound to a `?` placeholder.
    enum Value {
        case text(String)
        case integer(Int64)
    }

    struct Row {
        let statement: OpaquePointer

        func isNull(_ column: Int32) -> Bool {
            sqlite3_column_type(statement, column) == SQLITE_NULL
        }

        func text(_ column: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: bytes)
        }

        func data(_ column: Int32) -> Data? {
            guard let bytes = sqlite3_column_blob(statement, column) else { return nil }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }

        /// `nil` for NULL, so a missing field isn't mistaken for zero.
        func integer(_ column: Int32) -> Int64? {
            isNull(column) ? nil : sqlite3_column_int64(statement, column)
        }
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK else {
            // SQLite returns a handle even when opening fails, and it must be
            // closed. `deinit` still runs after a throwing init, so the handle
            // is cleared here to keep it from being closed a second time.
            sqlite3_close(handle)
            handle = nil
            throw Failure.open(status)
        }
        // The tool may be writing; wait briefly instead of failing the refresh.
        sqlite3_busy_timeout(handle, 500)
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func rows<T>(_ sql: String, bind values: [String], map: (Row) -> T) throws -> [T] {
        try rows(sql, values: values.map { .text($0) }, map: map)
    }

    func rows<T>(_ sql: String, values: [Value], map: (Row) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let prepared = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard prepared == SQLITE_OK, let statement else { throw Failure.query(prepared) }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, value) in values.enumerated() {
            switch value {
            case .text(let text): sqlite3_bind_text(statement, Int32(index + 1), text, -1, transient)
            case .integer(let number): sqlite3_bind_int64(statement, Int32(index + 1), number)
            }
        }

        var results: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                results.append(map(Row(statement: statement)))
            } else if step == SQLITE_DONE {
                return results
            } else {
                throw Failure.query(step)
            }
        }
    }

    /// Whether the database has a table by this name.
    func hasTable(_ name: String) throws -> Bool {
        try !rows("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", bind: [name]) { _ in true }.isEmpty
    }
}
