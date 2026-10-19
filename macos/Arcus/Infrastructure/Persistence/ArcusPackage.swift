import Foundation
import OSLog
import ArcusDomain

/// The `.arcus` project package: a directory containing `manifest.json`, `model.sqlite`, `assets/` and
/// `thumbnails/preview.png`. See Docs/FileFormat.md.
public enum ArcusPackage {
    /// Layout version written by this build. Schema 3 keeps the package and SQL layout of schema 2 and adds element
    /// data that schema-2 readers can't decode (every new field decodes with a default, so schema-2 files open):
    /// - Floors, roofs, stairs and ramps: `ElementData.ramp` / category `ramps`, `ConstraintData.Kind.join` (Join
    ///   Geometry), `RoofData.extrusion` (Roof by Extrusion), `SlabData.shapePoints` / `RoofData.shapePoints`.
    /// - Families: sweep, blend, revolve and nested forms (with `.arcusfamily` schema 2 and the manifest's `isTemplate`).
    /// - Views and datums: `scopeBoxID` on levels, grids, reference planes and views, `ElementData.scopeBox`,
    ///   `VisibilityGraphics.shownOptInCategories`, categories scopeBoxes, projectBasePoint, surveyPoint and cameras.
    /// - Documentation: `ViewData.colorSchemeID` / `areaSchemeID`, `AreaSchemeData.boundaryRule`,
    ///   `DimensionData.chainStyle`, `ElementData.colorScheme` / `colorFillLegend`.
    /// - Groups: `GroupData.arraySpec`.
    public static let currentSchemaVersion: Int = 3
    /// This build reads packages whose `minimumReaderVersion` is at most this value.
    public static let readerVersion: Int = 3
    /// `minimumReaderVersion` written by this build: schema-2 builds refuse schema-3 files with a "newer format"
    /// message instead of failing on element kinds they don't know.
    public static let minimumReaderVersionWritten: Int = 3
    /// Oldest schema version this build can read (older ones are migrated on read).
    public static let oldestReadableSchema: Int = 1

    public static let fileExtension = "arcus"
    /// FM3: Furniture documents use the same package with their own extension and format.
    public static let furnitureFileExtension = "arcusfurniture"
    public static let manifestPath = "manifest.json"
    public static let modelPath = "model.sqlite"
    public static let assetsDirectory = "assets"
    public static let thumbnailPath = "thumbnails/preview.png"

    static let log = Logger(subsystem: "com.local.arcus", category: "Persistence")

    public struct WriteInfo: Sendable, Hashable {
        public var documentID: UUID
        public var appVersion: String
        public var build: String
        /// Creation date to preserve (nil = now).
        public var created: Date?
        public var thumbnailPNG: Data?
        /// Marks the package as a project template (manifest `isTemplate`).
        public var isTemplate: Bool = false
        public init(documentID: UUID = UUID(), appVersion: String, build: String, created: Date? = nil, thumbnailPNG: Data? = nil) {
            self.documentID = documentID; self.appVersion = appVersion; self.build = build; self.created = created; self.thumbnailPNG = thumbnailPNG
        }
    }

    // MARK: Writing

    /// Writes a complete `.arcus` package directory at `url` (staged in a temporary directory on the same volume,
    /// then moved into place; an existing item at `url` is replaced atomically).
    public static func write(_ model: BIMModel, to url: URL, info: WriteInfo) throws {
        try PackageWriter.write(try files(model, info: info), to: url)
    }

    /// The package as a directory `FileWrapper` (for `NSDocument.fileWrapper(ofType:)`).
    public static func fileWrapper(_ model: BIMModel, info: WriteInfo) throws -> FileWrapper {
        PackageWriter.fileWrapper(try files(model, info: info))
    }

