import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// COMPD: group D components (16 Lighting & Electrical · 17 Glass & Panels · 18 Edges & Profiles · 19 Motion ·
/// 20 Decorative): every definition builds and flexes, places on a sample carcass, shelf and glass door with its
/// machining, feeds the Edge Profile tool and edge banding, sums its power, and is found by search.
@Suite("COMPD group D components")
struct COMPDTests {
    static let inch = 0.0254
    static var defs: [ComponentDefinition] { ComponentLibrary.groupD }
    static func def(_ name: String) throws -> ComponentDefinition { try #require(defs.first { $0.name == name }, "\(name) is in group D") }

    // MARK: Definitions

    @Test func everyDefinitionBuilds() {
        for d in Self.defs {
            let problems = ComponentKit.validate(d)
            #expect(problems.isEmpty, "\(problems)")
        }
    }

    @Test func everyListItemIsThere() {
        let count = Dictionary(grouping: Self.defs, by: \.category).mapValues(\.count)
        #expect(count[.lighting] == 24 && count[.glass] == 17 && count[.edges] == 22 && count[.motion] == 24 && count[.decorative] == 20, "\(count)")
        #expect(Self.defs.count == 107)
        #expect(Set(Self.defs.map(\.name)).count == Self.defs.count, "names are unique")
        // All in the registry; Lift-Up Mechanisms upgrade FM5's Flap Stay (same family, an extra type).
        let names = Set(ComponentLibrary.furniture.map(\.name))
        #expect(Self.defs.allSatisfy { names.contains($0.name) })
        let stay = ComponentLibrary.component(named: FurnitureHardware.flapStay)
        #expect(stay?.type(named: "Lift-Up Stay - Heavy") != nil && stay?.type(named: "Lift-Up Stay") != nil && stay?.aliases.contains("lift-up mechanisms") == true)
        #expect(stay?.id == ComponentLibrary.fm5Components.first { $0.name == FurnitureHardware.flapStay }?.id, "keeps the FM5 id")
    }

    @Test func everyTypeHasTradeData() {
        for d in Self.defs {
            #expect(!d.tags.isEmpty && !d.aliases.isEmpty, "\(d.name): tags and aliases")
            #expect(!d.materials.isEmpty, "\(d.name): a material slot")
            #expect(!d.symbols.isEmpty, "\(d.name): 2D symbols")
            #expect(!d.placement.hosts.isEmpty && !d.placement.faces.isEmpty, "\(d.name): host rules")
            #expect((1...4).contains(d.types.count) || d.name == FurnitureHardware.flapStay, "\(d.name): \(d.types.count) types")
            #expect(d.manufacturer == "Generic")
            for t in d.types {
                #expect(t.cost > 0 && !t.model.isEmpty && t.sku.hasPrefix("GEN-") && t.manufacturer == "Generic", "\(d.name) / \(t.name)")
                for p in d.parameters where p.formula == nil && p.type != .elementRef(.materials) {
                    #expect(t.values[p.name] != nil, "\(d.name) / \(t.name) sets \(p.name)")
                }
            }
        }
    }

    /// Every family flexes: each length parameter of its default type at 0.8× and 1.25× still builds (every type
    /// builds as it is: `everyDefinitionBuilds`).
    @Test func everyFamilyFlexes() {
        for d in Self.defs {
            let lengths = d.parameters.filter { $0.type == .length && $0.formula == nil }.map(\.name)
            for t in d.defaultType.map({ [$0] }) ?? [] {
                for p in lengths {
                    guard let v = t.values[p]?.doubleValue, v > 0 else { continue }
                    for k in [0.8, 1.25] {
                        var fam = d.family
                        fam.types = [FamilyTypeDefinition(name: t.name, values: t.values.merging([p: .double(v * k)]) { _, b in b })]
                        let ev = FamilyEvaluator.evaluate(fam, typeName: t.name)
                        #expect(ev.errors.isEmpty && ev.solids.contains { !$0.isVoid }, "\(d.name) / \(t.name): \(p) x \(k): \(ev.errors)")
                    }
                }
            }
        }
    }

    @Test func electronicsCarryPowerData() throws {
        let powered = Self.defs.filter { $0.electrical != nil }
        #expect(powered.count == 21, "\(powered.count)")
        for d in powered {
            #expect(d.parameter(named: "Power") != nil && d.parameter(named: "Voltage") != nil, "\(d.name)")
            #expect(d.roles.contains(.electrical))
            #expect(["DC 12 V", "DC 24 V", "AC 120 V"].contains(d.electrical?.supply ?? ""), "\(d.name): \(d.electrical?.supply ?? "")")
        }
        #expect(try Self.def("LED Strip Profile").electrical?.perFoot == true)
        #expect(try Self.def("Cabinet Puck Light").electrical?.perFoot == false)
        #expect(try Self.def("LED Driver").parameter(named: "Output Power") != nil)
    }

    // MARK: Placement and machining

    static func cabinet() throws -> BIMModel { try #require(FurnitureSamples.baseCabinetModel()) }
    static func run(_ m: BIMModel, _ body: (TransactionContext) throws -> Void) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: "Edit")
        try body(tx)
        return try tx.commit().model
    }
    static func part(_ m: BIMModel, _ role: FurniturePartKind) throws -> Element {
        try #require(m.elements(.furnitureShelves).first { $0.furnitureShelf?.role == role })
    }
    static func leftSide(_ m: BIMModel) throws -> Element {
        try #require(m.elements(.furniturePanels).filter { $0.furniturePanel?.role == .panel }.min { (FurniturePartSolids.partBox($0, m)?.box.min.x ?? 0) < (FurniturePartSolids.partBox($1, m)?.box.min.x ?? 0) })
    }
    static func mine(_ m: BIMModel, _ ids: [ElementID]) -> [MachiningEntry] {
        FurnitureMachining.entries(m).filter { if case .hardware(let h) = $0.source { return ids.contains(h) }; return false }
    }
    static func bounds(_ e: Element, _ m: BIMModel) -> Box3 { ElementMeshes.parts(e, m, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) } }

    @Test func ledProfileRunsUnderTheTopInAMachinedGroove() throws {
        var m = try Self.cabinet()
        let top = try Self.part(m, .top)
        let d = try Self.def("Recessed LED Profile")
        var ids: [ElementID] = []
        m = try Self.run(m) { tx in ids = try ComponentPlacement.place(d, hostID: top.id, settings: ComponentSettings(face: .bottom, alignment: .full), in: tx) }
        let f = try #require(ComponentPlacement.face(top, .bottom, m))
        let e = try #require(m[ids.first ?? ElementID(0)])
        #expect(abs((e.params[Parameters.familyParamID("Length")]?.doubleValue ?? 0) - f.width) < 1e-6, "runs the top's full width")
        let grooves = Self.mine(m, ids).filter { $0.label == "LED groove" }
        #expect(grooves.count == 1 && grooves[0].partID == top.id)
        if case .groove(let a, let b, let axis, let w, let depth) = grooves.first?.op {
            #expect(abs(a.distance(to: b) - f.width) < 1e-4)
            #expect(abs(w - 0.0127) < 1e-6 && abs(depth - 0.007) < 1e-6)
            #expect(axis.dot(f.n) < -0.99, "cut up into the top")
        }
        // The profile sits in the groove, flush with the underside.
        let b = Self.bounds(e, m)
        #expect(b.max.z <= f.origin.z + 0.0075 && b.min.z >= f.origin.z - 0.0003, "inside the top: \(b.min.z)…\(b.max.z) vs \(f.origin.z)")
        #expect(ComponentFabrication.powerSummary(m).first { $0.supply == "DC 12 V" }.map { abs($0.watts - 2.9 * f.width / 0.3048) < 1e-6 } == true)
    }

    @Test func pucksBoreTheTopAndSumPower() throws {
        var m = try Self.cabinet()
        let top = try Self.part(m, .top)
        let d = try Self.def("Cabinet Puck Light")
        var ids: [ElementID] = []
        m = try Self.run(m) { tx in
            for x in [-0.4, 0.4] {
                ids += try ComponentPlacement.place(d, typeName: "Puck Light - 65 mm Recessed, 58 mm Cutout", hostID: top.id,
                                                    settings: ComponentSettings(face: .bottom, alignment: .center, offsetX: x), in: tx)
            }
        }
        let cut = Self.mine(m, ids).filter { $0.label == "Puck cutout" }
        #expect(cut.count == 2 && cut.allSatisfy { $0.partID == top.id })
        if case .drill(_, _, let dia, let depth) = cut.first?.op { #expect(abs(dia - 0.058) < 1e-6 && abs(depth - 0.008) < 1e-6) }
        let cable = Self.mine(m, ids).filter { $0.label == "Puck cable hole" }
        if case .drill(_, _, _, let depth) = cable.first?.op { #expect(abs(depth - 0.75 * Self.inch) < 1e-4, "through the 3/4\" top") }
        let sum = try #require(ComponentFabrication.powerSummary(m).first { $0.supply == "DC 12 V" })
        #expect(abs(sum.watts - 5) < 1e-6 && sum.driver == 15)
    }

    @Test func tMoldingSlotsTheShelfEdge() throws {
        var m = try Self.cabinet()
        let bottom = try Self.part(m, .bottom)
        let d = try Self.def("T-Molding")
        var ids: [ElementID] = []
        m = try Self.run(m) { tx in ids = try ComponentPlacement.place(d, hostID: bottom.id, settings: ComponentSettings(face: .frontEdge, alignment: .full), in: tx) }
        let f = try #require(ComponentPlacement.face(bottom, .frontEdge, m))
        let slot = Self.mine(m, ids).filter { $0.label == "T-molding slot" }
        #expect(slot.count == 1 && slot[0].partID == bottom.id)
        if case .groove(let a, let b, let axis, let w, _) = slot.first?.op {
            #expect(abs(a.distance(to: b) - f.width) < 1e-4 && abs(w - 0.0016) < 1e-6 && axis.dot(Vec3(0, 1, 0)) > 0.99, "into the front edge")
        }
        // The cap is in front of the edge, the tongue in the slot.
        let b = Self.bounds(try #require(m[ids[0]]), m)
        #expect(b.min.y < f.origin.y - 0.001 && b.max.y > f.origin.y + 0.005)
    }

    @Test func gasStrutGoesOnTheSideAndCrownAlongTheTop() throws {
        var m = try Self.cabinet()
        let side = try Self.leftSide(m), top = try Self.part(m, .top)
        let strut = try Self.def("Gas Strut"), crown = try Self.def("Crown Molding")
        var s: [ElementID] = [], c: [ElementID] = []
        m = try Self.run(m) { tx in
            s = try ComponentPlacement.place(strut, hostID: side.id, settings: ComponentSettings(face: .inside, alignment: .top, offsetY: 3 * Self.inch), in: tx)
            c = try ComponentPlacement.place(crown, hostID: top.id, settings: ComponentSettings(face: .front, alignment: .full), in: tx)
        }
        let inside = try #require(ComponentPlacement.face(side, .inside, m))
        #expect(inside.n.x > 0.99, "the left side's inside face looks into the cabinet")
        let sb = Self.bounds(try #require(m[s[0]]), m)
        #expect(sb.min.x >= inside.origin.x - 1e-4 && sb.max.x > inside.origin.x + 0.01, "the strut stands off the inside face")
        #expect(Self.mine(m, s).filter { $0.label == "Strut bracket screw" && $0.partID == side.id }.count >= 2)
        let front = try #require(ComponentPlacement.face(top, .front, m))
        let cb = Self.bounds(try #require(m[c[0]]), m)
        #expect(cb.max.y <= front.origin.y + 1e-4 && cb.min.y < front.origin.y - 0.06, "the crown projects from the front")
        #expect(abs((cb.max.x - cb.min.x) - front.width) < 1e-3, "and runs the top's width")
    }

    @Test func glassHardwareGoesOnAGlassDoor() throws {
        var m = try Self.cabinet()
        let door = try #require(m.elements(.furnitureFronts).filter { $0.furnitureFront?.kind == .door }.min { $0.id < $1.id })
        let glassType = try #require(m.types(for: .furnitureFronts).first { $0.name == "Glass Panel - Full Overlay" })
        m = try Self.run(m) { tx in tx.update(door.id) { $0.typeID = glassType.id } }
        let handle = try Self.def("Glass Door Handle"), hinge = try Self.def("Glass Door Hinge - Clamp")
        var h: [ElementID] = [], g: [ElementID] = []
        m = try Self.run(m) { tx in
            h = try ComponentPlacement.place(handle, typeName: "Glass Bar Handle - 96 mm CC", hostID: door.id, in: tx)
            g = try ComponentPlacement.place(hinge, hostID: door.id, in: tx)
        }
        let holes = Self.mine(m, h).filter { $0.label == "Glass handle hole" }
        #expect(holes.count == 2 && holes.allSatisfy { $0.partID == door.id })
        if holes.count == 2, case .drill(let a, _, let dia, _) = holes[0].op, case .drill(let b, _, _, _) = holes[1].op {
            #expect(abs(a.distance(to: b) - 0.096) < 1e-6 && abs(dia - 0.012) < 1e-6)
        }
        #expect(g.count == 2, "a hinge set by the count rule")
        // A glass shelf support in the side's pin holes.
        let side = try Self.leftSide(m)
        let pin = try Self.def("Glass Shelf Support - Pin with Pad")
        var p: [ElementID] = []
        m = try Self.run(m) { tx in p = try ComponentPlacement.place(pin, hostID: side.id, settings: ComponentSettings(face: .inside, alignment: .center), in: tx) }
        let hole = Self.mine(m, p).filter { $0.label == "Shelf pin hole" }
        #expect(hole.count == 1 && hole[0].partID == side.id)
        if case .drill(_, let axis, let dia, _) = hole.first?.op { #expect(abs(dia - 0.005) < 1e-6 && axis.x < -0.99, "into the side") }
    }

    @Test func hostRulesRefuseTheWrongHost() throws {
        var m = try Self.cabinet()
        let side = try Self.leftSide(m)
        #expect(throws: TransactionError.self) {
            m = try Self.run(m) { tx in _ = try ComponentPlacement.place(try Self.def("Glass Door Hinge - Clamp"), hostID: side.id, in: tx) }
        }
        #expect(throws: TransactionError.self) {
            m = try Self.run(m) { tx in _ = try ComponentPlacement.place(try Self.def("Rotating Platform"), hostID: side.id, in: tx) }
        }
    }

    // MARK: Edge treatments in the Furniture tools

    @Test func edgeProfileTypesAndBandsAreInFurnitureDocuments() throws {
        let m = try Self.cabinet()
        let specs = ComponentLibrary.edgeProfileTypes
        #expect(specs.count == Self.defs.filter { $0.roles.contains(.edgeProfile) }.reduce(0) { $0 + $1.types.count })
        let types = m.types(for: .furnitureEdgeProfiles)
        for s in specs {
            let t = try #require(types.first { $0.name == s.name }, "\(s.name)")
            let v = FurniturePartTypes.Values(t.typeData)
            #expect(t.typeData?.familyName == "Edge Profile" && v.profileShape == s.shape && abs(v.size - s.size) < 1e-9)
        }
        #expect(specs.contains { $0.shape == .bevel } && specs.contains { $0.shape == .ogee } && specs.contains { $0.shape == .fingerPull })
        let bands = ComponentLibrary.edgeBands
        #expect(bands.count == 16)
        for b in bands {
            let mat = try #require(m.elements(.materials).first { $0.name == b.name }, "\(b.name)")
            #expect(mat.material?.costUnit == MaterialCostUnit.linearFoot && mat.material?.cost == b.costPerFoot)
        }
        // Idempotent.
        let tx = TransactionContext(model: m, name: "Again")
        ComponentLibrary.ensureGroupDEdgeTypes(in: tx)
        let again = try tx.commit().model
        #expect(again.types(for: .furnitureEdgeProfiles).count == types.count)
    }

    @Test func theEdgeProfileToolCutsABevel() throws {
        var m = try Self.cabinet()
        let top = try Self.part(m, .top)
        let bevel = try #require(m.types(for: .furnitureEdgeProfiles).first { $0.name == "Bevel - 1/2\" x 1/4\"" })
        let before = ElementMeshes.parts(top, m, detail: .fine).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        var id = ElementID(0)
        m = try Self.run(m) { tx in id = try FurniturePartOperations.createEdgeProfile(on: top.id, edge: PartEdge(axis: .x, firstAtMax: false, secondAtMax: true), typeID: bevel.id, in: tx) }
        #expect(m[id]?.furnitureEdgeProfile != nil)
        let after = ElementMeshes.parts(try #require(m[top.id]), m, detail: .fine).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        let len = try #require(FurniturePartSolids.partBox(top, m)?.box).max.x - (FurniturePartSolids.partBox(top, m)?.box.min.x ?? 0)
        let removed = 0.5 * (0.5 * Self.inch) * (0.25 * Self.inch) * len
        #expect(abs((before - after) - removed) < removed * 0.15, "a 1/2\" x 1/4\" bevel comes off: \(before - after) vs \(removed)")
        let shape = EdgeProfileShapes.voidProfile(.bevel, size: 0.5 * Self.inch, depth: 0.25 * Self.inch, offset: 0, inSecondFace: false, thickness1: 0.02, thickness2: 0.02)
        #expect(shape.contains { abs($0.x - 0.5 * Self.inch) < 1e-9 && abs($0.y) < 1e-9 } && shape.contains { abs($0.x) < 1e-9 && abs($0.y - 0.25 * Self.inch) < 1e-9 })
    }

    @Test func edgeBandingSetsAPartTypesBand() throws {
        var m = try Self.cabinet()
        let ply = try #require(m.types(for: .furniturePanels).first { $0.name == "3/4\" Plywood" })
        var ok = false
        m = try Self.run(m) { tx in ok = ComponentLibrary.applyEdgeBand("ABS Edge Banding - 2 mm x 22 mm", toType: ply.id, in: tx) }
        #expect(ok)
        let v = FurniturePartTypes.Values(m[ply.id]?.typeData)
        #expect(m[v.edgeMaterial ?? ElementID(0)]?.name == "ABS Edge Banding - 2 mm x 22 mm" && abs(v.edgeThickness - 0.002) < 1e-9)
        #expect(!ComponentLibrary.applyEdgeBand("No Such Band", toType: ply.id, in: TransactionContext(model: m, name: "x")))
    }

    // MARK: Search

    @Test func everyComponentIsFoundBySearch() {
        let index = ComponentSearchIndex(ComponentLibrary.furniture)
        func top(_ q: String, _ n: Int = 3) -> [String] { index.search(q, limit: n).map(\.definition.name) }
        for d in Self.defs { #expect(top(d.name, 3).contains(d.name), "\(d.name): \(top(d.name, 3))") }
        #expect(top("led profile", 4).contains("LED Strip Profile"), "\(top("led profile", 4))")
        #expect(top("puck light").first == "Cabinet Puck Light", "\(top("puck light"))")
        #expect(top("t molding").first == "T-Molding", "\(top("t molding"))")
        #expect(top("crown").first == "Crown Molding", "\(top("crown"))")
        #expect(top("cane").contains("Cane Webbing"))
        #expect(top("mirror clip").first == "Mirror Clip", "\(top("mirror clip"))")
        #expect(top("gas strut").first == "Gas Strut", "\(top("gas strut"))")
        #expect(top("lazy susan bearing", 4).contains("Swivel Bearing Plate"), "\(top("lazy susan bearing", 4))")
        #expect(top("abs edge banding").first == "ABS Edge Banding", "\(top("abs edge banding"))")
        #expect(top("usb charger").first == "USB Charging Port", "\(top("usb charger"))")
        let recessed = index.search("recessed led 24 x 7", limit: 1).first
        #expect(recessed?.definition.name == "Recessed LED Profile")
    }
}
