import SwiftUI
import AppKit
import ArcusDomain

// W4-FAMED: Family Editor window structure. Sidebar (views, types, elements) · content (ribbon, canvas, status) · inspector
// (Properties). Each pane scrolls on its own; the split positions persist with the window frame.

@MainActor
final class FamilyEditorSplitController: NSSplitViewController {
    let model: FamilyEditorModel
    private(set) var sidebarItem: NSSplitViewItem!
    private(set) var inspectorItem: NSSplitViewItem!

    init(model: FamilyEditorModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        splitView.autosaveName = "ArcusFamilyEditor.split"
        let sidebar = NSHostingController(rootView: FamilyBrowserView(model: model))
        sidebar.sizingOptions = []
        sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 210
        sidebarItem.maximumThickness = 360
        sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        let content = NSHostingController(rootView: FamilyContentView(model: model))
        content.sizingOptions = []
        let contentItem = NSSplitViewItem(viewController: content)
        contentItem.minimumThickness = 440
        let inspector = NSHostingController(rootView: FamilyInspectorView(model: model))
        inspector.sizingOptions = []
        inspectorItem = NSSplitViewItem(inspectorWithViewController: inspector)
        inspectorItem.minimumThickness = 300
        inspectorItem.maximumThickness = 520
        inspectorItem.canCollapse = true
        addSplitViewItem(sidebarItem)
        addSplitViewItem(contentItem)
        addSplitViewItem(inspectorItem)
        view.frame = NSRect(x: 0, y: 0, width: 1440, height: 860)
    }
}

/// The window toolbar: sidebar and inspector toggles plus the Family Editor's own commands.
@MainActor
final class FamilyEditorToolbar: NSObject, NSToolbarDelegate {
    let model: FamilyEditorModel
    weak var controller: FamilyEditorWindowController?
    init(model: FamilyEditorModel, controller: FamilyEditorWindowController) { self.model = model; self.controller = controller }

