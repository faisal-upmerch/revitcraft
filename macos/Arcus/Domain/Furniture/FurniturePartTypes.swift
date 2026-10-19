import Foundation
import ArcusGeometry

// FM4: part types (Type Properties ▸ Edit Type) and the standard types every Furniture document starts with. Types are
// ordinary `TypeData` elements of the part categories, with the values below in `params` (system families, like wall
// and floor types).

/// Leg shapes (Type Properties ▸ Shape).
public enum LegShape: String, Codable, Sendable, CaseIterable {
    case square = "Square", round = "Round", turned = "Turned", hairpin = "Hairpin", sled = "Sled", plinthBlock = "Plinth Block", caster = "Caster"
}

/// Rail cross-sections (Type Properties ▸ Profile).
public enum RailProfile: String, Codable, Sendable, CaseIterable { case rectangle = "Rectangle", round = "Round" }

/// Top edge shapes (Type Properties ▸ Edge Profile of tops).
public enum TopEdge: String, Codable, Sendable, CaseIterable { case square = "Square", roundOver = "Round-Over", chamfer = "Chamfer", bullnose = "Bullnose", ogee = "Ogee" }

public enum FurniturePartTypes {
    // MARK: Type parameters

    public static let thickness = ParameterID("furniture.thickness")
    public static let coreMaterial = ParameterID("furniture.coreMaterial")
    public static let faceMaterial = ParameterID("furniture.faceMaterial")
    public static let edgeMaterial = ParameterID("furniture.edgeMaterial")
    public static let edgeThickness = ParameterID("furniture.edgeThickness")
    /// Default edge banding, as "L1 L2 W1 W2" text.
    public static let banding = ParameterID("furniture.banding")
    public static let grain = ParameterID("furniture.grain")
    /// Tops: overhang past the carcass and the edge shape.
    public static let overhang = ParameterID("furniture.overhang")
    public static let topEdge = ParameterID("furniture.topEdge")
    /// Legs.
    public static let legShape = ParameterID("furniture.legShape")
    public static let width = ParameterID("furniture.width")
    public static let depth = ParameterID("furniture.depth")
    /// Legs: the size at the foot (0 = no taper).
    public static let taper = ParameterID("furniture.taper")
    /// Hairpin and sled legs: rod or tube size.
    public static let rod = ParameterID("furniture.rod")
    /// Rails.
    public static let railProfile = ParameterID("furniture.railProfile")
    /// Edge profiles: the shape, its size (radius, chamfer, groove width) and groove depth.
    public static let profileShape = ParameterID("furniture.profileShape")
    public static let size = ParameterID("furniture.size")
    public static let grooveDepth = ParameterID("furniture.grooveDepth")

    static let inch = 0.0254

    // MARK: Reading a type

