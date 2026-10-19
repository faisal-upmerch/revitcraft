import Foundation
import Testing
import AppKit
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

// S3D: 3D snapping measures distances on screen with the viewport's `screenProjection`; it must map world points to
// exactly where the viewport draws them and shoot the same pointer rays.

@MainActor
@Suite("3D snapping projection")
struct S3DProjectionTests {
    @Test func screenProjectionMatchesTheViewport() throws {
        let view = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 900, height: 600))
        for perspective in [true, false] {
            var cam = Camera3D.defaultIsometric
            cam.eye = Vec3(-12, -18, 14)
            cam.target = Vec3(2, 3, 1)
            cam.isPerspective = perspective
            cam.orthoHeight = 14
            view.camera = cam
            let proj = view.screenProjection
            for p in [Vec3(0, 0, 0), Vec3(4, -2, 3), Vec3(10, 8, 0.5), Vec3(2, 3, 1)] {
                let a = try #require(view.viewPoint(of: p)), b = try #require(proj.project(p))
                #expect(hypot(Double(a.x) - b.x, Double(a.y) - b.y) < 1e-6, "perspective \(perspective): \(p) \(a) \(b)")
                let r1 = view.pointerRay(at: a), r2 = proj.ray(at: b)
                #expect(r1.direction.distance(to: r2.direction) < 1e-9 && r1.origin.distance(to: r2.origin) < 1e-6)
                #expect(abs(view.worldPerPoint(at: p) - proj.worldPerPoint(at: p)) < 1e-9)
            }
        }
    }
}
