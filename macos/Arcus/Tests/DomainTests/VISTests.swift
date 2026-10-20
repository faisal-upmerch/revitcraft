import Foundation
import Testing
@testable import ArcusGeometry
@testable import ArcusDomain

// VIS: curves follow the view's detail level in families, furniture parts and projects; meshes are cached per detail
// level; the turned leg, caster and sketched furniture keep their curves round.

@Suite("VIS smooth curves")
struct VISTests {
    static let inch = 0.0254

    /// A Furniture document with one leg of `type`.
    static func leg(_ type: String, height: Double = 16) throws -> (BIMModel, Element) {
        let m = FurnitureTemplates.blank(category: .furniture, name: type)
        let tx = TransactionContext(model: m, name: "Leg")
        FurniturePartTypes.ensureStandard(in: tx)
        let t = try #require(tx.model.types(for: .furnitureLegs).first { $0.name == type }?.id)
        let id = try FurniturePartOperations.createLeg(at: .zero, extent: PartExtent(topPlane: nil, height: height * inch), typeID: t, in: tx)
        let out = try tx.commit().model
        return (out, try #require(out[id]))
    }

    /// Distinct plan angles of a mesh's vertices around the z axis (its facets around a round leg).
    static func facets(_ mesh: Mesh) -> Int {
        Set(mesh.positions.filter { Vec2($0.x, $0.y).length > 1e-4 }.map { Int((atan2($0.y, $0.x) * 1e4).rounded()) }).count
    }

    @Test func roundLegFacetsFollowTheDetailLevel() throws {
        let (m, e) = try Self.leg("Round 1 1/2\"")
        let counts = DetailLevel.allCases.map { Self.facets(ElementMeshes.parts(e, m, detail: $0).reduce(Mesh()) { var x = $0; x.append($1.mesh); return x }) }
        #expect(counts[0] < counts[1] && counts[1] < counts[2], "\(counts)")
        #expect(counts[2] >= 72, "Fine: 5° facets or finer")
        // Every vertex of the shaft sits on its circle (the chord tolerance holds).
        let r = 0.75 * Self.inch
        let fine = ElementMeshes.parts(e, m, detail: .fine)[0].mesh
        for p in fine.positions where Vec2(p.x, p.y).length > 1e-4 { #expect(abs(Vec2(p.x, p.y).length - r) < 1e-9) }
        #expect(r * (1 - cos(.pi / Double(counts[2]))) <= 0.0002)
    }

    @Test func familyCirclesAndRevolvesUseTheQuality() throws {
        var f = FamilyDefinition(name: "Knob", template: .furniture)
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        f.solids = [FamilySolid(name: "Disc", profile: .circle(center: FamilyPoint("0", "0"), radius: "0.02"), zMin: .expr("0"), zMax: .expr("0.01")),
                    FamilySolid(name: "Turned", profile: .revolve(FamilyRevolve(profile: [FamilyPoint("0", "0"), FamilyPoint("0.03", "0"),
                                                                                             FamilyPoint("0.03", "0.02"), FamilyPoint("0", "0.02")])),
                                zMin: .expr("0.01"), zMax: .expr("0.03"))]
        let coarse = FamilyEvaluator.evaluate(f, typeName: "T", quality: .coarse)
        let fine = FamilyEvaluator.evaluate(f, typeName: "T", quality: .fine)
        #expect(coarse.solids[0].profile.outer.count == TessellationQuality.coarse.fullCircleSegments(radius: 0.02))
        #expect(fine.solids[0].profile.outer.count == TessellationQuality.fine.fullCircleSegments(radius: 0.02))
        #expect(Self.facets(fine.solids[1].familyMesh) >= 72)
        #expect(Self.facets(coarse.solids[1].familyMesh) < Self.facets(fine.solids[1].familyMesh))
        // The default stays Medium.
        #expect(FamilyEvaluator.evaluate(f, typeName: "T").solids[0].profile.outer.count == TessellationQuality.medium.fullCircleSegments(radius: 0.02))
    }

    @Test func storedCurvesAreRefinedInFamilies() throws {
        // A polygon profile written as a 24-sided circle (as the library kit writes round tops) gets rounder at Fine.
        var f = FamilyDefinition(name: "Round Top", template: .furniture)
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        let pts = (0..<24).map { k -> FamilyPoint in let a = 2 * Double.pi * Double(k) / 24; return FamilyPoint("\(0.4 * cos(a))", "\(0.4 * sin(a))") }
        f.solids = [FamilySolid(name: "Top", profile: .polygon(pts), zMin: .expr("0"), zMax: .expr("0.03"))]
        let fine = FamilyEvaluator.evaluate(f, typeName: "T", quality: .fine).solids[0].profile.outer
        let coarse = FamilyEvaluator.evaluate(f, typeName: "T", quality: .coarse).solids[0].profile.outer
        #expect(coarse.count >= 24 && coarse.count < fine.count)
        #expect(fine.count >= 72)
        for p in fine.points { #expect(abs(p.length - 0.4) < 1e-9, "refined points lie on the circle") }
    }

    @Test func meshesAreCachedPerDetailLevel() throws {
        let (m, e) = try Self.leg("Turned 2 1/2\"", height: 18)
        let cache = GeometryCache()
        let fine = cache.parts(e, m, detail: .fine)
        let coarse = cache.parts(e, m, detail: .coarse)
        #expect(cache.count == 2, "one entry per detail level")
        let misses = cache.misses
        _ = cache.parts(e, m, detail: .fine); _ = cache.parts(e, m, detail: .coarse)
        #expect(cache.misses == misses, "switching detail levels hits the cache")
        #expect(fine.reduce(0) { $0 + $1.mesh.triangleCount } > coarse.reduce(0) { $0 + $1.mesh.triangleCount })
        let shaded = cache.shadedParts(e, m, detail: .fine)
        #expect(shaded.count == fine.count)
        #expect(shaded.contains { $0.shaded.silhouetteCount > 0 }, "the turned body has silhouette seams")
    }

    @Test func turnedLegProfileIsAClosedSimpleShape() {
        for (w, h) in [(2.5 * Self.inch, 28 * Self.inch), (2 * Self.inch, 4 * Self.inch)] {
            let prof = FurnitureLegShapes.turnedProfile(width: w, height: h).map { Vec2($0.0, $0.1 * h + $0.2) }
            let poly = Polygon2(prof).simplified()
            #expect(poly.isSimple, "w \(w) h \(h)")
            #expect(prof.allSatisfy { $0.x >= 0 && $0.x <= w / 2 })
        }
    }

    @Test func casterHasAWheelOnAnAxle() throws {
        let (m, e) = try Self.leg("Caster 2\"", height: 3)
        guard let (ev, _) = FurniturePartMeshes.evaluated(e, m, detail: .fine) else { Issue.record("no caster"); return }
        let names = Set(ev.solids.map(\.name))
        for n in ["Wheel", "Axle", "Swivel", "Fork Cheek 1", "Fork Cheek 2"] { #expect(names.contains { $0.hasSuffix(n) }, "\(n) in \(names)") }
    }

    @Test func sketchedArcsKeepTheirQuality() throws {
        let circle = Sketch(loops: [[.arc(Arc2(center: .zero, radius: 0.025, startAngle: 0, sweep: .pi)),
                                     .arc(Arc2(center: .zero, radius: 0.025, startAngle: .pi, sweep: .pi))]])
        guard case .success(let fine) = circle.polygons(quality: .fine), case .success(let old) = circle.polygons() else { Issue.record("no loop"); return }
        #expect(fine[0].count >= 72)
        #expect(old[0].count < 12, "the default 5 mm chord left a 1\" circle with a handful of sides")
    }
}
