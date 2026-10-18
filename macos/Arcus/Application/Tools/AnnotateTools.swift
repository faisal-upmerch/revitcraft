import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// W2-ANNOT: Annotate tab tools — text notes with leaders, special tags (material, keynotes, tread numbers, view
// references, span direction, stair paths, scale bars), repeating details, legend components and detail groups.

/// Preview helpers for annotation tools.
public enum AnnotationPreview {
    /// The primitives in the preview colour (strokes, fills and texts), masks kept.
    public static func tinted(_ prims: [GPrimitive], _ color: RGBColor) -> [GPrimitive] {
        prims.map { p in
            switch p {
            case .polyline(let pts, let closed, var st): st.color = color; return .polyline(pts, closed: closed, st)
            case .arc(let a, var st): st.color = color; return .arc(a, st)
            case .fill(let polys, var f):
                if f == GFill.mask { return p }
                f.color = color
                if f.background != nil { f.background = nil; f.transparency = max(f.transparency, 0.6) }
                return .fill(polys, f)
            case .text(var t): t.color = color; t.opaque = false; return .text(t)
            }
        }
    }
}

// MARK: - Text notes

/// Text: click where the text goes (or drag its width to wrap it), type, and click away. With a leader the first
/// click is the arrow point (and, for two segments, the second the elbow). The text type comes from the type selector.
@MainActor
public final class TextTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.textNote
    public let title = "Text"
    public enum LeaderMode: String, CaseIterable, Sendable {
        case none = "No Leader", one = "One Segment", two = "Two Segments", arc = "Curved"
    }
    public var leaderMode: LeaderMode = .none
    /// Kept for older callers: true = one-segment leader.
    public var leader: Bool {
        get { leaderMode != .none }
        set { leaderMode = newValue ? .one : .none }
    }
    public var alignment: TextAlignment = .left
    var leaderPoint: Vec2?
    var elbowPoint: Vec2?
    var dragStart: Vec2?
    var dragCurrent: Vec2?
    /// Set while the text is being typed (the tool waits for it).
    var pending = false

    public var prompt: String {
        switch leaderMode {
        case .none: return "Click where the text starts, or drag to set its width."
        case .two where leaderPoint != nil && elbowPoint == nil: return "Click the leader's elbow."
        default: return leaderPoint == nil ? "Click the leader arrow point." : "Click where the text starts."
        }
    }
    public var options: [ToolOption] {
        [ToolOption(id: "leader", label: "Leader", kind: .choice(LeaderMode.allCases.map(\.rawValue)), value: .text(leaderMode.rawValue)),
         ToolOption(id: "align", label: "Align", kind: .choice(TextAlignment.allCases.map(\.rawValue)), value: .text(alignment.rawValue))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "leader":
            if let b = value.boolValue { leader = b } else if let m = LeaderMode(rawValue: value.textValue ?? "") { leaderMode = m }
            leaderPoint = nil; elbowPoint = nil
        case "align": if let a = TextAlignment(rawValue: value.textValue ?? "") { alignment = a }
        default: break
        }
    }

    /// The text type: the type selector's choice, else the smallest plain text type.
    var textType: ElementID? {
        if let t = ctx.currentTypes[.textNotes], ctx.model[t]?.typeData != nil { return t }
        let types = ctx.model.types(for: .textNotes)
        return types.min { a, b in
            let sa = TextNoteStyle.of(type: a.typeData), sb = TextNoteStyle.of(type: b.typeData)
            return (sa.bold ? 1 : 0, sa.size) < (sb.bold ? 1 : 0, sb.size)
        }?.id
    }
    var style: TextNoteStyle { TextNoteStyle.of(type: ctx.model[textType]?.typeData) }
    var paperScale: Double { ctx.isSheet ? 1 : Double(ctx.scale) }

    func note(at p: Vec2, text: String, width: Double) -> TextNoteData {
        var n = TextNoteData(position: p, text: text, width: width)
        n.alignment = alignment
        if let lp = leaderPoint {
            n.leaders = [lp]
            if let e = elbowPoint { n.leaderElbows = [e] }
            if leaderMode == .arc { n.leaderShape = .arc }
        }
        return n
    }

    func wrapWidth(to p: Vec2) -> Double {
        guard let s = dragStart else { return 0 }
        let w = abs(p.x - s.x) / paperScale
        return w > style.size * 4 ? w : 0
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        preview.cursor = .crosshair
        guard !pending else { return }
        var prims: [GPrimitive] = []
        if let lp = leaderPoint, leaderMode == .two, elbowPoint == nil {
            prims.append(ctx.line(lp, i.point))
        } else if leaderPoint != nil || leaderMode == .none {
            let width = dragStart != nil ? wrapWidth(to: i.point) : 0
            let anchor = dragStart.map { Vec2(min($0.x, i.point.x), max($0.y, i.point.y)) } ?? i.point
            let n = note(at: anchor, text: "Text", width: width)
            let probe = Element(id: ElementID(UInt64.max - 9), category: .textNotes, data: .textNote(n), typeID: textType, ownerViewID: ctx.viewID)
            if let p = AnnotationRenderer.previewItem(probe, model: ctx.model, scale: ctx.isSheet ? 1 : ctx.scale) {
                prims += AnnotationPreview.tinted(p, ctx.previewStroke.color)
            }
            // The text box being dragged or placed.
            let box = TextNoteGeometry.box(n, style, scale: paperScale)
            prims.append(.polyline(box.corners, closed: true, GStroke(weight: 1, color: ctx.previewStroke.color, pattern: .dash)))
        }
        preview.primitives = prims
    }

    public func pointerDown(_ i: ToolInput) {
        guard !pending else { return }
        if leaderMode != .none && leaderPoint == nil { leaderPoint = i.point; return }
        if leaderMode == .two && elbowPoint == nil { elbowPoint = i.point; return }
        dragStart = i.point
        dragCurrent = i.point
    }

    public func pointerDragged(_ i: ToolInput) { if dragStart != nil { dragCurrent = i.point } }

    public func pointerUp(_ i: ToolInput) {
        guard let s = dragStart else { return }
        let width = wrapWidth(to: i.point)
        let pos = width > 0 ? Vec2(min(s.x, i.point.x), max(s.y, i.point.y)) : s
        dragStart = nil; dragCurrent = nil
        begin(at: pos, width: width)
    }

    /// Asks for the text and creates the note (in place when the host can edit on the canvas).
    public func begin(at pos: Vec2, width: Double = 0) {
        let template = note(at: pos, text: "", width: width)
        leaderPoint = nil; elbowPoint = nil
        let view = ctx.viewID, type = textType
        pending = true
        preview = ToolPreview()
        ctx.askText("Text", at: pos) { [weak self] text in
            guard let self else { return }
            self.pending = false
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            var n = template
            n.text = text
            self.ctx.session.perform("Create Text") { tx in tx.create(.textNotes, data: .textNote(n), typeID: type, ownerViewID: view) }
            if let err = self.ctx.session.lastError { self.message(err.message) }
        }
    }

    public func escape() -> EscapeResult {
        if elbowPoint != nil { elbowPoint = nil; return .stayInTool }
        if leaderPoint != nil || dragStart != nil { leaderPoint = nil; dragStart = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

/// Adding and removing text note leaders.
public enum TextLeaders {
    /// Adds a straight leader to a note, pointing away from the side that already has leaders (left first).
    public static func add(to id: ElementID, in tx: TransactionContext) {
        guard let e = tx.model[id], let n = e.textNote else { return }
        let style = TextNoteStyle.resolve(e, tx.model)
        let s = GripService.paperScale(of: e, tx.model)
        let box = TextNoteGeometry.box(n, style, scale: s)
        let dir = box.u.lengthSquared > 0 ? box.u.normalized : .unitX
        let down = box.v.lengthSquared > 0 ? box.v.normalized : Vec2(0, -1)
        let leftCount = n.leaders.filter { ($0 - box.center).dot(dir) <= 0 }.count
        let rightCount = n.leaders.count - leftCount
        let toRight = leftCount > rightCount
        let reach = 0.012 * s
        let base = toRight ? box.point(1, 0) : box.point(0, 0)
        let end = base + dir * (toRight ? reach : -reach) + down * (reach * (0.6 + 0.5 * Double(n.leaders.count / 2)))
        tx.update(id) { el in
            guard var t = el.textNote else { return }
            t.leaders.append(end)
            if var elbows = t.leaderElbows {
                while elbows.count < t.leaders.count { elbows.append(nil) }
                t.leaderElbows = elbows
            }
            el.textNote = t
        }
    }

    /// Removes the last leader of a note.
    public static func removeLast(from id: ElementID, in tx: TransactionContext) {
        tx.update(id) { el in
            guard var t = el.textNote, !t.leaders.isEmpty else { return }
            t.leaders.removeLast()
            if var elbows = t.leaderElbows {
                if elbows.count > t.leaders.count { elbows.removeLast(elbows.count - t.leaders.count) }
                t.leaderElbows = elbows.contains { $0 != nil } ? elbows : nil
            }
            el.textNote = t
        }
    }
}

// MARK: - Special tags

/// Material tags, keynotes, tread numbers, view references, span direction symbols, stair paths and scale bars.
@MainActor
public final class SpecialTagTool: BaseTool, InteractiveTool {
    public let kind: TagKind
    public var commandID: CommandID {
        switch kind {
        case .material: .materialTag
        case .keynoteElement: .keynoteElement
        case .keynoteMaterial: .keynoteMaterial
        case .keynoteUser: .keynoteUser
        case .treadNumber: .treadNumber
        case .viewReference: .viewReference
        case .spanDirection: .spanDirection
        case .stairPath: .stairPath
        case .scaleBar: .scaleBar
        }
    }
    public var title: String { kind.rawValue }
    /// Picked element and point (for tags placed with a second click).
    var picked: (id: ElementID, point: Vec2, material: ElementID?)?
    public var leader = true
    public var keynoteDisplay: KeynoteDisplay = .key
    public var userKey: String = KeynoteTable.standard.first { $0.parent != nil }?.key ?? "A1.01"
    public var targetViewID: ElementID?

    public init(ctx: ToolContext, kind: TagKind) {
        self.kind = kind
        super.init(ctx: ctx)
        if kind == .viewReference { targetViewID = referenceViews.first?.id }
        if kind.isKeynote { keynoteDisplay = Keynoting.display(ctx.model); userKey = Keynoting.pickable(ctx.model).first?.key ?? userKey } // F12
    }

    /// Categories each kind picks.
    var pickable: Set<Category> {
        switch kind {
        case .treadNumber, .stairPath: [.stairs]
        case .spanDirection: [.floors]
        case .material, .keynoteMaterial: Set(Category.taggable).subtracting([.rooms, .areas])
        case .keynoteElement, .keynoteUser: Set(Category.taggable).subtracting([.rooms, .areas]).union([.detailComponents])
        case .viewReference, .scaleBar: []
        }
    }
    var needsPick: Bool { !pickable.isEmpty }
    /// Kinds placed with one click on the element (the click is also where they draw).
    var oneClick: Bool { kind == .treadNumber || kind == .stairPath || kind == .spanDirection || !needsPick }
    var planOnly: Bool { kind == .treadNumber || kind == .stairPath || kind == .spanDirection }

    /// Views a view reference can point to: other plans, sections, elevations, details and drafting views.
    var referenceViews: [Element] {
        ctx.model.views.filter { $0.id != ctx.viewID && ($0.view?.kind.isPlan == true || $0.view?.kind.isVerticalCut == true || $0.view?.kind == .drafting) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public var prompt: String {
        if planOnly && !ctx.isPlan { return "\(title) is placed in plan views." }
        switch kind {
        case .scaleBar: return "Click to place the scale bar (its left end)."
        case .viewReference: return targetViewID == nil ? "Create another view first." : "Click to place the reference to “\(ctx.model[targetViewID]?.name ?? "")”."
        case .treadNumber: return "Click a stair run on the side where the numbers go."
        case .stairPath: return "Click a stair."
        case .spanDirection: return "Click a floor where the symbol goes."
        default: return picked == nil ? "Click an element\(kind == .material || kind == .keynoteMaterial ? " (or wall layer)" : "")." : "Click to place the \(kind.isKeynote ? "keynote" : "tag")."
        }
    }

    public var options: [ToolOption] {
        var o: [ToolOption] = []
        if kind.isKeynote { o.append(ToolOption(id: "display", label: "Display", kind: .choice(KeynoteDisplay.allCases.map(\.rawValue)), value: .text(keynoteDisplay.rawValue))) }
        if kind == .keynoteUser {
            let table = Keynoting.pickable(ctx.model) // F12: the project's keynote table
            let keys = table.map { "\($0.key) \($0.text)" }
            let current = table.first { $0.key == userKey }.map { "\($0.key) \($0.text)" } ?? userKey
            o.append(ToolOption(id: "key", label: "Key", kind: .choice(keys), value: .text(current)))
        }
        if [.material, .keynoteElement, .keynoteMaterial, .keynoteUser].contains(kind) {
            o.append(ToolOption(id: "leader", label: "Leader", kind: .bool, value: .bool(leader)))
        }
        if kind == .viewReference {
            o.append(ToolOption(id: "view", label: "Target View", kind: .choice(referenceViews.map(\.name)), value: .text(ctx.model[targetViewID]?.name ?? "")))
        }
        return o
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        switch id {
        case "display": if let d = KeynoteDisplay(rawValue: value.textValue ?? "") { keynoteDisplay = d }
        case "key": if let t = value.textValue, let k = Keynoting.pickable(ctx.model).first(where: { "\($0.key) \($0.text)" == t })?.key ?? t.split(separator: " ").first.map(String.init) { userKey = k } // F12
        case "leader": leader = value.boolValue ?? true
        case "view": targetViewID = referenceViews.first { $0.name == value.textValue }?.id
        default: break
        }
    }

    func data(target: ElementID, head: Vec2, leaderEnd: Vec2?, material: ElementID?) -> TagData {
        var t = TagData(taggedID: target, head: head, hasLeader: leaderEnd != nil)
        t.kind = kind
        t.leaderEnd = leaderEnd
        switch kind {
        case .material, .keynoteMaterial: t.materialID = material
        case .keynoteUser: t.keynote = userKey
        default: break
        }
        if kind.isKeynote { t.keynoteDisplay = keynoteDisplay }
        return t
    }

    var category: Category { [.spanDirection, .stairPath, .scaleBar, .viewReference].contains(kind) ? .genericAnnotations : .tags }

    /// The tag a click at `p` would create (nil when nothing suitable is under the pointer).
    func proposal(_ i: ToolInput) -> TagData? {
        if let pk = picked {
            return data(target: pk.id, head: i.point, leaderEnd: leader ? pk.point : nil, material: pk.material)
        }
        switch kind {
        case .scaleBar: return data(target: ctx.viewID, head: i.point, leaderEnd: nil, material: nil)
        case .viewReference: return targetViewID.map { data(target: $0, head: i.point, leaderEnd: nil, material: nil) }
        default:
            guard let e = hit(i, pickable) else { return nil }
            if oneClick { return data(target: e.id, head: i.point, leaderEnd: nil, material: nil) }
            return nil
        }
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        if planOnly && !ctx.isPlan { preview.cursor = .notAllowed; return }
        if picked == nil, needsPick, let e = hit(i, pickable) { preview.highlight = [e.id]; preview.cursor = .pick }
        guard let t = proposal(i) else { return }
        let probe = Element(id: ElementID(UInt64.max - 10), category: category, data: .tag(t), ownerViewID: ctx.viewID)
        if let prims = AnnotationRenderer.previewItem(probe, model: ctx.model, scale: ctx.isSheet ? 1 : ctx.scale) {
            preview.primitives = AnnotationPreview.tinted(prims, ctx.previewStroke.color)
        }
    }

    public func pointerDown(_ i: ToolInput) {
        if planOnly && !ctx.isPlan { message("\(title) is placed in plan views."); return }
        if picked == nil, needsPick, !oneClick {
            guard let e = hit(i, pickable) else { message("Click an element."); return }
            let material = (kind == .material || kind == .keynoteMaterial) ? MaterialPick.material(at: i.rawPoint, of: e, ctx.model, view: ctx.view) : nil
            if (kind == .material || kind == .keynoteMaterial) && material == nil { message("That element has no material to tag."); return }
            if kind == .keynoteElement, (ctx.model.typeParam(e, ParameterID("type.keynote"))?.textValue ?? "").isEmpty {
                message("The type has no Keynote yet; the keynote shows “?” until one is set in Type Properties.")
            }
            picked = (e.id, i.rawPoint, material)
            if !leader { place(i) }
            return
        }
        place(i)
    }

    func place(_ i: ToolInput) {
        guard let t = proposal(i) ?? picked.map({ data(target: $0.id, head: $0.point, leaderEnd: nil, material: $0.material) }) else {
            message(kind == .viewReference ? "Create another view to reference first." : "Click a suitable element."); return
        }
        let view = ctx.viewID, cat = category
        ctx.session.perform("Place \(title)") { tx in tx.create(cat, data: .tag(t), ownerViewID: view) }
        if let err = ctx.session.lastError { message(err.message) }
        picked = nil
        preview = ToolPreview()
    }

    public func escape() -> EscapeResult {
        if picked != nil { picked = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Repeating detail components

/// Draws the path of a repeating detail: the current detail component repeats from the first click to the second.
@MainActor
public final class RepeatingDetailTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.repeatingDetailComponent
    public let title = "Repeating Detail Component"
    var start: Vec2?
    /// Spacing (view units); 0 = the component's own length.
    public var spacing = 0.0
    public var prompt: String { start == nil ? "Click the start of the repeating detail." : "Click the end, or type a length." }
    public var snapFrom: Vec2? { start }
    public var numericLabel: String? { start != nil ? "Length" : nil }
    public var options: [ToolOption] { [ToolOption(id: "spacing", label: "Spacing", kind: .length, value: .double(spacing))] }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "spacing", let d = value.doubleValue, d >= 0 { spacing = d } }
    var current: Vec2?

    func probe(_ a: Vec2, _ b: Vec2) -> Element? {
        guard let t = ctx.type(for: .detailComponents) else { return nil }
        var d = DetailComponentData(location: a)
        d.repeatEnd = b
        d.repeatSpacing = spacing > Tolerance.length ? spacing : nil
        return Element(id: ElementID(UInt64.max - 11), category: .detailComponents, data: .detailComponent(d), typeID: t, ownerViewID: ctx.viewID)
    }

    public func pointerMoved(_ i: ToolInput) {
        current = i.point
        preview = ToolPreview()
        guard let s = start else { return }
        preview.primitives = [ctx.line(s, i.point)]
        if let e = probe(s, i.point), let prims = AnnotationRenderer.previewItem(e, model: ctx.model, scale: ctx.scale) {
            preview.primitives += AnnotationPreview.tinted(prims, ctx.previewStroke.color)
        }
        preview.tempDims = [tempDim(s, i.point)]
    }
    public func pointerDown(_ i: ToolInput) {
        guard let s = start else { start = i.point; return }
        commit(s, i.point)
    }
    public func numericInput(_ text: String) -> Bool {
        guard let s = start, let c = current, let len = ctx.parse(text), len > Tolerance.length else { return false }
        let d = (c - s).lengthSquared > 0 ? (c - s).normalized : .unitX
        commit(s, s + d * len)
        return true
    }
    func commit(_ a: Vec2, _ b: Vec2) {
        guard a.distance(to: b) > Tolerance.length * 10 else { return }
        guard let e = probe(a, b), let t = e.typeID else { message("Load a detail component family first."); return }
        let view = ctx.viewID
        ctx.session.perform("Create Repeating Detail") { tx in tx.create(.detailComponents, data: e.data, typeID: t, ownerViewID: view) }
        if let err = ctx.session.lastError { message(err.message) }
        start = nil
        preview = ToolPreview()
    }
    public func escape() -> EscapeResult {
        if start != nil { start = nil; preview = ToolPreview(); return .stayInTool }
        return .exitTool
    }
}

// MARK: - Legend components

/// Places the symbol of a model type in a legend (or drafting) view.
@MainActor
public final class LegendComponentTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.legendComponent
    public let title = "Legend Component"
    public var typeID: ElementID?
    public var rotation = 0.0
    /// Length drawn for wall, floor and roof types (view units).
    public var hostLength = 1.0

    /// Types a legend can show: loadable family types and layered wall, floor, roof and ceiling types.
    public var candidates: [Element] {
        let cats: [Category] = [.doors, .windows, .furniture, .casework, .plumbingFixtures, .specialtyEquipment, .genericModels,
                                .columns, .structuralColumns, .walls, .floors, .roofs, .ceilings]
        return cats.flatMap { ctx.model.types(for: $0) }.filter { $0.typeData?.familyID != nil || $0.typeData?.assembly != nil }
    }
    func label(_ t: Element) -> String { "\(t.typeData?.familyName ?? ""): \(t.name)" }

    public override init(ctx: ToolContext) {
        super.init(ctx: ctx)
        typeID = candidates.first?.id
    }

    public var prompt: String {
        guard ctx.viewData?.kind == .legend || ctx.isDrafting else { return "Legend components are placed in legend views." }
        return "Click to place the legend component. Space rotates 90°."
    }
    public var options: [ToolOption] {
        [ToolOption(id: "type", label: "Family", kind: .choice(candidates.map(label)), value: .text(ctx.model[typeID].map(label) ?? "")),
         ToolOption(id: "length", label: "Host Length", kind: .length, value: .double(hostLength))]
    }
    public func setOption(_ id: String, _ value: ParamValue) {
        if id == "type" { typeID = candidates.first { label($0) == value.textValue }?.id }
        if id == "length", let d = value.doubleValue, d > 0 { hostLength = d }
    }
    public func spaceBar() { rotation = Angle.normalize(rotation + .pi / 2) }

    func data(at p: Vec2) -> DetailComponentData? {
        guard let t = typeID else { return nil }
        var d = DetailComponentData(location: p, rotation: rotation)
        d.legendTypeID = t
        if ctx.model[t]?.typeData?.assembly != nil { d.legendLength = hostLength }
        return d
    }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let d = data(at: i.point) else { preview.cursor = .notAllowed; return }
        let probe = Element(id: ElementID(UInt64.max - 12), category: .detailComponents, data: .detailComponent(d), ownerViewID: ctx.viewID)
        if let prims = AnnotationRenderer.previewItem(probe, model: ctx.model, scale: ctx.scale) {
            preview.primitives = AnnotationPreview.tinted(prims, ctx.previewStroke.color)
        }
    }
    public func pointerDown(_ i: ToolInput) {
        guard ctx.viewData?.kind == .legend || ctx.isDrafting else { message("Open a legend view (View ▸ Legend) to place legend components."); return }
        guard let d = data(at: i.point) else { message("Load a door, window or furniture family, or add a wall type, first."); return }
        let view = ctx.viewID
        ctx.session.perform("Place Legend Component") { tx in tx.create(.detailComponents, data: .detailComponent(d), ownerViewID: view) }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Detail groups

public enum DetailGroups {
    /// Elements that can go in a detail group: view-specific detail items and annotations of one view, not in a group.
    public static func members(_ ids: [ElementID], _ model: BIMModel) -> [ElementID] {
        let els = ids.compactMap { model[$0] }.filter { $0.ownerViewID != nil && $0.groupID == nil && $0.group == nil && ElementTransform.isTransformable($0) }
        guard let view = els.first?.ownerViewID else { return [] }
        return els.filter { $0.ownerViewID == view }.map(\.id)
    }

    /// Centre of the members' annotation graphics (the group origin).
    public static func center(_ ids: [ElementID], _ model: BIMModel, scale: Int) -> Vec2 {
        var r = Rect2.empty
        for id in ids {
            guard let e = model[id], let prims = AnnotationRenderer.previewItem(e, model: model, scale: scale) else { continue }
            r.include(GItem(elementID: id, category: e.category, layer: .annotation, primitives: prims).bounds)
        }
        return r.isEmpty ? ElementOperations.center(of: ids, model) : r.center
    }

    /// Creates a detail group type named `name` from `ids`. Returns the group element.
    @discardableResult
    public static func create(_ ids: [ElementID], name: String? = nil, scale: Int, in tx: TransactionContext) throws -> ElementID {
        let m = members(ids, tx.model)
        guard !m.isEmpty, let view = tx.model[m[0]]?.ownerViewID else { throw TransactionError("Select detail lines, regions, components or text of one view to group.") }
        let existing = Set((tx.model.elements(.detailGroups) + tx.model.elements(.modelGroups)).compactMap { $0.group?.groupTypeName })
        var n = existing.count + 1
        var groupName = name ?? "Detail Group \(n)"
        while name == nil && existing.contains(groupName) { n += 1; groupName = "Detail Group \(n)" }
        if existing.contains(groupName) { throw TransactionError("A group named “\(groupName)” already exists.") }
        let origin = center(m, tx.model, scale: scale)
        let gid = tx.create(.detailGroups, name: groupName, data: .group(GroupData(members: m, origin: origin, groupTypeName: groupName)), ownerViewID: view)
        for id in m { tx.update(id) { $0.groupID = gid } }
        return gid
    }

    /// Group type names with at least one instance.
    public static func typeNames(_ model: BIMModel) -> [String] {
        Array(Set(model.elements(.detailGroups).compactMap { $0.group?.groupTypeName })).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Places a copy of a detail group type in `view` with its origin at `p`. Returns the new group.
    @discardableResult
    public static func place(_ typeName: String, at p: Vec2, in view: ElementID, tx: TransactionContext) throws -> ElementID {
        guard let src = tx.model.elements(.detailGroups).first(where: { $0.group?.groupTypeName == typeName }), let gd = src.group else {
            throw TransactionError("There is no detail group named “\(typeName)”.")
        }
        let map = ElementOperations.copy(gd.members, by: .translation(p - gd.origin), in: tx, viewID: src.ownerViewID, targetView: view)
        let members = gd.members.compactMap { map[$0] }
        guard !members.isEmpty else { throw TransactionError("The group “\(typeName)” has nothing to place.") }
        let gid = tx.create(.detailGroups, name: typeName, data: .group(GroupData(members: members, origin: p, groupTypeName: typeName)), ownerViewID: view)
        for id in members { tx.update(id) { $0.groupID = gid; $0.ownerViewID = view } }
        return gid
    }
}

/// Places copies of a detail group.
@MainActor
public final class DetailGroupTool: BaseTool, InteractiveTool {
    public let commandID = CommandID.detailGroupPlace
    public let title = "Place Detail Group"
    public var groupName: String?
    public override init(ctx: ToolContext) {
        super.init(ctx: ctx)
        groupName = DetailGroups.typeNames(ctx.model).first
    }
    public var prompt: String { groupName == nil ? "Create a detail group first (select detail items, then Create Detail Group)." : "Click to place “\(groupName!)”." }
    public var options: [ToolOption] {
        [ToolOption(id: "group", label: "Group", kind: .choice(DetailGroups.typeNames(ctx.model)), value: .text(groupName ?? ""))]
    }
    public func setOption(_ id: String, _ value: ParamValue) { if id == "group" { groupName = value.textValue } }

    public func pointerMoved(_ i: ToolInput) {
        preview = ToolPreview()
        guard let name = groupName, let src = ctx.model.elements(.detailGroups).first(where: { $0.group?.groupTypeName == name }), let gd = src.group else { return }
        let delta = i.point - gd.origin
        var prims: [GPrimitive] = []
        for id in gd.members {
            guard var e = ctx.model[id] else { continue }
            _ = ElementTransform.apply(.translation(delta), to: &e)
            if let p = AnnotationRenderer.previewItem(e, model: ctx.model, scale: ctx.scale) { prims += p }
        }
        preview.primitives = AnnotationPreview.tinted(prims, ctx.previewStroke.color)
    }
    public func pointerDown(_ i: ToolInput) {
        guard let name = groupName else { message("Create a detail group first."); return }
        let view = ctx.viewID
        ctx.session.perform("Place Detail Group") { tx in try DetailGroups.place(name, at: i.point, in: view, tx: tx) }
        if let err = ctx.session.lastError { message(err.message) }
    }
    public func escape() -> EscapeResult { .exitTool }
}

// MARK: - Beam annotations

public enum BeamAnnotations {
    /// Tags every untagged beam among `visible` in `view` at its midpoint (a short leader-free tag above the beam).
    @discardableResult
    public static func run(view: ElementID, visible: Set<ElementID>, in tx: TransactionContext) -> Int {
        let scale = Double(tx.model[view]?.view?.scale ?? 100)
        var n = 0
        for id in visible.sorted() {
            guard let e = tx.model[id], e.category == .structuralFraming, let b = e.beam,
                  !tx.model.tags(of: id).contains(where: { $0.ownerViewID == view && $0.tag?.kind == nil }),
                  let tt = TagTool.defaultTagType(for: .structuralFraming, tx.model) else { continue }
            let seg = b.curve.asSegment
            let up = seg.map { $0.direction.perpendicular.y < 0 ? -$0.direction.perpendicular : $0.direction.perpendicular } ?? Vec2(0, 1)
            let head = b.curve.midpoint + up * (0.004 * scale)
            var td = TagData(taggedID: id, head: head)
            if let s = seg, abs(s.direction.y) > abs(s.direction.x) { td.orientation = .vertical }
            tx.create(.tags, data: .tag(td), typeID: tt, ownerViewID: view)
            n += 1
        }
        return n
    }
}
