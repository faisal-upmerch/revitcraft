import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain

/// COMP: the Furniture Component Library kit and infrastructure.
@Suite("COMP component kit")
struct COMPKitTests {
    /// A sample face-based component using every geometry helper.
    static func sample() -> ComponentDefinition {
        var b = ComponentBuilder("Kit Sample Handle", .handles, "Bar Handles", "Sample.")
        b.tags("handle", "sample"); b.aliases("pull")
        b.length("Length", ComponentKit.mm(160)); b.length("Hole Spacing", ComponentKit.mm(128))
        b.length("Diameter", ComponentKit.mm(12)); b.length("Projection", ComponentKit.mm(34))
        b.length("Offset", ComponentKit.inch(2.5), instance: true, group: .placement)
        b.material("Finish Material", .satinNickel)
        b.host(ComponentHostKind.fronts, faces: [.front], align: .center)
        b.drill("Handle hole", x: "-Hole Spacing / 2", y: CX.zero, diameter: CX.mm(5), depth: "0.019 m", through: true)
        b.cylinder("Bar", axis: .x, center: (CX.zero, "Projection - Diameter / 2"), radius: "Diameter / 2", from: "-Length / 2", to: "Length / 2")
        b.cylinder("Post", axis: .z, center: ("-Hole Spacing / 2", CX.zero), radius: CX.mm(5), from: CX.zero, to: "Projection - Diameter / 2")
        b.roundedBar("Rose", center: ("Hole Spacing / 2", CX.zero), width: CX.mm(14), height: CX.mm(14), radius: CX.mm(7), from: CX.zero, to: CX.mm(3))
        b.revolve("Knob", profile: ComponentKit.points([(CX.zero, CX.zero), (CX.mm(8), CX.zero), (CX.mm(12), CX.mm(10)), (CX.zero, CX.mm(12))]), base: CX.mm(3))
        b.sweep("Bow", path: ComponentKit.arcPath(center: (CX.zero, CX.zero), radius: CX.mm(40), startDegrees: 0, sweepDegrees: 180),
                profile: ComponentKit.circle(radius: CX.mm(4), segments: 12), plane: .xz)
        b.track("Track", from: "-Length / 2", to: "Length / 2", width: CX.mm(20), height: CX.mm(10), wall: CX.mm(2))
        b.tube("Tube", axis: .y, center: (CX.zero, CX.mm(20)), outer: CX.mm(6), inner: CX.mm(4), from: CX.zero, to: CX.mm(30))
        b.bracket("Bracket", width: CX.mm(20), legA: CX.mm(30), legB: CX.mm(30), thickness: CX.mm(2))
        b.symbol(.top, [.coarse], .line(("-Length / 2", CX.zero), ("Length / 2", CX.zero)))
        b.type("Kit Sample - 128 mm CC", ["Length": ComponentKit.mm(164)], cost: 5.25, model: "KS-128")
        b.type("Kit Sample - 160 mm CC", ["Length": ComponentKit.mm(196), "Hole Spacing": ComponentKit.mm(160)], cost: 6.25, model: "KS-160")
        return b.build()
    }

    @Test func builderProducesAValidFamily() {
        let d = Self.sample()
        #expect(ComponentKit.validate(d).isEmpty, "\(ComponentKit.validate(d))")
        #expect(d.id == "comp.01.kit-sample-handle")
        #expect(d.family.template == .furnitureHardware)
        #expect(d.defaultType?.name == "Kit Sample - 128 mm CC")
        #expect(d.types[0].values["Projection"] == .double(0.034), "defaults fill every type")
        #expect(d.types[0].sku == "GEN-KS-128")
        #expect(d.family.solids.allSatisfy { $0.isVoid || $0.materialParameter == "Finish Material" })
    }

    @Test func fm5FamiliesAreOnTheKit() {
        let fm5 = ComponentLibrary.fm5Components
        #expect(fm5.count == 17)
        for d in fm5 {
            #expect(ComponentKit.validate(d).isEmpty, "\(d.name): \(ComponentKit.validate(d))")
            let spec = FurnitureHardware.library.first { $0.family.name == d.name }
            #expect(spec?.types.map(\.name) == d.types.map(\.name), "\(d.name) keeps FM5's types")
            #expect(d.types.allSatisfy { $0.cost > 0 })
        }
        #expect(ComponentLibrary.component(named: FurnitureHardware.concealedHinge)?.hardwareKind == .hinge)
    }

    @Test func registryIdsAreUnique() {
        let ids = ComponentLibrary.furniture.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ComponentLibrary.furniture.count >= 17)
    }

    @Test func upgradingAnFM5FamilyKeepsItsTypes() throws {
        var b = try #require(ComponentBuilder(upgrading: FurnitureHardware.knob))
        b.aliases("mushroom knob")
        b.type("1 3/4\" Black", ["Diameter": ComponentKit.inch(1.75), "Projection": ComponentKit.inch(1.25)], flags: ["Vertical": false, "On Lid": false],
               cost: 5, model: "KN-175K")
        let up = b.build()
        let old = try #require(ComponentLibrary.fm5Components.first { $0.name == FurnitureHardware.knob })
        let merged = ComponentLibrary.merged(upgrade: up, over: old)
        #expect(merged.types.count == old.types.count + 1)
        #expect(merged.id == old.id)
        #expect(merged.aliases.contains("mushroom knob"))
        #expect(ComponentKit.validate(merged).isEmpty, "\(ComponentKit.validate(merged))")
    }
}
