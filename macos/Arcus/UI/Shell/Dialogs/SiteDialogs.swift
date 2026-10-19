import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusCAD

// W2-DWG: Massing & Site dialogs (Site Settings, toposurface from a point file or from a CAD import).

enum SiteDialog: Equatable {
    case settings
    case pointFile(URL)
    case fromImport(ElementID)
    case pointFileToposolid(URL), fromImportToposolid(ElementID), simplify(ElementID) // BL-SITE
}

struct SiteDialogHost: View {
    let state: DocumentState
    let dialog: SiteDialog
    var body: some View {
        switch dialog {
        case .settings: SiteSettingsDialog(state: state)
        case .pointFile(let url): PointFileDialog(state: state, url: url)
        case .fromImport(let id): TopoFromImportDialog(state: state, linkID: id)
        case .pointFileToposolid(let url): PointFileDialog(state: state, url: url, toposolid: true) // BL-SITE
        case .fromImportToposolid(let id): TopoFromImportDialog(state: state, linkID: id, toposolid: true) // BL-SITE
        case .simplify(let id): SimplifySurfaceDialog(state: state, elementID: id) // BL-SITE
        }
    }
}

struct SiteSettingsDialog: View {
    let state: DocumentState
    @State private var interval = ""
    @State private var primaryEvery = 5
    @State private var show = true
    var body: some View {
        DialogFrame(title: "Site Settings", icon: "mountain.2", tint: .green, subtitle: "Contour lines of every toposurface in plan views.", labelWidth: 170, state: state) {
            let m = state.model
            guard let v = try? Parameters.parse(interval, type: .length, model: m).doubleValue, v >= 0.01 else {
                state.show("Enter a contour interval of at least 10 mm.", error: true); return
            }
            guard let pi = m.projectInfoElement?.id else { state.show("The project has no Project Information element.", error: true); return }
            let s = SiteSettings(contourInterval: v, primaryEvery: primaryEvery, showContours: show)
            state.session.perform("Site Settings") { tx in tx.update(pi) { s.write(to: &$0) } }
            state.presented = nil
        } content: {
            DialogSection("Contours", footnote: "Primary contours are drawn heavier. Label them with Massing & Site ▸ Label Contours.") {
                DialogRow("Show contours") { Toggle("", isOn: $show).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                DialogRow("Interval") { TextField("", text: $interval).labelsHidden().multilineTextAlignment(.trailing).frame(width: 120) }
                DialogRow("Primary contour every") {
                    Stepper(value: $primaryEvery, in: 1...50) { Text("\(primaryEvery) contour\(primaryEvery == 1 ? "" : "s")").monospacedDigit() }
                }
            }
        }
        .onAppear {
            let s = SiteSettings(state.model)
            interval = Parameters.format(.double(s.contourInterval), type: .length, model: state.model)
            primaryEvery = s.primaryEvery
            show = s.showContours
        }
    }
}

struct PointFileDialog: View {
    let state: DocumentState
    let url: URL
    var toposolid = false // BL-SITE: create a toposolid instead of a legacy toposurface
    private var noun: String { toposolid ? "Toposolid" : "Toposurface" }
    @State private var unit = "m"
    @State private var result: SitePointFile.Result?
    @State private var text = ""
    @State private var error: String?
    private static let units: [(String, String, Double)] = [("m", "Meters", 1), ("mm", "Millimeters", 0.001), ("cm", "Centimeters", 0.01), ("ft", "Feet", 0.3048), ("usft", "US survey feet", 1200.0 / 3937.0), ("in", "Inches", 0.0254)]
    var scale: Double { Self.units.first { $0.0 == unit }?.2 ?? 1 }

