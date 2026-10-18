import Foundation
import ArcusGeometry
import ArcusDomain

/// Edit Witness Lines: clicking a reference adds it to a linear or aligned dimension string; clicking one the
/// dimension already measures removes it (a dimension keeps at least two). The dimension keeps its element id.
@MainActor
public final class WitnessLineTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.editWitnessLines
    public let title = "Edit Witness Lines"
    public let dimensionID: ElementID

    public init(ctx: ToolContext, dimensionID: ElementID) {
        self.dimensionID = dimensionID
        super.init(ctx: ctx)
    }

    public var prompt: String { "Click a wall, grid, line or point to add a witness line; click a measured reference to remove it. Return or Esc finishes." }

    var dimension: DimensionData? { ctx.model[dimensionID]?.dimension }

    /// The reference a click would add or remove, and whether it is already measured.
    func pick(_ i: ToolInput) -> (ref: GeometryReference, point: Vec2, existing: Int?)? {
        guard let d = dimension else { return nil }
        var probe = i
        probe.hitCandidates = i.hitCandidates.filter { $0 != dimensionID }
        probe.hit = probe.hitCandidates.first
        let picker = DimensionTool(ctx: ctx, kind: d.kind)
        // A wall already measured counts as clicked when any of its faces or its centerline is, so it can be removed.
        if let id = probe.hit, let k = d.references.firstIndex(where: { $0.elementID == id }) {
            return (d.references[k], i.point, k)
        }
        guard let (ref, p) = picker.reference(for: probe) else { return nil }
        return (ref, p, d.references.firstIndex(of: ref))
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.cursor = .pick
        preview.highlight = [dimensionID]
        if let p = pick(i), let id = p.ref.elementID { preview.highlight.insert(id) }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let d = dimension else { message("The dimension no longer exists."); return }
        guard let p = pick(i) else { message("Click a wall, grid, line or snap point."); return }
        if let k = p.existing {
            guard d.references.count > 2 else { message("A dimension needs at least two witness lines."); return }
            ctx.session.perform("Remove Witness Line") { tx in
                tx.update(dimensionID) { e in
                    guard var dd = e.dimension else { return }
                    dd.references.remove(at: k)
                    if k < dd.fallbackPoints.count { dd.fallbackPoints.remove(at: k) }
                    e.dimension = dd
                }
            }
        } else {
            ctx.session.perform("Add Witness Line") { tx in
                tx.update(dimensionID) { e in
                    guard let dd = e.dimension else { return }
                    e.dimension = Self.adding(p.ref, at: p.point, to: dd, tx.model, view: tx.model[e.ownerViewID])
                }
            }
        }
        if let err = ctx.session.lastError { message(err.message) }
    }

    /// `d` with `ref` inserted in order along the measurement direction.
    static func adding(_ ref: GeometryReference, at point: Vec2, to d: DimensionData, _ model: BIMModel, view: Element? = nil) -> DimensionData {
        var out = d
        // W2-ANNOT: positions in the dimension's view (sections and elevations use (u, z)).
        let pts = AnnotationGeometry.points(d, model, view: view)
        // Fallback points stay parallel to the references (they are shown if a reference stops resolving).
        var fallback = Array(d.fallbackPoints.prefix(pts.count))
        fallback += pts.dropFirst(fallback.count)
        let n = AnnotationGeometry.measurementDirection(d, pts, model, view: view)
        let q = AnnotationGeometry.anchor(ref, fallback: point, model, view: view) ?? point
        let k = pts.firstIndex { ($0 - d.linePoint).dot(n) > (q - d.linePoint).dot(n) } ?? pts.count
        // Keep the existing order when it runs against the direction: insert relative to the first reference.
        let ascending = pts.count < 2 || (pts[pts.count - 1] - pts[0]).dot(n) >= 0
        let index = ascending ? k : (pts.firstIndex { ($0 - d.linePoint).dot(n) < (q - d.linePoint).dot(n) } ?? pts.count)
        out.references.insert(ref, at: index)
        fallback.insert(point, at: index)
        out.fallbackPoints = fallback
        return out
    }

    public func finish() -> Bool { ctx.toolFinished?(); return true }
    public func escape() -> EscapeResult { .exitTool }
}
