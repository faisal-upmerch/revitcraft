import SwiftUI
import AppKit
import ArcusGeometry
import ArcusCalc
import ArcusDomain
import ArcusApplication

/// Compound structure editor (exterior/top → interior/bottom). BL-PROPS: the core is bounded by two draggable
/// "Core Boundary" rows instead of a per-layer checkbox (an empty core is allowed), a section preview follows every
/// edit, and changes are handed to `onChange` (the Type Properties dialog stages them) instead of being committed here.
struct AssemblyEditor: View {
    let state: DocumentState
    let isWall: Bool
    /// Toposolid types mark one layer Variable (BL-SITE).
    var isToposolid = false
    /// Receives each valid edit; returns an error message when the edit can't be staged.
    let onChange: (CompoundAssembly) -> String?
    @State private var draft: CompoundAssembly
    @State private var selected: CompoundAssembly.StructureRow?
    @State private var thicknessText: [Int: String] = [:]
    @State private var error: String?

    init(state: DocumentState, assembly: CompoundAssembly, isWall: Bool, isToposolid: Bool = false, onChange: @escaping (CompoundAssembly) -> String?) {
        self.isToposolid = isToposolid
        self.state = state
        self.isWall = isWall
        self.onChange = onChange
        _draft = State(initialValue: assembly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    header
                    Text(isWall ? "EXTERIOR SIDE" : "TOP").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.tertiary)
                    List(selection: $selected) {
                        ForEach(draft.structureRows, id: \.self) { r in
                            rowView(r).tag(r)
                        }
                        .onMove { src, dst in update(draft.moving(rows: src, to: dst)) }
                    }
                    .listStyle(.bordered)
                    .alternatingRowBackgrounds(.disabled)
                    .frame(height: min(320, CGFloat(draft.structureRows.count) * 26 + 10))
                    Text(isWall ? "INTERIOR SIDE" : "BOTTOM").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(.tertiary)
                }
                SectionPreview(state: state, assembly: draft, isWall: isWall)
                    .frame(width: 150, height: 170)
            }
            HStack {
                Button("Insert") {
                    let at = (selectedLayer ?? draft.layers.count - 1) + 1
                    var a = draft
                    a.layers.insert(AssemblyLayer(function: .finish1, materialID: nil, thickness: 0.01), at: at)
                    // A layer inserted after a core layer joins the core; one inserted above the core stays outside it.
                    if at <= a.coreStart { a.coreStart += 1; a.coreEnd += 1 } else if at <= a.coreEnd { a.coreEnd += 1 }
                    update(a)
                }
                Button("Delete") {
                    guard let i = selectedLayer, draft.layers.count > 1 else { return }
                    var a = draft
                    a.layers.remove(at: i)
                    if i < a.coreStart { a.coreStart -= 1 }
                    if i < a.coreEnd { a.coreEnd -= 1 }
                    a.coreEnd = max(a.coreStart, a.coreEnd)
                    selected = nil
                    update(a)
                }
                .disabled(selectedLayer == nil || draft.layers.count <= 1)
                Button("Up") { moveSelected(-1) }.disabled(selected == nil)
                Button("Down") { moveSelected(1) }.disabled(selected == nil)
                Spacer()
                Text("Total \(format(draft.totalThickness))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .controlSize(.small)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if isWall {
                HStack(spacing: 16) {
                    Picker("Wrapping at Inserts", selection: Binding(get: { draft.wrappingAtInserts }, set: { var a = draft; a.wrappingAtInserts = $0; update(a) })) {
                        ForEach(WrappingPreference.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.fixedSize()
                    Picker("Wrapping at Ends", selection: Binding(get: { draft.wrappingAtEnds }, set: { var a = draft; a.wrappingAtEnds = $0; update(a) })) {
                        ForEach(WrappingPreference.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.fixedSize()
                }
                .controlSize(.small)
                .help("Layers marked Wraps turn around door and window jambs and free wall ends, from the chosen face.")
            }
        }
    }

    var header: some View {
        HStack(spacing: 6) {
            Text("#").frame(width: 22); Text("Function").frame(width: 140, alignment: .leading); Text("Material").frame(width: 170, alignment: .leading)
            Text("Thickness").frame(width: 80, alignment: .leading)
            if isWall { Text("Wraps").frame(width: 40) }
            if isToposolid { Text("Variable").frame(width: 52) } // BL-SITE
        }
        .font(.caption).foregroundStyle(.secondary).padding(.leading, 8)
    }

    @ViewBuilder func rowView(_ r: CompoundAssembly.StructureRow) -> some View {
        switch r {
        case .coreTop, .coreBottom:
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary).frame(width: 22)
                Text("Core Boundary").font(.system(size: 11, weight: .semibold))
                Text(r == .coreTop ? "Layers Above Wrap" : "Layers Below Wrap").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 2)
            .background(Tokens.contextualTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            .help("Drag to move the core boundary. The layers between the two boundaries form the core; an empty core is allowed.")
            .accessibilityLabel("Core Boundary, \(r == .coreTop ? "layers above wrap" : "layers below wrap")")
        case .layer(let i):
            if draft.layers.indices.contains(i) { layerRow(i) }
        }
    }

    func layerRow(_ i: Int) -> some View {
        let inCore = i >= draft.coreStart && i < draft.coreEnd
        return HStack(spacing: 6) {
            Text("\(i + 1)").frame(width: 22).font(.caption.monospacedDigit())
            Picker("", selection: Binding(get: { draft.layers[i].function }, set: { var a = draft; a.layers[i].function = $0; update(a) })) {
                ForEach(LayerFunction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.labelsHidden().frame(width: 140)
            MaterialPicker(state: state, selection: Binding(get: { draft.layers[i].materialID }, set: { var a = draft; a.layers[i].materialID = $0; update(a) }))
                .frame(width: 170)
            TextField("", text: Binding(get: { thicknessText[i] ?? format(draft.layers[i].thickness) }, set: { thicknessText[i] = $0 }))
                .textFieldStyle(.roundedBorder).frame(width: 80)
                .onSubmit { commitThickness(i) }
                .accessibilityLabel("Layer \(i + 1) thickness")
            if isWall {
                Toggle("", isOn: Binding(get: { draft.layers[i].wraps }, set: { var a = draft; a.layers[i].wraps = $0; update(a) }))
                    .toggleStyle(.checkbox).labelsHidden().frame(width: 40)
                    .disabled(inCore)
                    .help(inCore ? "Core layers never wrap." : "Wrap this layer around inserts and wall ends (see the wrapping settings below).")
                    .accessibilityLabel("Layer \(i + 1) wraps")
            }
            if isToposolid { // BL-SITE: the variable layer absorbs the terrain's relief down to a flat base
                Toggle("", isOn: Binding(get: { draft.layers[i].isVariable },
                                         set: { on in var a = draft; for k in a.layers.indices { a.layers[k].isVariable = on && k == i }; update(a) }))
                    .toggleStyle(.checkbox).labelsHidden().frame(width: 52)
                    .help("A variable layer reaches down to a flat base below the lowest point; the layers above it follow the terrain.")
                    .accessibilityLabel("Layer \(i + 1) variable")
            }
        }
        .controlSize(.small)
    }

    var selectedLayer: Int? { if case .layer(let i)? = selected { return i }; return nil }

    func format(_ d: Double) -> String { Parameters.format(.double(d), type: .length, model: state.model) }

    func update(_ a: CompoundAssembly) {
        draft = a
        thicknessText = [:]
        if let e = a.validate() { error = e.description; return }
        error = onChange(a)
    }

    func commitThickness(_ i: Int) {
        guard let t = thicknessText[i] else { return }
        guard let v = try? Parameters.parse(t, type: .length, model: state.model).doubleValue, v >= 0 else {
            error = "Type a thickness such as 12 or 12 mm."; return
        }
        var a = draft
        a.layers[i].thickness = v
        update(a)
    }

    func moveSelected(_ d: Int) {
        guard let s = selected, let i = draft.structureRows.firstIndex(of: s) else { return }
        let rows = draft.structureRows
        let j = i + d
        guard rows.indices.contains(j) else { return }
        let moved = draft.moving(rows: IndexSet(integer: i), to: d > 0 ? j + 1 : j)
        update(moved)
        // Keep the moved row selected.
        switch s {
        case .layer: selected = moved.structureRows[j]
        default: selected = s
        }
    }
}

/// BL-PROPS: live section through the structure: layers to scale in their material colours, the core boundaries dashed.
struct SectionPreview: View {
    let state: DocumentState
    let assembly: CompoundAssembly
    let isWall: Bool

    var body: some View {
        Canvas { ctx, size in
            let total = max(assembly.totalThickness, 1e-6)
            let inset: CGFloat = 8
            let span = (isWall ? size.width : size.height) - inset * 2
            var pos = inset
            func band(_ a: CGFloat, _ b: CGFloat) -> CGRect {
                isWall ? CGRect(x: a, y: inset, width: b - a, height: size.height - inset * 2)
                       : CGRect(x: inset, y: a, width: size.width - inset * 2, height: b - a)
            }
            var boundaries: [CGFloat] = [pos]
            for l in assembly.layers {
                let w = CGFloat(l.thickness / total) * span
                let r = band(pos, pos + w)
                let c = state.model[l.materialID]?.material?.color.color ?? Color.gray.opacity(0.35)
                ctx.fill(Path(r), with: .color(c))
                ctx.stroke(Path(r), with: .color(.primary.opacity(0.5)), lineWidth: 0.5)
                pos += w
                boundaries.append(pos)
            }
            for k in [assembly.coreStart, assembly.coreEnd] where boundaries.indices.contains(k) {
                var p = Path()
                let x = boundaries[k]
                if isWall { p.move(to: CGPoint(x: x, y: 2)); p.addLine(to: CGPoint(x: x, y: size.height - 2)) }
                else { p.move(to: CGPoint(x: 2, y: x)); p.addLine(to: CGPoint(x: size.width - 2, y: x)) }
                ctx.stroke(p, with: .color(Tokens.contextualTint), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .overlay(alignment: .bottom) {
            Text("Preview").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.bottom, -14)
        }
        .accessibilityElement()
        .accessibilityLabel("Section preview, \(assembly.layers.count) layers")
    }
}
