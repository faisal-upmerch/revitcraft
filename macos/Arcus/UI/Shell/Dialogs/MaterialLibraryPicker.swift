import SwiftUI
import AppKit
import ArcusDomain
import ArcusApplication

/// Manage ▸ Materials ▸ Add from Library: the built-in material library, searchable and grouped by class. Several
/// materials can be checked and added at once; materials whose names the project already has are shown but can't be
/// added again.
struct MaterialLibraryPicker: View {
    let state: DocumentState
    /// Called with the ids of the added materials (empty when cancelled).
    let finish: ([ElementID]) -> Void
    @State private var query = ""
    @State private var region: MaterialRegion?
    @State private var checked: Set<String> = []
    @FocusState private var searchFocused: Bool

    var existing: Set<String> { Set(state.model.materials.map(\.name)) }

    var filtered: [LibraryMaterial] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return MaterialLibrary.all.filter { m in
            (region == nil || m.region == region) && (q.isEmpty || [m.name, m.materialClass.rawValue, m.description, m.region.rawValue].contains { $0.lowercased().contains(q) })
        }
    }

    var body: some View {
        let list = filtered
        let have = existing
        let groups = Dictionary(grouping: list, by: \.materialClass)
        let classes = MaterialClass.allCases.filter { groups[$0] != nil }
        let addable = list.filter { !have.contains($0.name) }
        ArcusDialog(icon: "books.vertical", tint: .pink, title: "Add Materials from Library", subtitle: "\(MaterialLibrary.all.count) common building materials. Check the ones to add.",
                    size: .large, okTitle: checked.count == 1 ? "Add 1 Material" : "Add \(checked.count) Materials", okDisabled: checked.isEmpty,
                    disabledReason: "Check the materials to add", height: 600, onCancel: { finish([]) }, onOK: { add() }) { // DIALOGS
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search name, class or description", text: $query)
                            .textFieldStyle(.plain)
                            .focused($searchFocused)
                            .accessibilityLabel("Search library")
                        if !query.isEmpty {
                            Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.tertiary)
                                .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                    Picker("Region", selection: $region) {
                        Text("All Regions").tag(MaterialRegion?.none)
                        Divider()
                        ForEach(MaterialRegion.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Region")
                }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(classes, id: \.self) { c in
                        Section {
                            ForEach(groups[c]!) { m in row(m, inProject: have.contains(m.name)) }
                        } header: {
                            HStack {
                                Text(c.rawValue).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary)
                                Spacer()
                                let open = groups[c]!.filter { !have.contains($0.name) }.map(\.name)
                                if !open.isEmpty {
                                    Button(open.allSatisfy(checked.contains) ? "Uncheck All" : "Check All") {
                                        if open.allSatisfy(checked.contains) { checked.subtract(open) } else { checked.formUnion(open) }
                                    }
                                    .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 3)
                        }
                    }
                    if list.isEmpty {
                        Text("No library materials match “\(query)”.").font(.callout).foregroundStyle(.secondary).padding(16)
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .background(DialogColors.sectionFill, in: RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .clipShape(RoundedRectangle(cornerRadius: Tokens.radiusSection))
            .overlay(RoundedRectangle(cornerRadius: Tokens.radiusSection).strokeBorder(DialogColors.sectionStroke))
            .frame(maxHeight: .infinity)
        } leading: {
            Text(checked.isEmpty ? "\(addable.count) available" : "\(checked.count) selected")
                .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
        }
        .onAppear { searchFocused = true }
    }

    func row(_ m: LibraryMaterial, inProject: Bool) -> some View {
        let isOn = checked.contains(m.name)
        return HStack(spacing: 10) {
            Image(systemName: inProject ? "checkmark.circle.fill" : (isOn ? "checkmark.square.fill" : "square"))
                .foregroundStyle(inProject ? Color.secondary : (isOn ? Color.accentColor : Color.secondary))
                .font(.system(size: 14))
                .frame(width: 18)
            MaterialSwatch(color: m.color, transparency: m.transparency, size: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(m.name).font(.system(size: 12.5)).lineLimit(1)
                Text(m.description).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if inProject {
                Text("In project").font(.system(size: 10.5)).foregroundStyle(.tertiary)
            } else if m.region != .world {
                Text(m.region.rawValue).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(isOn ? Color.accentColor.opacity(0.12) : .clear))
        .modifier(HoverBackground(radius: 7))
        .contentShape(Rectangle())
        .opacity(inProject ? 0.6 : 1)
        .onTapGesture {
            guard !inProject else { return }
            if isOn { checked.remove(m.name) } else { checked.insert(m.name) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(inProject ? "In project" : (isOn ? "Checked" : "Unchecked"))
    }

    func add() {
        let names = MaterialLibrary.all.map(\.name).filter(checked.contains)
        var added: [ElementID] = []
        state.session.perform(names.count == 1 ? "Add Material from Library" : "Add Materials from Library") { tx in
            added = StandardContent.addMaterials(names, to: tx)
        }
        state.show(added.count == 1 ? "Added 1 material from the library." : "Added \(added.count) materials from the library.")
        finish(added)
    }
}
