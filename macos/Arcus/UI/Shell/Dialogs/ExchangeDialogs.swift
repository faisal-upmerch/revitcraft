import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusOutput
import ArcusIFC
import ArcusCAD
import ArcusServices

enum DWGStatus {
    static var reason: String { DWGProviders.current.unavailableReason ?? "DWG import is available (\(DWGProviders.current.sdkName) \(DWGProviders.current.sdkVersion ?? ""))." }
    /// W2-DWG: who does the conversion, shown in the DWG link/import dialog.
    static var conversionNote: String {
        let p = DWGProviders.current
        if let e = p as? ExternalConverterDWGProvider { return "The DWG is converted to DXF on this Mac by \(e.converter.displayName), a separately installed third-party program." }
        return ""
    }
}

// MARK: - PDF

struct ExportPDFDialog: View {
    let state: DocumentState
    @State private var chosen: Set<ElementID> = []
    @State private var combined = true
    @State private var naming = 0
    @State private var fileName = "Drawing Set.pdf"
    @State private var includeViews = false
    var items: [Element] { state.model.sheets + (includeViews ? state.model.views.filter { $0.view?.kind != .threeD || true } : []) }

    var body: some View {
        DialogFrame(title: "Export PDF", subtitle: "Vector PDF with live text, bookmarks and links between view markers and sheets.", okTitle: "Export…", okDisabled: chosen.isEmpty, state: state) {
            chooseFolder()
        } content: {
            HStack {
                Toggle("Include views", isOn: $includeViews)
                Spacer()
                Button("Select All") { chosen = Set(items.map(\.id)) }
                Button("Select None") { chosen = [] }
            }
            List(items, id: \.id) { e in
                Toggle(isOn: Binding(get: { chosen.contains(e.id) }, set: { if $0 { chosen.insert(e.id) } else { chosen.remove(e.id) } })) {
                    Text(e.sheet.map { "\($0.number) – \(e.name)" } ?? "\(e.view?.kind.rawValue ?? "View"): \(e.name)")
                }
            }.frame(minHeight: 220)
            Picker("Output", selection: $combined) { Text("One combined PDF").tag(true); Text("Separate files").tag(false) }.pickerStyle(.radioGroup)
            if combined { FormRow(label: "File name") { TextField("", text: $fileName).textFieldStyle(.roundedBorder) } }
            else {
                Picker("File naming", selection: $naming) { Text("Sheet number – Sheet name").tag(0); Text("View or sheet name").tag(1); Text("Project number – Sheet number").tag(2) }
            }
        }
        .frame(minWidth: 560, idealWidth: 560)
        .onAppear { chosen = Set(state.model.sheets.map(\.id)); fileName = "\(state.model.projectInfo.projectName).pdf" }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        guard let w = state.window else { return }
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let dir = panel.url else { return }
            let m = state.model
            let items = items.filter { chosen.contains($0.id) }.map { PDFExportItem(elementID: $0.id, kind: $0.sheet != nil ? .sheet : .view) }
            var job = PDFExportJob(items: items, outputDirectory: dir)
            job.combined = combined
            job.combinedFileName = fileName.hasSuffix(".pdf") ? fileName : fileName + ".pdf"
            job.naming = naming == 0 ? .sheetNumberAndName : naming == 1 ? .viewName : .custom("{Project Number} - {Sheet Number}")
            job.creator = "Arcus \(AppVersionInfo.current.marketingVersion)"
            let conflicts = PDFExporter.conflicts(m, job: job)
            if !conflicts.isEmpty {
                let alert = NSAlert()
                alert.messageText = "\(conflicts.count) file(s) already exist."
                alert.informativeText = conflicts.prefix(5).map(\.lastPathComponent).joined(separator: "\n")
                alert.addButton(withTitle: "Replace")
                alert.addButton(withTitle: "Keep Both")
                alert.addButton(withTitle: "Skip Existing")
                alert.addButton(withTitle: "Cancel")
                switch alert.runModal() {
                case .alertFirstButtonReturn: job.overwrite = .replace
                case .alertSecondButtonReturn: job.overwrite = .uniquify
                case .alertThirdButtonReturn: job.overwrite = .skip
                default: return
                }
            }
            state.presented = nil
            let finalJob = job
            state.runBackground("Exporting PDF") { progress, cancelled in
                try await PDFExporter.export(m, job: finalJob, progress: { p, label in progress(p, label) }, isCancelled: cancelled)
            } completion: { (r: Result<PDFExportResult, any Error>) in
                switch r {
                case .success(let res):
                    DiagnosticsLog.shared.recordTiming("PDF export", seconds: res.elapsed)
                    state.show("Exported \(res.pageCount) page(s) to \(res.files.count) file(s) in \(String(format: "%.1f", res.elapsed)) s.")
                    if let first = res.files.first { NSWorkspace.shared.activateFileViewerSelecting([first]) }
                case .failure(let e): state.show("PDF export failed: \(e)", error: true)
                }
            }
        }
    }
}

