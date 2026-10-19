import Foundation
import ArcusGeometry

// FM9B: frame builders of the simple pieces: tables and desks (a top on legs with aprons, stretchers and a lower
// shelf), seats (chairs, stools and benches: a seat on legs, a back of rails, slats or a panel, arms), beds (posts,
// rails, slats and a mattress, a headboard and footboard), upholstered seating (a sofa's arms, back, deck and
// cushions) and racks (posts and shelves on formula planes).

extension SA.Builder {
    func legWidth(_ type: String) throws -> Double { FurniturePartTypes.Values(model[try self.type(.furnitureLegs, type)]?.typeData).width / SA.inch }
    func shelfThickness(_ type: String) throws -> Double { thickness(try self.type(.furnitureShelves, type)) / SA.inch }
    func panelThickness(_ type: String) throws -> Double { thickness(try self.type(.furniturePanels, type)) / SA.inch }
}

// MARK: - Tables

extension SA {
    /// A table or desk: a top on four legs, aprons, stretchers, a lower shelf and a drawer.
    struct TableSpec: Sendable {
        var top = SA.oakTop
        var leg = SA.tapered
        /// The legs' outer faces in from the top's edges.
        var legInset: Double = 1.5
        var apron: String? = SA.apron
        /// Stretchers this high (to their tops) between the legs, front and back and at the ends.
        var stretchers: Double? = nil
        var stretcherType = SA.stretcher
        /// A lower shelf with its top this high, between the legs.
        var shelf: (height: Double, type: String)? = nil
        /// A drawer in the front apron, under a rail this far below the top's underside.
        var drawer: Double? = nil
        /// Only end stretchers (and one along the middle): trestle-like desks and benches.
        var endStretchersOnly = false
        /// The formula of the table top's top face when it isn't the Top (a vanity's table under its mirror).
        var topPlane: String? = nil
        /// A top of this many slats (rails along X) instead of a board.
        var slats: Int? = nil
    }
}

extension SA.Piece {
    static func table(_ name: String, rooms: [String], _ category: FamilyTemplate = .furniture, material: String, sizes: [SA.Size], _ s: SA.TableSpec,
                      planes: [SA.Plane] = [], more: [Step] = []) -> SA.Piece {
        var steps: [Step] = [{ try SA.TableLayout(s, $0).build() }]
        if s.drawer != nil { steps.append { try SA.TableLayout(s, $0).drawer() } }
        let top = s.topPlane.map { [SA.Plane("Table Top", .z, $0)] } ?? []
        return SA.Piece(name, rooms: rooms, category, material: material, sizes: sizes, planes: top + planes, steps: steps + more)
    }
}

extension SA {
    struct TableLayout {
        let s: SA.TableSpec
        let b: SA.Builder
        let topT: Double, w: Double

        init(_ s: SA.TableSpec, _ b: SA.Builder) {
            self.s = s; self.b = b
            topT = s.slats != nil ? 0.75 : (try? b.shelfThickness(s.top)) ?? 1
            w = (try? b.legWidth(s.leg)) ?? 1.5
        }

        var topZ: SA.LP { s.topPlane == nil ? SA.T : SA.p("Table Top") }
        var under: SA.LP { topZ - topT }
        var x: (SA.LP, SA.LP) { (SA.L + s.legInset, SA.R - s.legInset) }
        var y: (SA.LP, SA.LP) { (SA.F + s.legInset, SA.B - s.legInset) }

