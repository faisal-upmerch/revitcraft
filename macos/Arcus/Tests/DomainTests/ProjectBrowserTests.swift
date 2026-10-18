import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

// BL-BROWSER: Project Browser tree, naming rules, view titles, level names, view ranges and view placement.

@Suite("Project Browser")
struct ProjectBrowserTests {
    func level(_ m: BIMModel, _ name: String) -> Element { m.levels.first { $0.name == name }! }
    func view(_ m: BIMModel, _ kind: ViewKind, _ name: String) -> Element { m.views.first { $0.view?.kind == kind && $0.name == name }! }

    // MARK: Tree

    @Test func topLevelNodesAreInReferenceOrderAndAlwaysShown() {
        let (m, _) = Fx.template()
        let tree = ProjectBrowserTree.build(m)
        #expect(tree.map(\.title) == ["Views (all)", "Legends", "Schedules/Quantities (all)", "Sheets (all)", "Families", "Groups", "Links"])
        #expect(tree[1].children?.isEmpty == true, "Legends is shown even without legends")
        #expect(tree[6].children?.isEmpty == true, "Links is shown even without links")
        #expect(tree[5].children?.map(\.title) == ["Detail", "Model"])
        // Even a filter that matches nothing keeps the fixed nodes.
        #expect(ProjectBrowserTree.build(m, filter: "zzzz").map(\.id) == tree.map(\.id))
    }

    @Test func viewFoldersFollowTheViewTypeOrder() {
        let (m, _) = Fx.template()
        let folders = ProjectBrowserTree.build(m)[0].children!.map(\.title)
        #expect(folders == ["Floor Plans", "Ceiling Plans", "Elevations (Building Elevation)", "3D Views"])
        let elevations = ProjectBrowserTree.find("views.Elevations", in: ProjectBrowserTree.build(m))!
        #expect(elevations.children!.map(\.title) == ["East", "North", "South", "West"])
    }

