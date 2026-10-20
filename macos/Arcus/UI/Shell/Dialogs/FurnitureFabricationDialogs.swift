import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication
import ArcusCAD

// FM7: the fabrication dialogs: Manage ▸ Stock Sheets and Hardware Catalog (settings tables like Object Styles; edits
// stay in the dialog until OK, one undoable change), Fabricate ▸ CNC Export (options, the parts to write, a folder)
// and Check Parts (the findings, as Review Warnings lists them, with Show).

/// Sheets of the fabrication batch.
enum FM7Dialog: Equatable {
    case stockSheets, hardwareCatalog, cncExport, checkParts
}

struct FM7DialogHost: View {
    let state: DocumentState
    let dialog: FM7Dialog
    var body: some View {
        switch dialog {
        case .stockSheets: StockSheetsDialog(state: state)
        case .hardwareCatalog: HardwareCatalogDialog(state: state)
        case .cncExport: CNCExportDialog(state: state)
        case .checkParts: CheckPartsDialog(state: state)
        }
    }
}

/// Length text in the document's units ("4'", "96\"", "1/8\"").
@MainActor
enum FM7Text {
    static func length(_ v: Double, _ m: BIMModel) -> String { FurnitureSizeText.inches(v) }
    /// A length typed in a fabrication dialog: a plain number is inches (shop sizes), otherwise the document's units.
    static func parseLength(_ s: String, _ m: BIMModel) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let d = Double(t) { return d * 0.0254 }
        return try? QuantityParser.parse(t, kind: .length, units: m.units)
    }
    static func money(_ v: Double, _ m: BIMModel) -> String { Parameters.format(.double(v), type: .currency, model: m) }
    static func parseMoney(_ s: String, _ m: BIMModel) -> Double? {
        let t = s.replacingOccurrences(of: m.units.currencySymbol, with: "").trimmingCharacters(in: .whitespaces)
        return Double(t)
    }
}

/// A text field that edits freely and applies its text on Return or when it loses focus (then shows the value again,
/// formatted), as Properties fields do.
struct FM7CommitField: View {
    var placeholder = ""
    let text: () -> String
    let commit: (String) -> Void
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onSubmit { apply() }
            .onChange(of: focused) { _, now in if !now { apply() } }
            .onAppear { draft = text() }
            .onChange(of: text()) { _, v in if !focused { draft = v } }
    }

    func apply() { commit(draft); draft = text() }
}

// MARK: - Stock Sheets

struct StockSheetsDialog: View {
    let state: DocumentState
    @State private var settings: FurnitureStockSheets?
    @State private var selection: String?
    @State private var error: String?

    var m: BIMModel { state.model }
    var materials: [Element] { m.elements(.materials).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    static let thicknesses: [Double] = [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 1, 1.25, 1.5].map { $0 * 0.0254 }

    var body: some View {
        DialogFrame(title: "Stock Sheets", icon: "rectangle.split.3x3", tint: .brown, size: .wide, subtitle: "Sheet sizes parts are nested on.", okDisabled: settings?.problem() != nil,
                    disabledReason: settings?.problem(), state: state, onOK: commit) {
            if let s = settings {
                StockSheetsEditor(settings: Binding(get: { settings ?? s }, set: { settings = $0 }), selection: $selection, model: m)
                if let error { DialogNotice(.error, error) }
            }
        }
        .onAppear { if settings == nil { settings = m.stockSheets } }
    }

    func commit() {
        guard let s = settings else { return }
        if s != m.stockSheets {
            state.session.perform("Stock Sheets") { tx in try FurnitureStockSheets.set(s, in: tx) }
            if let e = state.session.lastError { error = e.message; return }
        }
        state.presented = nil
    }
}

/// The sizes table and the nesting settings (also rendered on its own by QA).
struct StockSheetsEditor: View {
    @Binding var settings: FurnitureStockSheets
    @Binding var selection: String?
    let model: BIMModel

    var materials: [Element] { model.elements(.materials).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }

    var body: some View {
        VStack(alignment: .leading, spacing: DialogStyle.sectionSpacing) {
            DialogSection("Sizes", footnote: "A size with no material or thickness is used for every part without a size of its own.", rows: false) {
                VStack(spacing: 0) {
                    header
                    Divider()
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach($settings.sizes) { $s in
                                row($s)
                                DialogColors.rowDivider.frame(height: 1)
                            }
                        }
                    }
                    .frame(height: min(CGFloat(max(settings.sizes.count, 3)) * 34, 210)) // DIALOGS: as tall as the sizes
                    Divider()
                    HStack(spacing: 8) {
                        Button("Add 4' x 8'") { add(StockSheetSize(name: "4' x 8'", length: 96 * 0.0254, width: 48 * 0.0254)) }
                        Button("Add 5' x 5'") { add(StockSheetSize(name: "5' x 5'", length: 60 * 0.0254, width: 60 * 0.0254)) }
                        Button("Duplicate") { if let s = settings.sizes.first(where: { $0.id == selection }) { var c = s; c.id = UUID().uuidString; c.name += " Copy"; add(c) } }
                            .disabled(selection == nil)
                        Spacer()
                        Button("Delete") { settings.sizes.removeAll { $0.id == selection }; selection = nil }
                            .disabled(selection == nil || settings.sizes.count <= 1)
                    }
                    .controlSize(.small).padding(.horizontal, 10).frame(height: 32)
                }
            }
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                DialogSection("Cutting") {
                    DialogRow("Kerf") { lengthField(Binding(get: { settings.kerf }, set: { settings.kerf = $0 })).frame(width: 90) }
                    DialogRow("Edge trim") { lengthField(Binding(get: { settings.edgeTrim }, set: { settings.edgeTrim = $0 })).frame(width: 90) }
                    DialogRow("Rotation") { Toggle("Parts without grain may turn 90°", isOn: $settings.allowRotation).toggleStyle(.checkbox) }
                }
                DialogSection("Nesting") {
                    DialogRow("Method") {
                        Picker("", selection: $settings.method) { ForEach(NestingMethod.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize()
                    }
                    DialogRow("Sheet goods cost") {
                        Picker("", selection: $settings.costBasis) { ForEach(SheetCostBasis.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize()
                    }
                }
            }
            .environment(\.dialogLabelWidth, 120)
        }
    }

    func add(_ s: StockSheetSize) { settings.sizes.append(s); selection = s.id }

    static let columns: [(String, CGFloat)] = [("Name", 156), ("Material", 160), ("Thickness", 86), ("Length", 80), ("Width", 80), ("Grain", 116), ("Cost / Sheet", 90)]

    var header: some View {
        HStack(spacing: 8) {
            ForEach(Self.columns, id: \.0) { c in Text(c.0).font(DialogStyle.sectionTitle).foregroundStyle(.secondary).frame(width: c.1, alignment: .leading) }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
    }

    func row(_ s: Binding<StockSheetSize>) -> some View {
        let w = Self.columns.map(\.1)
        return HStack(spacing: 8) {
            TextField("", text: s.name).textFieldStyle(.roundedBorder).frame(width: w[0])
            Picker("", selection: s.materialID) {
                Text("Any Material").tag(ElementID?.none)
                ForEach(materials, id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden().frame(width: w[1])
            Picker("", selection: s.thickness) {
                Text("Any").tag(Double?.none)
                ForEach(StockSheetsDialog.thicknesses, id: \.self) { Text(FurnitureSizeText.inches($0)).tag(Optional($0)) }
            }.labelsHidden().frame(width: w[2])
            lengthField(s.length).frame(width: w[3])
            lengthField(s.width).frame(width: w[4])
            Picker("", selection: s.grain) { ForEach(GrainDirection.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: w[5])
            FM7CommitField(placeholder: "Material's", text: { s.wrappedValue.cost.map { FM7Text.money($0, model) } ?? "" },
                           commit: { s.wrappedValue.cost = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : FM7Text.parseMoney($0, model) })
                .frame(width: w[6])
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(selection == s.wrappedValue.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = s.wrappedValue.id }
    }

    func lengthField(_ v: Binding<Double>) -> some View {
        FM7CommitField(text: { FM7Text.length(v.wrappedValue, model) }, commit: { if let d = FM7Text.parseLength($0, model), d >= 0 { v.wrappedValue = d } })
    }
}

// MARK: - Hardware Catalog

struct HardwareCatalogDialog: View {
    let state: DocumentState
    struct Row: Identifiable, Hashable {
        let id: ElementID
        let family: String, type: String, kind: String
        var cost: Double, manufacturer: String, model: String
    }
    @State private var rows: [Row] = []
    @State private var original: [Row] = []
    @State private var filter = ""

    var shown: [Row] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return rows.filter { f.isEmpty || "\($0.family) \($0.type) \($0.kind) \($0.model)".lowercased().contains(f) }
    }

    var body: some View {
        DialogFrame(title: "Hardware Catalog", icon: "wrench.and.screwdriver", tint: .brown, size: .wide, subtitle: "\(rows.count) hardware types", state: state, onOK: commit) {
            TextField("Filter", text: $filter).textFieldStyle(.roundedBorder).frame(width: 260)
            DialogSection(footnote: "Costs are per piece. Placed hardware and the joints' fasteners use them in the Hardware Schedule and Cost.", boxed: false) {
                HardwareCatalogTable(rows: $rows, shown: shown.map(\.id), model: state.model)
            }
        }
        .onAppear { if rows.isEmpty { rows = Self.rows(state.model); original = rows } }
    }

    static func rows(_ m: BIMModel) -> [Row] {
        m.types(for: .furnitureHardware).map { t in
            let td = t.typeData
            let hv = FurnitureHardware.Values(td)
            return Row(id: t.id, family: td?.familyName ?? "", type: t.name, kind: hv.kind?.rawValue ?? "", cost: hv.cost,
                       manufacturer: td?.params[ParameterID("type.manufacturer")]?.textValue ?? "", model: td?.params[ParameterID("type.model")]?.textValue ?? "")
        }.sorted { ($0.family, $0.type) < ($1.family, $1.type) }
    }

    func commit() {
        let changed = rows.filter { r in original.first { $0.id == r.id } != r }
        if !changed.isEmpty {
            state.session.perform("Hardware Catalog") { tx in
                for r in changed {
                    tx.update(r.id) { e in
                        e.typeData?.params[ParameterID("type.cost")] = .double(max(0, r.cost))
                        e.typeData?.params[ParameterID("type.manufacturer")] = .text(r.manufacturer)
                        e.typeData?.params[ParameterID("type.model")] = .text(r.model)
                    }
                }
            }
            if let e = state.session.lastError { state.show(e.message, error: true) }
        }
        state.presented = nil
    }
}

struct HardwareCatalogTable: View {
    @Binding var rows: [HardwareCatalogDialog.Row]
    let shown: [ElementID]
    let model: BIMModel
    static let columns: [(String, CGFloat)] = [("Family", 220), ("Type", 140), ("Kind", 100), ("Unit Cost", 80), ("Manufacturer", 120), ("Model", 110)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Self.columns, id: \.0) { c in Text(c.0).font(DialogStyle.sectionTitle).foregroundStyle(.secondary).frame(width: c.1, alignment: .leading) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach($rows) { $r in
                        if shown.contains(r.id) {
                            HStack(spacing: 8) {
                                Text(r.family).frame(width: Self.columns[0].1, alignment: .leading).lineLimit(1)
                                Text(r.type).frame(width: Self.columns[1].1, alignment: .leading).lineLimit(1)
                                Text(r.kind).foregroundStyle(.secondary).frame(width: Self.columns[2].1, alignment: .leading)
                                FM7CommitField(text: { FM7Text.money(r.cost, model) }, commit: { if let v = FM7Text.parseMoney($0, model), v >= 0 { r.cost = v } })
                                    .frame(width: Self.columns[3].1)
                                TextField("", text: $r.manufacturer).textFieldStyle(.roundedBorder).frame(width: Self.columns[4].1)
                                TextField("", text: $r.model).textFieldStyle(.roundedBorder).frame(width: Self.columns[5].1)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            DialogColors.rowDivider.frame(height: 1)
                        }
                    }
                }
            }
            .frame(height: 380)
        }
        .background(RoundedRectangle(cornerRadius: Tokens.radiusSection).fill(DialogColors.sectionFill))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
    }
}

// MARK: - CNC Export

struct CNCExportDialog: View {
    let state: DocumentState
    @AppStorage("fm7.cnc.layout") private var layout = CNCExport.Layout.perPart.rawValue
    @AppStorage("fm7.cnc.format") private var format = CNCExport.Format.dxf.rawValue
    @AppStorage("fm7.cnc.faceB") private var faceB = CNCExport.FaceB.separateFile.rawValue
    @AppStorage("fm7.cnc.csv") private var csv = true
    @State private var chosen: Set<String> = []
    @State private var loaded = false

    var programs: [CNCPartProgram] { FurnitureCNC.programs(state.model) }
    var dwgReason: String? { DWGExporter.unavailableReason() }

    var body: some View {
        DialogFrame(title: "CNC Export", icon: "scissors", tint: .brown, size: .wide, subtitle: "DXF or DWG programs in inches.", okTitle: "Export…",
                    okDisabled: layout == CNCExport.Layout.perPart.rawValue && chosen.isEmpty, disabledReason: "Check at least one part", state: state, onOK: export) {
            CNCExportOptions(layout: $layout, format: $format, faceB: $faceB, csv: $csv, chosen: $chosen, programs: programs,
                             sheets: FurnitureFabrication.nesting(state.model).reduce(0) { $0 + $1.result.sheets.count }, dwgReason: dwgReason, model: state.model)
        }
        .onAppear { if !loaded { chosen = Set(programs.map(\.part.key)); loaded = true; if dwgReason != nil { format = CNCExport.Format.dxf.rawValue } } }
    }

    func export() {
        guard let w = state.window else { return }
        let o = CNCExport.Options(layout: CNCExport.Layout(rawValue: layout) ?? .perPart, format: CNCExport.Format(rawValue: format) ?? .dxf,
                                  faceB: CNCExport.FaceB(rawValue: faceB) ?? .separateFile, includeCSV: csv,
                                  partKeys: chosen.count == programs.count ? nil : chosen)
        let m = state.model
        state.presented = nil
        let panel = NSOpenPanel()
        panel.title = "CNC Export"
        panel.message = "Choose a folder for the CNC files. Files with the same names are replaced."
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: w) { r in
            guard r == .OK, let dir = panel.url else { return }
            let folder = dir.appendingPathComponent(CNCExportOptions.folderName(m))
            let helper = BundledDWGHelpers.standard.acadrust
            state.runBackground("CNC Export") { progress, cancelled in
                progress(0.1, "Writing programs")
                return try CNCExport.write(m, to: folder, options: o, dwgHelper: helper, isCancelled: cancelled)
            } completion: { (result: Result<[URL], any Error>) in
                switch result {
                case .success(let urls):
                    state.show("CNC Export: \(urls.count) files in “\(folder.lastPathComponent)”.")
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                case .failure(let e):
                    if !(e is CancellationError) { state.show("CNC Export failed: \(e)", error: true) }
                }
            }
        }
    }
}

/// The CNC Export options and part list (also rendered on its own by QA).
struct CNCExportOptions: View {
    @Binding var layout: String
    @Binding var format: String
    @Binding var faceB: String
    @Binding var csv: Bool
    @Binding var chosen: Set<String>
    let programs: [CNCPartProgram]
    let sheets: Int
    let dwgReason: String?
    let model: BIMModel

    static func folderName(_ m: BIMModel) -> String { DWGExporter.fileName("\(m.furnitureSetup?.name ?? "Furniture") CNC").replacingOccurrences(of: ".dwg", with: "") }

    var body: some View {
        VStack(alignment: .leading, spacing: DialogStyle.sectionSpacing) {
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                DialogSection("Output") {
                    DialogRow("Files") {
                        PillSegmented(selection: $layout, CNCExport.Layout.allCases.map { ($0.rawValue, $0.rawValue) }) // PILLS
                    }
                    DialogRow("Format") {
                        HStack {
                            PillSegmented(selection: $format, (dwgReason == nil ? CNCExport.Format.allCases : [.dxf]).map { ($0.rawValue, $0.rawValue) }) // PILLS
                            .help(dwgReason ?? "DWG is written by the bundled DWG engine")
                            if dwgReason != nil { Text("DWG needs the bundled DWG engine.").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    DialogRow("Face B") {
                        Picker("", selection: $faceB) { ForEach(CNCExport.FaceB.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) } }
                            .labelsHidden().fixedSize().disabled(layout != CNCExport.Layout.perPart.rawValue)
                    }
                    Toggle("Part List (CSV)", isOn: $csv).toggleStyle(.checkbox)
                }
                .environment(\.dialogLabelWidth, 70)
                DialogSection("Layers", footnote: "Inches. X along the cut length, Y along the width, origin at face A's lower-left corner.") {
                    Text(verbatim: "OUTLINE · INNER · DRILL_<dia>_<depth> · GROOVE_<depth> · POCKET_<depth> · HDRILL (edge) · BAND_<thickness> · GRAIN · LABEL · SHEET (nested)")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(width: 320)
            }
            if layout == CNCExport.Layout.perPart.rawValue {
                DialogSection("Parts", footnote: "\(chosen.count) of \(programs.count) parts · \(programs.filter { $0.faceB != nil }.count) with face B", boxed: false) {
                    partTable
                } accessory: {
                    HStack(spacing: 4) {
                        Button("Select All") { chosen = Set(programs.map(\.part.key)) }
                        Button("Select None") { chosen = [] }
                    }
                }
            } else {
                DialogNotice(.info, sheets == 0 ? "No sheet parts to nest." : "\(sheets) nested \(sheets == 1 ? "sheet" : "sheets"), one file each (Manage ▸ Stock Sheets sets the stock).")
            }
        }
    }

    static let columns: [(String, CGFloat)] = [("", 24), ("Mark", 80), ("Part", 170), ("Material", 150), ("Size", 170), ("Operations", 90), ("Face B", 60)]

    var partTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(Self.columns, id: \.0) { c in Text(c.0).font(DialogStyle.sectionTitle).foregroundStyle(.secondary).frame(width: c.1, alignment: .leading) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            Divider()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(programs, id: \.part.key) { p in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(get: { chosen.contains(p.part.key) }, set: { if $0 { chosen.insert(p.part.key) } else { chosen.remove(p.part.key) } }))
                                .toggleStyle(.checkbox).labelsHidden().frame(width: Self.columns[0].1)
                            Text(p.part.mark).frame(width: Self.columns[1].1, alignment: .leading)
                            Text(p.part.name).frame(width: Self.columns[2].1, alignment: .leading).lineLimit(1)
                            Text(model[p.part.materialID]?.name ?? "—").frame(width: Self.columns[3].1, alignment: .leading).lineLimit(1)
                            Text("\(FurnitureSizeText.inches(p.part.length)) x \(FurnitureSizeText.inches(p.part.width)) x \(FurnitureSizeText.inches(p.part.thickness))")
                                .frame(width: Self.columns[4].1, alignment: .leading).monospacedDigit()
                            Text("\(p.operationCount)")
                                .frame(width: Self.columns[5].1, alignment: .trailing).monospacedDigit()
                            Text(p.faceB == nil ? "" : "Yes").frame(width: Self.columns[6].1, alignment: .leading)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        DialogColors.rowDivider.frame(height: 1)
                    }
                }
            }
            .frame(height: 260)
        }
        .background(RoundedRectangle(cornerRadius: Tokens.radiusSection).fill(DialogColors.sectionFill))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
    }
}

// MARK: - Check Parts

struct CheckPartsDialog: View {
    let state: DocumentState
    @State private var findings: [ModelWarning] = []
    @State private var selection: String?
    @State private var loaded = false

