import Foundation
import ArcusGeometry

/// A rectangular opening cut through a straight or curved wall (its host), drawn in an elevation or section.
/// Positions are relative to the host so the opening follows the wall when it moves or changes height.
public struct WallOpeningData: Hashable, Codable, Sendable {
    /// Stations along the host's location curve (meters from its start).
    public var start: Double
    public var end: Double
    /// Bottom and top of the opening measured from the host's base.
    public var bottom: Double
    public var top: Double

    public init(start: Double, end: Double, bottom: Double, top: Double) {
        self.start = start; self.end = end; self.bottom = bottom; self.top = top
    }

    public var width: Double { abs(end - start) }
    public var height: Double { abs(top - bottom) }
}

/// A vertical shaft: one plan sketch that cuts every floor, ceiling and roof between its base and top.
/// The element's level is the base constraint.
public struct ShaftOpeningData: Hashable, Codable, Sendable {
    public var boundary: Sketch
    public var baseOffset: Double
    /// Top constraint level; nil means "Unconnected" using `unconnectedHeight`.
    public var topLevelID: ElementID?
    public var topOffset: Double
    public var unconnectedHeight: Double

    public init(boundary: Sketch, baseOffset: Double = 0, topLevelID: ElementID? = nil, topOffset: Double = 0, unconnectedHeight: Double = 3) {
        self.boundary = boundary; self.baseOffset = baseOffset; self.topLevelID = topLevelID
        self.topOffset = topOffset; self.unconnectedHeight = unconnectedHeight
    }

    enum CodingKeys: String, CodingKey { case boundary, baseOffset, topLevelID, topOffset, unconnectedHeight }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        boundary = try c.decode(Sketch.self, forKey: .boundary)
        baseOffset = try c.decodeIfPresent(Double.self, forKey: .baseOffset) ?? 0
        topLevelID = try c.decodeIfPresent(ElementID.self, forKey: .topLevelID)
        topOffset = try c.decodeIfPresent(Double.self, forKey: .topOffset) ?? 0
        unconnectedHeight = try c.decodeIfPresent(Double.self, forKey: .unconnectedHeight) ?? 3
    }
}

/// Openings that are elements in their own right (door and window openings belong to their families).
public enum OpeningData: Hashable, Codable, Sendable {
    case wall(WallOpeningData)
    case shaft(ShaftOpeningData)

    public var wallOpening: WallOpeningData? { if case .wall(let w) = self { return w }; return nil }
    public var shaft: ShaftOpeningData? { if case .shaft(let s) = self { return s }; return nil }
}
