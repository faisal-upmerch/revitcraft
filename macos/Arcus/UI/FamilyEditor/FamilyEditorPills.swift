import AppKit
import SwiftUI
import ArcusDomain
import ArcusApplication

// FES: the Family Editor's floating pieces, drawn like the project window's (ShellChrome.swift, ContentArea.swift):
// the controls pill, the dock's top row and family header, the collapsed-sidebar strip, the view tab pills, the
// Options Bar, the bottom pill (view controls and status) and the problems card. They share the project shell's
// glass (`GlassPill`, `GlassPanel`), buttons (`PillIconButton`, `RibbonPressStyle`, `HoverBackground`) and metrics.

// MARK: - Top row

/// The right-hand pill of the top row: undo and redo (the family's own stack) and the Properties toggle.
struct FamilyControlsPill: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        let _ = model.family // undo and redo availability follow every edit
        HStack(spacing: PillSpec.gap) {
            PillIconButton(symbol: "arrow.uturn.backward", help: model.undo.canUndo ? "Undo \(model.undo.undoActionName) (⌘Z)" : "Undo (⌘Z)", enabled: model.undo.canUndo) { model.undo.undo() }
            PillIconButton(symbol: "arrow.uturn.forward", help: model.undo.canRedo ? "Redo \(model.undo.redoActionName) (⇧⌘Z)" : "Redo (⇧⌘Z)", enabled: model.undo.canRedo) { model.undo.redo() }
            PillIconButton(symbol: "sidebar.trailing", help: "Show or hide Properties (⌥⌘2)") { model.chrome.toggleProperties() }
            AIToolbarButton(panel: AIAssistantPanel.of(family: model)) { AIAssistantPanel.toggle(family: model) } // AICORE: the AI assistant (⇧⌘A)
        }
        .padding(.horizontal, PillSpec.inset) // PILLS
        .frame(height: CGFloat(ShellMetrics.arcus.pillHeight))
        .modifier(GlassPill(role: .controls))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Window controls")
    }
}

/// The top row inside the left dock: the traffic lights and the hide-sidebar button.
struct FamilyDockTopRow: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        HStack(spacing: 0) {
            FamilyTrafficLightsHost(chrome: model.chrome).padding(.leading, 12)
            Spacer(minLength: 8)
            PillIconButton(symbol: "sidebar.leading", help: "Hide Sidebar (⌥⌘S)") { model.chrome.toggleBrowser() }
                .foregroundStyle(.secondary)
                .padding(.trailing, 8)
        }
        .frame(height: CGFloat(ShellMetrics.arcus.pillHeight))
    }
}

/// The strip that stands in for the hidden left dock: the traffic lights and a show-sidebar button.
struct FamilyCollapsedStrip: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        HStack(spacing: 0) {
            FamilyTrafficLightsHost(chrome: model.chrome).padding(.leading, 12)
            Spacer(minLength: 6)
            PillIconButton(symbol: "sidebar.leading", help: "Show Sidebar (⌥⌘S)") { model.chrome.toggleBrowser() }
                .foregroundStyle(.secondary)
                .padding(.trailing, 6)
        }
        .frame(width: CGFloat(ShellMetrics.arcus.collapsedStripWidth), height: CGFloat(ShellMetrics.arcus.pillHeight))
        .modifier(GlassPill(role: .collapsedStrip))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Collapsed sidebar")
    }
}

