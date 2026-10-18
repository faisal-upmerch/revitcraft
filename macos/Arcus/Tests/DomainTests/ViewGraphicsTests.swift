import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("View graphics and visibility")
struct ViewGraphicsTests {
    struct Scene {
        var model: BIMModel
        let ids: ProjectTemplates.Ids
        let walls: [ElementID]
        let partition: ElementID
        let door: ElementID
        let window: ElementID
        let floor: ElementID
        let ceiling: ElementID
        let room: ElementID
        let box: ElementID
        var plan: ElementID { ids.planViews[ids.levels[0]]! }
        var rcp: ElementID { ids.ceilingViews[ids.levels[0]]! }
    }

    func scene(wallType: String = Fx.generic) throws -> Scene {
        var (m, ids) = Fx.template()
        var walls: [ElementID] = [], part: ElementID!, door: ElementID!, win: ElementID!, floor: ElementID!, ceil: ElementID!, room: ElementID!, box: ElementID!
        try Fx.commit(&m) { tx in
            walls = Fx.boxWalls(tx, ids, type: wallType)
            part = Fx.wall(tx, ids, Vec2(5, 0), Vec2(5, 8), type: Fx.generic)
            door = Fx.door(tx, ids, host: walls[0], at: Vec2(2, 0), mark: "D1")
            win = Fx.window(tx, ids, host: walls[2], at: Vec2(7, 8), sill: 0.9)
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(10, 8))))), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            ceil = tx.create(.ceilings, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(0.1, 0.1), max: Vec2(4.9, 7.9))), offset: 2.7)),
                             typeID: ids.ceilingTypes["Plasterboard Ceiling"], levelID: ids.levels[0])
            room = tx.create(.rooms, name: "Office", data: .room(RoomData(point: Vec2(2, 4), number: "101")), levelID: ids.levels[0])
            box = tx.create(.genericModels, data: .component(ComponentData(location: Vec2(7, 4))), typeID: ids.familyTypes["Generic Box: 1000 x 1000 x 1000"], levelID: ids.levels[0])
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(Vec2(0, 6), Vec2(5, 6))))), levelID: ids.levels[0])
            tx.create(.grids, name: "1", data: .grid(GridData(curve: .line(Segment2(Vec2(0, -3), Vec2(0, 11))))))
            tx.create(.tags, data: .tag(TagData(taggedID: door, head: Vec2(2, -1))), typeID: ids.familyTypes["Door Tag: Standard"], ownerViewID: ids.planViews[ids.levels[0]])
        }
        return Scene(model: m, ids: ids, walls: walls, partition: part, door: door, window: win, floor: floor, ceiling: ceil, room: room, box: box)
    }

    func build(_ m: BIMModel, _ view: ElementID, _ temp: TemporaryVisibility = TemporaryVisibility()) -> ViewGraphics {
        ViewGraphicsBuilder(model: m, view: m[view]!, temporary: temp).build()
    }
    func categories(_ g: ViewGraphics) -> Set<ArcusDomain.Category> { Set(g.items.map(\.category)) }
    func ids(_ g: ViewGraphics) -> Set<ElementID> { Set(g.items.compactMap(\.elementID)) }
    func edit(_ s: inout Scene, _ view: KeyPath<Scene, ElementID>, _ body: @escaping (inout ViewData) -> Void) throws {
        let id = s[keyPath: view]
        try Fx.commit(&s.model) { tx in tx.update(id) { e in body(&e.view!) } }
    }

    @Test func floorPlanShowsCutWallsInsertsAndRooms() throws {
        let s = try scene()
        let g = build(s.model, s.plan)
        #expect(g.items.contains { $0.category == .walls && $0.layer == .cut })
        #expect(categories(g).isSuperset(of: [.walls, .doors, .windows, .floors, .rooms, .genericModels, .roomSeparationLines, .grids, .tags]))
        #expect(!categories(g).contains(.ceilings))
        #expect(g.items.map(\.layer) == g.items.map(\.layer).sorted(), "items are ordered by layer")
        #expect(g.extents.contains(Rect2(min: Vec2(-0.1, -0.1), max: Vec2(10.1, 8.1))))
        #expect(g.scale == 100)
        // Every wall appears exactly once as a cut item.
        #expect(g.items.filter { $0.category == .walls && $0.layer == .cut }.count == 5)
    }

    @Test func reflectedCeilingPlanShowsCeilingsNotDoorsOrFurniture() throws {
        let s = try scene()
        let g = build(s.model, s.rcp)
        let c = categories(g)
        #expect(c.contains(.ceilings))
        #expect(c.contains(.walls))
        #expect(c.contains(.windows), "the window head (2.4 m) is above the 2.3 m RCP cut")
        #expect(!c.contains(.doors))
        #expect(!c.contains(.floors))
        #expect(!c.contains(.genericModels))
    }

    @Test func sectionCutsWallsItCrosses() throws {
        var s = try scene()
        var sid: ElementID!
        try Fx.commit(&s.model) { tx in
            var v = ViewData(kind: .section)
            v.planeOrigin = Vec3(5, 4, 0)
            v.viewDirection = Vec2(0, 1)
            v.farClip = 10
            sid = tx.create(.views, name: "Section A", data: .view(v))
        }
        let g = build(s.model, sid)
        let cut = Set(g.items.filter { $0.layer == .cut }.compactMap(\.elementID))
        #expect(cut.isSuperset(of: [s.walls[1], s.walls[3]]), "east and west walls are cut")
        #expect(!cut.contains(s.walls[0]), "the south wall is behind the plane")
        #expect(!cut.contains(s.walls[2]), "the north wall is seen in projection")
        #expect(ids(g).contains(s.walls[2]))
        #expect(categories(g).contains(.levels))
        #expect(categories(g).contains(.grids), "grid 1 (x = 0) crosses the section plane")
    }

    @Test func elevationProjectsWithoutCutting() throws {
        let s = try scene()
        let south = s.model.views.first { $0.name == "South" }!.id
        let g = build(s.model, south)
        #expect(g.items.contains { $0.category == .walls && $0.layer == .model })
        #expect(!g.items.contains { $0.layer == .cut })
        #expect(categories(g).contains(.levels))
        #expect(categories(g).contains(.grids), "grids perpendicular to the elevation show even though the plane sits outside the building")
        // Elevation coordinates are (along, absolute elevation).
        let wallBounds = g.items.filter { $0.category == .walls }.reduce(Rect2.empty) { $0.union($1.bounds) }
        #expect(Fx.approx(wallBounds.min.y, 0, 1e-6) && Fx.approx(wallBounds.max.y, 4, 1e-6))
    }

    @Test func hiddenCategoriesAndElements() throws {
        var s = try scene()
        let door = s.door, win = s.window
        try edit(&s, \.plan) { v in v.visibility.hiddenCategories = [.doors, .rooms]; v.visibility.hiddenElements = [win] }
        let g = build(s.model, s.plan)
        #expect(!categories(g).contains(.doors))
        #expect(!categories(g).contains(.rooms))
        #expect(!ids(g).contains(win))
        #expect(!ids(g).contains(door))
        // Reveal Hidden shows them again.
        var t = TemporaryVisibility()
        t.revealHidden = true
        #expect(ids(build(s.model, s.plan, t)).isSuperset(of: [door, win]))
    }

    @Test func viewFiltersHideAndOverride() throws {
        var s = try scene()
        var hide: ElementID!, tint: ElementID!
        try Fx.commit(&s.model) { tx in
            tx.update(s.walls[0]) { $0.mark = "HIDE" }
            tx.update(s.walls[1]) { $0.mark = "TINT" }
            hide = tx.create(.filters, name: "Hide", data: .filter(ViewFilterData(categories: [.walls], rules: [FilterRule(parameter: .mark, op: .equals, value: .text("hide"))])))
            tint = tx.create(.filters, name: "Tint", data: .filter(ViewFilterData(categories: [.walls], rules: [FilterRule(parameter: .mark, op: .beginsWith, value: .text("TI"))])))
        }
        var o = GraphicOverride()
        o.halftone = true
        try edit(&s, \.plan) { v in v.visibility.filters = [AppliedFilter(filterID: hide, visible: false), AppliedFilter(filterID: tint, override: o)] }
        let g = build(s.model, s.plan)
        #expect(!ids(g).contains(s.walls[0]))
        let tinted = g.items.first { $0.elementID == s.walls[1] }!
        #expect(tinted.primitives.contains { if case .polyline(_, _, let st) = $0 { return st.halftone } else { return false } })
        let resolver = VisibilityResolver(model: s.model, view: s.model[s.plan]!)
        #expect(resolver.resolve(s.model[s.walls[2]]!)?.halftone == nil)
    }

    @Test(arguments: PhaseFilter.allCases)
    func phaseFilterGraphics(_ filter: PhaseFilter) throws {
        var s = try scene()
        var existing: ElementID!, demolished: ElementID!
        try Fx.commit(&s.model) { tx in
            existing = Fx.wall(tx, s.ids, Vec2(20, 0), Vec2(25, 0))
            demolished = Fx.wall(tx, s.ids, Vec2(20, 3), Vec2(25, 3))
            tx.update(existing) { $0.phaseCreated = s.ids.phases[0] }
            tx.update(demolished) { $0.phaseCreated = s.ids.phases[0]; $0.phaseDemolished = s.ids.phases[1] }
        }
        try edit(&s, \.plan) { v in v.phaseFilter = filter }
        let r = VisibilityResolver(model: s.model, view: s.model[s.plan]!)
        let e = s.model[existing]!, d = s.model[demolished]!, n = s.model[s.walls[0]]!
        #expect(r.phaseStatus(e) == .existing && r.phaseStatus(d) == .demolished && r.phaseStatus(n) == .new)
        let (eo, dObj, no) = (r.resolve(e), r.resolve(d), r.resolve(n))
        switch filter {
        case .none:
            #expect(eo != nil && dObj != nil && no != nil)
            #expect(eo?.halftone == nil)
        case .showAll:
            #expect(eo?.halftone == true)
            #expect(dObj?.projectionLinePattern == .hidden)
            #expect(no != nil && no?.halftone == nil)
        case .showComplete:
            #expect(eo != nil && dObj == nil && no != nil)
        case .showNew:
            #expect(eo == nil && dObj == nil && no != nil)
        case .showPreviousAndNew:
            #expect(eo?.halftone == true && dObj == nil && no != nil)
        case .showPreviousPhase:
            #expect(eo != nil && no == nil)
        case .showDemoAndNew:
            #expect(eo == nil && dObj?.cutLinePattern == .hidden && no != nil)
        }
        // A view set to the Existing phase never shows New Construction elements.
        let existingPhase = s.ids.phases[0]
        try edit(&s, \.plan) { v in v.phaseID = existingPhase }
        let past = VisibilityResolver(model: s.model, view: s.model[s.plan]!)
        #expect(past.phaseStatus(n) == .future)
        #expect(past.resolve(n) == nil)
    }

    @Test func temporaryHideAndIsolate() throws {
        let s = try scene()
        var iso = TemporaryVisibility()
        iso.isolatedCategories = [.walls]
        let g = build(s.model, s.plan, iso)
        #expect(categories(g).intersection([.doors, .windows, .floors, .rooms, .genericModels, .tags]).isEmpty)
        #expect(categories(g).contains(.walls))
        var isoEl = TemporaryVisibility()
        isoEl.isolatedElements = [s.door]
        #expect(ids(build(s.model, s.plan, isoEl)).intersection(Set(s.walls)).isEmpty)
        #expect(ids(build(s.model, s.plan, isoEl)).contains(s.door))
        var hide = TemporaryVisibility()
        hide.hiddenElements = [s.walls[0]]
        hide.hiddenCategories = [.floors]
        #expect(hide.isActive)
        let h = build(s.model, s.plan, hide)
        #expect(!ids(h).contains(s.walls[0]) && !categories(h).contains(.floors))
        #expect(!TemporaryVisibility().isActive)
    }

    @Test func cropRegionClipsModelGraphics() throws {
        var s = try scene()
        let crop = Rect2(min: Vec2(-1, -1), max: Vec2(4, 9))
        try edit(&s, \.plan) { v in v.cropActive = true; v.cropRegion = crop; v.cropVisible = true }
        let g = build(s.model, s.plan)
        #expect(g.crop == crop)
        for item in g.items where item.layer != .annotation && item.layer != .overlay {
            #expect(crop.expanded(by: 1e-9).contains(item.bounds) || item.bounds.isEmpty, "\(item.category) \(item.bounds)")
        }
        #expect(!ids(g).contains(s.box), "the component at x = 7 is outside the crop")
        #expect(!ids(g).contains(s.window))
        #expect(g.items.contains { $0.layer == .overlay && $0.category == .views }, "visible crop boundary")
        // Clipping splits lines at the boundary.
        let clipped = ViewGraphicsBuilder.clipPrimitive(.polyline([Vec2(0, 0), Vec2(10, 0)], closed: false, .thin), to: Rect2(min: Vec2(2, -1), max: Vec2(5, 1)))
        guard case .polyline(let pts, _, _)? = clipped.first else { Issue.record("expected a polyline"); return }
        #expect(Fx.approx(pts.first!, Vec2(2, 0)) && Fx.approx(pts.last!, Vec2(5, 0)))
    }

    @Test func viewTemplateControlsViewSettings() throws {
        var s = try scene()
        let presentation = s.model.elements(.viewTemplates).first { $0.name == "Presentation Plan" }!.id
        let arch = s.model.elements(.viewTemplates).first { $0.name == "Architectural Plan" }!.id
        let door = s.door
        try edit(&s, \.plan) { v in v.templateID = presentation; v.detailLevel = .fine; v.visibility.hiddenElements = [door] }
        let r = VisibilityResolver(model: s.model, view: s.model[s.plan]!)
        #expect(r.data.detailLevel == .coarse)
        #expect(r.vg.hiddenCategories.contains(.roomSeparationLines))
        #expect(r.vg.hiddenElements.contains(door), "element hides stay with the view")
        let g = build(s.model, s.plan)
        #expect(!categories(g).contains(.roomSeparationLines))
        #expect(!ids(g).contains(door))
        // Template-controlled parameters are locked in the inspector.
        #expect(!Parameters.isEditable(ParameterID("view.detailLevel"), on: s.model[s.plan]!, s.model))
        try edit(&s, \.plan) { v in v.templateID = arch; v.scale = 50 }
        #expect(build(s.model, s.plan).scale == 100)
        // Deleting the template releases the view.
        try Fx.commit(&s.model) { tx in tx.delete(arch) }
        #expect(s.model[s.plan]!.view!.templateID == nil)
        #expect(build(s.model, s.plan).scale == 50)
    }

    @Test func viewTemplateMustMatchViewKind() throws {
        let s = try scene()
        let planTemplate = s.model.elements(.viewTemplates).first { $0.name == "Architectural Plan" }!.id
        let south = s.model.views.first { $0.name == "South" }!.id
        let tx = TransactionContext(model: s.model, name: "Template")
        #expect(throws: ParameterError.self) { try Parameters.set(ParameterID("view.template"), to: .ref(planTemplate), on: south, in: tx) }
        try Parameters.set(ParameterID("view.template"), to: .ref(planTemplate), on: s.rcp, in: tx)
    }

    @Test(arguments: [DetailLevel.coarse, .medium, .fine])
    func detailLevelChangesWallFills(_ level: DetailLevel) throws {
        var s = try scene(wallType: Fx.brick)
        try edit(&s, \.plan) { v in v.detailLevel = level }
        let g = build(s.model, s.plan)
        let south = g.items.first { $0.elementID == s.walls[0] && $0.layer == .cut }!
        var fills: [GFill] = []
        var thinLines = 0
        for p in south.primitives {
            if case .fill(_, let f) = p { fills.append(f) }
            if case .polyline(_, _, let st) = p, st.weight == 1 { thinLines += 1 }
        }
        switch level {
        case .coarse:
            #expect(fills.count == 1 && fills[0].pattern == .solid)
            #expect(thinLines == 0)
        case .medium:
            #expect(fills.count == 1 && fills[0].pattern != .solid)
            #expect(thinLines > 0, "layer boundaries")
        case .fine:
            #expect(fills.count == 4, "one fill per layer")
            #expect(Set(fills.map(\.pattern)).count > 1)
        }
    }

    @Test func structuralDisciplineHidesArchitecturalContent() throws {
        var s = try scene()
        try edit(&s, \.plan) { v in v.discipline = .structural }
        let c = categories(build(s.model, s.plan))
        #expect(c.contains(.walls) && c.contains(.floors))
        #expect(!c.contains(.doors) && !c.contains(.genericModels))
    }

    @Test func designOptionsShowPrimaryUnlessChosen() throws {
        var s = try scene()
        var primary: ElementID!, secondary: ElementID!, a: ElementID!, b: ElementID!
        try Fx.commit(&s.model) { tx in
            primary = tx.create(.designOptions, name: "Open", data: .designOption(DesignOptionData(setName: "Layout", isPrimary: true)))
            secondary = tx.create(.designOptions, name: "Closed", data: .designOption(DesignOptionData(setName: "Layout", isPrimary: false)))
            a = Fx.wall(tx, s.ids, Vec2(20, 0), Vec2(25, 0))
            b = Fx.wall(tx, s.ids, Vec2(20, 3), Vec2(25, 3))
            tx.update(a) { $0.designOptionID = primary }
            tx.update(b) { $0.designOptionID = secondary }
        }
        #expect(ids(build(s.model, s.plan)).contains(a))
        #expect(!ids(build(s.model, s.plan)).contains(b))
        try edit(&s, \.plan) { v in v.designOptions = ["Layout": secondary] }
        #expect(!ids(build(s.model, s.plan)).contains(a))
        #expect(ids(build(s.model, s.plan)).contains(b))
    }

    @Test func tagsOnlyAppearInTheirOwnView() throws {
        let s = try scene()
        let tag = s.model.elements(.tags)[0].id
        #expect(ids(build(s.model, s.plan)).contains(tag))
        let l2plan = s.ids.planViews[s.ids.levels[1]]!
        #expect(!ids(build(s.model, l2plan)).contains(tag))
    }

    @Test func upperFloorPlanDoesNotCutLowerWalls() throws {
        let s = try scene()
        let g = build(s.model, s.ids.planViews[s.ids.levels[1]]!)
        #expect(!g.items.contains { $0.category == .walls && $0.layer == .cut })
        #expect(!ids(g).contains(s.door))
    }

    @Test(arguments: [
        (FilterRule.Op.equals, ParamValue.double(2.0), ParamValue.double(2.0), true), (.equals, .text("Abc"), .text("abc"), true),
        (.notEquals, .text("a"), .text("b"), true), (.greater, .double(3), .double(2), true), (.greater, .double(2), .double(2), false),
        (.greaterOrEqual, .double(2), .double(2), true), (.less, .text("A9"), .text("A10"), true), (.lessOrEqual, .int(3), .double(3), true),
        (.contains, .text("Office 12"), .text("ice"), true), (.notContains, .text("Office"), .text("x"), true),
        (.beginsWith, .text("Door"), .text("do"), true), (.endsWith, .text("Door"), .text("OR"), true),
        (.hasValue, .text(""), .text(""), false), (.hasNoValue, .ref(nil), .text(""), true), (.hasValue, .ref(ElementID(3)), .text(""), true),
    ])
    func filterRuleEvaluation(_ op: FilterRule.Op, _ lhs: ParamValue, _ rhs: ParamValue, _ expected: Bool) {
        #expect(FilterEvaluation.evaluate(op, lhs: lhs, rhs: rhs) == expected)
    }

    @Test func missingValuesOnlyMatchNegativeRules() {
        #expect(FilterEvaluation.evaluate(.notEquals, lhs: nil, rhs: .text("x")))
        #expect(!FilterEvaluation.evaluate(.equals, lhs: nil, rhs: .text("x")))
        #expect(FilterEvaluation.evaluate(.hasNoValue, lhs: nil, rhs: .text("")))
    }

    @Test func overridesMergeFieldByField() {
        var a = GraphicOverride()
        a.projectionLineWeight = 3
        a.halftone = false
        var b = GraphicOverride()
        b.halftone = true
        b.surfaceColor = RGBColor(1, 0, 0)
        let m = a.merged(with: b)
        #expect(m.projectionLineWeight == 3 && m.halftone == true && m.surfaceColor == RGBColor(1, 0, 0))
        #expect(GraphicOverride().isEmpty && !m.isEmpty)
    }

    @Test func lineWeightsScaleWithViewScale() {
        #expect(LineWeights.paperWidth(1, scale: 20) == LineWeights.paperWidth(1, scale: 500), "weight 1 never scales")
        #expect(LineWeights.paperWidth(5, scale: 20) > LineWeights.paperWidth(5, scale: 100))
        #expect(LineWeights.paperWidth(5, scale: 100) > LineWeights.paperWidth(5, scale: 500))
        #expect(LineWeights.paperWidth(99, scale: 100) == LineWeights.paperWidth(16, scale: 100))
    }
}
