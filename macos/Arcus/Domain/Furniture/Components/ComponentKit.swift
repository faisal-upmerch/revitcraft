import Foundation
import ArcusGeometry

// COMP: the Furniture Component Library kit. Every built-in component (handles, hinges, slides, legs, LED profiles…)
// is a `ComponentDefinition`: a parametric loadable family in the Furniture Hardware category (Revit-style: a family
// with types, type and instance parameters, material slots) plus the library data the Components panel, placement,
// machining, compatibility checks and schedules read. Definitions are plain data; nothing enters a document until a
// component is placed or loaded (Load Family), and then only that family.
//
// Writing a component (category agents fill ComponentLibrary+A/B/C/D.swift only):
//
//     static func barHandle() -> ComponentDefinition {
//         var b = ComponentBuilder("Bar Handle", .handles, "Bar Handles", "Round bar on two posts.")
//         b.tags("handle", "pull", "bar"); b.aliases("bar pull", "rail handle")
//         b.length("Length", ComponentKit.mm(160)); b.length("Hole Spacing", ComponentKit.mm(128))
//         b.length("Diameter", ComponentKit.mm(12)); b.length("Projection", ComponentKit.mm(34))
//         b.material("Finish Material", .satinNickel)
//         b.host([.door, .drawerFront, .flap], faces: [.front], align: .center)
//         b.drill("Handle hole", x: "-Hole Spacing / 2", y: "0 m", diameter: CX.mm(5), depth: "Host Thickness", through: true)
//         b.drill("Handle hole", x: "Hole Spacing / 2", y: "0 m", diameter: CX.mm(5), depth: "Host Thickness", through: true)
//         b.cylinder("Bar", axis: .x, center: ("0 m", "Projection - Diameter / 2"), radius: "Diameter / 2", from: "-Length / 2", to: "Length / 2")
//         b.symbol(.top, [.coarse], .line(("-Length / 2", "0 m"), ("Length / 2", "0 m")))
//         b.type("Bar Handle - 128 mm CC", ["Length": ComponentKit.mm(164), "Hole Spacing": ComponentKit.mm(128)], cost: 5.25, model: "BH-128")
//         return b.build()
//     }
//
// Geometry frame (`ComponentFrame.face`, the default, like a Revit face-based family): the origin is the mounting
// point on the host face, family X runs along the face (left to right as you look at it), family Y up the face, and
// family Z out of the face, away from the host material. Plan-placed items (legs, bases, casters, glides) use
// `ComponentFrame.plan`: X/Y in plan, Z up, origin at the mounting point (items under a part hang below it, at negative
// Z). Expressions are family formulas in meters ("Length / 2 + 0.005 m"); CX.mm(5) / CX.inch(1.5) write constants.
// Every solid helper takes a `FamilySketchPlane` where the form has one (XY → normal Z, XZ → normal Y, YZ → normal X).
//
// Keep the API additive: new fields get defaults so existing definitions keep compiling.

// MARK: Categories

/// The owner's 20 component categories (01–20), in browser order.
public enum ComponentCategory: Int, CaseIterable, Codable, Sendable, Hashable, Identifiable, Comparable {
    case handles = 1, locks, hinges, drawers, slidingDoors, connectors, legs, shelving, wardrobe, kitchen
    case tables, beds, sofas, chairs, mobility, lighting, glass, edges, motion, decorative

    public var id: Int { rawValue }
    /// "01" … "20".
    public var code: String { String(format: "%02d", rawValue) }

    public var title: String {
        switch self {
        case .handles: "Handles, Knobs & Pulls"
        case .locks: "Locks & Security"
        case .hinges: "Hinges & Door Mechanisms"
        case .drawers: "Drawer Systems"
        case .slidingDoors: "Sliding Door Systems"
        case .connectors: "Connectors & Fasteners"
        case .legs: "Legs, Feet & Bases"
        case .shelving: "Shelving Hardware"
        case .wardrobe: "Wardrobe & Closet"
        case .kitchen: "Kitchen Cabinet Accessories"
        case .tables: "Table & Desk Hardware"
        case .beds: "Bed & Bedroom Hardware"
        case .sofas: "Sofa & Upholstery Hardware"
        case .chairs: "Chair Hardware"
        case .mobility: "Wheels, Casters & Mobility"
        case .lighting: "Lighting & Electrical"
        case .glass: "Glass, Mirrors & Panels"
        case .edges: "Edge Treatments & Profiles"
        case .motion: "Motion & Mechanical"
        case .decorative: "Decorative & Finishing"
        }
    }

    /// SF Symbol for the browser's category list.
    public var symbol: String {
        switch self {
        case .handles: "hand.point.up.left"
        case .locks: "lock"
        case .hinges: "door.left.hand.open"
        case .drawers: "archivebox"
        case .slidingDoors: "rectangle.split.2x1"
        case .connectors: "screwdriver"
        case .legs: "chair.lounge"
        case .shelving: "books.vertical"
        case .wardrobe: "tshirt"
        case .kitchen: "fork.knife"
        case .tables: "table.furniture"
        case .beds: "bed.double"
        case .sofas: "sofa"
        case .chairs: "chair"
        case .mobility: "circle.circle"
        case .lighting: "lightbulb"
        case .glass: "square.on.square.dashed"
        case .edges: "square.dashed"
        case .motion: "gearshape.2"
        case .decorative: "sparkles"
        }
    }

    public static func < (a: ComponentCategory, b: ComponentCategory) -> Bool { a.rawValue < b.rawValue }
}

// MARK: Parameters

/// How the Properties palette groups a component's parameters (the owner's order). Stored in the family as the
/// nearest `ParameterGroup`.
public enum ComponentParamGroup: String, CaseIterable, Codable, Sendable, Hashable {
    case identity = "Identity", dimensions = "Dimensions", placement = "Placement", materials = "Materials"
    case constraints = "Constraints", manufacturing = "Manufacturing", data = "Data"

    public var familyGroup: ParameterGroup {
        switch self {
        case .identity: .identity
        case .dimensions: .dimensions
        case .placement: .constraints
        case .materials: .materials
        case .constraints: .constraints
        case .manufacturing: .construction
        case .data: .other
        }
    }
}

/// One family parameter of a component, with its default (the type value for type parameters; the default instance
/// value for instance parameters, which also goes in every type).
public struct ComponentParameter: Hashable, Sendable, Codable {
    public var name: String
    public var type: ParamType
    public var isInstance: Bool
    public var group: ComponentParamGroup
    public var defaultValue: ParamValue?
    public var formula: String?
    /// Display unit for plain numbers ("lb", "W", "V", "N", "mm stroke"…); nil for lengths and angles.
    public var unit: String?
    /// Allowed range (meters for lengths), for Properties validation and compatibility checks.
    public var minimum: Double?
    public var maximum: Double?

