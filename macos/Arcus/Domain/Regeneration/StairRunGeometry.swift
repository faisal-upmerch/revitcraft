import Foundation
import ArcusGeometry

// STAIR: plan geometry of one stair run, independent of heights: the tread cells in walking order, the run's left and
// right boundaries (with the walk distance of each point, for heights along the edge), its walk line and its start and
// end edges. `StairGeometry.layout` adds the heights.

/// One tread cell of a run in plan.
struct StairCell {
    var polygon: Polygon2
    /// Front (lower) and back edges, each from the run's left boundary to its right.
    var front: Segment2
    var back: Segment2
    /// Walk distance from the run's start edge to the front edge, and to the back edge.
    var station: Double
    var backStation: Double
    var walkPoint: Vec2
    var walkDirection: Vec2
    var isWinder = false
}

/// A point of a run boundary with its walk distance.
struct StairEdgePoint {
    var point: Vec2
    var station: Double
}

/// The plan shape of a run.
struct StairRunShapeGeometry {
    var cells: [StairCell]
    var left: [StairEdgePoint]
    var right: [StairEdgePoint]
    var walk: [Vec2]
    var walkStations: [Double]
    var startEdge: Segment2
    var endEdge: Segment2
    var startDirection: Vec2
    var endDirection: Vec2
    var walkLength: Double { walkStations.last ?? 0 }
}

enum StairRunGeometry {
    /// The plan shape of `run` with `treads` tread cells of depth `tread` along the walk line. Sketched runs take their
    /// cells from their riser lines. nil when the run can't be built (a spiral narrower than its width, a sketch
    /// without two risers and a path).
    static func shape(_ run: StairRun, treads: Int, tread: Double) -> StairRunShapeGeometry? {
        switch run.shape {
        case .straight: return straight(run, treads: treads, tread: tread)
        case .spiral: return spiral(run, treads: treads, tread: tread)
        case .lWinder, .uWinder: return winder(run, treads: treads, tread: tread)
        case .sketch: return sketch(run)
        }
    }

    /// Straight run: rectangular treads along the run direction.
    static func straight(_ run: StairRun, treads: Int, tread: Double) -> StairRunShapeGeometry {
        let d = run.directionVector, n = d.perpendicular, hw = run.width / 2, c0 = run.start
        let length = Double(treads) * tread
        var cells: [StairCell] = []
        for k in 0..<treads {
            let a = Double(k) * tread, b = a + tread
            let f = Segment2(c0 + d * a + n * hw, c0 + d * a - n * hw)
            let bk = Segment2(c0 + d * b + n * hw, c0 + d * b - n * hw)
            cells.append(StairCell(polygon: Polygon2([f.start, f.end, bk.end, bk.start]).counterClockwise, front: f, back: bk,
                                   station: a, backStation: b, walkPoint: c0 + d * ((a + b) / 2), walkDirection: d))
        }
        let end = c0 + d * length
        return StairRunShapeGeometry(cells: cells,
                                     left: [StairEdgePoint(point: c0 + n * hw, station: 0), StairEdgePoint(point: end + n * hw, station: length)],
                                     right: [StairEdgePoint(point: c0 - n * hw, station: 0), StairEdgePoint(point: end - n * hw, station: length)],
                                     walk: [c0, end], walkStations: [0, length],
                                     startEdge: Segment2(c0 + n * hw, c0 - n * hw), endEdge: Segment2(end + n * hw, end - n * hw),
                                     startDirection: d, endDirection: d)
    }

