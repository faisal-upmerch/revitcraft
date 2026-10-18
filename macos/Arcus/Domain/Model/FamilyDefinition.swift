import Foundation
import ArcusGeometry

/// Category templates for new loadable families.
public enum FamilyTemplate: String, Codable, Sendable, CaseIterable {
    case door = "Door"
    case window = "Window"
    case furniture = "Furniture"
    case casework = "Casework"
    case genericModel = "Generic Model"
    case column = "Column"
    case structuralColumn = "Structural Column"
    case structuralFraming = "Structural Framing"
    case plumbingFixture = "Plumbing Fixture"
    case tag = "Tag"
    case genericAnnotation = "Generic Annotation"
    case titleBlock = "Title Block"
    case profile = "Profile"
    case detailComponent = "Detail Component"
    // W2-LIB: component library categories
    case lightingFixture = "Lighting Fixture"
    case electricalFixture = "Electrical Fixture"
    case mechanicalEquipment = "Mechanical Equipment"
    case specialtyEquipment = "Specialty Equipment"
    case planting = "Planting"
    case entourage = "Entourage"
    case parking = "Parking"
    case site = "Site"

    public var category: Category {
        switch self {
        case .door: .doors
        case .window: .windows
        case .furniture: .furniture
        case .casework: .casework
        case .genericModel: .genericModels
        case .column: .columns
        case .structuralColumn: .structuralColumns
        case .structuralFraming: .structuralFraming
        case .plumbingFixture: .plumbingFixtures
        case .tag: .tags
        case .genericAnnotation: .genericAnnotations
        case .titleBlock: .titleBlocks
        case .profile: .detailComponents
        case .detailComponent: .detailComponents
        case .lightingFixture: .lightingFixtures // W2-LIB
        case .electricalFixture: .electricalFixtures
        case .mechanicalEquipment: .mechanicalEquipment
        case .specialtyEquipment: .specialtyEquipment
        case .planting: .planting
        case .entourage: .entourage
        case .parking: .parking
        case .site: .site
        }
    }
    public var isHostedInWall: Bool { self == .door || self == .window }
    public var is3D: Bool {
        switch self {
        case .tag, .genericAnnotation, .titleBlock, .profile, .detailComponent: false
        default: true
        }
    }
}

/// A family parameter. Values are provided per type (type parameters) or per instance.
public struct FamilyParameter: Hashable, Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var type: ParamType
    public var isInstance: Bool
    public var group: ParameterGroup
    /// Formula driving this parameter; nil = user value.
    public var formula: String?
    /// Built-in parameters (Width, Height…) cannot be deleted/renamed.
    public var isBuiltIn: Bool
    public init(name: String, type: ParamType, isInstance: Bool = false, group: ParameterGroup = .dimensions, formula: String? = nil, isBuiltIn: Bool = false) {
        self.name = name; self.type = type; self.isInstance = isInstance; self.group = group; self.formula = formula; self.isBuiltIn = isBuiltIn
    }
}

public struct FamilyTypeDefinition: Hashable, Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    /// Values for non-formula parameters by name.
    public var values: [String: ParamValue]
    public init(name: String, values: [String: ParamValue]) { self.name = name; self.values = values }
}

/// Axis of a family reference plane's normal.
public enum FamilyAxis: String, Codable, Sendable, CaseIterable { case x = "X", y = "Y", z = "Z" }

public enum ReferenceStrength: String, Codable, Sendable, CaseIterable {
    case notAReference = "Not a Reference", weak = "Weak Reference", strong = "Strong Reference"
    case left = "Left", centerLeftRight = "Center (Left/Right)", right = "Right"
    case front = "Front", centerFrontBack = "Center (Front/Back)", back = "Back"
    case bottom = "Bottom", centerElevation = "Center (Elevation)", top = "Top"
}

/// A reference plane in family coordinates, positioned by an expression (formula) along its axis.
public struct FamilyReferencePlane: Hashable, Codable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var axis: FamilyAxis
    /// Offset from the family origin along `axis`. A formula string (e.g. "Width / 2", "0", "-Depth").
    public var offset: String
    public var strength: ReferenceStrength
    /// Origin-defining planes cannot be moved.
    public var definesOrigin: Bool
    public init(name: String, axis: FamilyAxis, offset: String, strength: ReferenceStrength = .weak, definesOrigin: Bool = false) {
        self.name = name; self.axis = axis; self.offset = offset; self.strength = strength; self.definesOrigin = definesOrigin
    }
}

