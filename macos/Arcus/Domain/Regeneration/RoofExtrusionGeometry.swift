import Foundation
import ArcusGeometry

/// Problems with an extruded roof's profile.
public enum RoofProfileError: Error, Hashable, Sendable, CustomStringConvertible {
    case empty, closed, disconnected, selfIntersecting, noDepth
    public var description: String {
        switch self {
        case .empty: "Sketch the roof profile with at least one line or arc."
        case .closed: "A roof by extrusion needs an open profile. Delete one line so the profile has two free ends."
        case .disconnected: "The profile lines must connect end to end in a single chain."
        case .selfIntersecting: "The roof profile crosses itself."
        case .noDepth: "Extrusion Start and End must differ."
        }
    }
}

/// Geometry of roofs by extrusion (see `RoofExtrusion`).
public enum RoofExtrusionGeometry {
    static let tolerance = Tolerance.length * 10

    /// Orders curves into one open chain running from its left end (smaller station) to its right end.
    public static func orderedChain(_ curves: [Curve2]) -> Result<[Curve2], RoofProfileError> {
        let cs = curves.filter { $0.length > Tolerance.shortCurve }
        guard !cs.isEmpty else { return .failure(.empty) }
        func degree(_ p: Vec2) -> Int {
            cs.reduce(0) { $0 + ($1.start.isAlmostEqual(p, tolerance: tolerance) ? 1 : 0) + ($1.end.isAlmostEqual(p, tolerance: tolerance) ? 1 : 0) }
        }
        let ends = cs.flatMap { [$0.start, $0.end] }
        if ends.contains(where: { degree($0) > 2 }) { return .failure(.disconnected) }
        guard let free = ends.first(where: { degree($0) == 1 }) else {
            return .failure(Sketch.orderLoop(cs) != nil ? .closed : .disconnected)
        }
        var remaining = cs
        var chain: [Curve2] = []
        var at = free
        while let i = remaining.firstIndex(where: { $0.start.isAlmostEqual(at, tolerance: tolerance) || $0.end.isAlmostEqual(at, tolerance: tolerance) }) {
            let c = remaining.remove(at: i)
            let oriented = c.start.isAlmostEqual(at, tolerance: tolerance) ? c : c.reversed
            chain.append(oriented)
            at = oriented.end
        }
        guard remaining.isEmpty else { return .failure(.disconnected) }
        if chain[0].start.x > chain[chain.count - 1].end.x { chain = chain.reversed().map(\.reversed) }
        let pts = polyline(chain)
        for i in 0..<(pts.count - 1) {
            for j in (i + 2)..<max(i + 2, pts.count - 1) {
                if Segment2(pts[i], pts[i + 1]).intersection(Segment2(pts[j], pts[j + 1])) != nil { return .failure(.selfIntersecting) }
            }
        }
        return .success(chain)
    }

    public static func validate(_ x: RoofExtrusion) -> RoofProfileError? {
        if case .failure(let e) = orderedChain(x.profile) { return e }
        if abs(x.end - x.start) < 0.01 { return .noDepth }
        return nil
    }

    static func polyline(_ chain: [Curve2]) -> [Vec2] {
        var pts: [Vec2] = []
        for c in chain {
            for p in c.tessellate(chordTolerance: 0.01) where pts.last.map({ !$0.isAlmostEqual(p) }) ?? true { pts.append(p) }
        }
        return pts
    }

    /// Top line of the profile (left to right) in work-plane coordinates.
    public static func topLine(_ x: RoofExtrusion) -> [Vec2]? {
        guard case .success(let chain) = orderedChain(x.profile) else { return nil }
        let pts = polyline(chain)
        return pts.count >= 2 ? pts : nil
    }

    /// Underside line: the top line offset by the roof thickness, perpendicular to the profile. Falls back to a
    /// vertical drop where a tight curve would make the perpendicular offset fold over.
    static func underside(_ top: [Vec2], thickness t: Double) -> [Vec2] {
        let off = PolylineOffset.offset(top, by: -t)
        if off.count >= 2, Polygon2(top + off.reversed()).isSimple { return off }
        return top.map { Vec2($0.x, $0.y - t) }
    }

