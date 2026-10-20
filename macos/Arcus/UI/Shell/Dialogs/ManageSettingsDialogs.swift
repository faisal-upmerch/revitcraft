import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-VG: Manage tab dialogs — Object Styles, Warnings, Select by ID, Additional Settings — and View ▸ User Interface.

// MARK: - Object Styles

struct ObjectStylesDialog: View {
    let state: DocumentState
    @State private var draft = ObjectStyleSettings()
    @State private var tab = 0
    @State private var selection: String?

    var model: BIMModel { state.model }
    var stored: ObjectStyleSettings { model.projectInfo.objectStyles ?? ObjectStyleSettings() }
    var dirty: Bool { draft != stored }

    var rows: [VGRow] {
        let cats: [Category]
        switch tab {
        case 0: cats = Category.allCases.filter { $0.isModel && ![.modelGroups, .importedCAD, .ifcReference].contains($0) }
        case 1: cats = Category.allCases.filter { $0.isAnnotation || $0.categoryClass == .datum }
        default: cats = [.importedCAD, .ifcReference]
        }
        return cats.sorted { $0.displayName < $1.displayName }.map { c in
            let subs = Subcategories.names(for: c).map { VGRow(kind: .subcategory(c, $0)) }
            return VGRow(kind: .category(c), children: subs.isEmpty ? nil : subs)
        }
    }

    var body: some View {
        ArcusDialog(icon: "paintbrush", tint: .indigo, title: "Object Styles", subtitle: "Line weights, colours, patterns and materials every view starts from.",
                    size: .extraWide, height: 640, onCancel: { state.presented = nil }, onOK: { save(); state.presented = nil }) {
            PillSegmented(selection: $tab, [(0, "Model Objects"), (1, "Annotation Objects"), (2, "Imported Objects")]).frame(maxWidth: .infinity) // PILLS
            Table(rows, children: \.children, selection: $selection) {
                TableColumn("Category") { r in Text(r.name).fontWeight(overridden(r) ? .semibold : .regular) }.width(min: 180, ideal: 220)
                TableColumn("Projection") { r in weightPicker(r, cut: false) }.width(90)
                TableColumn("Cut") { r in if tab == 0 { weightPicker(r, cut: true) } }.width(90)
                TableColumn("Line Color") { r in colorCell(r) }.width(90)
                TableColumn("Line Pattern") { r in patternPicker(r) }.width(130)
                TableColumn("Material") { r in if tab == 0, r.isCategory { materialPicker(r) } }.width(min: 140, ideal: 180)
            }
            .scrollContentBackground(.hidden)
            .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
            .frame(maxHeight: .infinity)
            DialogCaption("Bold rows differ from the built-in defaults. View, filter and element overrides still apply on top.")
        } leading: {
            Button("Reset to Default") { if let r = selectedRow { set(r) { $0 = ObjectStyleOverride() } } }.disabled(selectedRow.map { !overridden($0) } ?? true)
                .help("Return the selected category or subcategory to the built-in style")
        } trailing: {
            Button("Apply") { save() }.disabled(!dirty).dialogButton()
        }
        .onAppear { draft = stored }
    }

    var selectedRow: VGRow? { rows.flatMap { [$0] + ($0.children ?? []) }.first { $0.id == selection } }

    func key(_ r: VGRow) -> (Category, String?) {
        switch r.kind {
        case .category(let c): (c, nil)
        case .subcategory(let c, let s): (c, s)
        default: (.genericModels, nil)
        }
    }
    func effective(_ r: VGRow) -> ObjectStyle { let (c, s) = key(r); return ObjectStyles.effective(c, subcategory: s, draft) }
    func overridden(_ r: VGRow) -> Bool { let (c, s) = key(r); return draft[c, s] != nil }
    func set(_ r: VGRow, _ mutate: (inout ObjectStyleOverride) -> Void) {
        let (c, s) = key(r)
        var o = draft[c, s] ?? ObjectStyleOverride()
        mutate(&o)
        draft[c, s] = o
    }