        func build() throws {
            if let n = s.slats {
                // Slats 2 1/2" wide, the outer ones on the Front and Back, the rest spaced between them.
                let depth = (b.v(SA.B) - b.v(SA.F)) / SA.inch - 2.5
                for k in 0..<n {
                    let d = 1.25 + depth * Double(k) / Double(max(1, n - 1))
                    try b.railX((SA.L, SA.R), y: k < n / 2 ? SA.F + d : SA.B - (depth + 2.5 - d), top: topZ, SA.slat)
                }
            } else {
                try b.board(x: (SA.L, SA.R), y: (SA.F, SA.B), top: topZ, s.top, role: .top)
            }
            try b.legs(x: x, y: y, inset: w / 2, z: (SA.Z, under), s.leg)
            if let apron = s.apron {
                try b.aprons(x: x, y: y, inset: w / 2, legWidth: w, top: under, apron, sides: s.drawer == nil ? ["F", "B", "L", "R"] : ["B", "L", "R"])
                if let d = s.drawer {
                    // The drawer rail under the drawer opening, between the front legs.
                    try b.railX((x.0 + w, x.1 - w), y: y.0 + 0.375, top: under - d, SA.stretcher)
                }
            }
            if let h = s.stretchers {
                let z = SA.Z + h
                if s.endStretchersOnly {
                    try b.aprons(x: x, y: y, inset: w / 2, legWidth: w, top: z, s.stretcherType, sides: ["L", "R"])
                    try b.railX((x.0 + w, x.1 - w), y: SA.CY, top: z - 0.75, s.stretcherType)
                } else {
                    try b.aprons(x: x, y: y, inset: w / 2, legWidth: w, top: z, s.stretcherType)
                }
            }
            if let sh = s.shelf {
                try b.board(x: (x.0 + w, x.1 - w), y: (y.0, y.1), top: SA.Z + sh.height, sh.type)
            }
        }

        func drawer() throws {
            guard let d = s.drawer else { return }
            _ = try b.drawers(SA.CX, under - d / 2, count: 1, "Slab - Inset")
        }
    }
}

// MARK: - Seats

extension SA {
    /// A seat's back.
    enum SeatBack: Sendable {
        case none
        /// Horizontal rails between the back posts (ladder back), from the top down.
        case rails(Int)
        /// Vertical slats between a top rail and the seat.
        case slats(Int)
        /// A panel (splat or upholstered back) between the posts.
        case panel(String)
    }
}

extension SA {
    /// A chair, stool or bench: a seat board on legs, seat rails, a back, arms, a cushion and footrests.
    struct SeatSpec: Sendable {
        /// The formula of the seat's top face ("Height * 0.53"); stools and benches sit at the Top.
        var seat = "Height"
        var seatType = SA.oakTop
        var leg = SA.sq
        var legInset: Double = 0.5
        /// The legs' inset from the Front and Back when it differs (rockers reaching past the legs).
        var legInsetY: Double? = nil
        var apron: String? = SA.apron
        var back: SA.SeatBack = .none
        /// Arm rests on the front legs, this formula high.
        var arms: String? = nil
        var cushion: String? = nil
        /// Stretchers (footrests) this high between the legs.
        var stretchers: Double? = nil
        var stretcherType = SA.stretcher
        /// An octagonal seat with its corners cut this much (stools).
        var octagon: Double? = nil
        /// The legs stand on runners (rockers) this high, along the sides.
        var runners: Double? = nil
    }
}

extension SA.Piece {
    static func seat(_ name: String, rooms: [String], material: String, sizes: [SA.Size], _ s: SA.SeatSpec, more: [Step] = []) -> SA.Piece {
        var planes = [SA.Plane("Seat", .z, s.seat)]
        if let a = s.arms { planes.append(SA.Plane("Arm", .z, a)) }
        return SA.Piece(name, rooms: rooms, material: material, sizes: sizes, planes: planes, steps: [{ try SA.SeatLayout(s, $0).build() }] + more)
    }
}

extension SA {
    struct SeatLayout {
        let s: SA.SeatSpec
        let b: SA.Builder

        init(_ s: SA.SeatSpec, _ b: SA.Builder) { self.s = s; self.b = b }

