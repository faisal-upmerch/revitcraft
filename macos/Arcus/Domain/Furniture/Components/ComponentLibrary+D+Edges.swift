import Foundation
import ArcusGeometry

// COMPD: 18 Edge Treatments & Profiles. Three kinds:
// - Edge banding (role Edge Banding): PVC, ABS, veneer, pre-glued and solid lipping, as strips on a part's edge. Each
//   type is also an edge band material (cost per linear foot) with its thickness, for parts' Edge Band Material
//   (ComponentLibrary+D+EdgeTypes.swift).
// - Cut profiles (role Edge Profile): round-over, chamfer, bullnose, bevel, finger pull and countertop edges. Each type
//   is also an Edge Profile type the Edge Profile tool cuts (Profile, Size, Depth); the component itself is a short
//   profiled sample of the edge.
// - Profile components swept along the host edge or face: aluminium edge caps, T-molding (with its slot), U, L and J
//   channels, trims, corner protectors, handleless channels, plinth and toe-kick profiles and panel joint profiles.
//
// Edge items use the edge face frame: X along the edge, Y across the panel's thickness (centred), Z out of the edge
// (the panel is at Z < 0).

extension ComponentLibrary {
    static var groupDEdges: [ComponentDefinition] {
        [edgeBanding(), pvcBanding(), absBanding(), veneerEdge(), solidLipping(), aluminumEdge(), tMolding(), uChannel(), lChannel(), jChannel(),
         decorativeTrim(), cornerProtector(), roundedEdge(), chamferedEdge(), bullnoseEdge(), beveledEdge(), fingerPullGroove(), handlelessChannel(),
         plinthProfile(), toeKickProfile(), countertopEdge(), panelJoint()]
    }

    static let edgeFaces: [ComponentFace] = [.frontEdge, .topEdge, .bottomEdge, .leftEdge, .rightEdge]
    static let edgeHosts: [ComponentHostKind] = [.sidePanel, .divider, .shelf, .top, .bottom, .door, .drawerFront, .flap, .lid, .back]

    // MARK: Edge banding

    /// A banding strip on the edge face: Band Width across the edge (≥ the panel), Thickness out of it.
    fileprivate static func banding(_ name: String, _ sub: String, _ description: String, finish: ComponentFinish, tags: [String], aliases: [String],
                                    types: [(String, Double, Double, Double, String)]) -> ComponentDefinition {
        var b = ComponentBuilder(name, .edges, sub, description)
        b.definition.tags = tags + ["edge banding", "edge", "banding"]
        b.definition.aliases = aliases
        b.role(.edgeBanding)
        b.material("Band Material", finish)
        b.runLength(DK.feet(2), max: 6)
        b.length("Thickness", types[0].1); b.length("Band Width", types[0].2)
        b.length("Trim Allowance", DK.mm(1), group: .manufacturing)
        b.hostRun(edgeHosts, faces: edgeFaces)
        b.runBox("Band", y: ("-Band Width / 2", "Band Width / 2"), z: (DK.z, "Thickness"))
        b.profile(DK.pts([("-Band Width / 2", DK.z), ("Band Width / 2", DK.z), ("Band Width / 2", "Thickness"), ("-Band Width / 2", "Thickness")]))
        b.runOutlines(y: ("-Band Width / 2", "Band Width / 2"), z: (DK.z, "Thickness"))
        b.requires(.hostThickness(min: nil, max: "Band Width"))
        for (k, t) in types.enumerated() {
            b.type(t.0, ["Thickness": t.1, "Band Width": t.2], cost: t.3, model: t.4, description: "\(t.0), per linear foot", isDefault: k == 0)
        }
        return b.build()
    }

    static func edgeBanding() -> ComponentDefinition {
        banding("Edge Banding", "Edge Banding", "Pre-glued (hot-melt) birch veneer edge banding, ironed on and trimmed flush.", finish: .hotMelt,
                tags: ["veneer", "pre-glued", "hot melt", "iron-on", "birch"],
                aliases: ["iron-on edge banding", "pre-glued edge banding", "hot melt edging", "edge tape", "13/16\" edge banding", "22 mm edging"],
                types: [("Edge Banding - 13/16\" Pre-Glued", DK.mm(0.5), DK.inch(13.0 / 16), 0.30, "EB-1316"),
                        ("Edge Banding - 15/16\" Pre-Glued", DK.mm(0.5), DK.inch(15.0 / 16), 0.34, "EB-1516"),
                        ("Edge Banding - 2\" Pre-Glued", DK.mm(0.5), DK.inch(2), 0.55, "EB-2")])
    }

    static func pvcBanding() -> ComponentDefinition {
        banding("PVC Edge Banding", "Edge Banding", "PVC edge banding for melamine and laminate panels, applied with hot-melt glue on an edge bander.", finish: .pvcWhite,
                tags: ["pvc", "plastic", "melamine", "laminate"],
                aliases: ["pvc edging", "plastic edge banding", "melamine edging", "0.5 mm edge band", "1 mm edge band", "2 mm edge band"],
                types: [("PVC Edge Banding - 0.5 mm x 22 mm", DK.mm(0.5), DK.mm(22), 0.12, "PVC-05-22"),
                        ("PVC Edge Banding - 1 mm x 22 mm", DK.mm(1), DK.mm(22), 0.25, "PVC-10-22"),
                        ("PVC Edge Banding - 2 mm x 22 mm", DK.mm(2), DK.mm(22), 0.40, "PVC-20-22"),
                        ("PVC Edge Banding - 2 mm x 42 mm", DK.mm(2), DK.mm(42), 0.65, "PVC-20-42")])
    }

