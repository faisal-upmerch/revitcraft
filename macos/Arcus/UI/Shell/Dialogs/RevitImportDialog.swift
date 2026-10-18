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
        DialogFrame(title: "Import Revit Model: \(url.lastPathComponent)",
                    subtitle: "Walls, floors, roofs, ceilings, doors, windows, rooms, stairs, railings, columns, beams, materials and families become native, editable Arcus elements. Other geometry arrives as reference geometry.",
                    okTitle: "Import", state: state) { run() } content: {
            Form {
                Picker("Elements imported before", selection: $policy) {
                    Text("Update them from this file").tag(ExchangeImportOptions.ExistingElementPolicy.update)
                    Text("Keep them unchanged").tag(ExchangeImportOptions.ExistingElementPolicy.keep)
                    Text("Import as new copies").tag(ExchangeImportOptions.ExistingElementPolicy.duplicate)
                }
                Toggle("Create floor plans for new levels", isOn: $createPlanViews)
                Toggle("Import unsupported geometry as reference meshes", isOn: $importMeshes)
            }
            .formStyle(.grouped)
            Text("Elements keep their identity across imports, so re-importing an updated export updates the same walls and doors.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 520, idealWidth: 520)
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

    var revitFileBody: some View {
        DialogFrame(title: url.lastPathComponent,
                    subtitle: info.map { i in i.kind.displayName + (i.revitRelease.map { " · saved by release \($0)" } ?? "") } ?? (inspectionError == nil ? "Reading the file…" : "The file could not be inspected."), // W4-AUDIT
                    okTitle: provider.isAvailable ? "Import" : "Done", showCancel: provider.isAvailable, state: state) {
            if provider.isAvailable { runDirect() } else { state.presented = nil }
        } content: {
            HStack(alignment: .top, spacing: 16) {
                preview
                VStack(alignment: .leading, spacing: 8) {
                    if let inspectionError { Label(inspectionError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                    if !provider.isAvailable {
                        ScrollView {
                            Text(provider.unavailableReason ?? "").font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                        HStack {
                            Button("Import a .arcusx Export…") { state.presented = nil; CommandRouter(state: state).run(.importRevit) }
                            Button("Import IFC…") { state.presented = nil; CommandRouter(state: state).run(.importIFC) }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
        .frame(minWidth: 600, idealWidth: 600)
        .task { inspect() }
    }

    @ViewBuilder var preview: some View {
        if let png = info?.previewPNG, let image = NSImage(data: png) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                .frame(width: 160, height: 160)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                .accessibilityLabel("Preview image stored in the file")
        } else {
            RoundedRectangle(cornerRadius: 8).fill(.quaternary)
                .frame(width: 160, height: 160)
                .overlay(Image(systemName: "doc.questionmark").font(.system(size: 34, weight: .light)).foregroundStyle(.secondary))
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
