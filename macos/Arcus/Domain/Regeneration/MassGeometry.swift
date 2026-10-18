import Foundation
import ArcusGeometry
import ArcusCalc

// F5: geometry of conceptual masses (RevitCraft rc-core build3d.rs and plan.rs `ElementKind::Mass`) and Model by Face
// (edit.rs `model_by_face`).

/// One face of a mass: a side face between edge `index` of the footprint and the same edge of the top loop, or the
/// top face.
public struct MassFace: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case side, top }
    public var kind: Kind
    /// Side faces: the footprint edge (counterclockwise, so the mass lies to its left). Unused for the top face.
    public var index: Int
    public var bottom: Segment2
    public var top: Segment2
    public var z0: Double
    public var z1: Double
    /// True when the face is vertical (extrusions; blends lean inward).
    public var isVertical: Bool { bottom.start.isAlmostEqual(top.start, tolerance: 1e-6) && bottom.end.isAlmostEqual(top.end, tolerance: 1e-6) }
}

public enum MassGeometry {
    /// RevitCraft's default In-Place Mass height: 10 m (30'-0" in imperial projects).
    public static func defaultHeight(_ units: UnitsSettings) -> Double { units.system == .imperial ? 9.144 : 10 }

    public static func baseZ(_ e: Element, _ model: BIMModel) -> Double { model.elevation(ofLevel: e.levelID) + (e.mass?.baseOffset ?? 0) }
    public static func topZ(_ e: Element, _ model: BIMModel) -> Double { baseZ(e, model) + (e.mass?.height ?? 0) }

    /// The footprint (counterclockwise).
    public static func footprint(_ m: MassData) -> Polygon2 { Polygon2(m.boundary).counterClockwise }

    /// The top loop: the footprint, or for a blend the footprint shrunk by the top inset (nil when that leaves nothing).
    public static func topLoop(_ m: MassData) -> Polygon2? { loop(m, at: 1) }

    /// The horizontal section `t` of the way up (0 = base, 1 = top), counterclockwise; nil when a blend's inset leaves
    /// nothing at that height.
    public static func loop(_ m: MassData, at t: Double) -> Polygon2? {
        let base = footprint(m)
        guard base.count >= 3, !base.isDegenerate else { return nil }
        guard m.isBlend else { return base }
        let d = (m.topInset ?? 0) * min(max(t, 0), 1)
        if d <= Tolerance.length { return base }
        return base.offset(by: -d).filter(\.isCounterClockwise).max { $0.area < $1.area }
    }

    /// The section at absolute elevation `z`, or nil outside the mass.
    public static func section(_ e: Element, _ model: BIMModel, atZ z: Double) -> Polygon2? {
        guard let m = e.mass, m.height > Tolerance.length else { return nil }
        let z0 = baseZ(e, model)
        guard z >= z0 - Tolerance.length, z <= z0 + m.height + Tolerance.length else { return nil }
        return loop(m, at: (z - z0) / m.height)
    }

