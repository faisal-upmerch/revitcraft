import Foundation
import ArcusDomain

/// IFC schema written by the exporter. Raw values are the `FILE_SCHEMA` identifiers.
public enum IFCSchema: String, Sendable, CaseIterable {
    case ifc2x3 = "IFC2X3"
    case ifc4 = "IFC4"

    /// Model view definition written into `FILE_DESCRIPTION`.
    public var viewDefinition: String {
        switch self {
        case .ifc2x3: "CoordinationView_V2.0"
        case .ifc4: "ReferenceView_V1.2"
        }
    }
}

/// Which point of the model becomes the IFC world origin.
public enum IFCCoordinateBase: String, Sendable, CaseIterable {
    /// Arcus internal coordinates are written unchanged.
    case internalOrigin
    /// Coordinates are written relative to the project base point.
    case projectBasePoint
    /// Coordinates are written relative to the survey point; IFC4 adds IfcMapConversion + IfcProjectedCRS.
    case sharedCoordinates
}

public struct IFCExportOptions: Sendable {
    public var schema: IFCSchema = .ifc4
    /// Export only elements visible in this view (`VisibilityResolver`).
    public var visibleInViewID: ElementID? = nil
    /// One file per building storey, each with the project/site/building context.
    public var splitByStorey = false
    public var includeBaseQuantities = true
    public var includePropertySets = true
    public var includeClassification = true
    public var coordinateBase: IFCCoordinateBase = .projectBasePoint
    /// nil = latest phase. Elements created after the phase or demolished by then are skipped.
    public var phaseID: ElementID? = nil
    public var authorName = ""
    public var organization = ""
    public var applicationVersion = "1.0"
    public var fileName = "Project.ifc"
    /// Timestamp written to FILE_NAME and IfcOwnerHistory. nil = now. Tests inject a fixed date.
    public var timeStamp: Date? = nil
    public init() {}
}

public struct IFCExportReport: Sendable {
    public var files: [String]
    /// Number of written entity instances per IFC class (e.g. "IfcWall": 4), summed over all files.
    public var entityCounts: [String: Int]
    /// Number of model elements written as IFC products (counted once even when split by storey).
    public var exportedElements: Int
    public var skipped: [(ElementID, String)]
    public var warnings: [String]
    public var elapsed: TimeInterval
    public init(files: [String] = [], entityCounts: [String: Int] = [:], exportedElements: Int = 0, skipped: [(ElementID, String)] = [],
                warnings: [String] = [], elapsed: TimeInterval = 0) {
        self.files = files; self.entityCounts = entityCounts; self.exportedElements = exportedElements
        self.skipped = skipped; self.warnings = warnings; self.elapsed = elapsed
    }
}

public struct IFCImportOptions: Sendable {
    /// Convert recognisable IFC elements into native Arcus elements (walls, floors, rooms, doors, windows, columns, beams).
    public var mapToNative = true
    /// Storeys within this distance (meters) of an existing level reuse that level.
    public var targetLevelMatchTolerance = 0.05
    /// Parser limits (defaults are sized for real projects; lower them for untrusted batch processing).
    public var limits = STEPParser.Limits()
    public init() {}
}

public struct IFCImportReport: Sendable {
    public var schema: String
    public var fileName: String
    /// Total entity instances in the DATA section.
    public var entityCount: Int
    /// Native Arcus elements created, keyed by category (e.g. "walls": 4, "levels": 1, "elementTypes": 2).
    public var nativeCounts: [String: Int]
    /// Reference (immutable) elements created, keyed by IFC class.
    public var referenceCounts: [String: Int]
    /// Entities that could not be interpreted (unsupported geometry, unknown products), keyed by IFC class.
    public var unsupported: [String: Int]
    public var warnings: [String]
    public var elapsed: TimeInterval
    public init(schema: String = "", fileName: String = "", entityCount: Int = 0, nativeCounts: [String: Int] = [:], referenceCounts: [String: Int] = [:],
                unsupported: [String: Int] = [:], warnings: [String] = [], elapsed: TimeInterval = 0) {
        self.schema = schema; self.fileName = fileName; self.entityCount = entityCount; self.nativeCounts = nativeCounts
        self.referenceCounts = referenceCounts; self.unsupported = unsupported; self.warnings = warnings; self.elapsed = elapsed
    }
}

/// Error raised for malformed, truncated, hostile or unsupported IFC input, and for cancellation.
public struct IFCError: Error, Sendable, CustomStringConvertible {
    public var message: String
    /// 1-based line number in the STEP file, when known.
    public var line: Int?
    public init(_ message: String, line: Int? = nil) { self.message = message; self.line = line }
    public var description: String { line.map { "Line \($0): \(message)" } ?? message }

    static let cancelled = IFCError("The operation was cancelled.")
}
