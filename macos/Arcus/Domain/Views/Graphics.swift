import Foundation
import ArcusGeometry

/// Line weight table: pen widths on paper (mm) by weight number (1…16) and view scale.
/// Printed weights depend on category, cut/projection role and scale; on-screen "thin lines" is a UI option only.
public enum LineWeights {
    static let base: [Double] = [0.09, 0.13, 0.18, 0.25, 0.35, 0.50, 0.70, 1.00, 1.40, 2.00, 2.50, 3.00, 3.50, 4.00, 4.50, 5.00]
    /// Paper width in millimeters for a weight number at a view scale (denominator).
    public static func paperWidth(_ weight: Int, scale: Int) -> Double {
        let w = base[max(0, min(base.count - 1, weight - 1))]
        // Coarser scales thin lines slightly; detail scales thicken them (clamped).
        let f = min(1.5, max(0.65, pow(100.0 / Double(max(scale, 1)), 0.18)))
        return weight <= 1 ? w : w * f
    }
}

/// Stroke style of a graphic primitive.
public struct GStroke: Hashable, Sendable {
    public var weight: Int
    public var color: RGBColor
    public var pattern: LinePatternKind
    public var halftone: Bool
    public init(weight: Int = 1, color: RGBColor = .black, pattern: LinePatternKind = .solid, halftone: Bool = false) {
        self.weight = weight; self.color = color; self.pattern = pattern; self.halftone = halftone
    }
    public static let thin = GStroke(weight: 1)
}

/// Fill style of a region.
public struct GFill: Hashable, Sendable {
    public var pattern: FillPatternKind
    public var color: RGBColor
    public var background: RGBColor?
    /// 0 = opaque, 1 = invisible.
    public var transparency: Double
    public var halftone: Bool
    /// Model patterns are sized in model units; drafting patterns in paper units.
    public var isModelPattern: Bool
    /// W4-HATCH: line-family definition of a project fill pattern. When set, renderers draw these lines (clipped to the
    /// region) instead of the procedural `pattern`, which stays as the density fallback.
    public var hatch: HatchPattern? = nil
    public init(pattern: FillPatternKind, color: RGBColor = .black, background: RGBColor? = nil, transparency: Double = 0, halftone: Bool = false, isModelPattern: Bool = false) {
        self.pattern = pattern; self.color = color; self.background = background; self.transparency = transparency
        self.halftone = halftone; self.isModelPattern = isModelPattern
    }
    public static let mask = GFill(pattern: .solid, color: .white)

    /// A fill drawing a project pattern: its line families, with the pattern's procedural kind as fallback. // W4-HATCH
    public init(fillPattern d: FillPatternData, color: RGBColor, background: RGBColor? = nil, transparency: Double = 0, halftone: Bool = false) {
        self.init(pattern: d.kind, color: color, background: background, transparency: transparency, halftone: halftone, isModelPattern: d.isModelPattern)
        self.hatch = d.hatch
    }
    /// Replaces the pattern (procedural kind and line families) keeping colours.
    public mutating func setPattern(_ d: FillPatternData) { pattern = d.kind; isModelPattern = d.isModelPattern; hatch = d.hatch }
    public mutating func setPattern(_ k: FillPatternKind) { pattern = k; hatch = nil }
}

