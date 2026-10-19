import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM8 (full compile and the family round trip): every sample piece (bookcase, table, base cabinet with doors and
/// drawers, a carcass with joints) compiles to a family that, loaded into a project, draws a Coarse outline and
/// Medium/Fine edges in plan, shows its fronts and hardware by detail level in 3D, maps its materials to the project's,
/// and flexes for every type and size (dividers stay equal, hinges follow the door height); reloading keeps the placed
/// instances and their values (Overwrite) or takes the piece's (… and its parameter values); a Furniture Schedule lists
/// Width, Depth, Height, Material and Cost.
@Suite("FM8 Furniture compile and round trip") @MainActor
struct FM8Tests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    /// A carcass of two sides, a top, a bottom and a fixed shelf between them, and a back: joints at every corner.
    static func carcass() throws -> BIMModel {
        let s = DocumentSession(model: FurnitureTemplates.blank(category: .casework, name: "Carcass"))
        var ids: [String: ElementID] = [:]
        _ = s.perform("Sides") { tx in
            let p = FurniturePlanes.positionsByName(tx.model)
            let l = p["Left"]!, r = p["Right"]!, f = p["Front"]!, b = p["Back"]!
            ids["left"] = try FurniturePartOperations.createPanel(start: Vec2(l, f), end: Vec2(l, b), extent: PartExtent(), in: tx)
            ids["right"] = try FurniturePartOperations.createPanel(start: Vec2(r, b), end: Vec2(r, f), extent: PartExtent(), in: tx)
        }
        _ = s.perform("Top and Bottom") { tx in
            let p = FurniturePlanes.positionsByName(tx.model)
            let t = 0.75 * inch
            let inside = [Vec2(p["Left"]! + t, p["Front"]!), Vec2(p["Right"]! - t, p["Front"]!), Vec2(p["Right"]! - t, p["Back"]!), Vec2(p["Left"]! + t, p["Back"]!)]
            ids["top"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Top", offset: 0, role: .top, in: tx)
            ids["bottom"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Bottom", offset: t, role: .bottom, in: tx)
            ids["shelf"] = try FurniturePartOperations.createShelf(boundary: inside, plane: "Bottom", offset: 14 * inch, in: tx)
        }
        _ = s.perform("Lock and Back") { tx in
            try FurnitureSamples.lockToFramingPlanes([ids["top"]!, ids["bottom"]!, ids["shelf"]!], in: tx)
            _ = try FurniturePartOperations.createBack(atFront: Vec2(0, 10 * inch), fit: .inside, in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        return s.model
    }

    static func samples() throws -> [(String, BIMModel)] {
        [("bookcase", try #require(FurnitureSamples.bookcaseModel())), ("table", try #require(FurnitureSamples.tableModel())),
         ("cabinet", try #require(FurnitureSamples.baseCabinetModel())), ("carcass", try carcass())]
    }

    /// A project with `f` loaded from `source` and one instance placed at (2, 3).
    static func project(_ f: FamilyDefinition, _ source: BIMModel) throws -> (DocumentSession, ElementID, ElementID) {
        let project = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)
        var fid: ElementID?
        _ = project.perform("Load") { tx in fid = FurnitureLoading.load(f, from: source, replacing: nil, in: tx) }
        #expect(project.lastError == nil, "\(project.lastError?.message ?? "")")
        let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
        var inst: ElementID?
        _ = project.perform("Place") { tx in
            inst = tx.create(type.typeData!.instanceCategory, data: .component(ComponentData(location: Vec2(2, 3))), typeID: type.id, levelID: project.model.levels.first?.id)
        }
        return (project, try #require(fid), try #require(inst))
    }

    static func meshBounds(_ m: BIMModel, _ id: ElementID, _ d: DetailLevel = .fine) -> Box3 {
        ElementMeshes.parts(m[id]!, m, detail: d).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
    }

    static func planPrimitives(_ m: BIMModel, _ id: ElementID, _ d: DetailLevel) -> [GPrimitive] {
        var pm = m
        var v = m.views.first { $0.view?.kind == .floorPlan && $0.levelID == m[id]?.levelID }!
        v.view?.detailLevel = d
        pm.put(v)
        return ViewGraphicsBuilder(model: pm, view: v).build().items.filter { $0.elementID == id }.flatMap(\.primitives)
    }

    // MARK: Compile fidelity

    @Test func everySampleCompilesFlexesAndPassesTheFlexTest() throws {
        for (name, m) in try Self.samples() {
            let f = FurnitureCompiler.family(from: m)
            #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty, "\(name): \(FamilyEvaluator.flexTest(f, units: .imperial).prefix(3))")
            let ev0 = FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial)
            #expect(ev0.errors.isEmpty, "\(name): \(ev0.errors.prefix(3))")
            // Width, Depth and Height flex the whole piece: fronts and overhangs add a fixed amount, the rest scales.
            for (param, axis) in [("Width", 0), ("Depth", 1), ("Height", 2)] {
                for scale in [0.85, 1.4] { // the bookcase's top fixed shelf sits at 59"
                    var g = f
                    let base = g.types[0].values[param]?.doubleValue ?? 0
                    g.types[0].values[param] = .double(base * scale)
                    let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
                    #expect(ev.errors.isEmpty, "\(name) \(param) x\(scale): \(ev.errors.prefix(2))")
                    let b = ev.bounds, b0 = ev0.bounds
                    let size = [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z][axis]
                    let size0 = [b0.max.x - b0.min.x, b0.max.y - b0.min.y, b0.max.z - b0.min.z][axis]
                    #expect(Self.approx(size - size0, base * (scale - 1), 1e-4), "\(name) \(param) x\(scale): \(size0) → \(size)")
                }
            }
            // Light: Coarse and Medium meshes stay small.
            let tris = { (d: DetailLevel) in ev0.solids.filter { !$0.isVoid && $0.visibleAt.contains(d) }.reduce(0) { $0 + $1.familyMesh.indices.count / 3 } }
            #expect(tris(.coarse) < 600 && tris(.medium) < 1500, "\(name): \(tris(.coarse)) / \(tris(.medium)) triangles")
            #expect(tris(.coarse) <= tris(.medium) && tris(.medium) <= tris(.fine))
        }
    }

    @Test func twoOrMoreDividersStayEqualAsThePieceFlexes() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        let f = FurnitureCompiler.family(from: m)
        // Each divider's centre plane is a formula, so no EQ chain (and no Part Offset parameters) is left to drift.
        #expect(!f.parameters.contains { $0.name.hasPrefix("Part Offset") || $0.name.hasPrefix("Front Offset") }, "\(f.parameters.map(\.name))")
        for w in [30.0, 54, 72, 96] {
            var g = f
            g.types[0].values["Width"] = .double(w * Self.inch)
            let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
            #expect(ev.errors.isEmpty)
            let centres = Set(ev.solids.filter { $0.name.hasPrefix("DV") && !$0.isVoid }.map { (($0.bounds.min.x + $0.bounds.max.x) / 2 / Self.inch * 1000).rounded() / 1000 }).sorted()
            let inside = w / 2 - 0.75
            #expect(centres.count == 2 && Self.approx(centres.first, -inside + 2 * inside / 3, 1e-3) && Self.approx(centres.last, -inside + 4 * inside / 3, 1e-3), "W \(w): \(centres)")
        }
    }

    @Test func hingesFollowTheDoorHeight() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        let f = FurnitureCompiler.family(from: m)
        #expect(f.parameters.contains { $0.name.hasSuffix("Hinge Count") && $0.formula != nil && $0.group == .other })
        func hinges(_ h: Double) -> [Double] {
            var g = f
            g.types[0].values["Height"] = .double(h * Self.inch)
            let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
            return ev.solids.filter { $0.name.hasPrefix(FurnitureHardware.concealedHinge) && $0.name.contains("Plate") && $0.bounds.min.x < 0 }.map { $0.bounds.min.z }.sorted()
        }
        // The doors are 4 1/8" shorter than the cabinet (toe kick and reveals): 2 hinges up to 40", 3 up to 60"…
        for (h, n) in [(34.5, 2), (43.0, 2), (52.0, 3), (75.0, 4), (95.0, 5)] {
            let z = hinges(h)
            #expect(z.count == n, "H \(h): \(z.count) hinges")
            if z.count > 2 { #expect(Self.approx(z[1] - z[0], z[z.count - 1] - z[z.count - 2], 1e-4), "evenly spaced") }
        }
    }

    @Test func plansDrawAnOutlineAtCoarseAndEdgesAtMediumAndFine() throws {
        for (name, m) in try Self.samples() {
            let f = FurnitureCompiler.family(from: m)
            let coarse = f.planLines.filter { $0.visibleAt.contains(.coarse) }
            #expect(coarse.count == 4, "\(name): the outline on Left, Right, Front and Back")
            #expect(coarse.allSatisfy { if case .line(let a, let b) = $0.shape, case .plane = a.x, case .plane = b.y { return true }; return false })
            let medium = f.planLines.filter { $0.visibleAt.contains(.medium) }
            #expect(medium.count >= 4, "\(name): \(medium.count) Medium lines")
            #expect(f.planLines.filter { $0.visibleAt.contains(.fine) }.count >= medium.count - 1)
            let (p, _, inst) = try Self.project(f, m)
            let c = Self.planPrimitives(p.model, inst, .coarse), fi = Self.planPrimitives(p.model, inst, .fine)
            #expect(c.count == 4 && fi.count >= 4, "\(name): plan \(c.count) / \(fi.count)")
            // The outline is the piece's Width x Depth, where it was placed.
            let pts = c.flatMap { p -> [Vec2] in if case .polyline(let ps, _, _) = p { return ps }; return [] }
            let r = Rect2(points: pts)
            let w = f.types[0].values["Width"]?.doubleValue ?? 0, d = f.types[0].values["Depth"]?.doubleValue ?? 0
            #expect(Self.approx(r.width, w, 1e-6) && Self.approx(r.height, d, 1e-6) && Self.approx(r.center.x, 2, 1e-6) && Self.approx(r.center.y, 3, 1e-6), "\(name): \(r)")
        }
        // The table's top hides its legs and aprons from above.
        let tableModel = try #require(FurnitureSamples.tableModel())
        let table = FurnitureCompiler.family(from: tableModel)
        #expect(table.planLines.filter { $0.visibleAt.contains(.medium) }.count == 4)
        // The base cabinet: carcass, door and drawer edges in front of it, and the swings at Medium and Fine only.
        let cabinetModel = try #require(FurnitureSamples.baseCabinetModel())
        let cab = FurnitureCompiler.family(from: cabinetModel)
        #expect(cab.planLines.filter { $0.visibleAt.contains(.medium) && $0.subcategory != .swing }.count > 8)
        #expect(cab.planLines.filter { $0.subcategory == .swing }.allSatisfy { $0.visibleAt == [.medium, .fine] })
        // Medium plan lines follow the flex: a wider cabinet's lines reach its new sides.
        var wide = cab
        wide.types[0].values["Width"] = .double(72 * Self.inch)
        let ev = FamilyEvaluator.evaluate(wide, typeName: wide.types[0].name, units: .imperial)
        let xs = ev.planLines.filter { $0.visibleAt.contains(.medium) }.flatMap { l -> [Double] in if case .line(let s) = l.curve { return [s.start.x, s.end.x] }; return [] }
        #expect(Self.approx(xs.max(), 36 * Self.inch, 1e-5) && Self.approx(xs.min(), -36 * Self.inch, 1e-5), "\(xs.min() ?? 0) … \(xs.max() ?? 0)")
    }

    @Test func detailLevelsShowFrontsAndHardwareAtMediumAndMachiningAtFine() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        let (p, _, inst) = try Self.project(FurnitureCompiler.family(from: m), m)
        let coarse = ElementMeshes.parts(p.model[inst]!, p.model, detail: .coarse)
        let medium = ElementMeshes.parts(p.model[inst]!, p.model, detail: .medium)
        let fine = ElementMeshes.parts(p.model[inst]!, p.model, detail: .fine)
        #expect(coarse.count < medium.count && medium.count < fine.count, "\(coarse.count) \(medium.count) \(fine.count)")
        // Fronts stand proud of the carcass at Medium, not at Coarse.
        let cb = coarse.reduce(Box3.empty) { $0.union($1.mesh.bounds) }, mb = medium.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(mb.min.y < cb.min.y - 0.5 * Self.inch)
        // Every material is a project material, the hardware's included.
        let names = Set(fine.compactMap { $0.materialID.flatMap { p.model[$0]?.material != nil ? p.model[$0]?.name : nil } })
        #expect(names.isSuperset(of: ["Plywood", "Steel"]), "\(names)")
        #expect(fine.allSatisfy { $0.materialID == nil || p.model[$0.materialID]?.material != nil })
    }

    @Test func materialsMapToProjectMaterialsCreatingMissingOnes() throws {
        let m = try #require(FurnitureSamples.tableModel())
        let f = FurnitureCompiler.family(from: m)
        let project = DocumentSession(model: ProjectTemplates.make(.empty, units: .imperial).0)
        #expect(project.model.elements(.materials).first { $0.name == "Solid Maple" } == nil)
        var fid: ElementID?
        _ = project.perform("Load") { tx in fid = FurnitureLoading.load(f, from: m, replacing: nil, in: tx) }
        let type = try #require(project.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
        let fam = try #require(project.model[fid]?.family)
        for p in fam.parameters { guard case .elementRef(.materials) = p.type else { continue }
            #expect(project.model[type.typeData?.params[Parameters.familyParamID(p.name)]?.refValue]?.material != nil, "\(p.name)")
        }
        #expect(project.model.elements(.materials).contains { $0.name == "Solid Maple" })
        // A material parameter changed in the project changes the instance's material.
        let ply = try #require(project.model.elements(.materials).first { $0.name == "Plywood" }?.id)
        let topParam = try #require(fam.parameters.first { $0.name.contains("Butcher Block") }?.name)
        _ = project.perform("Material") { tx in tx.update(type.id) { $0.typeData?.params[Parameters.familyParamID(topParam)] = .ref(ply) } }
        var inst: ElementID?
        _ = project.perform("Place") { tx in inst = tx.create(.furniture, data: .component(ComponentData(location: .zero)), typeID: type.id, levelID: project.model.levels.first?.id) }
        #expect(ElementMeshes.parts(project.model[inst!]!, project.model).contains { $0.materialID == ply })
    }

    // MARK: Flex in the project

    @Test func typeAndInstanceParametersFlexInTheProject() throws {
        var m = try #require(FurnitureSamples.bookcaseModel())
        let tx = TransactionContext(model: m, name: "Types")
        try FurnitureParameters.edit(tx) { s in
            _ = FamilyEditing.addType(&s.family, named: "48\" Wide", copying: s.currentType)
            if let i = s.family.types.firstIndex(where: { $0.name == "48\" Wide" }) { s.family.types[i].values["Width"] = .double(48 * Self.inch) }
            s.family.parameters.append(FamilyParameter(name: "Clearance", type: .length, isInstance: true, group: .dimensions))
        }
        m = try tx.commit().model
        let f = FurnitureCompiler.family(from: m)
        #expect(f.types.count == 2 && f.parameter(named: "Clearance")?.isInstance == true)
        #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty)
        let (p, fid, inst) = try Self.project(f, m)
        let types = p.model.elements(.elementTypes).filter { $0.typeData?.familyID == fid }
        #expect(types.count == 2)
        let wide = try #require(types.first { $0.name == "48\" Wide" })
        let b0 = Self.meshBounds(p.model, inst)
        _ = p.perform("Change Type") { tx in tx.update(inst) { $0.typeID = wide.id } }
        let b1 = Self.meshBounds(p.model, inst)
        #expect(Self.approx((b1.max.x - b1.min.x) - (b0.max.x - b0.min.x), 12 * Self.inch, 1e-5), "\(b0) → \(b1)")
        // Edit Type: Height on the project type.
        _ = p.perform("Edit Type") { tx in tx.update(wide.id) { $0.typeData?.params[Parameters.familyParamID("Height")] = .double(84 * Self.inch) } }
        let b2 = Self.meshBounds(p.model, inst)
        #expect(Self.approx(b2.max.z - b2.min.z, 84 * Self.inch, 1e-5))
        // Properties: grouped as Revit groups them, Cost in Identity Data from the estimate (per type).
        let entries = Parameters.typeEntries(p.model[wide.id]!, p.model)
        #expect(entries.first { $0.name == "Width" }?.group == .dimensions)
        #expect(entries.contains { $0.group == .materials && $0.name.hasSuffix("Material") })
        let cost = entries.first { $0.name == "Cost" }
        #expect(cost?.group == .identity && (cost?.value?.doubleValue ?? 0) > 0)
        let narrow = try #require(types.first { $0.name != wide.name })
        let narrowCost = Parameters.typeEntries(narrow, p.model).first { $0.name == "Cost" }?.value?.doubleValue ?? 0
        #expect((cost?.value?.doubleValue ?? 0) > narrowCost, "the wider type costs more")
        #expect(Parameters.instanceEntries(p.model[inst]!, p.model).contains { $0.name == "Clearance" && $0.group == .dimensions })
    }

    // MARK: Reload

    @Test func reloadKeepsInstancesAndTheirValuesOrTakesThePiecesValues() throws {
        var m = try #require(FurnitureSamples.bookcaseModel())
        let tx = TransactionContext(model: m, name: "Instance parameter")
        try FurnitureParameters.edit(tx) { $0.family.parameters.append(FamilyParameter(name: "Clearance", type: .length, isInstance: true)) }
        m = try tx.commit().model
        let (p, fid, inst) = try Self.project(FurnitureCompiler.family(from: m), m)
        let type = try #require(p.model.elements(.elementTypes).first { $0.typeData?.familyID == fid })
        _ = p.perform("Values") { tx in
            tx.update(inst) { $0.params[Parameters.familyParamID("Clearance")] = .double(2 * Self.inch); $0.params[.comments] = .text("By the window") }
            tx.update(type.id) { $0.typeData?.params[Parameters.familyParamID("Depth")] = .double(16 * Self.inch) }
        }
        // Edit Family: the source, made taller, compiled and reloaded over the family.
        let loaded = try #require(p.model[fid]?.family)
        let source = try #require(FurnitureCompiler.source(of: loaded))
        #expect(source.isFurniture && source.allElements.count == m.allElements.count)
        let etx = TransactionContext(model: source, name: "Taller")
        try FurnitureParameters.setValue("Height", .double(80 * Self.inch), in: etx)
        let edited = try etx.commit().model
        let f2 = FurnitureCompiler.family(from: edited)
        for mode in FamilyReloadMode.allCases {
            let s = DocumentSession(model: p.model)
            _ = s.perform("Reload") { tx in _ = FurnitureLoading.load(f2, from: edited, replacing: fid, mode: mode, in: tx) }
            #expect(s.lastError == nil)
            #expect(s.model.elements(.families).filter { $0.name == f2.name }.count == 1)
            let e = try #require(s.model[inst], "the placed instance stays")
            #expect(e.typeID == type.id && e.params[Parameters.familyParamID("Clearance")]?.doubleValue == 2 * Self.inch && e.params[.comments]?.textValue == "By the window")
            let t = try #require(s.model[type.id]?.typeData)
            let depth = t.params[Parameters.familyParamID("Depth")]?.doubleValue ?? 0, height = t.params[Parameters.familyParamID("Height")]?.doubleValue ?? 0
            switch mode {
            case .keepProjectValues: #expect(Self.approx(depth, 16 * Self.inch) && Self.approx(height, 72 * Self.inch), "Overwrite the existing version keeps the project's values")
            case .overwriteValues: #expect(Self.approx(depth, 12 * Self.inch) && Self.approx(height, 80 * Self.inch), "… and its parameter values takes the piece's")
            }
            // The instance is drawn with the reloaded family; the family carries the edited source.
            #expect(!ElementMeshes.parts(e, s.model).isEmpty)
            #expect(s.model[fid]?.family.flatMap(FurnitureCompiler.source)?.furnitureSetup?.family.types.first?.values["Height"]?.doubleValue == 80 * Self.inch)
        }
    }

    // MARK: Schedules and cost

    @Test func furnitureScheduleListsSizesMaterialAndCost() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        let (p, _, _) = try Self.project(FurnitureCompiler.family(from: m), m)
        var def = ScheduleDefinition(kind: .category, categories: [.casework], fields: FurnitureScheduleFields.defaults())
        def.grandTotals = true
        var sid: ElementID?
        _ = p.perform("Schedule") { tx in sid = tx.create(.schedules, name: "Casework Schedule", data: .schedule(def)) }
        #expect(def.fields.map(\.heading) == ["Family and Type", "Level", "Width", "Depth", "Height", "Material", "Cost", "Count"])
        let schedule = try #require(sid.flatMap { p.model[$0] })
        let csv = ScheduleEngine.csv(ScheduleEngine.compute(schedule, p.model))
        #expect(csv.contains("4'") && csv.contains("6\""), "Width 54\": \(csv)")
        #expect(csv.contains("Plywood"), "\(csv)")
        let cost = FurnitureCostEstimate.cost(of: m)
        #expect(cost > 100 && cost < 2000, "\(cost)")
        #expect(csv.contains(String(Int(cost))), "\(csv)")
    }

    @Test func costEstimateFollowsSizeAndHardware() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        let base = FurnitureCostEstimate.cost(of: m)
        let tx = TransactionContext(model: m, name: "Wider")
        try FurnitureParameters.setValue("Width", .double(72 * Self.inch), in: tx)
        let wide = try tx.commit().model
        #expect(FurnitureCostEstimate.cost(of: wide) > base)
        let hardware = m.elements(.furnitureHardware).reduce(0) { $0 + FurnitureHardware.values(of: $1, m).cost }
        #expect(hardware > 0 && base > hardware)
        let byType = FurnitureCostEstimate.costs(byType: m)
        #expect(byType.count == m.furnitureSetup?.family.types.count && Self.approx(byType.values.first, base, 0.01))
    }

    // MARK: Library

    @Test func templateURLsGoUnderTheirRoom() {
        let root = URL(fileURLWithPath: "/tmp/fm8-templates")
        #expect(FurnitureLibraryCatalog.templateURL(name: "Hall Bench", room: "Entryway", root: root).path == "/tmp/fm8-templates/Entryway/Hall Bench.arcusfurniture")
        #expect(FurnitureLibraryCatalog.templateURL(name: "Shelf 1/2", room: FurnitureLibraryCatalog.myTemplatesRoom, root: root).path == "/tmp/fm8-templates/Shelf 1-2.arcusfurniture")
        let rooms = FurnitureLibraryCatalog.templateRooms([])
        #expect(rooms.last == FurnitureLibraryCatalog.myTemplatesRoom && rooms.contains("Kitchen"))
    }
}
