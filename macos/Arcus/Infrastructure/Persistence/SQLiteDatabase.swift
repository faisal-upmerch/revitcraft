import Foundation
import SQLite3

/// Error from the SQLite layer; mapped to `PersistenceError` by callers.
struct SQLiteError: Error, CustomStringConvertible {
    var code: Int32
    var message: String
    var description: String { "SQLite error \(code): \(message)" }
}

private let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal, non-shared SQLite connection wrapper. Not thread-safe; one owner at a time.
final class SQLiteDatabase {
    private(set) var handle: OpaquePointer?

    private init(handle: OpaquePointer?) { self.handle = handle }
    deinit { close() }

    func close() {
        if let h = handle { sqlite3_close_v2(h) }
        handle = nil
    }

    /// Fresh in-memory database (used for writing; serialized afterwards).
    static func inMemory() throws -> SQLiteDatabase {
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(":memory:", &h, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil)
        let db = SQLiteDatabase(handle: h)
        guard rc == SQLITE_OK else { throw db.error(rc) }
        db.harden()
        return db
    }

    /// Opens an existing file read-only and immutable (no locks, no journal side files are ever created).
    static func openReadOnly(path: String) throws -> SQLiteDatabase {
        var comps = URLComponents()
        comps.scheme = "file"
        comps.path = path
        comps.queryItems = [URLQueryItem(name: "mode", value: "ro"), URLQueryItem(name: "immutable", value: "1")]
        let uri = comps.string ?? "file:\(path)?mode=ro&immutable=1"
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(uri, &h, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI | SQLITE_OPEN_NOMUTEX, nil)
        let db = SQLiteDatabase(handle: h)
        guard rc == SQLITE_OK else { throw db.error(rc) }
        db.harden()
        return db
    }

    /// Loads a database image from memory (read-only; SQLite owns a private copy).
    static func deserialize(_ data: Data, readOnly: Bool = true) throws -> SQLiteDatabase {
        let db = try inMemory()
        let size = data.count
        guard let buf = sqlite3_malloc64(sqlite3_uint64(max(size, 1))) else { throw SQLiteError(code: SQLITE_NOMEM, message: "out of memory") }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress, size > 0 { memcpy(buf, base, size) }
        }
        var flags = UInt32(SQLITE_DESERIALIZE_FREEONCLOSE | SQLITE_DESERIALIZE_RESIZEABLE)
        if readOnly { flags |= UInt32(SQLITE_DESERIALIZE_READONLY) }
        let rc = sqlite3_deserialize(db.handle, "main", buf.assumingMemoryBound(to: UInt8.self), sqlite3_int64(size), sqlite3_int64(size), flags)
        guard rc == SQLITE_OK else { throw db.error(rc) }
        return db
    }

    /// Serializes the main database to a byte image identical to the on-disk file format.
    func serialize() throws -> Data {
        var size: sqlite3_int64 = 0
        guard let p = sqlite3_serialize(handle, "main", &size, 0) else { throw error(sqlite3_errcode(handle)) }
        defer { sqlite3_free(p) }
        return Data(bytes: p, count: Int(size))
    }

    /// Defensive settings for untrusted databases.
    private func harden() {
        guard handle != nil else { return }
        // Never run schema-embedded SQL functions from untrusted files; check cell sizes to catch corruption early.
        try? exec("PRAGMA trusted_schema = OFF; PRAGMA cell_size_check = ON;")
    }

    func error(_ rc: Int32) -> SQLiteError {
        let msg = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? String(cString: sqlite3_errstr(rc))
        return SQLiteError(code: rc, message: msg)
    }

    func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? ""
            sqlite3_free(err)
            throw SQLiteError(code: rc, message: msg)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &stmt, nil)
        guard rc == SQLITE_OK, let stmt else { throw error(rc) }
        return Statement(stmt, db: self)
    }

    /// Runs a query and returns the first column of every row as text.
    func strings(_ sql: String) throws -> [String] {
        let s = try prepare(sql)
        var out: [String] = []
        while try s.step() { out.append(s.text(0) ?? "") }
        return out
    }

    func scalarInt(_ sql: String) throws -> Int64? {
        let s = try prepare(sql)
        return try s.step() ? s.int64(0) : nil
    }

    func tableExists(_ name: String) throws -> Bool {
        let s = try prepare("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?")
        try s.bind(1, name)
        return try s.step()
    }

    final class Statement {
        private var stmt: OpaquePointer?
        private unowned let db: SQLiteDatabase
        init(_ stmt: OpaquePointer, db: SQLiteDatabase) { self.stmt = stmt; self.db = db }
        deinit { sqlite3_finalize(stmt) }

        func reset() {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
        func bind(_ i: Int32, _ v: Int64) throws {
            let rc = sqlite3_bind_int64(stmt, i, v)
            if rc != SQLITE_OK { throw db.error(rc) }
        }
        func bind(_ i: Int32, _ v: String) throws {
            let rc = sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT_PTR)
            if rc != SQLITE_OK { throw db.error(rc) }
        }
        func bind(_ i: Int32, _ v: Data) throws {
            let rc = v.withUnsafeBytes { raw in
                sqlite3_bind_blob64(stmt, i, raw.baseAddress ?? UnsafeRawPointer(bitPattern: 1), sqlite3_uint64(raw.count), SQLITE_TRANSIENT_PTR)
            }
            if rc != SQLITE_OK { throw db.error(rc) }
        }
        /// Steps; returns true when a row is available, false when done.
        @discardableResult
        func step() throws -> Bool {
            let rc = sqlite3_step(stmt)
            switch rc {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            default: throw db.error(rc)
            }
        }
        func int64(_ col: Int32) -> Int64 { sqlite3_column_int64(stmt, col) }
        func text(_ col: Int32) -> String? {
            guard let p = sqlite3_column_text(stmt, col) else { return nil }
            return String(cString: p)
        }
        func byteCount(_ col: Int32) -> Int { Int(sqlite3_column_bytes(stmt, col)) }
        func isNull(_ col: Int32) -> Bool { sqlite3_column_type(stmt, col) == SQLITE_NULL }
        func blob(_ col: Int32) -> Data {
            let n = Int(sqlite3_column_bytes(stmt, col))
            guard n > 0, let p = sqlite3_column_blob(stmt, col) else { return Data() }
            return Data(bytes: p, count: n)
        }
    }
}
