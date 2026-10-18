import Foundation
import Testing
@testable import ArcusGeometry

@Suite struct MeshBuilderTests {
    @Test func extrudedBox() {
        let m = MeshBuilder.extrude(Profile2(outer: rect(0, 0, 4, 3)), bottom: 0, top: 2.5)
        #expect(approx(m.signedVolume, 30, 1e-9))
        #expect(isWatertight(m))
        #expect(m.normals.count == m.positions.count)
        #expect(m.featureEdges.count == 2 * 12)
        #expect(approx(m.surfaceArea, 2 * 12 + 14 * 2.5, 1e-9))
    }

    @Test func extrusionWithHoleAndReversedHeights() {
        let p = Profile2(outer: rect(0, 0, 10, 10), holes: [rect(2, 2, 4, 4), rect(6, 6, 8, 9)])
        let m = MeshBuilder.extrude(p, bottom: 3, top: 1)
        #expect(approx(m.signedVolume, p.area * 2, 1e-9))
        #expect(isWatertight(m))
        #expect(approx(m.bounds.min.z, 1) && approx(m.bounds.max.z, 3))
    }

    @Test func extrusionOutwardNormals() {
        let m = MeshBuilder.extrude(Profile2(outer: rect(0, 0, 1, 1)), bottom: 0, top: 1)
        let c = Vec3(0.5, 0.5, 0.5)
        for t in stride(from: 0, to: m.indices.count, by: 3) {
            let a = m.positions[Int(m.indices[t])], b = m.positions[Int(m.indices[t + 1])], d = m.positions[Int(m.indices[t + 2])]
            let n = (b - a).cross(d - a)
            #expect(n.dot((a + b + d) / 3 - c) > 0)
            #expect(n.normalized.dot(m.normals[Int(m.indices[t])]) > 0.999)
        }
    }

    @Test func cylinderVolumeAndCreaseEdges() {
        let n = 24
        let m = MeshBuilder.cylinder(center: Vec2(5, 5), radius: 0.5, z0: 0, z1: 3, segments: n)
        let polyArea = Double(n) / 2 * 0.25 * sin(2 * .pi / Double(n))
        #expect(approx(m.signedVolume, polyArea * 3, 1e-9))
        #expect(isWatertight(m))
        // Only the two cap outlines: facet edges are below the crease angle.
        #expect(m.featureEdges.count == 2 * 2 * n)
        let coarse = MeshBuilder.cylinder(center: .zero, radius: 1, z0: 0, z1: 1, segments: 6)
        #expect(coarse.featureEdges.count == 2 * (2 * 6 + 6))
    }

    @Test func extrudeInFrameWithNegativeDepth() {
        let frame = Transform3.frame(origin: Vec3(1, 2, 3), xAxis: .unitX, yAxis: .unitZ) // local Z = -Y world
        let m = MeshBuilder.extrude(Profile2(outer: rect(0, 0, 2, 1)), frame: frame, depth: -0.5)
        #expect(approx(m.signedVolume, 1, 1e-9))
        #expect(isWatertight(m))
        let b = m.bounds
        #expect(approx(b.min.y, 2) && approx(b.max.y, 2.5))
        #expect(approx(b.min.z, 3) && approx(b.max.z, 4))
    }

    @Test func slopedSlab() {
        let prof = Profile2(outer: rect(0, 0, 4, 2))
        let bottom = PlaneZ(a: 0.1, b: 0, c: 0)
        let top = PlaneZ(a: 0.1, b: 0.05, c: 0.3)
        let m = MeshBuilder.slab(prof, bottom: bottom, top: top)
        // Thickness is linear, so volume = area × thickness at the centroid.
        let c = Vec2(2, 1)
        #expect(approx(m.signedVolume, 8 * (top.z(at: c) - bottom.z(at: c)), 1e-9))
        #expect(isWatertight(m))
        #expect(approx(PlaneZ.flat(2).z(at: Vec2(100, -3)), 2))
        let through = PlaneZ.through(Vec3(0, 0, 1), Vec3(1, 0, 2), Vec3(0, 1, 1))!
        #expect(approx(through.a, 1) && approx(through.b, 0) && approx(through.c, 1))
    }

