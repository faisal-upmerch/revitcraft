import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusOutput
import ArcusCAD

// DWG: File ▸ Export ▸ CAD Formats ▸ DWG… Writes the chosen views and sheets as 2D DWG drawings, one file each, as
// Revit's DWG export does: Arcus's DXF writer (AIA or category layers, Print Setup's hide options) and then the bundled
// acadrust engine, which reads every file back before saving it (DWGExporter.swift).

/// Remembered choices (per Mac).
enum DWGExportPreferences {
    static let versionKey = "dwg.export.version"
    static let layersKey = "dwg.export.layers"
}

struct ExportDWGDialog: View {
    let state: DocumentState
    @State private var chosen: Set<ElementID> = []
    @State private var includeViews = false
    @AppStorage(DWGExportPreferences.versionKey) private var versionCode = DWGExportVersion.default.rawValue
    @AppStorage(DWGExportPreferences.layersKey) private var layersName = DXFLayerStandard.allCases[0].rawValue

    var items: [Element] { state.model.sheets + (includeViews ? state.model.views.filter { $0.view?.kind != .threeD } : []) }
    var version: DWGExportVersion { DWGExportVersion(rawValue: versionCode) ?? .default }
    var layers: DXFLayerStandard { DXFLayerStandard(rawValue: layersName) ?? DXFLayerStandard.allCases[0] }

