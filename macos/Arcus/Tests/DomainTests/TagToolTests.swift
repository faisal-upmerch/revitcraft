import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

@MainActor
@Suite("Tag tools (W2-ANNOT)")
struct TagToolTests {
    func tag(_ b: AnnotBench) throws -> Element { try #require(b.model.allElements.filter { $0.tag != nil }.max { $0.id < $1.id }) }

    func door(_ b: AnnotBench, wall: Int = 0, at p: Vec2 = Vec2(5, 0), mark: String = "D7") -> ElementID {
        var id: ElementID!
        b.perform("Door") { tx in id = Fx.door(tx, b.ids, host: b.walls[wall], at: p, mark: mark) }
        return id
    }

    func stair(_ b: AnnotBench) -> ElementID {
        var id: ElementID!
        b.perform("Stair") { tx in
            id = tx.create(.stairs, data: .stair(StairData(origin: Vec2(2, 2), direction: 0, width: 1.1, topLevelID: b.ids.levels[1])),
                           typeID: b.ids.systemTypes["Stair"], levelID: b.level1)
        }
        return id
    }

    @Test func tagByCategoryFollowsTheTaggedElementsParameters() throws {
        let b = AnnotBench()
        let d = door(b)
        let tool = TagTool(ctx: b.ctx())
        tool.pointerMoved(b.input(Vec2(5, 0), hit: d))
        #expect(AnnotBench.strings(tool.preview.primitives) == ["D7"], "the tag previews before placing")
        b.click(tool, Vec2(5, 0), hit: d)
        let t = try tag(b)
        #expect(t.tag?.taggedID == d && t.ownerViewID == b.plan)
        #expect(b.model[b.model[t.typeID]?.typeData?.familyID]?.name == "Door Tag")
        #expect(b.strings(t.id) == ["D7"])
        #expect(b.item(t.id)?.hitPolygons.isEmpty == false)
        b.perform("Mark") { tx in try Parameters.set(ParameterID("mark"), to: .text("D12"), on: d, in: tx) }
        #expect(b.strings(t.id) == ["D12"], "tags show the current value")
        // Deleting the door deletes its tag; undo restores both.
        b.step { b.session.delete([d]) }
        #expect(b.model[t.id] == nil)
        b.undo()
        #expect(b.strings(t.id) == ["D12"])
        // Clicking empty space tags nothing.
        b.click(tool, Vec2(5, 4))
        #expect(b.model.elements(.tags).count == 1)
        #expect(b.messages.last?.contains("taggable") == true)
    }

    @Test func tagLeadersHaveMovableEndsAndElbows() throws {
        let b = AnnotBench()
        let d = door(b)
        let tool = TagTool(ctx: b.ctx())
        tool.setOption("leader", .bool(true))
        b.click(tool, Vec2(5, 0), hit: d)
        let t = try tag(b)
        #expect(t.tag?.hasLeader == true)
        #expect(t.tag!.head.distance(to: Vec2(5, 0)) > 1, "a leader tag sits away from the door (12 mm at 1:100)")
        let leader = AnnotBench.polylines(try b.prims(t.id)).first { $0.0.last?.isAlmostEqual(Vec2(5, 0), tolerance: 1e-6) == true }
        #expect(leader != nil, "the leader ends at the door")
        let grips = GripService.grips(for: t, b.model, viewKind: .floorPlan)
        let end = try #require(grips.first { $0.kind == .tagLeaderEnd })
        let elbow = try #require(grips.first { $0.kind == .tagLeaderElbow })
        b.perform("Elbow") { tx in GripService.apply(elbow, to: Vec2(4, 1), in: tx) }
        b.perform("End") { tx in GripService.apply(end, to: Vec2(4.6, 0), in: tx) }
        let pts = try #require(AnnotBench.polylines(try b.prims(t.id)).first { $0.0.last == Vec2(4.6, 0) }?.0)
        #expect(pts.contains(Vec2(4, 1)))
        b.undo()
        #expect(b.model[t.id]?.tag?.leaderEnd == nil)
    }

    @Test func tagsInSectionsAnchorAtTheElementsStationAndHeight() throws {
        let b = AnnotBench()
        let d = door(b, wall: 2, at: Vec2(5, 8))
        let section = b.section()
        let tool = TagTool(ctx: b.ctx(section))
        b.click(tool, Vec2(7, 1), hit: d)
        let t = try tag(b)
        #expect(t.ownerViewID == section)
        let head = t.tag!.head
        #expect(abs(head.x - 7) < 0.6, "u of the door (x = 5, section starting at x = −2): \(head)")
        #expect(head.y > 0.3 && head.y < 2.4, "about the door's mid-height: \(head)")
        #expect(b.strings(t.id, section) == ["D7"])
    }

    @Test func roomAreaAndMultiCategoryTags() throws {
        let b = AnnotBench()
        var room: ElementID!, area: ElementID!, chair: ElementID!
        b.perform("Content") { tx in
            room = tx.create(.rooms, name: "Office", data: .room(RoomData(point: Vec2(5, 4), number: "101")), levelID: b.level1)
            area = tx.create(.areas, name: "Gross Floor", data: .room(RoomData(point: Vec2(5, 4), number: "")), levelID: b.level1)
            chair = tx.create(.furniture, data: .component(ComponentData(location: Vec2(2, 2))), typeID: b.model.types(for: .furniture).first?.id, levelID: b.level1) { $0.mark = "F1" }
        }
        let rt = TagTool(ctx: b.ctx(), commandID: .roomTag, categories: [.rooms])
        b.click(rt, Vec2(5, 4), hit: room)
        let roomTag = try tag(b)
        #expect(Set(b.strings(roomTag.id)).isSuperset(of: ["Office", "101"]))

        let at = TagTool(ctx: b.ctx(), commandID: .areaTag, categories: [.areas])
        b.click(at, Vec2(5, 4), hit: area)
        let areaTag = try tag(b)
        #expect(b.model[b.model[areaTag.typeID]?.typeData?.familyID]?.name == AnnotationLibrary.areaTagName)
        #expect(b.strings(areaTag.id).contains("Gross Floor"))

        let mt = TagTool(ctx: b.ctx(), commandID: .multiCategoryTag)
        b.click(mt, Vec2(2, 2), hit: chair)
        let multi = try tag(b)
        #expect(AnnotationLibrary.isMultiCategory(b.model[multi.typeID]!, b.model))
        #expect(b.strings(multi.id) == ["F1"])
        // Tag by Category prefers the category's own tag.
        #expect(TagTool.defaultTagType(for: .furniture, b.model).map { !AnnotationLibrary.isMultiCategory(b.model[$0]!, b.model) } == true)
    }

    func layeredWall(_ b: AnnotBench) -> ElementID {
        var id: ElementID!
        b.perform("Wall") { tx in id = Fx.wall(tx, b.ids, Vec2(0, -5), Vec2(10, -5), type: Fx.brick) }
        return id
    }

    @Test func materialTagsNameTheLayerUnderThePointer() throws {
        let b = AnnotBench()
        let w = layeredWall(b)
        let f = try #require(WallGeometry.frame(b.model[w]!, b.model))
        let ext = f.exteriorFace.closestPoint(to: Vec2(5, -5))
        let inward = (Vec2(5, -5) - ext).normalized
        let tool = SpecialTagTool(ctx: b.ctx(), kind: .material)
        b.click(tool, ext + inward * 0.05, hit: w)     // in the brick
        b.click(tool, Vec2(5, -7))
        let t1 = try tag(b)
        #expect(t1.tag?.kind == .material && t1.category == .tags)
        #expect(b.strings(t1.id) == ["Brick, Common"])
        b.click(tool, ext + inward * 0.15, hit: w)     // in the insulation
        b.click(tool, Vec2(6, -7))
        #expect(b.strings(try tag(b).id) == ["Rigid Insulation"])
        #expect(AnnotBench.polylines(try b.prims(try tag(b).id)).contains { $0.0.last?.isAlmostEqual(ext + inward * 0.15, tolerance: 1e-6) == true },
                "the leader points at the picked layer")
        // Material parameter can retarget the tag.
        let entry = try #require(Parameters.instanceEntries(b.model[t1.id]!, b.model).first { $0.name == "Material" })
        let plaster = try #require(b.ids.materials["Plaster"])
        b.perform("Material") { tx in try Parameters.set(entry.id, to: .ref(plaster), on: t1.id, in: tx) }
        #expect(b.strings(t1.id) == ["Plaster"])
    }

