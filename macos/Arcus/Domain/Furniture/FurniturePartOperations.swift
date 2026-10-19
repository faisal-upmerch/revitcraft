import Foundation
import ArcusGeometry

// FM4: the model operations behind the part tools (and the library builder and tests): create panels, shelves, backs,
// dividers, legs, rails, slats, plinths, edge profiles and openings; attach and detach; edit a profile. Each runs in
// the caller's transaction; regeneration then binds the new part to the planes and part faces it lies on.

/// A part's run between two bounds along an axis (Base/Top Constraint): a plane and an offset, or a fixed value, and
/// for the top optionally an Unconnected Height instead.
public struct PartExtent: Hashable, Sendable {
    public var basePlane: String?
    public var baseOffset: Double
    /// nil = Unconnected (use `height`).
    public var topPlane: String?
    public var topOffset: Double
    public var height: Double
    public init(basePlane: String? = "Bottom", baseOffset: Double = 0, topPlane: String? = "Top", topOffset: Double = 0, height: Double = 30 * 0.0254) {
        self.basePlane = basePlane; self.baseOffset = baseOffset; self.topPlane = topPlane; self.topOffset = topOffset; self.height = height
    }

    /// Resolved base and top, with their bounds.
    public func resolve(_ m: BIMModel) -> (base: Double, top: Double, bounds: [String: FurnitureBound]) {
        let r = FurnitureBoundResolver(m)
        var b: [String: FurnitureBound] = [:]
        var base = baseOffset
        if let p = basePlane, let v = r.positions[p] { base = v + baseOffset; b["base"] = .plane(p, offset: baseOffset) }
        var top = base + height
        if let p = topPlane, let v = r.positions[p] { top = v + topOffset; b["top"] = .plane(p, offset: topOffset) }
        return (base, top, b)
    }
}

public enum FurniturePartOperations {
    static let inch = 0.0254

    /// A part type of `category` (the given one when it is one, else the first of `family`), creating the standard
    /// types when the document has none.
    static func type(_ id: ElementID?, _ category: Category, family: String? = nil, in tx: TransactionContext) -> ElementID? {
        if let id, tx.model[id]?.typeData?.instanceCategory == category { return id }
        if FurniturePartTypes.firstType(category, family: family, tx.model) == nil { FurniturePartTypes.ensureStandard(in: tx) }
        return FurniturePartTypes.firstType(category, family: family, tx.model) ?? FurniturePartTypes.firstType(category, tx.model)
    }

    static func level(_ m: BIMModel) -> ElementID? { m.levels.first?.id }

    static func requireFurniture(_ tx: TransactionContext) throws(TransactionError) {
        guard tx.model.isFurniture else { throw TransactionError("Parts are made in Furniture documents.") }
    }

    // MARK: Panels

    /// Creates a panel on `plane` from `start` to `end` (sketch coordinates), running across the plane over `extent`.
    @discardableResult
    public static func createPanel(start: Vec2, end: Vec2, plane: FamilySketchPlane = .xy, locationLine: PanelLocationLine = .faceOutside,
                                   flipped: Bool = false, extent: PartExtent, role: FurniturePartKind = .panel, typeID: ElementID? = nil,
                                   in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        guard start.distance(to: end) > Tolerance.shortCurve else { throw TransactionError("The panel is too short.") }
        let (base, top, bounds) = extent.resolve(tx.model)
        guard top - base > Tolerance.length else { throw TransactionError("The panel's top must be above its base.", resolution: "Change the Base or Top Constraint, or the offsets.") }
        let t = type(typeID, .furniturePanels, family: "Panel", in: tx)
        var p = PanelData(role: role, plane: plane, start: start, end: end, locationLine: locationLine, flipped: flipped, base: base, top: top, bounds: bounds)
        if role == .back { p.back = BackIntent(fit: .inside) }
        return tx.create(.furniturePanels, data: .furniturePanel(p), typeID: t, levelID: level(tx.model))
    }

