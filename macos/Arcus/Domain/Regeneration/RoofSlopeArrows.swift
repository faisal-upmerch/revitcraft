import Foundation
import ArcusGeometry

/// F2: roof slope arrows and eave alignment (RevitCraft `Roof::slope_arrows`, Align Eaves / Adjust Height / Adjust
/// Overhang). An arrow drawn from a footprint edge that doesn't define slope makes that edge slope: the roof rises from
/// the edge (at the arrow's tail offset above the base) toward the arrow's head at the arrow's slope.
public enum RoofSlopeArrows {
    /// How close (plan) an arrow's tail must be to an edge to drive it, as RevitCraft's 300 mm.
    public static let tailReach = 0.3

    /// The slope angle and eave offset an arrow gives `edge`, or nil when no arrow's tail is on it. The arrow's rise
    /// (slope × its length) is reached at its head, so the edge's slope across it is the rise over the head's distance
    /// from the edge line.
    public static func edgeSlope(for edge: Curve2, _ arrows: [SlopeArrow]) -> (slope: Double, offset: Double)? {
        guard let s = edge.asSegment else { return nil }
        for a in arrows where s.distance(to: a.tail) <= tailReach {
            let len = a.tail.distance(to: a.head)
            let across = abs(s.signedDistance(to: a.head))
            guard len > Tolerance.length, across > Tolerance.length, a.slope > 0 else { continue }
            return (atan(a.slope * len / across), a.tailOffset)
        }
        return nil
    }

    /// Eave height above the roof base of loop-0 curve `k`.
    public static func eaveOffset(_ r: RoofData, curve k: Int) -> Double {
        r.edgeOffsets.map { k < $0.count ? $0[k] : 0 } ?? 0
    }
}
