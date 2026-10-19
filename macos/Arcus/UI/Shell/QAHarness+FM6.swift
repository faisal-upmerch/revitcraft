import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM6: screenshots of Furniture joints (hooked from `screenshots()` with one line, per appearance): the sample bookcase
// with a fixed (dadoed) shelf in a section across it and its Left elevation at Fine (dados, the back's groove, hidden
// dowel and shelf-pin holes), the Joint tool's markers with a picked joint and its Options Bar in the Front elevation
// and in 3D, a box of panels in plan with butt and mitred corners, and the Joint Rules dialog.
extension QAHarness {
    static func fm6Screenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Bookcase Joints", category: .casework, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        var ids: [String: ElementID] = [:]
        s.session.perform("Bookcase") { tx in ids = try FurnitureSamples.bookcase(in: tx) }
        s.session.perform("Plinth and Back") { tx in try FurnitureSamples.bookcaseFinish(in: tx, ids) }
        // A fixed shelf (dadoed into the sides), a section across the carcass and Fine elevations.
        s.session.perform("Fixed Shelf") { tx in if let sh = ids["shelf2"] { tx.update(sh) { $0.furnitureShelf?.adjustable = false; $0.furnitureShelf?.pins = nil } } }
        s.session.perform("Section") { tx in
            var v = ViewData(kind: .section, scale: 6)
            v.planeOrigin = Vec3(0, -0.01, 0); v.viewDirection = Vec2(0, 1); v.farClip = 2; v.detailLevel = .fine
            tx.create(.views, name: "Section 1", data: .view(v))
            for e in tx.model.views where e.view?.kind == .elevation { tx.update(e.id) { $0.view?.detailLevel = .fine } }
        }
        for (kind, name, label) in [(ViewKind.section, "Section 1", "section-fine"), (.elevation, "Left", "left-fine")] {
            guard let v = view(s, kind: kind, name: name) else { continue }
            s.open(v.id)
            _ = await waitForGraphics(s, v.id)
            (s.canvases[v.id] as? Canvas2DView)?.zoomToFit()
            await pause(700)
            await shot(w, "fm6-bookcase-\(label)-\(suffix)")
        }
        // The Joint tool in the Front elevation: markers, the side–top joint picked, its Options Bar.
        if let front = view(s, kind: .elevation, name: "Front"), let left = ids["left"], let top = ids["top"],
           let j = FurnitureJoints.joint(left, top, s.model), let map = FurnitureSketchMap.of(front.view) {
            s.open(front.id)
            _ = await waitForGraphics(s, front.id)
            (s.canvases[front.id] as? Canvas2DView)?.zoomToFit()
            CommandRouter(state: s).run(.furnitureJoint)
            if let tool = s.activeTool as? FurnitureJointTool {
                let p = map.project(j.marker)
                tool.pointerDown(ToolInput(point: p, rawPoint: p))
                s.toolChangedState()
            }
            await pause(700)
            await shot(w, "fm6-joint-tool-front-\(suffix)")
            s.cancelTool()
            await pause(300)
        }
        // In 3D: the markers on the model.
        if let v3 = view(s, kind: .threeD) {
            s.open(v3.id)
            await pause(1200)
            CommandRouter(state: s).run(.furnitureJoint)
            await pause(900)
            await shot(w, "fm6-joint-tool-3d-\(suffix)")
            s.cancelTool()
            await pause(300)
        }
        // Joint Rules.
        s.presented = .fm6(.jointRules)
        await pause(800)
        if let sheet = w.attachedSheet { await shot(sheet, "fm6-joint-rules-\(suffix)") } else { await shot(w, "fm6-joint-rules-\(suffix)") }
        s.presented = nil
        await pause(500)
        // A box drawn as a rectangle of panels: butt corners (the long sides run through), then mitred.
        if let plan = view(s, kind: .floorPlan) {
            s.session.perform("Box") { tx in
                for e in Category.furnitureParts.flatMap({ tx.model.elements($0) }) { tx.delete(e.id) }
                _ = try FurniturePartOperations.createPanelRectangle(Rect2(min: Vec2(-0.38, -0.2), max: Vec2(0.38, 0.2)), extent: PartExtent(topPlane: nil, height: 0.6), in: tx)
            }
            s.open(plan.id)
            _ = await waitForGraphics(s, plan.id)
            (s.canvases[plan.id] as? Canvas2DView)?.zoomToFit()
            await pause(600)
            await shot(w, "fm6-box-plan-butt-\(suffix)")
            s.session.perform("Miter") { tx in for j in FurnitureJoints.joints(tx.model) { try FurnitureJointOperations.set(j.key, type: .miter, in: tx) } }
            _ = await waitForGraphics(s, plan.id)
            await pause(600)
            await shot(w, "fm6-box-plan-miter-\(suffix)")
        }
        s.ribbonTab = .fabricate; s.ribbonShowsContextual = false
        await pause(400)
        await shot(w, "fm6-ribbon-fabricate-\(suffix)")
        s.document?.updateChangeCount(.changeCleared)
        s.document?.close()
        await pause(500)
    }
}
