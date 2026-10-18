import Foundation
import ArcusGeometry
import ArcusDomain

// I4: RevitCraft's datum grips (crates/rc-app grips.rs). Grid ends are hollow for model (3D) extents and filled for
// 2D extents in the view, with a 3D/2D switch, Add Elbow and an alignment lock where ends line up. Sections get end,
// far-clip and flip grips.

extension GripService {
    /// Where the elbow control sits while a bubble has no elbow (beside the bubble), and how far a new elbow jogs it.
    static let elbowOffsetPaper = 0.008

    /// Grid end grips in a plan view, at the ends as drawn there; `isOn` = the end has 2D extents in that view.
    /// A bubble with an elbow adds the elbow's drag grip.
    static func gridGrips(_ id: ElementID, _ g: GridData, viewID: ElementID?) -> [Grip] {
        let c = g.curve(in: viewID)
        let x = g.extent(in: viewID)
        var out = [Grip(elementID: id, kind: .start, position: c.start, isOn: x?.start != nil, viewID: viewID),
                   Grip(elementID: id, kind: .end, position: c.end, isOn: x?.end != nil, viewID: viewID)]
        if case .line(let s) = c {
            let d = s.direction
            // The elbow grip sits where the jog meets the bubble: dragging it across the grid sets the offset.
            if g.bubbleAtStart, let o = x?.elbowStart { out.append(Grip(elementID: id, kind: .gridElbow(atEnd: false), position: s.start + o, direction: -d, viewID: viewID)) }
            if g.bubbleAtEnd, let o = x?.elbowEnd { out.append(Grip(elementID: id, kind: .gridElbow(atEnd: true), position: s.end + o, direction: d, viewID: viewID)) }
        }
        return out
    }

    /// Section in a plan: its two ends and the far-clip triangle (the depth beyond the line, toward the view).
    static func sectionGrips(_ id: ElementID, _ vd: ViewData) -> [Grip] {
        guard let line = sectionLine(vd) else { return [] }
        let mid = (line.a + line.b) * 0.5
        return [Grip(elementID: id, kind: .sectionEnd(true), position: line.a),
                Grip(elementID: id, kind: .sectionEnd(false), position: line.b),
                Grip(elementID: id, kind: .sectionDepth, position: mid + line.forward * vd.farClip, direction: line.forward)]
    }

    static func sectionControls(_ id: ElementID, _ vd: ViewData, pixel: Double) -> [Grip] {
        guard let line = sectionLine(vd) else { return [] }
        let mid = (line.a + line.b) * 0.5
        return [Grip(elementID: id, kind: .flipSection, position: mid - line.forward * (18 * pixel), direction: line.forward)]
    }

    /// A section's line in plan: crop left and right along the view's right vector, through the plane origin.
    static func sectionLine(_ vd: ViewData) -> (a: Vec2, b: Vec2, forward: Vec2, right: Vec2, origin: Vec2)? {
        guard let o = vd.planeOrigin, let f = vd.viewDirection?.normalized, let r = vd.rightVector else { return nil }
        let crop = vd.cropRegion ?? Rect2(min: Vec2(-5, 0), max: Vec2(5, 10))
        return (o.xy + r * crop.min.x, o.xy + r * crop.max.x, f, r, o.xy)
    }

    /// Grid end controls: the 3D/2D switch beside each end, Add Elbow beside a shown bubble that has none, and the
    /// padlock where the end lines up with another grid's.
    static func gridControls(_ e: Element, _ g: GridData, _ model: BIMModel, view: Element?, pixel: Double, bubbleRadius r: Double) -> [Grip] {
        guard case .line(let s) = g.curve(in: view?.id) else { return [] }
        let d = s.direction, n = d.perpendicular
        let x = g.extent(in: view?.id)
        var out: [Grip] = []
        for atEnd in [false, true] {
            let p = atEnd ? s.end : s.start
            let outward = atEnd ? d : -d
            let side = outward.perpendicular
            out.append(Grip(elementID: e.id, kind: .gridExtents(atEnd: atEnd), position: p + side * (14 * pixel) - outward * (2 * pixel),
                            direction: outward, isOn: (atEnd ? x?.end : x?.start) != nil, viewID: view?.id))
            let bubble = atEnd ? g.bubbleAtEnd : g.bubbleAtStart
            if bubble, (atEnd ? x?.elbowEnd : x?.elbowStart) == nil {
                out.append(Grip(elementID: e.id, kind: .addElbow(atEnd: atEnd), position: p - n * (r + 10 * pixel) + outward * r,
                                direction: outward, viewID: view?.id))
            }
            if !alignedGridEnds(e.id, atEnd: atEnd, model, viewID: view?.id).isEmpty {
                out.append(Grip(elementID: e.id, kind: .gridLock(atEnd: atEnd), position: p - outward * (18 * pixel) - side * (12 * pixel),
                                direction: outward, isOn: g.isLocked(atEnd: atEnd), viewID: view?.id))
            }
        }
        return out
    }

    /// Ends of other straight grids parallel to `id` whose end lies level with its end (RevitCraft `aligned_grids`).
    public static func alignedGridEnds(_ id: ElementID, atEnd: Bool, _ model: BIMModel, viewID: ElementID?) -> [(ElementID, Bool)] {
        guard let g = model[id]?.grid, case .line(let s) = g.curve(in: viewID) else { return [] }
        let d = s.direction, end = atEnd ? s.end : s.start
        var out: [(ElementID, Bool)] = []
        for o in model.elements(.grids) where o.id != id {
            guard let og = o.grid, case .line(let os) = og.curve(in: viewID), abs(os.direction.cross(d)) < 1e-3 else { continue }
            for (oe, q) in [(false, os.start), (true, os.end)] where abs((q - end).dot(d)) < 0.001 { out.append((o.id, oe)) }
        }
        return out
    }

