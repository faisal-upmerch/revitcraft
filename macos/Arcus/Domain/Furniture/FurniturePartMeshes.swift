import Foundation
import ArcusGeometry

// FM4: 3D geometry and quantities of furniture parts. A part is evaluated as a small family made of its own solids,
// the voids of the edge profiles and grooves it hosts and the void forms that reach it, by `FamilyEvaluator`, the
// same code that evaluates loaded families, so what the document shows is what Load into Project produces.

public enum FurniturePartMeshes {
    /// The part as a family to evaluate, with the material of each of its solids.
    static func displayFamily(_ e: Element, _ m: BIMModel, voids extra: [FamilySolid] = [], detail: DetailLevel? = nil) -> (FamilyDefinition, [String: ElementID]) {
        let ctx = PartSolidContext(symbolic: false)
        var parts = FurniturePartSolids.solids(e, m, ctx)
        if e.furnitureEdgeProfile == nil, e.furnitureForm?.isVoid != true {
            for h in m.hosted(by: e.id) where h.furnitureEdgeProfile != nil { parts.placed += FurniturePartSolids.solids(h, m, ctx).placed }
        }
        var f = FamilyDefinition(name: "Part \(e.id.raw)", template: .genericModel)
        f.types = [FamilyTypeDefinition(name: "Part", values: [:])]
        f.solids = parts.solids + extra
        if let detail { f.solids = f.solids.filter { $0.visibleAt.contains(detail) } } // FM6: joint cuts and tenons only at Fine
        for (k, p) in parts.placed.enumerated() {
            var nf = p.family
            nf.name = "Local \(k) \(nf.name)"
            if let span = p.span, nf.parameter(named: "Height") != nil || nf.parameter(named: "Length") != nil {
                let key = nf.parameter(named: "Height") != nil ? "Height" : "Length"
                nf.types = nf.types.map { var t = $0; t.values[key] = .double(max(Tolerance.length * 2, span.end.value - span.start.value)); return t }
            }
            if let mat = p.material, nf.parameter(named: "Material") != nil { nf.types = nf.types.map { var t = $0; t.values["Material"] = .ref(mat); return t } }
            f.nestedFamilies.append(nf)
            f.nestedInstances.append(NestedFamilyInstance(familyName: nf.name, typeName: nf.types.first?.name, x: .expr(PartSolidContext.number(p.x.value)),
                                                          y: .expr(PartSolidContext.number(p.y.value)), z: .expr(PartSolidContext.number(p.z.value)),
                                                          rotation: PartSolidContext.number(p.rotation), mirrored: p.mirrored))
        }
        return (f, parts.materials)
    }

    /// The part evaluated, with its materials per solid id.
    public static func evaluated(_ e: Element, _ m: BIMModel, detail: DetailLevel? = nil) -> (EvaluatedFamily, [String: ElementID])? {
        guard e.category.isFurniturePart else { return nil }
        var (f, mats) = displayFamily(e, m, detail: detail)
        guard !f.solids.isEmpty || !f.nestedInstances.isEmpty else { return nil }
        var ev = FamilyEvaluator.evaluate(f, typeName: "Part", units: m.units)
        // Void forms cut the parts they reach, as voids cut solids in a family.
        if e.furnitureForm == nil, e.furnitureEdgeProfile == nil {
            let b = ev.bounds
            let voids = voidForms(m).filter { $0.1.intersects(b) }.flatMap(\.0)
            if !voids.isEmpty {
                (f, mats) = displayFamily(e, m, voids: voids, detail: detail)
                ev = FamilyEvaluator.evaluate(f, typeName: "Part", units: m.units)
            }
        }
        return (ev, mats)
    }

    /// The model's void forms as solids, with their bounds.
    static func voidForms(_ m: BIMModel) -> [([FamilySolid], Box3)] {
        m.elements(.furnitureForms).compactMap { v in
            guard let f = v.furnitureForm, f.isVoid else { return nil }
            let s = FurnitureForms.solids(v, f, m, PartSolidContext(symbolic: false)).solids.map { var x = $0; x.isVoid = true; return x }
            var fam = FamilyDefinition(name: "Void", template: .genericModel)
            fam.types = [FamilyTypeDefinition(name: "Void", values: [:])]
            fam.solids = s.map { var x = $0; x.isVoid = false; return x }
            let b = FamilyEvaluator.evaluate(fam, typeName: "Void", units: m.units).bounds
            return b.isEmpty ? nil : (s, b)
        }
    }

