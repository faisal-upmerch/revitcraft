import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F34: Structure ▸ Reinforcement tools and Annotate ▸ Symbol / Multi-Rebar, following RevitCraft's canvas_tools.rs
// (ToolKind::RebarSet, AreaReinfHost, PathReinfHost, FabricAreaHost, FabricSheet, RebarCoupler, HostSymbol).

/// Finding reinforcement hosts and annotated elements under the pointer.
@MainActor
enum F34Pick {
    /// The floor of the view's level under a plan point, or the wall under the pointer in a section or elevation.
    static func host(_ i: ToolInput, _ ctx: ToolContext) -> Element? {
        if ctx.isPlan {
            return Reinforcement.floor(at: i.point, level: ctx.levelID, ctx.model)
                ?? ([i.hit].compactMap { $0 } + i.hitCandidates).compactMap { ctx.model[$0] }.first { $0.category == .floors && $0.slab != nil }
        }
        return ([i.hit].compactMap { $0 } + i.hitCandidates).compactMap { ctx.model[$0] }.first { $0.wall != nil && Reinforcement.canHost($0) }
    }

    /// The first element under the pointer that `fits`: canvas hits first, then reinforcement boundaries containing the
    /// point and bars, paths and beams near it.
    static func element(_ i: ToolInput, _ ctx: ToolContext, fits: (Element) -> Bool) -> Element? {
        let m = ctx.model
        if let e = ([i.hit].compactMap { $0 } + i.hitCandidates).compactMap({ m[$0] }).first(where: fits) { return e }
        let p = i.point, tol = ctx.pixel * 8
        func onLevel(_ e: Element) -> Bool {
            let host = e.rebarCoupler != nil ? m[m[e.hostID]?.hostID] : m[e.hostID]
            return e.beamSystem != nil || e.beam != nil ? e.levelID == ctx.levelID : host?.levelID == ctx.levelID && host?.slab != nil
        }
        let cats: [Category] = [.structuralRebar, .pathReinforcement, .fabricReinforcement, .areaReinforcement, .fabricAreas, .beamSystems, .structuralFraming]
        for c in cats {
            for e in m.elements(c).reversed() where fits(e) && onLevel(e) {
                switch e.data {
                case .rebar:
                    if Reinforcement.rebarBars(e, m).contains(where: { Segment2($0.start.xy, $0.end.xy).distance(to: p) <= tol }) { return e }
                case .pathReinforcement(let r):
                    if zip(r.path, r.path.dropFirst()).contains(where: { Segment2($0, $1).distance(to: p) <= tol }) { return e }
                    if Reinforcement.pathRegions(e, m).contains(where: { $0.contains(p) }) { return e }
                case .fabricSheet:
                    if Polygon2(Reinforcement.sheetOutline(e, m)).contains(p) { return e }
                case .areaReinforcement(let a):
                    if Polygon2(a.boundary).contains(p) { return e }
                case .fabricArea(let a):
                    if Polygon2(a.boundary).contains(p) { return e }
                case .beamSystem(let b):
                    if Polygon2(b.boundary).contains(p) { return e }
                case .beam(let b):
                    if b.curve.distance(to: p) <= max(tol, BeamGeometry.section(e, m).width / 2) { return e }
                default: break
                }
            }
        }
        return nil
    }
}

// MARK: - Rebar

