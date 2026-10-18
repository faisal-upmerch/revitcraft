import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

// W4-HATCH: line-family fill patterns — generator geometry, standard library, material defaults, override order,
// text format, edits and undo.

@Suite("Fill patterns")
struct FillPatternTests {
    static let square = Polygon2.rectangle(Rect2(min: Vec2(0, 0), max: Vec2(10, 10)))

    // MARK: Generator

    @Test func draftingLinesAreSpacedOnPaperAndScaleWithTheView() throws {
        let h = HatchPattern(families: [HatchFamily(angle: 0, spacing: 3)], isModel: false)
        let at100 = try #require(HatchGenerator.generate([Self.square], h, scale: 100))
        let at50 = try #require(HatchGenerator.generate([Self.square], h, scale: 50))
        // 3 mm at 1:100 = 0.3 m → 10 m / 0.3 ≈ 33 lines; at 1:50 half the spacing, twice the lines.
        #expect((32...34).contains(at100.segments.count))
        #expect((66...68).contains(at50.segments.count))
        #expect(abs(at100.minSpacing - 0.3) < 1e-9 && abs(at50.minSpacing - 0.15) < 1e-9)
        // Every line spans the full square and is horizontal.
        for s in at100.segments {
            #expect(abs(s.start.y - s.end.y) < 1e-9 && abs(s.length - 10) < 1e-6)
            #expect(s.start.x >= -1e-9 && s.end.x <= 10 + 1e-9)
        }
    }

    @Test func modelPatternsIgnoreTheViewScale() throws {
        let h = HatchPattern(families: [HatchFamily(angle: 90, spacing: 600)], isModel: true)
        let a = try #require(HatchGenerator.generate([Self.square], h, scale: 100))
        let b = try #require(HatchGenerator.generate([Self.square], h, scale: 20))
        #expect(a.segments.count == b.segments.count && (16...18).contains(a.segments.count))
        #expect(abs(a.minSpacing - 0.6) < 1e-9)
    }

    @Test func linesAreClippedToThePolygonAndSkipHoles() throws {
        let hole = Polygon2.rectangle(Rect2(min: Vec2(4, 4), max: Vec2(6, 6)))
        let h = HatchPattern(families: [HatchFamily(angle: 45, spacing: 2), HatchFamily(angle: 0, spacing: 1.5)], isModel: false)
        let lines = try #require(HatchGenerator.generate([Self.square, hole], h, scale: 100))
        #expect(lines.segments.count > 60)
        for s in lines.segments {
            let m = s.start.midpoint(s.end)
            #expect(m.x > -1e-6 && m.x < 10 + 1e-6 && m.y > -1e-6 && m.y < 10 + 1e-6, "segment outside the square")
            #expect(!(m.x > 4 + 1e-6 && m.x < 6 - 1e-6 && m.y > 4 + 1e-6 && m.y < 6 - 1e-6), "segment inside the hole")
        }
        // A diagonal line through the middle is split around the hole: its parts end on the hole's edges.
        func onHoleEdge(_ p: Vec2) -> Bool {
            let dx4: Double = abs(p.x - 4), dx6: Double = abs(p.x - 6), dy4: Double = abs(p.y - 4), dy6: Double = abs(p.y - 6)
            return min(dx4, dx6, dy4, dy6) < 1e-6
        }
        let touching = lines.segments.filter { onHoleEdge($0.start) || onHoleEdge($0.end) }
        #expect(touching.count >= 8)
    }

