import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

// MARK: - Place Rooms Automatically

@Suite("Automatic room placement")
struct AutomaticRoomTests {
    @Test func placesOneRoomPerRegionAndSkipsWallMaterial() throws {
        var box = try Fx.box { tx, ids, _ in
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(4, 0), Vec2(4, 8))))), levelID: ids.levels[0])
        }
        let regions = RoomGeometry.unoccupiedRegions(level: box.l1, box.model)
        #expect(regions.count == 2, "two halves; the wall ring itself is not a region")
        var created: [ElementID] = []
        let l1 = box.l1
        try Fx.commit(&box.model) { tx in created = RoomPlacement.placeAutomatically(level: l1, in: tx) }
        #expect(created.count == 2)
        let rooms = created.map { box.model[$0]! }
        #expect(rooms.map { $0.room!.number } == ["101", "102"])
        #expect(rooms.allSatisfy { RoomGeometry.boundary($0, box.model).state == .bounded })
        let areas = rooms.map { RoomGeometry.boundary($0, box.model).area }.sorted()
        #expect(Fx.approx(areas[0], 3.9 * 7.8, 1e-6) && Fx.approx(areas[1], 5.9 * 7.8, 1e-6))
        // Nothing left to fill.
        #expect(RoomGeometry.unoccupiedRegions(level: box.l1, box.model).isEmpty)
        try Fx.commit(&box.model) { tx in #expect(RoomPlacement.placeAutomatically(level: l1, in: tx).isEmpty) }
    }

    @Test func existingRoomsKeepTheirRegion() throws {
        var box = try Fx.box { tx, ids, _ in
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(4, 0), Vec2(4, 8))))), levelID: ids.levels[0])
            tx.create(.rooms, name: "Kept", data: .room(RoomData(point: Vec2(2, 4), number: "101")), levelID: ids.levels[0])
        }
        var created: [ElementID] = []
        let l1 = box.l1
        try Fx.commit(&box.model) { tx in created = RoomPlacement.placeAutomatically(level: l1, in: tx) }
        #expect(created.count == 1)
        #expect(box.model[created[0]]!.room!.number == "102")
        #expect(box.model[created[0]]!.room!.point.x > 4)
    }

    @MainActor @Test func roomToolPlacesAndTagsAutomatically() {
        let (m, ids) = Fx.template()
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        session.perform("Box") { tx in _ = Fx.boxWalls(tx, ids) }
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        let tool = RoomTool(ctx: ctx)
        #expect(tool.placeAutomatically() == 1)
        let room = session.model.elements(.rooms).first!
        #expect(session.model.tags(of: room.id).count == 1, "Tag on Placement applies")
        tool.tagOnPlacement = false
        #expect(tool.placeAutomatically() == 0)
    }

    /// Courtyard House: removing the ground floor rooms and placing automatically fills every enclosed region once.
    @Test func courtyardGroundFloorGetsOneRoomPerEnclosedRegion() throws {
        var m = Fx.isolated(CourtyardHouse.make())
        let level = m.levels[0].id
        let original = m.elements(.rooms).filter { $0.levelID == level && RoomGeometry.boundary($0, m).state == .bounded }
        #expect(!original.isEmpty)
        let points = original.compactMap { $0.room?.point }
        try Fx.commit(&m) { tx in for r in original { tx.delete(r.id) } }
        let regions = RoomGeometry.unoccupiedRegions(level: level, m)
        var created: [ElementID] = []
        try Fx.commit(&m) { tx in created = RoomPlacement.placeAutomatically(level: level, in: tx) }
        #expect(created.count == regions.count)
        let placed = created.map { m[$0]! }
        let states = placed.map { RoomGeometry.boundary($0, m).state }
        #expect(states.allSatisfy { $0 == .bounded }, "every automatic room is bounded and none is redundant")
        #expect(Set(placed.map { $0.room!.number }).count == placed.count, "numbers are unique")
        // Each region the model's own rooms occupied now holds exactly one automatic room.
        for p in points {
            let holders = placed.filter { RoomGeometry.boundary($0, m).profile?.contains(p) == true }
            #expect(holders.count == 1, "region at \(p)")
        }
        #expect(RoomGeometry.unoccupiedRegions(level: level, m).isEmpty)
    }
}

