import Foundation

// FM9C: Storage & Utility pieces (simple detail).

extension SimpleB {
    static var storage: [Piece] {
        [
            Piece("Modular Storage System", [storageRoom], .casework, modularStorageSystem),
            Piece("Drawer Cabinet", [storageRoom], .casework, drawerCabinet),
            Piece("Storage Bench", [storageRoom], storageBench),
            Piece("Storage Ottoman", [storageRoom], storageOttoman),
            Piece("Utility Rack", [storageRoom], utilityRack),
            Piece("Laundry Cabinet", [storageRoom], .casework, laundryCabinet),
            Piece("Ironing Board Cabinet", [storageRoom], .casework, ironingBoardCabinet),
            Piece("Wardrobe Organizer", [storageRoom], .casework, wardrobeOrganizer),
            Piece("Shoe Organizer", [storageRoom], shoeOrganizer),
            Piece("Trunk", [storageRoom], trunk),
            Piece("Cube Organizer", [storageRoom], cubeOrganizer),
            Piece("Wall Cabinet", [storageRoom], .casework, wallCabinet),
            Piece("Freestanding Closet", [storageRoom], freestandingCloset),
        ]
    }

    /// A divider panel centred on `x`, between y0 and y1 and z0 and z1 (follows the plane its faces are drawn on).
    @discardableResult
    static func divider(_ s: SBStep, x: Double, y: (Double, Double), z: (Double, Double), _ type: String = "3/4\" Plywood") throws -> ElementID {
        let t = try s.thickness(.furniturePanels, type)
        return try s.panelX(x - t / 2, inward: 1, y: y, z: z, type, role: .divider)
    }

    /// Three columns on a toe kick: open shelves left, a pair of doors under an open shelf in the middle, three drawers
    /// under an open shelf right.
    static func modularStorageSystem() throws -> BIMModel {
        let p = try SBBuilder("Modular Storage System", .casework, [SBSize(72, 16, 72), SBSize(96, 16, 84)], material: "Plywood",
                              planes: [SBPlane("Divider 1", .x, "-Width / 6", at: -12), SBPlane("Divider 2", .x, "Width / 6", at: 12),
                                       SBPlane("Shelf 1", .z, "Height * 0.4"), SBPlane("Shelf 2", .z, "Height * 0.7")])
        var c: SBCarcass?
        try p.step("Carcass, Dividers and Shelves") { s in
            c = try s.carcass(bottomAt: 4.75)
            let (d1, d2, s1, s2) = (s.pos("Divider 1"), s.pos("Divider 2"), s.pos("Shelf 1"), s.pos("Shelf 2"))
            for x in [d1, d2] { try divider(s, x: x, y: (s.f, s.b - 0.25), z: (4.75, s.h - 0.75)) }
            for (x0, x1) in [(s.l + 0.75, d1 - 0.375), (d1 + 0.375, d2 - 0.375), (d2 + 0.375, s.r - 0.75)] {
                try s.board(x: (x0, x1), y: (s.f, s.b - 0.25), top: s1, "3/4\" Plywood Shelf")
                try s.board(x: (x0, x1), y: (s.f, s.b - 0.25), top: s2, "3/4\" Plywood Shelf")
            }
            try s.board(x: (s.l + 0.75, d1 - 0.375), y: (s.f, s.b - 0.25), top: (4.75 + s1) / 2, "3/4\" Plywood Shelf", adjustable: true)
        }
        try p.step("Kick and Back") { s in
            try s.plinth(under: c!.bottom)
            try s.back(x: 0, z: s.h / 2)
        }
        try p.step("Doors and Drawers") { s in
            let z = (4.75 + s.pos("Shelf 1")) / 2
            try s.door(x: 0, z: z, "Slab - Full Overlay Pair")
            try s.drawers(x: (s.pos("Divider 2") + s.r) / 2, z: z, count: 3)
        }
        return try p.finish()
    }

    /// A tall stack of five drawers on a toe kick.
    static func drawerCabinet() throws -> BIMModel {
        let p = try SBBuilder("Drawer Cabinet", .casework, [SBSize(24, 18, 40), SBSize(30, 20, 48)], material: "Plywood")
        var c: SBCarcass?
        try p.step("Carcass") { s in c = try s.carcass(bottomAt: 4.75) }
        try p.step("Kick and Back") { s in
            try s.plinth(under: c!.bottom)
            try s.back(x: 0, z: s.h / 2)
        }
        try p.step("Drawers") { s in try s.drawers(x: 0, z: s.h / 2, count: 5) }
        return try p.finish()
    }

