import Foundation
import ArcusGeometry

// FMG2: Explode Parts, a 3D view option for Furniture documents (shop drawing F104 uses it). Every part moves out from
// the parts it joins, along the joint's axis: at a joint, the part that runs through moves away from the part that
// ends at it, and that part moves the other way, one step each (a top trimmed between two sides stays while the sides
// move out; the legs under a top move down and out from their aprons). A part that other parts run into from both
// sides (a bottom with the back above and the plinth below) moves the way it lies from the piece's middle. Parts no
// joint moves and that sit on the
// outside of the piece across their thickness (a back, a plinth, doors and drawers) move out that way. Hardware moves
// with the front or part that owns it. Nothing in the model moves: the 3D view (and its PDF, image and sheet
// viewports) draws each element offset, with an optional tag (its Mark) on each part.

public enum FurnitureExplode {
    static let inch = 0.0254
    /// The view's parameters: Explode Parts (on/off), Explode Distance and Tag Parts.
    public static let onParam = ParameterID("furniture.view.explode")
    public static let distanceParam = ParameterID("furniture.view.explodeDistance")
    public static let tagsParam = ParameterID("furniture.view.explodeTags")
    /// The distance a new exploded view moves parts by, and the slider's range.
    public static let defaultDistance = 6 * inch
    public static let maximumDistance = 24 * inch

    // MARK: View settings

    public static func isExploded(_ view: Element) -> Bool { view.view?.kind == .threeD && view.params[onParam]?.boolValue == true }
    public static func distance(_ view: Element) -> Double { view.params[distanceParam]?.doubleValue ?? defaultDistance }
    public static func showsTags(_ view: Element) -> Bool { view.params[tagsParam]?.boolValue ?? true }

    /// Turns Explode Parts on or off in a 3D view, with a distance and tags (nil keeps the view's).
    public static func set(_ viewID: ElementID, on: Bool, distance: Double? = nil, tags: Bool? = nil, in tx: TransactionContext) throws(TransactionError) {
        guard tx.model.isFurniture else { throw TransactionError("Explode Parts works in Furniture documents.") }
        guard tx.model[viewID]?.view?.kind == .threeD else { throw TransactionError("Explode Parts works in 3D views.", resolution: "Open a 3D view.") }
        if let d = distance, !(d >= 0 && d <= maximumDistance + 1e-9) { throw TransactionError("The distance must be between 0\" and \(Int((maximumDistance / inch).rounded()))\".") }
        tx.update(viewID) { v in
            v.params[onParam] = .bool(on)
            if let distance { v.params[distanceParam] = .double(distance) }
            if let tags { v.params[tagsParam] = .bool(tags) }
        }
    }

    // MARK: Offsets

    /// Each element's offset in `view` (empty when the view isn't exploded).
    public static func offsets(_ m: BIMModel, view: Element) -> [ElementID: Vec3] {
        guard m.isFurniture, isExploded(view) else { return [:] }
        let d = distance(view)
        guard d > 1e-9 else { return [:] }
        return directions(m).mapValues { $0 * d }
    }

    /// The direction (in steps of one distance per axis) each element moves when its view explodes (cached).
    public static func directions(_ m: BIMModel) -> [ElementID: Vec3] {
        guard m.isFurniture else { return [:] }
        if let c = ExplodeCache.shared.get(m.contentStamp) { return c }
        let v = compute(m)
        ExplodeCache.shared.put(m.contentStamp, v)
        return v
    }

    static func compute(_ m: BIMModel) -> [ElementID: Vec3] {
        let sol = JointSolver.solve(m)
        var steps: [ElementID: [Double]] = [:]
        // Per part and axis: the pushes it gets as the part that runs through, and as the part that ends.
        var asThrough: [ElementID: [Set<Double>]] = [:], asOther: [ElementID: [Int]] = [:]
        for j in sol.joints {
            let s: Double = j.otherEndAtMax ? 1 : -1 // the through part lies toward +s along the axis
            steps[j.throughID, default: [0, 0, 0]][j.axis.idx] += s
            steps[j.otherID, default: [0, 0, 0]][j.axis.idx] -= s
            asThrough[j.throughID, default: [[], [], []]][j.axis.idx].insert(s)
            asOther[j.otherID, default: [0, 0, 0]][j.axis.idx] += 1
        }
        // The piece's box, and each element's box (parts, fronts, hardware, forms).
        var boxes: [ElementID: Box3] = [:]
        let cats = Category.furnitureParts.filter { $0 != .furnitureEdgeProfiles } + [.furnitureFronts, .furnitureHardware]
        for e in m.elements(cats) where !e.isType {
            let b = GeometryCache.shared.parts(e, m, detail: .medium).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
            if !b.isEmpty { boxes[e.id] = b }
        }
        let piece = boxes.values.reduce(Box3.empty) { $0.union($1) }
        guard !piece.isEmpty else { return [:] }
        var out: [ElementID: Vec3] = [:]
        for (id, b) in boxes {
            guard let e = m[id], e.category != .furnitureHardware else { continue }
            var v = (steps[id] ?? [0, 0, 0]).map { max(-1, min(1, $0)) }
            let c = [b.center.x, b.center.y, b.center.z], pc = [piece.center.x, piece.center.y, piece.center.z]
            let pext = [piece.max.x - piece.min.x, piece.max.y - piece.min.y, piece.max.z - piece.min.z]
            for k in 0..<3 where abs(v[k]) < 0.5 && asThrough[id]?[k].count == 2 && (asOther[id]?[k] ?? 0) == 0 && abs(c[k] - pc[k]) > 0.1 * pext[k] {
                v[k] = c[k] > pc[k] ? 1 : -1 // run into from both sides: out from the middle
            }
            if v.allSatisfy({ abs($0) < 0.5 }) {
                // Nothing pulls it: out across its thickness when it's on the outside of the piece.
                let ext = [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z]
                let lo = [b.min.x, b.min.y, b.min.z], hi = [b.max.x, b.max.y, b.max.z]
                let plo = [piece.min.x, piece.min.y, piece.min.z], phi = [piece.max.x, piece.max.y, piece.max.z]
                if let t = (0..<3).min(by: { ext[$0] < ext[$1] }) {
                    let tol = max(1.5 * ext[t], 1 * inch)
                    // Fronts go twice as far, clear of the carcass edges that move out with the sides.
                    let step: Double = e.category == .furnitureFronts ? 2 : 1
                    let atHi = hi[t] >= phi[t] - tol, atLo = lo[t] <= plo[t] + tol
                    if atHi && !atLo { v[t] = step } else if atLo && !atHi { v[t] = -step }
                }
            }
            if v.contains(where: { abs($0) > 0.5 }) { out[id] = Vec3(v[0], v[1], v[2]) }
        }
        // Hardware moves with its owner.
        for h in m.elements(.furnitureHardware) where !h.isType {
            if let owner = h.params[FurnitureHardware.ownerParam]?.refValue ?? h.hostID, let v = out[owner] { out[h.id] = v }
        }
        return out
    }

