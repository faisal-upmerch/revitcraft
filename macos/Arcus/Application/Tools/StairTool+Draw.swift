import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// STAIR: drawing runs, landings, supports and sketched runs in Create Stair, and the sketch's preview.

extension StairTool {
    public var prompt: String {
        if modifying {
            switch selection {
            case .run?: return "Drag a run's end arrows to add or remove risers, its side arrows to change its width, or the run to move it."
            case .landing?: return "Delete the landing in the Options Bar, or pick another component."
            case nil: return "Select a run or landing to edit it, or choose a Run, Landing or Support tool. Finish Edit Mode creates the stair."
            }
        }
        if runSketch != nil {
            switch sketchLine {
            case .boundary: return chain.isEmpty ? "Click the start of a boundary line (draw the left and right boundaries)." : "Click the next point of the boundary; Esc ends the line."
            case .riser: return chain.isEmpty ? "Click the start of a riser line." : "Click the end of the riser line."
            case .path: return chain.isEmpty ? "Click the start of the stair path, at the bottom of the stair." : "Click the next point of the stair path; Esc ends it."
            }
        }
        switch component {
        case .run:
            switch runMode {
            case .straight: return clicks.isEmpty ? "Click the start of the run." : "Click the end of the run, or type its length."
            case .fullStepSpiral: return clicks.isEmpty ? "Click the centre of the spiral." : "Click the start of the run to set the radius. Space reverses the turn."
            case .centerEndsSpiral:
                return clicks.isEmpty ? "Click the centre of the spiral." : clicks.count == 1 ? "Click the start of the run." : "Click the end of the run. Space reverses the turn."
            case .lWinder, .uWinder: return "Click the start of the run. Space rotates it."
            case .sketch: return "Draw boundary, riser and stair path lines."
            }
        case .landing:
            return landingMode == .pickTwoRuns ? (pickedRun == nil ? "Pick the first run." : "Pick the second run.")
                : (landingPoints.isEmpty ? "Click the first corner of the landing." : "Click the next corner; click the first corner (or Finish) to close the landing.")
        case .support: return "Pick a run edge to add a support (stringer) to it."
        }
    }

    // MARK: Pointer

    public func pointerMoved(_ i: ToolInput) {
        if modifying { hoverGrip = dragging == nil ? grip(at: i.rawPoint).map(\.1) : dragging; rebuild(); return }
        let p = snapped(i)
        current = p
        if runSketch == nil, component == .run, runMode == .centerEndsSpiral, clicks.count == 2 { trackSweep(p) }
        rebuild()
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Sketch stairs in a plan view."); return }
        if modifying { modifyDown(i); rebuild(); return }
        let p = snapped(i)
        if runSketch != nil { sketchClick(p); rebuild(); return }
        switch component {
        case .run: runClick(p)
        case .landing: landingClick(p, i)
        case .support: supportClick(i)
        }
        rebuild()
    }

    /// Where the next run could start: straight on, turned left or right after a landing (L), or back beside the last
    /// run (U); each as a point on the Location Line for the direction the run would take.
    public var startCandidates: [(point: Vec2, direction: Vec2)] {
        guard component == .run, clicks.isEmpty, let l = layout(), let last = l.runs.last else { return [] }
        let e = last.endEdge.midpoint, d = last.endDirection, n = d.perpendicular, w = last.width
        // Back beside the run (U), clear of both runs' stringers by 100 mm.
        let supports = [type.left, type.right].map { $0.kind == .stringerClosed ? $0.width + $0.lateralOffset : 0 }.reduce(0, +)
        let gap = 0.1 + supports
        // Straight on past a landing one run width deep; turned left or right (L); back beside the run (U).
        let centres: [(Vec2, Vec2)] = [(e + d * w, d), (e + d * (w / 2) + n * (w / 2), n), (e + d * (w / 2) - n * (w / 2), -n),
                                       (e + n * (w / 2 + width / 2 + gap), -d), (e - n * (w / 2 + width / 2 + gap), -d)]
        return centres.map { c, t in (c - t.perpendicular * centerOffset, t) }
    }

    /// Offset from the drawn path to the run centre line (toward the run's left).
    var centerOffset: Double {
        let side = locationLine == .exteriorSupportLeft ? type.left : type.right
        let sw = side.kind == .none ? 0 : side.width + side.lateralOffset
        return locationLine.centerOffset(width: width, supportWidth: sw) + offset
    }

