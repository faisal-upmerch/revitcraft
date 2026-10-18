import Foundation
import ArcusGeometry
import ArcusDomain

/// Geometry helpers shared by the reader, converter and writer.
enum CADGeometry {
    /// Arc for a polyline segment with a bulge (tan(sweep/4)); nil for a straight or degenerate segment.
    static func bulgeArc(_ p0: Vec2, _ p1: Vec2, _ bulge: Double) -> Arc2? {
        guard bulge != 0, bulge.isFinite else { return nil }
        let d = p1 - p0
        let chord = d.length
        guard chord > 0, chord.isFinite else { return nil }
        let s = chord / 2
        let left = d.perpendicular / chord
        let center = p0.midpoint(p1) + left * (s * (1 - bulge * bulge) / (2 * bulge))
        let radius = s * (1 + bulge * bulge) / (2 * abs(bulge))
        let sweep = 4 * atan(bulge)
        guard radius.isFinite, center.x.isFinite, center.y.isFinite else { return nil }
        return Arc2(center: center, radius: radius, startAngle: (p0 - center).angle, sweep: sweep)
    }

    /// Bulge for an arc segment (inverse of `bulgeArc`).
    static func bulge(forSweep sweep: Double) -> Double { tan(sweep / 4) }

    /// Chord tolerance for tessellating a curve of the given size (same units as the size).
    static func chordTolerance(forSize size: Double) -> Double {
        let s = abs(size)
        guard s.isFinite, s > 0 else { return 1e-3 }
        return max(s * 2e-3, s * 1e-6)
    }

    /// Whether the transform is a similarity (rotation/mirror + uniform scale).
    static func isSimilarity(_ t: Transform2) -> Bool {
        let c1 = Vec2(t.a, t.c), c2 = Vec2(t.b, t.d)
        let l1 = c1.length, l2 = c2.length
        guard l1 > 0, l2 > 0 else { return false }
        return abs(l1 - l2) <= 1e-9 * max(l1, l2) && abs(c1.dot(c2)) <= 1e-9 * l1 * l2
    }

    /// Maps a counter-clockwise arc through an affine transform. Returns an arc for similarity transforms, else an ellipse.
    static func mapArc(center: Vec2, radius: Double, start: Double, end: Double, _ t: Transform2) -> (arc: (Vec2, Double, Double, Double)?, ellipse: Ellipse2?) {
        if t == .identity { return ((center, radius, start, end), nil) }
        if isSimilarity(t) {
            let c = t.apply(center)
            let r = radius * t.uniformScale
            let s = t.applyVector(Vec2.fromAngle(start)).angle
            let e = t.applyVector(Vec2.fromAngle(end)).angle
            // A mirror reverses the traversal: ccw from s to e becomes ccw from e' to s'.
            return t.isMirroring ? ((c, r, e, s), nil) : ((c, r, s, e), nil)
        }
        let el = Ellipse2(center: center, majorAxis: Vec2(radius, 0), ratio: 1, startParam: start, endParam: end).transformed(t)
        return (nil, el)
    }

    /// Positive counter-clockwise sweep from start to end in (0, 2π] (equal angles → full circle).
    static func ccwSweep(_ start: Double, _ end: Double) -> Double {
        let s = Angle.normalize(end - start)
        return s <= 1e-12 ? Angle.twoPi : s
    }

    /// Transform from an entity's Object Coordinate System to WCS, projected to XY (arbitrary axis algorithm).
    /// Returns nil for the default extrusion (0,0,1).
    static func ocsTransform(_ n: Vec3, elevation: Double = 0) -> Transform2? {
        guard n.x.isFinite, n.y.isFinite, n.z.isFinite else { return nil }
        let len = n.length
        guard len > 1e-12 else { return nil }
        let nn = n / len
        if abs(nn.x) < 1e-12 && abs(nn.y) < 1e-12 && nn.z > 0 { return nil }
        let ax: Vec3
        if abs(nn.x) < 1.0 / 64.0 && abs(nn.y) < 1.0 / 64.0 { ax = Vec3.unitY.cross(nn).normalized } else { ax = Vec3.unitZ.cross(nn).normalized }
        let ay = nn.cross(ax).normalized
        return Transform2(a: ax.x, b: ay.x, c: ax.y, d: ay.y, tx: elevation * nn.x, ty: elevation * nn.y)
    }

