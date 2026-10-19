import Foundation
import ArcusGeometry
import ArcusCalc

// STAIR: the stair layout of a component stair (Revit-style Stair by Component): runs of treads with their heights,
// landings, supports and the calculation-rule warnings. Plan graphics (StairPlanGraphics), 3D (StairMeshes), railings
// (StairRailings), tags, schedules and IFC all read this one layout.

/// A tread of a stair in plan with its walking-surface height.
public struct StairTread: Sendable, Hashable {
    public var polygon: Polygon2
    /// Front (nosing) and back edges, from the run's left boundary to its right (left of the up direction).
    public var front: Segment2
    public var back: Segment2
    /// Height of the walking surface.
    public var z: Double
    /// Tread number along the whole stair (Tread/Riser Start Number first).
    public var number: Int
    public var walkPoint: Vec2
    public var walkDirection: Vec2
    public var isWinder: Bool
}

/// A riser of a stair in plan (the line where it meets the tread below) and its bottom and top heights.
public struct StairRiserLine: Sendable, Hashable {
    public var line: Segment2
    public var z0: Double
    public var z1: Double
    /// Walk distance from the run's start edge.
    public var station: Double
    /// Riser number along the whole stair.
    public var number: Int
}

/// A point of a stair edge (or walk line) with the height of the nosing line there.
public struct StairPathPoint: Sendable, Hashable {
    public var point: Vec2
    public var z: Double
    /// On a landing (flat) rather than on a run.
    public var onLanding: Bool
    public init(point: Vec2, z: Double, onLanding: Bool) { self.point = point; self.z = z; self.onLanding = onLanding }
}

/// Computed stair layout.
public struct StairLayout: Sendable {
    public struct Run: Sendable {
        /// Centre line at the start edge, and the direction of travel there.
        public var start: Vec2
        public var direction: Vec2
        public var risers: Int
        /// Height of the floor or landing the run starts from.
        public var baseZ: Double
        public var width: Double
        public var shape: StairRunShape
        public var index: Int
        public var treads: [StairTread]
        public var riserLines: [StairRiserLine]
        /// Left and right boundaries from the start edge to the end edge, with the nosing-line height at each point.
        public var left: [StairPathPoint]
        public var right: [StairPathPoint]
        /// Walk line (run centre line) from the start edge to the end edge.
        public var walk: [Vec2]
        public var walkStations: [Double]
        public var startEdge: Segment2
        public var endEdge: Segment2
        public var endDirection: Vec2
        public var topZ: Double
        /// Number of treads (legacy name: risers - 1 for a run that starts and ends with a riser).
        public var length: Double { Double(max(risers - 1, 0)) }
        /// Plan outline (left boundary up, right boundary back).
        public var outline: Polygon2 { Polygon2(left.map(\.point) + right.reversed().map(\.point)).simplified() }
        /// Nosing-line height at walk distance `s` (extended beyond the run at the run's average pitch).
        public func pitchZ(_ s: Double) -> Double {
            guard let first = riserLines.first else { return baseZ }
            let pts = riserLines.map { (s: $0.station, z: $0.z1) }
            let slope = pts.count >= 2 ? (pts.last!.z - first.z1) / max(pts.last!.s - first.station, 1e-9) : 0
            if s <= first.station { return first.z1 + (s - first.station) * slope }
            for (a, b) in zip(pts, pts.dropFirst()) where s <= b.s {
                return a.z + (b.z - a.z) * (s - a.s) / max(b.s - a.s, 1e-9)
            }
            return pts.last!.z + (s - pts.last!.s) * slope
        }
        /// The walk line point at walk distance `s`.
        public func walkPoint(_ s: Double) -> Vec2 {
            guard walk.count >= 2 else { return start }
            for i in 0..<(walk.count - 1) where s <= walkStations[i + 1] || i == walk.count - 2 {
                let t = (s - walkStations[i]) / max(walkStations[i + 1] - walkStations[i], 1e-9)
                return walk[i].lerp(to: walk[i + 1], t: max(0, min(1, t)))
            }
            return walk.last!
        }
        public var walkLength: Double { walkStations.last ?? 0 }
    }