// MARK: - IFC export

struct ExportIFCDialog: View {
    let state: DocumentState
    @State private var options = IFCExportOptions()
    @State private var visibleOnly = false
    var body: some View {
        DialogFrame(title: "Export IFC", subtitle: "Architectural subset. Unsupported items are listed in the export report.", okTitle: "Export…", state: state) {
            export()
        } content: {
            Form {
                Picker("Schema", selection: $options.schema) {
                    Text("IFC4 Reference View").tag(IFCSchema.ifc4); Text("IFC2x3 Coordination View 2.0").tag(IFCSchema.ifc2x3)
                }
                Toggle("Only elements visible in the active view", isOn: $visibleOnly)
                Toggle("Split by storey (one file per level)", isOn: $options.splitByStorey)
                Toggle("Base quantities", isOn: $options.includeBaseQuantities)
                Toggle("Property sets (common and Arcus parameters)", isOn: $options.includePropertySets)
                Toggle("Classification", isOn: $options.includeClassification)
                Picker("Coordinate base", selection: $options.coordinateBase) {
                    Text("Internal origin").tag(IFCCoordinateBase.internalOrigin); Text("Project base point").tag(IFCCoordinateBase.projectBasePoint); Text("Shared coordinates (survey point)").tag(IFCCoordinateBase.sharedCoordinates)
                }
                TextField("Author", text: $options.authorName)
                TextField("Organization", text: $options.organization)
            }
        }
        .frame(minWidth: 520, idealWidth: 520)
        .onAppear { options.organization = state.model.projectInfo.organization; options.fileName = "\(state.model.projectInfo.projectName).ifc" }
    }
    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ifc") ?? .data]
        panel.nameFieldStringValue = options.fileName
        guard let w = state.window else { return }
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let url = panel.url else { return }
            var o = options
            o.fileName = url.lastPathComponent
            o.visibleInViewID = visibleOnly ? state.activeViewID : nil
            o.applicationVersion = AppVersionInfo.current.marketingVersion
            let m = state.model
            let dir = url.deletingLastPathComponent()
            state.presented = nil
            let opts = o
            state.runBackground("Exporting IFC") { progress, cancelled in
                let (files, report) = try IFCExporter.export(m, options: opts, progress: { progress($0, "Writing") }, isCancelled: cancelled)
                for f in files { try f.data.write(to: dir.appendingPathComponent(f.name), options: .atomic) }
                return report
            } completion: { (r: Result<IFCExportReport, any Error>) in
                switch r {
                case .success(let rep):
                    DiagnosticsLog.shared.recordTiming("IFC export", seconds: rep.elapsed)
                    var text = "Files: \(rep.files.joined(separator: ", "))\nElements exported: \(rep.exportedElements)\nElapsed: \(String(format: "%.2f", rep.elapsed)) s\n\nEntities:\n"
                    text += rep.entityCounts.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
                    if !rep.warnings.isEmpty { text += "\n\nWarnings:\n" + rep.warnings.map { "  • \($0)" }.joined(separator: "\n") }
                    if !rep.skipped.isEmpty { text += "\n\nNot exported (\(rep.skipped.count)):\n" + rep.skipped.prefix(200).map { "  \($0.0): \($0.1)" }.joined(separator: "\n") }
                    state.presented = .report("IFC Export Report", text)
                case .failure(let e): state.show("IFC export failed: \(e)", error: true)
                }
            }
        }
    }
}

