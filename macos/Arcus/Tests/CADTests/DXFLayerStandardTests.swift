import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

/// F13: DXF export with the AIA CAD layer guidelines (RevitCraft's default) or category names.
@Suite("DXF layer standards")
struct DXFLayerStandardTests {
    @Test func aiaLayersNameWallsDoorsAndTagsByHost() throws {
        var m = BIMModel()
        let tx = TransactionContext(model: m, name: "Fixture")
        let wall = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(5, 0))))))
        let door = tx.create(.doors, data: .insert(InsertData(location: Vec2(2, 0))), hostID: wall)
        let tag = tx.create(.tags, data: .tag(TagData(taggedID: door, head: Vec2(2, 1))))
        m = try tx.commit().model
        let st = GStroke(weight: 1)
        let line: [GPrimitive] = [.polyline([.zero, Vec2(1, 0)], closed: false, st)]
        let g = ViewGraphics(viewID: ElementID(99), scale: 100, items: [
            GItem(elementID: wall, category: .walls, layer: .cut, primitives: line),
            GItem(elementID: door, category: .doors, layer: .model, primitives: line),
            GItem(elementID: tag, category: .tags, layer: .annotation, primitives: line),
            GItem(elementID: nil, category: .dimensions, layer: .annotation, primitives: line),
        ], extents: Rect2(min: .zero, max: Vec2(5, 1)), crop: nil, modelRevision: 1)
        let aia = try DXFReader.read(DXFWriter.write(g, layers: .aia, model: m), fileName: "aia.dxf")
        #expect(Set(aia.layers.map(\.name)).isSuperset(of: ["A-WALL", "A-DOOR", "A-DOOR-IDEN", "A-ANNO-DIMS"]))
        let cat = try DXFReader.read(DXFWriter.write(g, layers: .category, model: m), fileName: "cat.dxf")
        #expect(Set(cat.layers.map(\.name)).isSuperset(of: ["Walls", "Doors", "Tags", "Dimensions"]))
    }
}