        func build() throws {
            let seatT = try b.shelfThickness(s.seatType), w = try b.legWidth(s.leg)
            let seat = SA.p("Seat"), under = seat - seatT
            let hasBack: Bool = { if case .none = s.back { return false }; return true }()
            let iy = s.legInsetY ?? s.legInset
            let x = (SA.L + s.legInset, SA.R - s.legInset), y = (SA.F + iy, SA.B - iy)
            let cx = (x.0 + w / 2, x.1 - w / 2), fy = y.0 + w / 2, by = y.1 - w / 2
            // Legs: the back ones run up as the back posts; on rockers, the legs stand on them.
            let frontTop = s.arms != nil ? SA.p("Arm") - 0.75 : under
            var foot = SA.Z
            if let r = s.runners {
                let rise = try rockers(thickness: r, at: [cx.0, cx.1], legY: b.v(fy), legWidth: w)
                foot = SA.Z + rise
            }
            for xx in [cx.0, cx.1] {
                try b.leg(xx, fy, z: (foot, frontTop), s.leg)
                try b.leg(xx, by, z: (foot, hasBack ? SA.T : under), s.leg)
            }
            // The seat: between the front legs when they run up to the arms, and in front of the back posts.
            let seatX = s.arms != nil ? (x.0 + w, x.1 - w) : (SA.L, SA.R)
            let seatBack = hasBack ? y.1 - w : SA.B
            // The seat's front: on the Front, or 1" past the front legs when they're set back (rockers reach past them).
            let seatFront = s.legInsetY == nil ? SA.F : y.0 - 1
            if let cut = s.octagon {
                try b.octagon(x: seatX, y: (seatFront, seatBack), cut: cut, top: seat, s.seatType)
            } else {
                try b.board(x: seatX, y: (seatFront, seatBack), top: seat, s.seatType, role: .top)
            }
            if let c = s.cushion {
                try b.board(x: (seatX.0 + 0.5, seatX.1 - 0.5), y: (seatFront + 0.5, seatBack - 0.5), top: seat + (try b.shelfThickness(c)), c, role: .top)
            }
            if let apron = s.apron {
                let ax = (x.0 + w, x.1 - w), ay = (y.0 + w, y.1 - w)
                try b.railX(ax, y: fy, top: under, apron)
                try b.railX(ax, y: by, top: under, apron)
                try b.railY(ay, x: cx.0, top: under, apron)
                try b.railY(ay, x: cx.1, top: under, apron)
            }
            if let h = s.stretchers {
                let z = SA.Z + h, ax = (x.0 + w, x.1 - w), ay = (y.0 + w, y.1 - w)
                try b.railX(ax, y: fy, top: z, s.stretcherType)
                try b.railX(ax, y: by, top: z - 1.5, s.stretcherType)
                try b.railY(ay, x: cx.0, top: z - 0.75, s.stretcherType)
                try b.railY(ay, x: cx.1, top: z - 0.75, s.stretcherType)
            }
            if s.arms != nil {
                // Arm rests 2 1/2" wide over the front legs, flush with the Left and Right.
                for xx in [SA.L + 1.25, SA.R - 1.25] { try b.railY((y.0, y.1 - w), x: xx, top: SA.p("Arm"), SA.slat) }
            }
            // The back, between the posts.
            let bx = (x.0 + w, x.1 - w)
            switch s.back {
            case .none: break
            case .rails(let n):
                for k in 0..<n { try b.railX(bx, y: by, top: SA.T - (1 + Double(k) * 4.5), SA.apron) }
            case .slats(let n):
                try b.railX(bx, y: by, top: SA.T - 0.5, SA.apron)
                try b.railX(bx, y: by, top: seat + 4, SA.stretcher)
                let span = 3.0 * Double(n - 1)
                for k in 0..<n {
                    try b.leg(SA.CX + (-span / 2 + 3 * Double(k)), by, z: (seat + 4, SA.T - 3.5), "Square 1 3/4\" x 3/4\"")
                }
            case .panel(let type):
                let t = try b.panelThickness(type)
                // Flush with the posts' backs when it is thinner than them, else its back face on theirs.
                let face = t <= w ? SA.B - (iy + w / 2 + t / 2) : SA.B - (iy + t)
                try b.sideY(face, toward: 1, x: bx, z: (seat + 3, SA.T - 0.5), type)
            }
        }

