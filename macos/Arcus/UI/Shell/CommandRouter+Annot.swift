import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// W2-ANNOT: availability, tools and actions of the Annotate tab additions.
extension CommandRouter {
    static let annotCommands: Set<CommandID> = [
        .repeatingDetailComponent, .legendComponent, .detailGroupPlace, .detailGroupCreate, .checkSpelling, .findReplace, .multiCategoryTag,
        .materialTag, .areaTag, .viewReference, .keynoteElement, .keynoteMaterial, .keynoteUser, .treadNumber, .beamAnnotations, .scaleBar,
        .spanDirection, .stairPath, .addTextLeader, .removeTextLeader,
    ]

    func annotDisabledReason(_ id: CommandID) -> String? {
        guard Self.annotCommands.contains(id) else { return nil }
        let kind = viewKind
        let is2D = kind.map { $0 != .threeD } ?? isSheet
        let sel = selection.compactMap { model[$0] }
        switch id {
        case .findReplace:
            return nil
        case .addTextLeader:
            return sel.contains { $0.textNote != nil } ? nil : "Select text notes."
        case .removeTextLeader:
            return sel.contains { !($0.textNote?.leaders.isEmpty ?? true) } ? nil : "Select text notes with leaders."
        case .detailGroupCreate:
            return DetailGroups.members(selection, model).isEmpty ? "Select detail lines, regions, components or text in one view." : nil
        default: break
        }
        guard is2D && !isSchedule else { return "Annotations are added in 2D views and sheets." }
        switch id {
        case .checkSpelling:
            return nil
        case .legendComponent:
            return kind == .legend || kind == .drafting ? nil : "Open a legend view (View ▸ Legend) to place legend components."
        case .treadNumber, .stairPath:
            guard isPlan else { return "Open a plan view to use this tool." }
            return model.elements(.stairs).isEmpty ? "The project has no stairs yet." : nil
        case .spanDirection:
            guard isPlan else { return "Open a plan view to use this tool." }
            return model.elements(.floors).isEmpty ? "The project has no floors yet." : nil
        case .beamAnnotations:
            return model.elements(.structuralFraming).isEmpty ? "The project has no beams yet." : nil
        case .detailGroupPlace:
            return DetailGroups.typeNames(model).isEmpty ? "Create a detail group first (select detail items, then Create Detail Group)." : nil
        case .areaTag:
            return kind == .areaPlan ? nil : "Areas are tagged in area plans (View ▸ Area Plan)."
        case .viewReference:
            return model.views.contains { $0.id != state.editingViewID && ($0.view?.kind.isPlan == true || $0.view?.kind.isVerticalCut == true) } ? nil : "Create another view to reference first."
        case .scaleBar:
            return isSheet ? "Place scale bars in views: they show the view's scale." : nil
        case .materialTag, .keynoteElement, .keynoteMaterial, .keynoteUser, .multiCategoryTag:
            return isPlan || (kind?.isVerticalCut ?? false) ? nil : "Tags are placed in plans, sections and elevations."
        case .repeatingDetailComponent:
            return model.types(for: .detailComponents).isEmpty ? "Load a detail component family first." : nil
        default:
            return nil
        }
    }

