import Foundation
import Testing
import Metal
import ArcusGeometry
import ArcusDomain
@testable import ArcusViewport3D

/// VIS: scene build and frame times for the Courtyard House and the 20k stress model (smooth curves must not regress
/// them). Prints BENCH lines; the bounds are loose sanity checks only.
@Suite("VIS viewport performance", .serialized)
@MainActor struct VISPerformanceTests {
    static let size = CGSize(width: 2560, height: 1600)

    func report(_ name: String, _ model: BIMModel) throws {
        guard MTLCreateSystemDefaultDevice() != nil else { return }
        let view3D = try #require(model.elements(.views).first { $0.view?.kind == .threeD })
        DerivedCaches.purgeAll()
        var t = CFAbsoluteTimeGetCurrent()
        let cold = SceneBuilder.build(model: model, view: view3D, detail: .fine)
        let coldMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        t = CFAbsoluteTimeGetCurrent()
        let warm = SceneBuilder.build(model: model, view: view3D, detail: .fine)
        let warmMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        let v = Viewport3DView(frame: CGRect(x: 0, y: 0, width: 1280, height: 800), backend: .classic)
        v.setScene(warm)
        v.orient(to: .southWestIso, animated: false)
        v.zoomExtents(animated: false)
        for style in [VisualStyle.shaded, .hiddenLine] {
            v.visualStyle = style
            v.showEdgesInShadedStyles = style == .shaded
            _ = v.measureFrameTimes(frames: 5, size: Self.size)
            let r = v.measureFrameTimes(frames: 60, size: Self.size)
            print(String(format: "BENCH VIS %@ %@: scene cold %.1f ms warm %.1f ms, tris %d, edges %d, gpu median %.3f ms p95 %.3f ms, cpu median %.3f ms",
                         name, style.rawValue, coldMs, warmMs, cold.triangleCount, v.statistics.edges,
                         Stats.median(r.gpu), Stats.percentile(r.gpu, 0.95), Stats.median(r.cpu)))
            #expect(Stats.median(r.gpu) < 50)
        }
    }

    /// Library pieces with round, turned and tapered parts: {3D} scene and a Front elevation (hidden lines) at Fine.
    @Test func furniturePieces() throws {
        for name in ["Dining Table", "Dining Chair", "Side Table", "Coffee Table", "Office Chair"] {
            guard let m = FurnitureLibrary.all.first(where: { $0.name == name })?.build() else { continue }
            let v3 = try #require(m.elements(.views).first { $0.view?.kind == .threeD })
            DerivedCaches.purgeAll()
            var t = CFAbsoluteTimeGetCurrent()
            let scene = SceneBuilder.build(model: m, view: v3, detail: .fine)
            let sceneMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
            var elevMs = 0.0
            if var front = m.elements(.views).first(where: { $0.view?.kind == .elevation && $0.name.contains("Front") }) {
                front.view?.detailLevel = .fine
                t = CFAbsoluteTimeGetCurrent()
                _ = ViewGraphicsBuilder(model: m, view: front).build()
                elevMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
            }
            print(String(format: "BENCH VIS furniture %@: {3D} Fine scene cold %.1f ms, tris %d; Front elevation Fine %.1f ms", name, sceneMs, scene.triangleCount, elevMs))
        }
    }

    @Test func courtyardHouse() throws { try report("courtyard", CourtyardHouse.make()) }
    @Test func stress20k() throws { try report("stress", CourtyardHouse.stress(count: 20_000)) }
}
