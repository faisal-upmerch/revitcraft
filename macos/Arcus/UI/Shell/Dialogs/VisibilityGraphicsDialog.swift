import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-VG: Visibility/Graphic Overrides — Model, Annotation and Imported categories with expandable subcategories,
// projection/cut line and pattern overrides, transparency, halftone and per-category detail level; Filters with
// Add/Remove/Up/Down/Edit-New; Links and Design Options when the project has them. OK, Cancel and Apply (Apply
// commits and keeps the dialog open so the canvas behind previews the result). Works on a view or a view template.

/// What a Visibility/Graphics dialog edits.
enum VGTarget: Equatable {
    case view(ElementID)
    case template(ElementID)
    var id: ElementID { switch self { case .view(let v), .template(let v): v } }
}

struct VisibilityGraphicsDialog: View {
    let state: DocumentState
    let target: VGTarget
    /// Called instead of dismissing the document sheet when the dialog is nested in another dialog.
    var onClose: (() -> Void)?

    @State private var vg = VisibilityGraphics()
    @State private var designOptions: [String: ElementID] = [:]
    @State private var committed: VisibilityGraphics?
    @State private var tab: Tab = .model
    @State private var search = ""
    @State private var selectedFilter: ElementID?
    @State private var showFilters = false
    @State private var editTemplate: ElementID?
    @State private var quickName = "Filter 1"
    @State private var quickCategory: Category = .walls
    @State private var quickParam = "mark"
    @State private var quickValue = ""

    init(state: DocumentState, viewID: ElementID) { self.state = state; self.target = .view(viewID) }
    init(state: DocumentState, target: VGTarget, onClose: (() -> Void)? = nil) { self.state = state; self.target = target; self.onClose = onClose }

    enum Tab: String, CaseIterable, Identifiable {
        case model = "Model Categories", annotation = "Annotation Categories", imported = "Imported Categories", filters = "Filters"
        case links = "Links", designOptions = "Design Options"
        var id: String { rawValue }
    }

    var model: BIMModel { state.model }
    var element: Element? { model[target.id] }
    /// The kind of view edited (a template's: the views it applies to); 3D views hide reference planes by default.
    var viewKind: ViewKind? { element?.view?.kind ?? element?.viewTemplate?.appliesTo }
    /// The template that controls V/G of the edited view (nothing to edit here then).
    var controllingTemplate: Element? {
        guard case .view = target, let e = element else { return nil }
        return ViewTemplates.controllingTemplate(e, .visibility, model)
    }
    var tabs: [Tab] {
        var t: [Tab] = [.model, .annotation, .imported, .filters]
        if !model.elements(.ifcReference).isEmpty { t.append(.links) }
        if case .view = target, !model.elements(.designOptions).isEmpty { t.append(.designOptions) }
        return t
    }
    var title: String {
        switch target {
        case .view: "Visibility/Graphic Overrides for \(element?.view?.kind.rawValue ?? "View"): \(element?.name ?? "")"
        case .template: "Visibility/Graphic Overrides for View Template: \(element?.name ?? "")"
        }
    }

