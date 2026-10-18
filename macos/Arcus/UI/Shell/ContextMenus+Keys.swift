import AppKit
import ArcusDomain
import ArcusApplication

// BL-KEYS: canvas context menus in the order BIM users know them.
//
// - Drawing (a tool is active): Cancel · Repeat [cmd] · Recent Commands ▸ · (Finish / Cancel Edit Mode) · Snap Overrides ▸ ·
//   zoom items · Previous/Next Pan/Zoom · Browsers ▸ · Properties.
// - Element: Cancel · Repeat · Recent Commands ▸ · Hide in View ▸ · Override Graphics in View ▸ · Create Similar · Edit
//   Family · Select Previous · Select All Instances ▸ · Delete · Find Referring Views · zoom items · Browsers ▸ ·
//   Properties, then Arcus's extras below a separator (Edit Type, flips, Move, Copy, Pin, groups, Selection Box, …).
// - Empty canvas: Cancel · Repeat · Recent Commands ▸ · Select Previous · zoom items · Browsers ▸ · Properties, then
//   Paste, Reset Temporary Hide/Isolate and Visibility/Graphics as extras.
// Cancel is the same two-stage cancel as Esc.
extension ContextMenuBuilder {
    func keysMenu(for hit: ElementID?) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let tool = state.activeTool
        addCommonHead(to: menu)
        if let tool {
            if tool.isSketchMode {
                menu.addItem(.separator())
                menu.addItem(item("Finish Edit Mode", "checkmark", .finishSketch))
                menu.addItem(item("Cancel Edit Mode", "xmark.circle", .cancelSketch))
            }
            menu.addItem(.separator())
            menu.addItem(submenu("Snap Overrides", "scope", snapOverrideItems()))
            addNavigationTail(to: menu)
            return menu
        }
        if let id = hit, let e = state.model[id] {
            addElementItems(to: menu, e)
            addNavigationTail(to: menu)
            addElementExtras(to: menu, e)
        } else {
            menu.addItem(.separator())
            menu.addItem(item("Select Previous", "clock.arrow.circlepath", .selectPrevious))
            addNavigationTail(to: menu)
            menu.addItem(.separator())
            menu.addItem(item("Paste", "doc.on.clipboard", .paste))
            if state.editingViewID.flatMap({ state.session.temporaryVisibility[$0]?.isActive }) == true {
                menu.addItem(item("Reset Temporary Hide/Isolate", "arrow.uturn.backward.circle", .resetTemporary))
            }
            menu.addItem(item("Visibility/Graphics…", "eye", .visibilityGraphics))
        }
        if state.activeViewportEditor != nil { // WP6a
            menu.addItem(.separator())
            menu.addItem(item("Deactivate View", "rectangle.dashed", .deactivateViewport))
        }
        return menu
    }

    // MARK: Sections

    /// Cancel · Repeat [last] · Recent Commands ▸
    private func addCommonHead(to menu: NSMenu) {
        let cancel = action("Cancel", "xmark") { [state] in state.escape() }
        cancel.isEnabled = state.activeTool != nil || !state.session.selection.isEmpty || state.keys.pendingCommand != nil
        menu.addItem(cancel)
        let recent = ToolLifecycle.recentRepeatable(state.recentCommands)
        if let last = recent.first {
            menu.addItem(action("Repeat [\(CommandCatalog.info(last).title)]", "repeat") { [state] in state.repeatLastCommand() })
        } else {
            let r = NSMenuItem(title: "Repeat", action: nil, keyEquivalent: "")
            r.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: nil)
            r.isEnabled = false
            menu.addItem(r)
        }
        let recentItems = recent.map { id in item(CommandCatalog.info(id).title, CommandCatalog.info(id).symbol, id) }
        let sub = submenu("Recent Commands", "clock", recentItems)
        sub.isEnabled = !recentItems.isEmpty
        menu.addItem(sub)
    }

    /// Zoom In Region · Zoom Out (2x) · Zoom To Fit · Previous/Next Pan/Zoom · Browsers ▸ · Properties
    private func addNavigationTail(to menu: NSMenu) {
        menu.addItem(.separator())
        menu.addItem(item("Zoom In Region", "rectangle.and.hand.point.up.left", .zoomRegion))
        menu.addItem(item("Zoom Out (2x)", "minus.magnifyingglass", .zoomOutTwice))
        menu.addItem(item("Zoom To Fit", "arrow.up.left.and.arrow.down.right", .zoomExtents))
        menu.addItem(item("Previous Pan/Zoom", "arrow.uturn.backward.circle", .previousPanZoom))
        menu.addItem(item("Next Pan/Zoom", "arrow.uturn.forward.circle", .nextPanZoom))
        menu.addItem(.separator())
        let browser = item("Project Browser", "sidebar.left", .toggleNavigator)
        browser.state = state.showNavigator ? .on : .off
        menu.addItem(submenu("Browsers", "sidebar.left", [browser]))
        let props = item("Properties", "sidebar.right", .toggleProperties)
        props.state = state.showProperties ? .on : .off
        menu.addItem(props)
    }

    private func addElementItems(to menu: NSMenu, _ e: Element) {
        let router = CommandRouter(state: state)
        menu.addItem(.separator())
        menu.addItem(submenu("Hide in View", "eye.slash.fill", [
            item("Elements", "eye.slash.fill", .hideInView),
            item("Category", "eye.slash.circle.fill", .hideCategoryInView),
            item("By Filter…", "line.3.horizontal.decrease.circle", .hideByFilter),
        ]))
        let byElement: NSMenuItem = router.wp6aDisabledReason(.overrideGraphicsElement) == nil
            ? item("By Element…", "paintbrush", .overrideGraphicsElement)
            : { let i = item("By Element…", "paintbrush", .overrideGraphicsElement); i.isEnabled = false; return i }()
        menu.addItem(submenu("Override Graphics in View", "paintbrush", [
            byElement,
            item("By Category…", "paintbrush.pointed", .overrideByCategory),
            item("By Filter…", "paintbrush.pointed.fill", .overrideByFilter),
        ]))
        menu.addItem(.separator())
        if CreateSimilar.plan(for: e, state.model) != nil { menu.addItem(item("Create Similar", "rectangle.badge.plus", .createSimilar)) }
        if router.disabledReason(.familyEditor) == nil { menu.addItem(item("Edit Family", "square.and.pencil", .familyEditor)) }
        menu.addItem(.separator())
        menu.addItem(item("Select Previous", "clock.arrow.circlepath", .selectPrevious))
        if e.typeID != nil {
            menu.addItem(submenu("Select All Instances", "square.stack.3d.up", [
                item("Visible in View", "square.stack.3d.up", .selectAllInstancesInView),
                item("In Entire Project", "square.stack.3d.up.fill", .selectAllInstancesInProject),
            ]))
        }
        menu.addItem(item("Delete", "trash", .delete))
        menu.addItem(.separator())
        menu.addItem(item("Find Referring Views…", "rectangle.stack.badge.person.crop", .findReferringViews))
    }

    /// Arcus's own element commands, below a separator.
    private func addElementExtras(to menu: NSMenu, _ e: Element) {
        var extras: [NSMenuItem] = []
        if let t = e.typeID {
            let edit = NSMenuItem(title: "Edit Type…", action: #selector(MenuTarget.editType(_:)), keyEquivalent: "")
            edit.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
            edit.representedObject = TypeEdit(state: state, typeID: t)
            edit.target = MenuTarget.shared
            extras.append(edit)
        }
        if ArrayOperations.arrayGroup(of: e.id, state.model) != nil { extras.append(item("Array Number…", "number.square", .arrayNumber)) }
        if CommandRouter(state: state).editableSketch(e) { extras.append(item("Edit Boundary", "square.dashed", .editBoundary)) }
        if e.insert != nil {
            extras.append(item("Flip Facing", "arrow.up.arrow.down", .flipFacing))
            extras.append(item("Flip Hand", "arrow.left.arrow.right", .flipHand))
            extras.append(item("Pick New Host", "hand.point.up.left", .pickHost))
        }
        if e.wall != nil {
            extras.append(item("Flip Wall", "arrow.left.arrow.right.square", .flipWall))
            extras.append(item("Attach Top/Base", "arrow.up.to.line", .attachTop))
        }
        if e.link != nil {
            extras.append(item("Reload Link", "arrow.clockwise.circle", .reloadLink))
            extras.append(item("Explode…", "arrow.triangle.2.circlepath", .convertLinkToDrafting))
        }
        extras.append(item("Move", "arrow.up.and.down.and.arrow.left.and.right", .move))
        extras.append(item("Copy", "plus.square.on.square", .copy))
        extras.append(item(e.pinned ? "Unpin" : "Pin", e.pinned ? "pin.slash" : "pin", e.pinned ? .unpin : .pin))
        extras.append(item("Create Group", "square.on.square.dashed", .createGroup))
        if e.dimension?.kind == .linear || e.dimension?.kind == .aligned { extras.append(item("Edit Witness Lines", "ruler", .editWitnessLines)) }
        // WP6a: viewports on sheets and the 3D selection box.
        if e.viewport != nil, state.activeViewportEditor == nil, state.model[e.viewport?.viewID]?.view != nil {
            extras.append(item("Activate View", "rectangle.inset.filled.and.cursorarrow", .activateViewport))
        }
        if e.category.isModel { extras.append(item("Selection Box", "cube.transparent", .selectionBox)) }
        menu.addItem(.separator())
        for i in extras { menu.addItem(i) }
    }

    /// The two-letter snap overrides for the next pick, with their aliases shown.
    private func snapOverrideItems() -> [NSMenuItem] {
        let entries: [(String, CommandID)?] = [
            ("Endpoints", .snapEndpoint), ("Midpoints", .snapMidpoint), ("Nearest", .snapNearest), ("Work Plane Grid", .snapWorkPlaneGrid),
            ("Quadrants", .snapQuadrant), ("Intersections", .snapIntersection), ("Centers", .snapCenter), ("Perpendicular", .snapPerpendicular),
            ("Tangents", .snapTangent), ("Points", .snapPoints), nil, ("Snap to Remote Objects", .snapRemote), ("Close", .snapClose), nil,
            ("Turn Override Off", .snapOverrideOff), ("Snaps Off", .snapsOff),
        ]
        return entries.map { entry in
            guard let (title, id) = entry else { return .separator() }
            let alias = KeyboardAliases.shared.aliases(for: id).first.map { "  \($0)" } ?? ""
            return item(title + alias, CommandCatalog.info(id).symbol, id)
        }
    }

    // MARK: Helpers

    private func submenu(_ title: String, _ symbol: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        let m = NSMenu(title: title)
        m.autoenablesItems = false
        for x in items { m.addItem(x) }
        i.submenu = m
        return i
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping @MainActor () -> Void) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: #selector(KeysMenuAction.run(_:)), keyEquivalent: "")
        i.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        i.target = KeysMenuAction.shared
        i.representedObject = KeysMenuAction.Box(run)
        return i
    }
}

/// Menu items that run a closure (Cancel, Repeat).
@MainActor
final class KeysMenuAction: NSObject {
    static let shared = KeysMenuAction()
    final class Box { let run: @MainActor () -> Void; init(_ run: @escaping @MainActor () -> Void) { self.run = run } }
    @objc func run(_ sender: NSMenuItem) { (sender.representedObject as? Box)?.run() }
}