    @Test func dashesAndDotsFollowThePeriodAndTheShift() throws {
        // 1:1000 so 1 mm = 1 m: dashes 4 on, 2 off, a dot, 2 off → period 8.
        let fam = HatchFamily(angle: 0, spacing: 5, dashes: [4, -2, 0, -2])
        let lines = try #require(HatchGenerator.generate([Self.square], HatchPattern(families: [fam], isModel: false), scale: 1000))
        #expect(lines.segments.allSatisfy { $0.length <= 4 + 1e-9 })
        #expect(lines.segments.contains { abs($0.length - 4) < 1e-9 })
        #expect(!lines.dots.isEmpty)
        for d in lines.dots {
            let r: Double = (d.x - 6).truncatingRemainder(dividingBy: 8)
            let onPeriod: Bool = abs(r) < 1e-6 || abs(r + 8) < 1e-6 || abs(r - 8) < 1e-6
            #expect(onPeriod, "dot at \(d.x) is off the dash period")
        }
        // Shift staggers successive lines by 4 → dash starts alternate between x ≡ 0 and x ≡ 4 (mod 8).
        let shifted = HatchFamily(angle: 0, shift: 4, spacing: 5, dashes: [4, -4])
        let s = try #require(HatchGenerator.generate([Self.square], HatchPattern(families: [shifted], isModel: false), scale: 1000))
        let rows = Dictionary(grouping: s.segments) { Int($0.start.y.rounded()) }
        let starts = rows.mapValues { Set($0.map { Int(($0.start.x).rounded()) % 8 }) }
        #expect(starts[5] == [4] && starts[10] == [0], "\(starts)")
    }

    @Test func overBudgetHatchReturnsNilAndTheCacheRemembers() {
        let dense = HatchPattern(families: [HatchFamily(angle: 0, spacing: 0.02), HatchFamily(angle: 90, spacing: 0.02)], isModel: false)
        #expect(HatchGenerator.generate([Self.square], dense, scale: 100, budget: 1000) == nil)
        let cache = HatchCache(capacity: 8)
        let h = HatchPattern(families: [HatchFamily(angle: 45, spacing: 3)], isModel: false)
        let a = cache.lines([Self.square], h, scale: 100)
        let b = cache.lines([Self.square], h, scale: 100)
        #expect(a == b && a != nil)
        #expect(cache.statistics.hits == 1 && cache.statistics.misses == 1)
        for i in 0..<20 { _ = cache.lines([Self.square], HatchPattern(families: [HatchFamily(angle: Double(i), spacing: 3)], isModel: false), scale: 100) }
        #expect(cache.statistics.entries <= 8)
    }

    // MARK: Library and defaults

