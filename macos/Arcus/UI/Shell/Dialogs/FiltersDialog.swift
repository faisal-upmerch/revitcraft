import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-VG: View ▸ Filters — rule-based filters shared with Visibility/Graphics: several categories, rules joined by
// AND or OR, and nested rule sets with their own AND/OR.

struct FiltersDialog: View {
    let state: DocumentState
    var initial: ElementID?
    /// Set when nested in Visibility/Graphics (closing must not dismiss the document sheet).
    var onClose: (() -> Void)?

    @State private var selection: ElementID?
    @State private var draft = ViewFilterData(categories: [], rules: [])
    @State private var name = ""
    @State private var loaded: ElementID?
    @State private var hideUnchecked = false

    var model: BIMModel { state.model }
    var filters: [Element] { model.elements(.filters).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
    static let filterableCategories: [Category] = Category.allCases.filter { $0.isModel || $0.isAnnotation || $0.categoryClass == .datum }
        .filter { ![.modelGroups, .importedCAD, .ifcReference].contains($0) }.sorted { $0.displayName < $1.displayName }

    var body: some View {
        ArcusDialog(icon: "line.3.horizontal.decrease.circle", tint: .indigo, title: "Filters", subtitle: "Rule-based selections of elements that views can hide or override.",
                    size: .wide, height: 600, onCancel: { close() }, onOK: { save(); close() }) {
            HStack(alignment: .top, spacing: DialogStyle.sectionSpacing) {
                filterList.frame(width: 190)
                if selection != nil {
                    categoryList.frame(width: 210)
                    rulesEditor.frame(maxWidth: .infinity)
                } else {
                    DialogPane {
                        DialogEmptyState(icon: "line.3.horizontal.decrease.circle", title: "No Filter Selected", message: "Create a filter, then choose its categories and rules.",
                                         actionTitle: "New Filter", action: { newFilter() })
                    }
                    .padding(.top, 21)
                }
            }
            .frame(maxHeight: .infinity)
        } trailing: {
            Button("Apply") { save() }.disabled(!dirty).dialogButton()
        }
        .onAppear { select(initial ?? filters.first?.id) }
        .onChange(of: selection) { old, new in
            if old != nil, old == loaded { save() }
            select(new)
        }
    }

    // MARK: Filter list

    var filterList: some View {
        VStack(alignment: .leading, spacing: 8) {
            DialogPane("Filters") {
                List(filters, id: \.id, selection: $selection) { f in Label(f.name, systemImage: "line.3.horizontal.decrease").tag(f.id) }
                    .overlay { if filters.isEmpty { DialogEmptyState(icon: "line.3.horizontal.decrease.circle", title: "No filters yet") } }
            } bar: {
                Button { newFilter() } label: { Image(systemName: "plus").frame(width: 20) }.help("New filter").accessibilityLabel("New filter")
                Button { duplicate() } label: { Image(systemName: "plus.square.on.square").frame(width: 20) }.help("Duplicate").accessibilityLabel("Duplicate filter").disabled(selection == nil)
                Button { delete() } label: { Image(systemName: "minus").frame(width: 20) }.help("Delete (removes it from every view)").accessibilityLabel("Delete filter").disabled(selection == nil)
            }
            .buttonStyle(.borderless)
            if selection != nil {
                TextField("Name", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Filter name")
            }
        }
    }

    // MARK: Categories

    var categoryList: some View {
        VStack(alignment: .leading, spacing: 8) {
            DialogPane("Categories") {
                List {
                    ForEach(Self.filterableCategories.filter { !hideUnchecked || draft.categories.contains($0) }, id: \.self) { c in
                        Toggle(c.displayName, isOn: Binding(get: { draft.categories.contains(c) }, set: { on in
                            if on { if !draft.categories.contains(c) { draft.categories.append(c) } } else { draft.categories.removeAll { $0 == c } }
                        })).toggleStyle(.checkbox)
                    }
                }
            } bar: {
                Button("Check All") { draft.categories = Self.filterableCategories }
                Button("Check None") { draft.categories = [] }
            }
            Toggle("Hide un-checked categories", isOn: $hideUnchecked).controlSize(.small)
        }
    }

    // MARK: Rules

    var parameters: [(id: ParameterID, name: String, type: ParamType)] { FilterEvaluation.parameters(for: draft.categories, model) }

    var rulesEditor: some View {
        DialogPane("Filter rules") {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Elements must match", selection: $draft.matchAll) {
                Text("all rules (AND)").tag(true); Text("any rule (OR)").tag(false)
            }.fixedSize()
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.rules.indices, id: \.self) { i in
                        RuleRow(rule: $draft.rules[i], parameters: parameters, model: model) { draft.rules.remove(at: i) }
                    }
                    ForEach((draft.groups ?? []).indices, id: \.self) { g in
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Picker("Rule set: match", selection: groupBinding(g).matchAll) { Text("all (AND)").tag(true); Text("any (OR)").tag(false) }.fixedSize()
                                    Spacer()
                                    Button("Remove Set") { draft.groups?.remove(at: g); if draft.groups?.isEmpty == true { draft.groups = nil } }
                                }
                                ForEach(groupBinding(g).wrappedValue.rules.indices, id: \.self) { i in
                                    RuleRow(rule: groupBinding(g).rules[i], parameters: parameters, model: model) { draft.groups?[g].rules.remove(at: i) }
                                }
                                Button("Add Rule") { draft.groups?[g].rules.append(defaultRule) }
                            }
                        }
                    }
                }
            }
            HStack {
                Button("Add Rule") { draft.rules.append(defaultRule) }
                Button("Add Rule Set") { draft.groups = (draft.groups ?? []) + [FilterRuleGroup(rules: [defaultRule], matchAll: !draft.matchAll)] }
                    .help("A nested set of rules with its own AND/OR, e.g. (Mark contains E AND Function equals Exterior) OR …")
                Spacer()
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            if draft.categories.isEmpty { DialogNotice(.warning, "Choose at least one category.") }
        }
        .padding(12)
        }
    }

    var defaultRule: FilterRule { FilterRule(parameter: parameters.first { $0.id == .mark }?.id ?? .mark, op: .equals, value: .text("")) }

    func groupBinding(_ g: Int) -> Binding<FilterRuleGroup> {
        Binding(get: { draft.groups?.indices.contains(g) == true ? draft.groups![g] : FilterRuleGroup(rules: []) },
                set: { v in if draft.groups?.indices.contains(g) == true { draft.groups![g] = v } })
    }

    var summary: String {
        guard selection != nil else { return "" }
        let n = draft.categories.flatMap { model.elements($0) }.filter { FilterEvaluation.matches(draft, $0, model) }.count
        return "\(n) element\(n == 1 ? "" : "s") in the project match."
    }

    // MARK: Actions

    var dirty: Bool {
        guard let id = selection, let f = model[id] else { return false }
        return f.viewFilter != draft || f.name != name
    }

    func select(_ id: ElementID?) {
        selection = id
        loaded = id
        draft = id.flatMap { model[$0]?.viewFilter } ?? ViewFilterData(categories: [], rules: [])
        name = id.flatMap { model[$0]?.name } ?? ""
    }

    func save() {
        guard let id = loaded, model[id] != nil, let f = model[id], f.viewFilter != draft || f.name != name else { return }
        let d = draft, n = name.trimmingCharacters(in: .whitespaces).isEmpty ? f.name : name
        state.session.perform("Edit Filter") { tx in tx.update(id) { $0.viewFilter = d; $0.name = n } }
    }

    func uniqueName(_ base: String) -> String {
        var n = base, k = 2
        while model.elements(.filters).contains(where: { $0.name == n }) { n = "\(base) \(k)"; k += 1 }
        return n
    }

    func newFilter() {
        save()
        var created: ElementID?
        let n = uniqueName("Filter")
        state.session.perform("New Filter") { tx in created = tx.create(.filters, name: n, data: .filter(ViewFilterData(categories: [], rules: []))) }
        if let created { selection = created; select(created) }
    }

    func duplicate() {
        save()
        guard let id = selection, let f = model[id], let d = f.viewFilter else { return }
        var created: ElementID?
        let n = uniqueName(f.name + " Copy")
        state.session.perform("Duplicate Filter") { tx in created = tx.create(.filters, name: n, data: .filter(d)) }
        if let created { selection = created; select(created) }
    }

    func delete() {
        guard let id = selection else { return }
        state.session.perform("Delete Filter") { tx in
            for v in tx.model.views where v.view?.visibility.filters.contains(where: { $0.filterID == id }) == true {
                tx.update(v.id) { $0.view?.visibility.filters.removeAll { $0.filterID == id } }
            }
            for t in tx.model.elements(.viewTemplates) where t.viewTemplate?.visibility?.filters.contains(where: { $0.filterID == id }) == true {
                tx.update(t.id) { $0.viewTemplate?.visibility?.filters.removeAll { $0.filterID == id } }
            }
            tx.delete(id)
        }
        loaded = nil
        select(filters.first?.id)
    }

    func close() { if let onClose { onClose() } else { state.presented = nil } }
}

