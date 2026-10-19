import Foundation
import ArcusGeometry

// FM5: bays, as rooms (Room ▸ RM). A bay keeps a point inside it; its opening is the clear space between the nearest
// parts round that point (sides and dividers left and right, the bottom, shelves and the top below and above, or
// Bay Separators), found again at every regeneration so it follows the parts as they move. Seen from above (picked in
// plan), a bay is a top-access opening between sides, front and back. Bay Divide splits a bay into rows or columns
// (equal, EQ, or by dimension) like a curtain grid; each cell is a sub-bay element hosted by the bay.

public enum FurnitureBays {
    static let inch = 0.0254

    /// A part or separator that can bound a bay, with its box (and the planes its faces follow).
    struct Bounder {
        var id: ElementID
        var box: FurniturePartSolids.PartBox
        /// Dividers, fixed shelves and separators sit between two bays.
        var shared: Bool
        var isSeparator: Bool
    }

    /// The parts and separators that bound bays in a model, seen in a face's frame (FMG3: the front's unless a bay
    /// faces another way; boxes are the parts' extents in that frame).
    struct Scene {
        var bounders: [Bounder]
        var planes: [String: Double]
        var model: BIMModel
        var frame: BayFrame

        init(_ m: BIMModel, frame: BayFrame = .front) {
            model = m
            self.frame = frame
            planes = FurniturePlanes.positionsByName(m)
            var list: [Bounder] = []
            let boxes = FurniturePartBinder.boxes(m)
            for (id, b) in boxes {
                guard let e = m[id], e.furniturePanel?.role != .back else { continue }
                if e.furnitureShelf?.adjustable == true { continue } // FM9: adjustable shelves sit behind the fronts; they don't bound bays
                let role = e.furniturePartKind
                list.append(Bounder(id: id, box: frame.localBox(b), shared: role == .divider || role == .shelf, isSeparator: false)) // FMG3
            }
            if !frame.isSquare { list += FurnitureBays.cantedBounders(m, frame, skipping: Set(boxes.keys)) } // FMG3
            for s in m.elements(.furnitureBaySeparators) {
                guard let d = s.furnitureBaySeparator else { continue }
                if d.face == .front, BayFrame(angle: d.facing ?? 0) != frame { continue } // FMG3: separators of this face only
                let lo = Vec2(min(d.start.x, d.end.x), min(d.start.y, d.end.y)), hi = Vec2(max(d.start.x, d.end.x), max(d.start.y, d.end.y))
                // A separator is a zero-thickness box in its face.
                let far = 100.0
                let box: FurniturePartSolids.PartBox
                switch d.face {
                case .front: box = .init(x: (PartValue(lo.x), PartValue(hi.x)), y: (PartValue(-far), PartValue(far)), z: (PartValue(lo.y), PartValue(hi.y)))
                case .top: box = frame.localBox(.init(x: (PartValue(lo.x), PartValue(hi.x)), y: (PartValue(lo.y), PartValue(hi.y)), z: (PartValue(-far), PartValue(far))))
                }
                list.append(Bounder(id: s.id, box: box, shared: true, isSeparator: true))
            }
            bounders = list.sorted { $0.id < $1.id }
        }

        func plane(_ n: String) -> PartValue? { planes[n].map { PartValue($0, plane: n, offset: 0) } }

        /// FMG3: the opening's face when nothing bounds it on that side: the framing planes (Left/Right, Front/Back,
        /// Bottom/Top) seen in the frame. Keys as BayOpening's ("x0", "x1", "y0", "y1", "z0", "z1").
        func fallback(_ key: String) -> PartValue? {
            let names = ["x0": "Left", "x1": "Right", "y0": "Front", "y1": "Back", "z0": "Bottom", "z1": "Top"]
            if frame.isIdentity || key.hasPrefix("z") { return names[key].flatMap(plane) }
            guard let l = plane("Left"), let r = plane("Right"), let f = plane("Front"), let b = plane("Back") else { return nil }
            let lb = frame.localBox(.init(x: (l, r), y: (f, b), z: (PartValue(0), PartValue(0))))
            switch key {
            case "x0": return lb.x.0
            case "x1": return lb.x.1
            case "y0": return lb.y.0
            default: return lb.y.1
            }
        }
    }

