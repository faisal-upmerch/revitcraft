import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusServices

/// Starting content for new families per category template.
enum FamilyTemplates {
    static func make(_ t: FamilyTemplate) -> FamilyDefinition {
        var f: FamilyDefinition
        switch t {
        case .door: f = StarterLibrary.singleDoor()
        case .window: f = StarterLibrary.casementWindow()
        case .casework: f = StarterLibrary.baseCabinet()
        case .plumbingFixture: f = StarterLibrary.basin()
        case .tag: f = StarterLibrary.tagFamily("Tag", categories: [.genericModels], label: "Mark", shape: "rect")
        case .titleBlock: f = StarterLibrary.titleBlock("Title Block", width: 0.42, height: 0.297)
        case .genericAnnotation: f = StarterLibrary.northArrow()
        case .profile: f = StarterLibrary.handrailProfile()
        case .detailComponent: f = StarterLibrary.woodBlocking()
        default: f = StarterLibrary.genericBox()
        }
        f.template = t
        f.types = [f.types.first ?? FamilyTypeDefinition(name: "Type 1", values: [:])]
        if t.is3D { f.addTemplateOriginConstraints() } // BL-SITE: new labeled dimensions can't drift the family off its origin
        return f
    }
}

// W4-FAMED: document-style window (sidebar · canvas · inspector) with a persisted frame and split positions.
@MainActor
final class FamilyEditorWindowController: NSWindowController, NSWindowDelegate {
    static var open: [FamilyEditorWindowController] = []
    let model: FamilyEditorModel
    private var toolbarDelegate: FamilyEditorToolbar!

    static func open(familyID: ElementID, state: DocumentState) {
        if let existing = open.first(where: { $0.model.familyID == familyID && $0.model.state === state }) { existing.window?.makeKeyAndOrderFront(nil); return }
        guard let fam = state.model[familyID]?.family else { return }
        present(FamilyEditorModel(family: fam, state: state, familyID: familyID))
    }
    static func open(new family: FamilyDefinition, state: DocumentState) {
        present(FamilyEditorModel(family: family, state: state, familyID: nil))
    }
    @discardableResult
    private static func present(_ m: FamilyEditorModel) -> FamilyEditorWindowController {
        let wc = FamilyEditorWindowController(model: m)
        open.append(wc)
        wc.showWindow(nil)
        return wc
    }

    init(model: FamilyEditorModel) {
        self.model = model
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.minSize = NSSize(width: 1000, height: 640)
        w.toolbarStyle = .unified
        w.tabbingMode = .disallowed
        w.contentViewController = FamilyEditorSplitController(model: model)
        w.setFrameAutosaveName("ArcusFamilyEditor")
        if w.frame.width < 1000 || w.frame.height < 640 { w.setContentSize(NSSize(width: 1440, height: 900)); w.center() }
        super.init(window: w)
        w.delegate = self
        toolbarDelegate = FamilyEditorToolbar(model: model, controller: self)
        let tb = NSToolbar(identifier: "ArcusFamilyEditorToolbar")
        tb.delegate = toolbarDelegate
        tb.displayMode = .iconOnly // W4-AUDIT: labels truncated at 1280 pt; the titles stay in the tooltips
        tb.allowsUserCustomization = false
        w.toolbar = tb
        updateTitle()
        model.onRename = { [weak self] _ in self?.updateTitle() }
        model.onClose = { [weak self] in self?.close() } // F1415: Load into Project and Close
    }
    required init?(coder: NSCoder) { fatalError() }

    func updateTitle() {
        window?.title = "Family Editor – \(model.family.name)"
        window?.subtitle = "\(model.family.template.rawValue) family" + (model.familyID == nil ? " · not loaded" : "")
    }

    func windowWillClose(_ notification: Notification) { FamilyEditorWindowController.open.removeAll { $0 === self } }
    /// Edit ▸ Undo/Redo and ⌘Z in the window use the family's own undo stack.
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { model.undo }
}

/// Tools sketched on the family canvas (the ribbon's Create and Annotate tabs).
enum FamilyCanvasTool: Equatable {
    /// A reference plane drawn vertically (true) or horizontally in the current view.
    case referencePlane(vertical: Bool)
    case dimension
    case symbolicLine
    case annotationLine
    case label
    /// F1415: sketch mode: the model's `sketch` (forms, regions, openings) is drawn on the canvas.
    case sketch
    /// F1415: the revolve's axis line, picked while sketching a revolve.
    case axisLine
    /// F1415: Model Line or Reference Line, drawn as a chain on the view's work plane.
    case modelLine(reference: Bool)
    /// F1415: Control, placed in plan.
    case control(FamilyControlKind)
    /// F1415: Model Text with its text, placed by a click.
    case modelText(String)

