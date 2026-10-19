import Foundation

// FM9C: Decorative & Accent pieces (simple detail).

extension SimpleB {
    static var decorative: [Piece] {
        [
            Piece("Accent Table", [decor], accentTable),
            Piece("Pedestal Table", [decor], pedestalTable),
            Piece("Display Shelf", [decor], displayShelf),
            Piece("Curio Cabinet", [decor], .casework, curioCabinet),
            Piece("Decorative Console", [decor], decorativeConsole),
            Piece("Folding Screen", [decor], foldingScreen),
            Piece("Fireplace Mantel", [decor], .casework, fireplaceMantel),
            Piece("Decorative Bench", [decor], decorativeBench),
            Piece("Accent Cabinet", [decor], .casework, accentCabinet),
            Piece("Ladder Shelf", [decor], ladderShelf),
            Piece("Floating Shelf", [decor], floatingShelf),
            Piece("Display Pedestal", [decor], displayPedestal),
            Piece("Sculpture Stand", [decor], sculptureStand),
        ]
    }

    /// A small walnut table on tapered legs with a lower shelf.
    static func accentTable() throws -> BIMModel {
        let p = try SBBuilder("Accent Table", .furniture, [SBSize(20, 20, 24), SBSize(24, 24, 26)], material: "Solid Walnut")
        try p.step("Top, Legs and Shelf") { s in
            let t = try s.table(top: "1 1/4\" Solid Walnut Top", leg: "Round Tapered 1 3/4\" Oak", inset: 1.5, apron: "3/4\" x 1 1/2\" Walnut Rail")
            try s.board(x: (t.legX.0 + t.legWidth, t.legX.1 - t.legWidth), y: (t.legY.0 + 0.5, t.legY.1 - 0.5), top: 7, "3/4\" Solid Walnut Shelf")
        }
        return try p.finish()
    }

    /// A round top on a central column with a cross foot.
    static func pedestalTable() throws -> BIMModel {
        let p = try SBBuilder("Pedestal Table", .furniture, [SBSize(36, 36, 30), SBSize(42, 42, 30)], material: "Solid Walnut")
        try p.step("Top, Column and Foot") { s in
            let r = s.w / 2
            try s.board(loop: s.circle((0, 0), r, 32), top: s.h, "1 1/4\" Solid Walnut Top", role: .top)
            try s.leg(0, 0, z: (2.5, s.h - 1.25), "Round 4\" Walnut Column")
            let foot = "2\" x 2 1/2\" Walnut Foot", reach = r * 0.6
            try s.rail((-reach, 0), (reach, 0), z: 2.5, foot)
            try s.rail((0, -reach), (0, -2), z: 2.5, foot)
            try s.rail((0, 2), (0, reach), z: 2.5, foot)
            try s.rail((-r * 0.35, 0), (r * 0.35, 0), z: s.h - 1.25, "3/4\" x 3\" Apron")
        }
        return try p.finish()
    }