    @Test func camerasAndLegendsAndDependentsLiveWhereTheyBelong() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        var camera: ElementID!, legend: ElementID!, dependent: ElementID!
        try Fx.commit(&m) { tx in
            camera = try CameraViews.create(eye: Vec2(0, -10), target: .zero, levelID: ids.levels[0], in: tx)
            legend = tx.create(.views, name: "Door Legend", data: .view(ViewData(kind: .legend, scale: 50)))
            var d = tx.model[plan]!.view!
            d.parentViewID = plan
            dependent = tx.create(.views, name: "Level 1 - Dependent 1", data: .view(d), levelID: ids.levels[0])
        }
        let tree = ProjectBrowserTree.build(m)
        let threeD = ProjectBrowserTree.find("views.3D Views", in: tree)!
        #expect(threeD.children!.contains { $0.elementID == camera && $0.symbol == "camera" }, "cameras are listed under 3D Views")
        #expect(tree[1].children!.map(\.elementID) == [legend])
        #expect(ProjectBrowserTree.find("views.Legends", in: tree) == nil, "legends are not a view folder")
        let parent = ProjectBrowserTree.find(ProjectBrowserTree.viewNodeID(plan), in: tree)!
        #expect(parent.children?.map(\.elementID) == [dependent], "dependent views nest under their parent")
        #expect(ProjectBrowserTree.ancestors(of: ProjectBrowserTree.viewNodeID(dependent), in: tree)
                == ["views", "views.Floor Plans", ProjectBrowserTree.viewNodeID(plan)])
    }

    @Test func familiesAreCategoryFamilyType() throws {
        let (m, ids) = Fx.template()
        let doorType = ids.familyTypes[Fx.doorType]!
        let tree = ProjectBrowserTree.build(m)
        let doors = ProjectBrowserTree.find("f.\(Category.doors.rawValue)", in: tree)!
        let family = try #require(doors.children?.first { $0.title == "Door - Single Flush" })
        #expect(family.kind == .family)
        #expect(family.elementID == m[doorType]?.typeData?.familyID)
        #expect(family.children!.contains { $0.title == "900 x 2100" && $0.elementID == doorType && $0.kind == .type && $0.subtitle == "0" })
        #expect(!doors.children!.contains { $0.kind == .type }, "types never sit directly under a category")
    }

    @Test func filterMatchesFamilyOrType() throws {
        let (m, _) = Fx.template()
        let byFamily = ProjectBrowserTree.find("f.\(Category.doors.rawValue)", in: ProjectBrowserTree.build(m, filter: "single flush"))!
        let fam = try #require(byFamily.children?.first { $0.title == "Door - Single Flush" })
        #expect(fam.children!.count == m.types(for: .doors).filter { $0.typeData?.familyName == "Door - Single Flush" }.count, "a family match keeps every type")
        let byType = ProjectBrowserTree.build(m, filter: "820 x 2040")
        let doors = try #require(ProjectBrowserTree.find("f.\(Category.doors.rawValue)", in: byType))
        #expect(doors.children!.map(\.title) == ["Door - Single Flush"])
        #expect(doors.children![0].children!.map(\.title) == ["820 x 2040"])
        #expect(ProjectBrowserTree.find("views.Floor Plans", in: byType) == nil)
    }

    @Test func sheetsListPlacedViewsWithTypePrefixes() throws {
        var (m, ids) = Fx.template()
        let sheet = m.sheets[0].id
        let plan = ids.planViews[ids.levels[0]]!
        try Fx.commit(&m) { tx in try SheetPlacement.place(plan, onSheet: sheet, in: tx) }
        let node = ProjectBrowserTree.find(ProjectBrowserTree.sheetNodeID(sheet), in: ProjectBrowserTree.build(m))!
        #expect(node.title == "A101 - Unnamed")
        #expect(node.children?.map(\.title) == ["Floor Plan: Level 1"])
        #expect(ProjectBrowserTree.nodeID(forOpenable: plan, m) == "v\(plan.raw)")
    }

    // MARK: Titles and naming

    @Test func qualifiedTitles() throws {
        var (m, _) = Fx.template()
        #expect(ViewTitles.qualified(view(m, .floorPlan, "Level 1")) == "Floor Plan: Level 1")
        #expect(ViewTitles.qualified(view(m, .ceilingPlan, "Level 1")) == "Ceiling Plan: Level 1")
        #expect(ViewTitles.qualified(view(m, .elevation, "South")) == "Elevation: South")
        #expect(ViewTitles.qualified(view(m, .threeD, "{3D}")) == "3D View: {3D}")
        #expect(ViewTitles.qualified(m.sheets[0]) == "Sheet: A101 - Unnamed")
        #expect(ViewTitles.qualified(m.schedules[0]) == "Schedule: \(m.schedules[0].name)")
        try Fx.commit(&m) { tx in
            var s = ViewData(kind: .section); s.planeOrigin = Vec3(0, 0, 0); s.viewDirection = Vec2(0, 1)
            tx.create(.views, name: "Section 1", data: .view(s))
        }
        #expect(ViewTitles.qualified(view(m, .section, "Section 1")) == "Section: Section 1")
    }

    @Test func duplicateNamesAreCopyOf() {
        var taken: Set<String> = []
        let first = BrowserNaming.duplicateName(of: "Level 1") { taken.contains($0) }
        #expect(first == "Copy of Level 1")
        taken.insert(first)
        #expect(BrowserNaming.duplicateName(of: "Level 1") { taken.contains($0) } == "Copy (2) of Level 1")
        taken.insert("Copy (2) of Level 1")
        #expect(BrowserNaming.duplicateName(of: "Level 1") { taken.contains($0) } == "Copy (3) of Level 1")
        #expect(BrowserNaming.dependentName(of: "Level 1") { $0 == "Level 1 - Dependent 1" } == "Level 1 - Dependent 2")
        let (m, _) = Fx.template()
        // A floor plan "Copy of Level 1" doesn't block the ceiling plan's copy.
        #expect(BrowserNaming.duplicateViewName(view(m, .ceilingPlan, "Level 1"), in: m) == "Copy of Level 1")
    }

    @Test func renameRules() throws {
        let (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        #expect(BrowserNaming.renameProblem(plan, to: "", in: m) != nil)
        #expect(BrowserNaming.renameProblem(plan, to: "   ", in: m) != nil)
        #expect(BrowserNaming.renameProblem(plan, to: "Level 2", in: m)?.contains("already") == true, "same view type")
        #expect(BrowserNaming.renameProblem(plan, to: "Level 1", in: m) == nil, "its own name")
        #expect(BrowserNaming.renameProblem(plan, to: "South", in: m) == nil, "an elevation's name is free for a plan")
        #expect(BrowserNaming.renameProblem(plan, to: "  First Floor ", in: m) == nil)
        #expect(BrowserNaming.renameProblem(plan, to: "A:B", in: m) != nil)
        let door = ids.familyTypes[Fx.doorType]!
        #expect(BrowserNaming.renameProblem(door, to: "820 x 2040", in: m) != nil, "types are unique within their family")
        #expect(BrowserNaming.renameProblem(door, to: "Wide", in: m) == nil)
        #expect(BrowserNaming.familyRenameProblem("Door - Single Flush", category: .doors, to: "Door - Double Flush", in: m) != nil)
        #expect(BrowserNaming.familyRenameProblem("Door - Single Flush", category: .doors, to: "Door - Flush", in: m) == nil)
        let sheet = m.sheets[0].id
        #expect(BrowserNaming.sheetTitleProblem(sheet, number: "A102", name: "Plans", in: m) == nil)
        #expect(BrowserNaming.sheetTitleProblem(sheet, number: " ", name: "Plans", in: m) != nil)
        #expect(BrowserNaming.duplicateTypeName("900 x 2100", family: "Door - Single Flush", category: .doors, in: m) == "900 x 2100 2")
    }

    @Test func renameIsUndoableThroughTheNameParameter() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        let before = m
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("name"), to: .text("First Floor"), on: plan, in: tx) }
        #expect(m[plan]?.name == "First Floor")
        #expect(before[plan]?.name == "Level 1")
    }

    // MARK: Levels

    @Test func levelNamesIncrementTheLastCreatedNumber() throws {
        var (m, _) = Fx.template()
        #expect(LevelNaming.nextName(m) == "Level 3", "after Roof, the last numbered level was Level 2")
        try Fx.commit(&m) { tx in tx.create(.levels, name: "Level 5", data: .level(LevelData(elevation: 12))) }
        #expect(LevelNaming.nextName(m) == "Level 6")
        try Fx.commit(&m) { tx in tx.create(.levels, name: "L-09", data: .level(LevelData(elevation: 16))) }
        #expect(LevelNaming.nextName(m) == "L-10")
        #expect(LevelNaming.trailingNumber("Roof") == nil)
        #expect(LevelNaming.trailingNumber("Level 007")! == ("Level ", 7, 3))
    }

    // MARK: View range

    @Test func viewRangeRelativeLevels() throws {
        let (m, ids) = Fx.template()
        let l1 = ids.levels[0]
        var r = ViewRange.floorPlanDefault
        r.set(.top, level: .levelAbove, offset: 0)
        #expect(Fx.approx(r.z(.top, viewLevel: l1, in: m), 4.0))
        #expect(r.level(.top, viewLevel: l1) == .levelAbove)
        r.set(.top, level: .unlimited, offset: 0)
        #expect(r.z(.top, viewLevel: l1, in: m) >= ViewRange.unlimitedExtent)
        r.set(.depth, level: .levelBelow, offset: 0)
        #expect(r.z(.depth, viewLevel: l1, in: m) <= -ViewRange.unlimitedExtent, "no level below Level 1")
        r.set(.depth, level: .level(ids.levels[1]), offset: 0)
        #expect(r.problem(viewLevel: l1, in: m)?.contains("view depth") == true, "view depth above the bottom")
        r.set(.depth, level: .associated, offset: 0)
        #expect(r.problem(viewLevel: l1, in: m) == nil)
        r.set(.cut, level: .associated, offset: 5)
        #expect(r.problem(viewLevel: l1, in: m) == nil, "unlimited top is above any cut plane")
        r.set(.top, level: .associated, offset: 2)
        #expect(r.problem(viewLevel: l1, in: m)?.contains("top") == true)
        #expect(ViewRange.choices(for: .top, m).prefix(3) == [.associated, .levelAbove, .unlimited])
        // Old ranges keep reading as offsets from the associated level.
        #expect(ViewRange.floorPlanDefault.level(.bottom, viewLevel: l1) == .associated)
    }

    @Test func viewRangeRoundTripsThroughCodable() throws {
        var r = ViewRange.floorPlanDefault
        r.set(.top, level: .levelAbove, offset: 0.5)
        let back = try JSONDecoder().decode(ViewRange.self, from: JSONEncoder().encode(r))
        #expect(back == r)
        let legacy = try JSONDecoder().decode(ViewRange.self, from: Data(#"{"topOffset":2.3,"cutOffset":1.2,"bottomOffset":0,"depthOffset":0}"#.utf8))
        #expect(legacy.topAnchor == nil && legacy == ViewRange.floorPlanDefault)
    }

    @Test func planGraphicsUseTheLevelAbove() throws {
        var box = try Fx.box()
        let plan = box.plan.id
        try Fx.commit(&box.model) { tx in tx.update(plan) { $0.view?.viewRange.set(.top, level: .levelAbove, offset: 0) } }
        let g = PlanGraphics(builder: ViewGraphicsBuilder(model: box.model, view: box.model[plan]!), ceiling: false)
        #expect(Fx.approx(g.topZ, 4.0))
    }

    @Test func viewRangeParametersCheckAbsoluteHeightsForRelativeLevels() throws {
        var box = try Fx.box()
        let plan = box.plan.id
        try Fx.commit(&box.model) { tx in tx.update(plan) { $0.view?.viewRange.set(.top, level: .levelAbove, offset: 0) } }
        // Top at Level 2 (4 m): a 1.3 m cut is fine although the top offset is 0.
        try Fx.commit(&box.model) { tx in try Parameters.set(ParameterID("view.cutPlane"), to: .double(1.3), on: plan, in: tx) }
        #expect(Fx.approx(box.model[plan]!.view!.viewRange.cutOffset, 1.3))
        #expect(throws: (any Error).self) {
            try Fx.commit(&box.model) { tx in try Parameters.set(ParameterID("view.cutPlane"), to: .double(5), on: plan, in: tx) }
        }
    }

    // MARK: Placing views

    @Test func placeViewCandidatesArePrefixedSearchableAndSkipPlacedViews() throws {
        var (m, ids) = Fx.template()
        let sheet = m.sheets[0].id
        let plan = ids.planViews[ids.levels[0]]!
        var all = PlaceViewCandidates.list(forSheet: sheet, m)
        #expect(all.contains { $0.title == "Floor Plan: Level 1" })
        #expect(all.contains { $0.title == "Ceiling Plan: Level 1" })
        #expect(!all.contains { $0.title.hasPrefix("Sheet:") })
        let search = PlaceViewCandidates.list(forSheet: sheet, m, search: "level 1")
        #expect(search.map(\.title).sorted() == ["Ceiling Plan: Level 1", "Floor Plan: Level 1"])
        try Fx.commit(&m) { tx in try SheetPlacement.place(plan, onSheet: sheet, in: tx) }
        all = PlaceViewCandidates.list(forSheet: sheet, m)
        #expect(!all.contains { $0.id == plan }, "placed views are not offered again")
        #expect(all.contains { $0.id == m.schedules[0].id }, "schedules can go on many sheets")
    }

    @Test func multipleViewsAreTiledAroundTheCursor() throws {
        let centers = SheetPlacement.tiledCenters(sizes: [Vec2(0.2, 0.1), Vec2(0.1, 0.1)], at: Vec2(0.5, 0.3), gap: 0.01)
        #expect(Fx.approx(centers[0], Vec2(0.5 - 0.155 + 0.1, 0.3)))
        #expect(Fx.approx(centers[1], Vec2(0.5 + 0.155 - 0.05, 0.3)))
        var (m, ids) = Fx.template()
        let sheet = m.sheets[0].id
        let a = ids.planViews[ids.levels[0]]!, b = ids.planViews[ids.levels[1]]!
        let sizes = [a, b].map { SheetPlacement.paperSize(of: $0, m) }
        var result: (placed: [ElementID], refused: [String])!
        try Fx.commit(&m) { tx in result = try SheetPlacement.place([a, b], sizes: sizes, onSheet: sheet, at: Vec2(0.4, 0.3), in: tx) }
        #expect(result.placed.count == 2 && result.refused.isEmpty)
        #expect(m.sheet(containing: a)?.id == sheet && m.sheet(containing: b)?.id == sheet)
        // Placing an already-placed view is refused with a message.
        #expect(throws: TransactionError.self) { try Fx.commit(&m) { tx in try SheetPlacement.place([a], sizes: [sizes[0]], onSheet: sheet, at: .zero, in: tx) } }
        #expect(SheetPlacement.refusal(a, onSheet: sheet, m)?.contains("already placed") == true)
    }

    // MARK: Title blocks

    @Test func titleBlockTypeSetsTheSheetSize() throws {
        var (m, ids) = Fx.template()
        let sheet = m.sheets[0].id
        let a3 = try #require(ids.titleBlocks["A3 Title Block"])
        #expect(SheetTitleBlocks.paper(forTitleBlockType: a3, m) == .a3)
        try Fx.commit(&m) { tx in try SheetTitleBlocks.setTitleBlock(a3, on: sheet, in: tx) }
        #expect(m[sheet]?.sheet?.paper == .a3)
        #expect(m[sheet]?.sheet?.titleBlockTypeID == a3)
        if let archD = ids.titleBlocks["ARCH D Title Block"] { #expect(SheetTitleBlocks.paper(forTitleBlockType: archD, m) == .archD) }
    }

    // MARK: References

    @Test func elevationsAreReferencedByPlans() throws {
        var (m, ids) = Fx.template()
        let south = view(m, .elevation, "South")
        let refs = ViewReferences.referringViews(of: south.id, m)
        #expect(refs.contains { $0.id == ids.planViews[ids.levels[0]] })
        #expect(ViewReferences.referencingSheetAndDetail(of: south.id, m) == nil)
        let sheet = m.sheets[0].id
        let plan = ids.planViews[ids.levels[0]]!
        try Fx.commit(&m) { tx in try SheetPlacement.place(plan, onSheet: sheet, in: tx) }
        let ref = try #require(ViewReferences.referencingSheetAndDetail(of: south.id, m))
        #expect(ref.sheet == "A101" && ref.detail == "1")
    }

    @Test func templateCapturesTheView() throws {
        let (m, ids) = Fx.template()
        let v = m[ids.planViews[ids.levels[0]]!]!.view!
        let td = ViewTemplateData.capturing(v)
        #expect(td.appliesTo == .floorPlan && td.scale == v.scale && td.viewRange == v.viewRange)
    }
}
