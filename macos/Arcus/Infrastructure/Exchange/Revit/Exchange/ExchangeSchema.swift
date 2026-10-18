import Foundation

// Arcus Exchange (.arcusx) schema, version 1.0.
//
// An OPEN, documented JSON format written by the Arcus Bridge Revit add-in (Tools/RevitBridge) and read by
// `ArcusExchangeImporter`. The normative reference is Docs/RevitInterop.md ("Schema reference") together with
// Tools/RevitBridge/arcus-exchange.schema.json. Keep all three in sync.
//
// Conventions:
// - Lengths in meters, areas m², volumes m³, angles radians, slopes rise/run. Model coordinates are the source
//   application's internal coordinates (Z up), converted to meters.
// - Every object has an `id` unique within the file (references use it) and optionally `uniqueId`, the source
//   application's stable element identity (Revit UniqueId). Arcus derives element GlobalIds from `uniqueId`.
// - Enumerations are strings; unknown values fall back to a documented default and produce a warning.
// - Unknown keys are ignored. Every list is decoded item by item: a malformed item is skipped and reported.

public enum ExchangeFormat {
    /// Value of the top-level `format` key.
    public static let identifier = "arcus-exchange"
    /// Highest schema version this build reads fully.
    public static let schemaMajor = 1
    public static let schemaMinor = 0
    public static var schemaVersion: String { "\(schemaMajor).\(schemaMinor)" }
    public static let fileExtension = "arcusx"
}

// MARK: - Value types

/// A 2D curve in plan (x, y). Lines use `start`/`end`; arcs use `start`/`mid`/`end` (three points on the arc);
/// circles use `center`/`radius`. Roof footprint curves also carry `definesSlope`/`slopeAngle`/`overhang`.
public struct XCurve: Codable, Hashable, Sendable {
    public var type: String?
    public var start: [Double]?
    public var end: [Double]?
    public var mid: [Double]?
    public var center: [Double]?
    public var radius: Double?
    public var definesSlope: Bool?
    public var slopeAngle: Double?
    public var overhang: Double?

    public init(type: String, start: [Double]? = nil, end: [Double]? = nil, mid: [Double]? = nil, center: [Double]? = nil, radius: Double? = nil) {
        self.type = type; self.start = start; self.end = end; self.mid = mid; self.center = center; self.radius = radius
    }
    public static func line(_ a: [Double], _ b: [Double]) -> XCurve { XCurve(type: "line", start: a, end: b) }
    public static func arc(_ a: [Double], _ m: [Double], _ b: [Double]) -> XCurve { XCurve(type: "arc", start: a, end: b, mid: m) }
}

/// A scalar in family coordinates: a number (meters), an Arcus formula expression (constants need units, e.g.
/// `"-Width / 2 - 0.05 m"`), or a reference plane (`{"plane": "Left"}`).
public enum XScalar: Codable, Hashable, Sendable {
    case number(Double)
    case expr(String)
    case plane(String)

    private enum Keys: String, CodingKey { case plane, expr }
    public init(from decoder: any Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if let d = try? c.decode(Double.self) { self = .number(d); return }
            if let s = try? c.decode(String.self) {
                let t = s.trimmingCharacters(in: .whitespaces)
                if let d = Double(t) { self = .number(d) } else { self = .expr(t) }
                return
            }
        }
        let k = try decoder.container(keyedBy: Keys.self)
        if let p = try k.decodeIfPresent(String.self, forKey: .plane) { self = .plane(p); return }
        if let e = try k.decodeIfPresent(String.self, forKey: .expr) { self = .expr(e); return }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected a number, expression or {\"plane\": name}."))
    }
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .number(let d): var c = encoder.singleValueContainer(); try c.encode(d)
        case .expr(let s): var c = encoder.singleValueContainer(); try c.encode(s)
        case .plane(let p): var c = encoder.container(keyedBy: Keys.self); try c.encode(p, forKey: .plane)
        }
    }
}

