import Foundation
import Testing
import simd
import ArcusGeometry
@testable import ArcusViewport3D

@Suite("Shadow math")
struct ShadowMathTests {
    @Test func lightMatrixEnclosesTheBoundsAndOrdersDepthFromTheSun() throws {
        let box = Box3(min: Vec3(100, 200, 0), max: Vec3(140, 230, 25))
        let origin = SIMD3<Double>(120, 215, 12)
        for sun in [SIMD3<Double>(0.3, -0.5, 0.8), SIMD3(0, 0, 1), SIMD3(-0.9, 0.1, 0.05)] {
            let (m, extent) = try #require(ShadowMath.lightMatrix(towardLight: simd_normalize(sun), bounds: box, origin: origin))
            #expect(extent.x > 0 && extent.y > 0 && extent.z > 0)
            for c in box.corners {
                let p = m * SIMD4<Float>(SIMD3<Float>(c.simd - origin), 1)
                #expect(abs(p.x) <= 1 && abs(p.y) <= 1, "corner outside the shadow map for sun \(sun)")
                #expect(p.z >= 0 && p.z <= 1)
            }
            // Moving toward the sun reduces depth (0 = nearest the sun).
            let a = m * SIMD4<Float>(0, 0, 0, 1)
            let b = m * SIMD4<Float>(SIMD3<Float>(simd_normalize(sun) * 5), 1)
            #expect(b.z < a.z)
        }
        #expect(ShadowMath.lightMatrix(towardLight: SIMD3(0, 0, 1), bounds: .empty, origin: .zero) == nil)
    }

    @Test func cameraKeyLightIsAboveTheHorizonAndBehindTheViewer() {
        let forward = simd_normalize(SIMD3<Double>(1, 1, -1))
        let right = simd_normalize(cross(forward, SIMD3(0, 0, 1)))
        let up = cross(right, forward)
        let l = ShadowMath.cameraKeyLight(forward: forward, right: right, up: up)
        #expect(abs(simd_length(l) - 1) < 1e-9)
        #expect(l.z > 0.7)
        #expect(dot(SIMD2(l.x, l.y), SIMD2(forward.x, forward.y)) < 0)
    }
}
