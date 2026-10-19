import Foundation
import ArcusGeometry

// FM5: doors, drawers and flaps, hosted in bays as doors and windows are hosted in walls. A front's leaves come from its
// bay's opening and its type: full overlay covers the carcass's outside edges (less the edge reveal) and half of every
// shared divider or shelf (less half the reveal), half overlay covers half of every part, inset sits inside the opening
// with the reveal all round. Pairs split the width with a reveal between the leaves. The hinge side flips like a door's
// hand. Each front owns its hardware: hinges by height (2 up to 40", 3 up to 60", 4 up to 80", then 5), a slide pair per
// drawer (the longest standard length that fits the depth), a handle per leaf and stays for flaps, kept in step with
// the front at every regeneration as component instances hosted by it.

/// The edge a leaf hinges on.
public enum HingeEdge: String, Sendable, Hashable { case left, right, top, bottom, back }

/// One leaf of a front, in model coordinates. Seen from the front, `u` runs along X and `v` along Z, and `w` (the
/// thickness) along Y, front face first. Seen from above (a lid), `v` runs along Y and `w` along Z, underside first.
public struct FrontLeaf: Sendable {
    public var u: (PartValue, PartValue)
    public var v: (PartValue, PartValue)
    public var w: (PartValue, PartValue)
    public var hinge: HingeEdge?
    public var width: Double { u.1.value - u.0.value }
    public var height: Double { v.1.value - v.0.value }
    public var rect: Rect2 { Rect2(min: Vec2(u.0.value, v.0.value), max: Vec2(u.1.value, v.1.value)) }
}

/// A front's resolved geometry.
public struct FrontGeometry: Sendable {
    public var kind: FrontKind
    public var face: BayFace
    public var opening: BayOpening
    public var leaves: [FrontLeaf]
    public var thickness: Double
    /// FMG3: the frame of the bay's face; leaves (and the opening) are in it (the identity for the front and lids).
    public var frame: BayFrame = .front
    /// The face the front is seen on: front face y (seen from the front) or top face z (lid).
    public var outerFace: Double { face == .front ? (leaves.first?.w.0.value ?? 0) : (leaves.first?.w.1.value ?? 0) }
    /// The back face (front) or underside (lid), where hinge cups are bored.
    public var innerFace: Double { face == .front ? (leaves.first?.w.1.value ?? 0) : (leaves.first?.w.0.value ?? 0) }
}

/// The drawer box of a drawer front, from its bay and slides.
public struct DrawerBox: Sendable {
    public var x0: Double, y0: Double, z0: Double
    public var width: Double, depth: Double, height: Double
    public var side: Double, back: Double, bottom: Double
    public var slideTypeID: ElementID?
    public var slideLength: Double
}

/// A hardware instance a front wants: its slot, type, insertion point and instance values.
public struct HardwarePlacement: Sendable {
    public var slot: String
    public var typeID: ElementID
    /// The insertion point, with the planes it follows (so a compiled piece's hardware moves when it flexes).
    public var at: (x: PartValue, y: PartValue, z: PartValue)
    public var mirrored: Bool
    public var values: [String: ParamValue]
    /// The part it's screwed to besides the front (side panel, top), for machining.
    public var carcassPartID: ElementID?
    /// FMG3: the instance's rotation (radians): its bay's face frame.
    public var rotation: Double = 0
    public var origin: Vec3 { Vec3(at.x.value, at.y.value, at.z.value) }
}

public enum FurnitureFronts {
    static let inch = 0.0254

    // MARK: Rules

    /// Hinges per edge length: 2 up to 40", 3 up to 60", 4 up to 80", then 5 (as hinge makers recommend).
    public static func hingeCount(edgeLength l: Double) -> Int {
        let i = l / inch
        if i <= 40 + 1e-6 { return 2 }
        if i <= 60 + 1e-6 { return 3 }
        if i <= 80 + 1e-6 { return 4 }
        return 5
    }

