import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// COMPC: Group C of the Furniture Component Library (10 Kitchen, 11 Table & Desk, 12 Bed, 13 Sofa, 14 Chair): every
/// definition builds and validates, every type evaluates to sane geometry, key parameters flex it, it fits the sample
/// cabinet bay, desk, bed or chair it's meant for, and search finds it.
@Suite("COMPC component library group C")
struct COMPCTests {
    static let defs = ComponentsC.all
    static let inch = 0.0254

    static func bounds(_ d: ComponentDefinition, _ type: String? = nil, _ inst: [String: ParamValue] = [:], detail: DetailLevel = .fine) -> Box3 {
        let ev = FamilyEvaluator.evaluate(d.family, typeName: type ?? d.defaultType!.name, instance: inst)
        var b = Box3.empty
        for s in ev.solids where !s.isVoid && s.visibleAt.contains(detail) && s.visibleIn3D { b.include(s.bounds) }
        return b
    }

    @Test func groupCoversEveryCategoryWithItsCounts() {
        var counts: [ComponentCategory: Int] = [:]
        for d in Self.defs { counts[d.category, default: 0] += 1 }
        // The owner's list: 28 kitchen (+ Sink Cutout), 27 table & desk, 17 bed, 19 sofa, 19 chair.
        #expect(counts[.kitchen] == 29 && counts[.tables] == 27 && counts[.beds] == 17 && counts[.sofas] == 19 && counts[.chairs] == 19, "\(counts)")
        #expect(Set(Self.defs.map(\.category)).isSubset(of: [.kitchen, .tables, .beds, .sofas, .chairs]))
        let names = Self.defs.map(\.name)
        #expect(Set(names).count == names.count, "duplicate names")
        let ids = Self.defs.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids")
    }

    @Test func everyDefinitionValidates() {
        for d in Self.defs {
            let problems = ComponentKit.validate(d)
            #expect(problems.isEmpty, "\(d.name): \(problems.prefix(4))")
            #expect((1...4).contains(d.types.count), "\(d.name): \(d.types.count) types")
            #expect(!d.aliases.isEmpty && d.tags.count >= 3, "\(d.name): tags and aliases")
            #expect(!d.materials.isEmpty, "\(d.name): no material slot")
            #expect(!d.symbols.isEmpty, "\(d.name): no 2D symbol")
            #expect(d.symbols.contains { $0.levels.contains(.coarse) }, "\(d.name): no Coarse symbol")
            #expect(!d.placement.hosts.isEmpty, "\(d.name): no host rule")
            #expect(d.manufacturer == "Generic")
            for t in d.types {
                #expect(t.cost >= 0 && !t.model.isEmpty && t.sku.hasPrefix("GEN-") && t.manufacturer == "Generic", "\(d.name) / \(t.name): catalogue data")
            }
        }
    }