/// Structure ▸ Rebar: a set of straight bars in a floor or slab, at its bottom cover. Click the start (inside the
/// floor) and the end; Quantity and Spacing lay the copies out to the left of the bar.
@MainActor
public final class RebarTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.rebar
    public let title = "Rebar"
    var start: Vec2?
    var current: Vec2?
    public var quantity = 1
    public var spacing: Double

    public override init(ctx: ToolContext) {
        spacing = ctx.units.system == .imperial ? 0.3048 : 0.3
        super.init(ctx: ctx)
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Rebar is placed in plan views." }
        return start == nil ? "Click inside a floor or slab to start the bar." : "Click to end the bar."
    }
    public var numericLabel: String? { start != nil ? "Length" : nil }
    public var snapFrom: Vec2? { start }
    public var options: [ToolOption] {
        [ToolOption(id: "layout", label: "Layout", kind: .choice(["Fixed Number"]), value: .text("Fixed Number")),
         ToolOption(id: "quantity", label: "Quantity", kind: .integer, value: .int(quantity)),
         ToolOption(id: "spacing", label: "Spacing", kind: .length, value: .double(spacing))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "quantity": if let n = value.intValue ?? value.doubleValue.map({ Int($0.rounded()) }) { quantity = min(200, max(1, n)) }
        case "spacing": if let d = value.doubleValue { spacing = max(0.025, d) }
        default: break
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let a = start else {
            if ctx.isPlan, Reinforcement.floor(at: i.point, level: ctx.levelID, ctx.model) == nil { preview.cursor = .notAllowed }
            return
        }
        // The set: the bar and its copies to the left.
        let n = (i.point - a).normalized.perpendicular
        for k in 0..<max(1, quantity) {
            let off = n * (spacing * Double(k))
            preview.primitives.append(ctx.line(a + off, i.point + off, heavy: true))
        }
        preview.tempDims = [tempDim(a, i.point), angleDim(a, i.point)]
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to place rebar."); return }
        guard let a = start else {
            if Reinforcement.floor(at: i.point, level: ctx.levelID, ctx.model) != nil { start = i.point } else { message("Start the bar inside a floor or slab.") }
            return
        }
        commit(a, i.point)
    }

    public func numericInput(_ text: String) -> Bool {
        guard let s = start, let c = current, let len = ctx.parse(text), len > Tolerance.shortCurve else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        commit(s, s + d * len)
        return true
    }

    func commit(_ a: Vec2, _ b: Vec2) {
        start = nil
        preview = ToolPreview()
        guard a.distance(to: b) >= 0.05 else { message("The bar is too short."); return }
        guard let host = Reinforcement.floor(at: a, level: ctx.levelID, ctx.model) else { message("Start the bar inside a floor or slab."); return }
        let (count, spacing) = (quantity, spacing)
        let chosen = ctx.currentTypes[.structuralRebar].flatMap { ctx.model[$0]?.typeData?.instanceCategory == .structuralRebar ? $0 : nil }
        var created: ElementID?
        ctx.session.perform("Create Rebar") { tx in
            Reinforcement.ensureBarTypes(in: tx)
            let bt = chosen ?? Reinforcement.defaultBarType(tx.model)
            created = tx.create(.structuralRebar, data: .rebar(RebarData(start: a, end: b, count: count, spacing: spacing)), typeID: bt, levelID: host.levelID, hostID: host.id)
        }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
    }

    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Area, Path and Fabric Area

/// Structure ▸ Area, Path and Fabric Area: pick the floor or slab (in a plan) or the wall (in a section or elevation
/// that looks at it), then sketch the boundary or path there. Finish creates the reinforcement.
@MainActor
public final class ReinforcementSketchTool: InteractiveTool {
    public enum Kind: Sendable { case area, path, fabricArea }
    public let kind: Kind
    let ctx: ToolContext
    /// The sketch, once the host is picked.
    public private(set) var sketch: SketchTool?
    var ownPreview = ToolPreview()

    public init(ctx: ToolContext, kind: Kind, host: ElementID? = nil) {
        self.ctx = ctx
        self.kind = kind
        // A selected floor (in a plan) or wall (in a view looking straight at it) is the host.
        if let host, let e = ctx.model[host], Reinforcement.canHost(e),
           e.slab != nil ? ctx.isPlan : (ctx.viewData.map { Reinforcement.viewFacesWall($0, e.id, ctx.model) } ?? false) { begin(e) }
    }

    public var commandID: CommandID {
        switch kind { case .area: .areaReinforcement; case .path: .pathReinforcement; case .fabricArea: .fabricArea }
    }
    public var title: String { sketch?.title ?? (kind == .area ? "Area Reinforcement" : kind == .path ? "Path Reinforcement" : "Fabric Area") }
    public var prompt: String {
        if let s = sketch { return s.prompt }
        switch kind {
        case .area: return "Select a floor or slab to reinforce."
        case .path: return "Pick Structural Floor or Wall for Path Reinforcement"
        case .fabricArea: return "Pick Structural Floor or Wall for Fabric Area Reinforcement"
        }
    }
    public var preview: ToolPreview { sketch?.preview ?? ownPreview }
    public var numericLabel: String? { sketch?.numericLabel }
    public var options: [ToolOption] { sketch?.options ?? [] }
    public var isSketchMode: Bool { sketch != nil }
    public var snapFrom: Vec2? { sketch?.snapFrom }
    public func setOption(_ id: String, _ value: ParamValue) { sketch?.setOption(id, value) }

    func target(_ host: ElementID) -> F34SketchTarget {
        switch kind {
        case .area: .areaReinforcement(host: host)
        case .path: .pathReinforcement(host: host)
        case .fabricArea: .fabricArea(host: host)
        }
    }

    func begin(_ host: Element) {
        let s = SketchTool(ctx: ctx, target: .f34(target(host.id)), commandID: commandID)
        s.drawMode = .line
        sketch = s
        ctx.session.selection.select([])
    }

    public func pointerMoved(_ i: ToolInput) {
        if let s = sketch { s.pointerMoved(i); return }
        ownPreview = ToolPreview()
        if let h = F34Pick.host(i, ctx) { ownPreview.highlight = [h.id]; ownPreview.cursor = .pick }
    }

    public func pointerDown(_ i: ToolInput) {
        if let s = sketch { s.pointerDown(i); return }
        guard let h = F34Pick.host(i, ctx) else {
            ctx.showMessage?(ctx.isPlan || ctx.isVertical ? prompt : "Open a plan, section or elevation to place reinforcement.")
            return
        }
        if h.wall != nil, let v = ctx.viewData, !Reinforcement.viewFacesWall(v, h.id, ctx.model) {
            ctx.showMessage?("Sketch wall reinforcement in a section or elevation that looks straight at the wall.")
            return
        }
        begin(h)
    }

    public func pointerDragged(_ i: ToolInput) { sketch?.pointerDragged(i) }
    public func pointerUp(_ i: ToolInput) { sketch?.pointerUp(i) }
    public func numericInput(_ text: String) -> Bool { sketch?.numericInput(text) ?? false }
    public func escape() -> EscapeResult { sketch?.escape() ?? .exitTool }
    public func finish() -> Bool { sketch?.finish() ?? false }
    public func cancelSketch() {
        if let s = sketch { s.cancelSketch() } else { ctx.toolFinished?() }
    }
    public func spaceBar() { sketch?.spaceBar() }
}

// MARK: - Fabric Sheet

/// Structure ▸ Fabric Sheet: one click within a floor (in a plan) or on a wall (in a section or elevation) places a
/// sheet centred there.
@MainActor
public final class FabricSheetTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.fabricSheet
    public let title = "Fabric Sheet"
    public var prompt: String { "Click within a structural Wall or Floor to place Fabric Sheet." }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        let type = ctx.model.types(for: .fabricReinforcement).first?.id
        let size = Reinforcement.sheetSize(ctx.model, type)
        let r = Reinforcement.sheetRect(i.point, direction: .unitX, length: size.length, width: size.width)
        preview.primitives = [.polyline(r, closed: true, ctx.previewStroke), ctx.line(r[0], r[2])]
    }

    public func pointerDown(_ i: ToolInput) {
        guard let host = F34Pick.host(i, ctx) else { message(prompt); return }
        var at = i.point
        if host.wall != nil {
            guard let v = ctx.viewData, let q = Reinforcement.wallFacePoint(i.point, view: v, host: host.id, ctx.model) else {
                message("Place wall fabric in a section or elevation that looks straight at the wall."); return
            }
            at = q
        }
        var created: ElementID?
        ctx.session.perform("Place Fabric Sheet") { tx in
            let type = Reinforcement.ensureFabricType(in: tx)
            created = tx.create(.fabricReinforcement, data: .fabricSheet(FabricSheetData(center: at)), typeID: type, levelID: host.levelID, hostID: host.id)
        }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
    }

    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Rebar Coupler

