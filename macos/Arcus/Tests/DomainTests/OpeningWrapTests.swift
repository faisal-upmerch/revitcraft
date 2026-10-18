import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Wall openings, shafts and wrapping")
struct OpeningWrapTests {
    // MARK: Wall openings

    @Test func wallOpeningReducesAreaByWidthTimesHeight() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!, op: ElementID!
        try Fx.commit(&m) { tx in w = Fx.wall(tx, ids, .zero, Vec2(10, 0)) }
        let before = QuantityEngine.quantities(for: m[w]!, in: m)
        #expect(Fx.approx(before.area ?? 0, 40))
        try Fx.commit(&m) { tx in
            op = tx.create(.wallOpenings, data: .opening(.wall(WallOpeningData(start: 2, end: 3.5, bottom: 1, top: 3))), levelID: ids.levels[0], hostID: w)
        }
        let after = QuantityEngine.quantities(for: m[w]!, in: m)
        #expect(Fx.approx(after.area ?? 0, 40 - 1.5 * 2, 1e-9))
        #expect(Fx.approx(after.volume ?? 0, (40 - 3) * 0.2, 1e-9))
        #expect(Fx.approx(abs(WallGeometry.solid(m[w]!, m).signedVolume), (40 - 3) * 0.2, 1e-6))
        let o = try #require(WallGeometry.openings(m[w]!, m).first)
        #expect(o.insertID == op && Fx.approx(o.s0, 2) && Fx.approx(o.z1, 3))
        // Parameters edit the opening relative to its host; the geometry follows.
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("opening.width"), to: .double(2), on: op, in: tx) }
        #expect(Fx.approx(QuantityEngine.quantities(for: m[w]!, in: m).area ?? 0, 40 - 2 * 2, 1e-9))
        // Moving the wall carries the opening; deleting the wall deletes it.
        try Fx.commit(&m) { tx in try ElementOperationsShim.move([w], by: Vec2(0, 3), tx) }
        #expect(Fx.approx(WallGeometry.openings(m[w]!, m).first?.s0 ?? -1, 2))
        try Fx.commit(&m) { tx in tx.delete(w) }
        #expect(m[op] == nil)
    }

    @Test func wallOpeningShowsInPlanAndElevation() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!, low: ElementID!, high: ElementID!
        try Fx.commit(&m) { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(10, 0))
            low = tx.create(.wallOpenings, data: .opening(.wall(WallOpeningData(start: 1, end: 2, bottom: 0.5, top: 2))), levelID: ids.levels[0], hostID: w)
            high = tx.create(.wallOpenings, data: .opening(.wall(WallOpeningData(start: 5, end: 6, bottom: 2, top: 2.2))), levelID: ids.levels[0], hostID: w)
        }
        let plan = m[ids.planViews[ids.levels[0]]!]!
        let g = ViewGraphicsBuilder(model: m, view: plan).build()
        // The plan cut (1.2 m) passes through the low opening: the wall splits in two, and the opening is selectable.
        #expect(g.items.first { $0.elementID == w }?.hitPolygons.count == 2)
        #expect(g.items.contains { $0.elementID == low && !$0.hitPolygons.isEmpty })
        // The high opening is above the cut: drawn with overhead lines.
        let hi = try #require(g.items.first { $0.elementID == high })
        #expect(hi.primitives.contains { if case .polyline(_, _, let st) = $0 { return st.pattern == .overhead }; return false })
        let south = m.views.first { $0.name == "South" }!
        let eg = ViewGraphicsBuilder(model: m, view: south).build()
        #expect(eg.items.contains { $0.elementID == low && $0.hitPolygons.first.map { Fx.approx($0.area, 1.5) } == true })
    }

    // MARK: Shafts

    @Test func shaftSpanningThreeLevelsCutsEachSlabInRangeOnly() throws {
        var (m, ids) = Fx.template()
        var floors: [ElementID] = [], outside: ElementID!, shaft: ElementID!, l4: ElementID!
        try Fx.commit(&m) { tx in
            l4 = tx.create(.levels, name: "Level 4", data: .level(LevelData(elevation: 12)))
            for lv in ids.levels + [l4] {
                floors.append(tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))),
                                        typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: lv))
            }
            outside = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(20, 0), max: Vec2(30, 8))))),
                                typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[1])
            // From 0.5 m below Level 2 up to Level 4: cuts the Level 2, Roof (8 m) and Level 4 floors.
            shaft = tx.create(.shaftOpenings, data: .opening(.shaft(ShaftOpeningData(boundary: Sketch(rect: Rect2(min: Vec2(2, 2), max: Vec2(4, 5))),
                                                                                    baseOffset: -0.5, topLevelID: l4))), levelID: ids.levels[1])
        }
        let area = { (id: ElementID) in QuantityEngine.quantities(for: m[id]!, in: m).area ?? 0 }
        #expect(Fx.approx(area(floors[0]), 80), "the floor below the shaft's base is not cut")
        for f in floors.dropFirst() { #expect(Fx.approx(area(f), 80 - 6, 1e-6)) }
        #expect(Fx.approx(area(outside), 80), "slabs outside the sketch are not cut")
        #expect(ShaftCuts.cutElements(by: m[shaft]!, m).map(\.id) == Array(floors.dropFirst()))
        // 3D: the cut slab's volume drops by the hole.
        let v = abs(ElementMeshes.parts(m[floors[1]]!, m, detail: .coarse).reduce(0) { $0 + $1.mesh.signedVolume })
        #expect(Fx.approx(v, (80 - 6) * 0.2, 1e-6))
        // Moving the shaft updates the cut through the dependency graph.
        let key = GeometryCache.key(m[floors[1]]!, m, detail: .fine)
        try Fx.commit(&m) { tx in tx.update(shaft) { ElementTransform.apply(.translation(Vec2(1, 0)), to: &$0) } }
        #expect(GeometryCache.key(m[floors[1]]!, m, detail: .fine) != key)
        // Plans in range draw the shaft (outline + symbolic lines) and the slab with its hole.
        let plan = m[ids.planViews[ids.levels[1]]!]!
        let g = ViewGraphicsBuilder(model: m, view: plan).build()
        let item = try #require(g.items.first { $0.elementID == shaft })
        #expect(item.primitives.count == 3)
        let slab = try #require(g.items.first { $0.elementID == floors[1] })
        #expect(slab.primitives.filter { if case .polyline(_, true, _) = $0 { return true }; return false }.count == 2, "outline and hole")
        let ground = m[ids.planViews[ids.levels[0]]!]!
        #expect(!ViewGraphicsBuilder(model: m, view: ground).build().items.contains { $0.elementID == shaft })
    }

    @Test func shaftCutsRoofsInRange() throws {
        var (m, ids) = Fx.template()
        var roof: ElementID!
        try Fx.commit(&m) { tx in
            roof = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))), edgeSlopes: [nil, nil, nil, nil])),
                             typeID: ids.roofTypes["Flat Roof - Concrete"], levelID: ids.levels[1])
            tx.create(.shaftOpenings, data: .opening(.shaft(ShaftOpeningData(boundary: Sketch(rect: Rect2(min: Vec2(2, 2), max: Vec2(4, 4))), unconnectedHeight: 6))),
                      levelID: ids.levels[0])
        }
        #expect(ShaftCuts.externalCuts(for: m[roof]!, m).count == 1)
        let v = abs(RoofGeometry.meshParts(m[roof]!, m).reduce(0) { $0 + $1.mesh.signedVolume })
        let t = RoofGeometry.thickness(m[roof]!, m)
        #expect(Fx.approx(v, (80 - 4) * t, 1e-6))
    }

    // MARK: Wrapping

    /// Brick-on-CMU walls with the brick (exterior) and plaster (interior) layers set to wrap.
    func wrappingBox(inserts: WrappingPreference, ends: WrappingPreference) throws -> (BIMModel, ElementID, ProjectTemplates.Ids) {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in
            tx.update(ids.wallTypes[Fx.brick]!) { t in
                var a = t.typeData!.assembly!
                a.layers[0].wraps = true
                a.layers[a.layers.count - 1].wraps = true
                a.wrappingAtInserts = inserts
                a.wrappingAtEnds = ends
                t.typeData!.assembly = a
            }
            w = Fx.wall(tx, ids, .zero, Vec2(10, 0), type: Fx.brick)
            Fx.window(tx, ids, host: w, at: Vec2(5, 0), sill: 0.9)
        }
        return (m, w, ids)
    }

    /// Layer boundary segments square to a straight wall along the x axis.
    func returnSegments(_ m: BIMModel, _ w: ElementID, z: Double) -> [Segment2] {
        let f = WallGeometry.frame(m[w]!, m)!
        return WallGeometry.layerBoundaryCurves(m[w]!, f, atZ: z, m).compactMap(\.asSegment).filter { abs($0.direction.x) < 1e-9 && $0.length > 1e-6 }
    }

    @Test func wrappingAtInsertsAddsReturnsAtTheJambs() throws {
        let (plain, pw, _) = try wrappingBox(inserts: .doNotWrap, ends: .doNotWrap)
        #expect(returnSegments(plain, pw, z: 1.5).isEmpty)
        let (m, w, _) = try wrappingBox(inserts: .exterior, ends: .doNotWrap)
        let ops = WallGeometry.openings(m[w]!, m)
        #expect(ops.count == 1)
        let returns = WallGeometry.wrapReturns(m[w]!, atZ: 1.5, m)
        #expect(returns.count == 2)
        #expect(returns.allSatisfy { $0.fromExterior && Fx.approx($0.depths.last!, 0.102) })
        let across = returnSegments(m, w, z: 1.5)
        // One return per jamb, one brick thickness back from the opening.
        #expect(across.count == 2)
        let xs = across.map(\.start.x).sorted()
        #expect(Fx.approx(xs[0], ops[0].s0 - 0.102, 1e-9) && Fx.approx(xs[1], ops[0].s1 + 0.102, 1e-9))
        // The return runs from the brick's inner face across to the core's far face.
        let f = WallGeometry.frame(m[w]!, m)!
        let a = f.assembly
        #expect(Fx.approx(across[0].length, a.exteriorToCore + a.coreThickness - 0.102, 1e-9))
        // Fine plans fill the returned leg with the brick's pattern.
        #expect(WallGeometry.wrapRegions(m[w]!, f, atZ: 1.5, m).count == 2)
        // Below the window (no opening at that height) nothing wraps.
        #expect(returnSegments(m, w, z: 0.5).isEmpty)
    }

    @Test func wrappingAtEndsCoversFreeEndsFromBothSides() throws {
        let (m, w, _) = try wrappingBox(inserts: .doNotWrap, ends: .both)
        let returns = WallGeometry.wrapReturns(m[w]!, atZ: 0.5, m)
        #expect(returns.count == 4) // both faces at both free ends
        let f = WallGeometry.frame(m[w]!, m)!
        let a = f.assembly
        let ext = returns.first { $0.fromExterior }!
        #expect(Fx.approx(ext.reach, a.exteriorToCore + a.coreThickness / 2, 1e-9), "with Both, each side wraps to the core centre")
        #expect(returnSegments(m, w, z: 0.5).count == 4)
    }
}
