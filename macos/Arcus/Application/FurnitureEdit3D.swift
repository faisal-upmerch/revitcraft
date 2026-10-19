import Foundation
import ArcusGeometry
import ArcusDomain

// FM3D: editing Furniture parts in 3D views, as Revit edits family solids in 3D.
// - Shape handles: an arrow on each face of a selected part that can stretch (a panel's ends, top and base; a leg's
//   top and base; a shelf's edges; an extrusion's ends). Dragging moves that face along its axis. A face locked to a
//   reference plane moves the plane, so the labelled dimension's parameter changes and everything locked to the plane
//   follows (the Family Editor's behaviour); other faces move alone and lock to a plane they're dropped on.
// - Temporary dimensions: from the selected part's faces to the nearest plane or part face beyond them on each axis;
//   typing a value moves the part.
// - 3D moves: dragging a part slides it in the plane of the face grabbed, its faces snapping to planes and other parts.

/// A shape handle on a part's face.
public struct FurnitureShapeHandle: Sendable, Hashable {
    public var elementID: ElementID
    public var face: PartFaceRef
    /// The middle of the face (where the arrow stands).
    public var position: Vec3
    /// Where the face is along its axis.
    public var value: Double
    /// Where the opposite face is (the face can't be dragged through it).
    public var opposite: Double
    /// The coordinates the face is (FurniturePartCoordinates keys; "w0", "w1", "height" for forms).
    public var keys: [String]
    /// The reference plane the face is locked to: dragging it moves the plane.
    public var plane: String?

    public var axis: FamilyAxis { face.axis }
    /// The arrow's direction: out of the face.
    public var direction: Vec3 { FurniturePlacements.unit(face.axis) * (face.atMax ? 1 : -1) }
}

public enum FurnitureShapeHandles {
    /// The smallest a part can be stretched to (1/16").
    public static let minimumSize = 0.0254 / 16

    /// The shape handles of a part or form.
    public static func handles(_ e: Element, _ m: BIMModel) -> [FurnitureShapeHandle] {
        if let f = e.furnitureForm { return formHandles(e, f, m) }
        guard e.category.isFurniturePart, e.furnitureEdgeProfile == nil, let box = FurniturePartSolids.partBox(e, m)?.box else { return [] }
        let coords = FurniturePartCoordinates.coordinates(of: e)
        let bounds = FurniturePartBounds.bounds(of: e)
        var out: [FurnitureShapeHandle] = []
        for face in PartFaceRef.all {
            let v = FurniturePlacements.component(face.atMax ? box.max : box.min, face.axis)
            let opp = FurniturePlacements.component(face.atMax ? box.min : box.max, face.axis)
            let on = coords.filter { $0.axis == face.axis && abs($0.value - v) <= 1e-6 }
            guard !on.isEmpty, stretchesOnly(e, on.map(\.key), face, box, m) else { continue }
            // Locked when every coordinate on the face follows the same plane with no offset.
            let names = Set(on.compactMap { c -> String? in if case .plane(let n, let o)? = bounds[c.key], abs(o) < 1e-7 { return n }; return nil })
            let plane = names.count == 1 && on.allSatisfy({ if case .plane? = bounds[$0.key] { return true }; return false }) ? names.first : nil
            out.append(FurnitureShapeHandle(elementID: e.id, face: face, position: faceCenter(box, face), value: v, opposite: opp, keys: on.map(\.key), plane: plane))
        }
        return out
    }

