import Foundation
import ArcusGeometry

/// Join Geometry between walls, floors, roofs and ceilings.
///
/// A join is a `ConstraintData(kind: .join)` element whose first reference cuts the overlapping volume out of the
/// second, so the overlap is modelled, drawn in sections and counted in quantities exactly once. The cutting order
/// follows the construction hierarchy: walls cut roofs, floors and ceilings; roofs cut floors and ceilings; floors
/// cut ceilings. The element being cut is always a slab or roof, whose solids are vertical prisms between height
/// fields, so the remaining volume is rebuilt exactly as prisms.
public enum SolidJoins {
    /// A vertical prism between two height fields over a plan profile.
    public struct Prism: Sendable {
        public var profile: Profile2
        public var bottom: PlaneZ
        public var top: PlaneZ
    }

    /// A remaining piece after cutting: height fields may be the lower or upper envelope of several planes.
    struct Piece {
        var profile: Profile2
        var bottom: [PlaneZ]   // max of these
        var top: [PlaneZ]      // min of these
        func bottomZ(_ p: Vec2) -> Double { bottom.map { $0.z(at: p) }.max() ?? 0 }
        func topZ(_ p: Vec2) -> Double { top.map { $0.z(at: p) }.min() ?? 0 }
    }

    /// Cutting priority by category; nil when the element can't take part in a solid join.
    public static func priority(_ e: Element) -> Int? {
        switch (e.category, e.data) {
        case (.walls, .wall): 3
        case (.roofs, .roof): 2
        case (.floors, .slab), (.buildingPads, .slab): 1
        case (.ceilings, .slab): 0
        default: nil
        }
    }

    /// Cutter and cut element for a pair, or nil when the pair can't be joined (same kind, or not joinable).
    public static func order(_ a: Element, _ b: Element) -> (cutter: Element, cut: Element)? {
        guard a.id != b.id, let pa = priority(a), let pb = priority(b), pa != pb else { return nil }
        return pa > pb ? (a, b) : (b, a)
    }

    // MARK: Relationships

    /// Every join in the model: (constraint element, cutter, cut).
    public static func joins(_ model: BIMModel) -> [(id: ElementID, cutter: ElementID, cut: ElementID)] {
        model.elements(.constraints).compactMap { c in
            guard let d = c.constraint, d.kind == .join, d.references.count == 2,
                  let a = d.references[0].elementID, let b = d.references[1].elementID else { return nil }
            return (c.id, a, b)
        }
    }

    public static func cutters(of e: Element, _ model: BIMModel) -> [Element] {
        joins(model).filter { $0.cut == e.id }.compactMap { model[$0.cutter] }
    }

    public static func joinID(_ a: ElementID, _ b: ElementID, _ model: BIMModel) -> ElementID? {
        joins(model).first { ($0.cutter == a && $0.cut == b) || ($0.cutter == b && $0.cut == a) }?.id
    }

    /// Elements whose derived geometry changes when `id` changes: join partners (and, for a join, both sides).
    public static func partners(of id: ElementID, _ model: BIMModel) -> [ElementID] {
        var out: [ElementID] = []
        for j in joins(model) {
            if j.id == id { out += [j.cutter, j.cut] }
            if j.cutter == id { out.append(j.cut) }
            if j.cut == id { out.append(j.cutter) }
        }
        return out
    }

    /// Cache-key inputs of a cut element: the join elements, the cutters and what their geometry depends on.
    public static func inputs(of e: Element, _ model: BIMModel) -> [ElementID] {
        var out: [ElementID] = []
        for j in joins(model) where j.cut == e.id {
            out.append(j.id)
            guard let c = model[j.cutter] else { continue }
            out.append(c.id)
            if let t = c.typeID { out.append(t) }
            if let l = c.levelID { out.append(l) }
            if let t = c.wall?.topLevelID { out.append(t) }
            for o in c.wall != nil ? WallGeometry.joinCandidates(c, model) : [] { out.append(o.id) }
        }
        return out
    }

    // MARK: Prisms

