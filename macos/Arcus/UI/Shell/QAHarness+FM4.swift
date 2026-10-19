import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM4: screenshots of Furniture parts (hooked from `screenshots()` with one line, per appearance): a bookcase and a dining
// table built with the part operations the tools use, in plan, front elevation, a section and 3D; the contextual tabs
// of a selected panel and of the Panel, Shelf and Leg tools; and the Parts and Forms panels of Create.
extension QAHarness {
    static func fm4Screenshots(_ suffix: String) async {
        for (name, category) in [("Bookcase", FamilyTemplate.casework), ("Dining Table", .furniture)] {
            AppDelegate.shared?.newFurniture(name: name, category: category, template: nil)
            await pause(900)
            guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
            w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
            let isBook = category == .casework
            var ids: [String: ElementID] = [:]
            s.session.perform(isBook ? "Bookcase" : "Table") { tx in ids = isBook ? try FurnitureSamples.bookcase(in: tx) : try FurnitureSamples.table(in: tx) }
            s.session.perform(isBook ? "Plinth and Back" : "Legs and Aprons") { tx in
                if isBook { try FurnitureSamples.bookcaseFinish(in: tx, ids) } else { try FurnitureSamples.tableFinish(in: tx, ids) }
            }
            let slug = isBook ? "bookcase" : "table"
            // A section through the middle (looking at the side).
            s.session.perform("Section") { tx in
                var v = ViewData(kind: .section, scale: 12)
                v.planeOrigin = Vec3(-0.01, 0, 0); v.viewDirection = Vec2(1, 0); v.farClip = 2; v.detailLevel = .fine
                tx.create(.views, name: "Section 1", data: .view(v))
            }
            for (kind, view, label) in [(ViewKind.floorPlan, "Ref. Level", "plan"), (.elevation, "Front", "front"), (.section, "Section 1", "section"), (.threeD, "{3D}", "3d")] {
                guard let v = self.view(s, kind: kind, name: view) else { continue }
                s.open(v.id)
                if kind != .threeD { _ = await waitForGraphics(s, v.id); (s.canvases[v.id] as? Canvas2DView)?.zoomToFit() }
                await pause(kind == .threeD ? 1500 : 700)
                await shot(w, "fm4-\(slug)-\(label)-\(suffix)")
            }
            guard isBook, let plan = view(s, kind: .floorPlan, name: "Ref. Level"), let front = view(s, kind: .elevation, name: "Front") else {
                s.document?.updateChangeCount(.changeCleared); s.document?.close(); await pause(500); continue
            }
            // The contextual tab of a selected side: Modify | Panels (Edit Profile, Opening, Attach Top/Base…).
            s.open(front.id)
            _ = await waitForGraphics(s, front.id)
            if let left = ids["left"] { s.session.selection.select([left]) }
            s.ribbonShowsContextual = true
            await pause(600)
            await shot(w, "fm4-modify-panels-\(suffix)")
            s.session.selection.clear()
            // The tools' contextual tabs and Options Bars.
            for (cmd, viewID, label) in [(CommandID.furniturePanel, plan.id, "place-panel"), (.furnitureShelf, plan.id, "sketch-shelf"), (.furnitureLeg, plan.id, "place-leg"),
                                         (.furnitureDivider, front.id, "place-divider")] {
                s.open(viewID)
                _ = await waitForGraphics(s, viewID)
                CommandRouter(state: s).run(cmd)
                await pause(600)
                await shot(w, "fm4-\(label)-\(suffix)")
                s.cancelTool()
                await pause(300)
            }
            s.ribbonTab = .create; s.ribbonShowsContextual = false
            await pause(400)
            await shot(w, "fm4-ribbon-create-\(suffix)")
            s.document?.updateChangeCount(.changeCleared)
            s.document?.close()
            await pause(500)
        }
    }
}