/// The family's name, category, load state and active view at the top of the left dock (the project window shows
/// the project there). The menu offers the family's document commands.
struct FamilyHeader: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.55, green: 0.42, blue: 0.92), Color(red: 0.36, green: 0.26, blue: 0.78)], startPoint: .top, endPoint: .bottom))
                Image(systemName: "cube.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)
            .shadow(color: .black.opacity(0.12), radius: 1.5, y: 1)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(model.family.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(model.familyID == nil ? "Not loaded" : "In project").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.07)))
                        .fixedSize()
                }
                Text("\(model.family.template.rawValue) · \(model.view.viewTitle)")
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 0)
            Menu {
                ForEach([CommandID.feFamilyTypes, .feFamilyCategory, .feSaveFamilyAs], id: \.self) { item($0) }
                Divider()
                ForEach([CommandID.feLoadIntoProject, .feLoadAndClose], id: \.self) { item($0) }
            } label: {
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            .foregroundStyle(.secondary)
            .help("Family")
            .accessibilityLabel("Family options")
        }
        .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Family \(model.family.name), \(model.family.template.rawValue), \(model.view.viewTitle)")
    }

    func item(_ id: CommandID) -> some View {
        let info = CommandCatalog.byID[id]
        return Button(info?.title ?? id.rawValue, systemImage: info?.symbol ?? "questionmark") { model.perform(id) }.disabled(model.disabledReason(id) != nil)
    }
}

// MARK: - View tabs

/// The open views as a row of small glass pills (only when more than one is open), with the overflow menu.
struct FamilyViewTabPills: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        let row = HStack(spacing: 6) {
            ForEach(model.openViews) { v in
                tab(v).id(v)
                    .frame(height: CGFloat(ShellMetrics.arcus.viewTabsHeight))
                    .modifier(GlassPill(role: .viewTab))
            }
        }
        .padding(.vertical, 1)
        HStack(spacing: 6) {
            ViewThatFits(in: .horizontal) {
                row.fixedSize()
                ScrollView(.horizontal, showsIndicators: false) { row.fixedSize() }
            }
            Menu {
                ForEach(model.openViews) { v in
                    Button { model.view = v } label: { if v == model.view { Label(v.viewTitle, systemImage: "checkmark") } else { Text(v.viewTitle) } }
                }
                Divider()
                Menu("Open View") { ForEach(FamilyPreviewMode.allCases) { v in Button(v.viewTitle, systemImage: v.symbol) { model.view = v } } }
                Button("Close Inactive Views") { model.openViews = [model.view] }.disabled(model.openViews.count < 2)
            } label: {
                // PILLS: a 22 pt hover circle 4 pt inside the 30 pt glass circle, as the tabs' capsules.
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    .frame(width: PillSpec.viewTabItemHeight, height: PillSpec.viewTabItemHeight)
                    .pillHighlight(false)
                    .padding(PillSpec.inset)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .modifier(GlassPill(role: .viewTab))
            .help("All open views")
            .accessibilityLabel("Open views, \(model.openViews.count)")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Open views")
    }

    func tab(_ v: FamilyPreviewMode) -> some View {
        let active = v == model.view
        return HStack(spacing: 6) {
            Image(systemName: v.symbol).font(.system(size: 10.5, weight: active ? .semibold : .regular)).foregroundStyle(active ? Tokens.selectionColor : .secondary)
            Text(v.viewTitle).font(.system(size: 11.5, weight: active ? .semibold : .regular)).lineLimit(1).fixedSize()
                .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            ViewTabCloseButton(title: v.viewTitle) { close(v) }
        }
        // PILLS: as the project window's view tabs (PillSpec).
        .padding(.leading, PillSpec.padding).padding(.trailing, PillSpec.closePadding)
        .frame(height: PillSpec.viewTabItemHeight)
        .pillHighlight(active, .tint(Tokens.selectionColor))
        .padding(PillSpec.inset)
        .contentShape(Capsule()) // the whole pill takes the click
        .onTapGesture { model.view = v }
        .contextMenu {
            Button("Close") { close(v) }
            Button("Close Inactive Views") { model.openViews = [model.view] }.disabled(model.openViews.count < 2)
        }
        .help(v.viewTitle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(v.viewTitle)
        .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
        .accessibilityAction { model.view = v }
    }

    func close(_ v: FamilyPreviewMode) {
        guard model.openViews.count > 1 else { return }
        model.openViews.removeAll { $0 == v }
        if model.view == v, let last = model.openViews.last { model.view = last }
    }
}

// MARK: - Options Bar

/// The Options Bar: the running tool's or sketch's options, as a glass pill in the shell's third row (Revit puts an
/// extrusion's Depth, a reference plane's orientation and a control's type here).
struct FamilyOptionsBar: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        if let title = model.optionsTitle {
            let row = HStack(spacing: 12) {
                Label(title, systemImage: model.sketch != nil ? "pencil.and.outline" : "plus.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Tokens.contextualTint)
                    .lineLimit(1).fixedSize()
                FamilyToolOptions(model: model)
            }.fixedSize()
            ViewThatFits(in: .horizontal) {
                row
                ScrollView(.horizontal, showsIndicators: false) { row }
            }
            .instantContent("options", key: title) // PILLS: a new tool's options swap, never cross-fade
            .padding(.horizontal, 14)
            .frame(height: CGFloat(ShellMetrics.arcus.optionsHeight))
            .modifier(GlassPill(role: .options))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Options Bar")
        }
    }
}

