import Foundation
import ArcusGeometry

// FM9B: more builders of the simple pieces: chests (a box with a lid), carts and trolleys (posts on casters with
// shelves and handles) and desks (a top on pedestals of drawers or end panels, a modesty panel and a monitor shelf).

// MARK: - Chests

extension SA {
    /// A box with a lift-up lid: four walls, a bottom, feet or legs.
    struct ChestSpec: Sendable {
        var wood: SA.Wood = .pine
        /// Feet or legs under the corners (nil: the walls stand on the floor).
        var feet: (height: Double, type: String)? = (3, SA.block)
        var lid = true
    }
}

extension SA.Piece {
    static func chest(_ name: String, rooms: [String], material: String, sizes: [SA.Size], _ c: SA.ChestSpec, more: [Step] = []) -> SA.Piece {
        var steps: [Step] = [{ b in
            let t = try b.panelThickness(c.wood.panel)
            let base = SA.Z + (c.feet?.height ?? 0)
            try b.sideX(SA.L, toward: 1, y: (SA.F, SA.B), z: (base, SA.T), c.wood.panel)
            try b.sideX(SA.R, toward: -1, y: (SA.F, SA.B), z: (base, SA.T), c.wood.panel)
            try b.sideY(SA.F, toward: 1, x: (SA.L + t, SA.R - t), z: (base, SA.T), c.wood.panel)
            try b.sideY(SA.B, toward: -1, x: (SA.L + t, SA.R - t), z: (base, SA.T), c.wood.panel)
            try b.board(x: (SA.L + t, SA.R - t), y: (SA.F + t, SA.B - t), top: base + (t + 0.75), c.wood.shelf, role: .bottom)
            if let f = c.feet {
                let w = try b.legWidth(f.type)
                try b.legs(x: (SA.L, SA.R), y: (SA.F, SA.B), inset: w / 2, z: (SA.Z, base), f.type)
            }
        }]
        if c.lid { steps.append { b in try b.lid(SA.CX, SA.CY, material: c.wood.front) } }
        return SA.Piece(name, rooms: rooms, material: material, sizes: sizes, steps: steps + more)
    }
}

// MARK: - Carts

extension SA {
    /// A cart or trolley: posts on casters, shelves on formula planes (equal spacing), handles along the ends.
    struct CartSpec: Sendable {
        var post = "Round 1\" Steel"
        var shelf = "3/4\" Solid Walnut Shelf"
        var shelves = 2
        /// The lowest shelf's top above the floor.
        var bottom: Double = 7
        var handles = true
        /// A low rail round each shelf's front and back (a lip, or a basket's rim).
        var lips = false
    }
}

extension SA.Piece {
    static func cart(_ name: String, rooms: [String], material: String, sizes: [SA.Size], _ c: SA.CartSpec, more: [Step] = []) -> SA.Piece {
        let n = max(2, c.shelves)
        // The top shelf sits 1 1/2" under the handles (or on the Top); the rest are spaced equally down to the bottom one.
        let topShelf = c.handles ? "Height - 2\"" : "Height"
        var planes = [SA.Plane("Shelf \(n)", .z, topShelf)]
        for k in 1..<(n - 1) { planes.append(SA.Plane("Shelf \(k + 1)", .z, "\(fmt(c.bottom))\" + (\(topShelf) - \(fmt(c.bottom))\") * \(k) / \(n - 1)")) }
        return SA.Piece(name, rooms: rooms, material: material, sizes: sizes, planes: planes, steps: [{ b in
            let pw = try b.legWidth(c.post), cw = try b.legWidth(SA.caster)
            let inset = max(pw, cw) / 2, caster = 3.0
            try b.legs(x: (SA.L, SA.R), y: (SA.F, SA.B), inset: inset, z: (SA.Z, SA.Z + caster), SA.caster)
            try b.legs(x: (SA.L, SA.R), y: (SA.F, SA.B), inset: inset, z: (SA.Z + caster, c.handles ? SA.T - 1 : SA.T), c.post)
            let x = (SA.L + (inset + pw / 2), SA.R - (inset + pw / 2))
            let levels = [SA.Z + c.bottom] + (1..<n).map { SA.p("Shelf \($0 + 1)") }
            for z in levels {
                try b.board(x: x, y: (SA.F, SA.B), top: z, c.shelf)
                if c.lips {
                    for y in [SA.F + 0.375, SA.B - 0.375] { try b.railX(x, y: y, top: z + 2, SA.stretcher) }
                }
            }
            if c.handles {
                for xx in [SA.L + inset, SA.R - inset] { try b.railY((SA.F + (inset + pw / 2), SA.B - (inset + pw / 2)), x: xx, top: SA.T, "1\" Round Steel Rail") }
            }
        }] + more)
    }
}

