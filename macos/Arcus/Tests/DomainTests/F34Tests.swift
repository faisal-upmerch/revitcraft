import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// F34: Structure (truss, brace, beam system, structural settings) and Reinforcement (rebar, area, path, fabric,
/// cover, couplers), their symbols and Multi-Rebar annotations.
@Suite("F34 structure and reinforcement")
struct F34Tests {
    /// A template with a 3 × 2 m (or `w` × `h`) 200 mm slab on Level 1 and the bar types.
    static func slab(w: Double = 3, h: Double = 2) throws -> (BIMModel, ProjectTemplates.Ids, ElementID) {
        var (m, ids) = Fx.template()
        var floor = ElementID(0)
        try Fx.commit(&m) { tx in
            let s = SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(w, h))))
            floor = tx.create(.floors, data: .slab(s), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            Reinforcement.ensureBarTypes(in: tx)
        }
        return (m, ids, floor)
    }

    static func barType(_ m: BIMModel, _ name: String) -> ElementID? { Reinforcement.barTypes(m).first { $0.name == name }?.id }

    // MARK: Reinforcement geometry

    @Test func barTypesAndCoverFollowTheUnits() throws {
        let (m, _, _) = try Self.slab()
        #expect(Reinforcement.barTypes(m).map(\.name) == ["10M", "15M", "20M", "25M"])
        #expect(Reinforcement.barName(m, Reinforcement.defaultBarType(m)) == "15M")
        #expect(Fx.approx(Reinforcement.cover(m), 0.040))
        var (im, _) = Fx.template(units: .imperial)
        try Fx.commit(&im) { tx in Reinforcement.ensureBarTypes(in: tx) }
        #expect(Reinforcement.barTypes(im).map(\.name) == ["#3", "#4", "#5", "#6"])
        #expect(Fx.approx(Reinforcement.cover(im), 0.0381))
    }

    @Test func areaReinforcementBarsSitInsideTheCoverInFourLayers() throws {
        var (m, _, floor) = try Self.slab()
        let bt = Self.barType(m, "15M")
        var id = ElementID(0)
        try Fx.commit(&m) { tx in
            let layer = RebarLayer(barTypeID: bt, spacing: 0.3)
            id = tx.create(.areaReinforcement, data: .areaReinforcement(AreaReinforcementData(boundary: [.zero, Vec2(3, 0), Vec2(3, 2), Vec2(0, 2)], major: .unitX,
                                                                                              layers: Array(repeating: layer, count: 4))), hostID: floor)
        }
        let a = try #require(m[id])
        let bars = Reinforcement.areaBars(a, m)
        // Major bars (along x) across 2000 − 2 × 40 at 300: 7; minor (along y) across 2920: 10; top and bottom.
        #expect(bars.count == 2 * (7 + 10))
        let zmax = bars.map(\.start.z).max() ?? 0
        #expect(Fx.approx(zmax, 0 - 0.040 - 0.008))
        let zmin = bars.map(\.start.z).min() ?? 0
        #expect(Fx.approx(zmin, -0.2 + 0.040 + 0.008))
        #expect(bars.allSatisfy { $0.start.x >= 0.04 - 1e-9 && $0.end.x <= 2.96 + 1e-9 && $0.start.y >= 0.04 - 1e-9 && $0.end.y <= 1.96 + 1e-9 })
        #expect(Reinforcement.areaTag(a, m) == "(T) 15M@300 EW (B) 15M@300 EW", "\(Reinforcement.areaTag(a, m))")
        // Deleting the floor deletes its reinforcement.
        try Fx.commit(&m) { tx in tx.delete(floor) }
        #expect(m[id] == nil)
    }

    @Test func rebarSetsPathFabricAndCouplersLayOutTheirBars() throws {
        var (m, _, floor) = try Self.slab(w: 6, h: 4)
        let bt = Self.barType(m, "15M")
        var (path, fa, rb, cp) = (ElementID(0), ElementID(0), ElementID(0), ElementID(0))
        try Fx.commit(&m) { tx in
            // A path along the south edge, drawn west to east: bars run north, into the slab.
            path = tx.create(.pathReinforcement, data: .pathReinforcement(PathReinforcementData(path: [.zero, Vec2(3, 0)], barTypeID: bt, spacing: 0.3, length: 1.8)), hostID: floor)
            let ft = Reinforcement.ensureFabricType(in: tx)
            fa = tx.create(.fabricAreas, data: .fabricArea(FabricAreaData(boundary: [.zero, Vec2(6, 0), Vec2(6, 4), Vec2(0, 4)], major: .unitX, fabricTypeID: ft)), hostID: floor)
            rb = tx.create(.structuralRebar, data: .rebar(RebarData(start: Vec2(0.5, 1), end: Vec2(2.5, 1), count: 2, spacing: 0.2)), typeID: bt, hostID: floor)
            cp = tx.create(.rebarCouplers, data: .rebarCoupler(RebarCouplerData(atEnd: true)), hostID: rb)
        }
        let bars = Reinforcement.pathBars(try #require(m[path]), m)
        #expect(bars.count == 11)
        #expect(bars.allSatisfy { Fx.approx($0.end.y - $0.start.y, 1.8) })
        #expect(Reinforcement.pathTag(try #require(m[path]), m) == "15M @ 300")
        // 2 × 2 lapped 4800 × 2400 sheets cover 5920 × 3920.
        #expect(Reinforcement.fabricAreaSheets(try #require(m[fa]), m).count == 4)
        #expect(!Reinforcement.fabricAreaWires(try #require(m[fa]), m).isEmpty)
        let set = Reinforcement.rebarBars(try #require(m[rb]), m)
        #expect(set.count == 2 && Fx.approx(set[1].start.y, 1.2))
        #expect(Fx.approx(set[0].start.z, -0.2 + 0.040 + 0.008))
        let pts = Reinforcement.couplerPoints(try #require(m[cp]), m)
        #expect(pts.count == 2 && Fx.approx(pts[0].center.x, 2.5))
        // Bars become steel rods in 3D.
        let parts = ElementMeshes.parts(try #require(m[rb]), m)
        #expect(parts.count == 1 && parts[0].mesh.triangleCount == 2 * (8 * 2 + 2 * 6))
        // Deleting the set deletes its couplers.
        try Fx.commit(&m) { tx in tx.delete(rb) }
        #expect(m[cp] == nil)
    }

    @Test func coverSettingsMoveTheBars() throws {
        var (m, _, floor) = try Self.slab()
        let bt = Self.barType(m, "15M")
        var rb = ElementID(0)
        try Fx.commit(&m) { tx in
            rb = tx.create(.structuralRebar, data: .rebar(RebarData(start: Vec2(0.5, 1), end: Vec2(2.5, 1))), typeID: bt, hostID: floor)
            var s = StructuralSettingsData(); s.rebarCover = 0.05
            StructuralFraming.setSettings(s, in: tx)
        }
        #expect(Fx.approx(Reinforcement.rebarBars(try #require(m[rb]), m)[0].start.z, -0.2 + 0.05 + 0.008))
        #expect(m.elements(.structuralSettings).count == 1)
    }

    @Test func wallAreaReinforcementLiesInsideTheWall() throws {
        let box = try Fx.box()
        var m = box.model
        let w = box.walls[0]
        var id = ElementID(0)
        try Fx.commit(&m) { tx in
            let bt = Reinforcement.ensureBarTypes(in: tx)[1]
            let face = [Vec2.zero, Vec2(4, 0), Vec2(4, 3), Vec2(0, 3)]
            id = tx.create(.areaReinforcement, data: .areaReinforcement(AreaReinforcementData(boundary: face, major: .unitX,
                                                                                              layers: Array(repeating: RebarLayer(barTypeID: bt, spacing: 0.3), count: 4))), hostID: w)
        }
        let bars = Reinforcement.areaBars(try #require(m[id]), m)
        #expect(!bars.isEmpty)
        // The south wall runs along y = 0, 200 mm thick: every bar stays inside it, on both faces.
        #expect(bars.allSatisfy { abs($0.start.y) < 0.1 && abs($0.end.y) < 0.1 && $0.start.z >= 0 && $0.end.z <= 3 + 1e-6 })
        #expect(bars.contains { $0.start.y > 0 } && bars.contains { $0.start.y < 0 })
    }

    // MARK: Framing

    @Test func trussBraceAndBeamSystem() throws {
        var (m, ids) = Fx.template()
        let beamType = ids.systemTypes["Steel Beam 200 x 400"]
        var truss: [ElementID] = [], brace = ElementID(0), sys = ElementID(0)
        try Fx.commit(&m) { tx in
            truss = try StructuralFraming.truss(from: .zero, to: Vec2(6, 0), depth: 1.5, type: beamType, level: ids.levels[0], in: tx)
            let up = StructuralFraming.storeyHeight(above: ids.levels[0], tx.model)
            brace = StructuralFraming.brace(from: Vec2(0, 5), to: Vec2(4, 5), z0: 0, z1: up, type: beamType, level: ids.levels[0], in: tx)
            sys = try StructuralFraming.beamSystem(boundary: [Vec2(0, 10), Vec2(8, 10), Vec2(8, 16), Vec2(0, 16)], spacing: 1.8, beamType: beamType, level: ids.levels[0], in: tx)
        }
        // Two chords and four alternating diagonals (6 m / 1.5 m).
        #expect(truss.count == 6)
        let chords = truss.prefix(2).compactMap { m[$0]?.beam }
        #expect(chords.map(\.startOffset) == [0, 1.5])
        #expect(m[truss[2]]?.beam?.startOffset == 0 && m[truss[2]]?.beam?.endOffset == 1.5 && m[truss[3]]?.beam?.startOffset == 1.5)
        #expect(m[brace]?.beam?.endOffset == 4 && m[brace]?.params[StructuralFraming.usageParameter]?.textValue == "Vertical Bracing")
        // A 6 m bay at 1.8 m: three beams along the first edge, centred across it.
        var beams = m.hosted(by: sys).compactMap(\.beam)
        #expect(beams.count == 3)
        #expect(beams.compactMap { $0.curve.asSegment?.start.y }.sorted().map { ($0 * 1000).rounded() / 1000 } == [11.2, 13, 14.8])
        // The system is edited as one: a new spacing rebuilds its beams, deleting it deletes them.
        try Fx.commit(&m) { tx in tx.update(sys) { $0.beamSystem?.spacing = 1.0 } }
        beams = m.hosted(by: sys).compactMap(\.beam)
        #expect(beams.count == 6)
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("beamSystem.spacing"), to: .double(2.0), on: sys, in: tx) }
        #expect(m.hosted(by: sys).count == 3)
        try Fx.commit(&m) { tx in tx.delete(sys) }
        #expect(m.elements(.structuralFraming).count == 7)
    }

    @Test func beamCutbackShortensBeamsInPlan() throws {
        var (m, ids) = Fx.template()
        var b = ElementID(0)
        try Fx.commit(&m) { tx in
            b = tx.create(.structuralFraming, data: .beam(BeamData(curve: .line(Segment2(.zero, Vec2(5, 0))))), typeID: ids.systemTypes["Steel Beam 200 x 400"], levelID: ids.levels[0])
        }
        let plan = try #require(m[ids.planViews[ids.levels[0]]!])
        let item = try #require(ViewGraphicsBuilder(model: m, view: plan).build().items.first { $0.elementID == b })
        // 2.38 mm on paper at 1:100.
        #expect(Fx.approx(item.bounds.min.x, 0.238, 1e-6) && Fx.approx(item.bounds.max.x, 5 - 0.238, 1e-6))
    }

    // MARK: Graphics and symbols

    @Test func reinforcementDrawsInPlanAndSymbolsCarryTheirTags() throws {
        var (m, ids, floor) = try Self.slab(w: 6, h: 4)
        let plan = ids.planViews[ids.levels[0]]!
        let bt = Self.barType(m, "15M")
        var (rb, area, sym, multi) = (ElementID(0), ElementID(0), ElementID(0), ElementID(0))
        try Fx.commit(&m) { tx in
            rb = tx.create(.structuralRebar, data: .rebar(RebarData(start: Vec2(0.5, 1), end: Vec2(2.5, 1), count: 3, spacing: 0.2)), typeID: bt, hostID: floor)
            area = tx.create(.areaReinforcement, data: .areaReinforcement(AreaReinforcementData(boundary: [Vec2(3, 0), Vec2(6, 0), Vec2(6, 4), Vec2(3, 4)], major: .unitX,
                                                                                                layers: Array(repeating: RebarLayer(barTypeID: bt, spacing: 0.3), count: 4))), hostID: floor)
            sym = tx.create(.genericAnnotations, data: .structuralSymbol(StructuralSymbolData(kind: .rebar, position: Vec2(1.5, 1.2))), hostID: rb, ownerViewID: plan)
            multi = tx.create(.genericAnnotations, data: .structuralSymbol(StructuralSymbolData(kind: .multiRebarAligned, position: Vec2(1.5, 1.2))), hostID: rb, ownerViewID: plan)
        }
        let g = ViewGraphicsBuilder(model: m, view: m[plan]!).build()
        let bars = try #require(g.items.first { $0.elementID == rb })
        #expect(bars.primitives.count == 3)
        #expect(g.items.contains { $0.elementID == area })
        func texts(_ id: ElementID) -> [String] {
            g.items.first { $0.elementID == id }?.primitives.compactMap { if case .text(let t) = $0 { return t.string }; return nil } ?? []
        }
        #expect(texts(sym) == ["3 15M @ 200"], "\(texts(sym)) \(texts(multi))")
        #expect(texts(multi).contains("400") && texts(multi).contains("3 15M @ 200"))
        // Symbols go with their rebar set.
        try Fx.commit(&m) { tx in tx.delete(rb) }
        #expect(m[sym] == nil && m[multi] == nil)
    }

    @Test func movingReinforcementMovesItsBars() throws {
        var (m, _, floor) = try Self.slab(w: 6, h: 4)
        let bt = Self.barType(m, "15M")
        var rb = ElementID(0)
        try Fx.commit(&m) { tx in
            rb = tx.create(.structuralRebar, data: .rebar(RebarData(start: Vec2(0.5, 1), end: Vec2(2.5, 1), count: 2, spacing: 0.2)), typeID: bt, hostID: floor)
        }
        var e = try #require(m[rb])
        let before = Reinforcement.rebarBars(e, m).map { ($0.start.xy + $0.end.xy) / 2 }
        #expect(ElementTransform.apply(.scale(1, -1), to: &e))
        let after = Reinforcement.rebarBars(e, m).map { ($0.start.xy + $0.end.xy) / 2 }
        // Mirrored about the x axis: every bar lands on its mirror image.
        #expect(Set(after.map { Vec2(($0.x * 1000).rounded() / 1000, ($0.y * 1000).rounded() / 1000) })
                == Set(before.map { Vec2(($0.x * 1000).rounded() / 1000, (-$0.y * 1000).rounded() / 1000) }))
    }

    @Test func reinforcementParametersAndSchedules() throws {
        var (m, _, floor) = try Self.slab(w: 6, h: 4)
        let bt = Self.barType(m, "15M")
        var rb = ElementID(0)
        try Fx.commit(&m) { tx in
            rb = tx.create(.structuralRebar, data: .rebar(RebarData(start: Vec2(0.5, 1), end: Vec2(2.5, 1), count: 3, spacing: 0.2)), typeID: bt, hostID: floor)
        }
        let e = try #require(m[rb])
        #expect(Parameters.value(ParameterID("rebar.quantity"), of: e, m) == .int(3))
        #expect(Parameters.value(ParameterID("rebar.totalLength"), of: e, m)?.doubleValue.map { Fx.approx($0, 6) } == true)
        #expect(Parameters.value(Reinforcement.barDiameterParameter, of: e, m)?.doubleValue == 0.016)
        try Fx.commit(&m) { tx in try Parameters.set(ParameterID("rebar.quantity"), to: .int(5), on: rb, in: tx) }
        #expect(m[rb]?.rebar?.count == 5)
        #expect(Category.schedulable.contains(.structuralRebar))
    }
}

/// F34 tools, driven as the canvas drives them.
@MainActor
@Suite("F34 structure and reinforcement tools")
struct F34ToolTests {
    func context(_ build: (TransactionContext, ProjectTemplates.Ids) throws -> Void = { _, _ in }) throws -> (ToolContext, ProjectTemplates.Ids) {
        var (m, ids) = Fx.template()
        try Fx.commit(&m) { tx in
            let s = SlabData(boundary: Sketch(rect: Rect2(min: .zero, max: Vec2(6, 4))))
            tx.create(.floors, data: .slab(s), typeID: ids.floorTypes["Concrete Slab 200mm"], levelID: ids.levels[0])
            try build(tx, ids)
        }
        let session = DocumentSession(model: m)
        session.undoManager.groupsByEvent = false
        session.undoManager.beginUndoGrouping()
        let ctx = ToolContext(session: session, viewID: ids.planViews[ids.levels[0]]!)
        ctx.pixel = 0.01
        return (ctx, ids)
    }
    func click(_ tool: some InteractiveTool, _ p: Vec2, hit: ElementID? = nil) {
        var i = ToolInput(point: p, rawPoint: p)
        i.hit = hit
        tool.pointerMoved(i)
        tool.pointerDown(i)
    }
    var floorID: (ToolContext) -> ElementID { { $0.model.elements(.floors).first!.id } }

    @Test func rebarToolPlacesASetInTheFloor() throws {
        let (ctx, _) = try context()
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        let tool = RebarTool(ctx: ctx)
        tool.setOption("quantity", .int(4))
        tool.setOption("spacing", .double(0.25))
        click(tool, Vec2(10, 10))
        #expect(messages.last == "Start the bar inside a floor or slab.")
        click(tool, Vec2(1, 1))
        tool.pointerMoved(ToolInput(point: Vec2(5, 1), rawPoint: Vec2(5, 1)))
        #expect(tool.preview.primitives.count == 4)
        click(tool, Vec2(5, 1))
        let r = try #require(ctx.model.elements(.structuralRebar).first)
        #expect(r.rebar == RebarData(start: Vec2(1, 1), end: Vec2(5, 1), count: 4, spacing: 0.25))
        #expect(r.hostID == floorID(ctx) && ctx.model[r.typeID]?.name == "15M")
        #expect(ctx.session.selection.ids == [r.id])
    }

    @Test func areaPathAndFabricAreaPickTheFloorThenSketch() throws {
        let (ctx, _) = try context()
        let area = ReinforcementSketchTool(ctx: ctx, kind: .area)
        #expect(!area.isSketchMode)
        click(area, Vec2(2, 2))
        #expect(area.isSketchMode)
        area.setOption("mode", .text("Rectangle"))
        click(area, Vec2(0, 0)); click(area, Vec2(3, 2))
        #expect(area.finish())
        let a = try #require(ctx.model.elements(.areaReinforcement).first)
        #expect(a.hostID == floorID(ctx) && a.areaReinforcement?.layers.count == 4)
        #expect(ctx.model.hosted(by: a.id).first?.structuralSymbol?.kind == .areaReinforcement)

        let path = ReinforcementSketchTool(ctx: ctx, kind: .path)
        click(path, Vec2(2, 2))
        click(path, Vec2(0, 0)); click(path, Vec2(3, 0))
        #expect(path.finish())
        let p = try #require(ctx.model.elements(.pathReinforcement).first)
        #expect(p.pathReinforcement?.path == [Vec2(0, 0), Vec2(3, 0)])
        #expect(Reinforcement.pathBars(p, ctx.model).count == 11)
        #expect(ctx.model.hosted(by: p.id).first?.structuralSymbol?.kind == .pathReinforcement)

        let fabric = ReinforcementSketchTool(ctx: ctx, kind: .fabricArea)
        click(fabric, Vec2(2, 2))
        fabric.setOption("mode", .text("Rectangle"))
        click(fabric, Vec2(0, 0)); click(fabric, Vec2(6, 4))
        #expect(fabric.finish())
        let f = try #require(ctx.model.elements(.fabricAreas).first)
        #expect(Reinforcement.fabricAreaSheets(f, ctx.model).count == 4)
    }

    @Test func wallAreaReinforcementIsSketchedInAnElevation() throws {
        var walls: [ElementID] = []
        let (ctx, ids) = try context { tx, ids in walls = Fx.boxWalls(tx, ids) }
        let south = try #require(ctx.model.views.first { $0.name == "South" && $0.view?.kind == .elevation })
        ctx.viewID = south.id
        let tool = ReinforcementSketchTool(ctx: ctx, kind: .area)
        click(tool, Vec2(2, 1), hit: walls[0])
        #expect(tool.isSketchMode)
        tool.setOption("mode", .text("Rectangle"))
        click(tool, Vec2(1, 0.5)); click(tool, Vec2(4, 2.5))
        #expect(tool.finish())
        let a = try #require(ctx.model.elements(.areaReinforcement).first)
        #expect(a.hostID == walls[0] && a.levelID == ids.levels[0])
        let b = a.areaReinforcement!.boundary
        #expect(b.map(\.x).min() == 1 && b.map(\.x).max() == 4 && b.map(\.y).min() == 0.5 && b.map(\.y).max() == 2.5)
        // It draws on its wall in the elevation.
        let g = ViewGraphicsBuilder(model: ctx.model, view: ctx.model[south.id]!).build()
        #expect(g.items.contains { $0.elementID == a.id })
    }

    @Test func fabricSheetCouplersAndSymbols() throws {
        let (ctx, _) = try context()
        let sheet = FabricSheetTool(ctx: ctx)
        click(sheet, Vec2(3, 2))
        #expect(ctx.model.elements(.fabricReinforcement).first?.fabricSheet?.center == Vec2(3, 2))
        // Two sets meeting end to end.
        let rebar = RebarTool(ctx: ctx)
        click(rebar, Vec2(0.5, 1)); click(rebar, Vec2(2.5, 1))
        click(rebar, Vec2(2.5, 1)); click(rebar, Vec2(4.5, 1))
        let sets = ctx.model.elements(.structuralRebar).sorted { $0.id < $1.id }
        #expect(sets.count == 2)
        let coupler = RebarCouplerTool(ctx: ctx, between: true)
        click(coupler, Vec2(2.4, 1)); click(coupler, Vec2(2.6, 1))
        let c = try #require(ctx.model.elements(.rebarCouplers).first)
        #expect(c.hostID == sets[0].id && c.rebarCoupler == RebarCouplerData(atEnd: true, otherRebarID: sets[1].id))
        // Place on Bar End refuses a second coupler on the same end.
        var messages: [String] = []
        ctx.showMessage = { messages.append($0) }
        let onEnd = RebarCouplerTool(ctx: ctx)
        click(onEnd, Vec2(2.4, 1))
        #expect(messages.last == "This end of the bars already has a coupler.")
        // A rebar symbol is placed with one click; a Multi-Rebar annotation picks the set, then places the line.
        let sym = StructuralSymbolTool(ctx: ctx, kind: .rebar, commandID: .rebarSymbol)
        click(sym, Vec2(1.5, 1))
        #expect(ctx.model.hosted(by: sets[0].id).contains { $0.structuralSymbol?.kind == .rebar })
        let multi = StructuralSymbolTool(ctx: ctx, kind: .multiRebarLinear, commandID: .multiRebarLinear)
        click(multi, Vec2(3.5, 1))
        #expect(ctx.model.hosted(by: sets[1].id).allSatisfy { $0.structuralSymbol == nil })
        click(multi, Vec2(3.5, 2))
        #expect(ctx.model.hosted(by: sets[1].id).contains { $0.structuralSymbol == StructuralSymbolData(kind: .multiRebarLinear, position: Vec2(3.5, 2)) })
    }

    @Test func trussBraceAndBeamSystemTools() throws {
        let (ctx, ids) = try context()
        ctx.currentTypes[.structuralFraming] = ids.systemTypes["Steel Beam 200 x 400"]
        let truss = TrussBraceTool(ctx: ctx, kind: .truss)
        click(truss, Vec2(0, 10)); click(truss, Vec2(9, 10))
        #expect(ctx.model.elements(.structuralFraming).count == 2 + 6)
        let brace = TrussBraceTool(ctx: ctx, kind: .brace)
        click(brace, Vec2(0, 12))
        #expect(brace.numericInput("4000"))
        let b = try #require(ctx.model.elements(.structuralFraming).first { $0.beam?.curve.asSegment?.start == Vec2(0, 12) })
        #expect(b.beam?.endOffset == 4 && b.typeID == ids.systemTypes["Steel Beam 200 x 400"])
        let sys = SketchTool(ctx: ctx, target: .f34(.beamSystem), commandID: .beamSystem)
        sys.setOption("mode", .text("Rectangle"))
        click(sys, Vec2(0, 20)); click(sys, Vec2(8, 26))
        #expect(sys.finish())
        let s = try #require(ctx.model.elements(.beamSystems).first)
        #expect(ctx.model.hosted(by: s.id).filter { $0.beam != nil }.count == 3)
        #expect(ctx.model.hosted(by: s.id).contains { $0.structuralSymbol?.kind == .beamSystem })
        // Undo removes the system with its beams.
        ctx.session.undoManager.endUndoGrouping()
        ctx.session.undoManager.undo()
        #expect(ctx.model.elements(.beamSystems).isEmpty)
    }
}
