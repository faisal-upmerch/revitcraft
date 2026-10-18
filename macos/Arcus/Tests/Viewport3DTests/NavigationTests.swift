import Foundation
import Testing
import AppKit
import simd
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

// W2-CAM: navigation input mapping, camera frame fitting, clip planes and navigation on a live viewport.

@Suite("Navigation mapping")
struct NavigationMappingTests {
    @Test func middleButtonFollowsTheChosenStyle() {
        #expect(NavigationMapping.dragMode(button: 2, modifiers: [], style: .blender) == .orbit)
        #expect(NavigationMapping.dragMode(button: 2, modifiers: .shift, style: .blender) == .pan)
        #expect(NavigationMapping.dragMode(button: 2, modifiers: .control, style: .blender) == .dolly)
        #expect(NavigationMapping.dragMode(button: 2, modifiers: [], style: .revit) == .pan)
        #expect(NavigationMapping.dragMode(button: 2, modifiers: .shift, style: .revit) == .orbit)
    }

    @Test func leftButtonNavigatesOnlyWithOption() {
        #expect(NavigationMapping.dragMode(button: 0, modifiers: [], style: .blender) == nil, "plain left drags belong to tools and selection")
        #expect(NavigationMapping.dragMode(button: 0, modifiers: .option, style: .blender) == .orbit)
        #expect(NavigationMapping.dragMode(button: 0, modifiers: [.option, .shift], style: .blender) == .pan)
        #expect(NavigationMapping.dragMode(button: 0, modifiers: [.option, .control], style: .revit) == .dolly)
        #expect(NavigationMapping.dragMode(button: 0, modifiers: [.option, .command], style: .blender) == nil)
    }

    @Test func dragDirections() {
        let right = NavigationMapping.orbitAngles(dx: 10, dy: 0)
        #expect(right.yaw < 0 && right.pitch == 0, "dragging right turns the camera clockwise (the model right)")
        #expect(NavigationMapping.orbitAngles(dx: 0, dy: -10).pitch > 0, "dragging down raises the camera")
        #expect(NavigationMapping.dollyFactor(dy: 20) > 1 && NavigationMapping.dollyFactor(dy: -20) < 1)
        #expect(abs(NavigationMapping.dollyFactor(dy: 20) * NavigationMapping.dollyFactor(dy: -20) - 1) < 1e-12)
        #expect(NavigationMapping.wheelZoomFactor(dy: 1, precise: false) > 1 && NavigationMapping.wheelZoomFactor(dy: 1e9, precise: true).isFinite)
    }

