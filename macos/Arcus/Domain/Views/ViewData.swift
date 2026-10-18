import Foundation
import ArcusGeometry

public enum ViewKind: String, Codable, Sendable, CaseIterable {
    case floorPlan = "Floor Plan"
    case ceilingPlan = "Reflected Ceiling Plan"
    case structuralPlan = "Structural Plan"
    case areaPlan = "Area Plan"
    case elevation = "Elevation"
    case section = "Section"
    case detail = "Detail View"
    case drafting = "Drafting View"
    case legend = "Legend"
    case threeD = "3D View"

    public var isPlan: Bool { self == .floorPlan || self == .ceilingPlan || self == .structuralPlan || self == .areaPlan }
    public var isVerticalCut: Bool { self == .elevation || self == .section || self == .detail }
    public var isModelView: Bool { self != .drafting && self != .legend }
    /// Heading used in the Project Browser.
    public var navigatorGroup: String {
        switch self {
        case .floorPlan: "Floor Plans"
        case .ceilingPlan: "Ceiling Plans"
        case .structuralPlan: "Structural Plans"
        case .areaPlan: "Area Plans"
        case .elevation: "Elevations"
        case .section: "Sections"
        case .detail: "Detail Views"
        case .drafting: "Drafting Views"
        case .legend: "Legends"
        case .threeD: "3D Views"
        }
    }
    public var symbolName: String {
        switch self {
        case .floorPlan, .structuralPlan, .areaPlan: "square.grid.3x3.topleft.filled"
        case .ceilingPlan: "rectangle.split.3x3"
        case .elevation: "building.2"
        case .section: "rectangle.split.2x1"
        case .detail: "plus.magnifyingglass"
        case .drafting: "pencil.and.ruler"
        case .legend: "list.bullet.rectangle"
        case .threeD: "cube"
        }
    }
}

public enum DetailLevel: String, Codable, Sendable, CaseIterable { case coarse = "Coarse", medium = "Medium", fine = "Fine" }

public enum VisualStyle: String, Codable, Sendable, CaseIterable {
    case wireframe = "Wireframe"
    case hiddenLine = "Hidden Line"
    case shaded = "Shaded"
    case consistentColors = "Consistent Colors"
    case transparent = "Transparent"
    /// Material appearance colors with physically based lighting, sky and environment (3D views).
    case realistic = "Realistic"

    /// Unknown styles (e.g. written by a newer version) fall back to Shaded instead of failing the whole view.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = VisualStyle(rawValue: raw) ?? .shaded
    }
}

public enum Discipline: String, Codable, Sendable, CaseIterable {
    case architectural = "Architectural", structural = "Structural", coordination = "Coordination"
}

/// Plan view range, offsets relative to named levels (nil level = the view's own level).
public struct ViewRange: Hashable, Codable, Sendable {
    public var topLevelID: ElementID?
    public var topOffset: Double
    public var cutOffset: Double
    public var bottomLevelID: ElementID?
    public var bottomOffset: Double
    public var depthLevelID: ElementID?
    public var depthOffset: Double
    /// Relative levels ("Level Above", "Level Below", "Unlimited") that override the level ids; nil in older files. BL-BROWSER
    public var topAnchor: ViewRangeAnchor?
    public var bottomAnchor: ViewRangeAnchor?
    public var depthAnchor: ViewRangeAnchor?
    public init(topOffset: Double = 2.3, cutOffset: Double = 1.2, bottomOffset: Double = 0, depthOffset: Double = 0) {
        topLevelID = nil; self.topOffset = topOffset; self.cutOffset = cutOffset
        bottomLevelID = nil; self.bottomOffset = bottomOffset; depthLevelID = nil; self.depthOffset = depthOffset
    }
    public static let floorPlanDefault = ViewRange(topOffset: 2.3, cutOffset: 1.2, bottomOffset: 0, depthOffset: 0)
    public static let ceilingPlanDefault = ViewRange(topOffset: 3.5, cutOffset: 2.3, bottomOffset: 2.3, depthOffset: 3.5)
}

public enum PhaseFilter: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case showAll = "Show All"
    case showComplete = "Show Complete"
    case showNew = "Show New"
    case showPreviousAndNew = "Show Previous + New"
    case showPreviousPhase = "Show Previous Phase"
    case showDemoAndNew = "Show Demo + New"
}

