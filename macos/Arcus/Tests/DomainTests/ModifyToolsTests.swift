import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// Modify tools and the clipboard: Create Similar, Measure, arrays, Disjoin, Offset, Split, Demolish, Scale and
/// paste between projects.
@MainActor
@Suite("Modify tools and clipboard")
struct ModifyToolsTests {
    static let doubleDoor = "Door - Double Flush: 1800 x 2100"

    func context() -> (ToolContext, ProjectTemplates.Ids) {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()   // tools commit without a run loop
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.currentTypes[.walls] = ids.wallTypes[Fx.generic]
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2, shift: Bool = false, hit: ElementID? = nil) {
        var i = ToolInput(point: p, rawPoint: p)
        i.shift = shift
        i.hit = hit
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }
    func wallWithDoor(_ ctx: ToolContext, _ ids: ProjectTemplates.Ids, _ a: Vec2 = .zero, _ b: Vec2 = Vec2(10, 0), door at: Vec2 = Vec2(4, 0)) -> (ElementID, ElementID) {
        var w: ElementID!, d: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, a, b); d = Fx.door(tx, ids, host: w, at: at) }
        return (w, d)
    }
    func segment(_ m: BIMModel, _ id: ElementID) -> Segment2 { m[id]!.wall!.location.asSegment! }

    // MARK: Create Similar

    @Test func createSimilarOnADoorStartsTheDoorToolWithThatType() throws {
        let (ctx, ids) = context()
        let double = try #require(ids.familyTypes[Self.doubleDoor])
        #expect(ctx.type(for: .doors) != double, "the default door type is a different one")
        var w: ElementID!, d: ElementID!
        ctx.session.perform("Setup") { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(12, 0))
            d = Fx.door(tx, ids, host: w, at: Vec2(3, 0), type: Self.doubleDoor)
        }
        let plan = try #require(CreateSimilar.plan(for: ctx.model[d]!, ctx.model))
        #expect(plan.command == .door)
        #expect(plan.types[.doors] == double)
        // What the router does: preselect the type, then start the command's tool.
        for (c, t) in plan.types { ctx.currentTypes[c] = t }
        let tool = InsertTool(ctx: ctx, category: .doors)
        #expect(tool.commandID == plan.command)
        click(tool, Vec2(8, 0.05), hit: w)
        let placed = ctx.model.elements(.doors).filter { $0.id != d }
        #expect(placed.count == 1)
        #expect(placed.first?.typeID == double && placed.first?.hostID == w)
    }

    @Test func createSimilarMapsElementsToTheirTools() throws {
        let (ctx, ids) = context()
        var arc: ElementID!, line: ElementID!, win: ElementID!
        ctx.session.perform("Setup") { tx in
            arc = tx.create(.walls, data: .wall(WallData(location: .arc(Arc2(center: .zero, radius: 5, startAngle: 0, sweep: 1)))), typeID: ids.wallTypes[Fx.brick], levelID: ids.levels[0])
            let host = Fx.wall(tx, ids, Vec2(0, 10), Vec2(10, 10))
            win = Fx.window(tx, ids, host: host, at: Vec2(5, 10))
            line = tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(.zero, Vec2(1, 0))))), ownerViewID: ctx.viewID)
        }
        let m = ctx.model
        #expect(CreateSimilar.plan(for: m[arc]!, m) == CreateSimilar.Plan(command: .wallArc, types: [.walls: ids.wallTypes[Fx.brick]!]))
        #expect(CreateSimilar.plan(for: m[win]!, m)?.command == .window)
        #expect(CreateSimilar.plan(for: m[line]!, m)?.command == .detailLine)
        #expect(CreateSimilar.plan(for: m[ctx.viewID]!, m) == nil, "views are not placed with a tool")
        #expect(CommandCatalog.defaultAliases["CS"] == .createSimilar)
    }

    // MARK: Measure

    @Test func measureReportsWithoutChangingTheModel() {
        let (ctx, _) = context()
        let revision = ctx.model.revision
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        let tool = MeasureTool(ctx: ctx, mode: .between)
        tool.chain = true
        click(tool, .zero)
        click(tool, Vec2(3, 4))
        #expect(messages.last?.contains("Length 5") == true)
        click(tool, Vec2(3, 10))
        #expect(Fx.approx(tool.total, 11))
        #expect(messages.last?.contains("Total 11") == true)
        #expect(tool.preview.tempDims.count == 2)
        #expect(ctx.model.revision == revision, "measuring never commits")
        #expect(tool.escape() == .stayInTool)
        #expect(tool.escape() == .exitTool)
    }

    @Test func measureAlongSumsElementsWithShift() {
        let (ctx, ids) = context()
        var a: ElementID!, b: ElementID!
        ctx.session.perform("Walls") { tx in a = Fx.wall(tx, ids, .zero, Vec2(6, 0)); b = Fx.wall(tx, ids, Vec2(6, 0), Vec2(6, 4)) }
        let revision = ctx.model.revision
        let tool = MeasureTool(ctx: ctx, mode: .along)
        click(tool, Vec2(3, 0), hit: a)
        #expect(Fx.approx(tool.total, 6))
        click(tool, Vec2(6, 2), shift: true, hit: b)
        #expect(Fx.approx(tool.total, 10))
        click(tool, Vec2(6, 2), hit: b)
        #expect(Fx.approx(tool.total, 4), "a plain click starts a new measurement")
        #expect(ctx.model.revision == revision)
    }

    // MARK: Arrays

    @Test func radialArrayOfSixOver360PlacesMembers60DegreesApart() throws {
        let (ctx, ids) = context()
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, Vec2(5, 0), Vec2(8, 0)) }
        let tool = ArrayTool(ctx: ctx, ids: [w])
        tool.setOption("arrayMode", .text("Radial"))
        tool.setOption("count", .int(6))
        tool.setOption("last", .bool(true))
        tool.center = .zero
        #expect(tool.numericLabel == "Angle")
        #expect(tool.numericInput("360"))
        let walls = ctx.model.elements(.walls)
        #expect(walls.count == 6)
        let angles = walls.map { Angle.degrees(Angle.normalize($0.wall!.location.start.angle)) }.sorted()
        for (k, a) in angles.enumerated() { #expect(abs(a - Double(k) * 60) < 1e-6) }
        let group = try #require(ArrayOperations.arrayGroup(of: w, ctx.model))
        #expect(group.group?.members.count == 6)
        #expect(group.group?.arraySpec?.kind == .radial && group.group?.arraySpec?.count == 6)
    }

    @Test func editingTheArrayCountRegeneratesMembers() throws {
        let (ctx, ids) = context()
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, Vec2(5, 0), Vec2(8, 0)) }
        var group: ElementID?
        ctx.session.perform("Array") { tx in
            group = try ArrayOperations.create(.radial(count: 6, center: .zero, stepAngle: .pi / 3, sourceMembers: [w], fixedExtent: true), associate: true, in: tx, viewID: ctx.viewID)
        }
        let gid = try #require(group)
        ctx.session.perform("Array Number") { tx in try ArrayOperations.setCount(8, ofArray: gid, in: tx, viewID: ctx.viewID) }
        #expect(ctx.session.lastError == nil)
        let walls = ctx.model.elements(.walls)
        #expect(walls.count == 8)
        let angles = walls.map { Angle.degrees(Angle.normalize($0.wall!.location.start.angle)) }.sorted()
        for (k, a) in angles.enumerated() { #expect(abs(a - Double(k) * 45) < 1e-6, "a full turn stays evenly spread") }
        let g = try #require(ctx.model[gid]?.group)
        #expect(g.members.count == 8 && g.arraySpec?.count == 8)
        #expect(g.members.first == w, "the source stays member 0")
        #expect(walls.allSatisfy { $0.groupID == gid })
        // Linear, fixed spacing: fewer members shrink the array.
        var line: ElementID!
        ctx.session.perform("Line") { tx in line = Fx.wall(tx, ids, Vec2(0, 20), Vec2(2, 20)) }
        var lg: ElementID?
        ctx.session.perform("Array") { tx in lg = try ArrayOperations.create(.linear(count: 4, step: Vec2(0, 3), sourceMembers: [line]), associate: true, in: tx, viewID: nil) }
        ctx.session.perform("Array Number") { tx in try ArrayOperations.setCount(2, ofArray: lg!, in: tx, viewID: nil) }
        let ys = ctx.model[lg!]!.group!.members.map { ctx.model[$0]!.wall!.location.start.y }.sorted()
        #expect(ys == [20, 23])
        #expect(ArrayOperations.arrayGroup(of: line, ctx.model)?.id == lg)
    }

    @Test func linearArrayWithoutAssociationMakesNoGroup() {
        let (ctx, ids) = context()
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, .zero, Vec2(4, 0)) }
        let tool = ArrayTool(ctx: ctx, ids: [w])
        tool.setOption("associate", .bool(false))
        tool.setOption("count", .int(3))
        click(tool, .zero)
        click(tool, Vec2(0, 5))
        #expect(ctx.model.elements(.walls).count == 3)
        #expect(ctx.model.elements(.modelGroups).isEmpty)
    }

    // MARK: Disjoin

    func rectangle(_ ctx: ToolContext, _ ids: ProjectTemplates.Ids) -> [ElementID] {
        var walls: [ElementID] = []
        ctx.session.perform("Walls") { tx in
            let c = [Vec2(0, 0), Vec2(12, 0), Vec2(12, 8), Vec2(0, 8)]
            for i in 0..<4 { walls.append(Fx.wall(tx, ids, c[i], c[(i + 1) % 4])) }
        }
        return walls
    }

    @Test func disjoinMovesAWallWithoutStretchingItsJoinedNeighbour() {
        let (ctx, ids) = context()
        let w = rectangle(ctx, ids)
        let tool = MoveCopyTool(ctx: ctx, ids: [w[0]], copy: false)
        tool.setOption("disjoin", .bool(true))
        #expect(tool.options.contains { $0.id == "disjoin" })
        click(tool, Vec2(6, 0))
        click(tool, Vec2(6, -2))
        #expect(Fx.approx(segment(ctx.model, w[0]).start, Vec2(0, -2)))
        #expect(Fx.approx(segment(ctx.model, w[1]).start, Vec2(12, 0)), "east wall keeps its end")
        #expect(Fx.approx(segment(ctx.model, w[3]).end, Vec2(0, 0)), "west wall keeps its end")
        // Without Disjoin the neighbours follow (unchanged behaviour).
        ctx.session.perform("Move") { tx in try ElementOperations.transform([w[2]], by: .translation(Vec2(0, 1)), in: tx, viewID: nil) }
        #expect(Fx.approx(segment(ctx.model, w[1]).end, Vec2(12, 9)))
    }

    @Test func disjoinRehostsAMovedDoorOnTheWallAtItsNewLocation() {
        let (ctx, ids) = context()
        let (w1, d) = wallWithDoor(ctx, ids)
        var w2: ElementID!
        ctx.session.perform("Wall") { tx in w2 = Fx.wall(tx, ids, Vec2(0, 5), Vec2(10, 5)) }
        ctx.session.perform("Move") { tx in try ElementOperations.transform([d], by: .translation(Vec2(1, 5)), in: tx, viewID: nil, disjoin: true) }
        #expect(ctx.model[d]?.hostID == w2)
        #expect(Fx.approx(ctx.model[d]!.insert!.location, Vec2(5, 5)))
        #expect(ctx.model[w1] != nil)
        // Nowhere to go: refused.
        ctx.session.perform("Move") { tx in try ElementOperations.transform([d], by: .translation(Vec2(0, 20)), in: tx, viewID: nil, disjoin: true) }
        #expect(ctx.session.lastError != nil)
        #expect(ctx.model[d]?.hostID == w2)
    }

    // MARK: Offset

    @Test func offsettingAWallWithADoorCreatesADoorHostedOnTheNewWall() {
        let (ctx, ids) = context()
        let (w, d) = wallWithDoor(ctx, ids)
        let tool = OffsetTool(ctx: ctx)
        tool.setOption("distance", .double(3))
        var i = ToolInput(point: Vec2(5, 1), rawPoint: Vec2(5, 1))
        i.hit = w
        tool.pointerMoved(i)
        tool.pointerDown(i)
        let walls = ctx.model.elements(.walls)
        #expect(walls.count == 2)
        let copy = walls.first { $0.id != w }!
        #expect(Fx.approx(copy.wall!.location.start, Vec2(0, 3)))
        let doors = ctx.model.elements(.doors)
        #expect(doors.count == 2)
        let newDoor = doors.first { $0.id != d }!
        #expect(newDoor.hostID == copy.id)
        #expect(Fx.approx(newDoor.insert!.location, Vec2(4, 3)))
        #expect(ctx.model[d]?.hostID == w && Fx.approx(ctx.model[d]!.insert!.location, Vec2(4, 0)))
    }

    @Test func offsetWithoutCopyMovesTheDoorWithTheWall() {
        let (ctx, ids) = context()
        let (w, d) = wallWithDoor(ctx, ids)
        ctx.session.perform("Offset") { tx in try ElementOperations.offset(w, by: -2, copy: false, in: tx, viewID: ctx.viewID) }
        #expect(Fx.approx(segment(ctx.model, w).start, Vec2(0, -2)))
        #expect(Fx.approx(ctx.model[d]!.insert!.location, Vec2(4, -2)))
    }

    // MARK: Split

    @Test func deleteInnerSegmentRemovesThePartBetweenTwoPicks() {
        let (ctx, ids) = context()
        var w: ElementID!, inside: ElementID!, outside: ElementID!
        ctx.session.perform("Setup") { tx in
            w = Fx.wall(tx, ids, .zero, Vec2(12, 0))
            inside = Fx.door(tx, ids, host: w, at: Vec2(5, 0))
            outside = Fx.door(tx, ids, host: w, at: Vec2(10, 0))
        }
        let tool = SplitTool(ctx: ctx)
        tool.setOption("splitMode", .text(SplitTool.Mode.deleteInnerSegment.rawValue))
        click(tool, Vec2(4, 0), hit: w)
        click(tool, Vec2(7, 0), hit: w)
        #expect(ctx.session.lastError == nil)
        let walls = ctx.model.elements(.walls).sorted { $0.wall!.location.start.x < $1.wall!.location.start.x }
        #expect(walls.count == 2)
        #expect(Fx.approx(walls[0].wall!.location.end, Vec2(4, 0)))
        #expect(Fx.approx(walls[1].wall!.location.start, Vec2(7, 0)) && Fx.approx(walls[1].wall!.location.end, Vec2(12, 0)))
        #expect(ctx.model[inside] == nil, "the door in the removed part goes with it")
        #expect(ctx.model[outside]?.hostID == walls[1].id)
    }

    @Test func splitWithGapLeavesTheGap() {
        let (ctx, ids) = context()
        var w: ElementID!
        ctx.session.perform("Wall") { tx in w = Fx.wall(tx, ids, .zero, Vec2(10, 0)) }
        let tool = SplitTool(ctx: ctx)
        tool.setOption("splitMode", .text(SplitTool.Mode.gap.rawValue))
        tool.setOption("gap", .double(0.5))
        click(tool, Vec2(5, 0), hit: w)
        let xs = ctx.model.elements(.walls).flatMap { [$0.wall!.location.start.x, $0.wall!.location.end.x] }.sorted()
        #expect(xs.count == 4)
        #expect(Fx.approx(xs[1], 4.75) && Fx.approx(xs[2], 5.25))
    }

    // MARK: Demolish

    @Test func demolishSetsThePhaseOnTheWallAndItsDoor() throws {
        let (ctx, ids) = context()
        let (w, d) = wallWithDoor(ctx, ids)
        let phase = try #require(ctx.viewData?.phaseID)
        let tool = DemolishTool(ctx: ctx)
        #expect(tool.phaseID == phase)
        click(tool, Vec2(8, 0), hit: w)
        #expect(ctx.model[w]?.phaseDemolished == phase)
        #expect(ctx.model[d]?.phaseDemolished == phase)
        // An element created in a later phase can't be demolished in an earlier one.
        ctx.session.perform("Existing") { tx in tx.update(w) { $0.phaseDemolished = nil } }
        ctx.session.perform("Demolish") { tx in try ElementOperations.demolish([w], phase: ids.phases[0], in: tx) }
        #expect(ctx.session.lastError != nil)
        #expect(ctx.model[w]?.phaseDemolished == nil)
    }

    // MARK: Scale

    @Test func scaleResizesWallsAboutTheOrigin() {
        let (ctx, ids) = context()
        let (w, d) = wallWithDoor(ctx, ids, Vec2(1, 1), Vec2(5, 1), door: Vec2(3, 1))
        let tool = ScaleTool(ctx: ctx, ids: [w, d])
        click(tool, Vec2(1, 1))
        click(tool, Vec2(5, 1))
        click(tool, Vec2(9, 1))
        #expect(Fx.approx(segment(ctx.model, w).end, Vec2(9, 1)))
        #expect(Fx.approx(ctx.model[d]!.insert!.location, Vec2(5, 1)), "the door keeps its relative position")
        let numeric = ScaleTool(ctx: ctx, ids: [w])
        numeric.setOption("scaleMethod", .text("Numerical"))
        #expect(numeric.numericInput("0.5"))
        click(numeric, Vec2(1, 1))
        #expect(Fx.approx(segment(ctx.model, w).end, Vec2(5, 1)))
    }

    // MARK: Paste between projects

    @Test func pasteBetweenSessionsMapsTypesByNameAndReportsDuplicates() throws {
        let (srcModel, srcIDs) = Fx.template()
        let (dstModel, dstIDs) = Fx.template()
        let source = DocumentSession(model: srcModel)
        let dest = DocumentSession(model: dstModel)
        // The destination's generic wall type differs (a different fire rating); the source also has a type the
        // destination lacks.
        let genericDst = dstIDs.wallTypes[Fx.generic]!
        dest.perform("Edit Type") { tx in tx.update(genericDst) { $0.typeData?.params[ParameterID("typeComments")] = .text("Destination version") } }
        var custom: ElementID!, w1: ElementID!, w2: ElementID!, d: ElementID!
        source.perform("Setup") { tx in
            var td = tx.model[srcIDs.wallTypes[Fx.brick]!]!.typeData!
            td.params[ParameterID("typeComments")] = .text("Only in the source")
            custom = tx.create(.elementTypes, name: "Custom Partition", data: .type(td))
            w1 = Fx.wall(tx, srcIDs, .zero, Vec2(6, 0))
            w2 = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(0, 3), Vec2(6, 3))), topLevelID: srcIDs.levels[1])), typeID: custom, levelID: srcIDs.levels[0])
            d = Fx.door(tx, srcIDs, host: w1, at: Vec2(3, 0))
        }
        let payload = try #require(ClipboardPayload.capture([w1, w2], from: source.model, viewID: nil, levelID: srcIDs.levels[0]))
        #expect(payload.elements.map(\.id).contains(d), "hosted doors travel with their wall")
        #expect(payload.context[custom] != nil && payload.context[srcIDs.levels[1]] != nil)

        var report = PasteReport()
        dest.perform("Paste") { tx in report = ProjectTransfer.paste(payload, into: tx, targetView: nil, fallbackLevel: dstIDs.levels[0]) }
        #expect(dest.lastError == nil)
        #expect(report.pasted.count == 3)
        let walls = dest.model.elements(.walls)
        #expect(walls.count == 2)
        let generic = try #require(walls.first { $0.wall!.location.start == .zero })
        #expect(generic.typeID == genericDst, "types are matched by name")
        #expect(generic.levelID == dstIDs.levels[0] && generic.wall?.topLevelID == dstIDs.levels[1])
        #expect(report.duplicateTypes.contains { $0.hasSuffix(Fx.generic) }, "a same-named type with other settings is reported")
        let added = try #require(walls.first { $0.id != generic.id }?.typeID)
        #expect(dest.model[added]?.name == "Custom Partition")
        #expect(dest.model[added]?.typeData?.params[ParameterID("typeComments")] == .text("Only in the source"))
        #expect(report.addedTypes == ["\(dest.model[added]!.typeData!.familyName): Custom Partition"])
        let door = try #require(dest.model.elements(.doors).first)
        #expect(door.hostID == generic.id)
        #expect(door.typeID == dstIDs.familyTypes[Fx.doorType], "the door type matches by family and type name")
        #expect(!report.duplicateTypes.contains(Fx.doorType), "identical types are not reported")
        #expect(report.summary.contains("Pasted 3"))
        // Pasting again reuses the type added the first time.
        var again = PasteReport()
        dest.perform("Paste") { tx in again = ProjectTransfer.paste(payload, into: tx, transform: .translation(Vec2(0, 10)), targetView: nil, fallbackLevel: nil) }
        #expect(again.addedTypes.isEmpty)
        #expect(dest.model.types(for: .walls).filter { $0.name == "Custom Partition" }.count == 1)
    }

    @Test func pasteBetweenSessionsSkipsDependentsWithoutTheirHost() throws {
        let (srcModel, srcIDs) = Fx.template()
        let (dstModel, dstIDs) = Fx.template()
        let source = DocumentSession(model: srcModel)
        let dest = DocumentSession(model: dstModel)
        var d: ElementID!
        source.perform("Setup") { tx in let w = Fx.wall(tx, srcIDs, .zero, Vec2(6, 0)); d = Fx.door(tx, srcIDs, host: w, at: Vec2(3, 0)) }
        let payload = try #require(ClipboardPayload.capture([d], from: source.model, viewID: nil, levelID: nil))
        var report = PasteReport()
        dest.perform("Paste") { tx in report = ProjectTransfer.paste(payload, into: tx, targetView: nil, fallbackLevel: dstIDs.levels[0]) }
        #expect(report.pasted.isEmpty)
        #expect(report.skipped.count == 1)
        #expect(dest.model.elements(.doors).isEmpty)
    }
}