    /// Serialized package contents, manifest last.
    static func files(_ model: BIMModel, info: WriteInfo) throws -> PackageWriter.Files {
        let now = Date()
        let created = info.created ?? now
        var files: PackageWriter.Files = []
        var checksums: [String: String] = [:]

        // Reference drawings → content-keyed compressed assets.
        var index: [String: String] = [:]
        var assets: [String: Data] = [:]
        let enc = StoredJSON.encoder()
        for (key, drawing) in model.referenceDrawings.sorted(by: { $0.key < $1.key }) {
            let json: Data
            do { json = try enc.encode(drawing) } catch {
                throw PersistenceError(.corrupt("drawing \(key)"), "Reference drawing “\(key)” couldn’t be encoded: \(error)")
            }
            let name = Checksum.hex(json) + "." + AssetCodec.Algorithm.lzfse.fileExtension
            index[key] = name
            if assets[name] == nil { assets[name] = try AssetCodec.encode(json, algorithm: .lzfse) }
        }

        let sqlite: Data
        do {
            sqlite = try ModelStore.writeV2(model, drawingIndex: index, meta: .init(appVersion: info.appVersion, build: info.build, documentID: info.documentID, created: created, modified: now))
        } catch let e as PersistenceError { throw e } catch {
            throw PersistenceError(.io(String(describing: error)), "Arcus couldn’t build the document database: \(error)")
        }
        files.append((modelPath, sqlite))
        checksums[modelPath] = Checksum.hex(sqlite)
        for (name, data) in assets.sorted(by: { $0.key < $1.key }) {
            let p = assetsDirectory + "/" + name
            files.append((p, data))
            checksums[p] = Checksum.hex(data)
        }
        if let png = info.thumbnailPNG { files.append((thumbnailPath, png)) }

        let furniture = model.isFurniture // FM3
        var manifest = PackageManifest(format: furniture ? PackageManifest.furnitureFormat : PackageManifest.projectFormat, schemaVersion: currentSchemaVersion,
                                       minimumReaderVersion: minimumReaderVersionWritten, writerAppVersion: info.appVersion,
                                       writerBuild: info.build, documentID: info.documentID, created: created, modified: now,
                                       elementCount: model.count, checksums: checksums, isTemplate: info.isTemplate ? true : nil)
        if furniture { manifest.kind = DocumentKind.furniture.rawValue }
        files.append((manifestPath, try manifest.encoded()))
        return files
    }

    /// Writes `model` as a project template: model elements removed (see `ProjectTemplates.templateModel(from:)`)
    /// and the manifest flagged `isTemplate`.
    public static func writeTemplate(_ model: BIMModel, to url: URL, info: WriteInfo) throws {
        var i = info
        i.isTemplate = true
        try write(ProjectTemplates.templateModel(from: model), to: url, info: i)
    }

    // MARK: Reading

    public static func read(from url: URL) throws -> (model: BIMModel, manifest: PackageManifest) {
        try read(from: url, limits: .default)
    }
    public static func read(from url: URL, limits: PersistenceLimits) throws -> (model: BIMModel, manifest: PackageManifest) {
        try read(DirectorySource(root: url), limits: limits)
    }
    public static func read(fileWrapper: FileWrapper) throws -> (model: BIMModel, manifest: PackageManifest) {
        try read(WrapperSource(wrapper: fileWrapper), limits: .default)
    }
    public static func read(fileWrapper: FileWrapper, limits: PersistenceLimits) throws -> (model: BIMModel, manifest: PackageManifest) {
        try read(WrapperSource(wrapper: fileWrapper), limits: limits)
    }

    /// Reads and validates only the manifest (format identifier and parseability; version gating is left to the caller).
    public static func readManifest(_ url: URL) throws -> PackageManifest {
        try loadManifest(DirectorySource(root: url), limits: .default, format: PackageManifest.projectFormat)
    }

    /// The optional preview image.
    public static func readThumbnail(_ url: URL, limits: PersistenceLimits = .default) -> Data? {
        try? DirectorySource(root: url).read(thumbnailPath, maxBytes: limits.maxThumbnailBytes)
    }

