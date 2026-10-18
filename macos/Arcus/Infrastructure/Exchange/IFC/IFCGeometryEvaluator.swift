import Foundation
import ArcusGeometry
import ArcusDomain

/// Triangle soup in world meters, accumulated while evaluating representation items.
struct TriMesh {
    var positions: [Vec3] = []
    var indices: [UInt32] = []
    /// Polygon boundary edges (pairs of vertex indices) used as feature edges.
    var edges: [UInt32] = []

    var isEmpty: Bool { indices.isEmpty }
    var triangleCount: Int { indices.count / 3 }

    mutating func append(_ o: TriMesh) {
        let base = UInt32(positions.count)
        positions += o.positions
        indices += o.indices.map { $0 + base }
        edges += o.edges.map { $0 + base }
    }

    func transformed(_ t: Transform3) -> TriMesh {
        var m = self
        m.positions = positions.map(t.apply)
        if t.determinant < 0 {
            for i in stride(from: 0, to: m.indices.count, by: 3) { m.indices.swapAt(i + 1, i + 2) }
        }
        return m
    }

    var bounds: Box3 { Box3(points: positions) }

    /// Adds a planar polygon (outer loop + holes) in 3D, triangulated in its plane.
    mutating func addPolygon(_ outer: [Vec3], holes: [[Vec3]] = []) {
        let loop = Self.dedupe(outer)
        guard loop.count >= 3 else { return }
        let n = Self.newell(loop)
        guard n.length > 1e-14 else { return }
        let nz = n.normalized
        let base = UInt32(positions.count)
        if holes.isEmpty && loop.count == 3 {
            positions += loop
            indices += [base, base + 1, base + 2]
            edges += [base, base + 1, base + 1, base + 2, base + 2, base]
            return
        }
        let x = nz.anyPerpendicular.normalized, y = nz.cross(x)
        let o = loop[0]
        func flat(_ p: Vec3) -> Vec2 { Vec2((p - o).dot(x), (p - o).dot(y)) }
        let holes3 = holes.map(Self.dedupe).filter { $0.count >= 3 }
        var lookup: [Vec2: Vec3] = [:]
        for p in loop { lookup[flat(p)] = p }
        for h in holes3 { for p in h { lookup[flat(p)] = p } }
        let outer2 = Polygon2(loop.map(flat))
        if holes3.isEmpty && outer2.isConvex {
            positions += loop
            for i in 1..<(loop.count - 1) { indices += [base, base + UInt32(i), base + UInt32(i + 1)] }
            for i in 0..<loop.count { edges += [base + UInt32(i), base + UInt32((i + 1) % loop.count)] }
            return
        }
        let tri = Triangulator.triangulate(Profile2(outer: outer2.counterClockwise, holes: holes3.map { Polygon2($0.map(flat)).clockwise }))
        guard !tri.triangles.isEmpty else { return }
        let pts = tri.points.map { lookup[$0] ?? (o + x * $0.x + y * $0.y) }
        positions += pts
        // Triangulator output is CCW in the (x, y) frame whose normal is nz: keep that orientation.
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            indices += [base + UInt32(tri.triangles[t]), base + UInt32(tri.triangles[t + 1]), base + UInt32(tri.triangles[t + 2])]
        }
        var k = 0
        for l in [loop] + holes3 {
            let c = min(l.count, pts.count - k)
            for i in 0..<c { edges += [base + UInt32(k + i), base + UInt32(k + (i + 1) % c)] }
            k += c
        }
    }

    static func dedupe(_ pts: [Vec3]) -> [Vec3] {
        var out: [Vec3] = []
        for p in pts where out.last.map({ !$0.isAlmostEqual(p, tolerance: 1e-9) }) ?? true { out.append(p) }
        while out.count > 1, out[0].isAlmostEqual(out[out.count - 1], tolerance: 1e-9) { out.removeLast() }
        return out
    }

    static func newell(_ pts: [Vec3]) -> Vec3 {
        var n = Vec3.zero
        for i in 0..<pts.count {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            n = n + Vec3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
        }
        return n
    }

    /// Converts to an Arcus mesh with flat normals.
    var domainMesh: Mesh {
        var normals = [Vec3](repeating: .unitZ, count: positions.count)
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[i])], b = positions[Int(indices[i + 1])], c = positions[Int(indices[i + 2])]
            let n = (b - a).cross(c - a)
            if n.lengthSquared > 0 {
                let nn = n.normalized
                normals[Int(indices[i])] = nn; normals[Int(indices[i + 1])] = nn; normals[Int(indices[i + 2])] = nn
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices, featureEdges: edges)
    }
}

