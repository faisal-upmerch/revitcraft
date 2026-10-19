import Foundation
import ArcusGeometry

// FM9: recipes for the common kinds of piece, built from the LibraryBuilder's parts (FurnitureLibraryKit.swift):
// carcass (cabinets, dressers, wardrobes, bookcases), table (tables, desks, benches), chair, bed, shelving (open
// shelving on posts) and upholstered (sofas, armchairs, ottomans). Every size is in inches. Each recipe returns its
// parts by role so a piece can add to them.

// MARK: - Carcass

/// A carcass: sides, top, bottom, back, base (plinth or legs), columns split by EQ dividers, and per column rows from the
/// bottom separated by fixed shelves, each row open or with doors or drawers, with adjustable shelves or a closet rod.
public struct CarcassSpec: Sendable {
    public enum Top: Sendable {
        /// A top between the sides (flush).
        case inside(String = "3/4\" Plywood Top")
        /// A top over the sides overhanging the carcass by `front`, `sides` and `back` (the overall size includes it).
        case over(String, front: Double = 1, sides: Double = 0.75, back: Double = 0)
        /// No top (an open box or a carcass under a separate top).
        case none
    }
    public enum Base: Sendable {
        /// A raised bottom over a plinth (toe kick) set back from the front.
        case plinth(height: Double = 4, setback: Double = 3)
        /// The carcass on legs `height` tall, `inset` in from its corners.
        case legs(String, height: Double, inset: Double = 1)
        /// The bottom on the floor between the sides.
        case floor
    }
    /// The plan and height range the carcass fills (nil = the planes).
    public var x: ClosedRange<Double>?
    public var y: ClosedRange<Double>?
    public var z: ClosedRange<Double>?
    public var panel: String
    public var top: Top
    public var base: Base
    /// The back's type (nil = no back).
    public var back: String?
    public var columns: [CarcassColumn]
    public var shelf: String
    /// Front types by name (nil = the standard types).
    public var doorType: String?
    public var pairType: String?
    public var drawerType: String?
    public var flapType: String?
    /// How far the carcass box sits back from the front so overlay fronts stay inside the Depth (nil = their
    /// thickness when the carcass has fronts).
    public var frontInset: Double?
    public init(x: ClosedRange<Double>? = nil, y: ClosedRange<Double>? = nil, z: ClosedRange<Double>? = nil, panel: String = "3/4\" Plywood",
                top: Top = .inside(), base: Base = .plinth(), back: String? = "1/4\" Back Panel (Hardboard)", columns: [CarcassColumn] = [CarcassColumn()],
                shelf: String = "3/4\" Plywood Shelf", doorType: String? = nil, pairType: String? = nil, drawerType: String? = nil, flapType: String? = nil) {
        self.x = x; self.y = y; self.z = z; self.panel = panel; self.top = top; self.base = base; self.back = back; self.columns = columns; self.shelf = shelf
        self.doorType = doorType; self.pairType = pairType; self.drawerType = drawerType; self.flapType = flapType
    }

    var hasFronts: Bool { columns.contains { $0.rows.contains { $0.front != .none } } }
}

/// One column of a carcass: its rows from the bottom.
public struct CarcassColumn: Sendable {
    public var rows: [CarcassRow]
    public init(rows: [CarcassRow] = [CarcassRow()]) { self.rows = rows }
    public init(_ rows: CarcassRow...) { self.rows = rows }
}

/// One row of a column: what closes it, its clear height (nil = a share of what's left), adjustable shelves inside and
/// a closet rod.
public struct CarcassRow: Sendable {
    public enum Front: Sendable, Equatable {
        case none, door, doorLeft, doorRight, pair, drawers(Int), flapUp, flapDown
    }
    public var front: Front
    public var height: Double?
    public var shelves: Int
    public var rod: Bool
    /// This row's front type (nil = the carcass's).
    public var frontType: String?
    public init(_ front: Front = .none, height: Double? = nil, shelves: Int = 0, rod: Bool = false, frontType: String? = nil) {
        self.front = front; self.height = height; self.shelves = shelves; self.rod = rod; self.frontType = frontType
    }
}

/// The parts a carcass recipe made.
public struct Carcass: Sendable {
    public var sides: [ElementID] = []
    public var top: ElementID?
    public var bottom: ElementID?
    public var back: ElementID?
    public var plinth: ElementID?
    public var legs: [ElementID] = []
    public var dividers: [ElementID] = []
    public var shelves: [ElementID] = []
    public var bays: [ElementID] = []
    public var fronts: [ElementID] = []
    /// The carcass box (outside of the sides, front to back, base to top) and the clear interior heights (inches).
    public var box: (x: ClosedRange<Double>, y: ClosedRange<Double>, z: ClosedRange<Double>) = (0...0, 0...0, 0...0)
    public var interior: ClosedRange<Double> = 0...0
    /// Each column's clear x range.
    public var columns: [ClosedRange<Double>] = []
}

