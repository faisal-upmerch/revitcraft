import Foundation
import ArcusGeometry
import ArcusCalc

/// HOUSE: a two-storey house on a square 40'-0" × 40'-0" (1,600 sq ft) lot, built with the domain API the way the
/// sample project is. Imperial, Architectural template.
///
/// Program: one-car garage, entry, living room, kitchen / dining, powder room, laundry, U-shaped stair (ground);
/// two bedrooms with closets, full bath, linen, hall and two recessed balconies (upper). 30'-0" × 30'-0" square
/// footprint on 5'-0" setbacks, 10'-0" floor to floor, flat roof behind a 3'-0" parapet.
///
/// Construction: 8" CMU exterior walls with 2" XPS and furred gypsum board, 6" CMU garage separation walls,
/// 2x4 partitions (wet-area partitions at the bath), 6" concrete upper floor with tile, slab on grade, TPO roof on
/// tapered insulation over an 8" concrete slab. All positions are in feet from the lot's south-west corner
/// (street side south).
public enum TwoStoryHouse {
    public static let projectName = "Two-Story House"

    /// Design dimensions (feet).
    public enum Dim {
        public static let lot = 40.0
        public static let setback = 5.0
        public static let footprint = 30.0
        public static let floorToFloor = 10.0
        public static let parapet = 3.0
        public static let tread = 11.0 / 12
        public static let garageWidth = 10.5
        public static let garageDepth = 20.5
        /// Exterior wall: 7/8" stucco, 8" CMU, 2" XPS, 7/8" furring, 5/8" gypsum board = 12".
        public static let exteriorWall = 1.0
    }

    /// Feet to meters.
    @inlinable public static func ft(_ v: Double) -> Double { v * 0.3048 }
    static func P(_ x: Double, _ y: Double) -> Vec2 { Vec2(ft(x), ft(y)) }

    public static func make() -> BIMModel {
        let tx = TransactionContext(model: BIMModel(), name: projectName)
        let ids = ProjectTemplates.populate(tx, kind: .architectural, units: .imperial, projectName: projectName)
        Builder(tx: tx, ids: ids).build()
        // Reproducible file: every element gets a GUID derived from its (deterministic) id.
        for e in tx.model.allElements { tx.update(e.id) { $0.ifcGUID = .deterministic("two-story-house/\(e.id.raw)") } }
        do {
            return try tx.commit().model
        } catch {
            preconditionFailure("Two-Story House failed validation: \(error)")
        }
    }

    // MARK: - Builder

    final class Builder {
        let tx: TransactionContext
        let ids: ProjectTemplates.Ids
        var m: BIMModel { tx.model }

        init(tx: TransactionContext, ids: ProjectTemplates.Ids) { self.tx = tx; self.ids = ids }

        // Levels and views.
        var ground = ElementID(0), upper = ElementID(0), roof = ElementID(0)
        var groundPlan = ElementID(0), upperPlan = ElementID(0), roofPlan = ElementID(0), sitePlan = ElementID(0)
        var sections: [ElementID] = []
        var cutaways: [ElementID] = []

        // Types.
        var extWall = ElementID(0), garageWall = ElementID(0), partition = ElementID(0), wetWall = ElementID(0)
        var slabOnGrade = ElementID(0), upperFloorType = ElementID(0), balconyFloor = ElementID(0), roofType = ElementID(0)

        // Thicknesses (feet) and key lines (feet, wall centerlines unless noted).
        var te = 0.0, tg = 0.0, tp = 0.0, tw = 0.0
        var e0 = 0.0, e1 = 0.0, i0 = 0.0, i1 = 0.0
        var gx = 0.0, gy = 0.0, ux = 0.0
        var sy = 0.0, stairX0 = 0.0, stairY0 = 0.0, stairWidth = 0.0
        var hx = 0.0, by = 0.0
        var c1x = 0.0, c1y = 0.0, c2x = 0.0, c2y = 0.0
        var slabThk = 0.0, roofThk = 0.0
        let kitchenLine = 18.5, entryEast = 21.0, entryNorth = 11.0

        // Walls by role.
        var walls: [String: ElementID] = [:]

        func t(_ name: String) -> ElementID {
            if let id = ids.familyTypes[name] ?? ids.systemTypes[name] ?? ids.wallTypes[name] ?? ids.floorTypes[name] ?? ids.roofTypes[name] { return id }
            preconditionFailure("Two-Story House: missing type \(name)")
        }
        func thickness(_ type: ElementID) -> Double { (m[type]?.typeData?.assembly?.totalThickness ?? 0) / 0.3048 }

        /// The house's exterior wall type: stucco on insulated 8" CMU, exactly 12" so plan dimensions stay round.
        func stuccoCMUWall() -> ElementID {
            let names = ["Stucco, Portland Cement", "Concrete Masonry Units", "Rigid Insulation, XPS", "Metal Stud", "Gypsum Wall Board"]
            StandardContent.addMaterials(names, to: tx)
            func layer(_ f: LayerFunction, _ name: String, _ inches: Double) -> AssemblyLayer {
                AssemblyLayer(function: f, materialID: m.material(named: name)?.id, thickness: ft(inches / 12))
            }
            var td = TypeData(instanceCategory: .walls, systemFamily: .basicWall, familyName: "Basic Wall", assembly: CompoundAssembly(layers: [
                layer(.finish1, names[0], 0.875), layer(.structure, names[1], 7.625), layer(.thermal, names[2], 2),
                layer(.substrate, names[3], 0.875), layer(.finish2, names[4], 0.625),
            ]))
            td.params[ParameterID("type.function")] = .text("Exterior")
            td.params[ParameterID("type.mark")] = .text("EX1")
            return tx.create(.elementTypes, name: "Exterior - Stucco on 8\" CMU Insulated (12\")", data: .type(td))
        }

        func build() {
            setUpLevels()
            setUpTypes()
            groundFloor()
            upperFloor()
            openings()
            stair()
            roofAndSlabs()
            site()
            furniture()
            documentation()
        }

        // MARK: Levels

        func setUpLevels() {
            ground = ids.levels[0]; upper = ids.levels[1]; roof = ids.levels[2]
            tx.update(ground) { $0.name = "Ground Floor"; $0.level?.elevation = 0 }
            tx.update(upper) { $0.name = "Upper Floor"; $0.level?.elevation = ft(Dim.floorToFloor) }
            tx.update(roof) { $0.name = "Roof"; $0.level?.elevation = ft(2 * Dim.floorToFloor) }
            for v in m.views where v.levelID != nil {
                if let lname = m[v.levelID]?.name { tx.update(v.id) { $0.name = lname } }
            }
            groundPlan = ids.planViews[ground]!
            upperPlan = ids.planViews[upper]!
            roofPlan = ids.planViews[roof]!
            tx.update(roofPlan) { $0.name = "Roof Plan" }
            for s in m.sheets { tx.delete(s.id) }
            tx.update(m.elements(.projectInfo)[0].id) {
                $0.projectInfo?.projectNumber = "2026-014"
                $0.projectInfo?.clientName = "Owner"
                $0.projectInfo?.address = "40' x 40' Lot (1,600 SF)"
                $0.projectInfo?.status = "Schematic Design"
                $0.projectInfo?.issueDate = "2026-10-19"
                $0.projectInfo?.buildingName = projectName
            }
        }