extension FamilyEditorModel {
    /// The Options Bar's title, or nil when no tool or sketch runs.
    var optionsTitle: String? {
        if let s = sketch { return "Sketch: " + s.title.replacingOccurrences(of: "Create ", with: "") }
        return tool?.title
    }
}

/// The options of the running tool or sketch.
struct FamilyToolOptions: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        HStack(spacing: 12) {
            if let s = model.sketch {
                divider
                if s.form == .extrusion || s.form == .blend {
                    option("Depth") {
                        ValueField(text: model.length(s.depth)) { t in
                            if let v = try? Parameters.parse(t, type: .length, model: model.state.model), let d = v.doubleValue, d > 0 {
                                model.extrusionDepth = d
                                if var cur = model.sketch { cur.depth = d; model.sketch = cur }
                            } else { model.message = "“\(t)” isn't a depth greater than zero." }
                        }
                        .font(.system(size: 11).monospacedDigit()).frame(width: 86)
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
                        .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
                    }
                }
                option("Draw") {
                    PillSegmented(selection: Binding(get: { model.sketchDraw }, set: { model.sketchDraw = $0; model.tool = .sketch }), [(FamilySketchDraw.line, "Line"), (FamilySketchDraw.rectangle, "Rectangle")], size: .small) // PILLS
                    .disabled(s.drawsPath)
                }
                if s.form.isForm { workPlane }
                Text(s.vertices.isEmpty ? "No points yet" : "\(s.vertices.count) point\(s.vertices.count == 1 ? "" : "s")")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            } else if let t = model.tool {
                switch t {
                case .referencePlane(let vertical):
                    divider
                    option("Orientation") {
                        PillSegmented(selection: Binding(get: { vertical }, set: { model.tool = .referencePlane(vertical: $0) }), [(true, "Vertical"), (false, "Horizontal")], size: .small) // PILLS
                    }
                case .control(let kind):
                    divider
                    option("Type") {
                        Picker("", selection: Binding(get: { kind }, set: { model.tool = .control($0) })) {
                            ForEach([FamilyControlKind.singleVertical, .doubleVertical, .singleHorizontal, .doubleHorizontal], id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden().controlSize(.small).fixedSize()
                    }
                case .modelLine:
                    divider
                    workPlane
                case .modelText(let text):
                    divider
                    option("Text") { Text("“\(text)”").font(.system(size: 11)).lineLimit(1).fixedSize() }
                    workPlane
                case .dimension, .symbolicLine, .annotationLine, .label, .sketch, .axisLine:
                    EmptyView()
                }
            }
        }
    }

    var divider: some View { Divider().frame(height: 16) }

    var workPlane: some View {
        option("Placement Plane") {
            Text(model.workPlane.map { "Reference Plane: \($0)" } ?? "Ref. Level")
                .font(.system(size: 11)).lineLimit(1).fixedSize()
        }
    }

    func option<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).fixedSize()
            content()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

// MARK: - Bottom pill