    var body: some View {
        ArcusDialog(icon: "eye", tint: .indigo, title: title, subtitle: "Category visibility and graphic overrides" + ({ if case .template = target { return " of the template." } else { return " in this view." } }()),
                    size: .extraWide, height: 660, onCancel: { close() }, onOK: { apply(); close() }) {
            if let t = controllingTemplate {
                HStack {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    Text("The view template “\(t.name)” controls these settings.")
                    Spacer()
                    Button("Edit Template…") { editTemplate = t.id }.controlSize(.small)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
                .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(Color.accentColor.opacity(0.22)))
            }
            Picker("", selection: $tab) { ForEach(tabs) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize().frame(maxWidth: .infinity)
            Group {
                switch tab {
                case .model, .annotation: categoriesTab
                case .imported: importedTab
                case .filters: filtersTab
                case .links: linksTab
                case .designOptions: designOptionsTab
                }
            }
            .disabled(controllingTemplate != nil)
            .frame(minHeight: 380, maxHeight: .infinity)
        } leading: {
            if tab == .model || tab == .annotation {
                Button("All") { setAll(true) }.help("Show every category in the list")
                Button("None") { setAll(false) }.help("Hide every category in the list")
                Button("Invert") { invert() }.help("Swap shown and hidden categories")
            }
        } trailing: {
            Button("Apply") { apply() }.disabled(!dirty).help("Apply the changes and keep this dialog open").dialogButton()
        }
        .onAppear(perform: load)
        .onChange(of: tabs) { _, t in if !t.contains(tab) { tab = .model } }
        .sheet(isPresented: $showFilters) { FiltersDialog(state: state, initial: selectedFilter, onClose: { showFilters = false }).opaqueDialogBackground() } // DIALOGS
        .sheet(item: Binding(get: { editTemplate.map(IdentifiedID.init) }, set: { editTemplate = $0?.id })) { t in
            VisibilityGraphicsDialog(state: state, target: .template(t.id), onClose: { editTemplate = nil }).opaqueDialogBackground() // DIALOGS
        }
    }

    // MARK: Load / apply

    func stored() -> VisibilityGraphics {
        switch target {
        case .view(let v): model[v]?.view?.visibility ?? VisibilityGraphics()
        case .template(let t): model[t]?.viewTemplate?.visibility ?? VisibilityGraphics()
        }
    }

    func load() {
        vg = stored()
        committed = vg
        designOptions = element?.view?.designOptions ?? [:]
    }

    var dirty: Bool { vg != committed || designOptions != (element?.view?.designOptions ?? [:]) }

    func apply() {
        guard dirty, controllingTemplate == nil else { return }
        let v = vg, d = designOptions
        switch target {
        case .view(let id):
            state.session.perform("Visibility/Graphics") { tx in tx.update(id) { $0.view?.visibility = v; $0.view?.designOptions = d } }
        case .template(let id):
            state.session.perform("Edit View Template") { tx in
                tx.update(id) { $0.viewTemplate?.visibility = v }
                ViewTemplates.propagate(id, in: tx)
            }
        }
        if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() }
        committed = vg
    }

    func close() { if let onClose { onClose() } else { state.presented = nil } }

    // MARK: Category tabs

    var rows: [VGRow] {
        let cats: [Category] = tab == .model
            ? Category.allCases.filter { $0.isModel && ![.modelGroups, .importedCAD, .ifcReference].contains($0) }
            : Category.allCases.filter { $0.isAnnotation || $0.categoryClass == .datum }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return cats.filter { q.isEmpty || $0.displayName.lowercased().contains(q) }
            .sorted { $0.displayName < $1.displayName }
            .map { c in
                let subs = Subcategories.names(for: c).map { VGRow(kind: .subcategory(c, $0)) }
                return VGRow(kind: .category(c), children: subs.isEmpty ? nil : subs)
            }
    }

