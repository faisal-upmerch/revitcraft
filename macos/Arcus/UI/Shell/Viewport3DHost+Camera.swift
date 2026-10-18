import AppKit
import Observation
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusViewport3D

// W2-CAM: cameras in 3D views — Lock Camera to View, View Through Camera, Align Camera to View, the camera frame.

/// Per-document camera state (not saved in the project): the active camera and per-view Lock Camera to View.
@Observable @MainActor final class CameraSessionState {
    @ObservationIgnored private static let table = NSMapTable<DocumentState, CameraSessionState>.weakToStrongObjects()

    static func of(_ state: DocumentState) -> CameraSessionState {
        if let s = table.object(forKey: state) { return s }
        let s = CameraSessionState()
        table.setObject(s, forKey: state)
        return s
    }

    /// Camera used by View Through Camera and Align Camera to View in other 3D views.
    var activeCameraID: ElementID?
    /// Lock Camera to View per view; unset means on for camera views and off elsewhere.
    var lockOverrides: [ElementID: Bool] = [:]

    /// The active camera if it still exists, else the only camera of the project.
    func activeCamera(in model: BIMModel) -> ElementID? {
        if let id = activeCameraID, model[id]?.isCameraView == true { return id }
        let all = model.cameraViews
        return all.count == 1 ? all[0].id : nil
    }

    /// Whether navigating the 3D view `viewID` moves its camera (or the camera it looks through).
    func isLocked(_ viewID: ElementID, _ model: BIMModel) -> Bool {
        lockOverrides[viewID] ?? (model[viewID]?.isCameraView ?? false)
    }
}

/// Camera state of one 3D view host.
@MainActor final class CameraHostControl {
    private static let table = NSMapTable<Viewport3DHost, CameraHostControl>.weakToStrongObjects()

    static func of(_ host: Viewport3DHost) -> CameraHostControl {
        if let c = table.object(forKey: host) { return c }
        let c = CameraHostControl()
        table.setObject(c, forKey: host)
        return c
    }

    /// Camera view this viewport is looking through (Blender's camera view), if any.
    var lookingThrough: ElementID?
    /// That camera as last applied or committed (to follow undo and edits made elsewhere).
    var throughCamera: Camera3D?
    /// Where the viewport was before looking through, restored when leaving.
    var cameraBefore: Camera3D?
    var settleTask: Task<Void, Never>?
}

extension Camera3D {
    /// Same pose, projection and lens (clip and frame settings ignored).
    func hasSamePose(as o: Camera3D) -> Bool { CameraMotion.align(o, to: self).isAlmostEqual(o, tolerance: 1e-6) }
}

extension Viewport3DHost {
    var cameraControl: CameraHostControl { CameraHostControl.of(self) }
    var cameraSession: CameraSessionState { CameraSessionState.of(state) }

    /// Hooked from `init`: commits navigation to locked cameras, forwards keypad 0 / ⌃⌥0 and keeps the frame current.
    func installCameraControls() {
        viewport.onCameraChanged = { [weak self] _ in self?.cameraNavigationSettled() }
        viewport.onNavigationAction = { [weak self] a in
            switch a {
            case .viewThroughCamera: self?.toggleViewThroughCamera()
            case .alignCameraToView: self?.alignCameraToView()
            }
        }
        _ = state.session.onChange { [weak self] _ in self?.cameraModelChanged() }
        cameraModelChanged()
    }

    /// The camera this viewport navigates when locked: the one it looks through, or its own when it is a camera view.
    var navigatedCameraID: ElementID? {
        if let id = cameraControl.lookingThrough { return id }
        return state.model[viewID]?.isCameraView == true ? viewID : nil
    }

