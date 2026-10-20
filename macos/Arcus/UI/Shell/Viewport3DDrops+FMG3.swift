import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
import ArcusViewport3D

// FMG3: a furniture piece (.arcusfurniture) or family (.arcusfamily) dropped on a 3D view loads (as Load Family does,
// reusing one already loaded) and is placed where it lands: where the pointer meets the work plane's level (under what
// it points at when that plane is out of sight), as a component placed in a plan.

extension Viewport3DToolController: Viewport3DDropHandler {
    func viewport3DAccepts(_ urls: [URL]) -> Bool {
        state.model[viewID]?.view?.kind == .threeD && urls.contains { [FurnitureLibraryCatalog.fileExtension, FamilyPackage.fileExtension].contains($0.pathExtension.lowercased()) }
    }

    func viewport3DDrop(_ urls: [URL], at point: CGPoint) -> Bool {
        guard let url = urls.first(where: { [FurnitureLibraryCatalog.fileExtension, FamilyPackage.fileExtension].contains($0.pathExtension.lowercased()) }) else { return false }
        dropPreview = nil
        // FMG4: on the view's work plane (a reference plane or a face set with Work Plane ▸ Set), else the level.
        guard let q = dropPlacement(at: point) else {
            state.show("Drop it where the view meets the work plane.", error: true)
            return false
        }
        return Self.loadAndPlace(url, at: q.point, level: dropTarget.level, offset: q.offset, in: state)
    }

    /// Loads the file (once) and places its type at a plan point on a level; true when placed.
    @discardableResult
    static func loadAndPlace(_ url: URL, at p: Vec2, level: ElementID?, offset: Double = 0, in state: DocumentState) -> Bool {
        let preferred: String?, name: String?
        if url.pathExtension.lowercased() == FurnitureLibraryCatalog.fileExtension {
            guard let source = FurnitureFileLoad.furnitureModel(url, state) else { return false }
            preferred = source.furnitureSetup?.currentType
            name = FurnitureFileLoad.load(source, into: state, reuse: true)
        } else {
            preferred = nil
            name = FurnitureFileLoad.load(url, into: state, reuse: true)
        }
        guard let name, let type = FurnitureFileLoad.placementType(name, preferred: preferred, state), let cat = type.typeData?.instanceCategory else { return false }
        state.currentTypes[cat] = type.id
        var placed: ElementID?
        state.session.perform("Place \(name)") { tx in
            var c = ComponentData(location: p)
            c.offset = offset // FMG4: on a work plane above the level
            placed = tx.create(cat, data: .component(c), typeID: type.id, levelID: level)
        }
        if let e = state.session.lastError { state.show(e.message, error: true); return false }
        if let placed { state.session.selection.select([placed]) }
        state.show("Placed “\(name)”.")
        return placed != nil
    }
}