    // MARK: Finding

    /// The opening round `p` seen from the front (x, z), or nil when nothing bounds it.
    static func front(at p: Vec2, _ s: Scene) -> BayOpening? {
        let tol = 1e-7
        // FMG3: on a canted face, parts at an angle to it reach across the opening by their extent; only the parts at
        // the face (within 1 1/2" of its front-most part over the point) bound it.
        var bounders = s.bounders
        if !s.frame.isSquare {
            let over = bounders.filter { !$0.isSeparator && $0.box.box.min.x <= p.x + tol && $0.box.box.max.x >= p.x - tol }
            if let face = over.map(\.box.box.min.y).min() { bounders = bounders.filter { $0.isSeparator || $0.box.box.min.y <= face + 1.5 * inch } }
        }
        guard let o = front(at: p, s, bounders) else { return nil }
        guard !s.frame.isIdentity else { return o }
        // FMG3: seen from another face, parts behind the bay's back (the far side's) don't bound it.
        let inFront = bounders.filter { $0.isSeparator || $0.box.box.min.y < o.y1 - 1e-6 }
        guard inFront.count < bounders.count else { return o }
        return front(at: p, s, inFront) ?? o
    }

    /// One pass of `front(at:)` over the given bounders.
    static func front(at p: Vec2, _ s: Scene, _ bounders: [Bounder]) -> BayOpening? {
        let px = p.x, pz = p.y
        var left: Bounder?, right: Bounder?, below: Bounder?, above: Bounder?
        let tol = 1e-7
        for c in bounders {
            let bx = c.box.box
            let sx = bx.max.x - bx.min.x, sz = bx.max.z - bx.min.z
            // Uprights (sides, dividers, legs, vertical separators) are thinner across x than they are tall.
            if sx < sz, bx.min.z <= pz + tol, bx.max.z >= pz - tol {
                if bx.max.x <= px + tol, left.map({ bx.max.x > $0.box.box.max.x }) ?? true { left = c }
                if bx.min.x >= px - tol, right.map({ bx.min.x < $0.box.box.min.x }) ?? true { right = c }
            }
            // Bottoms, shelves, tops, rails and horizontal separators are longer across x than they are tall.
            if sz < sx, bx.min.x <= px + tol, bx.max.x >= px - tol {
                if bx.max.z <= pz + tol, below.map({ bx.max.z > $0.box.box.max.z }) ?? true { below = c }
                if bx.min.z >= pz - tol, above.map({ bx.min.z < $0.box.box.min.z }) ?? true { above = c }
            }
        }
        guard left != nil || right != nil || below != nil || above != nil else { return nil }
        guard let lx = left?.box.x.1 ?? s.fallback("x0"), let rx = right?.box.x.0 ?? s.fallback("x1"),
              let bz = below?.box.z.1 ?? s.fallback("z0"), let tz = above?.box.z.0 ?? s.fallback("z1"),
              rx.value - lx.value > Tolerance.length, tz.value - bz.value > Tolerance.length else { return nil }
        // Depth: from the front edges of the parts round it to the back panel (or their back edges).
        let parts = [left, right, below, above].compactMap { $0 }.filter { !$0.isSeparator }
        let y0 = parts.map(\.box.y.0).min { $0.value < $1.value } ?? s.fallback("y0") ?? PartValue(-0.3)
        var y1 = parts.map(\.box.y.1).max { $0.value < $1.value } ?? s.fallback("y1") ?? PartValue(0.3)
        var backID: ElementID?
        let mid = Vec2((lx.value + rx.value) / 2, (bz.value + tz.value) / 2)
        // FMG3: seen from another face, a part across the opening at that face (a side panel seen from the side)
        // closes it: the region is behind the part, not a bay. A part across it further in is its back.
        if !s.frame.isIdentity {
            let round = Set([left, right, below, above].compactMap { $0?.id })
            for c in s.bounders where !c.isSeparator && !round.contains(c.id) {
                let bx = c.box.box
                // Only boards parallel to the face (thin seen from it): a board at an angle reaches across by its extent.
                guard bx.max.y - bx.min.y < 0.2 * min(bx.max.x - bx.min.x, bx.max.z - bx.min.z),
                      bx.min.x <= mid.x, bx.max.x >= mid.x, bx.min.z <= mid.y, bx.max.z >= mid.y else { continue }
                if bx.min.y <= y0.value + 1e-6 { return nil }
                if bx.min.y < y1.value { y1 = c.box.y.0; backID = c.id }
            }
        }
        for e in s.model.elements(.furniturePanels) where e.furniturePanel?.role == .back {
            guard let b = FurniturePartSolids.partBox(e, s.model).map(s.frame.localBox) else { continue } // FMG3
            let bx = b.box
            // FMG3: seen from another face, a back panel at that face closes the opening (the bay is behind it).
            if !s.frame.isIdentity, bx.min.x <= mid.x, bx.max.x >= mid.x, bx.min.z <= mid.y, bx.max.z >= mid.y, bx.min.y <= y0.value + 1e-6 { return nil }
            if bx.min.x <= mid.x, bx.max.x >= mid.x, bx.min.z <= mid.y, bx.max.z >= mid.y, bx.min.y < y1.value + 1e-6, bx.min.y > y0.value {
                y1 = b.y.0; backID = e.id
            }
        }
        var o = BayOpening(x0: lx.value, x1: rx.value, y0: y0.value, y1: y1.value, z0: bz.value, z1: tz.value)
        o.outer0 = left?.box.x.0.value ?? lx.value
        o.outer1 = right?.box.x.1.value ?? rx.value
        o.outerLow = below?.box.z.0.value ?? bz.value
        o.outerHigh = above?.box.z.1.value ?? tz.value
        var b: [String: FurnitureBound] = [:]
        func bind(_ k: String, _ v: PartValue?) { if let v, let n = v.plane { b[k] = .plane(n, offset: v.offset) } }
        bind("x0", lx); bind("x1", rx); bind("z0", bz); bind("z1", tz); bind("y0", y0); bind("y1", y1)
        bind("outer0", left?.box.x.0 ?? lx); bind("outer1", right?.box.x.1 ?? rx); bind("outerLow", below?.box.z.0 ?? bz); bind("outerHigh", above?.box.z.1 ?? tz)
        o.bounds = b
        o.left = left.flatMap { $0.isSeparator ? nil : $0.id }; o.right = right.flatMap { $0.isSeparator ? nil : $0.id }
        o.bottom = below.flatMap { $0.isSeparator ? nil : $0.id }; o.top = above.flatMap { $0.isSeparator ? nil : $0.id }; o.back = backID
        o.sharedLeft = left?.shared ?? false; o.sharedRight = right?.shared ?? false
        o.sharedLow = below?.shared ?? false; o.sharedHigh = above?.shared ?? false
        if !s.frame.isSquare { // FMG3: the canted face's front corners, each on the part beside it
            let v0 = left?.box.y.0 ?? y0, v1 = right?.box.y.0 ?? y0
            o.cant = [lx.value, v0.value, rx.value, v1.value]
            bind("cant.u0", lx); bind("cant.v0", v0); bind("cant.u1", rx); bind("cant.v1", v1)
            o.bounds = b
        }
        return o
    }

