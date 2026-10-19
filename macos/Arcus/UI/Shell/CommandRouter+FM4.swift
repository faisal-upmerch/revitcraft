import AppKit
import ArcusDomain
import ArcusApplication

// FM4: routing for Furniture parts and forms (Docs/FurnitureMode.md §6). Every FM4 command works only in Furniture
// documents; each tool says which views it draws in, as Revit's tools do.

extension CommandRouter {
    static let fm4IDs: Set<CommandID> = [
        .furniturePanel, .furnitureShelf, .furnitureTop, .furnitureBack, .furnitureDivider, .furnitureLeg, .furnitureLegsAtCorners, .furnitureRail,
        .furnitureSlats, .furniturePlinth, .furnitureEdgeProfile, .furnitureGroove, .furnitureEditProfile, .furnitureResetProfile, .furnitureAttach,
        .furnitureDetach, .furniturePanelOpening, .furnitureFlipPanel, .furnitureExtrusion, .furnitureBlend, .furnitureRevolve, .furnitureSweep,
        .furnitureSweptBlend, .furnitureCushion, .furnitureVoidExtrusion, .furnitureVoidBlend, .furnitureVoidRevolve, .furnitureVoidSweep, .furnitureVoidSweptBlend,
    ]

    var fm4Map: FurnitureSketchMap? { FurnitureSketchMap.of(model[state.editingViewID]?.view) }
    var fm4Selected: [Element] { selection.compactMap { model[$0] }.filter { $0.category.isFurniturePart } }
    var fm4SelectedPanels: [Element] { fm4Selected.filter { $0.furniturePanel != nil } }

    /// Why one of this batch's commands can't run now, or nil.
    func fm4DisabledReason(_ id: CommandID) -> String? {
        guard Self.fm4IDs.contains(id) else {
            // Edit Boundary of a shelf, top or bottom works in plans.
            if id == .editBoundary, selection.count == 1, model[selection[0]]?.furnitureShelf != nil, !isPlan { return "Edit a shelf's boundary in a plan view." }
            return nil
        }
        guard state.mode == .furniture else { return "Only in Furniture documents." }
        let map = fm4Map
        let plan = map?.plane == .xy, front = map?.plane == .xz
        switch id {
        case .furniturePanel, .furnitureRail, .furnitureEdgeProfile, .furnitureGroove, .furnitureExtrusion, .furnitureVoidExtrusion:
            return map == nil ? "Open a plan, or an elevation or section square to the piece." : nil
        case .furnitureShelf, .furnitureTop, .furnitureLeg, .furnitureLegsAtCorners, .furnitureSlats, .furnitureBlend, .furnitureVoidBlend,
             .furnitureSweep, .furnitureVoidSweep, .furnitureSweptBlend, .furnitureVoidSweptBlend, .furnitureCushion:
            return plan ? nil : "Open a plan view to use this tool."
        case .furnitureBack, .furnitureDivider:
            return front ? nil : "Open the Front or Back elevation (or a section parallel to it)."
        case .furnitureRevolve, .furnitureVoidRevolve:
            return map != nil && !plan ? nil : "Sketch a revolve in an elevation or section."
        case .furniturePlinth:
            return map == nil ? "Open a plan or an elevation." : nil
        case .furnitureEditProfile:
            guard fm4SelectedPanels.count == 1, selection.count == 1 else { return "Select one panel." }
            guard let p = fm4SelectedPanels[0].furniturePanel, p.plane == .xy, let map, map.plane != .xy,
                  let f = FurniturePartSolids.linearFrame(p.plane, p.start, p.end), FamilySketchPlane.normal(f.crossAxis) == map.plane else {
                return "Open an elevation that sees the panel's face."
            }
            return nil
        case .furnitureResetProfile:
            return fm4SelectedPanels.contains { $0.furniturePanel?.profile != nil || $0.furniturePanel?.openings?.isEmpty == false } ? nil : "Select a panel with an edited profile or openings."
        case .furnitureAttach:
            return fm4Selected.contains { $0.furniturePanel?.plane == .xy || $0.furnitureLeg != nil } ? nil : "Select panels drawn in plan, or legs."
        case .furnitureDetach:
            return fm4Selected.contains { $0.furniturePanel?.attachedTopID != nil || $0.furniturePanel?.attachedBaseID != nil || $0.furnitureLeg?.attachedTopID != nil }
                ? nil : "Select attached panels or legs."
        case .furniturePanelOpening:
            return map != nil && !plan ? nil : "Open an elevation that sees the panel's face."
        case .furnitureFlipPanel:
            return fm4SelectedPanels.isEmpty ? "Select panels." : nil
        default:
            return nil
        }
    }

    /// The type a tool starts with when the Type Selector has none (3/4" Plywood, not the alphabetical first), and the
    /// standard part types in documents made before they existed.
    func fm4PrepareTypes(_ cat: Category, family: String? = nil, _ c: ToolContext) {
        if model.types(for: cat).isEmpty { session.perform("Load Standard Part Types") { tx in FurniturePartTypes.ensureStandard(in: tx) } }
        if let t = state.currentTypes[cat], model[t]?.typeData?.instanceCategory == cat, family == nil || model[t]?.typeData?.familyName == family { c.currentTypes[cat] = t; return }
        if let t = FurniturePartTypes.firstType(cat, family: family, model) { state.currentTypes[cat] = t; c.currentTypes[cat] = t }
    }

