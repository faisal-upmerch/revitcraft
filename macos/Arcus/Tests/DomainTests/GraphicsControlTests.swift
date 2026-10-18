import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

// BL-VG: Visibility/Graphics overrides, Object Styles, filters with AND/OR rule sets, view templates, warnings,
// element id lists, Cut Geometry and structural foundations.

@Suite("Graphics control")
struct GraphicsControlTests {
    struct Scene {
        var model: BIMModel
        let ids: ProjectTemplates.Ids
        let walls: [ElementID]
        let door: ElementID
        var plan: ElementID { ids.planViews[ids.levels[0]]! }
    }

    func scene() throws -> Scene {
        var (m, ids) = Fx.template()
        var walls: [ElementID] = [], door: ElementID!
        try Fx.commit(&m) { tx in
            walls = Fx.boxWalls(tx, ids, type: Fx.brick)
            door = Fx.door(tx, ids, host: walls[0], at: Vec2(3, 0))
        }
        return Scene(model: m, ids: ids, walls: walls, door: door)
    }

    func edit(_ s: inout Scene, view: ElementID? = nil, _ f: @escaping (inout ViewData) -> Void) throws {
        let v = view ?? s.plan
        try Fx.commit(&s.model) { tx in tx.update(v) { e in if var d = e.view { f(&d); e.view = d } } }
    }

    func build(_ m: BIMModel, _ v: ElementID, _ t: TemporaryVisibility = TemporaryVisibility()) -> ViewGraphics {
        ViewGraphicsBuilder(model: m, view: m[v]!, temporary: t).build()
    }

    /// Weights of the stroked lines of an element's cut item.
    func cutWeights(_ g: ViewGraphics, _ id: ElementID) -> Set<Int> {
        var out = Set<Int>()
        for i in g.items where i.elementID == id && i.layer == .cut {
            for p in i.primitives { if case .polyline(_, _, let st) = p, st.weight > 1 { out.insert(st.weight) } }
        }
        return out
    }

    // MARK: Override resolution

    @Test func overrideResolutionOrder() throws {
        var s = try scene()
        var filter: ElementID!
        try Fx.commit(&s.model) { tx in
            tx.update(s.walls[0]) { $0.mark = "E1" }
            filter = tx.create(.filters, name: "E walls", data: .filter(ViewFilterData(categories: [.walls], rules: [FilterRule(parameter: .mark, op: .beginsWith, value: .text("E"))])))
            // Object style: walls cut weight 7 project-wide.
            tx.update(tx.model.projectInfoElement!.id) { e in
                var os = ObjectStyleSettings(); os[.walls, nil] = ObjectStyleOverride(cutWeight: 7)
                e.projectInfo?.objectStyles = os
            }
        }
        // Object style only.
        #expect(cutWeights(build(s.model, s.plan), s.walls[1]) == [7])
        // Category override beats object style.
        try edit(&s) { v in var o = GraphicOverride(); o.cutLineWeight = 9; v.visibility.categoryOverrides[.walls] = o }
        #expect(cutWeights(build(s.model, s.plan), s.walls[1]) == [9])
        // Filter beats category (only on matching walls).
        try edit(&s) { v in var o = GraphicOverride(); o.cutLineWeight = 11; v.visibility.filters = [AppliedFilter(filterID: filter, override: o)] }
        var g = build(s.model, s.plan)
        #expect(cutWeights(g, s.walls[0]) == [11])
        #expect(cutWeights(g, s.walls[1]) == [9])
        // Element override ("Override Graphics in View") beats the filter.
        let w0 = s.walls[0]
        try edit(&s) { v in var o = GraphicOverride(); o.cutLineWeight = 13; v.visibility.setElementOverride(o, for: [w0]) }
        g = build(s.model, s.plan)
        #expect(cutWeights(g, s.walls[0]) == [13])
        // A filter that hides wins over any graphic override.
        try edit(&s) { v in v.visibility.filters[0].visible = false }
        #expect(!build(s.model, s.plan).items.contains { $0.elementID == w0 })
    }

    @Test func templateVisibilityBeatsViewCategoryOverrides() throws {
        var s = try scene()
        var tpl: ElementID!
        try Fx.commit(&s.model) { tx in
            var td = ViewTemplateData(appliesTo: .floorPlan)
            var vg = VisibilityGraphics(); var o = GraphicOverride(); o.cutLineWeight = 3; vg.categoryOverrides[.walls] = o
            td.visibility = vg
            tpl = tx.create(.viewTemplates, name: "T", data: .viewTemplate(td))
        }
        try edit(&s) { v in var o = GraphicOverride(); o.cutLineWeight = 12; v.visibility.categoryOverrides[.walls] = o; v.templateID = tpl }
        #expect(cutWeights(build(s.model, s.plan), s.walls[1]) == [3])
    }

