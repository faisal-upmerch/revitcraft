import Foundation
import ArcusGeometry

// F67: 2D graphics of linked models (cut at the host view's cut plane and projected below it, styled by the host
// view's object styles for each linked element's category), point clouds (dots within the view range), decals
// (outline with a cross) and DWF markups on sheets.

enum LinkedGraphics {
    /// Point dots drawn per point cloud in a 2D view.
    static let maxPoints2D = 40_000

    // MARK: Plans

    static func planItems(_ g: PlanGraphics) -> [GItem] {
        let b = g.builder
        var items: [GItem] = []
        if b.resolver.vg.showLinks {
            for e in b.model.elements(.linkedModels) {
                guard let l = e.linkedModel, l.isLoaded, let o = b.resolver.resolve(e) else { continue }
                items += linkedPlan(e, l, o, g)
                if b.isCancelled() { return items }
            }
        }
        for e in b.model.elements(.pointClouds) {
            guard let pc = e.pointCloud, pc.isLoaded, let o = b.resolver.resolve(e) else { continue }
            let t = pc.transform
            let pts = thinned(pc.points.points).map { (t.apply($0.position), $0.color) }.filter { $0.0.z >= g.bottomZ - 1e-6 && $0.0.z <= g.cutZ + 1e-6 }
            if let item = dots(e, pts.map { ($0.0.xy, $0.1) }, pc.hasColor, o, b) { items.append(item) }
        }
        for e in b.model.elements(.decals) {
            guard let d = e.decal, let o = b.resolver.resolve(e) else { continue }
            let c = d.corners()
            let zs = c.map(\.z)
            let st = b.stroke(.decals, cut: false, o)
            if abs(d.normal.normalized.z) > 0.7 {
                // On a floor or roof: seen from above when it lies below the cut plane.
                guard (zs.max() ?? 0) <= g.cutZ + 1e-6, d.normal.z > 0 || g.ceiling else { continue }
                items.append(rectItem(e, c.map(\.xy), st))
            } else if (zs.min() ?? 0) <= g.topZ, (zs.max() ?? 0) >= g.bottomZ {
                // On a wall: a line along the face, drawn just in front of it.
                let lift = d.normal.normalized.xy * b.paper(0.0006)
                let a = c[0].xy + lift, z = c[1].xy + lift
                items.append(GItem(elementID: e.id, category: .decals, layer: .annotation, primitives: [.polyline([a, z], closed: false, GStroke(weight: max(2, st.weight), color: st.color, halftone: st.halftone))],
                                   hitPolygons: [Polygon2([a - lift, z - lift, z + lift, a + lift])]))
            }
        }
        return items
    }

    static func linkedPlan(_ e: Element, _ l: LinkedModelData, _ o: GraphicOverride, _ g: PlanGraphics) -> [GItem] {
        let b = g.builder
        let parts = GeometryCache.shared.parts(e, b.model, detail: .medium)
        let cutZ = g.cutZ, depthZ = g.depthZ
        let cutPlane = Plane3.horizontal(z: cutZ)
        var inputs: [HLRInput] = []
        var cutPrims: [GPrimitive] = [], hits: [Polygon2] = []
        var hull = Rect2.empty
        for (i, p) in parts.enumerated() where i < l.parts.count {
            let cat = l.parts[i].category
            if b.resolver.vg.hiddenCategories.contains(cat) || b.resolver.temp.hiddenCategories.contains(cat) { continue }
            let bb = p.mesh.bounds
            guard !p.mesh.isEmpty, bb.min.z <= cutZ, bb.max.z >= depthZ else { continue }
            inputs.append(HLRInput(tag: i, mesh: p.mesh))
            hull.include(Rect2(min: bb.min.xy, max: bb.max.xy))
            if bb.max.z > cutZ, bb.min.z < cutZ {
                let loops = MeshSection.section(p.mesh, plane: cutPlane)
                guard !loops.isEmpty else { continue }
                let world = loops.map { Polygon2($0.points.map { cutPlane.fromPlane($0).xy }) }
                let st = b.stroke(cat, cut: true, o)
                cutPrims.append(.fill(world, b.cutFill(cat, materialID: nil, o) ?? GFill(pattern: .solid, color: RGBColor(0.82, 0.82, 0.82), halftone: st.halftone)))
                cutPrims += world.map { GPrimitive.polyline($0.points, closed: true, st) }
                hits += world
            }
        }
        var items: [GItem] = []
        if !inputs.isEmpty {
            let proj = ViewProjection.topDown(z: cutZ, depth: max(0.01, cutZ - depthZ))
            let edges = HiddenLineRenderer.render(inputs, projection: proj, isCancelled: b.isCancelled)
            var byTag: [Int: [Segment2]] = [:]
            for edge in edges { byTag[edge.tag, default: []].append(Segment2(proj.unproject(edge.segment.start), proj.unproject(edge.segment.end))) }
            var prims: [GPrimitive] = []
            for tag in byTag.keys.sorted() {
                let st = b.stroke(l.parts[tag].category, cut: false, o)
                prims += g.merge(byTag[tag]!).map { .polyline($0, closed: false, st) }
            }
            if !prims.isEmpty { items.append(GItem(elementID: e.id, category: .linkedModels, layer: .model, primitives: prims, hitPolygons: hull.isEmpty ? [] : [.rectangle(hull)])) }
        }
        if !cutPrims.isEmpty { items.append(GItem(elementID: e.id, category: .linkedModels, layer: .cut, primitives: cutPrims, hitPolygons: hits)) }
        return items
    }