    var body: some View {
        let list = items
        DialogFrameWithActions(title: "Export DWG", icon: "square.and.arrow.up", tint: .teal, subtitle: "2D DWG drawings, one file per view or sheet. Print Setup's hide options apply.",
                    okTitle: "Export…", okDisabled: chosen.isEmpty, disabledReason: "Check at least one sheet or view", labelWidth: 90, state: state) {
            export()
        } content: {
            DialogSection(includeViews ? "Sheets and views" : "Sheets", boxed: false) {
                DialogCheckList(items: list.map { e in DialogCheckItem(id: e.id, title: ViewTitles.qualified(e), icon: e.sheet != nil ? "doc.richtext" : "rectangle.on.rectangle") },
                                checked: $chosen, maxRows: 7, noun: "items", emptyTitle: "No sheets", emptyMessage: "Create a sheet, or include views.", emptyIcon: "doc.richtext")
            } accessory: {
                Toggle("Include views", isOn: $includeViews)
            }
            DialogSection("Format", footnote: "Model views are written at full size in \(state.model.units.system == .metric ? "millimetres" : "inches"); sheets at paper size in millimetres. Each file is read back before it is saved.") {
                DialogRow("Version") {
                    Picker("", selection: $versionCode) { ForEach(DWGExportVersion.allCases) { Text($0.title).tag($0.rawValue) } }.labelsHidden().fixedSize()
                }
                DialogRow("Layers") {
                    Picker("", selection: $layersName) { ForEach(DXFLayerStandard.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }.labelsHidden().fixedSize()
                }
            }
        } actions: {
            Button("Select All") { chosen = Set(list.map(\.id)) }.disabled(list.isEmpty)
            Button("Select None") { chosen = [] }.disabled(chosen.isEmpty)
        }
        .onAppear {
            if let a = state.activeView, a.sheet != nil || (a.view != nil && a.view?.kind != .threeD) { chosen = [a.id]; includeViews = a.sheet == nil }
            else { chosen = Set(state.model.sheets.map(\.id)) }
        }
    }

    func export() {
        let ids = items.filter { chosen.contains($0.id) }.map(\.id)
        guard !ids.isEmpty, let w = state.window else { return }
        let m = state.model
        state.presented = nil
        let names = Self.fileNames(ids.compactMap { m[$0] })
        if ids.count == 1 {
            let panel = NSSavePanel()
            panel.title = "Export DWG"
            panel.allowedContentTypes = [UTType(filenameExtension: "dwg") ?? .data]
            panel.nameFieldStringValue = names[ids[0]] ?? "Drawing.dwg"
            panel.beginSheetModal(for: w) { r in
                guard r == .OK, let url = panel.url else { return }
                run([(ids[0], url)])
            }
        } else {
            let panel = NSOpenPanel()
            panel.title = "Export DWG"
            panel.message = "Choose a folder for \(ids.count) DWG files. Files with the same names are replaced."
            panel.prompt = "Export"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.canCreateDirectories = true
            panel.beginSheetModal(for: w) { r in
                guard r == .OK, let dir = panel.url else { return }
                run(ids.map { ($0, dir.appendingPathComponent(names[$0] ?? "Drawing.dwg")) })
            }
        }
    }

    /// One file name per view or sheet ("A101 - Ground Floor.dwg", "Floor Plan - Level 1.dwg"), made unique.
    static func fileNames(_ elements: [Element]) -> [ElementID: String] {
        var used: Set<String> = []
        var out: [ElementID: String] = [:]
        for e in elements {
            let base = DWGExporter.fileName(e.sheet != nil ? ViewTitles.sheetLabel(e) : ViewTitles.qualified(e))
            var name = base, n = 2
            while used.contains(name.lowercased()) {
                name = (base as NSString).deletingPathExtension + " (\(n)).dwg"; n += 1
            }
            used.insert(name.lowercased())
            out[e.id] = name
        }
        return out
    }

    func run(_ jobs: [(ElementID, URL)]) {
        let m = state.model
        var printOptions = PrintOptions(m.manageData.printSetup ?? PrintSetup())
        printOptions.colors = .color // as the DXF export: layers keep their colours; Print Setup's hide options still apply
        let o = printOptions
        let version = version, layers = layers
        let helper = BundledDWGHelpers.standard.acadrust
        let units: CADUnits = m.units.system == .metric ? .millimeters : .inches
        let cached = Dictionary(uniqueKeysWithValues: jobs.compactMap { id, _ in state.graphics.graphics(id).map { (id, $0) } })
        state.runBackground("Exporting DWG") { progress, cancelled in
            let views: @Sendable (Element) -> ViewGraphics? = { v in PrintFiltering.apply(cached[v.id] ?? ViewGraphicsBuilder(model: m, view: v).build(), o, model: m) }
            var written: [String] = []
            var failed: [String] = []
            for (i, (id, url)) in jobs.enumerated() {
                if cancelled() { throw CancellationError() }
                guard let e = m[id] else { continue }
                progress(Double(i) / Double(max(jobs.count, 1)), e.name)
                let dxf: Data
                if e.sheet != nil {
                    let g = PrintFiltering.apply(DWFxExporter.sheetPage(e, model: m, viewGraphics: views).graphics, o, model: m)
                    dxf = DXFWriter.write(g, units: .millimeters, layers: layers, model: m)
                } else if let g = views(e) {
                    dxf = DXFWriter.write(g, units: units, layers: layers, model: m)
                } else { continue }
                do {
                    try DWGExporter.write(dxf: dxf, to: url, version: version, helper: helper, isCancelled: cancelled)
                    written.append(url.lastPathComponent)
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failed.append("\(url.lastPathComponent): \(error)")
                }
            }
            progress(1, "")
            return (written, failed)
        } completion: { (r: Result<([String], [String]), any Error>) in
            switch r {
            case .success(let (written, failed)):
                if failed.isEmpty {
                    state.show(written.count == 1 ? "Exported \(written[0]) (\(version.title))." : "Exported \(written.count) DWG files (\(version.title)).")
                } else {
                    state.presented = .report("DWG Export", (written.isEmpty ? "" : "Exported \(written.count) of \(jobs.count) files.\n\n")
                                                + "Not exported:\n" + failed.joined(separator: "\n")
                                                + "\n\nYou can export the same views and sheets as DXF instead (File ▸ Export ▸ CAD Formats ▸ DXF).")
                }
            case .failure(let e):
                if !(e is CancellationError) { state.show("DWG export failed: \(e.localizedDescription)", error: true) }
            }
        }
    }
}