/// A bound for solids and lines: either a named reference plane (locked) or a free expression.
public enum FamilyBound: Hashable, Codable, Sendable {
    case plane(String)
    case expr(String)
}

public enum FamilySubcategory: String, Codable, Sendable, CaseIterable {
    case general = "General", frame = "Frame/Mullion", panel = "Panel", glass = "Glass", opening = "Opening"
    case swing = "Plan Swing", elevationSwing = "Elevation Swing", hidden = "Hidden Lines", sill = "Sill/Head"
}

/// A sweep: a closed profile carried along an open plan path.
///
/// The path lies in family XY at the solid's base elevation (`FamilySolid.zMin`). Profile coordinates are
/// (x = horizontal offset to the left of the path direction, y = height above the path).
public struct FamilySweep: Hashable, Codable, Sendable {
    public var path: [FamilyPoint]
    public var profile: [FamilyPoint]
    /// Name of an embedded profile family (`FamilyDefinition.nestedFamilies`) whose profile loop is used instead of `profile`.
    public var profileFamily: String?
    /// Type of the profile family (nil = its first type).
    public var profileFamilyType: String?
    public init(path: [FamilyPoint], profile: [FamilyPoint], profileFamily: String? = nil, profileFamilyType: String? = nil) {
        self.path = path; self.profile = profile; self.profileFamily = profileFamily; self.profileFamilyType = profileFamilyType
    }
}

/// A blend: a solid lofted from a bottom plan loop at `zMin` to a top plan loop at `zMax`.
public struct FamilyBlend: Hashable, Codable, Sendable {
    public var bottom: [FamilyPoint]
    public var top: [FamilyPoint]
    public init(bottom: [FamilyPoint], top: [FamilyPoint]) { self.bottom = bottom; self.top = top }
}

/// A revolve: a closed profile turned about a vertical axis.
///
/// Profile coordinates are (x = distance from the axis, y = height above the solid's base `zMin`).
public struct FamilyRevolve: Hashable, Codable, Sendable {
    public var profile: [FamilyPoint]
    /// Plan position of the vertical axis.
    public var axis: FamilyPoint
    /// Start and end angles in degrees (expressions), measured counterclockwise from +X.
    public var startDegrees: String
    public var endDegrees: String
    public init(profile: [FamilyPoint], axis: FamilyPoint = FamilyPoint("0", "0"), startDegrees: String = "0", endDegrees: String = "360") {
        self.profile = profile; self.axis = axis; self.startDegrees = startDegrees; self.endDegrees = endDegrees
    }
}

/// A family solid or void: an extrusion (rectangle, polygon or circle profile between `zMin` and `zMax`),
/// a sweep, a blend or a revolve.
public struct FamilySolid: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public enum Profile: Hashable, Codable, Sendable {
        case rectangle(xMin: FamilyBound, xMax: FamilyBound, yMin: FamilyBound, yMax: FamilyBound)
        /// Polygon with expression coordinates.
        case polygon([FamilyPoint])
        /// Circle (for round columns, fixtures).
        case circle(center: FamilyPoint, radius: String)
        /// Sweep along a plan path starting at `zMin`.
        case sweep(FamilySweep)
        /// Blend between two plan loops at `zMin` and `zMax`.
        case blend(FamilyBlend)
        /// Revolve about a vertical axis, profile heights measured from `zMin`.
        case revolve(FamilyRevolve)

