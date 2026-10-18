import AppKit
import ArcusDomain

// W4-FAMED: screenshots of the Family Editor window (hooked from `screenshots()` with one line).
extension QAHarness {
    /// Opens a furniture family from the New Family template in the editor, captures it at the minimum (1000 pt) and a
    /// spacious (1440 pt) width with a form selected, then the Family Types sheet, and closes the window.
    static func familyEditorScreenshots(_ s: DocumentState, _ suffix: String) async {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Side Table"
        FamilyEditorWindowController.open(new: f, state: s)
        await pause(600)
        guard let wc = FamilyEditorWindowController.open.last, let w = wc.window else { return }
        for (width, height, label) in [(1000.0, 640.0, "min"), (1440.0, 900.0, "wide")] {
            w.setContentSize(NSSize(width: width, height: height))
            w.center()
            wc.model.select(nil)
            wc.model.zoomToFit()
            await pause(500)
            await shot(w, "family-editor-\(label)-\(suffix)")
            if let solid = wc.model.family.solids.first { wc.model.select(.solid(solid.id)) }
            await pause(400)
            await shot(w, "family-editor-form-selected-\(label)-\(suffix)")
        }
        wc.model.view = .front
        wc.model.select(nil)
        await pause(500)
        await shot(w, "family-editor-front-\(suffix)")
        // F1415: Back elevation, Default 3D orbited, a swept blend cut by a void revolve, a control, and sketch mode.
        wc.model.edit("QA content") { f in
            f.solids.append(FamilySolid(name: "Rail", profile: .sweep(FamilySweep(path: [FamilyPoint("-0.4", "-0.3"), FamilyPoint("0.4", "-0.3")],
                                                                                 profile: [FamilyPoint("0", "0"), FamilyPoint("0.08", "0"), FamilyPoint("0.08", "0.08"), FamilyPoint("0", "0.08")],
                                                                                 endProfile: [FamilyPoint("0", "0"), FamilyPoint("0.03", "0"), FamilyPoint("0.03", "0.03"), FamilyPoint("0", "0.03")])),
                                        zMin: .expr("0.2"), zMax: .expr("0.2")))
            f.solids.append(FamilySolid(name: "Bore", profile: .revolve(FamilyRevolve(profile: [FamilyPoint("0", "-0.1"), FamilyPoint("0.12", "-0.1"), FamilyPoint("0.12", "2"), FamilyPoint("0", "2")])),
                                        zMin: .expr("0"), zMax: .expr("0"), isVoid: true))
            f.controls.append(FamilyControl(position: FamilyPoint("0", "-0.6"), kind: .doubleHorizontal))
        }
        wc.model.view = .back
        await pause(500)
        await shot(w, "family-editor-back-\(suffix)")
        wc.model.perform(.feDefault3D)
        wc.model.orbit = FamilyOrbit(yaw: 120, pitch: -25)
        await pause(700)
        await shot(w, "family-editor-3d-orbit-\(suffix)")
        wc.model.view = .plan
        wc.model.perform(.feExtrusion)
        wc.model.addSketchVertex(.init(u: -0.2, v: -0.2)); wc.model.addSketchVertex(.init(u: 0.25, v: -0.2)); wc.model.addSketchVertex(.init(u: 0.1, v: 0.3))
        await pause(500)
        await shot(w, "family-editor-sketch-\(suffix)")
        wc.model.cancelSketch()
        wc.model.view = .plan
        wc.model.sheet = .familyTypes
        await pause(900)
        if let sheet = w.attachedSheet { await shot(sheet, "family-types-dialog-\(suffix)") }
        wc.model.sheet = nil
        await pause(400)
        w.close()
        await pause(300)
    }
}
