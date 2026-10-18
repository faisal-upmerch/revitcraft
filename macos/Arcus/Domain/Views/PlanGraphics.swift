import Foundation
import ArcusGeometry

/// Plan and reflected-ceiling-plan graphics.
struct PlanGraphics {
    let builder: ViewGraphicsBuilder
    let ceiling: Bool

    var model: BIMModel { builder.model }
    var data: ViewData { builder.data }
    var levelID: ElementID? { builder.view.levelID }
    var levelZ: Double { model.elevation(ofLevel: levelID) }
    func planeZ(_ level: ElementID?, _ offset: Double) -> Double { model.elevation(ofLevel: level ?? levelID) + offset }
    var cutZ: Double { planeZ(nil, data.viewRange.cutOffset) }
    var bottomZ: Double { data.viewRange.z(.bottom, viewLevel: levelID, in: model) } // BL-BROWSER: Level Above/Below, Unlimited
    var depthZ: Double { data.viewRange.z(.depth, viewLevel: levelID, in: model) } // BL-BROWSER
    var topZ: Double { data.viewRange.z(.top, viewLevel: levelID, in: model) } // BL-BROWSER

    func build() -> [GItem] {
        var items: [GItem] = []
        let visible = builder.visibleModelElements()
        var byCategory: [Category: [(Element, GraphicOverride)]] = [:]
        for v in visible { byCategory[v.0.category, default: []].append(v) }

        if let u = data.underlayLevelID, u != levelID { items += underlay(u) }
        items += links()
        items += walls(byCategory[.walls] ?? [])
        items += wp3Items(byCategory) // WP3: curtain walls, wall openings, shafts
        if builder.isCancelled() { return items }
        items += inserts((byCategory[.doors] ?? []) + (byCategory[.windows] ?? []))
        items += slabs((byCategory[.floors] ?? []) + (byCategory[.buildingPads] ?? []) + (ceiling ? (byCategory[.ceilings] ?? []) : []))
        items += columns((byCategory[.columns] ?? []) + (byCategory[.structuralColumns] ?? []))
        items += beams(byCategory[.structuralFraming] ?? [])
        items += f34Items(byCategory) // F34: reinforcement and beam systems
        if !ceiling {
            items += stairs(byCategory[.stairs] ?? [])
            items += railings(byCategory[.railings] ?? [])
            items += ramps(byCategory[.ramps] ?? [])
            items += components([Category.furniture, .casework, .genericModels, .plumbingFixtures, .specialtyEquipment, .parking,
                                 .lightingFixtures, .electricalFixtures, .mechanicalEquipment, .planting, .entourage, .site].flatMap { byCategory[$0] ?? [] }) // W2-LIB
        } else {
            items += ceilingFixtures([Category.lightingFixtures, .mechanicalEquipment].flatMap { byCategory[$0] ?? [] }) // W2-LIB: lights in ceiling plans
        }
        items += projectedBelow((byCategory[.roofs] ?? []) + (byCategory[.ifcReference] ?? []))
        items += topography(byCategory[.topography] ?? [])
        items += rooms()
        items += colorFills()
        items += datumsAndLines()
        items += SitePlanGraphics.items(builder: builder) // WP6a: scope boxes, cameras, base and survey points
        return items
    }

    // MARK: Walls

