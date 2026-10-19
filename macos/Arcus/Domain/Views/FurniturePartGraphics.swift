import Foundation
import ArcusGeometry

// FM4: 2D graphics of furniture parts, drawn as casework shop drawings read: in plans the parts the cut plane passes
// through are cut (heavy outline, the material's cut pattern) and the rest of the view range is seen in projection;
// elevations and sections (VerticalGraphics) add the dashed hidden lines at Medium and Fine, the grain arrow on panel
// faces seen square on, and edge profiles and grooves as selectable lines along their edge.

extension ViewGraphicsBuilder {
    /// Part graphics for this view (plans: all of them; elevations and sections: hidden lines, grain, edge profiles).
    func furniturePartGraphics() -> [GItem] {
        guard Category.furnitureParts.contains(where: { !model.elements($0).isEmpty }) else { return [] }
        let parts = visibleModelElements().filter { $0.0.category.isFurniturePart }
        guard !parts.isEmpty else { return [] }
        if data.kind.isPlan { return partPlanItems(parts + fm5PlanParts()) } // FM5: fronts and hardware are cut and seen with the parts
        if data.kind.isVerticalCut, let fr = VerticalGraphics.frame(data) { return partVerticalItems(parts, fr) }
        return []
    }

    func partMesh(_ e: Element) -> Mesh {
        var mesh = Mesh()
        for p in GeometryCache.shared.parts(e, model, detail: detailLevel(e.category)) { mesh.append(p.mesh) }
        return mesh
    }

    func partMaterial(_ e: Element) -> ElementID? {
        if let f = e.furnitureForm { return f.materialID }
        return FurniturePartTypes.values(of: e, model).material
    }

    /// The thin stroke of grain arrows and other symbols.
    func symbolStroke(_ e: Element, _ o: GraphicOverride) -> GStroke {
        var st = stroke(e.category, cut: false, o)
        st.weight = 1
        return st
    }

    // MARK: Plans