    /// Rectangle: four panels round the rectangle, drawn clockwise so the outside faces face out (as walls).
    @discardableResult
    public static func createPanelRectangle(_ r: Rect2, plane: FamilySketchPlane = .xy, locationLine: PanelLocationLine = .faceOutside, flipped: Bool = false,
                                            extent: PartExtent, typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        var ids: [ElementID] = []
        for e in Polygon2.rectangle(r).clockwise.edges {
            ids.append(try createPanel(start: e.start, end: e.end, plane: plane, locationLine: locationLine, flipped: flipped, extent: extent, typeID: typeID, in: tx))
        }
        return ids
    }

    // MARK: Shelves

    /// Creates a shelf, top or bottom from a closed plan loop, its top face at `elevation` (a plane and offset).
    @discardableResult
    public static func createShelf(boundary: [Vec2], plane: String? = "Bottom", offset: Double, role: FurniturePartKind = .shelf, adjustable: Bool = false,
                                   frontSetback: Double = 0, typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        var loop = Polygon2(boundary).simplified().counterClockwise
        guard loop.count >= 3, !loop.isDegenerate else { throw TransactionError("Sketch a closed loop with an area.") }
        if frontSetback > Tolerance.length {
            // The front is the edge at the lowest y: it moves back.
            let minY = loop.points.map(\.y).min() ?? 0
            loop = Polygon2(loop.points.map { abs($0.y - minY) < 1e-7 ? Vec2($0.x, $0.y + frontSetback) : $0 })
        }
        let r = FurnitureBoundResolver(tx.model)
        var z = offset
        var bounds: [String: FurnitureBound] = [:]
        if let p = plane, let v = r.positions[p] { z = v + offset; bounds["z"] = .plane(p, offset: offset) }
        let family = role == .top ? "Top" : "Shelf"
        let t = type(typeID, .furnitureShelves, family: family, in: tx)
        var s = ShelfData(role: role, boundary: loop.points, elevation: z, adjustable: adjustable, frontSetback: frontSetback, bounds: bounds)
        if adjustable { s.pins = ShelfPins() }
        return tx.create(.furnitureShelves, data: .furnitureShelf(s), typeID: t, levelID: level(tx.model))
    }

    /// Pick Panels: the boundary line a panel gives a shelf, on its face toward `p` (the inside), or on its far face
    /// with Extend into Panel; shifted by `offset` away from the click.
    public static func pickPanelLine(_ e: Element, toward p: Vec2, offset: Double = 0, extendIntoPanel: Bool = false, _ m: BIMModel) -> Segment2? {
        guard let b = FurniturePartSolids.partBox(e, m)?.box else { return nil }
        let r = Rect2(min: b.min.xy, max: b.max.xy)
        guard r.width > Tolerance.length, r.height > Tolerance.length else { return nil }
        // The panel's long plan side is its face.
        if r.width < r.height {
            let toward = p.x > r.center.x
            let x = (toward != extendIntoPanel ? r.max.x : r.min.x) + (toward ? offset : -offset)
            return Segment2(Vec2(x, r.min.y), Vec2(x, r.max.y))
        }
        let toward = p.y > r.center.y
        let y = (toward != extendIntoPanel ? r.max.y : r.min.y) + (toward ? offset : -offset)
        return Segment2(Vec2(r.min.x, y), Vec2(r.max.x, y))
    }

    /// The loop of picked panel lines: each line trimmed or extended to its neighbours (lines sorted round their
    /// centre), as Pick Walls closes a floor boundary.
    public static func closeLoop(_ lines: [Segment2]) -> [Vec2]? {
        guard lines.count >= 3 else { return nil }
        let c = lines.reduce(Vec2.zero) { $0 + $1.midpoint } * (1 / Double(lines.count))
        let sorted = lines.sorted { ($0.midpoint - c).angle < ($1.midpoint - c).angle }
        var pts: [Vec2] = []
        for i in sorted.indices {
            let a = sorted[i], b = sorted[(i + 1) % sorted.count]
            guard let hit = a.lineIntersection(b), !a.isParallel(to: b) else { return nil }
            pts.append(hit.point)
        }
        let poly = Polygon2(pts)
        return poly.isDegenerate ? nil : poly.counterClockwise.points
    }

