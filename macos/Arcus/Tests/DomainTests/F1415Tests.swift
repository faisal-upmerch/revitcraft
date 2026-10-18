import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// F1415 (RevitCraft port, Family Editor A and B): voids of every form cut solids, Swept Blend, extrusions sketched on
/// elevation planes, model text, model and reference lines, flip controls that flip placed instances, filled/masking
/// regions, openings, the work plane and the sketch mode that builds them.
@Suite("F1415 Family Editor")
struct F1415Tests {
    static func approx(_ a: Double, _ b: Double, _ tol: Double = 1e-6) -> Bool { abs(a - b) <= tol }

    /// The Generic Box: a 1 m cube between Left/Right, Front/Back and Bottom/Top.
    static func box() -> FamilyDefinition { var f = StarterLibrary.genericBox(); f.addTemplateOriginConstraints(); return f }
    static func eval(_ f: FamilyDefinition) -> EvaluatedFamily { FamilyEvaluator.evaluate(f, typeName: f.types[0].name) }
    static func square(_ h: Double, at c: (Double, Double) = (0, 0)) -> [FamilyPoint] {
        [FamilyPoint("\(c.0 - h)", "\(c.1 - h)"), FamilyPoint("\(c.0 + h)", "\(c.1 - h)"), FamilyPoint("\(c.0 + h)", "\(c.1 + h)"), FamilyPoint("\(c.0 - h)", "\(c.1 + h)")]
    }

    // MARK: CSG

    @Test func csgSubtractsUnitesAndIntersectsBoxes() {
        let a = MeshCSG(mesh: .box(Box3(min: Vec3(-1, -1, 0), max: Vec3(1, 1, 1))))
        let b = MeshCSG(mesh: .box(Box3(min: Vec3(-0.25, -0.25, -0.1), max: Vec3(0.25, 0.25, 2))))
        #expect(Self.approx(a.subtracting(b).volume, 4 - 0.25))
        #expect(Self.approx(a.intersecting(b).volume, 0.25))
        let c = MeshCSG(mesh: .box(Box3(min: Vec3(0.5, -0.5, 0), max: Vec3(1.5, 0.5, 1))))
        #expect(Self.approx(a.union(c).volume, 4 + 0.5))
        // The cut mesh is closed and draws its real edges only (no seams between coplanar fragments).
        let m = a.subtracting(b).mesh()
        #expect(Self.approx(m.signedVolume, 3.75))
        #expect(m.featureEdges.count / 2 >= 24 && m.featureEdges.count / 2 <= 40, "\(m.featureEdges.count / 2) edges")
    }

    // MARK: Voids

    @Test func voidRevolveCutsAnExtrusion() {
        var f = Self.box()
        f.solids.append(FamilySolid(name: "Hole", profile: .revolve(FamilyRevolve(profile: [FamilyPoint("0", "-0.1"), FamilyPoint("0.2", "-0.1"), FamilyPoint("0.2", "1.1"), FamilyPoint("0", "1.1")])),
                                    zMin: .expr("0"), zMax: .expr("0"), isVoid: true))
        let ev = Self.eval(f)
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        #expect(ev.warnings.isEmpty, "\(ev.warnings)")
        let disc = 0.5 * 48 * 0.04 * sin(2 * .pi / 48) // the 48-gon the revolve is tessellated into
        #expect(Self.approx(ev.solidVolume, 1 - disc, 1e-4), "\(ev.solidVolume)")
    }

