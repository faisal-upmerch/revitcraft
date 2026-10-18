import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// BL-CANVAS (ARCUS-048/049/050): the full sketch Draw panel — polygons, circles, center-ends, tangent and fillet
// arcs, Pick Lines — the Options Bar Offset, Extend into Wall (to Core), and sketch errors that name their lines.

/// Shapes shared by the sketch and wall draw tools.
enum DrawShapes {
    /// Arc about `center` from `start` (which sets the radius) toward the direction of `end`, the shorter way round.
    static func centerEndsArc(center c: Vec2, start s: Vec2, end e: Vec2) -> Arc2? {
        let r = c.distance(to: s)
        guard r > Tolerance.shortCurve, e.distance(to: c) > Tolerance.shortCurve else { return nil }
        let a0 = (s - c).angle
        let sweep = Angle.normalizeSigned((e - c).angle - a0)
        guard abs(sweep) > 1e-6 else { return nil }
        return Arc2(center: c, radius: r, startAngle: a0, sweep: sweep)
    }

    /// Regular polygon: `through` is a corner (inscribed) or the middle of a side (circumscribed).
    static func polygon(center: Vec2, through p: Vec2, sides: Int, circumscribed: Bool) -> [Curve2] {
        let r0 = center.distance(to: p)
        guard r0 > Tolerance.shortCurve else { return [] }
        let n = max(3, sides)
        let half = Double.pi / Double(n)
        var a0 = (p - center).angle
        var r = r0
        if circumscribed { r = r0 / cos(half); a0 -= half }
        let pts = (0..<n).map { k in center + Vec2.fromAngle(a0 + 2 * Double.pi * Double(k) / Double(n)) * r }
        return Polygon2(pts).edges.map { .line($0) }
    }

    /// A full circle as two half arcs.
    static func circle(center: Vec2, radius r: Double) -> [Curve2] {
        guard r > Tolerance.shortCurve else { return [] }
        return [.arc(Arc2(center: center, radius: r, startAngle: 0, sweep: Double.pi)), .arc(Arc2(center: center, radius: r, startAngle: Double.pi, sweep: Double.pi))]
    }
}

extension SketchTool {
    /// Colour of lines named by a sketch error (the UI sets it from Settings ▸ Colors ▸ Alert).
    public static var alertColor = RGBColor(0.93, 0.33, 0.10)
    static var alertStroke: GStroke { GStroke(weight: 3, color: alertColor) }

    // MARK: Prompts and options

    var drawPrompt: String {
        switch drawMode {
        case .inscribedPolygon, .circumscribedPolygon:
            if start == nil { return "Click the center of the polygon." }
            return drawMode == .inscribedPolygon ? "Click a corner of the polygon, or type the radius." : "Click the middle of a side, or type the radius."
        case .circle: return start == nil ? "Click the center of the circle." : "Click a point on the circle, or type the radius."
        case .centerArc:
            if start == nil { return "Click the center of the arc." }
            return arcEnd == nil ? "Click the start of the arc (sets the radius)." : "Click the end of the arc."
        case .tangentArc:
            return tangentStart == nil ? "Tangent arcs continue from the last line. Draw a line first." : "Click the end of the tangent arc."
        case .filletArc:
            switch filletPicks.count {
            case 0: return "Click the first line to fillet."
            case 1: return "Click the second line to fillet."
            default: return "Click to set the fillet radius, or type it."
            }
        case .pickLines: return "Click a line, wall face, grid or reference plane to add a boundary line on it."
        default: return freeformPrompt ?? "" // F1
        }
    }

    var drawNumericLabel: String? {
        switch drawMode {
        case .circle, .inscribedPolygon, .circumscribedPolygon: start != nil ? "Radius" : nil
        case .filletArc: filletPicks.count == 2 ? "Radius" : nil
        default: nil
        }
    }

    var drawOptions: [ToolOption] {
        guard !arrowMode, ![.callout, .revisionCloud, .slopeArrow].contains(target) else { return [] }
        var o: [ToolOption] = []
        let usesOverhang = target == .roof && drawMode == .pickWalls
        if !usesOverhang, ![.filletArc, .tangentArc].contains(drawMode) {
            o.append(ToolOption(id: "offset", label: "Offset", kind: .length, value: .double(offset)))
        }
        if drawMode == .inscribedPolygon || drawMode == .circumscribedPolygon {
            o.append(ToolOption(id: "sides", label: "Sides", kind: .integer, value: .int(sides)))
        }
        return o
    }

    /// A drawn line or arc shifted by the Options Bar Offset (to the left of the drawing direction).
    func offsetCurve(_ c: Curve2) -> Curve2 { offset == 0 ? c : c.offset(by: offset) }

    /// Signed offset of the wall's core face on the given side of its location line.
    func coreFaceOffset(_ f: WallFrame, left: Bool) -> Double {
        let a = f.offset(fromExterior: f.assembly.exteriorToCore), b = f.offset(fromExterior: f.assembly.exteriorToCore + f.assembly.coreThickness)
        return left ? max(a, b) : min(a, b)
    }

