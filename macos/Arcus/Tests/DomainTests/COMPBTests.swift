import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// COMPB: Component Library group B (06 Connectors & Fasteners, 07 Legs, Feet & Bases, 08 Shelving Hardware,
/// 09 Wardrobe & Closet, 15 Wheels, Casters & Mobility).
@Suite("COMPB group B components")
struct COMPBTests {
    static var defs: [ComponentDefinition] { ComponentLibrary.groupB }

    @Test func everyDefinitionBuildsAndEvaluates() {
        for d in Self.defs {
            #expect(ComponentKit.validate(d).isEmpty, "\(d.name): \(ComponentKit.validate(d))")
            #expect(!d.aliases.isEmpty && !d.tags.isEmpty, "\(d.name): search data")
            #expect((1...8).contains(d.types.count), "\(d.name): \(d.types.count) types")
            #expect(!d.materials.isEmpty, "\(d.name): material slots")
            #expect(d.family.manufacturer == "Generic")
            #expect(!d.symbols.isEmpty || !d.family.planLines.isEmpty, "\(d.name): 2D symbols")
            for t in d.types {
                #expect(t.cost > 0 && !t.model.isEmpty && !t.sku.isEmpty, "\(d.name) / \(t.name): catalogue data")
                let ev = FamilyEvaluator.evaluate(d.family, typeName: t.name)
                for level in [DetailLevel.medium, .fine] {
                    let shown = ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(level) && !$0.familyMesh.isEmpty }
                    #expect(!shown.isEmpty, "\(d.name) / \(t.name) shows nothing at \(level)")
                }
            }
        }
    }
}