/// A parameter value: number (SI units), boolean, text, a material reference `{"materialId": "…"}`, another element
/// reference `{"elementId": "…"}`, or null. Values of any other shape decode as `.unsupported` (never an error).
public enum XValue: Codable, Hashable, Sendable {
    case number(Double)
    case bool(Bool)
    case text(String)
    case material(String)
    case element(String)
    case null
    case unsupported

    private enum Keys: String, CodingKey { case materialId, elementId }
    public init(from decoder: any Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil() { self = .null; return }
            if let b = try? c.decode(Bool.self) { self = .bool(b); return }
            if let d = try? c.decode(Double.self) { self = .number(d); return }
            if let s = try? c.decode(String.self) { self = .text(s); return }
        }
        if let k = try? decoder.container(keyedBy: Keys.self) {
            if let m = try? k.decode(String.self, forKey: .materialId) { self = .material(m); return }
            if let e = try? k.decode(String.self, forKey: .elementId) { self = .element(e); return }
        }
        self = .unsupported
    }
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .number(let d): var c = encoder.singleValueContainer(); try c.encode(d)
        case .bool(let b): var c = encoder.singleValueContainer(); try c.encode(b)
        case .text(let s): var c = encoder.singleValueContainer(); try c.encode(s)
        case .material(let m): var c = encoder.container(keyedBy: Keys.self); try c.encode(m, forKey: .materialId)
        case .element(let e): var c = encoder.container(keyedBy: Keys.self); try c.encode(e, forKey: .elementId)
        case .null, .unsupported: var c = encoder.singleValueContainer(); try c.encodeNil()
        }
    }
}

/// Placement of a family instance: origin plus the family's X/Y/Z axes in model coordinates.
public struct XTransform: Codable, Hashable, Sendable {
    public var origin: [Double]?
    public var basisX: [Double]?
    public var basisY: [Double]?
    public var basisZ: [Double]?
    public init(origin: [Double], basisX: [Double], basisY: [Double], basisZ: [Double] = [0, 0, 1]) {
        self.origin = origin; self.basisX = basisX; self.basisY = basisY; self.basisZ = basisZ
    }
}

/// Triangle mesh: flat `positions` (x, y, z, x, y, z, …) and flat `indices` (three per triangle).
public struct XMesh: Codable, Hashable, Sendable {
    public var positions: [Double]?
    public var indices: [Int]?
    public init(positions: [Double], indices: [Int]) { self.positions = positions; self.indices = indices }
}

/// An array decoded item by item; malformed items are skipped and counted instead of failing the document.
public struct Lossy<T: Codable & Sendable>: Codable, Sendable {
    public var items: [T]
    public var failures: Int
    public init(_ items: [T] = []) { self.items = items; failures = 0 }
    private struct Skip: Decodable { init(from decoder: any Decoder) throws {} }
    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        items = []
        failures = 0
        while !c.isAtEnd {
            if let v = try? c.decode(T.self) { items.append(v); continue }
            failures += 1
            if (try? c.decode(Skip.self)) == nil { break }
        }
    }
    public func encode(to encoder: any Encoder) throws { try items.encode(to: encoder) }
}

// MARK: - Document

public struct XGenerator: Codable, Hashable, Sendable {
    public var name: String?
    public var version: String?
    /// Host application, e.g. "Autodesk Revit 2025".
    public var host: String?
    public var exportedAt: String?
    public init(name: String? = nil, version: String? = nil, host: String? = nil, exportedAt: String? = nil) {
        self.name = name; self.version = version; self.host = host; self.exportedAt = exportedAt
    }
}

public struct XSource: Codable, Hashable, Sendable {
    public var fileName: String?
    public var path: String?
    /// Stable identity of the source document (Revit: the ProjectInformation UniqueId or the document's
    /// creation GUID); used to derive identities of objects without `uniqueId`.
    public var documentId: String?
    public var application: String?
    public init(fileName: String? = nil, documentId: String? = nil) { self.fileName = fileName; self.documentId = documentId }
}