    var title: String {
        switch self {
        case .referencePlane(let v): v ? "Vertical Reference Plane" : "Horizontal Reference Plane"
        case .dimension: "Dimension"
        case .symbolicLine: "Symbolic Line"
        case .annotationLine: "Annotation Line"
        case .label: "Label"
        case .sketch: "Sketch"
        case .axisLine: "Axis Line"
        case .modelLine(let r): r ? "Reference Line" : "Model Line"
        case .control(let k): "Control: \(k.rawValue)"
        case .modelText: "Model Text"
        }
    }
    var prompt: String {
        switch self {
        case .referencePlane: "Click to place the reference plane. Esc cancels."
        case .dimension: "Click the first reference plane, then a parallel one."
        case .symbolicLine, .annotationLine: "Click the start point, then the end point."
        case .label: "Click where the label goes."
        case .sketch: "Sketch on the canvas; Finish Edit Mode (✓ or Return) when done."
        case .axisLine: "Click where the revolve's vertical axis goes."
        case .modelLine: "Click the start, then each next point; Esc ends the chain."
        case .control: "Click in plan where the flip control goes."
        case .modelText: "Click to place the model text."
        }
    }
}

@MainActor
@Observable
final class FamilyEditorModel {
    var family: FamilyDefinition {
        didSet {
            refresh()
            if oldValue.name != family.name { onRename?(family.name) }
        }
    }
    /// Called when the family is renamed (the window title follows).
    @ObservationIgnored var onRename: ((String) -> Void)?
    var currentType: String { didSet { refresh() } }
    /// The family evaluated for `currentType` (kept current as the family or type changes).
    private(set) var evaluated: EvaluatedFamily
    var flexResults: [String]? = nil
    var message: String?
    let state: DocumentState
    /// Project family this window edits; set after the first Load into Project of a new family so later loads reload it.
    private(set) var familyID: ElementID?
    let undo = UndoManager()

    // W4-FAMED: view state shared by the browser, ribbon, canvas and inspector.
    var view: FamilyPreviewMode = .plan { didSet { drawingRevision += 1; if !openViews.contains(view) { openViews.append(view) } } } // F1415: view tabs
    var detail: DetailLevel = .fine { didSet { drawingRevision += 1 } }
    var applyVisibility = true { didSet { drawingRevision += 1 } }
    /// Bumped whenever the canvas drawing must be rebuilt (evaluation, view, detail level, visibility).
    private(set) var drawingRevision = 0
    var selection: FamilyEditing.Item?
    var tool: FamilyCanvasTool?
    /// Incremented to ask the canvas to zoom to fit.
    var fitRequest = 0
    /// Cursor position readout from the canvas.
    var cursorText = ""
    enum Sheet: String, Identifiable { case familyTypes, categoryAndParameters, workPlane; var id: String { rawValue } }
    var sheet: Sheet?

    // F1415: view tabs, 3D orbit, sketch mode, the work plane and control placement.
    /// The family's open views (the view tabs over the canvas).
    var openViews: [FamilyPreviewMode] = [.plan]
    /// Direction the Default 3D view looks from (orbit).
    var orbit = FamilyOrbit() { didSet { drawingRevision += 1 } }
    /// True while the 3D view is being orbited: the canvas draws plain edges until the drag ends.
    var orbiting = false { didSet { drawingRevision += 1 } }
    /// The sketch in progress (sketch mode), or nil.
    var sketch: FamilyEditing.Sketch?
    /// Draw panel choice while sketching.
    var sketchDraw: FamilySketchDraw = .line
    /// Depth of new extrusions and blends.
    var extrusionDepth = 0.25
    /// Work Plane ▸ Set: the named reference plane new sketches, lines and text start from (nil = the view's own plane).
    var workPlane: String? { didSet { drawingRevision += 1 } }
    /// Work Plane ▸ Show.
    var showWorkPlane = false { didSet { drawingRevision += 1 } }
    /// Closes the window (Load into Project and Close).
    @ObservationIgnored var onClose: (() -> Void)?

    init(family: FamilyDefinition, state: DocumentState, familyID: ElementID?) {
        self.family = family
        self.state = state
        self.familyID = familyID
        let t = family.types.first?.name ?? ""
        currentType = t
        evaluated = FamilyEvaluator.evaluate(family, typeName: t, units: state.model.units)
    }

    var units: UnitsSettings { state.model.units }

    private func refresh() {
        evaluated = FamilyEvaluator.evaluate(family, typeName: currentType, units: units)
        drawingRevision += 1
        if let s = selection, !exists(s) { selection = nil }
    }

