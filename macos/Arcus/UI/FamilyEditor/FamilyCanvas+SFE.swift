import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// SFE: the Family Editor canvas snaps like the project's 2D views (see `FamilySnapper`): in the Ref. Level plan and the four
// elevations, every pick (reference planes, symbolic and annotation lines, labels, sketches, model and reference lines,
// controls, model text, plane drags) snaps to the forms' edges as the view draws them, symbolic, model and reference lines,
// regions, nested families, the sketch in progress and the reference planes, with the project's magenta markers, labels
// and dashed tracking lines. Tab cycles the snaps under the pointer; typed SE, SM, SI, … override the next pick. The
// Default 3D view has no picking or placing (every tool switches to a 2D view), so it doesn't snap.

/// The canvas's snapping state.
@MainActor
final class FamilySnapState {
    let snapper: FamilySnapper
    /// What the loaded snap geometry was built from.
    struct Key: Equatable { var revision: Int; var sketch: FamilyEditing.Sketch?; var view: FamilyPreviewMode }
    var key: Key?
    var tool: FamilyCanvasTool?
    /// Snaps stepped through with Tab, held while the pointer stays where Tab was pressed (screen point).
    var tab: (candidates: [SnapResult], index: Int, at: Vec2)?
    /// The last snap resolved for the pointer or a drag (drawn by the canvas).
    var last: SnapResult?
    /// True while a plane is dragged (its snap is drawn without a tool).
    var dragging = false
    var aliases = AliasMatcher()

    init(projectInfo: Element?) { snapper = FamilySnapper(projectInfo: projectInfo) }
}

extension FamilyCanvasView {
    private var sfeSize: Vec2 { Vec2(bounds.width, bounds.height) }
    private var sfeFrame: FamilyEditing.ViewFrame { viewMode.frame ?? .plan }

    /// The canvas's snap state, made on first use with the project's units.
    var sfeState: FamilySnapState {
        if let s = snapState { return s }
        let s = FamilySnapState(projectInfo: model?.state.model.projectInfoElement)
        snapState = s
        return s
    }

    /// The start of the line being drawn, in view coordinates (perpendicular, tangent, angle and length snaps).
    var sfeFrom: Vec2? {
        switch tool {
        case .symbolicLine?, .annotationLine?: return pending
        case .modelLine?: return chainStart.map { sfeFrame.view($0.point) }
        case .sketch?:
            if let c = pendingCorner { return sfeFrame.view(c.point) }
            guard let s = sketch, s.frame == sfeFrame, model?.sketchDraw == .line || s.drawsPath, let v = s.vertices.last else { return nil }
            return sfeFrame.view(v.point)
        default: return nil
        }
    }

    /// The snapped view point for `p` and the snap made (nil: free point, rounded to the millimetre).
    func sfeSnap(_ p: Vec2) -> (Vec2, SnapResult?) {
        guard viewMode != .threeD, let st = sfePrepare() else { return (p, nil) }
        if let t = st.tab {
            let sp = camera.toScreen(p, size: sfeSize)
            if hypot(sp.x - t.at.x, sp.y - t.at.y) <= 3 { let s = t.candidates[t.index]; st.last = s; return (s.point, s) }
            st.tab = nil
        }
        let r = st.snapper.snap(p, from: sfeFrom, constrainOrtho: tool != nil && NSEvent.modifierFlags.contains(.shift))
        st.last = r.snap
        return r
    }

    /// The snap state with its geometry, scale and settings current (nil in 3D).
    private func sfePrepare() -> FamilySnapState? {
        guard let model, viewMode != .threeD else { return nil }
        let st = sfeState
        let key = FamilySnapState.Key(revision: revision, sketch: sketch, view: viewMode)
        if st.key != key { st.snapper.load(sfeScene()); st.key = key }
        if st.tool != tool { st.tool = tool; st.tab = nil; st.snapper.resetTracking(); st.snapper.pickDone() }
        st.snapper.pixel = 1 / max(camera.scale, 1e-9)
        st.snapper.settings = model.state.snapSettings
        return st
    }

    /// A snapped view point as a sketch vertex locked to the planes it lies on.
    func sfeVertex(_ p: Vec2) -> FamilyEditing.SketchVertex {
        guard viewMode != .threeD else { return FamilyEditing.snapVertex(p, frame: .plan, planes: [], tolerance: 0) }
        return sfeState.snapper.vertex(sfeSnap(p).0, frame: sfeFrame)
    }

    /// Pointer moved: the snap's description joins the coordinates in the status bar.
    func sfeHover(_ p: Vec2) {
        guard tool != nil, tool != .dimension, viewMode != .threeD, let model else { return }
        guard let s = sfeSnap(p).1 else { return }
        var text = s.description
        if let t = sfeState.tab { text += " (\(t.index + 1) of \(t.candidates.count); Tab for the next)" }
        model.cursorText += "   " + text
    }

    /// A plane drag starts (it never snaps to itself) or ends (nil).
    func sfeExclude(_ item: FamilyEditing.Item?) {
        guard let st = sfePrepare() else { return }
        st.snapper.exclude(item.map { [$0] } ?? [])
        st.dragging = item != nil
        if item == nil { st.last = nil }
    }

    /// A pick was made: a typed override applied to it only, and a Tab choice is used up.
    func sfePickDone() {
        guard let st = snapState else { return }
        st.snapper.pickDone()
        st.tab = nil
    }

