import Foundation
import ArcusGeometry

// FM9: this batch's library pieces (see FurnitureLibrary.swift): the Top 25 essentials at high detail, plus the
// kitchen's wall and single-door base cabinets. Each is built with the kit (FurnitureLibraryKit) on the Furniture mode
// operations: real carcass construction (sides, tops, bottoms, backs, plinths, dividers, fixed and adjustable shelves),
// doors and drawers with their hinges, slides and handles, legs, aprons and stretchers, and upholstery as locked forms
// (crowned cushions with piping, arms, backs), in standard US sizes.

extension FurnitureLibrary {
    static var essentials: [FurnitureLibraryPiece] {
        [
            .init("Sofa", rooms: ["Living Room"], detail: .high, keywords: ["couch", "settee", "three seater", "upholstered", "linen"]) { Essentials.sofa() },
            .init("Coffee Table", rooms: ["Living Room"], detail: .high, keywords: ["cocktail table", "walnut", "low table"]) { Essentials.coffeeTable() },
            .init("TV Stand", rooms: ["Living Room"], detail: .high, keywords: ["media console", "credenza", "entertainment", "mid-century"]) { Essentials.tvStand() },
            .init("Armchair", rooms: ["Living Room"], detail: .high, keywords: ["club chair", "lounge chair", "upholstered", "accent"]) { Essentials.armchair() },
            .init("Side Table", rooms: ["Living Room"], detail: .high, keywords: ["end table", "lamp table", "drawer"]) { Essentials.sideTable() },
            .init("Bookshelf", rooms: ["Living Room"], category: .casework, detail: .high, keywords: ["bookcase", "shelves", "oak"]) { Essentials.bookshelf() },
            .init("Bed", rooms: ["Bedroom"], detail: .high, keywords: ["twin", "full", "queen", "king", "mattress", "headboard", "upholstered"]) { Essentials.bed() },
            .init("Bedside Table", rooms: ["Bedroom"], detail: .high, keywords: ["nightstand", "night table", "drawer", "walnut"]) { Essentials.bedsideTable() },
            .init("Wardrobe", rooms: ["Bedroom"], category: .casework, detail: .high, keywords: ["armoire", "closet", "hanging rod", "shaker"]) { Essentials.wardrobe() },
            .init("Dresser", rooms: ["Bedroom"], category: .casework, detail: .high, keywords: ["chest of drawers", "drawers", "mid-century", "walnut"]) { Essentials.dresser() },
            .init("Dressing Table", rooms: ["Bedroom"], detail: .high, keywords: ["vanity", "makeup table", "mirror"]) { Essentials.dressingTable() },
            .init("Dining Table", rooms: ["Dining Room"], detail: .high, keywords: ["kitchen table", "4 seat", "6 seat", "8 seat", "white oak"]) { Essentials.diningTable() },
            .init("Dining Chair", rooms: ["Dining Room"], detail: .high, keywords: ["side chair", "kitchen chair", "leather seat", "walnut"]) { Essentials.diningChair() },
            .init("Sideboard", rooms: ["Dining Room"], category: .casework, detail: .high, keywords: ["buffet", "credenza", "server", "walnut"]) { Essentials.sideboard() },
            .init("Kitchen Cabinet", rooms: ["Kitchen"], category: .casework, detail: .high, keywords: ["base cabinet", "lower cabinet", "drawer", "shaker"]) { Essentials.kitchenCabinet() },
            .init("Kitchen Base Cabinet - Single Door", rooms: ["Kitchen"], category: .casework, detail: .high,
                  keywords: ["base cabinet", "narrow", "12\"", "15\"", "18\""]) { Essentials.kitchenBaseSingle() },
            .init("Kitchen Wall Cabinet", rooms: ["Kitchen"], category: .casework, detail: .high, keywords: ["upper cabinet", "wall cabinet", "shaker"]) { Essentials.kitchenWallCabinet() },
            .init("Pantry Cabinet", rooms: ["Kitchen"], category: .casework, detail: .high, keywords: ["tall cabinet", "larder", "utility", "shelves"]) { Essentials.pantryCabinet() },
            .init("Study Desk", rooms: ["Home Office"], detail: .high, keywords: ["desk", "writing desk", "pedestal", "drawers"]) { Essentials.studyDesk() },
            .init("Office Chair", rooms: ["Home Office"], detail: .high, keywords: ["task chair", "swivel", "casters", "ergonomic", "mesh"]) { Essentials.officeChair() },
            .init("Storage Cabinet", rooms: ["Living Room", "Storage & Utility"], category: .casework, detail: .high,
                  keywords: ["cupboard", "linen cabinet", "doors", "drawers"]) { Essentials.storageCabinet() },
            .init("Shoe Rack", rooms: ["Living Room"], detail: .high, keywords: ["shoe shelf", "entry", "slatted", "bench"]) { Essentials.shoeRack() },
            .init("Entryway Bench", rooms: ["Entryway & Hallway"], detail: .high, keywords: ["mudroom bench", "cubbies", "cushion", "storage bench"]) { Essentials.entrywayBench() },
            .init("Bathroom Vanity", rooms: ["Bathroom"], category: .casework, detail: .high, keywords: ["sink", "vanity cabinet", "quartz", "faucet"]) { Essentials.bathroomVanity() },
            .init("Shelving Unit", rooms: ["Storage & Utility"], detail: .high, keywords: ["industrial", "steel", "etagere", "open shelves"]) { Essentials.shelvingUnit() },
            .init("Ottoman", rooms: ["Living Room"], detail: .high, keywords: ["footstool", "pouf", "tufted", "upholstered"]) { Essentials.ottoman() },
            .init("Console Table", rooms: ["Living Room"], detail: .high, keywords: ["sofa table", "hall table", "entry table", "drawer"]) { Essentials.consoleTable() },
        ]
    }
}

/// The essential pieces' builders.
enum Essentials {
    typealias Size = LibraryKit.Size

    // MARK: Shared types

    static let walnutLeg = "Walnut Tapered 1 3/4\""
    static let walnutTop = "1\" Solid Walnut Top"
    static let walnutPly = "3/4\" Walnut Veneer Plywood"
    static let oakPly = "3/4\" White Oak Veneer Plywood"
    static let whitePanel = "3/4\" Painted MDF (White)"

