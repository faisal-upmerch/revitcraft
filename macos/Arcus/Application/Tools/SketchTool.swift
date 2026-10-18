import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

/// Sketch mode for boundary-based elements. Lines are drawn (line/rectangle/arc) or picked from walls;
/// Finish validates the loops and commits one transaction; Cancel restores the pre-sketch state.
@MainActor
public final class SketchTool: BaseTool, InteractiveTool {
    public enum Target: Sendable, Equatable {
        case floor, ceiling, roof, buildingPad, filledRegion, maskingRegion, revisionCloud, railing, propertyLine, callout, slopeArrow
        /// Open roof profile sketched in an elevation or section (Roof by Extrusion).
        case roofExtrusion
        /// F34: beam system bays and area, path and fabric area reinforcement boundaries (SketchTool+F34.swift).
        case f34(F34SketchTarget)
    }
    /// Draw tools of the contextual Draw panel (BL-CANVAS: the full set of the reference tool's boundary sketches).
    public enum DrawMode: String, CaseIterable {
        case line = "Line", rectangle = "Rectangle", inscribedPolygon = "Inscribed Polygon", circumscribedPolygon = "Circumscribed Polygon"
        case circle = "Circle", arc = "Start-End-Radius Arc", centerArc = "Center-ends Arc", tangentArc = "Tangent End Arc"
        case filletArc = "Fillet Arc"
        case spline = "Spline", ellipse = "Ellipse", partialEllipse = "Partial Ellipse" // F1: in RevitCraft's order, before the picks
        case pickLines = "Pick Lines", pickWalls = "Pick Walls"
    }

    public let target: Target
    public let commandID: CommandID
    /// Element being edited (Edit Boundary); nil = create new.
    public let editingID: ElementID?
    public var drawMode: DrawMode = .line
    public internal(set) var curves: [Curve2] = []
    /// Roof edges: slope per curve index (nil = non-slope-defining).
    public private(set) var slopes: [Double?] = []
    public var defaultSlope = atan(0.5)
    public var definesSlope = true
    public var overhang = 0.6
    public var extendIntoWall = false
    /// Options Bar Offset: drawn and picked lines are shifted by this distance (closed shapes grow outward). // BL-CANVAS
    public var offset = 0.0
    /// Sides of inscribed and circumscribed polygons.
    public var sides = 6
    /// Fillet Arc: indices of the sketch lines picked so far.
    var filletPicks: [Int] = []
    /// F1: the spline or ellipse being drawn (Spline, Ellipse, Partial Ellipse draw modes).
    var freeformDraft: FreeformDraft?
    /// Lines named by the last Finish error (drawn in the alert colour until the sketch changes).
    public internal(set) var errorCurves: Set<Int> = []
    public var slopeArrow: SlopeArrow?
    var start: Vec2?
    var arcEnd: Vec2?
    var current: Vec2?
    var arrowMode = false
    public var revisionID: ElementID?
    /// Roof by extrusion: reference plane used as the work plane (nil = the view's own plane).
    public var workPlaneID: ElementID?
    /// F2: roof slope arrows, eave offsets and the Align Eaves mode (SketchTool+F2.swift).
    var f2 = SketchF2State()

    public init(ctx: ToolContext, target: Target, commandID: CommandID, editing: ElementID? = nil) {
        self.target = target
        self.commandID = commandID
        self.editingID = editing
        super.init(ctx: ctx)
        if let id = editing, let e = ctx.model[id] {
            switch e.data {
            case .slab(let s): curves = s.boundary.allCurves; slopeArrow = s.slopeArrow
            case .roof(let r) where r.extrusion != nil:
                if let t = extrusionToView(r.extrusion!, e) { curves = r.extrusion!.profile.map { $0.transformed(t) } }
                workPlaneID = r.extrusion?.workPlaneID
            case .roof(let r): curves = r.footprint.loops.first ?? []; slopes = r.edgeSlopes
                for loop in r.footprint.loops.dropFirst() { curves += loop; slopes += Array(repeating: nil, count: loop.count) }
                f2.load(r) // F2: slope arrows, eave offsets
            case .filledRegion(let f): curves = f.boundary.allCurves
            case .railing(let r): curves = r.path
            case .revisionCloud(let c): curves = c.outline.edges.map { .line($0) }; revisionID = c.revisionID
            case .beamSystem, .areaReinforcement, .fabricArea: curves = F34SketchTarget.boundaryCurves(e) // F34
            default: break
            }
        }
        if target == .revisionCloud, revisionID == nil { revisionID = ctx.model.revisions.last { $0.revisionData?.issued == false }?.id ?? ctx.model.revisions.last?.id }
        if target == .roof || target == .floor || target == .ceiling { drawMode = editing == nil && target != .ceiling ? .pickWalls : .line }
    }

