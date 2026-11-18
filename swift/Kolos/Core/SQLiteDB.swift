import Foundation
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum DBError: Error {
    case open
    case exec(String)
}

/// Тонкая обёртка над системным SQLite (тот же формат файлов, что у Flutter-версии)
final class SQLiteDB {
    private var handle: OpaquePointer?

    init(path: String, readOnly: Bool) throws {
        let flags: Int32 = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &handle, flags, nil) != SQLITE_OK {
            sqlite3_close(handle)
            throw DBError.open
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "sqlite"
            sqlite3_free(err)
            throw DBError.exec(msg)
        }
    }

    /// Выборка: каждая строка превращается в T
    func query<T>(_ sql: String, _ args: [Any] = [], _ map: (Row) -> T) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            sqlite3_finalize(stmt)
            return []
        }
        defer { sqlite3_finalize(s) }
        bind(s, args)
        var out: [T] = []
        while sqlite3_step(s) == SQLITE_ROW {
            out.append(map(Row(stmt: s)))
        }
        return out
    }

    /// Вставка многих строк одним подготовленным запросом
    func insert(_ sql: String, _ rows: [[Any]]) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let s = stmt else {
            throw DBError.exec(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(s) }
        for r in rows {
            sqlite3_reset(s)
            sqlite3_clear_bindings(s)
            bind(s, r)
            if sqlite3_step(s) != SQLITE_DONE {
                throw DBError.exec(String(cString: sqlite3_errmsg(handle)))
            }
        }
    }

    private func bind(_ s: OpaquePointer, _ args: [Any]) {
        for (i, a) in args.enumerated() {
            let idx = Int32(i + 1)
            if let v = a as? Int {
                sqlite3_bind_int64(s, idx, Int64(v))
            } else if let v = a as? String {
                sqlite3_bind_text(s, idx, v, -1, sqliteTransient)
            } else {
                sqlite3_bind_null(s, idx)
            }
        }
    }
}

struct Row {
    let stmt: OpaquePointer

    func int(_ i: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, i))
    }

    func text(_ i: Int32) -> String {
        if let p = sqlite3_column_text(stmt, i) {
            return String(cString: p)
        }
        return ""
    }
}
