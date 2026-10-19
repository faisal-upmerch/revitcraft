import Foundation
import ArcusGeometry

// COMPC: 11 Table & Desk Hardware. Plan frame throughout: items under a top hang below its underside (origin on the
// underside, negative Z); items on the top (grommets, power and charging modules, monitor arms, screens, lights) stand
// on its upper face (origin on the top face, positive Z, cutouts below as voids and through-pockets). Desk frames hang
// from the underside of the top to the floor, so their Frame Height is the height of the top's underside. -Y is the
// front (the user's side); edge-mounted items sit on the back edge at Y = 0.

extension ComponentsC {
    static var tables: [ComponentDefinition] {
        [legMountingPlate(), deskFrame(), heightAdjustableMechanism(), electricDeskFrame(), crankDeskFrame(), foldingTableHinge(), dropLeafSupport(),
         extensionSlide(), butterflyLeaf(), tabletopConnector(), deskGrommet(), cableTray(), cableRaceway(), cableClip(), cableBasket(), monitorArm(),
         keyboardTray(), cpuHolder(), deskDrawer(), privacyPanel(), modestyPanel(), deskDivider(), powerModule(), usbModule(), wirelessCharger(),
         deskLight(), deskHook()]
    }

    // MARK: Mounting and connectors

    /// Leg mounting plate: a steel plate screwed under the top with a threaded boss for a hanger-bolt leg, straight or
    /// angled.
    static func legMountingPlate() -> ComponentDefinition {
        var b = ComponentBuilder("Table Leg Mounting Plate", .tables, "Mounting & Connectors", "Steel plate screwed under the top with a threaded boss for a hanger-bolt leg.",
                                 frame: .plan)
        b.tags("table", "leg", "plate", "mounting", "hanger bolt", "angled")
        b.aliases("leg mounting plate", "leg plate", "top plate", "angled leg plate", "straight leg plate", "5/16 in", "M8", "3 in", "10°")
        b.material("Finish Material", .zinc)
        b.length("Plate Size", CC.inch(3))
        b.length("Plate Thickness", CC.mm(2.5))
        b.length("Boss Diameter", CC.mm(16))
        b.length("Boss Length", CC.mm(12))
        b.angle("Leg Angle", 0)
        b.text("Thread", "5/16\"-18", group: .manufacturing)
        b.number("Load Capacity", 150, unit: "lb", group: .data)
        b.host([.top, .bottom, .shelf], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight, .center], offsetX: CC.inch(2), offsetY: CC.inch(2))
        b.requires(.hostThickness(min: "0.016 m", max: nil))
        b.plate("Plate", width: "Plate Size", depth: "Plate Size", radius: "Plate Size * 0.12", z: ("-Plate Thickness", "0 m"))
        b.strut("Boss", plane: .xz, ("0 m", "-Plate Thickness"), ("Boss Length * sin(Leg Angle)", "-Plate Thickness - Boss Length * cos(Leg Angle)"), at: "0 m", d: "Boss Diameter", segments: 20)
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] {
            b.drill("Plate screw", x: "\(x) * Plate Size * 0.36", y: "\(y) * Plate Size * 0.36", diameter: CX.mm(3.5), depth: CX.inch(0.625))
        }
        b.symbol(.face, [.coarse], .rect(("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2")), .circle(("0 m", "0 m"), "Boss Diameter / 2"))
        b.symbol(.top, [.coarse], .rect(("-Plate Size / 2", "-Plate Thickness - Boss Length"), ("Plate Size / 2", "0 m")))
        b.type("Table Leg Mounting Plate - Straight 3\"", [:], cost: 3.5, model: "LMP-S3")
        b.type("Table Leg Mounting Plate - Straight 4\"", ["Plate Size": CC.inch(4), "Plate Thickness": CC.mm(3)], numbers: ["Load Capacity": 220], cost: 4.5, model: "LMP-S4")
        b.type("Table Leg Mounting Plate - Angled 10° 3\"", ["Leg Angle": 10 * .pi / 180], cost: 4, model: "LMP-A3")
        b.type("Table Leg Mounting Plate - Angled 15° 4\"", ["Leg Angle": 15 * .pi / 180, "Plate Size": CC.inch(4), "Plate Thickness": CC.mm(3)], cost: 5, model: "LMP-A4")
        return b.build()
    }

    /// Dog-bone tabletop connector: two barrels in 35 mm bores joined by a bolt across a top's seam.
    static func tabletopConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Tabletop Connector", .tables, "Mounting & Connectors", "Dog-bone connector: barrels in two bores across the seam, drawn together by a bolt.",
                                 frame: .plan)
        b.tags("table", "top", "connector", "seam", "joining", "worktop")
        b.aliases("dog bone connector", "worktop connector bolt", "table top fastener", "seam connector", "100 mm", "150 mm", "35 mm")
        b.material("Finish Material", .zinc)
        b.length("Bolt Length", CC.mm(100))
        b.length("Barrel Diameter", CC.mm(35))
        b.length("Bore Depth", CC.mm(20))
        b.length("Bolt Diameter", CC.mm(8))
        b.host([.top], faces: [.bottom], align: .center)
        b.requires(.hostThickness(min: "Bore Depth + 0.008 m", max: nil))
        b.requires(.note("Center it on the seam between the two tops."))
        for s in ["-", ""] {
            b.cyl("Barrel", axis: .z, center: ("\(s)(Bolt Length / 2 - Barrel Diameter / 2)", "0 m"), radius: "Barrel Diameter / 2 - 0.001 m", from: "-0.002 m", to: "Bore Depth - 0.004 m")
            b.drill("Connector bore", x: "\(s)(Bolt Length / 2 - Barrel Diameter / 2)", y: "0 m", diameter: "Barrel Diameter", depth: "Bore Depth")
        }
        b.rodX("Bolt", y: "0 m", z: "Bore Depth / 2", d: "Bolt Diameter", from: "-Bolt Length / 2 + Barrel Diameter / 2", to: "Bolt Length / 2 - Barrel Diameter / 2")
        b.groove("Bolt channel", from: ("-Bolt Length / 2 + Barrel Diameter", "0 m"), to: ("Bolt Length / 2 - Barrel Diameter", "0 m"), width: "Bolt Diameter + 0.002 m", depth: "Bore Depth / 2 + Bolt Diameter / 2")
        b.symbol(.face, [.coarse], .circle(("-Bolt Length / 2 + Barrel Diameter / 2", "0 m"), "Barrel Diameter / 2"), .circle(("Bolt Length / 2 - Barrel Diameter / 2", "0 m"), "Barrel Diameter / 2"),
                 .line(("-Bolt Length / 2 + Barrel Diameter", "0 m"), ("Bolt Length / 2 - Barrel Diameter", "0 m")))
        b.symbol(.top, [.coarse], .rect(("-Bolt Length / 2", "0 m"), ("Bolt Length / 2", "Bore Depth")))
        b.type("Tabletop Connector - 100 mm", [:], cost: 1.6, model: "TTC-100")
        b.type("Tabletop Connector - 150 mm", ["Bolt Length": CC.mm(150)], cost: 2.1, model: "TTC-150")
        return b.build()
    }

    // MARK: Desk frames

    /// A static desk frame: two legs on T-feet, top support arms, a crossbar and leveling glides.
    static func deskFrame() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Frame", .tables, "Desk Frames", "Steel desk frame: two legs on T-feet with top support arms, a crossbar and leveling glides.", frame: .plan)
        b.tags("desk", "frame", "table", "base", "steel", "office")
        b.aliases("desk base", "steel desk frame", "table frame", "office desk legs", "48 in", "60 in", "72 in", "1200 mm", "1500 mm", "1800 mm")
        b.role(.module)
        b.material("Frame Material", .matteBlack)
        b.material("Glide Material", .blackPlastic)
        b.length("Frame Width", CC.inch(56))
        b.length("Frame Depth", CC.inch(26))
        b.length("Frame Height", CC.inch(28.5), instance: true, group: .placement, min: CC.inch(22), max: CC.inch(32))
        b.length("Leg Size", CC.mm(60))
        b.length("Foot Height", CC.mm(40))
        b.length("Crossbar Height", CC.mm(380), instance: true, group: .placement)
        b.number("Load Capacity", 220, unit: "lb", group: .data)
        b.host([.top], faces: [.bottom], align: .center)
        b.requires(.hostWidth(min: "Frame Width + 0.05 m", max: nil))
        b.requires(.hostHeight(min: "Frame Depth", max: nil))
        b.clearance(.box(name: "Knee space", x0: "-Frame Width / 2 + Leg Size", x1: "Frame Width / 2 - Leg Size", y0: "-Frame Depth / 2", y1: "Frame Depth / 2", z0: "-Frame Height", z1: "-0.04 m"))
        let lx = "Frame Width / 2 - Leg Size / 2"
        for (s, n) in [("-", "Left"), ("", "Right")] {
            let x = "\(s)(\(lx))"
            b.box("\(n) Leg", x: ("\(x) - Leg Size / 2", "\(x) + Leg Size / 2"), y: ("-Leg Size * 0.4", "Leg Size * 0.4"), z: ("-Frame Height + Foot Height", "-0.04 m"))
            b.roundedBar("\(n) Foot", center: (x, "0 m"), width: "Leg Size", height: "Frame Depth - 0.02 m", radius: "Leg Size * 0.3",
                         from: "-Frame Height + 0.012 m", to: "-Frame Height + Foot Height")
            b.box("\(n) Top Arm", x: ("\(x) - Leg Size / 2", "\(x) + Leg Size / 2"), y: ("-Frame Depth / 2", "Frame Depth / 2"), z: ("-0.04 m", "0 m"))
            b.using("Glide Material")
            for y in ["-(Frame Depth / 2 - 0.04 m)", "Frame Depth / 2 - 0.04 m"] {
                b.cyl("\(n) Glide", axis: .z, center: (x, y), radius: "0.014 m", from: "-Frame Height", to: "-Frame Height + 0.012 m")
            }
            b.using("Frame Material")
            for y in ["-(Frame Depth / 2 - 0.05 m)", "Frame Depth / 2 - 0.05 m"] {
                b.drill("Top screw", x: x, y: y, diameter: CX.mm(5), depth: CX.mm(16))
            }
        }
        b.box("Crossbar", x: ("-(\(lx)) + Leg Size / 2", "\(lx) - Leg Size / 2"), y: ("Leg Size * 0.1", "Leg Size * 0.4"), z: ("-Frame Height + Crossbar Height", "-Frame Height + Crossbar Height + 0.05 m"))
        b.box("Top Beam", x: ("-(\(lx)) + Leg Size / 2", "\(lx) - Leg Size / 2"), y: ("Frame Depth * 0.2", "Frame Depth * 0.2 + 0.03 m"), z: ("-0.07 m", "0 m"))
        b.outlines(x: ("-Frame Width / 2", "Frame Width / 2"), y: ("-Frame Depth / 2", "Frame Depth / 2"), z: ("-Frame Height", "0 m"))
        for (w, d, cost) in [(44.0, 22.0, 139.0), (56, 26, 159), (68, 26, 189)] {
            b.type("Desk Frame - \(Int(w + 4))\"", ["Frame Width": CC.inch(w), "Frame Depth": CC.inch(d)], cost: cost, model: "DF-\(Int(w + 4))", description: "Desk frame for a \(Int(w + 4))\" top")
        }
        return b.build()
    }

    /// Columns for a desk (telescoping stages between a foot and the top's support arm), shared by the electric and crank
    /// frames: `stages` 2 or 3 with the 3-stage middle shown by the "Three Stage" flag.
    static func liftColumns(_ b: inout ComponentBuilder, crank: Bool) {
        let lx = "Frame Width / 2 - 0.035 m"
        b.length("Column Top", 0, formula: "-0.035 m")
        b.length("Foot Top", 0, formula: "-Desk Height + Foot Height")
        b.length("Stage Length", 0, formula: "(Desk Height - Foot Height - 0.035 m) / if(Three Stage, 3, 2) + 0.05 m")
        b.countFlag("Middle Stage", "Three Stage")
        for (s, n) in [("-", "Left"), ("", "Right")] {
            let x = "\(s)(\(lx))"
            b.using("Frame Material")
            b.box("\(n) Outer Stage", x: ("\(x) - 0.04 m", "\(x) + 0.04 m"), y: ("-0.03 m", "0.03 m"), z: ("Foot Top", "Foot Top + Stage Length"))
            b.shown("Middle Stage") { $0.box("\(n) Middle Stage", x: ("\(x) - 0.036 m", "\(x) + 0.036 m"), y: ("-0.026 m", "0.026 m"), z: ("Foot Top + Stage Length - 0.05 m", "Column Top - Stage Length + 0.05 m")) }
            b.box("\(n) Inner Stage", x: ("\(x) - 0.032 m", "\(x) + 0.032 m"), y: ("-0.022 m", "0.022 m"), z: ("Column Top - Stage Length", "Column Top"))
            b.roundedBar("\(n) Foot", center: (x, "0 m"), width: "0.07 m", height: "Frame Depth", radius: "0.02 m", from: "-Desk Height + 0.01 m", to: "Foot Top")
            b.box("\(n) Top Arm", x: ("\(x) - 0.03 m", "\(x) + 0.03 m"), y: ("-Frame Depth / 2 + 0.03 m", "Frame Depth / 2 - 0.03 m"), z: ("Column Top", "0 m"))
            b.using("Glide Material")
            for y in ["-(Frame Depth / 2 - 0.04 m)", "Frame Depth / 2 - 0.04 m"] {
                b.cyl("\(n) Glide", axis: .z, center: (x, y), radius: "0.012 m", from: "-Desk Height", to: "-Desk Height + 0.01 m")
            }
            for y in ["-(Frame Depth / 2 - 0.06 m)", "Frame Depth / 2 - 0.06 m"] { b.drill("Top screw", x: x, y: y, diameter: CX.mm(5), depth: CX.mm(16)) }
        }
        b.using("Frame Material")
        b.box("Cross Beam", x: ("-(\(lx)) + 0.04 m", "\(lx) - 0.04 m"), y: ("0.04 m", "0.09 m"), z: ("-0.06 m", "-0.01 m"))
        b.clearance(.box(name: "Knee space", x0: "-Frame Width / 2 + 0.08 m", x1: "Frame Width / 2 - 0.08 m", y0: "-Frame Depth / 2", y1: "Frame Depth / 2", z0: "-Desk Height", z1: "-0.06 m"))
        b.outlines(x: ("-Frame Width / 2", "Frame Width / 2"), y: ("-Frame Depth / 2", "Frame Depth / 2"), z: ("-Desk Height", "0 m"))
        b.symbol(.top, [.medium, .fine], dashed: true, .line(("-Frame Width / 2", "-Maximum Height"), ("Frame Width / 2", "-Maximum Height")),
                 .line(("-Frame Width / 2", "-Minimum Height"), ("Frame Width / 2", "-Minimum Height")))
        _ = crank
    }

    /// Electric sit-stand desk frame: two telescoping lifting columns with motors, a cross beam, control box and handset.
    static func electricDeskFrame() -> ComponentDefinition {
        var b = ComponentBuilder("Electric Standing Desk Frame", .tables, "Desk Frames", "Sit-stand desk frame: motorized telescoping columns, cross beam, control box and handset.",
                                 frame: .plan)
        b.tags("desk", "standing", "sit-stand", "electric", "height adjustable", "motor")
        b.aliases("standing desk frame", "sit stand desk", "electric desk base", "motorized desk frame", "dual motor", "3-stage", "2-stage")
        b.role(.module)
        b.material("Frame Material", ComponentFinish("Powder Coat - White", .metal, RGBColor(hex: 0xE9E9E6)))
        b.material("Glide Material", .blackPlastic)
        b.material("Control Material", .blackPlastic)
        b.length("Frame Width", CC.inch(55), instance: true, group: .placement, min: CC.inch(43), max: CC.inch(71))
        b.length("Frame Depth", CC.inch(27))
        b.length("Desk Height", CC.inch(29), instance: true, group: .placement)
        b.length("Minimum Height", CC.inch(24.5))
        b.length("Maximum Height", CC.inch(50))
        b.length("Foot Height", CC.mm(45))
        b.flag("Three Stage", true, instance: false, group: .dimensions)
        b.number("Motors", 2, group: .data)
        b.number("Lift Capacity", 275, unit: "lb", group: .data)
        b.number("Speed", 1.5, unit: "in/s", group: .data)
        b.electrical(watts: 300, volts: 120, supply: "AC 120 V to control box, DC 29 V to motors", cable: "6 ft power cord; motor and handset cables in the cross beam", connector: "NEMA 5-15")
        b.host([.top], faces: [.bottom], align: .center)
        b.requires(.hostWidth(min: "Frame Width + 0.05 m", max: nil))
        b.requires(.note("Desk Height must stay between Minimum Height and Maximum Height."))
        liftColumns(&b, crank: false)
        b.using("Control Material")
        b.box("Control Box", x: ("-0.12 m", "0.12 m"), y: ("0.1 m", "0.2 m"), z: ("-0.07 m", "-0.01 m"))
        b.box("Handset", x: ("Frame Width / 2 - 0.25 m", "Frame Width / 2 - 0.1 m"), y: ("-Frame Depth / 2 + 0.01 m", "-Frame Depth / 2 + 0.06 m"), z: ("-0.025 m", "0 m"))
        for (s, n) in [("-", "Left"), ("", "Right")] {
            b.box("\(n) Motor", x: ("\(s)(Frame Width / 2 - 0.035 m) - 0.03 m", "\(s)(Frame Width / 2 - 0.035 m) + 0.03 m"), y: ("0.03 m", "0.11 m"), z: ("-0.09 m", "-0.035 m"))
        }
        b.using(nil)
        b.type("Electric Standing Desk Frame - Dual Motor 3-Stage", [:], cost: 429, model: "ESD-D3", isDefault: true)
        b.type("Electric Standing Desk Frame - Dual Motor 2-Stage", ["Minimum Height": CC.inch(28), "Maximum Height": CC.inch(47)], flags: ["Three Stage": false],
               numbers: ["Lift Capacity": 220], cost: 349, model: "ESD-D2")
        b.type("Electric Standing Desk Frame - Single Motor 2-Stage", ["Minimum Height": CC.inch(28), "Maximum Height": CC.inch(47), "Frame Width": CC.inch(47)], flags: ["Three Stage": false],
               numbers: ["Motors": 1, "Lift Capacity": 154, "Power": 150], cost: 249, model: "ESD-S2")
        return b.build()
    }

    /// Manual crank sit-stand frame: two telescoping columns driven by a hex shaft through the cross beam and a folding
    /// crank handle.
    static func crankDeskFrame() -> ComponentDefinition {
        var b = ComponentBuilder("Manual Crank Desk Frame", .tables, "Desk Frames", "Crank sit-stand frame: two telescoping columns, a hex drive shaft and a folding crank handle.",
                                 frame: .plan)
        b.tags("desk", "standing", "crank", "manual", "height adjustable", "sit-stand")
        b.aliases("hand crank desk", "crank standing desk", "manual sit stand frame", "crank adjustable desk", "2-stage")
        b.role(.module)
        b.material("Frame Material", ComponentFinish("Powder Coat - Grey", .metal, RGBColor(hex: 0x8E9196)))
        b.material("Glide Material", .blackPlastic)
        b.length("Frame Width", CC.inch(47), instance: true, group: .placement, min: CC.inch(39), max: CC.inch(63))
        b.length("Frame Depth", CC.inch(24))
        b.length("Desk Height", CC.inch(29), instance: true, group: .placement)
        b.length("Minimum Height", CC.inch(28))
        b.length("Maximum Height", CC.inch(45))
        b.length("Foot Height", CC.mm(40))
        b.length("Crank Length", CC.mm(160))
        b.flag("Three Stage", false, instance: false, group: .dimensions)
        b.number("Turns per Inch", 6, group: .data)
        b.number("Lift Capacity", 175, unit: "lb", group: .data)
        b.host([.top], faces: [.bottom], align: .center)
        b.requires(.hostWidth(min: "Frame Width + 0.05 m", max: nil))
        liftColumns(&b, crank: true)
        b.rodX("Drive Shaft", y: "0.065 m", z: "-0.035 m", d: CX.mm(8), from: "-Frame Width / 2 + 0.035 m", to: "Frame Width / 2 - 0.035 m")
        b.box("Gearbox", x: ("Frame Width / 2 - 0.08 m", "Frame Width / 2 - 0.035 m"), y: ("-0.04 m", "0.03 m"), z: ("-0.1 m", "-0.04 m"))
        b.strut("Crank Arm", plane: .yz, ("-0.04 m", "-0.07 m"), ("-0.04 m - Crank Length", "-0.12 m"), at: "Frame Width / 2 - 0.06 m", d: CX.mm(12))
        b.rodX("Crank Grip", y: "-0.04 m - Crank Length", z: "-0.12 m", d: CX.mm(22), from: "Frame Width / 2 - 0.1 m", to: "Frame Width / 2 - 0.06 m")
        b.type("Manual Crank Desk Frame - 2-Stage", [:], cost: 199, model: "MCD-2")
        b.type("Manual Crank Desk Frame - 3-Stage", ["Minimum Height": CC.inch(25), "Maximum Height": CC.inch(49)], flags: ["Three Stage": true], cost: 259, model: "MCD-3")
        return b.build()
    }

    /// Pneumatic sit-stand mechanism: one gas-spring column on a T-foot with a release paddle, for small desks and
    /// lecterns.
    static func heightAdjustableMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Height-Adjustable Desk Mechanism", .tables, "Desk Frames", "Pneumatic single-column lift: a gas-spring column on a T-foot with a release paddle.",
                                 frame: .plan)
        b.tags("desk", "height adjustable", "pneumatic", "gas spring", "column", "lift")
        b.aliases("pneumatic desk lift", "gas spring desk column", "sit stand column", "lectern base", "400 mm stroke", "16 in stroke")
        b.material("Frame Material", .aluminum)
        b.material("Foot Material", .matteBlack)
        b.length("Desk Height", CC.inch(30), instance: true, group: .placement)
        b.length("Stroke", CC.mm(400))
        b.length("Column Diameter", CC.mm(70))
        b.length("Foot Length", CC.mm(600))
        b.length("Top Plate Size", CC.mm(250))
        b.number("Lift Force", 400, unit: "N", group: .data)
        b.length("Minimum Height", 0, formula: "0.71 m")
        b.length("Maximum Height", 0, formula: "Minimum Height + Stroke")
        b.host([.top], faces: [.bottom], align: .center)
        b.requires(.hostWidth(min: "Top Plate Size", max: nil))
        b.requires(.note("Set Lift Force to the top's weight plus what it carries."))
        b.plate("Top Plate", width: "Top Plate Size", depth: "Top Plate Size * 0.6", radius: CX.mm(8), z: ("-0.006 m", "0 m"))
        b.cyl("Inner Column", axis: .z, center: ("0 m", "0 m"), radius: "Column Diameter / 2 - 0.006 m", from: "-(Desk Height - 0.05 m) / 2", to: "-0.006 m", segments: 32)
        b.cyl("Outer Column", axis: .z, center: ("0 m", "0 m"), radius: "Column Diameter / 2", from: "-Desk Height + 0.04 m", to: "-(Desk Height - 0.05 m) / 2 - 0.02 m", segments: 32)
        b.box("Release Paddle", x: ("Top Plate Size / 2 - 0.06 m", "Top Plate Size / 2 + 0.04 m"), y: ("-Top Plate Size * 0.3", "-Top Plate Size * 0.3 + 0.03 m"), z: ("-0.016 m", "-0.006 m"))
        b.using("Foot Material")
        b.roundedBar("Foot", width: "Foot Length", height: "0.08 m", radius: "0.03 m", from: "-Desk Height", to: "-Desk Height + 0.04 m")
        b.roundedBar("Foot Cross", width: "0.08 m", height: "Foot Length * 0.7", radius: "0.03 m", from: "-Desk Height", to: "-Desk Height + 0.04 m")
        b.using(nil)
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] {
            b.drill("Plate screw", x: "\(x) * Top Plate Size * 0.4", y: "\(y) * Top Plate Size * 0.22", diameter: CX.mm(5), depth: CX.mm(16))
        }
        b.outlines(x: ("-Foot Length / 2", "Foot Length / 2"), y: ("-Foot Length * 0.35", "Foot Length * 0.35"), z: ("-Desk Height", "0 m"))
        b.type("Height-Adjustable Desk Mechanism - 400 mm Stroke", [:], cost: 189, model: "HAM-400")
        b.type("Height-Adjustable Desk Mechanism - 500 mm Stroke", ["Stroke": CC.mm(500), "Foot Length": CC.mm(700)], numbers: ["Lift Force": 500], cost: 229, model: "HAM-500")
        return b.build()
    }

    // MARK: Table mechanisms

    /// Folding leg bracket: a plate under the top, a hinge and a leg socket that locks upright or folds flat.
    static func foldingTableHinge() -> ComponentDefinition {
        var b = ComponentBuilder("Folding Table Hinge", .tables, "Table Mechanisms", "Folding leg bracket: base plate, hinge and leg socket that locks upright or folds flat under the top.",
                                 frame: .plan)
        b.tags("table", "folding", "leg", "hinge", "bracket", "locking")
        b.aliases("folding leg bracket", "folding table leg hinge", "self locking leg brace", "fold down leg hinge", "1 1/4 in", "1 1/2 in", "32 mm")
        b.material("Finish Material", .zinc)
        b.length("Plate Length", CC.mm(100))
        b.length("Plate Width", CC.mm(50))
        b.length("Socket Size", CC.inch(1.25))
        b.length("Socket Length", CC.mm(60))
        b.flag("Folded", false, group: .placement)
        b.flag("Upright", false, formula: "not(Folded)")
        b.host([.top, .bottom], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight], offsetX: CC.inch(2), offsetY: CC.inch(2))
        b.clearance(.box(name: "Fold swing", x0: "-Socket Size / 2", x1: "Socket Size / 2", y0: "0 m", y1: "Socket Length + 0.6 m", z0: "-Socket Length - 0.6 m", z1: "0 m"))
        b.box("Base Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Length / 2", "Plate Length / 2"), z: ("-0.003 m", "0 m"))
        b.box("Hinge Cheek L", x: ("-Socket Size / 2 - 0.004 m", "-Socket Size / 2 - 0.001 m"), y: ("-0.02 m", "0.02 m"), z: ("-0.03 m", "-0.003 m"))
        b.box("Hinge Cheek R", x: ("Socket Size / 2 + 0.001 m", "Socket Size / 2 + 0.004 m"), y: ("-0.02 m", "0.02 m"), z: ("-0.03 m", "-0.003 m"))
        b.rodX("Pivot", y: "0 m", z: "-0.02 m", d: CX.mm(6), from: "-Socket Size / 2 - 0.006 m", to: "Socket Size / 2 + 0.006 m")
        b.shown("Upright") { b in
            b.cyl("Socket", axis: .z, center: ("0 m", "0 m"), radius: "Socket Size / 2", from: "-0.03 m - Socket Length", to: "-0.03 m", segments: 28)
            b.link("Lock Brace", plane: .yz, ("Plate Length / 2 - 0.005 m", "-0.004 m"), ("Socket Size / 2", "-0.03 m - Socket Length * 0.8"), at: "0 m", width: CX.mm(12), thickness: CX.mm(3))
        }
        b.shown("Folded") { $0.cyl("Socket (Folded)", axis: .y, center: ("0 m", "-0.02 m"), radius: "Socket Size / 2", from: "0.01 m", to: "0.01 m + Socket Length", segments: 28) }
        for y in ["-Plate Length * 0.38", "Plate Length * 0.38"] {
            for x in ["-Plate Width * 0.3", "Plate Width * 0.3"] { b.drill("Plate screw", x: x, y: y, diameter: CX.mm(3.5), depth: CX.mm(12)) }
        }
        b.outlines(x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Length / 2", "Plate Length / 2"), z: ("-0.03 m - Socket Length", "0 m"))
        b.symbol(.side, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("-0.02 m", "0 m"), radius: "Socket Length", startDegrees: "180", sweepDegrees: "-90"))
        b.type("Folding Table Hinge - 1 1/4\" Round", [:], cost: 6.5, model: "FTH-125")
        b.type("Folding Table Hinge - 1 1/2\" Round", ["Socket Size": CC.inch(1.5), "Plate Length": CC.mm(110)], cost: 7.5, model: "FTH-150")
        return b.build()
    }

    /// Drop-leaf support: a steel arm on a pivot plate that swings out under the raised leaf.
    static func dropLeafSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Drop-Leaf Support", .tables, "Table Mechanisms", "Swing-out steel arm under a drop leaf: closed along the apron, open under the raised leaf.",
                                 frame: .plan)
        b.tags("table", "drop leaf", "support", "bracket", "swing arm", "leaf")
        b.aliases("drop leaf bracket", "leaf support arm", "swing leaf support", "table leaf support", "10 in", "12 in", "14 in")
        b.material("Finish Material", .bronze)
        b.length("Arm Length", CC.inch(12))
        b.length("Arm Width", CC.mm(19))
        b.length("Arm Thickness", CC.mm(5))
        b.flag("Open", true, group: .placement)
        b.flag("Closed", false, formula: "not(Open)")
        b.number("Load Capacity", 50, unit: "lb", group: .data)
        b.host([.top, .rail], faces: [.bottom], align: .center)
        b.requires(.note("Put it under the fixed top near the leaf's hinge line; the arm reaches under the leaf."))
        b.clearance(.box(name: "Arm swing", x0: "-Arm Length", x1: "Arm Length", y0: "-Arm Length", y1: "0 m", z0: "-0.03 m", z1: "0 m"))
        b.plate("Pivot Plate", width: CX.mm(60), depth: CX.mm(40), radius: CX.mm(5), z: ("-0.004 m", "0 m"))
        b.cyl("Pivot", axis: .z, center: ("0 m", "0 m"), radius: CX.mm(6), from: "-0.02 m", to: "-0.004 m")
        b.shown("Open") { $0.box("Arm (Open)", x: ("-Arm Width / 2", "Arm Width / 2"), y: ("-Arm Length", "0.01 m"), z: ("-0.004 m - Arm Thickness", "-0.004 m")) }
        b.shown("Closed") { $0.box("Arm (Closed)", x: ("-0.01 m", "Arm Length"), y: ("-Arm Width / 2", "Arm Width / 2"), z: ("-0.004 m - Arm Thickness", "-0.004 m")) }
        b.drill("Plate screw", x: "-0.022 m", y: "0 m", diameter: CX.mm(3.5), depth: CX.mm(12))
        b.drill("Plate screw", x: "0.022 m", y: "0 m", diameter: CX.mm(3.5), depth: CX.mm(12))
        b.symbol(.face, [.coarse], .rect(("-Arm Width / 2", "-Arm Length"), ("Arm Width / 2", "0.01 m")))
        b.symbol(.face, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("0 m", "0 m"), radius: "Arm Length", startDegrees: "-90", sweepDegrees: "90"))
        b.symbol(.top, [.coarse], .rect(("-Arm Width / 2", "-0.004 m - Arm Thickness"), ("Arm Width / 2", "0 m")))
        for (l, cost) in [(10.0, 8.0), (12, 9.5), (14, 11)] {
            b.type("Drop-Leaf Support - \(Int(l))\"", ["Arm Length": CC.inch(l)], cost: cost, model: "DLS-\(Int(l))")
        }
        return b.build()
    }

    /// Table extension slide: a pair of telescoping three-part slides under the top; Extension opens them.
    static func extensionSlide() -> ComponentDefinition {
        var b = ComponentBuilder("Table Extension Slide", .tables, "Table Mechanisms", "Pair of telescoping three-part slides under an extending table's top.", frame: .plan)
        b.tags("table", "extension", "slide", "telescoping", "leaf", "dining")
        b.aliases("table slides", "extension table slides", "telescopic table runner", "equalizer slide", "28 in", "34 in", "40 in", "700 mm", "850 mm")
        b.material("Finish Material", .steel)
        b.length("Closed Length", CC.inch(28))
        b.length("Maximum Extension", CC.inch(20))
        b.length("Extension", 0, instance: true, group: .placement, min: 0)
        b.length("Slide Spacing", CC.inch(18), instance: true, group: .placement)
        b.length("Slide Width", CC.mm(45))
        b.length("Slide Height", CC.mm(30))
        b.number("Load Capacity", 110, unit: "lb", group: .data)
        b.host([.top], faces: [.bottom], align: .center)
        b.requires(.hostWidth(min: "Closed Length", max: nil))
        b.requires(.note("Extension is up to Maximum Extension; each half of the top moves half of it."))
        for (s, n) in [("-", "Front"), ("", "Back")] {
            let y = "\(s)(Slide Spacing / 2)"
            let yr = ("\(y) - Slide Width / 2", "\(y) + Slide Width / 2")
            b.box("\(n) Outer Left", x: ("-Closed Length / 2 - Extension / 2", "-Extension / 2 + 0.05 m"), y: yr, z: ("-Slide Height", "0 m"))
            b.box("\(n) Outer Right", x: ("Extension / 2 - 0.05 m", "Closed Length / 2 + Extension / 2"), y: yr, z: ("-Slide Height", "0 m"))
            b.box("\(n) Middle", x: ("-Closed Length / 2 + 0.08 m", "Closed Length / 2 - 0.08 m"), y: ("\(y) - Slide Width / 2 + 0.006 m", "\(y) + Slide Width / 2 - 0.006 m"),
                  z: ("-Slide Height + 0.004 m", "-0.004 m"))
            for x in ["-Closed Length / 2 - Extension / 2 + 0.05 m", "Closed Length / 2 + Extension / 2 - 0.05 m"] {
                b.drill("Slide screw", x: x, y: y, diameter: CX.mm(4), depth: CX.mm(14))
            }
        }
        b.outlines(x: ("-Closed Length / 2", "Closed Length / 2"), y: ("-Slide Spacing / 2 - Slide Width / 2", "Slide Spacing / 2 + Slide Width / 2"), z: ("-Slide Height", "0 m"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("-Closed Length / 2 - Maximum Extension / 2", "-Slide Spacing / 2"), ("Closed Length / 2 + Maximum Extension / 2", "Slide Spacing / 2")))
        for (l, e, cost) in [(28.0, 20.0, 45.0), (34, 24, 55), (40, 30, 65)] {
            b.type("Table Extension Slide - \(Int(l))\"", ["Closed Length": CC.inch(l), "Maximum Extension": CC.inch(e)], cost: cost, model: "TES-\(Int(l))",
                   description: "Extension slide pair, \(Int(l))\" closed, opens \(Int(e))\"")
        }
        return b.build()
    }

    /// Butterfly leaf: a self-storing leaf in two halves on a center hinge; stored upright under the top or unfolded flush.
    static func butterflyLeaf() -> ComponentDefinition {
        var b = ComponentBuilder("Butterfly Leaf Mechanism", .tables, "Table Mechanisms", "Self-storing butterfly leaf: two halves on a center hinge, stored upright under the top or unfolded flush.",
                                 frame: .plan)
        b.tags("table", "butterfly", "leaf", "self-storing", "extension", "dining")
        b.aliases("butterfly leaf", "self storing leaf", "folding table leaf", "butterfly extension", "18 in", "20 in", "24 in")
        b.material("Leaf Material", .walnut)
        b.material("Hardware Material", .steel)
        b.length("Leaf Width", CC.inch(18))
        b.length("Leaf Depth", CC.inch(38))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.flag("Unfolded", false, group: .placement)
        b.flag("Stored", false, formula: "not(Unfolded)")
        b.host([.top], faces: [.bottom], align: .center)
        b.requires(.hostHeight(min: "Leaf Depth", max: nil))
        b.requires(.note("Used with Table Extension Slides; the table opens by Leaf Width."))
        b.using("Leaf Material")
        b.shown("Unfolded") { $0.box("Leaf (Unfolded)", x: ("-Leaf Width / 2", "Leaf Width / 2"), y: ("-Leaf Depth / 2", "Leaf Depth / 2"), z: ("0 m", "Host Thickness")) }
        b.shown("Stored") { b in
            for s in ["-", ""] {
                b.box("Leaf Half (Stored)", x: ("\(s)(Host Thickness) - 0.001 m", "\(s)0.001 m"), y: ("-Leaf Depth / 2", "Leaf Depth / 2"), z: ("-Leaf Width / 2 - 0.01 m", "-0.01 m"))
            }
        }
        b.using("Hardware Material")
        for s in ["-", ""] {
            b.box("Hinge", x: ("-0.012 m", "0.012 m"), y: ("\(s)(Leaf Depth / 3) - 0.03 m", "\(s)(Leaf Depth / 3) + 0.03 m"), z: ("if(Unfolded, -0.004 m, -Leaf Width / 2 - 0.014 m)", "if(Unfolded, 0 m, -Leaf Width / 2 - 0.01 m)"))
            b.box("Pivot Bracket", x: ("-Host Thickness - 0.02 m", "Host Thickness + 0.02 m"), y: ("\(s)(Leaf Depth / 2) - 0.004 m", "\(s)(Leaf Depth / 2) + 0.004 m"), z: ("-0.05 m", "0 m"))
        }
        b.using(nil)
        b.symbol(.face, [.coarse], .rect(("-Leaf Width / 2", "-Leaf Depth / 2"), ("Leaf Width / 2", "Leaf Depth / 2")))
        b.symbol(.face, [.medium, .fine], dashed: true, .line(("0 m", "-Leaf Depth / 2"), ("0 m", "Leaf Depth / 2")))
        b.symbol(.top, [.coarse], .rect(("-Leaf Width / 2", "-Leaf Width / 2"), ("Leaf Width / 2", "Host Thickness")))
        for (w, cost) in [(18.0, 89.0), (24, 109)] {
            b.type("Butterfly Leaf Mechanism - \(Int(w))\" Leaf", ["Leaf Width": CC.inch(w)], cost: cost, model: "BLM-\(Int(w))")
        }
        return b.build()
    }

    // MARK: Cable management

    /// Desk grommet: a liner through the top and a cap with a cable slot; the bore is a void in the top.
    static func deskGrommet() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Cable Grommet", .tables, "Cable Management", "Round desk grommet: liner through the top and a cap with a cable slot.", frame: .plan)
        b.tags("desk", "grommet", "cable", "wire", "hole", "cutout")
        b.aliases("cable grommet", "desk grommet", "wire hole cover", "cable port", "60 mm", "80 mm", "100 mm", "2 3/8 in", "3 1/8 in")
        b.material("Finish Material", .blackPlastic)
        b.length("Hole Diameter", CC.mm(60))
        b.length("Cap Diameter", 0, formula: "Hole Diameter + 0.01 m")
        b.length("Cap Thickness", CC.mm(3))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.host([.top, .shelf], faces: [.top], align: .topRight, alignments: [.topRight, .topLeft, .center], offsetX: CC.inch(4), offsetY: CC.inch(3))
        b.requires(.hostThickness(min: "0.012 m", max: "0.05 m"))
        b.drill("Grommet hole", x: "0 m", y: "0 m", diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        b.cyl("Host Cutout", axis: .z, center: ("0 m", "0 m"), radius: "Hole Diameter / 2", from: "-Host Thickness", to: "0 m", segments: 32, void: true)
        b.revolve("Liner", profile: ComponentKit.points([("Hole Diameter / 2 - 0.0025 m", "0 m"), ("Hole Diameter / 2", "0 m"), ("Hole Diameter / 2", "Host Thickness"),
                                                         ("Hole Diameter / 2 - 0.0025 m", "Host Thickness")]), base: "-Host Thickness")
        b.revolve("Cap", profile: ComponentKit.points([("Hole Diameter / 2 - 0.0025 m", "0 m"), ("Cap Diameter / 2", "0 m"), ("Cap Diameter / 2 - 0.001 m", "Cap Thickness"),
                                                       ("Hole Diameter / 2 - 0.0025 m", "Cap Thickness")]), base: "0 m", startDegrees: "20", endDegrees: "340")
        b.box("Cable Slot Cover", x: ("-Hole Diameter / 2 + 0.003 m", "Hole Diameter / 2 - 0.003 m"), y: ("-Hole Diameter * 0.2", "Hole Diameter / 2 - 0.004 m"), z: ("0.0005 m", "Cap Thickness"))
        b.symbol(.face, [.coarse, .medium, .fine], .circle(("0 m", "0 m"), "Cap Diameter / 2"), .circle(("0 m", "0 m"), "Hole Diameter / 2"))
        b.symbol(.top, [.coarse], .rect(("-Cap Diameter / 2", "-Host Thickness"), ("Cap Diameter / 2", "Cap Thickness")))
        for (d, cost) in [(60.0, 3.0), (80, 4.0), (100, 5.5)] {
            b.type("Desk Cable Grommet - \(Int(d)) mm", ["Hole Diameter": CC.mm(d)], cost: cost, model: "DCG-\(Int(d))")
        }
        return b.build()
    }

    /// Under-desk cable tray: a perforated steel trough on two brackets.
    static func cableTray() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Cable Tray", .tables, "Cable Management", "Under-desk cable trough on two brackets, for power strips and cable slack.", frame: .plan)
        b.tags("desk", "cable", "tray", "trough", "wire management", "under desk")
        b.aliases("cable tray", "under desk cable tray", "wire tray", "cable trough", "24 in", "36 in", "48 in", "600 mm", "900 mm", "1200 mm")
        b.material("Finish Material", .matteBlack)
        b.length("Tray Length", CC.inch(36))
        b.length("Tray Width", CC.mm(120))
        b.length("Tray Depth", CC.mm(100))
        b.length("Drop", CC.mm(20))
        b.host([.top], faces: [.bottom], align: .top, alignments: [.top, .center], offsetY: CC.inch(2))
        b.requires(.hostWidth(min: "Tray Length", max: nil))
        let z0 = "-Drop - Tray Depth", z1 = "-Drop"
        b.box("Bottom", x: ("-Tray Length / 2", "Tray Length / 2"), y: ("-Tray Width / 2", "Tray Width / 2"), z: (z0, "\(z0) + 0.0015 m"))
        b.box("Front Wall", x: ("-Tray Length / 2", "Tray Length / 2"), y: ("-Tray Width / 2", "-Tray Width / 2 + 0.0015 m"), z: (z0, "\(z0) + Tray Depth * 0.6"))
        b.box("Back Wall", x: ("-Tray Length / 2", "Tray Length / 2"), y: ("Tray Width / 2 - 0.0015 m", "Tray Width / 2"), z: (z0, z1))
        for s in ["-", ""] {
            let x = "\(s)(Tray Length / 2 - 0.08 m)"
            b.box("Bracket", x: ("\(x) - 0.015 m", "\(x) + 0.015 m"), y: ("Tray Width / 2 - 0.002 m", "Tray Width / 2 + 0.002 m"), z: (z0, "0 m"))
            b.box("Bracket Tab", x: ("\(x) - 0.015 m", "\(x) + 0.015 m"), y: ("Tray Width / 2 - 0.03 m", "Tray Width / 2 + 0.002 m"), z: ("-0.002 m", "0 m"))
            b.drill("Bracket screw", x: x, y: "Tray Width / 2 - 0.015 m", diameter: CX.mm(4), depth: CX.mm(14))
        }
        b.outlines(x: ("-Tray Length / 2", "Tray Length / 2"), y: ("-Tray Width / 2", "Tray Width / 2"), z: (z0, "0 m"))
        for (l, cost) in [(24.0, 24.0), (36, 29), (48, 35)] {
            b.type("Desk Cable Tray - \(Int(l))\"", ["Tray Length": CC.inch(l)], cost: cost, model: "DCT-\(Int(l))")
        }
        return b.build()
    }

    /// Adhesive under-desk cable raceway: a U channel with a snap lid.
    static func cableRaceway() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Cable Raceway", .tables, "Cable Management", "Under-desk cable channel: a U raceway with a snap lid, screwed or taped under the top.", frame: .plan)
        b.tags("desk", "cable", "channel", "raceway", "wire management", "under desk")
        b.aliases("cable channel", "cable raceway", "wire channel", "cord cover", "16 in", "24 in", "40 in")
        b.material("Finish Material", .whitePlastic)
        b.length("Channel Length", CC.inch(16))
        b.length("Channel Width", CC.mm(30))
        b.length("Channel Height", CC.mm(16))
        b.length("Wall", CC.mm(1.5), group: .manufacturing)
        b.host([.top, .bottom, .rail], faces: [.bottom], align: .top, alignments: [.top, .center, .full])
        b.profileAlongX("Channel", profile: ComponentKit.points([("-Channel Width / 2", "0 m"), ("Channel Width / 2", "0 m"), ("Channel Width / 2", "-Channel Height"),
                                                                 ("Channel Width / 2 - Wall", "-Channel Height"), ("Channel Width / 2 - Wall", "-Wall"), ("-Channel Width / 2 + Wall", "-Wall"),
                                                                 ("-Channel Width / 2 + Wall", "-Channel Height"), ("-Channel Width / 2", "-Channel Height")]),
                        from: "-Channel Length / 2", to: "Channel Length / 2")
        b.box("Lid", x: ("-Channel Length / 2", "Channel Length / 2"), y: ("-Channel Width / 2 - 0.001 m", "Channel Width / 2 + 0.001 m"), z: ("-Channel Height - Wall", "-Channel Height"))
        b.drill("Channel screw", x: "-Channel Length / 2 + 0.05 m", y: "0 m", diameter: CX.mm(3), depth: CX.mm(10))
        b.drill("Channel screw", x: "Channel Length / 2 - 0.05 m", y: "0 m", diameter: CX.mm(3), depth: CX.mm(10))
        b.outlines(x: ("-Channel Length / 2", "Channel Length / 2"), y: ("-Channel Width / 2", "Channel Width / 2"), z: ("-Channel Height - Wall", "0 m"))
        for (l, cost) in [(16.0, 6.0), (24, 8), (40, 12)] {
            b.type("Desk Cable Raceway - \(Int(l))\"", ["Channel Length": CC.inch(l)], cost: cost, model: "DCR-\(Int(l))")
        }
        return b.build()
    }

    /// Adhesive or screw-on cable clip.
    static func cableClip() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Cable Clip", .tables, "Cable Management", "Screw-on or adhesive clip that holds one to three cables under or behind a desk.", frame: .plan)
        b.tags("desk", "cable", "clip", "cord", "wire management")
        b.aliases("cable clip", "cord clip", "wire clip", "adhesive cable holder", "1 slot", "3 slot")
        b.material("Finish Material", .blackPlastic)
        b.length("Base Length", CC.mm(30))
        b.length("Slot Diameter", CC.mm(8))
        b.number("Slots", 1, group: .dimensions)
        b.host([.top, .bottom, .rail], faces: [.bottom], align: .center)
        b.box("Base", x: ("-Base Length / 2", "Base Length / 2"), y: ("-0.01 m", "0.01 m"), z: ("-0.002 m", "0 m"))
        for k in 1...3 {
            let v: String? = k == 1 ? nil : "Show Slot \(k)"
            if let v { b.countFlag(v, "Slots >= \(k)") }
            let x = "(\(k - 1) - (Slots - 1) / 2) * (Slot Diameter + 0.003 m)"
            b.shown(v) { $0.revolve("Clip \(k)", profile: ComponentKit.points([("Slot Diameter / 2", "-0.006 m"), ("Slot Diameter / 2 + 0.0015 m", "-0.006 m"),
                                                                               ("Slot Diameter / 2 + 0.0015 m", "0.006 m"), ("Slot Diameter / 2", "0.006 m")]),
                                       plane: .yz, axis: ("0 m", "-0.002 m - Slot Diameter / 2"), base: "\(x) - 0.006 m", startDegrees: "-60", endDegrees: "240") }
        }
        b.drill("Clip screw", x: "-Base Length / 2 + 0.004 m", y: "0 m", diameter: CX.mm(2.5), depth: CX.mm(8))
        b.outlines(x: ("-Base Length / 2", "Base Length / 2"), y: ("-0.01 m", "0.01 m"), z: ("-0.0035 m - Slot Diameter", "0 m"))
        b.type("Desk Cable Clip - 1 Slot", [:], numbers: ["Slots": 1], cost: 0.5, model: "DCC-1")
        b.type("Desk Cable Clip - 3 Slot", ["Base Length": CC.mm(40)], numbers: ["Slots": 3], cost: 0.9, model: "DCC-3")
        return b.build()
    }

    /// Under-desk wire cable basket.
    static func cableBasket() -> ComponentDefinition {
        var b = ComponentBuilder("Under-Desk Cable Basket", .tables, "Cable Management", "Wire basket hung under the top for power strips, adapters and cable slack.", frame: .plan)
        b.tags("desk", "cable", "basket", "wire", "under desk", "power strip")
        b.aliases("cable basket", "wire cable basket", "under desk wire basket", "cable management basket", "24 in", "32 in", "600 mm", "800 mm")
        b.material("Finish Material", .matteBlack)
        b.length("Basket Length", CC.inch(24))
        b.length("Basket Width", CC.mm(150))
        b.length("Basket Depth", CC.mm(110))
        b.length("Wire Diameter", CC.mm(4))
        b.host([.top], faces: [.bottom], align: .top, alignments: [.top, .center], offsetY: CC.inch(2))
        b.requires(.hostWidth(min: "Basket Length", max: nil))
        b.basket("Basket", x: ("-Basket Length / 2", "Basket Length / 2"), y: ("-Basket Width / 2", "Basket Width / 2"), z: ("-Basket Depth - 0.01 m", "-0.01 m"), wire: "Wire Diameter")
        for s in ["-", ""] {
            let x = "\(s)(Basket Length / 2 - 0.03 m)"
            b.box("Hanger", x: ("\(x) - 0.01 m", "\(x) + 0.01 m"), y: ("Basket Width / 2 - 0.02 m", "Basket Width / 2"), z: ("-0.012 m", "0 m"))
            b.drill("Hanger screw", x: x, y: "Basket Width / 2 - 0.01 m", diameter: CX.mm(4), depth: CX.mm(14))
        }
        b.outlines(x: ("-Basket Length / 2", "Basket Length / 2"), y: ("-Basket Width / 2", "Basket Width / 2"), z: ("-Basket Depth - 0.01 m", "0 m"))
        for (l, cost) in [(24.0, 22.0), (32, 27)] {
            b.type("Under-Desk Cable Basket - \(Int(l))\"", ["Basket Length": CC.inch(l)], cost: cost, model: "UCB-\(Int(l))")
        }
        return b.build()
    }

    // MARK: Ergonomics

    /// Monitor arm: a clamp on the top's back edge, a pole, one or two articulated arms with VESA plates.
    static func monitorArm() -> ComponentDefinition {
        var b = ComponentBuilder("Monitor Arm", .tables, "Ergonomics", "Desk-clamp monitor arm: pole, articulated arm and VESA 75/100 plate; single or dual.", frame: .plan)
        b.tags("desk", "monitor", "arm", "vesa", "screen", "clamp")
        b.aliases("monitor mount", "screen arm", "dual monitor arm", "gas spring monitor arm", "vesa 100", "vesa 75", "desk clamp arm")
        b.material("Finish Material", .matteBlack)
        b.length("Pole Height", CC.mm(450))
        b.length("Arm Reach", CC.mm(420), instance: true, group: .placement, max: CC.mm(520))
        b.length("Arm Height", CC.mm(320), instance: true, group: .placement)
        b.length("Clamp Opening", CC.mm(85))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.flag("Dual", false, instance: false, group: .dimensions)
        b.flag("Single", false, formula: "not(Dual)")
        b.number("Load per Arm", 17.6, unit: "lb", group: .data)
        b.text("VESA Pattern", "75 x 75, 100 x 100", group: .data)
        b.host([.top], faces: [.top], align: .top, alignments: [.top, .topLeft, .topRight])
        b.requires(.hostThickness(min: "0.012 m", max: "Clamp Opening"))
        b.clearance(.box(name: "Arm swing", x0: "-Arm Reach", x1: "Arm Reach", y0: "-Arm Reach", y1: "0.05 m", z0: "0 m", z1: "Pole Height"))
        // Clamp: top plate, back plate down the edge, lower jaw and screw.
        b.box("Clamp Top", x: ("-0.04 m", "0.04 m"), y: ("-0.09 m", "0.012 m"), z: ("0 m", "0.01 m"))
        b.box("Clamp Back", x: ("-0.03 m", "0.03 m"), y: ("0.002 m", "0.012 m"), z: ("-Host Thickness - 0.025 m", "0 m"))
        b.box("Clamp Jaw", x: ("-0.03 m", "0.03 m"), y: ("-0.06 m", "0.012 m"), z: ("-Host Thickness - 0.012 m", "-Host Thickness"))
        b.rodZ("Clamp Screw", x: "0 m", y: "-0.035 m", d: CX.mm(10), from: "-Host Thickness - 0.04 m", to: "-Host Thickness - 0.012 m")
        b.cyl("Pole", axis: .z, center: ("0 m", "-0.04 m"), radius: "0.016 m", from: "0.01 m", to: "Pole Height", segments: 28)
        for (side, sign) in [("Single", "0"), ("Dual", "-1"), ("Dual", "1")] {
            let tag = sign == "0" ? "" : (sign == "-1" ? " L" : " R")
            // Two links: from the pole out (diagonal on dual) to the elbow, then to the head.
            let ex = sign == "0" ? "0.12 m" : "\(sign) * Arm Reach * 0.45", ey = sign == "0" ? "-0.04 m - Arm Reach * 0.55" : "-0.04 m - Arm Reach * 0.35"
            let hx = sign == "0" ? "0 m" : "\(sign) * Arm Reach * 0.75", hy = "-0.04 m - Arm Reach"
            b.shown(side) { b in
                b.link("Upper Arm\(tag)", plane: .xy, ("0 m", "-0.04 m"), (ex, ey), at: "Arm Height", width: CX.mm(30), thickness: CX.mm(28))
                b.link("Forearm\(tag)", plane: .xy, (ex, ey), (hx, hy), at: "Arm Height", width: CX.mm(26), thickness: CX.mm(24))
                b.cyl("Elbow\(tag)", axis: .z, center: (ex, ey), radius: "0.018 m", from: "Arm Height - 0.016 m", to: "Arm Height + 0.016 m")
                b.box("Tilt Head\(tag)", x: ("\(hx) - 0.02 m", "\(hx) + 0.02 m"), y: ("\(hy) - 0.03 m", "\(hy) + 0.01 m"), z: ("Arm Height - 0.04 m", "Arm Height + 0.02 m"))
                b.box("VESA Plate\(tag)", x: ("\(hx) - 0.06 m", "\(hx) + 0.06 m"), y: ("\(hy) - 0.036 m", "\(hy) - 0.03 m"), z: ("Arm Height - 0.07 m", "Arm Height + 0.05 m"))
            }
        }
        b.drill("Grommet mount (option)", x: "0 m", y: "-0.04 m", diameter: CX.mm(12), depth: "Host Thickness", through: true)
        b.symbol(.face, [.coarse], .rect(("-0.04 m", "-0.09 m"), ("0.04 m", "0.012 m")), .line(("0 m", "-0.04 m"), ("0 m", "-0.04 m - Arm Reach")))
        b.symbol(.face, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("0 m", "-0.04 m"), radius: "Arm Reach", startDegrees: "200", sweepDegrees: "140"))
        b.symbol(.top, [.coarse], .line(("0 m", "0 m"), ("0 m", "Pole Height")), .rect(("-0.06 m", "Arm Height - 0.07 m"), ("0.06 m", "Arm Height + 0.05 m")))
        b.type("Monitor Arm - Single", [:], cost: 89, model: "MA-S")
        b.type("Monitor Arm - Dual", ["Arm Reach": CC.mm(480)], flags: ["Dual": true], cost: 149, model: "MA-D")
        b.type("Monitor Arm - Single Gas Spring", ["Pole Height": CC.mm(380), "Arm Reach": CC.mm(500)], numbers: ["Load per Arm": 19.8], cost: 129, model: "MA-SG")
        return b.build()
    }

    /// Under-desk keyboard tray on a track: platform and mouse wing that slide out and swivel.
    static func keyboardTray() -> ComponentDefinition {
        var b = ComponentBuilder("Keyboard Tray", .tables, "Ergonomics", "Under-desk keyboard platform with mouse wing on a sliding track.", frame: .plan)
        b.tags("desk", "keyboard", "tray", "ergonomic", "pull-out", "mouse")
        b.aliases("keyboard platform", "pull out keyboard tray", "under desk keyboard drawer", "keyboard shelf", "17 in track", "22 in track")
        b.material("Platform Material", .blackPlastic)
        b.material("Track Material", .steel)
        b.length("Track Length", CC.inch(17))
        b.length("Platform Width", CC.inch(26))
        b.length("Platform Depth", CC.inch(10))
        b.length("Drop", CC.mm(60))
        b.length("Pull Out", CC.mm(300), instance: true, group: .placement, min: 0)
        b.host([.top], faces: [.bottom], align: .bottom, alignments: [.bottom, .center])
        b.requires(.hostHeight(min: "Track Length", max: nil))
        b.clearance(.box(name: "Knee space", x0: "-Platform Width / 2", x1: "Platform Width / 2", y0: "Track Length - 0.09 m - Pull Out - Platform Depth", y1: "Track Length", z0: "-Drop - 0.03 m", z1: "0 m"))
        b.using("Track Material")
        b.box("Track", x: ("-0.04 m", "0.04 m"), y: ("0 m", "Track Length"), z: ("-0.02 m", "0 m"))
        b.box("Carriage", x: ("-0.03 m", "0.03 m"), y: ("Track Length - 0.12 m - Pull Out", "Track Length - Pull Out"), z: ("-Drop", "-0.02 m"))
        b.using("Platform Material")
        b.roundedBar("Platform", center: ("-0.04 m", "Track Length - 0.09 m - Pull Out - Platform Depth / 2"), width: "Platform Width - 0.1 m", height: "Platform Depth", radius: "0.015 m", from: "-Drop - 0.015 m", to: "-Drop")
        b.roundedBar("Mouse Wing", center: ("Platform Width / 2 - 0.05 m", "Track Length - 0.09 m - Pull Out - Platform Depth / 2"), width: "0.2 m", height: "Platform Depth * 0.9", radius: "0.015 m",
                     from: "-Drop - 0.015 m", to: "-Drop - 0.003 m")
        b.box("Wrist Rest", x: ("-Platform Width / 2 + 0.01 m", "Platform Width / 2 - 0.15 m"), y: ("Track Length - 0.09 m - Pull Out - Platform Depth", "Track Length - 0.03 m - Pull Out - Platform Depth"), z: ("-Drop", "-Drop + 0.015 m"))
        b.using(nil)
        for y in ["0.03 m", "Track Length / 2", "Track Length - 0.03 m"] { b.drill("Track screw", x: "0 m", y: y, diameter: CX.mm(4), depth: CX.mm(16)) }
        b.outlines(x: ("-Platform Width / 2", "Platform Width / 2"), y: ("Track Length - 0.09 m - Pull Out - Platform Depth", "Track Length"), z: ("-Drop - 0.015 m", "0 m"))
        b.type("Keyboard Tray - 17\" Track", [:], cost: 119, model: "KT-17")
        b.type("Keyboard Tray - 22\" Track", ["Track Length": CC.inch(22), "Platform Width": CC.inch(28)], cost: 139, model: "KT-22")
        return b.build()
    }

    /// Under-desk CPU holder: a sliding hanger rail with an adjustable cradle.
    static func cpuHolder() -> ComponentDefinition {
        var b = ComponentBuilder("CPU Holder", .tables, "Ergonomics", "Under-desk computer holder: a sliding, swiveling hanger with an adjustable cradle.", frame: .plan)
        b.tags("desk", "cpu", "computer", "tower", "holder", "under desk")
        b.aliases("cpu holder", "pc tower mount", "computer tower holder", "under desk cpu mount", "adjustable cpu cradle")
        b.material("Finish Material", .matteBlack)
        b.length("CPU Width", CC.inch(8), instance: true, group: .placement, min: CC.inch(3), max: CC.inch(8.5))
        b.length("CPU Height", CC.inch(17), instance: true, group: .placement, max: CC.inch(21))
        b.length("CPU Depth", CC.inch(16))
        b.length("Rail Length", CC.mm(300))
        b.number("Load Capacity", 44, unit: "lb", group: .data)
        b.host([.top], faces: [.bottom], align: .bottomRight, alignments: [.bottomRight, .bottomLeft])
        b.clearance(.box(name: "CPU", x0: "-CPU Width / 2", x1: "CPU Width / 2", y0: "-CPU Depth / 2", y1: "CPU Depth / 2", z0: "-CPU Height - 0.04 m", z1: "-0.04 m"))
        b.box("Rail", x: ("-0.025 m", "0.025 m"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("-0.015 m", "0 m"))
        b.cyl("Swivel", axis: .z, center: ("0 m", "0 m"), radius: "0.025 m", from: "-0.04 m", to: "-0.015 m")
        b.box("Top Bar", x: ("-CPU Width / 2 - 0.01 m", "CPU Width / 2 + 0.01 m"), y: ("-0.02 m", "0.02 m"), z: ("-0.05 m", "-0.04 m"))
        for s in ["-", ""] {
            b.box("Side Strap", x: ("\(s)(CPU Width / 2) - 0.004 m", "\(s)(CPU Width / 2) + 0.004 m"), y: ("-0.02 m", "0.02 m"), z: ("-CPU Height - 0.06 m", "-0.04 m"))
            b.box("Cradle Arm", x: ("-CPU Width / 2 - 0.004 m", "CPU Width / 2 + 0.004 m"), y: ("\(s)(CPU Depth / 2 - 0.03 m) - 0.015 m", "\(s)(CPU Depth / 2 - 0.03 m) + 0.015 m"),
                  z: ("-CPU Height - 0.06 m", "-CPU Height - 0.05 m"))
        }
        b.box("Cradle Spine", x: ("-0.015 m", "0.015 m"), y: ("-CPU Depth / 2 + 0.03 m", "CPU Depth / 2 - 0.03 m"), z: ("-CPU Height - 0.06 m", "-CPU Height - 0.05 m"))
        for y in ["-Rail Length / 2 + 0.03 m", "Rail Length / 2 - 0.03 m"] { b.drill("Rail screw", x: "0 m", y: y, diameter: CX.mm(4), depth: CX.mm(16)) }
        b.outlines(x: ("-CPU Width / 2", "CPU Width / 2"), y: ("-CPU Depth / 2", "CPU Depth / 2"), z: ("-CPU Height - 0.06 m", "0 m"))
        b.type("CPU Holder - Adjustable", [:], cost: 39, model: "CPU-ADJ")
        b.type("CPU Holder - Compact", ["CPU Width": CC.inch(4), "CPU Height": CC.inch(12), "CPU Depth": CC.inch(12)], numbers: ["Load Capacity": 22], cost: 29, model: "CPU-CMP")
        return b.build()
    }

    /// Slim under-desk drawer on side-mount slides with its hanging brackets.
    static func deskDrawer() -> ComponentDefinition {
        var b = ComponentBuilder("Under-Desk Drawer", .tables, "Ergonomics", "Slim drawer hung under the top on side-mount slides: box, front and hanging brackets.", frame: .plan)
        b.tags("desk", "drawer", "pencil drawer", "under desk", "storage", "slide")
        b.aliases("desk drawer", "pencil drawer", "under desk drawer", "slim drawer", "20 in", "24 in", "500 mm", "600 mm")
        b.material("Box Material", .whitePlastic)
        b.material("Front Material", .oak)
        b.material("Slide Material", .steel)
        b.length("Drawer Width", CC.inch(20))
        b.length("Drawer Depth", CC.inch(14))
        b.length("Drawer Height", CC.inch(3))
        b.length("Pull Out", 0, instance: true, group: .placement, min: 0)
        b.host([.top], faces: [.bottom], align: .bottom, alignments: [.bottom, .bottomLeft, .bottomRight])
        b.requires(.hostWidth(min: "Drawer Width + 0.06 m", max: nil))
        b.clearance(.box(name: "Drawer travel", x0: "-Drawer Width / 2", x1: "Drawer Width / 2", y0: "-Drawer Depth", y1: "0 m", z0: "-Drawer Height - 0.01 m", z1: "0 m"))
        let y0 = "-Pull Out", y1 = "Drawer Depth - Pull Out"
        b.using("Slide Material")
        for s in ["-", ""] {
            b.box("Hanger", x: ("\(s)(Drawer Width / 2 + 0.013 m) - 0.015 m", "\(s)(Drawer Width / 2 + 0.013 m) + 0.015 m"), y: ("0 m", "Drawer Depth"), z: ("-Drawer Height - 0.005 m", "0 m"))
            b.drill("Hanger screw", x: "\(s)(Drawer Width / 2 + 0.013 m)", y: "0.05 m", diameter: CX.mm(4), depth: CX.mm(14))
            b.drill("Hanger screw", x: "\(s)(Drawer Width / 2 + 0.013 m)", y: "Drawer Depth - 0.05 m", diameter: CX.mm(4), depth: CX.mm(14))
        }
        b.using("Box Material")
        b.tray("Box", x: ("-Drawer Width / 2", "Drawer Width / 2"), y: (y0, y1), z: ("-Drawer Height", "-0.008 m"), wall: CX.mm(8), floor: CX.mm(4))
        b.using("Front Material")
        b.box("Front", x: ("-Drawer Width / 2 - 0.02 m", "Drawer Width / 2 + 0.02 m"), y: ("\(y0) - 0.019 m", y0), z: ("-Drawer Height - 0.006 m", "-0.004 m"))
        b.using(nil)
        b.outlines(x: ("-Drawer Width / 2 - 0.02 m", "Drawer Width / 2 + 0.02 m"), y: ("-0.019 m", "Drawer Depth"), z: ("-Drawer Height - 0.006 m", "0 m"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("-Drawer Width / 2", "-Drawer Depth"), ("Drawer Width / 2", "0 m")))
        for (w, cost) in [(20.0, 49.0), (24, 55)] {
            b.type("Under-Desk Drawer - \(Int(w))\"", ["Drawer Width": CC.inch(w)], cost: cost, model: "UDD-\(Int(w))")
        }
        return b.build()
    }

    // MARK: Panels and screens

    /// Privacy screen clamped to the top's back edge.
    static func privacyPanel() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Privacy Panel", .tables, "Panels & Screens", "Privacy screen on two clamps at the top's back edge: felt, fabric or acrylic.", frame: .plan)
        b.tags("desk", "privacy", "screen", "panel", "acoustic", "partition")
        b.aliases("privacy screen", "desk screen", "acoustic desk panel", "clamp on desk divider", "48 in", "60 in", "18 in high")
        b.material("Panel Material", .felt)
        b.material("Clamp Material", .aluminum)
        b.length("Panel Width", CC.inch(48))
        b.length("Panel Height", CC.inch(18))
        b.length("Panel Thickness", CC.mm(12))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.host([.top], faces: [.top], align: .top, alignments: [.top, .bottom, .left, .right])
        b.requires(.hostWidth(min: "Panel Width", max: nil))
        b.using("Panel Material")
        b.box("Panel", x: ("-Panel Width / 2", "Panel Width / 2"), y: ("0 m", "Panel Thickness"), z: ("-0.05 m", "Panel Height"))
        b.using("Clamp Material")
        for s in ["-", ""] {
            let x = "\(s)(Panel Width / 2 - 0.15 m)"
            b.box("Clamp", x: ("\(x) - 0.025 m", "\(x) + 0.025 m"), y: ("-0.04 m", "Panel Thickness + 0.006 m"), z: ("0 m", "0.04 m"))
            b.box("Clamp Jaw", x: ("\(x) - 0.025 m", "\(x) + 0.025 m"), y: ("-0.04 m", "Panel Thickness + 0.006 m"), z: ("-Host Thickness - 0.01 m", "-Host Thickness"))
            b.box("Clamp Back", x: ("\(x) - 0.025 m", "\(x) + 0.025 m"), y: ("Panel Thickness", "Panel Thickness + 0.006 m"), z: ("-Host Thickness - 0.01 m", "0.04 m"))
        }
        b.using(nil)
        b.outlines(x: ("-Panel Width / 2", "Panel Width / 2"), y: ("-0.04 m", "Panel Thickness + 0.006 m"), z: ("-Host Thickness - 0.01 m", "Panel Height"))
        b.type("Desk Privacy Panel - 48\" x 18\" Felt", [:], cost: 129, model: "DPP-4818F")
        b.type("Desk Privacy Panel - 60\" x 18\" Felt", ["Panel Width": CC.inch(60)], cost: 149, model: "DPP-6018F")
        b.type("Desk Privacy Panel - 48\" x 24\" Acrylic", ["Panel Height": CC.inch(24), "Panel Thickness": CC.mm(6)], cost: 119, model: "DPP-4824A")
        return b.build()
    }

    /// Modesty panel: a panel hung under the top between the legs, at the front or back.
    static func modestyPanel() -> ComponentDefinition {
        var b = ComponentBuilder("Modesty Panel", .tables, "Panels & Screens", "Panel hung under the top between the legs, on two angle brackets.", frame: .plan)
        b.tags("desk", "modesty", "panel", "screen", "under desk", "privacy")
        b.aliases("modesty screen", "desk front panel", "knee panel", "under desk panel", "48 in", "60 in", "72 in")
        b.material("Panel Material", ComponentFinish("Steel - Perforated Black", .metal, RGBColor(hex: 0x303134)))
        b.material("Bracket Material", .matteBlack)
        b.length("Panel Width", CC.inch(44))
        b.length("Panel Drop", CC.inch(14))
        b.length("Panel Thickness", CC.mm(2))
        b.length("Setback", CC.mm(60), instance: true, group: .placement)
        b.host([.top], faces: [.bottom], align: .top, alignments: [.top, .bottom])
        b.requires(.hostWidth(min: "Panel Width + 0.1 m", max: nil))
        b.using("Panel Material")
        b.box("Panel", x: ("-Panel Width / 2", "Panel Width / 2"), y: ("-Panel Thickness / 2", "Panel Thickness / 2"), z: ("-0.03 m - Panel Drop", "-0.03 m"))
        b.box("Top Flange", x: ("-Panel Width / 2", "Panel Width / 2"), y: ("-0.012 m", "Panel Thickness / 2"), z: ("-0.032 m", "-0.03 m"))
        b.using("Bracket Material")
        for s in ["-", ""] {
            let x = "\(s)(Panel Width / 2 - 0.1 m)"
            b.box("Bracket", x: ("\(x) - 0.02 m", "\(x) + 0.02 m"), y: ("Panel Thickness / 2", "Panel Thickness / 2 + 0.003 m"), z: ("-0.07 m", "0 m"))
            b.box("Bracket Tab", x: ("\(x) - 0.02 m", "\(x) + 0.02 m"), y: ("Panel Thickness / 2", "Panel Thickness / 2 + 0.04 m"), z: ("-0.003 m", "0 m"))
            b.drill("Bracket screw", x: x, y: "0.025 m", diameter: CX.mm(4), depth: CX.mm(14))
        }
        b.using(nil)
        b.outlines(x: ("-Panel Width / 2", "Panel Width / 2"), y: ("-0.012 m", "0.04 m"), z: ("-0.03 m - Panel Drop", "0 m"))
        for (w, cost) in [(44.0, 59.0), (56, 69), (68, 79)] {
            b.type("Modesty Panel - \(Int(w + 4))\" Desk", ["Panel Width": CC.inch(w)], cost: cost, model: "MP-\(Int(w + 4))")
        }
        return b.build()
    }

    /// Benching divider: a screen on the centre line between two face-to-face desks, with an accessory rail.
    static func deskDivider() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Divider", .tables, "Panels & Screens", "Benching divider between face-to-face desks: framed screen with an accessory rail.", frame: .plan)
        b.tags("desk", "divider", "benching", "screen", "partition", "office")
        b.aliases("desk partition", "benching screen", "desk separator", "office divider", "48 in", "60 in", "24 in high")
        b.material("Panel Material", .fabric)
        b.material("Frame Material", .aluminum)
        b.length("Divider Width", CC.inch(60))
        b.length("Divider Height", CC.inch(24))
        b.length("Panel Thickness", CC.mm(25))
        b.flag("Accessory Rail", true, group: .constraints)
        b.host([.top], faces: [.top], align: .center, alignments: [.center, .top])
        b.requires(.hostWidth(min: "Divider Width", max: nil))
        b.using("Panel Material")
        b.box("Panel", x: ("-Divider Width / 2 + 0.015 m", "Divider Width / 2 - 0.015 m"), y: ("-Panel Thickness / 2", "Panel Thickness / 2"), z: ("0.06 m", "Divider Height - 0.015 m"))
        b.using("Frame Material")
        for s in ["-", ""] {
            b.box("Frame Post", x: ("\(s)(Divider Width / 2) - 0.015 m", "\(s)(Divider Width / 2) + 0.015 m"), y: ("-Panel Thickness / 2", "Panel Thickness / 2"), z: ("0 m", "Divider Height"))
            b.box("Foot", x: ("\(s)(Divider Width / 2 - 0.2 m) - 0.03 m", "\(s)(Divider Width / 2 - 0.2 m) + 0.03 m"), y: ("-0.06 m", "0.06 m"), z: ("0 m", "0.01 m"))
            b.box("Foot Post", x: ("\(s)(Divider Width / 2 - 0.2 m) - 0.012 m", "\(s)(Divider Width / 2 - 0.2 m) + 0.012 m"), y: ("-0.01 m", "0.01 m"), z: ("0.01 m", "0.06 m"))
        }
        b.box("Frame Top", x: ("-Divider Width / 2", "Divider Width / 2"), y: ("-Panel Thickness / 2", "Panel Thickness / 2"), z: ("Divider Height - 0.015 m", "Divider Height"))
        b.box("Frame Bottom", x: ("-Divider Width / 2", "Divider Width / 2"), y: ("-Panel Thickness / 2", "Panel Thickness / 2"), z: ("0.045 m", "0.06 m"))
        b.shown("Accessory Rail") { $0.box("Accessory Rail", x: ("-Divider Width / 2 + 0.05 m", "Divider Width / 2 - 0.05 m"), y: ("-Panel Thickness / 2 - 0.012 m", "-Panel Thickness / 2"),
                                           z: ("Divider Height * 0.55", "Divider Height * 0.55 + 0.03 m")) }
        b.using(nil)
        for s in ["-", ""] { b.drill("Foot screw", x: "\(s)(Divider Width / 2 - 0.2 m)", y: "0 m", diameter: CX.mm(4), depth: CX.mm(14)) }
        b.outlines(x: ("-Divider Width / 2", "Divider Width / 2"), y: ("-0.06 m", "0.06 m"), z: ("0 m", "Divider Height"))
        b.type("Desk Divider - 48\" x 24\"", ["Divider Width": CC.inch(48)], cost: 189, model: "DD-4824")
        b.type("Desk Divider - 60\" x 24\"", [:], cost: 219, model: "DD-6024", isDefault: true)
        b.type("Desk Divider - 72\" x 18\"", ["Divider Width": CC.inch(72), "Divider Height": CC.inch(18)], cost: 239, model: "DD-7218")
        return b.build()
    }

    // MARK: Power and light

    /// In-desk power module: a flush housing in a rectangular cutout through the top, with outlets and USB ports.
    static func powerModule() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Power Module", .tables, "Power & Light", "In-desk power unit: flush housing with outlets and USB ports in a cutout through the top.", frame: .plan)
        b.tags("desk", "power", "outlet", "usb", "electrical", "cutout")
        b.aliases("desk power outlet", "in desk power", "power data module", "flush desk outlet", "pop-up power", "2 outlet", "120 v")
        b.material("Housing Material", .aluminum)
        b.material("Faceplate Material", .blackPlastic)
        b.length("Cutout Length", CC.mm(160))
        b.length("Cutout Width", CC.mm(70))
        b.length("Housing Depth", CC.mm(60))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.number("Outlets", 2, group: .dimensions)
        b.number("USB Ports", 2, group: .dimensions)
        b.flag("Pop-Up", false, instance: false, group: .dimensions)
        b.flag("Flush", false, formula: "not(Pop-Up)")
        b.electrical(watts: 1800, volts: 120, supply: "AC 120 V, 15 A", cable: "6 ft cord with plug; route under the top", connector: "NEMA 5-15")
        b.host([.top], faces: [.top], align: .top, alignments: [.top, .center, .topLeft, .topRight], offsetY: CC.inch(4))
        b.requires(.hostThickness(min: "0.012 m", max: "0.05 m"))
        b.requires(.note("Keep the housing's underside clear of rails and drawers."))
        b.pocket("Power module cutout", width: "Cutout Length", height: "Cutout Width", depth: "Host Thickness", through: true)
        b.box("Host Cutout", x: ("-Cutout Length / 2", "Cutout Length / 2"), y: ("-Cutout Width / 2", "Cutout Width / 2"), z: ("-Host Thickness", "0 m"), void: true)
        b.using("Housing Material")
        b.box("Housing", x: ("-Cutout Length / 2 + 0.001 m", "Cutout Length / 2 - 0.001 m"), y: ("-Cutout Width / 2 + 0.001 m", "Cutout Width / 2 - 0.001 m"), z: ("-Host Thickness - Housing Depth", "0 m"))
        b.shown("Flush") { $0.roundedBar("Bezel", width: "Cutout Length + 0.012 m", height: "Cutout Width + 0.012 m", radius: CX.mm(4), from: "0 m", to: "0.003 m") }
        b.shown("Pop-Up") { b in
            b.cyl("Tower", axis: .z, center: ("0 m", "0 m"), radius: "Cutout Width / 2 - 0.002 m", from: "0 m", to: "Cutout Length", segments: 32)
            b.cyl("Tower Cap", axis: .z, center: ("0 m", "0 m"), radius: "Cutout Width / 2 + 0.004 m", from: "Cutout Length", to: "Cutout Length + 0.008 m", segments: 32)
        }
        b.using("Faceplate Material")
        for k in 1...3 {
            let v = "Show Outlet \(k)"
            b.countFlag(v, "and(Flush, Outlets >= \(k))")
            let x = "-Cutout Length / 2 + 0.03 m + 0.042 m * \(k - 1)"
            b.shown(v) { $0.box("Outlet \(k)", x: ("\(x) - 0.016 m", "\(x) + 0.016 m"), y: ("-0.018 m", "0.018 m"), z: ("0.003 m", "0.005 m")) }
        }
        for k in 1...2 {
            let v = "Show USB \(k)"
            b.countFlag(v, "and(Flush, USB Ports >= \(k))")
            let y = k == 1 ? "-0.01 m" : "0.01 m"
            b.shown(v) { $0.box("USB Port \(k)", x: ("Cutout Length / 2 - 0.025 m", "Cutout Length / 2 - 0.013 m"), y: ("\(y) - 0.003 m", "\(y) + 0.003 m"), z: ("0.003 m", "0.004 m")) }
        }
        b.using(nil)
        b.symbol(.face, [.coarse, .medium, .fine], .rect(("-Cutout Length / 2 - 0.006 m", "-Cutout Width / 2 - 0.006 m"), ("Cutout Length / 2 + 0.006 m", "Cutout Width / 2 + 0.006 m")))
        b.symbol(.face, [.coarse], .line(("-Cutout Length / 2", "-Cutout Width / 2"), ("Cutout Length / 2", "Cutout Width / 2")),
                 .line(("-Cutout Length / 2", "Cutout Width / 2"), ("Cutout Length / 2", "-Cutout Width / 2")))
        b.symbol(.top, [.coarse], dashed: true, .rect(("-Cutout Length / 2", "-Host Thickness - Housing Depth"), ("Cutout Length / 2", "0 m")))
        b.type("Desk Power Module - 2 Outlets + 2 USB", [:], cost: 79, model: "DPM-2A2U")
        b.type("Desk Power Module - 3 Outlets", ["Cutout Length": CC.mm(190)], numbers: ["Outlets": 3, "USB Ports": 0], cost: 89, model: "DPM-3A")
        b.type("Desk Power Module - Pop-Up 3 Outlets", ["Cutout Length": CC.mm(200), "Cutout Width": CC.mm(80), "Housing Depth": CC.mm(210)], flags: ["Pop-Up": true],
               numbers: ["Outlets": 3, "USB Ports": 2], cost: 149, model: "DPM-POP3")
        return b.build()
    }

    /// Round USB charging module in a grommet-size hole.
    static func usbModule() -> ComponentDefinition {
        var b = ComponentBuilder("Desk USB Charging Module", .tables, "Power & Light", "Round in-desk USB-A / USB-C charger in a grommet-size hole.", frame: .plan)
        b.tags("desk", "usb", "charger", "usb-c", "electrical", "grommet")
        b.aliases("usb charging port", "desk usb charger", "usb-c desk port", "in desk usb", "60 mm", "80 mm", "5 v")
        b.material("Finish Material", .blackPlastic)
        b.length("Hole Diameter", CC.mm(60))
        b.length("Body Depth", CC.mm(55))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.number("USB-A Ports", 1, group: .dimensions)
        b.number("USB-C Ports", 1, group: .dimensions)
        b.electrical(watts: 30, volts: 5, supply: "AC 120 V adapter to USB 5 V (USB-C PD up to 20 V)", cable: "6 ft cord to the adapter", connector: "NEMA 1-15")
        b.host([.top, .shelf], faces: [.top], align: .topRight, alignments: [.topRight, .topLeft, .center], offsetX: CC.inch(4), offsetY: CC.inch(3))
        b.requires(.hostThickness(min: "0.012 m", max: "0.05 m"))
        b.drill("USB module hole", x: "0 m", y: "0 m", diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        b.cyl("Host Cutout", axis: .z, center: ("0 m", "0 m"), radius: "Hole Diameter / 2", from: "-Host Thickness", to: "0 m", segments: 32, void: true)
        b.cyl("Body", axis: .z, center: ("0 m", "0 m"), radius: "Hole Diameter / 2 - 0.001 m", from: "-Host Thickness - Body Depth", to: "0 m", segments: 32)
        b.revolve("Bezel", profile: ComponentKit.points([("0 m", "0 m"), ("Hole Diameter / 2 + 0.005 m", "0 m"), ("Hole Diameter / 2 + 0.004 m", "0.004 m"), ("0 m", "0.004 m")]))
        b.box("USB-A Port", x: ("-0.014 m", "-0.002 m"), y: ("-0.0025 m", "0.0025 m"), z: ("0.004 m", "0.0045 m"))
        b.box("USB-C Port", x: ("0.004 m", "0.0125 m"), y: ("-0.0016 m", "0.0016 m"), z: ("0.004 m", "0.0045 m"))
        b.symbol(.face, [.coarse, .medium, .fine], .circle(("0 m", "0 m"), "Hole Diameter / 2 + 0.005 m"))
        b.symbol(.top, [.coarse], dashed: true, .rect(("-Hole Diameter / 2", "-Host Thickness - Body Depth"), ("Hole Diameter / 2", "0.004 m")))
        b.type("Desk USB Charging Module - 60 mm A+C", [:], cost: 35, model: "DUM-60AC")
        b.type("Desk USB Charging Module - 80 mm 2C", ["Hole Diameter": CC.mm(80)], numbers: ["USB-A Ports": 0, "USB-C Ports": 2, "Power": 65], cost: 49, model: "DUM-80CC")
        return b.build()
    }

    /// Wireless charging pad: flush in a cutout, or under-mounted in a blind pocket below a thin top.
    static func wirelessCharger() -> ComponentDefinition {
        var b = ComponentBuilder("In-Desk Wireless Charger", .tables, "Power & Light", "Wireless phone charger: flush in a round cutout, or hidden under the top in a blind pocket.", frame: .plan)
        b.tags("desk", "wireless", "charger", "qi", "phone", "electrical")
        b.aliases("wireless charging module", "qi charger", "invisible charger", "under desk wireless charger", "15 w", "10 w", "80 mm")
        b.material("Finish Material", .blackPlastic)
        b.length("Pad Diameter", CC.mm(80))
        b.length("Pad Depth", CC.mm(18))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.length("Remaining Thickness", CC.mm(6), group: .manufacturing)
        b.flag("Under-Mount", false, instance: false, group: .dimensions)
        b.flag("Flush Mount", false, formula: "not(Under-Mount)")
        b.electrical(watts: 15, volts: 5, supply: "USB 5 V / 9 V adapter", cable: "USB-C cable to adapter", connector: "USB-C")
        b.host([.top, .shelf], faces: [.top], align: .topRight, alignments: [.topRight, .topLeft, .center], offsetX: CC.inch(6), offsetY: CC.inch(4))
        b.requires(.note("Under-mount: leave Remaining Thickness of top over the pad (max 3/4\" total)."))
        b.shown("Flush Mount") { b in
            b.cyl("Host Cutout", axis: .z, center: ("0 m", "0 m"), radius: "Pad Diameter / 2", from: "-Pad Depth", to: "0 m", segments: 32, void: true)
            b.cyl("Pad", axis: .z, center: ("0 m", "0 m"), radius: "Pad Diameter / 2 - 0.0005 m", from: "-Pad Depth", to: "0 m", segments: 40)
            b.revolve("Rim", profile: ComponentKit.points([("Pad Diameter / 2 - 0.003 m", "0 m"), ("Pad Diameter / 2 + 0.003 m", "0 m"), ("Pad Diameter / 2 + 0.002 m", "0.002 m"),
                                                           ("Pad Diameter / 2 - 0.003 m", "0.002 m")]))
        }
        b.shown("Under-Mount") { b in
            b.cyl("Pad (Under-Mount)", axis: .z, center: ("0 m", "0 m"), radius: "Pad Diameter / 2", from: "-Host Thickness - Pad Depth + Host Thickness - Remaining Thickness",
                  to: "-Remaining Thickness", segments: 40)
            b.box("Mount Bracket", x: ("-Pad Diameter / 2 - 0.02 m", "Pad Diameter / 2 + 0.02 m"), y: ("-0.012 m", "0.012 m"), z: ("-Host Thickness - 0.003 m", "-Host Thickness"))
        }
        b.pocket("Wireless charger pocket", width: "Pad Diameter", height: "Pad Diameter", depth: "if(Under-Mount, Host Thickness - Remaining Thickness, Pad Depth)", through: false)
        b.symbol(.face, [.coarse, .medium, .fine], .circle(("0 m", "0 m"), "Pad Diameter / 2"))
        b.symbol(.top, [.coarse], dashed: true, .rect(("-Pad Diameter / 2", "-Pad Depth"), ("Pad Diameter / 2", "0 m")))
        b.type("In-Desk Wireless Charger - Flush 15 W", [:], cost: 45, model: "IWC-F15")
        b.type("In-Desk Wireless Charger - Under-Mount 10 W", ["Pad Diameter": CC.mm(90), "Pad Depth": CC.mm(14)], flags: ["Under-Mount": true], numbers: ["Power": 10], cost: 55, model: "IWC-U10")
        return b.build()
    }

    /// Desk task light: an LED arm lamp on a desk clamp or grommet mount.
    static func deskLight() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Task Light", .tables, "Power & Light", "LED task light on a desk clamp or grommet mount: two arm links and a slim head.", frame: .plan)
        b.tags("desk", "light", "lamp", "led", "task light", "electrical")
        b.aliases("desk lamp", "task lamp", "clamp lamp", "led desk light", "architect lamp", "monitor light")
        b.material("Finish Material", .matteBlack)
        b.material("Lens Material", .diffuser)
        b.length("Arm Length", CC.mm(380))
        b.length("Head Length", CC.mm(400))
        b.length("Host Thickness", CC.inch(1), instance: true, group: .placement)
        b.angle("Arm Angle", 60, instance: true, group: .placement)
        b.flag("Grommet Mount", false, instance: false, group: .dimensions)
        b.flag("Clamp Mount", false, formula: "not(Grommet Mount)")
        b.number("Light Output", 800, unit: "lm", group: .data)
        b.number("Color Temperature", 3000, unit: "K", group: .data)
        b.electrical(watts: 10, volts: 24, supply: "AC 120 V adapter to DC 24 V", cable: "6 ft cord with in-line dimmer", connector: "Barrel 5.5 mm")
        b.host([.top], faces: [.top], align: .topLeft, alignments: [.topLeft, .topRight, .top])
        b.requires(.hostThickness(min: "0.012 m", max: "0.065 m"))
        b.shown("Clamp Mount") { b in
            b.box("Clamp Top", x: ("-0.03 m", "0.03 m"), y: ("-0.07 m", "0.01 m"), z: ("0 m", "0.012 m"))
            b.box("Clamp Back", x: ("-0.025 m", "0.025 m"), y: ("0 m", "0.01 m"), z: ("-Host Thickness - 0.02 m", "0 m"))
            b.box("Clamp Jaw", x: ("-0.025 m", "0.025 m"), y: ("-0.05 m", "0.01 m"), z: ("-Host Thickness - 0.01 m", "-Host Thickness"))
        }
        b.shown("Grommet Mount") { b in
            b.cyl("Grommet Post", axis: .z, center: ("0 m", "-0.03 m"), radius: "0.006 m", from: "-Host Thickness - 0.02 m", to: "0.012 m")
            b.cyl("Grommet Collar", axis: .z, center: ("0 m", "-0.03 m"), radius: "0.025 m", from: "0 m", to: "0.008 m")
        }
        b.cyl("Pivot", axis: .z, center: ("0 m", "-0.03 m"), radius: "0.012 m", from: "0.012 m", to: "0.06 m")
        b.strut("Lower Arm", plane: .yz, ("-0.03 m", "0.06 m"), ("-0.03 m - Arm Length * cos(Arm Angle)", "0.06 m + Arm Length * sin(Arm Angle)"), at: "0 m", d: CX.mm(12))
        b.strut("Upper Arm", plane: .yz, ("-0.03 m - Arm Length * cos(Arm Angle)", "0.06 m + Arm Length * sin(Arm Angle)"),
                ("-0.03 m - Arm Length * cos(Arm Angle) - Arm Length * 0.9", "0.06 m + Arm Length * sin(Arm Angle) + 0.02 m"), at: "0 m", d: CX.mm(10))
        let hy = "-0.03 m - Arm Length * cos(Arm Angle) - Arm Length * 0.9", hz = "0.06 m + Arm Length * sin(Arm Angle) + 0.02 m"
        b.roundedBar("Head", center: ("0 m", hy), width: "Head Length", height: "0.04 m", radius: "0.012 m", from: "\(hz) - 0.012 m", to: hz)
        b.using("Lens Material")
        b.roundedBar("Lens", center: ("0 m", hy), width: "Head Length - 0.02 m", height: "0.025 m", radius: "0.008 m", from: "\(hz) - 0.014 m", to: "\(hz) - 0.012 m")
        b.using(nil)
        b.drill("Grommet mount hole", x: "0 m", y: "-0.03 m", diameter: CX.mm(14), depth: "Host Thickness", through: true)
        b.symbol(.face, [.coarse], .rect(("-0.03 m", "-0.07 m"), ("0.03 m", "0.01 m")), .rect(("-Head Length / 2", "\(hy) - 0.02 m"), ("Head Length / 2", "\(hy) + 0.02 m")))
        b.symbol(.top, [.coarse], .line(("0 m", "0.06 m"), ("0 m", hz)))
        b.type("Desk Task Light - Clamp", [:], cost: 89, model: "DTL-C")
        b.type("Desk Task Light - Grommet", [:], flags: ["Grommet Mount": true], cost: 95, model: "DTL-G")
        return b.build()
    }

    /// Under-desk bag hook that swings out.
    static func deskHook() -> ComponentDefinition {
        var b = ComponentBuilder("Desk Hook", .tables, "Power & Light", "Swing-out bag and headphone hook under the top's edge.", frame: .plan)
        b.tags("desk", "hook", "bag", "headphone", "under desk", "hanger")
        b.aliases("bag hook", "headphone hook", "purse hook", "under desk hook", "swivel hook")
        b.material("Finish Material", .matteBlack)
        b.length("Hook Reach", CC.mm(60))
        b.length("Hook Drop", CC.mm(45))
        b.number("Load Capacity", 22, unit: "lb", group: .data)
        b.host([.top], faces: [.bottom], align: .bottomRight, alignments: [.bottomRight, .bottomLeft, .bottom], offsetX: CC.inch(3), offsetY: CC.inch(1))
        b.plate("Plate", width: CX.mm(40), depth: CX.mm(40), radius: CX.mm(6), z: ("-0.004 m", "0 m"))
        b.cyl("Swivel", axis: .z, center: ("0 m", "0 m"), radius: "0.008 m", from: "-0.012 m", to: "-0.004 m")
        b.wire("Hook", plane: .yz, [("0 m", "-0.01 m"), ("-Hook Reach", "-0.01 m"), ("-Hook Reach", "-Hook Drop"), ("-Hook Reach + 0.015 m", "-Hook Drop - 0.005 m"),
                                     ("-Hook Reach + 0.025 m", "-Hook Drop + 0.012 m")], at: "0 m", d: CX.mm(6))
        b.drill("Plate screw", x: "-0.013 m", y: "-0.013 m", diameter: CX.mm(3.5), depth: CX.mm(12))
        b.drill("Plate screw", x: "0.013 m", y: "0.013 m", diameter: CX.mm(3.5), depth: CX.mm(12))
        b.symbol(.face, [.coarse], .rect(("-0.02 m", "-0.02 m"), ("0.02 m", "0.02 m")), .line(("0 m", "0 m"), ("0 m", "-Hook Reach")))
        b.symbol(.top, [.coarse], .line(("0 m", "0 m"), ("0 m", "-Hook Drop")))
        b.type("Desk Hook - Swivel", [:], cost: 9, model: "DH-SW")
        b.type("Desk Hook - Large Swivel", ["Hook Reach": CC.mm(80), "Hook Drop": CC.mm(60)], numbers: ["Load Capacity": 33], cost: 12, model: "DH-SWL")
        return b.build()
    }
}