    public var isSketchMode: Bool { true }
    public var title: String {
        switch target {
        case .floor: "Floor Boundary"
        case .ceiling: "Ceiling Boundary"
        case .roof: "Roof Footprint"
        case .buildingPad: "Building Pad"
        case .filledRegion: "Filled Region"
        case .maskingRegion: "Masking Region"
        case .revisionCloud: "Revision Cloud"
        case .railing: "Railing Path"
        case .propertyLine: "Property Lines"
        case .callout: "Callout"
        case .slopeArrow: "Slope Arrow"
        case .roofExtrusion: "Roof Profile"
        case .f34(let t): t.title // F34
        }
    }
    public var prompt: String {
        if let p = f2Prompt { return p } // F2: Align Eaves
        if arrowMode { return start == nil ? "Click the tail of the slope arrow (low end)." : "Click the head of the slope arrow." }
        if target == .roofExtrusion, start == nil, drawMode == .line {
            return "Sketch the roof profile as an open chain of lines and arcs. Finish (↩) extrudes it perpendicular to the work plane."
        }
        switch drawMode {
        case .pickWalls: return "Click walls to add boundary lines, or click inside an enclosed area to pick all of its walls. Finish (↩) when the loop is closed."
        case .rectangle: return start == nil ? "Click the first corner." : "Click the opposite corner."
        case .arc: return start == nil ? "Click the arc start." : (arcEnd == nil ? "Click the arc end." : "Click a point on the arc.")
        case .line: return start == nil ? "Click to start a boundary line. Finish (↩) validates the sketch; Cancel discards it." : "Click the next point or type a length."
        default: return drawPrompt
        }
    }
    public var numericLabel: String? { drawMode == .line && start != nil ? "Length" : drawNumericLabel }
    public var snapFrom: Vec2? { start }