    /// A part type's values with defaults.
    public struct Values: Sendable {
        public var td: TypeData?
        public init(_ td: TypeData?) { self.td = td }
        func d(_ id: ParameterID, _ fallback: Double) -> Double { td?.params[id]?.doubleValue ?? fallback }
        func t(_ id: ParameterID) -> String { td?.params[id]?.textValue ?? "" }
        public var thickness: Double { d(FurniturePartTypes.thickness, 0.75 * inch) }
        public var coreMaterial: ElementID? { td?.params[FurniturePartTypes.coreMaterial]?.refValue }
        public var faceMaterial: ElementID? { td?.params[FurniturePartTypes.faceMaterial]?.refValue }
        public var edgeMaterial: ElementID? { td?.params[FurniturePartTypes.edgeMaterial]?.refValue }
        public var edgeThickness: Double { d(FurniturePartTypes.edgeThickness, 0) }
        public var banding: EdgeBanding { EdgeBanding(code: t(FurniturePartTypes.banding)) }
        public var grain: GrainDirection { GrainDirection(rawValue: t(FurniturePartTypes.grain)) ?? .length }
        public var overhang: Double { d(FurniturePartTypes.overhang, 0) }
        public var topEdge: TopEdge { TopEdge(rawValue: t(FurniturePartTypes.topEdge)) ?? .square }
        public var legShape: LegShape { LegShape(rawValue: t(FurniturePartTypes.legShape)) ?? .square }
        public var width: Double { d(FurniturePartTypes.width, 1.5 * inch) }
        public var depth: Double { d(FurniturePartTypes.depth, width) }
        public var taper: Double { d(FurniturePartTypes.taper, 0) }
        public var rod: Double { d(FurniturePartTypes.rod, 0.375 * inch) }
        public var railProfile: RailProfile { RailProfile(rawValue: t(FurniturePartTypes.railProfile)) ?? .rectangle }
        public var profileShape: EdgeProfileShape { EdgeProfileShape(rawValue: t(FurniturePartTypes.profileShape)) ?? .roundOver }
        public var size: Double { d(FurniturePartTypes.size, 0.25 * inch) }
        public var grooveDepth: Double { d(FurniturePartTypes.grooveDepth, 0.25 * inch) }
        /// The material solids show: the core (cut) material; faces are coloured by the face material in 3D.
        public var material: ElementID? { coreMaterial ?? faceMaterial }
    }

    public static func values(of e: Element, _ m: BIMModel) -> Values { Values(m.typeData(of: e)) }

    // MARK: Standard types

    /// A standard type: category, family (the Type Selector's group), name and values. Materials are named.
    public struct Spec: Sendable {
        public var category: Category
        public var family: String
        public var name: String
        public var numbers: [ParameterID: Double]
        public var texts: [ParameterID: String]
        public var materials: [ParameterID: String]
    }

    static func sheet(_ cat: Category, _ family: String, _ name: String, t: Double, core: String, face: String? = nil, edge: String? = "Edge Banding",
                      edgeT: Double = 0.02 * inch, banding: String = "L1", grain: GrainDirection = .length, extra: [ParameterID: Double] = [:],
                      texts: [ParameterID: String] = [:]) -> Spec {
        var mats: [ParameterID: String] = [coreMaterial: core]
        if let face { mats[faceMaterial] = face }
        if let edge { mats[edgeMaterial] = edge }
        var nums: [ParameterID: Double] = [thickness: t * inch, edgeThickness: edge == nil ? 0 : edgeT]
        for (k, v) in extra { nums[k] = v }
        var tx: [ParameterID: String] = [FurniturePartTypes.banding: edge == nil ? "None" : banding, FurniturePartTypes.grain: grain.rawValue]
        for (k, v) in texts { tx[k] = v }
        return Spec(category: cat, family: family, name: name, numbers: nums, texts: tx, materials: mats)
    }

    static func leg(_ name: String, _ shape: LegShape, w: Double, d: Double? = nil, taper: Double = 0, rod: Double = 0.375, material: String) -> Spec {
        Spec(category: .furnitureLegs, family: "Leg", name: name,
             numbers: [width: w * inch, depth: (d ?? w) * inch, FurniturePartTypes.taper: taper * inch, FurniturePartTypes.rod: rod * inch], texts: [legShape: shape.rawValue],
             materials: [coreMaterial: material])
    }

    static func rail(_ name: String, w: Double, h: Double, profile: RailProfile = .rectangle, material: String = "Solid Oak") -> Spec {
        Spec(category: .furnitureRails, family: "Rail", name: name, numbers: [width: w * inch, depth: h * inch],
             texts: [railProfile: profile.rawValue, grain: GrainDirection.length.rawValue], materials: [coreMaterial: material])
    }

    static func edge(_ family: String, _ name: String, _ shape: EdgeProfileShape, size s: Double, depth: Double = 0) -> Spec {
        Spec(category: .furnitureEdgeProfiles, family: family, name: name, numbers: [size: s * inch, FurniturePartTypes.grooveDepth: depth * inch],
             texts: [profileShape: shape.rawValue], materials: [:])
    }

