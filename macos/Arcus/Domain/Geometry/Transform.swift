import Foundation
import simd

/// 2D affine transform: p' = linear * p + translation.
/// Stored as a 2x2 matrix (a b; c d) and translation (tx, ty).
public struct Transform2: Hashable, Codable, Sendable {
    public var a: Double, b: Double, c: Double, d: Double
    public var tx: Double, ty: Double

    public init(a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double) {
        self.a = a; self.b = b; self.c = c; self.d = d; self.tx = tx; self.ty = ty
    }

    public static let identity = Transform2(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0)

    public static func translation(_ v: Vec2) -> Transform2 { Transform2(a: 1, b: 0, c: 0, d: 1, tx: v.x, ty: v.y) }
    public static func rotation(_ angle: Double, around p: Vec2 = .zero) -> Transform2 {
        let cs = cos(angle), sn = sin(angle)
        let r = Transform2(a: cs, b: -sn, c: sn, d: cs, tx: 0, ty: 0)
        return .translation(p) * r * .translation(-p)
    }
    public static func scale(_ sx: Double, _ sy: Double, around p: Vec2 = .zero) -> Transform2 {
        .translation(p) * Transform2(a: sx, b: 0, c: 0, d: sy, tx: 0, ty: 0) * .translation(-p)
    }
    /// Reflection across the line through `p` with direction `dir`.
    public static func mirror(through p: Vec2, direction dir: Vec2) -> Transform2 {
        let u = dir.normalized
        let m = Transform2(a: u.x * u.x * 2 - 1, b: 2 * u.x * u.y, c: 2 * u.x * u.y, d: u.y * u.y * 2 - 1, tx: 0, ty: 0)
        return .translation(p) * m * .translation(-p)
    }

    public func apply(_ p: Vec2) -> Vec2 { Vec2(a * p.x + b * p.y + tx, c * p.x + d * p.y + ty) }
    public func applyVector(_ v: Vec2) -> Vec2 { Vec2(a * v.x + b * v.y, c * v.x + d * v.y) }
    public var determinant: Double { a * d - b * c }
    public var isMirroring: Bool { determinant < 0 }
    /// Rotation angle of the linear part (valid for rigid / uniform-scale transforms).
    public var rotationAngle: Double { atan2(c, a) }
    public var uniformScale: Double { abs(determinant).squareRoot() }

    public var inverse: Transform2 {
        let det = determinant
        guard abs(det) > 1e-300 else { return .identity }
        let ia = d / det, ib = -b / det, ic = -c / det, id = a / det
        return Transform2(a: ia, b: ib, c: ic, d: id, tx: -(ia * tx + ib * ty), ty: -(ic * tx + id * ty))
    }

    /// Composition: (l * r).apply(p) == l.apply(r.apply(p)).
    public static func * (l: Transform2, r: Transform2) -> Transform2 {
        Transform2(
            a: l.a * r.a + l.b * r.c, b: l.a * r.b + l.b * r.d,
            c: l.c * r.a + l.d * r.c, d: l.c * r.b + l.d * r.d,
            tx: l.a * r.tx + l.b * r.ty + l.tx, ty: l.c * r.tx + l.d * r.ty + l.ty)
    }
}

/// 3D rigid/affine transform backed by a double-precision 4x4 matrix (column-major, simd).
public struct Transform3: Hashable, Sendable {
    public var matrix: simd_double4x4

    public init(_ m: simd_double4x4) { matrix = m }
    public static let identity = Transform3(matrix_identity_double4x4)

