import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// Moving walls keeps them joined to walls that did not move, and dragged elements never snap to themselves.
@Suite("Move keeps joins")
struct MoveJoinTests {
    func rectangle() throws -> (BIMModel, [ElementID]) {
        var (m, ids) = Fx.template()
        var walls: [ElementID] = []
        try Fx.commit(&m) { tx in
            let c = [Vec2(0, 0), Vec2(12, 0), Vec2(12, 8), Vec2(0, 8)]
            for i in 0..<4 { walls.append(Fx.wall(tx, ids, c[i], c[(i + 1) % 4])) }
        }
        return (m, walls)
    }

    @Test func movingOneWallStretchesItsCornerNeighbours() throws {
        var (m, w) = try rectangle()
        try Fx.commit(&m) { tx in try ElementOperations.transform([w[0]], by: .translation(Vec2(0, -1.5)), in: tx, viewID: nil) }
        let south = m[w[0]]!.wall!.location.asSegment!, east = m[w[1]]!.wall!.location.asSegment!, west = m[w[3]]!.wall!.location.asSegment!
        #expect(Fx.approx(south.start, Vec2(0, -1.5)) && Fx.approx(south.end, Vec2(12, -1.5)))
        #expect(Fx.approx(east.start, Vec2(12, -1.5)) && Fx.approx(east.end, Vec2(12, 8)))
        #expect(Fx.approx(west.end, Vec2(0, -1.5)) && Fx.approx(west.start, Vec2(0, 8)))
        // Still a closed, joined outline: the room-bounding footprint union has one outer loop.
        #expect(WallGeometry.endJoin(m[w[0]]!, atEnd: false, m).kind != .free)
    }

    @Test func teeJoinedPartitionFollowsTheMovedWall() throws {
        var (m, w) = try rectangle()
        var p: ElementID!
        try Fx.commit(&m) { tx in p = Fx.wall(tx, Fx.template().1, Vec2(6, 0), Vec2(6, 8)) }
        try Fx.commit(&m) { tx in try ElementOperations.transform([w[2]], by: .translation(Vec2(0, 2)), in: tx, viewID: nil) }
        let seg = m[p]!.wall!.location.asSegment!
        #expect(Fx.approx(seg.end, Vec2(6, 10)), "partition end follows the north wall")
        #expect(Fx.approx(seg.start, Vec2(6, 0)))
    }

    @Test func movingTheWholeSetDoesNotStretchAnything() throws {
        var (m, w) = try rectangle()
        try Fx.commit(&m) { tx in try ElementOperations.transform(w, by: .translation(Vec2(3, 1)), in: tx, viewID: nil) }
        #expect(Fx.approx(m[w[1]]!.wall!.location.asSegment!.length, 8))
        #expect(Fx.approx(m[w[0]]!.wall!.location.asSegment!.start, Vec2(3, 1)))
    }

    @Test func disallowedJoinIsNotStretched() throws {
        var (m, w) = try rectangle()
        try Fx.commit(&m) { tx in tx.update(w[1]) { $0.wall?.allowJoinAtStart = false } }
        try Fx.commit(&m) { tx in try ElementOperations.transform([w[0]], by: .translation(Vec2(0, -1)), in: tx, viewID: nil) }
        #expect(Fx.approx(m[w[1]]!.wall!.location.asSegment!.start, Vec2(12, 0)))
    }

    @MainActor @Test func draggedElementsDoNotSnapToThemselves() {
        let seg = [Vec2(0, 0), Vec2(10, 0)]
        let g = ViewGraphics(viewID: ElementID(99), scale: 100,
                             items: [GItem(elementID: ElementID(1), category: .walls, layer: .model, primitives: [.polyline(seg, closed: false, .thin)])],
                             extents: .empty, crop: nil, modelRevision: 0)
        let idx = SnapIndex(graphics: g, model: BIMModel(), view: Element(id: ElementID(99), category: .views, data: .view(ViewData(kind: .drafting))))
        #expect(idx.snap(Vec2(5, -1), radius: 1.5, from: nil, settings: SnapSettings())?.kind == .midpoint)
        #expect(idx.snap(Vec2(5, -1), radius: 1.5, from: nil, settings: SnapSettings(), exclude: [ElementID(1)]) == nil)
    }
}