    /// The top-access opening round plan point `p`: between the uprights left and right and the panels in front and
    /// behind, up to their lowest top (the rim), above the highest board below it.
    static func top(at p: Vec2, _ s: Scene) -> BayOpening? {
        let px = p.x, py = p.y
        let tol = 1e-7
        var left: Bounder?, right: Bounder?, front: Bounder?, back: Bounder?
        for c in s.bounders {
            let bx = c.box.box
            let sx = bx.max.x - bx.min.x, sy = bx.max.y - bx.min.y, sz = bx.max.z - bx.min.z
            guard sz > min(sx, sy) || c.isSeparator else { continue }
            if sx < sy, bx.min.y <= py + tol, bx.max.y >= py - tol {
                if bx.max.x <= px + tol, left.map({ bx.max.x > $0.box.box.max.x }) ?? true { left = c }
                if bx.min.x >= px - tol, right.map({ bx.min.x < $0.box.box.min.x }) ?? true { right = c }
            }
            if sy < sx, bx.min.x <= px + tol, bx.max.x >= px - tol {
                if bx.max.y <= py + tol, front.map({ bx.max.y > $0.box.box.max.y }) ?? true { front = c }
                if bx.min.y >= py - tol, back.map({ bx.min.y < $0.box.box.min.y }) ?? true { back = c }
            }
        }
        guard let l = left, let r = right, let f = front, let bk = back else { return nil }
        let walls = [l, r, f, bk].filter { !$0.isSeparator }
        guard let rim = walls.map(\.box.z.1).min(by: { $0.value < $1.value }) else { return nil }
        // The floor: the highest board under the point below the rim.
        var floor: Bounder?
        for c in s.bounders where !c.isSeparator {
            let bx = c.box.box
            let sz = bx.max.z - bx.min.z
            guard sz < bx.max.x - bx.min.x, sz < bx.max.y - bx.min.y, bx.min.x <= px, bx.max.x >= px, bx.min.y <= py, bx.max.y >= py, bx.max.z < rim.value - Tolerance.length else { continue }
            if floor.map({ bx.max.z > $0.box.box.max.z }) ?? true { floor = c }
        }
        let z0 = floor?.box.z.1 ?? s.plane("Bottom") ?? PartValue(0)
        let x0 = l.box.x.1, x1 = r.box.x.0, y0 = f.box.y.1, y1 = bk.box.y.0
        guard x1.value - x0.value > Tolerance.length, y1.value - y0.value > Tolerance.length, rim.value - z0.value > Tolerance.length else { return nil }
        var o = BayOpening(x0: x0.value, x1: x1.value, y0: y0.value, y1: y1.value, z0: z0.value, z1: rim.value)
        o.outer0 = l.box.x.0.value; o.outer1 = r.box.x.1.value; o.outerLow = f.box.y.0.value; o.outerHigh = bk.box.y.1.value
        var b: [String: FurnitureBound] = [:]
        func bind(_ k: String, _ v: PartValue) { if let n = v.plane { b[k] = .plane(n, offset: v.offset) } }
        bind("x0", x0); bind("x1", x1); bind("y0", y0); bind("y1", y1); bind("z0", z0); bind("z1", rim)
        bind("outer0", l.box.x.0); bind("outer1", r.box.x.1); bind("outerLow", f.box.y.0); bind("outerHigh", bk.box.y.1)
        o.bounds = b
        o.left = l.isSeparator ? nil : l.id; o.right = r.isSeparator ? nil : r.id; o.bottom = f.isSeparator ? nil : f.id; o.top = bk.isSeparator ? nil : bk.id
        o.sharedLeft = l.shared; o.sharedRight = r.shared; o.sharedLow = f.shared; o.sharedHigh = bk.shared
        return o
    }

