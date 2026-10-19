import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// COMPA: Group A of the Furniture Component Library (handles, locks, hinges, drawer systems, sliding doors), and the
/// evaluator support it needs (revolves and blends on side work planes).
@Suite("COMPA components")
struct COMPATests {
    // MARK: FM5 hardware values recognise component families by their parameters

    static func td(_ family: String, _ values: [String: ParamValue]) -> TypeData {
        var p: [ParameterID: ParamValue] = [:]
        for (k, v) in values { p[Parameters.familyParamID(k)] = v }
        return TypeData(instanceCategory: .furnitureHardware, familyName: family, params: p)
    }

    @Test func hardwareValuesReadParameters() {
        typealias V = FurnitureHardware.Values
        // New families: by parameters.
        #expect(V(Self.td("Soft-Close Hinge", ["Cup Diameter": .double(0.035)])).isConcealed)
        #expect(!V(Self.td("Detachable Hinge", ["Leaf Height": .double(0.05)])).isConcealed)
        #expect(V(Self.td("Mushroom Knob", ["Hole Spacing": .double(0)])).isKnob)
        #expect(V(Self.td("Mushroom Knob", ["Hole Spacing": .double(0)])).handleHoleSpacing == 0)
        #expect(!V(Self.td("Bow Handle", ["Hole Spacing": .double(0.128)])).isKnob)
        #expect(V(Self.td("J-Pull Profile", ["Edge Mounted": .bool(true)])).isEdgePull)
        #expect(V(Self.td("Concealed Drawer Runners", ["Undermount": .bool(true)])).isUndermount)
        #expect(V(Self.td("Continuous Hinge", ["Continuous": .bool(true)])).isPiano)
        #expect(!V(Self.td("Drawer Slide - Ball Bearing", ["Undermount": .bool(false)])).isUndermount)
        // FM5 families: by name, as before.
        #expect(V(Self.td(FurnitureHardware.knob, [:])).isKnob)
        #expect(V(Self.td(FurnitureHardware.concealedHinge, [:])).isConcealed)
        #expect(V(Self.td(FurnitureHardware.edgePull, [:])).isEdgePull)
        #expect(V(Self.td(FurnitureHardware.undermountSlide, [:])).isUndermount)
        #expect(V(Self.td(FurnitureHardware.pianoHinge, [:])).isPiano)
        #expect(!V(Self.td(FurnitureHardware.barPull, ["Hole Spacing": .double(0.128)])).isKnob)
    }

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
