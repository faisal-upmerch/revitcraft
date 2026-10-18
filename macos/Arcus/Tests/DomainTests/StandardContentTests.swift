import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

private let inch = 0.0254

@Suite("Material library")
struct MaterialLibraryTests {
    @Test func libraryIsLargeUniqueAndValid() {
        let all = MaterialLibrary.all
        #expect(all.count >= 250)
        #expect(Set(all.map(\.name)).count == all.count, "names are unique")
        for m in all {
            #expect(m.hex <= 0xFFFFFF)
            #expect((0..<1).contains(m.transparency), "\(m.name)")
            #expect(!m.description.isEmpty, "\(m.name)")
            #expect(m.name.trimmingCharacters(in: .whitespaces) == m.name)
            let c = m.color
            #expect([c.r, c.g, c.b].allSatisfy { (0...1).contains($0) })
        }
        let classes = Set(all.map(\.materialClass))
        for c in [MaterialClass.concrete, .masonry, .stone, .metal, .wood, .glass, .plaster, .insulation, .ceramic, .plastic, .earth, .paint, .liquid, .gas] {
            #expect(classes.contains(c), "\(c.rawValue)")
        }
        #expect(Set(all.map(\.region)).count == MaterialRegion.allCases.count)
    }

    @Test func transparentMaterialsAreTransparent() {
        for n in ["Glass, Clear Float", "Glass", "Water", "Polycarbonate, Multiwall Clear", "Shoji Paper", "Air Space"] {
            #expect((MaterialLibrary.named(n)?.transparency ?? 0) > 0.2, "\(n)")
        }
        #expect(MaterialLibrary.all.filter { $0.materialClass == .glass && $0.transparency > 0 }.count >= 15)
    }

    @Test(arguments: ["Kota Stone", "Kadappa Stone", "Shahabad Stone", "Jaisalmer Stone", "Brick, Fly Ash", "Hardwood, Teak", "Hardwood, Sal",
                      "Hardwood, Sheesham", "IPS Flooring", "Mangalore Tile", "Limestone, Portland", "Travertine", "Brick, Clinker", "Zinc, Natural",
                      "Bamboo, Natural", "Rammed Earth", "Shoji Paper", "Concrete Masonry Units", "Fiber Cement Siding, Lap", "Asphalt Shingles, Charcoal",
                      "Cross-Laminated Timber (CLT)", "Glued-Laminated Timber (Glulam)", "Laminated Veneer Lumber (LVL)", "Plywood", "Oriented Strand Board (OSB)",
                      "Medium-Density Fiberboard (MDF)", "Terrazzo, Cast-in-Place", "Linoleum, Natural", "Epoxy Floor Coating, Grey", "Grass", "Gravel", "Water"])
    func regionalAndCommonMaterialsExist(_ name: String) {
        #expect(MaterialLibrary.named(name) != nil)
    }

    @Test func classesMatchWhatTheMaterialIs() {
        #expect(MaterialLibrary.named("Kota Stone")?.materialClass == .stone)
        #expect(MaterialLibrary.named("Brick, Fly Ash")?.materialClass == .masonry)
        #expect(MaterialLibrary.named("Hardwood, Teak")?.materialClass == .wood)
        #expect(MaterialLibrary.named("Zinc, Natural")?.materialClass == .metal)
        #expect(MaterialLibrary.named("Water")?.materialClass == .liquid)
        #expect(MaterialLibrary.named("Rigid Insulation, XPS")?.materialClass == .insulation)
        #expect(MaterialLibrary.named("Paint - Navy")?.materialClass == .paint)
        #expect(MaterialLibrary.all.filter { $0.materialClass == .paint }.count >= 20)
    }

