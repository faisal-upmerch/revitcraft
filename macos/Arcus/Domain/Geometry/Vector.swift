import Foundation

/// A 2D point or vector in model meters.
public struct Vec2: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double

    @inlinable public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    @inlinable public init(x: Double, y: Double) { self.x = x; self.y = y }

    public static let zero = Vec2(0, 0)
    public static let unitX = Vec2(1, 0)
    public static let unitY = Vec2(0, 1)

    @inlinable public var length: Double { (x * x + y * y).squareRoot() }
    @inlinable public var lengthSquared: Double { x * x + y * y }
    @inlinable public var normalized: Vec2 {
        let l = length
        return l > 0 ? Vec2(x / l, y / l) : .zero
    }
    /// Counter-clockwise perpendicular.
    @inlinable public var perpendicular: Vec2 { Vec2(-y, x) }
    @inlinable public var angle: Double { atan2(y, x) }
    @inlinable public static func fromAngle(_ a: Double, length: Double = 1) -> Vec2 { Vec2(cos(a) * length, sin(a) * length) }

    @inlinable public func dot(_ o: Vec2) -> Double { x * o.x + y * o.y }
    /// 2D cross product (z of the 3D cross).
    @inlinable public func cross(_ o: Vec2) -> Double { x * o.y - y * o.x }
    @inlinable public func distance(to o: Vec2) -> Double { (self - o).length }
    @inlinable public func distanceSquared(to o: Vec2) -> Double { (self - o).lengthSquared }
    @inlinable public func isAlmostEqual(_ o: Vec2, tolerance: Double = Tolerance.length) -> Bool {
        distanceSquared(to: o) <= tolerance * tolerance
    }
    @inlinable public func rotated(by a: Double) -> Vec2 {
        let c = cos(a), s = sin(a)
        return Vec2(x * c - y * s, x * s + y * c)
    }
    @inlinable public func rotated(by a: Double, around p: Vec2) -> Vec2 { (self - p).rotated(by: a) + p }
    @inlinable public func lerp(to o: Vec2, t: Double) -> Vec2 { Vec2(x + (o.x - x) * t, y + (o.y - y) * t) }
    @inlinable public func midpoint(_ o: Vec2) -> Vec2 { Vec2((x + o.x) * 0.5, (y + o.y) * 0.5) }
    @inlinable public var xy0: Vec3 { Vec3(x, y, 0) }
    @inlinable public func at(z: Double) -> Vec3 { Vec3(x, y, z) }

    @inlinable public static func + (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x + b.x, a.y + b.y) }
    @inlinable public static func - (a: Vec2, b: Vec2) -> Vec2 { Vec2(a.x - b.x, a.y - b.y) }
    @inlinable public static func * (a: Vec2, s: Double) -> Vec2 { Vec2(a.x * s, a.y * s) }
    @inlinable public static func * (s: Double, a: Vec2) -> Vec2 { Vec2(a.x * s, a.y * s) }
    @inlinable public static func / (a: Vec2, s: Double) -> Vec2 { Vec2(a.x / s, a.y / s) }
    @inlinable public static prefix func - (a: Vec2) -> Vec2 { Vec2(-a.x, -a.y) }
    @inlinable public static func += (a: inout Vec2, b: Vec2) { a = a + b }
    @inlinable public static func -= (a: inout Vec2, b: Vec2) { a = a - b }

    public var description: String { "(\(x), \(y))" }
}

/// A 3D point or vector in model meters. Z is up.
public struct Vec3: Hashable, Codable, Sendable, CustomStringConvertible {
    public var x: Double
    public var y: Double
    public var z: Double

    @inlinable public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }
    @inlinable public init(x: Double, y: Double, z: Double) { self.x = x; self.y = y; self.z = z }
    @inlinable public init(_ v: Vec2, z: Double = 0) { self.x = v.x; self.y = v.y; self.z = z }

    public static let zero = Vec3(0, 0, 0)
    public static let unitX = Vec3(1, 0, 0)
    public static let unitY = Vec3(0, 1, 0)
    public static let unitZ = Vec3(0, 0, 1)

    @inlinable public var xy: Vec2 { Vec2(x, y) }
    @inlinable public var length: Double { (x * x + y * y + z * z).squareRoot() }
    @inlinable public var lengthSquared: Double { x * x + y * y + z * z }
    @inlinable public var normalized: Vec3 {
        let l = length
        return l > 0 ? Vec3(x / l, y / l, z / l) : .zero
    }
    @inlinable public func dot(_ o: Vec3) -> Double { x * o.x + y * o.y + z * o.z }
    @inlinable public func cross(_ o: Vec3) -> Vec3 {
        Vec3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)
    }
    @inlinable public func distance(to o: Vec3) -> Double { (self - o).length }
    @inlinable public func isAlmostEqual(_ o: Vec3, tolerance: Double = Tolerance.length) -> Bool {
        (self - o).lengthSquared <= tolerance * tolerance
    }
    @inlinable public func lerp(to o: Vec3, t: Double) -> Vec3 { self + (o - self) * t }
    /// Any unit vector perpendicular to this one.
    public var anyPerpendicular: Vec3 {
        let a = abs(x) < 0.9 ? Vec3.unitX : Vec3.unitY
        return cross(a).normalized
    }

    @inlinable public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    @inlinable public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    @inlinable public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    @inlinable public static func * (s: Double, a: Vec3) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }
    @inlinable public static func / (a: Vec3, s: Double) -> Vec3 { Vec3(a.x / s, a.y / s, a.z / s) }
    @inlinable public static prefix func - (a: Vec3) -> Vec3 { Vec3(-a.x, -a.y, -a.z) }
    @inlinable public static func += (a: inout Vec3, b: Vec3) { a = a + b }

    public var description: String { "(\(x), \(y), \(z))" }
}
