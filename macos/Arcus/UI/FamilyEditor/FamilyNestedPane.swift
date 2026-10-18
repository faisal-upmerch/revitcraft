import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ArcusDomain
import ArcusPersistence

// W4-FAMED: nested families are loaded from the ribbon (Insert ▸ Load Family), listed in the browser (Loaded Families) and
// placed instances are edited in Properties.

/// Loading, placing and removing families embedded in the edited family.
@MainActor
struct FamilyNestedActions {
    let model: FamilyEditorModel

    func embed(_ f: FamilyDefinition) {
        guard f.name != model.family.name else { model.message = "A family can't be nested in itself."; return }
        if Self.contains(f, named: model.family.name) {
            model.message = "“\(f.name)” already contains “\(model.family.name)”, so nesting it here would loop."
            return
        }
        let replacing = model.family.nestedFamily(named: f.name) != nil
        model.edit(replacing ? "Reload Nested Family" : "Load Nested Family") { fam in
            if let i = fam.nestedFamilies.firstIndex(where: { $0.name == f.name }) { fam.nestedFamilies[i] = f } else { fam.nestedFamilies.append(f) }
        }
        model.message = replacing ? "Replaced the embedded “\(f.name)”." : "Loaded “\(f.name)” into this family. Place it from the browser's Loaded Families."
    }

    static func contains(_ f: FamilyDefinition, named n: String) -> Bool {
        f.nestedFamilies.contains { $0.name == n || contains($0, named: n) }
    }

    func loadFromFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.arcusFamily]
        panel.allowsMultipleSelection = true
        panel.message = "Choose Arcus families (.arcusfamily) to nest."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { embed(try FamilyPackage.read(from: url).0) } catch {
                model.message = "Couldn't load \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func remove(_ f: FamilyDefinition) {
        let placed = model.family.nestedInstances.filter { $0.familyName == f.name }.count
        model.edit("Remove Nested Family") { fam in
            fam.nestedFamilies.removeAll { $0.name == f.name }
            fam.nestedInstances.removeAll { $0.familyName == f.name }
        }
        model.message = placed > 0 ? "Removed “\(f.name)” and its \(placed) instance(s)." : "Removed “\(f.name)”."
    }

    func place(_ f: FamilyDefinition) {
        // Associate same-named parameters by default (the usual case: Width → Width).
        var bindings: [String: String] = [:]
        for p in f.parameters where p.formula == nil {
            if let host = model.family.parameter(named: p.name), host.type == p.type { bindings[p.name] = p.name }
        }
        let inst = NestedFamilyInstance(familyName: f.name, typeName: f.types.first?.name, bindings: bindings)
        model.edit("Place Nested Family") { $0.nestedInstances.append(inst) }
        model.selection = .nested(inst.id)
    }
}

/// Placement, type, visibility and associated parameters of one nested instance.
struct NestedInstanceEditor: View {
    let model: FamilyEditorModel
    let instance: NestedFamilyInstance

    var nested: FamilyDefinition? { model.family.nestedFamily(named: instance.familyName) }
    func set(_ name: String = "Edit Nested Family", _ change: @escaping (inout NestedFamilyInstance) -> Void) { model.updateNested(instance.id, name, change) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let nf = nested {
                InspectorRow(label: "Type") {
                    Picker("", selection: Binding(get: { instance.typeName ?? nf.types.first?.name ?? "" }, set: { v in set { $0.typeName = v } })) {
                        ForEach(nf.types) { Text($0.name).tag($0.name) }
                    }
                    .labelsHidden()
                }
            } else {
                Text("“\(instance.familyName)” isn't loaded in this family.").foregroundStyle(.red).font(.caption)
            }
            InspectorRow(label: "Insertion point") {
                HStack {
                    FamilyBoundField(model: model, label: "x", bound: instance.x) { b in set { $0.x = b } }
                    FamilyBoundField(model: model, label: "y", bound: instance.y) { b in set { $0.y = b } }
                    FamilyBoundField(model: model, label: "z", bound: instance.z) { b in set { $0.z = b } }
                }
            }
            InspectorRow(label: "Rotation °") {
                HStack {
                    ValueField(text: instance.rotation) { v in set { $0.rotation = v.isEmpty ? "0" : v } }.font(.caption.monospaced()).frame(width: 90)
                    Toggle("Mirrored", isOn: Binding(get: { instance.mirrored }, set: { v in set { $0.mirrored = v } })).toggleStyle(.checkbox).font(.caption)
                }
            }
            FamilyVisibilityControls(model: model, visibleAt: instance.visibleAt, parameter: instance.visibilityParameter,
                                     setLevels: { l in set { $0.visibleAt = l } }, setParameter: { p in set { $0.visibilityParameter = p } })
            if let nf = nested { associations(nf) }
        }
    }

    func associations(_ nf: FamilyDefinition) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Associated Parameters").font(Tokens.groupHeader).foregroundStyle(.secondary)
            ForEach(nf.parameters.filter { $0.formula == nil }) { p in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(p.name).font(.caption).lineLimit(1)
                        Text(p.isInstance ? "Instance" : "Type").font(.caption2).foregroundStyle(.tertiary)
                    }
                    HStack(spacing: 6) {
                        Text("=").foregroundStyle(.secondary)
                        ValueField(text: instance.bindings[p.name] ?? "", placeholder: "not associated") { v in
                            let t = v.trimmingCharacters(in: .whitespaces)
                            set("Associate Parameter") { $0.bindings[p.name] = t.isEmpty ? nil : t }
                        }
                        .font(.caption.monospaced())
                        Menu {
                            Button("Not Associated") { set("Associate Parameter") { $0.bindings[p.name] = nil } }
                            Divider()
                            ForEach(model.family.parameters.filter { compatible($0.type, p.type) }) { hp in
                                Button(hp.name) { set("Associate Parameter") { $0.bindings[p.name] = hp.name } }
                            }
                        } label: { Image(systemName: "link") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help("Associate with a host parameter")
                    }
                }
            }
            Text("An associated parameter takes its value from the host: a host parameter name or any formula of host parameters. Others use the nested type's value.")
                .font(.caption2).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
    }

    func compatible(_ a: ParamType, _ b: ParamType) -> Bool {
        if a == b { return true }
        switch (a.dimension, b.dimension) {
        case let (x?, y?): return x == y
        default: return false
        }
    }
}
