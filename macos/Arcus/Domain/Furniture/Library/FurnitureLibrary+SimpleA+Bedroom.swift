import Foundation

// FM9B: simple pieces for the bedroom. Beds have their head at the Back; Width is the bed's width, Depth its length
// and Height the headboard's top.

extension FurnitureLibrary {
    static var simpleABedroom: [SA.Piece] {
        let room = ["Bedroom"]
        return [
            platformBed("Platform Bed", rooms: room, storage: false),
            platformBed("Storage Bed", rooms: ["Bedroom", "Multipurpose & Space-Saving"], storage: true),
            bunkBed,
            daybed,
            headboard,
            .casePiece("Nightstand", rooms: room, .furniture, material: "Solid Oak", sizes: [SA.Size(20, 16, 24), SA.Size(24, 18, 26)],
                       SA.CaseSpec(wood: .oak, topOver: (SA.oakTop, 0.75), base: .legs(6, SA.tapered), rows: [[.drawers(1)], [.open]], rowLines: ["Height - 7.5\""])),
            .casePiece("Chest of Drawers", rooms: room, .furniture, material: "Solid Maple", sizes: [SA.Size(34, 18, 44), SA.Size(38, 20, 50)],
                       SA.CaseSpec(wood: .maple, topOver: (SA.Wood.maple.top, 0.5), base: .plinth(4), rows: [[.drawers(5)]])),
            .casePiece("Armoire", rooms: room, .furniture, material: "Solid Walnut", sizes: [SA.Size(40, 22, 72), SA.Size(48, 24, 78)],
                       SA.CaseSpec(wood: .walnut, topOver: (SA.walnutTop, 0.75), base: .plinth(4), rows: [[.doors(2)], [.drawerColumns(2)]],
                                   rowLines: ["Height * 0.27"], door: SA.shakerDoor)),
            .table("Vanity Table", rooms: room, material: "Solid Oak", sizes: [SA.Size(42, 18, 58), SA.Size(48, 20, 62)],
                   SA.TableSpec(top: SA.oakTop, leg: SA.tapered, legInset: 1, apron: SA.apron, drawer: 4.5, topPlane: "Height * 0.52"), more: [vanityMirror]),
            .seat("Vanity Stool", rooms: room, material: "Solid Walnut", sizes: [SA.Size(18, 14, 18), SA.Size(20, 16, 19)],
                  SA.SeatSpec(seat: "Height - 3\"", seatType: "3/4\" Solid Walnut Shelf", leg: SA.roundTapered, legInset: 0.5, apron: SA.apron,
                              cushion: "3\" Seat Cushion", stretchers: 6, stretcherType: SA.roundStretcher)),
            fullLengthMirror,
            .seat("Bedroom Bench", rooms: room, material: "Fabric", sizes: [SA.Size(48, 16, 19), SA.Size(60, 18, 19)],
                  SA.SeatSpec(seat: "Height - 3\"", seatType: SA.plyTop, leg: SA.tapered, legInset: 1, apron: SA.apron, cushion: "3\" Seat Cushion")),
            .chest("Storage Chest", rooms: ["Bedroom", "Storage & Utility"], material: "Solid Pine", sizes: [SA.Size(40, 18, 20), SA.Size(48, 20, 22)],
                   SA.ChestSpec(wood: .pine, feet: (3, SA.block))),
            clothesRack,
            .casePiece("Jewelry Cabinet", rooms: room, material: "Solid Walnut", sizes: [SA.Size(16, 16, 40), SA.Size(18, 18, 44)],
                       SA.CaseSpec(wood: .walnut, topOver: ("3/4\" Solid Walnut Shelf", 0.5), base: .legs(5, SA.tapered), rows: [[.door(right: false)], [.drawers(4)]],
                                   rowLines: ["Height * 0.62"], door: SA.glassDoor)),
            blanketLadder,
            .casePiece("Bedside Shelf", rooms: room, .furniture, material: "Solid Oak", sizes: [SA.Size(16, 10, 8), SA.Size(20, 10, 10)],
                       SA.CaseSpec(wood: .oak, base: .none, back: SA.ply14, rows: [[.open]])),
        ]
    }

