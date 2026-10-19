import Foundation

// FM9C: Outdoor & Balcony pieces (simple detail): teak, cedar and aluminium frames with outdoor-fabric cushions.

extension SimpleB {
    static var outdoor: [Piece] {
        [
            Piece("Outdoor Sofa", [outdoorRoom], outdoorSofa),
            Piece("Patio Chair", [outdoorRoom], patioChair),
            Piece("Outdoor Dining Table", [outdoorRoom], outdoorDiningTable),
            Piece("Outdoor Dining Chair", [outdoorRoom], outdoorDiningChair),
            Piece("Garden Bench", [outdoorRoom], gardenBench),
            Piece("Sun Lounger", [outdoorRoom], sunLounger),
            Piece("Hammock", [outdoorRoom], hammock),
            Piece("Hanging Chair", [outdoorRoom], hangingChair),
            Piece("Outdoor Coffee Table", [outdoorRoom], outdoorCoffeeTable),
            Piece("Outdoor Side Table", [outdoorRoom], outdoorSideTable),
            Piece("Picnic Table", [outdoorRoom], picnicTable),
            Piece("Patio Storage Box", [outdoorRoom], patioStorageBox),
            Piece("Outdoor Bar Table", [outdoorRoom], outdoorBarTable),
            Piece("Folding Chair", [outdoorRoom, multi], foldingChair),
            Piece("Folding Table", [outdoorRoom], foldingTable),
            Piece("Swing Bench", [outdoorRoom], swingBench),
            Piece("Adirondack Chair", [outdoorRoom], adirondackChair),
            Piece("Plant Stand", [outdoorRoom, decor], plantStand),
        ]
    }

    /// A teak lounge frame with outdoor cushions: legs in the corners (the back ones up to the top), wide arm boards on
    /// slatted sides, a slatted seat deck, back rails, and `seats` seat and back cushions.
    static func teakLounge(_ s: SBStep, seats: Int, arm: Double = 24, seat: Double = 12) throws {
        let leg = "Square 2\" Teak", rail = "1\" x 3\" Teak Rail"
        for x in [s.l + 1, s.r - 1] {
            try s.leg(x, s.f + 1, z: (0, arm), leg)
            try s.leg(x, s.b - 1, z: (0, s.h), leg)
        }
        for (x0, x1) in [(s.l, s.l + 3.5), (s.r - 3.5, s.r)] {
            try s.board(x: (x0, x1), y: (s.f, s.b - 2), top: arm + 1, "1\" Teak Top", role: .top)
        }
        for x in [s.l + 1, s.r - 1] {
            for z in [8.0, 16] { try s.rail((x, s.f + 2), (x, s.b - 2), z: z, rail) }
        }
        try s.rail((s.l + 2, s.f + 1), (s.r - 2, s.f + 1), z: seat, rail)
        try s.rail((s.r - 2, s.b - 1), (s.l + 2, s.b - 1), z: seat, rail)
        try s.slats(x: (s.l + 2, s.r - 2), y: (s.f + 2.5, s.b - 2.5), alongX: true, count: 6, top: seat, "3/4\" x 2\" Teak Slat")
        for z in [s.h - 9, s.h] { try s.rail((s.r - 2, s.b - 1), (s.l + 2, s.b - 1), z: z, rail) }
        let (x0, x1) = (s.l + 3.5, s.r - 3.5)
        let cw = (x1 - x0) / Double(seats)
        for k in 0..<seats {
            let a = x0 + cw * Double(k), c = a + cw
            try s.cushion(x: (a, c), y: (s.f + 0.5, s.b - 6.5), z0: seat, height: 5, "Outdoor Fabric")
            try s.cushion(x: (a + 0.5, c - 0.5), y: (s.b - 6.5, s.b - 2), z0: seat + 5, height: s.h - seat - 6, "Outdoor Fabric", crown: 0.75)
        }
    }

    /// A three-seat teak sofa with outdoor cushions.
    static func outdoorSofa() throws -> BIMModel {
        let p = try SBBuilder("Outdoor Sofa", .furniture, [SBSize(78, 32, 31), SBSize(90, 34, 31)], material: "Solid Teak")
        try p.step("Frame and Cushions") { s in try teakLounge(s, seats: 3) }
        return try p.finish()
    }