    /// True when moving the coordinates `keys` by a little moves only `face` of the part's box (a stretch, not a move).
    static func stretchesOnly(_ e: Element, _ keys: [String], _ face: PartFaceRef, _ box: Box3, _ m: BIMModel) -> Bool {
        let d = 0.01
        var p = e
        let coords = Dictionary(FurniturePartCoordinates.coordinates(of: e).map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        for k in keys { FurniturePartCoordinates.set(k, (coords[k] ?? 0) + d, in: &p) }
        guard let b = FurniturePartSolids.partBox(p, m)?.box else { return false }
        for a in FamilyAxis.allCases {
            for atMax in [false, true] {
                let before = FurniturePlacements.component(atMax ? box.max : box.min, a)
                let after = FurniturePlacements.component(atMax ? b.max : b.min, a)
                let expected = a == face.axis && atMax == face.atMax ? before + d : before
                if abs(after - expected) > 1e-6 { return false }
            }
        }
        return true
    }

    static func faceCenter(_ b: Box3, _ f: PartFaceRef) -> Vec3 {
        var c = b.center
        let v = FurniturePlacements.component(f.atMax ? b.max : b.min, f.axis)
        switch f.axis { case .x: c.x = v; case .y: c.y = v; case .z: c.z = v }
        return c
    }

    /// Extrusions and blends stretch at their two ends, cushions at their top (forms that follow planes on that axis
    /// don't: their planes place them).
    static func formHandles(_ e: Element, _ f: FurnitureFormData, _ m: BIMModel) -> [FurnitureShapeHandle] {
        let b = ElementMeshes.bounds(e, m)
        guard !b.isEmpty else { return [] }
        var out: [FurnitureShapeHandle] = []
        func add(_ axis: FamilyAxis, _ atMax: Bool, _ key: String) {
            guard f.lock?[axis] == nil else { return }
            let face = PartFaceRef(axis: axis, atMax: atMax)
            let v = FurniturePlacements.component(atMax ? b.max : b.min, axis), opp = FurniturePlacements.component(atMax ? b.min : b.max, axis)
            out.append(FurnitureShapeHandle(elementID: e.id, face: face, position: faceCenter(b, face), value: v, opposite: opp, keys: [key], plane: nil))
        }
        switch f.kind {
        case .extrusion:
            let a = f.plane.axes.w
            add(a, false, "w0"); add(a, true, "w1")
        case .blend: add(.z, false, "w0"); add(.z, true, "w1")
        case .cushion: add(.z, true, "height")
        default: break
        }
        return out
    }

    /// Drags a handle's face to `value` along its axis.
    public static func stretch(_ h: FurnitureShapeHandle, to value: Double, in tx: TransactionContext) throws(TransactionError) {
        guard let e = tx.model[h.elementID] else { return }
        let size = h.face.atMax ? value - h.opposite : h.opposite - value
        guard size >= minimumSize - 1e-9 else {
            throw TransactionError("The part can't be smaller than 1/16\".", elements: [h.elementID])
        }
        let delta = value - h.value
        guard abs(delta) > 1e-9 else { return }
        if var f = e.furnitureForm {
            for k in h.keys {
                switch k {
                case "w0": f.w0 += delta
                case "w1": f.w1 += delta
                case "height": f.w1 += delta; f.cushion?.height += delta
                default: break
                }
            }
            tx.update(e.id) { $0.furnitureForm = f }
            return
        }
        if let name = h.plane, let plane = FurniturePlanes.all(tx.model).first(where: { FurniturePlanes.names(tx.model)[$0.id] == name }), var rp = plane.referencePlane {
            guard !plane.pinned else {
                throw TransactionError("This face is locked to “\(name)”, which is pinned.", elements: [h.elementID, plane.id],
                                       resolution: "Unpin the plane to change the piece's size, or unlock the face.")
            }
            rp = FurniturePlanes.placed(rp, at: value, extents: FurniturePlanes.extents(tx.model))
            tx.update(plane.id) { $0.referencePlane = rp }
            return
        }
        let coords = Dictionary(FurniturePartCoordinates.coordinates(of: e).map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        tx.update(e.id) { el in
            for k in h.keys { FurniturePartCoordinates.set(k, (coords[k] ?? h.value) + delta, in: &el) }
            // A top or base dragged off its shelf no longer follows it (Detach).
            if var p = el.furniturePanel {
                if h.keys.contains("top") { p.attachedTopID = nil }
                if h.keys.contains("base") { p.attachedBaseID = nil }
                el.furniturePanel = p
            }
            if var l = el.furnitureLeg, h.keys.contains("top") { l.attachedTopID = nil; el.furnitureLeg = l }
        }
    }
}

// MARK: - Snapping along an axis

/// A position a face can snap to along an axis: a reference plane or another part's face.
public struct FurnitureAxisSnap: Sendable, Hashable {
    public var value: Double
    public var label: String
}

public enum FurnitureAxisSnaps {
    /// The planes along `axis` and the faces of the other parts (not `excluding`) across it.
    public static func candidates(along axis: FamilyAxis, excluding: Set<ElementID>, _ m: BIMModel) -> [FurnitureAxisSnap] {
        var out = FurniturePartCoordinates.planes(along: axis, m).map { FurnitureAxisSnap(value: $0.position, label: $0.name) }
        for c in Category.furnitureParts {
            for e in m.elements(c) where !excluding.contains(e.id) {
                guard let b = FurniturePartFaces.box(e, m) else { continue }
                let name = e.mark.isEmpty ? e.category.singularName : e.mark
                out.append(FurnitureAxisSnap(value: FurniturePlacements.component(b.min, axis), label: name))
                out.append(FurnitureAxisSnap(value: FurniturePlacements.component(b.max, axis), label: name))
            }
        }
        return out
    }

    /// The nearest candidate within `tolerance` of `value`.
    public static func nearest(_ value: Double, _ candidates: [FurnitureAxisSnap], tolerance: Double) -> FurnitureAxisSnap? {
        candidates.filter { abs($0.value - value) <= tolerance }.min { abs($0.value - value) < abs($1.value - value) }
    }
}

// MARK: - Temporary dimensions

/// A temporary dimension of a selected part in 3D: from a face to the nearest plane or part face beyond it.
public struct FurnitureTempDim3D: Sendable, Hashable {
    public var elementID: ElementID
    public var axis: FamilyAxis
    /// On the reference.
    public var from: Vec3
    /// On the part's face.
    public var to: Vec3
    public var value: Double
    /// The plane's name, or the other part's Mark.
    public var reference: String
    /// +1 when the face is beyond the reference along the axis (moving the part along the axis lengthens it).
    public var sign: Double
}

public enum FurnitureTempDims3D {
    /// The temporary dimensions of a part: on each axis, from its low face down to the nearest reference and from its
    /// high face up to the nearest one (planes, and faces of parts that overlap it across the axis).
    public static func dims(_ e: Element, _ m: BIMModel, reach: Double = 2.5) -> [FurnitureTempDim3D] {
        guard e.category.isFurniturePart, e.furnitureEdgeProfile == nil, let box = FurniturePartFaces.box(e, m) else { return [] }
        var out: [FurnitureTempDim3D] = []
        let others = Category.furnitureParts.flatMap { m.elements($0) }.filter { $0.id != e.id }.compactMap { o in FurniturePartFaces.box(o, m).map { (o, $0) } }
        for a in FamilyAxis.allCases {
            let across = FamilyAxis.allCases.filter { $0 != a }
            func overlaps(_ b: Box3) -> Bool {
                across.allSatisfy { x in
                    FurniturePlacements.component(b.max, x) > FurniturePlacements.component(box.min, x) + 1e-4
                        && FurniturePlacements.component(b.min, x) < FurniturePlacements.component(box.max, x) - 1e-4
                }
            }
            var refs = FurniturePartCoordinates.planes(along: a, m).map { FurnitureAxisSnap(value: $0.position, label: $0.name) }
            for (o, b) in others where overlaps(b) {
                let name = o.mark.isEmpty ? o.category.singularName : o.mark
                refs.append(FurnitureAxisSnap(value: FurniturePlacements.component(b.min, a), label: name))
                refs.append(FurnitureAxisSnap(value: FurniturePlacements.component(b.max, a), label: name))
            }
            let lo = FurniturePlacements.component(box.min, a), hi = FurniturePlacements.component(box.max, a)
            let c = box.center
            func at(_ v: Double) -> Vec3 { var p = c; switch a { case .x: p.x = v; case .y: p.y = v; case .z: p.z = v }; return p }
            if let r = refs.filter({ $0.value < lo - 1e-4 && lo - $0.value <= reach }).max(by: { $0.value < $1.value }) {
                out.append(FurnitureTempDim3D(elementID: e.id, axis: a, from: at(r.value), to: at(lo), value: lo - r.value, reference: r.label, sign: 1))
            }
            if let r = refs.filter({ $0.value > hi + 1e-4 && $0.value - hi <= reach }).min(by: { $0.value < $1.value }) {
                out.append(FurnitureTempDim3D(elementID: e.id, axis: a, from: at(r.value), to: at(hi), value: r.value - hi, reference: r.label, sign: -1))
            }
        }
        return out
    }

    /// The move that makes a temporary dimension read `value`.
    public static func move(for d: FurnitureTempDim3D, to value: Double) -> Vec3 {
        FurniturePlacements.unit(d.axis) * ((value - d.value) * d.sign)
    }
}

// MARK: - 3D moves

public enum FurnitureMove3D {
    /// Moves elements by a 3D vector: across the plan as Move does in plan (`plan`: the plan view whose transform it
    /// is), and up or down for parts, bays and hardware (their heights).
    public static func translate(_ ids: [ElementID], by d: Vec3, plan: ElementID?, in tx: TransactionContext) throws(TransactionError) {
        if d.xy.length > 1e-9 { try ElementOperations.transform(ids, by: .translation(d.xy), in: tx, viewID: plan) }
        guard abs(d.z) > 1e-9 else { return }
        let pinned = ids.filter { tx.model[$0]?.pinned == true }
        if !pinned.isEmpty { throw TransactionError("Pinned elements can't be moved. Unpin them first.", elements: pinned) }
        let up = Vec3(0, 0, d.z)
        var set = Set(ids)
        set.formUnion(FurnitureBays.movedBays(set, tx.model))
        for id in set.sorted() {
            guard let e = tx.model[id] else { continue }
            if e.category.isFurniturePart { tx.update(id) { FurniturePartTransform.translate(&$0, by: up) } }
            else if e.furnitureBay != nil || e.furnitureBaySeparator != nil { tx.update(id) { _ = FurnitureBays.translate3D(&$0, by: up) } }
            else if case .component(var c) = e.data, c.sketchPlane == nil { c.offset += d.z; tx.update(id) { $0.data = .component(c) } }
        }
    }

    /// The move of a dragged box snapped along `axes`: on each axis its low or high face takes the nearest candidate
    /// within `tolerance`. Returns the snapped move and what each axis snapped to.
    public static func snap(_ box: Box3, by d: Vec3, axes: [FamilyAxis], candidates: [FamilyAxis: [FurnitureAxisSnap]], tolerance: Double)
        -> (move: Vec3, snaps: [(axis: FamilyAxis, snap: FurnitureAxisSnap)]) {
        var move = d
        var snaps: [(axis: FamilyAxis, snap: FurnitureAxisSnap)] = []
        for a in axes {
            let dv = FurniturePlacements.component(d, a)
            let lo = FurniturePlacements.component(box.min, a) + dv, hi = FurniturePlacements.component(box.max, a) + dv
            let cands = candidates[a] ?? []
            var best: (FurnitureAxisSnap, Double)?
            for v in [lo, hi] {
                if let s = FurnitureAxisSnaps.nearest(v, cands, tolerance: tolerance), best.map({ abs(s.value - v) < abs($0.1) }) ?? true { best = (s, s.value - v) }
            }
            guard let (s, adjust) = best else { continue }
            switch a { case .x: move.x += adjust; case .y: move.y += adjust; case .z: move.z += adjust }
            snaps.append((a, s))
        }
        return (move, snaps)
    }
}
