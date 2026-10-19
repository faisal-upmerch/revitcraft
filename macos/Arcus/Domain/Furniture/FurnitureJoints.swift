import Foundation
import ArcusGeometry

// FM6: what joints do to the model and what other milestones read from them: each part's solids trimmed, extended and
// mitred by its joints, with tongues, tenons, grooves and mortises at Fine (FurniturePartSolids.solids calls
// `applyJoints`); cut sizes (Part List, nesting, the Cut Size parameter); hardware counts (Hardware Schedule); and the
// dependencies geometry caches need (a part's solids depend on the parts it joins, the joint elements and the rules).

public enum FurnitureJoints {
    /// Every joint of a Furniture document.
    public static func joints(_ m: BIMModel) -> [FurnitureJoint] { JointSolver.solve(m).joints }

    /// The joint between two parts, if they join.
    public static func joint(_ p: ElementID, _ q: ElementID, _ m: BIMModel) -> FurnitureJoint? { JointSolver.solve(m).joint(JointKey(p, q)) }

    /// A part's cut size: length × width × thickness (largest first), including what runs into grooves and tenons, and
    /// the trims its joints make. Parts that aren't single boxes (shaped panels, round rails, slats, forms) give their
    /// nominal size.
    public static func cutSize(of id: ElementID, in m: BIMModel) -> (length: Double, width: Double, thickness: Double)? {
        guard let e = m[id] else { return nil }
        if let env = JointSolver.solve(m).envelopes[id], JointSolver.solve(m).parts[id]?.reshapeable == true {
            let d = FamilyAxis.allCases.map { env.ext($0) }.sorted(by: >)
            return (d[0], d[1], d[2])
        }
        return FurniturePartMeshes.nominalSize(e, m)
    }

    /// "11 1/4\" x 30 1/2\"": the cut width by length (Cut Size).
    public static func cutSizeText(_ id: ElementID, _ m: BIMModel) -> String {
        guard let (l, w, _) = cutSize(of: id, in: m) else { return "" }
        return "\(FurnitureSizeText.inches(w)) x \(FurnitureSizeText.inches(l))"
    }

    /// Fasteners and shelf pins the joints use, by kind, for the Hardware Schedule.
    public static func hardwareCounts(_ m: BIMModel) -> [(kind: String, count: Int)] {
        JointSolver.solve(m).hardware.filter { $0.value > 0 }.sorted { $0.key < $1.key }.map { (kind: $0.key, count: $0.value) }
    }

    // MARK: Dependencies

    /// What a part's solids depend on beyond itself: the parts it joins and their types, its joint elements and the
    /// document's Joint Rules (project information).
    public static func inputs(of e: Element, _ m: BIMModel) -> Set<ElementID> {
        guard m.isFurniture, e.category.isFurniturePart else { return [] }
        var s: Set<ElementID> = []
        let sol = JointSolver.solve(m)
        for p in sol.partners[e.id] ?? [] { s.insert(p); if let t = m[p]?.typeID { s.insert(t) } }
        for j in m.elements(.furnitureJoints) where j.furnitureJoint?.parts.contains(e.id) == true { s.insert(j.id) }
        if let info = m.projectInfoElement { s.insert(info.id) }
        return s
    }

    /// Elements whose graphics change with `e`: a part's joint partners; a joint element's parts; every part when the
    /// Joint Rules may have changed.
    public static func affected(by e: Element, _ m: BIMModel) -> Set<ElementID> {
        guard m.isFurniture else { return [] }
        if let j = e.furnitureJoint { return Set(j.parts) }
        if e.category == .projectInfo { return Set(Category.furnitureParts.flatMap { m.elements($0) }.map(\.id)) }
        guard e.category.isFurniturePart || e.typeData?.instanceCategory.isFurniturePart == true else { return [] }
        let sol = JointSolver.solve(m)
        if e.typeData != nil {
            return Set(m.instances(ofType: e.id).flatMap { sol.partners[$0.id] ?? [] })
        }
        return sol.partners[e.id] ?? []
    }

    // MARK: Geometry

