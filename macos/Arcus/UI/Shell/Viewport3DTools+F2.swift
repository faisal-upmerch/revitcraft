import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// F2: Work Plane ▸ Show in 3D views (RevitCraft view3d.rs): the work plane as a translucent plane with dashed grid
// lines and a solid border, drawn over the model around its extents.

extension Viewport3DToolController {
    /// The view shows its work plane.
    var showsWorkPlane: Bool { state.model[viewID]?.view?.showsWorkPlane == true }

    /// The plane shown: the one set on the view, else the level its tools draw on.
    var shownWorkPlane: WorkPlaneRef? {
        if let w = state.model[viewID]?.view?.workPlane, WorkPlanes.isValid(w, state.model) { return w }
        return workPlaneLevel.map { .level($0) }
    }

    func drawShownWorkPlane(_ cg: CGContext, viewport v: Viewport3DView) {
        let m = state.model
        guard showsWorkPlane, let w = shownWorkPlane, let f = WorkPlanes.frame(w, m) else { return }
        let r = WorkPlanes.extent(f, m)
        let corners = r.corners.map { f.point($0.x, $0.y) }
        cg.saveGState()
        defer { cg.restoreGState() }
        let pts = corners.compactMap { v.viewPoint(of: $0) }
        if pts.count == 4 {
            cg.setFillColor(NSColor(srgbRed: 110 / 255, green: 170 / 255, blue: 235 / 255, alpha: 45 / 255).cgColor)
            cg.addLines(between: pts); cg.closePath(); cg.fillPath()
        }
        cg.setStrokeColor(NSColor(srgbRed: 80 / 255, green: 150 / 255, blue: 230 / 255, alpha: 160 / 255).cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [6, 4])
        for g in WorkPlanes.gridLines(r, spacing: WorkPlanes.spacing(m)) {
            if let (a, b) = v.viewSegment(f.point(g.start.x, g.start.y), f.point(g.end.x, g.end.y)) { cg.move(to: a); cg.addLine(to: b) }
        }
        cg.strokePath()
        cg.setLineDash(phase: 0, lengths: [])
        cg.setStrokeColor(NSColor(srgbRed: 60 / 255, green: 130 / 255, blue: 220 / 255, alpha: 1).cgColor)
        cg.setLineWidth(1.5)
        for k in 0..<4 {
            if let (a, b) = v.viewSegment(corners[k], corners[(k + 1) % 4]) { cg.move(to: a); cg.addLine(to: b) }
        }
        cg.strokePath()
    }
}