    /// A teak lounge chair with outdoor cushions.
    static func patioChair() throws -> BIMModel {
        let p = try SBBuilder("Patio Chair", .furniture, [SBSize(30, 32, 31), SBSize(34, 34, 31)], material: "Solid Teak")
        try p.step("Frame and Cushions") { s in try teakLounge(s, seats: 1) }
        return try p.finish()
    }

    /// A teak dining table: a solid top on square legs with aprons.
    static func outdoorDiningTable() throws -> BIMModel {
        let p = try SBBuilder("Outdoor Dining Table", .furniture, [SBSize(72, 38, 29), SBSize(60, 36, 29)], material: "Solid Teak")
        try p.step("Top, Legs and Aprons") { s in try s.table(top: "1\" Teak Top", leg: "Square 2\" Teak", inset: 1.5, apron: "1\" x 3\" Teak Rail") }
        return try p.finish()
    }

    /// A teak dining chair: slatted seat, three back rails, side stretchers.
    static func outdoorDiningChair() throws -> BIMModel {
        let p = try SBBuilder("Outdoor Dining Chair", .furniture, [SBSize(20, 22, 35), SBSize(22, 23, 36)], material: "Solid Teak",
                              planes: [SBPlane("Seat", .z, "Height * 0.5")])
        try p.step("Frame") { s in
            try s.chair(seat: s.pos("Seat"), leg: "Square 1 1/2\" Teak", seatType: "3/4\" x 2\" Teak Slat", apron: "1\" x 3\" Teak Rail", seatSlats: 6,
                        backRails: 3, backRail: "1\" x 3\" Teak Rail", stretcherAt: 6, stretcher: "1\" x 3\" Teak Rail")
        }
        return try p.finish()
    }

    /// A teak garden bench: slatted seat and back, arms on posts.
    static func gardenBench() throws -> BIMModel {
        let p = try SBBuilder("Garden Bench", .furniture, [SBSize(60, 24, 35), SBSize(48, 24, 35)], material: "Solid Teak",
                              planes: [SBPlane("Seat", .z, "Height * 0.5"), SBPlane("Arm", .z, "Height * 0.75")])
        try p.step("Frame") { s in
            let seat = s.pos("Seat")
            let lw = try s.chair(seat: seat, leg: "Square 2\" Teak", seatType: "3/4\" x 2\" Teak Slat", apron: "1\" x 3\" Teak Rail", seatSlats: 6,
                                 backRails: 0, backPosts: true, backSlats: 0, stretcherAt: 5, stretcher: "1\" x 3\" Teak Rail", x: (s.l + 1, s.r - 1))
            for k in 0..<4 { try s.rail((s.l + 1 + lw, s.b - lw / 2), (s.r - 1 - lw, s.b - lw / 2), z: seat + 5 + (s.h - seat - 5) * Double(k) / 3, "1\" x 3\" Teak Rail") }
            let arm = s.pos("Arm")
            for x in [s.l + 1 + lw / 2, s.r - 1 - lw / 2] { try s.leg(x, s.f + lw / 2, z: (seat, arm - 0.75), "Square 1 1/2\" Teak") }
            for (x0, x1) in [(s.l, s.l + 1 + lw + 0.5), (s.r - 1 - lw - 0.5, s.r)] { try s.board(x: (x0, x1), y: (s.f, s.b - lw), top: arm, "3/4\" Teak Shelf") }
        }
        return try p.finish()
    }

