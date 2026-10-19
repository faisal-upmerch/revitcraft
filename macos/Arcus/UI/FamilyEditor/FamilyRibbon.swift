import SwiftUI
import ArcusDomain
import ArcusApplication

// W4-FAMED: the Family Editor ribbon.
// F1415: RevitCraft's family tabs (`crates/rc-app/src/ribbon.rs` `FAMILY_TABS`: Create, Insert, Annotate, View, Manage and
// Modify) and the contextual "Modify | …" tab of sketch mode and the placing tools (`family_contextual`). Commands take
// their names, symbols and help from `CommandCatalog` (Commands+F1415.swift).
// FES: drawn like the project ribbon (Ribbon.swift): the tabs in the glass tab pill, the panels on the glass ribbon strip
// at the project ribbon's fixed panel height. The tab row and the panel row size to their content vertically, so the
// window can never squeeze them (the tab names used to vanish and the panels to clip under the toolbar).

enum FamilyRibbonTab: String, CaseIterable, Identifiable {
    case create = "Create", insert = "Insert", annotate = "Annotate", view = "View", manage = "Manage", modify = "Modify"
    var id: String { rawValue }
}

extension FamilyEditorModel {
    /// "Modify | Create Extrusion", "Modify | Place Control", "Modify | Forms"… or nil.
    var ribbonContextualTitle: String? {
        if let s = sketch { return "Modify | " + s.title }
        if let t = tool { return "Modify | Place " + t.title }
        if let s = selection { return "Modify | " + FamilyRibbonPanels.category(s, self) }
        return nil
    }
}

extension EnvironmentValues {
    /// The icon tint of the ribbon panel a button is in (as the project ribbon colours its panels).
    @Entry var familyRibbonTint: Color = RibbonContent.build
}

// MARK: - Tabs

/// The ribbon's tabs in the tab pill: the six task tabs, the contextual tab and the minimize control. When the pill is
/// too narrow the contextual title truncates first; only then do the task tabs collapse into one menu.
struct FamilyRibbonTabsBar: View {
    @Bindable var model: FamilyEditorModel
    /// The width the tab pill may take.
    let available: CGFloat

    enum Fit: Equatable { case full, truncatedContextual, compact }

