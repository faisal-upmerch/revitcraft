import Foundation
import ArcusGeometry

public enum SlabGeometry {
    public static func thickness(_ e: Element, _ model: BIMModel) -> Double {
        let t = model.typeData(of: e)?.assembly?.totalThickness ?? 0
        if t > Tolerance.length { return t }
        return e.category == .ceilings ? 0.025 : 0.2
    }

    public static func profile(_ e: Element) -> Profile2? {
        guard let s = e.slab else { return nil }
        if case .success(let p) = s.boundary.profile() { return p }
        return nil
    }

    /// Top and bottom planes (z = a·x + b·y + c).
    public static func planes(_ e: Element, _ model: BIMModel) -> (bottom: PlaneZ, top: PlaneZ)? {
        guard let s = e.slab else { return nil }
        let t = thickness(e, model)
        let lv = model.elevation(ofLevel: e.levelID) + s.offset
        let isCeiling = e.category == .ceilings
        var top: PlaneZ
        if let arrow = s.slopeArrow, arrow.tail.distance(to: arrow.head) > Tolerance.length {
            let d = (arrow.head - arrow.tail).normalized * arrow.slope
            let z0 = lv + arrow.tailOffset + (isCeiling ? t : 0)
            // z = z0 + d·(p - tail)
            top = PlaneZ(a: d.x, b: d.y, c: z0 - d.dot(arrow.tail))
        } else {
            top = .flat(isCeiling ? lv + t : lv)
        }
        let bottom = PlaneZ(a: top.a, b: top.b, c: top.c - t)
        return (bottom, top)
    }

    public static func mesh(_ e: Element, _ model: BIMModel) -> Mesh {
        guard let p = profile(e), let (b, t) = planes(e, model) else { return .empty }
        if let pts = e.slab?.shapePoints, !pts.isEmpty { return ShapeEditing.mesh(p, bottom: b, top: t, points: pts) }
        return MeshBuilder.slab(p, bottom: b, top: t)
    }

    /// Shaped top surface of a shape-edited floor (nil when unedited).
    public static func shapedSurface(_ e: Element) -> ShapedSurface? {
        guard let pts = e.slab?.shapePoints, !pts.isEmpty, let p = profile(e) else { return nil }
        return ShapeEditing.surface(p, points: pts)
    }

    public static func meshParts(_ e: Element, _ model: BIMModel, detail: DetailLevel) -> [MeshPart] {
        if let cut = ShaftCuts.slabParts(e, model, detail: detail) { return cut } // WP3: shaft openings
        guard let p = profile(e), let (b, t) = planes(e, model) else { return [] }
        // Joined with walls, roofs or floors that cut it: the remaining prisms.
        if let cut = SolidJoins.slabParts(e, model, detail: detail) { return cut }
        // Shape-edited floors: one variable-thickness solid (the top follows the points, the bottom stays planar).
        if let pts = e.slab?.shapePoints, !pts.isEmpty {
            return [MeshPart(mesh: ShapeEditing.mesh(p, bottom: b, top: t, points: pts), materialID: surfaceMaterial(e, model))]
        }
        guard detail == .fine, let a = model.typeData(of: e)?.assembly, a.layers.count > 1 else {
            return [MeshPart(mesh: MeshBuilder.slab(p, bottom: b, top: t), materialID: surfaceMaterial(e, model))]
        }
        // Layered: layers are ordered top to bottom.
        var parts: [MeshPart] = []
        var acc = 0.0
        for layer in a.layers where layer.thickness > Tolerance.length {
            let top = PlaneZ(a: t.a, b: t.b, c: t.c - acc)
            acc += layer.thickness
            let bot = PlaneZ(a: t.a, b: t.b, c: t.c - acc)
            parts.append(MeshPart(mesh: MeshBuilder.slab(p, bottom: bot, top: top), materialID: layer.materialID))
        }
        return parts
    }

    /// Material seen on the exposed (top/exterior) surface in 3D.
    public static func surfaceMaterial(_ e: Element, _ model: BIMModel) -> ElementID? {
        model.typeData(of: e)?.assembly?.layers.first { $0.thickness > 0 }?.materialID ?? primaryMaterial(e, model)
    }

