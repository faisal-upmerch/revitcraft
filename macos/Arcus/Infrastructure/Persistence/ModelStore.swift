import Foundation
import ArcusDomain

/// Reads and writes `model.sqlite` (schema v2; reads v1 for migration).
enum ModelStore {
    /// `PRAGMA application_id` of Arcus model databases ("PLNT").
    static let applicationID: Int32 = 0x504C_4E54

    static let schemaV2 = """
    PRAGMA foreign_keys = ON;
    PRAGMA application_id = \(applicationID);
    PRAGMA user_version = 2;
    CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE elements(id INTEGER PRIMARY KEY, category TEXT NOT NULL, kind TEXT NOT NULL, revision INTEGER NOT NULL, data BLOB NOT NULL);
    CREATE TABLE relations(element_id INTEGER NOT NULL REFERENCES elements(id) ON DELETE CASCADE, related_id INTEGER NOT NULL REFERENCES elements(id) ON DELETE CASCADE, role TEXT NOT NULL);
    CREATE TABLE project(key TEXT PRIMARY KEY, data BLOB);
    """
    static let indexesV2 = """
    CREATE INDEX relations_by_element ON relations(element_id);
    CREATE INDEX relations_by_related ON relations(related_id);
    """

    /// Project-table keys (schema v2).
    enum ProjectKey {
        static let nextID = "nextID", revision = "revision", projectParameters = "projectParameters"
        static let viewSheetSets = "viewSheetSets", referenceDrawings = "referenceDrawings"
    }

    struct Meta {
        var appVersion: String
        var build: String
        var documentID: UUID
        var created: Date
        var modified: Date
    }

    // MARK: Write (v2)

    /// Builds a complete v2 database in memory and returns its file image (rollback-journal mode; never WAL).
    static func writeV2(_ model: BIMModel, drawingIndex: [String: String], meta: Meta) throws -> Data {
        let elements = model.allElements
        for e in elements where e.id.raw > UInt64(Int64.max) {
            throw PersistenceError(.limitExceeded("element id"), "Element \(e.id) has an id too large to store.")
        }
        let blobs = try ElementCodec.encode(elements)
        let enc = StoredJSON.encoder()
        let db = try SQLiteDatabase.inMemory()
        try db.exec(schemaV2)
        try db.exec("BEGIN IMMEDIATE")
        do {
            let ins = try db.prepare("INSERT INTO elements(id, category, kind, revision, data) VALUES (?, ?, ?, ?, ?)")
            for (i, e) in elements.enumerated() {
                ins.reset()
                try ins.bind(1, Int64(e.id.raw))
                try ins.bind(2, e.category.rawValue)
                try ins.bind(3, e.kind.rawValue)
                try ins.bind(4, Int64(bitPattern: e.revision))
                try ins.bind(5, blobs[i])
                try ins.step()
            }
            let rel = try db.prepare("INSERT INTO relations(element_id, related_id, role) VALUES (?, ?, ?)")
            for e in elements {
                for r in RelationRoles.references(of: e) where model.contains(r.target) && r.target.raw <= UInt64(Int64.max) {
                    rel.reset()
                    try rel.bind(1, Int64(e.id.raw))
                    try rel.bind(2, Int64(r.target.raw))
                    try rel.bind(3, r.role)
                    try rel.step()
                }
            }
            let proj = try db.prepare("INSERT INTO project(key, data) VALUES (?, ?)")
            func put(_ key: String, _ data: Data) throws {
                proj.reset(); try proj.bind(1, key); try proj.bind(2, data); try proj.step()
            }
            try put(ProjectKey.nextID, try enc.encode(model.nextID))
            try put(ProjectKey.revision, try enc.encode(model.revision))
            try put(ProjectKey.projectParameters, try enc.encode(model.projectParameters))
            try put(ProjectKey.viewSheetSets, try enc.encode(model.viewSheetSets))
            try put(ProjectKey.referenceDrawings, try enc.encode(drawingIndex))
            let m = try db.prepare("INSERT INTO meta(key, value) VALUES (?, ?)")
            for (k, v) in [("schema_version", "2"), ("writer_app_version", meta.appVersion), ("writer_build", meta.build),
                           ("document_id", meta.documentID.uuidString), ("element_count", String(elements.count)),
                           ("created", ManifestDates.format(meta.created)), ("modified", ManifestDates.format(meta.modified))] {
                m.reset(); try m.bind(1, k); try m.bind(2, v); try m.step()
            }
            try db.exec(indexesV2)
            try db.exec("COMMIT")
        } catch {
            try? db.exec("ROLLBACK")
            throw error
        }
        return try db.serialize()
    }

