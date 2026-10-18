import Foundation
import ArcusGeometry
import ArcusCalc

/// sRGB color with alpha, components 0…1.
public struct RGBColor: Hashable, Codable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    public init(hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255; g = Double((hex >> 8) & 0xff) / 255; b = Double(hex & 0xff) / 255; a = 1
    }
    public static let black = RGBColor(0, 0, 0)
    public static let white = RGBColor(1, 1, 1)
    public static let gray = RGBColor(0.5, 0.5, 0.5)
    public var hexString: String {
        String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
    public func mixed(with o: RGBColor, amount t: Double) -> RGBColor {
        RGBColor(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t)
    }
    public var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

/// System family kinds (families that live only in projects).
public enum SystemFamily: String, Codable, Sendable, CaseIterable {
    case basicWall = "Basic Wall"
    case floor = "Floor"
    case ceiling = "Compound Ceiling"
    case roof = "Basic Roof"
    case stair = "Assembled Stair"
    case railing = "Railing"
    case level = "Level"
    case grid = "Grid"
    case buildingPad = "Building Pad"
    case topography = "Toposurface"
    case toposolid = "Toposolid" // BL-SITE
    case floorPlanView = "Floor Plan"
    case ceilingPlanView = "Ceiling Plan"
    case structuralPlanView = "Structural Plan"
    case elevationView = "Elevation"
    case sectionView = "Section"
    case detailView = "Detail View"
    case draftingView = "Drafting View"
    case legendView = "Legend"
    case threeDView = "3D View"
    case scheduleView = "Schedule"
    case sheet = "Sheet"
    case viewport = "Viewport"
    case dimensionStyle = "Linear Dimension Style"
    case angularDimensionStyle = "Angular Dimension Style"
    case radialDimensionStyle = "Radial Dimension Style"
    case spotElevationStyle = "Spot Elevations"
    case spotCoordinateStyle = "Spot Coordinates"
    case spotSlopeStyle = "Spot Slopes"
    case textStyle = "Text"
    case filledRegion = "Filled Region"
    case room = "Room"
    case area = "Area"
    case revisionCloud = "Revision Cloud"
    case insulation = "Insulation"
    case ramp = "Ramp"
    case curtainWall = "Curtain Wall"
    case curtainPanel = "System Panel"
    case stackedWall = "Stacked Wall" // F2
}

public enum LayerFunction: String, Codable, Sendable, CaseIterable {
    case structure = "Structure [1]"
    case substrate = "Substrate [2]"
    case thermal = "Thermal/Air Layer [3]"
    case membrane = "Membrane Layer"
    case finish1 = "Finish 1 [4]"
    case finish2 = "Finish 2 [5]"

    /// Join priority: lower numbers join first (structure highest priority).
    public var priority: Int {
        switch self {
        case .structure: 1
        case .substrate: 2
        case .thermal: 3
        case .finish1: 4
        case .finish2: 5
        case .membrane: 0
        }
    }
}

public struct AssemblyLayer: Hashable, Codable, Sendable {
    public var function: LayerFunction
    public var materialID: ElementID?
    public var thickness: Double
    public var wraps: Bool
    public var isVariable: Bool
    public init(function: LayerFunction, materialID: ElementID?, thickness: Double, wraps: Bool = false) {
        self.function = function; self.materialID = materialID; self.thickness = thickness; self.wraps = wraps; self.isVariable = false
    }
}

public enum WrappingPreference: String, Codable, Sendable, CaseIterable {
    case doNotWrap = "Do not wrap", exterior = "Exterior", interior = "Interior", both = "Both"
}

/// Ordered layers from exterior (index 0) to interior for walls, top to bottom for floors/roofs/ceilings.
public struct CompoundAssembly: Hashable, Codable, Sendable {
    public var layers: [AssemblyLayer]
    /// Index of the first core layer and one past the last core layer.
    public var coreStart: Int
    public var coreEnd: Int
    public var wrappingAtInserts: WrappingPreference
    public var wrappingAtEnds: WrappingPreference

    public init(layers: [AssemblyLayer], coreStart: Int? = nil, coreEnd: Int? = nil) {
        self.layers = layers
        let s = layers.firstIndex { $0.function == .structure } ?? 0
        let e = (layers.lastIndex { $0.function == .structure } ?? max(0, layers.count - 1)) + 1
        self.coreStart = coreStart ?? s
        self.coreEnd = coreEnd ?? e
        self.wrappingAtInserts = .doNotWrap
        self.wrappingAtEnds = .doNotWrap
    }

    public var totalThickness: Double { layers.reduce(0) { $0 + $1.thickness } }
    /// Core range clamped to valid layer indices (robust to hostile or stale data).
    var safeCore: Range<Int> {
        let s = max(0, min(coreStart, layers.count))
        let e = max(s, min(coreEnd, layers.count))
        return s..<e
    }
    public var coreThickness: Double { layers[safeCore].reduce(0) { $0 + $1.thickness } }
    /// Distance from the exterior face to the start of the core.
    public var exteriorToCore: Double { layers[0..<safeCore.lowerBound].reduce(0) { $0 + $1.thickness } }
    /// Distances from the exterior face to each layer boundary (count = layers.count + 1).
    public var boundaries: [Double] {
        var out = [0.0]
        var acc = 0.0
        for l in layers { acc += l.thickness; out.append(acc) }
        return out
    }

    public enum ValidationError: Error, Hashable, Sendable, CustomStringConvertible {
        case noLayers, nonPositiveThickness(Int), invalidCore, membraneWithThickness(Int)
        public var description: String {
            switch self {
            case .noLayers: "An assembly needs at least one layer."
            case .nonPositiveThickness(let i): "Layer \(i + 1) must be thicker than zero."
            case .invalidCore: "The core boundaries are outside the layer list."
            case .membraneWithThickness(let i): "Membrane layer \(i + 1) must have zero thickness."
            }
        }
    }
    public func validate() -> ValidationError? {
        if layers.isEmpty { return .noLayers }
        for (i, l) in layers.enumerated() {
            if l.function == .membrane {
                if l.thickness > Tolerance.length { return .membraneWithThickness(i) }
            } else if l.thickness <= Tolerance.length { return .nonPositiveThickness(i) }
        }
        // BL-PROPS: an empty core (coreStart == coreEnd) is allowed — core-less structures, as in current BIM tools.
        if coreStart < 0 || coreEnd > layers.count || coreStart > coreEnd { return .invalidCore }
        return nil
    }
}

/// An element type (the "type" of a family). Type parameters live here.
public struct TypeData: Hashable, Codable, Sendable {
    /// Category of the instances of this type.
    public var instanceCategory: Category
    public var systemFamily: SystemFamily?
    /// Loadable family element for component types.
    public var familyID: ElementID?
    public var familyName: String
    public var params: [ParameterID: ParamValue]
    public var assembly: CompoundAssembly?
    /// Curtain wall types: grid, panel and mullion rules (nil for every other type).
    public var curtain: CurtainSpec?
    /// F2: stacked wall types: the basic wall types stacked from the bottom up (nil for every other type).
    public var stack: StackedWallSpec?
    public init(instanceCategory: Category, systemFamily: SystemFamily? = nil, familyID: ElementID? = nil, familyName: String,
                params: [ParameterID: ParamValue] = [:], assembly: CompoundAssembly? = nil) {
        self.instanceCategory = instanceCategory; self.systemFamily = systemFamily; self.familyID = familyID
        self.familyName = familyName; self.params = params; self.assembly = assembly; self.curtain = nil
    }
}

public enum MaterialClass: String, Codable, Sendable, CaseIterable {
    case generic = "Generic", concrete = "Concrete", masonry = "Masonry", metal = "Metal", wood = "Wood"
    case glass = "Glass", plaster = "Plaster", insulation = "Insulation", stone = "Stone", ceramic = "Ceramic"
    case plastic = "Plastic", earth = "Earth", paint = "Paint", liquid = "Liquid", gas = "Gas"
}

public struct MaterialData: Hashable, Codable, Sendable {
    public var materialClass: MaterialClass
    public var color: RGBColor
    public var transparency: Double
    public var surfacePatternID: ElementID?
    public var surfacePatternColor: RGBColor
    public var cutPatternID: ElementID?
    public var cutPatternColor: RGBColor
    public var description: String
    public var manufacturer: String
    public var model: String
    public var cost: Double
    public var keynote: String
    public var mark: String
    public init(materialClass: MaterialClass, color: RGBColor, transparency: Double = 0, description: String = "") {
        self.materialClass = materialClass; self.color = color; self.transparency = transparency
        self.surfacePatternID = nil; self.surfacePatternColor = .black; self.cutPatternID = nil; self.cutPatternColor = .black
        self.description = description; self.manufacturer = ""; self.model = ""; self.cost = 0; self.keynote = ""; self.mark = ""
    }
}

public struct PhaseData: Hashable, Codable, Sendable {
    /// Sequence order: lower is earlier.
    public var order: Int
    public var description: String
    public init(order: Int, description: String = "") { self.order = order; self.description = description }
}

public struct DesignOptionData: Hashable, Codable, Sendable {
    public var setName: String
    public var isPrimary: Bool
    public init(setName: String, isPrimary: Bool) { self.setName = setName; self.isPrimary = isPrimary }
}

public struct AreaSchemeData: Hashable, Codable, Sendable {
    public var description: String
    /// Where automatic boundary lines sit on exterior walls. Optional so older files decode (nil = gross).
    public var boundaryRule: AreaBoundaryRule?
    public init(description: String = "", boundaryRule: AreaBoundaryRule? = nil) { self.description = description; self.boundaryRule = boundaryRule }
    public var rule: AreaBoundaryRule { boundaryRule ?? .gross }
}

/// Geographic and project-wide settings.
public struct ProjectInfoData: Hashable, Codable, Sendable {
    public var projectNumber: String
    public var projectName: String
    public var clientName: String
    public var address: String
    public var status: String
    public var issueDate: String
    public var author: String
    public var organization: String
    public var buildingName: String
    public var units: UnitsSettings
    /// Angle from project north to true north (radians, counter-clockwise positive).
    public var trueNorthAngle: Double
    public var latitude: Double
    public var longitude: Double
    public var elevationAboveSeaLevel: Double
    public var siteName: String
    /// Project base point in internal coordinates.
    public var projectBasePoint: Vec3
    /// Survey point in internal coordinates and its shared-coordinate values.
    public var surveyPoint: Vec3
    public var surveyEasting: Double
    public var surveyNorthing: Double
    public var surveyElevation: Double
    /// Model extents limit used by health checks (meters from the internal origin).
    public var extentsWarningDistance: Double
    /// Naming pattern for new sheets: prefix and digits.
    public var sheetNumberPrefix: String
    /// Project Object Styles: per category/subcategory line weights, colour, pattern and material. Optional: older files decode as nil.
    public var objectStyles: ObjectStyleSettings? // BL-VG
    /// Global parameters, saved selections, starting view, keynoting and print setup (ManageProjectData.swift). Optional: older files decode as nil. // F11
    public var f11: ManageProjectData?

    public init(projectName: String = "Project Name", units: UnitsSettings = .metric) {
        projectNumber = "0001"; self.projectName = projectName; clientName = "Owner"; address = ""; status = "Project Status"
        issueDate = ""; author = ""; organization = ""; buildingName = ""; self.units = units; trueNorthAngle = 0
        latitude = 0; longitude = 0; elevationAboveSeaLevel = 0; siteName = "Default Site"
        projectBasePoint = .zero; surveyPoint = .zero; surveyEasting = 0; surveyNorthing = 0; surveyElevation = 0
        extentsWarningDistance = Tolerance.farFromOrigin; sheetNumberPrefix = "A"
    }
}

// MARK: - Graphics resources

public enum LinePatternKind: String, Codable, Sendable, CaseIterable {
    case solid = "Solid", dash = "Dash", hidden = "Hidden", center = "Center", dot = "Dot", dashDot = "Dash Dot", overhead = "Overhead"
    case longDash = "Long Dash", doubleDash = "Double Dash", dashDotDot = "Dash Dot Dot", demolished = "Demolished"

    /// Dash lengths on paper in millimeters (on, off, on, off…), at most four dashes. Empty for solid. Lengths are paper
    /// sizes: a view at any scale prints the same dashes, and renderers convert them with the paper-to-device factor.
    public var dashPattern: [Double] {
        switch self {
        case .solid: []
        case .dash: [3, 1.5]
        case .hidden: [1.5, 1.5]
        case .center: [8, 1.5, 1.5, 1.5]
        case .dot: [0.2, 1.2]
        case .dashDot: [4, 1.2, 0.2, 1.2]
        case .overhead: [2.5, 1.2]
        case .longDash: [9, 2]
        case .doubleDash: [5, 1, 5, 3]
        case .dashDotDot: [7, 1.2, 0.2, 1.2, 0.2, 1.2]
        case .demolished: [2, 1]
        }
    }
}

public struct LineStyleData: Hashable, Codable, Sendable {
    /// Line weight number 1…16 (see `LineWeights`).
    public var weight: Int
    public var color: RGBColor
    public var pattern: LinePatternKind
    public init(weight: Int, color: RGBColor = .black, pattern: LinePatternKind = .solid) { self.weight = weight; self.color = color; self.pattern = pattern }
}

public enum FillPatternKind: String, Codable, Sendable, CaseIterable {
    case solid = "Solid Fill"
    case diagonalUp = "Diagonal Up"
    case diagonalDown = "Diagonal Down"
    case crosshatch = "Crosshatch"
    case diagonalCrosshatch = "Diagonal Crosshatch"
    case horizontal = "Horizontal"
    case vertical = "Vertical"
    case concrete = "Concrete"
    case brick = "Brick"
    case insulation = "Insulation"
    case sand = "Sand"
    case wood = "Wood Grain"
    case grid = "Grid"
    case earth = "Earth"
}

public struct FillPatternData: Hashable, Codable, Sendable {
    /// Procedural kind: the pattern of older files, and the fallback when a line-family hatch is too dense to draw.
    public var kind: FillPatternKind
    /// Drafting patterns scale with paper (spacing in paper mm); model patterns are fixed in model meters.
    public var isModelPattern: Bool
    public var spacing: Double
    /// W4-HATCH: line families (millimetres: paper for drafting, model for model patterns). nil in older files.
    public var families: [HatchFamily]?
    public var description: String?
    public init(kind: FillPatternKind, isModelPattern: Bool = false, spacing: Double = 2.0) {
        self.kind = kind; self.isModelPattern = isModelPattern; self.spacing = spacing
    }
}

// MARK: - Constraints

/// A persistent constraint between geometric references.
public struct ConstraintData: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Distance between parallel references is locked to `value`.
        case lockedDistance
        /// References are aligned (collinear/coplanar).
        case alignment
        /// Consecutive distances along the references are equal.
        case equality
        /// Solid join: the first reference's element cuts the overlapping volume out of the second's.
        case join
    }
    public var kind: Kind
    public var references: [GeometryReference]
    public var value: Double
    /// The dimension that owns this constraint (lock/EQ on a permanent dimension), if any.
    public var dimensionID: ElementID?
    public init(kind: Kind, references: [GeometryReference], value: Double = 0, dimensionID: ElementID? = nil) {
        self.kind = kind; self.references = references; self.value = value; self.dimensionID = dimensionID
    }
}