public struct XUnits: Codable, Hashable, Sendable {
    /// "metric" or "imperial" (display preference only; values are always SI).
    public var system: String?
    /// Arcus length display name, e.g. "Millimeters" (optional).
    public var length: String?
}

public struct XProjectInfo: Codable, Hashable, Sendable {
    public var name: String?
    public var number: String?
    public var clientName: String?
    public var address: String?
    public var status: String?
    public var issueDate: String?
    public var author: String?
    public var organization: String?
    public var buildingName: String?
    public var siteName: String?
    /// Degrees.
    public var latitude: Double?
    public var longitude: Double?
    public var elevation: Double?
    /// Angle from project north to true north, radians, counter-clockwise positive.
    public var trueNorthAngle: Double?
    public var projectBasePoint: [Double]?
    public var surveyPoint: [Double]?
}

public struct XMaterial: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var name: String?
    /// Arcus material class name (Generic, Concrete, Masonry, Metal, Wood, Glass, …) or the source class.
    public var materialClass: String?
    /// "#RRGGBB".
    public var color: String?
    /// 0 (opaque) … 1 (fully transparent).
    public var transparency: Double?
    public var description: String?
    public var manufacturer: String?
    public var model: String?
    public var mark: String?
    public var keynote: String?
    public var cost: Double?
}

public struct XLevel: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var name: String?
    public var elevation: Double?
    public var isBuildingStorey: Bool?
    public var isStructural: Bool?
}

public struct XGrid: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var name: String?
    public var curve: XCurve?
    public var bottomElevation: Double?
    public var topElevation: Double?
}

public struct XLayer: Codable, Hashable, Sendable {
    /// structure | substrate | thermal | membrane | finish1 | finish2 (| structuralDeck → structure)
    public var function: String?
    public var materialId: String?
    public var thickness: Double?
    public var wraps: Bool?
    public var isVariable: Bool?
    public var isCore: Bool?
}

public struct XSection: Codable, Hashable, Sendable {
    /// "rectangle" or "circle".
    public var shape: String?
    public var width: Double?
    public var depth: Double?
    public var diameter: Double?
}

public struct XStairTypeInfo: Codable, Hashable, Sendable {
    public var maxRiserHeight: Double?
    public var minTreadDepth: Double?
    public var treadThickness: Double?
    public var waist: Double?
}

public struct XRailingTypeInfo: Codable, Hashable, Sendable {
    public var height: Double?
    public var balusterSpacing: Double?
    public var balusterSize: Double?
    public var railSize: Double?
}

/// A system (non-loadable) type: walls, floors, ceilings, roofs, and the section types used for columns, beams,
/// stairs and railings.
public struct XType: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var name: String?
    public var familyName: String?
    /// walls | floors | ceilings | roofs | buildingPads | columns | structuralColumns | structuralFraming | stairs | railings
    public var category: String?
    /// Walls: "basic" | "curtain" | "stacked". Only basic walls map to native Arcus walls.
    public var kind: String?
    /// Layers exterior → interior (walls) or top → bottom (floors, roofs, ceilings).
    public var layers: [XLayer]?
    /// Index of the first core layer and one past the last core layer.
    public var coreStart: Int?
    public var coreEnd: Int?
    /// "doNotWrap" | "exterior" | "interior" | "both"
    public var wrappingAtInserts: String?
    public var wrappingAtEnds: String?
    /// Total thickness, used when no layers are given.
    public var thickness: Double?
    /// Wall function: "Exterior", "Interior", "Foundation", "Retaining", "Soffit", "Core-shaft".
    public var function: String?
    public var typeMark: String?
    public var description: String?
    public var fireRating: String?
    public var materialId: String?
    public var section: XSection?
    public var stair: XStairTypeInfo?
    public var railing: XRailingTypeInfo?
    public var parameters: [String: XValue]?
}

// MARK: - Families

