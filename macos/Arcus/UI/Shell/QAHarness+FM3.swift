import AppKit
import ArcusDomain
import ArcusApplication

// FM3: screenshots of a new Furniture document (hooked from `screenshots()` with one line, per appearance): the plan,
// the front elevation, the 3D view, every Furniture ribbon tab, Family Types and Category and Parameters, Flex, and
// the plan after Width changes.
extension QAHarness {
    static func furnitureScreenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Side Table", category: .furniture, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        if let plan = view(s, kind: .floorPlan, name: "Ref. Level") {
            s.open(plan.id)
            _ = await waitForGraphics(s, plan.id)
            (s.canvases[plan.id] as? Canvas2DView)?.zoomToFit()
            await pause(600)
            await shot(w, "furniture-plan-\(suffix)")
            // A plane selected: its labelled Width shows as an editable value.
            if let right = s.model.elements(.referencePlanes).first(where: { $0.name == "Right" }) {
                s.session.selection.select([right.id])
                await pause(500)
                await shot(w, "furniture-plane-selected-\(suffix)")
                s.session.selection.clear()
            }
        }
        if let front = view(s, kind: .elevation, name: "Front") {
            s.open(front.id)
            _ = await waitForGraphics(s, front.id)
            (s.canvases[front.id] as? Canvas2DView)?.zoomToFit()
            await pause(600)
            await shot(w, "furniture-front-\(suffix)")
        }
        if let v3 = view(s, kind: .threeD, name: "{3D}") {
            s.open(v3.id)
            await pause(1500)
            await shot(w, "furniture-3d-\(suffix)")
        }
        for tab in RibbonTab.tabs(for: .furniture) {
            s.ribbonTab = tab; s.ribbonShowsContextual = false
            await pause(300)
            await shot(w, "furniture-ribbon-\(tab.rawValue.lowercased())-\(suffix)")
        }
        s.ribbonTab = .create
        for (dialog, name) in [(FM3Dialog.familyTypes, "furniture-family-types"), (.category, "furniture-category"), (.flex(FurnitureParameters.flex(s.model)), "furniture-flex")] {
            s.presented = .fm3(dialog)
            await pause(800)
            if let sheet = w.attachedSheet { await shot(sheet, "\(name)-\(suffix)") } else { await shot(w, "\(name)-\(suffix)") }
            s.presented = nil
            await pause(500)
        }
        // Width 48": the planes move with the parameter.
        s.session.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(48 * 0.0254), in: tx) }
        if let plan = view(s, kind: .floorPlan, name: "Ref. Level") {
            s.open(plan.id)
            _ = await waitForGraphics(s, plan.id)
            await pause(600)
            await shot(w, "furniture-plan-width48-\(suffix)")
        }
        s.document?.updateChangeCount(.changeCleared)
        s.document?.close()
        await pause(500)
    }
}
