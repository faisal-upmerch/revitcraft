import Foundation

// FM9C: Kids' Room & Nursery pieces (simple detail).

extension SimpleB {
    static var kids: [Piece] {
        [
            Piece("Crib", [kidsRoom], crib),
            Piece("Toddler Bed", [kidsRoom], toddlerBed),
            Piece("Kids' Bed", [kidsRoom], kidsBed),
            Piece("Loft Bed", [kidsRoom], loftBed),
            Piece("Changing Table", [kidsRoom], changingTable),
            Piece("Nursery Dresser", [kidsRoom], .casework, nurseryDresser),
            Piece("Toy Chest", [kidsRoom], toyChest),
            Piece("Toy Storage Organizer", [kidsRoom], toyStorageOrganizer),
            Piece("Kids' Desk", [kidsRoom], kidsDesk),
            Piece("Kids' Chair", [kidsRoom], kidsChair),
            Piece("Kids' Bookshelf", [kidsRoom], kidsBookshelf),
            Piece("Play Table", [kidsRoom], playTable),
            Piece("High Chair", [kidsRoom], highChair),
            Piece("Nursery Glider", [kidsRoom], nurseryGlider),
            Piece("Kids' Wardrobe", [kidsRoom], .casework, kidsWardrobe),
            Piece("Playroom Storage Unit", [kidsRoom], .casework, playroomStorageUnit),
        ]
    }

    /// Spindles (vertical bars) evenly spaced between two plan points, from z0 to z1, at most `gap` apart.
    static func bars(_ s: SBStep, from a: (Double, Double), to c: (Double, Double), z: (Double, Double), gap: Double = 2.375,
                     _ type: String = "1\" x 1\" Maple Spindle") throws {
        let len = hypot(c.0 - a.0, c.1 - a.1)
        let n = max(1, Int((len / gap).rounded(.up)) - 1)
        for k in 1...n {
            let t = Double(k) / Double(n + 1)
            try s.spindle(a.0 + (c.0 - a.0) * t, a.1 + (c.1 - a.1) * t, z: z, type)
        }
    }

    /// A standard crib (mini crib as a second type): four posts, a rail top and bottom on every side with spindles
    /// between them, a mattress platform and a crib mattress.
    static func crib() throws -> BIMModel {
        let p = try SBBuilder("Crib", .furniture, [SBSize(54, 30, 36, "Standard Crib"), SBSize(40, 26, 36, "Mini Crib")], material: "Solid Maple")
        try p.step("Posts, Rails and Spindles") { s in
            let pw = 2.0
            try s.legs(x: (s.l, s.r), y: (s.f, s.b), z: (0, s.h), "Square 2\" Maple Post")
            let rail = "3/4\" x 3\" Maple Rail"
            let (lowTop, topTop) = (13.0, s.h - 1)
            let cx = (s.l + pw / 2, s.r - pw / 2), cy = (s.f + pw / 2, s.b - pw / 2)
            for (zt) in [lowTop, topTop] {
                try s.rail((s.l + pw, cy.0), (s.r - pw, cy.0), z: zt, rail)
                try s.rail((s.r - pw, cy.1), (s.l + pw, cy.1), z: zt, rail)
                try s.rail((cx.0, cy.1 - pw / 2), (cx.0, cy.0 + pw / 2), z: zt, rail)
                try s.rail((cx.1, cy.0 + pw / 2), (cx.1, cy.1 - pw / 2), z: zt, rail)
            }
            let z = (lowTop, topTop - 3)
            try bars(s, from: (s.l + pw, cy.0), to: (s.r - pw, cy.0), z: z)
            try bars(s, from: (s.l + pw, cy.1), to: (s.r - pw, cy.1), z: z)
            try bars(s, from: (cx.0, s.f + pw), to: (cx.0, s.b - pw), z: z)
            try bars(s, from: (cx.1, s.f + pw), to: (cx.1, s.b - pw), z: z)
            try s.board(x: (s.l + pw, s.r - pw), y: (s.f + pw, s.b - pw), top: 8, "3/4\" Plywood Shelf")
            try s.board(x: (s.l + pw, s.r - pw), y: (s.f + pw, s.b - pw), top: 13, "5\" Crib Mattress")
        }
        return try p.finish()
    }

