import Foundation
import ArcusGeometry

// STAIR: 3D of stairs from the stair layout and the run, landing and support types: monolithic runs (a stepped solid
// with a sloped soffit of the run type's Structural Depth), assembled runs (treads with nosings and risers on
// stringers or carriages), landings of the landing type's thickness, and supports. Every piece is a closed solid of
// its own, so sections cut each one cleanly.

/// A piece of a stair's 3D: one run, landing or support, with its parts by material (IFC exports each run as a flight
/// and each landing as a slab).
public struct StairPiece: Sendable {
    public enum Kind: Sendable, Equatable { case run(Int), landing(Int), support(Int) }
    public var kind: Kind
    public var parts: [MeshPart]
    /// The storey of a multistory stair (0: the stair itself).
    public var storey: Int
}

public enum StairMeshes {
    /// 3D of the stair, every storey of a multistory stair, merged by material.
    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        var groups: [ElementID?: Mesh] = [:]
        var order: [ElementID?] = []
        for piece in pieces(e, model) {
            for p in piece.parts where !p.mesh.isEmpty {
                if groups[p.materialID] == nil { order.append(p.materialID) }
                groups[p.materialID, default: Mesh()].append(p.mesh)
            }
        }
        return order.map { MeshPart(mesh: groups[$0]!, materialID: $0) }
    }

    /// The stair's runs, landings and supports as separate pieces (every storey of a multistory stair).
    public static func pieces(_ e: Element, _ model: BIMModel) -> [StairPiece] {
        let storeys = MultistoryStairs.storeys(of: e, model) ?? [e] // F2
        return storeys.enumerated().flatMap { k, s in pieces(single: s, model).map { var p = $0; p.storey = k; return p } }
    }

    static func pieces(single e: Element, _ model: BIMModel) -> [StairPiece] {
        guard let l = StairGeometry.layout(e, model) else { return [] }
        var out: [StairPiece] = []
        func piece(_ kind: StairPiece.Kind, _ meshes: [(Mesh, ElementID?)]) {
            var groups: [ElementID?: Mesh] = [:], order: [ElementID?] = []
            for (m, mat) in meshes where !m.isEmpty {
                if groups[mat] == nil { order.append(mat) }
                groups[mat, default: Mesh()].append(m)
            }
            if !order.isEmpty { out.append(StairPiece(kind: kind, parts: order.map { MeshPart(mesh: groups[$0]!, materialID: $0) }, storey: 0)) }
        }
        let rt = l.type.run
        for r in l.runs {
            var meshes: [(Mesh, ElementID?)] = []
            if rt.monolithic {
                // A tread finish on a monolithic run: the structure stops under it, the finish's top is the walking surface.
                let finish = rt.tread ? rt.treadThickness : 0
                meshes += monolithicRun(r, l, lowered: finish).map { ($0, rt.material) }
                if rt.tread { meshes += r.treads.map { (treadSlab($0, r, l, thickness: finish, top: $0.z), rt.treadMaterial) } }
            } else {
                meshes += r.treads.map { (treadSlab($0, r, l, thickness: rt.treadThickness, top: $0.z), rt.treadMaterial) }
                if rt.riser { meshes += r.riserLines.map { (riser($0, r, l), rt.riserMaterial) } }
            }
            piece(.run(r.index), meshes)
        }
        let lt = l.type.landing
        for (k, land) in l.landings.enumerated() {
            let prof = Profile2(outer: land.polygon)
            if lt.tread {
                piece(.landing(k), [(MeshBuilder.extrude(prof, bottom: land.z - lt.treadThickness, top: land.z), lt.treadMaterial),
                                    (MeshBuilder.extrude(prof, bottom: land.z - lt.treadThickness - lt.thickness, top: land.z - lt.treadThickness), lt.material)])
            } else {
                piece(.landing(k), [(MeshBuilder.extrude(prof, bottom: land.z - lt.thickness, top: land.z), lt.material)])
            }
        }
        for (k, s) in l.supports.enumerated() { piece(.support(k), supportMeshes(s, l).map { ($0, s.info.material ?? rt.material) }) }
        return out
    }

    // MARK: Monolithic runs

    /// A monolithic run: straight runs as one stepped profile with a sloped soffit; other shapes tread by tread, each
    /// down to the soffit under it.
    static func monolithicRun(_ r: StairLayout.Run, _ l: StairLayout, lowered: Double = 0) -> [Mesh] {
        let depth = l.type.run.structuralDepth
        let rh = l.riserHeight, slope = rh / max(l.treadDepth, 1e-6)
        let cosA = 1 / (1 + slope * slope).squareRoot()
        let drop = depth / cosA
        if r.shape == .straight {
            let d = r.direction, length = r.walkLength
            // Profile in the run's vertical plane: x along travel from the start edge, y = elevation.
            var pts: [Vec2] = [Vec2(0, r.baseZ)]
            var zNow = r.baseZ
            for t in r.treads {
                let x0 = (t.front.midpoint - r.startEdge.midpoint).dot(d), x1 = (t.back.midpoint - r.startEdge.midpoint).dot(d)
                let z = t.z - lowered
                if z > zNow + 1e-9 { pts.append(Vec2(x0, z)) }
                pts.append(Vec2(x1, z))
                zNow = z
            }
            // The last riser: a landing after the run forms it; at the top of the stair the run carries it with a
            // bearing one tread deep under the floor it meets.
            var endX = length
            if r.topZ - lowered > zNow + 1e-9, r.index == l.runs.last?.index {
                pts.append(Vec2(length, r.topZ - lowered))
                endX = length + l.treadDepth
                pts.append(Vec2(endX, r.topZ - lowered))
            }
            // Soffit parallel to the line through the tread-riser corners (z = base + x · slope), `drop` below it.
            let soffit = { (x: Double) in r.baseZ + x * slope - drop }
            let zEnd = max(soffit(endX), r.baseZ)
            if zEnd < (pts.last?.y ?? 0) - 1e-6 { pts.append(Vec2(endX, zEnd)) }
            let xFloor = drop / slope
            if xFloor > 0, xFloor < endX, zEnd > r.baseZ + 1e-6 { pts.append(Vec2(xFloor, r.baseZ)) }
            let profile = Polygon2(pts).simplified()
            guard !profile.isDegenerate, profile.isSimple else { return [] }
            let origin = r.startEdge.end // right boundary at the start
            let frame = Transform3.frame(origin: Vec3(origin.x, origin.y, 0), xAxis: Vec3(d.x, d.y, 0), yAxis: .unitZ)
            // Frame Z = X × Y points to the right of travel; extrude toward the left (negative depth).
            return [MeshBuilder.extrude(Profile2(outer: profile), frame: frame, depth: -r.width)]
        }
        // Spiral and winder runs: each tread a prism down to the soffit plane under it (sloped along the walk line).
        var out: [Mesh] = []
        for (k, t) in r.treads.enumerated() {
            let soffitZ = r.baseZ + Double(k) * rh + rh * 0.5 - drop
            let g = t.walkDirection.normalized
            let top = PlaneZ.flat(t.z - lowered)
            var bottom = PlaneZ(a: g.x * slope, b: g.y * slope, c: soffitZ - slope * g.dot(t.walkPoint))
            let minZ = t.polygon.points.map { bottom.z(at: $0) }.min() ?? soffitZ
            let maxZ = t.polygon.points.map { bottom.z(at: $0) }.max() ?? soffitZ
            if minZ < r.baseZ || maxZ > t.z - 0.02 { bottom = PlaneZ.flat(max(r.baseZ, min(soffitZ, t.z - 0.05))) }
            out.append(MeshBuilder.slab(Profile2(outer: t.polygon), bottom: bottom, top: top))
        }
        return out
    }

    // MARK: Assembled runs

    /// A tread slab (with its nosing: the front edge, and the sides the run type names, pushed out by the Nosing
    /// Length) from `top - thickness` to `top`.
    static func treadSlab(_ t: StairTread, _ r: StairLayout.Run, _ l: StairLayout, thickness: Double, top: Double) -> Mesh {
        let rt = l.type.run
        var poly = t.polygon
        let nose = rt.nosingLength
        if nose > 1e-6, t.front.length > 1e-6 {
            let fwd = -t.walkDirection.normalized
            let toLeft = -t.front.direction
            let pushLeft = rt.applyNosing == .frontLeft || rt.applyNosing == .frontLeftRight
            let pushRight = rt.applyNosing == .frontRight || rt.applyNosing == .frontLeftRight
            func near(_ p: Vec2, _ q: Vec2) -> Bool { p.isAlmostEqual(q, tolerance: 1e-6) }
            poly = Polygon2(poly.points.map { p in
                var q = p
                if near(p, t.front.start) || near(p, t.front.end) { q = q + fwd * nose }
                if pushLeft, near(p, t.front.start) || near(p, t.back.start) { q = q + toLeft * nose }
                if pushRight, near(p, t.front.end) || near(p, t.back.end) { q = q - toLeft * nose }
                return q
            })
        }
        return MeshBuilder.extrude(Profile2(outer: poly), bottom: top - thickness, top: top)
    }

    /// A riser plate along a riser line, behind it in the direction of travel, between the treads it joins.
    static func riser(_ k: StairRiserLine, _ r: StairLayout.Run, _ l: StairLayout) -> Mesh {
        let rt = l.type.run
        let th = rt.riserThickness
        guard th > 1e-6, k.line.length > 1e-6 else { return .empty }
        let back = k.line.direction.perpendicular * -1 // travel direction: the line runs left → right
        let a = k.line.start, b = k.line.end
        let poly = Polygon2([a, b, b + back * th, a + back * th])
        let tt = rt.treadThickness
        let z0 = rt.connection == .riserBehindTread ? k.z0 - tt : k.z0
        let z1 = k.z1 - tt
        guard z1 > z0 + 1e-6 else { return .empty }
        return MeshBuilder.extrude(Profile2(outer: poly), bottom: z0, top: z1)
    }

    // MARK: Supports

    /// Stringers and carriages, segment by segment along their path: each a prism of the support's width whose top
    /// follows the path (nosing line plus Top Offset for stringers, under the treads for carriages), the support's
    /// depth (perpendicular to the slope) below it, never below the stair's base.
    static func supportMeshes(_ s: StairLayout.Support, _ l: StairLayout) -> [Mesh] {
        var path = s.path
        guard path.count >= 2 else { return [] }
        let info = s.info
        let lift: (StairPathPoint) -> Double = { p in
            if s.kind == .carriageOpen { return p.onLanding ? -l.type.landing.thickness : -(l.riserHeight + l.type.run.treadThickness) }
            return info.topOffset
        }
        // A stringer starts on the floor in front of the first riser: one tread back along the pitch.
        if s.kind == .stringerClosed, let first = path.first, !first.onLanding, path.count >= 2 {
            let d = (path[1].point - first.point)
            if d.length > 1e-6 {
                let back = first.point - d.normalized * l.treadDepth
                path.insert(StairPathPoint(point: back, z: first.z - l.riserHeight, onLanding: false), at: 0)
            }
        }
        var out: [Mesh] = []
        for (p, q) in zip(path, path.dropFirst()) {
            let seg = Segment2(p.point, q.point)
            guard seg.length > 1e-4 else { continue }
            let za = p.z + lift(p), zb = q.z + lift(q)
            let slope = (zb - za) / seg.length
            // A step at a corner (landing to run) is a joint, not a piece of stringer.
            if abs(slope) > 2.5 { continue }
            let cosA = 1 / (1 + slope * slope).squareRoot()
            let depth = (p.onLanding && q.onLanding ? info.landingDepth : info.depth) / cosA
            let n = seg.direction.perpendicular * (info.width / 2)
            let dir = seg.direction
            // Top plane through the segment's top line, level across the support.
            let top = PlaneZ(a: dir.x * slope, b: dir.y * slope, c: za - slope * dir.dot(p.point))
            let bottom = PlaneZ(a: top.a, b: top.b, c: top.c - depth)
            func quad(_ s0: Double, _ s1: Double) -> Profile2 {
                let a = seg.start + dir * s0, b = seg.start + dir * s1
                return Profile2(outer: Polygon2([a - n, b - n, b + n, a + n]).counterClockwise)
            }
            let floor = l.baseZ
            let b0 = za - depth, b1 = zb - depth
            if b0 >= floor - 1e-9 && b1 >= floor - 1e-9 {
                out.append(MeshBuilder.slab(quad(0, seg.length), bottom: bottom, top: top))
            } else if b0 < floor && b1 < floor {
                if max(za, zb) > floor + 1e-6 { out.append(MeshBuilder.slab(quad(0, seg.length), bottom: .flat(floor), top: top)) }
            } else {
                let x = seg.length * (floor - b0) / (b1 - b0)
                let (flatPart, slopedPart) = b0 < floor ? ((0.0, x), (x, seg.length)) : ((x, seg.length), (0.0, x))
                if flatPart.1 - flatPart.0 > 1e-4 { out.append(MeshBuilder.slab(quad(flatPart.0, flatPart.1), bottom: .flat(floor), top: top)) }
                if slopedPart.1 - slopedPart.0 > 1e-4 { out.append(MeshBuilder.slab(quad(slopedPart.0, slopedPart.1), bottom: bottom, top: top)) }
            }
        }
        return out
    }
}

extension StairGeometry {
    /// 3D of the stair (every storey of a multistory stair).
    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] { StairMeshes.meshParts(e, model) }
}