    /// The solid: an extrusion of the footprint, or a blend lofted from the footprint to the top loop.
    public static func mesh(_ e: Element, _ model: BIMModel) -> Mesh {
        guard let m = e.mass, m.height > Tolerance.length else { return .empty }
        let base = footprint(m)
        guard base.count >= 3, !base.isDegenerate else { return .empty }
        let z0 = baseZ(e, model), z1 = z0 + m.height
        if m.isBlend, let top = topLoop(m) {
            return FamilyFormGeometry.blendMesh(bottom: base, top: top, z0: z0, z1: z1) // the Family Editor's blend form
        }
        return MeshBuilder.extrude(Profile2(outer: base), bottom: z0, top: z1)
    }

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        let m = mesh(e, model)
        return m.isEmpty ? [] : [MeshPart(mesh: m, materialID: nil)]
    }

    /// The side faces (one per footprint edge) and the top face.
    public static func faces(_ e: Element, _ model: BIMModel) -> [MassFace] {
        guard let m = e.mass else { return [] }
        let base = footprint(m)
        guard base.count >= 3, let top = topLoop(m) else { return [] }
        let z0 = baseZ(e, model), z1 = z0 + m.height
        var out: [MassFace] = []
        let topEdges = top.count == base.count ? aligned(top, to: base).edges : []
        for (i, b) in base.edges.enumerated() {
            // A blend whose top loop lost or gained corners has no face per footprint edge.
            guard m.isBlend == false || topEdges.count == base.count else { break }
            out.append(MassFace(kind: .side, index: i, bottom: b, top: m.isBlend ? topEdges[i] : b, z0: z0, z1: z1))
        }
        out.append(MassFace(kind: .top, index: -1, bottom: Segment2(.zero, .zero), top: Segment2(.zero, .zero), z0: z1, z1: z1))
        return out
    }

    /// `top` rotated so its vertex i lies nearest the footprint's vertex i (an inset loop keeps the corners).
    static func aligned(_ top: Polygon2, to base: Polygon2) -> Polygon2 {
        guard let first = base.points.first, let k = top.points.indices.min(by: { top.points[$0].distance(to: first) < top.points[$1].distance(to: first) }) else { return top }
        return Polygon2(Array(top.points[k...] + top.points[..<k]))
    }

    /// The face of a mass nearest a plan point (side faces by their footprint edge; inside the top loop of a blend, the
    /// top face).
    public static func nearestSideFace(_ e: Element, _ model: BIMModel, to p: Vec2) -> MassFace? {
        faces(e, model).filter { $0.kind == .side }.min { $0.bottom.distance(to: p) < $1.bottom.distance(to: p) }
    }

    /// The face under a 3D surface point: the top when the point is at the top elevation, else the nearest side face.
    public static func face(_ e: Element, _ model: BIMModel, at p: Vec3) -> MassFace? {
        let all = faces(e, model)
        if abs(p.z - topZ(e, model)) < 0.01 { return all.first { $0.kind == .top } }
        let sides = all.filter { $0.kind == .side }
        return sides.min { distance($0, p) < distance($1, p) }
    }

    /// Plan distance from a point to a side face at the point's height.
    static func distance(_ f: MassFace, _ p: Vec3) -> Double {
        let t = f.z1 - f.z0 > Tolerance.length ? min(max((p.z - f.z0) / (f.z1 - f.z0), 0), 1) : 0
        let a = f.bottom.start + (f.top.start - f.bottom.start) * t, b = f.bottom.end + (f.top.end - f.bottom.end) * t
        return Segment2(a, b).distance(to: p.xy)
    }

    /// Levels whose elevation lies in the mass, from its base up to (not including) its top: where mass floors are.
    public static func floorLevels(_ e: Element, _ model: BIMModel) -> [Element] {
        let z0 = baseZ(e, model), z1 = topZ(e, model)
        return model.levels.filter { let z = $0.level?.elevation ?? 0; return z >= z0 - 0.001 && z < z1 - 0.001 }
    }

    /// Gross Floor Area: the mass's section area at every level that cuts it.
    public static func grossFloorArea(_ e: Element, _ model: BIMModel) -> Double {
        floorLevels(e, model).reduce(0) { $0 + (section(e, model, atZ: $1.level?.elevation ?? 0)?.area ?? 0) }
    }

    /// Quantities: Gross Surface Area (area), Gross Volume (volume), height and perimeter of the footprint.
    public static func quantities(_ e: Element, _ model: BIMModel, _ q: inout ElementQuantities) {
        guard let m = e.mass else { return }
        let solid = mesh(e, model)
        q.volume = abs(solid.signedVolume)
        q.area = solid.surfaceArea
        q.height = m.height
        q.perimeter = footprint(m).perimeter
        q.elevationBottom = baseZ(e, model)
        q.elevationTop = topZ(e, model)
    }

    /// "Mass 1", "Mass 2"… (RevitCraft's names for new masses).
    public static func nextName(_ model: BIMModel) -> String {
        let used = Set(model.elements(.mass).map(\.name))
        var n = model.elements(.mass).count + 1
        while used.contains("Mass \(n)") { n += 1 }
        return "Mass \(n)"
    }

    /// Creates a mass from a closed footprint (RevitCraft `add_mass`).
    @discardableResult
    public static func create(boundary: [Vec2], height: Double, topInset: Double? = nil, level: ElementID?, in tx: TransactionContext) throws -> ElementID {
        let poly = Polygon2(boundary)
        guard poly.count >= 3, !poly.isDegenerate else { throw TransactionError("The mass needs a closed boundary.") }
        guard height > Tolerance.length else { throw TransactionError("The mass height must be positive.") }
        let data = MassData(boundary: poly.points, height: height, topInset: topInset.flatMap { $0 > Tolerance.length ? $0 : nil })
        if data.isBlend, MassGeometry.topLoop(data) == nil { throw TransactionError("The top inset leaves no top face. Use a smaller inset.") }
        return tx.create(.mass, name: nextName(tx.model), data: .mass(data), levelID: level)
    }
}

// MARK: - Model by Face

/// What Model by Face builds on a mass.
public enum ModelByFaceKind: String, Sendable, CaseIterable {
    case curtainSystem = "Curtain System", roof = "Roof", wall = "Wall", floor = "Floor"
}

