import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// Canvas direct manipulation: temporary dimensions on the selection, typed drag values, flip and toggle controls,
/// Tab chain selection, Select Previous, witness lines and Tab snap cycling.
@MainActor
@Suite("Select tool and direct manipulation")
struct SelectToolTests {
    @MainActor struct Env {
        let ctx: ToolContext
        let ids: ProjectTemplates.Ids
        var session: DocumentSession { ctx.session }
        var model: BIMModel { ctx.session.model }
        var selection: SelectionModel { ctx.session.selection }
        var plan: ElementID { ids.planViews[ids.levels[0]]! }
    }

    func env(_ build: (TransactionContext, ProjectTemplates.Ids) throws -> Void = { _, _ in }) throws -> Env {
        var (m, ids) = Fx.template()
        try Fx.commit(&m, "Setup") { tx in try build(tx, ids) }
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()   // tools commit without a run loop
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.pixel = 0.01
        return Env(ctx: ctx, ids: ids)
    }

    /// Three horizontal 10 m walls at y = 0, 3 and 7.5; returns the environment and the wall ids bottom to top.
    func threeWalls() throws -> (Env, [ElementID]) {
        var w: [ElementID] = []
        let e = try env { tx, ids in w = [0, 3, 7.5].map { Fx.wall(tx, ids, Vec2(0, $0), Vec2(10, $0)) } }
        return (e, w)
    }

    func offsets(_ dims: [SelectionDimension]) -> [SelectionDimension] { dims.filter { $0.role == .offset }.sorted { $0.value < $1.value } }

    // MARK: Temporary dimensions

    @Test func wallBetweenParallelWallsShowsTwoOffsetsAndItsLength() throws {
        let (e, w) = try threeWalls()
        let dims = SelectionDimensions.compute(for: w[1], in: e.model, view: e.model[e.plan])
        let off = offsets(dims)
        let T = WallGeometry.assembly(for: e.model[w[1]]!, e.model).totalThickness
        #expect(off.count == 2)
        // Face to face: the gaps between the walls, not their centre lines.
        #expect(Fx.approx(off[0].value, 3 - T) && Fx.approx(off[1].value, 4.5 - T))
        #expect(off[0].otherReference.elementID == w[0] && off[1].otherReference.elementID == w[2])
        #expect(off.allSatisfy { Fx.approx(abs($0.from.y - 3), T / 2) && Fx.approx($0.from.distance(to: $0.to), $0.value) })
        let length = try #require(dims.first { $0.role == .length })
        #expect(Fx.approx(length.value, 10))
        // Only in plan views.
        let south = e.model.views.first { $0.name == "South" }
        #expect(SelectionDimensions.compute(for: w[1], in: e.model, view: south).isEmpty)
    }

    @Test func typedValueMovesByTheDifferenceLikeADrag() throws {
        // Typing 2 m into the 3 m dimension moves the wall 1 m toward the reference ...
        let (typed, w) = try threeWalls()
        typed.selection.select([w[1]])
        let tool = SelectTool(ctx: typed.ctx)
        let d = try #require(offsets(tool.selectionDimensions).first)
        let T = WallGeometry.assembly(for: typed.model[w[1]]!, typed.model).totalThickness
        #expect(tool.setDimension(d, to: "2000"))
        let loc = try #require(typed.model[w[1]]!.wall!.location.asSegment)
        #expect(Fx.approx(loc.start, Vec2(0, 2 + T)) && Fx.approx(loc.end, Vec2(10, 2 + T)), "a 2 m gap between the faces")
        #expect(Fx.approx(offsets(tool.selectionDimensions)[0].value, 2), "the dimension follows the move")
        #expect(!tool.setDimension(d, to: "abc"))

        // ... exactly as dragging it there does.
        let (dragged, w2) = try threeWalls()
        dragged.selection.select([w2[1]])
        let drag = SelectTool(ctx: dragged.ctx)
        _ = drag.beginDrag(at: Vec2(5, 3), grip: nil)
        drag.dragged(to: Vec2(5, 2 + T))
        drag.endDrag(at: Vec2(5, 2 + T))
        #expect(Fx.approx(dragged.model[w2[1]]!.wall!.location.midpoint, typed.model[w[1]]!.wall!.location.midpoint))

        // Typing while dragging sets the highlighted (nearest) gap, measured with the drag applied.
        let (during, w3) = try threeWalls()
        during.selection.select([w3[1]])
        let t3 = SelectTool(ctx: during.ctx)
        #expect(t3.numericLabel == nil)
        _ = t3.beginDrag(at: Vec2(5, 3), grip: nil)
        t3.dragged(to: Vec2(5, 2.6))
        #expect(t3.numericLabel == "Distance")
        #expect(t3.numericInput("2000"))
        #expect(Fx.approx(during.model[w3[1]]!.wall!.location.midpoint, typed.model[w[1]]!.wall!.location.midpoint))
        #expect(!t3.isDragging)
    }