    /// Mid-century walnut: tapered round legs, a solid top with a round-over, walnut veneer plywood carcass, walnut
    /// slab fronts with brass knobs.
    static func walnut(_ k: LibraryBuilder) {
        k.legType(walnutLeg, shape: .round, width: 1.75, taper: 1, material: "Solid Walnut")
        k.shelfType(walnutTop, thickness: 1, material: "Solid Walnut", top: true, edgeShape: .roundOver)
        k.panelType(walnutPly, thickness: 0.75, material: "Walnut Veneer Plywood", face: "Walnut Veneer")
        k.shelfType("3/4\" Walnut Veneer Shelf", thickness: 0.75, material: "Walnut Veneer Plywood", face: "Walnut Veneer", edge: "Edge Banding")
        k.panelType("3/4\" Solid Walnut", thickness: 0.75, material: "Solid Walnut", edge: nil)
        k.frontType(.door, "Walnut Slab - Brass Knob", from: "Slab - Full Overlay", material: "Walnut Veneer Plywood", handle: (FurnitureHardware.knob, "1 1/2\" Brass"))
        k.frontType(.drawer, "Walnut Slab - Brass Knob", from: "Slab - Full Overlay", material: "Walnut Veneer Plywood", handle: (FurnitureHardware.knob, "1 1/2\" Brass"))
        k.frontType(.door, "Walnut Slab - Edge Pull", from: "Slab - Full Overlay", material: "Walnut Veneer Plywood", handle: (FurnitureHardware.edgePull, "4\""))
        k.frontType(.drawer, "Walnut Slab - Edge Pull", from: "Slab - Full Overlay", material: "Walnut Veneer Plywood", handle: (FurnitureHardware.edgePull, "4\""))
    }

    /// White oak: veneer plywood carcass and shelves.
    static func oak(_ k: LibraryBuilder) {
        k.panelType(oakPly, thickness: 0.75, material: "Oak Veneer Plywood", face: "Oak Veneer")
        k.shelfType("3/4\" Oak Veneer Shelf", thickness: 0.75, material: "Oak Veneer Plywood", face: "Oak Veneer", edge: "Edge Banding")
        k.shelfType("1\" Solid White Oak Top", thickness: 1, material: "Solid White Oak", top: true, edgeShape: .roundOver)
    }

    /// Painted Shaker: white painted carcass, Shaker doors and drawers with bar pulls.
    static func shaker(_ k: LibraryBuilder, pulls: String = "128 mm") {
        k.panelType(whitePanel, thickness: 0.75, material: "Painted MDF - White", edge: nil, grain: .none)
        k.shelfType("3/4\" Painted MDF Shelf (White)", thickness: 0.75, material: "Painted MDF - White", grain: .none)
        k.shelfType("3/4\" Painted MDF Top (White)", thickness: 0.75, material: "Painted MDF - White", top: true, edgeShape: .roundOver, grain: .none)
        k.frontType(.door, "Shaker White - Bar Pull", from: "Shaker - Full Overlay", material: "Painted MDF - White", panel: "Painted MDF - White",
                    handle: (FurnitureHardware.barPull, pulls))
        k.frontType(.door, "Shaker White Pair - Bar Pull", from: "Shaker - Full Overlay Pair", material: "Painted MDF - White", panel: "Painted MDF - White",
                    handle: (FurnitureHardware.barPull, pulls))
        k.frontType(.drawer, "Shaker White - Bar Pull", from: "Shaker - Full Overlay", material: "Painted MDF - White", panel: "Painted MDF - White",
                    handle: (FurnitureHardware.barPull, pulls), frame: 1.5)
        k.frontType(.drawer, "Slab White - Bar Pull", from: "Slab - Full Overlay", material: "Painted MDF - White", handle: (FurnitureHardware.barPull, pulls))
    }

    // MARK: Living Room

    static func sofa() -> BIMModel {
        LibraryKit.piece("Sofa", sizes: [Size("72\"", w: 72, d: 36, h: 34), Size("84\"", w: 84, d: 37, h: 34), Size("96\"", w: 96, d: 38, h: 34)],
                         description: "Three-seat track-arm sofa: hardwood frame, crowned seat and back cushions with piping, walnut legs") { k in
            walnut(k)
            try k.upholstered(UpholsteredSpec(fabric: "Fabric - Oatmeal Linen", seats: 3, seatHeight: 18, cushionThickness: 5, armWidth: 6, armHeight: 25,
                                              backThickness: 7, leg: walnutLeg, legHeight: 5, centerLegs: true, pillows: 2, pillowFabric: "Fabric - Sage Boucle"))
        }
    }

    static func armchair() -> BIMModel {
        LibraryKit.piece("Armchair", sizes: [Size("32\"", w: 32, d: 34, h: 33), Size("36\"", w: 36, d: 36, h: 34)],
                         description: "Track-arm club chair: hardwood frame, crowned seat cushion and back cushion, walnut legs") { k in
            walnut(k)
            try k.upholstered(UpholsteredSpec(fabric: "Fabric - Navy Velvet", seats: 1, seatHeight: 18, cushionThickness: 5, armWidth: 5.5, armHeight: 24,
                                              backThickness: 6.5, leg: walnutLeg, legHeight: 5))
        }
    }

    static func ottoman() -> BIMModel {
        LibraryKit.piece("Ottoman", sizes: [Size("Square 24\"", w: 24, d: 24, h: 17), Size("Square 30\"", w: 30, d: 30, h: 17), Size("Bench 40\"", w: 40, d: 22, h: 17)],
                         description: "Tufted upholstered ottoman on walnut legs, piped crowned top") { k in
            walnut(k)
            let u = try k.upholstered(UpholsteredSpec(fabric: "Leather - Cognac", seats: 1, seatHeight: 17, cushionThickness: 4, armWidth: 0, armHeight: 0,
                                                      backThickness: 0, backCushions: false, leg: walnutLeg, legHeight: 4))
            // Buttons tufting the top: a 2 x 2 grid of covered buttons.
            let top = 17.4
            for fx in [0.3, 0.7] {
                for fy in [0.3, 0.7] {
                    let x = u.seatX.lowerBound + (u.seatX.upperBound - u.seatX.lowerBound) * fx, y = u.seatY.lowerBound + (u.seatY.upperBound - u.seatY.lowerBound) * fy
                    try k.revolve(axis: Vec2(x, y), profile: [Vec2(0, 0), Vec2(0.45, 0), Vec2(0.5, 0.15), Vec2(0.35, 0.3), Vec2(0, 0.32)], z: top - 0.5,
                                  material: "Leather - Cognac", lock: .axes(x: .stretch, y: .stretch, z: .low))
                }
            }
        }
    }