    /// A teak sun lounger: a slatted frame on four legs, a raised slatted back on struts and a pad. FMG1: the struts run
    /// from the hinge to the Top (cut level there) and the back slats stay evenly spaced up them as the piece flexes.
    static func sunLounger() throws -> BIMModel {
        let p = try SBBuilder("Sun Lounger", .furniture, [SBSize(28, 78, 36), SBSize(30, 84, 38)], material: "Solid Teak")
        try p.step("Frame, Back and Pad") { s in
            let rail = "1\" x 3\" Teak Rail", deck = 13.0
            try s.legs(x: (s.l + 0.5, s.r - 0.5), y: (s.f + 2, s.b - 2), z: (0, deck - 1), "Square 2\" Teak")
            for x in [s.l + 1, s.r - 1] { try s.rail((x, s.f), (x, s.b), z: deck - 0.75, rail) }
            try s.slats(x: (s.l + 1.5, s.r - 1.5), y: (s.f + 1, s.b - 30), alongX: true, spacing: 3.5, top: deck, "3/4\" x 2\" Teak Slat")
            // The back: two struts from the hinge up to the Top, slats evenly up them (EQ), propped at 60% by two struts.
            let (y0, z0, y1, z1) = (s.b - 29, deck, s.b - 6, s.h)
            for x in [s.l + 2.5, s.r - 2.5] { try s.railYZ((y0, z0), (y1, z1), x: x, rail, cuts: (nil, .horizontal)) }
            for x in [s.l + 4, s.r - 4] {
                let prop = try s.railYZ((s.b - 2, deck), (y0 + (y1 - y0) * 0.6, z0 + (z1 - z0) * 0.6 - 2), x: x, rail)
                s.keep(prop, ["end.u": (y0, y1, .y), "end.v": (z0 - 2, z1 - 2, .z)], index: 3, count: 5)
            }
            try s.raked(x: (s.l + 1.5, s.r - 1.5), from: (y0, z0), to: (y1, z1), count: 10, of: 12, lift: 1.5, "3/4\" x 2\" Teak Slat")
            try s.cushion(x: (s.l + 2, s.r - 2), y: (s.f + 1, s.b - 30), z0: deck, height: 2, "Outdoor Fabric", crown: 0.25, radius: 1)
        }
        return try p.finish()
    }

    /// A hammock on a steel stand: a base beam and feet, two raked uprights, a canvas bed hung between spreader bars on
    /// ropes (the bed is an extrusion, the stand and ropes are rails). FMG1: the uprights' outer edges run to the Left
    /// and Right, cut level top and bottom; the bed and its pillow hang from the spreader bars, which follow the Top.
    static func hammock() throws -> BIMModel {
        let p = try SBBuilder("Hammock", .furniture, [SBSize(120, 40, 46), SBSize(132, 44, 48)], material: "Canvas")
        try p.step("Stand, Ropes and Bed") { s in
            let tube = "1 1/2\" x 1 1/2\" Steel Tube"
            try s.rail((s.l + 8, 0), (s.r - 8, 0), z: 1.5, tube)
            for x in [s.l + 8, s.r - 8] { try s.rail((x, s.f), (x, s.b), z: 1.5, tube) }
            let left = try s.railXZ((s.l + 9, 1.5), (s.l, s.h - 1), y: 0, tube, cuts: (.horizontal, .horizontal))
            let right = try s.railXZ((s.r - 9, 1.5), (s.r, s.h - 1), y: 0, tube, cuts: (.horizontal, .horizontal))
            s.tx.update(left) { $0.furnitureRail?.yJustification = .right }
            s.tx.update(right) { $0.furnitureRail?.yJustification = .left }
            let (e0, e1, zEnd, sag) = (s.l + 22, s.r - 22, 34.0, 18.0)
            for x in [e0, e1] { try s.rail((x, s.b - 4), (x, s.f + 4), z: zEnd, "1 1/4\" Round Maple Dowel", just: .center) }
            try s.railXZ((e0, zEnd), (s.l + 3, s.h - 3), y: 0, "1/2\" Cotton Rope")
            try s.railXZ((e1, zEnd), (s.r - 3, s.h - 3), y: 0, "1/2\" Cotton Rope")
            // The bed: a sagging band (a catenary-like curve) extruded across the hammock's width; each half follows its
            // spreader bar, and the whole bed hangs from the Top with the bars.
            let n = 16
            var top: [(Double, Double)] = [], bottom: [(Double, Double)] = []
            for k in 0...n {
                let t = Double(k) / Double(n)
                let x = e0 + (e1 - e0) * t
                let z = sag + (zEnd - sag) * pow(2 * t - 1, 2)
                top.append((x, z + 0.5)); bottom.append((x, z - 0.5))
            }
            try s.extrusion(top + bottom.reversed(), plane: .xz, w: (s.f + 5, s.b - 5), "Canvas", lock: .axes(.span, .stretch, .high))
            try s.cushion(x: (e0 + 4, e0 + 18), y: (s.f + 8, s.b - 8), z0: 26, height: 4, "Outdoor Fabric", crown: 1, lock: .axes(.low, .stretch, .high))
        }
        return try p.finish()
    }