/// Graphic override applied to a category, filter, or element in a view.
public struct GraphicOverride: Hashable, Codable, Sendable {
    public var projectionLineWeight: Int?
    public var projectionLineColor: RGBColor?
    public var projectionLinePattern: LinePatternKind?
    public var cutLineWeight: Int?
    public var cutLineColor: RGBColor?
    public var cutLinePattern: LinePatternKind?
    public var surfacePattern: FillPatternKind?
    public var surfaceColor: RGBColor?
    public var cutPattern: FillPatternKind?
    public var cutPatternColor: RGBColor?
    public var transparency: Double?
    public var halftone: Bool?
    /// W4-HATCH: project fill patterns (by element) for surface and cut overrides; they win over the procedural kinds.
    public var surfacePatternID: ElementID?
    public var cutPatternID: ElementID?
    public init() {}
    public var isEmpty: Bool { self == GraphicOverride() }

    /// Overlays `o` on top of self (non-nil fields in o win).
    public func merged(with o: GraphicOverride) -> GraphicOverride {
        var r = self
        if let v = o.projectionLineWeight { r.projectionLineWeight = v }
        if let v = o.projectionLineColor { r.projectionLineColor = v }
        if let v = o.projectionLinePattern { r.projectionLinePattern = v }
        if let v = o.cutLineWeight { r.cutLineWeight = v }
        if let v = o.cutLineColor { r.cutLineColor = v }
        if let v = o.cutLinePattern { r.cutLinePattern = v }
        if let v = o.surfacePattern { r.surfacePattern = v }
        if let v = o.surfaceColor { r.surfaceColor = v }
        if let v = o.cutPattern { r.cutPattern = v }
        if let v = o.cutPatternColor { r.cutPatternColor = v }
        if let v = o.transparency { r.transparency = v }
        if let v = o.halftone { r.halftone = v }
        if let v = o.surfacePatternID { r.surfacePatternID = v } // W4-HATCH
        if let v = o.cutPatternID { r.cutPatternID = v } // W4-HATCH
        return r
    }
}

/// Visibility/Graphics settings for a view (or a view template).
public struct VisibilityGraphics: Hashable, Codable, Sendable {
    public var hiddenCategories: Set<Category>
    public var categoryOverrides: [Category: GraphicOverride]
    /// Applied filters in priority order (last wins).
    public var filters: [AppliedFilter]
    public var hiddenElements: Set<ElementID>
    public var elementOverrides: [ElementID: GraphicOverride]
    /// Hidden link layers: link element → layer names.
    public var hiddenLinkLayers: [ElementID: Set<String>]
    public var showLinks: Bool
    /// Categories that are hidden unless a view turns them on (project base point, survey point). WP6a; absent in older files.
    public var shownOptInCategories: Set<Category>?
    /// Subcategory overrides and hidden subcategories keyed by `Subcategories.key` ("doors/Plan Swing"). Optional: older files decode as nil.
    public var subcategoryOverrides: [String: GraphicOverride]? // BL-VG
    public var hiddenSubcategories: Set<String>? // BL-VG
    /// Per-category detail level ("By View" when absent). Optional: older files decode as nil.
    public var categoryDetailLevels: [Category: DetailLevel]? // BL-VG
    public init() {
        hiddenCategories = []; categoryOverrides = [:]; filters = []; hiddenElements = []; elementOverrides = [:]
        hiddenLinkLayers = [:]; showLinks = true
    }
}

public struct AppliedFilter: Hashable, Codable, Sendable {
    public var filterID: ElementID
    public var visible: Bool
    public var override: GraphicOverride
    public init(filterID: ElementID, visible: Bool = true, override: GraphicOverride = GraphicOverride()) {
        self.filterID = filterID; self.visible = visible; self.override = override
    }
}

/// Rule-based filter definition.
public struct ViewFilterData: Hashable, Codable, Sendable {
    public var categories: [Category]
    public var rules: [FilterRule]
    /// All rules must match when true; any when false.
    public var matchAll: Bool
    /// Nested rule sets combined with `rules` by `matchAll` (e.g. (A AND B) OR (C AND D)). Optional: older files decode as nil.
    public var groups: [FilterRuleGroup]? // BL-VG
    public init(categories: [Category], rules: [FilterRule], matchAll: Bool = true) {
        self.categories = categories; self.rules = rules; self.matchAll = matchAll
    }
}

