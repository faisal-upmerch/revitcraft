import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// FMG4: the gap batches' open items. Slats keep their spread through their joints in compiled families: the slats
/// stay between their first plane and far side (not at fixed offsets from the first), the slats past the count stay
/// hidden, the legs at the slats' ends aren't run on across the layout, and tenons and mortises follow the slats.
@Suite("FMG4 slats through joints") @MainActor
struct FMG4SlatTests {
    static let inch = 0.0254

    static func compiled(_ name: String) throws -> FamilyDefinition {
        let p = try #require(SimpleB.pieces.first { $0.name == name })
        return FurnitureCompiler.family(from: try p.make())
    }

    static func evaluate(_ f: FamilyDefinition, _ param: String, _ k: Double) -> EvaluatedFamily {
        var g = f
        if let base = g.types[0].values[param]?.doubleValue { g.types[0].values[param] = .double(base * k) }
        return FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
    }

    @Test(arguments: ["Outdoor Side Table", "Garden Bench", "Shoe Bench"])
    func slatsSpreadWithDepthInTheCompiledFamily(_ name: String) throws {
        let f = try Self.compiled(name)
        let base = Self.evaluate(f, "Depth", 1), deep = Self.evaluate(f, "Depth", 1.25), shallow = Self.evaluate(f, "Depth", 0.85)
        for ev in [base, deep, shallow] { #expect(ev.errors.isEmpty, "\(name): \(ev.errors.prefix(2))") }
        let b0 = FMG1Tests.bounds(base)
        for (ev, k) in [(deep, 1.25), (shallow, 0.85)] {
            let b = FMG1Tests.bounds(ev)
            let depth0 = b0.max.y - b0.min.y, depth = b.max.y - b.min.y
            let d = try #require(f.types[0].values["Depth"]?.doubleValue)
            #expect(abs((depth - depth0) - d * (k - 1)) < 1e-3, "\(name) x\(k): \(depth0 / Self.inch) → \(depth / Self.inch)")
            // The last visible slat of the top layout sits at the far side: within a slat of the back.
            let slats = ev.solids.filter { $0.name.hasPrefix("SL1 Slat") && !$0.name.contains("Tenon") && !$0.isVoid }
            let back = slats.map(\.bounds.max.y).max() ?? 0
            #expect(abs(back - b.max.y) < 3.5 * Self.inch, "\(name) x\(k): last slat at \(back / Self.inch), piece back \(b.max.y / Self.inch)")
        }
    }

    @Test func aLegUnderSlatsIsntRunOnAcrossTheLayout() throws {
        let p = try #require(SimpleB.pieces.first { $0.name == "Outdoor Side Table" })
        let m = try p.make()
        let sol = JointSolver.solve(m)
        for leg in m.elements(.furnitureLegs) {
            guard let part = sol.parts[leg.id], let box = sol.finalBoxes[leg.id] else { continue }
            #expect(abs(box.ext(.y) - part.box.size.y) < 1e-6, "\(leg.mark): \(part.box.size.y / Self.inch) → \(box.ext(.y) / Self.inch)")
        }
    }
}

/// FMG4: the template views' scale follows the piece (a standard furniture scale), the template dimensions sit at
/// paper distances outside it, row by row, the elevation markers just outside the plan, and a View Scale the user
/// sets turns the automatic scale off for that view.
@Suite("FMG4 automatic view scale") @MainActor
struct FMG4AutoScaleTests {
    static let inch = 0.0254

