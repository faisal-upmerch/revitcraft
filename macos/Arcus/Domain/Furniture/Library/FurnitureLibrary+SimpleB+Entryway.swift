import Foundation

// FM9C: Entryway & Hallway pieces (simple detail).

extension SimpleB {
    static var entryway: [Piece] {
        [
            Piece("Shoe Cabinet", [entry], .casework, shoeCabinet),
            Piece("Shoe Bench", [entry], shoeBench),
            Piece("Entryway Console", [entry], entrywayConsole),
            Piece("Coat Rack", [entry], coatRack),
            Piece("Hall Tree", [entry], hallTree),
            Piece("Umbrella Stand", [entry], umbrellaStand),
            Piece("Wall-Mounted Shelf", [entry], wallMountedShelf),
            Piece("Key Organizer", [entry], keyOrganizer),
            Piece("Storage Cubby", [entry], .casework, storageCubby),
            Piece("Hallway Cabinet", [entry], .casework, hallwayCabinet),
            Piece("Coat Stand", [entry], coatStand),
        ]
    }

    /// Two tilt-out (drop-down) bins over a toe kick, split by a fixed shelf halfway up the opening.
    static func shoeCabinet() throws -> BIMModel {
        let p = try SBBuilder("Shoe Cabinet", .casework, [SBSize(32, 12, 40), SBSize(40, 12, 48)], material: "Plywood",
                              planes: [SBPlane("Bin Line", .z, "Height / 2 + 0.06985 m", at: 40 / 2 + 2.75)])
        var c: SBCarcass?
        try p.step("Carcass") { s in
            c = try s.carcass(bottomAt: 4.75)
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos("Bin Line"), "3/4\" Plywood Shelf")
        }
        try p.step("Kick and Back") { s in
            try s.plinth(under: c!.bottom, setback: 2)
            try s.back(x: 0, z: s.h / 2)
        }
        try p.step("Tilt-Out Bins") { s in
            let mid = s.pos("Bin Line")
            try s.flap(x: 0, z: (4.75 + mid) / 2)
            try s.flap(x: 0, z: (mid + s.h) / 2)
        }
        return try p.finish()
    }

    /// A seat with a leather pad on two ends, with two slatted shoe shelves below.
    static func shoeBench() throws -> BIMModel {
        let p = try SBBuilder("Shoe Bench", .furniture, [SBSize(36, 14, 19), SBSize(48, 16, 19)], material: "Solid Oak")
        try p.step("Seat and Ends") { s in
            let seat = s.h - 2
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: seat, "1\" Solid Oak Top", role: .top)
            try s.cushion(x: (s.l + 1, s.r - 1), y: (s.f + 1, s.b - 1), z0: seat, height: 2, "Leather", crown: 0.25, radius: 1)
            try s.panelX(s.l + 1, inward: 1, y: (s.f + 1, s.b - 1), z: (0, seat - 1), "3/4\" Solid Oak")
            try s.panelX(s.r - 1, inward: -1, y: (s.f + 1, s.b - 1), z: (0, seat - 1), "3/4\" Solid Oak")
        }
        try p.step("Shoe Shelves") { s in
            for z in [3.0, 9.5] {
                try s.slats(x: (s.l + 1.75, s.r - 1.75), y: (s.f + 1.5, s.b - 1.5), alongX: true, count: 4, top: z, "3/4\" x 2 1/2\" Slat")
            }
        }
        return try p.finish()
    }

    /// A narrow table with tapered legs, aprons and a lower shelf.
    static func entrywayConsole() throws -> BIMModel {
        let p = try SBBuilder("Entryway Console", .furniture, [SBSize(48, 14, 32), SBSize(60, 16, 32)], material: "Solid Oak")
        try p.step("Top, Legs and Aprons") { s in
            let t = try s.table(top: "1\" Solid Oak Top", leg: "Square Tapered 1 3/4\"", inset: 1)
            try s.board(x: (t.legX.0 + t.legWidth, t.legX.1 - t.legWidth), y: t.legY, top: 9, "1\" Solid Oak Shelf")
        }
        return try p.finish()
    }

    /// A wall-hung board with five pegs and a shelf on top.
    static func coatRack() throws -> BIMModel {
        let p = try SBBuilder("Coat Rack", .furniture, [SBSize(36, 6, 9), SBSize(24, 6, 9)], material: "Solid Oak")
        try p.step("Board, Shelf and Pegs") { s in
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "1\" Solid Oak Shelf")
            try s.panelY(s.b, inward: -1, x: (s.l, s.r), z: (0, s.h - 1), "3/4\" Solid Oak")
            for x in [s.l + 2, s.r - 2] { try s.panelX(x - 0.375, inward: 1, y: (s.f + 1.5, s.b - 0.75), z: (s.h - 4, s.h - 1), "3/4\" Solid Oak") }
            for k in 0..<5 {
                let x = s.l + 4 + (s.w - 8) * Double(k) / 4
                try s.rail((x, s.b - 0.75), (x, s.f + 2), z: 3, "3/4\" Round Maple Peg", just: .center)
            }
        }
        return try p.finish()
    }

    /// A bench with cubbies below and a tall back with hooks and a top shelf.
    static func hallTree() throws -> BIMModel {
        let p = try SBBuilder("Hall Tree", .furniture, [SBSize(38, 16, 72), SBSize(48, 18, 76)], material: "Solid Oak")
        let seat = 19.0
        try p.step("Bench and Uprights") { s in
            try s.carcass(z: (0, seat - 1), bottomAt: 4, sides: "3/4\" Solid Oak", top: nil, bottom: "1\" Solid Oak Shelf")
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: seat, "1\" Solid Oak Top", role: .top)
            try s.panelX(s.l, inward: 1, y: (s.b - 10, s.b), z: (seat, s.h - 1), "3/4\" Solid Oak")
            try s.panelX(s.r, inward: -1, y: (s.b - 10, s.b), z: (seat, s.h - 1), "3/4\" Solid Oak")
            try s.board(x: (s.l, s.r), y: (s.b - 10, s.b), top: s.h, "1\" Solid Oak Shelf")
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (seat, s.h - 1), "3/4\" Oak Veneer Plywood")
        }
        try p.step("Cubbies and Hooks") { s in
            try s.back(x: 0, z: 10)
            try s.dividers(x: 0, z: 10, count: 2, "3/4\" Solid Oak")
            for k in 0..<4 {
                let x = s.l + 5 + (s.w - 10) * Double(k) / 3
                try s.rail((x, s.b - 0.75), (x, s.b - 4.5), z: s.h - 14, "3/4\" Round Maple Peg", just: .center)
            }
        }
        return try p.finish()
    }

    /// A round stand: a steel tube (an extrusion with its bore as a hole) on a foot plate, with a rim ring and a glass
    /// drip tray, all locked to the planes so the stand flexes.
    static func umbrellaStand() throws -> BIMModel {
        let p = try SBBuilder("Umbrella Stand", .furniture, [SBSize(10, 10, 22), SBSize(12, 12, 24)], material: "Steel")
        try p.step("Body") { s in
            let r = s.w / 2
            let all = SBStep.Lock.axes(.scale, .scale, .scale)
            try s.extrusion(s.circle((0, 0), r), w: (0, 0.6), "Steel", lock: all)
            try s.extrusion(s.circle((0, 0), r - 0.1), holes: [s.circle((0, 0), r - 0.6)], w: (0.6, s.h - 0.6), "Steel", lock: all)
            try s.extrusion(s.circle((0, 0), r), holes: [s.circle((0, 0), r - 0.8)], w: (s.h - 0.6, s.h), "Steel", lock: all)
            try s.extrusion(s.circle((0, 0), r - 0.7), w: (0.6, 1.2), "Glass", lock: all)
        }
        return try p.finish()
    }

    /// A shelf on two brackets in front of a back plate that hangs on the wall.
    static func wallMountedShelf() throws -> BIMModel {
        let p = try SBBuilder("Wall-Mounted Shelf", .furniture, [SBSize(24, 8, 6), SBSize(36, 10, 7)], material: "Solid Walnut")
        try p.step("Shelf and Brackets") { s in
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "1\" Solid Oak Shelf")
            try s.panelY(s.b, inward: -1, x: (s.l, s.r), z: (0, s.h - 1), "3/4\" Solid Walnut")
            for x in [s.l + 3, s.r - 3.75] { try s.panelX(x, inward: 1, y: (s.b - 4, s.b - 0.75), z: (1, s.h - 1), "3/4\" Solid Walnut") }
        }
        return try p.finish()
    }

    /// A small wall box: a back, sides, a top, a mail tray with a lip and a row of key hooks.
    static func keyOrganizer() throws -> BIMModel {
        let p = try SBBuilder("Key Organizer", .furniture, [SBSize(12, 4, 10), SBSize(16, 4, 12)], material: "Solid Oak")
        try p.step("Box") { s in
            try s.panelY(s.b, inward: -1, x: (s.l, s.r), z: (0, s.h), "1/2\" Plywood", role: .back)
            try s.carcass(y: (s.f, s.b - 0.5), bottomAt: 0.5, sides: "1/2\" Plywood", top: "3/4\" Plywood Top", bottom: "3/4\" Plywood Shelf")
            try s.panelY(s.f, inward: 1, x: (s.l + 0.5, s.r - 0.5), z: (0.5, 3), "1/2\" Plywood")
            for k in 0..<5 {
                let x = s.l + 2 + (s.w - 4) * Double(k) / 4
                try s.rail((x, s.b - 0.5), (x, s.f + 1), z: s.h - 3.5, "1/2\" Round Steel Rod", just: .center)
            }
        }
        return try p.finish()
    }

    /// Nine open cubbies: two fixed shelves on thirds, two EQ dividers in each row, a back.
    static func storageCubby() throws -> BIMModel {
        let p = try SBBuilder("Storage Cubby", .casework, [SBSize(36, 15, 36), SBSize(44, 15, 44)], material: "Plywood",
                              planes: [SBPlane("Shelf 1", .z, "Height * 0.3333"), SBPlane("Shelf 2", .z, "Height * 0.6667")])
        try p.step("Carcass and Shelves") { s in
            try s.carcass(bottomAt: 0.75)
            for n in ["Shelf 1", "Shelf 2"] { try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos(n), "3/4\" Plywood Shelf") }
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2) }
        try p.step("Dividers") { s in
            for z in [s.h / 6, s.h / 2, s.h * 5 / 6] { try s.dividers(x: 0, z: z, count: 2) }
        }
        return try p.finish()
    }

    /// Two drawers over a pair of doors, on a toe kick.
    static func hallwayCabinet() throws -> BIMModel {
        let p = try SBBuilder("Hallway Cabinet", .casework, [SBSize(36, 16, 34), SBSize(48, 16, 34)], material: "Plywood",
                              planes: [SBPlane("Drawer Line", .z, "Height * 0.75")])
        try p.step("Carcass") { s in
            try s.carcass(bottomAt: 4.75)
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f, s.b), top: s.pos("Drawer Line"), "3/4\" Plywood Shelf")
        }
        try p.step("Kick, Back and Divider") { s in
            if let bottom = s.tx.model.elements(.furnitureShelves).first(where: { $0.furnitureShelf?.role == .bottom })?.id { try s.plinth(under: bottom) }
            try s.back(x: 0, z: s.h / 2)
            try s.dividers(x: 0, z: (s.pos("Drawer Line") + s.h) / 2, count: 1)
        }
        try p.step("Doors and Drawers") { s in
            let zd = (s.pos("Drawer Line") + s.h) / 2
            try s.drawers(x: s.l / 2, z: zd, count: 1)
            try s.drawers(x: s.r / 2, z: zd, count: 1)
            try s.door(x: 0, z: (4.75 + s.pos("Drawer Line")) / 2, "Slab - Full Overlay Pair")
        }
        return try p.finish()
    }

    /// A turned pole on a round foot (a plate and a blended dome) with a finial and four hooks at the top (extrusions),
    /// the forms locked to the planes so the stand flexes.
    static func coatStand() throws -> BIMModel {
        let p = try SBBuilder("Coat Stand", .furniture, [SBSize(18, 18, 72), SBSize(22, 22, 76)], material: "Solid Walnut")
        try p.step("Pole, Foot and Hooks") { s in
            let r = s.w / 2
            let all = SBStep.Lock.axes(.scale, .scale, .scale)
            try s.extrusion(s.circle((0, 0), r), w: (0, 0.5), "Solid Walnut", lock: all)
            try s.blend(s.circle((0, 0), r * 0.6), s.circle((0, 0), 1.4), z: (0.5, 2.2), "Solid Walnut", lock: all)
            try s.leg(0, 0, z: (2.2, s.h - 2), "Turned 2\" Walnut")
            try s.blend(s.circle((0, 0), 1.2), s.circle((0, 0), 0.3), z: (s.h - 2, s.h), "Solid Walnut", lock: all)
            // Hooks: J shapes in the front and side elevations, 3/4" thick.
            let hook: [(Double, Double)] = [(0.9, -9), (1.4, -9), (1.4, -2.5), (4.2, -0.6), (4.6, 0.6), (4.0, 0.8), (3.8, -0.1), (0.9, -2.0)]
            for side in [1.0, -1.0] {
                try s.extrusion(hook.map { (side * $0.0, s.h + $0.1 - 4) }, plane: .xz, w: (-0.375, 0.375), "Brass", lock: all)
                try s.extrusion(hook.map { (side * $0.0, s.h + $0.1 - 6) }, plane: .yz, w: (-0.375, 0.375), "Brass", lock: all)
            }
        }
        return try p.finish()
    }
}
