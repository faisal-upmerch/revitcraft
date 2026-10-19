import Foundation
import ArcusGeometry

// COMPD: 19 Motion & Mechanical Components. Struts, stays, dampers, catches and latches go between a front (door,
// flap, lid) and the carcass: they're hosted on the side (or top) and drill the front as the counterpart. Platforms,
// bearings and lifting columns use the plan frame (Z up). Electric actuators and columns carry power data.

extension ComponentLibrary {
    static var groupDMotion: [ComponentDefinition] {
        [gasStrut(), gasSpring(), hydraulicDamper(), softCloseDamper(), doorStay(), lidStay(), liftUpStay(), foldDownMechanism(), pushToOpenActuator(),
         magneticCatch(), rollerCatch(), ballCatch(), springLatch(), doorStop(), doorBuffer(), foldingMechanism(), telescopicMechanism(), linearActuator(),
         liftingColumn(), rotatingPlatform(), swivelBearing(), turntableBearing(), pivotMechanism(), counterbalance()].compactMap { $0 }
    }

    /// A strut along the face at `Angle` from +X: body from the origin, rod to the end (`Extended Length`), at `standoff`
    /// out of the face; a ball-socket bracket at each end.
    fileprivate static func strut(_ b: inout ComponentBuilder, body: String, rod: String, standoff: String, eyes: Bool) {
        func along(_ l: String) -> FamilyPoint { DK.p("(\(l)) * cos(Angle)", "(\(l)) * sin(Angle)") }
        b.sweep("Body", path: [along("0.012 m"), along("0.012 m + Body Length")], profile: ComponentKit.circle(center: (DK.z, standoff), radius: "\(body) / 2", segments: 24))
        b.using("Rod Material")
        b.sweep("Rod", path: [along("0.012 m + Body Length"), along("Extended Length - 0.012 m")], profile: ComponentKit.circle(center: (DK.z, standoff), radius: "\(rod) / 2", segments: 16))
        b.using(nil)
        for (n, l) in [("Base", "0 m"), ("End", "Extended Length")] {
            let c = ("(\(l)) * cos(Angle)", "(\(l)) * sin(Angle)")
            if eyes {
                b.pipe("\(n) Eye", axis: .z, center: c, outer: "\(body) / 2", inner: CX.mm(4), from: "\(standoff) - 0.006 m", to: "\(standoff) + 0.006 m")
            } else {
                b.rod("\(n) Ball", axis: .z, center: c, radius: CX.mm(5), from: "\(standoff) - 0.005 m", to: "\(standoff) + 0.005 m")
            }
            b.roundedBar("\(n) Bracket", center: c, width: CX.mm(36), height: CX.mm(18), radius: CX.mm(4), from: CX.zero, to: CX.mm(3))
            b.rod("\(n) Stud", axis: .z, center: c, radius: CX.mm(3), from: CX.mm(3), to: standoff)
        }
        b.screwPair("Strut bracket screw", spacing: CX.mm(24), diameter: 3.5, depth: 12)
        b.drill("Strut bracket screw", x: "Extended Length * cos(Angle) - 0.012 m", y: "Extended Length * sin(Angle)", diameter: CX.mm(3.5), depth: CX.mm(12), target: .counterpart)
        b.drill("Strut bracket screw", x: "Extended Length * cos(Angle) + 0.012 m", y: "Extended Length * sin(Angle)", diameter: CX.mm(3.5), depth: CX.mm(12), target: .counterpart)
        b.symbol(.face, [.coarse, .medium, .fine], .line((DK.z, DK.z), ("Extended Length * cos(Angle)", "Extended Length * sin(Angle)")))
        b.symbol(.face, [.medium, .fine], .circle((DK.z, DK.z), CX.mm(6)), .circle(("Extended Length * cos(Angle)", "Extended Length * sin(Angle)"), CX.mm(6)))
        b.symbol(.top, [.medium, .fine], .rect((DK.z, CX.zero), ("Extended Length * cos(Angle)", "\(standoff) + \(body) / 2")))
    }

    static func gasStrut() -> ComponentDefinition {
        var b = ComponentBuilder("Gas Strut", .motion, "Struts & Springs", "Gas strut holding a lift-up flap or lid open: ball-socket brackets on the side and the front.")
        b.tags("gas strut", "gas lift", "lid support", "flap", "stay", "piston")
        b.aliases("gas struts", "gas lift support", "lid lift", "gas piston", "cabinet strut", "lift-up strut", "100 n gas strut")
        b.material("Body Material", .matteBlack)
        b.material("Rod Material", .chrome)
        b.length("Extended Length", DK.mm(245)); b.length("Stroke", DK.mm(80)); b.length("Body Diameter", DK.mm(15)); b.length("Rod Diameter", DK.mm(6))
        b.length("Body Length", 0, formula: "Extended Length - Stroke - 0.034 m")
        b.length("Closed Length", 0, formula: "Extended Length - Stroke")
        b.number("Force", 100, unit: "N", group: .data)
        b.angle("Angle", 35, instance: true, group: .placement)
        b.hardwareKind(.stay)
        b.host([.sidePanel], faces: [.inside], align: .top, alignments: [.top, .bottom], offsetX: DK.inch(2), offsetY: DK.inch(3))
        strut(&b, body: "Body Diameter", rod: "Rod Diameter", standoff: "0.012 m", eyes: false)
        b.clearance(.box(name: "Swing", x0: "0 m", x1: "Extended Length", y0: "-0.02 m", y1: "Extended Length", z0: "0 m", z1: "0.03 m"))
        b.requires(.note("Force: about (flap weight x center of gravity distance) / (strut lever x 2 struts); one strut each side over 24\" wide."))
        b.requires(.maxHostWeight("Force / 4.45 * 1.5"))
        b.type("Gas Strut - 245 mm, 60 N", numbers: ["Force": 60], cost: 7.50, model: "GST-245-060")
        b.type("Gas Strut - 245 mm, 100 N", cost: 7.50, model: "GST-245-100", isDefault: true)
        b.type("Gas Strut - 300 mm, 120 N", ["Extended Length": DK.mm(300), "Stroke": DK.mm(100)], numbers: ["Force": 120], cost: 8.50, model: "GST-300-120")
        b.type("Gas Strut - 400 mm, 150 N", ["Extended Length": DK.mm(400), "Stroke": DK.mm(150), "Body Diameter": DK.mm(18), "Rod Diameter": DK.mm(8)],
               numbers: ["Force": 150], cost: 10.00, model: "GST-400-150")
        return b.build()
    }

    static func gasSpring() -> ComponentDefinition {
        var b = ComponentBuilder("Gas Spring", .motion, "Struts & Springs", "Heavy gas spring with eye ends for storage beds, heavy lids and lifting tops.")
        b.tags("gas spring", "gas strut", "lift", "bed", "heavy", "eyelet")
        b.aliases("gas springs", "heavy gas strut", "bed lift spring", "eyelet gas spring", "storage bed piston", "400 n gas spring")
        b.material("Body Material", .matteBlack)
        b.material("Rod Material", .chrome)
        b.length("Extended Length", DK.mm(400)); b.length("Stroke", DK.mm(150)); b.length("Body Diameter", DK.mm(22)); b.length("Rod Diameter", DK.mm(10))
        b.length("Body Length", 0, formula: "Extended Length - Stroke - 0.04 m")
        b.number("Force", 400, unit: "N", group: .data)
        b.angle("Angle", 30, instance: true, group: .placement)
        b.host([.sidePanel, .rail], faces: [.inside], align: .bottom, alignments: [.bottom, .top], offsetX: DK.inch(3), offsetY: DK.inch(2))
        strut(&b, body: "Body Diameter", rod: "Rod Diameter", standoff: "0.016 m", eyes: true)
        b.clearance(.box(name: "Swing", x0: "0 m", x1: "Extended Length", y0: "-0.03 m", y1: "Extended Length", z0: "0 m", z1: "0.04 m"))
        b.requires(.note("Use in pairs; size the force to the lid's weight with the maker's chart."))
        b.type("Gas Spring - 400 mm, 400 N", cost: 16.00, model: "GSP-400-400")
        b.type("Gas Spring - 500 mm, 600 N", ["Extended Length": DK.mm(500), "Stroke": DK.mm(200)], numbers: ["Force": 600], cost: 19.00, model: "GSP-500-600")
        b.type("Gas Spring - 600 mm, 800 N", ["Extended Length": DK.mm(600), "Stroke": DK.mm(250), "Body Diameter": DK.mm(28), "Rod Diameter": DK.mm(14)],
               numbers: ["Force": 800], cost: 24.00, model: "GSP-600-800")
        return b.build()
    }