    @Test func typedLengthMovesTheWallEnd() throws {
        let (e, w) = try threeWalls()
        e.selection.select([w[0]])
        let tool = SelectTool(ctx: e.ctx)
        let length = try #require(tool.selectionDimensions.first { $0.role == .length })
        #expect(tool.setDimension(length, to: "6500"))
        #expect(e.model[w[0]]!.wall!.location == .line(Segment2(Vec2(0, 0), Vec2(6.5, 0))))
        // Dragging an end grip and typing sets the length from the fixed end.
        let grip = GripService.grips(for: e.model[w[0]]!, e.model, viewKind: .floorPlan)[1]
        _ = tool.beginDrag(at: grip.position, grip: grip)
        tool.dragged(to: Vec2(7, 0.1))
        #expect(tool.numericLabel == "Length")
        #expect(tool.numericInput("4000"))
        let seg = try #require(e.model[w[0]]!.wall!.location.asSegment)
        #expect(Fx.approx(seg.length, 4) && seg.start == Vec2(0, 0))
    }

    @Test func pinnedElementsRefuseTypedValues() throws {
        let (e, w) = try threeWalls()
        e.session.perform("Pin") { tx in tx.update(w[1]) { $0.pinned = true } }
        e.selection.select([w[1]])
        let tool = SelectTool(ctx: e.ctx)
        var messages: [String] = []
        e.ctx.showMessage = { messages.append($0) }
        let d = try #require(offsets(tool.selectionDimensions).first)
        tool.setDimension(d, to: "1000")
        #expect(e.model[w[1]]!.wall!.location.start == Vec2(0, 3))
        #expect(messages.contains { $0.contains("pinned") })
    }

    @Test func doorDimensionsRunAlongTheHost() throws {
        var host: ElementID!, door: ElementID!
        let e = try env { tx, ids in
            let walls = Fx.boxWalls(tx, ids, w: 10, h: 8)
            host = walls[0]
            door = Fx.door(tx, ids, host: host, at: Vec2(3, 0))
        }
        let dims = offsets(SelectionDimensions.compute(for: door, in: e.model, view: e.model[e.plan]))
        // From each opening edge to the inner face of the west (x = 0) and east (x = 10) walls.
        let T = WallGeometry.assembly(for: e.model[host]!, e.model).totalThickness
        let jl = try #require(DimensionQueries.resolve(GeometryReference(door, .openingLeft), e.model)?.point)
        let jr = try #require(DimensionQueries.resolve(GeometryReference(door, .openingRight), e.model)?.point)
        let W = jl.distance(to: jr)
        #expect(dims.count == 2)
        #expect(Fx.approx(dims[0].value, 3 - W / 2 - T / 2) && Fx.approx(dims[1].value, 7 - W / 2 - T / 2))
        e.selection.select([door])
        let tool = SelectTool(ctx: e.ctx)
        #expect(tool.setDimension(dims[0], to: "1200"))
        #expect(Fx.approx(e.model[door]!.insert!.location, Vec2(T / 2 + 1.2 + W / 2, 0)), "a 1.2 m gap from the west wall's face to the opening")
        #expect(e.model[door]!.hostID == host)
    }

