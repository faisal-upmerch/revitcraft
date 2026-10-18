import Foundation
import Testing
@testable import ArcusGeometry

@Suite struct HiddenLineTests {
    let northElevation = ViewProjection.elevation(lookingAt: Vec2(0, 1), origin: Vec3(0, -10, 0), near: 0, far: 100)

    func lengths(_ edges: [HLREdge]) -> [Int: Double] {
        var r: [Int: Double] = [:]
        for e in edges { r[e.tag, default: 0] += e.segment.length }
        return r
    }

    @Test func projectionFrames() {
        let v = northElevation
        #expect(approx(v.forward, Vec3(0, 1, 0)))
        #expect(approx(v.right, Vec3(1, 0, 0)))
        let p = v.project(Vec3(2, 5, 3))
        #expect(approx(p.uv, Vec2(2, 3)) && approx(p.depth, 15))
        let top = ViewProjection.topDown(z: 10, depth: 20)
        #expect(approx(top.forward, Vec3(0, 0, -1)))
        let q = top.project(Vec3(4, 5, 7))
        #expect(approx(q.uv, Vec2(4, 5)) && approx(q.depth, 3))
    }

    @Test func frontBoxHidesPartOfBackBox() {
        let back = Mesh.box(Box3(min: Vec3(0, 5, 0), max: Vec3(4, 6, 3)))
        let front = Mesh.box(Box3(min: Vec3(1, 0, 0), max: Vec3(2, 1, 1)))
        let edges = HiddenLineRenderer.render([HLRInput(tag: 1, mesh: back), HLRInput(tag: 2, mesh: front)], projection: northElevation)
        let l = lengths(edges)
        // Back box outline 14 m, minus the 1 m of its bottom edge behind the front box.
        #expect(approx(l[1] ?? 0, 13, 1e-6))
        #expect(approx(l[2] ?? 0, 4, 1e-6))
        // Bottom edge of the back box is split into two visible pieces.
        let bottom = edges.filter { $0.tag == 1 && approx($0.segment.start.y, 0) && approx($0.segment.end.y, 0) }
        #expect(bottom.count == 2)
        #expect(edges.allSatisfy { $0.tag != 1 || approx($0.depth, 15) })
    }

    @Test func partialOcclusionWithExactLengths() {
        // A tall back wall partially hidden by a lower, offset front box.
        let back = Mesh.box(Box3(min: Vec3(0, 5, 0), max: Vec3(6, 6, 4)))
        let front = Mesh.box(Box3(min: Vec3(-1, 0, 0), max: Vec3(2.5, 1, 2)))
        let l = lengths(HiddenLineRenderer.render([HLRInput(tag: 1, mesh: back), HLRInput(tag: 2, mesh: front)], projection: northElevation))
        // Back: top 6 + right 4 + left (4 - 2) + bottom (6 - 2.5) = 15.5.
        #expect(approx(l[1] ?? 0, 15.5, 1e-6))
        #expect(approx(l[2] ?? 0, 2 * 3.5 + 2 * 2, 1e-6))
    }

    @Test func intersectingBoxesOutline() {
        let a = Mesh.box(Box3(min: Vec3(0, 0, 0), max: Vec3(4, 4, 2)))
        let b = Mesh.box(Box3(min: Vec3(2, 2, 0), max: Vec3(6, 6, 2)))
        let edges = HiddenLineRenderer.render([HLRInput(tag: 1, mesh: a), HLRInput(tag: 2, mesh: b)], projection: northElevation)
        let l = lengths(edges)
        #expect(approx(l[1] ?? 0, 12, 1e-6))
        #expect(approx(l[2] ?? 0, 6, 1e-6))
        // No visible piece of B lies left of x = 4.
        #expect(edges.filter { $0.tag == 2 }.allSatisfy { min($0.segment.start.x, $0.segment.end.x) >= 4 - 1e-9 })
    }

    @Test func nearPlaneCutsAway() {
        let box = Mesh.box(Box3(min: Vec3(0, 0, 0), max: Vec3(4, 4, 3)))
        let section = ViewProjection.elevation(lookingAt: Vec2(0, 1), origin: Vec3(0, 2, 0), near: 0, far: 50)
        let l = lengths(HiddenLineRenderer.render([HLRInput(tag: 7, mesh: box)], projection: section))
        // Only the back face outline remains (the front half is removed by the cut).
        #expect(approx(l[7] ?? 0, 14, 1e-6))
        // Far plane excludes everything behind it.
        let shallow = ViewProjection.elevation(lookingAt: Vec2(0, 1), origin: Vec3(0, -10, 0), near: 0, far: 5)
        #expect(HiddenLineRenderer.render([HLRInput(tag: 7, mesh: box)], projection: shallow).isEmpty)
    }

