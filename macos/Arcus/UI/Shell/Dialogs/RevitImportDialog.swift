import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication
import ArcusServices
import ArcusRevit

/// Import Revit Model: a `.arcusx` exchange file (written by the Arcus Bridge add-in) imports as native, editable
/// elements and families. A `.rvt`/`.rfa` file is inspected (kind, release, preview) and imported only when this build
/// includes the licensed direct-import provider; otherwise the dialog explains the two routes that work.
struct RevitImportDialog: View {
    let state: DocumentState
    let url: URL
    @State private var policy = ExchangeImportOptions.ExistingElementPolicy.update
    @State private var createPlanViews = true
    @State private var importMeshes = true
    @State private var info: RevitFileInfo?
    @State private var inspectionError: String?

    var isExchange: Bool { RevitProviders.isExchangeFile(url) }
    var provider: any RevitImportProvider { RevitProviders.current }

    var body: some View {
        if isExchange { exchangeBody } else { revitFileBody }
    }

    // MARK: .arcusx

    var exchangeBody: some View {
        DialogFrame(title: "Import Revit Model", file: url, subtitle: url.lastPathComponent + DialogFileInfo.sizeSuffix(url), okTitle: "Import", labelWidth: 170, state: state) { run() } content: {
            DialogSection("Options", footnote: "Elements keep their identity across imports: re-importing an updated export updates the same walls and doors.") {
                DialogRow("Elements imported before") {
                    Picker("", selection: $policy) {
                        Text("Update them from this file").tag(ExchangeImportOptions.ExistingElementPolicy.update)
                        Text("Keep them unchanged").tag(ExchangeImportOptions.ExistingElementPolicy.keep)
                        Text("Import as new copies").tag(ExchangeImportOptions.ExistingElementPolicy.duplicate)
                    }.labelsHidden().fixedSize()
                }
                Toggle("Create floor plans for new levels", isOn: $createPlanViews)
                Toggle("Import unsupported geometry as reference meshes", isOn: $importMeshes)
            }
            DialogNotice(.info, "Walls, floors, roofs, ceilings, doors, windows, rooms, stairs, railings, columns, beams, materials and families become native, editable elements. Other geometry arrives as reference geometry.")
        }
    }

    func run() {
        let u = url, m = state.model
        var o = ExchangeImportOptions()
        o.existingElements = policy
        o.createPlanViews = createPlanViews
        o.importMeshes = importMeshes
        let opts = o
        state.presented = nil
        state.runBackground("Importing \(u.lastPathComponent)") { _, _ in
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let tx = TransactionContext(model: m, name: "Import Revit Model")
            let report: ExchangeImportReport
            do { report = try RevitProviders.importExchangeFile(u, into: tx, options: opts) } catch { throw ImportFailure(message: "\(error)") }
            return (tx.touchedIDs.compactMap { tx.model[$0] }, report)
        } completion: { (r: Result<([Element], ExchangeImportReport), any Error>) in
            switch r {
            case .success(let (elements, report)):
                state.session.perform("Import Revit Model") { tx in for e in elements.sorted(by: { $0.id < $1.id }) { tx.insertPreservingID(e) } }
                if let e = state.session.lastError { state.show("The import could not be applied: \(e.message)", error: true); state.session.clearError(); return }
                state.presented = .report("Import Report", Self.reportText(report))
            case .failure(let e):
                state.show("Import failed: \((e as? ImportFailure)?.message ?? "\(e)")", error: true)
            }
        }
    }

    static func reportText(_ r: ExchangeImportReport) -> String {
        var text = r.summary
        if let g = r.generator { text += "\n\nWritten by: \(g) (schema \(r.schemaVersion))" }
        if !r.familyDefinitions.isEmpty { text += "\nFamilies converted: " + r.familyDefinitions.map(\.name).sorted().joined(separator: ", ") }
        if !r.warnings.isEmpty { text += "\n\nWarnings:\n" + r.warnings.prefix(200).map { "  • \($0.message)" }.joined(separator: "\n") }
        if r.warnings.count > 200 { text += "\n  … and \(r.warnings.count - 200) more" }
        return text
    }