        func setUpTypes() {
            extWall = stuccoCMUWall()
            garageWall = t("Generic - 6\"")
            partition = t("Interior - 4 1/2\" Partition (2x4)")
            wetWall = t("Interior - 4 3/4\" Partition (Wet Area)")
            slabOnGrade = t("Slab on Grade 4\" w/ Vapor Retarder")
            upperFloorType = t("Concrete Slab 6\"")
            balconyFloor = t("Pavers on Concrete Slab 6\"")
            roofType = t("TPO on Rigid Insulation - Concrete Slab 8\"")
            te = thickness(extWall); tg = thickness(garageWall); tp = thickness(partition); tw = thickness(wetWall)
            slabThk = thickness(upperFloorType); roofThk = thickness(roofType)

            let s = Dim.setback, f = Dim.footprint
            e0 = s + te / 2; e1 = s + f - te / 2
            i0 = s + te; i1 = s + f - te
            // Garage: 10'-6" × 20'-6" clear behind the 6" CMU separation walls.
            gx = i0 + Dim.garageWidth + tg / 2
            gy = i0 + Dim.garageDepth + tg / 2
            ux = 11.25
            // U-stair along the north wall: two runs and the gap between them, landing against the east wall.
            sy = 27.25
            stairY0 = sy + tp / 2
            stairWidth = (i1 - stairY0 - 0.1 / 0.3048) / 2
            stairX0 = i1 - (8 * Dim.tread + stairWidth)
            // Upper floor: 4'-0" hall east of the bath / bedroom 2 line; loggia back wall 6'-0" in from the facade.
            hx = gx + 4.5
            by = s + 6.0 + te / 2
            // Reach-in closets 2'-4" deep: bedroom 2 (4'-6" wide, NE corner), bedroom 1 (6'-6" wide, NE corner).
            c2y = gy - tw / 2 - 28.0 / 12 - tp / 2
            c2x = gx - tp / 2 - 4.5 - tp / 2
            c1y = sy - tp / 2 - 28.0 / 12 - tp / 2
            c1x = i1 - 6.5 - tp / 2
        }

        // MARK: Walls

        @discardableResult
        func wall(_ key: String, _ a: (Double, Double), _ b: (Double, Double), type: ElementID, level: ElementID, top: ElementID?,
                  topOffset: Double = 0, baseOffset: Double = 0, structural: Bool = false, joins: Bool = true) -> ElementID {
            var wd = WallData(location: .line(Segment2(P(a.0, a.1), P(b.0, b.1))), baseOffset: ft(baseOffset), topLevelID: top, topOffset: ft(topOffset))
            wd.structural = structural
            wd.allowJoinAtStart = joins; wd.allowJoinAtEnd = joins
            let id = tx.create(.walls, data: .wall(wd), typeID: type, levelID: level)
            walls[key] = id
            return id
        }

        /// Room separation line (bounds open-plan rooms).
        func separation(_ a: (Double, Double), _ b: (Double, Double), level: ElementID) {
            tx.create(.roomSeparationLines, data: .modelLine(ModelLineData(curve: .line(Segment2(P(a.0, a.1), P(b.0, b.1))))), levelID: level)
        }

        func groundFloor() {
            // Exterior walls, clockwise so the exterior face is outward, from 6" below the slab (grade) to the upper floor.
            let corners = [(e0, e0), (e0, e1), (e1, e1), (e1, e0)]
            for (k, name) in ["G.W", "G.N", "G.E", "G.S"].enumerated() {
                wall(name, corners[k], corners[(k + 1) % 4], type: extWall, level: ground, top: upper, baseOffset: -0.5, structural: true)
            }
            // Garage separation walls (6" CMU): east wall runs the full depth (garage, then powder room / hall).
            let under = -slabThk
            wall("G.garageE", (gx, e0), (gx, e1), type: garageWall, level: ground, top: upper, topOffset: under, structural: true)
            wall("G.garageN", (e0, gy), (gx, gy), type: garageWall, level: ground, top: upper, topOffset: under, structural: true)
            // Laundry | powder room.
            wall("G.laundry", (ux, gy), (ux, e1), type: partition, level: ground, top: upper, topOffset: under)
            // Stair wall (south side of the stair, kitchen counters against it).
            wall("G.stair", (stairX0, sy), (e1, sy), type: partition, level: ground, top: upper, topOffset: under)
            // Open plan: entry, living, kitchen / dining, hall and stair separated by room separation lines.
            separation((entryEast, e0), (entryEast, entryNorth), level: ground)
            separation((gx, entryNorth), (entryEast, entryNorth), level: ground)
            separation((gx, kitchenLine), (e1, kitchenLine), level: ground)
            separation((gx, sy), (stairX0, sy), level: ground)
            separation((stairX0, sy), (stairX0, e1), level: ground)
        }