    /// The interactive tool for one of this batch's commands, or nil.
    func fm4MakeTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        if id == .editBoundary, selection.count == 1, let e = model[selection[0]], let s = e.furnitureShelf {
            return SketchTool.furniture(c, .shelf(s.role), commandID: .editBoundary, editing: e.id)
        }
        guard Self.fm4IDs.contains(id) else { return nil }
        switch id {
        case .furniturePanel: fm4PrepareTypes(.furniturePanels, family: "Panel", c); return FurniturePanelTool(ctx: c)
        case .furnitureShelf: fm4PrepareTypes(.furnitureShelves, family: "Shelf", c); return SketchTool.furniture(c, .shelf(.shelf), commandID: id)
        case .furnitureTop: fm4PrepareTypes(.furnitureShelves, family: "Top", c); return SketchTool.furniture(c, .shelf(.top), commandID: id)
        case .furnitureBack: fm4PrepareTypes(.furniturePanels, c); return FurnitureBackTool(ctx: c)
        case .furnitureDivider: fm4PrepareTypes(.furniturePanels, family: "Panel", c); return FurnitureDividerTool(ctx: c)
        case .furnitureLeg: fm4PrepareTypes(.furnitureLegs, c); return FurnitureLegTool(ctx: c)
        case .furnitureLegsAtCorners: fm4PrepareTypes(.furnitureLegs, c); return FurnitureLegTool(ctx: c, atCorners: true)
        case .furnitureRail: fm4PrepareTypes(.furnitureRails, c); return FurnitureRailTool(ctx: c)
        case .furnitureSlats:
            fm4PrepareTypes(.furnitureRails, c)
            // Slats start on a slat type, unless one was chosen.
            if let t = state.currentTypes[.furnitureRails], model[t]?.name.contains("Slat") != true,
               let slat = model.types(for: .furnitureRails).first(where: { $0.name.contains("Slat") }) {
                state.currentTypes[.furnitureRails] = slat.id; c.currentTypes[.furnitureRails] = slat.id
            }
            return FurnitureSlatsTool(ctx: c)
        case .furniturePlinth: fm4PrepareTypes(.furniturePanels, family: "Panel", c); return FurniturePlinthTool(ctx: c)
        case .furnitureEdgeProfile: fm4PrepareTypes(.furnitureEdgeProfiles, family: "Edge Profile", c); return FurnitureEdgeProfileTool(ctx: c, groove: false)
        case .furnitureGroove:
            fm4PrepareTypes(.furnitureEdgeProfiles, family: FurniturePartTypes.grooveFamily, c)
            return FurnitureEdgeProfileTool(ctx: c, groove: true)
        case .furnitureEditProfile:
            guard let p = fm4SelectedPanels.first else { return nil }
            return SketchTool.furniture(c, .panelProfile(p.id), commandID: id)
        case .furnitureAttach: return FurnitureAttachTool(ctx: c, ids: fm4Selected.map(\.id))
        case .furniturePanelOpening: return FurniturePanelOpeningTool(ctx: c, panel: fm4SelectedPanels.count == 1 ? fm4SelectedPanels[0].id : nil)
        case .furnitureExtrusion: return SketchTool.furniture(c, .form(.extrusion, isVoid: false), commandID: id)
        case .furnitureBlend: return SketchTool.furniture(c, .form(.blend, isVoid: false), commandID: id)
        case .furnitureRevolve: return SketchTool.furniture(c, .form(.revolve, isVoid: false), commandID: id)
        case .furnitureSweep: return SketchTool.furniture(c, .form(.sweep, isVoid: false), commandID: id)
        case .furnitureSweptBlend: return SketchTool.furniture(c, .form(.sweptBlend, isVoid: false), commandID: id)
        case .furnitureVoidExtrusion: return SketchTool.furniture(c, .form(.extrusion, isVoid: true), commandID: id)
        case .furnitureVoidBlend: return SketchTool.furniture(c, .form(.blend, isVoid: true), commandID: id)
        case .furnitureVoidRevolve: return SketchTool.furniture(c, .form(.revolve, isVoid: true), commandID: id)
        case .furnitureVoidSweep: return SketchTool.furniture(c, .form(.sweep, isVoid: true), commandID: id)
        case .furnitureVoidSweptBlend: return SketchTool.furniture(c, .form(.sweptBlend, isVoid: true), commandID: id)
        case .furnitureCushion: return FurnitureCushionTool(ctx: c)
        default: return nil
        }
    }

    /// Runs one of this batch's commands; true when handled.
    func fm4Perform(_ id: CommandID) -> Bool {
        let panels = fm4SelectedPanels.map(\.id)
        switch id {
        case .furnitureResetProfile:
            session.perform("Reset Profile") { tx in
                for p in panels { tx.update(p) { $0.furniturePanel?.profile = nil; $0.furniturePanel?.openings = nil } }
            }
        case .furnitureDetach:
            let ids = fm4Selected.map(\.id)
            session.perform("Detach Top/Base") { tx in FurniturePartOperations.detach(ids, in: tx) }
        case .furnitureFlipPanel:
            session.perform("Flip Panel") { tx in for p in panels { tx.update(p) { $0.furniturePanel?.flipped.toggle() } } }
        default:
            return false
        }
        if let e = session.lastError { state.show(e.message, error: true) }
        return true
    }
}

/// FM4: the part category a tool's Type Selector shows.
func fm4PropertiesCategory(_ cmd: CommandID) -> Category? {
    switch cmd {
    case .furniturePanel, .furnitureBack, .furnitureDivider, .furniturePlinth: .furniturePanels
    case .furnitureShelf, .furnitureTop: .furnitureShelves
    case .furnitureLeg, .furnitureLegsAtCorners: .furnitureLegs
    case .furnitureRail, .furnitureSlats: .furnitureRails
    case .furnitureEdgeProfile, .furnitureGroove: .furnitureEdgeProfiles
    default: nil
    }
}