    static func absBanding() -> ComponentDefinition {
        banding("ABS Edge Banding", "Edge Banding", "ABS edge banding: chlorine-free, tougher than PVC, for high-wear edges.", finish: .absGrey,
                tags: ["abs", "plastic", "melamine", "chlorine free"],
                aliases: ["abs edging", "abs edge band", "thermoplastic edge banding", "3 mm edge band"],
                types: [("ABS Edge Banding - 1 mm x 22 mm", DK.mm(1), DK.mm(22), 0.30, "ABS-10-22"),
                        ("ABS Edge Banding - 2 mm x 22 mm", DK.mm(2), DK.mm(22), 0.48, "ABS-20-22"),
                        ("ABS Edge Banding - 3 mm x 42 mm", DK.mm(3), DK.mm(42), 0.90, "ABS-30-42")])
    }

    static func veneerEdge() -> ComponentDefinition {
        banding("Wood Veneer Edge", "Edge Banding", "Real wood veneer edge banding (fleece-backed), to match veneered plywood.", finish: .veneerOak,
                tags: ["veneer", "wood", "real wood", "plywood", "oak"],
                aliases: ["wood veneer edges", "veneer edging", "wood edge banding", "real wood edge band", "fleece back veneer"],
                types: [("Wood Veneer Edge - 0.6 mm x 24 mm", DK.mm(0.6), DK.mm(24), 0.45, "WVE-06-24"),
                        ("Wood Veneer Edge - 1 mm x 24 mm", DK.mm(1), DK.mm(24), 0.60, "WVE-10-24"),
                        ("Wood Veneer Edge - 0.6 mm x 50 mm", DK.mm(0.6), DK.mm(50), 0.80, "WVE-06-50")])
    }

    static func solidLipping() -> ComponentDefinition {
        banding("Solid Wood Lipping", "Edge Banding", "Solid wood lipping glued to a panel's edge and planed flush: a hard-wearing, shapeable edge.", finish: .oak,
                tags: ["lipping", "solid wood", "hardwood", "nosing"],
                aliases: ["solid wood edging", "hardwood lipping", "edge lipping", "wood nosing", "1/4\" lipping"],
                types: [("Solid Wood Lipping - 1/4\" x 7/8\"", DK.inch(0.25), DK.inch(0.875), 0.90, "SWL-14-78"),
                        ("Solid Wood Lipping - 3/8\" x 7/8\"", DK.inch(0.375), DK.inch(0.875), 1.10, "SWL-38-78"),
                        ("Solid Wood Lipping - 1/2\" x 1 1/8\"", DK.inch(0.5), DK.inch(1.125), 1.45, "SWL-12-118")])
    }

    // MARK: Cut edge profiles

    /// The corner curve of a cut profile in corner coordinates (a: in from the edge face… see `cutSection`), from the
    /// point on the edge face (a = s, b = 0) to the point on the top face (a = 0, b = s).
    static func cornerCurve(_ shape: EdgeProfileShape) -> [(String, String)] {
        func n(_ v: Double) -> String { LX.num(v) }
        switch shape {
        case .chamfer: return [("Size", DK.z), (DK.z, "Size")]
        case .bevel: return [("Depth", DK.z), (DK.z, "Size")]
        case .roundOver:
            return (0...10).map { k in let t = -Double.pi / 2 - Double.pi / 2 * Double(k) / 10; return ("Size + Size * \(n(cos(t)))", "Size + Size * \(n(sin(t)))") }
        case .cove:
            return (0...10).map { k in let t = Double.pi / 2 * Double(k) / 10; return ("Size * \(n(cos(t)))", "Size * \(n(sin(t)))") }
        case .ogee:
            return (0...16).map { k in let t = Double(k) / 16; return ("Size * \(n(1 - t))", "Size * \(n(0.5 - 0.5 * cos(.pi * t)))") }
        case .fingerPull:
            return (0...12).map { k in let t = Double.pi / 2 * Double(k) / 12; return ("Size * \(n(0.6 * cos(t)))", "Size * \(n(sin(t)))") }
        case .bullnose, .groove:
            return [("Size", DK.z), (DK.z, "Size")]
        }
    }

    /// The (Y, Z) section of a profiled edge sample: the panel (Panel Thickness across Y, Sample Depth into Z < 0) with the
    /// profile cut at its top corner (Y = Panel Thickness / 2, Z = 0), at the back corner for finger pulls, or a half
    /// round across the whole thickness for bullnoses. Corner coordinates: a down from the top face, b in from the edge face.
    static func cutSection(_ shape: EdgeProfileShape) -> [FamilyPoint] {
        let t = "Panel Thickness / 2", d = "-Sample Depth"
        let base: [(String, String)] = [("-\(t)", d), (t, d)]
        switch shape {
        case .bullnose:
            // A half round across the whole thickness, centred on the edge face.
            let arc = (0...16).map { k -> (String, String) in
                let a = Double.pi * Double(k) / 16
                return ("\(t) * \(LX.num(cos(a)))", "-\(t) + \(t) * \(LX.num(sin(a)))")
            }
            return DK.pts(base + arc)
        case .fingerPull:
            // At the back corner (Y = -t): a up from the back face, b in from the edge face.
            return DK.pts(base + [(t, DK.z)] + cornerCurve(shape).map { ("-\(t) + \($0.0)", "-(\($0.1))") })
        default:
            // Up the top face to the curve, along it to the edge face, across the edge face.
            return DK.pts(base + cornerCurve(shape).reversed().map { ("\(t) - (\($0.0))", "-(\($0.1))") } + [("-\(t)", DK.z)])
        }
    }