    static func coffeeTable() -> BIMModel {
        LibraryKit.piece("Coffee Table", sizes: [Size("42\"", w: 42, d: 22, h: 17), Size("48\"", w: 48, d: 24, h: 18), Size("54\"", w: 54, d: 28, h: 18)],
                         description: "Solid walnut top with round-over edges, tapered legs, aprons and a lower shelf") { k in
            walnut(k)
            k.railType("3/4\" x 2 1/2\" Walnut Apron", width: 0.75, height: 2.5, material: "Solid Walnut")
            try k.table(TableSpec(top: walnutTop, leg: walnutLeg, legInset: 1.25, apron: "3/4\" x 2 1/2\" Walnut Apron", apronSetback: 0.375,
                                  shelf: (type: "3/4\" Walnut Veneer Shelf", height: 5)))
        }
    }

    static func sideTable() -> BIMModel {
        LibraryKit.piece("Side Table", sizes: [Size("18\"", w: 18, d: 18, h: 24), Size("22\"", w: 22, d: 22, h: 24)],
                         description: "Walnut side table with a drawer in the apron and a lower shelf") { k in
            walnut(k)
            k.railType("3/4\" x 4\" Walnut Apron", width: 0.75, height: 4, material: "Solid Walnut")
            k.frontType(.drawer, "Walnut Inset - Brass Knob", from: "Slab - Inset", material: "Solid Walnut", handle: (FurnitureHardware.knob, "1 1/2\" Brass"))
            try k.table(TableSpec(top: walnutTop, leg: walnutLeg, legInset: 0.75, apron: "3/4\" x 4\" Walnut Apron", apronSetback: 0.25,
                                  shelf: (type: "3/4\" Walnut Veneer Shelf", height: 6), drawer: (width: 10, height: 3, type: "Walnut Inset - Brass Knob"), drawerPanel: "3/4\" Solid Walnut"))
        }
    }

    static func consoleTable() -> BIMModel {
        LibraryKit.piece("Console Table", sizes: [Size("48\"", w: 48, d: 14, h: 30), Size("60\"", w: 60, d: 16, h: 30)],
                         description: "Slim walnut console with a centre drawer and a lower shelf") { k in
            walnut(k)
            k.railType("3/4\" x 4\" Walnut Apron", width: 0.75, height: 4, material: "Solid Walnut")
            k.legType("Walnut Square Tapered 1 1/2\"", shape: .square, width: 1.5, taper: 0.875, material: "Solid Walnut")
            k.frontType(.drawer, "Walnut Inset - Brass Knob", from: "Slab - Inset", material: "Solid Walnut", handle: (FurnitureHardware.knob, "1 1/2\" Brass"))
            try k.table(TableSpec(top: walnutTop, leg: "Walnut Square Tapered 1 1/2\"", legInset: 0.75, apron: "3/4\" x 4\" Walnut Apron", apronSetback: 0.25,
                                  shelf: (type: "3/4\" Walnut Veneer Shelf", height: 8), drawer: (width: 18, height: 3, type: "Walnut Inset - Brass Knob"), drawerPanel: "3/4\" Solid Walnut"))
        }
    }

    static func tvStand() -> BIMModel {
        LibraryKit.piece("TV Stand", category: .casework, sizes: [Size("48\"", w: 48, d: 16, h: 22), Size("60\"", w: 60, d: 18, h: 24), Size("72\"", w: 72, d: 18, h: 24)],
                         description: "Mid-century media console: walnut veneer carcass on tapered legs, doors either side of an open shelf") { k in
            walnut(k)
            try k.carcass(CarcassSpec(panel: walnutPly, top: .over(walnutTop, front: 0.25, sides: 0.25, back: 0), base: .legs(walnutLeg, height: 7, inset: 1.5),
                                      columns: [CarcassColumn(CarcassRow(.door, shelves: 1)), CarcassColumn(CarcassRow(.none, shelves: 1)),
                                                CarcassColumn(CarcassRow(.door, shelves: 1))],
                                      shelf: "3/4\" Walnut Veneer Shelf", doorType: "Walnut Slab - Brass Knob"))
        }
    }

    static func bookshelf() -> BIMModel {
        LibraryKit.piece("Bookshelf", category: .casework, sizes: [Size("30\"", w: 30, d: 12, h: 72), Size("36\"", w: 36, d: 12, h: 72), Size("36\" Tall", w: 36, d: 12, h: 84)],
                         description: "Oak veneer bookcase: fixed middle shelf, four adjustable shelves on pins, recessed plinth, back in a rabbet") { k in
            oak(k)
            let c = try k.carcass(CarcassSpec(panel: oakPly, top: .over("1\" Solid White Oak Top", front: 0.75, sides: 0.5, back: 0), base: .plinth(height: 3.5, setback: 1),
                                              back: "1/4\" Plywood", columns: [CarcassColumn(CarcassRow(.none, shelves: 2), CarcassRow(.none, shelves: 2))],
                                              shelf: "3/4\" Oak Veneer Shelf"))
            _ = c
        }
    }

    static func storageCabinet() -> BIMModel {
        LibraryKit.piece("Storage Cabinet", category: .casework, sizes: [Size("30\"", w: 30, d: 16, h: 60), Size("36\"", w: 36, d: 18, h: 72)],
                         description: "Painted Shaker cupboard: pair of doors over adjustable shelves, two drawers below") { k in
            shaker(k)
            try k.carcass(CarcassSpec(panel: whitePanel, top: .over("3/4\" Painted MDF Top (White)", front: 0.75, sides: 0.5), base: .plinth(height: 3.5, setback: 2),
                                      columns: [CarcassColumn(CarcassRow(.drawers(2), height: 13), CarcassRow(.pair, shelves: 3))],
                                      shelf: "3/4\" Painted MDF Shelf (White)", pairType: "Shaker White Pair - Bar Pull", drawerType: "Shaker White - Bar Pull"))
        }
    }