/// Massing & Site ▸ Model by Face (RevitCraft edit.rs `model_by_face`): native walls, curtain walls, floors and roofs
/// made from a mass's faces. Walls put their exterior finish face on the mass face; floors go where levels cut the
/// mass (mass floors); the roof sits on the top face.
public enum ModelByFace {
    /// Creates elements on `faces` of `massID` (all of them when nil). `typeID` is the wall, curtain wall, floor or
    /// roof type. Returns the new elements; throws when nothing can be made.
    @discardableResult
    public static func create(_ kind: ModelByFaceKind, mass massID: ElementID, faces chosen: [MassFace]? = nil, typeID: ElementID?,
                              in tx: TransactionContext) throws -> [ElementID] {
        let model = tx.model
        guard let e = model[massID], let m = e.mass else { throw TransactionError("Select a mass.") }
        let all = MassGeometry.faces(e, model)
        var out: [ElementID] = []
        switch kind {
        case .wall, .curtainSystem:
            let sides = (chosen ?? all).filter { $0.kind == .side }
            guard !sides.isEmpty else { throw TransactionError("Walls by face are made on the side faces of a mass.") }
            let curtain = kind == .curtainSystem
            if curtain, sides.contains(where: { !$0.isVertical }) {
                throw TransactionError("Curtain systems need vertical faces; this mass tapers to its top.", elements: [massID])
            }
            let slant = m.isBlend ? -atan((m.topInset ?? 0) / max(m.height, Tolerance.length)) : 0
            for f in sides {
                // Clockwise around the mass, so the exterior side (to the left) faces out.
                let seg = Segment2(f.bottom.end, f.bottom.start)
                if model.elements(.walls).contains(where: { $0.levelID == e.levelID && onSameLine($0, seg) }) { continue }
                var w = WallData(location: .line(seg), locationLine: curtain ? .wallCenterline : .finishFaceExterior,
                                 baseOffset: m.baseOffset, topLevelID: nil, unconnectedHeight: m.height)
                w.slantAngle = slant
                if curtain { w.curtain = CurtainInstanceData(); w.slantAngle = 0 }
                out.append(tx.create(.walls, data: .wall(w), typeID: typeID, levelID: e.levelID))
            }
            if out.isEmpty { throw TransactionError("These faces already have walls.", elements: [massID]) }
        case .floor:
            let levels = MassGeometry.floorLevels(e, model)
            guard !levels.isEmpty else { throw TransactionError("No level cuts the mass. Floors by face need mass floors at levels.", elements: [massID]) }
            for l in levels {
                guard let loop = MassGeometry.section(e, model, atZ: l.level?.elevation ?? 0) else { continue }
                let sketch = Sketch(polygon: loop)
                if model.elements(.floors).contains(where: { $0.levelID == l.id && $0.slab?.boundary == sketch }) { continue }
                out.append(tx.create(.floors, data: .slab(SlabData(boundary: sketch)), typeID: typeID, levelID: l.id))
            }
            if out.isEmpty { throw TransactionError("The mass floors already have floors.", elements: [massID]) }
        case .roof:
            if let chosen, !chosen.contains(where: { $0.kind == .top }) { throw TransactionError("Roofs by face are made on the top face of a mass.") }
            guard let top = MassGeometry.topLoop(m) else { throw TransactionError("The mass has no top face.") }
            let z1 = MassGeometry.topZ(e, model)
            // On the level nearest the top, offset to it (RevitCraft).
            let level = model.levels.min { abs(($0.level?.elevation ?? 0) - z1) < abs(($1.level?.elevation ?? 0) - z1) }?.id ?? e.levelID
            let sketch = Sketch(polygon: top)
            if model.elements(.roofs).contains(where: { $0.roof?.footprint == sketch && abs(model.baseElevation(of: $0) - z1) < 0.001 }) {
                throw TransactionError("The mass already has a roof on its top face.", elements: [massID])
            }
            let r = RoofData(footprint: sketch, edgeSlopes: Array(repeating: nil, count: top.count), baseOffset: z1 - model.elevation(ofLevel: level))
            out.append(tx.create(.roofs, data: .roof(r), typeID: typeID, levelID: level))
        }
        return out
    }

    /// True when a wall's location runs along `seg` (either direction).
    static func onSameLine(_ w: Element, _ seg: Segment2) -> Bool {
        guard let s = w.wall?.location.asSegment else { return false }
        let tol = 0.001
        return (s.start.isAlmostEqual(seg.start, tolerance: tol) && s.end.isAlmostEqual(seg.end, tolerance: tol))
            || (s.start.isAlmostEqual(seg.end, tolerance: tol) && s.end.isAlmostEqual(seg.start, tolerance: tol))
    }
}