    /// A cut-profile definition: Edge Profile types (Profile, Size, Depth) plus a profiled sample for previews.
    fileprivate static func cutProfile(_ name: String, _ description: String, tags: [String], aliases: [String],
                                       types: [(String, EdgeProfileShape, Double, Double, Double, String)], panel: Double = DK.inch(0.75)) -> ComponentDefinition {
        var b = ComponentBuilder(name, .edges, "Edge Profiles", description)
        b.definition.tags = tags + ["edge profile", "router", "profile", "edge"]
        b.definition.aliases = aliases
        b.role(.edgeProfile)
        b.material("Sample Material", .maple)
        let shapes = types.map(\.1).reduce(into: [EdgeProfileShape]()) { if !$0.contains($1) { $0.append($1) } }
        b.text("Profile Shape", shapes[0].rawValue, group: .manufacturing)
        b.length("Size", types[0].2, group: .manufacturing); b.length("Depth", types[0].3, group: .manufacturing)
        // The sample's thickness: the part it's cut on (a full bullnose spans its whole thickness, so it follows Size).
        if shapes == [.bullnose] { b.length("Panel Thickness", panel, group: .placement, formula: "Size") }
        else { b.length("Panel Thickness", panel, instance: true, group: .placement) }
        b.length("Sample Depth", DK.inch(1.5)); b.runLength(DK.inch(4))
        b.hostRun(edgeHosts + [.rail, .leg], faces: edgeFaces)
        // One profiled sample per shape; a family with several shapes shows the type's own (Yes/No per shape).
        for shape in shapes {
            if shapes.count > 1 { b.flag("\(shape.rawValue) Shape", shape == shapes[0], instance: false, group: .manufacturing); b.visibility = "\(shape.rawValue) Shape" }
            b.run("Profiled Edge (\(shape.rawValue))", cutSection(shape))
            b.symbol(.side, [.coarse, .medium, .fine], .polyline(cutSection(shape), closed: true))
        }
        b.visibility = nil
        b.profile(DK.pts(cornerCurve(shapes[0])))
        b.symbol(.face, [.medium, .fine], .line((DK.lo, DK.z), (DK.hi, DK.z)))
        b.requires(.hostThickness(min: shapes == [.bullnose] ? "Size" : "Size + 0.002 m", max: nil))
        for (k, t) in types.enumerated() {
            var flags: [String: Bool] = [:]
            if shapes.count > 1 { for s in shapes { flags["\(s.rawValue) Shape"] = s == t.1 } }
            b.type(t.0, ["Size": t.2, "Depth": t.3], flags: flags, texts: ["Profile Shape": t.1.rawValue], cost: t.4, model: t.5,
                   description: "\(t.0) (router bit profile); cost per linear foot", isDefault: k == 0)
        }
        return b.build()
    }

    static func roundedEdge() -> ComponentDefinition {
        cutProfile("Rounded Edge Profile", "Round-over edge cut with a round-over bit along a part's edge.",
                   tags: ["round over", "rounded", "radius", "eased"], aliases: ["rounded edge profiles", "round-over edge", "radius edge", "roundover"],
                   types: [("Round-Over - 3/8\"", .roundOver, DK.inch(0.375), 0, 0.35, "REP-38"), ("Round-Over - 1/2\"", .roundOver, DK.inch(0.5), 0, 0.40, "REP-12"),
                           ("Round-Over - 3/16\"", .roundOver, DK.inch(0.1875), 0, 0.30, "REP-316")])
    }

    static func chamferedEdge() -> ComponentDefinition {
        cutProfile("Chamfered Edge Profile", "45° chamfer cut along a part's edge.",
                   tags: ["chamfer", "45", "arris", "eased"], aliases: ["chamfered edge profiles", "chamfer edge", "45 degree edge", "arris"],
                   types: [("Chamfer - 1/4\"", .chamfer, DK.inch(0.25), 0, 0.30, "CEP-14"), ("Chamfer - 3/8\"", .chamfer, DK.inch(0.375), 0, 0.35, "CEP-38"),
                           ("Chamfer - 1/16\" Eased", .chamfer, DK.inch(0.0625), 0, 0.20, "CEP-116")])
    }

    static func bullnoseEdge() -> ComponentDefinition {
        cutProfile("Bullnose Edge Profile", "Full half-round edge across the part's thickness.",
                   tags: ["bullnose", "half round", "round edge"], aliases: ["bullnose profiles", "full bullnose", "half round edge", "bull nose"],
                   types: [("Bullnose - 5/8\"", .bullnose, DK.inch(0.625), 0, 0.45, "BEP-58"), ("Bullnose - 1\"", .bullnose, DK.inch(1), 0, 0.55, "BEP-1"),
                           ("Bullnose - 1 1/2\"", .bullnose, DK.inch(1.5), 0, 0.70, "BEP-112")], panel: DK.inch(0.625))
    }