    // MARK: .rvt / .rfa

    @ViewBuilder var revitFileBody: some View {
        let status = info.map { i in i.kind.displayName + (i.revitRelease.map { " · release \($0)" } ?? "") } ?? (inspectionError == nil ? "Reading the file…" : "Can't be read")
        DialogFrame(title: provider.isAvailable ? "Import Revit Model" : "Open Revit File", file: url, subtitle: url.lastPathComponent + " · " + status, // W4-AUDIT
                    okTitle: provider.isAvailable ? "Import" : "Done", showCancel: provider.isAvailable, state: state) {
            if provider.isAvailable { runDirect() } else { state.presented = nil }
        } content: {
            if info != nil || inspectionError == nil {
                DialogSection(rows: false) {
                    HStack(alignment: .center, spacing: 14) {
                        preview
                        VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent).font(.headline).lineLimit(1).truncationMode(.middle)
                            Text(info.map { $0.kind.displayName } ?? "Reading the file…").foregroundStyle(.secondary)
                            if let r = info?.revitRelease { Text("Saved by release \(r)").foregroundStyle(.secondary) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                }
            }
            if let inspectionError { DialogNotice(.error, title: "This file can't be read", inspectionError.components(separatedBy: "could not be read: ").last ?? inspectionError) }
            if !provider.isAvailable {
                DialogNotice(.info, title: "Arcus doesn't open .rvt or .rfa files directly", "Export from Revit, then import the export here.",
                             detail: provider.unavailableReason)
                DialogSection("Import instead") {
                    DialogListRow(icon: "arrow.triangle.2.circlepath", iconTint: .accentColor, title: "Arcus Bridge export (.arcusx)",
                                  subtitle: "Recommended. Walls, doors, rooms and families stay editable.") {
                        Button("Import .arcusx…") { state.presented = nil; CommandRouter(state: state).run(.importRevit) }
                    }
                    DialogListRow(icon: "cube.transparent", iconTint: .teal, title: "IFC", subtitle: "In Revit choose File ▸ Export ▸ IFC.") {
                        Button("Import IFC…") { state.presented = nil; CommandRouter(state: state).run(.importIFC) }
                    }
                }
            }
        }
        .task { inspect() }
    }

    @ViewBuilder var preview: some View {
        if let png = info?.previewPNG, let image = NSImage(data: png) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 96, height: 96)
                .background(RoundedRectangle(cornerRadius: Tokens.radiusSection).fill(Color.white))
                .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
                .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
                .accessibilityLabel("Preview image stored in the file")
        } else {
            Image(nsImage: DialogFileIcon.image(for: url)).resizable().interpolation(.high)
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
        }
    }

    func inspect() {
        let u = url
        Task.detached(priority: .userInitiated) {
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let result = Result { () throws(RevitInspectionError) -> RevitFileInfo in try RevitFileInspector.inspect(u) }
            await MainActor.run {
                switch result {
                case .success(let i): info = i
                case .failure(let e): inspectionError = e.message
                }
            }
        }
    }

    func runDirect() {
        let u = url, m = state.model, p = provider
        state.presented = nil
        state.runBackground("Importing \(u.lastPathComponent)") { _, _ in
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            let tx = TransactionContext(model: m, name: "Import Revit Model")
            let report: ExchangeImportReport
            do { report = try p.import(u, into: tx, options: ExchangeImportOptions()) } catch { throw ImportFailure(message: "\(error)") }
            return (tx.touchedIDs.compactMap { tx.model[$0] }, report)
        } completion: { (r: Result<([Element], ExchangeImportReport), any Error>) in
            switch r {
            case .success(let (elements, report)):
                state.session.perform("Import Revit Model") { tx in for e in elements.sorted(by: { $0.id < $1.id }) { tx.insertPreservingID(e) } }
                if let e = state.session.lastError { state.show("The import could not be applied: \(e.message)", error: true); state.session.clearError(); return }
                state.presented = .report("Import Report", Self.reportText(report))
            case .failure(let e): state.show("Import failed: \((e as? ImportFailure)?.message ?? "\(e)")", error: true)
            }
        }
    }
}

private struct ImportFailure: Error { let message: String }