// MARK: - CAD import / link

struct ImportCADDialog: View {
    let state: DocumentState
    let url: URL
    let isLink: Bool
    let isDWG: Bool
    @State private var doc: CADDocument?
    @State private var error: String?
    @State private var layers: Set<String> = []
    @State private var options = CADImportOptions()
    @State private var positioning = 0
    @State private var units: CADUnits?
    @State private var dependencies: [CADDependency] = []
    @State private var resolved: [String: URL] = [:]
    @State private var readProgress = 0.0 // W2-DWG
    @State private var readCancel = CancelBox() // W2-DWG

    var body: some View {
        DialogFrame(title: "\(isLink ? "Link" : "Import") \(isDWG ? "DWG" : "DXF"): \(url.lastPathComponent)",
                    subtitle: (isLink ? "A link stays connected to the file and can be reloaded. The source file is never modified." : "An import stores a snapshot in the project. The source file is never modified.")
                        + (isDWG ? " " + DWGStatus.conversionNote : ""), // W2-DWG
                    okTitle: isLink ? "Link" : "Import", okDisabled: doc == nil || layers.isEmpty, state: state) {
            place()
        } content: {
            if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            if let doc {
                Text(verbatim: "\(doc.versionName.isEmpty ? doc.version : doc.versionName) · \(doc.layers.count) layers · \(doc.entityCounts.values.reduce(0, +)) entities · units: \(String(describing: doc.units))")
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading) {
                        HStack { Text("Layers").font(.headline); Spacer(); Button("All") { layers = Set(doc.layers.map(\.name)) }; Button("None") { layers = [] } }
                        List(doc.layers, id: \.name) { l in
                            Toggle(isOn: Binding(get: { layers.contains(l.name) }, set: { if $0 { layers.insert(l.name) } else { layers.remove(l.name) } })) {
                                HStack { Circle().fill(l.color.color).frame(width: 9, height: 9); Text(l.name); if !l.isOn || l.isFrozen { Text("off").font(.caption2).foregroundStyle(.secondary) } }
                            }
                        }.frame(width: 250, height: 220)
                    }
                    Form {
                        Picker("Units", selection: $units) {
                            Text("From file (\(String(describing: doc.units)))").tag(CADUnits?.none)
                            ForEach([CADUnits.millimeters, .centimeters, .meters, .inches, .feet], id: \.self) { Text(String(describing: $0)).tag(Optional($0)) }
                        }
                        Picker("Layout", selection: $options.layout) {
                            Text("Model space").tag(String?.none)
                            ForEach(doc.layouts.filter { !$0.isModelSpace }.map(\.name), id: \.self) { Text($0).tag(Optional($0)) }
                        }
                        Picker("Positioning", selection: $positioning) {
                            Text("Origin to origin").tag(0); Text("Center to center").tag(1); Text("Shared coordinates (survey point)").tag(2)
                        }
                        Toggle("Current view only", isOn: Binding(get: { options.currentViewOnly != nil }, set: { options.currentViewOnly = $0 ? state.activeViewID : nil }))
                        Toggle("Explode blocks", isOn: $options.explodeBlocks)
                    }
                }
                if !dependencies.isEmpty {
                    GroupBox("Referenced files") {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(dependencies, id: \.self) { d in
                                HStack {
                                    Image(systemName: d.status == .found ? "checkmark.circle" : "exclamationmark.triangle").foregroundStyle(d.status == .found ? .green : .orange)
                                    Text("\(d.kind.rawValue): \(d.name)").lineLimit(1)
                                    Text(d.status.rawValue).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    if d.status != .found { Button("Locate…") { locate(d) } }
                                }
                            }
                            Text("Arcus only looks next to the drawing. Missing references are listed in the import report.").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if error == nil {
                ProgressView(isDWG ? "Converting \(url.lastPathComponent) to DXF…" : "Reading \(url.lastPathComponent)…", value: readProgress) // W2-DWG
                    .frame(maxWidth: .infinity, minHeight: 280) // W4-AUDIT: same footprint as the loaded layout, so the sheet needn't grow after reading
            }
        }
        .frame(minWidth: 640, idealWidth: 640)
        .task { await read() }
        .onDisappear { readCancel.cancelled = true } // W2-DWG: stops a running converter
    }

    func read() async {
        let u = url
        let dwg = isDWG
        let box = readCancel // W2-DWG
        let provider = DWGProviders.current // W2-DWG: resolved on the main actor (reads Settings)
        let progressSink: @MainActor @Sendable (Double) -> Void = { [self] p in readProgress = p }
        do {
            let d: CADDocument = try await Task.detached(priority: .userInitiated) {
                let access = u.startAccessingSecurityScopedResource()
                defer { if access { u.stopAccessingSecurityScopedResource() } }
                if dwg {
                    return try provider.read(u, options: CADReadOptions(), progress: { p in Task { @MainActor in progressSink(p) } }, isCancelled: { box.cancelled })
                }
                return try DXFReader.read(try Data(contentsOf: u), fileName: u.lastPathComponent)
            }.value
            doc = d
            layers = Set(d.layers.filter { $0.isOn && !$0.isFrozen }.map(\.name))
            dependencies = CADDependencies.scan(d, parentURL: u, userResolved: resolved)
        } catch {
            self.error = "\(error)"
        }
    }

    func locate(_ d: CADDependency) {
        let panel = NSOpenPanel()
        panel.message = "Locate “\(d.name)”"
        if panel.runModal() == .OK, let u = panel.url, let doc {
            resolved[d.name] = u
            dependencies = CADDependencies.scan(doc, parentURL: url, userResolved: resolved)
        }
    }

    func place() {
        var o = options
        o.includedLayers = layers
        o.unitsOverride = units
        o.isLink = isLink
        o.levelID = state.activeView?.levelID ?? state.model.levels.first?.id
        let info = state.model.projectInfo
        switch positioning {
        case 1: o.positioning = .centerToCenter
        case 2: o.positioning = .sharedCoordinates(easting: info.surveyEasting, northing: info.surveyNorthing, rotation: info.trueNorthAngle)
        default: o.positioning = .originToOrigin
        }
        let u = url
        let bookmark = try? u.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let origin = info.surveyPoint.xy
        state.presented = nil
        let opts = o
        state.runBackground(isLink ? "Linking \(u.lastPathComponent)" : "Importing \(u.lastPathComponent)") { progress, cancelled in
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            return try await CADLinkService.prepare(url: u, bookmark: bookmark, options: opts, projectSurveyOrigin: origin, progress: { progress($0, "Converting") }, isCancelled: cancelled)
        } completion: { (r: Result<CADLinkService.Prepared, any Error>) in
            switch r {
            case .success(let prepared):
                var report: CADImportReport?
                state.session.perform(isLink ? "Link CAD" : "Import CAD") { tx in report = try CADLinkService.place(prepared: prepared, in: tx).1 }
                if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError(); return }
                if let rep = report {
                    DiagnosticsLog.shared.recordTiming("CAD import", seconds: rep.elapsed)
                    state.presented = .report("\(isLink ? "Link" : "Import") Report", CADReportText.text(rep))
                }
            case .failure(let e): state.show("Could not read \(u.lastPathComponent): \(e)", error: true)
            }
        }
    }
}