    /// Hinge centres along an edge from `lo` to `hi`: the first and last `inset` from the ends, the rest equally spaced.
    public static func hingePositions(_ lo: Double, _ hi: Double, count: Int, inset: Double) -> [Double] {
        let a = lo + min(inset, (hi - lo) / 4), b = hi - min(inset, (hi - lo) / 4)
        guard count > 1 else { return [(lo + hi) / 2] }
        return (0..<count).map { a + (b - a) * Double($0) / Double(count - 1) }
    }

    // MARK: Geometry

    static func mid(_ a: PartValue, _ b: PartValue) -> PartValue {
        let v = (a.value + b.value) / 2
        if let p = a.plane, p == b.plane { return PartValue(v, plane: p, offset: (a.offset + b.offset) / 2) }
        return PartValue(v)
    }

    /// One edge of a front across `o`: the face (`inner`) and the bounding part's outside face (`outer`), on the low
    /// (`sign` = -1) or high side.
    static func edge(inner: PartValue, outer: PartValue, shared: Bool, sign: Double, overlay: FrontOverlay, reveal r: Double, edgeReveal er: Double) -> PartValue {
        switch overlay {
        case .inset: return inner.shifted(-sign * r)
        case .half: return mid(inner, outer).shifted(-sign * r / 2)
        case .full:
            if shared { return mid(inner, outer).shifted(-sign * r / 2) }
            // An exposed edge: the outside face less the edge reveal (the opening itself when nothing bounds it).
            return abs(outer.value - inner.value) < 1e-9 ? inner.shifted(-sign * er) : outer.shifted(-sign * er)
        }
    }

    /// The front's leaves in its bay (nil when the bay isn't enclosed).
    public static func geometry(_ e: Element, _ m: BIMModel) -> FrontGeometry? {
        guard let f = e.furnitureFront, let bay = m[e.hostID]?.furnitureBay, let o = bay.opening else { return nil }
        let pair: Bool? = f.leafCount != nil || f.leafCountParameter != nil ? leafCount(e, m) >= 2 : nil // FMG3
        return geometry(f, type: FurnitureFrontTypes.values(of: e, m), bay: bay, opening: o, pair: pair)
    }

    /// `pair` overrides the type's Leaf Count (FMG3: an instance's, or its family parameter's).
    public static func geometry(_ f: FrontData, type tv: FurnitureFrontTypes.Values, bay: BayData, opening o: BayOpening, pair: Bool? = nil) -> FrontGeometry? {
        let t = tv.thickness, r = tv.reveal, er = tv.edgeReveal, ov = tv.overlay
        let front = bay.face == .front
        let u0 = edge(inner: o.value("x0"), outer: o.value("outer0"), shared: o.sharedLeft, sign: -1, overlay: ov, reveal: r, edgeReveal: er)
        let u1 = edge(inner: o.value("x1"), outer: o.value("outer1"), shared: o.sharedRight, sign: 1, overlay: ov, reveal: r, edgeReveal: er)
        let (vk0, vk1) = front ? ("z0", "z1") : ("y0", "y1")
        let v0 = edge(inner: o.value(vk0), outer: o.value("outerLow"), shared: o.sharedLow, sign: -1, overlay: ov, reveal: r, edgeReveal: er)
        let v1 = edge(inner: o.value(vk1), outer: o.value("outerHigh"), shared: o.sharedHigh, sign: 1, overlay: ov, reveal: r, edgeReveal: er)
        guard u1.value - u0.value > Tolerance.length * 10, v1.value - v0.value > Tolerance.length * 10 else { return nil }
        // Thickness: overlay fronts sit in front of (or on) the carcass; inset fronts are flush with it.
        let w: (PartValue, PartValue)
        if front {
            let y0 = o.value("y0")
            w = ov == .inset ? (y0, y0.shifted(t)) : (y0.shifted(-t), y0)
        } else {
            let z1 = o.value("z1")
            w = ov == .inset ? (z1.shifted(-t), z1) : (z1, z1.shifted(t))
        }
        var leaves: [FrontLeaf] = []
        switch f.kind {
        case .drawer:
            leaves = [FrontLeaf(u: (u0, u1), v: (v0, v1), w: w, hinge: nil)]
        case .flap:
            let h: HingeEdge = front ? (tv.flapAction == .liftUp ? .top : .bottom) : .back
            leaves = [FrontLeaf(u: (u0, u1), v: (v0, v1), w: w, hinge: h)]
        case .door:
            if !front {
                leaves = [FrontLeaf(u: (u0, u1), v: (v0, v1), w: w, hinge: .back)]
            } else if pair ?? tv.isPair {
                let c = mid(u0, u1)
                leaves = [FrontLeaf(u: (u0, c.shifted(-r / 2)), v: (v0, v1), w: w, hinge: .left),
                          FrontLeaf(u: (c.shifted(r / 2), u1), v: (v0, v1), w: w, hinge: .right)]
            } else {
                leaves = [FrontLeaf(u: (u0, u1), v: (v0, v1), w: w, hinge: f.hingeFlipped ? .right : .left)]
            }
        }
        return FrontGeometry(kind: f.kind, face: bay.face, opening: o, leaves: leaves, thickness: t, frame: BayFrame(bay)) // FMG3
    }

