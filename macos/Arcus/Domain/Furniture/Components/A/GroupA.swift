import Foundation
import ArcusGeometry

// COMPA: Group A's starters. Front hardware (handles, hinges, slides) uses FM5's legacy frames and parameter names so
// doors, drawers and flaps place, flip and machine it as they do FM5's families; everything else is face- or
// plan-based (ComponentKit.swift header).

/// Group A's component definitions (01 Handles, 02 Locks, 03 Hinges, 04 Drawer Systems, 05 Sliding Doors).
enum GroupA {
    static let F = FurnitureHardware.self
    static func mm(_ v: Double) -> Double { v / 1000 }
    static func inch(_ v: Double) -> Double { v * 0.0254 }
    static let finish = FurnitureHardware.finishMaterial

    /// A new family, or an upgrade of an FM5 one (its solids, types, symbols and rules cleared, its parameters kept with
    /// their FM5 values as defaults).
    static func starter(_ name: String, _ category: ComponentCategory, _ sub: String, _ description: String, frame: ComponentFrame,
                        upgrading fm5: String? = nil) -> ComponentBuilder {
        guard let fm5, var b = ComponentBuilder(upgrading: fm5) else { return ComponentBuilder(name, category, sub, description, frame: frame) }
        let first = b.definition.types.first?.values ?? [:]
        for k in b.definition.parameters.indices where b.definition.parameters[k].formula == nil && b.definition.parameters[k].defaultValue == nil {
            b.definition.parameters[k].defaultValue = first[b.definition.parameters[k].name]
        }
        b.definition.family.solids = []
        b.definition.family.planLines = []
        b.definition.types = []
        b.definition.symbols = []
        b.definition.requirements = []
        b.definition.clearances = []
        b.definition.mounting = []
        b.definition.subcategory = sub
        b.definition.family.description = description
        return b
    }

    /// Sets the finish material slot's default (FM5's slot is Finish Material).
    static func setFinish(_ b: inout ComponentBuilder, _ f: ComponentFinish, slot: String = FurnitureHardware.finishMaterial) {
        if let k = b.definition.materials.firstIndex(where: { $0.name == slot }) { b.definition.materials[k].finish = f } else { b.material(slot, f) }
    }

    // MARK: Handles

    /// A front handle in FM5's front frame (local a along it, b across, c out of the face), hosted on fronts.
    static func handle(_ name: String, _ sub: String, _ description: String, finish f: ComponentFinish = .satinNickel, upgrading fm5: String? = nil,
                       edge: Bool = false) -> ShapeA {
        var b = starter(name, .handles, sub, description, frame: .legacyFront, upgrading: fm5)
        setFinish(&b, f)
        ShapeA.frontFlags(&b)
        b.length("Front Thickness", inch(0.75), instance: true, group: .placement)
        b.hardwareKind(.handle)
        if edge {
            b.flag("Edge Mounted", true, instance: false, group: .manufacturing)
            b.host(ComponentHostKind.fronts, faces: [.topEdge], align: .center, alignments: [.center, .left, .right, .inside])
        } else {
            b.host(ComponentHostKind.fronts, faces: [.front], align: .center, alignments: [.center, .inside, .top, .bottom, .topLeft, .topRight],
                   offsetX: inch(2.5), offsetY: inch(2.5))
        }
        b.tags("handle", "pull", "hardware")
        return ShapeA(b, frames: FrameA.front)
    }

    /// The two screw holes of a two-post handle, through the front.
    static func postHoles(_ b: inout ComponentBuilder, spacing: String = "Hole Spacing", diameter: String = "Hole Diameter") {
        b.drill("Handle hole", x: "-(\(spacing)) / 2", y: CX.zero, diameter: diameter, depth: "Host Thickness", through: true)
        b.drill("Handle hole", x: "(\(spacing)) / 2", y: CX.zero, diameter: diameter, depth: "Host Thickness", through: true)
    }

    /// Finger space in front of a pull.
    static func fingerSpace(_ b: inout ComponentBuilder, length: String = "Length", projection: String = "Projection") {
        b.clearance(.box(name: "Finger space", x0: "-(\(length)) / 2", x1: "(\(length)) / 2", y0: CX.mm(-25), y1: CX.mm(25), z0: CX.zero, z1: "(\(projection)) + 0.02 m"))
    }

    /// Coarse symbols of a front item: its outline on the face and its depth seen from above.
    static func coarse(_ g: inout ShapeA, length: String, height: String, projection: String) {
        g.b.symbol(.face, [.coarse], .rect(("-(\(length)) / 2", "-(\(height)) / 2"), ("(\(length)) / 2", "(\(height)) / 2")))
        g.b.symbol(.top, [.coarse], .rect(("-(\(length)) / 2", CX.zero), ("(\(length)) / 2", projection)))
    }

    /// Coarse symbols of a round front item.
    static func coarseRound(_ g: inout ShapeA, diameter: String, projection: String) {
        g.b.symbol(.face, [.coarse], .circle((CX.zero, CX.zero), "(\(diameter)) / 2"))
        g.b.symbol(.top, [.coarse], .rect(("-(\(diameter)) / 2", CX.zero), ("(\(diameter)) / 2", projection)))
    }
}

extension GroupA {
    /// Every Group A definition, in browser order.
    static var all: [ComponentDefinition] { handles + locks + hinges + drawers }
}
