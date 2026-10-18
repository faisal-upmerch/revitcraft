import Foundation

/// The single tolerance policy for Arcus geometry.
///
/// Model coordinates are double-precision meters. Every geometric comparison in
/// the kernel and the domain goes through these values; code must not introduce
/// ad-hoc epsilons. The values are chosen for architectural modeling:
///
/// - `length`: two points closer than 0.01 mm are the same point. Far below any
///   buildable dimension, far above double rounding noise for coordinates up to
///   ~100 km from the origin (ulp at 1e5 m ≈ 1.5e-11 m).
/// - `angle`: directions within ~0.0006° are parallel.
/// - `area`: loops smaller than 1 mm² are degenerate.
/// - `snap`: default screen-independent snap capture distance in meters is not
///   defined here; snapping works in view pixels and converts through scale.
public enum Tolerance {
    /// Distance under which points coincide (meters).
    public static let length: Double = 1.0e-5
    /// Squared `length`, for comparisons that avoid square roots.
    public static let lengthSquared: Double = length * length
    /// Angle under which directions are parallel (radians).
    public static let angle: Double = 1.0e-5
    /// Area under which a loop is degenerate (square meters).
    public static let area: Double = 1.0e-6
    /// Volume under which a solid is degenerate (cubic meters).
    public static let volume: Double = 1.0e-9
    /// Relative tolerance for dimensionless parameters along curves (0…1).
    public static let parameter: Double = 1.0e-9
    /// Short curve limit: curves shorter than this cannot be created (meters).
    /// Mirrors the practical "element is too short" limit of BIM authoring tools (~0.8 mm).
    public static let shortCurve: Double = 0.0008
    /// Coordinates farther than this from the internal origin trigger a warning
    /// (meters). Precision stays adequate but graphics precision degrades.
    public static let farFromOrigin: Double = 32_000

    @inlinable public static func isZero(_ v: Double) -> Bool { abs(v) <= length }
    @inlinable public static func equal(_ a: Double, _ b: Double) -> Bool { abs(a - b) <= length }
    @inlinable public static func equalAngle(_ a: Double, _ b: Double) -> Bool {
        abs(Angle.normalizeSigned(a - b)) <= angle
    }
    @inlinable public static func lessOrEqual(_ a: Double, _ b: Double) -> Bool { a <= b + length }
    @inlinable public static func less(_ a: Double, _ b: Double) -> Bool { a < b - length }
}

public enum Angle {
    public static let twoPi = Double.pi * 2
    /// Normalizes to [0, 2π).
    @inlinable public static func normalize(_ a: Double) -> Double {
        var r = a.truncatingRemainder(dividingBy: twoPi)
        if r < 0 { r += twoPi }
        if r >= twoPi { r -= twoPi }
        return r
    }
    /// Normalizes to (-π, π].
    @inlinable public static func normalizeSigned(_ a: Double) -> Double {
        var r = normalize(a)
        if r > .pi { r -= twoPi }
        return r
    }
    @inlinable public static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
    @inlinable public static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
}
