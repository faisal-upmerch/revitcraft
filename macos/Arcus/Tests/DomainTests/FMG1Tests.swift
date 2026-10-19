import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusApplication

/// FMG1 (Furniture mode parts and flex gaps): angled parts and revolves follow their planes, Slats lay out between
/// planes, turned legs are fast, and the nine library pieces that kept fixed parts now flex fully with two types each.
@Suite("FMG1 Furniture parts and flex") @MainActor
struct FMG1Tests {
    static let inch = 0.0254

    /// The pieces that kept some parts' size before FMG1, and the turned-leg pieces.
    nonisolated static let flexPieces = ["Sun Lounger", "Hammock", "Hanging Chair", "Picnic Table", "Folding Chair", "Swing Bench", "Adirondack Chair",
                             "Folding Screen", "Ladder Shelf"]

    /// Builds, checks and flexes a library piece as FM9C does: Flex passes, Check Parts has no errors, and Width, Depth
    /// and Height scale the whole compiled piece (hardware aside) for every type.
    static func checkFlex(_ name: String) throws {
        let p = try #require(SimpleB.pieces.first { $0.name == name })
        let m = try p.make()
        let setup = try #require(m.furnitureSetup)
        #expect(setup.family.types.count == 2, "\(name): \(setup.family.types.count) types")
        #expect(FurnitureParameters.flex(m).isEmpty, "\(name): \(FurnitureParameters.flex(m).prefix(3))")
        let errors = FurnitureCheckParts.check(m).filter { $0.severity == .error || $0.code == "fm7.material" }
        #expect(errors.isEmpty, "\(name): \(errors.prefix(3).map(\.message))")
        let f = FurnitureCompiler.family(from: m)
        let flex = FamilyEvaluator.flexTest(f, units: .imperial)
        #expect(flex.isEmpty, "\(name): \(flex.prefix(3))")
        for t in f.types {
            let ev0 = FamilyEvaluator.evaluate(f, typeName: t.name, units: .imperial)
            #expect(ev0.errors.isEmpty && !ev0.solids.isEmpty, "\(name) \(t.name): \(ev0.errors.prefix(2))")
            for (param, axis) in [("Width", 0), ("Depth", 1), ("Height", 2)] {
                for scale in [0.85, 1.25] {
                    var g = f
                    guard let i = g.types.firstIndex(where: { $0.name == t.name }), let base = g.types[i].values[param]?.doubleValue else { continue }
                    g.types[i].values[param] = .double(base * scale)
                    let ev = FamilyEvaluator.evaluate(g, typeName: t.name, units: .imperial)
                    #expect(ev.errors.isEmpty, "\(name) \(param) x\(scale): \(ev.errors.prefix(2))")
                    let b = FM9CTests.bounds(ev), b0 = FM9CTests.bounds(ev0)
                    let size = [b.max.x - b.min.x, b.max.y - b.min.y, b.max.z - b.min.z][axis]
                    let size0 = [b0.max.x - b0.min.x, b0.max.y - b0.min.y, b0.max.z - b0.min.z][axis]
                    #expect(abs((size - size0) - base * (scale - 1)) < 1e-3, "\(name) \(t.name) \(param) x\(scale): \(size0 / inch) → \(size / inch)")
                }
            }
        }
    }

    @Test(arguments: flexPieces)
    func libraryPieceFlexesFully(_ name: String) throws { try Self.checkFlex(name) }

    @Test func turnedLegsAreFast() throws {
        for name in ["Decorative Console", "Decorative Bench"] {
            let start = ContinuousClock.now
            let p = try #require(SimpleB.pieces.first { $0.name == name })
            let m = try p.make()
            let legs = m.elements(.furnitureLegs)
            #expect(!legs.isEmpty && legs.allSatisfy { FurniturePartTypes.values(of: $0, m).legShape == .turned }, "\(name) has turned legs")
            for e in Category.furnitureParts.flatMap({ m.elements($0) }) { _ = FurniturePartMeshes.meshParts(e, m, detail: .fine) }
            let f = FurnitureCompiler.family(from: m)
            #expect(FamilyEvaluator.flexTest(f, units: .imperial).isEmpty, "\(name)")
            let elapsed = ContinuousClock.now - start
            #expect(elapsed < .seconds(2), "\(name): \(elapsed)")
        }
    }

    // MARK: Helpers