        func upperFloor() {
            let parapet = Dim.parapet
            let underRoof = -roofThk
            // Perimeter: west, north and east walls to the parapet top.
            let face = Dim.setback
            wall("U.W", (e0, face), (e0, e1), type: extWall, level: upper, top: roof, topOffset: parapet, structural: true)
            wall("U.N", (e0, e1), (e1, e1), type: extWall, level: upper, top: roof, topOffset: parapet, structural: true)
            wall("U.E", (e1, e1), (e1, face), type: extWall, level: upper, top: roof, topOffset: parapet, structural: true)
            // South facade: a solid pier between the two loggias, and spandrels (lintel + parapet) over them. The
            // spandrels sit above the plan cut and don't join, so the plans show clean loggia corners.
            let lintel = 8.5
            wall("U.S.east", (e1, e0), (hx, e0), type: extWall, level: upper, top: roof, topOffset: parapet, baseOffset: lintel, joins: false)
            wall("U.S.pier", (hx, e0), (gx, e0), type: extWall, level: upper, top: roof, topOffset: parapet, structural: true)
            wall("U.S.west", (gx, e0), (e0, e0), type: extWall, level: upper, top: roof, topOffset: parapet, baseOffset: lintel, joins: false)
            // Loggia walls: pier sides and the back wall with the balcony doors (exterior faces toward the loggias).
            wall("U.pierW", (gx, e0), (gx, by), type: extWall, level: upper, top: roof, topOffset: underRoof)
            wall("U.pierE", (hx, by), (hx, e0), type: extWall, level: upper, top: roof, topOffset: underRoof)
            wall("U.back", (e1, by), (e0, by), type: extWall, level: upper, top: roof, topOffset: underRoof, structural: true)
            // Partitions.
            wall("U.hallW", (gx, by), (gx, gy), type: partition, level: upper, top: roof, topOffset: underRoof)
            wall("U.bathE", (gx, gy), (gx, e1), type: wetWall, level: upper, top: roof, topOffset: underRoof)
            wall("U.bathS", (e0, gy), (gx, gy), type: wetWall, level: upper, top: roof, topOffset: underRoof)
            wall("U.hallE", (hx, by), (hx, sy), type: partition, level: upper, top: roof, topOffset: underRoof)
            wall("U.stair", (hx, sy), (e1, sy), type: partition, level: upper, top: roof, topOffset: underRoof)
            wall("U.closet2S", (c2x, c2y), (gx, c2y), type: partition, level: upper, top: roof, topOffset: underRoof)
            wall("U.closet2W", (c2x, c2y), (c2x, gy), type: partition, level: upper, top: roof, topOffset: underRoof)
            wall("U.closet1S", (c1x, c1y), (e1, c1y), type: partition, level: upper, top: roof, topOffset: underRoof)
            wall("U.closet1W", (c1x, c1y), (c1x, sy), type: partition, level: upper, top: roof, topOffset: underRoof)
            // Upper hall: open to the stair landing.
            separation((stairX0, sy), (stairX0, e1), level: upper)
            // Balconies: open on the street side.
            separation((e0, e0), (gx, e0), level: upper)
            separation((hx, e0), (e1, e0), level: upper)
        }

        // MARK: Openings

        @discardableResult
        func door(_ type: String, host: String, at p: (Double, Double), level: ElementID, flip: Bool = false, hand: Bool = false, mark: String) -> ElementID {
            tx.create(.doors, data: .insert(InsertData(location: P(p.0, p.1))), typeID: t(type), levelID: level, hostID: walls[host]!) {
                $0.mark = mark
                $0.insert?.facingFlipped = flip
                $0.insert?.handFlipped = hand
            }
        }

        @discardableResult
        func window(_ type: String, host: String, at p: (Double, Double), sill: Double, level: ElementID) -> ElementID {
            tx.create(.windows, data: .insert(InsertData(location: P(p.0, p.1), sillHeight: ft(sill))), typeID: t(type), levelID: level, hostID: walls[host]!)
        }

        var doors: [(ElementID, ElementID, Vec2)] = []   // door, plan view, tag head
        var windows: [(ElementID, ElementID, Vec2)] = []

        func openings() {
            let g = ground, u = upper
            func d(_ type: String, _ host: String, _ p: (Double, Double), _ level: ElementID, _ mark: String, tag: (Double, Double), flip: Bool = false, hand: Bool = false) {
                let id = door(type, host: host, at: p, level: level, flip: flip, hand: hand, mark: mark)
                doors.append((id, level == g ? groundPlan : upperPlan, P(tag.0, tag.1)))
            }
            // Window tags sit 1'-8" outside the wall face, inside the dimension strings.
            func w(_ type: String, _ host: String, _ p: (Double, Double), sill: Double, _ level: ElementID) {
                let id = window(type, host: host, at: p, sill: sill, level: level)
                let out = 1 + 2.0 / 3
                let lo = Dim.setback - out, hi = Dim.setback + Dim.footprint + out
                let tag = host.hasSuffix(".S") ? (p.0, lo) : host.hasSuffix(".N") ? (p.0, hi) : host.hasSuffix(".E") ? (hi, p.1) : (lo, p.1)
                windows.append((id, level == g ? groundPlan : upperPlan, P(tag.0, tag.1)))
            }
            let garageCx = (i0 + gx - tg / 2) / 2
            let entryCx = (gx + tg / 2 + entryEast) / 2
            // Ground floor doors.
            d("Door - Overhead Sectional: 9'-0\" x 7'-0\"", "G.S", (garageCx, e0), g, "101", tag: (garageCx, 3.3))
            d("Door - Single Panel: 36\" x 80\"", "G.S", (entryCx, e0), g, "102", tag: (entryCx, 3.3))
            d("Door - Fire Rated Single: 36\" x 80\" (20 min)", "G.garageE", (gx, 8.6), g, "101A", tag: (gx - 1.8, 10.6), flip: true)
            d("Door - Fire Rated Single: 36\" x 80\" (20 min)", "G.garageN", ((i0 + ux) / 2, gy), g, "108", tag: ((i0 + ux) / 2 + 2.6, gy - 1.6))
            d("Door - Single Panel: 30\" x 80\"", "G.garageE", (gx, 30.0), g, "107", tag: (gx + 2.2, 32.6))
            // Upper floor doors.
            let bed2Cx = (i0 + gx - te / 2) / 2, bed1Cx = (hx + te / 2 + i1) / 2
            d("Door - Sliding Glass: 72\" x 80\"", "U.back", (bed2Cx, by), u, "203A", tag: (bed2Cx, by + 1.6))
            d("Door - Sliding Glass: 72\" x 80\"", "U.back", (bed1Cx, by), u, "201A", tag: (bed1Cx, by + 1.6))
            d("Door - Single Panel: 30\" x 80\"", "U.back", ((gx + hx) / 2, by), u, "207", tag: ((gx + hx) / 2, by + 1.7), flip: true)
            d("Door - Single Panel: 32\" x 80\"", "U.hallW", (gx, 21.0), u, "203", tag: (gx - 2.2, 18.8), flip: true)
            d("Door - Single Panel: 32\" x 80\"", "U.hallE", (hx, 24.6), u, "201", tag: (hx + 2.4, 21.8))
            d("Door - Single Panel: 30\" x 80\"", "U.bathE", (gx, 29.0), u, "205", tag: (gx - 2.2, 31.2), flip: true)
            d("Door - Bifold 2-Leaf: 36\" x 80\"", "U.closet2S", ((c2x + gx) / 2, c2y), u, "204", tag: ((c2x + gx) / 2, c2y - 1.6))
            d("Door - Bifold 4-Leaf: 60\" x 80\"", "U.closet1S", ((c1x + e1) / 2, c1y), u, "202", tag: ((c1x + e1) / 2, c1y - 1.6))
            // Windows: living, kitchen (over the sink), dining / hall, powder, laundry, stair, garage.
            w("Window - Casement Double: 72\" x 60\"", "G.S", (27.6, e0), sill: 2.5, g)
            w("Window - Casement: 48\" x 60\"", "G.E", (e1, 12.4), sill: 2.5, g)
            w("Window - Casement Double: 48\" x 48\"", "G.E", (e1, 22.5), sill: 3.5, g)
            w("Window - Casement: 36\" x 60\"", "G.N", (20.2, e1), sill: 2.5, g)
            w("Window - Awning: 36\" x 24\"", "G.N", ((ux + gx) / 2, e1), sill: 5.0, g)
            w("Window - Awning: 36\" x 24\"", "G.N", ((i0 + ux) / 2, e1), sill: 5.0, g)
            w("Window - Awning: 48\" x 24\"", "G.E", (e1, 31.6), sill: 7.0, g)
            w("Window - Single Hung: 32\" x 54\"", "G.W", (e0, 16.0), sill: 3.0, g)
            // Bedrooms: egress casements (sill 2'-6", well under 44"), bath, hall, stair.
            w("Window - Casement: 36\" x 60\"", "U.E", (e1, 17.5), sill: 2.5, u)
            w("Window - Casement: 36\" x 60\"", "U.W", (e0, 15.0), sill: 2.5, u)
            w("Window - Awning: 36\" x 24\"", "U.N", (10.2, e1), sill: 5.0, u)
            w("Window - Casement: 36\" x 60\"", "U.N", (20.2, e1), sill: 2.5, u)
            w("Window - Fixed: 36\" x 60\"", "U.E", (e1, 31.6), sill: 2.5, u)
        }