    public init(name: String, type: ParamType, isInstance: Bool = false, group: ComponentParamGroup = .dimensions,
                defaultValue: ParamValue? = nil, formula: String? = nil, unit: String? = nil, minimum: Double? = nil, maximum: Double? = nil) {
        self.name = name; self.type = type; self.isInstance = isInstance; self.group = group; self.defaultValue = defaultValue
        self.formula = formula; self.unit = unit; self.minimum = minimum; self.maximum = maximum
    }
}

/// A material slot (a material parameter) and its default finish.
public struct ComponentMaterialSlot: Hashable, Sendable, Codable {
    /// The material parameter's name ("Finish Material", "Glass Material").
    public var name: String
    public var finish: ComponentFinish
    public init(name: String, finish: ComponentFinish) { self.name = name; self.finish = finish }
}

/// A default material: found in the document by name, else created (Furniture template names first).
public struct ComponentFinish: Hashable, Sendable, Codable {
    public var name: String
    public var materialClass: MaterialClass
    public var color: RGBColor
    public var transparency: Double
    public init(_ name: String, _ materialClass: MaterialClass, _ color: RGBColor, transparency: Double = 0) {
        self.name = name; self.materialClass = materialClass; self.color = color; self.transparency = transparency
    }
    public var data: MaterialData { MaterialData(materialClass: materialClass, color: color, transparency: transparency, description: "Component library default") }

    public static let steel = ComponentFinish("Steel", .metal, RGBColor(hex: 0x9EA3A8))
    public static let stainless = ComponentFinish("Stainless Steel", .metal, RGBColor(hex: 0xC2C6CA))
    public static let chrome = ComponentFinish("Chrome", .metal, RGBColor(hex: 0xD4D8DC))
    public static let satinNickel = ComponentFinish("Satin Nickel", .metal, RGBColor(hex: 0xB4B2AC))
    public static let matteBlack = ComponentFinish("Matte Black Metal", .metal, RGBColor(hex: 0x2B2C2E))
    public static let brass = ComponentFinish("Brass", .metal, RGBColor(hex: 0xB89A5A))
    public static let bronze = ComponentFinish("Oil-Rubbed Bronze", .metal, RGBColor(hex: 0x5A4636))
    public static let aluminum = ComponentFinish("Aluminum", .metal, RGBColor(hex: 0xB9BEC3))
    public static let zinc = ComponentFinish("Zinc", .metal, RGBColor(hex: 0x9CA1A6))
    public static let whitePlastic = ComponentFinish("Plastic - White", .plastic, RGBColor(hex: 0xEEEEEC))
    public static let blackPlastic = ComponentFinish("Plastic - Black", .plastic, RGBColor(hex: 0x2A2B2D))
    public static let greyPlastic = ComponentFinish("Plastic - Grey", .plastic, RGBColor(hex: 0x8C8F93))
    public static let nylon = ComponentFinish("Nylon", .plastic, RGBColor(hex: 0xE6E1D3))
    public static let rubber = ComponentFinish("Rubber - Black", .plastic, RGBColor(hex: 0x222222))
    public static let felt = ComponentFinish("Felt - Grey", .generic, RGBColor(hex: 0x8A8A88))
    public static let oak = ComponentFinish("Solid Oak", .wood, RGBColor(hex: 0xB88A5A))
    public static let walnut = ComponentFinish("Solid Walnut", .wood, RGBColor(hex: 0x6B4A32))
    public static let maple = ComponentFinish("Solid Maple", .wood, RGBColor(hex: 0xD9BE92))
    public static let beech = ComponentFinish("Beech", .wood, RGBColor(hex: 0xD4AE84))
    public static let glass = ComponentFinish("Glass", .glass, RGBColor(hex: 0x9FC4D6), transparency: 0.7)
    public static let mirror = ComponentFinish("Mirror", .glass, RGBColor(hex: 0xC9D6DD), transparency: 0.1)
    public static let crystal = ComponentFinish("Crystal", .glass, RGBColor(hex: 0xDCEAF0), transparency: 0.5)
    public static let leather = ComponentFinish("Leather - Tan", .generic, RGBColor(hex: 0x8C5A36))
    public static let fabric = ComponentFinish("Fabric - Grey", .generic, RGBColor(hex: 0x8E8A84))
    public static let foam = ComponentFinish("Foam", .generic, RGBColor(hex: 0xE8DFC8))
    public static let diffuser = ComponentFinish("LED Diffuser - Opal", .plastic, RGBColor(hex: 0xFBF8EE), transparency: 0.15)
    public static let ledEmitter = ComponentFinish("LED - Warm White", .generic, RGBColor(hex: 0xFFE9B8))
    public static let cane = ComponentFinish("Cane", .wood, RGBColor(hex: 0xD2B078))
    public static let rattan = ComponentFinish("Rattan", .wood, RGBColor(hex: 0xB78E55))
}

// MARK: Types

/// One standard type (size) of a component, with cost and catalogue data. Names use the trade's units: metric trade
/// names where the trade uses mm ("Drawer Slide - 450 mm", "Bar Pull - 128 mm CC"), else Imperial.
public struct ComponentType: Hashable, Sendable, Codable {
    public var name: String
    /// Parameter values by name (lengths in meters).
    public var values: [String: ParamValue]
    /// Unit cost, USD (editable per document in Edit Type ▸ Identity Data).
    public var cost: Double
    public var manufacturer: String
    public var model: String
    public var sku: String
    public var description: String
    public var isDefault: Bool
    public init(name: String, values: [String: ParamValue], cost: Double, manufacturer: String = "Generic", model: String, sku: String,
                description: String, isDefault: Bool = false) {
        self.name = name; self.values = values; self.cost = cost; self.manufacturer = manufacturer; self.model = model
        self.sku = sku; self.description = description; self.isDefault = isDefault
    }
}

/// A saved setting of a component: a type plus instance values ("Handle 3\" from top"). Built-in presets ship with
/// definitions; users save their own from the Components panel.
public struct ComponentPreset: Hashable, Sendable, Codable, Identifiable {
    public var id: String { "\(definitionID)/\(name)" }
    public var name: String
    public var definitionID: String
    public var typeName: String
    public var values: [String: ParamValue]
    public var alignment: ComponentAlignment?
    public init(name: String, definitionID: String, typeName: String, values: [String: ParamValue] = [:], alignment: ComponentAlignment? = nil) {
        self.name = name; self.definitionID = definitionID; self.typeName = typeName; self.values = values; self.alignment = alignment
    }
}

// MARK: Frames, hosts and placement

/// How a component's family coordinates relate to what it's mounted on.
public enum ComponentFrame: String, Codable, Sendable, Hashable {
    /// Face-based (default): origin on the host face, X along it, Y up it, Z out of it.
    case face
    /// Plan: X/Y in plan, Z up; placed on a level, under a part (hanging below, negative Z) or on top of one.
    case plan
    /// FM5 handles and pulls: X along the front, Z up, -Y out of the front (Yes/No Vertical, On Lid).
    case legacyFront
    /// FM5 hinges: X into the opening from the hinge edge, Z along the edge, Y behind the front (Top/Bottom/Back Edge).
    case legacyHinge
    /// FM5 slide pairs: origin at the opening's bottom-left-front corner, X across, Y into the depth, Z up.
    case legacyOpening
}