    @Test func columnGetsOneDimensionPerAxis() throws {
        var col: ElementID!
        let e = try env { tx, ids in
            _ = Fx.boxWalls(tx, ids, w: 10, h: 8)
            col = tx.create(.columns, data: .column(ColumnData(location: Vec2(2, 5))), levelID: ids.levels[0])
        }
        let dims = SelectionDimensions.compute(for: col, in: e.model, view: e.model[e.plan]).sorted { $0.value < $1.value }
        #expect(dims.count == 2)
        let T = WallGeometry.assembly(for: e.model.elements(.walls).first!, e.model).totalThickness
        #expect(Fx.approx(dims[0].value, 2 - T / 2) && Fx.approx(dims[1].value, 3 - T / 2), "column centre to the wall faces")
    }

    @Test func gridsDimensionToParallelGrids() throws {
        var g: [ElementID] = []
        let e = try env { tx, _ in
            g = [0.0, 6, 13].enumerated().map { k, x in tx.create(.grids, name: "\(k + 1)", data: .grid(GridData(curve: .line(Segment2(Vec2(x, -2), Vec2(x, 12)))))) }
        }
        let dims = offsets(SelectionDimensions.compute(for: g[1], in: e.model, view: e.model[e.plan]))
        #expect(dims.map(\.value).map { ($0 * 1000).rounded() } == [6000, 7000])
    }

    @Test func makingATemporaryDimensionPermanentMeasuresTheSame() throws {
        let (e, w) = try threeWalls()
        e.selection.select([w[1]])
        let tool = SelectTool(ctx: e.ctx)
        for d in tool.selectionDimensions { tool.makePermanent(d) }
        let dims = e.model.elements(.dimensions)
        #expect(dims.count == 3)
        #expect(dims.allSatisfy { $0.ownerViewID == e.plan })
        let values = dims.flatMap { DimensionQueries.measure($0, e.model) }.map { ($0 * 1000).rounded() }.sorted()
        let T = WallGeometry.assembly(for: e.model[w[1]]!, e.model).totalThickness
        #expect(values == [((3 - T) * 1000).rounded(), ((4.5 - T) * 1000).rounded(), 10000])
    }

    // MARK: Flip and toggle controls

    @Test func flipControlsToggleEachFlagIndependently() throws {
        var wall: ElementID!, door: ElementID!
        let e = try env { tx, ids in
            wall = Fx.wall(tx, ids, .zero, Vec2(8, 0))
            door = Fx.door(tx, ids, host: wall, at: Vec2(3, 0))
        }
        let view = e.model[e.plan]
        let wc = GripService.controls(for: e.model[wall]!, e.model, view: view, pixel: 0.01)
        #expect(wc.map(\.kind) == [.flipWall])
        // The wall's arrows sit outside its exterior (left) face.
        #expect(wc[0].position.y > 0.1)
        let tool = SelectTool(ctx: e.ctx)
        tool.click(wc[0])
        #expect(e.model[wall]!.wall!.flipped)
        let flippedControls = GripService.controls(for: e.model[wall]!, e.model, view: view, pixel: 0.01)
        #expect(flippedControls[0].position.y < -0.1, "the arrows follow the exterior side")

        let dc = GripService.controls(for: e.model[door]!, e.model, view: view, pixel: 0.01)
        #expect(Set(dc.map(\.kind)) == [.flipFacing, .flipHand])
        tool.click(dc.first { $0.kind == .flipFacing }!)
        #expect(e.model[door]!.insert!.facingFlipped && !e.model[door]!.insert!.handFlipped)
        tool.click(dc.first { $0.kind == .flipHand }!)
        #expect(e.model[door]!.insert!.facingFlipped && e.model[door]!.insert!.handFlipped)
        tool.click(dc.first { $0.kind == .flipFacing }!)
        #expect(!e.model[door]!.insert!.facingFlipped && e.model[door]!.insert!.handFlipped)
        #expect(e.model[wall]!.wall!.flipped, "flipping the door leaves the wall alone")
        // Drag grips are unchanged by the controls.
        #expect(GripService.grips(for: e.model[door]!, e.model, viewKind: .floorPlan).map(\.kind) == [.point])
        // No controls outside plan views.
        let south = e.model.views.first { $0.name == "South" }
        #expect(GripService.controls(for: e.model[wall]!, e.model, view: south, pixel: 0.01).isEmpty)
    }

