import Foundation
import ArcusGeometry

// FM3: the Furniture document (Docs/FurnitureMode.md §3). A Furniture document is an ordinary Arcus project in a
// different mode: its project information says `.furniture`, it carries the piece's parameters, types and category,
// and its reference planes have formula offsets, so it flexes like a loadable family.

/// What a document is: an Architectural project or a Furniture piece.
public enum DocumentKind: String, Codable, Sendable, CaseIterable {
    case project, furniture

    /// The mode's name as the shell shows it.
    public var title: String {
        switch self {
        case .project: "Architectural"
        case .furniture: "Furniture"
        }
    }
}

/// What a material's `cost` is priced per.
public enum MaterialCostUnit: String, Codable, Sendable, CaseIterable {
    case sheet = "Sheet", squareFoot = "ft²", boardFoot = "Board Foot", linearFoot = "Linear Foot", each = "Each"
}

/// A Furniture document's parameters, types and category.
///
/// The piece is held as a family definition without geometry (`family`): its name, category (`template`, Furniture or
/// Casework), parameters with formulas and types with their values. That is exactly what Family Types and Category and
/// Parameters edit, and what `FurnitureCompiler` copies into the loadable family. Stored on the document's project
/// information (one per document, undoable like any other edit).
public struct FurnitureSetupData: Hashable, Codable, Sendable {
    public var family: FamilyDefinition
    /// The type whose values drive the planes (Family Types ▸ Type).
    public var currentType: String

    public init(family: FamilyDefinition, currentType: String? = nil) {
        self.family = family
        self.currentType = currentType ?? family.types.first?.name ?? ""
    }

    public var name: String { family.name }
    public var category: FamilyTemplate { family.template }
}

/// A reference plane's parametric definition in a Furniture document.
public struct FurniturePlaneData: Hashable, Codable, Sendable {
    /// The plane's normal: X planes run front to back (Left, Right), Y planes left to right (Front, Back), Z planes are
    /// horizontal (Bottom, Top).
    public var axis: FamilyAxis
    /// Offset from the origin along `axis`, as a formula of the parameters ("Width / 2"); nil keeps the drawn position.
    public var offsetFormula: String?
    public var strength: ReferenceStrength
    /// The origin planes (centres and Bottom) never move.
    public var definesOrigin: Bool

    public init(axis: FamilyAxis, offsetFormula: String? = nil, strength: ReferenceStrength = .weak, definesOrigin: Bool = false) {
        self.axis = axis; self.offsetFormula = offsetFormula; self.strength = strength; self.definesOrigin = definesOrigin
    }
}

/// Where a furniture part's end or face lies: on a named reference plane (plus an offset), or at a fixed value.
/// Mirrors `FamilyBound`; parts store these so they follow the planes when the parameters change.
public enum FurnitureBound: Hashable, Codable, Sendable {
    /// A reference plane by name, and an offset along its axis (meters, positive toward +axis).
    case plane(String, offset: Double)
    /// A fixed coordinate along the axis (meters).
    case value(Double)
}

/// Resolves `FurnitureBound`s against the document's reference planes.
public struct FurnitureBoundResolver: Sendable {
    /// Plane positions along their axes, by plane name.
    public let positions: [String: Double]
    public init(positions: [String: Double]) { self.positions = positions }
    public init(_ model: BIMModel) { positions = FurniturePlanes.positionsByName(model) }

    /// The coordinate of `bound`, or nil when its plane doesn't exist.
    public func resolve(_ bound: FurnitureBound) -> Double? {
        switch bound {
        case .plane(let n, let o): positions[n].map { $0 + o }
        case .value(let v): v
        }
    }

    /// The bound that keeps `value`: on the plane within `tolerance` of it (nearest), else a fixed value.
    public func bind(_ value: Double, axisPlanes names: [String], tolerance: Double = 0.001) -> FurnitureBound {
        let near = names.compactMap { n in positions[n].map { (n, $0) } }.min { abs($0.1 - value) < abs($1.1 - value) }
        if let (n, p) = near, abs(p - value) <= tolerance { return .plane(n, offset: 0) }
        return .value(value)
    }
}

// MARK: - Model accessors

extension ProjectInfoData {
    /// The document kind (projects when unset).
    public var kind: DocumentKind { documentKind ?? .project }
}

extension BIMModel {
    /// True for Furniture documents.
    public var isFurniture: Bool { projectInfo.kind == .furniture }
    /// The Furniture document's parameters and types (nil in projects).
    public var furnitureSetup: FurnitureSetupData? { isFurniture ? projectInfo.furniture : nil }
}

// MARK: - Plane geometry

/// Positions and extents of a Furniture document's parametric reference planes.
public enum FurniturePlanes {
    /// How far planes reach past the piece (meters, about 1 ft).
    public static let margin = 0.3048