        /// True for the vertical extrusion forms (rectangle, polygon, circle).
        public var isExtrusion: Bool {
            switch self {
            case .rectangle, .polygon, .circle: true
            case .sweep, .blend, .revolve: false
            }
        }
        public var formName: String {
            switch self {
            case .rectangle, .polygon, .circle: "Extrusion"
            case .sweep: "Sweep"
            case .blend: "Blend"
            case .revolve: "Revolve"
            }
        }
    }
    public var profile: Profile
    public var zMin: FamilyBound
    public var zMax: FamilyBound
    /// Parameter (material type) assigning the material; nil = category default.
    public var materialParameter: String?
    public var subcategory: FamilySubcategory
    public var isVoid: Bool
    /// Boolean parameter controlling visibility.
    public var visibilityParameter: String?
    public var visibleAt: Set<DetailLevel>
    /// Shown in plan and ceiling plan views.
    public var visibleInPlan: Bool
    /// Shown in 3D views.
    public var visibleIn3D: Bool
    /// Shown in elevations and sections looking at the family's front or back.
    public var visibleInFrontBack: Bool
    /// Shown in elevations and sections looking at the family's left or right side.
    public var visibleInLeftRight: Bool
    public init(name: String, profile: Profile, zMin: FamilyBound, zMax: FamilyBound, materialParameter: String? = nil,
                subcategory: FamilySubcategory = .general, isVoid: Bool = false, visibleInPlan: Bool = true) {
        id = UUID().uuidString; self.name = name; self.profile = profile; self.zMin = zMin; self.zMax = zMax
        self.materialParameter = materialParameter; self.subcategory = subcategory; self.isVoid = isVoid
        visibilityParameter = nil; visibleAt = [.coarse, .medium, .fine]; self.visibleInPlan = visibleInPlan
        visibleIn3D = true; visibleInFrontBack = true; visibleInLeftRight = true
    }

    enum CodingKeys: String, CodingKey {
        case id, name, profile, zMin, zMax, materialParameter, subcategory, isVoid, visibilityParameter, visibleAt, visibleInPlan
        case visibleIn3D, visibleInFrontBack, visibleInLeftRight
    }
    /// Families written before the view-visibility settings existed decode as visible everywhere.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        profile = try c.decode(Profile.self, forKey: .profile)
        zMin = try c.decode(FamilyBound.self, forKey: .zMin)
        zMax = try c.decode(FamilyBound.self, forKey: .zMax)
        materialParameter = try c.decodeIfPresent(String.self, forKey: .materialParameter)
        subcategory = try c.decodeIfPresent(FamilySubcategory.self, forKey: .subcategory) ?? .general
        isVoid = try c.decodeIfPresent(Bool.self, forKey: .isVoid) ?? false
        visibilityParameter = try c.decodeIfPresent(String.self, forKey: .visibilityParameter)
        visibleAt = try c.decodeIfPresent(Set<DetailLevel>.self, forKey: .visibleAt) ?? [.coarse, .medium, .fine]
        visibleInPlan = try c.decodeIfPresent(Bool.self, forKey: .visibleInPlan) ?? true
        visibleIn3D = try c.decodeIfPresent(Bool.self, forKey: .visibleIn3D) ?? true
        visibleInFrontBack = try c.decodeIfPresent(Bool.self, forKey: .visibleInFrontBack) ?? true
        visibleInLeftRight = try c.decodeIfPresent(Bool.self, forKey: .visibleInLeftRight) ?? true
    }
}

public struct FamilyPoint: Hashable, Codable, Sendable {
    public var x: FamilyBound
    public var y: FamilyBound
    public init(_ x: FamilyBound, _ y: FamilyBound) { self.x = x; self.y = y }
    public init(_ x: String, _ y: String) { self.x = .expr(x); self.y = .expr(y) }
}

/// Symbolic (2D) line shown in plan, or in annotation/title-block families.
public struct FamilyLine: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public enum Shape: Hashable, Codable, Sendable {
        case line(FamilyPoint, FamilyPoint)
        /// Arc: center, radius expression, start and sweep angle expressions (degrees).
        case arc(center: FamilyPoint, radius: String, startDegrees: String, sweepDegrees: String)
    }
    public var shape: Shape
    public var subcategory: FamilySubcategory
    /// Line weight for annotation families (1…16); model families use category styles.
    public var weight: Int
    public var visibilityParameter: String?
    public var visibleAt: Set<DetailLevel>
    public init(shape: Shape, subcategory: FamilySubcategory = .general, weight: Int = 1) {
        id = UUID().uuidString; self.shape = shape; self.subcategory = subcategory; self.weight = weight
        visibilityParameter = nil; visibleAt = [.coarse, .medium, .fine]
    }
}

/// Filled region inside an annotation / detail family (solid or masking).
public struct FamilyFill: Hashable, Codable, Sendable {
    public var points: [FamilyPoint]
    public var pattern: FillPatternKind
    public var isMasking: Bool
    public init(points: [FamilyPoint], pattern: FillPatternKind = .solid, isMasking: Bool = false) { self.points = points; self.pattern = pattern; self.isMasking = isMasking }
}

/// A text label in annotation families (tags, title blocks). Shows a parameter value or fixed text.
public struct FamilyLabel: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var position: FamilyPoint
    /// Parameter shown; for tags this is a parameter of the tagged element, for title blocks a sheet/project parameter.
    public var parameterName: String?
    public var staticText: String
    /// Text height on paper (meters).
    public var height: Double
    public var alignment: TextAlignment
    public var bold: Bool
    public var sample: String
    public init(position: FamilyPoint, parameterName: String?, staticText: String = "", height: Double = 0.0025, alignment: TextAlignment = .center, bold: Bool = false, sample: String = "?") {
        id = UUID().uuidString; self.position = position; self.parameterName = parameterName; self.staticText = staticText
        self.height = height; self.alignment = alignment; self.bold = bold; self.sample = sample
    }
}

