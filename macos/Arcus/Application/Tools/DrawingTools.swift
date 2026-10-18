import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// MARK: - Lines (model, detail, separation, boundaries, reference planes, grids)

@MainActor
public final class LineTool: BaseTool, InteractiveTool {
    public enum Kind { case detail, model, roomSeparation, areaBoundary, propertyLine, referencePlane, grid, beam, insulation
        case spaceSeparation // F5
    }
    public let kind: Kind
    public let commandID: CommandID
    var start: Vec2?
    var current: Vec2?
    public var chain: Bool
    public var arcMode = false
    var arcMid: Vec2?
    public var styleID: ElementID?
    public var insulationWidth = 0.1
    var nextGridName: String
    /// Grids only: create grids on picked lines instead of drawing them (WP6a).
    public var pickLines = false
    /// F1: the spline or ellipse being drawn (Spline, Ellipse, Partial Ellipse draw modes); nil in Line mode.
    public internal(set) var freeformDraft: FreeformDraft?

    public init(ctx: ToolContext, kind: Kind, commandID: CommandID) {
        self.kind = kind
        self.commandID = commandID
        chain = kind != .grid && kind != .referencePlane && kind != .beam && kind != .insulation
        let grids = ctx.model.elements(.grids).map(\.name)
        nextGridName = LineTool.nextName(after: grids)
        super.init(ctx: ctx)
        styleID = ctx.model.lineStyle(named: LineStyles.defaultName)?.id ?? LineStyles.sorted(ctx.model).first?.id
    }

    static func nextName(after names: [String]) -> String { GridNaming.next(after: names) } // BL-SCHED: Z → AA, unique, prefixed numbers