public struct XFamilyParameter: Codable, Hashable, Sendable {
    public var name: String?
    /// length | area | volume | angle | slope | number | integer | percentage | currency | text | multilineText |
    /// yesNo | url | material | (anything else is skipped with a warning)
    public var dataType: String?
    public var isInstance: Bool?
    /// constraints | construction | graphics | materials | dimensions | structural | identity | phasing | text | ifc | other
    public var group: String?
    /// Formula in Arcus formula syntax (which accepts common Revit formulas).
    public var formula: String?
    public var isBuiltIn: Bool?
    public var isShared: Bool?
    public var isReporting: Bool?
    /// Canonical meaning of a built-in parameter whose display name is localized: "width" | "height".
    public var builtIn: String?
}

public struct XFamilyType: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var name: String?
    /// Values by parameter name (SI units). Material parameters use {"materialId": "…"}.
    public var values: [String: XValue]?
    public var typeMark: String?
    public var description: String?
    public var fireRating: String?
}

public struct XReferencePlane: Codable, Hashable, Sendable {
    public var name: String?
    /// Axis of the plane's normal: "x" | "y" | "z".
    public var axis: String?
    public var offset: XScalar?
    /// notAReference | weak | strong | left | centerLeftRight | right | front | centerFrontBack | back | bottom | centerElevation | top
    public var strength: String?
    public var definesOrigin: Bool?
}

public struct XFamilyDimension: Codable, Hashable, Sendable {
    public var planeA: String?
    public var planeB: String?
    public var label: String?
}

/// A curve of a family profile or symbolic line; coordinates are scalars in the two axes of the profile plane.
/// Lines: `start`/`end`. Arcs: `start`/`mid`/`end`, optionally with parametric `center`/`radius`. Circles: `center`/`radius`.
public struct XProfileCurve: Codable, Hashable, Sendable {
    public var type: String?
    public var start: [XScalar]?
    public var end: [XScalar]?
    public var mid: [XScalar]?
    public var center: [XScalar]?
    public var radius: XScalar?
    public init(type: String, start: [XScalar]? = nil, end: [XScalar]? = nil, mid: [XScalar]? = nil, center: [XScalar]? = nil, radius: XScalar? = nil) {
        self.type = type; self.start = start; self.end = end; self.mid = mid; self.center = center; self.radius = radius
    }
}

/// Family geometry. `extrusion`: closed `loops` in the plane normal to `extrusionAxis` ("z": x/y profile,
/// "y": x/z profile, "x": y/z profile), extruded between the two `extent` values along that axis.
/// `mesh`: tessellated geometry in family coordinates (blends, revolves, sweeps, nested families, non-axis-aligned
/// extrusions) that Arcus approximates.
public struct XFamilyGeometry: Codable, Hashable, Sendable {
    public var kind: String?
    public var name: String?
    public var isVoid: Bool?
    public var extrusionAxis: String?
    public var extent: [XScalar]?
    public var loops: [[XProfileCurve]]?
    public var positions: [Double]?
    public var indices: [Int]?
    public var materialParameter: String?
    public var materialId: String?
    /// General | Frame/Mullion | Panel | Glass | Opening | Plan Swing | Elevation Swing | Hidden Lines | Sill/Head
    public var subcategory: String?
    public var visibilityParameter: String?
    /// Subset of "coarse", "medium", "fine".
    public var visibleAt: [String]?
    public var visibleInPlan: Bool?
    /// Source form kind, informational: extrusion | blend | revolution | sweep | sweptBlend | nestedFamily | freeForm
    public var sourceKind: String?
}

public struct XFamilyLine: Codable, Hashable, Sendable {
    public var curve: XProfileCurve?
    public var subcategory: String?
    public var visibleAt: [String]?
}

public struct XOpening: Codable, Hashable, Sendable {
    public var xMin: XScalar?
    public var xMax: XScalar?
    public var zMin: XScalar?
    public var zMax: XScalar?
}

