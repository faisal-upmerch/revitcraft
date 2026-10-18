import Foundation
import ArcusGeometry
import ArcusCalc

/// Deterministic reference project: two three-storey wings around a courtyard joined by an existing link.
/// Original content; used as the sample project and the performance fixture.
public enum CourtyardHouse {
    public struct Stats: Sendable { public var elements: Int; public var rooms: Int; public var openings: Int; public var views: Int; public var sheets: Int; public var schedules: Int }

    public static func make(units: UnitsSettings = .metric) -> BIMModel {
        let tx = TransactionContext(model: BIMModel(), name: "Courtyard House")
        let ids = ProjectTemplates.populate(tx, kind: .architectural, units: units, projectName: "Courtyard House")
        let log = GUIDLog()
        Builder(tx: tx, ids: ids, log: log).build()
        // Reproducible fixture: elements created without a named GUID (template content, annotations, furniture)
        // get one derived from their (deterministic) element id.
        for e in tx.model.allElements where !log.named.contains(e.ifcGUID) {
            tx.update(e.id) { $0.ifcGUID = .deterministic("courtyard/element/\(e.id.raw)") }
        }
        do {
            return try tx.commit().model
        } catch {
            preconditionFailure("Courtyard House failed validation: \(error)")
        }
    }

    public static func stats(_ m: BIMModel) -> Stats {
        Stats(elements: m.count, rooms: m.elements(.rooms).count, openings: m.elements(.doors).count + m.elements(.windows).count,
              views: m.views.count, sheets: m.sheets.count, schedules: m.schedules.count)
    }

    /// Stress fixture: `count` simple elements (walls, columns and floors on a grid) for engine benchmarks.
    public static func stress(count: Int = 20_000) -> BIMModel {
        let (base, ids) = ProjectTemplates.make(.empty, units: .metric, projectName: "Stress")
        let tx = TransactionContext(model: base, name: "Stress")
        let level = ids.levels[0]
        let wall = ids.wallTypes["Generic - 200mm"]
        let col = ids.systemTypes["Concrete Column 400 x 400"]
        let side = Int(Double(count).squareRoot().rounded(.up))
        var n = 0
        outer: for i in 0..<side {
            for j in 0..<side {
                if n >= count { break outer }
                let o = Vec2(Double(i) * 3, Double(j) * 3)
                if n % 2 == 0 {
                    tx.create(.walls, data: .wall(WallData(location: .line(Segment2(o, o + Vec2(2.4, 0))), unconnectedHeight: 3)), typeID: wall, levelID: level)
                } else {
                    tx.create(.columns, data: .column(ColumnData(location: o + Vec2(1.2, 1.5))), typeID: col, levelID: level)
                }
                n += 1
            }
        }
        return (try? tx.commit().model) ?? base
    }

    final class GUIDLog { var named = Set<IFCGUID>() }

    struct Builder {
        let tx: TransactionContext
        let ids: ProjectTemplates.Ids
        var log = GUIDLog()
        var m: BIMModel { tx.model }

        func guid(_ s: String) -> IFCGUID {
            let g = IFCGUID.deterministic("courtyard/" + s)
            log.named.insert(g)
            return g
        }