extension LibraryBuilder {
    /// Builds a carcass (see `CarcassSpec`).
    @discardableResult
    public func carcass(_ s: CarcassSpec) throws -> Carcass {
        var out = Carcass()
        let xr = s.x ?? l...r, y0 = s.y ?? f...b, zr = s.z ?? 0...h
        let inset = s.frontInset ?? (s.hasFronts ? 0.75 : 0)
        let yr = (y0.lowerBound + inset)...y0.upperBound
        let t = thickness(type(.furniturePanels, s.panel))
        var cx = xr, cy = yr, sideTop = zr.upperBound
        var topT = 0.0
        switch s.top {
        case .inside(let tt): topT = thickness(type(.furnitureShelves, tt))
        case .over(let tt, let fr, let sd, let bk):
            topT = thickness(type(.furnitureShelves, tt))
            cx = (xr.lowerBound + sd)...(xr.upperBound - sd); cy = (y0.lowerBound + max(fr, inset))...(yr.upperBound - bk)
            sideTop = zr.upperBound - topT
        case .none: break
        }
        let bottomT = thickness(type(.furnitureShelves, s.shelf))
        var sideBase = zr.lowerBound, bottomTop = zr.lowerBound + bottomT
        switch s.base {
        case .plinth(let ph, _): bottomTop = zr.lowerBound + ph + bottomT
        case .legs(_, let lh, _): sideBase = zr.lowerBound + lh; bottomTop = sideBase + bottomT
        case .floor: break
        }
        out.box = (cx, cy, sideBase...zr.upperBound)
        out.sides.append(try board(x: cx.lowerBound...(cx.lowerBound + t), y: cy, z: sideBase...sideTop, type: s.panel))
        out.sides.append(try board(x: (cx.upperBound - t)...cx.upperBound, y: cy, z: sideBase...sideTop, type: s.panel))
        let inner = (cx.lowerBound + t)...(cx.upperBound - t)
        switch s.top {
        case .inside(let tt): out.top = try shelf(x: inner, y: cy, top: zr.upperBound, type: tt, role: .top)
        case .over(let tt, _, _, _): out.top = try shelf(x: xr, y: y0, top: zr.upperBound, type: tt, role: .top)
        case .none: break
        }
        out.bottom = try shelf(x: inner, y: cy, top: bottomTop, type: s.shelf, role: .bottom)
        let midZ = (bottomTop + (zr.upperBound - topT)) / 2
        out.interior = bottomTop...(zr.upperBound - topT)
        var backFace = cy.upperBound
        if let bt = s.back {
            out.back = try back(at: Vec2((inner.lowerBound + inner.upperBound) / 2, midZ), type: bt)
            backFace -= thickness(type(.furniturePanels, bt))
        }
        switch s.base {
        case .plinth(_, let sb): if let bottom = out.bottom { out.plinth = try plinth(under: bottom, setback: sb, type: s.panel) }
        case .legs(let lt, let lh, let inset):
            out.legs = try legs(x: cx, y: cy, inset: inset, z: zr.lowerBound...(zr.lowerBound + lh), type: lt)
        case .floor: break
        }
        // Columns: EQ dividers between the bottom and the top.
        let n = max(1, s.columns.count)
        let dt = t
        if n > 1 { out.dividers = try dividers(at: Vec2((inner.lowerBound + inner.upperBound) / 2, midZ), count: n - 1, type: s.panel) }
        let lo = inner.lowerBound, hi = inner.upperBound
        out.columns = (0..<n).map { i in
            let a = i == 0 ? lo : lo + (hi - lo) * Double(i) / Double(n) + dt / 2
            let c = i == n - 1 ? hi : lo + (hi - lo) * Double(i + 1) / Double(n) - dt / 2
            return a...c
        }
        // Rows: fixed shelves between them.
        let ts = thickness(type(.furnitureShelves, s.shelf))
        var rowRanges: [[ClosedRange<Double>]] = []
        for (ci, col) in s.columns.enumerated() {
            let rows = col.rows.isEmpty ? [CarcassRow()] : col.rows
            let clear = out.interior.upperBound - out.interior.lowerBound - Double(rows.count - 1) * ts
            let fixed = rows.compactMap(\.height).reduce(0, +)
            let flexible = rows.filter { $0.height == nil }.count
            let share = flexible > 0 ? max(1, (clear - fixed) / Double(flexible)) : 0
            var z = out.interior.lowerBound
            var ranges: [ClosedRange<Double>] = []
            for (k, row) in rows.enumerated() {
                let hgt = row.height ?? share
                let top = k == rows.count - 1 ? out.interior.upperBound : z + hgt
                ranges.append(z...top)
                if k < rows.count - 1 {
                    out.shelves.append(try shelf(x: out.columns[ci], y: cy.lowerBound...backFace, top: top + ts, type: s.shelf))
                    z = top + ts
                }
            }
            rowRanges.append(ranges)
        }
        // Fronts in each row's bay.
        try commit()
        for (ci, col) in s.columns.enumerated() {
            let rows = col.rows.isEmpty ? [CarcassRow()] : col.rows
            let xc = (out.columns[ci].lowerBound + out.columns[ci].upperBound) / 2
            for (k, row) in rows.enumerated() where row.front != .none {
                let zr = rowRanges[ci][k]
                let bayID = try bay(at: Vec2(xc, (zr.lowerBound + zr.upperBound) / 2))
                out.bays.append(bayID)
                let autoRight = n > 1 && ci == n - 1
                switch row.front {
                case .none: break
                case .door: out.fronts += try front(.door, in: bayID, type: row.frontType ?? s.doorType, hingeRight: autoRight)
                case .doorLeft: out.fronts += try front(.door, in: bayID, type: row.frontType ?? s.doorType)
                case .doorRight: out.fronts += try front(.door, in: bayID, type: row.frontType ?? s.doorType, hingeRight: true)
                case .pair: out.fronts += try front(.door, in: bayID, type: row.frontType ?? s.pairType ?? "Slab - Full Overlay Pair")
                case .drawers(let c): out.fronts += try drawers(in: bayID, count: c, type: row.frontType ?? s.drawerType)
                case .flapUp: out.fronts += try front(.flap, in: bayID, type: row.frontType ?? s.flapType)
                case .flapDown: out.fronts += try front(.flap, in: bayID, type: row.frontType ?? s.flapType ?? "Slab - Full Overlay Drop-Down")
                }
            }
        }
        // Adjustable shelves and closet rods inside the rows (behind any doors).
        for (ci, col) in s.columns.enumerated() {
            let rows = col.rows.isEmpty ? [CarcassRow()] : col.rows
            for (k, row) in rows.enumerated() {
                let zr = rowRanges[ci][k]
                if row.shelves > 0 {
                    for j in 1...row.shelves {
                        let z = zr.lowerBound + (zr.upperBound - zr.lowerBound) * Double(j) / Double(row.shelves + 1) + ts / 2
                        out.shelves.append(try shelf(x: out.columns[ci], y: cy.lowerBound...backFace, top: z, type: s.shelf, adjustable: true, setback: 0.25))
                    }
                }
                if row.rod {
                    let rodType = "1\" Round Stretcher"
                    let yc = (cy.lowerBound + backFace) / 2
                    out.shelves.append(try rail(from: Vec2(out.columns[ci].lowerBound, yc), to: Vec2(out.columns[ci].upperBound, yc), z: zr.upperBound - 2.5,
                                                type: rodType, justification: .center))
                }
            }
        }
        return out
    }
}

