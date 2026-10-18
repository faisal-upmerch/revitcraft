import Foundation
import Testing
@testable import ArcusGeometry

@Suite struct PlanarArrangementTests {
    @Test func singleSquare() {
        let arr = PlanarArrangement(segments: rectSegments(0, 0, 4, 3))
        #expect(arr.faces.count == 1)
        #expect(approx(arr.faces[0].area, 12))
        #expect(arr.faces[0].outer.isCounterClockwise)
        #expect(arr.face(containing: Vec2(1, 1)) != nil)
        #expect(arr.face(containing: Vec2(5, 1)) == nil)
        #expect(arr.face(containing: Vec2(4, 1)) == nil) // on an edge
    }

    /// 2×2 grid of rooms bounded by the faces of 0.2 m walls.
    @Test func twoByTwoRoomGridFromWallFaces() {
        let t = 0.2
        var segs: [Segment2] = []
        // Four rooms, each bounded by wall faces (room interiors 4×3).
        for (x0, y0) in [(0.0, 0.0), (4.0 + t, 0.0), (0.0, 3.0 + t), (4.0 + t, 3.0 + t)] {
            segs += rectSegments(x0, y0, x0 + 4, y0 + 3)
        }
        // Outer wall face.
        segs += rectSegments(-t, -t, 8 + 2 * t, 6 + 2 * t)
        let arr = PlanarArrangement(segments: segs)
        let rooms = [Vec2(2, 1.5), Vec2(6, 1.5), Vec2(2, 5), Vec2(6, 5)].compactMap { arr.face(containing: $0) }
        #expect(rooms.count == 4)
        for r in rooms { #expect(approx(r.area, 12)) }
        // The wall body itself is a face whose holes are the four rooms.
        let wall = arr.face(containing: Vec2(4.1, 1))
        #expect(wall != nil)
        #expect(wall!.holes.count == 4)
        #expect(approx(wall!.area, 8.6 * 6.6 - 48))
    }

    @Test func tJunctionSplitsRoom() {
        var segs = rectSegments(0, 0, 10, 6)
        segs.append(Segment2(Vec2(4, 0), Vec2(4, 6))) // wall line touching both sides
        segs.append(Segment2(Vec2(4, 3), Vec2(10, 3))) // T into the previous line
        let arr = PlanarArrangement(segments: segs)
        #expect(arr.faces.count == 3)
        #expect(approx(arr.face(containing: Vec2(1, 1))!.area, 24))
        #expect(approx(arr.face(containing: Vec2(6, 1))!.area, 18))
        #expect(approx(arr.face(containing: Vec2(6, 5))!.area, 18))
    }

    @Test func columnIslandBecomesHole() {
        var segs = rectSegments(0, 0, 10, 10)
        segs += rectSegments(4, 4, 5, 5) // free-standing column
        let arr = PlanarArrangement(segments: segs)
        let room = arr.face(containing: Vec2(1, 1))
        #expect(room != nil)
        #expect(room!.holes.count == 1)
        #expect(!room!.holes[0].isCounterClockwise)
        #expect(approx(room!.area, 99))
        #expect(approx(room!.profile.area, 99))
        // Inside the column is the column's own face.
        #expect(approx(arr.face(containing: Vec2(4.5, 4.5))!.area, 1))
    }

    @Test func nestedIslands() {
        var segs = rectSegments(0, 0, 20, 20)
        segs += rectSegments(5, 5, 15, 15)
        segs += rectSegments(9, 9, 11, 11)
        let arr = PlanarArrangement(segments: segs)
        #expect(approx(arr.face(containing: Vec2(1, 1))!.area, 300))
        #expect(approx(arr.face(containing: Vec2(6, 6))!.area, 96))
        #expect(approx(arr.face(containing: Vec2(10, 10))!.area, 4))
    }

    @Test func unenclosedRegionReturnsNil() {
        // Three sides of a room only.
        let segs = [
            Segment2(Vec2(0, 0), Vec2(5, 0)), Segment2(Vec2(5, 0), Vec2(5, 5)), Segment2(Vec2(5, 5), Vec2(0, 5)),
        ]
        let arr = PlanarArrangement(segments: segs)
        #expect(arr.faces.isEmpty)
        #expect(arr.face(containing: Vec2(2, 2)) == nil)
    }

    @Test func danglingStubsArePruned() {
        var segs = rectSegments(0, 0, 6, 4)
        segs.append(Segment2(Vec2(3, 0), Vec2(3, 1.5)))   // stub from a wall into the room
        segs.append(Segment2(Vec2(1, 2), Vec2(2, 2)))     // free-floating line
        segs.append(Segment2(Vec2(6, 2), Vec2(8, 2)))     // stub outside
        let arr = PlanarArrangement(segments: segs)
        #expect(arr.faces.count == 1)
        let f = arr.faces[0]
        #expect(approx(f.area, 24))
        #expect(f.holes.isEmpty)
        #expect(f.outer.simplified().count == 4)
        #expect(approx(f.outer.perimeter, 20))
    }

    @Test func bridgeToIslandIsPruned() {
        var segs = rectSegments(0, 0, 10, 10)
        segs += rectSegments(4, 4, 6, 6)
        segs.append(Segment2(Vec2(0, 5), Vec2(4, 5))) // room separation line reaching the column
        let arr = PlanarArrangement(segments: segs)
        let room = arr.face(containing: Vec2(1, 1))!
        #expect(approx(room.area, 96))
        #expect(room.holes.count == 1)
        #expect(approx(room.outer.perimeter, 40))
    }

    @Test func overlappingCollinearSegmentsMerge() {
        var segs = rectSegments(0, 0, 4, 4)
        segs.append(Segment2(Vec2(1, 0), Vec2(3, 0)))      // duplicate piece of the bottom edge
        segs.append(Segment2(Vec2(4, 4), Vec2(0, 4)))      // reversed duplicate of the top edge
        segs.append(Segment2(Vec2(-1, 0), Vec2(2, 0)))     // overlaps and extends
        let arr = PlanarArrangement(segments: segs)
        #expect(arr.faces.count == 1)
        #expect(approx(arr.faces[0].area, 16))
        // No duplicated edges: total edge length = square perimeter + the 1 m extension.
        let total = arr.edges.reduce(0) { $0 + $1.length }
        #expect(approx(total, 17))
    }

    @Test func snapsNearCoincidentVertices() {
        let e = 4e-6 // below the default snap tolerance
        let segs = [
            Segment2(Vec2(0, 0), Vec2(5, 0)), Segment2(Vec2(5 + e, e), Vec2(5, 5)),
            Segment2(Vec2(5, 5 - e), Vec2(0, 5)), Segment2(Vec2(0, 5), Vec2(e, 0)),
        ]
        let arr = PlanarArrangement(segments: segs)
        #expect(arr.faces.count == 1)
        #expect(approx(arr.faces[0].area, 25, 1e-4))
        // A wider snap closes a 3 mm gap.
        let gap = [
            Segment2(Vec2(0, 0), Vec2(5, 0)), Segment2(Vec2(5, 0.003), Vec2(5, 5)),
            Segment2(Vec2(5, 5), Vec2(0, 5)), Segment2(Vec2(0, 5), Vec2(0, 0)),
        ]
        #expect(PlanarArrangement(segments: gap).faces.isEmpty)
        #expect(PlanarArrangement(segments: gap, snapTolerance: 0.005).faces.count == 1)
    }

    @Test func largeCoordinates() {
        let o = Vec2(10_000, -10_000)
        var segs = rectSegments(o.x, o.y, o.x + 5, o.y + 4)
        segs.append(Segment2(o + Vec2(2, 0), o + Vec2(2, 4)))
        let arr = PlanarArrangement(segments: segs)
        #expect(arr.faces.count == 2)
        #expect(approx(arr.face(containing: o + Vec2(1, 1))!.area, 8, 1e-6))
    }

    @Test func deterministic() {
        var segs: [Segment2] = []
        for i in 0..<6 { segs.append(Segment2(Vec2(Double(i), -1), Vec2(Double(i), 6))) }
        for j in 0..<6 { segs.append(Segment2(Vec2(-1, Double(j)), Vec2(6, Double(j)))) }
        let a = PlanarArrangement(segments: segs)
        let b = PlanarArrangement(segments: segs)
        #expect(a.faces.count == 25)
        #expect(a.faces.map(\.outer) == b.faces.map(\.outer))
        #expect(a.vertices == b.vertices)
    }

    @Test func manyRoomsPerformance() {
        // 60×60 grid of rooms: 7,200 wall lines crossing into 3,600 faces.
        var segs: [Segment2] = []
        let n = 60
        for i in 0...n {
            segs.append(Segment2(Vec2(Double(i) * 3, 0), Vec2(Double(i) * 3, Double(n) * 3)))
            segs.append(Segment2(Vec2(0, Double(i) * 3), Vec2(Double(n) * 3, Double(i) * 3)))
        }
        let clock = ContinuousClock()
        let start = clock.now
        let arr = PlanarArrangement(segments: segs)
        let elapsed = clock.now - start
        #expect(arr.faces.count == n * n)
        #expect(elapsed < .seconds(10))
    }
}

@Suite struct BoundaryCleanupTests {
    @Test func lJoinRemovesInteriorLine() {
        // Two overlapping wall rectangles forming an L corner.
        let a = rect(0, 0, 5, 0.2)
        let b = rect(0, 0, 0.2, 4)
        let pieces = BoundaryCleanup.unionBoundary(of: [a, b])
        let total = pieces.reduce(0) { $0 + $1.segment.length }
        // Union outline perimeter: 5 + 0.2 + 4.8 + ... = 2*(5+4) = 18.
        #expect(approx(total, 18))
        // No piece lies inside the union.
        for p in pieces {
            let m = p.segment.midpoint
            #expect(!(a.contains(m, onBoundary: false) || b.contains(m, onBoundary: false)))
        }
        // Interior on the left of every piece.
        for p in pieces {
            let q = p.segment.midpoint + p.segment.normal * 0.01
            #expect(a.contains(q) || b.contains(q))
        }
    }