/// A dimension in the family editor between reference planes. It constrains the planes it measures:
///
/// - labeled with a parameter: the distance from A to B equals the parameter's value;
/// - locked: the distance from A to B stays at its sketched value (the planes' own offsets);
/// - equality (EQ): plane B stays midway between A and `planeC`.
///
/// Constraints take precedence over plane offsets; planes not fixed by constraints keep their offsets.
public struct FamilyDimension: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var planeA: String
    public var planeB: String
    public var labelParameter: String?
    /// Equality constraint across the three planes A, B and `planeC` (EQ).
    public var planeC: String?
    public var isEquality: Bool
    /// Locks the current (sketched) distance between A and B.
    public var isLocked: Bool
    /// Side of A that B is kept on when a label drives the distance (+1 = toward +axis, −1 = toward −axis), fixed when the
    /// label is applied; nil takes it from the sketched offsets on every evaluation (families written before it existed).
    public var direction: Int? // BL-SITE
    public init(planeA: String, planeB: String, labelParameter: String? = nil) {
        id = UUID().uuidString; self.planeA = planeA; self.planeB = planeB; self.labelParameter = labelParameter; planeC = nil; isEquality = false
        isLocked = false
        direction = nil // BL-SITE
    }
    /// An EQ constraint keeping `middle` equidistant from `a` and `c`.
    public static func equality(_ a: String, _ middle: String, _ c: String) -> FamilyDimension {
        var d = FamilyDimension(planeA: a, planeB: middle)
        d.planeC = c
        d.isEquality = true
        return d
    }

    enum CodingKeys: String, CodingKey { case id, planeA, planeB, labelParameter, planeC, isEquality, isLocked, direction } // BL-SITE
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        planeA = try c.decode(String.self, forKey: .planeA)
        planeB = try c.decode(String.self, forKey: .planeB)
        labelParameter = try c.decodeIfPresent(String.self, forKey: .labelParameter)
        planeC = try c.decodeIfPresent(String.self, forKey: .planeC)
        isEquality = try c.decodeIfPresent(Bool.self, forKey: .isEquality) ?? false
        isLocked = try c.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        direction = try c.decodeIfPresent(Int.self, forKey: .direction) // BL-SITE
    }
}

/// An instance of an embedded (nested) family placed inside a host family.
///
/// `bindings` associate nested parameters with the host: each maps a nested parameter name to a host formula
/// (usually just a host parameter name, e.g. "Width" or "Width / 2 - 50 mm").
public struct NestedFamilyInstance: Hashable, Codable, Sendable, Identifiable {
    public var id: String
    /// Name of the embedded family (`FamilyDefinition.nestedFamilies`).
    public var familyName: String
    /// Type of the nested family (nil = its first type).
    public var typeName: String?
    /// Insertion point in host coordinates (bounds may lock to host reference planes).
    public var x: FamilyBound
    public var y: FamilyBound
    public var z: FamilyBound
    /// Rotation about the vertical axis in degrees (expression).
    public var rotation: String
    /// Mirrors the nested family across its own YZ plane before rotation.
    public var mirrored: Bool
    public var bindings: [String: String]
    public var visibilityParameter: String?
    public var visibleAt: Set<DetailLevel>
    public init(familyName: String, typeName: String? = nil, x: FamilyBound = .expr("0"), y: FamilyBound = .expr("0"), z: FamilyBound = .expr("0"),
                rotation: String = "0", mirrored: Bool = false, bindings: [String: String] = [:]) {
        id = UUID().uuidString; self.familyName = familyName; self.typeName = typeName; self.x = x; self.y = y; self.z = z
        self.rotation = rotation; self.mirrored = mirrored; self.bindings = bindings
        visibilityParameter = nil; visibleAt = [.coarse, .medium, .fine]
    }

