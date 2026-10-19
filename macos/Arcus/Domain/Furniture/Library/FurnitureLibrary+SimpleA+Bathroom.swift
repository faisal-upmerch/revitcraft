import Foundation
import ArcusGeometry

// FM9B: simple pieces for the bathroom (the Corner Shelf is with the living room's pieces, listed under both).

extension FurnitureLibrary {
    static var simpleABathroom: [SA.Piece] {
        let room = ["Bathroom"]
        return [
            .casePiece("Vanity Cabinet", rooms: room, material: "Quartz - White", sizes: [SA.Size(36, 21, 34), SA.Size(48, 21, 34)],
                       SA.CaseSpec(wood: .paintedWhite, topOver: ("1 1/4\" Quartz Top", 0.75), base: .plinth(4), rows: [[.doors(2), .drawers(3)]],
                                   door: SA.shakerDoor, drawer: SA.slabDrawer),
                       more: [vanitySink]),
            .casePiece("Medicine Cabinet", rooms: room, material: "Mirror", sizes: [SA.Size(20, 6, 26), SA.Size(24, 6, 30)],
                       SA.CaseSpec(wood: .melamine, base: .none, rows: [[.doorsWithShelves(1, shelves: 2)]], frontMaterial: "Mirror")),
            .casePiece("Bathroom Storage Cabinet", rooms: room, material: "Painted MDF - White", sizes: [SA.Size(24, 12, 32), SA.Size(30, 14, 36)],
                       SA.CaseSpec(wood: .paintedWhite, topOver: (SA.Wood.paintedWhite.top, 0.5), base: .legs(4, SA.sq), rows: [[.open], [.doorsWithShelves(2, shelves: 1)]],
                                   rowLines: ["Height * 0.55"])),
            wallShelf,
            towelRack,
            .casePiece("Linen Cabinet", rooms: room, material: "Painted MDF - White", sizes: [SA.Size(24, 16, 72), SA.Size(30, 18, 78)],
                       SA.CaseSpec(wood: .paintedWhite, topOver: (SA.Wood.paintedWhite.top, 0.5), base: .plinth(4),
                                   rows: [[.doorsWithShelves(2, shelves: 2)], [.drawerColumns(2)], [.doorsWithShelves(2, shelves: 1)]],
                                   rowLines: ["Height * 0.5", "Height * 0.5 - 7\""], door: SA.shakerDoor, drawer: SA.shakerDrawer)),
            .seat("Bathroom Stool", rooms: room, material: "Solid Oak", sizes: [SA.Size(14, 12, 18), SA.Size(16, 12, 20)],
                  SA.SeatSpec(seat: "Height", seatType: SA.oakTop, leg: "Square 1 1/4\"", legInset: 0.75, apron: SA.apron, stretchers: 6)),
            .chest("Laundry Hamper", rooms: room, material: "Solid Pine", sizes: [SA.Size(18, 14, 24), SA.Size(22, 16, 26)],
                   SA.ChestSpec(wood: .pine, feet: (2, "Square 1 1/4\""))),
            overToiletUnit,
            .table("Bathroom Bench", rooms: room, material: "Solid Oak", sizes: [SA.Size(30, 12, 18), SA.Size(36, 14, 18)],
                   SA.TableSpec(top: SA.oakTop, leg: SA.sq, legInset: 1, apron: SA.apron, shelf: (5, "3/4\" Solid Oak Shelf"), slats: 4)),
        ]
    }

    /// The vanity's undermount sink: a hole through the counter (a void) and a ceramic bowl under it.
    static let vanitySink: SA.Piece.Step = { b in
        let r = 7.0 * SA.inch, top = b.v(SA.T), t = 1.25 * SA.inch, cy = b.v(SA.CY) - 1 * SA.inch
        let circle = (0..<24).map { k -> Vec2 in let a = 2 * Double.pi * Double(k) / 24; return Vec2(r * cos(a), cy + r * 0.75 * sin(a)) }
        var hole = FurnitureFormData(kind: .extrusion, isVoid: true, profile: circle, w0: top - t - 0.002, w1: top + 0.002)
        hole.visibleAt = [.coarse, .medium, .fine]
        // The bowl and the hole stay centred under the top, which follows the Top.
        try b.form(hole, material: nil, lock: FormLock.framing(b.model, z: .high))
        var bowl = FurnitureFormData(kind: .revolve, profile: [Vec2(0, 0), Vec2(5.5 * SA.inch, 0), Vec2(7.2 * SA.inch, 5.5 * SA.inch), Vec2(0, 5.5 * SA.inch)],
                                     w0: top - t - 5.5 * SA.inch, w1: top - t)
        bowl.axis = Vec2(0, cy)
        try b.form(bowl, material: "Ceramic - White", lock: FormLock.framing(b.model, z: .high))
    }