/// Structure ▸ Rebar Coupler: Place on Bar End puts couplers on the end of the picked set nearest the click; Place
/// between Two Bars joins two sets that meet end to end.
@MainActor
public final class RebarCouplerTool: BaseTool, InteractiveTool {
    public static let placements = ["Place on Bar End", "Place between Two Bars"]
    public let commandID = CommandID.rebarCoupler
    public let title = "Rebar Coupler"
    public var between: Bool
    var first: (id: ElementID, click: Vec2)?

    public init(ctx: ToolContext, between: Bool = false) {
        self.between = between
        super.init(ctx: ctx)
    }

    public var prompt: String {
        between && first != nil ? "Select the second rebar set; its bars must meet the first set's end to end." : "Select a valid rebar set to place the coupler."
    }
    public var options: [ToolOption] {
        [ToolOption(id: "placement", label: "Placement", kind: .choice(Self.placements), value: .text(Self.placements[between ? 1 : 0]))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "placement" { between = value.textValue == Self.placements[1]; first = nil }
    }

    func rebar(_ i: ToolInput) -> Element? { F34Pick.element(i, ctx) { $0.rebar != nil } }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if let r = rebar(i) { preview.highlight = [r.id]; preview.cursor = .pick }
        if let f = first { preview.highlight.insert(f.id) }
    }

