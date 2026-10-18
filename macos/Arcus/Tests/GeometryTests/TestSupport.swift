import Foundation
@testable import ArcusGeometry

/// Numeric comparison helper for tests.
func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }
func approx(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6) -> Bool { a.distance(to: b) <= tol }
func approx(_ a: Vec3, _ b: Vec3, _ tol: Double = 1e-6) -> Bool { a.distance(to: b) <= tol }

func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> Polygon2 {
    Polygon2([Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)])
}

func rectSegments(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Segment2] {
    rect(x0, y0, x1, y1).edges
}

/// Area covered by index triangles.
func triangleArea(_ pts: [Vec2], _ tris: [Int]) -> Double {
    var s = 0.0
    for t in stride(from: 0, to: tris.count, by: 3) {
        s += (pts[tris[t + 1]] - pts[tris[t]]).cross(pts[tris[t + 2]] - pts[tris[t]]) * 0.5
    }
    return s
}

/// Checks a closed mesh: every undirected edge (by welded position) is used by an even
/// number of triangles and every directed edge is matched by its reverse.
func isWatertight(_ m: Mesh) -> Bool {
    var welder = PointWelder3(tolerance: Tolerance.length)
    let ids = m.positions.map { welder.id(for: $0) }
    var directed: [SIMD2<Int>: Int] = [:]
    for t in stride(from: 0, to: m.indices.count, by: 3) {
        let a = ids[Int(m.indices[t])], b = ids[Int(m.indices[t + 1])], c = ids[Int(m.indices[t + 2])]
        if a == b || b == c || a == c { continue }
        for (u, v) in [(a, b), (b, c), (c, a)] { directed[SIMD2(u, v), default: 0] += 1 }
    }
    for (k, n) in directed where directed[SIMD2(k.y, k.x), default: 0] != n { return false }
    return true
}