/// What a component can be mounted on.
public enum ComponentHostKind: String, CaseIterable, Codable, Sendable, Hashable {
    case door = "Door", drawerFront = "Drawer Front", flap = "Flap", lid = "Lid"
    case sidePanel = "Side Panel", divider = "Divider", back = "Back", top = "Top", bottom = "Bottom", shelf = "Shelf"
    case rail = "Rail", leg = "Leg", plinth = "Plinth", form = "Form"
    /// Inside an enclosed bay (slides, rods, organizers, pull-outs): placed between its sides.
    case bay = "Bay"
    /// Glass panels and glass fronts.
    case glass = "Glass"
    /// The floor (Ref. Level) or a project level.
    case floor = "Floor"
    /// Project walls (Architectural projects).
    case wall = "Wall"
    /// Any furniture part.
    case anyPart = "Any Part"

    /// Fronts (doors, drawer fronts, flaps, lids).
    public static let fronts: [ComponentHostKind] = [.door, .drawerFront, .flap, .lid]
    /// Carcass panels.
    public static let carcass: [ComponentHostKind] = [.sidePanel, .divider, .back, .top, .bottom, .shelf]
}

/// A face of the host, as you look at the piece from the front.
public enum ComponentFace: String, CaseIterable, Codable, Sendable, Hashable {
    /// The face toward the viewer (a front's outside face, a panel's front edge face for edge items).
    case front = "Front", back = "Back", left = "Left", right = "Right", top = "Top", bottom = "Bottom"
    /// The face toward the inside of the piece (a door's back, a side's inside face).
    case inside = "Inside"
    /// The face away from the inside (a side's outside face).
    case outside = "Outside"
    /// Narrow edges of a panel or front.
    case topEdge = "Top Edge", bottomEdge = "Bottom Edge", leftEdge = "Left Edge", rightEdge = "Right Edge", frontEdge = "Front Edge"
    /// Any face the pointer is on.
    case any = "Any"
}

/// Where on the host face the component sits by default (Revit-like justification).
public enum ComponentAlignment: String, CaseIterable, Codable, Sendable, Hashable {
    case center = "Center", left = "Left", right = "Right", top = "Top", bottom = "Bottom"
    case topLeft = "Top Left", topRight = "Top Right", bottomLeft = "Bottom Left", bottomRight = "Bottom Right"
    /// Toward the opening side / hinge side of a front (handles go away from the hinges).
    case inside = "Inside", outside = "Outside"
    /// Along the whole face (rods, LED strips, tracks, edge profiles): length follows the host.
    case full = "Full Length"
}

/// A point components snap to, in the mount frame on the face (x, y expressions).
public struct ComponentSnapPoint: Hashable, Sendable, Codable {
    public var name: String
    public var x: String
    public var y: String
    public init(_ name: String, x: String, y: String) { self.name = name; self.x = x; self.y = y }
}

/// How many instances go on one host edge (hinges): by the edge length, with an inset from the ends. Users can change
/// the thresholds per document (Manage ▸ Hardware Rules).
public struct ComponentCountRule: Hashable, Sendable, Codable {
    /// (maximum edge length in meters, count) in increasing order; longer edges use `maximumCount`.
    public var steps: [ComponentCountStep]
    public var maximumCount: Int
    /// Distance from each end of the edge to the first and last instance (meters).
    public var inset: Double
    public init(steps: [ComponentCountStep], maximumCount: Int, inset: Double) { self.steps = steps; self.maximumCount = maximumCount; self.inset = inset }

    public func count(forEdge length: Double) -> Int {
        for s in steps where length <= s.upTo + 1e-6 { return s.count }
        return maximumCount
    }

    /// Hinges: 2 up to 40", 3 up to 60", 4 up to 80", then 5; 3" from the ends.
    public static let hinges = ComponentCountRule(steps: [.init(upTo: 40 * 0.0254, count: 2), .init(upTo: 60 * 0.0254, count: 3), .init(upTo: 80 * 0.0254, count: 4)],
                                                  maximumCount: 5, inset: 3 * 0.0254)
}

public struct ComponentCountStep: Hashable, Sendable, Codable {
    public var upTo: Double
    public var count: Int
    public init(upTo: Double, count: Int) { self.upTo = upTo; self.count = count }
}

/// Where and how a component goes on a host.
public struct ComponentPlacementRule: Hashable, Sendable, Codable {
    public var hosts: [ComponentHostKind]
    public var faces: [ComponentFace]
    public var alignment: ComponentAlignment
    /// Alignments offered in the Options Bar and Properties (the default first).
    public var alignments: [ComponentAlignment]
    /// Default distance from the aligned edge(s) along the face (meters): x from the left/right edge, y from top/bottom.
    public var offsetX: Double
    public var offsetY: Double
    /// Distance out of the face (meters), e.g. a standoff.
    public var offsetZ: Double
    /// Turned 90° on the face (vertical handles on doors): true when it runs up the face by default.
    public var vertical: Bool
    /// Several per edge (hinges), with a count rule.
    public var count: ComponentCountRule?
    /// Placed as a mirrored pair on opposite faces (drawer slides on both sides of a bay).
    public var mirroredPair: Bool
    public var snapPoints: [ComponentSnapPoint]
    public init(hosts: [ComponentHostKind], faces: [ComponentFace], alignment: ComponentAlignment = .center, alignments: [ComponentAlignment] = [],
                offsetX: Double = 0, offsetY: Double = 0, offsetZ: Double = 0, vertical: Bool = false, count: ComponentCountRule? = nil,
                mirroredPair: Bool = false, snapPoints: [ComponentSnapPoint] = []) {
        self.hosts = hosts; self.faces = faces; self.alignment = alignment
        self.alignments = alignments.isEmpty ? [alignment] : (alignments.contains(alignment) ? alignments : [alignment] + alignments)
        self.offsetX = offsetX; self.offsetY = offsetY; self.offsetZ = offsetZ; self.vertical = vertical; self.count = count
        self.mirroredPair = mirroredPair; self.snapPoints = snapPoints
    }

    /// Free placement on a level (no host).
    public static let free = ComponentPlacementRule(hosts: [.floor], faces: [.top])
}

// MARK: Mounting and machining

/// What a mounting operation machines.
public enum ComponentMountTarget: String, Codable, Sendable, Hashable {
    /// The host part the component is placed on.
    case host
    /// The part across the gap (a hinge plate's carcass side, a slide's side panel, a lock's strike).
    case counterpart
}

