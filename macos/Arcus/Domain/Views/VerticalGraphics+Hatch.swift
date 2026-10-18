import Foundation
import ArcusGeometry

// W4-HATCH: compound walls cut by a section show each layer's material cut pattern (medium and fine detail), like the
// per-layer fills in plan; surface finish materials of slabs for plan surface patterns.

extension VerticalGraphics {
    /// The section polygons of a wall split into its layers, each filled with the layer material's cut pattern.
    /// nil when the wall isn't a straight compound wall or the section runs parallel to it (one fill then).
    func wallLayerCutFills(_ e: Element, _ fr: Frame, _ polys: [Polygon2], _ o: GraphicOverride) -> [GPrimitive]? {
        if let parts = StackedWalls.parts(of: e, model) { return stackedCutFills(parts, fr, polys, o) } // F2
        guard let f = WallGeometry.frame(e, model), f.assembly.layers.count > 1, case .line(let seg) = f.location else { return nil }
        let planeLine = Segment2(fr.origin.xy - fr.right * 10_000, fr.origin.xy + fr.right * 10_000)
        let b = f.assembly.boundaries
        // Where each layer boundary (offset line) meets the section plane, as a view u coordinate.
        var us: [Double] = []
        for d in b {
            let line = seg.offset(by: f.offset(fromExterior: d))
            guard let hit = line.lineIntersection(planeLine) else { return nil }
            us.append(fr.u(hit.point))
        }
        guard us.count == f.assembly.layers.count + 1 else { return nil }
        var bb = Rect2.empty
        for p in polys { bb.include(p.bounds) }
        guard !bb.isEmpty else { return nil }
        let profiles = polys.map { Profile2(outer: $0) }
        var out: [GPrimitive] = []
        for (i, layer) in f.assembly.layers.enumerated() where layer.thickness > Tolerance.length {
            let lo = min(us[i], us[i + 1]), hi = max(us[i], us[i + 1])
            guard hi - lo > Tolerance.length else { continue }
            let band = Polygon2([Vec2(lo, bb.min.y - 1), Vec2(hi, bb.min.y - 1), Vec2(hi, bb.max.y + 1), Vec2(lo, bb.max.y + 1)])
            let clipped = PolygonBoolean.intersection(profiles, [Profile2(outer: band)])
            guard !clipped.isEmpty else { continue }
            let fill = builder.cutFill(.walls, materialID: layer.materialID, o, type: model.typeData(of: e), detail: .fine) ?? GFill(pattern: .diagonalUp)
            out.append(.fill(clipped.map(\.outer), fill))
        }
        return out.isEmpty ? nil : out
    }
}

extension VerticalGraphics {
    /// F2: a stacked wall's section, part by part: each part's height band of the cut, filled with its own layers.
    func stackedCutFills(_ parts: [Element], _ fr: Frame, _ polys: [Polygon2], _ o: GraphicOverride) -> [GPrimitive]? {
        var out: [GPrimitive] = []
        let profiles = polys.map { Profile2(outer: $0) }
        for p in parts {
            guard let f = WallGeometry.frame(p, model) else { continue }
            let band = Polygon2([Vec2(-1e6, f.baseZ), Vec2(1e6, f.baseZ), Vec2(1e6, f.topZ), Vec2(-1e6, f.topZ)])
            let clipped = PolygonBoolean.intersection(profiles, [Profile2(outer: band)]).map(\.outer)
            guard !clipped.isEmpty else { continue }
            if let layered = wallLayerCutFills(p, fr, clipped, o) { out += layered; continue }
            let a = f.assembly
            let core = a.layers.indices.contains(a.coreStart) ? a.layers[a.coreStart].materialID : a.layers.first?.materialID
            out.append(.fill(clipped, builder.cutFill(p, materialID: core, o) ?? GFill(pattern: .solid, color: .white)))
        }
        return out.isEmpty ? nil : out
    }
}

extension SlabGeometry {
    /// Material of the outermost finish layer of a floor, roof or ceiling: the first layer (top) or the last (bottom).
    /// Falls back to the core material for single-layer types.
    public static func finishMaterial(_ e: Element, _ model: BIMModel, top: Bool) -> ElementID? {
        guard let a = model.typeData(of: e)?.assembly else { return primaryMaterial(e, model) }
        let layers = a.layers.filter { $0.thickness > Tolerance.length }
        return (top ? layers.first : layers.last)?.materialID ?? primaryMaterial(e, model)
    }
}