    enum CodingKeys: String, CodingKey { case id, familyName, typeName, x, y, z, rotation, mirrored, bindings, visibilityParameter, visibleAt }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        familyName = try c.decode(String.self, forKey: .familyName)
        typeName = try c.decodeIfPresent(String.self, forKey: .typeName)
        x = try c.decodeIfPresent(FamilyBound.self, forKey: .x) ?? .expr("0")
        y = try c.decodeIfPresent(FamilyBound.self, forKey: .y) ?? .expr("0")
        z = try c.decodeIfPresent(FamilyBound.self, forKey: .z) ?? .expr("0")
        rotation = try c.decodeIfPresent(String.self, forKey: .rotation) ?? "0"
        mirrored = try c.decodeIfPresent(Bool.self, forKey: .mirrored) ?? false
        bindings = try c.decodeIfPresent([String: String].self, forKey: .bindings) ?? [:]
        visibilityParameter = try c.decodeIfPresent(String.self, forKey: .visibilityParameter)
        visibleAt = try c.decodeIfPresent(Set<DetailLevel>.self, forKey: .visibleAt) ?? [.coarse, .medium, .fine]
    }
}

/// Opening cut in the host wall (doors/windows), in family coordinates.
public struct FamilyOpening: Hashable, Codable, Sendable {
    public var xMin: FamilyBound
    public var xMax: FamilyBound
    public var zMin: FamilyBound
    public var zMax: FamilyBound
    public init(xMin: FamilyBound, xMax: FamilyBound, zMin: FamilyBound, zMax: FamilyBound) {
        self.xMin = xMin; self.xMax = xMax; self.zMin = zMin; self.zMax = zMax
    }
}

/// A loadable Arcus family. Coordinates: origin at the insertion point, X along the host/width, Y toward the
/// facing (exterior) side, Z up from the insertion elevation. Meters.
public struct FamilyDefinition: Hashable, Codable, Sendable {
    public var name: String
    public var template: FamilyTemplate
    public var parameters: [FamilyParameter]
    public var types: [FamilyTypeDefinition]
    public var referencePlanes: [FamilyReferencePlane]
    public var dimensions: [FamilyDimension]
    public var solids: [FamilySolid]
    public var planLines: [FamilyLine]
    /// Lines for annotation / title block / detail families and elevation symbolic lines.
    public var annotationLines: [FamilyLine]
    public var fills: [FamilyFill]
    public var labels: [FamilyLabel]
    public var opening: FamilyOpening?
    /// Closed profile loop for profile families (used by railings, fascia, gutters).
    public var profileLoop: [FamilyPoint]
    /// For tags: the categories this tag family can tag.
    public var taggedCategories: [Category]
    /// Family format version written with this definition.
    public var formatVersion: Int
    public var description: String
    public var manufacturer: String
    /// Families embedded in this one (nested families and profile families used by sweeps).
    public var nestedFamilies: [FamilyDefinition]
    /// Placed instances of embedded families.
    public var nestedInstances: [NestedFamilyInstance]
    /// A shared family nested in a host is also loaded into the project as its own family when the host is loaded,
    /// so it can be placed, scheduled and edited on its own.
    public var isShared: Bool

    public init(name: String, template: FamilyTemplate) {
        self.name = name; self.template = template; parameters = []; types = []; referencePlanes = []; dimensions = []
        solids = []; planLines = []; annotationLines = []; fills = []; labels = []; opening = nil; profileLoop = []
        taggedCategories = []; formatVersion = FamilyDefinition.currentFormatVersion; description = ""; manufacturer = ""
        nestedFamilies = []; nestedInstances = []; isShared = false
    }
    /// 2 adds sweeps, blends, revolves, nested families, EQ/locked dimensions and per-view visibility.
    public static let currentFormatVersion = 2

    public func parameter(named n: String) -> FamilyParameter? { parameters.first { $0.name == n } }
    public func type(named n: String) -> FamilyTypeDefinition? { types.first { $0.name == n } }
    public func nestedFamily(named n: String) -> FamilyDefinition? { nestedFamilies.first { $0.name == n } }

    /// Oldest family reader that interprets this definition fully: 2 when it uses anything format 1 readers would drop
    /// or misread (non-extrusion solids, nested families, EQ or locked dimensions, per-view visibility), else 1.
    public var minimumReaderVersion: Int {
        let v2 = solids.contains { !$0.profile.isExtrusion || !$0.visibleIn3D || !$0.visibleInFrontBack || !$0.visibleInLeftRight }
            || !nestedFamilies.isEmpty || !nestedInstances.isEmpty || isShared
            || dimensions.contains { $0.isEquality || $0.isLocked }
        return v2 ? 2 : 1
    }

