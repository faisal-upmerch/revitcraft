import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput

// F13: Print Setup, Print Preview and DWF/DWFx export (RevitCraft rc-app dialogs/mod.rs print setup and preview,
// export dialog `ExportKind::Dwf`).

struct PrintSetupDialog: View {
    let state: DocumentState
    @State private var setup = PrintSetup()
    var body: some View {
        DialogFrame(title: "Print Setup", subtitle: "Paper, zoom and colours for printing views, and what to leave out of prints, PDF and DWFx. Sheets print at their own paper size.", state: state) {
            let s = setup
            if state.f11Perform("Print Setup", { tx in tx.updateManageData { $0.printSetup = s } }) { state.presented = nil }
        } content: {
            Form {
                Section("Paper (views)") {
                    Picker("Size", selection: $setup.paper) { ForEach(PaperSize.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Picker("Orientation", selection: $setup.landscape) { Text("Landscape").tag(true); Text("Portrait").tag(false) }.pickerStyle(.radioGroup)
                    Picker("Zoom", selection: $setup.zoom) { ForEach(PrintSetup.Zoom.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.radioGroup)
                }
                Section("Appearance") {
                    Picker("Colors", selection: $setup.colors) { ForEach(PrintSetup.Colors.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                }
                Section("Options") {
                    Toggle("Hide reference/work planes", isOn: $setup.hideReferencePlanes)
                    Toggle("Hide scope boxes", isOn: $setup.hideScopeBoxes)
                    Toggle("Hide crop boundaries", isOn: $setup.hideCropBoundaries)
                    Toggle("Hide unreferenced view tags", isOn: $setup.hideUnreferencedViewTags)
                }
            }
        }
        .frame(minWidth: 480)
        .onAppear { setup = state.model.manageData.printSetup ?? PrintSetup() }
    }
}

/// Print Preview: the pages as they will print (rendered with Print Setup), with Print… and Close.
struct PrintPreviewDialog: View {
    let state: DocumentState
    let pdf: Data
    let title: String
    var body: some View {
        DialogFrame(title: "Print Preview", subtitle: title, okTitle: "Print…", state: state) {
            state.presented = nil
            F13Print.printPDF(pdf, title: title, state: state)
        } content: {
            PDFPreview(data: pdf).frame(minWidth: 720, minHeight: 480)
        }
    }
}

private struct PDFPreview: NSViewRepresentable {
    let data: Data
    func makeNSView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.backgroundColor = .underPageBackgroundColor
        v.document = PDFDocument(data: data)
        return v
    }
    func updateNSView(_ v: PDFView, context: Context) {}
}

struct ExportDWFxDialog: View {
    let state: DocumentState
    @State private var chosen: Set<ElementID> = []
    @State private var includeViews = false
    var items: [Element] { state.model.sheets + (includeViews ? state.model.views.filter { $0.view?.kind != .threeD } + state.model.schedules : []) }
    var body: some View {
        DialogFrame(title: "Export DWF/DWFx", subtitle: "Sheets and views as a DWFx package for markup and review. Print Setup's options apply.", okTitle: "Export…",
                    okDisabled: chosen.isEmpty, state: state) {
            export()
        } content: {
            HStack {
                Toggle("Include views and schedules", isOn: $includeViews)
                Spacer()
                Button("Select All") { chosen = Set(items.map(\.id)) }
                Button("Select None") { chosen = [] }
            }
            List(items, id: \.id) { e in
                Toggle(isOn: Binding(get: { chosen.contains(e.id) }, set: { if $0 { chosen.insert(e.id) } else { chosen.remove(e.id) } })) { Text(ViewTitles.qualified(e)) }
            }.frame(minHeight: 220)
        }
        .frame(minWidth: 520)
        .onAppear {
            if let a = state.activeView, a.sheet != nil || a.view != nil || a.schedule != nil { chosen = [a.id]; includeViews = a.sheet == nil } else { chosen = Set(state.model.sheets.map(\.id)) }
        }
    }

    func export() {
        let ids = items.filter { chosen.contains($0.id) }.map(\.id)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dwfx") ?? .data]
        panel.nameFieldStringValue = "\(state.model.projectInfo.projectName).dwfx"
        guard let w = state.window else { return }
        state.presented = nil
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let url = panel.url else { return }
            let m = state.model, o = PrintOptions(m.manageData.printSetup ?? PrintSetup())
            let cached = Dictionary(uniqueKeysWithValues: ids.compactMap { id in state.graphics.graphics(id).map { (id, $0) } })
            state.runBackground("Exporting DWFx") { progress, cancelled in
                let provider: @Sendable (Element) -> ViewGraphics? = { v in PrintFiltering.apply(cached[v.id] ?? ViewGraphicsBuilder(model: m, view: v).build(), o, model: m) }
                var pages: [DWFxPage] = []
                for (i, id) in ids.enumerated() {
                    if cancelled() { throw CancellationError() }
                    guard let e = m[id] else { continue }
                    if e.sheet != nil { var p = DWFxExporter.sheetPage(e, model: m, viewGraphics: provider); p.graphics = PrintFiltering.apply(p.graphics, o, model: m); pages.append(p) }
                    else if e.schedule != nil { pages.append(DWFxExporter.schedulePage(e, model: m)) }
                    else if let g = provider(e) { pages.append(DWFxExporter.viewPage(e, graphics: g)) }
                    progress(Double(i + 1) / Double(max(ids.count, 1)), e.name)
                }
                let (data, warnings) = DWFxExporter.write(pages, fonts: DWFxExporter.systemFonts())
                try data.write(to: url, options: .atomic)
                return (pages.count, warnings)
            } completion: { (r: Result<(Int, [String]), any Error>) in
                switch r {
                case .success(let (n, warnings)): state.show("Exported \(n) page\(n == 1 ? "" : "s") to \(url.lastPathComponent).\(warnings.isEmpty ? "" : " " + warnings.joined(separator: " "))")
                case .failure(let e): if !(e is CancellationError) { state.show("DWFx export failed: \(e.localizedDescription)", error: true) }
                }
            }
        }
    }
}

/// Print and Print Preview: the active view or sheet rendered to vector PDF with Print Setup, then printed through the
/// system print panel (or shown first).
@MainActor
enum F13Print {
    static func job(_ state: DocumentState, directory: URL) -> PDFExportJob? {
        guard let a = state.activeView, a.sheet != nil || a.view != nil || a.schedule != nil else { return nil }
        let s = state.model.manageData.printSetup ?? PrintSetup()
        var job = PDFExportJob(items: [PDFExportItem(elementID: a.id, kind: a.sheet != nil ? .sheet : .view)], outputDirectory: directory)
        job.combined = true
        job.combinedFileName = "Print.pdf"
        job.overwrite = .replace
        job.viewPaper = s.paper
        job.viewLandscape = s.landscape
        job.zoom = s.zoom == .fitToPage ? .fit : .actual
        job.hideCropBoundaries = s.hideCropBoundaries
        job.hideReferencePlanes = s.hideReferencePlanes
        job.hideScopeBoxes = s.hideScopeBoxes
        job.hideUnreferencedViewTags = s.hideUnreferencedViewTags
        job.colors = s.colors
        job.bookmarks = false
        return job
    }

    /// Renders the active view or sheet, then hands the PDF to `done` (main actor).
    static func render(_ state: DocumentState, _ done: @escaping @MainActor (Data, String) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ArcusPrint-\(UUID().uuidString)")
        guard let job = job(state, directory: dir), let a = state.activeView else { state.show("Open a view, sheet or schedule to print."); return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let m = state.model, title = ViewTitles.qualified(a)
        let cached = state.graphics.graphics(a.id)
        state.runBackground("Preparing print") { _, cancelled in
            let res = try await PDFExporter.export(m, job: job, graphics: { v in v.id == a.id ? cached : nil }, isCancelled: cancelled)
            defer { try? FileManager.default.removeItem(at: dir) }
            guard let url = res.files.first else { throw PDFExportError("Nothing to print.") }
            return try Data(contentsOf: url)
        } completion: { (r: Result<Data, any Error>) in
            switch r {
            case .success(let d): done(d, title)
            case .failure(let e): state.show("Print failed: \(e.localizedDescription)", error: true)
            }
        }
    }

    static func printPDF(_ data: Data, title: String, state: DocumentState) {
        guard let doc = PDFDocument(data: data), let page = doc.page(at: 0) else { return }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        let box = page.bounds(for: .mediaBox)
        info.paperSize = box.size
        info.orientation = box.width >= box.height ? .landscape : .portrait
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        guard let op = doc.printOperation(for: info, scalingMode: .pageScaleDownToFit, autoRotate: true) else { return }
        op.jobTitle = title
        if let w = state.window { op.runModal(for: w, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
    }
}
