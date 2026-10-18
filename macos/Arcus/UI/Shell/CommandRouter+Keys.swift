import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-KEYS: commands added for keyboard and context-menu parity (snap overrides, Repeat, Zoom All to Fit, View
// Properties, Hide in View / Override Graphics submenus, Find Referring Views), the Modify pre-selection flow, and
// ⌘A and Delete behaviour.
extension CommandRouter {
    /// Runs before availability checks. True when the command was taken over (pre-selection started).
    func keysIntercept(_ id: CommandID) -> Bool {
        if state.keys.pendingCommand != nil {
            // Navigation and selection commands leave a waiting Modify command alone; anything else replaces it.
            let keeps: Set<CommandID> = [.selectAll, .selectAllInstancesInView, .selectAllInstancesInProject, .selectByCategory, .filterSelection, .selectPrevious]
            if !keeps.contains(id) && CommandCatalog.info(id).group != .view && CommandCatalog.info(id).group != .app { state.cancelPreselection() }
            if id == .modify { state.cancelPreselection() }
        }
        return state.beginPreselection(id)
    }

    private static let snapOverrideCommands: Set<CommandID> = [.snapWorkPlaneGrid, .snapPoints, .snapRemote, .snapClose, .snapOverrideOff]

    func keysDisabledReason(_ id: CommandID) -> String? {
        switch id {
        case _ where Self.snapOverrideCommands.contains(id):
            return state.activeTool == nil ? "Snap overrides apply while a drawing tool is active." : nil
        case .findReferringViews:
            return selection.count == 1 ? nil : "Select one element."
        case .hideCategoryInView:
            if selection.isEmpty { return "Select elements first." }
            return state.editingViewID.flatMap({ model[$0]?.view }) == nil ? "Open a view first." : nil
        case .hideByFilter, .overrideByCategory, .overrideByFilter:
            return state.editingViewID.flatMap({ model[$0]?.view }) == nil ? "Open a view first." : nil
        default:
            return nil
        }
    }

    /// Commands this extension performs. True when handled.
    func keysPerform(_ id: CommandID) -> Bool {
        switch id {
        case .selectAll:
            guard let g = state.graphics.graphics(state.activeViewID ?? ElementID(0)) else { return true }
            var ids = Set<ElementID>()
            for i in g.items where i.selectable { if let e = i.elementID { ids.insert(e) } }
            let chosen = SelectAllScope.filter(ids.sorted(), in: model)
            session.selection.select(chosen)
            if !chosen.isEmpty { state.show("\(chosen.count) elements selected.") }
        case .delete:
            state.deleteSelection()
        case .snapWorkPlaneGrid, .snapPoints, .snapRemote, .snapClose, .snapOverrideOff:
            let o: ToolContext.SnapOverride? = switch id {
            case .snapWorkPlaneGrid: .only(.gridIntersection)
            case .snapPoints: .kinds([.endpoint, .center])
            case .snapRemote: .remote
            case .snapClose: .only(.endpoint)
            default: nil
            }
            ctx()?.snapOverride = o
            let text: String = switch id {
            case .snapWorkPlaneGrid: "Next pick snaps to grid intersections only."
            case .snapPoints: "Next pick snaps to points (end and centre points) only."
            case .snapRemote: "Next pick snaps to objects farther from the pointer."
            case .snapClose: "Next pick snaps to endpoints only; pick the chain's start point to close it."
            default: "Snap override off."
            }
            state.show(text)
        case .repeatLastCommand:
            state.repeatLastCommand()
        case .zoomAllToFit:
            for (_, canvas) in state.canvases {
                if let c = canvas as? Canvas2DView { c.recordNavigation(); c.zoomToFit() }
                (canvas as? Viewport3DHost)?.zoomExtents()
            }
        case .viewProperties:
            session.selection.clear()
            if !state.showProperties { state.showProperties = true; state.onWorkspaceChange?() }
            state.inspectorFocusRequest += 1
        case .findReferringViews:
            findReferringViews()
        case .hideCategoryInView:
            guard let v = state.editingViewID else { return true }
            let cats = Set(selection.compactMap { model[$0]?.category })
            session.perform("Hide Category in View") { tx in tx.update(v) { $0.view?.visibility.hiddenCategories.formUnion(cats) } }
            session.selection.clear()
            state.show("Hidden in this view: \(cats.map(\.displayName).sorted().joined(separator: ", ")). Visibility/Graphics shows them again.")
        case .hideByFilter, .overrideByCategory, .overrideByFilter:
            guard let v = state.editingViewID else { return true }
            state.presented = .visibilityGraphics(v)
            if id != .overrideByCategory { state.show("Use the Filters tab to hide or override elements by a filter.") }
        default:
            return false
        }
        return true
    }

    /// Lists the views that show the selected element; the user can open one.
    func findReferringViews() {
        guard selection.count == 1, let id = selection.first, let e = model[id] else { return }
        let snapshot = model
        let name = e.category.singularName + (e.name.isEmpty ? "" : " “\(e.name)”")
        state.runBackground("Finding views that show the \(e.category.singularName.lowercased())") { _, cancelled in
            ReferringViews.find(id, in: snapshot, isCancelled: cancelled)
        } completion: { [state] (r: Result<[ElementID], any Error>) in
            guard case .success(let views) = r else { return }
            Self.presentReferringViews(views, name: name, state: state)
        }
    }

    private static func presentReferringViews(_ views: [ElementID], name: String, state: DocumentState) {
        guard let window = state.window else { return }
        let alert = NSAlert()
        alert.messageText = "Views showing the \(name)"
        guard !views.isEmpty else {
            alert.informativeText = "No view shows this element."
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window)
            return
        }
        alert.informativeText = views.count == 1 ? "1 view shows it." : "\(views.count) views show it."
        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 320, height: 26), pullsDown: false)
        for v in views {
            guard let e = state.model[v] else { continue }
            popup.addItem(withTitle: "\(e.view?.kind.rawValue ?? "View"): \(e.name)")
            popup.lastItem?.representedObject = v.raw
        }
        alert.accessoryView = popup
        alert.addButton(withTitle: "Open View")
        alert.addButton(withTitle: "Close")
        alert.beginSheetModal(for: window) { r in
            guard r == .alertFirstButtonReturn, let raw = popup.selectedItem?.representedObject as? UInt64 else { return }
            state.open(ElementID(raw))
        }
    }
}
