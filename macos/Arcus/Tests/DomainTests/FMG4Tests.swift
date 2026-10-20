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

/// FMG4: a canted front in a loaded family flexed out of square: its hardware turns with the face (not kept at 45°),
/// its elevation swing spans the leaf and turns too, louvered fronts keep their tilted louvers, and CNC Export drills
/// it (hinge cups and handle holes), not only its outline.
@Suite("FMG4 canted fronts") @MainActor
struct FMG4CantTests {
    static let i = 0.0254

    /// A formula's value in a family type (a probe parameter), as a plain number (angles in degrees).
    static func probe(_ f: FamilyDefinition, _ formula: String, type: String? = nil, _ values: [String: Double] = [:]) -> Double? {
        var g = f
        let t = type ?? g.types[0].name
        if let k = g.types.firstIndex(where: { $0.name == t }) { for (n, v) in values { g.types[k].values[n] = .double(v) } }
        for kind in [ParamType.angle, .length, .number] {
            var p = g
            p.parameters.append(FamilyParameter(name: "FMG4 Probe", type: kind, formula: formula))
            let r = FamilyEvaluator.parameterValues(p, typeName: t, units: .imperial)
            if r.errors.isEmpty, case .quantity(let d, _)? = r.values["FMG4 Probe"] { return d }
        }
        return nil
    }

    /// A model coordinate (a plane or a sum of planes) in an evaluated family.
    static func position(_ v: PartValue, _ ev: EvaluatedFamily) -> Double {
        guard v.plane != nil else { return v.value }
        return PlaneTerms.terms(v.plane).reduce(v.constant) { $0 + $1.value * (ev.planes[$1.key] ?? 0) }
    }

