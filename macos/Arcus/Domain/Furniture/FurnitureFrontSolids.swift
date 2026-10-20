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
        // FMG3: a front on another face is written in its bay's frame and turned into the model as it's written.
        let savedFrame = ctx.frame, savedAnchors = ctx.cantAnchors
        ctx.frame = g.frame.isIdentity ? nil : g.frame
        ctx.cantAnchors = ctx.symbolic ? CantAnchors(g.opening, g.frame) : nil
        defer { ctx.frame = savedFrame; ctx.cantAnchors = savedAnchors }
        for (li, leaf) in g.leaves.enumerated() {
            let name = g.leaves.count > 1 ? "\(base) Leaf \(li + 1)" : base
            let style = lidStyle(tv.style, g.face) // FMG3: lids take the Shaker and framed styles too
            if style == .slab || leaf.width < 3 * tv.stileWidth || leaf.height < 3 * tv.railWidth {
                let s = leafBox(name, leaf, g, ctx)
                out.solids.append(s); out.materials[s.id] = tv.material
                if let shape = tv.edgeProfile, g.face == .front, let host = partBox(leaf) {
                    let size = min(tv.thickness * 0.4, 0.25 * inch)
                    for edge in [PartEdge(axis: .x, firstAtMax: false, secondAtMax: false), PartEdge(axis: .x, firstAtMax: false, secondAtMax: true),
                                 PartEdge(axis: .z, firstAtMax: false, secondAtMax: false), PartEdge(axis: .z, firstAtMax: true, secondAtMax: false)] {
                        if let v = FurniturePartSolids.edgeVoid(name: "\(name) Edge", host: host, edge: edge, shape: shape, size: size, depth: 0, offset: 0,
                                                                inSecondFace: false, ctx: ctx) { out.placed.append(g.frame.placed(v, anchors: ctx.cantAnchors, spanAlongU: edge.axis == .x)) } // FMG3; FMG4: canted
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
            for var s in drawerBoxSolids(base, box, opening: g.opening, ctx) { // FM8: on the bay's planes
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

    /// FMG3: the style a front is built in: lids (seen from above) take Slab, Shaker and Glass Panel; a louvered lid is
    /// framed with a panel.
    public static func lidStyle(_ style: FrontStyle, _ face: BayFace) -> FrontStyle { face == .front || style != .louvered ? style : .shaker }

    /// Stiles, rails and the panel (or glass, or louvers) of a framed leaf seen from the front (FMG3: or a lid's, seen
    /// from above: stiles along its depth, the panel recessed from its top).
    static func frame(_ name: String, _ l: FrontLeaf, _ g: FrontGeometry, _ tv: FurnitureFrontTypes.Values, _ style: FrontStyle, _ ctx: PartSolidContext,
                      detail: Set<DetailLevel>, into out: inout PartSolids) {
        let S = tv.stileWidth, R = tv.railWidth
        let (u0, u1, v0, v1) = (l.u.0, l.u.1, l.v.0, l.v.1)
        let w = l.w
        let lid = g.face == .top
        func add(_ s: FamilySolid, _ mat: ElementID?) { var s = s; s.visibleAt = detail; out.solids.append(s); out.materials[s.id] = mat }
        // A piece across the leaf: u along its width, v along its height (a lid's depth), t through its thickness.
        func piece(_ n: String, _ u: (PartValue, PartValue), _ v: (PartValue, PartValue), _ t: (PartValue, PartValue)) -> FamilySolid {
            lid ? FurniturePartSolids.box(n, plane: .xy, u: u, v: v, w: t, ctx) : FurniturePartSolids.box(n, plane: .xy, u: u, v: t, w: v, ctx)
        }
        add(piece("\(name) Left Stile", (u0, u0.shifted(S)), (v0, v1), w), tv.material)
        add(piece("\(name) Right Stile", (u1.shifted(-S), u1), (v0, v1), w), tv.material)
        add(piece("\(name) Bottom Rail", (u0.shifted(S), u1.shifted(-S)), (v0, v0.shifted(R)), w), tv.material)
        add(piece("\(name) Top Rail", (u0.shifted(S), u1.shifted(-S)), (v1.shifted(-R), v1), w), tv.material)
        let pu = (u0.shifted(S), u1.shifted(-S)), pv = (v0.shifted(R), v1.shifted(-R))
        switch style {
        case .shaker, .slab:
            // The panel, recessed from the frame's face (a lid's top).
            let face = lid ? w.1.shifted(-tv.panelRecess) : w.0.shifted(tv.panelRecess)
            let t = lid ? (face.shifted(-tv.panelThickness), face) : (face, face.shifted(tv.panelThickness))
            add(piece("\(name) Panel", pu, pv, t), tv.panelMaterial)
        case .glass:
            let c = FurnitureFronts.mid(w.0, w.1)
            add(piece("\(name) Glass", pu, pv, (c.shifted(-tv.panelThickness / 2), c.shifted(tv.panelThickness / 2))), tv.panelMaterial)
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
                if let fr = ctx.frame, !fr.isSquare { // FMG4: louvers on a canted face keep their tilt
                    out.placed.append(fr.louver("\(name) Louver \(k + 1)", pts, u: pu, ctx, material: tv.material))
                    continue
                }
                add(FurniturePartSolids.prism("\(name) Louver \(k + 1)", plane: .yz, pts, w: pu, ctx), tv.material)
            }
        }
    }

    /// The drawer box: two sides, a front and a back between them, and the bottom.
    /// FM8: each face follows the bay's plane at its clearance from it (width and height follow the bay; the depth is
    /// the slide's stock length, from the bay's front), so a compiled cabinet's boxes flex with their drawers.
    static func drawerBoxSolids(_ name: String, _ b: DrawerBox, opening o: BayOpening, _ ctx: PartSolidContext) -> [FamilySolid] {
        func box(_ n: String, _ x: (PartValue, PartValue), _ y: (PartValue, PartValue), _ z: (PartValue, PartValue)) -> FamilySolid {
            FurniturePartSolids.box("\(name) \(n)", plane: .xy, u: x, v: y, w: z, ctx)
        }
        let x0 = o.value("x0").shifted(b.x0 - o.x0), x1 = o.value("x1").shifted(b.x0 + b.width - o.x1)
        let y0 = o.value("y0").shifted(b.y0 - o.y0), y1 = y0.shifted(b.depth)
        let z0 = o.value("z0").shifted(b.z0 - o.z0), z1 = o.value("z1").shifted(b.z0 + b.height - o.z1)
        let up = 0.5 * inch
        let inner = (x0.shifted(b.side), x1.shifted(-b.side))
        return [box("Box Left Side", (x0, x0.shifted(b.side)), (y0, y1), (z0, z1)), box("Box Right Side", (x1.shifted(-b.side), x1), (y0, y1), (z0, z1)),
                box("Box Front", inner, (y0, y0.shifted(b.back)), (z0, z1)), box("Box Back", inner, (y1.shifted(-b.back), y1), (z0, z1)),
                box("Box Bottom", inner, (y0.shifted(b.back), y1.shifted(-b.back)), (z0.shifted(up), z0.shifted(up + b.bottom)))]
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
        let ev = FamilyEvaluator.evaluate(f, typeName: "Front", units: m.units, quality: detail.tessellation) // VIS: curves by detail level
        let tv = FurnitureFrontTypes.values(of: e, m)
        let face = tv.faceMaterial.flatMap { m[$0]?.material }
        return ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(detail) }.map { s in
            let mat = s.resolvedMaterial ?? s.sourceID.flatMap { mats[$0] } ?? tv.material
            var part = MeshPart(mesh: s.displayMesh, materialID: mat)
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
        if e.furnitureFront?.leafCountParameter != nil, let info = m.projectInfoElement { s.insert(info.id) } // FMG3: Leaf Count by type
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
