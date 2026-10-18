import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F1: Opening ▸ By Face, Vertical and Dormer (RevitCraft `ToolKind::VerticalOpening` / `DormerOpening` in
// `crates/rc-app/src/canvas_tools.rs`): pick the roof (or floor or ceiling), then sketch the opening's boundary in
// sketch mode. A dormer's boundary starts in Pick Walls, so its walls (and Pick Lines for the roof edges) give the loop.

/// Picks a host, then runs a boundary sketch with the full Draw panel; Finish cuts the host.
@MainActor
public final class HostedOpeningTool: BaseTool, InteractiveTool {
    public let kind: HostedOpeningKind
    public let commandID: CommandID
    /// The floor, ceiling or roof being cut, once picked.
    public private(set) var hostID: ElementID?
    /// The boundary sketch (after the host is picked). It runs as a generic boundary sketch; Finish is handled here.
    public private(set) var sketch: SketchTool?

    public init(ctx: ToolContext, kind: HostedOpeningKind, host: ElementID? = nil) {
        self.kind = kind
        commandID = switch kind { case .vertical: .verticalOpening; case .byFace: .faceOpening; case .dormer: .dormerOpening }
        super.init(ctx: ctx)
        if let h = host, let e = ctx.model[h], HostedOpenings.canHost(e, kind: kind) { begin(on: h) }
    }

    public var title: String {
        switch kind {
        case .vertical: "Vertical Opening"
        case .byFace: "Opening by Face"
        case .dormer: "Dormer Opening"
        }
    }

    public var prompt: String {
        guard ctx.isPlan else { return "Openings are sketched in plan views." }
        if let s = sketch {
            return s.drawMode == .line && kind != .dormer && s.curves.isEmpty ? "Sketch the opening's closed boundary. Finish (↩) cuts the \(hostName)." : s.prompt
        }
        // RevitCraft's prompts.
        switch kind {
        case .vertical: return "Select a roof, floor, or ceiling."
        case .byFace: return "Pick a face of a roof, floor, or ceiling."
        case .dormer: return "Select the roof to be cut by the dormer opening."
        }
    }

    var hostName: String { ctx.model[hostID]?.category.singularName.lowercased() ?? "host" }

    public override var preview: ToolPreview {
        get { sketch.map { s in var p = s.preview; if let h = hostID { p.highlight.insert(h) }; return p } ?? super.preview }
        set { super.preview = newValue }
    }
    public var isSketchMode: Bool { sketch != nil }
    public var numericLabel: String? { sketch?.numericLabel }
    public var snapFrom: Vec2? { sketch?.snapFrom }
    public var options: [ToolOption] { sketch?.options ?? [] }
    public func setOption(_ id: String, _ value: ParamValue) { sketch?.setOption(id, value) }

    /// The host candidate under the pointer.
    func host(at i: ToolInput) -> Element? {
        for id in [i.hit].compactMap({ $0 }) + i.hitCandidates {
            if let e = ctx.model[id], HostedOpenings.canHost(e, kind: kind) { return e }
        }
        return nil
    }

    /// Starts the boundary sketch on a host.
    func begin(on host: ElementID) {
        hostID = host
        let s = SketchTool(ctx: ctx, target: .buildingPad, commandID: commandID)
        if kind == .dormer { s.setOption("mode", .text(SketchTool.DrawMode.pickWalls.rawValue)) }
        sketch = s
    }

    public func pointerMoved(_ i: ToolInput) {
        if let s = sketch { s.pointerMoved(i); return }
        super.preview = ToolPreview()
        if let e = host(at: i) { super.preview.highlight = [e.id]; super.preview.cursor = .pick }
    }

    public func pointerDown(_ i: ToolInput) {
        guard ctx.isPlan else { message("Open a plan view to sketch the opening."); return }
        if let s = sketch { s.pointerDown(i); return }
        guard let e = host(at: i) else {
            message(kind == .dormer ? "Select the roof to be cut by the dormer opening." : "Select a roof, floor, or ceiling.")
            return
        }
        begin(on: e.id)
        sketch?.pointerMoved(i)
    }

    public func pointerDragged(_ i: ToolInput) { sketch?.pointerDragged(i) }
    public func pointerUp(_ i: ToolInput) { sketch?.pointerUp(i) }
    public func numericInput(_ text: String) -> Bool { sketch?.numericInput(text) ?? false }
    public func spaceBar() { sketch?.spaceBar() }

    public func escape() -> EscapeResult {
        if let s = sketch { return s.escape() }
        return .exitTool
    }

    public func cancelSketch() {
        sketch = nil
        hostID = nil
        ctx.toolFinished?()
    }

    /// Validates the sketch (one closed loop; more loops cut more holes) and creates the opening.
    public func finish() -> Bool {
        guard let s = sketch, let host = hostID, let h = ctx.model[host] else { return false }
        let loops = s.splitLoops(s.curves)
        if let issue = SketchValidation.validate(s.curves, loops: loops) {
            s.presentSketchIssue(issue)
            return false
        }
        let boundary = Sketch(loops: loops)
        if case .failure(let err) = boundary.profile() { message(err.description); return false }
        guard create(boundary, host: h) != nil else { return false }
        sketch = nil
        hostID = nil
        ctx.toolFinished?()
        return true
    }

    /// Creates the opening element. Returns its id, or nil (with a message) when the boundary misses the host.
    @discardableResult
    public func create(_ boundary: Sketch, host: Element) -> ElementID? {
        Self.create(boundary, kind: kind, host: host, session: ctx.session, report: { [weak self] in self?.message($0) })
    }

    /// Creates a hosted opening of `kind` in `host` (shared by the tool and tests).
    @discardableResult
    public static func create(_ boundary: Sketch, kind: HostedOpeningKind, host: Element, session: DocumentSession,
                              report: (String) -> Void = { _ in }) -> ElementID? {
        guard HostedOpenings.canHost(host, kind: kind) else {
            report(kind == .dormer ? "Dormer openings cut roofs." : "Openings cut floors, roofs and ceilings.")
            return nil
        }
        guard case .success(let p) = boundary.profile(), let b = HostedOpenings.hostBounds(host, session.model), p.bounds.intersects(b) else {
            report("The opening must lie over the \(host.category.singularName.lowercased()) it cuts.")
            return nil
        }
        var id: ElementID?
        let data = ShaftOpeningData(boundary: boundary, unconnectedHeight: 0, hosted: kind)
        let name = switch kind { case .vertical: "Vertical Opening"; case .byFace: "Opening by Face"; case .dormer: "Dormer Opening" }
        session.perform("Create \(name)") { tx in
            id = tx.create(.shaftOpenings, name: name, data: .opening(.shaft(data)), levelID: host.levelID, hostID: host.id)
        }
        if let e = session.lastError { report(e.message); return nil }
        return id
    }
}
