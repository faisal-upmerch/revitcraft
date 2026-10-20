import Foundation
import ArcusGeometry
import ArcusDomain

// FM4: sketch mode in Furniture documents. Shelf, Top and Bottom sketch like Floor: boundary lines or Pick Panels
// (a panel's inside face, or with Extend into Panel its outside face; click inside a carcass to pick all four sides),
// Height Offset from a horizontal plane, Finish/Cancel. Edit Profile sketches a panel's outline in an elevation that
// sees its face. The forms sketch their loops (Extrusion, Blend), a profile and an axis line (Revolve) or a path and
// profiles (Sweep, Swept Blend).

/// What an FM4 sketch makes.
public enum FM4SketchTarget: Sendable, Equatable {
    /// A shelf, top or bottom.
    case shelf(FurniturePartKind)
    /// Edit Profile of a panel.
    case panelProfile(ElementID)
    case form(FurnitureFormKind, isVoid: Bool)

    public var title: String {
        switch self {
        case .shelf(let k): "\(k.rawValue) Boundary"
        case .panelProfile: "Panel Profile"
        case .form(let k, let v): (v ? "Void " : "") + k.rawValue
        }
    }

    var drawModes: [SketchTool.DrawMode] {
        switch self {
        case .shelf: [.line, .rectangle, .inscribedPolygon, .circumscribedPolygon, .circle, .arc, .centerArc, .tangentArc, .filletArc, .pickLines, .pickWalls]
        case .panelProfile: [.line, .rectangle, .arc, .centerArc, .tangentArc, .filletArc, .pickLines]
        case .form: [.line, .rectangle, .inscribedPolygon, .circumscribedPolygon, .circle, .arc, .centerArc, .tangentArc, .filletArc, .spline, .ellipse, .pickLines]
        }
    }

    /// FMG1: Sweep and Swept Blend (Pick Path, paths on any work plane).
    var isSweep: Bool { if case .form(let k, _) = self { return k == .sweep || k == .sweptBlend }; return false }

    /// Revolve axes and sweep paths are open curves next to the closed profiles.
    var allowsOpenCurves: Bool {
        if case .form(let k, _) = self { return k == .revolve || k == .sweep || k == .sweptBlend }
        return false
    }
}

/// Options of the Furniture sketches (kept for the next sketch of the same kind).
public struct FM4SketchState: Sendable {
    public var plane: String? = "Bottom"
    public var heightOffset: Double = 0.25 * 0.0254 * 3
    public var adjustable = false
    public var frontSetback = 0.0
    public var extendIntoPanel = false
    /// Forms: the extents along the work plane's normal (from the work plane), and revolve angles.
    public var start = 0.0
    public var end = 12 * 0.0254
    public var endAngle = 2 * Double.pi
    /// FMG1: Blend's two sketches (Edit Base / Edit Top): which one is being sketched, and the other one's lines.
    public var editingTop = false
    var otherSketch: [Curve2] = []
    public init() {}
}

extension SketchTool {
    /// A Furniture sketch for `target` (shelves and tops start on Pick Panels, as Floor starts on Pick Walls).
    public static func furniture(_ ctx: ToolContext, _ target: FM4SketchTarget, commandID: CommandID, editing: ElementID? = nil) -> SketchTool {
        let t = SketchTool(ctx: ctx, target: .fm4(target), commandID: commandID, editing: editing)
        switch target {
        case .shelf(let k):
            if let id = editing, let s = ctx.model[id]?.furnitureShelf {
                // Edit Boundary: the shelf's own loop, drawn with lines.
                t.curves = Polygon2(s.boundary).edges.map { .line($0) }
                t.drawMode = .line
                return t
            }
            t.drawMode = .pickWalls
            t.fm4.plane = k == .top ? "Top" : "Bottom"
            t.fm4.heightOffset = k == .top ? 0 : k == .bottom ? 0.75 * 0.0254 : 12 * 0.0254
            t.fm4.extendIntoPanel = k == .top
        case .panelProfile(let id):
            t.drawMode = .line
            if let e = ctx.model[id], let outline = t.fm4ProfileInView(e) { t.curves = Polygon2(outline).edges.map { .line($0) } }
        case .form:
            t.drawMode = .line
            t.fm4.start = 0
            t.fm4.end = 12 * 0.0254
        }
        return t
    }

    var fm4Map: FurnitureSketchMap? { FurnitureSketchMap.of(ctx.viewData) }

    // MARK: Options

