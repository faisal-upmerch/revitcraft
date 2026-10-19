import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusApplication

/// FMG2 (Furniture joints and fabrication gaps): shaped panels, round rails and slats join like the other parts;
/// joints the rules make show and edit in Properties; a back grooved on four sides has its corners filled; 3D views
/// explode the parts along their joints (F104); CNC programs cover shaped parts and slats and put edge banding on its
/// own layer.
@Suite("FMG2 Furniture joints and fabrication") @MainActor
struct FMG2Tests {
    static let inch = 0.0254
    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }

    static func commit(_ m: BIMModel, _ name: String = "Edit", _ body: (TransactionContext) throws -> Void) throws -> BIMModel {
        let tx = TransactionContext(model: m, name: name)
        try body(tx)
        return try tx.commit().model
    }

    static func bookcase() -> (BIMModel, [String: ElementID]) { FM6Tests.bookcase() }
    static func mark(_ m: BIMModel, _ id: ElementID?) -> String { FurnitureJointParameters.mark(id, m) }

    /// The bookcase with its left side's top front quarter cut away (Edit Profile: the front half 6" lower) and an
    /// opening in the right side.
    static func shapedBookcase() throws -> (BIMModel, [String: ElementID]) {
        var (m, ids) = bookcase()
        let left = try #require(ids["left"]), right = try #require(ids["right"])
        m = try commit(m, "Shape") { tx in
            let i = inch
            try FurniturePartOperations.setProfile(left, [Vec2(0, 0), Vec2(12 * i, 0), Vec2(12 * i, 72 * i), Vec2(6 * i, 72 * i), Vec2(6 * i, 66 * i), Vec2(0, 66 * i)], in: tx)
            try FurniturePartOperations.addOpening(right, PanelOpening(s0: 3 * i, s1: 9 * i, t0: 30 * i, t1: 40 * i), in: tx)
        }
        return (m, ids)
    }

    // MARK: 1. Joints for every part

    @Test func shapedPanelsJoinWhereTheyMeetTheirOutline() throws {
        var (m, ids) = try Self.shapedBookcase()
        let left = ids["left"]!, right = ids["right"]!, top = ids["top"]!
        // Both shaped sides still join the top and the back, and run through as before.
        let lt = try #require(FurnitureJoints.joint(left, top, m))
        #expect(lt.type == .dowel && lt.throughID == left)
        #expect(FurnitureJoints.joint(right, top, m)?.throughID == right)
        #expect(FurnitureJoints.joint(left, ids["back"]!, m)?.type == .groove)
        // The joint sits on the part of the side that reaches the top (the back half), and so do its dowels.
        let back = 0.0 // the side runs from y = -6" to 6"; its back half (y > 0) reaches the top
        #expect(lt.marker.y > back, "marker \(lt.marker)")
        let dowels = FurnitureMachining.entries(m).filter { e in
            guard e.partID == left, e.label == "Dowel", case .drill(let c, _, _, _) = e.op else { return false }
            return c.z > 70 * Self.inch
        }
        #expect(!dowels.isEmpty)
        for d in dowels { if case .drill(let c, _, _, _) = d.op { #expect(c.y > back, "dowel at \(c)") } }
        // An apron at the front, in the cut-away part, doesn't join the left side; it still joins the right one.
        var apron: ElementID?
        m = try Self.commit(m) { tx in
            apron = try FurniturePartOperations.createRail(start: Vec2(-17.25 * Self.inch, -4 * Self.inch), end: Vec2(17.25 * Self.inch, -4 * Self.inch),
                                                           w: 70 * Self.inch, justification: .top, in: tx)
        }
        #expect(FurnitureJoints.joint(left, apron!, m) == nil)
        #expect(FurnitureJoints.joint(right, apron!, m)?.pair == .railPanel)
        // Cut sizes: the blank round the outline; the CNC outline is the profile itself, with the right side's opening.
        let cut = try #require(FurnitureJoints.cutSize(of: left, in: m))
        #expect(Self.approx(cut.length, 72 * Self.inch) && Self.approx(cut.width, 12 * Self.inch), "\(cut)")
        let progs = FurnitureCNC.programs(m)
        let lp = try #require(progs.first { $0.part.elementID == left })
        let outline = try #require(lp.faceA.paths.first { $0.layer == "OUTLINE" })
        #expect(outline.points.count == 6, "\(outline.points)")
        #expect(lp.faceA.circles.contains { $0.layer.hasPrefix("DRILL_") }, "the dowels into the shaped side are drilled")
        let rp = try #require(progs.first { $0.part.elementID == right })
        #expect(rp.faceA.paths.filter { $0.layer == "INNER" }.count == 1)
    }

    @Test func roundRailsAreMortisedIntoTheLegs() throws {
        var m = try #require(FurnitureSamples.tableModel())
        let round = try #require(m.types(for: .furnitureRails).first { $0.name == "1\" Round Stretcher" })
        let apron = try #require(m.elements(.furnitureRails).first)
        m = try Self.commit(m) { tx in tx.update(apron.id) { $0.typeID = round.id } }
        let joints = FurnitureJoints.joints(m).filter { $0.key.a == apron.id || $0.key.b == apron.id }
        let legs = joints.filter { $0.pair == .railLeg }
        #expect(legs.count == 2 && legs.allSatisfy { $0.type == .mortiseTenon && $0.otherID == apron.id }, "\(joints.map { "\($0.pair) \($0.type)" })")
        // Round tenons go in drilled mortises (5/8" for a 1" rail).
        let holes = FurnitureMachining.entries(m).filter { e in legs.contains { $0.throughID == e.partID } && e.label == "Mortise" }
        let drilled = holes.compactMap { e -> Double? in if case .drill(_, _, let d, _) = e.op { return d }; return nil }
        #expect(drilled.count == 2 && drilled.allSatisfy { Self.approx($0, 0.625 * Self.inch) }, "\(holes.map(\.op))")
        // The rail stays round, ends at the legs, and at Fine has its tenons.
        let coarse = FurniturePartMeshes.meshParts(m[apron.id]!, m, detail: .coarse).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        let fine = FurniturePartMeshes.meshParts(m[apron.id]!, m, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(fine.max.x - fine.min.x > coarse.max.x - coarse.min.x + 0.4 * Self.inch, "tenons: \(coarse) \(fine)")
        let solids = FurniturePartSolids.solids(m[apron.id]!, m, PartSolidContext(symbolic: false)).solids
        #expect(solids.filter { if case .circle = $0.profile { return !$0.isVoid }; return false }.count == 3, "the rail and two round tenons")
        // Set to dowels: one dowel on the rail's axis at each end.
        let key = legs[0].key
        m = try Self.commit(m) { tx in try FurnitureJointOperations.set(key, type: .dowel, in: tx) }
        let dowels = FurnitureMachining.entries(m).filter { $0.partID == apron.id && $0.label == "Dowel" }
        #expect(dowels.count == 1, "\(dowels.count)")
    }

    /// A bench: two aprons along x and six slats running across between them, their tops at Top.
    static func bench(_ category: FamilyTemplate) throws -> (BIMModel, slats: ElementID, aprons: [ElementID]) {
        var m = FurnitureTemplates.blank(category: category, name: "Bench")
        var aprons: [ElementID] = [], slats: ElementID?
        m = try commit(m) { tx in
            for y in [-8.0, 8.0] {
                aprons.append(try FurniturePartOperations.createRail(start: Vec2(-17 * inch, y * inch), end: Vec2(17 * inch, y * inch), w: 0, wPlane: "Top", in: tx))
            }
            slats = try FurniturePartOperations.createSlats(in: Rect2(min: Vec2(-15 * inch, -7.625 * inch), max: Vec2(15 * inch, 7.625 * inch)), alongX: false,
                                                            rule: .fixedNumber, spacing: 0, number: 6, z: 0, zPlane: "Top", in: tx)
        }
        return (m, try #require(slats), aprons)
    }

    @Test func slatsJoinTheRailsTheySpanBetween() throws {
        let (m, slats, aprons) = try Self.bench(.furniture)
        let js = FurnitureJoints.joints(m).filter { $0.otherID == slats }
        #expect(js.count == 2 && js.allSatisfy { $0.pair == .slatFrame && $0.type == .mortiseTenon && aprons.contains($0.throughID) },
                "\(FurnitureJoints.joints(m).map { "\($0.pair) \($0.type)" })")
        // A mortise per slat in each apron, a tenon at each end of each slat.
        let mortises = FurnitureMachining.entries(m).filter { aprons.contains($0.partID) && $0.label == "Mortise" }
        #expect(mortises.count == 12)
        #expect(FurniturePartMeshes.meshParts(m[slats]!, m, detail: .fine).count == 18)
        // One slat's cut size, six of them in the Part List.
        let cut = try #require(FurnitureJoints.cutSize(of: slats, in: m))
        let tv = FurniturePartTypes.values(of: m[slats]!, m)
        let tenon = 0.375 * Self.inch - tv.depth / 6 - Self.inch / 32 // half the apron, less half the tenon and 1/32"
        #expect(Self.approx(cut.length, 15.25 * Self.inch + 2 * tenon, 1e-5) && Self.approx(cut.width, tv.width), "\(cut.length / Self.inch)")
        #expect(FurnitureFabrication.parts(m).first { $0.elementID == slats }?.quantity == 6)
        // Casework: dowelled, drilled into the slats' ends (CNC edge boring).
        let (c, cs, _) = try Self.bench(.casework)
        #expect(FurnitureJoints.joints(c).filter { $0.otherID == cs }.allSatisfy { $0.type == .dowel })
        let prog = try #require(FurnitureCNC.programs(c).first { $0.part.elementID == cs })
        #expect(prog.faceA.paths.filter { $0.layer.hasPrefix("HDRILL_") }.count == 2, "\(prog.faceA.layers)")
        // Rules: the pair kind is in Joint Rules.
        #expect(FurnitureJointRules.defaults(.furniture).rule(.slatFrame, category: .furniture).type == .mortiseTenon)
    }

    // MARK: 2. Properties

    @Test func partsListTheirJointsAndEditingOneMakesIt() throws {
        let (m0, ids) = Self.bookcase()
        let s = DocumentSession(model: m0)
        let left = ids["left"]!, top = ids["top"]!
        let topMark = Self.mark(s.model, top)
        let rows = Parameters.instanceEntries(s.model[left]!, s.model)
        let type = try #require(rows.first { $0.name == "\(topMark) Joint" })
        #expect(type.value?.textValue == "Dowel" && !type.isReadOnly)
        #expect(rows.contains { $0.name == "\(topMark) By Rule" && $0.value?.boolValue == true && $0.isReadOnly })
        #expect(rows.contains { $0.name == "\(topMark) Spacing" })
        #expect(rows.contains { $0.name == "\(Self.mark(s.model, ids["back"])) Joint" && $0.value?.textValue == "Groove" })
        // Editing the rules' joint makes the user's joint (one element), as Revit does.
        s.setParameter(type.id, value: .text("Cam Lock"), on: [left], name: "Joint")
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let j = try #require(FurnitureJoints.joint(left, top, s.model))
        #expect(j.type == .camLock && j.isUserSet && s.model.elements(.furnitureJoints).count == 1)
        let after = Parameters.instanceEntries(s.model[left]!, s.model)
        #expect(after.contains { $0.name == "\(topMark) By Rule" && $0.value?.boolValue == false && !$0.isReadOnly })
        // A size, then By Rule.
        let spacing = try #require(after.first { $0.name == "\(topMark) Spacing" })
        s.setParameter(spacing.id, value: .double(5 * Self.inch), on: [left], name: "Spacing")
        #expect(Self.approx(FurnitureJoints.joint(left, top, s.model)?.parameters.spacing, 5 * Self.inch))
        let byRule = try #require(after.first { $0.name == "\(topMark) By Rule" })
        s.setParameter(byRule.id, value: .bool(true), on: [left], name: "By Rule")
        #expect(FurnitureJoints.joint(left, top, s.model)?.isUserSet == false && s.model.elements(.furnitureJoints).isEmpty)
        // Undo brings the user's joint back.
        s.undoManager.groupsByEvent = false
        s.undoManager.beginUndoGrouping()
        s.setParameter(type.id, value: .text("Confirmat Screw"), on: [left], name: "Joint")
        s.undoManager.endUndoGrouping()
        #expect(FurnitureJoints.joint(left, top, s.model)?.type == .confirmat)
        s.undoManager.undo()
        #expect(FurnitureJoints.joint(left, top, s.model)?.isUserSet == false)
    }

    @Test func thePickedJointShowsInPropertiesSetOrNot() throws {
        let (s, ids) = FM6Tests.rectangleBox()
        let j = try #require(FurnitureJoints.joints(s.model).first)
        // A joint the rules make: the joint's rows, By Rule on, Runs Through a choice of its two parts.
        let rows = FurnitureJointProperties.rows(j.key, s.model)
        #expect(rows.contains { $0.entry.name == "Joint" && $0.entry.value?.textValue == "Dowel" })
        #expect(rows.contains { $0.entry.name == "By Rule" && $0.entry.value?.boolValue == true && $0.entry.isReadOnly })
        let through = try #require(rows.first { $0.entry.name == "Runs Through" })
        let marks = [Self.mark(s.model, j.key.a), Self.mark(s.model, j.key.b)]
        #expect(through.entry.type == .choice(marks) && !through.entry.isReadOnly)
        // Picking the other part makes the joint; picking it back returns it to the rule.
        let other = Self.mark(s.model, j.otherID), drawn = Self.mark(s.model, j.throughID)
        _ = s.perform("Runs Through") { tx in try FurnitureJointOperations.setProperty(j.key, FurnitureJointParameters.through.id, .text(other), in: tx) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        #expect(FurnitureJoints.joint(j.key.a, j.key.b, s.model)?.throughID == j.otherID && s.model.elements(.furnitureJoints).count == 1)
        _ = s.perform("Runs Through") { tx in try FurnitureJointOperations.setProperty(j.key, FurnitureJointParameters.through.id, .text(drawn), in: tx) }
        #expect(FurnitureJoints.joint(j.key.a, j.key.b, s.model)?.throughID == j.throughID && s.model.elements(.furnitureJoints).isEmpty)
        // The rule's type isn't an override either; a size is.
        _ = s.perform("Type") { tx in try FurnitureJointOperations.setProperty(j.key, FurnitureJointParameters.jointType.id, .text("Dowel"), in: tx) }
        #expect(s.model.elements(.furnitureJoints).isEmpty)
        _ = s.perform("Count") { tx in try FurnitureJointOperations.setProperty(j.key, FurnitureJointParameters.value(.count).id, .int(3), in: tx) }
        #expect(FurnitureJoints.joint(j.key.a, j.key.b, s.model)?.parameters.count == 3 && s.model.elements(.furnitureJoints).count == 1)
        // A joint that isn't at a corner: Runs Through is fixed.
        let (m, bids) = Self.bookcase()
        let shelfBack = try #require(FurnitureJoints.joint(bids["shelf1"]!, bids["back"]!, m))
        #expect(FurnitureJointProperties.rows(shelfBack.key, m).first { $0.entry.name == "Runs Through" }?.entry.isReadOnly == true)
        _ = ids
    }

    // MARK: 3. Back in grooves on four sides

    @Test func aBackGroovedOnFourSidesHasItsCornersFilled() throws {
        let (m, ids) = Self.bookcase()
        let back = ids["back"]!, left = ids["left"]!, top = ids["top"]!
        let sol = JointSolver.solve(m)
        let bb = try #require(sol.finalBoxes[back]), lb = try #require(sol.finalBoxes[left]), tb = try #require(sol.finalBoxes[top])
        let d = 0.25 * Self.inch
        // The corner: in the left side's groove (x) and the top's groove (z), across the back's thickness.
        let corner = Vec3(lb.h(.x) - d / 2, (bb.l(.y) + bb.h(.y)) / 2, tb.l(.z) + d / 2)
        func contains(_ s: FamilySolid, _ p: Vec3) -> Bool {
            guard case .rectangle(let x0, let x1, let y0, let y1) = s.profile, s.workPlane == nil else { return false }
            func n(_ b: FamilyBound) -> Double { if case .expr(let x) = b { return Double(x) ?? .nan }; return .nan }
            return p.x > n(x0) && p.x < n(x1) && p.y > n(y0) && p.y < n(y1) && p.z > n(s.zMin) && p.z < n(s.zMax)
        }
        let backSolids = FurniturePartSolids.solids(m[back]!, m, PartSolidContext(symbolic: false)).solids
        #expect(backSolids.contains { !$0.isVoid && $0.visibleAt == [.fine] && contains($0, corner) }, "the back's tongue runs into the corner")
        let leftSolids = FurniturePartSolids.solids(m[left]!, m, PartSolidContext(symbolic: false)).solids
        #expect(leftSolids.contains { $0.isVoid && contains($0, corner) }, "the side's groove runs on to meet the top's")
        let topSolids = FurniturePartSolids.solids(m[top]!, m, PartSolidContext(symbolic: false)).solids
        #expect(!topSolids.contains { contains($0, corner) }, "the corner is in the side, not the top")
        // The side's groove (CNC) runs past the back's edges by the top's and bottom's groove depth.
        let groove = FurnitureMachining.entries(m).first { $0.partID == left && $0.label == JointType.groove.rawValue }
        guard case .groove(let a, let b, _, _, _)? = groove?.op else { Issue.record("no groove"); return }
        #expect(Self.approx(max(a.z, b.z), bb.h(.z) + d, 1e-7) && Self.approx(min(a.z, b.z), bb.l(.z) - d, 1e-7), "\(a.z) \(b.z) vs \(bb.l(.z)) \(bb.h(.z))")
        // The top's groove stops at the sides (the corner isn't in the top).
        let tg = FurnitureMachining.entries(m).first { $0.partID == top && $0.label == JointType.groove.rawValue }
        guard case .groove(let ta, let tbb, _, _, _)? = tg?.op else { Issue.record("no top groove"); return }
        #expect(Self.approx(abs(ta.x - tbb.x), bb.ext(.x), 1e-7))
        // Nothing overlaps at Fine (the tongue fills the groove only).
        for other in [left, top, ids["right"]!, ids["bottom"]!] {
            for s1 in backSolids where !s1.isVoid {
                for s2 in FurniturePartSolids.solids(m[other]!, m, PartSolidContext(symbolic: false)).solids where !s2.isVoid {
                    let p = Vec3(corner.x, corner.y, corner.z)
                    #expect(!(contains(s1, p) && contains(s2, p) && !leftSolids.contains { $0.isVoid && contains($0, p) }))
                }
            }
        }
    }

    // MARK: 4. Explode Parts

    @Test func explodedViewsMovePartsAlongTheirJoints() throws {
        var (m, ids) = Self.bookcase()
        let view = try #require(m.views.first { $0.name == "{3D}" })
        let before = ViewGraphicsBuilder(model: m, view: m[view.id]!).build()
        m = try Self.commit(m, "Explode") { tx in try FurnitureExplode.set(view.id, on: true, distance: 6 * Self.inch, in: tx) }
        let v = m[view.id]!
        let o = FurnitureExplode.offsets(m, view: v)
        #expect((o[ids["left"]!]?.x ?? 0) < 0 && (o[ids["right"]!]?.x ?? 0) > 0)
        #expect((o[ids["top"]!]?.z ?? 0) > 0 && (o[ids["bottom"]!]?.z ?? 0) < 0)
        #expect((o[ids["back"]!]?.y ?? 0) > 0, "the back moves out the back")
        #expect((o[ids["shelf2"]!]?.y ?? 0) < 0 && (o[ids["shelf2"]!]?.z ?? 0) == 0, "shelves move forward off the back")
        #expect(Self.approx(o[ids["left"]!]?.x, -6 * Self.inch))
        // The hidden-line drawing (PDF, images, sheets) is drawn exploded, with a tag on each part.
        let g = ViewGraphicsBuilder(model: m, view: v).build()
        #expect(g.extents.width > before.extents.width + 0.2, "\(before.extents) \(g.extents)")
        let tags = g.items.filter { $0.category == .tags && $0.layer == .annotation }
        let texts = Set(tags.flatMap(\.primitives).compactMap { p -> String? in if case .text(let t) = p { return t.string }; return nil })
        #expect(texts.contains(Self.mark(m, ids["left"])) && texts.contains(Self.mark(m, ids["top"])), "\(texts)")
        // Tags don't overlap.
        let boxes = tags.compactMap { t in t.primitives.compactMap { p -> Rect2? in if case .fill(let polys, _) = p { return polys.first?.bounds }; return nil }.first }
        let overlaps = boxes.indices.flatMap { i in boxes.indices.filter { $0 > i && boxes[i].expanded(by: -1e-6).intersects(boxes[$0].expanded(by: -1e-6)) } }
        #expect(overlaps.isEmpty, "\(overlaps.count) tags overlap")
        // Tag Parts off; Explode Parts off.
        m = try Self.commit(m) { tx in try FurnitureExplode.set(view.id, on: true, tags: false, in: tx) }
        #expect(!ViewGraphicsBuilder(model: m, view: m[view.id]!).build().items.contains { $0.category == .tags && $0.layer == .annotation })
        m = try Self.commit(m) { tx in try FurnitureExplode.set(view.id, on: false, in: tx) }
        #expect(FurnitureExplode.offsets(m, view: m[view.id]!).isEmpty)
        // Plan views and projects don't explode.
        #expect(throws: TransactionError.self) { _ = try Self.commit(m) { tx in try FurnitureExplode.set(m.views.first { $0.name == "Ref. Level" }!.id, on: true, in: tx) } }
        // A table: the legs move down and out, the top up.
        var t = try #require(FurnitureSamples.tableModel())
        let tv = try #require(t.views.first { $0.name == "{3D}" })
        t = try Self.commit(t) { tx in try FurnitureExplode.set(tv.id, on: true, in: tx) }
        let to = FurnitureExplode.offsets(t, view: t[tv.id]!)
        let top = try #require(t.elements(.furnitureShelves).first)
        #expect((to[top.id]?.z ?? 0) > 0)
        for leg in t.elements(.furnitureLegs) {
            let off = try #require(to[leg.id])
            let c = FurniturePartMeshes.meshParts(leg, t, detail: .coarse).reduce(Box3.empty) { $0.union($1.mesh.bounds) }.center
            #expect(off.z < 0 && off.x * c.x > 0 && off.y * c.y > 0, "\(leg.mark): \(off)")
        }
    }

    @Test func explodePartsIsInTheViewsPropertiesAndF104UsesIt() throws {
        let (m0, ids) = Self.bookcase()
        let s = DocumentSession(model: m0)
        let view = try #require(s.model.views.first { $0.name == "{3D}" })
        let rows = Parameters.instanceEntries(s.model[view.id]!, s.model)
        #expect(rows.contains { $0.name == "Explode Parts" && $0.value?.boolValue == false && $0.group == .graphics })
        #expect(rows.contains { $0.name == "Explode Distance" && $0.isReadOnly })
        s.setParameter(FurnitureExplode.onParam, value: .bool(true), on: [view.id], name: "Explode Parts")
        s.setParameter(FurnitureExplode.distanceParam, value: .double(8 * Self.inch), on: [view.id], name: "Explode Distance")
        #expect(FurnitureExplode.isExploded(s.model[view.id]!) && Self.approx(FurnitureExplode.distance(s.model[view.id]!), 8 * Self.inch))
        s.setParameter(FurnitureExplode.distanceParam, value: .double(-1), on: [view.id], name: "Explode Distance")
        #expect(s.lastError != nil)
        // Projects' 3D views don't have it.
        let p = BIMModel()
        if let pv = p.views.first(where: { $0.view?.kind == .threeD }) { #expect(!Parameters.instanceEntries(pv, p).contains { $0.name == "Explode Parts" }) }
        // F104's Back 3D view is exploded with its parts tagged.
        let shop = try Self.commit(s.model, "Shop Drawings") { tx in FurnitureShopDrawings.update(in: tx) }
        let back3D = try #require(shop.views.first { $0.name == FurnitureShopDrawings.back3DName })
        #expect(FurnitureExplode.isExploded(back3D) && back3D.view?.titleOnSheet == "Exploded View")
        let f104 = try #require(shop.sheets.first { $0.sheet?.number == FurnitureShopDrawings.details })
        let g = SheetGraphicsBuilder(model: shop, sheet: f104).build()
        let texts = g.items.flatMap(\.primitives).compactMap { p -> String? in if case .text(let t) = p { return t.string }; return nil }
        #expect(texts.contains(Self.mark(shop, ids["left"])), "F104 tags the parts")
        // Older documents: Shop Drawings turns it on once; off stays off.
        let off = try Self.commit(shop) { tx in try FurnitureExplode.set(back3D.id, on: false, in: tx); FurnitureShopDrawings.update(in: tx) }
        #expect(!FurnitureExplode.isExploded(off[back3D.id]!))
    }

    // MARK: 5. CNC

    @Test func edgeBandingHasItsOwnLayer() throws {
        let (m, _) = Self.bookcase()
        let progs = FurnitureCNC.programs(m)
        let banded = try #require(progs.first { $0.part.banding != .none && $0.part.bandingThickness > 0 })
        let layer = FurnitureCNC.bandLayer(thickness: banded.part.bandingThickness)
        #expect(layer.hasPrefix("BAND_") && layer != "BAND_0")
        let bands = banded.faceA.paths.filter { $0.layer == layer }
        let b = banded.part.banding
        #expect(bands.count == [b.l1, b.l2, b.w1, b.w2].filter { $0 }.count, "\(banded.part.banding.code): \(bands.map(\.points))")
        #expect(bands.allSatisfy { !$0.closed && $0.points.count == 2 })
        let L = banded.part.length, W = banded.part.width
        if b.l1 { #expect(bands.contains { $0.points.allSatisfy { abs($0.y) < 1e-9 } && abs(abs($0.points[1].x - $0.points[0].x) - L) < 1e-9 }) }
        if b.l2 { #expect(bands.contains { $0.points.allSatisfy { abs($0.y - W) < 1e-9 } }) }
        // Banding isn't machining.
        #expect(banded.operationCount == banded.faceA.circles.count + banded.faceA.paths.filter { !["OUTLINE", "GRAIN", "INNER", layer].contains($0.layer) }.count
                                        + (banded.faceB.map { $0.circles.count + $0.paths.filter { !["OUTLINE", "GRAIN", "INNER"].contains($0.layer) }.count } ?? 0))
        // A shaped part's banding follows the side its edges face.
        let shaped = FurnitureCNC.banding(CutPart(key: "x", mark: "X", name: "Panel", typeName: "", elementID: ElementID(0), isDerived: false, materialID: nil,
                                                  faceMaterialID: nil, length: 1, width: 0.5, thickness: 0.019, grain: .length, banding: EdgeBanding(l2: true),
                                                  bandingMaterialID: nil, bandingThickness: 0.001, quantity: 1),
                                          outline: [Vec2(0, 0), Vec2(1, 0), Vec2(1, 0.3), Vec2(0.5, 0.5), Vec2(0, 0.3)], m)
        #expect(shaped.count == 1 && shaped[0].points.count == 3, "the two edges facing +Y as one run: \(shaped.map(\.points))")
    }
}