    public var title: String {
        switch kind {
        case .detail: "Detail Line"
        case .model: "Model Line"
        case .roomSeparation: "Room Separator"
        case .areaBoundary: "Area Boundary"
        case .propertyLine: "Property Line"
        case .referencePlane: "Reference Plane"
        case .grid: "Grid"
        case .beam: "Beam"
        case .insulation: "Insulation"
        case .spaceSeparation: "Space Separator" // F5
        }
    }
    public var prompt: String {
        if kind == .grid && pickLines { return "Click a line, wall face or CAD line to place grid \(nextGridName) on it." }
        if kind == .grid { return start == nil ? "Click to start grid \(nextGridName)." : "Click to end grid \(nextGridName), or type a length." }
        if let d = freeformDraft { return d.prompt } // F1
        return start == nil ? "Click to start the \(title.lowercased())." : "Click the end point or type a length. Esc ends the chain."
    }
    public var numericLabel: String? { start != nil ? "Length" : nil }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] {
        var o: [ToolOption] = freeformModeOptions // F1: Line, Spline, Ellipse, Partial Ellipse
        if kind == .detail || kind == .model {
            // W2-ANNOT: standard styles first, with their patterns for the Options Bar previews.
            let styles = LineStyles.sorted(ctx.model)
            var option = ToolOption(id: "style", label: "Line Style", kind: .choice(styles.map(\.name)), value: .text(ctx.model[styleID]?.name ?? ""))
            option.lineStyles = Dictionary(styles.compactMap { e in e.lineStyle.map { (e.name, $0) } }, uniquingKeysWith: { a, _ in a })
            o.append(option)
        }
        if kind == .grid { o.append(ToolOption(id: "mode", label: "Draw", kind: .choice(LineTool.gridModes), value: .text(pickLines ? "Pick Lines" : "Line"))) }
        if kind == .grid { o.append(ToolOption(id: "name", label: "Name", kind: .choice([nextGridName]), value: .text(nextGridName))) }
        if kind == .insulation { o.append(ToolOption(id: "width", label: "Width", kind: .length, value: .double(insulationWidth))) }
        if kind != .grid && kind != .referencePlane && kind != .beam && kind != .insulation {
            o.append(ToolOption(id: "chain", label: "Chain", kind: .bool, value: .bool(chain)))
            o.append(ToolOption(id: "arc", label: "Arc", kind: .bool, value: .bool(arcMode)))
        }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "style": styleID = ctx.model.lineStyle(named: value.textValue ?? "")?.id
        case "chain": chain = value.boolValue ?? true
        case "arc": arcMode = value.boolValue ?? false; arcMid = nil
        case "width": if let d = value.doubleValue, d > 0 { insulationWidth = d }
        case "name": if let s = value.textValue, !s.isEmpty { nextGridName = s }
        case "mode" where kind == .grid: pickLines = value.textValue == "Pick Lines"; start = nil; preview = ToolPreview()
        case "mode" where usesFreeformModes: setFreeformMode(value.textValue) // F1
        default: break
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        if pickLines && kind == .grid { pickLinesMoved(i); return }
        if freeformDraft != nil { freeformMoved(i); return } // F1
        current = i.point
        preview = ToolPreview()
        if let s = start {
            if arcMode, let m = arcMid, let a = Arc2(through: s, i.point, m) {
                preview.primitives.append(.arc(a, ctx.previewStroke))
            } else {
                if kind == .detail || kind == .model, let ls = ctx.model[styleID]?.lineStyle {
                    // W2-ANNOT: the rubber band shows the line style's pattern and weight (in the preview colour).
                    preview.primitives.append(.polyline([s, i.point], closed: false, GStroke(weight: ls.weight, color: ctx.previewStroke.color, pattern: ls.pattern)))
                } else {
                    preview.primitives.append(ctx.line(s, i.point, heavy: kind == .beam))
                }
                let previous = lastSegment.flatMap { $0.end.distance(to: s) < 1e-9 ? $0.direction : nil }
                preview.tempDims = [tempDim(s, i.point), angleDim(s, i.point, reference: previous)] + referenceDims(for: Segment2(s, i.point))
            }
        } else if let k = i.snap?.kind, k == .extension || k == .intersection {
            preview.tempDims = referenceDims(at: i.point)
        }
    }

    public func pointerDown(_ i: ToolInput) {
        if pickLines && kind == .grid { pickLinesDown(i); return }
        if freeformDraft != nil { freeformDown(i); return } // F1
        guard let s = start else { start = i.point; return }
        if arcMode {
            if arcMid == nil { arcMid = i.point; return }
            if let a = Arc2(through: s, i.point, arcMid!) { commit(.arc(a)); start = chain ? arcMid : nil; arcMid = nil }
            return
        }
        commit(.line(Segment2(s, i.point)))
        lastSegment = Segment2(s, i.point)
        start = chain ? i.point : nil
    }
    /// The segment just drawn in a chain: the next segment's angle is measured from it.
    var lastSegment: Segment2?

    public func numericInput(_ text: String) -> Bool {
        guard let s = start, let c = current, let len = ctx.parse(text), len > Tolerance.shortCurve else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        let e = s + d * len
        commit(.line(Segment2(s, e)))
        start = chain ? e : nil
        return true
    }

    func commit(_ c: Curve2, freeform: FreeformCurve? = nil) { // F1: freeform = a spline or ellipse with `c` its chord
        guard c.length > Tolerance.shortCurve else { return }
        let view = ctx.viewID
        let level = ctx.levelID
        switch kind {
        case .detail:
            ctx.session.perform("Create Detail Line") { tx in
                tx.create(.detailLines, data: .modelLine(ModelLineData(curve: c, styleID: styleID, freeform: freeform)), ownerViewID: view)
            }
        case .model, .roomSeparation, .areaBoundary, .propertyLine, .spaceSeparation: // F5: space separators
            let cat: Category = kind == .model ? .genericModels : kind == .roomSeparation ? .roomSeparationLines : kind == .areaBoundary ? .areaBoundaryLines
                : kind == .spaceSeparation ? .spaceSeparationLines : .propertyLines
            guard ctx.isPlan else { message("Draw these lines in a plan view."); return }
            if kind == .areaBoundary && ctx.viewData?.kind != .areaPlan { message("Draw area boundaries in an area plan (View ▸ Area Plan)."); return }
            let areaScheme = kind == .areaBoundary ? ctx.viewData?.areaSchemeID ?? AreaPlans.sortedSchemes(ctx.model).first?.id : nil
            ctx.session.perform("Create \(title)") { tx in
                // Model lines are level-hosted lines without an owner view.
                tx.create(cat == .genericModels ? .detailLines : cat, data: .modelLine(ModelLineData(curve: c, styleID: styleID, freeform: freeform)), levelID: level) { e in
                    if let areaScheme { e.params[AreaPlans.schemeParameter] = .ref(areaScheme) }
                }
            }
        case .referencePlane:
            guard let s = c.asSegment else { return }
            ctx.session.perform("Create Reference Plane") { tx in
                tx.create(.referencePlanes, name: "", data: .referencePlane(ReferencePlaneData(line: s)))
            }
        case .grid:
            guard ctx.isPlan else { message("Draw grids in a plan view."); return }
            let name = nextGridName
            ctx.session.perform("Create Grid") { tx in
                tx.create(.grids, name: name, data: .grid(GridData(curve: c)))
            }
            if ctx.session.lastError == nil { nextGridName = LineTool.nextName(after: ctx.model.elements(.grids).map(\.name)) }
        case .beam:
            guard ctx.isPlan else { message("Draw beams in a plan view."); return }
            let type = ctx.type(for: .structuralFraming)
            ctx.session.perform("Create Beam") { tx in
                tx.create(.structuralFraming, data: .beam(BeamData(curve: c)), typeID: type, levelID: level)
            }
        case .insulation:
            guard let s = c.asSegment else { return }
            ctx.session.perform("Create Insulation") { tx in
                tx.create(.insulation, data: .insulation(InsulationData(line: s, width: insulationWidth)), ownerViewID: view)
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }

    public func escape() -> EscapeResult {
        if freeformDraft.map({ !$0.points.isEmpty }) == true { freeformDraft?.reset(); preview = ToolPreview(); return .stayInTool } // F1
        if start != nil { start = nil; arcMid = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Level (elevation/section views)

@MainActor
public final class LevelTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.level
    public let title = "Level"
    var start: Vec2?
    /// Make Plan View and the plan view types it makes (on the contextual ribbon). BL-BROWSER
    public var makePlanViews = true
    public var planViewKinds: [ViewKind] = [.floorPlan, .ceilingPlan]
    public static let planViewChoices: [ViewKind] = [.floorPlan, .ceilingPlan, .structuralPlan]
    /// Draw panel: "Line" draws the level; "Pick Lines" makes one at a picked horizontal line. BL-BROWSER
    public var mode = "Line"
    var picked: Segment2?

    public var prompt: String {
        guard ctx.isVertical else { return "Levels are added in an elevation or section view." }
        if mode == "Pick Lines" { return "Click a horizontal line to create a level at its height." }
        return start == nil ? "Click to start the level line at the new elevation." : "Click to end the level line."
    }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] { [ToolOption(id: "mode", label: "Draw", kind: .choice(["Line", "Pick Lines"]), value: .text(mode))] }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "mode", let m = value.textValue { mode = m; start = nil; preview = ToolPreview() }
        if id == "plans" { makePlanViews = value.boolValue ?? true }
    }

    /// The horizontal line near the pointer, for Pick Lines.
    func pickable(_ p: Vec2) -> Segment2? {
        guard let (s, _) = ctx.snapIndex.nearestSegment(p, radius: ctx.pixel * 8), s.length > Tolerance.shortCurve,
              abs(s.end.y - s.start.y) <= s.length * 1e-3 else { return nil }
        return s
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard ctx.isVertical else { return }
        if mode == "Pick Lines" {
            picked = pickable(i.point)
            if let s = picked { preview.primitives.append(ctx.line(s.start, s.end, heavy: true)); preview.cursor = .pick }
            return
        }
        let z = start?.y ?? i.point.y
        let a = start.map { Vec2($0.x, z) } ?? Vec2(i.point.x - ctx.paper(0.03), z)
        preview.primitives.append(ctx.line(a, Vec2(i.point.x, z), heavy: true))
        if let nearest = ctx.model.levels.min(by: { abs(($0.level?.elevation ?? 0) - z) < abs(($1.level?.elevation ?? 0) - z) }), let le = nearest.level?.elevation {
            preview.tempDims = [TemporaryDimension(from: Vec2(i.point.x, le), to: Vec2(i.point.x, z), text: ctx.format(abs(z - le)), isAngle: false, isActive: false)]
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isVertical else { message("Open an elevation or section to add levels."); return }
        if mode == "Pick Lines" {
            guard let s = pickable(i.point) else { message("Click a horizontal line (a floor edge, a model or detail line)."); return }
            create(z: s.start.y, from: min(s.start.x, s.end.x), to: max(s.start.x, s.end.x))
            return
        }
        guard let s = start else { start = i.point; return }
        create(z: s.y, from: min(s.x, i.point.x), to: max(s.x, i.point.x))
        start = nil
    }

    func create(z: Double, from x0: Double, to x1: Double) {
        let kinds = makePlanViews ? planViewKinds : []
        let name = LevelNaming.nextName(ctx.model)
        let phase = ctx.model.latestPhase?.id
        let scale = ctx.scale
        ctx.session.perform("Create Level") { tx in
            var ld = LevelData(elevation: z)
            ld.extentStart = x0; ld.extentEnd = x1
            let lid = tx.create(.levels, name: name, data: .level(ld))
            for k in kinds {
                var v = ViewData(kind: k, scale: scale); v.phaseID = phase
                tx.create(.views, name: name, data: .view(v), levelID: lid)
            }
        }
        if let e = ctx.session.lastError { message(e.message) }
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}