    func fm4Options(_ t: FM4SketchTarget, _ base: [ToolOption]) -> [ToolOption] {
        var o = base.map { opt -> ToolOption in
            guard opt.id == "mode", case .choice(let modes) = opt.kind else { return opt }
            var x = opt
            x.kind = .choice(modes.map { $0 == DrawMode.pickWalls.rawValue ? "Pick Panels" : $0 })
            if x.value.textValue == DrawMode.pickWalls.rawValue { x.value = .text("Pick Panels") }
            // FMG1: a sweep's path is picked from lines and edges in the view (Pick Path).
            if t.isSweep {
                x.kind = .choice(modes.map { $0 == DrawMode.pickLines.rawValue ? "Pick Path" : $0 }.filter { $0 != "Pick Panels" })
                if x.value.textValue == DrawMode.pickLines.rawValue { x.value = .text("Pick Path") }
            }
            return x
        }
        switch t {
        case .shelf:
            o.append(ToolOption(id: "fm4.plane", label: "Height Offset from", kind: .choice(FurnitureToolOptions.planeNames(.z, ctx.model)), value: .text(fm4.plane ?? "")))
            o.append(ToolOption(id: "fm4.offset", label: "", kind: .length, value: .double(fm4.heightOffset)))
            if drawMode == .pickWalls { o.append(ToolOption(id: "fm4.extend", label: "Extend into Panel", kind: .bool, value: .bool(fm4.extendIntoPanel))) }
            o.append(ToolOption(id: "fm4.setback", label: "Front Setback", kind: .length, value: .double(fm4.frontSetback)))
            if case .shelf(.shelf) = t { o.append(ToolOption(id: "fm4.adjustable", label: "Adjustable", kind: .bool, value: .bool(fm4.adjustable))) }
        case .panelProfile:
            break
        case .form(let k, _):
            switch k {
            case .extrusion:
                o.append(ToolOption(id: "fm4.end", label: "Depth", kind: .length, value: .double(fm4.end)))
                o.append(ToolOption(id: "fm4.start", label: "Start", kind: .length, value: .double(fm4.start)))
            case .blend:
                o.append(ToolOption(id: "fm4.end", label: "Second End", kind: .length, value: .double(fm4.end)))
                o.append(ToolOption(id: "fm4.start", label: "First End", kind: .length, value: .double(fm4.start)))
            case .revolve:
                o.append(ToolOption(id: "fm4.angle", label: "End Angle", kind: .angle, value: .double(fm4.endAngle)))
            case .sweep, .sweptBlend:
                // FMG1: in a plan the path's height above the level; in an elevation its offset from the work plane.
                o.append(ToolOption(id: "fm4.start", label: ctx.isPlan ? "Elevation" : "Offset from Work Plane", kind: .length, value: .double(fm4.start)))
            case .cushion:
                break
            }
        }
        return o
    }

    /// True when handled.
    func fm4SetOption(_ t: FM4SketchTarget, _ id: String, _ v: ParamValue) -> Bool {
        switch id {
        case "mode" where v.textValue == "Pick Panels":
            drawMode = .pickWalls; start = nil; arcEnd = nil; filletPicks = []
        case "mode" where v.textValue == "Pick Path": // FMG1
            drawMode = .pickLines; start = nil; arcEnd = nil; filletPicks = []
        case "fm4.plane": fm4.plane = v.textValue
        case "fm4.offset": fm4.heightOffset = v.doubleValue ?? 0
        case "fm4.extend": fm4.extendIntoPanel = v.boolValue ?? false
        case "fm4.setback": fm4.frontSetback = max(0, v.doubleValue ?? 0)
        case "fm4.adjustable": fm4.adjustable = v.boolValue ?? false
        case "fm4.start": fm4.start = v.doubleValue ?? 0
        case "fm4.end": fm4.end = v.doubleValue ?? fm4.end
        case "fm4.angle": if let a = v.doubleValue, abs(a) > 1e-3 { fm4.endAngle = min(2 * .pi, a) }
        default: return false
        }
        rebuild()
        return true
    }

    // MARK: Pick Panels

    /// The panel under a plan point.
    func fm4Panel(at p: Vec2) -> Element? {
        guard ctx.isPlan, let map = fm4Map else { return nil }
        return FurnitureToolOptions.parts(at: p, [.furniturePanels], map: map, tolerance: ctx.pixel * 6, ctx.model).first
    }

    /// Pick Panels preview: the panel under the pointer highlights. True when handled.
    func fm4Preview(at c: Vec2) -> Bool {
        guard drawMode == .pickWalls, case .fm4(.shelf) = target else { return false }
        if let e = fm4Panel(at: c) {
            preview.highlight = [e.id]
            preview.cursor = .pick
            if let line = fm4PickLine(e, toward: c) { preview.primitives.append(ctx.line(line.start, line.end, heavy: true)) }
        }
        return true
    }

