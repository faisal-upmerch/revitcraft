import AppKit
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

/// Drawing, placing, selecting and moving in a 3D view (W2-3D).
///
/// Tools run on a level work plane: the pointer ray meets the horizontal plane at the level's elevation and the same
/// tool instances receive plan points through that level's floor-plan `ToolContext`, so tool logic, snapping, temporary
/// dimensions and typed values are exactly those of the plan. Doors, windows and other host pickers use the surface
/// under the pointer instead, so they follow the wall face you point at. Previews, the snap marker, temporary
/// dimensions and the cursor tooltip are drawn projected onto the plane in a transparent layer above the viewport.
///
/// Without a tool, dragging an element that is already selected moves the selection on the horizontal plane through
/// the grab point (walls move perpendicular to themselves, as in plan) with snapping to the plan geometry of the
/// element's level, a live ghost and a typed distance. Arrow keys nudge the selection. Everything else (orbit, pan,
/// click-select, camera keys) stays with the viewport.
@MainActor
final class Viewport3DToolController: NSObject, Viewport3DPointerHandler, NSTextFieldDelegate {
    unowned let state: DocumentState
    let viewID: ElementID
    weak var viewport: Viewport3DView?
    weak var host: NSView?
    let overlay = Viewport3DToolOverlay(frame: .zero)
    /// The work-plane level picked in the Options Bar for this view (nil: follow the default).
    var chosenLevel: ElementID?
    /// FMG4: the piece being dragged onto the view from Finder, drawn where it would land.
    var dropPreview: DropPreview3D?

    private enum Press {
        case none
        case tool
        /// Pressed on a selected element; becomes a drag after a few points of movement, else a click.
        case pending(grab: Vec3, id: ElementID, flags: NSEvent.ModifierFlags)
        case drag
        /// The rest of this press is ignored (a typed value ended the drag, or it could not start).
        case swallow
    }
    private var press = Press.none
    private var downPoint = CGPoint.zero
    private(set) var lastMouse: CGPoint?
    /// Plan point under the pointer on the current plane (for the work-plane grid).
    var planePoint: Vec2? // S3D2: set by tools on other work planes too
    private(set) var snap: SnapResult?
    /// Elevation of the plane the current interaction draws on.
    var planeZ = 0.0 // S3D2: set by tools on other work planes too
    /// The selection drag in progress (a plan `SelectTool` on the dragged element's level).
    private(set) var dragTool: SelectTool?
    private var planListeners: [ElementID: UUID] = [:]
    /// Per plan: its display list without annotations and the snap index built from it (what exists in 3D).
    private var modelPlans: [ElementID: (graphics: ViewGraphics, snaps: SnapIndex)] = [:]
    private var revisionObserved = false
    private var numericField: NSTextField?
    private enum NumericTarget { case tool, drag }
    private var numericTarget = NumericTarget.tool
    private var dragAwaitingValue = false
    private var tooltipVisible = false
    private var tooltipTimer: Timer?
    /// Snapping to the model geometry of the view (Viewport3DSnapping.swift). // S3D
    let snapping3D = Viewport3DSnapping()
    /// Furniture editing in 3D: shape handles, moves, temporary dimensions, Tab (Viewport3DFurniture*.swift). // FM3D
    let fm3d = FM3DViewState()

    init(state: DocumentState, viewID: ElementID, viewport: Viewport3DView, host: NSView) {
        self.state = state
        self.viewID = viewID
        self.viewport = viewport
        self.host = host
        super.init()
        overlay.controller = self
        overlay.frame = host.bounds
        overlay.autoresizingMask = [.width, .height]
        host.addSubview(overlay, positioned: .above, relativeTo: viewport)
        viewport.pointerHandler = self
        observeTools()
        observeSelection()
    }

    isolated deinit {
        tooltipTimer?.invalidate()
        for (plan, token) in planListeners { state.graphics.unlisten(plan, token) }
    }

    // MARK: Work plane

    /// The level tools draw on in this view.
    var workPlaneLevel: ElementID? {
        let m = state.model
        if let l = chosenLevel, m[l]?.level != nil, WorkPlane3D.planView(forLevel: l, in: m) != nil { return l }
        if case .level(let l)? = m[viewID]?.view?.workPlane, WorkPlane3D.planView(forLevel: l, in: m) != nil { return l } // F2: Work Plane ▸ Set
        return WorkPlane3D.defaultLevel(in: m, recentViews: state.viewHistory)
    }

