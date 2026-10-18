import SwiftUI
import ArcusDomain
import ArcusApplication

// W4-FAMED: the Family Editor ribbon. It scrolls horizontally rather than clipping when the window is narrow.
// F1415: RevitCraft's family tabs (`crates/rc-app/src/ribbon.rs` `FAMILY_TABS`: Create, Insert, Annotate, View, Manage and
// Modify) with Arcus's tab capsules and panel cards, and the contextual "Modify | …" tab of sketch mode and the placing
// tools (`family_contextual`). Commands take their names, symbols and help from `CommandCatalog` (Commands+F1415.swift).

enum FamilyRibbonTab: String, CaseIterable, Identifiable {
    case create = "Create", insert = "Insert", annotate = "Annotate", view = "View", manage = "Manage", modify = "Modify"
    var id: String { rawValue }
}

struct FamilyRibbonView: View {
    @Bindable var model: FamilyEditorModel
    @State private var tab: FamilyRibbonTab = .create
    /// The contextual tab is showing (it opens when a sketch, tool or selection begins; the previous tab returns after).
    @State private var contextualShown = false

    /// "Modify | Create Extrusion", "Modify | Place Control", "Modify | Forms"… or nil.
    var contextualTitle: String? {
        if let s = model.sketch { return "Modify | " + s.title }
        if let t = model.tool { return "Modify | Place " + t.title }
        if let s = model.selection { return "Modify | " + Self.category(s, model) }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 1) {
                ForEach(FamilyRibbonTab.allCases) { t in
                    FamilyRibbonTabButton(title: t.rawValue, selected: tab == t && !(contextualShown && contextualTitle != nil)) { tab = t; contextualShown = false }
                }
                if let c = contextualTitle {
                    FamilyRibbonTabButton(title: c, selected: contextualShown, contextual: true) { contextualShown = true }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 4) {
                    if contextualShown, contextualTitle != nil { contextual } else { panels(tab) }
                }
                .padding(.vertical, 3)
            }
        }
        .padding(.horizontal, 8).padding(.bottom, 3)
        .background(.bar)
        .onChange(of: contextualTitle) { old, new in
            if new != nil && new != old { contextualShown = true } else if new == nil { contextualShown = false }
        }
    }

    // MARK: Tabs

    @ViewBuilder
    func panels(_ t: FamilyRibbonTab) -> some View {
        switch t {
        case .create: create
        case .insert: insert
        case .annotate: annotate
        case .view: viewTab
        case .manage: manage
        case .modify: modify
        }
    }

    var selectPanel: some View {
        PanelCard(title: "Select") {
            FamilyRibbonButton(title: "Modify", symbol: "cursorarrow", large: true, active: model.tool == nil && model.sketch == nil, help: "Leave the current tool (Esc).") {
                if model.sketch != nil { model.cancelSketch() } else { model.tool = nil }
            }
        }
    }

    var familyEditorPanel: some View {
        PanelCard(title: "Family Editor") {
            HStack(alignment: .top, spacing: 4) {
                cmd(.feLoadIntoProject, large: true, title: "Load into\nProject")
                cmd(.feLoadAndClose, large: true, title: "Load into\nProject and Close")
            }
        }
    }

    @ViewBuilder
    var create: some View {
        selectPanel
        PanelCard(title: "Properties") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feFamilyTypes)
                cmd(.feFamilyCategory, title: "Category and Parameters")
            }
        }
        PanelCard(title: "Forms") {
            HStack(alignment: .top, spacing: 4) {
                cmd(.feExtrusion, large: true)
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    cmd(.feBlend); cmd(.feRevolve); cmd(.feSweep)
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    cmd(.feSweptBlend)
                    FamilyRibbonSmallMenu(title: "Void Forms", symbol: "cube.transparent", active: model.sketch?.isVoid == true) {
                        ForEach([CommandID.feVoidExtrusion, .feVoidBlend, .feVoidRevolve, .feVoidSweep], id: \.self) { id in
                            Button(CommandCatalog.byID[id]?.title ?? id.rawValue) { model.perform(id) }.disabled(model.disabledReason(id) != nil)
                        }
                    }
                }
            }
        }
        PanelCard(title: "Model") {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    cmd(.feModelLine); cmd(.feComponent); cmd(.feModelText)
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) { cmd(.feOpening) }
            }
        }
        PanelCard(title: "Control") { cmd(.feControl, large: true) }
        PanelCard(title: "Datum") {
            HStack(alignment: .top, spacing: 4) {
                FamilyRibbonMenu(title: "Reference\nPlane", symbol: "squareshape.split.2x2.dotted", active: { if case .referencePlane = model.tool { true } else { false } }()) {
                    Button("Vertical in This View") { toggle(.referencePlane(vertical: true)) }.disabled(model.view == .threeD)
                    Button("Horizontal in This View") { toggle(.referencePlane(vertical: false)) }.disabled(model.view == .threeD)
                    Divider()
                    Button("Add X Plane") { model.addPlane(.x) }
                    Button("Add Y Plane") { model.addPlane(.y) }
                    Button("Add Z Plane") { model.addPlane(.z) }
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) { cmd(.feReferenceLine) }
            }
        }
        workPlanePanel
        familyEditorPanel
    }

    var workPlanePanel: some View {
        PanelCard(title: "Work Plane") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feWorkPlaneSet, title: "Set")
                cmd(.feWorkPlaneShow, title: "Show")
                Text(model.workPlane.map { "Plane: \($0)" } ?? "View's own plane").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).frame(height: RibbonMetrics.rowHeight)
            }
        }
    }

    @ViewBuilder
    var insert: some View {
        selectPanel
        PanelCard(title: "Load from Library") {
            FamilyRibbonMenu(title: "Load\nFamily", symbol: "square.and.arrow.down") {
                Button("From File…") { model.perform(.feLoadNestedFamily) }
                let project = model.state.model.elements(.families).compactMap(\.family).filter { $0.name != model.family.name }
                if !project.isEmpty {
                    Divider()
                    ForEach(project.sorted { $0.name < $1.name }, id: \.name) { f in Button(f.name) { FamilyNestedActions(model: model).embed(f) } }
                }
            }
        }
        familyEditorPanel
    }

    @ViewBuilder
    var annotate: some View {
        selectPanel
        PanelCard(title: "Dimension") {
            HStack(alignment: .top, spacing: 4) {
                cmd(.feDimension, large: true)
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "EQ", symbol: "equal", large: false, help: "Keep a middle plane equally spaced between two others.") { model.addDimension(eq: true) }
                        .disabled(model.family.referencePlanes.count < 3)
                    FamilyRibbonButton(title: "Outer Planes", symbol: "ruler.fill", large: false, help: "A dimension between the outermost planes of an axis.") { model.addDimension(eq: false) }
                        .disabled(model.family.referencePlanes.count < 2)
                }
            }
        }
        PanelCard(title: "Detail") {
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    cmd(.feSymbolicLine)
                    FamilyRibbonButton(title: "Annotation Line", symbol: "scribble", large: false, active: model.tool == .annotationLine, help: "Line of an annotation, tag, title block or detail family.") {
                        if model.view != .plan { model.view = .plan }
                        toggle(.annotationLine)
                    }
                    FamilyRibbonButton(title: "Arc", symbol: "circle.lefthalf.filled", large: false, help: "A plan arc, edited in Properties.") { model.addArc() }
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    cmd(.feMaskingRegion); cmd(.feFilledRegion)
                }
            }
        }
        PanelCard(title: "Text") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feText)
                FamilyRibbonButton(title: "Label", symbol: "tag", large: false, active: model.tool == .label, help: "A label that shows a parameter's value (tags and title blocks).") {
                    if model.view != .plan { model.view = .plan }
                    toggle(.label)
                }
            }
        }
        familyEditorPanel
    }

    @ViewBuilder
    var viewTab: some View {
        selectPanel
        PanelCard(title: "Graphics") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: model.applyVisibility ? "Show All" : "Preview Visibility", symbol: model.applyVisibility ? "eye" : "eye.slash", large: false,
                                   help: "Show only what a project view would show at this detail level and view direction, or every form and line.") { model.applyVisibility.toggle() }
                Picker("", selection: $model.detail) { ForEach(DetailLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().fixedSize().controlSize(.small).disabled(!model.applyVisibility)
            }
        }
        PanelCard(title: "Create") { cmd(.feDefault3D, large: true, title: "Default\n3D View") }
        PanelCard(title: "Windows") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: "Close Inactive", symbol: "xmark.rectangle", large: false, help: "Close every view tab but the active one.") { model.openViews = [model.view] }
                    .disabled(model.openViews.count <= 1)
                FamilyRibbonButton(title: "Zoom to Fit", symbol: "arrow.up.left.and.down.right.magnifyingglass", large: false) { model.zoomToFit() }
            }
        }
        familyEditorPanel
    }

    @ViewBuilder
    var manage: some View {
        selectPanel
        PanelCard(title: "Settings") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feFamilyCategory, title: "Category and Parameters")
                cmd(.fePurgeUnused, title: "Purge Unused")
            }
        }
        PanelCard(title: "Inquiry") {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feFlexTest)
                cmd(.feSaveFamilyAs, title: "Save As…")
            }
        }
        familyEditorPanel
    }

    @ViewBuilder
    var modify: some View {
        selectPanel
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
                    ForEach([FamilyPreviewMode.plan, .front, .back]) { m in FamilyRibbonButton(title: m.tabTitle, symbol: m.symbol, large: false, active: model.view == m) { model.view = m } }
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    ForEach([FamilyPreviewMode.left, .right, .threeD]) { m in FamilyRibbonButton(title: m.tabTitle, symbol: m.symbol, large: false, active: model.view == m) { model.view = m } }
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

    // MARK: Contextual tab

    @ViewBuilder
    var contextual: some View {
        if let s = model.sketch {
            PanelCard(title: "Mode", contextual: true) {
                HStack(alignment: .top, spacing: 4) {
                    cmd(.feFinishSketch, large: true, title: "Finish\nEdit Mode")
                    cmd(.feCancelSketch, large: true, title: "Cancel\nEdit Mode")
                }
            }
            PanelCard(title: "Draw", contextual: true) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "Line", symbol: "line.diagonal", large: false, active: model.sketchDraw == .line && model.tool == .sketch) { model.sketchDraw = .line; model.tool = .sketch }
                    FamilyRibbonButton(title: "Rectangle", symbol: "rectangle", large: false, active: model.sketchDraw == .rectangle && model.tool == .sketch) { model.sketchDraw = .rectangle; model.tool = .sketch }
                        .disabled(s.drawsPath)
                    if s.form == .revolve {
                        FamilyRibbonButton(title: "Axis Line", symbol: "arrow.up.and.down", large: false, active: model.tool == .axisLine, help: "Pick the vertical axis the profile revolves about.") { model.tool = .axisLine }
                    } else {
                        FamilyRibbonButton(title: "Undo Point", symbol: "arrow.uturn.backward", large: false) { model.undoSketchVertex() }.disabled(s.vertices.isEmpty)
                    }
                }
            }
            if (s.form == .sweep || s.form == .sweptBlend) && s.stage > 0 {
                PanelCard(title: s.form == .sweep ? "Sweep" : "Swept Blend", contextual: true) {
                    FamilyRibbonButton(title: "Go To\nView", symbol: "arrow.right.square", large: true, help: "Open a view where the profile plane is parallel to the screen.") { model.goToProfileView() }
                }
            }
            if s.form == .extrusion || s.form == .blend {
                PanelCard(title: s.form == .extrusion ? "Extrusion" : "Blend", contextual: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Depth").font(.system(size: 10)).foregroundStyle(.secondary)
                        ValueField(text: model.length(model.extrusionDepth)) { t in
                            if let v = try? Parameters.parse(t, type: .length, model: model.state.model), let d = v.doubleValue, d > 0 { model.extrusionDepth = d }
                            else { model.message = "“\(t)” isn't a depth greater than zero." }
                        }
                        .font(.system(size: 11).monospacedDigit()).frame(width: 90)
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: .textBackgroundColor)))
                    }
                }
            }
            if s.form.isForm { workPlanePanel }
        } else if case .control(let k)? = model.tool {
            PanelCard(title: "Control Type", contextual: true) {
                HStack(alignment: .top, spacing: 4) {
                    ForEach([(CommandID.feControlSingleVertical, FamilyControlKind.singleVertical), (.feControlDoubleVertical, .doubleVertical),
                             (.feControlSingleHorizontal, .singleHorizontal), (.feControlDoubleHorizontal, .doubleHorizontal)], id: \.0) { id, kind in
                        cmd(id, large: true, title: kind.rawValue.replacingOccurrences(of: " ", with: "\n"))
                            .overlay(alignment: .bottom) { if k == kind { Capsule().fill(Tokens.contextualTint).frame(width: 18, height: 2) } }
                    }
                }
            }
        } else if let t = model.tool {
            PanelCard(title: "Select", contextual: true) {
                FamilyRibbonButton(title: "Modify", symbol: "cursorarrow", large: true, help: "Leave \(t.title) (Esc).") { model.tool = nil }
            }
            switch t {
            case .modelLine, .modelText: workPlanePanel
            default: EmptyView()
            }
        } else {
            modify
        }
    }

    // MARK: Helpers

    /// A command button with its catalog title, symbol and help; disabled with the reason as its tooltip.
    func cmd(_ id: CommandID, large: Bool = false, title: String? = nil) -> some View {
        let info = CommandCatalog.byID[id]
        let reason = model.disabledReason(id)
        return FamilyRibbonButton(title: title ?? info?.title ?? id.rawValue, symbol: info?.symbol ?? "questionmark", large: large, active: model.isActive(id),
                                  help: reason ?? info?.help) { model.perform(id) }
            .disabled(reason != nil && id != .feComponent)
    }

    private func toggle(_ t: FamilyCanvasTool) {
        if model.sketch != nil { model.cancelSketch() }
        model.tool = model.tool == t ? nil : t
    }

    /// The selection's category, as RevitCraft titles the contextual tab.
    static func category(_ i: FamilyEditing.Item, _ model: FamilyEditorModel) -> String {
        switch i {
        case .solid(let id): model.family.solids.first { $0.id == id }.map { ($0.isVoid ? "Void " : "") + $0.profile.kindName } ?? "Forms"
        case .plane: "Reference Planes"
        case .dimension: "Dimensions"
        case .control: "Generic Annotations"
        case .modelText: "Model Text"
        case .nested: "Generic Models"
        case .fill: "Detail Items"
        case .line, .label: "Lines"
        case .modelLine(let id): model.family.modelLines.first { $0.id == id }?.isReference == true ? "Reference Lines" : "Lines"
        case .type: "Family Types"
        case .parameter: "Parameters"
        }
    }
}