    var body: some View {
        let count = result?.points.count ?? 0
        DialogFrame(title: "\(noun) from Point File", file: url, subtitle: url.lastPathComponent + DialogFileInfo.sizeSuffix(url), okTitle: "Create", okDisabled: count < 3,
                    disabledReason: error == nil ? "The file needs at least 3 points" : nil, labelWidth: 110, state: state) {
            create()
        } content: {
            if let error { DialogNotice(.error, title: "The file can't be read", error) }
            DialogSection("File", footnote: "Each line: x, y, z (comma, semicolon, tab or space separated), optionally after a point name. Placed at internal coordinates.") {
                DialogRow("Units") {
                    Picker("", selection: $unit) { ForEach(Self.units, id: \.0) { Text($0.1).tag($0.0) } }.labelsHidden().fixedSize()
                }
            }
            if let r = result {
                DialogSection("Preview") {
                    DialogValueRow(label: "Points", value: "\(r.points.count)" + (r.skippedLines.isEmpty ? "" : " · \(r.skippedLines.count) line\(r.skippedLines.count == 1 ? "" : "s") skipped (first: line \(r.skippedLines[0]))"))
                    if let (extent, elevations) = bounds(r) {
                        DialogValueRow(label: "Extent", value: extent)
                        DialogValueRow(label: "Elevations", value: elevations)
                    }
                }
                if r.points.count > SiteOperations.maxSurfacePoints {
                    DialogNotice(.info, "Dense data is thinned evenly to about \(SiteOperations.maxSurfacePoints) points.")
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: unit) { _, _ in result = SitePointFile.parse(text, scale: scale) }
    }

    func bounds(_ r: SitePointFile.Result) -> (String, String)? {
        guard !r.points.isEmpty else { return nil }
        let b = Rect2(points: r.points.map(\.xy))
        let zs = r.points.map(\.z)
        let f = { (v: Double) in Parameters.format(.double(v), type: .length, model: state.model) }
        return ("\(f(b.width)) × \(f(b.height))", "\(f(zs.min() ?? 0)) to \(f(zs.max() ?? 0))")
    }

    func load() {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url), d.count < 64 << 20 else { error = "The file could not be read, or is larger than 64 MB."; return }
        text = String(decoding: d, as: UTF8.self)
        if state.model.units.system == .imperial { unit = "ft" }
        result = SitePointFile.parse(text, scale: scale)
    }

    func create() {
        guard let pts = result?.points else { return }
        var kept = 0
        let name = url.deletingPathExtension().lastPathComponent, solid = toposolid
        state.session.perform("\(noun) from File") { tx in
            kept = solid ? try ToposolidOperations.create(points: pts, name: name, typeID: state.currentTypes[.topography], in: tx).1 // BL-SITE
                         : try SiteOperations.createToposurface(pts, name: name, in: tx).1
        }
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        state.presented = nil
        state.show("\(noun) created from \(kept) points.")
    }
}

struct TopoFromImportDialog: View {
    let state: DocumentState
    let linkID: ElementID
    var toposolid = false // BL-SITE
    private var noun: String { toposolid ? "Toposolid" : "Toposurface" }
    @State private var doc: CADDocument?
    @State private var summaries: [CADSitePoints.LayerSummary] = []
    @State private var chosen: Set<String> = []
    @State private var error: String?
    @State private var cancel = CancelBox()

    var body: some View {
        DialogFrameWithActions(title: "\(noun) from Import", icon: "mountain.2", tint: .green, subtitle: "Choose layers with contour lines or spot points. Their elevations become the surface.",
                    okTitle: "Create", okDisabled: doc == nil || chosen.isEmpty, disabledReason: doc == nil ? nil : "Check at least one layer", state: state) {
            create()
        } content: {
            if let error { DialogNotice(.error, title: "The drawing can't be used", error) }
            if doc != nil {
                DialogCheckList(items: summaries.map { l in
                    DialogCheckItem(id: l.name, title: l.name, subtitle: l.elevations > 0 ? "\(l.elevations)+ elevations" : "flat", detail: "\(l.points) points")
                }, checked: $chosen, maxRows: 8, noun: "layers", emptyTitle: "No layers")
            } else if error == nil {
                DialogSection(rows: false) {
                    ProgressView("Reading \(state.model[linkID]?.link?.sourceName ?? "")…").padding(20).frame(maxWidth: .infinity, minHeight: 120)
                }
            }
        } actions: {
            Button("Check All") { chosen = Set(summaries.map(\.name)) }.disabled(summaries.isEmpty)
            Button("Check None") { chosen = [] }.disabled(chosen.isEmpty)
        }
        .task { await read() }
        .onDisappear { cancel.cancelled = true }
    }