    static func shoeRack() -> BIMModel {
        LibraryKit.piece("Shoe Rack", sizes: [Size("24\"", w: 24, d: 12, h: 18), Size("30\"", w: 30, d: 12, h: 18), Size("36\"", w: 36, d: 13, h: 20)],
                         description: "Solid oak shoe rack: two slatted tiers between solid sides, a top to sit on") { k in
            k.panelType("3/4\" Solid White Oak", thickness: 0.75, material: "Solid White Oak", edge: nil)
            k.shelfType("1\" Solid White Oak Top", thickness: 1, material: "Solid White Oak", top: true, edgeShape: .roundOver)
            k.railType("3/4\" x 1 1/2\" Oak Slat", width: 1.5, height: 0.75, material: "Solid White Oak")
            k.railType("3/4\" x 1 1/2\" Oak Rail", width: 0.75, height: 1.5, material: "Solid White Oak")
            let t = 0.75
            for x in [k.l, k.r - t] { try k.board(x: x...(x + t), y: k.f...k.b, z: 0...(k.h - 1), type: "3/4\" Solid White Oak") }
            try k.shelf(x: k.l...k.r, y: k.f...k.b, top: k.h, type: "1\" Solid White Oak Top", role: .top)
            // Two slatted tiers, each on front and back rails.
            for z in [3.0, 10.0] {
                try k.rail(from: Vec2(k.l + t, k.f + 1), to: Vec2(k.r - t, k.f + 1), z: z, type: "3/4\" x 1 1/2\" Oak Rail")
                try k.rail(from: Vec2(k.r - t, k.b - 1), to: Vec2(k.l + t, k.b - 1), z: z, type: "3/4\" x 1 1/2\" Oak Rail")
                try k.slats(x: (k.l + t)...(k.r - t), y: (k.f + 0.5)...(k.b - 0.5), z: z + 0.75, alongX: true, number: 4, type: "3/4\" x 1 1/2\" Oak Slat")
            }
        }
    }

    static func shelvingUnit() -> BIMModel {
        LibraryKit.piece("Shelving Unit", sizes: [Size("36\"", w: 36, d: 16, h: 72), Size("48\"", w: 48, d: 18, h: 72), Size("48\" Deep", w: 48, d: 24, h: 72)],
                         description: "Industrial shelving: black steel posts and cross braces, five solid oak shelves") { k in
            k.legType("Black Steel Square 1 1/4\"", shape: .square, width: 1.25, material: "Black Steel")
            k.shelfType("1\" Solid White Oak Shelf", thickness: 1, material: "Solid White Oak")
            k.railType("3/8\" Steel Rod", width: 0.375, height: 0.375, profile: .round, material: "Black Steel")
            k.railType("1\" x 1\" Steel Rail", width: 1, height: 1, material: "Black Steel")
            let s = try k.shelving(ShelvingSpec(post: "Black Steel Square 1 1/4\"", shelf: "1\" Solid White Oak Shelf", count: 5, bottom: 4, brace: "3/8\" Steel Rod"))
            _ = s
            // Steel side rails under each shelf carry it.
            let tops = (0..<5).map { kk in 4 + 1 + (k.h - 5) * Double(kk) / 4 }
            for z in tops {
                try k.rail(from: Vec2(k.l + 0.625, k.b - 1.25), to: Vec2(k.l + 0.625, k.f + 1.25), z: z - 1, type: "1\" x 1\" Steel Rail")
                try k.rail(from: Vec2(k.r - 0.625, k.f + 1.25), to: Vec2(k.r - 0.625, k.b - 1.25), z: z - 1, type: "1\" x 1\" Steel Rail")
            }
        }
    }

    // MARK: Bedroom

    static func bed() -> BIMModel {
        // Frame outside = mattress + 2" across (rails and clearance), + 3" along (headboard, foot rail).
        LibraryKit.piece("Bed", sizes: [Size("Twin", w: 40, d: 78, h: 48, ["Mattress Width": 38, "Mattress Length": 75]),
                                        Size("Full", w: 56, d: 78, h: 48, ["Mattress Width": 54, "Mattress Length": 75]),
                                        Size("Queen", w: 62, d: 83, h: 52, ["Mattress Width": 60, "Mattress Length": 80]),
                                        Size("King", w: 78, d: 83, h: 52, ["Mattress Width": 76, "Mattress Length": 80])],
                         parameters: ["Mattress Width", "Mattress Length"],
                         description: "Platform bed: channel-tufted upholstered headboard, walnut rails on cleats, slats, centre rail and legs; mattress and bedding") { k in
            walnut(k)
            k.panelType("1\" Solid Walnut", thickness: 1, material: "Solid Walnut", edge: nil)
            k.legType("Walnut Square 2\"", shape: .square, width: 2, material: "Solid Walnut")
            try k.bed(BedSpec(frame: "1\" Solid Walnut", headboard: .upholstered(material: "Fabric - Charcoal Weave", thickness: 2.5, channels: 7), footboard: nil,
                              railTop: 13, railHeight: 6, slatDrop: 2.5, leg: "Walnut Square 2\"", mattressThickness: 11, pillows: 2))
            try k.setFormula("Width", "Mattress Width + 0.0508 m")
            try k.setFormula("Depth", "Mattress Length + 0.0762 m")
        }
    }

    static func bedsideTable() -> BIMModel {
        LibraryKit.piece("Bedside Table", sizes: [Size("20\"", w: 20, d: 16, h: 24), Size("24\"", w: 24, d: 18, h: 26)],
                         description: "Walnut nightstand on tapered legs: a drawer over an open shelf") { k in
            walnut(k)
            try k.carcass(CarcassSpec(panel: walnutPly, top: .over(walnutTop, front: 0.25, sides: 0.25), base: .legs(walnutLeg, height: 8, inset: 1),
                                      columns: [CarcassColumn(CarcassRow(.none), CarcassRow(.drawers(1), height: 5))],
                                      shelf: "3/4\" Walnut Veneer Shelf", drawerType: "Walnut Slab - Brass Knob"))
        }
    }

