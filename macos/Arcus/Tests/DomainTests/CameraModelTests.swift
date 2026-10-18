import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

// W2-CAM: camera math (lens, basis, roll, navigation motions) and camera view parameters.

private func near(_ a: Double, _ b: Double, _ tol: Double = 1e-9) -> Bool { abs(a - b) <= tol }
private func near(_ a: Vec3, _ b: Vec3, _ tol: Double = 1e-9) -> Bool { (a - b).length <= tol }

@Suite("Camera math")
struct CameraMathTests {
    let deg = Double.pi / 180

    @Test func focalLengthAndFieldOfViewAreLinked() {
        // 35 mm-equivalent against the 24 mm frame height: 50 mm ≈ 26.99°, 24 mm = 53.13°.
        #expect(near(Camera3D.fieldOfView(focalLength: 50), 2 * atan(12.0 / 50)))
        #expect(near(Camera3D.fieldOfView(focalLength: 12), .pi / 2), "12 mm on a 24 mm frame is 90° vertical")
        for mm in [4.0, 18, 35, 50, 85, 300, 2000] {
            #expect(near(Camera3D.focalLength(fieldOfView: Camera3D.fieldOfView(focalLength: mm)), mm, 1e-9))
        }
        var c = Camera3D.lookAt(eye: .zero, target: Vec3(0, 10, 0))
        c.focalLength = 35
        #expect(near(c.fieldOfView, 2 * atan(12.0 / 35)))
        c.fieldOfView = 60 * deg
        #expect(near(c.focalLength, 12 / tan(30 * deg)))
        // Out-of-range lenses clamp.
        #expect(near(Camera3D.fieldOfView(focalLength: 1), Camera3D.fieldOfView(focalLength: 4)))
    }

    @Test func lookAtBuildsALevelRightHandedBasis() {
        let c = Camera3D.lookAt(eye: Vec3(0, -10, 1.6), target: Vec3(0, 0, 1.6))
        let b = c.basis
        #expect(near(b.forward, .unitY) && near(b.right, .unitX) && near(b.up, .unitZ))
        #expect(near(c.roll, 0))
        // Looking straight down keeps north at the top.
        let top = Camera3D.lookAt(eye: Vec3(0, 0, 20), target: .zero)
        #expect(near(top.basis.up, .unitY) && near(top.basis.right, .unitX))
    }

    @Test func rollRotatesUpAboutTheViewDirection() {
        var c = Camera3D.lookAt(eye: Vec3(0, -10, 1.6), target: Vec3(0, 0, 1.6), roll: 20 * deg)
        #expect(near(c.roll, 20 * deg, 1e-12))
        // Positive roll turns the camera clockwise as the viewer sees it: up leans to the right.
        #expect(c.basis.up.x > 0 && near(c.basis.up.dot(c.forward), 0))
        c.roll = -35 * deg
        #expect(near(c.roll, -35 * deg, 1e-12))
    }

    @Test func orbitIsATurntableAboutThePivot() {
        let pivot = Vec3(5, 5, 0)
        let c = Camera3D.lookAt(eye: Vec3(5, -5, 0), target: pivot, isPerspective: true)
        let yawed = CameraMotion.orbit(c, yaw: .pi / 2, pitch: 0, pivot: pivot)
        #expect(near(yawed.eye, Vec3(15, 5, 0), 1e-9), "a quarter turn counter-clockwise moves the eye from south to east")
        #expect(near(yawed.target, pivot) && near(yawed.distance, c.distance))
        let raised = CameraMotion.orbit(c, yaw: 0, pitch: 30 * deg, pivot: pivot)
        #expect(near(CameraMotion.elevation(raised), 30 * deg, 1e-9) && raised.eye.z > 0)
        #expect(near((raised.eye - pivot).length, 10, 1e-9) && near(raised.roll, 0, 1e-9))
        // The elevation clamps at straight down.
        let over = CameraMotion.orbit(c, yaw: 0, pitch: 200 * deg, pivot: pivot)
        #expect(near(CameraMotion.elevation(over), .pi / 2, 1e-9))
        // Roll survives an orbit.
        var rolled = c; rolled.roll = 10 * deg
        #expect(near(CameraMotion.orbit(rolled, yaw: 0.4, pitch: 0.2, pivot: pivot).roll, 10 * deg, 1e-9))
    }

    @Test func panMovesEyeAndTargetInTheViewPlane() {
        let c = Camera3D.lookAt(eye: Vec3(0, -10, 0), target: .zero)
        let p = CameraMotion.pan(c, dx: 2, dy: 1)
        #expect(near(p.eye, Vec3(2, -10, 1)) && near(p.target, Vec3(2, 0, 1)))
    }

