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
}
