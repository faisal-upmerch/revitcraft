import Foundation

// FM9B: simple pieces for the living room.

extension FurnitureLibrary {
    static var simpleALiving: [SA.Piece] {
        let room = ["Living Room"]
        return [
            sectionalSofa,
            .sofa("Loveseat", rooms: room, sizes: [SA.Size(58, 34, 34), SA.Size(64, 36, 34)], SA.SofaSpec(cushions: 2)),
            .sofa("Recliner", rooms: room, material: "Leather", sizes: [SA.Size(36, 38, 40), SA.Size(40, 40, 42)],
                  SA.SofaSpec(seat: "Height * 0.48", armHeight: "Height * 0.62", legHeight: 3, leg: SA.block, cushions: 1, cover: "Leather", cushion: "6\" Seat Cushion")),
            .sofa("Accent Chair", rooms: room, sizes: [SA.Size(28, 30, 32), SA.Size(30, 32, 34)],
                  SA.SofaSpec(arm: 0, seat: "Height * 0.55", legHeight: 7, cushions: 1, cushion: "4\" Seat Cushion", back: 3)),
            .sofa("Lounge Chair", rooms: ["Living Room", "Outdoor & Balcony"], sizes: [SA.Size(32, 34, 30), SA.Size(36, 36, 32)],
                  SA.SofaSpec(arm: 3, seat: "Height * 0.5", armHeight: "Height * 0.7", legHeight: 6, leg: SA.tapered, cushions: 1, back: 3)),
            .seat("Rocking Chair", rooms: ["Living Room", "Kids' Room & Nursery"], material: "Solid Maple", sizes: [SA.Size(24, 32, 42), SA.Size(26, 34, 44)],
                  SA.SeatSpec(seat: "Height * 0.4", seatType: "1\" Solid Maple Top", leg: SA.round, legInset: 0.5, legInsetY: 4, apron: SA.apron, back: .slats(5),
                              arms: "Height * 0.6", cushion: "2\" Seat Pad", runners: 1.5)),
            .table("End Table", rooms: room, material: "Solid Oak", sizes: [SA.Size(22, 22, 24), SA.Size(24, 24, 26)],
                   SA.TableSpec(top: SA.oakTop, leg: SA.tapered, legInset: 1, apron: SA.apron, shelf: (8, "3/4\" Solid Oak Shelf"))),
            .casePiece("Entertainment Center", rooms: room, material: "Solid Walnut", sizes: [SA.Size(60, 18, 24), SA.Size(72, 20, 24)],
                       SA.CaseSpec(wood: .walnut, topOver: (SA.walnutTop, 0.5), base: .legs(6, "Square 2\" Walnut"),
                                   rows: [[.door(right: false), .shelves(1), .door(right: true)]])),
            .casePiece("Display Cabinet", rooms: room, material: "Solid Oak", sizes: [SA.Size(36, 16, 72), SA.Size(40, 18, 78)],
                       SA.CaseSpec(wood: .oak, topOver: (SA.oakTop, 0.75), base: .plinth(4), rows: [[.glassDoors(2)], [.glassDoors(2)], [.doors(2)]],
                                   rowLines: ["Height * 0.64", "Height * 0.34"])),
            pouf,
            .table("Bench", rooms: room, material: "Solid Oak", sizes: [SA.Size(48, 16, 18), SA.Size(60, 16, 18)],
                   SA.TableSpec(top: SA.oakTop, leg: SA.tapered, legInset: 1.5, apron: SA.apron, stretchers: 5)),
            roomDivider,
            nestingTables,
            magazineRack,
            cornerShelf,
        ]
    }

