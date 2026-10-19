import Foundation
import ArcusGeometry
import ArcusDomain

// S3D2: line elements of a 3D view (Lines3D: grids, levels, reference planes, model lines, 2D CAD) as scene elements
// with edges and no faces, so the viewport draws them depth-tested like model edges and 3D snapping indexes them.
extension SceneBuilder {
    nonisolated static func lineElements(model: BIMModel, view: Element, resolver: VisibilityResolver, sectionBox: Box3?) -> [SceneElement] {
        Lines3D.items(model: model, view: view, resolver: resolver).compactMap { item in
            let b = item.mesh.bounds
            if let sb = sectionBox, !sb.intersects(b.expanded(by: Tolerance.length)) { return nil }
            return SceneElement(id: item.id, category: item.category, parts: [ScenePart(mesh: item.mesh, color: item.color)], bounds: b)
        }
    }
}

nonisolated extension SceneElement {
    /// S3D2: drawn as lines only (datums, model lines, 2D CAD): no faces.
    public var isLinesOnly: Bool { parts.allSatisfy { $0.mesh.indices.isEmpty } }
}

extension Viewport3DView {
    /// S3D2: whether the current visual style draws edges (and so the line elements: datums, model lines, 2D CAD).
    public var drawsEdges: Bool {
        visualStyle == .hiddenLine || visualStyle == .wireframe || visualStyle == .transparent || showEdgesInShadedStyles
    }
}
