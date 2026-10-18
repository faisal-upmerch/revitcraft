import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// W2-DWG: Massing & Site commands and hosted profiles (wall sweep, slab edge, soffit).
extension CommandRouter {
    static let siteCommands: Set<CommandID> = [.siteSettings, .toposurfaceFromFile, .toposurfaceFromImport, .subregion, .splitSurface, .mergeSurfaces,
                                               .gradedRegion, .editSurface, .labelContours, .siteComponent, .parkingComponent, .parkingLayout,
                                               .wallSweep, .slabEdge, .roofSoffit,
                                               .toposolid, .toposolidFromFile, .toposolidFromImport, .generateToposolid, .subdivideToposolid,
                                               .simplifySurface, .excavateToposolid] // BL-SITE

    private var selectedSurfaces: [Element] {
        selection.compactMap { model[$0] }.filter { $0.topography != nil && $0.topography?.boundary == nil }
    }

    func siteDisabledReason(_ id: CommandID) -> String? {
        let sel = selection.compactMap { model[$0] }
        switch id {
        case .subregion, .splitSurface, .parkingLayout, .siteComponent, .parkingComponent, .toposolid:
            return isPlan ? nil : "Open a plan view to use this tool."
        case .toposolidFromImport, .generateToposolid, .subdivideToposolid, .simplifySurface, .excavateToposolid: // BL-SITE
            return toposolidDisabledReason(id)
        case .labelContours:
            return isPlan ? (model.elements(.topography).isEmpty ? "The project has no toposurface." : nil) : "Open a plan view to label contours."
        case .mergeSurfaces:
            return selectedSurfaces.count >= 2 ? nil : "Select two or more toposurfaces."
        case .gradedRegion, .editSurface:
            return selectedSurfaces.count == 1 && isPlan ? nil : "Select one toposurface in a plan view."
        case .toposurfaceFromImport:
            return sel.count == 1 && (sel[0].link?.format == .dxf || sel[0].link?.format == .dwg) ? nil : "Select one linked or imported DXF or DWG drawing."
        case .wallSweep:
            return sel.contains { $0.wall != nil && $0.wall?.curtain == nil } ? nil : "Select walls."
        case .slabEdge:
            return sel.contains { $0.category == .floors } ? nil : "Select floors."
        case .roofSoffit:
            return sel.contains { $0.roof != nil && $0.roof?.extrusion == nil } ? nil : "Select footprint roofs."
        default:
            return nil
        }
    }

    func siteTool(_ id: CommandID, _ c: ToolContext) -> (any InteractiveTool)? {
        let surface = selectedSurfaces.first?.id
        switch id {
        case .parkingLayout:
            return ParkingLayoutTool(ctx: c)
        case .subregion: return SubregionTool(ctx: c, hostID: surface)
        case .splitSurface: return SplitSurfaceTool(ctx: c, hostID: surface)
        case .labelContours: return LabelContoursTool(ctx: c)
        case .toposolid: return ToposolidSketchTool(ctx: c) // BL-SITE
        case .subdivideToposolid: return selection.compactMap({ model[$0] }).first(where: \.isToposolid).map { ToposolidSketchTool(ctx: c, subdivide: $0.id) } // BL-SITE
        case .editSurface: return surface.flatMap { EditSurfaceTool(ctx: c, surfaceID: $0, commandID: .editSurface) }
        case .siteComponent: return componentTool(c, commandID: id, keywords: ["tree", "plant", "shrub", "planting", "entourage", "bench", "bollard", "planter", "site"])
        case .parkingComponent: return componentTool(c, commandID: id, keywords: ["parking", "stall", "car", "sign"])
        default: return nil
        }
    }