    /// Tab steps through the snaps under the pointer; letters type next-pick overrides (SE, SM, SI, …) while a tool runs.
    /// Returns true when the key was used.
    func sfeKey(_ event: NSEvent) -> Bool {
        guard tool != nil, viewMode != .threeD, let model else { return false }
        let st = sfeState
        if event.keyCode == 53 { return st.aliases.cancel() }
        if event.keyCode == 48 { return sfeCycleSnap() }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let chars = event.charactersIgnoringModifiers, chars.count == 1, let ch = chars.first, ch.isLetter else { return false }
        let out = st.aliases.feed(ch, at: event.timestamp, in: FamilySnapper.overrideAliases)
        for id in out.commands {
            guard let o = FamilySnapper.override(for: id) else { continue }
            st.snapper.snapOverride = o.override
            st.tab = nil
            model.message = o.message
        }
        needsDisplay = true
        return !out.commands.isEmpty || out.echo != nil
    }

    private func sfeCycleSnap() -> Bool {
        guard let c = cursor else { return false }
        let st = sfeState
        let sp = camera.toScreen(c, size: sfeSize)
        if var t = st.tab, hypot(sp.x - t.at.x, sp.y - t.at.y) <= 3 {
            t.index = (t.index + 1) % t.candidates.count
            st.tab = t
        } else {
            _ = sfeSnap(c) // the snap geometry is current
            let found = st.snapper.candidates(c, from: sfeFrom)
            guard found.count > 1 else { return false }
            st.tab = (found, 1, sp)
        }
        if let t = st.tab { st.last = t.candidates[t.index] }
        if let model, let s = st.last, let t = st.tab {
            model.cursorText = "\(s.description) (\(t.index + 1) of \(t.candidates.count); Tab for the next)"
        }
        needsDisplay = true
        return true
    }

    /// Draws the current snap: marker, label and tracking lines.
    func sfeDrawSnap(_ ctx: CGContext) {
        guard viewMode != .threeD, let st = snapState, let s = st.last else { return }
        // The Dimension tool picks planes, not points.
        guard st.dragging || (tool != nil && tool != .dimension && cursor != nil) else { return }
        SnapMarkerRenderer.draw(s, in: ctx, bounds: bounds, yDown: true) { p in
            let q = camera.toScreen(p, size: sfeSize)
            return CGPoint(x: q.x, y: q.y)
        }
    }

    // MARK: Scene

    /// The view's snappable geometry: what the canvas draws (forms, lines, regions, nested families), the true arcs of
    /// symbolic arcs, the sketch in progress and the reference planes. Dimensions, labels and controls don't snap.
    func sfeScene() -> FamilySnapScene {
        var scene = FamilySnapScene()
        guard let model else { return scene }
        let frame = sfeFrame
        scene.planes = drawing.planes.map { FamilyEditing.PlaneLine(name: $0.name, vertical: $0.vertical, value: $0.value) }
        let drawn = Set(drawing.strokes.compactMap(\.item))
        var arcItems = Set<FamilyEditing.Item>()
        if viewMode == .plan {
            for l in model.evaluated.planLines + model.evaluated.annotationLines {
                guard case .arc(let a) = l.curve, let id = l.sourceID, drawn.contains(.line(id)) else { continue }
                arcItems.insert(.line(id))
                scene.arcs.append(.init(arc: a, item: .line(id), label: sfeLabel(.line(id), model)))
            }
        }
        for st in drawing.strokes {
            guard let item = st.item, !arcItems.contains(item), st.points.count >= 2 else { continue }
            var hidden = st.style == .hiddenByVisibility
            if case .fill = item { hidden = false } // a masking region's boundary is drawn dashed but is its edge
            scene.curves.append(.init(points: st.points, closed: st.closed, item: item, label: sfeLabel(item, model), hidden: hidden))
        }
        if let s = sketch {
            let label = "Lines : <Sketch>"
            if s.frame == frame, s.vertices.count >= 2 {
                scene.curves.append(.init(points: s.vertices.map { frame.view($0.point) }, closed: false, item: nil, label: label))
            }
            if viewMode == .plan {
                if s.form == .blend, s.stage == 1, s.base.count >= 3 {
                    scene.curves.append(.init(points: s.base.map { Vec2(model.value(of: $0.x), model.value(of: $0.y)) }, closed: true, item: nil, label: label))
                }
                if s.form == .sweep || s.form == .sweptBlend, s.stage > 0, s.path.count >= 2 {
                    scene.curves.append(.init(points: s.path.map { Vec2(model.value(of: $0.x), model.value(of: $0.y)) }, closed: false, item: nil, label: label))
                }
            }
        }
        return scene
    }

    /// Status-bar name of a family item, in the project's "Category : Name" style.
    private func sfeLabel(_ item: FamilyEditing.Item, _ model: FamilyEditorModel) -> String {
        let title = model.title(item)
        switch item {
        case .solid: return "\(model.family.template.category.displayName) : \(title)"
        case .line: return "Lines : Symbolic Lines"
        case .modelLine(let id):
            return model.family.modelLines.first { $0.id == id }?.isReference == true ? "Reference Lines : Reference Line" : "Lines : Model Lines"
        case .fill: return "Detail Items : \(title.capitalized)"
        case .nested: return "Nested Families : \(title)"
        case .modelText: return "Model Text : \(title)"
        default: return title
        }
    }
}