/// The bottom pill: the view controls (view, detail level, Preview Visibility, zoom) on the left, then the status
/// (message or prompt), the cursor position and the problems button.
struct FamilyBottomPill: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        HStack(spacing: 0) {
            FamilyViewControls(model: model)
            Divider().frame(height: 16).padding(.horizontal, 10)
            FamilyStatusText(model: model).instantContent("status", key: model.statusText) // PILLS: one status line
        }
        .padding(.leading, PillSpec.inset).padding(.trailing, 14) // PILLS: the first capsule 4 pt from the pill's end
        .frame(height: Tokens.bottomBarHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(Capsule())
        .modifier(GlassPill(role: .bottom))
    }
}

/// View, detail level, Preview Visibility and zoom for the active family view.
struct FamilyViewControls: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        let chrome = model.chrome
        HStack(spacing: PillSpec.gap) { // PILLS
            Menu {
                ForEach(FamilyPreviewMode.allCases) { v in
                    Toggle(v.viewTitle, isOn: Binding(get: { v == model.view }, set: { _ in model.view = v })) // VIS: checkmark on the current view
                }
            } label: { Image(systemName: model.view.symbol) }
            .menuStyle(.borderlessButton).fixedSize().barMenuItem().pillHighlight(false)
            .help("View: \(model.view.viewTitle)").accessibilityLabel("View \(model.view.viewTitle)")
            Menu {
                ForEach(DetailLevel.allCases, id: \.self) { d in
                    Toggle(isOn: Binding(get: { d == model.detail }, set: { _ in model.detail = d })) { // VIS: checkmark and icon per level
                        Label { Text(d.rawValue) } icon: { Image(nsImage: ViewStateIcons.detail(d)) }
                    }
                }
            } label: { ViewControlIcon(image: ViewStateIcons.detail(model.detail)) }
            .menuStyle(.borderlessButton).fixedSize().barMenuItem().pillHighlight(false)
            .disabled(!model.applyVisibility)
            .help(model.applyVisibility ? model.detail.controlHelp : "Detail Level (turn on Preview Visibility to use it)")
            .accessibilityLabel("Detail Level")
            .accessibilityValue(model.detail.rawValue)
            Button { model.applyVisibility.toggle() } label: {
                Image(systemName: model.applyVisibility ? "eye" : "eye.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(model.applyVisibility ? AnyShapeStyle(Tokens.selectionColor) : AnyShapeStyle(.secondary))
                    .frame(width: PillSpec.shellItemHeight, height: PillSpec.shellItemHeight) // PILLS: 28 pt, 4 pt inside the bottom pill
            }
            .buttonStyle(RibbonPressStyle())
            .pillHighlight(model.applyVisibility, .tint(Tokens.selectionColor))
            .help(model.applyVisibility ? "Preview Visibility: on. Shows only what a project view would show at this detail level and view direction." : "Preview Visibility: off. Shows every form and line.")
            .accessibilityLabel("Preview Visibility")
            .accessibilityValue(model.applyVisibility ? "On" : "Off")
            Menu {
                Button("Zoom to Fit") { model.zoomToFit() }
                Divider()
                ForEach([50, 100, 200, 400], id: \.self) { p in Button("\(p)%") { model.chrome.zoomRequest = Double(p) / 100 * 400 } }
            } label: { Text(zoomText(chrome.zoomScale)).font(Tokens.monoDigits) }
            .menuStyle(.borderlessButton).fixedSize().barMenuItem().pillHighlight(false)
            .help("Zoom (grid \(model.length(chrome.gridStep)))")
            .accessibilityLabel("Zoom \(zoomText(chrome.zoomScale))")
            Button { model.zoomToFit() } label: {
                Image(systemName: "arrow.up.left.and.down.right.magnifyingglass").font(.system(size: 11)).frame(width: PillSpec.shellItemHeight, height: PillSpec.shellItemHeight) // PILLS: 28 pt, 4 pt inside the bottom pill
            }
            .buttonStyle(RibbonPressStyle())
            .pillHighlight(false)
            .help("Zoom to Fit (F)")
            .accessibilityLabel("Zoom to Fit")
        }
        .fixedSize()
    }

    func zoomText(_ scale: Double) -> String { "\(Int((scale / 400 * 100).rounded()))%" }
}