/// One machining operation from a component's mounting data, in the mount frame (x, y on the face; depth into the
/// host along -Z). Expressions see the component's parameters plus "Host Thickness".
public enum ComponentMountOp: Hashable, Sendable, Codable {
    case drill(label: String, x: String, y: String, diameter: String, depth: String, through: Bool, target: ComponentMountTarget)
    /// A rectangular pocket or cutout (electronics, flush pulls, lock bodies), centred at (x, y).
    case pocket(label: String, x: String, y: String, width: String, height: String, depth: String, through: Bool, target: ComponentMountTarget)
    /// A groove or channel (cable channels, LED recess, track groove) from (x0, y0) to (x1, y1).
    case groove(label: String, x0: String, y0: String, x1: String, y1: String, width: String, depth: String, target: ComponentMountTarget)
    /// A hole drilled into the host's edge (cam bolts, edge boring), along +Y of the mount frame from (x, 0).
    case edgeDrill(label: String, x: String, z: String, diameter: String, depth: String, target: ComponentMountTarget)
}

/// Space a component needs, for collision and compatibility checks (meters, expressions).
public enum ComponentClearance: Hashable, Sendable, Codable {
    /// A box in the mount frame the component sweeps or needs free (handles' finger space, a flap stay's swing).
    case box(name: String, x0: String, x1: String, y0: String, y1: String, z0: String, z1: String)
    /// Minimum gap behind (rear), beside (side), above (top) or below (bottom) inside the bay.
    case rear(String), side(String), top(String), bottom(String)
}

/// A compatibility rule, checked live while placing and in Check Parts. Expressions see the component's parameters.
public enum ComponentRequirement: Hashable, Sendable, Codable {
    /// Host part (or front) thickness range.
    case hostThickness(min: String?, max: String?)
    /// Host face width/height range (along the mount frame's X and Y).
    case hostWidth(min: String?, max: String?)
    case hostHeight(min: String?, max: String?)
    /// The bay or carcass depth must take this length (slides: "Slide Length + Rear Clearance").
    case fitsDepth(String)
    /// The host face must be at least this wide/tall (handles: "Length + 1 in").
    case fitsWidth(String)
    case fitsHeight(String)
    /// The host's estimated weight (lb) per instance must not exceed this expression (hinges' door weight).
    case maxHostWeight(String)
    /// The front's overlay must be one of these (Full Overlay, Half Overlay, Inset).
    case overlay([String])
    /// A rule the checker can't evaluate itself: shown as a note.
    case note(String)
}

/// Electronics data (geometry and data only: no behaviour).
public struct ComponentElectrical: Hashable, Sendable, Codable {
    /// Parameter holding watts ("Power"); per foot when `perFoot`.
    public var powerParameter: String
    public var voltageParameter: String
    public var perFoot: Bool
    /// "AC 120 V", "DC 12 V", "DC 24 V", "USB 5 V".
    public var supply: String
    public var cable: String
    public var connector: String
    public init(powerParameter: String = "Power", voltageParameter: String = "Voltage", perFoot: Bool = false, supply: String, cable: String, connector: String = "") {
        self.powerParameter = powerParameter; self.voltageParameter = voltageParameter; self.perFoot = perFoot
        self.supply = supply; self.cable = cable; self.connector = connector
    }
}

/// Roles that tie a component into other Furniture tools.
public enum ComponentRole: String, Codable, Sendable, Hashable, CaseIterable {
    /// Offered in the Leg tool's Type Selector.
    case legType
    /// An edge banding type for parts' Edge Banding.
    case edgeBanding
    /// A profile for Edge Profile / Groove (uses `ComponentDefinition.profile`).
    case edgeProfile
    /// Counts in the power summary.
    case electrical
    /// A multi-part module (pull-out pantry, drawer stack) inserted as an assembly.
    case module
}

// MARK: Symbols

/// Which 2D view a symbol is drawn for, in the mount frame: `face` looks at the host face (x, y), `top` looks down onto
/// the X–Z plane from +Y (x, z), `side` looks at the Y–Z plane from +X (z, y). Plans and elevations show the symbols
/// whose plane faces them.
public enum ComponentSymbolView: String, Codable, Sendable, Hashable { case face, top, side }

/// A 2D symbol shape in the symbol view's (u, v) coordinates (expressions).
public enum ComponentSymbolShape: Hashable, Sendable, Codable {
    case line(FamilyPoint, FamilyPoint)
    case polyline([FamilyPoint], closed: Bool)
    case rectangle(FamilyPoint, FamilyPoint)
    case circle(center: FamilyPoint, radius: String)
    case arc(center: FamilyPoint, radius: String, startDegrees: String, sweepDegrees: String)

    public static func line(_ a: (String, String), _ b: (String, String)) -> ComponentSymbolShape { .line(FamilyPoint(a.0, a.1), FamilyPoint(b.0, b.1)) }
    public static func rect(_ a: (String, String), _ b: (String, String)) -> ComponentSymbolShape { .rectangle(FamilyPoint(a.0, a.1), FamilyPoint(b.0, b.1)) }
    public static func circle(_ c: (String, String), _ r: String) -> ComponentSymbolShape { .circle(center: FamilyPoint(c.0, c.1), radius: r) }
}

public struct ComponentSymbol: Hashable, Sendable, Codable {
    public var view: ComponentSymbolView
    public var levels: Set<DetailLevel>
    public var shapes: [ComponentSymbolShape]
    /// Dashed (hidden or swing) lines.
    public var dashed: Bool
    public init(view: ComponentSymbolView, levels: Set<DetailLevel>, shapes: [ComponentSymbolShape], dashed: Bool = false) {
        self.view = view; self.levels = levels; self.shapes = shapes; self.dashed = dashed
    }
}

// MARK: Definition

/// A component of the Furniture Component Library: a family with types plus its library data.
public struct ComponentDefinition: Hashable, Sendable, Identifiable, Codable {
    /// Stable id ("comp.01.bar-handle"); placed instances and loaded families keep it.
    public var id: String
    /// Bumped when the definition changes; documents with an older version are offered an upgrade.
    public var version: Int
    public var name: String { family.name }
    public var category: ComponentCategory
    public var subcategory: String
    public var description: String { family.description }
    public var tags: [String]
    /// Other names people search for (synonyms, trade names, sizes in mm and inches).
    public var aliases: [String]
    public var frame: ComponentFrame
    /// The family (parameters, solids, symbols, types). Template: Furniture Hardware.
    public var family: FamilyDefinition
    public var parameters: [ComponentParameter]
    public var types: [ComponentType]
    public var materials: [ComponentMaterialSlot]
    public var placement: ComponentPlacementRule
    public var mounting: [ComponentMountOp]
    public var clearances: [ComponentClearance]
    public var requirements: [ComponentRequirement]
    public var symbols: [ComponentSymbol]
    public var electrical: ComponentElectrical?
    public var roles: Set<ComponentRole>
    /// The FM5 hardware kind when the component plays that role on fronts (hinge, slide, handle…).
    public var hardwareKind: HardwareKind?
    /// Cross-section (x, y) for edge profiles, edge banding and extrusions with profiles.
    public var profile: [FamilyPoint]
    public var presets: [ComponentPreset]
    /// The definition this one is a variant of (a user's customised copy keeps its original's id here).
    public var variantOf: String?
    /// True for the user's own components (Save Selection as Component, duplicates); built-ins are read-only.
    public var isUserComponent: Bool
    /// Old type name → new type name (an upgraded FM5 family that renamed its types). The registry drops the old
    /// types, and documents that use them are migrated: instances keep their type, renamed.
    public var renamedTypes: [String: String] = [:]