    /// Closed cross-section of the roof in work-plane coordinates.
    public static func section(_ x: RoofExtrusion, thickness t: Double) -> Polygon2? {
        guard let top = topLine(x) else { return nil }
        let poly = Polygon2(top + underside(top, thickness: t).reversed())
        return poly.isDegenerate ? nil : poly.counterClockwise
    }

    public static func baseZ(_ e: Element, _ model: BIMModel) -> Double { RoofGeometry.baseZ(e, model) }

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let x = e.roof?.extrusion, validate(x) == nil, let sec = section(x, thickness: RoofGeometry.thickness(e, model)) else { return [] }
        let o = x.planPoint(0, depth: x.start)
        // Frame: X along the work plane, Y up; local Z = X × Y = −normal, so a negative depth extrudes along +normal.
        let frame = Transform3.frame(origin: Vec3(o, z: baseZ(e, model)), xAxis: Vec3(x.direction.x, x.direction.y, 0), yAxis: .unitZ)
        let mesh = MeshBuilder.extrude(Profile2(outer: sec), frame: frame, depth: -(x.end - x.start))
        return [MeshPart(mesh: mesh, materialID: SlabGeometry.surfaceMaterial(e, model))]
    }

    /// Plan rectangle covered by the roof.
    public static func footprint(_ e: Element) -> Polygon2? {
        guard let x = e.roof?.extrusion, let top = topLine(x) else { return nil }
        let xs = top.map(\.x)
        guard let lo = xs.min(), let hi = xs.max(), hi - lo > Tolerance.length else { return nil }
        return Polygon2([x.planPoint(lo, depth: x.start), x.planPoint(hi, depth: x.start), x.planPoint(hi, depth: x.end), x.planPoint(lo, depth: x.end)]).counterClockwise
    }

    /// Heights of a polyline at station `s` (every segment spanning it).
    static func heights(_ line: [Vec2], at s: Double) -> [Double] {
        var out: [Double] = []
        for i in 0..<(line.count - 1) {
            let a = line[i], b = line[i + 1]
            let lo = min(a.x, b.x), hi = max(a.x, b.x)
            guard s >= lo - Tolerance.length, s <= hi + Tolerance.length else { continue }
            if hi - lo < Tolerance.length { out.append(max(a.y, b.y)); continue }
            out.append(a.y + (b.y - a.y) * (s - a.x) / (b.x - a.x))
        }
        return out
    }

    static func inDepth(_ x: RoofExtrusion, _ p: Vec2) -> Double? {
        let l = x.local(p)
        guard l.depth >= min(x.start, x.end) - Tolerance.length, l.depth <= max(x.start, x.end) + Tolerance.length else { return nil }
        return l.x
    }

    /// Top surface elevation above a plan point (highest crossing), nil outside the roof.
    public static func topZ(_ e: Element, at p: Vec2, _ model: BIMModel) -> Double? {
        guard let x = e.roof?.extrusion, let s = inDepth(x, p), let top = topLine(x), let h = heights(top, at: s).max() else { return nil }
        return baseZ(e, model) + h
    }

    /// Underside elevation above a plan point (lowest crossing), nil outside the roof.
    public static func undersideZ(_ e: Element, at p: Vec2, _ model: BIMModel) -> Double? {
        guard let x = e.roof?.extrusion, let s = inDepth(x, p), let top = topLine(x) else { return nil }
        guard let h = heights(underside(top, thickness: RoofGeometry.thickness(e, model)), at: s).min() else { return nil }
        return baseZ(e, model) + h
    }

    public static func ridgeHeight(_ e: Element, _ model: BIMModel) -> Double? {
        guard let x = e.roof?.extrusion, let top = topLine(x), let h = top.map(\.y).max() else { return nil }
        return baseZ(e, model) + h
    }

    /// Sloped top area, volume and perimeter of the plan footprint.
    public static func quantities(_ e: Element, _ model: BIMModel) -> (area: Double, volume: Double, perimeter: Double, top: Double)? {
        guard let x = e.roof?.extrusion, let top = topLine(x), let sec = section(x, thickness: RoofGeometry.thickness(e, model)) else { return nil }
        let depth = abs(x.end - x.start)
        let length = (0..<(top.count - 1)).reduce(0) { $0 + top[$1].distance(to: top[$1 + 1]) }
        return (length * depth, sec.area * depth, footprint(e)?.perimeter ?? 0, baseZ(e, model) + (top.map(\.y).max() ?? 0))
    }
}