    static func beveledEdge() -> ComponentDefinition {
        cutProfile("Beveled Edge Profile", "Shallow bevel: a long slope on the face down to a narrow edge (tabletops, panels).",
                   tags: ["bevel", "beveled", "slope", "raised panel"], aliases: ["beveled edge profiles", "bevelled edge", "bevel edge", "sloped edge"],
                   types: [("Bevel - 1/2\" x 1/4\"", .bevel, DK.inch(0.5), DK.inch(0.25), 0.40, "BVP-12-14"), ("Bevel - 1\" x 1/4\"", .bevel, DK.inch(1), DK.inch(0.25), 0.50, "BVP-1-14"),
                           ("Bevel - 3/4\" x 1/2\"", .bevel, DK.inch(0.75), DK.inch(0.5), 0.50, "BVP-34-12")], panel: DK.inch(1))
    }

    static func fingerPullGroove() -> ComponentDefinition {
        cutProfile("Finger-Pull Groove", "Cove routed into the back of a front's edge as an integrated pull (handleless fronts).",
                   tags: ["finger pull", "handleless", "groove", "integrated pull", "cove"],
                   aliases: ["finger-pull grooves", "finger groove", "routed pull", "integrated handle", "handleless groove", "finger grip"],
                   types: [("Finger Pull - 1\"", .fingerPull, DK.inch(1), 0, 0.60, "FPG-1"), ("Finger Pull - 1 1/4\"", .fingerPull, DK.inch(1.25), 0, 0.70, "FPG-114")])
    }

    static func countertopEdge() -> ComponentDefinition {
        cutProfile("Countertop Edge Profile", "Countertop edge shapes: eased, half bullnose, ogee and bevel on 1 1/4\" tops.",
                   tags: ["countertop", "worktop", "edge", "ogee", "eased", "half bullnose"],
                   aliases: ["countertop edge profiles", "worktop edge", "counter edge", "half bullnose", "ogee edge", "eased edge"],
                   types: [("Countertop - Eased 1/8\"", .roundOver, DK.inch(0.125), 0, 0.50, "CTE-E18"), ("Countertop - Half Bullnose 3/4\"", .roundOver, DK.inch(0.75), 0, 1.20, "CTE-HB34"),
                           ("Countertop - Ogee 3/4\"", .ogee, DK.inch(0.75), 0, 1.60, "CTE-OG34"), ("Countertop - Bevel 3/8\"", .bevel, DK.inch(0.375), DK.inch(0.375), 1.00, "CTE-BV38")],
                   panel: DK.inch(1.25))
    }

    // MARK: Profile components

    static func aluminumEdge() -> ComponentDefinition {
        var b = ComponentBuilder("Aluminum Edge Profile", .edges, "Edge Profiles", "Aluminium U-cap pushed or glued over a panel's edge: a metal edge on shelves, tops and doors.")
        b.tags("aluminum", "edge", "cap", "u-cap", "metal edge", "profile")
        b.aliases("aluminum edge profiles", "aluminium edge cap", "metal edge trim", "edge cap profile", "u cap")
        b.material("Profile Material", .anodized)
        b.runLength(DK.mm(1000))
        b.length("Panel Thickness", DK.mm(18)); b.length("Wall", DK.mm(1.2)); b.length("Leg", DK.mm(8))
        b.hostRun(edgeHosts, faces: edgeFaces)
        let pt = "Panel Thickness / 2"
        b.run("Cap", DK.pts([("-\(pt) - Wall", "-Leg"), ("-\(pt)", "-Leg"), ("-\(pt)", DK.z), (pt, DK.z), (pt, "-Leg"), ("\(pt) + Wall", "-Leg"),
                             ("\(pt) + Wall", "Wall - 0.0004 m"), ("\(pt) + Wall - 0.0004 m", "Wall"), ("-\(pt) - Wall + 0.0004 m", "Wall"), ("-\(pt) - Wall", "Wall - 0.0004 m")]))
        b.runOutlines(y: ("-\(pt) - Wall", "\(pt) + Wall"), z: ("-Leg", "Wall"))
        b.requires(.hostThickness(min: "Panel Thickness - 0.0005 m", max: "Panel Thickness + 0.0005 m"))
        b.type("Aluminum Edge Cap - 18 mm Panel", cost: 6.50, model: "AEC-18")
        b.type("Aluminum Edge Cap - 3/4\" Panel", ["Panel Thickness": DK.inch(0.75)], cost: 6.50, model: "AEC-34")
        b.type("Aluminum Edge Cap - 25 mm Panel", ["Panel Thickness": DK.mm(25), "Leg": DK.mm(10)], cost: 8.00, model: "AEC-25")
        return b.build()
    }