// MARK: - Colour schemes

@Suite("Colour fill schemes")
struct ColorSchemeTests {
    /// A 10 × 8 box split into three rooms: Office, Lab, Office departments.
    func scene(scheme: ColorSchemeData = .department) throws -> (Fx.Box, [ElementID], ElementID) {
        var rooms: [ElementID] = [], schemeID: ElementID!
        var box = try Fx.box { tx, ids, _ in
            for x in [3.0, 6.0] {
                tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(x, 0), Vec2(x, 8))))), levelID: ids.levels[0])
            }
            for (i, dept) in ["Office", "Lab", "Office"].enumerated() {
                rooms.append(tx.create(.rooms, name: "R\(i)", data: .room(RoomData(point: Vec2(1.5 + Double(i) * 3, 4), number: "10\(i)")), levelID: ids.levels[0]) {
                    $0.params[ParameterID("room.department")] = .text(dept)
                })
            }
            schemeID = tx.create(.colorSchemes, name: "Department", data: .colorScheme(scheme))
        }
        let plan = box.ids.planViews[box.l1]!
        try Fx.commit(&box.model) { tx in tx.update(plan) { $0.view?.colorSchemeID = schemeID } }
        return (box, rooms, schemeID)
    }

    func fills(_ g: ViewGraphics) -> [GFill] {
        g.items.filter { $0.elementID == nil && $0.layer == .fills && ($0.category == .rooms || $0.category == .areas) }.flatMap { item in
            item.primitives.compactMap { if case .fill(_, let f) = $0 { return f }; return nil }
        }
    }

    @Test func departmentSchemeFillsOneColourPerValueAndListsValuesInUse() throws {
        var (box, _, _) = try scene()
        let plan = box.ids.planViews[box.l1]!
        let g = ViewGraphicsBuilder(model: box.model, view: box.model[plan]!, temporary: TemporaryVisibility()).build()
        let f = fills(g)
        #expect(f.count == 3, "one fill per room")
        #expect(Set(f.map(\.color)).count == 2, "one colour per department")
        let rows = try #require(ColorFill.legendRows(view: box.model[plan]!, box.model))
        #expect(rows.rows.map { ColorFill.label(rows.scheme, row: $0, box.model) }.sorted() == ["Lab", "Office"])
        // A legend element renders a swatch and a label per row in use.
        var legend: ElementID!
        try Fx.commit(&box.model) { tx in legend = tx.create(.colorFillLegends, data: .colorFillLegend(ColorFillLegendData(position: Vec2(12, 8))), ownerViewID: plan) }
        let g2 = ViewGraphicsBuilder(model: box.model, view: box.model[plan]!, temporary: TemporaryVisibility()).build()
        let item = try #require(g2.items.first { $0.elementID == legend })
        let texts = item.primitives.compactMap { if case .text(let t) = $0 { return t.string }; return nil }
        #expect(texts == ["Department Legend", "Office", "Lab"] || texts == ["Department Legend", "Lab", "Office"])
        #expect(item.primitives.filter { if case .fill = $0 { return true }; return false }.count == 2)
    }

    @Test func storedRowsKeepTheirColoursAndHiddenRowsAreSkipped() throws {
        var s = ColorSchemeData.department
        s.entries = [ColorFillEntry(value: "Lab", color: RGBColor(1, 0, 0), visible: false)]
        let (box, _, _) = try scene(scheme: s)
        let plan = box.ids.planViews[box.l1]!
        let f = fills(ViewGraphicsBuilder(model: box.model, view: box.model[plan]!, temporary: TemporaryVisibility()).build())
        #expect(f.count == 2, "the hidden Lab row is not filled")
        #expect(!f.contains { $0.color == RGBColor(1, 0, 0) })
        let rows = try #require(ColorFill.legendRows(view: box.model[plan]!, box.model))
        #expect(rows.rows.map { ColorFill.label(rows.scheme, row: $0, box.model) } == ["Office"])
    }

    @Test func rangeSchemeBandsByArea() throws {
        var s = ColorSchemeData(category: .rooms, title: "Area", parameter: ParameterID("q.area"), parameterName: "Area", parameterType: .area, mode: .byRange)
        s.entries = [ColorFillEntry(lower: nil, color: RGBColor(1, 0, 0)), ColorFillEntry(lower: 20, color: RGBColor(0, 1, 0)), ColorFillEntry(lower: 25, color: RGBColor(0, 0, 1))]
        let (box, rooms, _) = try scene(scheme: s)
        // Room widths 2.9, 2.8, 3.9 m by 7.8 m: 22.62, 21.84, 30.42 m².
        let idx = rooms.map { ColorFill.entryIndex(for: box.model[$0]!, in: s, box.model) }
        #expect(idx == [1, 1, 2])
        #expect(ColorFill.label(s, row: 0, box.model).hasPrefix("Less than"))
        #expect(ColorFill.label(s, row: 2, box.model).hasSuffix("or more"))
        let plan = box.ids.planViews[box.l1]!
        let f = fills(ViewGraphicsBuilder(model: box.model, view: box.model[plan]!, temporary: TemporaryVisibility()).build())
        #expect(f.filter { $0.color == RGBColor(0, 1, 0) }.count == 2 && f.filter { $0.color == RGBColor(0, 0, 1) }.count == 1)
    }

    @Test func sectionShowsColourFillOfCutRooms() throws {
        var (box, _, schemeID) = try scene()
        var section: ElementID!
        try Fx.commit(&box.model) { tx in
            var v = ViewData(kind: .section, scale: 100)
            v.viewDirection = Vec2(0, 1)
            v.planeOrigin = Vec3(-1, 4, 0)
            v.colorSchemeID = schemeID
            section = tx.create(.views, name: "S", data: .view(v))
        }
        let g = ViewGraphicsBuilder(model: box.model, view: box.model[section]!, temporary: TemporaryVisibility()).build()
        let f = fills(g)
        #expect(f.count == 3)
        #expect(Set(f.map(\.color)).count == 2)
    }

    @Test func autoColoursAreStableAndAvoidTakenColours() {
        let a = ColorFill.autoColor(for: "Office", avoiding: [])
        #expect(a == ColorFill.autoColor(for: "Office", avoiding: []))
        #expect(ColorFill.autoColor(for: "Office", avoiding: [a]) != a)
        let s = ColorFill.completed(.department, values: ["B", "A", "B", ""])
        #expect(s.entries.map(\.value) == ["", "A", "B"])
        #expect(Set(s.entries.map(\.color)).count == 3)
    }

    @Test func viewParameterAssignsOnlyMatchingSchemes() throws {
        var (box, _, schemeID) = try scene()
        let plan = box.ids.planViews[box.l1]!
        var areaScheme: ElementID!
        try Fx.commit(&box.model) { tx in
            areaScheme = tx.create(.colorSchemes, name: "Areas", data: .colorScheme(ColorSchemeData(category: .areas, title: "A", parameter: ParameterID("name"), parameterName: "Name")))
        }
        #expect(Parameters.value(ParameterID("view.colorScheme"), of: box.model[plan]!, box.model)?.refValue == schemeID)
        let tx = TransactionContext(model: box.model, name: "Set")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("view.colorScheme"), to: .ref(areaScheme), on: plan, in: tx) }
    }
}

