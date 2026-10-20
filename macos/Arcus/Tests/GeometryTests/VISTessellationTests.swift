import Foundation
import Testing
@testable import ArcusGeometry

// VIS: chord-tolerance tessellation by detail level, curve refinement of stored points, smooth normals with sharp
// creases, silhouette candidates and the clean-up of Boolean results.

@Suite("VIS tessellation and smooth shading")
struct VISTessellationTests {
    /// Largest distance between the chords of a tessellated circle and the circle.
    static func chordError(radius r: Double, segments n: Int) -> Double { r * (1 - cos(.pi / Double(n))) }

    @Test func segmentsFollowTheDetailLevel() {
        let r = 0.75 * 0.0254 // a 1 1/2" round leg
        let c = TessellationQuality.coarse.fullCircleSegments(radius: r)
        let m = TessellationQuality.medium.fullCircleSegments(radius: r)
        let f = TessellationQuality.fine.fullCircleSegments(radius: r)
        #expect(c < m && m < f)
        #expect(f >= 72, "Fine: at most 5° a segment")
        #expect(Self.chordError(radius: r, segments: f) <= 0.0002, "Fine: chord within 0.2 mm")
        #expect(Self.chordError(radius: r, segments: m) <= 0.0005)
        #expect(Self.chordError(radius: r, segments: c) <= 0.002)
    }

    @Test func largeArcsKeepTheChordToleranceUpToTheCap() {
        let r = 0.6 // a round table top
        let f = TessellationQuality.fine.fullCircleSegments(radius: r)
        #expect(Self.chordError(radius: r, segments: f) <= 0.0002 + 1e-12)
        #expect(TessellationQuality.fine.fullCircleSegments(radius: 50) == TessellationQuality.fine.maxSegments, "huge arcs are capped")
        #expect(TessellationQuality.fine.segments(radius: r, sweep: .pi / 2) * 4 >= f, "a quarter arc gets a quarter of the circle")
    }

