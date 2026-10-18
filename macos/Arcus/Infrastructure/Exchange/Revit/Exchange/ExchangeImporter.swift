import Foundation
import ArcusGeometry
import ArcusDomain

public enum ExchangeDocumentKind: String, Sendable, Hashable {
    case project, family
}

/// Options for `ArcusExchangeImporter`.
public struct ExchangeImportOptions: Sendable {
    /// What to do when the target model already has an element with the GlobalId derived from a source `uniqueId`
    /// (re-importing an updated export).
    public enum ExistingElementPolicy: String, Sendable, CaseIterable {
        /// Overwrite the existing element's data from the file, keeping its Arcus id (default).
        case update
        /// Leave the existing element untouched and reference it.
        case keep
        /// Create a new element with a new GlobalId.
        case duplicate
    }
    /// How family geometry Arcus cannot represent exactly (non-rectangular vertical profiles, tessellated forms) is handled.
    public enum ApproximationPolicy: String, Sendable, CaseIterable {
        /// Replace it with a box of the same extents (reported as approximated). Voids are always skipped.
        case boundingBox
        /// Leave it out (reported as skipped).
        case skip
    }

    /// Largest accepted input (bytes).
    public var maxInputBytes = 256 << 20
    /// Largest number of listed objects.
    public var maxObjects = 500_000
    /// Largest triangle count of one mesh.
    public var maxTrianglesPerMesh = 500_000
    /// Largest triangle count over all meshes.
    public var maxTotalTriangles = 5_000_000
    /// Largest number of curves in one sketch or path.
    public var maxCurvesPerSketch = 10_000
    /// Coordinates farther than this from the origin (meters) are rejected.
    public var maxCoordinate = 1_000_000.0
    public var existingElements = ExistingElementPolicy.update
    /// Copy project information (name, number, address, location) into the model.
    public var applyProjectInfo = true
    /// Switch the model's display units to the file's unit system.
    public var applyUnits = false
    /// Create a floor plan view for each new level.
    public var createPlanViews = true
    /// Import fallback meshes as reference geometry.
    public var importMeshes = true
    public var unsupportedFamilyGeometry = ApproximationPolicy.boundingBox
    /// Reuse an existing level with the same name and elevation instead of creating a renamed copy.
    public var mergeLevelsByName = true
    /// Reuse an existing material with the same name instead of creating a copy.
    public var reuseMaterialsByName = true
    /// Validate the imported elements with a trial commit and drop any that would make the commit fail.
    public var validateWithTrialCommit = true
    /// File name recorded in element source metadata (defaults to the name stored in the file).
    public var fileName: String?

    public init() {}
}

/// A non-fatal issue found during import.
public struct ExchangeImportWarning: Hashable, Sendable, CustomStringConvertible {
    public var code: String
    public var message: String
    /// `id` of the object in the exchange file, when the warning concerns one.
    public var sourceID: String?
    public init(code: String, message: String, sourceID: String? = nil) { self.code = code; self.message = message; self.sourceID = sourceID }
    public var description: String { message }
}

/// Result of an import: what was created, updated, approximated or skipped, and why.
public struct ExchangeImportReport: Sendable {
    public var documentKind: ExchangeDocumentKind = .project
    public var schemaVersion: String = ""
    public var generator: String?
    public var sourceFileName: String?
    /// Native elements created, by kind ("walls", "doors", "types", "families", …).
    public var created: [String: Int] = [:]
    /// Existing elements updated in place (matched by GlobalId).
    public var updated: [String: Int] = [:]
    /// Existing elements kept unchanged (matched by GlobalId, `existingElements == .keep`).
    public var kept: [String: Int] = [:]
    /// Reference-geometry (mesh) elements created, by source category.
    public var referenceMeshes: [String: Int] = [:]
    /// Items imported with approximations, by kind.
    public var approximated: [String: Int] = [:]
    /// Items not imported, by kind.
    public var skipped: [String: Int] = [:]
    public var warnings: [ExchangeImportWarning] = []
    /// Converted family definitions (for writing `.arcusfamily` files).
    public var familyDefinitions: [FamilyDefinition] = []
    /// Exchange `id` → Arcus element for every imported object.
    public var elementMap: [String: ElementID] = [:]

