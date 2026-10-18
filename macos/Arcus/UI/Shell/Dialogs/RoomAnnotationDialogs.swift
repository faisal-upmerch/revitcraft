import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// MARK: - Tag All

/// Tag All: categories with their tag types, scope (view or selection), leader and orientation.
struct TagAllDialog: View {
    let state: DocumentState
    let viewID: ElementID
    @State private var chosen: Set<Category> = []
    @State private var types: [Category: ElementID] = [:]
    @State private var onlySelected = false
    @State private var leader = false
    @State private var leaderText = ""
    @State private var orientation: TagOrientation = .horizontal
    @State private var loaded = false

    var body: some View {
        let m = state.model
        let visible = CommandRouter(state: state).visibleElementIDs(viewID)
        let untagged = TagAll.untagged(in: viewID, visible: visible, m)
        let selection = Set(state.session.selection.ids)
        let cats = Category.taggable.filter { untagged[$0]?.isEmpty == false }
        let leaderLength = (try? Parameters.parse(leaderText, type: .length, model: m))?.doubleValue
        DialogFrame(title: "Tag All", subtitle: "Tags every visible element of the chosen categories that has no tag in “\(m[viewID]?.name ?? "")”.",
                    okDisabled: chosen.isEmpty || (leader && (leaderLength ?? 0) <= 0), state: state) {
            apply(visible: visible, selection: selection, leaderLength: leaderLength ?? 0.012)
        } content: {
            if cats.isEmpty {
                Text("Every taggable element in this view is already tagged.").foregroundStyle(.secondary)
            } else {
                List(cats, id: \.self) { c in
                    let count = (untagged[c] ?? []).filter { !onlySelected || selection.contains($0) }.count
                    let options = TagAll.tagTypes(for: c, m)
                    HStack {
                        Toggle(isOn: Binding(get: { chosen.contains(c) }, set: { if $0 { chosen.insert(c) } else { chosen.remove(c) } })) {
                            Text("\(c.displayName)  ·  \(count)").monospacedDigit()
                        }
                        .disabled(options.isEmpty)
                        Spacer()
                        if options.isEmpty {
                            Text("No tag family loaded").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Picker("", selection: Binding(get: { types[c] ?? options[0].id }, set: { types[c] = $0 })) {
                                ForEach(options, id: \.id) { t in Text("\(t.typeData?.familyName ?? ""): \(t.name)").tag(t.id) }
                            }
                            .labelsHidden().frame(width: 240)
                        }
                    }
                }
                .frame(minHeight: 180)
            }
            Toggle("Only selected elements in the current view", isOn: $onlySelected).disabled(selection.isEmpty)
            HStack {
                Toggle("Leader", isOn: $leader)
                TextField("Length", text: $leaderText).textFieldStyle(.roundedBorder).frame(width: 90).disabled(!leader)
                if leader && (leaderLength ?? 0) <= 0 { Text("Enter a length on paper").font(.caption).foregroundStyle(.red) }
                Spacer()
                Picker("Orientation", selection: $orientation) {
                    ForEach(TagOrientation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .frame(width: 200)
            }
        }
        .frame(minWidth: 540)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            leaderText = Parameters.format(.double(0.012), type: .length, model: m)
            onlySelected = !selection.isEmpty && selection.contains { id in cats.contains { untagged[$0]?.contains(id) == true } }
            for c in cats { if let t = TagAll.tagTypes(for: c, m).first { types[c] = t.id; chosen.insert(c) } }
        }
    }

    func apply(visible: Set<ElementID>, selection: Set<ElementID>, leaderLength: Double) {
        let m = state.model
        var chosenTypes: [Category: ElementID] = [:]
        for c in chosen { if let t = types[c] ?? TagAll.tagTypes(for: c, m).first?.id { chosenTypes[c] = t } }
        let options = TagAllOptions(tagTypes: chosenTypes, onlyElements: onlySelected ? selection : nil, leader: leader,
                                    leaderLength: leaderLength, orientation: orientation)
        let scale = m[viewID]?.view?.scale ?? 1
        var count = 0
        state.session.perform("Tag All") { tx in count = TagAll.run(options, view: viewID, visible: visible, scale: scale, in: tx) }
        state.presented = nil
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        state.show(count == 0 ? "Nothing to tag: the chosen elements are already tagged." : "Tagged \(count) element\(count == 1 ? "" : "s").")
    }
}

// MARK: - Color schemes

/// Edit Color Scheme: define schemes for rooms and areas (by value or by range, colours and patterns per row) and
/// choose the scheme the active view uses.
struct ColorSchemesDialog: View {
    let state: DocumentState
    let viewID: ElementID
    let placeLegend: Bool