// MARK: - Table

/// A table: a top, legs in its corners, aprons between them, and optionally a lower shelf, stretchers and a drawer in
/// the front apron.
public struct TableSpec: Sendable {
    public var top: String
    public var x: ClosedRange<Double>?
    public var y: ClosedRange<Double>?
    /// The top's top face (nil = the Top plane).
    public var z: Double?
    public var leg: String
    /// Legs' outside faces in from the top's edges.
    public var legInset: Double
    /// The apron type (nil = no aprons).
    public var apron: String?
    /// Aprons' outside faces in from the legs' outside faces.
    public var apronSetback: Double
    /// A lower shelf: its type and the height of its top face.
    public var shelf: (type: String, height: Double)?
    /// Stretchers between the legs: type and height of their top.
    public var stretchers: (type: String, height: Double)?
    /// A drawer in the front apron: clear width and height of the opening, and its front type.
    public var drawer: (width: Double, height: Double, type: String?)?
    public init(top: String = "1 1/2\" Butcher Block", x: ClosedRange<Double>? = nil, y: ClosedRange<Double>? = nil, z: Double? = nil,
                leg: String = "Square Tapered 1 3/4\"", legInset: Double = 1.5, apron: String? = "3/4\" x 3\" Apron", apronSetback: Double = 0.25,
                shelf: (type: String, height: Double)? = nil, stretchers: (type: String, height: Double)? = nil, drawer: (width: Double, height: Double, type: String?)? = nil) {
        self.top = top; self.x = x; self.y = y; self.z = z; self.leg = leg; self.legInset = legInset; self.apron = apron; self.apronSetback = apronSetback
        self.shelf = shelf; self.stretchers = stretchers; self.drawer = drawer
    }
}

/// The parts a table recipe made.
public struct Table: Sendable {
    public var top: ElementID?
    public var legs: [ElementID] = []
    public var aprons: [ElementID] = []
    public var shelf: ElementID?
    public var stretchers: [ElementID] = []
    public var drawer: [ElementID] = []
    /// The top's underside (inches) and the legs' centre lines.
    public var underside: Double = 0
    public var legX: (Double, Double) = (0, 0)
    public var legY: (Double, Double) = (0, 0)
}

extension LibraryBuilder {
    /// Builds a table (see `TableSpec`).
    @discardableResult
    public func table(_ s: TableSpec) throws -> Table {
        var out = Table()
        let xr = s.x ?? l...r, yr = s.y ?? f...b, zt = s.z ?? h
        let tt = thickness(type(.furnitureShelves, s.top))
        let topID = try shelf(x: xr, y: yr, top: zt, type: s.top, role: .top)
        out.top = topID
        out.underside = zt - tt
        let (lw, ld) = legSize(s.leg)
        // Legs At Corners, attached to the top.
        out.legs = try legsAtCorners(of: topID, inset: s.legInset, type: s.leg)
        let x0 = xr.lowerBound + s.legInset, x1 = xr.upperBound - s.legInset, y0 = yr.lowerBound + s.legInset, y1 = yr.upperBound - s.legInset
        out.legX = (x0 + lw / 2, x1 - lw / 2); out.legY = (y0 + ld / 2, y1 - ld / 2)
        let under = out.underside
        if let apron = s.apron {
            let aw = railSize(apron).width
            let fy = y0 + s.apronSetback + aw / 2, by = y1 - s.apronSetback - aw / 2
            let lx = x0 + s.apronSetback + aw / 2, rx = x1 - s.apronSetback - aw / 2
            let ax0 = x0 + lw, ax1 = x1 - lw, ay0 = y0 + ld, ay1 = y1 - ld
            if let dr = s.drawer {
                // The front apron is cut round the drawer: two short aprons, a rail under the opening, runners and a kicker.
                let dx0 = -dr.width / 2, dx1 = dr.width / 2
                let runner = "3/4\" Plywood"
                let rt = thickness(type(.furniturePanels, runner))
                out.aprons.append(try rail(from: Vec2(ax0, fy), to: Vec2(dx0 - rt, fy), z: under, type: apron))
                out.aprons.append(try rail(from: Vec2(dx1 + rt, fy), to: Vec2(ax1, fy), z: under, type: apron))
                let front = fy - aw / 2
                let zLow = under - dr.height
                let support = "3/4\" x 1 1/2\" Stretcher"
                _ = support
                out.drawer.append(try board(x: (dx0 - rt)...dx0, y: front...(by - aw / 2), z: (zLow - 0.75)...under, type: runner))
                out.drawer.append(try board(x: dx1...(dx1 + rt), y: front...(by - aw / 2), z: (zLow - 0.75)...under, type: runner))
                out.drawer.append(try shelf(x: dx0...dx1, y: front...(by - aw / 2), top: zLow, type: "1/2\" Plywood Shelf", role: .shelf))
                out.drawer.append(try rail(from: Vec2(dx0, front + 0.375), to: Vec2(dx1, front + 0.375), z: under, type: "3/4\" x 3/4\" Cleat"))
            } else {
                out.aprons.append(try rail(from: Vec2(ax0, fy), to: Vec2(ax1, fy), z: under, type: apron))
            }
            out.aprons.append(try rail(from: Vec2(ax1, by), to: Vec2(ax0, by), z: under, type: apron))
            out.aprons.append(try rail(from: Vec2(lx, ay1), to: Vec2(lx, ay0), z: under, type: apron))
            out.aprons.append(try rail(from: Vec2(rx, ay0), to: Vec2(rx, ay1), z: under, type: apron))
        }
        if let st = s.stretchers {
            let sw = railSize(st.type).width
            let lx = x0 + lw / 2, rx = x1 - lw / 2
            out.stretchers.append(try rail(from: Vec2(lx, y1 - ld), to: Vec2(lx, y0 + ld), z: st.height, type: st.type))
            out.stretchers.append(try rail(from: Vec2(rx, y0 + ld), to: Vec2(rx, y1 - ld), z: st.height, type: st.type))
            out.stretchers.append(try rail(from: Vec2(lx + sw / 2, 0), to: Vec2(rx - sw / 2, 0), z: st.height, type: st.type))
        }
        if let sh = s.shelf {
            out.shelf = try shelf(x: (x0 + lw)...(x1 - lw), y: y0...y1, top: sh.height, type: sh.type)
        }
        if let dr = s.drawer {
            try commit()
            let bayID = try bay(at: Vec2(0, under - dr.height / 2))
            out.drawer += try front(.drawer, in: bayID, type: dr.type ?? "Slab - Inset")
        }
        return out
    }