    /// Spiral run: treads are sectors of the ring around `center`; the walk line is the centre arc (radius = distance
    /// from the centre to `start`).
    static func spiral(_ run: StairRun, treads: Int, tread: Double) -> StairRunShapeGeometry? {
        guard let c = run.center else { return nil }
        let r = run.start.distance(to: c), hw = run.width / 2
        guard r > hw + 0.05 else { return nil }
        let sigma: Double = run.turnsLeft ?? true ? 1 : -1
        let a0 = (run.start - c).angle
        func angle(_ s: Double) -> Double { a0 + sigma * s / r }
        func at(_ s: Double, _ radius: Double) -> Vec2 { c + Vec2.fromAngle(angle(s), length: radius) }
        func dir(_ s: Double) -> Vec2 { Vec2.fromAngle(angle(s)).perpendicular * sigma }
        // Left of travel is toward the centre when the spiral turns left.
        let rl = r - sigma * hw, rr = r + sigma * hw
        let steps = 4
        var cells: [StairCell] = []
        var left: [StairEdgePoint] = [], right: [StairEdgePoint] = [], walk: [Vec2] = [], stations: [Double] = []
        for k in 0..<treads {
            let a = Double(k) * tread, b = a + tread
            var lpts: [Vec2] = [], rpts: [Vec2] = []
            for i in 0...steps {
                let s = a + (b - a) * Double(i) / Double(steps)
                lpts.append(at(s, rl)); rpts.append(at(s, rr))
                if i < steps || k == treads - 1 {
                    left.append(StairEdgePoint(point: at(s, rl), station: s))
                    right.append(StairEdgePoint(point: at(s, rr), station: s))
                    walk.append(at(s, r)); stations.append(s)
                }
            }
            let poly = Polygon2(lpts + rpts.reversed()).counterClockwise
            cells.append(StairCell(polygon: poly, front: Segment2(at(a, rl), at(a, rr)), back: Segment2(at(b, rl), at(b, rr)),
                                   station: a, backStation: b, walkPoint: at((a + b) / 2, r), walkDirection: dir((a + b) / 2)))
        }
        if treads == 0 {
            left = [StairEdgePoint(point: at(0, rl), station: 0)]; right = [StairEdgePoint(point: at(0, rr), station: 0)]
            walk = [at(0, r)]; stations = [0]
        }
        let length = Double(treads) * tread
        return StairRunShapeGeometry(cells: cells, left: left, right: right, walk: walk, walkStations: stations,
                                     startEdge: Segment2(at(0, rl), at(0, rr)), endEdge: Segment2(at(length, rl), at(length, rr)),
                                     startDirection: dir(0), endDirection: dir(length))
    }

    /// Straight treads per leg of a winder run: the legs before the last as stored, the last leg the rest.
    static func legs(_ run: StairRun, treads: Int) -> [Int] {
        let corners = run.corners, k = run.winders
        let straight = max(0, treads - corners * k)
        var legs = Array((run.legTreads ?? []).prefix(corners))
        while legs.count < corners { legs.append(corners == 1 ? straight / 2 : (legs.isEmpty ? straight / 3 : 0)) }
        legs = legs.map { max(0, $0) }
        var used = legs.reduce(0, +)
        // Too many in the first legs: take them back, last leg first.
        var i = legs.count - 1
        while used > straight, i >= 0 {
            let take = min(legs[i], used - straight)
            legs[i] -= take; used -= take
            i -= 1
        }
        return legs + [straight - used]
    }

