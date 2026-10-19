import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// The geometry of the tool in progress snaps like drawn lines, as in Revit: a floor sketch's own lines give endpoints,
/// midpoints and alignment, so the next line can stop level with an earlier one.
@MainActor
@Suite("Snapping to the sketch in progress")
struct SketchSnappingTests {
    func context() -> ToolContext {
        let ctx = ToolContext(session: DocumentSession(model: BIMModel()), viewID: ElementID(99))
        ctx.pixel = 0.01    // tolerances: 6 pt = 0.06 m
        return ctx
    }
    /// A sketch so far: up the left side, then along the bottom (the screenshot the owner sent).
    let sketch: [Curve2] = [.line(Segment2(Vec2(0, 4), Vec2(0, 0))), .line(Segment2(Vec2(0, 0), Vec2(3, 0)))]

    @Test func drawingUpStopsLevelWithTheSketchsOtherEnd() {
        let ctx = context()
        ctx.snapIndex.setTransient(sketch)
        // Going up from the bottom-right corner, a little above the left line's top: vertical and level with its end.
        let (p, r) = ctx.snap(Vec2(3.02, 4.037), from: Vec2(3, 0))
        #expect(abs(p.x - 3) < 1e-9 && abs(p.y - 4) < 1e-9, "snapped to \(p) (\(r?.shortLabel ?? "-"))")
        #expect(r?.shortLabel == "Vertical and Extension", "label: \(r?.shortLabel ?? "nil")")
    }

    @Test func theSketchsEndpointsAndMidpointsSnap() {
        let ctx = context()
        ctx.snapIndex.setTransient(sketch)
        let (e, re) = ctx.snap(Vec2(0.03, 3.98), from: Vec2(2, 2))
        #expect(re?.kind == .endpoint && Fx.approx(e, Vec2(0, 4)), "closes on the first point")
        let (m, rm) = ctx.snap(Vec2(1.52, 0.03), from: Vec2(2, 2))
        #expect(rm?.kind == .midpoint && Fx.approx(m, Vec2(1.5, 0)))
    }

    @Test func withoutTheSketchNothingIsThereToSnapTo() {
        let ctx = context()
        let (_, r) = ctx.snap(Vec2(0.03, 3.98), from: Vec2(2, 2))
        #expect(r?.kind != .endpoint)
        ctx.snapIndex.setTransient(sketch)
        ctx.snapIndex.setTransient([])
        #expect(ctx.snap(Vec2(0.03, 3.98), from: Vec2(2, 2)).1?.kind != .endpoint, "cleared when the tool ends")
    }

    @Test func toolsOfferThePointsPlacedSoFar() {
        #expect(SnapIndex.chain([Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)]).count == 2)
        #expect(SnapIndex.chain([Vec2(0, 0), Vec2(1, 0), Vec2(1, 1)], closed: true).count == 3)
        #expect(SnapIndex.chain([Vec2(0, 0)]).isEmpty)
    }
}