    /// Where a tangent arc starts: the end of the last line drawn, continuing its direction.
    var tangentStart: (point: Vec2, tangent: Vec2)? {
        guard let last = curves.last else { return nil }
        return (last.end, last.tangent(at: 1))
    }

    /// The sketch line nearest `p` within pick distance (straight lines only when `linesOnly`).
    func curveIndex(near p: Vec2, linesOnly: Bool = false) -> Int? {
        let tol = ctx.pixel * 8
        return curves.indices.filter { !linesOnly || curves[$0].asSegment != nil }
            .min { curves[$0].distance(to: p) < curves[$1].distance(to: p) }
            .flatMap { curves[$0].distance(to: p) <= tol ? $0 : nil }
    }

    // MARK: Shapes

    func polygonCurves(center: Vec2, through p: Vec2) -> [Curve2] {
        let d = p - center
        let len = d.length
        let q = offset == 0 || len < Tolerance.shortCurve ? p : center + d / len * (len + offset)
        return DrawShapes.polygon(center: center, through: q, sides: sides, circumscribed: drawMode == .circumscribedPolygon)
    }
    func circleCurves(center: Vec2, radius r: Double) -> [Curve2] { DrawShapes.circle(center: center, radius: r + offset) }

    /// Picked line under the pointer, shifted by Offset away from the side the pointer is on.
    func pickedLine(at p: Vec2) -> Segment2? {
        guard let (seg, _) = ctx.snapIndex.nearestSegment(p, radius: ctx.pixel * 8) else { return nil }
        guard offset != 0 else { return seg }
        let n = seg.direction.perpendicular
        let side: Double = n.dot(p - seg.start) >= 0 ? -1 : 1
        return Segment2(seg.start + n * offset * side, seg.end + n * offset * side)
    }

    /// Fillet radius that puts the arc through `p`.
    func filletRadius(through p: Vec2) -> Double? {
        guard filletPicks.count == 2, let a = curves[safe: filletPicks[0]]?.asSegment, let b = curves[safe: filletPicks[1]]?.asSegment,
              !a.isParallel(to: b), let q = a.lineIntersection(b)?.point else { return nil }
        func away(_ s: Segment2) -> Vec2 { ((s.start.distance(to: q) > s.end.distance(to: q) ? s.start : s.end) - q).normalized }
        let theta = acos(max(-1, min(1, away(a).dot(away(b)))))
        let k = 1 / sin(theta / 2) - 1
        guard k > 1e-9 else { return nil }
        return (p - q).length / k
    }

    /// Replaces the two picked lines by their trimmed pieces and adds the fillet arc.
    @discardableResult
    func applyFillet(radius r: Double) -> Bool {
        guard filletPicks.count == 2, let a = curves[safe: filletPicks[0]]?.asSegment, let b = curves[safe: filletPicks[1]]?.asSegment,
              let f = Fillet.lines(a, b, radius: r) else {
            message("Those lines can't be filleted with that radius.")
            return false
        }
        curves[filletPicks[0]] = .line(f.a)
        curves[filletPicks[1]] = .line(f.b)
        add(.arc(f.arc))
        filletPicks = []
        return true
    }

    // MARK: Preview and clicks

    /// Preview for the draw tools added by BL-CANVAS; false for the tools `rebuild` draws itself.
    func previewDraw(at c: Vec2) -> Bool {
        func show(_ cs: [Curve2]) {
            for k in cs {
                switch k {
                case .line(let s): preview.primitives.append(.polyline([s.start, s.end], closed: false, ctx.previewHeavy))
                case .arc(let a): preview.primitives.append(.arc(a, ctx.previewHeavy))
                }
            }
        }
        switch drawMode {
        case .inscribedPolygon, .circumscribedPolygon:
            if let s = start { show(polygonCurves(center: s, through: c)); preview.tempDims = [tempDim(s, c)] }
        case .circle:
            if let s = start { show(circleCurves(center: s, radius: s.distance(to: c))); preview.tempDims = [tempDim(s, c)] }
        case .centerArc:
            if let s = start, let e = arcEnd, let a = DrawShapes.centerEndsArc(center: s, start: e, end: c) {
                show([offsetCurve(.arc(a))])
                preview.primitives.append(ctx.line(s, e))
            } else if let s = start {
                preview.primitives.append(ctx.line(s, c))
                preview.tempDims = [tempDim(s, c)]
            }
        case .tangentArc:
            if let t = tangentStart, let a = WallTool.tangentArc(from: t.point, tangent: t.tangent, to: c) { show([.arc(a)]) }
        case .filletArc:
            if filletPicks.count == 2, let r = filletRadius(through: c), let a = curves[filletPicks[0]].asSegment,
               let b = curves[filletPicks[1]].asSegment, let f = Fillet.lines(a, b, radius: r) {
                show([.arc(f.arc)])
            } else if filletPicks.count < 2, let k = curveIndex(near: c, linesOnly: true), !filletPicks.contains(k) {
                show([curves[k]])
                preview.cursor = .pick
            }
        case .pickLines:
            if let s = pickedLine(at: c) { show([.line(s)]); preview.cursor = .pick }
        default:
            return previewFreeform(at: c) // F1: Spline, Ellipse, Partial Ellipse
        }
        return true
    }

