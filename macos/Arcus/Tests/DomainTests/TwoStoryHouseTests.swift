import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// HOUSE: the Two-Story House sample meets its brief (program, lot, setbacks, stair code checks, enclosure, health)
/// and carries its documentation set.
@Suite("Two-Story House")
struct TwoStoryHouseTests {
    static let model = TwoStoryHouse.make()
    var m: BIMModel { Self.model }
    let ft = 0.3048, inch = 0.0254

    func rooms(_ name: String) -> [Element] { m.elements(.rooms).filter { $0.name == name } }
    func level(_ name: String) -> Element { m.levels.first { $0.name == name }! }

    @Test func imperialArchitecturalProjectWithTwoStoreysAndRoof() {
        #expect(m.units.system == .imperial)
        let elev = m.levels.compactMap { $0.level?.elevation }.sorted()
        #expect(elev.count == 3)
        #expect(abs(elev[1] - 10 * ft) < 1e-9 && abs(elev[2] - 20 * ft) < 1e-9)
    }

    @Test func programIsComplete() {
        #expect(rooms("Bedroom 1").count == 1 && rooms("Bedroom 2").count == 1)
        #expect(rooms("Living").count == 1)
        #expect(rooms("Kitchen / Dining").count == 1)
        #expect(m.elements(.rooms).filter { $0.name.hasPrefix("Balcony") }.count == 2)
        #expect(rooms("Garage").count == 1)
        #expect(rooms("Bath").count == 1 && rooms("Powder").count == 1)
        #expect(rooms("Closet").count == 2)
        // Bedrooms and balconies are upstairs; living, kitchen and garage downstairs.
        let upper = level("Upper Floor").id, ground = level("Ground Floor").id
        #expect(m.elements(.rooms).filter { ["Bedroom 1", "Bedroom 2", "Balcony 1", "Balcony 2", "Bath"].contains($0.name) }.allSatisfy { $0.levelID == upper })
        #expect(m.elements(.rooms).filter { ["Living", "Kitchen / Dining", "Garage", "Entry"].contains($0.name) }.allSatisfy { $0.levelID == ground })
    }

    @Test func everyRoomIsEnclosedAndSized() throws {
        for r in m.elements(.rooms) {
            let b = RoomGeometry.boundary(r, m)
            #expect(b.state == .bounded, "\(r.name) is not enclosed")
        }
        func sf(_ name: String) -> Double { (rooms(name).first.map { RoomGeometry.boundary($0, m).area } ?? 0) / (ft * ft) }
        #expect(sf("Bedroom 1") >= 120 && sf("Bedroom 2") >= 120)
        #expect(sf("Living") >= 150)
        #expect(sf("Bath") >= 40)
    }

    @Test func oneParkingSpaceWithACar() throws {
        let garage = try #require(rooms("Garage").first)
        let profile = try #require(RoomGeometry.boundary(garage, m).profile)
        let b = profile.bounds
        #expect(b.width >= 10 * ft - 1e-6 && b.height >= 20 * ft - 1e-6)
        let cars = m.elements(.entourage).filter { m[$0.typeID].flatMap { m[$0.typeData?.familyID] }?.name.hasPrefix("Car") == true }
        #expect(cars.count == 1)
        #expect(cars.allSatisfy { profile.outer.contains($0.component!.location) })
        // An overhead door on the street face.
        #expect(m.elements(.doors).contains { $0.mark == "101" && m[$0.typeID]?.name.contains("9'-0\"") == true })
    }

    @Test func lotIsFortyBySquareWithFootprintInsideSetbacks() {
        let lines = m.elements(.propertyLines).compactMap { $0.modelLine?.curve.asSegment }
        #expect(lines.count == 4)
        let lot = lines.reduce(Rect2.empty) { $0.union($1.bounds) }
        #expect(abs(lot.width - 40 * ft) < 1e-6 && abs(lot.height - 40 * ft) < 1e-6)
        #expect(abs(lot.width * lot.height / (ft * ft) - 1600) < 1e-3)
        // Every wall lies within the 5'-0" setbacks; the footprint is a 30'-0" square.
        let buildable = Rect2(min: lot.min + Vec2(5 * ft, 5 * ft), max: lot.max - Vec2(5 * ft, 5 * ft)).expanded(by: 1e-6)
        var footprint = Rect2.empty
        for w in m.elements(.walls) {
            guard let fp = WallGeometry.footprint(w, m) else { continue }
            footprint = footprint.union(fp.bounds)
            #expect(fp.points.allSatisfy { buildable.contains($0) })
        }
        #expect(abs(footprint.width - 30 * ft) < 1e-6 && abs(footprint.height - 30 * ft) < 1e-6)
        #expect(m.elements(.topography).contains { $0.isToposolid })
    }

