import Foundation
import ArcusGeometry

/// Geometry for the non-extrusion family forms (sweep, blend, revolve) and their plan footprints.
public enum FamilyFormGeometry {
    // MARK: Sweep

    /// Plan footprint of a sweep along a plan polyline whose profile spans `uMin…uMax` across the path
    /// (u measured to the left of the path direction). Joints are mitered like the swept solid.
    public static func sweepFootprint(path: [Vec2], uMin: Double, uMax: Double) -> Profile2? {
        var pts: [Vec2] = []
        for p in path where pts.last.map({ !$0.isAlmostEqual(p) }) ?? true { pts.append(p) }
        guard pts.count >= 2, uMax - uMin > Tolerance.length else { return nil }
        let left = offset(pts, uMax), right = offset(pts, uMin)
        let poly = Polygon2(left + right.reversed())
        guard !poly.isDegenerate else { return nil }
        return Profile2(outer: poly)
    }

    /// Offsets a polyline by `u` to the left of its direction with mitered joints (matching `MeshBuilder.sweep`).
    static func offset(_ pts: [Vec2], _ u: Double) -> [Vec2] {
        let m = pts.count
        let dirs = (0..<(m - 1)).map { (pts[$0 + 1] - pts[$0]).normalized }
        return (0..<m).map { j in
            let s = j == 0 ? 0 : j - 1
            let base = pts[j] + dirs[s].perpendicular * u
            guard j > 0, j < m - 1 else { return base }
            let nm = dirs[j - 1] + dirs[j]
            guard nm.length > Tolerance.angle else { return base }
            let n = nm.normalized
            let denom = dirs[j - 1].dot(n)
            guard abs(denom) > Tolerance.angle else { return base }
            let lambda = -(base - pts[j]).dot(n) / denom
            return base + dirs[j - 1] * lambda
        }
    }

    // MARK: Blend

    /// A closed solid lofted from `bottom` (at `z0`) to `top` (at `z1`). Loops with different vertex counts are
    /// matched by arc length, starting from the top vertex whose direction from the centroid best matches the bottom's first vertex.
    public static func blendMesh(bottom: Polygon2, top: Polygon2, z0: Double, z1: Double) -> Mesh {
        let b = bottom.simplified().counterClockwise, t0 = top.simplified().counterClockwise
        guard b.count >= 3, t0.count >= 3, !b.isDegenerate, !t0.isDegenerate, z1 - z0 > Tolerance.length else { return .empty }
        let t = aligned(t0, to: b)
        let fb = fractions(b.points), ft = fractions(t.points)
        var merged = (fb + ft).sorted()
        merged = merged.reduce(into: [Double]()) { acc, f in if acc.last.map({ f - $0 > 1e-9 }) ?? true { acc.append(f) } }
        let ringB = merged.map { sample(b.points, fb, $0) }, ringT = merged.map { sample(t.points, ft, $0) }
        /// Ring indices of the loop's own vertices where the outline creases (vertical feature edges go there).
        func creases(_ loop: Polygon2, _ fs: [Double]) -> Set<Int> {
            var out: Set<Int> = []
            for (i, f) in fs.enumerated() where MeshTools.turn(loop.points, i) > .pi / 8 {
                if let k = merged.firstIndex(where: { abs($0 - f) <= 1e-9 }) { out.insert(k) }
            }
            return out
        }
        let creaseB = creases(b, fb), creaseT = creases(t, ft)
        var w = MeshTools()
        let n = merged.count
        for k in 0..<n {
            let k1 = (k + 1) % n
            let p0 = ringB[k].at(z: z0), p1 = ringB[k1].at(z: z0), q1 = ringT[k1].at(z: z1), q0 = ringT[k].at(z: z1)
            let quadNormal = (p1 - p0).cross(q0 - p0)
            let planar = quadNormal.length > Tolerance.area && abs((q1 - p0).dot(quadNormal.normalized)) <= Tolerance.length
            if planar {
                let base = w.add([p0, p1, q1, q0], normal: quadNormal.normalized)
                w.triangle(base, base + 1, base + 2); w.triangle(base, base + 2, base + 3)
                w.edge(base, base + 1); w.edge(base + 3, base + 2)
                if creaseB.contains(k) || creaseT.contains(k) { w.edge(base, base + 3) }
            } else {
                let n1 = (p1 - p0).cross(q1 - p0), n2 = (q1 - p0).cross(q0 - p0)
                if n1.length > Tolerance.area {
                    let a = w.add([p0, p1, q1], normal: n1.normalized)
                    w.triangle(a, a + 1, a + 2)
                    w.edge(a, a + 1)
                }
                if n2.length > Tolerance.area {
                    let c = w.add([p0, q1, q0], normal: n2.normalized)
                    w.triangle(c, c + 1, c + 2)
                    w.edge(c + 2, c + 1)
                    if creaseB.contains(k) || creaseT.contains(k) { w.edge(c, c + 2) }
                }
            }
        }
        for (loop, z, up) in [(b, z0, false), (t, z1, true)] {
            let tri = Triangulator.triangulate(Profile2(outer: loop))
            let base = w.add(tri.points.map { $0.at(z: z) }, normal: up ? .unitZ : -.unitZ)
            for i in stride(from: 0, to: tri.triangles.count, by: 3) {
                let a = base + UInt32(tri.triangles[i]), bb = base + UInt32(tri.triangles[i + 1]), c = base + UInt32(tri.triangles[i + 2])
                if up { w.triangle(a, bb, c) } else { w.triangle(a, c, bb) }
            }
        }
        return w.mesh
    }