    var body: some View {
        let chrome = model.chrome
        let contextual = model.ribbonContextualTitle
        let contextualShown = chrome.ribbonShowsContextual && contextual != nil
        let fit = Self.fit(contextual: contextual, available: available)
        HStack(spacing: 1) {
            if fit == .compact {
                Menu {
                    ForEach(FamilyRibbonTab.allCases) { t in
                        Button { pick(t) } label: {
                            if chrome.ribbonTab == t { Label(t.rawValue, systemImage: "checkmark") } else { Text(t.rawValue) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(chrome.ribbonTab.rawValue).font(.system(size: 12, weight: contextualShown ? .medium : .semibold)).lineLimit(1).fixedSize()
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(contextualShown ? Color.secondary : Color.primary)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(contextualShown ? 0 : 0.10)))
                    .contentShape(Capsule())
                } primaryAction: { pick(chrome.ribbonTab) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                .accessibilityLabel("Ribbon tab: \(chrome.ribbonTab.rawValue)")
            } else {
                ForEach(FamilyRibbonTab.allCases) { t in
                    FamilyRibbonTabButton(title: t.rawValue, selected: chrome.ribbonTab == t && !contextualShown, chrome: chrome) { pick(t) }
                        doubleTap: { chrome.ribbonCollapsed.toggle() }
                }
            }
            if let contextual {
                FamilyRibbonTabButton(title: contextual, selected: contextualShown, contextual: true, chrome: chrome) {
                    chrome.ribbonShowsContextual = true
                    if chrome.ribbonCollapsed { chrome.ribbonCollapsed = false }
                } doubleTap: { chrome.ribbonCollapsed.toggle() }
                .frame(maxWidth: fit == .full ? nil : max(56, available - Self.tasksWidth(compact: fit == .compact)), alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }
            Button { chrome.ribbonCollapsed.toggle() } label: {
                Image(systemName: chrome.ribbonCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .buttonStyle(RibbonPressStyle())
            .modifier(HoverBackground(radius: 11))
            .foregroundStyle(.secondary)
            .help(chrome.ribbonCollapsed ? "Show the ribbon panels" : "Minimize the ribbon to tabs")
            .accessibilityLabel(chrome.ribbonCollapsed ? "Show ribbon panels" : "Minimize ribbon")
        }
        .padding(.horizontal, 3)
        .arcusAnimation(contextual)
        .fixedSize(horizontal: fit == .full, vertical: true) // the row keeps its height whatever the window offers
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ribbon tabs")
    }

    func pick(_ t: FamilyRibbonTab) {
        model.chrome.ribbonTab = t; model.chrome.ribbonShowsContextual = false
        if model.chrome.ribbonCollapsed { model.chrome.ribbonCollapsed = false }
    }

    /// A tab's width: its title in the selected weight plus its padding and the row spacing.
    static func tabWidth(_ title: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        return ceil((title as NSString).size(withAttributes: [.font: font]).width) + 21
    }
    /// The task tabs (or the compact menu) plus the minimize control and the row's padding.
    static func tasksWidth(compact: Bool) -> CGFloat {
        (compact ? tabWidth(FamilyRibbonTab.create.rawValue) + 30 : FamilyRibbonTab.allCases.reduce(0) { $0 + tabWidth($1.rawValue) }) + 30
    }
    /// How the tabs fit in `available` points.
    static func fit(contextual: String?, available: CGFloat) -> Fit {
        let tasks = tasksWidth(compact: false)
        if tasks + (contextual.map(tabWidth) ?? 0) <= available { return .full }
        if tasks + (contextual == nil ? 0 : 90) <= available { return .truncatedContextual }
        return .compact
    }
}

/// The tab pill: the tabs bar in a glass capsule.
struct FamilyRibbonTabsPill: View {
    @Bindable var model: FamilyEditorModel
    let available: CGFloat
    var body: some View {
        FamilyRibbonTabsBar(model: model, available: max(0, available - 10))
            .padding(.horizontal, 5)
            .frame(height: CGFloat(ShellMetrics.arcus.pillHeight))
            .modifier(GlassPill(role: .tabs))
    }
}

/// A ribbon tab capsule, as the project ribbon's tabs.
struct FamilyRibbonTabButton: View {
    let title: String
    let selected: Bool
    var contextual = false
    var chrome: FamilyEditorChrome? = nil
    let action: () -> Void
    var doubleTap: () -> Void = {}
    @State private var hovering = false
    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .lineLimit(1).truncationMode(.tail)
            .fixedSize(horizontal: !contextual, vertical: true) // FES: a tab name never collapses; a squeezed contextual tab still reads "Modi…"
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FamilyEditorChrome.space)) } action: { chrome?.measuredTabs[title] = $0 }
            .frame(minWidth: contextual ? 56 : 0)
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
            .onTapGesture(count: 2, perform: doubleTap)
            .onTapGesture(perform: action)
            .help(title)
            .accessibilityElement()
            .accessibilityLabel(title + " tab")
            .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
            .accessibilityAction { action() }
    }
}

// MARK: - Strip

/// The ribbon strip: the active tab's panels on the rounded glass bar.
struct FamilyRibbonStrip: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        FamilyRibbonPanels(model: model)
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(ShellMetrics.arcus.ribbonHeight))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FamilyEditorChrome.space)) } action: { [chrome = model.chrome] in chrome.measuredStrip = $0 }
            .modifier(GlassPill(role: .ribbon, cornerRadius: Tokens.dockCornerRadius))
    }
}

/// The panels of the chosen tab (or the contextual tab). The row has the project ribbon's fixed height; in a narrow
/// window its panels shrink and collapse (POLISH).
struct FamilyRibbonPanels: View {
    @Bindable var model: FamilyEditorModel

