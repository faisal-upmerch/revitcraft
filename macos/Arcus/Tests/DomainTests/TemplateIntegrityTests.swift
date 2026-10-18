import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// New projects combine content from several libraries (standard types, annotation styles, materials); nothing may be
/// defined twice.
@Suite("Project template integrity")
struct TemplateIntegrityTests {
    @Test(arguments: [UnitSystem.imperial, .metric])
    func namesAreUniqueInNewProjects(_ system: UnitSystem) {
        let units: UnitsSettings = system == .imperial ? .imperial : .metric
        for kind in [ProjectTemplateKind.architectural, .empty] {
            let (m, _) = ProjectTemplates.make(kind, units: units)
            var seen: [String: Int] = [:]
            for t in m.elements(.elementTypes) {
                let key = "\(t.typeData?.instanceCategory.rawValue ?? "?") / \(t.typeData?.familyName ?? "") / \(t.name)"
                seen[key, default: 0] += 1
            }
            let dupTypes = seen.filter { $0.value > 1 }.map(\.key).sorted()
            #expect(dupTypes.isEmpty, "\(kind) \(system): duplicate types \(dupTypes.prefix(10))")
            let mats = Dictionary(grouping: m.materials, by: \.name).filter { $0.value.count > 1 }.map(\.key).sorted()
            #expect(mats.isEmpty, "\(kind) \(system): duplicate materials \(mats.prefix(10))")
            let styles = Dictionary(grouping: m.elements(.lineStyles), by: \.name).filter { $0.value.count > 1 }.map(\.key).sorted()
            #expect(styles.isEmpty, "\(kind) \(system): duplicate line styles \(styles.prefix(10))")
        }
    }
}