    static func wardrobe() -> BIMModel {
        LibraryKit.piece("Wardrobe", category: .casework, sizes: [Size("36\"", w: 36, d: 24, h: 72), Size("48\"", w: 48, d: 24, h: 78), Size("72\"", w: 72, d: 24, h: 84)],
                         description: "Painted Shaker wardrobe: hanging rod and a shelf behind the left door, adjustable shelves behind the right, two drawers below each") { k in
            shaker(k, pulls: "160 mm")
            try k.carcass(CarcassSpec(panel: whitePanel, top: .over("3/4\" Painted MDF Top (White)", front: 1, sides: 0.75), base: .plinth(height: 4, setback: 2),
                                      columns: [CarcassColumn(CarcassRow(.drawers(2), height: 16), CarcassRow(.door, shelves: 0, rod: true)),
                                                CarcassColumn(CarcassRow(.drawers(2), height: 16), CarcassRow(.door, shelves: 3))],
                                      shelf: "3/4\" Painted MDF Shelf (White)", doorType: "Shaker White - Bar Pull", drawerType: "Shaker White - Bar Pull"))
        }
    }

    static func dresser() -> BIMModel {
        LibraryKit.piece("Dresser", category: .casework, sizes: [Size("48\"", w: 48, d: 18, h: 32), Size("60\"", w: 60, d: 18, h: 34), Size("66\"", w: 66, d: 20, h: 34)],
                         description: "Mid-century six-drawer dresser: walnut veneer carcass, solid walnut top, tapered legs, edge pulls") { k in
            walnut(k)
            try k.carcass(CarcassSpec(panel: walnutPly, top: .over(walnutTop, front: 0.25, sides: 0.25), base: .legs(walnutLeg, height: 7, inset: 1.25),
                                      columns: [CarcassColumn(CarcassRow(.drawers(3))), CarcassColumn(CarcassRow(.drawers(3)))],
                                      shelf: "3/4\" Walnut Veneer Shelf", drawerType: "Walnut Slab - Edge Pull"))
        }
    }

    static func dressingTable() -> BIMModel {
        LibraryKit.piece("Dressing Table", sizes: [Size("40\"", w: 40, d: 18, h: 60), Size("48\"", w: 48, d: 20, h: 62)],
                         description: "Walnut dressing table with a drawer and a framed mirror on posts") { k in
            walnut(k)
            k.railType("3/4\" x 4\" Walnut Apron", width: 0.75, height: 4, material: "Solid Walnut")
            k.frontType(.drawer, "Walnut Inset - Brass Knob", from: "Slab - Inset", material: "Solid Walnut", handle: (FurnitureHardware.knob, "1 1/2\" Brass"))
            k.legType("Walnut Square 1 1/4\"", shape: .square, width: 1.25, material: "Solid Walnut")
            // The table's top is on its own plane at half the Height (30" for the 60" type); the mirror runs to the Top.
            try k.addPlane("Table Top", axis: .z, formula: "Height / 2")
            let zt = k.plane("Table Top")
            try k.table(TableSpec(top: walnutTop, z: zt, leg: walnutLeg, legInset: 1, apron: "3/4\" x 4\" Walnut Apron", apronSetback: 0.25,
                                  drawer: (width: 20, height: 3.5, type: "Walnut Inset - Brass Knob"), drawerPanel: "3/4\" Solid Walnut"))
            // The mirror: two posts on the top at the back, a walnut frame and the glass.
            let y = k.b - 1.25
            let px = (k.r - k.l) / 2 - 5
            for x in [-px, px] { try k.leg(at: Vec2(x, y), z: zt...k.h, type: "Walnut Square 1 1/4\"") }
            let mw = 2 * px - 1.25, mz0 = zt + 6, mz1 = k.h - 0.25
            let frame = FurnitureForms.roundedRect(Vec2(0, (mz0 + mz1) / 2), mw, mz1 - mz0, 3)
            let glass = FurnitureForms.roundedRect(Vec2(0, (mz0 + mz1) / 2), mw - 2.5, mz1 - mz0 - 2.5, 2)
            guard let zl = k.axisLock(.span, low: "Table Top", high: "Top") else { return }
            let xl = k.axisLock(.stretch, low: "Left", high: "Right"), yl = k.axisLock(.high, low: "Front", high: "Back")
            try k.extrusion(frame, plane: .xz, w: (y - 0.5)...(y + 0.5), material: "Solid Walnut", lock: .custom(FormLock(x: xl, y: yl, z: zl)))
            try k.extrusion(glass, plane: .xz, w: (y - 0.625)...(y - 0.5), material: "Mirror", lock: .custom(FormLock(x: xl, y: yl, z: zl)))
        }
    }

    // MARK: Dining Room

    static func diningTable() -> BIMModel {
        LibraryKit.piece("Dining Table", sizes: [Size("4-Seat 48\"", w: 48, d: 36, h: 30), Size("6-Seat 72\"", w: 72, d: 40, h: 30), Size("8-Seat 96\"", w: 96, d: 42, h: 30)],
                         description: "Solid white oak dining table: 1 1/4\" top with eased edges, tapered legs, 4\" aprons") { k in
            k.shelfType("1 1/4\" Solid White Oak Top", thickness: 1.25, material: "Solid White Oak", top: true, edgeShape: .chamfer)
            k.legType("White Oak Square Tapered 2 1/2\"", shape: .square, width: 2.5, taper: 1.5, material: "Solid White Oak")
            k.railType("7/8\" x 4\" White Oak Apron", width: 0.875, height: 4, material: "Solid White Oak")
            try k.table(TableSpec(top: "1 1/4\" Solid White Oak Top", leg: "White Oak Square Tapered 2 1/2\"", legInset: 2, apron: "7/8\" x 4\" White Oak Apron",
                                  apronSetback: 0.375))
        }
    }

