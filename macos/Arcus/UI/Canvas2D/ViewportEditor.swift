import AppKit
import ArcusGeometry
import ArcusDomain
import ArcusApplication

/// Editing a view through its viewport on a sheet ("Activate View").
///
/// The sheet canvas hosts a second `Canvas2DView` for the placed view, framed exactly over the viewport and kept at
/// the sheet's zoom divided by the view scale, so the view lines up with the sheet drawing. Every interaction inside
/// the viewport (selection, grips, tools, snapping, keyboard) is the ordinary canvas behaviour of that view; the rest
/// of the sheet is dimmed and ignores clicks. Double-clicking outside the viewport, or Deactivate View, returns to the
/// sheet.
@MainActor
final class ViewportEditor {
    unowned let sheetCanvas: Canvas2DView
    let viewportID: ElementID
    let viewID: ElementID
    let child: Canvas2DView
    private var syncing = false

    var state: DocumentState { sheetCanvas.state }

    init(sheetCanvas: Canvas2DView, viewportID: ElementID, viewID: ElementID) {
        self.sheetCanvas = sheetCanvas
        self.viewportID = viewportID
        self.viewID = viewID
        child = Canvas2DView(state: sheetCanvas.state, viewID: viewID)
        child.sheetHost = sheetCanvas
        child.wantsLayer = true
        child.layer?.borderWidth = 1.5
        child.layer?.borderColor = Tokens.selection.cgColor
        child.setAccessibilityLabel("Activated view \(sheetCanvas.state.model[viewID]?.name ?? "")")
    }

    /// The viewport's paper box and view region, from the placed view's current graphics.
    private func placement() -> (shown: Rect2, region: Rect2, scale: Int)? {
        let m = state.model
        guard let vp = m[viewportID]?.viewport, vp.viewID == viewID, let vd = m[viewID]?.view else { return nil }
        guard let g = child.graphics ?? state.graphics.graphics(viewID) else { return nil }
        let region = SheetGraphicsBuilder.viewRegion(g)
        let (box, _) = SheetGraphicsBuilder.placement(center: vp.center, region: region, scale: vd.scale)
        return (box.expanded(by: SheetGraphicsBuilder.annotationMargin), region, vd.scale)
    }

    /// Re-frames the embedded canvas after the sheet pans or zooms, the viewport moves or the view's extent changes.
    func sync() {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        guard state.model[viewportID]?.viewport?.viewID == viewID, state.model[viewID]?.view != nil else {
            sheetCanvas.deactivateViewport()
            return
        }
        if child.superview == nil { sheetCanvas.addSubview(child) }
        guard let p = placement() else { child.isHidden = true; return }
        child.isHidden = false
        let a = sheetCanvas.toScreen(p.shown.min), b = sheetCanvas.toScreen(p.shown.max)
        let frame = NSRect(x: a.x, y: a.y, width: max(1, b.x - a.x), height: max(1, b.y - a.y))
        if child.frame != frame { child.frame = frame }
        // Paper meters per view meter is 1/scale, so the embedded canvas zooms 1/scale of the sheet.
        child.zoom = sheetCanvas.zoom / Double(max(p.scale, 1))
        child.center = p.region.center
        child.needsDisplay = true
    }

    /// Dims the sheet around the activated viewport (the embedded canvas draws on top).
    func drawDimming(in ctx: CGContext) {
        guard let g = sheetCanvas.graphics else { return }
        let a = sheetCanvas.toScreen(g.extents.min), b = sheetCanvas.toScreen(g.extents.max)
        ctx.saveGState()
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.fill(CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
        ctx.restoreGState()
    }

    /// Clicks on the sheet outside the activated view: a double-click deactivates, anything else is ignored.
    func sheetMouseDown(_ event: NSEvent) {
        if event.clickCount == 2 { sheetCanvas.deactivateViewport(); return }
        sheetCanvas.window?.makeFirstResponder(child)
        state.show("Double-click outside the view, or right-click and choose Deactivate View, to return to the sheet.")
    }

    func sheetContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(ContextMenuBuilder(state: state, viewID: sheetCanvas.viewID, canvas: sheetCanvas).item("Deactivate View", "rectangle.dashed", .deactivateViewport))
        return menu
    }
}

// MARK: - Sheet canvas: activation and drop target

extension Canvas2DView {
    /// Paper-coloured canvases: sheets and views activated on a sheet.
    var isPaper: Bool { isSheet || sheetHost != nil }