    func partPlanItems(_ parts: [(Element, GraphicOverride)]) -> [GItem] {
        let levelZ = model.elevation(ofLevel: view.levelID)
        let cutZ = levelZ + data.viewRange.cutOffset
        let depthZ = data.viewRange.z(.depth, viewLevel: view.levelID, in: model)
        let cutPlane = Plane3.horizontal(z: cutZ)
        var items: [GItem] = []
        var inputs: [HLRInput] = []
        var map: [Int: (Element, GraphicOverride, Rect2)] = [:]
        for (i, (e, o)) in parts.enumerated() {
            if isCancelled() { return items }
            if e.furnitureEdgeProfile != nil { if let it = edgeProfileItem(e, o, project: { ($0.xy, -$0.z) }) { items.append(it) }; continue }
            if let f = e.furnitureForm, f.isVoid { if let it = voidFormItem(e, o, project: { ($0.xy, -$0.z) }) { items.append(it) }; continue }
            let mesh = partMesh(e)
            let b = mesh.bounds
            guard !mesh.isEmpty, b.min.z <= cutZ + Tolerance.length, b.max.z >= depthZ - Tolerance.length else { continue }
            let hull = Rect2(min: b.min.xy, max: b.max.xy)
            if b.max.z > cutZ, b.min.z < cutZ {
                let loops = MeshSection.section(mesh, plane: cutPlane).map { Polygon2($0.points.map { cutPlane.fromPlane($0).xy }) }.filter { !$0.isDegenerate }
                if !loops.isEmpty {
                    let st = stroke(e.category, cut: true, o)
                    var prims: [GPrimitive] = []
                    if let fill = cutFill(e, materialID: partMaterial(e), o) { prims.append(.fill(loops, fill)) }
                    prims += loops.map { .polyline($0.points, closed: true, st) }
                    items.append(GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims, hitPolygons: loops))
                }
            }
            let below = b.max.z > cutZ ? MeshClip.clip(mesh, keepingBelow: cutPlane) : mesh
            guard !below.isEmpty else { continue }
            inputs.append(HLRInput(tag: i, mesh: below))
            map[i] = (e, o, hull)
        }
        guard !inputs.isEmpty else { return items }
        let proj = ViewProjection.topDown(z: cutZ, depth: max(0.01, cutZ - depthZ))
        let edges = HiddenLineRenderer.render(inputs, projection: proj, isCancelled: isCancelled)
        var byTag: [Int: [Segment2]] = [:]
        for e in edges { byTag[e.tag, default: []].append(e.segment) }
        // Grain arrows only on the shelves seen from above (not under another one below the cut).
        let seen = map.values.compactMap { $0.0.furnitureShelf.map { (s: $0, top: Polygon2($0.boundary)) } }.filter { $0.s.elevation <= cutZ }
        for (tag, (e, o, hull)) in map.sorted(by: { $0.key < $1.key }) {
            let st = stroke(e.category, cut: false, o)
            var prims: [GPrimitive] = (byTag[tag] ?? []).map { .polyline([proj.unproject($0.start), proj.unproject($0.end)], closed: false, st) }
            if detailLevel(e.category) != .coarse, let s = e.furnitureShelf, s.boundary.count >= 3,
               !seen.contains(where: { $0.s.elevation > s.elevation + Tolerance.length && $0.top.contains(Polygon2(s.boundary).centroid) }) {
                prims += grainArrow(planShelf: s, e, o)
            }
            items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: [.rectangle(hull)]))
        }
        // Hidden lines at Fine: what each part has that the others hide.
        if inputs.count > 1, map.values.contains(where: { detailLevel($0.0.category) == .fine }) {
            items += hiddenItems(inputs, map.mapValues { ($0.0, $0.1) }, projection: proj, shown: byTag, unproject: { proj.unproject($0) }, levels: [.fine])
        }
        return items
    }

    /// The grain/span arrow of a shelf seen from above: a double-headed arrow along its grain through its centre.
    func grainArrow(planShelf s: ShelfData, _ e: Element, _ o: GraphicOverride) -> [GPrimitive] {
        let tv = FurniturePartTypes.values(of: e, model)
        guard tv.grain != .none, s.boundary.count >= 3 else { return [] }
        var ang = FurniturePartMeshes.spanAngle(s)
        if tv.grain == .width { ang += .pi / 2 }
        let poly = Polygon2(s.boundary)
        let c = poly.centroid, d = Vec2.fromAngle(ang)
        let us = s.boundary.map { ($0 - c).dot(d) }
        let half = ((us.max() ?? 0) - (us.min() ?? 0)) * 0.2
        return arrow(c - d * half, c + d * half, symbolStroke(e, o))
    }

    /// A double-headed arrow (the grain symbol).
    func arrow(_ a: Vec2, _ b: Vec2, _ st: GStroke) -> [GPrimitive] {
        let d = (b - a).normalized, n = d.perpendicular
        let h = paper(0.0022), w = paper(0.0009)
        guard a.distance(to: b) > h * 2 else { return [] }
        return [.polyline([a, b], closed: false, st),
                .polyline([a + d * h + n * w, a, a + d * h - n * w], closed: false, st),
                .polyline([b - d * h + n * w, b, b - d * h - n * w], closed: false, st)]
    }

    /// Hidden lines: each part's edges drawn alone, less those the view shows (dashed, in the part's projection colour).
    func hiddenItems(_ inputs: [HLRInput], _ map: [Int: (Element, GraphicOverride)], projection: ViewProjection, shown: [Int: [Segment2]],
                     unproject: (Vec2) -> Vec2, clip: Rect2? = nil, levels: Set<DetailLevel>) -> [GItem] {
        var items: [GItem] = []
        for input in inputs {
            guard let (e, o) = map[input.tag], levels.contains(detailLevel(e.category)) else { continue }
            if isCancelled() { return items }
            let alone = HiddenLineRenderer.render([input], projection: projection, clip: clip, isCancelled: isCancelled).map(\.segment)
            let hidden = PresentationGeometry.subtract(alone, shown[input.tag] ?? [], tolerance: paper(0.0002)).filter { $0.length > paper(0.0006) }
            guard !hidden.isEmpty else { continue }
            var st = stroke(e.category, cut: false, o)
            st.pattern = .hidden
            st.weight = 1
            items.append(GItem(elementID: e.id, category: e.category, layer: .model,
                               primitives: hidden.map { .polyline([unproject($0.start), unproject($0.end)], closed: false, st) }, hitPolygons: []))
        }
        return items
    }

    // MARK: Elevations and sections

    func partVerticalItems(_ parts: [(Element, GraphicOverride)], _ fr: VerticalGraphics.Frame) -> [GItem] {
        let isSection = data.kind != .elevation
        let proj = ViewProjection(origin: Vec3(fr.origin.x, fr.origin.y, 0), right: Vec3(fr.right.x, fr.right.y, 0), up: .unitZ,
                                  near: isSection ? 0.0005 : 0, far: data.farClip)
        let toView: (Vec3) -> (Vec2, Double) = { p in let r = proj.project(p); return (r.uv, r.depth) }
        var items: [GItem] = []
        var inputs: [HLRInput] = []
        var map: [Int: (Element, GraphicOverride)] = [:]
        for (i, (e, o)) in parts.enumerated() {
            if isCancelled() { return items }
            if e.furnitureEdgeProfile != nil { if let it = edgeProfileItem(e, o, project: toView) { items.append(it) }; continue }
            if let f = e.furnitureForm, f.isVoid { if let it = voidFormItem(e, o, project: toView) { items.append(it) }; continue }
            let mesh = partMesh(e)
            guard !mesh.isEmpty else { continue }
            let depths = mesh.bounds.corners.map { ($0.xy - fr.origin.xy).dot(fr.forward) }
            guard (depths.max() ?? 0) >= -0.001, (depths.min() ?? 0) <= data.farClip else { continue }
            inputs.append(HLRInput(tag: i, mesh: mesh))
            map[i] = (e, o)
            if detailLevel(e.category) != .coarse { items += grainArrow(e, o, fr) }
        }
        let levels: Set<DetailLevel> = [.medium, .fine]
        guard inputs.count > 1, map.values.contains(where: { levels.contains(detailLevel($0.0.category)) }) else { return items }
        let crop = data.cropRegion
        let all = HiddenLineRenderer.render(inputs, projection: proj, clip: crop, isCancelled: isCancelled)
        var shown: [Int: [Segment2]] = [:]
        for e in all { shown[e.tag, default: []].append(e.segment) }
        // Only parts other parts hide from view have hidden lines; behind-the-view-plane parts are cut away already.
        items += hiddenItems(inputs, map, projection: proj, shown: shown, unproject: { $0 }, clip: crop, levels: levels)
        return items
    }

    /// The grain arrow of a panel or rail whose face the view sees square on (a back panel in a front elevation…).
    func grainArrow(_ e: Element, _ o: GraphicOverride, _ fr: VerticalGraphics.Frame) -> [GItem] {
        guard e.furniturePanel != nil || e.furnitureRail != nil, let box = FurniturePartSolids.partBox(e, model)?.box else { return [] }
        let tv = FurniturePartTypes.values(of: e, model)
        guard tv.grain != .none else { return [] }
        let size = Vec3(box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z)
        // The thin axis is the face normal; it must be the view direction.
        let thin: FamilyAxis = size.x <= size.y && size.x <= size.z ? .x : size.y <= size.z ? .y : .z
        let f = fr.forward
        let facing = thin == .x ? abs(f.x) > 0.99 : thin == .y ? abs(f.y) > 0.99 : false
        guard facing else { return [] }
        let u0 = fr.u(box.min.xy), u1 = fr.u(box.max.xy)
        let ur = (min(u0, u1), max(u0, u1)), zr = (box.min.z, box.max.z)
        let wu = ur.1 - ur.0, hz = zr.1 - zr.0
        let alongLength = tv.grain == .length
        let horizontal = (wu >= hz) == alongLength
        let c = Vec2((ur.0 + ur.1) / 2, (zr.0 + zr.1) / 2)
        let half = (horizontal ? wu : hz) * 0.2
        let d = horizontal ? Vec2(1, 0) : Vec2(0, 1)
        let prims = arrow(c - d * half, c + d * half, symbolStroke(e, o))
        return prims.isEmpty ? [] : [GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: [])]
    }

    // MARK: Edge profiles and void forms

    /// An edge profile or groove: its edge, seen in the view, as a thin selectable line.
    func edgeProfileItem(_ e: Element, _ o: GraphicOverride, project: (Vec3) -> (Vec2, Double)) -> GItem? {
        guard let ep = e.furnitureEdgeProfile, let host = model[e.hostID], let b = FurniturePartSolids.partBox(host, model)?.box else { return nil }
        let (p0, p1) = FurniturePartOperations.segment(b, ep.edge)
        let a = project(p0).0, c = project(p1).0
        let st = stroke(e.category, cut: false, o)
        let pad = paper(0.0012)
        let seg = Segment2(a, c)
        let hit: Polygon2
        if seg.isDegenerate { hit = .rectangle(Rect2(center: a, halfSize: Vec2(pad, pad))) }
        else { let n = seg.normal * pad, d = seg.direction * pad; hit = Polygon2([a - n - d, c - n + d, c + n + d, a + n - d]) }
        return GItem(elementID: e.id, category: e.category, layer: .model, primitives: seg.isDegenerate ? [] : [.polyline([a, c], closed: false, st)], hitPolygons: [hit])
    }

    /// A void form: its outline (bounds) dashed, so it can be selected.
    func voidFormItem(_ e: Element, _ o: GraphicOverride, project: (Vec3) -> (Vec2, Double)) -> GItem? {
        guard let f = e.furnitureForm else { return nil }
        var fam = FamilyDefinition(name: "Void", template: .genericModel)
        fam.types = [FamilyTypeDefinition(name: "Void", values: [:])]
        fam.solids = FurnitureForms.solids(e, f, model, PartSolidContext(symbolic: false)).solids.map { var s = $0; s.isVoid = false; return s }
        let b = FamilyEvaluator.evaluate(fam, typeName: "Void", units: model.units).bounds
        guard !b.isEmpty else { return nil }
        let pts = b.corners.map { project($0).0 }
        let r = Rect2(points: pts)
        var st = stroke(e.category, cut: false, o)
        st.pattern = .dash
        st.color = RGBColor(0.85, 0.45, 0.10)
        return GItem(elementID: e.id, category: e.category, layer: .model, primitives: [.polyline(r.corners, closed: true, st)], hitPolygons: [.rectangle(r)])
    }
}
