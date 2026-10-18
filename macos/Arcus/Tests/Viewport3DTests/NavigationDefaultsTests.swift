import Foundation
import Testing
import AppKit
import simd
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

// BL-SITE (ARCUS-029/030/031): BIM-style navigation by default, the same zoom ratio per wheel notch in every view,
// and a complete orientation cube.

@Suite("Navigation defaults")
struct NavigationDefaultsTests {
    @MainActor @Test func freshInstallUsesBIMStyle() {
        let key = "viewport3D.navigationStyle"
        let saved = UserDefaults.standard.string(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        UserDefaults.standard.removeObject(forKey: key)
        let style = Viewport3DNavigationSettings.style
        #expect(style == .revit)
        #expect(NavigationMapping.dragMode(button: 2, modifiers: [], style: style) == .pan, "middle-drag pans")
        #expect(NavigationMapping.dragMode(button: 2, modifiers: .shift, style: style) == .orbit, "⇧ middle-drag orbits")
        // The Blender-style scheme stays available and is remembered.
        Viewport3DNavigationSettings.style = .blender
        #expect(Viewport3DNavigationSettings.style == .blender)
        #expect(NavigationMapping.dragMode(button: 2, modifiers: [], style: .blender) == .orbit)
        #expect(!Viewport3DNavigationStyle.revit.summary.isEmpty && !Viewport3DNavigationStyle.blender.summary.isEmpty)
    }

    @Test func trackpadSwipesFollowTheStyle() {
        #expect(!NavigationMapping.trackpadSwipeOrbits(style: .revit, shift: false), "BIM: two-finger drag pans")
        #expect(NavigationMapping.trackpadSwipeOrbits(style: .revit, shift: true), "BIM: ⇧ two-finger drag orbits")
        #expect(NavigationMapping.trackpadSwipeOrbits(style: .blender, shift: false))
        #expect(!NavigationMapping.trackpadSwipeOrbits(style: .blender, shift: true))
    }

    @Test func bimStyleOrbitsAboutTheSelectionOrTheModelCentre() {
        #expect(NavigationMapping.pivotRule(style: .revit, orbitAroundSelection: false) == .selectionOrModelCentre)
        #expect(NavigationMapping.pivotRule(style: .blender, orbitAroundSelection: false) == .pointer)
        #expect(NavigationMapping.pivotRule(style: .blender, orbitAroundSelection: true) == .selectionOrPointer)
    }

    @Test func oneWheelNotchIsTheSameRatioInEveryView() {
        // 2D views (Canvas2DView) and 3D views both use NavigationZoom; five notches in and out cancel.
        let five = NavigationZoom.factor(dy: 5 * 1, precise: false) // clamped to 4 lines per event
        #expect(abs(NavigationMapping.wheelZoomFactor(dy: 1, precise: false) - NavigationZoom.notchFactor) < 1e-12)
        var scale = 1.0
        for _ in 0..<5 { scale *= NavigationZoom.factor(dy: 1, precise: false) }
        #expect(abs(scale - pow(1.18, 5)) < 1e-9 && scale > 2, "five notches more than double the scale")
        for _ in 0..<5 { scale *= NavigationZoom.factor(dy: -1, precise: false) }
        #expect(abs(scale - 1) < 1e-9)
        #expect(five == pow(1.18, 4))
        #expect(abs(NavigationZoom.factor(dy: 100, precise: true) - pow(1.006, 100)) < 1e-12)
    }

    @Test func orientationCubeUpVector() {
        #expect(OrientationCubeMath.up(forViewFrom: SIMD3(0, 0, 1)) == SIMD3(0, 1, 0), "Top shows plan north up")
        #expect(OrientationCubeMath.up(forViewFrom: SIMD3(0, 0, -1)) == SIMD3(0, 1, 0))
        #expect(OrientationCubeMath.up(forViewFrom: SIMD3(1, 0, 1)) == SIMD3(0, 0, 1))
    }
}

@Suite("Orientation cube", .serialized)
@MainActor struct OrientationCubeTests {
    /// A widget seen from the default south-west isometric camera.
    func widget() -> OrientationWidget {
        let w = OrientationWidget(frame: NSRect(x: 0, y: 0, width: 112, height: 128))
        w.basisProvider = { CameraFrame.basis(Camera3D.defaultIsometric) }
        return w
    }

    /// Projects a cube point the way the widget draws it.
    func point(_ w: OrientationWidget, _ p: SIMD3<Double>) -> CGPoint {
        let b = CameraFrame.basis(Camera3D.defaultIsometric)
        let c = CGPoint(x: w.bounds.midX + 4, y: w.bounds.maxY - 56)
        return CGPoint(x: c.x + dot(p, b.right) * 20, y: c.y + dot(p, b.up) * 20)
    }

    @Test func facesEdgesCornersCompassAndHomeAreClickable() {
        let w = widget()
        #expect(w.target(at: point(w, SIMD3(0, 0, 1))) == .face(.top), "the TOP face")
        #expect(w.target(at: point(w, SIMD3(-1, -1, 1))) == .corner(.southWestIso), "the nearest top corner")
        #expect(w.target(at: point(w, SIMD3(0, -1, 1))) == .direction(SIMD3(0, -1, 1)), "the top-front edge")
        #expect(w.target(at: point(w, SIMD3(-1, -1, 0))) == .direction(SIMD3(-1, -1, 0)), "the front-left vertical edge")
        #expect(w.target(at: point(w, SIMD3(-1, -1, -1))) == .direction(SIMD3(-1, -1, -1)), "a visible bottom corner")
        #expect(w.target(at: point(w, SIMD3(0, -2.05, -1))) == .compass(.front), "the S letter")
        #expect(w.target(at: CGPoint(x: 16, y: 16)) == .home)
    }

    @Test func clickingOrients() {
        let w = widget()
        var preset: OrientationPreset?, dir: SIMD3<Double>?
        w.onOrient = { preset = $0 }
        w.onOrientDirection = { dir = $0 }
        for (p, check) in [(point(w, SIMD3(0, 0, 1)), 0), (point(w, SIMD3(0, -1, 1)), 1)] {
            let loc = w.convert(p, to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                                           eventNumber: 0, clickCount: 1, pressure: 1)!
                if type == .leftMouseDown { w.mouseDown(with: e) } else { w.mouseUp(with: e) }
            }
            if check == 0 { #expect(preset == .top) } else { #expect(dir == SIMD3(0, -1, 1)) }
        }
    }

    @Test func topOrientsPlanDown() throws {
        guard let b = Fixture.backends.first else { return }
        let v = Fixture.view(b, elements: 8)
        v.orient(to: .top, animated: false)
        let basis = CameraFrame.basis(v.camera)
        #expect(simd_length(basis.forward - SIMD3(0, 0, -1)) < 1e-6 && simd_length(basis.up - SIMD3(0, 1, 0)) < 1e-6)
        v.orient(toDirection: Vec3(0, -1, 1), animated: false)
        let e = CameraFrame.basis(v.camera)
        #expect(simd_length(e.forward - simd_normalize(SIMD3(0, 1, -1))) < 1e-6, "the top-front edge looks down from the south at 45°")
    }
}