    func fm4PickLine(_ e: Element, toward p: Vec2) -> Segment2? {
        var off = offset
        if case .fm4(.shelf(.top)) = target, fm4.extendIntoPanel { off += FurniturePartTypes.Values(ctx.model[FurnitureToolOptions.type(.furnitureShelves, family: "Top", ctx)]?.typeData).overhang }
        return FurniturePartOperations.pickPanelLine(e, toward: p, offset: off, extendIntoPanel: fm4.extendIntoPanel, ctx.model)
    }

    /// Pick Panels click: a panel adds its line; inside a carcass, its four sides (planes where there's no panel).
    func fm4PointerDown(_ p: Vec2) -> Bool {
        guard drawMode == .pickWalls, case .fm4(.shelf) = target else { return false }
        if let e = fm4Panel(at: p), let line = fm4PickLine(e, toward: p) {
            add(.line(line))
            fm4CloseLoop()
            return true
        }
        // Inside a carcass: the nearest panel face (or plane) on each side.
        let m = ctx.model
        let boxes = m.elements(.furniturePanels).compactMap { FurniturePartSolids.partBox($0, m)?.box }
        let planes = FurniturePlanes.positionsByName(m)
        let ext = fm4.extendIntoPanel
        var l = planes["Left"], r = planes["Right"], f = planes["Front"], b = planes["Back"]
        for bx in boxes {
            if bx.min.y <= p.y, bx.max.y >= p.y {
                if bx.max.x <= p.x { let v = ext ? bx.min.x : bx.max.x; if l.map({ v > $0 }) ?? true { l = v } }
                if bx.min.x >= p.x { let v = ext ? bx.max.x : bx.min.x; if r.map({ v < $0 }) ?? true { r = v } }
            }
            if bx.min.x <= p.x, bx.max.x >= p.x {
                if bx.max.y <= p.y { let v = ext ? bx.min.y : bx.max.y; if f.map({ v > $0 }) ?? true { f = v } }
                if bx.min.y >= p.y { let v = ext ? bx.max.y : bx.min.y; if b.map({ v < $0 }) ?? true { b = v } }
            }
        }
        guard let x0 = l, let x1 = r, let y0 = f, let y1 = b, x1 - x0 > Tolerance.length, y1 - y0 > Tolerance.length else {
            message("Click a panel, or inside the panels round the shelf.")
            return true
        }
        for e in Polygon2.rectangle(Rect2(min: Vec2(x0, y0), max: Vec2(x1, y1))).edges { add(.line(e)) }
        return true
    }

    /// Picked lines meet: each is trimmed or extended to its neighbours once three or more form a loop.
    func fm4CloseLoop() {
        let lines = curves.compactMap(\.asSegment)
        guard lines.count == curves.count, lines.count >= 3, let loop = FurniturePartOperations.closeLoop(lines) else { return }
        // Only when every line is near the loop (they were picked round one space).
        let poly = Polygon2(loop)
        guard lines.allSatisfy({ poly.distanceToBoundary($0.midpoint) < max($0.length, 0.05) }) else { return }
        curves = poly.edges.map { .line($0) }
    }

    // MARK: Panel profile

    /// A panel's outline in this view's coordinates, when the view sees its face square on.
    func fm4ProfileInView(_ e: Element) -> [Vec2]? {
        guard let p = e.furniturePanel, p.plane == .xy, let map = fm4Map, map.plane != .xy,
              let f = FurniturePartSolids.linearFrame(p.plane, p.start, p.end), FamilySketchPlane.normal(f.crossAxis) == map.plane else { return nil }
        let outline = p.profile ?? [Vec2(0, 0), Vec2(p.length, 0), Vec2(p.length, p.height), Vec2(0, p.height)]
        let u0 = f.lineAlongU ? p.start.x : p.start.y
        return outline.map { st in map.toView(Vec2(u0 + st.x * f.along, p.base + st.y)) }
    }

    /// A view outline in the panel's face coordinates.
    func fm4ProfileFromView(_ e: Element, _ pts: [Vec2]) -> [Vec2]? {
        guard let p = e.furniturePanel, let map = fm4Map, let f = FurniturePartSolids.linearFrame(p.plane, p.start, p.end) else { return nil }
        let u0 = f.lineAlongU ? p.start.x : p.start.y
        return pts.map { v in let s = map.toSketch(v); return Vec2((s.x - u0) * f.along, s.y - p.base) }
    }

    // MARK: Finish