    func snapped(_ i: ToolInput) -> Vec2 {
        if let c = startCandidates.min(by: { $0.point.distance(to: i.rawPoint) < $1.point.distance(to: i.rawPoint) }),
           c.point.distance(to: i.rawPoint) <= ctx.pixel * 12 { return c.point }
        return i.point
    }

    // MARK: Runs

    func runClick(_ p: Vec2) {
        switch runMode {
        case .straight:
            if clicks.isEmpty { clicks = [p] } else { placeStraight(to: p) }
        case .fullStepSpiral:
            if clicks.isEmpty { clicks = [p] } else if let r = spiralRun(center: clicks[0], start: p, sweep: nil) { add(r); clicks = [] }
        case .centerEndsSpiral:
            if clicks.count < 2 { clicks.append(p); if clicks.count == 2 { spiralSweep = 0; lastPointerAngle = nil } }
            else if let r = spiralRun(center: clicks[0], start: clicks[1], sweep: spiralSweep) { add(r); clicks = [] }
        case .lWinder, .uWinder:
            add(winderRun(at: p))
        case .sketch:
            if runSketch == nil { runSketch = StairRunSketch() }
        }
    }

    /// The straight run from the first click to `p`, its end snapped to whole treads.
    func straightRun(to p: Vec2) -> StairRun? {
        guard let s = clicks.first, let num = numbers else { return nil }
        let v = p - s
        guard v.length > num.tread * 0.5 else { return nil }
        let t = v.normalized
        let treads = max(1, Int((v.length / num.tread).rounded()))
        var r = StairRun(start: s + t.perpendicular * centerOffset, direction: t.angle, risers: treads + 1, width: width)
        r.locationLine = locationLine
        return r
    }

    func placeStraight(to p: Vec2) {
        guard let r = straightRun(to: p) else { return }
        add(r)
        clicks = []
    }

    /// A spiral run around `center` starting at `start`: Full-Step (all remaining risers) or Center-Ends (`sweep`).
    func spiralRun(center: Vec2, start: Vec2, sweep: Double?) -> StairRun? {
        guard let num = numbers else { return nil }
        let rClick = start.distance(to: center)
        let ccw = sweep.map { $0 >= 0 } ?? !spiralClockwise
        // Left of travel points to the centre when the spiral turns left.
        let toLeft = ccw ? (center - start).normalized : (start - center).normalized
        let s = start + toLeft * centerOffset
        let radius = s.distance(to: center)
        guard radius > width / 2 + 0.05, rClick > 1e-6 else { message("The spiral's radius must be more than half the run width."); return nil }
        var risers: Int
        if let sweep {
            risers = Int((abs(sweep) * radius / num.tread).rounded()) + 1
        } else {
            risers = remaining > 1 ? remaining : num.desired
        }
        risers = max(2, risers)
        let a = (s - center).angle
        var r = StairRun(shape: .spiral, start: s, direction: (Vec2.fromAngle(a).perpendicular * (ccw ? 1 : -1)).angle, risers: risers, width: width)
        r.center = center
        r.turnsLeft = ccw
        r.locationLine = locationLine
        return r
    }

    /// Follows the pointer round the centre so a Center-Ends sweep can pass 180°.
    func trackSweep(_ p: Vec2) {
        let c = clicks[0]
        let a = (p - c).angle
        let last = lastPointerAngle ?? (clicks[1] - c).angle
        spiralSweep += Angle.normalizeSigned(a - last)
        lastPointerAngle = a
        if spiralSweep.magnitude > 2 * .pi - 0.05 { spiralSweep = (2 * .pi - 0.05) * (spiralSweep < 0 ? -1 : 1) }
    }

    /// An L- or U-Shape Winder run starting at `p` with the remaining risers, legs shared evenly.
    func winderRun(at p: Vec2) -> StairRun {
        let num = numbers
        let base = layout()?.runs.last?.endDirection.angle ?? .pi / 2
        let dir = base + Double(winderTurns % 4) * .pi / 2
        let risers = max(remaining > 3 ? remaining : (num?.desired ?? 16), 6)
        let treads = risers - 1
        let u = runMode == .uWinder
        var r = StairRun(shape: u ? .uWinder : .lWinder, start: p + Vec2.fromAngle(dir).perpendicular * centerOffset, direction: dir,
                         risers: risers, width: width)
        r.turnsLeft = !spiralClockwise
        r.windersPerCorner = 3
        let straight = max(0, treads - (u ? 6 : 3))
        r.legTreads = u ? [straight / 2, 0] : [straight / 2]
        r.locationLine = locationLine
        return r
    }