    func walls(_ ws: [(Element, GraphicOverride)]) -> [GItem] {
        let ws = ws.filter { !CurtainWallGeometry.isCurtain($0.0, model) } // WP3: curtain walls draw separately
        var cutPolys: [Polygon2] = []
        var owner: [Int] = []
        var projected: [(Element, GraphicOverride, Polygon2)] = []
        var cutWalls: [(Element, GraphicOverride)] = []
        for (w, o) in ws {
            guard let f = WallGeometry.frame(w, model) else { continue }
            if f.baseZ <= cutZ && f.topZ > cutZ {
                let pieces = WallGeometry.planCut(w, atZ: cutZ, model)
                guard !pieces.isEmpty else { continue }
                cutWalls.append((w, o))
                for p in pieces { cutPolys.append(p); owner.append(cutWalls.count - 1) }
            } else if f.topZ <= cutZ && f.topZ > depthZ - Tolerance.length, w.levelID == levelID || f.baseZ >= depthZ - Tolerance.length {
                if let fp = WallGeometry.footprint(w, model) { projected.append((w, o, fp)) }
            }
        }
        var items: [GItem] = []
        // Fills first, per wall.
        var boundaryByWall: [Int: [Segment2]] = [:]
        for piece in BoundaryCleanup.unionBoundary(of: cutPolys) { boundaryByWall[owner[piece.polygonIndex], default: []].append(piece.segment) }
        for (i, (w, o)) in cutWalls.enumerated() {
            let polys = zip(cutPolys, owner).filter { $0.1 == i }.map(\.0)
            var prims: [GPrimitive] = []
            let f = WallGeometry.frame(w, model)!
            let coreMat = f.assembly.layers.indices.contains(f.assembly.coreStart) ? f.assembly.layers[f.assembly.coreStart].materialID : nil
            if builder.detailLevel(.walls) == .fine, f.assembly.layers.count > 1 { // BL-VG
                // Per-layer fills: clip each layer band to the cut pieces.
                prims += layerFills(f, pieces: polys, o)
                prims += wrapFills(w, f, o) // WP3: wrapping at inserts and ends
            } else if let fill = builder.cutFill(w, materialID: coreMat, o) { // W4-HATCH: type coarse fill, material cut pattern
                prims.append(.fill(polys, fill))
            }
            let st = builder.stroke(.walls, cut: true, o)
            for s in merge(boundaryByWall[i] ?? []) { prims.append(.polyline(s, closed: false, st)) }
            if builder.detailLevel(.walls) != .coarse { // BL-VG
                let thin = GStroke(weight: 1, color: st.color, pattern: .solid, halftone: st.halftone)
                for c in WallGeometry.layerBoundaryCurves(w, f, atZ: cutZ, model) {
                    let pts = c.tessellate(chordTolerance: 0.003)
                    for k in 0..<(pts.count - 1) {
                        for seg in segmentsInside(Segment2(pts[k], pts[k + 1]), polys) { prims.append(.polyline([seg.start, seg.end], closed: false, thin)) }
                    }
                }
            }
            items.append(GItem(elementID: w.id, category: .walls, layer: .cut, primitives: prims, hitPolygons: polys))
        }
        // Projection walls below the cut.
        let projPieces = BoundaryCleanup.unionBoundary(of: projected.map(\.2))
        var projByWall: [Int: [Segment2]] = [:]
        for p in projPieces { projByWall[p.polygonIndex, default: []].append(p.segment) }
        for (i, (w, o, fp)) in projected.enumerated() {
            let st = builder.stroke(.walls, cut: false, o)
            items.append(GItem(elementID: w.id, category: .walls, layer: .model,
                               primitives: merge(projByWall[i] ?? []).map { .polyline($0, closed: false, st) }, hitPolygons: [fp]))
        }
        return items
    }

    func layerFills(_ f: WallFrame, pieces: [Polygon2], _ o: GraphicOverride) -> [GPrimitive] {
        guard case .line(let seg) = f.location else {
            if let fill = builder.cutFill(.walls, materialID: f.assembly.layers.first?.materialID, o) { return [.fill(pieces, fill)] }
            return []
        }
        var out: [GPrimitive] = []
        let b = f.assembly.boundaries
        for (i, layer) in f.assembly.layers.enumerated() where layer.thickness > Tolerance.length {
            let o1 = f.offset(fromExterior: b[i]), o2 = f.offset(fromExterior: b[i + 1])
            let lo = min(o1, o2), hi = max(o1, o2)
            // Band polygon long enough to cover the joins, then intersect with each piece.
            let ext = seg.direction * (f.thickness * 4 + 1)
            let a = seg.start - ext, bEnd = seg.end + ext
            let n = seg.normal
            let band = Polygon2([a + n * lo, bEnd + n * lo, bEnd + n * hi, a + n * hi])
            let clipped = PolygonBoolean.intersection(pieces.map { Profile2(outer: $0) }, [Profile2(outer: band)])
            guard !clipped.isEmpty else { continue }
            let fill = builder.cutFill(.walls, materialID: layer.materialID, o, type: nil, detail: .fine) ?? GFill(pattern: .diagonalUp) // W4-HATCH
            out.append(.fill(clipped.map(\.outer), fill))
        }
        return out
    }

