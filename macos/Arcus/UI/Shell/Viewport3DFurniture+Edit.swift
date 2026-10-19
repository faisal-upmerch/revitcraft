import AppKit
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// FM3D: editing Furniture parts in a 3D view without a tool, as Revit edits family solids in 3D: shape handles (blue
// arrows on the faces of the selected parts; drag to stretch, snapping to planes and part faces), dragging selected
// parts in the plane of the face grabbed (faces snap to planes and other parts), temporary dimensions to the nearest
// plane or part on each axis (click the value, type a distance), and Tab to step through the elements stacked under
// the pointer. Orbit, pan and the orientation cube are untouched: only presses on a handle, a value or a selected
// part are taken.

extension Viewport3DToolController {
    /// Selected parts shape handles and temporary dimensions are shown for (up to four).
    var fm3dSelectedParts: [Element] {
        let sel = state.session.selection.ids.compactMap { state.model[$0] }
        guard !sel.isEmpty, sel.count <= 4, sel.allSatisfy({ $0.category.isFurniturePart }) else { return [] }
        return sel
    }

    /// The overlay has something of FM3D to draw (it then follows the camera).
    var fm3dShowsOverlay: Bool { fm3dDocument && (!fm3dSelectedParts.isEmpty || fm3d.drag != nil) }

    // MARK: Pointer

