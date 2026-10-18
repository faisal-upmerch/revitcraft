import Foundation
import ArcusGeometry

/// Plan graphics for curtain walls, wall openings, shafts and compound-wall wrapping.
extension PlanGraphics {
    /// Curtain walls, wall openings and shaft openings.
    func wp3Items(_ byCategory: [Category: [(Element, GraphicOverride)]]) -> [GItem] {
        var items = curtainWalls((byCategory[.walls] ?? []).filter { CurtainWallGeometry.isCurtain($0.0, model) })
        // Openings are not among the builder's mesh categories; resolve their visibility here.
        func visible(_ c: Category) -> [(Element, GraphicOverride)] {
            byCategory[c] ?? model.elements(c).compactMap { e in builder.resolver.resolve(e).map { (e, $0) } }
        }
        items += wallOpenings(visible(.wallOpenings))
        items += shafts(visible(.shaftOpenings))
        return items
    }

    // MARK: Curtain walls

    func curtainWalls(_ ws: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (w, o) in ws {
            guard let f = WallGeometry.frame(w, model), let fp = WallGeometry.footprint(w, model) else { continue }
            let isCut = f.baseZ <= cutZ && f.topZ > cutZ
            let below = !isCut && f.topZ <= cutZ && f.topZ > depthZ - Tolerance.length && (w.levelID == levelID || f.baseZ >= depthZ - Tolerance.length)
            guard isCut || below else { continue }
            let (panels, mullions) = isCut ? CurtainWallGeometry.planOutlines(w, atZ: cutZ, model) : CurtainWallGeometry.planProjection(w, model)
            let st = builder.stroke(.walls, cut: isCut, o)
            let thin = GStroke(weight: 1, color: st.color, pattern: st.pattern, halftone: st.halftone)
            var prims: [GPrimitive] = []
            if builder.detailLevel(.walls) == .coarse { // BL-VG
                // Coarse: the panel plane as a single line, mullions as outlines.
                let c = f.location.offset(by: f.centerOffset)
                switch c {
                case .line(let s): prims.append(.polyline([s.start, s.end], closed: false, thin))
                case .arc(let a): prims.append(.arc(a, thin))
                }
            } else {
                prims += panels.map { .polyline($0.points, closed: true, thin) }
            }
            if isCut, !mullions.isEmpty, let fill = builder.cutFill(.walls, materialID: CurtainWallGeometry.spec(w, model)?.mullionMaterialID, o) {
                prims.append(.fill(mullions, fill))
            }
            prims += mullions.map { .polyline($0.points, closed: true, st) }
            items.append(GItem(elementID: w.id, category: .walls, layer: isCut ? .cut : .model, primitives: prims, hitPolygons: [fp]))
        }
        return items
    }

    // MARK: Wall openings

    /// Wall openings: selectable across the wall where the cut plane passes through them (the wall itself shows the
    /// gap); openings wholly above the cut plane are drawn as overhead lines.
    func wallOpenings(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let x = WallOpeningGeometry.extents(e, model), let outline = WallOpeningGeometry.planOutline(e, model) else { continue }
            guard x.host.baseZ <= cutZ, x.host.topZ > cutZ, x.z0 <= topZ + Tolerance.length else { continue }
            var prims: [GPrimitive] = []
            if x.z0 > cutZ {
                var st = builder.stroke(.wallOpenings, cut: false, o)
                st.pattern = .overhead
                prims.append(.polyline(outline.points, closed: true, st))
            } else if x.z1 < cutZ {
                continue
            }
            items.append(GItem(elementID: e.id, category: .wallOpenings, layer: .model, primitives: prims, hitPolygons: [outline]))
        }
        return items
    }

    // MARK: Shafts

    /// Shafts in plans whose cut plane lies within the shaft: the outline plus symbolic diagonals.
    func shafts(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let (z0, z1) = ShaftCuts.range(e, model), z0 <= cutZ + Tolerance.length, z1 >= cutZ - Tolerance.length,
                  let p = ShaftCuts.profile(e) else { continue }
            let st = builder.stroke(.shaftOpenings, cut: false, o)
            var prims: [GPrimitive] = p.loops.map { .polyline($0.points, closed: true, st) }
            let b = p.bounds
            for d in [Segment2(b.min, b.max), Segment2(Vec2(b.min.x, b.max.y), Vec2(b.max.x, b.min.y))] {
                for s in segmentsInside(d, [p.outer]) where !p.holes.contains(where: { $0.contains(s.midpoint, onBoundary: false) }) {
                    prims.append(.polyline([s.start, s.end], closed: false, st))
                }
            }
            items.append(GItem(elementID: e.id, category: .shaftOpenings, layer: .model, primitives: prims, hitPolygons: [p.outer]))
        }
        return items
    }

    // MARK: Wrapping

    /// Fills for the returned legs of wrapping layers at jambs and free ends (fine detail).
    func wrapFills(_ w: Element, _ f: WallFrame, _ o: GraphicOverride) -> [GPrimitive] {
        var out: [GPrimitive] = []
        for (layer, poly) in WallGeometry.wrapRegions(w, f, atZ: cutZ, model) where f.assembly.layers.indices.contains(layer) {
            let fill = builder.cutFill(.walls, materialID: f.assembly.layers[layer].materialID, o, type: nil, detail: .fine) ?? GFill(pattern: .diagonalUp) // W4-HATCH
            out.append(.fill([poly], fill))
        }
        return out
    }
}