    @Test func stairMeetsResidentialRules() throws {
        let stair = try #require(m.elements(.stairs).first)
        let l = try #require(StairGeometry.layout(stair, m))
        #expect(l.warnings.isEmpty)
        #expect(l.riserHeight <= 7.75 * inch)
        #expect(l.treadDepth >= 10 * inch)
        #expect(l.width >= 36 * inch)
        #expect(abs(l.topZ - l.baseZ - 10 * ft) < 1e-9)
        // Handrails on both sides; the upper floor is cut over the whole stair (headroom), with a guard at its edge.
        #expect(m.elements(.railings).filter { $0.hostID == stair.id }.count == 2)
        let shaft = try #require(m.elements(.shaftOpenings).first)
        let cut = ShaftCuts.cutElements(by: shaft, m)
        #expect(cut.contains { $0.name == "Upper Floor Slab" })
        #expect(!cut.contains { $0.name == "Slab on Grade" })
        let hole = try #require(ShaftCuts.profile(shaft)).bounds.expanded(by: 0.01)
        for r in l.runs { #expect(l.runRect(r).points.allSatisfy { hole.contains($0) }) }
        // U-stair rails follow the landing instead of crossing it.
        for rail in m.elements(.railings) where rail.hostID == stair.id {
            let pts = StairGeometry.railingPath(stair, m, leftSide: rail.railing!.hostSideLeft)
            for (a, b) in zip(pts, pts.dropFirst()) {
                let d = (b.xy - a.xy)
                #expect(abs(d.x) < 1e-6 || abs(d.y) < 1e-6, "rail segment runs diagonally across the landing")
            }
        }
    }

    @Test func bedroomsHaveEgressWindowsAndBalconyDoors() {
        let upper = level("Upper Floor").id
        let egress = m.elements(.windows).filter { w in
            w.levelID == upper && (w.insert?.sillHeight ?? 99) <= 44 * inch && (m[w.typeID]?.typeData?.familyName.contains("Casement") == true)
        }
        #expect(egress.count >= 2)
        let sliders = m.elements(.doors).filter { m[$0.typeID]?.typeData?.familyName == "Door - Sliding Glass" }
        #expect(sliders.count == 2)
        #expect(m.elements(.railings).filter { $0.levelID == upper && $0.hostID == nil }.count == 3) // two balcony guards, one stair guard
    }

    @Test func modelIsHealthy() {
        let health = ModelHealth.check(m)
        #expect(!health.contains { $0.severity == .error })
        #expect(health.isEmpty, "\(health.map(\.message))")
    }

    @Test func documentationSetIsComplete() {
        let views = m.views
        #expect(views.filter { $0.view?.kind == .floorPlan }.count >= 4) // two floors, roof, site
        #expect(views.filter { $0.view?.kind == .elevation }.count == 4)
        #expect(views.filter { $0.view?.kind == .section }.count == 2)
        #expect(views.contains { $0.view?.kind == .threeD })
        #expect(m.schedules.contains { $0.name == "Room Schedule" })
        let numbers = Set(m.sheets.compactMap { $0.sheet?.number })
        #expect(numbers.isSuperset(of: ["A000", "A001", "A101", "A102", "A201", "A301", "A401"]))
        #expect(m.sheets.allSatisfy { $0.sheet?.paper == .archD && $0.sheet?.titleBlockTypeID != nil })
        // Plans carry room tags and dimensions; every room is tagged.
        for name in ["Ground Floor Plan", "Upper Floor Plan"] {
            let v = views.first { $0.name == name }!
            #expect(m.elements(.dimensions).filter { $0.ownerViewID == v.id }.count >= 6)
        }
        let tagged = Set(m.elements(.tags).compactMap { $0.tag?.taggedID })
        #expect(m.elements(.rooms).allSatisfy { tagged.contains($0.id) })
        // Every placed view is on a sheet.
        let placed = Set(m.elements(.viewports).compactMap { $0.viewport?.viewID })
        for name in ["Site Plan", "Ground Floor Plan", "Upper Floor Plan", "Section 1", "Section 2", "South Elevation", "{3D}"] {
            #expect(views.contains { $0.name == name && placed.contains($0.id) }, "\(name) is not on a sheet")
        }
    }

    @Test func drawingsBuild() {
        for v in m.views where [.floorPlan, .elevation, .section].contains(v.view?.kind) {
            #expect(!ViewGraphicsBuilder(model: m, view: v).build().items.isEmpty, "\(v.name) is empty")
        }
        for s in m.sheets { #expect(!SheetGraphicsBuilder(model: m, sheet: s).build().items.isEmpty) }
    }
}
