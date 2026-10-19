import Foundation
import ArcusGeometry

// COMPC: 12 Bed & Bedroom Hardware. Rail and post hardware is face-based (X along the rail, Y up, Z out of the rail's
// inside face into the bed); lift mechanisms draw their arms in the rail's plane and open by an Open Angle instance
// parameter. Slat bases, centre rails, casters, feet, Murphy and folding beds use the plan frame (origin on the bed's
// centre line at the slat ledge, or at the floor, Z up; -Y is the foot end).

extension ComponentsC {
    static var beds: [ComponentDefinition] {
        [bedRailConnector(), bedRailBracket(), slatHolder(), slatSystem(), adjustableBedSupport(), centerSupportRail(), gasLiftBed(), hydraulicBedLift(),
         bedStorageHinge(), foldingBed(), murphyBed(), headboardBracket(), bedsideConnector(), underBedSlide(), bedCaster(), bedLevelingFoot(), mattressRetainer()]
    }

    /// Mattress sizes (inches): name, width, length.
    static let mattresses: [(String, Double, Double)] = [("Twin", 38, 75), ("Full", 53, 75), ("Queen", 60, 80), ("King", 76, 80)]

    // MARK: Frame connectors

    /// Hook-plate bed rail connector: a slotted plate on the post and a hook plate on the rail's end that drops into it.
    static func bedRailConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Rail Hook Connector", .beds, "Frame Connectors", "Hook-plate connector: a slotted plate on the post and a hook plate on the rail end that drops into it.")
        b.tags("bed", "rail", "connector", "hook plate", "knock-down", "post")
        b.aliases("bed frame connector", "bed rail fastener", "hook and slot bed bracket", "interlocking bed rail plate", "4 in", "5 in", "6 in")
        b.material("Finish Material", .steel)
        b.length("Plate Length", CC.inch(5))
        b.length("Plate Width", CC.mm(38))
        b.length("Plate Thickness", CC.mm(3))
        b.number("Hooks", 2, group: .dimensions)
        b.host([.leg, .rail, .sidePanel], faces: [.inside, .front, .any], align: .top, alignments: [.top, .center], offsetY: CC.inch(2))
        b.requires(.hostWidth(min: "Plate Width + 0.006 m", max: nil))
        b.box("Post Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Length / 2", "Plate Length / 2"), z: ("0 m", "Plate Thickness"))
        b.box("Rail Plate", x: ("-Plate Width / 2 + 0.003 m", "Plate Width / 2 - 0.003 m"), y: ("-Plate Length / 2 - 0.005 m", "Plate Length / 2 - 0.005 m"), z: ("Plate Thickness + 0.004 m", "2 * Plate Thickness + 0.004 m"))
        for k in 1...3 {
            let v: String? = k <= 2 ? nil : "Show Hook \(k)"
            if let v { b.countFlag(v, "Hooks >= \(k)") }
            let y = "-Plate Length / 2 + Plate Length * (\(k) - 0.5) / Hooks"
            b.shown(v) { $0.box("Hook \(k)", x: ("-0.006 m", "0.006 m"), y: ("\(y) - 0.008 m", "\(y) + 0.004 m"), z: ("Plate Thickness", "Plate Thickness + 0.004 m")) }
        }
        for y in ["-Plate Length / 2 + 0.012 m", "Plate Length / 2 - 0.012 m"] { b.drill("Plate screw", x: "0 m", y: y, diameter: CX.mm(4.5), depth: CX.mm(25)) }
        b.drill("Rail screw", x: "0 m", y: "0 m", diameter: CX.mm(4.5), depth: CX.mm(25), target: .counterpart)
        b.pocket("Hook clearance", width: "0.016 m", height: "Plate Length - 0.02 m", depth: "0.008 m")
        b.outlines(plan: .top, elevation: .face, x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Length / 2", "Plate Length / 2"), z: ("0 m", "2 * Plate Thickness + 0.004 m"))
        for (l, n, cost) in [(4.0, 2.0, 4.5), (5, 2, 5.5), (6, 3, 6.5)] {
            b.type("Bed Rail Hook Connector - \(Int(l))\"", ["Plate Length": CC.inch(l)], numbers: ["Hooks": n], cost: cost, model: "BRH-\(Int(l))", description: "Hook-plate bed rail connector set, \(Int(l))\"")
        }
        return b.build()
    }

    /// Corner bracket between a bed rail and a post or headboard: two drilled leaves at 90°.
    static func bedRailBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Rail Bracket", .beds, "Frame Connectors", "Heavy steel corner bracket joining a bed rail to a post or headboard, bolted through both.")
        b.tags("bed", "rail", "bracket", "corner", "angle", "steel")
        b.aliases("bed corner bracket", "bed frame bracket", "rail to post bracket", "bed angle bracket", "3 in", "4 in")
        b.material("Finish Material", .matteBlack)
        b.length("Leg Length", CC.inch(4))
        b.length("Bracket Height", CC.inch(3))
        b.length("Thickness", CC.mm(4))
        b.host([.rail, .sidePanel], faces: [.inside], align: .left, alignments: [.left, .right])
        b.requires(.hostHeight(min: "Bracket Height", max: nil))
        b.box("Rail Leaf", x: ("0 m", "Leg Length"), y: ("-Bracket Height / 2", "Bracket Height / 2"), z: ("0 m", "Thickness"))
        b.box("Post Leaf", x: ("0 m", "Thickness"), y: ("-Bracket Height / 2", "Bracket Height / 2"), z: ("0 m", "Leg Length"))
        b.link("Gusset", plane: .xz, ("Leg Length * 0.5", "Thickness"), ("Thickness", "Leg Length * 0.5"), at: "0 m", width: CX.mm(4), thickness: "Bracket Height * 0.6")
        for x in ["Leg Length * 0.35", "Leg Length * 0.8"] {
            b.drill("Bracket bolt", x: x, y: "0 m", diameter: CX.mm(7), depth: CX.mm(30))
            b.drill("Post bolt", x: x, y: "0 m", diameter: CX.mm(7), depth: CX.mm(30), target: .counterpart)
        }
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("Leg Length", "0 m"), ("0 m", "0 m"), ("0 m", "Leg Length")]), closed: false))
        b.symbol(.face, [.coarse], .rect(("0 m", "-Bracket Height / 2"), ("Leg Length", "Bracket Height / 2")))
        b.type("Bed Rail Bracket - 3\"", ["Leg Length": CC.inch(3), "Bracket Height": CC.inch(2.5)], cost: 3.5, model: "BRB-3")
        b.type("Bed Rail Bracket - 4\"", [:], cost: 4.5, model: "BRB-4", isDefault: true)
        return b.build()
    }

    /// Slat holder: a moulded cup screwed to the rail's inside face that holds one slat end.
    static func slatHolder() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Slat Holder", .beds, "Slats & Supports", "Moulded cup on the rail's inside face holding one slat end; rubber-damped.")
        b.tags("bed", "slat", "holder", "cup", "clip", "rail")
        b.aliases("slat cap", "slat bracket", "lath holder", "slat clip", "53 mm", "68 mm", "2 in", "2 3/4 in")
        b.material("Finish Material", .blackPlastic)
        b.length("Slat Width", CC.mm(53))
        b.length("Slat Thickness", CC.mm(8))
        b.length("Cup Depth", CC.mm(22))
        b.length("Wall", CC.mm(2.5), group: .manufacturing)
        b.host([.rail, .sidePanel], faces: [.inside], align: .top, alignments: [.top, .center], count: ComponentCountRule(steps: [], maximumCount: 14, inset: CC.inch(2)))
        b.box("Back Plate", x: ("-Slat Width / 2 - Wall - 0.006 m", "Slat Width / 2 + Wall + 0.006 m"), y: ("-0.03 m", "0.006 m"), z: ("0 m", "Wall"))
        b.box("Cup Floor", x: ("-Slat Width / 2 - Wall", "Slat Width / 2 + Wall"), y: ("-Slat Thickness - Wall", "-Slat Thickness"), z: ("Wall", "Cup Depth"))
        for s in ["-", ""] {
            b.box("Cup Side", x: ("\(s)(Slat Width / 2 + Wall / 2) - Wall / 2", "\(s)(Slat Width / 2 + Wall / 2) + Wall / 2"), y: ("-Slat Thickness - Wall", "0.004 m"), z: ("Wall", "Cup Depth"))
            b.drill("Holder screw", x: "\(s)(Slat Width / 2 + Wall + 0.003 m)", y: "-0.015 m", diameter: CX.mm(3.5), depth: CX.mm(16))
        }
        b.outlines(plan: .top, elevation: .face, x: ("-Slat Width / 2 - Wall - 0.006 m", "Slat Width / 2 + Wall + 0.006 m"), y: ("-0.03 m", "0.006 m"), z: ("0 m", "Cup Depth"))
        b.type("Bed Slat Holder - 53 mm", [:], cost: 0.35, model: "BSH-53")
        b.type("Bed Slat Holder - 68 mm", ["Slat Width": CC.mm(68)], cost: 0.4, model: "BSH-68")
        return b.build()
    }

    /// A complete slat base: two side stringers, a centre rail and arched slats at a pitch, sized per mattress.
    static func slatSystem() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Slat System", .beds, "Slats & Supports", "Sprung slat base: arched slats on side stringers and a centre rail, sized to the mattress.", frame: .plan)
        b.tags("bed", "slats", "slat base", "sprung", "foundation", "mattress")
        b.aliases("slatted bed base", "sprung slats", "bed slat kit", "slat roll", "twin", "full", "queen", "king", "double")
        b.role(.module)
        b.material("Slat Material", .beech)
        b.material("Rail Material", .blackPlastic)
        b.length("Base Width", CC.inch(60))
        b.length("Base Length", CC.inch(80))
        b.length("Slat Width", CC.mm(53))
        b.length("Slat Thickness", CC.mm(8))
        b.length("Arch", CC.mm(12))
        b.number("Slat Count", 28, group: .dimensions)
        b.flag("Center Rail", true, instance: false, group: .dimensions)
        b.number("Load Capacity", 600, unit: "lb", group: .data)
        b.host([.bay, .rail, .bottom], faces: [.top], align: .center)
        b.requires(.hostWidth(min: "Base Width", max: nil))
        b.requires(.note("Slat gap is (Base Length - Slat Count x Slat Width) / Slat Count; keep it under 3\" for foam mattresses."))
        b.using("Rail Material")
        for s in ["-", ""] { b.box("Stringer", x: ("\(s)(Base Width / 2) - 0.02 m", "\(s)(Base Width / 2) + 0.02 m"), y: ("-Base Length / 2", "Base Length / 2"), z: ("-0.02 m", "0 m")) }
        b.shown("Center Rail") { $0.box("Center Rail", x: ("-0.02 m", "0.02 m"), y: ("-Base Length / 2", "Base Length / 2"), z: ("-0.02 m", "0 m")) }
        b.using("Slat Material")
        for k in 1...36 {
            let v: String? = k <= 10 ? nil : "Show Slat \(k)"
            if let v { b.countFlag(v, "Slat Count >= \(k)") }
            let y = "-Base Length / 2 + Base Length * (\(k) - 0.5) / Slat Count"
            let path: [(String, String)] = [("-Base Width / 2", "0 m"), ("-Base Width / 4", "Arch * 0.75"), ("0 m", "Arch"), ("Base Width / 4", "Arch * 0.75"), ("Base Width / 2", "0 m")]
            b.shown(v) { $0.sweep("Slat \(k)", path: ComponentKit.points(path.map { ($0.0, "\($0.1) + Slat Thickness / 2") }),
                                  profile: ComponentKit.rect(width: "Slat Thickness", height: "Slat Width"), plane: .xz, at: y) }
        }
        b.using(nil)
        b.symbol(.face, [.coarse], .rect(("-Base Width / 2", "-Base Length / 2"), ("Base Width / 2", "Base Length / 2")),
                 .line(("-Base Width / 2", "-Base Length / 2"), ("Base Width / 2", "Base Length / 2")))
        b.symbol(.top, [.coarse], .rect(("-Base Width / 2", "-0.02 m"), ("Base Width / 2", "Arch + Slat Thickness")))
        for (n, w, l) in mattresses {
            let count = (l * 0.0254 / 0.075).rounded()
            b.type("Bed Slat System - \(n)", ["Base Width": CC.inch(w), "Base Length": CC.inch(l)], flags: ["Center Rail": w > 40], numbers: ["Slat Count": count],
                   cost: w > 40 ? 129 + (w - 53) * 2 : 89, model: "BSS-\(n.prefix(1))", description: "Slat base for a \(n) mattress, \(Int(w))\" x \(Int(l))\", \(Int(count)) slats", isDefault: n == "Queen")
        }
        return b.build()
    }

    /// Screw-adjustable support leg under a bed's centre rail.
    static func adjustableBedSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Adjustable Bed Support", .beds, "Slats & Supports", "Screw-adjustable support leg under a centre rail: saddle, threaded stem, tube and floor pad.", frame: .plan)
        b.tags("bed", "support", "leg", "adjustable", "center rail", "floor")
        b.aliases("bed support leg", "center support leg", "adjustable bed leg", "bed frame support", "6 in", "8 in", "12 in")
        b.material("Finish Material", .steel)
        b.material("Pad Material", .rubber)
        b.length("Support Height", CC.inch(8), instance: true, group: .placement, min: CC.inch(6), max: CC.inch(14))
        b.length("Saddle Width", CC.mm(45))
        b.length("Pad Diameter", CC.mm(60))
        b.number("Load Capacity", 500, unit: "lb", group: .data)
        b.host([.rail, .bottom], faces: [.bottom], align: .center)
        b.box("Saddle Base", x: ("-Saddle Width / 2", "Saddle Width / 2"), y: ("-0.04 m", "0.04 m"), z: ("-0.004 m", "0 m"))
        for s in ["-", ""] { b.box("Saddle Side", x: ("\(s)(Saddle Width / 2) - 0.002 m", "\(s)(Saddle Width / 2) + 0.002 m"), y: ("-0.04 m", "0.04 m"), z: ("0 m", "0.03 m")) }
        b.rodZ("Threaded Stem", x: "0 m", y: "0 m", d: CX.mm(12), from: "-Support Height * 0.45", to: "-0.004 m")
        b.cyl("Lock Nut", axis: .z, center: ("0 m", "0 m"), radius: CX.mm(11), from: "-Support Height * 0.45 - 0.008 m", to: "-Support Height * 0.45", segments: 6)
        b.cyl("Tube", axis: .z, center: ("0 m", "0 m"), radius: CX.mm(13), from: "-Support Height + 0.012 m", to: "-Support Height * 0.45 - 0.008 m")
        b.using("Pad Material")
        b.cyl("Floor Pad", axis: .z, center: ("0 m", "0 m"), radius: "Pad Diameter / 2", from: "-Support Height", to: "-Support Height + 0.012 m", segments: 32)
        b.using(nil)
        b.drill("Saddle screw", x: "0 m", y: "-0.025 m", diameter: CX.mm(4), depth: CX.mm(16))
        b.drill("Saddle screw", x: "0 m", y: "0.025 m", diameter: CX.mm(4), depth: CX.mm(16))
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Pad Diameter / 2"), .rect(("-Saddle Width / 2", "-0.04 m"), ("Saddle Width / 2", "0.04 m")))
        b.symbol(.top, [.coarse], .rect(("-Pad Diameter / 2", "-Support Height"), ("Pad Diameter / 2", "0.03 m")))
        b.type("Adjustable Bed Support - 6\" to 10\"", ["Support Height": CC.inch(8)], cost: 9, model: "ABS-610")
        b.type("Adjustable Bed Support - 10\" to 14\"", ["Support Height": CC.inch(12)], cost: 11, model: "ABS-1014")
        return b.build()
    }

    /// Steel centre support rail along the bed's length with two or three adjustable legs.
    static func centerSupportRail() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Center Support Rail", .beds, "Slats & Supports", "Steel centre rail from head to foot with adjustable legs, for full, queen and king beds.", frame: .plan)
        b.tags("bed", "center rail", "support", "steel", "frame", "legs")
        b.aliases("center support beam", "middle rail", "bed center beam", "bed frame center support", "full", "queen", "king")
        b.material("Finish Material", .matteBlack)
        b.material("Pad Material", .rubber)
        b.length("Rail Length", CC.inch(78))
        b.length("Rail Size", CC.mm(40))
        b.length("Leg Height", CC.inch(7), instance: true, group: .placement)
        b.number("Legs", 2, group: .dimensions)
        b.host([.rail, .bay, .bottom], faces: [.top, .bottom], align: .center)
        b.requires(.hostHeight(min: "Rail Length", max: nil))
        b.box("Rail", x: ("-Rail Size / 2", "Rail Size / 2"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("-Rail Size", "0 m"))
        for s in ["-", ""] { b.box("End Bracket", x: ("-Rail Size", "Rail Size"), y: ("\(s)(Rail Length / 2) - 0.003 m", "\(s)(Rail Length / 2) + 0.003 m"), z: ("-Rail Size - 0.02 m", "0 m")) }
        for k in 1...3 {
            let v: String? = k <= 2 ? nil : "Show Leg \(k)"
            if let v { b.countFlag(v, "Legs >= \(k)") }
            let y = "-Rail Length / 2 + Rail Length * (\(k) - 0.5) / Legs"
            b.shown(v) { b in
                b.using("Finish Material")
                b.rodZ("Leg \(k)", x: "0 m", y: y, d: CX.mm(25), from: "-Rail Size - Leg Height + 0.012 m", to: "-Rail Size")
                b.using("Pad Material")
                b.cyl("Leg \(k) Pad", axis: .z, center: ("0 m", y), radius: CX.mm(28), from: "-Rail Size - Leg Height", to: "-Rail Size - Leg Height + 0.012 m", segments: 28)
            }
        }
        b.using(nil)
        for s in ["-", ""] { b.drill("End bracket screw", x: "0 m", y: "\(s)(Rail Length / 2)", diameter: CX.mm(5), depth: CX.mm(20), target: .counterpart) }
        b.outlines(x: ("-Rail Size / 2", "Rail Size / 2"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("-Rail Size - Leg Height", "0 m"))
        b.type("Bed Center Support Rail - Full", ["Rail Length": CC.inch(73)], numbers: ["Legs": 2], cost: 29, model: "CSR-F")
        b.type("Bed Center Support Rail - Queen", [:], numbers: ["Legs": 2], cost: 32, model: "CSR-Q", isDefault: true)
        b.type("Bed Center Support Rail - King", [:], numbers: ["Legs": 3], cost: 39, model: "CSR-K")
        return b.build()
    }

    // MARK: Lift and fold mechanisms

    /// Gas-lift bed mechanism (one side; used in pairs): a base bracket on the side rail, a lift arm carrying the
    /// platform, and a gas spring with its stroke.
    static func gasLiftBed() -> ComponentDefinition {
        var b = ComponentBuilder("Gas Lift Bed Mechanism", .beds, "Lift & Fold", "Storage bed lift (one side, used in pairs): base bracket, lift arm and gas spring that raise the platform.")
        b.tags("bed", "gas lift", "storage bed", "ottoman", "gas spring", "lift")
        b.aliases("ottoman bed lift", "storage bed mechanism", "gas spring bed lift", "lift up bed hardware", "800 n", "1000 n", "1200 n", "1500 n")
        b.material("Frame Material", .matteBlack)
        b.material("Spring Material", .chrome)
        b.length("Arm Length", CC.mm(1200))
        b.length("Bracket Length", CC.mm(420))
        b.length("Stroke", CC.mm(250))
        b.length("Spring Length", CC.mm(600))
        b.length("Pivot Height", CC.mm(60))
        b.number("Spring Force", 1200, unit: "N", group: .dimensions)
        b.angle("Open Angle", 0, instance: true, group: .placement)
        b.length("Arm End X", 0, formula: "Arm Length * cos(Open Angle)")
        b.length("Arm End Y", 0, formula: "Pivot Height + Arm Length * sin(Open Angle)")
        b.length("Strut Top X", 0, formula: "0.38 m * cos(Open Angle)")
        b.length("Strut Top Y", 0, formula: "Pivot Height + 0.38 m * sin(Open Angle)")
        b.host([.rail, .sidePanel], faces: [.inside], align: .left, alignments: [.left, .right], mirroredPair: true)
        b.requires(.hostWidth(min: "Bracket Length + 0.1 m", max: nil))
        b.requires(.note("Pick the Spring Force for the platform plus mattress weight (about 10 N per lb, per pair)."))
        b.clearance(.box(name: "Platform swing", x0: "0 m", x1: "Arm Length", y0: "0 m", y1: "Pivot Height + Arm Length * 0.7", z0: "0 m", z1: "0.06 m"))
        b.using("Frame Material")
        b.box("Base Bracket", x: ("-0.04 m", "Bracket Length"), y: ("0 m", "0.05 m"), z: ("0 m", "0.004 m"))
        b.box("Pivot Plate", x: ("-0.04 m", "0.05 m"), y: ("0 m", "Pivot Height + 0.03 m"), z: ("0.004 m", "0.01 m"))
        b.cyl("Pivot", axis: .z, center: ("0 m", "Pivot Height"), radius: CX.mm(8), from: "0 m", to: "0.028 m")
        b.link("Lift Arm", plane: .xy, ("0 m", "Pivot Height"), ("Arm End X", "Arm End Y"), at: "0.022 m", width: CX.mm(40), thickness: CX.mm(4))
        b.link("Platform Angle", plane: .xy, ("Arm Length * 0.15 * cos(Open Angle)", "Pivot Height + Arm Length * 0.15 * sin(Open Angle)"), ("Arm End X", "Arm End Y"),
               at: "0.045 m", width: CX.mm(4), thickness: CX.mm(40))
        b.using("Spring Material")
        // Gas spring: body from the bracket's foot end, rod to the arm.
        b.strut("Spring Body", plane: .xy, ("Bracket Length", "0.025 m"), ("Bracket Length + (Strut Top X - Bracket Length) * 0.55", "0.025 m + (Strut Top Y - 0.025 m) * 0.55"),
                at: "0.03 m", d: CX.mm(22), segments: 16)
        b.strut("Spring Rod", plane: .xy, ("Bracket Length + (Strut Top X - Bracket Length) * 0.55", "0.025 m + (Strut Top Y - 0.025 m) * 0.55"), ("Strut Top X", "Strut Top Y"),
                at: "0.03 m", d: CX.mm(10), segments: 12)
        b.using(nil)
        for x in ["0 m", "Bracket Length * 0.5", "Bracket Length - 0.02 m"] { b.drill("Bracket screw", x: x, y: "0.025 m", diameter: CX.mm(5), depth: CX.mm(20)) }
        b.symbol(.top, [.coarse], .rect(("-0.04 m", "0 m"), ("Arm Length", "0.06 m")))
        b.symbol(.face, [.coarse], .line(("0 m", "Pivot Height"), ("Arm Length", "Pivot Height")), .rect(("-0.04 m", "0 m"), ("Bracket Length", "0.05 m")))
        b.symbol(.face, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("0 m", "Pivot Height"), radius: "Arm Length", startDegrees: "0", sweepDegrees: "45"))
        b.type("Gas Lift Bed Mechanism - Twin 800 N", ["Arm Length": CC.mm(1000)], numbers: ["Spring Force": 800], cost: 59, model: "GLB-800")
        b.type("Gas Lift Bed Mechanism - Full 1000 N", ["Arm Length": CC.mm(1150)], numbers: ["Spring Force": 1000], cost: 65, model: "GLB-1000")
        b.type("Gas Lift Bed Mechanism - Queen 1200 N", [:], numbers: ["Spring Force": 1200], cost: 69, model: "GLB-1200", isDefault: true)
        b.type("Gas Lift Bed Mechanism - King 1500 N", ["Arm Length": CC.mm(1250), "Stroke": CC.mm(300), "Spring Length": CC.mm(700)], numbers: ["Spring Force": 1500], cost: 79, model: "GLB-1500")
        return b.build()
    }

    /// Hydraulic storage bed lift (one side): a parallel linkage that raises the platform level, driven by a hydraulic
    /// cylinder.
    static func hydraulicBedLift() -> ComponentDefinition {
        var b = ComponentBuilder("Hydraulic Storage Bed Lift", .beds, "Lift & Fold", "Parallel-linkage storage lift (one side): the platform rises level on two links and a hydraulic cylinder.")
        b.tags("bed", "hydraulic", "storage bed", "lift", "parallel", "linkage")
        b.aliases("hydraulic bed lift", "level lift storage bed", "parallel lift bed", "bed lift kit", "hydraulic ottoman")
        b.material("Frame Material", .steel)
        b.material("Cylinder Material", .chrome)
        b.length("Link Length", CC.mm(350))
        b.length("Link Spacing", CC.mm(700))
        b.length("Base Length", CC.mm(900))
        b.angle("Lift Angle", 0, instance: true, group: .placement)
        b.number("Lift Force", 1500, unit: "N", group: .dimensions)
        b.length("Rise", 0, formula: "Link Length * sin(Lift Angle)")
        b.length("Shift", 0, formula: "Link Length * cos(Lift Angle)")
        b.host([.rail, .sidePanel], faces: [.inside], align: .center, mirroredPair: true)
        b.requires(.hostWidth(min: "Base Length", max: nil))
        b.using("Frame Material")
        b.box("Base Rail", x: ("-Base Length / 2", "Base Length / 2"), y: ("0 m", "0.04 m"), z: ("0 m", "0.005 m"))
        b.box("Top Rail", x: ("-Base Length / 2 + Shift - Link Length", "Base Length / 2 + Shift - Link Length"), y: ("0.04 m + Rise", "0.08 m + Rise"), z: ("0.03 m", "0.035 m"))
        for (k, x) in ["-Link Spacing / 2", "Link Spacing / 2"].enumerated() {
            b.link("Link \(k + 1)", plane: .xy, (x, "0.02 m"), ("\(x) + Shift - Link Length", "0.06 m + Rise"), at: "0.018 m", width: CX.mm(30), thickness: CX.mm(5))
            b.cyl("Link \(k + 1) Pivot", axis: .z, center: (x, "0.02 m"), radius: CX.mm(7), from: "0 m", to: "0.025 m")
        }
        b.using("Cylinder Material")
        b.strut("Cylinder", plane: .xy, ("Link Spacing / 2 + 0.08 m", "0.02 m"), ("Link Spacing / 2 + Shift * 0.5 - Link Length * 0.5 - 0.1 m", "0.04 m + Rise * 0.5"), at: "0.04 m", d: CX.mm(30))
        b.using(nil)
        for x in ["-Base Length / 2 + 0.03 m", "0 m", "Base Length / 2 - 0.03 m"] { b.drill("Base screw", x: x, y: "0.02 m", diameter: CX.mm(5), depth: CX.mm(20)) }
        b.symbol(.face, [.coarse], .rect(("-Base Length / 2", "0 m"), ("Base Length / 2", "0.08 m")))
        b.symbol(.top, [.coarse], .rect(("-Base Length / 2", "0 m"), ("Base Length / 2", "0.04 m")))
        b.type("Hydraulic Storage Bed Lift - Standard", [:], cost: 119, model: "HBL-STD")
        b.type("Hydraulic Storage Bed Lift - Heavy Duty", ["Link Length": CC.mm(400), "Base Length": CC.mm(1000)], numbers: ["Lift Force": 2200], cost: 159, model: "HBL-HD")
        return b.build()
    }

    /// Storage bed hinge: a heavy two-leaf pivot for a lift-up lid or headboard storage, without a spring.
    static func bedStorageHinge() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Storage Hinge", .beds, "Lift & Fold", "Heavy two-leaf pivot hinge for a lift-up storage lid or ottoman bed without springs.")
        b.tags("bed", "hinge", "storage", "ottoman", "lid", "pivot")
        b.aliases("ottoman hinge", "storage bed hinge", "lift up lid hinge", "bed box hinge", "heavy duty pivot hinge")
        b.material("Finish Material", .zinc)
        b.length("Leaf Length", CC.mm(160))
        b.length("Leaf Width", CC.mm(40))
        b.length("Leaf Thickness", CC.mm(3))
        b.angle("Open Angle", 0, instance: true, group: .placement)
        b.host([.rail, .sidePanel, .back], faces: [.inside], align: .top, alignments: [.top], count: ComponentCountRule(steps: [.init(upTo: 1.2, count: 2)], maximumCount: 3, inset: CC.inch(4)))
        b.box("Frame Leaf", x: ("-Leaf Length", "0 m"), y: ("-Leaf Width", "0 m"), z: ("0 m", "Leaf Thickness"))
        b.link("Lid Leaf", plane: .xy, ("0 m", "0 m"), ("-Leaf Length * cos(Open Angle)", "Leaf Length * sin(Open Angle)"), at: "Leaf Thickness * 1.5", width: "Leaf Width", thickness: "Leaf Thickness")
        b.cyl("Knuckle", axis: .z, center: ("0 m", "0 m"), radius: CX.mm(7), from: "0 m", to: "Leaf Thickness * 2.5")
        for x in ["-0.02 m", "-Leaf Length + 0.02 m"] { b.drill("Hinge screw", x: x, y: "-Leaf Width / 2", diameter: CX.mm(4.5), depth: CX.mm(16)) }
        b.outlines(plan: .top, elevation: .face, x: ("-Leaf Length", "0.007 m"), y: ("-Leaf Width", "0.007 m"), z: ("0 m", "Leaf Thickness * 2.5"))
        b.type("Bed Storage Hinge - 160 mm", [:], cost: 7, model: "BSTH-160")
        b.type("Bed Storage Hinge - 220 mm", ["Leaf Length": CC.mm(220), "Leaf Width": CC.mm(50)], cost: 9, model: "BSTH-220")
        return b.build()
    }

    /// Rollaway folding bed frame: two halves on a centre hinge, legs and casters; folds upright.
    static func foldingBed() -> ComponentDefinition {
        var b = ComponentBuilder("Folding Bed Mechanism", .beds, "Lift & Fold", "Rollaway folding bed frame: two tube halves on a centre hinge with legs and casters; folds upright.", frame: .plan)
        b.tags("bed", "folding", "rollaway", "guest bed", "frame", "caster")
        b.aliases("rollaway bed frame", "folding guest bed", "fold up bed", "cot frame", "twin", "31 in", "38 in")
        b.material("Frame Material", .steel)
        b.material("Caster Material", .blackPlastic)
        b.length("Frame Width", CC.inch(31))
        b.length("Frame Length", CC.inch(75))
        b.length("Frame Height", CC.inch(14))
        b.length("Tube Diameter", CC.mm(25))
        b.flag("Folded", false, group: .placement)
        b.flag("Open", false, formula: "not(Folded)")
        b.host([.floor], faces: [.top], align: .center)
        let w = "Frame Width / 2", l = "Frame Length / 2", h = "Frame Height", d = "Tube Diameter"
        b.shown("Open") { b in
            for s in ["-", ""] {
                b.rodY("Side Rail", x: "\(s)(\(w))", z: h, d: d, from: "-\(l)", to: l)
                b.rodX("End Rail", y: "\(s)(\(l))", z: h, d: d, from: "-\(w)", to: w)
                for t in ["-", ""] {
                    b.rodZ("Leg", x: "\(s)(\(w) - 0.03 m)", y: "\(t)(\(l) - 0.06 m)", d: d, from: "0.05 m", to: h)
                    b.using("Caster Material")
                    b.cyl("Caster", axis: .x, center: ("\(t)(\(l) - 0.06 m)", "0.025 m"), radius: "0.025 m", from: "\(s)(\(w) - 0.03 m) - 0.01 m", to: "\(s)(\(w) - 0.03 m) + 0.01 m")
                    b.using("Frame Material")
                }
            }
            b.rodX("Hinge Bar", y: "0 m", z: h, d: d, from: "-\(w)", to: w)
            b.box("Spring Deck", x: ("-\(w) + 0.02 m", "\(w) - 0.02 m"), y: ("-\(l) + 0.02 m", "\(l) - 0.02 m"), z: ("\(h) - 0.003 m", "\(h) + 0.003 m"))
        }
        b.shown("Folded") { b in
            for (k, y) in ["-0.06 m", "0.06 m"].enumerated() {
                b.box("Folded Half \(k + 1)", x: ("-\(w)", w), y: ("\(y) - 0.015 m", "\(y) + 0.015 m"), z: ("0.06 m", "0.06 m + \(l)"))
            }
            b.using("Caster Material")
            for s in ["-", ""] { b.cyl("Caster (Folded)", axis: .x, center: ("0 m", "0.025 m"), radius: "0.025 m", from: "\(s)(\(w) - 0.03 m) - 0.01 m", to: "\(s)(\(w) - 0.03 m) + 0.01 m") }
            b.using("Frame Material")
        }
        b.symbol(.face, [.coarse], .rect(("-\(w)", "-\(l)"), (w, l)), .line(("-\(w)", "0 m"), (w, "0 m")))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("-\(w)", "-0.08 m"), (w, "0.08 m")))
        b.symbol(.top, [.coarse], .rect(("-\(w)", "0 m"), (w, h)))
        b.type("Folding Bed Mechanism - 31\" Cot", [:], cost: 149, model: "FBM-31")
        b.type("Folding Bed Mechanism - 38\" Twin", ["Frame Width": CC.inch(38)], cost: 179, model: "FBM-38")
        return b.build()
    }

    /// Murphy (wall) bed mechanism, vertical: side pivot plates with piston lifts and the bed frame that swings down
    /// from the wall cabinet; Open Angle 0 is closed (upright), 90° open.
    static func murphyBed() -> ComponentDefinition {
        var b = ComponentBuilder("Murphy Bed Mechanism", .beds, "Lift & Fold", "Vertical wall bed mechanism: pivot plates with piston lifts and the bed frame, closed upright or open on its fold-down leg.",
                                 frame: .plan)
        b.tags("bed", "murphy", "wall bed", "fold-down", "piston", "mechanism")
        b.aliases("wall bed mechanism", "murphy bed hardware", "fold down bed kit", "vertical wall bed", "twin", "full", "queen")
        b.role(.module)
        b.material("Frame Material", .steel)
        b.material("Platform Material", ComponentFinish("Plywood", .wood, RGBColor(hex: 0xCDAF7D)))
        b.length("Frame Width", CC.inch(62))
        b.length("Frame Length", CC.inch(82))
        b.length("Pivot Height", CC.inch(9))
        b.length("Pivot Offset", CC.inch(4))
        b.length("Leg Height", CC.inch(9))
        b.angle("Open Angle", 0, instance: true, group: .placement)
        b.number("Piston Force", 1300, unit: "N", group: .data)
        b.length("End Y", 0, formula: "-Pivot Offset - Frame Length * sin(Open Angle)")
        b.length("End Z", 0, formula: "Pivot Height + Frame Length * cos(Open Angle)")
        b.host([.floor, .back, .wall], faces: [.top, .front], align: .center)
        b.requires(.note("Anchor the cabinet to the wall studs; the open bed reaches Pivot Offset + Frame Length from the wall."))
        b.clearance(.box(name: "Bed swing", x0: "-Frame Width / 2", x1: "Frame Width / 2", y0: "-Pivot Offset - Frame Length", y1: "0 m", z0: "0 m", z1: "Pivot Height + Frame Length"))
        let w = "Frame Width / 2"
        b.using("Frame Material")
        for s in ["-", ""] {
            let x = "\(s)(\(w) + 0.02 m)"
            b.box("Pivot Plate", x: ("\(x) - 0.004 m", "\(x) + 0.004 m"), y: ("-Pivot Offset - 0.15 m", "-0.02 m"), z: ("0 m", "Pivot Height + 0.25 m"))
            b.cyl("Pivot", axis: .x, center: ("-Pivot Offset", "Pivot Height"), radius: CX.mm(12), from: "\(x) - 0.03 m", to: "\(x) + 0.004 m")
            b.link("Side Rail", plane: .yz, ("-Pivot Offset", "Pivot Height"), ("End Y", "End Z"), at: "\(s)(\(w))", width: CX.mm(50), thickness: CX.mm(30))
            b.strut("Piston", plane: .yz, ("-0.05 m", "Pivot Height + 0.2 m"), ("-Pivot Offset + (End Y + Pivot Offset) * 0.25", "Pivot Height + (End Z - Pivot Height) * 0.25"),
                    at: "\(s)(\(w) + 0.03 m)", d: CX.mm(22))
        }
        b.rodX("Foot Rail", y: "End Y", z: "End Z", d: CX.mm(35), from: "-\(w)", to: w)
        b.rodX("Head Rail", y: "-Pivot Offset", z: "Pivot Height", d: CX.mm(35), from: "-\(w)", to: w)
        b.strut("Fold-Down Leg", plane: .yz, ("End Y", "End Z"), ("End Y - Leg Height * cos(Open Angle)", "End Z - Leg Height * sin(Open Angle)"), at: "0 m", d: CX.mm(30))
        b.using("Platform Material")
        b.link("Platform", plane: .yz, ("-Pivot Offset - 0.03 m * sin(Open Angle)", "Pivot Height + 0.03 m * cos(Open Angle)"),
               ("End Y + 0.03 m * sin(Open Angle)", "End Z - 0.03 m * cos(Open Angle)"), at: "0 m", width: CX.mm(18), thickness: "Frame Width - 0.04 m")
        b.using(nil)
        for s in ["-", ""] { b.drill("Floor anchor", x: "\(s)(\(w) + 0.02 m)", y: "-Pivot Offset - 0.1 m", diameter: CX.mm(8), depth: CX.mm(19)) }
        b.symbol(.face, [.coarse], .rect(("-\(w) - 0.03 m", "-Pivot Offset - 0.15 m"), ("\(w) + 0.03 m", "0 m")))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("-\(w)", "-Pivot Offset - Frame Length"), (w, "-Pivot Offset")))
        b.symbol(.side, [.coarse], dashed: true, .arc(center: FamilyPoint("Pivot Height", "-Pivot Offset"), radius: "Frame Length", startDegrees: "0", sweepDegrees: "-90"))
        b.symbol(.top, [.coarse], .rect(("-\(w) - 0.03 m", "0 m"), ("\(w) + 0.03 m", "Pivot Height + Frame Length")))
        for (n, wid, len, f, cost) in [("Twin", 41.0, 77.0, 900.0, 549.0), ("Full", 56, 77, 1100, 649), ("Queen", 62, 82, 1300, 749)] {
            b.type("Murphy Bed Mechanism - \(n) Vertical", ["Frame Width": CC.inch(wid), "Frame Length": CC.inch(len)], numbers: ["Piston Force": f], cost: cost, model: "MBM-\(n.prefix(1))V",
                   isDefault: n == "Queen")
        }
        return b.build()
    }

    // MARK: Headboards and nightstands

    /// Headboard bracket: a bolt-on steel plate with adjustment slots, joggled to clear the frame.
    static func headboardBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Headboard Bracket", .beds, "Headboard & Nightstand", "Bolt-on steel plate with two adjustment slots joining a headboard to a metal or wood frame.")
        b.tags("bed", "headboard", "bracket", "plate", "bolt-on", "adapter")
        b.aliases("headboard plate", "headboard adapter", "headboard mounting bracket", "bolt on headboard bracket", "universal headboard bracket")
        b.material("Finish Material", .matteBlack)
        b.length("Plate Length", CC.inch(10))
        b.length("Plate Width", CC.mm(50))
        b.length("Joggle", CC.mm(15))
        b.length("Slot Length", CC.mm(60))
        b.host([.back, .leg, .rail], faces: [.back, .outside], align: .bottom, alignments: [.bottom, .center])
        b.box("Frame Leg", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("0 m", "Plate Length * 0.4"), z: ("0 m", "0.004 m"))
        b.box("Joggle", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("Plate Length * 0.4", "Plate Length * 0.4 + 0.004 m"), z: ("0 m", "Joggle + 0.004 m"))
        b.box("Headboard Leg", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("Plate Length * 0.4", "Plate Length"), z: ("Joggle", "Joggle + 0.004 m"))
        for y in ["Plate Length * 0.2", "Plate Length * 0.75"] {
            b.groove("Adjustment slot", from: ("0 m", "\(y) - Slot Length / 2"), to: ("0 m", "\(y) + Slot Length / 2"), width: CX.mm(9), depth: CX.mm(4))
        }
        b.drill("Headboard bolt", x: "0 m", y: "Plate Length * 0.75", diameter: CX.mm(8), depth: CX.mm(25), target: .counterpart)
        b.outlines(plan: .top, elevation: .face, x: ("-Plate Width / 2", "Plate Width / 2"), y: ("0 m", "Plate Length"), z: ("0 m", "Joggle + 0.004 m"))
        b.type("Headboard Bracket - 10\" Bolt-On", [:], cost: 8, model: "HBB-10")
        b.type("Headboard Bracket - 14\" Universal", ["Plate Length": CC.inch(14), "Slot Length": CC.mm(100)], cost: 11, model: "HBB-14U")
        return b.build()
    }

    /// Bedside table connector: a flat steel strap that ties a nightstand to the bed frame so it can't drift.
    static func bedsideConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Bedside Table Connector", .beds, "Headboard & Nightstand", "Steel strap that ties a nightstand to the bed frame or headboard, with a slotted end for spacing.")
        b.tags("bed", "nightstand", "bedside", "connector", "strap", "bracket")
        b.aliases("nightstand connector", "bedside bracket", "nightstand to bed bracket", "floating nightstand bracket")
        b.material("Finish Material", .matteBlack)
        b.length("Strap Length", CC.mm(200))
        b.length("Strap Width", CC.mm(30))
        b.length("Offset", CC.mm(25), instance: true, group: .placement)
        b.host([.sidePanel, .back], faces: [.outside], align: .top, alignments: [.top, .center])
        b.box("Strap", x: ("0 m", "Strap Length"), y: ("-Strap Width / 2", "Strap Width / 2"), z: ("0 m", "0.003 m"))
        b.box("Return", x: ("Strap Length - 0.003 m", "Strap Length"), y: ("-Strap Width / 2", "Strap Width / 2"), z: ("0 m", "Offset"))
        b.box("Tab", x: ("Strap Length - 0.04 m", "Strap Length"), y: ("-Strap Width / 2", "Strap Width / 2"), z: ("Offset - 0.003 m", "Offset"))
        b.drill("Strap screw", x: "0.02 m", y: "0 m", diameter: CX.mm(4.5), depth: CX.mm(16))
        b.drill("Strap screw", x: "0.06 m", y: "0 m", diameter: CX.mm(4.5), depth: CX.mm(16))
        b.groove("Spacing slot", from: ("Strap Length * 0.4", "0 m"), to: ("Strap Length * 0.8", "0 m"), width: CX.mm(6), depth: CX.mm(3))
        b.outlines(plan: .top, elevation: .face, x: ("0 m", "Strap Length"), y: ("-Strap Width / 2", "Strap Width / 2"), z: ("0 m", "Offset"))
        b.type("Bedside Table Connector - 200 mm", [:], cost: 6, model: "BTC-200")
        b.type("Bedside Table Connector - 300 mm", ["Strap Length": CC.mm(300)], cost: 7.5, model: "BTC-300")
        return b.build()
    }

    // MARK: Drawers, casters, feet

    /// Under-bed drawer slides: a heavy-duty full-extension pair for the drawers in a bed base (legacy opening frame,
    /// like FM5's slides).
    static func underBedSlide() -> ComponentDefinition {
        var b = ComponentBuilder("Under-Bed Drawer Slide", .beds, "Drawers & Mobility", "Heavy-duty full-extension slide pair for under-bed drawers.", frame: .legacyOpening)
        b.tags("bed", "drawer", "slide", "under bed", "storage", "full extension")
        b.aliases("under bed drawer runner", "bed drawer slides", "storage bed slides", "heavy duty slide", "500 mm", "600 mm", "700 mm", "20 in", "24 in", "28 in")
        b.hardwareKind(.slide)
        b.material("Finish Material", .zinc)
        b.openingParameters(width: CC.mm(700), depth: CC.mm(720), height: CC.mm(200))
        b.length("Slide Length", CC.mm(600), group: .manufacturing)
        b.length("Slide Height", CC.mm(53))
        b.length("Slide Thickness", CC.mm(19))
        b.length("Mount Height", CC.mm(60), instance: true, group: .placement)
        b.length("Rear Clearance", CC.mm(10), group: .manufacturing)
        b.number("Load Rating", 150, unit: "lb", group: .data)
        b.host([.bay], faces: [.left, .right], align: .full, mirroredPair: true)
        b.requires(.fitsDepth("Slide Length + Rear Clearance"))
        b.clearance(.side("Slide Thickness"))
        b.sideRunners("Slide", width: "Opening Width", y: ("0.002 m", "0.002 m + Slide Length"), z: "Mount Height", height: "Slide Height", thickness: "Slide Thickness")
        for (x, axis) in [("0 m", "L"), ("Opening Width", "R")] {
            for y in ["0.037 m", "0.037 m + 0.224 m", "Slide Length - 0.02 m"] {
                b.drill("Slide screw (\(axis))", x: x, y: y, diameter: CX.mm(4), depth: CX.mm(12), target: .counterpart)
            }
        }
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Slide Length"), z: ("Mount Height - Slide Height / 2", "Mount Height + Slide Height / 2"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("0 m", "-Slide Length"), ("Opening Width", "0 m")))
        for (l, cost) in [(500.0, 34.0), (600, 39), (700, 45)] {
            b.type("Under-Bed Drawer Slide - \(Int(l)) mm", ["Slide Length": CC.mm(l)], cost: cost, model: "UBS-\(Int(l))")
        }
        return b.build()
    }

    /// Bed caster: a heavy swivel caster with brake on a plate under a rail or leg.
    static func bedCaster() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Caster", .beds, "Drawers & Mobility", "Heavy swivel bed caster with a total-lock brake, on a plate under a rail or leg.", frame: .plan)
        b.tags("bed", "caster", "wheel", "brake", "swivel", "mobility")
        b.aliases("bed wheel", "bed frame caster", "locking bed caster", "rug caster", "2 in", "3 in", "50 mm", "75 mm")
        b.material("Finish Material", .zinc)
        b.material("Wheel Material", .greyPlastic)
        b.length("Wheel Diameter", CC.inch(2))
        b.length("Wheel Width", CC.mm(25))
        b.length("Plate Size", CC.inch(2.5))
        b.number("Load Capacity", 150, unit: "lb", group: .data)
        b.host([.leg, .rail, .bottom], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight, .center], offsetX: CC.inch(1), offsetY: CC.inch(1))
        b.caster("Caster", x: "0 m", y: "0 m", top: "0 m", wheel: "Wheel Diameter", wheelWidth: "Wheel Width", plateSize: "Plate Size")
        b.box("Brake Pedal", x: ("-0.012 m", "0.012 m"), y: ("-Wheel Diameter * 0.75", "-Wheel Diameter * 0.2"), z: ("-Wheel Diameter * 0.55", "-Wheel Diameter * 0.45"))
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] { b.drill("Plate screw", x: "\(x) * Plate Size * 0.35", y: "\(y) * Plate Size * 0.35", diameter: CX.mm(4.5), depth: CX.mm(16)) }
        b.symbol(.face, [.coarse], .rect(("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2")), .circle(("0 m", "0 m"), "Wheel Diameter * 0.6"))
        b.symbol(.top, [.coarse], .circle(("0 m", "-Wheel Diameter / 2 - 0.012 m"), "Wheel Diameter / 2"))
        b.type("Bed Caster - 2\" Locking", [:], cost: 6.5, model: "BC-2L")
        b.type("Bed Caster - 3\" Locking", ["Wheel Diameter": CC.inch(3), "Plate Size": CC.inch(3)], numbers: ["Load Capacity": 250], cost: 8.5, model: "BC-3L")
        return b.build()
    }

    /// Bed leveling foot: a wide pad on a threaded stem with its insert, for bed frames and bases.
    static func bedLevelingFoot() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Leveling Foot", .beds, "Drawers & Mobility", "Wide swivel pad on a threaded stem, screwed into a bed frame or base leg.", frame: .plan)
        b.tags("bed", "leveling", "foot", "glide", "adjustable", "floor")
        b.aliases("bed leveler", "bed frame glide", "adjustable bed foot", "bed leg leveler", "2 in", "3 in", "M10", "3/8 in")
        b.material("Finish Material", .zinc)
        b.material("Pad Material", .blackPlastic)
        b.length("Pad Diameter", CC.inch(2.5))
        b.length("Stem Length", CC.mm(40))
        b.length("Adjustment", CC.mm(15), instance: true, group: .placement, min: 0, max: CC.mm(30))
        b.text("Thread", "3/8\"-16", group: .manufacturing)
        b.host([.leg, .rail, .bottom], faces: [.bottom], align: .center)
        b.requires(.hostThickness(min: "Stem Length - Adjustment + 0.005 m", max: nil))
        b.rodZ("Stem", x: "0 m", y: "0 m", d: CX.mm(9.5), from: "-Adjustment - 0.012 m", to: "Stem Length - Adjustment")
        b.cyl("Nut", axis: .z, center: ("0 m", "0 m"), radius: CX.mm(9), from: "-Adjustment", to: "-Adjustment + 0.006 m", segments: 6)
        b.using("Pad Material")
        b.revolve("Pad", profile: ComponentKit.points([("0 m", "0 m"), ("Pad Diameter / 2", "0 m"), ("Pad Diameter / 2", "0.005 m"), ("Pad Diameter * 0.3", "0.012 m"), ("0 m", "0.012 m")]),
                  base: "-Adjustment - 0.024 m")
        b.using(nil)
        b.drill("Insert hole", x: "0 m", y: "0 m", diameter: CX.mm(12), depth: "Stem Length")
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Pad Diameter / 2"))
        b.symbol(.top, [.coarse], .rect(("-Pad Diameter / 2", "-Adjustment - 0.024 m"), ("Pad Diameter / 2", "0 m")))
        b.type("Bed Leveling Foot - 2 1/2\"", [:], cost: 2.5, model: "BLF-25")
        b.type("Bed Leveling Foot - 3 1/2\" Heavy", ["Pad Diameter": CC.inch(3.5), "Stem Length": CC.mm(50)], texts: ["Thread": "1/2\"-13"], cost: 3.5, model: "BLF-35")
        return b.build()
    }

    /// Mattress retainer: a U-shaped steel bar at the foot of an adjustable or platform base that stops the mattress
    /// sliding.
    static func mattressRetainer() -> ComponentDefinition {
        var b = ComponentBuilder("Mattress Retainer", .beds, "Headboard & Nightstand", "U-shaped steel bar in two sockets at the foot of a base that keeps the mattress from sliding.", frame: .plan)
        b.tags("bed", "mattress", "retainer", "bar", "adjustable base", "foot")
        b.aliases("mattress retainer bar", "mattress stopper", "mattress holder bar", "foot retainer", "4 in", "6 in")
        b.material("Finish Material", .matteBlack)
        b.length("Retainer Width", CC.inch(30))
        b.length("Retainer Height", CC.inch(4))
        b.length("Bar Diameter", CC.mm(12))
        b.host([.rail, .top], faces: [.top], align: .bottom, alignments: [.bottom, .center])
        b.wire("Bar", plane: .xz, [("-Retainer Width / 2", "-0.03 m"), ("-Retainer Width / 2", "Retainer Height - 0.02 m"), ("-Retainer Width / 2 + 0.02 m", "Retainer Height"),
                                    ("Retainer Width / 2 - 0.02 m", "Retainer Height"), ("Retainer Width / 2", "Retainer Height - 0.02 m"), ("Retainer Width / 2", "-0.03 m")],
               at: "0 m", d: "Bar Diameter")
        for s in ["-", ""] {
            b.cyl("Socket", axis: .z, center: ("\(s)(Retainer Width / 2)", "0 m"), radius: "Bar Diameter / 2 + 0.003 m", from: "-0.035 m", to: "0.004 m")
            b.drill("Socket hole", x: "\(s)(Retainer Width / 2)", y: "0 m", diameter: "Bar Diameter + 0.006 m", depth: CX.mm(35))
        }
        b.symbol(.face, [.coarse], .line(("-Retainer Width / 2", "0 m"), ("Retainer Width / 2", "0 m")))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("-Retainer Width / 2", "0 m"), ("-Retainer Width / 2", "Retainer Height"), ("Retainer Width / 2", "Retainer Height"),
                                                                ("Retainer Width / 2", "0 m")]), closed: false))
        b.type("Mattress Retainer - 30\" x 4\"", [:], cost: 15, model: "MR-304")
        b.type("Mattress Retainer - 36\" x 6\"", ["Retainer Width": CC.inch(36), "Retainer Height": CC.inch(6)], cost: 18, model: "MR-366")
        return b.build()
    }
}
