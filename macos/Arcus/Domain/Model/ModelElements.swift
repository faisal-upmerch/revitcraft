import Foundation
import ArcusGeometry

// MARK: - Datums

public struct LevelData: Hashable, Codable, Sendable {
    /// Elevation above the internal origin (meters).
    public var elevation: Double
    /// Building storey levels define storeys for IFC, schedules and room upper limits.
    public var isBuildingStorey: Bool
    public var isStructural: Bool
    /// Room computation height above the level.
    public var computationHeight: Double
    /// Plan extents of the level line in elevation/section views (2D extents, meters along the view).
    public var extentStart: Double?
    public var extentEnd: Double?
    public var showBubbleStart: Bool
    public var showBubbleEnd: Bool
    /// Scope box limiting where the level appears (WP6a; absent in older files).
    public var scopeBoxID: ElementID?

    public init(elevation: Double, isBuildingStorey: Bool = true, isStructural: Bool = false, computationHeight: Double = 0,
                showBubbleStart: Bool = false, showBubbleEnd: Bool = true) {
        self.elevation = elevation; self.isBuildingStorey = isBuildingStorey; self.isStructural = isStructural
        self.computationHeight = computationHeight; self.showBubbleStart = showBubbleStart; self.showBubbleEnd = showBubbleEnd
    }
}

public struct GridData: Hashable, Codable, Sendable {
    public var curve: Curve2
    public var bubbleAtStart: Bool
    public var bubbleAtEnd: Bool
    /// 3D vertical extents (absolute elevations). nil = extend through all levels.
    public var bottomElevation: Double?
    public var topElevation: Double?
    /// Scope box limiting where the grid appears (WP6a; absent in older files).
    public var scopeBoxID: ElementID?
    /// I4: per-view 2D extents and bubble elbows, as in RevitCraft. Ends without one use the model (3D) extents.
    /// Absent in older files.
    public var viewExtents: [GridViewExtent]?
    /// I4: alignment locks: a locked end moves with the ends of parallel grids aligned with it.
    public var lockStart: Bool?
    public var lockEnd: Bool?
    /// F2: multi-segment grids: the bend points between the start and the end of `curve` (a line through the two
    /// ends). Absent (or empty) for straight and arc grids, and in older files.
    public var vertices: [Vec2]?
    public init(curve: Curve2, bubbleAtStart: Bool = true, bubbleAtEnd: Bool = false) {
        self.curve = curve; self.bubbleAtStart = bubbleAtStart; self.bubbleAtEnd = bubbleAtEnd
    }

    /// The grid's 2D extents and elbows in `viewID`, if it has any there.
    public func extent(in viewID: ElementID?) -> GridViewExtent? {
        guard let viewID else { return nil }
        return viewExtents?.first { $0.viewID == viewID }
    }
    /// Updates (creating if needed) the 2D extents of `viewID`; extents left empty are removed.
    public mutating func updateExtent(in viewID: ElementID, _ change: (inout GridViewExtent) -> Void) {
        var list = viewExtents ?? []
        var x = list.first { $0.viewID == viewID } ?? GridViewExtent(viewID: viewID)
        change(&x)
        list.removeAll { $0.viewID == viewID }
        if !x.isEmpty { list.append(x) }
        viewExtents = list.isEmpty ? nil : list
    }
    /// The grid as drawn in `viewID`: straight grids take that view's 2D ends where it has them.
    public func curve(in viewID: ElementID?) -> Curve2 {
        guard !isMultiSegment, let x = extent(in: viewID), case .line(let s) = curve else { return curve } // F2: multi-segment grids keep their model ends
        return .line(Segment2(x.start ?? s.start, x.end ?? s.end))
    }
    public func isLocked(atEnd: Bool) -> Bool { (atEnd ? lockEnd : lockStart) ?? false }
}

/// I4: a grid's 2D extents and bubble elbows in one view (RevitCraft `GridViewExtents`).
public struct GridViewExtent: Hashable, Codable, Sendable {
    public var viewID: ElementID
    /// 2D ends in this view; nil = the model (3D) end.
    public var start: Vec2?
    public var end: Vec2?
    /// Elbow: the bubble's offset across the grid at that end (view units).
    public var elbowStart: Vec2?
    public var elbowEnd: Vec2?
    public init(viewID: ElementID, start: Vec2? = nil, end: Vec2? = nil, elbowStart: Vec2? = nil, elbowEnd: Vec2? = nil) {
        self.viewID = viewID; self.start = start; self.end = end; self.elbowStart = elbowStart; self.elbowEnd = elbowEnd
    }
    public var isEmpty: Bool { start == nil && end == nil && elbowStart == nil && elbowEnd == nil }
}