    @Test func keypadFollowsTheBlenderLayoutAndLeavesOtherKeysAlone() {
        #expect(NavigationMapping.keypadCommand(keyCode: 83, modifiers: .numericPad) == .orient(.front))
        #expect(NavigationMapping.keypadCommand(keyCode: 83, modifiers: [.numericPad, .control]) == .orient(.back))
        #expect(NavigationMapping.keypadCommand(keyCode: 85, modifiers: []) == .orient(.right))
        #expect(NavigationMapping.keypadCommand(keyCode: 85, modifiers: .control) == .orient(.left))
        #expect(NavigationMapping.keypadCommand(keyCode: 89, modifiers: []) == .orient(.top))
        #expect(NavigationMapping.keypadCommand(keyCode: 89, modifiers: .control) == .orient(.bottom))
        #expect(NavigationMapping.keypadCommand(keyCode: 87, modifiers: []) == .toggleProjection)
        #expect(NavigationMapping.keypadCommand(keyCode: 82, modifiers: []) == .action(.viewThroughCamera))
        #expect(NavigationMapping.keypadCommand(keyCode: 82, modifiers: [.control, .option]) == .action(.alignCameraToView))
        #expect(NavigationMapping.keypadCommand(keyCode: 65, modifiers: []) == .frameSelected)
        #expect(NavigationMapping.keypadCommand(keyCode: 115, modifiers: []) == .frameAll)
        // Main-row digits and letters (typed aliases, numeric entry) are not navigation; ⌘ and ⇧ combinations pass through.
        for code: UInt16 in [18, 19, 20, 29, 13, 0, 3] { #expect(NavigationMapping.keypadCommand(keyCode: code, modifiers: []) == nil) }
        #expect(NavigationMapping.keypadCommand(keyCode: 83, modifiers: .command) == nil)
        #expect(NavigationMapping.keypadCommand(keyCode: 83, modifiers: .shift) == nil)
    }

    @Test func flyKeysAndVelocity() {
        #expect(NavigationMapping.flyKey(keyCode: 13) == .forward && NavigationMapping.flyKey(keyCode: 0) == .left)
        #expect(NavigationMapping.flyKey(keyCode: 14) == .up && NavigationMapping.flyKey(keyCode: 12) == .down)
        #expect(NavigationMapping.flyKey(keyCode: 3) == nil)
        #expect(NavigationMapping.flyVelocity([.forward], speed: 2) == SIMD3(0, 2, 0))
        let diag = NavigationMapping.flyVelocity([.forward, .right], speed: 2)
        #expect(abs(simd_length(diag) - 2) < 1e-12, "diagonal movement is not faster")
        #expect(NavigationMapping.flyVelocity([.forward, .back], speed: 2) == SIMD3(0, 0, 0))
        #expect(NavigationMapping.initialFlySpeed(sceneDiagonal: 30) == 2)
        #expect(NavigationMapping.initialFlySpeed(sceneDiagonal: 0) > 0)
    }
}

@Suite("Camera frame and clipping")
struct CameraFrameTests {
    @Test func frameFitsInsideTheViewAndCarriesTheFieldOfView() {
        let size = CGSize(width: 400, height: 300)
        let r = CameraFrameFit.rect(in: size, aspect: 1.5)
        #expect(abs(r.width / r.height - 1.5) < 1e-9)
        #expect(r.minX >= 0 && r.maxX <= 400 && r.minY >= 0 && r.maxY <= 300)
        #expect(abs(r.midX - 200) < 1e-9 && abs(r.midY - 150) < 1e-9)
        let tall = CameraFrameFit.rect(in: size, aspect: 0.5)
        #expect(abs(tall.height - 300 * (1 - 2 * CameraFrameFit.margin)) < 1e-9)
        let c = Camera3D.lookAt(eye: Vec3(0, -10, 0), target: .zero, fieldOfView: 0.6)
        let f = CameraFrameFit.framed(c, aspect: 1.5, size: size)
        // The camera's angle spans the frame, so the whole view shows a wider angle.
        #expect(abs(tan(f.fieldOfView / 2) - tan(0.3) * 300 / Double(r.height)) < 1e-9)
        #expect(CameraFrameFit.framed(c, aspect: nil, size: size) == c)
        var o = c; o.isPerspective = false; o.orthoHeight = 10
        #expect(abs(CameraFrameFit.framed(o, aspect: 1.5, size: size).orthoHeight - 10 * 300 / Double(r.height)) < 1e-9)
    }

    @Test func nearAndFarClipSetTheDepthRange() {
        var c = Camera3D.lookAt(eye: .zero, target: Vec3(0, 10, 0))
        c.nearClip = 0.5
        c.farClipActive = true; c.farClipDistance = 20
        let box = Box3(min: Vec3(-50, 1, -50), max: Vec3(50, 100, 50))
        let cf = CameraFrame(camera: c, aspect: 1.5, origin: SIMD3(0, 0, 0), depthBounds: box)
        #expect(cf.near == 0.5 && cf.far == 20)
        // Reversed Z: 1 at the near plane, 0 at the far plane, negative (clipped) beyond it.
        #expect(abs(cf.ndc(SIMD3(0, 0.5, 0)).0.z - 1) < 1e-9)
        #expect(abs(cf.ndc(SIMD3(0, 20, 0)).0.z) < 1e-9)
        #expect(cf.ndc(SIMD3(0, 30, 0)).0.z < 0)
        // Linear depth recovered the way the post-processing shader does it: depthB / (z + depthA).
        let z = cf.ndc(SIMD3(0, 7, 0)).0.z
        #expect(abs(cf.depthB / (z + cf.depthA) - 7) < 1e-9)
        // Without a far clip the far plane is infinite and depthA is 0 (the previous projection).
        c.farClipActive = nil
        let inf = CameraFrame(camera: c, aspect: 1.5, origin: SIMD3(0, 0, 0), depthBounds: box)
        #expect(inf.far == .infinity && inf.depthA == 0 && inf.depthB == inf.near)
    }
}

@Suite("Viewport navigation", .serialized)
@MainActor struct ViewportNavigationTests {
    func view() -> Viewport3DView? {
        guard let b = Fixture.backends.first else { return nil }
        let v = Fixture.view(b, elements: 16)
        v.zoomExtents(animated: false)
        return v
    }

