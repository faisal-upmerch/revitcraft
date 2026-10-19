import Foundation

// FM9B: simple pieces for the kitchen (the Kitchen Island is with the dining room's pieces, listed under both).

extension FurnitureLibrary {
    static var simpleAKitchen: [SA.Piece] {
        let room = ["Kitchen"]
        return [
            .casePiece("Kitchen Cart", rooms: room, .furniture, material: "Solid Maple", sizes: [SA.Size(30, 18, 36), SA.Size(36, 20, 36)],
                       SA.CaseSpec(wood: .maple, topOver: (SA.butcher, 1), base: .legs(3, SA.caster), back: SA.ply14, rows: [[.drawers(1)], [.open]],
                                   rowLines: ["Height - 9.5\""])),
            .rack("Kitchen Rack", rooms: room, material: "Steel", sizes: [SA.Size(36, 14, 54), SA.Size(48, 18, 72)],
                  SA.RackSpec(post: "Square 1\" Steel", shelf: "1/8\" Steel Shelf", shelves: 4, bottom: 6)),
            .casePiece("Open Shelving Unit", rooms: room, .furniture, material: "Solid Oak", sizes: [SA.Size(30, 12, 60), SA.Size(36, 14, 72)],
                       SA.CaseSpec(wood: .oak, base: .none, back: nil, rows: Array(repeating: [.open], count: 5))),
            .casePiece("Utility Cabinet", rooms: room, material: "Melamine", sizes: [SA.Size(30, 18, 72), SA.Size(36, 24, 84)],
                       SA.CaseSpec(wood: .melamine, base: .plinth(4), rows: [[.doorsWithShelves(2, shelves: 2)], [.doorsWithShelves(2, shelves: 1)]],
                                   rowLines: ["Height * 0.42"])),
            .casePiece("Microwave Stand", rooms: room, .furniture, material: "Solid Oak", sizes: [SA.Size(24, 16, 36), SA.Size(30, 18, 40)],
                       SA.CaseSpec(wood: .oak, topOver: (SA.oakTop, 0.5), base: .legs(4, SA.sq), rows: [[.open], [.doorsWithShelves(2, shelves: 1)]],
                                   rowLines: ["Height * 0.6"])),
            .rack("Baker's Rack", rooms: room, material: "Steel", sizes: [SA.Size(36, 16, 60), SA.Size(48, 18, 72)],
                  SA.RackSpec(post: "Round 1\" Steel", shelf: "1\" Solid Pine Shelf", shelves: 4, bottom: 8)),
            .cart("Storage Trolley", rooms: room, material: "Steel", sizes: [SA.Size(18, 12, 30), SA.Size(20, 14, 34)],
                  SA.CartSpec(post: "Square 1\" Steel", shelf: "1/8\" Steel Shelf", shelves: 3, bottom: 6, handles: true, lips: true, lip: "3/4\" x 1 1/2\" Steel Bar")),
            .table("Breakfast Bar", rooms: room, material: "Solid Maple", sizes: [SA.Size(48, 16, 42), SA.Size(60, 18, 42)],
                   SA.TableSpec(top: SA.butcher, leg: SA.sq, legInset: 1.5, apron: SA.apron, stretchers: 10)),
            .table("Foldable Table", rooms: room, material: "Laminate", sizes: [SA.Size(30, 24, 30), SA.Size(36, 30, 30)],
                   SA.TableSpec(top: SA.laminateTop, leg: "Square 1\" Steel", legInset: 1.5, apron: "3/4\" x 1 1/2\" Steel Bar", stretchers: 8,
                                stretcherType: "3/4\" x 1 1/2\" Steel Bar", endStretchersOnly: true)),
            stepStool,
        ]
    }

    /// A two-step stool: a low step at the front and the top step behind it, each on its own pair of sides.
    static var stepStool: SA.Piece {
        SA.Piece("Step Stool", rooms: ["Kitchen"], material: "Solid Pine", sizes: [SA.Size(16, 18, 18), SA.Size(18, 20, 24)],
                 planes: [SA.Plane("Step", .z, "Height * 0.5")], steps: [{ b in
            let t = 0.75, wood = SA.Wood.pine, step = SA.p("Step")
            for (x, dir) in [(SA.L, 1.0), (SA.R, -1.0)] {
                try b.sideX(x, toward: dir, y: (SA.F, SA.CY), z: (SA.Z, step - t), wood.panel)
                try b.sideX(x, toward: dir, y: (SA.CY, SA.B), z: (SA.Z, SA.T - t), wood.panel)
            }
            try b.board(x: (SA.L, SA.R), y: (SA.F, SA.CY), top: step, wood.shelf, role: .top)
            try b.board(x: (SA.L, SA.R), y: (SA.CY, SA.B), top: SA.T, wood.shelf, role: .top)
            // Aprons under the steps and the riser between them.
            try b.sideY(SA.F + 1, toward: 1, x: (SA.L + t, SA.R - t), z: (step - 4, step - t), wood.panel)
            try b.sideY(SA.CY, toward: 1, x: (SA.L + t, SA.R - t), z: (step, SA.T - t), wood.panel)
            try b.sideY(SA.B - 1, toward: -1, x: (SA.L + t, SA.R - t), z: (SA.T - 5, SA.T - t), wood.panel)
        }])
    }
}