    /// The element's solid as vertical prisms (walls: footprint between base and top; slabs: profile between their
    /// planes; roofs: each roof face, or each segment of an extruded profile).
    public static func prisms(_ e: Element, _ model: BIMModel) -> [Prism] {
        switch e.data {
        case .wall:
            guard let f = WallGeometry.frame(e, model), let fp = WallGeometry.footprint(e, model) else { return [] }
            return [Prism(profile: Profile2(outer: fp.counterClockwise), bottom: .flat(f.baseZ), top: .flat(f.topZ))]
        case .slab:
            guard let p = SlabGeometry.profile(e), let (b, t) = SlabGeometry.planes(e, model) else { return [] }
            return [Prism(profile: p, bottom: b, top: t)]
        case .roof(let r):
            let t = RoofGeometry.thickness(e, model)
            if let x = r.extrusion {
                guard let top = RoofExtrusionGeometry.topLine(x) else { return [] }
                let z0 = RoofGeometry.baseZ(e, model)
                var out: [Prism] = []
                for i in 0..<(top.count - 1) {
                    let a = top[i], b = top[i + 1]
                    guard abs(b.x - a.x) > Tolerance.length else { continue }
                    let slope = (b.y - a.y) / (b.x - a.x)
                    // Top plane through the profile segment, constant along the extrusion.
                    let d = x.direction * slope
                    let pa = x.planPoint(a.x, depth: 0)
                    let topPlane = PlaneZ(a: d.x, b: d.y, c: z0 + a.y - d.dot(pa))
                    let drop = t * (1 + slope * slope).squareRoot()
                    let quad = Polygon2([x.planPoint(a.x, depth: x.start), x.planPoint(b.x, depth: x.start), x.planPoint(b.x, depth: x.end), x.planPoint(a.x, depth: x.end)])
                    out.append(Prism(profile: Profile2(outer: quad.counterClockwise), bottom: PlaneZ(a: topPlane.a, b: topPlane.b, c: topPlane.c - drop), top: topPlane))
                }
                return out
            }
            guard let s = RoofGeometry.surface(e, model) else { return [] }
            let holes = RoofGeometry.openings(e).map { Profile2(outer: $0) }
            var out: [Prism] = []
            for face in s.faces {
                guard let top = RoofGeometry.planeZ(face) else { continue }
                let xy = Polygon2(face.map(\.xy))
                guard !xy.isDegenerate else { continue }
                let pieces = holes.isEmpty ? [Profile2(outer: xy.counterClockwise)] : PolygonBoolean.difference([Profile2(outer: xy.counterClockwise)], holes)
                for p in pieces { out.append(Prism(profile: p, bottom: PlaneZ(a: top.a, b: top.b, c: top.c - t), top: top)) }
            }
            return out
        default:
            return []
        }
    }

    /// Removes the cutter prisms from the pieces.
    static func subtract(_ pieces: [Piece], _ cutters: [Prism]) -> [Piece] {
        var current = pieces
        for c in cutters {
            var next: [Piece] = []
            for p in current {
                guard p.profile.bounds.intersects(c.profile.bounds.expanded(by: Tolerance.length)) else { next.append(p); continue }
                for outside in PolygonBoolean.difference([p.profile], [c.profile]) {
                    next.append(Piece(profile: outside, bottom: p.bottom, top: p.top))
                }
                for inside in PolygonBoolean.intersection([p.profile], [c.profile]) {
                    // Part of the piece below the cutter's bottom and above the cutter's top survive.
                    next.append(Piece(profile: inside, bottom: p.bottom, top: p.top + [c.bottom]))
                    next.append(Piece(profile: inside, bottom: p.bottom + [c.top], top: p.top))
                }
            }
            current = next.filter { piece in
                piece.profile.loops.flatMap(\.points).contains { piece.topZ($0) - piece.bottomZ($0) > 1e-7 }
            }
        }
        return current
    }