    public var defaultType: ComponentType? { types.first(where: \.isDefault) ?? types.first }
    public func type(named n: String) -> ComponentType? { types.first { $0.name == n } }
    public func parameter(named n: String) -> ComponentParameter? { parameters.first { $0.name == n } }
    public var manufacturer: String { family.manufacturer }

    public init(id: String, version: Int = 1, category: ComponentCategory, subcategory: String, tags: [String] = [], aliases: [String] = [],
                frame: ComponentFrame = .face, family: FamilyDefinition, parameters: [ComponentParameter] = [], types: [ComponentType] = [],
                materials: [ComponentMaterialSlot] = [], placement: ComponentPlacementRule = .free, mounting: [ComponentMountOp] = [],
                clearances: [ComponentClearance] = [], requirements: [ComponentRequirement] = [], symbols: [ComponentSymbol] = [],
                electrical: ComponentElectrical? = nil, roles: Set<ComponentRole> = [], hardwareKind: HardwareKind? = nil,
                profile: [FamilyPoint] = [], presets: [ComponentPreset] = [], variantOf: String? = nil, isUserComponent: Bool = false) {
        self.id = id; self.version = version; self.category = category; self.subcategory = subcategory; self.tags = tags; self.aliases = aliases
        self.frame = frame; self.family = family; self.parameters = parameters; self.types = types; self.materials = materials
        self.placement = placement; self.mounting = mounting; self.clearances = clearances; self.requirements = requirements
        self.symbols = symbols; self.electrical = electrical; self.roles = roles; self.hardwareKind = hardwareKind; self.profile = profile
        self.presets = presets; self.variantOf = variantOf; self.isUserComponent = isUserComponent
    }
}

extension ComponentDefinition {
    /// Tolerant decoding (user library files): fields added after a file was written take their defaults.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id), version: try c.decodeIfPresent(Int.self, forKey: .version) ?? 1,
                  category: try c.decode(ComponentCategory.self, forKey: .category), subcategory: try c.decodeIfPresent(String.self, forKey: .subcategory) ?? "",
                  tags: try c.decodeIfPresent([String].self, forKey: .tags) ?? [], aliases: try c.decodeIfPresent([String].self, forKey: .aliases) ?? [],
                  frame: try c.decodeIfPresent(ComponentFrame.self, forKey: .frame) ?? .face, family: try c.decode(FamilyDefinition.self, forKey: .family),
                  parameters: try c.decodeIfPresent([ComponentParameter].self, forKey: .parameters) ?? [],
                  types: try c.decodeIfPresent([ComponentType].self, forKey: .types) ?? [],
                  materials: try c.decodeIfPresent([ComponentMaterialSlot].self, forKey: .materials) ?? [],
                  placement: try c.decodeIfPresent(ComponentPlacementRule.self, forKey: .placement) ?? .free,
                  mounting: try c.decodeIfPresent([ComponentMountOp].self, forKey: .mounting) ?? [],
                  clearances: try c.decodeIfPresent([ComponentClearance].self, forKey: .clearances) ?? [],
                  requirements: try c.decodeIfPresent([ComponentRequirement].self, forKey: .requirements) ?? [],
                  symbols: try c.decodeIfPresent([ComponentSymbol].self, forKey: .symbols) ?? [],
                  electrical: try c.decodeIfPresent(ComponentElectrical.self, forKey: .electrical),
                  roles: try c.decodeIfPresent(Set<ComponentRole>.self, forKey: .roles) ?? [],
                  hardwareKind: try c.decodeIfPresent(HardwareKind.self, forKey: .hardwareKind),
                  profile: try c.decodeIfPresent([FamilyPoint].self, forKey: .profile) ?? [],
                  presets: try c.decodeIfPresent([ComponentPreset].self, forKey: .presets) ?? [],
                  variantOf: try c.decodeIfPresent(String.self, forKey: .variantOf),
                  isUserComponent: try c.decodeIfPresent(Bool.self, forKey: .isUserComponent) ?? false)
        renamedTypes = try c.decodeIfPresent([String: String].self, forKey: .renamedTypes) ?? [:]
    }
}

// MARK: Kit helpers

public enum ComponentKit {
    public static let inchM = 0.0254
    /// Millimeters → meters (type values).
    public static func mm(_ v: Double) -> Double { v / 1000 }
    /// Inches → meters (type values).
    public static func inch(_ v: Double) -> Double { v * inchM }
    /// Feet → meters (type values).
    public static func feet(_ v: Double) -> Double { v * 12 * inchM }

    /// Type parameter on loaded families and their types: the definition id and version.
    public static let definitionParam = ParameterID("comp.definition")
    public static let versionParam = ParameterID("comp.version")
    /// Type identity data: SKU (manufacturer, model, description and cost use the standard type.* ids).
    public static let skuParam = ParameterID("type.sku")

    /// "comp.01.bar-handle" from a category and a name.
    public static func id(_ category: ComponentCategory, _ name: String) -> String {
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            .split(separator: "-").joined(separator: "-")
        return "comp.\(category.code).\(slug)"
    }

    /// Problems with a definition: types missing values, solids that don't build for a type, unknown names. Category
    /// agents call this from their tests for every definition.
    public static func validate(_ d: ComponentDefinition) -> [String] {
        var out: [String] = []
        if d.types.isEmpty { out.append("\(d.name): no types") }
        if d.types.count > 8 { out.append("\(d.name): \(d.types.count) types (1–4 standard sizes expected, slides up to 8)") }
        if Set(d.types.map(\.name)).count != d.types.count { out.append("\(d.name): duplicate type names") }
        if d.family.solids.isEmpty { out.append("\(d.name): no geometry") }
        if d.tags.isEmpty { out.append("\(d.name): no search tags") }
        for t in d.types {
            let ev = FamilyEvaluator.evaluate(d.family, typeName: t.name)
            for e in ev.errors { out.append("\(d.name) / \(t.name): \(e)") }
            if ev.solids.filter({ !$0.isVoid }).isEmpty { out.append("\(d.name) / \(t.name): no solids for this type") }
            if t.cost < 0 { out.append("\(d.name) / \(t.name): negative cost") }
        }
        return out
    }
}

/// Expression constants for geometry: CX.mm(5) → "0.005 m".
public enum CX {
    public static func m(_ v: Double) -> String { "\(LX.num(v)) m" }
    public static func mm(_ v: Double) -> String { m(v / 1000) }
    public static func inch(_ v: Double) -> String { m(v * 0.0254) }
    public static let zero = "0 m"
}

// MARK: Builder