    // MARK: Backs

    /// The carcass round a point: the nearest part faces on each side (left/right along x, below/above along z, and the
    /// front and back of the carcass along y). `point` is (x, z) in a Front/Back elevation or (y, z) in a side one.
    public struct Bay: Sendable {
        public var x: (PartValue, PartValue)
        public var y: (PartValue, PartValue)
        public var z: (PartValue, PartValue)
        /// The parts that bound it: left, right, bottom, top (any may be missing).
        public var left: ElementID?, right: ElementID?, bottom: ElementID?, top: ElementID?
        /// The same bounds on the outside of the bounding parts (full overlay).
        public var outer: (x: (PartValue, PartValue), z: (PartValue, PartValue))
    }

    /// The bay at `point` of a front view (x, z): bounded by the nearest parts left and right, below and above (or, with
    /// `carcass`, the lowest and highest: the whole carcass a back covers); its depth spans the sides.
    public static func bay(atFront point: Vec2, carcass: Bool = false, _ m: BIMModel) -> Bay? {
        let boxes = FurniturePartBinder.boxes(m).filter { m[$0.key]?.furniturePanel?.role != .back }
        let px = point.x, pz = point.y
        var left: (ElementID, FurniturePartSolids.PartBox)?, right: (ElementID, FurniturePartSolids.PartBox)?
        var below: (ElementID, FurniturePartSolids.PartBox)?, above: (ElementID, FurniturePartSolids.PartBox)?
        for (id, b) in boxes {
            let bx = b.box
            // Sides are thin across x; bottoms, shelves and tops are thin in z.
            let sx = bx.max.x - bx.min.x, sy = bx.max.y - bx.min.y, sz = bx.max.z - bx.min.z
            let side = sx <= sy && sx <= sz, flat = sz <= sx && sz <= sy
            if side, bx.min.z <= pz, bx.max.z >= pz {
                if bx.max.x <= px + 1e-9, left.map({ bx.max.x > $0.1.box.max.x }) ?? true { left = (id, b) }
                if bx.min.x >= px - 1e-9, right.map({ bx.min.x < $0.1.box.min.x }) ?? true { right = (id, b) }
            }
            if flat, bx.min.x <= px, bx.max.x >= px {
                if bx.max.z <= pz + 1e-9, below.map({ carcass ? bx.max.z < $0.1.box.max.z : bx.max.z > $0.1.box.max.z }) ?? true { below = (id, b) }
                if bx.min.z >= pz - 1e-9, above.map({ carcass ? bx.min.z > $0.1.box.min.z : bx.min.z < $0.1.box.min.z }) ?? true { above = (id, b) }
            }
        }
        let planes = FurniturePlanes.positionsByName(m)
        func plane(_ n: String) -> PartValue? { planes[n].map { PartValue($0, plane: n, offset: 0) } }
        guard let lx = left?.1.x.1 ?? plane("Left"), let rx = right?.1.x.0 ?? plane("Right"),
              let bz = below?.1.z.1 ?? plane("Bottom"), let tz = above?.1.z.0 ?? plane("Top"), rx.value - lx.value > Tolerance.length, tz.value - bz.value > Tolerance.length else { return nil }
        let sides = [left?.1, right?.1].compactMap { $0 }
        let y0 = sides.map(\.y.0).min { $0.value < $1.value } ?? plane("Front") ?? PartValue(-0.2)
        let y1 = sides.map(\.y.1).max { $0.value < $1.value } ?? plane("Back") ?? PartValue(0.2)
        let outer = (x: (left?.1.x.0 ?? lx, right?.1.x.1 ?? rx), z: (below?.1.z.0 ?? bz, above?.1.z.1 ?? tz))
        return Bay(x: (lx, rx), y: (y0, y1), z: (bz, tz), left: left?.0, right: right?.0, bottom: below?.0, top: above?.0, outer: outer)
    }

