import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// F1415: the Family Editor's commands (RevitCraft's Fe* commands, `crates/rc-app/src/actions.rs`), sketch mode
// (`family_editor.rs` `set_tool`, `finish`, `cancel_sketch`, Go To View, Work Plane Set), Model Line / Reference Line,
// Control, Model Text and Load into Project and Close. Sketch geometry lives in `FamilyEditing` (Domain).

extension FamilyEditorModel {
    /// The current 2D view's frame, nil in 3D.
    var frame: FamilyEditing.ViewFrame? { view.frame }

    /// Resolves a sketch bound to metres in the current type.
    func value(of b: FamilyBound) -> Double {
        switch b {
        case .plane(let n): evaluated.planes[n] ?? 0
        case .expr(let e): FamilyEditing.number(e) ?? 0
        }
    }

    /// Where new sketches, lines and text in `frame` start: the work plane when it is parallel to the view.
    func workOffset(_ frame: FamilyEditing.ViewFrame) -> FamilyBound {
        FamilyEditing.workPlaneOffset(family, named: workPlane, frame: frame)
    }

    // MARK: Commands

    /// Why a Family Editor command can't run now, or nil.
    func disabledReason(_ id: CommandID) -> String? {
        let sketching = sketch != nil
        switch id {
        case .feFinishSketch, .feCancelSketch: return sketching ? nil : "Nothing is being sketched."
        case .feOpening where !family.template.isHostedInWall: return "Openings cut the host of wall-hosted families (doors and windows)."
        case .feComponent where family.nestedFamilies.allSatisfy({ $0.template == .profile }): return nil // offers to load one
        case .feDimension where family.referencePlanes.count < 2: return "A dimension needs two parallel reference planes."
        case .fePurgeUnused where family.nestedFamilies.isEmpty: return "No families are loaded into this family."
        case .feWorkPlaneSet where family.referencePlanes.isEmpty: return "The family has no reference planes."
        default: break
        }
        let sketchTools: Set<CommandID> = [.feExtrusion, .feBlend, .feRevolve, .feSweep, .feSweptBlend, .feVoidExtrusion, .feVoidBlend, .feVoidRevolve, .feVoidSweep,
                                          .feFilledRegion, .feMaskingRegion, .feOpening]
        if sketching && sketchTools.contains(id) { return "Finish or cancel the current sketch first." }
        return nil
    }

    /// True when the command's tool is the one running (the ribbon highlights it).
    func isActive(_ id: CommandID) -> Bool {
        if let s = sketch {
            let form: FamilyEditing.SketchForm? = switch id {
            case .feExtrusion, .feVoidExtrusion: .extrusion
            case .feBlend, .feVoidBlend: .blend
            case .feRevolve, .feVoidRevolve: .revolve
            case .feSweep, .feVoidSweep: .sweep
            case .feSweptBlend: .sweptBlend
            case .feFilledRegion: .filledRegion
            case .feMaskingRegion: .maskingRegion
            case .feOpening: .opening
            default: nil
            }
            let void: Set<CommandID> = [.feVoidExtrusion, .feVoidBlend, .feVoidRevolve, .feVoidSweep]
            if let form { return s.form == form && s.isVoid == void.contains(id) }
        }
        switch (id, tool) {
        case (.feModelLine, .modelLine(false)?), (.feReferenceLine, .modelLine(true)?), (.feDimension, .dimension?), (.feSymbolicLine, .symbolicLine?): return true
        case (.feControl, .control?), (.feModelText, .modelText?): return true
        case (.feControlSingleVertical, .control(.singleVertical)?), (.feControlDoubleVertical, .control(.doubleVertical)?),
             (.feControlSingleHorizontal, .control(.singleHorizontal)?), (.feControlDoubleHorizontal, .control(.doubleHorizontal)?): return true
        case (.feReferencePlane, .referencePlane?): return true
        case (.feWorkPlaneShow, _): return showWorkPlane
        default: return false
        }
    }

