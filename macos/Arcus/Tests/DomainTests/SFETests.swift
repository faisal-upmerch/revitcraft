import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// SFE (RevitCraft port): object snapping in the Family Editor's 2D views, through the project's snap engine. Endpoint,
/// midpoint and reference-plane intersections (with plane locking), alignment tracking, Tab candidates, typed overrides,
/// and the clean-up of drawn geometry (hidden-line pieces chained, tessellated circles snapping by centre).
@Suite("SFE Family Editor snapping")
@MainActor
struct SFETests {
    static func approx(_ a: Vec2, _ b: Vec2, _ tol: Double = 1e-6) -> Bool { a.distance(to: b) <= tol }

    /// The Generic Box (1 m cube between Left/Right, Front/Back, Bottom/Top), evaluated.
    static func box() -> (FamilyDefinition, EvaluatedFamily) {
        let f = StarterLibrary.genericBox()
        return (f, FamilyEvaluator.evaluate(f, typeName: f.types[0].name))
    }

    /// The reference planes seen edge-on in `frame`, as the canvas lists them.
    static func planes(_ f: FamilyDefinition, _ ev: EvaluatedFamily, _ frame: FamilyEditing.ViewFrame) -> [FamilyEditing.PlaneLine] {
        f.referencePlanes.compactMap { p in
            guard let v = ev.planes[p.name] else { return nil }
            if p.axis == frame.plane.axes.u { return FamilyEditing.PlaneLine(name: p.name, vertical: true, value: v * frame.uSign) }
            if p.axis == frame.plane.axes.v { return FamilyEditing.PlaneLine(name: p.name, vertical: false, value: v) }
            return nil
        }
    }

    /// The box's plan: its form outline and the planes.
    static func planScene() -> FamilySnapScene {
        let (f, ev) = box()
        let curves = ev.solids.map { FamilySnapScene.Curve(points: $0.profile.outer.points, closed: true, item: .solid($0.sourceID ?? ""), label: "Generic Models : Box") }
        return FamilySnapScene(curves: curves, planes: planes(f, ev, .plan))
    }

    /// A snapper at 1 mm per screen point (10 mm snap radius, 6 mm tracking tolerance).
    static func snapper(_ scene: FamilySnapScene) -> FamilySnapper {
        let s = FamilySnapper()
        s.pixel = 0.001
        s.load(scene)
        return s
    }

    @Test func snapsToAFormCornerAndLocksToItsPlanes() {
        let s = Self.snapper(Self.planScene())
        let (p, r) = s.snap(Vec2(0.503, 0.497))
        #expect(r?.kind == .endpoint)
        #expect(Self.approx(p, Vec2(0.5, 0.5)))
        #expect(r?.label == "ENDPOINT of [Generic Models : Box]")
        let v = s.vertex(p, frame: .plan)
        #expect(v.uPlane == "Right" && v.vPlane == "Back")
        #expect(v.familyPoint == FamilyPoint(.plane("Right"), .plane("Back")))
    }

    @Test func snapsToAnEdgeMidpoint() {
        let s = Self.snapper(Self.planScene())
        let (p, r) = s.snap(Vec2(0.504, 0.006))
        #expect(r?.kind == .midpoint)
        #expect(Self.approx(p, Vec2(0.5, 0)))
        let v = s.vertex(p, frame: .plan)
        #expect(v.uPlane == "Right" && v.vPlane == nil) // the right edge lies on the Right plane
    }

    @Test func referencePlaneIntersectionLocksToBothPlanes() {
        let (f, ev) = Self.box()
        // Front elevation, planes only: the crossing of Left and Bottom is an intersection snap of the two planes.
        let s = Self.snapper(FamilySnapScene(planes: Self.planes(f, ev, .front)))
        let (p, r) = s.snap(Vec2(-0.506, 0.004))
        #expect(r?.kind == .intersection)
        #expect(Self.approx(p, Vec2(-0.5, 0)))
        #expect(Set(r.map(s.planes(of:)) ?? []) == ["Left", "Bottom"])
        #expect(r?.label == "INTERSECTION of [Reference Planes : Left] AND [Reference Planes : Bottom]")
        let v = s.vertex(p, frame: .front)
        #expect(v.uPlane == "Left" && v.vPlane == "Bottom")
        // Back elevation: the u axis is mirrored; the vertex still locks to Left in sketch coordinates.
        let back = Self.snapper(FamilySnapScene(planes: Self.planes(f, ev, .back)))
        let (q, rb) = back.snap(Vec2(0.505, 0.003))
        #expect(rb?.kind == .intersection)
        let vb = back.vertex(q, frame: .back)
        #expect(vb.uPlane == "Left" && vb.vPlane == "Bottom" && abs(vb.u + 0.5) < 1e-9)
    }