    static func tMolding() -> ComponentDefinition {
        var b = ComponentBuilder("T-Molding", .edges, "Edge Profiles", "Flexible T-molding: a crowned cap with a barbed tongue tapped into a slot cut in the edge.")
        b.tags("t-molding", "t-mold", "edge", "barbed", "slot", "plastic")
        b.aliases("t molding", "t-moulding", "tee molding", "barbed edge trim", "arcade edging", "3/4\" t-molding")
        b.material("Molding Material", .blackPlastic)
        b.runLength(DK.mm(1000))
        b.length("Cap Width", DK.inch(0.75)); b.length("Cap Thickness", DK.mm(1.5)); b.length("Barb Width", DK.mm(1.6)); b.length("Barb Depth", DK.inch(0.4))
        b.hostRun(edgeHosts, faces: edgeFaces)
        let crown = (0...12).map { k -> FamilyPoint in
            let a = Double.pi * Double(k) / 12
            return DK.p("Cap Width / 2 * \(LX.num(cos(a)))", "Cap Thickness * 0.4 + Cap Thickness * 0.6 * \(LX.num(sin(a)))")
        }
        b.run("Cap", [DK.p("-Cap Width / 2", DK.z), DK.p("Cap Width / 2", DK.z)] + crown)
        var barb: [(String, String)] = [("-Barb Width / 2", DK.z)]
        for k in 0..<4 {
            let z0 = "-Barb Depth * \(LX.num(0.2 + 0.2 * Double(k)))", z1 = "-Barb Depth * \(LX.num(0.32 + 0.2 * Double(k)))"
            barb += [("-Barb Width / 2", z0), ("-Barb Width / 2 - 0.0007 m", z1), ("-Barb Width / 2", z1)]
        }
        barb += [("-Barb Width / 2", "-Barb Depth"), ("Barb Width / 2", "-Barb Depth")]
        for k in (0..<4).reversed() {
            let z0 = "-Barb Depth * \(LX.num(0.2 + 0.2 * Double(k)))", z1 = "-Barb Depth * \(LX.num(0.32 + 0.2 * Double(k)))"
            barb += [("Barb Width / 2", z1), ("Barb Width / 2 + 0.0007 m", z1), ("Barb Width / 2", z0)]
        }
        barb += [("Barb Width / 2", CX.mm(0.2)), ("-Barb Width / 2", CX.mm(0.2))]
        b.run("Barbed Tongue", DK.pts(barb))
        b.groove("T-molding slot", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Barb Width", depth: "Barb Depth + 0.001 m")
        b.runOutlines(y: ("-Cap Width / 2", "Cap Width / 2"), z: ("-Barb Depth", "Cap Thickness"))
        b.requires(.hostThickness(min: "Cap Width - 0.001 m", max: "Cap Width + 0.001 m"))
        b.type("T-Molding - 5/8\"", ["Cap Width": DK.inch(0.625)], cost: 0.60, model: "TM-58")
        b.type("T-Molding - 3/4\"", cost: 0.65, model: "TM-34", isDefault: true)
        b.type("T-Molding - 1\"", ["Cap Width": DK.inch(1)], cost: 0.80, model: "TM-1")
        return b.build()
    }

    /// A channel section: walls at ±(Inner Width / 2) up to their heights, base under them.
    fileprivate static func channel(_ inner: String, height: String, wall: String) -> [FamilyPoint] {
        let w = "(\(inner)) / 2"
        return DK.pts([("-\(w) - \(wall)", DK.z), ("\(w) + \(wall)", DK.z), ("\(w) + \(wall)", height), (w, height), (w, wall), ("-\(w)", wall), ("-\(w)", height),
                       ("-\(w) - \(wall)", height)])
    }

    static func uChannel() -> ComponentDefinition {
        var b = ComponentBuilder("U-Channel Profile", .edges, "Channels & Angles", "Aluminium U-channel: edge cap, panel track or glass channel, screwed or glued along a part.")
        b.tags("u-channel", "channel", "aluminum", "track", "edge", "profile")
        b.aliases("u-channel profiles", "u channel", "u profile", "channel trim", "panel channel")
        b.material("Profile Material", .anodized)
        b.runLength(DK.mm(1000))
        b.length("Inner Width", DK.mm(10)); b.length("Channel Height", DK.mm(10)); b.length("Wall", DK.mm(1.5))
        b.hostRun(edgeHosts + [.rail], faces: edgeFaces + [.inside, .top, .bottom])
        b.run("Channel", channel("Inner Width", height: "Channel Height", wall: "Wall"))
        b.runScrews("Channel screw", diameter: 3, depth: 12)
        b.runOutlines(y: ("-Inner Width / 2 - Wall", "Inner Width / 2 + Wall"), z: (DK.z, "Channel Height"))
        b.type("U-Channel - 10 x 10 mm", cost: 4.50, model: "UC-1010")
        b.type("U-Channel - 1/2\" x 1/2\"", ["Inner Width": DK.inch(0.5), "Channel Height": DK.inch(0.5)], cost: 4.80, model: "UC-1212")
        b.type("U-Channel - 3/4\" Panel", ["Inner Width": DK.inch(0.76), "Channel Height": DK.inch(0.5)], cost: 5.50, model: "UC-34")
        return b.build()
    }

    static func lChannel() -> ComponentDefinition {
        var b = ComponentBuilder("L-Channel Profile", .edges, "Channels & Angles", "Aluminium angle along an outside corner: one leg on the edge, one on the face.")
        b.tags("l-channel", "angle", "aluminum", "corner", "edge", "profile")
        b.aliases("l-channel profiles", "aluminum angle", "angle trim", "l profile", "corner angle")
        b.material("Profile Material", .anodized)
        b.runLength(DK.mm(1000))
        b.length("Leg A", DK.mm(20)); b.length("Leg B", DK.mm(20)); b.length("Wall", DK.mm(1.5))
        // The corner at the origin: Leg A down the edge face (−Y), Leg B back along the face (−Z).
        b.host(edgeHosts, faces: edgeFaces, align: .full, alignments: [.full], offsetY: 0)
        b.run("Angle", DK.pts([("-Leg A", DK.z), (DK.z, DK.z), (DK.z, "-Leg B"), ("Wall", "-Leg B"), ("Wall", "Wall"), ("-Leg A", "Wall")]))
        b.runOutlines(y: ("-Leg A", "Wall"), z: ("-Leg B", "Wall"))
        b.type("L-Channel - 20 x 20 mm", cost: 3.80, model: "LC-2020")
        b.type("L-Channel - 30 x 30 mm", ["Leg A": DK.mm(30), "Leg B": DK.mm(30), "Wall": DK.mm(2)], cost: 5.20, model: "LC-3030")
        b.type("L-Channel - 3/4\" x 3/4\"", ["Leg A": DK.inch(0.75), "Leg B": DK.inch(0.75), "Wall": DK.inch(1.0 / 16)], cost: 3.90, model: "LC-3434")
        return b.build()
    }

    static func jChannel() -> ComponentDefinition {
        var b = ComponentBuilder("J-Channel Profile", .edges, "Channels & Angles", "J-trim finishing a panel's exposed edge: a short back leg, the edge and a long face leg.")
        b.tags("j-channel", "j-trim", "edge", "trim", "profile")
        b.aliases("j-channel profiles", "j channel", "j trim", "j mould", "panel edge trim")
        b.material("Profile Material", .whitePlastic)
        b.runLength(DK.mm(1000))
        b.length("Panel Thickness", DK.inch(0.5)); b.length("Face Leg", DK.inch(0.75)); b.length("Back Leg", DK.inch(0.375)); b.length("Wall", DK.mm(1.2))
        b.hostRun(edgeHosts, faces: edgeFaces)
        let p = "Panel Thickness / 2"
        b.run("J Trim", DK.pts([("-\(p) - Wall", "-Back Leg"), ("-\(p)", "-Back Leg"), ("-\(p)", DK.z), (p, DK.z), (p, "-Face Leg"), ("\(p) + Wall", "-Face Leg"),
                                ("\(p) + Wall", "Wall"), ("-\(p) - Wall", "Wall")]))
        b.runOutlines(y: ("-Panel Thickness / 2 - Wall", "Panel Thickness / 2 + Wall"), z: ("-Face Leg", "Wall"))
        b.requires(.hostThickness(min: "Panel Thickness - 0.001 m", max: "Panel Thickness + 0.001 m"))
        b.type("J-Channel - 1/2\" Panel", cost: 1.20, model: "JC-12")
        b.type("J-Channel - 3/4\" Panel", ["Panel Thickness": DK.inch(0.75), "Face Leg": DK.inch(1)], cost: 1.40, model: "JC-34")
        return b.build()
    }

    static func decorativeTrim() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Trim", .edges, "Trims", "Small solid trim applied to a face or edge: half-round, bead or quarter-round.")
        b.tags("trim", "half round", "bead", "quarter round", "molding", "applied")
        b.aliases("decorative trims", "half round trim", "bead molding", "quarter round", "scotia", "astragal trim")
        b.material("Trim Material", .oak)
        b.runLength(DK.mm(1000))
        b.length("Trim Width", DK.inch(0.5)); b.length("Projection", DK.inch(0.25))
        b.flag("Quarter Round", false, instance: false, group: .dimensions)
        b.flag("Bead", false, instance: false, group: .dimensions)
        b.flag("Half Round", true, formula: "and(not(Quarter Round), not(Bead))")
        b.hostRun(edgeHosts + [.rail, .plinth], faces: edgeFaces + [.front, .inside])
        func round(_ center: String, _ rx: String, _ a0: Double, _ a1: Double, _ steps: Int = 12) -> [FamilyPoint] {
            (0...steps).map { k in
                let a = (a0 + (a1 - a0) * Double(k) / Double(steps)) * .pi / 180
                return DK.p("\(center) + (\(rx)) * \(LX.num(cos(a)))", "Projection * \(LX.num(sin(a)))")
            }
        }
        b.visibility = "Half Round"
        b.run("Half Round", [DK.p("-Trim Width / 2", DK.z), DK.p("Trim Width / 2", DK.z)] + round(DK.z, "Trim Width / 2", 0, 180).dropFirst().dropLast())
        b.visibility = "Quarter Round"
        b.run("Quarter Round", [DK.p("-Trim Width / 2", DK.z)] + round("-Trim Width / 2", "Trim Width", 0, 90))
        b.visibility = "Bead"
        b.run("Bead", [DK.p("-Trim Width / 2", DK.z), DK.p("Trim Width / 2", DK.z), DK.p("Trim Width / 2", "Projection * 0.25")]
              + round(DK.z, "Trim Width * 0.38", 10, 170) + [DK.p("-Trim Width / 2", "Projection * 0.25")])
        b.visibility = nil
        b.runOutlines(y: ("-Trim Width / 2", "Trim Width / 2"), z: (DK.z, "Projection"))
        b.type("Half-Round - 1/2\"", cost: 0.70, model: "DT-HR12")
        b.type("Quarter-Round - 1/2\"", ["Projection": DK.inch(0.5)], flags: ["Quarter Round": true], cost: 0.70, model: "DT-QR12")
        b.type("Bead - 3/8\"", ["Trim Width": DK.inch(0.375), "Projection": DK.inch(0.1875)], flags: ["Bead": true], cost: 0.80, model: "DT-BD38")
        return b.build()
    }