    /// The opening of a bay at its seed (FMG3: seen in `frame` for bays on a side).
    public static func opening(face: BayFace, at p: Vec2, frame: BayFrame = .front, _ m: BIMModel) -> BayOpening? {
        face == .front ? front(at: p, Scene(m, frame: frame)) : top(at: p, Scene(m))
    }

    /// The centre of an opening in its face's coordinates.
    public static func center(_ o: BayOpening, _ face: BayFace) -> Vec2 {
        face == .front ? Vec2((o.x0 + o.x1) / 2, (o.z0 + o.z1) / 2) : Vec2((o.x0 + o.x1) / 2, (o.y0 + o.y1) / 2)
    }

    /// The opening's outline in its face's coordinates (front: x, z; top: x, y).
    public static func outline(_ o: BayOpening, _ face: BayFace) -> Rect2 {
        face == .front ? Rect2(min: Vec2(o.x0, o.z0), max: Vec2(o.x1, o.z1)) : Rect2(min: Vec2(o.x0, o.y0), max: Vec2(o.x1, o.y1))
    }

    /// "14 1/2\" x 30\"": the clear opening, width by height (or width by depth seen from above).
    public static func sizeText(_ b: BayData) -> String {
        guard let o = b.opening else { return "Not Enclosed" }
        return "\(FurnitureSizeText.inches(o.width)) x \(FurnitureSizeText.inches(b.face == .front ? o.height : o.depth))"
    }

