import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// MARK: - Wall

/// Draws basic and curtain walls (the type selector decides which). Options Bar: Height/Depth with a level or an
/// unconnected value, Location Line, Chain, Offset, Radius, Join Status; Space flips the exterior side while drawing.
@MainActor
public final class WallTool: BaseTool, InteractiveTool {
    public enum Mode: String, CaseIterable {
        case line = "Line", rectangle = "Rectangle", inscribedPolygon = "Inscribed Polygon", circumscribedPolygon = "Circumscribed Polygon"
        case circle = "Circle", arc = "Start-End-Radius Arc", centerArc = "Center-ends Arc", tangentArc = "Tangent End Arc" // BL-CANVAS
        case filletArc = "Fillet Arc", pickLines = "Pick Lines"
    }
    /// Height draws the wall up from the current level; Depth draws it down to a level below (or by a depth).
    public enum Extent: String, CaseIterable { case height = "Height", depth = "Depth" }
    public enum JoinStatus: String, CaseIterable { case allow = "Allow", disallow = "Disallow" }

    public var mode: Mode
    public let commandID: CommandID
    public var title: String { "Wall" }
    var start: Vec2?
    var arcEnd: Vec2?
    var current: Vec2?
    public var chain = true
    public var locationLine: WallLocationLine = .wallCenterline
    public var extent: Extent = .height
    /// Height: the top constraint (nil = unconnected, using `unconnectedHeight`).
    public var topLevelID: ElementID?
    /// Depth: the level the wall goes down to (nil = unconnected, using `unconnectedHeight` as the depth).
    public var depthLevelID: ElementID?
    public var unconnectedHeight = 3.0
    public var baseOffset = 0.0
    public var offset = 0.0
    /// Radius: fillets corners of line chains; fixes the size of circles, polygons and arcs (fewer clicks).
    public var useRadius = false
    public var radius = 1.0
    public var sides = 6
    public var joinStatus: JoinStatus = .allow
    /// Space bar while drawing: puts the exterior on the right of the drawing direction instead of the left.
    public var flipSide = false
    var created = 0
    /// End point and direction of travel of the last wall drawn in this chain (tangent arcs and fillets continue from it).
    var chainEnd: (point: Vec2, tangent: Vec2)?
    /// The last straight wall of the chain and the line it was drawn on (before Offset), trimmed when the next corner
    /// is filleted.
    var lastLineWall: (id: ElementID, drawn: Segment2)?
    /// Fillet Arc: the walls picked so far.
    var filletWalls: [ElementID] = []

    public init(ctx: ToolContext, mode: Mode = .line, commandID: CommandID? = nil) {
        self.mode = mode
        self.commandID = commandID ?? (mode == .arc ? .wallArc : mode == .rectangle ? .wallRectangle : mode == .pickLines ? .wallPickLines : .wall)
        super.init(ctx: ctx)
        topLevelID = ctx.model.levelAbove(ctx.levelID)?.id
        let lv = ctx.model.levels
        if topLevelID == nil, let i = lv.firstIndex(where: { $0.id == ctx.levelID }), i > 0 {
            unconnectedHeight = max(2.4, (lv[i].level?.elevation ?? 0) - (lv[i - 1].level?.elevation ?? 0))
        }
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Walls are drawn in plan views. Open a floor plan to draw walls." }
        let flip = " Space flips the exterior side."
        switch mode {
        case .line: return start == nil ? "Click to enter the wall start point." : "Click to enter the wall end point, or type a length. Esc ends the chain." + flip
        case .rectangle: return start == nil ? "Click the first corner of the rectangle." : "Click the opposite corner." + flip
        case .inscribedPolygon, .circumscribedPolygon:
            if useRadius { return "Click the center of the polygon." }
            return start == nil ? "Click the center of the polygon." : (mode == .inscribedPolygon ? "Click a corner of the polygon, or type the radius." : "Click the middle of a side, or type the radius.")
        case .circle:
            if useRadius { return "Click the center of the circle." }
            return start == nil ? "Click the center of the circle." : "Click a point on the circle, or type the radius." + flip
        case .arc:
            if start == nil { return "Click the arc start point." }
            if arcEnd == nil { return "Click the arc end point." }
            return useRadius ? "Click the side the arc bulges toward." : "Click a point on the arc to set its curvature."
        case .centerArc:
            if start == nil { return "Click the center of the arc." }
            return arcEnd == nil ? (useRadius ? "Click the direction of the arc start." : "Click the arc start point (sets the radius).") : "Click the arc end point." + flip
        case .tangentArc:
            return chainEnd == nil ? "Click the end of a wall to continue from it with a tangent arc." : "Click the end point of the tangent arc." + flip
        case .filletArc:
            switch filletWalls.count {
            case 0: return "Click the first wall to fillet."
            case 1: return "Click the second wall to fillet."
            default: return "Click to set the fillet radius, or type it."
            }
        case .pickLines: return "Click a line, grid, wall face or CAD line to create a wall on it."
        }
    }
    public var numericLabel: String? {
        switch mode {
        case .line: start != nil ? "Length" : nil
        case .circle, .inscribedPolygon, .circumscribedPolygon: start != nil ? "Radius" : nil
        case .filletArc: filletWalls.count == 2 ? "Radius" : nil
        default: nil
        }
    }
    public var snapFrom: Vec2? { start ?? chainEnd?.point }