// MARK: - Area plans

@Suite("Area plans and schemes")
struct AreaPlanTests {
    @Test(arguments: [AreaBoundaryRule.gross, .rentable])
    func automaticBoundaryFollowsExteriorWalls(_ rule: AreaBoundaryRule) throws {
        var box = try Fx.box { tx, ids, _ in
            // An interior partition does not produce boundary lines.
            Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 8))
        }
        let t = WallGeometry.frame(box.model[box.walls[0]]!, box.model)!.thickness
        var plan: ElementID!, scheme: ElementID!
        let l1 = box.l1
        try Fx.commit(&box.model) { tx in
            AreaPlans.ensureDefaultSchemes(in: tx)
            scheme = tx.model.elements(.areaSchemes).first { $0.name == (rule == .gross ? AreaPlans.grossName : AreaPlans.rentableName) }!.id
            plan = AreaPlans.createAreaPlan(level: l1, scheme: scheme, automaticBoundary: true, in: tx)
        }
        #expect(box.model[plan]!.view!.kind == .areaPlan && box.model[plan]!.view!.areaSchemeID == scheme)
        let lines = box.model.elements(.areaBoundaryLines).filter { $0.params[AreaPlans.schemeParameter]?.refValue == scheme }
        #expect(lines.count == 4)
        // Place areas automatically in the plan: one area bounded by the lines.
        var created: [ElementID] = []
        try Fx.commit(&box.model) { tx in created = RoomPlacement.placeAutomatically(level: l1, in: tx, areaScheme: scheme) }
        #expect(created.count == 1)
        let b = RoomGeometry.boundary(box.model[created[0]]!, box.model)
        #expect(b.state == .bounded)
        let expected = rule == .gross ? (10 + t) * (8 + t) : (10 - t) * (8 - t)
        #expect(Fx.approx(b.area, expected, 1e-6))
        // Running again does not duplicate boundary lines.
        try Fx.commit(&box.model) { tx in #expect(AreaPlans.createAutomaticBoundary(level: l1, scheme: scheme, in: tx) == 0) }
        // The area plan draws only its scheme's areas.
        let g = ViewGraphicsBuilder(model: box.model, view: box.model[plan]!, temporary: TemporaryVisibility()).build()
        #expect(g.items.contains { $0.elementID == created[0] })
    }

    @Test func defaultSchemesAreCreatedOnce() throws {
        var (m, _) = Fx.template()
        try Fx.commit(&m) { tx in AreaPlans.ensureDefaultSchemes(in: tx); AreaPlans.ensureDefaultSchemes(in: tx) }
        let names = AreaPlans.sortedSchemes(m).map(\.name)
        #expect(names.filter { $0 == AreaPlans.grossName }.count == 1 && names.filter { $0 == AreaPlans.rentableName }.count == 1)
        #expect(m.elements(.areaSchemes).first { $0.name == AreaPlans.rentableName }?.areaScheme?.rule == .rentable)
    }

    @Test func areasOfOtherSchemesAreNotShown() throws {
        var box = try Fx.box()
        var gross: ElementID!, rentable: ElementID!, grossPlan: ElementID!, rentArea: ElementID!
        let l1 = box.l1
        try Fx.commit(&box.model) { tx in
            AreaPlans.ensureDefaultSchemes(in: tx)
            gross = tx.model.elements(.areaSchemes).first { $0.name == AreaPlans.grossName }!.id
            rentable = tx.model.elements(.areaSchemes).first { $0.name == AreaPlans.rentableName }!.id
            grossPlan = AreaPlans.createAreaPlan(level: l1, scheme: gross, automaticBoundary: true, in: tx)
            AreaPlans.createAreaPlan(level: l1, scheme: rentable, automaticBoundary: true, in: tx)
        }
        try Fx.commit(&box.model) { tx in rentArea = RoomPlacement.placeAutomatically(level: l1, in: tx, areaScheme: rentable).first }
        let g = ViewGraphicsBuilder(model: box.model, view: box.model[grossPlan]!, temporary: TemporaryVisibility()).build()
        #expect(!g.items.contains { $0.elementID == rentArea })
        let shownLines = g.items.filter { $0.category == .areaBoundaryLines }.compactMap(\.elementID)
        #expect(shownLines.count == 4)
        #expect(shownLines.allSatisfy { box.model[$0]?.params[AreaPlans.schemeParameter]?.refValue == gross })
    }

    @Test func olderFilesDecodeWithoutNewFields() throws {
        let data = try JSONEncoder().encode(ViewData(kind: .floorPlan))
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "colorSchemeID"); obj.removeValue(forKey: "areaSchemeID")
        let v = try JSONDecoder().decode(ViewData.self, from: JSONSerialization.data(withJSONObject: obj))
        #expect(v.colorSchemeID == nil && v.areaSchemeID == nil)
        let s = try JSONDecoder().decode(AreaSchemeData.self, from: Data(#"{"description":"Old"}"#.utf8))
        #expect(s.rule == .gross && s.description == "Old")
    }
}

