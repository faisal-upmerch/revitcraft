import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// FM3D: what Furniture editing draws over a 3D view: shape handles (Revit's blue arrows) on the selected parts' faces,
// the part being stretched or moved as a dashed box with its size or move distance and the plane it snapped to, the
// temporary dimensions of one selected part, and the face or plane picked for Placement Plane ▸ Pick.

extension Viewport3DToolController {
    func drawFM3D(_ cg: CGContext, viewport v: Viewport3DView) {
        fm3d.handleHits = []
        fm3d.dimLabels = []
        guard fm3dDocument else { return }
        if state.activeTool != nil {
            if fm3d.pickingPlane, let p = lastMouse, let face = fm3dFace(at: p) { fm3dDrawFacePatch(face.point, face.normal, cg, v) }
            return
        }
        let m = state.model
        switch fm3d.drag {
        case .handle(let h, let value, let snap)?:
            if let e = m[h.elementID], var b = FurniturePartFaces.box(e, m) {
                Self.fm3dSetFace(&b, h.face, value)
                fm3dDrawBox(b, cg, v)
                fm3dDrawHandle(h, at: Self.fm3dFaceCenter(b, h.face), cg, v, emphasis: 2)
                let label = fm3dFormat(abs(value - h.opposite)) + (snap.map { "  (\($0.label))" } ?? "")
                if let q = v.viewPoint(of: Self.fm3dFaceCenter(b, h.face)) { fm3dDrawValue(label, at: CGPoint(x: q.x, y: q.y + 26), cg) }
            }
            return
        case .move(_, _, _, let box, let move, let snaps)?:
            let b = Box3(min: box.min + move, max: box.max + move)
            fm3dDrawBox(b, cg, v)
            for s in snaps { fm3dDrawSnapGuide(s.axis, s.snap.value, b, cg, v) }
            if let q = v.viewPoint(of: b.center) {
                fm3dDrawValue(fm3dFormat(move.length) + (snaps.isEmpty ? "" : "  (" + snaps.map(\.snap.label).joined(separator: ", ") + ")"), at: CGPoint(x: q.x, y: q.y + 20), cg)
            }
            return
        case nil: break
        }
        let parts = fm3dSelectedParts
        guard !parts.isEmpty else { return }
        for e in parts {
            for h in FurnitureShapeHandles.handles(e, m) { fm3dDrawHandle(h, at: h.position, cg, v, emphasis: h == fm3d.hoveredHandle ? 1 : 0) }
        }
        if parts.count == 1, fm3d.dimField == nil { for d in FurnitureTempDims3D.dims(parts[0], m) { fm3dDrawTempDim(d, cg, v) } }
    }

    // MARK: Pieces

    static func fm3dFaceCenter(_ b: Box3, _ f: PartFaceRef) -> Vec3 {
        var c = b.center
        let v = FurniturePlacements.component(f.atMax ? b.max : b.min, f.axis)
        switch f.axis { case .x: c.x = v; case .y: c.y = v; case .z: c.z = v }
        return c
    }

    static func fm3dSetFace(_ b: inout Box3, _ f: PartFaceRef, _ v: Double) {
        switch (f.axis, f.atMax) {
        case (.x, false): b.min.x = v
        case (.x, true): b.max.x = v
        case (.y, false): b.min.y = v
        case (.y, true): b.max.y = v
        case (.z, false): b.min.z = v
        case (.z, true): b.max.z = v
        }
    }

    /// A blue arrow out of a face (filled; hovered larger; dragged darker), recorded for hit testing.
    func fm3dDrawHandle(_ h: FurnitureShapeHandle, at p: Vec3, _ cg: CGContext, _ v: Viewport3DView, emphasis: Int) {
        guard let c = v.viewPoint(of: p), let q = v.viewPoint(of: p + h.direction * v.worldPerPoint(at: p) * 30) else { return }
        let dx = q.x - c.x, dy = q.y - c.y, len = hypot(dx, dy)
        guard len > 8 else { return } // pointing at the viewer
        let ux = dx / len, uy = dy / len
        let size: CGFloat = emphasis > 0 ? 1.25 : 1
        let base = CGPoint(x: c.x + ux * 6, y: c.y + uy * 6), tip = CGPoint(x: c.x + ux * 20 * size, y: c.y + uy * 20 * size)
        let nx = -uy * 6.5 * size, ny = ux * 6.5 * size
        let pts = [tip, CGPoint(x: base.x + nx, y: base.y + ny), CGPoint(x: base.x - nx, y: base.y - ny)]
        cg.saveGState()
        cg.addLines(between: pts); cg.closePath()
        let fill = emphasis == 2 ? NSColor(srgbRed: 0.1, green: 0.3, blue: 0.75, alpha: 1) : NSColor(srgbRed: 0.2, green: 0.45, blue: 0.95, alpha: 1)
        cg.setFillColor(fill.cgColor)
        cg.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 1.5, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        cg.fillPath()
        cg.setShadow(offset: .zero, blur: 0, color: nil)
        cg.addLines(between: pts); cg.closePath()
        cg.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
        cg.setLineWidth(1.2)
        cg.strokePath()
        cg.restoreGState()
        let r = CGRect(points: pts).insetBy(dx: -3, dy: -3)
        fm3d.handleHits.append((h, r))
    }