    public var options: [ToolOption] {
        var o = [ToolOption(id: "mode", label: "Draw", kind: .choice(availableModes.map(\.rawValue)), value: .text(drawMode.rawValue))]
        o += drawOptions // BL-CANVAS: Offset, Sides
        if target == .roof {
            o.append(ToolOption(id: "definesSlope", label: "Defines Slope", kind: .bool, value: .bool(definesSlope)))
            o.append(ToolOption(id: "slope", label: "Slope", kind: .angle, value: .double(defaultSlope)))
            if drawMode == .pickWalls { o.append(ToolOption(id: "overhang", label: "Overhang", kind: .length, value: .double(overhang))) }
            o.append(ToolOption(id: "arrow", label: "Slope Arrow", kind: .bool, value: .bool(arrowMode))) // F2: roof slope arrows
        }
        if target == .floor {
            o.append(ToolOption(id: "arrow", label: "Slope Arrow", kind: .bool, value: .bool(arrowMode)))
            if drawMode == .pickWalls { o.append(ToolOption(id: "extend", label: "Extend into Wall (to Core)", kind: .bool, value: .bool(extendIntoWall))) }
        }
        if target == .roofExtrusion, editingID == nil {
            // Editing keeps the roof's own work plane and extents.
            o.append(ToolOption(id: "workPlane", label: "Work Plane", kind: .choice(["View Plane"] + parallelPlanes.map(\.name)),
                                value: .text(ctx.model[workPlaneID]?.name ?? "View Plane")))
            o.append(ToolOption(id: "overhang", label: "Overhang", kind: .length, value: .double(overhang)))
        }
        if target == .revisionCloud {
            o.append(ToolOption(id: "revision", label: "Revision", kind: .choice(ctx.model.revisions.map(\.name)), value: .text(ctx.model[revisionID]?.name ?? "")))
        }
        return o
    }
    var availableModes: [DrawMode] {
        switch target {
        case .floor, .ceiling, .roof, .buildingPad: DrawMode.allCases
        case .railing, .propertyLine: [.line, .arc, .centerArc, .tangentArc, .filletArc, .pickLines, .pickWalls]
        case .callout, .revisionCloud: [.rectangle, .line]
        case .roofExtrusion: [.line, .arc, .centerArc, .tangentArc, .filletArc, .pickLines]
        default: DrawMode.allCases.filter { $0 != .pickWalls }
        }
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "mode": if let m = DrawMode(rawValue: value.textValue ?? "") ?? (value.textValue == "Arc" ? .arc : nil) { drawMode = m; start = nil; arcEnd = nil; filletPicks = [] }
        case "offset": offset = value.doubleValue ?? 0
        case "sides": if let n = value.intValue, (3...64).contains(n) { sides = n } else { message("Polygons need 3 to 64 sides.") }
        case "definesSlope": definesSlope = value.boolValue ?? true
        case "slope": if let a = value.doubleValue, a > 0, a < .pi / 2 { defaultSlope = a }
        case "overhang": overhang = value.doubleValue ?? 0
        case "extend": extendIntoWall = value.boolValue ?? false
        case "arrow": arrowMode = value.boolValue ?? false; start = nil
        case "revision": revisionID = ctx.model.revisions.first { $0.name == value.textValue }?.id
        case "workPlane": workPlaneID = parallelPlanes.first { $0.name == value.textValue }?.id
        default: break
        }
    }

    // MARK: Pointer

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        rebuild()
    }

    func rebuild() {
        preview = ToolPreview()
        preview.cursor = .crosshair
        for (k, c) in curves.enumerated() {
            var st = (target == .roof && k < slopes.count && slopes[k] != nil) ? ctx.previewHeavy : ctx.previewStroke
            if errorCurves.contains(k) || filletPicks.contains(k) { st = errorCurves.contains(k) ? Self.alertStroke : ctx.previewHeavy }
            switch c {
            case .line(let s):
                preview.primitives.append(.polyline([s.start, s.end], closed: false, st))
                if target == .roof, k < slopes.count, slopes[k] != nil {
                    let m = s.midpoint, n = s.normal * ctx.paper(0.004)
                    preview.primitives.append(.polyline([m, m + n, m + n * 0.7 + s.direction * ctx.paper(0.001)], closed: false, ctx.previewStroke))
                }
            case .arc(let a): preview.primitives.append(.arc(a, st))
            }
        }
        f2RebuildArrows() // F2: roof slope arrows, Align Eaves picks
        if let a = slopeArrow {
            preview.primitives.append(ctx.line(a.tail, a.head, heavy: true))
            let d = (a.head - a.tail).normalized
            let h = ctx.paper(0.003)
            preview.primitives.append(.polyline([a.head - d * h + d.perpendicular * h * 0.4, a.head, a.head - d * h - d.perpendicular * h * 0.4], closed: false, ctx.previewHeavy))
        }
        guard let c = current else { return }
        if drawMode == .pickWalls, !arrowMode {
            if let w = pickWall(c) { preview.highlight = [w.id]; preview.cursor = .pick }
            return
        }
        if previewDraw(at: c) { return } // BL-CANVAS: polygons, circles, arcs, fillets, picked lines
        if let s = start {
            switch drawMode {
            case .rectangle:
                preview.primitives.append(.polyline(Rect2(points: [s, c]).corners, closed: true, ctx.previewHeavy))
            case .arc:
                if let e = arcEnd, let a = Arc2(through: s, c, e) { preview.primitives.append(.arc(a, ctx.previewHeavy)) } else { preview.primitives.append(ctx.line(s, c)) }
            default:
                preview.primitives.append(ctx.line(s, c, heavy: true))
                preview.tempDims = [tempDim(s, c), angleDim(s, c)]
            }
        }
    }

    func pickWall(_ p: Vec2) -> Element? {
        let tol = ctx.pixel * 10
        return ctx.model.elements(.walls).filter { $0.levelID == ctx.levelID }.first { w in
            guard let f = WallGeometry.frame(w, ctx.model) else { return false }
            return f.location.distance(to: p) <= f.thickness / 2 + tol
        }
    }

    public func pointerDown(_ i: ToolInput) {
        let p = i.point
        if f2PointerDown(p) { rebuild(); return } // F2: Align Eaves picks
        if arrowMode {
            if let s = start {
                // Default 2% fall; adjust Slope in Properties after finishing.
                if target == .roof { f2AddRoofArrow(tail: s, head: p) } // F2: a roof keeps every arrow, at the sketch's slope
                else { slopeArrow = SlopeArrow(tail: s, head: p, slope: 0.02) }
                start = nil
                arrowMode = false
            } else { start = p }
            rebuild(); return
        }
        errorCurves = []
        if clickDraw(at: p) { rebuild(); return } // BL-CANVAS
        switch drawMode {
        case .line:
            if let s = start { add(offsetCurve(.line(Segment2(s, p)))); start = p; if closesLoop(at: p) { start = nil } } else { start = p }
        case .rectangle:
            if let s = start {
                let r = Rect2(points: [s, p])
                guard r.width > Tolerance.shortCurve, r.height > Tolerance.shortCurve else { return }
                for e in Polygon2.rectangle(offset == 0 ? r : r.expanded(by: offset)).edges { add(.line(e)) }
                start = nil
            } else { start = p }
        case .arc:
            if start == nil { start = p } else if arcEnd == nil { arcEnd = p } else if let s = start, let e = arcEnd, let a = Arc2(through: s, p, e) {
                add(offsetCurve(.arc(a))); start = e; arcEnd = nil
                if closesLoop(at: e) { start = nil }
            }
        case .pickWalls:
            if let w = pickWall(p) { addWallLine(w, toward: p) } else { pickRegion(p) }
        default: break
        }
        rebuild()
    }

    func add(_ c: Curve2) {
        guard c.length > Tolerance.shortCurve else { return }
        curves.append(c)
        slopes.append(target == .roof && definesSlope ? defaultSlope : nil)
    }

    func closesLoop(at p: Vec2) -> Bool {
        guard let first = curves.first else { return false }
        return first.start.isAlmostEqual(p, tolerance: Tolerance.length * 10) || curves.contains { $0.start.isAlmostEqual(p, tolerance: Tolerance.length * 10) && $0 != curves.last }
    }

    /// Adds the line of a wall face nearest the click (interior face for floors, exterior + overhang for roofs).
    func addWallLine(_ w: Element, toward p: Vec2) {
        guard let f = WallGeometry.frame(w, ctx.model) else { return }
        let off: Double
        switch target {
        case .roof: off = (f.location.normal(at: 0.5).dot(p - f.location.midpoint) > 0 ? f.rightOffset - overhang : f.leftOffset + overhang)
        default:
            // The face on the click side (or, with Extend into Wall, the core face on that side); a positive Offset
            // moves the line away from the click, into the wall. // BL-CANVAS
            let toLeft = f.location.normal(at: 0.5).dot(p - f.location.midpoint) > 0
            off = (extendIntoWall ? coreFaceOffset(f, left: toLeft) : (toLeft ? f.leftOffset : f.rightOffset)) + (toLeft ? -offset : offset)
        }
        add(f.location.offset(by: off))
    }

    /// Picks every wall around an enclosed region and builds a closed boundary.
    func pickRegion(_ p: Vec2) {
        guard let level = ctx.levelID else { return }
        let z = ctx.levelElevation + 0.5
        let segs = RoomGeometry.boundingSegments(level: level, atZ: z, ctx.model)
        guard let face = PlanarArrangement(segments: segs).face(containing: p) else { message("That area is not enclosed by walls."); return }
        var outline = face.outer
        if target == .roof {
            // Union the interior region with the bounding walls, then offset by the overhang.
            let walls = ctx.model.elements(.walls).filter { $0.levelID == level }.compactMap { WallGeometry.footprint($0, ctx.model) }
            let near = walls.filter { $0.bounds.intersects(outline.bounds.expanded(by: 1)) }
            if let u = PolygonBoolean.union([Profile2(outer: outline)] + near.map { Profile2(outer: $0) }).max(by: { $0.area < $1.area }) {
                outline = u.outer
            }
            if overhang > 0, let o = outline.offset(by: overhang).first { outline = o }
        }
        for e in outline.counterClockwise.simplified().edges { add(.line(e)) }
    }

    public func numericInput(_ text: String) -> Bool {
        if drawMode != .line { return drawNumericInput(text) } // BL-CANVAS
        guard drawMode == .line, let s = start, let c = current, let len = ctx.parse(text), len > Tolerance.shortCurve else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        let e = s + d * len
        add(offsetCurve(.line(Segment2(s, e))))
        start = e
        rebuild()
        return true
    }

    public func escape() -> EscapeResult {
        if start != nil || arcEnd != nil || !filletPicks.isEmpty || hasFreeformDraft { start = nil; arcEnd = nil; filletPicks = []; freeformDraft = nil; rebuild(); return .stayInTool } // F1: free-form drafts
        return .stayInTool // sketch mode requires explicit Finish or Cancel
    }

    public func cancelSketch() {
        curves = []; slopes = []
        ctx.toolFinished?()
    }

    /// Toggles "defines slope" for the roof edge nearest a point (used by the options bar/context action).
    public func toggleSlope(near p: Vec2) {
        guard target == .roof, let k = curves.indices.min(by: { curves[$0].distance(to: p) < curves[$1].distance(to: p) }) else { return }
        slopes[k] = slopes[k] == nil ? defaultSlope : nil
        rebuild()
    }

    // MARK: Finish

    public func finish() -> Bool {
        commitPendingSpline() // F1: a spline in progress becomes boundary lines
        let view = ctx.viewID
        let level = ctx.levelID
        switch target {
        case .railing, .propertyLine:
            guard !curves.isEmpty else { message("Draw at least one line."); return false }
            let path = curves
            if target == .railing {
                let t = ctx.type(for: .railings)
                ctx.session.perform(editingID == nil ? "Create Railing" : "Edit Railing Path") { tx in
                    if let id = editingID { tx.update(id) { $0.railing?.path = path } }
                    else { tx.create(.railings, data: .railing(RailingData(path: path)), typeID: t, levelID: level) }
                }
            } else {
                ctx.session.perform("Create Property Lines") { tx in
                    for c in path { tx.create(.propertyLines, data: .modelLine(ModelLineData(curve: c)), levelID: level) }
                }
            }
        case .callout:
            guard let r = curves.reduce(Rect2.empty, { $0.union($1.bounds) }) as Rect2?, !r.isEmpty else { return false }
            createCallout(r)
        case .roofExtrusion:
            guard commitExtrusion() else { return false }
        case .f34(let t) where t.isOpenPath: // F34: path reinforcement is an open chain
            guard f34FinishPath(t) else { return false }
        default:
            let loops = splitLoops(curves)
            if let issue = SketchValidation.validate(curves, loops: loops) { // BL-CANVAS: ARCUS-050
                presentSketchIssue(issue)
                return false
            }
            commitSketch(Sketch(loops: loops), view: view, level: level)
        }
        if let e = ctx.session.lastError { message(e.message); return false }
        curves = []; slopes = []
        ctx.toolFinished?()
        return true
    }

    /// Groups curves into connected loops.
    func splitLoops(_ cs: [Curve2]) -> [[Curve2]] {
        var remaining = cs
        var loops: [[Curve2]] = []
        let tol = Tolerance.length * 10
        while let first = remaining.first {
            remaining.removeFirst()
            var loop = [first]
            var changed = true
            while changed {
                changed = false
                let ends = loop.flatMap { [$0.start, $0.end] }
                if let i = remaining.firstIndex(where: { c in ends.contains { $0.isAlmostEqual(c.start, tolerance: tol) || $0.isAlmostEqual(c.end, tolerance: tol) } }) {
                    loop.append(remaining.remove(at: i)); changed = true
                }
            }
            loops.append(loop)
        }
        return loops.sorted { a, b in
            Rect2(points: a.flatMap { [$0.start, $0.end] }).width * Rect2(points: a.flatMap { [$0.start, $0.end] }).height >
            Rect2(points: b.flatMap { [$0.start, $0.end] }).width * Rect2(points: b.flatMap { [$0.start, $0.end] }).height
        }
    }

    func commitSketch(_ sketch: Sketch, view: ElementID, level: ElementID?) {
        let editing = editingID
        switch target {
        case .floor, .ceiling, .buildingPad:
            let cat: Category = target == .floor ? .floors : target == .ceiling ? .ceilings : .buildingPads
            let type = ctx.type(for: cat)
            let arrow = slopeArrow
            var created: ElementID?
            ctx.session.perform(editing == nil ? "Create \(cat.singularName)" : "Edit \(cat.singularName) Boundary") { tx in
                if let id = editing {
                    tx.update(id) { $0.slab?.boundary = sketch; $0.slab?.slopeArrow = arrow }
                } else {
                    var s = SlabData(boundary: sketch, offset: cat == .ceilings ? 2.7 : 0)
                    s.slopeArrow = arrow
                    created = tx.create(cat, data: .slab(s), typeID: type, levelID: level)
                }
            }
            if ctx.session.lastError == nil { keepSelected(created ?? editing) } // BL-CANVAS: ARCUS-049
            if cat == .floors, ctx.session.lastError == nil { offerWallAttachment(created) }
        case .roof:
            // Reorder slopes to match the outer loop order.
            let outer = sketch.loops.first ?? []
            var loopSlopes: [Double?] = []
            for c in outer {
                let idx = curves.firstIndex(of: c) ?? curves.firstIndex(of: c.reversed)
                loopSlopes.append(idx.flatMap { $0 < slopes.count ? slopes[$0] : nil })
            }
            let type = ctx.type(for: .roofs)
            let oh = overhang
            // Roofs sketched on a level sit at that level; the walls below are offered for attachment.
            var created: ElementID?
            let (arrows, offsets) = f2RoofEaves(outer) // F2: slope arrows, eave offsets
            ctx.session.perform(editing == nil ? "Create Roof" : "Edit Roof Footprint") { tx in
                if let id = editing { tx.update(id) { $0.roof?.footprint = sketch; $0.roof?.edgeSlopes = loopSlopes; $0.roof?.slopeArrows = arrows; $0.roof?.edgeOffsets = offsets } }
                else {
                    var r = RoofData(footprint: sketch, edgeSlopes: loopSlopes, overhang: oh)
                    r.slopeArrows = arrows; r.edgeOffsets = offsets
                    created = tx.create(.roofs, data: .roof(r), typeID: type, levelID: level)
                }
            }
            if ctx.session.lastError == nil { keepSelected(created ?? editing) } // BL-CANVAS: ARCUS-049
            if ctx.session.lastError == nil { offerWallAttachment(created) }
        case .filledRegion, .maskingRegion:
            let masking = target == .maskingRegion
            // W2-ANNOT: the type chosen in the type selector; masking regions have no type (a filled region type was
            // refused by validation, so Masking Region created nothing).
            let type = masking ? nil : ctx.type(for: .filledRegions)
            var created: ElementID?
            ctx.session.perform(editing == nil ? "Create \(masking ? "Masking" : "Filled") Region" : "Edit Region Boundary") { tx in
                if let id = editing { tx.update(id) { $0.filledRegion?.boundary = sketch } }
                else { created = tx.create(masking ? .maskingRegions : .filledRegions, data: .filledRegion(FilledRegionData(boundary: sketch, isMasking: masking)), typeID: type, ownerViewID: view) }
            }
            if ctx.session.lastError == nil { keepSelected(created ?? editing) } // BL-CANVAS: ARCUS-049
        case .revisionCloud:
            guard case .success(let polys) = sketch.polygons(), let outline = polys.first else { return }
            let rev = revisionID
            if let r = rev, ctx.model[r]?.revisionData?.issued == true { message("That revision is issued. Choose an unissued revision."); return }
            ctx.session.perform("Create Revision Cloud") { tx in
                if let id = editing { tx.update(id) { $0.revisionCloud?.outline = outline } }
                else { tx.create(.revisionClouds, data: .revisionCloud(RevisionCloudData(outline: outline, revisionID: rev)), ownerViewID: view) }
            }
        case .f34(let t): f34Commit(t, sketch, view: view, level: level) // F34
        default: break
        }
    }

    func createCallout(_ r: Rect2) {
        guard let parent = ctx.view, let pd = parent.view, pd.kind.isPlan else { message("Callouts are created in plan views."); return }
        let n = ctx.model.views.filter { $0.view?.parentViewID != nil }.count + 1
        ctx.session.perform("Create Callout") { tx in
            var v = pd
            v.scale = max(1, pd.scale / 2)
            v.cropRegion = r
            v.cropActive = true
            v.cropVisible = true
            v.parentViewID = parent.id
            v.visibility = pd.visibility
            tx.create(.views, name: "Callout \(n) of \(parent.name)", data: .view(v), levelID: parent.levelID)
        }
    }
}