    /// A two-tier wall shelf with a towel bar under it, between two ends.
    static var wallShelf: SA.Piece {
        SA.Piece("Wall Shelf", rooms: ["Bathroom"], material: "Solid Oak", sizes: [SA.Size(24, 7, 14), SA.Size(30, 8, 16)],
                 planes: [SA.Plane("Lower Shelf", .z, "Height * 0.45")], steps: [{ b in
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T), SA.oak)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, SA.T), SA.oak)
            for z in [SA.p("Lower Shelf"), SA.T] { try b.board(x: (SA.L + 0.75, SA.R - 0.75), y: (SA.F, SA.B), top: z, "3/4\" Solid Oak Shelf") }
            try b.railX((SA.L + 0.75, SA.R - 0.75), y: SA.F + 1.5, top: SA.Z + 1.5, "3/4\" Dowel Rod")
            try b.sideY(SA.B, toward: -1, x: (SA.L + 0.75, SA.R - 0.75), z: (SA.T - 3, SA.T - 0.75), SA.oak)
        }])
    }

    /// A free-standing towel rack: two posts on feet and three rods.
    static var towelRack: SA.Piece {
        let planes = (1...2).map { SA.Plane("Rod \($0)", .z, "Height * \($0) / 3") }
        return SA.Piece("Towel Rack", rooms: ["Bathroom"], material: "Solid Oak", sizes: [SA.Size(24, 14, 36), SA.Size(30, 16, 40)], planes: planes, steps: [{ b in
            let post = "Square 1 1/4\"", w = 1.25
            for x in [SA.L + w / 2, SA.R - w / 2] {
                try b.leg(x, SA.CY, z: (SA.Z + 1.5, SA.T), post)
                try b.railY((SA.F, SA.B), x: x, top: SA.Z + 1.5, SA.stretcher)
            }
            for z in [SA.p("Rod 1"), SA.p("Rod 2"), SA.T - 1] {
                try b.railX((SA.L + w, SA.R - w), y: SA.CY, top: z, "3/4\" Dowel Rod")
            }
        }])
    }

    /// Storage over a toilet: two tall sides, a cabinet with doors at the top, an open shelf under it, and a rail
    /// low at the back, open below for the toilet.
    static var overToiletUnit: SA.Piece {
        SA.Piece("Over-Toilet Storage Unit", rooms: ["Bathroom"], .casework, material: "Painted MDF - White", sizes: [SA.Size(25, 9, 66), SA.Size(28, 10, 70)],
                 planes: [SA.Plane("Cabinet", .z, "Height * 0.7"), SA.Plane("Open Shelf", .z, "Height * 0.52")], steps: [{ b in
            let t = 0.75, wood = SA.Wood.paintedWhite
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T), wood.panel)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, SA.T), wood.panel)
            let inner = (SA.L + t, SA.R - t)
            try b.board(x: inner, y: (SA.F, SA.B - 0.25), top: SA.T, wood.top, role: .top)
            try b.board(x: inner, y: (SA.F, SA.B - 0.25), top: SA.p("Cabinet"), wood.shelf, role: .bottom)
            try b.sideY(SA.B, toward: -1, x: inner, z: (SA.p("Cabinet") - t, SA.T), SA.hardboard, role: .back)
            try b.board(x: inner, y: (SA.F, SA.B), top: SA.p("Open Shelf"), wood.shelf)
            try b.railX(inner, y: SA.B - 0.375, top: SA.Z + 6, SA.stretcher)
            try b.railX(inner, y: SA.B - 0.375, top: SA.p("Open Shelf") - t, SA.apron)
        }, { b in
            try b.doors(SA.CX, SA.p("Cabinet") + 6, count: 2, SA.shakerDoor, material: "Painted MDF - White")
        }])
    }
}