        /// Curved rockers under the legs at `xs` (extrusions in the side view, locked to the side they're on, scaled
        /// between Front and Back, standing on the Bottom). Returns the rockers' top above the floor under the legs.
        func rockers(thickness r: Double, at xs: [SA.LP], legY: Double, legWidth w: Double) throws -> Double {
            let f = b.v(SA.F), bk = b.v(SA.B), cy = (f + bk) / 2, half = (bk - f) / 2, sag = 2.5 * SA.inch
            func z(_ y: Double) -> Double { sag * pow((y - cy) / half, 2) }
            let ys = (0...16).map { f + (bk - f) * Double($0) / 16 }
            let profile = ys.map { Vec2($0, z($0)) } + ys.reversed().map { Vec2($0, z($0) + r * SA.inch) }
            for (k, x) in xs.enumerated() {
                let xc = b.v(x)
                let fd = FurnitureFormData(kind: .extrusion, plane: .yz, profile: profile, w0: xc - w * SA.inch / 2, w1: xc + w * SA.inch / 2)
                let lock = FormLock.framing(b.model, x: k == 0 ? .low : .high, y: .scale, z: .low)
                try b.form(fd, material: FurniturePartTypes.Values(b.model[try b.type(.furnitureLegs, s.leg)]?.typeData).material.flatMap { b.model[$0]?.name }, lock: lock)
            }
            return (z(legY) + r * SA.inch) / SA.inch
        }
    }
}

// MARK: - Beds

extension SA {
    /// A bed: posts, side and end rails, cleats and slats, a mattress, a headboard and a footboard (head at the Back).
    struct BedSpec: Sendable {
        var post = "Square 3 1/2\" Post"
        /// The rails' tops above the floor.
        var railTop: Double = 14
        var rail = "1 1/2\" x 5 1/2\" Bed Rail"
        var slats = 12
        var mattress = "10\" Mattress"
        /// A headboard panel between the head posts, up to the Top.
        var headboard: String? = SA.oak
        /// A footboard panel this high (its top above the floor).
        var footboard: (height: Double, type: String)? = nil
        /// The foot posts' tops above the floor (nil: just above the rails).
        var footPost: Double? = nil
        /// Slats run across the Width (along X), between the side rails; false: along Y, between the end rails (daybeds).
        var slatsAlongX = true
    }
}

extension SA.Piece {
    static func bed(_ name: String, rooms: [String], material: String, sizes: [SA.Size], _ s: SA.BedSpec, planes: [SA.Plane] = [],
                    more: [Step] = []) -> SA.Piece {
        SA.Piece(name, rooms: rooms, material: material, sizes: sizes, planes: planes, steps: [{ try SA.BedLayout(s, $0).build() }] + more)
    }
}

extension SA {
    struct BedLayout {
        let s: SA.BedSpec
        let b: SA.Builder
        init(_ s: SA.BedSpec, _ b: SA.Builder) { self.s = s; self.b = b }

        func build() throws {
            let p = try b.legWidth(s.post), railW = 1.5
            let top = SA.Z + s.railTop
            // Posts at the corners.
            try b.leg(SA.L + p / 2, SA.B - p / 2, z: (SA.Z, s.headboard == nil ? top + 2 : SA.T), s.post)
            try b.leg(SA.R - p / 2, SA.B - p / 2, z: (SA.Z, s.headboard == nil ? top + 2 : SA.T), s.post)
            let foot = SA.Z + (s.footPost ?? (s.footboard.map { $0.height + 1 } ?? s.railTop + 2))
            try b.leg(SA.L + p / 2, SA.F + p / 2, z: (SA.Z, foot), s.post)
            try b.leg(SA.R - p / 2, SA.F + p / 2, z: (SA.Z, foot), s.post)
            try frame(at: top, inset: p, railW: railW, posts: true)
            if let h = s.headboard {
                let t = try b.panelThickness(h)
                try b.sideY(SA.B - (p / 2 + t / 2), toward: 1, x: (SA.L + p, SA.R - p), z: (top, SA.T - 1), h)
            }
            if let f = s.footboard {
                let t = try b.panelThickness(f.type)
                try b.sideY(SA.F + (p / 2 - t / 2), toward: 1, x: (SA.L + p, SA.R - p), z: (top, SA.Z + f.height), f.type)
            }
        }