/// Writes a `ComponentDefinition`: metadata, parameters, material slots, hosting, mounting, geometry, symbols, types.
/// All geometry helpers work in the definition's frame (face-based by default, see the file header) and return the
/// solid's id (for voids' `cuts`).
public struct ComponentBuilder {
    public var definition: ComponentDefinition
    /// Detail levels new solids show at (hardware: Medium and Fine; structural items like legs: all).
    public var visibleAt: Set<DetailLevel> = [.medium, .fine]
    /// Yes/No parameter controlling new solids' visibility (nil = always).
    public var visibility: String?
    /// The material slot new solids use (nil = the first slot).
    public var currentMaterial: String?

    public init(_ name: String, _ category: ComponentCategory, _ subcategory: String, _ description: String, id: String? = nil, frame: ComponentFrame = .face) {
        var f = FamilyDefinition(name: name, template: .furnitureHardware)
        f.description = description
        f.manufacturer = "Generic"
        definition = ComponentDefinition(id: id ?? ComponentKit.id(category, name), category: category, subcategory: subcategory, frame: frame, family: f)
        if frame == .plan { visibleAt = [.coarse, .medium, .fine] }
    }

    /// Starts from an existing family (FM5 hardware, a user's family): keeps its parameters, solids and types.
    public init(wrapping family: FamilyDefinition, _ category: ComponentCategory, _ subcategory: String, id: String? = nil, frame: ComponentFrame) {
        definition = ComponentDefinition(id: id ?? ComponentKit.id(category, family.name), category: category, subcategory: subcategory, frame: frame, family: family)
        definition.parameters = family.parameters.map { p in
            ComponentParameter(name: p.name, type: p.type, isInstance: p.isInstance, group: Self.group(p.group, p.type), formula: p.formula)
        }
        definition.types = family.types.map { t in
            ComponentType(name: t.name, values: t.values, cost: 0, model: "", sku: "", description: "")
        }
        for p in family.parameters where p.type == .elementRef(.materials) {
            definition.materials.append(ComponentMaterialSlot(name: p.name, finish: .steel))
        }
    }

    static func group(_ g: ParameterGroup, _ t: ParamType) -> ComponentParamGroup {
        switch g {
        case .identity: .identity
        case .materials: .materials
        case .constraints: .placement
        case .construction: .manufacturing
        case .other: .data
        default: t == .elementRef(.materials) ? .materials : .dimensions
        }
    }

    // MARK: Metadata

    public mutating func tags(_ t: String...) { definition.tags += t }
    public mutating func aliases(_ a: String...) { definition.aliases += a }
    public mutating func version(_ v: Int) { definition.version = v }
    public mutating func hardwareKind(_ k: HardwareKind) { definition.hardwareKind = k }
    public mutating func role(_ r: ComponentRole) { definition.roles.insert(r) }
    public mutating func profile(_ pts: [FamilyPoint]) { definition.profile = pts }
    /// Records renamed types (old name → new name), for upgrades of existing families.
    public mutating func renames(_ map: [String: String]) { definition.renamedTypes.merge(map) { _, b in b } }
    public mutating func preset(_ name: String, type: String, values: [String: ParamValue] = [:], alignment: ComponentAlignment? = nil) {
        definition.presets.append(ComponentPreset(name: name, definitionID: definition.id, typeName: type, values: values, alignment: alignment))
    }

    // MARK: Parameters

    /// Adds a parameter (type parameter unless `instance`); `defaultValue` goes in every type that doesn't set it.
    public mutating func parameter(_ name: String, _ type: ParamType, _ defaultValue: ParamValue?, instance: Bool = false, group: ComponentParamGroup = .dimensions,
                                   formula: String? = nil, unit: String? = nil, min: Double? = nil, max: Double? = nil) {
        guard definition.parameter(named: name) == nil else { return }
        definition.parameters.append(ComponentParameter(name: name, type: type, isInstance: instance, group: group, defaultValue: defaultValue,
                                                        formula: formula, unit: unit, minimum: min, maximum: max))
        definition.family.parameters.append(FamilyParameter(name: name, type: type, isInstance: instance, group: group.familyGroup, formula: formula))
    }
    public mutating func length(_ name: String, _ v: Double, instance: Bool = false, group: ComponentParamGroup = .dimensions, formula: String? = nil, min: Double? = nil, max: Double? = nil) {
        parameter(name, .length, formula == nil ? .double(v) : nil, instance: instance, group: group, formula: formula, min: min, max: max)
    }
    /// Degrees.
    public mutating func angle(_ name: String, _ degrees: Double, instance: Bool = false, group: ComponentParamGroup = .dimensions) {
        parameter(name, .angle, .double(degrees * .pi / 180), instance: instance, group: group)
    }
    public mutating func number(_ name: String, _ v: Double, unit: String? = nil, instance: Bool = false, group: ComponentParamGroup = .data) {
        parameter(name, .number, .double(v), instance: instance, group: group, unit: unit)
    }
    public mutating func integer(_ name: String, _ v: Int, instance: Bool = false, group: ComponentParamGroup = .dimensions) {
        parameter(name, .integer, .int(v), instance: instance, group: group)
    }
    public mutating func flag(_ name: String, _ v: Bool, instance: Bool = true, group: ComponentParamGroup = .constraints, formula: String? = nil) {
        parameter(name, .bool, formula == nil ? .bool(v) : nil, instance: formula == nil ? instance : false, group: group, formula: formula)
    }
    public mutating func text(_ name: String, _ v: String, instance: Bool = false, group: ComponentParamGroup = .data) {
        parameter(name, .text, .text(v), instance: instance, group: group)
    }
    public mutating func choice(_ name: String, _ options: [String], _ v: String, instance: Bool = false, group: ComponentParamGroup = .data) {
        parameter(name, .choice(options), .text(v), instance: instance, group: group)
    }
    /// A material slot (material parameter) with its default finish. The first slot is the solids' default.
    public mutating func material(_ name: String, _ finish: ComponentFinish) {
        guard !definition.materials.contains(where: { $0.name == name }) else { return }
        definition.materials.append(ComponentMaterialSlot(name: name, finish: finish))
        definition.family.parameters.append(FamilyParameter(name: name, type: .elementRef(.materials), group: .materials))
    }
    /// Sets the material slot for the solids added next.
    public mutating func using(_ slot: String?) { currentMaterial = slot }

    /// Electronics data plus its Power (W) and Voltage (V) type parameters.
    public mutating func electrical(watts: Double, volts: Double, perFoot: Bool = false, supply: String, cable: String, connector: String = "") {
        number("Power", watts, unit: perFoot ? "W/ft" : "W", group: .data)
        number("Voltage", volts, unit: "V", group: .data)
        definition.electrical = ComponentElectrical(perFoot: perFoot, supply: supply, cable: cable, connector: connector)
        definition.roles.insert(.electrical)
    }

    // MARK: Types