    @Test func voidSweepAndVoidBlendCut() {
        var f = Self.box()
        // A 0.2 x 0.2 channel across the top of the box, along X.
        f.solids.append(FamilySolid(name: "Channel", profile: .sweep(FamilySweep(path: [FamilyPoint("-1", "0"), FamilyPoint("1", "0")],
                                                                                 profile: [FamilyPoint("-0.1", "0"), FamilyPoint("0.1", "0"), FamilyPoint("0.1", "0.3"), FamilyPoint("-0.1", "0.3")])),
                                    zMin: .expr("0.8"), zMax: .expr("0.8"), isVoid: true))
        let swept = Self.eval(f)
        #expect(swept.errors.isEmpty, "\(swept.errors)")
        #expect(Self.approx(swept.solidVolume, 1 - 0.2 * 0.2 * 1, 1e-6), "\(swept.solidVolume)")
        // A void blend (a frustum 0.2 → 0.1 square, 0.5 tall) sunk into the bottom.
        var g = Self.box()
        g.solids.append(FamilySolid(name: "Pocket", profile: .blend(FamilyBlend(bottom: Self.square(0.1), top: Self.square(0.05))), zMin: .expr("-0.5"), zMax: .expr("0.5"), isVoid: true))
        let blend = Self.eval(g)
        // Below z = 0 the frustum is outside the box; inside it runs from 0.15 to 0.1 square halves... measure by CSG directly.
        let pocket = MeshCSG(mesh: FamilyFormGeometry.blendMesh(bottom: Polygon2(Self.square(0.1).map { Vec2(Double($0.x.text)!, Double($0.y.text)!) }),
                                                                top: Polygon2(Self.square(0.05).map { Vec2(Double($0.x.text)!, Double($0.y.text)!) }), z0: -0.5, z1: 0.5))
        let inside = pocket.intersecting(MeshCSG(mesh: .box(Box3(min: Vec3(-0.5, -0.5, 0), max: Vec3(0.5, 0.5, 1))))).volume
        #expect(inside > 0.005)
        #expect(Self.approx(blend.solidVolume, 1 - inside, 1e-6), "\(blend.solidVolume) vs \(1 - inside)")
    }

    @Test func voidExtrusionCutsARevolveAndExtrusionsStayExact() {
        var f = FamilyDefinition(name: "Vase", template: .genericModel)
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        f.solids = [FamilySolid(name: "Body", profile: .revolve(FamilyRevolve(profile: [FamilyPoint("0", "0"), FamilyPoint("0.3", "0"), FamilyPoint("0.3", "1"), FamilyPoint("0", "1")])),
                                zMin: .expr("0"), zMax: .expr("0")),
                    FamilySolid(name: "Cut", profile: .rectangle(xMin: .expr("0"), xMax: .expr("1"), yMin: .expr("-1"), yMax: .expr("1")), zMin: .expr("0.5"), zMax: .expr("2"), isVoid: true)]
        let full = Self.eval({ var g = f; g.solids.removeLast(); return g }()).solidVolume
        let cut = Self.eval(f).solidVolume
        // The void removes half of the upper half.
        #expect(Self.approx(cut, full * 0.75, 1e-4), "\(cut) vs \(full * 0.75)")
        // Extrusion minus extrusion is still the exact prism cut (no meshes).
        var b = Self.box()
        b.solids.append(FamilySolid(name: "Slot", profile: .rectangle(xMin: .expr("-0.1"), xMax: .expr("0.1"), yMin: .expr("-1"), yMax: .expr("1")), zMin: .expr("0.5"), zMax: .expr("2"), isVoid: true))
        let eb = Self.eval(b)
        #expect(eb.solids.filter { !$0.isVoid }.allSatisfy { $0.mesh == nil })
        #expect(Self.approx(eb.solidVolume, 1 - 0.2 * 0.5))
    }

    // MARK: Swept Blend and elevation extrusions

    @Test func sweptBlendLoftsBetweenItsProfiles() {
        var f = FamilyDefinition(name: "SB", template: .genericModel)
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        let sq = { (s: Double) in [FamilyPoint("0", "0"), FamilyPoint("\(s)", "0"), FamilyPoint("\(s)", "\(s)"), FamilyPoint("0", "\(s)")] }
        f.solids = [FamilySolid(name: "SB", profile: .sweep(FamilySweep(path: [FamilyPoint("0", "0"), FamilyPoint("1", "0")], profile: sq(0.2), endProfile: sq(0.1))),
                                zMin: .expr("0"), zMax: .expr("0"))]
        #expect(f.solids[0].profile.kindName == "Swept Blend")
        let ev = Self.eval(f)
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let s = ev.solids[0]
        // As RevitCraft's test: the far end is the small profile; left of an eastward path is +Y.
        #expect(s.bounds.min.isAlmostEqual(.zero) && s.bounds.max.isAlmostEqual(Vec3(1, 0.2, 0.2)), "\(s.bounds)")
        let far = s.familyMesh.positions.filter { abs($0.x - 1) < 1e-9 }
        #expect(far.allSatisfy { $0.y <= 0.1 + 1e-9 && $0.z <= 0.1 + 1e-9 })
        // A frustum: h/3 (A1 + A2 + √(A1 A2)).
        #expect(Self.approx(abs(s.familyMesh.signedVolume), (0.04 + 0.01 + 0.02) / 3, 1e-9), "\(s.familyMesh.signedVolume)")
        #expect(f.minimumReaderVersion == 3)
        // A swept blend along an L path keeps a closed volume.
        f.solids[0].profile = .sweep(FamilySweep(path: [FamilyPoint("0", "0"), FamilyPoint("1", "0"), FamilyPoint("1", "1")], profile: sq(0.1), endProfile: sq(0.1)))
        let l = Self.eval(f).solids[0]
        #expect(l.familyMesh.signedVolume > 0.015 && l.familyMesh.signedVolume < 0.025, "\(l.familyMesh.signedVolume)")
    }

