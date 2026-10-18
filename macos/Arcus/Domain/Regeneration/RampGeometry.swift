import Foundation
import ArcusGeometry

/// Computed ramp layout: sloped runs and flat landings in walking order from the bottom to the top.
public struct RampLayout: Sendable {
    public struct Piece: Sendable {
        /// Plan outline (counter-clockwise).
        public var polygon: Polygon2
        /// Centerline from the lower end to the upper end (a single point for corner landings).
        public var start: Vec2
        public var end: Vec2
        /// Top surface elevation at `start` and `end` (equal for landings).
        public var z0: Double
        public var z1: Double
        public var isLanding: Bool

        public var direction: Vec2 { (end - start).lengthSquared > 0 ? (end - start).normalized : .unitX }
        public var length: Double { start.distance(to: end) }
        /// Top surface as a height field.
        public var plane: PlaneZ {
            guard !isLanding, length > Tolerance.length else { return .flat(z0) }
            let d = direction * ((z1 - z0) / length)
            return PlaneZ(a: d.x, b: d.y, c: z0 - d.dot(start))
        }
    }

    public var pieces: [Piece]
    public var baseZ: Double
    public var topZ: Double
    public var width: Double
    /// Horizontal length of the sloped runs (landings excluded).
    public var slopedLength: Double
    /// Rise over sloped run.
    public var slope: Double
    /// The type's maximum slope (rise/run).
    public var maxSlope: Double
    /// Sloped run needed to climb the full height at the type's maximum slope.
    public var requiredLength: Double
    /// Centerline stations (plan point, top elevation, index of the path vertex when the station is one).
    public var stations: [(point: Vec2, z: Double, vertex: Int?)]
    public var warnings: [String]

    public var rise: Double { topZ - baseZ }
    /// True when the drawn run is too short for the type's maximum slope.
    public var isTooSteep: Bool { slope > maxSlope * (1 + 1e-6) + 1e-9 }
}

public enum RampGeometry {
    public static let maxSlopeParam = ParameterID("ramp.maxSlope")
    public static let maxRunParam = ParameterID("ramp.maxRunLength")
    public static let landingParam = ParameterID("ramp.landingLength")
    public static let shapeParam = ParameterID("ramp.shape")
    public static let thicknessParam = ParameterID("ramp.thickness")
    public static let minimumWidth = 0.6

    /// Default type values (1:12 slope, 9 m maximum incline length, 1.5 m landings, solid body).
    public static let defaultMaxSlope = 1.0 / 12.0
    public static let defaultMaxRun = 9.0
    public static let defaultLanding = 1.5
    public static let defaultThickness = 0.15

    /// Name and data of the default ramp type, created by the Ramp tool the first time a document needs one (templates
    /// don't carry it, so existing template content and element ids stay unchanged).
    public static let defaultTypeName = "Ramp 1:12"
    public static func defaultType(material: ElementID?) -> TypeData {
        TypeData(instanceCategory: .ramps, systemFamily: .ramp, familyName: "Ramp",
                 params: [maxSlopeParam: .double(defaultMaxSlope), maxRunParam: .double(defaultMaxRun), landingParam: .double(defaultLanding),
                          shapeParam: .text(RampShape.solid.rawValue), thicknessParam: .double(defaultThickness), ParameterID("type.material"): .ref(material)])
    }

    public static func maxSlope(_ e: Element, _ model: BIMModel) -> Double {
        let s = model.typeParam(e, maxSlopeParam)?.doubleValue ?? defaultMaxSlope
        return s > 1e-6 ? s : defaultMaxSlope
    }

    public static func shape(_ e: Element, _ model: BIMModel) -> RampShape {
        model.typeParam(e, shapeParam)?.textValue.flatMap(RampShape.init(rawValue:)) ?? .solid
    }

    /// Why a ramp can't be laid out, or nil when it can.
    public static func invalidReason(_ e: Element, _ model: BIMModel) -> String? {
        guard let r = e.ramp else { return "Not a ramp." }
        let path = cleaned(r.path)
        if path.count < 2 { return "A ramp needs a run of at least two points." }
        if r.width < minimumWidth - Tolerance.length { return "A ramp must be at least \(Int(minimumWidth * 1000)) mm wide." }
        if rise(e, model) <= 0.005 { return "The ramp needs a top above its base." }
        if layout(e, model) == nil { return "The run is too short for the ramp's width and turns. Draw longer runs." }
        return nil
    }

    static func cleaned(_ pts: [Vec2]) -> [Vec2] {
        var out: [Vec2] = []
        for p in pts where out.last.map({ !$0.isAlmostEqual(p, tolerance: 0.001) }) ?? true { out.append(p) }
        return out
    }