/// One filter rule: parameter, operator and value (typed per the parameter: lengths parse with project units,
/// element references pick from a list).
private struct RuleRow: View {
    @Binding var rule: FilterRule
    let parameters: [(id: ParameterID, name: String, type: ParamType)]
    let model: BIMModel
    let remove: () -> Void
    @State private var text = ""

    var type: ParamType { parameters.first { $0.id == rule.parameter }?.type ?? .text }

    var body: some View {
        HStack {
            Picker("", selection: $rule.parameter) {
                ForEach(parameters, id: \.id) { p in Text(p.name).tag(p.id) }
                if !parameters.contains(where: { $0.id == rule.parameter }) { Text(rule.parameter.key).tag(rule.parameter) }
            }
            .labelsHidden().frame(width: 150).accessibilityLabel("Parameter")
            Picker("", selection: $rule.op) { ForEach(FilterRule.Op.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .labelsHidden().frame(width: 150).accessibilityLabel("Operator")
            if rule.op != .hasValue && rule.op != .hasNoValue { valueField }
            Spacer(minLength: 0)
            Button { remove() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Remove rule").accessibilityLabel("Remove rule")
        }
        .onAppear { text = Parameters.format(rule.value, type: type, model: model) }
        .onChange(of: rule.parameter) { _, _ in text = ""; rule.value = .text("") }
    }

    @ViewBuilder var valueField: some View {
        switch type {
        case .elementRef(let c):
            Picker("", selection: Binding(get: { rule.value.refValue }, set: { rule.value = .ref($0) })) {
                Text("<none>").tag(ElementID?.none)
                ForEach(model.elements(c), id: \.id) { e in Text(e.name).tag(Optional(e.id)) }
            }.labelsHidden().frame(width: 160)
        case .choice(let options):
            Picker("", selection: Binding(get: { rule.value.textValue ?? "" }, set: { rule.value = .text($0) })) {
                Text("").tag("")
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().frame(width: 160)
        case .bool:
            Picker("", selection: Binding(get: { rule.value.boolValue ?? true }, set: { rule.value = .bool($0) })) { Text("Yes").tag(true); Text("No").tag(false) }
                .labelsHidden().frame(width: 90)
        default:
            TextField("Value", text: $text).textFieldStyle(.roundedBorder).frame(width: 160)
                .onChange(of: text) { _, t in
                    if type.unitKind != nil, let v = try? Parameters.parse(t, type: type, model: model) { rule.value = v } else { rule.value = .text(t) }
                }
                .accessibilityLabel("Value")
        }
    }
}