    static func hydraulicDamper() -> ComponentDefinition {
        var b = ComponentBuilder("Hydraulic Damper", .motion, "Dampers", "Linear hydraulic damper that lowers a drop-down flap or lid slowly; pivots on the side and the front.")
        b.tags("hydraulic", "damper", "lid", "flap", "slow close", "soft down")
        b.aliases("hydraulic dampers", "lid damper", "soft down stay", "flap damper", "oil damper", "slow close damper")
        b.material("Body Material", .steel)
        b.material("Rod Material", .chrome)
        b.length("Extended Length", DK.mm(220)); b.length("Stroke", DK.mm(80)); b.length("Body Diameter", DK.mm(12)); b.length("Rod Diameter", DK.mm(5))
        b.length("Body Length", 0, formula: "Extended Length - Stroke - 0.034 m")
        b.number("Load", 10, unit: "kg", group: .data)
        b.angle("Angle", 45, instance: true, group: .placement)
        b.hardwareKind(.stay)
        b.host([.sidePanel], faces: [.inside], align: .bottom, alignments: [.bottom, .top], offsetX: DK.inch(1.5), offsetY: DK.inch(1))
        strut(&b, body: "Body Diameter", rod: "Rod Diameter", standoff: "0.01 m", eyes: false)
        b.requires(.maxHostWeight("Load * 2.2"))
        b.type("Hydraulic Damper - 10 kg Flap", cost: 9.00, model: "HD-10")
        b.type("Hydraulic Damper - 20 kg Flap", ["Extended Length": DK.mm(260), "Stroke": DK.mm(100), "Body Diameter": DK.mm(15)], numbers: ["Load": 20], cost: 11.00, model: "HD-20")
        return b.build()
    }

    static func softCloseDamper() -> ComponentDefinition {
        var b = ComponentBuilder("Soft-Close Damper", .motion, "Dampers", "Door damper pressed into a 10 mm hole in the carcass edge (or on a screw-on adapter): the door closes softly.")
        b.tags("soft close", "damper", "door", "silent", "press-in", "10 mm")
        b.aliases("soft-close dampers", "door damper", "push-in damper", "cabinet door damper", "soft close adapter", "silent close")
        b.material("Body Material", .greyPlastic)
        b.material("Tip Material", .rubber)
        b.length("Bore Diameter", DK.mm(10)); b.length("Body Length", DK.mm(25)); b.length("Plunger", DK.mm(8))
        b.flag("Screw-On", false, instance: false, group: .manufacturing)
        b.host([.sidePanel, .top, .bottom, .divider], faces: [.frontEdge], align: .top, alignments: [.top, .bottom], offsetY: DK.inch(3))
        b.rod("Body", axis: .z, center: (DK.z, DK.z), radius: "Bore Diameter / 2 - 0.0002 m", from: "if(Screw-On, 0.002 m, -Body Length)", to: "if(Screw-On, Body Length + 0.002 m, 0 m)")
        b.rod("Collar", axis: .z, center: (DK.z, DK.z), radius: "Bore Diameter / 2 + 0.0015 m", from: "if(Screw-On, Body Length + 0.002 m, 0 m)", to: "if(Screw-On, Body Length + 0.0035 m, 0.0015 m)")
        b.using("Tip Material")
        b.rod("Plunger", axis: .z, center: (DK.z, DK.z), radius: CX.mm(3), from: "if(Screw-On, Body Length + 0.0035 m, 0.0015 m)", to: "if(Screw-On, Body Length + 0.0035 m, 0.0015 m) + Plunger")
        b.using(nil)
        b.visibility = "Screw-On"
        b.box("Adapter", x: (CX.mm(-15), CX.mm(15)), y: ("-Bore Diameter / 2 - 0.002 m", "Bore Diameter / 2 + 0.002 m"), z: (DK.z, CX.mm(2)))
        b.visibility = nil
        b.drill("Damper bore", x: CX.zero, y: CX.zero, diameter: "if(Screw-On, 0 m, Bore Diameter)", depth: "Body Length + 0.001 m")
        b.screwPair("Damper adapter screw", spacing: CX.mm(22), diameter: 3, depth: 10, when: "Screw-On")
        b.roundOutlines(radius: "Bore Diameter / 2 + 0.0015 m", z: ("-Body Length", "Plunger + 0.0015 m"))
        b.type("Soft-Close Damper - Press-In 10 mm", cost: 2.20, model: "SCD-10P")
        b.type("Soft-Close Damper - Screw-On Adapter", flags: ["Screw-On": true], cost: 2.80, model: "SCD-10S")
        return b.build()
    }

    /// Two arms pinned together: one from the side's bracket, one to the front's, at `Angle` open.
    fileprivate static func foldingArms(_ b: inout ComponentBuilder, armA: String, armB: String, width: String, thickness: String) {
        let w = "(\(width)) / 2", t = thickness
        b.extrusion("Arm A", profile: DK.pts([(DK.z, "-\(w)"), (armA, "-\(w)"), (armA, w), (DK.z, w)]), plane: .xy, from: CX.mm(4), to: "0.004 m + \(t)")
        b.extrusion("Arm B", profile: DK.pts([(armA, "-\(w)"), ("\(armA) + (\(armB)) * cos(Angle)", "(\(armB)) * sin(Angle) - \(w)"),
                                              ("\(armA) + (\(armB)) * cos(Angle)", "(\(armB)) * sin(Angle) + \(w)"), (armA, w)]),
                    plane: .xy, from: "0.004 m + \(t)", to: "0.004 m + 2 * \(t)")
        b.rod("Pivot", axis: .z, center: (armA, DK.z), radius: CX.mm(3), from: CX.mm(4), to: "0.005 m + 2 * \(t)")
        b.roundedBar("Side Bracket", width: CX.mm(28), height: CX.mm(18), radius: CX.mm(3), from: CX.zero, to: CX.mm(4))
        b.rod("Side Pin", axis: .z, center: (DK.z, DK.z), radius: CX.mm(3), from: CX.mm(4), to: "0.005 m + \(t)")
    }

    static func doorStay() -> ComponentDefinition {
        var b = ComponentBuilder("Door Stay", .motion, "Stays", "Friction stay arm that stops a door at 90° or 110° and holds it against wind and knocks.")
        b.tags("door stay", "restraint", "stop", "friction", "arm", "door")
        b.aliases("door stays", "door restraint", "door check", "friction stay", "door stop arm", "wardrobe door stay")
        b.material("Finish Material", .steel)
        b.length("Arm A Length", DK.mm(110)); b.length("Arm B Length", DK.mm(100)); b.length("Arm Width", DK.mm(12)); b.length("Arm Thickness", DK.mm(2.5))
        b.angle("Angle", 150, instance: true, group: .placement)
        b.host([.top, .sidePanel], faces: [.bottom, .inside], align: .left, alignments: [.left, .right], offsetX: DK.inch(1), offsetY: DK.inch(2))
        foldingArms(&b, armA: "Arm A Length", armB: "Arm B Length", width: "Arm Width", thickness: "Arm Thickness")
        b.screwPair("Door stay screw", spacing: CX.mm(18), diameter: 3.5, depth: 12)
        b.drill("Door stay screw", x: "Arm A Length + Arm B Length * cos(Angle)", y: "Arm B Length * sin(Angle)", diameter: CX.mm(3.5), depth: CX.mm(12), target: .counterpart)
        b.symbol(.face, [.coarse, .medium, .fine], .line((DK.z, DK.z), ("Arm A Length", DK.z)), .line(("Arm A Length", DK.z), ("Arm A Length + Arm B Length * cos(Angle)", "Arm B Length * sin(Angle)")))
        b.type("Door Stay - 90°", cost: 6.50, model: "DST-90")
        b.type("Door Stay - 110°", ["Arm A Length": DK.mm(130), "Arm B Length": DK.mm(120)], cost: 7.00, model: "DST-110")
        return b.build()
    }

    static func lidStay() -> ComponentDefinition {
        var b = ComponentBuilder("Lid Stay", .motion, "Stays", "Folding lid stay for chests and toy boxes: holds the lid open and lets it down slowly (child-safe).")
        b.tags("lid stay", "chest", "toy box", "lid support", "soft down", "folding")
        b.aliases("lid stays", "chest lid support", "toy box hinge", "safety lid stay", "lid support hinge")
        b.material("Finish Material", .steel)
        b.length("Arm A Length", DK.inch(4)); b.length("Arm B Length", DK.inch(4.5)); b.length("Arm Width", DK.mm(14)); b.length("Arm Thickness", DK.mm(2.5))
        b.number("Torque", 25, unit: "in-lb", group: .data)
        b.angle("Angle", 120, instance: true, group: .placement)
        b.hardwareKind(.stay)
        b.host([.sidePanel], faces: [.inside], align: .top, alignments: [.top], offsetX: DK.inch(1.5), offsetY: DK.inch(1))
        foldingArms(&b, armA: "Arm A Length", armB: "Arm B Length", width: "Arm Width", thickness: "Arm Thickness")
        b.rod("Damper", axis: .z, center: (DK.z, DK.z), radius: CX.mm(9), from: CX.mm(4), to: CX.mm(14))
        b.screwPair("Lid stay screw", spacing: CX.mm(18), diameter: 3.5, depth: 12)
        b.drill("Lid stay screw", x: "Arm A Length + Arm B Length * cos(Angle)", y: "Arm B Length * sin(Angle)", diameter: CX.mm(3.5), depth: CX.mm(12), target: .counterpart)
        b.symbol(.face, [.coarse, .medium, .fine], .line((DK.z, DK.z), ("Arm A Length", DK.z)), .line(("Arm A Length", DK.z), ("Arm A Length + Arm B Length * cos(Angle)", "Arm B Length * sin(Angle)")))
        b.requires(.note("Pick the torque from the lid: weight (lb) x depth (in) / 2, one stay per side over 24\" wide."))
        b.type("Lid Stay - 25 in-lb", cost: 8.00, model: "LST-25")
        b.type("Lid Stay - 45 in-lb", ["Arm A Length": DK.inch(5), "Arm B Length": DK.inch(5.5), "Arm Width": DK.mm(16)], numbers: ["Torque": 45], cost: 10.50, model: "LST-45")
        return b.build()
    }

