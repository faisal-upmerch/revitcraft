import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Curtain walls")
struct CurtainWallTests {
    static func panelType(_ m: BIMModel, _ name: String) -> ElementID {
        m.type(category: .curtainPanels, family: CurtainWallDefaults.panelFamily, name: name)!.id
    }

    /// A curtain wall type with the given rules; interior vertical mullions on, others off unless requested.
    @discardableResult
    static func curtainType(_ tx: TransactionContext, vertical: CurtainGridRule, horizontal: CurtainGridRule = CurtainGridRule(),
                            verticalMullions: Bool = true, horizontalMullions: Bool = false, border: Bool = false, name: String = "Test CW") -> ElementID {
        var td = TypeData(instanceCategory: .walls, systemFamily: .curtainWall, familyName: CurtainWallDefaults.wallFamily)
        td.curtain = CurtainSpec(vertical: vertical, horizontal: horizontal, panelTypeID: panelType(tx.model, "Glazed"),
                                 verticalMullions: verticalMullions, horizontalMullions: horizontalMullions, borderMullions: border,
                                 mullion: MullionProfile(width: 0.05, depth: 0.15), mullionMaterialID: tx.model.material(named: "Aluminum")?.id)
        return tx.create(.elementTypes, name: name, data: .type(td))
    }

    struct Scene {
        var model: BIMModel
        let ids: ProjectTemplates.Ids
        let type: ElementID
        let wall: ElementID
        var element: Element { model[wall]! }
    }

