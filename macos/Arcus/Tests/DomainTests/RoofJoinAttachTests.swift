import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Roof by extrusion")
struct RoofExtrusionTests {
    static func l(_ a: Vec2, _ b: Vec2) -> Curve2 { .line(Segment2(a, b)) }
    /// Symmetric gable: 8 m wide, 2 m rise, extruded 10 m.
    static let gable = [l(Vec2(0, 0), Vec2(4, 2)), l(Vec2(8, 0), Vec2(4, 2))]

    @Test func closedProfileIsRejectedWithASpecificMessage() {
        let closed = Self.gable + [Self.l(Vec2(0, 0), Vec2(8, 0))]
        guard case .failure(let e) = RoofExtrusionGeometry.orderedChain(closed) else { Issue.record("expected failure"); return }
        #expect(e == .closed)
        #expect(e.description.contains("open profile"))
        let x = RoofExtrusion(origin: .zero, direction: .unitX, profile: closed, start: 0, end: 10)
        #expect(RoofExtrusionGeometry.validate(x) == .closed)
        // The transaction is refused with that message too.
        let (m, ids) = Fx.template()
        let tx = TransactionContext(model: m, name: "Roof")
        var data = RoofData(footprint: Sketch(loops: []), edgeSlopes: [])
        data.extrusion = x
        tx.create(.roofs, data: .roof(data), typeID: ids.roofTypes["Metal Roof - Insulated"], levelID: ids.levels[1])
        do { _ = try tx.commit(); Issue.record("expected rejection") } catch {
            #expect(error.message.contains("open profile"))
        }
    }

    @Test func otherProfileErrors() {
        #expect(RoofExtrusionGeometry.validate(RoofExtrusion(origin: .zero, direction: .unitX, profile: [], start: 0, end: 5)) == .empty)
        let gap = [Self.l(Vec2(0, 0), Vec2(4, 2)), Self.l(Vec2(5, 2), Vec2(8, 0))]
        #expect(RoofExtrusionGeometry.validate(RoofExtrusion(origin: .zero, direction: .unitX, profile: gap, start: 0, end: 5)) == .disconnected)
        #expect(RoofExtrusionGeometry.validate(RoofExtrusion(origin: .zero, direction: .unitX, profile: Self.gable, start: 2, end: 2)) == .noDepth)
        let crossing = [Self.l(Vec2(0, 0), Vec2(4, 2)), Self.l(Vec2(4, 2), Vec2(4, -1)), Self.l(Vec2(4, -1), Vec2(1, 2))]
        #expect(RoofExtrusionGeometry.validate(RoofExtrusion(origin: .zero, direction: .unitX, profile: crossing, start: 0, end: 5)) == .selfIntersecting)
    }

    @Test func gableExtrusionGeometryAndQuantities() throws {
        var (m, ids) = Fx.template()
        var r: ElementID!
        try Fx.commit(&m) { tx in
            var data = RoofData(footprint: Sketch(loops: []), edgeSlopes: [])
            // Reversed, unordered input: the chain is ordered left to right.
            data.extrusion = RoofExtrusion(origin: Vec2(0, 0), direction: .unitX, profile: [Self.gable[1].reversed, Self.gable[0]], start: -1, end: 9)
            r = tx.create(.roofs, data: .roof(data), typeID: ids.roofTypes["Metal Roof - Insulated"], levelID: ids.levels[1])
        }
        let e = m[r]!
        let t = RoofGeometry.thickness(e, m)
        let base = m.elevation(ofLevel: ids.levels[1])
        let mesh = RoofGeometry.meshParts(e, m).reduce(into: Mesh()) { $0.append($1.mesh) }
        // Plan extents: stations 0…8 along x, depth −1…9 along +y (the work plane's normal).
        #expect(abs(mesh.bounds.min.y - -1) < 1e-9 && abs(mesh.bounds.max.y - 9) < 1e-9)
        #expect(abs(mesh.bounds.max.z - (base + 2)) < 1e-9)
        let q = QuantityEngine.quantities(for: e, in: m)
        let slopeLen = 2 * (16.0 + 4).squareRoot()
        #expect(abs(q.area! - slopeLen * 10) < 1e-6)
        #expect(abs(abs(mesh.signedVolume) - q.volume!) < 1e-6)
        #expect(Fx.approx(RoofGeometry.topZ(e, at: Vec2(4, 3), m)!, base + 2))
        #expect(Fx.approx(RoofGeometry.topZ(e, at: Vec2(2, 3), m)!, base + 1))
        #expect(RoofGeometry.topZ(e, at: Vec2(2, 20), m) == nil)
        // Underside: perpendicular thickness on a 1:2 pitch drops t·√(1 + 0.25) vertically.
        #expect(abs(AttachmentQueries.undersideZ(e, at: Vec2(2, 3), m)! - (base + 1 - t * (1.25).squareRoot())) < 1e-6)
        #expect(Parameters.instanceEntries(e, m).contains { $0.id == ParameterID("roof.extrusionEnd") })
    }