    @Test func extrusionsOnElevationPlanesRunAlongTheirNormal() {
        var f = FamilyDefinition(name: "Plate", template: .genericModel)
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        var s = FamilySolid(name: "Front plate", profile: .polygon([FamilyPoint("0", "0"), FamilyPoint("1", "0"), FamilyPoint("0.5", "2")]), zMin: .expr("0.1"), zMax: .expr("0.3"))
        s.workPlane = .xz
        f.solids = [s]
        let ev = Self.eval(f)
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = ev.solids[0].bounds
        #expect(b.min.isAlmostEqual(Vec3(0, 0.1, 0)) && b.max.isAlmostEqual(Vec3(1, 0.3, 2)), "\(b)")
        #expect(Self.approx(ev.solidVolume, 0.5 * 1 * 2 * 0.2))
        #expect(Self.approx(ev.solids[0].profile.outer.area, 1 * 0.2), "plan footprint is the extrusion's shadow")
        f.solids[0].workPlane = .yz
        let r = Self.eval(f).solids[0].bounds
        #expect(r.min.isAlmostEqual(Vec3(0.1, 0, 0)) && r.max.isAlmostEqual(Vec3(0.3, 1, 2)), "\(r)")
    }

    // MARK: Model text, lines, regions

    @Test func modelTextBecomesSolidsOnItsWorkPlane() {
        TestGlyphs.install() // F1Tests' block glyphs: 0.6 × 1 boxes advancing 0.7
        var f = Self.box()
        f.modelTexts = [FamilyModelText(text: "AB", plane: .xz, position: FamilyPoint("-0.5", "1.2"), offset: .plane("Front"), size: 0.2, depth: 0.05)]
        let ev = Self.eval(f)
        let text = ev.solids.filter { $0.sourceID == f.modelTexts[0].id }
        #expect(text.count == 2)
        let b = text.reduce(Box3.empty) { $0.union($1.bounds) }
        #expect(Self.approx(b.min.y, -0.5) && Self.approx(b.max.y, -0.45), "extruded back from the Front plane: \(b)")
        #expect(Self.approx(b.min.z, 1.2) && Self.approx(b.max.z, 1.4) && Self.approx(b.min.x, -0.5), "\(b)")
        #expect(f.minimumReaderVersion == 3)
    }

    @Test func modelAndReferenceLinesEvaluateAndOnlyModelLinesReachProjects() throws {
        var f = Self.box()
        f.name = "Lined Box"
        f.modelLines = [FamilyModelLine(plane: .xy, offset: .plane("Top"), start: FamilyPoint(.plane("Left"), .expr("0")), end: FamilyPoint(.plane("Right"), .expr("0"))),
                        FamilyModelLine(plane: .xz, start: FamilyPoint("0", "0"), end: FamilyPoint("0", "1"), isReference: true)]
        let ev = Self.eval(f)
        #expect(ev.modelLines.count == 2)
        #expect(ev.modelLines[0].start.isAlmostEqual(Vec3(-0.5, 0, 1)) && ev.modelLines[0].end.isAlmostEqual(Vec3(0.5, 0, 1)))
        #expect(ev.modelLines[1].isReference && ev.modelLines[1].end.isAlmostEqual(Vec3(0, 0, 1)))
        var (m, ids) = Fx.template()
        let (_, _, inst) = try Self.place(&m, ids, f, at: Vec2(3, 0))
        let symbols = ComponentGeometry.planSymbols(m[inst]!, m)
        let lines = symbols.compactMap { s -> Segment2? in if case .line(let seg) = s.curve { return seg }; return nil }
        #expect(lines.contains { $0.start.isAlmostEqual(Vec2(2.5, 0)) && $0.end.isAlmostEqual(Vec2(3.5, 0)) })
        #expect(!lines.contains { $0.length < 1e-6 }, "the reference line (edge-on in plan) is not drawn")
        // Renaming a plane carries the line's lock.
        var g = f
        #expect(FamilyEditing.renamePlane(&g, "Top", to: "Lid"))
        #expect(g.modelLines[0].offset == .plane("Lid"))
    }