public struct FilterRule: Hashable, Codable, Sendable {
    public enum Op: String, Codable, Sendable, CaseIterable {
        case equals = "equals", notEquals = "does not equal", greater = "is greater than", greaterOrEqual = "is greater than or equal to"
        case less = "is less than", lessOrEqual = "is less than or equal to", contains = "contains", notContains = "does not contain"
        case beginsWith = "begins with", endsWith = "ends with", hasValue = "has a value", hasNoValue = "has no value"
    }
    public var parameter: ParameterID
    public var op: Op
    public var value: ParamValue
    public init(parameter: ParameterID, op: Op, value: ParamValue) { self.parameter = parameter; self.op = op; self.value = value }
}

/// Which properties a view template controls.
public struct ViewTemplateData: Hashable, Codable, Sendable {
    public var appliesTo: ViewKind
    public var scale: Int?
    public var detailLevel: DetailLevel?
    public var visualStyle: VisualStyle?
    public var discipline: Discipline?
    public var viewRange: ViewRange?
    public var phaseFilter: PhaseFilter?
    public var visibility: VisibilityGraphics?
    public init(appliesTo: ViewKind) { self.appliesTo = appliesTo }
}

/// A saved camera for 3D views.
public struct Camera3D: Hashable, Codable, Sendable {
    public var eye: Vec3
    public var target: Vec3
    public var up: Vec3
    public var isPerspective: Bool
    public var fieldOfView: Double
    /// Orthographic view height in meters.
    public var orthoHeight: Double
    // W2-CAM: camera clipping and frame (optional; absent in older files → automatic near, no far clip, 3:2 frame).
    /// Near clip distance from the eye in meters; nil chooses one from the scene depth.
    public var nearClip: Double?
    /// Whether the far clip plane is on, and its distance from the eye in meters (kept while off).
    public var farClipActive: Bool?
    public var farClipDistance: Double?
    /// Camera frame (crop region) size on paper in meters; its aspect ratio is the frame shown when the view crops.
    public var cropWidth: Double?
    public var cropHeight: Double?
    public init(eye: Vec3, target: Vec3, up: Vec3 = .unitZ, isPerspective: Bool = false, fieldOfView: Double = 50 * .pi / 180, orthoHeight: Double = 40) {
        self.eye = eye; self.target = target; self.up = up; self.isPerspective = isPerspective
        self.fieldOfView = fieldOfView; self.orthoHeight = orthoHeight
    }
    public static let defaultIsometric = Camera3D(eye: Vec3(-30, -40, 30), target: Vec3(10, 10, 3))
}