    /// The run the pointer is drawing now (nil before its first click).
    var pendingRun: StairRun? {
        guard runSketch == nil, component == .run, !modifying, let c = current else { return nil }
        switch runMode {
        case .straight: return clicks.isEmpty ? nil : straightRun(to: c)
        case .fullStepSpiral: return clicks.isEmpty ? nil : spiralRun(center: clicks[0], start: c, sweep: nil)
        case .centerEndsSpiral: return clicks.count == 2 ? spiralRun(center: clicks[0], start: clicks[1], sweep: spiralSweep) : nil
        case .lWinder, .uWinder: return winderRun(at: c)
        case .sketch: return nil
        }
    }

    func setRisers(_ i: Int, _ n: Int) {
        guard var r = draft.runs?[i] else { return }
        r.risers = max(2, n)
        if r.shape == .lWinder || r.shape == .uWinder {
            r.legTreads = StairRunGeometryAccess.scaledLegs(r, treads: r.risers - 1)
        }
        draft.runs?[i] = r
    }

    // MARK: Landings

    /// Index of the run under (or nearest to, within a few pixels) a point.
    func runIndex(at p: Vec2) -> Int? {
        guard let l = layout() else { return nil }
        let tol = ctx.pixel * 8
        return l.runs.min { distance($0.outline, p) < distance($1.outline, p) }.flatMap { distance($0.outline, p) <= tol ? $0.index : nil }
    }
    func distance(_ poly: Polygon2, _ p: Vec2) -> Double { poly.contains(p) ? 0 : poly.distanceToBoundary(p) }

    func landingClick(_ p: Vec2, _ i: ToolInput) {
        switch landingMode {
        case .pickTwoRuns:
            guard let k = runIndex(at: i.rawPoint) else { message("Pick a run of the stair."); return }
            guard let a = pickedRun else { pickedRun = k; return }
            pickedRun = nil
            guard abs(a - k) == 1 else { message(a == k ? "Pick two different runs." : "Pick two runs that follow each other."); return }
            let after = min(a, k)
            guard let l = layout(), let ra = l.runs.first(where: { $0.index == after }), let rb = l.runs.first(where: { $0.index == after + 1 }),
                  StairGeometry.automaticLanding(ra, rb) != nil else { message("These runs already meet, or are too far apart for a landing."); return }
            var list = draft.landings ?? (0..<max(0, runs.count - 1)).map { StairLanding(afterRun: $0) }
            list.removeAll { $0.afterRun == after }
            list.append(StairLanding(afterRun: after))
            draft.landings = list.sorted { ($0.afterRun ?? Int.max) < ($1.afterRun ?? Int.max) }
        case .sketch:
            if landingPoints.count >= 3, p.distance(to: landingPoints[0]) <= ctx.pixel * 10 { closeLandingSketch(); return }
            if let last = landingPoints.last, last.distance(to: p) < 0.01 { return }
            landingPoints.append(p)
        }
    }

    /// Closes the landing sketch: the landing joins the runs whose ends it touches.
    func closeLandingSketch() {
        guard landingPoints.count >= 3 else { return }
        let poly = Polygon2(landingPoints)
        landingPoints = []
        guard !poly.isDegenerate, poly.isSimple else { message("The landing's boundary crosses itself."); return }
        var after: Int?
        if let l = layout() {
            for (k, r) in l.runs.enumerated() where k + 1 < l.runs.count {
                let next = l.runs[k + 1]
                if distance(poly, r.endEdge.midpoint) < 0.05 && distance(poly, next.startEdge.midpoint) < 0.05 { after = r.index; break }
            }
        }
        var list = draft.landings ?? (0..<max(0, runs.count - 1)).map { StairLanding(afterRun: $0) }
        if let a = after { list.removeAll { $0.afterRun == a } }
        list.append(StairLanding(afterRun: after, boundary: poly.counterClockwise.points))
        draft.landings = list
    }