    // MARK: Controls

    static func place(_ m: inout BIMModel, _ ids: ProjectTemplates.Ids, _ family: FamilyDefinition, at p: Vec2) throws -> (ElementID, ElementID, ElementID) {
        var fid = ElementID(0), tid = ElementID(0), inst = ElementID(0)
        try Fx.commit(&m) { tx in
            fid = FamilyProjectLoader.load(family, replacing: tx.model.family(named: family.name)?.id, in: tx)
            tid = try #require(tx.model.elements(.elementTypes).first { $0.typeData?.familyID == fid }?.id)
            inst = tx.create(.genericModels, data: .component(ComponentData(location: p)), typeID: tid, levelID: ids.levels[0])
        }
        return (fid, tid, inst)
    }

    static func bounds(_ id: ElementID, _ m: BIMModel) -> Box3 {
        ComponentGeometry.meshParts(m[id]!, m).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
    }

    @Test func controlsFlipPlacedInstances() throws {
        var f = Self.box()
        f.name = "Flippable"
        // An off-centre block so flips show: x in 0.5…1.5 beside the box, y in 0.5…0.9.
        f.solids.append(FamilySolid(name: "Arm", profile: .rectangle(xMin: .expr("0.5"), xMax: .expr("1.5"), yMin: .expr("0.5"), yMax: .expr("0.9")), zMin: .expr("0"), zMax: .expr("0.2")))
        f.controls = [FamilyControl(position: FamilyPoint("0", "-0.8"), kind: .singleHorizontal), FamilyControl(position: FamilyPoint("0.8", "0"), kind: .doubleVertical)]
        #expect(f.minimumReaderVersion == 3)
        var (m, ids) = Fx.template()
        let (_, _, inst) = try Self.place(&m, ids, f, at: Vec2(10, 0))
        let before = Self.bounds(inst, m)
        #expect(Self.approx(before.max.x, 11.5) && Self.approx(before.max.y, 0.9))
        let view = m[ids.planViews[ids.levels[0]]!]
        let controls = GripService.controls(for: m[inst]!, m, view: view, pixel: 0.01)
        #expect(controls.count == 2)
        let hand = try #require(controls.first { $0.kind == .flipHand })
        let facing = try #require(controls.first { $0.kind == .flipFacing })
        #expect(hand.position.isAlmostEqual(Vec2(10, -0.8)) && facing.position.isAlmostEqual(Vec2(10.8, 0)))
        // Horizontal control: Flip Hand mirrors the instance across its Y axis.
        try Fx.commit(&m) { tx in GripService.toggle(hand, in: tx) }
        #expect(m[inst]?.component?.mirrored == true)
        let mirrored = Self.bounds(inst, m)
        #expect(Self.approx(mirrored.min.x, 8.5) && Self.approx(mirrored.max.x, 10.5), "\(mirrored)")
        // Vertical control: Flip Facing mirrors across its X axis.
        try Fx.commit(&m) { tx in GripService.toggle(facing, in: tx) }
        #expect(m[inst]?.component?.facingFlipped == true)
        let flipped = Self.bounds(inst, m)
        #expect(Self.approx(flipped.min.y, -0.9) && Self.approx(flipped.max.y, 0.5), "\(flipped)")
        // The controls follow the instance.
        let moved = GripService.controls(for: m[inst]!, m, view: view, pixel: 0.01)
        #expect(moved.contains { $0.kind == .flipHand && $0.position.isAlmostEqual(Vec2(10, 0.8)) })
        try Fx.commit(&m) { tx in GripService.toggle(facing, in: tx) }
        #expect(m[inst]?.component?.facingFlipped == nil)
        // Families without controls get none.
        let (_, _, plain) = try Self.place(&m, ids, { var g = Self.box(); g.name = "Plain"; return g }(), at: .zero)
        #expect(GripService.controls(for: m[plain]!, m, view: view, pixel: 0.01).isEmpty)
    }

