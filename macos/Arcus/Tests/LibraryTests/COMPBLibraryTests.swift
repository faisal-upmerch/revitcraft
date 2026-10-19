import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// COMPB: sweeps over every Component Library group B definition (slow, so they live with the library suites): each
/// builds and validates, evaluates at Medium and Fine with its catalogue data, symbols and materials, and flexes.
@Suite("COMPB group B definitions")
struct COMPBLibraryTests {
    static var defs: [ComponentDefinition] { ComponentLibrary.groupB }

    @Test func everyDefinitionBuildsAndEvaluates() {
        for d in Self.defs {
            #expect(ComponentKit.validate(d).isEmpty, "\(d.name): \(ComponentKit.validate(d))")
            #expect(!d.aliases.isEmpty && !d.tags.isEmpty, "\(d.name): search data")
            #expect((1...8).contains(d.types.count), "\(d.name): \(d.types.count) types")
            #expect(!d.materials.isEmpty && d.family.manufacturer == "Generic", "\(d.name): materials and manufacturer")
            #expect(d.placement.hosts != [.floor] || d.frame == .plan, "\(d.name): host rule")
            // 2D: a face (or plan) symbol at every level, and a second view (plan of face items, side of plan items) at Coarse.
            for level in DetailLevel.allCases {
                #expect(d.symbols.contains { $0.view == .face && $0.levels.contains(level) }, "\(d.name): face symbol at \(level)")
            }
            #expect(d.symbols.contains { $0.view != .face && $0.levels.contains(.coarse) }, "\(d.name): second view at Coarse")
            for t in d.types {
                #expect(t.cost > 0 && !t.model.isEmpty && t.sku.hasPrefix("GEN-") && t.manufacturer == "Generic", "\(d.name) / \(t.name): catalogue data")
                let ev = FamilyEvaluator.evaluate(d.family, typeName: t.name)
                for level in [DetailLevel.medium, .fine] {
                    let shown = ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(level) && !$0.familyMesh.isEmpty }
                    #expect(!shown.isEmpty, "\(d.name) / \(t.name) shows nothing at \(level)")
                }
            }
        }
    }

    /// Scaling every length of a type flexes the family: it still builds and grows.
    @Test func everyDefinitionFlexes() {
        for d in Self.defs {
            for t in d.types {
                var f = d.family
                guard let k = f.types.firstIndex(where: { $0.name == t.name }) else { continue }
                for (name, v) in f.types[k].values where f.parameter(named: name)?.type == .length {
                    if case .double(let x) = v { f.types[k].values[name] = .double(x * 1.25) }
                }
                let a = FamilyEvaluator.evaluate(d.family, typeName: t.name), b = FamilyEvaluator.evaluate(f, typeName: t.name)
                #expect(b.errors.isEmpty, "\(d.name) / \(t.name) flexed: \(b.errors)")
                func size(_ ev: EvaluatedFamily) -> Double {
                    ev.solids.filter { !$0.isVoid }.reduce(Box3.empty) { $0.union($1.bounds) }.size.length
                }
                #expect(size(b) > size(a) * 1.08, "\(d.name) / \(t.name) doesn't grow: \(size(a)) → \(size(b))")
            }
        }
    }

}