    @Test func objectStylesDriveEveryViewWithoutOverrides() throws {
        var s = try scene()
        let before = cutWeights(build(s.model, s.plan), s.walls[1])
        #expect(before == [ObjectStyles.style(.walls).cutWeight])
        try Fx.commit(&s.model) { tx in
            tx.update(tx.model.projectInfoElement!.id) { e in
                var os = ObjectStyleSettings()
                os[.walls, nil] = ObjectStyleOverride(cutWeight: 8, color: RGBColor(0.8, 0, 0))
                e.projectInfo?.objectStyles = os
            }
        }
        let g = build(s.model, s.plan)
        #expect(cutWeights(g, s.walls[1]) == [8])
        let colors = g.items.filter { $0.elementID == s.walls[1] }.flatMap(\.primitives).compactMap { p -> RGBColor? in
            if case .polyline(_, _, let st) = p { return st.color } else { return nil }
        }
        #expect(colors.contains(RGBColor(0.8, 0, 0)))
        // A second plan (Level 2 walls none; use the Level 1 ceiling plan's walls) also picks the style up.
        if let rcp = s.ids.ceilingViews[s.ids.levels[0]] {
            #expect(cutWeights(build(s.model, rcp), s.walls[1]).isSubset(of: [8]))
        }
        // Persisted: the settings survive a Codable round trip of the project info.
        let data = try JSONEncoder().encode(s.model.projectInfo)
        #expect(try JSONDecoder().decode(ProjectInfoData.self, from: data).objectStyles?[.walls, nil]?.cutWeight == 8)
    }

    // MARK: Subcategories and detail level

    @Test func hiddenSubcategoryAndSubcategoryOverride() throws {
        var s = try scene()
        func arcs(_ g: ViewGraphics) -> Int {
            g.items.filter { $0.elementID == s.door }.flatMap(\.primitives).filter { if case .arc = $0 { return true }; return false }.count
        }
        #expect(arcs(build(s.model, s.plan)) > 0)
        let swing = Subcategories.key(.doors, FamilySubcategory.swing.rawValue)
        #expect(Subcategories.names(for: .doors).contains(FamilySubcategory.swing.rawValue))
        try edit(&s) { v in v.visibility.hiddenSubcategories = [swing] }
        let g = build(s.model, s.plan)
        #expect(arcs(g) == 0)
        #expect(g.items.contains { $0.elementID == s.door }, "the rest of the door still draws")
        // Subcategory override: frame lines take weight 6.
        let frame = Subcategories.key(.doors, FamilySubcategory.frame.rawValue)
        try edit(&s) { v in
            v.visibility.hiddenSubcategories = nil
            var o = GraphicOverride(); o.projectionLineWeight = 6; o.cutLineWeight = 6
            v.visibility.subcategoryOverrides = [frame: o]
        }
        let weights = build(s.model, s.plan).items.filter { $0.elementID == s.door }.flatMap(\.primitives).compactMap { p -> Int? in
            if case .polyline(_, _, let st) = p { return st.weight } else { return nil }
        }
        #expect(weights.contains(6))
    }

    @Test func perCategoryDetailLevel() throws {
        var s = try scene()
        func wallFills(_ g: ViewGraphics) -> [FillPatternKind] {
            g.items.filter { $0.elementID == s.walls[1] }.flatMap(\.primitives).compactMap { p -> FillPatternKind? in
                if case .fill(_, let f) = p { return f.pattern } else { return nil }
            }
        }
        try edit(&s) { v in v.detailLevel = .medium }
        #expect(!wallFills(build(s.model, s.plan)).allSatisfy { $0 == .solid })
        try edit(&s) { v in v.visibility.categoryDetailLevels = [.walls: .coarse] }
        #expect(wallFills(build(s.model, s.plan)) == [.solid])
    }

    @Test func wireframeDropsModelFillsIn2D() throws {
        var s = try scene()
        #expect(build(s.model, s.plan).items.contains { i in i.layer == .cut && i.primitives.contains { if case .fill = $0 { return true }; return false } })
        try edit(&s) { v in v.visualStyle = .wireframe }
        let g = build(s.model, s.plan)
        #expect(!g.items.contains { i in [.cut, .model, .fills].contains(i.layer) && i.primitives.contains { if case .fill = $0 { return true }; return false } })
        #expect(g.items.contains { $0.elementID == s.walls[0] })
    }

