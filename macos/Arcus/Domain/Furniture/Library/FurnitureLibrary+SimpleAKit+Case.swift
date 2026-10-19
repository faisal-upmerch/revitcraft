import Foundation
import ArcusGeometry

// FM9B: the case builder of the simple pieces: a carcass (sides, bottom, top, back) on a plinth, legs or feet, or
// hung from a wall, split into rows (fixed shelves, equal or on formula planes) and columns (EQ dividers), with each
// compartment open, shelved, or closed by doors, drawers or a flap. Hardware comes with the fronts.

extension SA {
    /// The board types of one material: sides and dividers, shelves and bottoms, tops.
    struct Wood: Sendable {
        var panel: String
        var shelf: String
        var top: String
        /// The doors' and drawer fronts' material (nil: the standard types' own).
        var front: String?
        static let ply = SA.Wood(panel: SA.ply, shelf: SA.plyShelf, top: SA.plyTop, front: nil)
        static let oak = SA.Wood(panel: SA.oak, shelf: "3/4\" Solid Oak Shelf", top: SA.oakTop, front: "Solid Oak")
        static let walnut = SA.Wood(panel: SA.walnut, shelf: "3/4\" Solid Walnut Shelf", top: SA.walnutTop, front: "Solid Walnut")
        static let veneer = SA.Wood(panel: SA.veneer, shelf: "3/4\" Oak Veneer Shelf", top: "3/4\" Oak Veneer Top", front: nil)
        static let melamine = SA.Wood(panel: SA.mel, shelf: SA.melShelf, top: "3/4\" Melamine Top", front: "Melamine")
        static let mdf = SA.Wood(panel: SA.mdf, shelf: "3/4\" MDF Shelf", top: "3/4\" MDF Top", front: "MDF")
        static let pine = SA.Wood(panel: "3/4\" Solid Pine", shelf: "3/4\" Solid Pine Shelf", top: "1\" Solid Pine Top", front: "Solid Pine")
        static let maple = SA.Wood(panel: "3/4\" Solid Maple", shelf: "3/4\" Solid Maple Shelf", top: "1\" Solid Maple Top", front: "Solid Maple")

        /// The shelf and top types the woods need beyond the standard ones.
        static let extraTypes: [FurniturePartTypes.Spec] = [
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "3/4\" Solid Oak Shelf", t: 0.75, core: "Solid Oak", edge: nil),
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "3/4\" Oak Veneer Shelf", t: 0.75, core: "Plywood", face: "Veneer", banding: "L1"),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "3/4\" Oak Veneer Top", t: 0.75, core: "Plywood", face: "Veneer", banding: "L1 L2 W1 W2",
                                     texts: [FurniturePartTypes.topEdge: TopEdge.square.rawValue]),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "3/4\" Melamine Top", t: 0.75, core: "Melamine", edge: "PVC Edge Banding", edgeT: 0.04,
                                     banding: "L1 L2 W1 W2", grain: .none, texts: [FurniturePartTypes.topEdge: TopEdge.square.rawValue]),
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "3/4\" MDF Shelf", t: 0.75, core: "MDF", edge: nil, grain: .none),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "3/4\" MDF Top", t: 0.75, core: "MDF", edge: nil, grain: .none,
                                     texts: [FurniturePartTypes.topEdge: TopEdge.square.rawValue]),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "3/4\" Solid Pine", t: 0.75, core: "Solid Pine", edge: nil),
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "3/4\" Solid Pine Shelf", t: 0.75, core: "Solid Pine", edge: nil),
            FurniturePartTypes.sheet(.furnitureShelves, "Top", "1\" Solid Pine Top", t: 1, core: "Solid Pine", edge: nil, texts: [FurniturePartTypes.topEdge: TopEdge.roundOver.rawValue]),
            FurniturePartTypes.sheet(.furniturePanels, "Panel", "3/4\" Solid Maple", t: 0.75, core: "Solid Maple", edge: nil),
            FurniturePartTypes.sheet(.furnitureShelves, "Shelf", "3/4\" Solid Maple Shelf", t: 0.75, core: "Solid Maple", edge: nil),
        ]
    }
}

extension SA {
    /// What fills one compartment of a case.
    enum Fill: Sendable {
        case open
        /// Fixed shelves splitting it into equal spaces (EQ).
        case shelves(Int)
        case drawers(Int)
        /// Drawers side by side (EQ).
        case drawerColumns(Int)
        /// A door hinged left (or right).
        case door(right: Bool)
        /// Doors side by side (EQ), hinged at the outer edges.
        case doors(Int)
        case glassDoors(Int)
        case flap(dropDown: Bool)
    }
}

