import Foundation
import ArcusGeometry
import ArcusDomain

// FMG1: dimensioning furniture parts: a click on a part picks the face nearest the pointer that the view sees as a line
// (in plan its sides, in an elevation or section its top, bottom and the sides across the view), as clicking a wall
// picks its nearer face. The dimension then follows the face as the part moves, is resized or flexes.

extension DimensionTool {
    func fmg1PartFaceReference(_ i: ToolInput) -> (GeometryReference, Vec2)? {
        guard kind == .aligned || kind == .linear, let id = i.hit, let e = ctx.model[id], e.category.isFurniturePart else { return nil }
        let best = FurniturePartFaces.references(id).compactMap { r -> (GeometryReference, Double)? in
            guard let res = AnnotationGeometry.resolve(r, ctx.model, view: ctx.view) else { return nil }
            return (r, lineDistance(res, i.rawPoint))
        }.min { $0.1 < $1.1 }
        guard let (ref, _) = best else { return nil }
        return (ref, i.rawPoint)
    }
}