    /// The plan tool context for `level` (default: the work plane), kept supplied with that plan's snap index.
    func context(forLevel level: ElementID? = nil) -> ToolContext? {
        guard let l = level ?? workPlaneLevel, let plan = WorkPlane3D.planView(forLevel: l, in: state.model) else { return nil }
        listen(plan)
        let c = state.toolContext(for: plan)
        c.currentTypes = state.currentTypes
        if let v = viewport { c.pixel = max(v.worldPerPoint(at: Vec3(v.camera.target.x, v.camera.target.y, c.levelElevation)), 1e-6) }
        return c
    }

    /// Picks a new work plane; a running tool restarts on it (its sketch or chain is discarded, as when changing views).
    func setWorkPlane(_ level: ElementID) {
        if activeSketchPlane != nil { WorkPlanes.set(.level(level), on: viewID, in: state.session) } // S3D2: back to a level
        guard level != workPlaneLevel || chosenLevel == nil else { return }
        chosenLevel = level
        if let tool = state.activeTool {
            let id = tool.commandID
            state.cancelTool()
            CommandRouter(state: state).run(id)
        }
        state.toolChangedState()
        refresh()
    }

    private func listen(_ plan: ElementID) {
        guard planListeners[plan] == nil else { return }
        planListeners[plan] = state.graphics.listen(plan) { [weak self] g in
            guard let self, let view = self.state.model[plan] else { return }
            let m = self.state.model
            self.state.toolContext(for: plan).snapIndex = SnapIndex(graphics: g, model: m, view: view)
            let mg = WorkPlane3D.modelGraphics(g, model: m)
            self.modelPlans[plan] = (mg, SnapIndex(graphics: mg, model: m, view: view))
        }
    }

    /// Plans are rebuilt on every model change while listened to; stop once nothing here needs them (no tool, drag or
    /// selection in this view).
    private func releasePlansIfIdle() {
        guard state.activeTool == nil, dragTool == nil, state.session.selection.isEmpty || host?.window == nil else { return }
        stopListening()
    }

    private func stopListening() {
        for (plan, token) in planListeners { state.graphics.unlisten(plan, token) }
        planListeners = [:]
        modelPlans = [:]
    }

    /// Runs `body` with the plan context snapping only to what the 3D view shows; the plan's own index (used when the
    /// plan is open in a tab) is restored afterwards.
    private func withModelSnaps<T>(_ ctx: ToolContext?, _ body: () -> T) -> T {
        guard let ctx, let idx = modelPlans[ctx.viewID]?.snaps else { return body() }
        let saved = ctx.snapIndex
        ctx.snapIndex = idx
        defer { ctx.snapIndex = saved }
        return body()
    }

    private func toolContext(of tool: (any InteractiveTool)?) -> ToolContext? { (tool as? BaseTool)?.ctx }

    // MARK: Tool state

    /// Called by `DocumentState.setTool`.
    func toolChanged() {
        numericField?.removeFromSuperview(); numericField = nil
        snap = nil
        snapping3D.reset() // S3D
        if let tool = state.activeTool {
            if let plan = (tool as? BaseTool)?.ctx.viewID, state.model[plan]?.view?.kind.isPlan == true { listen(plan) }
            if let v = viewport { v.window?.makeFirstResponder(v) }
            NSCursor.crosshair.set()
        } else {
            releasePlansIfIdle()
            viewport?.preselection = nil
            NSCursor.arrow.set()
        }
        refresh()
    }