    // MARK: Sketch mode

    static func planes(_ f: FamilyDefinition, _ frame: FamilyEditing.ViewFrame) -> [FamilyEditing.PlaneLine] {
        let ev = eval(f)
        return f.referencePlanes.compactMap { p in
            guard let v = ev.planes[p.name] else { return nil }
            if p.axis == frame.plane.axes.u { return .init(name: p.name, vertical: true, value: v * frame.uSign) }
            if p.axis == frame.plane.axes.v { return .init(name: p.name, vertical: false, value: v) }
            return nil
        }
    }

    static func value(_ f: FamilyDefinition) -> (FamilyBound) -> Double {
        let ev = eval(f)
        return { b in
            switch b {
            case .plane(let n): ev.planes[n] ?? 0
            case .expr(let e): Double(e) ?? 0
            }
        }
    }

    @Test func sketchedExtrusionsLockToThePlanesTheySnapTo() {
        let f = Self.box()
        let planes = Self.planes(f, .plan)
        let a = FamilyEditing.snapVertex(Vec2(-0.499, -0.501), frame: .plan, planes: planes, tolerance: 0.01)
        let b = FamilyEditing.snapVertex(Vec2(0.2, 0.3004), frame: .plan, planes: planes, tolerance: 0.01)
        #expect(a.uPlane == "Left" && a.vPlane == "Front" && b.uPlane == nil && Self.approx(b.v, 0.3))
        var s = FamilyEditing.Sketch(form: .extrusion, frame: .plan, depth: 0.4, offset: FamilyEditing.workPlaneOffset(f, named: "Top", frame: .plan))
        s.vertices = FamilyEditing.rectangle(a, b)
        guard case .solid(let solid) = FamilyEditing.finish(&s, in: f, value: Self.value(f)) else { Issue.record("no solid"); return }
        #expect(solid.profile == .rectangle(xMin: .plane("Left"), xMax: .expr("0.2"), yMin: .plane("Front"), yMax: .expr("0.3")))
        #expect(solid.zMin == .plane("Top") && solid.zMax == .expr("1.4") && solid.workPlane == nil)
        // In the Back elevation the horizontal axis runs along −X, and the depth goes toward −Y (into the screen).
        let back = Self.planes(f, .back)
        let p = FamilyEditing.snapVertex(Vec2(-0.5, 0.2), frame: .back, planes: back, tolerance: 0.01)
        #expect(p.uPlane == "Right" && Self.approx(p.u, 0.5))
        var e = FamilyEditing.Sketch(form: .extrusion, isVoid: true, frame: .back, depth: 0.1, offset: FamilyEditing.workPlaneOffset(f, named: "Back", frame: .back))
        e.vertices = [p, FamilyEditing.SketchVertex(u: 0, v: 0.2), FamilyEditing.SketchVertex(u: 0.25, v: 0.6)]
        guard case .solid(let v) = FamilyEditing.finish(&e, in: f, value: Self.value(f)) else { Issue.record("no void"); return }
        #expect(v.isVoid && v.workPlane == .xz && v.zMin == .expr("0.4") && v.zMax == .plane("Back"))
        // A non-parallel work plane falls back to the view's own plane.
        #expect(FamilyEditing.workPlaneOffset(f, named: "Left", frame: .plan) == .expr("0"))
    }