    static func cornerProtector() -> ComponentDefinition {
        var b = ComponentBuilder("Corner Protector", .edges, "Trims", "Clear self-adhesive corner protector along an outside corner: a soft rounded nose against knocks.")
        b.tags("corner", "protector", "guard", "clear", "safety", "child", "edge")
        b.aliases("corner protectors", "edge protector", "corner guard strip", "clear corner guard", "baby proof edge")
        b.material("Protector Material", .clearPVC)
        b.runLength(DK.mm(1000))
        b.length("Leg", DK.inch(0.75)); b.length("Wall", DK.mm(1.5)); b.length("Nose Radius", DK.mm(5))
        b.host(edgeHosts, faces: edgeFaces, align: .full, alignments: [.full], offsetY: 0)
        let nose = DK.arc("Wall - Nose Radius", "Wall - Nose Radius", "Nose Radius", 0, 90, steps: 8)
        b.run("Protector", DK.pts([("-Leg", DK.z), ("Wall - Nose Radius", DK.z)]) + DK.arc("Wall - Nose Radius", "Wall - Nose Radius", "Nose Radius - Wall", 90, 0, steps: 8).dropFirst()
              + DK.pts([(DK.z, "-Leg"), ("Wall", "-Leg")]) + nose + DK.pts([("-Leg", "Wall")]))
        b.runOutlines(y: ("-Leg", "Wall"), z: ("-Leg", "Wall"))
        b.type("Corner Protector - Clear 3/4\"", cost: 0.90, model: "CP-34")
        b.type("Corner Protector - Clear 1\"", ["Leg": DK.inch(1), "Nose Radius": DK.mm(7)], cost: 1.10, model: "CP-1")
        return b.build()
    }