    var body: some View {
        let counts = Dictionary(grouping: findings, by: { DialogSeverity($0.severity) }).mapValues(\.count)
        ArcusDialog(icon: "checklist", tint: .brown, title: "Check Parts", subtitle: summary, size: .large, okTitle: "Close", showCancel: false,
                    onCancel: { state.presented = nil }, onOK: { state.presented = nil }) {
            DialogSummaryTiles(tiles: DialogSummaryTiles.severities(counts))
            CheckPartsList(findings: findings, selection: $selection, model: state.model)
        } leading: {
            Button("Show") { show() }.disabled(selected.isEmpty).help("Select the parts and zoom to them")
            Button("Check Again") { findings = FurnitureCheckParts.check(state.model) }
        }
        .onAppear { if !loaded { findings = FurnitureCheckParts.check(state.model); loaded = true } }
    }

    var summary: String {
        let e = findings.filter { $0.severity == .error }.count, w = findings.filter { $0.severity == .warning }.count, i = findings.filter { $0.severity == .info }.count
        return findings.isEmpty ? "No problems found" : "\(e) errors, \(w) warnings, \(i) notes"
    }

    var selected: [ElementID] { findings.first { $0.id == selection }?.elements.filter { state.model[$0] != nil } ?? [] }

    func show() {
        let ids = selected
        state.presented = nil
        SelectByIDDialog.showElements(ids, state: state)
    }
}

/// The findings list (also rendered on its own by QA).
struct CheckPartsList: View {
    let findings: [ModelWarning]
    @Binding var selection: String?
    let model: BIMModel

    var body: some View {
        List(findings, selection: $selection) { w in
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.message)
                    Text(Self.title(w.code)).font(.caption).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: w.severity == .error ? "exclamationmark.octagon.fill" : w.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle")
                    .foregroundStyle(w.severity == .error ? .red : w.severity == .warning ? .orange : .secondary)
            }
            .tag(w.id)
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .opacity(findings.isEmpty ? 0 : 1)
        .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
        .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
        .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
        .overlay {
            if findings.isEmpty {
                DialogEmptyState(icon: "checkmark.seal", title: "No Problems", message: "Every part has a material, fits its stock and its hardware.")
            }
        }
        .frame(height: max(160, min(CGFloat(findings.count) * 46 + 16, 380))) // DIALOGS: as tall as the findings
    }

    static func title(_ code: String) -> String {
        switch code {
        case "fm7.material": "Missing material"
        case "fm7.stock": "Larger than the stock"
        case "fm7.thin": "Too thin for its hardware"
        case "fm7.overlap": "Overlapping parts"
        case "fm7.banding": "Unbanded edge"
        default: code
        }
    }
}