    public struct Landing: Sendable {
        public var polygon: Polygon2
        public var z: Double
        /// The landing joins this run to the next (nil: a free sketched landing).
        public var afterRun: Int?
        public var isAutomatic: Bool
        /// Index in `StairData.landings` (nil: an automatic landing of a stair without a landing list).
        public var index: Int?
    }

    /// A support (stringer or carriage) along a run edge and the landings it continues around.
    public struct Support: Sendable {
        public var kind: StairSupportKind
        public var side: StairSupport.Side?
        public var run: Int?
        public var info: StairTypeInfo.Support
        /// Centre line of the support in plan, with the nosing-line height at each point.
        public var path: [StairPathPoint]
        /// Inner and outer face lines in plan.
        public var faces: [[Vec2]]
    }

    public var runs: [Run]
    public var landings: [Landing]
    public var supports: [Support]
    /// Actual Number of Risers (all runs).
    public var riserCount: Int
    /// Desired Number of Risers: the risers the stair needs to reach its top.
    public var desiredRiserCount: Int
    public var riserHeight: Double
    public var treadDepth: Double
    public var baseZ: Double
    public var topZ: Double
    /// Width of the first run (Actual Run Width).
    public var width: Double
    public var warnings: [String]
    public var type: StairTypeInfo
    public var beginWithRiser: Bool
    public var endWithRiser: Bool

    /// Plan outline of a run (legacy name).
    public func runRect(_ r: Run) -> Polygon2 { r.outline }

    /// The stair's plan outline: runs and landings as one region (Shaft ▸ Pick Stair, hit testing).
    public var outline: [Polygon2] {
        let profiles = runs.map { Profile2(outer: $0.outline.counterClockwise) } + landings.map { Profile2(outer: $0.polygon.counterClockwise) }
        return PolygonBoolean.union(profiles).map(\.outer)
    }

    /// Risers left to reach the top (negative: too many).
    public var remainingRisers: Int { desiredRiserCount - riserCount }
}

public enum StairGeometry {
    /// Smallest and largest number of risers a stair may have.
    public static let riserRange = 2...200

    /// The stair's height, Desired Number of Risers and Actual Riser Height (from its levels and type), or nil when the
    /// top isn't above the base.
    public static func numbers(_ e: Element, _ model: BIMModel, type t: StairTypeInfo? = nil) -> (base: Double, top: Double, desired: Int, riser: Double, tread: Double)? {
        guard let s = e.stair else { return nil }
        let t = t ?? StairTypeInfo.of(e, model)
        let base = model.baseElevation(of: e)
        let top = model.topElevation(base: base, topLevelID: s.topLevelID, topOffset: s.topOffset, unconnectedHeight: s.unconnectedHeight)
        let h = top - base
        guard h > 0.1 else { return nil }
        var n = s.desiredRiserCount ?? Int((h / t.maxRiser - 1e-9).rounded(.up))
        n = max(riserRange.lowerBound, min(n, riserRange.upperBound))
        return (base, top, n, h / Double(n), s.treadDepth ?? t.minTread)
    }

    /// The runs and landings of a stair: its own, or those its shape stands for (older stairs).
    public static func components(_ e: Element, _ model: BIMModel) -> (runs: [StairRun], landings: [StairLanding]?)? {
        guard let s = e.stair else { return nil }
        if let runs = s.runs, !runs.isEmpty { return (runs, s.landings) }
        guard let n = numbers(e, model) else { return nil }
        let legacy = StairComponents.legacy(s, risers: n.desired, tread: n.tread)
        return (legacy.runs, legacy.landings)
    }