    // MARK: Tags

    /// FMG4: where a joint marker between `parts` is drawn in an exploded view: halfway between their offsets.
    public static func markerOffset(_ parts: [ElementID], _ offsets: [ElementID: Vec3]) -> Vec3 {
        guard !parts.isEmpty, !offsets.isEmpty else { return Vec3(0, 0, 0) }
        return parts.reduce(Vec3(0, 0, 0)) { $0 + (offsets[$1] ?? Vec3(0, 0, 0)) } * (1 / Double(parts.count))
    }

    /// The parts an exploded view tags: parts and fronts with a Mark.
    public static func tagged(_ e: Element) -> Bool {
        (e.category.isFurniturePart && e.furnitureEdgeProfile == nil || e.category == .furnitureFronts) && !e.mark.isEmpty
    }

    /// Tags on an exploded 3D view's hidden-line drawing: each part's Mark in a box at the middle of its projected
    /// outline, moved clear of the tags already placed (with a leader back to the part).
    static func tagItems(_ builder: ViewGraphicsBuilder, _ centers: [(Element, Vec2)], drawing: Rect2? = nil) -> [GItem] {
        // FMG4: at paper size, but never more than a thirtieth of the drawing (a 3D view's image on its own, not at its
        // scale on a sheet, would otherwise get tags many times the parts' size).
        let paperH = 0.0022, full = builder.paper(paperH)
        let k = drawing.map { min(1, max($0.width, $0.height) / 30 / max(full, 1e-9)) } ?? 1
        let h = paperH * k, pad = builder.paper(0.0008) * k
        let th = full * k
        var placed: [Rect2] = []
        var out: [GItem] = []
        let stroke = GStroke(weight: 1, color: .black)
        for (e, c) in centers.sorted(by: { $0.1.y != $1.1.y ? $0.1.y > $1.1.y : $0.1.x < $1.1.x }) {
            let w = th * 0.62 * Double(max(1, e.mark.count)) + 2 * pad, hh = th + 2 * pad
            func rect(_ p: Vec2) -> Rect2 { Rect2(center: p, halfSize: Vec2(w / 2, hh / 2)) }
            var at = c
            let step = max(w, hh) * 1.15
            search: for ring in 0...8 {
                let candidates: [Vec2] = ring == 0 ? [c] : (0..<8).map { k in
                    let a = Double(k) * .pi / 4 + .pi / 2
                    return c + Vec2(cos(a), sin(a)) * (step * Double(ring))
                }
                for p in candidates where !placed.contains(where: { $0.expanded(by: pad).intersects(rect(p)) }) { at = p; break search }
            }
            let r = rect(at)
            placed.append(r)
            var prims: [GPrimitive] = []
            if at.distance(to: c) > 1e-9 {
                // A leader from the box's nearest edge point to the part.
                let q = Vec2(min(max(c.x, r.min.x), r.max.x), min(max(c.y, r.min.y), r.max.y))
                prims.append(.polyline([q, c], closed: false, stroke))
                prims.append(.arc(Arc2(center: c, radius: builder.paper(0.0005) * k, startAngle: 0, sweep: 2 * .pi), stroke))
            }
            prims.append(.fill([Polygon2.rectangle(r)], GFill(pattern: .solid, color: .white)))
            prims.append(.polyline(Polygon2.rectangle(r).points, closed: true, stroke))
            prims.append(.text(GText(position: at, height: h, string: e.mark, alignment: .center, verticalAnchor: 0.5, bold: true)))
            out.append(GItem(elementID: e.id, category: .tags, layer: .annotation, primitives: prims, selectable: false))
        }
        return out
    }
}

/// Explode directions per model state (a few recent states).
final class ExplodeCache: @unchecked Sendable {
    static let shared = ExplodeCache()
    private let lock = NSLock()
    private var entries: [(UInt64, [ElementID: Vec3])] = []
    func get(_ stamp: UInt64) -> [ElementID: Vec3]? { lock.lock(); defer { lock.unlock() }; return entries.first { $0.0 == stamp }?.1 }
    func put(_ stamp: UInt64, _ v: [ElementID: Vec3]) {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.0 == stamp }
        entries.insert((stamp, v), at: 0)
        if entries.count > 4 { entries.removeLast() }
    }
}
