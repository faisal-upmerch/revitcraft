import Foundation
import ArcusGeometry

/// Elevation, section and detail (callout of a section) graphics generated from model geometry.
/// View coordinates: u along the view's right vector (meters from the plane origin), v = absolute elevation.
struct VerticalGraphics {
    let builder: ViewGraphicsBuilder
    var model: BIMModel { builder.model }
    var data: ViewData { builder.data }

    struct Frame {
        var origin: Vec3
        var forward: Vec2
        var right: Vec2
        var plane: Plane3
        func uv(_ p: Vec3) -> Vec2 { Vec2((p.xy - origin.xy).dot(right), p.z) }
        func u(_ p: Vec2) -> Double { (p - origin.xy).dot(right) }
    }

    static func frame(_ d: ViewData) -> Frame? {
        guard let o = d.planeOrigin, let f = d.viewDirection?.normalized, let r = d.rightVector else { return nil }
        let plane = Plane3(origin: Vec3(o.x, o.y, 0), normal: Vec3(-f.x, -f.y, 0), xAxis: Vec3(r.x, r.y, 0))
        return Frame(origin: Vec3(o.x, o.y, 0), forward: f, right: r, plane: plane)
    }

    func build() -> [GItem] {
        guard let fr = VerticalGraphics.frame(data) else { return [] }
        var items: [GItem] = []
        let visible = builder.visibleModelElements()
        let isSection = data.kind != .elevation
        let proj = ViewProjection(origin: Vec3(fr.origin.x, fr.origin.y, 0), right: Vec3(fr.right.x, fr.right.y, 0), up: .unitZ,
                                  near: isSection ? 0.0005 : 0, far: data.farClip)
        let crop = data.cropRegion
        var inputs: [HLRInput] = []
        var map: [Int: (Element, GraphicOverride)] = [:]
        for (i, (e, o)) in visible.enumerated() {
            if builder.isCancelled() { return items }
            let parts = GeometryCache.shared.parts(e, model, detail: builder.detailLevel(e.category)).filter { $0.isVisible(lookingAlong: fr.forward) } // BL-VG
            var mesh = Mesh()
            for p in parts { mesh.append(p.mesh) }
            guard !mesh.isEmpty else { continue }
            // Depth culling against the view slab.
            let b = mesh.bounds
            let depths = b.corners.map { ($0.xy - fr.origin.xy).dot(fr.forward) }
            guard (depths.max() ?? 0) >= -0.001, (depths.min() ?? 0) <= data.farClip else { continue }
            if let crop {
                let us = b.corners.map { fr.u($0.xy) }
                if (us.max() ?? 0) < crop.min.x || (us.min() ?? 0) > crop.max.x || b.max.z < crop.min.y || b.min.z > crop.max.y { continue }
            }
            inputs.append(HLRInput(tag: i, mesh: mesh))
            map[i] = (e, o)
            // Cut polygons where the section plane passes through the element.
            if isSection, (depths.min() ?? 0) < 0, (depths.max() ?? 0) > 0, e.topography?.solid != nil, parts.count > 1 {
                // BL-SITE: toposolids cut layer by layer, each with its own material's cut pattern.
                var prims: [GPrimitive] = [], hits: [Polygon2] = []
                let st = builder.stroke(e.category, cut: true, o)
                let thin = GStroke(weight: 1, color: st.color, halftone: st.halftone)
                for (k, p) in parts.enumerated() {
                    let polys = MeshSection.section(p.mesh, plane: fr.plane).map { Polygon2($0.points.map { Vec2($0.x, $0.y) }) }
                    guard !polys.isEmpty else { continue }
                    prims.append(.fill(polys, builder.cutFill(e.category, materialID: p.materialID, o) ?? GFill(pattern: .solid, color: .white)))
                    prims += polys.map { .polyline($0.points, closed: true, k == 0 || data.detailLevel == .coarse ? st : thin) }
                    hits += polys
                }
                if !prims.isEmpty { items.append(GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims, hitPolygons: hits)) }
            } else if isSection, (depths.min() ?? 0) < 0, (depths.max() ?? 0) > 0 {
                let loops = MeshSection.section(mesh, plane: fr.plane)
                if !loops.isEmpty {
                    let polys = loops.map { Polygon2($0.points.map { Vec2($0.x, $0.y) }) }
                    let st = builder.stroke(e.category, cut: true, o)
                    var prims: [GPrimitive] = []
                    let mat = parts.first?.materialID
                    if e.wall != nil, builder.detailLevel(e.category) != .coarse, let layered = wallLayerCutFills(e, fr, polys, o) { // W4-HATCH: per-layer cut patterns
                        prims += layered
                    } else if let fill = builder.cutFill(e, materialID: mat, o) { prims.append(.fill(polys, fill)) } // W4-HATCH
                    else { prims.append(.fill(polys, GFill(pattern: .solid, color: .white))) }
                    prims += polys.map { .polyline($0.points, closed: true, st) }
                    if builder.detailLevel(e.category) != .coarse, e.wall != nil { prims += wallLayerLines(e, fr, st) } // BL-VG
                    items.append(GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims, hitPolygons: polys))
                }
            }
        }
        let edges = HiddenLineRenderer.render(inputs, projection: proj, clip: crop, isCancelled: builder.isCancelled)
        var byTag: [Int: [HLREdge]] = [:]
        for e in edges { byTag[e.tag, default: []].append(e) }
        for tag in byTag.keys.sorted() {
            guard let (e, o) = map[tag] else { continue }
            let st = builder.stroke(e.category, cut: false, o)
            // proj maps uv with v measured along +Z from origin z=0 → v is absolute elevation.
            let segs = byTag[tag]!.map(\.segment)
            let hull = Rect2(points: segs.flatMap { [$0.start, $0.end] })
            items.append(GItem(elementID: e.id, category: e.category, layer: .model,
                               primitives: segs.map { .polyline([$0.start, $0.end], closed: false, st) }, hitPolygons: [.rectangle(hull)]))
        }
        items += fmg3FamilyModelLines(fr, visible) // FMG3: loaded casework's door swings and model lines
        items += colorFills(fr)
        items += f34Items(fr) // F34: wall-hosted reinforcement
        items += wallOpeningItems(fr) // WP3: selectable wall openings
        items += wallRevealItems(fr) // F1: selectable wall reveals
        items += LinkedGraphics.verticalItems(self, fr) // F67: point clouds and decals
        // Datums.
        var extents = Rect2.empty
        for i in items { extents.include(i.bounds) }
        if extents.isEmpty { extents = Rect2(min: Vec2(-5, 0), max: Vec2(5, 5)) }
        let u0 = (crop?.min.x ?? extents.min.x) - builder.paper(0.01)
        let u1 = (crop?.max.x ?? extents.max.x) + builder.paper(0.01)
        for l in model.levels {
            guard let o = builder.resolver.resolve(l), let ld = l.level else { continue }
            // WP6a: a level in a scope box appears only where the view sees the box, trimmed to it.
            guard let (lu0, lu1) = ScopeBoxes.levelExtent(l, from: u0, to: u1, origin: fr.origin.xy, right: fr.right, forward: fr.forward, builder: builder) else { continue }
            items.append(DatumGraphics.levelVertical(l, ld, from: lu0, to: lu1, builder: builder, o))
        }
        let zs = model.levels.compactMap { $0.level?.elevation }
        let zmin = (crop?.min.y ?? min(extents.min.y, zs.min() ?? 0)) - builder.paper(0.005)
        let zmax = (crop?.max.y ?? max(extents.max.y, zs.max() ?? 3)) + builder.paper(0.008)
        let planeLine = Segment2(fr.origin.xy - fr.right * 10_000, fr.origin.xy + fr.right * 10_000)
        for g in model.elements(.grids) {
            guard let o = builder.resolver.resolve(g), let seg = g.grid?.segment(seenBy: planeLine) else { continue } // F2: multi-segment grids
            guard !seg.isParallel(to: planeLine), let hit = seg.lineIntersection(planeLine) else { continue }
            if data.kind == .elevation {
                // Elevations show grids that run into the view within its depth, wherever the elevation plane sits.
                let d0 = (seg.start - fr.origin.xy).dot(fr.forward), d1 = (seg.end - fr.origin.xy).dot(fr.forward)
                guard max(d0, d1) >= -0.001, min(d0, d1) <= data.farClip else { continue }
            } else {
                // Sections show only grids the cut plane actually crosses.
                guard hit.t >= -0.01, hit.t <= 1.01 else { continue }
            }
            let u = fr.u(hit.point)
            if let crop, u < crop.min.x || u > crop.max.x { continue }
            // WP6a: a grid in a scope box appears only where the view sees the box, limited to its height.
            guard var (gz0, gz1) = ScopeBoxes.gridExtent(g, z0: zmin, z1: zmax, origin: fr.origin.xy, right: fr.right, forward: fr.forward, builder: builder) else { continue }
            // BL-SCHED (ARCUS-089): a grid's own 3D extents limit it in elevations and sections too.
            if let b = g.grid?.bottomElevation { gz0 = max(gz0, b) }
            if let t = g.grid?.topElevation { gz1 = min(gz1, t) }
            guard gz1 > gz0 else { continue }
            items.append(DatumGraphics.gridVertical(g, at: u, z0: gz0, z1: gz1, builder: builder, o))
        }
        return items
    }

    /// Vertical layer boundary lines where the section plane crosses a wall.
    func wallLayerLines(_ e: Element, _ fr: Frame, _ st: GStroke) -> [GPrimitive] {
        if let parts = StackedWalls.parts(of: e, model) { return parts.flatMap { wallLayerLines($0, fr, st) } } // F2: each part over its band
        guard let f = WallGeometry.frame(e, model) else { return [] }
        let planeLine = Segment2(fr.origin.xy - fr.right * 10_000, fr.origin.xy + fr.right * 10_000)
        var out: [GPrimitive] = []
        let thin = GStroke(weight: 1, color: st.color, halftone: st.halftone)
        let ops = WallGeometry.openings(e, model)
        for c in WallGeometry.layerBoundaryCurves(f) {
            guard let s = c.asSegment, let hit = s.lineIntersection(planeLine), hit.t >= 0, hit.t <= 1 else { continue }
            let u = fr.u(hit.point)
            let station = WallGeometry.station(of: hit.point, on: f.location)
            var bands = [(f.baseZ, f.topZ)]
            for o in ops where o.s0 <= station && o.s1 >= station {
                bands = bands.flatMap { b in [(b.0, min(b.1, o.z0)), (max(b.0, o.z1), b.1)].filter { $0.1 - $0.0 > 1e-4 } }
            }
            for b in bands { out.append(.polyline([Vec2(u, b.0), Vec2(u, b.1)], closed: false, thin)) }
        }
        return out
    }
}