    var body: some View {
        // POLISH: panels shrink and collapse from the right to fit the strip (RibbonCollapse.swift), instead of scrolling.
        RibbonPanelRow(spacing: 4) {
            rowPanels
            RibbonOverflowButton { rowPanels } // POLISH: when even collapsed panels don't fit
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Tokens.ribbonPanelHeight)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FamilyEditorChrome.space)) } action: { [chrome = model.chrome] in chrome.measuredPanelRow = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ribbon")
    }

    /// The panels of the chosen tab, or of the contextual tab.
    @ViewBuilder var rowPanels: some View {
        if model.chrome.ribbonShowsContextual, model.ribbonContextualTitle != nil { contextual } else { panels(model.chrome.ribbonTab) }
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

    func panel<C: View>(_ title: String, _ tint: Color, contextual: Bool = false, @ViewBuilder _ content: () -> C) -> some View {
        FamilyRibbonPanel(title: title, tint: tint, contextual: contextual, chrome: model.chrome, content: content)
    }

    var selectPanel: some View {
        panel("Select", RibbonContent.modify, contextual: model.chrome.ribbonShowsContextual) {
            FamilyRibbonButton(title: "Modify", symbol: "cursorarrow", large: true, active: model.tool == nil && model.sketch == nil, help: "Leave the current tool (Esc).") {
                if model.sketch != nil { model.cancelSketch() } else { model.tool = nil }
            }
        }
    }

    /// On every tab, as in Revit: Load into Project (and Close), and the editor's own commands that used to be in the
    /// window toolbar.
    var familyEditorPanel: some View {
        panel("Family Editor", RibbonContent.manage) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
                cmd(.feLoadIntoProject, large: true, title: "Load into\nProject")
                cmd(.feLoadAndClose, large: true, title: "Load into\nProject and Close")
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    cmd(.feFamilyTypes)
                    cmd(.feFlexTest)
                    cmd(.feSaveFamilyAs, title: "Save As…")
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "Zoom to Fit", symbol: "arrow.up.left.and.down.right.magnifyingglass", large: false, help: "Zoom to Fit (F, or double-click the canvas).") { model.zoomToFit() }
                }
            }
        }
    }

    @ViewBuilder
    var create: some View {
        selectPanel
        panel("Properties", RibbonContent.modify) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feFamilyTypes)
                cmd(.feFamilyCategory, title: "Category and Parameters")
            }
        }
        panel("Forms", RibbonContent.build) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
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
        panel("Model", RibbonContent.build) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    cmd(.feModelLine); cmd(.feComponent); cmd(.feModelText)
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) { cmd(.feOpening) }
            }
        }
        panel("Control", RibbonContent.build) { cmd(.feControl, large: true) }
        panel("Datum", RibbonContent.datum) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
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
        panel("Work Plane", RibbonContent.datum, contextual: model.sketch != nil || model.tool != nil) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feWorkPlaneSet, title: "Set")
                cmd(.feWorkPlaneShow, title: "Show")
                Text(model.workPlane.map { "Plane: \($0)" } ?? "View's own plane").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(height: RibbonMetrics.rowHeight).padding(.horizontal, 5)
            }
        }
    }

    @ViewBuilder
    var insert: some View {
        selectPanel
        panel("Load from Library", RibbonContent.build) {
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
        panel("Dimension", RibbonContent.annotate) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
                cmd(.feDimension, large: true)
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    FamilyRibbonButton(title: "EQ", symbol: "equal", large: false, help: "Keep a middle plane equally spaced between two others.") { model.addDimension(eq: true) }
                        .disabled(model.family.referencePlanes.count < 3)
                    FamilyRibbonButton(title: "Outer Planes", symbol: "ruler.fill", large: false, help: "A dimension between the outermost planes of an axis.") { model.addDimension(eq: false) }
                        .disabled(model.family.referencePlanes.count < 2)
                }
            }
        }
        panel("Detail", RibbonContent.annotate) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
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
        panel("Text", RibbonContent.annotate) {
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
        panel("Graphics", RibbonContent.view) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: model.applyVisibility ? "Show All" : "Preview Visibility", symbol: model.applyVisibility ? "eye" : "eye.slash", large: false,
                                   help: "Show only what a project view would show at this detail level and view direction, or every form and line.") { model.applyVisibility.toggle() }
                Picker("", selection: $model.detail) { ForEach(DetailLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .labelsHidden().fixedSize().controlSize(.small).disabled(!model.applyVisibility)
                    .padding(.horizontal, 5)
                    .help("Detail level")
            }
        }
        panel("Create", RibbonContent.view) { cmd(.feDefault3D, large: true, title: "Default\n3D View") }
        panel("Windows", RibbonContent.view) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: "Close Inactive", symbol: "xmark.rectangle", large: false, help: "Close every view tab but the active one.") { model.openViews = [model.view] }
                    .disabled(model.openViews.count <= 1)
                FamilyRibbonButton(title: "Zoom to Fit", symbol: "arrow.up.left.and.down.right.magnifyingglass", large: false, help: "Zoom to Fit (F).") { model.zoomToFit() }
            }
        }
        familyEditorPanel
    }

    @ViewBuilder
    var manage: some View {
        selectPanel
        panel("Settings", RibbonContent.manage) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feFamilyCategory, title: "Category and Parameters")
                cmd(.fePurgeUnused, title: "Purge Unused")
            }
        }
        panel("Inquiry", RibbonContent.manage) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                cmd(.feFlexTest)
                cmd(.feSaveFamilyAs, title: "Save As…")
            }
        }
        familyEditorPanel
    }

    @ViewBuilder
    var modify: some View {
        let contextual = model.chrome.ribbonShowsContextual
        selectPanel
        panel("Modify", RibbonContent.modify, contextual: contextual) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: "Delete", symbol: "trash", large: false) { model.deleteSelection() }.disabled(model.selection == nil)
                FamilyRibbonButton(title: "Duplicate", symbol: "plus.square.on.square", large: false) { model.duplicateSelection() }.disabled(model.selection == nil)
                FamilyRibbonButton(title: "Deselect", symbol: "xmark.circle", large: false) { model.select(nil) }.disabled(model.selection == nil)
            }
        }
        panel("View", RibbonContent.view, contextual: contextual) {
            HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    ForEach([FamilyPreviewMode.plan, .front, .back]) { m in FamilyRibbonButton(title: m.tabTitle, symbol: m.symbol, large: false, active: model.view == m) { model.view = m } }
                }
                VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                    ForEach([FamilyPreviewMode.left, .right, .threeD]) { m in FamilyRibbonButton(title: m.tabTitle, symbol: m.symbol, large: false, active: model.view == m) { model.view = m } }
                }
            }
        }
        panel("Family Types", RibbonContent.modify, contextual: contextual) {
            VStack(alignment: .leading, spacing: RibbonMetrics.rowSpacing) {
                FamilyRibbonButton(title: "New Type…", symbol: "plus", large: false) { model.newType(copying: false) }
                FamilyRibbonButton(title: "Rename Type…", symbol: "pencil", large: false) { model.renameType() }
                FamilyRibbonButton(title: "Delete Type", symbol: "minus", large: false) { model.deleteType() }.disabled(model.family.types.count <= 1)
            }
        }
        if !contextual { familyEditorPanel }
    }

    // MARK: Contextual tab

    @ViewBuilder
    var contextual: some View {
        if let s = model.sketch {
            panel("Mode", RibbonContent.modify, contextual: true) {
                HStack(spacing: RibbonMetrics.columnSpacing) {
                    FamilyModeButton(title: "Finish Edit Mode", symbol: "checkmark", color: .green, help: "Finish Edit Mode (Return or ⌘Return)") { model.perform(.feFinishSketch) }
                        .keyboardShortcut(.return, modifiers: [.command])
                    FamilyModeButton(title: "Cancel Edit Mode", symbol: "xmark", color: .red, help: "Cancel Edit Mode (Esc twice)") { model.perform(.feCancelSketch) }
                }
            }
            panel("Draw", RibbonContent.build, contextual: true) {
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
                panel(s.form == .sweep ? "Sweep" : "Swept Blend", RibbonContent.build, contextual: true) {
                    FamilyRibbonButton(title: "Go To\nView", symbol: "arrow.right.square", large: true, help: "Open a view where the profile plane is parallel to the screen.") { model.goToProfileView() }
                }
            }
            if s.form.isForm { workPlanePanel }
        } else if case .control(let k)? = model.tool {
            panel("Control Type", RibbonContent.build, contextual: true) {
                HStack(alignment: .top, spacing: RibbonMetrics.columnSpacing) {
                    ForEach([(CommandID.feControlSingleVertical, FamilyControlKind.singleVertical), (.feControlDoubleVertical, .doubleVertical),
                             (.feControlSingleHorizontal, .singleHorizontal), (.feControlDoubleHorizontal, .doubleHorizontal)], id: \.0) { id, kind in
                        cmd(id, large: true, title: kind.rawValue.replacingOccurrences(of: " ", with: "\n"))
                            .overlay(alignment: .bottom) { if k == kind { Capsule().fill(Tokens.contextualTint).frame(width: 18, height: 2) } }
                    }
                }
            }
        } else if let t = model.tool {
            panel("Select", RibbonContent.modify, contextual: true) {
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

// MARK: - Panel and buttons

/// A ribbon panel: the project ribbon's `PanelCard` with the panel's icon tint for its buttons. Its frame is recorded
/// for the QA check that no panel is clipped.
struct FamilyRibbonPanel<Content: View>: View {
    let title: String
    let tint: Color
    var contextual = false
    var chrome: FamilyEditorChrome?
    @ViewBuilder let content: Content

    init(title: String, tint: Color, contextual: Bool = false, chrome: FamilyEditorChrome? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.tint = tint; self.contextual = contextual; self.chrome = chrome; self.content = content()
    }

    var body: some View {
        // POLISH: as designed, then compact, then icons, then collapsed into its button (RibbonCollapse.swift).
        CollapsibleRibbonPanel(key: title, title: title, symbol: symbol, tint: tint, contextual: contextual) { _ in
            PanelCard(title: title, contextual: contextual) { content }
        }
        .environment(\.familyRibbonTint, tint)
        .fixedSize(horizontal: false, vertical: true) // the row picks the width (each variant keeps its own)
        .modifier(FamilyPanelFrame(title: title, chrome: chrome))
    }

    /// The collapsed button's symbol: the panel's own, by title.
    var symbol: String {
        switch title {
        case "Select": "cursorarrow"
        case "Properties", "Family Types": "slider.horizontal.3"
        case "Forms": "cube"
        case "Model": "line.diagonal"
        case "Control": "arrow.left.and.right"
        case "Datum": "squareshape.split.2x2.dotted"
        case "Work Plane": "square.grid.3x3"
        case "Family Editor": "square.and.arrow.down.on.square"
        case "Dimension": "ruler"
        case "Detail": "scribble"
        case "Text": "textformat"
        case "Graphics", "View": "eye"
        case "Windows": "macwindow"
        case "Settings": "gearshape"
        case "Inquiry": "checkmark.circle"
        case "Modify": "pencil"
        default: "square.grid.2x2"
        }
    }
}

/// Records a Family Editor panel's frame for the QA check (not from the More popover). // POLISH
struct FamilyPanelFrame: ViewModifier {
    let title: String
    let chrome: FamilyEditorChrome?
    @Environment(\.ribbonRecording) private var recording
    func body(content: Content) -> some View {
        content.onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FamilyEditorChrome.space)) } action: { r in
            if recording { chrome?.measuredPanels[title] = r }
        }
    }
}

