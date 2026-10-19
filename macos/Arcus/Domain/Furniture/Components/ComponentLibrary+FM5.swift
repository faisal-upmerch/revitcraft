import Foundation
import ArcusGeometry

// COMP: FM5's 17 hardware families on the Component kit. Same family names, parameters, solids and types, so files
// that already use them keep working; the kit adds library data (category, tags, aliases, hosting, mounting, rules,
// symbols, cost and catalogue data from FM5's type specs). Category agents that cover one of these list items upgrade
// it with `ComponentBuilder(upgrading:)` instead of writing a new family.

extension ComponentLibrary {
    /// FM5's hardware families as component definitions.
    static var fm5Components: [ComponentDefinition] {
        FurnitureHardware.library.compactMap(fm5Definition)
    }

    /// Library data of each FM5 family: category, subcategory, frame, tags, aliases.
    struct FM5Meta {
        var category: ComponentCategory, sub: String, frame: ComponentFrame, tags: [String], aliases: [String]
        var hosts: [ComponentHostKind], faces: [ComponentFace], align: ComponentAlignment
    }

    static let fm5Meta: [String: FM5Meta] = {
        let F = FurnitureHardware.self
        return [
            F.concealedHinge: FM5Meta(category: .hinges, sub: "Concealed Hinges", frame: .legacyHinge, tags: ["hinge", "concealed", "cup", "35 mm", "frameless", "soft close", "110"],
                                      aliases: ["euro hinge", "cup hinge", "hidden hinge", "cabinet hinge", "clip-on hinge"], hosts: [.door, .flap, .lid], faces: [.inside], align: .left),
            F.faceFrameHinge: FM5Meta(category: .hinges, sub: "Concealed Hinges", frame: .legacyHinge, tags: ["hinge", "concealed", "cup", "face frame", "35 mm"],
                                      aliases: ["face frame hinge", "compact hinge", "euro hinge"], hosts: [.door], faces: [.inside], align: .left),
            F.buttHinge: FM5Meta(category: .hinges, sub: "Butt Hinges", frame: .legacyHinge, tags: ["hinge", "butt", "leaf", "mortise"],
                                 aliases: ["leaf hinge", "door hinge"], hosts: [.door, .lid], faces: [.leftEdge, .rightEdge], align: .left),
            F.pianoHinge: FM5Meta(category: .hinges, sub: "Continuous Hinges", frame: .legacyHinge, tags: ["hinge", "piano", "continuous", "lid"],
                                  aliases: ["continuous hinge", "strip hinge"], hosts: [.lid, .flap, .door], faces: [.inside], align: .full),
            F.sideMountSlide: FM5Meta(category: .drawers, sub: "Drawer Slides", frame: .legacyOpening, tags: ["slide", "drawer", "side mount", "ball bearing", "full extension"],
                                      aliases: ["drawer runner", "runner", "drawer glide", "ball bearing slide"], hosts: [.bay], faces: [.inside], align: .bottom),
            F.undermountSlide: FM5Meta(category: .drawers, sub: "Drawer Slides", frame: .legacyOpening, tags: ["slide", "drawer", "undermount", "concealed", "soft close"],
                                       aliases: ["concealed runner", "undermount runner", "hidden slide"], hosts: [.bay], faces: [.inside], align: .bottom),
            F.barPull: FM5Meta(category: .handles, sub: "Bar Handles", frame: .legacyFront, tags: ["handle", "pull", "bar"],
                               aliases: ["bar handle", "rail handle", "cabinet handle"], hosts: ComponentHostKind.fronts, faces: [.front], align: .center),
            F.knob: FM5Meta(category: .handles, sub: "Knobs", frame: .legacyFront, tags: ["knob", "handle", "round"],
                            aliases: ["cabinet knob", "round knob", "pull knob"], hosts: ComponentHostKind.fronts, faces: [.front], align: .center),
            F.cupPull: FM5Meta(category: .handles, sub: "Cup Pulls", frame: .legacyFront, tags: ["pull", "cup", "bin", "handle"],
                               aliases: ["bin pull", "shell pull", "cup handle"], hosts: [.drawerFront], faces: [.front], align: .center),
            F.edgePull: FM5Meta(category: .handles, sub: "Edge Pulls", frame: .legacyFront, tags: ["pull", "edge", "handle", "tab"],
                                aliases: ["tab pull", "edge handle", "finger pull"], hosts: ComponentHostKind.fronts, faces: [.topEdge], align: .center),
            F.flapStay: FM5Meta(category: .motion, sub: "Lid Stays", frame: .plan, tags: ["stay", "flap", "lid", "lift up", "drop down"],
                                aliases: ["lid stay", "flap stay", "lift-up mechanism", "lid support"], hosts: [.sidePanel], faces: [.inside], align: .top),
            F.glide: FM5Meta(category: .legs, sub: "Leveling Feet", frame: .plan, tags: ["glide", "leveler", "foot", "adjustable"],
                             aliases: ["leveling foot", "adjustable foot", "leveler", "adjustable leg"], hosts: [.bottom], faces: [.bottom], align: .bottomLeft),
            F.caster: FM5Meta(category: .mobility, sub: "Swivel Casters", frame: .plan, tags: ["caster", "wheel", "swivel"],
                              aliases: ["castor", "wheel", "swivel caster", "plate caster"], hosts: [.bottom], faces: [.bottom], align: .bottomLeft),
            F.shelfPin: FM5Meta(category: .shelving, sub: "Shelf Pins", frame: .plan, tags: ["shelf pin", "shelf support", "pin", "5 mm"],
                                aliases: ["shelf peg", "shelf support", "spoon pin", "shelf rest"], hosts: [.sidePanel, .divider], faces: [.inside], align: .center),
            F.camLock: FM5Meta(category: .connectors, sub: "Cam Connectors", frame: .plan, tags: ["cam", "connector", "knock down", "bolt"],
                               aliases: ["cam and bolt connector", "minifix", "cam fitting", "cam lock"], hosts: [.shelf, .top, .bottom], faces: [.inside], align: .left),
            F.dowel: FM5Meta(category: .connectors, sub: "Dowels", frame: .plan, tags: ["dowel", "wood", "fluted", "joint"],
                             aliases: ["wood dowel", "fluted dowel", "dowel pin"], hosts: ComponentHostKind.carcass, faces: [.any], align: .center),
            F.confirmat: FM5Meta(category: .connectors, sub: "Screws", frame: .plan, tags: ["screw", "confirmat", "connector"],
                                 aliases: ["one-piece connector", "euro screw", "assembly screw"], hosts: ComponentHostKind.carcass, faces: [.any], align: .center),
        ]
    }()

