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
        DialogFrame(title: "New \(kind.rawValue)", subtitle: "Choose the levels to create views for.", okDisabled: chosen.isEmpty, state: state) {
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
                // W4-AUDIT: no empty 160 pt list under the explanation.
                Text("Every level already has a \(kind.rawValue.lowercased()). Duplicate an existing view instead.").foregroundStyle(.secondary).frame(maxWidth: 420, alignment: .leading)
            } else {
                List(candidates, id: \.id) { l in
                    Toggle(isOn: Binding(get: { chosen.contains(l.id) }, set: { if $0 { chosen.insert(l.id) } else { chosen.remove(l.id) } })) {
                        Text("\(l.name)  ·  \(Parameters.format(.double(l.level?.elevation ?? 0), type: .length, model: state.model))")
                    }
                }
                .frame(minHeight: 160)
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
        DialogFrame(title: "New Sheet", subtitle: "Sheets are created from title block families.", okDisabled: number.isEmpty || m.sheets.contains { $0.sheet?.number == number }, state: state) {
            var created: ElementID?
            let tb = titleBlock, n = number, nm = name, p = paper
            state.session.perform("Create Sheet") { tx in created = tx.create(.sheets, name: nm, data: .sheet(SheetData(number: n, paper: p, titleBlockTypeID: tb))) }
            state.presented = nil
            if let created { state.open(created) }
        } content: {
            FormRow(label: "Title block") {
                Picker("", selection: $titleBlock) {
                    Text("None (plain border)").tag(ElementID?.none)
                    ForEach(m.types(for: .titleBlocks), id: \.id) { t in Text(t.name).tag(Optional(t.id)) }
                }.labelsHidden()
                .onChange(of: titleBlock) { _, t in if let t, let p = SheetTitleBlocks.paper(forTitleBlockType: t, m) { paper = p } } // BL-BROWSER
            }
            FormRow(label: "Paper size") {
                Picker("", selection: $paper) { ForEach(PaperSize.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden()
            }
            FormRow(label: "Sheet number") {
                TextField("A101", text: $number).textFieldStyle(.roundedBorder).frame(width: 120)
                if m.sheets.contains(where: { $0.sheet?.number == number }) { Text("Already used").foregroundStyle(.red).font(.caption) }
            }
            FormRow(label: "Sheet name") { TextField("Name", text: $name).textFieldStyle(.roundedBorder) }
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
        DialogFrame(title: "Rename", okDisabled: name.trimmingCharacters(in: .whitespaces).isEmpty, state: state) {
            state.session.setParameter(ParameterID("name"), value: .text(name), on: [elementID], name: "Name")
            state.presented = nil
        } content: {
            TextField("Name", text: $name).textFieldStyle(.roundedBorder).frame(width: 320)
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
        DialogFrame(title: mode == .filterSelection ? "Filter Selection" : "Select by Category", state: state) {
            let ids = counts.filter { chosen.contains($0.0) }.flatMap(\.1)
            state.session.selection.select(ids)
            state.presented = nil
        } content: {
            List(counts, id: \.0) { c, ids in
                Toggle("\(c.displayName) (\(ids.count))", isOn: Binding(get: { chosen.contains(c) }, set: { if $0 { chosen.insert(c) } else { chosen.remove(c) } }))
            }.frame(minHeight: 240)
            HStack { Button("Check All") { chosen = Set(counts.map(\.0)) }; Button("Check None") { chosen = [] } }
        }
        .onAppear { if mode == .filterSelection { chosen = Set(counts.map(\.0)) } }
    }
}

struct PasteToLevelsDialog: View {
    let state: DocumentState
    @State private var chosen: Set<ElementID> = []
    var body: some View {
        DialogFrame(title: "Paste Aligned to Selected Levels", okDisabled: chosen.isEmpty, state: state) {
            Clipboard(state: state).paste(mode: .levels(chosen.sorted()))
            state.presented = nil
        } content: {
            List(state.model.levels, id: \.id) { l in
                Toggle(l.name, isOn: Binding(get: { chosen.contains(l.id) }, set: { if $0 { chosen.insert(l.id) } else { chosen.remove(l.id) } }))
            }.frame(minHeight: 180)
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
        DialogFrame(title: "Override Graphics in View",
                    subtitle: "\(count == 1 ? (m[elementIDs[0]].map { $0.category.singularName } ?? "1 element") : "\(count) elements") in “\(m[viewID]?.name ?? "")”. Only this view changes.",
                    state: state) {
            apply(o, name: "Override Graphics in View")
        } content: {
            Form {
                Toggle("Halftone", isOn: Binding(get: { o.halftone ?? false }, set: { o.halftone = $0 ? true : nil }))
                Section("Projection Lines") {
                    linePattern($o.projectionLinePattern)
                    OptionalColorRow(label: "Color", color: $o.projectionLineColor)
                    lineWeight($o.projectionLineWeight)
                }
                Section("Surface Patterns") {
                    HStack { Text("Pattern"); Spacer(); FillPatternMenu(state: state, selection: $o.surfacePatternID, noneLabel: o.surfacePattern?.rawValue ?? "By Category") } // W4-HATCH
                    OptionalColorRow(label: "Color", color: $o.surfaceColor)
                }
                Section("Surface Transparency") {
                    HStack {
                        Slider(value: Binding(get: { (o.transparency ?? 0) * 100 }, set: { o.transparency = $0 < 0.5 ? nil : $0 / 100 }), in: 0...90, step: 5)
                            .accessibilityLabel("Transparency")
                        Text(o.transparency.map { "\(Int(($0 * 100).rounded())) %" } ?? "By Category").monospacedDigit().frame(width: 86, alignment: .trailing)
                    }
                }
                Section("Cut Lines") {
                    linePattern($o.cutLinePattern)
                    OptionalColorRow(label: "Color", color: $o.cutLineColor)
                    lineWeight($o.cutLineWeight)
                }
                Section("Cut Patterns") {
                    HStack { Text("Pattern"); Spacer(); FillPatternMenu(state: state, selection: $o.cutPatternID, noneLabel: o.cutPattern?.rawValue ?? "By Category") } // W4-HATCH
                    OptionalColorRow(label: "Color", color: $o.cutPatternColor)
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 360, idealHeight: 520, maxHeight: 560) // W4-AUDIT: the form scrolls instead of pushing the buttons below the window
            HStack {
                Button("Reset") { o = GraphicOverride() }
                    .help("Clear the fields; choose OK to return the elements to their category graphics in this view.")
                Spacer()
            }
        }
        .frame(minWidth: 460, idealWidth: 480)
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
    }

    func lineWeight(_ b: Binding<Int?>) -> some View {
        Picker("Weight", selection: b) {
            Text("By Category").tag(Int?.none)
            ForEach(1...16, id: \.self) { Text("\($0)").tag(Optional($0)) }
        }
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
        HStack {
            Toggle(label, isOn: Binding(get: { color != nil }, set: { color = $0 ? (color ?? .black) : nil }))
            Spacer()
            if color == nil { Text("By Category").foregroundStyle(.secondary) }
            ColorPicker("", selection: Binding(get: { (color ?? .black).color }, set: { color = RGBColor.from(NSColor($0)) }), supportsOpacity: false)
                .labelsHidden()
                .disabled(color == nil)
                .accessibilityLabel("\(label) override")
        }
    }
}