    /// A hanging egg chair on a stand: a cross base under a round base plate, a pole with an arm over the chair, a
    /// chain and a rattan basket (a revolve open at the front) with a seat cushion. FMG1: the base plate's sketch is
    /// locked to the planes (its edge keeps its distance in from the Right); the basket grows with Width and hangs from
    /// the Top.
    static func hangingChair() throws -> BIMModel {
        let p = try SBBuilder("Hanging Chair", .furniture, [SBSize(40, 40, 78), SBSize(36, 36, 74)], material: "Rattan")
        try p.step("Stand, Basket and Cushion") { s in
            let tube = "1 1/2\" x 1 1/2\" Steel Tube"
            try s.rail((s.l, 0), (s.r, 0), z: 1.5, tube)
            try s.rail((0, s.f), (0, -0.75), z: 1.5, tube)
            try s.rail((0, 0.75), (0, s.b), z: 1.5, tube)
            try s.revolve([(0, 0), (s.r - 4, 0), (s.r - 4, 0.5), (s.r - 5, 2), (0, 2)], z0: 1.5, "Steel", radiiTo: "Right")
            try s.leg(0, s.b - 3, z: (1.5, s.h - 1), "Round 1 1/4\" Steel")
            try s.rail((0, s.b - 3), (0, 0), z: s.h - 1, tube)
            try s.spindle(0, 0, z: (54, s.h - 2.5), "1/2\" Round Steel Rod")
            // The basket: a shell revolved from -45° to 225°, open toward the front.
            let shell: [(Double, Double)] = [(0, 0), (8, 0.5), (14, 5), (16.5, 14), (15.5, 26), (11, 34), (6, 37), (5.2, 35.8), (9.8, 33),
                                             (14, 25.5), (15, 14), (12.8, 6), (7.5, 1.6), (0, 1.2)]
            try s.revolve(shell, at: (0, 0), z0: 18, "Rattan", angles: (-45, 225), lock: .revolveProfile(.scale, nil, .high))
            try s.cushion(x: (-11, 11), y: (-9, 10), z0: 19.5, height: 4, "Outdoor Fabric", crown: 1, radius: 4, lock: .axes(.scale, .scale, .high))
        }
        return try p.finish()
    }

    /// A low teak table: a slatted top on aprons and legs, and a slatted shelf below.
    static func slattedTable(_ s: SBStep, shelf: Double = 5) throws {
        let rail = "1\" x 3\" Teak Rail"
        let (_, lw) = try s.legs(x: (s.l + 0.5, s.r - 0.5), y: (s.f + 0.5, s.b - 0.5), z: (0, s.h - 0.75), "Square 2\" Teak")
        try s.railRing(x: (s.l + 0.5, s.r - 0.5), y: (s.f + 0.5, s.b - 0.5), legWidth: lw, top: s.h - 0.75, rail)
        try s.slats(x: (s.l, s.r), y: (s.f, s.b), alongX: true, spacing: 2.5, top: s.h, "3/4\" x 2\" Teak Slat")
        try s.railRing(x: (s.l + 0.5, s.r - 0.5), y: (s.f + 0.5, s.b - 0.5), legWidth: lw, top: shelf - 0.75, rail, sides: (false, false, true, true))
        try s.slats(x: (s.l + 2.5, s.r - 2.5), y: (s.f + 1.5, s.b - 1.5), alongX: true, spacing: 3, top: shelf, "3/4\" x 2\" Teak Slat")
    }