    static func bound(_ v: PartValue) -> FurnitureBound? { v.plane.map { .plane($0, offset: v.offset) } }

    /// Back: a panel across the back of the carcass round `point` (front view x, z), inside it or overlaying it.
    @discardableResult
    public static func createBack(atFront point: Vec2, fit: BackIntent.Fit, typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        guard let bay = bay(atFront: point, carcass: true, tx.model) else { throw TransactionError("Click inside a carcass: the back fits between its sides, bottom and top.") }
        let any = type(typeID, .furniturePanels, family: "Panel", in: tx)
        let t = typeID == nil ? (tx.model.types(for: .furniturePanels).first { $0.name.contains("Back Panel") }?.id ?? any) : any
        let (xs, zs) = fit == .inside ? (bay.x, bay.z) : (bay.outer.x, bay.outer.z)
        // The back face of the carcass: its outside face flush (inside) or its inside face against it (overlay).
        let y = bay.y.1
        var p = PanelData(role: .back, plane: .xy, start: Vec2(xs.0.value, y.value), end: Vec2(xs.1.value, y.value),
                          locationLine: fit == .inside ? .faceOutside : .faceInside, base: zs.0.value, top: zs.1.value)
        var b: [String: FurnitureBound] = [:]
        b["start.u"] = bound(xs.0); b["end.u"] = bound(xs.1); b["start.v"] = bound(y); b["end.v"] = bound(y)
        b["base"] = bound(zs.0); b["top"] = bound(zs.1)
        p.bounds = b.compactMapValues { $0 }
        p.back = BackIntent(fit: fit, carcass: [bay.left, bay.right, bay.bottom, bay.top].compactMap { $0 })
        return tx.create(.furniturePanels, data: .furniturePanel(p), typeID: t, levelID: level(tx.model))
    }

    // MARK: Dividers

    /// Dividers: `count` panels splitting the bay round `point` (front view x, z) into equal spaces (EQ), vertical (between
    /// the bottom and top) or horizontal (between the sides).
    @discardableResult
    public static func createDividers(atFront point: Vec2, vertical: Bool, count: Int = 1, setback: Double = 0, typeID: ElementID? = nil,
                                      in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        try requireFurniture(tx)
        guard count >= 1 else { throw TransactionError("Make at least one divider.") }
        guard let bay = bay(atFront: point, tx.model) else { throw TransactionError("Click inside a bay: dividers fit between the parts round it.") }
        let t = type(typeID, .furniturePanels, family: "Panel", in: tx)
        // The back of the bay stops at a back panel if one is there.
        let y0 = bay.y.0.shifted(setback), y1 = backFace(bay, tx.model) ?? bay.y.1
        var ids: [ElementID] = []
        for i in 1...count {
            var p: PanelData
            if vertical {
                let lo = bay.x.0.value, hi = bay.x.1.value, c = lo + (hi - lo) * Double(i) / Double(count + 1)
                p = PanelData(role: .divider, plane: .xy, start: Vec2(c, y0.value), end: Vec2(c, y1.value), locationLine: .centerline, base: bay.z.0.value, top: bay.z.1.value)
                p.bounds = ["start.v": bound(y0), "end.v": bound(y1), "base": bound(bay.z.0), "top": bound(bay.z.1)].compactMapValues { $0 }
                if let l = bound(bay.x.0), let h = bound(bay.x.1) { p.eq = EqualSpacing(low: l, high: h, index: i, count: count + 1) }
            } else {
                let lo = bay.z.0.value, hi = bay.z.1.value, c = lo + (hi - lo) * Double(i) / Double(count + 1)
                p = PanelData(role: .divider, plane: .xz, start: Vec2(bay.x.0.value, c), end: Vec2(bay.x.1.value, c), locationLine: .centerline, base: y0.value, top: y1.value)
                p.bounds = ["start.u": bound(bay.x.0), "end.u": bound(bay.x.1), "base": bound(y0), "top": bound(y1)].compactMapValues { $0 }
                if let l = bound(bay.z.0), let h = bound(bay.z.1) { p.eq = EqualSpacing(low: l, high: h, index: i, count: count + 1) }
            }
            ids.append(tx.create(.furniturePanels, data: .furniturePanel(p), typeID: t, levelID: level(tx.model)))
        }
        return ids
    }