public struct ReferencePlaneData: Hashable, Codable, Sendable {
    /// Plan line of a vertical reference plane.
    public var line: Segment2
    public var isReference: Bool
    /// Scope box limiting where the reference plane appears (WP6a; absent in older files).
    public var scopeBoxID: ElementID?
    public init(line: Segment2, isReference: Bool = true) { self.line = line; self.isReference = isReference }
}

// MARK: - Walls

public enum WallLocationLine: String, Codable, Sendable, CaseIterable {
    case wallCenterline = "Wall Centerline"
    case coreCenterline = "Core Centerline"
    case finishFaceExterior = "Finish Face: Exterior"
    case finishFaceInterior = "Finish Face: Interior"
    case coreFaceExterior = "Core Face: Exterior"
    case coreFaceInterior = "Core Face: Interior"
}

public struct WallData: Hashable, Codable, Sendable {
    /// Location line in plan. The exterior side is to the LEFT of the curve direction unless `flipped`.
    public var location: Curve2
    public var locationLine: WallLocationLine
    public var baseOffset: Double
    /// Top constraint level; nil means "Unconnected" using `unconnectedHeight`.
    public var topLevelID: ElementID?
    public var topOffset: Double
    public var unconnectedHeight: Double
    public var flipped: Bool
    public var roomBounding: Bool
    public var structural: Bool
    public var allowJoinAtStart: Bool
    public var allowJoinAtEnd: Bool
    /// Roofs/floors the top is attached to.
    public var attachedTopIDs: [ElementID]
    /// Floors the base is attached to.
    public var attachedBaseIDs: [ElementID]
    /// Optional edited elevation profile in wall-local coordinates (x along location from start, y = height above base).
    public var profile: Polygon2?
    /// Cross slope from vertical (radians, 0 = vertical). Positive leans toward the exterior.
    public var slantAngle: Double
    /// Curtain walls: manual grid lines and panel/mullion overrides (nil for other walls).
    public var curtain: CurtainInstanceData?
    /// W2-DWG: horizontal sweeps (cornices, base boards, string courses) along a face. Optional, so older documents decode.
    public var sweeps: [WallSweep]?

    public init(location: Curve2, locationLine: WallLocationLine = .wallCenterline, baseOffset: Double = 0,
                topLevelID: ElementID? = nil, topOffset: Double = 0, unconnectedHeight: Double = 3.0) {
        self.location = location; self.locationLine = locationLine; self.baseOffset = baseOffset
        self.topLevelID = topLevelID; self.topOffset = topOffset; self.unconnectedHeight = unconnectedHeight
        self.flipped = false; self.roomBounding = true; self.structural = false
        self.allowJoinAtStart = true; self.allowJoinAtEnd = true
        self.attachedTopIDs = []; self.attachedBaseIDs = []; self.profile = nil; self.slantAngle = 0; self.curtain = nil
    }
}

// MARK: - Inserts and components

public struct InsertData: Hashable, Codable, Sendable {
    /// Insertion point in plan (on the host's location line).
    public var location: Vec2
    /// Sill height for windows / base offset for doors, relative to the host's base level.
    public var sillHeight: Double
    public var facingFlipped: Bool
    public var handFlipped: Bool
    public init(location: Vec2, sillHeight: Double = 0) {
        self.location = location; self.sillHeight = sillHeight; self.facingFlipped = false; self.handFlipped = false
    }
}

public struct ComponentData: Hashable, Codable, Sendable {
    public var location: Vec2
    public var rotation: Double
    /// Elevation above the associated level.
    public var offset: Double
    public var mirrored: Bool
    /// F1415: Flip Facing from a family's vertical flip control (mirrors across the family's X axis); nil = not flipped.
    public var facingFlipped: Bool?
    public init(location: Vec2, rotation: Double = 0, offset: Double = 0, mirrored: Bool = false) {
        self.location = location; self.rotation = rotation; self.offset = offset; self.mirrored = mirrored
    }
}