enum CADReportText {
    static func text(_ r: CADImportReport) -> String {
        var s = "File: \(r.fileName)\nFormat: \(r.format) \(r.version)\nUnits: \(r.units) (scale \(r.unitScale) m/unit)\n"
        s += "Extents: \(String(format: "%.2f × %.2f m", r.extents.width, r.extents.height))\nLayouts: \(r.layouts.joined(separator: ", "))\nLayers: \(r.layerCount)\n"
        s += "Converted entities: \(r.converted)\nRetained as reference geometry: \(r.retainedAsReference)\n"
        s += "Elapsed: \(String(format: "%.2f", r.elapsed)) s · Peak memory: \(ByteCountFormatter.string(fromByteCount: Int64(r.peakMemoryBytes), countStyle: .memory))\n"
        s += "\nEntities by type:\n" + r.entityCountsByType.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
        if !r.unsupported.isEmpty { s += "\n\nUnsupported (kept as bounds/metadata where possible):\n" + r.unsupported.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n") }
        if !r.missingFonts.isEmpty { s += "\n\nMissing fonts/SHX: " + r.missingFonts.joined(separator: ", ") }
        if !r.missingXrefs.isEmpty { s += "\nMissing xrefs: " + r.missingXrefs.joined(separator: ", ") }
        if !r.missingImages.isEmpty { s += "\nMissing images: " + r.missingImages.joined(separator: ", ") }
        if !r.warnings.isEmpty { s += "\n\nWarnings:\n" + r.warnings.map { "  • \($0)" }.joined(separator: "\n") }
        return s
    }
}

// MARK: - IFC import

struct ImportIFCDialog: View {
    let state: DocumentState
    let url: URL
    @State private var mapToNative = true
    var body: some View {
        DialogFrame(title: "Import IFC: \(url.lastPathComponent)", subtitle: "Recognised walls, floors, rooms, doors, windows, columns and beams become native elements; everything else stays as immutable reference geometry with its IFC data.", okTitle: "Import", state: state) {
            run()
        } content: {
            Toggle("Convert recognised elements to native Arcus elements", isOn: $mapToNative)
            Text("From Revit, the Arcus Bridge export (Insert ▸ Import Revit Model) keeps more data editable than IFC. Arcus does not open .rvt or .rfa files directly.").font(.caption).foregroundStyle(.secondary)
        }
    }
    func run() {
        let u = url
        let m = state.model
        var o = IFCImportOptions()
        o.mapToNative = mapToNative
        state.presented = nil
        let opts = o
        state.runBackground("Importing IFC") { progress, cancelled in
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: u)
            let tx = TransactionContext(model: m, name: "Import IFC")
            let report = try IFCImporter.importFile(data, fileName: u.lastPathComponent, into: tx, options: opts, progress: { progress($0, "Reading") }, isCancelled: cancelled)
            return (tx.touchedIDs.compactMap { tx.model[$0] }, report)
        } completion: { (r: Result<([Element], IFCImportReport), any Error>) in
            switch r {
            case .success(let (elements, report)):
                state.session.perform("Import IFC") { tx in for e in elements.sorted(by: { $0.id < $1.id }) { tx.insertPreservingID(e) } }
                if let e = state.session.lastError { state.show("IFC import could not be applied: \(e.message)", error: true); state.session.clearError(); return }
                DiagnosticsLog.shared.recordTiming("IFC import", seconds: report.elapsed)
                var text = "Schema: \(report.schema)\nEntities: \(report.entityCount)\nElapsed: \(String(format: "%.2f", report.elapsed)) s\n\nNative elements:\n"
                text += report.nativeCounts.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
                text += "\n\nReference geometry:\n" + report.referenceCounts.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n")
                if !report.unsupported.isEmpty { text += "\n\nUnsupported:\n" + report.unsupported.sorted { $0.key < $1.key }.map { "  \($0.key): \($0.value)" }.joined(separator: "\n") }
                if !report.warnings.isEmpty { text += "\n\nWarnings:\n" + report.warnings.map { "  • \($0)" }.joined(separator: "\n") }
                state.presented = .report("IFC Import Report", text)
            case .failure(let e): state.show("IFC import failed: \(e)", error: true)
            }
        }
    }
}