/// A ribbon button, drawn as the project ribbon's: large (icon over a two-line caption) or small (icon beside the
/// caption), the icon in the panel's tint, hover and "on" backgrounds, press feedback.
struct FamilyRibbonButton: View {
    let title: String
    let symbol: String
    let large: Bool
    var active = false
    var help: String? = nil
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @Environment(\.familyRibbonTint) private var tint

    var body: some View {
        Button(action: action) { FamilyRibbonLabel(title: title, symbol: symbol, large: large, menu: false, enabled: enabled, tint: tint) }
            .buttonStyle(RibbonPressStyle())
            .modifier(HoverBackground(active: active, tint: tint, radius: large ? 8 : 6))
            .help(help ?? title.replacingOccurrences(of: "\n", with: " "))
            .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// The label of a ribbon button or menu, with the project ribbon's metrics.
struct FamilyRibbonLabel: View {
    let title: String
    let symbol: String
    let large: Bool
    let menu: Bool
    let enabled: Bool
    let tint: Color
    @Environment(\.ribbonDensity) private var density // POLISH: shrunk panels draw small buttons, then icons

    var body: some View {
        let fg: AnyShapeStyle = enabled ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary)
        if density >= 2 {
            HStack(spacing: 1) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: RibbonMetrics.smallIcon + 0.5))
                    .foregroundStyle(fg)
                if menu { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(.secondary) }
            }
            .frame(minWidth: 26, minHeight: RibbonMetrics.rowHeight, maxHeight: RibbonMetrics.rowHeight)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        } else if large && density == 0 {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: RibbonMetrics.largeIcon, weight: .regular))
                    .foregroundStyle(fg)
                    .frame(width: 30, height: 26)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(title).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).fixedSize()
                    if menu { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(.secondary) }
                }
                .foregroundStyle(Color.primary)
                .frame(height: 26, alignment: .top)
            }
            .frame(minWidth: 48, maxHeight: RibbonMetrics.contentHeight, alignment: .top)
            .padding(.horizontal, 5).padding(.top, 2)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: RibbonMetrics.smallIcon))
                    .foregroundStyle(fg)
                    .frame(width: 16, height: 16)
                Text(title.replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11)).lineLimit(1).fixedSize()
                    .foregroundStyle(Color.primary)
                if menu { Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold)).foregroundStyle(.secondary) }
            }
            .frame(height: RibbonMetrics.rowHeight)
            .padding(.horizontal, 5)
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Rectangle())
        }
    }
}

