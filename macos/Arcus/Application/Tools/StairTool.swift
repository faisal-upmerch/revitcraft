import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// STAIR: Stair (ST) and Edit Stairs — Revit's "Modify | Create Stair" sketch mode, Stair by Component.
//
// Components: Run (Straight, Full-Step Spiral, Center-Ends Spiral, L-Shape Winder, U-Shape Winder, Create Sketch with
// Boundary, Riser and Stair Path lines), Landing (Pick Two Runs, Create Sketch) and Support (Pick Edges). The Options
// Bar has Location Line, Offset, Actual Run Width and Automatic Landing. While a run is drawn the readout says how many
// risers it creates and how many remain to reach the top ("8 RISERS CREATED, 10 REMAINING"); the run end snaps to whole
// treads. Runs drawn after a turn get an automatic landing. Esc leaves the current drawing tool for selecting the
// sketch's runs and landings, whose grips (run ends, width arrows) edit them. Finish Edit Mode creates (or updates) the
// stair, with railings as set in Tools ▸ Railing; Cancel Edit Mode discards the sketch.

/// The Create Stair / Edit Stairs tool. (Named `StairTool` so the older Stair commands and Connect Levels keep working.)
@MainActor
public final class StairTool: BaseTool, InteractiveTool {
    public enum Component: String, CaseIterable, Sendable { case run = "Run", landing = "Landing", support = "Support" }
    public enum RunMode: String, CaseIterable, Sendable {
        case straight = "Straight", fullStepSpiral = "Full-Step Spiral", centerEndsSpiral = "Center-Ends Spiral"
        case lWinder = "L-Shape Winder", uWinder = "U-Shape Winder", sketch = "Create Sketch"
    }
    public enum LandingMode: String, CaseIterable, Sendable { case pickTwoRuns = "Pick Two Runs", sketch = "Create Sketch" }
    /// What a sketched run's next lines are (Run ▸ Create Sketch).
    public enum SketchLine: String, CaseIterable, Sendable { case boundary = "Boundary", riser = "Riser", path = "Stair Path" }
    /// A component of the sketch selected for editing.
    public enum Selection: Equatable, Sendable { case run(Int), landing(Int) }
    /// Grips of a selected run.
    public enum Grip: Equatable, Sendable { case start, end, widthLeft, widthRight, body }

    public let editingID: ElementID?
    public var commandID: CommandID { editingID == nil ? .stair : .editStair }
    public var title: String { editingID == nil ? "Stair" : "Edit Stairs" }
    public var isSketchMode: Bool { true }

    /// The stair being sketched (levels, offsets, runs, landings, supports).
    public internal(set) var draft: StairData
    public var component: Component = .run { didSet { if oldValue != component { resetStep(); modifying = false } } }
    public var runMode: RunMode = .straight { didSet { if oldValue != runMode { resetStep(); modifying = false } } }
    public var landingMode: LandingMode = .pickTwoRuns { didSet { if oldValue != landingMode { resetStep(); modifying = false } } }
    public var sketchLine: SketchLine = .boundary { didSet { chain = [] } }
    /// Esc left the drawing tools: clicks select the sketch's components.
    public internal(set) var modifying = false
    public var locationLine: StairLocationLine = .runCenter
    public var offset = 0.0
    public var width: Double
    public var automaticLanding = true
    /// Tools ▸ Railing: the railing type the stair gets (nil = None) and its position.
    public var railingTypeID: ElementID?
    public var railingPosition: StairRailingPosition = .treads
    /// Older option: railings on or off (the Railing setting's None).
    public var railings: Bool {
        get { railingTypeID != nil }
        set { railingTypeID = newValue ? (railingTypeID ?? Self.defaultRailingType(ctx.model)) : nil }
    }
    public var topLevelID: ElementID? { get { draft.topLevelID } set { draft.topLevelID = newValue } }
    /// F2: Connect Levels while placing: the stair repeats up to this level (multistory).
    public var multistoryTopLevelID: ElementID? { get { draft.multistoryTopLevelID } set { draft.multistoryTopLevelID = newValue } }

    // Drawing state.
    var clicks: [Vec2] = []
    var current: Vec2?
    /// Quarter turns of a winder run's direction (Space), and whether it turns right.
    var winderTurns = 0
    var spiralClockwise = false
    /// Center-Ends Spiral: the sweep followed continuously from the start point.
    var spiralSweep = 0.0
    var lastPointerAngle: Double?
    /// Run ▸ Create Sketch: the run being sketched and the line chain in progress.
    public internal(set) var runSketch: StairRunSketch?
    var chain: [Vec2] = []
    /// Landing ▸ Create Sketch: the boundary points so far; Pick Two Runs: the first run picked.
    var landingPoints: [Vec2] = []
    var pickedRun: Int?
    // Modifying.
    public internal(set) var selection: Selection?
    var dragging: Grip?
    var dragStart: Vec2?
    var dragBase: StairData?
    var hoverGrip: Grip?

