import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM7: screenshots of Furniture fabrication (hooked from `screenshots()` with one line, per appearance): the sample base
// cabinet's Part List and Hardware Schedule, a Nesting view, sheets F101–F104 after Shop Drawings, the Fabricate tab,
// and the Stock Sheets, CNC Export and Check Parts dialogs.
extension QAHarness {
    static func fm7Screenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Base Cabinet Fabrication", category: .casework, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        var ids: [String: ElementID] = [:]
        s.session.perform("Base Cabinet") { tx in ids = try FurnitureSamples.baseCabinet(in: tx) }
        s.session.perform("Back, Kick and Dividers") { tx in try FurnitureSamples.baseCabinetInterior(in: tx, ids) }
        s.session.perform("Doors and Drawers") { tx in _ = try FurnitureSamples.baseCabinetFronts(in: tx) }
        let router = CommandRouter(state: s)
        s.ribbonTab = .fabricate
        s.ribbonShowsContextual = false
        // Schedules.
        for (cmd, label) in [(CommandID.furniturePartList, "part-list"), (.furnitureHardwareSchedule, "hardware-schedule"), (.furnitureCost, "cost")] {
            router.run(cmd)
            await pause(900)
            await shot(w, "fm7-\(label)-\(suffix)")
        }
        // Nesting: the plywood view.
        router.run(.furnitureNesting)
        if let v = FurnitureNestingViews.views(s.model).first(where: { $0.name.hasPrefix("Plywood 3/4") }) ?? FurnitureNestingViews.views(s.model).first {
            s.open(v.id)
            _ = await waitForGraphics(s, v.id)
            (s.canvases[v.id] as? Canvas2DView)?.zoomToFit()
            await pause(700)
            await shot(w, "fm7-nesting-\(suffix)")
        }
        // The shop drawing set.
        router.run(.furnitureShopDrawings)
        for number in ["F101", "F102", "F103", "F104"] {
            guard let sheet = s.model.sheets.first(where: { $0.sheet?.number == number }) else { continue }
            s.open(sheet.id)
            _ = await waitForGraphics(s, sheet.id)
            (s.canvases[sheet.id] as? Canvas2DView)?.zoomToFit()
            await pause(900)
            await shot(w, "fm7-sheet-\(number)-\(suffix)")
        }
        // Dialogs.
        for (dialog, label) in [(FM7Dialog.stockSheets, "stock-sheets"), (.cncExport, "cnc-export"), (.checkParts, "check-parts"), (.hardwareCatalog, "hardware-catalog")] {
            s.presented = .fm7(dialog)
            await pause(800)
            if let sheet = w.attachedSheet { await shot(sheet, "fm7-\(label)-\(suffix)") } else { await shot(w, "fm7-\(label)-\(suffix)") }
            s.presented = nil
            await pause(500)
        }
        s.document?.updateChangeCount(.changeCleared)
        s.document?.close()
        await pause(400)
    }
}