// MARK: - Roof by extrusion

extension SketchTool {
    /// The vertical view's frame: plan origin of the view plane, its right vector and the viewing direction.
    var verticalFrame: (origin: Vec2, right: Vec2, forward: Vec2)? {
        guard let v = ctx.viewData, v.kind.isVerticalCut, let o = v.planeOrigin, let r = v.rightVector, let f = v.viewDirection?.normalized else { return nil }
        return (o.xy, r, f)
    }

    /// Reference planes parallel to the view: usable as work planes for the roof profile.
    var parallelPlanes: [Element] {
        guard let fr = verticalFrame else { return [] }
        return ctx.model.elements(.referencePlanes).filter { e in
            guard let l = e.referencePlane?.line, l.length > Tolerance.length else { return false }
            return abs(l.direction.cross(fr.right)) < 1e-3
        }
    }

    /// Maps an extruded roof's profile coordinates to this view's (u, z) coordinates; nil unless the view looks
    /// perpendicular to the roof's work plane.
    func extrusionToView(_ x: RoofExtrusion, _ roof: Element) -> Transform2? {
        guard let fr = verticalFrame, abs(fr.right.cross(x.direction)) < 1e-3 else { return nil }
        let s = fr.right.dot(x.direction) > 0 ? 1.0 : -1.0
        let b = (fr.origin - x.origin).dot(x.direction)
        let base = RoofGeometry.baseZ(roof, ctx.model)
        // px = s·u + b and y = z − base, so u = s·(px − b) and z = y + base.
        return Transform2(a: s, b: 0, c: 0, d: 1, tx: -s * b, ty: base)
    }