    /// The part's solids with its joints applied: the main box rebuilt with its trimmed and extended faces (a prism when
    /// mitred), and at Fine its tongues and tenons and the grooves and mortises cut in it (voids that cut only it).
    static func applyJoints(_ raw: PartSolids, _ e: Element, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        guard m.isFurniture, e.furnitureEdgeProfile == nil, e.furnitureForm == nil else { return raw }
        let sol = JointSolver.solve(m)
        guard let mods = sol.mods[e.id], !mods.isEmpty, let part = sol.parts[e.id] else { return raw }
        var out = raw
        let mains = raw.solids.indices.filter { !raw.solids[$0].isVoid }
        var hosts = mains.map { raw.solids[$0].id } + raw.placed.flatMap { $0.family.solids.map(\.id) }
        let material = mains.first.flatMap { raw.materials[raw.solids[$0].id] } ?? raw.placed.first?.material
        if mods.reshapes, part.reshapeable, mains.count == 1, let box = sol.finalBoxes[e.id] {
            let old = raw.solids[mains[0]]
            var s = mainSolid(old.name, box, mods.miters, ctx)
            s.materialParameter = old.materialParameter
            out.solids[mains[0]] = s
            out.materials[old.id] = nil
            if let material { out.materials[s.id] = material }
            hosts = [s.id] + raw.placed.flatMap { $0.family.solids.map(\.id) }
        }
        let name = mains.first.map { raw.solids[$0].name } ?? (e.mark.isEmpty ? "Part" : e.mark)
        for (k, b) in mods.fineSolids.enumerated() {
            var s = FurniturePartSolids.box("\(name) Tenon \(k + 1)", plane: .xy, u: (b.lo[0], b.hi[0]), v: (b.lo[1], b.hi[1]), w: (b.lo[2], b.hi[2]), ctx)
            s.visibleAt = [.fine]
            out.solids.append(s)
            if let material { out.materials[s.id] = material }
        }
        for (k, b) in mods.fineVoids.enumerated() {
            var s = FurniturePartSolids.box("\(name) Joint Cut \(k + 1)", plane: .xy, u: (b.lo[0], b.hi[0]), v: (b.lo[1], b.hi[1]), w: (b.lo[2], b.hi[2]), ctx, void: true)
            s.visibleAt = [.fine]
            s.cuts = hosts
            out.solids.append(s)
        }
        return out
    }

    /// The part's main solid: its final box, or the prism of its mitred rectangle.
    static func mainSolid(_ name: String, _ b: JBox, _ miters: [Miter], _ ctx: PartSolidContext) -> FamilySolid {
        guard let normal = miters.first?.normal else {
            return FurniturePartSolids.box(name, plane: .xy, u: (b.lo[0], b.hi[0]), v: (b.lo[1], b.hi[1]), w: (b.lo[2], b.hi[2]), ctx)
        }
        let plane = FamilySketchPlane.normal(normal)
        let (u, v, w) = plane.axes
        // Corners (u side, v side), counterclockwise in (u, v).
        var corners: [(Bool, Bool, PartValue, PartValue)] = [(false, false, b.lo[u.idx], b.lo[v.idx]), (true, false, b.hi[u.idx], b.lo[v.idx]),
                                                             (true, true, b.hi[u.idx], b.hi[v.idx]), (false, true, b.lo[u.idx], b.hi[v.idx])]
        for mt in miters where mt.normal == normal {
            for i in corners.indices {
                let su = corners[i].0, sv = corners[i].1
                let lSide = mt.lAxis == u ? su : sv, tSide = mt.tAxis == u ? su : sv
                guard lSide == mt.lAtMax, tSide == mt.tAtMax else { continue }
                if mt.lAxis == u { corners[i].2 = mt.to } else { corners[i].3 = mt.to }
            }
        }
        var pts = corners.map { ($0.2, $0.3) }
        let area = pts.indices.reduce(0.0) { acc, i in
            let p = pts[i], q = pts[(i + 1) % pts.count]
            return acc + p.0.value * q.1.value - q.0.value * p.1.value
        }
        if area < 0 { pts.reverse() }
        var s = FamilySolid(name: name, profile: .polygon(pts.map { ctx.point($0.0, $0.1) }), zMin: ctx.bound(b.lo[w.idx]), zMax: ctx.bound(b.hi[w.idx]))
        if plane != .xy { s.workPlane = plane }
        return s
    }
}