    static func diningChair() -> BIMModel {
        LibraryKit.piece("Dining Chair", sizes: [Size("18\"", w: 18, d: 20, h: 33), Size("20\"", w: 20, d: 21, h: 34)],
                         description: "Walnut dining chair: leather upholstered seat, curved-look slat back, side stretchers") { k in
            walnut(k)
            k.legType("Walnut Square Tapered 1 1/2\"", shape: .square, width: 1.5, taper: 1, material: "Solid Walnut")
            k.legType("Walnut Back Leg 1 1/2\"", shape: .square, width: 1.5, depth: 1.5, material: "Solid Walnut")
            k.railType("3/4\" x 2 3/4\" Walnut Seat Rail", width: 0.75, height: 2.75, material: "Solid Walnut")
            k.railType("1/2\" x 2\" Walnut Slat", width: 2, height: 0.5, material: "Solid Walnut")
            k.railType("3/4\" x 1\" Walnut Stretcher", width: 0.75, height: 1, material: "Solid Walnut")
            try k.chair(ChairSpec(seatHeight: 18, leg: "Walnut Square Tapered 1 1/2\"", backLeg: "Walnut Back Leg 1 1/2\"", legInset: 0.25,
                                  rail: "3/4\" x 2 3/4\" Walnut Seat Rail", seat: .upholstered(material: "Leather - Cognac", thickness: 1.75),
                                  back: .slats(count: 3, type: "1/2\" x 2\" Walnut Slat"), stretchers: (type: "3/4\" x 1\" Walnut Stretcher", height: 6)))
        }
    }

    static func sideboard() -> BIMModel {
        LibraryKit.piece("Sideboard", category: .casework, sizes: [Size("60\"", w: 60, d: 18, h: 32), Size("72\"", w: 72, d: 18, h: 34)],
                         description: "Walnut sideboard on tapered legs: doors with shelves either side of three drawers") { k in
            walnut(k)
            try k.carcass(CarcassSpec(panel: walnutPly, top: .over(walnutTop, front: 0.25, sides: 0.25), base: .legs(walnutLeg, height: 7, inset: 1.5),
                                      columns: [CarcassColumn(CarcassRow(.door, shelves: 1)), CarcassColumn(CarcassRow(.drawers(3))), CarcassColumn(CarcassRow(.door, shelves: 1))],
                                      shelf: "3/4\" Walnut Veneer Shelf", doorType: "Walnut Slab - Brass Knob", drawerType: "Walnut Slab - Brass Knob"))
        }
    }

    // MARK: Kitchen

    static func kitchenCabinet() -> BIMModel {
        LibraryKit.piece("Kitchen Cabinet", category: .casework,
                         sizes: [Size("B24", w: 24, d: 24, h: 34.5), Size("B30", w: 30, d: 24, h: 34.5), Size("B33", w: 33, d: 24, h: 34.5), Size("B36", w: 36, d: 24, h: 34.5)],
                         description: "Frameless base cabinet: drawer over a pair of Shaker doors, adjustable shelf, 4\" toe kick") { k in
            shaker(k)
            try k.carcass(CarcassSpec(panel: whitePanel, top: .inside("3/4\" Painted MDF Shelf (White)"), base: .plinth(height: 4, setback: 3),
                                      columns: [CarcassColumn(CarcassRow(.pair, shelves: 1), CarcassRow(.drawers(1), height: 5.5))],
                                      shelf: "3/4\" Painted MDF Shelf (White)", pairType: "Shaker White Pair - Bar Pull", drawerType: "Slab White - Bar Pull"))
        }
    }

    static func kitchenBaseSingle() -> BIMModel {
        LibraryKit.piece("Kitchen Base Cabinet - Single Door", category: .casework,
                         sizes: [Size("B12", w: 12, d: 24, h: 34.5), Size("B15", w: 15, d: 24, h: 34.5), Size("B18", w: 18, d: 24, h: 34.5), Size("B21", w: 21, d: 24, h: 34.5)],
                         description: "Frameless base cabinet: drawer over a Shaker door, adjustable shelf, 4\" toe kick") { k in
            shaker(k)
            try k.carcass(CarcassSpec(panel: whitePanel, top: .inside("3/4\" Painted MDF Shelf (White)"), base: .plinth(height: 4, setback: 3),
                                      columns: [CarcassColumn(CarcassRow(.door, shelves: 1), CarcassRow(.drawers(1), height: 5.5))],
                                      shelf: "3/4\" Painted MDF Shelf (White)", doorType: "Shaker White - Bar Pull", drawerType: "Slab White - Bar Pull"))
        }
    }

    static func kitchenWallCabinet() -> BIMModel {
        LibraryKit.piece("Kitchen Wall Cabinet", category: .casework,
                         sizes: [Size("W2430", w: 24, d: 12, h: 30), Size("W3030", w: 30, d: 12, h: 30), Size("W3630", w: 36, d: 12, h: 30), Size("W3642", w: 36, d: 12, h: 42)],
                         description: "Frameless wall cabinet: pair of Shaker doors, two adjustable shelves; hang with its base at 54\"") { k in
            shaker(k)
            try k.carcass(CarcassSpec(panel: whitePanel, top: .inside("3/4\" Painted MDF Shelf (White)"), base: .floor,
                                      columns: [CarcassColumn(CarcassRow(.pair, shelves: 2, handle: .bottom))], shelf: "3/4\" Painted MDF Shelf (White)",
                                      pairType: "Shaker White Pair - Bar Pull"))
        }
    }

    static func pantryCabinet() -> BIMModel {
        LibraryKit.piece("Pantry Cabinet", category: .casework, sizes: [Size("24\"", w: 24, d: 24, h: 84), Size("30\"", w: 30, d: 24, h: 84), Size("36\"", w: 36, d: 24, h: 90)],
                         description: "Tall pantry: pairs of Shaker doors over adjustable shelves, a fixed shelf between, toe kick") { k in
            shaker(k, pulls: "192 mm")
            try k.carcass(CarcassSpec(panel: whitePanel, top: .inside("3/4\" Painted MDF Shelf (White)"), base: .plinth(height: 4, setback: 3),
                                      columns: [CarcassColumn(CarcassRow(.pair, height: 30, shelves: 1), CarcassRow(.pair, shelves: 3, handle: .bottom))],
                                      shelf: "3/4\" Painted MDF Shelf (White)", pairType: "Shaker White Pair - Bar Pull"))
        }
    }

    // MARK: Home Office