    @Test func sweepHorizontalRailing() {
        let prof = rect(-0.05, -0.05, 0.05, 0.05)
        let path = [Vec3(0, 0, 1), Vec3(2, 0, 1), Vec3(2, 3, 1)]
        let m = MeshBuilder.sweep(profile: prof, along: path)
        #expect(approx(m.signedVolume, 0.01 * 5, 1e-9))
        #expect(isWatertight(m))
        // The profile's v axis is up: its top stays at z = 1.05.
        #expect(approx(m.bounds.max.z, 1.05, 1e-12))
        // u points left of travel: along +X the left side is +Y.
        #expect(approx(m.bounds.min.y, -0.05, 1e-12))
    }

    @Test func sweepSlopedStairRail() {
        let prof = rect(-0.02, -0.02, 0.02, 0.02)
        let path = [Vec3(0, 0, 0.9), Vec3(1, 0, 0.9), Vec3(4, 0, 2.9), Vec3(5, 0, 2.9)]
        let m = MeshBuilder.sweep(profile: prof, along: path)
        let centerline = 1 + (9.0 + 4).squareRoot() + 1
        #expect(approx(m.signedVolume, 0.0016 * centerline, 1e-9))
        #expect(isWatertight(m))
    }

    @Test func revolveFullAndPartial() {
        let n = 64
        let cyl = MeshBuilder.revolve(profile: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 2), Vec2(0, 2)], around: Vec3(3, 3, 0), segments: n)
        #expect(approx(cyl.signedVolume, Double(n) / 2 * sin(2 * .pi / Double(n)) * 2, 1e-9))
        #expect(isWatertight(cyl))
        let k = 16
        let part = MeshBuilder.revolve(profile: [Vec2(1, 0), Vec2(2, 0), Vec2(2, 1), Vec2(1, 1)], around: .zero, segments: k, angle: .pi / 2)
        #expect(approx(part.signedVolume, Double(k) * 0.5 * sin(.pi / 2 / Double(k)) * 3, 1e-9))
        #expect(isWatertight(part))
        let negative = MeshBuilder.revolve(profile: [Vec2(1, 0), Vec2(2, 0), Vec2(2, 1), Vec2(1, 1)], around: .zero, segments: k, angle: -.pi / 2)
        #expect(approx(negative.signedVolume, part.signedVolume, 1e-9))
        #expect(isWatertight(negative))
        #expect(negative.bounds.max.y <= 1e-9)
    }

    @Test func degenerateInputsGiveEmptyMeshes() {
        #expect(MeshBuilder.extrude(Profile2(outer: Polygon2([.zero, .unitX])), bottom: 0, top: 1).isEmpty)
        #expect(MeshBuilder.extrude(Profile2(outer: rect(0, 0, 1, 1)), bottom: 1, top: 1).isEmpty)
        #expect(MeshBuilder.sweep(profile: rect(0, 0, 1, 1), along: [.zero]).isEmpty)
        #expect(MeshBuilder.cylinder(center: .zero, radius: 0, z0: 0, z1: 1).isEmpty)
    }

    @Test func largeCoordinateExtrusion() {
        let p = Profile2(outer: rect(10_000, 10_000, 10_004, 10_003))
        let m = MeshBuilder.extrude(p, bottom: 0, top: 3)
        // Volume via divergence theorem loses digits far from the origin; shift first.
        let local = m.transformed(.translation(Vec3(-10_000, -10_000, 0)))
        #expect(approx(local.signedVolume, 36, 1e-6))
    }
}