    /// The slide type a drawer uses: the type's slide family at the longest length that fits the bay's depth.
    public static func slideType(_ e: Element, _ m: BIMModel, geometry g: FrontGeometry) -> ElementID? {
        let tv = FurnitureFrontTypes.values(of: e, m)
        guard let chosen = tv.slideType, let fam = m[chosen]?.typeData?.familyName else { return nil }
        let start = tv.overlay == .inset ? g.opening.y0 + tv.thickness : g.opening.y0
        return FurnitureHardware.slide(family: fam, fitting: g.opening.y1 - start, m)
    }

    /// The drawer box of a drawer (nil for doors and flaps, or when no slide fits).
    public static func drawerBox(_ e: Element, _ m: BIMModel) -> DrawerBox? {
        guard e.furnitureFront?.kind == .drawer, let g = geometry(e, m), g.face == .front else { return nil }
        let tv = FurnitureFrontTypes.values(of: e, m)
        let slide = slideType(e, m, geometry: g)
        let sv = FurnitureHardware.Values(m[slide]?.typeData)
        let o = g.opening
        let y0 = tv.overlay == .inset ? o.y0 + tv.thickness : o.y0
        let length = slide == nil ? max(0, o.y1 - y0 - 0.5 * inch) : sv.slideLength
        let width = o.width - 2 * sv.sideClearance
        let height = o.height - sv.bottomClearance - sv.topClearance
        guard width > 2 * tv.boxSide + Tolerance.length, height > tv.boxBottom + Tolerance.length, length > Tolerance.length else { return nil }
        return DrawerBox(x0: o.x0 + sv.sideClearance, y0: y0, z0: o.z0 + sv.bottomClearance, width: width, depth: length, height: height,
                         side: tv.boxSide, back: tv.boxBack, bottom: tv.boxBottom, slideTypeID: slide, slideLength: sv.slideLength)
    }

    // MARK: Hardware

    static func hingeType(_ e: Element, _ m: BIMModel) -> ElementID? {
        let t = e.furnitureFront?.hingeTypeID ?? FurnitureFrontTypes.values(of: e, m).hingeType
        return FurnitureHardware.Values(m[t]?.typeData).kind == .hinge ? t : nil
    }
    static func handleType(_ e: Element, _ m: BIMModel) -> ElementID? {
        let t = e.furnitureFront?.handleTypeID ?? FurnitureFrontTypes.values(of: e, m).handleType
        return FurnitureHardware.Values(m[t]?.typeData).kind == .handle ? t : nil
    }