    // MARK: Read

    enum Layout: Int { case v1 = 1, v2 = 2 }

    struct Row {
        var id: Int64
        var category: String
        var kind: String?
        var data: Data
    }

    /// Raw content of a model database before element decoding.
    struct RawModel {
        var layout: Layout
        var rows: [Row] = []
        var nextID: UInt64?
        var revision: UInt64?
        var projectParameters: [ParameterDefinition]?
        var viewSheetSets: [ViewSheetSet]?
        /// v2: model drawing key → asset file name.
        var drawingIndex: [String: String] = [:]
        /// v1: model drawing key → ReferenceDrawing JSON.
        var inlineDrawings: [String: Data] = [:]
        /// Problems encountered in salvage mode.
        var problems: [String] = []
    }

    static func detectLayout(_ db: SQLiteDatabase) throws -> Layout {
        let userVersion = try db.scalarInt("PRAGMA user_version") ?? 0
        guard try db.tableExists("elements") else { throw SQLiteError(code: 0, message: "the model database has no elements table") }
        let hasDrawings = try db.tableExists("drawings")
        if userVersion == 1 || hasDrawings { return .v1 }
        if userVersion >= 2, try db.tableExists("project") { return .v2 }
        throw SQLiteError(code: 0, message: "unrecognised model database layout (user_version \(userVersion))")
    }

    /// Reads everything. In strict mode the first error throws; in salvage mode errors become `problems`.
    static func read(_ db: SQLiteDatabase, limits: PersistenceLimits, salvage: Bool) throws -> RawModel {
        let layout: Layout
        do { layout = try detectLayout(db) } catch {
            if !salvage { throw error }
            // Best guess: v2 if a project table exists.
            layout = ((try? db.tableExists("project")) ?? false) ? .v2 : .v1
        }
        var raw = RawModel(layout: layout)

        // Element count limit before loading anything large.
        if let count = try? db.scalarInt("SELECT COUNT(*) FROM elements"), count > Int64(limits.maxElements) {
            throw LimitError("the document has \(count) elements; the limit is \(limits.maxElements)")
        }

        raw.rows = try readRows(db, layout: layout, limits: limits, salvage: salvage, problems: &raw.problems)

        switch layout {
        case .v2:
            let values = try readKeyed(db, sql: "SELECT key, data, length(data) FROM project", limits: limits, salvage: salvage, problems: &raw.problems)
            try decodeProject(values, into: &raw, limits: limits, salvage: salvage)
            if let idx = values[ProjectKey.referenceDrawings] {
                do { raw.drawingIndex = try StoredJSON.decode([String: String].self, from: idx, limits: limits, maxBytes: limits.maxProjectValueBytes, what: "the drawing index") } catch {
                    if !salvage { throw error }
                    raw.problems.append("The reference drawing index is unreadable (\(error)).")
                }
            }
        case .v1:
            let values = try readKeyed(db, sql: "SELECT key, CAST(value AS BLOB), length(value) FROM meta", limits: limits, salvage: salvage, problems: &raw.problems)
            try decodeProject(values, into: &raw, limits: limits, salvage: salvage)
            if (try? db.tableExists("drawings")) == true {
                raw.inlineDrawings = try readKeyed(db, sql: "SELECT key, data, length(data) FROM drawings", limits: limits, salvage: salvage, problems: &raw.problems)
            }
        }
        return raw
    }

    private static func decodeProject(_ values: [String: Data], into raw: inout RawModel, limits: PersistenceLimits, salvage: Bool) throws {
        func value<T: Decodable>(_ key: String, _ t: T.Type) throws -> T? {
            guard let d = values[key] else { return nil }
            do { return try StoredJSON.decode(T.self, from: d, limits: limits, maxBytes: limits.maxProjectValueBytes, what: "project value “\(key)”") } catch {
                if !salvage { throw error }
                raw.problems.append("Project value “\(key)” is unreadable and was reset (\(ElementCodec.describe(error))).")
                return nil
            }
        }
        raw.nextID = try value(ProjectKey.nextID, UInt64.self)
        raw.revision = try value(ProjectKey.revision, UInt64.self)
        raw.projectParameters = try value(ProjectKey.projectParameters, [ParameterDefinition].self)
        raw.viewSheetSets = try value(ProjectKey.viewSheetSets, [ViewSheetSet].self)
    }

