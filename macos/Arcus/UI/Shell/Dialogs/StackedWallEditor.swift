import SwiftUI
import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// F2: the structure of a stacked wall type in Type Properties (RevitCraft's "Structure (bottom → top)"): one row per
/// basic wall type with its height (or Variable), offset and flip, bottom part last as in a section. Edits are handed
/// to `onChange` (the dialog stages them).
struct StackedWallEditor: View {
    let state: DocumentState
    /// The dialog's preview model (staged duplicates included).
    let model: BIMModel
    let onChange: (StackedWallSpec) -> String?
    @State private var draft: StackedWallSpec
    @State private var selected: Int?
    @State private var heightText: [Int: String] = [:]
    @State private var offsetText: [Int: String] = [:]
    @State private var error: String?

    init(state: DocumentState, model: BIMModel, spec: StackedWallSpec, onChange: @escaping (StackedWallSpec) -> String?) {
        self.state = state; self.model = model; self.onChange = onChange
        _draft = State(initialValue: spec)
    }

    /// Basic wall types (stacked and curtain types don't stack).
    var basicTypes: [Element] { model.types(for: .walls).filter { $0.typeData?.stack == nil && $0.typeData?.curtain == nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("#").frame(width: 22); Text("Name").frame(width: 260, alignment: .leading)
                Text("Height").frame(width: 90, alignment: .leading); Text("Offset").frame(width: 80, alignment: .leading); Text("Flip").frame(width: 32)
            }
            .font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
            Text("TOP").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.tertiary)
            List(selection: $selected) {
                ForEach(Array(draft.parts.indices.reversed()), id: \.self) { i in row(i).tag(i) }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .frame(height: min(240, CGFloat(draft.parts.count) * 26 + 10))
            Text("BOTTOM").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.tertiary)
            HStack {
                Button("Insert") {
                    var s = draft
                    let at = (selected ?? s.parts.count - 1) + 1
                    s.parts.insert(StackedWallPart(typeID: basicTypes.first?.id, height: 1.0), at: at)
                    selected = at
                    update(s)
                }
                Button("Delete") {
                    guard let i = selected, draft.parts.count > 1 else { return }
                    var s = draft
                    s.parts.remove(at: i)
                    selected = nil
                    update(s)
                }
                .disabled(selected == nil || draft.parts.count <= 1)
                Button("Up") { move(1) }.disabled(selected.map { $0 >= draft.parts.count - 1 } ?? true)
                Button("Down") { move(-1) }.disabled(selected.map { $0 <= 0 } ?? true)
                Spacer()
                Text("Fixed \(format(fixedHeight))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            Text("One part is Variable: it takes the wall height the fixed parts leave.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    var fixedHeight: Double { draft.parts.enumerated().filter { $0.offset != draft.variableIndex }.reduce(0) { $0 + max(0, $1.element.height) } }

    func row(_ i: Int) -> some View {
        HStack(spacing: 6) {
            Text("\(i + 1)").frame(width: 22).font(.caption.monospacedDigit())
            Picker("", selection: Binding(get: { draft.parts[i].typeID ?? ElementID(0) }, set: { var s = draft; s.parts[i].typeID = $0; update(s) })) {
                ForEach(basicTypes, id: \.id) { Text($0.name).tag($0.id) }
            }
            .labelsHidden().frame(width: 260)
            .accessibilityLabel("Part \(i + 1) wall type")
            HStack(spacing: 2) {
                TextField("", text: Binding(get: { heightText[i] ?? (draft.parts[i].isVariable ? "Variable" : format(draft.parts[i].height)) }, set: { heightText[i] = $0 }))
                    .textFieldStyle(.roundedBorder).frame(width: 70)
                    .onSubmit { commitHeight(i) }
                    .accessibilityLabel("Part \(i + 1) height")
                Button { var s = draft; for k in s.parts.indices where k != i && s.parts[k].isVariable { s.parts[k].height = 1.0 }; s.parts[i].height = 0; update(s) } label: {
                    Image(systemName: "arrow.up.and.down.square")
                }
                .buttonStyle(.borderless).help("Make this part Variable")
            }
            .frame(width: 90, alignment: .leading)
            TextField("", text: Binding(get: { offsetText[i] ?? format(draft.parts[i].offset) }, set: { offsetText[i] = $0 }))
                .textFieldStyle(.roundedBorder).frame(width: 80)
                .onSubmit { commitOffset(i) }
                .accessibilityLabel("Part \(i + 1) offset")
                .help("Offset of this part's location line from the stacked wall's, toward the exterior.")
            Toggle("", isOn: Binding(get: { draft.parts[i].flipped ?? false }, set: { var s = draft; s.parts[i].flipped = $0 ? true : nil; update(s) }))
                .toggleStyle(.checkbox).labelsHidden().frame(width: 32)
                .accessibilityLabel("Part \(i + 1) flipped")
        }
        .controlSize(.small)
    }

    func format(_ d: Double) -> String { Parameters.format(.double(d), type: .length, model: model) }

    func update(_ s: StackedWallSpec) {
        draft = s
        heightText = [:]; offsetText = [:]
        if let e = s.validate() { error = e.description; return }
        error = onChange(s)
    }

    func commitHeight(_ i: Int) {
        guard let t = heightText[i] else { return }
        var s = draft
        if t.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("var") {
            for k in s.parts.indices where k != i && s.parts[k].isVariable { s.parts[k].height = 1.0 }
            s.parts[i].height = 0
        } else {
            guard let v = try? Parameters.parse(t, type: .length, model: model).doubleValue, v > 0 else { error = "Type a height such as 900 mm, or Variable."; return }
            s.parts[i].height = v
        }
        update(s)
    }

    func commitOffset(_ i: Int) {
        guard let t = offsetText[i] else { return }
        guard let v = try? Parameters.parse(t, type: .length, model: model).doubleValue else { error = "Type an offset such as 50 mm."; return }
        var s = draft
        s.parts[i].offset = v
        update(s)
    }

    /// Moves the selected part up (+1) or down (−1) the stack.
    func move(_ d: Int) {
        guard let i = selected, draft.parts.indices.contains(i + d) else { return }
        var s = draft
        s.parts.swapAt(i, i + d)
        selected = i + d
        update(s)
    }
}