    func edit(_ name: String, _ change: (inout FamilyDefinition) -> Void) {
        let before = family
        var next = family
        change(&next)
        guard next != before else { return }
        family = next
        flexResults = nil
        undo.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.restore(before, name: name) } }
        undo.setActionName(name)
    }

    /// Undo/redo step: swaps the family back and registers the inverse.
    private func restore(_ f: FamilyDefinition, name: String) {
        let now = family
        family = f
        if family.type(named: currentType) == nil { currentType = family.types.first?.name ?? "" }
        flexResults = nil
        undo.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.restore(now, name: name) } }
        undo.setActionName(name)
    }

    // MARK: Element edits by identity

    func updateSolid(_ id: String, _ name: String = "Edit Form", _ change: (inout FamilySolid) -> Void) {
        edit(name) { f in if let i = f.solids.firstIndex(where: { $0.id == id }) { change(&f.solids[i]) } }
    }
    func updatePlanLine(_ id: String, _ change: (inout FamilyLine) -> Void) {
        edit("Edit Line") { f in
            if let i = f.planLines.firstIndex(where: { $0.id == id }) { change(&f.planLines[i]) }
            else if let i = f.annotationLines.firstIndex(where: { $0.id == id }) { change(&f.annotationLines[i]) }
        }
    }
    func updateLabel(_ id: String, _ change: (inout FamilyLabel) -> Void) {
        edit("Edit Label") { f in if let i = f.labels.firstIndex(where: { $0.id == id }) { change(&f.labels[i]) } }
    }
    func updateDimension(_ id: String, _ change: (inout FamilyDimension) -> Void) {
        let planes = evaluated.planes
        edit("Edit Dimension") { f in
            guard let i = f.dimensions.firstIndex(where: { $0.id == id }) else { return }
            let before = f.dimensions[i]
            change(&f.dimensions[i])
            f.dimensions[i].fixLabelDirection(planes, after: before) // BL-SITE
        }
    }
    func updatePlane(_ name: String, _ change: (inout FamilyReferencePlane) -> Void) {
        edit("Edit Reference Plane") { f in if let i = f.referencePlanes.firstIndex(where: { $0.name == name }) { change(&f.referencePlanes[i]) } }
    }
    func updateNested(_ id: String, _ name: String = "Edit Nested Family", _ change: (inout NestedFamilyInstance) -> Void) {
        edit(name) { f in if let i = f.nestedInstances.firstIndex(where: { $0.id == id }) { change(&f.nestedInstances[i]) } }
    }
    func updateParameter(_ name: String, _ action: String = "Edit Parameter", _ change: (inout FamilyParameter) -> Void) {
        edit(action) { f in if let i = f.parameters.firstIndex(where: { $0.name == name }) { change(&f.parameters[i]) } }
    }

    // MARK: Selection

    func exists(_ item: FamilyEditing.Item) -> Bool {
        switch item {
        case .type(let n): family.type(named: n) != nil
        case .plane(let n): family.referencePlanes.contains { $0.name == n }
        case .dimension(let id): family.dimensions.contains { $0.id == id }
        case .solid(let id): family.solids.contains { $0.id == id }
        case .line(let id): family.planLines.contains { $0.id == id } || family.annotationLines.contains { $0.id == id }
        case .label(let id): family.labels.contains { $0.id == id }
        case .nested(let id): family.nestedInstances.contains { $0.id == id }
        case .parameter(let n): family.parameter(named: n) != nil
        case .modelLine(let id): family.modelLines.contains { $0.id == id } // F1415
        case .control(let id): family.controls.contains { $0.id == id }
        case .modelText(let id): family.modelTexts.contains { $0.id == id }
        case .fill(let id): family.fills.contains { $0.id == id }
        }
    }

    func select(_ item: FamilyEditing.Item?) {
        selection = item
        if case .type(let n)? = item, n != currentType { currentType = n }
    }

    /// Short description of an item for the inspector header and the browser.
    func title(_ item: FamilyEditing.Item) -> String {
        switch item {
        case .type(let n): n
        case .plane(let n): n
        case .dimension(let id):
            if let d = family.dimensions.first(where: { $0.id == id }) { d.isEquality ? "EQ \(d.planeA) · \(d.planeB) · \(d.planeC ?? "")" : "\(d.planeA) → \(d.planeB)" } else { "Dimension" }
        case .solid(let id): family.solids.first { $0.id == id }?.name ?? "Form"
        case .line(let id):
            if let l = family.planLines.first(where: { $0.id == id }) ?? family.annotationLines.first(where: { $0.id == id }) {
                switch l.shape { case .line: "\(l.subcategory.rawValue) line"; case .arc: "\(l.subcategory.rawValue) arc" }
            } else { "Line" }
        case .label(let id): family.labels.first { $0.id == id }.map { $0.parameterName.map { "〈\($0)〉" } ?? "“\($0.staticText)”" } ?? "Label"
        case .nested(let id): family.nestedInstances.first { $0.id == id }.map { "\($0.familyName)" + ($0.typeName.map { ": \($0)" } ?? "") } ?? "Nested family"
        case .parameter(let n): n
        case .modelLine(let id): family.modelLines.first { $0.id == id }.map { ($0.isReference ? "Reference line" : "Model line") + " (\($0.plane.rawValue))" } ?? "Line" // F1415
        case .control(let id): family.controls.first { $0.id == id }.map { "Control: \($0.kind.rawValue)" } ?? "Control"
        case .modelText(let id): family.modelTexts.first { $0.id == id }.map { "“\($0.text)”" } ?? "Model Text"
        case .fill(let id): family.fills.first { $0.id == id }.map { $0.isMasking ? "Masking region" : "Filled region" } ?? "Region"
        }
    }

    func deleteSelection() {
        guard let s = selection else { return }
        let positions = evaluated.planes
        var baked = 0
        if case .plane(let n) = s, family.referencePlanes.first(where: { $0.name == n })?.definesOrigin == true { message = "“\(n)” defines the family origin and can't be deleted."; return }
        if case .parameter(let n) = s, family.parameter(named: n)?.isBuiltIn == true { message = "Built-in parameters can't be deleted."; return }
        if case .type = s, family.types.count <= 1 { message = "A family needs at least one type."; return }
        edit("Delete \(title(s))") { f in
            if case .plane(let n) = s { baked = FamilyEditing.deletePlane(&f, n, positions: positions) } else { FamilyEditing.delete(s, from: &f, positions: positions) }
        }
        if case .type = s { currentType = family.types.first?.name ?? "" }
        if case .plane(let n) = s { message = baked > 0 ? "Deleted “\(n)”; \(baked) face(s) locked to it now keep its position." : nil }
        if case .parameter(let n) = s { message = "Deleted “\(n)”. Formulas that used it are reported by the flex test." }
        selection = nil
    }

    func duplicateSelection() {
        guard let s = selection else { return }
        switch s {
        case .solid(let id):
            guard let src = family.solids.first(where: { $0.id == id }) else { return }
            let copy = FamilyEditing.duplicate(src)
            edit("Duplicate Form") { $0.solids.append(copy) }
            selection = .solid(copy.id)
        case .type(let n):
            let name = FamilyEditing.uniqueName(n) { self.family.type(named: $0) != nil }
            edit("Duplicate Type") { FamilyEditing.addType(&$0, named: name, copying: n) }
            currentType = name; selection = .type(name)
        case .line(let id):
            guard var l = family.planLines.first(where: { $0.id == id }) ?? family.annotationLines.first(where: { $0.id == id }) else { return }
            let plan = family.planLines.contains { $0.id == id }
            l = FamilyLine(shape: l.shape, subcategory: l.subcategory, weight: l.weight)
            edit("Duplicate Line") { if plan { $0.planLines.append(l) } else { $0.annotationLines.append(l) } }
            selection = .line(l.id)
        default: message = "Only forms, lines and types can be duplicated."
        }
    }

    // MARK: Canvas authoring (W4-FAMED)

    /// The family axis a line drawn vertically (or horizontally) in the current view represents.
    func axis(vertical: Bool) -> FamilyAxis? { view.axes.map { vertical ? $0.u : $0.v } }

    func addPlane(vertical: Bool, at value: Double) {
        guard let axis = axis(vertical: vertical) else { message = "Reference planes are drawn in plan and elevation views."; return }
        let p = FamilyEditing.newPlane(family, axis: axis, at: value)
        edit("Add Reference Plane") { $0.referencePlanes.append(p) }
        selection = .plane(p.name)
    }

    func addPlane(_ axis: FamilyAxis) {
        let p = FamilyEditing.newPlane(family, axis: axis, at: 0.1)
        edit("Add Reference Plane") { $0.referencePlanes.append(p) }
        selection = .plane(p.name)
    }

    func addDimension(_ a: String, _ b: String) {
        guard let d = FamilyEditing.dimension(family, between: a, and: b) else { message = "A dimension needs two different parallel reference planes."; return }
        edit("Add Dimension") { $0.dimensions.append(d) }
        selection = .dimension(d.id)
    }

    /// A dimension (or EQ) between the outermost planes of the first axis with enough planes.
    func addDimension(eq: Bool) {
        let byAxis = Dictionary(grouping: family.referencePlanes, by: \.axis)
        let preferred = view.axes.map { [$0.u, $0.v] } ?? []
        guard let group = (preferred + FamilyAxis.allCases).compactMap({ byAxis[$0] }).first(where: { $0.count >= (eq ? 3 : 2) }) else {
            message = eq ? "EQ needs three parallel reference planes." : "A dimension needs two parallel reference planes."
            return
        }
        let sorted = group.sorted { (evaluated.planes[$0.name] ?? 0) < (evaluated.planes[$1.name] ?? 0) }
        let d = eq ? FamilyDimension.equality(sorted[0].name, sorted[1].name, sorted[sorted.count - 1].name) : FamilyDimension(planeA: sorted[0].name, planeB: sorted[sorted.count - 1].name)
        edit(eq ? "Add EQ" : "Add Dimension") { $0.dimensions.append(d) }
        selection = .dimension(d.id)
    }

    func addLine(from a: Vec2, to b: Vec2, annotation: Bool) {
        guard view == .plan else { message = "Symbolic lines are drawn in the plan view."; return }
        let l = FamilyEditing.newLine(from: a, to: b)
        edit(annotation ? "Add Annotation Line" : "Add Symbolic Line") { if annotation { $0.annotationLines.append(l) } else { $0.planLines.append(l) } }
        selection = .line(l.id)
    }

    func addArc() {
        let l = FamilyLine(shape: .arc(center: FamilyPoint("0", "0"), radius: "0.1", startDegrees: "0", sweepDegrees: "90"))
        edit("Add Arc") { $0.planLines.append(l) }
        selection = .line(l.id)
    }

    func addLabel(at p: Vec2) {
        guard view == .plan else { message = "Labels are placed in the plan view."; return }
        let param = family.parameters.first { $0.type == .text && !$0.isBuiltIn }?.name ?? family.parameters.first { $0.type == .text }?.name
        let l = FamilyEditing.newLabel(at: p, parameter: param)
        edit("Add Label") { $0.labels.append(l) }
        selection = .label(l.id)
    }

    enum NewForm { case extrusion, blend, revolve, sweep }

    /// Adds a form with a starter shape (blends, revolves and sweeps are edited in the inspector).
    func addForm(_ kind: NewForm, void: Bool) {
        let count = family.solids.count + 1
        let s: FamilySolid
        switch kind {
        case .extrusion:
            s = FamilySolid(name: void ? "Void \(count)" : "Extrusion \(count)",
                            profile: .rectangle(xMin: .expr("-0.1"), xMax: .expr("0.1"), yMin: .expr("-0.1"), yMax: .expr("0.1")), zMin: .expr("0"), zMax: .expr("0.2"), isVoid: void)
        case .blend:
            s = FamilySolid(name: "Blend \(count)", profile: .blend(FamilyBlend(bottom: square(0.2), top: square(0.1))), zMin: .expr("0"), zMax: .expr("0.3"))
        case .revolve:
            s = FamilySolid(name: "Revolve \(count)",
                            profile: .revolve(FamilyRevolve(profile: [FamilyPoint("0", "0"), FamilyPoint("0.15", "0"), FamilyPoint("0.1", "0.3"), FamilyPoint("0", "0.3")])),
                            zMin: .expr("0"), zMax: .expr("0"))
        case .sweep:
            s = FamilySolid(name: "Sweep \(count)",
                            profile: .sweep(FamilySweep(path: [FamilyPoint("-0.5", "0"), FamilyPoint("0.5", "0")],
                                                        profile: [FamilyPoint("-0.025", "0"), FamilyPoint("0.025", "0"), FamilyPoint("0.025", "0.05"), FamilyPoint("-0.025", "0.05")])),
                            zMin: .expr("0"), zMax: .expr("0"))
        }
        edit("Add \(s.profile.formName)") { $0.solids.append(s) }
        selection = .solid(s.id)
    }

    private func square(_ h: Double) -> [FamilyPoint] {
        [FamilyPoint("\(-h)", "\(-h)"), FamilyPoint("\(h)", "\(-h)"), FamilyPoint("\(h)", "\(h)"), FamilyPoint("\(-h)", "\(h)")]
    }

    /// Applies a plane dragged on the canvas: rewrites its offset or the parameter that drives it.
    func movePlane(_ name: String, to value: Double) {
        switch FamilyEditing.planeMove(family, plane: name, to: value, positions: evaluated.planes) {
        case .offset(let text): updatePlane(name) { $0.offset = text }
        case .parameter(let param, let v):
            guard let p = family.parameter(named: param) else { return }
            setRawValue(p, .double(v))
        case .refused(let why): message = why
        }
    }

    func zoomToFit() { fitRequest += 1 }

    // MARK: Values

    /// Display text of a parameter's value in the current type.
    func value(_ p: FamilyParameter) -> String {
        if p.formula != nil, let v = evaluated.values[p.name] { return Parameters.format(FamilyEvaluator.paramValue(v, type: p.type), type: p.type, model: state.model) }
        let raw = family.type(named: currentType)?.values[p.name] ?? p.type.defaultValue
        return Parameters.format(raw, type: p.type, model: state.model)
    }

    func setValue(_ p: FamilyParameter, _ text: String) {
        guard let v = try? Parameters.parse(text, type: p.type, model: state.model) else { message = "“\(text)” isn't a valid \(p.type.displayName.lowercased())."; return }
        setRawValue(p, v)
    }

    func setRawValue(_ p: FamilyParameter, _ v: ParamValue) {
        let t = currentType
        edit("Change \(p.name)") { f in
            if let i = f.types.firstIndex(where: { $0.name == t }) { f.types[i].values[p.name] = v }
        }
    }

    func length(_ meters: Double) -> String { Parameters.format(.double(meters), type: .length, model: state.model) }

    /// Parameters usable as a dimension label (lengths).
    var lengthParameters: [FamilyParameter] { family.parameters.filter { $0.type == .length } }
    /// Yes/No parameters usable as visibility controls.
    var boolParameters: [FamilyParameter] { family.parameters.filter { $0.type == .bool } }
    var materialParameters: [FamilyParameter] { family.parameters.filter { if case .elementRef(.materials) = $0.type { return true }; return false } }
    var textParameters: [FamilyParameter] { family.parameters.filter { $0.type == .text } }

    // MARK: Types and parameters (Family Types dialog)

    func newType(copying: Bool) {
        let base = copying ? currentType : "Type \(family.types.count + 1)"
        let suggested = FamilyEditing.uniqueName(base) { self.family.type(named: $0) != nil }
        guard let name = Self.ask(copying ? "Duplicate Type" : "New Type", "Name", suggested) else { return }
        guard family.type(named: name) == nil else { message = "A type named “\(name)” already exists."; return }
        edit(copying ? "Duplicate Type" : "New Type") { FamilyEditing.addType(&$0, named: name, copying: self.currentType) }
        currentType = name
        if case .type = selection { selection = .type(name) }
    }

    func renameType() {
        let old = currentType
        guard let name = Self.ask("Rename Type", "Name", old), name != old else { return }
        guard family.type(named: name) == nil else { message = "A type named “\(name)” already exists."; return }
        edit("Rename Type") { FamilyEditing.renameType(&$0, old, to: name) }
        currentType = name
        if case .type = selection { selection = .type(name) }
    }

    func deleteType() {
        guard family.types.count > 1 else { message = "A family needs at least one type."; return }
        let n = currentType
        edit("Delete Type") { FamilyEditing.deleteType(&$0, n) }
        currentType = family.types.first?.name ?? ""
        if case .type = selection { selection = .type(currentType) }
    }

    /// Renames a parameter everywhere it is used; false (with a message) when the name is taken or invalid.
    @discardableResult
    func renameParameter(_ old: String, to new: String) -> Bool {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard n != old else { return true }
        guard FamilyEditing.isValidName(n) else { message = "“\(n)” can't be used as a parameter name."; return false }
        guard family.parameter(named: n) == nil else { message = "A parameter named “\(n)” already exists."; return false }
        edit("Rename Parameter") { FamilyEditing.renameParameter(&$0, old, to: n) }
        if selection == .parameter(old) { selection = .parameter(n) }
        return true
    }

    @discardableResult
    func renamePlane(_ old: String, to new: String) -> Bool {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard n != old else { return true }
        guard FamilyEditing.isValidName(n) else { message = "“\(n)” can't be used as a plane name."; return false }
        guard !family.referencePlanes.contains(where: { $0.name == n }) else { message = "A plane named “\(n)” already exists."; return false }
        edit("Rename Reference Plane") { FamilyEditing.renamePlane(&$0, old, to: n) }
        if selection == .plane(old) { selection = .plane(n) }
        return true
    }

    func addParameter(name: String, type: ParamType, instance: Bool, group: ParameterGroup) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard FamilyEditing.isValidName(n) else { message = "“\(n)” can't be used as a parameter name."; return }
        guard family.parameter(named: n) == nil else { message = "A parameter named “\(n)” already exists."; return }
        edit("Add Parameter") { $0.parameters.append(FamilyParameter(name: n, type: type, isInstance: instance, group: group)) }
    }

    func deleteParameter(_ p: FamilyParameter) {
        guard !p.isBuiltIn else { return }
        edit("Delete Parameter") { FamilyEditing.deleteParameter(&$0, p.name) }
        message = "Deleted “\(p.name)”. Formulas that used it are reported by the flex test."
    }

    /// Creates a type length parameter holding the dimension's current distance in every type, and labels the dimension with it.
    func createLabelParameter(for d: FamilyDimension) {
        guard let name = Self.ask("Label with a New Parameter", "A type length parameter is added with the current distance in every type, and drives this dimension.", "", placeholder: "Parameter name") else { return }
        guard FamilyEditing.isValidName(name) else { message = "“\(name)” can't be used as a parameter name."; return }
        guard family.parameter(named: name) == nil else { message = "A parameter named “\(name)” already exists."; return }
        // Each type keeps its own current distance.
        var distances: [String: Double] = [:]
        for t in family.types {
            let ev = FamilyEvaluator.evaluate(family, typeName: t.name, units: units)
            if let a = ev.planes[d.planeA], let b = ev.planes[d.planeB] { distances[t.name] = abs(b - a) }
        }
        let planes = evaluated.planes
        edit("Label Dimension") { f in
            f.parameters.append(FamilyParameter(name: name, type: .length))
            for i in f.types.indices { f.types[i].values[name] = .double(distances[f.types[i].name] ?? 0) }
            if let i = f.dimensions.firstIndex(where: { $0.id == d.id }) {
                let before = f.dimensions[i]
                f.dimensions[i].labelParameter = name; f.dimensions[i].isLocked = false
                f.dimensions[i].fixLabelDirection(planes, after: before) // BL-SITE
            }
        }
    }

    /// A small modal prompt for a name.
    static func ask(_ title: String, _ label: String, _ initial: String, placeholder: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = label
        let field = NSTextField(string: initial)
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK"); alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let v = field.stringValue.trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    // MARK: Flex, save, load

    func flex() {
        flexResults = FamilyEvaluator.flexTest(family, units: units)
    }

    func saveToDisk() {
        flex()
        if let r = flexResults, !r.isEmpty {
            let alert = NSAlert()
            alert.messageText = "The flex test found \(r.count) problem(s)."
            alert.informativeText = r.prefix(6).joined(separator: "\n")
            alert.addButton(withTitle: "Save Anyway"); alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.arcusFamily]
        panel.nameFieldStringValue = family.name + ".arcusfamily"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let v = AppVersionInfo.current
            try FamilyPackage.write(family, thumbnailPNG: nil, to: url, appVersion: v.marketingVersion, build: v.build)
            message = "Saved \(url.lastPathComponent)."
        } catch { message = "Save failed: \(error.localizedDescription)" }
    }

    /// Attaches the window to the project family a first Load into Project created (F1415: `loadIntoProject` lives in
    /// FamilyEditor+F1415.swift with Load into Project and Close).
    func attach(_ id: ElementID?) {
        familyID = id
        onRename?(family.name)
    }
}