    /// A 6 m curtain wall from (0,0) to (6,0), Level 1 → Level 2 (4 m).
    func scene(vertical: CurtainGridRule = CurtainGridRule(layout: .fixedDistance, spacing: 1.5), horizontal: CurtainGridRule = CurtainGridRule(),
               verticalMullions: Bool = true, horizontalMullions: Bool = false, border: Bool = false, length: Double = 6) throws -> Scene {
        var (m, ids) = Fx.template()
        var t: ElementID!, w: ElementID!
        try Fx.commit(&m) { tx in
            t = Self.curtainType(tx, vertical: vertical, horizontal: horizontal, verticalMullions: verticalMullions, horizontalMullions: horizontalMullions, border: border)
            w = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(length, 0))), topLevelID: ids.levels[1])), typeID: t, levelID: ids.levels[0])
        }
        return Scene(model: m, ids: ids, type: t, wall: w)
    }

    @Test func fixedSpacingOnSixMetreWallHasFourPanelsAndThreeMullions() throws {
        let s = try scene()
        let l = try #require(CurtainWallGeometry.layout(s.element, s.model))
        #expect(l.panels.count == 4)
        #expect(l.interiorMullions.count == 3)
        #expect(l.mullions.allSatisfy{ $0.isVertical })
        #expect(l.stations.map { ($0 * 1000).rounded() / 1000 } == [0, 1.5, 3, 4.5, 6])
        #expect(Fx.approx(l.baseZ, 0) && Fx.approx(l.topZ, 4))
        #expect(l.panels.allSatisfy { $0.kind == .glazed && Fx.approx($0.z1 - $0.z0, 4) && Fx.approx($0.s1 - $0.s0, 1.5) })
        // 3D: one glass part (the four panels) plus one mullion part, each panel and mullion a closed box.
        let parts = ElementMeshes.parts(s.element, s.model)
        #expect(parts.count == 2)
        #expect(parts[0].subcategory == .glass && parts[0].materialID == s.model.material(named: "Glass")?.id)
        #expect(parts[1].subcategory == .frame)
        #expect(Fx.approx(abs(parts[1].mesh.signedVolume), 3 * 0.05 * 0.15 * 4, 1e-9))
        // Panels stop at the mullion faces: 4 × height × (widths less 1 or 2 half-mullions).
        let glazedWidth = 6 - 3 * 0.05
        #expect(Fx.approx(abs(parts[0].mesh.signedVolume), glazedWidth * 4 * 0.025, 1e-9))
        #expect(CurtainWallGeometry.isCurtain(s.element, s.model))
        #expect(s.element.wall?.curtain != nil, "the regenerator gives curtain walls their instance data")
    }

    @Test func changingTheSpacingRegeneratesPanelsAndMullions() throws {
        var s = try scene()
        let key = GeometryCache.key(s.element, s.model, detail: .fine)
        _ = GeometryCache.shared.parts(s.element, s.model, detail: .fine)
        try Fx.commit(&s.model) { tx in
            try Parameters.set(ParameterID("curtain.v.spacing"), to: .double(2), on: s.type, in: tx)
        }
        let l = try #require(CurtainWallGeometry.layout(s.element, s.model))
        #expect(l.panels.count == 3)
        #expect(l.interiorMullions.count == 2)
        #expect(GeometryCache.key(s.element, s.model, detail: .fine) != key)
        let cached = GeometryCache.shared.parts(s.element, s.model, detail: .fine)
        #expect(Fx.approx(abs(cached.last!.mesh.signedVolume), 2 * 0.05 * 0.15 * 4, 1e-9))
        // Back to 1.5 m via the Number layout: 3 lines → 4 panels.
        try Fx.commit(&s.model) { tx in
            try Parameters.set(ParameterID("curtain.v.layout"), to: .text("Fixed Number"), on: s.type, in: tx)
            try Parameters.set(ParameterID("curtain.v.count"), to: .int(3), on: s.type, in: tx)
        }
        #expect(CurtainWallGeometry.layout(s.element, s.model)?.panels.count == 4)
    }

    @Test(arguments: [
        (CurtainGridRule(layout: .none), 6.0, [Double]()),
        (CurtainGridRule(layout: .fixedDistance, spacing: 1.5), 6.0, [1.5, 3, 4.5]),
        (CurtainGridRule(layout: .fixedDistance, spacing: 2, justification: .beginning), 5.0, [2, 4]),
        (CurtainGridRule(layout: .fixedDistance, spacing: 2, justification: .end), 5.0, [1, 3]),
        (CurtainGridRule(layout: .fixedDistance, spacing: 2, justification: .center), 5.0, [0.5, 2.5, 4.5]),
        (CurtainGridRule(layout: .fixedNumber, count: 4), 5.0, [1, 2, 3, 4]),
        (CurtainGridRule(layout: .maximumSpacing, spacing: 1.6), 5.0, [1.25, 2.5, 3.75]),
        (CurtainGridRule(layout: .fixedDistance, spacing: 10), 5.0, [Double]()),
    ])
    func gridRules(_ rule: CurtainGridRule, _ length: Double, _ expected: [Double]) {
        let p = rule.positions(length: length)
        #expect(p.count == expected.count)
        for (a, b) in zip(p, expected) { #expect(Fx.approx(a, b, 1e-9)) }
    }

    @Test func horizontalGridsBordersAndTrimming() throws {
        let s = try scene(horizontal: CurtainGridRule(layout: .fixedDistance, spacing: 1.5), horizontalMullions: true, border: true)
        let l = try #require(CurtainWallGeometry.layout(s.element, s.model))
        #expect(l.heights.map { ($0 * 1000).rounded() / 1000 } == [0, 1.5, 3, 4])
        #expect(l.panels.count == 12)
        // Vertical: 5 grid lines × 3 rows; horizontal: 4 grid lines × 4 columns.
        #expect(l.mullions.filter{ $0.isVertical }.count == 15)
        #expect(l.mullions.filter { !$0.isVertical }.count == 16)
        #expect(l.mullions.filter{ $0.isBorder }.count == 2 * 3 + 2 * 4)
        // A corner panel is inset by the border mullion (full width) and half an interior mullion.
        let p = l.panels.first { $0.column == 0 && $0.row == 0 }!
        let x = CurtainWallGeometry.panelExtents(p, l)
        #expect(Fx.approx(x.s0, 0.05) && Fx.approx(x.s1, 1.475) && Fx.approx(x.z0, 0.05) && Fx.approx(x.z1, 1.475))
        // Horizontal mullions run between vertical mullion faces.
        let h = l.mullions.first { !$0.isVertical && !$0.isBorder && $0.from == 0 }!
        let run = CurtainWallGeometry.horizontalRun(h, l)
        #expect(Fx.approx(run.0, 0.05) && Fx.approx(run.1, 1.475))
    }

    @Test func manualGridsAndPanelAndMullionOverrides() throws {
        var s = try scene()
        let empty = Self.panelType(s.model, "Empty"), solid = Self.panelType(s.model, "Solid")
        try Fx.commit(&s.model) { tx in
            tx.update(s.wall) { e in
                var c = e.wall!.curtain!
                c.verticalGrids = [0.75]
                c.horizontalGrids = [2]
                c.panels = [CurtainPanelOverride(station: 0.3, height: 1, typeID: empty), CurtainPanelOverride(station: 5, height: 3, typeID: solid)]
                c.mullions = [CurtainMullionOverride(isVertical: true, position: 3, from: 0, to: 4, present: false)]
                e.wall!.curtain = c
            }
        }
        let l = try #require(CurtainWallGeometry.layout(s.element, s.model))
        #expect(l.stations.count == 6)
        #expect(l.interiorStations.map { ($0 * 100).rounded() / 100 } == [0.75, 1.5, 3, 4.5])
        #expect(l.panels.count == 5 * 2)
        #expect(l.panels.first { $0.s0 == 0 && $0.z0 == 0 }?.kind == .empty)
        #expect(l.panels.first { $0.s0 == 4.5 && $0.z0 == 2 }?.kind == .solid)
        // Interior vertical mullions: 4 lines × 2 rows, minus the two removed at station 3.
        #expect(l.interiorMullions.count == 6)
        #expect(!l.mullions.contains { abs($0.position - 3) < 1e-9 })
    }

    @Test func templatesShipCurtainTypesAndTheTypeSelectorSeesThem() throws {
        let (m, ids) = Fx.template()
        let walls = m.types(for: .walls)
        #expect(walls.filter { $0.typeData?.curtain != nil }.map(\.name).sorted() == ["Curtain Wall", "Exterior Glazing", "Storefront"])
        #expect(walls.first?.typeData?.curtain == nil, "basic walls stay the default wall type")
        #expect(m.types(for: .curtainPanels).map(\.name).sorted() == ["Empty", "Glazed", "Solid"])
        #expect(ids.systemTypes["Curtain Wall: Storefront"] != nil)
        // Populating again is a no-op.
        let tx = TransactionContext(model: m, name: "Again")
        #expect(CurtainWallDefaults.populate(tx).isEmpty)
    }

    @Test func retypingAWallAddsOrRemovesItsCurtainData() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in w = Fx.wall(tx, ids, .zero, Vec2(6, 0)) }
        #expect(m[w]?.wall?.curtain == nil)
        let storefront = ids.systemTypes["Curtain Wall: Storefront"]!
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("familyAndType"), to: .ref(storefront), on: w, in: tx) }
        #expect(m[w]?.wall?.curtain != nil)
        #expect(Parameters.instanceEntries(m[w]!, m).contains { $0.name == "Panels" })
        try Fx.commit(&m) { tx in tx.update(w) { $0.typeID = ids.wallTypes[Fx.generic] } }
        #expect(m[w]?.wall?.curtain == nil)
        #expect(!Parameters.instanceEntries(m[w]!, m).contains { $0.name == "Panels" })
    }

    @Test func curtainWallsButtRatherThanJoin() throws {
        var (m, ids) = Fx.template()
        var cw: ElementID!, basic: ElementID!
        try Fx.commit(&m) { tx in
            let t = Self.curtainType(tx, vertical: CurtainGridRule(layout: .fixedDistance, spacing: 1.5))
            cw = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(.zero, Vec2(6, 0))), topLevelID: ids.levels[1])), typeID: t, levelID: ids.levels[0])
            basic = Fx.wall(tx, ids, Vec2(6, 0), Vec2(6, 5))
        }
        #expect(WallGeometry.joinCandidates(m[cw]!, m).isEmpty)
        #expect(WallGeometry.endJoin(m[basic]!, atEnd: false, m).kind == .free)
        // The nominal thickness comes from the mullion depth.
        #expect(Fx.approx(WallGeometry.frame(m[cw]!, m)!.thickness, 0.15))
    }

    @Test func quantitiesReportGridAreaPanelsAndMullions() throws {
        let s = try scene()
        let q = QuantityEngine.quantities(for: s.element, in: s.model)
        #expect(Fx.approx(q.area ?? 0, 24))
        #expect(Fx.approx(q.length ?? 0, 6) && Fx.approx(q.height ?? 0, 4))
        let glass = q.materials.first { $0.materialID == s.model.material(named: "Glass")?.id }
        #expect(Fx.approx(glass?.area ?? 0, (6 - 0.15) * 4, 1e-9))
        let alu = q.materials.first { $0.materialID == s.model.material(named: "Aluminum")?.id }
        #expect(Fx.approx(alu?.volume ?? 0, 3 * 4 * 0.05 * 0.15, 1e-9))
        #expect(Parameters.value(ParameterID("curtain.panelCount"), of: s.element, s.model) == .int(4))
        #expect(Fx.approx(Parameters.value(ParameterID("curtain.mullionLength"), of: s.element, s.model)?.doubleValue ?? 0, 12))
        // Type rules are schedulable through the instance.
        #expect(Parameters.value(ParameterID("curtain.v.spacing"), of: s.element, s.model)?.doubleValue == 1.5)
        #expect(Parameters.typeEntries(s.model[s.type]!, s.model).contains { $0.name == "Vertical Grid: Layout" && $0.value == .text("Fixed Distance") })
    }

    @Test func planShowsPanelsAndCutMullions() throws {
        let s = try scene(border: true)
        let plan = s.model[s.ids.planViews[s.ids.levels[0]]!]!
        let g = ViewGraphicsBuilder(model: s.model, view: plan).build()
        let item = try #require(g.items.first { $0.elementID == s.wall })
        #expect(item.layer == .cut)
        let closed = item.primitives.filter { if case .polyline(_, true, _) = $0 { return true }; return false }
        // 4 panels + 3 interior + 2 border mullions.
        #expect(closed.count == 4 + 5)
        #expect(item.primitives.contains { if case .fill(let polys, _) = $0 { return polys.count == 5 }; return false })
        #expect(!item.hitPolygons.isEmpty)
        // Elevation: panels and mullions project as lines.
        let south = s.model.views.first { $0.name == "South" }!
        let eg = ViewGraphicsBuilder(model: s.model, view: south).build()
        #expect(eg.items.contains { $0.elementID == s.wall && !$0.primitives.isEmpty })
    }

    @Test func curvedCurtainWallsFacetAtGridLines() throws {
        var (m, ids) = Fx.template()
        var w: ElementID!
        try Fx.commit(&m) { tx in
            let t = Self.curtainType(tx, vertical: CurtainGridRule(layout: .fixedNumber, count: 5))
            let arc = Arc2(center: .zero, radius: 5, startAngle: 0, sweep: .pi / 2)
            w = tx.create(.walls, data: .wall(WallData(location: .arc(arc), topLevelID: ids.levels[1])), typeID: t, levelID: ids.levels[0])
        }
        let l = try #require(CurtainWallGeometry.layout(m[w]!, m))
        #expect(l.panels.count == 6)
        let solids = CurtainWallGeometry.panelSolids(m[w]!, m)
        #expect(solids.count == 6)
        // Each panel is flat: its vertices lie within the chord band, well inside the arc's sagitta.
        for (_, mesh) in solids {
            let b = mesh.bounds
            #expect(b.max.z - b.min.z > 3.9)
        }
    }

    @Test func curtainDataDecodesWithDefaults() throws {
        let dec = JSONDecoder()
        let rule = try dec.decode(CurtainGridRule.self, from: Data("{}".utf8))
        #expect(rule == CurtainGridRule())
        let spec = try dec.decode(CurtainSpec.self, from: Data(#"{"verticalMullions":true}"#.utf8))
        #expect(spec.verticalMullions && !spec.borderMullions && spec.mullion == MullionProfile())
        let inst = try dec.decode(CurtainInstanceData.self, from: Data(#"{"verticalGrids":[1.5]}"#.utf8))
        #expect(inst.verticalGrids == [1.5] && inst.panels.isEmpty)
        // Walls and types written before curtain walls existed have no curtain keys.
        let w = WallData(location: .line(Segment2(.zero, .unitX)))
        let json = try JSONEncoder().encode(w)
        #expect(!String(decoding: json, as: UTF8.self).contains("curtain"))
        let decoded = try dec.decode(WallData.self, from: json)
        #expect(decoded.curtain == nil)
        let td = try dec.decode(TypeData.self, from: JSONEncoder().encode(TypeData(instanceCategory: .walls, familyName: "Basic Wall")))
        #expect(td.curtain == nil)
    }
}
