import Foundation
import ArcusGeometry
import ArcusCalc

// W2-DWG: site modelling — Site Settings, survey point files, toposurface editing (split, merge, sub-regions, graded
// regions, contour labels) and parking layouts.

// MARK: - Site Settings

/// Project-wide contour display settings, stored as parameters of the Project Information element.
public struct SiteSettings: Sendable, Hashable {
    /// Distance between contour lines (meters).
    public var contourInterval: Double
    /// Every Nth contour is a primary (heavier) contour.
    public var primaryEvery: Int
    public var showContours: Bool

    public static let intervalKey = ParameterID("site.contourInterval")
    public static let primaryEveryKey = ParameterID("site.primaryEvery")
    public static let showContoursKey = ParameterID("site.showContours")

    public init(contourInterval: Double, primaryEvery: Int, showContours: Bool = true) {
        self.contourInterval = contourInterval; self.primaryEvery = primaryEvery; self.showContours = showContours
    }

    /// Metric: 0.5 m with a primary every 2.5 m. Imperial: 1'-0" with a primary every 5'-0".
    public static func defaults(for system: UnitSystem) -> SiteSettings {
        system == .imperial ? SiteSettings(contourInterval: 0.3048, primaryEvery: 5) : SiteSettings(contourInterval: 0.5, primaryEvery: 5)
    }

    public init(_ model: BIMModel) {
        var s = SiteSettings.defaults(for: model.units.system)
        if let p = model.projectInfoElement?.params {
            if let v = p[Self.intervalKey]?.doubleValue, v.isFinite, v >= 0.01 { s.contourInterval = v }
            if let v = p[Self.primaryEveryKey]?.intValue, v >= 1 { s.primaryEvery = min(v, 100) }
            if let v = p[Self.showContoursKey]?.boolValue { s.showContours = v }
        }
        self = s
    }

    /// Writes the settings onto the Project Information element.
    public func write(to e: inout Element) {
        e.params[Self.intervalKey] = .double(contourInterval)
        e.params[Self.primaryEveryKey] = .int(primaryEvery)
        e.params[Self.showContoursKey] = .bool(showContours)
    }

    public var primaryInterval: Double { contourInterval * Double(max(1, primaryEvery)) }
    public func isPrimary(_ z: Double) -> Bool {
        let step = primaryInterval
        guard step > 0 else { return false }
        return abs((z / step).rounded() * step - z) < 1e-6 * max(1, abs(z))
    }
}

// MARK: - Survey point files

/// Reads CSV / XYZ / TXT survey point files: one point per line, "x, y, z" (comma, semicolon, tab or space separated),
/// optionally with a leading point name or number ("P12, x, y, z"). Header and comment lines are skipped.
public enum SitePointFile {
    public struct Result: Sendable {
        public var points: [Vec3]
        /// 1-based numbers of lines that were not blank or comments but could not be read.
        public var skippedLines: [Int]
    }

    /// `scale` converts file units to meters (1 for meters, 0.3048 for feet, 0.001 for millimeters).
    public static func parse(_ text: String, scale: Double = 1, maxPoints: Int = 200_000) -> Result {
        var pts: [Vec3] = []
        var skipped: [Int] = []
        var lineNo = 0
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }) {
            lineNo += 1
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") || line.hasPrefix(";") { continue }
            let fields = line.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "\t" || $0 == " " }).map(String.init).filter { !$0.isEmpty }
            let numbers = fields.map { Double($0) }
            var xyz: [Double]?
            if numbers.count >= 3, numbers.prefix(3).allSatisfy({ $0 != nil }) {
                // x y z [extra columns]; four numeric columns with an integer first = point number, x, y, z.
                if numbers.count == 4, numbers.allSatisfy({ $0 != nil }), let n = numbers[0], n == n.rounded(), abs(n) < 1e7,
                   fields[0].allSatisfy({ $0.isNumber }) {
                    xyz = numbers[1...3].map { $0! }
                } else {
                    xyz = numbers.prefix(3).map { $0! }
                }
            } else if numbers.count >= 4, numbers[0] == nil, numbers[1...3].allSatisfy({ $0 != nil }) {
                xyz = numbers[1...3].map { $0! }   // name, x, y, z
            }
            guard let v = xyz, v.allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else {
                if pts.isEmpty && skipped.isEmpty && fields.contains(where: { Double($0) == nil }) { continue } // header line
                skipped.append(lineNo); continue
            }
            pts.append(Vec3(v[0] * scale, v[1] * scale, v[2] * scale))
            if pts.count >= maxPoints { break }
        }
        return Result(points: pts, skippedLines: skipped)
    }
}

