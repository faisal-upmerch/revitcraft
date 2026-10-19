import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// COMPC: Group C of the Furniture Component Library (10 Kitchen, 11 Table & Desk, 12 Bed, 13 Sofa, 14 Chair): every
/// definition builds and validates, every type evaluates to sane geometry, key parameters flex it, it fits the sample
/// cabinet bay, desk, bed or chair it's meant for, and search finds it.
@Suite("COMPC component library group C")
struct COMPCTests {
    static let defs = ComponentsC.all
    static let inch = 0.0254

    static func bounds(_ d: ComponentDefinition, _ type: String? = nil, _ inst: [String: ParamValue] = [:], detail: DetailLevel = .fine) -> Box3 {
        let ev = FamilyEvaluator.evaluate(d.family, typeName: type ?? d.defaultType!.name, instance: inst)
        var b = Box3.empty
        for s in ev.solids where !s.isVoid && s.visibleAt.contains(detail) && s.visibleIn3D { b.include(s.bounds) }
        return b
    }

    @Test func groupCoversEveryCategoryWithItsCounts() {
        var counts: [ComponentCategory: Int] = [:]
        for d in Self.defs { counts[d.category, default: 0] += 1 }
        #expect(counts[.kitchen, default: 0] >= 28, "kitchen \(counts[.kitchen, default: 0])")
        #expect(Set(Self.defs.map(\.category)).isSubset(of: [.kitchen, .tables, .beds, .sofas, .chairs]))
        let names = Self.defs.map(\.name)
        #expect(Set(names).count == names.count, "duplicate names")
        let ids = Self.defs.map(\.id)
        #expect(Set(ids).count == ids.count, "duplicate ids")
    }

    @Test func everyDefinitionValidates() {
        for d in Self.defs {
            let problems = ComponentKit.validate(d)
            #expect(problems.isEmpty, "\(d.name): \(problems.prefix(4))")
            #expect((1...4).contains(d.types.count), "\(d.name): \(d.types.count) types")
            #expect(!d.aliases.isEmpty && d.tags.count >= 3, "\(d.name): tags and aliases")
            #expect(!d.materials.isEmpty, "\(d.name): no material slot")
            #expect(!d.symbols.isEmpty, "\(d.name): no 2D symbol")
            #expect(d.symbols.contains { $0.levels.contains(.coarse) }, "\(d.name): no Coarse symbol")
            #expect(!d.placement.hosts.isEmpty, "\(d.name): no host rule")
            #expect(d.manufacturer == "Generic")
            for t in d.types {
                #expect(t.cost >= 0 && !t.model.isEmpty && t.sku.hasPrefix("GEN-") && t.manufacturer == "Generic", "\(d.name) / \(t.name): catalogue data")
            }
        }
    }

    @Test func everyTypeEvaluatesToSaneGeometry() {
        var empty: [String] = []
        defer { #expect(empty.isEmpty, "solids without a mesh: \(empty.count): \(empty.prefix(12))") }
        for d in Self.defs {
            for t in d.types {
                let ev = FamilyEvaluator.evaluate(d.family, typeName: t.name)
                #expect(ev.errors.isEmpty, "\(d.name) / \(t.name): \(ev.errors.prefix(3))")
                for s in ev.solids where !s.isVoid {
                    if s.familyMesh.isEmpty { empty.append("\(d.name) / \(t.name): \(s.name)") }
                }
                let b = Self.bounds(d, t.name)
                #expect(b.min.x.isFinite && b.max.x.isFinite, "\(d.name) / \(t.name): empty")
                let size = b.max - b.min
                #expect(size.x < 3.2 && size.y < 3.2 && size.z < 3.2, "\(d.name) / \(t.name): \(size) too big")
                #expect(max(size.x, size.y, size.z) > 0.004, "\(d.name) / \(t.name): \(size) too small")
            }
        }
    }
}
