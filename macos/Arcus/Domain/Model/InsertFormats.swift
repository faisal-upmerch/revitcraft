import Foundation
import ArcusGeometry

// F67: what the Insert tab's file readers (ArcusCAD) hand to the model operations.

/// Points read from a point cloud or survey file, in meters.
public struct PointSet: Sendable {
    public var points: [(Vec3, (UInt8, UInt8, UInt8))]
    /// Points in the file before thinning.
    public var sourceCount: Int
    public var hasColor: Bool
    /// Meters per file unit that was applied.
    public var unitScale: Double
    public init(points: [(Vec3, (UInt8, UInt8, UInt8))], sourceCount: Int, hasColor: Bool, unitScale: Double) {
        self.points = points; self.sourceCount = sourceCount; self.hasColor = hasColor; self.unitScale = unitScale
    }
    public var positions: [Vec3] { points.map(\.0) }
}

/// A gbXML space: its name, floor outline (meters, plan) and bottom/top elevations.
public struct GbXMLSpace: Sendable, Hashable {
    public var name: String
    public var number: String
    public var floor: [Vec2]
    public var bottom: Double
    public var top: Double
    public init(name: String, number: String = "", floor: [Vec2], bottom: Double, top: Double) {
        self.name = name; self.number = number; self.floor = floor; self.bottom = bottom; self.top = top
    }
}

/// One page of a DWFx (XPS) package, in paper meters from the page's bottom left.
public struct DWFPage: Sendable {
    public var name: String
    public var size: Vec2
    public var polylines: [MarkupData.Polyline]
    public var texts: [MarkupData.Text]
    public var pictures: [MarkupData.Picture]
    public init(name: String, size: Vec2, polylines: [MarkupData.Polyline] = [], texts: [MarkupData.Text] = [], pictures: [MarkupData.Picture] = []) {
        self.name = name; self.size = size; self.polylines = polylines; self.texts = texts; self.pictures = pictures
    }
    public var isEmpty: Bool { polylines.isEmpty && texts.isEmpty && pictures.isEmpty }
}
