import Foundation
import ArcusGeometry

// COMPC: 13 Sofa & Upholstery Hardware. Plan frame for what goes under or into a seat (legs, casters, swivel bases,
// recliner and sofa-bed mechanisms, springs, webbing, pocket units, cushion supports): origin on the seat frame's
// underside (or on its top face for springs and webbing), -Y the front. Recliner mechanisms are simplified linkages:
// side plates with their links drawn in the side (Y–Z) plane, opened by the Reclined instance flag. Frame hardware
// (connectors, clips, buttons, arm and headrest hinges) is face-based.

extension ComponentsC {
    static var sofas: [ComponentDefinition] {
        [sofaLeg(), sofaConnector(), sectionalConnector(), recliner(.pushBack), recliner(.manual), recliner(.electric), sofaBedMechanism(), pullOutSofaBed(),
         seatSpring(), zigzagSpring(), pocketSpringUnit(), elasticWebbing(), upholsteryClip(), upholsteryButton(), cushionSupport(), armrestHinge(),
         headrestMechanism(), sofaCaster(), swivelSofaBase()]
    }

    // MARK: Legs and connectors

    /// Sofa leg: a turned tapered or bun leg on a hanger bolt with its mounting plate.
    static func sofaLeg() -> ComponentDefinition {
        var b = ComponentBuilder("Sofa Leg", .sofas, "Legs & Connectors", "Turned sofa leg on a hanger bolt and mounting plate: tapered or bun.", frame: .plan)
        b.tags("sofa", "leg", "foot", "tapered", "bun", "upholstery")
        b.aliases("couch leg", "sofa foot", "bun foot", "tapered sofa leg", "replacement sofa leg", "4 in", "6 in", "3 in", "5/16 in hanger bolt")
        b.role(.legType)
        b.material("Leg Material", .walnut)
        b.material("Plate Material", .zinc)
        b.length("Leg Height", CC.inch(6))
        b.length("Top Diameter", CC.mm(45))
        b.length("Bottom Diameter", CC.mm(28))
        b.flag("Bun Foot", false, instance: false, group: .dimensions)
        b.flag("Tapered", false, formula: "not(Bun Foot)")
        b.number("Load per Leg", 250, unit: "lb", group: .data)
        b.host([.bottom, .rail, .form], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight, .center], offsetX: CC.inch(2), offsetY: CC.inch(2))
        b.using("Plate Material")
        b.plate("Plate", width: "Top Diameter + 0.02 m", depth: "Top Diameter + 0.02 m", radius: CX.mm(4), z: ("-0.002 m", "0 m"))
        b.using("Leg Material")
        b.shown("Tapered") { $0.revolve("Leg", profile: ComponentKit.points([("0 m", "0 m"), ("Bottom Diameter / 2", "0 m"), ("Bottom Diameter / 2 + 0.002 m", "0.006 m"),
                                                                          ("Top Diameter / 2", "Leg Height - 0.002 m"), ("0 m", "Leg Height - 0.002 m")]), base: "-Leg Height") }
        b.shown("Bun Foot") { $0.revolve("Bun", profile: ComponentKit.points([("0 m", "0 m"), ("Top Diameter * 0.35", "0 m"), ("Top Diameter * 0.55", "Leg Height * 0.2"),
                                                                           ("Top Diameter * 0.62", "Leg Height * 0.5"), ("Top Diameter * 0.55", "Leg Height * 0.8"),
                                                                           ("Top Diameter * 0.4", "Leg Height - 0.002 m"), ("0 m", "Leg Height - 0.002 m")]), base: "-Leg Height") }
        b.using(nil)
        b.drill("Hanger bolt insert", x: "0 m", y: "0 m", diameter: CX.mm(10), depth: CX.mm(20))
        for (x, y) in [("-1", "-1"), ("1", "1")] { b.drill("Plate screw", x: "\(x) * (Top Diameter / 2 + 0.005 m)", y: "\(y) * (Top Diameter / 2 + 0.005 m)", diameter: CX.mm(3.5), depth: CX.mm(16)) }
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Top Diameter / 2"))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("-Top Diameter / 2", "0 m"), ("-Bottom Diameter / 2", "-Leg Height"), ("Bottom Diameter / 2", "-Leg Height"), ("Top Diameter / 2", "0 m")]), closed: true))
        b.type("Sofa Leg - 4\" Tapered", ["Leg Height": CC.inch(4)], cost: 7, model: "SL-T4")
        b.type("Sofa Leg - 6\" Tapered", [:], cost: 8.5, model: "SL-T6", isDefault: true)
        b.type("Sofa Leg - 3\" Bun Foot", ["Leg Height": CC.inch(3), "Top Diameter": CC.mm(70)], flags: ["Bun Foot": true], cost: 9, model: "SL-B3")
        return b.build()
    }

    /// Slide-in back connector: a channel plate on the seat frame and a tongue plate on the back that drops into it.
    static func sofaConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Sofa Connector", .sofas, "Legs & Connectors", "Slide-in back connector: a channel plate on the seat frame and a tongue plate on the back frame.")
        b.tags("sofa", "connector", "back", "slide-in", "bracket", "knock-down")
        b.aliases("sofa back connector", "slide in sofa bracket", "couch back bracket", "sofa back bracket", "knock down sofa fitting")
        b.material("Finish Material", .steel)
        b.length("Plate Length", CC.mm(150))
        b.length("Plate Width", CC.mm(50))
        b.length("Plate Thickness", CC.mm(2.5))
        b.host([.rail, .form, .back], faces: [.back, .inside], align: .bottom, alignments: [.bottom, .center], count: ComponentCountRule(steps: [.init(upTo: 1.5, count: 2)], maximumCount: 3, inset: CC.inch(6)))
        b.box("Channel Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Length / 2", "Plate Length / 2"), z: ("0 m", "Plate Thickness"))
        for s in ["-", ""] { b.box("Channel Lip", x: ("\(s)(Plate Width / 2) - 0.004 m", "\(s)(Plate Width / 2) + 0.004 m"), y: ("-Plate Length / 2", "Plate Length / 2 - 0.02 m"), z: ("Plate Thickness", "3 * Plate Thickness")) }
        b.box("Tongue Plate", x: ("-Plate Width / 2 + 0.005 m", "Plate Width / 2 - 0.005 m"), y: ("-Plate Length / 2 + 0.02 m", "Plate Length / 2 + 0.03 m"), z: ("Plate Thickness", "2 * Plate Thickness"))
        for y in ["-Plate Length / 2 + 0.015 m", "Plate Length / 2 - 0.035 m"] { b.drill("Plate screw", x: "0 m", y: y, diameter: CX.mm(4.5), depth: CX.mm(20)) }
        b.drill("Tongue screw", x: "0 m", y: "Plate Length / 2 + 0.015 m", diameter: CX.mm(4.5), depth: CX.mm(20), target: .counterpart)
        b.outlines(plan: .top, elevation: .face, x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Length / 2", "Plate Length / 2 + 0.03 m"), z: ("0 m", "3 * Plate Thickness"))
        b.type("Sofa Connector - 150 mm", [:], cost: 3, model: "SC-150")
        b.type("Sofa Connector - 200 mm", ["Plate Length": CC.mm(200)], cost: 3.75, model: "SC-200")
        return b.build()
    }

    /// Sectional connector: two toothed plates under two neighbouring sections' bottom rails that hook together.
    static func sectionalConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Sectional Sofa Connector", .sofas, "Legs & Connectors", "Interlocking toothed plates under neighbouring sections' bottom rails that hold a sectional together.",
                                 frame: .plan)
        b.tags("sofa", "sectional", "connector", "clip", "alligator", "modular")
        b.aliases("sectional couch connector", "alligator clip", "sofa section clamp", "modular sofa connector", "sectional bracket")
        b.material("Finish Material", .zinc)
        b.length("Plate Length", CC.mm(115))
        b.length("Plate Width", CC.mm(60))
        b.length("Gap", CC.mm(0), instance: true, group: .placement, min: 0)
        b.host([.rail, .bottom], faces: [.bottom], align: .left, alignments: [.left, .right])
        b.requires(.note("One plate under each section, teeth facing; place on both ends of the joint."))
        for (n, x0, x1) in [("Left", "-Plate Length - Gap / 2", "-Gap / 2"), ("Right", "Gap / 2", "Plate Length + Gap / 2")] {
            b.box("\(n) Plate", x: (x0, x1), y: ("-Plate Width / 2", "Plate Width / 2"), z: ("-0.0025 m", "0 m"))
            b.drill("\(n) plate screw", x: "(\(x0) + \(x1)) / 2", y: "-Plate Width / 4", diameter: CX.mm(4.5), depth: CX.mm(16))
            b.drill("\(n) plate screw", x: "(\(x0) + \(x1)) / 2", y: "Plate Width / 4", diameter: CX.mm(4.5), depth: CX.mm(16))
        }
        for k in 0..<3 {
            let y = "-Plate Width / 2 + Plate Width * \(LX.num((Double(k) + 0.5) / 3))"
            b.box("Tooth L\(k + 1)", x: ("-Gap / 2 - 0.006 m", "-Gap / 2 + 0.014 m"), y: ("\(y) - 0.006 m", "\(y) + 0.002 m"), z: ("-0.012 m", "-0.0025 m"))
            b.box("Tooth R\(k + 1)", x: ("Gap / 2 - 0.014 m", "Gap / 2 + 0.006 m"), y: ("\(y) - 0.002 m", "\(y) + 0.006 m"), z: ("-0.012 m", "-0.0025 m"))
        }
        b.outlines(x: ("-Plate Length - Gap / 2", "Plate Length + Gap / 2"), y: ("-Plate Width / 2", "Plate Width / 2"), z: ("-0.012 m", "0 m"))
        b.type("Sectional Sofa Connector - Standard", [:], cost: 4, model: "SSC-STD")
        b.type("Sectional Sofa Connector - Wide", ["Plate Length": CC.mm(150), "Plate Width": CC.mm(80)], cost: 5.5, model: "SSC-W")
        return b.build()
    }

    // MARK: Recliners

    enum ReclinerKind { case pushBack, manual, electric }

    /// A recliner mechanism as a simplified linkage: on each side a base rail, a seat plate, a back post and the
    /// footrest's lazy-tong arms, closed or reclined (seat back, footrest out), and the footrest board across.
    static func recliner(_ kind: ReclinerKind) -> ComponentDefinition {
        let name: String, desc: String
        switch kind {
        case .pushBack: (name, desc) = ("Recliner Mechanism", "Wall-hugger (push-back) recliner mechanism: side plates with seat, back and footrest linkage, opened by leaning back.")
        case .manual: (name, desc) = ("Manual Recliner Mechanism", "Handle-release recliner mechanism: side linkage, footrest and a pull handle on a cable.")
        case .electric: (name, desc) = ("Electric Recliner Mechanism", "Power recliner mechanism: side linkage and footrest driven by a linear actuator, with a switch.")
        }
        var b = ComponentBuilder(name, .sofas, "Recliners", desc, frame: .plan)
        b.tags("sofa", "recliner", "mechanism", "footrest", "linkage", kind == .electric ? "power" : "manual")
        switch kind {
        case .pushBack: b.aliases("push back recliner", "wall hugger mechanism", "reclining sofa mechanism", "recliner hardware")
        case .manual: b.aliases("manual recliner", "handle recliner mechanism", "lever recliner", "pull cable recliner")
        case .electric: b.aliases("power recliner", "electric recliner", "motorized recliner mechanism", "lift motor recliner", "29 v")
        }
        b.role(.module)
        b.material("Frame Material", .matteBlack)
        b.material("Footrest Material", ComponentFinish("Plywood", .wood, RGBColor(hex: 0xCDAF7D)))
        if kind == .electric { b.material("Motor Material", .blackPlastic) }
        b.length("Mechanism Spacing", CC.inch(20))
        b.length("Seat Depth", CC.inch(20))
        b.length("Footrest Reach", CC.inch(18))
        b.length("Footrest Width", CC.inch(18))
        b.length("Back Height", CC.inch(10))
        b.flag("Reclined", false, group: .placement)
        b.number("Recline Angle", 45, unit: "°", group: .dimensions)
        b.number("Seat Weight Limit", 300, unit: "lb", group: .data)
        b.flag("Wall Hugger", kind == .pushBack, instance: false, group: .data)
        b.length("Foot Y", 0, formula: "if(Reclined, -Seat Depth / 2 - Footrest Reach, -Seat Depth / 2 + 0.02 m)")
        b.length("Foot Z", 0, formula: "if(Reclined, -0.06 m, -0.2 m)")
        b.length("Back Lean", 0, formula: "if(Reclined, Back Height * 0.7, Back Height * 0.2)")
        b.host([.bottom, .form, .rail], faces: [.bottom], align: .center)
        b.requires(.hostWidth(min: "Mechanism Spacing + 0.06 m", max: nil))
        b.requires(.note("Footrest Reach plus the seat must clear the room in front; wall huggers need 4\" behind."))
        b.clearance(.box(name: "Footrest travel", x0: "-Footrest Width / 2", x1: "Footrest Width / 2", y0: "-Seat Depth / 2 - Footrest Reach - 0.05 m", y1: "-Seat Depth / 2", z0: "-0.25 m", z1: "0 m"))
        b.using("Frame Material")
        for s in ["-", ""] {
            let x = "\(s)(Mechanism Spacing / 2)"
            b.link("Base Rail", plane: .yz, ("-Seat Depth / 2", "-0.22 m"), ("Seat Depth / 2", "-0.22 m"), at: x, width: CX.mm(30), thickness: CX.mm(5))
            b.link("Seat Plate", plane: .yz, ("-Seat Depth / 2", "-0.01 m"), ("Seat Depth / 2", "-0.01 m"), at: x, width: CX.mm(20), thickness: CX.mm(4))
            b.link("Front Link", plane: .yz, ("-Seat Depth / 4", "-0.22 m"), ("-Seat Depth / 3", "-0.01 m"), at: "\(x) + \(s)0.006 m", width: CX.mm(22), thickness: CX.mm(4))
            b.link("Rear Link", plane: .yz, ("Seat Depth / 3", "-0.22 m"), ("Seat Depth / 2.4", "-0.01 m"), at: "\(x) + \(s)0.006 m", width: CX.mm(22), thickness: CX.mm(4))
            b.link("Back Post", plane: .yz, ("Seat Depth / 2", "-0.01 m"), ("Seat Depth / 2 + Back Lean", "Back Height"), at: x, width: CX.mm(30), thickness: CX.mm(5))
            // Footrest lazy tongs: two crossing arms from the seat plate's front to the footrest bracket.
            b.link("Footrest Arm A", plane: .yz, ("-Seat Depth / 3", "-0.01 m"), ("Foot Y", "Foot Z"), at: "\(x) - \(s)0.006 m", width: CX.mm(18), thickness: CX.mm(4))
            b.link("Footrest Arm B", plane: .yz, ("-Seat Depth / 2", "-0.12 m"), ("Foot Y + 0.04 m", "Foot Z - 0.05 m"), at: "\(x) - \(s)0.012 m", width: CX.mm(18), thickness: CX.mm(4))
            for (py, pz) in [("-Seat Depth / 4", "-0.22 m"), ("Seat Depth / 3", "-0.22 m"), ("Seat Depth / 2", "-0.01 m")] {
                b.cyl("Pivot", axis: .x, center: (py, pz), radius: CX.mm(6), from: "\(x) - 0.012 m", to: "\(x) + 0.012 m", segments: 12)
            }
            b.drill("Mechanism bolt", x: x, y: "-Seat Depth / 3", diameter: CX.mm(8), depth: CX.mm(25))
            b.drill("Mechanism bolt", x: x, y: "Seat Depth / 3", diameter: CX.mm(8), depth: CX.mm(25))
        }
        b.box("Cross Tube", x: ("-Mechanism Spacing / 2", "Mechanism Spacing / 2"), y: ("Seat Depth / 6 - 0.012 m", "Seat Depth / 6 + 0.012 m"), z: ("-0.2 m", "-0.176 m"))
        b.using("Footrest Material")
        b.link("Footrest", plane: .yz, ("Foot Y", "Foot Z"), ("Foot Y + if(Reclined, 0.3 m, 0 m)", "Foot Z + if(Reclined, 0.03 m, 0.18 m)"), at: "0 m", width: CX.mm(12), thickness: "Footrest Width")
        b.using("Frame Material")
        switch kind {
        case .pushBack: break
        case .manual:
            b.box("Handle", x: ("Mechanism Spacing / 2 + 0.03 m", "Mechanism Spacing / 2 + 0.04 m"), y: ("-0.05 m", "0.05 m"), z: ("-0.12 m", "-0.05 m"))
            b.wire("Release Cable", plane: .yz, [("0 m", "-0.08 m"), ("Seat Depth / 6", "-0.15 m"), ("Seat Depth / 6", "-0.19 m")], at: "Mechanism Spacing / 2 + 0.02 m", d: CX.mm(5))
        case .electric:
            b.using("Motor Material")
            b.strut("Actuator Motor", plane: .yz, ("Seat Depth / 2 - 0.02 m", "-0.2 m"), ("Seat Depth / 2 - 0.16 m", "-0.17 m"), at: "0 m", d: CX.mm(70))
            b.strut("Actuator Tube", plane: .yz, ("Seat Depth / 2 - 0.16 m", "-0.17 m"), ("if(Reclined, -Seat Depth / 2, -Seat Depth / 4)", "-0.12 m"), at: "0 m", d: CX.mm(35))
            b.box("Power Supply", x: ("0.12 m", "0.24 m"), y: ("Seat Depth / 2 - 0.08 m", "Seat Depth / 2"), z: ("-0.22 m", "-0.18 m"))
            b.box("Switch", x: ("Mechanism Spacing / 2 + 0.02 m", "Mechanism Spacing / 2 + 0.035 m"), y: ("-0.04 m", "0.04 m"), z: ("-0.09 m", "-0.06 m"))
            b.electrical(watts: 50, volts: 29, supply: "AC 120 V adapter to DC 29 V", cable: "Motor cable and switch cable to the power supply; 6 ft cord", connector: "NEMA 1-15")
            b.using("Frame Material")
        }
        b.using(nil)
        b.symbol(.face, [.coarse], .rect(("-Mechanism Spacing / 2", "-Seat Depth / 2"), ("Mechanism Spacing / 2", "Seat Depth / 2")))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("-Footrest Width / 2", "-Seat Depth / 2 - Footrest Reach"), ("Footrest Width / 2", "-Seat Depth / 2")))
        b.symbol(.side, [.coarse], .rect(("-0.22 m", "-Seat Depth / 2"), ("0 m", "Seat Depth / 2")))
        switch kind {
        case .pushBack:
            b.type("Recliner Mechanism - Wall Hugger", [:], cost: 89, model: "RM-WH")
            b.type("Recliner Mechanism - Standard", ["Footrest Reach": CC.inch(20)], flags: ["Wall Hugger": false], cost: 79, model: "RM-STD")
        case .manual:
            b.type("Manual Recliner Mechanism - Handle", [:], cost: 99, model: "MRM-H")
            b.type("Manual Recliner Mechanism - Handle Wide", ["Mechanism Spacing": CC.inch(23), "Footrest Width": CC.inch(21)], cost: 109, model: "MRM-HW")
        case .electric:
            b.type("Electric Recliner Mechanism - Single Motor", [:], cost: 229, model: "ERM-1")
            b.type("Electric Recliner Mechanism - Single Motor Wall Hugger", [:], flags: ["Wall Hugger": true], cost: 249, model: "ERM-1WH")
        }
        return b.build()
    }

    // MARK: Sofa beds

    /// Tri-fold sofa bed mechanism: three hinged decks folded in the seat, or open flat with fold-out legs.
    static func sofaBedMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Sofa Bed Mechanism", .sofas, "Sofa Beds", "Tri-fold sofa bed mechanism: three hinged decks stowed in the seat or unfolded flat on fold-out legs.", frame: .plan)
        b.tags("sofa bed", "sleeper", "mechanism", "tri-fold", "pull-out bed", "guest bed")
        b.aliases("sleeper sofa mechanism", "sofa bed frame", "fold out bed mechanism", "three fold sofa bed", "twin", "full", "queen")
        b.role(.module)
        b.material("Frame Material", .steel)
        b.material("Deck Material", ComponentFinish("Mesh Deck - Black", .generic, RGBColor(hex: 0x3A3B3E)))
        b.length("Bed Width", CC.inch(54))
        b.length("Bed Length", CC.inch(72))
        b.length("Deck Height", CC.inch(14))
        b.length("Seat Depth", CC.inch(22))
        b.flag("Open", false, group: .placement)
        b.flag("Folded", false, formula: "not(Open)")
        b.host([.floor, .form], faces: [.top], align: .center)
        b.requires(.note("Needs Bed Length + 4\" free in front of the sofa when open."))
        b.clearance(.box(name: "Bed open", x0: "-Bed Width / 2", x1: "Bed Width / 2", y0: "Seat Depth / 2 - Bed Length", y1: "Seat Depth / 2", z0: "0 m", z1: "Deck Height"))
        let w = "Bed Width / 2"
        b.shown("Folded") { b in
            for k in 0..<3 {
                let z = "Deck Height - 0.03 m - 0.06 m * \(k)"
                b.using("Deck Material")
                b.box("Stowed Deck \(k + 1)", x: ("-\(w) + 0.02 m", "\(w) - 0.02 m"), y: ("-Seat Depth / 2 + 0.03 m", "Seat Depth / 2 - 0.03 m"), z: ("\(z) - 0.005 m", z))
                b.using("Frame Material")
                for s in ["-", ""] { b.rodY("Stowed Rail \(k + 1)", x: "\(s)(\(w) - 0.015 m)", z: "\(z) - 0.012 m", d: CX.mm(20), from: "-Seat Depth / 2 + 0.02 m", to: "Seat Depth / 2 - 0.02 m") }
            }
        }
        b.shown("Open") { b in
            let segs = [("Seat Depth / 2", "Seat Depth / 2 - Bed Length / 3"), ("Seat Depth / 2 - Bed Length / 3", "Seat Depth / 2 - Bed Length * 2 / 3"),
                        ("Seat Depth / 2 - Bed Length * 2 / 3", "Seat Depth / 2 - Bed Length")]
            for (k, y) in segs.enumerated() {
                b.using("Deck Material")
                b.box("Deck \(k + 1)", x: ("-\(w) + 0.02 m", "\(w) - 0.02 m"), y: (y.1, y.0), z: ("Deck Height - 0.005 m", "Deck Height"))
                b.using("Frame Material")
                for s in ["-", ""] { b.rodY("Side Rail \(k + 1)", x: "\(s)(\(w) - 0.015 m)", z: "Deck Height - 0.012 m", d: CX.mm(20), from: y.1, to: y.0) }
                b.rodX("Cross Rail \(k + 1)", y: y.1, z: "Deck Height - 0.012 m", d: CX.mm(20), from: "-\(w)", to: w)
            }
            for (y, n) in [("Seat Depth / 2 - Bed Length * 2 / 3 + 0.03 m", "Middle"), ("Seat Depth / 2 - Bed Length + 0.03 m", "Foot")] {
                b.wire("\(n) Leg", plane: .xz, [("-\(w) + 0.04 m", "Deck Height - 0.02 m"), ("-\(w) + 0.04 m", "0 m"), ("\(w) - 0.04 m", "0 m"), ("\(w) - 0.04 m", "Deck Height - 0.02 m")],
                       at: y, d: CX.mm(20))
            }
        }
        b.using(nil)
        for s in ["-", ""] { b.drill("Mounting bolt", x: "\(s)(\(w) + 0.01 m)", y: "0 m", diameter: CX.mm(8), depth: CX.mm(25), target: .counterpart) }
        b.symbol(.face, [.coarse], .rect(("-\(w)", "-Seat Depth / 2"), (w, "Seat Depth / 2")))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("-\(w)", "Seat Depth / 2 - Bed Length"), (w, "Seat Depth / 2")))
        b.symbol(.top, [.coarse], .rect(("-\(w)", "0 m"), (w, "Deck Height")))
        b.type("Sofa Bed Mechanism - Twin", ["Bed Width": CC.inch(38)], cost: 249, model: "SBM-T")
        b.type("Sofa Bed Mechanism - Full", [:], cost: 289, model: "SBM-F", isDefault: true)
        b.type("Sofa Bed Mechanism - Queen", ["Bed Width": CC.inch(60), "Bed Length": CC.inch(74)], cost: 329, model: "SBM-Q")
        return b.build()
    }

    /// Pull-out (trundle) sofa bed frame: a slatted deck on casters that rolls out from under the seat and rises.
    static func pullOutSofaBed() -> ComponentDefinition {
        var b = ComponentBuilder("Pull-Out Sofa Bed Frame", .sofas, "Sofa Beds", "Roll-out sofa bed frame: a slatted deck on casters that pulls out from under the seat.", frame: .plan)
        b.tags("sofa bed", "pull-out", "trundle", "roll-out", "slats", "caster")
        b.aliases("roll out sofa bed", "pull out bed frame", "trundle sofa bed", "click clack alternative", "twin", "full")
        b.role(.module)
        b.material("Frame Material", .steel)
        b.material("Slat Material", .beech)
        b.material("Caster Material", .blackPlastic)
        b.length("Deck Width", CC.inch(52))
        b.length("Deck Depth", CC.inch(30))
        b.length("Deck Height", CC.inch(12))
        b.length("Pull Out", 0, instance: true, group: .placement, min: 0)
        b.number("Slats", 9, group: .dimensions)
        b.host([.floor, .bottom, .bay], faces: [.top], align: .center)
        b.clearance(.box(name: "Pull-out travel", x0: "-Deck Width / 2", x1: "Deck Width / 2", y0: "-Deck Depth - Pull Out", y1: "0 m", z0: "0 m", z1: "Deck Height"))
        let w = "Deck Width / 2", y0 = "-Deck Depth / 2 - Pull Out", y1 = "Deck Depth / 2 - Pull Out"
        b.using("Frame Material")
        for s in ["-", ""] {
            b.box("Side Rail", x: ("\(s)(\(w)) - 0.015 m", "\(s)(\(w)) + 0.015 m"), y: (y0, y1), z: ("Deck Height - 0.06 m", "Deck Height"))
            for (t, y) in [("Front", "\(y0) + 0.04 m"), ("Back", "\(y1) - 0.04 m")] {
                b.rodZ("\(t) Leg", x: "\(s)(\(w) - 0.04 m)", y: y, d: CX.mm(25), from: "0.05 m", to: "Deck Height - 0.06 m")
                b.using("Caster Material")
                b.cyl("\(t) Caster", axis: .x, center: (y, "0.025 m"), radius: "0.025 m", from: "\(s)(\(w) - 0.04 m) - 0.01 m", to: "\(s)(\(w) - 0.04 m) + 0.01 m")
                b.using("Frame Material")
            }
        }
        b.box("Front Rail", x: ("-\(w)", w), y: (y0, "\(y0) + 0.03 m"), z: ("Deck Height - 0.06 m", "Deck Height"))
        b.box("Back Rail", x: ("-\(w)", w), y: ("\(y1) - 0.03 m", y1), z: ("Deck Height - 0.06 m", "Deck Height"))
        b.using("Slat Material")
        for k in 1...12 {
            let v: String? = k <= 6 ? nil : "Show Slat \(k)"
            if let v { b.countFlag(v, "Slats >= \(k)") }
            let x = "-\(w) + 0.03 m + (Deck Width - 0.06 m) * (\(k) - 0.5) / Slats"
            b.shown(v) { $0.box("Slat \(k)", x: ("\(x) - 0.03 m", "\(x) + 0.03 m"), y: ("\(y0) + 0.03 m", "\(y1) - 0.03 m"), z: ("Deck Height - 0.03 m", "Deck Height - 0.02 m")) }
        }
        b.using(nil)
        b.outlines(x: ("-\(w)", w), y: ("-Deck Depth / 2", "Deck Depth / 2"), z: ("0 m", "Deck Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("-\(w)", "-Deck Depth * 1.5"), (w, "-Deck Depth / 2")))
        b.type("Pull-Out Sofa Bed Frame - Twin", ["Deck Width": CC.inch(38)], numbers: ["Slats": 7], cost: 159, model: "PSB-T")
        b.type("Pull-Out Sofa Bed Frame - Full", [:], numbers: ["Slats": 9], cost: 189, model: "PSB-F", isDefault: true)
        return b.build()
    }

    // MARK: Springs and suspension

    /// Coil seat spring (hourglass), stapled or clipped to the seat base.
    static func seatSpring() -> ComponentDefinition {
        var b = ComponentBuilder("Seat Spring", .sofas, "Springs & Suspension", "Hourglass coil seat spring for hand-tied or clipped seat bases.", frame: .plan)
        b.tags("sofa", "spring", "coil", "seat", "upholstery", "hand-tied")
        b.aliases("coil spring", "upholstery coil spring", "hourglass spring", "seat coil", "4 in", "5 in", "6 in", "9 gauge")
        b.material("Finish Material", .steel)
        b.length("Free Height", CC.inch(5))
        b.length("End Diameter", CC.mm(90))
        b.length("Waist Diameter", CC.mm(55))
        b.length("Wire Diameter", CC.mm(3.5))
        b.text("Wire Gauge", "9 ga", group: .manufacturing)
        b.host([.form, .bottom, .rail], faces: [.top], align: .center)
        let ts: [Double] = [0, 0.18, 0.36, 0.5, 0.64, 0.82, 1]
        for (k, t) in ts.enumerated() {
            let shape = abs(t - 0.5) * 2 // 1 at the ends, 0 at the waist
            let r = "(Waist Diameter + (End Diameter - Waist Diameter) * \(LX.num(shape * shape))) / 2"
            b.revolve("Coil \(k + 1)", profile: ComponentKit.circle(center: (r, "0 m"), radius: "Wire Diameter / 2", segments: 8), base: "Wire Diameter / 2 + (Free Height - Wire Diameter) * \(LX.num(t))")
        }
        for k in 0..<(ts.count - 1) {
            b.strut("Turn \(k + 1)", plane: .xz, ("(Waist Diameter + (End Diameter - Waist Diameter) * \(LX.num(pow(abs(ts[k] - 0.5) * 2, 2)))) / 2", "Wire Diameter / 2 + (Free Height - Wire Diameter) * \(LX.num(ts[k]))"),
                    ("-(Waist Diameter + (End Diameter - Waist Diameter) * \(LX.num(pow(abs(ts[k + 1] - 0.5) * 2, 2)))) / 2", "Wire Diameter / 2 + (Free Height - Wire Diameter) * \(LX.num(ts[k + 1]))"),
                    at: "0 m", d: "Wire Diameter", segments: 8)
        }
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "End Diameter / 2"), .circle(("0 m", "0 m"), "Waist Diameter / 2"))
        b.symbol(.top, [.coarse], .polyline(ComponentKit.points([("-End Diameter / 2", "0 m"), ("-Waist Diameter / 2", "Free Height / 2"), ("-End Diameter / 2", "Free Height"),
                                                                ("End Diameter / 2", "Free Height"), ("Waist Diameter / 2", "Free Height / 2"), ("End Diameter / 2", "0 m")]), closed: true))
        b.type("Seat Spring - 4\"", ["Free Height": CC.inch(4), "End Diameter": CC.mm(80)], cost: 0.9, model: "SS-4")
        b.type("Seat Spring - 5\"", [:], cost: 1.0, model: "SS-5", isDefault: true)
        b.type("Seat Spring - 6\"", ["Free Height": CC.inch(6), "End Diameter": CC.mm(100), "Waist Diameter": CC.mm(60)], cost: 1.15, model: "SS-6")
        return b.build()
    }

    /// Zigzag (sinuous) spring across a seat or back frame, with its end clips.
    static func zigzagSpring() -> ComponentDefinition {
        var b = ComponentBuilder("Zigzag Spring", .sofas, "Springs & Suspension", "Sinuous (zigzag) spring run front to back across a seat frame, with an end clip at each rail.", frame: .plan)
        b.tags("sofa", "spring", "zigzag", "sinuous", "no-sag", "seat")
        b.aliases("sinuous spring", "no sag spring", "s spring", "serpentine spring", "20 in", "22 in", "24 in", "9 gauge", "11 gauge")
        b.material("Finish Material", .steel)
        b.material("Clip Material", .zinc)
        b.length("Spring Length", CC.inch(22))
        b.length("Spring Width", CC.mm(55))
        b.length("Wire Diameter", CC.mm(3.8))
        b.length("Arch", CC.mm(25))
        b.text("Wire Gauge", "9 ga", group: .manufacturing)
        b.host([.rail, .form], faces: [.top], align: .center, count: ComponentCountRule(steps: [], maximumCount: 12, inset: CC.inch(2)))
        b.requires(.note("Space springs about 4\" to 5\" apart across the seat."))
        let waves = 14
        var pts: [(String, String)] = []
        for k in 0...waves {
            let t = Double(k) / Double(waves)
            pts.append(("\(k % 2 == 0 ? "-" : "")Spring Width / 2", "-Spring Length / 2 + Spring Length * \(LX.num(t))"))
        }
        // Planar zigzag, raised by the arch in the middle: two runs at the arch's quarter heights would need a 3D path,
        // so the arch is shown by the clips' height difference.
        b.wire("Spring", plane: .xy, pts, at: "Arch", d: "Wire Diameter", segments: 8)
        b.using("Clip Material")
        for s in ["-", ""] {
            b.box("End Clip", x: ("-0.012 m", "0.012 m"), y: ("\(s)(Spring Length / 2) - 0.012 m", "\(s)(Spring Length / 2) + 0.012 m"), z: ("0 m", "0.012 m"))
            b.wire("End Hook", plane: .yz, [("\(s)(Spring Length / 2)", "0.012 m"), ("\(s)(Spring Length / 2 - 0.03 m)", "Arch")], at: "0 m", d: "Wire Diameter", segments: 8)
            b.drill("Clip nail", x: "0 m", y: "\(s)(Spring Length / 2)", diameter: CX.mm(2.5), depth: CX.mm(20))
        }
        b.using(nil)
        b.symbol(.face, [.coarse], .polyline(ComponentKit.points(pts), closed: false))
        b.symbol(.top, [.coarse], .line(("-Spring Width / 2", "0 m"), ("Spring Width / 2", "Arch")))
        for (l, cost) in [(20.0, 2.1), (22, 2.3), (24, 2.5)] {
            b.type("Zigzag Spring - \(Int(l))\"", ["Spring Length": CC.inch(l)], cost: cost, model: "ZZ-\(Int(l))")
        }
        return b.build()
    }

    /// Pocket spring unit: a grid of fabric-pocketed coils for cushions and seats.
    static func pocketSpringUnit() -> ComponentDefinition {
        var b = ComponentBuilder("Pocket Spring Unit", .sofas, "Springs & Suspension", "Pocketed coil unit: a grid of coils in fabric pockets for seat cushions and decks.", frame: .plan)
        b.tags("sofa", "pocket spring", "coil", "cushion", "seat", "unit")
        b.aliases("pocket coil unit", "pocketed springs", "encased coils", "spring cushion core", "20 x 20", "24 x 24", "3 in coil")
        b.material("Fabric Material", ComponentFinish("Non-Woven - White", .generic, RGBColor(hex: 0xEFEDE6)))
        b.length("Unit Width", CC.inch(21))
        b.length("Unit Depth", CC.inch(21))
        b.length("Unit Height", CC.inch(3.5))
        b.number("Columns", 7, group: .dimensions)
        b.number("Rows", 7, group: .dimensions)
        b.host([.form, .bottom], faces: [.top], align: .center)
        b.box("Base Fabric", x: ("-Unit Width / 2", "Unit Width / 2"), y: ("-Unit Depth / 2", "Unit Depth / 2"), z: ("0 m", "0.002 m"))
        for c in 1...10 {
            for r in 1...10 {
                let v: String? = (c <= 6 && r <= 6) ? nil : "Show Coil \(c)-\(r)"
                if let v { b.countFlag(v, "and(Columns >= \(c), Rows >= \(r))") }
                let x = "-Unit Width / 2 + Unit Width * (\(c) - 0.5) / Columns", y = "-Unit Depth / 2 + Unit Depth * (\(r) - 0.5) / Rows"
                b.shown(v) { $0.cyl("Coil \(c)-\(r)", axis: .z, center: (x, y), radius: "Unit Width / Columns / 2 - 0.001 m", from: "0.002 m", to: "Unit Height", segments: 12) }
            }
        }
        b.outlines(x: ("-Unit Width / 2", "Unit Width / 2"), y: ("-Unit Depth / 2", "Unit Depth / 2"), z: ("0 m", "Unit Height"))
        b.type("Pocket Spring Unit - 21\" x 21\"", [:], numbers: ["Columns": 7, "Rows": 7], cost: 39, model: "PSU-2121")
        b.type("Pocket Spring Unit - 24\" x 24\"", ["Unit Width": CC.inch(24), "Unit Depth": CC.inch(24)], numbers: ["Columns": 8, "Rows": 8], cost: 45, model: "PSU-2424")
        b.type("Pocket Spring Unit - 30\" x 24\"", ["Unit Width": CC.inch(30), "Unit Depth": CC.inch(24)], numbers: ["Columns": 10, "Rows": 8], cost: 55, model: "PSU-3024")
        return b.build()
    }

    /// Elastic webbing: interwoven straps stretched across a seat or back frame.
    static func elasticWebbing() -> ComponentDefinition {
        var b = ComponentBuilder("Elastic Webbing", .sofas, "Springs & Suspension", "Elastic seat webbing: straps stretched front to back and side to side, interwoven, stapled to the frame.",
                                 frame: .plan)
        b.tags("sofa", "webbing", "elastic", "seat", "suspension", "strap")
        b.aliases("elastic seat webbing", "upholstery webbing", "rubber webbing", "pirelli webbing", "2 in", "3 in", "50 mm", "75 mm")
        b.material("Finish Material", ComponentFinish("Webbing - Black", .generic, RGBColor(hex: 0x2E2E30)))
        b.length("Frame Width", CC.inch(24), instance: true, group: .placement)
        b.length("Frame Depth", CC.inch(22), instance: true, group: .placement)
        b.length("Strap Width", CC.inch(2))
        b.length("Strap Spacing", CC.inch(3))
        b.length("Strap Thickness", CC.mm(2))
        b.number("Stretch", 10, unit: "%", group: .manufacturing)
        b.host([.form, .rail], faces: [.top], align: .center)
        for k in 0..<10 {
            let vy = "Show Long Strap \(k + 1)", vx = "Show Cross Strap \(k + 1)"
            b.countFlag(vy, "-Frame Width / 2 + Strap Width / 2 + Strap Spacing * \(k) <= Frame Width / 2 - Strap Width / 2")
            b.countFlag(vx, "-Frame Depth / 2 + Strap Width / 2 + Strap Spacing * \(k) <= Frame Depth / 2 - Strap Width / 2")
            let x = "-Frame Width / 2 + Strap Width / 2 + Strap Spacing * \(k)", y = "-Frame Depth / 2 + Strap Width / 2 + Strap Spacing * \(k)"
            b.shown(vy) { $0.box("Long Strap \(k + 1)", x: ("\(x) - Strap Width / 2", "\(x) + Strap Width / 2"), y: ("-Frame Depth / 2", "Frame Depth / 2"), z: ("0 m", "Strap Thickness")) }
            b.shown(vx) { $0.box("Cross Strap \(k + 1)", x: ("-Frame Width / 2", "Frame Width / 2"), y: ("\(y) - Strap Width / 2", "\(y) + Strap Width / 2"), z: ("Strap Thickness", "2 * Strap Thickness")) }
        }
        b.outlines(x: ("-Frame Width / 2", "Frame Width / 2"), y: ("-Frame Depth / 2", "Frame Depth / 2"), z: ("0 m", "2 * Strap Thickness"))
        b.type("Elastic Webbing - 2\"", [:], cost: 12, model: "EW-2", description: "2\" elastic webbing, one seat, 3\" spacing")
        b.type("Elastic Webbing - 3\"", ["Strap Width": CC.inch(3), "Strap Spacing": CC.inch(4)], cost: 14, model: "EW-3", description: "3\" elastic webbing, one seat, 4\" spacing")
        return b.build()
    }

    // MARK: Clips, buttons, supports

    /// Upholstery clip: a spring-steel clip that holds a zigzag spring or webbing on a rail.
    static func upholsteryClip() -> ComponentDefinition {
        var b = ComponentBuilder("Upholstery Clip", .sofas, "Clips & Buttons", "Spring-steel clip nailed to a rail that holds a zigzag spring end or a webbing strap.")
        b.tags("sofa", "clip", "spring clip", "webbing clip", "upholstery", "rail")
        b.aliases("zigzag spring clip", "sinuous spring clip", "webbing clip", "spring retainer clip", "no sag clip")
        b.material("Finish Material", .zinc)
        b.length("Clip Width", CC.mm(25))
        b.length("Clip Length", CC.mm(32))
        b.length("Clip Height", CC.mm(10))
        b.host([.rail], faces: [.top, .inside], align: .center)
        b.box("Base", x: ("-Clip Width / 2", "Clip Width / 2"), y: ("-Clip Length / 2", "Clip Length / 2"), z: ("0 m", "0.001 m"))
        b.link("Tongue", plane: .yz, ("-Clip Length / 2", "0.001 m"), ("Clip Length / 4", "Clip Height"), at: "0 m", width: CX.mm(1.2), thickness: "Clip Width * 0.8")
        b.box("Lip", x: ("-Clip Width * 0.4", "Clip Width * 0.4"), y: ("Clip Length / 4", "Clip Length / 2"), z: ("Clip Height - 0.0012 m", "Clip Height"))
        b.drill("Clip nail", x: "-Clip Width / 3", y: "0 m", diameter: CX.mm(2), depth: CX.mm(16))
        b.drill("Clip nail", x: "Clip Width / 3", y: "0 m", diameter: CX.mm(2), depth: CX.mm(16))
        b.outlines(plan: .top, elevation: .face, x: ("-Clip Width / 2", "Clip Width / 2"), y: ("-Clip Length / 2", "Clip Length / 2"), z: ("0 m", "Clip Height"))
        b.type("Upholstery Clip - Spring", [:], cost: 0.12, model: "UC-S")
        b.type("Upholstery Clip - Webbing 2\"", ["Clip Width": CC.inch(2.1), "Clip Height": CC.mm(6)], cost: 0.18, model: "UC-W2")
        return b.build()
    }

    /// Covered upholstery button: a dome with a wire shank (face-based on the cushion or back face).
    static func upholsteryButton() -> ComponentDefinition {
        var b = ComponentBuilder("Upholstery Button", .sofas, "Clips & Buttons", "Fabric-covered tufting button: a dome with a wire shank through the cushion.")
        b.tags("sofa", "button", "tufting", "upholstery", "covered", "chesterfield")
        b.aliases("tufting button", "covered button", "upholstery tuft button", "size 24", "size 36", "size 45", "16 mm", "22 mm", "28 mm")
        b.material("Cover Material", .fabric)
        b.length("Button Diameter", CC.mm(22))
        b.length("Dome Height", CC.mm(6))
        b.length("Tuft Depth", CC.mm(20), instance: true, group: .placement)
        b.host([.form, .back], faces: [.front, .top, .any], align: .center)
        b.revolve("Dome", profile: ComponentKit.points([("0 m", "0 m"), ("Button Diameter / 2", "0 m"), ("Button Diameter * 0.45", "Dome Height * 0.55"),
                                                        ("Button Diameter * 0.3", "Dome Height * 0.9"), ("0 m", "Dome Height")]), base: "0 m")
        b.revolve("Shank", profile: ComponentKit.points([("0 m", "0 m"), ("0.0015 m", "0 m"), ("0.0015 m", "Tuft Depth"), ("0 m", "Tuft Depth")]), base: "-Tuft Depth")
        b.symbol(.face, [.coarse, .medium, .fine], .circle(("0 m", "0 m"), "Button Diameter / 2"))
        b.symbol(.top, [.coarse], .arc(center: FamilyPoint("0 m", "0 m"), radius: "Button Diameter / 2", startDegrees: "0", sweepDegrees: "180"))
        b.type("Upholstery Button - 16 mm (Size 24)", ["Button Diameter": CC.mm(16), "Dome Height": CC.mm(5)], cost: 0.25, model: "UB-24")
        b.type("Upholstery Button - 22 mm (Size 36)", [:], cost: 0.3, model: "UB-36", isDefault: true)
        b.type("Upholstery Button - 28 mm (Size 45)", ["Button Diameter": CC.mm(28), "Dome Height": CC.mm(7)], cost: 0.35, model: "UB-45")
        return b.build()
    }

    /// Cushion support panel: a perforated board on edge battens under a seat cushion (instead of springs).
    static func cushionSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Cushion Support Panel", .sofas, "Springs & Suspension", "Perforated board on edge battens that carries a seat cushion where there are no springs.", frame: .plan)
        b.tags("sofa", "cushion", "support", "deck", "board", "seat")
        b.aliases("cushion support", "seat deck board", "sofa seat board", "sagging cushion support", "21 in", "24 in")
        b.material("Board Material", ComponentFinish("Hardboard", .wood, RGBColor(hex: 0x8E6C4A)))
        b.material("Batten Material", .beech)
        b.length("Panel Width", CC.inch(21))
        b.length("Panel Depth", CC.inch(20))
        b.length("Board Thickness", CC.mm(6))
        b.host([.form, .rail, .bottom], faces: [.top], align: .center)
        b.using("Batten Material")
        for s in ["-", ""] { b.box("Batten", x: ("\(s)(Panel Width / 2) - 0.02 m", "\(s)(Panel Width / 2) + 0.02 m"), y: ("-Panel Depth / 2", "Panel Depth / 2"), z: ("0 m", "0.018 m")) }
        b.box("Center Batten", x: ("-0.02 m", "0.02 m"), y: ("-Panel Depth / 2", "Panel Depth / 2"), z: ("0 m", "0.018 m"))
        b.using("Board Material")
        b.box("Board", x: ("-Panel Width / 2", "Panel Width / 2"), y: ("-Panel Depth / 2", "Panel Depth / 2"), z: ("0.018 m", "0.018 m + Board Thickness"))
        b.using(nil)
        b.outlines(x: ("-Panel Width / 2", "Panel Width / 2"), y: ("-Panel Depth / 2", "Panel Depth / 2"), z: ("0 m", "0.018 m + Board Thickness"))
        b.type("Cushion Support Panel - 21\"", [:], cost: 18, model: "CSP-21")
        b.type("Cushion Support Panel - 24\"", ["Panel Width": CC.inch(24), "Panel Depth": CC.inch(22)], cost: 21, model: "CSP-24")
        return b.build()
    }

    /// Ratchet armrest hinge: a frame plate and an arm plate on a ratchet hub that clicks through its positions.
    static func armrestHinge() -> ComponentDefinition {
        var b = ComponentBuilder("Armrest Hinge", .sofas, "Hinges & Ratchets", "Ratchet hinge for an adjustable sofa arm: frame plate, arm plate and a ratchet hub with click positions.")
        b.tags("sofa", "armrest", "hinge", "ratchet", "adjustable", "arm")
        b.aliases("sofa arm hinge", "ratchet hinge", "adjustable armrest hinge", "click clack hinge", "5 position", "7 position")
        b.material("Finish Material", .matteBlack)
        b.length("Plate Length", CC.mm(110))
        b.length("Plate Width", CC.mm(40))
        b.length("Hub Diameter", CC.mm(46))
        b.angle("Arm Angle", 0, instance: true, group: .placement)
        b.number("Positions", 5, group: .dimensions)
        b.number("Range", 90, unit: "°", group: .dimensions)
        b.host([.form, .sidePanel, .rail], faces: [.inside, .outside], align: .top, alignments: [.top, .center], mirroredPair: true)
        b.cyl("Ratchet Hub", axis: .z, center: ("0 m", "0 m"), radius: "Hub Diameter / 2", from: "0 m", to: "0.012 m", segments: 28)
        b.box("Frame Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Length", "0 m"), z: ("0 m", "0.004 m"))
        b.link("Arm Plate", plane: .xy, ("0 m", "0 m"), ("-Plate Length * sin(Arm Angle)", "Plate Length * cos(Arm Angle)"), at: "0.009 m", width: "Plate Width", thickness: CX.mm(4))
        for y in ["-Plate Length * 0.4", "-Plate Length * 0.85"] { b.drill("Plate screw", x: "0 m", y: y, diameter: CX.mm(5), depth: CX.mm(20)) }
        b.drill("Arm screw", x: "0 m", y: "Plate Length * 0.6", diameter: CX.mm(5), depth: CX.mm(20), target: .counterpart)
        b.symbol(.face, [.coarse], .rect(("-Plate Width / 2", "-Plate Length"), ("Plate Width / 2", "Plate Length")), .circle(("0 m", "0 m"), "Hub Diameter / 2"))
        b.symbol(.face, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("0 m", "0 m"), radius: "Plate Length", startDegrees: "90", sweepDegrees: "Range"))
        b.symbol(.top, [.coarse], .rect(("-Plate Width / 2", "0 m"), ("Plate Width / 2", "0.012 m")))
        b.type("Armrest Hinge - 5 Position", [:], cost: 12, model: "AH-5")
        b.type("Armrest Hinge - 7 Position", ["Hub Diameter": CC.mm(52)], numbers: ["Positions": 7, "Range": 180], cost: 15, model: "AH-7")
        return b.build()
    }

    /// Adjustable headrest mechanism for sofa backs: a ratchet bracket that tilts the headrest forward in clicks.
    static func headrestMechanism() -> ComponentDefinition {
        var b = ComponentBuilder("Adjustable Headrest Mechanism", .sofas, "Hinges & Ratchets", "Ratchet bracket in a sofa back that tilts the headrest forward in clicks and resets at the end.")
        b.tags("sofa", "headrest", "ratchet", "adjustable", "back", "tilt")
        b.aliases("sofa headrest hinge", "headrest ratchet", "adjustable headrest bracket", "tilting headrest mechanism", "5 step", "7 step")
        b.material("Finish Material", .steel)
        b.length("Base Length", CC.mm(120))
        b.length("Arm Length", CC.mm(140))
        b.length("Bracket Width", CC.mm(35))
        b.angle("Tilt Angle", 0, instance: true, group: .placement)
        b.number("Steps", 5, group: .dimensions)
        b.host([.form, .back, .rail], faces: [.back, .inside], align: .top, alignments: [.top], count: ComponentCountRule(steps: [.init(upTo: 1.0, count: 2)], maximumCount: 3, inset: CC.inch(4)))
        b.box("Base Plate", x: ("-Bracket Width / 2", "Bracket Width / 2"), y: ("-Base Length", "0 m"), z: ("0 m", "0.004 m"))
        b.cyl("Ratchet", axis: .x, center: ("0 m", "0.012 m"), radius: "0.016 m", from: "-Bracket Width / 2", to: "Bracket Width / 2", segments: 20)
        b.link("Headrest Arm", plane: .yz, ("0 m", "0.012 m"), ("Arm Length * cos(Tilt Angle)", "0.012 m + Arm Length * sin(Tilt Angle)"), at: "0 m", width: CX.mm(4), thickness: "Bracket Width")
        for y in ["-Base Length * 0.3", "-Base Length * 0.8"] { b.drill("Base screw", x: "0 m", y: y, diameter: CX.mm(5), depth: CX.mm(20)) }
        b.outlines(plan: .top, elevation: .face, x: ("-Bracket Width / 2", "Bracket Width / 2"), y: ("-Base Length", "Arm Length"), z: ("0 m", "0.03 m"))
        b.symbol(.side, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("0.012 m", "0 m"), radius: "Arm Length", startDegrees: "90", sweepDegrees: "-60"))
        b.type("Adjustable Headrest Mechanism - 5 Step", [:], cost: 9, model: "AHM-5")
        b.type("Adjustable Headrest Mechanism - 7 Step", ["Arm Length": CC.mm(170)], numbers: ["Steps": 7], cost: 11, model: "AHM-7")
        return b.build()
    }

    // MARK: Mobility

    /// Low-profile sofa caster hidden under the frame.
    static func sofaCaster() -> ComponentDefinition {
        var b = ComponentBuilder("Sofa Caster", .sofas, "Mobility", "Low-profile swivel caster on a plate, hidden under a sofa frame or sectional.", frame: .plan)
        b.tags("sofa", "caster", "wheel", "hidden", "swivel", "low profile")
        b.aliases("couch caster", "sofa wheel", "hidden caster", "low profile caster", "1 1/2 in", "40 mm")
        b.material("Finish Material", .zinc)
        b.material("Wheel Material", .blackPlastic)
        b.length("Wheel Diameter", CC.mm(40))
        b.length("Wheel Width", CC.mm(18))
        b.length("Plate Size", CC.mm(45))
        b.number("Load Capacity", 90, unit: "lb", group: .data)
        b.host([.bottom, .rail, .leg], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight], offsetX: CC.inch(2), offsetY: CC.inch(2))
        b.caster("Caster", x: "0 m", y: "0 m", top: "0 m", wheel: "Wheel Diameter", wheelWidth: "Wheel Width", plateSize: "Plate Size")
        for (x, y) in [("-1", "-1"), ("1", "1")] { b.drill("Plate screw", x: "\(x) * Plate Size * 0.33", y: "\(y) * Plate Size * 0.33", diameter: CX.mm(4), depth: CX.mm(16)) }
        b.symbol(.face, [.coarse], .rect(("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2")))
        b.symbol(.top, [.coarse], .circle(("0 m", "-Wheel Diameter / 2 - 0.012 m"), "Wheel Diameter / 2"))
        b.type("Sofa Caster - 40 mm", [:], cost: 3.5, model: "SCA-40")
        b.type("Sofa Caster - 50 mm", ["Wheel Diameter": CC.mm(50), "Plate Size": CC.mm(50)], numbers: ["Load Capacity": 120], cost: 4.2, model: "SCA-50")
        return b.build()
    }

    /// Swivel base for swivel sofas and lounge chairs: a turntable bearing between the seat plate and a base ring.
    static func swivelSofaBase() -> ComponentDefinition {
        var b = ComponentBuilder("Swivel Sofa Base", .sofas, "Mobility", "Heavy swivel plate for swivel chairs and sofas: ball-bearing turntable between a seat plate and a base ring.",
                                 frame: .plan)
        b.tags("sofa", "swivel", "base", "turntable", "bearing", "lounge chair")
        b.aliases("swivel plate", "swivel chair base", "lazy susan bearing", "swivel glider base", "12 in", "16 in", "360°")
        b.material("Finish Material", .steel)
        b.material("Base Material", .matteBlack)
        b.length("Plate Size", CC.inch(12))
        b.length("Base Diameter", CC.inch(22))
        b.length("Base Height", CC.inch(3))
        b.flag("Memory Return", false, instance: false, group: .data)
        b.number("Load Capacity", 500, unit: "lb", group: .data)
        b.host([.bottom, .form], faces: [.bottom], align: .center)
        b.box("Seat Plate", x: ("-Plate Size / 2", "Plate Size / 2"), y: ("-Plate Size / 2", "Plate Size / 2"), z: ("-0.003 m", "0 m"))
        b.cyl("Bearing", axis: .z, center: ("0 m", "0 m"), radius: "Plate Size * 0.48", from: "-0.012 m", to: "-0.003 m", segments: 40)
        b.box("Base Plate", x: ("-Plate Size / 2", "Plate Size / 2"), y: ("-Plate Size / 2", "Plate Size / 2"), z: ("-0.015 m", "-0.012 m"))
        b.using("Base Material")
        b.revolve("Base Ring", profile: ComponentKit.points([("Base Diameter / 2 - 0.03 m", "0 m"), ("Base Diameter / 2", "0 m"), ("Base Diameter / 2 - 0.01 m", "Base Height - 0.015 m"),
                                                             ("Plate Size * 0.4", "Base Height - 0.015 m"), ("Plate Size * 0.4", "Base Height - 0.02 m"), ("Base Diameter / 2 - 0.035 m", "Base Height - 0.02 m")]),
                  base: "-Base Height")
        b.using(nil)
        for (x, y) in [("-1", "-1"), ("1", "-1"), ("1", "1"), ("-1", "1")] { b.drill("Plate screw", x: "\(x) * Plate Size * 0.42", y: "\(y) * Plate Size * 0.42", diameter: CX.mm(5), depth: CX.mm(20)) }
        b.symbol(.face, [.coarse], .circle(("0 m", "0 m"), "Base Diameter / 2"), .rect(("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2")))
        b.symbol(.top, [.coarse], .rect(("-Base Diameter / 2", "-Base Height"), ("Base Diameter / 2", "0 m")))
        b.type("Swivel Sofa Base - 12\" Plate", [:], cost: 45, model: "SSB-12")
        b.type("Swivel Sofa Base - 16\" Plate Memory Return", ["Plate Size": CC.inch(16), "Base Diameter": CC.inch(26)], flags: ["Memory Return": true], numbers: ["Load Capacity": 700],
               cost: 89, model: "SSB-16R")
        return b.build()
    }
}