    static func handlelessChannel() -> ComponentDefinition {
        var b = ComponentBuilder("Handleless Channel Profile", .edges, "Handleless Profiles", "Aluminium channel across the bay between fronts: fronts sit proud of it and are pulled from its recess.")
        b.tags("handleless", "channel", "recessed pull", "aluminum", "rail", "true handleless")
        b.aliases("handleless cabinet profiles", "handleless rail", "recessed handle rail", "c profile", "l profile", "channel pull")
        b.material("Profile Material", .anodized)
        b.runLength(DK.inch(30))
        b.length("Channel Height", DK.mm(57)); b.length("Channel Depth", DK.mm(28)); b.length("Wall", DK.mm(1.8))
        b.flag("L Profile", false, instance: false, group: .dimensions)
        b.flag("C Profile", true, formula: "not(L Profile)")
        // In the bay's front: the recess opens toward the viewer (+Z), its back at -Channel Depth.
        b.host([.bay], faces: [.front], align: .full, alignments: [.full, .top], offsetY: 0)
        let h = "Channel Height", d = "-Channel Depth", t = "Wall"
        b.visibility = "C Profile"
        b.run("C Channel", DK.pts([("-\(h) / 2", d), ("\(h) / 2", d), ("\(h) / 2", DK.z), ("\(h) / 2 - 0.012 m", DK.z), ("\(h) / 2 - 0.012 m", "-\(t)"),
                                   ("\(h) / 2 - \(t)", "-\(t)"), ("\(h) / 2 - \(t)", "\(d) + \(t)"), ("-\(h) / 2 + \(t)", "\(d) + \(t)"), ("-\(h) / 2 + \(t)", "-\(t)"),
                                   ("-\(h) / 2 + 0.012 m", "-\(t)"), ("-\(h) / 2 + 0.012 m", DK.z), ("-\(h) / 2", DK.z)]))
        b.visibility = "L Profile"
        b.run("L Channel", DK.pts([("-\(h) / 2", d), ("\(h) / 2", d), ("\(h) / 2", DK.z), ("\(h) / 2 - \(t)", DK.z), ("\(h) / 2 - \(t)", "\(d) + \(t)"),
                                   ("-\(h) / 2", "\(d) + \(t)")]))
        b.visibility = nil
        b.pocket("Side notch", x: "-Length / 2", y: CX.zero, width: CX.mm(2), height: "Channel Height", depth: "Channel Depth", target: .counterpart)
        b.pocket("Side notch", x: "Length / 2", y: CX.zero, width: CX.mm(2), height: "Channel Height", depth: "Channel Depth", target: .counterpart)
        b.runOutlines(y: ("-Channel Height / 2", "Channel Height / 2"), z: ("-Channel Depth", DK.z))
        b.requires(.note("Notch both sides' front edges Channel Height x Channel Depth; fronts overlap the channel by 1/2\"."))
        b.type("Handleless Channel - C, Between Drawers", cost: 9.00, model: "HCP-C")
        b.type("Handleless Channel - L, Under Top", ["Channel Height": DK.mm(37)], flags: ["L Profile": true], cost: 7.50, model: "HCP-L")
        return b.build()
    }