    func fm3dMouseDown(_ event: NSEvent, at p: CGPoint) -> Bool {
        guard fm3dDocument else { return false }
        if state.activeTool != nil {
            guard fm3d.pickingPlane else { return false }
            fm3dFinishPickingPlane(at: p)
            return true
        }
        if fm3d.dimField != nil { fm3dEndDimEdit(commit: false) }
        if let t = fm3d.tab, hypot(p.x - t.at.x, p.y - t.at.y) <= 3 {
            state.session.selection.click(t.ids[t.index], shift: event.modifierFlags.contains(.shift), command: event.modifierFlags.contains(.command))
            fm3d.tab = nil
            return true
        }
        fm3d.tab = nil
        if let d = fm3d.dimLabels.first(where: { $0.rect.contains(p) }) { fm3dBeginDimEdit(d.dim, at: d.rect); return true }
        if let h = fm3d.handleHits.first(where: { $0.rect.contains(p) })?.handle {
            fm3d.drag = .handle(h, value: h.value, snap: nil)
            state.hoverDescription = "Drag the face; it snaps to planes and parts."
            return true
        }
        guard event.clickCount < 2, !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.command), let v = viewport, !fm3dSelectedParts.isEmpty else { return false }
        let hit = v.pick(at: p)
        guard let id = hit.id, let grab = hit.position, state.session.selection.contains(id) else { return false }
        fm3d.pending = (id, grab, event.modifierFlags, p)
        return true
    }

    func fm3dMouseDragged(_ event: NSEvent, at p: CGPoint) -> Bool {
        guard fm3dDocument, state.activeTool == nil else { return false }
        if let pend = fm3d.pending {
            guard hypot(p.x - pend.at.x, p.y - pend.at.y) > 3 else { return true }
            fm3d.pending = nil
            fm3dBeginMove(grab: pend.grab, at: pend.at)
        }
        guard let drag = fm3d.drag, let v = viewport else { return false }
        switch drag {
        case .handle(let h, _, _):
            var value = fm3dAxisValue(h, at: p) ?? h.value
            let tol = v.worldPerPoint(at: h.position) * 8
            let snap = FurnitureAxisSnaps.nearest(value, FurnitureAxisSnaps.candidates(along: h.axis, excluding: [h.elementID], state.model), tolerance: tol)
            if let s = snap { value = s.value }
            fm3d.drag = .handle(h, value: value, snap: snap)
            state.hoverDescription = "Size \(fm3dFormat(abs(value - h.opposite)))" + (snap.map { ", on \($0.label)" } ?? "")
        case .move(let ids, let grab, let n, let box, _, _):
            let ray = v.pointerRay(at: p)
            let f = FacePlanes.frame(normal: n, origin: grab)
            guard let w = f.intersect(origin: ray.origin, direction: ray.direction) else { return true }
            var d = w - grab
            let axes = FamilyAxis.allCases.filter { abs(FurniturePlacements.component(n, $0)) < 1e-3 }
            if event.modifierFlags.contains(.shift), let a = axes.max(by: { abs(FurniturePlacements.component(d, $0)) < abs(FurniturePlacements.component(d, $1)) }) {
                d = FurniturePlacements.unit(a) * FurniturePlacements.component(d, a)
            }
            let cands = Dictionary(uniqueKeysWithValues: axes.map { ($0, FurnitureAxisSnaps.candidates(along: $0, excluding: Set(ids), state.model)) })
            let r = FurnitureMove3D.snap(box, by: d, axes: axes, candidates: cands, tolerance: v.worldPerPoint(at: grab) * 8)
            fm3d.drag = .move(ids: ids, grab: grab, normal: n, box: box, move: r.move, snaps: r.snaps)
            state.hoverDescription = "Move \(fm3dFormat(r.move.length))" + (r.snaps.isEmpty ? "" : ", on " + r.snaps.map(\.snap.label).joined(separator: ", "))
        }
        overlay.needsDisplay = true
        return true
    }

    func fm3dMouseUp(_ event: NSEvent, at p: CGPoint) -> Bool {
        guard fm3dDocument, state.activeTool == nil else { return false }
        if let pend = fm3d.pending {
            fm3d.pending = nil
            state.session.selection.click(pend.id, shift: pend.flags.contains(.shift), command: pend.flags.contains(.command))
            return true
        }
        guard let drag = fm3d.drag else { return false }
        fm3d.drag = nil
        state.hoverDescription = ""
        switch drag {
        case .handle(let h, let value, _):
            guard abs(value - h.value) > 1e-7 else { break }
            state.session.perform("Drag Shape Handle") { tx in try FurnitureShapeHandles.stretch(h, to: value, in: tx) }
        case .move(let ids, _, _, _, let move, _):
            guard move.length > 1e-7 else { break }
            let plan = FurniturePlacements.planHost(state.model)
            state.session.perform("Move") { tx in try FurnitureMove3D.translate(ids, by: move, plan: plan, in: tx) }
        }
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
        overlay.needsDisplay = true
        return true
    }

    /// True to keep the event from the viewport (a shape handle under the pointer, a Tab choice held).
    func fm3dMouseMoved(_ event: NSEvent, at p: CGPoint) -> Bool {
        guard fm3dDocument else { return false }
        if state.activeTool != nil { fm3dRetarget(at: p); return false }
        if let t = fm3d.tab {
            if hypot(p.x - t.at.x, p.y - t.at.y) <= 3 { return true }
            fm3d.tab = nil
        }
        let h = fm3d.handleHits.first { $0.rect.contains(p) }?.handle
        if h != fm3d.hoveredHandle { fm3d.hoveredHandle = h; overlay.needsDisplay = true }
        guard h != nil else { return false }
        state.session.selection.preselection = nil
        state.hoverDescription = "Drag to stretch the part. A face on a reference plane moves the plane."
        NSCursor.openHand.set()
        return true
    }

    /// Tab steps through what's under the pointer; Escape drops a drag or the plane pick.
    func fm3dKeyDown(_ event: NSEvent) -> Bool {
        guard fm3dDocument else { return false }
        switch event.keyCode {
        case 53:
            if fm3d.drag != nil || fm3d.pending != nil { fm3d.drag = nil; fm3d.pending = nil; state.hoverDescription = ""; overlay.needsDisplay = true; return true }
            if fm3d.pickingPlane { fm3d.pickingPlane = false; overlay.needsDisplay = true; return true }
            return false
        case 48 where state.activeTool == nil:
            guard let p = lastMouseForFM3D else { return false }
            if var t = fm3d.tab, hypot(p.x - t.at.x, p.y - t.at.y) <= 3 {
                t.index = (t.index + 1) % t.ids.count
                fm3d.tab = t
            } else {
                let ids = fm3dStack(at: p)
                guard ids.count > 1 else { return false }
                fm3d.tab = (ids, 1, p)
            }
            guard let t = fm3d.tab else { return false }
            let id = t.ids[t.index]
            state.session.selection.preselection = id
            let name = state.model[id].map { e in e.mark.isEmpty ? e.category.singularName : "\(e.category.singularName) \(e.mark)" } ?? ""
            state.hoverDescription = "\(name) (\(t.index + 1) of \(t.ids.count)). Tab for the next; click to select."
            return true
        default:
            return false
        }
    }

    /// The pointer's last position over the view.
    var lastMouseForFM3D: CGPoint? {
        guard let v = viewport, let w = v.window else { return nil }
        let p = v.convert(w.mouseLocationOutsideOfEventStream, from: nil)
        return v.bounds.contains(p) ? p : nil
    }

    // MARK: Moves and handles

    private func fm3dBeginMove(grab: Vec3, at p: CGPoint) {
        let parts = fm3dSelectedParts
        guard !parts.isEmpty, let face = fm3dFace(at: p) else { return }
        let box = parts.compactMap { FurniturePartFaces.box($0, state.model) }.reduce(Box3.empty) { $0.union($1) }
        guard !box.isEmpty else { return }
        fm3d.drag = .move(ids: parts.map(\.id), grab: grab, normal: face.normal, box: box, move: .zero, snaps: [])
    }

    /// Where the pointer is along a handle's axis (the nearest point of the axis line to the pointer ray).
    func fm3dAxisValue(_ h: FurnitureShapeHandle, at p: CGPoint) -> Double? {
        guard let v = viewport else { return nil }
        let a = FurniturePlacements.unit(h.axis), ray = v.pointerRay(at: p)
        let w0 = h.position - ray.origin
        let b = a.dot(ray.direction), c = ray.direction.dot(ray.direction), d = a.dot(w0), e = ray.direction.dot(w0)
        let denom = c - b * b
        guard abs(denom) > 1e-9 else { return nil }
        return h.value + (b * e - c * d) / denom
    }

    /// Elements under a view point, nearest first (Tab).
    func fm3dStack(at p: CGPoint) -> [ElementID] {
        guard let v = viewport else { return [] }
        let ray = v.pointerRay(at: p), m = state.model
        var hits: [(ElementID, Double)] = []
        for id in v.sceneElementIDs {
            guard let e = m[id], state.session.selection.allows(e) else { continue }
            let b = ElementMeshes.bounds(e, m)
            guard !b.isEmpty, Self.fm3dRayHitsBox(ray.origin, ray.direction, b.expanded(by: 1e-3)) else { continue }
            var best = Double.infinity
            for part in GeometryCache.shared.parts(e, m, detail: .medium) where part.isVisibleIn3D {
                if let t = Self.fm3dRayHitsMesh(ray.origin, ray.direction, part.mesh) { best = min(best, t) }
            }
            if best.isFinite { hits.append((id, best)) }
        }
        return hits.sorted { $0.1 < $1.1 }.map(\.0)
    }

    static func fm3dRayHitsBox(_ o: Vec3, _ d: Vec3, _ b: Box3) -> Bool {
        var t0 = -Double.infinity, t1 = Double.infinity
        for a in FamilyAxis.allCases {
            let oa = FurniturePlacements.component(o, a), da = FurniturePlacements.component(d, a)
            let lo = FurniturePlacements.component(b.min, a), hi = FurniturePlacements.component(b.max, a)
            if abs(da) < 1e-12 { if oa < lo || oa > hi { return false }; continue }
            let ta = (lo - oa) / da, tb = (hi - oa) / da
            t0 = max(t0, min(ta, tb)); t1 = min(t1, max(ta, tb))
        }
        return t1 >= max(t0, 0)
    }

    /// The nearest ray parameter where the ray meets the mesh (Möller–Trumbore).
    static func fm3dRayHitsMesh(_ o: Vec3, _ d: Vec3, _ m: Mesh) -> Double? {
        var best: Double?
        var i = 0
        while i + 2 < m.indices.count {
            let a = m.positions[Int(m.indices[i])], b = m.positions[Int(m.indices[i + 1])], c = m.positions[Int(m.indices[i + 2])]
            i += 3
            let e1 = b - a, e2 = c - a, pv = d.cross(e2), det = e1.dot(pv)
            guard abs(det) > 1e-14 else { continue }
            let inv = 1 / det, tv = o - a, u = tv.dot(pv) * inv
            guard u >= 0, u <= 1 else { continue }
            let q = tv.cross(e1), w = d.dot(q) * inv
            guard w >= 0, u + w <= 1 else { continue }
            let t = e2.dot(q) * inv
            if t > 1e-9, best.map({ t < $0 }) ?? true { best = t }
        }
        return best
    }

    // MARK: Temporary dimension values

    func fm3dFormat(_ v: Double) -> String { QuantityFormatter.format(v, kind: .length, units: state.model.units) }

    private func fm3dBeginDimEdit(_ d: FurnitureTempDim3D, at rect: CGRect) {
        guard let host else { return }
        fm3d.dimField?.removeFromSuperview()
        let f = NSTextField(string: fm3dFormat(d.value))
        f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        f.bezelStyle = .roundedBezel
        f.target = self
        f.action = #selector(fm3dDimCommitted(_:))
        f.setAccessibilityLabel("Distance to \(d.reference)")
        f.frame = NSRect(x: rect.midX - 55, y: rect.midY - 11, width: 110, height: 22)
        host.addSubview(f, positioned: .above, relativeTo: overlay)
        host.window?.makeFirstResponder(f)
        f.currentEditor()?.selectAll(nil)
        fm3d.dimField = f
        fm3d.dimEditing = d
    }

    @objc private func fm3dDimCommitted(_ sender: NSTextField) { fm3dEndDimEdit(commit: true) }

    func fm3dEndDimEdit(commit: Bool) {
        guard let f = fm3d.dimField else { return }
        let text = f.stringValue, dim = fm3d.dimEditing
        f.removeFromSuperview()
        fm3d.dimField = nil
        fm3d.dimEditing = nil
        if let v = viewport { v.window?.makeFirstResponder(v) }
        guard commit, let d = dim else { return }
        guard let value = try? QuantityParser.parse(text, kind: .length, units: state.model.units), value >= 0 else {
            state.show("“\(text)” is not a valid distance.", error: true); return
        }
        let move = FurnitureTempDims3D.move(for: d, to: value)
        let plan = FurniturePlacements.planHost(state.model)
        state.session.perform("Move") { tx in try FurnitureMove3D.translate([d.elementID], by: move, plan: plan, in: tx) }
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
        overlay.needsDisplay = true
    }
}
