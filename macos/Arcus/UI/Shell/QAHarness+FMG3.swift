import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FMG3: screenshots of fronts on every face (hooked from `screenshots()` with one line, per appearance): the island's
// doors in its Back elevation; the Corner Cabinet's canted door in a section looking at the cant, in plan and 3D; the
// Storage Bed's side drawers in its Left elevation and plan; the chest's Shaker lid and its swing in the Right
// elevation; the Kitchen Cabinet at B15 (single) and B30 (a pair) with Leaf Count in Properties; a bay selected for
// Move; and a project elevation with loaded Kitchen Cabinets showing their door swings.
extension QAHarness {
    static func fmg3Screenshots(_ suffix: String) async {
        let pieces: [(String, BIMModel?)] = [
            ("island", FurnitureSamples.islandModel()),
            ("corner-cabinet", FurnitureLibrary.all.first { $0.name == "Corner Cabinet" }?.build()),
            ("storage-bed", FurnitureLibrary.all.first { $0.name == "Storage Bed" }?.build()),
            ("chest", FurnitureSamples.chestModel()),
            ("kitchen-cabinet", FurnitureLibrary.all.first { $0.name == "Kitchen Cabinet" }?.build()),
        ]
        for (label, model) in pieces {
            guard let model else { continue }
            let doc = ArcusDocument(model: model, displayName: label)
            NSDocumentController.shared.addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
            await pause(800)
            guard let s = doc.state, let w = s.window else { doc.close(); continue }
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            var views: [(ViewKind, String?, String)] = [(.floorPlan, nil, "plan"), (.threeD, nil, "3d")]
            switch label {
            case "island": views.append((.elevation, "Back", "back"))
            case "corner-cabinet":
                s.session.perform("Cant Section") { tx in
                    var v = ViewData(kind: .section, scale: 12)
                    let d = Vec2(-1, 1).normalized
                    v.planeOrigin = Vec3(d * -1.0, z: 0); v.viewDirection = d; v.farClip = 3; v.detailLevel = .fine
                    tx.create(.views, name: "Cant", data: .view(v))
                }
                views.append((.section, "Cant", "cant-section"))
            case "storage-bed": views.append((.elevation, "Left", "left"))
            case "chest": views.append((.elevation, "Right", "right"))
            default: views.append((.elevation, "Front", "front"))
            }
            for (kind, name, shotName) in views {
                guard let v = view(s, kind: kind, name: name) else { continue }
                s.open(v.id)
                if kind != .threeD { _ = await waitForGraphics(s, v.id); (s.canvases[v.id] as? Canvas2DView)?.zoomToFit() } else { CommandRouter(state: s).run(.zoomExtents) }
                await pause(kind == .threeD ? 1500 : 700)
                await shot(w, "fmg3-\(label)-\(shotName)-\(suffix)")
            }
            if label == "kitchen-cabinet" {
                // The door's Leaf Count in Properties, and the cabinet as a pair (B30).
                if let door = s.model.elements(.furnitureFronts).first(where: { $0.furnitureFront?.kind == .door }) { s.session.selection.select([door.id]) }
                await pause(600)
                await shot(w, "fmg3-kitchen-cabinet-leaf-count-\(suffix)")
                s.session.selection.clear()
                s.session.perform("B30") { tx in try FurnitureParameters.setCurrentType("B30", in: tx) }
                if let v = view(s, kind: .elevation, name: "Front") { s.open(v.id); _ = await waitForGraphics(s, v.id); (s.canvases[v.id] as? Canvas2DView)?.zoomToFit() }
                await pause(700)
                await shot(w, "fmg3-kitchen-cabinet-b30-front-\(suffix)")
            }
            if label == "island", let back = view(s, kind: .elevation, name: "Back"),
               let bay = s.model.elements(.furnitureBays).first(where: { $0.furnitureBay?.facing != nil }) {
                // A bay selected in the Back elevation, ready to Move (it moves like a room; its door follows).
                s.open(back.id)
                s.session.selection.select([bay.id])
                await pause(600)
                await shot(w, "fmg3-island-bay-selected-\(suffix)")
                s.session.selection.clear()
            }
            doc.updateChangeCount(.changeCleared)
            doc.close()
            await pause(400)
        }
        // A project: loaded Kitchen Cabinets in an elevation, with their door swings.
        guard let src = FurnitureLibrary.all.first(where: { $0.name == "Kitchen Cabinet" })?.build() else { return }
        let (model, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Kitchen")
        let doc = ArcusDocument(model: model, displayName: "Kitchen")
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        await pause(900)
        guard let s = doc.state, let w = s.window else { doc.close(); return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
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
            var ev = ViewData(kind: .elevation, scale: 24)
            ev.planeOrigin = Vec3(0.9, -3, 0); ev.viewDirection = Vec2(0, 1); ev.farClip = 10; ev.detailLevel = .medium
            elevation = tx.create(.views, name: "Kitchen Elevation", data: .view(ev))
        }
        if let elevation {
            s.open(elevation)
            _ = await waitForGraphics(s, elevation)
            (s.canvases[elevation] as? Canvas2DView)?.zoomToFit()
            await pause(800)
            await shot(w, "fmg3-project-kitchen-elevation-\(suffix)")
        }
        doc.updateChangeCount(.changeCleared)
        doc.close()
        await pause(400)
    }
}