    @Test func nearAPlaneAloneSnapsNearestAndLocksOneCoordinate() {
        let (f, ev) = Self.box()
        let s = Self.snapper(FamilySnapScene(planes: Self.planes(f, ev, .plan)))
        let (p, r) = s.snap(Vec2(0.2, 0.505))
        #expect(r?.kind == .nearest)
        #expect(abs(p.y - 0.5) < 1e-12)
        let v = s.vertex(p, frame: .plan)
        #expect(v.vPlane == "Back" && v.uPlane == nil)
        // Planes are infinite: no endpoint or midpoint anywhere along them.
        #expect(!s.candidates(Vec2(0.0, 0.505)).contains { $0.kind == .endpoint || $0.kind == .midpoint })
    }

    @Test func freePointsRoundToTheMillimetre() {
        let s = Self.snapper(Self.planScene())
        let (p, r) = s.snap(Vec2(2.12345, 3.45678))
        #expect(r == nil)
        #expect(Self.approx(p, Vec2(2.123, 3.457), 1e-12))
        #expect(s.vertex(p, frame: .plan).uPlane == nil)
    }

    @Test func extensionTrackingAndItsCrossingWithVertical() {
        let line = FamilySnapScene.Curve(points: [Vec2(0, 0), Vec2(1, 0)], closed: false, item: .modelLine("L1"), label: "Lines : Model Lines")
        let s = Self.snapper(FamilySnapScene(curves: [line]))
        // Beyond the line's end, near its extension: held on it, with a dashed guide from the end.
        let (p, r) = s.snap(Vec2(1.3, 0.004))
        #expect(r?.kind == .extension)
        #expect(abs(p.y) < 1e-9)
        #expect(r?.label == "EXTENSION of [Lines : Model Lines]")
        #expect(r?.guides.isEmpty == false)
        // Drawing down from a start point above: the vertical through it crosses the extension.
        let (q, rq) = s.snap(Vec2(1.302, 0.003), from: Vec2(1.3, 0.5))
        #expect(rq?.kind == .intersection)
        #expect(Self.approx(q, Vec2(1.3, 0)))
        #expect(rq?.label?.contains("EXTENSION of [Lines : Model Lines]") == true)
        #expect(rq?.label?.contains("VERTICAL") == true)
        // Alignment: level with the top end of a vertical line, well to its right.
        let post = FamilySnapScene.Curve(points: [Vec2(0, 0), Vec2(0, 1)], closed: false, item: .line("P"), label: "Lines : Symbolic Lines")
        let a = Self.snapper(FamilySnapScene(curves: [post]))
        let (q2, r2) = a.snap(Vec2(0.4, 1.003))
        #expect(r2?.kind == .extension && r2?.shortLabel == "Alignment")
        #expect(abs(q2.y - 1) < 1e-9)
        #expect(r2?.label == "ALIGNMENT with END of [Lines : Symbolic Lines]")
    }

    @Test func angleSnapUsesTheAdaptiveIncrement() {
        let s = Self.snapper(FamilySnapScene())
        // 300 pt long rubber band at ~31°: adaptive increment 5°, held at 30°.
        let from = Vec2(0, 0), raw = Vec2.fromAngle(Angle.radians(30.4), length: 0.3)
        let (p, r) = s.snap(from + raw, from: from)
        #expect(r?.kind == .angle)
        #expect(abs(Angle.degrees((p - from).angle) - 30) < 1e-6)
    }

    @Test func tabCandidatesListEveryNearbySnapBestFirst() {
        let line = FamilySnapScene.Curve(points: [Vec2(0, 0), Vec2(0.01, 0)], closed: false, item: .line("S1"), label: "Lines : Symbolic Lines")
        let s = Self.snapper(FamilySnapScene(curves: [line]))
        let raw = Vec2(0.004, 0.001)
        let found = s.candidates(raw)
        #expect(found.count >= 3)
        #expect(found.first?.point == s.snap(raw).point)
        #expect(found.map(\.kind).contains(.midpoint))
        #expect(found.map(\.kind).contains(.nearest))
        #expect(Set(found.map(\.kind)).count == found.count) // the best snap of each kind
    }

    @Test func typedOverridesApplyToTheNextPickOnly() {
        #expect(FamilySnapper.overrideAliases["SM"] == .snapMidpoint)
        #expect(FamilySnapper.overrideAliases["SE"] == .snapEndpoint)
        #expect(FamilySnapper.overrideAliases["SW"] == nil)
        let s = Self.snapper(Self.planScene())
        let raw = Vec2(0.497, 0.493) // a corner is in reach
        #expect(s.snap(raw).snap?.kind == .endpoint)
        s.snapOverride = FamilySnapper.override(for: .snapMidpoint)?.override
        let (p, r) = s.snap(Vec2(0.502, 0.012))
        #expect(r?.kind == .midpoint && Self.approx(p, Vec2(0.5, 0)))
        s.pickDone()
        #expect(s.snapOverride == nil)
        s.snapOverride = FamilySnapper.override(for: .snapsOff)?.override
        #expect(s.snap(Vec2(0.5013, 0.4991)).snap == nil)
        #expect(FamilySnapper.override(for: .snapOverrideOff) != nil && FamilySnapper.override(for: .snapOverrideOff)?.override == nil)
        #expect(FamilySnapper.override(for: .wall) == nil)
    }

