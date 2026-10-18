import Foundation
import ArcusGeometry
import ArcusCalc

/// One layer of a library assembly: function, library material name and thickness in meters.
public struct LayerSpec: Hashable, Sendable {
    public var function: LayerFunction
    public var material: String
    public var thickness: Double
    public init(_ function: LayerFunction, _ material: String, _ thickness: Double) {
        self.function = function; self.material = material; self.thickness = thickness
    }
}

/// A library wall, floor, roof or ceiling type: name, category and layers (exterior → interior for walls,
/// top → bottom for floors, roofs and ceilings).
public struct AssemblySpec: Hashable, Sendable {
    public var name: String
    public var category: Category
    /// Wall function ("Interior", "Exterior", "Foundation", "Retaining"); nil for other categories.
    public var function: String?
    public var layers: [LayerSpec]
    public var fireRating: String?
    public var totalThickness: Double { layers.reduce(0) { $0 + $1.thickness } }

    public var systemFamily: SystemFamily {
        switch category {
        case .floors: .floor
        case .roofs: .roof
        case .ceilings: .ceiling
        case .buildingPads: .buildingPad
        default: .basicWall
        }
    }
    public var familyName: String {
        switch category {
        case .floors: "Floor"
        case .roofs: "Basic Roof"
        case .ceilings: "Compound Ceiling"
        case .buildingPads: "Building Pad"
        default: "Basic Wall"
        }
    }
    public var assembly: CompoundAssembly {
        CompoundAssembly(layers: layers.map { AssemblyLayer(function: $0.function, materialID: nil, thickness: $0.thickness) })
    }
}

/// Standard wall, floor, roof and ceiling types for imperial and metric projects (original Arcus content with
/// common industry nominal sizes). Imperial names follow U.S. practice (nominal inches, stud sizes); metric names
/// follow millimetre practice, including common Indian assemblies (RCC slabs, 230 mm brick walls).
public enum BuildingTypesLibrary {
    static func inch(_ v: Double) -> Double { v * 0.0254 }
    static func mm(_ v: Double) -> Double { v / 1000 }

    public static func assemblies(_ system: UnitSystem) -> [AssemblySpec] {
        system == .imperial ? imperialWalls + imperialFloors + imperialRoofs + imperialCeilings + imperialPads
            : metricWalls + metricFloors + metricRoofs + metricCeilings
    }
    public static func walls(_ system: UnitSystem) -> [AssemblySpec] { assemblies(system).filter { $0.category == .walls } }
    public static func floors(_ system: UnitSystem) -> [AssemblySpec] { assemblies(system).filter { $0.category == .floors } }
    public static func roofs(_ system: UnitSystem) -> [AssemblySpec] { assemblies(system).filter { $0.category == .roofs } }
    public static func ceilings(_ system: UnitSystem) -> [AssemblySpec] { assemblies(system).filter { $0.category == .ceilings } }

    // MARK: Imperial

    static func wall(_ name: String, _ function: String, _ layers: [LayerSpec], fire: String? = nil) -> AssemblySpec {
        AssemblySpec(name: name, category: .walls, function: function, layers: layers, fireRating: fire)
    }
    static func floor(_ name: String, _ layers: [LayerSpec]) -> AssemblySpec { AssemblySpec(name: name, category: .floors, layers: layers) }
    static func roof(_ name: String, _ layers: [LayerSpec]) -> AssemblySpec { AssemblySpec(name: name, category: .roofs, layers: layers) }
    static func ceiling(_ name: String, _ layers: [LayerSpec]) -> AssemblySpec { AssemblySpec(name: name, category: .ceilings, layers: layers) }

