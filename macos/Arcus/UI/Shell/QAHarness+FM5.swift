import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FM5: screenshots of bays, doors, drawers and hardware (hooked from `screenshots()` with one line, per appearance): a
// base cabinet with two doors and three drawers built with the operations the tools use, its bays tagged in the Front
// elevation, in plan, front elevation, a section through the drawers and 3D; the contextual Modify | Doors tab; and the
// Door and Drawer tools' Options Bars.
extension QAHarness {
    static func fm5Screenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Base Cabinet", category: .casework, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        var ids: [String: ElementID] = [:]
        s.session.perform("Base Cabinet") { tx in ids = try FurnitureSamples.baseCabinet(in: tx) }
        s.session.perform("Back, Kick and Dividers") { tx in try FurnitureSamples.baseCabinetInterior(in: tx, ids) }
        var fronts: [String: [ElementID]] = [:]
        s.session.perform("Doors and Drawers") { tx in fronts = try FurnitureSamples.baseCabinetFronts(in: tx) }
        guard let front = view(s, kind: .elevation, name: "Front") else { return }
        // Bay Tags in the Front elevation, as Tag on Placement puts them.
        s.session.perform("Tag Bays") { tx in
            guard let map = FurnitureSketchMap.of(tx.model[front.id]?.view), let tag = TagTool.defaultTagType(for: .furnitureBays, tx.model) else { return }
            for b in tx.model.elements(.furnitureBays) where b.furnitureBay?.division == nil {
                guard let d = b.furnitureBay, let o = d.opening else { continue }
                let r = FurnitureBays.outline(o, d.face)
                tx.create(.tags, data: .tag(TagData(taggedID: b.id, head: map.toView(Vec2(r.center.x, r.min.y + r.height * 0.32)))), typeID: tag, ownerViewID: front.id)
            }
        }
        // A section through the drawer stack, looking at its side.
        s.session.perform("Section") { tx in
            var v = ViewData(kind: .section, scale: 12)
            v.planeOrigin = Vec3(-0.01, 0, 0); v.viewDirection = Vec2(1, 0); v.farClip = 2; v.detailLevel = .fine
            tx.create(.views, name: "Section 1", data: .view(v))
        }
        for (kind, name, label) in [(ViewKind.floorPlan, "Ref. Level", "plan"), (.elevation, "Front", "front"), (.section, "Section 1", "section"), (.threeD, "{3D}", "3d")] {
            guard let v = self.view(s, kind: kind, name: name) else { continue }
            s.open(v.id)
            if kind != .threeD { _ = await waitForGraphics(s, v.id); (s.canvases[v.id] as? Canvas2DView)?.zoomToFit() }
            await pause(kind == .threeD ? 1500 : 700)
            await shot(w, "fm5-cabinet-\(label)-\(suffix)")
        }
        // A selected door: Modify | Doors (Flip Hinge, Pick New Host, Select Hardware) and its flip control.
        s.open(front.id)
        _ = await waitForGraphics(s, front.id)
        if let door = fronts["leftDoor"]?.first { s.session.selection.select([door]) }
        s.ribbonShowsContextual = true
        await pause(600)
        await shot(w, "fm5-modify-doors-\(suffix)")
        s.session.selection.clear()
        // The tools' Options Bars.
        for (cmd, label) in [(CommandID.furnitureDoor, "place-door"), (.furnitureDrawer, "place-drawer"), (.furnitureBay, "place-bay")] {
            CommandRouter(state: s).run(cmd)
            await pause(600)
            await shot(w, "fm5-\(label)-\(suffix)")
            s.cancelTool()
            await pause(300)
        }
        s.ribbonTab = .create; s.ribbonShowsContextual = false
        await pause(400)
        await shot(w, "fm5-ribbon-create-\(suffix)")
        s.document?.updateChangeCount(.changeCleared)
        s.document?.close()
        await pause(500)
    }
}