    /// The front face of a back panel inside the bay, when there is one.
    static func backFace(_ bay: Bay, _ m: BIMModel) -> PartValue? {
        let mid = Vec2((bay.x.0.value + bay.x.1.value) / 2, (bay.z.0.value + bay.z.1.value) / 2)
        let backs = m.elements(.furniturePanels).filter { $0.furniturePanel?.role == .back }.compactMap { e -> FurniturePartSolids.PartBox? in
            guard let b = FurniturePartSolids.partBox(e, m) else { return nil }
            let bx = b.box
            return bx.min.x <= mid.x && bx.max.x >= mid.x && bx.min.z <= mid.y && bx.max.z >= mid.y ? b : nil
        }
        return backs.map(\.y.0).min { $0.value < $1.value }
    }

    // MARK: Legs

    /// A leg at a plan point from the base to the top of `extent`.
    @discardableResult
    public static func createLeg(at p: Vec2, extent: PartExtent, rotation: Double = 0, typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        let (base, top, bounds) = extent.resolve(tx.model)
        guard top - base > Tolerance.length else { throw TransactionError("The leg's top must be above its base.") }
        let t = type(typeID, .furnitureLegs, in: tx)
        return tx.create(.furnitureLegs, data: .furnitureLeg(LegData(location: p, base: base, top: top, rotation: rotation, bounds: bounds)), typeID: t, levelID: level(tx.model))
    }

    /// At Corners: a leg in each corner of a top or shelf, `inset` in from its edges, running from the base plane up to
    /// the top's underside (attached, so it follows the top).
    @discardableResult
    public static func legsAtCorners(of topID: ElementID, inset: Double, basePlane: String? = "Bottom", baseOffset: Double = 0, typeID: ElementID? = nil,
                                     in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        try requireFurniture(tx)
        guard let top = tx.model[topID], top.furnitureShelf != nil, let box = FurniturePartSolids.partBox(top, tx.model) else {
            throw TransactionError("Pick a rectangular top or shelf.")
        }
        let t = type(typeID, .furnitureLegs, in: tx)
        let tv = FurniturePartTypes.Values(tx.model[t]?.typeData)
        let hx = tv.width / 2 + inset, hy = tv.depth / 2 + inset
        let r = FurnitureBoundResolver(tx.model)
        var base = baseOffset
        var baseBound: FurnitureBound?
        if let p = basePlane, let v = r.positions[p] { base = v + baseOffset; baseBound = .plane(p, offset: baseOffset) }
        let under = box.z.0.value
        guard under - base > Tolerance.length else { throw TransactionError("The top is below the legs' base.") }
        var ids: [ElementID] = []
        for (xv, sx) in [(box.x.0, 1.0), (box.x.1, -1.0)] {
            for (yv, sy) in [(box.y.0, 1.0), (box.y.1, -1.0)] {
                let x = xv.shifted(sx * hx), y = yv.shifted(sy * hy)
                var l = LegData(location: Vec2(x.value, y.value), base: base, top: under)
                l.attachedTopID = topID
                l.bounds = ["x": bound(x), "y": bound(y), "base": baseBound].compactMapValues { $0 }
                ids.append(tx.create(.furnitureLegs, data: .furnitureLeg(l), typeID: t, levelID: level(tx.model)))
            }
        }
        return ids
    }