    public init() {}

    public func created(_ kind: String) -> Int { created[kind] ?? 0 }
    public var totalCreated: Int { created.values.reduce(0, +) }
    public var totalReferenceMeshes: Int { referenceMeshes.values.reduce(0, +) }
    public var totalSkipped: Int { skipped.values.reduce(0, +) }
    public func hasWarning(_ code: String) -> Bool { warnings.contains { $0.code == code } }

    /// One-paragraph summary for the import dialog.
    public var summary: String {
        func list(_ d: [String: Int]) -> String { d.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)" }.joined(separator: ", ") }
        var parts: [String] = []
        if !created.isEmpty { parts.append("Created " + list(created) + ".") }
        if !updated.isEmpty { parts.append("Updated " + list(updated) + ".") }
        if !referenceMeshes.isEmpty { parts.append("Imported as reference geometry: " + list(referenceMeshes) + ".") }
        if !approximated.isEmpty { parts.append("Approximated: " + list(approximated) + ".") }
        if !skipped.isEmpty { parts.append("Skipped: " + list(skipped) + ".") }
        if !warnings.isEmpty { parts.append("\(warnings.count) warning\(warnings.count == 1 ? "" : "s").") }
        return parts.isEmpty ? "Nothing was imported." : parts.joined(separator: " ")
    }
}

/// Why an exchange file could not be imported at all. Problems with individual objects are warnings instead.
public enum ExchangeImportError: Error, Hashable, Sendable, CustomStringConvertible {
    case tooLarge(bytes: Int, limit: Int)
    case notJSON(String)
    case notArcusExchange
    case missingSchemaVersion
    case invalidSchemaVersion(String)
    case unsupportedSchemaVersion(found: String, supported: String)
    case tooManyObjects(Int, limit: Int)
    case unknownDocumentKind(String)

    public var description: String {
        switch self {
        case .tooLarge(let b, let l):
            "The file is too large to import (\(b >> 20) MB; the limit is \(l >> 20) MB)."
        case .notJSON(let m):
            "The file is not valid Arcus Exchange JSON: \(m)"
        case .notArcusExchange:
            "The file is not an Arcus Exchange file (its \"format\" is not \"\(ExchangeFormat.identifier)\")."
        case .missingSchemaVersion:
            "The file has no schemaVersion, so Arcus can't tell how to read it."
        case .invalidSchemaVersion(let v):
            "The file's schemaVersion “\(v)” is not a valid version number (expected MAJOR.MINOR, e.g. “1.0”)."
        case .unsupportedSchemaVersion(let found, let supported):
            "This file uses Arcus Exchange schema \(found), which is newer than this version of Arcus supports (\(supported)). "
                + "Update Arcus, or export again with an Arcus Bridge add-in that writes schema \(supported)."
        case .tooManyObjects(let n, let l):
            "The file lists \(n) objects, more than the import limit of \(l)."
        case .unknownDocumentKind(let k):
            "The file's documentKind “\(k)” is unknown (expected “project” or “family”)."
        }
    }
}

/// A family converted from an exchange file, without a project.
public struct ExchangeFamilyResult: Sendable {
    public var definition: FamilyDefinition
    public var warnings: [String]
}

