import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// FMG4: Explode Parts in the live 3D view: each part's Mark tagged where the part is drawn (exploded), as the
// view's hidden-line image and its sheet show them; boxes are kept off each other, with a leader when moved.

/// Part tag anchors of an exploded view (model points), by model revision.
@MainActor final class ExplodeTagCache {
    static let shared = ExplodeTagCache()
    private var key: (UInt64, ElementID)?
    private var anchors: [(mark: String, at: Vec3)] = []

    func anchors(_ m: BIMModel, view: Element) -> [(mark: String, at: Vec3)] {
        if let k = key, k.0 == m.revision, k.1 == view.id { return anchors }
        let offsets = FurnitureExplode.offsets(m, view: view)
        var out: [(String, Vec3)] = []
        for (id, off) in offsets {
            guard let e = m[id], FurnitureExplode.tagged(e) else { continue }
            let b = ElementMeshes.bounds(e, m)
            guard !b.isEmpty else { continue }
            out.append((e.mark, (b.min + b.max) * 0.5 + off))
        }
        anchors = out.sorted { $0.0.localizedStandardCompare($1.0) == .orderedAscending }
        key = (m.revision, view.id)
        return anchors
    }
}

extension Viewport3DToolController {
    /// Tags on an exploded view's parts (the view's Explode Parts with Tag Parts on).
    func drawExplodeTags(_ cg: CGContext, viewport v: Viewport3DView) {
        guard let view = state.model[viewID], FurnitureExplode.isExploded(view), FurnitureExplode.showsTags(view) else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .foregroundColor: NSColor.black]
        var placed: [CGRect] = []
        cg.saveGState()
        defer { cg.restoreGState() }
        for a in ExplodeTagCache.shared.anchors(state.model, view: view) {
            guard let c = v.viewPoint(of: a.at) else { continue }
            let s = (a.mark as NSString).size(withAttributes: attrs)
            let w = s.width + 8, h = s.height + 2
            func rect(_ p: CGPoint) -> CGRect { CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h) }
            var at = c
            search: for ring in 0...6 {
                let candidates: [CGPoint] = ring == 0 ? [c] : (0..<8).map { k in
                    let ang = Double(k) * .pi / 4 + .pi / 2
                    return CGPoint(x: c.x + cos(ang) * (w + 4) * Double(ring), y: c.y + sin(ang) * (h + 4) * Double(ring))
                }
                for p in candidates where !placed.contains(where: { $0.insetBy(dx: -2, dy: -2).intersects(rect(p)) }) { at = p; break search }
            }
            let r = rect(at)
            placed.append(r)
            if hypot(at.x - c.x, at.y - c.y) > 0.5 {
                cg.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
                cg.setLineWidth(0.75)
                cg.move(to: CGPoint(x: min(max(c.x, r.minX), r.maxX), y: min(max(c.y, r.minY), r.maxY)))
                cg.addLine(to: c)
                cg.strokePath()
                cg.fillEllipse(in: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3))
            }
            cg.setFillColor(NSColor.white.withAlphaComponent(0.95).cgColor)
            cg.fill(r)
            cg.setStrokeColor(NSColor.black.cgColor)
            cg.setLineWidth(1)
            cg.stroke(r.insetBy(dx: 0.5, dy: 0.5))
            (a.mark as NSString).draw(at: CGPoint(x: r.minX + 4, y: r.minY + 1), withAttributes: attrs)
        }
    }
}
