import Foundation

/// Axis-aligned 2D bounds. An empty rect has `min > max`.
public struct Rect2: Hashable, Codable, Sendable {
    public var min: Vec2
    public var max: Vec2

    public init(min: Vec2, max: Vec2) { self.min = min; self.max = max }
    public init(center: Vec2, halfSize: Vec2) { min = center - halfSize; max = center + halfSize }
    public init<S: Sequence>(points: S) where S.Element == Vec2 {
        self = .empty
        for p in points { include(p) }
    }

    public static let empty = Rect2(min: Vec2(.infinity, .infinity), max: Vec2(-.infinity, -.infinity))

    public var isEmpty: Bool { min.x > max.x || min.y > max.y }
    public var width: Double { isEmpty ? 0 : max.x - min.x }
    public var height: Double { isEmpty ? 0 : max.y - min.y }
    public var size: Vec2 { Vec2(width, height) }
    public var center: Vec2 { min.midpoint(max) }
    public var corners: [Vec2] { [min, Vec2(max.x, min.y), max, Vec2(min.x, max.y)] }

    public mutating func include(_ p: Vec2) {
        min = Vec2(Swift.min(min.x, p.x), Swift.min(min.y, p.y))
        max = Vec2(Swift.max(max.x, p.x), Swift.max(max.y, p.y))
    }
    public mutating func include(_ r: Rect2) {
        guard !r.isEmpty else { return }
        include(r.min); include(r.max)
    }
    public func union(_ r: Rect2) -> Rect2 { var c = self; c.include(r); return c }
    public func expanded(by d: Double) -> Rect2 {
        isEmpty ? self : Rect2(min: min - Vec2(d, d), max: max + Vec2(d, d))
    }
    public func contains(_ p: Vec2, tolerance: Double = 0) -> Bool {
        p.x >= min.x - tolerance && p.x <= max.x + tolerance && p.y >= min.y - tolerance && p.y <= max.y + tolerance
    }
    public func contains(_ r: Rect2) -> Bool { !r.isEmpty && contains(r.min) && contains(r.max) }
    public func intersects(_ r: Rect2) -> Bool {
        !(isEmpty || r.isEmpty || r.min.x > max.x || r.max.x < min.x || r.min.y > max.y || r.max.y < min.y)
    }
    public func intersection(_ r: Rect2) -> Rect2 {
        let a = Vec2(Swift.max(min.x, r.min.x), Swift.max(min.y, r.min.y))
        let b = Vec2(Swift.min(max.x, r.max.x), Swift.min(max.y, r.max.y))
        return Rect2(min: a, max: b)
    }
}

/// Axis-aligned 3D bounds.
public struct Box3: Hashable, Codable, Sendable {
    public var min: Vec3
    public var max: Vec3

    public init(min: Vec3, max: Vec3) { self.min = min; self.max = max }
    public init<S: Sequence>(points: S) where S.Element == Vec3 {
        self = .empty
        for p in points { include(p) }
    }
    public static let empty = Box3(min: Vec3(.infinity, .infinity, .infinity), max: Vec3(-.infinity, -.infinity, -.infinity))

    public var isEmpty: Bool { min.x > max.x || min.y > max.y || min.z > max.z }
    public var center: Vec3 { (min + max) * 0.5 }
    public var size: Vec3 { isEmpty ? .zero : max - min }
    public var xy: Rect2 { isEmpty ? .empty : Rect2(min: min.xy, max: max.xy) }
    public var diagonal: Double { size.length }
    public var corners: [Vec3] {
        [Vec3(min.x, min.y, min.z), Vec3(max.x, min.y, min.z), Vec3(max.x, max.y, min.z), Vec3(min.x, max.y, min.z),
         Vec3(min.x, min.y, max.z), Vec3(max.x, min.y, max.z), Vec3(max.x, max.y, max.z), Vec3(min.x, max.y, max.z)]
    }

    public mutating func include(_ p: Vec3) {
        min = Vec3(Swift.min(min.x, p.x), Swift.min(min.y, p.y), Swift.min(min.z, p.z))
        max = Vec3(Swift.max(max.x, p.x), Swift.max(max.y, p.y), Swift.max(max.z, p.z))
    }
    public mutating func include(_ b: Box3) {
        guard !b.isEmpty else { return }
        include(b.min); include(b.max)
    }
    public func union(_ b: Box3) -> Box3 { var c = self; c.include(b); return c }
    public func intersects(_ b: Box3) -> Bool {
        !(isEmpty || b.isEmpty || b.min.x > max.x || b.max.x < min.x || b.min.y > max.y || b.max.y < min.y || b.min.z > max.z || b.max.z < min.z)
    }
    public func contains(_ p: Vec3) -> Bool {
        p.x >= min.x && p.x <= max.x && p.y >= min.y && p.y <= max.y && p.z >= min.z && p.z <= max.z
    }
    public func expanded(by d: Double) -> Box3 {
        isEmpty ? self : Box3(min: min - Vec3(d, d, d), max: max + Vec3(d, d, d))
    }
}