    // MARK: Rails and slats

    @discardableResult
    public static func createRail(start: Vec2, end: Vec2, plane: FamilySketchPlane = .xy, w: Double, wPlane: String? = nil,
                                  justification: RailJustification = .top, typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        guard start.distance(to: end) > Tolerance.shortCurve else { throw TransactionError("The rail is too short.") }
        let t = type(typeID, .furnitureRails, in: tx)
        var r = RailData(plane: plane, start: start, end: end, w: w, justification: justification)
        if let p = wPlane, let v = FurnitureBoundResolver(tx.model).positions[p] { r.w = v + w; r.bounds["w"] = .plane(p, offset: w) }
        return tx.create(.furnitureRails, data: .furnitureRail(r), typeID: t, levelID: level(tx.model))
    }

    /// Slats: rails filling a plan rectangle at a spacing (or a number of them), running along `alongX` or across it, as
    /// a beam system fills its boundary. The slats' tops are at `z`.
    @discardableResult
    public static func createSlats(in rect: Rect2, alongX: Bool, rule: SlatLayout.Rule, spacing: Double, number: Int, z: Double, zPlane: String? = nil,
                                   typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        guard rect.width > Tolerance.shortCurve, rect.height > Tolerance.shortCurve else { throw TransactionError("Pick a region with an area.") }
        let t = type(typeID ?? tx.model.types(for: .furnitureRails).first { $0.name.contains("Slat") }?.id, .furnitureRails, in: tx)
        let w = FurniturePartTypes.Values(tx.model[t]?.typeData).width
        // The first slat runs along one edge (inset by half a slat); the rest are laid out across the region.
        let start: Vec2, end: Vec2, extent: Double
        if alongX {
            start = Vec2(rect.min.x, rect.min.y + w / 2); end = Vec2(rect.max.x, rect.min.y + w / 2); extent = rect.height - w
        } else {
            // Running along y from max to min keeps the slats to the left (+x) of the line.
            start = Vec2(rect.min.x + w / 2, rect.max.y); end = Vec2(rect.min.x + w / 2, rect.min.y); extent = rect.width - w
        }
        guard extent >= 0 else { throw TransactionError("The region is narrower than one slat.") }
        var r = RailData(plane: .xy, start: start, end: end, w: z, justification: .top)
        if let p = zPlane, let v = FurnitureBoundResolver(tx.model).positions[p] { r.w = v + z; r.bounds["w"] = .plane(p, offset: z) }
        r.slats = SlatLayout(rule: rule, spacing: spacing, number: number, extent: extent)
        return tx.create(.furnitureRails, data: .furnitureRail(r), typeID: t, levelID: level(tx.model))
    }

    // MARK: Plinth

    /// Plinth / Kick: a panel along the front of a bottom (shelf or horizontal panel), set back from its front edge, from
    /// the base plane up to the bottom's underside (or `height` when given).
    @discardableResult
    public static func createPlinth(under bottomID: ElementID, setback: Double = 3 * 0.0254, height: Double? = nil, basePlane: String? = "Bottom",
                                    typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        guard let bottom = tx.model[bottomID], let box = FurniturePartSolids.partBox(bottom, tx.model) else { throw TransactionError("Pick a bottom shelf or panel.") }
        let t = type(typeID, .furniturePanels, family: "Panel", in: tx)
        let r = FurnitureBoundResolver(tx.model)
        let base = basePlane.flatMap { r.positions[$0] } ?? 0
        let under = box.z.0
        let topV = height.map { base + $0 } ?? under.value
        guard topV - base > Tolerance.length else { throw TransactionError("The bottom is on the base: there's no room for a plinth.", resolution: "Raise the bottom, or give the plinth a height.") }
        let y = box.y.0.shifted(setback)
        // Drawn right to left so its outside face faces the front.
        var p = PanelData(role: .plinth, plane: .xy, start: Vec2(box.x.1.value, y.value), end: Vec2(box.x.0.value, y.value), locationLine: .faceOutside, base: base, top: topV)
        p.bounds = ["start.u": bound(box.x.1), "end.u": bound(box.x.0), "start.v": bound(y), "end.v": bound(y),
                    "base": basePlane.map { .plane($0, offset: 0) }, "top": height == nil ? bound(under) : nil].compactMapValues { $0 }
        return tx.create(.furniturePanels, data: .furniturePanel(p), typeID: t, levelID: level(tx.model))
    }

