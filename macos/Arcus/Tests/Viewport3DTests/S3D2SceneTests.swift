import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusViewport3D

// S3D2: 3D views draw datums, model lines and 2D CAD as line elements (edges, no faces), following the view's
// visibility; the snap index then sees exactly what is drawn.

@Suite("3D line elements")
struct S3D2SceneTests {
    @Test func scenesCarryGridsLevelsAndReferencePlanesAsLines() throws {
        var m = BIMModel()
        let tx = TransactionContext(model: m, name: "Datums")
        let level = tx.create(.levels, name: "Level 1", data: .level(LevelData(elevation: 0)))
        _ = tx.create(.levels, name: "Level 2", data: .level(LevelData(elevation: 3.5)))
        let grid = tx.create(.grids, name: "A", data: .grid(GridData(curve: .line(Segment2(Vec2(0, 0), Vec2(10, 0))))))
        let plane = tx.create(.referencePlanes, name: "", data: .referencePlane(ReferencePlaneData(line: Segment2(Vec2(5, -4), Vec2(5, 4)))))
        m = try tx.commit().model
        let view = Element(id: ElementID(UInt64.max - 5), category: .views, name: "{3D}", data: .view(ViewData(kind: .threeD)))
        let scene = SceneBuilder.build(model: m, view: view)
        let ids = Set(scene.elements.map(\.id))
        #expect(ids.isSuperset(of: [level, grid, plane]))
        let g = try #require(scene.elements.first { $0.id == grid })
        #expect(g.isLinesOnly && g.parts[0].mesh.normals.count == g.parts[0].mesh.positions.count, "uploadable edge-only geometry")
        #expect(abs(g.bounds.min.z) < 1e-9 && abs(g.bounds.max.z - 3.5) < 1e-9, "from the lowest to the highest level")

        var hidden = ViewData(kind: .threeD)
        hidden.visibility.hiddenElements = [grid]
        hidden.visibility.hiddenCategories = [.referencePlanes]
        let v2 = Element(id: view.id, category: .views, data: .view(hidden))
        let ids2 = Set(SceneBuilder.build(model: m, view: v2).elements.map(\.id))
        #expect(!ids2.contains(grid) && !ids2.contains(plane) && ids2.contains(level))
        // Outside the section box: left out.
        var boxed = ViewData(kind: .threeD)
        boxed.sectionBoxActive = true
        boxed.sectionBox = Box3(min: Vec3(-1, -1, 3), max: Vec3(11, 1, 4))
        let ids3 = Set(SceneBuilder.build(model: m, view: Element(id: view.id, category: .views, data: .view(boxed))).elements.map(\.id))
        #expect(!ids3.contains(level) && ids3.contains(grid))
    }
}
