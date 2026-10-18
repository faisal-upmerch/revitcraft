import Foundation
import ArcusGeometry

// MARK: - Ramps

/// A ramp drawn as a run path in plan.
///
/// Every segment of `path` is a straight sloped run. Interior vertices become flat landings where the run turns, and
/// runs longer than the type's maximum incline length are broken by intermediate landings. The slope is whatever
/// the drawn run needs to climb from the base to the top; the type's maximum slope is checked, not enforced, so a
/// short run still commits and is reported in Model Health.
public struct RampData: Hashable, Codable, Sendable {
    /// Run centerline from the bottom of the ramp to the top (at least two points).
    public var path: [Vec2]
    /// Clear width of the ramp.
    public var width: Double
    public var baseOffset: Double
    /// Top constraint level; nil means "Unconnected" using `unconnectedHeight`.
    public var topLevelID: ElementID?
    public var topOffset: Double
    public var unconnectedHeight: Double

    public init(path: [Vec2], width: Double = 1.2, topLevelID: ElementID? = nil) {
        self.path = path; self.width = width; self.baseOffset = 0; self.topLevelID = topLevelID
        self.topOffset = 0; self.unconnectedHeight = 1.0
    }
}

/// Body of a ramp (type parameter `ramp.shape`).
public enum RampShape: String, CaseIterable, Sendable {
    /// Filled down to the base (a ramp on grade).
    case solid = "Solid"
    /// A sloped slab of the type's thickness (a suspended ramp).
    case thin = "Thin"
}

// MARK: - Roof by extrusion

/// An extruded roof: an open profile sketched on a vertical work plane and extruded perpendicular to that plane.
///
/// The work plane passes through `origin` and contains the horizontal unit vector `direction`. Profile coordinates are
/// (x, y) = (distance along `direction` from `origin`, height above the roof's base: its level plus `baseOffset`). The
/// solid runs from `start` to `end`, measured along `normal` (the left perpendicular of `direction`).
public struct RoofExtrusion: Hashable, Codable, Sendable {
    public var origin: Vec2
    public var direction: Vec2
    /// Open chain of lines and arcs, in order.
    public var profile: [Curve2]
    public var start: Double
    public var end: Double
    /// Reference plane the profile was sketched on, if any (informational).
    public var workPlaneID: ElementID?

    public init(origin: Vec2, direction: Vec2, profile: [Curve2], start: Double, end: Double, workPlaneID: ElementID? = nil) {
        self.origin = origin; self.direction = direction.normalized; self.profile = profile
        self.start = start; self.end = end; self.workPlaneID = workPlaneID
    }

    public var normal: Vec2 { direction.perpendicular }
    /// Plan point at profile station `x` and extrusion depth `depth`.
    public func planPoint(_ x: Double, depth: Double) -> Vec2 { origin + direction * x + normal * depth }
    /// Station and depth of a plan point.
    public func local(_ p: Vec2) -> (x: Double, depth: Double) { ((p - origin).dot(direction), (p - origin).dot(normal)) }
}

// MARK: - Shape editing

/// A shape-editing point on a floor or flat roof: its plan position and its elevation offset from the unedited top
/// surface. Points on boundary vertices raise or lower that vertex; interior points add a vertex to the top surface.
public struct ShapePoint: Hashable, Codable, Sendable {
    public var position: Vec2
    public var offset: Double
    public init(position: Vec2, offset: Double) { self.position = position; self.offset = offset }
}