    @Test func mirroringKeepsTheRoofOnTheSameSide() throws {
        var e = Element(id: ElementID(1), category: .roofs, data: .roof({
            var d = RoofData(footprint: Sketch(loops: []), edgeSlopes: [])
            d.extrusion = RoofExtrusion(origin: .zero, direction: .unitX, profile: Self.gable, start: 0, end: 5)
            return d
        }()))
        let before = RoofExtrusionGeometry.footprint(e)!.bounds
        // Mirror about the x axis: the plan rectangle mirrors to y ∈ −5…0.
        ElementTransform.apply(Transform2(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0), to: &e)
        let after = RoofExtrusionGeometry.footprint(e)!.bounds
        #expect(Fx.approx(after.min.y, -before.max.y) && Fx.approx(after.max.y, -before.min.y))
        #expect(Fx.approx(after.min.x, before.min.x) && Fx.approx(after.max.x, before.max.x))
    }
}

@Suite("Join geometry")
struct SolidJoinTests {
    /// A 10 × 10 × 0.2 floor on Level 1 and a 0.2 m wall crossing it that starts 0.5 m below the level.
    func floorAndWall() throws -> (BIMModel, ElementID, ElementID) {
        var (m, ids) = Fx.template()
        var f: ElementID!, w: ElementID!
        try Fx.commit(&m) { tx in
            f = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(loops: [ShapeEditingTests.square]))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            w = Fx.wall(tx, ids, Vec2(-1, 5), Vec2(11, 5)) { $0.baseOffset = -0.5 }
        }
        return (m, f, w)
    }

    @Test func floorWallJoinRemovesTheOverlapExactlyOnce() throws {
        var (m, f, w) = try floorAndWall()
        let floor0 = QuantityEngine.quantities(for: m[f]!, in: m).volume!
        let wall0 = QuantityEngine.quantities(for: m[w]!, in: m).volume!
        let wallThickness = WallGeometry.frame(m[w]!, m)!.thickness
        let overlap = 10 * wallThickness * 0.2
        #expect(Fx.approx(SolidJoins.overlapVolume(m[f]!, m[w]!, m), overlap))
        let pairs = SolidJoins.joinablePairs([f, w], m)
        #expect(pairs.count == 1 && pairs[0].cutter == w && pairs[0].cut == f)
        try Fx.commit(&m) { tx in #expect(SolidJoins.join([w, f], in: tx) == 1) }
        let floor1 = QuantityEngine.quantities(for: m[f]!, in: m)
        let wall1 = QuantityEngine.quantities(for: m[w]!, in: m).volume!
        #expect(Fx.approx(floor1.volume!, floor0 - overlap))
        #expect(Fx.approx(wall1, wall0), "the wall keeps its full volume")
        #expect(Fx.approx(floor1.volume! + wall1, floor0 + wall0 - overlap))
        #expect(Fx.approx(floor1.area!, 100 - 10 * wallThickness))
        // The floor's 3D solid agrees with its quantities.
        let mesh = ElementMeshes.parts(m[f]!, m, detail: .coarse).reduce(into: Mesh()) { $0.append($1.mesh) }
        #expect(Fx.approx(abs(mesh.signedVolume), floor1.volume!))
        // Joining again does nothing; unjoining restores the floor.
        #expect(SolidJoins.joinablePairs([f, w], m).isEmpty)
        try Fx.commit(&m) { tx in #expect(SolidJoins.unjoin([f], in: tx) == 1) }
        #expect(Fx.approx(QuantityEngine.quantities(for: m[f]!, in: m).volume!, floor0))
    }

    @Test func joinsFollowEditsAndDeletes() throws {
        var (m, f, w) = try floorAndWall()
        try Fx.commit(&m) { tx in SolidJoins.join([f, w], in: tx) }
        let key0 = GeometryCache.key(m[f]!, m, detail: .coarse)
        // Moving the wall changes the floor's cache key (the cut moves with it).
        try Fx.commit(&m) { tx in tx.update(w) { ElementTransform.apply(.translation(Vec2(0, 1)), to: &$0) } }
        #expect(GeometryCache.key(m[f]!, m, detail: .coarse) != key0)
        #expect(DependencyGraph.affected(by: [w], before: m, after: m).contains(f))
        // Deleting the wall deletes the join.
        try Fx.commit(&m) { tx in tx.delete(w) }
        #expect(SolidJoins.joins(m).isEmpty)
        #expect(ConstraintSolver.activeConstraints(m).isEmpty)
    }

    @Test func nonOverlappingOrSameKindPairsDontJoin() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!, w: ElementID!
        try Fx.commit(&m) { tx in
            a = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(loops: [ShapeEditingTests.square]))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            b = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(loops: [ShapeEditingTests.square]))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            w = Fx.wall(tx, ids, Vec2(20, 0), Vec2(30, 0))
        }
        #expect(SolidJoins.joinablePairs([a, b], m).isEmpty, "two floors")
        #expect(SolidJoins.joinablePairs([a, w], m).isEmpty, "no overlap")
    }

    @Test func roofCutByWallInSection() throws {
        var (m, ids) = Fx.template()
        var r: ElementID!, w: ElementID!
        try Fx.commit(&m) { tx in
            var data = RoofData(footprint: Sketch(loops: [ShapeEditingTests.square]), edgeSlopes: [nil, nil, nil, nil])
            data.baseOffset = 0
            r = tx.create(.roofs, data: .roof(data), typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
            w = Fx.wall(tx, ids, Vec2(5, -1), Vec2(5, 11), top: nil) { $0.unconnectedHeight = 5 }
        }
        let v0 = QuantityEngine.quantities(for: m[r]!, in: m).volume!
        try Fx.commit(&m) { tx in SolidJoins.join([r, w], in: tx) }
        let t = RoofGeometry.thickness(m[r]!, m)
        let wt = WallGeometry.frame(m[w]!, m)!.thickness
        #expect(Fx.approx(QuantityEngine.quantities(for: m[r]!, in: m).volume!, v0 - 10 * wt * t))
    }
}

