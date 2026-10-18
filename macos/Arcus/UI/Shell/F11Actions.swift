import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusCAD
import ArcusOutput
import ArcusPersistence

// F11–F13 actions that need the window: the active design option, Select Joined Elements, saved selections and the
// File ▸ Export commands (STL, gbXML, Room/Area Report, Family Types, DXF with AIA layers).

@MainActor
struct F11Actions {
    let state: DocumentState

    // MARK: Design options

    /// Makes `option` the one being edited (nil = main model). New elements join it, and the active view shows it.
    func setActiveOption(_ option: ElementID?) {
        let m = state.model
        state.session.activeDesignOptionID = option.flatMap { m[$0]?.designOption != nil ? $0 : nil }
        guard let o = state.session.activeDesignOptionID, let opt = m[o], let set = opt.designOption?.setName else {
            state.show("Editing the main model.")
            return
        }
        if let v = state.activeViewID, let vd = m[v]?.view, vd.kind.isModelView, vd.templateID == nil {
            let shown = vd.designOptions[set] ?? DesignOptionEditing.sets(m).first { $0.name == set }?.options.first?.id
            if shown != o { state.f11Perform("Show Option") { tx in tx.update(v) { $0.view?.designOptions[set] = o } } }
        }
        state.show("Editing design option \(DesignOptionEditing.label(opt)). New elements join it.")
    }

    // MARK: Selection

    /// Select Joined Elements: walls joined at the ends of the selected walls (L, T and straight joins) and the
    /// elements joined to the selection with Join Geometry.
    func selectJoined() {
        let m = state.model
        var out = state.session.selection.ids
        let tol = 0.001
        for id in state.session.selection.ids {
            guard let e = m[id], let seg = e.wall?.location.asSegment else { continue }
            for o in WallGeometry.joinCandidates(e, m) where !out.contains(o.id) {
                guard let os = o.wall?.location.asSegment else { continue }
                if seg.distance(to: os.start) < tol || seg.distance(to: os.end) < tol || os.distance(to: seg.start) < tol || os.distance(to: seg.end) < tol { out.append(o.id) }
            }
        }
        let picked = Set(state.session.selection.ids)
        for c in m.elements(.constraints) {
            guard let d = c.constraint, d.kind == .join else { continue }
            let ids = d.references.compactMap(\.elementID)
            if ids.contains(where: picked.contains) { for i in ids where !out.contains(i) { out.append(i) } }
        }
        let added = out.count - state.session.selection.ids.count
        state.session.selection.select(out)
        state.show(added == 0 ? "No joined elements to add." : "Added \(added) joined element\(added == 1 ? "" : "s").")
    }

    func saveSelection() {
        let ids = state.session.selection.ids
        state.requestText(prompt: "Name of the saved selection", initial: SavedSelections.nextName(state.model)) { name in
            guard let name else { return }
            if state.f11Perform("Save Selection", { tx in try SavedSelections.save(ids, name: name, in: tx) }) { state.show("Saved \(ids.count) element\(ids.count == 1 ? "" : "s") as “\(name)”.") }
        }
    }