public struct ColumnData: Hashable, Codable, Sendable {
    public var location: Vec2
    public var rotation: Double
    public var baseOffset: Double
    public var topLevelID: ElementID?
    public var topOffset: Double
    public var unconnectedHeight: Double
    public var roomBounding: Bool
    /// F2: slanted columns: the plan point at the column's top (the base is `location`). nil = vertical. Optional, so
    /// older documents decode.
    public var topLocation: Vec2?
    public init(location: Vec2, rotation: Double = 0, baseOffset: Double = 0, topLevelID: ElementID? = nil, topOffset: Double = 0, unconnectedHeight: Double = 3) {
        self.location = location; self.rotation = rotation; self.baseOffset = baseOffset; self.topLevelID = topLevelID
        self.topOffset = topOffset; self.unconnectedHeight = unconnectedHeight; self.roomBounding = true
    }
}

public enum BeamZJustification: String, Codable, Sendable, CaseIterable { case top = "Top", center = "Center", bottom = "Bottom" }

public struct BeamData: Hashable, Codable, Sendable {
    public var curve: Curve2
    public var startOffset: Double
    public var endOffset: Double
    public var zJustification: BeamZJustification
    public var rotation: Double
    public init(curve: Curve2, startOffset: Double = 0, endOffset: Double = 0, zJustification: BeamZJustification = .top) {
        self.curve = curve; self.startOffset = startOffset; self.endOffset = endOffset; self.zJustification = zJustification; self.rotation = 0
    }
}

// MARK: - Sketch-based elements

/// A sketch of closed loops made of lines and arcs. Loop 0 is typically the outer boundary.
public struct Sketch: Hashable, Codable, Sendable {
    public var loops: [[Curve2]]
    public init(loops: [[Curve2]]) { self.loops = loops }
    public init(polygon: Polygon2) { loops = [polygon.edges.map { .line($0) }] }
    public init(rect: Rect2) { self.init(polygon: .rectangle(rect)) }

    public var allCurves: [Curve2] { loops.flatMap { $0 } }
    public var bounds: Rect2 { allCurves.reduce(Rect2.empty) { $0.union($1.bounds) } }

    /// Converts loops to polygons (arcs tessellated). Returns nil with a reason if a loop is open.
    public func polygons(chordTolerance: Double = 0.005) -> Result<[Polygon2], SketchError> {
        var out: [Polygon2] = []
        for (i, loop) in loops.enumerated() {
            guard !loop.isEmpty else { continue }
            let ordered = Sketch.orderLoop(loop)
            guard let ordered else { return .failure(.openLoop(i)) }
            var pts: [Vec2] = []
            for c in ordered {
                let t = c.tessellate(chordTolerance: chordTolerance)
                pts.append(contentsOf: t.dropLast())
            }
            let poly = Polygon2(pts).simplified()
            if poly.isDegenerate { return .failure(.degenerateLoop(i)) }
            if !poly.isSimple { return .failure(.selfIntersecting(i)) }
            out.append(poly)
        }
        if out.isEmpty { return .failure(.empty) }
        return .success(out)
    }

    /// Builds a profile: the largest loop is the outer boundary, loops inside it are holes.
    public func profile() -> Result<Profile2, SketchError> {
        switch polygons() {
        case .failure(let e): return .failure(e)
        case .success(let polys):
            let sorted = polys.sorted { $0.area > $1.area }
            let outer = sorted[0]
            var holes: [Polygon2] = []
            for p in sorted.dropFirst() {
                guard outer.contains(p.points[0]) else { return .failure(.loopOutsideBoundary) }
                if holes.contains(where: { $0.contains(p.points[0]) }) { return .failure(.nestedLoops) }
                holes.append(p)
            }
            // Loops must not intersect each other.
            for i in 0..<sorted.count {
                for j in (i + 1)..<sorted.count {
                    for a in sorted[i].edges { for b in sorted[j].edges where a.intersection(b) != nil { return .failure(.loopsIntersect) } }
                }
            }
            return .success(Profile2(outer: outer, holes: holes))
        }
    }