    @Test func arcTessellationKeepsEndsExact() {
        let a = Arc2(center: Vec2(1, 2), radius: 0.3, startAngle: 0.2, sweep: 1.1)
        let pts = a.tessellate(quality: .fine)
        #expect(pts.first!.isAlmostEqual(a.start) && pts.last!.isAlmostEqual(a.end))
        for p in pts { #expect(abs(p.distance(to: a.center) - 0.3) < 1e-12) }
    }

    @Test func refinementRoundsStoredCurvesAndKeepsCorners() {
        // A rounded rectangle written with 6 points a corner (15° steps), as the furniture forms write it.
        var loop: [Vec2] = []
        let r = 0.02, hw = 0.2, hd = 0.1
        for (c, a0) in [(Vec2(hw - r, -hd + r), -Double.pi / 2), (Vec2(hw - r, hd - r), 0), (Vec2(-hw + r, hd - r), Double.pi / 2), (Vec2(-hw + r, -hd + r), Double.pi)] {
            for k in 0...6 { loop.append(c + Vec2.fromAngle(a0 + Double.pi / 2 * Double(k) / 6, length: r)) }
        }
        let fine = CurveRefinement.refine(loop, closed: true, quality: .fine)
        let coarse = CurveRefinement.refine(loop, closed: true, quality: .coarse)
        #expect(fine.count > loop.count * 2, "Fine adds points along the arcs")
        #expect(coarse.count == loop.count, "15° steps are already within Coarse")
        for p in loop { #expect(fine.contains { $0.isAlmostEqual(p) }, "every stored point is kept") }
        // New points lie on the corner circles.
        let centres = [Vec2(hw - r, -hd + r), Vec2(hw - r, hd - r), Vec2(-hw + r, hd - r), Vec2(-hw + r, -hd + r)]
        for p in fine where !loop.contains(where: { $0.isAlmostEqual(p) }) {
            #expect(centres.contains { abs($0.distance(to: p) - r) < 1e-9 }, "\(p) is on a corner arc")
        }
        // The straight sides stay single segments.
        #expect(!fine.contains { abs($0.y) < hd - r - 1e-6 && abs(abs($0.x) - hw) > 1e-6 && abs($0.y) > 1e-9 && abs(abs($0.y) - hd) > 1e-6 })
    }

    @Test func refinementLeavesPolygonsAlone() {
        let octagon = (0..<8).map { Vec2.fromAngle(Double($0) * .pi / 4, length: 0.1) } // a deliberate octagon (45° turns)
        #expect(CurveRefinement.refine(octagon, closed: true, quality: .fine).count == 8)
        let rect = [Vec2(0, 0), Vec2(1, 0), Vec2(1, 0.5), Vec2(0, 0.5)]
        #expect(CurveRefinement.refine(rect, closed: true, quality: .fine) == rect)
    }

    static func cylinder(_ n: Int) -> Mesh {
        let pts = (0..<n).map { Vec2.fromAngle(Double($0) / Double(n) * 2 * .pi, length: 0.02) }
        return MeshBuilder.extrude(Profile2(outer: Polygon2(pts)), bottom: 0, top: 0.3)
    }

    @Test func cylindersShadeSmoothAndKeepSharpRims() {
        let s = Self.cylinder(72).smoothShaded()
        // Side normals are radial (smooth), cap normals stay vertical (the rim is a real edge).
        var radial = 0, vertical = 0
        for (p, n) in zip(s.mesh.positions, s.mesh.normals) {
            if abs(n.z) > 0.999 { vertical += 1; continue }
            let rad = Vec3(p.x, p.y, 0).normalized
            #expect(n.dot(rad) > 0.9999, "side normal points out from the axis")
            radial += 1
        }
        #expect(radial > 0 && vertical > 0)
        #expect(s.silhouetteCount == 72, "one silhouette candidate per seam along the side")
        #expect(s.mesh.featureEdges.count / 2 == 144, "only the two rims are feature edges")
        #expect(abs(s.mesh.signedVolume - Self.cylinder(72).signedVolume) < 1e-12)
    }

    @Test func boxesStayFlat() {
        let box = Mesh.box(Box3(min: Vec3(0, 0, 0), max: Vec3(1, 2, 3)))
        let s = box.smoothShaded()
        #expect(s.silhouetteCount == 0)
        #expect(s.mesh.positions.count == box.positions.count, "no smooth seams: the mesh is kept as it is")
        #expect(s.mesh.normals == box.normals)
    }

    @Test func chamfersAndCoarseFacetsFollowTheCrease() {
        // 45° between faces (an octagonal prism): sharp; 10° (36 sides): smooth.
        #expect(Self.cylinder(8).smoothShaded().silhouetteCount == 0)
        #expect(Self.cylinder(36).smoothShaded().silhouetteCount == 36)
    }

    @Test func booleanCleanUpDropsLinesInsideSmoothSurfaces() {
        // Two coplanar triangles with a feature edge between them, and a real 90° edge.
        var m = Mesh()
        m.positions = [Vec3(0, 0, 0), Vec3(1, 0, 0), Vec3(1, 1, 0), Vec3(0, 1, 0), Vec3(1, 0, -1), Vec3(1, 1, -1)]
        m.normals = Array(repeating: .unitZ, count: 6)
        m.indices = [0, 1, 2, 0, 2, 3, 1, 4, 5, 1, 5, 2]
        m.featureEdges = [0, 2, 1, 2]
        let cleaned = MeshSmoothing.droppingSmoothEdges(m)
        #expect(cleaned.featureEdges == [1, 2], "the diagonal goes, the fold stays")
    }

    @Test func tJunctionsAreClosed() {
        // A big triangle whose edge carries the corner of two small ones.
        var m = Mesh()
        m.positions = [Vec3(0, 0, 0), Vec3(2, 0, 0), Vec3(1, 1, 0), Vec3(1, 0, 0), Vec3(1, -1, 0)]
        m.normals = Array(repeating: .unitZ, count: 5)
        m.indices = [0, 1, 2, 0, 4, 3, 3, 4, 1]
        let fixed = MeshSmoothing.fixingTJunctions(m)
        #expect(fixed.indices.count > m.indices.count)
        let area = { (mm: Mesh) -> Double in mm.surfaceArea }
        #expect(abs(area(fixed) - area(m)) < 1e-12, "same surface, split")
    }
}
