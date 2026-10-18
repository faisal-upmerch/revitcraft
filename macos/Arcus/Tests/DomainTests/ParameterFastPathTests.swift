import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// Schedules and tags use `descriptor(named:)`, `value(_:of:)` and `isEditable` instead of building every entry.
/// These must agree with `allEntries` (the inspector's view) for every parameter of every element.
@Suite("Parameter fast paths")
struct ParameterFastPathTests {
    @Test func fastPathsMatchAllEntries() {
        let m = CourtyardHouse.make()
        var checked = 0
        let sample = [Category.walls, .doors, .windows, .rooms, .floors, .roofs, .stairs, .columns, .furniture, .ceilings]
            .flatMap { m.elements($0).prefix(12) }
        for e in sample {
            let entries = Parameters.allEntries(e, m)
            var seenNames = Set<String>()
            for entry in entries {
                // Editability of the first entry with this id.
                if entries.first(where: { $0.id == entry.id })?.name == entry.name {
                    #expect(Parameters.isEditable(entry.id, on: e, m) == !entry.isReadOnly, "\(e.category) \(entry.name) editable")
                }
                // Name lookup resolves to the first entry with that name, and its value matches.
                guard seenNames.insert(entry.name).inserted else { continue }
                let d = Parameters.descriptor(named: entry.name, for: e, m)
                #expect(d?.id == entry.id, "\(e.category) \(entry.name) id")
                #expect(d?.type == entry.type, "\(e.category) \(entry.name) type")
                #expect(Parameters.format(Parameters.value(entry.id, of: e, m), type: entry.type, model: m)
                        == Parameters.format(entry.value, type: entry.type, model: m), "\(e.category) \(entry.name) value")
                checked += 1
            }
        }
        #expect(checked > 500)
    }
}