    static func set(_ name: String, _ inches: Double, _ m: BIMModel) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: "Size")
        try FurnitureParameters.setValue(name, .double(inches * Self.inch), in: tx)
        return try tx.commit().model
    }

    static func plan(_ m: BIMModel) -> Element { m.views.first { $0.name == "Ref. Level" && $0.view?.kind.isPlan == true }! }

    @Test func theScaleFollowsThePieceSize() throws {
        #expect(FurnitureAutoScale.scale(width: 12 * Self.inch, depth: 4 * Self.inch, height: 8 * Self.inch) == 4)
        #expect(FurnitureAutoScale.scale(width: 36 * Self.inch, depth: 15 * Self.inch, height: 18 * Self.inch) == 8)
        #expect(FurnitureAutoScale.scale(width: 84 * Self.inch, depth: 36 * Self.inch, height: 34 * Self.inch) == 24)
        var m = try Self.set("Width", 36, FurnitureTemplates.blank())
        m = try Self.set("Depth", 15, m)
        m = try Self.set("Height", 18, m)
        #expect(Self.plan(m).view?.scale == 8)
        #expect(m.views.filter { FurnitureAutoScale.isOn($0) }.allSatisfy { $0.view?.scale == 8 })
        // 84" wide: 1/2" = 1'-0" would fit, but at 15" deep 3/4" keeps the text a sixth of the depth.
        m = try Self.set("Width", 84, m)
        #expect(Self.plan(m).view?.scale == 16, "\(Self.plan(m).view?.scale ?? 0)")
        m = try Self.set("Depth", 36, m)
        #expect(Self.plan(m).view?.scale == 24, "\(Self.plan(m).view?.scale ?? 0)")
    }

    @Test func aViewScaleTheUserSetsStays() throws {
        var m = try Self.set("Width", 36, FurnitureTemplates.blank())
        let id = Self.plan(m).id
        let tx = TransactionContext(model: m, name: "View Scale")
        let auto = try #require(m[id]?.view?.scale)
        tx.update(id) { $0.view?.scale = auto == 4 ? 8 : 4 }
        m = try tx.commit().model
        let mine = auto == 4 ? 8 : 4
        #expect(m[id]?.view?.scale == mine)
        #expect(m[id]?.params[FurnitureAutoScale.onParam]?.boolValue == false)
        m = try Self.set("Width", 84, m)
        m = try Self.set("Depth", 36, m)
        #expect(m[id]?.view?.scale == mine)
        #expect(m.views.first { $0.name == "Front" }?.view?.scale == 24)
    }

    @Test func dimensionsSitInRowsAtPaperDistancesAndMarkersOutsideThePlan() throws {
        var m = try Self.set("Width", 84, FurnitureTemplates.blank())
        m = try Self.set("Depth", 36, m)
        let plan = Self.plan(m), s = Double(plan.view!.scale)
        let e = FurniturePlanes.extents(m), mg = FurniturePlanes.margin
        let front = e.y.lowerBound + mg
        let below = m.elements(.dimensions).filter { $0.ownerViewID == plan.id && $0.dimension!.linePoint.y < front }
        let rows = below.map { (front - $0.dimension!.linePoint.y) / s }.sorted()
        #expect(rows.count == 2)
        #expect(abs(rows[0] - FurnitureAutoScale.firstRow) < 1e-6 && abs(rows[1] - (FurnitureAutoScale.firstRow + FurnitureAutoScale.rowGap)) < 1e-6, "\(rows)")
        // The Front elevation's marker: in front of the piece, past the plan's crop and dimensions, inside its annotation crop.
        let fe = try #require(m.views.first { $0.name == "Front" }?.view)
        let marker = try #require(fe.markerPosition)
        #expect(marker.y < front - rows[1] * s)
        let crop = try #require(plan.view?.cropRegion)
        #expect(marker.y > crop.min.y - plan.view!.annotationCropOffset * s)
        #expect(abs((fe.planeOrigin?.y ?? 0) - marker.y) < 1e-9 && abs(fe.planeOrigin?.x ?? 1) < 1e-9) // moved along the view direction only
        // A dimension the user moves is theirs.
        let dim = below[0]
        let tx = TransactionContext(model: m, name: "Move")
        tx.update(dim.id) { $0.dimension?.linePoint.y -= 0.1 }
        m = try tx.commit().model
        let moved = try #require(m[dim.id]?.dimension?.linePoint)
        m = try Self.set("Width", 60, m)
        #expect(m[dim.id]?.dimension?.linePoint.y == moved.y)
        #expect(m[dim.id]?.params[FurnitureAutoScale.rowParam] == nil)
    }
}

/// FMG4: Associate Family Parameter (the = button): Leaf Count with an Integer or Yes/No parameter (a new one made in
/// the dialog too), Visible of parts and fronts with a Yes/No parameter (an optional seat cushion), unassociating, and
/// the compiled family showing the part by the parameter.
@Suite("FMG4 associate family parameter") @MainActor
struct FMG4AssociateTests {
    @Test func leafCountAssociatesWithANewOrExistingParameter() throws {
        let m = try #require(FurnitureLibrary.essentials.first { $0.name == "Kitchen Cabinet" }).build()
        let door = try #require(m.elements(.furnitureFronts).first { $0.furnitureFront?.kind == .door })
        let lc = FurnitureFrontParameters.leafCount.id
        #expect(FurnitureAssociations.compatibleTypes(lc, door) == [.integer, .bool])
        #expect(FurnitureAssociations.compatibleParameters(lc, door, m).map(\.name).contains("Leaf Count"))
        let s = DocumentSession(model: m)
        // A new Yes/No parameter, made and associated in one step: Yes in every type, so every type is a pair.
        _ = s.perform("Associate") { tx in
            try FurnitureAssociations.associate([door.id], lc, with: "Pair", adding: FamilyParameter(name: "Pair", type: .bool, group: .construction), in: tx)
        }
        #expect(s.lastError == nil)
        #expect(FurnitureAssociations.association(lc, s.model[door.id]!) == "Pair")
        #expect(FurnitureFronts.leafCount(s.model[door.id]!, s.model) == 2)
        let entry = Parameters.instanceEntries(s.model[door.id]!, s.model).first { $0.name == "Leaf Count" }
        #expect(entry?.isReadOnly == true && entry?.readOnlyReason?.contains("Pair") == true)
        // A Length parameter isn't compatible; an existing name can't be made again.
        _ = s.perform("Bad") { tx in try FurnitureAssociations.associate([door.id], lc, with: "Width", in: tx) }
        #expect(s.lastError != nil)
        _ = s.perform("Twice") { tx in
            try FurnitureAssociations.associate([door.id], lc, with: "Pair", adding: FamilyParameter(name: "Pair", type: .bool, group: .construction), in: tx)
        }
        #expect(s.lastError != nil)
        // <None>: the door's own (type's) count again.
        _ = s.perform("None") { tx in try FurnitureAssociations.associate([door.id], lc, with: nil, in: tx) }
        #expect(FurnitureAssociations.association(lc, s.model[door.id]!) == nil)
    }