    /// The model's furniture planes: model-wide reference planes with a furniture definition, sorted by id.
    public static func all(_ m: BIMModel) -> [Element] {
        m.elements(.referencePlanes).filter { $0.ownerViewID == nil && $0.referencePlane?.furniture != nil }.sorted { $0.id < $1.id }
    }

    /// The name a plane goes by in formulas, dimensions and the compiled family: its element name, or "Reference
    /// Plane <id>" when unnamed or when another plane has the same name.
    public static func names(_ m: BIMModel) -> [ElementID: String] {
        let planes = all(m)
        var count: [String: Int] = [:]
        for p in planes where !p.name.isEmpty { count[p.name, default: 0] += 1 }
        var out: [ElementID: String] = [:]
        for p in planes { out[p.id] = (!p.name.isEmpty && count[p.name] == 1) ? p.name : "Reference Plane \(p.id.raw)" }
        return out
    }

    /// Positions along their axes by plane name.
    public static func positionsByName(_ m: BIMModel) -> [String: Double] {
        let n = names(m)
        var out: [String: Double] = [:]
        for p in all(m) { if let name = n[p.id], let v = p.referencePlane.flatMap(position) { out[name] = v } }
        return out
    }

    /// A plane's position along its axis: x for X planes, y for Y planes, the elevation for Z planes.
    public static func position(_ rp: ReferencePlaneData) -> Double? {
        guard let f = rp.furniture else { return nil }
        switch f.axis {
        case .x: return (rp.line.start.x + rp.line.end.x) / 2
        case .y: return (rp.line.start.y + rp.line.end.y) / 2
        case .z: return rp.plane3D.map { ($0.start.z + $0.end.z) / 2 }
        }
    }

    /// The normal axis of a newly drawn plane, when it is parallel to one of the piece's axes.
    public static func axis(of rp: ReferencePlaneData) -> FamilyAxis? {
        if let p = rp.plane3D {
            let n = p.extrusion
            let horizontal = abs(p.start.z - p.end.z) < Tolerance.length && abs(n.z) < 1e-6
            return horizontal ? .z : nil
        }
        let d = rp.line.direction
        if abs(d.x) < 1e-6 { return .x }
        if abs(d.y) < 1e-6 { return .y }
        return nil
    }

    /// The plan box the planes span (x from X planes, y from Y planes), or a default around the origin.
    public static func extents(_ m: BIMModel, positions: [ElementID: Double]? = nil) -> (x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>) {
        var xs: [Double] = [], ys: [Double] = [], zs: [Double] = []
        for p in all(m) {
            guard let rp = p.referencePlane, let f = rp.furniture, let v = positions?[p.id] ?? position(rp) else { continue }
            switch f.axis { case .x: xs.append(v); case .y: ys.append(v); case .z: zs.append(v) }
        }
        func range(_ v: [Double], _ fallback: ClosedRange<Double>) -> ClosedRange<Double> {
            guard let lo = v.min(), let hi = v.max() else { return fallback }
            return (lo - margin)...(hi + margin)
        }
        return (range(xs, -0.6...0.6), range(ys, -0.45...0.45), range(zs, -0.15...0.9))
    }

    /// The plane moved to `value` along its axis, spanning `extents` on the other axes.
    public static func placed(_ rp: ReferencePlaneData, at value: Double, extents e: (x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>)) -> ReferencePlaneData {
        var r = rp
        guard let f = rp.furniture else { return rp }
        switch f.axis {
        case .x: r.line = Segment2(Vec2(value, e.y.lowerBound), Vec2(value, e.y.upperBound)); r.plane3D = nil
        case .y: r.line = Segment2(Vec2(e.x.lowerBound, value), Vec2(e.x.upperBound, value)); r.plane3D = nil
        case .z:
            r.line = Segment2(Vec2(e.x.lowerBound, e.y.lowerBound), Vec2(e.x.upperBound, e.y.lowerBound))
            r.plane3D = ReferencePlane3D(start: Vec3(e.x.lowerBound, e.y.lowerBound, value), end: Vec3(e.x.upperBound, e.y.lowerBound, value),
                                         extrusion: Vec3(0, 1, 0))
        }
        return r
    }

    /// A new parametric plane (for templates and the library).
    public static func make(axis: FamilyAxis, formula: String?, strength: ReferenceStrength, origin: Bool, at value: Double,
                            extents e: (x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>)) -> ReferencePlaneData {
        var rp = ReferencePlaneData(line: Segment2(.zero, Vec2(1, 0)))
        rp.furniture = FurniturePlaneData(axis: axis, offsetFormula: formula, strength: strength, definesOrigin: origin)
        return placed(rp, at: value, extents: e)
    }

    /// True for a horizontal (Z) furniture plane: shown in elevations and sections, not in plans.
    public static func isHorizontal(_ rp: ReferencePlaneData) -> Bool { rp.furniture?.axis == .z }
}