    func rotateTrueNorth() {
        let current = String(format: "%.2f", Angle.degrees(state.model.projectInfo.trueNorthAngle))
        state.requestText(prompt: "Angle from project north to true north (degrees, counter-clockwise)", initial: current) { text in
            guard let text, let deg = Double(text.replacingOccurrences(of: "°", with: "").trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            state.f11Perform("Rotate True North") { tx in
                guard let pid = tx.model.projectInfoElement?.id else { return }
                tx.update(pid) { $0.projectInfo?.trueNorthAngle = Angle.radians(deg) }
            }
        }
    }

    func newKeynoteLegend() {
        var made: ElementID?
        state.f11Perform("Keynote Legend") { tx in
            let n = (tx.model.schedules.filter { $0.schedule?.kind == .keynoteLegend }.count)
            made = tx.create(.schedules, name: n == 0 ? "Keynote Legend" : "Keynote Legend \(n + 1)", data: .schedule(KeynoteLegend.definition()))
        }
        if let made { state.open(made) }
    }

    // MARK: Export

    /// A save panel as a sheet; `write` returns a status message or throws.
    func save(_ title: String, name: String, types: [UTType], accessory: NSView? = nil, _ write: @escaping (URL) throws -> String) {
        let panel = NSSavePanel()
        panel.title = title
        panel.allowedContentTypes = types
        panel.nameFieldStringValue = name
        panel.accessoryView = accessory
        let finish: (NSApplication.ModalResponse) -> Void = { r in
            guard r == .OK, let url = panel.url else { return }
            do { state.show(try write(url)) } catch { state.show("Export failed: \(error.localizedDescription)", error: true) }
        }
        if let w = state.window { panel.beginSheetModal(for: w, completionHandler: finish) } else { finish(panel.runModal()) }
    }

    static func accessory(_ label: String, _ items: [String], selected: Int = 0) -> (NSView, NSPopUpButton) {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItems(withTitles: items)
        popup.selectItem(at: selected)
        let row = NSStackView(views: [NSTextField(labelWithString: label), popup])
        row.orientation = .horizontal
        row.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        return (row, popup)
    }

    func exportSTL() {
        let m = state.model
        save("Export STL", name: "\(m.projectInfo.projectName).stl", types: [UTType(filenameExtension: "stl") ?? .data]) { url in
            let (data, n) = STLExporter.write(m)
            try data.write(to: url, options: .atomic)
            return "Exported \(n) triangles to \(url.lastPathComponent)."
        }
    }

    func exportGbXML() {
        let m = state.model
        save("Export gbXML", name: "\(m.projectInfo.projectName).xml", types: [.xml]) { url in
            let (text, n) = GbXMLExporter.write(m)
            try text.write(to: url, atomically: true, encoding: .utf8)
            return "Exported \(n) space\(n == 1 ? "" : "s") to \(url.lastPathComponent)."
        }
    }

    func exportRoomAreaReport() {
        let m = state.model
        let (row, popup) = Self.accessory("Format:", RoomAreaReport.Format.allCases.map(\.rawValue))
        save("Room/Area Report", name: "Room Area Report.html", types: [.html, .commaSeparatedText], accessory: row) { url in
            let format = RoomAreaReport.Format.allCases[max(0, popup.indexOfSelectedItem)]
            var dest = url
            let ext = format == .html ? "html" : "csv"
            if dest.pathExtension.lowercased() != ext { dest = dest.deletingPathExtension().appendingPathExtension(ext) }
            let (text, n) = RoomAreaReport.write(m, format: format)
            try text.write(to: dest, atomically: true, encoding: .utf8)
            return "Exported \(n) room\(n == 1 ? "" : "s") and areas to \(dest.lastPathComponent)."
        }
    }

    /// The family of this project's most recently opened Family Editor window.
    var editedFamily: FamilyDefinition? {
        FamilyEditorWindowController.open.last { $0.model.state === state }?.model.family
    }

    func exportFamilyTypes() {
        guard let f = editedFamily else { state.show("Open a family in the Family Editor first."); return }
        let (row, popup) = Self.accessory("Format:", ["Type catalog text (## headings)", "Arcus type catalog (CSV)"])
        save("Export Family Types", name: "\(f.name).txt", types: [.plainText, .commaSeparatedText], accessory: row) { url in
            if popup.indexOfSelectedItem == 1 { try TypeCatalog.export(f).write(to: url, options: .atomic) }
            else { try FamilyTypesExport.write(f).write(to: url, atomically: true, encoding: .utf8) }
            return "Exported \(f.types.count) type\(f.types.count == 1 ? "" : "s") of \(f.name)."
        }
    }

    /// Export DXF of the active view, with layers named by the AIA CAD layer guidelines (RevitCraft's default) or by category.
    func exportDXF() {
        guard let v = state.activeViewID, let g = state.graphics.graphics(v), let view = state.model[v] else { state.show("Open a 2D view to export DXF."); return }
        let m = state.model
        let setup = PrintOptions(m.manageData.printSetup ?? PrintSetup())
        let (row, popup) = Self.accessory("Layers:", DXFLayerStandard.allCases.map(\.rawValue))
        save("Export DXF", name: "\(view.name).dxf", types: [UTType(filenameExtension: "dxf") ?? .data], accessory: row) { url in
            let layers = DXFLayerStandard.allCases[max(0, popup.indexOfSelectedItem)]
            var o = setup
            o.colors = .color
            let data = DXFWriter.write(PrintFiltering.apply(g, o, model: m), units: m.units.system == .metric ? .millimeters : .inches, layers: layers, model: m)
            try data.write(to: url, options: .atomic)
            return "Exported \(url.lastPathComponent)."
        }
    }
}