    @Test func cylinderSilhouettes() {
        let cyl = MeshBuilder.cylinder(center: Vec2(0, 0), radius: 1, z0: 0, z1: 2, segments: 48)
        let edges = HiddenLineRenderer.render([HLRInput(tag: 3, mesh: cyl)], projection: northElevation)
        let sil = edges.filter(\.isSilhouette)
        #expect(sil.count == 2)
        #expect(sil.allSatisfy { approx($0.segment.length, 2, 1e-9) && approx(abs($0.segment.start.x), 1, 1e-9) })
        // The bottom and top outlines project to two 2 m lines (front halves visible).
        let horizontal = edges.filter { !$0.isSilhouette }.reduce(0) { $0 + $1.segment.length }
        #expect(approx(horizontal, 4, 1e-6))
    }

    @Test func planViewAndClipRect() {
        let low = Mesh.box(Box3(min: Vec3(0, 0, 0), max: Vec3(10, 10, 1)))
        let high = Mesh.box(Box3(min: Vec3(4, 4, 0), max: Vec3(6, 6, 3)))
        let view = ViewProjection.topDown(z: 5, depth: 10)
        let l = lengths(HiddenLineRenderer.render([HLRInput(tag: 1, mesh: low), HLRInput(tag: 2, mesh: high)], projection: view))
        #expect(approx(l[1] ?? 0, 40, 1e-6))
        #expect(approx(l[2] ?? 0, 8, 1e-6))
        let clipped = HiddenLineRenderer.render([HLRInput(tag: 1, mesh: low)], projection: view,
                                                clip: Rect2(min: Vec2(-1, -1), max: Vec2(5, 5)))
        #expect(approx(clipped.reduce(0) { $0 + $1.segment.length }, 10, 1e-9))
    }

    @Test func cancellationReturnsEmpty() {
        let m = Mesh.box(Box3(min: .zero, max: Vec3(1, 1, 1)))
        #expect(HiddenLineRenderer.render([HLRInput(tag: 0, mesh: m)], projection: northElevation, isCancelled: { true }).isEmpty)
    }

    @Test func deterministicOutput() {
        var inputs: [HLRInput] = []
        for i in 0..<20 {
            let x = Double(i % 5) * 1.5, y = Double(i / 5) * 1.5
            inputs.append(HLRInput(tag: i, mesh: Mesh.box(Box3(min: Vec3(x, y, 0), max: Vec3(x + 1, y + 1, 1 + Double(i % 3))))))
        }
        let v = ViewProjection.elevation(lookingAt: Vec2(1, 1), origin: Vec3(-10, -10, 0), near: 0, far: 100)
        let a = HiddenLineRenderer.render(inputs, projection: v)
        let b = HiddenLineRenderer.render(inputs, projection: v)
        #expect(a == b)
        #expect(!a.isEmpty)
    }

    @Test func fiftyThousandTriangles() {
        var inputs: [HLRInput] = []
        var state: UInt64 = 7
        func rnd() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        for i in 0..<4200 {
            let x = Double(i % 70) * 1.2, y = Double(i / 70) * 1.2
            let h = 0.5 + rnd() * 4
            inputs.append(HLRInput(tag: i, mesh: Mesh.box(Box3(min: Vec3(x, y, 0), max: Vec3(x + 0.8 + rnd() * 0.3, y + 0.8, h)))))
        }
        #expect(inputs.reduce(0) { $0 + $1.mesh.triangleCount } == 50_400)
        let v = ViewProjection.elevation(lookingAt: Vec2(0.3, 1), origin: Vec3(0, -20, 0), near: 0, far: 500)
        let clock = ContinuousClock()
        let t0 = clock.now
        let edges = HiddenLineRenderer.render(inputs, projection: v)
        let dt = clock.now - t0
        #expect(!edges.isEmpty)
        // Generous bound for unoptimized debug builds; release is far faster.
        #expect(dt < .seconds(20))
        print("HLR 50k triangles: \(dt), \(edges.count) visible pieces")
    }
}