    static func outdoorCoffeeTable() throws -> BIMModel {
        let p = try SBBuilder("Outdoor Coffee Table", .furniture, [SBSize(44, 24, 16), SBSize(52, 28, 16)], material: "Solid Teak")
        try p.step("Frame and Slats") { s in try slattedTable(s) }
        return try p.finish()
    }

    static func outdoorSideTable() throws -> BIMModel {
        let p = try SBBuilder("Outdoor Side Table", .furniture, [SBSize(20, 20, 20), SBSize(24, 24, 22)], material: "Solid Teak")
        try p.step("Frame and Slats") { s in try slattedTable(s, shelf: 6) }
        return try p.finish()
    }

    /// A cedar picnic table with attached benches on A-frame legs. FMG1: the legs stand level on the floor and meet the
    /// top's cleats level; the top and seat planks are Slats.
    static func picnicTable() throws -> BIMModel {
        let p = try SBBuilder("Picnic Table", .furniture, [SBSize(72, 60, 30), SBSize(96, 60, 30)], material: "Western Red Cedar")
        try p.step("Frame, Top and Seats") { s in
            let plank = "1 1/2\" x 5 1/2\" Cedar Plank", rail = "1 1/2\" x 3 1/2\" Cedar Rail", tw = 14.5
            try s.slats(x: (s.l, s.r), y: (-tw, tw), alongX: true, count: 5, top: s.h, plank)
            try s.slats(x: (s.l, s.r), y: (s.f, s.f + 11.5), alongX: true, count: 2, top: 17, plank)
            try s.slats(x: (s.l, s.r), y: (s.b - 11.5, s.b), alongX: true, count: 2, top: 17, plank)
            for xc in [s.l + 12, s.r - 12] {
                try s.rail((xc, tw), (xc, -tw), z: s.h - 1.5, rail)
                try s.rail((xc, s.b - 1), (xc, s.f + 1), z: 15.5, rail)
                for side in [-1.0, 1.0] {
                    let x = xc + side * 1.5
                    try s.railYZ((s.f + 9, 0), (-4, s.h - 1.5), x: x, rail, cuts: (.horizontal, .horizontal))
                    try s.railYZ((s.b - 9, 0), (4, s.h - 1.5), x: x, rail, cuts: (.horizontal, .horizontal))
                }
            }
        }
        return try p.finish()
    }