// MARK: - Toposurface editing

public enum SiteEditing {
    /// Sub-regions are drawn this far above their host so the two surfaces never fight in 3D.
    public static let subregionLift = 0.005

    /// Keeps triangles whose centroid lies inside `boundary`.
    public static func clip(triangles tri: [Int], points pts: [Vec3], to boundary: Polygon2) -> [Int] {
        var out: [Int] = []
        for i in stride(from: 0, to: tri.count - 2, by: 3) {
            let c = (pts[tri[i]].xy + pts[tri[i + 1]].xy + pts[tri[i + 2]].xy) / 3
            if boundary.contains(c, onBoundary: false) { out += [tri[i], tri[i + 1], tri[i + 2]] }
        }
        return out
    }

    /// Elevation of the triangulated surface at `p`, or nil outside it.
    public static func surfaceZ(_ pts: [Vec3], at p: Vec2, triangles: [Int]? = nil) -> Double? {
        let tri = triangles ?? TopographyGeometry.triangulate(pts)
        for i in stride(from: 0, to: tri.count - 2, by: 3) {
            let a = pts[tri[i]], b = pts[tri[i + 1]], c = pts[tri[i + 2]]
            let d = (b.xy - a.xy).cross(c.xy - a.xy)
            guard abs(d) > 1e-15 else { continue }
            let u = (p - a.xy).cross(c.xy - a.xy) / d
            let v = (b.xy - a.xy).cross(p - a.xy) / d
            if u >= -1e-9, v >= -1e-9, u + v <= 1 + 1e-9 { return a.z + u * (b.z - a.z) + v * (c.z - a.z) }
        }
        return nil
    }

    /// Elevation at `p`, falling back to the nearest survey point outside the surface.
    public static func elevation(_ pts: [Vec3], at p: Vec2, triangles: [Int]? = nil) -> Double {
        if let z = surfaceZ(pts, at: p, triangles: triangles) { return z }
        return pts.min { $0.xy.distanceSquared(to: p) < $1.xy.distanceSquared(to: p) }?.z ?? 0
    }

    /// Points where `path` crosses the triangulation's edges, with interpolated elevations.
    static func crossings(_ pts: [Vec3], tri: [Int], path: [Vec2]) -> [Vec3] {
        var out: [Vec3] = []
        var seen = Set<UInt64>()
        for i in stride(from: 0, to: tri.count - 2, by: 3) {
            for (a, b) in [(tri[i], tri[i + 1]), (tri[i + 1], tri[i + 2]), (tri[i + 2], tri[i])] {
                let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
                guard seen.insert(key).inserted else { continue }
                let e = Segment2(pts[a].xy, pts[b].xy)
                for k in 0..<(path.count - 1) {
                    let s = Segment2(path[k], path[k + 1])
                    guard let (t, _) = intersect(e, s) else { continue }
                    out.append(pts[a].lerp(to: pts[b], t: t))
                }
            }
        }
        return out
    }

    /// Parameters (t on a, u on b) of the proper intersection of two segments.
    static func intersect(_ a: Segment2, _ b: Segment2) -> (Double, Double)? {
        let r = a.vector, s = b.vector
        let den = r.cross(s)
        guard abs(den) > 1e-15 else { return nil }
        let q = b.start - a.start
        let t = q.cross(s) / den, u = q.cross(r) / den
        guard t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        return (min(1, max(0, t)), min(1, max(0, u)))
    }