    /// The standard part types (Revit-style names: thickness then material).
    public static let standard: [Spec] = [
        sheet(.furniturePanels, "Panel", "3/4\" Plywood", t: 0.75, core: "Plywood", banding: "L1"),
        sheet(.furniturePanels, "Panel", "3/4\" MDF", t: 0.75, core: "MDF", edge: nil, grain: .none),
        sheet(.furniturePanels, "Panel", "5/8\" Melamine", t: 0.625, core: "Melamine", edge: "PVC Edge Banding", edgeT: 0.04, banding: "L1", grain: .none),
        sheet(.furniturePanels, "Panel", "3/4\" Melamine", t: 0.75, core: "Melamine", edge: "PVC Edge Banding", edgeT: 0.04, banding: "L1", grain: .none),
        sheet(.furniturePanels, "Panel", "1/2\" Plywood", t: 0.5, core: "Plywood", banding: "L1"),
        sheet(.furniturePanels, "Panel", "1/4\" Back Panel (Hardboard)", t: 0.25, core: "Hardboard", edge: nil, grain: .none),
        sheet(.furniturePanels, "Panel", "1/4\" Plywood", t: 0.25, core: "Plywood", edge: nil),
        sheet(.furniturePanels, "Panel", "3/4\" Solid Oak", t: 0.75, core: "Solid Oak", edge: nil),
        sheet(.furniturePanels, "Panel", "3/4\" Solid Walnut", t: 0.75, core: "Solid Walnut", edge: nil),
        sheet(.furniturePanels, "Panel", "3/4\" Oak Veneer Plywood", t: 0.75, core: "Plywood", face: "Veneer", banding: "L1"),
        sheet(.furnitureShelves, "Shelf", "3/4\" Plywood Shelf", t: 0.75, core: "Plywood", banding: "L1"),
        sheet(.furnitureShelves, "Shelf", "3/4\" Melamine Shelf", t: 0.75, core: "Melamine", edge: "PVC Edge Banding", edgeT: 0.04, banding: "L1", grain: .none),
        sheet(.furnitureShelves, "Shelf", "1\" Solid Oak Shelf", t: 1, core: "Solid Oak", edge: nil),
        sheet(.furnitureShelves, "Shelf", "1/4\" Glass Shelf", t: 0.25, core: "Glass", edge: nil, grain: .none),
        sheet(.furnitureShelves, "Top", "3/4\" Plywood Top", t: 0.75, core: "Plywood", banding: "L1 L2 W1 W2", texts: [topEdge: TopEdge.square.rawValue]),
        sheet(.furnitureShelves, "Top", "1\" Solid Oak Top", t: 1, core: "Solid Oak", edge: nil, extra: [overhang: 0.75 * inch], texts: [topEdge: TopEdge.roundOver.rawValue]),
        sheet(.furnitureShelves, "Top", "1 1/2\" Butcher Block", t: 1.5, core: "Solid Maple", edge: nil, extra: [overhang: 1 * inch], texts: [topEdge: TopEdge.roundOver.rawValue]),
        sheet(.furnitureShelves, "Top", "1 1/4\" Solid Walnut Top", t: 1.25, core: "Solid Walnut", edge: nil, extra: [overhang: 1 * inch], texts: [topEdge: TopEdge.chamfer.rawValue]),
        sheet(.furnitureShelves, "Top", "3/4\" Laminate Top", t: 0.75, core: "Particleboard", face: "Laminate", edge: "PVC Edge Banding", edgeT: 0.04,
              banding: "L1 L2 W1 W2", grain: .none, extra: [overhang: 0.5 * inch], texts: [topEdge: TopEdge.square.rawValue]),
        leg("Square 1 1/2\"", .square, w: 1.5, material: "Solid Oak"),
        leg("Square Tapered 1 3/4\"", .square, w: 1.75, taper: 1, material: "Solid Oak"),
        leg("Round 1 1/2\"", .round, w: 1.5, material: "Solid Maple"),
        leg("Round Tapered 2\"", .round, w: 2, taper: 1.125, material: "Solid Walnut"),
        leg("Turned 2 1/2\"", .turned, w: 2.5, material: "Solid Maple"),
        leg("Hairpin 3/8\" Rod", .hairpin, w: 4, d: 4, rod: 0.375, material: "Steel"),
        leg("Sled 1\" Steel", .sled, w: 1, d: 16, rod: 1, material: "Steel"),
        leg("Plinth Block 3\"", .plinthBlock, w: 3, material: "Solid Oak"),
        leg("Caster 2\"", .caster, w: 2, material: "Steel"),
        rail("3/4\" x 3\" Apron", w: 0.75, h: 3),
        rail("3/4\" x 1 1/2\" Stretcher", w: 0.75, h: 1.5),
        rail("1 1/2\" x 1 1/2\" Stretcher", w: 1.5, h: 1.5),
        rail("3/4\" x 3/4\" Cleat", w: 0.75, h: 0.75, material: "Solid Pine"),
        rail("3/4\" x 2 1/2\" Slat", w: 2.5, h: 0.75),
        rail("1\" x 3\" Bed Slat", w: 3, h: 1, material: "Solid Pine"),
        rail("1\" Round Stretcher", w: 1, h: 1, profile: .round),
        edge("Edge Profile", "1/4\" Round-Over", .roundOver, size: 0.25),
        edge("Edge Profile", "1/8\" Round-Over", .roundOver, size: 0.125),
        edge("Edge Profile", "1/8\" Chamfer", .chamfer, size: 0.125),
        edge("Edge Profile", "3/4\" Bullnose", .bullnose, size: 0.75),
        edge("Edge Profile", "1/2\" Ogee", .ogee, size: 0.5),
        edge("Edge Profile", "3/8\" Cove", .cove, size: 0.375),
        edge("Edge Profile", "3/4\" Finger Pull", .fingerPull, size: 0.75),
        edge("Groove", "1/4\" x 1/4\" Groove", .groove, size: 0.25, depth: 0.25),
        edge("Groove", "1/4\" x 3/8\" Groove", .groove, size: 0.25, depth: 0.375),
        edge("Groove", "3/4\" x 1/4\" Dado", .groove, size: 0.75, depth: 0.25),
    ]