    /// True when the package was written by a newer schema that this build can read but would not round-trip
    /// completely (unknown additive data is dropped on save). Callers should warn before overwriting.
    public static func isNewerThanCurrent(_ manifest: PackageManifest) -> Bool { manifest.schemaVersion > currentSchemaVersion }

    static func read(_ source: some PackageSource, limits: PersistenceLimits) throws -> (model: BIMModel, manifest: PackageManifest) {
        let url = source.displayURL
        let manifest = try loadManifest(source, limits: limits, format: PackageManifest.projectFormat)
        try gate(manifest, url: url)
        try verifyChecksums(source, manifest: manifest, required: [modelPath])

        let raw: ModelStore.RawModel
        do {
            let db = try source.openDatabase(modelPath)
            defer { db.close() }
            raw = try ModelStore.read(db, limits: limits, salvage: false)
        } catch let e as PersistenceError { throw e } catch let e as LimitError {
            throw PersistenceError.limit(url, e.description)
        } catch let e as TooLarge {
            throw PersistenceError.limit(url, "file is \(e.size) bytes")
        } catch {
            throw PersistenceError.corrupt(url, "the model database is unreadable: \(error)")
        }

        var elements: [Element] = []
        elements.reserveCapacity(raw.rows.count)
        let decoded = ElementCodec.decode(raw.rows.map(\.data), limits: limits)
        for (row, result) in zip(raw.rows, decoded) {
            switch result {
            case .success(let e):
                guard Int64(bitPattern: e.id.raw) == row.id else {
                    throw PersistenceError.corrupt(url, "element row #\(row.id) contains element \(e.id)")
                }
                guard IFCGUID(e.ifcGUID.value) != nil else {
                    throw PersistenceError.corrupt(url, "element #\(row.id) has an invalid IFC GUID")
                }
                elements.append(e)
            case .failure(let f):
                if f.isLimit { throw PersistenceError.limit(url, "element #\(row.id): \(f.message)") }
                throw PersistenceError.corrupt(url, "element #\(row.id) can’t be decoded: \(f.message)")
            }
        }

        var ignored: [String] = []
        let drawings = try loadDrawings(source, raw: raw, manifest: manifest, limits: limits, salvage: false, problems: &ignored)
        let maxID = elements.last.map { $0.id.raw + 1 } ?? 1
        let model = BIMModel(elements: elements, nextID: max(raw.nextID ?? 1, maxID), referenceDrawings: drawings,
                             projectParameters: raw.projectParameters ?? [], viewSheetSets: raw.viewSheetSets ?? [],
                             revision: raw.revision ?? 0)
        if raw.layout == .v1 {
            log.info("Migrated a schema v1 document (\(elements.count) elements) to the current in-memory model")
        }
        return (model, manifest)
    }

    static func loadManifest(_ source: some PackageSource, limits: PersistenceLimits, format: String) throws -> PackageManifest {
        let url = source.displayURL
        guard source.isPackageDirectory else { throw format == PackageManifest.familyFormat ? PersistenceError.notAFamily(url) : PersistenceError.notAPackage(url) }
        let data: Data?
        do { data = try source.read(manifestPath, maxBytes: limits.maxManifestBytes) } catch let e as TooLarge {
            throw PersistenceError.limit(url, "manifest.json is \(e.size) bytes")
        } catch {
            throw PersistenceError.io(url, "read", error)
        }
        guard let data else { throw format == PackageManifest.familyFormat ? PersistenceError.notAFamily(url) : PersistenceError.notAPackage(url) }
        guard StoredJSON.depthWithinLimit(data, limit: 16) else { throw PersistenceError.corrupt(url, "manifest.json is malformed") }
        let manifest: PackageManifest
        do { manifest = try PackageManifest.decode(data) } catch {
            throw PersistenceError.corrupt(url, "manifest.json is unreadable")
        }
        guard manifest.format == format || (format == PackageManifest.projectFormat && PackageManifest.projectFormats.contains(manifest.format)) else { // FM3: Furniture documents read as projects
            throw format == PackageManifest.familyFormat ? PersistenceError.notAFamily(url) : PersistenceError.notAPackage(url)
        }
        return manifest
    }