/// Loads families and type catalogs from disk.
@MainActor
struct FamilyLoader {
    let state: DocumentState

    /// Asks what to do with project type values when a family already in the project is loaded again (nil = cancel).
    static func askReloadMode(_ name: String) -> FamilyReloadMode? {
        let alert = NSAlert()
        alert.messageText = "“\(name)” is already in this project."
        alert.informativeText = "Its geometry and parameters will be replaced by this version. Types that exist in both can keep the values set in this project, or take the values stored in the family."
        alert.addButton(withTitle: "Keep Project Values")
        alert.addButton(withTitle: "Use Family Values")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepProjectValues
        case .alertSecondButtonReturn: return .overwriteValues
        default: return nil
        }
    }

    func load(_ family: FamilyDefinition, replacing existing: ElementID?, mode: FamilyReloadMode = .keepProjectValues) {
        let problems = FamilyEvaluator.flexTest(family, units: state.model.units)
        if !problems.isEmpty { state.show("“\(family.name)” has \(problems.count) flex-test problem(s): \(problems.first!)", error: true) }
        state.session.perform(existing == nil ? "Load Family" : "Reload Family") { tx in
            FamilyProjectLoader.load(family, replacing: existing, mode: mode, in: tx)
        }
    }

    func loadFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.arcusFamily]
        panel.allowsMultipleSelection = true
        panel.message = "Choose Arcus family files (.arcusfamily). RFA families come in through the Arcus Bridge export (Insert ▸ Import Revit Model)."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                let (fam, _, _) = try FamilyPackage.read(from: url)
                let existing = state.model.family(named: fam.name)?.id
                var mode = FamilyReloadMode.keepProjectValues
                if existing != nil {
                    guard let m = Self.askReloadMode(fam.name) else { continue }
                    mode = m
                }
                load(fam, replacing: existing, mode: mode)
            } catch {
                state.show("Couldn't load \(url.lastPathComponent): \(error.localizedDescription)", error: true)
            }
        }
    }

    func selectedFamilyID() -> ElementID? {
        for id in state.session.selection.ids {
            guard let e = state.model[id] else { continue }
            if e.family != nil { return id }
            if let f = (e.typeData ?? state.model.typeData(of: e))?.familyID { return f }
        }
        return nil
    }

    func reloadSelected() {
        guard let fid = selectedFamilyID(), let name = state.model[fid]?.name else { state.show("Select a family instance or type to reload.", error: true); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.arcusFamily]
        panel.message = "Choose the file to reload “\(name)” from."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let (fam, _, _) = try FamilyPackage.read(from: url)
            guard let mode = Self.askReloadMode(name) else { return }
            load(fam, replacing: fid, mode: mode)
        } catch { state.show("Couldn't reload: \(error.localizedDescription)", error: true) }
    }

    func loadTypeCatalog() {
        guard let fid = selectedFamilyID(), let fam = state.model[fid]?.family else { state.show("Select an instance or type of the family the catalog belongs to.", error: true); return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        do {
            let (types, errors) = try TypeCatalog.parse(data, family: fam)
            var updated = fam
            for t in types where updated.type(named: t.name) == nil { updated.types.append(t) }
            load(updated, replacing: fid)
            state.show("Loaded \(types.count) type(s)" + (errors.isEmpty ? "." : "; \(errors.count) row(s) had problems: \(errors.first!)"), error: !errors.isEmpty)
        } catch { state.show("Couldn't read the catalog: \(error.localizedDescription)", error: true) }
    }
}