    /// Lift-Up Mechanisms: FM5's Flap Stay, with a heavier type and the lift-up names.
    static func liftUpStay() -> ComponentDefinition? {
        guard var b = ComponentBuilder(upgrading: FurnitureHardware.flapStay) else { return nil }
        b.tags("lift-up mechanism", "lift up", "flap", "stay", "aventos-style", "power unit")
        b.aliases("lift-up mechanisms", "lift up mechanism", "flap lift system", "lift system", "stay lift", "lift-up fitting")
        b.type("Lift-Up Stay - Heavy", ["Body Length": DK.mm(190), "Body Height": DK.mm(130), "Body Width": DK.mm(36), "Arm Length": DK.mm(120),
                                        "Screw Hole Diameter": DK.mm(5), "Screw Hole Depth": DK.mm(13), "Screw Spacing": DK.mm(32)],
               flags: ["Drop Down": false], cost: 24.00, model: "FS-LUH", description: "Lift-up flap stay for heavy flaps (up to 22 lb), holds open at any angle")
        // Plan and elevation symbols of the mechanism on the side (FM5's frame: X across, Y back, Z up from the flap's top).
        b.symbol(.face, [.coarse, .medium, .fine], .rect(("0.015 m", "-Body Height"), ("0.015 m + Body Length", "0 m")))
        b.symbol(.top, [.medium, .fine], .rect(("0 m", "0.015 m"), ("Body Width", "0.015 m + Body Length")))
        b.symbol(.face, [.medium, .fine], dashed: true, .line(("0.015 m", "-0.04 m"), ("Arm Length", "-0.04 m")))
        return b.build()
    }

