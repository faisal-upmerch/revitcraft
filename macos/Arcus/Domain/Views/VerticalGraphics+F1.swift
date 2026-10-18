import Foundation
import ArcusGeometry

// F1: section and elevation graphics for RevitCraft port batch F1 elements.
extension VerticalGraphics {
    /// Wall reveals: the wall's own solid draws the groove; each reveal adds a selectable band over it.
    func wallRevealItems(_ fr: Frame) -> [GItem] {
        var items: [GItem] = []
        for e in model.elements(.reveals) {
            guard builder.resolver.resolve(e) != nil, let host = model[e.hostID], let f = WallGeometry.frame(host, model),
                  let seg = f.location.asSegment, let cut = WallReveals.cut(e, f) else { continue }
            let p0 = seg.point(at: max(0, cut.rect.min.x) / f.length), p1 = seg.point(at: min(f.length, cut.rect.max.x) / f.length)
            let d0 = (p0 - fr.origin.xy).dot(fr.forward), d1 = (p1 - fr.origin.xy).dot(fr.forward)
            guard max(d0, d1) >= -0.001, min(d0, d1) <= data.farClip else { continue }
            let u0 = fr.u(p0), u1 = fr.u(p1)
            guard abs(u1 - u0) > 1e-4 else { continue } // seen along the wall: the section cut shows the notch
            if let crop = data.cropRegion, max(u0, u1) < crop.min.x || min(u0, u1) > crop.max.x { continue }
            let band = Polygon2([Vec2(u0, cut.rect.min.y), Vec2(u1, cut.rect.min.y), Vec2(u1, cut.rect.max.y), Vec2(u0, cut.rect.max.y)]).counterClockwise
            items.append(GItem(elementID: e.id, category: .reveals, layer: .model, primitives: [], hitPolygons: [band]))
        }
        return items
    }
}
