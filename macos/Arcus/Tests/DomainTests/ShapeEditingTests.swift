import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Floor and roof shape editing")
struct ShapeEditingTests {
    static let square = SlabRoofTests.loop([Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)])

    func floor(_ points: [ShapePoint]? = nil) throws -> (BIMModel, ElementID) {
        var (m, ids) = Fx.template()
        var f: ElementID!
        try Fx.commit(&m) { tx in
            var s = SlabData(boundary: Sketch(loops: [Self.square]))
            s.shapePoints = points
            f = tx.create(.floors, data: .slab(s), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        return (m, f)
    }

    @Test func loweredPointMakesTopNonPlanarKeepsAreaAndReducesVolume() throws {
        let (flat, fid) = try floor()
        let (shaped, sid) = try floor([ShapePoint(position: Vec2(5, 5), offset: -0.02)])
        let q0 = QuantityEngine.quantities(for: flat[fid]!, in: flat)
        let q1 = QuantityEngine.quantities(for: shaped[sid]!, in: shaped)
        #expect(Fx.approx(q1.area!, q0.area!))
        #expect(Fx.approx(q0.volume!, 100 * 0.2))
        // A pyramid of depth 20 mm over the whole 10 × 10 square: V = 100 × 0.02 / 3.
        #expect(abs((q0.volume! - q1.volume!) - 100 * 0.02 / 3) < 1e-6)
        let e = shaped[sid]!
        #expect(Fx.approx(SlabGeometry.topZ(e, at: Vec2(5, 5), shaped)!, -0.02))
        #expect(Fx.approx(SlabGeometry.topZ(e, at: Vec2(0, 0), shaped)!, 0))
        #expect(Fx.approx(SlabGeometry.topZ(e, at: Vec2(2.5, 5), shaped)!, -0.01))
        // The top is no longer one plane: its vertices are not coplanar.
        let mesh = SlabGeometry.mesh(e, shaped)
        let topZs = Set(mesh.positions.filter { $0.z > -0.1 }.map { ($0.z * 1e6).rounded() })
        #expect(topZs.count == 2)
        // Closed solid with the bottom unchanged.
        #expect(abs(mesh.signedVolume - q1.volume!) < 1e-9)
        #expect(mesh.bounds.min.z == -0.2)
    }

    @Test func vertexOffsetsTiltTheEdge() throws {
        let (m, id) = try floor([ShapePoint(position: Vec2(10, 10), offset: 0.1)])
        let e = m[id]!
        #expect(Fx.approx(SlabGeometry.topZ(e, at: Vec2(10, 10), m)!, 0.1))
        let q = QuantityEngine.quantities(for: e, in: m)
        #expect(q.volume! > 100 * 0.2)
    }

    @Test func resetShapeRestoresTheOriginal() throws {
        var (m, id) = try floor([ShapePoint(position: Vec2(5, 5), offset: -0.05), ShapePoint(position: Vec2(0, 0), offset: 0.03)])
        let (flat, fid) = try floor()
        try Fx.commit(&m) { tx in tx.update(id) { ShapeEditing.setPoints([], on: &$0) } }
        #expect(m[id]!.slab!.shapePoints == nil)
        let q = QuantityEngine.quantities(for: m[id]!, in: m)
        #expect(Fx.approx(q.volume!, QuantityEngine.quantities(for: flat[fid]!, in: flat).volume!))
        #expect(Fx.approx(SlabGeometry.topZ(m[id]!, at: Vec2(5, 5), m)!, 0))
    }

    @Test func pointsOutsideOrOnEdgesAreIgnored() throws {
        let prof = Profile2(outer: Polygon2([Vec2(0, 0), Vec2(10, 0), Vec2(10, 10), Vec2(0, 10)]))
        #expect(!ShapeEditing.isPlaceable(Vec2(20, 5), in: prof))
        #expect(!ShapeEditing.isPlaceable(Vec2(5, 0.001), in: prof))
        #expect(ShapeEditing.isPlaceable(Vec2(10, 10), in: prof))
        let s = try #require(ShapeEditing.surface(prof, points: [ShapePoint(position: Vec2(20, 5), offset: 1), ShapePoint(position: Vec2(3, 4), offset: -0.01)]))
        #expect(s.points.count == 5)
        let area = stride(from: 0, to: s.triangles.count, by: 3).reduce(0.0) { acc, t in
            acc + (s.points[s.triangles[t + 1]] - s.points[s.triangles[t]]).cross(s.points[s.triangles[t + 2]] - s.points[s.triangles[t]]) / 2
        }
        #expect(Fx.approx(area, 100))
    }

    @Test func flatRoofDrainageFalls() throws {
        var (m, ids) = Fx.template()
        var r: ElementID!
        try Fx.commit(&m) { tx in
            var data = RoofData(footprint: Sketch(loops: [Self.square]), edgeSlopes: [nil, nil, nil, nil])
            data.shapePoints = [ShapePoint(position: Vec2(5, 5), offset: -0.05)]
            r = tx.create(.roofs, data: .roof(data), typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
        }
        let e = m[r]!
        #expect(ShapeEditing.canEdit(e))
        let base = RoofGeometry.baseZ(e, m)
        #expect(Fx.approx(RoofGeometry.topZ(e, at: Vec2(5, 5), m)!, base - 0.05))
        let q = QuantityEngine.quantities(for: e, in: m)
        let t = RoofGeometry.thickness(e, m)
        #expect(abs(q.volume! - (100 * t - 100 * 0.05 / 3)) < 1e-6)
    }
}