/// Text field that commits on Return or when it loses focus, and follows external changes (undo, type switch) while not being edited.
struct ValueField: View {
    let value: String
    var placeholder: String = ""
    let commit: (String) -> Void
    @State private var text: String
    @FocusState private var focused: Bool

    init(text: String, placeholder: String = "", commit: @escaping (String) -> Void) {
        value = text
        self.placeholder = placeholder
        self.commit = commit
        _text = State(initialValue: text)
    }
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { if text != value { commit(text) } }
            .onChange(of: value) { _, v in if !focused { text = v } }
            .onChange(of: focused) { _, isFocused in if !isFocused && text != value { commit(text) } }
    }
}

/// A (x, y) field pair for a family point: each coordinate is a reference-plane name (locks to the plane) or a formula.
struct FamilyPointField: View {
    let model: FamilyEditorModel
    let point: FamilyPoint
    var labels: (String, String) = ("x", "y")
    let set: (FamilyPoint) -> Void
    var body: some View {
        HStack(spacing: 4) {
            FamilyBoundField(model: model, label: labels.0, bound: point.x) { set(FamilyPoint($0, point.y)) }
            FamilyBoundField(model: model, label: labels.1, bound: point.y) { set(FamilyPoint(point.x, $0)) }
        }
    }
}