        /// Side and end rails between the posts (`inset` square), cleats on the side rails, slats on them and the mattress.
        func frame(at top: SA.LP, inset p: Double, railW: Double, posts: Bool) throws {
            let ix = (SA.L + p / 2, SA.R - p / 2), iy = (SA.F + p / 2, SA.B - p / 2)
            try b.railY((SA.F + p, SA.B - p), x: ix.0, top: top, s.rail)
            try b.railY((SA.F + p, SA.B - p), x: ix.1, top: top, s.rail)
            try b.railX((SA.L + p, SA.R - p), y: iy.0, top: top, s.rail)
            try b.railX((SA.L + p, SA.R - p), y: iy.1, top: top, s.rail)
            // Cleats along the side (or end) rails' inside faces; the slats sit on them.
            let inL = ix.0 + railW / 2, inR = ix.1 - railW / 2, inF = iy.0 + railW / 2, inB = iy.1 - railW / 2
            let slatTop = top - 1.5
            let n = max(2, s.slats)
            if s.slatsAlongX {
                try b.railY((SA.F + p, SA.B - p), x: inL + 0.375, top: slatTop - 1, SA.cleat)
                try b.railY((SA.F + p, SA.B - p), x: inR - 0.375, top: slatTop - 1, SA.cleat)
                let y0 = inF + 2.5, y1 = inB - 2.5
                let length = b.v(y1) - b.v(y0)
                for k in 0..<n {
                    // The first half follows the foot, the rest the head (a fixed spacing at the default length).
                    let d = length * Double(k) / Double(n - 1) / SA.inch
                    let yy = k < n / 2 ? y0 + d : y1 - (length / SA.inch - d)
                    try b.railX((inL, inR), y: yy, top: slatTop, SA.bedSlat)
                }
            } else {
                try b.railX((SA.L + p, SA.R - p), y: inF + 0.375, top: slatTop - 1, SA.cleat)
                try b.railX((SA.L + p, SA.R - p), y: inB - 0.375, top: slatTop - 1, SA.cleat)
                let x0 = inL + 2.5, x1 = inR - 2.5
                let length = b.v(x1) - b.v(x0)
                for k in 0..<n {
                    let d = length * Double(k) / Double(n - 1) / SA.inch
                    let xx = k < n / 2 ? x0 + d : x1 - (length / SA.inch - d)
                    try b.railY((inF, inB), x: xx, top: slatTop, SA.bedSlat)
                }
            }
            let mT = try b.shelfThickness(s.mattress)
            let my = s.slatsAlongX ? (SA.F + (p + 0.25), SA.B - (p + 0.25)) : (inF + 0.25, inB - 0.25)
            let mx = s.slatsAlongX ? (inL + 0.25, inR - 0.25) : (SA.L + (p + 0.25), SA.R - (p + 0.25))
            try b.board(x: mx, y: my, top: slatTop + mT, s.mattress, role: .top)
        }
    }
}

// MARK: - Upholstered seating

extension SA {
    /// A sofa, loveseat or upholstered chair: arms, a back, a front rail and deck, seat and back cushions on short legs.
    struct SofaSpec: Sendable {
        /// Arm thickness (0: armless).
        var arm: Double = 6
        var seat = "Height * 0.53"
        var armHeight = "Height * 0.74"
        var legHeight: Double = 4
        var leg = SA.roundTapered
        var cushions = 3
        var cover = "Fabric"
        /// Seat cushion thickness (a "<n>\" Seat Cushion" type).
        var cushion = "5\" Seat Cushion"
        var backCushions = true
        /// Back thickness.
        var back: Double = 6
    }
}

extension SA.Piece {
    static func sofa(_ name: String, rooms: [String], material: String = "Fabric", sizes: [SA.Size], _ s: SA.SofaSpec, more: [Step] = []) -> SA.Piece {
        // The legs' tops are a share of the Height, so the base keeps its proportion as the piece flexes.
        let legShare = ((s.legHeight / max(1, sizes.first?.h ?? 34)) * 1000).rounded() / 1000
        var planes = [SA.Plane("Seat", .z, s.seat), SA.Plane("Arm", .z, s.armHeight), SA.Plane("Legs", .z, "Height * \(fmt(legShare))")]
        let a = s.arm
        for k in 1..<max(1, s.cushions) {
            planes.append(SA.Plane("Cushion \(k)", .x, "-Width / 2 + \(fmt(a))\" + (Width - \(fmt(2 * a))\") * \(k) / \(s.cushions)"))
        }
        return SA.Piece(name, rooms: rooms, material: material, sizes: sizes, planes: planes, steps: [{ try SA.SofaLayout(s, $0).build() }] + more)
    }