    /// A rail type's width (across) and height (inches).
    public func railSize(_ type: String) -> (width: Double, height: Double) {
        let tv = FurniturePartTypes.Values(tx.model[self.type(.furnitureRails, type)]?.typeData)
        return (tv.width / Self.inch, tv.depth / Self.inch)
    }
}

// MARK: - Chair

/// A chair or stool: four legs (the back two running up to the back), seat rails, a seat (wood or upholstered), a back
/// (slats, rails, an upholstered pad or none), and optionally stretchers and arms.
public struct ChairSpec: Sendable {
    public enum Seat: Sendable {
        case wood(String)
        case upholstered(material: String, thickness: Double)
    }
    public enum Back: Sendable {
        case none
        case slats(count: Int, type: String)
        case rails(count: Int, type: String)
        case upholstered(material: String, thickness: Double)
    }
    /// Height of the seat's top.
    public var seatHeight: Double
    public var leg: String
    /// The back legs' type (nil = `leg`).
    public var backLeg: String?
    public var legInset: Double
    public var rail: String
    public var seat: Seat
    public var back: Back
    /// The back's height range (nil: from 5" above the seat to the Top).
    public var backRange: ClosedRange<Double>?
    public var stretchers: (type: String, height: Double)?
    /// Arm rails on the back legs: type and height of their top.
    public var arms: (type: String, height: Double)?
    public init(seatHeight: Double = 18, leg: String = "Square 1 1/2\"", backLeg: String? = nil, legInset: Double = 0.5, rail: String = "3/4\" x 3\" Apron",
                seat: Seat = .wood("1\" Solid Oak Shelf"), back: Back = .slats(count: 3, type: "3/4\" x 2 1/2\" Slat"), backRange: ClosedRange<Double>? = nil,
                stretchers: (type: String, height: Double)? = nil, arms: (type: String, height: Double)? = nil) {
        self.seatHeight = seatHeight; self.leg = leg; self.backLeg = backLeg; self.legInset = legInset; self.rail = rail; self.seat = seat; self.back = back
        self.backRange = backRange; self.stretchers = stretchers; self.arms = arms
    }
}

/// The parts a chair recipe made.
public struct Chair: Sendable {
    public var legs: [ElementID] = []
    public var rails: [ElementID] = []
    public var seat: [ElementID] = []
    public var back: [ElementID] = []
    public var stretchers: [ElementID] = []
    public var arms: [ElementID] = []
}

