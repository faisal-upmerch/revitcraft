import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// W2-DWG: Massing & Site (point files, site settings, split/merge/sub-region/graded region, contour labels, parking
/// layouts) and hosted profiles (wall sweeps, slab edges, soffits).
@Suite("Site tools and hosted profiles")
struct SiteToolsTests {
    /// A 10 × 10 grid of points (1 m apart) on the plane z = 0.1·x.
    static let slope: [Vec3] = (0...10).flatMap { i in (0...10).map { j in Vec3(Double(i), Double(j), 0.1 * Double(i)) } }

    // MARK: Point files

    @Test func pointFileFormats() {
        let text = """
        # survey 2026
        X,Y,Z
        0,0,10
        10;0;11
        10\t10\t12
        P4 0 10 13.5
        5 1 2 3
        oops, 1, x
        """
        let r = SitePointFile.parse(text)
        #expect(r.points == [Vec3(0, 0, 10), Vec3(10, 0, 11), Vec3(10, 10, 12), Vec3(0, 10, 13.5), Vec3(1, 2, 3)])
        #expect(r.skippedLines == [8])
        let feet = SitePointFile.parse("1 2 3\r\n4 5 6\r\n", scale: 0.3048)
        #expect(feet.points.count == 2 && Fx.approx(feet.points[1].z, 6 * 0.3048))
        #expect(SitePointFile.parse("").points.isEmpty)
    }

    // MARK: Settings

    @Test func siteSettingsDefaultsAndStorage() throws {
        var (m, _) = Fx.template()
        let s0 = SiteSettings(m)
        #expect(s0.contourInterval == 0.5 && s0.primaryEvery == 5 && s0.showContours)
        #expect(s0.isPrimary(2.5) && s0.isPrimary(-5) && !s0.isPrimary(3.0))
        #expect(SiteSettings.defaults(for: .imperial).contourInterval == 0.3048)
        let pi = try #require(m.projectInfoElement?.id)
        try Fx.commit(&m) { tx in tx.update(pi) { SiteSettings(contourInterval: 0.25, primaryEvery: 4, showContours: false).write(to: &$0) } }
        let s1 = SiteSettings(m)
        #expect(s1.contourInterval == 0.25 && s1.primaryEvery == 4 && !s1.showContours && s1.isPrimary(1.0))
    }

    // MARK: Surface editing

    @Test func surfaceElevation() throws {
        #expect(Fx.approx(try #require(SiteEditing.surfaceZ(Self.slope, at: Vec2(3.3, 4.7))), 0.33))
        #expect(SiteEditing.surfaceZ(Self.slope, at: Vec2(20, 20)) == nil)
        #expect(Fx.approx(SiteEditing.elevation(Self.slope, at: Vec2(20, 5)), 1.0), "outside: nearest point")
    }

    @Test func splitAlongALine() throws {
        let (left, right) = try #require(SiteEditing.split(Self.slope, along: [Vec2(4.5, 2), Vec2(4.5, 8)]))
        // The split line is extended across the whole surface; x < 4.5 is on the left of a line pointing +y.
        #expect(left.allSatisfy { $0.x <= 4.5 + 1e-9 } && right.allSatisfy { $0.x >= 4.5 - 1e-9 })
        let cut = left.filter { abs($0.x - 4.5) < 1e-9 }
        #expect(cut.count >= 11 && cut.allSatisfy { Fx.approx($0.z, 0.45) }, "both halves share the cut points at the surface's elevation")
        #expect(right.filter { abs($0.x - 4.5) < 1e-9 }.count == cut.count)
        #expect(SiteEditing.split(Self.slope, along: [Vec2(20, 0), Vec2(20, 1)]) == nil, "a line beside the surface doesn't split it")
    }

    @Test func mergeAndThin() {
        let a = [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(0, 1, 0)]
        let b = [Vec3(1, 0, 5), Vec3(2, 2, 1), Vec3(0.0004, 0, 9)]
        #expect(SiteEditing.merge(a, b) == a + [Vec3(2, 2, 1)])
        let dense = (0..<100).flatMap { i in (0..<100).map { j in Vec3(Double(i) * 0.1, Double(j) * 0.1, 0) } }
        let thin = SiteEditing.thin(dense, maxPoints: 500)
        #expect(thin.count <= 500 && thin.count > 100)
    }