// MARK: - Tag All and entire-wall dimensions

@MainActor
@Suite("Tag All and entire-wall dimensions")
struct AnnotationWorkflowTests {
    @Test func tagAllOnlySelectedTagsOnlyTheSelection() throws {
        var a: ElementID!, b: ElementID!, door: ElementID!
        var box = try Fx.box { tx, ids, walls in
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(4, 0), Vec2(4, 8))))), levelID: ids.levels[0])
            a = tx.create(.rooms, name: "A", data: .room(RoomData(point: Vec2(2, 4), number: "1")), levelID: ids.levels[0])
            b = tx.create(.rooms, name: "B", data: .room(RoomData(point: Vec2(7, 4), number: "2")), levelID: ids.levels[0])
            door = Fx.door(tx, ids, host: walls[0], at: Vec2(2, 0))
        }
        let plan = box.ids.planViews[box.l1]!
        let visible: Set<ElementID> = [a, b, door]
        let untagged = TagAll.untagged(in: plan, visible: visible, box.model)
        #expect(untagged[.rooms] == [a, b] && untagged[.doors] == [door])
        let roomTag = try #require(TagAll.tagTypes(for: .rooms, box.model).first?.id)
        let doorTag = try #require(TagAll.tagTypes(for: .doors, box.model).first?.id)
        var options = TagAllOptions(tagTypes: [.rooms: roomTag, .doors: doorTag], onlyElements: [b], leader: true, leaderLength: 0.01, orientation: .vertical)
        try Fx.commit(&box.model) { tx in #expect(TagAll.run(options, view: plan, visible: visible, scale: 100, in: tx) == 1) }
        #expect(box.model.tags(of: a).isEmpty && box.model.tags(of: door).isEmpty)
        let tag = try #require(box.model.tags(of: b).first?.tag)
        #expect(tag.hasLeader && tag.orientation == .vertical)
        #expect(Fx.approx(tag.head.distance(to: Vec2(7, 4)), 1.0, 1e-9), "10 mm on paper at 1:100")
        // Everything else, without the selection limit; already-tagged elements are skipped.
        options.onlyElements = nil
        try Fx.commit(&box.model) { tx in #expect(TagAll.run(options, view: plan, visible: visible, scale: 100, in: tx) == 2) }
        #expect(TagAll.untagged(in: plan, visible: visible, box.model).isEmpty)
        // Only chosen categories are tagged.
        #expect(box.model.elements(.tags).count == 3)
    }

    func boxWithWindows() throws -> Fx.Box {
        try Fx.box { tx, ids, walls in
            Fx.window(tx, ids, host: walls[0], at: Vec2(3, 0))
            Fx.window(tx, ids, host: walls[0], at: Vec2(7, 0))
            Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 8))
            tx.create(.grids, name: "A", data: .grid(GridData(curve: .line(Segment2(Vec2(2, -2), Vec2(2, 10))))))
        }
    }

    @Test func entireWallWithTwoWindowsHasSixReferencesWithWidths() throws {
        let box = try boxWithWindows()
        let south = box.model[box.walls[0]]!
        let t = WallGeometry.frame(south, box.model)!.thickness
        let refs = try #require(EntireWallDimension.references(wall: south, options: EntireWallOptions(openings: .widths), box.model))
        #expect(refs.count == 6)
        let d = Element(id: ElementID(1), category: .dimensions, data: .dimension(DimensionData(kind: .aligned, references: refs, linePoint: Vec2(0, -2), direction: 0)))
        let values = DimensionQueries.measure(d, box.model)
        #expect(values.count == 5)
        #expect(Fx.approx(values.reduce(0, +), 10 + t, 1e-6), "corner walls: outside face to outside face")
        let w = InsertGeometry.openingSize(box.model.hosted(by: south.id)[0], box.model)!.width
        #expect(Fx.approx(values[1], w, 1e-6) && Fx.approx(values[3], w, 1e-6))
        #expect(Fx.approx(values[0], 3 + t / 2 - w / 2, 1e-6))
    }

    @Test func entireWallOptions() throws {
        let box = try boxWithWindows()
        let south = box.model[box.walls[0]]!
        let centers = try #require(EntireWallDimension.references(wall: south, options: EntireWallOptions(openings: .centers), box.model))
        #expect(centers.count == 4)
        let none = try #require(EntireWallDimension.references(wall: south, options: EntireWallOptions(openings: .none), box.model))
        #expect(none.count == 2)
        // Intersecting walls add both faces of the partition (and the inner faces of the corner walls); grids add their line.
        let all = try #require(EntireWallDimension.references(wall: south, options: EntireWallOptions(openings: .none, intersectingWalls: true, intersectingGrids: true), box.model))
        #expect(all.count == 2 + 2 + 2 + 1)
        let centerlines = try #require(EntireWallDimension.references(wall: south, options: EntireWallOptions(openings: .none, intersectingWalls: true, preference: .wallCenterlines), box.model))
        #expect(centerlines.count == 3)
        let d = Element(id: ElementID(1), category: .dimensions, data: .dimension(DimensionData(kind: .aligned, references: centerlines, linePoint: Vec2(0, -2), direction: 0)))
        #expect(DimensionQueries.measure(d, box.model).map { ($0 * 1000).rounded() / 1000 } == [5, 5])
    }

    @Test func dimensionToolEntireWallsPicksThenPlaces() throws {
        let box = try boxWithWindows()
        let session = DocumentSession(model: box.model)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: box.ids.planViews[box.l1]!)
        let tool = DimensionTool(ctx: ctx, kind: .aligned)
        tool.setOption("pick", .text(DimensionTool.Pick.entireWalls.rawValue))
        #expect(tool.options.contains { $0.id == "openings" })
        var i = ToolInput(point: Vec2(1, 0), rawPoint: Vec2(1, 0))
        i.hit = box.walls[0]
        tool.pointerDown(i)
        tool.pointerDown(ToolInput(point: Vec2(1, -2), rawPoint: Vec2(1, -2)))
        let dim = try #require(session.model.elements(.dimensions).first?.dimension)
        #expect(dim.references.count == 6)
        #expect(tool.escape() == .exitTool)
    }
}

