import Foundation
import ArcusGeometry

// FMG3: bays on canted faces and moving bays. On a canted face (a corner cabinet's 45° door) every part bounds bays by
// its extent seen in the face's frame: single boxes and shaped shelves keep the planes they follow (so the opening
// flexes), other parts count by their corners. Bays move like rooms (Move, the arrow keys, dragging): the point inside
// them moves and the opening is found again there at regeneration, and the fronts they host follow.

extension FurnitureBays {
    typealias PartBox = FurniturePartSolids.PartBox

    /// The parts that aren't single boxes, as bounders of a canted face.
    static func cantedBounders(_ m: BIMModel, _ frame: BayFrame, skipping: Set<ElementID>) -> [Bounder] {
        var out: [Bounder] = []
        for c in [Category.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails] {
            for e in m.elements(c) where !skipping.contains(e.id) {
                if e.furniturePanel?.role == .back || e.furnitureShelf?.adjustable == true { continue }
                guard let box = cantedBox(e, m, frame) else { continue }
                let role = e.furniturePartKind
                out.append(Bounder(id: e.id, box: box, shared: role == .divider || role == .shelf, isSeparator: false))
            }
        }
        return out
    }

    /// A part's extent in a canted frame: a shaped shelf's corners with their planes, other parts by numbers.
    static func cantedBox(_ e: Element, _ m: BIMModel, _ frame: BayFrame) -> PartBox? {
        if let s = e.furnitureShelf, s.boundary.count >= 3 {
            let b = FurniturePartBounds.bounds(of: e)
            let pts = s.boundary.enumerated().map { i, p in (PartValue(p.x, b["p\(i).x"]), PartValue(p.y, b["p\(i).y"])) }
            let us = pts.map { frame.localU($0.0, $0.1) }, vs = pts.map { frame.localV($0.0, $0.1) }
            guard let u0 = us.min(by: { $0.value < $1.value }), let u1 = us.max(by: { $0.value < $1.value }),
                  let v0 = vs.min(by: { $0.value < $1.value }), let v1 = vs.max(by: { $0.value < $1.value }) else { return nil }
            let top = PartValue(s.elevation, b["z"])
            return PartBox(x: (u0, u1), y: (v0, v1), z: (top.shifted(-FurniturePartTypes.values(of: e, m).thickness), top))
        }
        var box = Box3.empty
        for s in FurniturePartSolids.rawSolids(e, m, PartSolidContext(symbolic: false)).solids where !s.isVoid {
            for p in corners(s) { box.include(frame.local(p)) }
        }
        guard !box.isEmpty else { return nil }
        return PartBox(x: (PartValue(box.min.x), PartValue(box.max.x)), y: (PartValue(box.min.y), PartValue(box.max.y)), z: (PartValue(box.min.z), PartValue(box.max.z)))
    }

    /// The corners of an extrusion written with numbers (none for other forms).
    static func corners(_ s: FamilySolid) -> [Vec3] {
        func n(_ b: FamilyBound) -> Double? { if case .expr(let e) = b { return Double(e.trimmingCharacters(in: .whitespaces)) }; return nil }
        guard let z0 = n(s.zMin), let z1 = n(s.zMax) else { return [] }
        let plane = s.workPlane ?? .xy
        var pts: [Vec2] = []
        switch s.profile {
        case .rectangle(let a, let b, let c, let d):
            guard let x0 = n(a), let x1 = n(b), let y0 = n(c), let y1 = n(d) else { return [] }
            pts = [Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1)]
        case .polygon(let ps):
            pts = ps.compactMap { p in n(p.x).flatMap { x in n(p.y).map { Vec2(x, $0) } } }
        case .circle(let c, let r):
            guard let cx = n(c.x), let cy = n(c.y), let rr = Double(r) else { return [] }
            pts = (0..<8).map { k in Vec2(cx, cy) + Vec2.fromAngle(Double(k) * .pi / 4) * rr }
        default: return []
        }
        return pts.flatMap { [plane.point($0.x, $0.y, z0), plane.point($0.x, $0.y, z1)] }
    }

    // MARK: Moving

    /// Moves a bay's point by a model displacement (in its face: along u and up; seen from above: in plan), as Move
    /// moves a room's point. A cell moves its divided bay. Regeneration finds the opening again at the new point.
    public static func translate(_ e: inout Element, by d: Vec3) {
        guard var b = e.furnitureBay, b.parentID == nil else { return }
        if b.face == .front {
            let f = BayFrame(b)
            let l = f.local(d)
            b.seed = b.seed + Vec2(l.x, l.z)
        } else {
            b.seed = b.seed + d.xy
        }
        e.furnitureBay = b
    }

    /// Moves a separator in its face, as a bay.
    public static func translateSeparator(_ e: inout Element, by d: Vec3) {
        guard var s = e.furnitureBaySeparator else { return }
        let delta: Vec2
        if s.face == .front { let l = BayFrame(angle: s.facing ?? 0).local(d); delta = Vec2(l.x, l.z) } else { delta = d.xy }
        s.start = s.start + delta; s.end = s.end + delta
        e.furnitureBaySeparator = s
    }

    /// The bays a set of moved elements moves: a cell stands for its divided bay.
    public static func movedBays(_ ids: Set<ElementID>, _ m: BIMModel) -> Set<ElementID> {
        var out: Set<ElementID> = []
        for id in ids {
            guard let b = m[id]?.furnitureBay else { continue }
            var top = id
            var parent = b.parentID
            while let p = parent, let pb = m[p]?.furnitureBay { top = p; parent = pb.parentID }
            out.insert(top)
        }
        return out
    }

    /// Warns when two bays of the same face end up in one region (a moved bay dropped into another's), as rooms do.
    static func warnShared(_ tx: TransactionContext) {
        let tops = tx.model.elements(.furnitureBays).filter { $0.furnitureBay?.parentID == nil }
        var seen: [String: ElementID] = [:]
        for b in tops.sorted(by: { $0.id < $1.id }) {
            guard let d = b.furnitureBay, let o = d.opening else { continue }
            let key = "\(d.face.rawValue)|\(BayFrame(d).angle)|\((o.x0 * 1e4).rounded())|\((o.x1 * 1e4).rounded())|\((o.z0 * 1e4).rounded())|\((o.z1 * 1e4).rounded())|\((o.y0 * 1e4).rounded())"
            if let other = seen[key] {
                tx.warn(ModelWarning(.warning, code: "bay.sameRegion", "\(b.name) is in the same region as \(tx.model[other]?.name ?? "another bay").", elements: [b.id, other]))
            } else { seen[key] = b.id }
        }
    }
}