    @Test func everyTypeEvaluatesToSaneGeometry() {
        var empty: [String] = []
        defer { #expect(empty.isEmpty, "solids without a mesh: \(empty.count): \(empty.prefix(12))") }
        for d in Self.defs {
            for t in d.types {
                let ev = FamilyEvaluator.evaluate(d.family, typeName: t.name)
                #expect(ev.errors.isEmpty, "\(d.name) / \(t.name): \(ev.errors.prefix(3))")
                for s in ev.solids where !s.isVoid {
                    if s.familyMesh.isEmpty { empty.append("\(d.name) / \(t.name): \(s.name)") }
                }
                let b = Self.bounds(d, t.name)
                #expect(b.min.x.isFinite && b.max.x.isFinite, "\(d.name) / \(t.name): empty")
                let size = b.max - b.min
                #expect(size.x < 3.2 && size.y < 3.2 && size.z < 3.2, "\(d.name) / \(t.name): \(size) too big")
                #expect(max(size.x, size.y, size.z) > 0.004, "\(d.name) / \(t.name): \(size) too small")
            }
        }
    }

    @Test func registeredWithoutNameClashes() {
        let all = ComponentLibrary.furniture
        for d in Self.defs {
            let r = all.first { $0.name == d.name }
            #expect(r != nil, "\(d.name) is in the registry")
            #expect(r?.category == d.category, "\(d.name) clashes with another group's \(r?.category.title ?? "")")
        }
    }

    @Test func presetsEvaluateAndMoveTheGeometry() {
        var count = 0
        for d in Self.defs {
            for p in d.presets {
                count += 1
                let ev = FamilyEvaluator.evaluate(d.family, typeName: p.typeName, instance: p.values)
                #expect(ev.errors.isEmpty, "\(d.name) · \(p.name): \(ev.errors.prefix(2))")
                for k in p.values.keys { #expect(d.parameter(named: k)?.isInstance == true, "\(d.name) · \(p.name): \(k) is an instance parameter") }
                let before = FamilyEvaluator.evaluate(d.family, typeName: p.typeName).solids.filter { !$0.isVoid }.map(\.bounds)
                let after = ev.solids.filter { !$0.isVoid }.map(\.bounds)
                let reshaped = before.count != after.count
                let moved = !reshaped && zip(before, after).contains { (($0.min - $1.min).length + ($0.max - $1.max).length) > 0.002 }
                #expect(moved || reshaped || p.name.contains("Left") || p.name.contains("Right"), "\(d.name) · \(p.name) changes nothing")
            }
        }
        #expect(count >= 35)
    }

    // MARK: Flexing

    /// Every definition has parameters that change its geometry: each type parameter that is a plain length and
    /// either sizes the piece or positions part of it.
    @Test func keyParametersFlexTheGeometry() {
        for d in Self.defs {
            let t = d.defaultType!
            let base = Self.bounds(d, t.name)
            var flexed: [String] = []
            for p in d.parameters where p.type == .length && p.formula == nil && !p.isInstance {
                guard let v = t.values[p.name]?.doubleValue, v > 0 else { continue }
                var td = d.family
                guard let k = td.types.firstIndex(where: { $0.name == t.name }) else { continue }
                td.types[k].values[p.name] = .double(v * 1.3)
                let ev = FamilyEvaluator.evaluate(td, typeName: t.name)
                var b = Box3.empty
                for s in ev.solids where !s.isVoid && s.visibleAt.contains(.fine) { b.include(s.bounds) }
                if (b.min - base.min).length + (b.max - base.max).length > 1e-4 { flexed.append(p.name) }
            }
            #expect(!flexed.isEmpty, "\(d.name): no type parameter changes its size")
        }
    }

    @Test func pullOutsSizeToTheBayAndBinsCount() throws {
        let pantry = try #require(Self.defs.first { $0.name == "Pull-Out Pantry" })
        let narrow = Self.bounds(pantry, nil, ["Opening Width": .double(0.164)]), wide = Self.bounds(pantry, nil, ["Opening Width": .double(0.414)])
        #expect(abs((wide.max.x - wide.min.x) - (narrow.max.x - narrow.min.x) - 0.25) < 0.002, "the frame follows the opening width")
        let trash = try #require(Self.defs.first { $0.name == "Pull-Out Trash Bin" })
        for (type, bins) in [("Pull-Out Trash Bin - Single 35 L - 300 mm", 1), ("Pull-Out Trash Bin - Double 2 x 35 L - 450 mm", 2), ("Pull-Out Trash Bin - Triple 3 x 18 L - 600 mm", 3)] {
            let ev = FamilyEvaluator.evaluate(trash.family, typeName: type)
            #expect(ev.solids.filter { $0.name.hasPrefix("Bin ") && !$0.name.contains("Rim") }.count == bins, "\(type)")
            let b = Self.bounds(trash, type)
            let w = try #require(trash.type(named: type)?.values["Opening Width"]?.doubleValue)
            #expect(b.min.x >= -1e-6 && b.max.x <= w + 1e-6, "\(type) fits its opening")
        }
        let tall = try #require(Self.defs.first { $0.name == "Tall Pantry Pull-Out" })
        let five = FamilyEvaluator.evaluate(tall.family, typeName: "Tall Pantry Pull-Out - 300 mm").solids.filter { $0.name.hasSuffix("Floor") }.count
        let six = FamilyEvaluator.evaluate(tall.family, typeName: "Tall Pantry Pull-Out - 600 mm").solids.filter { $0.name.hasSuffix("Floor") }.count
        #expect(five == 5 && six == 6)
    }

    @Test func mechanismsMoveByTheirInstanceParameters() throws {
        /// The height of a definition's geometry: Z in the plan frame, Y (up the face) on a face.
        func height(_ name: String, _ inst: [String: ParamValue] = [:], type: String? = nil) throws -> Double {
            let d = try #require(Self.defs.first { $0.name == name })
            let b = Self.bounds(d, type, inst)
            return d.frame == .face ? b.max.y - b.min.y : b.max.z - b.min.z
        }
        // Electric desk: 29" to 44" lifts the frame by 15".
        #expect(abs(try height("Electric Standing Desk Frame", ["Desk Height": .double(44 * Self.inch)]) - height("Electric Standing Desk Frame") - 15 * Self.inch) < 0.002)
        // Gas lift: extension adds to the length; the 150 mm type is longer than the 100 mm.
        #expect(abs(try height("Gas Lift Cylinder", ["Extension": .double(0.12)]) - height("Gas Lift Cylinder") - 0.06) < 0.001)
        #expect(try height("Gas Lift Cylinder", type: "Gas Lift Cylinder - 150 mm Stroke") > height("Gas Lift Cylinder", type: "Gas Lift Cylinder - 100 mm Stroke"))
        // Gas-lift bed: opening raises the arm's end.
        #expect(try height("Gas Lift Bed Mechanism", ["Open Angle": .double(40 * .pi / 180)]) > height("Gas Lift Bed Mechanism") + 0.5)
        // Murphy bed: closed it stands up, open it lies down.
        #expect(try height("Murphy Bed Mechanism") > height("Murphy Bed Mechanism", ["Open Angle": .double(.pi / 2)]) + 1.2)
        // Five-star base: the 700 mm type is wider than the 600 mm.
        let base = try #require(Self.defs.first { $0.name == "Five-Star Chair Base" })
        let b6 = Self.bounds(base, "Five-Star Chair Base - 600 mm Nylon"), b7 = Self.bounds(base, "Five-Star Chair Base - 700 mm Aluminum")
        #expect(abs((b7.max.x - b7.min.x) - (b6.max.x - b6.min.x) - 0.1 * 0.951) < 0.01, "arms reach the diameter")
        // Slat base: a king has more width than a twin and its slats follow the count.
        let slats = try #require(Self.defs.first { $0.name == "Bed Slat System" })
        let twin = FamilyEvaluator.evaluate(slats.family, typeName: "Bed Slat System - Twin").solids.filter { $0.name.hasPrefix("Slat ") }.count
        #expect(twin == Int((75 * Self.inch / 0.075).rounded()))
        // Recliner: reclined, the footrest reaches out in front.
        let rec = try #require(Self.defs.first { $0.name == "Recliner Mechanism" })
        #expect(Self.bounds(rec, nil, ["Reclined": .bool(true)]).min.y < Self.bounds(rec).min.y - 0.3)
    }

    @Test func electronicsCarryPowerDataAndCutouts() {
        let electrical = Self.defs.filter { $0.electrical != nil }
        let names = Set(electrical.map(\.name))
        for n in ["Desk Power Module", "Desk USB Charging Module", "In-Desk Wireless Charger", "Electric Standing Desk Frame", "Electric Recliner Mechanism", "Desk Task Light",
                  "Appliance Lift Mechanism"] {
            #expect(names.contains(n), "\(n) has power data")
        }
        for d in electrical {
            #expect(d.roles.contains(.electrical) && d.parameter(named: "Power") != nil && d.parameter(named: "Voltage") != nil, "\(d.name)")
            #expect(!(d.electrical?.supply.isEmpty ?? true) && !(d.electrical?.cable.isEmpty ?? true), "\(d.name): supply and cable")
        }
        // Grommets, modules and sinks cut the host (a through pocket or bore and a void), not themselves.
        for n in ["Desk Cable Grommet", "Desk Power Module", "Desk USB Charging Module", "Sink Cutout"] {
            guard let d = Self.defs.first(where: { $0.name == n }) else { Issue.record("\(n) missing"); continue }
            #expect(d.mounting.contains { op in
                switch op {
                case .drill(_, _, _, _, _, let through, _), .pocket(_, _, _, _, _, _, let through, _): through
                default: false
                }
            }, "\(n) cuts through the top")
            let voids = d.family.solids.filter(\.isVoid)
            #expect(!voids.isEmpty && voids.allSatisfy { $0.cuts == [] }, "\(n): the cutout void cuts only the host")
            let ev = FamilyEvaluator.evaluate(d.family, typeName: d.defaultType!.name)
            #expect(ev.solids.filter { !$0.isVoid }.count == d.family.solids.filter { !$0.isVoid && ($0.visibilityParameter == nil) }.count
                    || ev.solids.contains { !$0.isVoid }, "\(n) keeps its own solids")
        }
        // The grommet's sizes: 60 and 80 mm.
        let g = Self.defs.first { $0.name == "Desk Cable Grommet" }
        #expect(g?.types.map { $0.values["Hole Diameter"]?.doubleValue ?? 0 }.contains(0.06) == true && g?.types.map { $0.values["Hole Diameter"]?.doubleValue ?? 0 }.contains(0.08) == true)
    }

    // MARK: Placement

    /// A table-like piece (top, legs at the corners, aprons) standing in for a desk, a bed frame or a chair seat.
    static func tableLike(_ name: String, width: Double, depth: Double, height: Double) throws -> BIMModel {
        var m = FurnitureTemplates.blank(category: .furniture, name: name)
        let tx = TransactionContext(model: m, name: name)
        let ids = try FurnitureSamples.table(in: tx, width: width, depth: depth, height: height)
        m = try tx.commit().model
        let tx2 = TransactionContext(model: m, name: "Legs and Rails")
        try FurnitureSamples.tableFinish(in: tx2, ids)
        return try tx2.commit().model
    }

    /// The sample pieces: a base cabinet (bays, doors, drawers), a desk, a bed frame and a chair.
    static let samples: [String: BIMModel] = {
        var out: [String: BIMModel] = [:]
        out["cabinet"] = FurnitureSamples.baseCabinetModel()
        out["desk"] = try? tableLike("Desk", width: 60, depth: 30, height: 29)
        out["bed"] = try? tableLike("Bed", width: 62, depth: 82, height: 14)
        out["chair"] = try? tableLike("Chair", width: 18, depth: 18, height: 18)
        out["corner"] = try? cornerBase()
        return out
    }()

    /// A 36" x 36" corner base: one carcass and one bay, for the corner systems.
    static func cornerBase() throws -> BIMModel {
        var m = FurnitureTemplates.blank(category: .casework, name: "Corner Base")
        let tx = TransactionContext(model: m, name: "Corner Base")
        try FurnitureSamples.baseCabinet(in: tx, width: 36, depth: 36, height: 34.5)
        m = try tx.commit().model
        let tx2 = TransactionContext(model: m, name: "Bay")
        _ = try FurnitureBays.createBay(face: .front, at: Vec2(0, 20 * inch), in: tx2)
        return try tx2.commit().model
    }

    static func sample(for d: ComponentDefinition) -> String {
        d.subcategory == "Corner Systems" ? "corner" : sample(for: d.category)
    }

    static func sample(for c: ComponentCategory) -> String {
        switch c {
        case .kitchen: "cabinet"
        case .tables: "desk"
        case .beds: "bed"
        default: "chair"
        }
    }

    /// The first host in a sample piece that the definition goes on (the category's piece first, then the cabinet);
    /// nil host = the floor.
    static func host(for d: ComponentDefinition) -> (model: BIMModel, host: Element?)? {
        for key in [sample(for: d), "cabinet"] {
            guard let m = samples[key] else { continue }
            for kind in d.placement.hosts {
                if kind == .floor { return (m, nil) }
                let hosts = m.allElements.filter { !$0.isType && ComponentPlacement.hostKind($0, m) == kind }
                // Bays: the door bay (the drawer bay is full of drawers); others: the first.
                if let h = kind == .bay ? hosts.first(where: { b in m.hosted(by: b.id).contains { $0.furnitureFront?.kind == .door } }) ?? hosts.first : hosts.first {
                    return (m, h)
                }
            }
        }
        return nil
    }

    @Test func everyComponentPlacesOnItsSampleHost() throws {
        #expect(Self.samples.count == 5, "sample pieces build")
        var failures: [String] = []
        for d in Self.defs {
            guard let (m0, host) = Self.host(for: d) else { failures.append("\(d.name): no sample host"); continue }
            let tx = TransactionContext(model: m0, name: "Place \(d.name)")
            var extra: [String: ParamValue] = [:]
            // Bay items also take the bay's depth and height (placement sets the width).
            if let h = host, let op = h.furnitureBay?.opening, d.frame == .legacyOpening {
                if d.parameter(named: "Opening Depth") != nil { extra["Opening Depth"] = .double(op.y1 - op.y0) }
                if d.parameter(named: "Opening Height") != nil { extra["Opening Height"] = .double(op.z1 - op.z0) }
            }
            let ids: [ElementID]
            do { ids = try ComponentPlacement.place(d, hostID: host?.id, values: extra, in: tx) } catch { failures.append("\(d.name): \(error)"); continue }
            guard let m = try? tx.commit().model else { failures.append("\(d.name): commit failed"); continue }
            guard !ids.isEmpty, let e = m[ids[0]] else { failures.append("\(d.name): nothing placed"); continue }
            if e.hostID != host?.id { failures.append("\(d.name): not hosted by its host") }
            if ComponentDocument.definition(of: e, m)?.id != d.id { failures.append("\(d.name): instance lost its definition") }
            let eb = ids.compactMap { m[$0] }.reduce(Box3.empty) { b, x in ElementMeshes.parts(x, m, detail: .fine).reduce(b) { $0.union($1.mesh.bounds) } }
            guard eb.min.x <= eb.max.x else { failures.append("\(d.name): no geometry once placed"); continue }
            guard let h = host, let hm = m[h.id] else { continue }
            if let op = hm.furnitureBay?.opening {
                // Inside the bay across its width and height (pull-outs may reach out of the front).
                let tol = 0.02
                let lo = BayFrame(hm.furnitureBay!).world(Vec3(op.x0, op.y0, op.z0)), hi = BayFrame(hm.furnitureBay!).world(Vec3(op.x1, op.y1, op.z1))
                if eb.min.x < min(lo.x, hi.x) - tol || eb.max.x > max(lo.x, hi.x) + tol || eb.min.z < min(lo.z, hi.z) - tol || eb.max.z > max(lo.z, hi.z) + tol {
                    failures.append("\(d.name): \(eb) outside the bay \(lo)…\(hi)")
                }
                if let w = m[ids[0]]?.params[Parameters.familyParamID("Opening Width")]?.doubleValue, abs(w - (op.x1 - op.x0)) > 1e-6 {
                    failures.append("\(d.name): Opening Width \(w) is not the bay's \(op.x1 - op.x0)")
                }
            } else {
                // On the host: touching or overlapping its box.
                let hb = ElementMeshes.bounds(hm, m)
                let gap = max(0, hb.min.x - eb.max.x, eb.min.x - hb.max.x) + max(0, hb.min.y - eb.max.y, eb.min.y - hb.max.y) + max(0, hb.min.z - eb.max.z, eb.min.z - hb.max.z)
                if gap > 0.012 { failures.append("\(d.name): \(String(format: "%.3f", gap)) m away from its \(ComponentPlacement.hostKind(hm, m)?.rawValue ?? "host")") }
            }
        }
        #expect(failures.isEmpty, "\(failures.count) placement problems: \(failures)")
    }

    @Test func compatibilityChecksCatchTheWrongBay() throws {
        // A 28" lazy susan in a 17" cabinet bay is flagged; in the 36" corner base it fits.
        let susan = try #require(Self.defs.first { $0.name == "Lazy Susan" })
        let cab = try #require(Self.samples["cabinet"]), corner = try #require(Self.samples["corner"])
        let narrow = try #require(cab.allElements.first { ComponentPlacement.hostKind($0, cab) == .bay })
        let wide = try #require(corner.allElements.first { ComponentPlacement.hostKind($0, corner) == .bay })
        #expect(!ComponentChecks.requirements(susan, typeName: nil, host: narrow, kind: .bay, face: .bottom, cab).isEmpty)
        #expect(ComponentChecks.requirements(susan, typeName: nil, host: wide, kind: .bay, face: .bottom, corner).isEmpty,
                "\(ComponentChecks.requirements(susan, typeName: nil, host: wide, kind: .bay, face: .bottom, corner).map(\.message))")
        // A desk frame too wide for a 30" top is flagged.
        let frame = try #require(Self.defs.first { $0.name == "Desk Frame" })
        let chair = try #require(Self.samples["chair"])
        let seat = try #require(chair.allElements.first { ComponentPlacement.hostKind($0, chair) == .top })
        #expect(!ComponentChecks.requirements(frame, typeName: nil, host: seat, kind: .top, face: .bottom, chair).isEmpty)
    }

    @Test func underTopHardwareHangsBelowAndTopHardwareSitsOnTop() throws {
        let m0 = try #require(Self.samples["desk"])
        let top = try #require(m0.allElements.first { ComponentPlacement.hostKind($0, m0) == .top })
        let tb = ElementMeshes.bounds(top, m0)
        func placed(_ name: String) throws -> Box3 {
            let d = try #require(Self.defs.first { $0.name == name })
            let tx = TransactionContext(model: m0, name: name)
            let ids = try ComponentPlacement.place(d, hostID: top.id, in: tx)
            let m = try tx.commit().model
            return ids.compactMap { m[$0] }.reduce(Box3.empty) { b, x in ElementMeshes.parts(x, m, detail: .fine).reduce(b) { $0.union($1.mesh.bounds) } }
        }
        let frame = try placed("Desk Frame")
        #expect(abs(frame.max.z - tb.min.z) < 0.002, "the frame is under the top")
        #expect(frame.min.z < tb.min.z - 0.6, "and reaches down to the floor")
        let grommet = try placed("Desk Cable Grommet")
        #expect(grommet.max.z > tb.max.z && grommet.max.z < tb.max.z + 0.005, "the cap sits on the top")
        #expect(grommet.min.z < tb.max.z - 0.01, "the liner goes down through it")
        let tray = try placed("Desk Cable Tray")
        #expect(tray.max.z <= tb.min.z + 0.001, "the cable tray hangs under the top")
    }

    @Test func mountingBecomesMachiningOnTheHost() throws {
        let m0 = try #require(Self.samples["desk"])
        let top = try #require(m0.allElements.first { ComponentPlacement.hostKind($0, m0) == .top })
        let thickness = ElementMeshes.bounds(top, m0).max.z - ElementMeshes.bounds(top, m0).min.z
        let tx = TransactionContext(model: m0, name: "Grommet and Power")
        for name in ["Desk Cable Grommet", "Desk Power Module", "Desk Frame"] {
            _ = try ComponentPlacement.place(try #require(Self.defs.first { $0.name == name }), hostID: top.id, in: tx)
        }
        let m = try tx.commit().model
        let ops = FurnitureMachining.entries(m).filter { $0.partID == top.id }
        let bore = ops.first { $0.label == "Grommet hole" }
        if case .drill(_, let axis, let dia, let depth)? = bore?.op {
            #expect(abs(dia - 0.06) < 1e-6 && abs(depth - thickness) < 1e-4 && axis.z < -0.99, "a 60 mm bore through the top")
        } else { Issue.record("no grommet bore") }
        #expect(ops.contains { if case .pocket(let o, _, let depth) = $0.op { return o.count == 4 && abs(depth - thickness) < 1e-4 && $0.label == "Power module cutout" }; return false })
        #expect(ops.filter { $0.label == "Top screw" }.count == 4, "the desk frame's arm screws")
    }

    // MARK: Search

    @Test func searchFindsEveryComponentByNameAndAlias() {
        let index = ComponentSearchIndex(ComponentLibrary.furniture)
        var misses: [String] = []
        for d in Self.defs {
            if !index.search(d.name, limit: 3).contains(where: { $0.definition.id == d.id }) { misses.append(d.name) }
            if let a = d.aliases.first, !index.search(a, limit: 8).contains(where: { $0.definition.id == d.id }) { misses.append("\(d.name) as “\(a)”") }
        }
        #expect(misses.isEmpty, "not found: \(misses)")
        func first(_ q: String) -> String? { index.search(q, limit: 1).first?.definition.name }
        #expect(first("lazy susan") == "Lazy Susan")
        #expect(first("standing desk") == "Electric Standing Desk Frame")
        #expect(first("ottoman bed lift") == "Gas Lift Bed Mechanism")
        #expect(first("5 star base") == "Five-Star Chair Base")
        #expect(index.search("gas lift 150 mm", limit: 3).contains { $0.definition.name == "Gas Lift Cylinder" && $0.typeName == "Gas Lift Cylinder - 150 mm Stroke" })
        #expect(index.search("grommet 80 mm", limit: 3).contains { $0.definition.name == "Desk Cable Grommet" && $0.typeName == "Desk Cable Grommet - 80 mm" })
        #expect(index.search("", filter: ComponentSearchFilter(category: .chairs)).count >= 19)
    }
}
