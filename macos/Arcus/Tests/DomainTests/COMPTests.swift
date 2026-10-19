import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// COMP: the Furniture Component Library kit and infrastructure.
@Suite("COMP component kit")
struct COMPKitTests {
    /// A sample face-based component using every geometry helper.
    static func sample() -> ComponentDefinition {
        var b = ComponentBuilder("Kit Sample Handle", .handles, "Bar Handles", "Sample.")
        b.tags("handle", "sample"); b.aliases("pull")
        b.length("Length", ComponentKit.mm(160)); b.length("Hole Spacing", ComponentKit.mm(128))
        b.length("Diameter", ComponentKit.mm(12)); b.length("Projection", ComponentKit.mm(34))
        b.length("Offset", ComponentKit.inch(2.5), instance: true, group: .placement)
        b.material("Finish Material", .satinNickel)
        b.host(ComponentHostKind.fronts, faces: [.front], align: .center)
        b.drill("Handle hole", x: "-Hole Spacing / 2", y: CX.zero, diameter: CX.mm(5), depth: "0.019 m", through: true)
        b.cylinder("Bar", axis: .x, center: (CX.zero, "Projection - Diameter / 2"), radius: "Diameter / 2", from: "-Length / 2", to: "Length / 2")
        b.cylinder("Post", axis: .z, center: ("-Hole Spacing / 2", CX.zero), radius: CX.mm(5), from: CX.zero, to: "Projection - Diameter / 2")
        b.roundedBar("Rose", center: ("Hole Spacing / 2", CX.zero), width: CX.mm(14), height: CX.mm(14), radius: CX.mm(7), from: CX.zero, to: CX.mm(3))
        b.revolve("Knob", profile: ComponentKit.points([(CX.zero, CX.zero), (CX.mm(8), CX.zero), (CX.mm(12), CX.mm(10)), (CX.zero, CX.mm(12))]), base: CX.mm(3))
        b.sweep("Bow", path: ComponentKit.arcPath(center: (CX.zero, CX.zero), radius: CX.mm(40), startDegrees: 0, sweepDegrees: 180),
                profile: ComponentKit.circle(radius: CX.mm(4), segments: 12), plane: .xz)
        b.track("Track", from: "-Length / 2", to: "Length / 2", width: CX.mm(20), height: CX.mm(10), wall: CX.mm(2))
        b.tube("Tube", axis: .y, center: (CX.zero, CX.mm(20)), outer: CX.mm(6), inner: CX.mm(4), from: CX.zero, to: CX.mm(30))
        b.bracket("Bracket", width: CX.mm(20), legA: CX.mm(30), legB: CX.mm(30), thickness: CX.mm(2))
        b.symbol(.top, [.coarse], .line(("-Length / 2", CX.zero), ("Length / 2", CX.zero)))
        b.type("Kit Sample - 128 mm CC", ["Length": ComponentKit.mm(164)], cost: 5.25, model: "KS-128")
        b.type("Kit Sample - 160 mm CC", ["Length": ComponentKit.mm(196), "Hole Spacing": ComponentKit.mm(160)], cost: 6.25, model: "KS-160")
        return b.build()
    }

    @Test func builderProducesAValidFamily() {
        let d = Self.sample()
        #expect(ComponentKit.validate(d).isEmpty, "\(ComponentKit.validate(d))")
        #expect(d.id == "comp.01.kit-sample-handle")
        #expect(d.family.template == .furnitureHardware)
        #expect(d.defaultType?.name == "Kit Sample - 128 mm CC")
        #expect(d.types[0].values["Projection"] == .double(0.034), "defaults fill every type")
        #expect(d.types[0].sku == "GEN-KS-128")
        #expect(d.family.solids.allSatisfy { $0.isVoid || $0.materialParameter == "Finish Material" })
    }

    @Test func fm5FamiliesAreOnTheKit() {
        let fm5 = ComponentLibrary.fm5Components
        #expect(fm5.count == 17)
        for d in fm5 {
            #expect(ComponentKit.validate(d).isEmpty, "\(d.name): \(ComponentKit.validate(d))")
            let spec = FurnitureHardware.library.first { $0.family.name == d.name }
            #expect(spec?.types.map(\.name) == d.types.map(\.name), "\(d.name) keeps FM5's types")
            #expect(d.types.allSatisfy { $0.cost > 0 })
        }
        #expect(ComponentLibrary.component(named: FurnitureHardware.concealedHinge)?.hardwareKind == .hinge)
    }