/// A view: plan, elevation, section, drafting, legend or 3D.
public struct ViewData: Hashable, Codable, Sendable {
    public var kind: ViewKind
    /// Scale denominator: 100 means 1:100. Imperial scales map to their ratio (1/8" = 1'-0" → 96).
    public var scale: Int
    public var detailLevel: DetailLevel
    public var visualStyle: VisualStyle
    public var discipline: Discipline
    /// Crop region in view coordinates (plan: model XY; vertical views: (along, up) in the view plane).
    public var cropRegion: Rect2?
    /// F810: sketched crop boundary (View ▸ Callout ▸ Sketch), in view coordinates; the view clips to it inside
    /// `cropRegion` (its bounds). nil = rectangular crop. Optional: older files decode as nil.
    public var cropShape: [Vec2]?
    public var cropActive: Bool
    public var cropVisible: Bool
    public var annotationCropActive: Bool
    public var annotationCropOffset: Double
    public var viewRange: ViewRange
    public var underlayLevelID: ElementID?
    public var phaseID: ElementID?
    public var phaseFilter: PhaseFilter
    /// Design option shown for each option set (set name → option id). Unlisted sets show their primary.
    public var designOptions: [String: ElementID]
    public var templateID: ElementID?
    public var visibility: VisibilityGraphics
    /// F810: Show Hidden Lines pairs: lines of `hidden` behind `obscuring` draw dashed. Optional: older files decode as nil.
    public var hiddenLines: [HiddenLinePair]?
    /// Vertical views: the cut/elevation plane origin (on the plane), horizontal view direction (into the view), extents.
    public var planeOrigin: Vec3?
    public var viewDirection: Vec2?
    /// Far clip depth for vertical views (meters behind the plane).
    public var farClip: Double
    /// Camera for 3D views.
    public var camera: Camera3D?
    /// F810: walkthrough path and frames; the camera is the current frame's. Optional: older files decode as nil.
    public var walkthrough: WalkthroughData?
    public var sectionBox: Box3?
    public var sectionBoxActive: Bool
    /// Parent view for callouts and dependent views.
    public var parentViewID: ElementID?
    public var titleOnSheet: String
    /// Rotation of plan views relative to project north (radians, true-north display when `showTrueNorth`).
    public var showTrueNorth: Bool
    /// Crop for elevation/section marks in plan: marker position (elevations) is derived from `planeOrigin`.
    public var markerPosition: Vec2?
    /// Scope box the view's crop follows (plan views). WP6a; absent in older files.
    public var scopeBoxID: ElementID?
    /// Colour fill scheme applied to rooms/areas in plans and sections (nil = none). Optional: older files decode as nil.
    public var colorSchemeID: ElementID?
    /// Area plans: the area scheme whose areas and boundary lines the view shows. Optional: older files decode as nil.
    public var areaSchemeID: ElementID?
    /// F2: the view's work plane (Work Plane ▸ Set): nil = its default (a plan's level, the view plane of a section or
    /// elevation, the 3D tools' level). Optional: older files decode as nil.
    public var workPlane: WorkPlaneRef?
    /// F2: Work Plane ▸ Show: the work plane's grid is drawn in the view. Optional: older files decode as nil (hidden).
    public var showsWorkPlane: Bool?

    // MARK: 3D graphic display options (optional; absent in older files → defaults, see GraphicDisplayOptions.swift)

    /// Shadows, ambient shadows, silhouettes and sun settings for 3D views. nil means defaults; read through
    /// `displayOptions`.
    public var graphicDisplay: GraphicDisplayOptions?

    public init(kind: ViewKind, scale: Int = 100) {
        self.kind = kind; self.scale = scale; detailLevel = kind == .threeD ? .medium : .medium
        visualStyle = kind == .threeD ? .shaded : .hiddenLine
        discipline = .architectural; cropRegion = nil; cropActive = false; cropVisible = false
        annotationCropActive = false; annotationCropOffset = 0.01
        viewRange = kind == .ceilingPlan ? .ceilingPlanDefault : .floorPlanDefault
        underlayLevelID = nil; phaseID = nil; phaseFilter = .showAll; designOptions = [:]; templateID = nil
        visibility = VisibilityGraphics(); planeOrigin = nil; viewDirection = nil; farClip = 30; camera = nil
        sectionBox = nil; sectionBoxActive = false; parentViewID = nil; titleOnSheet = ""; showTrueNorth = false; markerPosition = nil
    }

    /// For vertical views: the in-plane right vector (horizontal) for a viewer looking along `viewDirection`.
    public var rightVector: Vec2? {
        guard let d = viewDirection?.normalized else { return nil }
        return Vec2(-d.y, d.x) * -1 // right-hand side when looking along d: rotate d by -90°
    }
}

/// View scale presets.
public enum ViewScales {
    public static let metric: [Int] = [1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000]
    public static let imperial: [(label: String, value: Int)] = [
        ("12\" = 1'-0\"", 1), ("6\" = 1'-0\"", 2), ("3\" = 1'-0\"", 4), ("1 1/2\" = 1'-0\"", 8), ("1\" = 1'-0\"", 12),
        ("3/4\" = 1'-0\"", 16), ("1/2\" = 1'-0\"", 24), ("3/8\" = 1'-0\"", 32), ("1/4\" = 1'-0\"", 48), ("3/16\" = 1'-0\"", 64),
        ("1/8\" = 1'-0\"", 96), ("3/32\" = 1'-0\"", 128), ("1/16\" = 1'-0\"", 192), ("1\" = 20'-0\"", 240), ("1\" = 50'-0\"", 600),
    ]
    public static func label(_ scale: Int, imperial: Bool) -> String {
        if imperial, let e = self.imperial.first(where: { $0.value == scale }) { return e.label }
        return "1 : \(scale)"
    }
}

extension AppliedFilter: Identifiable {
    public var id: ElementID { filterID }
}