    /// A low bed for a crib mattress: posts, a headboard and footboard, guard rails at the head and a low deck.
    static func toddlerBed() throws -> BIMModel {
        let p = try SBBuilder("Toddler Bed", .furniture, [SBSize(30, 56, 28)], material: "Solid Maple")
        try p.step("Frame") { s in
            try s.bed(post: "Square 2\" Maple Post", rail: "1 1/2\" x 5 1/2\" Maple Bed Rail", rail: 9, foot: 20, panel: "3/4\" Solid Maple",
                      mattress: "5\" Crib Mattress", slat: "1\" x 3\" Bed Slat", slatCount: 9)
            // Guard rails at the head, on both sides.
            for x in [s.l + 1, s.r - 1] {
                try s.rail((x, s.b - 2), (x, s.b - 26), z: 19, "3/4\" x 3\" Maple Rail")
                try s.spindle(x, s.b - 26, z: (9, 19), "1 1/2\" x 1 1/2\" Maple Rail")
            }
        }
        return try p.finish()
    }

    /// A twin (and full) bed with a panel headboard and footboard, side rails, slats and a mattress.
    static func kidsBed() throws -> BIMModel {
        let p = try SBBuilder("Kids' Bed", .furniture, [SBSize(42, 80, 38, "Twin"), SBSize(57, 80, 38, "Full")], material: "Solid Pine")
        try p.step("Frame") { s in
            try s.bed(post: "Square 2\" Maple Post", rail: "1 1/2\" x 5 1/2\" Pine Bed Rail", rail: 13, foot: 24, panel: "3/4\" Solid Pine",
                      mattress: "8\" Mattress")
        }
        return try p.finish()
    }

    /// A twin loft bed: four tall posts, a deck on side rails with slats and a mattress, guard rails all round and a
    /// ladder on the front.
    static func loftBed() throws -> BIMModel {
        let p = try SBBuilder("Loft Bed", .furniture, [SBSize(42, 80, 68, "Twin")], material: "Solid Pine",
                              planes: [SBPlane("Deck", .z, "Height * 0.78", at: 68 * 0.78)])
        try p.step("Frame and Deck") { s in
            let pw = 3.0
            try s.legs(x: (s.l, s.r), y: (s.f, s.b), z: (0, s.h), "Square 3\" Oak Post")
            let deck = s.pos("Deck")
            let rail = "1 1/2\" x 5 1/2\" Pine Bed Rail", guardRail = "1 1/2\" x 3 1/2\" Pine Rail"
            try s.rail((s.l + pw / 2, s.b - pw), (s.l + pw / 2, s.f + pw), z: deck, rail)
            try s.rail((s.r - pw / 2, s.f + pw), (s.r - pw / 2, s.b - pw), z: deck, rail)
            try s.rail((s.l + pw, s.f + pw / 2), (s.r - pw, s.f + pw / 2), z: deck, rail)
            try s.rail((s.r - pw, s.b - pw / 2), (s.l + pw, s.b - pw / 2), z: deck, rail)
            // Guard rails: all round at the top, the front open over the ladder.
            try s.rail((s.l + pw / 2, s.b - pw), (s.l + pw / 2, s.f + pw), z: s.h - 1, guardRail)
            try s.rail((s.r - pw / 2, s.f + pw), (s.r - pw / 2, s.b - pw), z: s.h - 1, guardRail)
            try s.rail((s.l + pw, s.f + pw / 2), (s.r - pw, s.f + pw / 2), z: s.h - 1, guardRail)
            try s.rail((s.r - pw, s.b - pw / 2), (s.l + pw, s.b - pw / 2), z: s.h - 1, guardRail)
            let ix = (s.l + pw / 2 + 0.75, s.r - pw / 2 - 0.75)
            try s.slats(x: ix, y: (s.f + pw, s.b - pw), alongX: true, count: 12, top: deck - 3)
            try s.board(x: ix, y: (s.f + pw, s.b - pw), top: deck + 3, "6\" Mattress")
            // A ladder on the left side, in the plane of the side rails.
            let lx = s.l + pw / 2
            for y in [s.f + 10, s.f + 26] { try s.railYZ((y, 0), (y, deck), x: lx, "1 1/2\" x 3 1/2\" Pine Rail") }
            var z = 10.0
            while z < deck - 4 {
                try s.rail((lx, s.f + 11.75), (lx, s.f + 24.25), z: z, "1 1/4\" Round Maple Dowel", just: .center)
                z += 11
            }
        }
        return try p.finish()
    }