extension LibraryBuilder {
    /// Builds a chair (see `ChairSpec`).
    @discardableResult
    public func chair(_ s: ChairSpec) throws -> Chair {
        var out = Chair()
        let (lw, ld) = legSize(s.leg)
        let backLeg = s.backLeg ?? s.leg
        let (bw, bd) = legSize(backLeg)
        let seatT: Double = switch s.seat {
        case .wood(let t): thickness(type(.furnitureShelves, t))
        case .upholstered(_, let th): 0.5 + th
        }
        let underSeat = s.seatHeight - seatT
        let hasBack: Bool = if case .none = s.back { false } else { true }
        let x0 = l + s.legInset, x1 = r - s.legInset, y0 = f + s.legInset, y1 = b - s.legInset
        let fxL = x0 + lw / 2, fxR = x1 - lw / 2, fy = y0 + ld / 2
        let bxL = x0 + bw / 2, bxR = x1 - bw / 2, by = y1 - bd / 2
        out.legs.append(try leg(at: Vec2(fxL, fy), z: 0...underSeat, type: s.leg))
        out.legs.append(try leg(at: Vec2(fxR, fy), z: 0...underSeat, type: s.leg))
        let backTop = hasBack ? h : underSeat
        out.legs.append(try leg(at: Vec2(bxL, by), z: 0...backTop, type: backLeg))
        out.legs.append(try leg(at: Vec2(bxR, by), z: 0...backTop, type: backLeg))
        // Seat rails between the legs, flush with the seat's underside.
        let rw = railSize(s.rail).width
        out.rails.append(try rail(from: Vec2(fxL + lw / 2, fy), to: Vec2(fxR - lw / 2, fy), z: underSeat, type: s.rail))
        out.rails.append(try rail(from: Vec2(bxR - bw / 2, by), to: Vec2(bxL + bw / 2, by), z: underSeat, type: s.rail))
        out.rails.append(try rail(from: Vec2(x0 + rw / 2, by - bd / 2), to: Vec2(x0 + rw / 2, fy + ld / 2), z: underSeat, type: s.rail))
        out.rails.append(try rail(from: Vec2(x1 - rw / 2, fy + ld / 2), to: Vec2(x1 - rw / 2, by - bd / 2), z: underSeat, type: s.rail))
        switch s.seat {
        case .wood(let t):
            out.seat.append(try shelf(x: l...r, y: f...(hasBack ? y1 - bd : b), top: s.seatHeight, type: t, role: .top))
        case .upholstered(let mat, let th):
            let deck = "1/2\" Plywood Shelf"
            out.seat.append(try shelf(x: (x0 + 0.25)...(x1 - 0.25), y: (y0 + 0.25)...(hasBack ? y1 - bd : y1 - 0.25), top: underSeat + 0.5, type: deck))
            out.seat.append(try cushion(x: (l + 0.25)...(r - 0.25), y: f...(hasBack ? y1 - bd : b), z: underSeat + 0.5, height: th, crown: min(0.75, th * 0.3),
                                        radius: 1.25, material: mat))
        }
        let br = s.backRange ?? (s.seatHeight + 5)...(h - 0.5)
        switch s.back {
        case .none: break
        case .slats(let count, let t):
            let (sw, sh) = railSize(t)
            let top = try railXZ(from: Vec2(bxL + bw / 2, h - 1.5), to: Vec2(bxR - bw / 2, h - 1.5), y: by, type: "3/4\" x 3\" Apron")
            out.back.append(top)
            let low = try railXZ(from: Vec2(bxL + bw / 2, br.lowerBound), to: Vec2(bxR - bw / 2, br.lowerBound), y: by, type: "3/4\" x 1 1/2\" Stretcher")
            out.back.append(low)
            let span = bxR - bxL - bw
            for k in 0..<count {
                let x = bxL + bw / 2 + span * Double(k + 1) / Double(count + 1)
                out.back.append(try railXZ(from: Vec2(x, br.lowerBound + 0.75), to: Vec2(x, h - 3), y: by, type: t))
            }
            _ = (sw, sh)
        case .rails(let count, let t):
            for k in 0..<count {
                let z = br.lowerBound + (br.upperBound - br.lowerBound) * Double(k) / Double(max(1, count - 1))
                out.back.append(try railXZ(from: Vec2(bxL + bw / 2, z), to: Vec2(bxR - bw / 2, z), y: by, type: t))
            }
        case .upholstered(let mat, let th):
            let pad = FurnitureForms.roundedRect(Vec2(0, (br.lowerBound + br.upperBound) / 2), bxR - bxL - bw - 0.5, br.upperBound - br.lowerBound, 1.5)
            out.back.append(try extrusion(pad, plane: .xz, w: (by - bd / 2 - th)...(by - bd / 2 + 0.25), material: mat))
        }
        if let st = s.stretchers {
            out.stretchers.append(try rail(from: Vec2(fxL, fy + ld / 2), to: Vec2(bxL, by - bd / 2), z: st.height, type: st.type))
            out.stretchers.append(try rail(from: Vec2(bxR, by - bd / 2), to: Vec2(fxR, fy + ld / 2), z: st.height, type: st.type))
        }
        if let a = s.arms {
            let aw = railSize(a.type).width
            out.arms.append(try rail(from: Vec2(bxL, by - bd / 2), to: Vec2(bxL, f + 1), z: a.height, type: a.type))
            out.arms.append(try rail(from: Vec2(bxR, f + 1), to: Vec2(bxR, by - bd / 2), z: a.height, type: a.type))
            _ = aw
        }
        return out
    }
}

// MARK: - Bed

/// A bed: headboard, footboard (or none), side rails with cleats, slats, a centre rail, legs, a mattress and bedding.
public struct BedSpec: Sendable {
    public enum Headboard: Sendable {
        case panel(String)
        case upholstered(material: String, thickness: Double, channels: Int)
    }
    /// Frame boards (headboard, footboard, rails).
    public var frame: String
    public var headboard: Headboard
    /// Footboard height (nil = no footboard: legs at the foot).
    public var footboard: Double?
    /// Rail top and height; the slats sit `slatDrop` below the rail top.
    public var railTop: Double
    public var railHeight: Double
    public var slatDrop: Double
    public var leg: String
    public var slat: String
    public var mattressThickness: Double
    public var mattressMaterial: String
    /// Bedding: pillows across the head and a duvet over the lower part.
    public var pillows: Int
    public var duvet: String?
    public init(frame: String = "3/4\" Solid Oak", headboard: Headboard = .panel("3/4\" Solid Oak"), footboard: Double? = nil, railTop: Double = 14, railHeight: Double = 7,
                slatDrop: Double = 3, leg: String = "Square 1 1/2\"", slat: String = "1\" x 3\" Bed Slat", mattressThickness: Double = 11, mattressMaterial: String = "Mattress",
                pillows: Int = 2, duvet: String? = "Fabric - White Cotton") {
        self.frame = frame; self.headboard = headboard; self.footboard = footboard; self.railTop = railTop; self.railHeight = railHeight; self.slatDrop = slatDrop
        self.leg = leg; self.slat = slat; self.mattressThickness = mattressThickness; self.mattressMaterial = mattressMaterial; self.pillows = pillows; self.duvet = duvet
    }
}

