import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// COMPA: Group A of the Furniture Component Library (handles, locks, hinges, drawer systems, sliding doors), and the
/// evaluator support it needs (revolves and blends on side work planes).
@Suite("COMPA components")
struct COMPATests {
    // MARK: Revolves and blends on side work planes

    /// A knob-like revolve: radius 10 mm, 20 mm tall, about the sketch's vertical axis.
    static func revolveFamily(_ plane: FamilySketchPlane?) -> FamilyDefinition {
        var f = FamilyDefinition(name: "Revolve Test", template: .furnitureHardware)
        let profile = [FamilyPoint("0 m", "0 m"), FamilyPoint("0.01 m", "0 m"), FamilyPoint("0.01 m", "0.02 m"), FamilyPoint("0 m", "0.02 m")]
        var s = FamilySolid(name: "Knob", profile: .revolve(FamilyRevolve(profile: profile, axis: FamilyPoint("0.05 m", "0 m"))), zMin: .expr("0 m"), zMax: .expr("0 m"))
        s.workPlane = plane
        f.solids = [s]
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        return f
    }

    @Test func revolveOnXZTurnsAboutY() throws {
        let ev = FamilyEvaluator.evaluate(Self.revolveFamily(.xz), typeName: "T")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = try #require(ev.solids.first).bounds
        // The axis runs along family Y through x = 0.05, z = 0; the profile's height runs along +Y.
        #expect(abs(b.min.y) < 1e-6 && abs(b.max.y - 0.02) < 1e-6)
        #expect(abs(b.min.x - 0.04) < 1e-4 && abs(b.max.x - 0.06) < 1e-4)
        #expect(abs(b.min.z + 0.01) < 1e-4 && abs(b.max.z - 0.01) < 1e-4)
    }

    @Test func revolveOnYZTurnsAboutX() throws {
        let ev = FamilyEvaluator.evaluate(Self.revolveFamily(.yz), typeName: "T")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = try #require(ev.solids.first).bounds
        #expect(abs(b.min.x) < 1e-6 && abs(b.max.x - 0.02) < 1e-6)
        #expect(abs(b.min.y - 0.04) < 1e-4 && abs(b.max.y - 0.06) < 1e-4)
    }

    @Test func planRevolveIsUnchanged() throws {
        for plane in [nil, FamilySketchPlane.xy] {
            let ev = FamilyEvaluator.evaluate(Self.revolveFamily(plane), typeName: "T")
            let b = try #require(ev.solids.first).bounds
            #expect(abs(b.min.z) < 1e-6 && abs(b.max.z - 0.02) < 1e-6)
            #expect(abs(b.min.x - 0.04) < 1e-4 && abs(b.max.x - 0.06) < 1e-4)
        }
    }

    @Test func blendOnXZRunsAlongY() throws {
        var f = FamilyDefinition(name: "Blend Test", template: .furnitureHardware)
        let sq = { (h: String) in [FamilyPoint("-\(h)", "-\(h)"), FamilyPoint(h, "-\(h)"), FamilyPoint(h, h), FamilyPoint("-\(h)", h)] }
        var s = FamilySolid(name: "Frustum", profile: .blend(FamilyBlend(bottom: sq("0.02 m"), top: sq("0.01 m"))), zMin: .expr("0 m"), zMax: .expr("0.03 m"))
        f.types = [FamilyTypeDefinition(name: "T", values: [:])]
        f.solids = [s]
        let flat = FamilyEvaluator.evaluate(f, typeName: "T")
        let fb = try #require(flat.solids.first).bounds
        #expect(abs(fb.max.z - 0.03) < 1e-6 && abs(fb.max.y - 0.02) < 1e-6)
        s.workPlane = .xz
        f.solids = [s]
        let ev = FamilyEvaluator.evaluate(f, typeName: "T")
        #expect(ev.errors.isEmpty, "\(ev.errors)")
        let b = try #require(ev.solids.first).bounds
        #expect(abs(b.min.y) < 1e-6 && abs(b.max.y - 0.03) < 1e-6)
        #expect(abs(b.max.z - 0.02) < 1e-6 && abs(b.max.x - 0.02) < 1e-6)
    }
}