    /// Orders curves head-to-tail (reversing as needed). Nil if they do not form one closed chain.
    public static func orderLoop(_ curves: [Curve2]) -> [Curve2]? {
        guard var current = curves.first else { return nil }
        var remaining = Array(curves.dropFirst())
        var out = [current]
        let tol = Tolerance.length * 10
        while !remaining.isEmpty {
            let end = current.end
            if let i = remaining.firstIndex(where: { $0.start.isAlmostEqual(end, tolerance: tol) }) {
                current = remaining.remove(at: i)
            } else if let i = remaining.firstIndex(where: { $0.end.isAlmostEqual(end, tolerance: tol) }) {
                current = remaining.remove(at: i).reversed
            } else {
                return nil
            }
            out.append(current)
        }
        guard out.last!.end.isAlmostEqual(out[0].start, tolerance: tol) else { return nil }
        return out
    }

    public func transformed(_ t: Transform2) -> Sketch { Sketch(loops: loops.map { $0.map { $0.transformed(t) } }) }
}

public enum SketchError: Error, Hashable, Sendable, CustomStringConvertible {
    case empty, openLoop(Int), degenerateLoop(Int), selfIntersecting(Int), loopOutsideBoundary, nestedLoops, loopsIntersect
    public var description: String {
        switch self {
        case .empty: "The sketch has no boundary lines."
        case .openLoop(let i): "Boundary loop \(i + 1) is not closed. Lines must connect end to end."
        case .degenerateLoop(let i): "Boundary loop \(i + 1) encloses no area."
        case .selfIntersecting(let i): "Boundary loop \(i + 1) crosses itself."
        case .loopOutsideBoundary: "An opening loop lies outside the outer boundary."
        case .nestedLoops: "Loops are nested more than one level deep."
        case .loopsIntersect: "Boundary loops intersect each other."
        }
    }
}

/// Slope arrow for sloped floors: rises from tail to head.
public struct SlopeArrow: Hashable, Codable, Sendable {
    public var tail: Vec2
    public var head: Vec2
    /// Height offset at the tail relative to the element's offset.
    public var tailOffset: Double
    /// Slope as rise/run.
    public var slope: Double
    public init(tail: Vec2, head: Vec2, tailOffset: Double = 0, slope: Double) {
        self.tail = tail; self.head = head; self.tailOffset = tailOffset; self.slope = slope
    }
}

public struct SlabData: Hashable, Codable, Sendable {
    public var boundary: Sketch
    /// Height offset of the top surface from the level (floors, pads) or of the bottom surface (ceilings).
    public var offset: Double
    public var slopeArrow: SlopeArrow?
    public var roomBounding: Bool
    public var structural: Bool
    /// Shape-editing points (nil or empty = the unedited top surface). Optional so documents from before schema 3 decode.
    public var shapePoints: [ShapePoint]?
    /// W2-DWG: slab edge profile swept along the outer boundary (floors). Optional, so older documents decode.
    public var edgeProfile: SlabEdgeProfile?
    public init(boundary: Sketch, offset: Double = 0) {
        self.boundary = boundary; self.offset = offset; self.slopeArrow = nil; self.roomBounding = true; self.structural = false
    }
}

public struct RoofData: Hashable, Codable, Sendable {
    /// Footprint sketch; loop 0 is the eave line (already including overhang). Further loops are openings.
    public var footprint: Sketch
    /// Per-curve of loop 0: slope angle (radians) when the edge defines slope; nil for gable edges.
    public var edgeSlopes: [Double?]
    public var baseOffset: Double
    /// Overhang recorded when the footprint was picked from walls (informational after creation).
    public var overhang: Double
    public var fascia: Bool
    public var gutter: Bool
    /// Roof by extrusion: when set, the roof is this extruded profile and `footprint`/`edgeSlopes` are unused (empty).
    /// Optional so documents from before schema 3 decode.
    public var extrusion: RoofExtrusion?
    /// Shape-editing points for flat footprint roofs (nil or empty = unedited).
    public var shapePoints: [ShapePoint]?
    /// W2-DWG: horizontal soffit under the eaves (nil = none). Optional, so older documents decode.
    public var soffit: RoofSoffit?
    /// F2: footprint slope arrows: the edge at an arrow's tail rises toward its head at the arrow's slope, from the
    /// arrow's tail offset. Optional, so older documents decode.
    public var slopeArrows: [SlopeArrow]?
    /// F2: per curve of loop 0 (as `edgeSlopes`): the eave's height above the roof base (Align Eaves). nil = all at
    /// the base. Optional, so older documents decode.
    public var edgeOffsets: [Double]?
    public init(footprint: Sketch, edgeSlopes: [Double?], baseOffset: Double = 0, overhang: Double = 0) {
        self.footprint = footprint; self.edgeSlopes = edgeSlopes; self.baseOffset = baseOffset; self.overhang = overhang
        self.fascia = false; self.gutter = false
    }
}