    public static func primaryMaterial(_ e: Element, _ model: BIMModel) -> ElementID? {
        guard let a = model.typeData(of: e)?.assembly else { return nil }
        let core = a.layers.indices.contains(a.coreStart) ? a.layers[a.coreStart] : a.layers.first
        return core?.materialID
    }

    public static func topZ(_ e: Element, at p: Vec2, _ model: BIMModel) -> Double? {
        guard let z = planes(e, model)?.top.z(at: p) else { return nil }
        return z + (shapedSurface(e)?.offset(at: p) ?? 0)
    }
}

public enum RoofGeometry {
    public static func thickness(_ e: Element, _ model: BIMModel) -> Double {
        let t = model.typeData(of: e)?.assembly?.totalThickness ?? 0
        return t > Tolerance.length ? t : 0.3
    }

    /// Footprint polygon and per-edge slopes (arcs are tessellated; segments inherit the curve's slope).
    public static func footprint(_ e: Element) -> (polygon: Polygon2, slopes: [Double?])? {
        guard let r = e.roof, let loop = r.footprint.loops.first, !loop.isEmpty else { return nil }
        guard let ordered = Sketch.orderLoop(loop) else { return nil }
        // Map ordered curves back to their slope entries.
        var pts: [Vec2] = []
        var slopes: [Double?] = []
        for c in ordered {
            let idx = loop.firstIndex(of: c) ?? loop.firstIndex(of: c.reversed) ?? 0
            let slope = idx < r.edgeSlopes.count ? r.edgeSlopes[idx] : nil
            let t = c.tessellate(chordTolerance: 0.01)
            for i in 0..<(t.count - 1) { pts.append(t[i]); slopes.append(slope) }
        }
        var poly = Polygon2(pts)
        guard poly.points.count == slopes.count, !poly.isDegenerate else { return nil }
        if !poly.isCounterClockwise {
            // Reverse points; edge i (p_i → p_i+1) becomes edge n-2-i in the reversed polygon.
            let n = pts.count
            poly = Polygon2(pts.reversed())
            var rs = [Double?](repeating: nil, count: n)
            for i in 0..<n { rs[(n - 2 - i + n) % n] = slopes[i] }
            slopes = rs
        }
        return (poly, slopes)
    }

    public static func openings(_ e: Element) -> [Polygon2] {
        guard let r = e.roof, r.footprint.loops.count > 1 else { return [] }
        let s = Sketch(loops: Array(r.footprint.loops.dropFirst()))
        if case .success(let polys) = s.polygons() { return polys }
        return []
    }

    public static func baseZ(_ e: Element, _ model: BIMModel) -> Double {
        model.elevation(ofLevel: e.levelID) + (e.roof?.baseOffset ?? 0)
    }

    public static func surface(_ e: Element, _ model: BIMModel) -> RoofSurface? {
        guard let (poly, slopes) = footprint(e) else { return nil }
        return RoofSolver.solve(footprint: poly, slopes: slopes, baseZ: baseZ(e, model))
    }