    /// Grid ends (2D in the view, or 3D with locked aligned ends following), elbows and section grips.
    static func applyDatum(_ g: Grip, to p: Vec2, in tx: TransactionContext) -> Bool {
        guard let e = tx.model[g.elementID] else { return false }
        switch (e.data, g.kind) {
        case (.grid(let gd), .start), (.grid(let gd), .end):
            let atEnd = g.kind == .end
            if let v = g.viewID, (atEnd ? gd.extent(in: v)?.end : gd.extent(in: v)?.start) != nil {
                tx.update(e.id) { el in el.grid?.updateExtent(in: v) { if atEnd { $0.end = p } else { $0.start = p } } }
                return true
            }
            // 3D: the model end moves; ends locked to it move along the grid by the same amount.
            let old = atEnd ? gd.curve.end : gd.curve.start
            let followers = gd.isLocked(atEnd: atEnd) ? alignedGridEnds(e.id, atEnd: atEnd, tx.model, viewID: nil) : []
            tx.update(e.id) { el in if let c = el.grid?.curve { el.grid?.curve = atEnd ? replaceEnd(c, end: p) : replaceEnd(c, start: p) } }
            if case .line(let s) = gd.curve {
                let shift = (p - old).dot(s.direction)
                for (oid, oe) in followers {
                    tx.update(oid) { el in
                        guard let c = el.grid?.curve, case .line(let os) = c else { return }
                        let sign = os.direction.dot(s.direction) >= 0 ? 1.0 : -1.0
                        let q = (oe ? os.end : os.start) + os.direction * (shift * sign)
                        el.grid?.curve = oe ? replaceEnd(c, end: q) : replaceEnd(c, start: q)
                    }
                }
            }
            return true
        case (.grid(let gd), .gridElbow(let atEnd)):
            guard let v = g.viewID, case .line(let s) = gd.curve(in: v) else { return true }
            let end = atEnd ? s.end : s.start, n = s.direction.perpendicular
            let o = n * (p - end).dot(n)
            tx.update(e.id) { el in el.grid?.updateExtent(in: v) { if atEnd { $0.elbowEnd = o } else { $0.elbowStart = o } } }
            return true
        case (.view(let vd), .sectionEnd(let isStart)):
            guard let line = sectionLine(vd) else { return true }
            let u = (p - line.origin).dot(line.right)
            tx.update(e.id) { el in
                var crop = vd.cropRegion ?? Rect2(min: Vec2(-5, 0), max: Vec2(5, 10))
                if isStart { crop.min.x = min(u, crop.max.x - 0.1) } else { crop.max.x = max(u, crop.min.x + 0.1) }
                el.view?.cropRegion = crop
            }
            return true
        case (.view(let vd), .sectionDepth):
            guard let line = sectionLine(vd) else { return true }
            let depth = max(0.1, (p - (line.a + line.b) * 0.5).dot(line.forward))
            tx.update(e.id) { el in el.view?.farClip = depth }
            return true
        default:
            return false
        }
    }

    static func isLocked(_ e: Element, atEnd: Bool) -> Bool { e.grid?.isLocked(atEnd: atEnd) ?? false }

    /// I4 control clicks: the 3D/2D switch, Add Elbow, the alignment lock and the section flip.
    static func toggleDatum(_ g: Grip, in tx: TransactionContext) -> Bool {
        guard let e = tx.model[g.elementID] else { return false }
        switch (e.data, g.kind) {
        case (.grid(let gd), .gridExtents(let atEnd)):
            guard let v = g.viewID else { return true }
            let c = gd.curve(in: v)
            tx.update(e.id) { el in
                el.grid?.updateExtent(in: v) { x in
                    if atEnd { x.end = x.end == nil ? c.end : nil } else { x.start = x.start == nil ? c.start : nil }
                }
            }
            return true
        case (.grid(let gd), .addElbow(let atEnd)):
            guard let v = g.viewID, case .line(let s) = gd.curve(in: v) else { return true }
            let scale = Double(tx.model[v]?.view?.scale ?? 100)
            let o = s.direction.perpendicular * -(elbowOffsetPaper * scale)
            tx.update(e.id) { el in el.grid?.updateExtent(in: v) { if atEnd { $0.elbowEnd = o } else { $0.elbowStart = o } } }
            return true
        case (.grid, .gridLock(let atEnd)):
            let locked = isLocked(e, atEnd: atEnd)
            tx.update(e.id) { el in if atEnd { el.grid?.lockEnd = !locked } else { el.grid?.lockStart = !locked } }
            return true
        case (.view(let vd), .flipSection):
            // Look the other way; the line stays where it is (the right vector turns with the view direction).
            tx.update(e.id) { el in
                guard let f = vd.viewDirection else { return }
                el.view?.viewDirection = -f
                if let c = vd.cropRegion { el.view?.cropRegion = Rect2(min: Vec2(-c.max.x, c.min.y), max: Vec2(-c.min.x, c.max.y)) }
            }
            return true
        default:
            return false
        }
    }
}