    /// Plan footprint of a blend: the union of both loops and the plan projection of every side face.
    public static func blendFootprint(bottom: Polygon2, top: Polygon2) -> Profile2? {
        let b = bottom.simplified().counterClockwise, t = aligned(top.simplified().counterClockwise, to: b)
        guard b.count >= 3, t.count >= 3 else { return nil }
        let fb = fractions(b.points), ft = fractions(t.points)
        let merged = Array(Set(fb + ft)).sorted()
        let rb = merged.map { sample(b.points, fb, $0) }, rt = merged.map { sample(t.points, ft, $0) }
        var parts = [Profile2(outer: b), Profile2(outer: t)]
        for k in 0..<merged.count {
            let k1 = (k + 1) % merged.count
            let q = Polygon2([rb[k], rb[k1], rt[k1], rt[k]])
            if !q.isDegenerate, q.isSimple { parts.append(Profile2(outer: q)) }
        }
        let union = PolygonBoolean.union(parts)
        return union.max { $0.area < $1.area }
    }

    /// Cumulative arc-length fractions (0 ≤ f < 1) of a closed loop's vertices.
    static func fractions(_ pts: [Vec2]) -> [Double] {
        let n = pts.count
        let lengths = (0..<n).map { pts[$0].distance(to: pts[($0 + 1) % n]) }
        let total = lengths.reduce(0, +)
        guard total > 0 else { return (0..<n).map { Double($0) / Double(n) } }
        var acc = 0.0
        return lengths.map { l in defer { acc += l }; return acc / total }
    }

    /// Point at arc-length fraction `f` along a closed loop with vertex fractions `fs`.
    static func sample(_ pts: [Vec2], _ fs: [Double], _ f: Double) -> Vec2 {
        let n = pts.count
        var i = 0
        while i + 1 < n && fs[i + 1] <= f + 1e-12 { i += 1 }
        let f0 = fs[i], f1 = i + 1 < n ? fs[i + 1] : 1
        let span = f1 - f0
        let local = span > 0 ? (f - f0) / span : 0
        return pts[i].lerp(to: pts[(i + 1) % n], t: max(0, min(1, local)))
    }

    /// Rotates the loop's vertex order so its first vertex points (from the centroid) the most like `ref`'s first vertex.
    static func aligned(_ loop: Polygon2, to ref: Polygon2) -> Polygon2 {
        guard loop.count >= 3, ref.count >= 3 else { return loop }
        let cr = ref.centroid, cl = loop.centroid
        let target = (ref.points[0] - cr).normalized
        let best = loop.points.indices.max { (loop.points[$0] - cl).normalized.dot(target) < (loop.points[$1] - cl).normalized.dot(target) } ?? 0
        return Polygon2(Array(loop.points[best...] + loop.points[..<best]))
    }

    // MARK: Revolve

    /// Plan footprint of a revolve: a full disc or ring, or an annular sector for partial revolves.
    public static func revolveFootprint(axis: Vec2, rMin: Double, rMax: Double, start: Double, sweep: Double) -> Profile2? {
        guard rMax > Tolerance.length, abs(sweep) > Tolerance.angle else { return nil }
        let full = abs(sweep) >= Angle.twoPi - Tolerance.angle
        let segs = max(8, Int((abs(sweep) / Angle.twoPi * 48).rounded(.up)))
        func arc(_ r: Double) -> [Vec2] { (0...segs).map { axis + Vec2.fromAngle(start + sweep * Double($0) / Double(segs), length: r) } }
        if full {
            let outer = Polygon2(Array(arc(rMax).dropLast()))
            let holes = rMin > Tolerance.length ? [Polygon2(Array(arc(rMin).dropLast()))] : []
            return Profile2(outer: outer, holes: holes)
        }
        let inner = rMin > Tolerance.length ? arc(rMin).reversed() : [axis]
        let poly = Polygon2(arc(rMax) + inner)
        return poly.isDegenerate ? nil : Profile2(outer: poly)
    }
}