    static func fm5Definition(_ spec: FurnitureHardware.FamilySpec) -> ComponentDefinition? {
        guard let meta = fm5Meta[spec.family.name] else { return nil }
        var b = ComponentBuilder(wrapping: spec.family, meta.category, meta.sub, frame: meta.frame)
        b.definition.tags = meta.tags
        b.definition.aliases = meta.aliases
        b.definition.hardwareKind = spec.kind
        b.definition.materials = [ComponentMaterialSlot(name: FurnitureHardware.finishMaterial,
                                                        finish: spec.kind == .dowel ? .beech : .steel)]
        b.definition.types = spec.types.map { t in
            ComponentType(name: t.name, values: t.values, cost: t.cost, model: t.model, sku: "GEN-\(t.model)", description: t.description)
        }
        if let first = b.definition.types.indices.first { b.definition.types[first].isDefault = true }
        let count: ComponentCountRule? = spec.kind == .hinge && spec.family.name != FurnitureHardware.pianoHinge ? .hinges : nil
        b.host(meta.hosts, faces: meta.faces, align: meta.align, count: count, mirroredPair: spec.kind == .slide)
        switch spec.kind {
        case .hinge:
            b.requires(.hostThickness(min: CX.inch(0.5), max: CX.inch(1.125)))
            b.requires(.overlay(spec.family.name == FurnitureHardware.faceFrameHinge ? ["Half Overlay", "Inset"] : ["Full Overlay", "Half Overlay", "Inset"]))
            b.requires(.maxHostWeight("26 * 2.2 / 2"))
        case .slide:
            b.requires(.fitsDepth("Slide Length + Rear Clearance"))
            b.clearance(.side("Side Clearance")); b.clearance(.rear("Rear Clearance")); b.clearance(.bottom("Bottom Clearance")); b.clearance(.top("Top Clearance"))
        case .handle:
            if spec.family.name != FurnitureHardware.knob { b.requires(.fitsWidth("Length + 0.0254 m")) }
            b.clearance(.box(name: "Finger space", x0: "-0.03 m", x1: "0.03 m", y0: "-0.04 m", y1: "-0.001 m", z0: "-0.025 m", z1: "0 m"))
        default: break
        }
        return b.build()
    }
}

extension ComponentBuilder {
    /// Starts from one of FM5's 17 hardware families (by its `FurnitureHardware` name): its parameters, solids, types,
    /// frame and library data. Add types, aliases, symbols and rules; keep its parameters (fronts and machining read
    /// them). The registry merges the result over the FM5 definition.
    public init?(upgrading fm5Name: String) {
        guard let spec = FurnitureHardware.library.first(where: { $0.family.name == fm5Name }), let d = ComponentLibrary.fm5Definition(spec) else { return nil }
        self.init(wrapping: d.family, d.category, d.subcategory, id: d.id, frame: d.frame)
        definition = d
        definition.family.types = []
        visibleAt = [.medium, .fine]
    }
}