    @Test func sketchedSweepAndSweptBlendFollowPathAndProfiles() {
        let f = Self.box()
        var s = FamilyEditing.Sketch(form: .sweep, frame: .plan)
        s.vertices = [.init(u: 0, v: -1), .init(u: 0, v: 1)]
        guard case .next = FamilyEditing.finish(&s, in: f, value: Self.value(f)) else { Issue.record("path"); return }
        // The path runs along +Y, so its profile plane is seen square in the Front and Back elevations.
        let station = FamilyEditing.profileStation([Vec2(0, -1), Vec2(0, 1)], form: .sweep, atEnd: false)!
        #expect(FamilyEditing.profileViews(normal: station.normal).map(\.plane) == [.xz, .xz])
        // Sketching in Right fails: that view looks along the path.
        s.frame = .right
        s.vertices = [.init(u: 0, v: 0), .init(u: 0.1, v: 0), .init(u: 0.1, v: 0.1)]
        guard case .failed = FamilyEditing.finish(&s, in: f, value: Self.value(f)) else { Issue.record("should fail"); return }
        s.frame = .front
        s.vertices = [.init(u: -0.1, v: 0), .init(u: -0.3, v: 0), .init(u: -0.3, v: 0.2), .init(u: -0.1, v: 0.2)]
        guard case .solid(let sweep) = FamilyEditing.finish(&s, in: f, value: Self.value(f)), case .sweep(let sw) = sweep.profile else { Issue.record("sweep"); return }
        // Left of a +Y path is −X: x = −0.1…−0.3 is 0.1…0.3 to the left.
        #expect(sw.profile.map { Double($0.x.text)! } == [0.1, 0.3, 0.3, 0.1])
        var g = Self.box(); g.solids = [sweep]
        let ev = Self.eval(g)
        #expect(ev.solids[0].bounds.min.isAlmostEqual(Vec3(-0.3, -1, 0)) && ev.solids[0].bounds.max.isAlmostEqual(Vec3(-0.1, 1, 0.2)), "\(ev.solids[0].bounds)")

        var b = FamilyEditing.Sketch(form: .sweptBlend, frame: .plan)
        b.vertices = [.init(u: 0, v: 0), .init(u: 1, v: 0), .init(u: 2, v: 0)]
        guard case .failed = FamilyEditing.finish(&b, in: f, value: Self.value(f)) else { Issue.record("one segment only"); return }
        b.vertices.removeLast()
        _ = FamilyEditing.finish(&b, in: f, value: Self.value(f))
        b.frame = .right
        b.vertices = FamilyEditing.rectangle(.init(u: 0, v: 0), .init(u: 0.2, v: 0.2))
        guard case .next = FamilyEditing.finish(&b, in: f, value: Self.value(f)) else { Issue.record("profile 1"); return }
        b.vertices = FamilyEditing.rectangle(.init(u: 0, v: 0), .init(u: 0.1, v: 0.1))
        guard case .solid(let sb) = FamilyEditing.finish(&b, in: f, value: Self.value(f)), case .sweep(let swb) = sb.profile else { Issue.record("swept blend"); return }
        #expect(swb.isSweptBlend && sb.name == "Swept Blend 2")
        g.solids = [sb]
        #expect(Self.approx(abs(Self.eval(g).solids[0].familyMesh.signedVolume), (0.04 + 0.01 + 0.02) / 3, 1e-9))
    }

    @Test func sketchedRevolveBlendRegionAndOpening() {
        let f = Self.box()
        var r = FamilyEditing.Sketch(form: .revolve, isVoid: true, frame: .front)
        r.axisU = 0.1
        r.vertices = FamilyEditing.rectangle(.init(u: 0.2, v: 0), .init(u: 0.4, v: 0.5))
        guard case .solid(let rev) = FamilyEditing.finish(&r, in: f, value: Self.value(f)), case .revolve(let rv) = rev.profile else { Issue.record("revolve"); return }
        #expect(rev.isVoid && rv.axis == FamilyPoint("0.1", "0") && rv.profile.map { Double($0.x.text)! } == [0.1, 0.3, 0.3, 0.1])
        r.vertices = FamilyEditing.rectangle(.init(u: 0, v: 0), .init(u: 0.4, v: 0.5))
        guard case .failed = FamilyEditing.finish(&r, in: f, value: Self.value(f)) else { Issue.record("crosses the axis"); return }

        var bl = FamilyEditing.Sketch(form: .blend, frame: .plan, depth: 0.5)
        bl.vertices = FamilyEditing.rectangle(.init(u: -0.2, v: -0.2), .init(u: 0.2, v: 0.2))
        guard case .next = FamilyEditing.finish(&bl, in: f, value: Self.value(f)) else { Issue.record("base"); return }
        bl.vertices = FamilyEditing.rectangle(.init(u: -0.1, v: -0.1), .init(u: 0.1, v: 0.1))
        guard case .solid(let blend) = FamilyEditing.finish(&bl, in: f, value: Self.value(f)), case .blend = blend.profile else { Issue.record("blend"); return }
        #expect(blend.zMin == .expr("0") && blend.zMax == .expr("0.5"))

        var region = FamilyEditing.Sketch(form: .maskingRegion, frame: .plan)
        region.vertices = [.init(u: 0, v: 0, uPlane: "Center (Left/Right)"), .init(u: 1, v: 0), .init(u: 1, v: 1)]
        guard case .fill(let fill) = FamilyEditing.finish(&region, in: f, value: Self.value(f)) else { Issue.record("region"); return }
        #expect(fill.isMasking && fill.points[0].x == .plane("Center (Left/Right)"))

        var op = FamilyEditing.Sketch(form: .opening, frame: .front)
        op.vertices = FamilyEditing.rectangle(.init(u: -0.4, v: 0, uPlane: "Left"), .init(u: 0.4, v: 2.1))
        guard case .failed = FamilyEditing.finish(&op, in: f, value: Self.value(f)) else { Issue.record("not hosted"); return }
        let door = StarterLibrary.singleDoor()
        guard case .opening(let o) = FamilyEditing.finish(&op, in: door, value: Self.value(door)) else { Issue.record("opening"); return }
        #expect(o.xMin == .plane("Left") && o.zMax == .expr("2.1"))
    }