    @Test func draggedPlaneDoesNotSnapToItself() {
        let (f, ev) = Self.box()
        let s = Self.snapper(FamilySnapScene(planes: Self.planes(f, ev, .plan)))
        #expect(s.snap(Vec2(0.503, 0.2)).snap?.kind == .nearest)
        s.exclude([.plane("Right")])
        #expect(s.snap(Vec2(0.503, 0.2)).snap == nil)
    }

    @Test func frontElevationEdgesChainIntoWholeEdges() {
        let (f, ev) = Self.box()
        let proj = ViewProjection.elevation(lookingAt: Vec2(0, 1), origin: .zero, near: -1_000, far: 1_000)
        let edges = HiddenLineRenderer.render(ev.solids.enumerated().map { HLRInput(tag: $0.offset, mesh: $0.element.familyMesh) }, projection: proj)
        // Hidden-line output is one stroke per piece; split the top edge in two as an occluder would.
        let top = { (e: HLREdge) in abs(e.segment.start.y - 1) < 1e-9 && abs(e.segment.end.y - 1) < 1e-9 }
        #expect(edges.contains(where: top))
        var curves = edges.filter { !top($0) }.map { FamilySnapScene.Curve(points: [$0.segment.start, $0.segment.end], closed: false, item: .solid("box"), label: "Generic Models : Box") }
        curves.append(.init(points: [Vec2(-0.5, 1), Vec2(-0.2, 1)], closed: false, item: .solid("box"), label: "Generic Models : Box"))
        curves.append(.init(points: [Vec2(-0.2, 1), Vec2(0.5, 1)], closed: false, item: .solid("box"), label: "Generic Models : Box"))
        let s = Self.snapper(FamilySnapScene(curves: curves, planes: Self.planes(f, ev, .front)))
        // The corner (also the crossing of Right and Top) and the top edge's true midpoint.
        let (c, rc) = s.snap(Vec2(0.497, 1.004))
        #expect(rc?.kind == .endpoint && Self.approx(c, Vec2(0.5, 1)))
        #expect(s.vertex(c, frame: .front).familyPoint == FamilyPoint(.plane("Right"), .plane("Top")))
        let (m, rm) = s.snap(Vec2(0.004, 1.003))
        #expect(rm?.kind == .midpoint && Self.approx(m, Vec2(0, 1)))
        // No false midpoint where the piece was split.
        #expect(s.snap(Vec2(-0.35, 1.004)).snap?.kind != .midpoint)
    }

    @Test func tessellatedCirclesSnapByCentreAndQuadrant() {
        let circle = Arc2(center: Vec2(0.2, 0.1), radius: 0.15, startAngle: 0, sweep: Angle.twoPi).tessellate(chordTolerance: 0.002)
        let s = Self.snapper(FamilySnapScene(curves: [.init(points: Array(circle.dropLast()), closed: true, item: .solid("c"), label: "Generic Models : Round")]))
        let (p, r) = s.snap(Vec2(0.203, 0.104))
        #expect(r?.kind == .center && Self.approx(p, Vec2(0.2, 0.1), 1e-9))
        let (q, rq) = s.snap(Vec2(0.353, 0.104))
        #expect(rq?.kind == .quadrant && Self.approx(q, Vec2(0.35, 0.1), 1e-9))
        // A rectangle with many vertices along its sides stays straight edges, not a circle.
        #expect(FamilySnapper.split([Vec2(0, 0), Vec2(1, 0), Vec2(1, 1), Vec2(0, 1)], closed: true).count == 4)
    }

    @Test func visibleGeometryWinsOverHiddenGeometry() {
        let shown = FamilySnapScene.Curve(points: [Vec2(-1, 0), Vec2(2, 0)], closed: false, item: .modelLine("A"), label: "Lines : Model Lines")
        let hidden = FamilySnapScene.Curve(points: [Vec2(0.003, 0.003), Vec2(0.003, 0.5)], closed: false, item: .solid("H"), label: "Generic Models : Hidden", hidden: true)
        let s = Self.snapper(FamilySnapScene(curves: [shown, hidden]))
        // A hidden form's endpoint is in reach, but the visible line under the pointer wins (Nearest).
        let (p, r) = s.snap(Vec2(0.004, 0.002))
        #expect(r?.kind == .nearest && Self.approx(p, Vec2(0.004, 0)))
        // With nothing visible in reach, the hidden geometry snaps.
        #expect(s.snap(Vec2(0.004, 0.2)).snap?.kind == .nearest)
        #expect(s.snap(Vec2(0.004, 0.498)).snap?.kind == .endpoint)
    }

    @Test func sketchInProgressIsSnappable() {
        let sketch = FamilySnapScene.Curve(points: [Vec2(0, 0), Vec2(0.4, 0), Vec2(0.4, 0.3)], closed: false, item: nil, label: "Lines : <Sketch>")
        let s = Self.snapper(FamilySnapScene(curves: [sketch]))
        let (p, r) = s.snap(Vec2(0.002, 0.003), from: Vec2(0.4, 0.3))
        #expect(r?.kind == .endpoint && Self.approx(p, .zero))
        #expect(r?.label == "ENDPOINT of [Lines : <Sketch>]")
    }
}
