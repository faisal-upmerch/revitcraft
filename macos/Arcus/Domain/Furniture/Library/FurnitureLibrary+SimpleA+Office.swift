import Foundation

// FM9B: simple pieces for the home office.

extension FurnitureLibrary {
    static var simpleAOffice: [SA.Piece] {
        let room = ["Home Office"]
        return [
            .desk("Office Desk", rooms: room, material: "Solid Oak", sizes: [SA.Size(48, 24, 30), SA.Size(60, 30, 30)],
                  SA.DeskSpec(wood: .oak, top: SA.oakTop, left: nil, right: 3)),
            .desk("Computer Desk", rooms: room, material: "Melamine", sizes: [SA.Size(47, 24, 36), SA.Size(55, 24, 36)],
                  SA.DeskSpec(wood: .melamine, top: "3/4\" Melamine Top", left: nil, right: 0, pedestalWidth: 10, riser: 6)),
            .table("Writing Desk", rooms: room, material: "Solid Walnut", sizes: [SA.Size(42, 22, 30), SA.Size(48, 24, 30)],
                   SA.TableSpec(top: SA.walnutTop, leg: SA.roundTapered, legInset: 1, apron: SA.apron, drawer: 4.5)),
            standingDesk,
            .desk("Executive Desk", rooms: room, material: "Solid Walnut", sizes: [SA.Size(66, 30, 30), SA.Size(72, 36, 30)],
                  SA.DeskSpec(wood: .walnut, top: SA.walnutTop, left: 3, right: 3, pedestalWidth: 15)),
            ergonomicChair,
            .seat("Guest Chair", rooms: room, material: "Fabric", sizes: [SA.Size(22, 22, 34), SA.Size(24, 24, 36)],
                  SA.SeatSpec(seat: "Height * 0.47", seatType: SA.plyTop, leg: SA.sq, legInset: 0, apron: SA.apron, back: .panel("3\" Upholstered Panel"),
                              arms: "Height * 0.72", cushion: "3\" Seat Cushion")),
            .casePiece("Filing Cabinet", rooms: room, material: "Plywood", sizes: [SA.Size(16, 24, 29), SA.Size(18, 26, 30)],
                       SA.CaseSpec(wood: .veneer, topOver: ("3/4\" Oak Veneer Top", 0), base: .plinth(3), rows: [[.drawers(2)]])),
            .casePiece("Bookcase", rooms: room, material: "Solid Oak", sizes: [SA.Size(30, 12, 72), SA.Size(36, 12, 84)],
                       SA.CaseSpec(wood: .oak, topOver: (SA.oakTop, 0.5), base: .plinth(3), rows: Array(repeating: [.open], count: 5))),
            .casePiece("Desk Hutch", rooms: room, material: "Solid Oak", sizes: [SA.Size(48, 12, 36), SA.Size(60, 12, 40)],
                       SA.CaseSpec(wood: .oak, base: .none, rows: [[.door(right: false), .shelves(1), .door(right: true)], [.open]], rowLines: ["Height * 0.45"])),
            .casePiece("Printer Stand", rooms: room, .furniture, material: "Melamine", sizes: [SA.Size(20, 16, 26), SA.Size(24, 18, 28)],
                       SA.CaseSpec(wood: .melamine, base: .legs(3, SA.caster), rows: [[.open], [.drawers(1)]], rowLines: ["Height * 0.42"])),
            monitorRiser,
            .casePiece("Storage Pedestal", rooms: room, material: "Melamine", sizes: [SA.Size(16, 20, 24), SA.Size(16, 22, 28)],
                       SA.CaseSpec(wood: .melamine, base: .legs(3, SA.caster), rows: [[.drawers(1)], [.drawers(1)]], rowLines: ["Height * 0.45"])),
            .casePiece("Office Credenza", rooms: room, material: "Solid Walnut", sizes: [SA.Size(60, 20, 30), SA.Size(72, 20, 30)],
                       SA.CaseSpec(wood: .walnut, topOver: (SA.walnutTop, 0.75), base: .plinth(3), rows: [[.doors(2), .drawers(3), .doors(2)]])),
            .table("Meeting Table", rooms: room, material: "Solid Walnut", sizes: [SA.Size(72, 36, 30), SA.Size(84, 42, 30)],
                   SA.TableSpec(top: SA.walnutTop, leg: "Square 2 1/2\" Post", legInset: 4, apron: SA.apron)),
            .casePiece("Wall-Mounted Desk", rooms: room, material: "Plywood", sizes: [SA.Size(32, 14, 24), SA.Size(40, 16, 28)],
                       SA.CaseSpec(wood: .ply, base: .none, back: SA.ply14, rows: [[.flap(dropDown: true)]])),
            .casePiece("Drawer Unit", rooms: room, material: "Melamine", sizes: [SA.Size(16, 18, 30), SA.Size(20, 20, 34)],
                       SA.CaseSpec(wood: .melamine, topOver: ("3/4\" Melamine Top", 0), base: .plinth(2), rows: [[.drawers(4)]])),
        ]
    }