    private func observeTools() {
        withObservationTracking {
            _ = state.toolRevision
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                // A tool ended (also in another view): stop rebuilding plans for snapping.
                self.releasePlansIfIdle()
                self.refresh()
                self.observeTools()
            }
        }
    }

    /// Selected elements can be dragged: keep their level's plan built so the first drag already snaps.
    private func observeSelection() {
        withObservationTracking {
            _ = state.session.selection.ids
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let ids = self.state.session.selection.ids
                self.overlay.needsDisplay = true // FM3D: shape handles follow the selection
                if self.host?.window != nil, !ids.isEmpty, let l = WorkPlane3D.level(of: ids, in: self.state.model),
                   let plan = WorkPlane3D.planView(forLevel: l, in: self.state.model) {
                    self.listen(plan)
                } else {
                    self.releasePlansIfIdle()
                }
                self.observeSelection()
            }
        }
    }

    func refresh() {
        overlay.needsDisplay = true
        if let tool = state.activeTool { viewport?.preselection = tool.preview.highlight.first }
    }

    /// Tools that pick a host face take the surface point under the pointer rather than the work plane.
    func prefersSurface(_ tool: any InteractiveTool) -> Bool { // S3D: internal for Tab snap cycling
        tool is InsertTool || tool is SplitTool || tool is PickHostTool || tool is TagTool || tool is AlignTool || tool is TrimExtendTool
            || tool is WallRevealTool // F1
            || tool is FurnitureJointTool // FM6: joints are picked on the parts' faces
    }

    // MARK: Input

    private func sample(_ event: NSEvent, at p: CGPoint, pick: Bool = true) -> WorkPlane3D.PointerSample? {
        guard let v = viewport else { return nil }
        let ray = v.pointerRay(at: p)
        let hit: (id: ElementID?, position: Vec3?) = pick ? v.pick(at: p) : (nil, nil)
        var s = WorkPlane3D.PointerSample(origin: ray.origin, direction: ray.direction, pickedID: hit.id, pickedPoint: hit.position)
        s.shift = event.modifierFlags.contains(.shift)
        s.command = event.modifierFlags.contains(.command)
        s.option = event.modifierFlags.contains(.option)
        s.clickCount = event.type == .mouseMoved ? 1 : event.clickCount
        return s
    }

    /// Screen tolerances on the plane: the world size of a point at the pointer's depth, a little larger on grazing views.
    private func setPixel(_ ctx: ToolContext, at q: Vec3) {
        guard let v = viewport else { return }
        let f = abs(v.cameraAxes.forward.z)
        ctx.pixel = max(v.worldPerPoint(at: q), 1e-6) / max(f, 0.3).squareRoot()
    }

    private func toolInput(_ event: NSEvent, at p: CGPoint, tool: any InteractiveTool) -> ToolInput? {
        if (tool as? BaseTool)?.ctx.furniture3D != nil { return fm3dToolInput(event, at: p, tool: tool) } // FM3D: Furniture tools on their 3D placement
        if (tool as? BaseTool)?.ctx.sketchPlane != nil { return sketchToolInput(event, at: p, tool: tool) } // S3D2: any work plane
        guard let ctx = (tool as? BaseTool)?.ctx ?? context(), let s = sample(event, at: p) else { return nil }
        let z = ctx.isPlan ? ctx.levelElevation : ctx.model.elevation(ofLevel: workPlaneLevel)
        let surface = prefersSurface(tool)
        guard let q = WorkPlane3D.planPoint(s, planeZ: z, preferSurface: surface) else { return nil }
        planeZ = z
        planePoint = q.xy
        setPixel(ctx, at: q)
        let g = modelPlans[ctx.viewID]?.graphics ?? state.graphics.graphics(ctx.viewID).map { WorkPlane3D.modelGraphics($0, model: state.model) }
        return snappedInput(s, at: p, planeZ: z, ctx: ctx, graphics: g, snapFrom: tool.snapFrom, preferSurface: surface, // S3D
                            constrainOrtho: event.modifierFlags.contains(.shift))
    }

    private func dragInput(_ event: NSEvent, at p: CGPoint, _ st: SelectTool) -> ToolInput? {
        guard let s = sample(event, at: p, pick: false), let q = WorkPlane3D.planPoint(s, planeZ: planeZ) else { return nil }
        planePoint = q.xy
        setPixel(st.ctx, at: q)
        return withModelSnaps(st.ctx) { snappedInput(s, at: p, planeZ: planeZ, ctx: st.ctx, graphics: modelPlans[st.ctx.viewID]?.graphics, // S3D
                                                     snapFrom: st.dragAnchor, orthoOnly: true) }
    }

    // MARK: Viewport3DPointerHandler

    func viewport3DMouseDown(_ event: NSEvent, at p: CGPoint) -> Bool {
        withModelSnaps(toolContext(of: state.activeTool) ?? dragTool?.ctx) { mouseDown(event, at: p) }
    }

    private func mouseDown(_ event: NSEvent, at p: CGPoint) -> Bool {
        lastMouse = p
        downPoint = p
        if fm3dMouseDown(event, at: p) { refresh(); return true } // FM3D: handles, values, parts, Tab, Pick a plane
        if let tool = state.activeTool {
            press = .tool
            guard let i = toolInput(event, at: p, tool: tool) else { return true }
            snap = i.snap
            tool.pointerDown(i)
            (tool as? BaseTool)?.ctx.snapOverride = nil
            snapping3D.tab = nil // S3D
            state.toolChangedState()
            refresh()
            return true
        }
        guard event.clickCount < 2, !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.command), let v = viewport else { return false }
        let hit = v.pick(at: p)
        guard let id = hit.id, let grab = hit.position, state.session.selection.contains(id) else { return false }
        press = .pending(grab: grab, id: id, flags: event.modifierFlags)
        return true
    }

    func viewport3DMouseDragged(_ event: NSEvent, at p: CGPoint) -> Bool {
        withModelSnaps(toolContext(of: state.activeTool) ?? dragTool?.ctx) { mouseDragged(event, at: p) }
    }

    private func mouseDragged(_ event: NSEvent, at p: CGPoint) -> Bool {
        lastMouse = p
        if fm3dMouseDragged(event, at: p) { return true } // FM3D
        pointerMovedForTooltip()
        switch press {
        case .none:
            return false
        case .swallow:
            return true
        case .tool:
            if let tool = state.activeTool, let i = toolInput(event, at: p, tool: tool) {
                tool.pointerDragged(i)
                tool.pointerMoved(i)
                snap = i.snap
                state.snapDescription = i.snap?.description
            }
        case .pending(let grab, let id, _):
            guard hypot(p.x - downPoint.x, p.y - downPoint.y) > 3 else { return true }
            guard beginDrag(grab: grab, id: id) else { press = .swallow; return true }
            press = .drag
            fallthrough
        case .drag:
            guard let st = dragTool, let i = dragInput(event, at: p, st) else { return true }
            snap = i.snap
            st.dragged(to: i.point, snapped: i.snap != nil)
            state.snapDescription = i.snap?.description
            state.hoverDescription = st.prompt
        }
        refresh()
        return true
    }

    func viewport3DMouseUp(_ event: NSEvent, at p: CGPoint) -> Bool {
        withModelSnaps(toolContext(of: state.activeTool) ?? dragTool?.ctx) { mouseUp(event, at: p) }
    }

    private func mouseUp(_ event: NSEvent, at p: CGPoint) -> Bool {
        defer { refresh() }
        if fm3dMouseUp(event, at: p) { return true } // FM3D
        switch press {
        case .none:
            return false
        case .swallow:
            press = .none
        case .tool:
            press = .none
            if let tool = state.activeTool, let i = toolInput(event, at: p, tool: tool) { tool.pointerUp(i) }
            state.toolChangedState()
        case .pending(_, let id, let flags):
            press = .none
            state.session.selection.click(id, shift: flags.contains(.shift), command: flags.contains(.command))
        case .drag:
            press = .none
            guard let st = dragTool else { return true }
            if numericField != nil, numericTarget == .drag, st.isDragging { dragAwaitingValue = true; return true }
            if let i = dragInput(event, at: p, st) { st.endDrag(i) } else { _ = st.escape() }
            endDrag()
        }
        return true
    }

    func viewport3DMouseMoved(_ event: NSEvent, at p: CGPoint) -> Bool {
        withModelSnaps(toolContext(of: state.activeTool) ?? dragTool?.ctx) { mouseMoved(event, at: p) }
    }

    private func mouseMoved(_ event: NSEvent, at p: CGPoint) -> Bool {
        if fm3dMouseMoved(event, at: p) { return true } // FM3D: a shape handle hovered, a Tab choice held; Place on Face
        guard let tool = state.activeTool else { return false }
        lastMouse = p
        pointerMovedForTooltip()
        guard let i = toolInput(event, at: p, tool: tool) else { snap = nil; refresh(); return true }
        snap = i.snap
        tool.pointerMoved(i)
        state.cursorPoint = i.rawPoint
        state.snapDescription = i.snap?.description
        switch tool.preview.cursor {
        case .notAllowed: NSCursor.operationNotAllowed.set()
        case .arrow: NSCursor.arrow.set()
        case .pick: NSCursor.pointingHand.set()
        case .move: NSCursor.openHand.set()
        case .copy: NSCursor.dragCopy.set()
        default: NSCursor.crosshair.set()
        }
        refresh()
        return true
    }

    func viewport3DCameraDidChange() {
        guard state.activeTool != nil || dragTool != nil || showsWorkPlane || fm3dShowsOverlay else { return } // F2: a shown work plane follows the camera; FM3D: handles
        overlay.needsDisplay = true
    }

    func viewport3DKeyDown(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        let chars = event.charactersIgnoringModifiers ?? ""
        let tool = state.activeTool
        if fm3dKeyDown(event) { refresh(); return true } // FM3D: Tab through stacked elements, Esc drops a handle drag
        switch event.keyCode {
        case 53: // Escape
            numericField?.removeFromSuperview(); numericField = nil
            if let st = dragTool { _ = st.escape(); endDrag(); refresh(); return true }
            guard tool != nil || !state.session.selection.isEmpty else { return false }
            state.escape(); refresh(); return true
        case 36, 76: // Return / Enter
            guard let t = tool else { return false }
            if t.finish() { state.toolChangedState() }
            refresh(); return true
        case 48: // Tab: step through the snaps under the pointer (S3D)
            guard tool != nil, let i = withModelSnaps(toolContext(of: tool), { cycleSnap3D() }) else { return false }
            snap = i.snap
            refresh(); return true
        case 49: // Space
            guard let t = tool else { return false }
            t.spaceBar(); state.toolChangedState(); refresh(); return true
        case 51, 117: // Delete
            guard tool == nil, !state.session.selection.isEmpty else { return false }
            state.session.delete(state.session.selection.ids); return true
        case 123, 124, 125, 126: // arrows nudge the selection; with nothing selected they stay camera keys
            guard tool == nil, dragTool == nil, flags.isEmpty, !state.session.selection.isEmpty else { return false }
            nudge(keyCode: event.keyCode, large: event.modifierFlags.contains(.shift))
            return true
        default: break
        }
        guard flags.isEmpty, let first = chars.first, first.isNumber || first == "-" || first == "." || first == "=" || first == "(" else { return false }
        if let label = tool?.numericLabel { beginNumericEntry(String(first), target: .tool, label: label); return true }
        if tool == nil, let st = dragTool, let label = st.numericLabel { beginNumericEntry(String(first), target: .drag, label: label); return true }
        return false
    }

    // MARK: Selection drag and nudge

    private func beginDrag(grab: Vec3, id: ElementID) -> Bool {
        let sel = state.session.selection.ids
        guard let level = WorkPlane3D.level(of: sel, preferred: id, in: state.model) ?? workPlaneLevel, let ctx = context(forLevel: level) else { return false }
        planeZ = grab.z
        setPixel(ctx, at: grab)
        let st = SelectTool(ctx: ctx)
        let (anchor, _) = withModelSnaps(ctx) { ctx.snap(grab.xy) }
        _ = st.beginDrag(at: anchor, grip: nil)
        dragTool = st
        return true
    }

    private func endDrag() {
        dragTool = nil
        dragAwaitingValue = false
        snap = nil
        snapping3D.pick = nil // S3D
        planePoint = nil
        state.hoverDescription = ""
        releasePlansIfIdle()
    }

    /// Moves the selection by 4 points on screen (20 with Shift) along the world axis nearest the arrow's screen direction.
    private func nudge(keyCode: UInt16, large: Bool) {
        guard let v = viewport else { return }
        let ids = state.session.selection.ids
        let (dx, dy) = keyCode == 123 ? (-1, 0) : keyCode == 124 ? (1, 0) : keyCode == 125 ? (0, -1) : (0, 1)
        var center = Vec3.zero
        var n = 0.0
        for id in ids { if let e = state.model[id] { let b = ElementMeshes.bounds(e, state.model); if !b.isEmpty { center = center + b.center; n += 1 } } }
        let at = n > 0 ? center / n : v.camera.target
        let axes = v.cameraAxes
        let step = v.worldPerPoint(at: at) * (large ? 20 : 4)
        let move = WorkPlane3D.nudge(dx: dx, dy: dy, cameraRight: axes.right, cameraUp: axes.up, cameraForward: axes.forward, step: step)
        guard move.length > 0 else { return }
        let plan = WorkPlane3D.level(of: ids, in: state.model).flatMap { WorkPlane3D.planView(forLevel: $0, in: state.model) } ?? viewID
        state.session.perform("Nudge") { tx in try ElementOperations.transform(ids, by: .translation(move), in: tx, viewID: plan) }
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
    }

    // MARK: Typed values

    private func beginNumericEntry(_ initial: String, target: NumericTarget, label: String) {
        guard let host else { return }
        numericField?.removeFromSuperview()
        numericTarget = target
        dragAwaitingValue = false
        let f = NSTextField(string: initial)
        f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        f.placeholderString = label
        f.delegate = self
        f.target = self
        f.action = #selector(numericCommitted(_:))
        f.bezelStyle = .roundedBezel
        f.setAccessibilityLabel(label)
        let p = lastMouse ?? CGPoint(x: host.bounds.midX, y: host.bounds.midY)
        f.frame = NSRect(x: min(p.x + 16, host.bounds.maxX - 130), y: max(p.y - 30, 4), width: 120, height: 22)
        host.addSubview(f, positioned: .above, relativeTo: overlay)
        host.window?.makeFirstResponder(f)
        f.currentEditor()?.selectedRange = NSRange(location: (initial as NSString).length, length: 0)
        numericField = f
    }

    @objc private func numericCommitted(_ sender: NSTextField) {
        let text = sender.stringValue
        sender.removeFromSuperview()
        numericField = nil
        if let v = viewport { v.window?.makeFirstResponder(v) }
        switch numericTarget {
        case .tool:
            if let t = state.activeTool, !t.numericInput(text) {
                state.show("“\(text)” is not a valid \(t.numericLabel?.lowercased() ?? "value").", error: true)
            }
        case .drag:
            guard let st = dragTool else { break }
            let label = st.numericLabel?.lowercased() ?? "value"
            if !st.numericInput(text) {
                state.show("“\(text)” is not a valid \(label).", error: true)
                if dragAwaitingValue { _ = st.escape() }
            }
            if !dragAwaitingValue { press = .swallow }
            endDrag()
        }
        numericTarget = .tool
        state.toolChangedState()
        refresh()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
        numericField?.removeFromSuperview(); numericField = nil
        if numericTarget == .drag, dragAwaitingValue, let st = dragTool { _ = st.escape(); endDrag() }
        numericTarget = .tool
        if let v = viewport { v.window?.makeFirstResponder(v) }
        refresh()
        return true
    }

    // MARK: Cursor tooltip

    private func pointerMovedForTooltip() {
        tooltipVisible = false
        tooltipTimer?.invalidate()
        tooltipTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.tooltipVisible = true
                self.overlay.needsDisplay = true
            }
        }
    }

    var tooltipText: String? {
        if let st = dragTool, st.isDragging { return "Drag to new position" }
        if let t = fm3dTooltip { return t } // FM3D
        guard let tool = state.activeTool else { return nil }
        if snapLabelShown, !(tool is InsertTool) { return nil } // S3D: the snap label shows beside the marker, as in plan
        if let s = snap, !(tool is InsertTool) { return s.shortLabel ?? s.kind.rawValue }
        let level = workPlaneLevel.flatMap { state.model[$0]?.name }
        return tool.prompt + (level.map { " (Work plane: \($0))" } ?? "")
    }

    // MARK: Drawing

    /// Draws the tool or drag preview projected onto the interaction plane, the snap marker and the tooltip.
    func drawOverlay(_ cg: CGContext, bounds: CGRect) {
        guard let v = viewport else { return }
        drawShownWorkPlane(cg, viewport: v) // F2: Work Plane ▸ Show
        drawDropPreview(cg, viewport: v) // FMG4: a piece being dragged in from Finder
        drawExplodeTags(cg, viewport: v) // FMG4: Explode Parts tags on the live view
        drawFM3D(cg, viewport: v) // FM3D: shape handles, temporary dimensions, moves
        let tool = state.activeTool
        let dragging = dragTool?.isDragging == true
        guard tool != nil || dragging else { return }
        let frame = drawFrame // S3D2: the level's plane, or the tool's work plane
        func seg(_ a: Vec2, _ b: Vec2) -> (CGPoint, CGPoint)? { v.viewSegment(frame.point(a.x, a.y), frame.point(b.x, b.y)) }
        func pt(_ a: Vec2) -> CGPoint? { v.viewPoint(of: frame.point(a.x, a.y)) }

        // A patch of the work plane around the pointer, so the plane being drawn on is visible.
        if tool != nil, let c = planePoint {
            let step = [0.1, 0.5, 1, 5, 10, 50].first { $0 >= v.worldPerPoint(at: frame.point(c.x, c.y)) * 18 } ?? 50
            let o = Vec2((c.x / step).rounded() * step, (c.y / step).rounded() * step)
            cg.saveGState()
            cg.setStrokeColor(Tokens.selection.withAlphaComponent(0.22).cgColor)
            cg.setLineWidth(0.75)
            for k in -4...4 {
                let d = Double(k) * step, r = 4 * step
                if let (a, b) = seg(o + Vec2(d, -r), o + Vec2(d, r)) { cg.move(to: a); cg.addLine(to: b) }
                if let (a, b) = seg(o + Vec2(-r, d), o + Vec2(r, d)) { cg.move(to: a); cg.addLine(to: b) }
            }
            cg.strokePath()
            cg.restoreGState()
        }

        var prims: [GPrimitive] = [], guides: [Segment2] = [], dims: [TemporaryDimension] = []
        if let t = tool { prims += t.preview.primitives; guides += t.preview.guides; dims += t.preview.tempDims }
        if dragging, let st = dragTool { prims += st.preview.primitives; guides += st.preview.guides; dims += st.preview.tempDims }
        for p in prims { draw(p, cg, seg: seg, pt: pt) }
        if let mk = tool as? any ToolWorldMarkers { drawWorldMarkers(mk.worldMarkers, cg, viewport: v) } // FM6: joint markers on the model
        drawGuides(guides, cg, seg: seg)
        for d in dims { drawTempDim(d, cg, seg: seg) }
        if let s = snap, !(tool is InsertTool) { drawSnap3D(s, cg, bounds: bounds, plane: frame) } // S3D: plan markers, on the model
        drawTooltip(cg, bounds: bounds)
    }

    private func draw(_ p: GPrimitive, _ cg: CGContext, seg: (Vec2, Vec2) -> (CGPoint, CGPoint)?, pt: (Vec2) -> CGPoint?) {
        func stroke(_ s: GStroke) {
            cg.setStrokeColor(s.color.nsColor.cgColor)
            cg.setLineWidth(s.weight > 1 ? 2.5 : 1.25)
            cg.setLineDash(phase: 0, lengths: s.pattern == .solid ? [] : [6, 4])
        }
        cg.saveGState()
        defer { cg.restoreGState() }
        switch p {
        case .polyline(let pts, let closed, let s):
            guard pts.count > 1 else { return }
            stroke(s)
            for i in 0..<(closed ? pts.count : pts.count - 1) {
                if let (a, b) = seg(pts[i], pts[(i + 1) % pts.count]) { cg.move(to: a); cg.addLine(to: b) }
            }
            cg.strokePath()
        case .arc(let a, let s):
            stroke(s)
            let n = max(8, Int(abs(a.sweep) / (.pi / 24)))
            let q = (0...n).map { a.point(atAngle: a.startAngle + a.sweep * Double($0) / Double(n)) }
            for i in 0..<n { if let (x, y) = seg(q[i], q[i + 1]) { cg.move(to: x); cg.addLine(to: y) } }
            cg.strokePath()
        case .fill(let polys, let f):
            cg.setFillColor(f.color.nsColor.withAlphaComponent(0.18 * (1 - f.transparency)).cgColor)
            for poly in polys {
                let q = poly.points.compactMap(pt)
                guard q.count == poly.points.count, q.count > 2 else { continue }
                cg.addLines(between: q); cg.closePath()
            }
            cg.fillPath()
        case .text(let t):
            guard let at = pt(t.position) else { return }
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: Tokens.construction]
            (t.string as NSString).draw(at: at, withAttributes: attrs)
        }
    }

    private func drawGuides(_ guides: [Segment2], _ cg: CGContext, seg: (Vec2, Vec2) -> (CGPoint, CGPoint)?) {
        guard !guides.isEmpty else { return }
        cg.saveGState()
        cg.setStrokeColor(Tokens.selection.withAlphaComponent(0.7).cgColor)
        cg.setLineWidth(1)
        cg.setLineDash(phase: 0, lengths: [6, 4])
        for g in guides { if let (a, b) = seg(g.start, g.end) { cg.move(to: a); cg.addLine(to: b) } }
        cg.strokePath()
        cg.restoreGState()
    }

    /// A temporary dimension as a thin line between its ends with its value in a box (angle dimensions: the value only).
    private func drawTempDim(_ d: TemporaryDimension, _ cg: CGContext, seg: (Vec2, Vec2) -> (CGPoint, CGPoint)?) {
        guard let (a, b) = seg(d.from, d.to), hypot(b.x - a.x, b.y - a.y) > 8 else { return }
        if !d.isAngle {
            cg.saveGState()
            cg.setStrokeColor(Tokens.construction.cgColor)
            cg.setLineWidth(1)
            cg.move(to: a); cg.addLine(to: b)
            for e in [a, b] { cg.addEllipse(in: CGRect(x: e.x - 1.5, y: e.y - 1.5, width: 3, height: 3)) }
            cg.strokePath()
            cg.restoreGState()
        }
        let size = (d.text as NSString).size(withAttributes: TempDimLabelStyle.attributes(active: d.isActive)) // BL-CANVAS: ARCUS-080
        let mid = d.isAngle ? CGPoint(x: a.x + (b.x - a.x) * 0.25, y: a.y + (b.y - a.y) * 0.25 - 16) : CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 + 10)
        TempDimLabelStyle.draw(d.text, in: TempDimLabelStyle.box(size: size, mid: mid), active: d.isActive, highlighted: false, canvas: .windowBackgroundColor)
    }

    private func drawTooltip(_ cg: CGContext, bounds: CGRect) {
        guard tooltipVisible, let text = tooltipText, !text.isEmpty, let m = lastMouse, bounds.contains(m) else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        let size = (text as NSString).size(withAttributes: attrs)
        var box = NSRect(x: m.x + 14, y: m.y - size.height - 22, width: size.width + 12, height: size.height + 6)
        if box.maxX > bounds.maxX - 4 { box.origin.x = m.x - box.width - 10 }
        if box.minY < bounds.minY + 4 { box.origin.y = m.y + 16 }
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        cg.setFillColor(NSColor.windowBackgroundColor.cgColor)
        cg.fill(box)
        cg.restoreGState()
        cg.setStrokeColor(NSColor.separatorColor.cgColor)
        cg.setLineWidth(1)
        cg.stroke(box.insetBy(dx: 0.5, dy: 0.5))
        (text as NSString).draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attrs)
    }
}