    public static func layout(_ e: Element, _ model: BIMModel) -> StairLayout? {
        guard let s = e.stair else { return nil }
        let type = StairTypeInfo.of(e, model)
        guard let num = numbers(e, model, type: type), let comps = components(e, model) else { return nil }
        let rh = num.riser, tread = num.tread
        let begin = s.beginWithRiser ?? true, end = s.endWithRiser ?? true
        let startNumber = s.treadNumberStart ?? 1
        var runs: [StairLayout.Run] = []
        var z = num.base
        var treadNumber = startNumber, riserNumber = startNumber
        var warnings: [String] = []
        let fmt: (Double) -> String = { QuantityFormatter.format($0, kind: .length, units: model.units) }
        for (i, r) in comps.runs.enumerated() {
            let n = max(1, r.risers)
            let lead = (i == 0 && !begin && r.shape != .sketch) ? 1 : 0
            let tail = (i == comps.runs.count - 1 && !end && r.shape != .sketch) ? 1 : 0
            let treads = r.shape == .sketch ? max(0, n - 1) : max(0, n - 1 + lead + tail)
            guard let g = StairRunGeometry.shape(r, treads: treads, tread: tread) else {
                warnings.append("Run \(i + 1) can't be built: \(r.shape == .spiral ? "its radius is smaller than half its width" : "it needs two risers and a stair path").")
                continue
            }
            let risersHere = r.shape == .sketch ? g.cells.count + 1 : n
            var tl: [StairTread] = [], rl: [StairRiserLine] = []
            for (k, c) in g.cells.enumerated() {
                let tz = k < lead ? z : z + Double(k - lead + 1) * rh
                tl.append(StairTread(polygon: c.polygon, front: c.front, back: c.back, z: tz, number: treadNumber,
                                     walkPoint: c.walkPoint, walkDirection: c.walkDirection, isWinder: c.isWinder))
                treadNumber += 1
                if k >= lead {
                    rl.append(StairRiserLine(line: c.front, z0: tz - rh, z1: tz, station: c.station, number: riserNumber))
                    riserNumber += 1
                }
            }
            let top = z + Double(risersHere) * rh
            if tail == 0 {
                rl.append(StairRiserLine(line: g.endEdge, z0: top - rh, z1: top, station: g.walkLength, number: riserNumber))
                riserNumber += 1
            }
            var run = StairLayout.Run(start: g.walk.first ?? r.start, direction: g.startDirection, risers: risersHere, baseZ: z, width: r.width,
                                      shape: r.shape, index: i, treads: tl, riserLines: rl, left: [], right: [], walk: g.walk,
                                      walkStations: g.walkStations, startEdge: g.startEdge, endEdge: g.endEdge, endDirection: g.endDirection, topZ: top)
            run.left = g.left.map { StairPathPoint(point: $0.point, z: run.pitchZ($0.station), onLanding: false) }
            run.right = g.right.map { StairPathPoint(point: $0.point, z: run.pitchZ($0.station), onLanding: false) }
            runs.append(run)
            z = top
            if r.width < type.minRunWidth - Tolerance.length {
                warnings.append("Run \(i + 1): Actual Run Width \(fmt(r.width)) is less than the type's Minimum Run Width \(fmt(type.minRunWidth)).")
            }
        }
        guard !runs.isEmpty else { return nil }
        let landings = landingLayouts(comps.landings, runs)
        let actual = runs.reduce(0) { $0 + $1.risers }
        // Calculation Rules.
        if rh > type.maxRiser + Tolerance.length {
            warnings.append("Actual Riser Height \(fmt(rh)) exceeds the type's Maximum Riser Height \(fmt(type.maxRiser)).")
        }
        if tread < type.minTread - Tolerance.length {
            warnings.append("Actual Tread Depth \(fmt(tread)) is less than the type's Minimum Tread Depth \(fmt(type.minTread)).")
        }
        if type.calcUse {
            let rule = 2 * rh + tread
            if rule < type.calcMin - Tolerance.length || rule > type.calcMax + Tolerance.length {
                warnings.append("Stair calculation rule not met: 2 × Riser + Tread = \(fmt(rule)), outside \(fmt(type.calcMin)) to \(fmt(type.calcMax)).")
            }
        }
        if actual < num.desired {
            warnings.append("The stair has \(actual) risers and needs \(num.desired) to reach its top (\(num.desired - actual) remaining). Add risers to the runs.")
        } else if actual > num.desired {
            warnings.append("The stair has \(actual) risers, more than the \(num.desired) it needs: its top end runs past the Top Level.")
        }
        var l = StairLayout(runs: runs, landings: landings, supports: [], riserCount: actual, desiredRiserCount: num.desired, riserHeight: rh,
                            treadDepth: tread, baseZ: num.base, topZ: num.top, width: runs[0].width, warnings: warnings, type: type,
                            beginWithRiser: begin, endWithRiser: end)
        l.supports = supportLayouts(l, s.supports ?? [], model)
        return l
    }