    /// Depth range of the walls under the profile, extended by the overhang (the default extrusion extents).
    func defaultExtents(origin: Vec2, direction: Vec2, stations: ClosedRange<Double>) -> (start: Double, end: Double) {
        let n = direction.perpendicular
        var lo = Double.infinity, hi = -Double.infinity
        for w in ctx.model.elements(.walls) {
            let b = ElementMeshes.bounds(w, ctx.model)
            guard !b.isEmpty else { continue }
            let corners = [b.min.xy, Vec2(b.max.x, b.min.y), b.max.xy, Vec2(b.min.x, b.max.y)]
            let xs = corners.map { ($0 - origin).dot(direction) }, ds = corners.map { ($0 - origin).dot(n) }
            guard let x0 = xs.min(), let x1 = xs.max(), x1 >= stations.lowerBound, x0 <= stations.upperBound else { continue }
            lo = min(lo, ds.min() ?? lo); hi = max(hi, ds.max() ?? hi)
        }
        guard lo < hi else { return (0, 10) }
        return (lo - overhang, hi + overhang)
    }

    /// Validates the open profile and creates (or updates) the extruded roof. Returns false with a message when the
    /// profile is not a single open chain.
    func commitExtrusion() -> Bool {
        guard let fr = verticalFrame else { message("Sketch a roof profile in an elevation or section."); return false }
        let chain: [Curve2]
        switch RoofExtrusionGeometry.orderedChain(curves) {
        case .failure(let err): message("\(err)"); return false
        case .success(let c): chain = c
        }
        if let id = editingID, let roof = ctx.model[id], let x = roof.roof?.extrusion {
            guard let toView = extrusionToView(x, roof) else { message("Open an elevation or section that looks straight at the roof's work plane."); return false }
            let profile = chain.map { $0.transformed(toView.inverse) }
            var updated = x
            updated.profile = profile
            if let err = RoofExtrusionGeometry.validate(updated) { message("\(err)"); return false }
            ctx.session.perform("Edit Roof Profile") { tx in tx.update(id) { $0.roof?.extrusion = updated } }
            return ctx.session.lastError == nil
        }
        // The roof hosts on the highest level at or below the profile's lowest point.
        let zs = chain.flatMap { $0.tessellate(chordTolerance: 0.01).map(\.y) }
        let minZ = zs.min() ?? 0
        let levels = ctx.model.levels
        let level = levels.filter { ($0.level?.elevation ?? 0) <= minZ + Tolerance.length }.max { ($0.level?.elevation ?? 0) < ($1.level?.elevation ?? 0) } ?? levels.first
        let baseZ = level?.level?.elevation ?? 0
        var depth = 0.0
        if let wp = workPlaneID, let l = ctx.model[wp]?.referencePlane?.line { depth = (l.start - fr.origin).dot(fr.forward) }
        let origin = fr.origin + fr.forward * depth
        let profile = chain.map { $0.transformed(Transform2(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: -baseZ)) }
        let us = chain.flatMap { [$0.start.x, $0.end.x] }
        let ext = defaultExtents(origin: origin, direction: fr.right, stations: (us.min() ?? 0)...(us.max() ?? 0))
        let x = RoofExtrusion(origin: origin, direction: fr.right, profile: profile, start: ext.start, end: ext.end, workPlaneID: workPlaneID)
        if let err = RoofExtrusionGeometry.validate(x) { message("\(err)"); return false }
        var data = RoofData(footprint: Sketch(loops: []), edgeSlopes: [])
        data.extrusion = x
        let type = ctx.type(for: .roofs)
        let levelID = level?.id
        var created: ElementID?
        ctx.session.perform("Create Roof") { tx in created = tx.create(.roofs, data: .roof(data), typeID: type, levelID: levelID) }
        guard ctx.session.lastError == nil else { return false }
        offerWallAttachment(created)
        return true
    }

    /// After a new roof or floor: highlights the walls below that reach it and asks whether to attach them.
    func offerWallAttachment(_ host: ElementID?) {
        guard let host, let e = ctx.model[host], let ask = ctx.requestConfirmation else { return }
        let walls = WallAttachment.candidates(for: e, ctx.model)
        guard !walls.isEmpty else { return }
        let session = ctx.session
        session.selection.select(walls)
        let noun = e.roof != nil ? "roof" : "floor"
        ask("Attach the \(walls.count) highlighted wall\(walls.count == 1 ? "" : "s") to the \(noun)?", "Attach") { yes in
            if yes { session.perform("Attach Walls") { tx in WallAttachment.attach(walls, to: host, in: tx) } }
            session.selection.select([host])
        }
    }
}

