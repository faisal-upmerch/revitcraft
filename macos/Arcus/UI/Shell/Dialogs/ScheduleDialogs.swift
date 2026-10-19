import SwiftUI
import ArcusDomain
import ArcusApplication
import ArcusOutput

struct NewScheduleDialog: View {
    let state: DocumentState
    let kind: ScheduleKind
    @State private var category: Category = .doors
    @State private var name = ""
    var body: some View {
        DialogFrame(title: kind == .materialTakeoff ? "New Material Takeoff" : "New Schedule", okDisabled: name.isEmpty, state: state) {
            var def = ScheduleDefinition(kind: kind, categories: [category], fields: defaultFields())
            def.sorting = def.fields.isEmpty ? [] : [ScheduleSort(fieldID: def.fields[0].id)]
            def.grandTotals = true
            var created: ElementID?
            let n = name
            state.session.perform("Create Schedule") { tx in created = tx.create(.schedules, name: n, data: .schedule(def)) }
            state.presented = nil
            if let created { state.open(created); state.presented = .scheduleProperties(created) }
        } content: {
            FormRow(label: "Category") {
                Picker("", selection: $category) { ForEach(Category.schedulable.filter { ![.sheets, .views, .revisions].contains($0) }, id: \.self) { Text($0.displayName).tag($0) } }.labelsHidden()
            }
            FormRow(label: "Name") { TextField("", text: $name).textFieldStyle(.roundedBorder) }
        }
        .onAppear { name = "\(category.singularName) \(kind == .materialTakeoff ? "Material Takeoff" : "Schedule")" }
        .onChange(of: category) { _, c in name = "\(c.singularName) \(kind == .materialTakeoff ? "Material Takeoff" : "Schedule")" }
    }
    func defaultFields() -> [ScheduleField] {
        if kind == .materialTakeoff {
            var fs = [ScheduleField(source: .material("Name"), heading: "Material", width: 0.05), ScheduleField(source: .material("Area"), heading: "Area", width: 0.025, alignment: .right),
                      ScheduleField(source: .material("Volume"), heading: "Volume", width: 0.025, alignment: .right)]
            fs[1].total = .total; fs[2].total = .total
            return fs
        }
        var fs = [ScheduleTemplates.field("familyAndType", "Family and Type", width: 0.05), ScheduleTemplates.field("level", "Level", width: 0.03)]
        switch category {
        case .walls: fs += [ScheduleTemplates.field("q.length", "Length", total: .total, align: .right), ScheduleTemplates.field("q.area", "Area", total: .total, align: .right)]
        case .floors, .ceilings, .roofs: fs += [ScheduleTemplates.field("q.area", "Area", total: .total, align: .right), ScheduleTemplates.field("q.volume", "Volume", total: .total, align: .right)]
        case .rooms, .spaces: fs = [ScheduleTemplates.field("room.number", "Number"), ScheduleTemplates.field("name", "Name", width: 0.04), ScheduleTemplates.field("q.area", "Area", total: .total, align: .right)] // F5: spaces
        case .mass: fs = [ScheduleTemplates.field("name", "Name", width: 0.04), ScheduleTemplates.field("level", "Level", width: 0.03), // F5
                          ScheduleTemplates.field("mass.grossFloorArea", "Gross Floor Area", total: .total, align: .right),
                          ScheduleTemplates.field("mass.grossVolume", "Gross Volume", total: .total, align: .right)]
        case .structuralRebar, .areaReinforcement, .pathReinforcement: // F34: rebar quantities
            fs += [ScheduleTemplates.field("rebar.quantity", "Quantity", total: .total, align: .right), ScheduleTemplates.field("rebar.totalLength", "Total Bar Length", total: .total, align: .right)]
        default: fs.insert(ScheduleTemplates.field("mark", "Mark", width: 0.015), at: 0)
        }
        fs.append(ScheduleField(source: .count, heading: "Count", width: 0.015, alignment: .right))
        return fs
    }
}