    // MARK: Landings

    static func landingLayouts(_ list: [StairLanding]?, _ runs: [StairLayout.Run]) -> [StairLayout.Landing] {
        let entries: [(StairLanding, Int?)] = list.map { $0.enumerated().map { ($0.element, Optional($0.offset)) } }
            ?? (0..<max(0, runs.count - 1)).map { (StairLanding(afterRun: $0), nil) }
        var out: [StairLayout.Landing] = []
        for (land, index) in entries {
            if let b = land.boundary, b.count >= 3 {
                let poly = Polygon2(b).counterClockwise
                let z = land.afterRun.flatMap { i in runs.first { $0.index == i }?.topZ } ?? nearestRunEnd(poly.centroid, runs)
                out.append(StairLayout.Landing(polygon: poly, z: z, afterRun: land.afterRun, isAutomatic: false, index: index))
            } else if let a = land.afterRun, let ra = runs.first(where: { $0.index == a }), let rb = runs.first(where: { $0.index == a + 1 }),
                      let poly = automaticLanding(ra, rb) {
                out.append(StairLayout.Landing(polygon: poly, z: ra.topZ, afterRun: a, isAutomatic: true, index: index))
            }
        }
        return out
    }

    static func nearestRunEnd(_ p: Vec2, _ runs: [StairLayout.Run]) -> Double {
        runs.min { $0.endEdge.distance(to: p) < $1.endEdge.distance(to: p) }?.topZ ?? runs.first?.baseZ ?? 0
    }

    /// The automatic landing joining run `a` to run `b`: a rectangle in `a`'s end frame around both runs' ends,
    /// one run width deep beyond `a` at a turn (RevitCraft `run_landing`, Revit's automatic landing). nil when the
    /// runs already meet or are too far apart to join.
    public static func automaticLanding(_ a: StairLayout.Run, _ b: StairLayout.Run) -> Polygon2? {
        let d0 = a.endDirection, d1 = b.direction
        var pts = [a.endEdge.start, a.endEdge.end, b.startEdge.start, b.startEdge.end]
        let turning = d0.dot(d1) < 0.999
        if turning {
            pts += [a.endEdge.start + d0 * a.width, a.endEdge.end + d0 * a.width]
            if d0.dot(d1) < -0.5 { pts.append(b.startEdge.midpoint + d0 * max(a.width, b.width)) }
        }
        let o = a.endEdge.midpoint, side = d0.perpendicular
        var u0 = Double.infinity, u1 = -Double.infinity, v0 = Double.infinity, v1 = -Double.infinity
        for q in pts {
            let u = (q - o).dot(d0), v = (q - o).dot(side)
            u0 = min(u0, u); u1 = max(u1, u); v0 = min(v0, v); v1 = max(v1, v)
        }
        guard u1 - u0 > 0.001, v1 - v0 > 0.001 else { return nil }
        let reach = 2.5 * (a.width + b.width)
        guard u1 - u0 <= reach, v1 - v0 <= reach + a.width else { return nil }
        func at(_ u: Double, _ v: Double) -> Vec2 { o + d0 * u + side * v }
        return Polygon2([at(u0, v0), at(u1, v0), at(u1, v1), at(u0, v1)]).counterClockwise
    }

    // MARK: Edges around landings

