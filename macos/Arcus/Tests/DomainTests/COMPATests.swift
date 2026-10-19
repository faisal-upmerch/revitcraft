import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// COMPA: Group A of the Furniture Component Library (handles, locks, hinges, drawer systems, sliding doors), and the
/// evaluator support it needs (revolves and blends on side work planes).
@Suite("COMPA components")
struct COMPATests {
    // MARK: FM5 hardware values recognise component families by their parameters

    static func td(_ family: String, _ values: [String: ParamValue]) -> TypeData {
        var p: [ParameterID: ParamValue] = [:]
        for (k, v) in values { p[Parameters.familyParamID(k)] = v }
        return TypeData(instanceCategory: .furnitureHardware, familyName: family, params: p)
    }

    @Test func hardwareValuesReadParameters() {
        typealias V = FurnitureHardware.Values
        // New families: by parameters.
        #expect(V(Self.td("Soft-Close Hinge", ["Cup Diameter": .double(0.035)])).isConcealed)
        #expect(!V(Self.td("Detachable Hinge", ["Leaf Height": .double(0.05)])).isConcealed)
        #expect(V(Self.td("Mushroom Knob", ["Hole Spacing": .double(0)])).isKnob)
        #expect(V(Self.td("Mushroom Knob", ["Hole Spacing": .double(0)])).handleHoleSpacing == 0)
        #expect(!V(Self.td("Bow Handle", ["Hole Spacing": .double(0.128)])).isKnob)
        #expect(V(Self.td("J-Pull Profile", ["Edge Mounted": .bool(true)])).isEdgePull)
        #expect(V(Self.td("Concealed Drawer Runners", ["Undermount": .bool(true)])).isUndermount)
        #expect(V(Self.td("Continuous Hinge", ["Continuous": .bool(true)])).isPiano)
        #expect(!V(Self.td("Drawer Slide - Ball Bearing", ["Undermount": .bool(false)])).isUndermount)
        // FM5 families: by name, as before.
        #expect(V(Self.td(FurnitureHardware.knob, [:])).isKnob)
        #expect(V(Self.td(FurnitureHardware.concealedHinge, [:])).isConcealed)
        #expect(V(Self.td(FurnitureHardware.edgePull, [:])).isEdgePull)
        #expect(V(Self.td(FurnitureHardware.undermountSlide, [:])).isUndermount)
        #expect(V(Self.td(FurnitureHardware.pianoHinge, [:])).isPiano)
        #expect(!V(Self.td(FurnitureHardware.barPull, ["Hole Spacing": .double(0.128)])).isKnob)
    }

    // MARK: Revolves and blends on side work planes

    /// A knob-like revolve: radius 10 mm, 20 mm tall, about the sketch's vertical axis.
    static func revolveFamily(_ plane: FamilySketchPlane?) -> FamilyDefinition {
        var f = FamilyDefinition(name: "Revolve Test", template: .furnitureHardware)
        let profile = [FamilyPoint("0 m", "0 m"), FamilyPoint("0.01 m", "0 m"), FamilyPoint("0.01 m", "0.02 m"), FamilyPoint("0 m", "0.02 m")]
        var s = FamilySolid(name: "Knob", profile: .revolve(FamilyRevolve(profile: profile, axis: FamilyPoint("0.05 m", "0 m"))), zMin: .expr("0 m"), zMax: .expr("0 m"))
        s.workPlane = plane
        f.solids = [s]
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        return f
    }

    @Test func revolveOnXZTurnsAboutY() throws {
        let ev = FamilyEvaluator.evaluate(Self.revolveFamily(.xz), typeName: "T")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = try #require(ev.solids.first).bounds
        // The axis runs along family Y through x = 0.05, z = 0; the profile's height runs along +Y.
        #expect(abs(b.min.y) < 1e-6 && abs(b.max.y - 0.02) < 1e-6)
        #expect(abs(b.min.x - 0.04) < 1e-4 && abs(b.max.x - 0.06) < 1e-4)
        #expect(abs(b.min.z + 0.01) < 1e-4 && abs(b.max.z - 0.01) < 1e-4)
    }

    @Test func revolveOnYZTurnsAboutX() throws {
        let ev = FamilyEvaluator.evaluate(Self.revolveFamily(.yz), typeName: "T")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = try #require(ev.solids.first).bounds
        #expect(abs(b.min.x) < 1e-6 && abs(b.max.x - 0.02) < 1e-6)
        #expect(abs(b.min.y - 0.04) < 1e-4 && abs(b.max.y - 0.06) < 1e-4)
    }