/// Imports Arcus Exchange (`.arcusx`) files — written by the Arcus Bridge Revit add-in — as native, editable Arcus
/// elements, types, materials and loadable families.
public enum ArcusExchangeImporter {
    /// Parses and version-checks a document without importing it.
    public static func decode(_ data: Data, options: ExchangeImportOptions = .init()) throws(ExchangeImportError) -> (document: ExchangeDocument, minorNewer: Bool) {
        guard data.count <= options.maxInputBytes else { throw .tooLarge(bytes: data.count, limit: options.maxInputBytes) }
        let doc: ExchangeDocument
        do { doc = try JSONDecoder().decode(ExchangeDocument.self, from: data) } catch {
            throw .notJSON(Self.describe(error))
        }
        guard doc.format == ExchangeFormat.identifier else { throw .notArcusExchange }
        guard !doc.malformedSections.contains("schemaVersion") else { throw .invalidSchemaVersion("(not text)") }
        guard let raw = doc.schemaVersion else { throw .missingSchemaVersion }
        guard let (major, minor) = parseVersion(raw) else { throw .invalidSchemaVersion(raw) }
        if major > ExchangeFormat.schemaMajor {
            throw .unsupportedSchemaVersion(found: raw, supported: ExchangeFormat.schemaVersion)
        }
        guard major >= 1 else { throw .invalidSchemaVersion(raw) }
        if let k = doc.documentKind, ExchangeDocumentKind(rawValue: k) == nil { throw .unknownDocumentKind(k) }
        guard doc.objectCount <= options.maxObjects else { throw .tooManyObjects(doc.objectCount, limit: options.maxObjects) }
        return (doc, major == ExchangeFormat.schemaMajor && minor > ExchangeFormat.schemaMinor)
    }

    /// Imports `data` into the transaction. Returns a report; throws only when the file as a whole is unusable.
    /// The caller commits `tx` (the importer validates its own elements first when `validateWithTrialCommit` is on).
    public static func `import`(data: Data, into tx: TransactionContext, options: ExchangeImportOptions = .init()) throws(ExchangeImportError) -> ExchangeImportReport {
        let (doc, minorNewer) = try decode(data, options: options)
        return importDocument(doc, into: tx, options: options, minorNewer: minorNewer)
    }

    /// Imports a decoded document (see `decode`).
    public static func importDocument(_ doc: ExchangeDocument, into tx: TransactionContext, options: ExchangeImportOptions = .init(),
                                      minorNewer: Bool = false) -> ExchangeImportReport {
        let s = ExchangeImportSession(doc: doc, tx: tx, options: options)
        if minorNewer {
            s.warn("schema.newerMinor", "The file uses schema \(doc.schemaVersion ?? "?"), a newer minor version than this Arcus (\(ExchangeFormat.schemaVersion)). Information Arcus doesn't know about was ignored.")
        }
        s.run()
        return s.report
    }

    /// Converts the families in an exchange file (typically a family export) to Arcus family definitions without a
    /// project, e.g. to save them as `.arcusfamily`. Material values are not kept (they need a project).
    public static func familyDefinitions(data: Data, options: ExchangeImportOptions = .init()) throws(ExchangeImportError) -> [ExchangeFamilyResult] {
        let (doc, _) = try decode(data, options: options)
        let materialNames = Dictionary(doc.materials.items.compactMap { m in m.id.map { ($0, m.name ?? $0) } }, uniquingKeysWith: { a, _ in a })
        return doc.families.items.map { f in
            let c = ExchangeFamilyConverter.convert(f, materialName: { materialNames[$0] }, options: options)
            return ExchangeFamilyResult(definition: c.definition, warnings: c.warnings)
        }
    }

    static func parseVersion(_ s: String) -> (Int, Int)? {
        let parts = s.trimmingCharacters(in: .whitespaces).split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count), let major = Int(parts[0]), major >= 0 else { return nil }
        let minor = parts.count > 1 ? Int(parts[1]) : 0
        guard let minor, minor >= 0 else { return nil }
        return (major, minor)
    }

    static func describe(_ error: any Error) -> String {
        if let e = error as? DecodingError {
            switch e {
            case .dataCorrupted(let c): return c.underlyingError.map { "\($0.localizedDescription)" } ?? c.debugDescription
            case .keyNotFound(let k, _): return "missing “\(k.stringValue)”"
            case .typeMismatch(_, let c), .valueNotFound(_, let c): return c.debugDescription
            @unknown default: return "\(e)"
            }
        }
        return error.localizedDescription
    }
}
