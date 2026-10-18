import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// BL-SITE (ARCUS-070): toposolid commands, the Simplify Surface dialog and the contextual ribbon items for
/// toposolids and legacy toposurfaces.
extension CommandRouter {
    private var selectedElements: [Element] { selection.compactMap { model[$0] } }

    func toposolidDisabledReason(_ id: CommandID) -> String? {
        let sel = selectedElements
        switch id {
        case .toposolidFromImport:
            return sel.count == 1 && (sel[0].link?.format == .dxf || sel[0].link?.format == .dwg) ? nil : "Select one linked or imported DXF or DWG drawing."
        case .generateToposolid:
            return sel.contains(where: \.isLegacyToposurface) ? nil : "Select a toposurface."
        case .subdivideToposolid:
            return sel.filter(\.isToposolid).count == 1 && isPlan ? nil : "Select one toposolid in a plan view."
        case .simplifySurface:
            return sel.count == 1 && sel[0].topography != nil && sel[0].topography?.boundary == nil ? nil : "Select one toposolid or toposurface."
        case .excavateToposolid:
            guard sel.filter(\.isToposolid).count == 1 else { return "Select one toposolid and the floors or building pads that cut it." }
            return sel.contains { $0.slab != nil && ($0.category == .floors || $0.category == .buildingPads) } ? nil : "Also select the floors or building pads that cut the toposolid."
        default:
            return nil
        }
    }

    func performToposolid(_ id: CommandID) {
        let sel = selectedElements
        switch id {
        case .toposolidFromFile:
            let types = ["csv", "txt", "xyz", "pts"].compactMap { UTType(filenameExtension: $0) } + [.commaSeparatedText, .plainText]
            chooseFile(types) { url in state.presented = .site(.pointFileToposolid(url)) }
        case .toposolidFromImport:
            if let s = sel.first { state.presented = .site(.fromImportToposolid(s.id)) }
        case .generateToposolid:
            let surfaces = sel.filter(\.isLegacyToposurface).map(\.id)
            let type = state.currentTypes[.topography]
            var made: [ElementID] = []
            session.perform("Generate Toposolid") { tx in for s in surfaces { made.append(try ToposolidOperations.generate(from: s, typeID: type, in: tx)) } }
            if let e = session.lastError { state.show(e.message, error: true); return }
            session.selection.select(made)
            state.show("\(made.count) toposolid\(made.count == 1 ? "" : "s") generated; the toposurface\(made.count == 1 ? " was" : "s were") replaced.")
        case .simplifySurface:
            if let s = sel.first { state.presented = .site(.simplify(s.id)) }
        case .excavateToposolid:
            guard let solid = sel.first(where: \.isToposolid)?.id else { return }
            let cutters = sel.filter { $0.slab != nil }.map(\.id)
            var r = (cut: 0.0, fill: 0.0)
            session.perform("Excavate") { tx in r = try ToposolidOperations.excavate(solid, by: cutters, in: tx) }
            if let e = session.lastError { state.show(e.message, error: true); return }
            let f = { (v: Double) in Parameters.format(.double(v), type: .volume, model: self.model) }
            state.show("Excavated: cut \(f(r.cut)), fill \(f(r.fill)). The totals are in the toposolid's Cut and Fill parameters.")
        default:
            break
        }
    }
}

extension RibbonContent {
    /// Contextual items for toposolids (shape editing, Sub-Divide, split, simplify, excavate) and for legacy
    /// toposurfaces (Generate Toposolid).
    static func siteSelectionItems(_ sel: [Element], _ m: BIMModel) -> (title: String?, items: [RibbonItem]) {
        if sel.contains(where: \.isToposolid) {
            return ("Toposolid", [.large(.editSurface), .large(.subdivideToposolid), .small(.splitSurface), .small(.simplifySurface), .small(.excavateToposolid),
                                  .small(.mergeSurfaces), .small(.gradedRegion)])
        }
        if sel.contains(where: \.isLegacyToposurface) {
            return ("Toposurface", [.large(.generateToposolid), .small(.editSurface), .small(.simplifySurface), .small(.splitSurface)])
        }
        return (nil, [])
    }
}