    /// The hardware a front places, by slot ("hinge.<leaf>.<k>", "handle.<leaf>", "slides", "stay.<k>"), in the model
    /// (FMG3: turned with the bay's face).
    public static func hardware(_ e: Element, _ m: BIMModel) -> [HardwarePlacement] {
        let local = localHardware(e, m)
        guard let bay = m[e.hostID]?.furnitureBay, case let fr = BayFrame(bay), !fr.isIdentity else { return local }
        return local.map { var p = $0; p.at = fr.world(p.at); p.rotation = fr.angle; return p }
    }

    /// The hardware a front places, in its bay's frame (as if its face were the front).
    public static func localHardware(_ e: Element, _ m: BIMModel) -> [HardwarePlacement] {
        guard let f = e.furnitureFront, let g = geometry(e, m) else { return [] }
        let tv = FurnitureFrontTypes.values(of: e, m)
        let o = g.opening
        var out: [HardwarePlacement] = []
        let t = g.thickness
        // Hinges.
        if let ht = hingeType(e, m) {
            let hv = FurnitureHardware.Values(m[ht]?.typeData)
            for (li, leaf) in g.leaves.enumerated() {
                guard let h = leaf.hinge else { continue }
                let along: (Double, Double) = h == .left || h == .right ? (leaf.v.0.value, leaf.v.1.value) : (leaf.u.0.value, leaf.u.1.value)
                let count = hv.isPiano ? 1 : ComponentRules.hingeRule(m).count(forEdge: along.1 - along.0) // COMP: Hardware Rules (default as hingeCount)
                let positions = hv.isPiano ? [(along.0 + along.1) / 2] : hingePositions(along.0, along.1, count: count, inset: tv.hingeInset)
                // The end hinges keep their inset from the leaf's ends as it resizes; the ones between are placed by number.
                let ends: (PartValue, PartValue) = h == .left || h == .right ? leaf.v : leaf.u
                func pos(_ k: Int, _ p: Double) -> PartValue {
                    if hv.isPiano { return mid(ends.0, ends.1) }
                    if k == 0 { return ends.0.shiftedTo(p, from: ends.0.value) }
                    if k == positions.count - 1 { return ends.1.shiftedTo(p, from: ends.1.value) }
                    return PartValue(p)
                }
                let inner = g.face == .front ? leaf.w.1 : leaf.w.0
                // The carcass part the plate goes on, and the distance from the hinge edge to its inside face.
                let (sideOffset, part): (Double, ElementID?) = switch h {
                case .left: (o.x0 - leaf.u.0.value, o.left)
                case .right: (leaf.u.1.value - o.x1, o.right)
                case .top: (leaf.v.1.value - o.z1, o.top)
                case .bottom: (o.z0 - leaf.v.0.value, o.bottom)
                case .back: (leaf.v.1.value - o.y1, o.top)
                }
                let frontEdge: Double = tv.overlay == .inset ? -t : 0
                var flags: [String: ParamValue] = ["Top Edge": .bool(h == .top), "Bottom Edge": .bool(h == .bottom), "Back Edge": .bool(h == .back),
                                                   "Side Offset": .double(sideOffset), "Front Edge": .double(frontEdge), "Front Thickness": .double(t)]
                if hv.isPiano { flags["Length"] = .double(max(Tolerance.length * 10, along.1 - along.0 - 1 * inch)) }
                for (k, p) in positions.enumerated() {
                    let q = pos(k, p)
                    let at: (PartValue, PartValue, PartValue) = switch h {
                    case .left: (leaf.u.0, inner, q)
                    case .right: (leaf.u.1, inner, q)
                    case .top: (q, inner, leaf.v.1)
                    case .bottom: (q, inner, leaf.v.0)
                    case .back: (q, leaf.v.1, inner)
                    }
                    out.append(HardwarePlacement(slot: "hinge.\(li).\(k)", typeID: ht, at: at, mirrored: h == .right, values: flags, carcassPartID: part))
                }
            }
        }
        // Handles: one per leaf.
        if f.handlePosition != .none, let hd = handleType(e, m) {
            let hv = FurnitureHardware.Values(m[hd]?.typeData)
            let edgeOffset = f.handleOffset ?? (tv.handleOffset > 0 ? tv.handleOffset : 2.5 * inch)
            for (li, leaf) in g.leaves.enumerated() {
                let along = hv.isKnob ? 0 : max(hv.handleLength, hv.handleHoleSpacing)
                let fromEnd = max(2.5 * inch, along / 2 + 1 * inch)
                var u = mid(leaf.u.0, leaf.u.1), v = mid(leaf.v.0, leaf.v.1)
                var vertical = false
                switch (f.kind, leaf.hinge) {
                case (.door, .left?), (.door, .right?):
                    u = leaf.hinge == .left ? leaf.u.1.shifted(-edgeOffset) : leaf.u.0.shifted(edgeOffset)
                    vertical = !hv.isKnob
                    switch f.handlePosition {
                    case .top: v = leaf.v.1.shifted(-fromEnd)
                    case .bottom: v = leaf.v.0.shifted(fromEnd)
                    default: break
                    }
                case (.flap, .top?): v = leaf.v.0.shifted(max(1.5 * inch, edgeOffset))
                case (.flap, .bottom?): v = leaf.v.1.shifted(-max(1.5 * inch, edgeOffset))
                case (_, .back?): v = leaf.v.0.shifted(max(1.5 * inch, edgeOffset))
                default:
                    if f.handlePosition == .top { v = leaf.v.1.shifted(-max(1.25 * inch, leaf.height / 4)) }
                }
                // Edge pulls sit on the top edge.
                if hv.isEdgePull, g.face == .front { v = leaf.v.1 }
                let at: (PartValue, PartValue, PartValue) = g.face == .front ? (u, leaf.w.0, v) : (u, v, leaf.w.1)
                out.append(HardwarePlacement(slot: "handle.\(li)", typeID: hd, at: at, mirrored: false,
                                             values: ["Vertical": .bool(vertical), "On Lid": .bool(g.face == .top), "Front Thickness": .double(t)], carcassPartID: nil))
            }
        }
        // Slides: one pair per drawer.
        if f.kind == .drawer, let box = drawerBox(e, m), let st = box.slideTypeID {
            let sv = FurnitureHardware.Values(m[st]?.typeData)
            let mount = sv.isUndermount ? sv.bottomClearance - sv.slideHeight / 2 : sv.bottomClearance + min(box.height / 2, 1.5 * inch)
            let y = tv.overlay == .inset ? o.value("y0").shifted(tv.thickness) : o.value("y0")
            out.append(HardwarePlacement(slot: "slides", typeID: st, at: (o.value("x0"), y, o.value("z0")), mirrored: false,
                                         values: ["Opening Width": .double(o.width), "Mount Height": .double(mount)], carcassPartID: o.left))
        }
        // Stays: flaps, on one side (two when wider than 18").
        if f.kind == .flap, g.face == .front, let st = tv.stayType, FurnitureHardware.Values(m[st]?.typeData).kind == .stay {
            let z = tv.flapAction == .liftUp ? o.value("z1") : o.value("z0").shifted(2 * inch)
            out.append(HardwarePlacement(slot: "stay.0", typeID: st, at: (o.value("x0"), o.value("y0"), z), mirrored: false, values: [:], carcassPartID: o.left))
            if o.width > 18 * inch {
                out.append(HardwarePlacement(slot: "stay.1", typeID: st, at: (o.value("x1"), o.value("y0"), z), mirrored: true, values: [:], carcassPartID: o.right))
            }
        }
        out += lidStays(e, g, tv, m) // FMG3
        return out
    }

