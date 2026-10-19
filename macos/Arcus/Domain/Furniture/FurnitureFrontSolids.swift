import Foundation
import ArcusGeometry

// FM5: fronts as family solids, written once for both uses as FM4 does for parts: with numbers for the display
// (evaluated by `FamilyEvaluator` into meshes) and bound to planes when compiling (Load into Project), so a loaded
// cabinet's doors and drawers resize when it flexes. Slab fronts are one board (with the type's edge profile cut round
// their face); Shaker fronts are a 5-piece frame (two stiles, two rails) round a recessed panel; Glass Panel fronts
// frame a glass pane; Louvered fronts fill the frame with angled slats. Drawers add their box (sides, front, back and
// bottom) behind the front.

public enum FurnitureFrontSolids {
    static let inch = 0.0254
    /// How far a panel or glass enters the frame's grooves (cut list sizes).
    public static let grooveDepth = 0.375 * inch

    /// A front's solids: leaves, frame pieces, panels, the drawer box; materials per solid id.
    public static func solids(_ e: Element, _ m: BIMModel, _ ctx: PartSolidContext, boxDetail: Set<DetailLevel> = [.medium, .fine],
                              frontDetail: Set<DetailLevel> = [.medium, .fine]) -> PartSolids {
        var out = PartSolids()
        guard let g = FurnitureFronts.geometry(e, m) else { return out }
        let tv = FurnitureFrontTypes.values(of: e, m)
        let base = e.mark.isEmpty ? g.kind.rawValue : e.mark
        for (li, leaf) in g.leaves.enumerated() {
            let name = g.leaves.count > 1 ? "\(base) Leaf \(li + 1)" : base
            let style: FrontStyle = g.face == .front ? tv.style : .slab
            if style == .slab || leaf.width < 3 * tv.stileWidth || leaf.height < 3 * tv.railWidth {
                let s = leafBox(name, leaf, g, ctx)
                out.solids.append(s); out.materials[s.id] = tv.material
                if let shape = tv.edgeProfile, g.face == .front, let host = partBox(leaf) {
                    let size = min(tv.thickness * 0.4, 0.25 * inch)
                    for edge in [PartEdge(axis: .x, firstAtMax: false, secondAtMax: false), PartEdge(axis: .x, firstAtMax: false, secondAtMax: true),
                                 PartEdge(axis: .z, firstAtMax: false, secondAtMax: false), PartEdge(axis: .z, firstAtMax: true, secondAtMax: false)] {
                        if let v = FurniturePartSolids.edgeVoid(name: "\(name) Edge", host: host, edge: edge, shape: shape, size: size, depth: 0, offset: 0,
                                                                inSecondFace: false, ctx: ctx) { out.placed.append(v) }
                    }
                }
                continue
            }
            // A simple leaf for Coarse; the frame and panel at Medium and Fine.
            var coarse = leafBox(name, leaf, g, ctx)
            coarse.visibleAt = Set<DetailLevel>([.coarse]).union(frontDetail.subtracting([.medium, .fine]))
            out.solids.append(coarse); out.materials[coarse.id] = tv.material
            frame(name, leaf, g, tv, style, ctx, detail: frontDetail, into: &out)
        }
        if g.kind == .drawer, let box = FurnitureFronts.drawerBox(e, m) {
            for var s in drawerBoxSolids(base, box, ctx) {
                s.visibleAt = boxDetail
                out.solids.append(s)
                out.materials[s.id] = s.name.hasSuffix("Bottom") ? (tv.bottomMaterial ?? tv.boxMaterial) : tv.boxMaterial
            }
        }
        return out
    }

    /// The leaf as one board.
    static func leafBox(_ name: String, _ l: FrontLeaf, _ g: FrontGeometry, _ ctx: PartSolidContext) -> FamilySolid {
        g.face == .front ? FurniturePartSolids.box(name, plane: .xy, u: l.u, v: l.w, w: l.v, ctx)
                         : FurniturePartSolids.box(name, plane: .xy, u: l.u, v: l.v, w: l.w, ctx)
    }

    /// The leaf's box as a part box (front leaves), for edge profiles.
    static func partBox(_ l: FrontLeaf) -> FurniturePartSolids.PartBox? {
        FurniturePartSolids.PartBox(x: l.u, y: l.w, z: l.v)
    }