    static func corner() throws -> (BIMModel, Element) {
        let m = try #require(FurnitureLibrary.simpleASpecs.first { $0.name == "Corner Cabinet" }).build()
        return (m, try #require(m.elements(.furnitureFronts).first))
    }

    @Test func hardwareAndSwingTurnWithTheCant() throws {
        let (m, door) = try Self.corner()
        let g = try #require(FurnitureFronts.geometry(door, m))
        let a = try #require(CantAnchors(g.opening, g.frame))
        let f = FurnitureCompiler.family(from: m)
        let flex = ["Width": 34 * Self.i, "Depth": 24 * Self.i]
        var g2 = f
        for (k, v) in flex { g2.types[0].values[k] = .double(v) }
        let ev = FamilyEvaluator.evaluate(g2, typeName: g2.types[0].name, units: .imperial)
        #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
        let d = Vec2(Self.position(a.p1.x, ev) - Self.position(a.p0.x, ev), Self.position(a.p1.y, ev) - Self.position(a.p0.y, ev))
        let now = atan2(d.y, d.x) * 180 / .pi
        #expect(abs(now - 45) > 2, "the cant turns when the cabinet is out of square: \(now)")
        let base = atan2(a.p1.y.value - a.p0.y.value, a.p1.x.value - a.p0.x.value) * 180 / .pi
        // Every hinge and the handle: their rotation now is their rotation in the document turned as the cant turned.
        let hardware = f.nestedInstances.filter { inst in [FurnitureHardware.concealedHinge, FurnitureHardware.barPull, FurnitureHardware.knob].contains { inst.familyName.hasPrefix($0) } }
        #expect(!hardware.isEmpty)
        for inst in hardware {
            let r0 = try #require(Self.probe(f, inst.rotation)), r = try #require(Self.probe(f, inst.rotation, flex))
            #expect(abs((r - r0) - (now - base)) < 1e-6, "\(inst.familyName): \(r0) → \(r), the cant \(base) → \(now)")
        }
        // The swing: placed at the leaf's corner, as wide as the leaf on the flexed face, turned with it.
        let swing = try #require(f.nestedInstances.first { $0.familyName.hasPrefix("Elevation Swing") })
        let r = try #require(Self.probe(f, swing.rotation, flex))
        #expect(abs(r - now) < 1e-6, "swing \(r), cant \(now)")
        let width = try #require(swing.bindings["Leaf Width"])
        let w0 = try #require(Self.probe(f, width)), w = try #require(Self.probe(f, width, flex))
        #expect(abs(w0 - g.leaves[0].width) < 1e-6, "\(w0 / Self.i) vs \(g.leaves[0].width / Self.i)")
        let lengthChange = d.length - Vec2(a.p1.x.value - a.p0.x.value, a.p1.y.value - a.p0.y.value).length
        #expect(abs((w - w0) - lengthChange) < 1e-6, "the leaf grows with the cant: \(w0 / Self.i) → \(w / Self.i)")
    }

    @Test func louveredCantedDoorsKeepTheirLouvers() throws {
        let (m, door) = try Self.corner()
        let louvered = try #require(m.types(for: .furnitureFronts).first { $0.typeData?.familyName == "Door" && FurnitureFrontTypes.Values($0.typeData).style == .louvered })
        let s = DocumentSession(model: m)
        _ = s.perform("Louvered") { tx in tx.update(door.id) { $0.typeID = louvered.id } }
        #expect(s.lastError == nil)
        let ctx = PartSolidContext(symbolic: false)
        let ps = FurnitureFrontSolids.solids(s.model[door.id]!, s.model, ctx)
        let louvers = ps.placed.filter { $0.family.solids.first?.name.contains("Louver") == true }
        #expect(louvers.count > 3, "\(louvers.count) louvers")
        #expect(louvers.allSatisfy { abs($0.rotation - 45) < 1e-6 && $0.family.solids.first?.workPlane == .yz })
        #expect(!ps.solids.contains { $0.name.contains("Louver") }, "no louver boxes")
        // Compiled: each louver between the corners, turned and as long as the panel with the cant.
        let f = FurnitureCompiler.family(from: s.model)
        let placed = f.nestedInstances.filter { $0.familyName.hasPrefix("Louver") }
        #expect(placed.count == louvers.count && placed.allSatisfy { Double($0.rotation) == nil && $0.bindings["Length"] != nil })
    }

    @Test func edgeProfileVoidsOnACantedSlabDoorFollowTheFace() throws {
        let (m, door) = try Self.corner()
        let slab = try #require(m.types(for: .furnitureFronts).first { $0.typeData?.familyName == "Door" && FurnitureFrontTypes.Values($0.typeData).style == .slab })
        let s = DocumentSession(model: m)
        _ = s.perform("Profiled slab") { tx in
            tx.update(door.id) { $0.typeID = slab.id }
            tx.update(slab.id) { $0.typeData?.params[FurnitureFrontTypes.edgeProfile] = .text(EdgeProfileShape.roundOver.rawValue) }
        }
        #expect(s.lastError == nil)
        let f = FurnitureCompiler.family(from: s.model)
        let mark = try #require(s.model[door.id]?.mark)
        let edges = f.nestedInstances.filter { $0.familyName.hasPrefix("\(mark) Edge") }
        #expect(edges.count == 4, "\(f.nestedInstances.map(\.familyName))")
        // Along the face (the top and bottom edges): turned with the cant and as long as the leaf on it.
        let along = edges.filter { $0.bindings["Length"].map { $0.contains("sqrt") } == true }
        #expect(along.count == 2 && edges.allSatisfy { Double($0.rotation) == nil }, "\(edges.map(\.rotation))")
    }

    @Test func cncDrillsACantedDoor() throws {
        let (m, door) = try Self.corner()
        // A slab door on the cant (its leaf is one CNC part).
        let slab = try #require(m.types(for: .furnitureFronts).first { $0.typeData?.familyName == "Door" && FurnitureFrontTypes.Values($0.typeData).style == .slab })
        let s = DocumentSession(model: m)
        _ = s.perform("Slab") { tx in tx.update(door.id) { $0.typeID = slab.id } }
        let programs = FurnitureCNC.programs(s.model).filter { $0.part.elementID == door.id }
        #expect(!programs.isEmpty)
        let layers = programs.flatMap { ($0.faceA.circles + ($0.faceB?.circles ?? [])).map(\.layer) }
        #expect(layers.contains { $0.hasPrefix("DRILL_1.378") }, "hinge cups (35 mm): \(Set(layers))")
        // The cups sit along the hinge edge, inside the leaf.
        let p = try #require(programs.first)
        let cups = (p.faceA.circles + (p.faceB?.circles ?? [])).filter { $0.layer.hasPrefix("DRILL_1.378") }
        #expect(cups.count == 2 && cups.allSatisfy { $0.center.x > 0 && $0.center.x < p.part.length && $0.center.y > 0 && $0.center.y < p.part.width }, "\(cups.map(\.center))")
    }
}

/// FMG4: a lid shows its swing in plan (dashed lines from its front corners to the middle of its hinged edge), in the
/// Furniture document's plan and in the loaded family, where it flexes with the lid.
@Suite("FMG4 lid plan swings") @MainActor
struct FMG4LidPlanTests {
    static let i = 0.0254