    // Imperial layer shorthands (thicknesses in inches).
    static func S(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.structure, m, inch(t)) }
    static func Sub(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.substrate, m, inch(t)) }
    static func Th(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.thermal, m, inch(t)) }
    static func F1(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.finish1, m, inch(t)) }
    static func F2(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.finish2, m, inch(t)) }
    static func Mb(_ m: String) -> LayerSpec { LayerSpec(.membrane, m, 0) }
    // Metric layer shorthands (thicknesses in millimetres).
    static func s(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.structure, m, mm(t)) }
    static func sub(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.substrate, m, mm(t)) }
    static func th(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.thermal, m, mm(t)) }
    static func f1(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.finish1, m, mm(t)) }
    static func f2(_ m: String, _ t: Double) -> LayerSpec { LayerSpec(.finish2, m, mm(t)) }

    static let gwb = "Gypsum Wall Board", gwbX = "Gypsum Wall Board, Type X", gwbMR = "Gypsum Wall Board, Moisture-Resistant"
    static let mStud = "Metal Stud", wStud = "Wood - Dimensional Lumber", cmu = "Concrete Masonry Units", brick = "Brick, Face Red"
    static let air = "Air Space", xps = "Rigid Insulation, XPS", polyiso = "Rigid Insulation, Polyiso", eps = "Rigid Insulation, EPS"
    static let gypSheath = "Gypsum Sheathing", ply = "Plywood", osb = "Oriented Strand Board (OSB)", wrb = "Weather-Resistive Barrier"
    static let conc = "Concrete, Cast-in-Place", felt = "Building Paper, Asphalt Felt"

    static let imperialWalls: [AssemblySpec] = [
        wall("Generic - 4\"", "Interior", [S(cmu, 4)]),
        wall("Generic - 6\"", "Interior", [S(cmu, 6)]),
        wall("Generic - 8\"", "Interior", [S(cmu, 8)]),
        wall("Generic - 12\"", "Interior", [S(cmu, 12)]),
        wall("Interior - 3 7/8\" Partition", "Interior", [F2(gwb, 0.625), S(mStud, 2.625), F2(gwb, 0.625)]),
        wall("Interior - 4 7/8\" Partition (1-hr)", "Interior", [F2(gwbX, 0.625), S(mStud, 3.625), F2(gwbX, 0.625)], fire: "1 HR"),
        wall("Interior - 4 1/2\" Partition (2x4)", "Interior", [F2(gwb, 0.5), S(wStud, 3.5), F2(gwb, 0.5)]),
        wall("Interior - 6 1/2\" Partition (2x6)", "Interior", [F2(gwb, 0.5), S(wStud, 5.5), F2(gwb, 0.5)]),
        wall("Interior - 6 1/8\" Partition (2-hr)", "Interior", [F2(gwbX, 0.625), F2(gwbX, 0.625), S(mStud, 3.625), F2(gwbX, 0.625), F2(gwbX, 0.625)], fire: "2 HR"),
        wall("Interior - 7 1/4\" Partition (6\" Mtl. Stud)", "Interior", [F2(gwb, 0.625), S(mStud, 6), F2(gwb, 0.625)]),
        wall("Interior - 4 3/4\" Partition (Wet Area)", "Interior", [F2("Cement Board", 0.5), S(mStud, 3.625), F2(gwbMR, 0.625)]),
        wall("Interior - 6 1/4\" Shaft Wall (2-hr)", "Interior", [F2("Gypsum Shaftliner", 1), S(mStud, 4), F2(gwbX, 0.625), F2(gwbX, 0.625)], fire: "2 HR"),
        wall("Interior - 10\" Chase Wall", "Interior", [F2(gwb, 0.625), S(mStud, 3.625), Th(air, 1.5), S(mStud, 3.625), F2(gwb, 0.625)]),
        wall("Interior - 4\" CMU", "Interior", [S(cmu, 3.625)]),
        wall("Interior - 6\" CMU", "Interior", [S(cmu, 5.625)]),
        wall("Interior - 8\" CMU", "Interior", [S(cmu, 7.625)], fire: "2 HR"),
        wall("Interior - 8\" CMU w/ Furring", "Interior", [S(cmu, 7.625), Sub(mStud, 0.875), F2(gwb, 0.625)]),
        wall("Exterior - Brick on 2x4 Wood Stud", "Exterior", [F1(brick, 3.625), Th(air, 1), Mb(wrb), Sub(ply, 0.5), S(wStud, 3.5), F2(gwb, 0.5)]),
        wall("Exterior - Brick on 2x6 Wood Stud", "Exterior", [F1(brick, 3.625), Th(air, 1), Mb(wrb), Sub(ply, 0.5), S(wStud, 5.5), F2(gwb, 0.5)]),
        wall("Exterior - Brick on Mtl. Stud", "Exterior", [F1(brick, 3.625), Th(air, 2), Th(xps, 2), Sub(gypSheath, 0.625), S(mStud, 6), F2(gwb, 0.625)]),
        wall("Exterior - Brick on CMU", "Exterior", [F1(brick, 3.625), Th(air, 2), Th(xps, 2), S(cmu, 7.625), F2(gwb, 0.625)]),
        wall("Exterior - 8\" CMU on Mtl. Stud", "Exterior", [F1("CMU, Split Face", 7.625), Th(air, 1), Th(xps, 2), Sub(gypSheath, 0.625), S(mStud, 3.625), F2(gwb, 0.625)]),
        wall("Exterior - 8\" CMU Insulated", "Exterior", [S(cmu, 7.625), Th(xps, 2), Sub(mStud, 1.625), F2(gwb, 0.625)]),
        wall("Exterior - 12\" CMU", "Exterior", [S(cmu, 11.625)]),
        wall("Exterior - Wood Siding on 2x6 Wood Stud", "Exterior", [F1("Wood Siding, Cedar Lap", 0.75), Mb(wrb), Sub(osb, 0.4375), S(wStud, 5.5), F2(gwb, 0.5)]),
        wall("Exterior - Fiber Cement Siding on 2x6 Wood Stud", "Exterior", [F1("Fiber Cement Siding, Lap", 0.3125), Mb(wrb), Sub(osb, 0.4375), S(wStud, 5.5), F2(gwb, 0.5)]),
        wall("Exterior - Vinyl Siding on 2x4 Wood Stud", "Exterior", [F1("Vinyl Siding, White", 0.5), Mb(wrb), Sub(osb, 0.4375), S(wStud, 3.5), F2(gwb, 0.5)]),
        wall("Exterior - Stucco on 2x6 Wood Stud", "Exterior", [F1("Stucco, Portland Cement", 0.875), Mb(wrb), Sub(ply, 0.5), S(wStud, 5.5), F2(gwb, 0.5)]),
        wall("Exterior - Stucco on Mtl. Stud", "Exterior", [F1("Stucco, Portland Cement", 0.875), Mb(wrb), Sub(gypSheath, 0.625), S(mStud, 6), F2(gwb, 0.625)]),
        wall("Exterior - EIFS on Mtl. Stud", "Exterior", [F1("EIFS Finish", 0.25), Th(eps, 2), Mb(wrb), Sub(gypSheath, 0.625), S(mStud, 6), F2(gwb, 0.625)]),
        wall("Exterior - Metal Panel on Mtl. Stud", "Exterior", [F1("Metal Panel, Insulated", 2), Th(air, 1), Sub(gypSheath, 0.625), S(mStud, 6), F2(gwb, 0.625)]),
        wall("Exterior - Stone Veneer on 2x6 Wood Stud", "Exterior", [F1("Stone Veneer, Manufactured", 2.5), Sub("Mortar, Cement", 0.75), Mb(wrb), Sub(ply, 0.5), S(wStud, 5.5), F2(gwb, 0.5)]),
        wall("Exterior - Brick Double Wythe 8\"", "Exterior", [S(brick, 3.625), S("Mortar, Cement", 0.75), S("Brick, Common", 3.625)]),
        wall("Exterior - 8\" Concrete", "Exterior", [S(conc, 8)]),
        wall("Exterior - 8\" Concrete Insulated", "Exterior", [S(conc, 8), Th(xps, 2), Sub(mStud, 1.625), F2(gwb, 0.625)]),
        wall("Exterior - 12\" Concrete Insulated", "Exterior", [S(conc, 12), Th(xps, 2), Sub(mStud, 1.625), F2(gwb, 0.625)]),
        wall("Exterior - SIP 6 1/2\" w/ Fiber Cement", "Exterior", [F1("Fiber Cement Siding, Lap", 0.3125), Mb(wrb), S(osb, 0.4375), Th(eps, 5.625), S(osb, 0.4375), F2(gwb, 0.5)]),
        wall("Exterior - ICF 6\" Core w/ Stucco", "Exterior", [F1("Stucco, Portland Cement", 0.875), Th(eps, 2.625), S(conc, 6), Th(eps, 2.625), F2(gwb, 0.5)]),
        wall("Foundation - 8\" Concrete", "Foundation", [S(conc, 8)]),
        wall("Foundation - 12\" Concrete", "Foundation", [S(conc, 12)]),
        wall("Foundation - 8\" CMU", "Foundation", [S(cmu, 7.625)]),
        wall("Retaining - 12\" Concrete", "Retaining", [S(conc, 12)]),
        wall("Retaining - 16\" Concrete", "Retaining", [S(conc, 16)]),
    ]

    static let imperialFloors: [AssemblySpec] = [
        floor("Concrete Slab 4\"", [S(conc, 4)]),
        floor("Concrete Slab 6\"", [S(conc, 6)]),
        floor("Concrete Slab 8\"", [S(conc, 8)]),
        floor("Concrete Slab 10\"", [S(conc, 10)]),
        floor("Concrete Slab 12\"", [S(conc, 12)]),
        floor("Slab on Grade 4\" w/ Vapor Retarder", [S(conc, 4), Mb("Vapor Retarder, Polyethylene"), Sub("Crushed Stone Aggregate", 4)]),
        floor("Slab on Grade 6\" w/ Vapor Retarder", [S(conc, 6), Mb("Vapor Retarder, Polyethylene"), Sub("Crushed Stone Aggregate", 4)]),
        floor("Concrete Slab 8\" + 2\" Topping", [F1("Concrete Topping", 2), S(conc, 8)]),
        floor("Concrete Slab 6\" - Tile", [F1("Porcelain Tile, Grey", 0.375), Sub("Mortar, Cement", 0.5), S(conc, 6)]),
        floor("Concrete Slab 6\" - Carpet", [F1("Carpet Tile, Charcoal", 0.375), S(conc, 6)]),
        floor("Concrete Slab 6\" - VCT", [F1("Vinyl Composition Tile", 0.125), S(conc, 6)]),
        floor("Concrete Slab 6\" - Terrazzo", [F1("Terrazzo, Cast-in-Place", 0.5), S(conc, 6)]),
        floor("Concrete Slab 6\" - Polished", [S("Concrete, Polished", 6)]),
        floor("Steel Deck 3\" + 3\" Concrete", [S("Concrete, Lightweight", 3), S("Steel Decking", 3)]),
        floor("Steel Deck 1 1/2\" + 2 1/2\" Concrete", [S("Concrete, Lightweight", 2.5), S("Steel Decking", 1.5)]),
        floor("Steel Deck 2\" + 3 1/4\" LW Concrete", [S("Concrete, Lightweight", 3.25), S("Steel Decking", 2)]),
        floor("Precast Hollow Core 8\" + 2\" Topping", [F1("Concrete Topping", 2), S("Concrete, Hollow Core Plank", 8)]),
        floor("Wood Joist 10\" - Wood Finish", [F1("Hardwood, Oak White", 0.75), Sub(ply, 0.75), S(wStud, 9.25), F2(gwb, 0.5)]),
        floor("Wood Joist 12\" - Carpet", [F1("Carpet, Broadloom Beige", 0.375), Sub(ply, 0.75), S(wStud, 11.25), F2(gwb, 0.625)]),
        floor("Wood I-Joist 11 7/8\" - LVT", [F1("Luxury Vinyl Tile, Oak", 0.25), Sub(osb, 0.75), S("Wood I-Joist", 11.875), F2(gwb, 0.625)]),
        floor("Wood Truss 16\" - Tile", [F1("Ceramic Tile", 0.375), Sub("Cement Board", 0.5), Sub(ply, 0.75), S(wStud, 16), F2(gwb, 0.625)]),
        floor("Wood Deck 2x6 on 2x10 Joists", [F1("Wood - Pressure Treated", 1.5), S("Wood - Pressure Treated", 9.25)]),
        floor("CLT 5-Ply 6 7/8\" - Wood Finish", [F1("Engineered Wood Flooring", 0.625), S("Cross-Laminated Timber (CLT)", 6.875)]),
        floor("Pavers on Concrete Slab 6\"", [F1("Concrete Pavers, Grey", 2.375), Sub("Sand", 1), S(conc, 6)]),
    ]

    static let imperialRoofs: [AssemblySpec] = [
        roof("Asphalt Shingle - Wood Rafter 2x8", [F1("Asphalt Shingles, Charcoal", 0.375), Mb(felt), Sub(ply, 0.625), S(wStud, 7.25)]),
        roof("Asphalt Shingle - Wood Rafter 2x10 Insulated", [F1("Asphalt Shingles, Weathered Wood", 0.375), Mb(felt), Sub(ply, 0.625), S(wStud, 9.25), F2(gwb, 0.625)]),
        roof("Standing Seam Metal - Wood Rafter 2x10", [F1("Metal Roofing", 0.5), Mb(felt), Sub(ply, 0.625), S(wStud, 9.25)]),
        roof("Clay Tile - Wood Rafter 2x8", [F1("Clay Roof Tile", 1.5), Mb(felt), Sub(ply, 0.625), S(wStud, 7.25)]),
        roof("Concrete Tile - Wood Rafter 2x8", [F1("Concrete Roof Tile", 1.5), Mb(felt), Sub(ply, 0.625), S(wStud, 7.25)]),
        roof("Slate - Wood Rafter 2x8", [F1("Slate Roofing", 0.375), Mb(felt), Sub(ply, 0.625), S(wStud, 7.25)]),
        roof("Wood Shake - Wood Rafter 2x8", [F1("Wood Shake Roofing", 0.75), Mb(felt), Sub(ply, 0.625), S(wStud, 7.25)]),
        roof("Built-Up Roof on Steel Deck", [F1("Bituminous Membrane", 0.375), Sub(gypSheath, 0.5), Th(polyiso, 4), S("Steel Decking", 1.5)]),
        roof("TPO on Rigid Insulation - Steel Deck", [F1("TPO Membrane, White", 0.0625), Sub(gypSheath, 0.5), Th(polyiso, 4), S("Steel Decking", 1.5)]),
        roof("TPO on Rigid Insulation - Concrete Slab 8\"", [F1("TPO Membrane, White", 0.0625), Th(polyiso, 4), S(conc, 8)]),
        roof("EPDM on Rigid Insulation - Concrete Slab 8\"", [F1("EPDM Membrane", 0.0625), Th(polyiso, 4), S(conc, 8)]),
        roof("Green Roof - Concrete Slab 8\"", [F1("Planting Soil", 6), Sub("Drainage Mat", 1), Mb("Root Barrier"), Th(xps, 4), S(conc, 8)]),
        roof("Insulated Metal Panel Roof 4\"", [S("Metal Panel, Insulated", 4)]),
    ]

    static let imperialCeilings: [AssemblySpec] = [
        ceiling("2'x2' ACT System", [F1("Acoustic Ceiling Tile, Fine Fissured", 0.75)]),
        ceiling("2'x4' ACT System", [F1("Acoustic Ceiling Tile", 0.625)]),
        ceiling("GWB 5/8\" on Mtl. Furring", [S(mStud, 0.875), F1(gwb, 0.625)]),
        ceiling("GWB 1/2\" on Wood Furring", [S(wStud, 0.75), F1(gwb, 0.5)]),
        ceiling("GWB 5/8\" Type X on Mtl. Furring (1-hr)", [S(mStud, 0.875), F1(gwbX, 0.625)]),
        ceiling("Plaster 7/8\" on Mtl. Lath", [S(mStud, 0.75), F1("Gypsum Plaster", 0.875)]),
        ceiling("Wood Plank Ceiling 3/4\"", [F1("Softwood, Pine", 0.75)]),
        ceiling("Metal Pan Ceiling 2'x2'", [F1("Metal Ceiling Panel", 0.5)]),
    ]

    static let imperialPads: [AssemblySpec] = [
        AssemblySpec(name: "Building Pad 12\"", category: .buildingPads, layers: [S("Earth", 12)]),
    ]

    // MARK: Metric

    static let pb = "Plasterboard", fr = "Gypsum Wall Board, Type X", plaster = "Cement Plaster", block = "Concrete Block, Hollow"
    static let rcc = "Concrete, Reinforced (RCC)", brickC = "Brick, Common", mw = "Mineral Wool"

    static let metricWalls: [AssemblySpec] = [
        wall("Generic - 100mm", "Interior", [s(cmu, 100)]),
        wall("Generic - 150mm", "Interior", [s(cmu, 150)]),
        wall("Generic - 200mm", "Interior", [s(cmu, 200)]),
        wall("Generic - 250mm", "Interior", [s(cmu, 250)]),
        wall("Generic - 300mm", "Interior", [s(cmu, 300)]),
        wall("Interior - 75mm Partition", "Interior", [f2(pb, 12.5), s(mStud, 50), f2(pb, 12.5)]),
        wall("Interior - 100mm Partition", "Interior", [f2(pb, 12.5), s("Timber Stud", 75), f2(pb, 12.5)]),
        wall("Interior - 125mm Partition (60 min)", "Interior", [f2(fr, 12.5), f2(fr, 12.5), s(mStud, 75), f2(fr, 12.5), f2(fr, 12.5)], fire: "60 min"),
        wall("Interior - 150mm Partition (Acoustic)", "Interior", [f2(pb, 12.5), f2(pb, 12.5), s(mStud, 100), f2(pb, 12.5), f2(pb, 12.5)]),
        wall("Interior - 100mm Partition (Wet Area)", "Interior", [f2("Cement Board", 12.5), s(mStud, 75), f2(gwbMR, 12.5)]),
        wall("Interior - 150mm Masonry", "Interior", [f1("Plaster", 13), s(cmu, 124), f1("Plaster", 13)]),
        wall("Interior - 100mm Blockwork, Plastered", "Interior", [f1(plaster, 12.5), s(block, 100), f1(plaster, 12.5)]),
        wall("Interior - 200mm Blockwork, Plastered", "Interior", [f1(plaster, 12.5), s(block, 200), f1(plaster, 12.5)]),
        wall("Interior - 115mm Brick Partition", "Interior", [f1(plaster, 12), s(brickC, 115), f1(plaster, 12)]),
        wall("Interior - 230mm Brick Wall", "Interior", [f1(plaster, 12), s(brickC, 230), f1(plaster, 12)]),
        wall("Interior - 100mm AAC Block", "Interior", [f1(plaster, 12), s("AAC Block", 100), f1(plaster, 12)]),
        wall("Interior - 150mm AAC Block", "Interior", [f1(plaster, 12), s("AAC Block", 150), f1(plaster, 12)]),
        wall("Exterior - 230mm Brick Wall", "Exterior", [f1(plaster, 20), s(brickC, 230), f2(plaster, 12)]),
        wall("Exterior - 345mm Brick Wall", "Exterior", [f1(plaster, 20), s(brickC, 345), f2(plaster, 12)]),
        wall("Exterior - 230mm Fly Ash Brick", "Exterior", [f1(plaster, 20), s("Brick, Fly Ash", 230), f2(plaster, 12)]),
        wall("Exterior - 200mm AAC Block", "Exterior", [f1(plaster, 20), s("AAC Block", 200), f2(plaster, 12)]),
        wall("Exterior - 200mm Concrete Block", "Exterior", [f1(plaster, 20), s(block, 200), f2(plaster, 12)]),
        wall("Exterior - 300mm Laterite Block", "Exterior", [f1(plaster, 20), s("Laterite Block", 300), f2(plaster, 12)]),
        wall("Exterior - Brick Cavity 300mm", "Exterior", [f1("Brick, Face Red", 102.5), th(air, 50), th("Rigid Insulation, PIR", 50), s(block, 100), f2("Plaster", 12.5)]),
        wall("Exterior - Clinker Brick Cavity 380mm", "Exterior", [f1("Brick, Clinker", 115), th(mw, 110), s("Brick, Sand-Lime", 140), f2("Plaster", 15)]),
        wall("Exterior - Brick on CMU", "Exterior", [f1(brickC, 102), th("Rigid Insulation", 75), s(cmu, 190), f2("Plaster", 13)]),
        wall("Exterior - Concrete 300mm", "Exterior", [s(conc, 250), th("Rigid Insulation", 50)]),
        wall("Exterior - Render on Blockwork 250mm", "Exterior", [f1("Render, Silicone Coloured", 20), s(block, 215), f2("Plaster", 15)]),
        wall("Exterior - ETICS on Concrete 350mm", "Exterior", [f1("EIFS Finish", 10), th(eps, 120), s(conc, 200), f2("Plaster", 20)]),
        wall("Exterior - Rainscreen on Concrete 350mm", "Exterior", [f1("Fiber Cement Panel, Smooth", 10), th("Air Gap, Ventilated", 40), th(mw, 100), s(conc, 200)]),
        wall("Exterior - Stone Clad Concrete 300mm", "Exterior", [f1("Granite, Grey", 30), th("Air Gap, Ventilated", 20), th(mw, 50), s(conc, 200)]),
        wall("Exterior - Timber Frame Render 240mm", "Exterior", [f1("Render, Silicone Coloured", 10), th("Wood Fibre Board", 60), s("Timber Stud", 140), sub(osb, 15), f2(pb, 15)]),
        wall("Exterior - Metal Panel on Steel Stud 250mm", "Exterior", [f1("Metal Panel, Insulated", 50), th(air, 25), sub(gypSheath, 12.5), s(mStud, 150), f2(pb, 12.5)]),
        wall("Exterior - CLT 100mm Clad 300mm", "Exterior", [f1("Timber Cladding", 20), th("Air Gap, Ventilated", 25), th("Wood Fibre Board", 140), s("Cross-Laminated Timber (CLT)", 100), f2(pb, 15)]),
        wall("Exterior - Rammed Earth 400mm", "Exterior", [s("Rammed Earth", 400)]),
        wall("Foundation - 300mm Concrete", "Foundation", [s(conc, 300)]),
        wall("Foundation - 450mm Random Rubble", "Foundation", [s("Stone, Random Rubble", 450)]),
        wall("Retaining - 300mm Concrete", "Retaining", [s(conc, 300)]),
        wall("Retaining - 400mm Concrete", "Retaining", [s(conc, 400)]),
    ]

    static let metricFloors: [AssemblySpec] = [
        floor("Concrete Slab 150mm", [s(conc, 150)]),
        floor("Concrete Slab 200mm", [s(conc, 200)]),
        floor("Concrete Slab 250mm", [s(conc, 250)]),
        floor("Concrete Slab 300mm", [s(conc, 300)]),
        floor("RCC Slab 100mm", [s(rcc, 100)]),
        floor("RCC Slab 125mm", [s(rcc, 125)]),
        floor("RCC Slab 150mm", [s(rcc, 150)]),
        floor("RCC Slab 200mm", [s(rcc, 200)]),
        floor("RCC Slab 150mm - Vitrified Tile", [f1("Vitrified Tile, Double Charged", 10), sub("Mortar, Cement", 40), s(rcc, 150), f2(plaster, 12)]),
        floor("RCC Slab 150mm - Kota Stone", [f1("Kota Stone", 25), sub("Mortar, Cement", 25), s(rcc, 150), f2(plaster, 12)]),
        floor("RCC Slab 150mm - Marble", [f1("Marble, White", 20), sub("Mortar, Cement", 30), s(rcc, 150), f2(plaster, 12)]),
        floor("RCC Slab 150mm - IPS", [f1("IPS Flooring", 40), s(rcc, 150), f2(plaster, 12)]),
        floor("RCC Slab 125mm - Granite", [f1("Granite, Grey", 20), sub("Mortar, Cement", 30), s(rcc, 125), f2(plaster, 12)]),
        floor("Ground Slab 150mm on Hardcore", [s(conc, 150), LayerSpec(.membrane, "Damp-Proof Course", 0), sub("Hardcore Fill", 150)]),
        floor("Ground Floor - PCC 100mm with Tile", [f1("Ceramic Tile, Anti-Skid", 10), sub("Mortar, Cement", 40), s("Concrete, Lean Mix (PCC)", 100), sub("Hardcore Fill", 150)]),
        floor("Screed on Concrete 250mm", [f1("Screed", 50), s(conc, 200)]),
        floor("Concrete Slab 200mm - Carpet Tile", [f1("Carpet Tile, Charcoal", 8), s(conc, 200)]),
        floor("Concrete Slab 200mm - Epoxy", [f1("Epoxy Floor Coating, Grey", 3), s(conc, 200)]),
        floor("Concrete Slab 200mm - LVT", [f1("Luxury Vinyl Tile, Oak", 5), sub("Screed", 40), s(conc, 200)]),
        floor("Terrazzo on Slab 200mm", [f1("Terrazzo, Cast-in-Place", 20), sub("Screed", 40), s(conc, 200)]),
        floor("Raised Access Floor 150mm on Slab 200mm", [f1("Raised Access Floor Panel", 40), th(air, 110), s(conc, 200)]),
        floor("Composite Steel Deck 130mm", [s("Concrete, Lightweight", 80), s("Steel Decking", 50)]),
        floor("Hollow Core Plank 200mm + 50mm Topping", [f1("Concrete Topping", 50), s("Concrete, Hollow Core Plank", 200)]),
        floor("Timber Floor 300mm", [f1("Oak Flooring", 20), sub("Timber Stud", 20), s("Timber Stud", 235), f2(pb, 25)]),
        floor("Timber Joist 225mm - Timber Finish", [f1("Engineered Wood Flooring", 20), sub(osb, 22), s("Timber Stud", 225), f2(pb, 15)]),
        floor("CLT Floor 160mm - Screed", [f1("Screed", 50), th(mw, 30), s("Cross-Laminated Timber (CLT)", 160)]),
        floor("Paving on Slab", [f1("Stone Paving", 40), s(conc, 150)]),
    ]

    static let metricRoofs: [AssemblySpec] = [
        roof("Tiled Roof - Timber", [f1("Clay Roof Tile", 50), th(mw, 150), s("Timber Stud", 100)]),
        roof("Metal Roof - Insulated", [f1("Metal Roofing", 10), th("Rigid Insulation", 150), s("Timber Stud", 140)]),
        roof("Flat Roof - Concrete", [LayerSpec(.membrane, "Membrane", 0), th("Rigid Insulation", 120), s(conc, 200)]),
        roof("Concrete Tile - Timber Rafter 150mm", [f1("Concrete Roof Tile", 50), LayerSpec(.membrane, felt, 0), s("Timber Stud", 150), f2(pb, 12.5)]),
        roof("Slate - Timber Rafter 150mm", [f1("Slate Roofing", 10), LayerSpec(.membrane, felt, 0), sub(osb, 18), s("Timber Stud", 150)]),
        roof("Standing Seam Zinc - Timber Rafter 200mm", [f1("Zinc, Natural", 5), LayerSpec(.membrane, "Weather-Resistive Barrier", 0), sub(ply, 18), s("Timber Stud", 200), f2(pb, 12.5)]),
        roof("Mangalore Tile - Timber Rafter 100mm", [f1("Mangalore Tile", 25), s("Hardwood, Sal", 100)]),
        roof("Flat Roof - RCC 150mm with Brickbat Coba", [f1("Mosaic Tile, Ceramic White", 10), sub("Brickbat Coba", 100), LayerSpec(.membrane, "Bituminous Membrane", 0), s(rcc, 150), f2(plaster, 12)]),
        roof("Flat Roof - RCC 125mm with Waterproofing", [f1("Bituminous Membrane", 4), sub("Screed", 50), s(rcc, 125), f2(plaster, 12)]),
        roof("Inverted Flat Roof - Concrete 200mm", [f1("Gravel", 50), th(xps, 120), LayerSpec(.membrane, "Bituminous Membrane", 0), s(conc, 200)]),
        roof("Green Roof - Concrete 250mm", [f1("Planting Soil", 150), sub("Drainage Mat", 25), LayerSpec(.membrane, "Root Barrier", 0), th(xps, 100), s(conc, 250)]),
        roof("Insulated Metal Panel Roof 100mm", [s("Metal Panel, Insulated", 100)]),
        roof("Fiber Cement Sheet Roof 6mm", [s("Fiber Cement Roofing Sheet", 6)]),
        roof("Polycarbonate Roof 16mm", [s("Polycarbonate, Multiwall Clear", 16)]),
        roof("Thatch Roof 300mm", [f1("Thatch", 250), s("Bamboo, Natural", 50)]),
    ]

    static let metricCeilings: [AssemblySpec] = [
        ceiling("Plasterboard Ceiling", [f1(pb, 12.5)]),
        ceiling("Acoustic Tile 600 x 600", [f1("Acoustic Ceiling Tile", 20)]),
        ceiling("Acoustic Tile 600 x 1200", [f1("Acoustic Ceiling Tile, Fine Fissured", 15)]),
        ceiling("Gypsum False Ceiling on Metal Grid", [s(mStud, 50), f1(pb, 12.5)]),
        ceiling("POP False Ceiling 20mm", [f1("Plaster of Paris (POP)", 20)]),
        ceiling("Metal Tile 600 x 600", [f1("Metal Ceiling Panel", 20)]),
        ceiling("Timber Slat Ceiling 20mm", [f1("Softwood, Pine", 20)]),
        ceiling("Plaster on Metal Lath 25mm", [s(mStud, 10), f1("Gypsum Plaster", 25)]),
        ceiling("Fiber Cement Board Ceiling 8mm", [f1("Fiber Cement Board", 8)]),
    ]

    // MARK: Imperial equivalents of the base template content

    /// Names the base template gives its types (metric) → the imperial type that replaces each in imperial projects.
    /// The `ProjectTemplates.Ids` keys keep the base names so code that looks content up by key keeps working.
    public static let imperialEquivalents: [String: String] = [
        "Generic - 200mm": "Generic - 8\"",
        "Interior - 100mm Partition": "Interior - 4 1/2\" Partition (2x4)",
        "Interior - 150mm Masonry": "Interior - 6\" CMU",
        "Exterior - Brick on CMU": "Exterior - Brick on CMU",
        "Exterior - Concrete 300mm": "Exterior - 12\" Concrete Insulated",
        "Retaining - 300mm Concrete": "Retaining - 12\" Concrete",
        "Exterior - Timber Frame Clad": "Exterior - Wood Siding on 2x6 Wood Stud",
        "Concrete Slab 200mm": "Concrete Slab 8\"",
        "Screed on Concrete 250mm": "Concrete Slab 8\" + 2\" Topping",
        "Timber Floor 300mm": "Wood Joist 10\" - Wood Finish",
        "Paving on Slab": "Pavers on Concrete Slab 6\"",
        "Building Pad 300mm": "Building Pad 12\"",
        "Tiled Roof - Timber": "Clay Tile - Wood Rafter 2x8",
        "Metal Roof - Insulated": "Standing Seam Metal - Wood Rafter 2x10",
        "Flat Roof - Concrete": "TPO on Rigid Insulation - Concrete Slab 8\"",
        "Plasterboard Ceiling": "GWB 5/8\" on Mtl. Furring",
        "Acoustic Tile 600 x 600": "2'x2' ACT System",
    ]
}
