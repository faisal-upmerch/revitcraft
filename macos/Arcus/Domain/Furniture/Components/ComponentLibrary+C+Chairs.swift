import Foundation
import ArcusGeometry

// COMPC: 14 Chair Hardware. Plan frame: bases, gas lifts and casters stand on the floor or sit in the base's socket
// (origin at the floor or the socket, Z up); seat hardware (swivel, tilt and recline mechanisms, plates, arm supports,
// back irons, stacking links) hangs under the seat with its origin on the seat's underside (-Y the front). Lumbar
// supports are face-based on the back's front face.

extension ComponentsC {
    static var chairs: [ComponentDefinition] {
        [chairLeg(), chairBase(), fiveStarBase(), gasLift(), swivelMechanism(), tiltMechanism(), chairRecline(), seatHeightAdjuster(), chairCaster(), chairGlide(),
         armrestSupport(), adjustableArmrest(), lumbarSupport(), chairHeadrest(), backConnector(), foldingChairHinge(), stackingConnector(), seatMountingPlate(), footrest()]
    }

    // MARK: Legs and bases

    /// Chair leg: a tapered wood leg, a straight metal tube leg or a bar-stool leg, on a hanger bolt and plate.
    static func chairLeg() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Leg", .chairs, "Legs & Bases", "Chair leg on a hanger bolt and mounting plate: tapered wood, straight metal tube or bar stool height.", frame: .plan)
        b.tags("chair", "leg", "tapered", "metal", "bar stool", "seat")
        b.aliases("dining chair leg", "replacement chair leg", "stool leg", "tapered chair leg", "17 3/4 in", "29 in", "450 mm")
        b.role(.legType)
        b.material("Leg Material", .oak)
        b.material("Plate Material", .zinc)
        b.length("Leg Height", CC.inch(17.75))
        b.length("Top Diameter", CC.mm(38))
        b.length("Bottom Diameter", CC.mm(24))
        b.flag("Metal Tube", false, instance: false, group: .dimensions)
        b.flag("Wood", false, formula: "not(Metal Tube)")
        b.host([.bottom, .form, .rail], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight], offsetX: CC.inch(1.5), offsetY: CC.inch(1.5))
        b.using("Plate Material")
        b.plate("Plate", width: "Top Diameter + 0.02 m", depth: "Top Diameter + 0.02 m", radius: CX.mm(4), z: ("-0.0025 m", "0 m"))
        b.using("Leg Material")
        b.shown("Wood") { $0.revolve("Leg", profile: ComponentKit.points([("0 m", "0 m"), ("Bottom Diameter / 2", "0 m"), ("Top Diameter / 2", "Leg Height - 0.0025 m"), ("0 m", "Leg Height - 0.0025 m")]),
                                     base: "-Leg Height") }
        b.shown("Metal Tube") { b in
            b.cyl("Tube", axis: .z, center: ("0 m", "0 m"), radius: "Top Diameter / 2", from: "-Leg Height + 0.008 m", to: "-0.0025 m", segments: 32)
            b.cyl("Glide Cap", axis: .z, center: ("0 m", "0 m"), radius: "Top Diameter / 2 - 0.001 m", from: "-Leg Height", to: "-Leg Height + 0.008 m", segments: 32)
        }
        b.using(nil)
        b.drill("Hanger bolt insert", x: "0 m", y: "0 m", diameter: CX.mm(10), depth: CX.mm(20))
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Top Diameter / 2"))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("-Top Diameter / 2", "0 m"), ("-Bottom Diameter / 2", "-Leg Height"), ("Bottom Diameter / 2", "-Leg Height"), ("Top Diameter / 2", "0 m")]), closed: true))
        b.type("Chair Leg - Tapered Wood 17 3/4\"", [:], cost: 9, model: "CL-TW18", isDefault: true)
        b.type("Chair Leg - Straight Metal 17 3/4\"", ["Top Diameter": CC.mm(25), "Bottom Diameter": CC.mm(25)], flags: ["Metal Tube": true], cost: 11, model: "CL-SM18")
        b.type("Chair Leg - Bar Stool Wood 29\"", ["Leg Height": CC.inch(29), "Top Diameter": CC.mm(42), "Bottom Diameter": CC.mm(28)], cost: 14, model: "CL-BW29")
        return b.build()
    }

    /// Disc chair base: a weighted steel disc and a column for lounge and bar chairs.
    static func chairBase() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Base", .chairs, "Legs & Bases", "Disc chair base: a weighted steel disc and a column with a top plate, for lounge chairs and bar stools.", frame: .plan)
        b.tags("chair", "base", "disc", "pedestal", "bar stool", "column")
        b.aliases("disc base", "round chair base", "pedestal chair base", "bar stool base", "trumpet base", "18 in", "20 in", "24 in")
        b.material("Finish Material", .chrome)
        b.length("Disc Diameter", CC.inch(18))
        b.length("Column Height", CC.inch(16))
        b.length("Column Diameter", CC.mm(50))
        b.length("Top Plate Size", CC.mm(200))
        b.host([.floor], faces: [.top], align: .center)
        b.revolve("Disc", profile: ComponentKit.points([("0 m", "0 m"), ("Disc Diameter / 2", "0 m"), ("Disc Diameter / 2", "0.006 m"), ("Disc Diameter * 0.3", "0.02 m"), ("0 m", "0.022 m")]))
        b.cyl("Column", axis: .z, center: ("0 m", "0 m"), radius: "Column Diameter / 2", from: "0.02 m", to: "Column Height - 0.006 m", segments: 32)
        b.box("Top Plate", x: ("-Top Plate Size / 2", "Top Plate Size / 2"), y: ("-Top Plate Size / 2", "Top Plate Size / 2"), z: ("Column Height - 0.006 m", "Column Height"))
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] { b.drill("Seat screw", x: "\(x) * Top Plate Size * 0.4", y: "\(y) * Top Plate Size * 0.4", diameter: CX.mm(6), depth: CX.mm(20), target: .counterpart) }
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Disc Diameter / 2"), .rect(("-Top Plate Size / 2", "-Top Plate Size / 2"), ("Top Plate Size / 2", "Top Plate Size / 2")))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("-Disc Diameter / 2", "0 m"), ("Disc Diameter / 2", "0 m"), ("Column Diameter / 2", "0.02 m"), ("Column Diameter / 2", "Column Height"),
                                                                ("-Column Diameter / 2", "Column Height"), ("-Column Diameter / 2", "0.02 m")]), closed: true))
        b.type("Chair Base - 18\" Disc Lounge", [:], cost: 79, model: "CB-18L")
        b.type("Chair Base - 20\" Disc Bar", ["Disc Diameter": CC.inch(20), "Column Height": CC.inch(26)], cost: 99, model: "CB-20B")
        b.type("Chair Base - 24\" Disc Table", ["Disc Diameter": CC.inch(24), "Column Height": CC.inch(27), "Column Diameter": CC.mm(76)], cost: 119, model: "CB-24T")
        return b.build()
    }

    /// Five-star base: five arms from a hub with the gas-lift taper socket and caster sockets (casters shown).
    static func fiveStarBase() -> ComponentDefinition {
        var b = ComponentBuilder("Five-Star Chair Base", .chairs, "Legs & Bases", "Five-arm swivel chair base: hub with a class 4 taper socket, caster sockets at 11 mm, casters shown.", frame: .plan)
        b.tags("chair", "base", "five star", "office chair", "caster", "swivel")
        b.aliases("5 star base", "office chair base", "star base", "chair spider", "600 mm", "650 mm", "700 mm", "24 in", "26 in", "28 in", "nylon", "aluminum")
        b.material("Base Material", .blackPlastic)
        b.material("Caster Material", .blackPlastic)
        b.length("Base Diameter", CC.mm(650))
        b.length("Hub Diameter", CC.mm(100))
        b.length("Arm Width", CC.mm(50))
        b.length("Arm Height", CC.mm(30))
        b.length("Caster Height", CC.mm(65))
        b.text("Taper", "Class 4 (50 mm)", group: .manufacturing)
        b.flag("Show Casters", true, group: .constraints)
        b.number("Load Capacity", 300, unit: "lb", group: .data)
        b.host([.floor], faces: [.top], align: .center)
        b.length("Arm Reach", 0, formula: "Base Diameter / 2 - 0.025 m")
        b.using("Base Material")
        b.revolve("Hub", profile: ComponentKit.points([("0.016 m", "0 m"), ("Hub Diameter / 2", "0 m"), ("Hub Diameter / 2", "Arm Height + 0.04 m"), ("0.016 m", "Arm Height + 0.04 m")]),
                  base: "Caster Height")
        for k in 0..<5 {
            let a = (90.0 + 72.0 * Double(k)) * .pi / 180
            let c = LX.num(cos(a)), s = LX.num(sin(a))
            func p(_ along: String, _ across: String) -> (String, String) { ("(\(along)) * \(c) - (\(across)) * \(s)", "(\(along)) * \(s) + (\(across)) * \(c)") }
            let arm = [p("Hub Diameter * 0.35", "-Arm Width / 2"), p("Arm Reach", "-Arm Width * 0.32"), p("Arm Reach + 0.02 m", "0 m"), p("Arm Reach", "Arm Width * 0.32"),
                       p("Hub Diameter * 0.35", "Arm Width / 2")]
            b.using("Base Material")
            b.extrusion("Arm \(k + 1)", profile: ComponentKit.points(arm), from: "Caster Height + 0.008 m", to: "Caster Height + 0.008 m + Arm Height")
            let tip = p("Arm Reach", "0 m")
            b.cyl("Socket \(k + 1)", axis: .z, center: tip, radius: CX.mm(12), from: "Caster Height", to: "Caster Height + 0.008 m")
            b.using("Caster Material")
            b.shown("Show Casters") { b in
                b.cyl("Caster \(k + 1) Hood", axis: .z, center: tip, radius: CX.mm(22), from: "Caster Height * 0.55", to: "Caster Height", segments: 20)
                for (w, off) in [("A", "-0.011 m"), ("B", "0.011 m")] {
                    b.cyl("Caster \(k + 1) Wheel \(w)", axis: .x, center: (tip.1, "Caster Height * 0.42"), radius: "Caster Height * 0.42",
                          from: "\(tip.0) + \(off) - 0.008 m", to: "\(tip.0) + \(off) + 0.008 m", segments: 24)
                }
            }
        }
        b.using(nil)
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Base Diameter / 2"), .circle(("0 m", "0 m"), "Hub Diameter / 2"))
        b.symbol(.top, [.coarse], .rect(("-Base Diameter / 2", "0 m"), ("Base Diameter / 2", "Caster Height + Arm Height + 0.04 m")))
        b.type("Five-Star Chair Base - 600 mm Nylon", ["Base Diameter": CC.mm(600)], cost: 29, model: "FSB-600N")
        b.type("Five-Star Chair Base - 650 mm Nylon", [:], cost: 35, model: "FSB-650N", isDefault: true)
        b.type("Five-Star Chair Base - 700 mm Aluminum", ["Base Diameter": CC.mm(700), "Arm Height": CC.mm(26)], texts: [:], numbers: ["Load Capacity": 400], cost: 79, model: "FSB-700A")
        return b.build()
    }

    /// Gas lift cylinder: a class 4 body with its taper, a telescoping dust cover and the piston rod; Extension raises it.
    static func gasLift() -> ComponentDefinition {
        var b = ComponentBuilder("Gas Lift Cylinder", .chairs, "Lift & Swivel", "Chair gas lift: class 4 tapered body, telescoping cover and piston rod; extends by its stroke.", frame: .plan)
        b.tags("chair", "gas lift", "cylinder", "pneumatic", "height", "office chair")
        b.aliases("gas cylinder", "chair cylinder", "pneumatic lift", "gas spring chair", "class 4", "100 mm stroke", "120 mm stroke", "150 mm stroke")
        b.material("Body Material", .matteBlack)
        b.material("Rod Material", .chrome)
        b.length("Stroke", CC.mm(120))
        b.length("Body Diameter", CC.mm(50))
        b.length("Minimum Length", CC.mm(290))
        b.length("Extension", CC.mm(60), instance: true, group: .placement, min: 0)
        b.length("Taper Length", CC.mm(30), group: .manufacturing)
        b.text("Class", "Class 4", group: .manufacturing)
        b.number("Load Rating", 250, unit: "lb", group: .data)
        b.length("Body Top", 0, formula: "Minimum Length - 0.06 m")
        b.host([.leg, .floor], faces: [.top], align: .center)
        b.requires(.note("Extension is between 0 and Stroke."))
        b.using("Body Material")
        b.revolve("Taper", profile: ComponentKit.points([("0 m", "0 m"), ("0.0138 m", "0 m"), ("0.0144 m", "Taper Length"), ("0 m", "Taper Length")]))
        b.cyl("Body", axis: .z, center: ("0 m", "0 m"), radius: "Body Diameter / 2", from: "Taper Length", to: "Body Top", segments: 32)
        b.cyl("Cover Lower", axis: .z, center: ("0 m", "0 m"), radius: "Body Diameter / 2 + 0.006 m", from: "Taper Length + 0.02 m", to: "(Taper Length + Body Top) / 2 + Extension / 2", segments: 32)
        b.cyl("Cover Upper", axis: .z, center: ("0 m", "0 m"), radius: "Body Diameter / 2 + 0.003 m", from: "(Taper Length + Body Top) / 2 + Extension / 2 - 0.02 m", to: "Body Top + Extension", segments: 32)
        b.using("Rod Material")
        b.revolve("Rod Taper", profile: ComponentKit.points([("0 m", "0 m"), ("0.0144 m", "0 m"), ("0.0138 m", "0.05 m"), ("0.006 m", "0.06 m"), ("0 m", "0.06 m")]), base: "Body Top + Extension")
        b.using(nil)
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Body Diameter / 2 + 0.006 m"))
        b.symbol(.top, [.coarse], .rect(("-Body Diameter / 2", "0 m"), ("Body Diameter / 2", "Minimum Length + Extension")))
        b.symbol(.top, [.medium, .fine], dashed: true, .line(("-Body Diameter", "Minimum Length + Stroke"), ("Body Diameter", "Minimum Length + Stroke")))
        b.type("Gas Lift Cylinder - 100 mm Stroke", ["Stroke": CC.mm(100), "Minimum Length": CC.mm(270), "Extension": CC.mm(50)], cost: 19, model: "GLC-100")
        b.type("Gas Lift Cylinder - 120 mm Stroke", [:], cost: 22, model: "GLC-120", isDefault: true)
        b.type("Gas Lift Cylinder - 150 mm Stroke", ["Stroke": CC.mm(150), "Minimum Length": CC.mm(340), "Extension": CC.mm(75)], cost: 26, model: "GLC-150")
        return b.build()
    }

    // MARK: Mechanisms under the seat

    /// The taper socket that takes a gas lift's rod, hanging below `z`.
    static func taperSocket(_ b: inout ComponentBuilder, z: String) {
        b.revolve("Taper Socket", profile: ComponentKit.points([("0.0144 m", "0 m"), ("0.022 m", "0 m"), ("0.026 m", "0.05 m"), ("0.0138 m", "0.05 m")]), base: "\(z) - 0.05 m")
    }

    /// Swivel plate: a seat plate bolted under the seat, a ball-bearing ring and the gas-lift taper socket.
    static func swivelMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Swivel Mechanism", .chairs, "Lift & Swivel", "Swivel plate under the seat: seat plate, ball-bearing ring and the gas-lift taper socket.", frame: .plan)
        b.tags("chair", "swivel", "plate", "bearing", "seat", "mechanism")
        b.aliases("swivel plate", "chair swivel", "seat swivel mechanism", "bar stool swivel", "200 x 250 mm", "8 x 10 in")
        b.material("Finish Material", .matteBlack)
        b.length("Plate Width", CC.mm(220))
        b.length("Plate Depth", CC.mm(270))
        b.length("Hole Spacing X", CC.mm(200))
        b.length("Hole Spacing Y", CC.mm(250))
        b.host([.bottom, .form], faces: [.bottom], align: .center)
        b.box("Seat Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Depth / 2", "Plate Depth / 2"), z: ("-0.003 m", "0 m"))
        b.cyl("Bearing Ring", axis: .z, center: ("0 m", "0 m"), radius: CX.mm(60), from: "-0.015 m", to: "-0.003 m", segments: 36)
        taperSocket(&b, z: "-0.015 m")
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] {
            b.drill("Seat bolt", x: "\(x) * Hole Spacing X / 2", y: "\(y) * Hole Spacing Y / 2", diameter: CX.mm(6), depth: CX.mm(16))
        }
        b.symbol(.face, [.coarse], .rect(("-Plate Width / 2", "-Plate Depth / 2"), ("Plate Width / 2", "Plate Depth / 2")), .circle(("0 m", "0 m"), "0.06 m"))
        b.symbol(.top, [.coarse], .rect(("-Plate Width / 2", "-0.065 m"), ("Plate Width / 2", "0 m")))
        b.type("Swivel Mechanism - 200 x 250 mm", [:], cost: 24, model: "SWM-200250")
        b.type("Swivel Mechanism - 160 x 200 mm", ["Plate Width": CC.mm(180), "Plate Depth": CC.mm(220), "Hole Spacing X": CC.mm(160), "Hole Spacing Y": CC.mm(200)], cost: 21, model: "SWM-160200")
        return b.build()
    }

    /// Tilt mechanism: housing on the gas lift, a seat plate that tilts back about the front (knee tilt) or the centre,
    /// tension knob and lock lever.
    static func tiltMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Tilt Mechanism", .chairs, "Mechanisms", "Office chair tilt: housing on the gas lift, tilting seat plate, tension knob and tilt-lock lever.", frame: .plan)
        b.tags("chair", "tilt", "mechanism", "office chair", "knee tilt", "tension")
        b.aliases("chair tilt mechanism", "knee tilt", "center tilt", "tilt control", "office chair mechanism", "200 x 250 mm")
        b.material("Finish Material", .matteBlack)
        b.length("Plate Width", CC.mm(220))
        b.length("Plate Depth", CC.mm(270))
        b.angle("Tilt Angle", 0, instance: true, group: .placement)
        b.number("Maximum Tilt", 15, unit: "°", group: .dimensions)
        b.flag("Knee Tilt", true, instance: false, group: .dimensions)
        b.length("Pivot Y", 0, formula: "if(Knee Tilt, -Plate Depth / 2 + 0.03 m, 0 m)")
        b.host([.bottom, .form], faces: [.bottom], align: .center)
        b.clearance(.box(name: "Tilt", x0: "-Plate Width / 2", x1: "Plate Width / 2", y0: "-Plate Depth / 2", y1: "Plate Depth / 2", z0: "-0.08 m", z1: "0 m"))
        b.link("Seat Plate", plane: .yz, ("-Plate Depth / 2", "-0.0015 m - (Pivot Y + Plate Depth / 2) * sin(Tilt Angle)"),
               ("Plate Depth / 2", "-0.0015 m - (Pivot Y - Plate Depth / 2) * sin(Tilt Angle)"), at: "0 m", width: CX.mm(3), thickness: "Plate Width")
        b.box("Housing", x: ("-0.06 m", "0.06 m"), y: ("-Plate Depth / 2 + 0.02 m", "Plate Depth / 2 - 0.04 m"), z: ("-0.06 m", "-0.005 m"))
        b.cyl("Pivot Shaft", axis: .x, center: ("Pivot Y", "-0.015 m"), radius: CX.mm(8), from: "-Plate Width / 2 + 0.01 m", to: "Plate Width / 2 - 0.01 m")
        b.cyl("Tension Knob", axis: .y, center: ("0 m", "-0.045 m"), radius: CX.mm(25), from: "-Plate Depth / 2 - 0.03 m", to: "-Plate Depth / 2 + 0.02 m", segments: 28)
        b.rodX("Tilt Lever", y: "-Plate Depth / 2 + 0.06 m", z: "-0.04 m", d: CX.mm(10), from: "0.06 m", to: "Plate Width / 2 + 0.06 m")
        b.cyl("Lever Paddle", axis: .x, center: ("-Plate Depth / 2 + 0.06 m", "-0.04 m"), radius: CX.mm(14), from: "Plate Width / 2 + 0.04 m", to: "Plate Width / 2 + 0.08 m", segments: 16)
        taperSocket(&b, z: "-0.06 m")
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] { b.drill("Seat bolt", x: "\(x) * 0.1 m", y: "\(y) * 0.125 m", diameter: CX.mm(6), depth: CX.mm(16)) }
        b.symbol(.face, [.coarse], .rect(("-Plate Width / 2", "-Plate Depth / 2"), ("Plate Width / 2", "Plate Depth / 2")), .line(("0.06 m", "-Plate Depth / 2 + 0.06 m"), ("Plate Width / 2 + 0.08 m", "-Plate Depth / 2 + 0.06 m")))
        b.symbol(.side, [.coarse], .rect(("-0.11 m", "-Plate Depth / 2"), ("0 m", "Plate Depth / 2")))
        b.type("Tilt Mechanism - Knee Tilt", [:], cost: 45, model: "TM-KT")
        b.type("Tilt Mechanism - Center Tilt", [:], flags: ["Knee Tilt": false], numbers: ["Maximum Tilt": 12], cost: 35, model: "TM-CT")
        return b.build()
    }

    /// Chair recline (synchro) mechanism: a housing and the back iron that reclines about the rear pivot.
    static func chairRecline() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Recline Mechanism", .chairs, "Mechanisms", "Synchro recline mechanism: housing on the gas lift and a back iron that reclines about the rear pivot, with lock.",
                                 frame: .plan)
        b.tags("chair", "recline", "synchro", "mechanism", "back", "office chair")
        b.aliases("recline mechanism", "synchro tilt", "synchronous mechanism", "multi lock mechanism", "chair back recline")
        b.material("Finish Material", .matteBlack)
        b.length("Plate Width", CC.mm(220))
        b.length("Plate Depth", CC.mm(270))
        b.length("Arm Length", CC.mm(200))
        b.length("Upright Length", CC.mm(330))
        b.angle("Recline Angle", 0, instance: true, group: .placement)
        b.number("Lock Positions", 5, group: .dimensions)
        b.number("Seat to Back Ratio", 2, unit: ":1", group: .data)
        b.length("Elbow Y", 0, formula: "Plate Depth / 2 - 0.02 m + Arm Length * cos(Recline Angle)")
        b.length("Elbow Z", 0, formula: "-0.05 m - Arm Length * sin(Recline Angle)")
        b.host([.bottom, .form], faces: [.bottom], align: .center)
        b.box("Seat Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Depth / 2", "Plate Depth / 2"), z: ("-0.003 m", "0 m"))
        b.box("Housing", x: ("-0.07 m", "0.07 m"), y: ("-Plate Depth / 2 + 0.02 m", "Plate Depth / 2"), z: ("-0.07 m", "-0.003 m"))
        b.link("Back Iron Arm", plane: .yz, ("Plate Depth / 2 - 0.02 m", "-0.05 m"), ("Elbow Y", "Elbow Z"), at: "0 m", width: CX.mm(14), thickness: CX.mm(60))
        b.link("Back Iron Upright", plane: .yz, ("Elbow Y", "Elbow Z"), ("Elbow Y + Upright Length * sin(Recline Angle)", "Elbow Z + Upright Length * cos(Recline Angle)"),
               at: "0 m", width: CX.mm(14), thickness: CX.mm(60))
        b.cyl("Rear Pivot", axis: .x, center: ("Plate Depth / 2 - 0.02 m", "-0.05 m"), radius: CX.mm(10), from: "-0.075 m", to: "0.075 m")
        b.rodX("Lock Lever", y: "-Plate Depth / 2 + 0.06 m", z: "-0.045 m", d: CX.mm(10), from: "-Plate Width / 2 - 0.06 m", to: "-0.07 m")
        taperSocket(&b, z: "-0.07 m")
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] { b.drill("Seat bolt", x: "\(x) * 0.1 m", y: "\(y) * 0.125 m", diameter: CX.mm(6), depth: CX.mm(16)) }
        b.drill("Back bolt", x: "0 m", y: "Elbow Y", diameter: CX.mm(8), depth: CX.mm(20), target: .counterpart)
        b.symbol(.face, [.coarse], .rect(("-Plate Width / 2", "-Plate Depth / 2"), ("Plate Width / 2", "Plate Depth / 2 + Arm Length")))
        b.symbol(.side, [.coarse], .polyline(ComponentKit.points([("-0.05 m", "Plate Depth / 2 - 0.02 m"), ("-0.05 m", "Plate Depth / 2 - 0.02 m + Arm Length"),
                                                                 ("Upright Length - 0.05 m", "Plate Depth / 2 - 0.02 m + Arm Length")]), closed: false))
        b.symbol(.side, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("-0.05 m", "Plate Depth / 2 - 0.02 m"), radius: "Upright Length", startDegrees: "60", sweepDegrees: "-25"))
        b.type("Chair Recline Mechanism - Synchro", [:], cost: 69, model: "CRM-SYN")
        b.type("Chair Recline Mechanism - Synchro Seat Slide", ["Plate Depth": CC.mm(300)], numbers: ["Lock Positions": 5], cost: 89, model: "CRM-SYNS")
        return b.build()
    }

    /// Seat height adjuster: a paddle lever on a bracket with the cable to the gas lift's release button.
    static func seatHeightAdjuster() -> ComponentDefinition {
        var b = ComponentBuilder("Seat Height Adjuster", .chairs, "Mechanisms", "Paddle lever on a bracket under the seat with the cable that presses the gas lift's release button.", frame: .plan)
        b.tags("chair", "height", "lever", "paddle", "gas lift", "release")
        b.aliases("height adjustment lever", "gas lift lever", "seat height paddle", "pneumatic release lever", "cable actuator")
        b.material("Finish Material", .blackPlastic)
        b.length("Lever Length", CC.mm(150))
        b.length("Cable Length", CC.mm(180))
        b.flag("Right Side", true, group: .placement)
        b.flag("Left Side", false, formula: "not(Right Side)")
        b.host([.bottom, .form], faces: [.bottom], align: .center)
        for (side, sign) in [("Right Side", ""), ("Left Side", "-")] {
            b.shown(side) { b in
                b.box("Bracket", x: ("\(sign)0.02 m", "\(sign)0.08 m"), y: ("-0.03 m", "0.03 m"), z: ("-0.004 m", "0 m"))
                b.rodX("Lever", y: "-0.01 m", z: "-0.012 m", d: CX.mm(9), from: sign.isEmpty ? "0.06 m" : "-0.06 m - Lever Length", to: sign.isEmpty ? "0.06 m + Lever Length" : "-0.06 m")
                b.roundedBar("Paddle", center: ("\(sign)(0.06 m + Lever Length)", "-0.01 m"), width: CX.mm(30), height: CX.mm(50), radius: CX.mm(10), from: "-0.02 m", to: "-0.006 m")
                b.wire("Cable", plane: .xz, [("\(sign)0.05 m", "-0.01 m"), ("\(sign)0.03 m", "-0.04 m"), ("0 m", "-Cable Length * 0.3")], at: "0 m", d: CX.mm(5))
            }
        }
        b.drill("Bracket screw", x: "0.05 m", y: "0 m", diameter: CX.mm(4), depth: CX.mm(14))
        b.symbol(.face, [.coarse], .line(("0.06 m", "-0.01 m"), ("0.06 m + Lever Length", "-0.01 m")), .rect(("0.02 m", "-0.03 m"), ("0.08 m", "0.03 m")))
        b.symbol(.top, [.coarse], .line(("0.06 m", "-0.012 m"), ("0.06 m + Lever Length", "-0.012 m")))
        b.type("Seat Height Adjuster - Paddle", [:], cost: 6, model: "SHA-P")
        b.type("Seat Height Adjuster - Long Paddle", ["Lever Length": CC.mm(190)], cost: 7, model: "SHA-LP")
        return b.build()
    }

    // MARK: Casters and glides

    /// Office chair caster: twin wheels under a hood on an 11 x 22 mm grip-ring stem.
    static func chairCaster() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Caster", .chairs, "Casters & Glides", "Twin-wheel chair caster under a hood on an 11 x 22 mm grip-ring stem; hard or soft wheels.", frame: .plan)
        b.tags("chair", "caster", "twin wheel", "office chair", "stem", "wheel")
        b.aliases("office chair wheel", "twin wheel caster", "chair wheel", "rollerblade caster", "11 mm stem", "50 mm", "60 mm", "65 mm", "2 in", "2 1/2 in")
        b.material("Wheel Material", .blackPlastic)
        b.material("Stem Material", .steel)
        b.length("Wheel Diameter", CC.mm(50))
        b.length("Stem Diameter", CC.mm(11))
        b.length("Stem Length", CC.mm(22))
        b.flag("Soft Wheels", false, instance: false, group: .data)
        b.flag("Locking", false, instance: false, group: .data)
        b.host([.leg, .bottom, .floor], faces: [.bottom], align: .center)
        b.requires(.note("Soft wheels for hard floors, hard wheels for carpet."))
        b.using("Stem Material")
        b.rodZ("Stem", x: "0 m", y: "0 m", d: "Stem Diameter", from: "0 m", to: "Stem Length")
        b.using("Wheel Material")
        b.cyl("Hood", axis: .z, center: ("0 m", "0.008 m"), radius: "Wheel Diameter * 0.45", from: "-Wheel Diameter * 0.45", to: "0 m", segments: 24)
        for (w, x) in [("A", "-0.012 m"), ("B", "0.012 m")] {
            b.cyl("Wheel \(w)", axis: .x, center: ("Wheel Diameter * 0.2", "-Wheel Diameter * 0.62"), radius: "Wheel Diameter / 2", from: "\(x) - 0.009 m", to: "\(x) + 0.009 m", segments: 28)
        }
        b.using(nil)
        b.drill("Stem socket", x: "0 m", y: "0 m", diameter: "Stem Diameter", depth: "Stem Length")
        b.symbol(.face, [.coarse], .rect(("-0.021 m", "Wheel Diameter * 0.2 - Wheel Diameter / 2"), ("0.021 m", "Wheel Diameter * 0.2 + Wheel Diameter / 2")))
        b.symbol(.top, [.coarse], .circle(("0 m", "-Wheel Diameter * 0.62"), "Wheel Diameter / 2"), .line(("0 m", "0 m"), ("0 m", "Stem Length")))
        b.type("Chair Caster - 50 mm Hard", [:], cost: 2.5, model: "CC-50H")
        b.type("Chair Caster - 60 mm Soft", ["Wheel Diameter": CC.mm(60)], flags: ["Soft Wheels": true], cost: 3.5, model: "CC-60S")
        b.type("Chair Caster - 65 mm Soft Locking", ["Wheel Diameter": CC.mm(65)], flags: ["Soft Wheels": true, "Locking": true], cost: 4.5, model: "CC-65SL")
        return b.build()
    }

    /// Chair glide: a stem glide in place of a caster, or a nail-in felt glide for wood legs.
    static func chairGlide() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Glide", .chairs, "Casters & Glides", "Chair glide: a stem glide in place of a caster, or a nail-in felt glide under a wood leg.", frame: .plan)
        b.tags("chair", "glide", "felt", "stem", "floor protector", "leg")
        b.aliases("chair glide", "stem glide", "nail in glide", "felt chair glide", "chair foot pad", "11 mm stem", "1 in")
        b.material("Glide Material", .blackPlastic)
        b.material("Felt Material", .felt)
        b.length("Glide Diameter", CC.mm(40))
        b.length("Glide Height", CC.mm(20))
        b.flag("Nail-In", false, instance: false, group: .dimensions)
        b.flag("Stem", false, formula: "not(Nail-In)")
        b.host([.leg, .bottom], faces: [.bottom], align: .center)
        b.shown("Stem") { b in
            b.rodZ("Stem", x: "0 m", y: "0 m", d: CX.mm(11), from: "0 m", to: "0.022 m")
            b.revolve("Glide", profile: ComponentKit.points([("0 m", "0 m"), ("Glide Diameter / 2", "0.004 m"), ("Glide Diameter * 0.45", "Glide Height"), ("0 m", "Glide Height")]), base: "-Glide Height")
        }
        b.shown("Nail-In") { b in
            b.rodZ("Nail", x: "0 m", y: "0 m", d: CX.mm(2.5), from: "0 m", to: "0.015 m")
            b.cyl("Cap", axis: .z, center: ("0 m", "0 m"), radius: "Glide Diameter / 2", from: "-Glide Height + 0.003 m", to: "0 m", segments: 28)
            b.using("Felt Material")
            b.cyl("Felt", axis: .z, center: ("0 m", "0 m"), radius: "Glide Diameter / 2 - 0.001 m", from: "-Glide Height", to: "-Glide Height + 0.003 m", segments: 28)
            b.using("Glide Material")
        }
        b.drill("Glide hole", x: "0 m", y: "0 m", diameter: CX.mm(11), depth: CX.mm(22))
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Glide Diameter / 2"))
        b.symbol(.top, [.coarse], .rect(("-Glide Diameter / 2", "-Glide Height"), ("Glide Diameter / 2", "0 m")))
        b.type("Chair Glide - Stem 11 mm", [:], cost: 1.5, model: "CG-S11")
        b.type("Chair Glide - Nail-In Felt 1\"", ["Glide Diameter": CC.inch(1), "Glide Height": CC.mm(6)], flags: ["Nail-In": true], cost: 0.4, model: "CG-NF1")
        return b.build()
    }

    // MARK: Arms, backs, heads

    /// Fixed T-arm support: a bracket under the seat, an upright and the arm pad.
    static func armrestSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Armrest Support", .chairs, "Arms & Backs", "Fixed T-arm: a steel bracket bolted under the seat, an upright and the arm pad.", frame: .plan)
        b.tags("chair", "armrest", "arm", "t-arm", "bracket", "office chair")
        b.aliases("chair arm", "fixed armrest", "t arm", "armrest bracket", "chair arm support")
        b.material("Frame Material", .matteBlack)
        b.material("Pad Material", ComponentFinish("Polyurethane - Black", .plastic, RGBColor(hex: 0x262628)))
        b.length("Arm Height", CC.inch(8))
        b.length("Pad Length", CC.mm(250))
        b.length("Pad Width", CC.mm(70))
        b.length("Bracket Length", CC.mm(220))
        b.length("Offset", CC.mm(60))
        b.flag("Right Arm", true, group: .placement)
        b.flag("Left Arm", false, formula: "not(Right Arm)")
        b.host([.bottom, .form], faces: [.bottom], align: .right, alignments: [.right, .left], mirroredPair: true)
        for (side, s) in [("Right Arm", ""), ("Left Arm", "-")] {
            let x = "\(s)Offset"
            b.shown(side) { b in
                b.using("Frame Material")
                b.box("Bracket", x: ("\(s)0 m", "\(x) - \(s)0.0 m"), y: ("-Bracket Length / 2", "Bracket Length / 2"), z: ("-0.008 m", "0 m"))
                b.box("Upright", x: ("\(x) - 0.012 m", "\(x) + 0.012 m"), y: ("-0.03 m", "0.03 m"), z: ("-0.008 m", "Arm Height"))
                b.using("Pad Material")
                b.roundedBar("Pad", center: (x, "-0.02 m"), width: "Pad Width", height: "Pad Length", radius: "Pad Width / 2 - 0.001 m", from: "Arm Height", to: "Arm Height + 0.025 m")
            }
        }
        b.using(nil)
        for y in ["-Bracket Length / 2 + 0.03 m", "Bracket Length / 2 - 0.03 m"] { b.drill("Arm bolt", x: "Offset / 3", y: y, diameter: CX.mm(6), depth: CX.mm(16)) }
        b.symbol(.face, [.coarse], .rect(("Offset - Pad Width / 2", "-0.02 m - Pad Length / 2"), ("Offset + Pad Width / 2", "-0.02 m + Pad Length / 2")))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("0 m", "0 m"), ("Offset", "0 m"), ("Offset", "Arm Height")]), closed: false))
        b.type("Armrest Support - Fixed T-Arm", [:], cost: 25, model: "AS-T")
        b.type("Armrest Support - Low T-Arm", ["Arm Height": CC.inch(6.5)], cost: 23, model: "AS-TL")
        return b.build()
    }

    /// Height-adjustable arm: a bracket, a two-piece column with a button and a pad; Arm Height moves it.
    static func adjustableArmrest() -> ComponentDefinition {
        var b = ComponentBuilder("Adjustable Armrest", .chairs, "Arms & Backs", "Height-adjustable arm (2D/3D/4D): bracket, telescoping column with button and a pivoting pad.", frame: .plan)
        b.tags("chair", "armrest", "adjustable", "height", "4d", "office chair")
        b.aliases("adjustable arm", "2d armrest", "3d armrest", "4d armrest", "height adjustable armrest", "multi function arm")
        b.material("Frame Material", .matteBlack)
        b.material("Pad Material", ComponentFinish("Polyurethane - Black", .plastic, RGBColor(hex: 0x262628)))
        b.length("Arm Height", CC.inch(8), instance: true, group: .placement, min: CC.inch(6.5), max: CC.inch(11))
        b.length("Pad Length", CC.mm(260))
        b.length("Pad Width", CC.mm(90))
        b.length("Offset", CC.mm(65))
        b.angle("Pad Swivel", 0, instance: true, group: .placement)
        b.text("Adjustments", "Height, width", group: .data)
        b.host([.bottom, .form], faces: [.bottom], align: .right, alignments: [.right, .left], mirroredPair: true)
        b.using("Frame Material")
        b.box("Bracket", x: ("0 m", "Offset"), y: ("-0.11 m", "0.11 m"), z: ("-0.008 m", "0 m"))
        b.box("Outer Column", x: ("Offset - 0.022 m", "Offset + 0.022 m"), y: ("-0.035 m", "0.035 m"), z: ("-0.008 m", "Arm Height * 0.55"))
        b.box("Inner Column", x: ("Offset - 0.017 m", "Offset + 0.017 m"), y: ("-0.03 m", "0.03 m"), z: ("Arm Height * 0.5", "Arm Height"))
        b.box("Button", x: ("Offset + 0.022 m", "Offset + 0.03 m"), y: ("-0.012 m", "0.012 m"), z: ("Arm Height * 0.45", "Arm Height * 0.52"))
        b.using("Pad Material")
        let ca = "cos(Pad Swivel)", sa = "sin(Pad Swivel)"
        b.link("Pad", plane: .xy, ("Offset - Pad Length / 2 * \(sa)", "-Pad Length / 2 * \(ca)"), ("Offset + Pad Length / 2 * \(sa)", "Pad Length / 2 * \(ca)"),
               at: "Arm Height + 0.0125 m", width: "Pad Width", thickness: CX.mm(25))
        b.using(nil)
        for y in ["-0.08 m", "0.08 m"] { b.drill("Arm bolt", x: "Offset / 3", y: y, diameter: CX.mm(6), depth: CX.mm(16)) }
        b.symbol(.face, [.coarse], .rect(("Offset - Pad Width / 2", "-Pad Length / 2"), ("Offset + Pad Width / 2", "Pad Length / 2")))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("0 m", "0 m"), ("Offset", "0 m"), ("Offset", "Arm Height")]), closed: false))
        b.type("Adjustable Armrest - 2D", [:], cost: 29, model: "AA-2D")
        b.type("Adjustable Armrest - 4D", ["Pad Length": CC.mm(270), "Pad Width": CC.mm(95)], texts: ["Adjustments": "Height, width, depth, swivel"], cost: 49, model: "AA-4D")
        return b.build()
    }

    /// Lumbar support: a curved pad on two vertical rails on the back's front face; Lumbar Height moves it.
    static func lumbarSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Lumbar Support Mechanism", .chairs, "Arms & Backs", "Height-adjustable lumbar pad on two vertical rails on the backrest's front face.")
        b.tags("chair", "lumbar", "support", "back", "ergonomic", "adjustable")
        b.aliases("lumbar support", "adjustable lumbar", "lumbar pad", "back support mechanism", "office chair lumbar")
        b.material("Pad Material", .blackPlastic)
        b.material("Rail Material", .greyPlastic)
        b.length("Pad Width", CC.mm(300))
        b.length("Pad Height", CC.mm(90))
        b.length("Bulge", CC.mm(20))
        b.length("Rail Length", CC.mm(160))
        b.length("Rail Spacing", CC.mm(220))
        b.length("Lumbar Height", CC.mm(0), instance: true, group: .placement, min: CC.mm(-50), max: CC.mm(50))
        b.host([.back, .form], faces: [.front], align: .center)
        b.using("Rail Material")
        for s in ["-", ""] { b.box("Rail", x: ("\(s)(Rail Spacing / 2) - 0.008 m", "\(s)(Rail Spacing / 2) + 0.008 m"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("0 m", "0.01 m")) }
        b.using("Pad Material")
        b.sweep("Pad", path: ComponentKit.points([("-Pad Width / 2", "0.01 m"), ("-Pad Width / 4", "0.01 m + Bulge * 0.8"), ("0 m", "0.01 m + Bulge"), ("Pad Width / 4", "0.01 m + Bulge * 0.8"),
                                                  ("Pad Width / 2", "0.01 m")]),
                profile: ComponentKit.rect(center: ("0 m", "0 m"), width: CX.mm(8), height: "Pad Height"), plane: .xz, at: "Lumbar Height")
        b.using(nil)
        for s in ["-", ""] {
            for y in ["-Rail Length / 2 + 0.02 m", "Rail Length / 2 - 0.02 m"] { b.drill("Rail screw", x: "\(s)(Rail Spacing / 2)", y: y, diameter: CX.mm(4), depth: CX.mm(12)) }
        }
        b.outlines(plan: .top, elevation: .face, x: ("-Pad Width / 2", "Pad Width / 2"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("0 m", "0.018 m + Bulge"))
        b.type("Lumbar Support Mechanism - Standard", [:], cost: 15, model: "LSM-STD")
        b.type("Lumbar Support Mechanism - Wide", ["Pad Width": CC.mm(360), "Rail Spacing": CC.mm(280)], cost: 18, model: "LSM-W")
        return b.build()
    }

    /// Chair headrest: two posts in sleeves above the back and a tilting pad; Headrest Height raises it.
    static func chairHeadrest() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Headrest Mechanism", .chairs, "Arms & Backs", "Office chair headrest: two posts in sleeves on the back's top, height and tilt adjustable pad.", frame: .plan)
        b.tags("chair", "headrest", "neck rest", "adjustable", "back", "office chair")
        b.aliases("headrest mechanism", "chair headrest", "neck support", "adjustable headrest", "clip on headrest")
        b.material("Frame Material", .matteBlack)
        b.material("Pad Material", .fabric)
        b.length("Post Spacing", CC.mm(160))
        b.length("Headrest Height", CC.mm(80), instance: true, group: .placement, min: 0, max: CC.mm(120))
        b.angle("Tilt Angle", 0, instance: true, group: .placement)
        b.length("Pad Width", CC.mm(280))
        b.length("Pad Height", CC.mm(130))
        b.host([.back, .form], faces: [.top], align: .center)
        b.using("Frame Material")
        for s in ["-", ""] {
            let x = "\(s)(Post Spacing / 2)"
            b.cyl("Sleeve", axis: .z, center: (x, "0 m"), radius: CX.mm(9), from: "-0.06 m", to: "0.01 m", segments: 16)
            b.rodZ("Post", x: x, y: "0 m", d: CX.mm(12), from: "-0.05 m", to: "Headrest Height + 0.04 m")
        }
        b.rodX("Hinge Bar", y: "0 m", z: "Headrest Height + 0.04 m", d: CX.mm(14), from: "-Post Spacing / 2 - 0.01 m", to: "Post Spacing / 2 + 0.01 m")
        b.using("Pad Material")
        b.link("Pad", plane: .yz, ("-0.02 m - 0.03 m * sin(Tilt Angle)", "Headrest Height + 0.04 m - Pad Height * 0.3"),
               ("-0.02 m - (Pad Height * 0.7) * sin(Tilt Angle)", "Headrest Height + 0.04 m + Pad Height * 0.7 * cos(Tilt Angle)"), at: "0 m", width: CX.mm(45), thickness: "Pad Width")
        b.using(nil)
        for s in ["-", ""] { b.drill("Sleeve hole", x: "\(s)(Post Spacing / 2)", y: "0 m", diameter: CX.mm(18), depth: CX.mm(60)) }
        b.symbol(.face, [.coarse], .rect(("-Pad Width / 2", "-0.045 m"), ("Pad Width / 2", "0.005 m")))
        b.symbol(.top, [.coarse], .rect(("-Pad Width / 2", "Headrest Height + 0.04 m - Pad Height * 0.3"), ("Pad Width / 2", "Headrest Height + 0.04 m + Pad Height * 0.7")))
        b.type("Chair Headrest Mechanism - Standard", [:], cost: 35, model: "CHM-STD")
        b.type("Chair Headrest Mechanism - Wide", ["Pad Width": CC.mm(320), "Post Spacing": CC.mm(200)], cost: 42, model: "CHM-W")
        return b.build()
    }

    /// Back iron: a steel bar that bolts under the seat and carries the backrest behind it.
    static func backConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Back Connector", .chairs, "Arms & Backs", "Back iron: a steel bar bolted under the seat at the back that curves up and carries the backrest.", frame: .plan)
        b.tags("chair", "back iron", "back", "connector", "spine", "bracket")
        b.aliases("back iron", "chair back bar", "chair spine", "back bracket", "j bar", "back connector")
        b.material("Finish Material", .matteBlack)
        b.length("Seat Reach", CC.mm(180))
        b.length("Back Rise", CC.mm(320))
        b.length("Setback", CC.mm(60))
        b.length("Bar Width", CC.mm(60))
        b.length("Bar Thickness", CC.mm(8))
        b.host([.bottom, .form], faces: [.bottom], align: .top, alignments: [.top])
        let path: [(String, String)] = [("-Seat Reach", "-Bar Thickness / 2"), ("0 m", "-Bar Thickness / 2"), ("Setback * 0.7", "-0.02 m"), ("Setback", "0.03 m"), ("Setback", "Back Rise")]
        b.sweep("Back Iron", path: ComponentKit.points(path), profile: ComponentKit.rect(width: "Bar Thickness", height: "Bar Width"), plane: .yz, at: "0 m")
        for y in ["-Seat Reach + 0.03 m", "-Seat Reach / 2"] { b.drill("Seat bolt", x: "0 m", y: y, diameter: CX.mm(6), depth: CX.mm(16)) }
        b.drill("Back bolt", x: "0 m", y: "Setback", diameter: CX.mm(6), depth: CX.mm(16), target: .counterpart)
        b.symbol(.face, [.coarse], .rect(("-Bar Width / 2", "-Seat Reach"), ("Bar Width / 2", "Setback + Bar Thickness / 2")))
        b.symbol(.side, [.coarse], .polyline(path.map { FamilyPoint($0.1, $0.0) }, closed: false))
        b.type("Chair Back Connector - Standard", [:], cost: 14, model: "CBC-STD")
        b.type("Chair Back Connector - Tall", ["Back Rise": CC.mm(420)], cost: 17, model: "CBC-T")
        return b.build()
    }

    /// Folding chair hinge: a scissor pivot between the front and back legs with a locking stay.
    static func foldingChairHinge() -> ComponentDefinition {
        var b = ComponentBuilder("Folding Chair Hinge", .chairs, "Folding & Stacking", "Scissor pivot between a folding chair's front and back legs, with the locking seat stay.")
        b.tags("chair", "folding", "hinge", "pivot", "scissor", "stay")
        b.aliases("folding chair pivot", "scissor hinge", "folding stool hinge", "chair folding bracket", "folding chair hardware")
        b.material("Finish Material", .zinc)
        b.length("Link Length", CC.mm(140))
        b.length("Link Width", CC.mm(22))
        b.angle("Open Angle", 60, instance: true, group: .placement)
        b.flag("Folded", false, group: .placement)
        b.parameter("Spread", .number, nil, formula: "if(Folded, 0.004, sin(Open Angle / 2))")
        b.host([.leg], faces: [.inside, .outside], align: .center, mirroredPair: true)
        b.cyl("Pivot Bolt", axis: .z, center: ("0 m", "0 m"), radius: CX.mm(5), from: "0 m", to: "0.014 m", segments: 16)
        b.link("Front Link", plane: .xy, ("-Link Length / 2 * Spread", "-Link Length / 2"), ("Link Length / 2 * Spread", "Link Length / 2"), at: "0.003 m", width: "Link Width", thickness: CX.mm(3))
        b.link("Back Link", plane: .xy, ("Link Length / 2 * Spread", "-Link Length / 2"), ("-Link Length / 2 * Spread", "Link Length / 2"), at: "0.008 m", width: "Link Width", thickness: CX.mm(3))
        b.link("Seat Stay", plane: .xy, ("-Link Length / 2 * Spread", "Link Length / 2"), ("Link Length / 2 * Spread + 0.04 m", "Link Length / 2 + 0.02 m"), at: "0.012 m", width: CX.mm(14), thickness: CX.mm(2.5))
        b.drill("Pivot hole", x: "0 m", y: "0 m", diameter: CX.mm(8), depth: CX.mm(25), through: true)
        b.symbol(.face, [.coarse], .line(("-Link Length / 2", "-Link Length / 2"), ("Link Length / 2", "Link Length / 2")), .line(("Link Length / 2", "-Link Length / 2"), ("-Link Length / 2", "Link Length / 2")))
        b.symbol(.top, [.coarse], .rect(("-Link Length / 2", "0 m"), ("Link Length / 2", "0.014 m")))
        b.type("Folding Chair Hinge - Standard", [:], cost: 5, model: "FCH-STD")
        b.type("Folding Chair Hinge - Heavy", ["Link Length": CC.mm(170), "Link Width": CC.mm(28)], cost: 7, model: "FCH-HD")
        return b.build()
    }

    /// Ganging (row) connector: a hook bracket under one chair's seat that drops into the next chair's slot plate.
    static func stackingConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Stacking Connector", .chairs, "Folding & Stacking", "Row ganging connector: a hook bracket under one chair's seat that drops into the next chair's slot plate.",
                                 frame: .plan)
        b.tags("chair", "ganging", "linking", "row", "stacking", "connector")
        b.aliases("chair ganging clip", "chair link", "row connector", "linking device", "stack chair connector")
        b.material("Finish Material", .chrome)
        b.length("Reach", CC.mm(45))
        b.length("Plate Length", CC.mm(80))
        b.host([.bottom, .rail, .leg], faces: [.bottom], align: .right, alignments: [.right, .left])
        b.box("Mount Plate", x: ("-0.02 m", "0 m"), y: ("-Plate Length / 2", "Plate Length / 2"), z: ("-0.003 m", "0 m"))
        b.wire("Hook", plane: .xz, [("-0.01 m", "-0.003 m"), ("Reach", "-0.003 m"), ("Reach", "-0.025 m")], at: "0 m", d: CX.mm(8))
        b.box("Slot Plate (Next Chair)", x: ("Reach - 0.015 m", "Reach + 0.015 m"), y: ("-0.02 m", "0.02 m"), z: ("-0.03 m", "-0.027 m"))
        for y in ["-Plate Length / 2 + 0.015 m", "Plate Length / 2 - 0.015 m"] { b.drill("Plate screw", x: "-0.01 m", y: y, diameter: CX.mm(4), depth: CX.mm(14)) }
        b.symbol(.face, [.coarse], .rect(("-0.02 m", "-Plate Length / 2"), ("0 m", "Plate Length / 2")), .line(("0 m", "0 m"), ("Reach", "0 m")))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("-0.01 m", "-0.003 m"), ("Reach", "-0.003 m"), ("Reach", "-0.025 m")]), closed: false))
        b.type("Chair Stacking Connector - Hook", [:], cost: 3.5, model: "CSC-H")
        b.type("Chair Stacking Connector - Long Hook", ["Reach": CC.mm(70)], cost: 4, model: "CSC-LH")
        return b.build()
    }

    /// Seat mounting plate: a steel plate with T-nuts at a mechanism's bolt pattern, set into the seat's underside.
    static func seatMountingPlate() -> ComponentDefinition {
        var b = ComponentBuilder("Seat Mounting Plate", .chairs, "Folding & Stacking", "Steel plate with four T-nuts at a mechanism's bolt pattern, screwed under the seat board.", frame: .plan)
        b.tags("chair", "seat", "plate", "t-nut", "mounting", "mechanism")
        b.aliases("seat plate", "t nut plate", "mechanism mounting plate", "chair seat plate", "200 x 250 mm", "160 x 200 mm", "M8")
        b.material("Finish Material", .zinc)
        b.length("Pattern X", CC.mm(200))
        b.length("Pattern Y", CC.mm(250))
        b.length("Plate Thickness", CC.mm(2.5))
        b.length("Seat Thickness", CC.mm(15), instance: true, group: .placement)
        b.text("Thread", "M8", group: .manufacturing)
        b.host([.bottom, .form], faces: [.bottom], align: .center)
        b.requires(.hostThickness(min: "0.012 m", max: nil))
        b.box("Plate", x: ("-Pattern X / 2 - 0.02 m", "Pattern X / 2 + 0.02 m"), y: ("-Pattern Y / 2 - 0.02 m", "Pattern Y / 2 + 0.02 m"), z: ("-Plate Thickness", "0 m"))
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] {
            let px = "\(x) * Pattern X / 2", py = "\(y) * Pattern Y / 2"
            b.cyl("T-Nut", axis: .z, center: (px, py), radius: CX.mm(5), from: "0 m", to: "Seat Thickness * 0.6", segments: 12)
            b.cyl("T-Nut Flange", axis: .z, center: (px, py), radius: CX.mm(11), from: "-Plate Thickness - 0.0015 m", to: "-Plate Thickness", segments: 16)
            b.drill("T-nut bore", x: px, y: py, diameter: CX.mm(10), depth: "Seat Thickness * 0.6")
        }
        b.symbol(.face, [.coarse], .rect(("-Pattern X / 2 - 0.02 m", "-Pattern Y / 2 - 0.02 m"), ("Pattern X / 2 + 0.02 m", "Pattern Y / 2 + 0.02 m")))
        b.symbol(.face, [.medium, .fine], .circle(("-Pattern X / 2", "-Pattern Y / 2"), "0.005 m"), .circle(("Pattern X / 2", "-Pattern Y / 2"), "0.005 m"),
                 .circle(("Pattern X / 2", "Pattern Y / 2"), "0.005 m"), .circle(("-Pattern X / 2", "Pattern Y / 2"), "0.005 m"))
        b.symbol(.top, [.coarse], .rect(("-Pattern X / 2 - 0.02 m", "-Plate Thickness"), ("Pattern X / 2 + 0.02 m", "0 m")))
        b.type("Seat Mounting Plate - 200 x 250 mm", [:], cost: 6, model: "SMP-200250")
        b.type("Seat Mounting Plate - 160 x 200 mm", ["Pattern X": CC.mm(160), "Pattern Y": CC.mm(200)], cost: 5, model: "SMP-160200")
        return b.build()
    }

    /// Foot ring for bar stools and drafting chairs: a ring on three spokes with a clamp collar on the gas lift.
    static func footrest() -> ComponentDefinition {
        var b = ComponentBuilder("Chair Footrest", .chairs, "Arms & Backs", "Foot ring for drafting chairs and stools: a ring on three spokes with a clamp collar on the gas lift.", frame: .plan)
        b.tags("chair", "footrest", "foot ring", "drafting chair", "bar stool", "ring")
        b.aliases("foot ring", "stool footrest", "drafting chair foot ring", "chair foot ring", "16 in", "18 in", "20 in")
        b.material("Finish Material", .chrome)
        b.length("Ring Diameter", CC.inch(18))
        b.length("Tube Diameter", CC.mm(20))
        b.length("Collar Diameter", CC.mm(65))
        b.length("Ring Height", CC.inch(0), instance: true, group: .placement)
        b.host([.leg], faces: [.any], align: .center)
        b.revolve("Ring", profile: ComponentKit.circle(center: ("Ring Diameter / 2", "0 m"), radius: "Tube Diameter / 2", segments: 12), base: "Ring Height")
        b.revolve("Collar", profile: ComponentKit.points([("0.027 m", "-0.03 m"), ("Collar Diameter / 2", "-0.03 m"), ("Collar Diameter / 2", "0.03 m"), ("0.027 m", "0.03 m")]), base: "Ring Height")
        for k in 0..<3 {
            let a = (90.0 + 120.0 * Double(k)) * .pi / 180
            let c = LX.num(cos(a)), s = LX.num(sin(a))
            b.strut("Spoke \(k + 1)", plane: .xy, ("Collar Diameter / 2 * \(c)", "Collar Diameter / 2 * \(s)"), ("Ring Diameter / 2 * \(c)", "Ring Diameter / 2 * \(s)"),
                    at: "Ring Height", d: CX.mm(14))
        }
        b.cyl("Clamp Knob", axis: .x, center: ("0 m", "Ring Height"), radius: CX.mm(12), from: "Collar Diameter / 2", to: "Collar Diameter / 2 + 0.03 m", segments: 16)
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Ring Diameter / 2 + Tube Diameter / 2"), .circle(("0 m", "0 m"), "Collar Diameter / 2"))
        b.symbol(.top, [.coarse], .rect(("-Ring Diameter / 2 - Tube Diameter / 2", "Ring Height - 0.03 m"), ("Ring Diameter / 2 + Tube Diameter / 2", "Ring Height + 0.03 m")))
        b.type("Chair Footrest - 16\" Ring", ["Ring Diameter": CC.inch(16)], cost: 29, model: "CFR-16")
        b.type("Chair Footrest - 18\" Ring", [:], cost: 32, model: "CFR-18", isDefault: true)
        b.type("Chair Footrest - 20\" Ring", ["Ring Diameter": CC.inch(20)], cost: 35, model: "CFR-20")
        return b.build()
    }
}