/// A ribbon tab capsule, styled like the project ribbon's tabs.
struct FamilyRibbonTabButton: View {
    let title: String
    let selected: Bool
    var contextual = false
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .foregroundStyle(contextual ? Tokens.contextualTint : (selected ? Color.primary : Color.secondary))
            .background {
                if selected {
                    Capsule().fill(contextual ? Tokens.contextualTint.opacity(0.18) : Color.primary.opacity(0.10))
                } else if hovering {
                    Capsule().fill(Color.primary.opacity(0.06))
                } else if contextual {
                    Capsule().strokeBorder(Tokens.contextualTint.opacity(0.45), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(title + " tab")
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { action() }
    }
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

/// F1415: a small ribbon row that opens a menu (Void Forms ▾).
struct FamilyRibbonSmallMenu<Items: View>: View {
    let title: String
    let symbol: String
    var active = false
    @ViewBuilder let items: Items
    var body: some View {
        Menu {
            items
        } label: {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: RibbonMetrics.smallIcon)).frame(width: 16)
                Text(title).font(.system(size: 11)).lineLimit(1).fixedSize()
                Image(systemName: "chevron.down").font(.system(size: 7))
            }
            .frame(height: RibbonMetrics.rowHeight)
            .padding(.horizontal, 4)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .foregroundStyle(active ? Tokens.selectionColor : .primary)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(active ? Tokens.selectionColor.opacity(0.15) : .clear))
        .fixedSize()
    }
}