    /// Runs a Family Editor command (ribbon, menus, command search).
    func perform(_ id: CommandID) {
        if let why = disabledReason(id) { message = why; return }
        switch id {
        case .feExtrusion: startSketch(.extrusion, void: false)
        case .feBlend: startSketch(.blend, void: false)
        case .feRevolve: startSketch(.revolve, void: false)
        case .feSweep: startSketch(.sweep, void: false)
        case .feSweptBlend: startSketch(.sweptBlend, void: false)
        case .feVoidExtrusion: startSketch(.extrusion, void: true)
        case .feVoidBlend: startSketch(.blend, void: true)
        case .feVoidRevolve: startSketch(.revolve, void: true)
        case .feVoidSweep: startSketch(.sweep, void: true)
        case .feFilledRegion: startSketch(.filledRegion, void: false)
        case .feMaskingRegion: startSketch(.maskingRegion, void: false)
        case .feOpening: startSketch(.opening, void: false)
        case .feFinishSketch: finishSketch()
        case .feCancelSketch: cancelSketch()
        case .feModelLine: startTool(.modelLine(reference: false))
        case .feReferenceLine: startTool(.modelLine(reference: true))
        case .feReferencePlane: startTool(.referencePlane(vertical: true))
        case .feDimension: startTool(.dimension)
        case .feSymbolicLine:
            if view != .plan { view = .plan }
            startTool(.symbolicLine)
        case .feControl: startControl(tool.flatMap { if case .control(let k) = $0 { k } else { nil } } ?? .singleHorizontal)
        case .feControlSingleVertical: startControl(.singleVertical)
        case .feControlDoubleVertical: startControl(.doubleVertical)
        case .feControlSingleHorizontal: startControl(.singleHorizontal)
        case .feControlDoubleHorizontal: startControl(.doubleHorizontal)
        case .feModelText:
            guard let text = Self.ask("Edit Text", "The text of the model text.", "Model Text") else { return }
            if view == .threeD { view = .front }
            startTool(.modelText(text))
        case .feText:
            if view != .plan { view = .plan }
            let l = FamilyEditing.newLabel(at: .zero, parameter: nil)
            edit("Add Text") { $0.labels.append(l) }
            selection = .label(l.id)
        case .feComponent: placeComponent()
        case .feFamilyTypes: sheet = .familyTypes
        case .feFamilyCategory: sheet = .categoryAndParameters
        case .feLoadIntoProject: loadIntoProject()
        case .feLoadAndClose: if loadIntoProject() { onClose?() }
        case .feDefault3D:
            orbit = FamilyOrbit()
            view = .threeD
            zoomToFit()
        case .feWorkPlaneSet: sheet = .workPlane
        case .feWorkPlaneShow: showWorkPlane.toggle()
        case .feLoadNestedFamily: FamilyNestedActions(model: self).loadFromFile()
        case .fePurgeUnused:
            var gone: [String] = []
            edit("Purge Unused") { gone = FamilyEditing.purgeUnusedNested(&$0) }
            message = gone.isEmpty ? "Every loaded family is in use." : "Purged \(gone.count) family(ies): \(gone.joined(separator: ", "))."
        case .feFlexTest: flex()
        case .feSaveFamilyAs: saveToDisk()
        default: break
        }
    }

    private func startTool(_ t: FamilyCanvasTool) {
        if case .modelLine = t, view == .threeD { view = .plan }
        if case .referencePlane = t, view == .threeD { view = .plan }
        if t == .dimension, view == .threeD { view = .plan }
        sketch = nil
        tool = tool == t ? nil : t
        if let tool { message = tool.prompt }
    }

    private func startControl(_ k: FamilyControlKind) {
        if view != .plan { view = .plan }
        sketch = nil
        tool = .control(k)
        message = "Click in plan where the \(k.rawValue.lowercased()) control goes. Placed instances show it in plan views."
    }