    @Test func lidsShowTheirSwingInPlan() throws {
        let m = try #require(FurnitureSamples.chestModel())
        let lid = try #require(m.elements(.furnitureFronts).first { FurnitureFronts.geometry($0, m)?.face == .top })
        let segs = FurnitureSwings.lidPlan(lid, m)
        #expect(segs.count == 2)
        let g = try #require(FurnitureFronts.geometry(lid, m))
        let back = g.leaves[0].v.1.value
        #expect(segs.allSatisfy { abs($0.end.y - back) < 1e-9 || abs($0.start.y - back) < 1e-9 }, "they point at the hinge")
        let plan = try #require(m.views.first { $0.view?.kind.isPlan == true })
        let items = ViewGraphicsBuilder(model: m, view: plan).build().items.filter { $0.elementID == lid.id }
        let dashed = items.flatMap(\.primitives).filter { if case .polyline(_, _, let st) = $0 { st.pattern == .dash } else { false } }
        #expect(dashed.count == 2, "\(items.count) items")
        // Loaded: on the lid's planes, so a wider chest gets a wider symbol.
        let f = FurnitureCompiler.family(from: m)
        let lines = f.planLines.filter { $0.subcategory == .elevationSwing }
        #expect(lines.count == 2)
        func span(_ w: Double) -> Double {
            var g = f
            g.types[0].values["Width"] = .double(w * Self.i)
            let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
            let xs = ev.planLines.filter { $0.subcategory == .elevationSwing }.flatMap { [$0.curve.bounds.min.x, $0.curve.bounds.max.x] }
            return (xs.max() ?? 0) - (xs.min() ?? 0)
        }
        #expect(abs((span(42) - span(36)) - 6 * Self.i) < 1e-4, "\(span(36) / Self.i) → \(span(42) / Self.i)")
    }
}

/// FMG4: elevation swings of doors on the front face flex with them in a loaded family (they were fixed lines).
@Suite("FMG4 front swings flex") @MainActor
struct FMG4FrontSwingTests {
    @Test func aWiderCabinetHasWiderSwings() throws {
        let m = try #require(FurnitureSamples.baseCabinetModel())
        let f = FurnitureCompiler.family(from: m)
        let swings = f.nestedInstances.filter { $0.familyName.hasPrefix("Elevation Swing") }
        #expect(swings.count == 2, "a pair of doors: \(swings.count)")
        let w = try #require(f.types[0].values["Width"]?.doubleValue)
        for s in swings {
            let width = try #require(s.bindings["Leaf Width"])
            let a = try #require(FMG4CantTests.probe(f, width)), b = try #require(FMG4CantTests.probe(f, width, ["Width": w + 0.2]))
            #expect(b > a + 0.05, "\(a) → \(b)")
        }
    }
}

/// FMG4: a loaded cabinet's swings in a project elevation are hidden by a wall in front of it (and drawn only where
/// they show past a short one), as a hidden-line elevation hides anything behind another element.
@Suite("FMG4 project swings hidden by walls") @MainActor
struct FMG4ProjectSwingTests {
    @Test func aWallInFrontHidesTheSwings() throws {
        let src = try #require(FurnitureLibrary.essentials.first { $0.name == "Kitchen Cabinet" }).build()
        let f = FurnitureCompiler.family(from: src)
        let s = DocumentSession(model: ProjectTemplates.make(.architectural, units: .imperial).0)
        var fid: ElementID?
        _ = s.perform("Load") { tx in fid = FurnitureLoading.load(f, from: src, replacing: nil, in: tx) }
        let type = try #require(s.model.elements(.elementTypes).first { $0.typeData?.familyID == fid && $0.name == "B30" })
        let wallType = try #require(s.model.types(for: .walls).first)
        var inst: ElementID?, view: ElementID?
        _ = s.perform("Place") { tx in
            inst = tx.create(.casework, data: .component(ComponentData(location: .zero)), typeID: type.id, levelID: tx.model.levels.first?.id)
            var v = ViewData(kind: .elevation, scale: 24)
            v.planeOrigin = Vec3(Vec2(0, -3), z: 0)
            v.viewDirection = Vec2(0, 1)
            v.farClip = 10
            v.detailLevel = .medium
            view = tx.create(.views, name: "Cabinet Front", data: .view(v))
        }
        func dashes() throws -> [Double] {
            let g = ViewGraphicsBuilder(model: s.model, view: try #require(s.model[view])).build()
            return g.items.filter { $0.elementID == inst }.flatMap(\.primitives).compactMap {
                if case .polyline(let p, _, let st) = $0, st.pattern == .dash, p.count == 2 { p[0].distance(to: p[1]) } else { nil }
            }
        }
        let open = try dashes()
        #expect(open.count >= 4, "two leaves, two lines each (broken where a handle is in front): \(open.count)")
        // A short wall in front of the left half: only the right leaf's lines (and what shows past the wall) remain.
        var short: ElementID?
        _ = s.perform("Short wall") { tx in
            short = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(-1, -1), Vec2(0, -1))))), typeID: wallType.id, levelID: tx.model.levels.first?.id)
        }
        #expect(s.lastError == nil)
        let half = try dashes()
        #expect(half.reduce(0, +) < open.reduce(0, +) * 0.75 && !half.isEmpty, "\(open.reduce(0, +)) → \(half.reduce(0, +))")
        // A long one hides them all.
        _ = s.perform("Long wall") { tx in
            tx.delete(short!)
            _ = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(-2, -1), Vec2(2, -1))))), typeID: wallType.id, levelID: tx.model.levels.first?.id)
        }
        #expect(try dashes().isEmpty)
    }
}