@Suite("WP6b command aliases")
struct RoomAnnotationAliasTests {
    @Test func switcherAliases() {
        let a = CommandCatalog.defaultAliases
        #expect(a["RT"] == .roomTag)
        #expect(a["EL"] == .spotElevation)
        #expect(a["EV"] == .elevation)
        for id in [CommandID.placeRoomsAutomatically, .placeAreasAutomatically, .colorSchemes, .colorFillLegend, .areaPlan] {
            #expect(CommandCatalog.byID[id] != nil)
        }
    }
}

@Suite("Baseline and ordinate dimensions")
struct ChainDimensionTests {
    func texts(_ style: DimensionChainStyle?) throws -> [String] {
        var (m, _) = Fx.template()
        var d = DimensionData(kind: .aligned, references: [.fixed(Vec2(0, 0)), .fixed(Vec2(2, 0)), .fixed(Vec2(5, 0))], linePoint: Vec2(0, -1), direction: 0)
        d.chainStyle = style
        var id: ElementID!
        try Fx.commit(&m) { tx in id = tx.create(.dimensions, data: .dimension(d)) }
        let item = try #require(AnnotationRenderer.item(m[id]!, GraphicOverride(), model: m, scale: 100, builder: nil))
        return item.primitives.compactMap { if case .text(let t) = $0 { return t.string }; return nil }
    }

    @Test func layouts() throws {
        let continuous = try texts(nil)
        let baseline = try texts(.baseline)
        let ordinate = try texts(.ordinate)
        #expect(continuous.count == 2 && baseline.count == 2 && ordinate.count == 3)
        #expect(continuous != baseline, "baseline measures both from the first reference")
        #expect(ordinate[0] == "0")
        #expect(baseline.last == ordinate.last, "the farthest reference has the same value in both")
    }

    @Test func stringTypeIsAParameter() throws {
        var (m, _) = Fx.template()
        var id: ElementID!
        try Fx.commit(&m) { tx in
            id = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: [.fixed(.zero), .fixed(Vec2(3, 0))], linePoint: Vec2(0, -1))))
        }
        #expect(Parameters.value(ParameterID("dimension.chainStyle"), of: m[id]!, m)?.textValue == "Continuous")
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("dimension.chainStyle"), to: .text("Ordinate"), on: id, in: tx) }
        #expect(m[id]!.dimension!.chainStyle == .ordinate)
    }
}