    /// A box as dashed blue edges (the part where it's going).
    func fm3dDrawBox(_ b: Box3, _ cg: CGContext, _ v: Viewport3DView) {
        let c = b.corners
        guard c.count == 8 else { return }
        cg.saveGState()
        cg.setStrokeColor(NSColor(srgbRed: 0.2, green: 0.45, blue: 0.95, alpha: 1).cgColor)
        cg.setLineWidth(1.5)
        cg.setLineDash(phase: 0, lengths: [6, 3])
        for (i, j) in Self.fm3dBoxEdges(b) { if let (p, q) = v.viewSegment(i, j) { cg.move(to: p); cg.addLine(to: q) } }
        cg.strokePath()
        cg.restoreGState()
    }

    static func fm3dBoxEdges(_ b: Box3) -> [(Vec3, Vec3)] {
        let xs = [b.min.x, b.max.x], ys = [b.min.y, b.max.y], zs = [b.min.z, b.max.z]
        var out: [(Vec3, Vec3)] = []
        for y in ys { for z in zs { out.append((Vec3(xs[0], y, z), Vec3(xs[1], y, z))) } }
        for x in xs { for z in zs { out.append((Vec3(x, ys[0], z), Vec3(x, ys[1], z))) } }
        for x in xs { for y in ys { out.append((Vec3(x, y, zs[0]), Vec3(x, y, zs[1]))) } }
        return out
    }

    /// The plane a moved part snapped to, as a dashed line through the box's middle on that plane.
    func fm3dDrawSnapGuide(_ a: FamilyAxis, _ value: Double, _ b: Box3, _ cg: CGContext, _ v: Viewport3DView) {
        let other = FamilyAxis.allCases.filter { $0 != a }
        guard let far = other.max(by: { FurniturePlacements.component(b.size, $0) < FurniturePlacements.component(b.size, $1) }) else { return }
        var p = b.center, q = b.center
        switch a { case .x: p.x = value; q.x = value; case .y: p.y = value; q.y = value; case .z: p.z = value; q.z = value }
        let reach = max(FurniturePlacements.component(b.size, far), 0.1)
        p = p - FurniturePlacements.unit(far) * reach
        q = q + FurniturePlacements.unit(far) * reach
        cg.saveGState()
        cg.setStrokeColor(NSColor(srgbRed: 120 / 255, green: 170 / 255, blue: 230 / 255, alpha: 1).cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [12, 3, 2, 3])
        if let (s, e) = v.viewSegment(p, q) { cg.move(to: s); cg.addLine(to: e); cg.strokePath() }
        cg.restoreGState()
    }

    /// A temporary dimension: a thin line from the reference to the face with its value in a box (click to type).
    func fm3dDrawTempDim(_ d: FurnitureTempDim3D, _ cg: CGContext, _ v: Viewport3DView) {
        guard let (a, b) = v.viewSegment(d.from, d.to), hypot(b.x - a.x, b.y - a.y) > 14 else { return }
        cg.saveGState()
        cg.setStrokeColor(TempDimLabelStyle.lineColor.cgColor)
        cg.setLineWidth(1)
        cg.move(to: a); cg.addLine(to: b)
        for e in [a, b] { cg.addEllipse(in: CGRect(x: e.x - 1.5, y: e.y - 1.5, width: 3, height: 3)) }
        cg.strokePath()
        cg.restoreGState()
        let text = fm3dFormat(d.value)
        let size = (text as NSString).size(withAttributes: TempDimLabelStyle.attributes(active: false))
        let box = TempDimLabelStyle.box(size: size, mid: CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + 9))
        TempDimLabelStyle.draw(text, in: box, active: false, highlighted: false, canvas: .windowBackgroundColor)
        fm3d.dimLabels.append((d, box))
    }

    /// A value in the temporary-dimension style.
    func fm3dDrawValue(_ text: String, at mid: CGPoint, _ cg: CGContext) {
        let size = (text as NSString).size(withAttributes: TempDimLabelStyle.attributes(active: true))
        TempDimLabelStyle.draw(text, in: TempDimLabelStyle.box(size: size, mid: mid), active: true, highlighted: false, canvas: .windowBackgroundColor)
    }

    /// The face under the pointer while picking a plane: a translucent patch on it.
    func fm3dDrawFacePatch(_ p: Vec3, _ n: Vec3, _ cg: CGContext, _ v: Viewport3DView) {
        let f = FacePlanes.frame(normal: n, origin: p)
        let r = v.worldPerPoint(at: p) * 40
        let pts = [f.point(-r, -r), f.point(r, -r), f.point(r, r), f.point(-r, r)].compactMap { v.viewPoint(of: $0) }
        guard pts.count == 4 else { return }
        cg.saveGState()
        cg.addLines(between: pts); cg.closePath()
        cg.setFillColor(NSColor(srgbRed: 110 / 255, green: 170 / 255, blue: 235 / 255, alpha: 0.35).cgColor)
        cg.fillPath()
        cg.addLines(between: pts); cg.closePath()
        cg.setStrokeColor(NSColor(srgbRed: 60 / 255, green: 130 / 255, blue: 220 / 255, alpha: 1).cgColor)
        cg.setLineWidth(1.5)
        cg.strokePath()
        cg.restoreGState()
    }
}

private extension CGRect {
    init(points: [CGPoint]) {
        let xs = points.map(\.x), ys = points.map(\.y)
        self.init(x: xs.min() ?? 0, y: ys.min() ?? 0, width: (xs.max() ?? 0) - (xs.min() ?? 0), height: (ys.max() ?? 0) - (ys.min() ?? 0))
    }
}