    static func approx(_ a: Double?, _ b: Double, _ tol: Double = 1e-6) -> Bool { a.map { abs($0 - b) <= tol } ?? false }
    static func plane(_ m: BIMModel, _ name: String) -> ElementID { FurniturePlanes.names(m).first { $0.value == name }!.key }

    /// Adds an aligned dimension between two references in a view; returns its id.
    static func dimension(_ s: DocumentSession, _ refs: [GeometryReference], in view: ElementID, at p: Vec2) -> ElementID? {
        var id: ElementID?
        _ = s.perform("Dimension") { tx in
            id = tx.create(.dimensions, data: .dimension(DimensionData(kind: .aligned, references: refs, linePoint: p)), typeID: tx.model.types(for: .dimensions).first?.id, ownerViewID: view)
        }
        return id
    }

    static func measure(_ s: DocumentSession, _ id: ElementID?) -> Double? { s.model[id].flatMap { AnnotationGeometry.measure($0, s.model).first } }

    // MARK: 1. Dimensions to part faces

    @Test func dimensionsToPartFacesFollowMovedAndFlexedParts() throws {
        let (s, ids) = FM4Tests.bookcase()
        let plan = FM4Tests.view(s.model, "Plan")
        let left = try #require(ids["left"]), right = try #require(ids["right"])
        // The Dimension tool picks a part's nearer face (in plan its sides).
        let ctx = ToolContext(session: s, viewID: plan)
        ctx.pixel = 0.001
        let tool = DimensionTool(ctx: ctx, kind: .aligned)
        var i = ToolInput(point: Vec2(-17.9 * Self.inch, 0), rawPoint: Vec2(-17.9 * Self.inch, 0))
        i.hit = left
        let picked = try #require(tool.reference(for: i)?.0)
        #expect(picked.kind == .partFace && picked.face == PartFaceRef(axis: .x, atMax: false), "\(picked)")
        // Inside faces of the sides: 36" less two 3/4" sides.
        let d = Self.dimension(s, [.partFace(left, PartFaceRef(axis: .x, atMax: true)), .partFace(right, PartFaceRef(axis: .x, atMax: false))], in: plan, at: Vec2(0, -12 * Self.inch))
        #expect(Self.approx(Self.measure(s, d), 34.5 * Self.inch), "\(Self.measure(s, d) ?? 0)")
        FM4Tests.setWidth(s, 48)
        #expect(Self.approx(Self.measure(s, d), 46.5 * Self.inch), "the dimension follows the flexed sides")
        _ = s.perform("Move") { tx in try ElementOperations.transform([right], by: .translation(Vec2(-2 * Self.inch, 0)), in: tx, viewID: nil) }
        #expect(Self.approx(Self.measure(s, d), 44.5 * Self.inch), "and the moved side")
        // In the Front elevation, a shelf's top face is a level line.
        let front = FM4Tests.view(s.model, "Front")
        let h = Self.dimension(s, [GeometryReference(Self.plane(s.model, "Bottom"), .location), .partFace(try #require(ids["shelf2"]), PartFaceRef(axis: .z, atMax: true))],
                               in: front, at: Vec2(30 * Self.inch, 0))
        #expect(Self.approx(Self.measure(s, h), 20 * Self.inch), "\(Self.measure(s, h) ?? 0)")
    }

    @Test func lockedDimensionsConstrainPartsLikeRevit() throws {
        let (s, ids) = FM4Tests.bookcase()
        let front = FM4Tests.view(s.model, "Front"), plan = FM4Tests.view(s.model, "Plan")
        let shelf = try #require(ids["shelf2"])
        // Lock shelf 2's top 10" below the Top: it follows the Top when Height changes (it was on the Bottom).
        let d = try #require(Self.dimension(s, [GeometryReference(Self.plane(s.model, "Top"), .location), .partFace(shelf, PartFaceRef(axis: .z, atMax: true))],
                                            in: front, at: Vec2(30 * Self.inch, 0)))
        _ = s.perform("Lock") { tx in tx.update(d) { $0.dimension?.locked = true } }
        #expect(s.lastError == nil)
        FM4Tests.set(s, "Height", 40)
        #expect(Self.approx(s.model[shelf]?.furnitureShelf?.elevation, 30 * Self.inch), "\((s.model[shelf]?.furnitureShelf?.elevation ?? 0) / Self.inch)")
        #expect(s.model[shelf]?.furnitureShelf?.bounds["z"] == .plane("Top", offset: -10 * Self.inch), "the shelf locks to the Top")
        // Moving the locked shelf by hand is refused.
        _ = s.perform("Move Shelf") { tx in tx.update(shelf) { $0.furnitureShelf?.elevation = 25 * Self.inch } }
        #expect(s.lastError?.message.contains("Constraints are not satisfied") == true, "\(s.lastError?.message ?? "")")
        #expect(Self.approx(s.model[shelf]?.furnitureShelf?.elevation, 30 * Self.inch))
        // Unlocked, it moves.
        _ = s.perform("Unlock") { tx in tx.update(d) { $0.dimension?.locked = false } }
        _ = s.perform("Move Shelf") { tx in tx.update(shelf) { $0.furnitureShelf?.elevation = 25 * Self.inch } }
        #expect(s.lastError == nil && Self.approx(s.model[shelf]?.furnitureShelf?.elevation, 25 * Self.inch))
        // Two part faces locked 36" apart: moving one side moves the other with it.
        let left = try #require(ids["left"]), right = try #require(ids["right"])
        let w = try #require(Self.dimension(s, [.partFace(left, PartFaceRef(axis: .x, atMax: false)), .partFace(right, PartFaceRef(axis: .x, atMax: true))], in: plan, at: Vec2(0, -12 * Self.inch)))
        _ = s.perform("Lock") { tx in tx.update(w) { $0.dimension?.locked = true } }
        _ = s.perform("Move") { tx in try ElementOperations.transform([right], by: .translation(Vec2(2 * Self.inch, 0)), in: tx, viewID: nil) }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        #expect(Self.approx(Self.measure(s, w), 36 * Self.inch), "\((Self.measure(s, w) ?? 0) / Self.inch)")
        #expect(Self.approx(FurniturePartSolids.partBox(s.model[left]!, s.model)?.box.min.x, -16 * Self.inch), "the left side followed")
    }