    static func gate(_ manifest: PackageManifest, url: URL?, reader: Int = readerVersion, oldest: Int = oldestReadableSchema) throws {
        if manifest.minimumReaderVersion > reader { throw PersistenceError.newer(url, manifest: manifest, reader: reader) }
        if manifest.schemaVersion < oldest { throw PersistenceError.unsupported(url, manifest.schemaVersion) }
    }

    /// Verifies every checksum listed in the manifest; `required` paths must be listed.
    static func verifyChecksums(_ source: some PackageSource, manifest: PackageManifest, required: [String]) throws {
        let url = source.displayURL
        for r in required where manifest.checksums[r] == nil {
            throw PersistenceError.corrupt(url, "the manifest has no checksum for \(r)")
        }
        for (path, expected) in manifest.checksums.sorted(by: { $0.key < $1.key }) {
            guard SafeName.isValidRelativePath(path) else { throw PersistenceError.corrupt(url, "the manifest lists an invalid path") }
            let actual: String?
            do { actual = try source.sha256(path) } catch { throw PersistenceError.io(url, "read", error) }
            guard let actual else { throw PersistenceError.corrupt(url, "\(path) is missing") }
            guard actual == expected.lowercased() else { throw PersistenceError.checksum(url, path: path) }
        }
    }

    /// Loads reference drawings (v2 assets or v1 inline rows). In salvage mode problems are collected instead of thrown.
    static func loadDrawings(_ source: some PackageSource, raw: ModelStore.RawModel, manifest: PackageManifest?, limits: PersistenceLimits,
                             salvage: Bool, problems: inout [String]) throws -> [String: ReferenceDrawing] {
        let url = source.displayURL
        var out: [String: ReferenceDrawing] = [:]
        func fail(_ e: PersistenceError) throws {
            if !salvage { throw e }
            problems.append(e.kindDetail)
        }
        switch raw.layout {
        case .v1:
            for (key, json) in raw.inlineDrawings.sorted(by: { $0.key < $1.key }) {
                do { out[key] = try StoredJSON.decode(ReferenceDrawing.self, from: json, limits: limits, maxBytes: limits.maxAssetBytes, what: "reference drawing") } catch let e as LimitError {
                    try fail(.limit(url, e.description))
                } catch {
                    try fail(.corrupt(url, "reference drawing “\(key)” can’t be decoded"))
                }
            }
        case .v2:
            guard raw.drawingIndex.count <= limits.maxAssets else {
                try fail(.limit(url, "\(raw.drawingIndex.count) assets")); return out
            }
            var cache: [String: ReferenceDrawing] = [:]
            for (key, name) in raw.drawingIndex.sorted(by: { $0.key < $1.key }) {
                guard SafeName.isValidComponent(name) else { try fail(.corrupt(url, "invalid asset name “\(name)”")); continue }
                if let d = cache[name] { out[key] = d; continue }
                let path = assetsDirectory + "/" + name
                if let manifest, manifest.checksums[path] == nil, !salvage {
                    try fail(.corrupt(url, "asset \(name) is not listed in the manifest")); continue
                }
                do {
                    guard let packed = try source.read(path, maxBytes: limits.maxAssetBytes) else { try fail(.corrupt(url, "asset \(name) is missing")); continue }
                    let json = try AssetCodec.decode(packed, limits: limits)
                    let stem = name.split(separator: ".").first.map(String.init) ?? ""
                    guard stem == Checksum.hex(json) else { try fail(.checksum(url, path: path)); continue }
                    let d = try StoredJSON.decode(ReferenceDrawing.self, from: json, limits: limits, maxBytes: limits.maxAssetBytes, what: "reference drawing")
                    cache[name] = d
                    out[key] = d
                } catch let e as PersistenceError {
                    throw e
                } catch let e as AssetCodec.DecodeError {
                    if case .limit(let s) = e { try fail(.limit(url, s)) } else { try fail(.corrupt(url, "asset \(name): \(e.description)")) }
                } catch let e as LimitError {
                    try fail(.limit(url, e.description))
                } catch let e as TooLarge {
                    try fail(.limit(url, "asset \(name) is \(e.size) bytes"))
                } catch {
                    try fail(.corrupt(url, "asset \(name) can’t be decoded"))
                }
            }
        }
        return out
    }

