import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// BL-BROWSER: Project Browser context menus (views, sheets, schedules, families, types, groups, links, folders) and
// the actions behind them. Unavailable items stay in the menu, greyed, with the reason as their tooltip.

/// Target of a closure-backed menu item (kept alive as the item's represented object).
final class BrowserMenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire(_ sender: Any?) { handler() }
}

/// A menu item that runs a closure; disabled items carry the reason as a tooltip.
@MainActor
func browserMenuItem(_ title: String, _ symbol: String? = nil, unavailable reason: String? = nil, _ handler: @escaping () -> Void = {}) -> NSMenuItem {
    let action = BrowserMenuAction(handler)
    let item = NSMenuItem(title: title, action: #selector(BrowserMenuAction.fire(_:)), keyEquivalent: "")
    item.target = action
    item.representedObject = action
    if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
    item.isEnabled = reason == nil
    item.toolTip = reason
    return item
}

/// Builds the context menu for a Project Browser node.
@MainActor
struct ProjectBrowserMenus {
    let state: DocumentState
    let browser: ProjectBrowserController
    var actions: ProjectBrowserActions { ProjectBrowserActions(state: state, browser: browser) }
    var m: BIMModel { state.model }

    func menu(for node: BrowserNode, all: [BrowserNode]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let items: [NSMenuItem]
        switch node.kind {
        case .view, .placedView: items = viewItems(node)
        case .schedule: items = scheduleItems(node)
        case .sheet: items = sheetItems(node)
        case .family: items = familyItems(node)
        case .type: items = typeItems(node)
        case .group: items = groupItems(node)
        case .link: items = linkItems(node, all: all)
        case .folder: items = folderItems(node)
        }
        for i in items { menu.addItem(i) }
        return menu
    }

    private func item(_ title: String, _ symbol: String? = nil, unavailable: String? = nil, _ action: @escaping () -> Void = {}) -> NSMenuItem {
        browserMenuItem(title, symbol, unavailable: unavailable, action)
    }

    private func submenu(_ title: String, _ symbol: String? = nil, unavailable: String? = nil, _ items: [NSMenuItem]) -> NSMenuItem {
        let i = item(title, symbol, unavailable: unavailable)
        let sub = NSMenu(title: title)
        sub.autoenablesItems = false
        for x in items { sub.addItem(x) }
        i.submenu = sub
        return i
    }

    /// Search…, Expand All, Collapse All.
    private var browsingItems: [NSMenuItem] {
        [item("Search…", "magnifyingglass") { actions.search() },
         item("Expand All", "arrow.down.right.and.arrow.up.left") { browser.expandAll() },
         item("Collapse All", "arrow.up.left.and.arrow.down.right") { browser.collapseAll() }]
    }

    private func openCloseItems(_ e: ElementID) -> [NSMenuItem] {
        let sheet = m.sheet(containing: e)
        return [item("Open", "arrow.up.forward.app") { state.open(e) },
                item("Open Sheet", "doc.richtext", unavailable: sheet == nil ? "This view is not placed on a sheet." : nil) { if let s = sheet { state.open(s.id) } },
                item("Close", "xmark.square", unavailable: state.openViews.contains(e) ? nil : "This view is not open.") { state.close(e) }]
    }

    // MARK: Views

    func viewItems(_ node: BrowserNode) -> [NSMenuItem] {
        guard let e = node.elementID, let v = m[e], let vd = v.view else { return [] }
        var out = openCloseItems(e)
        out.append(.separator())
        out.append(referringViewsItem(v, vd))
        out.append(.separator())
        out.append(item("Apply Template Properties…", "doc.text.below.ecg", unavailable: vd.kind == .legend ? "Legends don't use view templates." : nil) {
            state.open(e); state.presented = .visibilityGraphics(e)
        })
        out.append(item("Create View Template From View…", "doc.badge.plus", unavailable: vd.kind == .legend ? "Legends don't use view templates." : nil) {
            actions.createTemplate(from: e)
        })
        out.append(.separator())
        out.append(duplicateMenu(e, vd))
        if vd.parentViewID != nil {
            out.append(item("Convert to Independent View", "square.on.square.dashed") { actions.convertToIndependent(e) })
        } else {
            out.append(item("Convert to Independent View", "square.on.square.dashed", unavailable: "This view is not a dependent view."))
        }
        out.append(.separator())
        out.append(item("Rename…", "character.cursor.ibeam") { browser.beginRename(ProjectBrowserTree.viewNodeID(e)) })
        out.append(item("Select All Instances", "square.stack.3d.up", unavailable: "Views have no instances; use Select All Instances on a family type."))
        out.append(item("Properties", "slider.horizontal.3") { actions.showProperties(e) })
        if node.kind == .placedView, let vp = placedViewportID(node) {
            out.append(item("Remove from Sheet", "rectangle.badge.minus") { state.session.delete([vp]) })
        }
        if v.isCameraView {
            let cam = CameraBrowserActions(state: state)
            let isActive = CameraSessionState.of(state).activeCamera(in: m) == e
            out.append(.separator())
            out.append(item("Show Camera", "camera.viewfinder") { cam.showCamera(e) })
            out.append(item("Set as Active Camera", "camera.fill", unavailable: isActive ? "This is already the active camera." : nil) { cam.setActive(e) })
            out.append(item("Look Through", "camera.aperture") { cam.lookThrough(e) })
            out.append(item("Align to Current View", "camera.viewfinder",
                            unavailable: state.activeView?.view?.kind == .threeD ? nil : "Open a 3D view to align the camera to it.") { cam.alignToCurrentView(e) })
        }
        out.append(.separator())
        out += browsingItems
        out.append(.separator())
        out.append(item("Delete", "trash") { actions.delete([e]) })
        return out
    }

    private func placedViewportID(_ node: BrowserNode) -> ElementID? {
        guard node.id.hasPrefix("p"), let raw = UInt64(node.id.dropFirst()) else { return nil }
        return ElementID(raw)
    }

    private func referringViewsItem(_ v: Element, _ vd: ViewData) -> NSMenuItem {
        let refs = ViewReferences.referringViews(of: v.id, m)
        guard vd.kind == .section || vd.kind == .elevation || vd.kind == .detail || (vd.kind.isPlan && vd.parentViewID != nil && vd.cropRegion != nil) else {
            return item("Find Referring Views", "arrow.triangle.branch", unavailable: "Only sections, elevations and callouts are referenced from other views.")
        }
        guard !refs.isEmpty else { return item("Find Referring Views", "arrow.triangle.branch", unavailable: "No other view shows a marker for this view.") }
        return submenu("Find Referring Views", "arrow.triangle.branch", refs.map { r in
            item(ViewTitles.qualified(r)) { state.open(r.id) }
        })
    }

    private func duplicateMenu(_ e: ElementID, _ vd: ViewData) -> NSMenuItem {
        let dependentReason: String? = vd.parentViewID != nil ? "A dependent view can't have dependents of its own."
            : (vd.kind.isPlan || vd.kind.isVerticalCut) ? nil : "Only plans, sections, elevations and callouts have dependent views."
        let detailingReason: String? = vd.kind == .threeD ? "3D views have no view-specific detailing to copy." : nil
        return submenu("Duplicate View", "doc.on.doc", [
            item("Duplicate", "doc.on.doc") { actions.duplicate(e, .duplicateView) },
            item("Duplicate with Detailing", "doc.on.doc.fill", unavailable: detailingReason) { actions.duplicate(e, .duplicateViewWithDetailing) },
            item("Duplicate as a Dependent", "rectangle.split.2x1", unavailable: dependentReason) { actions.duplicate(e, .duplicateDependent) },
        ])
    }

    // MARK: Schedules and sheets

    func scheduleItems(_ node: BrowserNode) -> [NSMenuItem] {
        guard let e = node.elementID else { return [] }
        var out = openCloseItems(e)
        out.append(.separator())
        out.append(submenu("Duplicate View", "doc.on.doc", [
            item("Duplicate", "doc.on.doc") { actions.duplicate(e, .duplicateView) },
            item("Duplicate with Detailing", unavailable: "Schedules have no detailing to copy."),
            item("Duplicate as a Dependent", unavailable: "Schedules can't have dependent views."),
        ]))
        out.append(.separator())
        out.append(item("Rename…", "character.cursor.ibeam") { browser.beginRename(node.id) })
        out.append(item("Properties", "slider.horizontal.3") { actions.showProperties(e) })
        out.append(.separator())
        out += browsingItems
        out.append(.separator())
        out.append(item("Delete", "trash") { actions.delete([e]) })
        return out
    }

    func sheetItems(_ node: BrowserNode) -> [NSMenuItem] {
        guard let e = node.elementID else { return [] }
        var out: [NSMenuItem] = [
            item("Open", "arrow.up.forward.app") { state.open(e) },
            item("Close", "xmark.square", unavailable: state.openViews.contains(e) ? nil : "This sheet is not open.") { state.close(e) },
            .separator(),
            item("Add View…", "rectangle.badge.plus") { state.open(e); state.presented = .placeView(e) },
            .separator(),
            item("Rename…", "character.cursor.ibeam") { state.presented = .sheetTitle(e) },
            item("Properties", "slider.horizontal.3") { actions.showProperties(e) },
            .separator(),
        ]
        out += browsingItems
        out.append(.separator())
        out.append(item("Delete", "trash") { actions.delete([e]) })
        return out
    }

    // MARK: Families and types

    func familyItems(_ node: BrowserNode) -> [NSMenuItem] {
        let system = node.elementID == nil
        let systemReason = "Built-in (system) families can't be edited, reloaded or deleted; work with their types."
        var out: [NSMenuItem] = [
            item("New Type", "plus.square.on.square") { actions.newType(in: node) },
            item("Reload…", "arrow.clockwise", unavailable: system ? systemReason : nil) { actions.reloadFamily(node) },
            item("Edit", "pencil", unavailable: system ? systemReason : nil) { if let f = node.elementID { FamilyEditorWindowController.open(familyID: f, state: state) } },
            item("Delete from Project", "trash", unavailable: system ? systemReason : nil) { actions.deleteFamily(node) },
            item("Rename…", "character.cursor.ibeam", unavailable: browser.renameUnavailableReason(node)) { browser.beginRename(node.id) },
            .separator(),
        ]
        out += browsingItems
        return out
    }

    func typeItems(_ node: BrowserNode) -> [NSMenuItem] {
        guard let t = node.elementID, let type = m[t], let td = type.typeData else { return [] }
        let count = m.instanceCount(ofType: t)
        let command = ProjectBrowserActions.placementCommand(for: td.instanceCategory)
        let commandReason = command.flatMap { CommandRouter(state: state).disabledReason($0) }
        let matchable = state.session.selection.ids.compactMap { m[$0] }.filter { $0.typeID != nil && $0.typeID != t && sameCategory($0.category, td.instanceCategory) }
        var out: [NSMenuItem] = [
            item("Type Properties…", "slider.horizontal.3") { state.presented = .typeProperties(t) },
            .separator(),
            item("Duplicate", "plus.square.on.square") { actions.duplicateType(t) },
            item("Delete", "trash", unavailable: count > 0 ? "\(count) instance\(count == 1 ? "" : "s") use this type. Change their type or delete them first." : nil) { state.session.delete([t]) },
            item("Copy to Clipboard", "doc.on.clipboard", unavailable: "Copy an instance instead; pasting it into another project brings this type along."),
            item("Rename…", "character.cursor.ibeam") { browser.beginRename(node.id) },
            .separator(),
            submenu("Select All Instances", "square.stack.3d.up", unavailable: count == 0 ? "No instances of this type are placed." : nil, [
                item("Visible in View", unavailable: state.activeViewID == nil ? "Open a view first." : nil) { actions.selectInstances(of: t, inViewOnly: true) },
                item("In Entire Project") { actions.selectInstances(of: t, inViewOnly: false) },
            ]),
            item("Create Instance", "plus.rectangle.on.rectangle",
                 unavailable: command == nil ? "\(td.instanceCategory.displayName) are not placed with a tool." : commandReason) { actions.createInstance(of: t) },
            item("Match", "eyedropper", unavailable: matchable.isEmpty ? "Select \(td.instanceCategory.displayName.lowercased()) of another type first; Match gives them this type." : nil) {
                actions.match(matchable.map(\.id), to: t)
            },
            .separator(),
        ]
        out += browsingItems
        return out
    }

    private func sameCategory(_ a: Category, _ b: Category) -> Bool {
        a == b || Set([a, b]) == Set([.columns, .structuralColumns])
    }

    // MARK: Groups, links, folders

    func groupItems(_ node: BrowserNode) -> [NSMenuItem] {
        guard let e = node.elementID else { return [] }
        var out: [NSMenuItem] = [
            item("Select All Instances", "square.stack.3d.up") { actions.selectGroupInstances(e) },
            item("Rename…", "character.cursor.ibeam") { browser.beginRename(node.id) },
            .separator(),
        ]
        out += browsingItems
        return out
    }

    func linkItems(_ node: BrowserNode, all: [BrowserNode]) -> [NSMenuItem] {
        let ids = all.filter { $0.kind == .link }.compactMap(\.elementID)
        return [item("Reload", "arrow.clockwise") { LinkActions(state: state).reload(ids) },
                item("Remove", "trash") { state.session.delete(ids) },
                .separator()] + browsingItems
    }

    func folderItems(_ node: BrowserNode) -> [NSMenuItem] {
        var out: [NSMenuItem] = []
        switch node.id {
        case "sheets": out.append(item("New Sheet…", "doc.badge.plus") { state.presented = .newSheet })
        case "schedules": out.append(item("New Schedule/Quantities…", "tablecells.badge.ellipsis") { CommandRouter(state: state).run(.schedule) })
        case "legends": out.append(item("New Legend…", "list.bullet.rectangle") { CommandRouter(state: state).run(.legend) })
        case "links": out.append(item("Manage Links…", "link") { state.presented = .manageLinks })
        case "families": out.append(item("Load Family…", "square.and.arrow.down") { CommandRouter(state: state).run(.loadFamily) })
        case "views.3D Views":
            out.append(item("Create Camera from View", "camera.badge.ellipsis", unavailable: state.activeView?.view?.kind == .threeD ? nil : "Open a 3D view first.") {
                CommandRouter(state: state).run(.createCameraFromView)
            })
            out.append(item("Place Camera in Plan", "camera", unavailable: state.activeView?.view?.kind.isPlan == true ? nil : "Open a plan view first.") {
                CommandRouter(state: state).run(.cameraView)
            })
        default: break
        }
        if !out.isEmpty { out.append(.separator()) }
        return out + browsingItems
    }
}

/// What the Project Browser's menus and renaming do to the model and the window.
@MainActor
struct ProjectBrowserActions {
    let state: DocumentState
    let browser: ProjectBrowserController?
    var m: BIMModel { state.model }

    /// The placement command that creates instances of a category (for Create Instance).
    static func placementCommand(for c: Category) -> CommandID? {
        switch c {
        case .walls: .wall
        case .doors: .door
        case .windows: .window
        case .floors: .floor
        case .ceilings: .ceiling
        case .roofs: .roofFootprint
        case .columns: .column
        case .structuralColumns: .structuralColumn
        case .structuralFraming: .beam
        case .stairs: .stairStraight
        case .railings: .railing
        case .ramps: .ramp
        case .grids: .grid
        case .levels: .level
        case .textNotes: .textNote
        case .buildingPads: .buildingPad
        default: Category.componentCategories.contains(c) ? .component : nil
        }
    }

    func search() { NotificationCenter.default.post(name: .projectBrowserSearch, object: state) }

    func showProperties(_ e: ElementID) {
        state.session.selection.select([e])
        if !state.showProperties { state.showProperties = true; state.onWorkspaceChange?() }
        state.inspectorFocusRequest += 1
    }

    func delete(_ ids: [ElementID]) {
        let existing = ids.filter { m[$0] != nil }
        guard !existing.isEmpty else { return }
        for id in existing where state.openViews.contains(id) { state.close(id) }
        state.session.delete(existing)
    }

    func duplicate(_ e: ElementID, _ command: CommandID) {
        state.open(e)
        CommandRouter(state: state).run(command)
    }

    func convertToIndependent(_ e: ElementID) {
        state.session.perform("Convert to Independent View") { tx in tx.update(e) { $0.view?.parentViewID = nil } }
    }

    func createTemplate(from e: ElementID) {
        guard let v = m[e], let vd = v.view else { return }
        let base = "\(v.name) Template"
        var name = base, k = 2
        while m.elements(.viewTemplates).contains(where: { $0.name == name }) { name = "\(base) \(k)"; k += 1 }
        state.requestText(prompt: "Name of the new view template", initial: name) { text in
            guard let text else { return }
            let n = BrowserNaming.normalized(text)
            guard !n.isEmpty else { state.show("Enter a name for the view template.", error: true); return }
            guard !state.model.elements(.viewTemplates).contains(where: { $0.name == n }) else {
                state.show("A view template named “\(n)” already exists.", error: true); return
            }
            state.session.perform("Create View Template") { tx in tx.create(.viewTemplates, name: n, data: .viewTemplate(.capturing(vd))) }
            if state.session.lastError == nil { state.show("View template “\(n)” created from “\(v.name)”. Apply it with Apply Template Properties.") }
        }
    }

    /// Renames a browser item (the name is already validated).
    func rename(_ node: BrowserNode, to name: String) {
        switch node.kind {
        case .family:
            guard let old = node.familyName, let cat = node.category else { return }
            let fid = node.elementID
            state.session.perform("Rename Family") { tx in
                for t in tx.model.types(for: cat) where t.typeData?.familyName == old { tx.update(t.id) { $0.typeData?.familyName = name } }
                if let fid, tx.model[fid]?.family != nil { tx.update(fid) { $0.name = name; $0.family?.name = name } }
            }
        case .group:
            guard let e = node.elementID, let old = m[e]?.group?.groupTypeName, let cat = m[e]?.category else { return }
            state.session.perform("Rename Group") { tx in
                for g in tx.model.elements(cat) where g.group?.groupTypeName == old { tx.update(g.id) { $0.group?.groupTypeName = name; $0.name = name } }
            }
        default:
            guard let e = node.elementID else { return }
            state.session.setParameter(ParameterID("name"), value: .text(name), on: [e], name: "Rename")
        }
        state.updateWindowSubtitle()
    }

    // MARK: Families and types

    func duplicateType(_ t: ElementID) {
        guard let type = m[t], let td = type.typeData else { return }
        let name = BrowserNaming.duplicateTypeName(type.name, family: td.familyName, category: td.instanceCategory, in: m)
        var created: ElementID?
        state.session.perform("Duplicate Type") { tx in created = tx.create(.elementTypes, name: name, data: .type(td)) }
        if let created { renameSoon("t\(created.raw)") }
    }

    func newType(in family: BrowserNode) {
        guard let cat = family.category, let fam = family.familyName,
              let first = m.types(for: cat).first(where: { $0.typeData?.familyName == fam }) else { return }
        duplicateType(first.id)
    }

    /// Starts renaming a node created by the last transaction once the browser has rebuilt.
    private func renameSoon(_ nodeID: String) {
        guard let browser else { return }
        DispatchQueue.main.async { [weak browser] in
            DispatchQueue.main.async { browser?.beginRename(nodeID) }
        }
    }

    func reloadFamily(_ family: BrowserNode) {
        guard let cat = family.category, let fam = family.familyName,
              let type = m.types(for: cat).first(where: { $0.typeData?.familyName == fam }) else { return }
        state.session.selection.select([type.id])
        FamilyLoader(state: state).reloadSelected()
    }

    func deleteFamily(_ family: BrowserNode) {
        guard let cat = family.category, let fam = family.familyName else { return }
        let types = m.types(for: cat).filter { $0.typeData?.familyName == fam }
        let count = types.reduce(0) { $0 + m.instanceCount(ofType: $1.id) }
        guard count == 0 else {
            state.show("\(count) instance\(count == 1 ? "" : "s") of “\(fam)” are placed. Delete them or change their type first.", error: true)
            return
        }
        let ids = types.map(\.id) + [family.elementID].compactMap { $0 }
        state.requestConfirmation(message: "Delete the family “\(fam)” and its \(types.count) type\(types.count == 1 ? "" : "s") from the project?", confirmTitle: "Delete") { ok in
            if ok { state.session.delete(ids) }
        }
    }

    func selectInstances(of t: ElementID, inViewOnly: Bool) {
        var ids = m.instances(ofType: t).map(\.id)
        if inViewOnly, let g = state.graphics.graphics(state.activeViewID ?? ElementID(0)) {
            let visible = Set(g.items.compactMap(\.elementID))
            ids = ids.filter(visible.contains)
        }
        state.session.selection.select(ids)
        state.show(ids.isEmpty ? "No instances are visible in this view." : "\(ids.count) element\(ids.count == 1 ? "" : "s") selected.")
    }

    /// Starts the category's placement tool with this type in the Type Selector.
    func createInstance(of t: ElementID) {
        guard let td = m[t]?.typeData, let command = Self.placementCommand(for: td.instanceCategory) else { return }
        state.currentTypes[td.instanceCategory] = t
        if Category.componentCategories.contains(td.instanceCategory) { state.currentTypes[.furniture] = t }
        for c in state.toolContexts.values { c.currentTypes = state.currentTypes }
        state.session.selection.clear()
        CommandRouter(state: state).run(command)
        state.show("Placing \(td.familyName): \(m[t]?.name ?? "").")
    }

    func match(_ ids: [ElementID], to t: ElementID) {
        guard !ids.isEmpty else { return }
        state.session.setParameter(ParameterID("familyAndType"), value: .ref(t), on: ids, name: "Match Type")
    }

    func selectGroupInstances(_ e: ElementID) {
        guard let g = m[e], let name = g.group?.groupTypeName else { return }
        let ids = m.elements(g.category).filter { $0.group?.groupTypeName == name }.map(\.id)
        state.session.selection.select(ids)
        state.show("\(ids.count) group\(ids.count == 1 ? "" : "s") selected.")
    }
}

extension Notification.Name {
    /// Posted (object: the DocumentState) to move keyboard focus to the Project Browser's search field.
    static let projectBrowserSearch = Notification.Name("ArcusProjectBrowserSearch")
}

extension DocumentState {
    /// Opens the sheet and starts placing the views on it (the viewports follow the cursor; a click places them).
    /// Views already on a sheet are refused with a message; returns false when nothing can be placed.
    @discardableResult
    func beginViewportPlacement(_ ids: [ElementID], onSheet sheet: ElementID) -> Bool {
        guard model[sheet]?.sheet != nil else { return false }
        let refusals = ids.compactMap { SheetPlacement.refusal($0, onSheet: sheet, model) }
        let placeable = ids.filter { SheetPlacement.refusal($0, onSheet: sheet, model) == nil }
        guard !placeable.isEmpty else {
            show(refusals.first ?? "Nothing to place.", error: true)
            return false
        }
        if activeViewID != sheet { open(sheet) }
        let tool = PlaceViewportTool(ctx: toolContext(for: sheet), viewIDs: placeable)
        tool.onPlaced = { [weak self] vps in self?.session.selection.select(vps) }
        setTool(tool)
        show(refusals.first ?? "Move the pointer to position the viewport, then click to place it. Esc cancels.", error: !refusals.isEmpty)
        return true
    }

    /// ⌃Tab / ⌃⇧Tab: activates the next or previous view tab.
    func cycleViewTabs(forward: Bool) {
        guard openViews.count > 1 else { return }
        let i = activeViewID.flatMap { openViews.firstIndex(of: $0) } ?? 0
        activeViewID = openViews[(i + (forward ? 1 : openViews.count - 1)) % openViews.count]
    }
}

extension MainMenuBuilder {
    /// Window ▸ Show Next / Previous View Tab (⌃⇥ / ⌃⇧⇥).
    static func viewTabMenuItems() -> [NSMenuItem] {
        let next = NSMenuItem(title: "Show Next View Tab", action: #selector(DocumentWindowController.showNextViewTab(_:)), keyEquivalent: "\t")
        next.keyEquivalentModifierMask = [.control]
        let previous = NSMenuItem(title: "Show Previous View Tab", action: #selector(DocumentWindowController.showPreviousViewTab(_:)),
                                  keyEquivalent: String(UnicodeScalar(UInt8(NSBackTabCharacter))))
        previous.keyEquivalentModifierMask = [.control, .shift]
        return [.separator(), next, previous]
    }
}

extension DocumentWindowController {
    @objc func showNextViewTab(_ sender: Any?) { state.cycleViewTabs(forward: true) }
    @objc func showPreviousViewTab(_ sender: Any?) { state.cycleViewTabs(forward: false) }
}