    // MARK: 2. Blend: Edit Top

    @Test func blendSketchesItsBaseAndTopSeparately() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        let ctx = ToolContext(session: s, viewID: FM4Tests.view(s.model, "Plan"))
        let tool = SketchTool.furniture(ctx, .form(.blend, isVoid: false), commandID: .furnitureBlend)
        #expect(tool.isBlendSketch && !tool.isEditingBlendTop && tool.title == "Blend Base Boundary")
        tool.setOption("fm4.start", .double(2 * Self.inch))
        tool.setOption("fm4.end", .double(10 * Self.inch))
        tool.setOption("mode", .text("Rectangle"))
        FM4Tests.click(tool, Vec2(-0.2, -0.2)); FM4Tests.click(tool, Vec2(0.2, 0.2))
        #expect(!tool.finish(), "a blend needs its top too")
        tool.editBlend(top: true)
        #expect(tool.isEditingBlendTop && tool.title == "Blend Top Boundary" && tool.curves.isEmpty)
        tool.setOption("mode", .text("Rectangle"))
        FM4Tests.click(tool, Vec2(-0.05, -0.05)); FM4Tests.click(tool, Vec2(0.05, 0.05))
        #expect(tool.preview.primitives.count >= 8, "the base shows under the top")
        tool.editBlend(top: false)
        #expect(tool.curves.count == 4 && !tool.isEditingBlendTop)
        tool.editBlend(top: true)
        #expect(tool.finish())
        let e = try #require(s.model.elements(.furnitureForms).first)
        let f = try #require(e.furnitureForm)
        #expect(f.kind == .blend && Self.approx(Polygon2(f.profile).area, 0.16) && Self.approx(Polygon2(f.topProfile ?? []).area, 0.01))
        #expect(Self.approx(f.w0, 2 * Self.inch) && Self.approx(f.w1, 10 * Self.inch), "First End and Second End")
        // Edit Top on the selected blend: its top opens with the base kept.
        let edit = try #require(SketchTool.editBlend(ctx, e.id, top: true, commandID: .furnitureBlend))
        #expect(edit.isEditingBlendTop && edit.curves.count == 4)
        edit.cancelSketch()
        let edit2 = try #require(SketchTool.editBlend(ctx, e.id, top: true, commandID: .furnitureBlend))
        edit2.curves = Polygon2.rectangle(Rect2(min: Vec2(-0.1, -0.1), max: Vec2(0.1, 0.1))).edges.map { .line($0) }
        #expect(edit2.finish())
        #expect(Self.approx(Polygon2(s.model[e.id]?.furnitureForm?.topProfile ?? []).area, 0.04) && s.model.elements(.furnitureForms).count == 1)
        #expect(CommandCatalog.info(.furnitureBlendEditTop).title == "Edit Top" && CommandCatalog.info(.furnitureBlendEditBase).title == "Edit Base")
    }

    // MARK: 3. Sweeps in any view

    @Test func sweepPathsAreSketchedOnTheWorkPlaneInElevations() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        let ctx = ToolContext(session: s, viewID: FM4Tests.view(s.model, "Front"))
        let sw = SketchTool.furniture(ctx, .form(.sweep, isVoid: false), commandID: .furnitureSweep)
        let modes: [String] = sw.options.first.flatMap { o -> [String]? in if case .choice(let c) = o.kind { return c }; return nil } ?? []
        #expect(modes.contains("Pick Path") && !modes.contains("Pick Lines"))
        FM4Tests.click(sw, Vec2(-0.3, 0.2)); FM4Tests.click(sw, Vec2(0, 0.4)); FM4Tests.click(sw, Vec2(0.3, 0.2))
        _ = sw.escape()
        sw.setOption("mode", .text("Rectangle"))
        FM4Tests.click(sw, Vec2(0.5, 0.5)); FM4Tests.click(sw, Vec2(0.52, 0.53))
        #expect(sw.finish(), "a sweep in an elevation")
        let e = try #require(s.model.elements(.furnitureForms).first)
        let f = try #require(e.furnitureForm)
        #expect(f.plane == .xz && f.path?.count == 3)
        let b = FurniturePartMeshes.meshParts(e, s.model, detail: .fine).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        let frontPlane = FurniturePlanes.positionsByName(s.model)["Front"] ?? 0
        // The path stays in the Front plane's (x, z); the profile reaches 0.03 m into the piece from it.
        #expect(Self.approx(b.min.y, frontPlane, 1e-4) && Self.approx(b.max.y, frontPlane + 0.03, 1e-4), "\(b)")
        #expect(b.min.x < -0.29 && b.max.x > 0.29 && b.max.z > 0.4 && b.min.z > 0.17, "\(b)")
        // It compiles: the loaded family has the same sweep.
        let fam = FurnitureCompiler.family(from: s.model)
        let ev = FamilyEvaluator.evaluate(fam, typeName: fam.types[0].name, units: .imperial)
        let sb = try #require(ev.solids.first { $0.form == .sweep }).bounds
        #expect(Self.approx(sb.min.y, b.min.y, 1e-6) && Self.approx(sb.max.z, b.max.z, 1e-6))
    }

    // MARK: 4. Angled parts and revolves

    @Test func angledRailsAndLockedRevolvesFlex() throws {
        let s = DocumentSession(model: FurnitureTemplates.blank())
        var rail: ElementID?, rev: ElementID?
        // A raked rail drawn in a side elevation from the Front at the floor to the Back at the Top.
        _ = s.perform("Rail") { tx in
            rail = try FurniturePartOperations.createRail(start: Vec2(-9 * Self.inch, 0), end: Vec2(9 * Self.inch, 30 * Self.inch), plane: .yz, w: 0, justification: .center, in: tx)
            var f = FurnitureFormData(kind: .revolve, profile: [Vec2(0, 0), Vec2(18 * Self.inch, 0), Vec2(18 * Self.inch, 1 * Self.inch), Vec2(0, 1 * Self.inch)], w0: 0, w1: 0)
            f.axis = .zero
            rev = try FurniturePartOperations.createForm(f, in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let r = try #require(s.model[rail]?.furnitureRail)
        #expect(r.bounds["start.u"] == .plane("Front", offset: 0) && r.bounds["end.v"] == .plane("Top", offset: 0))
        #expect(s.model[rev]?.furnitureForm?.bounds?["p1.r"] == .plane("Right", offset: 0), "the revolve's edge locks to the Right")
        let f0 = FurnitureCompiler.family(from: s.model)
        FM4Tests.set(s, "Depth", 24)
        FM4Tests.setWidth(s, 48)
        #expect(Self.approx(s.model[rail]?.furnitureRail?.end.x, 12 * Self.inch) && Self.approx(s.model[rev]?.furnitureForm?.profile[1].x, 24 * Self.inch))
        // The family compiled at the first size, flexed to the new size, matches the document.
        var g = f0
        g.types[0].values["Depth"] = .double(24 * Self.inch); g.types[0].values["Width"] = .double(48 * Self.inch)
        let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
        #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
        let doc = FurniturePartMeshes.meshParts(s.model[rail]!, s.model, detail: .medium).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        let fam = try #require(ev.solids.first { $0.name == s.model[rail]!.mark }).bounds
        #expect(Self.approx(fam.min.y, doc.min.y, 1e-6) && Self.approx(fam.max.y, doc.max.y, 1e-6) && Self.approx(fam.max.z, doc.max.z, 1e-6), "\(fam) vs \(doc)")
        let disc = try #require(ev.solids.first { $0.form == .revolve }).bounds
        #expect(Self.approx(disc.max.x, 24 * Self.inch, 1e-4), "\(disc.max.x / Self.inch)")
        // Cut level at the floor, the rail stands on it.
        _ = s.perform("Cut") { tx in tx.update(rail!) { $0.furnitureRail?.startCut = .horizontal } }
        let cut = FurniturePartMeshes.meshParts(s.model[rail]!, s.model, detail: .medium).reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        #expect(Self.approx(cut.min.z, 0, 1e-9) && doc.min.z < -1e-3)
    }

    // MARK: 5. Slats follow the planes

    @Test func slatsLayOutAgainAsThePieceFlexes() throws {
        let (s, ids) = FM4Tests.bookcase()
        var slats: ElementID?, max: ElementID?
        let li = 17.25 * Self.inch
        _ = s.perform("Slats") { tx in
            slats = try FurniturePartOperations.createSlats(in: Rect2(min: Vec2(-li, -9 * Self.inch), max: Vec2(li, 9 * Self.inch)), alongX: false, rule: .fixedDistance,
                                                            spacing: 4 * Self.inch, number: 0, z: -2 * Self.inch, zPlane: "Top", in: tx)
            max = try FurniturePartOperations.createSlats(in: Rect2(min: Vec2(-li, -9 * Self.inch), max: Vec2(li, 9 * Self.inch)), alongX: false, rule: .maximumSpacing,
                                                          spacing: 4 * Self.inch, number: 0, z: -4 * Self.inch, zPlane: "Top", in: tx)
        }
        #expect(s.lastError == nil, "\(s.lastError?.message ?? "")")
        let r0 = try #require(s.model[slats]?.furnitureRail)
        // The first slat and the far side lock to the sides' inside faces (half a slat in).
        let w = FurniturePartTypes.values(of: s.model[slats]!, s.model).width
        #expect(r0.bounds["start.u"] == .plane("Left", offset: 0.75 * Self.inch + w / 2) && r0.bounds["far"] == .plane("Right", offset: -0.75 * Self.inch - w / 2), "\(r0.bounds)")
        let n0 = r0.slats!.offsets.count
        let f0 = FurnitureCompiler.family(from: s.model)
        FM4Tests.setWidth(s, 48)
        let r1 = try #require(s.model[slats]?.furnitureRail)
        #expect(Self.approx(r1.slats?.extent, r0.slats!.extent + 12 * Self.inch) && r1.slats!.offsets.count == n0 + 3, "Fixed Distance adds slats")
        let m1 = try #require(s.model[max]?.furnitureRail?.slats)
        #expect(m1.offsets.count == Int((m1.extent / (4 * Self.inch) - 1e-9).rounded(.up)) + 1 && Self.approx(m1.offsets.last, m1.extent), "Maximum Spacing keeps the sides")
        // The compiled family flexes the same way: the count is a formula and the extra slats show.
        var g = f0
        g.types[0].values["Width"] = .double(48 * Self.inch)
        let ev = FamilyEvaluator.evaluate(g, typeName: g.types[0].name, units: .imperial)
        #expect(ev.errors.isEmpty, "\(ev.errors.prefix(2))")
        let mark = s.model[slats]!.mark, maxMark = s.model[max]!.mark
        #expect(ev.solids.filter { $0.name.hasPrefix("\(mark) Slat") }.count == n0 + 3, "\(ev.solids.filter { $0.name.hasPrefix(mark) }.count)")
        let maxSolids = ev.solids.filter { $0.name.hasPrefix("\(maxMark) Slat") }
        #expect(maxSolids.count == m1.offsets.count)
        let xs = maxSolids.map(\.bounds)
        #expect(Self.approx(xs.map(\.min.x).min(), -24 * Self.inch + 0.75 * Self.inch, 1e-6) && Self.approx(xs.map(\.max.x).max(), 24 * Self.inch - 0.75 * Self.inch, 1e-6))
        _ = ids
    }
}