/// A minimal mesh writer (duplicated vertices per face, flat normals).
struct MeshTools {
    var mesh = Mesh()
    mutating func add(_ pts: [Vec3], normal: Vec3) -> UInt32 {
        let base = UInt32(mesh.positions.count)
        mesh.positions.append(contentsOf: pts)
        mesh.normals.append(contentsOf: repeatElement(normal, count: pts.count))
        return base
    }
    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) { mesh.indices.append(contentsOf: [a, b, c]) }
    mutating func edge(_ a: UInt32, _ b: UInt32) { mesh.featureEdges.append(contentsOf: [a, b]) }
    /// Turn angle (0…π) at vertex i of a closed loop.
    static func turn(_ loop: [Vec2], _ i: Int) -> Double {
        let n = loop.count
        let d0 = (loop[i] - loop[(i + n - 1) % n]).normalized, d1 = (loop[(i + 1) % n] - loop[i]).normalized
        return acos(max(-1, min(1, d0.dot(d1))))
    }
}

/// Solves family reference-plane positions from dimension constraints (labels, locks, EQ).
///
/// Plane offsets are the sketch: the solver finds the positions closest to them (least squares) that satisfy every
/// constraint exactly, with origin-defining planes fixed. Redundant constraints are ignored; conflicting ones are reported.
public enum FamilyConstraintSolver {
    public struct Result: Sendable {
        public var planes: [String: Double]
        /// Measured distance per dimension id (for EQ, the A–B distance).
        public var measured: [String: Double]
        /// Dimension ids that could not be satisfied.
        public var conflicts: Set<String>
        public var errors: [String]
    }

    struct Row { var coefficients: [Int: Double]; var rhs: Double; var dimensionID: String? }