    @Test func elementMaterialAndUserKeynotes() throws {
        let b = AnnotBench()
        let wallType = try #require(b.model[b.walls[0]]?.typeID)
        let cmu = try #require(b.ids.materials["Concrete Masonry Units"])
        b.perform("Keynotes") { tx in
            try Parameters.set(ParameterID("type.keynote"), to: .text("A2.03"), on: wallType, in: tx)
            tx.update(cmu) { $0.material?.keynote = "A2.05" }
        }
        let el = SpecialTagTool(ctx: b.ctx(), kind: .keynoteElement)
        b.click(el, Vec2(5, 0), hit: b.walls[0]); b.click(el, Vec2(5, -1.5))
        let k1 = try tag(b)
        #expect(b.strings(k1.id) == ["A2.03"])
        #expect(AnnotBench.polylines(try b.prims(k1.id)).count >= 2, "boxed key with a leader")
        let display = try #require(Parameters.instanceEntries(b.model[k1.id]!, b.model).first { $0.name == "Keynote Display" })
        b.perform("Display") { tx in try Parameters.set(display.id, to: .text("Key and Text"), on: k1.id, in: tx) }
        #expect(b.strings(k1.id) == ["A2.03 Concrete block inner leaf"])

        let mat = SpecialTagTool(ctx: b.ctx(), kind: .keynoteMaterial)
        b.click(mat, Vec2(5, 0), hit: b.walls[0]); b.click(mat, Vec2(6, -1.5))
        #expect(b.strings(try tag(b).id) == ["A2.05"])

        let user = SpecialTagTool(ctx: b.ctx(), kind: .keynoteUser)
        #expect(user.options.contains { $0.id == "key" })
        user.setOption("key", .text("A7.01 Paving slabs on sand bed"))
        user.setOption("display", .text("Text"))
        b.click(user, Vec2(5, 8), hit: b.walls[2]); b.click(user, Vec2(5, 9.5))
        let k3 = try tag(b)
        #expect(k3.tag?.keynote == "A7.01")
        #expect(b.strings(k3.id) == ["Paving slabs on sand bed"])
        // Keynotes don't count as the element's category tag.
        #expect(TagAll.untagged(in: b.plan, visible: [b.walls[0]], b.model)[.walls] == [b.walls[0]])
    }