    // MARK: Verification

    /// Full integrity check: manifest, checksums, SQLite `integrity_check` and `foreign_key_check`, element decoding,
    /// relations consistency and reference sanity. Never throws.
    public static func verify(_ url: URL) -> IntegrityReport {
        verify(DirectorySource(root: url), limits: .default)
    }

    static func verify(_ source: some PackageSource, limits: PersistenceLimits) -> IntegrityReport {
        var problems: [String] = []
        let manifest: PackageManifest
        do { manifest = try loadManifest(source, limits: limits, format: PackageManifest.projectFormat) } catch let e as PersistenceError {
            return IntegrityReport(isHealthy: false, problems: [e.description], recoveredElements: 0, lostElements: 0)
        } catch {
            return IntegrityReport(isHealthy: false, problems: ["\(error)"], recoveredElements: 0, lostElements: 0)
        }
        if manifest.minimumReaderVersion > readerVersion {
            return IntegrityReport(isHealthy: false, problems: [PersistenceError.newer(source.displayURL, manifest: manifest, reader: readerVersion).description],
                                   recoveredElements: 0, lostElements: 0)
        }
        if manifest.checksums[modelPath] == nil { problems.append("The manifest has no checksum for model.sqlite.") }
        for (path, expected) in manifest.checksums.sorted(by: { $0.key < $1.key }) {
            guard SafeName.isValidRelativePath(path) else { problems.append("The manifest lists an invalid path."); continue }
            switch Result(catching: { try source.sha256(path) }) {
            case .success(nil): problems.append("\(path) is missing.")
            case .success(let actual?): if actual != expected.lowercased() { problems.append("\(path) doesn’t match its checksum.") }
            case .failure(let e): problems.append("\(path) can’t be read (\(e)).")
            }
        }
        for name in source.list(assetsDirectory) where manifest.checksums[assetsDirectory + "/" + name] == nil {
            problems.append("assets/\(name) is not listed in the manifest.")
        }

        let db: SQLiteDatabase
        do { db = try source.openDatabase(modelPath) } catch {
            problems.append("model.sqlite can’t be opened (\(error)).")
            return IntegrityReport(isHealthy: false, problems: problems, recoveredElements: 0, lostElements: manifest.elementCount)
        }
        defer { db.close() }
        do {
            let ic = try db.strings("PRAGMA integrity_check(50)")
            if ic != ["ok"] { problems += ic.prefix(20).map { "SQLite integrity: \($0)" } }
        } catch { problems.append("SQLite integrity check failed (\(error)).") }
        do {
            let s = try db.prepare("PRAGMA foreign_key_check")
            var n = 0
            while try s.step() {
                n += 1
                if n <= 20 { problems.append("Foreign key violation in \(s.text(0) ?? "?") row \(s.int64(1)).") }
            }
        } catch { problems.append("SQLite foreign key check failed (\(error)).") }

        let raw: ModelStore.RawModel
        do { raw = try ModelStore.read(db, limits: limits, salvage: true) } catch {
            problems.append("The model can’t be read (\(error)).")
            return IntegrityReport(isHealthy: false, problems: problems, recoveredElements: 0, lostElements: manifest.elementCount)
        }
        problems += raw.problems
        var elements: [ElementID: Element] = [:]
        var failed = 0
        for (row, r) in zip(raw.rows, ElementCodec.decode(raw.rows.map(\.data), limits: limits)) {
            switch r {
            case .success(let e):
                if Int64(bitPattern: e.id.raw) != row.id { problems.append("Row #\(row.id) contains element \(e.id).") ; failed += 1; continue }
                if IFCGUID(e.ifcGUID.value) == nil { problems.append("Element \(e.id) has an invalid IFC GUID.") }
                if row.category != e.category.rawValue { problems.append("Element \(e.id) category column (\(row.category)) doesn’t match its data.") }
                if let k = row.kind, k != e.kind.rawValue { problems.append("Element \(e.id) kind column (\(k)) doesn’t match its data.") }
                elements[e.id] = e
            case .failure(let f):
                failed += 1
                if failed <= 50 { problems.append("Element #\(row.id) can’t be decoded (\(f.message)).") }
            }
        }
        if failed > 50 { problems.append("…and \(failed - 50) more undecodable elements.") }
        if raw.rows.count != manifest.elementCount {
            problems.append("The manifest records \(manifest.elementCount) elements but the database contains \(raw.rows.count).")
        }
        // Reference sanity.
        var dangling = 0
        var derived = Set<String>()
        for e in elements.values.sorted(by: { $0.id < $1.id }) {
            for r in RelationRoles.references(of: e) {
                if elements[r.target] == nil {
                    dangling += 1
                    if dangling <= 50 { problems.append("Element \(e.id) refers to missing element \(r.target) (\(r.role)).") }
                } else {
                    derived.insert("\(e.id.raw)|\(r.target.raw)|\(r.role)")
                }
            }
        }
        if dangling > 50 { problems.append("…and \(dangling - 50) more dangling references.") }
        if let next = raw.nextID, let maxID = elements.keys.max(), next <= maxID.raw {
            problems.append("The next element id (\(next)) is not above the highest id (\(maxID.raw)).")
        }
        if raw.layout == .v2 {
            do {
                let s = try db.prepare("SELECT element_id, related_id, role FROM relations")
                var stored = Set<String>()
                while try s.step() { stored.insert("\(s.int64(0))|\(s.int64(1))|\(s.text(2) ?? "")") }
                if stored != derived {
                    problems.append("The relations table is out of date (\(stored.subtracting(derived).count) stale, \(derived.subtracting(stored).count) missing rows).")
                }
            } catch { problems.append("The relations table can’t be read (\(error)).") }
        }
        var drawingProblems: [String] = []
        _ = try? loadDrawings(source, raw: raw, manifest: manifest, limits: limits, salvage: true, problems: &drawingProblems)
        problems += drawingProblems
        let lost = failed + max(0, manifest.elementCount - raw.rows.count)
        return IntegrityReport(isHealthy: problems.isEmpty, problems: problems, recoveredElements: elements.count, lostElements: lost)
    }