    public static func solve(_ family: FamilyDefinition, sketch: [String: Double], value: (String) -> Double?) -> Result {
        var planes = sketch
        var errors: [String] = []
        var conflicts: Set<String> = []
        let byName = Dictionary(family.referencePlanes.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        var rowsByAxis: [FamilyAxis: [Row]] = [:]
        var unknownsByAxis: [FamilyAxis: [String]] = [:]
        func index(_ name: String, _ axis: FamilyAxis) -> Int {
            if let i = unknownsByAxis[axis, default: []].firstIndex(of: name) { return i }
            unknownsByAxis[axis, default: []].append(name)
            return unknownsByAxis[axis]!.count - 1
        }
        func describe(_ d: FamilyDimension) -> String {
            d.isEquality ? "EQ \(d.planeA) / \(d.planeB) / \(d.planeC ?? "?")" : "\(d.planeA) – \(d.planeB)"
        }
        var dimensionRows: [(FamilyAxis, Row)] = []
        for d in family.dimensions {
            let names = [d.planeA, d.planeB] + (d.isEquality ? [d.planeC ?? ""] : [])
            let missing = names.filter { byName[$0] == nil }
            if !missing.isEmpty {
                errors.append("Dimension \(describe(d)) refers to a missing reference plane “\(missing[0])”.")
                continue
            }
            let axes = Set(names.map { byName[$0]!.axis })
            guard axes.count == 1, let axis = axes.first else {
                errors.append("Dimension \(describe(d)) measures planes that aren't parallel.")
                continue
            }
            let a = sketch[d.planeA] ?? 0, b = sketch[d.planeB] ?? 0
            if d.isEquality {
                let ia = index(d.planeA, axis), ib = index(d.planeB, axis), ic = index(d.planeC!, axis)
                var co: [Int: Double] = [:]
                co[ia, default: 0] += 1; co[ib, default: 0] -= 2; co[ic, default: 0] += 1
                dimensionRows.append((axis, Row(coefficients: co, rhs: 0, dimensionID: d.id)))
            } else if let label = d.labelParameter {
                guard let v = value(label) else {
                    errors.append("Dimension \(describe(d)) is labeled with “\(label)”, which isn't a length parameter.")
                    continue
                }
                let sign: Double = d.direction.map { $0 < 0 ? -1 : 1 } ?? (b - a < 0 ? -1 : 1) // BL-SITE: a fixed direction can't flip when flexing
                let ia = index(d.planeA, axis), ib = index(d.planeB, axis)
                guard ia != ib else { continue }
                dimensionRows.append((axis, Row(coefficients: [ib: 1, ia: -1], rhs: sign * v, dimensionID: d.id)))
            } else if d.isLocked {
                let ia = index(d.planeA, axis), ib = index(d.planeB, axis)
                guard ia != ib else { continue }
                dimensionRows.append((axis, Row(coefficients: [ib: 1, ia: -1], rhs: b - a, dimensionID: d.id)))
            }
        }
        // Origin planes are fixed; they go first so conflicts are blamed on dimensions.
        for (axis, names) in unknownsByAxis {
            for name in names where byName[name]?.definesOrigin == true {
                rowsByAxis[axis, default: []].append(Row(coefficients: [index(name, axis): 1], rhs: sketch[name] ?? 0, dimensionID: nil))
            }
        }
        for (axis, row) in dimensionRows { rowsByAxis[axis, default: []].append(row) }

        for axis in FamilyAxis.allCases {
            guard let rows = rowsByAxis[axis], let names = unknownsByAxis[axis] else { continue }
            let x0 = names.map { sketch[$0] ?? 0 }
            let n = names.count
            // Independent rows (incremental elimination); dependent rows are redundant or conflicting.
            var basis: [(row: [Double], rhs: Double, pivot: Int)] = []
            var kept: [Row] = []
            for r in rows {
                var a = [Double](repeating: 0, count: n)
                for (i, c) in r.coefficients { a[i] += c }
                let residual = r.rhs - zip(a, x0).reduce(0) { $0 + $1.0 * $1.1 }
                var red = a, rr = residual
                for bRow in basis where red[bRow.pivot] != 0 {
                    let f = red[bRow.pivot] / bRow.row[bRow.pivot]
                    for i in 0..<n { red[i] -= f * bRow.row[i] }
                    rr -= f * bRow.rhs
                }
                let scale = max(1, a.map(abs).max() ?? 1)
                guard let p = red.indices.max(by: { abs(red[$0]) < abs(red[$1]) }), abs(red[p]) > 1e-9 * scale else {
                    if abs(rr) > 1e-7, let id = r.dimensionID {
                        conflicts.insert(id)
                        if let d = family.dimensions.first(where: { $0.id == id }) {
                            errors.append("Dimension \(describe(d)) conflicts with other constraints and can't be satisfied.")
                        }
                    }
                    continue
                }
                basis.append((red, rr, p))
                kept.append(r)
            }
            guard !kept.isEmpty else { continue }
            // Minimum-norm correction δ with A δ = b − A x0: solve (A Aᵀ) y = r, δ = Aᵀ y.
            let m = kept.count
            let A: [[Double]] = kept.map { r in
                var a = [Double](repeating: 0, count: n)
                for (i, c) in r.coefficients { a[i] += c }
                return a
            }
            let r = kept.indices.map { k in kept[k].rhs - zip(A[k], x0).reduce(0) { $0 + $1.0 * $1.1 } }
            var M = (0..<m).map { i in (0..<m).map { j in zip(A[i], A[j]).reduce(0) { $0 + $1.0 * $1.1 } } }
            guard let y = gaussSolve(&M, r) else { errors.append("The \(axis.rawValue) dimensions could not be solved."); continue }
            for i in 0..<n {
                var delta = 0.0
                for k in 0..<m { delta += A[k][i] * y[k] }
                planes[names[i]] = x0[i] + delta
            }
        }
        var measured: [String: Double] = [:]
        for d in family.dimensions {
            guard let a = planes[d.planeA], let b = planes[d.planeB] else { continue }
            measured[d.id] = abs(b - a)
        }
        return Result(planes: planes, measured: measured, conflicts: conflicts, errors: errors)
    }

    /// Solves a small dense square system with partial pivoting; nil when singular.
    static func gaussSolve(_ M: inout [[Double]], _ rhs: [Double]) -> [Double]? {
        let n = rhs.count
        var b = rhs
        for col in 0..<n {
            guard let p = (col..<n).max(by: { abs(M[$0][col]) < abs(M[$1][col]) }), abs(M[p][col]) > 1e-12 else { return nil }
            if p != col { M.swapAt(p, col); b.swapAt(p, col) }
            for r in (col + 1)..<n where M[r][col] != 0 {
                let f = M[r][col] / M[col][col]
                for c in col..<n { M[r][c] -= f * M[col][c] }
                b[r] -= f * b[col]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for r in stride(from: n - 1, through: 0, by: -1) {
            var s = b[r]
            for c in (r + 1)..<n { s -= M[r][c] * x[c] }
            x[r] = s / M[r][r]
        }
        return x
    }
}