    // MARK: Operations

    static func level(_ m: BIMModel) -> ElementID? { m.levels.first?.id }

    /// A front type of `kind` (the given one when it is one, else the default), creating the standard types when the
    /// document has none.
    static func type(_ id: ElementID?, _ kind: FrontKind, in tx: TransactionContext) -> ElementID? {
        if let id, tx.model[id]?.typeData?.instanceCategory == .furnitureFronts, tx.model[id]?.typeData?.familyName == kind.rawValue { return id }
        if FurnitureFrontTypes.firstType(kind, tx.model) == nil { FurnitureFrontTypes.ensureStandard(in: tx) }
        return FurnitureFrontTypes.firstType(kind, tx.model)
    }

    /// Places a door, drawer or flap in a bay (a divided bay: in each of its cells that has none).
    @discardableResult
    public static func createFront(_ kind: FrontKind, in bayID: ElementID, typeID: ElementID? = nil, hingeFlipped: Bool = false,
                                   in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        guard tx.model.isFurniture else { throw TransactionError("Doors and drawers are placed in Furniture documents.") }
        guard let bay = tx.model[bayID], let bd = bay.furnitureBay else { throw TransactionError("Pick a bay.") }
        let cells = FurnitureBays.cellIDs(of: bayID, tx.model)
        if !cells.isEmpty {
            var ids: [ElementID] = []
            for c in cells where !tx.model.hosted(by: c).contains(where: { $0.furnitureFront != nil }) && FurnitureBays.cellIDs(of: c, tx.model).isEmpty {
                ids += try createFront(kind, in: c, typeID: typeID, hingeFlipped: hingeFlipped, in: tx)
            }
            guard !ids.isEmpty else { throw TransactionError("Every cell of \(bay.name) already has a front.", elements: [bayID]) }
            return ids
        }
        guard bd.opening != nil else { throw TransactionError("\(bay.name) is not enclosed: its opening can't take a \(kind.rawValue.lowercased()).", elements: [bayID]) }
        if let existing = tx.model.hosted(by: bayID).first(where: { $0.furnitureFront != nil }) {
            throw TransactionError("\(bay.name) already has a \(existing.furnitureFront!.kind.rawValue.lowercased()).", elements: [existing.id],
                                   resolution: "Delete it, or divide the bay (Bay Divide) for more fronts.")
        }
        if kind == .drawer, bd.face == .top { throw TransactionError("Drawers go in bays seen from the front.") }
        let t = type(typeID, kind, in: tx)
        var f = FrontData(kind: kind, hingeFlipped: hingeFlipped)
        // Wall cabinets (bays high up) get their door handles at the bottom, as cabinet makers fit them.
        if kind == .door, let o = bd.opening, o.z0 > 36 * inch { f.handlePosition = .bottom }
        let id = tx.create(.furnitureFronts, data: .furnitureFront(f), typeID: t, levelID: level(tx.model), hostID: bayID)
        if let o = bd.opening, let tid = t {
            let probe = Element(id: id, category: .furnitureFronts, data: .furnitureFront(f), typeID: tid, hostID: bayID)
            if geometry(f, type: FurnitureFrontTypes.Values(tx.model[tid]?.typeData), bay: bd, opening: o) == nil {
                tx.delete(id)
                throw TransactionError("The bay is too small for this \(kind.rawValue.lowercased()) type.", elements: [bayID])
            }
            if kind == .drawer, drawerBox(probe, tx.model) == nil {
                tx.delete(id)
                throw TransactionError("The bay is too shallow or too small for a drawer box and slides.", elements: [bayID],
                                       resolution: "Make the bay deeper, or use a shorter slide type.")
            }
        }
        return [id]
    }

