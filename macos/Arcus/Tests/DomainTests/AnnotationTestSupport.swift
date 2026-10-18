import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

// W2-ANNOT: a document session with a 10 × 8 box of walls on Level 1 for driving annotation tools the way the canvas
// does (pointerMoved, pointerDown, pointerUp, numericInput), with every action in its own undo group.

@MainActor
final class AnnotBench {
    let session: DocumentSession
    let ids: ProjectTemplates.Ids
    var walls: [ElementID] = []
    var messages: [String] = []
    /// What the text prompt answers (nil = cancel).
    var typedText: String? = "Note"
    private var contexts: [ElementID: ToolContext] = [:]

    init(units: UnitsSettings = .metric, box: Bool = true) {
        let (m, ids) = units == .metric ? Fx.template() : Fx.template(units: units)
        self.ids = ids
        session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        if box { step { session.perform("Box") { tx in walls = Fx.boxWalls(tx, ids) } } }
    }

    var model: BIMModel { session.model }
    var plan: ElementID { ids.planViews[ids.levels[0]]! }
    var level1: ElementID { ids.levels[0] }

    /// Runs `body` as one undoable step.
    func step(_ body: () -> Void) {
        session.undoManager.beginUndoGrouping()
        body()
        session.undoManager.endUndoGrouping()
    }

    @discardableResult
    func perform(_ name: String, _ body: (TransactionContext) throws -> Void) -> TransactionRecord? {
        var r: TransactionRecord?
        step { r = session.perform(name, body) }
        return r
    }

    func undo() { session.undoManager.undo() }
    func redo() { session.undoManager.redo() }

    func ctx(_ view: ElementID? = nil) -> ToolContext {
        let v = view ?? plan
        if let c = contexts[v] { return c }
        let c = ToolContext(session: session, viewID: v)
        c.pixel = 0.01
        c.showMessage = { [weak self] m in self?.messages.append(m) }
        c.requestText = { [weak self] _, _, done in done(self?.typedText) }
        c.requestTextInPlace = { [weak self] _, _, done in done(self?.typedText) }
        contexts[v] = c
        return c
    }

    func input(_ p: Vec2, hit: ElementID? = nil, snapped: Bool = false) -> ToolInput {
        var i = ToolInput(point: p, rawPoint: p, snap: snapped ? SnapResult(point: p, kind: .endpoint, elementIDs: []) : nil)
        i.hit = hit
        i.hitCandidates = hit.map { [$0] } ?? []
        return i
    }

    /// Moves to `p` and clicks (press and release) as the canvas does.
    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil, snapped: Bool = false) {
        let i = input(p, hit: hit, snapped: snapped)
        step {
            tool.pointerMoved(i)
            tool.pointerDown(i)
            tool.pointerUp(i)
        }
    }

    /// Types a value into the tool (as the canvas's numeric field does).
    func type(_ tool: some InteractiveTool, _ text: String) -> Bool {
        var ok = false
        step { ok = tool.numericInput(text) }
        return ok
    }

    /// Presses at `a`, drags to `b` and releases.
    func drag(_ tool: some InteractiveTool, from a: Vec2, to b: Vec2) {
        step {
            tool.pointerMoved(input(a))
            tool.pointerDown(input(a))
            tool.pointerDragged(input(b))
            tool.pointerMoved(input(b))
            tool.pointerUp(input(b))
        }
    }

    func graphics(_ view: ElementID? = nil) -> ViewGraphics {
        let v = model[view ?? plan]!
        if v.sheet != nil { return SheetGraphicsBuilder(model: model, sheet: v).build() }
        return ViewGraphicsBuilder(model: model, view: v).build()
    }

    func item(_ id: ElementID, _ view: ElementID? = nil) -> GItem? { graphics(view).items.first { $0.elementID == id } }

    struct Missing: Error { var what: String }
    /// The primitives an element draws in a view (throws when it draws nothing).
    func prims(_ id: ElementID, _ view: ElementID? = nil) throws -> [GPrimitive] {
        guard let i = item(id, view) else { throw Missing(what: "no graphics for \(id)") }
        return i.primitives
    }

    static func texts(_ prims: [GPrimitive]) -> [GText] { prims.compactMap { if case .text(let t) = $0 { t } else { nil } } }
    static func strings(_ prims: [GPrimitive]) -> [String] { texts(prims).map(\.string) }
    static func polylines(_ prims: [GPrimitive]) -> [([Vec2], GStroke)] { prims.compactMap { if case .polyline(let p, _, let s) = $0 { (p, s) } else { nil } } }
    static func arcs(_ prims: [GPrimitive]) -> [Arc2] { prims.compactMap { if case .arc(let a, _) = $0 { a } else { nil } } }
    static func fills(_ prims: [GPrimitive]) -> [([Polygon2], GFill)] { prims.compactMap { if case .fill(let p, let f) = $0 { (p, f) } else { nil } } }

    func strings(_ id: ElementID, _ view: ElementID? = nil) -> [String] { item(id, view).map { Self.strings($0.primitives) } ?? [] }

    /// The newest element of a category.
    func last(_ c: ArcusDomain.Category) -> Element? { model.elements(c).max { $0.id < $1.id } }

    /// A section looking north through the box, cut across it at y = 4 (created with the Section tool).
    func section() -> ElementID {
        let tool = SectionTool(ctx: ctx())
        click(tool, Vec2(-2, 4))
        click(tool, Vec2(12, 4))
        return model.views.filter { $0.view?.kind == .section }.max { $0.id < $1.id }!.id
    }

    /// A drafting view (or legend) at a scale.
    func draftingView(_ kind: ViewKind = .drafting, scale: Int = 10) -> ElementID {
        var id: ElementID!
        perform("View") { tx in id = tx.create(.views, name: "\(kind.rawValue) \(Int.random(in: 1...9999))", data: .view(ViewData(kind: kind, scale: scale))) }
        return id
    }

    func sheet() -> ElementID {
        var id: ElementID!
        perform("Sheet") { tx in id = tx.create(.sheets, name: "Annotations", data: .sheet(SheetData(number: "A900"))) }
        return id
    }
}