    public static func translation(_ v: Vec3) -> Transform3 {
        var m = matrix_identity_double4x4
        m.columns.3 = SIMD4(v.x, v.y, v.z, 1)
        return Transform3(m)
    }
    public static func rotationZ(_ a: Double) -> Transform3 {
        let c = cos(a), s = sin(a)
        return Transform3(simd_double4x4(columns: (SIMD4(c, s, 0, 0), SIMD4(-s, c, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1))))
    }
    public static func rotation(axis: Vec3, angle: Double) -> Transform3 {
        let q = simd_quatd(angle: angle, axis: SIMD3(axis.x, axis.y, axis.z).normalizedSafe)
        return Transform3(simd_double4x4(q))
    }
    public static func scale(_ s: Vec3) -> Transform3 {
        Transform3(simd_double4x4(diagonal: SIMD4(s.x, s.y, s.z, 1)))
    }
    /// Frame with origin and orthonormal axes (x, y, z = x × y).
    public static func frame(origin: Vec3, xAxis: Vec3, yAxis: Vec3) -> Transform3 {
        let x = xAxis.normalized, y = yAxis.normalized, z = x.cross(y).normalized
        return Transform3(simd_double4x4(columns: (
            SIMD4(x.x, x.y, x.z, 0), SIMD4(y.x, y.y, y.z, 0), SIMD4(z.x, z.y, z.z, 0), SIMD4(origin.x, origin.y, origin.z, 1))))
    }
    /// Lifts a 2D plan transform into 3D (acting in XY, preserving Z).
    public init(_ t: Transform2, z: Double = 0) {
        matrix = simd_double4x4(columns: (
            SIMD4(t.a, t.c, 0, 0), SIMD4(t.b, t.d, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(t.tx, t.ty, z, 1)))
    }

    public func apply(_ p: Vec3) -> Vec3 {
        let r = matrix * SIMD4(p.x, p.y, p.z, 1)
        return Vec3(r.x, r.y, r.z)
    }
    public func applyVector(_ v: Vec3) -> Vec3 {
        let r = matrix * SIMD4(v.x, v.y, v.z, 0)
        return Vec3(r.x, r.y, r.z)
    }
    public var inverse: Transform3 { Transform3(matrix.inverse) }
    public var origin: Vec3 { Vec3(matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z) }
    public var xAxis: Vec3 { Vec3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z) }
    public var yAxis: Vec3 { Vec3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z) }
    public var zAxis: Vec3 { Vec3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z) }
    public var determinant: Double { matrix.determinant }

    public static func * (l: Transform3, r: Transform3) -> Transform3 { Transform3(l.matrix * r.matrix) }

    public static func == (l: Transform3, r: Transform3) -> Bool { l.matrix == r.matrix }
    public func hash(into h: inout Hasher) {
        for c in 0..<4 { for r in 0..<4 { h.combine(matrix[c][r]) } }
    }
}

extension Transform3: Codable {
    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var m = matrix_identity_double4x4
        for col in 0..<4 { for row in 0..<4 { m[col][row] = try c.decode(Double.self) } }
        matrix = m
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.unkeyedContainer()
        for col in 0..<4 { for row in 0..<4 { try c.encode(matrix[col][row]) } }
    }
}

extension SIMD3 where Scalar == Double {
    var normalizedSafe: SIMD3<Double> {
        let l = simd_length(self)
        return l > 0 ? self / l : SIMD3(0, 0, 1)
    }
}

/// An oriented plane: origin + unit normal, with an in-plane basis for 2D mapping.
public struct Plane3: Hashable, Codable, Sendable {
    public var origin: Vec3
    public var normal: Vec3
    public var xAxis: Vec3

    public init(origin: Vec3, normal: Vec3, xAxis: Vec3? = nil) {
        self.origin = origin
        let n = normal.normalized
        self.normal = n
        var x = xAxis ?? n.anyPerpendicular
        x = (x - n * x.dot(n)).normalized
        self.xAxis = x.lengthSquared > 0 ? x : n.anyPerpendicular
    }
    public var yAxis: Vec3 { normal.cross(xAxis) }

    public static func horizontal(z: Double) -> Plane3 { Plane3(origin: Vec3(0, 0, z), normal: .unitZ, xAxis: .unitX) }

    /// Signed distance of p above the plane.
    public func signedDistance(_ p: Vec3) -> Double { (p - origin).dot(normal) }
    public func project(_ p: Vec3) -> Vec3 { p - normal * signedDistance(p) }
    /// Maps a 3D point into plane coordinates (u along xAxis, v along yAxis).
    public func toPlane(_ p: Vec3) -> Vec2 { let d = p - origin; return Vec2(d.dot(xAxis), d.dot(yAxis)) }
    public func fromPlane(_ uv: Vec2, offset: Double = 0) -> Vec3 { origin + xAxis * uv.x + yAxis * uv.y + normal * offset }
    public var frame: Transform3 { .frame(origin: origin, xAxis: xAxis, yAxis: yAxis) }
}