/// Evaluates IFC placements and body representations into world-space triangle meshes (meters).
final class IFCGeometryEvaluator {
    let file: STEPFile
    /// File length unit in meters (e.g. 0.001 for millimeters).
    let lengthScale: Double
    /// File plane angle unit in radians (1 for radians, π/180 for degrees).
    let angleScale: Double
    private var placementCache: [Int: Transform3] = [:]
    private(set) var unsupported: [String: Int] = [:]
    private(set) var warnings: [String] = []
    /// Set while evaluating a product when a boolean result was approximated by its first operand.
    var approximatedBoolean = false
    /// Maximum triangles per product (hostile-input guard).
    var maxTriangles = 5_000_000

    init(file: STEPFile, lengthScale: Double, angleScale: Double) {
        self.file = file
        self.lengthScale = lengthScale
        self.angleScale = angleScale
    }

    func warn(_ s: String) { if !warnings.contains(s) { warnings.append(s) } }
    func noteUnsupported(_ type: String) { unsupported[IFCClassTable.name(for: type), default: 0] += 1 }

    // MARK: Primitives

    func coords(_ v: STEPValue) -> [Double]? {
        guard let l = v.listValue else { return nil }
        var out: [Double] = []
        for x in l {
            guard let d = x.doubleValue, d.isFinite else { return nil }
            out.append(d)
        }
        return out
    }

    func point3(_ v: STEPValue) -> Vec3? {
        guard let e = file[v], e.type == "IFCCARTESIANPOINT", let c = coords(e[0]), !c.isEmpty else { return nil }
        let s = lengthScale
        return Vec3(c[0] * s, (c.count > 1 ? c[1] : 0) * s, (c.count > 2 ? c[2] : 0) * s)
    }

    func point2(_ v: STEPValue) -> Vec2? { point3(v)?.xy }

    func direction3(_ v: STEPValue) -> Vec3? {
        guard let e = file[v], e.type == "IFCDIRECTION", let c = coords(e[0]), !c.isEmpty else { return nil }
        let d = Vec3(c[0], c.count > 1 ? c[1] : 0, c.count > 2 ? c[2] : 0)
        return d.lengthSquared > 1e-24 ? d.normalized : nil
    }

    func axis2Placement(_ v: STEPValue) -> Transform3 {
        guard let e = file[v] else { return .identity }
        let o = point3(e[0]) ?? .zero
        switch e.type {
        case "IFCAXIS2PLACEMENT3D":
            let z = direction3(e[1]) ?? .unitZ
            var x = direction3(e[2]) ?? (abs(z.dot(.unitX)) < 0.9 ? .unitX : .unitY)
            x = x - z * x.dot(z)
            if x.lengthSquared < 1e-18 { x = z.anyPerpendicular }
            return Transform3.frame(origin: o, xAxis: x.normalized, yAxis: z.cross(x.normalized))
        case "IFCAXIS2PLACEMENT2D":
            var x = direction3(e[1]) ?? .unitX
            x = Vec3(x.x, x.y, 0)
            if x.lengthSquared < 1e-18 { x = .unitX }
            return Transform3.frame(origin: Vec3(o.x, o.y, 0), xAxis: x.normalized, yAxis: Vec3(-x.normalized.y, x.normalized.x, 0))
        case "IFCAXIS1PLACEMENT":
            return .translation(o)
        default:
            return .identity
        }
    }

    /// World transform of an object placement (IfcLocalPlacement chains; cycles and depth guarded).
    func placement(_ v: STEPValue) -> Transform3 {
        guard let id = v.refValue else { return .identity }
        return placement(id, depth: 0)
    }

    private func placement(_ id: Int, depth: Int) -> Transform3 {
        if let c = placementCache[id] { return c }
        guard depth < 64, let e = file[id] else {
            warn("An object placement chain is too deep or cyclic; the placement was ignored.")
            return .identity
        }
        var t = Transform3.identity
        switch e.type {
        case "IFCLOCALPLACEMENT":
            let rel = axis2Placement(e[1])
            if let parent = e[0].refValue {
                placementCache[id] = .identity // cycle guard
                t = placement(parent, depth: depth + 1) * rel
            } else {
                t = rel
            }
        case "IFCGRIDPLACEMENT":
            warn("IfcGridPlacement is not supported; affected elements were placed at the origin.")
        default:
            break
        }
        placementCache[id] = t
        return t
    }

