import Foundation
import ArcusGeometry

/// Where a library material is typical. Used for filtering in the library picker; every material can be used anywhere.
public enum MaterialRegion: String, Codable, Sendable, CaseIterable {
    case world = "Worldwide"
    case northAmerica = "North America"
    case latinAmerica = "Latin America"
    case europe = "Europe"
    case india = "India & South Asia"
    case eastAsia = "East & Southeast Asia"
    case middleEastAfrica = "Middle East & Africa"
    case oceania = "Oceania"
}

/// One entry of the built-in material library (original Arcus content: generic names, approximate sRGB colors).
public struct LibraryMaterial: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public var name: String
    public var materialClass: MaterialClass
    /// sRGB color as 0xRRGGBB.
    public var hex: UInt32
    /// 0 = opaque, 1 = fully transparent.
    public var transparency: Double
    public var description: String
    public var region: MaterialRegion
    /// Part of the curated set every new project starts with (the rest is added on demand).
    public var inNewProjects: Bool

    public var color: RGBColor { RGBColor(hex: hex) }

    /// Material data for this entry. When `fillPatterns` (pattern name → element id) is given, the cut and surface
    /// pattern ids point at the project's pattern for the material's class.
    public func materialData(fillPatterns: [String: ElementID] = [:]) -> MaterialData {
        var m = MaterialData(materialClass: materialClass, color: color, transparency: transparency, description: description)
        MaterialPatternDefaults.apply(to: &m, name: name, patterns: fillPatterns) // W4-HATCH: cut and surface patterns by material name and class
        return m
    }
}

/// The built-in material library: common building materials from around the world.
///
/// New projects get the curated `newProjectSet` (every material the standard wall, floor, roof, ceiling, door, window
/// and column types use, plus common finishes); the rest is added on demand from Manage ▸ Materials ▸ Add from Library.
public enum MaterialLibrary {
    static func m(_ name: String, _ c: MaterialClass, _ hex: UInt32, _ description: String, _ region: MaterialRegion = .world,
                  t: Double = 0) -> LibraryMaterial {
        LibraryMaterial(name: name, materialClass: c, hex: hex, transparency: t, description: description, region: region,
                        inNewProjects: curated.contains(name))
    }

    /// Everyday materials every new project starts with, whatever its units. The standard types of the project's unit
    /// system bring the other materials they use.
    static let curated: Set<String> = [
        "Concrete, Cast-in-Place", "Concrete, Precast", "Concrete, Lightweight", "Concrete, Polished", "Screed", "Mortar, Cement", "Concrete Paving",
        "Terrazzo, Cast-in-Place",
        "Brick, Common", "Brick, Face Red", "Concrete Masonry Units", "AAC Block",
        "Stone Paving", "Granite, Grey", "Granite, Black Polished", "Marble, White", "Limestone", "Travertine", "Slate, Grey", "Sandstone, Buff",
        "Engineered Quartz",
        "Steel", "Steel, Structural", "Steel, Stainless Brushed", "Steel, Galvanized", "Aluminum", "Aluminum, Anodized Black", "Metal Roofing",
        "Metal Stud", "Steel Decking", "Aluminum Composite Panel, Silver",
        "Timber Stud", "Timber Cladding", "Oak Flooring", "Hardwood", "Softwood, Pine", "Hardwood, Oak White", "Hardwood, Walnut", "Hardwood, Maple",
        "Hardwood, Teak", "Bamboo, Natural",
        "Cross-Laminated Timber (CLT)", "Glued-Laminated Timber (Glulam)", "Laminated Veneer Lumber (LVL)", "Plywood", "Oriented Strand Board (OSB)",
        "Medium-Density Fiberboard (MDF)", "Engineered Wood Flooring",
        "Glass", "Glass, Clear Float", "Glass, Low-E Insulated", "Glass, Frosted",
        "Plasterboard", "Plaster", "Gypsum Wall Board", "Gypsum Wall Board, Type X", "Gypsum Wall Board, Moisture-Resistant", "Cement Board",
        "Cement Plaster", "Acoustic Ceiling Tile",
        "Rigid Insulation", "Mineral Wool", "Batt Insulation, Fiberglass", "Rigid Insulation, XPS", "Rigid Insulation, EPS", "Air Space",
        "Membrane", "Vapor Retarder, Polyethylene", "Weather-Resistive Barrier", "Bituminous Membrane",
        "Clay Roof Tile", "Asphalt Shingles, Charcoal",
        "Ceramic Tile", "Ceramic Tile, White Glazed", "Porcelain Tile, Grey", "Terracotta Tile", "Sanitaryware, Vitreous China",
        "Laminate", "Vinyl Sheet Flooring", "Luxury Vinyl Tile, Oak", "Linoleum, Natural", "Carpet Tile, Charcoal", "Carpet, Broadloom Beige",
        "Epoxy Floor Coating, Grey", "Wallpaper, Vinyl Neutral",
        "Paint - White", "Paint - Off-White", "Paint - Light Grey", "Paint - Charcoal",
        "Fiber Cement Panel, Smooth", "Plastic Laminate, White", "Polycarbonate, Multiwall Clear",
        "Earth", "Soil, Topsoil", "Sand", "Gravel", "Crushed Stone Aggregate", "Grass", "Mulch, Bark", "Asphalt Paving", "Water",
    ]

    /// Every library material, grouped loosely by kind.
    public static let all: [LibraryMaterial] = concrete + masonry + stone + metals + woods + engineeredWood + glass + plasters
        + insulation + membranesAndRoofing + ceramics + floorAndWallFinishes + paints + claddingAndPlastics + traditional + site

    /// The curated set new projects start with.
    public static var newProjectSet: [LibraryMaterial] { all.filter(\.inNewProjects) }

