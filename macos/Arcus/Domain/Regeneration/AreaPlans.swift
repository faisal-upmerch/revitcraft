import Foundation
import ArcusGeometry

/// Where automatic area boundary lines sit on exterior walls.
public enum AreaBoundaryRule: String, Codable, Sendable, CaseIterable {
    /// Gross building area: the exterior face of exterior walls.
    case gross
    /// Rentable area: the interior face of exterior walls.
    case rentable

    public var displayName: String {
        switch self {
        case .gross: "Gross (exterior face of exterior walls)"
        case .rentable: "Rentable (interior face of exterior walls)"
        }
    }
}

/// Area schemes, area plans and their automatic boundary lines.
public enum AreaPlans {
    /// Parameter on area boundary lines naming their area scheme (a reference value).
    public static let schemeParameter = ParameterID("areaScheme")

    public static let grossName = "Gross Building"
    public static let rentableName = "Rentable"

    /// Ensures the standard schemes (Gross Building, Rentable) exist and returns every area scheme, standard ones first.
    @discardableResult
    public static func ensureDefaultSchemes(in tx: TransactionContext) -> [ElementID] {
        let existing = tx.model.elements(.areaSchemes)
        if !existing.contains(where: { $0.name == grossName }) {
            tx.create(.areaSchemes, name: grossName, data: .areaScheme(AreaSchemeData(description: "Total constructed area of the building", boundaryRule: .gross)))
        }
        if !existing.contains(where: { $0.name == rentableName }) {
            tx.create(.areaSchemes, name: rentableName, data: .areaScheme(AreaSchemeData(description: "Area measured to the interior face of exterior walls", boundaryRule: .rentable)))
        }
        return sortedSchemes(tx.model).map(\.id)
    }

    /// Area schemes with the standard ones first, then by name.
    public static func sortedSchemes(_ model: BIMModel) -> [Element] {
        func rank(_ e: Element) -> Int { e.name == grossName ? 0 : e.name == rentableName ? 1 : 2 }
        return model.elements(.areaSchemes).sorted { (rank($0), $0.name) < (rank($1), $1.name) }
    }

    /// Room-bounding walls cut at the level's computation height, as profiles.
    static func wallFootprints(level: ElementID, _ model: BIMModel) -> [(ElementID, Polygon2)] {
        let z = RoomGeometry.computationZ(level: level, model)
        var out: [(ElementID, Polygon2)] = []
        for w in model.elements(.walls) where w.wall?.roomBounding == true && w.phaseDemolished == nil {
            guard let f = WallGeometry.frame(w, model), f.baseZ <= z + Tolerance.length, f.topZ >= z - Tolerance.length,
                  let fp = WallGeometry.footprint(w, model), !fp.isDegenerate else { continue }
            out.append((w.id, fp))
        }
        return out
    }

    /// Automatic boundary loops on a level: the outline of each building footprint at the exterior face of its
    /// exterior walls (gross), or at their interior face (rentable). Exterior walls are those on the outer outline.
    public static func automaticBoundary(level: ElementID, rule: AreaBoundaryRule, _ model: BIMModel) -> [Polygon2] {
        let walls = wallFootprints(level: level, model)
        guard !walls.isEmpty else { return [] }
        let union = PolygonBoolean.union(walls.map { Profile2(outer: $0.1) })
        let outers = union.map(\.outer)
        switch rule {
        case .gross:
            return outers
        case .rentable:
            let outerEdges = outers.flatMap(\.edges)
            let tol = 1e-3
            let exterior = walls.filter { _, fp in
                fp.edges.contains { e in
                    let m = e.midpoint
                    return e.length > tol && outerEdges.contains { $0.distance(to: m) <= tol && abs($0.direction.cross(e.direction)) < 1e-3 }
                }
            }
            let inside = PolygonBoolean.difference(outers.map { Profile2(outer: $0) }, exterior.map { Profile2(outer: $0.1) })
            return inside.map(\.outer).filter { $0.area > 0.5 }
        }
    }

    /// Creates area boundary lines for a scheme on a level from its exterior walls. Existing lines of the scheme on
    /// the level that coincide with a new line are kept instead of duplicated. Returns the number of lines created.
    @discardableResult
    public static func createAutomaticBoundary(level: ElementID, scheme: ElementID, in tx: TransactionContext) -> Int {
        let rule = tx.model[scheme]?.areaScheme?.rule ?? .gross
        let loops = automaticBoundary(level: level, rule: rule, tx.model)
        let existing = tx.model.elements(.areaBoundaryLines).filter { $0.levelID == level && $0.params[schemeParameter]?.refValue == scheme }
            .compactMap { $0.modelLine?.curve.asSegment }
        var count = 0
        for loop in loops {
            for e in loop.counterClockwise.edges where e.length > Tolerance.shortCurve {
                if existing.contains(where: { ($0.start.isAlmostEqual(e.start) && $0.end.isAlmostEqual(e.end)) || ($0.start.isAlmostEqual(e.end) && $0.end.isAlmostEqual(e.start)) }) { continue }
                tx.create(.areaBoundaryLines, data: .modelLine(ModelLineData(curve: .line(e))), levelID: level) { el in
                    el.params[schemeParameter] = .ref(scheme)
                }
                count += 1
            }
        }
        return count
    }

    /// Creates an area plan of a scheme for a level (named after the level), optionally with automatic boundary lines.
    @discardableResult
    public static func createAreaPlan(level: ElementID, scheme: ElementID, scale: Int = 100, automaticBoundary: Bool, in tx: TransactionContext) -> ElementID {
        var v = ViewData(kind: .areaPlan, scale: scale)
        v.phaseID = tx.model.latestPhase?.id
        v.areaSchemeID = scheme
        let schemeName = tx.model[scheme]?.name ?? "Area"
        let levelName = tx.model[level]?.name ?? "Level"
        var name = "\(levelName) (\(schemeName))"
        var k = 2
        while tx.model.views.contains(where: { $0.name == name && $0.view?.kind == .areaPlan }) { name = "\(levelName) (\(schemeName)) \(k)"; k += 1 }
        let id = tx.create(.views, name: name, data: .view(v), levelID: level)
        if automaticBoundary { createAutomaticBoundary(level: level, scheme: scheme, in: tx) }
        return id
    }
}