    /// A sit-stand desk: a laminate top on two steel columns with feet and a crossbar.
    static var standingDesk: SA.Piece {
        SA.Piece("Standing Desk", rooms: ["Home Office"], material: "Steel", sizes: [SA.Size(48, 30, 42), SA.Size(60, 30, 46)], steps: [{ b in
            let topT = try b.shelfThickness(SA.laminateTop), under = SA.T - topT, bar = "3/4\" x 1 1/2\" Steel Bar"
            try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: SA.T, SA.laminateTop, role: .top)
            for x in [SA.L + 4, SA.R - 4] {
                try b.railY((SA.F + 2, SA.B - 2), x: x, top: SA.Z + 1.5, bar)
                try b.leg(x, SA.CY, z: (SA.Z + 1.5, under - 1.5), "Square 2 1/2\" Steel")
                try b.railY((SA.F + 3, SA.B - 3), x: x, top: under, bar)
            }
            try b.railX((SA.L + 5.25, SA.R - 5.25), y: SA.CY, top: under - 1.5, bar)
        }])
    }

    /// An office chair: casters on a four-spoke base, a column, an upholstered seat and back, and arm rests.
    static var ergonomicChair: SA.Piece {
        SA.Piece("Ergonomic Chair", rooms: ["Home Office"], material: "Fabric", sizes: [SA.Size(26, 26, 42), SA.Size(28, 28, 46)],
                 planes: [SA.Plane("Seat", .z, "Height * 0.45"), SA.Plane("Arm", .z, "Height * 0.62")], steps: [{ b in
            let seat = SA.p("Seat"), tube = "1\" x 1\" Steel Tube", column = "Round 2\" Steel"
            // Casters at the ends of the spokes, the spokes into the column.
            for (x, y) in [(SA.CX, SA.F + 1), (SA.CX, SA.B - 1), (SA.L + 1, SA.CY), (SA.R - 1, SA.CY)] { try b.leg(x, y, z: (SA.Z, SA.Z + 3), SA.caster) }
            try b.railX((SA.L, SA.CX - 1), y: SA.CY, top: SA.Z + 4, tube)
            try b.railX((SA.CX + 1, SA.R), y: SA.CY, top: SA.Z + 4, tube)
            try b.railY((SA.F, SA.CY - 1), x: SA.CX, top: SA.Z + 4, tube)
            try b.railY((SA.CY + 1, SA.B), x: SA.CX, top: SA.Z + 4, tube)
            try b.leg(SA.CX, SA.CY, z: (SA.Z + 3, seat - 3.75), column)
            // The seat pan and cushion, the back on its post, the arms.
            try b.board(x: (SA.L + 3, SA.R - 3), y: (SA.F + 2, SA.B - 5), top: seat - 3, SA.plyShelf)
            try b.board(x: (SA.L + 3, SA.R - 3), y: (SA.F + 2, SA.B - 5), top: seat, "3\" Seat Cushion", role: .top)
            try b.leg(SA.CX, SA.B - 1.5, z: (seat - 3.75, SA.T - 6), "Square 1\" Steel")
            try b.railY((SA.B - 5, SA.B - 2), x: SA.CX, top: seat - 3.75 + 1, tube)
            try b.sideY(SA.B - 2, toward: -1, x: (SA.L + 3.5, SA.R - 3.5), z: (seat + 4, SA.T), "3\" Upholstered Panel")
            for x in [SA.L + 1.25, SA.R - 1.25] {
                try b.leg(x, SA.CY, z: (seat - 3.75, SA.p("Arm") - 0.75), "Square 1\" Steel")
                try b.railY((SA.F + 4, SA.B - 7), x: x, top: SA.p("Arm"), SA.slat)
            }
            try b.railX((SA.L + 1.75, SA.L + 3), y: SA.CY, top: seat - 3.75, tube)
            try b.railX((SA.R - 3, SA.R - 1.75), y: SA.CY, top: seat - 3.75, tube)
        }])
    }

    /// A monitor riser: a top on two ends.
    static var monitorRiser: SA.Piece {
        SA.Piece("Monitor Riser", rooms: ["Home Office"], material: "Solid Walnut", sizes: [SA.Size(22, 9, 4), SA.Size(27, 10, 5)], steps: [{ b in
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T - 0.75), SA.walnut)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, SA.T - 0.75), SA.walnut)
            try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: SA.T, "3/4\" Solid Walnut Shelf", role: .top)
        }])
    }
}
