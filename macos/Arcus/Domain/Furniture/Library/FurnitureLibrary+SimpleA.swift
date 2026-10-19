import Foundation

// FM9B: this batch's library pieces (see FurnitureLibrary.swift): 83 simple pieces for the living room, bedroom, dining
// room, kitchen, home office and bathroom, written with the FM9B kit (FurnitureLibrary+SimpleAKit*.swift), one file
// per room.

extension FurnitureLibrary {
    static var simpleA: [FurnitureLibraryPiece] { simpleASpecs.map { $0.libraryPiece(keywords: simpleAKeywords[$0.name] ?? []) } }

    /// Other names people search for (Load Furniture and Home ▸ Furniture search them too).
    static let simpleAKeywords: [String: [String]] = [
        "Sectional Sofa": ["couch", "l-shaped sofa", "corner sofa"], "Loveseat": ["sofa", "couch", "two-seater"], "Recliner": ["armchair", "lounger"],
        "Accent Chair": ["side chair", "armless chair"], "Lounge Chair": ["club chair", "easy chair"], "Rocking Chair": ["rocker"],
        "End Table": ["side table", "lamp table"], "Entertainment Center": ["tv stand", "media console", "tv cabinet"],
        "Display Cabinet": ["curio", "vitrine", "glass cabinet"], "Pouf": ["footstool", "hassock", "ottoman"], "Bench": ["seat"],
        "Room Divider": ["folding screen", "partition"], "Nesting Tables": ["side tables", "stacking tables"], "Magazine Rack": ["magazine holder"],
        "Corner Shelf": ["corner unit"], "Platform Bed": ["bed frame", "queen bed", "king bed"], "Storage Bed": ["bed with drawers"],
        "Bunk Bed": ["twin over twin", "kids bed"], "Daybed": ["sofa bed", "twin bed"], "Headboard": ["bed head"],
        "Nightstand": ["bedside table", "night table"], "Chest of Drawers": ["dresser", "tallboy", "chest"], "Armoire": ["wardrobe", "closet"],
        "Vanity Table": ["dressing table", "makeup table"], "Vanity Stool": ["dressing stool"], "Full-Length Mirror": ["floor mirror", "cheval mirror"],
        "Bedroom Bench": ["end of bed bench", "upholstered bench"], "Storage Chest": ["blanket chest", "trunk", "hope chest"],
        "Clothes Rack": ["garment rack", "clothing rail"], "Jewelry Cabinet": ["jewelry armoire"], "Blanket Ladder": ["quilt ladder"],
        "Bedside Shelf": ["floating nightstand", "wall shelf"], "Dining Bench": ["bench"], "Buffet Cabinet": ["sideboard", "buffet"],
        "China Cabinet": ["hutch", "display cabinet"], "Bar Cabinet": ["liquor cabinet", "drinks cabinet"], "Bar Cart": ["drinks trolley"],
        "Bar Stool": ["stool"], "Counter Stool": ["kitchen stool"], "Kitchen Island": ["island", "butcher block island"],
        "Breakfast Table": ["kitchen table", "bistro table"], "Breakfast Stool": ["kitchen stool"], "Serving Trolley": ["serving cart", "tea cart"],
        "Corner Cabinet": ["corner hutch"], "Wine Rack": ["wine cubby", "bottle rack"], "Crockery Cabinet": ["dish cabinet", "kitchen dresser"],
        "Kitchen Cart": ["rolling island", "kitchen trolley"], "Kitchen Rack": ["wire shelving", "pantry rack"], "Open Shelving Unit": ["shelves", "etagere"],
        "Utility Cabinet": ["pantry", "broom cabinet", "tall cabinet"], "Microwave Stand": ["microwave cart"], "Baker's Rack": ["kitchen rack"],
        "Storage Trolley": ["utility cart", "rolling cart"], "Breakfast Bar": ["bar table", "pub table"], "Foldable Table": ["folding table"],
        "Step Stool": ["step ladder"], "Office Desk": ["pedestal desk", "work desk"], "Computer Desk": ["pc desk", "workstation"],
        "Writing Desk": ["secretary", "console desk"], "Standing Desk": ["sit-stand desk", "adjustable desk"], "Executive Desk": ["double pedestal desk"],
        "Ergonomic Chair": ["office chair", "task chair", "desk chair"], "Guest Chair": ["visitor chair", "side chair"],
        "Filing Cabinet": ["file cabinet", "file drawers"], "Bookcase": ["bookshelf", "shelving"], "Desk Hutch": ["hutch", "desk organizer"],
        "Printer Stand": ["printer cart"], "Monitor Riser": ["monitor stand", "screen riser"], "Storage Pedestal": ["mobile pedestal", "file pedestal"],
        "Office Credenza": ["sideboard", "credenza"], "Meeting Table": ["conference table", "boardroom table"], "Wall-Mounted Desk": ["drop-down desk", "fold-down desk"],
        "Drawer Unit": ["chest", "storage drawers"], "Vanity Cabinet": ["bathroom vanity", "sink cabinet"], "Medicine Cabinet": ["mirror cabinet", "bathroom cabinet"],
        "Bathroom Storage Cabinet": ["bathroom cabinet"], "Wall Shelf": ["bathroom shelf", "towel shelf"], "Towel Rack": ["towel stand", "towel rail"],
        "Linen Cabinet": ["linen tower", "tall bathroom cabinet"], "Bathroom Stool": ["shower stool"], "Laundry Hamper": ["laundry basket", "hamper"],
        "Over-Toilet Storage Unit": ["space saver", "over the toilet"], "Bathroom Bench": ["shower bench", "teak bench"],
    ]

    /// The pieces as specs (tests build them with `build()`, which reports a failing step).
    static var simpleASpecs: [SA.Piece] { simpleALiving + simpleABedroom + simpleADining + simpleAKitchen + simpleAOffice + simpleABathroom }
}