    // MARK: Filters

    @Test func filterWithAndOrRuleSets() throws {
        var s = try scene()
        var generic: ElementID!, f: ElementID!
        try Fx.commit(&s.model) { tx in
            tx.update(s.ids.wallTypes[Fx.brick]!) { $0.typeData?.params[ParameterID("type.function")] = .text("Exterior") }
            tx.update(s.walls[0]) { $0.mark = "E1" }      // exterior, E → match
            tx.update(s.walls[1]) { $0.mark = "X1" }      // exterior, no E
            generic = Fx.wall(tx, s.ids, Vec2(2, 2), Vec2(6, 2))
            tx.update(generic) { $0.mark = "E2" }         // interior, E
            f = tx.create(.filters, name: "Exterior E", data: .filter(ViewFilterData(categories: [.walls], rules: [
                FilterRule(parameter: .mark, op: .contains, value: .text("E")),
                FilterRule(parameter: ParameterID("type.function"), op: .equals, value: .text("Exterior")),
            ], matchAll: true)))
        }
        let m = s.model
        var fd = m[f]!.viewFilter!
        #expect(FilterEvaluation.matches(fd, m[s.walls[0]]!, m))
        #expect(!FilterEvaluation.matches(fd, m[s.walls[1]]!, m))
        #expect(!FilterEvaluation.matches(fd, m[generic]!, m))
        // OR.
        fd.matchAll = false
        #expect(FilterEvaluation.matches(fd, m[s.walls[1]]!, m) && FilterEvaluation.matches(fd, m[generic]!, m))
        // (Mark contains E AND Function = Interior) OR (Mark = X1): generic and walls[1], not walls[0].
        let nested = ViewFilterData(categories: [.walls], rules: [FilterRule(parameter: .mark, op: .equals, value: .text("X1"))], matchAll: false)
        var n = nested
        n.groups = [FilterRuleGroup(rules: [FilterRule(parameter: .mark, op: .contains, value: .text("E")),
                                            FilterRule(parameter: ParameterID("type.function"), op: .equals, value: .text("Interior"))], matchAll: true)]
        #expect(FilterEvaluation.matches(n, m[generic]!, m))
        #expect(FilterEvaluation.matches(n, m[s.walls[1]]!, m))
        #expect(!FilterEvaluation.matches(n, m[s.walls[0]]!, m))
        // Applied in a view: only walls[0] turns halftone.
        var o = GraphicOverride(); o.halftone = true
        try edit(&s) { v in v.visibility.filters = [AppliedFilter(filterID: f, override: o)] }
        let r = VisibilityResolver(model: s.model, view: s.model[s.plan]!)
        #expect(r.resolve(s.model[s.walls[0]]!)?.halftone == true)
        #expect(r.resolve(s.model[s.walls[1]]!)?.halftone == nil)
        // Filters with nested sets survive Codable (and older files without `groups` decode).
        let data = try JSONEncoder().encode(n)
        #expect(try JSONDecoder().decode(ViewFilterData.self, from: data) == n)
        let old = try JSONEncoder().encode(nested)
        #expect(try JSONDecoder().decode(ViewFilterData.self, from: old).groups == nil)
        // The parameter list offers Mark and Function for walls.
        let params = FilterEvaluation.parameters(for: [.walls], s.model).map(\.id)
        #expect(params.contains(.mark) && params.contains(ParameterID("type.function")))
    }

    // MARK: View templates

    @Test func viewTemplateCreateAssignAndLock() throws {
        var s = try scene()
        let other = s.ids.planViews[s.ids.levels[1]]!
        try edit(&s) { v in v.scale = 50; v.detailLevel = .fine }
        let td = ViewTemplates.make(from: s.model[s.plan]!.view!)
        var tpl: ElementID!
        try Fx.commit(&s.model) { tx in
            tpl = tx.create(.viewTemplates, name: "Plans 1:50", data: .viewTemplate(td))
            try ViewTemplates.assign(tpl, to: other, in: tx)
        }
        #expect(s.model[other]?.view?.scale == 50)
        #expect(s.model[other]?.view?.detailLevel == .fine)
        func lock(_ key: String) -> String? {
            Parameters.instanceEntries(s.model[other]!, s.model).first { $0.id == ParameterID(key) }?.readOnlyReason
        }
        #expect(lock("view.scale") != nil)
        #expect(lock("view.detailLevel") != nil)
        #expect(lock("view.cropActive") == nil)
        // Stop controlling the scale: it unlocks, detail level stays locked.
        try Fx.commit(&s.model) { tx in
            tx.update(tpl) { e in if var t = e.viewTemplate { ViewTemplates.setControls(&t, .scale, false, source: ViewData(kind: .floorPlan)); e.viewTemplate = t } }
        }
        #expect(lock("view.scale") == nil)
        #expect(lock("view.detailLevel") != nil)
        // Editing the template pushes its values to the views that use it.
        try Fx.commit(&s.model) { tx in
            tx.update(tpl) { $0.viewTemplate?.detailLevel = .coarse }
            ViewTemplates.propagate(tpl, in: tx)
        }
        #expect(s.model[other]?.view?.detailLevel == .coarse)
        // A section can't use a plan template.
        let section = try #require(s.model.views.first { $0.view?.kind == .elevation })
        #expect(throws: TransactionError.self) { try Fx.commit(&s.model) { tx in try ViewTemplates.assign(tpl, to: section.id, in: tx) } }
    }