    /// A low bed: a solid frame on recessed feet, slats on cleats, the mattress inside the frame, and a headboard
    /// standing on the floor. The storage bed's frame is taller with two drawers in its foot end.
    static func platformBed(_ name: String, rooms: [String], storage: Bool) -> SA.Piece {
        let frameTop = storage ? 18.0 : 12.0
        return SA.Piece(name, rooms: rooms, material: "Solid Oak", sizes: [SA.Size(64, 86, 40, "Queen"), SA.Size(80, 86, 40, "King")], steps: [{ b in
            let t = 1.0, panel = "1\" Solid Oak", foot = 3.0
            let top = SA.Z + frameTop, base = SA.Z + (storage ? 2 : foot)
            // Headboard on the floor across the back; the frame's sides and foot in front of it.
            try b.sideY(SA.B, toward: -1, x: (SA.L, SA.R), z: (SA.Z, SA.T), panel)
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B - t), z: (base, top), panel)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B - t), z: (base, top), panel)
            let slatTop = top - 2.5
            if storage {
                // The drawer box under the foot: a bottom, a top the mattress rests on, the drawers' bay between them.
                try b.board(x: (SA.L + t, SA.R - t), y: (SA.F, SA.F + 26), top: base + 0.75, SA.plyShelf, role: .bottom)
                try b.board(x: (SA.L + t, SA.R - t), y: (SA.F, SA.F + 26), top: slatTop, SA.plyShelf, role: .shelf)
                try b.sideY(SA.F + 26, toward: 1, x: (SA.L + t, SA.R - t), z: (base, slatTop - 0.75), SA.ply, role: .divider)
            } else {
                try b.sideY(SA.F, toward: 1, x: (SA.L + t, SA.R - t), z: (base, top), panel)
                for (x, y) in [(SA.L + 4, SA.F + 4), (SA.R - 4, SA.F + 4), (SA.L + 4, SA.B - 6), (SA.R - 4, SA.B - 6)] {
                    try b.leg(x, y, z: (SA.Z, base), SA.block)
                }
            }
            // Cleats on the sides, slats across, the mattress.
            let front = storage ? SA.F + 26.75 : SA.F + t
            for (x, dir) in [(SA.L + t, 1.0), (SA.R - t, -1.0)] {
                try b.railY((front, SA.B - t), x: x + dir * 0.375, top: slatTop - 1, SA.cleat)
            }
            let n = 13
            let y0 = front + 2, y1 = SA.B - (t + 2)
            let length = b.v(y1) - b.v(y0)
            for k in 0..<n {
                let d = length * Double(k) / Double(n - 1) / SA.inch
                try b.railX((SA.L + t, SA.R - t), y: k < n / 2 ? y0 + d : y1 - (length / SA.inch - d), top: slatTop, SA.bedSlat)
            }
            try b.board(x: (SA.L + (t + 0.25), SA.R - (t + 0.25)), y: (SA.F + (t + 0.25), SA.B - (t + 0.25)), top: slatTop + 10, "10\" Mattress", role: .top)
        }, { b in
            // Two drawers side by side in the foot (EQ), between the bottom and the top of the box.
            guard storage else { return }
            try b.drawerColumns(SA.CX, SA.Z + (frameTop - 0.5) / 2, count: 2, material: "Solid Oak")
        }])
    }

    /// Twin over twin: four posts, two frames with slats and mattresses, guard rails round the top bunk and a ladder
    /// of rungs at the foot.
    static var bunkBed: SA.Piece {
        SA.Piece("Bunk Bed", rooms: ["Bedroom", "Kids' Room & Nursery"], material: "Solid Pine", sizes: [SA.Size(42, 81, 65, "Twin"), SA.Size(57, 79, 68, "Full")],
                 planes: [SA.Plane("Upper", .z, "Height * 0.66")], steps: [{ b in
            let spec = SA.BedSpec(post: "Square 3 1/2\" Post", railTop: 12, slats: 10, mattress: "8\" Mattress", headboard: nil)
            let layout = SA.BedLayout(spec, b)
            let p = 3.5, upper = SA.p("Upper")
            try b.legs(x: (SA.L, SA.R), y: (SA.F, SA.B), inset: p / 2, z: (SA.Z, SA.T), spec.post)
            try layout.frame(at: SA.Z + 12, inset: p, railW: 1.5, posts: true)
            try layout.frame(at: upper, inset: p, railW: 1.5, posts: true)
            // Guard rails on both sides and the head; the ladder's rungs between the foot posts.
            for x in [SA.L + p / 2, SA.R - p / 2] { try b.railY((SA.F + p, SA.B - p), x: x, top: SA.T - 1, SA.apron) }
            try b.railX((SA.L + p, SA.R - p), y: SA.B - p / 2, top: SA.T - 1, SA.apron)
            for k in 0..<4 {
                try b.railX((SA.L + p, SA.R - p), y: SA.F + p / 2, top: SA.Z + (20 + 6 * Double(k)), "1 1/4\" Round Rung")
            }
            try b.railX((SA.L + p, SA.R - p), y: SA.F + p / 2, top: SA.T - 1, "1 1/4\" Round Rung")
        }])
    }

    /// A daybed: a twin mattress on slats between a back and two arms, facing the room (Width is its length).
    static var daybed: SA.Piece {
        SA.Piece("Daybed", rooms: ["Bedroom"], material: "Solid Oak", sizes: [SA.Size(81, 42, 36, "Twin")],
                 planes: [SA.Plane("Arm", .z, "Height * 0.8"), SA.Plane("Rail", .z, "Height * 0.42")], steps: [{ b in
            let spec = SA.BedSpec(post: "Square 2 1/2\" Post", railTop: 15, slats: 12, mattress: "8\" Mattress", headboard: nil, slatsAlongX: false)
            let p = 2.5
            try b.leg(SA.L + p / 2, SA.B - p / 2, z: (SA.Z, SA.T), spec.post)
            try b.leg(SA.R - p / 2, SA.B - p / 2, z: (SA.Z, SA.T), spec.post)
            try b.leg(SA.L + p / 2, SA.F + p / 2, z: (SA.Z, SA.p("Arm")), spec.post)
            try b.leg(SA.R - p / 2, SA.F + p / 2, z: (SA.Z, SA.p("Arm")), spec.post)
            let rail = SA.p("Rail")
            try SA.BedLayout(spec, b).frame(at: rail, inset: p, railW: 1.5, posts: true)
            // The back and the arms: panels between the posts above the rails.
            try b.sideY(SA.B - (p / 2 + 0.375), toward: 1, x: (SA.L + p, SA.R - p), z: (rail, SA.T - 2), SA.oak)
            for (x, dir) in [(SA.L + (p / 2 - 0.375), 1.0), (SA.R - (p / 2 - 0.375), -1.0)] {
                try b.sideX(x, toward: dir, y: (SA.F + p, SA.B - p), z: (rail, SA.p("Arm") - 2), SA.oak)
            }
        }])
    }

    /// A headboard to fix to a bed frame: an upholstered panel between two posts that stand on the floor.
    static var headboard: SA.Piece {
        SA.Piece("Headboard", rooms: ["Bedroom"], material: "Fabric", sizes: [SA.Size(64, 4, 56, "Queen"), SA.Size(80, 4, 56, "King")], steps: [{ b in
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T), "1\" Solid Oak")
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, SA.T), "1\" Solid Oak")
            try b.sideY(SA.F, toward: 1, x: (SA.L + 1, SA.R - 1), z: (SA.Z + 22, SA.T - 1), "3\" Upholstered Panel")
            try b.sideY(SA.B, toward: -1, x: (SA.L + 1, SA.R - 1), z: (SA.Z + 22, SA.Z + 26), SA.oak)
        }])
    }

    /// The vanity table's mirror: a mirror between two posts standing on the back of the top, and a top rail.
    static let vanityMirror: SA.Piece.Step = { b in
        let top = SA.p("Table Top"), w = 1.25
        for x in [SA.L + 4, SA.R - 4] { try b.leg(x, SA.B - w / 2, z: (top, SA.T), "Square 1 1/4\"") }
        try b.railX((SA.L + (4 + w / 2), SA.R - (4 + w / 2)), y: SA.B - w / 2, top: SA.T, SA.stretcher)
        try b.sideY(SA.B - (w / 2 + 0.125), toward: 1, x: (SA.L + (4 + w / 2), SA.R - (4 + w / 2)), z: (top + 2, SA.T - 1.5), "1/4\" Mirror")
    }

    /// A free-standing floor mirror: a framed mirror between posts on feet.
    static var fullLengthMirror: SA.Piece {
        SA.Piece("Full-Length Mirror", rooms: ["Bedroom"], material: "Solid Walnut", sizes: [SA.Size(22, 14, 65), SA.Size(26, 16, 70)], steps: [{ b in
            let post = "Square 2\" Walnut", w = 2.0
            for x in [SA.L + w / 2, SA.R - w / 2] {
                try b.leg(x, SA.CY, z: (SA.Z + 1.5, SA.T), post)
                try b.railY((SA.F, SA.B), x: x, top: SA.Z + 1.5, SA.stretcher15)
            }
            let inner = (SA.L + w, SA.R - w)
            try b.railX(inner, y: SA.CY, top: SA.T, SA.apron)
            try b.railX(inner, y: SA.CY, top: SA.Z + 6, SA.apron)
            try b.sideY(SA.CY - 0.125, toward: 1, x: inner, z: (SA.Z + 6, SA.T - 3), "1/4\" Mirror")
        }])
    }

    /// A garment rack: steel uprights on feet, a hanging rod across the top and a shelf low down.
    static var clothesRack: SA.Piece {
        SA.Piece("Clothes Rack", rooms: ["Bedroom"], material: "Steel", sizes: [SA.Size(48, 18, 60), SA.Size(60, 20, 66)], steps: [{ b in
            let tube = "1\" x 1\" Steel Tube"
            for x in [SA.L + 0.5, SA.R - 0.5] {
                try b.leg(x, SA.CY, z: (SA.Z + 1, SA.T), "Round 1\" Steel")
                try b.railY((SA.F, SA.B), x: x, top: SA.Z + 1, tube)
            }
            try b.railX((SA.L + 1, SA.R - 1), y: SA.CY, top: SA.T - 1, "1 1/4\" Closet Rod")
            try b.board(x: (SA.L + 1, SA.R - 1), y: (SA.F + 2, SA.B - 2), top: SA.Z + 9, "3/4\" Solid Pine Shelf")
        }])
    }

    /// A blanket ladder: two flat stiles and round rungs on formula planes.
    static var blanketLadder: SA.Piece {
        let planes = (1...5).map { SA.Plane("Rung \($0)", .z, "Height * \($0) / 6") }
        return SA.Piece("Blanket Ladder", rooms: ["Bedroom"], material: "Solid Ash", sizes: [SA.Size(20, 2.5, 60), SA.Size(24, 2.5, 72)], planes: planes, steps: [{ b in
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (SA.Z, SA.T), SA.Wood.maple.panel)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (SA.Z, SA.T), SA.Wood.maple.panel)
            for k in 1...5 { try b.railX((SA.L + 0.75, SA.R - 0.75), y: SA.CY, top: SA.p("Rung \(k)") + 0.625, "1 1/4\" Round Rung") }
        }])
    }
}
