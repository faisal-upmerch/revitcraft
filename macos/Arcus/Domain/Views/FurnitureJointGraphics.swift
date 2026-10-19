import Foundation
import ArcusGeometry

// FM6: joint machining in elevations and sections at Fine, as shop drawings show it: holes drilled toward the viewer
// (dowels, cam bores, shelf pins) as dashed hidden circles, and holes across the view as dashed outlines of the bore.
// Grooves, dados and mortises are voids in the parts' solids, so the hidden-line pass already draws them; trims show at
// every detail level.

extension ViewGraphicsBuilder {
    /// Hidden holes of the joints and shelf pins (vertical views at Fine).
    func furnitureJointGraphics() -> [GItem] {
        guard model.isFurniture, data.kind.isVerticalCut, let fr = VerticalGraphics.frame(data) else { return [] }
        let visible = Dictionary(visibleModelElements().filter { $0.0.category.isFurniturePart && detailLevel($0.0.category) == .fine }.map { ($0.0.id, $0) },
                                 uniquingKeysWith: { a, _ in a })
        guard !visible.isEmpty else { return [] }
        let isSection = data.kind != .elevation
        let fwd = Vec3(fr.forward.x, fr.forward.y, 0)
        var byPart: [ElementID: [GPrimitive]] = [:]
        for entry in FurnitureMachining.entries(model) {
            guard case .drill(let c, let axis, let dia, let depth) = entry.op, let (e, o) = visible[entry.partID] else { continue }
            let d = (c.xy - fr.origin.xy).dot(fr.forward)
            guard d >= (isSection ? 0 : -0.001), d <= data.farClip else { continue }
            var st = stroke(e.category, cut: false, o)
            st.pattern = .hidden
            st.weight = 1
            let along = abs(axis.dot(fwd))
            if along > 0.95 {
                byPart[e.id, default: []].append(.arc(Arc2(center: fr.uv(c), radius: dia / 2, startAngle: 0, sweep: 2 * .pi), st))
            } else if along < 0.3 {
                // Seen from the side: the bore's outline from the face it's drilled in.
                let a = fr.uv(c), b = fr.uv(c + axis * depth)
                let dir = b - a
                guard dir.length > Tolerance.length else { continue }
                let n = dir.normalized.perpendicular * (dia / 2)
                byPart[e.id, default: []].append(.polyline([a + n, b + n, b - n, a - n], closed: false, st))
            }
        }
        return byPart.sorted { $0.key < $1.key }.compactMap { id, prims in
            guard let e = model[id] else { return nil }
            return GItem(elementID: id, category: e.category, layer: .model, primitives: prims, hitPolygons: [])
        }
    }
}