    /// Stiles, rails and the panel (or glass, or louvers) of a framed leaf seen from the front.
    static func frame(_ name: String, _ l: FrontLeaf, _ g: FrontGeometry, _ tv: FurnitureFrontTypes.Values, _ style: FrontStyle, _ ctx: PartSolidContext,
                      detail: Set<DetailLevel>, into out: inout PartSolids) {
        let S = tv.stileWidth, R = tv.railWidth
        let (u0, u1, v0, v1) = (l.u.0, l.u.1, l.v.0, l.v.1)
        let w = l.w
        func add(_ s: FamilySolid, _ mat: ElementID?) { var s = s; s.visibleAt = detail; out.solids.append(s); out.materials[s.id] = mat }
        add(FurniturePartSolids.box("\(name) Left Stile", plane: .xy, u: (u0, u0.shifted(S)), v: w, w: (v0, v1), ctx), tv.material)
        add(FurniturePartSolids.box("\(name) Right Stile", plane: .xy, u: (u1.shifted(-S), u1), v: w, w: (v0, v1), ctx), tv.material)
        add(FurniturePartSolids.box("\(name) Bottom Rail", plane: .xy, u: (u0.shifted(S), u1.shifted(-S)), v: w, w: (v0, v0.shifted(R)), ctx), tv.material)
        add(FurniturePartSolids.box("\(name) Top Rail", plane: .xy, u: (u0.shifted(S), u1.shifted(-S)), v: w, w: (v1.shifted(-R), v1), ctx), tv.material)
        let pu = (u0.shifted(S), u1.shifted(-S)), pv = (v0.shifted(R), v1.shifted(-R))
        switch style {
        case .shaker, .slab:
            // The panel, recessed from the frame's face.
            let face = w.0.shifted(tv.panelRecess)
            add(FurniturePartSolids.box("\(name) Panel", plane: .xy, u: pu, v: (face, face.shifted(tv.panelThickness)), w: pv, ctx), tv.panelMaterial)
        case .glass:
            let c = FurnitureFronts.mid(w.0, w.1)
            add(FurniturePartSolids.box("\(name) Glass", plane: .xy, u: pu, v: (c.shifted(-tv.panelThickness / 2), c.shifted(tv.panelThickness / 2)), w: pv, ctx), tv.panelMaterial)
        case .louvered:
            // Slats at 45° across the frame's thickness, one per pitch.
            let h = pv.1.value - pv.0.value
            let n = max(1, Int((h / tv.louverPitch).rounded(.down)))
            let pitch = h / Double(n)
            let yc = (w.0.value + w.1.value) / 2, half = min(tv.thickness, pitch) * 0.55, thick = 0.125 * inch
            let d = Vec2(cos(.pi / 4), -sin(.pi / 4)), nrm = d.perpendicular
            for k in 0..<n {
                let zc = pv.0.value + pitch * (Double(k) + 0.5)
                let c = Vec2(yc, zc)
                let pts = [c - d * half - nrm * thick / 2, c + d * half - nrm * thick / 2, c + d * half + nrm * thick / 2, c - d * half + nrm * thick / 2]
                add(FurniturePartSolids.prism("\(name) Louver \(k + 1)", plane: .yz, pts, w: pu, ctx), tv.material)
            }
        }
    }

    /// The drawer box: two sides, a front and a back between them, and the bottom.
    static func drawerBoxSolids(_ name: String, _ b: DrawerBox, _ ctx: PartSolidContext) -> [FamilySolid] {
        func box(_ n: String, _ x0: Double, _ x1: Double, _ y0: Double, _ y1: Double, _ z0: Double, _ z1: Double) -> FamilySolid {
            FurniturePartSolids.box("\(name) \(n)", plane: .xy, u: (PartValue(x0), PartValue(x1)), v: (PartValue(y0), PartValue(y1)), w: (PartValue(z0), PartValue(z1)), ctx)
        }
        let x0 = b.x0, x1 = b.x0 + b.width, y0 = b.y0, y1 = b.y0 + b.depth, z0 = b.z0, z1 = b.z0 + b.height
        let up = 0.5 * inch
        return [box("Box Left Side", x0, x0 + b.side, y0, y1, z0, z1), box("Box Right Side", x1 - b.side, x1, y0, y1, z0, z1),
                box("Box Front", x0 + b.side, x1 - b.side, y0, y0 + b.back, z0, z1), box("Box Back", x0 + b.side, x1 - b.side, y1 - b.back, y1, z0, z1),
                box("Box Bottom", x0 + b.side, x1 - b.side, y0 + b.back, y1 - b.back, z0 + up, z0 + up + b.bottom)]
    }

