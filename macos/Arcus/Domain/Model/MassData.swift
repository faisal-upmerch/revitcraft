import Foundation
import ArcusGeometry

// F5: Massing & Site ▸ In-Place Mass (RevitCraft rc-core model.rs `Mass`): a conceptual mass on a level.

/// A conceptual mass: a closed footprint sketched on its level, extruded to `height` above `baseOffset`. With a top
/// inset it is a blend whose top face is the footprint shrunk by that distance (an Arcus extension of RevitCraft's
/// extruded footprint). Masses show in every view unless Show Mass is off, and Model by Face builds walls, curtain
/// walls, floors and roofs on their faces.
public struct MassData: Hashable, Codable, Sendable {
    /// Footprint at the base, counterclockwise, in plan coordinates.
    public var boundary: [Vec2]
    public var height: Double
    /// Base above the element's level.
    public var baseOffset: Double
    /// Blend: the top loop is the footprint offset inward by this distance. nil or 0 = an extrusion. Optional, so
    /// documents without it decode.
    public var topInset: Double?

    public init(boundary: [Vec2], height: Double, baseOffset: Double = 0, topInset: Double? = nil) {
        self.boundary = Polygon2(boundary).counterClockwise.points
        self.height = height; self.baseOffset = baseOffset; self.topInset = topInset
    }

    /// True when the top is smaller than the footprint (a blend form).
    public var isBlend: Bool { (topInset ?? 0) > Tolerance.length }
    /// The form's name, as the Family Editor names forms.
    public var formName: String { isBlend ? "Blend" : "Extrusion" }
}

extension Element {
    /// F5: the mass data of a conceptual mass.
    public var mass: MassData? {
        get { if case .mass(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .mass(v) } }
    }
}