    /// L- and U-Shape Winder runs: straight legs joined by winder corners whose tread lines radiate from the inner corner
    /// (single-point winders), each corner a square one run width deep.
    static func winder(_ run: StairRun, treads: Int, tread: Double) -> StairRunShapeGeometry {
        let w = run.width, hw = w / 2, k = run.winders
        let sigma: Double = run.turnsLeft ?? true ? 1 : -1
        let legTreads = legs(run, treads: treads)
        var e = run.start, t = run.directionVector
        var station = 0.0
        var cells: [StairCell] = []
        var left: [StairEdgePoint] = [], right: [StairEdgePoint] = []
        var walk: [Vec2] = [e], stations: [Double] = [0]
        func addEdge(_ l: Vec2, _ r: Vec2, _ s: Double) {
            if left.last.map({ !$0.point.isAlmostEqual(l) || abs($0.station - s) > 1e-9 }) ?? true { left.append(StairEdgePoint(point: l, station: s)) }
            if right.last.map({ !$0.point.isAlmostEqual(r) || abs($0.station - s) > 1e-9 }) ?? true { right.append(StairEdgePoint(point: r, station: s)) }
        }
        addEdge(e + t.perpendicular * hw, e - t.perpendicular * hw, 0)
        let startDir = t
        for (leg, count) in legTreads.enumerated() {
            let n = t.perpendicular
            for j in 0..<count {
                let a = Double(j) * tread, b = a + tread
                let f = Segment2(e + t * a + n * hw, e + t * a - n * hw)
                let bk = Segment2(e + t * b + n * hw, e + t * b - n * hw)
                cells.append(StairCell(polygon: Polygon2([f.start, f.end, bk.end, bk.start]).counterClockwise, front: f, back: bk,
                                       station: station + a, backStation: station + b, walkPoint: e + t * ((a + b) / 2), walkDirection: t))
            }
            e = e + t * (Double(count) * tread)
            station += Double(count) * tread
            if count > 0 { walk.append(e); stations.append(station); addEdge(e + n * hw, e - n * hw, station) }
            guard leg < legTreads.count - 1 else { break }
            // Corner: entry edge centred on e, the square extends one width along t and turns toward `out`.
            let out = n * sigma
            let inner = e + out * hw
            let outer = e + t * w - out * hw
            let mid = e + t * hw, exit = mid + out * hw
            let walkCorner = [e, mid, exit]
            func hit(_ d: Vec2) -> (Vec2, Bool) {
                let du = d.dot(t), dv = d.dot(out)
                var lambda = Double.infinity, far = false
                if du > 1e-9 { lambda = w / du; far = true }
                if dv < -1e-9, w / -dv < lambda - 1e-9 { lambda = w / -dv; far = false }
                return (inner + d * lambda, far)
            }
            /// Walk distance (from the corner's entry) where a winder line from the inner corner crosses the walk line.
            func walkStation(_ d: Vec2) -> Double {
                let ray = Segment2(inner, inner + d * (w * 2))
                var acc = 0.0
                for (a, b) in zip(walkCorner, walkCorner.dropFirst()) {
                    if let p = ray.intersection(Segment2(a, b)) { return acc + a.distance(to: p) }
                    acc += a.distance(to: b)
                }
                return acc
            }
            var lines: [(Vec2, Bool, Double)] = []
            for i in 0...k {
                let d = (-out).rotated(by: sigma * (.pi / 2) * Double(i) / Double(k))
                let (p, far) = hit(d)
                lines.append((p, far, i == 0 ? 0 : i == k ? w : walkStation(d)))
            }
            for i in 0..<k {
                let (p0, far0, s0) = lines[i], (p1, far1, s1) = lines[i + 1]
                var pts = [inner, p0]
                if !far0 && far1 { pts.append(outer) }
                pts.append(p1)
                let f = sigma > 0 ? Segment2(inner, p0) : Segment2(p0, inner)
                let bk = sigma > 0 ? Segment2(inner, p1) : Segment2(p1, inner)
                let sm = (s0 + s1) / 2
                let wp = sm <= hw ? e + t * sm : mid + out * (sm - hw)
                cells.append(StairCell(polygon: Polygon2(pts).counterClockwise, front: f, back: bk, station: station + s0, backStation: station + s1,
                                       walkPoint: wp, walkDirection: sm <= hw ? t : out, isWinder: true))
            }
            // Boundaries: the inner one turns at the inner corner, the outer one goes round the square.
            let farEntry = e - out * hw, farExit = inner + t * w
            if sigma > 0 {
                left.append(StairEdgePoint(point: inner, station: station))
                left.append(StairEdgePoint(point: inner, station: station + w))
                right.append(StairEdgePoint(point: farEntry, station: station))
                right.append(StairEdgePoint(point: outer, station: station + hw))
                right.append(StairEdgePoint(point: farExit, station: station + w))
            } else {
                right.append(StairEdgePoint(point: inner, station: station))
                right.append(StairEdgePoint(point: inner, station: station + w))
                left.append(StairEdgePoint(point: farEntry, station: station))
                left.append(StairEdgePoint(point: outer, station: station + hw))
                left.append(StairEdgePoint(point: farExit, station: station + w))
            }
            walk.append(mid); stations.append(station + hw)
            walk.append(exit); stations.append(station + w)
            station += w
            e = exit
            t = out
        }
        let n = t.perpendicular
        addEdge(e + n * hw, e - n * hw, station)
        return StairRunShapeGeometry(cells: cells, left: left, right: right, walk: walk, walkStations: stations,
                                     startEdge: Segment2(run.start + startDir.perpendicular * hw, run.start - startDir.perpendicular * hw),
                                     endEdge: Segment2(e + n * hw, e - n * hw), startDirection: startDir, endDirection: t)
    }