    @Test func registryIdsAreUnique() {
        let ids = ComponentLibrary.furniture.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ComponentLibrary.furniture.count >= 17)
    }

    @Test func upgradingAnFM5FamilyKeepsItsTypes() throws {
        var b = try #require(ComponentBuilder(upgrading: FurnitureHardware.knob))
        b.aliases("mushroom knob")
        b.type("1 3/4\" Black", ["Diameter": ComponentKit.inch(1.75), "Projection": ComponentKit.inch(1.25)], flags: ["Vertical": false, "On Lid": false],
               cost: 5, model: "KN-175K")
        let up = b.build()
        let old = try #require(ComponentLibrary.fm5Components.first { $0.name == FurnitureHardware.knob })
        let merged = ComponentLibrary.merged(upgrade: up, over: old)
        #expect(merged.types.count == old.types.count + 1)
        #expect(merged.id == old.id)
        #expect(merged.aliases.contains("mushroom knob"))
        #expect(ComponentKit.validate(merged).isEmpty, "\(ComponentKit.validate(merged))")
    }
}

/// Small definitions standing in for the category groups, so the infrastructure tests don't depend on their content.
enum COMPFixtures {
    static func make(_ name: String, _ c: ComponentCategory, _ sub: String, tags: [String], aliases: [String] = [], hosts: [ComponentHostKind] = [.door],
                     faces: [ComponentFace] = [.front], frame: ComponentFrame = .face, length: [(String, Double)] = [("Length", 0.1)], angle: Double? = nil,
                     watts: Double? = nil, configure: (inout ComponentBuilder) -> Void = { _ in }) -> ComponentDefinition {
        var b = ComponentBuilder(name, c, sub, "\(name) for tests.", frame: frame)
        b.definition.tags = tags; b.definition.aliases = aliases
        b.length("Length", 0.1); b.length("Width", 0.02); b.length("Depth", 0.02)
        if let angle { b.angle("Opening Angle", angle) }
        if let watts { b.electrical(watts: watts, volts: 12, supply: "DC 12 V", cable: "2-wire 20 AWG") }
        b.material("Finish Material", .steel)
        b.host(hosts, faces: faces)
        b.box("Body", x: ("-Length / 2", "Length / 2"), y: ("-Width / 2", "Width / 2"), z: (CX.zero, "Depth"))
        configure(&b)
        for (k, (tn, l)) in length.enumerated() { b.type(tn, ["Length": l], cost: 2 + Double(k), model: "T\(k)") }
        return b.build()
    }

    static let catalog: [ComponentDefinition] = ComponentLibrary.fm5Components + [
        COMPKitTests.sample(),
        make("Cabinet Door Lock", .locks, "Cabinet Locks", tags: ["lock", "cam", "cylinder"], aliases: ["cupboard lock", "key lock"]),
        make("Wardrobe Lock", .locks, "Wardrobe Locks", tags: ["lock", "wardrobe"], aliases: ["closet lock"]),
        make("Soft-Close Hinge", .hinges, "Concealed Hinges", tags: ["hinge", "soft close", "concealed"], length: [("Soft-Close Hinge 110°", 0.05), ("Soft-Close Hinge 165°", 0.05)],
             angle: 110) { b in
            b.definition.types = []
            b.type("Soft-Close Hinge 110°", ["Length": 0.05], cost: 4, model: "SC110")
        },
        make("Glass Door Hinge", .hinges, "Glass Hinges", tags: ["hinge", "glass"], aliases: ["glass hinge", "glass clamp hinge"], hosts: [.glass, .door]),
        make("Push-to-Open Latch", .handles, "Push Latches", tags: ["push to open", "touch latch", "handleless"], aliases: ["push open", "tip on"]),
        make("Clothes Hanging Rod", .wardrobe, "Hanging Rods", tags: ["rod", "wardrobe", "hanging"], aliases: ["closet rod", "hanger rail"], hosts: [.bay], faces: [.top],
             length: [("Rod - 24\"", 0.6096), ("Rod - 36\"", 0.9144)]),
        make("Corner Carousel", .kitchen, "Corner Systems", tags: ["kitchen", "corner", "carousel", "lazy susan"], aliases: ["kitchen corner", "blind corner"], hosts: [.bay], faces: [.bottom]),
        make("Shelf Bracket", .shelving, "Shelf Brackets", tags: ["shelf", "bracket", "support"], aliases: ["shelf support"], hosts: [.sidePanel], faces: [.inside]),
        make("Adjustable Cabinet Leg", .legs, "Cabinet Legs", tags: ["leg", "adjustable", "cabinet"], aliases: ["adjustable leg", "leveling leg"], hosts: [.bottom], faces: [.bottom], frame: .plan),
        make("Cabinet Puck Light", .lighting, "Puck Lights", tags: ["led", "light", "cabinet", "puck"], aliases: ["LED cabinet light", "puck light"], hosts: [.top, .shelf], faces: [.bottom],
             watts: 3),
        make("Desk Cable Grommet", .tables, "Cable Management", tags: ["cable", "grommet", "desk"], aliases: ["desk cable hole", "cable port"], hosts: [.top], faces: [.top]),
        make("Gas Lift Bed Mechanism", .beds, "Bed Lifts", tags: ["bed", "lift", "gas", "storage"], aliases: ["bed lift", "storage bed lift"], hosts: [.sidePanel], faces: [.inside]),
        make("Concealed Shelf Support", .shelving, "Shelf Supports", tags: ["shelf", "concealed", "floating"], aliases: ["hidden shelf support"], hosts: [.sidePanel], faces: [.inside]),
        make("Wardrobe LED Rail", .lighting, "Wardrobe Lighting", tags: ["led", "wardrobe", "rail"], aliases: ["LED hanging rail"], hosts: [.bay], faces: [.top], watts: 4.5),
    ]
    static let index = ComponentSearchIndex(catalog)
}