    /// The work plane position of a form sketched in this view (Ref. Level in plans; the view side's plane in elevations).
    var fm4WorkPlane: Double {
        if let p = ctx.furniture3D, let map = fm4Map, p.axis == map.plane.axes.w { return p.depth } // FM3D: the 3D view's work plane
        guard let map = fm4Map, map.plane != .xy else { return ctx.levelElevation }
        let planes = FurniturePlanes.positionsByName(ctx.model)
        let f = map.forward
        let name: String
        switch map.plane {
        case .xz: name = f.y > 0 ? "Front" : "Back"
        default: name = f.x > 0 ? "Left" : "Right"
        }
        return planes[name] ?? 0
    }

    func fm4Commit(_ t: FM4SketchTarget, _ sketch: Sketch) {
        guard case .success(let polys) = sketch.polygons(quality: .fine), let outer = polys.max(by: { $0.area < $1.area }) else { message("Sketch a closed loop."); return } // VIS: arcs kept round
        switch t {
        case .shelf(let k):
            if let id = editingID {
                let pts = outer.counterClockwise.points
                ctx.session.perform("Edit \(k.rawValue) Boundary") { tx in
                    tx.update(id) { e in
                        guard var d = e.furnitureShelf else { return }
                        d.boundary = pts
                        d.bounds = d.bounds.filter { !$0.key.hasPrefix("p") }
                        e.furnitureShelf = d
                    }
                }
                if ctx.session.lastError == nil { keepSelected(id) }
                return
            }
            let s = fm4
            let family = k == .top ? "Top" : "Shelf"
            let type = FurnitureToolOptions.type(.furnitureShelves, family: family, ctx)
            var created: ElementID?
            ctx.session.perform("Create \(k.rawValue)") { tx in
                created = try FurniturePartOperations.createShelf(boundary: outer.points, plane: s.plane, offset: s.heightOffset, role: k, adjustable: s.adjustable && k == .shelf,
                                                                  frontSetback: s.frontSetback, typeID: type, in: tx)
            }
            if ctx.session.lastError == nil { keepSelected(created) }
        case .panelProfile(let id):
            guard let e = ctx.model[id], let outline = fm4ProfileFromView(e, outer.points) else { message("Edit the profile in an elevation that sees the panel's face."); return }
            ctx.session.perform("Edit Panel Profile") { tx in try FurniturePartOperations.setProfile(id, outline, in: tx) }
            if ctx.session.lastError == nil { keepSelected(id) }
        case .form(let k, let isVoid):
            guard let map = fm4Map else { message("Sketch forms in a plan, or in an elevation square to the piece."); return }
            let w = fm4WorkPlane
            var f: FurnitureFormData
            switch k {
            case .blend:
                guard ctx.isPlan, polys.count >= 2 else { message("Sketch two loops in a plan: the base, then the top."); return }
                let sorted = polys.sorted { $0.area > $1.area }
                f = FurnitureFormData(kind: .blend, isVoid: isVoid, profile: sorted[0].points, w0: w + fm4.start, w1: w + fm4.end)
                f.topProfile = sorted[1].points
            default:
                let toSketch = { (p: Vec2) in map.toSketch(p) }
                let up = ctx.furniture3D?.extrusionSign ?? 1 // FM3D: out of a picked face (down from a bottom face)
                f = FurnitureFormData(kind: .extrusion, isVoid: isVoid, plane: map.plane, profile: outer.points.map(toSketch),
                                      w0: w + min(up * fm4.start, up * fm4.end), w1: w + max(up * fm4.start, up * fm4.end))
                f.holes = polys.filter { $0 != outer }.map { $0.points.map(toSketch) }
                // In an elevation the extrusion runs from the work plane into the view.
                if map.plane != .xy {
                    let sign: Double = ctx.furniture3D?.extrusionSign ?? ((map.plane == .xz ? map.forward.y : map.forward.x) > 0 ? 1 : -1) // FM3D
                    let a = w + sign * fm4.start, b = w + sign * fm4.end
                    f.w0 = min(a, b); f.w1 = max(a, b)
                }
            }
            guard f.kind != .extrusion || f.w1 - f.w0 > Tolerance.length else { message("Give the extrusion a depth."); return }
            if fm3dUpdateExtrusion(f) { return } // FM3D: Edit Sketch of a selected extrusion
            var created: ElementID?
            ctx.session.perform("Create \(t.title)") { tx in created = try FurniturePartOperations.createForm(f, in: tx) }
            if ctx.session.lastError == nil { keepSelected(created) }
        }
    }