        func build() {
            var levels = ids.levels
            // Template has Level 1, Level 2, Roof. Rename and add a third storey.
            tx.update(levels[0]) { $0.name = "Ground Floor"; $0.ifcGUID = guid("level0") }
            tx.update(levels[1]) { $0.name = "First Floor"; $0.level?.elevation = 3.6; $0.ifcGUID = guid("level1") }
            tx.update(levels[2]) { $0.name = "Roof"; $0.level?.elevation = 10.8; $0.ifcGUID = guid("level3") }
            let second = tx.create(.levels, name: "Second Floor", data: .level(LevelData(elevation: 7.2)), ifcGUID: guid("level2"))
            levels.insert(second, at: 2)
            let phaseExisting = ids.phases[0], phaseNew = ids.phases[1]
            // Rename template views to follow their levels.
            for v in m.views where v.levelID != nil {
                if let lname = m[v.levelID]?.name { tx.update(v.id) { $0.name = lname } }
            }
            var fp = ViewData(kind: .floorPlan, scale: 100); fp.phaseID = phaseNew
            let planSecond = tx.create(.views, name: "Second Floor", data: .view(fp), levelID: second)
            var rcp = ViewData(kind: .ceilingPlan, scale: 100); rcp.phaseID = phaseNew
            tx.create(.views, name: "Second Floor", data: .view(rcp), levelID: second)
            // Remove the template's placeholder sheet; the project defines its own set.
            for s in m.sheets { tx.delete(s.id) }

            let extWall = ids.wallTypes["Exterior - Brick on CMU"]!
            let corrWall = ids.wallTypes["Interior - 150mm Masonry"]!
            let partition = ids.wallTypes["Interior - 100mm Partition"]!
            let floorType = ids.floorTypes["Screed on Concrete 250mm"]!
            let ceilingType = ids.ceilingTypes["Acoustic Tile 600 x 600"]!
            let roofType = ids.roofTypes["Tiled Roof - Timber"]!
            let door = ids.familyTypes["Door - Single Flush: 900 x 2100"]!
            let doubleDoor = ids.familyTypes["Door - Double Flush: 1800 x 2100"]!
            let window = ids.familyTypes["Window - Casement: 1200 x 1500"]!
            let glazed = ids.familyTypes["Window - Casement: 2400 x 2100 Glazed Wall"]!
            let desk = ids.familyTypes["Desk: 1500 x 750"]!
            let chair = ids.familyTypes["Chair: Task Chair"]!
            let cabinet = ids.familyTypes["Base Cabinet: 900"]!
            let doorTag = ids.familyTypes["Door Tag: Standard"]!
            let windowTag = ids.familyTypes["Window Tag: Standard"]!
            let roomTag = ids.familyTypes["Room Tag: Name and Number"]!
            let column = ids.systemTypes["Concrete Column 400 x 400"]!
            let beam = ids.systemTypes["Steel Beam 200 x 400"]!

            let storeys = [levels[0], levels[1], levels[2]]
            let planViews: [ElementID] = storeys.map { l in m.views.first { $0.levelID == l && $0.view?.kind == .floorPlan }?.id ?? planSecond }
            let departments = ["Studio", "Office", "Meeting", "Workshop", "Archive", "Library"]

            // Wing definitions: origin, length along axis, depth 14 m, axis direction.
            struct Wing { var name: String; var origin: Vec2; var length: Double; var alongX: Bool }
            let wings = [Wing(name: "A", origin: Vec2(0, 0), length: 48, alongX: true), Wing(name: "B", origin: Vec2(0, 20), length: 34, alongX: false)]
            let depth = 14.0
            func pt(_ w: Wing, _ s: Double, _ t: Double) -> Vec2 { w.alongX ? w.origin + Vec2(s, t) : w.origin + Vec2(t, s) }

            var roomCounter = 0
            for (li, level) in storeys.enumerated() {
                let above = li + 1 < levels.count ? levels[li + 1] : nil
                let view = planViews[li]
                for w in wings {
                    let key = "\(w.name)\(li)"
                    // Exterior walls, drawn clockwise so the exterior face is outward.
                    let c = [pt(w, 0, 0), pt(w, 0, depth), pt(w, w.length, depth), pt(w, w.length, 0)]
                    let corners = Polygon2(c).clockwise.points
                    var ext: [ElementID] = []
                    for k in 0..<4 {
                        var wd = WallData(location: .line(Segment2(corners[k], corners[(k + 1) % 4])), topLevelID: above)
                        wd.structural = true
                        ext.append(tx.create(.walls, data: .wall(wd), typeID: extWall, levelID: level, ifcGUID: guid("\(key)/ext\(k)")) { $0.phaseCreated = phaseNew })
                    }
                    // Corridor walls at t = 6 and t = 8.
                    var corridor: [ElementID] = []
                    for (k, t) in [6.0, 8.0].enumerated() {
                        corridor.append(tx.create(.walls, data: .wall(WallData(location: .line(Segment2(pt(w, 0, t), pt(w, w.length, t))), topLevelID: above)),
                                                  typeID: corrWall, levelID: level, ifcGUID: guid("\(key)/corr\(k)")) { $0.phaseCreated = phaseNew })
                    }
                    // Partitions every 4 m on both sides, leaving a stair bay at the far end of wing A.
                    let bays = Int(w.length / 4)
                    for b in 1..<bays {
                        let s = Double(b) * 4
                        for (side, range) in [(0, (0.0, 6.0)), (1, (8.0, depth))] {
                            tx.create(.walls, data: .wall(WallData(location: .line(Segment2(pt(w, s, range.0), pt(w, s, range.1))), topLevelID: above)),
                                      typeID: partition, levelID: level, ifcGUID: guid("\(key)/p\(b)-\(side)")) { $0.phaseCreated = phaseNew }
                        }
                    }
                    // Steel beams over the corridor on every partition line, carrying the floor above.
                    for b in 1..<bays {
                        let s = Double(b) * 4
                        tx.create(.structuralFraming, data: .beam(BeamData(curve: .line(Segment2(pt(w, s, 6), pt(w, s, 8))), startOffset: 3.35, endOffset: 3.35)),
                                  typeID: beam, levelID: level, ifcGUID: guid("\(key)/beam\(b)")) { $0.phaseCreated = phaseNew }
                    }
                    // Rooms, doors, windows, furniture, ceilings.
                    for b in 0..<bays {
                        let s0 = Double(b) * 4, sm = s0 + 2
                        for side in 0..<2 {
                            let isStair = w.name == "A" && b == bays - 1 && side == 1
                            let tMid = side == 0 ? 3.0 : 11.0
                            roomCounter += 1
                            let number = "\(li + 1)\(w.name)\(String(format: "%02d", b * 2 + side + 1))"
                            let name = isStair ? "Stair" : (b == 0 && side == 0 ? "Lobby" : (b % 5 == 4 ? "Toilets" : departments[(b + side + li) % departments.count]))
                            let roomID = tx.create(.rooms, name: name, data: .room(RoomData(point: pt(w, sm, tMid), number: number)), levelID: level, ifcGUID: guid("\(key)/room\(b)-\(side)")) {
                                $0.params[ParameterID("room.department")] = .text(isStair ? "Circulation" : departments[(b + li) % departments.count])
                                $0.params[ParameterID("room.floorFinish")] = .text(name == "Toilets" ? "Ceramic Tile" : "Oak Flooring")
                                $0.phaseCreated = phaseNew
                            }
                            tx.create(.tags, data: .tag(TagData(taggedID: roomID, head: pt(w, sm, tMid))), typeID: roomTag, ownerViewID: view)
                            // Door onto the corridor.
                            if !isStair {
                                let host = corridor[side]
                                let dID = tx.create(.doors, data: .insert(InsertData(location: pt(w, s0 + 1.2, side == 0 ? 6 : 8))), typeID: door, levelID: level, hostID: host,
                                                    ifcGUID: guid("\(key)/door\(b)-\(side)")) { e in
                                    e.mark = number
                                    e.phaseCreated = phaseNew
                                    if side == 0 { e.insert?.facingFlipped = true }
                                }
                                tx.create(.tags, data: .tag(TagData(taggedID: dID, head: pt(w, s0 + 1.2, side == 0 ? 5.2 : 8.8))), typeID: doorTag, ownerViewID: view)
                            }
                            // Window on the exterior wall.
                            let extHost: ElementID = w.alongX ? (side == 0 ? ext[3] : ext[1]) : (side == 0 ? ext[0] : ext[2])
                            let hostSeg = m[extHost]?.wall?.location.asSegment
                            if let hs = hostSeg {
                                let target = pt(w, sm, side == 0 ? 0 : depth)
                                let loc = hs.closestPoint(to: target)
                                let wtype = (b == 0 && side == 0 && li == 0) ? glazed : window
                                let sill = wtype == glazed ? 0.3 : 0.9
                                let wid = tx.create(.windows, data: .insert(InsertData(location: loc, sillHeight: sill)), typeID: wtype, levelID: level, hostID: extHost,
                                                    ifcGUID: guid("\(key)/win\(b)-\(side)")) { $0.phaseCreated = phaseNew }
                                tx.create(.tags, data: .tag(TagData(taggedID: wid, head: loc + (target - pt(w, sm, tMid)).normalized * 1.4)), typeID: windowTag, ownerViewID: view)
                            }
                            guard !isStair else { continue }
                            // Furniture.
                            let facing: Double = w.alongX ? (side == 0 ? 0 : .pi) : (side == 0 ? -.pi / 2 : .pi / 2)
                            if name == "Toilets" {
                                // Three WCs along the partition and two basins by the door.
                                for (k, off) in [3.3, 2.4, 1.5].enumerated() {
                                    tx.create(.plumbingFixtures, data: .component(ComponentData(location: pt(w, s0 + off, side == 0 ? 1.0 : 13.0), rotation: facing)),
                                              typeID: ids.familyTypes["WC Pan: Standard"]!, levelID: level) { $0.mark = "\(number)-WC\(k + 1)" }
                                }
                                for off in [0.8, 1.6] {
                                    tx.create(.plumbingFixtures, data: .component(ComponentData(location: pt(w, s0 + off, side == 0 ? 4.8 : 9.2), rotation: facing + .pi)),
                                              typeID: ids.familyTypes["Basin: Vanity 600"]!, levelID: level)
                                }
                            } else if name == "Meeting" {
                                // Table (two desks back to back) with six chairs.
                                for dt in [-0.4, 0.4] {
                                    tx.create(.furniture, data: .component(ComponentData(location: pt(w, sm, (side == 0 ? 3.0 : 11.0) + dt), rotation: w.alongX ? 0 : .pi / 2)),
                                              typeID: desk, levelID: level) { $0.phaseCreated = phaseNew }
                                }
                                for ds in [-0.5, 0.5] {
                                    for (dt, turn) in [(-1.3, 0.0), (1.3, Double.pi)] {
                                        let c = pt(w, sm + ds, (side == 0 ? 3.0 : 11.0) + dt)
                                        tx.create(.furniture, data: .component(ComponentData(location: c, rotation: (w.alongX ? 0 : .pi / 2) + turn)), typeID: chair, levelID: level)
                                    }
                                }
                                for (ds, turn) in [(-1.3, Double.pi / 2), (1.3, -Double.pi / 2)] {
                                    tx.create(.furniture, data: .component(ComponentData(location: pt(w, sm + ds, side == 0 ? 3.0 : 11.0), rotation: (w.alongX ? 0 : .pi / 2) + turn)),
                                              typeID: chair, levelID: level)
                                }
                            } else if name == "Lobby" {
                                // Reception desk with a task chair and a row of four waiting chairs.
                                tx.create(.furniture, data: .component(ComponentData(location: pt(w, sm, side == 0 ? 4.2 : 9.8), rotation: facing + .pi)),
                                          typeID: desk, levelID: level) { $0.phaseCreated = phaseNew; $0.mark = "\(number)-REC" }
                                tx.create(.furniture, data: .component(ComponentData(location: pt(w, sm, side == 0 ? 5.1 : 8.9), rotation: facing)), typeID: chair, levelID: level)
                                for k in 0..<4 {
                                    tx.create(.furniture, data: .component(ComponentData(location: pt(w, s0 + 0.8 + Double(k) * 0.8, side == 0 ? 1.0 : 13.0), rotation: facing + .pi)),
                                              typeID: chair, levelID: level)
                                }
                            } else if name != "Lobby" {
                                let deskAt = pt(w, sm, side == 0 ? 2.0 : 12.0)
                                tx.create(.furniture, data: .component(ComponentData(location: deskAt, rotation: facing)), typeID: desk, levelID: level) { $0.phaseCreated = phaseNew }
                                let chairAt = pt(w, sm, side == 0 ? 3.0 : 11.0)
                                tx.create(.furniture, data: .component(ComponentData(location: chairAt, rotation: facing + .pi)), typeID: chair, levelID: level)
                                tx.create(.casework, data: .component(ComponentData(location: pt(w, s0 + 0.6, side == 0 ? 4.4 : 9.6), rotation: w.alongX ? .pi / 2 : 0)),
                                          typeID: cabinet, levelID: level)
                                // Visitor chair across the desk.
                                tx.create(.furniture, data: .component(ComponentData(location: pt(w, sm + 0.9, side == 0 ? 1.1 : 12.9), rotation: facing)), typeID: chair, levelID: level)
                                if name == "Archive" || name == "Library" {
                                    for dt in [3.4, 2.4] {
                                        tx.create(.casework, data: .component(ComponentData(location: pt(w, s0 + 0.6, side == 0 ? dt : depth - dt), rotation: w.alongX ? .pi / 2 : 0)),
                                                  typeID: cabinet, levelID: level)
                                    }
                                }
                            }
                            // Ceiling for the room bay (interior faces approximated by the partition grid).
                            let r = Rect2(points: [pt(w, s0 + 0.1, side == 0 ? 0.25 : 8.1), pt(w, s0 + 3.95, side == 0 ? 5.9 : depth - 0.25)])
                            var cd = SlabData(boundary: Sketch(rect: r), offset: 2.7)
                            cd.roomBounding = false
                            tx.create(.ceilings, data: .slab(cd), typeID: ceilingType, levelID: level)
                        }
                    }
                    // Floor slab for the wing.
                    var fd = SlabData(boundary: Sketch(rect: Rect2(points: [pt(w, -0.19, -0.19), pt(w, w.length + 0.19, depth + 0.19)])))
                    fd.structural = true
                    tx.create(.floors, data: .slab(fd), typeID: floorType, levelID: level, ifcGUID: guid("\(key)/floor"))
                    // Overall dimension along the wing.
                    let dimY = w.alongX ? -4.0 : -4.0
                    let refs = [GeometryReference(ext[0], .exteriorFace), GeometryReference(ext[2], .exteriorFace)]
                    tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: refs, linePoint: pt(w, w.length / 2, dimY))),
                              typeID: ids.systemTypes["Dimension"], ownerViewID: view)
                }
            }

            // Existing single-storey link between wings (phase: Existing), with a demolished infill wall.
            let link = [Vec2(4, 14), Vec2(4, 20), Vec2(10, 20), Vec2(10, 14)]
            for k in [0, 2] {
                var wd = WallData(location: .line(Segment2(link[k], link[k + 1])), topLevelID: levels[1])
                wd.roomBounding = true
                tx.create(.walls, data: .wall(wd), typeID: extWall, levelID: levels[0], ifcGUID: guid("link/wall\(k)")) { $0.phaseCreated = phaseExisting }
            }
            let demo = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(4, 17), Vec2(10, 17))), topLevelID: levels[1])),
                                 typeID: partition, levelID: levels[0], ifcGUID: guid("link/demo")) {
                $0.phaseCreated = phaseExisting; $0.phaseDemolished = phaseNew
            }
            _ = demo
            var linkFloor = SlabData(boundary: Sketch(rect: Rect2(min: Vec2(4, 14), max: Vec2(10, 20))))
            linkFloor.structural = true
            tx.create(.floors, data: .slab(linkFloor), typeID: floorType, levelID: levels[0], ifcGUID: guid("link/floor")) { $0.phaseCreated = phaseExisting }
            // Link structure: columns and beams.
            for (k, p) in [Vec2(5, 15), Vec2(9, 15), Vec2(5, 19), Vec2(9, 19)].enumerated() {
                tx.create(.columns, data: .column(ColumnData(location: p, topLevelID: levels[1])), typeID: column, levelID: levels[0], ifcGUID: guid("link/col\(k)"))
            }
            for (a, b) in [(Vec2(5, 15), Vec2(9, 15)), (Vec2(5, 19), Vec2(9, 19))] {
                tx.create(.structuralFraming, data: .beam(BeamData(curve: .line(Segment2(a, b)), startOffset: 3.6, endOffset: 3.6)), typeID: beam, levelID: levels[0])
            }
            // Entrance doors on wing A south wall.
            if let south = m.elements(.walls).first(where: { $0.levelID == levels[0] && $0.typeID == extWall && abs(($0.wall?.location.midpoint.y ?? 1)) < 1e-6 }) {
                tx.create(.doors, data: .insert(InsertData(location: Vec2(24, 0))), typeID: doubleDoor, levelID: levels[0], hostID: south.id, ifcGUID: guid("entrance")) {
                    $0.mark = "E01"; $0.insert?.facingFlipped = true
                }
            }

            // Stairs with railings in wing A (stair bay) and wing B.
            let stairType = ids.systemTypes["Stair"]!
            let railType = ids.systemTypes["Railing"]!
            for (k, (o, dir)) in [(Vec2(44.75, 9.0), Double.pi / 2), (Vec2(9.0, 20.2), Double.pi / 2)].enumerated() {
                for li in 0..<2 {
                    var sd = StairData(shape: .uShaped, origin: o, direction: dir, width: 1.2, topLevelID: levels[li + 1])
                    sd.turnsLeft = false
                    let sid = tx.create(.stairs, data: .stair(sd), typeID: stairType, levelID: levels[li], ifcGUID: guid("stair\(k)/\(li)"))
                    for left in [true, false] {
                        var rd = RailingData(path: [])
                        rd.followsHost = true; rd.hostSideLeft = left
                        tx.create(.railings, data: .railing(rd), typeID: railType, levelID: levels[li], hostID: sid)
                    }
                }
            }

            // Roofs over each wing on the Roof level (hip roofs) with walls attached.
            for w in wings {
                let r = Rect2(points: [pt(w, -0.6, -0.6), pt(w, w.length + 0.6, depth + 0.6)])
                let sketch = Sketch(rect: r)
                let rid = tx.create(.roofs, data: .roof(RoofData(footprint: sketch, edgeSlopes: [atan(0.45), atan(0.45), atan(0.45), atan(0.45)], overhang: 0.6)),
                                    typeID: roofType, levelID: levels[3], ifcGUID: guid("roof\(w.name)")) {
                    $0.roof?.fascia = true
                }
                _ = rid
            }

            // Grids.
            for i in 0...12 {
                tx.create(.grids, name: "\(i + 1)", data: .grid(GridData(curve: .line(Segment2(Vec2(Double(i) * 4, -3), Vec2(Double(i) * 4, 17))))))
            }
            for (i, y) in [0.0, 6.0, 8.0, 14.0].enumerated() {
                tx.create(.grids, name: String(["A", "B", "C", "D"][i]), data: .grid(GridData(curve: .line(Segment2(Vec2(-3, y), Vec2(51, y))))))
            }
            for (i, x) in [0.0, 6.0, 8.0].enumerated() {
                tx.create(.grids, name: "B\(i + 1)", data: .grid(GridData(curve: .line(Segment2(Vec2(x, 18), Vec2(x, 57))))))
            }

            // Site: property lines, toposurface, building pad under the link.
            let site = [Vec2(-12, -12), Vec2(62, -12), Vec2(62, 64), Vec2(-12, 64)]
            for k in 0..<4 {
                tx.create(.propertyLines, data: .modelLine(ModelLineData(curve: .line(Segment2(site[k], site[(k + 1) % 4])))), levelID: levels[0])
            }
            var topo: [Vec3] = []
            for i in 0...6 { for j in 0...6 {
                let x = -12 + Double(i) * 74 / 6, y = -12 + Double(j) * 76 / 6
                topo.append(Vec3(x, y, -0.3 - 0.8 * sin(Double(i) * 0.7) * cos(Double(j) * 0.5)))
            } }
            tx.create(.topography, name: "Existing Ground", data: .topography(TopographyData(points: topo))) { $0.phaseCreated = phaseExisting }

            // Additional views: structural plans, presentation plans, roof & site plans, sections, callouts, 3D.
            var planViewIDs: [ElementID] = planViews
            for (li, l) in storeys.enumerated() {
                var sp = ViewData(kind: .structuralPlan, scale: 100); sp.discipline = .structural; sp.phaseID = phaseNew
                tx.create(.views, name: "\(m[l]!.name) - Structure", data: .view(sp), levelID: l)
                var pp = ViewData(kind: .floorPlan, scale: 200); pp.detailLevel = .coarse; pp.phaseID = phaseNew
                pp.templateID = m.elements(.viewTemplates).first { $0.name == "Presentation Plan" }?.id
                planViewIDs.append(tx.create(.views, name: "\(m[l]!.name) - Presentation", data: .view(pp), levelID: l))
                _ = li
            }
            var roofPlan = ViewData(kind: .floorPlan, scale: 200)
            roofPlan.viewRange = ViewRange(topOffset: 6, cutOffset: 5, bottomOffset: -4, depthOffset: -4)
            roofPlan.phaseID = phaseNew
            let roofPlanID = tx.create(.views, name: "Roof Plan", data: .view(roofPlan), levelID: levels[3])
            var sitePlan = ViewData(kind: .floorPlan, scale: 500)
            sitePlan.viewRange = ViewRange(topOffset: 15, cutOffset: 14, bottomOffset: -2, depthOffset: -2)
            sitePlan.phaseID = phaseNew
            sitePlan.phaseFilter = .showAll
            let sitePlanID = tx.create(.views, name: "Site Plan", data: .view(sitePlan), levelID: levels[0])
            // Existing-phase plan.
            var existing = ViewData(kind: .floorPlan, scale: 100); existing.phaseID = phaseExisting
            tx.create(.views, name: "Ground Floor - Existing", data: .view(existing), levelID: levels[0])
            // Callouts of the stair bays.
            var calloutIDs: [ElementID] = []
            for (k, (l, r)) in [(levels[0], Rect2(min: Vec2(42.5, 7.5), max: Vec2(48.5, 14.5))), (levels[1], Rect2(min: Vec2(42.5, 7.5), max: Vec2(48.5, 14.5))),
                                  (levels[0], Rect2(min: Vec2(6.5, 20.5), max: Vec2(14.5, 27.0))), (levels[1], Rect2(min: Vec2(6.5, 20.5), max: Vec2(14.5, 27.0)))].enumerated() {
                var cv = ViewData(kind: .floorPlan, scale: 50)
                cv.cropRegion = r; cv.cropActive = true; cv.cropVisible = false
                cv.parentViewID = planViews[l == levels[0] ? 0 : 1]
                cv.phaseID = phaseNew
                cv.detailLevel = .fine
                calloutIDs.append(tx.create(.views, name: "Stair \(k < 2 ? "A" : "B") - \(m[l]!.name)", data: .view(cv), levelID: l))
            }
            // Sections.
            var sectionIDs: [ElementID] = []
            for (k, (a, b)) in [(Vec2(-3, 7), Vec2(51, 7)), (Vec2(22, -3), Vec2(22, 17)), (Vec2(7, 17), Vec2(7, 57)), (Vec2(-3, 42), Vec2(17, 42))].enumerated() {
                var sv = ViewData(kind: .section, scale: 100)
                let dir = (b - a).normalized
                sv.viewDirection = dir.perpendicular
                sv.planeOrigin = Vec3(a, z: 0)
                sv.cropRegion = Rect2(min: Vec2(0, -1.5), max: Vec2(a.distance(to: b), 16))
                sv.cropActive = true
                sv.farClip = 12
                sv.phaseID = phaseNew
                sectionIDs.append(tx.create(.views, name: "Section \(k + 1)", data: .view(sv)))
            }
            // Elevations: place template elevations around the building with crops.
            let elevs = m.views.filter { $0.view?.kind == .elevation }
            for e in elevs {
                tx.update(e.id) { v in
                    guard var vd = v.view, let d = vd.viewDirection else { return }
                    let center = Vec2(24, 28)
                    let o = center - d * 45
                    vd.planeOrigin = Vec3(o, z: 0)
                    vd.markerPosition = center - d * 40
                    vd.farClip = 90
                    vd.phaseID = phaseNew
                    // u runs along the view's right vector from the plane origin.
                    vd.cropRegion = Rect2(min: Vec2(-32, -2), max: Vec2(32, 16))
                    vd.cropActive = true
                    v.view = vd
                }
            }
            // A second 3D view with a section box.
            var v3 = ViewData(kind: .threeD, scale: 100)
            v3.camera = Camera3D(eye: Vec3(70, -40, 45), target: Vec3(20, 20, 4))
            v3.sectionBox = Box3(min: Vec3(-2, -2, -1), max: Vec3(50, 16, 6))
            v3.sectionBoxActive = true
            v3.phaseID = phaseNew
            let axon = tx.create(.views, name: "Wing A - Cutaway", data: .view(v3))
            tx.update(m.views.first { $0.view?.kind == .threeD && $0.name == "{3D}" }!.id) {
                $0.view?.camera = Camera3D(eye: Vec3(-35, -45, 40), target: Vec3(22, 24, 4))
            }

            // Annotations: notes, spots, revision clouds.
            let rev1 = m.revisions.first!.id
            tx.update(rev1) { $0.revisionData?.issued = true; $0.revisionData?.date = "2026-06-01"; $0.revisionData?.description = "Planning submission" }
            let rev2 = tx.create(.revisions, name: "Revision 2", data: .revision(RevisionData(sequence: 2, date: "2026-09-15", description: "Stair B redesign")))
            tx.create(.revisionClouds, data: .revisionCloud(RevisionCloudData(outline: Polygon2.rectangle(Rect2(min: Vec2(5.5, 20), max: Vec2(15.5, 28))), revisionID: rev2)),
                      ownerViewID: planViews[0])
            tx.create(.textNotes, data: .textNote(TextNoteData(position: Vec2(18, -7), text: "ALL DIMENSIONS IN MILLIMETRES.\nDO NOT SCALE FROM DRAWINGS.")),
                      typeID: ids.systemTypes["Text 2.5mm Arial"], ownerViewID: planViews[0])
            tx.create(.spotElevations, data: .spot(SpotData(kind: .elevation, point: Vec2(24, 3), elevation: 0, leaderHead: Vec2(26, 4.5))), ownerViewID: planViews[0])
            tx.create(.genericAnnotations, data: .detailComponent(DetailComponentData(location: Vec2(56, 56))), typeID: ids.familyTypes["North Arrow: Standard"], ownerViewID: sitePlanID)

            // Additional schedules (defaults exist from the template: door, window, room, wall quantities, sheet list).
            var floors = ScheduleDefinition(kind: .category, categories: [.floors], fields: [
                ScheduleTemplates.field("familyAndType", "Type", width: 0.05), ScheduleTemplates.field("level", "Level", width: 0.03),
                ScheduleTemplates.field("q.area", "Area", width: 0.025, total: .total, align: .right), ScheduleTemplates.field("q.volume", "Volume", width: 0.025, total: .total, align: .right),
            ])
            floors.grandTotals = true
            tx.create(.schedules, name: "Floor Schedule", data: .schedule(floors))
            var furniture = ScheduleDefinition(kind: .category, categories: [.furniture, .casework], fields: [
                ScheduleTemplates.field("familyAndType", "Type", width: 0.05), ScheduleTemplates.field("level", "Level", width: 0.03),
                ScheduleField(source: .count, heading: "Count", width: 0.015, alignment: .right),
            ])
            furniture.kind = .multiCategory
            furniture.sorting = [ScheduleSort(fieldID: furniture.fields[0].id), ScheduleSort(fieldID: furniture.fields[1].id)]
            furniture.itemizeEveryInstance = false
            furniture.grandTotals = true
            tx.create(.schedules, name: "Furniture Schedule", data: .schedule(furniture))
            var takeoff = ScheduleDefinition(kind: .materialTakeoff, categories: [.walls], fields: [
                ScheduleField(source: .material("Name"), heading: "Material", width: 0.05),
                ScheduleField(source: .material("Area"), heading: "Area", width: 0.025, alignment: .right),
                ScheduleField(source: .material("Volume"), heading: "Volume", width: 0.025, alignment: .right),
            ])
            takeoff.fields[1].total = .total; takeoff.fields[2].total = .total
            takeoff.sorting = [ScheduleSort(fieldID: takeoff.fields[0].id)]
            takeoff.itemizeEveryInstance = false
            takeoff.grandTotals = true
            tx.create(.schedules, name: "Wall Material Takeoff", data: .schedule(takeoff))
            let revSchedule = ScheduleDefinition(kind: .revisionSchedule, categories: [.revisions], fields: [
                ScheduleTemplates.field("revision.number", "Rev", width: 0.012), ScheduleTemplates.field("revision.date", "Date", width: 0.025),
                ScheduleTemplates.field("revision.description", "Description", width: 0.07), ScheduleTemplates.field("revision.issued", "Issued", width: 0.015),
            ])
            tx.create(.schedules, name: "Revision Schedule", data: .schedule(revSchedule))
            var dept = ScheduleDefinition(kind: .category, categories: [.rooms], fields: [
                ScheduleTemplates.field("room.department", "Department", width: 0.04), ScheduleField(source: .count, heading: "Rooms", width: 0.015, alignment: .right),
                ScheduleTemplates.field("q.area", "Area", width: 0.025, total: .total, align: .right),
            ])
            dept.fields.append(ScheduleField(source: .percentage(of: dept.fields[2].id, byGroup: false), heading: "Share", width: 0.02, alignment: .right))
            dept.sorting = [ScheduleSort(fieldID: dept.fields[0].id)]
            dept.itemizeEveryInstance = false
            dept.grandTotals = true
            tx.create(.schedules, name: "Area by Department", data: .schedule(dept))

            // Views placed on A1 sheets: crop to the building and grids, and draw at 1:200 so they fit the sheet.
            let buildingCrop = Rect2(min: Vec2(-6, -8), max: Vec2(54, 60))
            let sheetPlans = planViews + [roofPlanID] + m.views.filter { $0.view?.kind == .ceilingPlan }.map(\.id)
            for id in sheetPlans {
                tx.update(id) { $0.view?.scale = 200; $0.view?.cropRegion = buildingCrop; $0.view?.cropActive = true; $0.view?.cropVisible = true }
            }
            for v in m.views where v.view?.kind == .elevation {
                tx.update(v.id) { $0.view?.scale = 200; $0.view?.cropRegion = Rect2(min: Vec2(-30, -2), max: Vec2(30, 16)) }
            }
            for id in sectionIDs { tx.update(id) { $0.view?.scale = 200 } }

            // Sheets.
            let tb = ids.titleBlocks["A1 Title Block"]
            func sheet(_ number: String, _ name: String) -> ElementID {
                var sd = SheetData(number: number, paper: .a1, titleBlockTypeID: tb)
                sd.issueDate = "2026-09-15"
                sd.additionalRevisionIDs = [rev1]
                return tx.create(.sheets, name: name, data: .sheet(sd))
            }
            func place(_ view: ElementID, on s: ElementID, at c: Vec2, _ n: String) {
                tx.create(.viewports, data: .viewport(ViewportData(viewID: view, center: c, detailNumber: n)), ownerViewID: s)
            }
            let sched = { (name: String) in m.schedules.first { $0.name == name }!.id }
            let cover = sheet("A000", "Cover Sheet and Drawing List")
            place(sched("Sheet List"), on: cover, at: Vec2(0.25, 0.4), "1")
            place(axon, on: cover, at: Vec2(0.5, 0.3), "2")
            let siteSheet = sheet("A001", "Site Plan")
            place(sitePlanID, on: siteSheet, at: Vec2(0.33, 0.3), "1")
            for (k, name) in ["Ground Floor Plan", "First Floor Plan", "Second Floor Plan"].enumerated() {
                let s = sheet("A10\(k + 1)", name)
                place(planViews[k], on: s, at: Vec2(0.33, 0.3), "1")
            }
            let roofSheet = sheet("A104", "Roof Plan")
            place(roofPlanID, on: roofSheet, at: Vec2(0.33, 0.3), "1")
            let rcps = m.views.filter { $0.view?.kind == .ceilingPlan }.sorted { m.elevation(ofLevel: $0.levelID) < m.elevation(ofLevel: $1.levelID) }
            for (k, v) in rcps.prefix(3).enumerated() {
                let s = sheet("A11\(k + 1)", "\(v.name) Reflected Ceiling Plan")
                place(v.id, on: s, at: Vec2(0.33, 0.3), "1")
            }
            let elevViews = m.views.filter { $0.view?.kind == .elevation }.sorted { $0.name < $1.name }
            for k in 0..<2 {
                let s = sheet("A20\(k + 1)", "Elevations \(k + 1)")
                for (j, v) in elevViews.dropFirst(k * 2).prefix(2).enumerated() { place(v.id, on: s, at: Vec2(0.33, 0.43 - Double(j) * 0.25), "\(j + 1)") }
            }
            for k in 0..<2 {
                let s = sheet("A30\(k + 1)", "Sections \(k + 1)")
                for (j, v) in sectionIDs.dropFirst(k * 2).prefix(2).enumerated() { place(v, on: s, at: Vec2(0.33, 0.43 - Double(j) * 0.25), "\(j + 1)") }
            }
            let stairSheet = sheet("A401", "Enlarged Stair Plans")
            for (j, v) in calloutIDs.enumerated() { place(v, on: stairSheet, at: Vec2(0.12 + Double(j % 2) * 0.25, 0.42 - Double(j / 2) * 0.22), "\(j + 1)") }
            let s501 = sheet("A501", "Door and Window Schedules")
            place(sched("Door Schedule"), on: s501, at: Vec2(0.2, 0.35), "1")
            place(sched("Window Schedule"), on: s501, at: Vec2(0.47, 0.45), "2")
            let s502 = sheet("A502", "Room Schedules")
            place(sched("Room Schedule"), on: s502, at: Vec2(0.2, 0.3), "1")
            place(sched("Area by Department"), on: s502, at: Vec2(0.47, 0.45), "2")
            _ = planViewIDs
        }
    }
}