    static func studyDesk() -> BIMModel {
        LibraryKit.piece("Study Desk", sizes: [Size("48\"", w: 48, d: 24, h: 30), Size("60\"", w: 60, d: 30, h: 30)],
                         description: "White oak desk: a three-drawer pedestal, an end panel, a modesty panel and a solid top") { k in
            oak(k)
            k.frontType(.drawer, "Oak Slab - Bar Pull", from: "Slab - Full Overlay", material: "Oak Veneer Plywood", handle: (FurnitureHardware.barPull, "128 mm"))
            let topT = 1.0
            try k.shelf(x: k.l...k.r, y: k.f...k.b, top: k.h, type: "1\" Solid White Oak Top", role: .top)
            // The pedestal on the right, under the top.
            let pw = 16.0
            try k.carcass(CarcassSpec(x: (k.r - pw - 0.5)...(k.r - 0.5), y: (k.f + 1)...(k.b - 0.5), z: 0...(k.h - topT), panel: oakPly, top: .inside("3/4\" Oak Veneer Shelf"),
                                      base: .plinth(height: 3, setback: 2), columns: [CarcassColumn(CarcassRow(.drawers(3)))], shelf: "3/4\" Oak Veneer Shelf",
                                      drawerType: "Oak Slab - Bar Pull"))
            // The end panel on the left and the modesty panel between it and the pedestal.
            let t = 0.75
            try k.board(x: (k.l + 0.5)...(k.l + 0.5 + t), y: (k.f + 1)...(k.b - 0.5), z: 0...(k.h - topT), type: oakPly)
            try k.board(x: (k.l + 0.5 + t)...(k.r - pw - 0.5), y: (k.b - 3 - t)...(k.b - 3), z: 12...(k.h - topT), type: oakPly)
        }
    }

    static func officeChair() -> BIMModel {
        LibraryKit.piece("Office Chair", sizes: [Size("Task", w: 26, d: 25, h: 40), Size("High Back", w: 26, d: 25, h: 46)],
                         description: "Swivel task chair: five-star aluminum base on casters, gas lift, padded seat, mesh back, T-arms") { k in
            k.legType("Twin-Wheel Caster 2\"", shape: .caster, width: 2, material: "Plastic - Black")
            let alu = "Aluminum", black = "Plastic - Black"
            let center: FurnitureAxisLock = .axes(x: .stretch, y: .stretch, z: .low)
            // Five-star base: tapered arms from the hub, a caster under each tip.
            let tipR = 11.5, z0 = 2.6, z1 = 3.8
            for i in 0..<5 {
                let a = -Double.pi / 2 + Double(i) * 2 * Double.pi / 5
                let u = Vec2(cos(a), sin(a)), n = Vec2(-sin(a), cos(a))
                let arm = [u * 1.2 + n * 1.2, u * tipR + n * 0.7, u * (tipR + 0.6), u * tipR - n * 0.7, u * 1.2 - n * 1.2]
                try k.blend(bottom: arm, top: arm.map { $0 * 0.98 }, z: z0...z1, material: alu, lock: center)
                try k.leg(at: u * tipR, z: 0...z0, type: "Twin-Wheel Caster 2\"")
            }
            try k.revolve(axis: .zero, profile: [Vec2(0, 0), Vec2(1.7, 0), Vec2(1.7, 1.8), Vec2(1.2, 2.2), Vec2(0, 2.2)], z: 2.4, material: alu, lock: center)
            // Gas lift: shroud and chrome piston.
            try k.revolve(axis: .zero, profile: [Vec2(0, 0), Vec2(1.15, 0), Vec2(0.95, 7), Vec2(0, 7)], z: 4.6, material: black, lock: center)
            try k.revolve(axis: .zero, profile: [Vec2(0, 0), Vec2(0.55, 0), Vec2(0.55, 3.6), Vec2(0, 3.6)], z: 11.6, material: "Chrome", lock: center)
            // Tilt mechanism, seat shell and cushion.
            try k.extrusion(FurnitureForms.roundedRect(Vec2(0, 0), 7, 8, 1), w: 15.2...16.8, material: black, lock: center)
            let seatY = (-10.5)...8.5
            try k.extrusion(FurnitureForms.roundedRect(Vec2(0, -1), 19, 19, 3), w: 16.8...17.4, material: black, lock: center)
            try k.cushion(x: -9.75...9.75, y: seatY, z: 17.4, height: 3.2, crown: 0.6, radius: 2.5, piping: false, material: "Fabric - Charcoal Weave",
                          lock: .axes(x: .stretch, y: .stretch, z: .low))
            // The spine from the mechanism up to the back, and the back: a lumbar-curved mesh slab.
            let spine = LibraryKit.softPolygon([Vec2(2.5, 15.2), Vec2(4.5, 15.2), Vec2(11.2, 20.5), Vec2(11.2, 25), Vec2(9.8, 25), Vec2(9.8, 21.5), Vec2(3.5, 17)], radius: 0.6)
            try k.extrusion(spine, plane: .yz, w: -1.25...1.25, material: alu, lock: center)
            let top = k.h - 0.25
            let front: [Vec2] = [Vec2(9.4, 22), Vec2(8.9, 25.5), Vec2(9.1, 28.5), Vec2(9.9, 32), Vec2(10.6, top - 4), Vec2(10.9, top)]
            let back = front.reversed().map { Vec2($0.x + 1.4, $0.y) }
            let slab = LibraryKit.softPolygon(front + back, radius: 0.6)
            try k.extrusion(slab, plane: .yz, w: -9.5...9.5, material: "Mesh - Black", lock: .axes(x: .stretch, y: .stretch, z: .span))
            // T-arms: a bracket under the seat, a post and a padded rest each side.
            for s in [-1.0, 1.0] {
                let xIn = s * 9.25, xOut = s * 10.75
                try k.extrusion(FurnitureForms.roundedRect(Vec2((xIn + xOut) / 2 + s * 0.4, 16.3), abs(xOut - xIn) + 0.8, 1, 0.3), plane: .xz, w: -1...1.5, material: black,
                                lock: .axes(x: s < 0 ? .low : .high, y: .stretch, z: .low))
                try k.extrusion(LibraryKit.softPolygon([Vec2(-0.6, 15.8), Vec2(1.6, 15.8), Vec2(1.2, 26.2), Vec2(-1.2, 26.2)], radius: 0.3), plane: .yz,
                                w: (s < 0 ? xOut - 1.1 : xOut)...(s < 0 ? xOut : xOut + 1.1), material: black, lock: .axes(x: s < 0 ? .low : .high, y: .stretch, z: .low))
                let padX = s * 11.1
                try k.cushion(x: (padX - 1.6)...(padX + 1.6), y: (-5.5)...4.5, z: 26.2, height: 1.1, crown: 0.25, radius: 1.4, piping: false, material: black,
                              lock: .axes(x: s < 0 ? .low : .high, y: .stretch, z: .low))
            }
        }
    }