    // MARK: Options Bar

    var levelsBelow: [Element] {
        let z = ctx.levelElevation
        return ctx.model.levels.filter { ($0.level?.elevation ?? 0) < z - Tolerance.length }
    }

    public var options: [ToolOption] {
        var o: [ToolOption] = [
            ToolOption(id: "mode", label: "Draw", kind: .choice(Mode.allCases.map(\.rawValue)), value: .text(mode.rawValue)),
            ToolOption(id: "extent", label: "", kind: .choice(Extent.allCases.map(\.rawValue)), value: .text(extent.rawValue)),
        ]
        switch extent {
        case .height:
            let top = ctx.model[topLevelID]?.name ?? "Unconnected"
            o.append(ToolOption(id: "top", label: "Height", kind: .choice(["Unconnected"] + ctx.model.levels.map(\.name)), value: .text(top)))
            if topLevelID == nil { o.append(ToolOption(id: "height", label: "Unconnected", kind: .length, value: .double(unconnectedHeight))) }
        case .depth:
            let base = ctx.model[depthLevelID]?.name ?? "Unconnected"
            o.append(ToolOption(id: "depthLevel", label: "Depth", kind: .choice(["Unconnected"] + levelsBelow.map(\.name)), value: .text(base)))
            if depthLevelID == nil { o.append(ToolOption(id: "height", label: "Unconnected", kind: .length, value: .double(unconnectedHeight))) }
        }
        o.append(ToolOption(id: "location", label: "Location Line", kind: .choice(WallLocationLine.allCases.map(\.rawValue)), value: .text(locationLine.rawValue)))
        if [.line, .arc, .centerArc, .tangentArc].contains(mode) { o.append(ToolOption(id: "chain", label: "Chain", kind: .bool, value: .bool(chain))) }
        o.append(ToolOption(id: "offset", label: "Offset", kind: .length, value: .double(offset)))
        if [.line, .arc, .centerArc, .circle, .inscribedPolygon, .circumscribedPolygon, .filletArc].contains(mode) {
            o.append(ToolOption(id: "useRadius", label: "Radius", kind: .bool, value: .bool(useRadius)))
            if useRadius { o.append(ToolOption(id: "radius", label: "", kind: .length, value: .double(radius))) }
        }
        if mode == .inscribedPolygon || mode == .circumscribedPolygon {
            o.append(ToolOption(id: "sides", label: "Sides", kind: .integer, value: .int(sides)))
        }
        o.append(ToolOption(id: "join", label: "Join Status", kind: .choice(JoinStatus.allCases.map(\.rawValue)), value: .text(joinStatus.rawValue)))
        return o
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "mode":
            if let m = Mode(rawValue: value.textValue ?? "") ?? Self.legacyMode(value.textValue), m != mode { // BL-CANVAS
                // Switching between chaining modes mid-chain continues from the last wall's end.
                let keep = chain ? chainEnd : nil
                mode = m
                resetSteps()
                if let k = keep, [.line, .arc, .tangentArc].contains(m) {
                    chainEnd = k
                    if m != .tangentArc { start = k.point }
                }
            }
        case "extent":
            if let e = Extent(rawValue: value.textValue ?? "") { extent = e }
        case "top": topLevelID = ctx.model.levels.first { $0.name == value.textValue }?.id
        case "depthLevel": depthLevelID = levelsBelow.first { $0.name == value.textValue }?.id
        case "height": if let d = value.doubleValue, d > 0.01 { unconnectedHeight = d }
        case "location": if let l = WallLocationLine(rawValue: value.textValue ?? "") { locationLine = l }
        case "chain": chain = value.boolValue ?? true
        case "offset": offset = value.doubleValue ?? 0
        case "useRadius": useRadius = value.boolValue ?? false
        case "radius": if let d = value.doubleValue, d > Tolerance.shortCurve { radius = d } else { message("The radius must be greater than zero.") }
        case "sides": if let n = value.intValue, (3...64).contains(n) { sides = n } else { message("Polygons need 3 to 64 sides.") }
        case "join": if let j = JoinStatus(rawValue: value.textValue ?? "") { joinStatus = j }
        default: break
        }
        rebuildPreview()
    }

    func resetSteps() {
        start = nil; arcEnd = nil; chainEnd = nil; lastLineWall = nil; filletWalls = []
        preview = ToolPreview()
    }

    // MARK: Type and side geometry

    var typeData: TypeData? { ctx.type(for: .walls).flatMap { ctx.model[$0]?.typeData } }
    var assembly: CompoundAssembly { WallGeometry.assembly(ofType: typeData) }
    var thickness: Double { assembly.totalThickness }

    /// Left/right face offsets of the drawn line for the current location line (exterior on the left unless flipped).
    func sideOffsets() -> (Double, Double) {
        let a = assembly
        let t = a.totalThickness
        let ext2core = a.exteriorToCore, core = a.coreThickness
        let pos: Double
        switch locationLine {
        case .wallCenterline: pos = t / 2
        case .coreCenterline: pos = ext2core + core / 2
        case .finishFaceExterior: pos = 0
        case .finishFaceInterior: pos = t
        case .coreFaceExterior: pos = ext2core
        case .coreFaceInterior: pos = ext2core + core
        }
        return flipSide ? (t - pos, -pos) : (pos, -(t - pos))
    }

    // MARK: Preview

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        onGuide = i.snap.map { [.extension, .intersection].contains($0.kind) } ?? false
        rebuildPreview()
    }
    /// The pointer is held on an alignment guide (before the first click, reference dimensions are shown then).
    var onGuide = false

    func rebuildPreview() {
        preview = ToolPreview()
        guard let c = current else { return }
        switch mode {
        case .line:
            if let s = start {
                preview.primitives += outline(.line(Segment2(s, c)))
                let previous = lastLineWall.flatMap { $0.drawn.end.distance(to: s) < 1e-9 ? $0.drawn.direction : nil }
                preview.tempDims = [tempDim(s, c), angleDim(s, c, reference: previous)] + referenceDims(for: Segment2(s, c))
            } else if onGuide {
                preview.tempDims = referenceDims(at: c)
            }
        case .rectangle:
            if let s = start {
                let r = Rect2(points: [s, c])
                for e in Polygon2.rectangle(r).clockwise.edges { preview.primitives += outline(.line(e)) }
                preview.tempDims = [tempDim(Vec2(r.min.x, r.min.y), Vec2(r.max.x, r.min.y)), tempDim(Vec2(r.max.x, r.min.y), Vec2(r.max.x, r.max.y), active: false)]
            }
        case .inscribedPolygon, .circumscribedPolygon:
            if useRadius {
                for e in polygonCurves(center: c, through: c + Vec2(radius, 0)) { preview.primitives += outline(e) }
            } else if let s = start {
                for e in polygonCurves(center: s, through: c) { preview.primitives += outline(e) }
                preview.tempDims = [tempDim(s, c)]
            }
        case .circle:
            if useRadius {
                for e in circleCurves(center: c, radius: radius) { preview.primitives += outline(e) }
            } else if let s = start {
                for e in circleCurves(center: s, radius: s.distance(to: c)) { preview.primitives += outline(e) }
                preview.tempDims = [tempDim(s, c)]
            }
        case .arc:
            if let s = start, let e = arcEnd, let a = arcThrough(s, e, c) {
                preview.primitives += outline(.arc(a))
            } else if let s = start {
                preview.primitives.append(ctx.line(s, c))
                preview.tempDims = [tempDim(s, c)]
            }
        case .centerArc:
            if let s = start, let e = arcEnd, let a = centerArc(center: s, start: e, end: c) {
                preview.primitives += outline(.arc(a))
                preview.primitives.append(ctx.line(s, a.start))
            } else if let s = start {
                preview.primitives.append(ctx.line(s, c))
                preview.tempDims = [tempDim(s, c)]
            }
        case .tangentArc:
            if let ce = chainEnd, let a = Self.tangentArc(from: ce.point, tangent: ce.tangent, to: c) {
                preview.primitives += outline(.arc(a))
            } else if chainEnd == nil, wallEnd(near: c) != nil {
                preview.cursor = .pick
            }
        case .filletArc:
            preview.highlight = Set(filletWalls)
            if filletWalls.count == 2, let f = fillet(radius: useRadius ? radius : filletRadius(through: c)) {
                preview.primitives += outline(.arc(f.arc))
            } else if let h = pickedWall(at: c) {
                preview.highlight.insert(h)
                preview.cursor = .pick
            }
        case .pickLines:
            if let (seg, _) = ctx.snapIndex.nearestSegment(c, radius: ctx.pixel * 8) {
                preview.primitives += outline(.line(seg))
                preview.cursor = .pick
            }
        }
    }

    /// Wall outline for a location curve, with the exterior face drawn heavy and a tick on the exterior side.
    func outline(_ c: Curve2) -> [GPrimitive] {
        guard c.length > 1e-6 else { return [] }
        let (l, r) = sideOffsets()
        let a = c.offset(by: offset + l), b = c.offset(by: offset + r)
        let ext = flipSide ? b : a, int = flipSide ? a : b
        var out: [GPrimitive] = [curvePrimitive(c.offset(by: offset), ctx.previewStroke), curvePrimitive(ext, ctx.previewHeavy), curvePrimitive(int, ctx.previewStroke)]
        out.append(ctx.line(a.start, b.start))
        out.append(ctx.line(a.end, b.end))
        // Exterior marker at mid-length.
        let m = ext.midpoint, n = c.normal(at: 0.5) * (flipSide ? -1 : 1)
        let size = ctx.pixel * 10
        out.append(.polyline([m + c.tangent(at: 0.5) * size * 0.6, m + n * size, m - c.tangent(at: 0.5) * size * 0.6], closed: false, ctx.previewStroke))
        return out
    }

    func curvePrimitive(_ c: Curve2, _ st: GStroke) -> GPrimitive {
        switch c {
        case .line(let s): .polyline([s.start, s.end], closed: false, st)
        case .arc(let a): .arc(a, st)
        }
    }

    // MARK: Shapes

    /// Closed polygon of `sides` sides; the second point is a corner (inscribed) or the middle of a side (circumscribed).
    func polygonCurves(center: Vec2, through p: Vec2) -> [Curve2] {
        let r0 = center.distance(to: p)
        guard r0 > Tolerance.shortCurve else { return [] }
        let n = max(3, sides)
        let half = Double.pi / Double(n)
        var a0 = (p - center).angle
        var r = r0
        if mode == .circumscribedPolygon { r = r0 / cos(half); a0 -= half }
        let pts = (0..<n).map { k in center + Vec2.fromAngle(a0 + 2 * Double.pi * Double(k) / Double(n)) * r }
        // Clockwise so the exterior (left of travel) faces out.
        return Polygon2(pts).clockwise.edges.map { .line($0) }
    }

    /// A circle as two clockwise half arcs (exterior outward).
    func circleCurves(center: Vec2, radius r: Double) -> [Curve2] {
        guard r > Tolerance.shortCurve else { return [] }
        return [.arc(Arc2(center: center, radius: r, startAngle: 0, sweep: -Double.pi)), .arc(Arc2(center: center, radius: r, startAngle: -Double.pi, sweep: -Double.pi))]
    }

    /// Start-end arc: through the third point, or with the Radius option on the side of the third point.
    func arcThrough(_ s: Vec2, _ e: Vec2, _ p: Vec2) -> Arc2? {
        guard useRadius else { return Arc2(through: s, p, e) }
        let chord = e - s
        let half = chord.length / 2
        guard half > Tolerance.shortCurve, radius >= half - 1e-9 else { return nil }
        let side: Double = chord.cross(p - s) >= 0 ? 1 : -1
        let h = sqrt(max(0, radius * radius - half * half))
        let mid = s.midpoint(e)
        let n = chord.normalized.perpendicular * side
        let bulge = mid + n * (radius - h) // the minor arc's midpoint
        return Arc2(through: s, bulge, e)
    }

    /// Center-ends arc: the second click sets the radius (or only the start direction with Radius on). // BL-CANVAS
    func centerArc(center c: Vec2, start s: Vec2, end e: Vec2) -> Arc2? {
        let st = useRadius && s.distance(to: c) > Tolerance.shortCurve ? c + (s - c).normalized * radius : s
        return DrawShapes.centerEndsArc(center: c, start: st, end: e)
    }

    /// Draw modes saved or typed under their earlier names.
    static func legacyMode(_ name: String?) -> Mode? {
        switch name { case "Arc": .arc; case "Tangent Arc": .tangentArc; default: nil }
    }

    /// Arc starting at `p` tangent to `t`, ending at `e`.
    static func tangentArc(from p: Vec2, tangent t: Vec2, to e: Vec2) -> Arc2? {
        let d = e - p
        let n = t.normalized.perpendicular
        let denom = 2 * d.dot(n)
        guard abs(denom) > 1e-9, d.length > Tolerance.shortCurve else { return nil }
        let rho = d.lengthSquared / denom
        let c = p + n * rho
        let r = abs(rho)
        let a0 = (p - c).angle, a1 = (e - c).angle
        var sweep = rho > 0 ? Angle.normalize(a1 - a0) : -Angle.normalize(a0 - a1)
        if abs(sweep) < 1e-9 { sweep = rho > 0 ? 2 * .pi : -2 * .pi }
        guard abs(sweep) < 2 * .pi - 1e-6 else { return nil }
        return Arc2(center: c, radius: r, startAngle: a0, sweep: sweep)
    }

    // MARK: Picking helpers

    /// A wall end within pick distance of `p`, with the direction of travel leaving that end.
    func wallEnd(near p: Vec2) -> (point: Vec2, tangent: Vec2)? {
        let tol = ctx.pixel * 8
        let near = ctx.model.elements(.walls, intersecting: Rect2(center: p, halfSize: Vec2(tol, tol))).filter { $0.levelID == ctx.levelID }
        // A wall ending here continues naturally; otherwise leave a wall's start going backwards.
        for w in near { if let c = w.wall?.location, c.end.distance(to: p) <= tol { return (c.end, c.tangent(at: 1)) } }
        for w in near { if let c = w.wall?.location, c.start.distance(to: p) <= tol { return (c.start, -c.tangent(at: 0)) } }
        return nil
    }

    func pickedWall(at p: Vec2) -> ElementID? {
        let tol = ctx.pixel * 8
        return ctx.model.elements(.walls, intersecting: Rect2(center: p, halfSize: Vec2(tol, tol)))
            .filter { $0.levelID == ctx.levelID && $0.wall?.location.asSegment != nil && !filletWalls.contains($0.id) }
            .min { ($0.wall!.location.distance(to: p)) < ($1.wall!.location.distance(to: p)) }
            .flatMap { $0.wall!.location.distance(to: p) <= tol + thickness ? $0.id : nil }
    }

    // MARK: Fillets

    struct Fillet { var arc: Arc2; var trimmed: [(ElementID, Segment2)]; var reversed: Bool }

    /// Corner geometry of the two picked walls: intersection, and unit directions from it along each wall.
    func corner() -> (q: Vec2, u1: Vec2, u2: Vec2, s1: Segment2, s2: Segment2)? {
        guard filletWalls.count == 2, let s1 = ctx.model[filletWalls[0]]?.wall?.location.asSegment,
              let s2 = ctx.model[filletWalls[1]]?.wall?.location.asSegment, !s1.isParallel(to: s2), let hit = s1.lineIntersection(s2) else { return nil }
        let q = hit.point
        func away(_ s: Segment2) -> Vec2 { (s.start.distance(to: q) > s.end.distance(to: q) ? s.start : s.end) - q }
        let u1 = away(s1), u2 = away(s2)
        guard u1.length > Tolerance.shortCurve, u2.length > Tolerance.shortCurve else { return nil }
        return (q, u1.normalized, u2.normalized, s1, s2)
    }

    func filletRadius(through p: Vec2) -> Double {
        guard let c = corner() else { return 0 }
        let theta = acos(max(-1, min(1, c.u1.dot(c.u2))))
        let k = 1 / sin(theta / 2) - 1
        guard k > 1e-9 else { return 0 }
        return (p - c.q).length / k
    }

    func fillet(radius r: Double) -> Fillet? {
        guard r > Tolerance.shortCurve, let c = corner() else { return nil }
        let theta = acos(max(-1, min(1, c.u1.dot(c.u2))))
        guard theta > 1e-3, theta < .pi - 1e-3 else { return nil }
        let d = r / tan(theta / 2)
        let t1 = c.q + c.u1 * d, t2 = c.q + c.u2 * d
        // The fillet must leave some of each wall.
        func far(_ s: Segment2) -> Vec2 { s.start.distance(to: c.q) > s.end.distance(to: c.q) ? s.start : s.end }
        guard d < far(c.s1).distance(to: c.q) - Tolerance.shortCurve, d < far(c.s2).distance(to: c.q) - Tolerance.shortCurve else { return nil }
        let bis = (c.u1 + c.u2).normalized
        let center = c.q + bis * (r / sin(theta / 2))
        let mid = center + (c.q - center).normalized * r
        func trimmed(_ s: Segment2, _ t: Vec2) -> Segment2 { s.start.distance(to: c.q) < s.end.distance(to: c.q) ? Segment2(t, s.end) : Segment2(s.start, t) }
        // Keep the chain direction: run the arc from the wall that ends at the corner to the one that starts there.
        let firstEndsAtCorner = c.s1.end.distance(to: c.q) < c.s1.start.distance(to: c.q)
        let secondEndsAtCorner = c.s2.end.distance(to: c.q) < c.s2.start.distance(to: c.q)
        let reversed = !firstEndsAtCorner && secondEndsAtCorner
        guard let arc = reversed ? Arc2(through: t2, mid, t1) : Arc2(through: t1, mid, t2) else { return nil }
        return Fillet(arc: arc, trimmed: [(filletWalls[0], trimmed(c.s1, t1)), (filletWalls[1], trimmed(c.s2, t2))], reversed: reversed)
    }

    func createFillet(_ r: Double) {
        guard let f = fillet(radius: r) else { message("The walls can't be filleted with that radius."); return }
        let before = created
        createWalls([.arc(f.arc)], extra: { tx in
            for (id, seg) in f.trimmed { tx.update(id) { $0.wall?.location = .line(seg) } }
        })
        if created > before { filletWalls = [] }
    }

    // MARK: Clicks

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a floor plan to draw walls."); return }
        let p = i.point
        switch mode {
        case .line:
            if let s = start {
                createChainSegment(from: s, to: p)
            } else {
                start = p
            }
        case .rectangle:
            if let s = start {
                let r = Rect2(points: [s, p])
                guard r.width > Tolerance.shortCurve, r.height > Tolerance.shortCurve else { return }
                // Clockwise so the exterior (left of each wall's direction) faces outward.
                createWalls(Polygon2.rectangle(r).clockwise.edges.map { .line($0) })
                start = nil
            } else { start = p }
        case .inscribedPolygon, .circumscribedPolygon:
            if useRadius { createWalls(polygonCurves(center: p, through: p + Vec2(radius, 0))) }
            else if let s = start { createWalls(polygonCurves(center: s, through: p)); start = nil }
            else { start = p }
        case .circle:
            if useRadius { createWalls(circleCurves(center: p, radius: radius)) }
            else if let s = start { createWalls(circleCurves(center: s, radius: s.distance(to: p))); start = nil }
            else { start = p }
        case .arc:
            if start == nil { start = p } else if arcEnd == nil { arcEnd = p } else if let s = start, let e = arcEnd {
                guard let a = arcThrough(s, e, p) else { message(useRadius ? "The radius is smaller than half the distance between the ends." : "The three points are in a line."); return }
                if createWalls([.arc(a)]) {
                    chainEnd = (a.end, a.tangent(at: 1))
                    lastLineWall = nil
                    start = chain ? e : nil
                }
                arcEnd = nil
            }
        case .centerArc:
            if start == nil { start = p }
            else if arcEnd == nil { if let s = start, s.distance(to: p) > Tolerance.shortCurve { arcEnd = p } }
            else if let s = start, let e = arcEnd {
                guard let a = centerArc(center: s, start: e, end: p) else { message("Click an end point away from the center."); return }
                if createWalls([.arc(a)]) {
                    chainEnd = (a.end, a.tangent(at: 1))
                    lastLineWall = nil
                }
                start = nil; arcEnd = nil
            }
        case .tangentArc:
            if let ce = chainEnd {
                guard let a = Self.tangentArc(from: ce.point, tangent: ce.tangent, to: p) else { message("Pick a point off the tangent line."); return }
                if createWalls([.arc(a)]) {
                    chainEnd = chain ? (a.end, a.tangent(at: 1)) : nil
                    lastLineWall = nil
                }
            } else if let we = wallEnd(near: p) {
                chainEnd = we
            } else {
                message("Tangent arcs continue from the end of a wall. Click a wall end, or draw a line first.")
            }
        case .filletArc:
            if filletWalls.count < 2 {
                if let id = pickedWall(at: p) {
                    filletWalls.append(id)
                    if filletWalls.count == 2 {
                        if corner() == nil { message("Pick two straight walls that are not parallel."); filletWalls = [] }
                        else if useRadius { createFillet(radius) }
                    }
                } else { message("Click a straight wall on this level.") }
            } else {
                createFillet(filletRadius(through: p))
            }
        case .pickLines:
            if let (seg, _) = ctx.snapIndex.nearestSegment(p, radius: ctx.pixel * 8) { createWalls([.line(seg)]) }
        }
        rebuildPreview()
    }

    /// Line mode: adds a segment to the chain, filleting the corner with the previous segment when Radius is on.
    func createChainSegment(from s: Vec2, to p: Vec2) {
        guard s.distance(to: p) > Tolerance.shortCurve else { return }
        var curves: [Curve2] = [.line(Segment2(s, p))]
        var trim: (ElementID, Curve2)?
        // Geometry is worked out on the drawn lines; createWalls applies the Offset to every curve.
        if useRadius, let last = lastLineWall, ctx.model[last.id] != nil, last.drawn.end.distance(to: s) < 1e-9 {
            let prev = last.drawn, cur = Segment2(s, p)
            let u1 = (prev.start - prev.end).normalized, u2 = cur.direction
            let theta = acos(max(-1, min(1, u1.dot(u2))))
            if theta > 1e-3, theta < .pi - 1e-3 {
                let d = radius / tan(theta / 2)
                if d < prev.length - Tolerance.shortCurve, d < cur.length - Tolerance.shortCurve {
                    let t1 = s + u1 * d, t2 = s + u2 * d
                    let center = s + (u1 + u2).normalized * (radius / sin(theta / 2))
                    let mid = center + (s - center).normalized * radius
                    if let arc = Arc2(through: t1, mid, t2) {
                        curves = [.arc(arc), .line(Segment2(t2, p))]
                        let kept = Curve2.line(Segment2(prev.start, t1))
                        trim = (last.id, offset == 0 ? kept : kept.offset(by: offset))
                    }
                }
            }
        }
        let ids = createWallIDs(curves, extra: { tx in if let (id, c) = trim { tx.update(id) { $0.wall?.location = c } } })
        guard let lastID = ids.last else { return }
        lastLineWall = chain ? (lastID, Segment2(curves.count == 2 ? (curves[1].start) : s, p)) : nil
        chainEnd = (p, (p - s).normalized)
        start = chain ? p : nil
    }

    // MARK: Creating walls

    @discardableResult
    func createWalls(_ curves: [Curve2], extra: ((TransactionContext) -> Void)? = nil) -> Bool {
        !createWallIDs(curves, extra: extra).isEmpty
    }

    /// Creates walls on the drawn curves (shifted by Offset) with the Options Bar settings; returns their ids.
    func createWallIDs(_ curves: [Curve2], extra: ((TransactionContext) -> Void)? = nil) -> [ElementID] {
        guard let level = ctx.levelID else { return [] }
        // Ends dropped on another wall's end (a visible face corner, say) move onto its location end so the walls join.
        let joinLevel = extent == .depth ? (depthLevelID ?? level) : level
        func joined(_ c: Curve2) -> Curve2 {
            guard joinStatus == .allow, case .line(var s) = c else { return c }
            if let p = WallGeometry.joinEndpoint(near: s.start, levelID: joinLevel, ctx.model) { s.start = p }
            if let p = WallGeometry.joinEndpoint(near: s.end, levelID: joinLevel, ctx.model) { s.end = p }
            return .line(s)
        }
        let valid = curves.map { joined(offset == 0 ? $0 : $0.offset(by: offset)) }.filter { $0.length > Tolerance.shortCurve }
        guard !valid.isEmpty else { return [] }
        let type = ctx.type(for: .walls)
        var ids: [ElementID] = []
        ctx.session.perform(valid.count == 1 ? "Create Wall" : "Create Walls") { tx in
            extra?(tx)
            for c in valid {
                var w = WallData(location: c, locationLine: locationLine, baseOffset: baseOffset, topLevelID: topLevelID, unconnectedHeight: unconnectedHeight)
                var base = level
                if extent == .depth {
                    if let d = depthLevelID {
                        base = d
                        w.baseOffset = 0
                    } else {
                        w.baseOffset = -unconnectedHeight
                    }
                    w.topLevelID = level
                    w.topOffset = 0
                }
                w.roomBounding = true
                w.flipped = flipSide
                w.allowJoinAtStart = joinStatus == .allow
                w.allowJoinAtEnd = joinStatus == .allow
                ids.append(tx.create(.walls, data: .wall(w), typeID: type, levelID: base))
            }
        }
        if let e = ctx.session.lastError { message(e.message); return [] }
        created += valid.count
        return ids
    }

    public func numericInput(_ text: String) -> Bool {
        guard let v = ctx.parse(text), v > Tolerance.shortCurve else { return false }
        switch mode {
        case .line:
            guard let s = start, let c = current else { return false }
            let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
            let end = s + d * v
            createChainSegment(from: s, to: end)
            current = end
        case .circle:
            guard let s = start else { return false }
            createWalls(circleCurves(center: s, radius: v)); start = nil
        case .inscribedPolygon, .circumscribedPolygon:
            guard let s = start, let c = current else { return false }
            let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
            createWalls(polygonCurves(center: s, through: s + d * v)); start = nil
        case .filletArc:
            guard filletWalls.count == 2 else { return false }
            createFillet(v)
        default:
            return false
        }
        rebuildPreview()
        return true
    }

    /// Space flips which side of the drawn line is the exterior, for the walls still to be drawn.
    public func spaceBar() {
        flipSide.toggle()
        message(flipSide ? "Exterior side: right of the drawing direction." : "Exterior side: left of the drawing direction.")
        rebuildPreview()
    }

    public func escape() -> EscapeResult {
        if start != nil || arcEnd != nil || chainEnd != nil || !filletWalls.isEmpty { resetSteps(); return .stayInTool }
        return .exitTool
    }
}