    // MARK: Recovery copy

    /// Writes a new package at `dest` containing every element (and project value / drawing) that still decodes from
    /// the possibly damaged package at `url`. Checksum mismatches are reported but don't stop extraction.
    /// The source is never modified.
    @discardableResult
    public static func saveRecoveryCopy(from url: URL, to dest: URL, info: WriteInfo) throws -> IntegrityReport {
        try saveRecoveryCopy(DirectorySource(root: url), to: dest, info: info, limits: .default)
    }

    static func saveRecoveryCopy(_ source: some PackageSource, to dest: URL, info: WriteInfo, limits: PersistenceLimits) throws -> IntegrityReport {
        let url = source.displayURL
        guard source.isPackageDirectory else { throw PersistenceError.notAPackage(url) }
        var problems: [String] = []
        var manifest: PackageManifest?
        do { manifest = try loadManifest(source, limits: limits, format: PackageManifest.projectFormat) } catch {
            problems.append("The manifest is unreadable; recovering from the database alone.")
        }
        if let m = manifest {
            if m.minimumReaderVersion > readerVersion { throw PersistenceError.newer(url, manifest: m, reader: readerVersion) }
            for (path, expected) in m.checksums.sorted(by: { $0.key < $1.key }) where SafeName.isValidRelativePath(path) {
                if let actual = try? source.sha256(path), actual != expected.lowercased() { problems.append("\(path) doesn’t match its checksum.") }
            }
        }
        var raw = ModelStore.RawModel(layout: .v2)
        do {
            let db = try source.openDatabase(modelPath)
            defer { db.close() }
            raw = try ModelStore.read(db, limits: limits, salvage: true)
            problems += raw.problems
        } catch let e as LimitError {
            throw PersistenceError.limit(url, e.description)
        } catch {
            problems.append("model.sqlite can’t be opened (\(error)); no elements could be recovered.")
        }
        var elements: [Element] = []
        var failed = 0
        let documentKey = (manifest?.documentID ?? info.documentID).uuidString
        for (row, r) in zip(raw.rows, ElementCodec.decode(raw.rows.map(\.data), limits: limits)) {
            if case .success(var e) = r, Int64(bitPattern: e.id.raw) == row.id {
                if IFCGUID(e.ifcGUID.value) == nil {
                    e.ifcGUID = .deterministic("arcus-recovered-\(documentKey)-\(e.id.raw)")
                    problems.append("Element \(e.id) had an invalid IFC GUID; a new one was assigned.")
                }
                elements.append(e)
            } else {
                failed += 1
                if failed <= 50 { problems.append("Element #\(row.id) couldn’t be recovered.") }
            }
        }
        var drawingProblems: [String] = []
        let drawings = (try? loadDrawings(source, raw: raw, manifest: manifest, limits: limits, salvage: true, problems: &drawingProblems)) ?? [:]
        problems += drawingProblems
        let maxID = elements.map(\.id.raw).max().map { $0 + 1 } ?? 1
        let model = BIMModel(elements: elements, nextID: max(raw.nextID ?? 1, maxID), referenceDrawings: drawings,
                             projectParameters: raw.projectParameters ?? [], viewSheetSets: raw.viewSheetSets ?? [], revision: raw.revision ?? 0)
        try write(model, to: dest, info: info)
        let lost = failed + max(0, (manifest?.elementCount ?? 0) - raw.rows.count)
        log.notice("Recovery copy written: \(elements.count) recovered, \(lost) lost")
        return IntegrityReport(isHealthy: problems.isEmpty && lost == 0, problems: problems, recoveredElements: elements.count, lostElements: lost)
    }