    /// The tool for an Annotate tab addition (nil for actions and other commands).
    func annotMakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        switch id {
        case .repeatingDetailComponent: return RepeatingDetailTool(ctx: c)
        case .legendComponent: return LegendComponentTool(ctx: c)
        case .detailGroupPlace: return DetailGroupTool(ctx: c)
        case .multiCategoryTag: return TagTool(ctx: c, commandID: .multiCategoryTag)
        case .areaTag: return TagTool(ctx: c, commandID: .areaTag, categories: [.areas])
        case .materialTag: return SpecialTagTool(ctx: c, kind: .material)
        case .keynoteElement: return SpecialTagTool(ctx: c, kind: .keynoteElement)
        case .keynoteMaterial: return SpecialTagTool(ctx: c, kind: .keynoteMaterial)
        case .keynoteUser: return SpecialTagTool(ctx: c, kind: .keynoteUser)
        case .treadNumber: return SpecialTagTool(ctx: c, kind: .treadNumber)
        case .viewReference: return SpecialTagTool(ctx: c, kind: .viewReference)
        case .spanDirection: return SpecialTagTool(ctx: c, kind: .spanDirection)
        case .stairPath: return SpecialTagTool(ctx: c, kind: .stairPath)
        case .scaleBar: return SpecialTagTool(ctx: c, kind: .scaleBar)
        default: return nil
        }
    }

    /// Runs Annotate actions. Returns false for other commands.
    func performAnnot(_ id: CommandID) -> Bool {
        let actions: Set<CommandID> = [.detailGroupCreate, .checkSpelling, .findReplace, .beamAnnotations, .addTextLeader, .removeTextLeader]
        guard actions.contains(id) else { return false }
        let sel = selection
        switch id {
        case .detailGroupCreate:
            var created: ElementID?
            let scale = model[state.editingViewID]?.view?.scale ?? 1
            session.perform("Create Detail Group") { tx in created = try DetailGroups.create(sel, scale: scale, in: tx) }
            if let e = session.lastError { state.show(e.message, error: true); session.clearError() }
            else if let g = created { session.selection.select([g]); state.show("Created “\(model[g]?.name ?? "")”. Place copies with Detail Group ▸ Place Detail Group.") }
        case .checkSpelling:
            if let v = state.editingViewID { state.presented = .checkSpelling(v) }
        case .findReplace:
            state.presented = .findReplace(state.editingViewID ?? state.activeViewID ?? ElementID(0))
        case .beamAnnotations:
            guard let v = state.editingViewID, let g = state.graphics.graphics(v) else { return true }
            let visible = Set(g.items.compactMap(\.elementID))
            var n = 0
            session.perform("Beam Annotations") { tx in n = BeamAnnotations.run(view: v, visible: visible, in: tx) }
            if let e = session.lastError { state.show(e.message, error: true) }
            else { state.show(n == 0 ? "Every visible beam is already tagged (or no beam tag family is loaded)." : "Tagged \(n) beam\(n == 1 ? "" : "s").") }
        case .addTextLeader, .removeTextLeader:
            let notes = sel.filter { model[$0]?.textNote != nil }
            session.perform(id == .addTextLeader ? "Add Leader" : "Remove Leader") { tx in
                for n in notes { if id == .addTextLeader { TextLeaders.add(to: n, in: tx) } else { TextLeaders.removeLast(from: n, in: tx) } }
            }
        default:
            break
        }
        return true
    }

    /// Double-click on a text note edits it in place.
    func editTextNoteInPlace(_ e: Element) { state.editTextNote(e) }
}

extension RibbonContent {
    /// W2-ANNOT: contextual items for selected annotations.
    static func annotSelectionItems(_ sel: [Element], _ m: BIMModel) -> (title: String?, items: [RibbonItem]) {
        var items: [RibbonItem] = []
        var title: String?
        if sel.contains(where: { $0.textNote != nil }) {
            title = "Text"
            items += [.small(.addTextLeader), .small(.removeTextLeader), .small(.checkSpelling)]
        }
        if !DetailGroups.members(sel.map(\.id), m).isEmpty && !sel.contains(where: { $0.group != nil }) {
            items.append(.small(.detailGroupCreate))
        }
        return (title, items)
    }
}

extension MainMenuBuilder {
    /// W2-ANNOT: Annotate menu items for the tab additions.
    static func annotMenuAdditions() -> [NSMenuItem] {
        commands([nil, .repeatingDetailComponent, .legendComponent, .detailGroupPlace, .detailGroupCreate, nil,
                  .checkSpelling, .findReplace, .addTextLeader, .removeTextLeader, nil,
                  .multiCategoryTag, .materialTag, .areaTag, .viewReference, .keynoteElement, .keynoteMaterial, .keynoteUser,
                  .treadNumber, .beamAnnotations, nil, .scaleBar, .spanDirection, .stairPath])
    }
}