    /// A new stair (Architecture ▸ Stair). `shape` is kept for the older Stair commands, which open the same tool.
    public init(ctx: ToolContext, shape: StairShape = .straight) {
        let type = StairTypeInfo.of(type: ctx.type(for: .stairs).flatMap { ctx.model[$0]?.typeData }, ctx.model)
        width = max(1.1, type.minRunWidth)
        var d = StairData(origin: .zero, direction: 0, width: width, topLevelID: ctx.model.levelAbove(ctx.levelID)?.id)
        d.runs = []
        draft = d
        editingID = nil
        super.init(ctx: ctx)
        railingTypeID = Self.defaultRailingType(ctx.model)
        _ = shape
    }

    /// Edit Stairs on a placed stair; an older stair is read as its runs and landings first.
    public init?(ctx: ToolContext, editing id: ElementID) {
        guard let e = ctx.model[id], var s = e.stair else { return nil }
        if !s.isComponentStair, let comps = StairGeometry.components(e, ctx.model) {
            s.runs = comps.runs
            s.landings = comps.landings
        }
        editingID = id
        draft = s
        width = s.runs?.first?.width ?? s.width
        super.init(ctx: ctx)
        railingTypeID = ctx.model.hosted(by: id).first { $0.railing != nil }?.typeID
        railingPosition = ctx.model.hosted(by: id).first { $0.railing != nil }?.railing?.stairPosition ?? .treads
        modifying = true
        rebuild()
    }

    static func defaultRailingType(_ m: BIMModel) -> ElementID? {
        let types = m.types(for: .railings)
        return types.first { ($0.typeData?.params[RailingTypeParam.height]?.doubleValue ?? 0) > 1.0 }?.id ?? types.first?.id
    }

    // MARK: The stair being sketched

    var stairTypeID: ElementID? { editingID.flatMap { ctx.model[$0]?.typeID } ?? ctx.type(for: .stairs) }
    var levelID: ElementID? { editingID.flatMap { ctx.model[$0]?.levelID } ?? ctx.levelID }

    /// The sketch as a stair element (with the Properties palette's values for a new stair), plus `extra` runs.
    func probe(_ data: StairData? = nil) -> Element {
        var d = data ?? draft
        if d.runs?.isEmpty ?? true { d.runs = [StairRun(start: .zero, direction: 0, risers: 2, width: width)] }
        var e = Element(id: editingID ?? ElementID(UInt64.max - 2), category: .stairs, data: .stair(d), typeID: stairTypeID, levelID: levelID)
        if editingID == nil, let defaults = ctx.session.creationDefaults, !defaults.isEmpty {
            let tx = TransactionContext(model: ctx.model, name: "Probe")
            let pid = tx.create(.stairs, data: .stair(d), typeID: stairTypeID, levelID: levelID)
            for v in defaults.values { try? Parameters.set(v.id, to: v.value, on: pid, in: tx) }
            if let p = tx.model[pid] { e.data = p.data; e.levelID = p.levelID }
        }
        return e
    }

    /// Riser height, tread depth and the risers the stair needs.
    var numbers: (desired: Int, riser: Double, tread: Double, base: Double)? {
        StairGeometry.numbers(probe(), ctx.model).map { ($0.desired, $0.riser, $0.tread, $0.base) }
    }
    var type: StairTypeInfo { StairTypeInfo.of(type: stairTypeID.flatMap { ctx.model[$0]?.typeData }, ctx.model) }
    var runs: [StairRun] { draft.runs ?? [] }
    var risersSoFar: Int { runs.reduce(0) { $0 + $1.risers } }
    var remaining: Int { (numbers?.desired ?? 0) - risersSoFar }
    /// The sketch's layout (nil without runs).
    func layout(_ data: StairData? = nil) -> StairLayout? {
        let d = data ?? draft
        guard !(d.runs?.isEmpty ?? true) else { return nil }
        return StairGeometry.layout(probe(d), ctx.model)
    }

    /// Adds a run (with its automatic landing when Automatic Landing is on).
    func add(_ run: StairRun) {
        var runs = self.runs
        runs.append(run)
        draft.runs = runs
        if !automaticLanding || draft.landings != nil {
            var list = draft.landings ?? (0..<max(0, runs.count - 2)).map { StairLanding(afterRun: $0) }
            if automaticLanding, runs.count >= 2 { list.append(StairLanding(afterRun: runs.count - 2)) }
            draft.landings = list
        }
    }