    // MARK: Sections and elevations

    static func verticalItems(_ v: VerticalGraphics, _ fr: VerticalGraphics.Frame) -> [GItem] {
        let b = v.builder
        var items: [GItem] = []
        let far = v.data.farClip
        for e in b.model.elements(.pointClouds) {
            guard let pc = e.pointCloud, pc.isLoaded, let o = b.resolver.resolve(e) else { continue }
            let t = pc.transform
            var pts: [(Vec2, RGBColor)] = []
            for p in thinned(pc.points.points) {
                let w = t.apply(p.position)
                let depth = (w.xy - fr.origin.xy).dot(fr.forward)
                if depth >= 0, depth <= far { pts.append((fr.uv(w), p.color)) }
            }
            if let item = dots(e, pts, pc.hasColor, o, b) { items.append(item) }
        }
        for e in b.model.elements(.decals) {
            guard let d = e.decal, let o = b.resolver.resolve(e) else { continue }
            // Faces turned towards the viewer.
            guard d.normal.xy.dot(fr.forward) < -0.3 else { continue }
            let depth = (d.center.xy - fr.origin.xy).dot(fr.forward)
            guard depth >= -0.01, depth <= far else { continue }
            items.append(rectItem(e, d.corners().map(fr.uv), b.stroke(.decals, cut: false, o)))
        }
        return items
    }

    // MARK: Shared

    static func thinned(_ pts: [(position: Vec3, color: RGBColor)]) -> [(position: Vec3, color: RGBColor)] {
        guard pts.count > maxPoints2D else { return pts }
        let step = (pts.count + maxPoints2D - 1) / maxPoints2D
        return stride(from: 0, to: pts.count, by: step).map { pts[$0] }
    }

    static func dots(_ e: Element, _ pts: [(Vec2, RGBColor)], _ hasColor: Bool, _ o: GraphicOverride, _ b: ViewGraphicsBuilder) -> GItem? {
        guard !pts.isEmpty else { return nil }
        let s = b.paper(0.0003)
        let st = b.stroke(.pointClouds, cut: false, o)
        var byColor: [RGBColor: [Polygon2]] = [:]
        var hull = Rect2.empty
        for (p, c) in pts {
            let col = hasColor && o.projectionLineColor == nil ? RGBColor((c.r * 8).rounded() / 8, (c.g * 8).rounded() / 8, (c.b * 8).rounded() / 8) : st.color
            byColor[col, default: []].append(.rectangle(Rect2(min: p - Vec2(s, s), max: p + Vec2(s, s))))
            hull.include(p)
        }
        let prims: [GPrimitive] = byColor.keys.sorted { $0.hexString < $1.hexString }.map { .fill(byColor[$0]!, GFill(pattern: .solid, color: $0, halftone: st.halftone)) }
        return GItem(elementID: e.id, category: .pointClouds, layer: .model, primitives: prims, hitPolygons: [.rectangle(hull.expanded(by: s))])
    }

    /// A decal outline with its diagonals.
    static func rectItem(_ e: Element, _ c: [Vec2], _ st: GStroke) -> GItem {
        GItem(elementID: e.id, category: .decals, layer: .annotation,
              primitives: [.polyline(c, closed: true, st), .polyline([c[0], c[2]], closed: false, st), .polyline([c[1], c[3]], closed: false, st)],
              hitPolygons: [Polygon2(c)])
    }

    // MARK: DWF markups (sheets)

    /// A markup page's lines, fills and text on its sheet (paper meters). Pictures draw as framed boxes here; the canvas
    /// paints the images themselves.
    static func markupItem(_ e: Element, _ m: MarkupData) -> GItem? {
        guard m.isLoaded else { return nil }
        let t = Transform2.translation(m.offset)
        var prims: [GPrimitive] = []
        for p in m.polylines where p.points.count >= 2 {
            let pts = p.points.map(t.apply)
            if p.filled, pts.count >= 3 { prims.append(.fill([Polygon2(pts)], GFill(pattern: .solid, color: p.color, transparency: 0.5))) }
            else { prims.append(.polyline(pts, closed: false, GStroke(weight: 1, color: p.color))) }
        }
        for x in m.texts { prims.append(.text(GText(position: t.apply(x.position), height: x.height, string: x.string, color: x.color))) }
        for pic in m.pictures {
            let r = Rect2(min: t.apply(pic.bounds.min), max: t.apply(pic.bounds.max))
            prims.append(.polyline(r.corners, closed: true, GStroke(weight: 1, color: .gray, pattern: .dash)))
        }
        var hull = Rect2.empty
        for p in m.polylines { for q in p.points { hull.include(t.apply(q)) } }
        for x in m.texts { hull.include(t.apply(x.position)) }
        for pic in m.pictures { hull.include(t.apply(pic.bounds.min)); hull.include(t.apply(pic.bounds.max)) }
        guard !prims.isEmpty else { return nil }
        return GItem(elementID: e.id, category: .dwfMarkups, layer: .annotation, primitives: prims, hitPolygons: hull.isEmpty ? [] : [.rectangle(hull)])
    }
}