    /// Materials the standard types use that the FM3 template doesn't have.
    static let extraMaterials: [FurnitureTemplates.MaterialSpec] = [
        .init(name: "Hardboard", materialClass: .wood, color: 0x8C6A4A, transparency: 0, cost: 18, unit: .sheet, description: "Tempered hardboard, 1/4\", 4'x8' sheet"),
        .init(name: "Edge Banding", materialClass: .wood, color: 0xE0C595, transparency: 0, cost: 0.35, unit: .linearFoot, description: "Birch veneer edge banding, 13/16\""),
        .init(name: "PVC Edge Banding", materialClass: .plastic, color: 0xF4F2EE, transparency: 0, cost: 0.25, unit: .linearFoot, description: "White PVC edge banding, 1 mm"),
    ]

    /// The family name edge profile types of grooves use.
    public static let grooveFamily = "Groove"

    /// Creates the standard part types, their materials and the Part Tag where missing (idempotent). Returns nothing;
    /// tools call it before their first part, the template when it's made.
    public static func ensureStandard(in tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        var materials: [String: ElementID] = [:]
        for m in tx.model.elements(.materials) { materials[m.name] = m.id }
        let patterns = MaterialPatternDefaults.patternIndex(tx.model)
        for spec in extraMaterials where materials[spec.name] == nil {
            var m = MaterialData(materialClass: spec.materialClass, color: RGBColor(hex: spec.color), transparency: spec.transparency, description: spec.description)
            MaterialPatternDefaults.apply(to: &m, name: spec.name, patterns: patterns)
            m.cost = spec.cost
            m.costUnit = spec.unit
            materials[spec.name] = tx.create(.materials, name: spec.name, data: .material(m))
        }
        let existing = Set(tx.model.elements(.elementTypes).compactMap { t -> String? in
            guard let td = t.typeData, td.instanceCategory.isFurniturePart else { return nil }
            return "\(td.instanceCategory.rawValue)|\(td.familyName)|\(t.name)"
        })
        for spec in standard where !existing.contains("\(spec.category.rawValue)|\(spec.family)|\(spec.name)") {
            var params: [ParameterID: ParamValue] = [:]
            for (k, v) in spec.numbers { params[k] = .double(v) }
            for (k, v) in spec.texts { params[k] = .text(v) }
            for (k, v) in spec.materials { params[k] = .ref(materials[v]) }
            tx.create(.elementTypes, name: spec.name, data: .type(TypeData(instanceCategory: spec.category, familyName: spec.family, params: params)))
        }
        ensurePartTag(in: tx)
    }

