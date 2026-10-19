import Foundation

// FM9B: simple pieces for the dining room.

extension FurnitureLibrary {
    static var simpleADining: [SA.Piece] {
        let room = ["Dining Room"]
        return [
            .table("Dining Bench", rooms: room, material: "Solid Oak", sizes: [SA.Size(60, 15, 18), SA.Size(72, 15, 18)],
                   SA.TableSpec(top: SA.butcher, leg: SA.tapered, legInset: 1, apron: SA.apron, stretchers: 5, endStretchersOnly: true)),
            .casePiece("Buffet Cabinet", rooms: room, material: "Solid Walnut", sizes: [SA.Size(60, 18, 34), SA.Size(72, 20, 36)],
                       SA.CaseSpec(wood: .walnut, topOver: (SA.walnutTop, 0.75), base: .legs(7, SA.tapered),
                                   rows: [[.drawers(1), .drawers(1), .drawers(1)], [.doorsWithShelves(3, shelves: 1)]],
                                   rowLines: ["Height - 8.5\""])),
            .casePiece("China Cabinet", rooms: room, material: "Solid Oak", sizes: [SA.Size(48, 18, 78), SA.Size(60, 18, 80)],
                       SA.CaseSpec(wood: .oak, topOver: (SA.oakTop, 0.75), base: .plinth(4),
                                   rows: [[.glassDoors(2)], [.drawerColumns(2)], [.doorsWithShelves(2, shelves: 1)]],
                                   rowLines: ["Height * 0.45", "Height * 0.45 - 7\""], door: SA.shakerDoor, drawer: SA.shakerDrawer),
                       more: [chinaShelves]),
            .casePiece("Bar Cabinet", rooms: room, material: "Solid Walnut", sizes: [SA.Size(36, 18, 48), SA.Size(42, 20, 52)],
                       SA.CaseSpec(wood: .walnut, topOver: (SA.walnutTop, 0.75), base: .legs(6, "Square 2\" Walnut"),
                                   rows: [[.flap(dropDown: true)], [.doorsWithShelves(2, shelves: 1)]], rowLines: ["Height * 0.5"])),
            .cart("Bar Cart", rooms: room, material: "Steel", sizes: [SA.Size(30, 16, 32), SA.Size(34, 18, 34)],
                  SA.CartSpec(post: "Round 1\" Steel", shelf: "3/4\" Solid Walnut Shelf", shelves: 2, bottom: 8, handles: true, lips: true)),
            .seat("Bar Stool", rooms: room, material: "Solid Oak", sizes: [SA.Size(16, 16, 30), SA.Size(18, 18, 30)],
                  SA.SeatSpec(seat: "Height", seatType: SA.oakTop, leg: "Round 1 1/4\"", legInset: 1, apron: SA.apron, stretchers: 11,
                              stretcherType: SA.roundStretcher, octagon: 4)),
            .seat("Counter Stool", rooms: room, material: "Solid Walnut", sizes: [SA.Size(17, 17, 34), SA.Size(18, 18, 36)],
                  SA.SeatSpec(seat: "Height * 0.72", seatType: SA.walnutTop, leg: "Square 1 1/4\"", legInset: 0, apron: SA.apron, back: .rails(2),
                              stretchers: 9)),
            kitchenIsland,
            .table("Breakfast Table", rooms: room, material: "Solid Ash", sizes: [SA.Size(36, 36, 30), SA.Size(42, 42, 30)],
                   SA.TableSpec(top: "1\" Solid Ash Top", leg: SA.round, legInset: 3, apron: SA.apron)),
            .seat("Breakfast Stool", rooms: room, material: "Solid Ash", sizes: [SA.Size(15, 15, 24), SA.Size(16, 16, 26)],
                  SA.SeatSpec(seat: "Height", seatType: "1\" Solid Ash Top", leg: "Round 1 1/4\"", legInset: 1, apron: nil, stretchers: 8,
                              stretcherType: SA.roundStretcher, octagon: 3.5)),
            .cart("Serving Trolley", rooms: room, material: "Solid Oak", sizes: [SA.Size(32, 18, 34), SA.Size(36, 20, 36)],
                  SA.CartSpec(post: SA.sq, shelf: "3/4\" Solid Oak Shelf", shelves: 3, bottom: 7, handles: true, lips: true)),
            cornerCabinet,
            .casePiece("Wine Rack", rooms: room, .furniture, material: "Solid Pine", sizes: [SA.Size(24, 12, 36), SA.Size(36, 12, 36)],
                       SA.CaseSpec(wood: .pine, base: .none, back: nil, rows: Array(repeating: [.open, .open, .open, .open], count: 6))),
            .casePiece("Crockery Cabinet", rooms: room, material: "Solid Maple", sizes: [SA.Size(40, 16, 66), SA.Size(48, 18, 72)],
                       SA.CaseSpec(wood: .maple, topOver: (SA.Wood.maple.top, 0.75), base: .plinth(4), rows: [[.glassDoors(2)], [.open], [.doorsWithShelves(2, shelves: 1)]],
                                   rowLines: ["Height * 0.62", "Height * 0.45"]), more: [crockeryShelves]),
        ]
    }