/// Schedule Properties: Fields, Filter, Sorting/Grouping, Formatting and Appearance of a schedule. OK applies every
/// change as one undo step. (BL-SCHED: opened on a tab from the Properties palette and the schedule ribbon.)
struct SchedulePropertiesDialog: View {
    let state: DocumentState
    let scheduleID: ElementID
    var initialTab = 0
    var initialField: String?
    @State private var def = ScheduleDefinition(kind: .category, categories: [])
    @State private var tab = 0
    @State private var selectedField: String?
    @State private var selectedAvailable: ParameterID?
    @State private var available: [ParameterEntry] = []
    @State private var formulaName = "Calculated"
    @State private var formulaText = ""
    @State private var formulaType: ParamType = .number
    @State private var sample: Element?

    var body: some View {
        DialogFrame(title: "Schedule Properties – \(state.model[scheduleID]?.name ?? "")", state: state) {
            let d = def
            state.session.perform("Edit Schedule") { tx in tx.update(scheduleID) { $0.schedule = d } }
            if let e = state.session.lastError { state.show(e.message, error: true); state.session.clearError() } else { state.presented = nil }
        } content: {
            Picker("", selection: $tab) { ForEach(ScheduleTab.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) } }
                .pickerStyle(.segmented).labelsHidden()
                .accessibilityLabel("Schedule Properties tab")
            Group {
                switch ScheduleTab(rawValue: tab) ?? .fields {
                case .fields: fieldsTab
                case .filter: filterTab
                case .sorting: sortTab
                case .formatting: formatTab
                case .appearance: appearanceTab
                }
            }
            .frame(minHeight: 340)
        }
        .frame(minWidth: 780, idealWidth: 780, minHeight: 540, idealHeight: 540)
        .onAppear {
            def = state.model[scheduleID]?.schedule ?? def
            tab = initialTab
            selectedField = initialField
            let m = state.model
            sample = m.elements(def.categories).first(where: { !$0.isType }) ?? m.elements(def.categories).first
            if let sample { available = Parameters.allEntries(sample, m) }
            if def.kind.isFabrication || def.kind == .materialTakeoff { available = FabricationSchedules.availableEntries(def.kind) + (def.kind.isFabrication ? [] : available) } // FM7
            var seen = Set<ParameterID>()
            available = available.filter { seen.insert($0.id).inserted }
        }
    }

    // MARK: Fields

    var unscheduled: [ParameterEntry] {
        available.filter { e in !def.fields.contains { if case .parameter(let p) = $0.source { return p == e.id }; return false } && !FabricationSchedules.schedules(def, e) } // FM7
    }

    func add(_ e: ParameterEntry) {
        let f = FabricationSchedules.field(for: e, def.kind) // FM7: fabrication and material fields
            ?? ScheduleField(source: .parameter(e.id), heading: e.name, width: e.type.isNumeric ? 0.022 : 0.03, alignment: e.type.isNumeric ? .right : .left)
        def.insertField(f, before: nil)
        selectedField = f.id
        selectedAvailable = nil
    }

    var fieldsTab: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading) {
                Text("Available fields").font(.caption).foregroundStyle(.secondary)
                List(unscheduled, id: \.id, selection: $selectedAvailable) { e in
                    HStack { Text(e.name); Spacer(); Text(e.isType ? "Type" : "").font(.caption2).foregroundStyle(.secondary) }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { add(e) }
                        .tag(e.id)
                }
                .frame(minHeight: 200)
                HStack {
                    Button("Add →") { if let id = selectedAvailable, let e = available.first(where: { $0.id == id }) { add(e) } }
                        .disabled(selectedAvailable == nil)
                    Text("or double-click").font(.caption2).foregroundStyle(.tertiary)
                }
                GroupBox("Calculated value") {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Name", text: $formulaName)
                        TextField("Formula, e.g. Area * 1.1", text: $formulaText).font(.system(.body, design: .monospaced))
                        Picker("Type", selection: $formulaType) { ForEach([ParamType.number, .length, .area, .volume, .currency, .text], id: \.self) { Text($0.displayName).tag($0) } }
                        HStack {
                            Button("Add") {
                                def.fields.append(ScheduleField(source: .formula(formulaText, formulaType), heading: formulaName, width: 0.03, alignment: .right))
                            }.disabled(formulaText.isEmpty || formulaName.isEmpty)
                            Button("Add Count") { def.fields.append(ScheduleField(source: .count, heading: "Count", width: 0.015, alignment: .right)) }
                        }
                        Text("Formulas use the headings of other fields.").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(width: 290)
            VStack(alignment: .leading) {
                Text("Scheduled fields (in order)").font(.caption).foregroundStyle(.secondary)
                List(selection: $selectedField) {
                    ForEach(def.fields) { f in
                        HStack {
                            Text(f.heading)
                            Spacer()
                            if f.hidden { Text("hidden").font(.caption2).foregroundStyle(.secondary) }
                            if case .formula = f.source { Text("calculated").font(.caption2).foregroundStyle(.secondary) }
                        }.tag(f.id)
                    }
                    .onMove { def.fields.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(minHeight: 340)
                HStack {
                    Button("Remove") { if let id = selectedField { def.removeField(id) }; selectedField = nil }.disabled(selectedField == nil)
                    Button("Move Up") { move(-1) }.disabled(selectedField == nil)
                    Button("Move Down") { move(1) }.disabled(selectedField == nil)
                    Spacer()
                    Toggle("Itemize every instance", isOn: $def.itemizeEveryInstance)
                }
            }
        }
    }

    func move(_ d: Int) {
        guard let id = selectedField, let i = def.fields.firstIndex(where: { $0.id == id }) else { return }
        let j = i + d
        guard j >= 0, j < def.fields.count else { return }
        def.fields.swapAt(i, j)
    }

    // MARK: Filter

    /// Drop-down values for filtering on a field (levels, types, Yes/No…), or nil for typed values.
    func filterOptions(_ fieldID: String) -> [String]? {
        guard let f = def.field(fieldID), let sample else { return nil }
        let type = ScheduleEngine.fieldType(f, def, state.model)
        if case .parameter(let p) = f.source, p == ParameterID("typeName") { return nil }
        return ScheduleEditing.options(for: type, elements: [sample], model: state.model)?.map(\.title)
    }

    var filterTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(def.filters.indices, id: \.self) { i in
                HStack {
                    Text(i == 0 ? "Filter by" : "And").frame(width: 60, alignment: .trailing)
                    Picker("", selection: $def.filters[i].fieldID) { ForEach(def.fields) { Text($0.heading).tag($0.id) } }.labelsHidden().frame(width: 170)
                    Picker("", selection: $def.filters[i].op) { ForEach(FilterRule.Op.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 190)
                    if ScheduleEditing.opNeedsValue(def.filters[i].op) {
                        let text = Binding(get: { def.filters[i].value.textValue ?? def.filters[i].value.description }, set: { def.filters[i].value = .text($0) })
                        if let opts = filterOptions(def.filters[i].fieldID) {
                            Picker("", selection: text) {
                                Text("").tag("")
                                ForEach(opts, id: \.self) { Text($0).tag($0) }
                            }.labelsHidden().frame(minWidth: 160)
                        } else {
                            TextField("Value", text: text).textFieldStyle(.roundedBorder)
                        }
                    } else {
                        Spacer()
                    }
                    Button { def.filters.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        .accessibilityLabel("Remove filter rule")
                }
            }
            Button("Add Filter Rule") { if let f = def.fields.first { def.filters.append(ScheduleFilter(fieldID: f.id, op: .equals, value: .text(""))) } }
                .disabled(def.fields.isEmpty || def.filters.count >= 8)
            Text("Rules combine with AND. Numbers use project units (900 or 2.1 m); levels, types and Yes/No match by name. Hidden fields can filter too.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Sorting/Grouping

    var sortTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(def.sorting.indices, id: \.self) { i in
                HStack {
                    Text(i == 0 ? "Sort by" : "Then by").frame(width: 60, alignment: .trailing)
                    Picker("", selection: $def.sorting[i].fieldID) { ForEach(def.fields) { Text($0.heading).tag($0.id) } }.labelsHidden().frame(width: 170)
                    Picker("", selection: $def.sorting[i].ascending) { Text("Ascending").tag(true); Text("Descending").tag(false) }.labelsHidden().frame(width: 110)
                    Toggle("Header", isOn: $def.sorting[i].header)
                    Toggle("Footer", isOn: $def.sorting[i].footer)
                    if def.sorting[i].footer {
                        Toggle("Title, count", isOn: $def.sorting[i].footerShowsTitleCountTotals).help("Footer shows the group title and its element count")
                    }
                    Toggle("Blank line", isOn: $def.sorting[i].blankLine)
                    Button { def.sorting.remove(at: i) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                        .accessibilityLabel("Remove sort level")
                }
            }
            Button("Add Sort Level") { if let f = def.fields.first { def.sorting.append(ScheduleSort(fieldID: f.id)) } }.disabled(def.fields.isEmpty || def.sorting.count >= 4)
            Text("Groups come from the first level with a header, footer or blank line.").font(.caption).foregroundStyle(.secondary)
            Divider()
            HStack {
                Toggle("Grand totals", isOn: $def.grandTotals)
                if def.grandTotals { TextField("Title", text: $def.grandTotalTitle).textFieldStyle(.roundedBorder).frame(width: 200) }
            }
            Toggle("Itemize every instance", isOn: $def.itemizeEveryInstance)
            Spacer()
        }
    }

    // MARK: Formatting

    var formatTab: some View {
        HStack(alignment: .top) {
            List(def.fields, selection: $selectedField) { f in Text(f.heading).tag(f.id) }.frame(width: 200)
            if let id = selectedField, let i = def.fields.firstIndex(where: { $0.id == id }) {
                Form {
                    TextField("Heading", text: $def.fields[i].heading)
                    Picker("Alignment", selection: $def.fields[i].alignment) { ForEach(HorizontalAlign.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Toggle("Hidden field", isOn: $def.fields[i].hidden)
                    Picker("Totals", selection: $def.fields[i].total) { ForEach(ScheduleTotal.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    Stepper("Width: \(Int((def.fields[i].width * 1000).rounded())) mm", value: $def.fields[i].width, in: 0.008...0.2, step: 0.002)
                    Picker("Field format", selection: Binding(get: { def.fields[i].decimals ?? -1 }, set: { def.fields[i].decimals = $0 < 0 ? nil : $0 })) {
                        Text("Use project settings").tag(-1); ForEach(0...4, id: \.self) { Text("\($0) decimal place\($0 == 1 ? "" : "s")").tag($0) }
                    }
                    Toggle("Conditional format", isOn: Binding(get: { def.fields[i].conditionalFormat != nil }, set: { def.fields[i].conditionalFormat = $0 ? ConditionalFormat(op: .greater, value: .text("0"), background: RGBColor(1, 0.9, 0.6)) : nil }))
                    if def.fields[i].conditionalFormat != nil {
                        Picker("When value", selection: Binding(get: { def.fields[i].conditionalFormat!.op }, set: { def.fields[i].conditionalFormat!.op = $0 })) { ForEach(FilterRule.Op.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                        TextField("Compare to", text: Binding(get: { def.fields[i].conditionalFormat!.value.textValue ?? "" }, set: { def.fields[i].conditionalFormat!.value = .text($0) }))
                        ColorPicker("Background", selection: Binding(get: { def.fields[i].conditionalFormat!.background.color }, set: { def.fields[i].conditionalFormat!.background = RGBColor.from(NSColor($0)) }))
                    }
                }
            } else {
                Text("Select a field to format.").foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Appearance

    static let textHeights: [Double] = [0.0018, 0.002, 0.0022, 0.0025, 0.003, 0.0035, 0.005]

    func heightPicker(_ label: String, _ kp: WritableKeyPath<ScheduleAppearance, Double>) -> some View {
        Picker(label, selection: Binding(get: { def.appearance[keyPath: kp] }, set: { def.appearance[keyPath: kp] = $0 })) {
            ForEach(Self.textHeights, id: \.self) { Text(String(format: "%.1f mm", $0 * 1000)).tag($0) }
            if !Self.textHeights.contains(def.appearance[keyPath: kp]) { Text(String(format: "%.1f mm", def.appearance[keyPath: kp] * 1000)).tag(def.appearance[keyPath: kp]) }
        }
    }

    func toggle(_ label: String, _ kp: WritableKeyPath<ScheduleAppearance, Bool>) -> some View {
        Toggle(label, isOn: Binding(get: { def.appearance[keyPath: kp] }, set: { def.appearance[keyPath: kp] = $0 }))
    }

    var appearanceTab: some View {
        HStack(alignment: .top, spacing: 24) {
            Form {
                Section("Graphics") {
                    toggle("Grid lines", \.gridLines)
                    toggle("Outline (heavy frame)", \.outline)
                    toggle("Blank row before data", \.blankRowBeforeData)
                    Toggle("Header shading", isOn: Binding(get: { def.appearance.headerShading != nil }, set: { def.appearance.headerShading = $0 ? RGBColor(0.88, 0.9, 0.93) : nil }))
                    if def.appearance.headerShading != nil {
                        ColorPicker("Shading color", selection: Binding(get: { def.appearance.headerShading!.color }, set: { def.appearance.headerShading = RGBColor.from(NSColor($0)) }))
                    }
                }
            }
            .frame(width: 330)
            Form {
                Section("Text") {
                    Toggle("Show title", isOn: $def.showTitle)
                    Toggle("Show headers", isOn: $def.showHeaders)
                    heightPicker("Title text", \.titleTextHeight)
                    toggle("Bold title", \.boldTitle)
                    heightPicker("Header text", \.headerTextHeight)
                    toggle("Bold headers", \.boldHeaders)
                    heightPicker("Body text", \.bodyTextHeight)
                }
            }
            .frame(width: 330)
        }
    }
}

struct CSVImportDialog: View {
    let state: DocumentState
    let scheduleID: ElementID
    let url: URL
    @State private var headers: [String] = []
    @State private var keyColumn = "Mark"
    @State private var columns: Set<String> = []
    @State private var preview: CSVImportPreview?
    @State private var error: String?

    var body: some View {
        DialogFrame(title: "Import Schedule Values from CSV", subtitle: url.lastPathComponent, okTitle: "Apply \(preview?.changes.count ?? 0) Change(s)",
                    okDisabled: (preview?.changes.isEmpty ?? true), state: state) {
            guard let p = preview else { return }
            state.session.perform("Import CSV Values") { tx in _ = try ScheduleCSV.apply(p, in: tx) }
            if let e = state.session.lastError { error = e.message; state.session.clearError(); return }
            state.presented = nil
            state.show("Updated \(p.changes.count) value(s).")
        } content: {
            if let error { Text(error).foregroundStyle(.red) }
            FormRow(label: "Match rows by") {
                Picker("", selection: $keyColumn) { ForEach(headers, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 200)
            }
            Text("Columns to import (only writable parameters are applied):").font(.caption).foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading) { ForEach(headers.filter { $0 != keyColumn }, id: \.self) { h in
                Toggle(h, isOn: Binding(get: { columns.contains(h) }, set: { if $0 { columns.insert(h) } else { columns.remove(h) }; refresh() }))
            } } }.frame(height: 110)
            if let p = preview {
                Text("\(p.changes.count) change(s), \(p.errors.count) problem(s), \(p.unmatchedKeys.count) unmatched row(s)").font(.callout)
                List {
                    ForEach(p.changes.prefix(200), id: \.self) { c in Text("\(c.parameterName): “\(c.oldText)” → “\(c.newText)”").font(.caption.monospaced()) }
                    ForEach(p.errors.prefix(100), id: \.self) { e in Text("Row \(e.row), \(e.column): \(e.message)").font(.caption).foregroundStyle(.red) }
                }.frame(minHeight: 160)
            }
        }
        .frame(minWidth: 620, idealWidth: 620)
        .onAppear(perform: load)
        .onChange(of: keyColumn) { _, _ in refresh() }
    }

    func load() {
        do {
            let rows = try ScheduleCSV.parse(try Data(contentsOf: url))
            headers = rows.first ?? []
            keyColumn = headers.contains("Mark") ? "Mark" : (headers.first ?? "")
        } catch { self.error = "\(error)" }
    }
    func refresh() {
        guard let s = state.model[scheduleID], let data = try? Data(contentsOf: url) else { return }
        do { preview = try ScheduleCSV.preview(data, schedule: s, model: state.model, keyColumn: keyColumn, columns: columns); error = nil }
        catch { self.error = "\(error)"; preview = nil }
    }
}