    var categoriesTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Filter list", text: $search).textFieldStyle(.roundedBorder).frame(width: 220)
            if tab == .model {
                Table(rows, children: \.children) {
                    TableColumn("Visibility") { r in visibilityCell(r) }.width(min: 180, ideal: 210)
                    TableColumn("Projection Lines") { r in OverrideButton(state: state, kind: .projectionLines, value: overrideBinding(r)) }.width(118)
                    TableColumn("Projection Patterns") { r in if r.isCategory { OverrideButton(state: state, kind: .surfacePatterns, value: overrideBinding(r)) } }.width(118)
                    TableColumn("Transparency") { r in if r.isCategory { OverrideButton(state: state, kind: .transparency, value: overrideBinding(r)) } }.width(96)
                    TableColumn("Cut Lines") { r in OverrideButton(state: state, kind: .cutLines, value: overrideBinding(r)) }.width(118)
                    TableColumn("Cut Patterns") { r in if r.isCategory { OverrideButton(state: state, kind: .cutPatterns, value: overrideBinding(r)) } }.width(118)
                    TableColumn("Halftone") { r in halftoneCell(r) }.width(60)
                    TableColumn("Detail Level") { r in if case .category(let c) = r.kind { detailCell(c) } }.width(100)
                }
            } else {
                Table(rows, children: \.children) {
                    TableColumn("Visibility") { r in visibilityCell(r) }.width(min: 220, ideal: 280)
                    TableColumn("Projection Lines") { r in OverrideButton(state: state, kind: .projectionLines, value: overrideBinding(r)) }.width(140)
                    TableColumn("Halftone") { r in halftoneCell(r) }.width(70)
                }
            }
        }
    }

    func visibilityCell(_ r: VGRow) -> some View {
        Toggle(isOn: visibleBinding(r)) { Text(r.name) }.toggleStyle(.checkbox)
            .accessibilityLabel("\(r.name) visible")
    }

    func halftoneCell(_ r: VGRow) -> some View {
        Toggle("", isOn: Binding(get: { overrideBinding(r).wrappedValue.halftone ?? false },
                                 set: { var o = overrideBinding(r).wrappedValue; o.halftone = $0 ? true : nil; overrideBinding(r).wrappedValue = o }))
            .toggleStyle(.checkbox).labelsHidden().accessibilityLabel("\(r.name) halftone")
    }

    func detailCell(_ c: Category) -> some View {
        Picker("", selection: Binding(get: { vg.categoryDetailLevels?[c] }, set: { v in
            var d = vg.categoryDetailLevels ?? [:]
            d[c] = v
            vg.categoryDetailLevels = d.isEmpty ? nil : d
        })) {
            Text("By View").tag(DetailLevel?.none)
            ForEach(DetailLevel.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
        }
        .labelsHidden().controlSize(.small).accessibilityLabel("\(c.displayName) detail level")
    }

    func visibleBinding(_ r: VGRow) -> Binding<Bool> {
        switch r.kind {
        case .category(let c):
            return Binding(get: { vg.isCategoryVisible(c, in: viewKind) }, set: { vg.setCategoryVisible(c, $0, in: viewKind) })
        case .subcategory(let c, let s):
            let k = Subcategories.key(c, s)
            return Binding(get: { !(vg.hiddenSubcategories?.contains(k) ?? false) }, set: { on in
                var h = vg.hiddenSubcategories ?? []
                if on { h.remove(k) } else { h.insert(k) }
                vg.hiddenSubcategories = h.isEmpty ? nil : h
            })
        case .instance(let id):
            return Binding(get: { !vg.hiddenElements.contains(id) }, set: { if $0 { vg.hiddenElements.remove(id) } else { vg.hiddenElements.insert(id) } })
        case .layer(let id, let layer):
            return Binding(get: { !(vg.hiddenLinkLayers[id]?.contains(layer) ?? false) }, set: { on in
                var s = vg.hiddenLinkLayers[id] ?? []
                if on { s.remove(layer) } else { s.insert(layer) }
                vg.hiddenLinkLayers[id] = s.isEmpty ? nil : s
            })
        }
    }

    func overrideBinding(_ r: VGRow) -> Binding<GraphicOverride> {
        switch r.kind {
        case .category(let c):
            return Binding(get: { vg.categoryOverrides[c] ?? GraphicOverride() }, set: { vg.categoryOverrides[c] = $0.isEmpty ? nil : $0 })
        case .subcategory(let c, let s):
            let k = Subcategories.key(c, s)
            return Binding(get: { vg.subcategoryOverrides?[k] ?? GraphicOverride() }, set: { o in
                var d = vg.subcategoryOverrides ?? [:]
                d[k] = o.isEmpty ? nil : o
                vg.subcategoryOverrides = d.isEmpty ? nil : d
            })
        case .instance(let id):
            return Binding(get: { vg.elementOverrides[id] ?? GraphicOverride() }, set: { vg.setElementOverride($0, for: [id]) })
        case .layer:
            return .constant(GraphicOverride())
        }
    }

    func setAll(_ on: Bool) { for r in rows { if case .category(let c) = r.kind { vg.setCategoryVisible(c, on, in: viewKind) } } }
    func invert() { for r in rows { if case .category(let c) = r.kind { vg.setCategoryVisible(c, !vg.isCategoryVisible(c, in: viewKind), in: viewKind) } } }

    // MARK: Imported

    var importedRows: [VGRow] {
        model.elements(.importedCAD).map { l in
            VGRow(kind: .instance(l.id), label: l.link?.sourceName ?? l.name,
                  children: (l.link?.layers ?? []).map { VGRow(kind: .layer(l.id, $0.name)) })
        }
    }

    var importedTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Show imported categories in this view", isOn: $vg.showLinks)
            Toggle(isOn: visibleBinding(VGRow(kind: .category(.importedCAD)))) { Text("Imported CAD (all imports and links)") }
            Table(importedRows, children: \.children) {
                TableColumn("Visibility") { r in visibilityCell(r) }.width(min: 260, ideal: 360)
                TableColumn("Projection Lines") { r in if case .instance = r.kind { OverrideButton(state: state, kind: .projectionLines, value: overrideBinding(r)) } }.width(140)
                TableColumn("Halftone") { r in if case .instance = r.kind { halftoneCell(r) } }.width(70)
            }
            .overlay {
                if importedRows.isEmpty {
                    ContentUnavailableView("No Imported Categories", systemImage: "square.stack.3d.down.right",
                                           description: Text("Link or import a DXF or DWG file from the Insert tab; its layers appear here."))
                }
            }
        }
    }

    // MARK: Links

    var linksTab: some View {
        Table(model.elements(.ifcReference).map { VGRow(kind: .instance($0.id), label: $0.name.isEmpty ? "IFC reference \($0.id)" : $0.name) }) {
            TableColumn("Visibility") { r in visibilityCell(r) }.width(min: 260, ideal: 360)
            TableColumn("Projection Lines") { r in OverrideButton(state: state, kind: .projectionLines, value: overrideBinding(r)) }.width(140)
            TableColumn("Halftone") { r in halftoneCell(r) }.width(70)
        }
    }

    // MARK: Design options

    var designOptionsTab: some View {
        let sets = Dictionary(grouping: model.elements(.designOptions), by: { $0.designOption?.setName ?? "" })
        return Form {
            ForEach(sets.keys.sorted(), id: \.self) { set in
                Picker(set, selection: Binding(get: { designOptions[set] }, set: { designOptions[set] = $0 })) {
                    Text("<Automatic> (primary)").tag(ElementID?.none)
                    ForEach(sets[set] ?? [], id: \.id) { o in Text(o.name + (o.designOption?.isPrimary == true ? " (primary)" : "")).tag(Optional(o.id)) }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Filters

    var filtersTab: some View {
        VStack(alignment: .leading, spacing: 6) {
            Table(vg.filters, selection: $selectedFilter) {
                TableColumn("Name") { f in Text(model[f.filterID]?.name ?? "Missing filter").foregroundStyle(model[f.filterID] == nil ? .red : .primary) }.width(min: 150, ideal: 190)
                TableColumn("Visibility") { f in Toggle("", isOn: filterBinding(f.filterID, \.visible)).toggleStyle(.checkbox).labelsHidden() }.width(62)
                TableColumn("Projection Lines") { f in OverrideButton(state: state, kind: .projectionLines, value: filterBinding(f.filterID, \.override)) }.width(118)
                TableColumn("Projection Patterns") { f in OverrideButton(state: state, kind: .surfacePatterns, value: filterBinding(f.filterID, \.override)) }.width(118)
                TableColumn("Transparency") { f in OverrideButton(state: state, kind: .transparency, value: filterBinding(f.filterID, \.override)) }.width(96)
                TableColumn("Cut Lines") { f in OverrideButton(state: state, kind: .cutLines, value: filterBinding(f.filterID, \.override)) }.width(118)
                TableColumn("Cut Patterns") { f in OverrideButton(state: state, kind: .cutPatterns, value: filterBinding(f.filterID, \.override)) }.width(118)
                TableColumn("Halftone") { f in
                    Toggle("", isOn: Binding(get: { filterBinding(f.filterID, \.override).wrappedValue.halftone ?? false },
                                             set: { var o = filterBinding(f.filterID, \.override).wrappedValue; o.halftone = $0 ? true : nil; filterBinding(f.filterID, \.override).wrappedValue = o }))
                        .toggleStyle(.checkbox).labelsHidden()
                }.width(60)
            }
            .overlay {
                if vg.filters.isEmpty {
                    ContentUnavailableView("No Filters Applied", systemImage: "line.3.horizontal.decrease.circle",
                                           description: Text("Add a filter to hide or override the elements that match its rules."))
                }
            }
            HStack {
                Menu("Add") {
                    let available = model.elements(.filters).filter { f in !vg.filters.contains { $0.filterID == f.id } }
                    if available.isEmpty { Text("Every filter is applied") }
                    ForEach(available, id: \.id) { f in Button(f.name) { vg.filters.append(AppliedFilter(filterID: f.id)); selectedFilter = f.id } }
                    Divider()
                    Button("Edit/New…") { showFilters = true }
                }
                .fixedSize().help("Apply a filter to this view")
                Button("Remove") { vg.filters.removeAll { $0.filterID == selectedFilter }; selectedFilter = nil }.disabled(selectedFilter == nil)
                Button("Up") { move(-1) }.disabled(!canMove(-1)).help("Filters lower in the list win over filters above them")
                Button("Down") { move(1) }.disabled(!canMove(1))
                Spacer()
                Button("Edit/New…") { showFilters = true }.help("Open the Filters dialog")
            }
            DisclosureGroup("Quick rule-based filter") {
                HStack {
                    TextField("Name", text: $quickName).frame(width: 120)
                    Picker("", selection: $quickCategory) { ForEach(Category.schedulable, id: \.self) { Text($0.displayName).tag($0) } }.labelsHidden().frame(width: 140)
                    Picker("", selection: $quickParam) {
                        Text("Mark").tag("mark"); Text("Comments").tag("comments"); Text("Type Mark").tag("type.mark"); Text("Function").tag("type.function")
                        Text("Fire Rating").tag("type.fireRating"); Text("Department").tag("room.department")
                    }.labelsHidden().frame(width: 120)
                    Text("contains")
                    TextField("Value", text: $quickValue).frame(width: 100)
                    Button("Add") { quickAdd() }.disabled(quickName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    func filterBinding<T>(_ id: ElementID, _ key: WritableKeyPath<AppliedFilter, T>) -> Binding<T> {
        Binding(get: { vg.filters.first { $0.filterID == id }.map { $0[keyPath: key] } ?? AppliedFilter(filterID: id)[keyPath: key] },
                set: { v in if let i = vg.filters.firstIndex(where: { $0.filterID == id }) { vg.filters[i][keyPath: key] = v } })
    }

    func canMove(_ d: Int) -> Bool {
        guard let i = vg.filters.firstIndex(where: { $0.filterID == selectedFilter }) else { return false }
        return vg.filters.indices.contains(i + d)
    }

    func move(_ d: Int) {
        guard let i = vg.filters.firstIndex(where: { $0.filterID == selectedFilter }), vg.filters.indices.contains(i + d) else { return }
        vg.filters.swapAt(i, i + d)
    }

    func quickAdd() {
        var fid: ElementID?
        let name = quickName, cat = quickCategory, param = quickParam, value = quickValue
        state.session.perform("Create Filter") { tx in
            fid = tx.create(.filters, name: name, data: .filter(ViewFilterData(categories: [cat], rules: [FilterRule(parameter: ParameterID(param), op: .contains, value: .text(value))])))
        }
        if let fid {
            var o = GraphicOverride(); o.halftone = true
            vg.filters.append(AppliedFilter(filterID: fid, visible: true, override: o))
            selectedFilter = fid
        }
    }
}

/// Wraps an id for `.sheet(item:)`.
struct IdentifiedID: Identifiable { let id: ElementID }

/// A row of the category tables: a category, one of its subcategories, an imported instance or one of its layers.
struct VGRow: Identifiable, Hashable {
    enum Kind: Hashable {
        case category(Category), subcategory(Category, String), instance(ElementID), layer(ElementID, String)
    }
    let kind: Kind
    var label: String?
    var children: [VGRow]?
    init(kind: Kind, label: String? = nil, children: [VGRow]? = nil) { self.kind = kind; self.label = label; self.children = children }
    var id: String {
        switch kind {
        case .category(let c): c.rawValue
        case .subcategory(let c, let s): Subcategories.key(c, s)
        case .instance(let e): "e\(e.raw)"
        case .layer(let e, let l): "e\(e.raw)/\(l)"
        }
    }
    var name: String {
        if let label { return label }
        switch kind {
        case .category(let c): return c.displayName
        case .subcategory(_, let s), .layer(_, let s): return s
        case .instance(let e): return e.description
        }
    }
    var isCategory: Bool { if case .category = kind { return true }; return false }
}

// MARK: - Override cells and editors

/// A V/G override cell: shows the current override (blank = by category) and opens the Line, Pattern or
/// Transparency override editor.
struct OverrideButton: View {
    enum Kind { case projectionLines, cutLines, surfacePatterns, cutPatterns, transparency }
    var state: DocumentState? = nil // W4-HATCH: project patterns in the pattern editors
    let kind: Kind
    @Binding var value: GraphicOverride
    @State private var editing = false

    var body: some View {
        Button { editing = true } label: {
            HStack(spacing: 4) {
                if let c = swatch { Circle().fill(c.color).frame(width: 9, height: 9).overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5)) }
                Text(summary.isEmpty ? "Override…" : summary).font(.system(size: 11)).foregroundStyle(summary.isEmpty ? .secondary : .primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(summary.isEmpty ? "No override: graphics come from Object Styles" : "Override: \(summary)")
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            Group {
                switch kind {
                case .projectionLines: LineOverrideEditor(title: "Projection Lines", weight: $value.projectionLineWeight, color: $value.projectionLineColor, pattern: $value.projectionLinePattern)
                case .cutLines: LineOverrideEditor(title: "Cut Lines", weight: $value.cutLineWeight, color: $value.cutLineColor, pattern: $value.cutLinePattern)
                case .surfacePatterns: PatternOverrideEditor(title: "Surface Patterns", pattern: $value.surfacePattern, color: $value.surfaceColor, patternID: $value.surfacePatternID, state: state) // W4-HATCH
                case .cutPatterns: PatternOverrideEditor(title: "Cut Patterns", pattern: $value.cutPattern, color: $value.cutPatternColor, patternID: $value.cutPatternID, state: state) // W4-HATCH
                case .transparency: TransparencyEditor(transparency: $value.transparency)
                }
            }
            .padding(14).frame(width: 300)
        }
    }

    var swatch: RGBColor? {
        switch kind {
        case .projectionLines: value.projectionLineColor
        case .cutLines: value.cutLineColor
        case .surfacePatterns: value.surfaceColor
        case .cutPatterns: value.cutPatternColor
        case .transparency: nil
        }
    }

    var summary: String {
        switch kind {
        case .projectionLines: Self.lines(value.projectionLineWeight, value.projectionLinePattern, value.projectionLineColor)
        case .cutLines: Self.lines(value.cutLineWeight, value.cutLinePattern, value.cutLineColor)
        case .surfacePatterns: value.surfacePatternID.flatMap { state?.model[$0]?.name } ?? Self.pattern(value.surfacePattern, value.surfaceColor) // W4-HATCH
        case .cutPatterns: value.cutPatternID.flatMap { state?.model[$0]?.name } ?? Self.pattern(value.cutPattern, value.cutPatternColor) // W4-HATCH
        case .transparency: value.transparency.map { "\(Int(($0 * 100).rounded())) %" } ?? ""
        }
    }

    static func lines(_ w: Int?, _ p: LinePatternKind?, _ c: RGBColor?) -> String {
        [w.map { "Weight \($0)" }, p?.rawValue, c != nil && w == nil && p == nil ? "Colour" : nil].compactMap { $0 }.joined(separator: " · ")
    }
    static func pattern(_ p: FillPatternKind?, _ c: RGBColor?) -> String {
        p?.rawValue ?? (c != nil ? "Colour" : "")
    }
}

/// Line Graphics override: pattern, colour and weight, each "By Category" (no override) or a value.
struct LineOverrideEditor: View {
    let title: String
    @Binding var weight: Int?
    @Binding var color: RGBColor?
    @Binding var pattern: LinePatternKind?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Line Graphics – \(title)").font(.headline)
            Picker("Pattern", selection: $pattern) {
                Text("By Category").tag(LinePatternKind?.none)
                ForEach(LinePatternKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            OverrideColorRow(label: "Color", color: $color)
            Picker("Weight", selection: $weight) {
                Text("By Category").tag(Int?.none)
                ForEach(1...16, id: \.self) { Text("\($0)").tag(Optional($0)) }
            }
            HStack { Button("Clear Overrides") { weight = nil; color = nil; pattern = nil }; Spacer() }
        }
    }
}

/// Fill Pattern Graphics override: pattern and colour.
struct PatternOverrideEditor: View {
    let title: String
    @Binding var pattern: FillPatternKind?
    @Binding var color: RGBColor?
    var patternID: Binding<ElementID?>? = nil // W4-HATCH: a project pattern (wins over the kind)
    var state: DocumentState? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Fill Pattern Graphics – \(title)").font(.headline)
            if let state, let patternID { // W4-HATCH
                HStack { Text("Pattern"); FillPatternMenu(state: state, selection: patternID, noneLabel: pattern?.rawValue ?? "By Category") }
            } else {
                Picker("Pattern", selection: $pattern) {
                    Text("By Category").tag(FillPatternKind?.none)
                    ForEach(FillPatternKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
            }
            OverrideColorRow(label: "Color", color: $color)
            HStack { Button("Clear Overrides") { pattern = nil; color = nil; patternID?.wrappedValue = nil }; Spacer() }
        }
    }
}

struct TransparencyEditor: View {
    @Binding var transparency: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Surface Transparency").font(.headline)
            HStack {
                Slider(value: Binding(get: { (transparency ?? 0) * 100 }, set: { transparency = $0 < 0.5 ? nil : $0 / 100 }), in: 0...90, step: 5)
                    .accessibilityLabel("Transparency")
                Text(transparency.map { "\(Int(($0 * 100).rounded())) %" } ?? "By Category").monospacedDigit().frame(width: 86, alignment: .trailing)
            }
        }
    }
}

/// A colour that is either inherited ("By Category") or overridden.
struct OverrideColorRow: View {
    let label: String
    @Binding var color: RGBColor?
    var body: some View {
        HStack {
            Toggle(label, isOn: Binding(get: { color != nil }, set: { color = $0 ? (color ?? .black) : nil }))
            Spacer()
            if color == nil { Text("By Category").foregroundStyle(.secondary) }
            ColorPicker("", selection: Binding(get: { (color ?? .black).color }, set: { color = RGBColor.from(NSColor($0)) }), supportsOpacity: false)
                .labelsHidden().disabled(color == nil).accessibilityLabel("\(label) override")
        }
    }
}