    private static func readKeyed(_ db: SQLiteDatabase, sql: String, limits: PersistenceLimits, salvage: Bool, problems: inout [String]) throws -> [String: Data] {
        var out: [String: Data] = [:]
        do {
            let s = try db.prepare(sql)
            while try s.step() {
                guard let k = s.text(0) else { continue }
                if s.int64(2) > Int64(limits.maxProjectValueBytes) {
                    let msg = "project value “\(k)” is \(s.int64(2)) bytes; the limit is \(limits.maxProjectValueBytes)"
                    if !salvage { throw LimitError(msg) }
                    problems.append(msg); continue
                }
                out[k] = s.blob(1)
            }
        } catch {
            if !salvage { throw error }
            problems.append("Some project data could not be read (\(error)).")
        }
        return out
    }

    private static func readRows(_ db: SQLiteDatabase, layout: Layout, limits: PersistenceLimits, salvage: Bool, problems: inout [String]) throws -> [Row] {
        let sql = layout == .v2
            ? "SELECT id, category, kind, length(data), data FROM elements WHERE id > ? ORDER BY id"
            : "SELECT id, category, NULL, length(data), data FROM elements WHERE id > ? ORDER BY id"
        var rows: [Row] = []
        var cursor = Int64.min
        var failures = 0
        while true {
            do {
                let s = try db.prepare(sql)
                try s.bind(1, cursor)
                while try s.step() {
                    let id = s.int64(0)
                    cursor = id
                    let size = s.int64(3)
                    if size > Int64(limits.maxElementBytes) {
                        let msg = "element #\(id) data is \(size) bytes; the limit is \(limits.maxElementBytes)"
                        if !salvage { throw LimitError(msg) }
                        problems.append(msg)
                        continue
                    }
                    rows.append(Row(id: id, category: s.text(1) ?? "", kind: s.isNull(2) ? nil : s.text(2), data: s.blob(4)))
                    if rows.count > limits.maxElements { throw LimitError("the document has more than \(limits.maxElements) elements") }
                }
                return rows
            } catch let e as LimitError {
                throw e
            } catch {
                if !salvage { throw error }
                failures += 1
                if failures == 1 { problems.append("The element table is damaged (\(error)); skipping unreadable rows.") }
                if failures > 20_000 { problems.append("Gave up scanning damaged element rows after \(failures) attempts."); return rows }
                if cursor == Int64.min { cursor = 0 }
                let step: Int64 = failures < 256 ? 1 : Int64(1) << Int64(min(40, failures / 256))
                let (next, overflow) = cursor.addingReportingOverflow(step)
                if overflow { return rows }
                cursor = next
            }
        }
    }

    // MARK: Legacy v1 writer (fixtures and migration tests only)

    /// Writes the documented v1 layout. Arcus never writes v1 documents in normal operation.
    static func writeV1(_ model: BIMModel) throws -> Data {
        let enc = StoredJSON.encoder()
        let db = try SQLiteDatabase.inMemory()
        try db.exec("""
        PRAGMA user_version = 1;
        CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE elements(id INTEGER PRIMARY KEY, category TEXT NOT NULL, data BLOB NOT NULL);
        CREATE TABLE drawings(key TEXT PRIMARY KEY, data BLOB NOT NULL);
        """)
        try db.exec("BEGIN")
        let blobs = try ElementCodec.encode(model.allElements)
        let ins = try db.prepare("INSERT INTO elements(id, category, data) VALUES (?, ?, ?)")
        for (i, e) in model.allElements.enumerated() {
            ins.reset(); try ins.bind(1, Int64(e.id.raw)); try ins.bind(2, e.category.rawValue); try ins.bind(3, blobs[i]); try ins.step()
        }
        let m = try db.prepare("INSERT INTO meta(key, value) VALUES (?, ?)")
        for (k, v) in [(ProjectKey.nextID, try enc.encode(model.nextID)), (ProjectKey.revision, try enc.encode(model.revision)),
                       (ProjectKey.projectParameters, try enc.encode(model.projectParameters)), (ProjectKey.viewSheetSets, try enc.encode(model.viewSheetSets))] {
            m.reset(); try m.bind(1, k); try m.bind(2, String(decoding: v, as: UTF8.self)); try m.step()
        }
        m.reset(); try m.bind(1, "schema_version"); try m.bind(2, "1"); try m.step()
        let d = try db.prepare("INSERT INTO drawings(key, data) VALUES (?, ?)")
        for (k, drawing) in model.referenceDrawings.sorted(by: { $0.key < $1.key }) {
            d.reset(); try d.bind(1, k); try d.bind(2, try enc.encode(drawing)); try d.step()
        }
        try db.exec("COMMIT")
        return try db.serialize()
    }
}