    @Test func operationsOnAModel() throws {
        var (m, ids) = Fx.template()
        var topo: ElementID!, sub: ElementID!, halves: [ElementID] = []
        let grass = try #require(ids.materials.values.first)
        try Fx.commit(&m) { tx in
            topo = try SiteOperations.createToposurface(Self.slope, name: "Existing Ground", in: tx).0
            sub = try SiteOperations.createSubregion(on: topo, boundary: .rectangle(Rect2(min: Vec2(6, 1), max: Vec2(9, 4))), materialID: grass, in: tx)
        }
        // Sub-region: hosted, has the material, and its mesh stays inside the boundary, just above the host.
        let s = try #require(m[sub])
        #expect(s.hostID == topo && s.topography?.materialID == grass)
        let mesh = TopographyGeometry.mesh(s)
        #expect(!mesh.indices.isEmpty)
        #expect(mesh.positions.allSatisfy { $0.x >= 6 - 1e-9 && $0.x <= 9 + 1e-9 && $0.y >= 1 - 1e-9 && $0.y <= 4 + 1e-9 })
        #expect(mesh.positions.allSatisfy { Fx.approx($0.z, 0.1 * $0.x + SiteEditing.subregionLift, 1e-6) })
        #expect(Fx.approx(mesh.surfaceArea, 9 * sqrt(1.01), 1e-3))
        #expect(ElementMeshes.parts(s, m).first?.materialID == grass)
        #expect(throws: SiteOperations.SiteError.self) {
            try Fx.commit(&m) { tx in try SiteOperations.createSubregion(on: sub, boundary: .rectangle(Rect2(min: .zero, max: Vec2(1, 1))), in: tx) }
        }

        // Split: the sub-region follows the half it lies in.
        try Fx.commit(&m) { tx in halves = try SiteOperations.split(topo, along: [Vec2(5, 0), Vec2(5, 10)], in: tx) }
        #expect(halves.count == 2)
        let east = try #require(halves.first { id in m[id]!.topography!.points.allSatisfy { $0.x >= 5 - 1e-9 } })
        #expect(m[sub]?.hostID == east)

        // Merge back; the sub-region moves to the result.
        var merged: ElementID!
        try Fx.commit(&m) { tx in merged = try SiteOperations.merge(halves, in: tx) }
        #expect(m.elements(.topography).filter { $0.topography?.boundary == nil }.count == 1)
        #expect(m[sub]?.hostID == merged)
        #expect(m[merged]!.topography!.points.count == Self.slope.count, "the cut points at x = 5 coincide with grid points and are merged")