    /// The Part Tag: Mark over the nominal size (W x L), for every part category, in a 24 × 7 mm box.
    static func ensurePartTag(in tx: TransactionContext) {
        guard !tx.model.elements(.families).contains(where: { $0.name == "Part Tag" }) else { return }
        var f = FamilyDefinition(name: "Part Tag", template: .tag)
        f.taggedCategories = Category.furnitureParts
        f.types = [FamilyTypeDefinition(name: "Mark and Size", values: [:])]
        // POLISH: 24 mm wide (was 18), so a size such as 22 3/4" x 66 1/2" stays inside the box.
        f.annotationLines = [
            FamilyLine(shape: .line(FamilyPoint("-0.012", "-0.0035"), FamilyPoint("0.012", "-0.0035"))),
            FamilyLine(shape: .line(FamilyPoint("0.012", "-0.0035"), FamilyPoint("0.012", "0.0035"))),
            FamilyLine(shape: .line(FamilyPoint("0.012", "0.0035"), FamilyPoint("-0.012", "0.0035"))),
            FamilyLine(shape: .line(FamilyPoint("-0.012", "0.0035"), FamilyPoint("-0.012", "-0.0035"))),
            FamilyLine(shape: .line(FamilyPoint("-0.012", "0"), FamilyPoint("0.012", "0"))),
        ]
        f.fills = [FamilyFill(points: [FamilyPoint("-0.012", "-0.0035"), FamilyPoint("0.012", "-0.0035"), FamilyPoint("0.012", "0.0035"), FamilyPoint("-0.012", "0.0035")], isMasking: true)]
        f.labels = [
            FamilyLabel(position: FamilyPoint("0", "0.0017"), parameterName: "Mark", height: 0.0022, bold: true, sample: "P1"),
            FamilyLabel(position: FamilyPoint("0", "-0.0018"), parameterName: "Size", height: 0.0018, sample: "11 1/4\" x 30\""),
        ]
        let fid = tx.create(.families, name: f.name, data: .family(f))
        tx.create(.elementTypes, name: "Mark and Size", data: .type(TypeData(instanceCategory: .tags, familyID: fid, familyName: f.name)))
    }

    /// The types tools start with (3/4" plywood sheets, a square leg, an apron), before the alphabetical first.
    public static let defaultNames: [String] = ["3/4\" Plywood", "3/4\" Plywood Shelf", "3/4\" Plywood Top", "Square 1 1/2\"", "3/4\" x 3\" Apron",
                                                "1/4\" Round-Over", "1/4\" x 1/4\" Groove"]

    /// The default type of a part category in a family (Panel, Shelf, Top, Leg, Rail, Edge Profile, Groove).
    public static func firstType(_ cat: Category, family: String? = nil, _ m: BIMModel) -> ElementID? {
        let list = m.types(for: cat).filter { family == nil || $0.typeData?.familyName == family }
        return (list.first { defaultNames.contains($0.name) } ?? list.first)?.id
    }
}