// MARK: - Circulation

public enum StairShape: String, Codable, Sendable, CaseIterable {
    case straight = "Straight"
    case lShaped = "L-Shaped"
    case uShaped = "U-Shaped"
}

public struct StairData: Hashable, Codable, Sendable {
    public var shape: StairShape
    /// Start of the first run (at the bottom riser, on the run centerline).
    public var origin: Vec2
    /// Direction of travel of the first run (radians).
    public var direction: Double
    /// Clear run width.
    public var width: Double
    public var baseOffset: Double
    public var topLevelID: ElementID?
    public var topOffset: Double
    /// Unconnected height when there is no top level.
    public var unconnectedHeight: Double
    /// Desired number of risers; nil = computed from the type's maximum riser height.
    public var desiredRiserCount: Int?
    /// Turn direction for L/U shapes.
    public var turnsLeft: Bool
    /// Number of risers in the first run for L/U shapes (nil = split evenly).
    public var firstRunRisers: Int?
    /// F2: multistory stairs (Connect Levels): the stair repeats, level to level, up to this level. Optional, so older
    /// documents decode.
    public var multistoryTopLevelID: ElementID?
    public init(shape: StairShape = .straight, origin: Vec2, direction: Double, width: Double = 1.1, topLevelID: ElementID? = nil) {
        self.shape = shape; self.origin = origin; self.direction = direction; self.width = width
        self.baseOffset = 0; self.topLevelID = topLevelID; self.topOffset = 0; self.unconnectedHeight = 3
        self.desiredRiserCount = nil; self.turnsLeft = true; self.firstRunRisers = nil
    }
}

public struct RailingData: Hashable, Codable, Sendable {
    /// Plan path.
    public var path: [Curve2]
    public var baseOffset: Double
    /// When hosted on a stair, follows the stair's slope; `hostID` on the element names the stair.
    public var followsHost: Bool
    /// Which side of the stair when hosted (true = left).
    public var hostSideLeft: Bool
    public init(path: [Curve2], baseOffset: Double = 0) {
        self.path = path; self.baseOffset = baseOffset; self.followsHost = false; self.hostSideLeft = false
    }
}

// MARK: - Rooms, areas, lines

public struct RoomData: Hashable, Codable, Sendable {
    /// Placement point in plan.
    public var point: Vec2
    public var number: String
    public var upperLimitLevelID: ElementID?
    public var limitOffset: Double
    public var baseOffset: Double
    /// Areas: the area scheme; nil for rooms.
    public var areaSchemeID: ElementID?
    public init(point: Vec2, number: String, limitOffset: Double = 2.7) {
        self.point = point; self.number = number; self.upperLimitLevelID = nil; self.limitOffset = limitOffset
        self.baseOffset = 0; self.areaSchemeID = nil
    }
}

public struct ModelLineData: Hashable, Codable, Sendable {
    public var curve: Curve2
    /// Line style element for detail/model lines.
    public var styleID: ElementID?
    /// F1: a spline or (partial) ellipse drawn as one line; `curve` is then its chord. Optional, so older documents decode.
    public var freeform: FreeformCurve?
    public init(curve: Curve2, styleID: ElementID? = nil, freeform: FreeformCurve? = nil) { self.curve = curve; self.styleID = styleID; self.freeform = freeform }
}

