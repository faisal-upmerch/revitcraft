import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusViewport3D

// FMG2: Explode Parts in the live 3D view: the scene draws each part moved by its explode offset.

@Suite("FMG2 exploded 3D scene")
struct FMG2SceneTests {
    @Test func explodedViewsDrawThePartsMoved() throws {
        let m = try #require(FurnitureSamples.bookcaseModel())
        let view = try #require(m.views.first { $0.name == "{3D}" })
        let before = Dictionary(SceneBuilder.build(model: m, view: view).elements.map { ($0.id, $0.bounds) }, uniquingKeysWith: { a, _ in a })
        let tx = TransactionContext(model: m, name: "Explode")
        try FurnitureExplode.set(view.id, on: true, distance: 0.1, in: tx)
        let e = try tx.commit().model
        let offsets = FurnitureExplode.offsets(e, view: e[view.id]!)
        #expect(!offsets.isEmpty)
        let after = SceneBuilder.build(model: e, view: e[view.id]!).elements
        for el in after {
            guard let b = before[el.id] else { continue }
            let o = offsets[el.id] ?? Vec3(0, 0, 0)
            #expect((el.bounds.min - b.min - o).length < 1e-9, "\(el.id): moved by its offset")
        }
    }
}