    /// An L-shaped sectional: a three-seat sofa along the back and a two-seat wing along the left, an arm at each open
    /// end, a corner seat, seat cushions and back cushions on the planes.
    static var sectionalSofa: SA.Piece {
        let wing = 38.0, a = 6.0, bk = 6.0, legH = 4.0
        let planes = [SA.Plane("Seat", .z, "Height * 0.53"), SA.Plane("Arm", .z, "Height * 0.74"),
                      SA.Plane("Cushion 1", .x, "-Width / 2 + 38\" + (Width - 44\") / 3"), SA.Plane("Cushion 2", .x, "-Width / 2 + 38\" + (Width - 44\") * 2 / 3"),
                      SA.Plane("Wing Cushion", .y, "-Depth / 2 + 6\" + (Depth - 44\") / 2")]
        return SA.Piece("Sectional Sofa", rooms: ["Living Room"], material: "Fabric", sizes: [SA.Size(112, 86, 34), SA.Size(124, 92, 34)], planes: planes, steps: [{ b in
            let base = SA.Z + legH, seat = SA.p("Seat"), deck = seat - 5, thick = "6\" Upholstered Panel", thin = "3\" Upholstered Panel"
            let cushion = "5\" Seat Cushion"
            // Legs under the corners of the L.
            for (x, y) in [(SA.L + 2, SA.F + 2), (SA.L + (wing - 2), SA.F + 2), (SA.L + 2, SA.B - 2), (SA.R - 2, SA.B - 2), (SA.R - 2, SA.B - (wing - 2))] {
                try b.leg(x, y, z: (SA.Z, base), SA.roundTapered)
            }
            // Backs along the Back and the Left; arms at the right end and the wing's front.
            try b.sideY(SA.B, toward: -1, x: (SA.L, SA.R - a), z: (base, SA.T), thick)
            try b.sideX(SA.L, toward: 1, y: (SA.F + a, SA.B - bk), z: (base, SA.T), thick)
            try b.sideX(SA.R, toward: -1, y: (SA.B - wing, SA.B), z: (base, SA.p("Arm")), thick)
            try b.sideY(SA.F, toward: 1, x: (SA.L, SA.L + wing), z: (base, SA.p("Arm")), thick)
            // Front rails and decks.
            try b.sideY(SA.B - wing, toward: 1, x: (SA.L + wing, SA.R - a), z: (base, deck), thin)
            try b.sideX(SA.L + wing, toward: -1, y: (SA.F + a, SA.B - wing), z: (base, deck), thin)
            try b.board(x: (SA.L + wing, SA.R - a), y: (SA.B - (wing - 3), SA.B - bk), top: deck, SA.plyShelf)
            try b.board(x: (SA.L + bk, SA.L + (wing - 3)), y: (SA.F + a, SA.B - bk), top: deck, SA.plyShelf)
            // Seat cushions: three along the back, the corner, two along the wing.
            let gap = 0.0625, depth = SA.B - (bk + 6 + 0.125)
            let xs = [SA.L + wing, SA.p("Cushion 1"), SA.p("Cushion 2"), SA.R - a]
            for k in 0..<3 { try b.board(x: (xs[k] + gap, xs[k + 1] - gap), y: (SA.B - wing, depth), top: seat, cushion, role: .top) }
            try b.board(x: (SA.L + (bk + 6.125), SA.L + wing - gap), y: (SA.B - wing + gap, depth), top: seat, cushion, role: .top)
            let ys = [SA.F + a, SA.p("Wing Cushion"), SA.B - wing]
            for k in 0..<2 { try b.board(x: (SA.L + (bk + 6.125), SA.L + wing), y: (ys[k] + gap, ys[k + 1] - gap), top: seat, cushion, role: .top) }
            // Back cushions against both backs.
            let backX = [SA.L + (bk + 6.0625), SA.L + wing, SA.p("Cushion 1"), SA.p("Cushion 2"), SA.R - a]
            for k in 0..<4 {
                try b.sideY(SA.B - (bk + gap), toward: -1, x: (backX[k] + gap, backX[k + 1] - gap), z: (seat + 0.125, SA.T - 1.5), thick)
            }
            let backY = [SA.F + a, SA.p("Wing Cushion"), SA.B - (bk + gap)]
            for k in 0..<2 {
                try b.sideX(SA.L + (bk + gap), toward: 1, y: (backY[k] + gap, backY[k + 1] - gap), z: (seat + 0.125, SA.T - 1.5), thick)
            }
        }])
    }