    // MARK: Cells (Bay Divide)

    /// The name of the plane at a Bay Divide line (sub-bay bounds, and the compiled family's EQ planes).
    public static func lineName(_ number: String, _ k: Int) -> String { "Bay \(number) Line \(k)" }

    /// The openings of a divided bay's cells, from the bottom (rows) or the left (columns).
    public static func cells(_ o: BayOpening, _ face: BayFace, _ d: BayDivision, number: String, frame: BayFrame = .front) -> [BayOpening] {
        let rows = d.direction == .rows
        // Seen from above, "rows" run front to back.
        let (lo, hi): (Double, Double) = rows ? (face == .front ? (o.z0, o.z1) : (o.y0, o.y1)) : (o.x0, o.x1)
        let spans = d.cells(lo, hi)
        let (kLo, kHi) = rows ? (face == .front ? ("z0", "z1") : ("y0", "y1")) : ("x0", "x1")
        let low = o.bounds[kLo]
        return spans.enumerated().map { k, span in
            var c = o
            if rows {
                if face == .front { c.z0 = span.0; c.z1 = span.1 } else { c.y0 = span.0; c.y1 = span.1 }
            } else { c.x0 = span.0; c.x1 = span.1 }
            // Inner lines: EQ lines follow a named plane the compile makes; lines by dimension keep their distance
            // from the low face's plane.
            func lineBound(_ index: Int, _ v: Double) -> FurnitureBound? {
                if d.layout == .equal {
                    // FMG3: on a turned face a column line is a plane of the model (followed negated when the face's u
                    // runs against its axis); on a canted face it is its share of the bay's two faces.
                    if !rows, !frame.isSquare {
                        let t = Double(index) / Double(spans.count)
                        let p = PartValue.sum(o.value(kLo).scaled(1 - t), o.value(kHi).scaled(t))
                        return p.plane.map { .plane($0, offset: p.offset) }
                    }
                    if !rows, (frame.uAxis?.sign ?? 1) < 0, let n = PlaneTerms.name([lineName(number, index): -1]) { return .plane(n, offset: 0) }
                    return .plane(lineName(number, index), offset: 0)
                }
                if case .plane(let n, let off)? = low { return .plane(n, offset: off + (v - lo)) }
                return nil
            }
            if k > 0 {
                c.bounds[kLo] = lineBound(k, span.0)
                if rows { c.sharedLow = true } else { c.sharedLeft = true }
                if rows, face == .front { c.outerLow = span.0; c.bounds["outerLow"] = c.bounds[kLo] }
                if !rows { c.outer0 = span.0; c.bounds["outer0"] = c.bounds[kLo] }
                if rows { c.bottom = nil } else { c.left = nil }
            }
            if k < spans.count - 1 {
                c.bounds[kHi] = lineBound(k + 1, span.1)
                if rows { c.sharedHigh = true } else { c.sharedRight = true }
                if rows, face == .front { c.outerHigh = span.1; c.bounds["outerHigh"] = c.bounds[kHi] }
                if !rows { c.outer1 = span.1; c.bounds["outer1"] = c.bounds[kHi] }
                if rows { c.top = nil } else { c.right = nil }
            }
            return c
        }
    }

    // MARK: Operations