    // MARK: Supports

    func supportClick(_ i: ToolInput) {
        guard let l = layout() else { message("Draw a run first."); return }
        let tol = ctx.pixel * 10
        var best: (Int, StairSupport.Side, Double)?
        for r in l.runs {
            for (side, edge) in [(StairSupport.Side.left, r.left), (.right, r.right)] {
                let pts = edge.map(\.point)
                let d = zip(pts, pts.dropFirst()).map { Segment2($0, $1).distance(to: i.rawPoint) }.min() ?? .infinity
                if d <= tol, d < (best?.2 ?? .infinity) { best = (r.index, side, d) }
            }
        }
        guard let (run, side, _) = best else { message("Pick the left or right edge of a run."); return }
        let typeSide = side == .left ? type.left : type.right
        if typeSide.kind != .none { message("The stair type already has a \(typeSide.kind.rawValue.lowercased()) on that side."); return }
        var list = draft.supports ?? []
        if let k = list.firstIndex(where: { $0.run == run && $0.side == side }) { list.remove(at: k) } else { list.append(StairSupport(run: run, side: side)) }
        draft.supports = list.isEmpty ? nil : list
    }

    // MARK: Sketched runs

    func sketchClick(_ p: Vec2) {
        guard var k = runSketch else { return }
        if let last = chain.last, last.distance(to: p) < 0.01 { return }
        if let last = chain.last {
            let seg = Curve2.line(Segment2(last, p))
            switch sketchLine {
            case .boundary: k.boundaries.append(seg); chain.append(p)
            case .path: k.path.append(seg); chain.append(p)
            case .riser: k.risers.append(seg); chain = []
            }
        } else {
            chain = [p]
        }
        runSketch = k
    }

    /// Finish in the run sketch: the sketched run joins the stair.
    func finishRunSketch() -> Bool {
        guard let k = runSketch else { return false }
        guard k.risers.count >= 2 else { message("Draw at least two riser lines."); return false }
        guard !k.path.isEmpty else { message("Draw the stair path from the bottom of the stair to the top."); return false }
        var r = StairRun(shape: .sketch, start: k.path[0].start, direction: k.path[0].tangent(at: 0).angle, risers: k.risers.count, width: width)
        r.sketch = k
        if let g = StairGeometry.layout(probe(StairData(origin: .zero, direction: 0).with(runs: [r])), ctx.model)?.runs.first {
            r.width = g.startEdge.length
            r.risers = g.risers
        }
        add(r)
        runSketch = nil
        chain = []
        runMode = .straight
        rebuild()
        return true
    }

    // MARK: Preview

