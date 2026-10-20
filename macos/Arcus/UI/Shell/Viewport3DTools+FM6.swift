import AppKit
import ArcusGeometry
import ArcusApplication
import ArcusDomain
import ArcusViewport3D

// FM6: markers a tool places on the model in 3D views (the Joint tool's joint markers), drawn at their world positions
// rather than on the work plane: round for joints by rule, square for joints the user set; hovered ones larger, the
// picked one filled.

extension Viewport3DToolController {
    func drawWorldMarkers(_ markers: [ToolWorldMarker], _ cg: CGContext, viewport v: Viewport3DView) {
        cg.saveGState()
        defer { cg.restoreGState() }
        let tint = Tokens.selection
        // FMG4: in an exploded view, between the two parts where they are drawn.
        let offsets = state.model[viewID].map { FurnitureExplode.offsets(state.model, view: $0) } ?? [:]
        for m in markers.sorted(by: { $0.emphasis < $1.emphasis }) {
            guard let p = v.viewPoint(of: m.position + FurnitureExplode.markerOffset(m.parts, offsets)) else { continue }
            let r: CGFloat = m.emphasis > 0 ? 6.5 : 4.5
            let rect = CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)
            let path = m.square ? CGPath(rect: rect, transform: nil) : CGPath(ellipseIn: rect, transform: nil)
            cg.addPath(path)
            cg.setFillColor(m.emphasis == 2 ? tint.cgColor : NSColor.white.withAlphaComponent(0.92).cgColor)
            cg.fillPath()
            cg.addPath(path)
            cg.setStrokeColor(tint.cgColor)
            cg.setLineWidth(m.emphasis > 0 ? 2 : 1.25)
            cg.strokePath()
        }
    }
}