    @Test func buttJoinSharedEdgeDisappears() {
        let a = rect(0, 0, 5, 0.2)
        let b = rect(5, 0, 10, 0.2)
        let pieces = BoundaryCleanup.unionBoundary(of: [a, b])
        #expect(approx(pieces.reduce(0) { $0 + $1.segment.length }, 20.4))
        #expect(!pieces.contains { approx($0.segment.start.x, 5) && approx($0.segment.end.x, 5) })
    }

    @Test func coincidentSameSideEdgesEmittedOnce() {
        // Two walls overlapping along their length, sharing the bottom face line.
        let a = rect(0, 0, 6, 0.2)
        let b = rect(2, 0, 8, 0.3)
        let pieces = BoundaryCleanup.unionBoundary(of: [a, b])
        let bottom = pieces.filter { approx($0.segment.start.y, 0) && approx($0.segment.end.y, 0) }
        #expect(approx(bottom.reduce(0) { $0 + $1.segment.length }, 8))
        #expect(approx(pieces.reduce(0) { $0 + $1.segment.length }, 8 + 8 + 0.2 + 0.3 + 0.1))
    }

    @Test func tJoinAndDeterminism() {
        let a = rect(0, 0, 10, 0.2)
        let b = rect(4.9, 0.2, 5.1, 5)
        let b2 = rect(4.9, 0, 5.1, 5) // overlaps into a
        let p1 = BoundaryCleanup.unionBoundary(of: [a, b2])
        let p2 = BoundaryCleanup.unionBoundary(of: [a, b2])
        #expect(p1 == p2)
        #expect(approx(p1.reduce(0) { $0 + $1.segment.length }, 30))
        let p3 = BoundaryCleanup.unionBoundary(of: [a, b])
        #expect(approx(p3.reduce(0) { $0 + $1.segment.length }, 30))
    }

    @Test func clipSegmentsOutside() {
        let segs = [Segment2(Vec2(-5, 1), Vec2(15, 1)), Segment2(Vec2(0, 0), Vec2(10, 0))]
        let polys = [rect(0, 0, 2, 2), rect(5, -1, 7, 3)]
        let out = BoundaryCleanup.clipSegments(segs, outside: polys)
        // First segment: [-5,0], [2,5], [7,15]. Second lies on the first polygon's edge
        // for [0,2] (kept), inside the second polygon for [5,7].
        #expect(out.count == 5)
        #expect(approx(out[0].length, 5) && approx(out[1].length, 3) && approx(out[2].length, 8))
        #expect(approx(out[3].length, 5) && approx(out[4].length, 3))
    }
}
