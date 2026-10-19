import SwiftUI
import Observation
import ArcusDomain
import ArcusApplication

/// BL-PROPS: Properties palette state that outlives the view — the browser preview, the category filter, recently used
/// types and the values chosen for new elements.
@MainActor
@Observable
final class PaletteState {
    /// A view the Project Browser is previewing (single click); shown while nothing is selected, until the canvas is
    /// clicked or the active view changes.
    var previewViewID: ElementID?
    /// Category shown for a multi-category selection (nil = Common), valid for `filterSelection` only.
    var filter: Category?
    var filterSelection: [ElementID] = []
    /// Types picked recently in the Type Selector, most recent first.
    var recentTypes: [ElementID] = []
    /// Instance values set in the "New <Category>" state, per instance category.
    var creationDefaults: [Category: CreationDefaults] = [:]
}

/// What the palette shows.
enum PaletteSubject: Hashable {
    /// The element the active placement tool will create (instance category, current type).
    case newElement(Category, ElementID?)
    /// Selected elements (already filtered by category); `common` when they span several categories.
    case elements([ElementID], common: Bool)
    /// A view, sheet or schedule: the active view, or one previewed from the Project Browser.
    case view(ElementID)
    /// FMG2: the joint the Joint tool picked (set by the user or by the rules).
    case joint(JointKey)
    case nothing
}

extension DocumentState {
    /// Shows a view's properties in the palette without activating it (Project Browser single click). Cleared by a
    /// canvas click or by activating a view. Pass nil to stop previewing.
    func previewViewProperties(_ id: ElementID?) {
        let valid = id.flatMap { model[$0] }.map { $0.view != nil || $0.sheet != nil || $0.schedule != nil } ?? false
        palette.previewViewID = valid && id != activeViewID ? id : nil
    }

    /// A click in the drawing area: the palette returns to the active view.
    func paletteCanvasClicked() {
        if palette.previewViewID != nil { palette.previewViewID = nil }
    }

    /// Called whenever the active view changes (tabs, browser, Duplicate, schedule jump, Previous View): with nothing
    /// but views selected (a browser selection), the palette follows the newly active view.
    func paletteViewActivated() {
        palette.previewViewID = nil
        let sel = session.selection.ids.compactMap { model[$0] }
        if !sel.isEmpty, sel.allSatisfy({ $0.view != nil || $0.sheet != nil || $0.schedule != nil }) { session.selection.clear() }
    }

    /// Called when the active tool changes: installs the pending new-element values for the tool's category.
    func paletteToolChanged() { syncCreationDefaults() }

    /// Instance category of the element the active tool places, if it is a placement tool.
    var placementCategory: Category? {
        guard let t = activeTool, let cat = PropertiesView.category(for: t.commandID) else { return nil }
        if cat == .furniture, let tid = currentTypes[.furniture], let c = model[tid]?.typeData?.instanceCategory { return c }
        return cat
    }

    /// Type the active placement tool will use.
    var placementTypeID: ElementID? {
        guard let cat = placementCategory, let t = activeTool, let key = PropertiesView.category(for: t.commandID) else { return nil }
        return currentTypes[key] ?? currentTypes[cat] ?? model.types(for: cat).first?.id
    }

    func syncCreationDefaults() {
        guard let cat = placementCategory, let d = palette.creationDefaults[cat], !d.isEmpty else { session.creationDefaults = nil; return }
        session.creationDefaults = d
    }

    /// The palette's subject: the pending new element, the selection, a previewed view or the active view.
    var paletteSubject: PaletteSubject {
        if let cat = placementCategory { return .newElement(cat, placementTypeID) }
        if let k = (activeTool as? FurnitureJointTool)?.picked { return .joint(k) } // FMG2: the picked joint, automatic or not
        let sel = session.selection.ids.compactMap { model[$0] }
        if !sel.isEmpty {
            if sel.count == 1, sel[0].view != nil || sel[0].sheet != nil || sel[0].schedule != nil { return .view(sel[0].id) }
            let cats = Set(sel.map(\.category))
            if cats.count == 1 { return .elements(sel.map(\.id), common: false) }
            if palette.filterSelection == session.selection.ids, let f = palette.filter, cats.contains(f) {
                return .elements(sel.filter { $0.category == f }.map(\.id), common: false)
            }
            return .elements(sel.map(\.id), common: true)
        }
        if let p = palette.previewViewID, model[p] != nil { return .view(p) }
        if let v = activeViewID, model[v] != nil { return .view(v) }
        return .nothing
    }
}