// MARK: - Desks

extension SA {
    /// A desk: a top on a pedestal of drawers or an end panel at each end, a modesty panel, a monitor shelf.
    struct DeskSpec: Sendable {
        var wood: SA.Wood = .oak
        var top = SA.oakTop
        /// Drawers in the left and right pedestals (nil: an end panel; 0: an open pedestal with a bottom).
        var left: Int? = nil
        var right: Int? = 3
        var pedestalWidth: Double = 16
        var modesty = true
        /// A monitor shelf this high above the desk top (the piece's Height includes it).
        var riser: Double? = nil
    }
}

extension SA.Piece {
    static func desk(_ name: String, rooms: [String], _ category: FamilyTemplate = .furniture, material: String, sizes: [SA.Size], _ d: SA.DeskSpec,
                     more: [Step] = []) -> SA.Piece {
        let planes = d.riser.map { [SA.Plane("Desk", .z, "Height - \(fmt($0))\"")] } ?? []
        return SA.Piece(name, rooms: rooms, category, material: material, sizes: sizes, planes: planes,
                        steps: [{ try SA.DeskLayout(d, $0).build() }, { try SA.DeskLayout(d, $0).drawers() }] + more)
    }
}

extension SA {
    struct DeskLayout {
        let d: SA.DeskSpec
        let b: SA.Builder
        let t: Double, topT: Double

        init(_ d: SA.DeskSpec, _ b: SA.Builder) {
            self.d = d; self.b = b
            t = (try? b.panelThickness(d.wood.panel)) ?? 0.75
            topT = (try? b.shelfThickness(d.top)) ?? 1
        }

        var deskTop: SA.LP { d.riser == nil ? SA.T : SA.p("Desk") }
        var under: SA.LP { deskTop - topT }
        /// The pedestals' and end panels' outer faces, 1" in from the top's ends, front and back.
        var outer: (SA.LP, SA.LP) { (SA.L + 1, SA.R - 1) }
        var y: (SA.LP, SA.LP) { (SA.F + 1, SA.B - 1) }

        /// A support's outer and inner faces at the left (`dir` 1) or right end.
        func faces(_ dir: Double, pedestal: Bool) -> (SA.LP, SA.LP) {
            let o = dir > 0 ? outer.0 : outer.1
            return (o, o + dir * (pedestal ? d.pedestalWidth : t))
        }

        func build() throws {
            try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: deskTop, d.top, role: .top)
            var inner: [SA.LP] = []
            for (dir, drawers) in [(1.0, d.left), (-1.0, d.right)] {
                let (o, i) = faces(dir, pedestal: drawers != nil)
                inner.append(i)
                try b.sideX(o, toward: dir, y: y, z: (SA.Z, under), d.wood.panel)
                guard drawers != nil else { continue }
                try b.sideX(i, toward: -dir, y: y, z: (SA.Z, under), d.wood.panel)
                let x = dir > 0 ? (o + t, i - t) : (i + t, o - t)
                try b.board(x: x, y: y, top: SA.Z + (3 + t), d.wood.shelf, role: .bottom)
                try b.sideY(y.0 + 2, toward: 1, x: x, z: (SA.Z, SA.Z + 3), d.wood.panel, role: .plinth)
            }
            if d.modesty {
                try b.sideY(y.1, toward: -1, x: (inner[0], inner[1]), z: (under - 14, under), d.wood.panel)
            }
            if d.riser != nil {
                // A monitor shelf on two short ends along the back of the top.
                let shelfT = try b.shelfThickness(d.wood.shelf)
                for (x, dir) in [(SA.L + 4, 1.0), (SA.R - 4, -1.0)] {
                    try b.sideX(x, toward: dir, y: (SA.B - 10, SA.B - 1), z: (deskTop, SA.T - shelfT), d.wood.panel)
                }
                try b.board(x: (SA.L + 4, SA.R - 4), y: (SA.B - 10, SA.B - 1), top: SA.T, d.wood.shelf)
            }
        }

        func drawers() throws {
            for (dir, drawers) in [(1.0, d.left), (-1.0, d.right)] {
                guard let n = drawers, n > 0 else { continue }
                let (o, _) = faces(dir, pedestal: true)
                let cx = o + dir * d.pedestalWidth / 2
                let z = (b.v(SA.Z + (3 + t)) + b.v(under)) / 2
                _ = try FurnitureFronts.createDrawers(in: try FurnitureBays.createBay(face: .front, at: Vec2(b.v(cx), z), in: b.tx), count: n,
                                                      typeID: try b.frontType(.drawer, SA.slabDrawer, material: d.wood.front), in: b.tx)
            }
        }
    }
}