    /// Removes points closer than `tolerance` in plan to an earlier point.
    public static func dedupe(_ pts: [Vec3], tolerance: Double = 0.001) -> [Vec3] {
        var out: [Vec3] = []
        var grid: [Int64: [Int]] = [:]
        let cell = max(tolerance, 1e-6) * 4
        func key(_ x: Int64, _ y: Int64) -> Int64 { x &* 73_856_093 ^ y &* 19_349_663 }
        for p in pts {
            let cx = Int64((p.x / cell).rounded(.down)), cy = Int64((p.y / cell).rounded(.down))
            var dup = false
            outer: for dx in -1...1 { for dy in -1...1 {
                for j in grid[key(cx + Int64(dx), cy + Int64(dy))] ?? [] where out[j].xy.distance(to: p.xy) < tolerance { dup = true; break outer }
            } }
            if dup { continue }
            grid[key(cx, cy), default: []].append(out.count)
            out.append(p)
        }
        return out
    }

    /// Thins a point cloud to at most `maxPoints` by keeping one point per grid cell (the first one), so contour data
    /// with thousands of vertices stays fast to triangulate.
    public static func thin(_ pts: [Vec3], maxPoints: Int) -> [Vec3] {
        let unique = dedupe(pts)
        guard unique.count > maxPoints, maxPoints >= 3 else { return unique }
        let b = Rect2(points: unique.map(\.xy))
        var cell = sqrt(max(b.width * b.height, 1e-6) / Double(maxPoints))
        var out = unique
        for _ in 0..<12 {
            var seen = Set<Int64>()
            out = unique.filter { p in
                let k = Int64(((p.x - b.min.x) / cell).rounded(.down)) &* 1_000_003 &+ Int64(((p.y - b.min.y) / cell).rounded(.down))
                return seen.insert(k).inserted
            }
            if out.count <= maxPoints { break }
            cell *= 1.3
        }
        return out
    }

    /// Splits a surface along a line or polyline. Each side keeps its own points plus the points where the split line
    /// crosses the surface, so the two halves meet exactly. Nil when the line doesn't divide the surface.
    public static func split(_ pts: [Vec3], along path: [Vec2]) -> (left: [Vec3], right: [Vec3])? {
        guard path.count >= 2, pts.count >= 3 else { return nil }
        let tri = TopographyGeometry.triangulate(pts)
        // Extend the ends of the split line well past the surface so it cuts right through.
        let b = Rect2(points: pts.map(\.xy))
        let reach = (b.width + b.height) * 2 + 1
        var ext = path
        ext[0] = path[0] - (path[1] - path[0]).normalized * reach
        ext[ext.count - 1] = path[path.count - 1] + (path[path.count - 1] - path[path.count - 2]).normalized * reach
        func side(_ p: Vec2) -> Double {
            // Signed distance to the nearest segment of the extended polyline.
            var best = Double.infinity, sign = 1.0
            for k in 0..<(ext.count - 1) {
                let s = Segment2(ext[k], ext[k + 1])
                let d = s.distance(to: p)
                if d < best { best = d; sign = s.direction.cross(p - s.start) >= 0 ? 1 : -1 }
            }
            return sign * best
        }
        let cut = crossings(pts, tri: tri, path: ext)
        var left: [Vec3] = [], right: [Vec3] = []
        for p in pts {
            let s = side(p.xy)
            if abs(s) < 1e-6 { left.append(p); right.append(p) } else if s > 0 { left.append(p) } else { right.append(p) }
        }
        left = dedupe(left + cut)
        right = dedupe(right + cut)
        guard left.count >= 3, right.count >= 3, left.count > cut.count, right.count > cut.count else { return nil }
        return (left, right)
    }

    /// Merges two surfaces' points (points of `b` within 1 mm of a point of `a` are dropped).
    public static func merge(_ a: [Vec3], _ b: [Vec3]) -> [Vec3] { dedupe(a + b) }