    /// IfcCartesianTransformationOperator (2D/3D, uniform or non-uniform).
    func transformationOperator(_ v: STEPValue) -> Transform3 {
        guard let e = file[v] else { return .identity }
        let is3D = e.type.contains("3D")
        var x = direction3(e[0]) ?? .unitX
        var y = direction3(e[1]) ?? .unitY
        let o = point3(e[2]) ?? .zero
        let s = e[3].doubleValue ?? 1
        var z = is3D ? (direction3(e[4]) ?? .unitZ) : .unitZ
        if !is3D { x = Vec3(x.x, x.y, 0); y = Vec3(-x.y, x.x, 0) }
        z = z.normalized
        x = (x - z * x.dot(z))
        if x.lengthSquared < 1e-18 { x = z.anyPerpendicular }
        x = x.normalized
        y = z.cross(x)
        var sx = s, sy = s, sz = s
        if e.type.contains("NONUNIFORM") {
            sy = (is3D ? e[5] : e[4]).doubleValue ?? s
            if is3D { sz = e[6].doubleValue ?? s }
        }
        if !(sx.isFinite && sy.isFinite && sz.isFinite) || sx == 0 || sy == 0 || sz == 0 { sx = 1; sy = 1; sz = 1 }
        return Transform3.frame(origin: o, xAxis: x, yAxis: y) * Transform3.scale(Vec3(sx, sy, sz))
    }

    // MARK: Representations

    /// Shape representations of a product, as (identifier, type, items).
    func representations(of product: STEPEntity) -> [(id: String, type: String, items: [STEPValue])] {
        guard let pds = file[product[6]] else { return [] }
        return (pds[2].listValue ?? []).compactMap { r in
            guard let rep = file[r] else { return nil }
            return (rep[1].stringValue ?? "", rep[2].stringValue ?? "", rep[3].listValue ?? [])
        }
    }

    /// World-space body mesh of a product (nil when it has no evaluable 3D body).
    func bodyMesh(of product: STEPEntity) -> TriMesh? {
        approximatedBoolean = false
        let reps = representations(of: product)
        let skip: Set<String> = ["Axis", "FootPrint", "Annotation", "Profile", "Reference", "Box", "Lighting", "Clearance", "CoG"]
        var chosen = reps.filter { $0.id == "Body" }
        if chosen.isEmpty { chosen = reps.filter { !skip.contains($0.id) } }
        if chosen.isEmpty { chosen = reps.filter { $0.id == "Box" } }
        guard !chosen.isEmpty else { return nil }
        let world = placement(product[5])
        var mesh = TriMesh()
        for rep in chosen {
            for item in rep.items { evaluate(item, world, depth: 0, into: &mesh) }
        }
        return mesh.isEmpty ? nil : mesh
    }

    /// World-space points of the product's 'Axis' representation (first curve), if any.
    func axisPoints(of product: STEPEntity) -> [Vec3]? {
        guard let rep = representations(of: product).first(where: { $0.id == "Axis" }), let item = rep.items.first else { return nil }
        let world = placement(product[5])
        guard let pts = curvePoints(item, depth: 0), pts.count >= 2 else { return nil }
        return pts.map { world.apply($0) }
    }

