import Foundation
import ArcusGeometry

// FMG4: what sits on a canted front follows the face when a loaded piece flexes out of square: the face's corners
// move with their planes, the face turns a little and changes length (CantAnchors), and hardware, edge-profile voids,
// louvers and elevation swings are placed between the corners and turned with the face (their rotation a formula of
// the corners), as a Revit-style door on a reference line between two planes does.

/// Where a shape placed on a canted face sits on it (face coordinates) and how it turns with it.
public struct CantPlacement: Sendable {
    public var anchors: CantAnchors
    /// The placement point on the face (u along it, v into it).
    public var u: Double, v: Double
    /// Degrees from the face's u direction.
    public var localRotation: Double
    /// The face coordinates (u) the shape's length spans, when its length runs along the face.
    public var spanU: (Double, Double)?
}

extension CantAnchors {
    /// The corners as length formulas (p0, p1), or nil when a plane has no formula.
    func cornerFormulas(_ ctx: PartSolidContext) -> (x0: String, y0: String, x1: String, y1: String)? {
        guard let formula = ctx.planeFormula else { return nil }
        func e(_ p: PartValue) -> String? {
            guard let n = p.plane else { return "\(FurnitureFormLocks.num(p.value)) m" }
            return PlaneTerms.expression(n, offset: p.offset, formula)
        }
        guard let x0 = e(p0.x), let y0 = e(p0.y), let x1 = e(p1.x), let y1 = e(p1.y) else { return nil }
        return (x0, y0, x1, y1)
    }

    /// The face's length between its corners, as a formula.
    func lengthFormula(_ ctx: PartSolidContext) -> String? {
        guard let c = cornerFormulas(ctx) else { return nil }
        let dx = "((\(c.x1)) - (\(c.x0)))", dy = "((\(c.y1)) - (\(c.y0)))"
        return "sqrt(\(dx) * \(dx) + \(dy) * \(dy))"
    }

    /// A rotation (degrees about Z) that turns with the face from what it is now (`degrees`).
    func rotationFormula(_ degrees: Double, _ ctx: PartSolidContext) -> String? {
        guard let c = cornerFormulas(ctx) else { return nil }
        let d = Vec2(p1.x.value - p0.x.value, p1.y.value - p0.y.value)
        // The corners' direction now, and the turn from it to the shape.
        let now = atan2(d.y, d.x) * 180 / .pi
        let delta = degrees - now
        let n = FurnitureFormLocks.num
        return "atan2((\(c.y1)) - (\(c.y0)), (\(c.x1)) - (\(c.x0))) * 180 / pi() \(delta < 0 ? "-" : "+") \(n(abs(delta)))"
    }

    /// The distance along the face from p0 to the point at face coordinate `u` (from the nearer corner, as `point`).
    func position(_ u: Double, _ ctx: PartSolidContext) -> String? {
        let sigma: Double = u1 >= u0 ? 1 : -1
        let n = FurnitureFormLocks.num
        if abs(u - u0) <= abs(u - u1) { return "(\(n(sigma * (u - u0))) m)" }
        guard let len = lengthFormula(ctx) else { return nil }
        return "(\(len) - \(n(sigma * (u1 - u))) m)"
    }

    /// The length along the face between face coordinates `a` and `b`.
    func span(_ a: Double, _ b: Double, _ ctx: PartSolidContext) -> String? {
        guard let pa = position(a, ctx), let pb = position(b, ctx) else { return nil }
        let sigma: Double = u1 >= u0 ? 1 : -1
        return sigma * (b - a) >= 0 ? "(\(pb) - \(pa))" : "(\(pa) - \(pb))"
    }
}

extension BayFrame {
    /// A local family placed on the face (as `placed`), remembering where it sits on a canted face when compiling.
    func placed(_ p: PlacedLocalFamily, anchors: CantAnchors?, spanAlongU: Bool) -> PlacedLocalFamily {
        var q = placed(p)
        if let anchors, !isSquare {
            q.cant = CantPlacement(anchors: anchors, u: p.x.value, v: p.y.value, localRotation: p.rotation,
                                   spanU: spanAlongU ? p.span.map { ($0.start.value, $0.end.value) } : nil)
        }
        return q
    }

    /// FMG4: a louver (a prism across a leaf on its yz plane, extruded along u) on a canted face, as a local family
    /// placed on the face: the slat keeps its tilt (a canted face has no model plane to draw it on).
    func louver(_ name: String, _ pts: [Vec2], u: (PartValue, PartValue), _ ctx: PartSolidContext, material: ElementID?) -> PlacedLocalFamily {
        let (a, b) = u.0.value <= u.1.value ? (u.0, u.1) : (u.1, u.0)
        var fam = FamilyDefinition(name: "Louver \(pts.map { "\(Int(($0.x * 1e4).rounded())),\(Int(($0.y * 1e4).rounded()))" }.joined(separator: " "))", template: .genericModel)
        fam.parameters = [FamilyParameter(name: "Length", type: .length)]
        fam.types = [FamilyTypeDefinition(name: "Louver", values: ["Length": .double(b.value - a.value)])]
        let poly = Polygon2(pts).counterClockwise.points
        var s = FamilySolid(name: name, profile: .polygon(poly.map { FamilyPoint(PartSolidContext.number($0.x), PartSolidContext.number($0.y)) }),
                            zMin: .expr("0"), zMax: .expr("Length"))
        s.workPlane = .yz
        fam.solids = [s]
        let local = PlacedLocalFamily(family: fam, x: a, y: PartValue(0), z: PartValue(0), rotation: 0, mirrored: false, span: (a, b), material: material)
        return placed(local, anchors: ctx.cantAnchors, spanAlongU: true)
    }
}

extension FurnitureCompiler {
    /// FMG4: the placement of a local family on a canted face in the compiled family: its point between the face's
    /// corners, its rotation turning with them and its length along the face; nil when it isn't on a canted face.
    static func cantedPlacement(_ p: PlacedLocalFamily, _ ctx: PartSolidContext) -> (x: FamilyBound, y: FamilyBound, rotation: String, length: String?)? {
        guard let c = p.cant, let xy = c.anchors.point(c.u, c.v, ctx),
              let rot = c.anchors.rotationFormula(p.rotation, ctx) else { return nil }
        let length = c.spanU.flatMap { c.anchors.span($0.0, $0.1, ctx) }
        return (xy.0, xy.1, rot, length)
    }
}
