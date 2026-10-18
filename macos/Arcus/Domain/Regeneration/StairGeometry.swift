import Foundation
import ArcusGeometry

/// Computed stair layout. Runs are straight flights; landings are flat rectangles.
public struct StairLayout: Sendable {
    public struct Run: Sendable {
        /// Start of the run centerline at the first riser, and unit direction of travel.
        public var start: Vec2
        public var direction: Vec2
        public var risers: Int
        /// Elevation at the bottom of the first riser.
        public var baseZ: Double
        public var width: Double
        public var length: Double { Double(max(risers - 1, 0)) }
    }
    public var runs: [Run]
    public var landings: [(polygon: Polygon2, z: Double)]
    public var riserCount: Int
    public var riserHeight: Double
    public var treadDepth: Double
    public var baseZ: Double
    public var topZ: Double
    public var width: Double
    public var warnings: [String]

    /// Plan footprint of each run as a rectangle (for plan display and railings).
    public func runRect(_ r: Run) -> Polygon2 {
        let n = r.direction.perpendicular * (r.width / 2)
        let end = r.start + r.direction * (Double(r.risers - 1) * treadDepth)
        return Polygon2([r.start - n, end - n, end + n, r.start + n])
    }
}

public enum StairGeometry {
    public static func layout(_ e: Element, _ model: BIMModel) -> StairLayout? {
        guard let s = e.stair else { return nil }
        let base = model.baseElevation(of: e)
        let top = model.topElevation(base: base, topLevelID: s.topLevelID, topOffset: s.topOffset, unconnectedHeight: s.unconnectedHeight)
        let h = top - base
        guard h > 0.1 else { return nil }
        let maxRiser = model.typeLength(e, ParameterID("stair.maxRiser"), default: 0.18)
        let tread = model.typeLength(e, ParameterID("stair.minTread"), default: 0.28)
        var n = s.desiredRiserCount ?? Int((h / maxRiser).rounded(.up))
        n = max(2, min(n, 80))
        let rh = h / Double(n)
        var warnings: [String] = []
        if rh > maxRiser + Tolerance.length {
            warnings.append(String(format: "Actual riser height %.0f mm exceeds the type maximum of %.0f mm.", rh * 1000, maxRiser * 1000))
        }
        let blondel = 2 * rh + tread
        if blondel < 0.55 || blondel > 0.70 {
            warnings.append(String(format: "Two risers plus one tread is %.0f mm; comfortable stairs are 550–700 mm.", blondel * 1000))
        }
        let dir = Vec2.fromAngle(s.direction)
        let w = s.width
        var runs: [StairLayout.Run] = []
        var landings: [(Polygon2, Double)] = []
        switch s.shape {
        case .straight:
            runs = [.init(start: s.origin, direction: dir, risers: n, baseZ: base, width: w)]
        case .lShaped, .uShaped:
            let n1 = max(2, min(n - 2, s.firstRunRisers ?? n / 2))
            let n2 = n - n1
            let run1End = s.origin + dir * (Double(n1 - 1) * tread)
            let zLanding = base + Double(n1) * rh
            let side = dir.perpendicular * (s.turnsLeft ? 1 : -1)
            if s.shape == .lShaped {
                // Landing square after run 1; run 2 leaves toward the turn side.
                let lc = run1End + dir * (tread / 2 + w / 2) // not used directly
                _ = lc
                let a = run1End + dir * 0, b = a + dir * w
                let hw = side * (w / 2)
                let landing = Polygon2([a - hw, b - hw, b + hw, a + hw])
                landings.append((landing.counterClockwise, zLanding))
                let run2Start = run1End + dir * (w / 2) + side * (w / 2)
                runs = [.init(start: s.origin, direction: dir, risers: n1, baseZ: base, width: w),
                        .init(start: run2Start, direction: side, risers: n2, baseZ: zLanding, width: w)]
            } else {
                let gap = 0.1
                let a = run1End, b = a + dir * w
                let far = side * (w * 1.5 + gap)
                let near = side * (-w / 2)
                let landing = Polygon2([a + near, b + near, b + far, a + far])
                landings.append((landing.counterClockwise, zLanding))
                let run2Start = run1End + side * (w + gap)
                runs = [.init(start: s.origin, direction: dir, risers: n1, baseZ: base, width: w),
                        .init(start: run2Start, direction: -dir, risers: n2, baseZ: zLanding, width: w)]
            }
        }
        return StairLayout(runs: runs, landings: landings, riserCount: n, riserHeight: rh, treadDepth: tread, baseZ: base, topZ: top,
                           width: w, warnings: warnings)
    }

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let l = layout(e, model) else { return [] }
        let waist = model.typeLength(e, ParameterID("stair.waist"), default: 0.15)
        let mat = model.typeParam(e, ParameterID("type.material"))?.refValue
        var mesh = Mesh()
        for r in l.runs {
            // Profile in the run's vertical plane: x along travel, y = z. Sawtooth top, sloped underside.
            var pts: [Vec2] = [Vec2(0, r.baseZ)]
            for i in 0..<r.risers {
                let x = Double(i) * l.treadDepth
                let z = r.baseZ + Double(i + 1) * l.riserHeight
                pts.append(Vec2(x, z))
                if i < r.risers - 1 { pts.append(Vec2(x + l.treadDepth, z)) }
            }
            let runLen = Double(r.risers - 1) * l.treadDepth
            let slope = l.riserHeight / l.treadDepth
            let topEnd = r.baseZ + Double(r.risers) * l.riserHeight
            let cosA = 1 / (1 + slope * slope).squareRoot()
            let drop = waist / cosA
            // Top: the last riser meets the upper floor; include one tread-depth of nosing into the landing,
            // then return along an underside parallel to the pitch line (clipped at the floor below).
            let lip = l.treadDepth
            pts.append(Vec2(runLen + lip, topEnd))
            let undersideAtEnd = min(topEnd - 0.05, r.baseZ + l.riserHeight + slope * (runLen + lip) - drop)
            pts.append(Vec2(runLen + lip, undersideAtEnd))
            let zAtStart = r.baseZ + l.riserHeight - drop
            if zAtStart < r.baseZ {
                pts.append(Vec2(min((drop - l.riserHeight) / slope, runLen), r.baseZ))
            } else {
                pts.append(Vec2(0, zAtStart))
            }
            let profile = Polygon2(pts).simplified()
            guard !profile.isDegenerate, profile.isSimple else { continue }
            let side = r.direction.perpendicular
            let origin = r.start - side * (r.width / 2)
            // Frame: X = travel, Y = up, Z = X × Y = −side → negative depth moves toward +side.
            let frame = Transform3.frame(origin: Vec3(origin.x, origin.y, 0), xAxis: Vec3(r.direction.x, r.direction.y, 0), yAxis: .unitZ)
            mesh.append(MeshBuilder.extrude(Profile2(outer: profile), frame: frame, depth: -r.width))
        }
        for land in l.landings {
            mesh.append(MeshBuilder.extrude(Profile2(outer: land.polygon), bottom: land.z - waist, top: land.z))
        }
        return [MeshPart(mesh: mesh, materialID: mat)]
    }

    /// Plan graphics: tread lines below the cut, a break line at the cut, and the walk line with arrow.
    public static func planLines(_ e: Element, _ model: BIMModel, cutZ: Double) -> (outline: [Segment2], treads: [Segment2], above: [Segment2], walk: [Vec2], breakLine: Segment2?) {
        guard let l = layout(e, model) else { return ([], [], [], [], nil) }
        var outline: [Segment2] = []
        var treads: [Segment2] = []
        var above: [Segment2] = []
        var walk: [Vec2] = []
        var brk: Segment2?
        for r in l.runs {
            let side = r.direction.perpendicular * (r.width / 2)
            for i in 0..<r.risers {
                let p = r.start + r.direction * (Double(i) * l.treadDepth)
                let z = r.baseZ + Double(i + 1) * l.riserHeight
                let seg = Segment2(p - side, p + side)
                if z <= cutZ { treads.append(seg) } else { above.append(seg) }
            }
            let end = r.start + r.direction * (Double(r.risers - 1) * l.treadDepth)
            let runTop = r.baseZ + Double(r.risers) * l.riserHeight
            // Break at the cut height within this run.
            if cutZ > r.baseZ && cutZ < runTop && brk == nil {
                let k = (cutZ - r.baseZ) / l.riserHeight
                let s = min(max(k - 1, 0), Double(r.risers - 1)) * l.treadDepth
                let c = r.start + r.direction * s
                brk = Segment2(c - side + r.direction * 0.15, c + side - r.direction * 0.15)
            }
            outline.append(Segment2(r.start - side, end - side))
            outline.append(Segment2(r.start + side, end + side))
            walk.append(r.start)
            walk.append(end)
        }
        for land in l.landings { outline.append(contentsOf: land.polygon.edges) }
        return (outline, treads, above, walk, brk)
    }

    /// Railing paths along the outer edges of the stair (left and right), in plan, with elevation along the path.
    public static func railingPath(_ e: Element, _ model: BIMModel, leftSide: Bool) -> [Vec3] {
        guard let l = layout(e, model) else { return [] }
        let inset = 0.05
        var pts: [Vec3] = []
        for (i, r) in l.runs.enumerated() {
            let side = r.direction.perpendicular * ((r.width / 2 - inset) * (leftSide ? 1 : -1))
            let start = r.start + side
            let end = r.start + r.direction * (Double(r.risers - 1) * l.treadDepth) + side
            let z0 = r.baseZ + l.riserHeight
            let z1 = r.baseZ + Double(r.risers) * l.riserHeight
            pts.append(Vec3(start, z: z0))
            pts.append(Vec3(end, z: z1))
            if i < l.landings.count {
                // Continue across the landing at landing height to the start of the next run.
                if i + 1 < l.runs.count {
                    let nr = l.runs[i + 1]
                    let nside = nr.direction.perpendicular * ((nr.width / 2 - inset) * (leftSide ? 1 : -1))
                    let corner = end + r.direction * l.width
                    let nstart = nr.start + nside
                    if corner.distance(to: nstart) > 0.05 { pts.append(Vec3(end + r.direction * (l.width - inset), z: z1)) }
                    _ = corner
                }
            }
        }
        return pts
    }
}