    @Test func newProjectsGetACuratedSetAndEverythingTheirTypesUse() {
        let core = MaterialLibrary.newProjectSet
        #expect((60...120).contains(core.count))
        #expect(core.count == MaterialLibrary.curated.count, "every curated name is a library material")
        for units in [UnitsSettings.metric, .imperial] {
            let (m, _) = ProjectTemplates.make(.architectural, units: units)
            let names = Set(m.materials.map(\.name))
            for c in core { #expect(names.contains(c.name), "\(c.name)") }
            // Every project material is a library material, so "Add from Library" can recognize it.
            for n in names { #expect(MaterialLibrary.named(n) != nil, "\(n)") }
            #expect(m.materials.count < MaterialLibrary.all.count)
            // Every compound layer has a material.
            for t in m.elements(.elementTypes) {
                for l in t.typeData?.assembly?.layers ?? [] { #expect(m[l.materialID]?.material != nil, "\(t.name)") }
            }
        }
    }

    @Test func addingFromTheLibrarySkipsExistingNames() throws {
        var (m, _) = Fx.template()
        let before = m.materials.count
        var added: [ElementID] = []
        try Fx.commit(&m) { tx in added = StandardContent.addMaterials(["Kota Stone", "Onyx", "Copper, Patina", "Not A Material"], to: tx) }
        #expect(added.count == 2)
        #expect(m.materials.count == before + 2)
        let onyx = m.material(named: "Onyx")?.material
        #expect(onyx?.materialClass == .stone && onyx?.transparency == 0.1 && onyx?.description.isEmpty == false)
        #expect(m[onyx?.cutPatternID]?.name == MaterialPatternDefaults.defaults(name: "Onyx", materialClass: .stone).cut) // W4-HATCH: library defaults by name and class
    }
}

@Suite("Unit-aware standard types")
struct UnitAwareTypeTests {
    static let imperial = ProjectTemplates.make(.architectural, units: .imperial)
    static let metric = Fx.archMetric

    static func names(_ m: BIMModel, _ c: ArcusDomain.Category) -> [String] { m.types(for: c).map(\.name) }
    static func type(_ m: BIMModel, _ c: ArcusDomain.Category, _ name: String) -> Element? { m.types(for: c).first { $0.name == name } }
    static func looksMetric(_ s: String) -> Bool {
        s.range(of: #"\d+ ?mm\b"#, options: .regularExpression) != nil || s.range(of: #"\b\d{3,4} x \d{3,4}\b"#, options: .regularExpression) != nil
    }

    @Test func imperialProjectsHaveImperialNamesOnly() {
        let m = Self.imperial.0
        for c in [ArcusDomain.Category.walls, .floors, .roofs, .ceilings, .doors, .windows, .columns, .structuralColumns, .stairs, .railings, .structuralFraming] {
            for n in Self.names(m, c) { #expect(!Self.looksMetric(n), "\(c): \(n)") }
        }
        #expect(Self.names(m, .walls).filter { $0.contains("\"") || $0.contains("2x") }.count >= 30)
    }

    @Test func metricProjectsHaveMetricNamesOnly() {
        let m = Self.metric.0
        for c in [ArcusDomain.Category.walls, .floors, .roofs, .ceilings, .doors, .windows, .columns, .structuralColumns] {
            for n in Self.names(m, c) { #expect(!n.contains("\""), "\(c): \(n)") }
        }
    }

    @Test(arguments: [UnitSystem.imperial, .metric])
    func extensiveTypeCounts(_ system: UnitSystem) {
        let m = system == .imperial ? Self.imperial.0 : Self.metric.0
        #expect(m.types(for: .walls).count >= 30)
        #expect(m.types(for: .floors).count >= 15)
        #expect(m.types(for: .roofs).count >= 10)
        #expect(m.types(for: .ceilings).count >= 6)
        #expect(m.types(for: .doors).count >= 40)
        #expect(m.types(for: .windows).count >= 30)
        #expect(m.types(for: .columns).count >= 20)
        #expect(m.types(for: .structuralColumns).count >= 40)
        let doorFamilies = Set(m.types(for: .doors).map(\.typeData!.familyName))
        for f in ["Door - Single Flush", "Door - Single Panel", "Door - Single Glazed", "Door - Single Half Glazed", "Door - Double Flush", "Door - Double Glazed",
                  "Door - Sliding Glass", "Door - Bypass Sliding", "Door - Pocket", "Door - Bifold 2-Leaf", "Door - Bifold 4-Leaf", "Door - Barn", "Door - Dutch",
                  "Door - Overhead Sectional", "Door - Roll-Up Shutter", "Door - Storefront Single", "Door - Storefront Double",
                  "Door - Fire Rated Single", "Door - Fire Rated Double"] {
            #expect(doorFamilies.contains(f), "\(f)")
        }
        let windowFamilies = Set(m.types(for: .windows).map(\.typeData!.familyName))
        for f in ["Window - Fixed", "Window - Picture", "Window - Casement", "Window - Casement Double", "Window - Awning", "Window - Hopper",
                  "Window - Single Hung", "Window - Double Hung", "Window - Sliding 2-Track", "Window - Sliding 3-Track", "Window - Bay",
                  "Window - Louvered", "Window - Ventilator"] {
            #expect(windowFamilies.contains(f), "\(f)")
        }
        // Marks stay unique as types are added.
        for c in [Category.doors, .windows, .walls] {
            let marks = m.types(for: c).compactMap { $0.typeData?.params[ParameterID("type.mark")]?.textValue }
            #expect(Set(marks).count == marks.count, "\(c)")
        }
    }

    @Test(arguments: [
        ("Interior - 4 7/8\" Partition (1-hr)", 4.875), ("Interior - 4 1/2\" Partition (2x4)", 4.5), ("Interior - 6 1/8\" Partition (2-hr)", 6.125),
        ("Interior - 7 1/4\" Partition (6\" Mtl. Stud)", 7.25), ("Generic - 8\"", 8), ("Interior - 8\" CMU", 7.625),
        ("Exterior - Brick on 2x6 Wood Stud", 3.625 + 1 + 0.5 + 5.5 + 0.5), ("Exterior - Brick Double Wythe 8\"", 8),
    ])
    func imperialWallThicknesses(_ name: String, _ inches: Double) {
        let m = Self.imperial.0
        let a = Self.type(m, .walls, name)?.typeData?.assembly
        #expect(a?.validate() == nil)
        #expect(abs((a?.totalThickness ?? 0) - inches * inch) < 1e-9, "\(name)")
    }

    @Test func imperialAssembliesUseTheRightLayers() {
        let m = Self.imperial.0
        let brick = Self.type(m, .walls, "Exterior - Brick on 2x6 Wood Stud")!.typeData!.assembly!
        #expect(brick.layers.map(\.function) == [.finish1, .thermal, .membrane, .substrate, .structure, .finish2])
        #expect(m[brick.layers[0].materialID]?.name == "Brick, Face Red")
        #expect(m[brick.layers[4].materialID]?.name == "Wood - Dimensional Lumber")
        #expect(abs(brick.coreThickness - 5.5 * inch) < 1e-9)
        let fire = Self.type(m, .walls, "Interior - 4 7/8\" Partition (1-hr)")!
        #expect(fire.typeData?.params[ParameterID("type.fireRating")] == .text("1 HR"))
        #expect(m[fire.typeData!.assembly!.layers[0].materialID]?.name == "Gypsum Wall Board, Type X")
        let deck = Self.type(m, .floors, "Steel Deck 3\" + 3\" Concrete")!.typeData!.assembly!
        #expect(abs(deck.totalThickness - 6 * inch) < 1e-9)
        #expect(abs(Self.type(m, .floors, "Wood Joist 10\" - Wood Finish")!.typeData!.assembly!.coreThickness - 9.25 * inch) < 1e-9)
        for n in ["2'x2' ACT System", "2'x4' ACT System", "GWB 5/8\" on Mtl. Furring"] { #expect(Self.type(m, .ceilings, n) != nil, "\(n)") }
        #expect(Self.type(m, .roofs, "Asphalt Shingle - Wood Rafter 2x8") != nil)
    }

    @Test(arguments: [("RCC Slab 150mm", 0.15), ("Concrete Slab 200mm", 0.2), ("RCC Slab 150mm - Vitrified Tile", 0.212)])
    func metricFloorThicknesses(_ name: String, _ t: Double) {
        let a = Self.type(Self.metric.0, .floors, name)?.typeData?.assembly
        #expect(a?.validate() == nil)
        #expect(abs((a?.totalThickness ?? 0) - t) < 1e-9)
    }

    @Test func metricAndIndianAssemblies() {
        let m = Self.metric.0
        let brick = Self.type(m, .walls, "Interior - 230mm Brick Wall")!.typeData!.assembly!
        #expect(abs(brick.coreThickness - 0.23) < 1e-9)
        #expect(abs(Self.type(m, .walls, "Interior - 115mm Brick Partition")!.typeData!.assembly!.coreThickness - 0.115) < 1e-9)
        let cavity = Self.type(m, .walls, "Exterior - Brick Cavity 300mm")!.typeData!.assembly!
        #expect(abs(cavity.totalThickness - 0.315) < 1e-9)
        #expect(Self.type(m, .ceilings, "Acoustic Tile 600 x 600") != nil)
        #expect(Self.type(m, .floors, "RCC Slab 150mm - Kota Stone").flatMap { m[$0.typeData?.assembly?.layers.first?.materialID]?.name } == "Kota Stone")
    }

    @Test(arguments: [UnitSystem.imperial, .metric])
    func everyLibraryAssemblyIsValid(_ system: UnitSystem) {
        let specs = BuildingTypesLibrary.assemblies(system)
        #expect(Set(specs.map { "\($0.category.rawValue)/\($0.name)" }).count == specs.count)
        for s in specs {
            #expect(s.assembly.validate() == nil, "\(s.name)")
            for l in s.layers { #expect(MaterialLibrary.named(l.material) != nil, "\(s.name): \(l.material)") }
        }
    }

    @Test func doorAndWindowSizesPerSystem() {
        let im = Self.imperial.0, me = Self.metric.0
        func width(_ m: BIMModel, _ c: ArcusDomain.Category, _ family: String, _ type: String) -> Double? {
            m.types(for: c).first { $0.name == type && $0.typeData?.familyName == family }?.typeData?.params[Parameters.familyParamID("Width")]?.doubleValue
        }
        #expect(width(im, .doors, "Door - Single Flush", "36\" x 80\"").map { abs($0 - 36 * inch) < 1e-9 } == true)
        #expect(width(im, .doors, "Door - Overhead Sectional", "16'-0\" x 7'-0\"").map { abs($0 - 192 * inch) < 1e-9 } == true)
        #expect(width(im, .doors, "Door - Overhead Sectional", "9'-0\" x 7'-0\"") != nil)
        #expect(width(im, .windows, "Window - Double Hung", "36\" x 62\"") != nil)
        #expect(width(me, .doors, "Door - Single Flush", "750 x 2100") == 0.75)
        #expect(width(me, .doors, "Door - Single Flush", "900 x 2100") == 0.9)
        #expect(width(me, .doors, "Door - Overhead Sectional", "2400 x 2100") == 2.4)
        #expect(width(me, .windows, "Window - Sliding 3-Track", "1800 x 1200") == 1.8)
        #expect(width(me, .windows, "Window - Ventilator", "600 x 450") == 0.6)
        // Fire ratings reach the schedule parameter.
        let fr = im.types(for: .doors).first { $0.name == "36\" x 84\" (90 min)" }
        #expect(fr?.typeData?.params[ParameterID("type.fireRating")] == .text("90 min"))
        // Door and window types carry their materials.
        let sf = me.types(for: .doors).first { $0.typeData?.familyName == "Door - Storefront Single" }!
        #expect(me[sf.typeData?.params[Parameters.familyParamID("Glass Material")]?.refValue]?.name == "Glass, Tempered")
    }

    @Test(arguments: [UnitSystem.imperial, .metric])
    func everyLibraryFamilyTypeEvaluates(_ system: UnitSystem) {
        let units: UnitsSettings = system == .imperial ? .imperial : .metric
        for e in OpeningLibrary.doors(system) + OpeningLibrary.windows(system) + ColumnLibrary.families(system) {
            let f = e.family
            #expect(!f.types.isEmpty, "\(f.name)")
            #expect(Set(f.types.map(\.name)).count == f.types.count, "\(f.name) type names are unique")
            for t in f.types {
                let ev = FamilyEvaluator.evaluate(f, typeName: t.name, units: units)
                #expect(ev.errors.isEmpty, "\(f.name): \(t.name): \(ev.errors)")
                #expect(!ev.solids.filter { !$0.isVoid }.isEmpty, "\(f.name): \(t.name)")
                if f.template.isHostedInWall {
                    let o = ev.opening
                    #expect(o != nil, "\(f.name)")
                    if let o, let w = t.values["Width"]?.doubleValue { #expect(o.xMax - o.xMin >= w - 1e-9, "\(f.name): \(t.name)") }
                }
            }
        }
    }

    @Test func templateKeysStillResolveInImperialProjects() {
        let (m, ids) = Self.imperial
        #expect(m[ids.wallTypes["Generic - 200mm"]]?.name == "Generic - 8\"")
        #expect(m[ids.wallTypes["Exterior - Brick on CMU"]]?.name == "Exterior - Brick on CMU")
        #expect(m[ids.floorTypes["Screed on Concrete 250mm"]]?.name == "Concrete Slab 8\" + 2\" Topping")
        #expect(m[ids.ceilingTypes["Acoustic Tile 600 x 600"]]?.name == "2'x2' ACT System")
        #expect(m[ids.familyTypes["Door - Single Flush: 900 x 2100"]]?.name == "36\" x 84\"")
        #expect(m[ids.familyTypes["Window - Casement: 2400 x 2100 Glazed Wall"]]?.name == "96\" x 84\" Glazed Wall")
        #expect(m[ids.systemTypes["Concrete Column 400 x 400"]]?.name == "Concrete Column 16\" x 16\"")
        #expect(m[ids.systemTypes["Stair"]]?.name == "Monolithic - 7\" max riser")
        #expect(m[ids.systemTypes["Text 2.5mm Arial"]]?.name == "3/32\" Arial")
        // Starter families carry only imperial types in imperial projects.
        let single = m.family(named: "Door - Single Flush")!.family!
        #expect(single.types.allSatisfy { $0.name.contains("\"") })
        #expect(m.sheets.allSatisfy { $0.sheet?.paper == .archD })
        #expect(m[ids.planViews[ids.levels[0]]]?.view?.scale == 96)
    }

    @Test func loadingStandardTypesRespectsTheProjectUnits() throws {
        var (m, _) = Fx.template()
        // A metric project already has everything.
        try Fx.commit(&m) { tx in #expect(StandardContent.loadMissing(into: tx) == 0) }
        // Switch the project to imperial: the imperial types are added, the metric ones kept.
        let metricWalls = m.types(for: .walls).count
        let info = m.projectInfoElement!.id
        try Fx.commit(&m) { tx in
            tx.update(info) { $0.projectInfo?.units = .imperial }
        }
        var added = 0
        try Fx.commit(&m) { tx in added = StandardContent.loadMissing(into: tx) }
        #expect(added > 150)
        #expect(m.types(for: .walls).count > metricWalls)
        #expect(m.types(for: .doors).contains { $0.name == "36\" x 80\"" && $0.typeData?.familyName == "Door - Single Flush" })
        #expect(m.types(for: .doors).contains { $0.name == "900 x 2100" && $0.typeData?.familyName == "Door - Single Flush" })
        #expect(m.family(named: "Steel Column - Wide Flange") != nil)
        try Fx.commit(&m) { tx in #expect(StandardContent.loadMissing(into: tx) == 0) }
        #expect(ModelHealth.check(m).isEmpty)
    }

    /// Places the first type of every door and window family in walls and checks the 3D parts, openings and plan.
    @Test(arguments: [UnitSystem.imperial, .metric])
    func everyDoorAndWindowFamilyPlacesAndDraws(_ system: UnitSystem) throws {
        let (m0, ids) = system == .imperial ? Self.imperial : Self.metric
        var m = Fx.isolated(m0)
        let families = (OpeningLibrary.doors(system) + OpeningLibrary.windows(system)).map(\.family)
        var placed: [(ElementID, String, Double)] = []
        try Fx.commit(&m) { tx in
            for (k, f) in families.enumerated() {
                let y = Double(k) * 4
                let wall = Fx.wall(tx, ids, Vec2(0, y), Vec2(9, y))
                let key = "\(f.name): \(f.types[0].name)"
                let type = try #require(ids.familyTypes[key], "\(key)")
                let sill = f.types[0].values["Default Sill Height"]?.doubleValue ?? 0
                let cat: ArcusDomain.Category = f.template == .door ? .doors : .windows
                placed.append((tx.create(cat, data: .insert(InsertData(location: Vec2(4.5, y), sillHeight: sill)), typeID: type, levelID: ids.levels[0], hostID: wall), key, sill))
            }
        }
        for (id, key, _) in placed {
            let e = try #require(m[id])
            #expect(!InsertGeometry.meshParts(e, m).isEmpty, "\(key)")
            #expect(InsertGeometry.openingSize(e, m) != nil, "\(key)")
            #expect(!InsertGeometry.planSymbols(e, m).isEmpty, "\(key)")
        }
        let plan = try #require(m[ids.planViews[ids.levels[0]]])
        let g = ViewGraphicsBuilder(model: m, view: plan).build()
        // Inserts whose sill is above the plan's cut plane (high awnings, ventilators) are not cut and not drawn.
        for (id, key, sill) in placed where sill < 1.2 { #expect(g.items.contains { $0.elementID == id }, "\(key)") }
    }

    @Test func imperialNameFormatting() {
        #expect(OpeningLibrary.inchText(36) == "36\"")
        #expect(OpeningLibrary.inchText(4.875) == "4 7/8\"")
        #expect(OpeningLibrary.inchText(0.625) == "5/8\"")
        #expect(OpeningLibrary.feetText(108) == "9'-0\"")
        #expect(OpeningLibrary.feetText(90) == "7'-6\"")
    }
}

@Suite("Column profiles")
struct ColumnProfileTests {
    static func family(_ system: UnitSystem, _ name: String) -> FamilyDefinition {
        ColumnLibrary.families(system).map(\.family).first { $0.name == name }!
    }
    static func section(_ system: UnitSystem, _ family: String, _ type: String) -> EvaluatedFamily.Solid {
        let ev = FamilyEvaluator.evaluate(Self.family(system, family), typeName: type, units: system == .imperial ? .imperial : .metric)
        #expect(ev.errors.isEmpty)
        let solids = ev.solids.filter { !$0.isVoid }
        #expect(solids.count == 1)
        return solids[0]
    }

    @Test func wideFlangeIsAnIShape() {
        let s = Self.section(.imperial, "Steel Column - Wide Flange", "W10x49")
        let d = 9.98 * inch, bf = 10.0 * inch, tw = 0.34 * inch, tf = 0.56 * inch
        #expect(s.profile.outer.count == 12)
        #expect(abs(s.profile.area - (2 * bf * tf + (d - 2 * tf) * tw)) < 1e-10)
        // Published area 14.4 in² includes root fillets.
        #expect(abs(s.profile.area / (14.4 * inch * inch) - 1) < 0.03)
        let b = s.profile.bounds
        #expect(abs(b.width - bf) < 1e-9 && abs(b.height - d) < 1e-9)
        #expect(abs(s.zMax - s.zMin - 10 * 12 * inch) < 1e-9)
    }

    @Test(arguments: [("W14x90", 26.5), ("W12x65", 19.1), ("W8x31", 9.13), ("W14x48", 14.1)])
    func wideFlangeAreasMatchPublishedValues(_ name: String, _ area: Double) {
        let s = Self.section(.imperial, "Steel Column - Wide Flange", name)
        #expect(abs(s.profile.area / (area * inch * inch) - 1) < 0.04, "\(name)")
    }

    @Test(arguments: [("HEB 200", 78.1), ("HEA 240", 76.8), ("IPE 300", 53.8), ("ISMB 300", 56.26), ("ISHB 200", 47.54)])
    func metricIAndHSectionAreas(_ name: String, _ areaCm2: Double) {
        let s = Self.section(.metric, "Steel Column - I Section", name)
        #expect(abs(s.profile.area / (areaCm2 * 1e-4) - 1) < 0.05, "\(name)")
    }

    @Test func hollowSectionsHaveHoles() {
        let hss = Self.section(.imperial, "Steel Column - HSS Rectangular", "HSS8x8x1/2")
        #expect(hss.profile.holes.count == 1)
        let t = 0.465 * inch, w = 8 * inch
        #expect(abs(hss.profile.area - (w * w - (w - 2 * t) * (w - 2 * t))) < 1e-9)
        #expect(abs(hss.profile.bounds.width - w) < 1e-9)
        #expect(hss.profile.holes.first.map { abs($0.bounds.width - (w - 2 * t)) < 1e-9 } == true)
        #expect(abs(hss.zMax - hss.zMin - 10 * 12 * inch) < 1e-9, "the void cuts the full height")

        let rhs = Self.section(.metric, "Steel Column - Hollow Rectangular", "RHS 300x200x10")
        #expect(abs(rhs.profile.bounds.width - 0.2) < 1e-9 && abs(rhs.profile.bounds.height - 0.3) < 1e-9)
        #expect(abs(rhs.profile.area - (0.2 * 0.3 - 0.18 * 0.28)) < 1e-9)

        let pipe = Self.section(.imperial, "Steel Column - Pipe", "Pipe 6 Std.")
        #expect(pipe.profile.holes.count == 1)
        let ro = 6.625 / 2 * inch, ri = ro - 0.261 * inch
        #expect(abs(pipe.profile.area / (Double.pi * (ro * ro - ri * ri)) - 1) < 0.05)
        let chs = Self.section(.metric, "Steel Column - Hollow Circular", "CHS 219.1x10")
        #expect(abs(chs.profile.bounds.width - 0.2191) < 0.002)
    }

    @Test func roundOctagonalAndConcreteSections() {
        let r = Self.section(.metric, "Concrete Column - Round", "450 Diameter")
        #expect(abs(r.profile.area / (Double.pi * 0.225 * 0.225) - 1) < 0.02)
        let o = Self.section(.metric, "Column - Octagonal", "600 Across Flats")
        #expect(o.profile.outer.count == 8)
        #expect(abs(o.profile.area - 2 * (2.0.squareRoot() - 1) * 0.36) < 1e-6)
        #expect(abs(o.profile.bounds.width - 0.6) < 1e-9)
        let c = Self.section(.imperial, "Concrete Column - Rectangular", "24\" x 36\"")
        #expect(abs(c.profile.bounds.width - 24 * inch) < 1e-9 && abs(c.profile.bounds.height - 36 * inch) < 1e-9)
        let sawn = Self.section(.imperial, "Wood Column - Sawn", "6x6")
        #expect(abs(sawn.profile.bounds.width - 5.5 * inch) < 1e-9)
        let pil = Self.section(.metric, "Column - Pilaster", "450 x 230")
        #expect(abs(pil.profile.bounds.min.y) < 1e-9 && abs(pil.profile.bounds.max.y - 0.23) < 1e-9)
    }

    @Test func classicalColumnHasBaseShaftAndCapital() {
        let f = Self.family(.imperial, "Column - Round with Base and Capital")
        let ev = FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial)
        #expect(ev.errors.isEmpty)
        #expect(ev.solids.count == 5)
        #expect(abs(ev.bounds.max.z - 10 * 12 * inch) < 1e-6 && abs(ev.bounds.min.z) < 1e-9)
        #expect(ev.solids.filter(\.visibleInPlan).map(\.name) == ["Shaft"])
    }

    @Test func placedHollowColumnShowsItsHoleInPlanAnd3D() throws {
        var (m, ids) = ProjectTemplates.make(.architectural, units: .imperial)
        m = Fx.isolated(m)
        let hss = ids.familyTypes["Steel Column - HSS Rectangular: HSS8x8x1/2"]
        let wf = ids.familyTypes["Steel Column - Wide Flange: W12x53"]
        #expect(hss != nil && wf != nil)
        var a: ElementID?, b: ElementID?
        try Fx.commit(&m) { tx in
            a = tx.create(.structuralColumns, data: .column(ColumnData(location: Vec2(2, 2), topLevelID: ids.levels[1])), typeID: hss, levelID: ids.levels[0])
            b = tx.create(.structuralColumns, data: .column(ColumnData(location: Vec2(6, 2), rotation: .pi / 2, topLevelID: ids.levels[1])), typeID: wf, levelID: ids.levels[0])
        }
        let tube = m[a]!, beam = m[b]!
        #expect(ComponentGeometry.planOutline(tube, m).count == 1)
        let loops = ComponentGeometry.planLoops(tube, m)
        #expect(loops.count == 2)
        #expect(abs(loops[0].area - (8 * inch) * (8 * inch)) < 1e-9)
        let parts = ComponentGeometry.meshParts(tube, m)
        #expect(parts.count == 1 && !parts[0].mesh.isEmpty)
        let bounds = parts[0].mesh.bounds
        #expect(abs(bounds.max.z - bounds.min.z - (m.levels[1].level!.elevation - m.levels[0].level!.elevation)) < 1e-6)
        #expect(m[m.typeParam(tube, ParameterID("type.material"))?.refValue]?.name == "Steel, Structural")
        let wfLoops = ComponentGeometry.planLoops(beam, m)
        #expect(wfLoops.count == 1 && wfLoops[0].count == 12)
        // Rotated 90°: the depth now runs along X.
        #expect(abs(wfLoops[0].bounds.width - 12.1 * inch) < 1e-6)
    }
}