    func key(_ code: UInt16, _ chars: String, _ flags: NSEvent.ModifierFlags = []) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
    }

    @Test func keypadViewsOrientTheCamera() throws {
        guard let v = view() else { return }
        v.keyDown(with: key(89, "7", .numericPad))
        #expect(simd_length(CameraFrame.basis(v.camera).forward - SIMD3(0, 0, -1)) < 1e-6, "keypad 7 looks down")
        v.keyDown(with: key(83, "1", [.numericPad, .control]))
        #expect(simd_length(CameraFrame.basis(v.camera).forward - SIMD3(0, -1, 0)) < 1e-6, "⌃ keypad 1 looks from the back (north)")
        let wasPerspective = v.camera.isPerspective
        v.keyDown(with: key(87, "5", .numericPad))
        #expect(v.camera.isPerspective != wasPerspective)
        var asked: Viewport3DNavigationAction?
        v.onNavigationAction = { asked = $0 }
        v.keyDown(with: key(82, "0", .numericPad))
        #expect(asked == .viewThroughCamera)
    }

    @Test func dragsOrbitPanAndDolly() throws {
        guard let v = view() else { return }
        v.setPerspective(true)
        let center = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        let start = v.camera
        v.beginNavigationDrag(.orbit, button: 2, at: center)
        #expect(v.isNavigating)
        let pivot = try #require(v.navigation.drag?.anchor)
        v.continueNavigationDrag(to: CGPoint(x: center.x + 40, y: center.y))
        v.endNavigationDrag()
        #expect(!v.isNavigating || v.isInteracting, "only the settle window remains")
        let d0 = simd_length(start.eye.simd - pivot), d1 = simd_length(v.camera.eye.simd - pivot)
        #expect(abs(d0 - d1) < 1e-6, "orbiting keeps the distance to the pivot")
        #expect(simd_length(v.camera.eye.simd - start.eye.simd) > 0.1)

        let beforePan = v.camera
        v.beginNavigationDrag(.pan, button: 2, at: center)
        v.continueNavigationDrag(to: CGPoint(x: center.x + 30, y: center.y + 10))
        v.endNavigationDrag()
        let move = v.camera.eye.simd - beforePan.eye.simd
        #expect(simd_length(move) > 0 && simd_length((v.camera.target.simd - beforePan.target.simd) - move) < 1e-9, "panning moves eye and target together")

        let beforeDolly = v.camera
        v.beginNavigationDrag(.dolly, button: 2, at: center)
        v.continueNavigationDrag(to: CGPoint(x: center.x, y: center.y + 50))
        v.endNavigationDrag()
        #expect(simd_length(v.camera.eye.simd - beforeDolly.eye.simd) > 0)
        #expect(simd_length(CameraFrame.basis(v.camera).forward - CameraFrame.basis(beforeDolly).forward) < 1e-9, "dolly keeps the view direction")
    }

    @Test func farClipHidesDistantGeometryInRenderingAndPicking() throws {
        guard let v = view() else { return }
        v.setPerspective(true)
        v.zoomExtents(animated: false)
        let center = CGPoint(x: v.bounds.midX, y: v.bounds.midY)
        #expect(v.element(at: center) != nil)
        var c = v.camera
        c.farClipActive = true; c.farClipDistance = 0.5
        v.camera = c
        #expect(v.element(at: center) == nil, "geometry beyond the far clip is not drawn or picked")
    }

    @Test func cameraFrameShowsAndNarrowsTheRenderedCamera() {
        guard let v = view() else { return }
        v.setPerspective(true)
        let size = CGSize(width: 800, height: 600)
        let plain = v.cameraFrame(size: size).camera.fieldOfView
        v.cameraFrameAspect = 1.5
        #expect(v.navigation.overlay?.frameAspect == 1.5)
        #expect(v.cameraFrame(size: size).camera.fieldOfView > plain)
        #expect(v.camera.fieldOfView == plain, "the saved camera is unchanged")
        v.cameraFrameAspect = nil
        #expect(v.navigation.overlay?.frameAspect == nil)
    }
}