    /// Parts of a segment strictly inside any of the polygons.
    func segmentsInside(_ s: Segment2, _ polys: [Polygon2]) -> [Segment2] {
        var ts: [Double] = [0, 1]
        for p in polys { for e in p.edges { if let h = s.lineIntersection(e), h.t > 0, h.t < 1, h.u >= -1e-9, h.u <= 1 + 1e-9 { ts.append(h.t) } } }
        ts.sort()
        var out: [Segment2] = []
        for i in 0..<(ts.count - 1) where ts[i + 1] - ts[i] > 1e-9 {
            let m = s.point(at: (ts[i] + ts[i + 1]) / 2)
            if polys.contains(where: { $0.contains(m, onBoundary: false) }) { out.append(Segment2(s.point(at: ts[i]), s.point(at: ts[i + 1]))) }
        }
        return out
    }

    /// Chains collinear/adjacent segments into polylines to reduce primitive count.
    func merge(_ segs: [Segment2]) -> [[Vec2]] {
        var remaining = segs
        var out: [[Vec2]] = []
        while let first = remaining.popLast() {
            var chain = [first.start, first.end]
            var extended = true
            while extended {
                extended = false
                if let i = remaining.firstIndex(where: { $0.start.isAlmostEqual(chain.last!) }) { chain.append(remaining.remove(at: i).end); extended = true }
                else if let i = remaining.firstIndex(where: { $0.end.isAlmostEqual(chain.last!) }) { chain.append(remaining.remove(at: i).start); extended = true }
            }
            out.append(chain)
        }
        return out
    }

    // MARK: Doors & windows

