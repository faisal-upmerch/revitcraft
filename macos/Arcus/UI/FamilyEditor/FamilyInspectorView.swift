import SwiftUI
import AppKit
import ArcusDomain

// W4-FAMED: the Properties pane of the Family Editor. Shows the family when nothing is selected, otherwise the selected
// type, parameter, reference plane, dimension, form, line, label or nested instance. Rows are label-over-control so
// nothing is truncated at 300 pt; the whole pane scrolls.

struct FamilyInspectorView: View {
    @Bindable var model: FamilyEditorModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    switch model.selection {
                    case nil: FamilyPropertiesSection(model: model)
                    case .type(let n)?: TypeInspector(model: model, name: n)
                    case .parameter(let n)?: ParameterInspector(model: model, name: n)
                    case .plane(let n)?: PlaneInspector(model: model, name: n)
                    case .dimension(let id)?: DimensionInspector(model: model, id: id)
                    case .solid(let id)?: SolidInspector(model: model, id: id)
                    case .line(let id)?: LineInspector(model: model, id: id)
                    case .label(let id)?: LabelInspector(model: model, id: id)
                    case .nested(let id)?: NestedInspector(model: model, id: id)
                    case .modelLine(let id)?: ModelLineInspector(model: model, id: id) // F1415
                    case .control(let id)?: ControlInspector(model: model, id: id)
                    case .modelText(let id)?: ModelTextInspector(model: model, id: id)
                    case .fill(let id)?: FillInspector(model: model, id: id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 300)
        .controlSize(.small)
    }

    var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Properties").font(.headline)
                Text(model.selection.map { kind($0) + " · " + model.title($0) } ?? "Family: \(model.family.name)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let s = model.selection {
                Button { model.select(nil) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Show the family's properties")
                Button(role: .destructive) { model.deleteSelection() } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("Delete \(model.title(s))")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    func kind(_ i: FamilyEditing.Item) -> String {
        switch i {
        case .type: "Type"; case .parameter: "Parameter"; case .plane: "Reference Plane"; case .dimension: "Dimension"
        case .solid: "Form"; case .line: "Line"; case .label: "Label"; case .nested: "Nested Family"
        case .modelLine(let id): model.family.modelLines.first { $0.id == id }?.isReference == true ? "Reference Line" : "Model Line" // F1415
        case .control: "Control"; case .modelText: "Model Text"
        case .fill(let id): model.family.fills.first { $0.id == id }?.isMasking == true ? "Masking Region" : "Filled Region"
        }
    }
}

/// A labelled inspector row: caption above the control, full width.
struct InspectorRow<Content: View>: View {
    let label: String
    var help: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(Tokens.groupHeader).foregroundStyle(.secondary)
            content.frame(maxWidth: .infinity, alignment: .leading)
        }
        .help(help ?? "")
    }
}

struct InspectorGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
    }
}

/// A text field that looks like a field (the inspector's editable values).
struct InspectorField: View {
    let text: String
    var placeholder = ""
    var mono = false
    let commit: (String) -> Void
    var body: some View {
        ValueField(text: text, placeholder: placeholder, commit: commit)
            .font(mono ? .system(.body, design: .monospaced) : .body)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
    }
}

// MARK: Family