    /// Plane of a planar 3D polygon as z = a·x + b·y + c (nil for vertical faces).
    static func planeZ(_ face: [Vec3]) -> PlaneZ? {
        guard face.count >= 3 else { return nil }
        var n = Vec3.zero
        for i in 0..<face.count {
            let a = face[i], b = face[(i + 1) % face.count]
            n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
        }
        guard abs(n.z) > 1e-9 else { return nil }
        let p = face[0]
        // n·(x - p) = 0 → z = p.z - (n.x (x - p.x) + n.y (y - p.y)) / n.z
        return PlaneZ(a: -n.x / n.z, b: -n.y / n.z, c: p.z + (n.x * p.x + n.y * p.y) / n.z)
    }

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        if let cut = SolidJoins.roofParts(e, model) { return cut }
        if e.roof?.extrusion != nil { return RoofExtrusionGeometry.meshParts(e, model) }
        if let shaped = shapedMesh(e, model) { return [MeshPart(mesh: shaped, materialID: SlabGeometry.surfaceMaterial(e, model))] }
        guard let s = surface(e, model) else { return [] }
        let t = thickness(e, model)
        let holes = (openings(e) + ShaftCuts.externalCuts(for: e, model)).map { Profile2(outer: $0) }
        let faceCuts = HostedOpenings.faceCuts(e, model) // F1: By Face openings
        var mesh = Mesh()
        for face in s.faces {
            guard let top = planeZ(face) else { continue }
            let bottom = PlaneZ(a: top.a, b: top.b, c: top.c - t)
            let xy = Polygon2(face.map(\.xy))
            guard !xy.isDegenerate else { continue }
            let pieces = holes.isEmpty ? [Profile2(outer: xy)] : PolygonBoolean.difference([Profile2(outer: xy)], holes)
            for piece in pieces { mesh.append(HostedOpenings.roofPiece(piece, bottom: bottom, top: top, faceCuts: faceCuts)) } // F1
        }
        var parts = [MeshPart(mesh: mesh, materialID: SlabGeometry.surfaceMaterial(e, model))]
        if e.roof?.fascia == true || e.roof?.gutter == true, let (poly, slopes) = footprint(e) {
            parts.append(contentsOf: eaveProfiles(poly, slopes: slopes, baseZ: baseZ(e, model), thickness: t, e: e, model))
        }
        return parts
    }

    /// Solid of a shape-edited flat roof (nil when the roof isn't shape edited).
    public static func shapedMesh(_ e: Element, _ model: BIMModel) -> Mesh? {
        guard let pts = e.roof?.shapePoints, !pts.isEmpty, ShapeEditing.canEdit(e), let prof = ShapeEditing.profile(of: e) else { return nil }
        let z = baseZ(e, model), t = thickness(e, model)
        return ShapeEditing.mesh(prof, bottom: .flat(z - t), top: .flat(z), points: pts)
    }

    /// Fascia boards and gutters swept along slope-defining eave edges.
    static func eaveProfiles(_ poly: Polygon2, slopes: [Double?], baseZ: Double, thickness t: Double, e: Element, _ model: BIMModel) -> [MeshPart] {
        var parts: [MeshPart] = []
        let edges = poly.edges
        for (i, edge) in edges.enumerated() where slopes[i] != nil && edge.length > 0.1 {
            let path = [Vec3(edge.start, z: baseZ), Vec3(edge.end, z: baseZ)]
            if e.roof?.fascia == true {
                // Fascia: 25 mm × (thickness + 50 mm) board on the outside of the eave (profile u = left of path = inside).
                let fascia = Polygon2([Vec2(-0.025, -t - 0.05), Vec2(0, -t - 0.05), Vec2(0, 0.02), Vec2(-0.025, 0.02)])
                parts.append(MeshPart(mesh: MeshBuilder.sweep(profile: fascia, along: path), materialID: nil, subcategory: .frame))
            }
            if e.roof?.gutter == true {
                let g = Polygon2([Vec2(-0.15, -t), Vec2(-0.025, -t), Vec2(-0.025, -t - 0.12), Vec2(-0.15, -t - 0.12)])
                parts.append(MeshPart(mesh: MeshBuilder.sweep(profile: g, along: path), materialID: nil, subcategory: .frame))
            }
        }
        return parts
    }

    /// Top surface elevation at a plan point (max over faces containing it).
    public static func topZ(_ e: Element, at p: Vec2, _ model: BIMModel) -> Double? {
        if e.roof?.extrusion != nil { return RoofExtrusionGeometry.topZ(e, at: p, model) }
        if let pts = e.roof?.shapePoints, !pts.isEmpty, ShapeEditing.canEdit(e), let prof = ShapeEditing.profile(of: e) {
            guard prof.contains(p), let off = ShapeEditing.surface(prof, points: pts)?.offset(at: p) else { return nil }
            return baseZ(e, model) + off
        }
        guard let s = surface(e, model) else { return nil }
        var best: Double?
        for face in s.faces {
            let xy = Polygon2(face.map(\.xy))
            guard xy.contains(p), let plane = planeZ(face) else { continue }
            let z = plane.z(at: p)
            best = max(best ?? z, z)
        }
        return best
    }

    public static func ridgeHeight(_ e: Element, _ model: BIMModel) -> Double? {
        if e.roof?.extrusion != nil { return RoofExtrusionGeometry.ridgeHeight(e, model) }
        return surface(e, model)?.faces.flatMap { $0 }.map(\.z).max()
    }
}

