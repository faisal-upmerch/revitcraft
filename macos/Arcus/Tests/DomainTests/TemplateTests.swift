import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

@Suite("Project templates")
struct TemplateTests {
    static let unitOptions: [UnitsSettings] = [.metric, .imperial]

    @Test(arguments: ProjectTemplateKind.allCases, unitOptions)
    func templatesBuildConsistently(_ kind: ProjectTemplateKind, _ units: UnitsSettings) {
        let (m, ids) = ProjectTemplates.make(kind, units: units, projectName: "T")
        #expect(m.units == units)
        #expect(m.projectInfo.projectName == "T")
        #expect(ModelHealth.check(m).isEmpty)
        let expectedLevels: [Double] = switch kind {
        case .architectural: [0, 4, 8]
        case .residential: [0, 2.8, 5.6]
        case .empty: [0, 3]
        }
        #expect(m.levels.compactMap { $0.level?.elevation } == expectedLevels)
        #expect(ids.levels == m.levels.map(\.id))
        for l in ids.levels {
            #expect(m[ids.planViews[l]]?.view?.kind == .floorPlan)
            #expect(m[ids.planViews[l]]?.levelID == l)
        }
        #expect(ids.ceilingViews.count == (kind == .empty ? 0 : ids.levels.count - 1))
        #expect(m.views.filter { $0.view?.kind == .elevation }.count == 4)
        #expect(m.views.filter { $0.view?.kind == .threeD }.count == 1)
        #expect(m.schedules.count == (kind == .empty ? 0 : 5))
        #expect(m.sheets.count == (kind == .empty ? 0 : 1))
        #expect(m.phases.count == 2 && m.latestPhase?.id == ids.phases[1])
        #expect(m.revisions.count == 1)
        // Every typed element points at a type of its own category; every family type at a family.
        for e in m.allElements {
            if let t = e.typeID { #expect(m[t]?.typeData?.instanceCategory == e.category) }
            if let f = e.typeData?.familyID { #expect(m[f]?.family != nil) }
            #expect(e.ifcGUID.isValid)
        }
        #expect(Set(m.allElements.map(\.ifcGUID)).count == m.count, "GUIDs are unique")
        for s in m.schedules { _ = ScheduleEngine.compute(s, m) }
    }

    @Test func residentialTemplateAddsTimberFrameWall() {
        let (m, ids) = ProjectTemplates.make(.residential, units: .metric)
        let t = m[ids.wallTypes["Exterior - Timber Frame Clad"]]!.typeData!.assembly!
        #expect(t.validate() == nil)
        #expect(Fx.approx(t.totalThickness, 0.02 + 0.14 + 0.09 + 0.0125, 1e-12))
        #expect(t.layers.contains { m[$0.materialID]?.name == "Membrane" && $0.function == .membrane })
        #expect(m.sheets[0].sheet?.paper == .a3)
        #expect(Fx.archMetric.0.sheets[0].sheet?.paper == .a1)
    }

    @Test(arguments: [(Fx.generic, 0.2), (Fx.brick, 0.38), ("Interior - 100mm Partition", 0.1), ("Interior - 150mm Masonry", 0.15), ("Exterior - Concrete 300mm", 0.3)])
    func wallTypeThicknesses(_ name: String, _ t: Double) {
        let (m, ids) = Fx.archMetric
        let a = m[ids.wallTypes[name]]!.typeData!.assembly!
        #expect(a.validate() == nil)
        #expect(Fx.approx(a.totalThickness, t, 1e-12))
        #expect(Parameters.value(ParameterID("type.width"), of: m[ids.wallTypes[name]]!, m)?.doubleValue.map { Fx.approx($0, t, 1e-12) } == true)
    }

    @Test func familyTypesCarryTheirFamilyValues() {
        let (m, ids) = Fx.archMetric
        let door = m[ids.familyTypes[Fx.doorType]]!
        #expect(door.typeData?.params[Parameters.familyParamID("Width")] == .double(0.9))
        #expect(door.typeData?.params[Parameters.familyParamID("Frame Material")] == .ref(ids.materials["Hardwood"]))
        let marks = m.types(for: .doors).compactMap { $0.typeData?.params[ParameterID("type.mark")]?.textValue }
        #expect(Set(marks).count == marks.count && marks.allSatisfy { $0.hasPrefix("D") })
    }
}

@Suite("Courtyard House fixture")
struct CourtyardFixtureTests {
    static let model = CourtyardHouse.make()

    @Test func statistics() {
        let m = Self.model
        let s = CourtyardHouse.stats(m)
        #expect(s.rooms == 120)
        #expect(s.openings >= 150)
        #expect(s.sheets == 16)
        #expect(s.schedules == 10)
        #expect(m.levels.count == 4)
        #expect(m.elements(.stairs).count >= 2)
        #expect(m.views.filter { $0.view?.kind == .elevation || $0.view?.kind == .section }.count >= 8)
        #expect(m.elements(.rooms).allSatisfy { RoomGeometry.boundary($0, m).state == .bounded })
    }

    @Test func everyDoorHasAHostAndEveryRoomAnArea() {
        let m = Self.model
        for d in m.elements(.doors) + m.elements(.windows) {
            #expect(m[d.hostID]?.wall != nil)
            #expect(WallGeometry.openings(m[d.hostID]!, m).contains { $0.insertID == d.id })
        }
        #expect(m.elements(.rooms).allSatisfy { RoomGeometry.boundary($0, m).area > 1 })
    }

    @Test func everySheetRendersItsViewports() {
        let m = Self.model
        for sheet in m.sheets {
            let vps = m.owned(byView: sheet.id).filter { $0.category == .viewports }
            let layouts = SheetGraphicsBuilder(model: m, sheet: sheet, viewGraphics: { _ in nil }).layouts()
            #expect(layouts.count == vps.count, "\(sheet.sheet!.number)")
        }
    }

    @Test func everyScheduleComputes() {
        let m = Self.model
        for s in m.schedules {
            let t = ScheduleEngine.compute(s, m)
            #expect(!t.columns.isEmpty, "\(s.name)")
        }
        let rooms = ScheduleEngine.compute(m.schedules.first { $0.name == "Room Schedule" }!, m)
        #expect(rooms.elementCount == 120)
    }

    @Test func geometryIsDeterministic() {
        let a = Self.model, b = CourtyardHouse.make()
        #expect(a.count == b.count)
        #expect(a.nextID == b.nextID)
        var differing = Set<String>()
        for e in a.allElements {
            guard var o = b[e.id] else { Issue.record("missing \(e.id)"); continue }
            o.ifcGUID = e.ifcGUID
            o.revision = e.revision  // revisions are process-unique cache stamps by design
            if o != e { differing.insert(e.category.rawValue) }
        }
        // Family solids/dimensions and schedule fields carry random UUIDs for sub-item identity; everything else must match.
        #expect(differing.isSubset(of: ["families", "schedules"]), "\(differing)")
    }

    @Test func buildingElementGUIDsAreDeterministic() {
        let a = Self.model, b = CourtyardHouse.make()
        let building: [ArcusDomain.Category] = [.walls, .doors, .windows, .rooms, .floors, .roofs, .stairs, .levels, .columns]
        let differing = a.elements(building).filter { b[$0.id]?.ifcGUID != $0.ifcGUID }
        #expect(differing.isEmpty, "\(differing.map { "\($0.category) \($0.id)" })")
    }

    @Test func allGUIDsAreDeterministic() {
        let a = Self.model, b = CourtyardHouse.make()
        let differing = a.allElements.filter { b[$0.id]?.ifcGUID != $0.ifcGUID }
        let categories = Set(differing.map(\.category.rawValue)).sorted()
        #expect(differing.isEmpty, "\(categories.joined(separator: ", "))")
    }

    @Test(arguments: [0, 1, 7, 500])
    func stressFixtureHasRequestedCount(_ count: Int) {
        let m = CourtyardHouse.stress(count: count)
        let walls = m.elements(.walls).count, columns = m.elements(.columns).count
        #expect(walls + columns == count)
        #expect(walls == (count + 1) / 2)
    }

    @Test func imperialCourtyardUsesImperialUnits() {
        let m = CourtyardHouse.make(units: .imperial)
        #expect(m.units.system == .imperial)
        #expect(CourtyardHouse.stats(m).rooms == 120)
    }
}
