import Foundation
import ArcusGeometry
import ArcusDomain

// STAIR: editing the sketch's components in Create Stair / Edit Stairs: select a run or landing; drag a run's end
// arrows to add or remove risers (whole treads), its side arrows to change its width from that side, or the run itself
// to move it; delete the selected component from the Options Bar.

extension StairTool {
    /// The selected run's grips: arrows at the start and end edges, and at the middle of each side.
    func grips() -> [(Vec2, Grip)] {
        guard case .run(let i)? = selection, let l = layout(), let r = l.runs.first(where: { $0.index == i }) else { return [] }
        let mid = r.walkPoint(r.walkLength / 2)
        func nearest(_ edge: [StairPathPoint]) -> Vec2 {
            let pts = edge.map(\.point)
            return zip(pts, pts.dropFirst()).map { Segment2($0, $1).closestPoint(to: mid) }.min { $0.distance(to: mid) < $1.distance(to: mid) } ?? mid
        }
        var out: [(Vec2, Grip)] = [(r.endEdge.midpoint, .end), (nearest(r.left), .widthLeft), (nearest(r.right), .widthRight)]
        if r.shape == .straight { out.append((r.startEdge.midpoint, .start)) }
        return out
    }

    func grip(at p: Vec2) -> (Vec2, Grip)? {
        let tol = ctx.pixel * 9
        return grips().filter { $0.0.distance(to: p) <= tol }.min { $0.0.distance(to: p) < $1.0.distance(to: p) }
    }

    func modifyDown(_ i: ToolInput) {
        if let (_, g) = grip(at: i.rawPoint) { beginDrag(g, i.point); return }
        if let k = runIndex(at: i.rawPoint) {
            if selection == .run(k) { beginDrag(.body, i.point) }
            selection = .run(k)
            return
        }
        if let l = layout(), let land = l.landings.first(where: { $0.polygon.contains(i.rawPoint) }) {
            if draft.landings == nil { draft.landings = (0..<max(0, runs.count - 1)).map { StairLanding(afterRun: $0) } }
            let index = land.index ?? draft.landings?.firstIndex { $0.afterRun == land.afterRun && $0.boundary == nil } ?? 0
            selection = .landing(index)
            return
        }
        selection = nil
    }

    func beginDrag(_ g: Grip, _ p: Vec2) {
        dragging = g
        dragStart = p
        dragBase = draft
    }

    public func pointerDragged(_ i: ToolInput) {
        guard modifying, let g = dragging, let base = dragBase, let p0 = dragStart, case .run(let k)? = selection,
              let src = base.runs?[k], let num = numbers else { return }
        let p = i.point
        var r = src
        let dir = src.directionVector, left = dir.perpendicular
        switch g {
        case .end:
            switch src.shape {
            case .straight:
                let along = (p - src.start).dot(dir)
                r.risers = max(2, Int((along / num.tread).rounded()) + 1)
            case .spiral:
                if let c = src.center {
                    let rad = src.start.distance(to: c)
                    let sigma: Double = src.turnsLeft ?? true ? 1 : -1
                    var sweep = Angle.normalize(((p - c).angle - (src.start - c).angle) * sigma)
                    if sweep < 1e-3 { sweep = 2 * .pi }
                    r.risers = max(2, Int((sweep * rad / num.tread).rounded()) + 1)
                }
            case .lWinder, .uWinder:
                if let l = StairGeometry.layout(probe(base), ctx.model), let lr = l.runs.first(where: { $0.index == k }) {
                    let delta = Int(((p - p0).dot(lr.endDirection) / num.tread).rounded())
                    r.risers = max(src.corners * src.winders + 2, src.risers + delta)
                }
            case .sketch: break
            }
        case .start:
            let end = src.start + dir * (Double(src.risers - 1) * num.tread)
            let along = (end - p).dot(dir)
            r.risers = max(2, Int((along / num.tread).rounded()) + 1)
            r.start = end - dir * (Double(r.risers - 1) * num.tread)
        case .widthLeft, .widthRight:
            let delta = (p - p0).dot(left) * (g == .widthLeft ? 1 : -1)
            let w = max(0.3, src.width + delta)
            let applied = w - src.width
            r.width = w
            if src.shape == .straight { r.start = src.start + left * (applied / 2 * (g == .widthLeft ? 1 : -1)) }
        case .body:
            let d = p - p0
            r.start = src.start + d
            r.center = src.center.map { $0 + d }
            if var s = src.sketch {
                let t = Transform2.translation(d)
                s.boundaries = s.boundaries.map { $0.transformed(t) }
                s.risers = s.risers.map { $0.transformed(t) }
                s.path = s.path.map { $0.transformed(t) }
                r.sketch = s
            }
        }
        var d = base
        d.runs?[k] = r
        draft = d
        if g == .end || g == .start, r.shape == .lWinder || r.shape == .uWinder { setRisers(k, r.risers) }
        rebuild()
    }

    public func pointerUp(_ i: ToolInput) {
        dragging = nil
        dragBase = nil
        dragStart = nil
        rebuild()
    }

    /// Deletes the selected run (with the landings and supports that belong to it) or landing.
    func deleteSelection() {
        switch selection {
        case .run(let i)?:
            guard runs.indices.contains(i) else { return }
            draft.runs?.remove(at: i)
            draft.landings = draft.landings?.compactMap { l in
                guard let a = l.afterRun else { return l }
                if a == i || a == i - 1 { return l.boundary == nil ? nil : StairLanding(afterRun: nil, boundary: l.boundary) }
                var x = l; x.afterRun = a > i ? a - 1 : a; return x
            }
            draft.supports = draft.supports?.compactMap { s in
                guard let r = s.run else { return s }
                if r == i { return nil }
                var x = s; x.run = r > i ? r - 1 : r; return x
            }
        case .landing(let k)?:
            if draft.landings == nil { draft.landings = (0..<max(0, runs.count - 1)).map { StairLanding(afterRun: $0) } }
            if draft.landings?.indices.contains(k) == true { draft.landings?.remove(at: k) }
        case nil: return
        }
        selection = nil
        rebuild()
    }

    /// Grips drawn as filled arrows: along the run at its ends, across it at its sides.
    func gripPrimitives() -> [GPrimitive] {
        guard case .run(let i)? = selection, let l = layout(), let r = l.runs.first(where: { $0.index == i }) else { return [] }
        let fill = GFill(pattern: .solid, color: RGBColor(0.11, 0.55, 0.95))
        let a = ctx.pixel * 7
        var out: [GPrimitive] = []
        func arrow(_ at: Vec2, _ d: Vec2, _ g: Grip) {
            let n = d.perpendicular
            let scale = (hoverGrip == g || dragging == g) ? 1.3 : 1
            out.append(.fill([Polygon2([at + d * a * scale, at - d * a * 0.4 * scale + n * a * 0.7 * scale, at - d * a * 0.4 * scale - n * a * 0.7 * scale])], fill))
        }
        for (p, g) in grips() {
            switch g {
            case .end: arrow(p + r.endDirection * a * 0.6, r.endDirection, g)
            case .start: arrow(p - r.direction * a * 0.6, -r.direction, g)
            case .widthLeft:
                let n = r.direction.perpendicular
                arrow(p + n * a * 0.6, n, g)
            case .widthRight:
                let n = -r.direction.perpendicular
                arrow(p + n * a * 0.6, n, g)
            case .body: break
            }
        }
        return out
    }
}