/// A bound field: typing a reference-plane name locks to that plane (shown with a lock), anything else is a formula.
struct FamilyBoundField: View {
    let model: FamilyEditorModel
    let label: String
    let bound: FamilyBound
    let set: (FamilyBound) -> Void
    var body: some View {
        HStack(spacing: 3) {
            if !label.isEmpty { Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            if case .plane = bound { Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(.green).help("Locked to a reference plane") }
            ValueField(text: Self.text(bound)) { text in
                let t = text.trimmingCharacters(in: .whitespaces)
                guard !t.isEmpty else { return }
                set(model.family.referencePlanes.contains { $0.name == t } ? .plane(t) : .expr(t))
            }
            .font(.caption.monospaced())
            .frame(minWidth: 44)
        }
    }
    static func text(_ b: FamilyBound) -> String { switch b { case .plane(let n): n; case .expr(let e): e } }
}

/// Editable list of family points (a path or a closed loop).
struct FamilyPointListEditor: View {
    let model: FamilyEditorModel
    let title: String
    let points: [FamilyPoint]
    var labels: (String, String) = ("x", "y")
    var minimum = 3
    let set: ([FamilyPoint]) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Button {
                    var p = points
                    let last = p.last ?? FamilyPoint("0", "0")
                    p.append(FamilyPoint(last.x, last.y))
                    set(p)
                } label: { Image(systemName: "plus") }.buttonStyle(.borderless).help("Add a point")
            }
            ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                HStack(spacing: 4) {
                    Text("\(i + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 16, alignment: .trailing)
                    FamilyPointField(model: model, point: p, labels: labels) { np in var ps = points; ps[i] = np; set(ps) }
                    Button { var ps = points; ps.remove(at: i); set(ps) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).disabled(points.count <= minimum).help("Remove this point")
                }
            }
        }
    }
}

/// Detail-level checkboxes plus a Yes/No parameter controlling visibility.
struct FamilyVisibilityControls: View {
    let model: FamilyEditorModel
    let visibleAt: Set<DetailLevel>
    let parameter: String?
    let setLevels: (Set<DetailLevel>) -> Void
    let setParameter: (String?) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                ForEach(DetailLevel.allCases, id: \.self) { d in
                    Toggle(d.rawValue, isOn: Binding(get: { visibleAt.contains(d) }, set: { on in
                        var s = visibleAt
                        if on { s.insert(d) } else { s.remove(d) }
                        setLevels(s)
                    }))
                    .toggleStyle(.checkbox).font(.caption)
                }
            }
            Picker("Visible", selection: Binding(get: { parameter ?? "" }, set: { setParameter($0.isEmpty ? nil : $0) })) {
                Text("Always").tag("")
                ForEach(model.boolParameters) { Text($0.name).tag($0.name) }
            }
            .font(.caption)
            .help("A Yes/No parameter that shows or hides this item.")
        }
    }
}