    @Test func bubbleEqualityAndLockControlsToggle() throws {
        var grid: ElementID!, dim: ElementID!
        var walls: [ElementID] = []
        let e = try env { tx, ids in
            grid = tx.create(.grids, name: "A", data: .grid(GridData(curve: .line(Segment2(Vec2(0, -2), Vec2(0, 12))))))
            walls = [0.0, 3, 7].map { Fx.wall(tx, ids, Vec2($0, 0), Vec2($0, 5)) }
            let refs = walls.map { GeometryReference($0, .location) }
            dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: refs, linePoint: Vec2(0, 6))),
                            ownerViewID: ids.planViews[ids.levels[0]]!)
        }
        let view = e.model[e.plan]
        let tool = SelectTool(ctx: e.ctx)
        let gc = GripService.controls(for: e.model[grid]!, e.model, view: view, pixel: 0.01).filter { if case .bubble = $0.kind { return true }; return false } // I4 adds 3D/2D, elbow and lock controls
        #expect(gc.map(\.kind) == [.bubble(atEnd: false), .bubble(atEnd: true)])
        #expect(gc[0].isOn && !gc[1].isOn)
        tool.click(gc[1])
        #expect(e.model[grid]!.grid!.bubbleAtEnd && e.model[grid]!.grid!.bubbleAtStart)
        tool.click(gc[0])
        #expect(!e.model[grid]!.grid!.bubbleAtStart)

        let dc = GripService.controls(for: e.model[dim]!, e.model, view: view, pixel: 0.01)
        #expect(Set(dc.map(\.kind)) == [.dimensionEquality, .dimensionLock])
        tool.click(dc.first { $0.kind == .dimensionEquality }!)
        #expect(e.model[dim]!.dimension!.equality && !e.model[dim]!.dimension!.locked)
        tool.click(dc.first { $0.kind == .dimensionLock }!)
        #expect(e.model[dim]!.dimension!.locked)
    }

    @Test func levelBubblesToggleInElevations() throws {
        let e = try env()
        let south = try #require(e.model.views.first { $0.name == "South" })
        let level = e.model.levels[0]
        let cs = GripService.controls(for: level, e.model, view: south, pixel: 0.01, levelLine: (-5, 20))
        #expect(cs.map(\.kind) == [.bubble(atEnd: false), .bubble(atEnd: true)])
        // Levels without explicit extents still get end grips from the drawn line.
        #expect(GripService.grips(for: level, e.model, viewKind: .elevation, levelLine: (-5, 20)).map(\.position) == [Vec2(-5, level.level!.elevation), Vec2(20, level.level!.elevation)])
        let before = level.level!.showBubbleStart
        SelectTool(ctx: e.ctx).click(cs[0])
        #expect(e.model[level.id]!.level!.showBubbleStart == !before)
    }

    // MARK: Tab chain and Select Previous

    @Test func tabOverOneWallOfAClosedLoopYieldsAllFour() throws {
        var box: [ElementID] = []
        var loose: ElementID!
        let e = try env { tx, ids in
            box = Fx.boxWalls(tx, ids)
            loose = Fx.wall(tx, ids, Vec2(20, 0), Vec2(25, 0))
        }
        let sel = e.selection
        sel.setCycleCandidates([box[2]], model: e.model)
        #expect(sel.preselectedIDs == [box[2]])
        sel.cycle()
        #expect(sel.isChainPreselected)
        #expect(Set(sel.preselectedIDs) == Set(box))
        sel.cycle()
        #expect(sel.preselectedIDs == [box[2]], "Tab wraps back to the wall itself")
        #expect(SelectionModel.wallChain(from: loose, in: e.model) == [loose])
        sel.setCycleCandidates([loose], model: e.model)
        sel.cycle()
        #expect(!sel.isChainPreselected, "a wall with no joined neighbours has no chain entry")
        // Disallowing a join breaks the chain there.
        e.session.perform("Disallow") { tx in tx.update(box[0]) { $0.wall?.allowJoinAtEnd = false } }
        let chain = SelectionModel.wallChain(from: box[0], in: e.model)
        #expect(Set(chain) == Set(box), "still connected the other way round the loop")
        e.session.perform("Disallow") { tx in tx.update(box[2]) { $0.wall?.allowJoinAtEnd = false } }
        #expect(Set(SelectionModel.wallChain(from: box[0], in: e.model)) == [box[0], box[3]])
    }

    @Test func selectPreviousRestoresThePriorSetAfterEscape() throws {
        let (e, w) = try threeWalls()
        let sel = e.selection
        #expect(!sel.selectPrevious(in: e.model), "nothing to restore yet")
        sel.select([w[0], w[2]])
        let tool = SelectTool(ctx: e.ctx)
        #expect(tool.escape() == .stayInTool)
        #expect(sel.isEmpty)
        #expect(sel.selectPrevious(in: e.model))
        #expect(sel.ids == [w[0], w[2]])
        // After a replacement the previous set is the one replaced; deleted elements are skipped.
        sel.select([w[1]])
        e.session.delete([w[2]])
        sel.clear()
        #expect(sel.selectPrevious(in: e.model) && sel.ids == [w[1]])
        sel.select([w[0]])
        #expect(sel.selectPrevious(in: e.model) && sel.ids == [w[1]])
    }

    /// I3: with an element selected, the permanent dimensions to it edit in place, as in RevitCraft: the segment's
    /// value moves the selected element; segments between two other references are not offered.
    @Test func permanentDimensionsToTheSelectionEditInPlace() throws {
        var walls: [ElementID] = []
        var dim: ElementID!
        let e = try env { tx, ids in
            walls = [0.0, 3, 7].map { Fx.wall(tx, ids, Vec2($0, 0), Vec2($0, 5)) }
            dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: walls.map { GeometryReference($0, .location) },
                                                                         linePoint: Vec2(0, 6))), ownerViewID: ids.planViews[ids.levels[0]]!)
        }
        e.selection.select([walls[1]])
        let tool = SelectTool(ctx: e.ctx)
        let perm = tool.selectionDimensions.filter { $0.permanentLabel != nil }.sorted { $0.value < $1.value }
        #expect(perm.count == 2, "both segments touch the middle wall")
        #expect(Fx.approx(perm[0].value, 3) && Fx.approx(perm[1].value, 4))
        #expect(perm.allSatisfy { $0.elementReference.elementID == walls[1] })
        // Typing 2 m into the 3 m segment moves the middle wall to x = 2; the dimension follows.
        let three = perm[0]
        #expect(tool.setDimension(three, to: "2000"))
        let loc = try #require(e.model[walls[1]]?.wall?.location.asSegment)
        #expect(Fx.approx(loc.start.x, 2) && Fx.approx(loc.end.x, 2))
        // Selecting an end wall offers only its own segment.
        e.selection.select([walls[0]])
        #expect(SelectTool(ctx: e.ctx).selectionDimensions.filter { $0.permanentLabel != nil }.count == 1)
        // Locked strings are left alone.
        try e.ctx.session.perform("Lock") { tx in tx.update(dim) { $0.dimension?.locked = true } }
        #expect(SelectTool(ctx: e.ctx).selectionDimensions.allSatisfy { $0.permanentLabel == nil })
    }

    // MARK: Witness lines

    @Test func witnessDragReReferencesTheDimension() throws {
        var walls: [ElementID] = []
        var dim: ElementID!
        let e = try env { tx, ids in
            walls = [0.0, 3, 7].map { Fx.wall(tx, ids, Vec2($0, 0), Vec2($0, 5)) }
            dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: [GeometryReference(walls[0], .location), GeometryReference(walls[1], .location)],
                                                                         linePoint: Vec2(0, 6))), ownerViewID: ids.planViews[ids.levels[0]]!)
        }
        e.selection.select([dim])
        let grips = GripService.grips(for: e.model[dim]!, e.model, viewKind: .floorPlan)
        let witness = try #require(grips.first { $0.kind == .witness(1) })
        let tool = SelectTool(ctx: e.ctx)
        _ = tool.beginDrag(at: witness.position, grip: witness)
        tool.dragged(to: Vec2(7, 2.5))
        var drop = ToolInput(point: Vec2(7.05, 2.5), rawPoint: Vec2(7.05, 2.5))
        drop.hitCandidates = [dim, walls[2]]
        drop.hit = dim
        tool.endDrag(drop)
        let d = try #require(e.model[dim]?.dimension)
        #expect(e.model.elements(.dimensions).map(\.id) == [dim], "same element, not recreated")
        #expect(d.references[0] == GeometryReference(walls[0], .location))
        #expect(d.references[1].elementID == walls[2])
    }

    @Test func editWitnessLinesAddsAndRemovesReferences() throws {
        var walls: [ElementID] = []
        var dim: ElementID!
        let e = try env { tx, ids in
            walls = [0.0, 3, 7].map { Fx.wall(tx, ids, Vec2($0, 0), Vec2($0, 5)) }
            dim = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: [GeometryReference(walls[0], .location), GeometryReference(walls[2], .location)],
                                                                         linePoint: Vec2(0, 6))), ownerViewID: ids.planViews[ids.levels[0]]!)
        }
        let tool = WitnessLineTool(ctx: e.ctx, dimensionID: dim)
        func click(_ id: ElementID, _ p: Vec2) {
            var i = ToolInput(point: p, rawPoint: p)
            i.hit = id; i.hitCandidates = [id]
            tool.pointerDown(i)
        }
        click(walls[1], Vec2(3, 2))
        var d = try #require(e.model[dim]?.dimension)
        #expect(d.references.map(\.elementID) == [walls[0], walls[1], walls[2]], "inserted in order along the dimension")
        // The new witness line picks the wall face nearest the click (the default preference).
        let segments = DimensionQueries.measure(e.model[dim]!, e.model)
        #expect(segments.count == 2 && Fx.approx(segments.reduce(0, +), 7) && abs(segments[0] - 3) <= 0.15)
        click(walls[1], Vec2(3, 2))
        d = try #require(e.model[dim]?.dimension)
        #expect(d.references.map(\.elementID) == [walls[0], walls[2]])
        var messages: [String] = []
        e.ctx.showMessage = { messages.append($0) }
        click(walls[0], Vec2(0, 2))
        #expect(e.model[dim]!.dimension!.references.count == 2 && !messages.isEmpty, "a dimension keeps two witness lines")
    }

    // MARK: Tab through snaps

    @Test func snapCandidatesListEveryDistinctSnapBestFirst() {
        let (m, ids) = Fx.template()
        let ctx = ToolContext(session: DocumentSession(model: m), viewID: ids.planViews[ids.levels[0]]!)
        ctx.pixel = 0.02
        ctx.snapIndex = SnapTests().cross
        // Near (7, 0): the intersection, and the nearest points on each line.
        let c = ctx.snapCandidates(Vec2(7.05, 0.05), from: nil)
        #expect(c.first?.kind == ctx.snap(Vec2(7.05, 0.05)).1?.kind)
        #expect(c.count >= 2)
        #expect(Set(c.map(\.kind)).contains(.intersection))
        ctx.snapOverride = .off
        #expect(ctx.snapCandidates(Vec2(7.05, 0.05), from: nil).isEmpty)
    }
}