    /// One side of the stair as a continuous path: up each run's boundary and around the landings' edges between runs
    /// (never across a landing), with the nosing-line height (runs) or landing height (landings). `inset` moves the
    /// path toward the inside of the stair (negative: outside).
    public static func sidePath(_ l: StairLayout, left: Bool, inset: Double = 0) -> [StairPathPoint] {
        var out: [StairPathPoint] = []
        func add(_ p: StairPathPoint) {
            if let last = out.last, last.point.isAlmostEqual(p.point), abs(last.z - p.z) < 1e-9 { return }
            out.append(p)
        }
        for (k, r) in l.runs.enumerated() {
            let edge = left ? r.left : r.right
            for p in edge { add(p) }
            guard k + 1 < l.runs.count else { continue }
            let next = l.runs[k + 1]
            let a = (left ? r.left.last : r.right.last)?.point ?? r.endEdge.start
            let b = (left ? next.left.first : next.right.first)?.point ?? next.startEdge.start
            if let land = l.landings.first(where: { $0.afterRun == r.index }) {
                let avoid = [(left ? r.right.last : r.left.last)?.point, (left ? next.right.first : next.left.first)?.point].compactMap { $0 }
                for q in loopPath(land.polygon, from: a, to: b, avoiding: avoid) { add(StairPathPoint(point: q, z: land.z, onLanding: true)) }
            }
        }
        guard abs(inset) > 1e-9 else { return out }
        // Offset in plan toward the inside: the left edge moves right of its direction, the right edge left.
        let pts = out.map(\.point)
        guard pts.count >= 2 else { return out }
        let moved = offset(pts, by: left ? -inset : inset)
        return zip(out, moved).map { StairPathPoint(point: $1, z: $0.z, onLanding: $0.onLanding) }
    }