@Suite("Attach walls to roofs and floors")
struct WallAttachmentTests {
    @Test func wallsBelowARoofAreOfferedAndAttach() throws {
        var (m, ids) = Fx.template()
        var walls: [ElementID] = []
        var roof: ElementID!, other: ElementID!
        try Fx.commit(&m) { tx in
            walls = Fx.boxWalls(tx, ids, w: 10, h: 8)
            // A wall on Level 2 (above the roof's underside) and one far away are not candidates.
            other = Fx.wall(tx, ids, Vec2(30, 0), Vec2(40, 0))
            let fp = SlabRoofTests.loop([Vec2(-0.5, -0.5), Vec2(10.5, -0.5), Vec2(10.5, 8.5), Vec2(-0.5, 8.5)])
            roof = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(loops: [fp]), edgeSlopes: [atan(0.5), nil, atan(0.5), nil], overhang: 0.5)),
                             typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: ids.levels[1])
        }
        let cands = WallAttachment.candidates(for: m[roof]!, m)
        #expect(Set(cands) == Set(walls))
        #expect(!cands.contains(other))
        try Fx.commit(&m) { tx in WallAttachment.attach(cands, to: roof, in: tx) }
        #expect(walls.allSatisfy { m[$0]!.wall!.attachedTopIDs == [roof] })
        #expect(WallAttachment.candidates(for: m[roof]!, m).isEmpty, "already attached")
        // The gable walls (east and west) now rise to the ridge under the roof.
        let east = m[walls[1]]!
        let ridge = RoofGeometry.ridgeHeight(m[roof]!, m)!
        let solid = WallGeometry.solid(east, m)
        #expect(solid.bounds.max.z > m.elevation(ofLevel: ids.levels[1]) + 0.5)
        #expect(solid.bounds.max.z < ridge)
    }

    @Test func wallsUnderAFloorStopAtItsUnderside() throws {
        var (m, ids) = Fx.template()
        var walls: [ElementID] = []
        var floor: ElementID!
        try Fx.commit(&m) { tx in
            walls = Fx.boxWalls(tx, ids, w: 10, h: 8)
            let fp = SlabRoofTests.loop([Vec2(0, 0), Vec2(10, 0), Vec2(10, 8), Vec2(0, 8)])
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(loops: [fp]))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[1])
        }
        #expect(Set(WallAttachment.candidates(for: m[floor]!, m)) == Set(walls))
        try Fx.commit(&m) { tx in WallAttachment.attach(walls, to: floor, in: tx) }
        let top = WallGeometry.solid(m[walls[0]]!, m).bounds.max.z
        #expect(Fx.approx(top, m.elevation(ofLevel: ids.levels[1]) - 0.2))
    }
}