    /// An open oak display shelf with adjustable glass shelves and a back.
    static func displayShelf() throws -> BIMModel {
        let p = try SBBuilder("Display Shelf", .furniture, [SBSize(36, 12, 48), SBSize(30, 10, 60)], material: "Solid Oak")
        try p.step("Carcass and Glass Shelves") { s in
            try s.carcass(bottomAt: 3, sides: "3/4\" Solid Oak", top: "1\" Solid Oak Top", bottom: "1\" Solid Oak Shelf")
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (0, 2), "3/4\" Solid Oak", role: .plinth)
            for k in 1...3 {
                try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.5, s.b - 0.25), top: 3 + (s.h - 4) * Double(k) / 4, "1/4\" Glass Display Shelf", adjustable: true)
            }
        }
        try p.step("Back") { s in try s.back(x: 0, z: s.h / 2, "1/4\" Plywood") }
        return try p.finish()
    }

    /// A tall display cabinet: a pair of glass doors over adjustable glass shelves, on a toe kick.
    static func curioCabinet() throws -> BIMModel {
        let p = try SBBuilder("Curio Cabinet", .casework, [SBSize(32, 14, 72), SBSize(36, 16, 78)], material: "Solid Oak")
        var c: SBCarcass?
        try p.step("Carcass and Glass Shelves") { s in
            c = try s.carcass(bottomAt: 4.75, sides: "3/4\" Oak Veneer Plywood", top: "1\" Solid Oak Top", bottom: "3/4\" Plywood Shelf")
            for k in 1...4 {
                try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.5, s.b - 0.25), top: 4.75 + (s.h - 5.75) * Double(k) / 5, "1/4\" Glass Display Shelf", adjustable: true)
            }
        }
        try p.step("Kick and Back") { s in
            try s.plinth(under: c!.bottom, "3/4\" Oak Veneer Plywood")
            try s.back(x: 0, z: s.h / 2, "1/4\" Plywood")
        }
        try p.step("Glass Doors") { s in try s.door(x: 0, z: s.h / 2, "Glass Panel - Full Overlay Pair") }
        return try p.finish()
    }

    /// A console with a marble top on tapered legs, aprons and an oak lower shelf.
    static func decorativeConsole() throws -> BIMModel {
        let p = try SBBuilder("Decorative Console", .furniture, [SBSize(54, 15, 32), SBSize(60, 16, 34)], material: "Solid Oak")
        try p.step("Top, Legs and Shelf") { s in
            let t = try s.table(top: "1\" Marble Top", leg: "Round Tapered 2\"", inset: 1, apron: "3/4\" x 3\" Apron")
            try s.board(x: (t.legX.0 + t.legWidth, t.legX.1 - t.legWidth), y: (t.legY.0 + 0.5, t.legY.1 - 0.5), top: 8, "1\" Solid Oak Shelf")
        }
        return try p.finish()
    }

    /// A four-leaf folding screen, half folded: walnut posts at the hinges and canvas leaves between them.
    static func foldingScreen() throws -> BIMModel {
        let p = try SBBuilder("Folding Screen", .furniture, [SBSize(72, 12, 70)], material: "Canvas")
        try p.step("Posts and Leaves") { s in
            let pts: [(Double, Double)] = (0...4).map { k in (s.l + 0.75 + (s.w - 1.5) * Double(k) / 4, k % 2 == 0 ? s.f + 0.75 : s.b - 0.75) }
            for q in pts { try s.leg(q.0, q.1, z: (0, s.h), "Square 1 1/2\" Walnut") }
            for (a, c) in zip(pts, pts.dropFirst()) {
                let dx = c.0 - a.0, dy = c.1 - a.1, len = hypot(dx, dy), ux = dx / len, uy = dy / len
                try s.panelLine((a.0 + ux * 0.75, a.1 + uy * 0.75), (c.0 - ux * 0.75, c.1 - uy * 0.75), z: (2, s.h - 2), "1/8\" Canvas Panel")
                for z in [2.0, s.h - 2] {
                    try s.panelLine((a.0 + ux * 0.75, a.1 + uy * 0.75), (c.0 - ux * 0.75, c.1 - uy * 0.75), z: (z - 1, z + (z < 3 ? 0 : 1)), "3/4\" Solid Walnut")
                }
            }
        }
        return try p.finish()
    }

    /// A mantel surround: two pilasters, a frieze between them and a mantel shelf over all.
    static func fireplaceMantel() throws -> BIMModel {
        let p = try SBBuilder("Fireplace Mantel", .casework, [SBSize(60, 8, 48), SBSize(72, 10, 54)], material: "MDF")
        try p.step("Pilasters, Frieze and Shelf") { s in
            let mdf = "3/4\" MDF", top = s.h - 1.25, pw = 8.0
            for (x0, x1) in [(s.l, s.l + pw), (s.r - pw, s.r)] {
                try s.panelY(s.f, inward: 1, x: (x0, x1), z: (0, top), mdf)
                try s.panelX(x0, inward: 1, y: (s.f + 0.75, s.b), z: (0, top), mdf)
                try s.panelX(x1, inward: -1, y: (s.f + 0.75, s.b), z: (0, top), mdf)
            }
            try s.panelY(s.f, inward: 1, x: (s.l + pw, s.r - pw), z: (top - 10, top), mdf)
            try s.board(x: (s.l + pw, s.r - pw), y: (s.f + 0.75, s.b), top: top - 9.25, "3/4\" MDF Top")
            try s.rail((s.l + 0.5, s.f + 0.375), (s.r - 0.5, s.f + 0.375), z: top, "3/4\" x 1 1/2\" Stretcher")
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "1 1/4\" Solid Walnut Top", role: .top)
        }
        return try p.finish()
    }

    /// An upholstered bench on tapered legs with aprons and stretchers.
    static func decorativeBench() throws -> BIMModel {
        let p = try SBBuilder("Decorative Bench", .furniture, [SBSize(48, 16, 19), SBSize(60, 18, 19)], material: "Solid Oak")
        try p.step("Frame and Seat") { s in
            let t = try s.table(top: "3/4\" Plywood Top", leg: "Round Tapered 2\"", inset: 0, apron: "3/4\" x 3\" Apron", topAt: s.h - 3)
            try s.railRing(x: t.legX, y: t.legY, legWidth: t.legWidth, top: 5, "3/4\" x 1 1/2\" Stretcher", sides: (false, false, true, true))
            try s.rail((t.legX.0 + t.legWidth, 0), (t.legX.1 - t.legWidth, 0), z: 5, "3/4\" x 1 1/2\" Stretcher")
            try s.cushion(x: (s.l, s.r), y: (s.f, s.b), z0: s.h - 3, height: 3, "Fabric", crown: 0.75, radius: 1)
        }
        return try p.finish()
    }

    /// A two-door cabinet raised on tapered legs (a mid-century accent piece).
    static func accentCabinet() throws -> BIMModel {
        let p = try SBBuilder("Accent Cabinet", .casework, [SBSize(32, 16, 32), SBSize(40, 18, 34)], material: "Solid Walnut")
        try p.step("Carcass and Legs") { s in
            try s.carcass(z: (8, s.h), bottomAt: 8.75, sides: "3/4\" Solid Walnut", top: "3/4\" Plywood Top", bottom: "3/4\" Plywood Shelf")
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.25, s.b - 0.25), top: (8.75 + s.h) / 2, "3/4\" Plywood Shelf", adjustable: true)
            try s.legs(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.75, s.b - 0.75), z: (0, 8), "Round Tapered 1 3/4\" Oak")
        }
        try p.step("Back") { s in try s.back(x: 0, z: (8 + s.h) / 2) }
        try p.step("Doors") { s in try s.door(x: 0, z: (8 + s.h) / 2, "Shaker - Full Overlay Pair") }
        return try p.finish()
    }

    /// A leaning ladder shelf: two raked rails and four shelves, deepest at the bottom.
    static func ladderShelf() throws -> BIMModel {
        let p = try SBBuilder("Ladder Shelf", .furniture, [SBSize(24, 16, 72)], material: "Solid Oak")
        try p.step("Rails and Shelves") { s in
            for x in [s.l + 0.75, s.r - 0.75] { try s.railYZ((s.f + 1.5, 0), (s.b - 1.5, s.h), x: x, "1 1/2\" x 3\" Oak Rail") }
            for z in [8.0, 24, 40, 56] {
                let yr = (s.f + 1.5) + (s.b - s.f - 3) * z / s.h
                try s.board(x: (s.l + 1.5, s.r - 1.5), y: (yr - 2, s.b - 0.5), top: z, "3/4\" Solid Pine Shelf")
            }
        }
        return try p.finish()
    }

    /// A floating shelf: a hollow walnut box (top, bottom, front and ends) on two hidden steel bracket rods.
    static func floatingShelf() throws -> BIMModel {
        let p = try SBBuilder("Floating Shelf", .furniture, [SBSize(36, 8, 2), SBSize(48, 10, 2.5)], material: "Solid Walnut")
        try p.step("Box and Bracket") { s in
            let wood = "3/4\" Solid Walnut", t = 0.75
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "3/4\" Solid Walnut Shelf")
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: t, "3/4\" Solid Walnut Shelf")
            try s.panelY(s.f, inward: 1, x: (s.l, s.r), z: (t, s.h - t), wood)
            try s.panelX(s.l, inward: 1, y: (s.f + t, s.b), z: (t, s.h - t), wood)
            try s.panelX(s.r, inward: -1, y: (s.f + t, s.b), z: (t, s.h - t), wood)
            for x in [s.l + s.w / 4, s.r - s.w / 4] { try s.rail((x, s.b), (x, s.f + 2), z: s.h / 2, "1/2\" Round Steel Rod", just: .center) }
        }
        return try p.finish()
    }

    /// A painted display plinth: four panels and a top on a recessed base.
    static func displayPedestal() throws -> BIMModel {
        let p = try SBBuilder("Display Pedestal", .furniture, [SBSize(16, 16, 36), SBSize(12, 12, 42)], material: "MDF")
        try p.step("Box and Base") { s in
            let mdf = "3/4\" MDF", base = 3.0
            try s.panelX(s.l, inward: 1, y: (s.f, s.b), z: (base, s.h - 0.75), mdf)
            try s.panelX(s.r, inward: -1, y: (s.f, s.b), z: (base, s.h - 0.75), mdf)
            try s.panelY(s.f, inward: 1, x: (s.l + 0.75, s.r - 0.75), z: (base, s.h - 0.75), mdf)
            try s.panelY(s.b, inward: -1, x: (s.l + 0.75, s.r - 0.75), z: (base, s.h - 0.75), mdf)
            try s.board(x: (s.l, s.r), y: (s.f, s.b), top: s.h, "3/4\" MDF Top", role: .top)
            try s.board(x: (s.l + 0.75, s.r - 0.75), y: (s.f + 0.75, s.b - 0.75), top: base + 0.75, "3/4\" MDF Top", role: .bottom)
            let i = 0.75
            try s.panelX(s.l + i, inward: 1, y: (s.f + i, s.b - i), z: (0, base), mdf)
            try s.panelX(s.r - i, inward: -1, y: (s.f + i, s.b - i), z: (0, base), mdf)
            try s.panelY(s.f + i, inward: 1, x: (s.l + i + 0.75, s.r - i - 0.75), z: (0, base), mdf)
            try s.panelY(s.b - i, inward: -1, x: (s.l + i + 0.75, s.r - i - 0.75), z: (0, base), mdf)
        }
        return try p.finish()
    }

    /// A marble sculpture stand: a base slab, a tapered column (a blend) and a top plate, locked to the planes.
    static func sculptureStand() throws -> BIMModel {
        let p = try SBBuilder("Sculpture Stand", .furniture, [SBSize(18, 18, 36), SBSize(14, 14, 42)], material: "Marble")
        try p.step("Base, Column and Top") { s in
            func square(_ half: Double) -> [(Double, Double)] { [(-half, -half), (half, -half), (half, half), (-half, half)] }
            let (hw, all) = (s.w / 2, SBStep.Lock.axes(.scale, .scale, .scale))
            try s.extrusion(square(hw), w: (0, 3), "Marble", lock: all)
            try s.blend(square(hw * 0.72), square(hw * 0.55), z: (3, s.h - 2), "Marble", lock: all)
            try s.extrusion(square(hw * 0.8), w: (s.h - 2, s.h), "Marble", lock: all)
        }
        return try p.finish()
    }
}