/// The status part of the bottom pill: the latest message (or the running tool's prompt), the cursor position and the
/// problems button.
struct FamilyStatusText: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        let errors = model.evaluated.errors.count, warnings = model.evaluated.warnings.count
        let flex = model.flexResults
        HStack(spacing: 10) {
            Text(model.statusText)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 30, idealWidth: 120, maxWidth: .infinity, alignment: .leading)
                .help(model.statusText)
                .accessibilityLabel("Status: \(model.statusText)")
            if model.message != nil {
                Button { model.message = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).help("Clear the message").accessibilityLabel("Clear the message")
            }
            if !model.cursorText.isEmpty, model.view != .threeD {
                Text(model.cursorText).font(Tokens.monoDigits).foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .accessibilityLabel("Cursor position \(model.cursorText)")
            }
            Button { model.chrome.problemsShown.toggle() } label: {
                let failed = !(flex ?? []).isEmpty
                HStack(spacing: 3) {
                    Image(systemName: errors > 0 || failed ? "exclamationmark.octagon" : warnings > 0 ? "exclamationmark.triangle" : "checkmark.seal")
                        .foregroundStyle(errors > 0 || failed ? .red : warnings > 0 ? .orange : flex != nil ? .green : .secondary)
                    Text(problemsText(errors: errors, warnings: warnings, flex: flex)).font(.system(size: 11).monospacedDigit()).lineLimit(1).fixedSize()
                }
            }
            .buttonStyle(.plain)
            .disabled(!model.hasProblems)
            .help(model.hasProblems ? "Show or hide the flex test, errors and warnings" : "No errors or warnings")
            .accessibilityLabel("Problems: " + problemsText(errors: errors, warnings: warnings, flex: flex))
        }
    }

    func problemsText(errors: Int, warnings: Int, flex: [String]?) -> String {
        if let flex, !flex.isEmpty { return "Flex: \(flex.count)" }
        if errors + warnings > 0 { return "\(errors + warnings)" }
        return flex != nil ? "Flex passed" : "No warnings"
    }
}

extension FamilyEditorModel {
    /// The bottom pill's status: the latest message, else the sketch's or tool's prompt, else the load state.
    var statusText: String {
        if let m = message { return m }
        if let s = sketch { return s.prompt }
        if let t = tool { return t.prompt }
        return familyID == nil ? "Not loaded into the project yet. Load into Project runs the flex test first." : "Ready."
    }
}

/// The flex test result and the evaluation's errors and warnings, on a glass card over the bottom pill.
struct FamilyProblemsCard: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        let flex = model.flexResults
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(flex.map { $0.isEmpty ? "Flex test passed" : "Flex test: \($0.count) problem\($0.count == 1 ? "" : "s")" } ?? "Errors and warnings")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(flex.map { $0.isEmpty ? Color.green : Color.red } ?? Color.primary)
                Spacer(minLength: 8)
                if model.flexResults != nil {
                    Button("Run Again") { model.flex() }.controlSize(.small)
                }
                Button { model.chrome.problemsShown = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Hide").accessibilityLabel("Hide problems")
            }
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 3) {
                    if let flex, flex.isEmpty {
                        Label("Every type and flexed value evaluates.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    }
                    ForEach(flex ?? [], id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled) }
                    ForEach(model.evaluated.errors, id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled) }
                    ForEach(model.evaluated.warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).textSelection(.enabled) }
                }
                .font(.system(size: 11))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(width: 440, alignment: .leading)
        .modifier(GlassPanel(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Problems")
    }
}

// MARK: - Dock panels

/// A dock panel's title row, as the project window's `PanelHeader`, with the panel's own buttons on the right.
struct FamilyPanelHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(title).font(.system(size: 11, weight: .semibold))
            Spacer()
            trailing
        }
        .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}