/// Transparent layer above the 3D viewport for tool previews; events pass through to the viewport.
final class Viewport3DToolOverlay: NSView {
    weak var controller: Viewport3DToolController?
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) {
        guard let cg = NSGraphicsContext.current?.cgContext else { return }
        controller?.drawOverlay(cg, bounds: bounds)
    }
}

// MARK: - Hooks used by shared files

extension DocumentState {
    /// The 3D tool controller of the active view, when it is a 3D view.
    var active3DTools: Viewport3DToolController? {
        (activeViewID.flatMap { canvases[$0] } as? Viewport3DHost)?.tools
    }
}

extension CommandRouter {
    /// Commands that run on a work plane in 3D views.
    static let w23DCommands: Set<CommandID> = [
        .wall, .wallArc, .wallRectangle, .wallPickLines, .curtainWall, .door, .window, .component, .column, .structuralColumn, .beam,
        .floor, .floorPickWalls, .ceiling, .roofFootprint, .roofPickWalls, .stairStraight, .stairL, .stairU, .railing, .ramp,
        .modelLine, .grid, .referencePlane, .shaftOpening, .buildingPad, .move, .copy,
        .wallReveal, // F1: clicks a wall face
        .stackedWall, // F2
    ]
    /// Modify tools whose work plane is the selection's level.
    static let w23DSelectionCommands: Set<CommandID> = [.move, .copy, .rotate, .mirrorPickAxis, .mirrorDrawAxis, .array, .scale, .align, .split, .trimExtendCorner, .trimExtendSingle, .trimExtendMultiple, .offset]

    /// Availability in 3D views: `.some(nil)` runs, `.some(reason)` is disabled, nil defers to the other checks.
    func w23DDisabledReason(_ id: CommandID) -> String?? {
        guard viewKind == .threeD, state.activeViewportEditor == nil, Self.w23DCommands.contains(id) else { return nil }
        guard state.active3DTools?.workPlaneLevel != nil else { return .some("Add a floor plan for a level to draw on it in 3D.") }
        if (id == .move || id == .copy) && selection.isEmpty { return .some("Select elements first.") }
        return .some(nil)
    }

    /// In a 3D view, tools run in the floor-plan context of the work plane (or of the selection, for modify tools).
    func w23DToolContext() -> ToolContext? {
        guard viewKind == .threeD, state.activeViewportEditor == nil, let tools = state.active3DTools else { return nil }
        var level: ElementID?
        if tools.chosenLevel == nil, let cmd = state.recentCommands.first, Self.w23DSelectionCommands.contains(cmd) { level = WorkPlane3D.level(of: selection, in: model) }
        return tools.context(forLevel: level)
    }
}