    static func level(_ m: BIMModel) -> ElementID? { m.levels.first?.id }

    /// The next free bay number ("1", "2"…).
    static func nextNumber(_ m: BIMModel) -> String {
        let used = m.elements(.furnitureBays).compactMap { $0.furnitureBay.flatMap { $0.parentID == nil ? Int($0.number) : nil } }
        return String((used.max() ?? 0) + 1)
    }

    /// Places a bay round `point` (front: u, z in an elevation or section looking at the face, in its `frame`; top:
    /// x, y in plan), as Room places a room.
    @discardableResult
    public static func createBay(face: BayFace, at point: Vec2, frame: BayFrame = .front, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        guard tx.model.isFurniture else { throw TransactionError("Bays are placed in Furniture documents.") }
        let frame = face == .front ? frame : .front
        guard let o = opening(face: face, at: point, frame: frame, tx.model) else {
            throw TransactionError(face == .front ? "Click inside a region bounded by parts or bay separators." : "Click inside a box bounded by sides, a front and a back.",
                                   resolution: "Add panels or shelves round the opening, or draw Bay Separators.")
        }
        for b in tx.model.elements(.furnitureBays) {
            guard let d = b.furnitureBay, d.parentID == nil, d.face == face, BayFrame(d) == frame, let bo = d.opening else { continue } // FMG3: same face
            if outline(bo, face).contains(point) { throw TransactionError("\(b.name) is already in this region.", elements: [b.id]) }
        }
        let number = nextNumber(tx.model)
        var d = BayData(face: face, seed: center(o, face), elevation: face == .top ? o.z1 : nil, number: number)
        d.facing = frame.stored // FMG3
        d.opening = o
        return tx.create(.furnitureBays, name: "Bay \(number)", data: .furnitureBay(d), levelID: level(tx.model))
    }

    /// Draws a Bay Separator (front: x, z; top: x, y). Lines snap square to the piece.
    @discardableResult
    public static func createSeparator(face: BayFace, from a: Vec2, to b: Vec2, frame: BayFrame = .front, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        guard tx.model.isFurniture else { throw TransactionError("Bay separators are drawn in Furniture documents.") }
        guard a.distance(to: b) > Tolerance.shortCurve else { throw TransactionError("The separator is too short.") }
        var e = b
        if abs(b.x - a.x) >= abs(b.y - a.y) { e.y = a.y } else { e.x = a.x }
        var d = BaySeparatorData(face: face, start: a, end: e)
        if face == .front { d.facing = frame.stored } // FMG3
        return tx.create(.furnitureBaySeparators, data: .furnitureBaySeparator(d), levelID: level(tx.model))
    }

    /// Bay Divide: splits the bay into cells (sub-bays), or removes the division with nil. A front already in the bay
    /// moves to the first cell.
    public static func divide(_ bayID: ElementID, _ division: BayDivision?, in tx: TransactionContext) throws(TransactionError) {
        guard let bay = tx.model[bayID], var d = bay.furnitureBay else { throw TransactionError("Select a bay.") }
        if let division {
            guard (1...24).contains(division.count) else { throw TransactionError("Divide a bay into 1 to 24 cells.") }
            if division.layout == .fixed, let o = d.opening {
                let total = division.direction == .rows ? (d.face == .front ? o.height : o.depth) : o.width
                guard division.sizes.prefix(division.count - 1).reduce(0, +) < total - Tolerance.length else {
                    throw TransactionError("The cell sizes are larger than the bay.", resolution: "Make the sizes smaller, or divide into fewer cells.")
                }
            }
        }
        d.division = division
        tx.update(bayID) { $0.furnitureBay = d }
        syncCells(bayID, in: tx)
        if division != nil, let first = cellIDs(of: bayID, tx.model).first {
            for f in tx.model.hosted(by: bayID) where f.furnitureFront != nil { tx.update(f.id) { $0.hostID = first } }
        }
    }