/// The parts a bed recipe made.
public struct Bed: Sendable {
    public var headboard: [ElementID] = []
    public var footboard: [ElementID] = []
    public var rails: [ElementID] = []
    public var slats: ElementID?
    public var legs: [ElementID] = []
    public var mattress: ElementID?
    public var bedding: [ElementID] = []
    /// The space inside the rails (inches) and the mattress's top.
    public var inside: (x: ClosedRange<Double>, y: ClosedRange<Double>) = (0...0, 0...0)
    public var mattressTop: Double = 0
}

extension LibraryBuilder {
    /// Builds a bed (see `BedSpec`). Width and Depth are the frame's outside; the mattress fills the inside less 1/2".
    @discardableResult
    public func bed(_ s: BedSpec) throws -> Bed {
        var out = Bed()
        let t = thickness(type(.furniturePanels, s.frame))
        var hbT = t
        switch s.headboard {
        case .panel(let pt):
            hbT = thickness(type(.furniturePanels, pt))
            out.headboard.append(try board(x: l...r, y: (b - hbT)...b, z: 0...h, type: pt))
        case .upholstered(let mat, let th, let channels):
            hbT = t + th
            out.headboard.append(try board(x: l...r, y: (b - t)...b, z: 0...h, type: s.frame))
            let n = max(1, channels)
            let x0 = l + 1.0, x1 = r - 1.0, z0 = s.railTop - 1, z1 = h - 1
            let cw = (x1 - x0) / Double(n)
            for k in 0..<n {
                let a = x0 + cw * Double(k), c = a + cw
                let pad = FurnitureForms.roundedRect(Vec2((a + c) / 2, (z0 + z1) / 2), cw - 0.25, z1 - z0, min(1.5, cw / 3))
                out.headboard.append(try extrusion(pad, plane: .xz, w: (b - t - th)...(b - t), material: mat))
            }
        }
        let footT = s.footboard == nil ? 0 : t
        if let fh = s.footboard { out.footboard.append(try board(x: l...r, y: f...(f + t), z: 0...fh, type: s.frame)) }
        let railBottom = s.railTop - s.railHeight
        let ry0 = f + footT, ry1 = b - hbT
        out.rails.append(try board(x: l...(l + t), y: ry0...ry1, z: railBottom...s.railTop, type: s.frame))
        out.rails.append(try board(x: (r - t)...r, y: ry0...ry1, z: railBottom...s.railTop, type: s.frame))
        if s.footboard == nil {
            out.rails.append(try board(x: (l + t)...(r - t), y: f...(f + t), z: railBottom...s.railTop, type: s.frame))
        }
        // Cleats on the rails' inside faces carry the slats; a centre rail on legs carries their middle.
        let slatTop = s.railTop - s.slatDrop
        let (sw, sh) = railSize(s.slat)
        _ = sw
        let cleat = "3/4\" x 3/4\" Cleat"
        let cy0 = ry0 + (s.footboard == nil ? t : 0), cy1 = ry1
        out.rails.append(try rail(from: Vec2(l + t + 0.375, cy1), to: Vec2(l + t + 0.375, cy0), z: slatTop - sh, type: cleat))
        out.rails.append(try rail(from: Vec2(r - t - 0.375, cy0), to: Vec2(r - t - 0.375, cy1), z: slatTop - sh, type: cleat))
        out.rails.append(try rail(from: Vec2(0, cy1), to: Vec2(0, cy0), z: slatTop - sh, type: "1 1/2\" x 1 1/2\" Stretcher"))
        out.slats = try slats(x: (l + t)...(r - t), y: cy0...cy1, z: slatTop, alongX: true, spacing: 5, type: s.slat)
        let (lw, _) = legSize(s.leg)
        for y in [cy0 + lw / 2 + 0.5, cy1 - lw / 2 - 0.5] { out.legs.append(try leg(at: Vec2(0, y), z: 0...(slatTop - sh - 1.5), type: s.leg)) }
        if s.footboard == nil {
            for x in [l + lw / 2, r - lw / 2] { out.legs.append(try leg(at: Vec2(x, f + lw / 2), z: 0...railBottom, type: s.leg)) }
        }
        out.inside = ((l + t)...(r - t), cy0...cy1)
        // Mattress and bedding.
        let mx = (l + t + 0.25)...(r - t - 0.25), my = (cy0 + 0.25)...(cy1 - 0.25)
        out.mattress = try cushion(x: mx, y: my, z: slatTop, height: s.mattressThickness, crown: 0.75, radius: 2, piping: true, material: s.mattressMaterial)
        out.mattressTop = slatTop + s.mattressThickness
        let mt = out.mattressTop
        if let duvet = s.duvet {
            // A duvet over the foot two thirds, hanging down the sides and the foot.
            let dy1 = my.lowerBound + (my.upperBound - my.lowerBound) * 0.7
            let dx = (mx.lowerBound - 0.5)...(mx.upperBound + 0.5)
            out.bedding.append(try cushion(x: dx, y: (my.lowerBound - 0.5)...dy1, z: mt - 6, height: 7, crown: 1, radius: 2, piping: false, material: duvet))
            out.bedding.append(try cushion(x: dx, y: (dy1 - 4)...(dy1 + 2), z: mt, height: 2.5, crown: 0.75, radius: 1.25, piping: false, material: duvet))
        }
        if s.pillows > 0 {
            let n = s.pillows
            let pw = min(26, (mx.upperBound - mx.lowerBound - 2) / Double(n))
            let gap = ((mx.upperBound - mx.lowerBound) - pw * Double(n)) / Double(n + 1)
            for k in 0..<n {
                let x0 = mx.lowerBound + gap + (pw + gap) * Double(k)
                out.bedding.append(try cushion(x: x0...(x0 + pw), y: (my.upperBound - 19)...(my.upperBound - 1), z: mt, height: 5, crown: 1.5, radius: 3, piping: false,
                                               material: "Fabric - White Cotton"))
            }
        }
        return out
    }
}