    func inserts(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let host = model[e.hostID], let f = WallGeometry.frame(host, model) else { continue }
            guard f.baseZ <= cutZ, f.topZ > cutZ else { continue }
            guard let (_, _, z0, z1) = InsertGeometry.openingInHost(e, host: f, model) else { continue }
            // Windows entirely above the cut plane are not drawn; below the cut show as projection.
            let isCut = z0 <= cutZ && z1 >= cutZ
            if !isCut && z0 > cutZ { continue }
            if ceiling && e.category == .doors { continue }
            let symbols = InsertGeometry.planSymbols(e, model).filter { $0.visibleAt.contains(builder.detailLevel(e.category)) } // BL-VG
            var prims: [GPrimitive] = []
            for s in symbols {
                guard let so = builder.subcategoryOverride(e, o, s.subcategory) else { continue } // BL-VG: hidden subcategory
                let cutPart = s.subcategory == .frame || s.subcategory == .glass || s.subcategory == .panel
                let st = builder.stroke(e, cut: isCut && cutPart && s.subcategory == .frame, so, s.subcategory) // BL-VG
                switch s.curve {
                case .line(let seg): prims.append(.polyline([seg.start, seg.end], closed: false, st))
                case .arc(let a): prims.append(.arc(a, GStroke(weight: 1, color: st.color, pattern: s.subcategory == .swing ? .solid : st.pattern, halftone: st.halftone)))
                }
            }
            // Selection area: the opening rectangle across the wall.
            var hit: [Polygon2] = []
            if let pl = InsertGeometry.placement(e, model), let op = FamilyInstanceGeometry.evaluate(e, model)?.opening {
                let h = f.thickness / 2 + 0.05
                hit.append(Polygon2([Vec2(op.xMin, -h), Vec2(op.xMax, -h), Vec2(op.xMax, h), Vec2(op.xMin, h)].map(pl.plan.apply)))
            }
            items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: hit))
        }
        return items
    }

    // MARK: Slabs

    func slabs(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let prof = ShaftCuts.planProfile(e, model), let (b, t) = SlabGeometry.planes(e, model) else { continue }
            let c = prof.outer.centroid
            let top = t.z(at: c), bot = b.z(at: c)
            if ceiling {
                guard e.category == .ceilings, bot >= cutZ - Tolerance.length, bot <= topZ + Tolerance.length else { continue }
                let st = builder.stroke(.ceilings, cut: false, o)
                var prims: [GPrimitive] = prof.loops.map { .polyline($0.points, closed: true, st) }
                let ceilingFill = builder.surfaceFill(materialID: SlabGeometry.finishMaterial(e, model, top: false), o)
                    ?? GFill(pattern: .grid, color: RGBColor(0.55, 0.55, 0.55), isModelPattern: true) // W4-HATCH: ceiling material surface pattern
                prims.insert(.fill(prof.loops, ceilingFill), at: 0)
                items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: [prof.outer]))
                continue
            }
            if e.category == .ceilings { continue }
            if bot <= cutZ && top >= cutZ {
                let st = builder.stroke(e.category, cut: true, o)
                var prims: [GPrimitive] = []
                if let fill = builder.cutFill(e, materialID: SlabGeometry.primaryMaterial(e, model), o) { prims.append(.fill(prof.loops, fill)) } // W4-HATCH
                prims += prof.loops.map { .polyline($0.points, closed: true, st) }
                items.append(GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims, hitPolygons: [prof.outer]))
            } else if top <= cutZ && top >= depthZ - Tolerance.length {
                let st = builder.stroke(e.category, cut: false, o)
                var prims: [GPrimitive] = []
                if let sf = builder.surfaceFill(materialID: SlabGeometry.finishMaterial(e, model, top: true), o) { prims.append(.fill(prof.loops, sf)) } // W4-HATCH: floor finish surface pattern
                prims += prof.loops.map { .polyline($0.points, closed: true, st) }
                items.append(GItem(elementID: e.id, category: e.category, layer: .fills, primitives: prims, hitPolygons: [prof.outer]))
            }
        }
        return items
    }

    // MARK: Columns, beams

    func columns(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let c = e.column else { continue }
            let base = model.baseElevation(of: e)
            let top = model.topElevation(base: base, topLevelID: c.topLevelID, topOffset: c.topOffset, unconnectedHeight: c.unconnectedHeight)
            let outlines = ComponentGeometry.planOutline(e, model)
            guard !outlines.isEmpty else { continue }
            let loops = ComponentGeometry.planLoops(e, model) // W2-TYPES: hollow sections keep their holes
            if base <= cutZ && top > cutZ {
                var prims: [GPrimitive] = []
                if let fill = builder.cutFill(e, materialID: model.typeParam(e, ParameterID("type.material"))?.refValue, o) { prims.append(.fill(loops, fill)) } // W4-HATCH
                let st = builder.stroke(e.category, cut: true, o)
                prims += loops.map { .polyline($0.points, closed: true, st) }
                items.append(GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims, hitPolygons: outlines))
            } else if top <= cutZ && top > depthZ {
                let st = builder.stroke(e.category, cut: false, o)
                items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: loops.map { .polyline($0.points, closed: true, st) }, hitPolygons: outlines))
            }
        }
        return items
    }

    func beams(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let outline = f34CutBack(BeamGeometry.planOutline(e, model), e) else { continue } // F34: symbolic cutback
            let top = model.elevation(ofLevel: e.levelID) + (e.beam?.startOffset ?? 0)
            guard top >= depthZ, top <= topZ + 0.5 else { continue }
            var st = builder.stroke(.structuralFraming, cut: false, o)
            if top > cutZ { st.pattern = .overhead }
            items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: [.polyline(outline.points, closed: true, st)], hitPolygons: [outline]))
        }
        return items
    }

    // MARK: Stairs & railings

    func stairs(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let l = StairGeometry.layout(e, model), l.baseZ <= cutZ + 0.01, l.topZ >= depthZ else { continue }
            let lines = StairGeometry.planLines(e, model, cutZ: cutZ)
            let st = builder.stroke(.stairs, cut: false, o)
            let cutSt = builder.stroke(.stairs, cut: true, o)
            var prims: [GPrimitive] = []
            for s in lines.outline { prims.append(.polyline([s.start, s.end], closed: false, cutSt)) }
            for s in lines.treads { prims.append(.polyline([s.start, s.end], closed: false, st)) }
            if builder.detailLevel(.stairs) == .fine { // BL-VG
                let hidden = GStroke(weight: 1, color: st.color, pattern: .hidden, halftone: st.halftone)
                for s in lines.above { prims.append(.polyline([s.start, s.end], closed: false, hidden)) }
            }
            if let b = lines.breakLine {
                let m = b.midpoint, d = b.direction, n = b.normal * builder.paper(0.0015)
                let zig = [b.start, m - d * builder.paper(0.002), m + n, m - n, m + d * builder.paper(0.002), b.end]
                prims.append(.polyline(zig, closed: false, st))
            }
            if lines.walk.count >= 2 {
                prims.append(.polyline(lines.walk, closed: false, st))
                let end = lines.walk.last!, prev = lines.walk[lines.walk.count - 2]
                let d = (end - prev).normalized, n = d.perpendicular
                let a = builder.paper(0.0025)
                prims.append(.polyline([end - d * a + n * a * 0.4, end, end - d * a - n * a * 0.4], closed: false, st))
                prims.append(.text(GText(position: lines.walk[0] - d * builder.paper(0.003), height: 0.0022, string: "UP", alignment: .center, verticalAnchor: 0.5)))
            }
            let hit = l.runs.map { l.runRect($0) } + l.landings.map(\.polygon)
            items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: hit))
        }
        return items
    }

    func railings(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            let path = RailingGeometry.path(e, model)
            guard path.count >= 2 else { continue }
            let z0 = path.map(\.z).min() ?? 0
            guard z0 <= cutZ + 1.2, z0 >= depthZ - 0.1 else { continue }
            let st = builder.stroke(.railings, cut: z0 < cutZ, o)
            let pts = path.map(\.xy)
            let hit = PolylineOffset.offset(pts, by: 0.05) + PolylineOffset.offset(pts, by: -0.05).reversed()
            items.append(GItem(elementID: e.id, category: e.category, layer: .model,
                               primitives: [.polyline(pts, closed: false, st), .polyline(PolylineOffset.offset(pts, by: 0.025), closed: false, GStroke(weight: 1, color: st.color, halftone: st.halftone))],
                               hitPolygons: [Polygon2(hit)]))
        }
        return items
    }

    // MARK: Components

    func components(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            let base = model.baseElevation(of: e)
            guard base <= cutZ + Tolerance.length, base >= depthZ - 0.5 else { continue }
            if e.levelID != levelID, base < bottomZ - 0.01 { continue }
            let st = builder.stroke(e.category, cut: false, o)
            let detail = builder.detailLevel(e.category) // BL-VG
            let symbols = ComponentGeometry.planSymbols(e, model).filter { $0.visibleAt.contains(detail) }
            var prims: [GPrimitive] = []
            for s in symbols {
                guard let so = builder.subcategoryOverride(e, o, s.subcategory) else { continue } // BL-VG
                let sst = so == o && s.subcategory == .general ? st : builder.stroke(e, cut: false, so, s.subcategory)
                switch s.curve {
                case .line(let seg): prims.append(.polyline([seg.start, seg.end], closed: false, sst))
                case .arc(let a): prims.append(.arc(a, sst))
                }
            }
            let outlines = ComponentGeometry.planOutline(e, model)
            if symbols.isEmpty { prims += ComponentGeometry.planOutline(e, model, detail: detail).map { .polyline($0.points, closed: true, st) } }
            items.append(GItem(elementID: e.id, category: e.category, layer: .model, primitives: prims, hitPolygons: outlines))
        }
        return items
    }

    // MARK: Roofs & 3D references

    func projectedBelow(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var inputs: [HLRInput] = []
        var map: [Int: (Element, GraphicOverride)] = [:]
        var items: [GItem] = []
        let cutPlane = Plane3.horizontal(z: cutZ)
        for (i, (e, o)) in list.enumerated() {
            var mesh = Mesh()
            for p in GeometryCache.shared.parts(e, model, detail: builder.detailLevel(e.category)) { mesh.append(p.mesh) } // BL-VG
            let b = mesh.bounds
            guard !mesh.isEmpty, b.min.z <= cutZ, b.max.z >= depthZ else { continue }
            inputs.append(HLRInput(tag: i, mesh: mesh))
            map[i] = (e, o)
            if b.max.z > cutZ {
                let loops = MeshSection.section(mesh, plane: cutPlane)
                if !loops.isEmpty {
                    let world = loops.map { Polygon2($0.points.map { cutPlane.fromPlane($0).xy }) }
                    let st = builder.stroke(e.category, cut: true, o)
                    var prims: [GPrimitive] = []
                    if let fill = builder.cutFill(e.category, materialID: nil, o) { prims.append(.fill(world, fill)) }
                    prims += world.map { .polyline($0.points, closed: true, st) }
                    items.append(GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims, hitPolygons: world))
                }
            }
        }
        guard !inputs.isEmpty else { return items }
        let proj = ViewProjection.topDown(z: cutZ, depth: max(0.01, cutZ - depthZ))
        let edges = HiddenLineRenderer.render(inputs, projection: proj, isCancelled: builder.isCancelled)
        var byTag: [Int: [Segment2]] = [:]
        for e in edges { byTag[e.tag, default: []].append(e.segment) }
        for tag in byTag.keys.sorted() {
            guard let (e, o) = map[tag] else { continue }
            let st = builder.stroke(e.category, cut: false, o)
            let segs = byTag[tag]!.map { Segment2(proj.unproject($0.start), proj.unproject($0.end)) }
            let hull = Rect2(points: segs.flatMap { [$0.start, $0.end] })
            items.append(GItem(elementID: e.id, category: e.category, layer: .model,
                               primitives: merge(segs).map { .polyline($0, closed: false, st) }, hitPolygons: [.rectangle(hull)]))
        }
        return items
    }

    func topography(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        list.map { e, o in
            let st = builder.stroke(.topography, cut: false, o)
            let major = GStroke(weight: 2, color: st.color, halftone: st.halftone)
            var prims: [GPrimitive] = []
            let site = SiteSettings(model) // W2-DWG: contour interval and primary contours from Site Settings
            if let b = e.topography?.boundary, b.count >= 3 { // W2-DWG: a sub-region shows its boundary; its host draws the contours
                return GItem(elementID: e.id, category: .topography, layer: .fills, primitives: [.polyline(b, closed: true, major)], hitPolygons: [Polygon2(b)])
            }
            for (z, seg) in (site.showContours ? TopographyGeometry.contours(e, interval: site.contourInterval) : []) {
                let isMajor = site.isPrimary(z)
                prims.append(.polyline([seg.start, seg.end], closed: false, isMajor ? major : st))
            }
            let m = TopographyGeometry.mesh(e)
            for i in stride(from: 0, to: m.featureEdges.count, by: 2) {
                prims.append(.polyline([m.positions[Int(m.featureEdges[i])].xy, m.positions[Int(m.featureEdges[i + 1])].xy], closed: false, major))
            }
            let hull = Polygon2(m.positions.map(\.xy)).bounds
            return GItem(elementID: e.id, category: .topography, layer: .fills, primitives: prims, hitPolygons: [.rectangle(hull)])
        }
    }

    // MARK: Rooms

    func rooms() -> [GItem] {
        guard let level = levelID else { return [] }
        var items: [GItem] = []
        let isAreaPlan = data.kind == .areaPlan
        let cat: Category = isAreaPlan ? .areas : .rooms
        let bounds = RoomBoundaryCache.shared.boundaries(level: level, model)
        for r in model.elements(cat) where r.levelID == level && (!isAreaPlan || data.areaSchemeID == nil || r.room?.areaSchemeID == data.areaSchemeID) {
            guard let o = builder.resolver.resolve(r) else { continue }
            guard let b = bounds[r.id], let prof = b.profile, b.state == .bounded else {
                // Unbounded rooms: a marker at the placement point so they remain selectable.
                if let p = r.room?.point {
                    let s = builder.paper(0.002)
                    let st = GStroke(weight: 1, color: RGBColor(0.8, 0.3, 0.2), halftone: o.halftone ?? false)
                    items.append(GItem(elementID: r.id, category: cat, layer: .annotation,
                                       primitives: [.polyline([p - Vec2(s, s), p + Vec2(s, s)], closed: false, st), .polyline([p - Vec2(s, -s), p + Vec2(s, -s)], closed: false, st)],
                                       hitPolygons: [.rectangle(Rect2(center: p, halfSize: Vec2(s, s)))]))
                }
                continue
            }
            var prims: [GPrimitive] = []
            if let sf = builder.surfaceFill(o) {
                prims.append(.fill(prof.loops, sf))
            } else if isAreaPlan {
                prims.append(.fill(prof.loops, GFill(pattern: .solid, color: RGBColor(0.75, 0.62, 0.85), transparency: 0.7)))
            }
            items.append(GItem(elementID: r.id, category: cat, layer: .fills, primitives: prims, hitPolygons: prof.loops))
        }
        return items
    }

    // MARK: Datums, model lines, links, underlay

    func datumsAndLines() -> [GItem] {
        var items: [GItem] = []
        for g in model.elements(.grids) {
            guard let o = builder.resolver.resolve(g), var gd = g.grid else { continue }
            guard ScopeBoxes.limitPlan(&gd, builder: builder) else { continue } // WP6a: scope box
            items.append(DatumGraphics.gridPlan(g, gd, builder: builder, o))
        }
        for r in model.elements(.referencePlanes) where r.ownerViewID == nil || r.ownerViewID == builder.view.id {
            guard let o = builder.resolver.resolve(r), var rp = r.referencePlane else { continue }
            guard ScopeBoxes.limitPlan(&rp, builder: builder) else { continue } // WP6a: scope box
            let st = builder.stroke(.referencePlanes, cut: false, o)
            var prims: [GPrimitive] = [.polyline([rp.line.start, rp.line.end], closed: false, st)]
            if !r.name.isEmpty {
                prims.append(.text(GText(position: rp.line.end, height: 0.0018, string: r.name, rotation: textAngle(rp.line.direction.angle), color: st.color)))
            }
            items.append(GItem(elementID: r.id, category: .referencePlanes, layer: .annotation, primitives: prims))
        }
        for l in model.elements(.detailLines) where l.ownerViewID == nil && l.levelID == levelID {
            guard let o = builder.resolver.resolve(l), let ml = l.modelLine else { continue }
            var st = builder.stroke(.detailLines, cut: false, o)
            if let ls = model[ml.styleID]?.lineStyle { st = GStroke(weight: ls.weight, color: ls.color, pattern: ls.pattern, halftone: st.halftone) }
            items.append(GItem(elementID: l.id, category: .detailLines, layer: .model, primitives: [curvePrim(ml.curve, st)]))
        }
        var lineCats: [Category] = [.roomSeparationLines, .propertyLines]
        if data.kind == .areaPlan { lineCats.append(.areaBoundaryLines) }
        for c in lineCats {
            for l in model.elements(c) where l.levelID == levelID || c == .propertyLines {
                if c == .areaBoundaryLines, let a = data.areaSchemeID, l.params[AreaPlans.schemeParameter]?.refValue != a { continue }
                guard let o = builder.resolver.resolve(l), let ml = l.modelLine else { continue }
                let st = builder.stroke(c, cut: false, o)
                items.append(GItem(elementID: l.id, category: c, layer: .model, primitives: [curvePrim(ml.curve, st)]))
            }
        }
        return items
    }

    func underlay(_ level: ElementID) -> [GItem] {
        let polys = model.elements(.walls).filter { $0.levelID == level }.compactMap { WallGeometry.footprint($0, model) }
        let st = GStroke(weight: 1, color: RGBColor(0.35, 0.35, 0.35), halftone: true)
        let segs = BoundaryCleanup.unionBoundary(of: polys).map(\.segment)
        return [GItem(elementID: nil, category: .walls, layer: .underlay, primitives: merge(segs).map { .polyline($0, closed: false, st) }, selectable: false)]
    }

    func links() -> [GItem] {
        var items: [GItem] = []
        for l in model.elements(.importedCAD) {
            guard let ld = l.link, ld.isLoaded, builder.resolver.vg.showLinks else { continue }
            if let owner = l.ownerViewID, owner != builder.view.id { continue }
            if l.ownerViewID == nil, l.levelID != nil, l.levelID != levelID { continue }
            guard let o = builder.resolver.resolve(l), let drawing = model.referenceDrawings[ld.contentKey] else { continue }
            items.append(LinkGraphics.item(l, ld, drawing, builder: builder, o, layer: ld.drawBehindModel ? .link : .model))
        }
        return items
    }

    func curvePrim(_ c: Curve2, _ st: GStroke) -> GPrimitive {
        switch c {
        case .line(let s): .polyline([s.start, s.end], closed: false, st)
        case .arc(let a): .arc(a, st)
        }
    }

    func textAngle(_ a: Double) -> Double {
        var r = Angle.normalizeSigned(a)
        if r > .pi / 2 + 1e-6 { r -= .pi } else if r < -.pi / 2 + 1e-6 { r += .pi }
        return r
    }
}

extension ViewProjection {
    /// Maps projected (u, v) back to plan XY for top-down projections.
    func unproject(_ uv: Vec2) -> Vec2 {
        let p = origin + right * uv.x + up * uv.y
        return p.xy
    }
}