    /// Site Component / Parking Component: places the site (planting, entourage, site furniture) or parking type in
    /// use, the way the Component tool does; when none is loaded yet, opens the component library filtered to those
    /// categories so one can be chosen.
    private func componentTool(_ c: ToolContext, commandID: CommandID, keywords: [String]) -> (any InteractiveTool)? {
        let parking = commandID == .parkingComponent
        let libraryCats = parking ? ComponentLibrary.parkingCategories : ComponentLibrary.siteCategories
        let cats: [Category] = libraryCats + (parking ? [.genericModels, .specialtyEquipment] : [.genericModels, .furniture, .specialtyEquipment])
        let current = cats.lazy.compactMap { cat in self.state.currentTypes[cat].flatMap { self.model[$0] }.map { (cat, $0) } }.first
        let match = current ?? cats.lazy.flatMap { cat in self.model.types(for: cat).map { (cat, $0) } }.first { cat, t in
            let n = ((t.typeData?.familyName ?? "") + " " + t.name).lowercased()
            return libraryCats.contains(cat) || keywords.contains { n.contains($0) }
        }
        guard let (cat, type) = match else {
            state.showComponentLibrary(categories: libraryCats)
            return nil
        }
        state.currentTypes[cat] = type.id
        c.currentTypes[cat] = type.id
        return ComponentTool(ctx: c, category: cat, commandID: commandID)
    }

    func performSite(_ id: CommandID) {
        let sel = selection
        switch id {
        case .siteSettings:
            state.presented = .site(.settings)
        case .toposurfaceFromFile:
            let types = ["csv", "txt", "xyz", "pts"].compactMap { UTType(filenameExtension: $0) } + [.commaSeparatedText, .plainText]
            chooseFile(types) { url in state.presented = .site(.pointFile(url)) }
        case .toposurfaceFromImport:
            if let s = sel.first { state.presented = .site(.fromImport(s)) }
        case .toposolidFromFile, .toposolidFromImport, .generateToposolid, .simplifySurface, .excavateToposolid: // BL-SITE
            performToposolid(id)
        case .mergeSurfaces:
            let ids = selectedSurfaces.map(\.id)
            var kept: ElementID?
            session.perform("Merge Surfaces") { tx in kept = try SiteOperations.merge(ids, in: tx) }
            if let e = session.lastError { state.show(e.message, error: true) } else if let kept { session.selection.select([kept]); state.show("\(ids.count) toposurfaces merged.") }
        case .gradedRegion:
            guard let s = selectedSurfaces.first?.id else { return }
            let phase = state.activeView?.view?.phaseID
            var graded: ElementID?
            session.perform("Graded Region") { tx in graded = try SiteOperations.gradedRegion(from: s, phase: phase, in: tx) }
            if let e = session.lastError { state.show(e.message, error: true); return }
            guard let graded, let c = ctx(), let tool = EditSurfaceTool(ctx: c, surfaceID: graded) else { return }
            session.selection.select([graded])
            state.setTool(tool)
            state.show("Graded region created; the existing surface is demolished in this phase. Add or re-level points, then Finish.")
        case .wallSweep:
            let walls = sel.filter { model[$0]?.wall != nil && model[$0]?.wall?.curtain == nil }
            session.perform("Add Wall Sweep") { tx in for w in walls { tx.update(w) { if ($0.wall?.sweeps ?? []).isEmpty { $0.wall?.sweeps = [WallSweep()] } } } }
            if session.lastError == nil { state.show("Sweep added to \(walls.count) wall\(walls.count == 1 ? "" : "s"). Set its height, size, side and material in Properties.") }
        case .slabEdge:
            let floors = sel.filter { model[$0]?.category == .floors }
            session.perform("Add Slab Edge") { tx in for f in floors { tx.update(f) { if $0.slab?.edgeProfile == nil { $0.slab?.edgeProfile = SlabEdgeProfile() } } } }
            if session.lastError == nil { state.show("Slab edge added to \(floors.count) floor\(floors.count == 1 ? "" : "s"). Set its width and depth in Properties.") }
        case .roofSoffit:
            let roofs = sel.filter { model[$0]?.roof != nil && model[$0]?.roof?.extrusion == nil }
            session.perform("Add Soffit") { tx in
                for r in roofs {
                    tx.update(r) { e in
                        guard e.roof?.soffit == nil else { return }
                        let o = e.roof?.overhang ?? 0
                        e.roof?.soffit = RoofSoffit(depth: o > Tolerance.length ? o : 0.45)
                    }
                }
            }
            if session.lastError == nil { state.show("Soffit added to \(roofs.count) roof\(roofs.count == 1 ? "" : "s"). Set its depth in Properties.") }
        default:
            if let c = ctx(), let t = siteTool(id, c) { state.setTool(t) }
        }
    }
}