/// FMG4: the FMG1 leftovers. A locked dimension between two part faces holds in the loaded family (the following face
/// is put on the plane the other follows); a stretcher joining a turned leg below its pommel gets a square block on the
/// leg and its mortise is cut there at Fine (and compiling stays under 2 s).
@Suite("FMG4 locked faces and turned legs") @MainActor
struct FMG4FMG1Tests {
    static let inch = 0.0254

    @Test func aFaceToFaceLockHoldsInTheLoadedFamily() throws {
        let (s, ids) = FM4Tests.bookcase()
        let plan = FM4Tests.view(s.model, "Plan")
        let left = try #require(ids["left"]), right = try #require(ids["right"])
        // The sides' inside faces locked 34 1/2" apart.
        let d = try #require(FMG1Tests.dimension(s, [.partFace(left, PartFaceRef(axis: .x, atMax: true)), .partFace(right, PartFaceRef(axis: .x, atMax: false))],
                                                 in: plan, at: Vec2(0, -12 * Self.inch)))
        _ = s.perform("Lock") { tx in tx.update(d) { $0.dimension?.locked = true } }
        _ = s.perform("Nudge") { tx in tx.update(d) { $0.dimension?.linePoint.y -= 0.01 } }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let gap = try #require(FMG1Tests.measure(s, d))
        // The right side now follows the plane the left side's face is on.
        let rightBounds = FurniturePartBounds.bounds(of: try #require(s.model[right]))
        let leftPlanes = Set(FurniturePartBounds.bounds(of: try #require(s.model[left])).values.compactMap { if case .plane(let n, _) = $0 { n } else { nil } })
        #expect(rightBounds.values.contains { if case .plane(let n, _) = $0 { leftPlanes.contains(n) } else { false } }, "\(rightBounds)")
        // Loaded and flexed wider: the gap between the faces is kept.
        let f = FurnitureCompiler.family(from: s.model)
        var g = f
        g.types[0].values["Width"] = .double((g.types[0].values["Width"]?.doubleValue ?? 0) + 12 * Self.inch)
        let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
        func solid(_ id: ElementID) -> Box3? { s.model[id].flatMap { e in ev.solids.first { $0.name == e.mark && !$0.isVoid }?.bounds } }
        let l = try #require(solid(left)), r = try #require(solid(right))
        #expect(abs((r.min.x - l.max.x) - gap) < 1e-4, "\((r.min.x - l.max.x) / Self.inch) vs \(gap / Self.inch)")
    }

    @Test func stretchersOnTurnedLegsAreMortisedInABlock() throws {
        for name in ["Decorative Console", "Decorative Bench"] {
            let start = ContinuousClock.now
            let m = try #require(SimpleB.pieces.first { $0.name == name }).make()
            let ctx = PartSolidContext(symbolic: false)
            var blocks = 0, cuts = 0
            for leg in m.elements(.furnitureLegs) {
                let ps = FurniturePartSolids.solids(leg, m, ctx)
                let fam = try #require(ps.placed.first?.family)
                blocks += fam.solids.filter { $0.name.hasPrefix("Block") }.count
                cuts += fam.solids.filter { $0.isVoid && $0.visibleAt == [.fine] }.count
                // The body is cut away at each block (no revolve passes through a mortise).
                if fam.solids.contains(where: { $0.name.hasPrefix("Block") }) { #expect((fam.nestedFamilies.first?.solids.count ?? 0) >= 2) }
            }
            #expect(cuts > 0, "\(name): mortises in the legs")
            let low = m.elements(.furnitureRails).contains { r in
                guard let rd = r.furnitureRail else { return false }
                return rd.w < 0.6 * (FurnitureParameters.value("Height", m).flatMap { if case .quantity(let v, _) = $0 { v } else { nil } } ?? 1)
            }
            if low { #expect(blocks > 0, "\(name): blocks where low stretchers join") }
            let f = FurnitureCompiler.family(from: m)
            #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty, "\(name)")
            let ev = FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial)
            #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
            #expect(ContinuousClock.now - start < .seconds(2), "\(name): \(ContinuousClock.now - start)")
        }
    }
}

/// FMG4: a piece dropped on a 3D view lands on the view's work plane (on a horizontal one at its height, as its
/// Elevation from Level), else on the level.
@Suite("FMG4 3D drop placement")
struct FMG4DropTests {
    @Test func aDropLandsOnTheWorkPlane() {
        let ray = WorkPlane3D.PointerSample(origin: Vec3(0, -10, 10), direction: Vec3(0, 1, -1).normalized)
        // On the level (z = 0): where the ray meets it.
        let onLevel = WorkPlane3D.dropPlacement(ray, workPlane: nil, levelZ: 0)
        #expect(onLevel.map { abs($0.point.y - 0) < 1e-9 && $0.offset == 0 } == true)
        // A horizontal work plane 0.9 m up (a counter): it sits on it.
        let counter = WorkPlaneFrame(origin: Vec3(0, 0, 0.9), u: Vec3(1, 0, 0), v: Vec3(0, 1, 0))
        let up = WorkPlane3D.dropPlacement(ray, workPlane: counter, levelZ: 0)
        #expect(up.map { abs($0.point.y - (-0.9)) < 1e-9 && abs($0.offset - 0.9) < 1e-9 } == true, "\(String(describing: up))")
        // A vertical one (a wall face at y = 2): on the level below where the pointer meets it.
        let wall = WorkPlaneFrame(origin: Vec3(0, 2, 0), u: Vec3(1, 0, 0), v: Vec3(0, 0, 1))
        let w = WorkPlane3D.dropPlacement(ray, workPlane: wall, levelZ: 0)
        #expect(w.map { abs($0.point.y - 2) < 1e-9 && $0.offset == 0 } == true, "\(String(describing: w))")
    }
}

/// FMG4: Part Tag leaders on a shop drawing never cross: the tags in a column are in the order of their parts.
@Suite("FMG4 tag leaders")
struct FMG4TagLeaderTests {
    @Test func leadersDontCross() {
        var rng = SystemRandomNumberGenerator()
        let outline = Rect2(min: Vec2(-0.5, 0), max: Vec2(0.5, 0.8))
        for _ in 0..<40 {
            let parts = (0..<9).map { k in
                (id: ElementID(UInt64(100 + k)), anchor: Vec2(Double.random(in: -0.48...0.48, using: &rng), Double.random(in: 0.02...0.78, using: &rng)))
            }
            let placed = FurnitureTagLayout.layout(parts, outline: outline, obstacles: [], scale: 12)
            #expect(placed.count == parts.count)
            let leaders = placed.map { Segment2($0.elbow ?? $0.head, $0.anchor) }
            for i in leaders.indices { for j in leaders.indices where j > i {
                #expect(leaders[i].intersection(leaders[j]) == nil, "\(placed[i].part) and \(placed[j].part) cross")
            } }
        }
    }
}