    @Test func planRevolveIsUnchanged() throws {
        for plane in [nil, FamilySketchPlane.xy] {
            let ev = FamilyEvaluator.evaluate(Self.revolveFamily(plane), typeName: "T")
            let b = try #require(ev.solids.first).bounds
            #expect(abs(b.min.z) < 1e-6 && abs(b.max.z - 0.02) < 1e-6)
            #expect(abs(b.min.x - 0.04) < 1e-4 && abs(b.max.x - 0.06) < 1e-4)
        }
    }

    @Test func blendOnXZRunsAlongY() throws {
        var f = FamilyDefinition(name: "Blend Test", template: .furnitureHardware)
        let sq = { (h: String) in [FamilyPoint("-\(h)", "-\(h)"), FamilyPoint(h, "-\(h)"), FamilyPoint(h, h), FamilyPoint("-\(h)", h)] }
        var s = FamilySolid(name: "Frustum", profile: .blend(FamilyBlend(bottom: sq("0.02 m"), top: sq("0.01 m"))), zMin: .expr("0 m"), zMax: .expr("0.03 m"))
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        f.solids = [s]
        let flat = FamilyEvaluator.evaluate(f, typeName: "T")
        let fb = try #require(flat.solids.first).bounds
        #expect(abs(fb.max.z - 0.03) < 1e-6 && abs(fb.max.y - 0.02) < 1e-6)
        s.workPlane = .xz
        f.solids = [s]
        let ev = FamilyEvaluator.evaluate(f, typeName: "T")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = try #require(ev.solids.first).bounds
        #expect(abs(b.min.y) < 1e-6 && abs(b.max.y - 0.03) < 1e-6)
        #expect(abs(b.max.z - 0.02) < 1e-6 && abs(b.max.x - 0.02) < 1e-6)
    }
}

/// COMPA: Group A's 100 components: every definition builds and validates, every type evaluates and flexes, each
/// places on the sample base cabinet with its host and machining, fronts use the hinges, handles and slides, and
/// search finds each by its name and aliases.
@Suite("COMPA definitions")
struct COMPADefinitionTests {
    static let defs = GroupA.all
    static let inch = 0.0254

    @Test func countsPerCategory() {
        let counts = Dictionary(grouping: Self.defs, by: \.category).mapValues(\.count)
        #expect(counts[.handles] == 22 && counts[.locks] == 16 && counts[.hinges] == 20 && counts[.drawers] == 24 && counts[.slidingDoors] == 18, "\(counts)")
        #expect(Self.defs.count == 100)
        #expect(Set(Self.defs.map(\.name)).count == 100, "names are unique")
        #expect(Set(Self.defs.map(\.id)).count == 100, "ids are unique")
    }

    @Test func everyDefinitionValidates() {
        for d in Self.defs {
            let problems = ComponentKit.validate(d)
            #expect(problems.isEmpty, "\(d.name): \(problems)")
        }
    }

    @Test func libraryDataIsComplete() {
        for d in Self.defs {
            #expect(!d.tags.isEmpty && !d.aliases.isEmpty, "\(d.name): tags and aliases")
            #expect(d.family.manufacturer == "Generic" && d.family.template == .furnitureHardware, "\(d.name)")
            #expect(!d.materials.isEmpty, "\(d.name): a material slot")
            #expect(!d.placement.hosts.isEmpty && !d.placement.faces.isEmpty, "\(d.name): host rules")
            #expect(d.symbols.contains { $0.levels.contains(.coarse) }, "\(d.name): a Coarse symbol")
            #expect(d.family.solids.contains { $0.visibleAt.contains(.fine) && !$0.visibleAt.contains(.coarse) } || d.frame == .plan, "\(d.name): Medium/Fine solids")
            let maxTypes = d.hardwareKind == .slide ? 8 : 4
            #expect((1...maxTypes).contains(d.types.count), "\(d.name): \(d.types.count) types")
            #expect(d.types.filter(\.isDefault).count == 1, "\(d.name): one default type")
            for t in d.types {
                #expect(t.cost > 0 && !t.model.isEmpty && t.sku.hasPrefix("GEN-") && t.manufacturer == "Generic", "\(d.name) / \(t.name): cost and catalogue data")
            }
            let slots = Set(d.materials.map(\.name))
            #expect(d.family.solids.allSatisfy { $0.isVoid || $0.materialParameter.map(slots.contains) == true }, "\(d.name): solids use its material slots")
            #expect(d.id.hasPrefix("comp.\(d.category.code).") || d.renamedTypes.count > 0 || FurnitureHardware.kinds[d.name] != nil, "\(d.name): id \(d.id)")
        }
    }