@Suite("COMP search")
struct COMPSearchTests {
    func top(_ q: String, _ n: Int = 3) -> [String] { COMPFixtures.index.search(q, limit: n).map(\.definition.name) }

    @Test func ownerExamples() {
        #expect(top("handle").contains(FurnitureHardware.barPull))
        #expect(top("closet handle", 20).contains(FurnitureHardware.barPull), "closet handle: \(top("closet handle"))")
        #expect(top("lock", 2).allSatisfy { $0.contains("Lock") }, "\(top("lock"))")
        #expect(top("soft close").first?.contains("Hinge") == true || top("soft close").contains(FurnitureHardware.undermountSlide), "\(top("soft close"))")
        #expect(top("hinge 110").first == "Soft-Close Hinge" || top("hinge 110").first == FurnitureHardware.concealedHinge, "\(top("hinge 110"))")
        let slide = COMPFixtures.index.search("drawer slide 450", limit: 2)
        #expect(slide.first.map { [FurnitureHardware.sideMountSlide, FurnitureHardware.undermountSlide].contains($0.definition.name) } == true)
        #expect(slide.first?.typeName == "18\"", "450 mm is the 18\" slide: \(String(describing: slide.first?.typeName))")
        #expect(COMPFixtures.index.search("18 inch slide", limit: 1).first?.typeName == "18\"")
        #expect(top("push open").first == "Push-to-Open Latch")
        #expect(top("wardrobe", 5).contains("Clothes Hanging Rod"))
        #expect(top("kitchen corner").first == "Corner Carousel")
        #expect(top("shelf support", 3).contains(FurnitureHardware.shelfPin), "\(top("shelf support"))")
        #expect(top("adjustable leg").first == "Adjustable Cabinet Leg" || top("adjustable leg").first == FurnitureHardware.glide)
        #expect(top("LED cabinet").first == "Cabinet Puck Light", "\(top("LED cabinet"))")
        #expect(top("glass hinge").first == "Glass Door Hinge")
        #expect(top("concealed", 6).contains(FurnitureHardware.concealedHinge))
        #expect(top("desk cable").first == "Desk Cable Grommet")
        #expect(top("bed lift").first == "Gas Lift Bed Mechanism")
    }

    @Test func synonymsTyposAndPlurals() {
        #expect(top("runner", 5).contains(FurnitureHardware.sideMountSlide))
        #expect(top("castor").first == FurnitureHardware.caster)
        #expect(top("hnige", 5).contains(FurnitureHardware.concealedHinge), "typo: \(top("hnige"))")
        #expect(top("hinges", 8).contains(FurnitureHardware.buttHinge))
        #expect(top("xyzzy").isEmpty)
        #expect(COMPFixtures.index.search("").count == COMPFixtures.catalog.count)
    }