/// A loadable family. Family coordinates: origin at the insertion point, X along the host (width), Y toward the
/// facing/exterior side, Z up. In a project export, `types` hold the project's current type values.
public struct XFamily: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var name: String?
    /// Arcus category key (doors, windows, furniture, casework, genericModels, columns, structuralColumns,
    /// structuralFraming, plumbingFixtures, specialtyEquipment) or another value (mapped to Generic Models).
    public var category: String?
    public var revitCategory: String?
    public var description: String?
    public var manufacturer: String?
    /// "wall" for wall-hosted families, "none" otherwise.
    public var hostKind: String?
    /// False when only parameters and types were exported (no geometry).
    public var definitionIncluded: Bool?
    public var parameters: [XFamilyParameter]?
    public var types: [XFamilyType]?
    public var referencePlanes: [XReferencePlane]?
    public var dimensions: [XFamilyDimension]?
    public var geometry: [XFamilyGeometry]?
    public var planLines: [XFamilyLine]?
    public var opening: XOpening?
}

// MARK: - Instances

public struct XWall: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var typeId: String?
    public var levelId: String?
    /// Location line curve in plan.
    public var curve: XCurve?
    /// wallCenterline | coreCenterline | finishFaceExterior | finishFaceInterior | coreFaceExterior | coreFaceInterior
    public var locationLine: String?
    public var baseOffset: Double?
    public var topLevelId: String?
    public var topOffset: Double?
    public var unconnectedHeight: Double?
    /// True when the exterior side is to the RIGHT of the curve direction.
    public var flipped: Bool?
    public var structural: Bool?
    public var roomBounding: Bool?
    public var joinAtStart: Bool?
    public var joinAtEnd: Bool?
    public var mark: String?
    public var comments: String?
    public var parameters: [String: XValue]?
    /// Fallback geometry for walls Arcus cannot represent natively (curtain, stacked, profiled).
    public var mesh: XMesh?
}

public struct XSlopeArrow: Codable, Hashable, Sendable {
    public var tail: [Double]?
    public var head: [Double]?
    public var tailOffset: Double?
    /// Rise/run.
    public var slope: Double?
}

/// Floors, ceilings and building pads.
public struct XSlab: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var typeId: String?
    public var levelId: String?
    /// Closed boundary loops; the largest is the outer boundary, loops inside it are openings.
    public var boundary: [[XCurve]]?
    /// Floors: top surface offset from the level. Ceilings: bottom surface offset.
    public var offset: Double?
    public var slopeArrow: XSlopeArrow?
    public var structural: Bool?
    public var roomBounding: Bool?
    public var mark: String?
    public var comments: String?
    public var parameters: [String: XValue]?
    public var mesh: XMesh?
}

public struct XRoof: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var typeId: String?
    public var levelId: String?
    /// "footprint" (native) or another kind ("extrusion", …) imported from `mesh`.
    public var kind: String?
    /// Eave loop(s); curves carry `definesSlope`, `slopeAngle` (radians) and `overhang`.
    public var footprint: [[XCurve]]?
    public var baseOffset: Double?
    public var overhang: Double?
    public var mark: String?
    public var comments: String?
    public var parameters: [String: XValue]?
    public var mesh: XMesh?
}

/// Doors and windows hosted by walls.
public struct XInsert: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    /// "doors" | "windows"
    public var category: String?
    /// Id of a family type (`families[].types[].id`).
    public var typeId: String?
    public var hostId: String?
    public var levelId: String?
    /// Insertion point [x, y, z] in model coordinates (z = bottom of the opening).
    public var location: [Double]?
    /// Sill height above the insert's level (used when `location` has no z).
    public var sillHeight: Double?
    /// Preferred: the instance transform. Flips are derived from it.
    public var transform: XTransform?
    /// Arcus convention: facing flipped = family +Y points to the host's interior side.
    public var facingFlipped: Bool?
    /// Arcus convention: hand flipped = family +X runs against the host's location curve.
    public var handFlipped: Bool?
    public var mark: String?
    public var comments: String?
    public var parameters: [String: XValue]?
    public var mesh: XMesh?
}