public struct TopographyData: Hashable, Codable, Sendable {
    public var points: [Vec3]
    /// W2-DWG: a sub-region's boundary in plan (the element's `hostID` is the toposurface it lies on). Triangles outside
    /// it are dropped. Nil for ordinary toposurfaces. Optional, so older documents decode.
    public var boundary: [Vec2]?
    /// W2-DWG: surface material (sub-regions, graded regions). Optional, so older documents decode.
    public var materialID: ElementID?
    /// BL-SITE: set on toposolids and their sub-divisions (layered solids); nil on legacy toposurfaces and sub-regions.
    /// Optional, so older documents decode.
    public var solid: ToposolidData?
    public init(points: [Vec3], boundary: [Vec2]? = nil, materialID: ElementID? = nil, solid: ToposolidData? = nil) { // BL-SITE
        self.points = points; self.boundary = boundary; self.materialID = materialID; self.solid = solid
    }
}

// MARK: - Groups, links, reference geometry

public struct GroupData: Hashable, Codable, Sendable {
    public var members: [ElementID]
    public var origin: Vec2
    /// Group instances sharing a group type name are updated together after Edit Group.
    public var groupTypeName: String
    /// Set for associative array groups (Array ▸ Group and Associate): how the members are regenerated when the
    /// number of array members changes. Nil for ordinary groups and in files written before arrays were associative.
    public var arraySpec: ArraySpec? = nil
    public init(members: [ElementID], origin: Vec2, groupTypeName: String) {
        self.members = members; self.origin = origin; self.groupTypeName = groupTypeName
    }
}

public enum LinkFormat: String, Codable, Sendable, CaseIterable {
    case dwg = "DWG", dxf = "DXF", ifc = "IFC", pdf = "PDF", image = "Image"
}

/// Per-link layer display state.
public struct LinkLayerState: Hashable, Codable, Sendable {
    public var name: String
    public var visible: Bool
    public var halftone: Bool
    public init(name: String, visible: Bool = true, halftone: Bool = false) { self.name = name; self.visible = visible; self.halftone = halftone }
}

/// A CAD/PDF/image link or import instance placed in the model or a view.
public struct LinkData: Hashable, Codable, Sendable {
    public var format: LinkFormat
    /// True for Link (reloadable, source-tracked), false for Import (snapshot).
    public var isLinked: Bool
    /// Security-scoped bookmark data for reloading linked files.
    public var bookmark: Data?
    public var sourcePath: String
    public var sourceName: String
    /// Content-addressed key of the reference drawing stored in the model assets.
    public var contentKey: String
    public var placement: Transform2
    public var elevationOffset: Double
    public var layers: [LinkLayerState]
    public var isLoaded: Bool
    public var opacity: Double
    public var drawBehindModel: Bool
    /// PDF page index or CAD layout name.
    public var page: String?
    public var lastLoaded: Date?
    public var sourceModified: Date?
    /// F67: the picture itself for Import Image / Import PDF (imports keep their content in the project).
    public var embeddedData: Data? = nil
    public init(format: LinkFormat, isLinked: Bool, sourcePath: String, sourceName: String, contentKey: String, placement: Transform2 = .identity) {
        self.format = format; self.isLinked = isLinked; self.bookmark = nil; self.sourcePath = sourcePath; self.sourceName = sourceName
        self.contentKey = contentKey; self.placement = placement; self.elevationOffset = 0; self.layers = []; self.isLoaded = true
        self.opacity = 1; self.drawBehindModel = true; self.page = nil; self.lastLoaded = nil; self.sourceModified = nil
    }
}

/// Immutable geometry retained from an import (unsupported IFC entities, converted CAD 3D faces).
public struct ReferenceGeometryData: Hashable, Codable, Sendable {
    public var positions: [Vec3]
    public var indices: [UInt32]
    public var edges: [UInt32]
    public var ifcType: String
    public var properties: [String: String]
    public init(mesh: Mesh, ifcType: String, properties: [String: String] = [:]) {
        positions = mesh.positions; indices = mesh.indices; edges = mesh.featureEdges; self.ifcType = ifcType; self.properties = properties
    }
    public var mesh: Mesh {
        var normals = [Vec3](repeating: .unitZ, count: positions.count)
        for i in stride(from: 0, to: indices.count, by: 3) {
            let a = positions[Int(indices[i])], b = positions[Int(indices[i + 1])], c = positions[Int(indices[i + 2])]
            let n = (b - a).cross(c - a).normalized
            normals[Int(indices[i])] = n; normals[Int(indices[i + 1])] = n; normals[Int(indices[i + 2])] = n
        }
        return Mesh(positions: positions, normals: normals, indices: indices, featureEdges: edges)
    }
}