    // MARK: Edge profiles

    /// An edge profile or groove along an edge of a box-shaped part.
    @discardableResult
    public static func createEdgeProfile(on hostID: ElementID, edge: PartEdge, groove: Bool = false, offset: Double = 0, typeID: ElementID? = nil,
                                         in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        guard let host = tx.model[hostID], FurniturePartSolids.partBox(host, tx.model) != nil else { throw TransactionError("Pick an edge of a panel, shelf, rail or square leg.") }
        let t = type(typeID, .furnitureEdgeProfiles, family: groove ? FurniturePartTypes.grooveFamily : "Edge Profile", in: tx)
        let isGroove = tx.model[t]?.typeData?.familyName == FurniturePartTypes.grooveFamily
        let d = EdgeProfileData(edge: edge, offset: offset, isGroove: isGroove)
        return tx.create(.furnitureEdgeProfiles, data: .furnitureEdgeProfile(d), typeID: t, levelID: level(tx.model), hostID: hostID)
    }

    /// The box edge of a part nearest a pick in a view, and the side the pick is on (the edge seen nearest the viewer).
    /// `toView` projects a world point to view coordinates and its depth.
    public static func nearestEdge(of e: Element, _ m: BIMModel, pick: Vec2, tolerance: Double, toView: (Vec3) -> (Vec2, Double)) -> PartEdge? {
        guard let b = FurniturePartSolids.partBox(e, m)?.box else { return nil }
        var best: (PartEdge, Double, Double)?
        for axis in FamilyAxis.allCases {
            for f in [false, true] {
                for s in [false, true] {
                    let edge = PartEdge(axis: axis, firstAtMax: f, secondAtMax: s)
                    let (p0, p1) = segment(b, edge)
                    let (a, da) = toView(p0), (c, dc) = toView(p1)
                    let seg = Segment2(a, c)
                    let dist = seg.isDegenerate ? a.distance(to: pick) : seg.distance(to: pick)
                    guard dist <= tolerance else { continue }
                    let depth = (da + dc) / 2
                    if best.map({ dist < $0.1 - 1e-9 || (abs(dist - $0.1) <= 1e-9 && depth < $0.2) }) ?? true { best = (edge, dist, depth) }
                }
            }
        }
        return best?.0
    }

    /// An edge of a box as a world segment.
    public static func segment(_ b: Box3, _ edge: PartEdge) -> (Vec3, Vec3) {
        func v(_ a: FamilyAxis, _ atMax: Bool) -> Double {
            switch a { case .x: atMax ? b.max.x : b.min.x; case .y: atMax ? b.max.y : b.min.y; case .z: atMax ? b.max.z : b.min.z }
        }
        let (a1, a2) = edge.across
        var p0: [FamilyAxis: Double] = [a1: v(a1, edge.firstAtMax), a2: v(a2, edge.secondAtMax)], p1 = p0
        p0[edge.axis] = v(edge.axis, false); p1[edge.axis] = v(edge.axis, true)
        return (Vec3(p0[.x] ?? 0, p0[.y] ?? 0, p0[.z] ?? 0), Vec3(p1[.x] ?? 0, p1[.y] ?? 0, p1[.z] ?? 0))
    }

    // MARK: Panel edits

