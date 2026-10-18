import SwiftUI
import ArcusDomain

// W4-FAMED: the editor's browser (sidebar): family views, types and every element of the family, like the project's
// Project Browser. Selecting a row activates the view or selects the element for the canvas and Properties.

enum FamilyBrowserRow: Hashable {
    case view(FamilyPreviewMode)
    case item(FamilyEditing.Item)
    case loadedFamily(String)
}

struct FamilyBrowserView: View {
    @Bindable var model: FamilyEditorModel

    private var selection: Binding<FamilyBrowserRow?> {
        Binding(get: {
            if let s = model.selection { return .item(s) }
            return .view(model.view)
        }, set: { row in
            switch row {
            case .view(let m)?: model.view = m; model.select(nil)
            case .item(let i)?: model.select(i)
            case .loadedFamily?, nil: model.select(nil)
            }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List(selection: selection) {
                // F1415: as RevitCraft's Project Browser lists a family's views.
                Section("Floor Plans") { viewRow(.plan) }
                Section("Elevations (Elevation 1)") { ForEach([FamilyPreviewMode.back, .front, .left, .right]) { viewRow($0) } }
                Section("3D Views") { viewRow(.threeD) }
                Section("Family Types") {
                    ForEach(model.family.types) { t in
                        Label(t.name, systemImage: t.name == model.currentType ? "checkmark.circle.fill" : "circle").tag(FamilyBrowserRow.item(.type(t.name)))
                            .contextMenu { typeMenu(t.name) }
                    }
                }
                Section("Reference Planes") {
                    ForEach(model.family.referencePlanes) { p in
                        HStack(spacing: 4) {
                            Image(systemName: "line.diagonal").foregroundStyle(.green)
                            Text(p.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(p.axis.rawValue).font(.caption).foregroundStyle(.tertiary)
                            if p.definesOrigin { Image(systemName: "scope").font(.caption).foregroundStyle(.secondary).help("Defines the family origin") }
                        }
                        .tag(FamilyBrowserRow.item(.plane(p.name)))
                        .contextMenu { itemMenu(.plane(p.name)) }
                    }
                }
                Section("Dimensions") {
                    ForEach(model.family.dimensions) { d in
                        HStack(spacing: 4) {
                            Image(systemName: d.isEquality ? "equal" : "ruler").foregroundStyle(.blue)
                            Text(model.title(.dimension(d.id))).lineLimit(1)
                            Spacer(minLength: 4)
                            if let l = d.labelParameter { Text(l).font(.caption).foregroundStyle(.blue).lineLimit(1) }
                            else if d.isLocked { Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary) }
                            if model.evaluated.conflictingDimensions.contains(d.id) { Image(systemName: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red) }
                        }
                        .tag(FamilyBrowserRow.item(.dimension(d.id)))
                        .contextMenu { itemMenu(.dimension(d.id)) }
                    }
                }
                Section("Forms") {
                    ForEach(model.family.solids) { s in
                        HStack(spacing: 4) {
                            Image(systemName: Self.icon(s.profile)).foregroundStyle(s.isVoid ? .orange : .secondary)
                            Text(s.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text((s.isVoid ? "Void " : "") + s.profile.kindName).font(.caption).foregroundStyle(.tertiary).lineLimit(1) // F1415: Swept Blend
                        }
                        .tag(FamilyBrowserRow.item(.solid(s.id)))
                        .contextMenu { itemMenu(.solid(s.id)) }
                    }
                }
                Section("Lines") {
                    ForEach(model.family.planLines) { l in
                        Label(model.title(.line(l.id)), systemImage: "line.diagonal.arrow").tag(FamilyBrowserRow.item(.line(l.id)))
                            .contextMenu { itemMenu(.line(l.id)) }
                    }
                    ForEach(model.family.annotationLines) { l in
                        Label("Annotation: " + model.title(.line(l.id)), systemImage: "scribble").tag(FamilyBrowserRow.item(.line(l.id)))
                            .contextMenu { itemMenu(.line(l.id)) }
                    }
                }
                F1415BrowserSections(model: model) // F1415: model and reference lines, controls, model text, regions
                if !model.family.labels.isEmpty {
                    Section("Labels") {
                        ForEach(model.family.labels) { l in
                            Label(model.title(.label(l.id)), systemImage: "tag").tag(FamilyBrowserRow.item(.label(l.id)))
                                .contextMenu { itemMenu(.label(l.id)) }
                        }
                    }
                }
                Section("Loaded Families") {
                    ForEach(model.family.nestedFamilies, id: \.name) { f in
                        HStack(spacing: 4) {
                            Image(systemName: "shippingbox").foregroundStyle(.secondary)
                            Text(f.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(f.template.rawValue).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                            if f.isShared { Image(systemName: "person.2").font(.caption2).foregroundStyle(.secondary).help("Shared") }
                        }
                        .tag(FamilyBrowserRow.loadedFamily(f.name))
                        .contextMenu {
                            Button("Place Instance") { FamilyNestedActions(model: model).place(f) }.disabled(f.template == .profile)
                            Toggle("Shared", isOn: Binding(get: { f.isShared }, set: { v in
                                model.edit(v ? "Make Shared" : "Make Not Shared") { fam in
                                    if let i = fam.nestedFamilies.firstIndex(where: { $0.name == f.name }) { fam.nestedFamilies[i].isShared = v }
                                }
                            }))
                            Divider()
                            Button("Remove from Family", role: .destructive) { FamilyNestedActions(model: model).remove(f) }
                        }
                    }
                    ForEach(model.family.nestedInstances) { inst in
                        HStack(spacing: 4) {
                            Image(systemName: "square.on.square").foregroundStyle(.secondary)
                            Text(model.title(.nested(inst.id))).lineLimit(1)
                            Spacer(minLength: 4)
                            if !inst.bindings.isEmpty { Text("\(inst.bindings.count) linked").font(.caption2).foregroundStyle(.blue) }
                        }
                        .tag(FamilyBrowserRow.item(.nested(inst.id)))
                        .contextMenu { itemMenu(.nested(inst.id)) }
                    }
                }
                Section("Parameters") {
                    ForEach(model.family.parameters) { p in
                        HStack(spacing: 4) {
                            Image(systemName: p.formula != nil ? "function" : p.isInstance ? "person" : "square.grid.2x2").foregroundStyle(.secondary).frame(width: 14)
                            Text(p.name).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(model.value(p)).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        .tag(FamilyBrowserRow.item(.parameter(p.name)))
                        .contextMenu { itemMenu(.parameter(p.name)) }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 210)
    }

    /// A view row; choosing it opens the view (and its tab).
    func viewRow(_ m: FamilyPreviewMode) -> some View {
        Label(m == .plan ? "Ref. Level" : m == .threeD ? "View 1 {3D}" : m.rawValue, systemImage: m.symbol).tag(FamilyBrowserRow.view(m))
            .fontWeight(model.view == m && model.selection == nil ? .semibold : .regular)
            .help(m.viewTitle)
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.family.name).font(.headline).lineLimit(1)
            HStack(spacing: 6) {
                Text(model.family.template.rawValue).font(.caption).padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(.quaternary))
                Text(model.familyID == nil ? "Not loaded" : "In project").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    func typeMenu(_ name: String) -> some View {
        Button("Make Current") { model.currentType = name }
        Button("New Type…") { model.newType(copying: false) }
        Button("Duplicate…") { model.currentType = name; model.newType(copying: true) }
        Button("Rename…") { model.currentType = name; model.renameType() }
        Divider()
        Button("Delete", role: .destructive) { model.currentType = name; model.deleteType() }.disabled(model.family.types.count <= 1)
    }

    @ViewBuilder
    func itemMenu(_ item: FamilyEditing.Item) -> some View {
        Button("Show in Properties") { model.select(item) }
        if case .solid = item { Button("Duplicate") { model.select(item); model.duplicateSelection() } }
        if case .line = item { Button("Duplicate") { model.select(item); model.duplicateSelection() } }
        Divider()
        Button("Delete", role: .destructive) { model.select(item); model.deleteSelection() }
    }

    static func icon(_ p: FamilySolid.Profile) -> String {
        switch p {
        case .rectangle, .polygon: "cube"
        case .circle: "cylinder"
        case .sweep: "point.topleft.down.to.point.bottomright.curvepath"
        case .blend: "trapezoid.and.line.vertical"
        case .revolve: "rotate.3d"
        }
    }
}

/// F1415: browser sections for the content RevitCraft's family editor adds.
struct F1415BrowserSections: View {
    let model: FamilyEditorModel
    var body: some View {
        if !model.family.modelLines.isEmpty {
            Section("Model and Reference Lines") {
                ForEach(model.family.modelLines) { l in
                    Label(model.title(.modelLine(l.id)), systemImage: l.isReference ? "line.diagonal.arrow" : "line.diagonal")
                        .foregroundStyle(l.isReference ? Color.green : Color.primary)
                        .tag(FamilyBrowserRow.item(.modelLine(l.id)))
                        .contextMenu { menu(.modelLine(l.id)) }
                }
            }
        }
        if !model.family.controls.isEmpty {
            Section("Controls") {
                ForEach(model.family.controls) { c in
                    Label(c.kind.rawValue, systemImage: c.kind.isHorizontal ? "arrow.left.arrow.right" : "arrow.up.arrow.down")
                        .tag(FamilyBrowserRow.item(.control(c.id)))
                        .contextMenu { menu(.control(c.id)) }
                }
            }
        }
        if !model.family.modelTexts.isEmpty {
            Section("Model Text") {
                ForEach(model.family.modelTexts) { t in
                    Label(t.text, systemImage: "textformat.size").lineLimit(1)
                        .tag(FamilyBrowserRow.item(.modelText(t.id)))
                        .contextMenu { menu(.modelText(t.id)) }
                }
            }
        }
        if !model.family.fills.isEmpty {
            Section("Regions") {
                ForEach(model.family.fills) { f in
                    Label(f.isMasking ? "Masking Region" : "Filled Region", systemImage: f.isMasking ? "square.on.square.dashed" : "square.fill.on.square")
                        .tag(FamilyBrowserRow.item(.fill(f.id)))
                        .contextMenu { menu(.fill(f.id)) }
                }
            }
        }
    }

    @ViewBuilder
    func menu(_ item: FamilyEditing.Item) -> some View {
        Button("Show in Properties") { model.select(item) }
        Divider()
        Button("Delete", role: .destructive) { model.select(item); model.deleteSelection() }
    }
}