        // Deleting the host deletes its sub-regions.
        try Fx.commit(&m) { tx in tx.delete(merged) }
        #expect(m[sub] == nil)
    }

    @Test func gradedRegionUsesPhases() throws {
        var (m, ids) = Fx.template()
        var topo: ElementID!, graded: ElementID!
        try Fx.commit(&m) { tx in topo = try SiteOperations.createToposurface(Self.slope, in: tx).0 }
        #expect(m[topo]?.phaseCreated == ids.phases.last)
        try Fx.commit(&m) { tx in graded = try SiteOperations.gradedRegion(from: topo, phase: nil, in: tx) }
        #expect(m[topo]?.phaseCreated == ids.phases[0] && m[topo]?.phaseDemolished == ids.phases[1])
        #expect(m[graded]?.phaseCreated == ids.phases[1] && m[graded]?.topography?.points == Self.slope)
        #expect(throws: SiteOperations.SiteError.self) { try Fx.commit(&m) { tx in _ = try SiteOperations.gradedRegion(from: topo, phase: nil, in: tx) } }
        #expect(throws: SiteOperations.SiteError.self) { try Fx.commit(&m) { tx in _ = try SiteOperations.gradedRegion(from: graded, phase: ids.phases[0], in: tx) } }
    }

    @Test func contourLabelsAlongALine() throws {
        let e = Element(id: ElementID(1), category: .topography, data: .topography(TopographyData(points: Self.slope)))
        let s = SiteSettings(contourInterval: 0.25, primaryEvery: 2)
        let labels = SiteEditing.contourLabels(e, settings: s, line: Segment2(Vec2(0.5, 5), Vec2(9.5, 5)))
        #expect(labels.map(\.elevation) == [0.25, 0.5, 0.75])
        #expect(labels.allSatisfy { abs(abs($0.rotation) - .pi / 2) < 1e-6 }, "contours run north–south on this slope")
        #expect(labels.map(\.isPrimary) == [false, true, false])
        #expect(SiteEditing.contourLabels(e, settings: s, line: Segment2(Vec2(0.5, 5), Vec2(9.5, 5)), primaryOnly: true).count == 1)
        #expect(Fx.approx(labels[0].position, Vec2(2.5, 5)))
    }

    // MARK: Parking

    @Test func parkingLayoutMetricNinetyDegrees() {
        let p = ParkingLayout.Parameters.defaults(for: .metric)
        #expect(p.stallWidth == 2.5 && p.stallDepth == 5.0 && p.aisleWidth == 6.0 && p.angle == 90)
        let r = ParkingLayout.generate(boundary: .rectangle(Rect2(min: .zero, max: Vec2(60, 30))), p)
        // Rows at y 0–5 (up), 11–16 (down), 16–21 (up, the next bay's aisle 21–27); a fourth row doesn't fit.
        #expect(r.rows == 3)
        #expect(r.stallCount == 72)
        #expect(r.stripes.count == 75)
        #expect(r.stripes.allSatisfy { Fx.approx($0.length, 5.0) })
        #expect(r.wheelStops.isEmpty)
    }

    @Test func parkingLayoutImperialDefaultsAndWheelStops() {
        let p = ParkingLayout.Parameters.defaults(for: .imperial)
        #expect(Fx.approx(p.stallWidth, 9 * 0.3048) && Fx.approx(p.stallDepth, 18 * 0.3048) && Fx.approx(p.aisleWidth, 24 * 0.3048))
        var q = p
        q.wheelStops = true
        let r = ParkingLayout.generate(boundary: .rectangle(Rect2(min: .zero, max: Vec2(30, 20))), q)
        #expect(r.stallCount > 0 && r.wheelStops.count == r.stallCount)
    }

    @Test(arguments: [60.0, 45.0])
    func angledParkingStaysInside(_ angle: Double) {
        let boundary = Polygon2([Vec2(0, 0), Vec2(50, 0), Vec2(50, 25), Vec2(10, 30), Vec2(0, 20)])
        let p = ParkingLayout.Parameters.defaults(for: .metric, angle: angle)
        let r = ParkingLayout.generate(boundary: boundary, p)
        #expect(r.stallCount > 10)
        #expect(r.stalls.allSatisfy { $0.allSatisfy { boundary.contains($0) } })
        #expect(r.stripes.allSatisfy { Fx.approx($0.length, p.stallDepth, 1e-6) })
        // Stripes meet the aisle at the chosen angle (the layout's x axis is the longest edge, here along +x).
        #expect(r.stripes.allSatisfy { Fx.approx(abs($0.direction.dot(.unitX)), cos(angle * .pi / 180), 1e-6) })
        #expect(p.aisleWidth < 6.0)
    }

    @Test func parkingLayoutTooSmall() {
        let r = ParkingLayout.generate(boundary: .rectangle(Rect2(min: .zero, max: Vec2(2, 2))), .defaults(for: .metric))
        #expect(r.stallCount == 0 && r.stripes.isEmpty)
    }

    // MARK: Hosted profiles

    @Test func wallSweepSlabEdgeAndSoffitGeometry() throws {
        var (m, ids) = Fx.template()
        var wall: ElementID!, floor: ElementID!, roof: ElementID!
        try Fx.commit(&m) { tx in
            wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(10, 0))
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            let a = 30.0 * .pi / 180
            roof = tx.create(.roofs, data: .roof(RoofData(footprint: Sketch(rect: Rect2(min: Vec2(-0.5, -0.5), max: Vec2(10.5, 8.5))), edgeSlopes: [a, a, a, a], overhang: 0.5)),
                             typeID: ids.roofTypes["Tiled Roof - Timber"], levelID: ids.levels[1])
        }
        #expect(HostedProfiles.parts(m[wall]!, m).isEmpty && HostedProfiles.parts(m[floor]!, m).isEmpty && HostedProfiles.parts(m[roof]!, m).isEmpty)

        // Parameters switch the profiles on and size them.
        try Fx.commit(&m) { tx in
            try Parameters.set(ParameterID("wall.sweep"), to: .bool(true), on: wall, in: tx)
            try Parameters.set(ParameterID("wall.sweepHeight"), to: .double(1.0), on: wall, in: tx)
            try Parameters.set(ParameterID("wall.sweepProjection"), to: .double(0.05), on: wall, in: tx)
            try Parameters.set(ParameterID("slab.edge"), to: .bool(true), on: floor, in: tx)
            try Parameters.set(ParameterID("slab.edgeDepth"), to: .double(0.4), on: floor, in: tx)
            try Parameters.set(ParameterID("roof.soffit"), to: .bool(true), on: roof, in: tx)
        }
        #expect(m[wall]?.wall?.sweeps?.first == WallSweep(height: 1.0, projection: 0.05))
        #expect(m[roof]?.roof?.soffit?.depth == 0.5, "defaults to the roof's overhang")

        let base = m.elevation(ofLevel: ids.levels[0])
        let sweep = try #require(HostedProfiles.parts(m[wall]!, m).first).mesh.bounds
        #expect(Fx.approx(sweep.min.z, base + 1.0) && Fx.approx(sweep.max.z, base + 1.15))
        #expect(Fx.approx(sweep.max.x - sweep.min.x, 10, 0.3))
        let wallBox = Box3(points: WallGeometry.solid(m[wall]!, m).positions)
        #expect(sweep.min.y < wallBox.min.y - 0.04 || sweep.max.y > wallBox.max.y + 0.04, "projects 50 mm beyond a face")

        let edge = try #require(HostedProfiles.parts(m[floor]!, m).first).mesh.bounds
        #expect(Fx.approx(edge.min.z, base - 0.2 - 0.4, 1e-6) && Fx.approx(edge.max.z, base - 0.2, 1e-6))
        #expect(Fx.approx(edge.min.x, 0) && Fx.approx(edge.max.x, 10))

        let soffit = try #require(HostedProfiles.parts(m[roof]!, m).first).mesh.bounds
        let eave = RoofGeometry.baseZ(m[roof]!, m) - RoofGeometry.thickness(m[roof]!, m)
        #expect(Fx.approx(soffit.max.z, eave, 1e-6) && Fx.approx(soffit.min.x, -0.5))
        // The parts are part of the element's 3D representation.
        #expect(ElementMeshes.parts(m[floor]!, m).count >= 2)

        // Invalid values are rejected; switching off removes the profile.
        #expect(throws: ParameterError.self) { try Fx.commit(&m) { tx in try Parameters.set(ParameterID("wall.sweepDepth"), to: .double(0), on: wall, in: tx) } }
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("slab.edge"), to: .bool(false), on: floor, in: tx) }
        #expect(m[floor]?.slab?.edgeProfile == nil)
    }

    @Test func profilesSurviveEncodeDecode() throws {
        var w = WallData(location: .line(Segment2(.zero, .unitX)))
        w.sweeps = [WallSweep(height: 2, side: .interior)]
        let d = try JSONDecoder().decode(WallData.self, from: JSONEncoder().encode(w))
        #expect(d.sweeps == w.sweeps)
        // Documents written before these fields existed still decode.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(TopographyData(points: [Vec3(1, 2, 3)]))) as! [String: Any]
        old.removeValue(forKey: "boundary"); old.removeValue(forKey: "materialID")
        let t = try JSONDecoder().decode(TopographyData.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(t.points == [Vec3(1, 2, 3)] && t.boundary == nil)
    }
}