    /// Opening: a rectangular cut-out between two face points (s along the line, t up from the base).
    public static func addOpening(_ panelID: ElementID, _ o: PanelOpening, in tx: TransactionContext) throws(TransactionError) {
        guard var p = tx.model[panelID]?.furniturePanel else { throw TransactionError("Select a panel.") }
        guard o.s1 - o.s0 > Tolerance.length, o.t1 - o.t0 > Tolerance.length else { throw TransactionError("The opening has no size.") }
        guard o.s0 >= -1e-9, o.s1 <= p.length + 1e-9, o.t0 >= -1e-9, o.t1 <= p.height + 1e-9 else { throw TransactionError("The opening must lie inside the panel.") }
        guard FurniturePartSolids.linearFrame(p.plane, p.start, p.end) != nil else { throw TransactionError("Openings are cut in panels drawn square to the piece.") }
        p.openings = (p.openings ?? []) + [o]
        tx.update(panelID) { $0.furniturePanel = p }
    }

    /// Edit Profile: replaces the panel's outline (face coordinates); nil resets it to the rectangle.
    public static func setProfile(_ panelID: ElementID, _ outline: [Vec2]?, in tx: TransactionContext) throws(TransactionError) {
        guard var p = tx.model[panelID]?.furniturePanel else { throw TransactionError("Select a panel.") }
        if let outline {
            let poly = Polygon2(outline)
            guard poly.count >= 3, !poly.isDegenerate, poly.isSimple else { throw TransactionError("The profile must be one closed loop that doesn't cross itself.") }
            guard FurniturePartSolids.linearFrame(p.plane, p.start, p.end) != nil else { throw TransactionError("Edit Profile works on panels drawn square to the piece.") }
            p.profile = poly.counterClockwise.points
        } else {
            p.profile = nil
        }
        tx.update(panelID) { $0.furniturePanel = p }
    }

    /// Attach Top/Base: the panels (drawn in plan) and legs run to the shelf or top: their tops to its underside when
    /// it's above them, their bases to its top face when it's below.
    public static func attach(_ ids: [ElementID], to shelfID: ElementID, in tx: TransactionContext) throws(TransactionError) {
        guard let s = tx.model[shelfID]?.furnitureShelf else { throw TransactionError("Pick a shelf, top or bottom to attach to.") }
        var attached = 0
        for id in ids {
            guard let e = tx.model[id] else { continue }
            if var p = e.furniturePanel, p.plane == .xy {
                if s.elevation > (p.base + p.top) / 2 { p.attachedTopID = shelfID } else { p.attachedBaseID = shelfID }
                tx.update(id) { $0.furniturePanel = p }
                attached += 1
            } else if var l = e.furnitureLeg {
                l.attachedTopID = shelfID
                tx.update(id) { $0.furnitureLeg = l }
                attached += 1
            }
        }
        if attached == 0 { throw TransactionError("Select panels drawn in plan, or legs, to attach.") }
    }

    /// Detach Top/Base: the panels keep where they are, bound to planes again.
    public static func detach(_ ids: [ElementID], in tx: TransactionContext) {
        for id in ids {
            tx.update(id) { e in
                if var p = e.furniturePanel { p.attachedTopID = nil; p.attachedBaseID = nil; e.furniturePanel = p }
                if var l = e.furnitureLeg { l.attachedTopID = nil; e.furnitureLeg = l }
            }
        }
    }

    // MARK: Forms

    @discardableResult
    public static func createForm(_ f: FurnitureFormData, in tx: TransactionContext) throws(TransactionError) -> ElementID {
        try requireFurniture(tx)
        var f = f
        if f.materialID == nil, !f.isVoid {
            let name = f.kind == .cushion ? "Fabric" : "Solid Oak"
            f.materialID = tx.model.elements(.materials).first { $0.name == name }?.id
        }
        return tx.create(.furnitureForms, data: .furnitureForm(f), levelID: level(tx.model))
    }
}