    @Test func temporaryViewPropertiesApplyWithoutSaving() throws {
        var s = try scene()
        var tpl: ElementID!
        try Fx.commit(&s.model) { tx in
            var td = ViewTemplateData(appliesTo: .floorPlan)
            td.scale = 20
            var vg = VisibilityGraphics(); vg.hiddenCategories = [.doors]
            td.visibility = vg
            tpl = tx.create(.viewTemplates, name: "Temp", data: .viewTemplate(td))
        }
        var t = TemporaryVisibility(); t.temporaryTemplateID = tpl
        let g = build(s.model, s.plan, t)
        #expect(g.scale == 20)
        #expect(!g.items.contains { $0.elementID == s.door })
        #expect(s.model[s.plan]?.view?.templateID == nil)
        #expect(build(s.model, s.plan).items.contains { $0.elementID == s.door })
    }

    // MARK: Reveal constraints

    @Test func revealConstraintsDrawsLocks() throws {
        var s = try scene()
        try Fx.commit(&s.model) { tx in
            tx.create(.constraints, data: .constraint(ConstraintData(kind: .alignment, references: [GeometryReference(s.walls[0], .location), GeometryReference(s.walls[2], .location)])))
        }
        #expect(!build(s.model, s.plan).items.contains { $0.category == .constraints })
        var t = TemporaryVisibility(); t.revealConstraints = true
        let items = build(s.model, s.plan, t).items.filter { $0.category == .constraints }
        #expect(items.count == 1)
        #expect(items.allSatisfy { !$0.selectable && $0.layer == .overlay })
    }

    // MARK: Warnings and ids

    @Test func warningsGroupAndExport() throws {
        var s = try scene()
        try Fx.commit(&s.model) { tx in
            tx.update(s.walls[0]) { $0.mark = "W" }
            tx.update(s.walls[1]) { $0.mark = "W" }
            Fx.wall(tx, s.ids, Vec2(0, 0), Vec2(5, 0)) // overlaps walls[0]
        }
        let ws = ModelHealth.check(s.model)
        let groups = WarningsReport.groups(ws)
        #expect(groups.contains { $0.code == "mark.duplicate" })
        #expect(groups.contains { $0.code == "wall.overlap" && $0.title == "Walls overlap." })
        #expect(Set(groups.map(\.code)).count == groups.count, "one group per code")
        #expect(groups.flatMap(\.warnings).count == ws.count)
        let html = WarningsReport.html(ws, s.model, projectName: "Test <P>")
        #expect(html.contains("Test &lt;P&gt;"))
        #expect(html.contains(s.walls[0].description))
        #expect(!html.contains("<script"))
        #expect(WarningsReport.describe(s.walls[0], s.model).hasPrefix("Walls : "))
    }

    @Test func elementIDLists() {
        let (ids, invalid) = ElementIDList.parse("12; 15, #20 x 12\n7")
        #expect(ids == [ElementID(12), ElementID(15), ElementID(20), ElementID(7)])
        #expect(invalid == ["x"])
        #expect(ElementIDList.format([ElementID(20), ElementID(3)]) == "3; 20")
    }

    // MARK: Geometry

    @Test func overlappingWallsCleanInPlan() throws {
        var (m, ids) = Fx.template()
        var a: ElementID!, b: ElementID!
        try Fx.commit(&m) { tx in
            a = Fx.wall(tx, ids, Vec2(0, 0), Vec2(6, 0))
            b = Fx.wall(tx, ids, Vec2(4, 0), Vec2(10, 0))
        }
        let g = ViewGraphicsBuilder(model: m, view: m[ids.planViews[ids.levels[0]]!]!).build()
        var pts: [Vec2] = []
        for i in g.items where i.layer == .cut && (i.elementID == a || i.elementID == b) {
            for p in i.primitives { if case .polyline(let ps, _, let st) = p, st.weight > 1 { pts += ps } }
        }
        #expect(!pts.isEmpty)
        let half = pts.map { abs($0.y) }.max() ?? 0
        // Every heavy cut line lies on the outline of the union: no line across the overlap at x = 4 or x = 6.
        #expect(pts.allSatisfy { abs(abs($0.y) - half) < 1e-6 || abs($0.x) < 1e-6 || abs($0.x - 10) < 1e-6 })
    }

