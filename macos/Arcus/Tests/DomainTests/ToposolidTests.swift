import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// BL-SITE (ARCUS-070): toposolids — creation, layers, sub-divisions, split/merge, simplify, excavate, conversion from
/// toposurfaces, contours, sections and parameters.
@Suite("Toposolids")
struct ToposolidTests {
    /// A 11 × 11 grid of points (1 m apart) on the plane z = 0.1·x.
    static let slope: [Vec3] = (0...10).flatMap { i in (0...10).map { j in Vec3(Double(i), Double(j), 0.1 * Double(i)) } }

    static func volume(_ parts: [MeshPart]) -> Double { parts.reduce(0) { $0 + $1.mesh.signedVolume } }

    /// A sketched 20 × 10 toposolid at elevation 0 with the default type.
    static func flat() throws -> (BIMModel, ElementID) {
        var (m, _) = Fx.template()
        var id: ElementID!
        try Fx.commit(&m) { tx in id = try ToposolidOperations.create(outline: .rectangle(Rect2(min: .zero, max: Vec2(20, 10))), elevation: 0, in: tx) }
        return (m, id)
    }

    static func sloped() throws -> (BIMModel, ElementID) {
        var (m, _) = Fx.template()
        var id: ElementID!
        try Fx.commit(&m) { tx in id = try ToposolidOperations.create(points: slope, in: tx).0 }
        return (m, id)
    }

    // MARK: Types and layers

    @Test func sketchedToposolidHasLayeredClosedSolids() throws {
        let (m, id) = try Self.flat()
        let e = try #require(m[id])
        #expect(e.isToposolid && !e.isLegacyToposurface && e.category == .topography)
        let type = try #require(m[e.typeID]?.typeData)
        #expect(type.systemFamily == .toposolid && type.assembly?.layers.count == 2 && type.assembly?.layers[1].isVariable == true)
        #expect(ToposolidTypes.types(m, subdivision: true).count == 1, "the default sub-division type is created with it")
        let parts = ElementMeshes.parts(e, m)
        #expect(parts.count == 2, "one closed solid per layer")
        #expect(parts.allSatisfy { $0.mesh.signedVolume > 0 }, "outward-facing closed solids")
        #expect(Fx.approx(parts[0].mesh.signedVolume, 20 * 10 * 0.3, 1e-6), "300 mm topsoil")
        #expect(Fx.approx(parts[1].mesh.signedVolume, 20 * 10 * 1.2, 1e-6), "1200 mm earth")
        #expect(parts[0].materialID != parts[1].materialID)
        let b = ElementMeshes.bounds(e, m)
        #expect(Fx.approx(b.min.z, -1.5) && Fx.approx(b.max.z, 0) && Fx.approx(b.max.x, 20))
    }

    @Test func variableLayerReachesAFlatBase() throws {
        let (m, id) = try Self.sloped()
        let parts = ElementMeshes.parts(m[id]!, m)
        #expect(Fx.approx(parts[0].mesh.signedVolume, 100 * 0.3, 1e-6), "the topsoil follows the terrain")
        // Earth: from (0.1x − 0.3) down to −1.5 over 10 × 10 → 120 + 0.1·∫x = 170.
        #expect(Fx.approx(parts[1].mesh.signedVolume, 170, 1e-6))
        #expect(Fx.approx(ElementMeshes.bounds(m[id]!, m).min.z, -1.5), "the base is flat, 1.5 m below the lowest point")
    }

    @Test func withoutAVariableLayerEveryLayerFollowsTheTerrain() throws {
        var (m, id) = try Self.sloped()
        let t = try #require(m[id]?.typeID)
        try Fx.commit(&m) { tx in tx.update(t) { for i in 0..<2 { $0.typeData?.assembly?.layers[i].isVariable = false } } }
        let parts = ElementMeshes.parts(m[id]!, m)
        #expect(Fx.approx(Self.volume(parts), 100 * 1.5, 1e-6))
        #expect(Fx.approx(ElementMeshes.bounds(m[id]!, m).min.z, -1.5) && Fx.approx(ElementMeshes.bounds(m[id]!, m).max.z, 1.0))
        #expect(Fx.approx(QuantityEngine.quantities(for: m[id]!, in: m).volume ?? 0, 150, 1e-6), "the type change regenerates the solid")
    }