    /// Closed vertical prism between two height fields (heights evaluated at the profile vertices).
    static func mesh(_ piece: Piece) -> Mesh {
        guard let prof = ShapeEditing.prepared(piece.profile) else { return .empty }
        let tri = Triangulator.triangulate(prof)
        guard !tri.triangles.isEmpty else { return .empty }
        func top(_ p: Vec2) -> Double { max(piece.topZ(p), piece.bottomZ(p)) }
        var m = Mesh()
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            let ids = [tri.triangles[t], tri.triangles[t + 1], tri.triangles[t + 2]]
            let v = ids.map { tri.points[$0].at(z: top(tri.points[$0])) }
            m.addConvexFace(v, normal: (v[1] - v[0]).cross(v[2] - v[0]).normalized, edges: false)
            let b = ids.reversed().map { tri.points[$0].at(z: piece.bottomZ(tri.points[$0])) }
            m.addConvexFace(b, normal: (b[1] - b[0]).cross(b[2] - b[0]).normalized, edges: false)
        }
        for loop in prof.loops {
            let pts = loop.points, n = pts.count
            for i in 0..<n {
                let p = pts[i], q = pts[(i + 1) % n]
                let d = (q - p).normalized
                let base = UInt32(m.positions.count)
                m.addConvexFace([p.at(z: piece.bottomZ(p)), q.at(z: piece.bottomZ(q)), q.at(z: top(q)), p.at(z: top(p))], normal: Vec3(d.y, -d.x, 0), edges: false)
                m.featureEdges += [base, base + 1, base + 3, base + 2]
                let prev = pts[(i + n - 1) % n]
                if acos(max(-1, min(1, (p - prev).normalized.dot(d)))) > .pi / 8 { m.featureEdges += [base, base + 3] }
            }
        }
        return m
    }

    /// Mesh parts of a cut element after its joins, or nil when nothing cuts it. `parts` are the element's own prisms
    /// with their materials (one per layer at fine detail).
    static func cut(_ own: [(Prism, ElementID?)], cutters: [Element], _ model: BIMModel) -> [MeshPart] {
        let cutPrisms = cutters.flatMap { prisms($0, model) }
        return own.map { prism, material in
            var mesh = Mesh()
            for piece in subtract([Piece(profile: prism.profile, bottom: [prism.bottom], top: [prism.top])], cutPrisms) { mesh.append(self.mesh(piece)) }
            return MeshPart(mesh: mesh, materialID: material)
        }
    }

    /// Slab parts with joins applied (nil when the slab isn't cut).
    public static func slabParts(_ e: Element, _ model: BIMModel, detail: DetailLevel) -> [MeshPart]? {
        let cs = cutters(of: e, model)
        guard !cs.isEmpty, let p = SlabGeometry.profile(e), let (b, t) = SlabGeometry.planes(e, model) else { return nil }
        if detail == .fine, let a = model.typeData(of: e)?.assembly, a.layers.count > 1 {
            var own: [(Prism, ElementID?)] = []
            var acc = 0.0
            for layer in a.layers where layer.thickness > Tolerance.length {
                let top = PlaneZ(a: t.a, b: t.b, c: t.c - acc)
                acc += layer.thickness
                own.append((Prism(profile: p, bottom: PlaneZ(a: t.a, b: t.b, c: t.c - acc), top: top), layer.materialID))
            }
            return cut(own, cutters: cs, model)
        }
        return cut([(Prism(profile: p, bottom: b, top: t), SlabGeometry.surfaceMaterial(e, model))], cutters: cs, model)
    }

    /// Roof parts with joins applied (nil when the roof isn't cut).
    public static func roofParts(_ e: Element, _ model: BIMModel) -> [MeshPart]? {
        let cs = cutters(of: e, model)
        guard !cs.isEmpty else { return nil }
        let mat = SlabGeometry.surfaceMaterial(e, model)
        let own = prisms(e, model).map { ($0, mat) }
        guard !own.isEmpty else { return nil }
        var mesh = Mesh()
        for part in cut(own, cutters: cs, model) { mesh.append(part.mesh) }
        return [MeshPart(mesh: mesh, materialID: mat)]
    }

    /// Volume of `e` that its cutters remove.
    public static func removedVolume(_ e: Element, _ model: BIMModel) -> Double {
        removedVolume(e, by: cutters(of: e, model), model)
    }

    /// Volume of `cut` inside `cutter` (what joining them removes from `cut`).
    public static func overlapVolume(_ cut: Element, _ cutter: Element, _ model: BIMModel) -> Double {
        removedVolume(cut, by: [cutter], model)
    }

    static func removedVolume(_ e: Element, by cs: [Element], _ model: BIMModel) -> Double {
        guard !cs.isEmpty else { return 0 }
        let own = prisms(e, model)
        let before = own.reduce(0.0) { acc, p in acc + abs(mesh(Piece(profile: p.profile, bottom: [p.bottom], top: [p.top])).signedVolume) }
        let cutPrisms = cs.flatMap { prisms($0, model) }
        let after = own.reduce(0.0) { acc, p in
            acc + subtract([Piece(profile: p.profile, bottom: [p.bottom], top: [p.top])], cutPrisms).reduce(0.0) { $0 + abs(mesh($1).signedVolume) }
        }
        return max(0, before - after)
    }

    /// Plan area of `e`'s top where a cutter passes through its full depth (a wall through a floor).
    public static func removedTopArea(_ e: Element, _ model: BIMModel) -> Double {
        let cs = cutters(of: e, model)
        guard !cs.isEmpty else { return 0 }
        var area = 0.0
        for p in prisms(e, model) {
            for c in cs.flatMap({ prisms($0, model) }) {
                for inside in PolygonBoolean.intersection([p.profile], [c.profile]) {
                    let m = inside.outer.centroid
                    if c.bottom.z(at: m) <= p.bottom.z(at: m) + 1e-6 && c.top.z(at: m) >= p.top.z(at: m) - 1e-6 { area += inside.area }
                }
            }
        }
        return area
    }

    // MARK: Editing

    /// Overlapping pairs among the given elements that can be joined and aren't joined yet, as (cutter, cut).
    public static func joinablePairs(_ ids: [ElementID], _ model: BIMModel) -> [(cutter: ElementID, cut: ElementID)] {
        let els = ids.compactMap { model[$0] }.filter { priority($0) != nil }
        var out: [(ElementID, ElementID)] = []
        for i in 0..<els.count {
            for j in (i + 1)..<max(i + 1, els.count) {
                guard let (cutter, cut) = order(els[i], els[j]), joinID(cutter.id, cut.id, model) == nil,
                      overlapVolume(cut, cutter, model) > 1e-9 else { continue }
                out.append((cutter.id, cut.id))
            }
        }
        return out.map { (cutter: $0.0, cut: $0.1) }
    }

    /// Creates joins between every overlapping pair of the given elements that isn't joined yet. Returns the number
    /// of joins created.
    @discardableResult
    public static func join(_ ids: [ElementID], in tx: TransactionContext) -> Int {
        let pairs = joinablePairs(ids, tx.model)
        for p in pairs {
            tx.create(.constraints, data: .constraint(ConstraintData(kind: .join, references: [GeometryReference(p.cutter, .location), GeometryReference(p.cut, .location)])))
        }
        return pairs.count
    }

    /// Removes joins between the given elements (with one element, every join it takes part in). Returns the count.
    @discardableResult
    public static func unjoin(_ ids: [ElementID], in tx: TransactionContext) -> Int {
        let set = Set(ids)
        let list = joins(tx.model).filter { set.count == 1 ? (set.contains($0.cutter) || set.contains($0.cut)) : (set.contains($0.cutter) && set.contains($0.cut)) }
        for j in list { tx.delete(j.id) }
        return list.count
    }

    /// Subtracts the joined overlap from an element's quantities: volume (and material volumes proportionally) and
    /// the top area where a cutter passes through the full depth.
    public static func applyToQuantities(_ q: inout ElementQuantities, _ e: Element, _ model: BIMModel) {
        let removed = removedVolume(e, model)
        guard removed > 1e-12, let v = q.volume, v > 0 else { return }
        let ratio = max(0, v - removed) / v
        q.volume = max(0, v - removed)
        let areaRemoved = removedTopArea(e, model)
        if let a = q.area { q.area = max(0, a - areaRemoved) }
        q.materials = q.materials.map { MaterialQuantity(materialID: $0.materialID, area: max(0, $0.area - areaRemoved), volume: $0.volume * ratio) }
    }
}