        // MARK: Stair

        var stairID = ElementID(0)

        func stair() {
            var sd = StairData(shape: .uShaped, origin: P(stairX0, stairY0 + stairWidth / 2), direction: 0, width: ft(stairWidth), topLevelID: upper)
            sd.turnsLeft = true
            sd.desiredRiserCount = 18
            sd.firstRunRisers = 9
            stairID = tx.create(.stairs, data: .stair(sd), typeID: t("Monolithic - 7\" max riser"), levelID: ground)
            for left in [true, false] {
                var rd = RailingData(path: [])
                rd.followsHost = true; rd.hostSideLeft = left
                tx.create(.railings, data: .railing(rd), typeID: t("Handrail - 36\""), levelID: ground, hostID: stairID)
            }
            // Stair shaft through the upper floor.
            let shaft = Sketch(rect: Rect2(min: P(stairX0, stairY0), max: P(i1, i1)))
            tx.create(.shaftOpenings, name: "Stair Shaft", data: .opening(.shaft(ShaftOpeningData(boundary: shaft, baseOffset: ft(Dim.floorToFloor - 1), topLevelID: upper, topOffset: ft(0.5)))),
                      levelID: ground)
            // Guard at the upper landing where the first run drops away.
            let guardX = stairX0 - 0.15
            tx.create(.railings, data: .railing(RailingData(path: [.line(Segment2(P(guardX, stairY0), P(guardX, stairY0 + stairWidth + 0.2)))])),
                      typeID: t("Guard - 42\""), levelID: upper)
        }

        // MARK: Floors and roof