@Suite struct MeshSectionTests {
    @Test func boxSectionIsCCWLoop() {
        let m = Mesh.box(Box3(min: Vec3(0, 0, 0), max: Vec3(4, 3, 2)))
        let loops = MeshSection.section(m, plane: .horizontal(z: 1))
        #expect(loops.count == 1)
        #expect(loops[0].isCounterClockwise)
        #expect(approx(loops[0].area, 12))
        #expect(loops[0].count == 4)
    }

    @Test func sectionWithHole() {
        let p = Profile2(outer: rect(0, 0, 10, 10), holes: [rect(3, 3, 5, 5)])
        let m = MeshBuilder.extrude(p, bottom: 0, top: 3)
        let loops = MeshSection.section(m, plane: .horizontal(z: 1.5))
        #expect(loops.count == 2)
        #expect(loops.filter(\.isCounterClockwise).count == 1)
        #expect(approx(loops.reduce(0) { $0 + $1.signedArea }, 96))
    }

    @Test func planeThroughVerticesIsDeterministic() {
        let m = Mesh.box(Box3(min: .zero, max: Vec3(1, 1, 1)))
        // At the top face: on-plane vertices count as positive, sides cross → one loop.
        let top = MeshSection.section(m, plane: .horizontal(z: 1))
        #expect(top.count == 1 && approx(top[0].area, 1))
        // At the bottom face: everything is on or above → nothing.
        #expect(MeshSection.section(m, plane: .horizontal(z: 0)).isEmpty)
        // Within tolerance of the top face snaps onto it.
        #expect(MeshSection.section(m, plane: .horizontal(z: 1 - 1e-7)).count == 1)
    }

    @Test func verticalAndInclinedSections() {
        let m = Mesh.box(Box3(min: .zero, max: Vec3(4, 2, 3)))
        let v = MeshSection.section(m, plane: Plane3(origin: Vec3(0, 1, 0), normal: .unitY, xAxis: .unitX))
        #expect(v.count == 1 && approx(v[0].area, 12))
        let incl = Plane3(origin: Vec3(2, 1, 1.5), normal: Vec3(0, -1, 1))
        let s = MeshSection.section(m, plane: incl)
        #expect(s.count == 1)
        #expect(approx(s[0].area, 4 * 2 * 2.0.squareRoot(), 1e-9))
    }

    @Test func openMeshSegmentsAndCylinder() {
        var m = Mesh()
        m.addConvexFace([Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(2, 0, 2), Vec3(0, 0, 2)], normal: -.unitY)
        let segs = MeshSection.sectionSegments(m, plane: .horizontal(z: 1))
        #expect(segs.count == 2)
        #expect(approx(segs.reduce(0) { $0 + $1.length }, 2))
        #expect(MeshSection.section(m, plane: .horizontal(z: 1)).isEmpty)
        let cyl = MeshBuilder.cylinder(center: Vec2(10_000, 10_000), radius: 1, z0: 0, z1: 2, segments: 32)
        let loops = MeshSection.section(cyl, plane: .horizontal(z: 0.5))
        #expect(loops.count == 1 && loops[0].count == 32)
    }

    @Test func clipKeepsBelow() {
        let m = Mesh.box(Box3(min: .zero, max: Vec3(2, 2, 4)))
        let c = MeshClip.clip(m, keepingBelow: .horizontal(z: 1.5))
        #expect(approx(c.bounds.max.z, 1.5))
        #expect(approx(c.surfaceArea, 4 + 4 * 2 * 1.5, 1e-9))
        #expect(c.normals.count == c.positions.count)
        // Feature edges: bottom outline, side-face bottoms and clipped verticals.
        #expect(c.featureEdges.count == 2 * 16) // Mesh.box stores each edge once per face
        let all = MeshClip.clip(m, keepingBelow: .horizontal(z: 10))
        #expect(all.triangleCount == m.triangleCount)
        #expect(MeshClip.clip(m, keepingBelow: .horizontal(z: -1)).triangleCount == 0)
    }
}
