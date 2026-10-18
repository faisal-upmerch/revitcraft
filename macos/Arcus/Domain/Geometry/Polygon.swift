import Foundation

/// A simple closed polygon (implicitly closed; last point != first point).
public struct Polygon2: Hashable, Codable, Sendable {
    public var points: [Vec2]

    public init(_ points: [Vec2]) {
        var pts = points
        if pts.count > 1, pts[0].isAlmostEqual(pts[pts.count - 1]) { pts.removeLast() }
        self.points = pts
    }

    public static func rectangle(_ r: Rect2) -> Polygon2 { Polygon2(r.corners) }

    public var count: Int { points.count }
    public var isEmpty: Bool { points.count < 3 }

    /// Signed area (positive for counter-clockwise).
    public var signedArea: Double {
        guard points.count >= 3 else { return 0 }
        var s = 0.0
        var j = points.count - 1
        for i in 0..<points.count {
            s += points[j].x * points[i].y - points[i].x * points[j].y
            j = i
        }
        return s * 0.5
    }
    public var area: Double { abs(signedArea) }
    public var isCounterClockwise: Bool { signedArea > 0 }
    public var isDegenerate: Bool { area <= Tolerance.area }
    public var perimeter: Double {
        guard points.count >= 2 else { return 0 }
        var s = 0.0
        for i in 0..<points.count { s += points[i].distance(to: points[(i + 1) % points.count]) }
        return s
    }
    public var bounds: Rect2 { Rect2(points: points) }
    public var edges: [Segment2] {
        guard points.count >= 2 else { return [] }
        return (0..<points.count).map { Segment2(points[$0], points[($0 + 1) % points.count]) }
    }
    public var centroid: Vec2 {
        let a = signedArea
        guard abs(a) > Tolerance.area else {
            return points.isEmpty ? .zero : points.reduce(.zero, +) / Double(points.count)
        }
        var cx = 0.0, cy = 0.0
        var j = points.count - 1
        for i in 0..<points.count {
            let f = points[j].x * points[i].y - points[i].x * points[j].y
            cx += (points[j].x + points[i].x) * f
            cy += (points[j].y + points[i].y) * f
            j = i
        }
        return Vec2(cx / (6 * a), cy / (6 * a))
    }
    public var counterClockwise: Polygon2 { isCounterClockwise ? self : reversed }
    public var clockwise: Polygon2 { isCounterClockwise ? reversed : self }
    public var reversed: Polygon2 { Polygon2(points.reversed()) }
    public func transformed(_ t: Transform2) -> Polygon2 {
        let p = Polygon2(points.map(t.apply))
        return p
    }

    /// Even-odd point containment. Points on the boundary (within tolerance) return `onBoundary`.
    public func contains(_ p: Vec2, onBoundary: Bool = true) -> Bool {
        guard points.count >= 3 else { return false }
        for e in edges where e.distance(to: p) <= Tolerance.length { return onBoundary }
        var inside = false
        var j = points.count - 1
        for i in 0..<points.count {
            let pi = points[i], pj = points[j]
            if (pi.y > p.y) != (pj.y > p.y) {
                let x = (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
    public func distanceToBoundary(_ p: Vec2) -> Double {
        edges.map { $0.distance(to: p) }.min() ?? .infinity
    }
    /// True if every interior angle turns the same way.
    public var isConvex: Bool {
        guard points.count >= 3 else { return false }
        var sign = 0.0
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count], c = points[(i + 2) % points.count]
            let cr = (b - a).cross(c - b)
            if abs(cr) <= Tolerance.lengthSquared { continue }
            if sign == 0 { sign = cr } else if sign * cr < 0 { return false }
        }
        return true
    }
    /// Removes consecutive duplicates and collinear midpoints.
    public func simplified() -> Polygon2 {
        var pts: [Vec2] = []
        for p in points where pts.last.map({ !$0.isAlmostEqual(p) }) ?? true { pts.append(p) }
        if pts.count > 1, pts[0].isAlmostEqual(pts[pts.count - 1]) { pts.removeLast() }
        var changed = true
        while changed && pts.count > 3 {
            changed = false
            for i in 0..<pts.count {
                let a = pts[(i + pts.count - 1) % pts.count], b = pts[i], c = pts[(i + 1) % pts.count]
                if Segment2(a, c).distance(to: b) <= Tolerance.length {
                    pts.remove(at: i); changed = true; break
                }
            }
        }
        return Polygon2(pts)
    }
    /// True if no two non-adjacent edges intersect.
    public var isSimple: Bool {
        let es = edges
        let n = es.count
        guard n >= 3 else { return false }
        for i in 0..<n {
            for j in (i + 1)..<n {
                if j == i + 1 || (i == 0 && j == n - 1) { continue }
                if es[i].intersection(es[j]) != nil { return false }
            }
        }
        return true
    }
}

/// A polygon with holes: one outer boundary (CCW) and zero or more inner loops (CW).
public struct Profile2: Hashable, Codable, Sendable {
    public var outer: Polygon2
    public var holes: [Polygon2]

    public init(outer: Polygon2, holes: [Polygon2] = []) {
        self.outer = outer.counterClockwise
        self.holes = holes.map(\.clockwise)
    }
    public var area: Double { outer.area - holes.reduce(0) { $0 + $1.area } }
    public var perimeter: Double { outer.perimeter + holes.reduce(0) { $0 + $1.perimeter } }
    public var bounds: Rect2 { outer.bounds }
    public func contains(_ p: Vec2) -> Bool {
        outer.contains(p) && !holes.contains { $0.contains(p, onBoundary: false) }
    }
    public func transformed(_ t: Transform2) -> Profile2 {
        Profile2(outer: outer.transformed(t), holes: holes.map { $0.transformed(t) })
    }
    public var loops: [Polygon2] { [outer] + holes }
}