    @Test func dollyMovesTowardTheTargetAndThroughIt() {
        let c = Camera3D.lookAt(eye: Vec3(0, -10, 0), target: .zero)
        let d = CameraMotion.dolly(c, factor: 2)
        #expect(near(d.eye, Vec3(0, -5, 0)) && near(d.target, .zero))
        let through = CameraMotion.dolly(Camera3D.lookAt(eye: Vec3(0, -0.06, 0), target: .zero), factor: 10)
        #expect(through.eye.y > -0.06 && near(through.distance, 0.05, 1e-12), "the target is pushed ahead")
        var ortho = c; ortho.isPerspective = false; ortho.orthoHeight = 20
        #expect(near(CameraMotion.dolly(ortho, factor: 4).orthoHeight, 5))
        #expect(CameraMotion.dolly(c, factor: .nan) == c)
    }

    @Test func zoomTowardAPointKeepsTheViewDirection() {
        let c = Camera3D.lookAt(eye: Vec3(0, -10, 0), target: .zero)
        let z = CameraMotion.zoom(c, factor: 2, toward: Vec3(4, 0, 0))
        #expect(near(z.eye, Vec3(2, -5, 0)))
        #expect(near(z.forward, c.forward))
    }

    @Test func flyLooksAndMovesLikeAFirstPersonCamera() {
        let c = Camera3D.lookAt(eye: Vec3(0, 0, 1.6), target: Vec3(0, 10, 1.6))
        let turned = CameraMotion.fly(c, yaw: .pi / 2)
        #expect(near(turned.forward, Vec3(-1, 0, 0), 1e-9), "positive yaw turns left")
        #expect(near(turned.eye, c.eye) && near(turned.distance, 10, 1e-9))
        let up = CameraMotion.fly(c, pitch: 30 * deg)
        #expect(near(asin(up.forward.z), 30 * deg, 1e-9))
        let capped = CameraMotion.fly(c, pitch: 2)
        #expect(near(asin(capped.forward.z), 89 * deg, 1e-9))
        let moved = CameraMotion.fly(c, move: Vec3(1, 2, 0.5))
        #expect(near(moved.eye, Vec3(1, 2, 2.1)) && near(moved.forward, c.forward))
    }

    @Test func alignCameraToViewKeepsClipAndFrame() {
        var saved = Camera3D.lookAt(eye: Vec3(0, -10, 1.6), target: .zero)
        saved.farClipActive = true; saved.farClipDistance = 42; saved.nearClip = 0.3; saved.cropWidth = 0.3; saved.cropHeight = 0.1
        let view = Camera3D(eye: Vec3(20, 20, 20), target: Vec3(1, 1, 1), up: .unitZ, isPerspective: false, fieldOfView: 0.5, orthoHeight: 12)
        let a = CameraMotion.align(saved, to: view)
        #expect(a.eye == view.eye && a.target == view.target && !a.isPerspective && a.orthoHeight == 12 && a.fieldOfView == 0.5)
        #expect(a.farClipDistance == 42 && a.effectiveFarClip == 42 && a.nearClip == 0.3 && near(a.frameAspect, 3))
    }

    @Test func projectionSwitchKeepsTheCameraInPlace() {
        var c = Camera3D.lookAt(eye: Vec3(0, -10, 0), target: .zero, fieldOfView: 60 * deg)
        c.setPerspective(false)
        #expect(!c.isPerspective && near(c.orthoHeight, 2 * 10 * tan(30 * deg)) && c.eye == Vec3(0, -10, 0))
    }

    @Test func oldCamerasDecodeWithoutTheNewFields() throws {
        let json = #"{"eye":{"x":1,"y":2,"z":3},"target":{"x":4,"y":5,"z":6},"up":{"x":0,"y":0,"z":1},"isPerspective":true,"fieldOfView":0.8,"orthoHeight":40}"#
        let c = try JSONDecoder().decode(Camera3D.self, from: Data(json.utf8))
        #expect(c.nearClip == nil && c.farClipActive == nil && c.effectiveFarClip == nil && c.frameAspect == 1.5)
        let round = try JSONDecoder().decode(Camera3D.self, from: JSONEncoder().encode(c))
        #expect(round == c)
    }
}

@Suite("Camera views")
struct CameraViewTests {
    func model() throws -> (BIMModel, ElementID, ElementID) {
        var (m, ids) = Fx.template()
        let level = ids.levels[0]
        var v: ElementID!
        try Fx.commit(&m) { tx in v = try CameraViews.create(eye: Vec2(-5, 0), target: Vec2(5, 0), levelID: level, in: tx) }
        return (m, v, level)
    }

    @Test func placedCamerasAreCameraViewsAndShowTheirFrame() throws {
        let (m, v, _) = try model()
        let e = try #require(m[v])
        #expect(e.isCameraView && e.view?.cropActive == true)
        #expect(m.cameraViews.map(\.id).contains(v))
        // The default 3D view is not a camera.
        var d = ViewData(kind: .threeD); d.camera = .defaultIsometric
        #expect(!Element(id: ElementID(1), category: .views, data: .view(d)).isCameraView)
    }