    /// Tessellates a polyline with bulges into points (arcs sampled).
    static func tessellate(points: [Vec2], bulges: [Double], closed: Bool, chord: Double? = nil) -> [Vec2] {
        guard points.count > 1 else { return points }
        var out: [Vec2] = [points[0]]
        let n = points.count
        let segs = closed ? n : n - 1
        for i in 0..<segs {
            let a = points[i], b = points[(i + 1) % n]
            let bu = i < bulges.count ? bulges[i] : 0
            if let arc = bulgeArc(a, b, bu) {
                let tol = chord ?? chordTolerance(forSize: arc.radius)
                out.append(contentsOf: arc.tessellate(chordTolerance: tol, maxSegments: 128).dropFirst())
            } else {
                out.append(b)
            }
        }
        if closed, out.count > 1, out[out.count - 1].isAlmostEqual(out[0], tolerance: 0) { out.removeLast() }
        return out
    }

    /// Points of a hatch edge in traversal order.
    static func tessellate(_ e: CADHatchEdge) -> [Vec2] {
        switch e {
        case .line(let a, let b): return [a, b]
        case .arc(let c, let r, let s, let en, let ccw):
            let sweep = ccw ? ccwSweep(s, en) : -ccwSweep(en, s)
            let arc = Arc2(center: c, radius: r, startAngle: s, sweep: sweep)
            return arc.tessellate(chordTolerance: chordTolerance(forSize: r), maxSegments: 128)
        case .ellipse(let el, _):
            // Clockwise edges were normalized to the equivalent counter-clockwise parameter range when read.
            return el.tessellate(chordTolerance: chordTolerance(forSize: el.majorAxis.length))
        case .spline(let s):
            let size = max(s.controlBounds.width, s.controlBounds.height)
            return s.tessellate(chordTolerance: chordTolerance(forSize: size))
        case .polyline(let pts, let bulges, let closed):
            var out = tessellate(points: pts, bulges: bulges, closed: closed)
            if closed, let f = out.first { out.append(f) }
            return out
        }
    }

    /// Joins hatch edges into one closed point loop.
    static func loopPoints(_ edges: [CADHatchEdge]) -> [Vec2] {
        var out: [Vec2] = []
        for e in edges {
            var pts = tessellate(e)
            guard !pts.isEmpty else { continue }
            if let last = out.last {
                // Edges may be stored in either direction; orient each to continue from the previous end.
                if let f = pts.first, let l = pts.last, l.distanceSquared(to: last) < f.distanceSquared(to: last) { pts.reverse() }
                if let f = pts.first, f.isAlmostEqual(last, tolerance: 1e-9 * max(1, abs(f.x) + abs(f.y))) { pts.removeFirst() }
            }
            out.append(contentsOf: pts)
        }
        if out.count > 1, out[0].isAlmostEqual(out[out.count - 1], tolerance: 1e-9 * max(1, abs(out[0].x) + abs(out[0].y))) { out.removeLast() }
        return out
    }

    static func isFinite(_ r: Rect2) -> Bool {
        !r.isEmpty && r.min.x.isFinite && r.min.y.isFinite && r.max.x.isFinite && r.max.y.isFinite
    }

    static func textWidth(_ s: String, height: Double, widthFactor: Double = 1) -> Double {
        let longest = s.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
        return height * 0.6 * Double(max(1, longest)) * (widthFactor > 0 ? widthFactor : 1)
    }

    /// Rotated text box corners (drawing units).
    static func textBox(position: Vec2, width: Double, height: Double, rotation: Double, below: Double = 0) -> [Vec2] {
        let u = Vec2.fromAngle(rotation), v = u.perpendicular
        let p0 = position - v * below
        return [p0, p0 + u * width, p0 + u * width + v * (height + below), p0 + v * (height + below)]
    }
}

/// Drawing-unit bounds of CAD entities, with memoized block bounds and cycle protection.
struct CADBoundsCalculator {
    let doc: CADDocument
    let maxDepth: Int
    private var memo: [String: Rect2] = [:]
    private var visiting: Set<String> = []
    private var upperNames: [String: String] = [:]

    init(doc: CADDocument, maxDepth: Int) {
        self.doc = doc; self.maxDepth = maxDepth
        for k in doc.blocks.keys { upperNames[k.uppercased()] = k }
    }

    func resolveName(_ n: String) -> String? {
        if doc.blocks[n] != nil { return n }
        return upperNames[n.uppercased()]
    }

    /// Bounds of a block's content (block coordinates). Computed with an explicit stack (post-order over the block graph),
    /// so deep or cyclic nesting cannot exhaust the call stack; cyclic and too-deep references contribute nothing.
    mutating func blockBounds(_ name: String, depth: Int) -> Rect2 {
        guard let root = resolveName(name) else { return .empty }
        if let m = memo[root] { return m }
        var stack: [(key: String, expanded: Bool)] = [(root, false)]
        var onStack: Set<String> = [root]
        while let top = stack.last {
            if !top.expanded {
                stack[stack.count - 1].expanded = true
                guard stack.count < maxDepth, let b = doc.blocks[top.key] else { continue }
                for child in CADBoundsCalculator.children(of: b) {
                    guard let ck = resolveName(child), memo[ck] == nil, !onStack.contains(ck) else { continue }
                    stack.append((ck, false))
                    onStack.insert(ck)
                }
            } else {
                stack.removeLast()
                onStack.remove(top.key)
                var r = Rect2.empty
                if let b = doc.blocks[top.key] {
                    visiting.insert(top.key)
                    for e in b.entities { r.include(bounds(e, depth: depth + 1)) }
                    visiting.remove(top.key)
                }
                memo[top.key] = r
            }
        }
        return memo[root] ?? .empty
    }