    /// Revolve, Sweep and Swept Blend: closed profiles and an open axis line or path.
    func fm4FinishForm(_ t: FM4SketchTarget) -> Bool {
        guard case .form(let k, let isVoid) = t, let map = fm4Map else { return false }
        let groups = splitLoops(curves)
        func closed(_ g: [Curve2]) -> Bool {
            guard let first = g.first else { return false }
            let ends = g.flatMap { [$0.start, $0.end] }
            return g.count >= 2 && ends.allSatisfy { p in ends.filter { $0.isAlmostEqual(p, tolerance: Tolerance.length * 10) }.count >= 2 } && first.length > 0
        }
        let loops = groups.filter(closed).compactMap { g -> Polygon2? in
            guard case .success(let polys) = Sketch(loops: [g]).polygons(quality: .fine) else { return nil } // VIS
            return polys.first
        }
        let open = groups.filter { !closed($0) }
        var f: FurnitureFormData
        switch k {
        case .revolve:
            guard !ctx.isPlan, let prof = loops.first, let axisLine = open.first?.first?.asSegment, abs(axisLine.direction.x) < 1e-6 else {
                message("Sketch a closed profile and a vertical axis line in an elevation.")
                return false
            }
            let au = map.toSketch(axisLine.start).x
            let pts = prof.points.map { map.toSketch($0) }
            let z0 = pts.map(\.y).min() ?? 0
            let profile = pts.map { Vec2(abs($0.x - au), $0.y - z0) }
            let w = fm4WorkPlane
            f = FurnitureFormData(kind: .revolve, isVoid: isVoid, profile: profile, w0: z0, w1: z0)
            f.axis = map.plane == .xz ? Vec2(au, w) : Vec2(w, au)
            f.endAngle = fm4.endAngle
        case .sweep, .sweptBlend:
            guard let pathCurves = open.first, let prof = loops.first, k == .sweep || loops.count >= 2 else {
                message(k == .sweep ? "Sketch or pick a path (open lines) and a closed profile." : "Sketch or pick a path and two closed profiles.")
                return false
            }
            // FMG1: the path lies on the view's work plane: the level in a plan, the view side's plane in an elevation or
            // section; the profile stands up from a plan path, or reaches into the view from an elevation path.
            var path: [Vec2] = []
            for c in orderedChain(pathCurves) {
                for p in (c.asArc.map { $0.tessellate(quality: .fine) } ?? c.tessellate(chordTolerance: 0.002)) { // VIS
                    let q = ctx.isPlan ? p : map.toSketch(p)
                    if path.last.map({ !$0.isAlmostEqual(q) }) ?? true { path.append(q) }
                }
            }
            let into: Double = ctx.isPlan ? 1 : ((map.plane == .xz ? map.forward.y : map.forward.x) > 0 ? 1 : -1)
            func local(_ poly: Polygon2) -> [Vec2] { let b = poly.bounds; return poly.points.map { Vec2($0.x - b.center.x, into * ($0.y - b.min.y)) } }
            let w0 = ctx.isPlan ? fm4WorkPlane + fm4.start : fm4WorkPlane + into * fm4.start // FM3D: the plan's work plane is the level's, or the 3D view's
            f = FurnitureFormData(kind: k, isVoid: isVoid, plane: ctx.isPlan ? .xy : map.plane, profile: local(prof), w0: w0, w1: 0)
            f.path = path
            if k == .sweptBlend { f.endProfile = local(loops[1]) }
        default:
            return false
        }
        var created: ElementID?
        ctx.session.perform("Create \(t.title)") { tx in created = try FurniturePartOperations.createForm(f, in: tx) }
        guard ctx.session.lastError == nil else { message(ctx.session.lastError?.message ?? ""); return false }
        keepSelected(created)
        return true
    }

    /// Open curves in order from one end.
    func orderedChain(_ cs: [Curve2]) -> [Curve2] {
        var rest = cs
        let tol = Tolerance.length * 10
        let ends = cs.flatMap { [$0.start, $0.end] }
        let startPoint = ends.first { p in ends.filter { $0.isAlmostEqual(p, tolerance: tol) }.count == 1 } ?? cs.first?.start ?? .zero
        var out: [Curve2] = []
        var cur = startPoint
        while !rest.isEmpty {
            if let i = rest.firstIndex(where: { $0.start.isAlmostEqual(cur, tolerance: tol) }) { let c = rest.remove(at: i); out.append(c); cur = c.end }
            else if let i = rest.firstIndex(where: { $0.end.isAlmostEqual(cur, tolerance: tol) }) { let c = rest.remove(at: i).reversed; out.append(c); cur = c.end }
            else { out += rest; break }
        }
        return out
    }
}
