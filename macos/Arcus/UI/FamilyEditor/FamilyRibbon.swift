import SwiftUI
import ArcusDomain

// W4-FAMED: the Family Editor ribbon. Create (datum, forms, detail, insert, properties, family editor) and Modify
// (select, modify, view). It scrolls horizontally rather than clipping when the window is narrow.

enum FamilyRibbonTab: String, CaseIterable, Identifiable {
    case create = "Create", modify = "Modify"
    var id: String { rawValue }
}

struct FamilyRibbonView: View {
    @Bindable var model: FamilyEditorModel
    @State private var tab: FamilyRibbonTab = .create

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Picker("", selection: $tab) { ForEach(FamilyRibbonTab.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
                .padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    switch tab {
                    case .create: create
                    case .modify: modify
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 8)
        .background(.bar)
    }

    // MARK: Create

    @ViewBuilder
    var create: some View {
        PanelCard(title: "Datum") {
            HStack(alignment: .top, spacing: 4) {
                FamilyRibbonMenu(title: "Reference\nPlane", symbol: "line.diagonal", active: { if case .referencePlane = model.tool { true } else { false } }()) {
                    Button("Vertical in This View") { toggle(.referencePlane(vertical: true)) }.disabled(model.view == .threeD)
                    Button("Horizontal in This View") { toggle(.referencePlane(vertical: false)) }.disabled(model.view == .threeD)
                    Divider()
                    Button("Add X Plane") { model.addPlane(.x) }
                    Button("Add Y Plane") { model.addPlane(.y) }
                    Button("Add Z Plane") { model.addPlane(.z) }
                }
                FamilyRibbonButton(title: "Dimension", symbol: "ruler", large: true, active: model.tool == .dimension, help: "Dimension between two parallel reference planes; label it with a parameter in Properties.") { toggle(.dimension) }
                    .disabled(model.view == .threeD || model.family.referencePlanes.count < 2)
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "EQ", symbol: "equal", large: false, help: "Keep a middle plane equally spaced between two others.") { model.addDimension(eq: true) }
                        .disabled(model.family.referencePlanes.count < 3)
                    FamilyRibbonButton(title: "Aligned", symbol: "ruler.fill", large: false, help: "A dimension between the outermost planes of an axis.") { model.addDimension(eq: false) }
                        .disabled(model.family.referencePlanes.count < 2)
                }
            }
        }
        PanelCard(title: "Forms") {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "Extrusion", symbol: "cube", large: false, active: model.tool == .extrusion(void: false), help: "Drag a rectangle to sketch an extrusion, or click again to add a default one.") {
                        if model.view == .threeD { model.addForm(.extrusion, void: false) } else { toggle(.extrusion(void: false)) }
                    }
                    FamilyRibbonButton(title: "Blend", symbol: "trapezoid.and.line.vertical", large: false) { model.addForm(.blend, void: false) }
                    FamilyRibbonButton(title: "Revolve", symbol: "rotate.3d", large: false) { model.addForm(.revolve, void: false) }
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "Sweep", symbol: "point.topleft.down.to.point.bottomright.curvepath", large: false) { model.addForm(.sweep, void: false) }
                    FamilyRibbonButton(title: "Void Extrusion", symbol: "cube.transparent", large: false, active: model.tool == .extrusion(void: true), help: "A void that cuts solid extrusions.") {
                        if model.view == .threeD { model.addForm(.extrusion, void: true) } else { toggle(.extrusion(void: true)) }
                    }
                }
            }
        }
        PanelCard(title: "Detail") {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "Symbolic Line", symbol: "line.diagonal.arrow", large: false, active: model.tool == .symbolicLine, help: "Plan symbolic line: replaces the cut outline of forms in plan views.") { toggle(.symbolicLine) }
                        .disabled(model.view != .plan)
                    FamilyRibbonButton(title: "Annotation Line", symbol: "scribble", large: false, active: model.tool == .annotationLine, help: "Line of an annotation, tag, title block or detail family.") { toggle(.annotationLine) }
                        .disabled(model.view != .plan)
                    FamilyRibbonButton(title: "Arc", symbol: "circle.lefthalf.filled", large: false, help: "A plan arc, edited in Properties.") { model.addArc() }
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "Label", symbol: "tag", large: false, active: model.tool == .label, help: "A label that shows a parameter's value (tags and title blocks).") { toggle(.label) }
                        .disabled(model.view != .plan)
                    FamilyRibbonButton(title: "Text", symbol: "textformat", large: false, help: "Static text.") {
                        guard model.view == .plan else { model.message = "Text is placed in the plan view."; return }
                        let l = FamilyEditing.newLabel(at: .zero, parameter: nil)
                        model.edit("Add Text") { $0.labels.append(l) }
                        model.selection = .label(l.id)
                    }
                }
            }
        }
        PanelCard(title: "Insert") {
            FamilyRibbonMenu(title: "Load\nFamily", symbol: "square.and.arrow.down") {
                Button("From File…") { FamilyNestedActions(model: model).loadFromFile() }
                let project = model.state.model.elements(.families).compactMap(\.family).filter { $0.name != model.family.name }
                if !project.isEmpty {
                    Divider()
                    ForEach(project.sorted { $0.name < $1.name }, id: \.name) { f in Button(f.name) { FamilyNestedActions(model: model).embed(f) } }
                }
            }
        }
        PanelCard(title: "Properties") {
            HStack(alignment: .top, spacing: 4) {
                FamilyRibbonButton(title: "Family\nTypes", symbol: "tablecells", large: true, help: "Types, parameter values and formulas.") { model.sheet = .familyTypes }
                FamilyRibbonButton(title: "Category and\nParameters", symbol: "list.bullet.rectangle", large: true) { model.sheet = .categoryAndParameters }
            }
        }
        PanelCard(title: "Family Editor") {
            HStack(alignment: .top, spacing: 4) {
                FamilyRibbonButton(title: "Load into\nProject", symbol: "square.and.arrow.up.on.square", large: true, help: "Load this family into the project, or reload it if it is already there.") { model.loadIntoProject() }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "Flex Test", symbol: "checkmark.seal", large: false) { model.flex() }
                    FamilyRibbonButton(title: "Save As…", symbol: "square.and.arrow.down", large: false) { model.saveToDisk() }
                }
            }
        }
    }

    // MARK: Modify

    @ViewBuilder
    var modify: some View {
        PanelCard(title: "Select") {
            FamilyRibbonButton(title: "Modify", symbol: "cursorarrow", large: true, active: model.tool == nil, help: "Leave the current tool (Esc).") { model.tool = nil }
        }
        PanelCard(title: "Modify") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: "Delete", symbol: "trash", large: false) { model.deleteSelection() }.disabled(model.selection == nil)
                FamilyRibbonButton(title: "Duplicate", symbol: "plus.square.on.square", large: false) { model.duplicateSelection() }.disabled(model.selection == nil)
                FamilyRibbonButton(title: "Deselect", symbol: "xmark.circle", large: false) { model.select(nil) }.disabled(model.selection == nil)
            }
        }
        PanelCard(title: "View") {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    ForEach(FamilyPreviewMode.allCases.prefix(3)) { m in
                        FamilyRibbonButton(title: m.rawValue, symbol: m.symbol, large: false, active: model.view == m) { model.view = m }
                    }
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "3D", symbol: "cube", large: false, active: model.view == .threeD) { model.view = .threeD }
                    FamilyRibbonButton(title: "Zoom to Fit", symbol: "arrow.up.left.and.down.right.magnifyingglass", large: false) { model.zoomToFit() }
                    FamilyRibbonButton(title: model.applyVisibility ? "Show All" : "Preview Visibility", symbol: model.applyVisibility ? "eye" : "eye.slash", large: false) { model.applyVisibility.toggle() }
                }
            }
        }
        PanelCard(title: "Family Types") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: "New Type…", symbol: "plus", large: false) { model.newType(copying: false) }
                FamilyRibbonButton(title: "Rename Type…", symbol: "pencil", large: false) { model.renameType() }
                FamilyRibbonButton(title: "Delete Type", symbol: "minus", large: false) { model.deleteType() }.disabled(model.family.types.count <= 1)
            }
        }
    }

    private func toggle(_ t: FamilyCanvasTool) { model.tool = model.tool == t ? nil : t }
}