    func evaluate(_ v: STEPValue, _ t: Transform3, depth: Int, into mesh: inout TriMesh) {
        guard let e = file[v] else { return }
        guard depth < 24 else { warn("Geometry nesting is too deep; some items were skipped."); return }
        guard mesh.triangleCount < maxTriangles else { warn("An element exceeded \(maxTriangles) triangles; its geometry was truncated."); return }
        switch e.type {
        case "IFCEXTRUDEDAREASOLID":
            guard let prof = profile(e[0], depth: depth + 1) else { noteUnsupported(file[e[0]]?.type ?? "IFCPROFILEDEF"); return }
            let pos = e[1].isNull ? Transform3.identity : axis2Placement(e[1])
            let dir = direction3(e[2]) ?? .unitZ
            guard let depthValue = e[3].doubleValue, depthValue.isFinite, abs(depthValue) < 1e7 else { return }
            let m = extrude(prof, direction: dir, depth: depthValue * lengthScale)
            mesh.append(m.transformed(t * pos))
        case "IFCFACETEDBREP", "IFCFACETEDBREPWITHVOIDS", "IFCMANIFOLDSOLIDBREP":
            evaluate(e[0], t, depth: depth + 1, into: &mesh)
        case "IFCCLOSEDSHELL", "IFCOPENSHELL", "IFCCONNECTEDFACESET":
            var local = TriMesh()
            for f in e[0].listValue ?? [] { face(f, into: &local) }
            mesh.append(local.transformed(t))
        case "IFCSHELLBASEDSURFACEMODEL", "IFCFACEBASEDSURFACEMODEL":
            for s in e[0].listValue ?? [] { evaluate(s, t, depth: depth + 1, into: &mesh) }
        case "IFCTRIANGULATEDFACESET":
            if let m = triangulatedFaceSet(e) { mesh.append(m.transformed(t)) }
        case "IFCPOLYGONALFACESET":
            if let m = polygonalFaceSet(e) { mesh.append(m.transformed(t)) }
        case "IFCMAPPEDITEM":
            guard let map = file[e[0]], let rep = file[map[1]] else { return }
            let origin = axis2Placement(map[0])
            let target = transformationOperator(e[1])
            let tt = t * target * origin
            for item in rep[3].listValue ?? [] { evaluate(item, tt, depth: depth + 1, into: &mesh) }
        case "IFCBOOLEANCLIPPINGRESULT", "IFCBOOLEANRESULT":
            approximatedBoolean = true
            evaluate(e[1], t, depth: depth + 1, into: &mesh)
        case "IFCCSGSOLID":
            evaluate(e[0], t, depth: depth + 1, into: &mesh)
        case "IFCBLOCK":
            let pos = axis2Placement(e[0])
            guard let x = e[1].doubleValue, let y = e[2].doubleValue, let z = e[3].doubleValue, x > 0, y > 0, z > 0, x < 1e7, y < 1e7, z < 1e7 else { return }
            let s = lengthScale
            let prof = Profile2(outer: .rectangle(Rect2(min: .zero, max: Vec2(x * s, y * s))))
            mesh.append(extrude(prof, direction: .unitZ, depth: z * s).transformed(t * pos))
        default:
            noteUnsupported(e.type)
        }
    }

    // MARK: Solids and faces