struct FamilyPropertiesSection: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        InspectorGroup(title: "Family") {
            InspectorRow(label: "Name") {
                InspectorField(text: model.family.name, placeholder: "Family name") { v in
                    let n = v.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty else { return }
                    model.edit("Rename Family") { $0.name = n }
                }
            }
            InspectorRow(label: "Category") {
                HStack {
                    Text(model.family.template.rawValue)
                    Spacer()
                    Button("Change…") { model.sheet = .categoryAndParameters }
                }
            }
            Toggle("Shared", isOn: Binding(get: { model.family.isShared }, set: { v in model.edit(v ? "Make Shared" : "Make Not Shared") { $0.isShared = v } }))
                .help("When this family is nested in another and that family is loaded into a project, a shared family is loaded too, so it can be placed, scheduled and edited on its own.")
            InspectorRow(label: "Description") { InspectorField(text: model.family.description) { v in model.edit("Edit Description") { $0.description = v } } }
            InspectorRow(label: "Manufacturer") { InspectorField(text: model.family.manufacturer) { v in model.edit("Edit Manufacturer") { $0.manufacturer = v } } }
        }
        InspectorGroup(title: "Family Types") {
            InspectorRow(label: "Current type") {
                Picker("", selection: $model.currentType) { ForEach(model.family.types) { Text($0.name).tag($0.name) } }.labelsHidden()
            }
            HStack {
                Button("New…") { model.newType(copying: false) }
                Button("Duplicate…") { model.newType(copying: true) }
                Button("Rename…") { model.renameType() }
                Button("Delete") { model.deleteType() }.disabled(model.family.types.count <= 1)
            }
            TypeValuesList(model: model)
            Button("Family Types…") { model.sheet = .familyTypes }.help("Every type side by side with values and formulas.")
        }
        InspectorGroup(title: "Contents") {
            let f = model.family
            Text("\(f.referencePlanes.count) reference planes · \(f.dimensions.count) dimensions · \(f.solids.count) forms · \(f.planLines.count + f.annotationLines.count) lines · \(f.labels.count) labels · \(f.nestedInstances.count) nested")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("Select an element in the browser or on the canvas to edit it here. Drag a reference plane on the canvas to move it; a labelled plane changes its parameter.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The current type's parameter values grouped by parameter group.
struct TypeValuesList: View {
    let model: FamilyEditorModel
    var groups: [(ParameterGroup, [FamilyParameter])] {
        Dictionary(grouping: model.family.parameters, by: \.group).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groups, id: \.0) { group, params in
                Text(group.rawValue).font(Tokens.groupHeader).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(params) { p in
                    HStack(spacing: 6) {
                        Text(p.name).lineLimit(1).frame(minWidth: 60, maxWidth: 130, alignment: .leading).help(p.name)
                        FamilyValueCell(model: model, parameter: p)
                        if p.formula != nil { Image(systemName: "function").font(.caption2).foregroundStyle(.secondary).help("= \(p.formula!)") }
                        if p.isInstance { Text("(instance)").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
            }
        }
    }
}

/// Value editor for one parameter in the current type: field, checkbox, material picker, or the formula's result.
struct FamilyValueCell: View {
    let model: FamilyEditorModel
    let parameter: FamilyParameter
    var body: some View {
        let p = parameter
        if p.formula != nil {
            Text(model.value(p)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        } else if p.type == .bool {
            let on = (model.family.type(named: model.currentType)?.values[p.name] ?? p.type.defaultValue).boolValue ?? false
            Toggle("", isOn: Binding(get: { on }, set: { model.setRawValue(p, .bool($0)) })).labelsHidden().toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
        } else if case .elementRef(.materials) = p.type {
            let current = (model.family.type(named: model.currentType)?.values[p.name])?.refValue
            Picker("", selection: Binding(get: { current?.raw ?? 0 }, set: { v in model.setRawValue(p, .ref(v == 0 ? nil : ElementID(v))) })) {
                Text("By Category").tag(UInt64(0))
                ForEach(model.state.model.elements(.materials), id: \.id) { m in Text(m.name).tag(m.id.raw) }
            }
            .labelsHidden().frame(maxWidth: .infinity)
        } else {
            InspectorField(text: model.value(p)) { model.setValue(p, $0) }
        }
    }
}

// MARK: Type

struct TypeInspector: View {
    @Bindable var model: FamilyEditorModel
    let name: String
    var body: some View {
        InspectorGroup(title: "Type") {
            InspectorRow(label: "Name") {
                InspectorField(text: name) { v in
                    let n = v.trimmingCharacters(in: .whitespaces)
                    guard !n.isEmpty, n != name else { return }
                    guard model.family.type(named: n) == nil else { model.message = "A type named “\(n)” already exists."; return }
                    model.edit("Rename Type") { FamilyEditing.renameType(&$0, name, to: n) }
                    model.currentType = n; model.selection = .type(n)
                }
            }
            HStack {
                Button("Duplicate…") { model.newType(copying: true) }
                Button("Delete") { model.deleteType() }.disabled(model.family.types.count <= 1)
                Spacer()
                Button("Family Types…") { model.sheet = .familyTypes }
            }
        }
        InspectorGroup(title: "Values") { TypeValuesList(model: model) }
    }
}

// MARK: Parameter

struct ParameterInspector: View {
    @Bindable var model: FamilyEditorModel
    let name: String
    var body: some View {
        if let p = model.family.parameter(named: name) {
            InspectorGroup(title: "Parameter") {
                InspectorRow(label: "Name") {
                    InspectorField(text: p.name) { v in model.renameParameter(p.name, to: v) }.disabled(p.isBuiltIn)
                }
                InspectorRow(label: "Type of parameter") { Text(p.type.displayName) }
                InspectorRow(label: "Kind") {
                    Picker("", selection: Binding(get: { p.isInstance }, set: { v in model.updateParameter(p.name, v ? "Make Instance Parameter" : "Make Type Parameter") { $0.isInstance = v } })) {
                        Text("Type").tag(false); Text("Instance").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize() // W4-AUDIT: never wraps "Instance"
                }
                InspectorRow(label: "Group") {
                    Picker("", selection: Binding(get: { p.group }, set: { g in model.updateParameter(p.name, "Change Parameter Group") { $0.group = g } })) {
                        ForEach(ParameterGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                InspectorRow(label: "Formula", help: "Parameter names, units (600 mm, 2'), + − × ÷, if(), and(), not(), sin() in degrees, sqrt()…") {
                    InspectorField(text: p.formula ?? "", placeholder: "=", mono: true) { f in
                        let t = f.trimmingCharacters(in: .whitespaces)
                        model.updateParameter(p.name, "Formula") { $0.formula = t.isEmpty ? nil : t }
                    }
                }
                InspectorRow(label: "Value in \(model.currentType)") { FamilyValueCell(model: model, parameter: p) }
                if p.isBuiltIn { Text("Built-in parameter: it can't be renamed or deleted.").font(.caption2).foregroundStyle(.tertiary) }
            }
        }
    }
}

// MARK: Reference plane

struct PlaneInspector: View {
    @Bindable var model: FamilyEditorModel
    let name: String
    var body: some View {
        if let p = model.family.referencePlanes.first(where: { $0.name == name }) {
            InspectorGroup(title: "Reference Plane") {
                InspectorRow(label: "Name") { InspectorField(text: p.name) { v in model.renamePlane(p.name, to: v) } }
                InspectorRow(label: "Axis") { Text("\(p.axis.rawValue) — \(p.axis == .z ? "horizontal plane at a height" : "vertical plane along " + (p.axis == .x ? "the width" : "the depth"))") }
                InspectorRow(label: "Sketch offset", help: "A number in metres or a formula. Dimensions move the plane to satisfy them; unconstrained planes stay at their offsets.") {
                    InspectorField(text: p.offset, mono: true) { v in model.updatePlane(p.name) { $0.offset = v } }.disabled(p.definesOrigin)
                }
                InspectorRow(label: "Position (\(model.currentType))") { Text(model.length(model.evaluated.planes[p.name] ?? 0)).foregroundStyle(.secondary) }
                InspectorRow(label: "Is Reference") {
                    Picker("", selection: Binding(get: { p.strength }, set: { s in model.updatePlane(p.name) { $0.strength = s } })) {
                        ForEach(ReferenceStrength.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                if p.definesOrigin { Label("Defines the family origin; it doesn't move.", systemImage: "scope").font(.caption).foregroundStyle(.secondary) }
                let dims = model.family.dimensions.filter { [$0.planeA, $0.planeB, $0.planeC].contains(p.name) }
                if !dims.isEmpty {
                    InspectorRow(label: "Constrained by") {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(dims) { d in Button(model.title(.dimension(d.id))) { model.select(.dimension(d.id)) }.buttonStyle(.link) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Dimension

struct DimensionInspector: View {
    @Bindable var model: FamilyEditorModel
    let id: String
    static let newParameterTag = "\u{1}new-parameter"

    var body: some View {
        if let d = model.family.dimensions.first(where: { $0.id == id }) {
            let axis = model.family.referencePlanes.first { $0.name == d.planeA }?.axis
            let conflict = model.evaluated.conflictingDimensions.contains(d.id)
            InspectorGroup(title: d.isEquality ? "Equality Constraint (EQ)" : "Dimension") {
                InspectorRow(label: "Plane A") {
                    planePicker(d.planeA, axis: nil) { v in
                        let newAxis = model.family.referencePlanes.first { $0.name == v }?.axis
                        model.updateDimension(d.id) { dim in
                            dim.planeA = v
                            let planes = model.family.referencePlanes
                            if planes.first(where: { $0.name == dim.planeB })?.axis != newAxis { dim.planeB = planes.first { $0.axis == newAxis && $0.name != v }?.name ?? dim.planeB }
                            if let c = dim.planeC, planes.first(where: { $0.name == c })?.axis != newAxis { dim.planeC = planes.first { $0.axis == newAxis && $0.name != v && $0.name != dim.planeB }?.name }
                        }
                    }
                }
                InspectorRow(label: d.isEquality ? "Middle plane (B)" : "Plane B") { planePicker(d.planeB, axis: axis) { v in model.updateDimension(d.id) { $0.planeB = v } } }
                if d.isEquality {
                    InspectorRow(label: "Plane C") { planePicker(d.planeC, axis: axis) { v in model.updateDimension(d.id) { $0.planeC = v } } }
                } else {
                    InspectorRow(label: "Label", help: "Label a dimension with a length parameter to drive it: the parameter's value sets the distance.") {
                        Picker("", selection: Binding(get: { d.labelParameter ?? "" }, set: { v in
                            if v == Self.newParameterTag { model.createLabelParameter(for: d); return }
                            model.updateDimension(d.id) { $0.labelParameter = v.isEmpty ? nil : v; if !v.isEmpty { $0.isLocked = false } }
                        })) {
                            Text("<None>").tag("")
                            ForEach(model.lengthParameters) { Text($0.name).tag($0.name) }
                            Divider()
                            Text("Add Parameter…").tag(Self.newParameterTag)
                        }
                        .labelsHidden()
                    }
                    Toggle("Lock the sketched distance", isOn: Binding(get: { d.isLocked }, set: { v in model.updateDimension(d.id) { $0.isLocked = v } }))
                        .disabled(d.labelParameter != nil)
                        .help(d.labelParameter != nil ? "A labeled dimension is driven by its parameter." : "Keep the current distance while other planes flex.")
                }
                InspectorRow(label: "Value (\(model.currentType))") {
                    HStack(spacing: 4) {
                        if conflict { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).help("This constraint conflicts with others and isn't satisfied.") }
                        Text(valueText(d)).font(Tokens.monoDigits).foregroundStyle(conflict ? .red : .secondary)
                    }
                }
                Text(d.isEquality ? "EQ keeps the middle plane midway between A and C, so flexing the outer planes moves it." : "The sketched offsets of A and B set the distance until a label or lock constrains it.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func planePicker(_ current: String?, axis: FamilyAxis?, set: @escaping (String) -> Void) -> some View {
        let choices = model.family.referencePlanes.filter { axis == nil || $0.axis == axis }
        return Picker("", selection: Binding(get: { current ?? "" }, set: { if !$0.isEmpty { set($0) } })) {
            if current == nil { Text("—").tag("") }
            ForEach(choices) { Text($0.name).tag($0.name) }
            if let current, !choices.contains(where: { $0.name == current }) { Text("\(current) (missing)").tag(current) }
        }
        .labelsHidden()
    }

    func valueText(_ d: FamilyDimension) -> String {
        guard let a = model.evaluated.planes[d.planeA], let b = model.evaluated.planes[d.planeB] else { return "—" }
        if d.isEquality, let cn = d.planeC, let c = model.evaluated.planes[cn] { return "\(model.length(abs(b - a))) = \(model.length(abs(c - b)))" }
        return model.length(abs(b - a))
    }
}

// MARK: Form

struct SolidInspector: View {
    @Bindable var model: FamilyEditorModel
    let id: String
    var body: some View {
        if let s = model.family.solids.first(where: { $0.id == id }) {
            InspectorGroup(title: (s.isVoid ? "Void " : "") + s.profile.formName) {
                InspectorRow(label: "Name") {
                    InspectorField(text: s.name) { n in
                        let t = n.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        model.updateSolid(s.id, "Rename Form") { $0.name = t }
                    }
                }
                HStack {
                    Button("Duplicate") { model.duplicateSelection() }
                    Toggle("Void", isOn: Binding(get: { s.isVoid }, set: { v in model.updateSolid(s.id, v ? "Make Void" : "Make Solid") { $0.isVoid = v } }))
                        .disabled(!s.profile.isExtrusion)
                        .help("Void extrusions cut solid extrusions.")
                }
            }
            InspectorGroup(title: "Shape") {
                FamilySolidEditor(model: model, solid: s)
                Text("Metres in family space (X along the width, Y toward the front, Z up). A field takes a reference plane name, which locks the face to the plane, or a formula.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Line

struct LineInspector: View {
    @Bindable var model: FamilyEditorModel
    let id: String
    var body: some View {
        if let l = model.family.planLines.first(where: { $0.id == id }) ?? model.family.annotationLines.first(where: { $0.id == id }) {
            let plan = model.family.planLines.contains { $0.id == id }
            InspectorGroup(title: plan ? "Plan Symbolic Line" : "Annotation Line") {
                switch l.shape {
                case .line(let a, let b):
                    InspectorRow(label: "From") { FamilyPointField(model: model, point: a, labels: ("x", "y")) { p in model.updatePlanLine(l.id) { $0.shape = .line(p, b) } } }
                    InspectorRow(label: "To") { FamilyPointField(model: model, point: b, labels: ("x", "y")) { p in model.updatePlanLine(l.id) { $0.shape = .line(a, p) } } }
                case .arc(let c, let r, let sa, let sw):
                    InspectorRow(label: "Center") { FamilyPointField(model: model, point: c, labels: ("x", "y")) { p in model.updatePlanLine(l.id) { $0.shape = .arc(center: p, radius: r, startDegrees: sa, sweepDegrees: sw) } } }
                    InspectorRow(label: "Radius") { InspectorField(text: r, mono: true) { v in model.updatePlanLine(l.id) { $0.shape = .arc(center: c, radius: v, startDegrees: sa, sweepDegrees: sw) } } }
                    HStack {
                        InspectorRow(label: "Start °") { InspectorField(text: sa, mono: true) { v in model.updatePlanLine(l.id) { $0.shape = .arc(center: c, radius: r, startDegrees: v, sweepDegrees: sw) } } }
                        InspectorRow(label: "Sweep °") { InspectorField(text: sw, mono: true) { v in model.updatePlanLine(l.id) { $0.shape = .arc(center: c, radius: r, startDegrees: sa, sweepDegrees: v) } } }
                    }
                }
                InspectorRow(label: "Subcategory") {
                    Picker("", selection: Binding(get: { l.subcategory }, set: { v in model.updatePlanLine(l.id) { $0.subcategory = v } })) {
                        ForEach(FamilySubcategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                }
                InspectorRow(label: "Line weight") {
                    Stepper(value: Binding(get: { l.weight }, set: { v in model.updatePlanLine(l.id) { $0.weight = v } }), in: 1...16) { Text("\(l.weight)") }
                }
            }
            InspectorGroup(title: "Visibility") {
                FamilyVisibilityControls(model: model, visibleAt: l.visibleAt, parameter: l.visibilityParameter,
                                         setLevels: { v in model.updatePlanLine(l.id) { $0.visibleAt = v } },
                                         setParameter: { p in model.updatePlanLine(l.id) { $0.visibilityParameter = p } })
                Text("Symbolic lines replace the cut outline of forms in plan views. Uncheck a detail level to hide the line there.")
                    .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Label

struct LabelInspector: View {
    @Bindable var model: FamilyEditorModel
    let id: String
    var body: some View {
        if let l = model.family.labels.first(where: { $0.id == id }) {
            InspectorGroup(title: l.parameterName == nil ? "Text" : "Label") {
                InspectorRow(label: "Shows") {
                    Picker("", selection: Binding(get: { l.parameterName ?? "" }, set: { v in model.updateLabel(l.id) { $0.parameterName = v.isEmpty ? nil : v } })) {
                        Text("Static text").tag("")
                        ForEach(model.family.parameters) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                }
                if l.parameterName == nil {
                    InspectorRow(label: "Text") { InspectorField(text: l.staticText) { v in model.updateLabel(l.id) { $0.staticText = v } } }
                } else {
                    InspectorRow(label: "Sample value") { InspectorField(text: l.sample) { v in model.updateLabel(l.id) { $0.sample = v } } }
                }
                InspectorRow(label: "Position") { FamilyPointField(model: model, point: l.position, labels: ("x", "y")) { p in model.updateLabel(l.id) { $0.position = p } } }
                InspectorRow(label: "Text height (paper mm)") {
                    InspectorField(text: FamilyEditing.numberText(l.height * 1000), mono: true) { v in if let h = Double(v), h > 0 { model.updateLabel(l.id) { $0.height = h / 1000 } } }
                }
                HStack {
                    Toggle("Bold", isOn: Binding(get: { l.bold }, set: { v in model.updateLabel(l.id) { $0.bold = v } }))
                    Picker("Alignment", selection: Binding(get: { l.alignment }, set: { v in model.updateLabel(l.id) { $0.alignment = v } })) {
                        ForEach(ArcusDomain.TextAlignment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }
        }
    }
}

// MARK: Nested instance

struct NestedInspector: View {
    @Bindable var model: FamilyEditorModel
    let id: String
    var body: some View {
        if let inst = model.family.nestedInstances.first(where: { $0.id == id }) {
            InspectorGroup(title: "Nested Family Instance") {
                Text(inst.familyName).font(.headline)
                NestedInstanceEditor(model: model, instance: inst)
            }
        }
    }
}