    /// Drawers: divides the bay into `count` equal rows (EQ) and puts a drawer in each, as a drawer stack.
    @discardableResult
    public static func createDrawers(in bayID: ElementID, count: Int, typeID: ElementID? = nil, in tx: TransactionContext) throws(TransactionError) -> [ElementID] {
        if count > 1 {
            guard FurnitureBays.cellIDs(of: bayID, tx.model).isEmpty else { return try createFront(.drawer, in: bayID, typeID: typeID, in: tx) }
            try FurnitureBays.divide(bayID, BayDivision(direction: .rows, count: count), in: tx)
        }
        return try createFront(.drawer, in: bayID, typeID: typeID, in: tx)
    }

    /// Pick New Host: moves fronts to another bay (one without a front).
    public static func rehost(_ ids: [ElementID], to bayID: ElementID, in tx: TransactionContext) throws(TransactionError) {
        guard tx.model[bayID]?.furnitureBay?.opening != nil else { throw TransactionError("Pick an enclosed bay.") }
        guard FurnitureBays.cellIDs(of: bayID, tx.model).isEmpty else { throw TransactionError("Pick one of the divided bay's cells.") }
        guard ids.count == 1 else { throw TransactionError("Select one front to move to another bay.") }
        if let other = tx.model.hosted(by: bayID).first(where: { $0.furnitureFront != nil && !ids.contains($0.id) }) {
            throw TransactionError("That bay already has a front.", elements: [other.id])
        }
        tx.update(ids[0]) { $0.hostID = bayID }
    }