    // MARK: Entryway and Bathroom

    static func entrywayBench() -> BIMModel {
        LibraryKit.piece("Entryway Bench", sizes: [Size("36\"", w: 36, d: 15, h: 19), Size("42\"", w: 42, d: 16, h: 19), Size("48\"", w: 48, d: 16, h: 19)],
                         description: "Oak bench with three shoe cubbies, a bottom shelf and a piped seat cushion") { k in
            oak(k)
            try k.carcass(CarcassSpec(z: 0...17, panel: oakPly, top: .over("1\" Solid White Oak Top", front: 0.5, sides: 0.5), base: .plinth(height: 2.5, setback: 0.75),
                                      back: "1/4\" Plywood", columns: [CarcassColumn(), CarcassColumn(), CarcassColumn()], shelf: "3/4\" Oak Veneer Shelf"))
            try k.cushion(x: (k.l + 0.75)...(k.r - 0.75), y: (k.f + 0.75)...(k.b - 0.75), z: 17, height: 2, crown: 0.5, radius: 1.25,
                          material: "Fabric - Charcoal Weave")
        }
    }

    static func bathroomVanity() -> BIMModel {
        LibraryKit.piece("Bathroom Vanity", category: .casework,
                         sizes: [Size("30\"", w: 30, d: 21, h: 34.5), Size("36\"", w: 36, d: 21, h: 34.5), Size("48\"", w: 48, d: 22, h: 34.5)],
                         description: "Painted vanity: quartz top with backsplash, undermount basin and faucet, pair of Shaker doors under a false drawer front") { k in
            shaker(k)
            k.frontType(.flap, "Shaker White Tilt-Out", from: "Slab - Full Overlay Drop-Down", material: "Painted MDF - White", panel: "Painted MDF - White",
                        style: .shaker, handle: (FurnitureHardware.barPull, "128 mm"))
            k.shelfType("1 1/4\" Quartz Top", thickness: 1.25, material: "Quartz - White", top: true, edgeShape: .roundOver, grain: .none)
            k.panelType("3/4\" Quartz Backsplash", thickness: 0.75, material: "Quartz - White", edge: nil, grain: .none)
            // Height is the counter's top (34 1/2"); the 4" backsplash and the faucet stand above it.
            let topZ = k.h, topT = 1.25
            try k.carcass(CarcassSpec(z: 0...(topZ - topT), panel: whitePanel, top: .inside("3/4\" Painted MDF Shelf (White)"), base: .plinth(height: 4, setback: 3),
                                      columns: [CarcassColumn(CarcassRow(.pair, shelves: 1), CarcassRow(.flapDown, height: 5))],
                                      shelf: "3/4\" Painted MDF Shelf (White)", pairType: "Shaker White Pair - Bar Pull", flapType: "Shaker White Tilt-Out"))
            try k.shelf(x: k.l...k.r, y: k.f...k.b, top: topZ, type: "1 1/4\" Quartz Top", role: .top)
            try k.board(x: k.l...k.r, y: (k.b - 0.75)...k.b, z: topZ...(topZ + 4), type: "3/4\" Quartz Backsplash")
            // The basin: a round undermount bowl under an opening in the top, and the faucet behind it.
            let by = -1.0, r = 7.5
            let hole = (0..<24).map { i -> Vec2 in let a = Double(i) / 24 * 2 * Double.pi; return Vec2(r * cos(a), by + r * 0.8 * sin(a)) }
            var cut = FurnitureFormData(kind: .extrusion, isVoid: true, profile: hole.map { Vec2($0.x * LibraryKit.inch, $0.y * LibraryKit.inch) },
                                        w0: (topZ - topT - 0.85) * LibraryKit.inch, w1: (topZ + 0.1) * LibraryKit.inch)
            cut.lock = FormLock.framing(k.model, x: .stretch, y: .stretch, z: .low)
            try k.step { tx in _ = try FurniturePartOperations.createForm(cut, in: tx) }
            try k.revolve(axis: Vec2(0, by), profile: [Vec2(r + 0.6, 0), Vec2(r + 0.6, -0.4), Vec2(r - 0.2, -1.2), Vec2(r - 1.5, -5), Vec2(2, -6.2), Vec2(0, -6.4),
                                                        Vec2(0, -5.9), Vec2(1.8, -5.7), Vec2(r - 2, -4.6), Vec2(r - 0.8, -1), Vec2(r - 0.2, 0)],
                          z: topZ - topT, material: "Ceramic - White", lock: .axes(x: .stretch, y: .stretch, z: .low))
            let fy = by + r * 0.8 + 2
            try k.revolve(axis: Vec2(0, fy), profile: [Vec2(0, 0), Vec2(1.1, 0), Vec2(1.1, 0.4), Vec2(0.55, 0.6), Vec2(0.5, 9), Vec2(0, 9.4)], z: topZ,
                          material: "Chrome", lock: .axes(x: .stretch, y: .stretch, z: .low))
            let tube = (0..<10).map { i -> Vec2 in let a = Double(i) / 10 * 2 * Double.pi; return Vec2(0.42 * cos(a), 0.42 * sin(a)) }
            try k.sweep(path: [Vec2(0, fy), Vec2(0, fy - 5)], profile: tube, z: topZ + 8.6, material: "Chrome", lock: .axes(x: .stretch, y: .stretch, z: .low))
            try k.revolve(axis: Vec2(0, fy - 5), profile: [Vec2(0, 0), Vec2(0.45, 0), Vec2(0.45, 1.2), Vec2(0, 1.2)], z: topZ + 7.6, material: "Chrome",
                          lock: .axes(x: .stretch, y: .stretch, z: .low))
            for s in [-1.0, 1.0] {
                try k.revolve(axis: Vec2(s * 3.5, fy), profile: [Vec2(0, 0), Vec2(0.9, 0), Vec2(0.7, 0.5), Vec2(0.45, 2.2), Vec2(0, 2.4)], z: topZ, material: "Chrome",
                              lock: .axes(x: .stretch, y: .stretch, z: .low))
            }
        }
    }
}

/// The kit's form lock, spelled for the essentials.
typealias FurnitureAxisLock = LibraryBuilder.Lock