    static func plinthProfile() -> ComponentDefinition {
        var b = ComponentBuilder("Plinth Profile", .edges, "Plinths & Kicks", "Aluminium plinth (kickboard) profile clipped to adjustable legs, with a floor seal.")
        b.tags("plinth", "kickboard", "toe kick", "aluminum", "base", "seal")
        b.aliases("plinth profiles", "plinth board", "kick plate", "aluminium plinth", "cabinet plinth")
        b.material("Profile Material", .anodized)
        b.material("Seal Material", .greyRubber)
        b.runLength(DK.inch(36))
        b.length("Plinth Height", DK.inch(4)); b.length("Wall", DK.mm(1.5)); b.length("Return", DK.mm(12))
        // On the front face of the plinth zone: Y up from the floor, the board's face at Z = 0.
        b.host([.plinth, .bottom, .floor], faces: [.front], align: .full, alignments: [.full], offsetY: 0)
        b.run("Board", DK.pts([(CX.mm(6), "-Return"), (CX.mm(6), DK.z), ("Plinth Height", DK.z), ("Plinth Height", "-Return"), ("Plinth Height - Wall", "-Return"),
                               ("Plinth Height - Wall", "-Wall"), ("0.006 m + Wall", "-Wall"), ("0.006 m + Wall", "-Return")]))
        b.using("Seal Material")
        b.run("Floor Seal", DK.pts([(DK.z, "-Wall - 0.003 m"), (CX.mm(6), "-Wall - 0.003 m"), (CX.mm(6), DK.z), (CX.mm(1), CX.mm(1))]))
        b.using(nil)
        b.runOutlines(y: (DK.z, "Plinth Height"), z: ("-Return", DK.z))
        b.type("Plinth Profile - 4\"", cost: 12.00, model: "PP-4")
        b.type("Plinth Profile - 6\"", ["Plinth Height": DK.inch(6)], cost: 15.00, model: "PP-6")
        b.type("Plinth Profile - 100 mm", ["Plinth Height": DK.mm(100)], cost: 12.00, model: "PP-100")
        return b.build()
    }

    static func toeKickProfile() -> ComponentDefinition {
        var b = ComponentBuilder("Toe Kick Profile", .edges, "Plinths & Kicks", "Vinyl cove base glued along a toe kick: a flexible finish with a cove toe at the floor.")
        b.tags("toe kick", "cove base", "vinyl", "base", "skirting", "plinth")
        b.aliases("toe kick profiles", "vinyl cove base", "rubber base", "cove base", "kick base", "4\" cove base")
        b.material("Base Material", .vinyl)
        b.runLength(DK.inch(36))
        b.length("Base Height", DK.inch(4)); b.length("Thickness", DK.inch(0.125)); b.length("Toe", DK.inch(0.375))
        b.host([.plinth, .bottom, .floor], faces: [.front], align: .full, alignments: [.full], offsetY: 0)
        b.run("Cove Base", [DK.p(DK.z, DK.z), DK.p(DK.z, "Toe"), DK.p("Thickness", "Toe")] + DK.arc("Toe", "Toe", "Toe - Thickness", 180, 270, steps: 8).dropFirst()
              + [DK.p("Base Height", "Thickness"), DK.p("Base Height", DK.z)])
        b.runOutlines(y: (DK.z, "Base Height"), z: (DK.z, "Toe"))
        b.type("Toe Kick Profile - 4\" Vinyl Cove", cost: 0.90, model: "TKP-4")
        b.type("Toe Kick Profile - 2 1/2\" Vinyl Cove", ["Base Height": DK.inch(2.5)], cost: 0.70, model: "TKP-25")
        return b.build()
    }

    static func panelJoint() -> ComponentDefinition {
        var b = ComponentBuilder("Panel Joint Profile", .edges, "Channels & Angles", "H-profile joining two panels edge to edge (backs, wall panels, long tops).")
        b.tags("panel joint", "h-profile", "connector", "joining strip", "aluminum", "edge")
        b.aliases("panel joint profiles", "h profile", "h channel", "joining profile", "panel connector strip")
        b.material("Profile Material", .anodized)
        b.runLength(DK.mm(1000))
        b.length("Panel Thickness", DK.inch(0.75)); b.length("Grip", DK.mm(10)); b.length("Wall", DK.mm(1.2))
        b.hostRun(edgeHosts, faces: edgeFaces)
        let p = "Panel Thickness / 2"
        b.run("H Profile", DK.pts([("-\(p) - Wall", "-Grip"), ("-\(p)", "-Grip"), ("-\(p)", DK.z), (p, DK.z), (p, "-Grip"), ("\(p) + Wall", "-Grip"),
                                   ("\(p) + Wall", "Grip + Wall"), (p, "Grip + Wall"), (p, "Wall"), ("-\(p)", "Wall"), ("-\(p)", "Grip + Wall"), ("-\(p) - Wall", "Grip + Wall")]))
        b.runOutlines(y: ("-\(p) - Wall", "\(p) + Wall"), z: ("-Grip", "Grip + Wall"))
        b.requires(.hostThickness(min: "Panel Thickness - 0.0005 m", max: "Panel Thickness + 0.0005 m"))
        b.type("Panel Joint - H, 3/4\" Panels", cost: 5.50, model: "PJH-34")
        b.type("Panel Joint - H, 18 mm Panels", ["Panel Thickness": DK.mm(18)], cost: 5.50, model: "PJH-18")
        b.type("Panel Joint - H, 1/4\" Backs", ["Panel Thickness": DK.inch(0.25), "Grip": DK.mm(8)], cost: 3.50, model: "PJH-14")
        return b.build()
    }
}