/// Queries used when walls attach to roofs and floors.
public enum AttachmentQueries {
    public static func undersideZ(_ host: Element, at p: Vec2, _ model: BIMModel) -> Double? {
        switch host.data {
        case .roof(let r) where r.extrusion != nil:
            return RoofExtrusionGeometry.undersideZ(host, at: p, model)
        case .roof:
            guard let top = RoofGeometry.topZ(host, at: p, model) else { return nil }
            return top - RoofGeometry.thickness(host, model)
        case .slab:
            guard let prof = SlabGeometry.profile(host), prof.contains(p), let (b, _) = SlabGeometry.planes(host, model) else { return nil }
            return b.z(at: p)
        default:
            return nil
        }
    }
}

public enum TopographyGeometry {
    /// Delaunay triangulation (Bowyer–Watson) of the survey points in plan.
    public static func triangulate(_ pts: [Vec3]) -> [Int] {
        guard pts.count >= 3 else { return [] }
        let b = Rect2(points: pts.map(\.xy))
        let d = max(b.width, b.height) * 20 + 1
        let c = b.center
        var verts = pts.map(\.xy)
        let s0 = verts.count
        verts.append(c + Vec2(-d, -d)); verts.append(c + Vec2(d, -d)); verts.append(c + Vec2(0, d))
        var tris: [(Int, Int, Int)] = [(s0, s0 + 1, s0 + 2)]
        func circum(_ t: (Int, Int, Int)) -> (Vec2, Double) {
            let a = verts[t.0], bb = verts[t.1], cc = verts[t.2]
            let dd = 2 * (a.x * (bb.y - cc.y) + bb.x * (cc.y - a.y) + cc.x * (a.y - bb.y))
            if abs(dd) < 1e-18 { return (a, .infinity) }
            let ux = (a.lengthSquared * (bb.y - cc.y) + bb.lengthSquared * (cc.y - a.y) + cc.lengthSquared * (a.y - bb.y)) / dd
            let uy = (a.lengthSquared * (cc.x - bb.x) + bb.lengthSquared * (a.x - cc.x) + cc.lengthSquared * (bb.x - a.x)) / dd
            let ctr = Vec2(ux, uy)
            return (ctr, ctr.distanceSquared(to: a))
        }
        for i in 0..<s0 {
            let p = verts[i]
            var bad: [(Int, Int, Int)] = []
            var keep: [(Int, Int, Int)] = []
            for t in tris {
                let (cc, r2) = circum(t)
                if cc.distanceSquared(to: p) < r2 - 1e-12 { bad.append(t) } else { keep.append(t) }
            }
            var edgeCount: [String: (Int, Int, Int)] = [:]
            var order: [String] = []
            for t in bad {
                for (a, bb) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] {
                    let k = "\(min(a, bb))-\(max(a, bb))"
                    if let e = edgeCount[k] { edgeCount[k] = (e.0, e.1, e.2 + 1) } else { edgeCount[k] = (a, bb, 1); order.append(k) }
                }
            }
            tris = keep
            for k in order { if let e = edgeCount[k], e.2 == 1 { tris.append((e.0, e.1, i)) } }
        }
        var out: [Int] = []
        for t in tris where t.0 < s0 && t.1 < s0 && t.2 < s0 {
            let a = verts[t.0], bb = verts[t.1], cc = verts[t.2]
            if (bb - a).cross(cc - a) > 0 { out += [t.0, t.1, t.2] } else { out += [t.0, t.2, t.1] }
        }
        return out
    }

    public static func mesh(_ e: Element) -> Mesh {
        guard var pts = e.topography?.points, pts.count >= 3 else { return .empty }
        var tri = triangulate(pts)
        if let o = e.topography?.solid?.outline, o.count >= 3, e.topography?.boundary == nil { tri = SiteEditing.clip(triangles: tri, points: pts, to: Polygon2(o)) } // BL-SITE
        if let b = e.topography?.boundary, b.count >= 3 { // W2-DWG: sub-regions keep only triangles inside their boundary
            tri = SiteEditing.clip(triangles: tri, points: pts, to: Polygon2(b))
            pts = pts.map { Vec3($0.xy, z: $0.z + SiteEditing.subregionLift) }
        }
        var m = Mesh(positions: pts, normals: Array(repeating: .unitZ, count: pts.count), indices: tri.map { UInt32($0) }, featureEdges: [])
        // Boundary edges (edges used by one triangle) are feature edges.
        var count: [UInt64: Int] = [:]
        for i in stride(from: 0, to: tri.count, by: 3) {
            for (a, b) in [(tri[i], tri[i + 1]), (tri[i + 1], tri[i + 2]), (tri[i + 2], tri[i])] {
                count[UInt64(min(a, b)) << 32 | UInt64(max(a, b)), default: 0] += 1
            }
        }
        for (k, c) in count.sorted(by: { $0.key < $1.key }) where c == 1 {
            m.featureEdges.append(UInt32(k >> 32)); m.featureEdges.append(UInt32(k & 0xffffffff))
        }
        // Smooth normals.
        var ns = [Vec3](repeating: .zero, count: pts.count)
        for i in stride(from: 0, to: tri.count, by: 3) {
            let n = (pts[tri[i + 1]] - pts[tri[i]]).cross(pts[tri[i + 2]] - pts[tri[i]])
            ns[tri[i]] += n; ns[tri[i + 1]] += n; ns[tri[i + 2]] += n
        }
        m.normals = ns.map { $0.lengthSquared > 0 ? $0.normalized : .unitZ }
        return m
    }

    /// Contour lines at the given interval (marching triangles).
    public static func contours(_ e: Element, interval: Double) -> [(z: Double, segment: Segment2)] {
        guard interval > 0, let pts = e.topography?.points, pts.count >= 3 else { return [] }
        var tri = triangulate(pts)
        if let o = e.topography?.solid?.outline, o.count >= 3 { tri = SiteEditing.clip(triangles: tri, points: pts, to: Polygon2(o)) } // BL-SITE
        let zs = pts.map(\.z)
        guard let lo = zs.min(), let hi = zs.max(), hi - lo < interval * 500 else { return [] }
        var out: [(Double, Segment2)] = []
        var k = (lo / interval).rounded(.up) // W2-DWG: levels as k × interval, so they don't drift (0.1 + 0.2 ≠ 0.3)
        while k * interval <= hi {
            let z = k * interval
            for i in stride(from: 0, to: tri.count, by: 3) {
                let v = [pts[tri[i]], pts[tri[i + 1]], pts[tri[i + 2]]]
                var hits: [Vec2] = []
                // W2-DWG: a vertex exactly at the contour level counts as above it, so contours through survey points at
                // round elevations (0.5, 1.0, …) are drawn instead of vanishing.
                for (a, b) in [(v[0], v[1]), (v[1], v[2]), (v[2], v[0])] where (a.z >= z) != (b.z >= z) {
                    let t = (z - a.z) / (b.z - a.z)
                    hits.append(a.xy.lerp(to: b.xy, t: t))
                }
                if hits.count == 2, hits[0].distanceSquared(to: hits[1]) > 1e-18 { out.append((z, Segment2(hits[0], hits[1]))) }
            }
            k += 1
        }
        return out
    }

    public static func surfaceArea(_ e: Element) -> Double { mesh(e).surfaceArea }
    public static func projectedArea(_ e: Element) -> Double {
        guard let pts = e.topography?.points else { return 0 }
        let tri = triangulate(pts)
        var a = 0.0
        for i in stride(from: 0, to: tri.count, by: 3) {
            a += abs((pts[tri[i + 1]].xy - pts[tri[i]].xy).cross(pts[tri[i + 2]].xy - pts[tri[i]].xy)) / 2
        }
        return a
    }
}
