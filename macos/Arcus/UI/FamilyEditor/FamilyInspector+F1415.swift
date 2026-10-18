import SwiftUI
import ArcusDomain

// F1415: Properties of the Family Editor content from RevitCraft: model and reference lines, flip controls, model text and
// filled or masking regions.

struct ModelLineInspector: View {
    let model: FamilyEditorModel
    let id: String
    var body: some View {
        if let l = model.family.modelLines.first(where: { $0.id == id }) {
            InspectorGroup(title: l.isReference ? "Reference Line" : "Model Line") {
                Toggle("Reference line", isOn: Binding(get: { l.isReference }, set: { v in update { $0.isReference = v } }))
                    .help("Reference lines are datums: green in the editor and never shown in projects.")
                InspectorRow(label: "Work plane") { Text(l.plane.label).foregroundStyle(.secondary) }
                InspectorRow(label: "Offset of the work plane") { FamilyBoundField(model: model, label: "", bound: l.offset) { b in update { $0.offset = b } } }
                let (u, v) = Self.axisNames(l.plane)
                InspectorRow(label: "Start") { FamilyPointField(model: model, point: l.start, labels: (u, v)) { p in update { $0.start = p } } }
                InspectorRow(label: "End") { FamilyPointField(model: model, point: l.end, labels: (u, v)) { p in update { $0.end = p } } }
                if !l.isReference {
                    InspectorRow(label: "Subcategory") {
                        Picker("", selection: Binding(get: { l.subcategory }, set: { v in update { $0.subcategory = v } })) {
                            ForEach(FamilySubcategory.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                    }
                }
            }
        }
    }
    func update(_ change: @escaping (inout FamilyModelLine) -> Void) {
        model.edit("Edit Line") { f in if let i = f.modelLines.firstIndex(where: { $0.id == id }) { change(&f.modelLines[i]) } }
    }
    static func axisNames(_ p: FamilySketchPlane) -> (String, String) {
        (p.axes.u.rawValue.lowercased(), p.axes.v.rawValue.lowercased())
    }
}

struct ControlInspector: View {
    let model: FamilyEditorModel
    let id: String
    var body: some View {
        if let c = model.family.controls.first(where: { $0.id == id }) {
            InspectorGroup(title: "Control") {
                InspectorRow(label: "Control Type", help: "Horizontal controls flip the hand of placed instances; vertical ones flip the facing.") {
                    Picker("", selection: Binding(get: { c.kind }, set: { v in update { $0.kind = v } })) {
                        ForEach(FamilyControlKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden()
                }
                InspectorRow(label: "Position (plan)") { FamilyPointField(model: model, point: c.position) { p in update { $0.position = p } } }
                Text(c.kind.isHorizontal ? "Instances show it in plan; clicking it flips the hand (mirrors left and right)." : "Instances show it in plan; clicking it flips the facing (mirrors front and back).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    func update(_ change: @escaping (inout FamilyControl) -> Void) {
        model.edit("Edit Control") { f in if let i = f.controls.firstIndex(where: { $0.id == id }) { change(&f.controls[i]) } }
    }
}

struct ModelTextInspector: View {
    let model: FamilyEditorModel
    let id: String
    var body: some View {
        if let t = model.family.modelTexts.first(where: { $0.id == id }) {
            InspectorGroup(title: "Model Text") {
                InspectorRow(label: "Text") { InspectorField(text: t.text) { v in if !v.isEmpty { update { $0.text = v } } } }
                InspectorRow(label: "Text Size") { InspectorField(text: model.length(t.size)) { v in setLength(v) { $0.size = $1 } } }
                InspectorRow(label: "Depth") { InspectorField(text: model.length(t.depth)) { v in setLength(v) { $0.depth = $1 } } }
                InspectorRow(label: "Text Font") { InspectorField(text: t.fontName) { v in if !v.isEmpty { update { $0.fontName = v } } } }
                InspectorRow(label: "Work plane") { Text(t.plane.label).foregroundStyle(.secondary) }
                InspectorRow(label: "Offset of the work plane") { FamilyBoundField(model: model, label: "", bound: t.offset) { b in update { $0.offset = b } } }
                let (u, v) = ModelLineInspector.axisNames(t.plane)
                InspectorRow(label: "Position") { FamilyPointField(model: model, point: t.position, labels: (u, v)) { p in update { $0.position = p } } }
                InspectorRow(label: "Material") {
                    Picker("", selection: Binding(get: { t.materialParameter ?? "" }, set: { v in update { $0.materialParameter = v.isEmpty ? nil : v } })) {
                        Text("By Category").tag("")
                        ForEach(model.materialParameters) { Text($0.name).tag($0.name) }
                    }.labelsHidden()
                }
                InspectorRow(label: "Visible") {
                    Picker("", selection: Binding(get: { t.visibilityParameter ?? "" }, set: { v in update { $0.visibilityParameter = v.isEmpty ? nil : v } })) {
                        Text("Always").tag("")
                        ForEach(model.boolParameters) { Text($0.name).tag($0.name) }
                    }.labelsHidden()
                }
            }
        }
    }
    func setLength(_ text: String, _ apply: @escaping (inout FamilyModelText, Double) -> Void) {
        guard let v = try? Parameters.parse(text, type: .length, model: model.state.model), let d = v.doubleValue, d > 0 else {
            model.message = "“\(text)” isn't a length greater than zero."
            return
        }
        update { apply(&$0, d) }
    }
    func update(_ change: @escaping (inout FamilyModelText) -> Void) {
        model.edit("Edit Model Text") { f in if let i = f.modelTexts.firstIndex(where: { $0.id == id }) { change(&f.modelTexts[i]) } }
    }
}

struct FillInspector: View {
    let model: FamilyEditorModel
    let id: String
    var body: some View {
        if let fill = model.family.fills.first(where: { $0.id == id }) {
            InspectorGroup(title: fill.isMasking ? "Masking Region" : "Filled Region") {
                Toggle("Masking region", isOn: Binding(get: { fill.isMasking }, set: { v in update { $0.isMasking = v } }))
                    .help("A masking region hides what lies under it; a filled region shows its pattern.")
                if !fill.isMasking {
                    InspectorRow(label: "Pattern") {
                        Picker("", selection: Binding(get: { fill.pattern }, set: { v in update { $0.pattern = v } })) {
                            ForEach(FillPatternKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }.labelsHidden()
                    }
                }
                FamilyPointListEditor(model: model, title: "Boundary (plan)", points: fill.points) { p in update { $0.points = p } }
            }
        }
    }
    func update(_ change: @escaping (inout FamilyFill) -> Void) {
        model.edit("Edit Region") { f in if let i = f.fills.firstIndex(where: { $0.id == id }) { change(&f.fills[i]) } }
    }
}