    func sourceURL() -> URL? {
        guard let ld = state.model[linkID]?.link else { return nil }
        var stale = false
        if let b = ld.bookmark, let u = try? URL(resolvingBookmarkData: b, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { return u }
        return FileManager.default.fileExists(atPath: ld.sourcePath) ? URL(fileURLWithPath: ld.sourcePath) : nil
    }

    func read() async {
        guard let ld = state.model[linkID]?.link, ld.format == .dxf || ld.format == .dwg else { error = "Select a DXF or DWG link or import."; return }
        guard let u = sourceURL() else {
            error = "“\(ld.sourceName)” can't be found at \(ld.sourcePath). Contour elevations are read from the original file; reload or re-link it first."
            return
        }
        let box = cancel
        let provider = DWGProviders.current
        do {
            let d = try await Task.detached(priority: .userInitiated) {
                let access = u.startAccessingSecurityScopedResource()
                defer { if access { u.stopAccessingSecurityScopedResource() } }
                return try DWGProviders.$providerOverride.withValue(provider) { try CADSitePoints.readSource(u, isCancelled: { box.cancelled }) }
            }.value
            doc = d
            summaries = CADSitePoints.layers(in: d)
            chosen = Set(summaries.filter { $0.elevations > 0 }.map(\.name))
            if summaries.isEmpty { error = "The drawing has no lines, polylines or points in model space." }
        } catch {
            self.error = "Could not read \(ld.sourceName): \(error)"
        }
    }

    func create() {
        guard let doc, let e = state.model[linkID], let ld = e.link else { return }
        let pts = CADSitePoints.modelPoints(for: ld, drawing: state.model.referenceDrawings[ld.contentKey], document: doc, layers: chosen)
        var kept = 0
        let solid = toposolid, noun = noun
        state.session.perform("\(noun) from Import") { tx in
            kept = solid ? try ToposolidOperations.create(points: pts, name: noun, typeID: state.currentTypes[.topography], in: tx).1 // BL-SITE
                         : try SiteOperations.createToposurface(pts, name: noun, in: tx).1
        }
        if let err = state.session.lastError { state.show(err.message, error: true); return }
        state.presented = nil
        state.show("\(noun) created from \(kept) points on \(chosen.count) layer\(chosen.count == 1 ? "" : "s").")
    }
}

/// BL-SITE: Simplify Surface — removes survey points that change the surface by less than the chosen accuracy. The
/// preview runs the same simplification on a scratch transaction (nothing is committed) as the accuracy changes.
struct SimplifySurfaceDialog: View {
    let state: DocumentState
    let elementID: ElementID
    @State private var accuracy = ""

    /// Points left at `accuracy` (nil when the value doesn't parse or the surface is too large to preview live).
    func preview(_ text: String) -> (before: Int, after: Int)? {
        let m = state.model
        guard let v = try? Parameters.parse(text, type: .length, model: m).doubleValue, v > 0,
              (m[elementID]?.topography?.points.count ?? 0) <= 4000 else { return nil }
        let tx = TransactionContext(model: m, name: "Preview")
        return try? ToposolidOperations.simplify(elementID, tolerance: v, in: tx)
    }

    var body: some View {
        let e = state.model[elementID]
        let n = e?.topography?.points.count ?? 0
        let valid = (try? Parameters.parse(accuracy, type: .length, model: state.model).doubleValue).map { $0 > 0 } ?? false
        let p = preview(accuracy)
        DialogFrame(title: "Simplify Surface", icon: "mountain.2", tint: .green, subtitle: "\(e?.name ?? "Surface") · \(n) points", okTitle: "Simplify",
                    okDisabled: !valid, disabledReason: "Enter an accuracy greater than zero", state: state) {
            let m = state.model
            guard let v = try? Parameters.parse(accuracy, type: .length, model: m).doubleValue, v > 0 else {
                state.show("Enter an accuracy greater than zero.", error: true); return
            }
            var r = (before: 0, after: 0)
            let id = elementID
            state.session.perform("Simplify Surface") { tx in r = try ToposolidOperations.simplify(id, tolerance: v, in: tx) }
            if let err = state.session.lastError { state.show(err.message, error: true); return }
            state.presented = nil
            state.show(r.after < r.before ? "Simplified from \(r.before) to \(r.after) points." : "Every point shapes the surface at this accuracy; nothing was removed.")
        } content: {
            DialogSection(footnote: "Points are removed while the surface stays within this vertical distance of every original point. The outline is kept.") {
                DialogRow("Accuracy") { TextField("", text: $accuracy).labelsHidden().multilineTextAlignment(.trailing).frame(width: 120) }
            }
            DialogSection("Preview") {
                DialogValueRow(label: "Points now", value: "\(n)")
                if let p {
                    DialogValueRow(label: "After", value: p.after < p.before ? "\(p.after) (\(p.before - p.after) removed, \(Int((Double(p.before - p.after) / Double(max(p.before, 1)) * 100).rounded())) %)" : "\(p.after) (nothing to remove)")
                } else {
                    DialogValueRow(label: "After", value: valid ? "Shown when you simplify" : "—")
                }
            }
        }
        .onAppear { accuracy = Parameters.format(.double(state.model.units.system == .imperial ? 0.0254 : 0.02), type: .length, model: state.model) }
    }
}
