import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FM6 (Furniture joints): the joint solver finds every pair of touching or overlapping parts, applies Joint Rules
/// unless the user set the joint, trims the parts so nothing overlaps, sizes each part for cutting (with groove depths
/// and tenons), machines the holes, grooves and shelf-pin rows, counts the hardware, and compiles without overlaps.
@Suite("FM6 Furniture joints") @MainActor
struct FM6Tests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }
    static func position(_ m: BIMModel, _ name: String) -> Double { FurniturePlanes.positionsByName(m)[name] ?? .nan }

    /// The part's 3D box at a detail level (its mesh bounds).
    static func meshBox(_ m: BIMModel, _ id: ElementID?, _ detail: DetailLevel = .coarse) -> Box3 {
        FurniturePartMeshes.meshParts(m[id]!, m, detail: detail).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
    }
    /// The volume two boxes share.
    static func shared(_ a: Box3, _ b: Box3) -> Double {
        let dx = min(a.max.x, b.max.x) - max(a.min.x, b.min.x), dy = min(a.max.y, b.max.y) - max(a.min.y, b.min.y), dz = min(a.max.z, b.max.z) - max(a.min.z, b.min.z)
        return dx > 0 && dy > 0 && dz > 0 ? dx * dy * dz : 0
    }
    /// True when two extrusions share volume: sample points of their boxes' overlap inside both profiles.
    static func solidsMeet(_ a: EvaluatedFamily.Solid, _ b: EvaluatedFamily.Solid) -> Bool {
        let o = Box3(min: Vec3(max(a.bounds.min.x, b.bounds.min.x), max(a.bounds.min.y, b.bounds.min.y), max(a.bounds.min.z, b.bounds.min.z)),
                     max: Vec3(min(a.bounds.max.x, b.bounds.max.x), min(a.bounds.max.y, b.bounds.max.y), min(a.bounds.max.z, b.bounds.max.z)))
        guard o.max.x - o.min.x > 1e-6, o.max.y - o.min.y > 1e-6, o.max.z - o.min.z > 1e-6 else { return false }
        func inside(_ s: EvaluatedFamily.Solid, _ p: Vec3) -> Bool {
            guard s.mesh == nil else { return s.bounds.contains(p) }
            return p.z > s.zMin && p.z < s.zMax && s.profile.outer.contains(p.xy)
        }
        for i in 1...3 { for j in 1...3 { for k in 1...3 {
            let p = Vec3(o.min.x + (o.max.x - o.min.x) * Double(i) / 4, o.min.y + (o.max.y - o.min.y) * Double(j) / 4, o.min.z + (o.max.z - o.min.z) * Double(k) / 4)
            if inside(a, p) && inside(b, p) { return true }
        } } }
        return false
    }
    static func parts(_ m: BIMModel) -> [Element] { [Category.furniturePanels, .furnitureShelves, .furnitureLegs, .furnitureRails].flatMap { m.elements($0) } }

    /// A box of four panels drawn as a rectangle (clockwise, outside faces out), 30" x 16" x 24" high.
    static func rectangleBox() -> (DocumentSession, [ElementID]) {
        let s = DocumentSession(model: FurnitureTemplates.blank(name: "Box"))
        var ids: [ElementID] = []
        _ = s.perform("Rectangle") { tx in
            let r = Rect2(min: Vec2(-15 * inch, -8 * inch), max: Vec2(15 * inch, 8 * inch))
            ids = try FurniturePartOperations.createPanelRectangle(r, extent: PartExtent(topPlane: nil, height: 24 * inch), in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        return (s, ids)
    }

    static func bookcase() -> (BIMModel, [String: ElementID]) {
        var m = FurnitureTemplates.blank(category: .casework, name: "Bookcase")
        let tx = TransactionContext(model: m, name: "Bookcase")
        let ids = try! FurnitureSamples.bookcase(in: tx)
        m = try! tx.commit().model
        let tx2 = TransactionContext(model: m, name: "Finish")
        try! FurnitureSamples.bookcaseFinish(in: tx2, ids)
        m = try! tx2.commit().model
        var all = ids
        all["back"] = m.elements(.furniturePanels).first { $0.furniturePanel?.role == .back }?.id
        all["plinth"] = m.elements(.furniturePanels).first { $0.furniturePanel?.role == .plinth }?.id
        return (m, all)
    }

    // MARK: Solver

    @Test func rectangleOfPanelsNoLongerOverlapsAtTheCorners() {
        let (s, ids) = Self.rectangleBox()
        let m = s.model
        let joints = FurnitureJoints.joints(m)
        #expect(joints.count == 4, "\(joints.map { "\($0.key) \($0.pair)" })")
        #expect(joints.allSatisfy { $0.pair == .sideSide && $0.isCorner && $0.type == .dowel })
        // Drawn overlapping: the rule (Longer runs through) decides; the 30" front and back run through the 16" ends.
        for j in joints {
            let t = m[j.throughID]!.furniturePanel!, o = m[j.otherID]!.furniturePanel!
            #expect(t.length > o.length)
        }
        for i in ids.indices { for k in ids.indices where k > i { #expect(Self.shared(Self.meshBox(m, ids[i]), Self.meshBox(m, ids[k])) < 1e-12) } }
        // Every part at Fine too (dowels don't add solids).
        for i in ids.indices { for k in ids.indices where k > i { #expect(Self.shared(Self.meshBox(m, ids[i], .fine), Self.meshBox(m, ids[k], .fine)) < 1e-12) } }
        // The ends are cut 1 1/2" shorter than drawn; the outside stays 30" x 16".
        let all = ids.reduce(Box3.empty) { $0.union(Self.meshBox(m, $1)) }
        #expect(Self.approx(all.max.x - all.min.x, 30 * Self.inch) && Self.approx(all.max.y - all.min.y, 16 * Self.inch))
        let end = ids.first { m[$0]!.furniturePanel!.length < 20 * Self.inch }!
        let cut = FurnitureJoints.cutSize(of: end, in: m)!
        #expect(Self.approx(cut.length, 24 * Self.inch) && Self.approx(cut.width, 14.5 * Self.inch) && Self.approx(cut.thickness, 0.75 * Self.inch), "\(cut)")
    }

    @Test func eachPairKindGetsItsRule() {
        let (m, ids) = Self.bookcase()
        func joint(_ a: String, _ b: String) -> FurnitureJoint? { FurnitureJoints.joint(ids[a]!, ids[b]!, m) }
        #expect(joint("left", "top")?.pair == .sideTop && joint("left", "top")?.type == .dowel)
        #expect(joint("left", "top")?.throughID == ids["left"], "drawn between the sides: the sides run through")
        #expect(joint("right", "bottom")?.pair == .sideBottom && joint("right", "bottom")?.type == .dowel)
        #expect(joint("left", "back")?.pair == .sideBack && joint("left", "back")?.type == .groove)
        #expect(joint("top", "back")?.pair == .sideBack && joint("bottom", "back")?.type == .groove)
        #expect(joint("shelf1", "back")?.pair == .shelfBack && joint("shelf1", "back")?.type == .butt)
        #expect(joint("shelf1", "back")?.throughID == ids["back"])
        #expect(joint("left", "shelf1") == nil, "adjustable shelves sit on pins")
        #expect(joint("plinth", "bottom")?.pair == .plinthCarcass && joint("plinth", "bottom")?.type == .pocketScrew)
        // The table: mortise and tenon aprons into the legs, dowelled legs, pocket-screwed aprons.
        let t = FurnitureSamples.tableModel()!
        let js = FurnitureJoints.joints(t)
        #expect(js.filter { $0.pair == .railLeg && $0.type == .mortiseTenon }.count == 8, "\(js.map { "\($0.pair) \($0.type)" })")
        #expect(js.filter { $0.pair == .topLeg && $0.type == .dowel }.count == 4)
        #expect(js.filter { $0.pair == .railTop && $0.type == .pocketScrew }.count == 4)
        #expect(js.filter { $0.pair == .railLeg }.allSatisfy { t[$0.throughID]?.furnitureLeg != nil })
    }

    @Test func furnitureCategoryDefaultsDiffer() {
        let r = FurnitureJointRules.defaults(.furniture)
        #expect(r.rule(.shelfSide, category: .furniture).type == .dowel && r.rule(.railLeg, category: .furniture).type == .mortiseTenon)
        let c = FurnitureJointRules.defaults(.casework)
        #expect(c.rule(.shelfSide, category: .casework).type == .dado && c.rule(.sideBack, category: .casework).type == .groove)
    }

    @Test func jointRulesChangeEveryJointOfAKind() {
        let (m, ids) = Self.bookcase()
        let s = DocumentSession(model: m)
        _ = s.perform("Joint Rules") { tx in
            var rules = tx.model.furnitureJointRules
            rules.rules = rules.rules.map { var r = $0; if r.pair == .sideTop || r.pair == .sideBottom { r.type = .camLock }; return r }
            try FurnitureJointOperations.setRules(rules, in: tx)
        }
        #expect(s.lastError == nil)
        let j = FurnitureJoints.joint(ids["left"]!, ids["top"]!, s.model)!
        #expect(j.type == .camLock)
        // 12" deep: cams 37 mm in from the front and back, at most 12" apart: two per joint, three holes each.
        let entries = FurnitureMachining.entries(s.model).filter { $0.source == .joint(ids["top"]!) && $0.partID == ids["top"] }
        #expect(entries.filter { $0.label == "Cam lock" }.count == 2 * 2, "both sides: \(entries.map(\.label))")
        let cams = FurnitureJoints.hardwareCounts(s.model).first { $0.kind == "Cam Lock 15 mm" }?.count
        #expect(cams == 8, "sides to top and bottom, two each")
    }

    // MARK: Override, Next/Previous

    @Test func setJointOverridesTheRuleAndNextCyclesThroughPartAndType() throws {
        let (m, ids) = Self.bookcase()
        let s = DocumentSession(model: m)
        let left = ids["left"]!, top = ids["top"]!
        let j0 = try #require(FurnitureJoints.joint(left, top, s.model))
        #expect(j0.isCorner && j0.throughID == left && !j0.isUserSet)
        // Next: the same type with the top running through: the top runs over the side, the side stops under it.
        _ = s.perform("Next") { tx in try FurnitureJointOperations.cycle(j0.key, by: 1, in: tx) }
        let j1 = try #require(FurnitureJoints.joint(left, top, s.model))
        #expect(j1.isUserSet && j1.throughID == top && j1.type == .dowel, "\(j1.type) \(j1.throughID)")
        let side = Self.meshBox(s.model, left), tb = Self.meshBox(s.model, top)
        #expect(Self.approx(side.max.z, tb.min.z) && Self.approx(tb.min.x, Self.position(s.model, "Left")), "\(side) \(tb)")
        #expect(Self.shared(side, tb) < 1e-12)
        // Previous goes back; the joint is then as the rule makes it, and its element goes.
        _ = s.perform("Previous") { tx in try FurnitureJointOperations.cycle(j1.key, by: -1, in: tx) }
        let j2 = try #require(FurnitureJoints.joint(left, top, s.model))
        #expect(j2.throughID == left && !j2.isUserSet && s.model.elements(.furnitureJoints).isEmpty)
        // Miter from the Options Bar: both run to the corner and meet on the diagonal.
        _ = s.perform("Miter") { tx in try FurnitureJointOperations.set(j0.key, type: .miter, in: tx) }
        let j3 = try #require(FurnitureJoints.joint(left, top, s.model))
        #expect(j3.type == .miter)
        let sm = Self.meshBox(s.model, left), tm = Self.meshBox(s.model, top)
        #expect(Self.approx(sm.max.z, 72 * Self.inch) && Self.approx(tm.min.x, Self.position(s.model, "Left")))
        let vol = FurniturePartMeshes.meshParts(s.model[left]!, s.model, detail: .coarse).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        let full = 12 * 72 * 0.75 * pow(Self.inch, 3)
        #expect(Self.approx(vol, full - 0.5 * 0.75 * 0.75 * 12 * pow(Self.inch, 3), 1e-9), "loses the triangle")
        // A T joint can't miter: the raised bottom stays butted.
        let jb = try #require(FurnitureJoints.joint(left, ids["bottom"]!, s.model))
        #expect(!jb.isCorner && !jb.configurations.contains { $0.type == .miter })
    }

    @Test func disallowJoinLeavesTheEndUnjoined() throws {
        let (s, ids) = Self.rectangleBox()
        let before = FurnitureJoints.joints(s.model).count
        let end = try #require(FurnitureJoints.joints(s.model).first)
        _ = s.perform("Disallow Join") { tx in try FurnitureJointOperations.disallow(end.key, in: tx) }
        #expect(FurnitureJoints.joints(s.model).count == before - 1)
        _ = s.perform("Allow Join") { tx in FurnitureJointOperations.allowJoins(ids, in: tx) }
        #expect(FurnitureJoints.joints(s.model).count == before)
        _ = s.perform("Disallow Join") { tx in FurnitureJointOperations.disallowJoins([ids[0]], in: tx) }
        #expect(FurnitureJoints.joints(s.model).count == before - 2, "both ends of the part")
    }

    // MARK: Cut sizes

    @Test func cutSizesIncludeDadoDepthsAndTenons() throws {
        // A fixed shelf is dadoed 1/4" into each side: cut 1/2" longer than the space between them.
        let (m0, ids) = Self.bookcase()
        let s = DocumentSession(model: m0)
        _ = s.perform("Fix Shelf") { tx in tx.update(ids["shelf2"]!) { $0.furnitureShelf?.adjustable = false; $0.furnitureShelf?.pins = nil } }
        let m = s.model
        let j = try #require(FurnitureJoints.joint(ids["left"]!, ids["shelf2"]!, m))
        #expect(j.pair == .shelfSide && j.type == .dado)
        let cut = try #require(FurnitureJoints.cutSize(of: ids["shelf2"]!, in: m))
        #expect(Self.approx(cut.length, 34.5 * Self.inch + 0.5 * Self.inch), "\(cut.length / Self.inch)")
        // It also stops at the back's face: 12" less the 1/4" setback and the 1/4" back.
        #expect(Self.approx(cut.width, 11.5 * Self.inch), "\(cut.width / Self.inch)")
        // The Fine 3D shows the dado in the side and the tongue in it; Coarse doesn't.
        let fine = FurniturePartMeshes.meshParts(m[ids["left"]!]!, m, detail: .fine).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        let coarse = FurniturePartMeshes.meshParts(m[ids["left"]!]!, m, detail: .coarse).reduce(0) { $0 + abs($1.mesh.signedVolume) }
        #expect(coarse - fine > 0.2 * Self.inch * 0.7 * Self.inch * 11 * Self.inch, "the dado and the back groove are cut at Fine")
        #expect(FurniturePartMeshes.meshParts(m[ids["shelf2"]!]!, m, detail: .fine).count == 3, "the shelf and its two tongues")
        // Table aprons: 1" tenons each end (shortened to stay clear of the other apron's tenon in the leg).
        let t = FurnitureSamples.tableModel()!
        let apron = try #require(t.elements(.furnitureRails).first)
        let jr = FurnitureJoints.joints(t).filter { $0.otherID == apron.id && $0.pair == .railLeg }
        #expect(jr.count == 2)
        let clear = Self.meshBox(t, apron.id).max.x - Self.meshBox(t, apron.id).min.x
        let rcut = try #require(FurnitureJoints.cutSize(of: apron.id, in: t))
        let tenon = (rcut.length - max(clear, Self.meshBox(t, apron.id).max.y - Self.meshBox(t, apron.id).min.y)) / 2
        #expect(tenon > 0.6 * Self.inch && tenon <= 1 * Self.inch, "\(tenon / Self.inch)")
        #expect(FurniturePartParameters.instance(for: apron).isEmpty == false)
        #expect(FurnitureJoints.cutSizeText(apron.id, t).contains("x"))
    }

    @Test func widthChangeKeepsTheJointsAndResizesTheCuts() throws {
        // FM4's bookcase: shelves picked from the sides' inside faces follow them as Width changes.
        let (s, ids) = FM4Tests.bookcase()
        let m = s.model
        let n = FurnitureJoints.joints(m).count
        #expect(n >= 6)
        let before = try #require(FurnitureJoints.cutSize(of: ids["top"]!, in: m))
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(48 * Self.inch), in: tx) }
        #expect(s.lastError == nil)
        #expect(FurnitureJoints.joints(s.model).count == n)
        let after = try #require(FurnitureJoints.cutSize(of: ids["top"]!, in: s.model))
        #expect(Self.approx(after.length - before.length, 12 * Self.inch, 1e-6), "\(after.length / Self.inch) \(before.length / Self.inch)")
        // A user-set joint survives the change too.
        _ = s.perform("Miter") { tx in try FurnitureJointOperations.set(JointKey(ids["left"]!, ids["top"]!), type: .miter, in: tx) }
        _ = s.perform("Width") { tx in try FurnitureParameters.setValue("Width", .double(40 * Self.inch), in: tx) }
        #expect(FurnitureJoints.joint(ids["left"]!, ids["top"]!, s.model)?.type == .miter)
    }

    // MARK: Machining

    @Test func dowelsAreSpacedByTheRule() throws {
        let (m, ids) = Self.bookcase()
        let j = try #require(FurnitureJoints.joint(ids["left"]!, ids["top"]!, m))
        let e = FurnitureMachining.entries(m).filter { $0.source == .joint(ids["top"]!) && $0.label == "Dowel" }
        // 12" deep, 1 1/2" from each end, at most 6" apart: three dowels, a hole in each part for each, at both sides.
        #expect(e.count == 12, "\(e.count)")
        let inSide = e.filter { $0.partID == ids["left"] }
        #expect(inSide.count == 3)
        let ys = inSide.compactMap { entry -> Double? in if case .drill(let c, let axis, let d, let depth) = entry.op { #expect(Self.approx(d, 0.008) && depth > 0.01 && axis.x < -0.99); return c.y } else { return nil } }.sorted()
        let f = Self.position(m, "Front")
        #expect(Self.approx(ys[0] - f, 1.5 * Self.inch) && Self.approx(ys[1] - f, 6 * Self.inch) && Self.approx(ys[2] - f, 10.5 * Self.inch), "\(ys.map { ($0 - f) / Self.inch })")
        #expect(j.parameters.diameter == 0.008)
        // The holes sit in the side's inside face, mid-thickness of the top.
        if case .drill(let c, _, _, _)? = inSide.first?.op {
            #expect(Self.approx(c.x, Self.position(m, "Left") + 0.75 * Self.inch) && Self.approx(c.z, 72 * Self.inch - 0.375 * Self.inch))
        }
        // A fixed count overrides the spacing.
        let s = DocumentSession(model: m)
        _ = s.perform("Count") { tx in try FurnitureJointOperations.set(j.key, parameters: JointParameters(count: 4), in: tx) }
        let el = try #require(s.model.elements(.furnitureJoints).first)
        #expect(FurnitureMachining.entries(s.model).filter { $0.source == .joint(el.id) && $0.label == "Dowel" }.count == 8, "the user's joint is the source")
        // Grooves for the back and a mortise per apron end.
        let grooves = FurnitureMachining.entries(m).filter { if case .groove = $0.op { return $0.label == "Groove" }; return false }
        #expect(grooves.count == 4, "sides, top and bottom: \(grooves.count)")
        let t = FurnitureSamples.tableModel()!
        #expect(FurnitureMachining.entries(t).filter { $0.label == "Mortise" }.count == 8)
        #expect(FurnitureMachining.entries(t).filter { $0.label == "Pocket" }.count >= 8)
    }

    @Test func shelfPinRowsAreDrilledInTheSides() {
        let (m, ids) = Self.bookcase()
        let pins = FurnitureMachining.entries(m).filter { $0.label == "Shelf pin" }
        // Four adjustable shelves, two rows in each side, 9 holes a row (4 above, 4 below, one under the shelf).
        #expect(pins.count == 4 * 2 * 2 * 9, "\(pins.count)")
        #expect(Set(pins.map(\.partID)) == [ids["left"]!, ids["right"]!])
        #expect(pins.allSatisfy { if case .shelfPins = $0.source { return true }; return false })
        let left = pins.filter { $0.partID == ids["left"] }
        let ys = Set(left.compactMap { e -> Int? in if case .drill(let c, _, _, _) = e.op { return Int((c.y * 10000).rounded()) }; return nil })
        #expect(ys.count == 2, "a front and a back row")
        #expect(FurnitureJoints.hardwareCounts(m).first { $0.kind == "Shelf Pin 5 mm" }?.count == 16)
    }

    @Test func hardwareCountsAddUpFasteners() {
        let (m, _) = Self.bookcase()
        let h = Dictionary(uniqueKeysWithValues: FurnitureJoints.hardwareCounts(m).map { ($0.kind, $0.count) })
        // Sides to top and bottom: 3 dowels each. Plinth: pocket screws to the bottom and sides.
        #expect(h["Dowel 5/16\" x 1 3/16\""] == 12, "\(h)")
        #expect((h["Pocket Screw 1 1/4\""] ?? 0) > 0)
    }

    // MARK: Compile

    @Test func compiledFamilyHasNoOverlapsAndCutsOnlyAtFine() throws {
        let (m, _) = Self.bookcase()
        let f = FurnitureCompiler.family(from: m)
        let ev = FamilyEvaluator.evaluate(f, typeName: f.types[0].name, units: .imperial)
        #expect(ev.errors.isEmpty, "\(ev.errors.prefix(3))")
        for level in [DetailLevel.coarse, .fine] {
            let solids = ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(level) }
            for i in solids.indices {
                for k in solids.indices where k > i {
                    // Solids of one part (a side and its uncut copy) aren't compared.
                    let a = solids[i], b = solids[k]
                    guard a.name.split(separator: " ").first != b.name.split(separator: " ").first else { continue }
                    #expect(!Self.solidsMeet(a, b), "\(level): \(a.name) / \(b.name)")
                }
            }
        }
        // Voids are Fine only; at Coarse the sides are whole.
        #expect(f.solids.filter(\.isVoid).allSatisfy { $0.visibleAt == [.fine] && $0.cuts?.isEmpty == false })
        let coarseVolume = ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(.coarse) }.reduce(0) { $0 + abs($1.familyMesh.signedVolume) }
        let fineVolume = ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(.fine) }.reduce(0) { $0 + abs($1.familyMesh.signedVolume) }
        // The tongues fill the grooves but for the grooves' clearance.
        #expect(fineVolume < coarseVolume && coarseVolume - fineVolume < 2 * pow(Self.inch, 3), "\(coarseVolume) \(fineVolume)")
        #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty, "\(FamilyEvaluator.flexTest(f, units: .imperial).prefix(3))")
        // Flexed wider, the trimmed top still spans between the sides.
        var wide = f
        wide.types[0].values["Width"] = .double(48 * Self.inch)
        let w = FamilyEvaluator.evaluate(wide, typeName: wide.types[0].name, units: .imperial)
        #expect(Self.approx(w.bounds.max.x - w.bounds.min.x, 48 * Self.inch, 1e-6))
    }

    @Test func oldFilesDecodeAndJointsRoundTrip() throws {
        let d = JointData(parts: [ElementID(9), ElementID(4)], type: .dado, throughPartID: ElementID(4), parameters: JointParameters(depth: 0.005))
        let back = try JSONDecoder().decode(JointData.self, from: JSONEncoder().encode(d))
        #expect(back == d && back.parts == [ElementID(4), ElementID(9)])
        let solid = FamilySolid(name: "S", profile: .rectangle(xMin: .expr("0"), xMax: .expr("1"), yMin: .expr("0"), yMax: .expr("1")), zMin: .expr("0"), zMax: .expr("1"))
        let json = String(decoding: try JSONEncoder().encode(solid), as: UTF8.self)
        #expect(!json.contains("cuts"), "nil Cut Geometry isn't written")
        var setup = FurnitureSetupData(family: FamilyDefinition(name: "P", template: .casework))
        let old = try JSONDecoder().decode(FurnitureSetupData.self, from: JSONEncoder().encode(setup))
        #expect(old.jointRules == nil)
        setup.jointRules = .defaults(.casework)
        #expect(try JSONDecoder().decode(FurnitureSetupData.self, from: JSONEncoder().encode(setup)).jointRules == setup.jointRules)
    }
}