    @Test func pointsOutsideASketchedOutlineAreClipped() throws {
        var (m, _) = Fx.template()
        var id: ElementID!
        // An L-shaped outline over the sloped survey.
        let l = Polygon2([Vec2(0, 0), Vec2(10, 0), Vec2(10, 4), Vec2(4, 4), Vec2(4, 10), Vec2(0, 10)])
        try Fx.commit(&m) { tx in
            id = tx.create(.topography, name: "Toposolid", data: .topography(TopographyData(points: SiteEditing.dedupe(Self.slope + ToposolidGeometry.flatPoints(outline: l, z: 0).map { Vec3($0.xy, z: 0.1 * $0.x) }),
                                                                                            solid: ToposolidData(outline: l.points))),
                           typeID: ToposolidTypes.ensureDefaults(in: tx).solid)
        }
        let s = ToposolidGeometry.topSurface(m[id]!, m)
        var area = 0.0
        for i in stride(from: 0, to: s.triangles.count, by: 3) {
            area += (s.points[s.triangles[i + 1]].xy - s.points[s.triangles[i]].xy).cross(s.points[s.triangles[i + 2]].xy - s.points[s.triangles[i]].xy) / 2
        }
        #expect(Fx.approx(area, l.area, 1e-6), "the surface covers exactly the L outline")
        let contours = TopographyGeometry.contours(m[id]!, interval: 0.25)
        #expect(!contours.isEmpty && contours.allSatisfy { l.contains($0.segment.midpoint) }, "contours stay inside the outline")
    }

    // MARK: Sub-Divide