    /// Every type's dimensions flex 20% up and 15% down without breaking any solid.
    @Test func everyTypeFlexes() {
        for d in Self.defs {
            let lengths = d.parameters.filter { $0.type == .length && $0.formula == nil && $0.group == .dimensions }.map(\.name)
            for t in d.types {
                for p in lengths {
                    guard let v = t.values[p]?.doubleValue, v > 0 else { continue }
                    for f in [1.2, 0.85] {
                        var fam = d.family
                        if let k = fam.types.firstIndex(where: { $0.name == t.name }) { fam.types[k].values[p] = .double(v * f) }
                        let ev = FamilyEvaluator.evaluate(fam, typeName: t.name)
                        #expect(ev.errors.isEmpty, "\(d.name) / \(t.name): \(p) × \(f): \(ev.errors)")
                        #expect(!ev.solids.filter { !$0.isVoid }.isEmpty, "\(d.name) / \(t.name): \(p) × \(f): no solids")
                    }
                }
            }
        }
    }

    @Test func registryCarriesGroupA() throws {
        for d in Self.defs {
            let r = try #require(ComponentLibrary.component(named: d.name), "\(d.name) in the registry")
            #expect(Set(r.types.map(\.name)) == Set(d.types.map(\.name)), "\(d.name): the registry's types are Group A's (renamed FM5 types dropped)")
        }
        // Upgrades keep FM5's ids and parameters (fronts and machining read them).
        for n in [FurnitureHardware.barPull, FurnitureHardware.knob, FurnitureHardware.cupPull, FurnitureHardware.edgePull, FurnitureHardware.concealedHinge,
                  FurnitureHardware.buttHinge, FurnitureHardware.pianoHinge, FurnitureHardware.sideMountSlide, FurnitureHardware.undermountSlide] {
            let r = try #require(ComponentLibrary.component(named: n))
            let fm5 = try #require(ComponentLibrary.fm5Components.first { $0.name == n })
            #expect(r.id == fm5.id, "\(n)")
            for p in fm5.family.parameters { #expect(r.family.parameter(named: p.name) != nil, "\(n) keeps \(p.name)") }
            #expect(r.hardwareKind == fm5.hardwareKind, "\(n)")
        }
    }

    @Test func searchFindsNamesAndAliases() {
        let index = ComponentSearchIndex(ComponentLibrary.furniture)
        let sizeOnly = try! NSRegularExpression(pattern: "^[0-9 ./]+( ?mm| ?mm cc| ?mm centers|\"|mm)?$")
        for d in Self.defs {
            let byName = index.search(d.name, limit: 3).map(\.definition.name)
            #expect(byName.contains(d.name), "\(d.name): \(byName)")
            for a in d.aliases where sizeOnly.firstMatch(in: a, range: NSRange(a.startIndex..., in: a)) == nil {
                let hits = index.search(a, limit: 40).map(\.definition.name)
                #expect(hits.contains(d.name), "\(d.name): alias \"\(a)\" → \(hits.prefix(5))")
            }
        }
    }

    // MARK: On the sample cabinet

    static func cabinet() throws -> BIMModel { try #require(FurnitureSamples.baseCabinetModel()) }

    static func run(_ m: BIMModel, _ body: (TransactionContext) throws -> Void) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: "Edit")
        try body(tx)
        return try tx.commit().model
    }

    /// A host of each kind in the sample cabinet.
    static func hosts(_ m: BIMModel) -> [ComponentHostKind: Element] {
        var out: [ComponentHostKind: Element] = [:]
        for c in [Category.furnitureFronts, .furniturePanels, .furnitureShelves, .furnitureBays, .furnitureLegs, .furnitureRails] {
            for e in m.elements(c).sorted(by: { $0.id < $1.id }) {
                if let k = ComponentPlacement.hostKind(e, m), out[k] == nil { out[k] = e }
            }
        }
        return out
    }

