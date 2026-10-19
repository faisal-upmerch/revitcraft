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