public enum RailingGeometry {
    /// 3D path of the railing's base line.
    public static func path(_ e: Element, _ model: BIMModel) -> [Vec3] {
        guard let r = e.railing else { return [] }
        if r.followsHost, let host = model[e.hostID], host.stair != nil {
            return StairGeometry.railingPath(host, model, leftSide: r.hostSideLeft)
        }
        if r.followsHost, let host = model[e.hostID], host.ramp != nil {
            return RampGeometry.railingPath(host, model, leftSide: r.hostSideLeft)
        }
        let z = model.baseElevation(of: e)
        var pts: [Vec3] = []
        for c in r.path {
            let t = c.tessellate(chordTolerance: 0.01)
            for (i, p) in t.enumerated() where !(i == 0 && pts.last.map { $0.xy.isAlmostEqual(p) } == true) {
                pts.append(Vec3(p, z: z))
            }
        }
        return pts
    }

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        let pts = path(e, model)
        guard pts.count >= 2 else { return [] }
        let h = model.typeLength(e, ParameterID("railing.height"), default: 1.0)
        let spacing = model.typeLength(e, ParameterID("railing.balusterSpacing"), default: 0.12)
        let bs = model.typeLength(e, ParameterID("railing.balusterSize"), default: 0.02)
        let rs = model.typeLength(e, ParameterID("railing.railSize"), default: 0.05)
        let mat = model.typeParam(e, ParameterID("type.material"))?.refValue
        var mesh = Mesh()
        // Top rail: rectangular section swept along the path raised by the railing height.
        let top = pts.map { $0 + Vec3(0, 0, h - rs / 2) }
        let rail = Polygon2([Vec2(-rs / 2, -rs / 2), Vec2(rs / 2, -rs / 2), Vec2(rs / 2, rs / 2), Vec2(-rs / 2, rs / 2)])
        mesh.append(MeshBuilder.sweep(profile: rail, along: top))
        // Balusters at spacing along each segment.
        var carry = 0.0
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let len = a.xy.distance(to: b.xy)
            guard len > Tolerance.length else { continue }
            var s = carry
            while s <= len {
                let p = a.lerp(to: b, t: s / len)
                mesh.append(Mesh.box(Box3(min: Vec3(p.x - bs / 2, p.y - bs / 2, p.z), max: Vec3(p.x + bs / 2, p.y + bs / 2, p.z + h - rs))))
                s += spacing
            }
            carry = s - len
        }
        return [MeshPart(mesh: mesh, materialID: mat)]
    }

    public static func length(_ e: Element, _ model: BIMModel) -> Double {
        let p = path(e, model)
        guard p.count >= 2 else { return 0 }
        return (0..<(p.count - 1)).reduce(0) { $0 + p[$1].distance(to: p[$1 + 1]) }
    }
}
