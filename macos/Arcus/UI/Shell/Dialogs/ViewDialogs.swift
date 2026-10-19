import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

struct NewViewDialog: View {
    let state: DocumentState
    let kind: ViewKind
    @State private var chosen: Set<ElementID> = []
    var candidates: [Element] {
        let existing = Set(state.model.views.filter { $0.view?.kind == kind && $0.view?.parentViewID == nil }.compactMap(\.levelID))
        return state.model.levels.filter { !existing.contains($0.id) || kind == .structuralPlan }
    }
    var body: some View {
        DialogFrame(title: "New \(kind.rawValue)", icon: "square.3.layers.3d", tint: .blue, subtitle: "Choose the levels to create views for.", okDisabled: chosen.isEmpty,
                    disabledReason: candidates.isEmpty ? nil : "Choose at least one level", state: state) {
            let scale = state.activeView?.view?.scale ?? 100
            state.session.perform("Create \(kind.rawValue)s") { tx in
                for l in chosen.sorted() {
                    var v = ViewData(kind: kind, scale: scale)
                    v.phaseID = tx.model.latestPhase?.id
                    if kind == .structuralPlan { v.discipline = .structural }
                    var name = tx.model[l]?.name ?? "Level"
                    if tx.model.views.contains(where: { $0.name == name && $0.view?.kind.navigatorGroup == kind.navigatorGroup }) { name += " (\(kind.rawValue))" }
                    tx.create(.views, name: name, data: .view(v), levelID: l)
                }
            }
            state.presented = nil
        } content: {
            if candidates.isEmpty {
                // W4-AUDIT: no empty list under the explanation.
                DialogNotice(.info, "Every level already has a \(kind.rawValue.lowercased()). Duplicate an existing view instead.")
            } else {
                DialogCheckList(items: candidates.map { l in
                    DialogCheckItem(id: l.id, title: l.name, icon: "square.3.layers.3d", detail: Parameters.format(.double(l.level?.elevation ?? 0), type: .length, model: state.model))
                }, checked: $chosen, maxRows: 8, noun: "levels", emptyTitle: "No levels")
            }
        }
    }
}