    // MARK: Regeneration

    /// Numbers new fronts (D1, DW1, FL1…), adopts a hinge or handle type changed on an owned instance, and keeps every
    /// front's hardware in step with it.
    static func regenerate(_ tx: TransactionContext, _ touched: Set<ElementID>) {
        let fronts = tx.model.elements(.furnitureFronts)
        let owned = tx.model.elements(.furnitureHardware).filter { $0.params[FurnitureHardware.slotParam] != nil }
        guard !fronts.isEmpty || !owned.isEmpty else { return }
        numberMarks(tx)
        // A Type Selector change on an owned hinge or handle becomes the front's choice (Revit swaps nested shared
        // families the same way, through the host's parameter).
        for h in owned where touched.contains(h.id) && tx.driven.contains(h.id) {
            guard let front = tx.model[h.hostID], front.furnitureFront != nil, let slot = h.params[FurnitureHardware.slotParam]?.textValue,
                  let t = h.typeID, tx.originalElement(h.id)?.typeID != t else { continue }
            let kind = FurnitureHardware.Values(tx.model[t]?.typeData).kind
            if slot.hasPrefix("handle"), kind == .handle { tx.propagate(front.id) { $0.furnitureFront?.handleTypeID = t } }
            if slot.hasPrefix("hinge"), kind == .hinge { tx.propagate(front.id) { $0.furnitureFront?.hingeTypeID = t } }
        }
        let levelZ = tx.model.elevation(ofLevel: level(tx.model))
        var keep: Set<ElementID> = []
        for front in tx.model.elements(.furnitureFronts) {
            if front.furnitureFront != nil, tx.model[front.hostID]?.furnitureBay?.opening == nil {
                tx.warn(ModelWarning(.warning, code: "front.noBay", "\(front.category.singularName) \(front.mark) has no enclosed bay to fit.", elements: [front.id]))
            }
            let wanted = hardware(front, tx.model)
            let existing = tx.model.hosted(by: front.id).filter { $0.params[FurnitureHardware.slotParam] != nil }
            var bySlot: [String: Element] = [:]
            for h in existing {
                guard let s = h.params[FurnitureHardware.slotParam]?.textValue, bySlot[s] == nil else { continue }
                bySlot[s] = h
            }
            for w in wanted {
                let data = ComponentData(location: w.origin.xy, rotation: w.rotation, offset: w.origin.z - levelZ, mirrored: w.mirrored) // FMG3: turned with its face
                if let h = bySlot[w.slot] {
                    keep.insert(h.id)
                    var e = h
                    e.typeID = w.typeID
                    e.data = .component(data)
                    e.params[FurnitureHardware.ownerParam] = .ref(front.id)
                    for (k, v) in w.values { e.params[Parameters.familyParamID(k)] = v }
                    if e != h { tx.propagate(h.id) { $0 = e } }
                } else {
                    let id = tx.create(.furnitureHardware, data: .component(data), typeID: w.typeID, levelID: front.levelID, hostID: front.id) { e in
                        e.params[FurnitureHardware.ownerParam] = .ref(front.id)
                        e.params[FurnitureHardware.slotParam] = .text(w.slot)
                        for (k, v) in w.values { e.params[Parameters.familyParamID(k)] = v }
                    }
                    keep.insert(id)
                }
            }
        }
        // Owned hardware a front no longer wants (or whose front is gone, or a copy) goes.
        for h in tx.model.elements(.furnitureHardware) where h.params[FurnitureHardware.slotParam] != nil && !keep.contains(h.id) {
            tx.delete(h.id)
        }
    }