// MARK: - Links

struct ManageLinksDialog: View {
    let state: DocumentState
    @State private var selected: ElementID?
    var body: some View {
        let _ = state.session.changeCounter
        let links = state.model.elements(.importedCAD)
        DialogFrame(title: "Manage Links", okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            Table(links, selection: $selected) {
                TableColumn("Name") { e in Text(e.link?.sourceName ?? e.name) }
                TableColumn("Type") { e in Text("\(e.link?.format.rawValue ?? "") \(e.link?.isLinked == true ? "Link" : "Import")") }.width(90)
                TableColumn("Status") { e in
                    let exists = e.link.map { FileManager.default.fileExists(atPath: $0.sourcePath) } ?? false
                    Text(e.link?.isLoaded == false ? "Unloaded" : (e.link?.isLinked == true && !exists ? "Not Found" : "Loaded"))
                }.width(80)
                TableColumn("Path") { e in Text(e.link?.sourcePath ?? "").lineLimit(1).truncationMode(.middle) }
            }
            .frame(minHeight: 200)
            .overlay { // W4-AUDIT: an empty table otherwise shows only blank striped rows
                if links.isEmpty {
                    Text("No linked or imported files.\nUse Insert ▸ Link CAD, Import CAD or Link IFC to add one.").multilineTextAlignment(.center).font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Reload") { if let s = selected { LinkActions(state: state).reload([s]) } }.disabled(selected == nil)
                Button("Reload From…") { if let s = selected, let e = state.model[s] { LinkActions(state: state).locate(s, name: e.link?.sourceName ?? "") } }.disabled(selected == nil)
                Button("Unload") { if let s = selected { state.session.perform("Unload Link") { tx in tx.update(s) { $0.link?.isLoaded = false } } } }.disabled(selected == nil)
                Button("Load") { if let s = selected { state.session.perform("Load Link") { tx in tx.update(s) { $0.link?.isLoaded = true } } } }.disabled(selected == nil)
                Spacer()
                Button("Remove", role: .destructive) { if let s = selected { state.session.delete([s]); selected = nil } }.disabled(selected == nil)
            }
            F67ManageLinksSection(state: state) // F67: linked models, IFC, point clouds, topography, DWF markups
        }
        .frame(minWidth: 680, idealWidth: 680)
    }
}

/// PDF page or image underlay: stored as a link with scale and opacity; drawn beneath the model on screen and in print.
struct UnderlayDialog: View {
    let state: DocumentState
    let url: URL
    let isPDF: Bool
    @State private var page = 1
    @State private var pageCount = 1
    @State private var scaleDenominator = 100.0
    @State private var opacity = 0.6
    var body: some View {
        DialogFrame(title: "\(isPDF ? "PDF" : "Image") Underlay: \(url.lastPathComponent)", subtitle: "Underlays are reference pictures, not BIM geometry.", okTitle: "Place", state: state) {
            place()
        } content: {
            Form {
                if isPDF { Stepper("Page \(page) of \(pageCount)", value: $page, in: 1...max(pageCount, 1)) }
                TextField(isPDF ? "Drawing scale 1 :" : "Meters per 1000 pixels", value: $scaleDenominator, format: .number)
                Slider(value: $opacity, in: 0.1...1) { Text("Opacity") }
            }
        }
        .onAppear {
            if isPDF, let d = CGPDFDocument(url as CFURL) { pageCount = d.numberOfPages } else if !isPDF { scaleDenominator = 10 }
        }
    }
    func place() {
        let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        var ld = LinkData(format: isPDF ? .pdf : .image, isLinked: true, sourcePath: url.path, sourceName: url.lastPathComponent, contentKey: "",
                          placement: .scale(isPDF ? scaleDenominator * 0.0254 / 72 : scaleDenominator / 1000, isPDF ? scaleDenominator * 0.0254 / 72 : scaleDenominator / 1000))
        ld.bookmark = bookmark
        ld.opacity = opacity
        ld.page = isPDF ? "\(page)" : nil
        ld.lastLoaded = Date()
        let view = state.activeViewID
        let level = state.activeView?.levelID
        state.session.perform("Place Underlay") { tx in tx.create(.importedCAD, name: url.lastPathComponent, data: .link(ld), levelID: level, ownerViewID: view) }
        state.presented = nil
    }
}