    public func pointerDown(_ i: ToolInput) {
        guard let rb = rebar(i), let r = rb.rebar else { message("Select a valid rebar set to place the coupler."); return }
        // The end of the set nearest the click.
        let atEnd = i.point.distance(to: r.end) < i.point.distance(to: r.start)
        if !between {
            place(rb.id, atEnd: atEnd, other: nil)
        } else if let f = first, let r1 = ctx.model[f.id]?.rebar {
            first = nil
            let firstEnd = f.click.distance(to: r1.end) < f.click.distance(to: r1.start)
            let q = firstEnd ? r1.end : r1.start
            guard rb.id != f.id, min(q.distance(to: r.start), q.distance(to: r.end)) <= 0.1 else { message("The bars must meet end to end to be coupled."); return }
            place(f.id, atEnd: firstEnd, other: rb.id)
        } else {
            first = (rb.id, i.point)
        }
    }

    func place(_ rebar: ElementID, atEnd: Bool, other: ElementID?) {
        guard !ctx.model.hosted(by: rebar).contains(where: { $0.rebarCoupler?.atEnd == atEnd }) else { message("This end of the bars already has a coupler."); return }
        let level = ctx.model[rebar]?.levelID
        var created: ElementID?
        ctx.session.perform("Rebar Coupler") { tx in
            created = tx.create(.rebarCouplers, data: .rebarCoupler(RebarCouplerData(atEnd: atEnd, otherRebarID: other)), levelID: level, hostID: rebar)
        }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
    }

    public func escape() -> EscapeResult {
        if first != nil { first = nil; return .stayInTool }
        return .exitTool
    }
}

// MARK: - Symbols and Multi-Rebar

/// Annotate ▸ Symbol (Beam, Area, Path, Rebar, Fabric) and Tag ▸ Multi-Rebar. A symbol is placed by clicking its
/// element where it should go; a Multi-Rebar annotation picks the rebar set, then a click places the dimension line.
@MainActor
public final class StructuralSymbolTool: BaseTool, InteractiveTool {
    public let kind: StructuralSymbolKind
    public let commandID: CommandID
    var picked: ElementID?

    public init(ctx: ToolContext, kind: StructuralSymbolKind, commandID: CommandID) {
        self.kind = kind
        self.commandID = commandID
        super.init(ctx: ctx)
    }

    var isMultiRebar: Bool { kind == .multiRebarAligned || kind == .multiRebarLinear }
    public var title: String { kind.rawValue }
    public var prompt: String {
        guard ctx.isPlan else { return "\(title) is placed in plan views." }
        switch kind {
        case .beamSystem: return "Select a beam to place the beam system symbol."
        case .areaReinforcement: return "Select an area reinforcement to place its symbol."
        case .pathReinforcement: return "Select a path reinforcement to place its symbol."
        case .rebar: return "Select a rebar set to place its symbol."
        case .fabric: return "Select a fabric area or sheet to place its symbol."
        case .multiRebarAligned, .multiRebarLinear: return picked == nil ? "Select a rebar set to annotate, then click to place the dimension." : "Click to place the dimension."
        }
    }

    func target(_ i: ToolInput) -> Element? { F34Pick.element(i, ctx) { [kind] in kind.fits($0) } }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard ctx.isPlan else { preview.cursor = .notAllowed; return }
        let host = picked.flatMap { ctx.model[$0] } ?? target(i)
        guard let host else { return }
        if picked == nil { preview.highlight = [host.id]; preview.cursor = .pick }
        // The symbol as it would be placed.
        let probe = Element(id: ElementID(UInt64.max - 11), category: .genericAnnotations, data: .structuralSymbol(StructuralSymbolData(kind: kind, position: i.point)),
                            hostID: host.id, ownerViewID: ctx.viewID)
        if let item = AnnotationRenderer.item(probe, GraphicOverride(), model: ctx.model, scale: ctx.scale, builder: nil) {
            preview.primitives = AnnotationPreview.tinted(item.primitives, ctx.previewStroke.color)
        }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to place \(title.lowercased())s."); return }
        if isMultiRebar, picked == nil {
            guard let r = target(i) else { message(prompt); return }
            picked = r.id
            return
        }
        guard let host = picked.flatMap({ ctx.model[$0] }) ?? target(i) else { message("Select an element this symbol can annotate."); return }
        picked = nil
        let (view, kind) = (ctx.viewID, kind)
        var created: ElementID?
        ctx.session.perform(isMultiRebar ? "Multi-Rebar Annotation" : "Place Symbol") { tx in
            created = tx.create(.genericAnnotations, data: .structuralSymbol(StructuralSymbolData(kind: kind, position: i.point)), hostID: host.id, ownerViewID: view)
        }
        if let e = ctx.session.lastError { message(e.message) } else if let created { ctx.session.selection.select([created]) }
    }

    public func escape() -> EscapeResult {
        if picked != nil { picked = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}