    /// A number for a formula: no trailing zeros.
    static func fmt(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
}

extension SA {
    struct SofaLayout {
        let s: SA.SofaSpec
        let b: SA.Builder
        init(_ s: SA.SofaSpec, _ b: SA.Builder) { self.s = s; self.b = b }

        func build() throws {
            // The upholstery in the piece's cover (copies of the Fabric types in another fabric or leather).
            let thick = try b.type(.furniturePanels, "6\" Upholstered Panel", material: s.cover), thin = try b.type(.furniturePanels, "3\" Upholstered Panel", material: s.cover)
            let cushion = try b.type(.furnitureShelves, s.cushion, material: s.cover)
            let base = SA.p("Legs"), seat = SA.p("Seat"), a = s.arm, bk = s.back
            let cT = try b.shelfThickness(s.cushion)
            let deck = seat - cT
            try b.legs(x: (SA.L, SA.R), y: (SA.F, SA.B), inset: 2, z: (SA.Z, base), s.leg)
            if a > 0 {
                for (x, dir) in [(SA.L, 1.0), (SA.R, -1.0)] {
                    try b.sideX(x, toward: dir, y: (SA.F, SA.B), z: (base, SA.p("Arm")), a >= 6 ? thick : thin)
                }
            }
            let ix = (SA.L + a, SA.R - a)
            try b.sideY(SA.B, toward: -1, x: ix, z: (base, SA.T), bk >= 6 ? thick : thin)
            try b.sideY(SA.F, toward: 1, x: ix, z: (base, deck), thin)
            try b.board(x: ix, y: (SA.F + 3, SA.B - bk), top: deck, try b.type(.furnitureShelves, SA.plyShelf, material: s.cover))
            // Seat and back cushions, split on the Cushion planes, with 1/8" between them.
            let backCushion = s.backCushions ? 6.0 : 0
            let cuts = [ix.0] + (1..<max(1, s.cushions)).map { SA.p("Cushion \($0)") } + [ix.1]
            for k in 0..<(cuts.count - 1) {
                let x0 = cuts[k] + 0.0625, x1 = cuts[k + 1] - 0.0625
                try b.board(x: (x0, x1), y: (SA.F, SA.B - (bk + backCushion + 0.125)), top: seat, cushion, role: .top)
                if s.backCushions {
                    try b.sideY(SA.B - (bk + 0.0625), toward: -1, x: (x0, x1), z: (seat + 0.125, SA.T - 1.5), thick)
                }
            }
        }
    }
}

// MARK: - Racks

extension SA {
    /// Open shelving on four posts: shelves on formula planes (equal spacing from the bottom shelf to the top).
    struct RackSpec: Sendable {
        var post = "Square 1\" Steel"
        var shelf = "1/8\" Steel Shelf"
        var shelves = 4
        /// The lowest shelf's top above the floor.
        var bottom: Double = 6
        /// Panels on the ends and back (bookcase-like racks) instead of open sides.
        var postInset: Double = 0
    }
}

extension SA.Piece {
    static func rack(_ name: String, rooms: [String], _ category: FamilyTemplate = .furniture, material: String, sizes: [SA.Size], _ s: SA.RackSpec,
                     more: [Step] = []) -> SA.Piece {
        let n = max(2, s.shelves)
        // The top shelf is on the Top; the others are equally spaced down to the bottom one.
        let planes = (1..<(n - 1)).map { k in SA.Plane("Shelf \(k + 1)", .z, "\(fmt(s.bottom))\" + (Height - \(fmt(s.bottom))\") * \(k) / \(n - 1)") }
        return SA.Piece(name, rooms: rooms, category, material: material, sizes: sizes, planes: planes, steps: [{ b in
            let w = try b.legWidth(s.post)
            try b.legs(x: (SA.L + s.postInset, SA.R - s.postInset), y: (SA.F, SA.B), inset: w / 2, z: (SA.Z, SA.T), s.post)
            let levels = [SA.Z + s.bottom] + (1..<(n - 1)).map { SA.p("Shelf \($0 + 1)") } + [SA.T]
            for z in levels {
                try b.board(x: (SA.L + (s.postInset + w), SA.R - (s.postInset + w)), y: (SA.F, SA.B), top: z, s.shelf)
            }
        }] + more)
    }
}