    /// An oak bench box with a lift-up seat and a cushion.
    static func storageBench() throws -> BIMModel {
        let p = try SBBuilder("Storage Bench", .furniture, [SBSize(42, 18, 19), SBSize(48, 18, 19)], material: "Solid Oak")
        try p.step("Box") { s in
            let rim = s.h - 3
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (0, rim), "3/4\" Solid Oak")
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (0, rim), "3/4\" Solid Oak")
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (2, rim), "3/4\" Solid Oak")
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (2, rim), "3/4\" Solid Oak")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.75, s.b - 0.75), top: 3, "3/4\" Plywood Shelf", role: .bottom)
        }
        try p.step("Seat") { s in
            try s.lid(x: 0, y: 0)
            try s.cushion(x: (s.l + 0.5, s.r - 0.5), y: (s.f + 0.5, s.b - 0.5), z0: s.h - 2.25, height: 2.25, crown: 0.4, radius: 1)
        }
        return try p.finish()
    }

    /// An upholstered box on short legs with an upholstered lift-up lid.
    static func storageOttoman() throws -> BIMModel {
        let p = try SBBuilder("Storage Ottoman", .furniture, [SBSize(30, 18, 18), SBSize(36, 20, 18)], material: "Fabric")
        try p.step("Box and Legs") { s in
            let rim = s.h - 4
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (3, rim), "4\" Upholstered Panel")
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (3, rim), "4\" Upholstered Panel")
            try s.panelY(s.f, inward: 1, x: (s.l + 4, s.r - 4), z: (3, rim), "4\" Upholstered Panel")
            try s.panelY(s.b, inward: -1, x: (s.l + 4, s.r - 4), z: (3, rim), "4\" Upholstered Panel")
            try s.board(x: (s.l + 4, s.r - 4), y: (s.f + 4, s.b - 4), top: 4, "3/4\" Plywood Shelf", role: .bottom)
            try s.legs(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 1), z: (0, 3), "Round Tapered 1 3/4\" Oak")
        }
        try p.step("Lid") { s in
            try s.lid(x: 0, y: 0, "Upholstered - Lift-Up Lid")
            try s.cushion(x: (s.l, s.r), y: (s.f, s.b), z0: s.h - 3.25, height: 3.25, crown: 0.75, radius: 2)
        }
        return try p.finish()
    }

    /// A steel shelving rack: four posts and five wire shelves.
    static func utilityRack() throws -> BIMModel {
        let p = try SBBuilder("Utility Rack", .furniture, [SBSize(48, 18, 72), SBSize(36, 14, 60)], material: "Steel",
                              planes: [SBPlane("Shelf 1", .z, "Height * 0.27"), SBPlane("Shelf 2", .z, "Height * 0.5"), SBPlane("Shelf 3", .z, "Height * 0.75")])
        try p.step("Posts and Shelves") { s in
            let pw = 1.25
            try s.legs(x: (s.l, s.r), y: (s.f, s.b), z: (0, s.h), "Round 1 1/4\" Steel")
            for z in [6.0, s.pos("Shelf 1"), s.pos("Shelf 2"), s.pos("Shelf 3"), s.h] {
                try s.board(x: (s.l + pw, s.r - pw), y: (s.f, s.b), top: z, "1\" Steel Wire Shelf")
            }
        }
        return try p.finish()
    }

    /// A tall laundry cabinet: a pair of doors over adjustable shelves, two tilt-out hampers below.
    static func laundryCabinet() throws -> BIMModel {
        let p = try SBBuilder("Laundry Cabinet", .casework, [SBSize(30, 24, 72), SBSize(36, 24, 84)], material: "Melamine",
                              planes: [SBPlane("Hamper Line", .z, "Height * 0.42")])
        var c: SBCarcass?
        try p.step("Carcass") { s in
            c = try s.carcass(bottomAt: 4.75, sides: "3/4\" Melamine", top: "3/4\" Laminate Top", bottom: "3/4\" Melamine Shelf")
            let hl = s.pos("Hamper Line")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b - 0.25), top: hl, "3/4\" Melamine Shelf")
            for k in 1...2 { try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.25, s.b - 0.25), top: hl + (s.h - hl) * Double(k) / 3, "3/4\" Melamine Shelf", adjustable: true) }
        }
        try p.step("Kick, Back and Divider") { s in
            try s.plinth(under: c!.bottom, "3/4\" Melamine")
            try s.back(x: 0, z: s.h / 2)
            try s.dividers(x: 0, z: (4.75 + s.pos("Hamper Line")) / 2, count: 1, "3/4\" Melamine")
        }
        try p.step("Doors and Hampers") { s in
            let hl = s.pos("Hamper Line")
            try s.door(x: 0, z: (hl + s.h) / 2, "White Slab - Full Overlay Pair")
            try s.flap(x: s.l / 2, z: (4.75 + hl) / 2)
            try s.flap(x: s.r / 2, z: (4.75 + hl) / 2)
        }
        return try p.finish()
    }

    /// A shallow wall cabinet with a full-height door; the ironing board folds inside with a shelf for the iron.
    static func ironingBoardCabinet() throws -> BIMModel {
        let p = try SBBuilder("Ironing Board Cabinet", .casework, [SBSize(16, 7, 50), SBSize(18, 8, 56)], material: "Plywood")
        try p.step("Carcass and Board") { s in
            try s.carcass(bottomAt: 0.75)
            try s.panelY(s.b - 0.25, inward: -1, x: (s.l + 2.5, s.r - 2.5), z: (3, s.h - 8), "3/4\" Plywood")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.25, s.b - 1.25), top: s.h - 4, "3/4\" Plywood Shelf", adjustable: true)
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        try p.step("Door") { s in try s.door(x: 0, z: s.h / 2) }
        return try p.finish()
    }

    /// An open closet system: a shelf tower in the middle, double hanging left, long hanging right, a top shelf.
    static func wardrobeOrganizer() throws -> BIMModel {
        let p = try SBBuilder("Wardrobe Organizer", .casework, [SBSize(72, 14, 84), SBSize(96, 14, 84)], material: "Melamine",
                              planes: [SBPlane("Tower Left", .x, "-0.2286 m", at: -9), SBPlane("Tower Right", .x, "0.2286 m", at: 9),
                                       SBPlane("Shelf 1", .z, "Height * 0.3"), SBPlane("Shelf 2", .z, "Height * 0.5"), SBPlane("Shelf 3", .z, "Height * 0.7")])
        var bottom: ElementID?
        try p.step("Sides, Tower and Shelves") { s in
            let m = "3/4\" Melamine", shelf = "3/4\" Melamine Shelf"
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (0, s.h), m)
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (0, s.h), m)
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.h, "3/4\" Laminate Top", role: .top)
            let (tl, tr) = (s.pos("Tower Left"), s.pos("Tower Right"))
            for x in [tl, tr] { try divider(s, x: x, y: (s.f, s.b), z: (0, s.h - 12.75), m) }
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.h - 12, shelf)
            bottom = try s.board(x: (tl + 0.375, tr - 0.375), y: (s.f, s.b), top: 4.75, shelf, role: .bottom)
            for n in ["Shelf 1", "Shelf 2", "Shelf 3"] { try s.board(x: (tl + 0.375, tr - 0.375), y: (s.f, s.b), top: s.pos(n), shelf) }
            let rod = "1 1/4\" Round Maple Dowel"
            try s.rail((s.l + 0.75, 0), (tl - 0.375, 0), z: s.h - 15, rod, just: .center)
            try s.rail((s.l + 0.75, 0), (tl - 0.375, 0), z: s.h * 0.48, rod, just: .center)
            try s.rail((tr + 0.375, 0), (s.r - 0.75, 0), z: s.h - 15, rod, just: .center)
        }
        try p.step("Kick") { s in try s.plinth(under: bottom!, "3/4\" Melamine") }
        return try p.finish()
    }

    /// An open shoe rack: two sides, a top and four tiers of sloped rod pairs.
    static func shoeOrganizer() throws -> BIMModel {
        let p = try SBBuilder("Shoe Organizer", .furniture, [SBSize(30, 12, 36), SBSize(42, 12, 36)], material: "Solid Pine")
        try p.step("Sides, Top and Rods") { s in
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (0, s.h - 0.75), "3/4\" Solid Pine")
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (0, s.h - 0.75), "3/4\" Solid Pine")
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "3/4\" Solid Pine Shelf", role: .top)
            for k in 0..<4 {
                let z = 3 + (s.h - 9) * Double(k) / 3
                try s.rail((s.l + 0.75, s.f + 1.5), (s.r - 0.75, s.f + 1.5), z: z, "3/4\" Round Steel Rod", just: .center)
                try s.rail((s.l + 0.75, s.b - 1.5), (s.r - 0.75, s.b - 1.5), z: z + 3, "3/4\" Round Steel Rod", just: .center)
            }
        }
        return try p.finish()
    }

    /// A walnut trunk: a box on four feet with a lift-up lid.
    static func trunk() throws -> BIMModel {
        let p = try SBBuilder("Trunk", .furniture, [SBSize(36, 20, 22), SBSize(42, 22, 24)], material: "Solid Walnut")
        try p.step("Box and Feet") { s in
            let wood = "3/4\" Solid Walnut", rim = s.h - 0.75
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (2.5, rim), wood)
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (2.5, rim), wood)
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (2.5, rim), wood)
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (2.5, rim), wood)
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.75, s.b - 0.75), top: 3.25, "3/4\" Plywood Shelf", role: .bottom)
            for x in [s.l + 1.5, s.r - 1.5] { try s.leg(x, s.f + 1.5, z: (0, 2.5), "Square 1 1/2\" Walnut"); try s.leg(x, s.b - 1.5, z: (0, 2.5), "Square 1 1/2\" Walnut") }
        }
        try p.step("Lid") { s in try s.lid(x: 0, y: 0, "Walnut Slab - Lift-Up Lid") }
        return try p.finish()
    }

    /// Eight open cubes, two wide and four high, in white melamine.
    static func cubeOrganizer() throws -> BIMModel {
        let p = try SBBuilder("Cube Organizer", .furniture, [SBSize(30, 12, 58), SBSize(36, 15, 70)], material: "Melamine",
                              planes: [SBPlane("Shelf 1", .z, "Height * 0.25"), SBPlane("Shelf 2", .z, "Height * 0.5"), SBPlane("Shelf 3", .z, "Height * 0.75")])
        try p.step("Carcass and Shelves") { s in
            try s.carcass(bottomAt: 0.75, sides: "3/4\" Melamine", top: "3/4\" Laminate Top", bottom: "3/4\" Melamine Shelf")
            for n in ["Shelf 1", "Shelf 2", "Shelf 3"] { try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos(n), "3/4\" Melamine Shelf") }
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        try p.step("Dividers") { s in
            for k in 0..<4 { try s.dividers(x: 0, z: s.h * (Double(k) + 0.5) / 4, count: 1, "3/4\" Melamine") }
        }
        return try p.finish()
    }

    /// A wall-hung cabinet with a pair of doors and two adjustable shelves.
    static func wallCabinet() throws -> BIMModel {
        let p = try SBBuilder("Wall Cabinet", .casework, [SBSize(30, 12, 30), SBSize(36, 12, 30)], material: "Plywood")
        try p.step("Carcass and Shelves") { s in
            try s.carcass(bottomAt: 0.75)
            for k in 1...2 { try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.25, s.b - 0.25), top: s.h * Double(k) / 3, "3/4\" Plywood Shelf", adjustable: true) }
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        try p.step("Doors") { s in try s.door(x: 0, z: s.h / 2, "Shaker - Full Overlay Pair") }
        return try p.finish()
    }

    /// A portable closet: a steel frame with canvas sides and back, a hanging rod and a bottom shelf.
    static func freestandingCloset() throws -> BIMModel {
        let p = try SBBuilder("Freestanding Closet", .furniture, [SBSize(48, 20, 70), SBSize(60, 20, 70)], material: "Canvas")
        try p.step("Frame, Canvas and Rod") { s in
            let (_, lw) = try s.legs(x: (s.l, s.r), y: (s.f, s.b), z: (0, s.h), "Square 1\" Steel")
            try s.railRing(x: (s.l, s.r), y: (s.f, s.b), legWidth: lw, top: s.h, "1\" x 1\" Steel Tube")
            try s.railRing(x: (s.l, s.r), y: (s.f, s.b), legWidth: lw, top: 7, "1\" x 1\" Steel Tube", sides: (true, true, false, false))
            try s.panelY(s.b, inward: -1, x: (s.l + 1, s.r - 1), z: (2, s.h - 1), "1/8\" Canvas Panel")
            try s.panelX(s.l, inward: 1, y: (s.f + 1, s.b - 1), z: (2, s.h - 1), "1/8\" Canvas Panel")
            try s.panelX(s.r, inward: -1, y: (s.f + 1, s.b - 1), z: (2, s.h - 1), "1/8\" Canvas Panel")
            try s.rail((s.l + 1, 0), (s.r - 1, 0), z: s.h - 4, "1\" Round Steel Tube", just: .center)
            try s.board(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 1), top: 7, "1\" Steel Wire Shelf")
        }
        return try p.finish()
    }
}
