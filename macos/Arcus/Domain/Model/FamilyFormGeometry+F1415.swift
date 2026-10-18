import Foundation
import ArcusGeometry

// F1415: geometry of the forms the Family Editor gained from RevitCraft (`crates/rc-core/src/family_def.rs` `form_mesh`):
// extrusions sketched on elevation planes, swept blends, model text, and void cuts of any form by any form.

extension FamilyFormGeometry {
    /// An extrusion of `profile` sketched on `plane` (u, v), between depths `w0` and `w1` along the plane's normal.
    public static func planeExtrusion(_ profile: Profile2, plane: FamilySketchPlane, w0: Double, w1: Double) -> Mesh {
        MeshBuilder.extrude(profile, bottom: w0, top: w1).transformed(plane.transform)
    }

    /// The plan footprint of a mesh's bounding box (for forms whose plan shadow is a rectangle: extrusions on elevation
    /// planes, upright text).
    public static func boxFootprint(_ mesh: Mesh) -> Profile2? {
        let b = mesh.bounds.xy
        guard !b.isEmpty, b.width > Tolerance.length, b.height > Tolerance.length else { return nil }
        return Profile2(outer: .rectangle(b))
    }

    /// A swept blend: a closed profile carried along a plan path at height `z0` that changes from `start` (at the path's
    /// start) to `end` (at its end) in proportion to the arc length travelled. Profiles are (x = left of the path, y = up),
    /// matched vertex to vertex by arc length like a blend's loops; joints are mitred like a sweep's.
    public static func sweptBlendMesh(path: [Vec2], z0: Double, start: Polygon2, end: Polygon2) -> Mesh {
        var pts: [Vec2] = []
        for p in path where pts.last.map({ !$0.isAlmostEqual(p) }) ?? true { pts.append(p) }
        let a = start.simplified().counterClockwise, b0 = end.simplified().counterClockwise
        guard pts.count >= 2, a.count >= 3, b0.count >= 3, !a.isDegenerate, !b0.isDegenerate else { return .empty }
        let b = aligned(b0, to: a)
        let fa = fractions(a.points), fb = fractions(b.points)
        var merged = (fa + fb).sorted()
        merged = merged.reduce(into: [Double]()) { acc, f in if acc.last.map({ f - $0 > 1e-9 }) ?? true { acc.append(f) } }
        let ra = merged.map { sample(a.points, fa, $0) }, rb = merged.map { sample(b.points, fb, $0) }
        let m = pts.count, n = merged.count
        let dirs = (0..<(m - 1)).map { (pts[$0 + 1] - pts[$0]).normalized }
        var travelled = [0.0]
        for i in 1..<m { travelled.append(travelled[i - 1] + pts[i].distance(to: pts[i - 1])) }
        let total = max(travelled[m - 1], Tolerance.length)
        /// Profile point q at joint j, on the joint's mitre plane (the incoming segment's frame).
        func ringPoint(_ j: Int, _ q: Vec2) -> Vec3 {
            let s = j == 0 ? 0 : j - 1
            let left = dirs[s].perpendicular
            var base2 = pts[j] + left * q.x
            if j > 0, j < m - 1 {
                let nm = dirs[j - 1] + dirs[j]
                if nm.length > Tolerance.angle {
                    let nrm = nm.normalized
                    let denom = dirs[j - 1].dot(nrm)
                    if abs(denom) > Tolerance.angle { base2 = base2 + dirs[j - 1] * (-(base2 - pts[j]).dot(nrm) / denom) }
                }
            }
            return Vec3(base2.x, base2.y, z0 + q.y)
        }
        let rings: [[Vec3]] = (0..<m).map { j in
            let t = travelled[j] / total
            return (0..<n).map { ringPoint(j, ra[$0].lerp(to: rb[$0], t: t)) }
        }
        /// Ring positions where either profile creases (lengthwise feature edges go there).
        var creases: Set<Int> = []
        for (loop, fs) in [(a, fa), (b, fb)] {
            for (i, f) in fs.enumerated() where MeshTools.turn(loop.points, i) > .pi / 8 {
                if let k = merged.firstIndex(where: { abs($0 - f) <= 1e-9 }) { creases.insert(k) }
            }
        }
        var w = MeshTools()
        for s in 0..<(m - 1) {
            let left = Vec3(dirs[s].perpendicular.x, dirs[s].perpendicular.y, 0)
            let t = (travelled[s] + travelled[s + 1]) / 2 / total
            for k in 0..<n {
                let k1 = (k + 1) % n
                let e = ra[k1].lerp(to: rb[k1], t: t) - ra[k].lerp(to: rb[k], t: t)
                let out = left * e.y + Vec3(0, 0, -e.x) // outward for a counterclockwise profile
                let p0 = rings[s][k], p1 = rings[s][k1], q1 = rings[s + 1][k1], q0 = rings[s + 1][k]
                for tri in [[p0, p1, q1], [p0, q1, q0]] {
                    var t3 = tri
                    var nrm = (t3[1] - t3[0]).cross(t3[2] - t3[0])
                    guard nrm.length > Tolerance.area * 1e-3 else { continue }
                    if nrm.dot(out) < 0 { t3 = [t3[0], t3[2], t3[1]]; nrm = -nrm }
                    let base = w.add(t3, normal: nrm.normalized)
                    w.triangle(base, base + 1, base + 2)
                }
                // Outline of the end rings, lengthwise creases, and the rings at path corners.
                let edgeBase = w.add([p0, p1, q0, q1], normal: out.normalized)
                if s == 0 { w.edge(edgeBase, edgeBase + 1) }
                if s == m - 2 { w.edge(edgeBase + 2, edgeBase + 3) }
                if creases.contains(k) { w.edge(edgeBase, edgeBase + 2) }
                if s > 0 && acos(max(-1, min(1, dirs[s - 1].dot(dirs[s])))) > .pi / 8 { w.edge(edgeBase, edgeBase + 1) }
            }
        }
        // End caps: the start and end profiles themselves.
        for (loop, j, normal, flip) in [(a, 0, -dirs[0], true), (b, m - 1, dirs[m - 2], false)] {
            let tri = Triangulator.triangulate(Profile2(outer: loop))
            let base = w.add(tri.points.map { ringPoint(j, $0) }, normal: Vec3(normal.x, normal.y, 0))
            for i in stride(from: 0, to: tri.triangles.count, by: 3) {
                let p = base + UInt32(tri.triangles[i]), q = base + UInt32(tri.triangles[i + 1]), r = base + UInt32(tri.triangles[i + 2])
                if flip { w.triangle(p, r, q) } else { w.triangle(p, q, r) }
            }
        }
        // The positions added only for edges carry no triangles; fix orientation globally if the profile ran the other way.
        var mesh = w.mesh
        if mesh.signedVolume < 0 {
            for i in stride(from: 0, to: mesh.indices.count, by: 3) { mesh.indices.swapAt(i + 1, i + 2) }
            mesh.normals = mesh.normals.map { -$0 }
        }
        return mesh
    }

    /// Model text glyph outlines as extrusion profiles in sketch coordinates (u, v), the first baseline's left end at
    /// `origin`.
    public static func textProfiles(_ t: FamilyModelText, origin: Vec2) -> [Profile2] {
        let contours = ModelTextGeometry.localContours(t.glyphData).map { $0.map { origin + $0 } }
        return ModelTextGeometry.shapes(contours)
    }

    /// `solid` minus `void` as meshes (any forms). nil when the void doesn't reach the solid; an empty mesh when it
    /// removes all of it.
    public static func subtract(_ solid: Mesh, _ void: Mesh) -> Mesh? {
        let a = MeshCSG(mesh: solid), b = MeshCSG(mesh: void)
        guard a.bounds.intersects(b.bounds) else { return nil }
        let before = a.volume
        let r = a.subtracting(b)
        let after = r.volume
        guard abs(before - after) > max(1e-12, abs(before) * 1e-9) else { return nil }
        return after <= max(1e-12, abs(before) * 1e-9) ? .empty : r.mesh()
    }
}