    static func foldDownMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Fold-Down Flap Mechanism", .motion, "Stays", "Parallel-arm mechanism for drop-down flaps (bar and desk flaps): the flap folds down level and is damped.")
        b.tags("fold down", "drop down", "flap", "mechanism", "desk", "bar", "damped")
        b.aliases("fold-down mechanisms", "drop down flap fitting", "fall flap mechanism", "secretary desk mechanism", "flap down stay")
        b.material("Finish Material", .steel)
        b.material("Cover Material", .whitePlastic)
        b.length("Body Length", DK.mm(120)); b.length("Body Height", DK.mm(40)); b.length("Arm Length", DK.mm(160)); b.length("Body Depth", DK.mm(16))
        b.number("Load", 8, unit: "kg", group: .data)
        b.angle("Angle", -90, instance: true, group: .placement)
        b.hardwareKind(.stay)
        b.host([.sidePanel], faces: [.inside], align: .bottom, alignments: [.bottom], offsetX: DK.inch(0.75), offsetY: DK.inch(1))
        b.using("Cover Material")
        b.roundedBar("Body", center: ("Body Length / 2", "Body Height / 2"), width: "Body Length", height: "Body Height", radius: CX.mm(6), from: CX.zero, to: "Body Depth")
        b.using(nil)
        for (k, y) in ["0.01 m", "Body Height - 0.01 m"].enumerated() {
            let p0 = ("Body Length - 0.012 m", y)
            b.extrusion("Arm \(k + 1)", profile: DK.pts([("\(p0.0) - 0.005 m", "\(p0.1) - 0.005 m"), ("\(p0.0) + Arm Length * cos(Angle) + 0.005 m", "\(p0.1) + Arm Length * sin(Angle) - 0.005 m"),
                                                         ("\(p0.0) + Arm Length * cos(Angle) + 0.005 m", "\(p0.1) + Arm Length * sin(Angle) + 0.005 m"), ("\(p0.0) - 0.005 m", "\(p0.1) + 0.005 m")]),
                        from: "Body Depth", to: "Body Depth + 0.003 m")
        }
        b.drill("Mechanism screw", x: CX.mm(15), y: "Body Height / 2", diameter: CX.mm(5), depth: CX.mm(13))
        b.drill("Mechanism screw", x: "Body Length - 0.03 m", y: "Body Height / 2", diameter: CX.mm(5), depth: CX.mm(13))
        b.drill("Flap bracket screw", x: "Body Length - 0.012 m + Arm Length * cos(Angle)", y: "Body Height / 2 + Arm Length * sin(Angle)", diameter: CX.mm(4), depth: CX.mm(12), target: .counterpart)
        b.outlines(x: (DK.z, "Body Length"), y: (DK.z, "Body Height"), z: (DK.z, "Body Depth"))
        b.requires(.maxHostWeight("Load * 2.2"))
        b.type("Fold-Down Mechanism - 8 kg", cost: 22.00, model: "FDM-08")
        b.type("Fold-Down Mechanism - 15 kg", ["Body Length": DK.mm(150), "Body Height": DK.mm(48), "Arm Length": DK.mm(190)], numbers: ["Load": 15], cost: 29.00, model: "FDM-15")
        return b.build()
    }

    // MARK: Catches and latches

    static func pushToOpenActuator() -> ComponentDefinition {
        var b = ComponentBuilder("Push-to-Open Actuator", .motion, "Catches & Latches", "Push latch for handleless doors and flaps: press the front and the plunger pushes it open.")
        b.tags("push to open", "push latch", "touch latch", "handleless", "tip on", "magnetic")
        b.aliases("push-to-open actuators", "push latch", "touch latch", "tip-on", "push opener", "spring latch for handleless")
        b.material("Body Material", .greyPlastic)
        b.material("Tip Material", .rubber)
        b.length("Body Length", DK.mm(60)); b.length("Body Width", DK.mm(16)); b.length("Body Height", DK.mm(16)); b.length("Stroke", DK.mm(20)); b.length("Bore Diameter", 0)
        b.flag("Bore-In", false, instance: false, group: .manufacturing)
        b.flag("Surface", true, formula: "not(Bore-In)")
        b.host([.sidePanel, .top, .bottom, .divider], faces: [.inside, .frontEdge], align: .top, alignments: [.top, .bottom, .center], offsetY: DK.inch(2))
        // Surface: the body on the inside face, the plunger toward the front (+X here is toward the front).
        b.visibility = "Surface"
        b.box("Body", x: ("-Body Length", DK.z), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.using("Tip Material")
        b.rod("Plunger", axis: .x, center: (DK.z, "Body Height / 2"), radius: CX.mm(4), from: CX.zero, to: "Stroke * 0.4")
        b.using(nil)
        b.visibility = "Bore-In"
        b.rod("Barrel", axis: .z, center: (DK.z, DK.z), radius: "Bore Diameter / 2 - 0.0002 m", from: "-Body Length", to: CX.zero)
        b.rod("Flange", axis: .z, center: (DK.z, DK.z), radius: "Bore Diameter / 2 + 0.002 m", from: CX.zero, to: CX.mm(1.5))
        b.using("Tip Material")
        b.rod("Bore Plunger", axis: .z, center: (DK.z, DK.z), radius: CX.mm(3.5), from: CX.mm(1.5), to: "0.0015 m + Stroke * 0.4")
        b.using(nil)
        b.visibility = nil
        b.screwPair("Latch screw", spacing: "Body Length * 0.6", y: CX.zero, diameter: 3, depth: 10, when: "Surface")
        b.drill("Latch bore", x: CX.zero, y: CX.zero, diameter: "if(Bore-In, Bore Diameter, 0 m)", depth: "Body Length + 0.001 m")
        b.outlines(x: ("-Body Length", "Stroke * 0.4"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.clearance(.box(name: "Push stroke", x0: "0 m", x1: "Stroke", y0: "-0.01 m", y1: "0.01 m", z0: "0 m", z1: "Body Height"))
        b.type("Push-to-Open Actuator - Surface, Magnetic Tip", cost: 4.50, model: "PTO-SM")
        b.type("Push-to-Open Actuator - Long Stroke 40 mm", ["Body Length": DK.mm(90), "Stroke": DK.mm(40)], cost: 6.50, model: "PTO-L40")
        b.type("Push-to-Open Actuator - Bore-In 10 mm", ["Body Length": DK.mm(40), "Bore Diameter": DK.mm(10), "Stroke": DK.mm(12)], flags: ["Bore-In": true], cost: 4.00, model: "PTO-B10")
        return b.build()
    }

    static func magneticCatch() -> ComponentDefinition {
        var b = ComponentBuilder("Magnetic Catch", .motion, "Catches & Latches", "Magnetic catch under the top or on the side, with a steel strike plate on the door.")
        b.tags("magnetic catch", "magnet", "catch", "door", "strike", "latch")
        b.aliases("magnetic catches", "magnet catch", "cabinet magnet", "door magnet", "magnetic latch", "bore-in magnet")
        b.material("Body Material", .whitePlastic)
        b.material("Strike Material", .steel)
        b.length("Body Length", DK.mm(40)); b.length("Body Width", DK.mm(14)); b.length("Body Height", DK.mm(14)); b.length("Bore Diameter", 0)
        b.number("Pull Force", 3, unit: "kg", group: .data)
        b.flag("Bore-In", false, instance: false, group: .manufacturing)
        b.flag("Surface", true, formula: "not(Bore-In)")
        b.host([.top, .sidePanel, .bottom, .shelf], faces: [.bottom, .inside, .frontEdge], align: .center, alignments: [.center, .left, .right], offsetY: DK.mm(10))
        b.visibility = "Surface"
        b.box("Body", x: ("-Body Length / 2", "Body Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.using("Strike Material")
        b.box("Magnet Faces", x: ("-Body Length / 2 + 0.006 m", "Body Length / 2 - 0.006 m"), y: ("Body Width / 2", "Body Width / 2 + 0.001 m"), z: (CX.mm(3), "Body Height - 0.003 m"))
        b.box("Strike Plate", x: ("-Body Length / 2 + 0.004 m", "Body Length / 2 - 0.004 m"), y: ("Body Width / 2 + 0.003 m", "Body Width / 2 + 0.004 m"), z: (CX.mm(1), "Body Height - 0.001 m"))
        b.using(nil)
        b.visibility = "Bore-In"
        b.rod("Cup", axis: .z, center: (DK.z, DK.z), radius: "Bore Diameter / 2 - 0.0002 m", from: CX.mm(-6), to: CX.zero)
        b.using("Strike Material")
        b.rod("Magnet", axis: .z, center: (DK.z, DK.z), radius: "Bore Diameter / 2 - 0.0012 m", from: CX.mm(-0.5), to: CX.mm(0.2))
        b.using(nil)
        b.visibility = nil
        b.screwPair("Catch screw", spacing: "Body Length * 0.7", y: CX.zero, diameter: 3, depth: 10, when: "Surface")
        b.drill("Magnet bore", x: CX.zero, y: CX.zero, diameter: "if(Bore-In, Bore Diameter, 0 m)", depth: CX.mm(6))
        b.drill("Strike screw", x: CX.zero, y: CX.zero, diameter: CX.mm(2.5), depth: CX.mm(8), target: .counterpart)
        b.outlines(x: ("-Body Length / 2", "Body Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.type("Magnetic Catch - Single, 3 kg", cost: 1.60, model: "MGC-S3")
        b.type("Magnetic Catch - Double, 6 kg", ["Body Length": DK.mm(52), "Body Width": DK.mm(16)], numbers: ["Pull Force": 6], cost: 2.40, model: "MGC-D6")
        b.type("Magnetic Catch - Bore-In 10 mm", ["Bore Diameter": DK.mm(10)], flags: ["Bore-In": true], numbers: ["Pull Force": 2], cost: 1.40, model: "MGC-B10")
        return b.build()
    }

    static func rollerCatch() -> ComponentDefinition {
        var b = ComponentBuilder("Roller Catch", .motion, "Catches & Latches", "Spring roller catch: one or two rollers grip the strike on the door.")
        b.tags("roller catch", "catch", "door", "roller", "strike", "latch")
        b.aliases("roller catches", "double roller catch", "spring roller latch", "roller latch")
        b.material("Finish Material", .brass)
        b.length("Body Length", DK.mm(36)); b.length("Body Width", DK.mm(16)); b.length("Body Height", DK.mm(12)); b.length("Roller Diameter", DK.mm(8))
        b.flag("Double", false, instance: false, group: .dimensions)
        b.host([.top, .sidePanel, .bottom, .shelf], faces: [.bottom, .inside], align: .center, alignments: [.center, .left, .right], offsetY: DK.mm(10))
        b.box("Body", x: ("-Body Length / 2", "Body Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height * 0.4"))
        b.box("Housing", x: ("-Body Length / 2 + 0.008 m", "Body Length / 2 - 0.008 m"), y: ("-Body Width / 2", "Body Width / 2 - 0.004 m"), z: ("Body Height * 0.4", "Body Height"))
        b.rod("Roller", axis: .x, center: ("Body Width / 2 - 0.004 m", "Body Height - Roller Diameter / 2"), radius: "Roller Diameter / 2", from: "-Body Length / 2 + 0.009 m", to: "Body Length / 2 - 0.009 m")
        b.visibility = "Double"
        b.rod("Second Roller", axis: .x, center: ("-Body Width / 2 + 0.004 m", "Body Height - Roller Diameter / 2"), radius: "Roller Diameter / 2", from: "-Body Length / 2 + 0.009 m", to: "Body Length / 2 - 0.009 m")
        b.visibility = nil
        b.box("Strike", x: (CX.mm(-6), CX.mm(6)), y: (CX.mm(-3), CX.mm(3)), z: ("Body Height + 0.002 m", "Body Height + 0.012 m"))
        b.screwPair("Catch screw", spacing: "Body Length * 0.75", diameter: 3, depth: 10)
        b.drill("Strike screw", x: CX.zero, y: CX.zero, diameter: CX.mm(2.5), depth: CX.mm(8), target: .counterpart)
        b.outlines(x: ("-Body Length / 2", "Body Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.type("Roller Catch - Single", cost: 2.50, model: "RC-S")
        b.type("Roller Catch - Double", ["Body Width": DK.mm(22)], flags: ["Double": true], cost: 3.20, model: "RC-D")
        return b.build()
    }

    static func ballCatch() -> ComponentDefinition {
        var b = ComponentBuilder("Ball Catch", .motion, "Catches & Latches", "Spring ball catch bored into the door's top edge, with a strike plate under the top.")
        b.tags("ball catch", "bullet catch", "catch", "door", "spring", "bore-in")
        b.aliases("ball catches", "double ball catch", "bullet catch", "spring ball latch", "8 mm ball catch")
        b.material("Finish Material", .brass)
        b.length("Bore Diameter", DK.mm(8)); b.length("Body Length", DK.mm(16)); b.length("Ball Diameter", DK.mm(5))
        b.flag("Double", false, instance: false, group: .dimensions)
        b.flag("Bore", true, formula: "not(Double)")
        b.host(ComponentHostKind.fronts, faces: [.topEdge], align: .outside, alignments: [.outside, .center], offsetX: DK.inch(1))
        b.visibility = "Bore"
        b.rod("Barrel", axis: .z, center: (DK.z, DK.z), radius: "Bore Diameter / 2 - 0.0002 m", from: "-Body Length", to: CX.zero)
        b.revolve("Ball", profile: DK.pts([(DK.z, CX.mm(-0.5))] + (0...8).map { k -> (String, String) in
            let a = -Double.pi / 2 + Double.pi * Double(k) / 8
            return ("Ball Diameter / 2 * \(LX.num(cos(a)))", "Ball Diameter / 2 * \(LX.num(sin(a)))")
        }.dropFirst().map { $0 }), base: CX.zero)
        b.visibility = "Double"
        b.box("Double Body", x: (CX.mm(-14), CX.mm(14)), y: (CX.mm(-6), CX.mm(6)), z: (DK.z, CX.mm(14)))
        b.rod("Ball Left", axis: .y, center: (CX.zero, CX.mm(10)), radius: "Ball Diameter / 2", from: CX.mm(-8), to: CX.mm(-6))
        b.rod("Ball Right", axis: .y, center: (CX.zero, CX.mm(10)), radius: "Ball Diameter / 2", from: CX.mm(6), to: CX.mm(8))
        b.visibility = nil
        b.drill("Ball catch bore", x: CX.zero, y: CX.zero, diameter: "if(Double, 0 m, Bore Diameter)", depth: "Body Length + 0.001 m")
        b.screwPair("Ball catch screw", spacing: CX.mm(20), diameter: 3, depth: 10, when: "Double")
        b.drill("Strike screw", x: CX.zero, y: CX.zero, diameter: CX.mm(2.5), depth: CX.mm(8), target: .counterpart)
        b.roundOutlines(radius: "Bore Diameter / 2", z: ("-Body Length", "Ball Diameter / 2"))
        b.type("Ball Catch - 8 mm Bore-In", cost: 1.20, model: "BC-08")
        b.type("Ball Catch - 3/8\" Bore-In", ["Bore Diameter": DK.inch(0.375), "Body Length": DK.inch(0.75), "Ball Diameter": DK.mm(6)], cost: 1.30, model: "BC-38")
        b.type("Ball Catch - Double, Surface", flags: ["Double": true], cost: 1.80, model: "BC-DS")
        return b.build()
    }

    static func springLatch() -> ComponentDefinition {
        var b = ComponentBuilder("Spring Latch", .motion, "Catches & Latches", "Spring bolt latch with a knob or lever: the bolt snaps into the keeper when the door shuts.")
        b.tags("spring latch", "latch", "bolt", "keeper", "door", "lever")
        b.aliases("spring latches", "spring bolt", "latch bolt", "cabinet latch", "slam latch")
        b.material("Finish Material", .satinNickel)
        b.length("Case Length", DK.mm(50)); b.length("Case Width", DK.mm(25)); b.length("Case Depth", DK.mm(10)); b.length("Bolt Throw", DK.mm(8))
        b.host(ComponentHostKind.fronts, faces: [.inside], align: .outside, alignments: [.outside, .top, .bottom])
        b.box("Case", x: ("-Case Length / 2", "Case Length / 2"), y: ("-Case Width / 2", "Case Width / 2"), z: (DK.z, "Case Depth"))
        b.box("Bolt", x: ("Case Length / 2", "Case Length / 2 + Bolt Throw"), y: (CX.mm(-5), CX.mm(5)), z: (CX.mm(2), "Case Depth - 0.002 m"))
        b.rod("Knob", axis: .z, center: ("-Case Length / 4", CX.zero), radius: CX.mm(5), from: "Case Depth", to: "Case Depth + 0.01 m")
        b.box("Keeper", x: ("Case Length / 2 + 0.002 m", "Case Length / 2 + 0.016 m"), y: ("-Case Width / 2", "Case Width / 2"), z: (DK.z, "Case Depth + 0.002 m"))
        b.screwPair("Latch screw", spacing: "Case Length * 0.6", diameter: 3, depth: 10)
        b.drill("Keeper screw", x: "Case Length / 2 + 0.009 m", y: CX.zero, diameter: CX.mm(3), depth: CX.mm(10), target: .counterpart)
        b.outlines(x: ("-Case Length / 2", "Case Length / 2 + 0.016 m"), y: ("-Case Width / 2", "Case Width / 2"), z: (DK.z, "Case Depth + 0.01 m"))
        b.type("Spring Latch - Surface", cost: 4.50, model: "SL-S")
        b.type("Spring Latch - Heavy", ["Case Length": DK.mm(70), "Case Width": DK.mm(32), "Bolt Throw": DK.mm(12)], cost: 6.50, model: "SL-H")
        return b.build()
    }

    static func doorStop() -> ComponentDefinition {
        var b = ComponentBuilder("Cabinet Door Stop", .motion, "Stops & Buffers", "Stop the door closes against: a small angle bracket or a stop block under the top.")
        b.tags("door stop", "stop", "bracket", "block", "inset door")
        b.aliases("door stops", "cabinet door stop", "inset door stop", "door stop block", "stop bracket")
        b.material("Finish Material", .steel)
        b.material("Pad Material", .rubber)
        b.length("Stop Width", DK.mm(20)); b.length("Leg", DK.mm(16)); b.length("Thickness", DK.mm(2))
        b.flag("Block", false, instance: false, group: .dimensions)
        b.flag("Bracket", true, formula: "not(Block)")
        b.host([.top, .bottom, .sidePanel], faces: [.bottom, .inside], align: .center, alignments: [.center, .left, .right], offsetY: DK.inch(0.75))
        b.visibility = "Bracket"
        b.bracket("Stop", width: "Stop Width", legA: "Leg", legB: "Leg", thickness: "Thickness")
        b.using("Pad Material")
        b.box("Pad", x: ("-Stop Width / 2 + 0.002 m", "Stop Width / 2 - 0.002 m"), y: ("-0.0015 m", CX.zero), z: (CX.mm(4), "Leg - 0.002 m"))
        b.using(nil)
        b.visibility = "Block"
        b.box("Stop Block", x: ("-Stop Width / 2", "Stop Width / 2"), y: (DK.z, "Leg"), z: (DK.z, "Leg"))
        b.visibility = nil
        b.drill("Stop screw", x: CX.zero, y: "Leg / 2", diameter: CX.mm(3), depth: CX.mm(12))
        b.outlines(x: ("-Stop Width / 2", "Stop Width / 2"), y: (DK.z, "Leg"), z: (DK.z, "Leg"))
        b.type("Door Stop - Angle Bracket", cost: 0.80, model: "DS-AB")
        b.type("Door Stop - Block 3/4\"", ["Stop Width": DK.inch(1.5), "Leg": DK.inch(0.75)], flags: ["Block": true], cost: 0.60, model: "DS-BL")
        return b.build()
    }

    static func doorBuffer() -> ComponentDefinition {
        var b = ComponentBuilder("Door Buffer", .motion, "Stops & Buffers", "Soft press-in buffer in a small hole in the carcass edge or door back: quiets the door shutting.")
        b.tags("buffer", "silencer", "bumper", "door", "press-in", "soft")
        b.aliases("cabinet door buffers", "door silencer", "press in bumper", "door cushion", "5 mm buffer", "8 mm buffer")
        b.material("Buffer Material", .greyRubber)
        b.length("Hole Diameter", DK.mm(5)); b.length("Head Diameter", DK.mm(8)); b.length("Head Height", DK.mm(2)); b.length("Stem Length", DK.mm(5))
        b.host([.sidePanel, .top, .bottom] + ComponentHostKind.fronts, faces: [.frontEdge, .inside], align: .topLeft, alignments: [.topLeft, .topRight, .bottomLeft, .bottomRight],
               offsetX: DK.inch(1), offsetY: DK.inch(1))
        b.rod("Stem", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2", from: "-Stem Length", to: CX.zero)
        b.revolve("Head", profile: DK.pts([(DK.z, DK.z), ("Head Diameter / 2", DK.z), ("Head Diameter / 2", "Head Height * 0.4")] + (1...6).map { k -> (String, String) in
            let a = Double.pi / 2 * Double(k) / 6
            return ("Head Diameter / 2 * \(LX.num(cos(a)))", "Head Height * 0.4 + Head Height * 0.6 * \(LX.num(sin(a)))")
        }))
        b.drill("Buffer hole", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Stem Length + 0.001 m")
        b.roundOutlines(radius: "Head Diameter / 2", z: ("-Stem Length", "Head Height"))
        b.type("Door Buffer - 5 mm Press-In", cost: 0.10, model: "DB-05")
        b.type("Door Buffer - 8 mm Press-In", ["Hole Diameter": DK.mm(8), "Head Diameter": DK.mm(12), "Head Height": DK.mm(3), "Stem Length": DK.mm(7)], cost: 0.14, model: "DB-08")
        return b.build()
    }

    // MARK: Folding, telescopic, electric

    static func foldingMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Folding Mechanism", .motion, "Folding & Telescopic", "Locking folding brace for fold-down shelves, wall desks and drop leaves: locks straight, folds flat.")
        b.tags("folding", "brace", "locking", "fold down", "wall desk", "drop leaf", "knee brace")
        b.aliases("folding mechanisms", "folding brace", "locking brace", "fold down bracket", "drop leaf brace", "collapsible bracket")
        b.material("Finish Material", .steel)
        b.length("Leg", DK.inch(10)); b.length("Bar Width", DK.mm(25)); b.length("Metal", DK.mm(3))
        b.number("Load", 100, unit: "lb", group: .data)
        b.host([.sidePanel, .back, .wall], faces: [.inside, .front], align: .top, alignments: [.top], offsetY: 0)
        // Folded open: a vertical leg on the wall, the shelf leg out of it, the hinged brace across.
        b.box("Wall Leg", x: ("-Bar Width / 2", "Bar Width / 2"), y: ("-Leg", DK.z), z: (DK.z, "Metal"))
        b.box("Shelf Leg", x: ("-Bar Width / 2", "Bar Width / 2"), y: ("-Metal", DK.z), z: (DK.z, "Leg"))
        b.extrusion("Diagonal Brace", profile: DK.pts([("-Leg * 0.85", "Metal"), ("-Leg * 0.85 + 0.012 m", "Metal"), ("-Metal", "Leg * 0.85 - 0.012 m"), ("-Metal", "Leg * 0.85")]),
                    plane: .yz, from: "-Bar Width * 0.3", to: "Bar Width * 0.3")
        b.rod("Lock Knuckle", axis: .x, center: ("-Leg * 0.42", "Leg * 0.42"), radius: CX.mm(5), from: "-Bar Width * 0.35", to: "Bar Width * 0.35")
        b.drill("Brace wall screw", x: CX.zero, y: "-Leg * 0.3", diameter: CX.mm(4.5), depth: CX.mm(16))
        b.drill("Brace wall screw", x: CX.zero, y: "-Leg * 0.75", diameter: CX.mm(4.5), depth: CX.mm(16))
        b.drill("Brace shelf screw", x: CX.zero, y: "Leg * 0.5", diameter: CX.mm(4), depth: CX.mm(12), target: .counterpart)
        b.outlines(x: ("-Bar Width / 2", "Bar Width / 2"), y: ("-Leg", DK.z), z: (DK.z, "Leg"))
        b.symbol(.side, [.coarse, .medium, .fine], .line((DK.z, DK.z), (DK.z, "-Leg")), .line((DK.z, DK.z), ("Leg", DK.z)), .line(("Leg * 0.85", DK.z), (DK.z, "-Leg * 0.85")))
        b.type("Folding Mechanism - Locking Brace 10\"", cost: 12.00, model: "FM-LB10")
        b.type("Folding Mechanism - Locking Brace 12\"", ["Leg": DK.inch(12)], numbers: ["Load": 120], cost: 14.00, model: "FM-LB12")
        b.type("Folding Mechanism - Heavy Brace 16\"", ["Leg": DK.inch(16), "Bar Width": DK.mm(32), "Metal": DK.mm(4)], numbers: ["Load": 250], cost: 22.00, model: "FM-HB16")
        return b.build()
    }

    static func telescopicMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Telescopic Mechanism", .motion, "Folding & Telescopic", "Nested-tube telescopic slide for extending tables, rails and lifts; locks at any length.")
        b.tags("telescopic", "extension", "slide", "tube", "extending", "nested")
        b.aliases("telescopic mechanisms", "telescoping tube", "extension tube", "telescopic slide", "telescopic rail")
        b.material("Outer Material", .steel)
        b.material("Inner Material", .chrome)
        b.length("Closed Length", DK.mm(400)); b.length("Stroke", DK.mm(300)); b.length("Outer Diameter", DK.mm(25)); b.length("Wall", DK.mm(1.5))
        b.length("Extension", DK.mm(150), instance: true, group: .placement)
        b.host([.rail, .bottom, .sidePanel, .anyPart], faces: [.bottom, .inside], align: .center, alignments: [.center, .left])
        b.pipe("Outer Tube", axis: .x, center: (DK.z, "Outer Diameter / 2"), outer: "Outer Diameter / 2", inner: "Outer Diameter / 2 - Wall", from: CX.zero, to: "Closed Length")
        b.using("Inner Material")
        b.rod("Inner Tube", axis: .x, center: (DK.z, "Outer Diameter / 2"), radius: "Outer Diameter / 2 - Wall - 0.0005 m", from: "Closed Length * 0.3", to: "Closed Length + min(Extension, Stroke)")
        b.using(nil)
        b.rod("Lock Knob", axis: .y, center: ("Closed Length - 0.015 m", "Outer Diameter / 2"), radius: CX.mm(6), from: "Outer Diameter / 2", to: "Outer Diameter / 2 + 0.012 m")
        for (n, x) in [("Base", "0.02 m"), ("End", "Closed Length + min(Extension, Stroke) - 0.02 m")] {
            b.box("\(n) Mount", x: ("\(x) - 0.015 m", "\(x) + 0.015 m"), y: ("-Outer Diameter / 2 - 0.006 m", "Outer Diameter / 2 + 0.006 m"), z: (DK.z, CX.mm(3)))
        }
        b.screwPair("Mount screw", spacing: "0.02 m", y: CX.zero, diameter: 4, depth: 14)
        b.outlines(x: (DK.z, "Closed Length + Extension"), y: ("-Outer Diameter / 2 - 0.006 m", "Outer Diameter / 2 + 0.006 m"), z: (DK.z, "Outer Diameter"))
        b.type("Telescopic Mechanism - 300 mm Stroke", cost: 18.00, model: "TM-300")
        b.type("Telescopic Mechanism - 500 mm Stroke", ["Closed Length": DK.mm(600), "Stroke": DK.mm(500), "Outer Diameter": DK.mm(30)], cost: 24.00, model: "TM-500")
        return b.build()
    }

    static func linearActuator() -> ComponentDefinition {
        var b = ComponentBuilder("Linear Actuator", .motion, "Electric Motion", "12 V electric linear actuator for lifts, recliners, hidden TV and flap openers; eye mounts both ends.")
        b.tags("linear actuator", "actuator", "electric", "motor", "12 v", "lift", "push rod")
        b.aliases("linear actuators", "electric actuator", "electric ram", "motorized actuator", "tv lift actuator", "electric piston")
        b.material("Body Material", .aluminum)
        b.material("Rod Material", .chrome)
        b.material("Motor Material", .matteBlack)
        b.length("Stroke", DK.mm(200)); b.length("Retracted Length", DK.mm(310)); b.length("Tube Diameter", DK.mm(30))
        b.length("Extension", 0, instance: true, group: .placement)
        b.number("Force", 1000, unit: "N", group: .data)
        b.number("Speed", 10, unit: "mm/s", group: .data)
        b.electrical(watts: 36, volts: 12, supply: "DC 12 V", cable: "2-wire, 1 m, with limit switches", connector: "2-pin")
        b.host([.sidePanel, .bottom, .back, .rail], faces: [.inside, .top], align: .bottom, alignments: [.bottom, .center])
        let c = "Tube Diameter / 2 + 0.004 m"
        b.pipe("Rear Eye", axis: .y, center: (CX.mm(8), c), outer: CX.mm(8), inner: CX.mm(4), from: CX.mm(-6), to: CX.mm(6))
        b.rod("Tube", axis: .x, center: (DK.z, c), radius: "Tube Diameter / 2", from: CX.mm(16), to: "Retracted Length - 0.03 m")
        b.using("Motor Material")
        b.rod("Motor", axis: .x, center: ("-Tube Diameter", c), radius: "Tube Diameter * 0.45", from: CX.mm(20), to: CX.mm(100))
        b.box("Gearbox", x: (CX.mm(16), CX.mm(40)), y: ("-Tube Diameter * 1.5", "Tube Diameter / 2"), z: (CX.mm(4), "Tube Diameter + 0.004 m"))
        b.using("Rod Material")
        b.rod("Push Rod", axis: .x, center: (DK.z, c), radius: "Tube Diameter * 0.3", from: "Retracted Length - 0.03 m", to: "Retracted Length - 0.012 m + min(Extension, Stroke)")
        b.using(nil)
        b.pipe("Front Eye", axis: .y, center: ("Retracted Length - 0.008 m + min(Extension, Stroke)", c), outer: CX.mm(8), inner: CX.mm(4), from: CX.mm(-6), to: CX.mm(6))
        b.drill("Actuator bracket screw", x: CX.mm(8), y: CX.mm(-12), diameter: CX.mm(4.5), depth: CX.mm(14))
        b.drill("Actuator bracket screw", x: CX.mm(8), y: CX.mm(12), diameter: CX.mm(4.5), depth: CX.mm(14))
        b.drill("Actuator bracket screw", x: "Retracted Length + Stroke", y: CX.zero, diameter: CX.mm(4.5), depth: CX.mm(14), target: .counterpart)
        b.outlines(x: (DK.z, "Retracted Length + Extension"), y: ("-Tube Diameter * 1.5", "Tube Diameter / 2"), z: (DK.z, "Tube Diameter + 0.008 m"))
        b.clearance(.box(name: "Stroke", x0: "Retracted Length", x1: "Retracted Length + Stroke", y0: "-0.01 m", y1: "0.01 m", z0: "0 m", z1: "Tube Diameter"))
        b.type("Linear Actuator - 100 mm, 1000 N", ["Stroke": DK.mm(100), "Retracted Length": DK.mm(210)], cost: 45.00, model: "LA-100-1000")
        b.type("Linear Actuator - 200 mm, 1000 N", cost: 52.00, model: "LA-200-1000", isDefault: true)
        b.type("Linear Actuator - 300 mm, 750 N", ["Stroke": DK.mm(300), "Retracted Length": DK.mm(410)], numbers: ["Force": 750], cost: 58.00, model: "LA-300-750")
        return b.build()
    }

    static func liftingColumn() -> ComponentDefinition {
        var b = ComponentBuilder("Electric Lifting Column", .motion, "Electric Motion", "Telescoping electric column (2 or 3 stages) for standing desks, TV lifts and adjustable tables.", frame: .plan)
        b.tags("lifting column", "electric", "desk", "standing desk", "telescopic", "24 v", "lift")
        b.aliases("electric lifting columns", "lift column", "desk leg motor", "telescopic column", "standing desk column", "tv lift column")
        b.material("Column Material", .matteBlack)
        b.material("Stage Material", .greyPlastic)
        b.length("Base Width", DK.mm(80)); b.length("Base Depth", DK.mm(60)); b.length("Retracted Height", DK.mm(560)); b.length("Stroke", DK.mm(500)); b.length("Stage Step", DK.mm(6))
        b.length("Extension", 0, instance: true, group: .placement)
        b.flag("Three Stage", false, instance: false, group: .dimensions)
        b.number("Load", 80, unit: "kg", group: .data)
        b.electrical(watts: 120, volts: 24, supply: "DC 24 V", cable: "Motor cable, 1.5 m", connector: "6-pin DIN")
        b.host([.floor, .bottom, .top], faces: [.top, .bottom], align: .center)
        let h = "Retracted Height", e = "min(Extension, Stroke)"
        b.box("Foot Plate", x: ("-Base Width", "Base Width"), y: ("-Base Depth * 1.2", "Base Depth * 1.2"), z: (DK.z, CX.mm(8)))
        b.box("Outer Stage", x: ("-Base Width / 2", "Base Width / 2"), y: ("-Base Depth / 2", "Base Depth / 2"), z: (CX.mm(8), "\(h) * 0.55"))
        b.using("Stage Material")
        b.box("Middle Stage", x: ("-Base Width / 2 + Stage Step", "Base Width / 2 - Stage Step"), y: ("-Base Depth / 2 + Stage Step", "Base Depth / 2 - Stage Step"),
              z: ("\(h) * 0.5", "if(Three Stage, \(h) * 0.78 + \(e) / 2, \(h) - 0.02 m + \(e))"))
        b.visibility = "Three Stage"
        b.box("Inner Stage", x: ("-Base Width / 2 + 2 * Stage Step", "Base Width / 2 - 2 * Stage Step"), y: ("-Base Depth / 2 + 2 * Stage Step", "Base Depth / 2 - 2 * Stage Step"),
              z: ("\(h) * 0.74 + \(e) / 2", "\(h) - 0.02 m + \(e)"))
        b.visibility = nil
        b.using(nil)
        b.box("Top Plate", x: ("-Base Width * 0.8", "Base Width * 0.8"), y: ("-Base Depth * 0.8", "Base Depth * 0.8"), z: ("\(h) - 0.02 m + \(e)", "\(h) + \(e)"))
        for (x, y) in [("-Base Width * 0.6", "-Base Depth * 0.6"), ("Base Width * 0.6", "-Base Depth * 0.6"), ("Base Width * 0.6", "Base Depth * 0.6"), ("-Base Width * 0.6", "Base Depth * 0.6")] {
            b.drill("Column top screw", x: x, y: y, diameter: CX.mm(6), depth: CX.mm(16), target: .counterpart)
        }
        b.symbol(.top, [.coarse, .medium, .fine], .rect(("-Base Width / 2", "-Base Depth / 2"), ("Base Width / 2", "Base Depth / 2")))
        b.symbol(.top, [.medium, .fine], .rect(("-Base Width", "-Base Depth * 1.2"), ("Base Width", "Base Depth * 1.2")))
        b.symbol(.face, [.coarse, .medium, .fine], .rect(("-Base Width / 2", DK.z), ("Base Width / 2", "\(h) + \(e)")))
        b.requires(.maxHostWeight("Load * 2.2"))
        b.type("Lifting Column - 2-Stage, 500 mm Stroke", cost: 120.00, model: "ELC-2-500")
        b.type("Lifting Column - 3-Stage, 650 mm Stroke", ["Retracted Height": DK.mm(580), "Stroke": DK.mm(650), "Base Width": DK.mm(90), "Base Depth": DK.mm(70)],
               flags: ["Three Stage": true], numbers: ["Load": 100, "Power": 150], cost: 165.00, model: "ELC-3-650")
        return b.build()
    }

    // MARK: Rotating

    static func rotatingPlatform() -> ComponentDefinition {
        var b = ComponentBuilder("Rotating Platform", .motion, "Rotating", "Round turntable platform on a ball-bearing ring: TV swivels, display turntables, corner shelves.", frame: .plan)
        b.tags("rotating", "turntable", "platform", "swivel", "lazy susan", "round")
        b.aliases("rotating platforms", "turntable platform", "tv swivel base", "rotating stand", "display turntable", "lazy susan platform")
        b.material("Platform Material", .maple)
        b.material("Bearing Material", .steel)
        b.length("Diameter", DK.inch(18)); b.length("Platform Thickness", DK.inch(0.75)); b.length("Bearing Height", DK.mm(9))
        b.number("Load", 300, unit: "lb", group: .data)
        b.host([.bottom, .shelf, .top, .floor], faces: [.top], align: .center)
        b.using("Bearing Material")
        b.pipe("Bearing Ring", axis: .z, center: (DK.z, DK.z), outer: "Diameter * 0.3", inner: "Diameter * 0.22", from: CX.zero, to: "Bearing Height")
        b.using(nil)
        b.revolve("Platform", profile: DK.pts([(DK.z, DK.z), ("Diameter / 2 - 0.004 m", DK.z), ("Diameter / 2", CX.mm(4)), ("Diameter / 2", "Platform Thickness - 0.004 m"),
                                               ("Diameter / 2 - 0.004 m", "Platform Thickness"), (DK.z, "Platform Thickness")]), base: "Bearing Height")
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            b.drill("Bearing screw", x: "Diameter * 0.26 * \(LX.num(cos(a)))", y: "Diameter * 0.26 * \(LX.num(sin(a)))", diameter: CX.mm(3.5), depth: CX.mm(12))
        }
        b.symbol(.top, [.coarse, .medium, .fine], .circle((DK.z, DK.z), "Diameter / 2"))
        b.symbol(.top, [.medium, .fine], dashed: true, .circle((DK.z, DK.z), "Diameter * 0.3"))
        b.symbol(.face, [.coarse, .medium, .fine], .rect(("-Diameter / 2", DK.z), ("Diameter / 2", "Bearing Height + Platform Thickness")))
        b.type("Rotating Platform - 12\"", ["Diameter": DK.inch(12)], numbers: ["Load": 200], cost: 28.00, model: "RP-12")
        b.type("Rotating Platform - 18\"", cost: 38.00, model: "RP-18", isDefault: true)
        b.type("Rotating Platform - 24\"", ["Diameter": DK.inch(24), "Platform Thickness": DK.inch(1)], numbers: ["Load": 400], cost: 52.00, model: "RP-24")
        return b.build()
    }

    static func swivelBearing() -> ComponentDefinition {
        var b = ComponentBuilder("Swivel Bearing Plate", .motion, "Rotating", "Square ball-bearing swivel plate between two parts (lazy susans, swivel tops, rotating stands).", frame: .plan)
        b.tags("swivel", "bearing", "plate", "lazy susan", "square", "ball bearing")
        b.aliases("swivel bearings", "lazy susan bearing", "square swivel plate", "turntable plate", "swivel plate")
        b.material("Finish Material", .zinc)
        b.length("Plate Size", DK.inch(6)); b.length("Height", DK.mm(8)); b.length("Plate Thickness", DK.mm(1.2))
        b.number("Load", 300, unit: "lb", group: .data)
        b.host([.bottom, .shelf, .top, .floor], faces: [.top, .bottom], align: .center)
        b.box("Bottom Plate", x: ("-Plate Size / 2", "Plate Size / 2"), y: ("-Plate Size / 2", "Plate Size / 2"), z: (DK.z, "Plate Thickness"))
        b.rod("Top Plate", axis: .z, center: (DK.z, DK.z), radius: "Plate Size * 0.6", from: "Height - Plate Thickness", to: "Height", segments: 4) // turned 45° to the bottom plate
        b.pipe("Race", axis: .z, center: (DK.z, DK.z), outer: "Plate Size * 0.42", inner: "Plate Size * 0.34", from: "Plate Thickness", to: "Height - Plate Thickness")
        for (x, y) in [("-Plate Size * 0.4", "-Plate Size * 0.4"), ("Plate Size * 0.4", "-Plate Size * 0.4"), ("Plate Size * 0.4", "Plate Size * 0.4"), ("-Plate Size * 0.4", "Plate Size * 0.4")] {
            b.drill("Swivel plate screw", x: x, y: y, diameter: CX.mm(3.5), depth: CX.mm(12))
        }
        b.symbol(.top, [.coarse, .medium, .fine], .rect(("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2")))
        b.symbol(.top, [.medium, .fine], dashed: true, .circle((DK.z, DK.z), "Plate Size * 0.42"))
        b.type("Swivel Bearing - 4\"", ["Plate Size": DK.inch(4), "Height": DK.mm(7)], numbers: ["Load": 200], cost: 3.50, model: "SB-4")
        b.type("Swivel Bearing - 6\"", cost: 5.00, model: "SB-6", isDefault: true)
        b.type("Swivel Bearing - 12\"", ["Plate Size": DK.inch(12), "Height": DK.mm(10), "Plate Thickness": DK.mm(1.5)], numbers: ["Load": 1000], cost: 12.00, model: "SB-12")
        return b.build()
    }

    static func turntableBearing() -> ComponentDefinition {
        var b = ComponentBuilder("Turntable Bearing", .motion, "Rotating", "Round aluminium ball-bearing ring for large turntables, round lazy susans and rotating tables.", frame: .plan)
        b.tags("turntable", "bearing", "ring", "round", "lazy susan", "rotating table")
        b.aliases("turntable bearings", "round lazy susan bearing", "bearing ring", "rotating table bearing", "300 mm turntable bearing")
        b.material("Finish Material", .aluminum)
        b.length("Outer Diameter", DK.mm(300)); b.length("Inner Diameter", DK.mm(220)); b.length("Height", DK.mm(9))
        b.number("Load", 400, unit: "lb", group: .data)
        b.host([.bottom, .shelf, .top, .floor], faces: [.top, .bottom], align: .center)
        b.pipe("Lower Ring", axis: .z, center: (DK.z, DK.z), outer: "Outer Diameter / 2", inner: "(Outer Diameter + Inner Diameter) / 4 - 0.002 m", from: CX.zero, to: "Height / 2")
        b.pipe("Upper Ring", axis: .z, center: (DK.z, DK.z), outer: "(Outer Diameter + Inner Diameter) / 4 + 0.002 m", inner: "Inner Diameter / 2", from: "Height / 2", to: "Height")
        for k in 0..<4 {
            let a = Double(k) * .pi / 2
            b.drill("Bearing screw", x: "(Outer Diameter / 2 - 0.008 m) * \(LX.num(cos(a)))", y: "(Outer Diameter / 2 - 0.008 m) * \(LX.num(sin(a)))", diameter: CX.mm(4), depth: CX.mm(12))
            b.drill("Bearing screw", x: "(Inner Diameter / 2 + 0.008 m) * \(LX.num(cos(a + .pi / 4)))", y: "(Inner Diameter / 2 + 0.008 m) * \(LX.num(sin(a + .pi / 4)))",
                    diameter: CX.mm(4), depth: CX.mm(12), target: .counterpart)
        }
        b.symbol(.top, [.coarse, .medium, .fine], .circle((DK.z, DK.z), "Outer Diameter / 2"), .circle((DK.z, DK.z), "Inner Diameter / 2"))
        b.type("Turntable Bearing - 300 mm", cost: 14.00, model: "TB-300")
        b.type("Turntable Bearing - 500 mm", ["Outer Diameter": DK.mm(500), "Inner Diameter": DK.mm(400)], numbers: ["Load": 600], cost: 24.00, model: "TB-500")
        b.type("Turntable Bearing - 200 mm", ["Outer Diameter": DK.mm(200), "Inner Diameter": DK.mm(140), "Height": DK.mm(8)], numbers: ["Load": 250], cost: 9.00, model: "TB-200")
        return b.build()
    }

    static func pivotMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Pivot Mechanism", .motion, "Rotating", "Top and bottom pivot pins for a panel that turns about its own axis (swivel mirrors, rotating TV panels, pivot shelves).")
        b.tags("pivot", "center pivot", "rotating panel", "swivel", "pin", "bearing")
        b.aliases("pivot mechanisms", "center pivot", "pivot pin set", "rotating panel pivot", "swivel mirror pivot")
        b.material("Finish Material", .stainless)
        b.length("Panel Height", DK.inch(30), instance: true); b.length("Pin Diameter", DK.mm(10)); b.length("Plate Width", DK.mm(40)); b.length("Plate Thickness", DK.mm(4))
        b.number("Load", 15, unit: "kg", group: .data)
        // On the panel's bottom edge: Z points down out of it, the axis is Z; the top pivot is Panel Height up (Z < 0).
        b.host([.door, .sidePanel, .shelf, .glass], faces: [.bottomEdge], align: .center)
        let top = "-Panel Height"
        b.box("Bottom Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Width / 4", "Plate Width / 4"), z: (DK.z, "Plate Thickness"))
        b.rod("Bottom Pin", axis: .z, center: (DK.z, DK.z), radius: "Pin Diameter / 2", from: "Plate Thickness", to: "Plate Thickness + 0.012 m")
        b.rod("Bottom Bushing", axis: .z, center: (DK.z, DK.z), radius: "Pin Diameter / 2 + 0.004 m", from: "Plate Thickness + 0.008 m", to: "Plate Thickness + 0.016 m")
        b.box("Top Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Width / 4", "Plate Width / 4"), z: ("\(top) - Plate Thickness", top))
        b.rod("Top Pin", axis: .z, center: (DK.z, DK.z), radius: "Pin Diameter / 2", from: "\(top) - Plate Thickness - 0.012 m", to: "\(top) - Plate Thickness")
        b.rod("Top Bushing", axis: .z, center: (DK.z, DK.z), radius: "Pin Diameter / 2 + 0.004 m", from: "\(top) - Plate Thickness - 0.016 m", to: "\(top) - Plate Thickness - 0.008 m")
        b.drill("Pivot plate screw", x: "-Plate Width / 3", y: CX.zero, diameter: CX.mm(4), depth: CX.mm(14))
        b.drill("Pivot plate screw", x: "Plate Width / 3", y: CX.zero, diameter: CX.mm(4), depth: CX.mm(14))
        b.drill("Pivot bushing hole", x: CX.zero, y: CX.zero, diameter: "Pin Diameter + 0.008 m", depth: CX.mm(16), target: .counterpart)
        b.symbol(.side, [.coarse, .medium, .fine], dashed: true, .line(("Plate Thickness + 0.016 m", DK.z), ("\(top) - Plate Thickness - 0.016 m", DK.z)))
        b.symbol(.face, [.medium, .fine], .circle((DK.z, DK.z), "Pin Diameter / 2 + 0.004 m"), .rect(("-Plate Width / 2", "-Plate Width / 4"), ("Plate Width / 2", "Plate Width / 4")))
        b.requires(.maxHostWeight("Load * 2.2"))
        b.type("Pivot Mechanism - 15 kg", cost: 16.00, model: "PM-15")
        b.type("Pivot Mechanism - 40 kg", ["Pin Diameter": DK.mm(14), "Plate Width": DK.mm(50), "Plate Thickness": DK.mm(5)], numbers: ["Load": 40], cost: 26.00, model: "PM-40")
        return b.build()
    }

    static func counterbalance() -> ComponentDefinition {
        var b = ComponentBuilder("Counterbalance Mechanism", .motion, "Struts & Springs", "Spring balance with a coiled tape for vertical-lift panels and doors: the panel stays where it's left.")
        b.tags("counterbalance", "spring balance", "vertical lift", "coil", "tape", "lift door")
        b.aliases("counterbalance mechanisms", "spring balance", "tape balance", "constant force spring", "vertical lift balance", "sash balance")
        b.material("Housing Material", .steel)
        b.material("Tape Material", .stainless)
        b.length("Housing Width", DK.mm(60)); b.length("Housing Height", DK.mm(90)); b.length("Housing Depth", DK.mm(22)); b.length("Travel", DK.inch(18))
        b.length("Extension", DK.inch(9), instance: true, group: .placement)
        b.number("Balance Load", 20, unit: "lb", group: .data)
        b.host([.sidePanel, .divider], faces: [.inside], align: .top, alignments: [.top], offsetY: DK.inch(1))
        b.box("Housing", x: ("-Housing Width / 2", "Housing Width / 2"), y: ("-Housing Height", DK.z), z: (DK.z, "Housing Depth"))
        b.rod("Coil", axis: .z, center: (DK.z, "-Housing Height * 0.45"), radius: "Housing Width * 0.4", from: "Housing Depth", to: "Housing Depth + 0.004 m")
        b.using("Tape Material")
        b.box("Tape", x: (CX.mm(-6), CX.mm(6)), y: ("-Housing Height - min(Extension, Travel)", "-Housing Height"), z: (CX.mm(8), CX.mm(9)))
        b.box("Hook", x: (CX.mm(-9), CX.mm(9)), y: ("-Housing Height - min(Extension, Travel) - 0.015 m", "-Housing Height - min(Extension, Travel)"), z: (CX.mm(5), CX.mm(12)))
        b.using(nil)
        b.screwPair("Balance screw", spacing: "Housing Width * 0.6", y: "-Housing Height * 0.15", diameter: 4, depth: 14)
        b.screwPair("Balance screw", spacing: "Housing Width * 0.6", y: "-Housing Height * 0.85", diameter: 4, depth: 14)
        b.drill("Hook screw", x: CX.zero, y: "-Housing Height - Travel", diameter: CX.mm(3.5), depth: CX.mm(12), target: .counterpart)
        b.outlines(x: ("-Housing Width / 2", "Housing Width / 2"), y: ("-Housing Height - Extension", DK.z), z: (DK.z, "Housing Depth + 0.004 m"))
        b.requires(.note("Pick the balance closest to the panel's weight; use one each side for panels over 24\" wide."))
        b.type("Counterbalance - 10-20 lb", cost: 26.00, model: "CB-1020")
        b.type("Counterbalance - 20-35 lb", ["Housing Width": DK.mm(75), "Housing Height": DK.mm(110)], numbers: ["Balance Load": 35], cost: 34.00, model: "CB-2035")
        return b.build()
    }
}