    /// A box pouf: upholstered sides round a padded top.
    static var pouf: SA.Piece {
        SA.Piece("Pouf", rooms: ["Living Room"], material: "Fabric", sizes: [SA.Size(18, 18, 16), SA.Size(22, 22, 18)], steps: [{ b in
            let side = "3\" Upholstered Panel", pad = "2\" Seat Pad"
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T - 2), side)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, SA.T - 2), side)
            try b.sideY(SA.F, toward: 1, x: (SA.L + 3, SA.R - 3), z: (SA.Z, SA.T - 2), side)
            try b.sideY(SA.B, toward: -1, x: (SA.L + 3, SA.R - 3), z: (SA.Z, SA.T - 2), side)
            try b.board(x: (SA.L + 3, SA.R - 3), y: (SA.F + 3, SA.B - 3), top: SA.Z + 1.5, SA.plyShelf, role: .bottom)
            try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: SA.T, pad, role: .top)
        }])
    }

    /// A three-panel screen: framed fabric panels between posts on feet.
    static var roomDivider: SA.Piece {
        let planes = (1...2).map { SA.Plane("Panel \($0)", .x, "-Width / 2 + Width * \($0) / 3") }
        return SA.Piece("Room Divider", rooms: ["Living Room", "Decorative & Accent"], material: "Solid Oak", sizes: [SA.Size(54, 12, 68), SA.Size(72, 12, 72)],
                        planes: planes, steps: [{ b in
            let post = "Square 1 1/4\"", w = 1.25
            let edges = [SA.L, SA.p("Panel 1"), SA.p("Panel 2"), SA.R]
            for k in 0..<3 {
                let x0 = edges[k] + (k == 0 ? w / 2 : w / 2 + 0.125), x1 = edges[k + 1] - (k == 2 ? w / 2 : w / 2 + 0.125)
                for x in [x0, x1] {
                    try b.leg(x, SA.CY, z: (SA.Z + 1.5, SA.T), post)
                    try b.railY((SA.F, SA.B), x: x, top: SA.Z + 1.5, SA.stretcher15)
                }
                let inner = (x0 + w / 2, x1 - w / 2)
                try b.railX(inner, y: SA.CY, top: SA.T, SA.stretcher)
                try b.railX(inner, y: SA.CY, top: SA.Z + 6, SA.stretcher)
                try b.sideY(SA.CY - 0.125, toward: 1, x: inner, z: (SA.Z + 6, SA.T - 1.5), "1/4\" Plywood")
            }
        }])
    }

    /// Two tables, the smaller one sliding under the larger.
    static var nestingTables: SA.Piece {
        SA.Piece("Nesting Tables", rooms: ["Living Room", "Multipurpose & Space-Saving"], material: "Solid Walnut", sizes: [SA.Size(22, 16, 22), SA.Size(24, 18, 24)],
                 steps: [{ b in
            let top = "3/4\" Solid Walnut Shelf", leg = "Square 1 1/4\"", w = 1.25
            // The large table: a top and four legs at its corners.
            try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: SA.T, top, role: .top)
            try b.legs(x: (SA.L, SA.R), y: (SA.F, SA.B), inset: w / 2, z: (SA.Z, SA.T - 0.75), leg)
            for y in [SA.F + w / 2, SA.B - w / 2] { try b.railX((SA.L + w, SA.R - w), y: y, top: SA.T - 0.75, SA.stretcher) }
            // The small one between the large one's legs, 3" lower, flush at the front.
            let x = (SA.L + (w + 0.25), SA.R - (w + 0.25)), y = (SA.F, SA.B - (w + 0.5)), z = SA.T - 3
            try b.board(x: x, y: y, top: z, top, role: .top)
            try b.legs(x: x, y: y, inset: w / 2, z: (SA.Z, z - 0.75), leg)
            for yy in [y.0 + w / 2, y.1 - w / 2] { try b.railX((x.0 + w, x.1 - w), y: yy, top: z - 0.75, SA.stretcher) }
        }])
    }

    /// A floor magazine rack: ends with a raised bottom, a centre divider and rails along the sides.
    static var magazineRack: SA.Piece {
        SA.Piece("Magazine Rack", rooms: ["Living Room"], material: "Solid Oak", sizes: [SA.Size(16, 12, 18), SA.Size(20, 13, 20)], steps: [{ b in
            let t = 0.75
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T), SA.oak)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, SA.T), SA.oak)
            try b.board(x: (SA.L + t, SA.R - t), y: (SA.F, SA.B), top: SA.Z + 3, "3/4\" Solid Oak Shelf", role: .bottom)
            try b.sideY(SA.CY - 0.375, toward: 1, x: (SA.L + t, SA.R - t), z: (SA.Z + 3, SA.T - 2), SA.oak, role: .divider)
            for y in [SA.F + 0.375, SA.B - 0.375] {
                try b.railX((SA.L + t, SA.R - t), y: y, top: SA.Z + 10, SA.stretcher)
                try b.railX((SA.L + t, SA.R - t), y: y, top: SA.Z + 6, SA.stretcher)
            }
            try b.railX((SA.L + t, SA.R - t), y: SA.CY, top: SA.T, "1 1/4\" Round Rung")
        }])
    }

    /// Triangular shelves for a corner (the corner at the back left) between two backs.
    static var cornerShelf: SA.Piece {
        let planes = (1...3).map { SA.Plane("Shelf \($0 + 1)", .z, "Height * \($0) / 4") }
        return SA.Piece("Corner Shelf", rooms: ["Living Room", "Bathroom"], material: "Solid Oak", sizes: [SA.Size(16, 16, 60), SA.Size(20, 20, 72)],
                        planes: planes, steps: [{ b in
            let t = 0.75
            try b.sideY(SA.B, toward: -1, x: (SA.L + t, SA.R), z: (SA.Z, SA.T), SA.oak, role: .back)
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T), SA.oak)
            let levels = [SA.Z + 3] + (1...3).map { SA.p("Shelf \($0 + 1)") } + [SA.T]
            for z in levels {
                try b.polygon([(SA.L + t, SA.F), (SA.R, SA.B - t), (SA.L + t, SA.B - t)], top: z, "3/4\" Solid Oak Shelf")
            }
        }])
    }
}