    /// Called (debounced) after the viewport camera changes. Commits one undoable change per navigation once it ends.
    func cameraNavigationSettled() {
        let control = cameraControl
        control.settleTask?.cancel()
        if viewport.isNavigating {
            control.settleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                self?.cameraNavigationSettled()
            }
            return
        }
        let cam = viewport.camera
        let model = state.model
        let locked = cameraSession.isLocked(viewID, model)
        if let through = control.lookingThrough {
            guard let saved = model[through]?.view?.camera else { leaveCamera(restore: false); return }
            guard !cam.hasSamePose(as: saved) else { return }
            if locked {
                control.throughCamera = CameraMotion.align(saved, to: cam)
                state.session.perform("Move Camera") { tx in try CameraViews.setCamera(cam, of: through, in: tx) }
            } else {
                // Unlocked: navigating leaves the camera view and the saved camera stays put.
                leaveCamera(restore: false)
            }
            return
        }
        guard locked, let own = model[viewID], own.isCameraView, let saved = own.view?.camera, !cam.hasSamePose(as: saved) else { return }
        let id = viewID
        state.session.perform("Move Camera") { tx in try CameraViews.setCamera(cam, of: id, in: tx) }
    }

    /// Follows model changes: the looked-through camera moving (undo, Properties) and the camera frame.
    func cameraModelChanged() {
        let control = cameraControl
        let model = state.model
        if let through = control.lookingThrough {
            if let c = model[through]?.view?.camera, model[through]?.isCameraView == true {
                if let last = control.throughCamera, c != last, !viewport.isNavigating {
                    control.throughCamera = c
                    viewport.camera = c
                }
            } else {
                leaveCamera(restore: false)
            }
        }
        updateCameraFrame()
    }

    /// Shows the frame of the camera being viewed when its view crops (Crop View on).
    func updateCameraFrame() {
        let model = state.model
        guard let id = navigatedCameraID, let e = model[id], let vd = e.view, let c = vd.camera, vd.cropActive else {
            viewport.cameraFrameAspect = nil
            return
        }
        viewport.cameraFrameAspect = c.frameAspect
    }

    /// Keypad 0 / View Through Camera: looks through the active camera; again returns to where the view was.
    func toggleViewThroughCamera() {
        let control = cameraControl
        let model = state.model
        if control.lookingThrough != nil { leaveCamera(restore: true); return }
        let active = cameraSession.activeCamera(in: model)
        if model[viewID]?.isCameraView == true, active == nil || active == viewID {
            // In a camera view: back to its saved camera.
            if let c = model[viewID]?.view?.camera { viewport.setCamera(c, animated: !AccessibilityPrefs.reduceMotion) }
            return
        }
        guard let id = active else {
            state.show(model.cameraViews.isEmpty
                       ? "There are no cameras yet. Use Create Camera from View, or place one from a plan with View ▸ Camera."
                       : "Choose the active camera: right-click a camera in the Project Browser and choose Set as Active Camera.")
            return
        }
        lookThrough(id)
    }

    /// Looks through a camera view in this viewport.
    func lookThrough(_ id: ElementID) {
        guard let e = state.model[id], let c = e.view?.camera else { return }
        if id == viewID { viewport.setCamera(c, animated: !AccessibilityPrefs.reduceMotion); return }
        let control = cameraControl
        if control.lookingThrough == nil { control.cameraBefore = viewport.camera }
        control.lookingThrough = id
        control.throughCamera = c
        viewport.setCamera(c, animated: !AccessibilityPrefs.reduceMotion)
        updateCameraFrame()
        let lock = cameraSession.isLocked(viewID, state.model)
        state.show("Looking through “\(e.name)”. " + (lock ? "Navigating moves the camera (Lock Camera to View is on)." : "Navigating leaves the camera; turn on Lock Camera to View to move it."))
    }

    /// Stops looking through a camera; `restore` animates back to the view from before.
    func leaveCamera(restore: Bool) {
        let control = cameraControl
        let before = control.cameraBefore
        control.lookingThrough = nil
        control.throughCamera = nil
        control.cameraBefore = nil
        updateCameraFrame()
        if restore, let before { viewport.setCamera(before, animated: !AccessibilityPrefs.reduceMotion); return }
        // Staying where the camera was: drop its clip planes, which belong to the camera, not to this view.
        var c = viewport.camera
        if let own = state.model[viewID]?.view?.camera {
            c.nearClip = own.nearClip; c.farClipActive = own.farClipActive; c.farClipDistance = own.farClipDistance
        } else {
            c.nearClip = nil; c.farClipActive = nil
        }
        if c != viewport.camera { viewport.camera = c }
    }

    /// ⌃⌥ keypad 0 / Align Camera to View: moves the camera being viewed (or the active camera) to the current view.
    func alignCameraToView() {
        let model = state.model
        guard let id = navigatedCameraID ?? cameraSession.activeCamera(in: model), let e = model[id], let saved = e.view?.camera else {
            state.show("Choose a camera first: right-click one in the Project Browser and choose Set as Active Camera, or use Create Camera from View.")
            return
        }
        let cam = viewport.camera
        state.session.perform("Align Camera to View") { tx in try CameraViews.setCamera(cam, of: id, in: tx) }
        guard state.session.lastError == nil else { return }
        if id != viewID {
            let control = cameraControl
            if control.lookingThrough == nil { control.cameraBefore = cam }
            control.lookingThrough = id
            control.throughCamera = CameraMotion.align(saved, to: cam)
            updateCameraFrame()
        }
        state.show("“\(e.name)” now matches this view.")
    }

    /// Saves the current view as a new camera and makes it the active camera.
    func createCameraFromView() {
        var cam = viewport.camera
        cam.cropWidth = CameraViews.defaultCropWidth
        cam.cropHeight = CameraViews.defaultCropHeight
        var created: ElementID?
        let template = state.model[viewID]?.view
        state.session.perform("Create Camera") { tx in created = CameraViews.create(camera: cam, from: template, in: tx) }
        guard let created, let e = state.model[created] else { return }
        cameraSession.activeCameraID = created
        state.show("Created camera “\(e.name)” and made it the active camera.")
    }

    /// Lock Camera to View on or off for this view.
    func toggleCameraLock() {
        let on = !cameraSession.isLocked(viewID, state.model)
        cameraSession.lockOverrides[viewID] = on
        state.show(on ? "Lock Camera to View is on: navigating moves the camera." : "Lock Camera to View is off: navigating no longer changes the saved camera.")
    }
}