extension SA {
    /// How a case stands.
    enum CaseBase: Sendable {
        /// A toe kick `h` inches high, set back 3".
        case plinth(Double)
        /// Four legs `h` inches high under the corners.
        case legs(Double, String)
        /// The bottom on the floor (or the wall-hung piece's underside on Bottom).
        case none

        var height: Double {
            switch self { case .plinth(let h), .legs(let h, _): h; case .none: 0 }
        }
    }
}

extension SA {
    /// A carcass, its rows and columns and what fills them.
    struct CaseSpec: Sendable {
        var wood: SA.Wood = .ply
        /// A top laid over the sides, `overhang` inches past them at the front and ends (nil: a top between the sides).
        var topOver: (type: String, overhang: Double)? = nil
        var base: SA.CaseBase = .plinth(4)
        var back: String? = SA.hardboard
        /// Rows from the top down, each split into equal columns.
        var rows: [[SA.Fill]] = [[.open]]
        /// Formulas for the top faces of the fixed shelves between rows (rows.count - 1 of them), from the top down; nil
        /// splits the rows equally (EQ dividers).
        var rowLines: [String]? = nil
        var door = SA.slabDoor
        var drawer = SA.slabDrawer
        /// The fronts' material (nil: the wood's).
        var frontMaterial: String? = nil
        /// The carcass stands this far in front of the Back plane (an island's seating overhang under the top).
        var backOverhang: Double = 0
    }
}

extension SA.Piece {
    /// A case piece: the carcass, then its rows, columns and fronts (one transaction each).
    static func casePiece(_ name: String, rooms: [String], _ category: FamilyTemplate = .casework, material: String, sizes: [SA.Size],
                          _ c: SA.CaseSpec, planes extra: [SA.Plane] = [], more: [Step] = []) -> SA.Piece {
        let lines = (c.rowLines ?? []).enumerated().map { SA.Plane("Shelf Line \($0.offset + 1)", .z, $0.element) }
        return SA.Piece(name, rooms: rooms, category, material: material, sizes: sizes, planes: lines + extra,
                           steps: [{ try SA.CaseLayout(c, $0).carcass() }, { try SA.CaseLayout(c, $0).rowDividers() },
                                   { try SA.CaseLayout(c, $0).columnDividers() }, { try SA.CaseLayout(c, $0).fills() }] + more)
    }
}

extension SA {
    /// The case's geometry on the planes, as each build step sees it.
    struct CaseLayout {
        let c: SA.CaseSpec
        let b: SA.Builder
        let t: Double, topT: Double, backT: Double, oh: Double

        init(_ c: SA.CaseSpec, _ b: SA.Builder) {
            self.c = c; self.b = b
            t = (try? b.type(.furniturePanels, c.wood.panel)).map { b.thickness($0) / SA.inch } ?? 0.75
            topT = c.topOver.flatMap { try? b.type(.furnitureShelves, $0.type) }.map { b.thickness($0) / SA.inch } ?? 0
            backT = c.back.flatMap { try? b.type(.furniturePanels, $0) }.map { b.thickness($0) / SA.inch } ?? 0
            oh = c.topOver?.overhang ?? 0
        }

        var xl: SA.LP { SA.L + oh }
        var xr: SA.LP { SA.R - oh }
        var yf: SA.LP { SA.F + oh }
        var yb: SA.LP { SA.B - c.backOverhang }
        var fronts: String? { c.frontMaterial ?? c.wood.front }
        var sideTop: SA.LP { c.topOver == nil ? SA.T : SA.T - topT }
        var sideBase: SA.LP {
            if case .legs = c.base { return SA.Z + c.base.height }
            return SA.Z
        }
        var bottomTop: SA.LP { SA.Z + (c.base.height + t) }
        var inner: (SA.LP, SA.LP) { (xl + t, xr - t) }
        var boardY: (SA.LP, SA.LP) { (yf, yb - backT) }
        /// The underside of the top (the inside top of the carcass).
        var ceiling: SA.LP { c.topOver == nil ? SA.T - t : sideTop }

