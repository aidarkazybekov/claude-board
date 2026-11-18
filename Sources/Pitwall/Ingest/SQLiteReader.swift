import Foundation
import SQLite3

/// Read-only access to another app's SQLite database. The database (with its WAL and shared-memory
/// files) is copied into the app's cache first, so we never take a lock on the live file or write
/// next to it, and rows still in the WAL are included.
final class SQLiteSnapshot {
    private var db: OpaquePointer?

    /// Copies `path` (plus -wal/-shm) to `cacheName` in the app's cache folder and opens the copy.
    init?(path: String, cacheName: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return nil }
        let dir = Paths.appSupport.appendingPathComponent("cache", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(cacheName).path
        for suffix in ["", "-wal", "-shm"] {
            try? fm.removeItem(atPath: dest + suffix)
            if fm.fileExists(atPath: path + suffix) { try? fm.copyItem(atPath: path + suffix, toPath: dest + suffix) }
        }
        guard sqlite3_open_v2(dest, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
    }

    deinit { sqlite3_close(db) }

    /// Runs a query and returns each row as column name → value (String, Int64, Double or nil).
    func rows(_ sql: String, _ args: [String] = []) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), a, -1, transient) }
        var out: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for c in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, c))
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(stmt, c)
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, c)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(stmt, c))
                default: break
                }
            }
            out.append(row)
        }
        return out
    }

    func hasTable(_ name: String) -> Bool {
        !rows("SELECT name FROM sqlite_master WHERE type='table' AND name=?", [name]).isEmpty
    }
}

extension Dictionary where Key == String, Value == Any {
    func str(_ k: String) -> String? { self[k] as? String }
    func int(_ k: String) -> Int64? { (self[k] as? Int64) ?? (self[k] as? Double).map { Int64($0) } }
}

/// Creates or opens a SQLite file for writing. Only the demo and the self-test use it, to build
/// databases shaped like another app's.
final class SQLiteWriter {
    private var db: OpaquePointer?

    init?(path: String) {
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
    }

    deinit { sqlite3_close(db) }

    @discardableResult
    func exec(_ sql: String, _ args: [String] = []) -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (i, a) in args.enumerated() { sqlite3_bind_text(stmt, Int32(i + 1), a, -1, transient) }
        return sqlite3_step(stmt) == SQLITE_DONE
    }
}