/// A large ribbon button that opens a menu (Reference Plane ▾, Load Family ▾).
struct FamilyRibbonMenu<Items: View>: View {
    let title: String
    let symbol: String
    var active = false
    @ViewBuilder let items: Items
    @Environment(\.familyRibbonTint) private var tint
    var body: some View {
        Menu { items } label: { FamilyRibbonLabel(title: title, symbol: symbol, large: true, menu: true, enabled: true, tint: tint) }
            .menuStyle(.button).buttonStyle(RibbonPressStyle()).menuIndicator(.hidden)
            .modifier(HoverBackground(active: active, tint: tint, radius: 8))
            .fixedSize()
            .accessibilityLabel(title.replacingOccurrences(of: "\n", with: " "))
    }
}

/// F1415: a small ribbon row that opens a menu (Void Forms ▾).
struct FamilyRibbonSmallMenu<Items: View>: View {
    let title: String
    let symbol: String
    var active = false
    @ViewBuilder let items: Items
    @Environment(\.familyRibbonTint) private var tint
    var body: some View {
        Menu { items } label: { FamilyRibbonLabel(title: title, symbol: symbol, large: false, menu: true, enabled: true, tint: tint) }
            .menuStyle(.button).buttonStyle(RibbonPressStyle()).menuIndicator(.hidden)
            .modifier(HoverBackground(active: active, tint: tint, radius: 6))
            .fixedSize()
            .accessibilityLabel(title)
    }
}

/// Sketch mode's Finish (green check) and Cancel (red cross), as the project ribbon's Mode panel.
struct FamilyModeButton: View {
    let title: String
    let symbol: String
    let color: Color
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 20, weight: .bold)).foregroundStyle(color).frame(width: 30, height: 26)
                Text(title).font(.system(size: 10)).lineLimit(2).multilineTextAlignment(.center).frame(maxWidth: 64).frame(height: 26, alignment: .top)
            }
            .frame(maxHeight: RibbonMetrics.contentHeight, alignment: .top)
            .padding(.horizontal, 4).padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(RibbonPressStyle())
        .modifier(HoverBackground(radius: 8))
        .help(help)
        .accessibilityLabel(title)
    }
}