    /// A standard type. `values` are lengths in meters (use ComponentKit.mm/inch), `flags` Yes/No, `texts` text values,
    /// `numbers` plain numbers; anything left out takes the parameter's default.
    public mutating func type(_ name: String, _ values: [String: Double] = [:], flags: [String: Bool] = [:], texts: [String: String] = [:],
                              numbers: [String: Double] = [:], cost: Double, model: String, sku: String? = nil, description: String? = nil, isDefault: Bool = false) {
        var v: [String: ParamValue] = [:]
        for (k, x) in values { v[k] = .double(x) }
        for (k, x) in numbers { v[k] = .double(x) }
        for (k, b) in flags { v[k] = .bool(b) }
        for (k, s) in texts { v[k] = .text(s) }
        definition.types.append(ComponentType(name: name, values: v, cost: cost, model: model, sku: sku ?? "GEN-\(model)",
                                              description: description ?? "\(definition.name), \(name)", isDefault: isDefault))
    }

    // MARK: Hosting, mounting, rules

    public mutating func host(_ hosts: [ComponentHostKind], faces: [ComponentFace], align: ComponentAlignment = .center, alignments: [ComponentAlignment] = [],
                              offsetX: Double = 0, offsetY: Double = 0, offsetZ: Double = 0, vertical: Bool = false, count: ComponentCountRule? = nil,
                              mirroredPair: Bool = false) {
        let snaps = definition.placement.snapPoints
        definition.placement = ComponentPlacementRule(hosts: hosts, faces: faces, alignment: align, alignments: alignments, offsetX: offsetX, offsetY: offsetY,
                                                      offsetZ: offsetZ, vertical: vertical, count: count, mirroredPair: mirroredPair, snapPoints: snaps)
    }
    public mutating func snap(_ name: String, x: String, y: String) { definition.placement.snapPoints.append(ComponentSnapPoint(name, x: x, y: y)) }

    public mutating func drill(_ label: String, x: String, y: String, diameter: String, depth: String, through: Bool = false, target: ComponentMountTarget = .host) {
        definition.mounting.append(.drill(label: label, x: x, y: y, diameter: diameter, depth: depth, through: through, target: target))
    }
    public mutating func pocket(_ label: String, x: String = CX.zero, y: String = CX.zero, width: String, height: String, depth: String, through: Bool = false,
                                target: ComponentMountTarget = .host) {
        definition.mounting.append(.pocket(label: label, x: x, y: y, width: width, height: height, depth: depth, through: through, target: target))
    }
    public mutating func groove(_ label: String, from: (String, String), to: (String, String), width: String, depth: String, target: ComponentMountTarget = .host) {
        definition.mounting.append(.groove(label: label, x0: from.0, y0: from.1, x1: to.0, y1: to.1, width: width, depth: depth, target: target))
    }
    public mutating func edgeDrill(_ label: String, x: String, z: String, diameter: String, depth: String, target: ComponentMountTarget = .host) {
        definition.mounting.append(.edgeDrill(label: label, x: x, z: z, diameter: diameter, depth: depth, target: target))
    }
    public mutating func clearance(_ c: ComponentClearance) { definition.clearances.append(c) }
    public mutating func requires(_ r: ComponentRequirement) { definition.requirements.append(r) }

    // MARK: Symbols

    public mutating func symbol(_ view: ComponentSymbolView, _ levels: Set<DetailLevel>, dashed: Bool = false, _ shapes: ComponentSymbolShape...) {
        definition.symbols.append(ComponentSymbol(view: view, levels: levels, shapes: shapes, dashed: dashed))
    }

    // MARK: Geometry

    mutating func add(_ s: FamilySolid) -> String {
        var s = s
        s.visibleAt = visibleAt
        s.visibilityParameter = visibility
        if !s.isVoid, s.materialParameter == nil { s.materialParameter = currentMaterial ?? definition.materials.first?.name }
        definition.family.solids.append(s)
        return s.id
    }

    /// A box from ranges on X, Y and Z.
    @discardableResult
    public mutating func box(_ name: String, x: (String, String), y: (String, String), z: (String, String), void: Bool = false) -> String {
        add(FamilySolid(name: name, profile: .rectangle(xMin: .expr(x.0), xMax: .expr(x.1), yMin: .expr(y.0), yMax: .expr(y.1)),
                        zMin: .expr(z.0), zMax: .expr(z.1), isVoid: void))
    }

    /// A cylinder along a family axis: `center` is on the other two axes in (X, Y), (X, Z) or (Y, Z) order.
    @discardableResult
    public mutating func cylinder(_ name: String, axis: FamilyAxis, center: (String, String), radius: String, from: String, to: String, void: Bool = false) -> String {
        let plane = Self.plane(normal: axis)
        var s = FamilySolid(name: name, profile: .circle(center: FamilyPoint(center.0, center.1), radius: radius), zMin: .expr(from), zMax: .expr(to), isVoid: void)
        if plane != .xy { s.workPlane = plane }
        return add(s)
    }

    /// A tube (a cylinder with a bore, the bore cut by a void).
    public mutating func tube(_ name: String, axis: FamilyAxis, center: (String, String), outer: String, inner: String, from: String, to: String) {
        let id = cylinder(name, axis: axis, center: center, radius: outer, from: from, to: to)
        let v = cylinder("\(name) Bore", axis: axis, center: center, radius: inner, from: from, to: to, void: true)
        if let k = definition.family.solids.firstIndex(where: { $0.id == v }) { definition.family.solids[k].cuts = [id] }
    }

    /// A prism: a closed (u, v) profile sketched on `plane`, extruded along its normal from `from` to `to`.
    @discardableResult
    public mutating func extrusion(_ name: String, profile: [FamilyPoint], plane: FamilySketchPlane = .xy, from: String, to: String, void: Bool = false) -> String {
        var s = FamilySolid(name: name, profile: .polygon(profile), zMin: .expr(from), zMax: .expr(to), isVoid: void)
        if plane != .xy { s.workPlane = plane }
        return add(s)
    }

    /// A bar with rounded ends or corners (stadium or rounded rectangle) on `plane`: `width` along u, `height` along v,
    /// centred at `center`, corner radius `radius` (expressions).
    @discardableResult
    public mutating func roundedBar(_ name: String, plane: FamilySketchPlane = .xy, center: (String, String) = (CX.zero, CX.zero), width: String, height: String,
                                    radius: String, from: String, to: String) -> String {
        extrusion(name, profile: ComponentKit.roundedRect(center: center, width: width, height: height, radius: radius), plane: plane, from: from, to: to)
    }

    /// A closed profile carried along an open path, both on `plane`'s sketch coordinates: the path in (u, v) at depth
    /// `at` along the normal, the profile's x to the left of the path direction and its y along the normal.
    @discardableResult
    public mutating func sweep(_ name: String, path: [FamilyPoint], profile: [FamilyPoint], plane: FamilySketchPlane = .xy, at: String = CX.zero) -> String {
        var s = FamilySolid(name: name, profile: .sweep(FamilySweep(path: path, profile: profile)), zMin: .expr(at), zMax: .expr(at))
        if plane != .xy { s.workPlane = plane }
        return add(s)
    }