    static func children(of b: CADBlock) -> [String] {
        var out: [String] = []
        for e in b.entities {
            switch e {
            case .insert(let i, _): out.append(i.blockName)
            case .dimension(let d, _): out.append(d.blockName)
            default: break
            }
        }
        return out
    }

    mutating func bounds(_ e: CADEntity, depth: Int = 0) -> Rect2 {
        switch e {
        case .line(let a, let b, _): return Rect2(points: [a.xy, b.xy])
        case .polyline(let p, _):
            if p.hasBulges { return Rect2(points: CADGeometry.tessellate(points: p.points2D, bulges: p.bulges, closed: p.closed)) }
            return Rect2(points: p.points2D)
        case .arc(let c, let r, let s, let en, _):
            return Arc2(center: c, radius: r, startAngle: s, sweep: CADGeometry.ccwSweep(s, en)).bounds
        case .circle(let c, let r, _): return Rect2(min: c - Vec2(r, r), max: c + Vec2(r, r))
        case .ellipse(let el, _): return el.bounds
        case .spline(let s, let fit, _, _):
            if let s, s.isValid { return s.controlBounds }
            return Rect2(points: fit)
        case .point(let p, _): return Rect2(points: [p.xy])
        case .text(let t, _):
            let w = CADGeometry.textWidth(t.text, height: t.height, widthFactor: t.widthFactor)
            return Rect2(points: CADGeometry.textBox(position: t.alignmentPoint ?? t.position, width: w, height: t.height, rotation: t.rotation))
        case .attributeDefinition: return .empty
        case .mtext(let m, _):
            let lines = max(1, m.plainText.split(separator: "\n", omittingEmptySubsequences: false).count)
            let w = m.width > 0 ? m.width : CADGeometry.textWidth(m.plainText, height: m.height)
            let h = m.height * (1 + Double(lines - 1) * 1.667 * max(0.25, m.lineSpacingFactor))
            return Rect2(points: CADGeometry.textBox(position: m.position, width: w, height: h, rotation: m.rotation, below: h))
        case .hatch(let h, _):
            var r = Rect2.empty
            for loop in h.loops { for edge in loop { r.include(Rect2(points: CADGeometry.tessellate(edge))) } }
            return r
        case .solid(let pts, _): return Rect2(points: pts)
        case .insert(let ins, _):
            guard let key = resolveName(ins.blockName), let b = doc.blocks[key] else { return Rect2(points: [ins.position]) }
            let bb = visiting.isEmpty ? blockBounds(key, depth: depth) : (memo[key] ?? .empty)
            var r = Rect2(points: [ins.position])
            guard !bb.isEmpty else { return r }
            let cols = max(1, ins.columns), rows = max(1, ins.rows)
            // Array extents: corner cells suffice (affine).
            for c in Set([0, cols - 1]) {
                for row in Set([0, rows - 1]) {
                    let t = ins.transform(basePoint: b.basePoint, column: c, row: row)
                    for p in bb.corners { r.include(t.apply(p)) }
                }
            }
            for a in ins.attributes where !a.isInvisible {
                r.include(bounds(.text(a.text, CADEntityProps()), depth: depth))
            }
            return r
        case .dimension(let d, _):
            var r = Rect2(points: [d.definitionPoint, d.textMidpoint])
            if let key = resolveName(d.blockName) { r.include(visiting.isEmpty ? blockBounds(key, depth: depth) : (memo[key] ?? .empty)) }
            return r
        case .leader(let pts, _, _): return Rect2(points: pts)
        case .multileader(let m, _):
            var r = Rect2(points: m.leaderLines.flatMap { $0 })
            if let p = m.textPosition { r.include(p) }
            return r
        case .image(_, let c, _): return Rect2(points: c)
        case .face3D(let pts, _): return Rect2(points: pts.map(\.xy))
        case .proxy(_, let b, _): return b ?? .empty
        case .unsupported: return .empty
        }
    }

    mutating func bounds(of entities: [CADEntity]) -> Rect2 {
        var r = Rect2.empty
        for e in entities {
            let b = bounds(e)
            if CADGeometry.isFinite(b) { r.include(b) }
        }
        return r
    }
}