        func carcass() throws {
            try b.sideX(xl, toward: 1, y: (yf, yb), z: (sideBase, sideTop), c.wood.panel)
            try b.sideX(xr, toward: -1, y: (yf, yb), z: (sideBase, sideTop), c.wood.panel)
            try b.board(x: inner, y: boardY, top: bottomTop, c.wood.shelf, role: .bottom)
            if let over = c.topOver {
                try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: SA.T, over.type, role: .top)
            } else {
                try b.board(x: inner, y: boardY, top: SA.T, c.wood.top, role: .top)
            }
            if let back = c.back {
                try b.sideY(yb, toward: -1, x: inner, z: (bottomTop - t, sideTop), back, role: .back)
            }
            switch c.base {
            case .plinth(let h): try b.sideY(yf + 3, toward: 1, x: inner, z: (SA.Z, SA.Z + h), c.wood.panel, role: .plinth)
            case .legs(let h, let type):
                let w = FurniturePartTypes.Values(b.model[try b.type(.furnitureLegs, type)]?.typeData).width / SA.inch
                try b.legs(x: (xl, xr), y: (yf, yb), inset: w / 2, z: (SA.Z, SA.Z + h), type)
            case .none: break
            }
            // Fixed shelves on formula planes between the rows.
            for k in (c.rowLines ?? []).indices {
                try b.board(x: inner, y: boardY, top: SA.p("Shelf Line \(k + 1)"), c.wood.shelf)
            }
        }

        // MARK: Cells

        /// Row centres (z), from the top down.
        var rowCentres: [Double] {
            let lo = b.v(bottomTop), hi = b.v(ceiling), n = c.rows.count
            if let lines = c.rowLines, lines.count == n - 1 {
                var tops = [hi], bottoms: [Double] = []
                for k in lines.indices { let z = b.v(SA.p("Shelf Line \(k + 1)")); bottoms.append(z); tops.append(z - t * SA.inch) }
                bottoms.append(lo)
                return (0..<n).map { (tops[$0] + bottoms[$0]) / 2 }
            }
            return (0..<n).map { hi - (hi - lo) * (Double($0) + 0.5) / Double(n) }
        }

        func columnCentres(_ n: Int) -> [Double] {
            let lo = b.v(inner.0), hi = b.v(inner.1)
            return (0..<n).map { lo + (hi - lo) * (Double($0) + 0.5) / Double(n) }
        }

        func rowDividers() throws {
            guard c.rows.count > 1, c.rowLines == nil else { return }
            let z = (b.v(bottomTop) + b.v(ceiling)) / 2
            _ = try FurniturePartOperations.createDividers(atFront: Vec2(b.v(SA.CX), z), vertical: false, count: c.rows.count - 1,
                                                           typeID: try b.type(.furniturePanels, c.wood.panel), in: b.tx)
        }

        func columnDividers() throws {
            let zs = rowCentres
            for (r, row) in c.rows.enumerated() where row.count > 1 {
                let x = (b.v(inner.0) + b.v(inner.1)) / 2
                _ = try FurniturePartOperations.createDividers(atFront: Vec2(x, zs[r]), vertical: true, count: row.count - 1,
                                                               typeID: try b.type(.furniturePanels, c.wood.panel), in: b.tx)
            }
        }

        func fills() throws {
            let zs = rowCentres
            for (r, row) in c.rows.enumerated() {
                let xs = columnCentres(row.count)
                for (k, fill) in row.enumerated() {
                    let p = Vec2(xs[k], zs[r])
                    try fillCell(fill, at: p, column: k, of: row.count)
                }
            }
        }

        func fillCell(_ fill: SA.Fill, at p: Vec2, column k: Int, of n: Int) throws {
            let tx = b.tx
            func bay() throws -> ElementID { try FurnitureBays.createBay(face: .front, at: p, in: tx) }
            switch fill {
            case .open: break
            case .shelves(let count):
                _ = try FurniturePartOperations.createDividers(atFront: p, vertical: false, count: count, typeID: try b.type(.furniturePanels, c.wood.panel), in: tx)
            case .drawers(let count):
                _ = try FurnitureFronts.createDrawers(in: try bay(), count: count, typeID: try b.frontType(.drawer, c.drawer, material: fronts), in: tx)
            case .drawerColumns(let count):
                let bay = try bay()
                try FurnitureBays.divide(bay, BayDivision(direction: .columns, count: count), in: tx)
                _ = try FurnitureFronts.createFront(.drawer, in: bay, typeID: try b.frontType(.drawer, c.drawer, material: fronts), in: tx)
            case .door(let right):
                _ = try FurnitureFronts.createFront(.door, in: try bay(), typeID: try b.frontType(.door, c.door, material: fronts), hingeFlipped: right, in: tx)
            case .doors(let count):
                try b.doors(in: try bay(), count: count, c.door, material: fronts)
            case .glassDoors(let count):
                try b.doors(in: try bay(), count: count, SA.glassDoor, material: fronts)
            case .flap(let dropDown):
                _ = try FurnitureFronts.createFront(.flap, in: try bay(), typeID: try b.frontType(.flap, dropDown ? SA.dropDown : SA.liftUp, material: fronts), in: tx)
            }
        }
    }
}