    /// The landing boundary from `a` to `b` (both on it): the way round that doesn't pass the `avoiding` points (the
    /// other side's run corners), including `a` and `b`.
    static func loopPath(_ poly: Polygon2, from a: Vec2, to b: Vec2, avoiding: [Vec2]) -> [Vec2] {
        if a.isAlmostEqual(b, tolerance: 1e-6) { return [a, b] }
        let p = poly.points, n = p.count
        guard n >= 3 else { return [a, b] }
        /// Edge index and parameter of the boundary point nearest q.
        func locate(_ q: Vec2) -> (Int, Double) {
            var best = (0, 0.0, Double.infinity)
            for i in 0..<n {
                let s = Segment2(p[i], p[(i + 1) % n])
                let t = max(0, min(1, s.parameter(of: q)))
                let d = s.point(at: t).distance(to: q)
                if d < best.2 { best = (i, t, d) }
            }
            return (best.0, best.1)
        }
        let (ia, ta) = locate(a), (ib, tb) = locate(b)
        func walk(_ forward: Bool) -> [Vec2] {
            var pts = [a]
            if ia == ib && (forward ? tb >= ta : tb <= ta) { return [a, b] }
            var i = ia
            for _ in 0..<(n + 1) {
                let corner = forward ? p[(i + 1) % n] : p[i]
                pts.append(corner)
                i = forward ? (i + 1) % n : (i + n - 1) % n
                if i == ib { break }
            }
            pts.append(b)
            return pts
        }
        func passes(_ path: [Vec2]) -> Bool {
            avoiding.contains { q in zip(path, path.dropFirst()).contains { Segment2($0, $1).distance(to: q) < 0.01 && !q.isAlmostEqual(a, tolerance: 0.01) && !q.isAlmostEqual(b, tolerance: 0.01) } }
        }
        let f = walk(true), r = walk(false)
        func length(_ x: [Vec2]) -> Double { zip(x, x.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) } }
        switch (passes(f), passes(r)) {
        case (false, true): return f
        case (true, false): return r
        default: return length(f) <= length(r) ? f : r
        }
    }

    // MARK: Supports

    static func supportLayouts(_ l: StairLayout, _ picked: [StairSupport], _ model: BIMModel) -> [StairLayout.Support] {
        var out: [StairLayout.Support] = []
        let t = l.type
        for (left, info) in [(true, t.left), (false, t.right)] where info.kind != .none {
            out.append(sideSupport(l, left: left, info: info))
        }
        if t.middle.kind != .none, t.middleCount > 0 {
            for r in l.runs {
                for i in 0..<t.middleCount {
                    let frac = Double(i + 1) / Double(t.middleCount + 1) - 0.5
                    let pts = offset(r.walk, by: frac * r.width)
                    let path = zip(pts, r.walkStations).map { StairPathPoint(point: $0, z: r.pitchZ($1), onLanding: false) }
                    out.append(support(.carriageOpen, side: nil, run: r.index, t.middle, path))
                }
            }
        }
        for p in picked {
            guard let ri = p.run, let r = l.runs.first(where: { $0.index == ri }) else { continue }
            let left = p.side == .left
            let base = left ? t.left : t.right
            var info = p.typeID.map { StairTypeInfo.support(typeID: $0, kind: base.kind == .none ? .stringerClosed : base.kind, model) } ?? base
            if info.kind == .none { info.kind = .stringerClosed }
            let edge = left ? r.left : r.right
            out.append(support(info.kind, side: p.side, run: ri, info, offsetEdge(edge, left: left, info)))
        }
        return out
    }

    /// The type's support on one side: along the runs and round the landings (closed stringers), or under each run
    /// (carriages).
    static func sideSupport(_ l: StairLayout, left: Bool, info: StairTypeInfo.Support) -> StairLayout.Support {
        if info.kind == .stringerClosed {
            let path = sidePath(l, left: left, inset: -(info.lateralOffset + info.width / 2))
            return support(.stringerClosed, side: left ? .left : .right, run: nil, info, path)
        }
        let path = l.runs.flatMap { offsetEdge(left ? $0.left : $0.right, left: left, info) }
        return support(.carriageOpen, side: left ? .left : .right, run: nil, info, path)
    }

    /// A run edge moved to the support's centre line: outside the run for stringers, under it for carriages.
    static func offsetEdge(_ edge: [StairPathPoint], left: Bool, _ info: StairTypeInfo.Support) -> [StairPathPoint] {
        let inward = info.kind == .carriageOpen ? info.lateralOffset + info.width / 2 : -(info.lateralOffset + info.width / 2)
        let pts = edge.map(\.point)
        guard pts.count >= 2 else { return edge }
        let moved = offset(pts, by: left ? -inward : inward)
        return zip(edge, moved).map { StairPathPoint(point: $1, z: $0.z, onLanding: $0.onLanding) }
    }

    /// Offsets a polyline by `d` (positive to the left of travel), point for point: repeated points (a height step at
    /// one plan point) move together, corners are mitred (limited to 4 × |d|).
    public static func offset(_ pts: [Vec2], by d: Double) -> [Vec2] {
        guard abs(d) > 1e-12, pts.count >= 2 else { return pts }
        return pts.indices.map { i in
            let p = pts[i]
            let prev = pts[..<i].last { !$0.isAlmostEqual(p) }
            let next = pts[(i + 1)...].first { !$0.isAlmostEqual(p) }
            let n0 = prev.map { (p - $0).normalized.perpendicular }
            let n1 = next.map { ($0 - p).normalized.perpendicular }
            switch (n0, n1) {
            case let (a?, b?):
                let m = a + b
                guard m.length > 1e-6 else { return p + a * d }
                let dir = m.normalized
                let c = max(dir.dot(a), 0.25)
                return p + dir * (d / c)
            case let (a?, nil): return p + a * d
            case let (nil, b?): return p + b * d
            default: return p
            }
        }
    }

    static func support(_ kind: StairSupportKind, side: StairSupport.Side?, run: Int?, _ info: StairTypeInfo.Support, _ path: [StairPathPoint]) -> StairLayout.Support {
        let pts = path.map(\.point)
        let faces = pts.count >= 2 ? [offset(pts, by: info.width / 2), offset(pts, by: -info.width / 2)] : []
        return StairLayout.Support(kind: kind, side: side, run: run, info: info, path: path, faces: faces)
    }
}
