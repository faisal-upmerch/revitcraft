import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FMG1: screenshots of the Furniture parts and flex gaps (hooked from `screenshots()` with one line, per appearance):
// a bookcase with a dimension locked from the Top to a shelf face, before and after Height changes; a Blend sketch on
// its top with the base dimmed and Edit Base in the ribbon; a Sweep sketched in the Front elevation (Pick Path); and
// the nine pieces that now flex fully, plus the turned-leg console, in {3D} at their second type.
extension QAHarness {
    static func fmg1Screenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Bookcase", category: .casework, template: nil)
        await pause(900)
        if let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window {
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            var ids: [String: ElementID] = [:]
            s.session.perform("Bookcase") { tx in ids = try FurnitureSamples.bookcase(in: tx) }
            if let front = view(s, kind: .elevation, name: "Front"), let shelf = ids["shelf2"] ?? ids["shelf1"],
               let top = FurniturePlanes.names(s.model).first(where: { $0.value == "Top" })?.key {
                var dim: ElementID?
                s.session.perform("Dimension") { tx in
                    dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: [GeometryReference(top, .location), .partFace(shelf, PartFaceRef(axis: .z, atMax: true))],
                                                                                linePoint: Vec2(24 * 0.0254, 0))), typeID: tx.model.types(for: .dimensions).first?.id, ownerViewID: front.id)
                }
                if let dim { s.session.perform("Lock") { tx in tx.update(dim) { $0.dimension?.locked = true } } }
                s.open(front.id)
                _ = await waitForGraphics(s, front.id); (s.canvases[front.id] as? Canvas2DView)?.zoomToFit()
                await pause(700)
                await shot(w, "fmg1-locked-dimension-\(suffix)")
                s.session.perform("Height") { tx in try FurnitureParameters.setValue("Height", .double(42 * 0.0254), in: tx) }
                _ = await waitForGraphics(s, front.id); (s.canvases[front.id] as? Canvas2DView)?.zoomToFit()
                await pause(700)
                await shot(w, "fmg1-locked-dimension-flexed-\(suffix)")
            }
            // Blend: the base sketched, then Edit Top.
            if let plan = view(s, kind: .floorPlan, name: "Ref. Level") {
                s.open(plan.id)
                _ = await waitForGraphics(s, plan.id)
                CommandRouter(state: s).run(.furnitureBlend)
                await pause(400)
                if let t = s.activeTool as? SketchTool {
                    t.setOption("mode", .text("Rectangle"))
                    for p in [Vec2(-0.3, -0.15), Vec2(0.3, 0.15)] { t.pointerDown(ToolInput(point: p, rawPoint: p)) }
                    await pause(300)
                    await shot(w, "fmg1-blend-base-\(suffix)")
                    CommandRouter(state: s).run(.furnitureBlendEditTop)
                    t.setOption("mode", .text("Rectangle"))
                    for p in [Vec2(-0.15, -0.08), Vec2(0.15, 0.08)] { t.pointerDown(ToolInput(point: p, rawPoint: p)) }
                    t.pointerMoved(ToolInput(point: Vec2(0.2, 0.1), rawPoint: Vec2(0.2, 0.1)))
                    s.toolRevision += 1
                    await pause(500)
                    await shot(w, "fmg1-blend-edit-top-\(suffix)")
                }
                s.cancelTool()
                await pause(300)
            }
            // Sweep in the Front elevation: Pick Path in the Draw choices, the path on the Front plane.
            if let front = view(s, kind: .elevation, name: "Front") {
                s.open(front.id)
                _ = await waitForGraphics(s, front.id)
                CommandRouter(state: s).run(.furnitureSweep)
                await pause(400)
                if let t = s.activeTool as? SketchTool {
                    for p in [Vec2(-0.35, 0.6), Vec2(0, 0.7), Vec2(0.35, 0.6)] { t.pointerDown(ToolInput(point: p, rawPoint: p)) }
                    s.toolRevision += 1
                    await pause(500)
                    await shot(w, "fmg1-sweep-front-\(suffix)")
                }
                s.cancelTool()
                await pause(300)
            }
            s.document?.updateChangeCount(.changeCleared)
            s.document?.close()
            await pause(500)
        }
        guard suffix == "light" else { return }
        let names = ["Sun Lounger", "Hammock", "Hanging Chair", "Picnic Table", "Folding Chair", "Swing Bench", "Adirondack Chair", "Folding Screen",
                     "Ladder Shelf", "Decorative Console"]
        for p in FurnitureLibrary.all where names.contains(p.name) {
            var m = p.build()
            // The second size type, to show the angled parts, slats and revolves following the planes.
            if let second = m.furnitureSetup?.family.types.dropFirst().first?.name {
                let tx = TransactionContext(model: m, name: "Type")
                if (try? FurnitureParameters.setCurrentType(second, in: tx)) != nil, let c = try? tx.commit() { m = c.model }
            }
            let doc = ArcusDocument(model: m, displayName: p.name)
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            await pause(700)
            guard let s = doc.state, let w = s.window else { doc.close(); continue }
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            if let v = view(s, kind: .threeD) {
                s.open(v.id)
                CommandRouter(state: s).run(.zoomExtents)
                await pause(1300)
                await shot(w, "fmg1-flex-\(p.name.lowercased().replacingOccurrences(of: " ", with: "-"))-3d-\(suffix)")
            }
            doc.updateChangeCount(.changeCleared)
            doc.close()
            await pause(300)
        }
    }
}