    /// The view being edited through an activated viewport on this sheet, if any.
    var activatedViewID: ElementID? { viewportEditor?.viewID }

    /// Activates a viewport so its view can be edited in place. Schedules are opened instead.
    func activateViewport(_ viewportID: ElementID) {
        guard isSheet, let vp = state.model[viewportID]?.viewport, let v = state.model[vp.viewID] else { return }
        guard v.view != nil else { state.open(vp.viewID); return }
        if viewportEditor?.viewportID == viewportID { return }
        deactivateViewport()
        state.cancelTool()
        state.session.selection.clear()
        let editor = ViewportEditor(sheetCanvas: self, viewportID: viewportID, viewID: vp.viewID)
        viewportEditor = editor
        editor.sync()
        window?.makeFirstResponder(editor.child)
        state.toolChangedState()
        needsDisplay = true
        state.show("Editing “\(v.name)” on the sheet. Double-click outside it or choose Deactivate View to return to the sheet.")
    }

    func deactivateViewport() {
        guard let editor = viewportEditor else { return }
        viewportEditor = nil
        state.cancelTool()
        state.session.selection.clear()
        editor.child.removeFromSuperview()
        window?.makeFirstResponder(self)
        state.toolChangedState()
        needsDisplay = true
    }

    /// Double-click on a sheet item: viewports of views activate (instead of opening the view in a tab).
    func activateViewportIfHit(_ item: GItem) -> Bool {
        guard isSheet, let id = item.elementID, let vp = state.model[id]?.viewport, state.model[vp.viewID]?.view != nil else { return false }
        activateViewport(id)
        return true
    }

    // MARK: Drop target (drag a view or schedule from the Project Browser onto a sheet)

    static let elementDragPrefix = "arcus-element:"

    /// Views and schedules on a drag pasteboard ("arcus-element:<id>" strings, one per dragged row). BL-BROWSER
    static func draggedElementIDs(_ pb: NSPasteboard) -> [ElementID] {
        (pb.pasteboardItems ?? []).compactMap { item in
            guard let s = item.string(forType: .string), s.hasPrefix(elementDragPrefix), let raw = UInt64(s.dropFirst(elementDragPrefix.count)) else { return nil }
            return ElementID(raw)
        }
    }

    private func draggedElements(_ sender: any NSDraggingInfo) -> [ElementID] {
        guard isSheet, viewportEditor == nil else { return [] }
        return Canvas2DView.draggedElementIDs(sender.draggingPasteboard).filter { state.model[$0]?.view != nil || state.model[$0]?.schedule != nil }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let op = fm8DragOperation(sender) { return op } // FM8: furniture files from Finder
        let ids = draggedElements(sender)
        guard !ids.isEmpty else { return [] }
        // BL-BROWSER: say at once when a view is already on a sheet.
        let refusals = ids.compactMap { SheetPlacement.refusal($0, onSheet: viewID, state.model) }
        if refusals.count == ids.count, let r = refusals.first { state.show(r, error: true); return [] }
        return .copy
    }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if let op = fm8DragOperation(sender) { return op } // FM8
        let ids = draggedElements(sender)
        return ids.contains { SheetPlacement.refusal($0, onSheet: viewID, state.model) == nil } ? .copy : []
    }

    /// BL-BROWSER: a drop starts viewport placement — the viewport follows the cursor and a click places it.
    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if let done = fm8PerformDrop(sender) { return done } // FM8
        let ids = draggedElements(sender)
        guard !ids.isEmpty, state.beginViewportPlacement(ids, onSheet: viewID) else { return false }
        let p = toView(convert(sender.draggingLocation, from: nil))
        state.activeTool?.pointerMoved(ToolInput(point: p, rawPoint: p))
        needsDisplay = true
        window?.makeFirstResponder(self)
        return true
    }
}

// MARK: - Document state helpers

extension DocumentState {
    /// The viewport editor of the active sheet, when a viewport is activated.
    var activeViewportEditor: ViewportEditor? { (canvases[activeViewID ?? ElementID(0)] as? Canvas2DView)?.viewportEditor }

    /// The view that commands and tools act on: the activated viewport's view, else the active view.
    var editingViewID: ElementID? { activeViewportEditor?.viewID ?? activeViewID }

    /// The 2D canvas showing a view (the embedded canvas for an activated viewport).
    func canvas2D(for viewID: ElementID) -> Canvas2DView? {
        if let ed = activeViewportEditor, ed.viewID == viewID { return ed.child }
        return canvases[viewID] as? Canvas2DView
    }
}