    @Test func standardLibraryIsLargeValidAndUnique() {
        let all = FillPatternLibrary.all
        #expect(all.count >= 40)
        #expect(Set(all.map(\.name)).count == all.count)
        for p in all where p.kind != .solid {
            #expect(!p.families.isEmpty && p.families.allSatisfy(\.isValid), "\(p.name) has an invalid family")
            #expect(p.data.hatch != nil)
        }
        // The 14 legacy procedural names are all standard patterns (older files and pickers keep working).
        for k in FillPatternKind.allCases { #expect(FillPatternLibrary.named(k.rawValue) != nil, "\(k.rawValue)") }
        #expect(FillPatternLibrary.drafting.count >= 25 && FillPatternLibrary.model.count >= 15)
    }

    @Test func newProjectsHaveTheLibraryAndMaterialsGetPatterns() throws {
        let (m, ids) = Fx.template()
        let names = Set(m.elements(.fillPatterns).map(\.name))
        #expect(FillPatternLibrary.all.allSatisfy { names.contains($0.name) })
        func cut(_ material: String) -> String? { m[m[ids.materials[material]]?.material?.cutPatternID]?.name }
        func surface(_ material: String) -> String? { m[m[ids.materials[material]]?.material?.surfacePatternID]?.name }
        #expect(cut("Brick, Common") == "Masonry - Brick" && surface("Brick, Common") == "Brick")
        #expect(cut("Concrete Masonry Units") == "Masonry - Concrete Block")
        #expect(cut("Concrete, Cast-in-Place") == "Concrete")
        #expect(cut("Rigid Insulation") == "Insulation - Rigid" && cut("Mineral Wool") == "Insulation")
        #expect(cut("Timber Stud") == "Wood - Framing" && cut("Oak Flooring") == "Wood Grain" && surface("Oak Flooring") == "Wood - Plank 150")
        #expect(cut("Steel") == "Steel" && cut("Aluminum") == "Aluminum" && cut("Glass") == "Glass" && cut("Earth") == "Earth")
        #expect(cut("Plasterboard") == "Gypsum - Plaster" && cut("Ceramic Tile") == "Tile" && surface("Ceramic Tile") == "Tile 300 x 300")
        // Region types reference project patterns.
        let region = m[ids.systemTypes["Region Concrete"]]?.typeData
        #expect(m[region?.params[ParameterID("region.fillPattern")]?.refValue]?.name == "Concrete")
        // Adding the standard library again is a no-op.
        var copy = m
        try Fx.commit(&copy) { tx in #expect(FillPatternLibrary.ensureStandard(in: tx) == 0) }
    }

    @Test func everyLibraryMaterialGetsSensibleDefaults() {
        let index = Dictionary(uniqueKeysWithValues: FillPatternLibrary.all.enumerated().map { ($0.element.name, ElementID(UInt64($0.offset) + 1)) })
        var withCut = 0
        for lib in MaterialLibrary.all {
            let d = MaterialPatternDefaults.defaults(name: lib.name, materialClass: lib.materialClass)
            if let c = d.cut { #expect(index[c] != nil, "\(lib.name): unknown cut pattern \(c)"); #expect(FillPatternLibrary.named(c)?.isModel == false, "\(lib.name): cut pattern \(c) must be drafting"); withCut += 1 }
            if let s = d.surface { #expect(index[s] != nil, "\(lib.name): unknown surface pattern \(s)"); #expect(FillPatternLibrary.named(s)?.isModel == true, "\(lib.name): surface pattern \(s) must be model") }
            let data = lib.materialData(fillPatterns: index)
            #expect((data.cutPatternID != nil) == (d.cut != nil))
        }
        #expect(Double(withCut) / Double(MaterialLibrary.all.count) > 0.9)
    }

    // MARK: Rendering order

    @Test func wallCutFillsFollowDetailMaterialAndOverrides() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        var wall: ElementID = ElementID(0)
        try Fx.commit(&m) { tx in wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(6, 0), type: Fx.brick) }
        func fills(_ detail: DetailLevel, _ edit: ((inout ViewData) -> Void)? = nil) throws -> [GFill] {
            var copy = m
            try Fx.commit(&copy) { tx in tx.update(plan) { $0.view?.detailLevel = detail; edit?(&$0.view!) } }
            let g = ViewGraphicsBuilder(model: copy, view: copy[plan]!).build()
            return g.items.filter { $0.elementID == wall && $0.layer == .cut }.flatMap(\.primitives).compactMap { if case .fill(_, let f) = $0 { return f } else { return nil } }
        }
        let coarse = try fills(.coarse)
        #expect(coarse.count == 1 && coarse[0].pattern == .solid && coarse[0].hatch == nil)
        let medium = try fills(.medium)   // core material (CMU) at medium
        #expect(medium.count == 1 && medium[0].hatch == m[ids.materials["Concrete Masonry Units"]!]?.material.flatMap { m[$0.cutPatternID]?.fillPattern?.hatch })
        let fine = try fills(.fine)       // one fill per layer, each with its material's pattern
        let brickHatch = m[m[ids.materials["Brick, Common"]!]?.material?.cutPatternID]?.fillPattern?.hatch
        let insulationHatch = m[m[ids.materials["Rigid Insulation"]!]?.material?.cutPatternID]?.fillPattern?.hatch
        #expect(fine.count >= 4)
        #expect(fine.contains { $0.hatch == brickHatch } && fine.contains { $0.hatch == insulationHatch })
        #expect(fine.allSatisfy { $0.hatch != nil })
        // Type's Coarse Scale Fill Pattern + colour.
        let earth = m.elements(.fillPatterns).first { $0.name == "Earth" }!.id
        var copy = m
        try Fx.commit(&copy) { tx in tx.update(ids.wallTypes[Fx.brick]!) { $0.typeData?.params[ParameterID("type.coarseFillPattern")] = .ref(earth); $0.typeData?.params[ParameterID("type.coarseFillColor")] = .text("#FF0000") } }
        try Fx.commit(&copy) { tx in tx.update(plan) { $0.view?.detailLevel = .coarse } }
        let coarseTyped = ViewGraphicsBuilder(model: copy, view: copy[plan]!).build()
            .items.filter { $0.elementID == wall && $0.layer == .cut }.flatMap(\.primitives).compactMap { if case .fill(_, let f) = $0 { return f } else { return nil } }
        #expect(coarseTyped.first?.hatch == copy[earth]?.fillPattern?.hatch && coarseTyped.first?.color == RGBColor(hex: 0xFF0000))
        // V/G category override → every layer; element override wins over the category.
        let steel = m.elements(.fillPatterns).first { $0.name == "Steel" }!.id
        let sand = m.elements(.fillPatterns).first { $0.name == "Sand" }!.id
        let categoryOverridden = try fills(.fine) { v in var o = GraphicOverride(); o.cutPatternID = steel; o.cutPatternColor = RGBColor(hex: 0x0000FF); v.visibility.categoryOverrides[.walls] = o }
        #expect(categoryOverridden.allSatisfy { $0.hatch == m[steel]?.fillPattern?.hatch && $0.color == RGBColor(hex: 0x0000FF) })
        let elementOverridden = try fills(.fine) { v in
            var o = GraphicOverride(); o.cutPatternID = steel; v.visibility.categoryOverrides[.walls] = o
            var eo = GraphicOverride(); eo.cutPatternID = sand; v.visibility.elementOverrides[wall] = eo
        }
        #expect(elementOverridden.allSatisfy { $0.hatch == m[sand]?.fillPattern?.hatch })
        // A Solid Fill override removes the hatch.
        let solid = m.elements(.fillPatterns).first { $0.name == "Solid Fill" }!.id
        let solidOverridden = try fills(.fine) { v in var o = GraphicOverride(); o.cutPatternID = solid; v.visibility.categoryOverrides[.walls] = o }
        #expect(solidOverridden.allSatisfy { $0.pattern == .solid && $0.hatch == nil })
    }

    @Test func floorsShowTheirFinishSurfacePatternInPlanAndRegionsUseProjectPatterns() throws {
        var (m, ids) = Fx.template()
        let plan = ids.planViews[ids.levels[0]]!
        let tile = m.elements(.fillPatterns).first { $0.name == "Tile 300 x 300" }!.id
        var floor = ElementID(0), region = ElementID(0)
        try Fx.commit(&m) { tx in
            tx.update(ids.materials["Concrete, Cast-in-Place"]!) { $0.material?.surfacePatternID = tile }
            floor = tx.create(.floors, data: .slab(SlabData(boundary: Sketch(rect: Rect2(min: Vec2(0, 0), max: Vec2(5, 5))))), typeID: ids.floorTypes["Concrete Slab 200mm"]!, levelID: ids.levels[0])
            region = tx.create(.filledRegions, data: .filledRegion(FilledRegionData(boundary: Sketch(rect: Rect2(min: Vec2(7, 7), max: Vec2(9, 9))))),
                               typeID: ids.systemTypes["Region Concrete"], ownerViewID: plan)
        }
        let g = ViewGraphicsBuilder(model: m, view: m[plan]!).build()
        let floorFills = g.items.filter { $0.elementID == floor }.flatMap(\.primitives).compactMap { if case .fill(_, let f) = $0 { return f } else { return nil } }
        #expect(floorFills.contains { $0.hatch == m[tile]?.fillPattern?.hatch && $0.isModelPattern })
        let regionFills = g.items.filter { $0.elementID == region }.flatMap(\.primitives).compactMap { if case .fill(_, let f) = $0 { return f } else { return nil } }
        #expect(regionFills.first?.hatch == m.elements(.fillPatterns).first { $0.name == "Concrete" }?.fillPattern?.hatch)
        #expect(regionFills.first?.color == RGBColor(hex: 0x555555) && regionFills.first?.background == .white)
    }

    @Test func sectionsCutCompoundWallsPerLayer() throws {
        var (m, ids) = Fx.template()
        var wall = ElementID(0), section = ElementID(0)
        try Fx.commit(&m) { tx in
            wall = Fx.wall(tx, ids, Vec2(0, 0), Vec2(6, 0), type: Fx.brick)
            var sv = ViewData(kind: .section, scale: 20)
            sv.planeOrigin = Vec3(3, 0, 0); sv.viewDirection = Vec2(1, 0); sv.farClip = 6   // perpendicular to the wall
            sv.cropRegion = Rect2(min: Vec2(-3, -1), max: Vec2(3, 5)); sv.cropActive = true
            sv.detailLevel = .fine
            section = tx.create(.views, name: "S", data: .view(sv))
        }
        let g = ViewGraphicsBuilder(model: m, view: m[section]!).build()
        let fills = g.items.filter { $0.elementID == wall && $0.layer == .cut }.flatMap(\.primitives).compactMap { if case .fill(_, let f) = $0 { return f } else { return nil } }
        #expect(fills.count == 4, "one fill per layer, got \(fills.count)")
        let brickHatch = m[m[ids.materials["Brick, Common"]!]?.material?.cutPatternID]?.fillPattern?.hatch
        #expect(fills.contains { $0.hatch == brickHatch })
    }

    // MARK: Text format

    @Test func textFormatRoundTripsAndReportsErrors() throws {
        let entries = FillPatternLibrary.all.filter { $0.kind != .solid }.map { FillPatternText.Entry(name: $0.name, description: $0.description, isModel: $0.isModel, families: $0.families) }
        let text = FillPatternText.format(entries)
        let back = try FillPatternText.parse(text)
        #expect(back.count == entries.count)
        for (a, b) in zip(entries, back) {
            #expect(a.name == b.name && a.isModel == b.isModel && a.families.count == b.families.count)
            for (fa, fb) in zip(a.families, b.families) {
                #expect(abs(fa.angle - fb.angle) < 1e-4 && abs(fa.spacing - fb.spacing) < 1e-4 && fa.dashes.count == fb.dashes.count)
            }
        }
        let inches = try FillPatternText.parse(";%UNITS=INCH\n*ANSI-ish, steel\n45, 0,0, 0,.125\n")
        #expect(abs((inches.first?.families.first?.spacing ?? 0) - 3.175) < 1e-9)
        #expect(throws: FillPatternText.ParseError.familyBeforePattern(line: 1)) { try FillPatternText.parse("45, 0, 0, 0, 3") }
        #expect(throws: FillPatternText.ParseError.emptyPattern(name: "Empty")) { try FillPatternText.parse("*Empty\n") }
        #expect(throws: FillPatternText.ParseError.badFamily(line: 2, text: "45, 0")) { try FillPatternText.parse("*X\n45, 0") }
        #expect(FillPatternText.closestKind([HatchFamily(angle: 0, spacing: 1), HatchFamily(angle: 90, spacing: 1)]) == .crosshatch)
        #expect(FillPatternText.closestKind([HatchFamily(angle: 0, spacing: 1, dashes: [0, -1])]) == .sand)
    }

    // MARK: Edits and undo

    @MainActor @Test func editsValidateFallBackOnDeleteAndUndo() throws {
        let (m0, ids) = Fx.template()
        let session = DocumentSession(model: m0)
        session.undoManager.groupsByEvent = false
        func group(_ body: () -> Void) { session.undoManager.beginUndoGrouping(); body(); session.undoManager.endUndoGrouping() }
        var created: ElementID?
        group { session.perform("New") { tx in created = try FillPatternEdits.create(name: "Rubble", isModel: false, families: [HatchFamily(angle: 30, spacing: 2, dashes: [3, -1])], in: tx) } }
        let id = try #require(created)
        #expect(session.model[id]?.fillPattern?.families?.count == 1 && session.model[id]?.fillPattern?.kind == .diagonalUp)
        group { session.perform("Dup") { tx in
            #expect(throws: FillPatternEdits.EditError.duplicateName("rubble")) { try FillPatternEdits.create(name: "rubble", isModel: false, families: [HatchFamily(angle: 0, spacing: 1)], in: tx) }
            #expect(throws: FillPatternEdits.EditError.invalidFamily(0)) { try FillPatternEdits.create(name: "Bad", isModel: false, families: [HatchFamily(angle: 0, spacing: 0)], in: tx) }
            #expect(throws: FillPatternEdits.EditError.solidLocked) { try FillPatternEdits.delete(tx.model.elements(.fillPatterns).first { $0.name == "Solid Fill" }!.id, in: tx) }
            _ = try FillPatternEdits.duplicate(id, in: tx)
        } }
        #expect(session.model.elements(.fillPatterns).contains { $0.name == "Copy of Rubble" })
        let brick = ids.materials["Brick, Common"]!
        let plan = ids.planViews[ids.levels[0]]!
        group { session.perform("Use") { tx in
            tx.update(brick) { $0.material?.cutPatternID = id }
            tx.update(plan) { var o = GraphicOverride(); o.surfacePatternID = id; $0.view?.visibility.categoryOverrides[.floors] = o }
        } }
        #expect(FillPatternEdits.users(of: id, session.model).map(\.id).sorted() == [brick, plan].sorted())
        group { session.perform("Edit") { tx in try FillPatternEdits.edit(id, name: "Rubble Stone", isModel: true, families: [HatchFamily(angle: 0, spacing: 300), HatchFamily(angle: 90, spacing: 300)], in: tx) } }
        #expect(session.model[id]?.name == "Rubble Stone" && session.model[id]?.fillPattern?.isModelPattern == true && session.model[id]?.fillPattern?.kind == .crosshatch)
        group { session.perform("Delete") { tx in try FillPatternEdits.delete(id, in: tx) } }
        #expect(session.model[id] == nil)
        #expect(session.model[brick]?.material?.cutPatternID == nil)
        #expect(session.model[plan]?.view?.visibility.categoryOverrides[.floors]?.surfacePatternID == nil)
        session.undoManager.undo()
        #expect(session.model[id]?.name == "Rubble Stone" && session.model[brick]?.material?.cutPatternID == id)
        session.undoManager.undo()
        #expect(session.model[id]?.name == "Rubble")
        // Import with name clashes.
        group { session.perform("Import") { tx in
            let ids = try FillPatternEdits.importEntries([FillPatternText.Entry(name: "Rubble", families: [HatchFamily(angle: 0, spacing: 1)]),
                                                          FillPatternText.Entry(name: "", families: [HatchFamily(angle: 0, spacing: 1)])], in: tx)
            #expect(ids.count == 2)
        } }
        #expect(session.model.elements(.fillPatterns).contains { $0.name == "Rubble (2)" } && session.model.elements(.fillPatterns).contains { $0.name == "Imported Pattern" })
        // Parameters: material Cut Pattern through the catalog, rejecting non-patterns.
        group { session.setParameter(ParameterID("material.cutPattern"), value: .ref(id), on: [brick], name: "Cut Pattern") }
        #expect(session.model[brick]?.material?.cutPatternID == id, "\(String(describing: session.lastError))")
        group { session.setParameter(ParameterID("material.cutPattern"), value: .ref(brick), on: [brick], name: "Cut Pattern") }
        #expect(session.lastError != nil)
        session.clearError()
        group { session.setParameter(ParameterID("material.cutPatternColor"), value: .text("#336699"), on: [brick], name: "Colour") }
        #expect(session.model[brick]?.material?.cutPatternColor == RGBColor(hex: 0x336699))
    }

    @Test func olderPatternsDecodeWithoutFamiliesAndGetUpgraded() throws {
        let legacy = try JSONDecoder().decode(FillPatternData.self, from: Data(#"{"kind":"Concrete","isModelPattern":false,"spacing":2}"#.utf8))
        #expect(legacy.families == nil && legacy.hatch == nil && legacy.kind == .concrete)
        let m0 = BIMModel()
        var m = Fx.isolated(m0)
        var id = ElementID(0)
        try Fx.commit(&m) { tx in id = tx.create(.fillPatterns, name: "Concrete", data: .fillPattern(legacy)) }
        try Fx.commit(&m) { tx in _ = FillPatternLibrary.ensureStandard(in: tx) }
        #expect(m[id]?.fillPattern?.families?.isEmpty == false)
        #expect(m.elements(.fillPatterns).filter { $0.name == "Concrete" }.count == 1)
    }
}