/// A ribbon button: large (icon over a two-line caption) or small (icon beside the caption).
struct FamilyRibbonButton: View {
    let title: String
    let symbol: String
    let large: Bool
    var active = false
    var help: String? = nil
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            if large {
                VStack(spacing: 3) {
                    Image(systemName: symbol).font(.system(size: RibbonMetrics.largeIcon)).frame(height: 24)
                    Text(title).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).fixedSize()
                }
                .frame(minWidth: 50)
                .frame(height: RibbonMetrics.contentHeight)
                .padding(.horizontal, 4)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: symbol).font(.system(size: RibbonMetrics.smallIcon)).frame(width: 16)
                    Text(title).font(.system(size: 11)).lineLimit(1).fixedSize()
                }
                .frame(height: RibbonMetrics.rowHeight)
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? (active ? Tokens.selectionColor : .primary) : .secondary)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(active ? Tokens.selectionColor.opacity(0.15) : hovering && enabled ? Color.primary.opacity(0.07) : .clear))
        .onHover { hovering = $0 }
        .help(help ?? title.replacingOccurrences(of: "\n", with: " "))
        .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    }
}

/// A large ribbon button that opens a menu.
struct FamilyRibbonMenu<Items: View>: View {
    let title: String
    let symbol: String
    var active = false
    @ViewBuilder let items: Items
    var body: some View {
        Menu {
            items
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: RibbonMetrics.largeIcon)).frame(height: 24)
                HStack(spacing: 2) {
                    Text(title).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).fixedSize()
                    Image(systemName: "chevron.down").font(.system(size: 7))
                }
            }
            .frame(minWidth: 50)
            .frame(height: RibbonMetrics.contentHeight)
            .padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .foregroundStyle(active ? Tokens.selectionColor : .primary)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(active ? Tokens.selectionColor.opacity(0.15) : .clear))
        .fixedSize()
    }
}