    func weightPicker(_ r: VGRow, cut: Bool) -> some View {
        Picker("", selection: Binding(get: { cut ? effective(r).cutWeight : effective(r).projectionWeight },
                                      set: { w in set(r) { if cut { $0.cutWeight = w } else { $0.projectionWeight = w } } })) {
            ForEach(1...16, id: \.self) { Text("\($0)").tag($0) }
        }
        .labelsHidden().controlSize(.small).accessibilityLabel("\(r.name) \(cut ? "cut" : "projection") line weight")
    }

    func colorCell(_ r: VGRow) -> some View {
        ColorPicker("", selection: Binding(get: { effective(r).color.color }, set: { c in set(r) { $0.color = RGBColor.from(NSColor(c)) } }), supportsOpacity: false)
            .labelsHidden().accessibilityLabel("\(r.name) line color")
    }

    func patternPicker(_ r: VGRow) -> some View {
        Picker("", selection: Binding(get: { effective(r).pattern }, set: { p in set(r) { $0.pattern = p } })) {
            ForEach(LinePatternKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden().controlSize(.small).accessibilityLabel("\(r.name) line pattern")
    }

    func materialPicker(_ r: VGRow) -> some View {
        let (c, s) = key(r)
        return Picker("", selection: Binding(get: { draft[c, s]?.materialID }, set: { m in set(r) { $0.materialID = m } })) {
            Text("By Category").tag(ElementID?.none)
            ForEach(model.materials, id: \.id) { m in Text(m.name).tag(Optional(m.id)) }
        }
        .labelsHidden().controlSize(.small).accessibilityLabel("\(r.name) material")
    }

    func save() {
        guard dirty else { return }
        let d = draft.styles.isEmpty ? nil : draft
        state.session.perform("Object Styles") { tx in
            if let pi = tx.model.projectInfoElement {
                tx.update(pi.id) { $0.projectInfo?.objectStyles = d }
            } else {
                var info = ProjectInfoData(); info.objectStyles = d
                tx.create(.projectInfo, name: "Project Information", data: .projectInfo(info))
            }
        }
    }
}

// MARK: - Warnings

/// Warnings, grouped by kind and expandable to each warning and its elements. Elements can be checked for deletion.
struct WarningsDialog: View {
    let state: DocumentState
    @State private var selection: String?
    @State private var checked: Set<ElementID> = []

    struct Node: Identifiable, Hashable {
        enum Kind: Hashable { case group(WarningGroup), warning(ModelWarning), element(ElementID) }
        let id: String
        let kind: Kind
        var children: [Node]?
    }

    var nodes: [Node] {
        WarningsReport.groups(state.healthWarnings).map { g in
            Node(id: "g:\(g.code)", kind: .group(g), children: g.warnings.map { w in
                Node(id: "w:\(w.id)", kind: .warning(w), children: w.elements.map { Node(id: "e:\(w.id):\($0.raw)", kind: .element($0)) })
            })
        }
    }

    var body: some View {
        let m = state.model
        let n = state.healthWarnings.count
        let counts = Dictionary(grouping: state.healthWarnings, by: { DialogSeverity($0.severity) }).mapValues(\.count)
        ArcusDialog(icon: "exclamationmark.triangle", tint: .orange, title: "Warnings",
                    subtitle: n == 0 ? "The model has no warnings." : "\(n) warning\(n == 1 ? "" : "s"). Expand one to see its elements; check elements to delete them.",
                    size: .large, okTitle: "Close", showCancel: false, onCancel: { state.presented = nil }, onOK: { state.presented = nil }) {
            DialogSummaryTiles(tiles: DialogSummaryTiles.severities(counts))
            List(nodes, children: \.children, selection: $selection) { n in
                switch n.kind {
                case .group(let g):
                    Label { Text("\(g.title) (\(g.warnings.count))") } icon: { severityIcon(g.severity) }
                case .warning(let w):
                    Label { Text(w.message) } icon: { severityIcon(w.severity) }
                case .element(let id):
                    Toggle(isOn: Binding(get: { checked.contains(id) }, set: { if $0 { checked.insert(id) } else { checked.remove(id) } })) {
                        Text(WarningsReport.describe(id, m)).foregroundStyle(m[id] == nil ? .secondary : .primary)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .opacity(state.healthWarnings.isEmpty ? 0 : 1)
            .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
            .overlay {
                if state.healthWarnings.isEmpty {
                    DialogEmptyState(icon: "checkmark.seal", title: "No Warnings", message: "The model has no warnings.")
                }
            }
            .frame(height: max(150, min(CGFloat(nodes.count) * 26 + 120, 420))) // DIALOGS: room to expand a few groups
        } leading: {
            Button("Show") { show() }.disabled(elements(for: selection).isEmpty).help("Select the elements and zoom to them")
            Button("Delete Checked") { deleteChecked() }.disabled(checked.isEmpty)
            Button("Export…") { export() }.disabled(state.healthWarnings.isEmpty).help("Save the warnings as an HTML report")
            Button("Check Again") { state.scheduleHealthCheck() }
        }
    }

    func severityIcon(_ s: ModelWarning.Severity) -> some View {
        Image(systemName: s == .error ? "exclamationmark.octagon.fill" : s == .warning ? "exclamationmark.triangle.fill" : "info.circle")
            .foregroundStyle(s == .error ? .red : s == .warning ? .orange : .secondary)
            .accessibilityLabel(s.rawValue)
    }

    func elements(for id: String?) -> [ElementID] {
        guard let id, let n = nodes.flatMap({ [$0] + ($0.children ?? []) + ($0.children ?? []).flatMap { $0.children ?? [] } }).first(where: { $0.id == id }) else { return [] }
        switch n.kind {
        case .group(let g): return Array(Set(g.warnings.flatMap(\.elements))).sorted()
        case .warning(let w): return w.elements
        case .element(let e): return [e]
        }
    }

    func show() {
        let ids = elements(for: selection).filter { state.model[$0] != nil }
        state.presented = nil
        SelectByIDDialog.showElements(ids, state: state)
    }

    func deleteChecked() {
        let ids = checked.filter { state.model[$0] != nil }.sorted()
        guard !ids.isEmpty else { return }
        state.session.delete(ids)
        checked = []
        state.scheduleHealthCheck()
    }

    func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "\(state.documentName) Warnings.html"
        let html = WarningsReport.html(state.healthWarnings, state.model, projectName: state.documentName)
        let write: (URL) -> Void = { url in
            do { try html.write(to: url, atomically: true, encoding: .utf8) } catch { state.show("Couldn't save the report: \(error.localizedDescription)", error: true) }
        }
        if let w = NSApp.keyWindow { panel.beginSheetModal(for: w) { r in if r == .OK, let u = panel.url { write(u) } } }
        else if panel.runModal() == .OK, let u = panel.url { write(u) }
    }
}

// MARK: - Select by ID

struct SelectByIDDialog: View {
    let state: DocumentState
    @State private var text = ""

    var parsed: (found: [ElementID], missing: [String]) {
        let (ids, invalid) = ElementIDList.parse(text)
        return (ids.filter { state.model[$0] != nil }, invalid + ids.filter { state.model[$0] == nil }.map(\.description))
    }

    var body: some View {
        let p = parsed
        DialogFrameWithActions(title: "Select by ID", icon: "number", size: .small, subtitle: "Separate ids with semicolons, commas or spaces.",
                               okDisabled: p.found.isEmpty, disabledReason: "Enter the id of an element", labelWidth: 60, state: state) {
            let ids = p.found
            state.presented = nil
            state.session.selection.select(ids)
            state.show("\(ids.count) element\(ids.count == 1 ? "" : "s") selected.")
        } content: {
            DialogSection(footnote: "\(p.found.count) element\(p.found.count == 1 ? "" : "s") found") {
                DialogRow("IDs") { TextField("1204; 1210", text: $text).labelsHidden().accessibilityLabel("Element ids") }
            }
            if !p.missing.isEmpty { DialogNotice(.warning, "Not found: \(p.missing.joined(separator: ", "))") }
        } actions: {
            Button("Show") { let ids = p.found; state.presented = nil; Self.showElements(ids, state: state) }.disabled(p.found.isEmpty)
                .help("Select the elements and open a view that shows them")
        }
        .onAppear { text = ElementIDList.format(state.session.selection.ids) }
    }

    /// Selects elements and zooms a plan view of their level (or the active 2D view) to them.
    static func showElements(_ ids: [ElementID], state: DocumentState) {
        let m = state.model
        let els = ids.compactMap { m[$0] }
        state.session.selection.select(els.map(\.id))
        guard let first = els.first else { return }
        let view: ElementID?
        if let owner = first.ownerViewID { view = owner }
        else if let plan = m.views.first(where: { $0.view?.kind == .floorPlan && $0.levelID == first.levelID }) ?? m.views.first(where: { $0.view?.kind == .floorPlan }) { view = plan.id }
        else { view = state.activeViewID }
        guard let v = view else { return }
        state.open(v)
        let b = els.reduce(Rect2.empty) { $0.union(ElementMeshes.bounds($1, m).xy) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let canvas = state.canvases[v] as? Canvas2DView, !b.isEmpty { canvas.zoom(to: b.expanded(by: 3)) }
        }
    }
}

// MARK: - Additional Settings

enum AdditionalSettingsTab: String, CaseIterable, Identifiable, Equatable {
    case lineWeights = "Line Weights", linePatterns = "Line Patterns", fillPatterns = "Fill Patterns", arrowheads = "Arrowheads"
    case temporaryDimensions = "Temporary Dimensions"
    var id: String { rawValue }
}

struct AdditionalSettingsDialog: View {
    let state: DocumentState
    @State var tab: AdditionalSettingsTab
    @State private var wallReference = TemporaryDimensionSettings.walls

    static let scales = [10, 20, 50, 100, 200, 500]

    var body: some View {
        ArcusDialog(icon: "gearshape", tint: .gray, title: "Additional Settings", subtitle: "Line weights, patterns, arrowheads and temporary dimensions.",
                    size: .wide, okTitle: "Done", showCancel: false, onCancel: { state.presented = nil }, onOK: { state.presented = nil }) {
            PillSegmented(selection: $tab, AdditionalSettingsTab.allCases.map { ($0, $0.rawValue) }) // PILLS
                .fixedSize().frame(maxWidth: .infinity)
            Group {
                switch tab {
                case .lineWeights: lineWeights
                case .linePatterns: linePatterns
                case .fillPatterns: fillPatterns
                case .arrowheads: arrowheads
                case .temporaryDimensions: temporaryDimensions
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
        } leading: {
            Button("Line Styles…") { state.presented = .lineStyles }.help("Open Manage ▸ Line Styles")
        }
    }

    var lineWeights: some View {
        DialogSection("Model line weights", footnote: "Printed pen width (mm) of each weight at common view scales. Weights 1–16 are fixed in this version of Arcus.", rows: false) {
            ScrollView {
                Grid(alignment: .trailing, horizontalSpacing: 28, verticalSpacing: 4) {
                    GridRow {
                        Text("Weight").font(DialogStyle.sectionTitle).foregroundStyle(.secondary)
                        ForEach(Self.scales, id: \.self) { Text("1 : \($0)").font(DialogStyle.sectionTitle).foregroundStyle(.secondary) }
                    }
                    Divider().gridCellColumns(Self.scales.count + 1)
                    ForEach(1...16, id: \.self) { w in
                        GridRow {
                            Text("\(w)").fontWeight(.medium)
                            ForEach(Self.scales, id: \.self) { s in Text(String(format: "%.2f", LineWeights.paperWidth(w, scale: s))).monospacedDigit() }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity)
            }
            .frame(maxHeight: 420)
        }
    }

    var linePatterns: some View {
        DialogListBox(count: LinePatternKind.allCases.count, rowHeight: 30, minRows: 6, maxRows: 13) {
        List(LinePatternKind.allCases, id: \.self) { p in
            HStack {
                Text(p.rawValue).frame(width: 140, alignment: .leading)
                Canvas { ctx, size in
                    var path = Path(); path.move(to: CGPoint(x: 0, y: size.height / 2)); path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    ctx.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.4, dash: p.dashPattern.map { CGFloat($0) * 2.4 }))
                }
                .frame(width: 180, height: 10)
                Text(p.dashPattern.isEmpty ? "Solid" : p.dashPattern.map { String(format: "%.1f", $0) }.joined(separator: ", ") + " mm")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        }
    }

    var fillPatterns: some View {
        FillPatternsSettingsView(state: state) // W4-HATCH: editable line-family patterns
    }

    var arrowheads: some View {
        let m = state.model
        let dimTypes = m.types(for: .dimensions)
        let textTypes = m.types(for: .textNotes)
        return ScrollView {
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                DialogSection("Dimension terminators") {
                    ForEach(DimensionTickMark.allCases, id: \.self) { t in
                        let n = dimTypes.filter { $0.typeData?.params[AnnotationParams.dimensionTick]?.textValue == t.rawValue }.count
                        DialogValueRow(label: t.rawValue, value: "\(n) dimension type\(n == 1 ? "" : "s")")
                    }
                }
                DialogSection("Leader arrowheads", footnote: "Choose a type's terminator or arrowhead in its Type Properties.") {
                    ForEach(LeaderArrowhead.allCases, id: \.self) { a in
                        let n = textTypes.filter { $0.typeData?.params[AnnotationParams.textArrowhead]?.textValue == a.rawValue }.count
                        DialogValueRow(label: a.rawValue, value: "\(n) text type\(n == 1 ? "" : "s")")
                    }
                }
            }
        }
    }

    var temporaryDimensions: some View {
        DialogSection("Temporary dimensions measure from", footnote: "A selected wall's temporary dimensions measure to the nearest parallel wall, grid or reference plane on each side.") {
            DialogRow("Walls", alignment: .top) {
                Picker("", selection: $wallReference) { ForEach(TemporaryDimensionSettings.WallReference.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.radioGroup).labelsHidden()
                    .onChange(of: wallReference) { _, v in TemporaryDimensionSettings.walls = v; state.toolChangedState() }
            }
            DialogValueRow(label: "Doors and Windows", value: "Openings")
        }
        .frame(maxWidth: 560)
    }
}

// MARK: - User Interface

struct UserInterfaceDialog: View {
    @Bindable var state: DocumentState
    @AppStorage("statusBar.visible") private var statusBar = true
    @AppStorage("navigationBar.visible") private var navigationBar = true
    var body: some View {
        DialogFrame(title: "User Interface", icon: "macwindow", tint: .gray, size: .small, subtitle: "Panels and bars shown in this window.", okTitle: "Done", showCancel: false, state: state) { state.presented = nil } content: {
            DialogSection {
                Toggle("Properties", isOn: Binding(get: { state.showProperties }, set: { state.showProperties = $0; state.onWorkspaceChange?() }))
                Toggle("Project Browser", isOn: Binding(get: { state.showNavigator }, set: { state.showNavigator = $0; state.onWorkspaceChange?() }))
                Toggle("Status Bar", isOn: $statusBar)
                Toggle("Navigation Bar", isOn: $navigationBar)
            }
        }
    }
}