    /// The sub-bays of a bay, by cell.
    public static func cellIDs(of bayID: ElementID, _ m: BIMModel) -> [ElementID] {
        m.hosted(by: bayID).filter { $0.furnitureBay?.parentID == bayID }.sorted { ($0.furnitureBay?.cell ?? 0) < ($1.furnitureBay?.cell ?? 0) }.map(\.id)
    }

    /// Creates, updates or removes a divided bay's sub-bays to match its cells.
    static func syncCells(_ bayID: ElementID, in tx: TransactionContext) {
        guard let bay = tx.model[bayID], let d = bay.furnitureBay else { return }
        let existing = tx.model.hosted(by: bayID).filter { $0.furnitureBay?.parentID == bayID }
        guard let division = d.division, let o = d.opening else {
            // An undivided bay (or one not enclosed) keeps no cells when undivided.
            if d.division == nil { for c in existing { tx.delete(c.id) } }
            else { for c in existing { tx.propagate(c.id) { $0.furnitureBay?.opening = nil } } }
            return
        }
        let cells = cells(o, d.face, division, number: d.number, frame: BayFrame(d)) // FMG3
        var byCell: [Int: Element] = [:]
        for c in existing {
            if let k = c.furnitureBay?.cell, k < cells.count, byCell[k] == nil { byCell[k] = c } else { tx.delete(c.id) }
        }
        for (k, co) in cells.enumerated() {
            let number = "\(d.number).\(k + 1)"
            if let c = byCell[k], var cd = c.furnitureBay {
                cd.opening = co; cd.seed = center(co, d.face); cd.number = number; cd.face = d.face; cd.facing = d.facing // FMG3
                let rename = c.name == "Bay \(c.furnitureBay?.number ?? "")"
                tx.propagate(c.id) { $0.furnitureBay = cd; if rename { $0.name = "Bay \(number)" } }
                syncCells(c.id, in: tx)
            } else {
                var cd = BayData(face: d.face, seed: center(co, d.face), elevation: d.elevation, number: number)
                cd.parentID = bayID; cd.cell = k; cd.opening = co; cd.facing = d.facing // FMG3
                tx.create(.furnitureBays, name: "Bay \(number)", data: .furnitureBay(cd), levelID: bay.levelID, hostID: bayID)
            }
        }
        // A front left in the divided bay moves into its first cell (Bay Divide set from Properties).
        if let first = cellIDs(of: bayID, tx.model).first {
            for f in tx.model.hosted(by: bayID) where f.furnitureFront != nil { tx.propagate(f.id) { $0.hostID = first } }
        }
    }

    // MARK: Regeneration

    /// Finds every bay's opening again (top-level bays from their seed, sub-bays from their bay's cells), as rooms
    /// update when walls move. Bays not enclosed any more keep their place with a warning.
    static func regenerate(_ tx: TransactionContext) {
        let tops = tx.model.elements(.furnitureBays).filter { $0.furnitureBay?.parentID == nil }
        guard !tops.isEmpty else { return }
        var scenes: [BayFrame: Scene] = [:] // FMG3: one per face
        func scene(_ f: BayFrame) -> Scene {
            if let s = scenes[f] { return s }
            let s = Scene(tx.model, frame: f)
            scenes[f] = s
            return s
        }
        for bay in tops.sorted(by: { $0.id < $1.id }) {
            guard var d = tx.model[bay.id]?.furnitureBay else { continue }
            let o = d.face == .front ? front(at: d.seed, scene(BayFrame(d))) : top(at: d.seed, scene(.front))
            d.opening = o
            if let o { d.seed = center(o, d.face); if d.face == .top { d.elevation = o.z1 } }
            else {
                tx.warn(ModelWarning(.warning, code: "bay.notEnclosed", "\(bay.name) is not in an enclosed region. Add parts or bay separators round it, or move it.", elements: [bay.id]))
            }
            if d != bay.furnitureBay { tx.propagate(bay.id) { $0.furnitureBay = d } }
            syncCells(bay.id, in: tx)
        }
        warnShared(tx) // FMG3: a bay moved into another's region
    }
}
