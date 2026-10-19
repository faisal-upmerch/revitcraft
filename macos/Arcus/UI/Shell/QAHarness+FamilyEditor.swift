import AppKit
import ArcusDomain
import ArcusApplication

// W4-FAMED: screenshots of the Family Editor window (hooked from `screenshots()` with one line).
// FES: the editor on the project window's shell; each size is also checked: every ribbon tab name is laid out at its full
// width inside the tab pill and no ribbon panel is clipped by the strip (QA steps "Family Editor shell …").
extension QAHarness {
    /// Opens a furniture family from the New Family template in the editor, captures it at the minimum size, at
    /// 1280 × 800 and at 1440 × 900 with a form selected, every ribbon tab and the views, then the Family Types sheet,
    /// and closes the window.
    static func familyEditorScreenshots(_ s: DocumentState, _ suffix: String) async {
        var f = FamilyTemplates.make(.furniture)
        f.name = "Side Table"
        FamilyEditorWindowController.open(new: f, state: s)
        await pause(600)
        guard let wc = FamilyEditorWindowController.open.last, let w = wc.window else { return }
        let min = FamilyEditorChrome.minimumSize
        for (size, label) in [(min, "min"), (NSSize(width: 1280, height: 800), "1280"), (NSSize(width: 1440, height: 900), "wide")] {
            w.setContentSize(size)
            w.center()
            wc.model.select(nil)
            wc.model.zoomToFit()
            await pause(500)
            await shot(w, "family-editor-\(label)-\(suffix)")
            for tab in FamilyRibbonTab.allCases {
                wc.model.chrome.ribbonTab = tab
                wc.model.chrome.measuredPanels = [:]
                await pause(250)
                await checkFamilyEditorShell(wc, "\(label) \(tab.rawValue) \(suffix)")
                if label == "1280" { await shot(w, "family-editor-ribbon-\(tab.rawValue.lowercased())-\(suffix)") }
            }
            wc.model.chrome.ribbonTab = .create
            if let solid = wc.model.family.solids.first { wc.model.select(.solid(solid.id)) }
            await pause(400)
            await checkFamilyEditorShell(wc, "\(label) selection \(suffix)")
            await shot(w, "family-editor-form-selected-\(label)-\(suffix)")
        }
        w.setContentSize(NSSize(width: 1280, height: 800))
        w.center()
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
        await checkFamilyEditorShell(wc, "sketch \(suffix)")
        await shot(w, "family-editor-sketch-\(suffix)")
        w.setContentSize(min)
        await pause(500)
        await checkFamilyEditorShell(wc, "min sketch \(suffix)")
        await shot(w, "family-editor-sketch-min-\(suffix)")
        w.setContentSize(NSSize(width: 1280, height: 800))
        wc.model.cancelSketch()
        wc.model.view = .plan
        wc.model.flex()
        await pause(500)
        await shot(w, "family-editor-flex-\(suffix)")
        wc.model.chrome.toggleBrowser()
        await pause(500)
        await shot(w, "family-editor-browser-hidden-\(suffix)")
        wc.model.chrome.toggleBrowser()
        wc.model.chrome.ribbonCollapsed = true
        await pause(400)
        await shot(w, "family-editor-ribbon-minimized-\(suffix)")
        wc.model.chrome.ribbonCollapsed = false
        wc.model.sheet = .familyTypes
        await pause(900)
        if let sheet = w.attachedSheet { await shot(sheet, "family-types-dialog-\(suffix)") }
        wc.model.sheet = nil
        await pause(400)
        w.close()
        await pause(300)
    }

    /// QA step: the ribbon's six tab names are laid out whole inside the tab pill, and every panel sits inside the
    /// ribbon strip (the owner's screenshot had no tab names and panels clipped under the toolbar).
    static func checkFamilyEditorShell(_ wc: FamilyEditorWindowController, _ label: String) async {
        await step("Family Editor shell \(label)") {
            let c = wc.model.chrome
            let m = ShellMetrics.arcus
            try check(wc.window?.toolbar == nil, "the window has a toolbar")
            let font = NSFont.systemFont(ofSize: 12, weight: .medium)
            for t in FamilyRibbonTab.allCases {
                guard let r = c.measuredTabs[t.rawValue] else { throw QAError("\(t.rawValue) tab is not laid out") }
                let need = (t.rawValue as NSString).size(withAttributes: [.font: font]).width - 1
                try check(r.width >= need && r.height >= 14, "\(t.rawValue) tab text is \(Int(r.width))×\(Int(r.height)) pt (needs \(Int(need)) wide)")
                try check(r.minY >= 0 && r.maxY <= CGFloat(m.margin + m.pillHeight), "\(t.rawValue) tab is outside the tab pill (y \(Int(r.minY))–\(Int(r.maxY)))")
            }
            let strip = c.measuredStrip, row = c.measuredPanelRow
            if !c.ribbonCollapsed {
                try check(strip.height >= CGFloat(m.ribbonHeight) - 0.5 && row.height >= Tokens.ribbonPanelHeight - 0.5, "ribbon strip \(Int(strip.height)) pt, panel row \(Int(row.height)) pt")
                try check(row.minY >= strip.minY - 0.5 && row.maxY <= strip.maxY + 0.5, "the panel row is outside the strip")
                for (title, r) in c.measuredPanels {
                    try check(r.minY >= row.minY - 0.5 && r.maxY <= row.maxY + 0.5, "\(title) panel is clipped (y \(Int(r.minY))–\(Int(r.maxY)), row \(Int(row.minY))–\(Int(row.maxY)))")
                }
            }
            return "tabs \(FamilyRibbonTab.allCases.map { "\($0.rawValue) \(Int(c.measuredTabs[$0.rawValue]?.width ?? 0))" }.joined(separator: ", ")); \(c.measuredPanels.count) panels in a \(Int(row.height)) pt row"
        }
    }
}