    enum CodingKeys: String, CodingKey {
        case name, template, parameters, types, referencePlanes, dimensions, solids, planLines, annotationLines, fills, labels, opening
        case profileLoop, taggedCategories, formatVersion, description, manufacturer, nestedFamilies, nestedInstances, isShared
    }
    /// Tolerant decoding: format 1 families have no nested content; list fields missing from hand-written files default to empty.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        template = try c.decode(FamilyTemplate.self, forKey: .template)
        parameters = try c.decodeIfPresent([FamilyParameter].self, forKey: .parameters) ?? []
        types = try c.decodeIfPresent([FamilyTypeDefinition].self, forKey: .types) ?? []
        referencePlanes = try c.decodeIfPresent([FamilyReferencePlane].self, forKey: .referencePlanes) ?? []
        dimensions = try c.decodeIfPresent([FamilyDimension].self, forKey: .dimensions) ?? []
        solids = try c.decodeIfPresent([FamilySolid].self, forKey: .solids) ?? []
        planLines = try c.decodeIfPresent([FamilyLine].self, forKey: .planLines) ?? []
        annotationLines = try c.decodeIfPresent([FamilyLine].self, forKey: .annotationLines) ?? []
        fills = try c.decodeIfPresent([FamilyFill].self, forKey: .fills) ?? []
        labels = try c.decodeIfPresent([FamilyLabel].self, forKey: .labels) ?? []
        opening = try c.decodeIfPresent(FamilyOpening.self, forKey: .opening)
        profileLoop = try c.decodeIfPresent([FamilyPoint].self, forKey: .profileLoop) ?? []
        taggedCategories = try c.decodeIfPresent([Category].self, forKey: .taggedCategories) ?? []
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        manufacturer = try c.decodeIfPresent(String.self, forKey: .manufacturer) ?? ""
        nestedFamilies = try c.decodeIfPresent([FamilyDefinition].self, forKey: .nestedFamilies) ?? []
        nestedInstances = try c.decodeIfPresent([NestedFamilyInstance].self, forKey: .nestedInstances) ?? []
        isShared = try c.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
    }
}

// BL-SITE: New Family templates seeded from starters whose Width/Depth/Height framing is only sketched.
extension FamilyDefinition {
    /// Anchors a category template's framing planes so dimensions the author adds can't drift the family off its
    /// insertion point: on X and Y without an origin plane, a fixed centre plane held midway between Left/Right
    /// (Front/Back) by EQ; on Z, a Bottom–Top dimension labeled "Height" when none measures those planes.
    ///
    /// Without these, the solver's closest-to-sketch solution spreads a new labeled dimension's correction over every
    /// unanchored plane on the axis (e.g. labeling a leg plane shifted Left, Right and Top). Idempotent.
    public mutating func addTemplateOriginConstraints() {
        func has(_ n: String) -> Bool { referencePlanes.contains { $0.name == n } }
        let centres: [(FamilyAxis, String, ReferenceStrength, String, String)] = [
            (.x, "Center (Left/Right)", .centerLeftRight, "Left", "Right"), (.y, "Center (Front/Back)", .centerFrontBack, "Front", "Back"),
        ]
        for (axis, name, strength, a, b) in centres where has(a) && has(b) && !has(name)
            && !referencePlanes.contains(where: { $0.axis == axis && $0.definesOrigin }) {
            referencePlanes.append(FamilyReferencePlane(name: name, axis: axis, offset: "0", strength: strength, definesOrigin: true))
            dimensions.append(.equality(a, name, b))
        }
        let measured = dimensions.contains { Set([$0.planeA, $0.planeB]) == ["Bottom", "Top"] }
        if has("Bottom"), has("Top"), !measured, let h = parameter(named: "Height"), h.type == .length, h.formula == nil {
            var d = FamilyDimension(planeA: "Bottom", planeB: "Top", labelParameter: "Height")
            d.direction = 1
            dimensions.append(d)
        }
    }
}

// BL-SITE: labeled dimensions keep the side they were drawn on while flexing.
extension FamilyDimension {
    /// Records `direction` from solved plane positions (the editor's current evaluation) when a label is applied or the
    /// measured planes change; `before` is the dimension prior to the edit (nil for a new dimension).
    public mutating func fixLabelDirection(_ planes: [String: Double], after before: FamilyDimension? = nil) {
        guard labelParameter != nil, !isEquality else { return }
        let changed = before.map { $0.labelParameter == nil || $0.planeA != planeA || $0.planeB != planeB } ?? true
        guard direction == nil || changed, let a = planes[planeA], let b = planes[planeB] else { return }
        direction = b < a ? -1 : 1
    }
}