// MARK: - Shelving

/// Open shelving on four posts: shelves at even spacing (or given heights), optional cross braces at the back.
public struct ShelvingSpec: Sendable {
    public var post: String
    public var shelf: String
    public var count: Int
    /// Heights of the shelves' tops (nil = `count` shelves from `bottom` to the Top, evenly).
    public var heights: [Double]?
    public var bottom: Double
    /// Back cross braces (a rail type), drawn in the back elevation.
    public var brace: String?
    public init(post: String = "Square 1 1/2\"", shelf: String = "3/4\" Plywood Shelf", count: Int = 5, heights: [Double]? = nil, bottom: Double = 4, brace: String? = nil) {
        self.post = post; self.shelf = shelf; self.count = count; self.heights = heights; self.bottom = bottom; self.brace = brace
    }
}

extension LibraryBuilder {
    /// Builds open shelving (see `ShelvingSpec`): posts at the corners, shelves between them. Returns posts, shelves, braces.
    @discardableResult
    public func shelving(_ s: ShelvingSpec) throws -> (posts: [ElementID], shelves: [ElementID], braces: [ElementID]) {
        let posts = try legs(x: l...r, y: f...b, z: 0...h, type: s.post)
        let ts = thickness(type(.furnitureShelves, s.shelf))
        let n = max(1, s.count)
        let tops = s.heights ?? (0..<n).map { k in n == 1 ? s.bottom + ts : s.bottom + ts + (h - s.bottom - ts) * Double(k) / Double(n - 1) }
        var shelves: [ElementID] = []
        for z in tops { shelves.append(try shelf(x: l...r, y: f...b, top: z, type: s.shelf)) }
        var braces: [ElementID] = []
        if let br = s.brace {
            let (pw, pd) = legSize(s.post)
            let y = b - pd / 2
            let z0 = tops.first ?? 0, z1 = tops.last ?? h
            braces.append(try railXZ(from: Vec2(l + pw, z0), to: Vec2(r - pw, z1 - ts), y: y, type: br))
            braces.append(try railXZ(from: Vec2(r - pw, z0), to: Vec2(l + pw, z1 - ts), y: y + railSize(br).width, type: br))
        }
        return (posts, shelves, braces)
    }
}

// MARK: - Upholstered

/// A sofa, loveseat, armchair, ottoman or upholstered bench: an upholstered base on legs, track arms, a back frame,
/// seat cushions with crowned tops and piping, back cushions and throw pillows.
public struct UpholsteredSpec: Sendable {
    public var fabric: String
    /// Seat cushions across (0 = a single tight seat).
    public var seats: Int
    /// Top of the seat cushions.
    public var seatHeight: Double
    public var cushionThickness: Double
    /// Arm width (0 = armless) and height of the arm's top.
    public var armWidth: Double
    public var armHeight: Double
    /// The back frame's thickness (0 = no back: an ottoman or bench).
    public var backThickness: Double
    public var backCushions: Bool
    public var leg: String
    public var legHeight: Double
    /// Legs in the middle of long pieces too.
    public var centerLegs: Bool
    public var pillows: Int
    public var pillowFabric: String?
    public init(fabric: String = "Fabric - Oatmeal Linen", seats: Int = 3, seatHeight: Double = 18, cushionThickness: Double = 5, armWidth: Double = 6, armHeight: Double = 25,
                backThickness: Double = 7, backCushions: Bool = true, leg: String = "Round Tapered 2\"", legHeight: Double = 4, centerLegs: Bool = false,
                pillows: Int = 0, pillowFabric: String? = nil) {
        self.fabric = fabric; self.seats = seats; self.seatHeight = seatHeight; self.cushionThickness = cushionThickness; self.armWidth = armWidth; self.armHeight = armHeight
        self.backThickness = backThickness; self.backCushions = backCushions; self.leg = leg; self.legHeight = legHeight; self.centerLegs = centerLegs
        self.pillows = pillows; self.pillowFabric = pillowFabric
    }
}

/// The parts an upholstered recipe made.
public struct Upholstered: Sendable {
    public var base: [ElementID] = []
    public var arms: [ElementID] = []
    public var back: [ElementID] = []
    public var seat: [ElementID] = []
    public var backCushions: [ElementID] = []
    public var pillows: [ElementID] = []
    public var legs: [ElementID] = []
    public var frame: [ElementID] = []
    /// The seat's clear width between the arms and its depth (inches).
    public var seatX: ClosedRange<Double> = 0...0
    public var seatY: ClosedRange<Double> = 0...0
}