    private enum Item {
        static let types = NSToolbarItem.Identifier("familyTypes")
        static let flex = NSToolbarItem.Identifier("flexTest")
        static let save = NSToolbarItem.Identifier("saveAs")
        static let load = NSToolbarItem.Identifier("loadIntoProject")
        static let fit = NSToolbarItem.Identifier("zoomToFit")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, Item.fit, .flexibleSpace, Item.types, Item.flex, Item.save, Item.load, .inspectorTrackingSeparator, .toggleInspector]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        func button(_ label: String, _ symbol: String, _ action: Selector, tip: String) -> NSToolbarItem {
            let i = NSToolbarItem(itemIdentifier: id)
            i.label = label; i.paletteLabel = label; i.toolTip = tip
            i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            i.action = action; i.target = self; i.isBordered = true
            return i
        }
        switch id {
        case Item.types: return button("Family Types", "tablecells", #selector(familyTypes), tip: "Family Types: types, parameter values and formulas")
        case Item.flex: return button("Flex Test", "checkmark.seal", #selector(flex), tip: "Evaluate every type, and each length parameter at 50% and 150%, reporting geometry and constraint failures.")
        case Item.save: return button("Save As", "square.and.arrow.down", #selector(save), tip: "Save the family as a .arcusfamily file")
        case Item.fit: return button("Fit", "arrow.up.left.and.down.right.magnifyingglass", #selector(fit), tip: "Zoom to fit (F, double-click)")
        case Item.load:
            let i = button("Load into Project", "square.and.arrow.up.on.square", #selector(load), tip: "Load this family into the project, or reload it if it is already there.")
            i.visibilityPriority = .high
            return i
        default: return nil
        }
    }

    @objc private func familyTypes() { model.sheet = .familyTypes }
    @objc private func flex() { model.flex() }
    @objc private func save() { model.saveToDisk() }
    @objc private func load() { model.loadIntoProject() }
    @objc private func fit() { model.zoomToFit() }
}

/// The content column: ribbon, the family canvas with its view bar, and the status strip.
struct FamilyContentView: View {
    @Bindable var model: FamilyEditorModel

    var body: some View {
        VStack(spacing: 0) {
            FamilyRibbonView(model: model)
            Divider()
            FamilyViewTabs(model: model) // F1415: the family's open views
            ZStack(alignment: .topLeading) {
                FamilyCanvas(model: model)
                canvasTitle.padding(8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
            FamilyViewBar(model: model)
            Divider()
            FamilyStatusStrip(model: model)
        }
        .frame(minWidth: 440)
        .sheet(item: $model.sheet) { s in
            switch s {
            case .familyTypes: FamilyTypesDialog(model: model)
            case .categoryAndParameters: FamilyCategoryDialog(model: model)
            case .workPlane: FamilyWorkPlaneDialog(model: model) // F1415
            }
        }
        .onKeyPress(.init("z"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) { model.undo.redo() } else { model.undo.undo() }
            return .handled
        }
    }

    var canvasTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(model.view.viewTitle).font(.system(size: 12, weight: .semibold))
            if let s = model.sketch { // F1415: sketch mode
                Label(s.title + " · " + s.prompt, systemImage: "pencil.and.outline").font(.caption).foregroundStyle(Color(nsColor: .systemPink))
            } else if let t = model.tool {
                Label(t.prompt, systemImage: "hand.point.up.left").font(.caption).foregroundStyle(Tokens.selectionColor)
            } else if let s = model.selection {
                Text(model.title(s)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .allowsHitTesting(false)
    }

}

/// View controls under the canvas. Its own view so the cursor readout's updates don't re-render the canvas host.
struct FamilyViewBar: View {
    @Bindable var model: FamilyEditorModel
    var body: some View {
        HStack(spacing: 10) {
            Picker("View", selection: $model.view) { ForEach(FamilyPreviewMode.allCases) { Text($0.rawValue).tag($0) } }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            Picker("Detail", selection: $model.detail) { ForEach(DetailLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                .fixedSize()
                .disabled(!model.applyVisibility)
            Toggle("Preview Visibility", isOn: $model.applyVisibility)
                .toggleStyle(.checkbox)
                .help("Show only what a project view would show at this detail level and view direction. Off shows every form and line.")
            Spacer(minLength: 8)
            Text(model.cursorText).font(Tokens.monoDigits).foregroundStyle(.secondary).lineLimit(1)
            Button { model.zoomToFit() } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                .buttonStyle(.borderless).help("Zoom to Fit (F)")
        }
        .controlSize(.small)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.bar)
    }
}

/// Messages, evaluation errors and warnings, and flex-test results, in a strip that never grows past a few lines.
struct FamilyStatusStrip: View {
    @Bindable var model: FamilyEditorModel

    var body: some View {
        let errors = model.evaluated.errors, warnings = model.evaluated.warnings
        let flex = model.flexResults
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 3) {
                if let m = model.message {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text(m).textSelection(.enabled)
                        Spacer()
                        Button { model.message = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }
                if let flex {
                    Label(flex.isEmpty ? "Flex test passed: every type and flexed value evaluates." : "Flex test: \(flex.count) problem(s)",
                          systemImage: flex.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(flex.isEmpty ? Color.green : Color.red)
                    ForEach(flex, id: \.self) { Text("• \($0)").foregroundStyle(.red).textSelection(.enabled) }
                }
                ForEach(errors, id: \.self) { Label($0, systemImage: "xmark.octagon.fill").foregroundStyle(.red).textSelection(.enabled) }
                ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                if model.message == nil && flex == nil && errors.isEmpty && warnings.isEmpty {
                    Text(model.familyID == nil ? "Not loaded into the project yet. Load into Project runs the flex test first." : "Ready.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 5)
        }
        .frame(height: (flex?.isEmpty == false || !errors.isEmpty) ? 92 : 30)
        .background(.bar)
    }
}