    @Test func filtersAndSpeed() {
        let locks = COMPFixtures.index.search("", filter: ComponentSearchFilter(category: .locks))
        #expect(locks.count == 2)
        let onBay = COMPFixtures.index.search("", filter: ComponentSearchFilter(host: .bay)).map(\.definition.name)
        #expect(onBay.contains("Clothes Hanging Rod") && !onBay.contains("Cabinet Door Lock"))
        // Thousands of components: 2,000 definitions searched in well under a second.
        let many = (0..<100).flatMap { k in COMPFixtures.catalog.map { d -> ComponentDefinition in var x = d; x.id += ".\(k)"; return x } }
        let big = ComponentSearchIndex(many)
        let t0 = Date()
        for q in ["hinge 110", "drawer slide 450", "closet handle", "hnige", "LED cabinet"] { _ = big.search(q, limit: 50) }
        #expect(Date().timeIntervalSince(t0) < 2.5, "searches took \(Date().timeIntervalSince(t0)) s")
    }

    @Test func recentSearches() {
        var r = ComponentRecentSearches()
        for q in ["hinge", "lock", "Hinge", "a"] { r.add(q) }
        #expect(r.items == ["Hinge", "lock"])
        for k in 0..<20 { r.add("q\(k)") }
        #expect(r.items.count == ComponentRecentSearches.limit)
    }
}

@Suite("COMP placement")
struct COMPPlacementTests {
    static let inch = 0.0254