public struct XRoom: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var name: String?
    public var number: String?
    public var levelId: String?
    public var point: [Double]?
    public var upperLimitLevelId: String?
    public var limitOffset: Double?
    public var baseOffset: Double?
    public var department: String?
    public var comments: String?
    public var parameters: [String: XValue]?
}

public struct XColumn: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    /// "columns" | "structuralColumns"
    public var category: String?
    public var typeId: String?
    public var levelId: String?
    public var location: [Double]?
    public var rotation: Double?
    public var transform: XTransform?
    public var baseOffset: Double?
    public var topLevelId: String?
    public var topOffset: Double?
    public var unconnectedHeight: Double?
    public var slanted: Bool?
    public var mark: String?
    public var comments: String?
    public var mesh: XMesh?
}

public struct XBeam: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var typeId: String?
    public var levelId: String?
    public var curve: XCurve?
    /// Offsets of the beam's reference line ends above the level.
    public var startOffset: Double?
    public var endOffset: Double?
    /// "top" | "center" | "bottom"
    public var zJustification: String?
    public var mark: String?
    public var comments: String?
    public var mesh: XMesh?
}

public struct XStair: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var typeId: String?
    public var levelId: String?
    /// "straight" | "lShaped" | "uShaped" | anything else (imported from `mesh`).
    public var shape: String?
    /// Start of the first run at the bottom riser, on the run centerline.
    public var origin: [Double]?
    /// Direction of travel of the first run (radians).
    public var direction: Double?
    public var width: Double?
    public var baseOffset: Double?
    public var topLevelId: String?
    public var topOffset: Double?
    public var unconnectedHeight: Double?
    public var riserCount: Int?
    public var turnsLeft: Bool?
    public var firstRunRisers: Int?
    public var riserHeight: Double?
    public var treadDepth: Double?
    public var mark: String?
    public var comments: String?
    public var mesh: XMesh?
}

public struct XRailing: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var typeId: String?
    public var levelId: String?
    /// Stair id when the railing is hosted on a stair.
    public var hostId: String?
    public var path: [XCurve]?
    public var baseOffset: Double?
    public var mark: String?
    public var comments: String?
    public var mesh: XMesh?
}

/// A free-standing loadable family instance (furniture, casework, generic models, fixtures…).
public struct XComponent: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var category: String?
    public var revitCategory: String?
    public var typeId: String?
    public var levelId: String?
    public var transform: XTransform?
    /// Used when `transform` is absent: [x, y, z], rotation (radians), mirrored.
    public var location: [Double]?
    public var rotation: Double?
    public var mirrored: Bool?
    public var hostId: String?
    public var mark: String?
    public var comments: String?
    public var parameters: [String: XValue]?
    public var mesh: XMesh?
}

/// Reference geometry for anything without a native Arcus equivalent. Imported read-only and labelled with its
/// source category.
public struct XMeshElement: Codable, Hashable, Sendable {
    public var id: String?
    public var uniqueId: String?
    public var category: String?
    public var revitCategory: String?
    public var name: String?
    public var levelId: String?
    public var positions: [Double]?
    public var indices: [Int]?
    public var materialId: String?
    /// Why the element was exported as a mesh, e.g. "curtain wall", "in-place family".
    public var reason: String?
    public var parameters: [String: XValue]?
}