    /// Points of a sub-region: the host's points inside the boundary, the boundary vertices at the host's elevation, and
    /// the points where the boundary crosses the host's triangulation.
    public static func subregionPoints(host pts: [Vec3], boundary: Polygon2) -> [Vec3] {
        let tri = TopographyGeometry.triangulate(pts)
        let loop = boundary.points + [boundary.points[0]]
        let inside = pts.filter { boundary.contains($0.xy, onBoundary: false) }
        let vertices = boundary.points.map { Vec3($0, z: elevation(pts, at: $0, triangles: tri)) }
        return dedupe(vertices + crossings(pts, tri: tri, path: loop) + inside)
    }

    /// A contour label: where a labelling line crosses a contour.
    public struct ContourLabel: Sendable, Hashable {
        public var position: Vec2
        public var elevation: Double
        /// Direction of the contour at the label (radians), turned to read left to right.
        public var rotation: Double
        public var isPrimary: Bool
    }

    /// Labels where `line` crosses the surface's contours (primary contours only when `primaryOnly`).
    public static func contourLabels(_ e: Element, settings: SiteSettings, line: Segment2, primaryOnly: Bool = false) -> [ContourLabel] {
        var out: [ContourLabel] = []
        for (z, seg) in TopographyGeometry.contours(e, interval: settings.contourInterval) {
            let primary = settings.isPrimary(z)
            if primaryOnly && !primary { continue }
            guard let (t, _) = intersect(line, seg) else { continue }
            var a = seg.direction.angle
            if a > .pi / 2 { a -= .pi } else if a < -.pi / 2 { a += .pi }
            let p = line.point(at: t)
            if out.contains(where: { abs($0.elevation - z) < 1e-9 && $0.position.distance(to: p) < 1e-6 }) { continue }
            out.append(ContourLabel(position: p, elevation: z, rotation: a, isPrimary: primary))
        }
        return out.sorted { line.parameter(of: $0.position) < line.parameter(of: $1.position) }
    }
}

// MARK: - Parking layout

/// Painted parking stalls generated inside a boundary.
public enum ParkingLayout {
    public struct Parameters: Sendable, Hashable {
        /// Angle between the stalls and the aisle, in degrees (90, 60 or 45).
        public var angle: Double
        /// Stall width measured perpendicular to its stripes.
        public var stallWidth: Double
        /// Length of the stall stripes.
        public var stallDepth: Double
        public var aisleWidth: Double
        public var wheelStops: Bool
        public init(angle: Double = 90, stallWidth: Double, stallDepth: Double, aisleWidth: Double, wheelStops: Bool = false) {
            self.angle = angle; self.stallWidth = stallWidth; self.stallDepth = stallDepth; self.aisleWidth = aisleWidth; self.wheelStops = wheelStops
        }
        /// 9' × 18' stalls with a 24' aisle (imperial) or 2.5 × 5.0 m stalls with a 6.0 m aisle (metric), at 90°.
        public static func defaults(for system: UnitSystem, angle: Double = 90) -> Parameters {
            var p = system == .imperial
                ? Parameters(angle: angle, stallWidth: 9 * 0.3048, stallDepth: 18 * 0.3048, aisleWidth: 24 * 0.3048)
                : Parameters(angle: angle, stallWidth: 2.5, stallDepth: 5.0, aisleWidth: 6.0)
            p.aisleWidth = recommendedAisle(for: system, angle: angle)
            return p
        }
        /// One-way aisles are narrower for angled parking: 24'/18'/13' or 6.0/5.5/4.0 m for 90°/60°/45°.
        public static func recommendedAisle(for system: UnitSystem, angle: Double) -> Double {
            let a = angle.rounded()
            if system == .imperial { return (a >= 90 ? 24 : a >= 60 ? 18 : 13) * 0.3048 }
            return a >= 90 ? 6.0 : a >= 60 ? 5.5 : 4.0
        }
    }

    public struct Result: Sendable {
        public var stripes: [Segment2] = []
        public var wheelStops: [Segment2] = []
        /// Stall outlines (parallelograms), for previews and tests.
        public var stalls: [[Vec2]] = []
        public var stallCount: Int { stalls.count }
        public var rows = 0
    }