    @Test func subDivisionFollowsItsHost() throws {
        var (m, id) = try Self.sloped()
        var sub: ElementID!
        try Fx.commit(&m) { tx in sub = try ToposolidOperations.subdivide(id, boundary: .rectangle(Rect2(min: Vec2(2, 2), max: Vec2(6, 6))), in: tx) }
        let s = try #require(m[sub])
        #expect(s.isToposolidSubdivision && s.hostID == id)
        let parts = ElementMeshes.parts(s, m)
        #expect(parts.count == 2, "paving and gravel layers")
        #expect(Fx.approx(Self.volume(parts), 16 * 0.1, 1e-6))
        let top = ElementMeshes.bounds(s, m).max.z
        #expect(Fx.approx(top, 0.6 + 0.1 + ToposolidGeometry.subdivisionLift, 1e-6), "the top follows the host at x = 6")
        // Raising the host raises the sub-division (its geometry depends on the host).
        try Fx.commit(&m) { tx in tx.update(id) { $0.topography?.points = Self.slope.map { Vec3($0.xy, z: $0.z + 1) } } }
        #expect(Fx.approx(ElementMeshes.bounds(m[sub]!, m).max.z, top + 1, 1e-6))
        #expect(DependencyGraph.inputs(of: m[sub]!, m).contains(id))
        // Negative height goes into the host.
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("toposolid.subdivisionHeight"), to: .double(-0.2), on: sub, in: tx) }
        #expect(Fx.approx(Self.volume(ElementMeshes.parts(m[sub]!, m)), 16 * 0.2, 1e-6))
        #expect(ElementMeshes.bounds(m[sub]!, m).max.z < top + 1)
        #expect(throws: (any Error).self) { try Fx.commit(&m) { tx in try Parameters.set(ParameterID("toposolid.subdivisionHeight"), to: .double(0), on: sub, in: tx) } }
    }

    @Test func subDivisionMustOverlapItsHost() throws {
        var (m, id) = try Self.flat()
        #expect(throws: (any Error).self) {
            try Fx.commit(&m) { tx in try ToposolidOperations.subdivide(id, boundary: .rectangle(Rect2(min: Vec2(30, 0), max: Vec2(35, 5))), in: tx) }
        }
    }

    // MARK: Split, merge

    @Test func splitAndMergeKeepTheVolume() throws {
        var (m, id) = try Self.flat()
        var sub: ElementID!
        try Fx.commit(&m) { tx in sub = try ToposolidOperations.subdivide(id, boundary: .rectangle(Rect2(min: Vec2(14, 2), max: Vec2(18, 6))), in: tx) }
        let before = QuantityEngine.quantities(for: m[id]!, in: m).volume ?? 0
        var parts: [ElementID] = []
        try Fx.commit(&m) { tx in parts = try SiteOperations.split(id, along: [Vec2(8, -1), Vec2(8, 11)], in: tx) }
        #expect(parts.count == 2)
        let a = ToposolidGeometry.outline(m[parts[0]]!).area, b = ToposolidGeometry.outline(m[parts[1]]!).area
        #expect(Fx.approx(a + b, 200, 1e-6) && Fx.approx(min(a, b), 80, 1e-6))
        let after = parts.reduce(0.0) { $0 + (QuantityEngine.quantities(for: m[$1]!, in: m).volume ?? 0) }
        #expect(Fx.approx(before, after, 1e-6))
        let east = parts.first { ToposolidGeometry.outline(m[$0]!).bounds.min.x > 7 }!
        #expect(m[sub]?.hostID == east, "the sub-division follows the part that holds it")
        #expect(m[parts[1]]?.typeID == m[parts[0]]?.typeID)
        var merged: ElementID!
        try Fx.commit(&m) { tx in merged = try SiteOperations.merge(parts, in: tx) }
        #expect(Fx.approx(ToposolidGeometry.outline(m[merged]!).area, 200, 1e-6))
        #expect(Fx.approx(QuantityEngine.quantities(for: m[merged]!, in: m).volume ?? 0, before, 1e-6))
        #expect(m[sub]?.hostID == merged)
    }

    @Test func toposolidsDoNotMergeWithToposurfaces() throws {
        var (m, id) = try Self.flat()
        var topo: ElementID!
        try Fx.commit(&m) { tx in topo = try SiteOperations.createToposurface(Self.slope, in: tx).0 }
        #expect(throws: (any Error).self) { try Fx.commit(&m) { tx in try SiteOperations.merge([id, topo], in: tx) } }
    }

    // MARK: Simplify and shape editing

    @Test func simplifyDropsPointsThatDoNotShapeTheSurface() throws {
        var pts = Self.slope
        pts[60].z += 0.8 // a bump at (5, 5)
        let kept = ToposolidGeometry.simplify(pts, outline: nil, tolerance: 0.01)
        #expect(kept.count < 12, "a plane needs its outline, plus the bump")
        #expect(kept.contains(pts[60]))
        for p in pts { #expect(abs(SiteEditing.elevation(kept, at: p.xy) - p.z) <= 0.01 + 1e-9) }
        var (m, id) = try Self.sloped()
        var counts = (before: 0, after: 0)
        try Fx.commit(&m) { tx in counts = try ToposolidOperations.simplify(id, tolerance: 0.001, in: tx) }
        #expect(counts.before == 121 && counts.after < 30 && m[id]?.topography?.points.count == counts.after)
        #expect(Fx.approx(QuantityEngine.quantities(for: m[id]!, in: m).volume ?? 0, 200, 1e-6), "the simplified surface is the same plane")
    }

    @Test func splitLineAddsPointsAtSurfaceElevation() {
        let out = ToposolidOperations.addSplitLine(Self.slope, from: Vec2(0.5, 0.5), to: Vec2(9.5, 9.2))
        #expect(out.count > Self.slope.count + 2)
        for p in out { #expect(Fx.approx(p.z, 0.1 * p.x, 1e-9)) }
    }

    // MARK: Excavate

    @Test func excavateByAFloorRecordsCutAndLowersTheSurface() throws {
        var (m, id) = try Self.flat()
        let ids = ProjectTemplates.make(.architectural, units: .metric).1
        var floor: ElementID!
        try Fx.commit(&m) { tx in
            var s = SlabData(boundary: Sketch(rect: Rect2(min: Vec2(4, 3), max: Vec2(8, 7))), offset: -0.8)
            s.structural = false
            floor = tx.create(.floors, data: .slab(s), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
        }
        let bottom = ElementMeshes.bounds(m[floor]!, m).min.z
        #expect(Fx.approx(bottom, -1.0, 1e-6))
        var r = (cut: 0.0, fill: 0.0)
        try Fx.commit(&m) { tx in r = try ToposolidOperations.excavate(id, by: [floor], in: tx) }
        #expect(abs(r.cut - 16) < 0.5 && r.fill < 1e-9, "4 × 4 m dug 1 m deep")
        let s = ToposolidGeometry.topSurface(m[id]!, m)
        #expect(Fx.approx(SiteEditing.elevation(s.points, at: Vec2(6, 5), triangles: s.triangles), -1.0, 1e-6))
        #expect(Fx.approx(SiteEditing.elevation(s.points, at: Vec2(15, 5), triangles: s.triangles), 0, 1e-6), "ground away from the pit is unchanged")
        #expect(Parameters.value(ParameterID("toposolid.cut"), of: m[id]!, m)?.doubleValue.map { abs($0 - r.cut) < 1e-9 } == true)
        #expect(throws: (any Error).self) { try Fx.commit(&m) { tx in try ToposolidOperations.excavate(id, by: [id], in: tx) } }
    }

    // MARK: Legacy conversion

    @Test func generateToposolidReplacesAToposurfaceAndItsSubRegions() throws {
        var (m, _) = Fx.template()
        var topo: ElementID!, sub: ElementID!
        let grass = m.elements(.materials).first!.id
        try Fx.commit(&m) { tx in
            topo = try SiteOperations.createToposurface(Self.slope, name: "Existing", in: tx).0
            sub = try SiteOperations.createSubregion(on: topo, boundary: .rectangle(Rect2(min: Vec2(1, 1), max: Vec2(3, 3))), materialID: grass, in: tx)
        }
        var solid: ElementID!
        try Fx.commit(&m) { tx in solid = try ToposolidOperations.generate(from: topo, in: tx) }
        #expect(m[topo] == nil && m[sub] == nil)
        let e = try #require(m[solid])
        #expect(e.isToposolid && e.name == "Existing" && e.topography?.points.count == 121)
        let subs = m.hosted(by: solid).filter(\.isToposolidSubdivision)
        #expect(subs.count == 1 && subs[0].topography?.materialID == grass)
        #expect(ElementMeshes.parts(subs[0], m).first?.materialID == grass, "the sub-region's material becomes the top layer's")
        #expect(throws: (any Error).self) { try Fx.commit(&m) { tx in try ToposolidOperations.generate(from: solid, in: tx) } }
    }

    // MARK: Views, parameters, transforms

    @Test func sectionCutsEveryLayerWithItsOwnFill() throws {
        var (m, id) = try Self.flat()
        var sid: ElementID!
        try Fx.commit(&m) { tx in
            var v = ViewData(kind: .section)
            v.planeOrigin = Vec3(10, 5, 0)
            v.viewDirection = Vec2(0, 1)
            v.farClip = 20
            sid = tx.create(.views, name: "Site Section", data: .view(v))
        }
        let g = ViewGraphicsBuilder(model: m, view: m[sid]!).build()
        let cut = try #require(g.items.first { $0.elementID == id && $0.layer == .cut })
        let fills = cut.primitives.compactMap { p -> GFill? in if case .fill(_, let f) = p { return f }; return nil }
        #expect(fills.count == 2, "topsoil and earth are cut separately")
        #expect(cut.hitPolygons.count == 2)
        let b = cut.bounds
        #expect(Fx.approx(b.min.y, -1.5, 1e-6) && Fx.approx(b.max.y, 0, 1e-6) && Fx.approx(b.width, 20, 1e-6))
        // Plan: contours and the outline.
        let plan = m.views.first { $0.view?.kind == .floorPlan }!
        #expect(ViewGraphicsBuilder(model: m, view: plan).build().items.contains { $0.elementID == id })
    }

    @Test func parametersAndSchedulesSeeVolumeAndThickness() throws {
        let (m, id) = try Self.flat()
        let e = m[id]!
        #expect(Parameters.value(ParameterID("q.volume"), of: e, m)?.doubleValue.map { Fx.approx($0, 300, 1e-6) } == true)
        #expect(Parameters.value(ParameterID("q.thickness"), of: e, m)?.doubleValue.map { Fx.approx($0, 1.5) } == true)
        #expect(Parameters.value(ParameterID("typeName"), of: e, m)?.textValue == "Toposolid 1500mm")
        let names = Parameters.instanceEntries(e, m).map(\.name)
        #expect(names.contains("Cut") && names.contains("Fill") && names.contains("Volume") && !names.contains("Height"))
        #expect(Category.schedulable.contains(.topography))
        let q = QuantityEngine.quantities(for: e, in: m)
        #expect(q.materials.count == 2 && Fx.approx(q.materials.reduce(0) { $0 + $1.volume }, 300, 1e-6))
    }

    @Test func movingAToposolidMovesItsOutline() throws {
        var (m, id) = try Self.flat()
        try Fx.commit(&m) { tx in try ElementOperations.transform([id], by: .translation(Vec2(5, 0)), in: tx, viewID: nil) }
        #expect(Fx.approx(ToposolidGeometry.outline(m[id]!).bounds.min.x, 5) && Fx.approx(ElementMeshes.bounds(m[id]!, m).max.x, 25))
    }

    @Test func legacyToolsRedirectToToposolidTools() throws {
        var (m, id) = try Self.flat()
        #expect(throws: (any Error).self) {
            try Fx.commit(&m) { tx in try SiteOperations.createSubregion(on: id, boundary: .rectangle(Rect2(min: Vec2(1, 1), max: Vec2(3, 3))), in: tx) }
        }
        let plan = try #require(CreateSimilar.plan(for: m[id]!, m))
        #expect(plan.command == .toposolid && plan.types[.topography] == m[id]?.typeID)
    }

    @Test func imperialDefaults() throws {
        var (m, _) = Fx.template(units: .imperial)
        var id: ElementID!
        try Fx.commit(&m) { tx in id = try ToposolidOperations.create(outline: .rectangle(Rect2(min: .zero, max: Vec2(10, 10))), elevation: 0, in: tx) }
        #expect(m[m[id]!.typeID]?.name == "Toposolid 5'-0\"")
        #expect(Fx.approx(ToposolidGeometry.thickness(m[id]!, m), 5 * 0.3048, 1e-9))
    }
}