        func roofAndSlabs() {
            // Slab on grade inside the exterior walls.
            tx.create(.floors, name: "Slab on Grade", data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: P(i0, i0), max: P(i1, i1))))), typeID: slabOnGrade, levelID: ground)
            // Upper floor: everything inside the exterior walls but the two balconies.
            let bal2W = gx - te / 2, bal1E = hx + te / 2, backFace = by - te / 2
            let poly = Polygon2([P(i0, backFace), P(bal2W, backFace), P(bal2W, i0), P(bal1E, i0), P(bal1E, backFace), P(i1, backFace), P(i1, i1), P(i0, i1)])
            var fd = SlabData(boundary: Sketch(polygon: poly))
            fd.structural = true
            tx.create(.floors, name: "Upper Floor Slab", data: .slab(fd), typeID: upperFloorType, levelID: upper)
            // Balcony slabs, 1 1/2" below the floor, between the loggia walls.
            for (name, r) in [("Balcony 2 Slab", Rect2(min: P(i0, i0), max: P(bal2W, backFace))), ("Balcony 1 Slab", Rect2(min: P(bal1E, i0), max: P(i1, backFace)))] {
                tx.create(.floors, name: name, data: .slab(SlabData(boundary: Sketch(rect: r), offset: ft(-1.5 / 12))), typeID: balconyFloor, levelID: upper)
            }
            // Flat roof (tapered insulation to drains) inside the parapets.
            let rr = Rect2(min: P(i0, i0), max: P(i1, i1))
            tx.create(.roofs, name: "Roof", data: .roof(RoofData(footprint: Sketch(rect: rr), edgeSlopes: [nil, nil, nil, nil])), typeID: roofType, levelID: roof)
            // Balcony guards on the parapet curb (top of the ground floor wall).
            let guardType = t("Guard - 42\"")
            for (a, b) in [(i0, bal2W), (bal1E, i1)] {
                tx.create(.railings, data: .railing(RailingData(path: [.line(Segment2(P(a, e0), P(b, e0)))])), typeID: guardType, levelID: upper)
            }
        }

        // MARK: Site

        var lotLines: [ElementID] = []

        func site() {
            let lot = [P(0, 0), P(Dim.lot, 0), P(Dim.lot, Dim.lot), P(0, Dim.lot)]
            for k in 0..<4 {
                lotLines.append(tx.create(.propertyLines, name: "Property Line", data: .modelLine(ModelLineData(curve: .line(Segment2(lot[k], lot[(k + 1) % 4])))), levelID: ground))
            }
            // Flat lot, finished grade 6" below the ground floor (the slab on grade sits in it; no excavation needed).
            if let topo = try? ToposolidOperations.create(outline: Polygon2(lot), elevation: ft(-0.5), levelID: ground, name: "Lot", in: tx) {
                let garageCx = (i0 + gx - tg / 2) / 2
                _ = try? ToposolidOperations.subdivide(topo, boundary: Polygon2.rectangle(Rect2(min: P(garageCx - 5.5, 0), max: P(garageCx + 5.5, Dim.setback))), in: tx)
                let entryCx = (gx + tg / 2 + entryEast) / 2
                _ = try? ToposolidOperations.subdivide(topo, boundary: Polygon2.rectangle(Rect2(min: P(entryCx - 2, 0), max: P(entryCx + 2, Dim.setback))), in: tx)
            }
        }

        // MARK: Furniture and fixtures

        func place(_ item: String, _ type: String, at p: (Double, Double), rotation: Double = 0, level: ElementID, offset: Double = 0) {
            guard let it = ComponentLibrary.item(named: item), let tid = ComponentLibraryLoader.load(it, typeName: type, in: tx) else {
                preconditionFailure("Two-Story House: missing library item \(item): \(type)")
            }
            let cat = m[tid]?.typeData?.instanceCategory ?? it.category
            tx.create(cat, data: .component(ComponentData(location: P(p.0, p.1), rotation: rotation, offset: ft(offset))), typeID: tid, levelID: level)
        }

        /// Library type depth along its local y (feet).
        func depth(_ item: String, _ type: String) -> Double {
            (ComponentLibrary.item(named: item)?.types.first { $0.name == type }?.depth ?? 0) / 0.3048
        }
        func width(_ item: String, _ type: String) -> Double {
            (ComponentLibrary.item(named: item)?.types.first { $0.name == type }?.width ?? 0) / 0.3048
        }

        func furniture() {
            let g = ground, u = upper
            let south = 0.0, north = Double.pi, east = Double.pi / 2, west = -Double.pi / 2 // facing directions (library fronts face -y)
            // Parking: one car in the garage, nose to the door.
            place("Car - Sedan", "Mid-Size", at: ((i0 + gx - tg / 2) / 2, i0 + Dim.garageDepth / 2 + 0.5), rotation: south, level: g)
            // Living: sofa facing the TV wall (east), armchair, coffee table, rug.
            place("Rug - Rectangular", "8' x 10'", at: (27.6, 12.2), rotation: west, level: g)
            place("Sofa - 3 Seat", "3 Seat 84\"", at: (23.4, 12.2), rotation: east, level: g)
            place("Coffee Table - Rectangular", "48\" x 24\"", at: (27.2, 12.2), rotation: west, level: g)
            place("Armchair - Upholstered", "32\"", at: (28.0, 8.4), rotation: north, level: g)
            place("TV Unit - Low", "72\"", at: (i1 - depth("TV Unit - Low", "72\"") / 2, 12.2), rotation: west, level: g)
            place("Console Table", "48\" x 14\"", at: (gx + tg / 2 + depth("Console Table", "48\" x 14\"") / 2, 15.6), rotation: east, level: g)
            // Kitchen: L along the stair wall and the east wall.
            let cab = { (n: String) in self.depth("Base Cabinet - US", n) }
            let nY = sy - tp / 2 - cab("36\"") / 2
            place("Base Cabinet - Corner", "36\" x 36\"", at: (i1 - 1.5, sy - tp / 2 - 1.5), rotation: south, level: g)
            place("Range - Freestanding", "30\"", at: (i1 - 3 - 1.25, sy - tp / 2 - depth("Range - Freestanding", "30\"") / 2), rotation: south, level: g)
            place("Base Cabinet - US", "24\"", at: (i1 - 5.5 - 1.0, nY), rotation: south, level: g)
            place("Refrigerator - French Door", "36\"", at: (i1 - 7.5 - 1.5, sy - tp / 2 - depth("Refrigerator - French Door", "36\"") / 2), rotation: south, level: g)
            let eX = i1 - cab("36\"") / 2
            let sinkY = sy - tp / 2 - 3 - 1.5
            place("Sink Base Cabinet - US", "36\"", at: (eX, sinkY), rotation: west, level: g)
            place("Kitchen Sink - Double Bowl", "33\" x 22\"", at: (eX, sinkY), rotation: west, level: g, offset: 0)
            place("Dishwasher", "24\"", at: (i1 - depth("Dishwasher", "24\"") / 2, sinkY - 1.5 - 1.0), rotation: west, level: g)
            // Dining.
            place("Dining Set - 6 Seat", "72\" x 36\"", at: (21.2, 22.6), rotation: west, level: g)
            // Powder room: WC on the back wall, lavatory on the side wall.
            let pX0 = ux + tp / 2
            place("WC - Floor Mounted", "Elongated 30\"", at: (pX0 + 1.6, i1 - depth("WC - Floor Mounted", "Elongated 30\"") / 2), rotation: south, level: g)
            place("Lavatory - Vanity", "24\"", at: (pX0 + depth("Lavatory - Vanity", "24\"") / 2, gy + tg / 2 + 1.6), rotation: east, level: g)
            // Laundry.
            place("Washer and Dryer - Stacked", "27\"", at: (i0 + 1.3, i1 - depth("Washer and Dryer - Stacked", "27\"") / 2), rotation: south, level: g)
            place("Laundry Tub", "24\"", at: (i0 + 3.6, i1 - depth("Laundry Tub", "24\"") / 2), rotation: south, level: g)

            // Bedroom 1 (east): queen bed against the hall wall, nightstands, dresser.
            let bed = ("Bed - US Standard", "Queen 60\" x 80\"")
            let b1x = hx + tp / 2 + depth(bed.0, bed.1) / 2
            place(bed.0, bed.1, at: (b1x, 18.0), rotation: east, level: u)
            for dy in [-3.6, 3.6] { place("Nightstand", "20\" x 16\"", at: (hx + tp / 2 + 0.75, 18.0 + dy), rotation: east, level: u) }
            place("Chest of Drawers - Tall", "36\"", at: (i1 - depth("Chest of Drawers - Tall", "36\"") / 2, 21.4), rotation: west, level: u)
            // Bedroom 2 (west): full bed against the west wall, nightstand, study desk.
            let bed2 = ("Bed - US Standard", "Full 54\" x 75\"")
            place(bed2.0, bed2.1, at: (i0 + depth(bed2.0, bed2.1) / 2, 20.0), rotation: east, level: u)
            place("Nightstand", "20\" x 16\"", at: (i0 + 0.75, 20.0 + 3.4), rotation: east, level: u)
            place("Desk - Kids Study", "36\"", at: (gx - tp / 2 - depth("Desk - Kids Study", "36\"") / 2, 15.2), rotation: west, level: u)
            // Bath: tub along the west wall, WC and vanity on the north wall.
            let tub = ("Bathtub - Alcove", "60\" x 30\"")
            place(tub.0, tub.1, at: (i0 + depth(tub.0, tub.1) / 2, i1 - width(tub.0, tub.1) / 2), rotation: east, level: u)
            place("WC - Floor Mounted", "Elongated 30\"", at: (10.2, i1 - depth("WC - Floor Mounted", "Elongated 30\"") / 2), rotation: south, level: u)
            place("Lavatory - Vanity", "36\"", at: (13.6, i1 - depth("Lavatory - Vanity", "36\"") / 2), rotation: south, level: u)
            // Balconies: two lounge chairs and a side table each.
            for cx in [(i0 + gx - te / 2) / 2, (hx + te / 2 + i1) / 2] {
                place("Chair - Lounge", "30\"", at: (cx - 1.7, 8.6), rotation: south, level: u)
                place("Chair - Lounge", "30\"", at: (cx + 1.7, 8.6), rotation: south, level: u)
                place("Side Table", "20\" x 20\"", at: (cx, 8.9), level: u)
            }
            // Site planting.
            place("Tree - Flowering Small", "10'", at: (37.5, 2.5), level: g)
            place("Tree - Flowering Small", "10'", at: (2.5, 37.5), level: g)
        }

        // MARK: Documentation

        func documentation() {
            rooms()
            planViews()
            dimensions()
            elevationsAndSections()
            threeD()
            sheets()
        }

        var roomTags: [(ElementID, ElementID, Vec2)] = []

        func rooms() {
            let tag = t("Room Tag: Name, Number and Area")
            func room(_ name: String, _ number: String, _ p: (Double, Double), _ level: ElementID, dept: String, finish: String, tagAt: (Double, Double)? = nil) {
                let id = tx.create(.rooms, name: name, data: .room(RoomData(point: P(p.0, p.1), number: number, limitOffset: ft(9))), levelID: level) {
                    $0.params[ParameterID("room.department")] = .text(dept)
                    $0.params[ParameterID("room.floorFinish")] = .text(finish)
                }
                let head = tagAt ?? p
                tx.create(.tags, data: .tag(TagData(taggedID: id, head: P(head.0, head.1))), typeID: tag, ownerViewID: level == ground ? groundPlan : upperPlan)
            }
            let g = ground, u = upper
            let garageCx = (i0 + gx - tg / 2) / 2
            room("Garage", "101", (garageCx, 21.5), g, dept: "Parking", finish: "Sealed Concrete", tagAt: (garageCx, 24.0))
            room("Entry", "102", ((gx + entryEast) / 2, 9.6), g, dept: "Circulation", finish: "Porcelain Tile")
            room("Living", "103", (30.4, 15.8), g, dept: "Living", finish: "Engineered Wood")
            room("Kitchen / Dining", "104", (25.6, 21.9), g, dept: "Living", finish: "Porcelain Tile", tagAt: (26.6, 21.4))
            room("Hall", "105", ((gx + stairX0) / 2, 31.4), g, dept: "Circulation", finish: "Porcelain Tile")
            room("Stair", "106", (25.4, 29.0), g, dept: "Circulation", finish: "Concrete")
            room("Powder", "107", ((ux + gx) / 2, 29.2), g, dept: "Service", finish: "Porcelain Tile")
            room("Laundry", "108", ((i0 + ux) / 2, 29.2), g, dept: "Service", finish: "Porcelain Tile")
            room("Bedroom 1", "201", (31.0, 15.0), u, dept: "Bedrooms", finish: "Engineered Wood")
            room("Closet", "202", ((c1x + i1) / 2, (c1y + sy) / 2), u, dept: "Bedrooms", finish: "Engineered Wood")
            room("Bedroom 2", "203", (11.0, 15.0), u, dept: "Bedrooms", finish: "Engineered Wood")
            room("Closet", "204", ((c2x + gx) / 2, (c2y + gy) / 2), u, dept: "Bedrooms", finish: "Engineered Wood")
            room("Bath", "205", (11.4, 29.6), u, dept: "Service", finish: "Porcelain Tile")
            room("Hall", "206", ((gx + hx) / 2, 16.5), u, dept: "Circulation", finish: "Engineered Wood")
            room("Linen", "207", ((gx + hx) / 2, 8.4), u, dept: "Service", finish: "Engineered Wood")
            room("Balcony 1", "208", ((hx + i1) / 2, 6.6), u, dept: "Outdoor", finish: "Concrete Pavers")
            room("Balcony 2", "209", ((i0 + gx) / 2, 6.6), u, dept: "Outdoor", finish: "Concrete Pavers")
        }

        func planViews() {
            let crop = Rect2(min: P(-5, -5), max: P(Dim.lot + 5, Dim.lot + 5))
            for v in [groundPlan, upperPlan, roofPlan] {
                tx.update(v) {
                    $0.view?.scale = 32
                    $0.view?.cropRegion = crop
                    $0.view?.cropActive = true
                    $0.view?.cropVisible = false
                    $0.view?.visibility.hiddenCategories.formUnion([.topography, .planting, .propertyLines])
                }
            }
            tx.update(groundPlan) { $0.name = "Ground Floor Plan" }
            tx.update(upperPlan) { $0.name = "Upper Floor Plan" }
            // Roof plan: cut through the parapets, depth to just under the roof slab (nothing below shows through).
            tx.update(roofPlan) { $0.view?.viewRange = ViewRange(topOffset: ft(10), cutOffset: ft(2), bottomOffset: ft(-1.5), depthOffset: ft(-1.5)) }
            // The ground floor plan shows the lot's front yard (driveway and walk) under the crop.
            var sp = ViewData(kind: .floorPlan, scale: 48)
            sp.viewRange = ViewRange(topOffset: ft(40), cutOffset: ft(35), bottomOffset: ft(-6), depthOffset: ft(-6))
            sp.phaseID = ids.phases.last
            sp.cropRegion = Rect2(min: P(-8, -11), max: P(Dim.lot + 8, Dim.lot + 6))
            sp.cropActive = true
            // The site plan shows the lot, grade, paving and planting with the building as its footprint outline.
            sp.visibility.hiddenCategories = [.walls, .doors, .windows, .floors, .stairs, .railings, .rooms, .roomSeparationLines, .furniture, .casework,
                                              .plumbingFixtures, .specialtyEquipment, .entourage, .shaftOpenings]
            sitePlan = tx.create(.views, name: "Site Plan", data: .view(sp), levelID: ground)
            let wide = m.elements(.lineStyles).first { $0.name == "Wide Lines" }?.id
            let fp = [P(Dim.setback, Dim.setback), P(Dim.setback + Dim.footprint, Dim.setback), P(Dim.setback + Dim.footprint, Dim.setback + Dim.footprint),
                      P(Dim.setback, Dim.setback + Dim.footprint)]
            for k in 0..<4 {
                tx.create(.detailLines, data: .modelLine(ModelLineData(curve: .line(Segment2(fp[k], fp[(k + 1) % 4])), styleID: wide)), ownerViewID: sitePlan)
            }
            // Tags.
            let doorTag = t("Door Tag: Standard"), windowTag = t("Window Tag: Standard")
            for (id, v, head) in doors { tx.create(.tags, data: .tag(TagData(taggedID: id, head: head)), typeID: doorTag, ownerViewID: v) }
            for (id, v, head) in windows { tx.create(.tags, data: .tag(TagData(taggedID: id, head: head)), typeID: windowTag, ownerViewID: v) }
            // Site plan: north arrow, notes.
            tx.create(.genericAnnotations, data: .detailComponent(DetailComponentData(location: P(Dim.lot + 4, Dim.lot + 2))), typeID: t("North Arrow: Standard"), ownerViewID: sitePlan)
            let note = t("Text 3/32\" Arial")
            tx.create(.textNotes, data: .textNote(TextNoteData(position: P(-6, -6), text: """
            LOT 40'-0" x 40'-0" = 1,600 SF. SETBACKS 5'-0" ALL SIDES.
            BUILDING FOOTPRINT 30'-0" x 30'-0" = 900 SF (56% LOT COVERAGE).
            DRIVEWAY TO ONE-CAR GARAGE; FINISHED GRADE 6" BELOW GROUND FLOOR.
            """)), typeID: note, ownerViewID: sitePlan)
            tx.create(.textNotes, data: .textNote(TextNoteData(position: P(Dim.lot / 2 - 4, -8.5), text: "STREET")), typeID: t("Text 1/4\" Arial Bold"), ownerViewID: sitePlan)
            for (p, text) in [((15.0, 23.0), "TWO-STORY HOUSE\nFLAT ROOF EL. 20'-0\"\nT.O. PARAPET EL. 23'-0\"\nGROUND FLOOR EL. 0'-0\""),
                              ((7.0, 2.0), "DRIVEWAY"), ((17.4, 2.0), "WALK")] {
                tx.create(.textNotes, data: .textNote(TextNoteData(position: P(p.0, p.1), text: text)), typeID: note, ownerViewID: sitePlan)
            }
            tx.create(.textNotes, data: .textNote(TextNoteData(position: P(10.0, 22.0), text: """
            TPO MEMBRANE ON TAPERED INSULATION OVER 8" CONCRETE SLAB,
            1/4" PER FOOT TO ROOF DRAINS. 3'-0" PARAPET ALL SIDES.
            """)), typeID: note, ownerViewID: roofPlan)
        }

        func dim(_ refs: [GeometryReference], at p: (Double, Double), view: ElementID) {
            tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: refs, linePoint: P(p.0, p.1))), typeID: ids.systemTypes["Dimension"], ownerViewID: view)
        }

        func dimensions() {
            func w(_ k: String) -> ElementID { walls[k]! }
            let ext = GeometryReference.Kind.exteriorFace, loc = GeometryReference.Kind.location
            // Ground floor: overall and chains on all four sides, garage clear sizes.
            let gp = groundPlan
            dim([.init(w("G.W"), ext), .init(w("G.E"), ext)], at: (20, 0.4), view: gp)
            dim([.init(w("G.W"), ext), .init(w("G.garageE"), loc), .init(w("G.E"), ext)], at: (20, 1.9), view: gp)
            dim([.init(w("G.S"), ext), .init(w("G.N"), ext)], at: (39.6, 20), view: gp)
            dim([.init(w("G.S"), ext), .init(w("G.stair"), loc), .init(w("G.N"), ext)], at: (38.1, 20), view: gp)
            dim([.init(w("G.W"), ext), .init(w("G.laundry"), loc), .init(w("G.garageE"), loc), .init(w("G.E"), ext)], at: (20, 38.1), view: gp)
            dim([.init(w("G.S"), ext), .init(w("G.garageN"), loc), .init(w("G.N"), ext)], at: (1.9, 20), view: gp)
            dim([.init(w("G.W"), .interiorFace), .init(w("G.garageE"), ext)], at: ((i0 + gx) / 2, 25.6), view: gp)
            dim([.init(w("G.S"), .interiorFace), .init(w("G.garageN"), .interiorFace)], at: (7.2, 16.0), view: gp)
            // Upper floor: overall, loggia / pier rhythm on the facade, bedroom depths.
            let up = upperPlan
            dim([.init(w("U.W"), ext), .init(w("U.E"), ext)], at: (20, 0.4), view: up)
            dim([.init(w("U.W"), ext), .init(w("U.pierW"), ext), .init(w("U.pierE"), ext), .init(w("U.E"), ext)], at: (20, 1.9), view: up)
            dim([.init(w("U.S.pier"), ext), .init(w("U.N"), ext)], at: (39.6, 20), view: up)
            dim([.init(w("U.S.pier"), ext), .init(w("U.back"), ext), .init(w("U.stair"), loc), .init(w("U.N"), ext)], at: (38.1, 20), view: up)
            dim([.init(w("U.W"), ext), .init(w("U.hallW"), loc), .init(w("U.hallE"), loc), .init(w("U.E"), ext)], at: (20, 38.1), view: up)
            dim([.init(w("U.S.pier"), ext), .init(w("U.back"), ext), .init(w("U.bathS"), loc), .init(w("U.N"), ext)], at: (1.9, 20), view: up)
            // Site plan: lot and setbacks.
            let sp = sitePlan
            dim([.init(lotLines[3], loc), .init(lotLines[1], loc)], at: (20, -4), view: sp)
            dim([.init(lotLines[0], loc), .init(lotLines[2], loc)], at: (Dim.lot + 4, 20), view: sp)
            let a = Dim.setback, b = Dim.setback + Dim.footprint
            dim([.init(lotLines[3], loc), .fixed(P(a, 20)), .fixed(P(b, 20)), .init(lotLines[1], loc)], at: (20, -1.6), view: sp)
            dim([.init(lotLines[0], loc), .fixed(P(20, a)), .fixed(P(20, b)), .init(lotLines[2], loc)], at: (Dim.lot + 1.6, 20), view: sp)
        }

        func elevationsAndSections() {
            let center = P(Dim.lot / 2, Dim.lot / 2)
            for e in m.views where e.view?.kind == .elevation {
                tx.update(e.id) { v in
                    guard var vd = v.view, let d = vd.viewDirection else { return }
                    vd.planeOrigin = Vec3(center - d * ft(30), z: 0)
                    vd.markerPosition = center - d * ft(23)
                    vd.farClip = ft(70)
                    vd.scale = 48
                    vd.cropRegion = Rect2(min: P(-23, -2), max: P(23, 26))
                    vd.cropActive = true
                    vd.visibility.hiddenCategories.insert(.planting)
                    v.view = vd
                    v.name = "\(v.name) Elevation"
                }
            }
            // Level lines span the building and its trees in every vertical view (u = 0 at the building's centre).
            for l in [ground, upper, roof] { tx.update(l) { $0.level?.extentStart = ft(-20.5); $0.level?.extentEnd = ft(18.5) } }
            // Section 1: east–west through the stair's first run, looking north. Section 2: north–south through the
            // stair, kitchen, living, bedroom 1 and its balcony, looking east.
            let runY = stairY0 + stairWidth / 2
            for (k, (a, b, far)) in [((-3.0, runY), (Dim.lot + 3, runY), 10.0), ((26.6, Dim.lot + 3), (26.6, -3.0), 30.0)].enumerated() {
                let pa = P(a.0, a.1), pb = P(b.0, b.1)
                var sv = ViewData(kind: .section, scale: 32)
                sv.viewDirection = (pb - pa).normalized.perpendicular
                sv.planeOrigin = Vec3((pa + pb) * 0.5, z: 0)
                sv.cropRegion = Rect2(min: Vec2(-pa.distance(to: pb) / 2, ft(-2.5)), max: Vec2(pa.distance(to: pb) / 2, ft(25)))
                sv.cropActive = true
                sv.farClip = ft(far)
                sv.phaseID = ids.phases.last
                sv.visibility.hiddenCategories.insert(.planting)
                sections.append(tx.create(.views, name: "Section \(k + 1)", data: .view(sv)))
            }
        }

        func threeD() {
            let c = Vec3(P(20, 20), z: ft(10))
            tx.update(m.views.first { $0.view?.kind == .threeD && $0.name == "{3D}" }!.id) {
                $0.view?.camera = Camera3D(eye: Vec3(P(62, -38), z: ft(48)), target: c, orthoHeight: ft(50))
                $0.view?.scale = 48
            }
            for (name, top, eye) in [("3D - Ground Floor Cutaway", Dim.floorToFloor - 2.0, (-24.0, -30.0)), ("3D - Upper Floor Cutaway", 2 * Dim.floorToFloor - 2.0, (64.0, -30.0))] {
                var v3 = ViewData(kind: .threeD, scale: 64)
                v3.camera = Camera3D(eye: Vec3(P(eye.0, eye.1), z: ft(52)), target: Vec3(P(20, 20), z: ft(top - 6)), orthoHeight: ft(46))
                v3.sectionBox = Box3(min: Vec3(P(-1, -1), z: ft(-2)), max: Vec3(P(Dim.lot + 1, Dim.lot + 1), z: ft(top)))
                v3.sectionBoxActive = true
                v3.phaseID = ids.phases.last
                v3.visibility.hiddenCategories = [.planting]
                cutaways.append(tx.create(.views, name: name, data: .view(v3)))
            }
        }

        /// Cover sheet project data: the program and areas.
        func projectData() -> String {
            """
            PROJECT DATA
            LOT: 40'-0" x 40'-0" = 1,600 SF, SETBACKS 5'-0" ALL SIDES
            BUILDING: 2 STOREYS, 30'-0" x 30'-0" FOOTPRINT = 900 SF (56% COVERAGE)
            GROSS FLOOR AREA: GROUND 900 SF (INCL. GARAGE 215 SF), UPPER 900 SF (INCL. BALCONIES)
            PROGRAM: 2 BEDROOMS WITH CLOSETS, LIVING, KITCHEN / DINING, FULL BATH, POWDER,
            LAUNDRY, U-STAIR, 2 RECESSED BALCONIES, 1-CAR GARAGE (10'-6" x 20'-6" CLEAR)
            HEIGHTS: 10'-0" FLOOR TO FLOOR, FLAT ROOF AT 20'-0", PARAPET TO 23'-0"
            STAIR: 18 RISERS AT 6 2/3", 11" TREADS, 3'-1" RUNS, HANDRAILS AT 36"
            CONSTRUCTION: STUCCO ON INSULATED 8" CMU, CONCRETE FLOORS AND ROOF
            """
        }

        func sheets() {
            let tb = ids.titleBlocks["ARCH D Title Block"]
            func sheet(_ number: String, _ name: String) -> ElementID {
                var sd = SheetData(number: number, paper: .archD, titleBlockTypeID: tb)
                sd.issueDate = "2026-10-19"
                sd.drawnBy = "Arcus"
                sd.designedBy = "Arcus"
                return tx.create(.sheets, name: name, data: .sheet(sd))
            }
            func place(_ view: ElementID, on s: ElementID, at c: (Double, Double), _ n: String) {
                tx.create(.viewports, data: .viewport(ViewportData(viewID: view, center: Vec2(c.0, c.1), detailNumber: n)), ownerViewID: s)
            }
            let sched = { (name: String) in self.m.schedules.first { $0.name == name }!.id }
            let three = m.views.first { $0.view?.kind == .threeD && $0.name == "{3D}" }!.id
            let s0 = sheet("A000", "Cover Sheet")
            place(three, on: s0, at: (0.27, 0.33), "1")
            place(sched("Sheet List"), on: s0, at: (0.585, 0.50), "2")
            tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(0.50, 0.36), text: projectData())), typeID: t("Text 3/32\" Arial"), ownerViewID: s0)
            let s1 = sheet("A001", "Site Plan")
            place(sitePlan, on: s1, at: (0.34, 0.31), "1")
            let s101 = sheet("A101", "Ground Floor Plan")
            place(groundPlan, on: s101, at: (0.34, 0.31), "1")
            let s102 = sheet("A102", "Upper Floor Plan")
            place(upperPlan, on: s102, at: (0.34, 0.31), "1")
            let s103 = sheet("A103", "Roof Plan")
            place(roofPlan, on: s103, at: (0.34, 0.31), "1")
            let elevs = m.views.filter { $0.view?.kind == .elevation }
            let order = ["South Elevation", "North Elevation", "East Elevation", "West Elevation"]
            let s201 = sheet("A201", "Exterior Elevations")
            for (k, name) in order.enumerated() {
                guard let v = elevs.first(where: { $0.name == name }) else { continue }
                place(v.id, on: s201, at: (0.18 + Double(k % 2) * 0.34, 0.45 - Double(k / 2) * 0.27), "\(k + 1)")
            }
            let s301 = sheet("A301", "Building Sections")
            for (k, v) in sections.enumerated() { place(v, on: s301, at: (0.36, 0.45 - Double(k) * 0.29), "\(k + 1)") }
            let s401 = sheet("A401", "Room Schedule and 3D Views")
            place(sched("Room Schedule"), on: s401, at: (0.20, 0.45), "1")
            for (k, v) in cutaways.enumerated() { place(v, on: s401, at: (0.18 + Double(k) * 0.34, 0.16), "\(k + 2)") }
            // Wider type columns so the imperial type names fit.
            for (name, width) in [("Door Schedule", 0.075), ("Window Schedule", 0.07)] {
                tx.update(sched(name)) { e in
                    guard var d = e.schedule, let i = d.fields.firstIndex(where: { $0.heading == "Type" }) else { return }
                    d.fields[i].width = width
                    e.schedule = d
                }
            }
            let s501 = sheet("A501", "Door and Window Schedules")
            place(sched("Door Schedule"), on: s501, at: (0.27, 0.45), "1")
            place(sched("Window Schedule"), on: s501, at: (0.27, 0.22), "2")
        }
    }
}