    // MARK: Options Bar

    public var options: [ToolOption] {
        var o: [ToolOption] = []
        if component == .run && !modifying && runSketch == nil {
            o.append(ToolOption(id: "locationLine", label: "Location Line", kind: .choice(StairLocationLine.allCases.map(\.rawValue)), value: .text(locationLine.rawValue)))
            o.append(ToolOption(id: "offset", label: "Offset", kind: .length, value: .double(offset)))
            o.append(ToolOption(id: "width", label: "Actual Run Width", kind: .length, value: .double(width)))
            o.append(ToolOption(id: "automaticLanding", label: "Automatic Landing", kind: .bool, value: .bool(automaticLanding)))
        }
        if modifying, let s = selection {
            switch s {
            case .run(let i) where runs.indices.contains(i):
                o.append(ToolOption(id: "selWidth", label: "Actual Run Width", kind: .length, value: .double(runs[i].width)))
                o.append(ToolOption(id: "selRisers", label: "Risers", kind: .integer, value: .int(runs[i].risers)))
                o.append(ToolOption(id: "delete", label: "Delete Run", kind: .button, value: .bool(false)))
            case .landing:
                o.append(ToolOption(id: "delete", label: "Delete Landing", kind: .button, value: .bool(false)))
            default: break
            }
        }
        return o
    }

    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "locationLine": if let l = StairLocationLine(rawValue: value.textValue ?? "") { locationLine = l }
        case "offset": offset = value.doubleValue ?? offset
        case "width":
            if let w = value.doubleValue, w >= 0.3 { width = w } else { message("A stair run must be at least 300 mm wide.") }
        case "automaticLanding": automaticLanding = value.boolValue ?? true
        case "selWidth":
            if case .run(let i)? = selection, let w = value.doubleValue, w >= 0.3, runs.indices.contains(i) { draft.runs?[i].width = w }
        case "selRisers":
            if case .run(let i)? = selection, let n = value.intValue, (1...200).contains(n), runs.indices.contains(i) { setRisers(i, n) }
        case "delete": deleteSelection()
        default: break
        }
        rebuild()
    }

    // MARK: Ribbon commands

    /// Run, Landing or Support (Components panel).
    public func choose(_ c: Component) { component = c; rebuild() }
    public func choose(_ m: RunMode) {
        component = .run
        runMode = m
        if m == .sketch, runSketch == nil { runSketch = StairRunSketch(); sketchLine = .boundary }
        rebuild()
    }
    public func choose(_ m: LandingMode) { component = .landing; landingMode = m; rebuild() }
    public func choose(_ l: SketchLine) { sketchLine = l; modifying = false; rebuild() }

    /// Tools ▸ Flip: reverses the stair's up direction (the top becomes the bottom), runs and landings kept in place.
    public func flip() {
        guard let l = layout(), !l.runs.isEmpty else { message("Draw a run first."); return }
        var flipped: [StairRun] = []
        for r in l.runs.reversed() {
            guard let src = runs.indices.contains(r.index) ? runs[r.index] : nil else { continue }
            var n = src
            switch src.shape {
            case .straight:
                n.start = r.endEdge.midpoint
                n.direction = (-r.endDirection).angle
            case .spiral:
                n.start = r.walk.last ?? src.start
                n.turnsLeft = !(src.turnsLeft ?? true)
                n.direction = (-r.endDirection).angle
            case .lWinder, .uWinder:
                n.start = r.endEdge.midpoint
                n.direction = (-r.endDirection).angle
                n.turnsLeft = !(src.turnsLeft ?? true)
                n.legTreads = StairRunGeometryAccess.reversedLegs(src, treads: r.treads.count)
            case .sketch:
                if var k = src.sketch { k.path = k.path.reversed().map(\.reversed); n.sketch = k }
            }
            flipped.append(n)
        }
        draft.runs = flipped
        let count = flipped.count
        draft.landings = draft.landings.map { list in
            list.map { l in var x = l; x.afterRun = l.afterRun.map { count - 2 - $0 }; return x }
        }
        draft.supports = draft.supports?.map { s in var x = s; x.run = s.run.map { count - 1 - $0 }; x.side = s.side == .left ? .right : .left; return x }
        selection = nil
        rebuild()
    }

    // MARK: Finish / Cancel

    public func finish() -> Bool {
        if runSketch != nil { return finishRunSketch() }
        if component == .landing, landingMode == .sketch, landingPoints.count >= 3 { closeLandingSketch(); return true }
        guard !runs.isEmpty else { message("Draw at least one run, or Cancel Edit Mode."); return false }
        var data = draft
        if let p = probe().stair { data = p; data.runs = draft.runs; data.landings = draft.landings; data.supports = draft.supports }
        data.width = runs.first?.width ?? width
        let level = levelID
        let typeID = stairTypeID
        let railType = railingTypeID
        let position = railingPosition
        if let id = editingID {
            ctx.session.perform("Edit Stairs") { tx in
                tx.update(id) { $0.stair = data }
                for r in tx.model.hosted(by: id) where r.railing != nil {
                    if railType == nil { tx.delete(r.id) } else {
                        tx.update(r.id) { $0.typeID = railType; $0.railing?.stairPosition = position }
                    }
                }
                if let rt = railType, !tx.model.hosted(by: id).contains(where: { $0.railing != nil }) {
                    Self.createRailings(tx, stair: id, type: rt, position: position, level: level)
                }
            }
        } else {
            ctx.session.perform("Create Stair") { tx in
                let sid = tx.create(.stairs, data: .stair(data), typeID: typeID, levelID: level)
                if let rt = railType { Self.createRailings(tx, stair: sid, type: rt, position: position, level: level) }
            }
        }
        if let err = ctx.session.lastError { message(err.message); return false }
        for w in ctx.session.lastWarnings { message(w.message) }
        ctx.toolFinished?()
        return true
    }

    /// A railing on each side of a new stair.
    static func createRailings(_ tx: TransactionContext, stair: ElementID, type: ElementID, position: StairRailingPosition, level: ElementID?) {
        for left in [true, false] {
            var rd = RailingData(path: [])
            rd.followsHost = true
            rd.hostSideLeft = left
            rd.stairPosition = position
            tx.create(.railings, data: .railing(rd), typeID: type, levelID: level, hostID: stair)
        }
    }

    public func cancelSketch() {
        if runSketch != nil { runSketch = nil; chain = []; runMode = .straight; rebuild(); return }
        ctx.toolFinished?()
    }

    public func escape() -> EscapeResult {
        if dragging != nil { dragging = nil; if let b = dragBase { draft = b }; dragBase = nil }
        else if !chain.isEmpty { chain = [] }
        else if !clicks.isEmpty || !landingPoints.isEmpty || pickedRun != nil { resetStep() }
        else if selection != nil { selection = nil }
        else if !modifying { modifying = true }
        rebuild()
        return .stayInTool
    }

    func resetStep() {
        clicks = []; landingPoints = []; pickedRun = nil; chain = []; spiralSweep = 0; lastPointerAngle = nil
    }

    public func spaceBar() {
        switch runMode {
        case .lWinder, .uWinder:
            winderTurns += 1
            if winderTurns % 4 == 0 { spiralClockwise.toggle() }
        case .fullStepSpiral, .centerEndsSpiral: spiralClockwise.toggle()
        default: break
        }
        rebuild()
    }

    public var snapFrom: Vec2? { runSketch != nil ? chain.last : (clicks.last ?? landingPoints.last) }

    /// The sketch's run and landing edges snap and align like drawn lines.
    public var snapCurves: [Curve2] {
        guard let l = layout() else { return SnapIndex.chain(chain) }
        var out: [Curve2] = []
        for r in l.runs {
            for e in [r.left.map(\.point), r.right.map(\.point)] { out += zip(e, e.dropFirst()).map { .line(Segment2($0, $1)) } }
            out.append(.line(r.startEdge)); out.append(.line(r.endEdge))
        }
        for land in l.landings { out += land.polygon.edges.map { .line($0) } }
        return out + SnapIndex.chain(chain)
    }

    public var numericLabel: String? { runSketch == nil && component == .run && runMode == .straight && clicks.count == 1 ? "Length" : nil }

    public func numericInput(_ text: String) -> Bool {
        guard numericLabel != nil, let s = clicks.first, let c = current, let len = ctx.parse(text), len > 0.05 else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitY
        placeStraight(to: s + d * len)
        return true
    }
}

/// Access to run geometry the tool needs (leg counts when a winder run is reversed).
enum StairRunGeometryAccess {
    /// Leg treads of a winder run walked from its top.
    static func reversedLegs(_ r: StairRun, treads: Int) -> [Int] {
        let k = r.winders, corners = r.corners
        let straight = max(0, treads - corners * k)
        var legs = Array((r.legTreads ?? []).prefix(corners))
        while legs.count < corners { legs.append(corners == 1 ? straight / 2 : 0) }
        let last = max(0, straight - legs.reduce(0, +))
        let all = legs + [last]
        return Array(all.reversed().prefix(corners))
    }
}