    public static func named(_ name: String) -> LibraryMaterial? { index[name] }
    static let index: [String: LibraryMaterial] = Dictionary(all.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })

    // MARK: Concrete

    static let concrete: [LibraryMaterial] = [
        m("Concrete, Cast-in-Place", .concrete, 0xB9B6AF, "Normal-weight structural concrete poured on site."),
        m("Concrete, Reinforced (RCC)", .concrete, 0xB5B2AB, "Reinforced cement concrete for slabs, beams and columns.", .india),
        m("Concrete, Precast", .concrete, 0xC4C1BA, "Factory-cast concrete panels and members."),
        m("Concrete, Lightweight", .concrete, 0xC9C6BE, "Structural lightweight concrete, typically on metal deck."),
        m("Concrete, Lean Mix (PCC)", .concrete, 0xB3AFA6, "Plain cement concrete for blinding, bedding and ground floors.", .india),
        m("Concrete, High Strength", .concrete, 0xA9A7A1, "High-strength concrete for columns and transfer structures."),
        m("Concrete, Exposed Architectural", .concrete, 0xBEBBB4, "Smooth fair-faced concrete left exposed as the finish."),
        m("Concrete, Board-Formed", .concrete, 0xAFABA3, "Exposed concrete showing the grain of timber formwork boards."),
        m("Concrete, Polished", .concrete, 0xA7A6A2, "Ground and polished concrete floor surface."),
        m("Concrete, White", .concrete, 0xE3E1DB, "Concrete made with white cement and light aggregates."),
        m("Concrete, Black Pigmented", .concrete, 0x4A4A4A, "Through-coloured dark concrete."),
        m("Concrete, Pervious", .concrete, 0xA59F94, "Open-graded concrete that lets water drain through."),
        m("Concrete, Stamped", .concrete, 0xB39C84, "Imprinted and coloured concrete paving."),
        m("Concrete, Fly Ash Blend", .concrete, 0xAEACA7, "Concrete with fly ash replacing part of the cement."),
        m("Concrete, Hollow Core Plank", .concrete, 0xBDBAB2, "Precast prestressed hollow core floor planks."),
        m("Concrete Topping", .concrete, 0xC0BDB6, "Cast topping over precast or structural slabs."),
        m("Screed", .concrete, 0xC8C4BC, "Sand-cement floor screed."),
        m("Shotcrete", .concrete, 0xB0ACA4, "Sprayed concrete for shoring, tunnels and pools."),
        m("Mortar, Cement", .concrete, 0xC1BDB4, "Cement-sand mortar for bedding tiles and stone."),
        m("Grout, Cementitious", .concrete, 0xBDB9B0, "Cement grout for block cores and tile joints."),
        m("GFRC Panel", .concrete, 0xD6D3CC, "Glass-fibre reinforced concrete cladding panel."),
        m("Terrazzo, Cast-in-Place", .concrete, 0xD9D3C8, "Marble chips in a cement matrix, ground smooth."),
        m("Terrazzo Tile", .concrete, 0xCFC8BC, "Precast terrazzo floor tile."),
        m("IPS Flooring", .concrete, 0xA6A39C, "Indian Patent Stone: cement concrete floor with a trowelled finish.", .india),
        m("Red Oxide Flooring", .concrete, 0x8E3B2E, "Cement floor coloured with red oxide, trowelled smooth.", .india),
        m("Encaustic Cement Tile", .concrete, 0xB9B2A4, "Patterned pressed-cement tile."),
        m("Athangudi Tile", .concrete, 0xA8483C, "Handmade patterned cement tile from Tamil Nadu.", .india),
        m("Concrete Roof Tile", .concrete, 0x6C6E70, "Interlocking concrete roof tile."),
        m("Fiber Cement Siding, Lap", .concrete, 0xB9B3A8, "Fibre cement lap siding boards.", .northAmerica),
        m("Fiber Cement Panel, Smooth", .concrete, 0x9FA1A0, "Through-coloured fibre cement façade panel."),
        m("Fiber Cement Board", .concrete, 0xBEBBB3, "Flat fibre cement sheet for soffits, ceilings and partitions."),
        m("Fiber Cement Roofing Sheet", .concrete, 0xA9A9A3, "Corrugated fibre cement roofing sheet.", .india),
        m("Concrete Pavers, Grey", .concrete, 0xA7A39C, "Precast concrete paving blocks."),
        m("Concrete Pavers, Interlocking Red", .concrete, 0x9B5445, "Coloured interlocking concrete paving blocks.", .india),
        m("Concrete Paving", .concrete, 0xB8B4AC, "Cast-in-place concrete sidewalk and hardstanding."),
    ]

    // MARK: Masonry

    static let masonry: [LibraryMaterial] = [
        m("Brick, Common", .masonry, 0xA9573F, "General-purpose fired clay brick."),
        m("Brick, Face Red", .masonry, 0x9E4A35, "Red clay facing brick."),
        m("Brick, Face Buff", .masonry, 0xD2B58A, "Buff clay facing brick."),
        m("Brick, Face Brown", .masonry, 0x7A4A35, "Dark brown clay facing brick."),
        m("Brick, Face Grey", .masonry, 0x8A8580, "Grey clay facing brick."),
        m("Brick, Engineering Blue", .masonry, 0x3F4450, "Dense, low-absorption engineering brick.", .europe),
        m("Brick, Clinker", .masonry, 0x5E3A2E, "Hard-fired clinker facing brick.", .europe),
        m("Brick, Yellow Stock", .masonry, 0xC9A66B, "Soft yellow stock brick.", .europe),
        m("Brick, Sand-Lime", .masonry, 0xE2DDD2, "Calcium silicate (sand-lime) brick.", .europe),
        m("Brick, Glazed White", .masonry, 0xEDEBE5, "Glazed facing brick."),
        m("Brick, Reclaimed", .masonry, 0x96604A, "Salvaged clay brick with weathered faces."),
        m("Brick, Fly Ash", .masonry, 0xA8A39A, "Brick made from fly ash, sand and lime.", .india),
        m("Brick, Wire-Cut Red", .masonry, 0xA24B34, "Machine-made wire-cut clay brick.", .india),
        m("Brick, Handmade Country", .masonry, 0xA0543A, "Hand-moulded clay brick fired in a kiln.", .india),
        m("Brick, Firebrick", .masonry, 0xD7B98C, "Refractory brick for fireplaces and ovens."),
        m("Concrete Masonry Units", .masonry, 0xA8A49C, "Standard hollow concrete block (CMU)."),
        m("CMU, Split Face", .masonry, 0xB2ADA3, "Concrete block with a rough split face.", .northAmerica),
        m("CMU, Ground Face", .masonry, 0xBDB8AE, "Concrete block ground to expose the aggregate."),
        m("CMU, Lightweight", .masonry, 0xB7B3AA, "Lightweight-aggregate concrete block."),
        m("CMU, Burnished Tan", .masonry, 0xC7B08D, "Coloured, burnished architectural block."),
        m("Concrete Block, Hollow", .masonry, 0xA3A098, "Hollow concrete block masonry.", .india),
        m("Concrete Block, Solid", .masonry, 0x9E9B93, "Solid dense concrete block."),
        m("AAC Block", .masonry, 0xE3E1DA, "Autoclaved aerated concrete block."),
        m("Clay Block, Hollow", .masonry, 0xB8694A, "Large-format perforated fired clay block.", .europe),
        m("Hollow Clay Tile", .masonry, 0xB9724F, "Structural hollow clay tile."),
        m("Laterite Block", .masonry, 0x9A4E32, "Cut laterite stone block.", .india),
        m("Brickbat Coba", .masonry, 0x9A6A52, "Broken brick in lime-cement mortar, laid to falls as roof insulation.", .india),
    ]

    // MARK: Stone

    static let stone: [LibraryMaterial] = [
        m("Stone Paving", .stone, 0xB3ABA0, "Natural stone paving slabs."),
        m("Granite, Grey", .stone, 0x8E8C8A, "Grey speckled granite."),
        m("Granite, Black Polished", .stone, 0x2B2B2D, "Polished black granite."),
        m("Granite, Red", .stone, 0x8A4B43, "Red granite."),
        m("Granite, Pink", .stone, 0xB88E84, "Pink granite."),
        m("Marble, White", .stone, 0xEEEDEA, "White marble."),
        m("Marble, White Veined", .stone, 0xE6E4E0, "White marble with grey veining."),
        m("Marble, Makrana White", .stone, 0xF1EFEA, "Fine white marble quarried in Rajasthan.", .india),
        m("Marble, Green", .stone, 0x3F5E4B, "Dark green marble.", .india),
        m("Marble, Black", .stone, 0x262626, "Black marble."),
        m("Marble, Beige", .stone, 0xDCCBB0, "Beige marble."),
        m("Limestone", .stone, 0xD9CFBC, "Natural limestone."),
        m("Limestone, Portland", .stone, 0xE0DACB, "Pale oolitic limestone from Dorset.", .europe),
        m("Limestone, Bath", .stone, 0xD8C79F, "Honey-coloured oolitic limestone.", .europe),
        m("Limestone, Indiana", .stone, 0xCFC6B4, "Buff oolitic limestone from the U.S. Midwest.", .northAmerica),
        m("Travertine", .stone, 0xDCCDB3, "Porous banded limestone, filled or unfilled.", .europe),
        m("Kota Stone", .stone, 0x6C7A74, "Blue-green fine-grained limestone from Rajasthan.", .india),
        m("Kota Stone, Brown", .stone, 0x8B7358, "Brown variety of Kota limestone.", .india),
        m("Kadappa Stone", .stone, 0x2E3336, "Black Cuddapah limestone slab from Andhra Pradesh.", .india),
        m("Shahabad Stone", .stone, 0x9D9A8E, "Grey limestone flooring slab from Karnataka.", .india),
        m("Tandur Stone", .stone, 0xA79F8A, "Yellow-grey limestone flooring slab from Telangana.", .india),
        m("Jaisalmer Stone", .stone, 0xD8B36A, "Golden-yellow limestone from Rajasthan.", .india),
        m("Dholpur Stone", .stone, 0xD6B89A, "Pinkish-beige sandstone from Rajasthan.", .india),
        m("Sandstone, Red", .stone, 0xA4553E, "Red sandstone.", .india),
        m("Sandstone, Buff", .stone, 0xD6C094, "Buff sandstone."),
        m("Sandstone, Grey", .stone, 0xA8A399, "Grey sandstone."),
        m("Slate, Grey", .stone, 0x55595E, "Grey slate slabs and tiles."),
        m("Slate, Green", .stone, 0x5C6B5E, "Green slate."),
        m("Slate Roofing", .stone, 0x4B5057, "Natural slate roof tiles."),
        m("Quartzite", .stone, 0xC9C3B8, "Hard metamorphic quartz sandstone."),
        m("Basalt", .stone, 0x44474A, "Dark volcanic stone."),
        m("Bluestone", .stone, 0x5E6770, "Blue-grey sandstone flagging.", .northAmerica),
        m("Fieldstone", .stone, 0x8F8778, "Rounded natural stone gathered from fields."),
        m("Flint", .stone, 0x5F5B55, "Knapped flint walling.", .europe),
        m("Stone Veneer, Manufactured", .stone, 0x9C9185, "Cast stone veneer units."),
        m("Stone, Random Rubble", .stone, 0x8C8273, "Uncoursed rubble stone masonry."),
        m("Engineered Quartz", .stone, 0xE8E6E1, "Quartz-resin composite slab for counters."),
        m("Soapstone", .stone, 0x6B6F6C, "Soft grey steatite."),
        m("Onyx", .stone, 0xE8DCC0, "Translucent banded onyx.", t: 0.1),
        m("Cobblestone, Granite", .stone, 0x77746F, "Granite setts and cobbles."),
        m("Flagstone", .stone, 0x9C9383, "Split stone paving flags."),
        m("Rock, Boulder", .stone, 0x8A857C, "Landscape boulders."),
        m("River Rock", .stone, 0x9B938A, "Rounded river stones for ballast and landscape."),
    ]

    // MARK: Metals

    static let metals: [LibraryMaterial] = [
        m("Steel", .metal, 0x7D8389, "Carbon steel."),
        m("Steel, Structural", .metal, 0x6F757B, "Hot-rolled structural steel sections."),
        m("Steel, Stainless Brushed", .metal, 0xB4B8BB, "Brushed stainless steel."),
        m("Steel, Stainless Polished", .metal, 0xC9CDD0, "Mirror-polished stainless steel."),
        m("Steel, Galvanized", .metal, 0xA3A9AE, "Hot-dip galvanized steel."),
        m("Steel, Weathering", .metal, 0x8A4B2A, "Weathering steel with a stable rust patina."),
        m("Steel, Painted Black", .metal, 0x2A2B2D, "Steel with a black paint finish."),
        m("Steel, Painted White", .metal, 0xE9E9E6, "Steel with a white paint finish."),
        m("Steel Decking", .metal, 0x9AA0A6, "Galvanized profiled steel floor or roof deck."),
        m("Metal Stud", .metal, 0xA9AEB2, "Cold-formed galvanized steel studs and furring."),
        m("Aluminum", .metal, 0xB9BEC4, "Aluminum."),
        m("Aluminum, Anodized Clear", .metal, 0xC6CACD, "Clear anodized aluminum."),
        m("Aluminum, Anodized Bronze", .metal, 0x5B4636, "Dark bronze anodized aluminum."),
        m("Aluminum, Anodized Black", .metal, 0x2F2F31, "Black anodized aluminum."),
        m("Aluminum, Powder Coated White", .metal, 0xEEEEEA, "White powder-coated aluminum."),
        m("Aluminum, Powder Coated Grey", .metal, 0x6D7176, "Grey powder-coated aluminum."),
        m("Aluminum Composite Panel, Silver", .metal, 0xBFC3C7, "Aluminum skins bonded to a mineral core."),
        m("Aluminum Composite Panel, White", .metal, 0xEFEFEC, "White aluminum composite panel."),
        m("Zinc, Natural", .metal, 0x8F969C, "Rolled zinc sheet cladding and roofing.", .europe),
        m("Zinc, Pre-Weathered Graphite", .metal, 0x5B6066, "Dark pre-patinated zinc sheet.", .europe),
        m("Copper, New", .metal, 0xB8734A, "Bright rolled copper sheet."),
        m("Copper, Patina", .metal, 0x6FA38E, "Copper with a green patina."),
        m("Brass", .metal, 0xB59A55, "Brass."),
        m("Bronze", .metal, 0x7D5C3A, "Cast or architectural bronze."),
        m("Cast Iron", .metal, 0x3A3B3C, "Cast iron."),
        m("Wrought Iron", .metal, 0x2F3033, "Wrought or forged iron."),
        m("Lead", .metal, 0x707478, "Lead sheet flashing."),
        m("Titanium", .metal, 0x9B9FA3, "Titanium sheet."),
        m("Chrome", .metal, 0xD8DBDE, "Chrome-plated metal."),
        m("Gold Leaf", .metal, 0xC9A646, "Gold leaf gilding."),
        m("Metal Roofing", .metal, 0x5E666E, "Profiled metal roof sheeting."),
        m("Metal Roofing, Standing Seam Dark Grey", .metal, 0x4A5057, "Standing seam metal roofing, dark grey finish."),
        m("Corrugated Metal Sheet", .metal, 0x9CA3A9, "Corrugated galvanized steel sheet."),
        m("Metal Sheet, Zinc-Aluminum Coated", .metal, 0xB0B6BA, "Zinc-aluminum alloy coated steel sheet.", .india),
        m("Metal Panel, Insulated", .metal, 0xD2D5D8, "Foam-core insulated metal wall or roof panel."),
        m("Perforated Metal Panel", .metal, 0x9EA3A7, "Perforated aluminum or steel screen.", t: 0.3),
        m("Expanded Metal Mesh", .metal, 0x8E9398, "Expanded steel mesh.", t: 0.4),
        m("Metal Mesh, Woven Stainless", .metal, 0xA7ABAF, "Woven stainless steel architectural mesh.", t: 0.35),
        m("Raised Access Floor Panel", .metal, 0xB9BCBE, "Steel-encased raised floor panel."),
        m("Metal Ceiling Panel", .metal, 0xE8E9E7, "Perforated metal lay-in or clip-in ceiling panel."),
    ]

    // MARK: Wood

    static let woods: [LibraryMaterial] = [
        m("Timber Stud", .wood, 0xCFA774, "Softwood framing timber."),
        m("Wood - Dimensional Lumber", .wood, 0xD2B07E, "Kiln-dried softwood framing lumber.", .northAmerica),
        m("Wood - Pressure Treated", .wood, 0xA69770, "Preservative-treated lumber for sill plates and decks.", .northAmerica),
        m("Timber Cladding", .wood, 0x9C7650, "Exterior timber boards."),
        m("Wood Siding, Cedar Lap", .wood, 0xA56A45, "Cedar bevel siding.", .northAmerica),
        m("Wood Siding, Painted White", .wood, 0xEEEDE8, "Painted wood lap siding.", .northAmerica),
        m("Timber Cladding, Charred", .wood, 0x222021, "Surface-charred timber cladding.", .eastAsia),
        m("Timber Cladding, Thermally Modified", .wood, 0x7A5638, "Heat-treated durable timber cladding.", .europe),
        m("Oak Flooring", .wood, 0xB88A5A, "Solid oak floorboards."),
        m("Hardwood", .wood, 0x8F6440, "General hardwood."),
        m("Softwood, Pine", .wood, 0xDDBB85, "Pine."),
        m("Softwood, Douglas Fir", .wood, 0xC9955E, "Douglas fir."),
        m("Softwood, Spruce", .wood, 0xE3C99A, "Spruce."),
        m("Softwood, Larch", .wood, 0xC48A5A, "Larch."),
        m("Softwood, Western Red Cedar", .wood, 0xA8653F, "Western red cedar."),
        m("Softwood, Cypress", .wood, 0xD2B48A, "Cypress."),
        m("Hardwood, Oak White", .wood, 0xC9A574, "White oak."),
        m("Hardwood, Oak Red", .wood, 0xB9805A, "Red oak."),
        m("Hardwood, Maple", .wood, 0xE3C8A0, "Hard maple."),
        m("Hardwood, Cherry", .wood, 0xA0583A, "Cherry."),
        m("Hardwood, Walnut", .wood, 0x5E3F2A, "Walnut."),
        m("Hardwood, Ash", .wood, 0xD9C19A, "Ash."),
        m("Hardwood, Beech", .wood, 0xD9B38A, "Beech."),
        m("Hardwood, Birch", .wood, 0xE6CFA6, "Birch."),
        m("Hardwood, Mahogany", .wood, 0x7E3B28, "Mahogany."),
        m("Hardwood, Teak", .wood, 0xA8743F, "Teak, for joinery, doors and decks.", .india),
        m("Hardwood, Sal", .wood, 0x8C5E3C, "Sal, a dense structural hardwood for frames and rafters.", .india),
        m("Hardwood, Sheesham", .wood, 0x6B4028, "Sheesham (Indian rosewood) for furniture and joinery.", .india),
        m("Hardwood, Rosewood", .wood, 0x4C2A1C, "Rosewood."),
        m("Hardwood, Mango", .wood, 0xB89468, "Mango wood.", .india),
        m("Hardwood, Acacia", .wood, 0xA7753F, "Acacia."),
        m("Hardwood, Iroko", .wood, 0x9A6B3A, "Iroko.", .middleEastAfrica),
        m("Hardwood, Jarrah", .wood, 0x7A3526, "Jarrah.", .oceania),
        m("Hardwood, Ipe", .wood, 0x6A4A2E, "Ipe, for exterior decking.", .latinAmerica),
        m("Hardwood, Meranti", .wood, 0xA2644A, "Meranti.", .eastAsia),
        m("Hardwood, Rubberwood", .wood, 0xE0C49C, "Rubberwood.", .eastAsia),
        m("Hardwood, Hinoki", .wood, 0xE6D2A8, "Japanese cypress.", .eastAsia),
        m("Wood Decking, Hardwood", .wood, 0x8A5A3A, "Hardwood deck boards."),
        m("Wood Shingles, Cedar", .wood, 0x9B6A45, "Sawn cedar shingles."),
        m("Wood Shake Roofing", .wood, 0x8B6A4A, "Split wood shakes."),
        m("Wood - Flush Door Veneer", .wood, 0xC59C6C, "Veneered flush door leaf."),
        m("Wood Paneling, Oak Slats", .wood, 0xB88B58, "Oak slat wall and ceiling lining."),
        m("Cork", .wood, 0xB38B5E, "Cork board and tiles."),
        m("Cork Flooring", .wood, 0xB08A5E, "Cork floor tiles."),
        m("Bamboo, Natural", .wood, 0xD4B570, "Round bamboo poles and split bamboo.", .eastAsia),
        m("Bamboo, Strand-Woven", .wood, 0x9C6B3C, "Compressed strand-woven bamboo flooring.", .eastAsia),
        m("Bamboo, Carbonized", .wood, 0xB0834E, "Steam-darkened bamboo flooring.", .eastAsia),
        m("Rattan", .wood, 0xC49A5A, "Rattan cane.", .eastAsia),
        m("Thatch", .wood, 0xB39A5E, "Reed or straw thatch."),
    ]

    static let engineeredWood: [LibraryMaterial] = [
        m("Cross-Laminated Timber (CLT)", .wood, 0xDDBE8C, "Mass timber panels of crosswise glued lamellae."),
        m("Glued-Laminated Timber (Glulam)", .wood, 0xD6AE78, "Glued laminated beams and columns."),
        m("Laminated Veneer Lumber (LVL)", .wood, 0xD9B37C, "Parallel veneers glued into beams and headers."),
        m("Parallel Strand Lumber (PSL)", .wood, 0xB88E56, "Long veneer strands glued into columns and beams."),
        m("Laminated Strand Lumber (LSL)", .wood, 0xC9A46B, "Flaked-strand structural lumber."),
        m("Wood I-Joist", .wood, 0xD0AE7A, "Prefabricated I-joist with OSB web."),
        m("Plywood", .wood, 0xD8B383, "Structural plywood sheathing."),
        m("Plywood, Marine", .wood, 0xC49A68, "Marine-grade plywood."),
        m("Plywood, Birch", .wood, 0xE4CFA8, "Birch-faced plywood for joinery."),
        m("Oriented Strand Board (OSB)", .wood, 0xC9A165, "OSB sheathing and subfloor."),
        m("Medium-Density Fiberboard (MDF)", .wood, 0xB08C62, "MDF for joinery and trim."),
        m("High-Density Fiberboard (HDF)", .wood, 0x9A7650, "HDF core board."),
        m("Particleboard", .wood, 0xC7AA80, "Particleboard."),
        m("Hardboard", .wood, 0x8C6A48, "Hardboard."),
        m("Blockboard", .wood, 0xCBA877, "Softwood strips between veneers, for doors and shutters.", .india),
        m("Wood Veneer, Oak", .wood, 0xC19A6B, "Oak veneer."),
        m("Wood Veneer, Walnut", .wood, 0x6B4A33, "Walnut veneer."),
        m("Engineered Wood Flooring", .wood, 0xB98E5E, "Hardwood wear layer on a plywood core."),
        m("Parquet, Oak", .wood, 0xB78655, "Oak parquet blocks."),
    ]

    // MARK: Glass

    static let glass: [LibraryMaterial] = [
        m("Glass", .glass, 0x9FC4D6, "Glazing.", t: 0.7),
        m("Glass, Clear Float", .glass, 0xC9DEE6, "Clear float glass.", t: 0.85),
        m("Glass, Low-E Insulated", .glass, 0x9DBFCB, "Double-glazed insulating unit with low-emissivity coating.", t: 0.7),
        m("Glass, Triple Glazed", .glass, 0x8FB3C0, "Triple-glazed insulating unit.", t: 0.65),
        m("Glass, Tinted Grey", .glass, 0x5E6A70, "Grey body-tinted glass.", t: 0.5),
        m("Glass, Tinted Bronze", .glass, 0x7A6450, "Bronze body-tinted glass.", t: 0.5),
        m("Glass, Tinted Green", .glass, 0x6FA08E, "Green body-tinted glass.", t: 0.55),
        m("Glass, Tinted Blue", .glass, 0x5C85A8, "Blue body-tinted glass.", t: 0.55),
        m("Glass, Reflective Silver", .glass, 0x8C9AA4, "Reflective coated glass.", t: 0.3),
        m("Glass, Frosted", .glass, 0xE3EAEC, "Acid-etched or sandblasted glass.", t: 0.35),
        m("Glass, Laminated Safety", .glass, 0xB8D3DC, "Laminated safety glass.", t: 0.75),
        m("Glass, Tempered", .glass, 0xBDD6DF, "Toughened safety glass.", t: 0.8),
        m("Glass, Fire-Rated", .glass, 0xB5CFD8, "Fire-resistant glazing.", t: 0.7),
        m("Glass, Wired", .glass, 0xA9C0C8, "Glass with embedded wire mesh.", t: 0.6),
        m("Glass, Patterned", .glass, 0xD5E1E4, "Rolled obscure patterned glass.", t: 0.45),
        m("Glass, Ceramic Frit", .glass, 0xC5D2D6, "Glass with a printed ceramic frit.", t: 0.5),
        m("Glass, Back-Painted White", .glass, 0xF1F1EE, "Opaque back-painted glass."),
        m("Glass, Back-Painted Black", .glass, 0x1E1F21, "Opaque back-painted glass (spandrel)."),
        m("Glass Block", .glass, 0xC7DDE3, "Hollow glass block.", t: 0.5),
        m("Channel Glass", .glass, 0xD0E2E4, "U-profile cast glass channels.", t: 0.45),
        m("Mirror", .glass, 0xD4DADD, "Silvered mirror glass."),
        m("Mosaic Tile, Glass Blue", .glass, 0x3F7FA6, "Glass mosaic tile for pools and feature walls."),
    ]

    // MARK: Gypsum and plasters

    static let plasters: [LibraryMaterial] = [
        m("Plasterboard", .plaster, 0xEEEBE4, "Gypsum plasterboard."),
        m("Plaster", .plaster, 0xF1EEE8, "Wall plaster."),
        m("Gypsum Wall Board", .plaster, 0xEDEAE3, "Gypsum wallboard.", .northAmerica),
        m("Gypsum Wall Board, Type X", .plaster, 0xE9E6E0, "Fire-resistant gypsum wallboard.", .northAmerica),
        m("Gypsum Wall Board, Moisture-Resistant", .plaster, 0xD9E3D2, "Moisture-resistant gypsum board."),
        m("Gypsum Board, Abuse-Resistant", .plaster, 0xE5E2DC, "High-impact gypsum board."),
        m("Gypsum Shaftliner", .plaster, 0xE4E1DA, "Thick fire-rated gypsum core board for shaft walls.", .northAmerica),
        m("Gypsum Sheathing", .plaster, 0xD9C77E, "Glass-mat gypsum exterior sheathing."),
        m("Cement Board", .plaster, 0xC9C6BE, "Cementitious backer board for tile."),
        m("Gypsum Plaster", .plaster, 0xF3F0EA, "Gypsum finish plaster."),
        m("Plaster of Paris (POP)", .plaster, 0xF6F4EF, "Plaster of Paris for false ceilings and punning.", .india),
        m("Lime Plaster", .plaster, 0xEFE9DC, "Lime-based plaster."),
        m("Cement Plaster", .plaster, 0xCAC5BB, "Cement-sand plaster (render).", .india),
        m("Cement Plaster, Sand-Faced", .plaster, 0xC4BBA9, "Textured sand-faced cement plaster.", .india),
        m("Stucco, Portland Cement", .plaster, 0xE3DCCB, "Three-coat Portland cement stucco.", .northAmerica),
        m("Stucco, Textured White", .plaster, 0xF0ECE3, "Textured white stucco finish."),
        m("Render, Silicone Coloured", .plaster, 0xE8DFCF, "Thin-coat silicone render.", .europe),
        m("EIFS Finish", .plaster, 0xE6DECF, "Exterior insulation and finish system base and finish coats."),
        m("Veneer Plaster", .plaster, 0xF2EFE9, "Thin-coat veneer plaster."),
        m("Venetian Plaster", .plaster, 0xE6DFD2, "Polished lime plaster."),
        m("Clay Plaster", .plaster, 0xC9A887, "Natural clay plaster."),
        m("Tadelakt", .plaster, 0xD7C3A6, "Burnished waterproof lime plaster.", .middleEastAfrica),
        m("Acoustic Plaster", .plaster, 0xF4F2EE, "Seamless sound-absorbing plaster."),
        m("Acoustic Ceiling Tile", .plaster, 0xF4F2EE, "Lay-in acoustic ceiling tile."),
        m("Acoustic Ceiling Tile, Fine Fissured", .plaster, 0xF2F0EB, "Fine-fissured mineral fibre ceiling tile."),
        m("Acoustic Panel, Mineral Fiber", .plaster, 0xF0EEE8, "Mineral fibre acoustic panel."),
        m("Gypsum Ceiling Tile, Vinyl Faced", .plaster, 0xF5F4F0, "Washable vinyl-faced gypsum ceiling tile."),
        m("Wood Wool Acoustic Panel", .plaster, 0xCDB590, "Cement-bonded wood wool panel."),
        m("Gypsum Block", .plaster, 0xEDEAE4, "Solid gypsum partition block."),
    ]

    // MARK: Insulation

    static let insulation: [LibraryMaterial] = [
        m("Rigid Insulation", .insulation, 0xE7D57C, "Rigid board insulation."),
        m("Mineral Wool", .insulation, 0xE9DFA8, "Mineral wool insulation."),
        m("Batt Insulation, Fiberglass", .insulation, 0xEBD27E, "Glass fibre batts between studs and joists.", .northAmerica),
        m("Batt Insulation, Mineral Wool", .insulation, 0xC9B38A, "Stone wool batts."),
        m("Rigid Insulation, XPS", .insulation, 0x9CC3DD, "Extruded polystyrene board."),
        m("Rigid Insulation, EPS", .insulation, 0xF3F1EA, "Expanded polystyrene board."),
        m("Rigid Insulation, Polyiso", .insulation, 0xD6D8DA, "Foil-faced polyisocyanurate board."),
        m("Rigid Insulation, PIR", .insulation, 0xE8D8A2, "Polyisocyanurate board.", .europe),
        m("Spray Foam, Closed Cell", .insulation, 0xE8D596, "Closed-cell spray polyurethane foam."),
        m("Spray Foam, Open Cell", .insulation, 0xF0E6C2, "Open-cell spray polyurethane foam."),
        m("Cellulose, Loose Fill", .insulation, 0xA7A39A, "Blown recycled cellulose."),
        m("Wood Fibre Board", .insulation, 0xB08A5C, "Wood fibre insulation board.", .europe),
        m("Sheep's Wool", .insulation, 0xE7E1D2, "Sheep's wool insulation batts."),
        m("Cork Insulation Board", .insulation, 0x7E5A3A, "Expanded cork board."),
        m("Hempcrete", .insulation, 0xC8BE9F, "Hemp shiv and lime binder."),
        m("Aerogel Blanket", .insulation, 0xD9DEE3, "Aerogel insulation blanket."),
        m("Perlite, Expanded", .insulation, 0xEDEDE8, "Expanded perlite fill."),
        m("Vermiculite", .insulation, 0xB8A36E, "Exfoliated vermiculite fill."),
        m("Glass Wool", .insulation, 0xE6CF7E, "Glass wool rolls and slabs.", .india),
        m("Rock Wool Slab", .insulation, 0xC4A870, "Dense rock wool slab."),
        m("Reflective Foil Insulation", .insulation, 0xC9CDD1, "Foil-faced bubble or foam insulation."),
        m("Air Space", .gas, 0xF2F6F8, "Unventilated air cavity.", t: 0.9),
        m("Air Gap, Ventilated", .gas, 0xEEF3F6, "Ventilated rainscreen cavity.", t: 0.9),
    ]

    // MARK: Membranes and roofing

    static let membranesAndRoofing: [LibraryMaterial] = [
        m("Membrane", .plastic, 0x3C3C3C, "Waterproofing membrane."),
        m("Vapor Retarder, Polyethylene", .plastic, 0xE6E9EB, "Polyethylene vapor retarder sheet.", t: 0.3),
        m("Weather-Resistive Barrier", .plastic, 0xE8ECEF, "Breathable house wrap / sheathing membrane."),
        m("Building Paper, Asphalt Felt", .plastic, 0x3A3632, "Asphalt-saturated felt underlayment."),
        m("Bituminous Membrane", .plastic, 0x2C2C2E, "Modified bitumen roofing membrane."),
        m("EPDM Membrane", .plastic, 0x232325, "EPDM rubber roofing membrane."),
        m("TPO Membrane, White", .plastic, 0xF2F2EF, "White thermoplastic polyolefin roofing membrane."),
        m("PVC Roofing Membrane", .plastic, 0xE8EAEB, "PVC single-ply roofing membrane."),
        m("Liquid-Applied Waterproofing", .plastic, 0x4A4C50, "Fluid-applied waterproofing."),
        m("Self-Adhered Flashing", .plastic, 0x3E3F42, "Self-adhered flashing membrane."),
        m("Damp-Proof Course", .plastic, 0x2F3033, "Damp-proof course / membrane."),
        m("Drainage Mat", .plastic, 0x2F3136, "Dimpled drainage and protection board."),
        m("Root Barrier", .plastic, 0x3B3F3A, "Root-resistant membrane for planted roofs."),
        m("Geotextile Fabric", .plastic, 0xDCDCD6, "Non-woven filter fabric."),
        m("Bentonite Waterproofing", .earth, 0x6A5C4A, "Bentonite clay waterproofing panels."),
        m("Asphalt Shingles, Charcoal", .generic, 0x3F4042, "Laminated asphalt roof shingles.", .northAmerica),
        m("Asphalt Shingles, Weathered Wood", .generic, 0x6E6254, "Laminated asphalt shingles, brown blend.", .northAmerica),
        m("Asphalt Shingles, Slate Grey", .generic, 0x5A5F64, "Laminated asphalt shingles, grey blend.", .northAmerica),
        m("Clay Roof Tile", .ceramic, 0x8F4B36, "Fired clay roof tile."),
        m("Clay Roof Tile, Barrel", .ceramic, 0xB5603E, "Half-round clay barrel tile."),
        m("Mangalore Tile", .ceramic, 0xA6503A, "Interlocking clay roof tile of the Mangalore pattern.", .india),
        m("Polycarbonate Roofing Sheet", .plastic, 0xDDE8EB, "Corrugated clear polycarbonate roofing.", t: 0.6),
    ]

    // MARK: Ceramics

    static let ceramics: [LibraryMaterial] = [
        m("Ceramic Tile", .ceramic, 0xDDD8CF, "Glazed ceramic tile."),
        m("Ceramic Tile, White Glazed", .ceramic, 0xF3F2EE, "White glazed wall tile."),
        m("Ceramic Tile, Beige", .ceramic, 0xD8CBB4, "Beige ceramic floor tile."),
        m("Ceramic Tile, Anti-Skid", .ceramic, 0xB3AEA6, "Slip-resistant matt ceramic floor tile.", .india),
        m("Porcelain Tile, Grey", .ceramic, 0xA5A39F, "Through-body porcelain tile."),
        m("Porcelain Tile, Wood-Look", .ceramic, 0xA37C58, "Plank-format porcelain tile with a wood print."),
        m("Porcelain Tile, Stone-Look Large Format", .ceramic, 0xD4CEC4, "Large-format porcelain slab."),
        m("Porcelain Stoneware, Anthracite", .ceramic, 0x3E4043, "Dark porcelain stoneware."),
        m("Vitrified Tile, Double Charged", .ceramic, 0xE2DDD3, "Double-charged vitrified floor tile.", .india),
        m("Vitrified Tile, Glazed", .ceramic, 0xD5CCBE, "Glazed vitrified tile.", .india),
        m("Quarry Tile", .ceramic, 0x9B4E36, "Unglazed extruded clay tile."),
        m("Terracotta Tile", .ceramic, 0xB8653F, "Unglazed terracotta floor tile."),
        m("Mosaic Tile, Ceramic White", .ceramic, 0xEDEDEA, "Small-format ceramic mosaic."),
        m("Subway Tile, White", .ceramic, 0xF5F4F0, "Glazed 3x6 wall tile."),
        m("Zellige Tile, Green", .ceramic, 0x2E6B5A, "Hand-cut glazed terracotta tile.", .middleEastAfrica),
        m("Azulejo Tile, Blue and White", .ceramic, 0x5E7FAE, "Painted tin-glazed tile.", .europe),
        m("Sanitaryware, Vitreous China", .ceramic, 0xF4F4F2, "Vitreous china for WCs and basins."),
        m("Brick Tile Cladding", .ceramic, 0xA65B42, "Thin clay brick slips."),
        m("Terracotta Cladding Panel", .ceramic, 0xC0714B, "Extruded terracotta rainscreen panel."),
        m("Terracotta Jaali", .ceramic, 0xB86844, "Perforated terracotta screen blocks.", .india, t: 0.25),
        m("Clay Pavers", .ceramic, 0xA2553F, "Fired clay paving bricks."),
    ]

    // MARK: Floor and wall finishes

    static let floorAndWallFinishes: [LibraryMaterial] = [
        m("Laminate", .plastic, 0xD9D2C6, "Laminate flooring."),
        m("Epoxy Floor Coating, Grey", .plastic, 0x8E959B, "Seamless epoxy floor coating."),
        m("Epoxy Floor Coating, Light Grey", .plastic, 0xB8BDC0, "Seamless light epoxy floor coating."),
        m("Polyurethane Screed", .plastic, 0x9CA1A5, "Heavy-duty polyurethane cement screed."),
        m("Vinyl Sheet Flooring", .plastic, 0xC7C1B6, "Homogeneous vinyl sheet flooring."),
        m("Luxury Vinyl Tile, Oak", .plastic, 0xB3895F, "Luxury vinyl plank with an oak print."),
        m("Vinyl Composition Tile", .plastic, 0xD9D6CF, "Vinyl composition tile (VCT).", .northAmerica),
        m("Rubber Flooring, Black", .plastic, 0x2D2E30, "Rubber sheet or tile flooring."),
        m("Linoleum, Natural", .plastic, 0xC3A77B, "Linseed oil linoleum."),
        m("Linoleum, Blue", .plastic, 0x4F6E8E, "Blue linoleum."),
        m("Carpet Tile, Charcoal", .generic, 0x4A4B4E, "Modular carpet tile."),
        m("Carpet, Broadloom Beige", .generic, 0xB8A88E, "Broadloom carpet."),
        m("Carpet, Blue", .generic, 0x3E4F6C, "Blue carpet."),
        m("Sisal Matting", .generic, 0xC7B084, "Natural sisal floor covering."),
        m("Coir Matting", .generic, 0x9C7446, "Coconut fibre matting.", .india),
        m("Wallpaper, Vinyl Neutral", .plastic, 0xE2DACB, "Vinyl wallcovering."),
        m("Wallpaper, Patterned Green", .plastic, 0x8FA68A, "Patterned paper wallcovering."),
        m("Fabric Wall Panel, Grey", .generic, 0x8C8E91, "Fabric-wrapped acoustic wall panel."),
        m("Acoustic Felt Panel", .generic, 0x6F7478, "PET felt acoustic panel."),
        m("Fabric, Upholstery Grey", .generic, 0x7B7E82, "Upholstery fabric."),
        m("Leather, Tan", .generic, 0x8C5A35, "Leather."),
    ]

    // MARK: Paints

    static let paints: [LibraryMaterial] = [
        m("Paint - White", .paint, 0xF7F6F2, "White emulsion paint."),
        m("Paint - Off-White", .paint, 0xF2EEE3, "Off-white paint."),
        m("Paint - Warm White", .paint, 0xF4EDDD, "Warm white paint."),
        m("Paint - Ivory", .paint, 0xF1E7CF, "Ivory paint."),
        m("Paint - Light Grey", .paint, 0xD3D3D0, "Light grey paint."),
        m("Paint - Mid Grey", .paint, 0x9C9C99, "Mid grey paint."),
        m("Paint - Charcoal", .paint, 0x3D3F42, "Charcoal paint."),
        m("Paint - Black", .paint, 0x1E1E1F, "Black paint."),
        m("Paint - Beige", .paint, 0xD9C9AC, "Beige paint."),
        m("Paint - Sand", .paint, 0xD8C49C, "Sand paint."),
        m("Paint - Terracotta", .paint, 0xB45F43, "Terracotta paint."),
        m("Paint - Brick Red", .paint, 0x8C3A2E, "Brick red paint."),
        m("Paint - Yellow Ochre", .paint, 0xCFA045, "Yellow ochre paint."),
        m("Paint - Lemon", .paint, 0xF1DE6F, "Lemon yellow paint."),
        m("Paint - Sage Green", .paint, 0x9BAA8C, "Sage green paint."),
        m("Paint - Olive", .paint, 0x6C7043, "Olive paint."),
        m("Paint - Forest Green", .paint, 0x2F5241, "Forest green paint."),
        m("Paint - Mint", .paint, 0xBFE0CD, "Mint paint."),
        m("Paint - Sky Blue", .paint, 0xA9C9E3, "Sky blue paint."),
        m("Paint - Navy", .paint, 0x24344F, "Navy paint."),
        m("Paint - Teal", .paint, 0x2E7272, "Teal paint."),
        m("Paint - Lavender", .paint, 0xC3B6D6, "Lavender paint."),
        m("Paint - Blush Pink", .paint, 0xE8C4BE, "Blush pink paint."),
        m("Paint - Safety Yellow", .paint, 0xF2C318, "Safety yellow marking paint."),
        m("Paint - Safety Red", .paint, 0xC22E27, "Safety red paint."),
        m("Paint - Exterior Masonry White", .paint, 0xF2F0EA, "Exterior masonry paint."),
        m("Paint - Distemper", .paint, 0xEEE9DD, "Water-based distemper finish.", .india),
        m("Paint - Lime Wash", .paint, 0xF0ECE0, "Traditional lime wash."),
        m("Paint - Enamel Grey", .paint, 0x7C8084, "Grey enamel for metalwork."),
        m("Paint - Intumescent", .paint, 0xE7E6E2, "Fire-protective intumescent coating."),
    ]

    // MARK: Cladding, composites and plastics

    static let claddingAndPlastics: [LibraryMaterial] = [
        m("Vinyl Siding, White", .plastic, 0xF0EFEA, "Vinyl lap siding.", .northAmerica),
        m("Vinyl Siding, Clay", .plastic, 0xCDBFA5, "Clay-coloured vinyl siding.", .northAmerica),
        m("HPL Cladding Panel", .plastic, 0x7C7F82, "High-pressure laminate façade panel."),
        m("Plastic Laminate, White", .plastic, 0xF3F3F0, "High-pressure plastic laminate for casework."),
        m("Melamine Faced Board", .plastic, 0xECEAE4, "Melamine-faced particleboard."),
        m("Solid Surface, White", .plastic, 0xF1F0EC, "Acrylic solid surface."),
        m("WPC Decking", .plastic, 0x7D6450, "Wood-plastic composite decking."),
        m("WPC Board", .plastic, 0xC9B59A, "Wood-plastic composite board for doors and frames.", .india),
        m("Polycarbonate, Multiwall Clear", .plastic, 0xDCE8EC, "Multiwall polycarbonate sheet.", t: 0.65),
        m("Polycarbonate, Opal", .plastic, 0xF0F2F2, "Opal diffusing polycarbonate.", t: 0.4),
        m("Acrylic Sheet, Clear", .plastic, 0xE3EEF1, "Clear acrylic sheet.", t: 0.85),
        m("ETFE Foil", .plastic, 0xE4EEF2, "ETFE foil cushions.", t: 0.8),
        m("PTFE Fabric Membrane", .plastic, 0xF4F2EA, "PTFE-coated glass fibre tensile fabric.", t: 0.35),
        m("Fiberglass Reinforced Panel", .plastic, 0xEFEDE6, "FRP wall lining for wet and hygienic areas."),
        m("PVC, White", .plastic, 0xF0F0EE, "Rigid PVC."),
        m("uPVC Frame, White", .plastic, 0xF2F2EF, "Unplasticised PVC window and door frames."),
        m("HDPE, Black", .plastic, 0x2B2C2E, "High-density polyethylene."),
        m("Artificial Turf", .plastic, 0x4E8C3A, "Synthetic grass."),
        m("Rubber Mulch", .plastic, 0x6A3A2E, "Recycled rubber play surface."),
        m("Resin-Bound Gravel", .plastic, 0xC0A77E, "Resin-bound aggregate paving."),
    ]

    // MARK: Traditional and regional

    static let traditional: [LibraryMaterial] = [
        m("Shoji Paper", .generic, 0xF3EEDF, "Translucent washi paper for sliding screens.", .eastAsia, t: 0.35),
        m("Tatami", .generic, 0xC9BC86, "Woven rush-covered floor mat.", .eastAsia),
        m("Bamboo Matting", .wood, 0xC9A868, "Woven bamboo mat panels.", .eastAsia),
        m("Rammed Earth", .earth, 0xB08A62, "Compacted earth walls."),
        m("Adobe", .earth, 0xB48B64, "Sun-dried mud brick.", .latinAmerica),
        m("Cob", .earth, 0xA88560, "Earth, straw and water walling.", .europe),
        m("Compressed Stabilized Earth Block", .earth, 0xA9785A, "Pressed earth block stabilized with cement or lime.", .india),
        m("Earth Plaster", .earth, 0x9E7A58, "Mud plaster.", .india),
    ]

    // MARK: Earth, site and landscape

    static let site: [LibraryMaterial] = [
        m("Earth", .earth, 0x8A7556, "Undisturbed soil."),
        m("Soil, Topsoil", .earth, 0x5E4A36, "Topsoil."),
        m("Soil, Clay", .earth, 0x8E6547, "Clay soil."),
        m("Soil, Sandy", .earth, 0xC8AE84, "Sandy soil."),
        m("Planting Soil", .earth, 0x5A4632, "Engineered planting substrate for planters and green roofs."),
        m("Sand", .earth, 0xD8C7A0, "Sand fill and bedding."),
        m("Gravel", .earth, 0x9E978C, "Gravel."),
        m("Gravel, Pea", .earth, 0xB0A28C, "Rounded pea gravel."),
        m("Crushed Stone Aggregate", .earth, 0x8F8B85, "Compacted crushed stone base course."),
        m("Hardcore Fill", .earth, 0x7F7A72, "Compacted broken stone or brick soling."),
        m("Decomposed Granite", .earth, 0xC2A57B, "Stabilized decomposed granite paths."),
        m("Grass", .earth, 0x6D8F45, "Lawn."),
        m("Grass, Dry", .earth, 0xA69B5A, "Dry grass."),
        m("Mulch, Bark", .earth, 0x5A3D28, "Shredded bark mulch."),
        m("Asphalt Paving", .generic, 0x3A3B3D, "Asphalt concrete pavement."),
        m("Asphalt, Weathered", .generic, 0x57585A, "Aged asphalt pavement."),
        m("Water", .liquid, 0x4F8FB5, "Water.", t: 0.5),
        m("Water, Pool", .liquid, 0x5FB6CF, "Swimming pool water.", t: 0.45),
        m("Water, Pond", .liquid, 0x4C6E5E, "Pond water.", t: 0.35),
    ]
}