    /// Sketched run: riser lines sorted along the stair path, trimmed or extended to the boundary lines; a tread between
    /// every two risers.
    static func sketch(_ run: StairRun) -> StairRunShapeGeometry? {
        guard let k = run.sketch, !k.path.isEmpty else { return nil }
        var path: [Vec2] = []
        for c in k.path {
            for p in c.tessellate(chordTolerance: 0.01) where path.last.map({ !$0.isAlmostEqual(p) }) ?? true { path.append(p) }
        }
        guard path.count >= 2 else { return nil }
        var cum: [Double] = [0]
        for (a, b) in zip(path, path.dropFirst()) { cum.append(cum.last! + a.distance(to: b)) }
        /// Station and tangent of the closest point on the path.
        func locate(_ p: Vec2) -> (s: Double, point: Vec2, tangent: Vec2) {
            var best = (Double.infinity, 0.0, path[0], Vec2.unitX)
            for i in 0..<(path.count - 1) {
                let seg = Segment2(path[i], path[i + 1])
                let q = seg.closestPoint(to: p)
                let d = q.distance(to: p)
                if d < best.0 { best = (d, cum[i] + path[i].distance(to: q), q, seg.direction) }
            }
            return (best.1, best.2, best.3)
        }
        let boundary: [Segment2] = k.boundaries.flatMap { c -> [Segment2] in
            let pts = c.tessellate(chordTolerance: 0.01)
            return zip(pts, pts.dropFirst()).map { Segment2($0, $1) }
        }
        struct R { var s: Double; var left: Vec2; var right: Vec2; var dir: Vec2 }
        var risers: [R] = []
        for c in k.risers {
            let seg = Segment2(c.start, c.end)
            guard !seg.isDegenerate else { continue }
            // Where the riser meets the path (or the path point nearest its middle).
            var at = locate(seg.midpoint)
            for i in 0..<(path.count - 1) {
                if let x = seg.lineIntersection(Segment2(path[i], path[i + 1])), x.u >= -1e-9, x.u <= 1 + 1e-9 {
                    at = (cum[i] + path[i].distance(to: x.point), x.point, Segment2(path[i], path[i + 1]).direction)
                    break
                }
            }
            let n = at.tangent.perpendicular
            var l = seg.start, r = seg.end
            if (l - at.point).dot(n) < (r - at.point).dot(n) { swap(&l, &r) }
            // Trim or extend to the nearest boundary on each side.
            var bestL = Double.infinity, bestR = Double.infinity
            for b in boundary {
                guard let x = seg.lineIntersection(b), x.u >= -1e-6, x.u <= 1 + 1e-6 else { continue }
                let side = (x.point - at.point).dot(n)
                let d = x.point.distance(to: at.point)
                if side > 0, d < bestL { bestL = d; l = x.point }
                if side < 0, d < bestR { bestR = d; r = x.point }
            }
            risers.append(R(s: at.s, left: l, right: r, dir: at.tangent))
        }
        risers.sort { $0.s < $1.s }
        guard risers.count >= 2 else { return nil }
        let s0 = risers[0].s
        var cells: [StairCell] = []
        for i in 0..<(risers.count - 1) {
            let a = risers[i], b = risers[i + 1]
            let f = Segment2(a.left, a.right), bk = Segment2(b.left, b.right)
            let mid = (a.left + a.right + b.left + b.right) / 4
            cells.append(StairCell(polygon: Polygon2([a.left, a.right, b.right, b.left]).counterClockwise, front: f, back: bk,
                                   station: a.s - s0, backStation: b.s - s0, walkPoint: locate(mid).point, walkDirection: a.dir))
        }
        let last = risers[risers.count - 1]
        var walk: [Vec2] = [], stations: [Double] = []
        for (i, p) in path.enumerated() where cum[i] > s0 + 1e-9 && cum[i] < last.s - 1e-9 { walk.append(p); stations.append(cum[i] - s0) }
        walk.insert(locate(risers[0].left.midpoint(risers[0].right)).point, at: 0); stations.insert(0, at: 0)
        walk.append(locate(last.left.midpoint(last.right)).point); stations.append(last.s - s0)
        return StairRunShapeGeometry(cells: cells,
                                     left: risers.map { StairEdgePoint(point: $0.left, station: $0.s - s0) },
                                     right: risers.map { StairEdgePoint(point: $0.right, station: $0.s - s0) },
                                     walk: walk, walkStations: stations,
                                     startEdge: Segment2(risers[0].left, risers[0].right), endEdge: Segment2(last.left, last.right),
                                     startDirection: risers[0].dir, endDirection: last.dir)
    }
}