    /// Clicks for the draw tools added by BL-CANVAS; false for the tools `pointerDown` handles itself.
    func clickDraw(at p: Vec2) -> Bool {
        switch drawMode {
        case .inscribedPolygon, .circumscribedPolygon:
            if let s = start { polygonCurves(center: s, through: p).forEach(add); start = nil } else { start = p }
        case .circle:
            if let s = start { circleCurves(center: s, radius: s.distance(to: p)).forEach(add); start = nil } else { start = p }
        case .centerArc:
            if start == nil { start = p }
            else if arcEnd == nil { if let s = start, s.distance(to: p) > Tolerance.shortCurve { arcEnd = p } }
            else if let s = start, let e = arcEnd {
                guard let a = DrawShapes.centerEndsArc(center: s, start: e, end: p) else { message("Click an end away from the center."); return true }
                add(offsetCurve(.arc(a)))
                start = nil; arcEnd = nil
            }
        case .tangentArc:
            guard let t = tangentStart else { message("Tangent arcs continue from the last line. Draw a line first."); return true }
            guard let a = WallTool.tangentArc(from: t.point, tangent: t.tangent, to: p) else { message("Pick a point off the tangent line."); return true }
            add(.arc(a))
        case .filletArc:
            if filletPicks.count < 2 {
                guard let k = curveIndex(near: p, linesOnly: true) else { message("Click a straight sketch line."); return true }
                if !filletPicks.contains(k) { filletPicks.append(k) }
                if filletPicks.count == 2, filletRadius(through: p) == nil, curves[filletPicks[0]].asSegment.map({ $0.isParallel(to: curves[filletPicks[1]].asSegment!) }) == true {
                    message("Pick two lines that are not parallel."); filletPicks = []
                }
            } else if let r = filletRadius(through: p) {
                applyFillet(radius: r)
            }
        case .pickLines:
            guard let s = pickedLine(at: p) else { message("Click a line, wall face, grid or reference plane."); return true }
            add(.line(s))
        default:
            return clickFreeform(at: p) // F1: Spline, Ellipse, Partial Ellipse
        }
        return true
    }

    /// Typed radius for circles, polygons and fillets.
    func drawNumericInput(_ text: String) -> Bool {
        guard let v = ctx.parse(text), v > Tolerance.shortCurve else { return false }
        switch drawMode {
        case .circle:
            guard let s = start else { return false }
            circleCurves(center: s, radius: v).forEach(add); start = nil
        case .inscribedPolygon, .circumscribedPolygon:
            guard let s = start else { return false }
            let d = current.map { ($0 - s).lengthSquared > 0 ? ($0 - s).normalized : .unitX } ?? .unitX
            polygonCurves(center: s, through: s + d * v).forEach(add); start = nil
        case .filletArc:
            guard filletPicks.count == 2 else { return false }
            guard applyFillet(radius: v) else { return false }
        default:
            return false
        }
        rebuild()
        return true
    }

    // MARK: Finish

    /// After Finish the new (or edited) element stays selected, as in the reference tool (ARCUS-049).
    func keepSelected(_ id: ElementID?) {
        if let id, ctx.model[id] != nil { ctx.session.selection.select([id]) }
    }

    /// Shows a sketch error naming its lines: they turn the alert colour; Continue returns to the sketch, Quit Sketch
    /// discards it (ARCUS-050).
    func presentSketchIssue(_ issue: SketchIssue) {
        errorCurves = Set(issue.curves)
        rebuild()
        guard let present = ctx.presentError else {
            message(issue.message + " Fix the highlighted lines, or Cancel the sketch.")
            return
        }
        let n = issue.curves.count
        let detail = n == 0 ? "Continue returns to the sketch; Quit Sketch discards it."
            : "\(n) line\(n == 1 ? " is" : "s are") highlighted. Continue returns to the sketch to fix \(n == 1 ? "it" : "them"); Quit Sketch discards the sketch."
        present(issue.message, detail, ["Continue", "Quit Sketch"]) { [weak self] choice in
            if choice == 1 { self?.cancelSketch() }
        }
    }
}

extension Array {
    fileprivate subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension SketchTool {
    /// Contextual tab name: "Modify | Create Floor Boundary" while creating, "Modify | Floors > Edit Boundary" while
    /// editing an existing element's sketch.
    public func ribbonTitle(_ model: BIMModel) -> String {
        if let id = editingID, let e = model[id] { return "Modify | \(e.category.displayName) > Edit Boundary" }
        return "Modify | Create \(title)"
    }
}