    func rebuild() {
        preview = ToolPreview()
        preview.cursor = modifying ? ((hoverGrip ?? dragging) == nil ? .arrow : .move) : .crosshair
        var data = draft
        let pending = pendingRun
        if let p = pending { data.runs = (data.runs ?? []) + [p] }
        let l = layout(data)
        let blue = ctx.previewStroke, heavy = ctx.previewHeavy
        let thin = GStroke(weight: 1, color: RGBColor(0.18, 0.43, 0.66))
        if let l {
            for r in l.runs {
                let isPending = pending != nil && r.index == (data.runs?.count ?? 0) - 1
                let selected = selection == .run(r.index)
                let st = selected ? GStroke(weight: 3, color: RGBColor(0.11, 0.55, 0.95)) : heavy
                preview.primitives.append(.polyline(r.outline.points, closed: true, isPending ? heavy : st))
                for t in r.treads { preview.primitives.append(.polyline([t.front.start, t.front.end], closed: false, thin)) }
                if r.walk.count >= 2 {
                    preview.primitives.append(.polyline(r.walk, closed: false, GStroke(weight: 1, color: thin.color, pattern: .dash)))
                    let end = r.walk[r.walk.count - 1], d = r.endDirection, n = d.perpendicular, a = ctx.paper(0.0025)
                    preview.primitives.append(.polyline([end - d * a + n * a * 0.4, end, end - d * a - n * a * 0.4], closed: false, thin))
                }
            }
            for (k, land) in l.landings.enumerated() {
                let selected = selection == .landing(land.index ?? k)
                preview.primitives.append(.polyline(land.polygon.points, closed: true, selected ? GStroke(weight: 3, color: RGBColor(0.11, 0.55, 0.95)) : blue))
            }
            for s in l.supports {
                for f in s.faces where f.count >= 2 { preview.primitives.append(.polyline(f, closed: false, GStroke(weight: 1, color: thin.color, pattern: .hidden))) }
            }
            if let p = pending, let pr = l.runs.last {
                let created = p.risers, left = (numbers?.desired ?? 0) - risersSoFar - created
                let text = left >= 0 ? "\(created) RISERS CREATED, \(left) REMAINING" : "\(created) RISERS CREATED, \(-left) TOO MANY"
                // Beside the run, at its middle, on the side away from the run's left (as Revit shows it).
                let at = pr.walkPoint(pr.walkLength / 2)
                let toRight = -pr.endDirection.perpendicular
                let right = toRight.x >= 0
                let side = toRight * (pr.width / 2 + ctx.paper(0.004))
                preview.primitives.append(.text(GText(position: at + side, height: 0.0025, string: text, alignment: right ? .left : .right,
                                                      verticalAnchor: 0.5, color: RGBColor(0.35, 0.35, 0.38))))
                if let s = clicks.first, runMode == .straight { preview.tempDims = [tempDim(s, pr.endEdge.midpoint - pr.endDirection.perpendicular * centerOffset)] }
            }
        }
        // Steps in progress.
        if let c = current, !modifying, runSketch == nil {
            switch (component, runMode) {
            case (.run, .fullStepSpiral), (.run, .centerEndsSpiral):
                if let cen = clicks.first {
                    preview.primitives.append(.arc(Arc2(center: cen, radius: max(cen.distance(to: clicks.count > 1 ? clicks[1] : c), 1e-3), startAngle: 0, sweep: 2 * .pi),
                                                   GStroke(weight: 1, color: thin.color, pattern: .dash)))
                }
            case (.run, .straight) where clicks.isEmpty:
                if let cand = startCandidates.first(where: { $0.point.isAlmostEqual(c, tolerance: 1e-9) }) {
                    preview.primitives.append(.arc(Arc2(center: cand.point, radius: ctx.pixel * 5, startAngle: 0, sweep: 2 * .pi), heavy))
                }
            default: break
            }
            if component == .landing, landingMode == .sketch, !landingPoints.isEmpty {
                preview.primitives.append(.polyline(landingPoints + [c], closed: false, heavy))
            }
        }
        if let k = pickedRun, let r = l?.runs.first(where: { $0.index == k }) {
            preview.primitives.append(.polyline(r.outline.points, closed: true, GStroke(weight: 4, color: RGBColor(0.11, 0.55, 0.95))))
        }
        if let k = runSketch {
            let green = GStroke(weight: 2, color: RGBColor(0.15, 0.6, 0.25)), black = GStroke(weight: 2, color: .black)
            let path = GStroke(weight: 2, color: RGBColor(0.15, 0.35, 0.85))
            for (list, st) in [(k.boundaries, green), (k.risers, black), (k.path, path)] {
                for c in list { preview.primitives.append(.polyline(c.tessellate(chordTolerance: 0.01), closed: false, st)) }
            }
            if let last = chain.last, let c = current {
                let st = sketchLine == .boundary ? green : sketchLine == .riser ? black : path
                preview.primitives.append(.polyline([last, c], closed: false, st))
                preview.tempDims = [tempDim(last, c)]
            }
        }
        if modifying { preview.primitives += gripPrimitives() }
        if let id = editingID { preview.highlight = [id] }
    }
}

extension StairData {
    /// A copy with these runs (and automatic landings).
    func with(runs: [StairRun]) -> StairData { var s = self; s.runs = runs; s.landings = nil; return s }
}

extension StairRunGeometryAccess {
    /// Winder legs for a new tread count, in proportion to the old ones.
    static func scaledLegs(_ r: StairRun, treads: Int) -> [Int] {
        let corners = r.corners, k = r.winders
        let straight = max(0, treads - corners * k)
        let old = r.legTreads ?? []
        let oldTotal = max(1, old.reduce(0, +) + max(0, r.risers - 1 - corners * k - old.reduce(0, +)))
        return old.prefix(corners).map { Int((Double($0) * Double(straight) / Double(oldTotal)).rounded()) }
    }
}
