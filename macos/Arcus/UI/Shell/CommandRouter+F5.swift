import AppKit
import ArcusDomain
import ArcusApplication

// F5: Analyze and Massing: spaces and zones, masses, model by face, model in-place. Docs/RevitCraftPort.md §5.

extension CommandRouter {
    static let f5ByFace: [CommandID: ModelByFaceKind] = [.wallByFace: .wall, .curtainSystemByFace: .curtainSystem, .floorByFace: .floor, .roofByFace: .roof]

    /// Selected masses (Model by Face then builds on all their faces at once, as RevitCraft does).
    var f5SelectedMasses: [ElementID] { selection.filter { model[$0]?.category == .mass } }

    /// The tool for one of this batch's commands, or nil.
    func f5MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .space:
            return SpaceTool(ctx: c)
        case .spaceSeparator:
            return LineTool(ctx: c, kind: .spaceSeparation, commandID: .spaceSeparator)
        case .spaceTag:
            // The tag family loads first so the hover preview shows the tag.
            if !model.elements(.families).contains(where: { $0.name == SpaceTags.familyName }) {
                session.perform("Load \(SpaceTags.familyName)") { tx in SpaceTags.ensure(in: tx) }
            }
            return TagTool(ctx: c, commandID: .spaceTag, categories: [.spaces])
        case .inPlaceMass:
            if !session.showMass { f5SetShowMass(true) } // RevitCraft turns Show Mass on to sketch a mass
            let t = SketchTool(ctx: c, target: .f5(.mass), commandID: .inPlaceMass)
            t.drawMode = .rectangle // RevitCraft starts the mass sketch with a rectangle
            return t
        case .editBoundary:
            // A mass edits its footprint in sketch mode.
            guard selection.count == 1, let id = selection.first, model[id]?.mass != nil else { return nil }
            let t = SketchTool(ctx: c, target: .f5(.mass), commandID: .editBoundary, editing: id)
            t.drawMode = .line
            return t
        case .wallByFace, .curtainSystemByFace, .floorByFace, .roofByFace:
            guard f5SelectedMasses.isEmpty, let kind = Self.f5ByFace[id] else { return nil } // with masses selected: f5Perform
            return ModelByFaceTool(ctx: c, kind: kind, typeID: f5ByFaceType(kind))
        default:
            return nil
        }
    }

    /// Runs one of this batch's commands that has no tool; true when handled.
    func f5Perform(_ id: CommandID) -> Bool {
        switch id {
        case .showMass:
            f5SetShowMass(!session.showMass)
            state.show(session.showMass ? "Masses are shown in every view." : "Masses are hidden in every view.")
        case .modelInPlace:
            state.presented = .f5(.modelInPlace)
        case .wallByFace, .curtainSystemByFace, .floorByFace, .roofByFace:
            let masses = f5SelectedMasses
            guard let kind = Self.f5ByFace[id] else { return false }
            guard !masses.isEmpty else { state.show("Select a mass first, then choose a Model by Face tool.", error: true); return true }
            let type = f5ByFaceType(kind)
            var made: [ElementID] = []
            session.perform(CommandCatalog.info(id).title) { tx in
                for m in masses { made += try ModelByFace.create(kind, mass: m, typeID: type, in: tx) }
            }
            if let e = session.lastError { state.show(e.message, error: true); return true }
            session.selection.select(made)
        default:
            return false
        }
        return true
    }

    /// Why one of this batch's commands can't run now, or nil.
    func f5DisabledReason(_ id: CommandID) -> String? {
        switch id {
        case .space, .spaceSeparator:
            return isPlan ? nil : "Open a plan view to use this tool."
        case .spaceTag:
            guard isPlan else { return "Open a plan view to tag spaces." }
            return model.elements(.spaces).isEmpty ? "The project has no spaces yet. Place them with Analyze ▸ Space." : nil
        case .inPlaceMass:
            return isPlan ? nil : "Open a plan view to sketch the mass footprint."
        case .wallByFace, .curtainSystemByFace, .floorByFace, .roofByFace:
            if model.elements(.mass).isEmpty { return "The project has no masses. Create one with In-Place Mass first." }
            if !f5SelectedMasses.isEmpty { return nil }
            return isPlan || viewKind == .threeD ? nil : "Select a mass, or open a plan or 3D view to pick its faces."
        case .modelInPlace:
            return model.levels.isEmpty ? "The project has no levels." : nil
        default:
            return nil
        }
    }

    /// The type Model by Face gives new elements: the type selector's current type, curtain wall types for curtain
    /// systems (added when the project has none).
    func f5ByFaceType(_ kind: ModelByFaceKind) -> ElementID? {
        switch kind {
        case .wall:
            let t = state.currentTypes[.walls].flatMap { model[$0]?.typeData?.curtain == nil ? $0 : nil }
            return t ?? model.types(for: .walls).first { $0.typeData?.curtain == nil }?.id
        case .curtainSystem:
            if !model.types(for: .walls).contains(where: { $0.typeData?.curtain != nil }) {
                session.perform("Add Curtain Wall Types") { tx in CurtainWallDefaults.populate(tx) }
            }
            let curtain = model.types(for: .walls).filter { $0.typeData?.curtain != nil }
            return state.currentTypes[.walls].flatMap { id in curtain.first { $0.id == id }?.id } ?? curtain.first { $0.name == "Storefront" }?.id ?? curtain.first?.id
        case .floor:
            return state.currentTypes[.floors].flatMap { model[$0]?.typeData != nil ? $0 : nil } ?? model.types(for: .floors).first?.id
        case .roof:
            return state.currentTypes[.roofs].flatMap { model[$0]?.typeData != nil ? $0 : nil } ?? model.types(for: .roofs).first?.id
        }
    }

    /// Double-click on an in-place family's instance: edit the family in place (the Family Editor). False otherwise.
    func f5EditInPlace(_ e: Element) -> Bool {
        guard e.component != nil || e.column != nil, let fid = model.typeData(of: e)?.familyID, InPlaceFamilies.isInPlace(model[fid]) else { return false }
        FamilyEditorWindowController.open(familyID: fid, state: state)
        return true
    }

    /// Show Mass: masses show or hide in every open view (plans, sections, elevations, 3D).
    func f5SetShowMass(_ on: Bool) {
        session.showMass = on
        for v in model.views { state.graphics.invalidateView(v.id) }
        for c in state.canvases.values { (c as? Viewport3DHost)?.rebuild() }
        state.toolChangedState()
    }
}