@Suite("Array group persistence")
struct ArraySpecCodingTests {
    @Test func groupsWithoutAnArraySpecStillDecode() throws {
        let legacy = GroupData(members: [ElementID(7)], origin: Vec2(1, 2), groupTypeName: "Group 1")
        let data = try JSONEncoder().encode(legacy)
        #expect(!(String(data: data, encoding: .utf8) ?? "").contains("arraySpec"), "ordinary groups are written as before")
        let back = try JSONDecoder().decode(GroupData.self, from: data)
        #expect(back == legacy && back.arraySpec == nil)
        var arrayed = legacy
        arrayed.arraySpec = .radial(count: 6, center: Vec2(3, 4), stepAngle: .pi / 3, sourceMembers: [ElementID(7)], fixedExtent: true)
        let round = try JSONDecoder().decode(GroupData.self, from: JSONEncoder().encode(arrayed))
        #expect(round == arrayed)
    }

    @Test func arraySpecFollowsTransforms() {
        let s = ArraySpec.radial(count: 4, center: Vec2(1, 0), stepAngle: 0.5, sourceMembers: [])
        let moved = s.transformed(by: .translation(Vec2(2, 3)))
        #expect(moved.center == Vec2(3, 3) && moved.stepAngle == 0.5)
        let mirrored = s.transformed(by: .mirror(through: .zero, direction: .unitX))
        #expect(mirrored.stepAngle == -0.5)
        let l = ArraySpec.linear(count: 3, step: Vec2(2, 0), sourceMembers: [], fixedExtent: true).withCount(5)
        #expect(l.step == Vec2(1, 0) && l.count == 5)
    }
}