    /// A cedar deck box with a lift-up lid.
    static func patioStorageBox() throws -> BIMModel {
        let p = try SBBuilder("Patio Storage Box", .furniture, [SBSize(48, 24, 26), SBSize(56, 26, 28)], material: "Western Red Cedar")
        try p.step("Box") { s in
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (2, s.h - 0.75), "3/4\" Cedar")
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (2, s.h - 0.75), "3/4\" Cedar")
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (2, s.h - 0.75), "3/4\" Cedar")
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (2, s.h - 0.75), "3/4\" Cedar")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.75, s.b - 0.75), top: 3.5, "3/4\" Cedar Shelf", role: .bottom)
            for x in [s.l + 1.5, s.r - 1.5] { try s.rail((x, s.f + 1), (x, s.b - 1), z: 2, "3 1/2\" x 1 1/2\" Cedar Rail") }
        }
        try p.step("Lid") { s in try s.lid(x: 0, y: 0, "Cedar Slab - Lift-Up Lid") }
        return try p.finish()
    }

    /// A bar-height table: a teak top on aluminium legs with aprons and a foot-rest ring.
    static func outdoorBarTable() throws -> BIMModel {
        let p = try SBBuilder("Outdoor Bar Table", .furniture, [SBSize(30, 30, 42), SBSize(48, 30, 42)], material: "Aluminum")
        try p.step("Top, Legs and Foot Rest") { s in
            let t = try s.table(top: "1\" Teak Top", leg: "Square 1 1/2\" Steel", inset: 1, apron: "1\" x 2\" Aluminum Rail")
            try s.railRing(x: t.legX, y: t.legY, legWidth: t.legWidth, top: 11, "1\" x 2\" Aluminum Rail")
        }
        return try p.finish()
    }

    /// A wooden slat folding chair: long front legs that become the back posts, short rear legs under the seat. FMG1:
    /// the legs' outer edges run from the Front and Back at the floor, cut level; the front legs reach the Top.
    static func foldingChair() throws -> BIMModel {
        let p = try SBBuilder("Folding Chair", .furniture, [SBSize(18, 21, 32), SBSize(19, 22, 34)], material: "Solid Teak")
        try p.step("Frame") { s in
            let rail = "1\" x 3\" Teak Rail", seat = 17.5
            for x in [s.l + 0.5, s.r - 0.5] {
                let id = try s.railYZ((s.f, 0), (s.b - 6, s.h), x: x, rail, cuts: (.horizontal, .horizontal))
                s.tx.update(id) { $0.furnitureRail?.yJustification = .right }
            }
            for x in [s.l + 1.5, s.r - 1.5] {
                let id = try s.railYZ((s.b, 0), (s.f + 5.5, seat - 0.75), x: x, rail, cuts: (.horizontal, .horizontal))
                s.tx.update(id) { $0.furnitureRail?.yJustification = .left }
            }
            try s.slats(x: (s.l + 2, s.r - 2), y: (s.f + 2, s.b - 6), alongX: true, count: 5, top: seat, "3/4\" x 2\" Teak Slat")
            for z in [s.h - 1, s.h - 6.5] { try s.rail((s.l + 1, s.b - 4.5), (s.r - 1, s.b - 4.5), z: z, rail) }
            try s.rail((s.l + 1, s.f + 4.5), (s.r - 1, s.f + 4.5), z: 6, "1\" Round Steel Tube", just: .center)
        }
        return try p.finish()
    }

    /// A folding banquet table: a laminate top on a steel apron frame and two folding leg frames.
    static func foldingTable() throws -> BIMModel {
        let p = try SBBuilder("Folding Table", .furniture, [SBSize(72, 30, 29), SBSize(60, 30, 29)], material: "Steel")
        try p.step("Top and Legs") { s in
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "3/4\" Laminate Top", role: .top)
            let under = s.h - 0.75
            try s.railRing(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 1), legWidth: 0, top: under, "1\" x 1\" Steel Tube", inset: 0.5)
            for x in [s.l + 6, s.r - 6] {
                for y in [s.f + 3, s.b - 3] { try s.leg(x, y, z: (0, under - 1), "Round 1 1/4\" Steel") }
                try s.rail((x, s.f + 3.6), (x, s.b - 3.6), z: 5, "1\" Round Steel Tube", just: .center)
                try s.rail((x, s.f + 3.6), (x, s.b - 3.6), z: under - 1.5, "1\" Round Steel Tube", just: .center)
            }
        }
        return try p.finish()
    }

    /// A porch swing on an A-frame: a beam on raked legs, a slatted bench with arms hung on rods. FMG1: the legs' outer
    /// edges run from the Front and Back at the floor to the beam, cut level; the seat is Slats.
    static func swingBench() throws -> BIMModel {
        let p = try SBBuilder("Swing Bench", .furniture, [SBSize(84, 56, 80), SBSize(72, 52, 78)], material: "Western Red Cedar")
        try p.step("Frame and Bench") { s in
            let rail = "1 1/2\" x 3 1/2\" Cedar Rail", slat = "3/4\" x 3 1/2\" Cedar Slat"
            try s.rail((s.l, 0), (s.r, 0), z: s.h, "3 1/2\" x 5 1/2\" Cedar Beam")
            for x in [s.l + 2, s.r - 2] {
                let front = try s.railYZ((s.f, 0), (-3.75, s.h - 5.5), x: x, rail, cuts: (.horizontal, .horizontal))
                let back = try s.railYZ((s.b, 0), (3.75, s.h - 5.5), x: x, rail, cuts: (.horizontal, .horizontal))
                s.tx.update(front) { $0.furnitureRail?.yJustification = .right }
                s.tx.update(back) { $0.furnitureRail?.yJustification = .left }
                try s.rail((x, s.f + 9), (x, s.b - 9), z: 18, rail)
            }
            let (bx, seat) = (25.0, 22.0)
            for x in [-bx, bx] {
                try s.rail((x, -11), (x, 11), z: seat - 0.75, rail)
                try s.spindle(x, 10, z: (seat - 4.25, seat + 18), "1 1/2\" x 1 1/2\" Pine Rail")
                try s.spindle(x, -10, z: (seat, seat + 9), "1 1/2\" x 1 1/2\" Pine Rail")
                try s.rail((x, -11.5), (x, 10.75), z: seat + 10, rail)
                for y in [-9.0, 8.5] { try s.spindle(x + (x < 0 ? -1.25 : 1.25), y, z: (seat + 10, s.h - 5.5), "1/2\" Round Steel Rod") }
            }
            try s.slats(x: (-bx - 0.75, bx + 0.75), y: (-11, 9.25), alongX: true, count: 5, top: seat, slat)
            for k in 0..<4 { try s.rail((-bx + 0.75, 10.5), (bx - 0.75, 10.5), z: seat + 5 + Double(k) * 4.2, slat, just: .top) }
        }
        return try p.finish()
    }

    /// A cedar Adirondack chair: a sloping slatted seat on stringers, a raked slatted back and wide flat arms. FMG1: the
    /// stringers run from the front, cut plumb, down to the Back on the floor; the seat slats stay evenly spaced down
    /// the slope (EQ); the back slats rise to the Top, cut level.
    static func adirondackChair() throws -> BIMModel {
        let p = try SBBuilder("Adirondack Chair", .furniture, [SBSize(30, 35, 38), SBSize(32, 37, 40)], material: "Western Red Cedar")
        try p.step("Frame, Seat, Back and Arms") { s in
            let rail = "1 1/2\" x 3 1/2\" Cedar Rail", slat = "3/4\" x 3 1/2\" Cedar Slat"
            for x in [s.l + 5, s.r - 5] {
                try s.leg(x + (x < 0 ? -2 : 2), s.f + 4, z: (0, 22), "Square 1 1/2\" Cedar")
                let stringer = try s.railYZ((s.f + 1, 12.5), (s.b, 0), x: x + (x < 0 ? 1.5 : -1.5), rail, cuts: (.vertical, .vertical))
                s.tx.update(stringer) { $0.furnitureRail?.yJustification = .left }
                s.lock(stringer, ["start.u": "Front", "end.u": "Back", "end.v": "Bottom"])
            }
            let (ys, zs, ye, ze) = (s.f + 2.5, 17.0, s.b - 15, 11.5)
            try s.raked(x: (s.l + 4, s.r - 4), from: (ys, zs), to: (ye, ze), count: 6, inclusive: true, slat)
            try s.rail((s.l + 4, s.b - 14), (s.r - 4, s.b - 14), z: 22, rail)
            for (k, x) in [-8.0, -4, 0, 4, 8].enumerated() {
                let top = s.h - [3.0, 1, 0, 1, 3][k]
                try s.railYZ((s.b - 15.5, 9), (s.b - 2, top), x: x, slat, cuts: (nil, .horizontal))
            }
            for (x0, x1) in [(s.l, s.l + 5.5), (s.r - 5.5, s.r)] { try s.board(x: (x0, x1), y: (s.f + 1, s.b - 12), top: 23, "3/4\" Cedar Shelf") }
        }
        return try p.finish()
    }

    /// A teak plant stand: a top and a lower shelf on four legs with aprons.
    static func plantStand() throws -> BIMModel {
        let p = try SBBuilder("Plant Stand", .furniture, [SBSize(12, 12, 30), SBSize(15, 15, 24)], material: "Solid Teak")
        try p.step("Top, Legs and Shelf") { s in
            let t = try s.table(top: "3/4\" Teak Shelf", leg: "Square 1 1/2\" Teak", inset: 0, apron: "1\" x 3\" Teak Rail")
            try s.board(x: (t.legX.0 + t.legWidth, t.legX.1 - t.legWidth), y: (t.legY.0, t.legY.1), top: 8, "3/4\" Teak Shelf")
        }
        return try p.finish()
    }
}