    @Test func theEntrywayBenchCushionIsOptionalByType() throws {
        let m = try #require(FurnitureLibrary.essentials.first { $0.name == "Entryway Bench" }).build()
        #expect(LibraryKit.buildError(m) == nil)
        let setup = try #require(m.furnitureSetup)
        #expect(setup.family.types.map(\.name) == ["36\"", "48\"", "60\""])
        #expect(setup.family.parameter(named: "Seat Cushion")?.type == .bool)
        let cushion = try #require(m.elements(.furnitureForms).first { FurnitureAssociations.association(FurnitureAssociations.visible, $0) == "Seat Cushion" })
        #expect(Parameters.instanceEntries(cushion, m).first { $0.name == "Visible" }?.isReadOnly == true)
        var f = FurnitureCompiler.family(from: m)
        func top(_ f: FamilyDefinition) -> Double { FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial).solids.filter { !$0.isVoid }.map(\.bounds.max.z).max() ?? 0 }
        #expect(abs(top(f) - 18 * 0.0254) < 1e-3, "\(top(f) / 0.0254)")
        f.types[0].values["Seat Cushion"] = .bool(false)
        #expect(abs(top(f) - 16 * 0.0254) < 1e-3, "\(top(f) / 0.0254)")
    }

    @Test func aPartNotVisibleIsLeftOutOfTheLoadedFamily() throws {
        let m = try #require(FurnitureLibrary.essentials.first { $0.name == "Entryway Bench" }).build()
        let s = DocumentSession(model: m)
        let cushion = try #require(m.elements(.furnitureForms).first)
        _ = s.perform("None") { tx in try FurnitureAssociations.associate([cushion.id], FurnitureAssociations.visible, with: nil, in: tx) }
        s.setParameter(FurnitureAssociations.visible, value: .bool(false), on: [cushion.id], name: "Visible")
        let f = FurnitureCompiler.family(from: s.model)
        let ev = FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial)
        #expect((ev.solids.filter { !$0.isVoid }.map(\.bounds.max.z).max() ?? 0) < 16.01 * 0.0254)
    }
}

/// FMG4: drawers on a side face get the stock slide length that fits as the loaded piece flexes (their depth runs
/// along X), as front drawers do along Y.
@Suite("FMG4 side drawers flex") @MainActor
struct FMG4SideDrawerTests {
    static let i = 0.0254

    @Test func sideDrawerBoxesTakeTheSlideThatFits() throws {
        let s = try FMG3Tests.sideOpenBox()
        let left = try #require(BayFrame(view: try FMG3Tests.view(s.model, "Left").view))
        var drawers: [ElementID] = []
        _ = s.perform("Drawers") { tx in
            let bay = try FurnitureBays.createBay(face: .front, at: Vec2(0, 9 * Self.i), frame: left, in: tx)
            drawers = try FurnitureFronts.createFront(.drawer, in: bay, in: tx)
        }
        #expect(s.lastError == nil && drawers.count == 1)
        let mark = try #require(s.model[drawers[0]]?.mark)
        let f = FurnitureCompiler.family(from: s.model)
        func box(_ width: Double) throws -> Double {
            var g = f
            g.types[0].values["Width"] = .double(width * Self.i)
            let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
            #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
            let side = try #require(ev.solids.first { $0.name == "\(mark) Box Left Side" })
            return side.bounds.size.x / Self.i
        }
        let wide = try box(60), narrow = try box(21)
        #expect(abs(wide - 24) < 1e-3, "60\" wide: a 24\" slide, got \(wide)")
        #expect(abs(narrow - 20) < 1e-3, "21\" wide (20 3/4\" clear): a 20\" slide, got \(narrow)")
    }
}