    static func rise(_ e: Element, _ model: BIMModel) -> Double {
        guard let r = e.ramp else { return 0 }
        let base = model.baseElevation(of: e)
        return model.topElevation(base: base, topLevelID: r.topLevelID, topOffset: r.topOffset, unconnectedHeight: r.unconnectedHeight) - base
    }

    public static func layout(_ e: Element, _ model: BIMModel) -> RampLayout? {
        guard let r = e.ramp else { return nil }
        let path = cleaned(r.path)
        guard path.count >= 2, r.width >= minimumWidth - Tolerance.length else { return nil }
        let base = model.baseElevation(of: e)
        let top = model.topElevation(base: base, topLevelID: r.topLevelID, topOffset: r.topOffset, unconnectedHeight: r.unconnectedHeight)
        let h = top - base
        guard h > 0.005 else { return nil }
        let w = r.width, half = w / 2
        let maxS = maxSlope(e, model)
        let maxRun = max(1.0, model.typeLength(e, maxRunParam, default: defaultMaxRun))
        let landing = max(0.3, model.typeLength(e, landingParam, default: defaultLanding))

        // Sloped sub-runs per segment (turn landings take half the width from each side of a corner).
        let n = path.count - 1
        var subRuns: [[(Vec2, Vec2)]] = []
        var landingsBetween: [[(Vec2, Vec2)]] = []
        var sloped = 0.0
        for i in 0..<n {
            let a = path[i], b = path[i + 1]
            let d = (b - a).normalized
            let s0 = i > 0 ? half : 0, s1 = i < n - 1 ? half : 0
            let runLen = a.distance(to: b) - s0 - s1
            guard runLen > -Tolerance.length else { return nil }
            var runs: [(Vec2, Vec2)] = []
            var lands: [(Vec2, Vec2)] = []
            if runLen > 0.01 {
                var k = 0
                while (runLen - Double(k) * landing) / Double(k + 1) > maxRun + Tolerance.length, runLen - Double(k + 1) * landing > 0.3 * Double(k + 2) { k += 1 }
                let each = (runLen - Double(k) * landing) / Double(k + 1)
                var p = a + d * s0
                for j in 0...k {
                    let q = p + d * each
                    runs.append((p, q))
                    sloped += each
                    p = q
                    if j < k { lands.append((p, p + d * landing)); p = p + d * landing }
                }
            }
            subRuns.append(runs)
            landingsBetween.append(lands)
        }
        guard sloped > 0.1 else { return nil }
        let slope = h / sloped

        var pieces: [RampLayout.Piece] = []
        var stations: [(point: Vec2, z: Double, vertex: Int?)] = [(path[0], base, 0)]
        var z = base
        for i in 0..<n {
            let d = (path[i + 1] - path[i]).normalized
            if i > 0 {
                let v = path[i]
                let dIn = (path[i] - path[i - 1]).normalized
                let hull = convexHull(square(v, dIn, half) + square(v, d, half))
                pieces.append(.init(polygon: hull, start: v, end: v, z0: z, z1: z, isLanding: true))
                stations.append((v, z, i))
            }
            let runs = subRuns[i], lands = landingsBetween[i]
            for (j, run) in runs.enumerated() {
                let len = run.0.distance(to: run.1)
                let z1 = z + slope * len
                pieces.append(.init(polygon: rect(run.0, run.1, half), start: run.0, end: run.1, z0: z, z1: z1, isLanding: false))
                stations.append((run.0, z, nil))
                stations.append((run.1, z1, nil))
                z = z1
                if j < lands.count {
                    let l = lands[j]
                    pieces.append(.init(polygon: rect(l.0, l.1, half), start: l.0, end: l.1, z0: z, z1: z, isLanding: true))
                    stations.append((l.1, z, nil))
                }
            }
        }
        stations.append((path[n], top, n))
        // Drop duplicate consecutive stations.
        var clean: [(point: Vec2, z: Double, vertex: Int?)] = []
        for s in stations {
            if let last = clean.last, last.point.isAlmostEqual(s.point, tolerance: 0.001), abs(last.z - s.z) < 1e-6 {
                if s.vertex != nil { clean[clean.count - 1].vertex = s.vertex }
                continue
            }
            clean.append(s)
        }

        let required = h / maxS
        var warnings: [String] = []
        if slope > maxS * (1 + 1e-6) + 1e-9 {
            warnings.append(String(format: "Ramp slope 1:%.1f is steeper than the type maximum of 1:%.1f. The ramp needs %.2f m of sloped run to reach its top; it has %.2f m.",
                                   1 / slope, 1 / maxS, required, sloped))
        }
        return RampLayout(pieces: pieces, baseZ: base, topZ: top, width: w, slopedLength: sloped, slope: slope, maxSlope: maxS,
                          requiredLength: required, stations: clean, warnings: warnings)
    }