    @Test func treadNumbersStairPathAndSpanDirection() throws {
        let b = AnnotBench()
        let s = stair(b)
        let layout = try #require(StairGeometry.layout(b.model[s]!, b.model))
        let treads = layout.runs.reduce(0) { $0 + $1.risers - 1 }
        let numbers = SpecialTagTool(ctx: b.ctx(), kind: .treadNumber)
        b.click(numbers, Vec2(3, 2.3), hit: s)
        let tn = try tag(b)
        let strings = b.strings(tn.id)
        #expect(strings.count == treads)
        #expect(strings.first == "1" && strings.last == "\(treads)")
        #expect(AnnotBench.texts(try b.prims(tn.id)).allSatisfy { $0.position.y > 2 }, "numbers on the clicked side of the run")

        let path = SpecialTagTool(ctx: b.ctx(), kind: .stairPath)
        b.click(path, Vec2(3, 2), hit: s)
        let sp = try tag(b)
        #expect(sp.category == .genericAnnotations)
        #expect(b.strings(sp.id).contains("UP"))
        #expect(!AnnotBench.polylines(try b.prims(sp.id)).isEmpty)

        var floor: ElementID!
        b.perform("Floor") { tx in
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 6))))), typeID: b.ids.floorTypes["Concrete Slab 200mm"], levelID: b.level1)
        }
        let span = SpecialTagTool(ctx: b.ctx(), kind: .spanDirection)
        b.click(span, Vec2(5, 3), hit: floor)
        let sd = try tag(b)
        #expect(AnnotBench.fills(try b.prims(sd.id)).count == 2, "a half arrow at each end")
        let line = try #require(AnnotBench.polylines(try b.prims(sd.id)).first?.0)
        #expect(abs(line[0].y - line[1].y) < 1e-9, "spans along the floor's longest edge (x)")
        // Plan-only tools refuse sections.
        let section = b.section()
        let inSection = SpecialTagTool(ctx: b.ctx(section), kind: .treadNumber)
        let before = b.model.elements(.tags).count
        b.click(inSection, Vec2(4, 1), hit: s)
        #expect(b.model.elements(.tags).count == before)
    }

    @Test func viewReferencesScaleBarsAndBeamAnnotations() throws {
        let b = AnnotBench()
        let section = b.section()
        let ref = SpecialTagTool(ctx: b.ctx(), kind: .viewReference)
        ref.setOption("view", .text(b.model[section]!.name))
        b.click(ref, Vec2(12, 2))
        let vr = try tag(b)
        let item = try #require(b.item(vr.id))
        #expect(item.targetViewID == section, "double-click opens the referenced view")
        #expect(AnnotBench.strings(item.primitives).contains(b.model[section]!.name))

        let bar = SpecialTagTool(ctx: b.ctx(), kind: .scaleBar)
        b.click(bar, Vec2(0, -3))
        let sb = try tag(b)
        #expect(sb.tag?.taggedID == b.plan)
        let labels = b.strings(sb.id)
        #expect(labels == ["0", "1", "2", "3", "4", "m"], "four 1 m blocks at 1:100 (40 mm of paper): \(labels)")
        b.perform("Scale") { tx in tx.update(b.plan) { $0.view?.scale = 200 } }
        #expect(b.strings(sb.id) == ["0", "2", "4", "6", "8", "m"])

        var beam: ElementID!
        b.perform("Beam") { tx in
            beam = tx.create(.structuralFraming, data: .beam(BeamData(curve: .line(Segment2(Vec2(0, 4), Vec2(10, 4))))),
                             typeID: b.ids.systemTypes["Steel Beam 200 x 400"], levelID: b.level1) { $0.mark = "B1" }
        }
        var n = 0
        b.perform("Beams") { tx in n = BeamAnnotations.run(view: b.plan, visible: Set(b.model.allElements.map(\.id)), in: tx) }
        #expect(n == 1)
        let bt = try #require(b.model.tags(of: beam).first)
        #expect(b.strings(bt.id) == ["B1"])
        b.perform("Again") { tx in n = BeamAnnotations.run(view: b.plan, visible: [beam], in: tx) }
        #expect(n == 0, "tagged beams are skipped")
    }
}
