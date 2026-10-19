import Foundation
import ArcusGeometry

// FM3: a Furniture document's reference planes in elevations and sections, as the Family Editor shows them: planes
// seen edge-on are dashed lines with their names (Left, Right, Top…). Plans draw the vertical planes as before and
// leave out the horizontal ones. Projects are unchanged.

extension ViewGraphicsBuilder {
    /// Reference plane lines for a Furniture document's vertical views (none in plans, 3D views or projects).
    func furnitureGraphics() -> [GItem] {
        guard model.isFurniture, data.kind.isVerticalCut, let fr = VerticalGraphics.frame(data) else { return [] }
        let planes = FurniturePlanes.all(model)
        guard !planes.isEmpty else { return [] }
        let ext = FurniturePlanes.extents(model)
        let corners = [Vec2(ext.x.lowerBound, ext.y.lowerBound), Vec2(ext.x.upperBound, ext.y.lowerBound),
                       Vec2(ext.x.lowerBound, ext.y.upperBound), Vec2(ext.x.upperBound, ext.y.upperBound)].map(fr.u)
        let uRange = (corners.min() ?? -1)...(corners.max() ?? 1)
        var items: [GItem] = []
        for p in planes {
            guard let o = resolver.resolve(p), let rp = p.referencePlane, let fp = rp.furniture, let v = FurniturePlanes.position(rp) else { continue }
            let st = stroke(.referencePlanes, cut: false, o)
            let a: Vec2, b: Vec2, angle: Double
            if fp.axis == .z {
                a = Vec2(uRange.lowerBound, v); b = Vec2(uRange.upperBound, v); angle = 0
            } else {
                // Seen edge-on only when the plane runs along the view direction.
                guard abs(rp.line.direction.cross(fr.forward)) < 0.01 else { continue }
                let u = fr.u(rp.line.start)
                a = Vec2(u, ext.z.lowerBound); b = Vec2(u, ext.z.upperBound); angle = .pi / 2
            }
            var prims: [GPrimitive] = [.polyline([a, b], closed: false, st)]
            if !p.name.isEmpty {
                prims.append(.text(GText(position: b, height: 0.0018, string: p.name, rotation: angle, color: st.color)))
            }
            items.append(GItem(elementID: p.id, category: .referencePlanes, layer: .annotation, primitives: prims))
        }
        return items
    }
}
