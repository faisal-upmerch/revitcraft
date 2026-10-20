import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FMG4: screenshots of the gap batches' finished items (hooked from `screenshots()` with one line, per appearance):
// library pieces at their automatic scale (Entryway Bench, Side Table, Sofa, Wardrobe: plan and Front); the Entryway
// Bench's cushion with Visible's = button and the Associate Family Parameter dialog; the Kitchen Cabinet door's
// Leaf Count = button; the Corner Cabinet out of square (its door, hardware and swing turned with the cant) in 3D and
// in a section; the chest's lid swing in plan; an exploded Back 3D with tags in the live view; F101 after Shop
// Drawings (the base cabinet at 1/2"); and a project elevation where a wall hides a loaded cabinet's swings.
extension QAHarness {
    static func fmg4Screenshots(_ suffix: String) async {
        let pieces = ["Entryway Bench", "Side Table", "Sofa", "Wardrobe"]
        for name in pieces {
            guard let model = FurnitureLibrary.all.first(where: { $0.name == name })?.build() else { continue }
            let slug = name.lowercased().replacingOccurrences(of: " ", with: "-")
            let doc = ArcusDocument(model: model, displayName: name)
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            await pause(800)
            guard let s = doc.state, let w = s.window else { doc.close(); continue }
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            for (kind, view, shotName) in [(ViewKind.floorPlan, nil as String?, "plan"), (.elevation, "Front", "front")] {
                guard let v = QAHarness.view(s, kind: kind, name: view) else { continue }
                s.open(v.id)
                _ = await waitForGraphics(s, v.id)
                (s.canvases[v.id] as? Canvas2DView)?.zoomToFit()
                await pause(700)
                await shot(w, "fmg4-\(slug)-\(shotName)-\(suffix)")
            }
            if name == "Entryway Bench", let cushion = s.model.elements(.furnitureForms).first {
                // Visible associated with Seat Cushion (the = button lit), and the dialog.
                if let v = QAHarness.view(s, kind: .threeD, name: nil) { s.open(v.id); CommandRouter(state: s).run(.zoomExtents) }
                s.session.selection.select([cushion.id])
                await pause(1200)
                await shot(w, "fmg4-entryway-bench-cushion-visible-\(suffix)")
                s.presented = .fmg4(.associate(elements: [cushion.id], property: FurnitureAssociations.visible, name: "Visible"))
                await pause(700)
                await shot(w, "fmg4-associate-dialog-\(suffix)")
                s.presented = nil
                s.session.selection.clear()
            }
            doc.updateChangeCount(.changeCleared)
            doc.close()
            await pause(400)
        }

        // The Kitchen Cabinet door's Leaf Count, associated (the = button) with Leaf Count.
        if let model = FurnitureLibrary.all.first(where: { $0.name == "Kitchen Cabinet" })?.build() {
            await fmg4Document(model, "Kitchen Cabinet") { s, w in
                if let v = QAHarness.view(s, kind: .elevation, name: "Front") { s.open(v.id); _ = await waitForGraphics(s, v.id); (s.canvases[v.id] as? Canvas2DView)?.zoomToFit() }
                if let door = s.model.elements(.furnitureFronts).first(where: { $0.furnitureFront?.kind == .door }) { s.session.selection.select([door.id]) }
                await pause(700)
                await shot(w, "fmg4-kitchen-cabinet-leaf-count-\(suffix)")
            }
        }

        // The Corner Cabinet made out of square (34" x 24"): its door, hardware and swing turned with the cant.
        if let model = FurnitureLibrary.all.first(where: { $0.name == "Corner Cabinet" })?.build() {
            await fmg4Document(model, "Corner Cabinet") { s, w in
                s.session.perform("Out of square") { tx in
                    try FurnitureParameters.setValue("Width", .double(34 * 0.0254), in: tx)
                    try FurnitureParameters.setValue("Depth", .double(24 * 0.0254), in: tx)
                }
                if let v = QAHarness.view(s, kind: .threeD, name: nil) { s.open(v.id); CommandRouter(state: s).run(.zoomExtents) }
                await pause(1500)
                await shot(w, "fmg4-corner-cabinet-out-of-square-3d-\(suffix)")
                if let v = QAHarness.view(s, kind: .floorPlan, name: nil) { s.open(v.id); _ = await waitForGraphics(s, v.id); (s.canvases[v.id] as? Canvas2DView)?.zoomToFit() }
                await pause(700)
                await shot(w, "fmg4-corner-cabinet-out-of-square-plan-\(suffix)")
            }
        }

        // The chest's lid swing in plan; the base cabinet's exploded Back 3D (tags in the live view) and its F101.
        if let model = FurnitureSamples.chestModel() {
            await fmg4Document(model, "Chest") { s, w in
                if let v = QAHarness.view(s, kind: .floorPlan, name: nil) { s.open(v.id); _ = await waitForGraphics(s, v.id); (s.canvases[v.id] as? Canvas2DView)?.zoomToFit() }
                await pause(700)
                await shot(w, "fmg4-chest-lid-plan-\(suffix)")
            }
        }
        if let model = FurnitureSamples.baseCabinetModel() {
            await fmg4Document(model, "Base Cabinet") { s, w in
                s.session.perform("Shop Drawings") { tx in FurnitureShopDrawings.update(in: tx) }
                if let b = s.model.views.first(where: { $0.name == FurnitureShopDrawings.back3DName }) {
                    s.open(b.id)
                    CommandRouter(state: s).run(.zoomExtents)
                    await pause(1500)
                    await shot(w, "fmg4-base-cabinet-exploded-tags-\(suffix)")
                }
                if let f101 = s.model.sheets.first(where: { $0.sheet?.number == FurnitureShopDrawings.shopDrawing }) {
                    s.open(f101.id)
                    _ = await waitForGraphics(s, f101.id)
                    (s.canvases[f101.id] as? Canvas2DView)?.zoomToFit()
                    await pause(900)
                    await shot(w, "fmg4-base-cabinet-f101-\(suffix)")
                }
            }
        }

        // A project: a wall in front of a loaded cabinet hides its swings in the elevation.
        guard let src = FurnitureLibrary.all.first(where: { $0.name == "Kitchen Cabinet" })?.build() else { return }
        let (model, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Kitchen")
        await fmg4Document(model, "Kitchen") { s, w in
            let f = FurnitureCompiler.family(from: src)
            var fid: ElementID?
            s.session.perform("Load") { tx in fid = FurnitureLoading.load(f, from: src, replacing: nil, in: tx) }
            var elevation: ElementID?
            s.session.perform("Place") { tx in
                var x = 0.0
                for name in ["B15", "B30", "B36"] {
                    guard let t = tx.model.elements(.elementTypes).first(where: { $0.typeData?.familyID == fid && $0.name == name }) else { continue }
                    tx.create(.casework, data: .component(ComponentData(location: Vec2(x, 0))), typeID: t.id, levelID: tx.model.levels.first?.id)
                    x += 0.95
                }
                if let wt = tx.model.types(for: .walls).first {
                    tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(-0.6, -1), Vec2(0.9, -1))))), typeID: wt.id, levelID: tx.model.levels.first?.id)
                }
                var ev = ViewData(kind: .elevation, scale: 24)
                ev.planeOrigin = Vec3(0.9, -3, 0); ev.viewDirection = Vec2(0, 1); ev.farClip = 10; ev.detailLevel = .medium
                elevation = tx.create(.views, name: "Kitchen Elevation", data: .view(ev))
            }
            if let elevation {
                s.open(elevation)
                _ = await waitForGraphics(s, elevation)
                (s.canvases[elevation] as? Canvas2DView)?.zoomToFit()
                await pause(800)
                await shot(w, "fmg4-project-wall-hides-swings-\(suffix)")
            }
        }
    }

    /// Opens a document window for a model, runs `body`, and closes it without saving.
    static func fmg4Document(_ model: BIMModel, _ name: String, _ body: (DocumentState, NSWindow) async -> Void) async {
        let doc = ArcusDocument(model: model, displayName: name)
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        await pause(900)
        guard let s = doc.state, let w = s.window else { doc.close(); return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        await body(s, w)
        doc.updateChangeCount(.changeCleared)
        doc.close()
        await pause(400)
    }
}