extension LibraryBuilder {
    /// Builds an upholstered piece (see `UpholsteredSpec`).
    @discardableResult
    public func upholstered(_ s: UpholsteredSpec) throws -> Upholstered {
        var out = Upholstered()
        let fab = s.fabric
        let lh = s.legHeight
        let deck = s.seatHeight - s.cushionThickness
        let aw = s.armWidth, bt = s.backThickness
        // Hardwood frame: front and back rails and the deck (hidden inside the upholstery, for the cut list).
        let frameRail = "3/4\" Plywood"
        let ft = thickness(type(.furniturePanels, frameRail))
        out.frame.append(try board(x: (l + aw + 0.5)...(r - aw - 0.5), y: (f + 1)...(f + 1 + ft), z: (lh + 0.5)...(deck - 1.5), type: frameRail))
        out.frame.append(try board(x: (l + aw + 0.5)...(r - aw - 0.5), y: (b - bt + 0.5)...(b - bt + 0.5 + ft), z: (lh + 0.5)...(deck - 1.5), type: frameRail))
        // The upholstered base box: round-cornered in plan, from the legs' top to the deck.
        let baseLoop = FurnitureForms.roundedRect(Vec2((l + r) / 2, (f + b) / 2), w, d, 1)
        out.base.append(try extrusion(baseLoop, plane: .xy, w: lh...deck, material: fab))
        // Arms: a side profile with a rounded top, extruded across the arm's width.
        if aw > 0 {
            let prof = FurnitureForms.roundedRect(Vec2((f + b) / 2, (deck + s.armHeight) / 2), d, s.armHeight - deck, min(2.5, aw / 2.2))
            out.arms.append(try extrusion(prof, plane: .yz, w: l...(l + aw), material: fab))
            out.arms.append(try extrusion(prof, plane: .yz, w: (r - aw)...r, material: fab))
        }
        // The back frame: rounded top, the full width behind the arms.
        if bt > 0 {
            let prof = FurnitureForms.roundedRect(Vec2(b - bt / 2, (deck + h) / 2), bt, h - deck, min(2.5, bt / 2.5))
            out.back.append(try extrusion(prof, plane: .yz, w: (l + (aw > 0 ? 0.25 : 0))...(r - (aw > 0 ? 0.25 : 0)), material: fab))
        }
        // Seat cushions between the arms, from the front to the back frame.
        let sx0 = l + aw, sx1 = r - aw
        let sy0 = f + 0.25, sy1 = bt > 0 ? b - bt : b - 0.25
        out.seatX = sx0...sx1; out.seatY = sy0...sy1
        let n = max(1, s.seats)
        let cw = (sx1 - sx0) / Double(n)
        for k in 0..<n {
            let a = sx0 + cw * Double(k)
            out.seat.append(try cushion(x: (a + 0.125)...(a + cw - 0.125), y: sy0...sy1, z: deck, height: s.cushionThickness, crown: 0.75, radius: 2,
                                        material: fab))
        }
        // Back cushions: a soft wedge leaning back against the frame.
        if bt > 0, s.backCushions {
            let bf = b - bt
            let zt = min(h - 1, s.armHeight + 9)
            for k in 0..<n {
                let a = sx0 + cw * Double(k)
                let wedge = [Vec2(bf - 6.5, s.seatHeight), Vec2(bf, s.seatHeight), Vec2(bf, zt), Vec2(bf - 4, zt)]
                let soft = LibraryKit.softPolygon(wedge, radius: 1.75)
                out.backCushions.append(try extrusion(soft, plane: .yz, w: (a + 0.25)...(a + cw - 0.25), material: fab))
            }
        }
        // Throw pillows against the arms.
        if s.pillows > 0, bt > 0 {
            let pf = s.pillowFabric ?? fab
            let bf = b - bt - (s.backCushions ? 6 : 0)
            let size = min(18, h - s.seatHeight - 3)
            for (k, xr) in [(sx0 + 1)...(sx0 + 1 + size), (sx1 - 1 - size)...(sx1 - 1)].prefix(s.pillows).enumerated() {
                let sq = FurnitureForms.roundedRect(Vec2((xr.lowerBound + xr.upperBound) / 2, s.seatHeight + size / 2 - 1.5), size, size, 4)
                out.pillows.append(try extrusion(sq, plane: .xz, w: (bf - 5)...bf, material: pf))
                _ = k
            }
        }
        // Legs under the base's corners (and the middle of long pieces).
        let (lw, _) = legSize(s.leg)
        let inset = 1.5 + lw / 2
        var xs = [l + inset, r - inset]
        if s.centerLegs { xs.append((l + r) / 2) }
        for x in xs { for y in [f + inset, b - inset] { out.legs.append(try leg(at: Vec2(x, y), z: 0...lh, type: s.leg)) } }
        return out
    }
}

extension LibraryKit {
    /// A polygon with its corners rounded by `radius` (counterclockwise output), for soft cushion profiles.
    public static func softPolygon(_ pts: [Vec2], radius: Double, steps: Int = 5) -> [Vec2] {
        let poly = Polygon2(pts).counterClockwise.points
        let n = poly.count
        guard n >= 3 else { return pts }
        var out: [Vec2] = []
        for i in 0..<n {
            let p = poly[i], a = poly[(i + n - 1) % n], c = poly[(i + 1) % n]
            let u = (a - p).normalized, v = (c - p).normalized
            let la = (a - p).length, lc = (c - p).length
            let rr = min(radius, la / 2.2, lc / 2.2)
            let p0 = p + u * rr, p1 = p + v * rr
            for k in 0...steps {
                let t = Double(k) / Double(steps)
                // Quadratic Bezier from p0 through the corner p to p1.
                let q = p0 * ((1 - t) * (1 - t)) + p * (2 * (1 - t) * t) + p1 * (t * t)
                out.append(q)
            }
        }
        return out
    }
}