    static func rect(_ a: Vec2, _ b: Vec2, _ half: Double) -> Polygon2 {
        let d = (b - a).normalized, n = d.perpendicular * half
        return Polygon2([a - n, b - n, b + n, a + n])
    }

    static func square(_ c: Vec2, _ d: Vec2, _ half: Double) -> [Vec2] {
        let n = d.perpendicular * half, t = d * half
        return [c - t - n, c + t - n, c + t + n, c - t + n]
    }

    /// Counter-clockwise convex hull (Andrew's monotone chain).
    static func convexHull(_ pts: [Vec2]) -> Polygon2 {
        let p = pts.sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        guard p.count > 2 else { return Polygon2(p) }
        func half(_ seq: [Vec2]) -> [Vec2] {
            var h: [Vec2] = []
            for q in seq {
                while h.count >= 2, (h[h.count - 1] - h[h.count - 2]).cross(q - h[h.count - 2]) <= 1e-12 { h.removeLast() }
                h.append(q)
            }
            return h
        }
        let lower = half(p), upper = half(p.reversed())
        return Polygon2(Array(lower.dropLast()) + Array(upper.dropLast()))
    }

    // MARK: 3D

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        guard let l = layout(e, model) else { return [] }
        let mat = model.typeParam(e, ParameterID("type.material"))?.refValue
        let thin = shape(e, model) == .thin
        let t = max(0.02, model.typeLength(e, thicknessParam, default: defaultThickness))
        var mesh = Mesh()
        for p in l.pieces {
            let top = p.plane
            let bottom = thin ? PlaneZ(a: top.a, b: top.b, c: top.c - t) : PlaneZ.flat(l.baseZ)
            if !thin && max(p.z0, p.z1) - l.baseZ < Tolerance.length { continue }
            mesh.append(MeshBuilder.slab(Profile2(outer: p.polygon.counterClockwise), bottom: bottom, top: top))
        }
        return [MeshPart(mesh: mesh, materialID: mat)]
    }

    // MARK: Plan

    /// Plan graphics: outline below the cut, outline above the cut (drawn hidden), a break line where the cut plane
    /// crosses a run, and the walk line from the bottom to the top.
    public static func planLines(_ e: Element, _ model: BIMModel, cutZ: Double) -> (below: [Segment2], above: [Segment2], walk: [Vec2], breakLine: Segment2?) {
        guard let l = layout(e, model) else { return ([], [], [], nil) }
        var below: [Segment2] = [], above: [Segment2] = []
        var brk: Segment2?
        let half = l.width / 2
        for p in l.pieces {
            let lo = min(p.z0, p.z1), hi = max(p.z0, p.z1)
            if hi <= cutZ + Tolerance.length {
                below += p.polygon.edges
            } else if lo >= cutZ - Tolerance.length {
                above += p.polygon.edges
            } else {
                // The cut crosses this run: split its outline at the cut station.
                let t = (cutZ - p.z0) / (p.z1 - p.z0)
                let c = p.start.lerp(to: p.end, t: t)
                let n = p.direction.perpendicular * half
                below += [Segment2(p.start - n, c - n), Segment2(p.start + n, c + n), Segment2(p.start - n, p.start + n)]
                above += [Segment2(c - n, p.end - n), Segment2(c + n, p.end + n), Segment2(p.end - n, p.end + n)]
                if brk == nil { brk = Segment2(c - n + p.direction * 0.15, c + n - p.direction * 0.15) }
            }
        }
        return (below, above, l.stations.map(\.point), brk)
    }

    // MARK: Railings

    /// Railing base line along one side of the ramp, following the top surface.
    public static func railingPath(_ e: Element, _ model: BIMModel, leftSide: Bool) -> [Vec3] {
        guard let l = layout(e, model), let r = e.ramp else { return [] }
        let path = cleaned(r.path)
        let s = (l.width / 2 - 0.05) * (leftSide ? 1 : -1)
        func normal(_ i: Int) -> Vec2 { (path[i + 1] - path[i]).normalized.perpendicular }
        var out: [Vec3] = []
        var segment = 0
        for st in l.stations {
            let offset: Vec2
            if let v = st.vertex, v > 0, v < path.count - 1 {
                let n1 = normal(v - 1), n2 = normal(v)
                let k = 1 + n1.dot(n2)
                offset = k > 1e-6 ? (n1 + n2) * (s / k) : n2 * s
                segment = v
            } else if let v = st.vertex {
                offset = normal(min(v, path.count - 2)) * s
            } else {
                // Station on a straight segment: find the segment containing it (stations are in walking order).
                while segment < path.count - 2, Segment2(path[segment], path[segment + 1]).distance(to: st.point) > 0.001 { segment += 1 }
                offset = normal(segment) * s
            }
            out.append(Vec3(st.point + offset, z: st.z))
        }
        return out
    }
}