    /// The part's 3D representation: one mesh part per solid, with its material (faces coloured by a face material).
    public static func meshParts(_ e: Element, _ m: BIMModel, detail: DetailLevel) -> [MeshPart] {
        guard let (ev, mats) = evaluated(e, m, detail: detail) else { return [] }
        let tv = FurniturePartTypes.values(of: e, m)
        let face = tv.faceMaterial.flatMap { m[$0]?.material }
        return ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(detail) }.map { s in
            let mat = s.resolvedMaterial ?? s.sourceID.flatMap { mats[$0] } ?? tv.material
            var part = MeshPart(mesh: s.familyMesh, materialID: mat)
            if let face { part.color = RGBColor(face.color.r, face.color.g, face.color.b, 1 - face.transparency) }
            return part
        }
    }

    /// Elements a part's geometry depends on beyond itself and its type: the edge profiles it hosts and their types,
    /// and the void forms.
    public static func inputs(of e: Element, _ m: BIMModel) -> Set<ElementID> {
        var s: Set<ElementID> = []
        if let h = e.hostID { s.insert(h); if let t = m[h]?.typeID { s.insert(t) } }
        for h in m.hosted(by: e.id) where h.furnitureEdgeProfile != nil { s.insert(h.id); if let t = h.typeID { s.insert(t) } }
        for v in m.elements(.furnitureForms) where v.furnitureForm?.isVoid == true { s.insert(v.id) }
        let tv = FurniturePartTypes.values(of: e, m)
        for id in [tv.coreMaterial, tv.faceMaterial].compactMap({ $0 }) { s.insert(id) }
        s.formUnion(FurnitureJoints.inputs(of: e, m)) // FM6: the parts it joins, its joints and the Joint Rules
        s.formUnion(FurnitureFormLocks.inputs(of: e, m)) // FM9: the planes a locked form follows
        return s
    }

    // MARK: Quantities

    /// Nominal size (length × width × thickness, before joints), area and volume. Cut sizes come with joints (FM7).
    public static func nominalSize(_ e: Element, _ m: BIMModel) -> (length: Double, width: Double, thickness: Double)? {
        let tv = FurniturePartTypes.values(of: e, m)
        switch e.data {
        case .furniturePanel(let p):
            let a = p.length, b = p.height
            return (max(a, b), min(a, b), tv.thickness)
        case .furnitureShelf(let s):
            guard s.boundary.count >= 3 else { return nil }
            let ang = spanAngle(s)
            let d = Vec2.fromAngle(ang), n = d.perpendicular
            let us = s.boundary.map { $0.dot(d) }, vs = s.boundary.map { $0.dot(n) }
            let l = (us.max() ?? 0) - (us.min() ?? 0), w = (vs.max() ?? 0) - (vs.min() ?? 0)
            return (max(l, w), min(l, w), tv.thickness)
        case .furnitureLeg(let l):
            return (l.height, max(tv.width, tv.depth), min(tv.width, tv.depth))
        case .furnitureRail(let r):
            return (r.length, max(tv.width, tv.depth), min(tv.width, tv.depth))
        case .furnitureEdgeProfile(let ep):
            guard let host = m[e.hostID], let b = FurniturePartSolids.partBox(host, m)?.box else { return nil }
            let len: Double = switch ep.edge.axis { case .x: b.max.x - b.min.x; case .y: b.max.y - b.min.y; case .z: b.max.z - b.min.z }
            return (len - ep.startSetback - ep.endSetback, tv.size, tv.profileShape == .groove ? tv.grooveDepth : tv.size)
        case .furnitureForm:
            guard let (ev, _) = evaluated(e, m) else { return nil }
            let b = ev.bounds
            guard !b.isEmpty else { return nil }
            let dims = [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z].sorted(by: >)
            return (dims[0], dims[1], dims[2])
        default:
            return nil
        }
    }

    /// The shelf's grain/span direction: its own, or along its longest edge.
    public static func spanAngle(_ s: ShelfData) -> Double {
        if let a = s.spanAngle { return a }
        let edges = Polygon2(s.boundary).edges
        return edges.max { $0.length < $1.length }?.direction.angle ?? 0
    }

    /// Number of pieces a part is (slats count each slat).
    public static func count(_ e: Element) -> Int { e.furnitureRail?.slats?.offsets.count ?? 1 }

    static func quantities(_ e: Element, _ m: BIMModel, _ q: inout ElementQuantities) {
        if let (l, w, t) = nominalSize(e, m) {
            q.length = l; q.width = w; q.thickness = t
            q.area = l * w * Double(count(e))
        }
        if case .furnitureShelf(let s) = e.data { q.area = Polygon2(s.boundary).area; q.perimeter = Polygon2(s.boundary).perimeter }
        let parts = meshParts(e, m, detail: .fine)
        let vol = parts.reduce(0) { $0 + abs($1.mesh.signedVolume) }
        if vol > 0 { q.volume = vol }
        let bb = parts.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        if !bb.isEmpty { q.elevationBottom = bb.min.z; q.elevationTop = bb.max.z; q.height = bb.max.z - bb.min.z }
        q.materials = [MaterialQuantity(materialID: FurniturePartTypes.values(of: e, m).material, area: q.area ?? 0, volume: vol)]
    }

    /// "11 1/4\" x 30\"": width by length (the Part Tag's Size).
    public static func sizeText(_ e: Element, _ m: BIMModel) -> String {
        guard let (l, w, _) = nominalSize(e, m) else { return "" }
        let f = { (v: Double) in FurnitureSizeText.inches(v) }
        return "\(f(w)) x \(f(l))"
    }
}

/// Feet-and-inches text for part sizes (fractional inches to 1/16", as shop drawings write them).
public enum FurnitureSizeText {
    public static func inches(_ v: Double) -> String {
        let total = (v / 0.0254 * 16).rounded() / 16
        let whole = Int(total.rounded(.towardZero))
        let frac = Int(((total - Double(whole)) * 16).rounded())
        func reduce(_ n: Int, _ d: Int) -> String {
            var a = n, b = d
            while a % 2 == 0 && b > 1 { a /= 2; b /= 2 }
            return "\(a)/\(b)"
        }
        if frac == 0 { return "\(whole)\"" }
        return whole == 0 ? "\(reduce(frac, 16))\"" : "\(whole) \(reduce(frac, 16))\""
    }
}
