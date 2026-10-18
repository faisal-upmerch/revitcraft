import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Spot and detail tools (W2-ANNOT)")
struct SpotAndDetailToolTests {
    func floor(_ b: AnnotBench) -> ElementID {
        var id: ElementID!
        b.perform("Floor") { tx in
            id = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: b.ids.floorTypes["Concrete Slab 200mm"], levelID: b.level1)
        }
        return id
    }

    // MARK: Spots

    @Test func spotElevationFollowsItsFloor() throws {
        let b = AnnotBench()
        let f = floor(b)
        let tool = SpotTool(ctx: b.ctx(), kind: .elevation)
        tool.pointerMoved(b.input(Vec2(5, 4)))
        #expect(!AnnotBench.texts(tool.preview.primitives).isEmpty, "the spot previews with its value")
        b.click(tool, Vec2(5, 4))
        b.click(tool, Vec2(6, 5))
        let s = try #require(b.last(.spotElevations))
        #expect(s.spot?.referenceID == f)
        #expect(b.strings(s.id).first?.hasPrefix("0") == true)
        let offset = try #require(Parameters.instanceEntries(b.model[f]!, b.model).first { $0.name == "Height Offset From Level" })
        b.perform("Raise") { tx in try Parameters.set(offset.id, to: .double(0.3), on: f, in: tx) }
        #expect(b.strings(s.id).first?.hasPrefix("300") == true, "the label re-measures the floor: \(b.strings(s.id))")
        // Grips move the point and the label.
        let head = try #require(GripService.grips(for: s, b.model, viewKind: .floorPlan).first { $0.kind == .spotHead })
        b.perform("Head") { tx in GripService.apply(head, to: Vec2(8, 6), in: tx) }
        #expect(b.model[s.id]?.spot?.leaderHead == Vec2(8, 6))
        b.undo()
        #expect(b.model[s.id]?.spot?.leaderHead == Vec2(6, 5))
    }

    @Test func spotsInSectionsAndCoordinates() throws {
        let b = AnnotBench()
        let section = b.section()
        let tool = SpotTool(ctx: b.ctx(section), kind: .elevation)
        b.click(tool, Vec2(5, 3)); b.click(tool, Vec2(6, 4))
        let s = try #require(b.last(.spotElevations))
        #expect(b.strings(s.id, section).first?.hasPrefix("3000") == true)
        let coord = SpotTool(ctx: b.ctx(), kind: .coordinate)
        b.click(coord, Vec2(2, 3)); b.click(coord, Vec2(3, 4))
        let c = try #require(b.last(.spotCoordinates))
        let text = b.strings(c.id).joined()
        #expect(text.contains("N ") && text.contains("E "))
        let inSection = SpotTool(ctx: b.ctx(section), kind: .coordinate)
        b.click(inSection, Vec2(2, 1))
        #expect(b.model.elements(.spotCoordinates).count == 1)
        #expect(b.messages.last?.contains("plan") == true)
        let slope = SpotTool(ctx: b.ctx(), kind: .slope)
        _ = floor(b)
        b.click(slope, Vec2(5, 4)); b.click(slope, Vec2(6, 4))
        #expect(b.last(.spotSlopes) != nil)
    }

    // MARK: Regions, components, clouds, insulation

    @Test func filledAndMaskingRegionsUseTheChosenType() throws {
        let b = AnnotBench()
        let ctx = b.ctx()
        let solid = try #require(b.ids.systemTypes["Region Solid Black"])
        ctx.currentTypes[.filledRegions] = solid
        let tool = SketchTool(ctx: ctx, target: .filledRegion, commandID: .filledRegion)
        tool.drawMode = .rectangle
        b.click(tool, Vec2(1, 1)); b.click(tool, Vec2(3, 2))
        b.step { _ = tool.finish() }
        let r = try #require(b.last(.filledRegions))
        #expect(r.typeID == solid)
        #expect(AnnotBench.fills(try b.prims(r.id)).first?.1.pattern == .solid)
        let mask = SketchTool(ctx: ctx, target: .maskingRegion, commandID: .maskingRegion)
        mask.drawMode = .rectangle
        b.click(mask, Vec2(4, 1)); b.click(mask, Vec2(6, 2))
        b.step { _ = mask.finish() }
        let m = try #require(b.last(.maskingRegions), "\(b.messages) \(String(describing: b.session.lastError))")
        let item = try #require(b.item(m.id))
        #expect(item.layer == .masking && AnnotBench.fills(item.primitives).first?.1 == .mask)
    }

    @Test func detailComponentsRepeatingDetailsAndLegendComponents() throws {
        let b = AnnotBench()
        let ctx = b.ctx()
        let blocking = try #require(b.ids.familyTypes["Wood Blocking: 45 x 90"])
        ctx.currentTypes[.detailComponents] = blocking
        let place = ComponentTool(ctx: ctx, category: .detailComponents, commandID: .detailComponent)
        b.click(place, Vec2(1, 1))
        let dc = try #require(b.last(.detailComponents))
        #expect(AnnotBench.polylines(try b.prims(dc.id)).count == 6, "rectangle and cross")

        let rep = RepeatingDetailTool(ctx: ctx)
        b.click(rep, Vec2(0, 3))
        rep.pointerMoved(b.input(Vec2(1, 3)))
        #expect(AnnotBench.polylines(rep.preview.primitives).count > 6)
        #expect(b.type(rep, "900"))
        let r = try #require(b.last(.detailComponents))
        #expect(r.detailComponent?.repeatEnd == Vec2(0.9, 3))
        #expect(AnnotBench.polylines(try b.prims(r.id)).count == 20 * 6, "0.9 m of 45 mm blocks")
        let spacing = try #require(Parameters.instanceEntries(b.model[r.id]!, b.model).first { $0.name == "Spacing" })
        b.perform("Spacing") { tx in try Parameters.set(spacing.id, to: .double(0.1), on: r.id, in: tx) }
        #expect(AnnotBench.polylines(try b.prims(r.id)).count == 9 * 6)
        let end = try #require(GripService.grips(for: b.model[r.id]!, b.model, viewKind: .floorPlan).first { $0.kind == .repeatEnd })
        b.perform("Stretch") { tx in GripService.apply(end, to: Vec2(2, 3), in: tx) }
        #expect(AnnotBench.polylines(try b.prims(r.id)).count == 20 * 6)

        let legend = b.draftingView(.legend, scale: 50)
        let lt = LegendComponentTool(ctx: b.ctx(legend))
        lt.setOption("type", .text("Door - Single Flush: 900 x 2100"))
        #expect(lt.options.first?.value.textValue == "Door - Single Flush: 900 x 2100")
        b.click(lt, Vec2(0, 0))
        let ld = try #require(b.last(.detailComponents))
        #expect(ld.ownerViewID == legend && ld.detailComponent?.legendTypeID != nil)
        let doorSymbol = try b.prims(ld.id, legend)
        #expect(!AnnotBench.polylines(doorSymbol).isEmpty && !AnnotBench.arcs(doorSymbol).isEmpty, "door leaf and swing")
        lt.setOption("type", .text("Basic Wall: Exterior - Brick on CMU"))
        lt.setOption("length", .double(2))
        b.click(lt, Vec2(0, -2))
        let lw = try #require(b.last(.detailComponents))
        #expect(AnnotBench.fills(try b.prims(lw.id, legend)).count == 4, "one hatch per layer")
        // Legend components are refused in plans.
        let inPlan = LegendComponentTool(ctx: b.ctx())
        let count = b.model.elements(.detailComponents).count
        b.click(inPlan, Vec2(0, 0))
        #expect(b.model.elements(.detailComponents).count == count)
    }

    @Test func revisionCloudsInsulationAndSymbols() throws {
        let b = AnnotBench()
        b.perform("Revision") { tx in tx.create(.revisions, name: "Rev A", data: .revision(RevisionData(sequence: 1, date: "2026-09-26", description: "Issue"))) }
        let cloud = SketchTool(ctx: b.ctx(), target: .revisionCloud, commandID: .revisionCloud)
        cloud.drawMode = .rectangle
        b.click(cloud, Vec2(1, 1)); b.click(cloud, Vec2(4, 3))
        b.step { _ = cloud.finish() }
        let c = try #require(b.last(.revisionClouds))
        #expect(AnnotBench.arcs(try b.prims(c.id)).count > 8)

        let ins = LineTool(ctx: b.ctx(), kind: .insulation, commandID: .insulation)
        b.click(ins, Vec2(0, -1)); b.click(ins, Vec2(3, -1))
        let i = try #require(b.last(.insulation))
        #expect(AnnotBench.polylines(try b.prims(i.id)).first?.0.count ?? 0 > 10, "zig-zag batt")
        let end = try #require(GripService.grips(for: i, b.model, viewKind: .floorPlan).first { $0.kind == .end })
        b.perform("Stretch") { tx in GripService.apply(end, to: Vec2(5, -1), in: tx) }
        #expect(b.model[i.id]?.insulation?.line.end == Vec2(5, -1))

        let ctx = b.ctx()
        ctx.currentTypes[.genericAnnotations] = b.model.types(for: .genericAnnotations).first { $0.typeData?.familyName == "North Arrow" }?.id
        let north = ComponentTool(ctx: ctx, category: .genericAnnotations, commandID: .northArrow)
        b.click(north, Vec2(12, 6))
        let na = try #require(b.last(.genericAnnotations))
        #expect(b.strings(na.id) == ["N"])
    }

    // MARK: Detail groups

    @Test func detailGroupsAreCreatedAndPlacedInOtherViews() throws {
        let b = AnnotBench(box: false)
        var members: [ElementID] = []
        b.perform("Items") { tx in
            members.append(tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(0, 0), Vec2(2, 0))))), ownerViewID: b.plan))
            members.append(tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(0, 1), text: "Typical")), typeID: b.model.types(for: .textNotes).first?.id, ownerViewID: b.plan))
        }
        var group: ElementID!
        b.perform("Group") { tx in group = try DetailGroups.create(members, scale: 100, in: tx) }
        let g = try #require(b.model[group])
        #expect(g.category == .detailGroups && g.group?.members.count == 2)
        #expect(members.allSatisfy { b.model[$0]?.groupID == group })
        let drafting = b.draftingView()
        let tool = DetailGroupTool(ctx: b.ctx(drafting))
        #expect(tool.groupName == g.name)
        tool.pointerMoved(b.input(Vec2(10, 10)))
        #expect(!tool.preview.primitives.isEmpty)
        b.click(tool, Vec2(10, 10))
        let copies = b.model.owned(byView: drafting)
        #expect(copies.filter { $0.category == .detailLines }.count == 1)
        #expect(copies.filter { $0.category == .textNotes }.count == 1)
        #expect(copies.contains { $0.category == .detailGroups })
        b.undo()
        #expect(b.model.owned(byView: drafting).isEmpty)
        // Model elements and mixed views can't make a detail group.
        #expect(DetailGroups.members([b.plan], b.model).isEmpty)
    }

    // MARK: Find, replace and spelling data

    @Test func findReplaceInTextNotesAndTagValues() throws {
        let b = AnnotBench()
        var room: ElementID!
        b.perform("Content") { tx in
            tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(1, 1), text: "Plasterboard ceiling; plasterboard lining")), typeID: b.model.types(for: .textNotes).first?.id, ownerViewID: b.plan)
            room = tx.create(.rooms, name: "Plasterboard Store", data: .room(RoomData(point: Vec2(5, 4), number: "7")), levelID: b.level1)
        }
        b.click(TagTool(ctx: b.ctx(), commandID: .roomTag, categories: [.rooms]), Vec2(5, 4), hit: room)
        let matches = TextSearch.find("plasterboard", scope: .view, view: b.plan, b.model)
        #expect(matches.count == 2)
        let note = try #require(matches.first { if case .textNote = $0.source { true } else { false } })
        #expect(note.ranges.count == 2)
        #expect(note.replaced(with: "gypsum board") == "gypsum board ceiling; gypsum board lining")
        #expect(TextSearch.find("plasterboard", TextSearch.Options(matchCase: true), scope: .view, view: b.plan, b.model).count == 1, "only the lower-case note")
        #expect(TextSearch.find("board", TextSearch.Options(wholeWords: true), scope: .project, view: nil, b.model).isEmpty)
        var n = 0
        b.perform("Replace") { tx in n = try TextSearch.replace(matches, query: "plasterboard", with: "Gypsum", in: tx) }
        #expect(n == 2)
        #expect(b.model[room]?.name == "Gypsum Store", "replacing in a room tag renames the room")
        #expect(b.model.elements(.textNotes).first?.textNote?.text == "Gypsum ceiling; Gypsum lining")
        b.undo()
        #expect(b.model[room]?.name == "Plasterboard Store")
        let words = TextSearch.words("Don't paint the plasterbord")
        #expect(words.map(\.word) == ["Don't", "paint", "the", "plasterbord"])
        // Spelling corrections replace one word by its character range.
        b.perform("Fix") { tx in try TextSearch.replaceRange(note.source, 0..<12, with: "Gypsum", in: tx) }
        #expect(b.model.elements(.textNotes).first?.textNote?.text == "Gypsum ceiling; plasterboard lining")
    }
}