public struct GText: Hashable, Sendable {
    public var position: Vec2
    /// Height on paper (meters).
    public var height: Double
    public var rotation: Double
    public var string: String
    public var alignment: TextAlignment
    /// Vertical anchor: 0 = baseline at position, 0.5 = centered, 1 = top at position.
    public var verticalAnchor: Double
    public var bold: Bool
    public var color: RGBColor
    public var halftone: Bool
    /// Maximum width on paper (meters) for wrapping; 0 = none.
    public var wrapWidth: Double
    public var italic: Bool
    public var underline: Bool
    /// Opaque text masks what is behind its block (plus a margin) with the paper/canvas colour, like a masking region.
    public var opaque: Bool
    public init(position: Vec2, height: Double, string: String, rotation: Double = 0, alignment: TextAlignment = .left,
                verticalAnchor: Double = 0, bold: Bool = false, color: RGBColor = .black, halftone: Bool = false, wrapWidth: Double = 0,
                italic: Bool = false, underline: Bool = false, opaque: Bool = false) {
        self.position = position; self.height = height; self.string = string; self.rotation = rotation; self.alignment = alignment
        self.verticalAnchor = verticalAnchor; self.bold = bold; self.color = color; self.halftone = halftone; self.wrapWidth = wrapWidth
        self.italic = italic; self.underline = underline; self.opaque = opaque
    }
    /// Margin around the text block of an opaque background, as a multiple of the cap height.
    public static let backgroundMargin = 0.35
    /// Underline position below the baseline and pen thickness, as multiples of the cap height.
    public static let underlineOffset = 0.22
    public static let underlineThickness = 0.07
}

/// Drawing primitives in view coordinates (plan: model meters XY; vertical views: (along, elevation); sheets: paper meters).
public enum GPrimitive: Hashable, Sendable {
    case polyline([Vec2], closed: Bool, GStroke)
    case arc(Arc2, GStroke)
    case fill([Polygon2], GFill)
    case text(GText)
}

/// A group of primitives belonging to one element (or to none, for view decorations).
public struct GItem: Sendable {
    public enum Layer: Int, Sendable, Comparable {
        case underlay = 0, link = 1, fills = 2, model = 3, cut = 4, annotation = 5, masking = 6, overlay = 7
        public static func < (a: Layer, b: Layer) -> Bool { a.rawValue < b.rawValue }
    }
    public var elementID: ElementID?
    public var category: Category
    public var layer: Layer
    public var primitives: [GPrimitive]
    public var bounds: Rect2
    /// For view markers: the view to open on double-click.
    public var targetViewID: ElementID?
    /// Selection hit geometry (outline); defaults to primitives.
    public var hitPolygons: [Polygon2]
    public var selectable: Bool
    /// View scale used for line weights when this item came from another view (viewports on sheets).
    public var lineScale: Int?

    public init(elementID: ElementID?, category: Category, layer: Layer, primitives: [GPrimitive], targetViewID: ElementID? = nil,
                hitPolygons: [Polygon2] = [], selectable: Bool = true) {
        self.elementID = elementID; self.category = category; self.layer = layer; self.primitives = primitives
        self.targetViewID = targetViewID; self.hitPolygons = hitPolygons; self.selectable = selectable
        self.bounds = GItem.computeBounds(primitives, hit: hitPolygons)
    }

    static func computeBounds(_ ps: [GPrimitive], hit: [Polygon2]) -> Rect2 {
        var r = Rect2.empty
        for p in ps {
            switch p {
            case .polyline(let pts, _, _): for q in pts { r.include(q) }
            case .arc(let a, _): r.include(a.bounds)
            case .fill(let polys, _): for poly in polys { r.include(poly.bounds) }
            case .text(let t): r.include(t.position)
            }
        }
        for h in hit { r.include(h.bounds) }
        return r
    }
}

/// The complete 2D display list of a view at a given state.
public struct ViewGraphics: Sendable {
    public var viewID: ElementID
    public var scale: Int
    public var items: [GItem]
    /// Extents of model content (view coordinates).
    public var extents: Rect2
    /// Active crop (view coordinates) if the view is cropped.
    public var crop: Rect2?
    public var modelRevision: UInt64
    public init(viewID: ElementID, scale: Int, items: [GItem], extents: Rect2, crop: Rect2?, modelRevision: UInt64) {
        self.viewID = viewID; self.scale = scale; self.items = items; self.extents = extents; self.crop = crop; self.modelRevision = modelRevision
    }
    /// Model-space size of a paper length (meters on paper → meters in the view).
    public func paperToModel(_ paper: Double) -> Double { paper * Double(scale) }
}