    @Test func modelLinesFromAChainAndPurgeUnused() {
        let chain: [FamilyEditing.SketchVertex] = [.init(u: 0, v: 0), .init(u: 1, v: 0), .init(u: 1, v: 0), .init(u: 1, v: 1)]
        let lines = FamilyEditing.modelLines(chain, frame: .right, offset: .plane("Right"), reference: true)
        #expect(lines.count == 2 && lines.allSatisfy { $0.plane == .yz && $0.isReference && $0.offset == .plane("Right") })
        var f = Self.box()
        f.nestedFamilies = [StarterLibrary.handrailProfile(), { var g = StarterLibrary.genericBox(); g.name = "Unused"; return g }()]
        f.solids.append(FamilySolid(name: "Rail", profile: .sweep(FamilySweep(path: [FamilyPoint("0", "0"), FamilyPoint("1", "0")], profile: [], profileFamily: f.nestedFamilies[0].name)),
                                    zMin: .expr("0"), zMax: .expr("0")))
        #expect(FamilyEditing.purgeUnusedNested(&f) == ["Unused"])
        #expect(f.nestedFamilies.count == 1)
    }

    // MARK: Format

    @Test func newContentRoundTripsAndOlderFamiliesDecode() throws {
        var f = Self.box()
        f.controls = [FamilyControl(position: FamilyPoint("0", "-1"), kind: .doubleHorizontal)]
        f.modelLines = [FamilyModelLine(plane: .xz, start: FamilyPoint("0", "0"), end: FamilyPoint("1", "1"))]
        f.modelTexts = [FamilyModelText(text: "Hi", plane: .xy, position: FamilyPoint("0", "0"))]
        f.fills = [FamilyFill(points: Self.square(0.1), isMasking: true)]
        let back = try JSONDecoder().decode(FamilyDefinition.self, from: JSONEncoder().encode(f))
        #expect(back == f)
        // A format-2 family (no F1415 keys, fills without ids) still decodes, the same way every time.
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(f)) as! [String: Any]
        for k in ["controls", "modelLines", "modelTexts"] { obj.removeValue(forKey: k) }
        obj["fills"] = (obj["fills"] as! [[String: Any]]).map { var d = $0; d.removeValue(forKey: "id"); return d }
        let data = try JSONSerialization.data(withJSONObject: obj)
        let old1 = try JSONDecoder().decode(FamilyDefinition.self, from: data), old2 = try JSONDecoder().decode(FamilyDefinition.self, from: data)
        #expect(old1 == old2 && old1.controls.isEmpty && old1.fills.count == 1)
        #expect(old1.minimumReaderVersion < 3)
        // Components saved before Flip Facing existed decode unflipped.
        let comp = try JSONDecoder().decode(ComponentData.self, from: Data(#"{"location":{"x":1,"y":2},"rotation":0,"offset":0,"mirrored":false}"#.utf8))
        #expect(comp.facingFlipped == nil)
    }
}

private extension FamilyBound {
    var text: String { switch self { case .plane(let n): n; case .expr(let e): e } }
}
