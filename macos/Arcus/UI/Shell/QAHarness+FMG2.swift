import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// FMG2: screenshots of the Furniture joint and fabrication gaps (hooked from `screenshots()` with one line, per
// appearance): the sample bookcase with a shaped side (Edit Profile) and its joints at Fine, the Joint tool with a
// joint the rules make picked and its Properties, a side's Properties listing its joints, the {3D} view exploded with
// the Explode Parts dialog and the view's Properties, and sheet F104 with its exploded view.
extension QAHarness {
    static func fmg2Screenshots(_ suffix: String) async {
        AppDelegate.shared?.newFurniture(name: "Bookcase Exploded", category: .casework, template: nil)
        await pause(900)
        guard let s = (NSDocumentController.shared.documents.last as? ArcusDocument)?.state, s.mode == .furniture, let w = s.window else { return }
        w.setContentSize(NSSize(width: 1440, height: 900)); w.center()
        var ids: [String: ElementID] = [:]
        s.session.perform("Bookcase") { tx in ids = try FurnitureSamples.bookcase(in: tx) }
        s.session.perform("Plinth and Back") { tx in try FurnitureSamples.bookcaseFinish(in: tx, ids) }
        // A shaped left side: its front top quarter cut away.
        if let left = ids["left"] {
            let i = 0.0254
            s.session.perform("Edit Profile") { tx in
                try FurniturePartOperations.setProfile(left, [Vec2(0, 0), Vec2(12 * i, 0), Vec2(12 * i, 72 * i), Vec2(6 * i, 72 * i), Vec2(6 * i, 66 * i), Vec2(0, 66 * i)], in: tx)
            }
        }
        // The Joint tool in Front: the side–top joint (made by the rules) picked, Properties showing it.
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
            await shot(w, "fmg2-joint-properties-\(suffix)")
            s.cancelTool()
            s.session.selection.select([left])
            await pause(700)
            await shot(w, "fmg2-part-joints-\(suffix)")
            s.session.selection.clear()
        }
        // {3D} exploded, the dialog and the view's Properties.
        if let v3 = view(s, kind: .threeD, name: "{3D}") ?? view(s, kind: .threeD) {
            s.open(v3.id)
            s.session.perform("Explode Parts") { tx in try FurnitureExplode.set(v3.id, on: true, in: tx) }
            await pause(1500)
            await shot(w, "fmg2-exploded-3d-\(suffix)")
            CommandRouter(state: s).run(.furnitureExplodeParts)
            await pause(800)
            if let sheet = w.attachedSheet { await shot(sheet, "fmg2-explode-dialog-\(suffix)") } else { await shot(w, "fmg2-explode-dialog-\(suffix)") }
            s.presented = nil
            await pause(500)
        }
        // F104 after Shop Drawings.
        CommandRouter(state: s).run(.furnitureShopDrawings)
        if let f104 = s.model.sheets.first(where: { $0.sheet?.number == FurnitureShopDrawings.details }) {
            s.open(f104.id)
            _ = await waitForGraphics(s, f104.id)
            (s.canvases[f104.id] as? Canvas2DView)?.zoomToFit()
            await pause(900)
            await shot(w, "fmg2-sheet-F104-\(suffix)")
        }
        s.document?.updateChangeCount(.changeCleared)
        s.document?.close()
        await pause(400)
    }
}
