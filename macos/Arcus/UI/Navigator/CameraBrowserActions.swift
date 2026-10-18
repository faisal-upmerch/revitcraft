import SwiftUI
import ArcusGeometry
import ArcusDomain
import ArcusApplication

// W2-CAM, folded into the Project Browser by BL-BROWSER: camera views are listed under 3D Views and these actions
// are on their context menu (Show Camera, Set as Active Camera, Look Through, Align to Current View).

/// Camera-view actions of the Project Browser.
@MainActor
struct CameraBrowserActions {
    let state: DocumentState

    func setActive(_ id: ElementID) {
        CameraSessionState.of(state).activeCameraID = id
        state.show("“\(state.model[id]?.name ?? "")” is the active camera: View Through Camera (keypad 0) looks through it.")
    }

    /// Show Camera: selects the camera in a plan of its level (opening one when the active view isn't).
    func showCamera(_ id: ElementID) {
        guard let cam = state.model[id] else { return }
        let showsIt: (Element?) -> Bool = { v in v?.view?.kind.isPlan == true && v?.levelID == cam.levelID }
        if !showsIt(state.activeView), let plan = state.model.views.first(where: { showsIt($0) && $0.view?.kind == .floorPlan }) ?? state.model.views.first(where: showsIt) {
            state.open(plan.id)
        }
        state.session.selection.select([id])
        if !showsIt(state.activeView) { state.show("“\(cam.name)” has no plan to show it in; it is selected so you can edit it in Properties.") }
    }

    func lookThrough(_ id: ElementID) {
        if let v = state.activeViewID, v != id, let host = state.canvases[v] as? Viewport3DHost, state.model[v]?.isCameraView != true {
            host.lookThrough(id)
        } else {
            state.open(id)
        }
    }

    func alignToCurrentView(_ id: ElementID) {
        guard let v = state.activeViewID, let host = state.canvases[v] as? Viewport3DHost else {
            state.show("Open a 3D view to align the camera to it.")
            return
        }
        let cam = host.viewport.camera
        state.session.perform("Align Camera to View") { tx in try CameraViews.setCamera(cam, of: id, in: tx) }
        if state.session.lastError == nil { state.show("“\(state.model[id]?.name ?? "")” now matches the current view.") }
    }
}