    @Test func everyComponentPlacesOnTheCabinet() throws {
        let cabinet = try Self.cabinet(), chest = try #require(FurnitureSamples.chestModel())
        let hosts = Self.hosts(cabinet), lids = Self.hosts(chest)
        #expect(hosts[.door] != nil && hosts[.drawerFront] != nil && hosts[.sidePanel] != nil && hosts[.bay] != nil, "\(hosts.keys)")
        var placedCount = 0
        for d in Self.defs {
            // The base cabinet's doors, drawers, sides and bays; the chest's lid for lid and flap hardware.
            let onCabinet = d.placement.hosts.first { hosts[$0] != nil }
            guard let kind = onCabinet ?? d.placement.hosts.first(where: { lids[$0] != nil }), let host = onCabinet != nil ? hosts[kind] : lids[kind] else {
                Issue.record("\(d.name): no host of \(d.placement.hosts) in the sample pieces")
                continue
            }
            let base = onCabinet != nil ? cabinet : chest
            var ids: [ElementID] = []
            let m = try Self.run(base) { tx in ids = try ComponentPlacement.place(d, hostID: host.id, in: tx) }
            #expect(!ids.isEmpty, "\(d.name) on a \(kind.rawValue)")
            for id in ids {
                let e = try #require(m[id])
                #expect(e.hostID == host.id && e.category == .furnitureHardware, "\(d.name): hosted by its \(kind.rawValue)")
                #expect(!ElementMeshes.parts(e, m, detail: .fine).isEmpty, "\(d.name): geometry on the \(kind.rawValue)")
            }
            if !d.mounting.isEmpty {
                let mine = Set(ids)
                let ops = FurnitureMachining.entries(m).filter { if case .hardware(let h) = $0.source { return mine.contains(h) } else { return false } }
                #expect(!ops.isEmpty, "\(d.name): its drilling reaches CNC")
            }
            placedCount += 1
        }
        #expect(placedCount == 100)
    }

    /// Doors and drawers use Group A hinges, handles, knobs and slides as they do FM5's: hinge sets by height with
    /// their cups bored, handle holes drilled, and the longest slide that fits the bay.
    @Test func frontsUseGroupAHardware() throws {
        var m = try Self.cabinet()
        let door = try #require(m.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .door }.min { $0.id < $1.id })
        let drawer = try #require(m.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .drawer }.min { $0.id < $1.id })
        func def(_ n: String) throws -> ComponentDefinition { try #require(Self.defs.first { $0.name == n }, "\(n)") }
        var hinge: ElementID?, handle: ElementID?, knob: ElementID?
        m = try Self.run(m) { tx in
            hinge = ComponentDocument.load(try def("Soft-Close Hinge"), in: tx)
            handle = ComponentDocument.load(try def("T-Bar Handle"), in: tx)
            knob = ComponentDocument.load(try def("Mushroom Knob"), in: tx)
            _ = ComponentDocument.load(try def("Drawer Slide - Ball Bearing"), in: tx)
        }
        m = try Self.run(m) { tx in
            tx.update(door.id) { $0.furnitureFront?.hingeTypeID = hinge; $0.furnitureFront?.handleTypeID = handle }
            tx.update(drawer.id) { $0.furnitureFront?.handleTypeID = knob }
        }
        let doorHW = FurnitureFronts.hardware(try #require(m[door.id], "door"), m)
        let hinges = doorHW.filter { $0.slot.hasPrefix("hinge") }
        let doorNow = try #require(m[door.id])
        let leafHeight = try #require(FurnitureFronts.geometry(doorNow, m)?.leaves.first?.height)
        #expect(hinges.count == FurnitureFronts.hingeCount(edgeLength: leafHeight))
        #expect(hinges.allSatisfy { $0.typeID == hinge })
        let ops = FurnitureMachining.entries(m)
        #expect(ops.filter { $0.partID == door.id && $0.label == "Hinge cup 35 mm" }.count == hinges.count, "a 35 mm cup per hinge")
        #expect(ops.filter { $0.partID == door.id && $0.label.hasPrefix("Handle hole") }.count == 2, "the T-bar's two holes")
        #expect(ops.filter { $0.partID == drawer.id && $0.label.hasPrefix("Handle hole") }.count == 1, "the knob's one hole")
        // The ball-bearing slide family: the longest length that fits a 24" deep bay, less the rear clearance.
        let slide = try #require(FurnitureHardware.slide(family: "Drawer Slide - Ball Bearing", fitting: 21 * Self.inch, m))
        #expect(m[slide]?.name == "Drawer Slide - 500 mm")
        #expect(FurnitureHardware.slide(family: "Drawer Slide - Ball Bearing", fitting: 9 * Self.inch, m) == nil, "nothing fits under 250 mm + clearance")
    }
}