    // MARK: Display

    /// The front as a family to evaluate, with materials per solid.
    static func displayFamily(_ e: Element, _ m: BIMModel) -> (FamilyDefinition, [String: ElementID]) {
        let parts = solids(e, m, PartSolidContext(symbolic: false), frontDetail: [.medium, .fine])
        var f = FamilyDefinition(name: "Front \(e.id.raw)", template: .genericModel)
        f.types = [FamilyTypeDefinition(name: "Front", values: [:])]
        f.solids = parts.solids
        for (k, p) in parts.placed.enumerated() {
            var nf = p.family
            nf.name = "Local \(k) \(nf.name)"
            if let span = p.span, nf.parameter(named: "Length") != nil {
                nf.types = nf.types.map { var t = $0; t.values["Length"] = .double(max(Tolerance.length * 2, span.end.value - span.start.value)); return t }
            }
            f.nestedFamilies.append(nf)
            f.nestedInstances.append(NestedFamilyInstance(familyName: nf.name, typeName: nf.types.first?.name, x: .expr(PartSolidContext.number(p.x.value)),
                                                          y: .expr(PartSolidContext.number(p.y.value)), z: .expr(PartSolidContext.number(p.z.value)),
                                                          rotation: PartSolidContext.number(p.rotation), mirrored: p.mirrored))
        }
        return (f, parts.materials)
    }

    /// The front's 3D representation at a detail level.
    public static func meshParts(_ e: Element, _ m: BIMModel, detail: DetailLevel) -> [MeshPart] {
        let (f, mats) = displayFamily(e, m)
        guard !f.solids.isEmpty else { return [] }
        let ev = FamilyEvaluator.evaluate(f, typeName: "Front", units: m.units)
        let tv = FurnitureFrontTypes.values(of: e, m)
        let face = tv.faceMaterial.flatMap { m[$0]?.material }
        return ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(detail) }.map { s in
            let mat = s.resolvedMaterial ?? s.sourceID.flatMap { mats[$0] } ?? tv.material
            var part = MeshPart(mesh: s.familyMesh, materialID: mat)
            if let face, mat == tv.material { part.color = RGBColor(face.color.r, face.color.g, face.color.b, 1 - face.transparency) }
            return part
        }
    }

    /// Elements a front's geometry depends on besides itself and its type: its bay (and the bay's bay), the materials
    /// and hardware types its type names, and the slide family's lengths.
    public static func inputs(of e: Element, _ m: BIMModel) -> Set<ElementID> {
        var s: Set<ElementID> = []
        var host = e.hostID
        while let h = host, let b = m[h] { s.insert(h); host = b.furnitureBay?.parentID }
        if let td = m.typeData(of: e) { for v in td.params.values { if let r = v.refValue { s.insert(r) } } }
        let tv = FurnitureFrontTypes.values(of: e, m)
        if let st = tv.slideType, let fam = m[st]?.typeData?.familyName {
            for t in m.types(for: .furnitureHardware) where t.typeData?.familyName == fam { s.insert(t.id) }
        }
        return s
    }

    /// Size and quantities: the leaves' width × height × thickness, their area, the volume of everything.
    static func quantities(_ e: Element, _ m: BIMModel, _ q: inout ElementQuantities) {
        guard let g = FurnitureFronts.geometry(e, m) else { return }
        let w = g.leaves.map(\.width).reduce(0, +), h = g.leaves.map(\.height).max() ?? 0
        q.width = w; q.height = h; q.length = h; q.thickness = g.thickness
        q.area = g.leaves.reduce(0) { $0 + $1.width * $1.height }
        let parts = meshParts(e, m, detail: .fine)
        let vol = parts.reduce(0) { $0 + abs($1.mesh.signedVolume) }
        if vol > 0 { q.volume = vol }
        q.materials = [MaterialQuantity(materialID: FurnitureFrontTypes.values(of: e, m).material, area: q.area ?? 0, volume: vol)]
    }

    /// "15 3/8\" x 29 7/8\"": a front's width by height (for one leaf of a pair, the leaf's).
    public static func sizeText(_ e: Element, _ m: BIMModel) -> String {
        guard let g = FurnitureFronts.geometry(e, m), let l = g.leaves.first else { return "" }
        return "\(FurnitureSizeText.inches(l.width)) x \(FurnitureSizeText.inches(l.height))"
    }
}