    func extrude(_ p: Profile2, direction d: Vec3, depth: Double) -> TriMesh {
        var m = TriMesh()
        let v = d * depth
        guard v.length > 1e-9 else { return m }
        let outer = p.outer.counterClockwise
        let holes = p.holes.map(\.clockwise)
        let tri = Triangulator.triangulate(Profile2(outer: outer, holes: holes))
        guard !tri.triangles.isEmpty else { return m }
        let up = v.z >= 0 || abs(v.z) < 1e-12
        let n = UInt32(tri.points.count)
        m.positions = tri.points.map { Vec3($0, z: 0) } + tri.points.map { Vec3($0, z: 0) + v }
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            let a = UInt32(tri.triangles[t]), b = UInt32(tri.triangles[t + 1]), c = UInt32(tri.triangles[t + 2])
            if up { m.indices += [a, c, b, n + a, n + b, n + c] } else { m.indices += [a, b, c, n + a, n + c, n + b] }
        }
        for loop in [outer] + holes {
            let pts = loop.points
            let base = UInt32(m.positions.count)
            for (i, p) in pts.enumerated() {
                let q = pts[(i + 1) % pts.count]
                let k = base + UInt32(i * 4)
                m.positions += [Vec3(p, z: 0), Vec3(q, z: 0), Vec3(q, z: 0) + v, Vec3(p, z: 0) + v]
                if up { m.indices += [k, k + 1, k + 2, k, k + 2, k + 3] } else { m.indices += [k, k + 2, k + 1, k, k + 3, k + 2] }
                m.edges += [k, k + 1, k + 3, k + 2, k, k + 3]
            }
        }
        return m
    }

    func loopPoints(_ v: STEPValue) -> [Vec3]? {
        guard let e = file[v] else { return nil }
        switch e.type {
        case "IFCPOLYLOOP":
            let pts = (e[0].listValue ?? []).compactMap(point3)
            return pts.count >= 3 ? pts : nil
        default:
            noteUnsupported(e.type)
            return nil
        }
    }

    func face(_ v: STEPValue, into m: inout TriMesh) {
        guard let f = file[v] else { return }
        guard f.type == "IFCFACE" || f.type == "IFCFACESURFACE" else { noteUnsupported(f.type); return }
        var outer: [Vec3]?
        var holes: [[Vec3]] = []
        for b in f[0].listValue ?? [] {
            guard let bound = file[b], var pts = loopPoints(bound[0]) else { continue }
            if bound[1].boolValue == false { pts.reverse() }
            if bound.type == "IFCFACEOUTERBOUND" && outer == nil { outer = pts } else { holes.append(pts) }
        }
        if outer == nil, !holes.isEmpty {
            // No explicit outer bound: the largest loop is the outer one.
            let i = holes.indices.max { TriMesh.newell(holes[$0]).length < TriMesh.newell(holes[$1]).length }!
            outer = holes.remove(at: i)
        }
        guard let o = outer else { return }
        m.addPolygon(o, holes: holes)
    }

    /// Reads IfcCartesianPointList3D / 2D coordinates.
    func pointList(_ v: STEPValue) -> [Vec3]? {
        guard let e = file[v], let rows = e[0].listValue else { return nil }
        var out: [Vec3] = []
        out.reserveCapacity(rows.count)
        let s = lengthScale
        for r in rows {
            guard let c = coords(r), c.count >= 2 else { return nil }
            out.append(Vec3(c[0] * s, c[1] * s, (c.count > 2 ? c[2] : 0) * s))
        }
        return out
    }

    private func isIndexList(_ v: STEPValue, width: Int?) -> Bool {
        guard let l = v.listValue, let first = l.first?.listValue else { return false }
        if let width, first.count != width { return false }
        return first.allSatisfy { if case .integer = $0 { return true }; return false }
    }

    func triangulatedFaceSet(_ e: STEPEntity) -> TriMesh? {
        guard let pts = pointList(e[0]) else { return nil }
        // CoordIndex position differs between IFC4 (index 3) and IFC4X3; find the list of integer triples.
        guard let ci = (1..<max(1, e.args.count)).first(where: { isIndexList(e[$0], width: 3) }) else { return nil }
        let pn = e[ci + 1].listValue?.compactMap(\.intValue)
        var m = TriMesh()
        m.positions = pts
        for t in e[ci].listValue ?? [] {
            guard let idx = t.listValue?.compactMap(\.intValue), idx.count == 3 else { continue }
            var ok = true
            let mapped: [UInt32] = idx.map { i in
                var k = i
                if let pn { if i >= 1 && i <= pn.count { k = pn[i - 1] } else { ok = false } }
                if k < 1 || k > pts.count { ok = false; return 0 }
                return UInt32(k - 1)
            }
            if ok { m.indices += mapped }
        }
        return m.isEmpty ? nil : m
    }

    func polygonalFaceSet(_ e: STEPEntity) -> TriMesh? {
        guard let pts = pointList(e[0]) else { return nil }
        let pn = e[3].listValue?.compactMap(\.intValue)
        func resolve(_ l: [STEPValue]) -> [Vec3]? {
            var out: [Vec3] = []
            for v in l {
                guard var k = v.intValue else { return nil }
                if let pn { guard k >= 1 && k <= pn.count else { return nil }; k = pn[k - 1] }
                guard k >= 1 && k <= pts.count else { return nil }
                out.append(pts[k - 1])
            }
            return out
        }
        var m = TriMesh()
        for f in e[2].listValue ?? [] {
            guard let fe = file[f], let outer = fe[0].listValue.flatMap(resolve) else { continue }
            let holes = fe.type == "IFCINDEXEDPOLYGONALFACEWITHVOIDS" ? (fe[1].listValue ?? []).compactMap { $0.listValue.flatMap(resolve) } : []
            m.addPolygon(outer, holes: holes)
        }
        return m.isEmpty ? nil : m
    }

    // MARK: Profiles and curves

    func circle(_ r: Double) -> [Vec2] {
        let n = max(12, min(64, Int((2 * .pi * r / 0.05).rounded())))
        return (0..<n).map { Vec2.fromAngle(2 * .pi * Double($0) / Double(n), length: r) }
    }

    func profile(_ v: STEPValue, depth: Int) -> Profile2? {
        guard let e = file[v], depth < 24 else { return nil }
        let s = lengthScale
        func pos(_ i: Int) -> Transform2 {
            let t = axis2Placement(e[i])
            return Transform2(a: t.xAxis.x, b: t.yAxis.x, c: t.xAxis.y, d: t.yAxis.y, tx: t.origin.x, ty: t.origin.y)
        }
        func valid(_ xs: Double?...) -> [Double]? {
            let vals = xs.compactMap { $0 }
            guard vals.count == xs.count, vals.allSatisfy({ $0.isFinite && $0 > 0 && $0 < 1e7 }) else { return nil }
            return vals.map { $0 * s }
        }
        switch e.type {
        case "IFCRECTANGLEPROFILEDEF":
            guard let d = valid(e[3].doubleValue, e[4].doubleValue) else { return nil }
            return Profile2(outer: .rectangle(Rect2(center: .zero, halfSize: Vec2(d[0] / 2, d[1] / 2)))).transformed(pos(2))
        case "IFCRECTANGLEHOLLOWPROFILEDEF":
            guard let d = valid(e[3].doubleValue, e[4].doubleValue, e[5].doubleValue), d[2] * 2 < min(d[0], d[1]) else { return nil }
            let outer = Polygon2.rectangle(Rect2(center: .zero, halfSize: Vec2(d[0] / 2, d[1] / 2)))
            let inner = Polygon2.rectangle(Rect2(center: .zero, halfSize: Vec2(d[0] / 2 - d[2], d[1] / 2 - d[2])))
            return Profile2(outer: outer, holes: [inner]).transformed(pos(2))
        case "IFCCIRCLEPROFILEDEF":
            guard let d = valid(e[3].doubleValue) else { return nil }
            return Profile2(outer: Polygon2(circle(d[0]))).transformed(pos(2))
        case "IFCCIRCLEHOLLOWPROFILEDEF":
            guard let d = valid(e[3].doubleValue, e[4].doubleValue), d[1] < d[0] else { return nil }
            return Profile2(outer: Polygon2(circle(d[0])), holes: [Polygon2(circle(d[0] - d[1]))]).transformed(pos(2))
        case "IFCISHAPEPROFILEDEF":
            guard let d = valid(e[3].doubleValue, e[4].doubleValue, e[5].doubleValue, e[6].doubleValue) else { return nil }
            let w = d[0] / 2, h = d[1] / 2, tw = d[2] / 2, tf = d[3]
            let pts = [Vec2(-w, -h), Vec2(w, -h), Vec2(w, -h + tf), Vec2(tw, -h + tf), Vec2(tw, h - tf), Vec2(w, h - tf), Vec2(w, h),
                       Vec2(-w, h), Vec2(-w, h - tf), Vec2(-tw, h - tf), Vec2(-tw, -h + tf), Vec2(-w, -h + tf)]
            return Profile2(outer: Polygon2(pts)).transformed(pos(2))
        case "IFCARBITRARYCLOSEDPROFILEDEF", "IFCARBITRARYPROFILEDEFWITHVOIDS":
            guard let outer = curvePoints(e[2], depth: depth + 1).map({ closedLoop($0.map(\.xy)) }), outer.count >= 3 else { return nil }
            var holes: [Polygon2] = []
            if e.type == "IFCARBITRARYPROFILEDEFWITHVOIDS" {
                for c in e[3].listValue ?? [] {
                    if let h = curvePoints(c, depth: depth + 1).map({ closedLoop($0.map(\.xy)) }), h.count >= 3 { holes.append(Polygon2(h)) }
                }
            }
            return Profile2(outer: Polygon2(outer), holes: holes)
        default:
            noteUnsupported(e.type)
            return nil
        }
    }

    func closedLoop(_ pts: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for p in pts where out.last.map({ !$0.isAlmostEqual(p, tolerance: 1e-9) }) ?? true { out.append(p) }
        while out.count > 1, out[0].isAlmostEqual(out[out.count - 1], tolerance: 1e-9) { out.removeLast() }
        return out
    }

    /// Points of a curve (local coordinates of the curve's representation).
    func curvePoints(_ v: STEPValue, depth: Int) -> [Vec3]? {
        guard let e = file[v], depth < 24 else { return nil }
        switch e.type {
        case "IFCPOLYLINE":
            let pts = (e[0].listValue ?? []).compactMap(point3)
            return pts.count >= 2 ? pts : nil
        case "IFCINDEXEDPOLYCURVE":
            guard let pts = pointList(e[0]), !pts.isEmpty else { return nil }
            guard let segs = e[1].listValue, !segs.isEmpty else { return pts }
            var out: [Vec3] = []
            func at(_ i: Int) -> Vec3? { i >= 1 && i <= pts.count ? pts[i - 1] : nil }
            for s in segs {
                guard case .typed(let kind, let args) = s, let idx = args.first?.listValue?.compactMap(\.intValue) else { continue }
                let p = idx.compactMap(at)
                guard p.count == idx.count else { return nil }
                if kind == "IFCARCINDEX", p.count == 3, let arc = Arc2(through: p[0].xy, p[1].xy, p[2].xy) {
                    out += arc.tessellate(chordTolerance: 0.002).map { Vec3($0, z: p[0].z) }
                } else {
                    out += p
                }
            }
            return out.count >= 2 ? out : nil
        case "IFCCOMPOSITECURVE":
            var out: [Vec3] = []
            for s in e[0].listValue ?? [] {
                guard let seg = file[s], var pts = curvePoints(seg[2], depth: depth + 1) else { continue }
                if seg[1].boolValue == false { pts.reverse() }
                for p in pts where out.last.map({ !$0.isAlmostEqual(p, tolerance: 1e-9) }) ?? true { out.append(p) }
            }
            return out.count >= 2 ? out : nil
        case "IFCTRIMMEDCURVE":
            return trimmedCurve(e, depth: depth)
        case "IFCCIRCLE":
            guard let r = e[1].doubleValue, r > 0, r < 1e7 else { return nil }
            let t = axis2Placement(e[0])
            let pts = circle(r * lengthScale).map { t.apply(Vec3($0, z: 0)) }
            return pts + [pts[0]]
        default:
            noteUnsupported(e.type)
            return nil
        }
    }

    private func trimmedCurve(_ e: STEPEntity, depth: Int) -> [Vec3]? {
        guard let basis = file[e[0]] else { return nil }
        func trimPoint(_ v: STEPValue) -> Vec3? { (v.listValue ?? []).lazy.compactMap { self.point3($0) }.first }
        func trimParam(_ v: STEPValue) -> Double? {
            (v.listValue ?? []).lazy.compactMap { x -> Double? in if case .typed(let t, _) = x, t == "IFCPARAMETERVALUE" { return x.doubleValue }; return nil }.first
        }
        let sense = e[3].boolValue ?? true
        switch basis.type {
        case "IFCLINE":
            let p0 = point3(basis[0]) ?? .zero
            var dir = Vec3.unitX
            if let vec = file[basis[1]] { dir = (direction3(vec[0]) ?? .unitX) * ((vec[1].doubleValue ?? 1) * lengthScale) }
            let a = trimPoint(e[1]) ?? trimParam(e[1]).map { p0 + dir * $0 }
            let b = trimPoint(e[2]) ?? trimParam(e[2]).map { p0 + dir * $0 }
            guard let a, let b else { return nil }
            return sense ? [a, b] : [b, a]
        case "IFCCIRCLE":
            guard let r0 = basis[1].doubleValue, r0 > 0, r0 < 1e7 else { return nil }
            let r = r0 * lengthScale
            let t = axis2Placement(basis[0])
            let inv = t.inverse
            func angle(_ v: STEPValue) -> Double? {
                if let p = trimPoint(v) { let l = inv.apply(p); return atan2(l.y, l.x) }
                return trimParam(v).map { $0 * angleScale }
            }
            guard var a0 = angle(e[1]), var a1 = angle(e[2]) else { return nil }
            if !sense { swap(&a0, &a1) }
            var sweep = a1 - a0
            while sweep <= 0 { sweep += 2 * .pi }
            let arc = Arc2(center: .zero, radius: r, startAngle: a0, sweep: sweep)
            var pts = arc.tessellate(chordTolerance: 0.002).map { t.apply(Vec3($0, z: 0)) }
            if !sense { pts.reverse() }
            return pts
        default:
            noteUnsupported(basis.type)
            return nil
        }
    }
}