    /// Glass shelves behind the china cabinet's glass doors.
    static let chinaShelves: SA.Piece.Step = { b in
        let t = 0.75
        for k in 1...2 {
            try b.board(x: (SA.L + 0.75 + t, SA.R - (0.75 + t)), y: (SA.F + (0.75 + 1), SA.B - 0.25), top: SA.p("Shelf Line 1") + (Double(k) * 12), SA.glassShelf, adjustable: true)
        }
    }

    /// A glass shelf behind the crockery cabinet's glass doors.
    static let crockeryShelves: SA.Piece.Step = { b in
        try b.board(x: (SA.L + 1.5, SA.R - 1.5), y: (SA.F + 1.75, SA.B - 0.25), top: SA.p("Shelf Line 1") + 11, SA.glassShelf, adjustable: true)
    }

    /// A kitchen island: a base cabinet of drawers and doors under a butcher-block top that overhangs the back for
    /// stools.
    static var kitchenIsland: SA.Piece {
        .casePiece("Kitchen Island", rooms: ["Dining Room", "Kitchen"], material: "Solid Maple", sizes: [SA.Size(60, 36, 36), SA.Size(72, 40, 36)],
                   SA.CaseSpec(wood: .ply, topOver: (SA.butcher, 1), base: .plinth(4), rows: [[.drawers(3), .doors(2)]],
                               door: SA.shakerDoor, drawer: SA.slabDrawer, backOverhang: 11))
    }

    /// A corner hutch: a square base cabinet with a door, and open triangular shelves on it between two backs (the
    /// corner at the back left).
    static var cornerCabinet: SA.Piece {
        let planes = [SA.Plane("Base Top", .z, "Height * 0.42")] + (1...2).map { SA.Plane("Hutch Shelf \($0)", .z, "Height * 0.42 + (Height * 0.58) * \($0) / 3") }
        return SA.Piece("Corner Cabinet", rooms: ["Dining Room"], .casework, material: "Solid Oak", sizes: [SA.Size(24, 24, 72), SA.Size(28, 28, 78)], planes: planes, steps: [{ b in
            let t = 0.75, top = SA.p("Base Top")
            // The base: sides, bottom on a kick, top, back.
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, top - 1), SA.oak)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, top - 1), SA.oak)
            try b.board(x: (SA.L + t, SA.R - t), y: (SA.F, SA.B - 0.25), top: SA.Z + 4.75, "3/4\" Solid Oak Shelf", role: .bottom)
            try b.sideY(SA.F + 3, toward: 1, x: (SA.L + t, SA.R - t), z: (SA.Z, SA.Z + 4), SA.oak, role: .plinth)
            try b.sideY(SA.B, toward: -1, x: (SA.L + t, SA.R - t), z: (SA.Z + 4, top - 1), SA.hardboard, role: .back)
            try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: top, SA.oakTop, role: .top)
            // The hutch: two backs in the corner and triangular shelves.
            try b.sideY(SA.B, toward: -1, x: (SA.L + t, SA.R), z: (top, SA.T), SA.oak, role: .back)
            try b.sideX(SA.L, toward: 1, y: (SA.F + 4, SA.B), z: (top, SA.T), SA.oak)
            for z in [SA.p("Hutch Shelf 1"), SA.p("Hutch Shelf 2"), SA.T] {
                try b.polygon([(SA.L + t, SA.F + 4), (SA.R, SA.B - t), (SA.L + t, SA.B - t)], top: z, "3/4\" Solid Oak Shelf")
            }
        }, { b in
            try b.door(SA.CX, SA.p("Base Top") - 12, SA.shakerDoor, material: "Solid Oak")
        }])
    }
}