/// Default object styles (per category projection/cut line weights and colors).
public struct ObjectStyle: Hashable, Codable, Sendable {
    public var projectionWeight: Int
    public var cutWeight: Int
    public var color: RGBColor
    public var pattern: LinePatternKind
    public init(_ p: Int, _ c: Int, color: RGBColor = .black, pattern: LinePatternKind = .solid) {
        projectionWeight = p; cutWeight = c; self.color = color; self.pattern = pattern
    }
}

public enum ObjectStyles {
    public static func style(_ c: Category) -> ObjectStyle {
        switch c {
        case .walls: ObjectStyle(2, 5)
        case .floors, .roofs, .ceilings, .buildingPads: ObjectStyle(1, 4)
        case .doors, .windows: ObjectStyle(1, 3)
        case .stairs, .ramps: ObjectStyle(1, 3)
        case .railings: ObjectStyle(1, 3)
        case .columns: ObjectStyle(1, 4)
        case .structuralColumns, .structuralFraming: ObjectStyle(2, 5)
        case .furniture, .casework, .plumbingFixtures, .specialtyEquipment, .genericModels: ObjectStyle(1, 2)
        case .rooms: ObjectStyle(1, 1, color: RGBColor(0.25, 0.45, 0.70))
        case .areas: ObjectStyle(1, 1, color: RGBColor(0.55, 0.35, 0.65))
        case .grids: ObjectStyle(1, 1, color: .black, pattern: .center)
        case .levels: ObjectStyle(1, 1, color: .black, pattern: .center)
        case .referencePlanes: ObjectStyle(1, 1, color: RGBColor(0.35, 0.55, 0.35), pattern: .dash)
        case .roomSeparationLines: ObjectStyle(1, 1)
        case .areaBoundaryLines: ObjectStyle(2, 2, color: RGBColor(0.55, 0.35, 0.65))
        case .propertyLines: ObjectStyle(2, 2, pattern: .dashDot)
        case .topography: ObjectStyle(1, 2, color: RGBColor(0.35, 0.35, 0.35))
        case .dimensions, .textNotes, .tags, .spotElevations, .spotCoordinates, .spotSlopes: ObjectStyle(1, 1)
        case .sectionMarks, .elevationMarks, .callouts: ObjectStyle(2, 2)
        case .revisionClouds: ObjectStyle(2, 2, color: RGBColor(0.85, 0.15, 0.10))
        case .detailLines: ObjectStyle(1, 1)
        case .importedCAD: ObjectStyle(1, 1)
        case .ifcReference: ObjectStyle(1, 2, color: RGBColor(0.30, 0.35, 0.50))
        default: ObjectStyle(1, 2)
        }
    }

    /// Cut pattern for a category at a detail level.
    public static func cutFill(_ c: Category, detail: DetailLevel, material: MaterialData?) -> GFill? {
        switch c {
        case .walls, .floors, .roofs, .ceilings, .columns, .stairs, .buildingPads, .ramps, .topography: // BL-SITE: toposolid layers
            if detail == .coarse { return GFill(pattern: .solid, color: RGBColor(0.28, 0.28, 0.28)) }
            if let m = material {
                return GFill(pattern: fillKind(for: m.materialClass), color: RGBColor(0.35, 0.35, 0.35), background: .white)
            }
            return GFill(pattern: .diagonalUp, color: RGBColor(0.4, 0.4, 0.4), background: .white)
        case .structuralColumns, .structuralFraming:
            return GFill(pattern: .solid, color: RGBColor(0.35, 0.35, 0.35))
        default:
            return nil
        }
    }

    public static func fillKind(for c: MaterialClass) -> FillPatternKind {
        switch c {
        case .concrete: .concrete
        case .masonry: .brick
        case .insulation: .insulation
        case .wood: .wood
        case .earth: .earth
        case .stone: .crosshatch
        case .metal: .diagonalCrosshatch
        case .glass, .gas, .liquid: .horizontal
        case .plaster, .paint: .sand
        default: .diagonalUp
        }
    }
}
