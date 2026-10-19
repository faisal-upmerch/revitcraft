import Foundation

// FM9C: Multipurpose & Space-Saving pieces (simple detail).

extension SimpleB {
    static var multipurpose: [Piece] {
        [
            Piece("Sofa Bed", [multi], sofaBed),
            Piece("Murphy Bed", [multi], .casework, murphyBed),
            Piece("Folding Desk", [multi], foldingDesk),
            Piece("Folding Dining Table", [multi], foldingDiningTable),
            Piece("Extendable Dining Table", [multi], extendableDiningTable),
            Piece("Convertible Sofa", [multi], convertibleSofa),
            Piece("Lift-Top Coffee Table", [multi], liftTopCoffeeTable),
            Piece("Stackable Chair", [multi], stackableChair),
            Piece("Modular Sofa", [multi], modularSofa),
            Piece("Transforming Table", [multi], transformingTable),
            Piece("Wall-Mounted Table", [multi], wallMountedTable),
            Piece("Ottoman Bed", [multi], ottomanBed),
            Piece("Drop-Leaf Table", [multi], dropLeafTable),
            Piece("Trundle Bed", [multi], trundleBed),
            Piece("Convertible Desk", [multi], convertibleDesk),
        ]
    }

    /// An upholstered sofa: a hardwood frame on legs (or on a plinth), a padded base, padded arms and back, and
    /// `seats` seat cushions and back pillows (cushion forms locked to the planes). `modules` splits the base into
    /// separate modules, as a modular sofa's.
    static func upholsteredSofa(_ s: SBStep, seats: Int, arm: Double = 6, armHeight: Double = 25, seat: Double = 18, back: Double = 8,
                                legs: String? = "Round Tapered 1 3/4\" Oak", legHeight: Double = 4, modules: Bool = false, material: String = "Fabric") throws {
        let z0 = legs == nil ? 0.5 : legHeight
        if let legs { try s.legs(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 1), z: (0, legHeight), legs) }
        else { try s.board(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 1), top: 0.5, "3/4\" Plywood Shelf", role: .bottom) }
        try s.railRing(x: (s.l + arm, s.r - arm), y: (s.f + 1, s.b - back), legWidth: 0, top: z0 + 3.5, "1 1/2\" x 3\" Oak Rail", inset: 0.75)
        let (x0, x1) = (s.l + arm, s.r - arm)
        try s.cushion(x: (s.l, x0), y: (s.f, s.b), z0: z0, height: armHeight - z0, material, crown: 1, radius: 2.5)
        try s.cushion(x: (x1, s.r), y: (s.f, s.b), z0: z0, height: armHeight - z0, material, crown: 1, radius: 2.5)
        try s.cushion(x: (x0, x1), y: (s.b - back, s.b), z0: z0, height: s.h - 4 - z0, material, crown: 1, radius: 2.5, lock: .z(.stretch))
        let cw = (x1 - x0) / Double(seats)
        for k in 0..<seats {
            let a = x0 + cw * Double(k), c = a + cw
            if modules || k == 0 { try s.cushion(x: modules ? (a, c) : (x0, x1), y: (s.f, s.b - back), z0: z0, height: seat - 5 - z0, material, crown: 0, radius: 1, piping: false) }
            try s.cushion(x: (a, c), y: (s.f, s.b - back), z0: seat - 5, height: 5, material)
            try s.cushion(x: (a + 0.5, c - 0.5), y: (s.b - back - 6, s.b - back), z0: seat, height: s.h - seat, material, crown: 1.5, radius: 3,
                          lock: .z(.stretch))
        }
    }

    /// A sofa that opens into a bed: two seat cushions over the folded mattress, padded arms and back.
    static func sofaBed() throws -> BIMModel {
        let p = try SBBuilder("Sofa Bed", .furniture, [SBSize(76, 36, 34, "Full"), SBSize(84, 38, 34, "Queen")], material: "Fabric")
        try p.step("Frame and Cushions") { s in try upholsteredSofa(s, seats: 2, arm: 7, legHeight: 3.5) }
        return try p.finish()
    }

    /// A wall bed cabinet, closed: tall sides, a top and a plinth, the bed's underside as two face panels recessed
    /// between the sides, and a pull bar across them (open at the back: it's fixed to the wall).
    static func murphyBed() throws -> BIMModel {
        let p = try SBBuilder("Murphy Bed", .casework, [SBSize(66, 18, 88, "Queen"), SBSize(58, 18, 82, "Full")], material: "Veneer")
        var c: SBCarcass?
        try p.step("Cabinet") { s in
            c = try s.carcass(bottomAt: 4.75, sides: "3/4\" Oak Veneer Plywood", top: "3/4\" Plywood Top")
            let mid = 0.0
            try s.panelY(s.f + 1.5, inward: 1, x: (s.l + 0.75, mid - 0.0625), z: (4.75, s.h - 0.75), "3/4\" Oak Veneer Plywood")
            try s.panelY(s.f + 1.5, inward: 1, x: (mid + 0.0625, s.r - 0.75), z: (4.75, s.h - 0.75), "3/4\" Oak Veneer Plywood")
            try s.rail((s.l + 10, s.f + 0.75), (s.r - 10, s.f + 0.75), z: s.h * 0.45, "1\" Round Steel Tube", just: .center)
        }
        try p.step("Kick") { s in try s.plinth(under: c!.bottom, setback: 1.5, "3/4\" Oak Veneer Plywood") }
        return try p.finish()
    }

    /// A wall-hung box with a drop-down front that becomes the desk.
    static func foldingDesk() throws -> BIMModel {
        let p = try SBBuilder("Folding Desk", .furniture, [SBSize(30, 12, 24), SBSize(36, 14, 28)], material: "Solid Walnut")
        try p.step("Box") { s in try s.carcass(bottomAt: 0.75, sides: "3/4\" Solid Walnut", top: "3/4\" Plywood Top") }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        try p.step("Drop Front") { s in try s.flap(x: 0, z: s.h / 2, "Walnut Slab - Drop-Down") }
        return try p.finish()
    }

    /// A gateleg table, open: a narrow centre top on four legs, two leaves, each held by a swing-out gate leg.
    static func foldingDiningTable() throws -> BIMModel {
        let p = try SBBuilder("Folding Dining Table", .furniture, [SBSize(60, 36, 30), SBSize(72, 40, 30)], material: "Solid Oak")
        try p.step("Tops, Legs and Gates") { s in
            let top = "1\" Solid Oak Top", leg = "Square 1 1/2\"", rail = "3/4\" x 3\" Apron", c = 9.0
            for (x0, x1) in [(s.l, -c), (-c, c), (c, s.r)] { try s.board(x: (x0, x1), y: (s.f, s.b), top: s.h, top, role: .top) }
            let under = s.h - 1
            let (_, lw) = try s.legs(x: (-c + 0.5, c - 0.5), y: (s.f + 2, s.b - 2), z: (0, under), "Square 1 1/2\"")
            try s.railRing(x: (-c + 0.5, c - 0.5), y: (s.f + 2, s.b - 2), legWidth: lw, top: under, rail)
            try s.railRing(x: (-c + 0.5, c - 0.5), y: (s.f + 2, s.b - 2), legWidth: lw, top: 4, rail, sides: (false, false, true, true))
            for (xg, xh) in [(s.l + 5, -c + 0.5 + lw), (s.r - 5, c - 0.5 - lw)] {
                try s.leg(xg, 0, z: (0, under), leg)
                try s.rail((xh, 0), (xg + (xg < 0 ? 0.75 : -0.75), 0), z: under, rail)
                try s.rail((xh, 0), (xg + (xg < 0 ? 0.75 : -0.75), 0), z: 7, rail)
            }
        }
        return try p.finish()
    }

    /// An extending table with its leaf in: two top halves and a centre leaf on legs and aprons.
    static func extendableDiningTable() throws -> BIMModel {
        let p = try SBBuilder("Extendable Dining Table", .furniture, [SBSize(78, 40, 30), SBSize(96, 42, 30)], material: "Solid Walnut")
        try p.step("Tops, Legs and Aprons") { s in
            let top = "1 1/4\" Solid Walnut Top", c = 9.0
            for (x0, x1) in [(s.l, -c), (-c, c), (c, s.r)] { try s.board(x: (x0, x1), y: (s.f, s.b), top: s.h, top, role: .top) }
            let under = s.h - 1.25
            let (_, lw) = try s.legs(x: (s.l + 2, s.r - 2), y: (s.f + 2, s.b - 2), z: (0, under), "Square 2\" Oak")
            try s.railRing(x: (s.l + 2, s.r - 2), y: (s.f + 2, s.b - 2), legWidth: lw, top: under, "3/4\" x 3\" Apron")
        }
        return try p.finish()
    }

    /// A futon: an oak frame with solid arms, a slatted seat and back rails, a folded futon mattress as seat and back.
    static func convertibleSofa() throws -> BIMModel {
        let p = try SBBuilder("Convertible Sofa", .furniture, [SBSize(80, 34, 33, "Full"), SBSize(86, 36, 33, "Queen")], material: "Solid Oak")
        try p.step("Frame and Mattress") { s in
            let rail = "1 1/2\" x 3\" Oak Rail", seat = 11.0
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (0, 24), "1\" Solid Oak")
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (0, 24), "1\" Solid Oak")
            for x in [s.l + 2, s.r - 2] { try s.leg(x, s.b - 2, z: (0, s.h), "Square 2\" Oak") }
            try s.rail((s.l + 1, s.f + 1.5), (s.r - 1, s.f + 1.5), z: seat, rail)
            try s.rail((s.r - 3, s.b - 6), (s.l + 3, s.b - 6), z: seat, rail)
            try s.slats(x: (s.l + 1, s.r - 1), y: (s.f + 3.5, s.b - 7.5), alongX: true, count: 6, top: seat - 0.5, "1\" x 3\" Bed Slat")
            for z in [seat + 8, s.h] { try s.rail((s.r - 3, s.b - 2), (s.l + 3, s.b - 2), z: z, rail) }
            try s.cushion(x: (s.l + 1.25, s.r - 1.25), y: (s.f + 1, s.b - 6), z0: seat, height: 6, "Fabric", crown: 0.75, radius: 3)
            try s.cushion(x: (s.l + 1.25, s.r - 1.25), y: (s.b - 9, s.b - 3), z0: seat + 6, height: s.h - seat - 7, "Fabric", crown: 0.75, radius: 3)
        }
        return try p.finish()
    }

    /// A box coffee table on feet whose top lifts up (a lift-up lid over the storage).
    static func liftTopCoffeeTable() throws -> BIMModel {
        let p = try SBBuilder("Lift-Top Coffee Table", .furniture, [SBSize(44, 22, 18), SBSize(48, 24, 19)], material: "Solid Walnut")
        try p.step("Box and Feet") { s in
            let wood = "3/4\" Solid Walnut", rim = s.h - 0.75
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (2, rim), wood)
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (2, rim), wood)
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (2, rim), wood)
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (2, rim), wood)
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.75, s.b - 0.75), top: 7, "3/4\" Plywood Shelf", role: .bottom)
            try s.legs(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 1), z: (0, 2), "Square 2\" Oak")
        }
        try p.step("Lift Top") { s in try s.lid(x: 0, y: 0, "Walnut Slab - Lift-Up Lid") }
        return try p.finish()
    }

    /// A stacking chair: a square steel-tube frame, a plywood seat and back.
    static func stackableChair() throws -> BIMModel {
        let p = try SBBuilder("Stackable Chair", .furniture, [SBSize(18, 20, 31), SBSize(19, 21, 32)], material: "Steel",
                              planes: [SBPlane("Seat", .z, "Height * 0.58")])
        try p.step("Frame, Seat and Back") { s in
            let seat = s.pos("Seat")
            let lw = try s.chair(seat: seat, leg: "Square 1\" Steel", seatType: "3/4\" Plywood Shelf", apron: "1\" x 1\" Steel Tube", backRails: 0, backPosts: true)
            try s.panelY(s.b - lw / 2 + 0.25, inward: -1, x: (s.l + lw, s.r - lw), z: (seat + 6, s.h - 0.5), "1/2\" Plywood")
        }
        return try p.finish()
    }

    /// A three-module sofa on a low plinth: separate module bases and cushions, arms at the ends.
    static func modularSofa() throws -> BIMModel {
        let p = try SBBuilder("Modular Sofa", .furniture, [SBSize(102, 38, 30), SBSize(120, 40, 30)], material: "Fabric")
        try p.step("Plinth, Modules and Cushions") { s in try upholsteredSofa(s, seats: 3, arm: 6, armHeight: 23, seat: 17, back: 9, legs: "Square 1 1/2\" Walnut", legHeight: 1.5, modules: true) }
        return try p.finish()
    }

    /// A coffee table whose top lifts to dining height: a carcass base with a shelf, the fixed top and the lift top
    /// on steel brackets.
    static func transformingTable() throws -> BIMModel {
        let p = try SBBuilder("Transforming Table", .furniture, [SBSize(48, 24, 22), SBSize(52, 26, 22)], material: "Solid Oak")
        try p.step("Base, Tops and Brackets") { s in
            let lower = s.h - 4
            try s.carcass(z: (0, lower), bottomAt: 3, sides: "3/4\" Solid Oak", top: "3/4\" Plywood Top", bottom: "3/4\" Plywood Shelf")
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "1\" Solid Oak Top", role: .top)
            for x in [s.l + 10, s.r - 10] {
                for y in [s.f + 4, s.b - 4] { try s.spindle(x, y, z: (lower, s.h - 1), "1\" x 1\" Steel Tube") }
                try s.rail((x, s.f + 4.5), (x, s.b - 4.5), z: s.h - 1, "1\" x 1\" Steel Tube")
            }
        }
        try p.step("Back") { s in try s.back(x: 0, z: (3 + s.h - 4) / 2) }
        return try p.finish()
    }

    /// A fold-down wall table, open: a wall cleat, the top, two fold-out brackets under it and a fold-down leg frame at
    /// the front.
    static func wallMountedTable() throws -> BIMModel {
        let p = try SBBuilder("Wall-Mounted Table", .furniture, [SBSize(36, 20, 30), SBSize(48, 24, 30)], material: "Solid Oak")
        try p.step("Cleat, Top and Brackets") { s in
            try s.panelY(s.b, inward: -1, x: (s.l, s.r), z: (s.h - 7, s.h - 1), "3/4\" Solid Oak")
            try s.board(x: (s.l, s.r), y: (s.f, s.b - 0.75), top: s.h, "1\" Solid Oak Top", role: .top)
            for x in [s.l + 6, s.r - 6.75] { try s.panelX(x, inward: 1, y: (s.f + 4, s.b - 0.75), z: (s.h - 9, s.h - 1), "3/4\" Solid Oak") }
            for x in [s.l + 2, s.r - 2] { try s.leg(x, s.f + 2, z: (0, s.h - 1), "Square 1 1/2\"") }
            try s.rail((s.l + 2.75, s.f + 2), (s.r - 2.75, s.f + 2), z: 6, "3/4\" x 1 1/2\" Stretcher")
        }
        return try p.finish()
    }

    /// An upholstered storage bed: a padded box base with a lift-up slatted platform, a tall padded headboard and a
    /// mattress.
    static func ottomanBed() throws -> BIMModel {
        let p = try SBBuilder("Ottoman Bed", .furniture, [SBSize(64, 86, 48, "Queen"), SBSize(80, 86, 48, "King")], material: "Fabric")
        try p.step("Base and Headboard") { s in
            let up = "4\" Upholstered Panel", rim = 16.0
            try s.panelY(s.b, inward: -1, x: (s.l, s.r), z: (0, s.h), "6\" Upholstered Panel")
            try s.panelX(s.l, inward: 1, y: (s.f, s.b - 6), z: (1, rim), up)
            try s.panelX(s.r, inward: -1, y: (s.f, s.b - 6), z: (1, rim), up)
            try s.panelY(s.f, inward: 1, x: (s.l + 4, s.r - 4), z: (1, rim), up)
            for (x0, x1) in [(s.l + 4, 0.0), (0.0, s.r - 4)] { try s.board(x: (x0, x1), y: (s.f + 4, s.b - 6), top: 2.5, "3/4\" Plywood Shelf", role: .bottom) }
            try s.slats(x: (s.l + 4, s.r - 4), y: (s.f + 4, s.b - 6), alongX: true, count: 14, top: rim, "1\" x 3\" Bed Slat")
            try s.mattress(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 6.5), top: rim + 10, thickness: 10)
        }
        return try p.finish()
    }

    /// A drop-leaf table with its leaves down: a centre top on legs and aprons, the leaves hanging at the ends.
    static func dropLeafTable() throws -> BIMModel {
        let p = try SBBuilder("Drop-Leaf Table", .furniture, [SBSize(38, 36, 30), SBSize(46, 42, 30)], material: "Solid Oak")
        try p.step("Top, Leaves, Legs and Aprons") { s in
            try s.board(x: (s.l + 1, s.r - 1), y: (s.f, s.b), top: s.h, "1\" Solid Oak Top", role: .top)
            for (x, d) in [(s.l, 1.0), (s.r, -1.0)] { try s.panelX(x, inward: d, y: (s.f, s.b), z: (s.h - 14, s.h - 1.25), "1\" Solid Oak") }
            let under = s.h - 1
            let (_, lw) = try s.legs(x: (s.l + 4, s.r - 4), y: (s.f + 2, s.b - 2), z: (0, under), "Round Tapered 1 3/4\" Oak")
            try s.railRing(x: (s.l + 4, s.r - 4), y: (s.f + 2, s.b - 2), legWidth: lw, top: under, "3/4\" x 3\" Apron")
        }
        return try p.finish()
    }

    /// A twin bed with a trundle: a panel headboard and footboard, raised side rails, slats and a mattress, and a
    /// rolling trundle box with its own mattress underneath.
    static func trundleBed() throws -> BIMModel {
        let p = try SBBuilder("Trundle Bed", .furniture, [SBSize(42, 80, 36, "Twin")], material: "Solid Maple")
        try p.step("Bed") { s in
            try s.bed(post: "Square 2\" Maple Post", rail: "1 1/2\" x 5 1/2\" Maple Bed Rail", rail: 19, foot: 26, panel: "3/4\" Solid Maple", mattress: 8)
        }
        try p.step("Trundle") { s in
            let (x0, x1, y0, y1, z0, z1) = (s.l + 3, s.r - 3, s.f + 2.5, s.b - 3, 2.0, 8.0)
            try s.panelX(x0, inward: 1, y: (y0 + 0.75, y1), z: (z0, z1), "3/4\" Plywood")
            try s.panelX(x1, inward: -1, y: (y0 + 0.75, y1), z: (z0, z1), "3/4\" Plywood")
            try s.panelY(y0, inward: 1, x: (x0, x1), z: (z0, z1), "3/4\" Solid Maple")
            try s.panelY(y1, inward: -1, x: (x0 + 0.75, x1 - 0.75), z: (z0, z1), "3/4\" Plywood")
            try s.board(x: (x0 + 0.75, x1 - 0.75), y: (y0 + 0.75, y1 - 0.75), top: z0 + 1.5, "3/4\" Plywood Shelf", role: .bottom)
            for x in [x0 + 2, x1 - 2] { for y in [y0 + 3, y1 - 3] { try s.leg(x, y, z: (0, z0), "Caster 2\"") } }
            try s.mattress(x: (x0 + 1, x1 - 1), y: (y0 + 1, y1 - 1), top: 13.5, thickness: 5)
        }
        return try p.finish()
    }

    /// A secretary desk: two drawers below, a drop-down writing front above, on a toe kick.
    static func convertibleDesk() throws -> BIMModel {
        let p = try SBBuilder("Convertible Desk", .furniture, [SBSize(32, 18, 42), SBSize(36, 20, 44)], material: "Solid Walnut",
                              planes: [SBPlane("Desk Line", .z, "Height * 0.5")])
        var c: SBCarcass?
        try p.step("Carcass") { s in
            c = try s.carcass(bottomAt: 4.75, sides: "3/4\" Solid Walnut", top: "1 1/4\" Solid Walnut Top")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos("Desk Line"), "3/4\" Plywood Shelf")
        }
        try p.step("Kick and Back") { s in
            try s.plinth(under: c!.bottom, "3/4\" Solid Walnut")
            try s.back(x: 0, z: s.h / 2)
        }
        try p.step("Drawers and Writing Front") { s in
            let dl = s.pos("Desk Line")
            try s.drawers(x: 0, z: (4.75 + dl) / 2, count: 2, "Walnut Slab - Full Overlay")
            try s.flap(x: 0, z: (dl + s.h) / 2, "Walnut Slab - Drop-Down")
        }
        return try p.finish()
    }
}