    @Test func parametersEditTheCameraWithUndo() throws {
        var (m, v, level) = try model()
        let names = Set(Parameters.instanceEntries(m[v]!, m).map(\.name))
        for n in ["Projection", "Focal Length (mm)", "Field of View", "Eye Position X", "Eye Elevation", "Target Elevation", "Roll",
                  "Near Clip Offset", "Far Clip Active", "Far Clip Offset", "Crop Region Width", "Crop Region Height", "Aspect Ratio", "Section Box"] {
            #expect(names.contains(n), "missing \(n)")
        }
        let z = m.elevation(ofLevel: level)
        let (record, _) = try Fx.commit(&m) { tx in
            try Parameters.set(ParameterID("camera.focalLength"), to: .double(35), on: v, in: tx)
            try Parameters.set(ParameterID("view.eyeHeight"), to: .double(3), on: v, in: tx)
            try Parameters.set(ParameterID("camera.roll"), to: .double(0.2), on: v, in: tx)
            try Parameters.set(ParameterID("camera.farClipActive"), to: .bool(true), on: v, in: tx)
            try Parameters.set(ParameterID("camera.farClipOffset"), to: .double(25), on: v, in: tx)
            try Parameters.set(ParameterID("camera.cropWidth"), to: .double(0.32), on: v, in: tx)
        }
        let c = try #require(m[v]?.view?.camera)
        #expect(near(c.focalLength, 35, 1e-9) && near(c.eye.z, z + 3) && near(c.roll, 0.2, 1e-9))
        #expect(c.effectiveFarClip == 25 && near(c.frameAspect, 2))
        #expect(near(Parameters.value(ParameterID("camera.fieldOfView"), of: m[v]!, m)?.doubleValue ?? 0, 2 * atan(12.0 / 35)))
        // One transaction: the inverse restores the original camera.
        let undone = try #require(record.inverse.changes.first { $0.id == v }?.after?.view?.camera)
        #expect(undone.farClipActive == nil && near(undone.focalLength, Camera3D.focalLength(fieldOfView: CameraViews.defaultFieldOfView), 1e-9))
        // Orthographic cameras stay cameras and get a view height instead of a lens.
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("camera.projection"), to: .text("Orthographic"), on: v, in: tx) }
        #expect(m[v]!.isCameraView && m[v]!.view!.camera!.isPerspective == false)
        #expect(Parameters.instanceEntries(m[v]!, m).contains { $0.name == "View Height" })
    }

    @Test func invalidValuesAreRefused() throws {
        var (m, v, _) = try model()
        #expect(throws: (any Error).self) {
            try Fx.commit(&m) { tx in try Parameters.set(ParameterID("camera.focalLength"), to: .double(1), on: v, in: tx) }
        }
        #expect(throws: (any Error).self) {
            try Fx.commit(&m) { tx in try Parameters.set(ParameterID("camera.eyeX"), to: .double(5), on: v, in: tx); try Parameters.set(ParameterID("camera.eyeY"), to: .double(0), on: v, in: tx); try Parameters.set(ParameterID("view.eyeHeight"), to: .double(CameraViews.defaultTargetHeight), on: v, in: tx) }
        }
    }

    @Test func duplicateAndCreateFromView() throws {
        var (m, v, level) = try model()
        var copy: ElementID!
        try Fx.commit(&m) { tx in copy = try CameraViews.duplicate(v, in: tx) }
        #expect(m[copy]!.name == m[v]!.name + " Copy" && m[copy]!.view?.camera == m[v]!.view?.camera && m[copy]!.levelID == level)
        var made: ElementID!
        let cam = Camera3D.lookAt(eye: Vec3(0, -20, m.elevation(ofLevel: level) + 1.7), target: .zero)
        try Fx.commit(&m) { tx in made = CameraViews.create(camera: cam, in: tx) }
        #expect(m[made]!.isCameraView && m[made]!.levelID == level)
        // Aligning a camera to a view keeps its frame settings.
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("camera.cropHeight"), to: .double(0.12), on: v, in: tx) }
        try Fx.commit(&m) { tx in try CameraViews.setCamera(cam, of: v, in: tx) }
        #expect(m[v]!.view!.camera!.eye == cam.eye && m[v]!.view!.camera!.cropHeight == 0.12)
    }

    @Test func planGlyphAndGripsMoveEyeAndTarget() throws {
        var (m, v, _) = try model()
        let plan = try #require(m.views.first { $0.view?.kind == .floorPlan && $0.levelID == m[v]!.levelID })
        #expect(ViewGraphicsBuilder(model: m, view: plan).build().items.contains { $0.elementID == v && $0.category == .cameras })
        let grips = GripService.grips(for: m[v]!, m, viewKind: .floorPlan)
        #expect(grips.map(\.position) == [Vec2(-5, 0), Vec2(5, 0)])
        let before = m[v]!.view!.camera!
        try Fx.commit(&m) { tx in GripService.apply(grips[1], to: Vec2(5, 5), in: tx) }
        let after = m[v]!.view!.camera!
        #expect(after.target == Vec3(5, 5, before.target.z) && after.eye == before.eye)
        #expect(GripService.grips(for: m[v]!, m, viewKind: .threeD).isEmpty)
        // Orthographic cameras keep their glyph.
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("camera.projection"), to: .text("Orthographic"), on: v, in: tx) }
        #expect(ViewGraphicsBuilder(model: m, view: plan).build().items.contains { $0.elementID == v && $0.category == .cameras })
    }
}