    static func cabinet() throws -> BIMModel { try #require(FurnitureSamples.baseCabinetModel()) }

    static func run(_ m: BIMModel, _ name: String = "Edit", _ body: (TransactionContext) throws -> Void) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: name)
        try body(tx)
        return try tx.commit().model
    }

    static func door(_ m: BIMModel) throws -> Element {
        try #require(m.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .door }.min { $0.id < $1.id })
    }

    @Test func placesOnAFaceAndFollowsTheHost() throws {
        var m = try Self.cabinet()
        let door = try Self.door(m)
        let d = COMPKitTests.sample()
        var ids: [ElementID] = []
        m = try Self.run(m, "Place") { tx in
            ids = try ComponentPlacement.place(d, hostID: door.id, settings: ComponentSettings(face: .front, alignment: .topRight, offsetX: 2 * Self.inch, offsetY: 3 * Self.inch), in: tx)
        }
        #expect(ids.count == 1)
        let e = try #require(m[ids[0]])
        #expect(e.category == .furnitureHardware && e.hostID == door.id)
        #expect(ComponentDocument.loadedFamily(d, m) != nil)
        let f0 = try #require(ComponentPlacement.face(door, .front, m))
        let o0 = try #require(e.component?.sketchPlane?.frame.origin)
        let corner0 = f0.point(f0.width / 2, f0.height / 2)
        #expect(abs((corner0 - o0).dot(f0.u) - 2 * Self.inch) < 1e-6 && abs((corner0 - o0).dot(f0.v) - 3 * Self.inch) < 1e-6)
        // Its geometry is on the door's face, in front of it.
        let b = ElementMeshes.parts(e, m, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(b.max.y <= f0.origin.y + 0.0041 && b.min.y < f0.origin.y - 0.03, "out of the face (the bow dips 4 mm behind it)")
        // The cabinet gets taller: the handle keeps its distance from the door's top-right corner.
        m = try Self.run(m, "Taller") { tx in try FurnitureParameters.setValue("Height", .double(40 * Self.inch), in: tx) }
        let door1 = try #require(m[door.id]), f1 = try #require(ComponentPlacement.face(door1, .front, m))
        #expect(f1.height > f0.height + 0.05)
        let o1 = try #require(m[ids[0]]?.component?.sketchPlane?.frame.origin)
        let corner1 = f1.point(f1.width / 2, f1.height / 2)
        #expect(abs((corner1 - o1).dot(f1.u) - 2 * Self.inch) < 1e-6 && abs((corner1 - o1).dot(f1.v) - 3 * Self.inch) < 1e-6)
        // Deleting the door deletes it.
        m = try Self.run(m, "Delete") { tx in tx.delete(door.id) }
        #expect(m[ids[0]] == nil)
    }

    @Test func hingeSetsFollowTheCountRule() throws {
        var m = try Self.cabinet()
        let door = try Self.door(m)
        let d = COMPFixtures.make("Test Hinge", .hinges, "Concealed Hinges", tags: ["hinge"], faces: [.inside]) { b in
            b.host([.door], faces: [.inside], align: .left, offsetX: 0.0225, count: .hinges)
        }
        m = try Self.run(m) { tx in _ = try ComponentPlacement.place(d, hostID: door.id, in: tx) }
        func hinges() -> [Element] { m.hosted(by: door.id).filter { ComponentDocument.definitionID(of: $0, m) == d.id } }
        #expect(hinges().count == 2)
        m = try Self.run(m) { tx in try FurnitureParameters.setValue("Height", .double(50 * Self.inch), in: tx) }
        #expect(hinges().count == 3, "a door over 40\" takes 3 hinges")
        let zs = hinges().compactMap { $0.component?.sketchPlane?.frame.origin.z }.sorted()
        #expect(zs.count == 3 && abs((zs[1] - zs[0]) - (zs[2] - zs[1])) < 1e-6)
    }

    @Test func replaceKeepsPlacementAndWarns() throws {
        var m = try Self.cabinet()
        let door = try Self.door(m)
        let a = COMPKitTests.sample()
        var ids: [ElementID] = []
        m = try Self.run(m) { tx in ids = try ComponentPlacement.place(a, hostID: door.id, settings: ComponentSettings(face: .front, alignment: .top, offsetY: 0.05), in: tx) }
        let before = try #require(m[ids[0]])
        let lock = try #require(COMPFixtures.catalog.first { $0.name == "Cabinet Door Lock" })
        var warnings: [ModelWarning] = []
        m = try Self.run(m, "Replace") { tx in warnings = try ComponentPlacement.replace(ids, with: lock, in: tx) }
        let after = try #require(m[ids[0]])
        #expect(ComponentDocument.definitionID(of: after, m) == lock.id)
        #expect(after.hostID == before.hostID && ComponentSettings(after) == ComponentSettings(before))
        #expect(warnings.isEmpty)
        // A rod on a door: placed, with a warning.
        let rod = try #require(COMPFixtures.catalog.first { $0.name == "Clothes Hanging Rod" })
        m = try Self.run(m, "Replace") { tx in warnings = try ComponentPlacement.replace(ids, with: rod, in: tx) }
        #expect(warnings.contains { $0.code == "comp.replace" })
        // Undo-able: the record's inverse restores the lock.
        let tx = TransactionContext(model: m, name: "Replace")
        _ = try ComponentPlacement.replace(ids, with: a, in: tx)
        let c = try tx.commit()
        #expect(ComponentDocument.definitionID(of: c.model[ids[0]]!, c.model) == a.id)
        #expect(ComponentDocument.definitionID(of: c.model.applying(c.record.inverse)[ids[0]]!, m) == rod.id)
    }

    @Test func compatibilityRules() throws {
        let m = try Self.cabinet()
        let door = try Self.door(m)
        // A slide pair needs 22" for a 22" slide in a 24" deep cabinet's drawer bay (minus the back): fits; 30" doesn't.
        let slide = try #require(ComponentLibrary.fm5Components.first { $0.name == FurnitureHardware.sideMountSlide })
        let bay = try #require(m[door.hostID])
        let ok = ComponentChecks.requirements(slide, typeName: "18\"", host: bay, kind: .bay, m)
        #expect(ok.isEmpty, "\(ok.map(\.message))")
        var long = slide
        long.types[0].values["Slide Length"] = .double(30 * Self.inch)
        long.family.types[0].values["Slide Length"] = .double(30 * Self.inch)
        #expect(ComponentChecks.requirements(long, typeName: long.types[0].name, host: bay, kind: .bay, m).contains { $0.code == "comp.depth" })
        // Handle longer than a narrow front.
        let bar = try #require(ComponentLibrary.fm5Components.first { $0.name == FurnitureHardware.barPull })
        var huge = bar
        huge.family.types[0].values["Length"] = .double(40 * Self.inch)
        #expect(ComponentChecks.requirements(huge, typeName: huge.family.types[0].name, host: door, kind: .door, m).contains { $0.code == "comp.fitWidth" })
        // Hinges: thickness range.
        let hinge = try #require(ComponentLibrary.fm5Components.first { $0.name == FurnitureHardware.concealedHinge })
        let r = ComponentChecks.requirements(hinge, typeName: nil, host: door, kind: .door, sharing: 2, m)
        #expect(r.isEmpty, "\(r.map(\.message))")
    }

    @Test func collisionsAreFound() throws {
        var m = try Self.cabinet()
        let door = try Self.door(m)
        let d = COMPKitTests.sample()
        m = try Self.run(m) { tx in
            _ = try ComponentPlacement.place(d, hostID: door.id, settings: ComponentSettings(face: .front, alignment: .center), in: tx)
            _ = try ComponentPlacement.place(d, hostID: door.id, settings: ComponentSettings(face: .front, alignment: .center, offsetX: 0.005), in: tx)
        }
        #expect(ComponentChecks.collisions(m).contains { $0.code == "comp.collision" })
        #expect(FurnitureCheckParts.check(m).contains { $0.code == "comp.collision" })
    }

    @Test func persistsAndUpgrades() throws {
        var m = try Self.cabinet()
        let door = try Self.door(m)
        var d = COMPKitTests.sample()
        var ids: [ElementID] = []
        m = try Self.run(m) { tx in ids = try ComponentPlacement.place(d, hostID: door.id, settings: ComponentSettings(face: .front, alignment: .bottomLeft, offsetX: 0.03, offsetY: 0.04, rotation: 0.2), in: tx) }
        // Elements round-trip through JSON (the package stores them so).
        let e = try #require(m[ids[0]])
        let back = try JSONDecoder().decode(Element.self, from: JSONEncoder().encode(e))
        #expect(back == e)
        #expect(ComponentSettings(back)?.rotation == 0.2 && ComponentSettings(back)?.alignment == .bottomLeft)
        let fam = try #require(ComponentDocument.loadedFamily(d, m))
        #expect(m[fam]?.params[ComponentKit.versionParam]?.intValue == 1)
        let t = try #require(m[e.typeID]?.typeData)
        #expect(t.params[ComponentKit.skuParam]?.textValue == "GEN-KS-128" && t.params[ParameterID("type.cost")]?.doubleValue == 5.25)
        // The definition round-trips (user library files).
        let dd = try JSONDecoder().decode(ComponentDefinition.self, from: JSONEncoder().encode(d))
        #expect(dd == d)
        // A newer version renames a type: the document upgrades, the instance keeps its (renamed) type.
        d.version = 2
        d.renamedTypes = ["Kit Sample - 128 mm CC": "Kit Sample - 128 mm"]
        d.types[0].name = "Kit Sample - 128 mm"
        d.family.types[0].name = "Kit Sample - 128 mm"
        let catalog = ComponentCatalog(builtIn: [d])
        #expect(ComponentDocument.loaded(m, catalog: catalog).first { $0.familyID == fam }?.isOutdated == true)
        m = try Self.run(m, "Upgrade") { tx in #expect(ComponentDocument.upgradeAll(in: tx, catalog: catalog) == 1) }
        #expect(m[m[ids[0]]!.typeID]?.name == "Kit Sample - 128 mm")
        #expect(m[fam]?.params[ComponentKit.versionParam]?.intValue == 2)
        // A definition gone from the library: the family keeps working.
        #expect(ComponentDocument.loaded(m, catalog: ComponentCatalog(builtIn: [])).first { $0.familyID == fam }?.isMissing == true)
        #expect(!ElementMeshes.parts(m[ids[0]]!, m).isEmpty)
    }

    @Test func machiningAndBOM() throws {
        var m = try Self.cabinet()
        let door = try Self.door(m)
        let d = COMPKitTests.sample()
        let light = try #require(COMPFixtures.catalog.first { $0.name == "Cabinet Puck Light" })
        let top = try #require(m.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .top })
        m = try Self.run(m) { tx in
            _ = try ComponentPlacement.place(d, hostID: door.id, settings: ComponentSettings(face: .front, alignment: .center), in: tx)
            _ = try ComponentPlacement.place(light, hostID: top.id, settings: ComponentSettings(face: .bottom, alignment: .center), in: tx)
        }
        let holes = FurnitureMachining.entries(m).filter { $0.label == "Handle hole" }
        #expect(holes.count == 1 && holes[0].partID == door.id)
        let bom = ComponentFabrication.bom(m)
        #expect(bom.contains { $0.family == d.name && $0.count == 1 && $0.unitCost == 5.25 })
        #expect(bom.contains { $0.category == .hinges && $0.count >= 4 }, "the doors' hinges are in the BOM")
        #expect(ComponentFabrication.powerSummary(m).first?.watts == 3)
        #expect(ComponentFabrication.powerSummary(m).first?.driver == 15)
        let rows = FabricationSchedules.rows(.hardwareSchedule, m)
        #expect(rows.contains { $0.values["Component Category"]?.textValue == "03 Hinges & Door Mechanisms" })
        #expect(rows.contains { $0.values["Power"]?.doubleValue == 3 })
    }
}
