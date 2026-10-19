import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// COMP: screenshots of the Component Library (hooked from `screenshots()` with one line, per appearance): the
// Components panel docked under Properties with a component previewed, the Component Browser window, Place Component
// over the base cabinet's front elevation, the one-click Add Hinges / Add Push-to-Open confirmation on a door, a handle
// replaced by a knob, and Insert Assembly. The dialogs are also in the dialog catalog (`compDialogCatalog`).
extension QAHarness {
    /// The Component Library's dialogs, for the dialog render test and the dialog captures.
    static func compDialogCatalog(_ f: DocumentState) -> [DialogCatalogEntry] {
        let m = f.model
        var d: [DialogCatalogEntry] = []
        func add(_ name: String, _ kind: DialogKind) { d.append(DialogCatalogEntry(name: name, kind: kind, furniture: true)) }
        if let door = m.elements(.furnitureFronts).filter({ $0.furnitureFront?.kind == .door }).min(by: { $0.id < $1.id }) {
            add("component-add-hinges", .comp(.action(.hinges, [door.id])))
            add("component-add-push-to-open", .comp(.action(.pushToOpen, [door.id])))
            if let bay = door.hostID { add("component-insert-assembly", .comp(.assembly(bay))) }
            add("component-save-selection", .comp(.saveSelection([door.id])))
        }
        add("component-hardware-rules", .comp(.hardwareRules))
        add("component-update", .comp(.update))
        if let first = ComponentLibrary.furniture.first { add("component-save-preset", .comp(.savePreset(first.id))) }
        return d
    }

    static func compScreenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Base Cabinet Components", category: .casework, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        var ids: [String: ElementID] = [:]
        s.session.perform("Base Cabinet") { tx in ids = try FurnitureSamples.baseCabinet(in: tx) }
        s.session.perform("Back, Kick and Dividers") { tx in try FurnitureSamples.baseCabinetInterior(in: tx, ids) }
        s.session.perform("Doors and Drawers") { tx in _ = try FurnitureSamples.baseCabinetFronts(in: tx) }
        let router = CommandRouter(state: s)
        let panel = ComponentPanelModel.of(s)
        s.ribbonTab = .create
        // The panel, docked, with a hinge previewed.
        router.run(.components)
        panel.query = "hinge 110"
        if let r = panel.results.first { panel.select(r) }
        if let front = s.model.views.first(where: { $0.name == "Front" }) { s.open(front.id); _ = await waitForGraphics(s, front.id) }
        await pause(900)
        await shot(w, "comp-panel-docked-\(suffix)")
        // 2D preview.
        panel.previewMode = .plan
        await pause(500)
        await shot(w, "comp-panel-preview-2d-\(suffix)")
        panel.previewMode = .threeD
        // Place Component over the front elevation.
        panel.query = "bar pull"
        if let r = panel.results.first { panel.select(r) }
        router.run(.componentPlace)
        await pause(700)
        await shot(w, "comp-place-tool-\(suffix)")
        router.run(.modify)
        // One-click hardware on a door.
        if let door = s.model.elements(.furnitureFronts).filter({ $0.furnitureFront?.kind == .door }).min(by: { $0.id < $1.id }) {
            s.session.selection.select([door.id])
            await pause(500)
            await shot(w, "comp-door-contextual-\(suffix)")
            for (a, label) in [(ComponentAction.hinges, "add-hinges"), (.pushToOpen, "add-push-to-open")] {
                s.presented = .comp(.action(a, [door.id]))
                await pause(800)
                if let sheet = w.attachedSheet { await shot(sheet, "comp-\(label)-\(suffix)") } else { await shot(w, "comp-\(label)-\(suffix)") }
                s.presented = nil
                await pause(400)
            }
            // Replace: a handle placed with the library, then replaced by a knob.
            if let bar = ComponentLibrary.component(named: FurnitureHardware.barPull), let knob = ComponentLibrary.component(named: FurnitureHardware.knob) {
                var placed: [ElementID] = []
                s.session.perform("Place Bar Pull") { tx in placed = try ComponentPlacement.place(bar, hostID: door.id, settings: ComponentSettings(face: .front, alignment: .bottom, offsetY: 0.06), in: tx) }
                s.session.selection.select(placed)
                panel.select(id: knob.id)
                ComponentPanelActions.replace(s)
                await pause(700)
                await shot(w, "comp-replace-\(suffix)")
            }
        }
        // The browser window.
        panel.query = ""
        ComponentBrowserWindow.show(s)
        await pause(1200)
        if let bw = NSApp.windows.first(where: { $0.title == "Component Browser" && $0.isVisible }) {
            await shot(bw, "comp-browser-\(suffix)")
            bw.close()
        }
        s.document?.updateChangeCount(.changeCleared)
        s.document?.close()
        await pause(400)
    }
}