    /// Create ▸ Component: places a loaded family, or offers to load one (RevitCraft's "No Component family is loaded").
    private func placeComponent() {
        let placeable = family.nestedFamilies.filter { $0.template != .profile }
        guard !placeable.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No component family is loaded into this family."
            alert.informativeText = "Load a family into this family to place it as a nested component."
            alert.addButton(withTitle: "Load Family…"); alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn { FamilyNestedActions(model: self).loadFromFile() }
            return
        }
        if placeable.count == 1 { FamilyNestedActions(model: self).place(placeable[0]); return }
        let alert = NSAlert()
        alert.messageText = "Place Component"
        alert.informativeText = "Choose the loaded family to place."
        let pick = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26))
        pick.addItems(withTitles: placeable.map(\.name))
        alert.accessoryView = pick
        alert.addButton(withTitle: "Place"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        FamilyNestedActions(model: self).place(placeable[max(0, pick.indexOfSelectedItem)])
    }

    // MARK: Sketch mode

    /// Opens sketch mode for a form, region or opening, in a 2D view that suits it (RevitCraft opens a 2D view from 3D).
    func startSketch(_ form: FamilyEditing.SketchForm, void: Bool) {
        switch form {
        case .blend, .sweep, .sweptBlend, .filledRegion, .maskingRegion: if view != .plan { view = .plan }
        case .revolve, .opening: if view == .plan || view == .threeD { view = .front }
        case .extrusion: if view == .threeD { view = .plan }
        }
        if form == .opening, view != .front, view != .back { view = .front }
        guard let f = frame else { return }
        tool = .sketch
        selection = nil
        sketchDraw = form == .opening ? .rectangle : .line
        sketch = FamilyEditing.Sketch(form: form, isVoid: void, frame: f, depth: extrusionDepth, offset: workOffset(f))
        message = sketch?.prompt
    }

    /// Adds a clicked vertex to the sketch. Clicking the first vertex again closes the loop (a no-op for paths).
    func addSketchVertex(_ v: FamilyEditing.SketchVertex) {
        guard var s = sketch, let f = frame else { return }
        if s.frame != f {
            guard s.vertices.isEmpty else { message = "Finish this boundary in \(FamilyPreviewMode.view(for: s.frame).viewTitle)."; return }
            s.frame = f
            if s.stage == 0 { s.offset = workOffset(f) }
        }
        if !s.drawsPath, s.vertices.count >= 3, v.point.isAlmostEqual(s.vertices[0].point, tolerance: 1e-6) {
            message = "The loop is closed. Finish Edit Mode (✓) to create it."
            sketch = s
            return
        }
        if let last = s.vertices.last, last.point.isAlmostEqual(v.point, tolerance: 1e-6) { return }
        s.vertices.append(v)
        sketch = s
    }

    /// Adds a dragged or two-click rectangle to the sketch.
    func addSketchRectangle(_ a: FamilyEditing.SketchVertex, _ b: FamilyEditing.SketchVertex) {
        guard var s = sketch, let f = frame, abs(a.u - b.u) > 1e-6, abs(a.v - b.v) > 1e-6 else { return }
        guard !s.drawsPath else { message = "A path is drawn with lines."; return }
        s.frame = f
        if s.stage == 0 && s.vertices.isEmpty { s.offset = workOffset(f) }
        s.vertices = FamilyEditing.rectangle(a, b)
        sketch = s
    }

    /// Removes the last sketched vertex.
    func undoSketchVertex() {
        guard var s = sketch, !s.vertices.isEmpty else { return }
        s.vertices.removeLast()
        sketch = s
    }

    func setSketchAxis(_ v: FamilyEditing.SketchVertex) {
        guard var s = sketch else { return }
        s.axisU = v.u
        s.axisPlane = v.uPlane
        sketch = s
        tool = .sketch
        message = "Axis set. Sketch the profile on one side of it."
    }

    /// Finish Edit Mode (✓): makes the form (or moves the sketch to its next stage).
    func finishSketch() {
        guard var s = sketch else { return }
        s.depth = extrusionDepth
        let result = FamilyEditing.finish(&s, in: family, value: value(of:))
        switch result {
        case .next(let msg):
            sketch = s
            message = msg
            if (s.form == .sweep || s.form == .sweptBlend) && s.stage == 1 { goToProfileView() }
        case .solid(let solid):
            edit("Create \(solid.isVoid ? "Void " : "")\(solid.profile.kindName)") { $0.solids.append(solid) }
            endSketch()
            selection = .solid(solid.id)
            message = "Created \(solid.name)."
        case .fill(let fill):
            edit(fill.isMasking ? "Create Masking Region" : "Create Filled Region") { $0.fills.append(fill) }
            endSketch()
            selection = .fill(fill.id)
        case .opening(let o):
            edit("Create Opening") { $0.opening = o }
            endSketch()
            message = "The opening now cuts the host wall of placed instances."
        case .failed(let why):
            message = why
        }
    }

    /// Cancel Edit Mode (✗): abandons the sketch.
    func cancelSketch() {
        endSketch()
        message = nil
    }

    private func endSketch() {
        sketch = nil
        if tool == .sketch || tool == .axisLine { tool = nil }
    }

    /// Go To View: opens an elevation where the profile plane is parallel to the screen (RevitCraft `goto_view_dialog`).
    func goToProfileView() {
        guard let s = sketch else { return }
        let path = s.path.map { Vec2(value(of: $0.x), value(of: $0.y)) }
        guard let station = FamilyEditing.profileStation(path, form: s.form, atEnd: s.stage == 2) else { return }
        let views = FamilyEditing.profileViews(normal: station.normal).map(FamilyPreviewMode.view(for:))
        guard !views.isEmpty else { message = "No elevation looks across this path; sketch the profile in Properties after finishing a default one."; return }
        if views.count == 1 { show(views[0]); return }
        let alert = NSAlert()
        alert.messageText = "Go To View"
        alert.informativeText = "Open the view to sketch the profile in."
        for v in views { alert.addButton(withTitle: v.viewTitle) }
        alert.addButton(withTitle: "Cancel")
        let r = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if r >= 0 && r < views.count { show(views[r]) }
    }

    private func show(_ v: FamilyPreviewMode) {
        view = v
        if var s = sketch, let f = v.frame { s.frame = f; sketch = s }
        zoomToFit()
    }

    // MARK: Lines, controls and text

    /// Adds Model Line / Reference Line segments between two sketched points on the view's work plane.
    func addModelLine(from a: FamilyEditing.SketchVertex, to b: FamilyEditing.SketchVertex, reference: Bool) {
        guard let f = frame else { return }
        let lines = FamilyEditing.modelLines([a, b], frame: f, offset: workOffset(f), reference: reference)
        guard let l = lines.first else { return }
        edit(reference ? "Add Reference Line" : "Add Model Line") { $0.modelLines.append(l) }
        selection = .modelLine(l.id)
    }

    func placeControl(at v: FamilyEditing.SketchVertex, kind: FamilyControlKind) {
        let c = FamilyControl(position: v.familyPoint, kind: kind)
        edit("Place Control") { $0.controls.append(c) }
        selection = .control(c.id)
    }

    func placeModelText(_ text: String, at v: FamilyEditing.SketchVertex) {
        guard let f = frame else { return }
        let imperial = units.system == .imperial
        var t = FamilyModelText(text: text, plane: f.plane, position: v.familyPoint, offset: workOffset(f), size: imperial ? 0.3048 : 0.3, depth: imperial ? 0.0254 : 0.05)
        if !ModelTextGlyphs.isInstalled { t.fontName = ModelTextData.defaultFont }
        edit("Place Model Text") { $0.modelTexts.append(t) }
        selection = .modelText(t.id)
        tool = nil // text is placed once
    }

    // MARK: Load into Project and Close

    /// Load into Project; true when the family was loaded (Load into Project and Close then closes the window).
    @discardableResult
    func loadIntoProject() -> Bool {
        flex()
        if let r = flexResults, !r.isEmpty {
            message = "Fix the flex-test problems before loading into the project."
            return false
        }
        let existing = familyID.flatMap { state.model[$0]?.family != nil ? $0 : nil } ?? state.model.family(named: family.name)?.id
        var mode = FamilyReloadMode.keepProjectValues
        if existing != nil {
            guard let m = FamilyLoader.askReloadMode(family.name) else { return false }
            mode = m
        }
        FamilyLoader(state: state).load(family, replacing: existing, mode: mode)
        // W4-FAMED: a new family attaches to the project family it created, so a later rename reloads it instead of adding a second family.
        if familyID == nil { attach(existing ?? state.model.family(named: family.name)?.id) }
        message = existing == nil ? "Loaded “\(family.name)” into the project." : "Reloaded “\(family.name)” in the project."
        return true
    }
}