    /// A three-drawer chest with a guard rail round its top for the changing pad.
    static func changingTable() throws -> BIMModel {
        let p = try SBBuilder("Changing Table", .furniture, [SBSize(36, 20, 40), SBSize(42, 20, 40)], material: "Plywood",
                              planes: [SBPlane("Pad", .z, "Height - 0.1016 m", at: 36)])
        var c: SBCarcass?
        try p.step("Carcass") { s in
            c = try s.carcass(bottomAt: 4.75, top: nil)
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos("Pad"), "3/4\" Plywood Top", role: .top)
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (s.pos("Pad"), s.h), "3/4\" Plywood")
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (s.pos("Pad"), s.pos("Pad") + 1.5), "3/4\" Plywood")
            try s.board(x: (s.l + 2, s.r - 2), y: (s.f + 2, s.b - 2), top: s.pos("Pad") + 2, "2\" Leather Pad")
        }
        try p.step("Kick and Back") { s in
            try s.plinth(under: c!.bottom)
            try s.back(x: 0, z: s.h / 2 - 4)
        }
        try p.step("Drawers") { s in try s.drawers(x: 0, z: (4.75 + s.pos("Pad")) / 2, count: 3, "White Slab - Full Overlay") }
        return try p.finish()
    }

    /// A six-drawer dresser: two columns of three drawers on a toe kick.
    static func nurseryDresser() throws -> BIMModel {
        let p = try SBBuilder("Nursery Dresser", .casework, [SBSize(54, 20, 34), SBSize(60, 20, 36)], material: "Plywood")
        var c: SBCarcass?
        try p.step("Carcass") { s in c = try s.carcass(bottomAt: 4.75, top: "3/4\" Plywood Top") }
        try p.step("Kick, Back and Divider") { s in
            try s.plinth(under: c!.bottom)
            try s.back(x: 0, z: s.h / 2)
            try s.dividers(x: 0, z: s.h / 2, count: 1)
        }
        try p.step("Drawers") { s in
            try s.drawers(x: s.l / 2, z: s.h / 2, count: 3, "White Slab - Full Overlay")
            try s.drawers(x: s.r / 2, z: s.h / 2, count: 3, "White Slab - Full Overlay")
        }
        return try p.finish()
    }

    /// A pine box on a raised bottom with a lift-up lid.
    static func toyChest() throws -> BIMModel {
        let p = try SBBuilder("Toy Chest", .furniture, [SBSize(36, 18, 20), SBSize(42, 20, 22)], material: "Solid Pine")
        try p.step("Box") { s in
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (0, s.h - 0.75), "3/4\" Solid Pine")
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (0, s.h - 0.75), "3/4\" Solid Pine")
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (0, s.h - 0.75), "3/4\" Solid Pine")
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (0, s.h - 0.75), "3/4\" Solid Pine")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.75, s.b - 0.75), top: 3, "3/4\" Solid Pine Shelf", role: .bottom)
        }
        try p.step("Lid") { s in try s.lid(x: 0, y: 0) }
        return try p.finish()
    }

    /// Open cubbies in three rows, each with a low lip across its front to keep the toys in.
    static func toyStorageOrganizer() throws -> BIMModel {
        let p = try SBBuilder("Toy Storage Organizer", .furniture, [SBSize(34, 12, 30), SBSize(42, 14, 34)], material: "Solid Pine",
                              planes: [SBPlane("Shelf 1", .z, "Height * 0.3333"), SBPlane("Shelf 2", .z, "Height * 0.6667")])
        try p.step("Carcass and Shelves") { s in
            try s.carcass(bottomAt: 2.75, sides: "3/4\" Solid Pine", top: "3/4\" Plywood Top")
            for n in ["Shelf 1", "Shelf 2"] { try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos(n), "3/4\" Solid Pine Shelf") }
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        try p.step("Dividers") { s in
            for z in [s.h / 6 + 1, s.h / 2, s.h * 5 / 6] { try s.dividers(x: 0, z: z, count: 1, "3/4\" Solid Pine") }
        }
        try p.step("Lips") { s in
            for z in [2.75, s.pos("Shelf 1"), s.pos("Shelf 2")] {
                try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (z, z + 3), "1/2\" Plywood")
            }
        }
        return try p.finish()
    }

    /// A child-height desk: a top on four legs with aprons and a book shelf below.
    static func kidsDesk() throws -> BIMModel {
        let p = try SBBuilder("Kids' Desk", .furniture, [SBSize(32, 20, 22), SBSize(40, 22, 24)], material: "Solid Maple")
        try p.step("Top, Legs and Shelf") { s in
            let t = try s.table(top: "3/4\" Solid Maple Top", leg: "Square 1 1/2\" Teak", inset: 0.75, apron: "3/4\" x 3\" Maple Rail")
            try s.board(x: (t.legX.0 + t.legWidth, t.legX.1 - t.legWidth), y: (t.legY.1 - 9, t.legY.1), top: 6, "3/4\" Plywood Shelf")
        }
        return try p.finish()
    }

    /// A child's chair: 12" seat, back with two rails.
    static func kidsChair() throws -> BIMModel {
        let p = try SBBuilder("Kids' Chair", .furniture, [SBSize(14, 13, 24), SBSize(15, 14, 27)], material: "Solid Maple",
                              planes: [SBPlane("Seat", .z, "Height * 0.5")])
        try p.step("Frame") { s in
            try s.chair(seat: s.pos("Seat"), leg: "Square 1 1/4\" Maple", seatType: "3/4\" Plywood Shelf", apron: "3/4\" x 1 1/2\" Maple Rail",
                        backRails: 2, backRail: "3/4\" x 3\" Maple Rail", stretcherAt: 4, stretcher: "3/4\" x 1 1/2\" Maple Rail")
        }
        return try p.finish()
    }

    /// A front-facing book display: three sloped-front shelves with lips, low enough for a child.
    static func kidsBookshelf() throws -> BIMModel {
        let p = try SBBuilder("Kids' Bookshelf", .furniture, [SBSize(30, 12, 32), SBSize(36, 12, 40)], material: "Plywood",
                              planes: [SBPlane("Shelf 1", .z, "Height * 0.35"), SBPlane("Shelf 2", .z, "Height * 0.68")])
        try p.step("Carcass and Shelves") { s in
            try s.carcass(bottomAt: 3, top: "3/4\" Plywood Top")
            for n in ["Shelf 1", "Shelf 2"] { try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos(n), "3/4\" Plywood Shelf") }
            for z in [3.0, s.pos("Shelf 1"), s.pos("Shelf 2")] {
                try s.rail((s.l + 0.75, s.f + 0.75), (s.r - 0.75, s.f + 0.75), z: z + 2.5, "1 1/4\" Round Maple Dowel", just: .center)
            }
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (0, 2.25), "3/4\" Plywood")
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        return try p.finish()
    }

    /// A low activity table on four round legs.
    static func playTable() throws -> BIMModel {
        let p = try SBBuilder("Play Table", .furniture, [SBSize(30, 24, 20), SBSize(36, 30, 22)], material: "Solid Maple")
        try p.step("Top and Legs") { s in
            try s.table(top: "3/4\" Laminate Top", leg: "Round 1 1/4\" Maple", inset: 1.5, apron: "3/4\" x 3\" Maple Rail")
        }
        return try p.finish()
    }

    /// A tall chair with a seat at table height, a footrest, arms and a tray in front.
    static func highChair() throws -> BIMModel {
        let p = try SBBuilder("High Chair", .furniture, [SBSize(22, 24, 40)], material: "Solid Maple",
                              planes: [SBPlane("Seat", .z, "Height * 0.55")])
        try p.step("Frame") { s in
            let seat = s.pos("Seat")
            let lw = try s.chair(seat: seat, leg: "Square 1 1/4\" Maple", seatType: "3/4\" Plywood Shelf", apron: "3/4\" x 1 1/2\" Maple Rail",
                                 backRails: 3, backRail: "3/4\" x 3\" Maple Rail", stretcherAt: 6, stretcher: "3/4\" x 1 1/2\" Maple Rail",
                                 y: (s.f + 6, s.b))
            // Footrest and arms with the tray on their front ends.
            try s.rail((s.l + lw, s.f + 6 + lw / 2), (s.r - lw, s.f + 6 + lw / 2), z: seat - 9, "3/4\" x 3\" Maple Rail")
            for x in [s.l + lw / 2, s.r - lw / 2] { try s.rail((x, s.b - lw), (x, s.f + 3), z: seat + 8, "3/4\" x 1 1/2\" Maple Rail") }
            try s.board(x: (s.l, s.r), y: (s.f, s.f + 8), top: seat + 8.75, "3/4\" Laminate Top")
        }
        return try p.finish()
    }

    /// An upholstered glider: padded arms to the floor, a seat cushion on a padded base and a tall back cushion.
    static func nurseryGlider() throws -> BIMModel {
        let p = try SBBuilder("Nursery Glider", .furniture, [SBSize(30, 33, 41)], material: "Fabric")
        try p.step("Arms, Seat and Back") { s in
            let arm = 24.0
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (1.5, arm), "6\" Upholstered Panel")
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (1.5, arm), "6\" Upholstered Panel")
            try s.panelY(s.b, inward: -1, x: (s.l + 6, s.r - 6), z: (1.5, s.h), "6\" Upholstered Panel")
            try s.board(x: (s.l + 6, s.r - 6), y: (s.f, s.b - 6), top: 13, "5\" Seat Cushion")
            try s.board(x: (s.l + 6, s.r - 6), y: (s.f, s.b - 6), top: 18, "5\" Seat Cushion")
            try s.board(x: (s.l + 6, s.r - 6), y: (s.f, s.b - 6), top: 8, "5\" Seat Cushion")
            try s.board(x: (s.l + 6, s.r - 6), y: (s.f + 1, s.b - 6), top: 3, "3/4\" Plywood Shelf", role: .bottom)
            for x in [s.l + 2, s.r - 2] {
                try s.rail((x, s.f + 2), (x, s.b - 2), z: 1.5, "1 1/2\" x 1 1/2\" Oak Rail")
            }
        }
        return try p.finish()
    }

    /// A child's wardrobe: a pair of doors over two drawers, on a toe kick.
    static func kidsWardrobe() throws -> BIMModel {
        let p = try SBBuilder("Kids' Wardrobe", .casework, [SBSize(32, 20, 56), SBSize(36, 20, 60)], material: "Melamine",
                              planes: [SBPlane("Drawer Line", .z, "Height * 0.3")])
        var c: SBCarcass?
        try p.step("Carcass") { s in
            c = try s.carcass(bottomAt: 4.75, sides: "3/4\" Melamine", top: "3/4\" Laminate Top", bottom: "3/4\" Melamine Shelf")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos("Drawer Line"), "3/4\" Melamine Shelf")
        }
        try p.step("Kick and Back") { s in
            try s.plinth(under: c!.bottom, "3/4\" Melamine")
            try s.back(x: 0, z: s.h / 2)
        }
        try p.step("Doors and Drawers") { s in
            try s.door(x: 0, z: (s.pos("Drawer Line") + s.h) / 2, "White Slab - Full Overlay Pair")
            try s.drawers(x: 0, z: (4.75 + s.pos("Drawer Line")) / 2, count: 2, "White Slab - Full Overlay")
        }
        return try p.finish()
    }

    /// Two rows of three: open cubbies above, bins (drawers) left and right with an open cubby between them below.
    static func playroomStorageUnit() throws -> BIMModel {
        let p = try SBBuilder("Playroom Storage Unit", .casework, [SBSize(48, 16, 36), SBSize(54, 16, 40)], material: "Melamine",
                              planes: [SBPlane("Shelf", .z, "Height * 0.5")])
        try p.step("Carcass and Shelf") { s in
            try s.carcass(bottomAt: 2.75, sides: "3/4\" Melamine", top: "3/4\" Laminate Top", bottom: "3/4\" Melamine Shelf")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos("Shelf"), "3/4\" Melamine Shelf")
            try s.panelY(s.f + 0.75, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (0, 2), "3/4\" Melamine", role: .plinth)
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        try p.step("Dividers") { s in
            try s.dividers(x: 0, z: (2.75 + s.pos("Shelf")) / 2, count: 2, "3/4\" Melamine")
            try s.dividers(x: 0, z: (s.pos("Shelf") + s.h) / 2, count: 2, "3/4\" Melamine")
        }
        try p.step("Bins") { s in
            let z = (2.75 + s.pos("Shelf")) / 2
            try s.drawers(x: s.l + s.w / 6, z: z, count: 1, "White Slab - Full Overlay")
            try s.drawers(x: s.r - s.w / 6, z: z, count: 1, "White Slab - Full Overlay")
        }
        return try p.finish()
    }
}
