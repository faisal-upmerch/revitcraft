import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// COMPB: Component Library group B (06 Connectors & Fasteners, 07 Legs, Feet & Bases, 08 Shelving Hardware,
/// 09 Wardrobe & Closet, 15 Wheels, Casters & Mobility): the list and counts, FM5 upgrades, components placed on a
/// sample carcass and table with their machining, legs as Leg types, connectors in joints by Joint Rules, and search.
/// The sweeps over every definition (build, evaluate, flex) are in LibraryTests (COMPBLibraryTests).
@Suite("COMPB group B components") @MainActor
struct COMPBTests {
    static let inch = 0.0254
    static var defs: [ComponentDefinition] { ComponentLibrary.groupB }

    static func def(_ name: String) throws -> ComponentDefinition { try #require(ComponentLibrary.component(named: name), "\(name)") }

    static func run(_ m: BIMModel, _ name: String = "Edit", _ body: (TransactionContext) throws -> Void) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: name)
        try body(tx)
        return try tx.commit().model
    }

    static func drills(_ m: BIMModel, source id: ElementID) -> [(ElementID, Vec3, Vec3, Double, Double, String)] {
        FurnitureMachining.entries(m).compactMap { e in
            guard case .hardware(let h) = e.source, h == id, case .drill(let c, let a, let d, let depth) = e.op else { return nil }
            return (e.partID, c, a, d, depth, e.label)
        }
    }

    // MARK: Definitions

    @Test func listCountsPerCategory() {
        var counts: [ComponentCategory: Int] = [:]
        for d in Self.defs { counts[d.category, default: 0] += 1 }
        #expect(counts[.connectors] == 27)
        #expect(counts[.legs] == 27, "Sofa Legs are group C's Sofa Leg")
        #expect(counts[.shelving] == 17)
        #expect(counts[.wardrobe] == 30)
        #expect(counts[.mobility] == 16)
        #expect(Set(Self.defs.map(\.name)).count == Self.defs.count, "names are unique")
        // Every one is in the registry, and none collides with another group's.
        let registry = Set(ComponentLibrary.furniture.map(\.name))
        #expect(Self.defs.allSatisfy { registry.contains($0.name) })
        let others = ComponentLibrary.groupA + ComponentLibrary.groupC + ComponentLibrary.groupD
        let clash = Set(others.map(\.name)).intersection(Self.defs.map(\.name))
        #expect(clash.isEmpty, "shared names: \(clash)")
    }

    @Test func fm5FamiliesAreUpgradedNotDuplicated() throws {
        let F = FurnitureHardware.self
        for (name, types) in [(F.camLock, ["12 mm", "15 mm", "20 mm"]), (F.dowel, ["6 x 30 mm", "8 x 30 mm", "8 x 40 mm", "10 x 40 mm"]),
                              (F.confirmat, ["7 x 50 mm", "5 x 40 mm", "6.3 x 50 mm", "7 x 70 mm"]), (F.glide, ["1\" Leveler", "1 1/2\" Leveler", "2\" Heavy Leveler"]),
                              (F.caster, ["2\" Swivel", "3\" Swivel", "1 5/8\" Swivel", "4\" Swivel"]), (F.shelfPin, ["5 mm Spoon", "1/4\" Spoon", "5 mm Plain", "5 mm Plate"])] {
            let d = try Self.def(name)
            #expect(Set(d.types.map(\.name)) == Set(types), "\(name): \(d.types.map(\.name))")
            #expect(ComponentLibrary.furniture.filter { $0.name == name }.count == 1)
            #expect(d.family.solids.allSatisfy { if case .circle = $0.profile { return false }; return true }, "\(name): smooth round parts")
            #expect(ComponentKit.validate(d).isEmpty, "\(ComponentKit.validate(d))")
        }
        // FM5's own type values are kept (fronts and joints read them).
        let cam = try Self.def(F.camLock)
        #expect(cam.type(named: "15 mm")?.values["Cam Distance"]?.doubleValue == 0.024)
        #expect(cam.type(named: "12 mm")?.values["Cam Diameter"]?.doubleValue == 0.012)
    }

    // MARK: Placement

    static func cabinet() throws -> BIMModel { try #require(FurnitureSamples.baseCabinetModel()) }

    @Test func legsAndCastersGoUnderTheBottomWithTheirScrews() throws {
        var m = try Self.cabinet()
        let bottom = try #require(m.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .bottom })
        let leg = try Self.def("Adjustable Cabinet Leg"), caster = try Self.def("Locking Caster")
        var legIDs: [ElementID] = [], casterIDs: [ElementID] = []
        m = try Self.run(m, "Legs") { tx in
            legIDs = try ComponentPlacement.place(leg, hostID: bottom.id, settings: ComponentSettings(face: .bottom, alignment: .bottomLeft, offsetX: 2 * Self.inch, offsetY: 2 * Self.inch), in: tx)
            casterIDs = try ComponentPlacement.place(caster, hostID: bottom.id, settings: ComponentSettings(face: .bottom, alignment: .topRight, offsetX: 2 * Self.inch, offsetY: 2 * Self.inch), in: tx)
        }
        let e = try #require(m[legIDs.first])
        #expect(e.hostID == bottom.id && e.category == .furnitureHardware)
        // It hangs under the bottom's underside down to the floor (100 mm).
        let f = try #require(ComponentPlacement.face(bottom, .bottom, m))
        let b = ElementMeshes.parts(e, m, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(abs(b.max.z - f.origin.z) < 0.002 && abs((f.origin.z - b.min.z) - 0.100) < 0.003, "\(b)")
        // At the corner, 2" in from the bottom's edges.
        let bb = ElementMeshes.bounds(bottom, m)
        let c = (b.min + b.max) * 0.5
        #expect(abs(c.x - (bb.min.x + 2 * Self.inch)) < 0.003, "\(c.x) vs \(bb.min.x)")
        // Four screws into the bottom, drilled up into it.
        let legHoles = Self.drills(m, source: e.id)
        #expect(legHoles.count == 4 && legHoles.allSatisfy { $0.0 == bottom.id && $0.2.z > 0.9 && abs($0.3 - 0.0035) < 1e-6 }, "\(legHoles)")
        let casterHoles = Self.drills(m, source: try #require(casterIDs.first))
        #expect(casterHoles.count == 4 && casterHoles.allSatisfy { $0.0 == bottom.id })
        // Shows at Coarse too (structural), and in the BOM with its cost.
        #expect(!ElementMeshes.parts(e, m, detail: .coarse).isEmpty)
        #expect(ComponentFabrication.bom(m).contains { $0.family == "Adjustable Cabinet Leg" && $0.unitCost > 0 })
    }

    @Test func shelfHardwareGoesOnTheSides() throws {
        var m = try Self.cabinet()
        let side = try #require(m.elements(.furniturePanels).first { $0.furniturePanel?.role == .panel })
        let support = try Self.def("Shelf Support"), pin = try Self.def(FurnitureHardware.shelfPin)
        var ids: [ElementID] = []
        m = try Self.run(m, "Supports") { tx in
            ids = try ComponentPlacement.place(support, hostID: side.id, settings: ComponentSettings(face: .inside, alignment: .bottomLeft, offsetX: 0.037, offsetY: 0.3), in: tx)
            _ = try ComponentPlacement.place(pin, typeName: "5 mm Plain", hostID: side.id, settings: ComponentSettings(face: .inside, alignment: .bottomRight, offsetX: 0.037, offsetY: 0.3), in: tx)
        }
        let holes = Self.drills(m, source: try #require(ids.first))
        #expect(holes.count == 1)
        let h = try #require(holes.first)
        #expect(h.0 == side.id && abs(h.3 - 0.005) < 1e-9 && abs(h.4 - 0.009) < 1e-6, "\(h)")
        // Into the side: the axis points out of the bay, across the side's thickness.
        let f = try #require(ComponentPlacement.face(side, .inside, m))
        #expect(h.2.dot(f.n) < -0.99)
        // Its geometry stands out of the side's inside face, into the bay.
        let e = try #require(m[ids.first])
        let b = ElementMeshes.parts(e, m, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect((b.max - f.origin).dot(f.n) > 0.01 || (b.min - f.origin).dot(f.n) > 0.01 || abs(f.n.x) > 0.9)
    }

    @Test func rodsAndPullOutsGoBetweenTheSidesOfABay() throws {
        var m = try Self.cabinet()
        let bay = try #require(m.elements(.furnitureBays).compactMap { b -> (Element, BayOpening)? in b.furnitureBay?.opening.map { (b, $0) } }.min { $0.0.id < $1.0.id })
        let rod = try Self.def("Clothes Hanging Rod"), basket = try Self.def("Pull-Out Basket"), turn = try Self.def("Rotating Shelf")
        var rodIDs: [ElementID] = [], basketIDs: [ElementID] = [], turnIDs: [ElementID] = []
        m = try Self.run(m, "Bay") { tx in
            let depth: [String: ParamValue] = ["Opening Depth": .double(bay.1.depth)]
            rodIDs = try ComponentPlacement.place(rod, hostID: bay.0.id, values: depth.merging(["Mount Height": .double(bay.1.height - 0.05)]) { a, _ in a }, in: tx)
            basketIDs = try ComponentPlacement.place(basket, hostID: bay.0.id, values: depth, in: tx)
            turnIDs = try ComponentPlacement.place(turn, hostID: bay.0.id, values: depth, in: tx)
        }
        let r = try #require(m[rodIDs.first])
        #expect(r.hostID == bay.0.id)
        #expect(abs((r.params[Parameters.familyParamID("Opening Width")]?.doubleValue ?? 0) - bay.1.width) < 1e-6, "the rod is cut to the bay")
        // Its 3D spans the bay from side to side.
        let b = ElementMeshes.parts(r, m, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(abs((b.max.x - b.min.x) - bay.1.width) < 0.002, "\(b.max.x - b.min.x) vs \(bay.1.width)")
        // Support screws in both sides.
        let holes = Self.drills(m, source: r.id)
        #expect(holes.contains { $0.0 == bay.1.left && $0.2.x < -0.99 } && holes.contains { $0.0 == bay.1.right && $0.2.x > 0.99 }, "\(holes.map { ($0.0, $0.5) })")
        // The basket's runner screws in both sides; the turntable's in the bottom.
        let bh = Self.drills(m, source: try #require(basketIDs.first))
        #expect(bh.filter { $0.0 == bay.1.left }.count == 2 && bh.filter { $0.0 == bay.1.right }.count == 2)
        let th = Self.drills(m, source: try #require(turnIDs.first))
        #expect(th.count == 4 && th.allSatisfy { $0.0 == bay.1.bottom && $0.2.z < -0.99 }, "\(th)")
        // The cabinet gets wider: the rod follows the bay.
        m = try Self.run(m, "Wider") { tx in try FurnitureParameters.setValue("Width", .double(60 * Self.inch), in: tx) }
        let w1 = try #require(m[bay.0.id]?.furnitureBay?.opening?.width)
        #expect(abs((m[r.id]?.params[Parameters.familyParamID("Opening Width")]?.doubleValue ?? 0) - w1) < 1e-6)
    }

    @Test func connectorsPlaceOnPartsWithTheirHoles() throws {
        var m = try Self.cabinet()
        let top = try #require(m.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .top })
        let cam = try Self.def("Cam and Bolt Connector")
        var ids: [ElementID] = []
        m = try Self.run(m, "Cam") { tx in
            ids = try ComponentPlacement.place(cam, hostID: top.id, settings: ComponentSettings(face: .bottom, alignment: .left, offsetX: 0.0, offsetY: 0), in: tx)
        }
        let holes = Self.drills(m, source: try #require(ids.first))
        let housing = try #require(holes.first { $0.5 == "Cam housing" })
        #expect(housing.0 == top.id && abs(housing.3 - 0.015) < 1e-9 && abs(housing.4 - 0.0125) < 1e-9 && housing.2.z > 0.99, "\(housing)")
        #expect(holes.contains { $0.5 == "Cam bolt hole" })
    }

    // MARK: Leg tool

    @Test func legComponentsAreLegTypes() throws {
        let m0 = try #require(FurnitureSamples.tableModel())
        // The template has a Leg type for each Leg Type component's default type.
        let hairpin = try Self.def("Hairpin Leg")
        let legTypes = m0.types(for: .furnitureLegs)
        let t = try #require(ComponentLegTypes.type(hairpin, hairpin.defaultType!.name, m0), "Hairpin Leg is a Leg type")
        #expect(m0[t]?.typeData?.familyName == "Hairpin Leg")
        #expect(ComponentLegTypes.definitions.count >= 20 && legTypes.count >= 9 + 20)
        // Built-in shapes are still all there.
        #expect(Set(legTypes.compactMap { FurniturePartTypes.Values($0.typeData).legShape }) == Set(LegShape.allCases))
        // Give the table's legs the hairpin type: each draws the component, foot on the floor, top under the top.
        let legs = m0.elements(.furnitureLegs)
        let m1 = try Self.run(m0, "Hairpins") { tx in for l in legs { tx.update(l.id) { $0.typeID = t } } }
        for l in legs {
            let e = try #require(m1[l.id]), d = try #require(e.furnitureLeg)
            let b = ElementMeshes.parts(e, m1, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
            #expect(abs(b.min.z - (m1.elevation(ofLevel: e.levelID) + d.base)) < 0.003 && abs(b.max.z - (m1.elevation(ofLevel: e.levelID) + d.top)) < 0.003,
                    "\(b.min.z)…\(b.max.z) vs \(d.base)…\(d.top)")
            #expect(max(b.max.x - b.min.x, b.max.y - b.min.y) > 0.1, "a 4\" spread hairpin")
        }
        // A taller table: the legs follow (Height is bound to the leg).
        let m2 = try Self.run(m1, "Taller") { tx in try FurnitureParameters.setValue("Height", .double(36 * Self.inch), in: tx) }
        let l = try #require(m2[legs[0].id])
        let b2 = ElementMeshes.parts(l, m2, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(b2.max.z - b2.min.z > 33 * Self.inch)
        // Loading another component as Leg types gives one type per size.
        let turned = try Self.def("Turned Leg")
        let m3 = try Self.run(m0, "Load") { tx in #expect(ComponentLegTypes.load(turned, in: tx).count == turned.types.count) }
        #expect(m3.types(for: .furnitureLegs).filter { $0.typeData?.familyName == "Turned Leg" }.count == turned.types.count)
    }

    // MARK: Joints

    static func bookcase() throws -> BIMModel { try #require(FurnitureSamples.bookcaseModel()) }

    static func withRule(_ m: BIMModel, _ pair: JointPairKind, _ type: JointType, _ f: JointFastener) throws -> BIMModel {
        try run(m, "Rule") { tx in
            var r = tx.model.furnitureJointRules
            var rule = r.rule(pair, category: tx.model.furnitureSetup?.category ?? .casework)
            rule.type = type
            rule.parameters = JointParameters(fastener: f.key)
            if let i = r.rules.firstIndex(where: { $0.pair == pair }) { r.rules[i] = rule } else { r.rules.append(rule) }
            try FurnitureJointOperations.setRules(r, in: tx)
        }
    }

    @Test func jointRulesPickConnectorComponents() throws {
        let m0 = try Self.bookcase()
        // Every fastener joint type offers Group B's connectors.
        #expect(FurnitureJointFasteners.options(.camLock).map(\.family).contains("Cam and Bolt Connector"))
        #expect(FurnitureJointFasteners.options(.dowel).map(\.family).contains("Metal Dowel"))
        #expect(FurnitureJointFasteners.options(.confirmat).map(\.family).contains("Cross Dowel"))
        #expect(FurnitureJointFasteners.options(.butt).map(\.family).contains("L-Bracket"))
        #expect(FurnitureJointFasteners.options(.biscuit).map(\.family) == ["Furniture Assembly Clip", "Furniture Assembly Clip"])
        // Side – Top with 12 mm system cams: drilled from the cam's own sizes, counted and priced under its name.
        let cam = try #require(FurnitureJointFasteners.options(.camLock).first { $0.typeName == "Cam and Bolt - 12 mm" })
        let m1 = try Self.withRule(m0, .sideTop, .camLock, cam)
        let ops = FurnitureMachining.entries(m1)
        let cams = ops.filter { $0.label == "Cam lock" }
        #expect(!cams.isEmpty)
        #expect(cams.allSatisfy { if case .drill(_, _, let d, let depth) = $0.op { return abs(d - 0.012) < 1e-9 && abs(depth - 0.0095) < 1e-9 }; return false })
        #expect(ops.contains { if $0.label == "Cam bolt hole", case .drill(_, _, let d, let depth) = $0.op { return abs(d - 0.007) < 1e-9 && abs(depth - 0.024) < 1e-9 }; return false })
        let counts = FurnitureJoints.hardwareCounts(m1)
        #expect(counts.contains { $0.kind == cam.name && $0.count == cams.count }, "\(counts)")
        let line = try #require(FurnitureFabrication.hardware(m1).first { $0.family == "Cam and Bolt Connector" })
        #expect(line.typeName == "Cam and Bolt - 12 mm" && abs(line.unitCost - 0.42) < 1e-9 && line.count == cams.count)
        // Without a fastener the joint drills FM6's 15 mm cam as before.
        let plain = try Self.run(m0, "Cam") { tx in
            var r = tx.model.furnitureJointRules
            if let i = r.rules.firstIndex(where: { $0.pair == .sideTop }) { r.rules[i].type = .camLock; r.rules[i].parameters = JointParameters() }
            else { r.rules.append(JointRule(.sideTop, .camLock)) }
            try FurnitureJointOperations.setRules(r, in: tx)
        }
        #expect(FurnitureMachining.entries(plain).filter { $0.label == "Cam lock" }.allSatisfy { if case .drill(_, _, let d, _) = $0.op { return abs(d - 0.015) < 1e-9 }; return false })
        // Metal dowels: their diameter.
        let dowel = try #require(FurnitureJointFasteners.options(.dowel).first { $0.typeName == "Metal Dowel - 5 x 30 mm" })
        let m2 = try Self.withRule(m0, .sideTop, .dowel, dowel)
        func dia(_ e: MachiningEntry) -> Double { if case .drill(_, _, let d, _) = e.op { return d }; return 0 }
        let dowels = FurnitureMachining.entries(m2).filter { $0.label == "Dowel" }
        let sideTop = FurnitureJoints.joints(m2).filter { $0.pair == .sideTop }.compactMap(\.elementID)
        #expect(dowels.contains { abs(dia($0) - 0.005) < 1e-9 } && dowels.contains { abs(dia($0) - 0.008) < 1e-9 }, "Side – Top dowels are 5 mm, the rest stay 8 mm")
        #expect(sideTop.isEmpty, "by rule")
        #expect(FurnitureJoints.hardwareCounts(m2).contains { $0.kind == dowel.name })
        // Cross dowels with a furniture bolt: the clearance hole, the bolt hole and the cross bore.
        let cross = try #require(FurnitureJointFasteners.options(.confirmat).first { $0.family == "Cross Dowel" })
        let m3 = try Self.withRule(m0, .sideTop, .confirmat, cross)
        let xo = FurnitureMachining.entries(m3)
        #expect(xo.contains { $0.label == "Cross Dowel" } && xo.contains { $0.label == "Bolt clearance" } && xo.contains { $0.label == "Bolt hole" })
        // Corner brackets along a butt joint: a screw in each part per bracket.
        let bracket = try #require(FurnitureJointFasteners.options(.butt).first { $0.family == "Corner Bracket" })
        let m4 = try Self.withRule(m0, .sideTop, .butt, bracket)
        let screws = FurnitureMachining.entries(m4).filter { $0.label == "Bracket screw" }
        let n = FurnitureJoints.hardwareCounts(m4).first { $0.kind == bracket.name }?.count ?? 0
        #expect(n > 0 && screws.count == 2 * n, "\(screws.count) screws for \(n) brackets")
    }

    @Test func aJointsFastenerIsSetInProperties() throws {
        let m0 = try Self.bookcase()
        let s = DocumentSession(model: m0)
        let side = try #require(m0.elements(.furniturePanels).first { $0.furniturePanel?.role == .panel })
        let top = try #require(m0.elements(.furnitureShelves).first { $0.furnitureShelf?.role == .top })
        let j = try #require(FurnitureJoints.joint(side.id, top.id, m0))
        #expect(j.type == .dowel)
        // The part's joint rows list a Fastener choice of dowels.
        let row = try #require(FurnitureJointProperties.partEntries(side, m0).first { $0.id.key == "furniture.partJoint.\(top.id.raw).fastener" })
        guard case .choice(let options) = row.type else { Issue.record("not a choice"); return }
        #expect(options.first == "By Joint Type" && options.contains("Metal Dowel - 6 x 30 mm"))
        _ = s.perform("Fastener") { tx in try Parameters.set(row.id, to: .text("Metal Dowel - 6 x 30 mm"), on: side.id, in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let j1 = try #require(FurnitureJoints.joint(side.id, top.id, s.model))
        #expect(FurnitureJointFasteners.fastener(j1.parameters.fastener)?.family == "Metal Dowel")
        // A connector that doesn't go in a dowel joint is refused.
        _ = s.perform("Bad") { tx in try Parameters.set(row.id, to: .text("Cam and Bolt - 15 mm"), on: side.id, in: tx) }
        #expect(s.lastError != nil)
        // By Joint Type puts it back (and the joint is by rule again).
        _ = s.perform("Back") { tx in try Parameters.set(row.id, to: .text("By Joint Type"), on: side.id, in: tx) }
        #expect(FurnitureJoints.joint(side.id, top.id, s.model)?.parameters.fastener == nil)
        #expect(FurnitureJointOperations.element(j.key, s.model) == nil)
    }

    // MARK: Search

    @Test func searchFindsThemByNameAliasAndSize() throws {
        let c = ComponentSearchIndex(ComponentLibrary.furniture)
        func top(_ q: String, _ n: Int = 3) -> [String] { c.search(q, limit: n).map(\.definition.name) }
        for d in Self.defs {
            #expect(top(d.name, 3).contains(d.name), "\(d.name): \(top(d.name, 3))")
        }
        #expect(top("minifix").first == "Cam and Bolt Connector")
        #expect(top("rafix").first == "Surface Cam Connector")
        #expect(top("closet pole").contains("Clothes Hanging Rod"))
        #expect(top("castor").contains { $0.contains("Caster") })
        #expect(top("oval rail 30 x 15").first == "Oval Wardrobe Rail")
        #expect(top("hair pin leg").first == "Hairpin Leg")
        let caster = try #require(c.search("locking caster 100 mm", limit: 1).first)
        #expect(caster.definition.name == "Locking Caster" && caster.typeName == "Locking Caster - 100 mm Total Lock", "\(caster.typeName ?? "")")
        let pin = try #require(c.search("shelf pin 1/4\"", limit: 1).first)
        #expect(pin.definition.name == FurnitureHardware.shelfPin && pin.typeName == "1/4\" Spoon")
    }
}