    /// New fronts without a Mark get the next number of their kind.
    static func numberMarks(_ tx: TransactionContext) {
        var high: [String: Int] = [:]
        var owners: [String: [ElementID]] = [:]
        let all = tx.model.elements(.furnitureFronts).sorted { $0.id < $1.id }
        for e in all where !e.mark.isEmpty { owners[e.mark, default: []].append(e.id) }
        var unnumbered: [(ElementID, String)] = []
        for e in all {
            guard let k = e.furnitureFront?.kind else { continue }
            let isNew = tx.originalElement(e.id) == nil
            let duplicate = isNew && (owners[e.mark]?.count ?? 0) > 1 && owners[e.mark]?.first != e.id
            if e.mark.isEmpty || duplicate { if isNew || e.mark.isEmpty { unnumbered.append((e.id, k.markPrefix)) }; continue }
            if e.mark.hasPrefix(k.markPrefix), let n = Int(e.mark.dropFirst(k.markPrefix.count)) { high[k.markPrefix] = max(high[k.markPrefix] ?? 0, n) }
        }
        for (id, prefix) in unnumbered {
            let n = (high[prefix] ?? 0) + 1
            high[prefix] = n
            tx.propagate(id) { $0.mark = "\(prefix)\(n)" }
        }
    }
}

/// FM5: regeneration of bays, fronts and their hardware (one call from FurnitureRegeneration, after the parts).
public enum FurnitureOpeningsRegeneration {
    public static func regenerate(_ tx: TransactionContext, _ touched: [ElementID]) {
        let m = tx.model
        guard !m.elements(.furnitureBays).isEmpty || !m.elements(.furnitureFronts).isEmpty || !m.elements(.furnitureHardware).isEmpty else { return }
        FurnitureBays.regenerate(tx)
        FurnitureFronts.regenerate(tx, Set(touched))
        fitPlanCrops(tx)
    }

    /// Plans whose crop follows the piece (FurnitureViews.autoCrop, fitted to the planes when they move) grow to take in
    /// the door swings.
    static func fitPlanCrops(_ tx: TransactionContext) {
        var swings = Rect2.empty
        for f in tx.model.elements(.furnitureFronts) {
            for c in FurnitureSwings.plan(f, tx.model) {
                switch c {
                case .line(let s): swings = swings.union(Rect2(points: [s.start, s.end]))
                case .arc(let a): swings = swings.union(Rect2(center: a.center, halfSize: Vec2(a.radius, a.radius)))
                }
            }
        }
        guard !swings.isEmpty else { return }
        let need = swings.expanded(by: 0.05)
        for v in tx.model.views where v.params[FurnitureViews.autoCrop]?.boolValue == true && v.view?.kind.isPlan == true {
            guard let d = v.view, d.cropActive, let current = d.cropRegion, !current.isEmpty else { continue }
            let crop = current.union(need)
            if crop != current { tx.propagate(v.id) { $0.view?.cropRegion = crop } }
        }
    }
}