/// Model In-place after its dialog: the new family opens in the Family Editor; its first Load into Project places the
/// single instance at the project origin on the level (RevitCraft family_editor.rs `load`). Later loads reload it.
@MainActor
final class InPlaceFamilyFlow {
    private static var active: [InPlaceFamilyFlow] = []
    private weak var session: DocumentSession?
    private let name: String
    private let level: ElementID?
    private var token: UUID?

    private init(session: DocumentSession, name: String, level: ElementID?) {
        self.session = session; self.name = name; self.level = level
    }

    static func begin(state: DocumentState, template: FamilyTemplate, name: String) {
        let unique = InPlaceFamilies.uniqueName(name, state.model)
        let level = state.model[state.editingViewID]?.levelID ?? state.model.levels.first?.id
        let flow = InPlaceFamilyFlow(session: state.session, name: unique, level: level)
        flow.token = state.session.onChange { [weak flow] _ in flow?.check() }
        active.append(flow)
        FamilyEditorWindowController.open(new: InPlaceFamilies.definition(name: unique, template: template), state: state)
        state.show("Model the in-place family “\(unique)”, then Load into Project to place it.")
    }

    /// When the family has been loaded, places its instance (after the loading transaction has finished).
    private func check() {
        guard let session, let fam = session.model.family(named: name), InPlaceFamilies.instances(of: fam.id, session.model).isEmpty else { return }
        stop()
        let fid = fam.id, level = level
        DispatchQueue.main.async {
            var placed: ElementID?
            session.perform("Model In-place") { tx in placed = try InPlaceFamilies.place(familyID: fid, level: level, in: tx) }
            if let placed { session.selection.select([placed]) }
        }
    }

    private func stop() {
        if let token { session?.removeChangeHandler(token) }
        token = nil
        Self.active.removeAll { $0 === self }
    }
}