    @Test func cutGeometryAndSwitchJoinOrder() throws {
        var (m, ids) = Fx.template()
        var lower: ElementID!, upper: ElementID!, wall: ElementID!
        try Fx.commit(&m) { tx in
            let ft = tx.model.types(for: .floors).first!.id
            lower = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(6, 6))))), typeID: ft, levelID: ids.levels[0])
            upper = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(3, 3), max: Vec2(9, 9))), offset: -0.05)), typeID: ft, levelID: ids.levels[0])
            wall = Fx.wall(tx, ids, Vec2(-1, 1), Vec2(8, 1))
        }
        let pair = try #require(SolidJoins.cutPair(m[lower]!, m[upper]!))
        #expect(pair.cut.id == lower && pair.cutter.id == upper, "first picked is cut when both can be")
        #expect(SolidJoins.cutPair(m[wall]!, m[lower]!)?.cut.id == lower, "walls are never cut")
        try Fx.commit(&m) { tx in try SolidJoins.cutGeometry(cutter: upper, cut: lower, in: tx) }
        #expect(SolidJoins.removedVolume(m[lower]!, m) > 1e-6)
        #expect(SolidJoins.removedVolume(m[upper]!, m) < 1e-9)
        #expect(throws: TransactionError.self) { try Fx.commit(&m) { tx in try SolidJoins.cutGeometry(cutter: upper, cut: lower, in: tx) } }
        try Fx.commit(&m) { tx in try SolidJoins.switchJoinOrder(lower, upper, in: tx) }
        #expect(SolidJoins.removedVolume(m[upper]!, m) > 1e-6)
        #expect(SolidJoins.removedVolume(m[lower]!, m) < 1e-9)
        // A wall/floor join can't be switched (walls aren't cut).
        try Fx.commit(&m) { tx in SolidJoins.join([wall, lower], in: tx) }
        #expect(throws: TransactionError.self) { try Fx.commit(&m) { tx in try SolidJoins.switchJoinOrder(wall, lower, in: tx) } }
    }

    // MARK: Structure

    @Test func foundationsUnderColumnsAndWalls() throws {
        var (m, ids) = Fx.template()
        var column: ElementID?, wall: ElementID!
        try Fx.commit(&m) { tx in
            wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(8, 0))
            if let ct = tx.model.types(for: .structuralColumns).first?.id {
                column = tx.create(.structuralColumns, data: .column(ColumnData(location: Vec2(4, 4))), typeID: ct, levelID: ids.levels[0])
            }
        }
        #expect(column != nil, "the template has structural column types")
        var strips: [ElementID] = []
        try Fx.commit(&m) { tx in strips = StructuralFoundations.wall(under: [wall], in: tx) }
        #expect(strips.count == 1)
        let strip = try #require(m[strips[0]])
        #expect(strip.slab?.structural == true && strip.category == .floors)
        #expect(m.type(of: strip)?.name == StructuralFoundations.stripTypeName)
        let t = WallGeometry.frame(m[wall]!, m)!.thickness
        #expect(Fx.approx(strip.slab!.boundary.bounds.height, t + 2 * StructuralFoundations.stripProjection, 1e-6))
        #expect(Fx.approx(m.typeData(of: strip)?.assembly?.totalThickness ?? 0, StructuralFoundations.stripDepth))
        if let column {
            var pads: [ElementID] = []
            try Fx.commit(&m) { tx in pads = StructuralFoundations.isolated(under: [column, wall], in: tx) }
            #expect(pads.count == 1)
            let pad = try #require(m[pads[0]])
            #expect(Fx.approx(pad.slab!.boundary.bounds.width, StructuralFoundations.padSize, 1e-6))
            #expect(Fx.approx(pad.slab!.boundary.bounds.center, Vec2(4, 4), 1e-6))
            // The footing type is reused, not duplicated.
            try Fx.commit(&m) { tx in StructuralFoundations.isolated(under: [column], in: tx) }
            #expect(m.types(for: .floors).filter { $0.name == StructuralFoundations.padTypeName }.count == 1)
        }
    }
}
