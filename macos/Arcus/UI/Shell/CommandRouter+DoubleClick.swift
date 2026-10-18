import AppKit
import ArcusDomain
import ArcusApplication

// BL-CANVAS (ARCUS-085): Settings ▸ Double-click decides what double-clicking an element does.

extension CommandRouter {
    /// Applies the double-click preference for `e`. Returns true when it handled the double-click (including "Do
    /// Nothing"); false leaves the built-in behaviour (edit type, sketch or group).
    func doubleClickPreference(_ e: Element) -> Bool {
        switch e.data {
        case .slab, .roof, .filledRegion, .revisionCloud, .railing, .stair:
            return CanvasSettings.sketchDoubleClick == .nothing
        case .group:
            return CanvasSettings.groupDoubleClick == .nothing
        case .insert, .component, .column, .detailComponent:
            switch CanvasSettings.familyDoubleClick {
            case .editType: return false
            case .nothing: return true
            case .editFamily:
                guard Parameters.familyDefinition(for: e, model) != nil else { return false }
                session.selection.select([e.id])
                run(.familyEditor)
                return true
            }
        default:
            return false
        }
    }
}

extension Canvas2DView {
    /// Double-click on a viewport on a sheet: nil keeps the default (activate the view), true means handled.
    func viewportDoubleClickPreference(_ target: ElementID) -> Bool? {
        switch CanvasSettings.viewportDoubleClick {
        case .activate: return nil
        case .open: state.open(target); return true
        case .nothing: return true
        }
    }
}