struct NewSheetDialog: View {
    let state: DocumentState
    @State private var titleBlock: ElementID?
    @State private var number = ""
    @State private var name = "Unnamed"
    @State private var paper: PaperSize = .a1
    var body: some View {
        let m = state.model
        let taken = m.sheets.contains { $0.sheet?.number == number }
        DialogFrame(title: "New Sheet", icon: "doc.richtext", tint: .blue, subtitle: "Sheets are created from title block families.", okDisabled: number.isEmpty || taken,
                    disabledReason: number.isEmpty ? "Enter a sheet number" : "Sheet \(number) already exists", state: state) {
            var created: ElementID?
            let tb = titleBlock, n = number, nm = name, p = paper
            state.session.perform("Create Sheet") { tx in created = tx.create(.sheets, name: nm, data: .sheet(SheetData(number: n, paper: p, titleBlockTypeID: tb))) }
            state.presented = nil
            if let created { state.open(created) }
        } content: {
            DialogSection("Title block") {
                DialogRow("Title block") {
                    Picker("", selection: $titleBlock) {
                        Text("None (plain border)").tag(ElementID?.none)
                        ForEach(m.types(for: .titleBlocks), id: \.id) { t in Text(t.name).tag(Optional(t.id)) }
                    }.labelsHidden()
                    .onChange(of: titleBlock) { _, t in if let t, let p = SheetTitleBlocks.paper(forTitleBlockType: t, m) { paper = p } } // BL-BROWSER
                }
                DialogRow("Paper size") {
                    Picker("", selection: $paper) { ForEach(PaperSize.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().fixedSize()
                }
            }
            DialogSection("Sheet") {
                DialogRow("Number") {
                    HStack(spacing: 8) {
                        TextField("A101", text: $number).labelsHidden().frame(width: 120)
                        if taken { Label("Already used", systemImage: "exclamationmark.circle.fill").font(.callout).foregroundStyle(.red) }
                    }
                }
                DialogRow("Name") { TextField("Name", text: $name).labelsHidden() }
            }
        }
        .onAppear {
            titleBlock = m.types(for: .titleBlocks).first { $0.name.hasPrefix("A1") }?.id ?? m.types(for: .titleBlocks).first?.id
            let prefix = m.projectInfo.sheetNumberPrefix
            let nums = m.sheets.compactMap { s -> Int? in guard let n = s.sheet?.number, n.hasPrefix(prefix) else { return nil }; return Int(n.dropFirst(prefix.count)) }
            number = "\(prefix)\((nums.max() ?? 100) + 1)"
            if let t = titleBlock, let tn = m[t]?.name { paper = tn.hasPrefix("A3") ? .a3 : tn.hasPrefix("ARCH D") ? .archD : .a1 }
        }
    }
}

// PlaceViewDialog and ViewRangeDialog: see ProjectBrowserDialogs.swift (BL-BROWSER).

struct RenameDialog: View {
    let state: DocumentState
    let elementID: ElementID
    @State private var name = ""
    var body: some View {
        DialogFrame(title: "Rename", icon: "pencil", size: .small, subtitle: state.model[elementID].map { $0.category.singularName } ?? "", okTitle: "Rename",
                    okDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty, disabledReason: "Enter a name", state: state) {
            state.session.setParameter(ParameterID("name"), value: .text(name), on: [elementID], name: "Name")
            state.presented = nil
        } content: {
            DialogSection { DialogRow("Name") { TextField("", text: $name).labelsHidden() } }
        }
        .onAppear { name = state.model[elementID]?.name ?? "" }
    }
}

// BL-VG: VisibilityGraphicsDialog moved to VisibilityGraphicsDialog.swift (override columns, subcategories, Apply).

/// Category picking for Select by Category / Filter Selection.
struct CategoryPickDialog: View {
    enum Mode { case selectInView, filterSelection }
    let state: DocumentState
    let mode: Mode
    @State private var chosen: Set<Category> = []
    var counts: [(Category, [ElementID])] {
        let m = state.model
        var ids: [ElementID]
        if mode == .filterSelection { ids = state.session.selection.ids }
        else { ids = state.graphics.graphics(state.activeViewID ?? ElementID(0)).map { Array(Set($0.items.filter(\.selectable).compactMap(\.elementID))) } ?? [] }
        let grouped = Dictionary(grouping: ids.compactMap { m[$0] }, by: \.category)
        return grouped.keys.sorted().map { ($0, grouped[$0]!.map(\.id)) }
    }
    var body: some View {
        let c = counts
        let total = c.reduce(0) { $0 + $1.1.count }
        DialogFrameWithActions(title: mode == .filterSelection ? "Filter Selection" : "Select by Category", icon: mode == .filterSelection ? "line.3.horizontal.decrease.circle" : "cursorarrow.rays",
                               subtitle: mode == .filterSelection ? "\(total) element\(total == 1 ? "" : "s") selected. Uncheck categories to leave them out." : "Choose categories to select in this view.",
                               state: state) {
            let ids = c.filter { chosen.contains($0.0) }.flatMap(\.1)
            state.session.selection.select(ids)
            state.presented = nil
        } content: {
            DialogCheckList(items: c.map { cat, ids in DialogCheckItem(id: cat, title: cat.displayName, detail: "\(ids.count)") },
                            checked: $chosen, maxRows: 10, noun: "elements", totalOfDetails: true,
                            emptyTitle: mode == .filterSelection ? "Nothing selected" : "No elements in this view", emptyMessage: mode == .filterSelection ? "Select elements first." : "",
                            emptyIcon: "cursorarrow.rays")
        } actions: {
            Button("Check All") { chosen = Set(c.map(\.0)) }.disabled(c.isEmpty)
            Button("Check None") { chosen = [] }.disabled(chosen.isEmpty)
        }
        .onAppear { if mode == .filterSelection { chosen = Set(counts.map(\.0)) } }
    }
}

struct PasteToLevelsDialog: View {
    let state: DocumentState
    @State private var chosen: Set<ElementID> = []
    var body: some View {
        let m = state.model
        let levels = m.levels.sorted { ($0.level?.elevation ?? 0) > ($1.level?.elevation ?? 0) }
        DialogFrameWithActions(title: "Paste Aligned to Selected Levels", icon: "doc.on.clipboard", subtitle: "The clipboard is pasted at the same place on each level.",
                               okDisabled: chosen.isEmpty, disabledReason: "Choose at least one level", state: state) {
            Clipboard(state: state).paste(mode: .levels(chosen.sorted()))
            state.presented = nil
        } content: {
            DialogCheckList(items: levels.map { l in
                DialogCheckItem(id: l.id, title: l.name, icon: "square.3.layers.3d", detail: Parameters.format(.double(l.level?.elevation ?? 0), type: .length, model: m))
            }, checked: $chosen, maxRows: 9, noun: "levels", emptyTitle: "No levels", emptyIcon: "square.3.layers.3d")
        } actions: {
            Button("Check All") { chosen = Set(levels.map(\.id)) }
            Button("Check None") { chosen = [] }.disabled(chosen.isEmpty)
        }
    }
}

/// Override Graphics in View ▸ By Element: view-specific lines, fills, halftone and transparency for the selection.
struct OverrideGraphicsDialog: View {
    let state: DocumentState
    let viewID: ElementID
    let elementIDs: [ElementID]
    @State private var o = GraphicOverride()

    var body: some View {
        let m = state.model
        let count = elementIDs.count
        DialogFrameWithActions(title: "Override Graphics in View", icon: "paintbrush.pointed", tint: .orange,
                    subtitle: "\(count == 1 ? (m[elementIDs[0]].map { $0.category.singularName } ?? "1 element") : "\(count) elements") in “\(m[viewID]?.name ?? "")”. Only this view changes.",
                    scrolls: true, labelWidth: 120, state: state) {
            apply(o, name: "Override Graphics in View")
        } content: {
            DialogSection {
                Toggle("Halftone", isOn: Binding(get: { o.halftone ?? false }, set: { o.halftone = $0 ? true : nil }))
            }
            DialogSection("Projection Lines") {
                DialogRow("Pattern") { linePattern($o.projectionLinePattern) }
                OptionalColorRow(label: "Color", color: $o.projectionLineColor)
                DialogRow("Weight") { lineWeight($o.projectionLineWeight) }
            }
            DialogSection("Surface Patterns") {
                DialogRow("Pattern") { FillPatternMenu(state: state, selection: $o.surfacePatternID, noneLabel: o.surfacePattern?.rawValue ?? "By Category") } // W4-HATCH
                OptionalColorRow(label: "Color", color: $o.surfaceColor)
            }
            DialogSection("Surface Transparency") {
                DialogRow("Transparency") {
                    HStack {
                        Slider(value: Binding(get: { (o.transparency ?? 0) * 100 }, set: { o.transparency = $0 < 0.5 ? nil : $0 / 100 }), in: 0...90, step: 5)
                            .accessibilityLabel("Transparency")
                        Text(o.transparency.map { "\(Int(($0 * 100).rounded())) %" } ?? "By Category").monospacedDigit().foregroundStyle(.secondary).frame(width: 86, alignment: .trailing)
                    }
                }
            }
            DialogSection("Cut Lines") {
                DialogRow("Pattern") { linePattern($o.cutLinePattern) }
                OptionalColorRow(label: "Color", color: $o.cutLineColor)
                DialogRow("Weight") { lineWeight($o.cutLineWeight) }
            }
            DialogSection("Cut Patterns") {
                DialogRow("Pattern") { FillPatternMenu(state: state, selection: $o.cutPatternID, noneLabel: o.cutPattern?.rawValue ?? "By Category") } // W4-HATCH
                OptionalColorRow(label: "Color", color: $o.cutPatternColor)
            }
        } actions: {
            Button("Reset") { o = GraphicOverride() }
                .help("Clear the fields; choose OK to return the elements to their category graphics in this view.")
        }
        .onAppear { o = state.model[viewID]?.view?.visibility.commonElementOverride(elementIDs) ?? GraphicOverride() }
    }

    func apply(_ value: GraphicOverride, name: String) {
        let ids = elementIDs
        state.session.perform(name) { tx in
            tx.update(viewID) { e in e.view?.visibility.setElementOverride(value, for: ids) }
        }
        state.presented = nil
    }

    func linePattern(_ b: Binding<LinePatternKind?>) -> some View {
        Picker("Pattern", selection: b) {
            Text("By Category").tag(LinePatternKind?.none)
            ForEach(LinePatternKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
        }
        .labelsHidden().fixedSize()
    }

    func lineWeight(_ b: Binding<Int?>) -> some View {
        Picker("Weight", selection: b) {
            Text("By Category").tag(Int?.none)
            ForEach(1...16, id: \.self) { Text("\($0)").tag(Optional($0)) }
        }
        .labelsHidden().fixedSize()
    }

    func fillPattern(_ b: Binding<FillPatternKind?>) -> some View {
        Picker("Pattern", selection: b) {
            Text("By Category").tag(FillPatternKind?.none)
            ForEach(FillPatternKind.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
        }
    }
}

/// A colour that is either inherited ("By Category") or overridden.
private struct OptionalColorRow: View {
    let label: String
    @Binding var color: RGBColor?
    var body: some View {
        DialogRow(label) {
            HStack(spacing: 10) {
                Toggle("Override", isOn: Binding(get: { color != nil }, set: { color = $0 ? (color ?? .black) : nil }))
                ColorPicker("", selection: Binding(get: { (color ?? .black).color }, set: { color = RGBColor.from(NSColor($0)) }), supportsOpacity: false)
                    .labelsHidden()
                    .disabled(color == nil)
                    .accessibilityLabel("\(label) override")
                if color == nil { Text("By Category").foregroundStyle(.secondary) }
            }
        }
    }
}
