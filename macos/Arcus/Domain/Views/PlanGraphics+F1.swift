import Foundation
import ArcusGeometry

// F1: plan graphics for RevitCraft port batch F1 elements.
extension PlanGraphics {
    /// Model Text in plans: lying text in the view range shows its glyph outlines (RevitCraft `plan_contours`); upright
    /// text cut by the cut plane shows its cut glyphs, and below it its footprint.
    func modelTexts(_ list: [(Element, GraphicOverride)]) -> [GItem] {
        var items: [GItem] = []
        for (e, o) in list {
            guard let t = e.modelText else { continue }
            let z0 = ModelTextGeometry.baseZ(e, model)
            let z1 = t.upright ? z0 + (ModelTextGeometry.localBounds(t)?.max.y ?? t.size) : z0 + t.depth
            guard z0 <= cutZ + Tolerance.length, z1 >= depthZ - Tolerance.length else { continue }
            if e.levelID != levelID, z0 < bottomZ - 0.01 { continue }
            let outlines = ModelTextGeometry.planOutlines(e)
            guard !outlines.isEmpty else { continue }
            let isCut = z0 < cutZ && z1 > cutZ
            if isCut && t.upright {
                let plane = Plane3.horizontal(z: cutZ)
                var mesh = Mesh()
                for p in GeometryCache.shared.parts(e, model, detail: builder.detailLevel(e.category)) { mesh.append(p.mesh) }
                let cut = MeshSection.section(mesh, plane: plane).map { Polygon2($0.points.map { plane.fromPlane($0).xy }) }
                if !cut.isEmpty {
                    let st = builder.stroke(e.category, cut: true, o)
                    var prims: [GPrimitive] = []
                    if let fill = builder.cutFill(e.category, materialID: t.materialID, o) { prims.append(.fill(cut, fill)) }
                    prims += cut.map { .polyline($0.points, closed: true, st) }
                    items.append(GItem(elementID: e.id, category: e.category, layer: .cut, primitives: prims, hitPolygons: outlines))
                    continue
                }
            }
            let st = builder.stroke(e.category, cut: isCut, o)
            items.append(GItem(elementID: e.id, category: e.category, layer: isCut ? .cut : .model,
                               primitives: outlines.map { .polyline($0.points, closed: true, st) }, hitPolygons: outlines))
        }
        return items
    }
}
