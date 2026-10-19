import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM3D: screenshots of Furniture design in 3D (hooked from `screenshots()` with one line, per appearance): the
// bookcase's 3D Design view with the Create tab's tools enabled, the Shelf tool sketching in 3D with its Placement
// Plane, the Panel tool on the top's top face (Pick a Face), and a selected side with its shape handles and
// temporary dimensions.
extension QAHarness {
    static func fm3dScreenshots(_ suffix: String) async {
        guard let model = FurnitureSamples.bookcaseModel() else { return }
        let doc = ArcusDocument(model: model, displayName: "Bookcase 3D")
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        await pause(800)
        guard let s = doc.state, let w = s.window, let v3 = s.model.views.first(where: { $0.name == FurnitureDesignView.name }) else { doc.close(); return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        s.open(v3.id)
        s.ribbonTab = .create
        await pause(1500)
        CommandRouter(state: s).run(.zoomExtents)
        await pause(600)
        await shot(w, "fm3d-create-tab-3d-\(suffix)")
        let r = CommandRouter(state: s)
        // The Shelf tool in 3D: Pick Panels at the shelf's height, the Options Bar's Placement Plane.
        r.run(.furnitureShelf)
        if let host = s.canvases[v3.id] as? Viewport3DHost, let p = host.viewport.viewPoint(of: Vec3(0, 0.05, 14 * 0.0254)) {
            host.tools.qaHover(p)
        }
        await pause(500)
        await shot(w, "fm3d-shelf-sketch-3d-\(suffix)")
        s.cancelTool()
        // The Panel tool on a picked face.
        r.run(.furniturePanel)
        if let host = s.canvases[v3.id] as? Viewport3DHost, let top = s.model.elements(.furnitureShelves).first(where: { $0.furnitureShelf?.role == .top }),
           let b = FurniturePartFaces.box(top, s.model), let p = host.viewport.viewPoint(of: Vec3(b.center.x, b.center.y, b.max.z)) {
            host.tools.fm3d.pickingPlane = true
            host.tools.qaHover(p)
            await pause(300)
            await shot(w, "fm3d-pick-face-\(suffix)")
            host.tools.fm3dFinishPickingPlane(at: p)
            host.tools.qaHover(p)
        }
        await pause(500)
        await shot(w, "fm3d-panel-on-face-\(suffix)")
        s.cancelTool()
        // Shape handles and temporary dimensions on a selected side.
        if let side = s.model.elements(.furniturePanels).first(where: { $0.furniturePanel?.role == .panel }) { s.session.selection.select([side.id]) }
        await pause(600)
        await shot(w, "fm3d-shape-handles-\(suffix)")
        s.session.selection.clear()
        doc.updateChangeCount(.changeCleared)
        doc.close()
        await pause(400)
    }
}

extension Viewport3DToolController {
    /// QA: the pointer moved to a view point (as a mouse move there would).
    func qaHover(_ p: CGPoint) {
        guard let w = viewport?.window, let e = NSEvent.mouseEvent(with: .mouseMoved, location: viewport?.convert(p, to: nil) ?? p, modifierFlags: [],
                                                                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber,
                                                                    context: nil, eventNumber: 0, clickCount: 1, pressure: 0) else { return }
        _ = viewport3DMouseMoved(e, at: p)
        overlay.needsDisplay = true
    }
}