/// Top-level Arcus Exchange document.
public struct ExchangeDocument: Codable, Sendable {
    public var format: String?
    public var schemaVersion: String?
    public var generator: XGenerator?
    /// "project" | "family"
    public var documentKind: String?
    public var source: XSource?
    public var units: XUnits?
    public var projectInfo: XProjectInfo?
    public var materials: Lossy<XMaterial>
    public var levels: Lossy<XLevel>
    public var grids: Lossy<XGrid>
    public var types: Lossy<XType>
    public var families: Lossy<XFamily>
    public var walls: Lossy<XWall>
    public var floors: Lossy<XSlab>
    public var ceilings: Lossy<XSlab>
    public var roofs: Lossy<XRoof>
    public var inserts: Lossy<XInsert>
    public var rooms: Lossy<XRoom>
    public var columns: Lossy<XColumn>
    public var beams: Lossy<XBeam>
    public var stairs: Lossy<XStair>
    public var railings: Lossy<XRailing>
    public var components: Lossy<XComponent>
    public var meshes: Lossy<XMeshElement>
    /// Top-level keys that were present but not lists/objects of the expected shape.
    public var malformedSections: [String] = []

    enum CodingKeys: String, CodingKey {
        case format, schemaVersion, generator, documentKind, source, units, projectInfo, materials, levels, grids, types, families
        case walls, floors, ceilings, roofs, inserts, rooms, columns, beams, stairs, railings, components, meshes
    }

    public init(documentKind: String = "project") {
        format = ExchangeFormat.identifier; schemaVersion = ExchangeFormat.schemaVersion; self.documentKind = documentKind
        materials = Lossy(); levels = Lossy(); grids = Lossy(); types = Lossy(); families = Lossy(); walls = Lossy()
        floors = Lossy(); ceilings = Lossy(); roofs = Lossy(); inserts = Lossy(); rooms = Lossy(); columns = Lossy()
        beams = Lossy(); stairs = Lossy(); railings = Lossy(); components = Lossy(); meshes = Lossy()
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var bad: [String] = []
        func one<T: Decodable>(_ k: CodingKeys) -> T? {
            guard c.contains(k) else { return nil }
            if let v = try? c.decodeIfPresent(T.self, forKey: k) { return v }
            bad.append(k.stringValue)
            return nil
        }
        func list<T: Codable & Sendable>(_ k: CodingKeys) -> Lossy<T> {
            guard c.contains(k) else { return Lossy() }
            if (try? c.decodeNil(forKey: k)) == true { return Lossy() }
            if let v = try? c.decode(Lossy<T>.self, forKey: k) { return v }
            bad.append(k.stringValue)
            return Lossy()
        }
        format = one(.format); schemaVersion = one(.schemaVersion); generator = one(.generator); documentKind = one(.documentKind)
        source = one(.source); units = one(.units); projectInfo = one(.projectInfo)
        materials = list(.materials); levels = list(.levels); grids = list(.grids); types = list(.types); families = list(.families)
        walls = list(.walls); floors = list(.floors); ceilings = list(.ceilings); roofs = list(.roofs); inserts = list(.inserts)
        rooms = list(.rooms); columns = list(.columns); beams = list(.beams); stairs = list(.stairs); railings = list(.railings)
        components = list(.components); meshes = list(.meshes)
        malformedSections = bad
    }

    /// Total number of listed objects (used for size limits).
    public var objectCount: Int {
        materials.items.count + levels.items.count + grids.items.count + types.items.count + families.items.count
            + walls.items.count + floors.items.count + ceilings.items.count + roofs.items.count + inserts.items.count
            + rooms.items.count + columns.items.count + beams.items.count + stairs.items.count + railings.items.count
            + components.items.count + meshes.items.count
    }

    /// Items that failed to decode, by section name.
    public var decodeFailures: [String: Int] {
        var out: [String: Int] = [:]
        func add(_ n: String, _ f: Int) { if f > 0 { out[n] = f } }
        add("materials", materials.failures); add("levels", levels.failures); add("grids", grids.failures); add("types", types.failures)
        add("families", families.failures); add("walls", walls.failures); add("floors", floors.failures); add("ceilings", ceilings.failures)
        add("roofs", roofs.failures); add("inserts", inserts.failures); add("rooms", rooms.failures); add("columns", columns.failures)
        add("beams", beams.failures); add("stairs", stairs.failures); add("railings", railings.failures)
        add("components", components.failures); add("meshes", meshes.failures)
        return out
    }
}