    // MARK: Test / tooling support

    /// Recomputes the manifest checksums of an existing package in place (tests and repair tooling).
    static func rewriteChecksums(at url: URL) throws {
        let src = DirectorySource(root: url)
        var m = try loadManifest(src, limits: .default, format: PackageManifest.projectFormat)
        var sums: [String: String] = [:]
        if let h = try src.sha256(modelPath) { sums[modelPath] = h }
        for name in src.list(assetsDirectory) { if let h = try src.sha256(assetsDirectory + "/" + name) { sums[assetsDirectory + "/" + name] = h } }
        m.checksums = sums
        try m.encoded().write(to: url.appending(path: manifestPath), options: .atomic)
    }

    /// Writes a documented schema v1 package (migration fixtures only).
    static func writeLegacyV1(_ model: BIMModel, to url: URL, info: WriteInfo) throws {
        let sqlite = try ModelStore.writeV1(model)
        let manifest = PackageManifest(format: PackageManifest.projectFormat, schemaVersion: 1, minimumReaderVersion: 1,
                                       writerAppVersion: info.appVersion, writerBuild: info.build, documentID: info.documentID,
                                       created: info.created ?? Date(), modified: info.created ?? Date(), elementCount: model.count,
                                       checksums: [modelPath: Checksum.hex(sqlite)])
        try PackageWriter.write([(modelPath, sqlite), (manifestPath, try manifest.encoded())], to: url)
    }
}

extension PersistenceError {
    /// Short description for problem lists.
    var kindDetail: String {
        switch kind {
        case .corrupt(let s): s
        case .checksumMismatch(let p): "\(p) doesn’t match its checksum"
        case .limitExceeded(let s): "safety limit: \(s)"
        default: description
        }
    }
}
