import Foundation
import SQLite3

/// Minimal wrapper over the system SQLite library: open a file, run statements with bound
/// values, read rows back. Not thread-safe; owned and used by one actor.
final class Database {
    enum Value: Equatable {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null
    }

    struct Error: Swift.Error, CustomStringConvertible {
        let code: Int32
        let message: String
        var description: String { "SQLite error \(code): \(message)" }
    }

    /// A result row; values are in the order the query selected them.
    struct Row {
        fileprivate let values: [Value]

        func int(_ column: Int) -> Int? {
            if case .integer(let value) = values[column] { return Int(value) }
            return nil
        }

        func double(_ column: Int) -> Double? {
            switch values[column] {
            case .real(let value): value
            case .integer(let value): Double(value)
            default: nil
            }
        }

        func string(_ column: Int) -> String? {
            if case .text(let value) = values[column] { return value }
            return nil
        }
    }

    private var handle: OpaquePointer?

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(url.path(percentEncoded: false), &handle, flags, nil)
        guard result == SQLITE_OK else {
            let error = Error(code: result, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed")
            sqlite3_close_v2(handle)
            throw error
        }
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs one or more statements without parameters.
    func execute(_ sql: String) throws {
        try check(sqlite3_exec(handle, sql, nil, nil, nil))
    }

    /// Runs a statement with bound parameters, ignoring any result rows.
    func run(_ sql: String, _ values: [Value] = []) throws {
        _ = try query(sql, values)
    }

    func query(_ sql: String, _ values: [Value] = []) throws -> [Row] {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(handle, sql, -1, &statement, nil))
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .integer(let int): try check(sqlite3_bind_int64(statement, position, int))
            case .real(let double): try check(sqlite3_bind_double(statement, position, double))
            case .text(let text): try check(sqlite3_bind_text(statement, position, text, -1, Self.transient))
            case .null: try check(sqlite3_bind_null(statement, position))
            }
        }

        var rows: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { try check(result); break }

            let columns = (0..<sqlite3_column_count(statement)).map { column -> Value in
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
                default: .null
                }
            }
            rows.append(Row(values: columns))
        }
        return rows
    }

    /// Runs `body` in a transaction, rolling back if it throws.
    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Schema version, for migrations.
    var userVersion: Int {
        get { (try? query("PRAGMA user_version").first?.int(0)) ?? 0 }
    }

    func setUserVersion(_ version: Int) throws {
        try execute("PRAGMA user_version = \(version)")
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK || result == SQLITE_DONE || result == SQLITE_ROW else {
            throw Error(code: result, message: String(cString: sqlite3_errmsg(handle)))
        }
    }

    /// Tells SQLite to copy bound strings, since Swift's buffers don't outlive the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

extension Database.Value {
    init(_ string: String?) {
        self = string.map(Database.Value.text) ?? .null
    }

    init(_ int: Int) {
        self = .integer(Int64(int))
    }

    init(_ date: Date) {
        self = .real(date.timeIntervalSince1970)
    }
}