    struct Draft: Identifiable {
        let id = UUID()
        var elementID: ElementID?
        var name: String
        var data: ColorSchemeData
    }

    @State private var drafts: [Draft] = []
    @State private var deleted: [ElementID] = []
    @State private var category: Category = .rooms
    @State private var selected: UUID?
    @State private var applyToView = true
    @State private var loaded = false

    var view: Element? { state.model[viewID] }
    /// The category the active view can colour (nil when the view takes no colour fill).
    var viewCategory: Category? {
        guard let vd = view?.view, vd.kind.isPlan || vd.kind == .section || vd.kind == .detail else { return nil }
        return ColorFill.category(for: vd)
    }
    var selectedIndex: Int? { drafts.firstIndex { $0.id == selected } }

    var body: some View {
        let m = state.model
        let canApply = viewCategory != nil && viewCategory == category && selectedIndex != nil
        DialogFrame(title: "Color Schemes", subtitle: "Rows are added automatically for new values. Hidden rows are not filled and not listed in legends.",
                    okDisabled: placeLegend && !canApply, state: state) {
            apply(canApply: canApply)
        } content: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $category) {
                        Text("Rooms").tag(Category.rooms)
                        Text("Areas").tag(Category.areas)
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    List(selection: $selected) {
                        ForEach(drafts.filter { $0.data.category == category }) { d in Text(d.name).tag(d.id) }
                    }
                    .frame(width: 190, height: 300)
                    HStack {
                        Button { duplicate() } label: { Image(systemName: "plus.square.on.square") }.help("Duplicate the selected scheme, or add one")
                        Button { remove() } label: { Image(systemName: "trash") }.help("Delete the selected scheme").disabled(selectedIndex == nil)
                    }
                    .buttonStyle(.borderless)
                }
                if let i = selectedIndex {
                    editor(i, m)
                } else {
                    Text("Add a scheme to colour \(category.displayName.lowercased()).").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 300)
                }
            }
            if let vc = viewCategory {
                Toggle("Use the selected scheme in “\(view?.name ?? "")”", isOn: $applyToView).disabled(!canApply)
                if vc != category { Text("This view colours \(vc.displayName.lowercased()).").font(.caption).foregroundStyle(.secondary) }
            }
            if placeLegend { Text("After OK, click in the view to place the legend.").font(.caption).foregroundStyle(.secondary) }
        }
        .frame(minWidth: 820)
        .onAppear(perform: load)
        .onChange(of: category) { _, c in
            if let i = selectedIndex, drafts[i].data.category == c { return }
            selected = drafts.first { $0.data.category == c }?.id
        }
    }

    // MARK: Editor

    @ViewBuilder func editor(_ i: Int, _ m: BIMModel) -> some View {
        let d = drafts[i]
        let params = parameterChoices(d.data.category, m)
        let numeric = params.first { $0.id == d.data.parameter }?.type.isNumeric ?? false
        let inUse = ColorFill.valuesInUse(d.data, m)
        VStack(alignment: .leading, spacing: 8) {
            FormRow(label: "Name") { TextField("", text: draftBinding(i, \.name, "")).textFieldStyle(.roundedBorder) }
            FormRow(label: "Legend title") { TextField("", text: draftBinding(i, \.data.title, "")).textFieldStyle(.roundedBorder) }
            FormRow(label: "Color by") {
                Picker("", selection: Binding(get: { d.data.parameter }, set: { setParameter(i, $0, params, m) })) {
                    ForEach(params, id: \.id) { p in Text(p.name).tag(p.id) }
                }
                .labelsHidden().frame(width: 220)
                Picker("", selection: Binding(get: { d.data.mode }, set: { setMode(i, $0, m) })) {
                    ForEach(ColorFillMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180).disabled(!numeric)
            }
            if d.data.category == .areas {
                FormRow(label: "Area scheme") {
                    Picker("", selection: draftBinding(i, \.data.areaSchemeID, nil)) {
                        Text("Any").tag(ElementID?.none)
                        ForEach(AreaPlans.sortedSchemes(m), id: \.id) { s in Text(s.name).tag(Optional(s.id)) }
                    }
                    .labelsHidden().frame(width: 220)
                }
            }
            rows(i, inUse, m)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder func rows(_ i: Int, _ inUse: [String: Int], _ m: BIMModel) -> some View {
        let d = drafts[i]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Visible").frame(width: 44)
                Text(d.data.mode == .byValue ? "Value" : "At least").frame(width: 110, alignment: .leading)
                Text("Label").frame(maxWidth: .infinity, alignment: .leading)
                Text("Color").frame(width: 50)
                Text("Fill pattern").frame(width: 150, alignment: .leading)
                if d.data.mode == .byValue { Text("In use").frame(width: 50) }
            }
            .font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(d.data.entries.indices, id: \.self) { j in
                        HStack {
                            Toggle("", isOn: entryBinding(i, j, \.visible, true)).labelsHidden().frame(width: 44)
                            if d.data.mode == .byValue {
                                Text(d.data.entries[j].value.isEmpty ? "(none)" : d.data.entries[j].value).lineLimit(1).frame(width: 110, alignment: .leading)
                            } else if j == 0 {
                                Text("—").foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
                            } else {
                                BoundField(value: Binding(get: { d.data.entries[j].lower ?? 0 }, set: { setLower(i, j, $0) }), type: d.data.parameterType, model: m)
                                    .frame(width: 110)
                            }
                            Text(ColorFill.label(d.data, row: j, m)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            ColorPicker("", selection: Binding(get: { d.data.entries[j].color.color },
                                                               set: { entryBinding(i, j, \.color, .white).wrappedValue = RGBColor.from(NSColor($0)) }))
                                .labelsHidden().frame(width: 50)
                            Picker("", selection: entryBinding(i, j, \.pattern, .solid)) {
                                ForEach(FillPatternKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden().frame(width: 150)
                            if d.data.mode == .byValue {
                                Text(inUse[d.data.entries[j].value].map { "\($0)" } ?? "–").monospacedDigit().foregroundStyle(.secondary).frame(width: 50)
                            }
                        }
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 260)
            HStack {
                if d.data.mode == .byRange {
                    Button("Add Range") { addRange(i) }
                    Button("Remove Range") { drafts[i].data.entries.removeLast() }.disabled(d.data.entries.count <= 2)
                } else {
                    Button("Remove Unused Rows") { drafts[i].data.entries.removeAll { inUse[$0.value] == nil } }
                        .disabled(!d.data.entries.contains { inUse[$0.value] == nil })
                }
            }
        }
    }

    // MARK: Parameters

    struct ParamChoice { let id: ParameterID; let name: String; let type: ParamType }

    /// Instance parameters of the category that make sense for colouring (text, choices, references and numbers).
    func parameterChoices(_ c: Category, _ m: BIMModel) -> [ParamChoice] {
        let sample = m.elements(c).first ?? Element(id: ElementID(0), category: c, data: .room(RoomData(point: .zero, number: "")))
        var seen = Set<ParameterID>()
        var out: [ParamChoice] = []
        for e in Parameters.instanceEntries(sample, m) {
            switch e.type {
            case .multilineText, .url, .bool: continue
            default: break
            }
            if ["ifcGUID", "elementID", "classification.code", "phaseCreated", "phaseDemolished"].contains(e.id.key) { continue }
            if seen.insert(e.id).inserted { out.append(ParamChoice(id: e.id, name: e.name, type: e.type)) }
        }
        return out
    }

    func setParameter(_ i: Int, _ id: ParameterID, _ params: [ParamChoice], _ m: BIMModel) {
        guard let p = params.first(where: { $0.id == id }), p.id != drafts[i].data.parameter else { return }
        drafts[i].data.parameter = p.id
        drafts[i].data.parameterName = p.name
        drafts[i].data.parameterType = p.type
        drafts[i].data.entries = []
        if drafts[i].data.title.isEmpty || drafts[i].data.title.hasSuffix(" Legend") { drafts[i].data.title = "\(p.name) Legend" }
        setMode(i, p.type.isNumeric && p.type != .integer ? .byRange : .byValue, m, force: true)
    }

    func setMode(_ i: Int, _ mode: ColorFillMode, _ m: BIMModel, force: Bool = false) {
        guard force || mode != drafts[i].data.mode else { return }
        drafts[i].data.mode = mode
        switch mode {
        case .byValue:
            drafts[i].data.entries = []
            drafts[i].data = ColorFill.completedWithProjectValues(drafts[i].data, m)
        case .byRange:
            let s = drafts[i].data
            let values = m.elements(s.category).compactMap { ColorFill.numericValue(of: $0, s, m) }
            drafts[i].data.entries = ColorFill.defaultRanges(for: values)
        }
    }

    /// Bindings that tolerate rows or schemes removed while SwiftUI still holds the old row views.
    func draftBinding<T>(_ i: Int, _ kp: WritableKeyPath<Draft, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { drafts.indices.contains(i) ? drafts[i][keyPath: kp] : fallback },
                set: { if drafts.indices.contains(i) { drafts[i][keyPath: kp] = $0 } })
    }
    func entryBinding<T>(_ i: Int, _ j: Int, _ kp: WritableKeyPath<ColorFillEntry, T>, _ fallback: T) -> Binding<T> {
        Binding(get: { drafts.indices.contains(i) && drafts[i].data.entries.indices.contains(j) ? drafts[i].data.entries[j][keyPath: kp] : fallback },
                set: { if drafts.indices.contains(i) && drafts[i].data.entries.indices.contains(j) { drafts[i].data.entries[j][keyPath: kp] = $0 } })
    }

    func setLower(_ i: Int, _ j: Int, _ v: Double) {
        guard drafts.indices.contains(i), drafts[i].data.entries.indices.contains(j), j > 0 else { return }
        drafts[i].data.entries[j].lower = v
        // Keep rows ordered by their lower bound (the open first row stays first).
        let first = drafts[i].data.entries[0]
        let rest = drafts[i].data.entries.dropFirst().sorted { ($0.lower ?? 0) < ($1.lower ?? 0) }
        drafts[i].data.entries = [first] + rest
    }

    func addRange(_ i: Int) {
        let e = drafts[i].data.entries
        let bounds = e.compactMap(\.lower)
        let step = bounds.count >= 2 ? bounds[bounds.count - 1] - bounds[bounds.count - 2] : max(bounds.last ?? 10, 1)
        let next = (bounds.last ?? 0) + step
        let used = Set(e.map(\.color))
        drafts[i].data.entries.append(ColorFillEntry(lower: next, color: ColorFill.autoColor(for: "\(next)", avoiding: used)))
    }

    // MARK: Load / save

    func load() {
        guard !loaded else { return }
        loaded = true
        let m = state.model
        drafts = m.elements(.colorSchemes).compactMap { e in
            e.colorScheme.map { Draft(elementID: e.id, name: e.name, data: ColorFill.completedWithProjectValues($0, m)) }
        }
        category = viewCategory ?? .rooms
        if !drafts.contains(where: { $0.data.category == category }) { drafts.append(defaultDraft(category, m)) }
        let current = view?.view?.colorSchemeID
        selected = drafts.first { $0.elementID == current && current != nil }?.id ?? drafts.first { $0.data.category == category }?.id
    }

    func defaultDraft(_ c: Category, _ m: BIMModel) -> Draft {
        var data = c == .rooms ? ColorSchemeData.department
            : ColorSchemeData(category: .areas, title: "Area Legend", parameter: ParameterID("name"), parameterName: "Name")
        data = ColorFill.completedWithProjectValues(data, m)
        return Draft(elementID: nil, name: uniqueName(c == .rooms ? "Department" : "Area Name"), data: data)
    }

    func uniqueName(_ base: String) -> String {
        var name = base, k = 2
        while drafts.contains(where: { $0.name == name }) { name = "\(base) \(k)"; k += 1 }
        return name
    }

    func duplicate() {
        if let i = selectedIndex {
            let d = Draft(elementID: nil, name: uniqueName(drafts[i].name), data: drafts[i].data)
            drafts.append(d); selected = d.id
        } else {
            let d = defaultDraft(category, state.model)
            drafts.append(d); selected = d.id
        }
    }

    func remove() {
        guard let i = selectedIndex else { return }
        if let id = drafts[i].elementID { deleted.append(id) }
        drafts.remove(at: i)
        selected = drafts.first { $0.data.category == category }?.id
    }

    func apply(canApply: Bool) {
        let saved = drafts, removed = deleted, view = viewID
        let assignKey = canApply && applyToView ? selected : nil
        state.session.perform("Color Schemes") { tx in
            for id in removed {
                for v in tx.model.views where v.view?.colorSchemeID == id { tx.update(v.id) { $0.view?.colorSchemeID = nil } }
                tx.delete(id)
            }
            var assigned: ElementID?
            for d in saved {
                let data = ColorFill.completedWithProjectValues(d.data, tx.model)
                let name = d.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Color Scheme" : d.name
                let id: ElementID
                if let existing = d.elementID, let e = tx.model[existing] {
                    if e.name != name || e.colorScheme != data { tx.update(existing) { $0.name = name; $0.colorScheme = data } }
                    id = existing
                } else {
                    id = tx.create(.colorSchemes, name: name, data: .colorScheme(data))
                }
                if d.id == assignKey { assigned = id }
            }
            if let assigned, tx.model[view]?.view?.colorSchemeID != assigned { tx.update(view) { $0.view?.colorSchemeID = assigned } }
        }
        state.presented = nil
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        if placeLegend { CommandRouter(state: state).run(.colorFillLegend) }
    }
}

/// A numeric field for a range bound, shown and parsed in project units.
private struct BoundField: View {
    @Binding var value: Double
    let type: ParamType
    let model: BIMModel
    @State private var text = ""
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .onAppear { text = Parameters.format(.double(value), type: type, model: model) }
            .onSubmit(commit)
            .onChange(of: value) { _, v in text = Parameters.format(.double(v), type: type, model: model) }
    }
    func commit() {
        if let v = (try? Parameters.parse(text, type: type, model: model))?.doubleValue ?? (try? Parameters.parse(text, type: .number, model: model))?.doubleValue {
            value = v
        } else {
            text = Parameters.format(.double(value), type: type, model: model)
        }
    }
}

// MARK: - Area plans

/// New Area Plan: pick a scheme (Gross Building or Rentable are created on first use) and levels; boundary lines
/// can be created from exterior walls.
struct NewAreaPlanDialog: View {
    let state: DocumentState
    @State private var scheme: ElementID?
    @State private var newScheme: AreaBoundaryRule? = .gross
    @State private var chosen: Set<ElementID> = []
    @State private var automatic = true

    var schemes: [Element] { AreaPlans.sortedSchemes(state.model) }
    /// The standard schemes that do not exist yet (offered in the picker; created on OK).
    var missingStandard: [AreaBoundaryRule] {
        [AreaBoundaryRule.gross, .rentable].filter { r in !schemes.contains { $0.name == (r == .gross ? AreaPlans.grossName : AreaPlans.rentableName) } }
    }

    var body: some View {
        let m = state.model
        DialogFrame(title: "New Area Plan", subtitle: "Area plans show the areas of one scheme. Boundary lines decide where areas are measured.",
                    okDisabled: chosen.isEmpty || (scheme == nil && newScheme == nil), state: state) {
            create()
        } content: {
            FormRow(label: "Area scheme") {
                Picker("", selection: Binding(get: { scheme.map { "id\($0.raw)" } ?? "new-\(newScheme?.rawValue ?? "")" }, set: { tag in
                    if let s = schemes.first(where: { "id\($0.id.raw)" == tag }) { scheme = s.id; newScheme = nil } else {
                        scheme = nil; newScheme = AreaBoundaryRule(rawValue: String(tag.dropFirst(4)))
                    }
                })) {
                    ForEach(schemes, id: \.id) { s in Text(s.name).tag("id\(s.id.raw)") }
                    ForEach(missingStandard, id: \.self) { r in Text(r == .gross ? AreaPlans.grossName : AreaPlans.rentableName).tag("new-\(r.rawValue)") }
                }
                .labelsHidden().frame(width: 220)
            }
            FormRow(label: "Boundary") {
                Text((scheme.flatMap { m[$0]?.areaScheme?.rule } ?? newScheme ?? .gross).displayName).foregroundStyle(.secondary)
            }
            List(m.levels, id: \.id) { l in
                Toggle(isOn: Binding(get: { chosen.contains(l.id) }, set: { if $0 { chosen.insert(l.id) } else { chosen.remove(l.id) } })) {
                    Text("\(l.name)  ·  \(Parameters.format(.double(l.level?.elevation ?? 0), type: .length, model: m))")
                }
            }
            .frame(minHeight: 160)
            Toggle("Create area boundary lines automatically from exterior walls", isOn: $automatic)
        }
        .onAppear {
            scheme = schemes.first?.id
            newScheme = scheme == nil ? .gross : nil
            if let l = state.activeView?.levelID { chosen = [l] }
        }
    }

    func create() {
        let levels = chosen.sorted { (state.model.elevation(ofLevel: $0), $0) < (state.model.elevation(ofLevel: $1), $1) }
        let picked = scheme, rule = newScheme, auto = automatic
        let scale = state.activeView?.view?.scale ?? 100
        var views: [ElementID] = []
        state.session.perform("Create Area Plans") { tx in
            AreaPlans.ensureDefaultSchemes(in: tx)
            let target = picked ?? tx.model.elements(.areaSchemes).first { $0.name == (rule == .rentable ? AreaPlans.rentableName : AreaPlans.grossName) }?.id
            guard let target else { return }
            for l in levels { views.append(AreaPlans.createAreaPlan(level: l, scheme: target, scale: scale, automaticBoundary: auto, in: tx)) }
        }
        state.presented = nil
        if let e = state.session.lastError { state.show(e.message, error: true); return }
        if let first = views.first { state.open(first) }
        let lines = views.first.flatMap { state.model[$0] }.map { v in
            state.model.elements(.areaBoundaryLines).filter { $0.levelID == v.levelID && $0.params[AreaPlans.schemeParameter]?.refValue == v.view?.areaSchemeID }.count
        } ?? 0
        if auto && lines == 0 { state.show("No exterior walls were found for automatic boundary lines. Draw them with Area Boundary.") }
    }
}
