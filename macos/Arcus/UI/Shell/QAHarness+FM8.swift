import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM8: screenshots of the family round trip (hooked from `screenshots()` with one line, per appearance): a project with
// the sample pieces (bookcase, dining table, base cabinet) loaded from Furniture mode and placed, in plan at Coarse and
// Fine and in {3D} at Coarse and Fine; the Load Furniture browser; Edit Family opening the cabinet in Furniture mode;
// and the Family Already Exists prompt its Load into Project shows.
extension QAHarness {
    static func fm8Screenshots(_ suffix: String) async {
        let (model, _) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Furniture Round Trip")
        let doc = ArcusDocument(model: model, displayName: "Furniture Round Trip")
        NSDocumentController.shared.addDocument(doc)
        doc.makeWindowControllers()
        doc.showWindows()
        await pause(900)
        guard let s = doc.state, let w = s.window, let plan = view(s, kind: .floorPlan, level: s.model.levels.first?.name) else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        // The pieces, loaded as families (names apart from the template's own Base Cabinet) and placed in a row.
        let pieces: [(String, BIMModel?)] = [("QA Bookcase", FurnitureSamples.bookcaseModel()), ("QA Dining Table", FurnitureSamples.tableModel()),
                                             ("QA Base Cabinet", FurnitureSamples.baseCabinetModel())]
        var x = 0.0
        var placed: [ElementID] = []
        for (name, m) in pieces {
            guard let m, let piece = FurnitureTemplates.copy(m, name: name, category: m.furnitureSetup?.category ?? .furniture),
                  FurnitureFileLoad.load(piece, into: s) != nil, let type = FurnitureFileLoad.placementType(name, preferred: nil, s) else { continue }
            let width = piece.furnitureSetup?.family.types.first?.values["Width"]?.doubleValue ?? 1
            let at = Vec2(x + width / 2, 0)
            s.session.perform("Place \(name)") { tx in
                placed.append(tx.create(type.typeData?.instanceCategory ?? .furniture, data: .component(ComponentData(location: at)), typeID: type.id, levelID: plan.levelID))
            }
            x += width + 0.6
        }
        func detail(_ v: Element, _ d: DetailLevel) { s.session.perform("Detail Level") { tx in tx.update(v.id) { $0.view?.detailLevel = d } } }
        for d in [DetailLevel.coarse, .fine] {
            detail(plan, d)
            s.open(plan.id)
            _ = await waitForGraphics(s, plan.id)
            (s.canvases[plan.id] as? Canvas2DView)?.zoom(to: Rect2(min: Vec2(-0.4, -1.2), max: Vec2(x, 1.2)))
            await pause(700)
            await shot(w, "fm8-project-plan-\(d.rawValue.lowercased())-\(suffix)")
        }
        if let threeD = view(s, kind: .threeD) {
            for d in [DetailLevel.coarse, .fine] {
                detail(threeD, d)
                s.open(threeD.id)
                CommandRouter(state: s).run(.zoomExtents)
                await pause(1500)
                await shot(w, "fm8-project-3d-\(d.rawValue.lowercased())-\(suffix)")
            }
        }
        // Insert ▸ Load Furniture.
        s.open(plan.id)
        s.ribbonTab = .insert; s.ribbonShowsContextual = false
        await pause(400)
        await shot(w, "fm8-ribbon-insert-\(suffix)")
        s.presented = .fm8(.loadFurniture)
        await pause(1200)
        if let sheet = w.attachedSheet { await shot(sheet, "fm8-load-furniture-\(suffix)") } else { await shot(w, "fm8-load-furniture-\(suffix)") }
        s.presented = nil
        await pause(500)
        // Edit Family on the cabinet: its Furniture document, then the reload prompt in the project.
        if let cabinet = placed.last {
            s.session.selection.select([cabinet])
            s.ribbonShowsContextual = true
            await pause(500)
            await shot(w, "fm8-modify-edit-family-\(suffix)")
            let before = NSDocumentController.shared.documents.count
            CommandRouter(state: s).run(.familyEditor)
            await pause(1200)
            if NSDocumentController.shared.documents.count > before, let fdoc = NSDocumentController.shared.documents.last as? ArcusDocument,
               let fs = fdoc.state, fs.mode == .furniture, let fw = fs.window {
                fw.setContentSize(NSSize(width: 1440, height: 900)); fw.center()
                if let v = view(fs, kind: .threeD) { fs.open(v.id) }
                fs.ribbonTab = .create; fs.ribbonShowsContextual = false
                await pause(1500)
                await shot(fw, "fm8-edit-family-furniture-\(suffix)")
                fdoc.updateChangeCount(.changeCleared)
                fdoc.close()
                await pause(500)
            }
            let alert = FamilyReloadPrompt.alert("QA Base Cabinet")
            alert.beginSheetModal(for: w) { _ in }
            await pause(800)
            if let sheet = w.attachedSheet { await shot(sheet, "fm8-reload-prompt-\(suffix)") }
            w.endSheet(alert.window)
            await pause(400)
        }
        doc.updateChangeCount(.changeCleared)
        doc.close()
        await pause(500)
    }
}