    /// A closed (r, h) profile turned about the plane's normal axis through `axis` (u, v): on XY about Z (knobs in
    /// the face frame, turned legs in the plan frame), XZ about Y, YZ about X. h is measured from `base` along the axis.
    @discardableResult
    public mutating func revolve(_ name: String, profile: [FamilyPoint], plane: FamilySketchPlane = .xy, axis: (String, String) = (CX.zero, CX.zero),
                                 base: String = CX.zero, startDegrees: String = "0", endDegrees: String = "360") -> String {
        var s = FamilySolid(name: name, profile: .revolve(FamilyRevolve(profile: profile, axis: FamilyPoint(axis.0, axis.1), startDegrees: startDegrees, endDegrees: endDegrees)),
                            zMin: .expr(base), zMax: .expr(base))
        if plane != .xy { s.workPlane = plane }
        return add(s)
    }

    /// A loft from a bottom loop at `from` to a top loop at `to` on `plane`.
    @discardableResult
    public mutating func blend(_ name: String, bottom: [FamilyPoint], top: [FamilyPoint], plane: FamilySketchPlane = .xy, from: String, to: String) -> String {
        var s = FamilySolid(name: name, profile: .blend(FamilyBlend(bottom: bottom, top: top)), zMin: .expr(from), zMax: .expr(to))
        if plane != .xy { s.workPlane = plane }
        return add(s)
    }

    /// A sheet-metal L bracket in the face frame: a leg flat on the face (`width` along X, `legA` up Y) and a leg standing
    /// out of the face (`legB` along Z) at its bottom edge, `thickness` thick.
    public mutating func bracket(_ name: String, width: String, legA: String, legB: String, thickness: String) {
        box("\(name) Face Leg", x: ("-(\(width)) / 2", "(\(width)) / 2"), y: (CX.zero, legA), z: (CX.zero, thickness))
        box("\(name) Out Leg", x: ("-(\(width)) / 2", "(\(width)) / 2"), y: (CX.zero, thickness), z: (CX.zero, legB))
    }

    /// A U-channel track running along X from `from` to `to`: `width` along Y (centred), `height` out of the face (Z),
    /// walls `wall` thick.
    public mutating func track(_ name: String, from: String, to: String, width: String, height: String, wall: String) {
        let w = "(\(width)) / 2", h = height, t = wall
        let pts = [FamilyPoint("-\(w)", CX.zero), FamilyPoint(w, CX.zero), FamilyPoint(w, h), FamilyPoint("\(w) - \(t)", h),
                   FamilyPoint("\(w) - \(t)", t), FamilyPoint("-\(w) + \(t)", t), FamilyPoint("-\(w) + \(t)", h), FamilyPoint("-\(w)", h)]
        extrusion(name, profile: pts, plane: .yz, from: from, to: to)
    }

    /// A profile extruded along X (edge profiles, LED channels, rails): `profile` in (Y, Z).
    @discardableResult
    public mutating func profileAlongX(_ name: String, profile: [FamilyPoint], from: String, to: String) -> String {
        extrusion(name, profile: profile, plane: .yz, from: from, to: to)
    }

    static func plane(normal a: FamilyAxis) -> FamilySketchPlane {
        switch a {
        case .z: .xy
        case .y: .xz
        case .x: .yz
        }
    }

    public func build() -> ComponentDefinition {
        var d = definition
        // Every type carries every parameter's default it doesn't set (instance defaults included, as FM5 does).
        for k in d.types.indices {
            for p in d.parameters where p.formula == nil && d.types[k].values[p.name] == nil {
                if let v = p.defaultValue { d.types[k].values[p.name] = v }
            }
        }
        if !d.types.contains(where: \.isDefault), !d.types.isEmpty { d.types[0].isDefault = true }
        d.family.types = d.types.map { FamilyTypeDefinition(name: $0.name, values: $0.values) }
        d.family.manufacturer = "Generic"
        return d
    }
}

// MARK: Profile helpers

extension ComponentKit {
    /// A rectangle centred at `center` (u, v), `width` × `height`.
    public static func rect(center: (String, String) = (CX.zero, CX.zero), width: String, height: String) -> [FamilyPoint] {
        let (cx, cy) = center, w = "(\(width)) / 2", h = "(\(height)) / 2"
        return [FamilyPoint("\(cx) - \(w)", "\(cy) - \(h)"), FamilyPoint("\(cx) + \(w)", "\(cy) - \(h)"),
                FamilyPoint("\(cx) + \(w)", "\(cy) + \(h)"), FamilyPoint("\(cx) - \(w)", "\(cy) + \(h)")]
    }

    /// A circle polygon (smooth enough for sweep profiles), `segments` sides.
    public static func circle(center: (String, String) = (CX.zero, CX.zero), radius: String, segments: Int = 24) -> [FamilyPoint] {
        (0..<segments).map { k in
            let a = Double(k) / Double(segments) * 2 * .pi
            return FamilyPoint("\(center.0) + (\(radius)) * \(LX.num(cos(a)))", "\(center.1) + (\(radius)) * \(LX.num(sin(a)))")
        }
    }

    /// A rectangle with rounded corners (radius ≤ half the shorter side; equal to it gives a stadium).
    public static func roundedRect(center: (String, String) = (CX.zero, CX.zero), width: String, height: String, radius: String, segments: Int = 6) -> [FamilyPoint] {
        let (cx, cy) = center, w = "(\(width)) / 2", h = "(\(height)) / 2", r = "(\(radius))"
        var out: [FamilyPoint] = []
        // Corner centres, counterclockwise from bottom-right, with the arc's start angle.
        let corners: [(String, String, Double)] = [("\(cx) + \(w) - \(r)", "\(cy) - \(h) + \(r)", -90), ("\(cx) + \(w) - \(r)", "\(cy) + \(h) - \(r)", 0),
                                                   ("\(cx) - \(w) + \(r)", "\(cy) + \(h) - \(r)", 90), ("\(cx) - \(w) + \(r)", "\(cy) - \(h) + \(r)", 180)]
        for (ux, uy, a0) in corners {
            for k in 0...segments {
                let a = (a0 + 90 * Double(k) / Double(segments)) * .pi / 180
                out.append(FamilyPoint("\(ux) + \(r) * \(LX.num(cos(a)))", "\(uy) + \(r) * \(LX.num(sin(a)))"))
            }
        }
        return out
    }

    /// An arc path (open) from `startDegrees` sweeping `sweepDegrees` about `center`, for bow handles and curved rails.
    public static func arcPath(center: (String, String), radius: String, startDegrees: Double, sweepDegrees: Double, segments: Int = 16) -> [FamilyPoint] {
        (0...segments).map { k in
            let a = (startDegrees + sweepDegrees * Double(k) / Double(segments)) * .pi / 180
            return FamilyPoint("\(center.0) + (\(radius)) * \(LX.num(cos(a)))", "\(center.1) + (\(radius)) * \(LX.num(sin(a)))")
        }
    }

    /// Points from (u, v) expression pairs.
    public static func points(_ p: [(String, String)]) -> [FamilyPoint] { p.map { FamilyPoint($0.0, $0.1) } }
}