    /// Fills `boundary` with double-loaded bays (stall row, aisle, stall row) parallel to its longest edge. A stall is kept
    /// only when it lies entirely inside the boundary.
    public static func generate(boundary: Polygon2, _ p: Parameters) -> Result {
        var r = Result()
        let poly = boundary.simplified().counterClockwise
        let theta = max(30, min(90, p.angle)) * .pi / 180
        guard poly.count >= 3, !poly.isDegenerate, p.stallWidth > 0.1, p.stallDepth > 0.1, p.aisleWidth >= 0 else { return r }
        // Local frame: x along the longest edge.
        guard let longest = poly.edges.max(by: { $0.length < $1.length }) else { return r }
        let ux = longest.direction, uy = ux.perpendicular
        let origin = longest.start
        func toLocal(_ q: Vec2) -> Vec2 { Vec2((q - origin).dot(ux), (q - origin).dot(uy)) }
        func toWorld(_ q: Vec2) -> Vec2 { origin + ux * q.x + uy * q.y }
        let local = Polygon2(poly.points.map(toLocal))
        let b = local.bounds
        let rowDepth = p.stallDepth * sin(theta)          // perpendicular extent of a stall row
        let pitch = p.stallWidth / sin(theta)             // stall spacing along the aisle
        let lean = p.stallDepth * cos(theta)              // x shift of the stripe from back to front
        let eps = 1e-6
        func inside(_ pts: [Vec2]) -> Bool { pts.allSatisfy { local.contains($0) } }

        /// Adds one row. `back` is the y of the stall backs; `dir` +1 when the aisle is above (+y), −1 when below.
        func row(back: Double, dir: Double) {
            var added = 0
            var x = b.min.x
            let front = back + dir * rowDepth
            // Mirrored rows keep the same lean along the aisle, so both rows are entered in the same direction (one-way aisle).
            while x + pitch <= b.max.x + eps {
                let b0 = Vec2(x, back), b1 = Vec2(x + pitch, back)
                let f0 = Vec2(x + lean, front), f1 = Vec2(x + pitch + lean, front)
                let quad = [b0, b1, f1, f0]
                if inside(quad) {
                    r.stalls.append(quad.map(toWorld))
                    added += 1
                    for s in [Segment2(b0, f0), Segment2(b1, f1)] {
                        let w = Segment2(toWorld(s.start), toWorld(s.end))
                        if !r.stripes.contains(where: { $0.start.isAlmostEqual(w.start, tolerance: 1e-6) && $0.end.isAlmostEqual(w.end, tolerance: 1e-6) }) {
                            r.stripes.append(w)
                        }
                    }
                    if p.wheelStops {
                        // 0.6 m (2') in from the back, 1.8 m (6') long (at most 75 % of the stall), parallel to the back.
                        let axis = (f0 - b0).normalized
                        let mid = b0.midpoint(b1) + axis * min(0.6, p.stallDepth * 0.2)
                        let half = min(1.8, p.stallWidth * 0.75) / 2 / sin(theta)
                        r.wheelStops.append(Segment2(toWorld(mid - Vec2(half, 0)), toWorld(mid + Vec2(half, 0))))
                    }
                }
                x += pitch
            }
            if added > 0 { r.rows += 1 }
        }

        // Bays: a row facing up into the aisle, the aisle, and a row facing down; the next bay starts back to back.
        var y = b.min.y
        while y + rowDepth + p.aisleWidth <= b.max.y + eps || (r.rows == 0 && y + rowDepth <= b.max.y + eps) {
            row(back: y, dir: 1)
            let aisleTop = y + rowDepth + p.aisleWidth
            guard aisleTop + rowDepth <= b.max.y + eps else { break }
            row(back: aisleTop + rowDepth, dir: -1)
            y = aisleTop + rowDepth
            if r.rows == 0 { break }
        }
        return r
    }
}
