import Foundation
import ArcusGeometry

// COMPB: 06 Connectors & Fasteners. Knock-down fittings, dowels, screws, bolts, nuts, brackets and plates.
//
// Frame (face-based, ComponentKit): the origin is on the host part's face at the joint edge; X runs along the edge, Y
// into the host away from the joint (the part across the joint is at negative Y), Z out of the face (the host's
// material is at negative Z, "Panel Thickness" deep). Joint fasteners (dowels, cams, confirmats, bolts, clips,
// brackets) are also offered to Joint Rules and the Joint tool (ComponentLibrary+B+Joints.swift), which drill them at
// every joint of their type.

extension ComponentLibrary {
    static var groupBConnectors: [ComponentDefinition] {
        [camLockUpgrade(), camDowel(), dowelUpgrade(), metalDowel(), confirmatUpgrade(), furnitureBolt(), barrelNut(), crossDowel(),
         camAndBolt(), surfaceCam(), eccentric(), cornerBracket(), lBracket(), tBracket(), angleBracket(), joiningPlate(), connectorPlate(),
         shelfSupport(), hiddenShelfSupport(), threadedInsert(), knockDownFitting(), panelClip(), magneticConnector(), assemblyClip(),
         adjustableBolt(), worktopConnector(), bedFrameConnector()]
    }

    static let pt = "Panel Thickness"

    /// The instance parameter every face-mounted connector has: the host's thickness, for the geometry inside it.
    static func panelThickness(_ b: inout ComponentBuilder, _ v: Double = ComponentKit.inch(0.75)) {
        b.length(pt, v, instance: true, group: .placement, min: ComponentKit.mm(10), max: ComponentKit.mm(40))
    }

    // MARK: Cams

    /// FM5's Cam Lock and Bolt, upgraded: 12, 15 and 20 mm cams, the edge hole the bolt takes, a drive slot at Fine.
    static func camLockUpgrade() -> ComponentDefinition {
        guard var b = ComponentBuilder(upgrading: FurnitureHardware.camLock) else { return camAndBolt() }
        b.smoothCircles()
        b.tags("cam connector", "cam lock", "knock down", "kd", "15 mm", "12 mm", "20 mm", "32 mm system")
        b.aliases("cam fitting", "cam lock nut", "cam and dowel", "rta connector", "flat pack connector")
        b.length("Edge Hole Diameter", ComponentKit.mm(8), group: .manufacturing)
        b.length("Edge Hole Depth", ComponentKit.mm(34), group: .manufacturing)
        b.at(CBL.fine) { b in
            b.box("Drive Slot", x: ("Cam Distance - Cam Diameter * 0.3", "Cam Distance + Cam Diameter * 0.3"), y: (CX.mm(-0.6), CX.mm(0.6)),
                  z: (CX.mm(-1.2), CX.mm(0.2)), void: true)
        }
        b.symCircle(.face, CBL.all, c: ("Cam Distance", CX.zero), r: "Cam Diameter / 2")
        b.symCross(.face, CBL.coarse, c: ("Cam Distance", CX.zero), s: "Cam Diameter * 0.35")
        b.symLine(.face, CBL.mediumFine, ("Cam Distance - Bolt Length", CX.zero), ("Cam Distance", CX.zero), dashed: true)
        b.symRect(.side, CBL.coarse, ("-Cam Depth", "-Cam Diameter / 2"), (CX.zero, "Cam Diameter / 2"))
        b.drill("Cam lock", x: "Cam Distance", y: CX.zero, diameter: "Cam Diameter", depth: "Cam Depth")
        b.edgeDrill("Cam bolt hole", x: CX.zero, z: "-Cam Depth / 2", diameter: "Edge Hole Diameter", depth: "Edge Hole Depth")
        b.drill("Cam bolt", x: CX.zero, y: CX.zero, diameter: "Bolt Hole Diameter", depth: "Bolt Hole Depth", target: .counterpart)
        b.requires(.hostThickness(min: "Cam Depth + 0.003 m", max: nil))
        let mm = ComponentKit.mm
        b.dropType("15 mm")
        b.type("12 mm", ["Cam Diameter": mm(12), "Cam Depth": mm(9.5), "Cam Distance": mm(22), "Bolt Diameter": mm(6), "Bolt Length": mm(28),
                         "Bolt Hole Diameter": mm(5), "Bolt Hole Depth": mm(9.5), "Edge Hole Diameter": mm(7), "Edge Hole Depth": mm(28)],
               cost: 0.38, model: "CL-12", description: "Cam lock 12 mm with connecting bolt, for 12-16 mm panels")
        b.type("15 mm", ["Cam Diameter": mm(15), "Cam Depth": mm(12.5), "Cam Distance": mm(24), "Bolt Diameter": mm(7), "Bolt Length": mm(34),
                         "Bolt Hole Diameter": mm(5), "Bolt Hole Depth": mm(11), "Edge Hole Diameter": mm(8), "Edge Hole Depth": mm(34)],
               cost: 0.45, model: "CL-15", description: "Cam lock 15 mm with connecting bolt, for 16-19 mm panels", isDefault: true)
        b.type("20 mm", ["Cam Diameter": mm(20), "Cam Depth": mm(15), "Cam Distance": mm(34), "Bolt Diameter": mm(8), "Bolt Length": mm(44),
                         "Bolt Hole Diameter": mm(7), "Bolt Hole Depth": mm(13), "Edge Hole Diameter": mm(10), "Edge Hole Depth": mm(44)],
               cost: 0.62, model: "CL-20", description: "Cam lock 20 mm with connecting bolt, for 22-29 mm panels")
        return b.build()
    }

    /// The cam bolt on its own (cam dowel): the head the cam pulls, the neck through the edge hole, the spigot or thread
    /// in the other part. Double Ended joins two cams through a divider.
    static func camDowel() -> ComponentDefinition {
        var b = ComponentBuilder("Cam Dowel", .connectors, "Cam Connectors", "Steel cam bolt: head for a cam housing, neck, and a threaded spigot for the other part.")
        b.tags("cam dowel", "cam bolt", "connecting bolt", "knock down", "kd", "24 mm", "34 mm")
        b.aliases("connector bolt", "cam stud", "dowel bolt", "connecting screw", "double ended bolt")
        b.hardwareKind(.camLock)
        b.material("Finish Material", .zinc)
        panelThickness(&b)
        b.length("Drilling Distance", ComponentKit.mm(24), min: ComponentKit.mm(20), max: ComponentKit.mm(44))
        b.length("Head Diameter", ComponentKit.mm(7))
        b.length("Neck Diameter", ComponentKit.mm(5))
        b.length("Spigot Diameter", ComponentKit.mm(5))
        b.length("Spigot Length", ComponentKit.mm(11))
        b.length("Edge Hole Diameter", ComponentKit.mm(8), group: .manufacturing)
        b.flag("Double Ended", false, instance: false, group: .constraints)
        b.flag("Single Ended", false, group: .constraints, formula: "not(Double Ended)")
        b.host([.shelf, .top, .bottom, .divider], faces: [.inside], align: .left)
        let z = "-\(pt) / 2"
        b.rod("Head", axis: .y, c: (CX.zero, z), r: "Head Diameter / 2", from: "Drilling Distance - 0.0035 m", to: "Drilling Distance")
        b.rod("Neck", axis: .y, c: (CX.zero, z), r: "Neck Diameter / 2", from: CX.zero, to: "Drilling Distance - 0.0035 m")
        b.rod("Collar", axis: .y, c: (CX.zero, z), r: "Edge Hole Diameter / 2 - 0.0002 m", from: CX.zero, to: CX.mm(3))
        b.shown(by: "Single Ended") { b in
            b.rod("Spigot", axis: .y, c: (CX.zero, z), r: "Spigot Diameter / 2", from: "-Spigot Length", to: CX.zero)
            b.at(CBL.fine) { b in
                for k in 0..<4 {
                    let y0 = "-Spigot Length * \(LX.num(0.2 + 0.2 * Double(k)))"
                    b.rod("Thread \(k + 1)", axis: .y, c: (CX.zero, z), r: "Spigot Diameter / 2 + 0.0004 m", from: "\(y0) - 0.0006 m", to: y0)
                }
            }
        }
        b.shown(by: "Double Ended") { b in
            b.rod("Second Neck", axis: .y, c: (CX.zero, z), r: "Neck Diameter / 2", from: "-Drilling Distance + 0.0035 m", to: CX.zero)
            b.rod("Second Head", axis: .y, c: (CX.zero, z), r: "Head Diameter / 2", from: "-Drilling Distance", to: "-Drilling Distance + 0.0035 m")
        }
        b.symLine(.face, CBL.all, (CX.zero, "-Spigot Length"), (CX.zero, "Drilling Distance"))
        b.symCircle(.face, CBL.coarse, c: (CX.zero, "Drilling Distance"), r: "Head Diameter / 2")
        b.edgeDrill("Cam dowel hole", x: CX.zero, z: z, diameter: "Edge Hole Diameter", depth: "Drilling Distance + 0.002 m")
        b.drill("Cam dowel spigot", x: CX.zero, y: CX.zero, diameter: "Spigot Diameter", depth: "Spigot Length", target: .counterpart)
        b.symRect(.top, CBL.coarse, ("-Head Diameter / 2", "-\(pt) / 2 - Head Diameter / 2"), ("Head Diameter / 2", "-\(pt) / 2 + Head Diameter / 2"))
        let mm = ComponentKit.mm
        b.type("Cam Dowel - 24 mm", ["Drilling Distance": mm(24)], flags: ["Double Ended": false], cost: 0.12, model: "CD-24", description: "Cam dowel, 24 mm drilling distance, 5 mm spigot")
        b.type("Cam Dowel - 34 mm", ["Drilling Distance": mm(34), "Spigot Length": mm(13)], flags: ["Double Ended": false], cost: 0.14, model: "CD-34",
               description: "Cam dowel, 34 mm drilling distance, for thick panels")
        b.type("Cam Dowel - Double Ended", ["Drilling Distance": mm(24)], flags: ["Double Ended": true], cost: 0.22, model: "CD-24D",
               description: "Double-ended cam dowel, joins two shelves through a divider")
        return b.build()
    }

    /// A Minifix-style system connector: a die-cast cam housing with a rim, set in the face, and a separate bolt.
    static func camAndBolt() -> ComponentDefinition {
        var b = ComponentBuilder("Cam and Bolt Connector", .connectors, "Cam Connectors", "System cam connector: die-cast cam housing with a rim and a separate connecting bolt, on the 32 mm system.")
        b.tags("cam", "connector", "cam and bolt", "system connector", "knock down", "kd", "15 mm", "32 mm system")
        b.aliases("minifix-style", "minifix", "cam fitting", "eccentric cam", "rta fitting")
        b.hardwareKind(.camLock)
        b.material("Finish Material", .zinc)
        b.material("Bolt Material", .steel)
        panelThickness(&b)
        b.length("Housing Diameter", ComponentKit.mm(15))
        b.length("Housing Depth", ComponentKit.mm(12.5))
        b.length("Rim Diameter", ComponentKit.mm(16.5))
        b.length("Drilling Distance", ComponentKit.mm(24), min: ComponentKit.mm(22), max: ComponentKit.mm(44))
        b.length("Bolt Diameter", ComponentKit.mm(6.5))
        b.length("Bolt Length", ComponentKit.mm(34))
        b.length("Bolt Hole Diameter", ComponentKit.mm(5), group: .manufacturing)
        b.length("Bolt Hole Depth", ComponentKit.mm(11), group: .manufacturing)
        b.length("Edge Hole Diameter", ComponentKit.mm(8), group: .manufacturing)
        b.host([.shelf, .top, .bottom, .divider], faces: [.inside], align: .left)
        let c = (CX.zero, "Drilling Distance")
        b.rod("Housing", c: c, r: "Housing Diameter / 2", from: "-Housing Depth", to: CX.zero)
        b.rod("Rim", c: c, r: "Rim Diameter / 2", from: CX.zero, to: CX.mm(0.8))
        b.at(CBL.fine) { b in
            b.box("Arrow", x: ("-Housing Diameter * 0.05", "Housing Diameter * 0.05"), y: ("Drilling Distance - Housing Diameter * 0.4", "Drilling Distance + Housing Diameter * 0.4"),
                  z: (CX.mm(0.4), CX.mm(1.0)), void: true)
        }
        b.slot("Bolt Material") { b in
            let z = "-\(pt) / 2"
            b.rod("Bolt Head", axis: .y, c: (CX.zero, z), r: "Bolt Diameter / 2 + 0.0005 m", from: "Drilling Distance - 0.004 m", to: "Drilling Distance")
            b.rod("Bolt", axis: .y, c: (CX.zero, z), r: "Bolt Diameter / 2 - 0.001 m", from: "Drilling Distance - Bolt Length", to: "Drilling Distance - 0.004 m")
        }
        b.symCircle(.face, CBL.all, c: c, r: "Rim Diameter / 2")
        b.symCross(.face, CBL.coarse, c: c, s: "Housing Diameter * 0.3")
        b.symLine(.face, CBL.mediumFine, (CX.zero, "Drilling Distance - Bolt Length"), (CX.zero, "Drilling Distance"), dashed: true)
        b.drill("Cam housing", x: c.0, y: c.1, diameter: "Housing Diameter", depth: "Housing Depth")
        b.edgeDrill("Cam bolt hole", x: CX.zero, z: "-\(pt) / 2", diameter: "Edge Hole Diameter", depth: "Drilling Distance + 0.002 m")
        b.drill("Cam bolt", x: CX.zero, y: CX.zero, diameter: "Bolt Hole Diameter", depth: "Bolt Hole Depth", target: .counterpart)
        b.requires(.hostThickness(min: "Housing Depth + 0.003 m", max: nil))
        b.symRect(.top, CBL.coarse, ("-Rim Diameter / 2", "-Housing Depth"), ("Rim Diameter / 2", CX.mm(0.8)))
        let mm = ComponentKit.mm
        b.type("Cam and Bolt - 12 mm", ["Housing Diameter": mm(12), "Housing Depth": mm(9.5), "Rim Diameter": mm(13.5), "Drilling Distance": mm(22), "Bolt Length": mm(28),
                                       "Bolt Diameter": mm(6), "Edge Hole Diameter": mm(7), "Panel Thickness": mm(16)],
               cost: 0.42, model: "CB-12", description: "Cam and bolt connector, 12 mm housing, 12-16 mm panels")
        b.type("Cam and Bolt - 15 mm", [:], cost: 0.48, model: "CB-15", description: "Cam and bolt connector, 15 mm housing, 16-19 mm panels", isDefault: true)
        b.type("Cam and Bolt - 15 mm / 34 mm", ["Drilling Distance": mm(34), "Bolt Length": mm(44)], cost: 0.52, model: "CB-1534",
               description: "Cam and bolt connector, 15 mm housing, 34 mm drilling distance")
        return b.build()
    }

    /// A Rafix-style surface cam connector: a round housing on the face (no bore through the face), pulling a bolt.
    static func surfaceCam() -> ComponentDefinition {
        var b = ComponentBuilder("Surface Cam Connector", .connectors, "Cam Connectors", "Surface-mounted cam connector: a round housing in a shallow 20 mm bore with a dowel spigot, pulling a bolt in the other part.")
        b.tags("cam", "connector", "surface", "knock down", "kd", "20 mm")
        b.aliases("rafix-style", "rafix", "surface connector", "shelf connector", "housing connector")
        b.hardwareKind(.camLock)
        b.material("Finish Material", .whitePlastic)
        b.material("Bolt Material", .zinc)
        panelThickness(&b)
        b.length("Housing Diameter", ComponentKit.mm(20))
        b.length("Housing Height", ComponentKit.mm(11))
        b.length("Bore Depth", ComponentKit.mm(4), group: .manufacturing)
        b.length("Set Back", ComponentKit.mm(9.5))
        b.length("Bolt Diameter", ComponentKit.mm(5))
        b.length("Bolt Length", ComponentKit.mm(12))
        b.flag("Double", false, instance: false)
        b.host([.shelf, .bottom, .top], faces: [.top, .bottom], align: .left)
        let c = (CX.zero, "Set Back")
        b.turn("Housing", c: c, base: "-Bore Depth", [(CX.zero, CX.zero), ("Housing Diameter / 2 - 0.0005 m", CX.zero), ("Housing Diameter / 2", "Bore Depth"),
                                                    ("Housing Diameter / 2", "Housing Height - 0.0015 m"), ("Housing Diameter / 2 - 0.0015 m", "Housing Height"), (CX.zero, "Housing Height")])
        b.at(CBL.fine) { b in
            b.box("Screw Slot", x: ("-Housing Diameter * 0.3", "Housing Diameter * 0.3"), y: ("Set Back - 0.0006 m", "Set Back + 0.0006 m"),
                  z: ("Housing Height - Bore Depth - 0.0012 m", "Housing Height - Bore Depth + 0.0002 m"), void: true)
        }
        b.slot("Bolt Material") { b in
            b.rod("Bolt", axis: .y, c: (CX.zero, "Housing Height / 2 - Bore Depth"), r: "Bolt Diameter / 2", from: "-Bolt Length", to: "Set Back")
        }
        b.shown(by: "Double") { b in
            b.turn("Second Housing", c: (CX.zero, "-Set Back"), base: "-Bore Depth", [(CX.zero, CX.zero), ("Housing Diameter / 2", CX.zero), ("Housing Diameter / 2", "Housing Height"), (CX.zero, "Housing Height")])
        }
        b.symCircle(.face, CBL.all, c: c, r: "Housing Diameter / 2")
        b.symCross(.face, CBL.coarse, c: c, s: "Housing Diameter * 0.3")
        b.drill("Housing bore", x: c.0, y: c.1, diameter: "Housing Diameter", depth: "Bore Depth")
        b.drill("Connector bolt", x: CX.zero, y: CX.zero, diameter: "Bolt Diameter", depth: "Bolt Length", target: .counterpart)
        b.symRect(.top, CBL.coarse, ("-Housing Diameter / 2", "-Bore Depth"), ("Housing Diameter / 2", "Housing Height - Bore Depth"))
        let mm = ComponentKit.mm
        b.type("Surface Cam - 20 mm", [:], flags: ["Double": false], cost: 0.65, model: "SC-20", description: "Surface cam connector, 20 mm housing, single")
        b.type("Surface Cam - 20 mm Double", ["Bolt Length": mm(20)], flags: ["Double": true], cost: 1.10, model: "SC-20D", description: "Surface cam connector pair across a divider")
        return b.build()
    }

    /// An eccentric connector: a cam with an eccentric spiral that pulls a pin, in a 20-25 mm bore; tightened from the face.
    static func eccentric() -> ComponentDefinition {
        var b = ComponentBuilder("Eccentric Connector", .connectors, "Cam Connectors", "Eccentric (spiral) connector in a face bore that draws a steel pin from the other part as it turns.")
        b.tags("eccentric", "connector", "cam", "knock down", "kd", "20 mm", "25 mm")
        b.aliases("eccentric fitting", "spiral cam", "tension cam", "eccentric lock")
        b.hardwareKind(.camLock)
        b.material("Finish Material", .zinc)
        panelThickness(&b, ComponentKit.mm(25))
        b.length("Body Diameter", ComponentKit.mm(25))
        b.length("Body Depth", ComponentKit.mm(14))
        b.length("Eccentricity", ComponentKit.mm(2.5))
        b.length("Center Distance", ComponentKit.mm(20))
        b.length("Pin Diameter", ComponentKit.mm(6))
        b.length("Pin Length", ComponentKit.mm(30))
        b.host([.shelf, .top, .bottom, .rail], faces: [.inside], align: .left)
        let c = (CX.zero, "Center Distance")
        b.rod("Body", c: c, r: "Body Diameter / 2", from: "-Body Depth", to: CX.zero)
        b.at(CBL.fine) { b in
            b.rod("Eccentric Boss", c: (CX.zero, "Center Distance + Eccentricity"), r: "Body Diameter * 0.2", from: CX.mm(-1), to: CX.mm(0.3))
            b.box("Hex Drive", x: ("-Body Diameter * 0.08", "Body Diameter * 0.08"), y: ("Center Distance - Body Diameter * 0.08", "Center Distance + Body Diameter * 0.08"),
                  z: (CX.mm(-3), CX.mm(0.4)), void: true)
        }
        b.rod("Pin", axis: .y, c: (CX.zero, "-Body Depth / 2"), r: "Pin Diameter / 2", from: "Center Distance - Pin Length", to: "Center Distance")
        b.symCircle(.face, CBL.all, c: c, r: "Body Diameter / 2")
        b.symCross(.face, CBL.coarse, c: c, s: "Body Diameter * 0.3")
        b.drill("Eccentric bore", x: c.0, y: c.1, diameter: "Body Diameter", depth: "Body Depth")
        b.edgeDrill("Eccentric pin hole", x: CX.zero, z: "-Body Depth / 2", diameter: "Pin Diameter + 0.001 m", depth: "Center Distance")
        b.drill("Eccentric pin", x: CX.zero, y: CX.zero, diameter: "Pin Diameter", depth: "Pin Length - Center Distance", target: .counterpart)
        b.requires(.hostThickness(min: "Body Depth + 0.004 m", max: nil))
        b.symRect(.top, CBL.coarse, ("-Body Diameter / 2", "-Body Depth"), ("Body Diameter / 2", CX.zero))
        let mm = ComponentKit.mm
        b.type("Eccentric - 20 mm", ["Body Diameter": mm(20), "Body Depth": mm(12), "Center Distance": mm(16), "Pin Diameter": mm(5), "Pin Length": mm(24), "Panel Thickness": mm(19)],
               cost: 0.70, model: "EC-20", description: "Eccentric connector, 20 mm bore, 5 mm pin")
        b.type("Eccentric - 25 mm", [:], cost: 0.95, model: "EC-25", description: "Eccentric connector, 25 mm bore, 6 mm pin", isDefault: true)
        return b.build()
    }

    // MARK: Dowels and screws

    /// FM5's Dowel, upgraded: flutes and chamfers at Fine, more sizes kept to the trade's 6, 8 and 10 mm.
    static func dowelUpgrade() -> ComponentDefinition {
        guard var b = ComponentBuilder(upgrading: FurnitureHardware.dowel) else { return metalDowel() }
        b.smoothCircles()
        b.tags("wooden dowel", "fluted", "beech", "6 mm", "8 mm", "10 mm", "joint", "dowel pin")
        b.aliases("wood dowel", "dowel peg", "fluted pin", "groove dowel", "1/4\" dowel", "5/16\" dowel", "3/8\" dowel")
        b.length("Chamfer", ComponentKit.mm(1), group: .dimensions)
        b.at(CBL.fine) { b in
            // Four flutes along the dowel, as shallow grooves cut in its surface (Along X frame only).
            b.shown(by: "Along X") { b in
                let x = ("-Length / 2 + Chamfer", "Length / 2 - Chamfer"), w = ("-Diameter * 0.12", "Diameter * 0.12")
                b.box("Flute 1", x: x, y: w, z: ("Diameter / 2 - 0.0007 m", "Diameter / 2 + 0.0003 m"), void: true)
                b.box("Flute 2", x: x, y: w, z: ("-Diameter / 2 - 0.0003 m", "-Diameter / 2 + 0.0007 m"), void: true)
                b.box("Flute 3", x: x, y: ("Diameter / 2 - 0.0007 m", "Diameter / 2 + 0.0003 m"), z: w, void: true)
                b.box("Flute 4", x: x, y: ("-Diameter / 2 - 0.0003 m", "-Diameter / 2 + 0.0007 m"), z: w, void: true)
            }
        }
        b.symLine(.face, CBL.all, ("-Length / 2", CX.zero), ("Length / 2", CX.zero))
        b.symRect(.face, CBL.mediumFine, ("-Length / 2", "-Diameter / 2"), ("Length / 2", "Diameter / 2"))
        b.drill("Dowel", x: CX.zero, y: CX.zero, diameter: "Diameter", depth: "Length / 2 + 0.001 m")
        b.drill("Dowel", x: CX.zero, y: CX.zero, diameter: "Diameter", depth: "Length / 2 + 0.001 m", target: .counterpart)
        b.symCircle(.side, CBL.coarse, r: "Diameter / 2")
        return b.build()
    }

    /// A steel dowel pin: plain or with a knurled half for press fits; for shelves, glass and knock-down joints.
    static func metalDowel() -> ComponentDefinition {
        var b = ComponentBuilder("Metal Dowel", .connectors, "Dowels", "Steel dowel pin with chamfered ends; the knurled type has a ribbed press-fit half.")
        b.tags("metal dowel", "steel dowel", "dowel pin", "pin", "5 mm", "6 mm", "8 mm")
        b.aliases("steel pin", "dowel pin", "locating pin", "knurled dowel", "parallel pin")
        b.hardwareKind(.dowel)
        b.material("Finish Material", .steel)
        b.length("Diameter", ComponentKit.mm(6))
        b.length("Length", ComponentKit.mm(30))
        b.length("Chamfer", ComponentKit.mm(0.5))
        b.flag("Knurled", false, instance: false)
        b.flag("Vertical", false)
        b.flag("Along Face", false, formula: "not(Vertical)")
        b.host(ComponentHostKind.carcass + [.glass], faces: [.any])
        func pin(_ b: inout ComponentBuilder, _ axis: FamilyAxis, _ flag: String) {
            b.shown(by: flag) { b in
                b.rod("Pin (\(flag))", axis: axis, r: "Diameter / 2", from: "-Length / 2 + Chamfer", to: "Length / 2 - Chamfer")
                b.rod("End A (\(flag))", axis: axis, r: "Diameter / 2 - Chamfer", from: "-Length / 2", to: "-Length / 2 + Chamfer")
                b.rod("End B (\(flag))", axis: axis, r: "Diameter / 2 - Chamfer", from: "Length / 2 - Chamfer", to: "Length / 2")
            }
        }
        pin(&b, .y, "Along Face")
        pin(&b, .z, "Vertical")
        b.at(CBL.fine) { b in
            b.shown(by: "Knurled") { b in
                for k in 0..<4 {
                    b.rod("Knurl \(k + 1)", axis: .y, r: "Diameter / 2 + 0.0002 m", from: "Length * \(LX.num(0.05 + 0.1 * Double(k)))", to: "Length * \(LX.num(0.09 + 0.1 * Double(k)))")
                }
            }
        }
        b.symRect(.face, CBL.all, ("-Diameter / 2", "-Length / 2"), ("Diameter / 2", "Length / 2"))
        b.drill("Metal dowel", x: CX.zero, y: CX.zero, diameter: "Diameter", depth: "Length / 2 + 0.001 m")
        b.drill("Metal dowel", x: CX.zero, y: CX.zero, diameter: "Diameter", depth: "Length / 2 + 0.001 m", target: .counterpart)
        b.symCircle(.top, CBL.coarse, r: "Diameter / 2")
        let mm = ComponentKit.mm
        b.type("Metal Dowel - 5 x 30 mm", ["Diameter": mm(5), "Length": mm(30)], flags: ["Knurled": false, "Vertical": false], cost: 0.09, model: "MD-530")
        b.type("Metal Dowel - 6 x 30 mm", [:], flags: ["Knurled": false, "Vertical": false], cost: 0.11, model: "MD-630", isDefault: true)
        b.type("Metal Dowel - 8 x 35 mm Knurled", ["Diameter": mm(8), "Length": mm(35)], flags: ["Knurled": true, "Vertical": false], cost: 0.16, model: "MD-835K")
        return b.build()
    }

    /// FM5's Confirmat Screw, upgraded: the trade's 5 x 40, 6.3 x 50, 7 x 50 and 7 x 70 mm, the thread and hex drive at Fine.
    static func confirmatUpgrade() -> ComponentDefinition {
        guard var b = ComponentBuilder(upgrading: FurnitureHardware.confirmat) else { return furnitureBolt() }
        b.smoothCircles()
        b.tags("confirmat", "screw", "one-piece connector", "7 x 50", "7x50", "knock down", "kd")
        b.aliases("euro screw", "assembly screw", "case screw", "confirmat screw 7x50", "chipboard connector")
        b.length("Head Height", ComponentKit.mm(6), group: .dimensions)
        b.length("Countersink Diameter", ComponentKit.mm(10), group: .manufacturing)
        b.at(CBL.fine) { b in
            b.shown(by: "Along X") { b in
                for k in 0..<6 {
                    let x = "Length * \(LX.num(0.3 + 0.11 * Double(k)))"
                    b.rod("Thread \(k + 1)", axis: .x, r: "Diameter / 2 + 0.0004 m", from: x, to: "\(x) + 0.0008 m", sides: 16)
                }
                b.box("Hex Drive", x: (CX.mm(-1.2), CX.mm(3)), y: ("-Diameter * 0.25", "Diameter * 0.25"), z: ("-Diameter * 0.25", "Diameter * 0.25"), void: true)
            }
        }
        b.symLine(.face, CBL.all, (CX.zero, CX.zero), ("Length", CX.zero))
        b.symCircle(.face, CBL.coarse, r: "Head Diameter / 2")
        b.drill("Confirmat", x: CX.zero, y: CX.zero, diameter: "Diameter", depth: "Host Thickness", through: true)
        b.drill("Confirmat pilot", x: CX.zero, y: CX.zero, diameter: "Pilot Diameter", depth: "Length - Host Thickness", target: .counterpart)
        b.symCircle(.side, CBL.coarse, r: "Head Diameter / 2")
        let mm = ComponentKit.mm
        b.type("5 x 40 mm", ["Diameter": mm(5), "Length": mm(40), "Head Diameter": mm(8), "Pilot Diameter": mm(3.5), "Head Height": mm(5), "Countersink Diameter": mm(8)],
               flags: ["Vertical": false], cost: 0.07, model: "CF-540", description: "Confirmat screw 5 x 40 mm, for 12-16 mm panels")
        b.type("6.3 x 50 mm", ["Diameter": mm(6.3), "Length": mm(50), "Head Diameter": mm(9), "Pilot Diameter": mm(4.5), "Head Height": mm(5.5), "Countersink Diameter": mm(9)],
               flags: ["Vertical": false], cost: 0.08, model: "CF-6350", description: "Confirmat screw 6.3 x 50 mm")
        b.type("7 x 70 mm", ["Diameter": mm(7), "Length": mm(70), "Head Diameter": mm(10), "Pilot Diameter": mm(5), "Head Height": mm(6), "Countersink Diameter": mm(10)],
               flags: ["Vertical": false], cost: 0.13, model: "CF-770", description: "Confirmat screw 7 x 70 mm, for 25 mm panels and worktops")
        return b.build()
    }

    // MARK: Bolts and nuts

    /// A connector bolt: a flat head with a hex socket and a metric thread, used with barrel nuts and cross dowels.
    static func furnitureBolt() -> ComponentDefinition {
        var b = ComponentBuilder("Furniture Bolt", .connectors, "Bolts and Nuts", "Furniture connector bolt: flat round head with a hex socket and a metric thread, for barrel nuts, cross dowels and inserts.")
        b.tags("bolt", "connector bolt", "joint connector bolt", "jcb", "m6", "m8", "hex socket", "knock down")
        b.aliases("jcb bolt", "allen bolt", "flat head bolt", "furniture connector bolt", "bed bolt", "chair bolt")
        b.hardwareKind(.screw)
        b.material("Finish Material", .matteBlack)
        b.text("Thread", "M6")
        b.length("Diameter", ComponentKit.mm(6))
        b.length("Length", ComponentKit.mm(50))
        b.length("Head Diameter", ComponentKit.mm(13))
        b.length("Head Height", ComponentKit.mm(2.5))
        b.length("Clearance Hole Diameter", ComponentKit.mm(7), group: .manufacturing)
        b.length("Counterbore Diameter", ComponentKit.mm(14), group: .manufacturing)
        b.host(ComponentHostKind.carcass + [.leg, .rail], faces: [.outside, .any])
        // The bolt goes into the face along -Z; the head sits on the face.
        b.turn("Head", base: CX.zero, [(CX.zero, CX.zero), ("Head Diameter / 2", CX.zero), ("Head Diameter / 2", "Head Height * 0.6"),
                                        ("Head Diameter / 2 - Head Height * 0.4", "Head Height"), (CX.zero, "Head Height")])
        b.rod("Shank", r: "Diameter / 2", from: "-Length", to: CX.zero)
        b.at(CBL.fine) { b in
            b.rod("Hex Socket", r: "Diameter * 0.35", from: "Head Height * 0.2", to: "Head Height + 0.0002 m", void: true, sides: 6)
            for k in 0..<8 {
                let z = "-Length * \(LX.num(0.45 + 0.065 * Double(k)))"
                b.rod("Thread \(k + 1)", r: "Diameter / 2 + 0.0003 m", from: "\(z) - 0.0007 m", to: z, sides: 16)
            }
        }
        b.symCircle(.face, CBL.all, r: "Head Diameter / 2")
        b.symCross(.face, CBL.coarse, s: "Diameter / 2")
        b.symRect(.top, CBL.mediumFine, ("-Diameter / 2", "-Length"), ("Diameter / 2", CX.zero), dashed: true)
        b.drill("Bolt clearance", x: CX.zero, y: CX.zero, diameter: "Clearance Hole Diameter", depth: "Host Thickness", through: true)
        b.drill("Bolt hole", x: CX.zero, y: CX.zero, diameter: "Clearance Hole Diameter", depth: "Length - Host Thickness", target: .counterpart)
        b.symRect(.top, CBL.coarse, ("-Head Diameter / 2", "-Length"), ("Head Diameter / 2", "Head Height"))
        let mm = ComponentKit.mm
        b.type("M6 x 30 mm", ["Length": mm(30)], cost: 0.18, model: "FB-M630")
        b.type("M6 x 50 mm", [:], cost: 0.22, model: "FB-M650", isDefault: true)
        b.type("M8 x 60 mm", ["Diameter": mm(8), "Length": mm(60), "Head Diameter": mm(16), "Head Height": mm(3), "Clearance Hole Diameter": mm(9),
                              "Counterbore Diameter": mm(17)], texts: ["Thread": "M8"], cost: 0.32, model: "FB-M860")
        b.type("M8 x 100 mm", ["Diameter": mm(8), "Length": mm(100), "Head Diameter": mm(16), "Head Height": mm(3), "Clearance Hole Diameter": mm(9),
                               "Counterbore Diameter": mm(17)], texts: ["Thread": "M8"], cost: 0.45, model: "FB-M8100", description: "Furniture bolt M8 x 100 mm, for bed rails and legs")
        return b.build()
    }

    /// A barrel nut: a cylinder with a threaded cross hole, set in a face bore to take a bolt from the edge.
    static func barrelNut() -> ComponentDefinition {
        var b = ComponentBuilder("Barrel Nut", .connectors, "Bolts and Nuts", "Barrel nut: a steel cylinder with a threaded cross hole and a screwdriver slot, set in a bore across the bolt.")
        b.tags("barrel nut", "nut", "cross nut", "m6", "m8", "knock down", "bolt")
        b.aliases("cylinder nut", "dowel nut", "sleeve nut", "furniture nut")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        panelThickness(&b)
        b.text("Thread", "M6")
        b.length("Diameter", ComponentKit.mm(10))
        b.length("Length", ComponentKit.mm(13))
        b.length("Bolt Distance", ComponentKit.mm(20))
        b.host(ComponentHostKind.carcass + [.rail, .leg], faces: [.inside])
        b.rod("Barrel", c: (CX.zero, "Bolt Distance"), r: "Diameter / 2", from: "-Length", to: CX.zero)
        b.at(CBL.fine) { b in
            b.box("Slot", x: ("-Diameter * 0.45", "Diameter * 0.45"), y: ("Bolt Distance - 0.0006 m", "Bolt Distance + 0.0006 m"), z: (CX.mm(-1.2), CX.mm(0.2)), void: true)
            b.rod("Thread Hole", axis: .y, c: (CX.zero, "-Length / 2"), r: "Diameter * 0.3", from: "Bolt Distance - Diameter / 2 - 0.0005 m", to: "Bolt Distance + Diameter / 2 + 0.0005 m",
                  void: true, sides: 16)
        }
        b.symCircle(.face, CBL.all, c: (CX.zero, "Bolt Distance"), r: "Diameter / 2")
        b.symLine(.face, CBL.coarse, ("-Diameter * 0.45", "Bolt Distance"), ("Diameter * 0.45", "Bolt Distance"))
        b.drill("Barrel nut bore", x: CX.zero, y: "Bolt Distance", diameter: "Diameter", depth: "Length + 0.001 m")
        b.edgeDrill("Bolt hole", x: CX.zero, z: "-Length / 2", diameter: "Diameter * 0.7", depth: "Bolt Distance + Diameter / 2")
        b.symRect(.top, CBL.coarse, ("-Diameter / 2", "-Length"), ("Diameter / 2", CX.zero))
        let mm = ComponentKit.mm
        b.type("M6 x 10 x 13 mm", [:], cost: 0.15, model: "BN-M613", isDefault: true)
        b.type("M8 x 13 x 16 mm", ["Diameter": mm(13), "Length": mm(16), "Bolt Distance": mm(25)], texts: ["Thread": "M8"], cost: 0.22, model: "BN-M816")
        b.type("M8 x 15 x 20 mm", ["Diameter": mm(15), "Length": mm(20), "Bolt Distance": mm(30), "Panel Thickness": mm(25)], texts: ["Thread": "M8"], cost: 0.28, model: "BN-M820")
        return b.build()
    }

    /// A cross dowel: a slotted barrel with a flat head and a threaded cross hole, driven in from the face.
    static func crossDowel() -> ComponentDefinition {
        var b = ComponentBuilder("Cross Dowel", .connectors, "Bolts and Nuts", "Cross dowel: a slotted steel barrel with a cross-threaded hole for a furniture bolt, driven from the face.")
        b.tags("cross dowel", "barrel nut", "nut", "m6", "m8", "knock down", "bolt", "slotted")
        b.aliases("cross bolt nut", "dowel nut", "slotted barrel nut", "t-nut dowel")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        panelThickness(&b, ComponentKit.inch(1.5))
        b.text("Thread", "M6")
        b.length("Diameter", ComponentKit.mm(10))
        b.length("Length", ComponentKit.mm(20))
        b.length("Head Diameter", ComponentKit.mm(11.5))
        b.length("Bolt Distance", ComponentKit.mm(25))
        b.host([.leg, .rail, .sidePanel, .bottom], faces: [.inside, .outside])
        let c = (CX.zero, "Bolt Distance")
        b.rod("Barrel", c: c, r: "Diameter / 2", from: "-Length", to: CX.zero)
        b.rod("Head", c: c, r: "Head Diameter / 2", from: CX.zero, to: CX.mm(1))
        b.at(CBL.fine) { b in
            b.box("Slot", x: ("-Head Diameter * 0.45", "Head Diameter * 0.45"), y: ("Bolt Distance - 0.0007 m", "Bolt Distance + 0.0007 m"), z: (CX.mm(-1.5), CX.mm(1.2)), void: true)
            b.rod("Thread Hole", axis: .y, c: (CX.zero, "-Length / 2"), r: "Diameter * 0.3", from: "Bolt Distance - Diameter / 2 - 0.0005 m", to: "Bolt Distance + Diameter / 2 + 0.0005 m",
                  void: true, sides: 16)
        }
        b.symCircle(.face, CBL.all, c: c, r: "Head Diameter / 2")
        b.symLine(.face, CBL.coarse, ("-Head Diameter * 0.45", "Bolt Distance"), ("Head Diameter * 0.45", "Bolt Distance"))
        b.drill("Cross dowel bore", x: CX.zero, y: "Bolt Distance", diameter: "Diameter", depth: "Length + 0.001 m")
        b.edgeDrill("Bolt hole", x: CX.zero, z: "-Length / 2", diameter: "Diameter * 0.7", depth: "Bolt Distance + Diameter / 2")
        b.symRect(.top, CBL.coarse, ("-Head Diameter / 2", "-Length"), ("Head Diameter / 2", CX.mm(1)))
        let mm = ComponentKit.mm
        b.type("M6 x 10 x 20 mm", [:], cost: 0.20, model: "XD-M620", isDefault: true)
        b.type("M8 x 12 x 24 mm", ["Diameter": mm(12), "Length": mm(24), "Head Diameter": mm(13.5), "Bolt Distance": mm(30)], texts: ["Thread": "M8"], cost: 0.30, model: "XD-M824")
        return b.build()
    }

    /// A threaded insert: a flanged steel or brass sleeve screwed into a pilot hole, giving a machine thread in wood.
    static func threadedInsert() -> ComponentDefinition {
        var b = ComponentBuilder("Threaded Insert", .connectors, "Inserts", "Threaded insert: a flanged sleeve with an outer wood thread and an inner machine thread, for bolts, legs and glides.")
        b.tags("threaded insert", "insert", "screw-in nut", "m6", "m8", "1/4-20", "5/16-18", "thread")
        b.aliases("insert nut", "wood insert", "screw-in insert", "tee nut", "t-nut", "e-z lok", "knife thread insert")
        b.hardwareKind(.screw)
        b.material("Finish Material", .brass)
        b.text("Thread", "M6")
        b.length("Outer Diameter", ComponentKit.mm(10))
        b.length("Length", ComponentKit.mm(13))
        b.length("Flange Diameter", ComponentKit.mm(12))
        b.length("Bore Diameter", ComponentKit.mm(6))
        b.length("Pilot Diameter", ComponentKit.mm(8), group: .manufacturing)
        b.flag("Flanged", true, instance: false)
        b.host(ComponentHostKind.carcass + [.leg, .rail], faces: [.any])
        b.rod("Sleeve", r: "Outer Diameter / 2 - 0.0005 m", from: "-Length", to: CX.zero)
        b.shown(by: "Flanged") { b in b.rod("Flange", r: "Flange Diameter / 2", from: CX.zero, to: CX.mm(1)) }
        b.rod("Bore", r: "Bore Diameter / 2", from: "-Length - 0.001 m", to: CX.mm(1.2), void: true, sides: 16)
        b.at(CBL.fine) { b in
            for k in 0..<4 {
                let z = "-Length * \(LX.num(0.2 + 0.2 * Double(k)))"
                b.rod("Thread \(k + 1)", r: "Outer Diameter / 2", from: "\(z) - 0.0012 m", to: z, sides: 20)
            }
        }
        b.symCircle(.face, CBL.all, r: "Outer Diameter / 2")
        b.symCircle(.face, CBL.mediumFine, r: "Bore Diameter / 2")
        b.drill("Insert pilot", x: CX.zero, y: CX.zero, diameter: "Pilot Diameter", depth: "Length + 0.002 m")
        b.symRect(.top, CBL.coarse, ("-Flange Diameter / 2", "-Length"), ("Flange Diameter / 2", CX.mm(1)))
        let mm = ComponentKit.mm
        b.type("M6 x 13 mm", [:], flags: ["Flanged": true], cost: 0.25, model: "TI-M613", isDefault: true)
        b.type("M8 x 15 mm", ["Outer Diameter": mm(12), "Length": mm(15), "Flange Diameter": mm(14), "Bore Diameter": mm(8), "Pilot Diameter": mm(10)],
               flags: ["Flanged": true], texts: ["Thread": "M8"], cost: 0.32, model: "TI-M815")
        b.type("1/4\"-20 x 1/2\"", ["Outer Diameter": ComponentKit.inch(0.41), "Length": ComponentKit.inch(0.5), "Flange Diameter": ComponentKit.inch(0.47),
                                     "Bore Diameter": ComponentKit.inch(0.25), "Pilot Diameter": ComponentKit.inch(0.3125)],
               flags: ["Flanged": false], texts: ["Thread": "1/4\"-20"], cost: 0.28, model: "TI-1420")
        return b.build()
    }

    // MARK: Brackets and plates

    /// The screw holes of a bracket leg along X: `n` holes at `pitch`, centred, at height y on the face.
    static func bracketScrews(_ b: inout ComponentBuilder, n: Int, pitch: String, y: String, label: String, target: ComponentMountTarget = .host) {
        for k in 0..<n {
            let x = "(\(LX.num(Double(k) - Double(n - 1) / 2))) * (\(pitch))"
            b.drill(label, x: x, y: y, diameter: "Screw Diameter * 0.6", depth: "Screw Length", target: target)
        }
    }

    /// A moulded plastic corner block: a triangular block in an inside corner, screwed to both parts.
    static func cornerBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Corner Bracket", .connectors, "Brackets", "Plastic corner block for an inside corner, screwed to both parts; the two-piece type comes apart.")
        b.tags("corner bracket", "corner block", "plastic", "knock down", "kd", "inside corner")
        b.aliases("corner brace", "corner joint block", "modesty block", "2-part corner block", "kd block")
        b.hardwareKind(.screw)
        b.material("Finish Material", .whitePlastic)
        b.length("Leg Length", ComponentKit.mm(30))
        b.length("Width", ComponentKit.mm(20))
        b.length("Wall", ComponentKit.mm(3))
        b.length("Screw Diameter", ComponentKit.mm(4), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(16), group: .manufacturing)
        b.integer("Screws per Leg", 1, group: .manufacturing)
        b.host(ComponentHostKind.carcass + [.rail], faces: [.inside], align: .bottomLeft)
        // A triangular prism in the corner between the face (Z = 0) and the other part (Y = 0).
        b.extrusion("Block", profile: ComponentKit.points([(CX.zero, CX.zero), ("Leg Length", CX.zero), (CX.zero, "Leg Length")]), plane: .yz, from: "-Width / 2", to: "Width / 2")
        b.at(CBL.fine) { b in
            b.rod("Screw Boss Face", axis: .z, c: (CX.zero, "Leg Length * 0.55"), r: "Screw Diameter * 0.9", from: CX.zero, to: "Leg Length * 0.45 - Wall", void: true, sides: 12)
            b.rod("Screw Boss Edge", axis: .y, c: (CX.zero, "Leg Length * 0.55"), r: "Screw Diameter * 0.9", from: CX.zero, to: "Leg Length * 0.45 - Wall", void: true, sides: 12)
        }
        b.symRect(.face, CBL.all, ("-Width / 2", CX.zero), ("Width / 2", "Leg Length"))
        b.symbol(.side, CBL.all, .polyline(ComponentKit.points([(CX.zero, CX.zero), ("Leg Length", CX.zero), (CX.zero, "Leg Length")]), closed: true))
        b.drill("Corner bracket screw", x: CX.zero, y: "Leg Length * 0.55", diameter: "Screw Diameter * 0.6", depth: "Screw Length")
        b.drill("Corner bracket screw", x: CX.zero, y: "Leg Length * 0.55", diameter: "Screw Diameter * 0.6", depth: "Screw Length", target: .counterpart)
        let mm = ComponentKit.mm
        b.type("Corner Bracket - 20 mm", ["Leg Length": mm(20), "Width": mm(14), "Screw Length": mm(13), "Screw Diameter": mm(3.5)], cost: 0.10, model: "CBK-20")
        b.type("Corner Bracket - 30 mm", [:], cost: 0.14, model: "CBK-30", isDefault: true)
        b.type("Corner Bracket - 40 mm", ["Leg Length": mm(40), "Width": mm(26), "Wall": mm(3.5)], cost: 0.19, model: "CBK-40")
        return b.build()
    }

    /// A steel angle (L) bracket: two screwed legs at 90°.
    static func lBracket() -> ComponentDefinition {
        var b = ComponentBuilder("L-Bracket", .connectors, "Brackets", "Steel L (angle) bracket: two legs at 90° with countersunk screw holes, for inside corners.")
        b.tags("l-bracket", "l bracket", "angle", "corner brace", "steel", "inside corner")
        b.aliases("angle bracket", "corner brace", "angle iron", "right angle bracket", "shelf angle")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        b.length("Leg A", ComponentKit.mm(40))
        b.length("Leg B", ComponentKit.mm(40))
        b.length("Width", ComponentKit.mm(16))
        b.length("Thickness", ComponentKit.mm(2))
        b.length("Screw Diameter", ComponentKit.mm(4), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(16), group: .manufacturing)
        b.integer("Holes per Leg", 2, group: .manufacturing)
        b.host(ComponentHostKind.carcass + [.rail, .leg], faces: [.inside], align: .bottomLeft)
        b.bracket("L", width: "Width", legA: "Leg A", legB: "Leg B", thickness: "Thickness")
        b.at(CBL.fine) { b in
            for (k, f) in [0.35, 0.75].enumerated() {
                b.rod("Hole A \(k + 1)", c: (CX.zero, "Leg A * \(LX.num(f))"), r: "Screw Diameter / 2 + 0.0003 m", from: CX.mm(-0.1), to: "Thickness + 0.0001 m", void: true, sides: 12)
                b.rod("Hole B \(k + 1)", axis: .y, c: (CX.zero, "Leg B * \(LX.num(f))"), r: "Screw Diameter / 2 + 0.0003 m", from: CX.mm(-0.1), to: "Thickness + 0.0001 m", void: true, sides: 12)
            }
        }
        b.symRect(.face, CBL.all, ("-Width / 2", CX.zero), ("Width / 2", "Leg A"))
        b.symbol(.side, CBL.all, .polyline(ComponentKit.points([("Leg B", CX.zero), (CX.zero, CX.zero), (CX.zero, "Leg A")]), closed: false))
        for f in ["0.35", "0.75"] {
            b.drill("L-bracket screw", x: CX.zero, y: "Leg A * \(f)", diameter: "Screw Diameter * 0.6", depth: "Screw Length")
            b.drill("L-bracket screw", x: CX.zero, y: "Leg B * \(f)", diameter: "Screw Diameter * 0.6", depth: "Screw Length", target: .counterpart)
        }
        let mm = ComponentKit.mm
        b.type("L-Bracket - 25 x 25 x 16 mm", ["Leg A": mm(25), "Leg B": mm(25), "Width": mm(16), "Thickness": mm(1.5)], cost: 0.18, model: "LB-2525")
        b.type("L-Bracket - 40 x 40 x 20 mm", ["Width": mm(20)], cost: 0.28, model: "LB-4040", isDefault: true)
        b.type("L-Bracket - 60 x 60 x 25 mm", ["Leg A": mm(60), "Leg B": mm(60), "Width": mm(25), "Thickness": mm(2.5), "Screw Diameter": mm(5)], cost: 0.42, model: "LB-6060")
        return b.build()
    }

    /// A flat T plate: a bar across the joint and a stem along the part that butts into it.
    static func tBracket() -> ComponentDefinition {
        var b = ComponentBuilder("T-Bracket", .connectors, "Brackets", "Flat steel T plate across a T joint (a rail into a stile, a divider into a shelf), screwed on the face.")
        b.tags("t-bracket", "t plate", "tee plate", "mending plate", "steel", "flat")
        b.aliases("tee bracket", "t mending plate", "t-shaped plate", "flat t brace")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        b.length("Width", ComponentKit.mm(75))
        b.length("Height", ComponentKit.mm(75))
        b.length("Bar Width", ComponentKit.mm(16))
        b.length("Thickness", ComponentKit.mm(1.5))
        b.length("Screw Diameter", ComponentKit.mm(4), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(16), group: .manufacturing)
        b.host(ComponentHostKind.carcass + [.rail, .back], faces: [.inside, .outside, .back], align: .center)
        b.box("Bar", x: ("-Width / 2", "Width / 2"), y: ("-Bar Width / 2", "Bar Width / 2"), z: (CX.zero, "Thickness"))
        b.box("Stem", x: ("-Bar Width / 2", "Bar Width / 2"), y: ("Bar Width / 2", "Height - Bar Width / 2"), z: (CX.zero, "Thickness"))
        b.at(CBL.fine) { b in
            b.screwHeads("Screw", [("-Width * 0.38", CX.zero), ("Width * 0.38", CX.zero), (CX.zero, "Height * 0.7")], z: "Thickness")
        }
        b.symRect(.face, CBL.all, ("-Width / 2", "-Bar Width / 2"), ("Width / 2", "Bar Width / 2"))
        b.symRect(.face, CBL.all, ("-Bar Width / 2", "Bar Width / 2"), ("Bar Width / 2", "Height - Bar Width / 2"))
        b.drill("T-bracket screw", x: "-Width * 0.38", y: CX.zero, diameter: "Screw Diameter * 0.6", depth: "Screw Length")
        b.drill("T-bracket screw", x: "Width * 0.38", y: CX.zero, diameter: "Screw Diameter * 0.6", depth: "Screw Length")
        b.drill("T-bracket screw", x: CX.zero, y: "Height * 0.7", diameter: "Screw Diameter * 0.6", depth: "Screw Length")
        b.symRect(.top, CBL.coarse, ("-Width / 2", CX.zero), ("Width / 2", "Thickness"))
        let mm = ComponentKit.mm
        b.type("T-Bracket - 50 x 50 mm", ["Width": mm(50), "Height": mm(50), "Bar Width": mm(13)], cost: 0.22, model: "TB-50")
        b.type("T-Bracket - 75 x 75 mm", [:], cost: 0.30, model: "TB-75", isDefault: true)
        b.type("T-Bracket - 100 x 100 mm", ["Width": mm(100), "Height": mm(100), "Bar Width": mm(19), "Thickness": mm(2)], cost: 0.42, model: "TB-100")
        return b.build()
    }

    /// A reinforced angle bracket with a pressed gusset.
    static func angleBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Angle Bracket", .connectors, "Brackets", "Reinforced steel angle bracket with a pressed gusset, for heavy corners (frames, beds, benches).")
        b.tags("angle bracket", "gusset", "reinforced", "corner", "steel", "heavy duty")
        b.aliases("reinforced angle", "gusset bracket", "heavy angle", "corner gusset", "angle brace")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        b.length("Leg A", ComponentKit.mm(60))
        b.length("Leg B", ComponentKit.mm(60))
        b.length("Width", ComponentKit.mm(40))
        b.length("Thickness", ComponentKit.mm(2.5))
        b.length("Gusset Size", ComponentKit.mm(20))
        b.length("Screw Diameter", ComponentKit.mm(5), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(20), group: .manufacturing)
        b.number("Load Rating", 200, unit: "lb", group: .data)
        b.host(ComponentHostKind.carcass + [.rail, .leg], faces: [.inside], align: .bottomLeft)
        b.bracket("Angle", width: "Width", legA: "Leg A", legB: "Leg B", thickness: "Thickness")
        b.extrusion("Gusset", profile: ComponentKit.points([("Thickness", "Thickness"), ("Gusset Size", "Thickness"), ("Thickness", "Gusset Size")]), plane: .yz,
                    from: "-Thickness / 2", to: "Thickness / 2")
        b.at(CBL.fine) { b in
            for (k, x) in ["-Width * 0.28", "Width * 0.28"].enumerated() {
                b.rod("Hole A \(k + 1)", c: (x, "Leg A * 0.65"), r: "Screw Diameter / 2 + 0.0003 m", from: CX.mm(-0.1), to: "Thickness + 0.0001 m", void: true, sides: 12)
                b.rod("Hole B \(k + 1)", axis: .y, c: (x, "Leg B * 0.65"), r: "Screw Diameter / 2 + 0.0003 m", from: CX.mm(-0.1), to: "Thickness + 0.0001 m", void: true, sides: 12)
            }
        }
        b.symRect(.face, CBL.all, ("-Width / 2", CX.zero), ("Width / 2", "Leg A"))
        b.symbol(.side, CBL.all, .polyline(ComponentKit.points([("Leg B", CX.zero), (CX.zero, CX.zero), (CX.zero, "Leg A")]), closed: false),
                 .line(("Gusset Size", CX.zero), (CX.zero, "Gusset Size")))
        for x in ["-Width * 0.28", "Width * 0.28"] {
            b.drill("Angle bracket screw", x: x, y: "Leg A * 0.65", diameter: "Screw Diameter * 0.6", depth: "Screw Length")
            b.drill("Angle bracket screw", x: x, y: "Leg B * 0.65", diameter: "Screw Diameter * 0.6", depth: "Screw Length", target: .counterpart)
        }
        let mm = ComponentKit.mm
        b.type("Angle Bracket - 40 mm", ["Leg A": mm(40), "Leg B": mm(40), "Width": mm(30), "Gusset Size": mm(15), "Thickness": mm(2)], numbers: ["Load Rating": 120],
               cost: 0.45, model: "AB-40")
        b.type("Angle Bracket - 60 mm", [:], cost: 0.65, model: "AB-60", isDefault: true)
        b.type("Angle Bracket - 90 mm", ["Leg A": mm(90), "Leg B": mm(90), "Width": mm(50), "Gusset Size": mm(30), "Thickness": mm(3)], numbers: ["Load Rating": 350],
               cost: 1.10, model: "AB-90")
        return b.build()
    }

    /// A flat straight mending plate across a butt joint.
    static func joiningPlate() -> ComponentDefinition {
        var b = ComponentBuilder("Joining Plate", .connectors, "Plates", "Flat straight steel plate across a butt joint, with countersunk holes.")
        b.tags("joining plate", "mending plate", "flat plate", "strap", "steel", "repair")
        b.aliases("mending plate", "flat strap", "straight plate", "repair plate", "flat bracket")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        b.length("Length", ComponentKit.mm(75))
        b.length("Width", ComponentKit.mm(19))
        b.length("Thickness", ComponentKit.mm(1.5))
        b.length("Screw Diameter", ComponentKit.mm(4), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(16), group: .manufacturing)
        b.integer("Holes", 4, group: .manufacturing)
        b.host(ComponentHostKind.carcass + [.rail, .back], faces: [.back, .inside, .outside, .bottom])
        b.plate("Plate", w: "Length", h: "Width", r: "Width * 0.15", z: (CX.zero, "Thickness"))
        b.at(CBL.fine) { b in
            for (k, f) in [-0.4, -0.15, 0.15, 0.4].enumerated() {
                b.rod("Hole \(k + 1)", c: ("Length * \(LX.num(f))", CX.zero), r: "Screw Diameter / 2 + 0.0003 m", from: CX.mm(-0.1), to: "Thickness + 0.0001 m", void: true, sides: 12)
            }
        }
        b.symRect(.face, CBL.all, ("-Length / 2", "-Width / 2"), ("Length / 2", "Width / 2"))
        b.symLine(.face, CBL.coarse, (CX.zero, "-Width / 2"), (CX.zero, "Width / 2"))
        for f in ["-0.4", "-0.15", "0.15", "0.4"] {
            b.drill("Plate screw", x: "Length * \(f)", y: CX.zero, diameter: "Screw Diameter * 0.6", depth: "Screw Length")
        }
        b.symRect(.top, CBL.coarse, ("-Length / 2", CX.zero), ("Length / 2", "Thickness"))
        let mm = ComponentKit.mm
        b.type("Joining Plate - 50 x 16 mm", ["Length": mm(50), "Width": mm(16), "Thickness": mm(1.2)], cost: 0.15, model: "JP-50")
        b.type("Joining Plate - 75 x 19 mm", [:], cost: 0.20, model: "JP-75", isDefault: true)
        b.type("Joining Plate - 100 x 25 mm", ["Length": mm(100), "Width": mm(25), "Thickness": mm(2)], cost: 0.28, model: "JP-100")
        return b.build()
    }

    /// A wide perforated connector plate for frames (stiles, rails, bed frames), with a grid of holes.
    static func connectorPlate() -> ComponentDefinition {
        var b = ComponentBuilder("Connector Plate", .connectors, "Plates", "Wide perforated steel plate joining frame members edge to edge, with a grid of screw holes.")
        b.tags("connector plate", "nail plate", "perforated plate", "frame", "steel", "mending")
        b.aliases("gang plate", "truss plate", "perforated strap", "frame plate", "joining plate wide")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        b.length("Length", ComponentKit.mm(100))
        b.length("Width", ComponentKit.mm(75))
        b.length("Thickness", ComponentKit.mm(1.5))
        b.length("Hole Pitch", ComponentKit.mm(20))
        b.length("Screw Diameter", ComponentKit.mm(4), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(20), group: .manufacturing)
        b.host([.rail, .leg, .back, .sidePanel, .bottom], faces: [.back, .inside, .outside, .bottom])
        b.box("Plate", x: ("-Length / 2", "Length / 2"), y: ("-Width / 2", "Width / 2"), z: (CX.zero, "Thickness"))
        b.at(CBL.fine) { b in
            for i in -1...1 { for j in -1...1 where (i + j) % 2 == 0 {
                b.rod("Hole \(i + 2)\(j + 2)", c: ("Hole Pitch * \(i) * 1.5", "Hole Pitch * \(j)"), r: "Screw Diameter / 2 + 0.0003 m", from: CX.mm(-0.1), to: "Thickness + 0.0001 m",
                      void: true, sides: 12)
            } }
        }
        b.symRect(.face, CBL.all, ("-Length / 2", "-Width / 2"), ("Length / 2", "Width / 2"))
        b.symLine(.face, CBL.coarse, ("-Length / 2", "-Width / 2"), ("Length / 2", "Width / 2"))
        for (x, y) in [("-Hole Pitch * 1.5", "-Hole Pitch"), ("Hole Pitch * 1.5", "-Hole Pitch"), ("-Hole Pitch * 1.5", "Hole Pitch"), ("Hole Pitch * 1.5", "Hole Pitch"), (CX.zero, CX.zero)] {
            b.drill("Plate screw", x: x, y: y, diameter: "Screw Diameter * 0.6", depth: "Screw Length")
        }
        b.symRect(.top, CBL.coarse, ("-Length / 2", CX.zero), ("Length / 2", "Thickness"))
        let mm = ComponentKit.mm
        b.type("Connector Plate - 80 x 50 mm", ["Length": mm(80), "Width": mm(50), "Hole Pitch": mm(15)], cost: 0.30, model: "CP-8050")
        b.type("Connector Plate - 100 x 75 mm", [:], cost: 0.42, model: "CP-10075", isDefault: true)
        b.type("Connector Plate - 150 x 100 mm", ["Length": mm(150), "Width": mm(100), "Hole Pitch": mm(25), "Thickness": mm(2)], cost: 0.65, model: "CP-150100")
        return b.build()
    }

    // MARK: Shelf supports (06 list; 08 has the shelf systems)

    /// A plug-in shelf support with a rest and a screw or lock tab, in a 5 mm hole on the 32 mm system.
    static func shelfSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Support", .connectors, "Shelf Supports", "Plug-in shelf support: a 5 mm pin with an L rest the shelf sits on, with a screw hole or a lock tab against tipping.")
        b.tags("shelf support", "shelf rest", "5 mm", "32 mm system", "l support", "plug-in")
        b.aliases("shelf supporter", "bracket pin", "shelf rest pin", "l-shaped shelf support", "locking shelf support")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .nickelPin)
        b.length("Pin Diameter", ComponentKit.mm(5))
        b.length("Pin Length", ComponentKit.mm(8))
        b.length("Rest Width", ComponentKit.mm(10))
        b.length("Rest Depth", ComponentKit.mm(16))
        b.length("Rest Height", ComponentKit.mm(14))
        b.length("Thickness", ComponentKit.mm(1.5))
        b.flag("Lock Tab", false, instance: false)
        b.host([.sidePanel, .divider], faces: [.inside], align: .center)
        b.rod("Pin", r: "Pin Diameter / 2", from: "-Pin Length", to: CX.zero)
        b.box("Back Plate", x: ("-Rest Width / 2", "Rest Width / 2"), y: ("-Rest Height / 2", "Rest Height / 2"), z: (CX.zero, "Thickness"))
        b.box("Rest", x: ("-Rest Width / 2", "Rest Width / 2"), y: ("Rest Height / 2 - Thickness", "Rest Height / 2"), z: (CX.zero, "Rest Depth"))
        b.shown(by: "Lock Tab") { b in
            b.box("Lock Tab", x: ("-Rest Width / 2", "Rest Width / 2"), y: ("Rest Height / 2", "Rest Height / 2 + 0.004 m"), z: ("Rest Depth - Thickness", "Rest Depth"))
        }
        b.symRect(.face, CBL.all, ("-Rest Width / 2", "-Rest Height / 2"), ("Rest Width / 2", "Rest Height / 2"))
        b.symRect(.top, CBL.all, ("-Rest Width / 2", CX.zero), ("Rest Width / 2", "Rest Depth"))
        b.drill("Shelf support", x: CX.zero, y: CX.zero, diameter: "Pin Diameter", depth: "Pin Length + 0.001 m")
        b.type("Shelf Support - 5 mm", [:], flags: ["Lock Tab": false], cost: 0.12, model: "SS-5", isDefault: true)
        b.type("Shelf Support - 5 mm Locking", [:], flags: ["Lock Tab": true], cost: 0.18, model: "SS-5L")
        b.type("Shelf Support - 1/4\"", ["Pin Diameter": ComponentKit.inch(0.25), "Pin Length": ComponentKit.inch(0.375), "Rest Width": ComponentKit.inch(0.5),
                                          "Rest Depth": ComponentKit.inch(0.625)], flags: ["Lock Tab": false], cost: 0.13, model: "SS-14")
        return b.build()
    }

    /// A hidden (blind) shelf support: a steel rod in the side's face that goes into a hole in the shelf's end.
    static func hiddenShelfSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Hidden Shelf Support", .connectors, "Shelf Supports", "Blind shelf support: a steel rod set in the side that goes into a hole drilled in the shelf's end, so nothing shows.")
        b.tags("hidden shelf support", "blind support", "invisible", "rod", "shelf", "8 mm", "10 mm")
        b.aliases("invisible shelf support", "blind shelf pin", "hidden shelf pin", "shelf rod support")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .steel)
        b.length("Rod Diameter", ComponentKit.mm(8))
        b.length("Side Depth", ComponentKit.mm(10))
        b.length("Shelf Depth", ComponentKit.mm(70))
        b.number("Load Rating", 25, unit: "lb", group: .data)
        b.host([.sidePanel, .divider], faces: [.inside], align: .center)
        b.rod("Rod", r: "Rod Diameter / 2", from: "-Side Depth", to: "Shelf Depth")
        b.at(CBL.fine) { b in b.rod("Tip", r: "Rod Diameter / 2 - 0.0008 m", from: "Shelf Depth", to: "Shelf Depth + 0.0008 m") }
        b.symCircle(.face, CBL.all, r: "Rod Diameter / 2")
        b.symRect(.top, CBL.all, ("-Rod Diameter / 2", "-Side Depth"), ("Rod Diameter / 2", "Shelf Depth"), dashed: true)
        b.drill("Hidden support (side)", x: CX.zero, y: CX.zero, diameter: "Rod Diameter", depth: "Side Depth + 0.001 m")
        b.drill("Hidden support (shelf end)", x: CX.zero, y: CX.zero, diameter: "Rod Diameter + 0.0005 m", depth: "Shelf Depth + 0.002 m", target: .counterpart)
        let mm = ComponentKit.mm
        b.type("Hidden Support - 8 x 80 mm", [:], cost: 0.35, model: "HS-880", isDefault: true)
        b.type("Hidden Support - 10 x 120 mm", ["Rod Diameter": mm(10), "Side Depth": mm(15), "Shelf Depth": mm(105)], numbers: ["Load Rating": 40], cost: 0.55, model: "HS-10120")
        return b.build()
    }

    // MARK: Clips and knock-down fittings

    /// A two-block knock-down fitting: two moulded blocks screwed to the two parts and bolted together.
    static func knockDownFitting() -> ComponentDefinition {
        var b = ComponentBuilder("Knock-Down Fitting", .connectors, "Knock-Down Fittings", "Two-block knock-down fitting: moulded blocks screwed to each part and drawn together by a machine screw.")
        b.tags("knock-down", "knock down", "kd fitting", "block", "two-part", "rta", "plastic")
        b.aliases("kd block", "two-piece connector", "modesty block", "rta block", "joint block")
        b.hardwareKind(.screw)
        b.material("Finish Material", .greyPlastic)
        b.length("Block Length", ComponentKit.mm(32))
        b.length("Block Width", ComponentKit.mm(14))
        b.length("Block Height", ComponentKit.mm(12))
        b.length("Screw Diameter", ComponentKit.mm(4), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(13), group: .manufacturing)
        b.flag("Double", false, instance: false)
        b.host(ComponentHostKind.carcass, faces: [.inside], align: .bottomLeft)
        // One block on the face (along X) and one on the other part (Y < 0 side, standing on Y = 0).
        b.box("Block A", x: ("-Block Length / 2", "Block Length / 2"), y: (CX.zero, "Block Width"), z: (CX.zero, "Block Height"))
        b.box("Block B", x: ("-Block Length / 2", "Block Length / 2"), y: ("Block Width", "Block Width + Block Height"), z: (CX.zero, "Block Width"))
        b.shown(by: "Double") { b in
            b.box("Block C", x: ("Block Length / 2 + 0.002 m", "Block Length * 1.5 + 0.002 m"), y: (CX.zero, "Block Width"), z: (CX.zero, "Block Height"))
        }
        b.at(CBL.fine) { b in
            b.screwHeads("Screw", [("-Block Length * 0.3", "Block Width / 2"), ("Block Length * 0.3", "Block Width / 2")], z: "Block Height", diameter: "Screw Diameter * 1.8")
        }
        b.boxSymbols(x: ("-Block Length / 2", "Block Length / 2"), y: (CX.zero, "Block Width + Block Height"), z: (CX.zero, "Block Height"))
        for x in ["-Block Length * 0.3", "Block Length * 0.3"] {
            b.drill("KD fitting screw", x: x, y: "Block Width / 2", diameter: "Screw Diameter * 0.6", depth: "Screw Length")
            b.drill("KD fitting screw", x: x, y: "Block Width / 2", diameter: "Screw Diameter * 0.6", depth: "Screw Length", target: .counterpart)
        }
        b.type("Knock-Down Fitting - Single", [:], flags: ["Double": false], cost: 0.25, model: "KD-1", isDefault: true)
        b.type("Knock-Down Fitting - Double", [:], flags: ["Double": true], cost: 0.40, model: "KD-2")
        return b.build()
    }

    /// A spring clip that holds a removable panel (backs, plinths, service panels) in a 5 mm hole or a groove.
    static func panelClip() -> ComponentDefinition {
        var b = ComponentBuilder("Panel Clip", .connectors, "Clips", "Spring steel clip that holds a removable panel (back, plinth, service panel) against its frame.")
        b.tags("panel clip", "spring clip", "back panel clip", "plinth clip", "removable panel", "clip")
        b.aliases("back clip", "panel retainer clip", "spring retainer", "access panel clip", "kick clip")
        b.hardwareKind(.screw)
        b.material("Finish Material", .steel)
        b.length("Panel Thickness Range", ComponentKit.mm(16))
        b.length("Width", ComponentKit.mm(12))
        b.length("Height", ComponentKit.mm(24))
        b.length("Spring Depth", ComponentKit.mm(8))
        b.length("Thickness", ComponentKit.mm(0.8))
        b.length("Pin Diameter", ComponentKit.mm(5), group: .manufacturing)
        b.host([.back, .plinth, .sidePanel, .bottom], faces: [.inside, .back], align: .center)
        b.box("Base", x: ("-Width / 2", "Width / 2"), y: ("-Height / 2", "Height / 2"), z: (CX.zero, "Thickness"))
        b.box("Spring", x: ("-Width / 2", "Width / 2"), y: ("Height / 2 - Thickness", "Height / 2"), z: (CX.zero, "Spring Depth"))
        b.box("Lip", x: ("-Width / 2", "Width / 2"), y: ("Height / 2 - Thickness", "Height / 2 + Spring Depth * 0.5"), z: ("Spring Depth - Thickness", "Spring Depth"))
        b.rod("Pin", r: "Pin Diameter / 2", from: CX.mm(-8), to: CX.zero)
        b.symRect(.face, CBL.all, ("-Width / 2", "-Height / 2"), ("Width / 2", "Height / 2"))
        b.symbol(.side, CBL.all, .polyline(ComponentKit.points([(CX.zero, "-Height / 2"), (CX.zero, "Height / 2"), ("Spring Depth", "Height / 2"),
                                                                 ("Spring Depth", "Height / 2 + Spring Depth * 0.5")]), closed: false))
        b.drill("Panel clip pin", x: CX.zero, y: CX.zero, diameter: "Pin Diameter", depth: CX.mm(9))
        let mm = ComponentKit.mm
        b.type("Panel Clip - 16 mm", [:], cost: 0.10, model: "PC-16", isDefault: true)
        b.type("Panel Clip - 19 mm", ["Panel Thickness Range": mm(19), "Spring Depth": mm(10)], cost: 0.11, model: "PC-19")
        return b.build()
    }

    /// A magnetic connector: a magnet in a cup in one part and a steel striker in the other (removable panels, fronts).
    static func magneticConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Magnetic Connector", .connectors, "Clips", "Magnetic connector: a neodymium magnet in a press-in cup and a matching steel striker, for removable panels and covers.")
        b.tags("magnetic connector", "magnet", "neodymium", "press-in", "removable panel", "10 mm", "13 mm", "20 mm")
        b.aliases("magnet cup", "press-in magnet", "magnetic fixing", "concealed magnet", "panel magnet")
        b.hardwareKind(.screw)
        b.material("Finish Material", .steel)
        b.material("Cup Material", .blackPlastic)
        b.length("Magnet Diameter", ComponentKit.mm(10))
        b.length("Cup Diameter", ComponentKit.mm(12))
        b.length("Cup Depth", ComponentKit.mm(7))
        b.length("Striker Thickness", ComponentKit.mm(1.5))
        b.number("Holding Force", 4, unit: "lb", group: .data)
        b.host(ComponentHostKind.carcass + ComponentHostKind.fronts + [.plinth], faces: [.any], align: .center)
        b.slot("Cup Material") { b in b.rod("Cup", r: "Cup Diameter / 2", from: "-Cup Depth", to: CX.zero) }
        b.rod("Magnet", r: "Magnet Diameter / 2", from: CX.mm(-3), to: CX.mm(0.2))
        b.rod("Striker", r: "Cup Diameter / 2", from: "0.0005 m", to: "0.0005 m + Striker Thickness")
        b.symCircle(.face, CBL.all, r: "Cup Diameter / 2")
        b.symCircle(.face, CBL.mediumFine, r: "Magnet Diameter / 2")
        b.drill("Magnet cup", x: CX.zero, y: CX.zero, diameter: "Cup Diameter", depth: "Cup Depth")
        b.drill("Striker", x: CX.zero, y: CX.zero, diameter: "Cup Diameter", depth: "Striker Thickness", target: .counterpart)
        b.symRect(.top, CBL.coarse, ("-Cup Diameter / 2", "-Cup Depth"), ("Cup Diameter / 2", "0.0005 m + Striker Thickness"))
        let mm = ComponentKit.mm
        b.type("Magnetic Connector - 10 mm", [:], numbers: ["Holding Force": 4], cost: 0.55, model: "MC-10", isDefault: true)
        b.type("Magnetic Connector - 13 mm", ["Magnet Diameter": mm(13), "Cup Diameter": mm(15), "Cup Depth": mm(8)], numbers: ["Holding Force": 7], cost: 0.75, model: "MC-13")
        b.type("Magnetic Connector - 20 mm", ["Magnet Diameter": mm(20), "Cup Diameter": mm(22), "Cup Depth": mm(9)], numbers: ["Holding Force": 15], cost: 1.20, model: "MC-20")
        return b.build()
    }

    /// A click (snap-in) assembly clip in a disc-cutter slot: two halves that latch as the parts are pushed together.
    static func assemblyClip() -> ComponentDefinition {
        var b = ComponentBuilder("Furniture Assembly Clip", .connectors, "Clips", "Snap-in assembly clip: two halves in slots cut with a biscuit cutter that latch when the parts are pushed together; tool-free.")
        b.tags("assembly clip", "click connector", "snap", "slot", "biscuit", "tool-free", "knock down")
        b.aliases("click connector", "snap connector", "slot connector", "clip connector", "invisible connector", "biscuit clip")
        b.hardwareKind(.screw)
        b.material("Finish Material", .greyPlastic)
        b.length("Clip Length", ComponentKit.mm(56))
        b.length("Clip Height", ComponentKit.mm(10))
        b.length("Clip Thickness", ComponentKit.mm(4))
        b.length("Slot Depth", ComponentKit.mm(10), group: .manufacturing)
        b.flag("Detachable", true, instance: false)
        b.host(ComponentHostKind.carcass + [.rail], faces: [.frontEdge, .any], align: .center)
        // A lens-shaped clip straddling the joint (Y = 0), in the joint plane.
        let lens = (0...12).map { k -> (String, String) in
            let t = Double(k) / 12, x = -0.5 + t, h = sin(Double.pi * t)
            return ("Clip Length * \(LX.num(x))", "Clip Height * \(LX.num(h))")
        } + (1..<12).reversed().map { k -> (String, String) in
            let t = Double(k) / 12, x = -0.5 + t, h = sin(Double.pi * t)
            return ("Clip Length * \(LX.num(x))", "-Clip Height * \(LX.num(h))")
        }
        b.extrusion("Clip", profile: ComponentKit.points(lens), plane: .xz, from: "-Clip Thickness / 2", to: "Clip Thickness / 2")
        b.at(CBL.fine) { b in
            b.shown(by: "Detachable") { b in b.rod("Release Hole", axis: .y, c: (CX.zero, CX.zero), r: CX.mm(1.5), from: "-Clip Thickness", to: "Clip Thickness", void: true, sides: 12) }
        }
        b.symLine(.face, CBL.all, ("-Clip Length / 2", CX.zero), ("Clip Length / 2", CX.zero))
        b.symbol(.top, CBL.all, .polyline(ComponentKit.points(lens), closed: true))
        b.groove("Clip slot", from: ("-Clip Length / 2", CX.zero), to: ("Clip Length / 2", CX.zero), width: "Clip Thickness", depth: "Slot Depth")
        b.groove("Clip slot", from: ("-Clip Length / 2", CX.zero), to: ("Clip Length / 2", CX.zero), width: "Clip Thickness", depth: "Slot Depth", target: .counterpart)
        let mm = ComponentKit.mm
        b.type("Assembly Clip - 10 mm", [:], flags: ["Detachable": true], cost: 0.60, model: "AC-10", isDefault: true)
        b.type("Assembly Clip - 14 mm", ["Clip Height": mm(14), "Clip Length": mm(66), "Slot Depth": mm(13)], flags: ["Detachable": true], cost: 0.75, model: "AC-14")
        return b.build()
    }

    /// An adjustable (tensioning) connector bolt: a turnbuckle body with two threaded ends, for long spans and frames.
    static func adjustableBolt() -> ComponentDefinition {
        var b = ComponentBuilder("Adjustable Connector Bolt", .connectors, "Bolts and Nuts", "Adjustable connector bolt: a hex body with left and right threads that pulls two parts together as it turns.")
        b.tags("adjustable bolt", "tension bolt", "turnbuckle", "connector", "m6", "m8", "frame")
        b.aliases("tensioning bolt", "turnbuckle connector", "draw bolt", "adjustable fastener", "span bolt")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        b.length("Minimum Length", ComponentKit.mm(50))
        b.length("Adjustment", ComponentKit.mm(20))
        b.length("Extension", ComponentKit.mm(10), instance: true, group: .placement)
        b.length("Diameter", ComponentKit.mm(6))
        b.length("Body Diameter", ComponentKit.mm(12))
        b.length("Body Length", ComponentKit.mm(20))
        b.host([.rail, .leg, .sidePanel, .divider], faces: [.inside], align: .center)
        // Along X, centred on the joint (X = 0 is the gap between the parts).
        b.rod("Body", axis: .x, c: (CX.zero, CX.zero), r: "Body Diameter / 2", from: "-Body Length / 2", to: "Body Length / 2", sides: 6)
        b.rod("Left Thread", axis: .x, r: "Diameter / 2", from: "-(Minimum Length + Extension) / 2", to: "-Body Length / 2")
        b.rod("Right Thread", axis: .x, r: "Diameter / 2", from: "Body Length / 2", to: "(Minimum Length + Extension) / 2")
        b.symRect(.face, CBL.all, ("-(Minimum Length + Extension) / 2", "-Diameter / 2"), ("(Minimum Length + Extension) / 2", "Diameter / 2"))
        b.symRect(.face, CBL.coarse, ("-Body Length / 2", "-Body Diameter / 2"), ("Body Length / 2", "Body Diameter / 2"))
        b.edgeDrill("Bolt hole", x: CX.zero, z: CX.zero, diameter: "Diameter + 0.001 m", depth: "(Minimum Length + Adjustment) / 2")
        b.edgeDrill("Bolt hole", x: CX.zero, z: CX.zero, diameter: "Diameter + 0.001 m", depth: "(Minimum Length + Adjustment) / 2", target: .counterpart)
        b.symRect(.top, CBL.coarse, ("-(Minimum Length + Extension) / 2", "-Body Diameter / 2"), ("(Minimum Length + Extension) / 2", "Body Diameter / 2"))
        let mm = ComponentKit.mm
        b.type("Adjustable Bolt - M6 50-70 mm", [:], cost: 0.85, model: "ADB-M650", isDefault: true)
        b.type("Adjustable Bolt - M8 70-100 mm", ["Minimum Length": mm(70), "Adjustment": mm(30), "Diameter": mm(8), "Body Diameter": mm(14), "Body Length": mm(26)],
               cost: 1.20, model: "ADB-M870")
        return b.build()
    }

    /// A worktop connector: a bolt with two crescent washers in pockets under a worktop joint.
    static func worktopConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Worktop Connector", .connectors, "Bolts and Nuts", "Worktop (countertop) connector: a bolt with two crescent washers in 35 mm pockets routed under a mitre or butt joint.")
        b.tags("worktop connector", "countertop bolt", "mitre bolt", "pull bolt", "65 mm", "150 mm")
        b.aliases("countertop connector", "worktop bolt", "panel bolt", "dog bone bolt", "draw bolt", "miter bolt")
        b.hardwareKind(.screw)
        b.material("Finish Material", .zinc)
        b.length("Bolt Length", ComponentKit.mm(150))
        b.length("Diameter", ComponentKit.mm(8))
        b.length("Pocket Diameter", ComponentKit.mm(35))
        b.length("Pocket Depth", ComponentKit.mm(20), group: .manufacturing)
        b.length("Washer Thickness", ComponentKit.mm(4))
        b.host([.top], faces: [.bottom], align: .center)
        // Across the joint along Y (the joint at Y = 0), under the top (pockets cut up into it from Z = 0).
        let z = "-Pocket Depth / 2"
        b.rod("Bolt", axis: .y, c: (CX.zero, z), r: "Diameter / 2", from: "-Bolt Length / 2", to: "Bolt Length / 2")
        for (n, range) in [("Washer A", ("-Bolt Length / 2", "-Bolt Length / 2 + Washer Thickness")), ("Washer B", ("Bolt Length / 2 - Washer Thickness", "Bolt Length / 2"))] {
            b.extrusion(n, profile: ComponentKit.points([("-Pocket Diameter * 0.45", CX.zero), ("Pocket Diameter * 0.45", CX.zero), ("Pocket Diameter * 0.3", "-Pocket Depth * 0.9"),
                                                         ("-Pocket Diameter * 0.3", "-Pocket Depth * 0.9")]), plane: .xz, from: range.0, to: range.1)
        }
        b.symLine(.face, CBL.all, (CX.zero, "-Bolt Length / 2"), (CX.zero, "Bolt Length / 2"))
        b.symCircle(.face, CBL.all, c: (CX.zero, "Bolt Length / 2"), r: "Pocket Diameter / 2")
        b.symCircle(.face, CBL.all, c: (CX.zero, "-Bolt Length / 2"), r: "Pocket Diameter / 2")
        b.drill("Worktop connector pocket", x: CX.zero, y: "Bolt Length / 2", diameter: "Pocket Diameter", depth: "Pocket Depth")
        b.groove("Worktop connector bolt slot", from: (CX.zero, CX.zero), to: (CX.zero, "Bolt Length / 2"), width: "Diameter + 0.002 m", depth: "Pocket Depth / 2 + Diameter / 2")
        b.drill("Worktop connector pocket", x: CX.zero, y: "Bolt Length / 2", diameter: "Pocket Diameter", depth: "Pocket Depth", target: .counterpart)
        b.requires(.hostThickness(min: CX.mm(28), max: nil))
        b.symRect(.top, CBL.coarse, ("-Pocket Diameter / 2", "-Pocket Depth"), ("Pocket Diameter / 2", CX.zero))
        let mm = ComponentKit.mm
        b.type("Worktop Connector - 65 mm", ["Bolt Length": mm(65), "Diameter": mm(6), "Pocket Depth": mm(18)], cost: 0.95, model: "WC-65")
        b.type("Worktop Connector - 150 mm", [:], cost: 1.40, model: "WC-150", isDefault: true)
        return b.build()
    }

    /// A bed frame connector: a hook plate on the rail end that drops into a slotted plate on the post (no tools).
    static func bedFrameConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Bed Frame Connector", .connectors, "Bed Fittings", "Bed rail fastener: a hook plate on the rail's end that drops into a slotted plate on the post; tool-free.")
        b.tags("bed frame connector", "bed rail fastener", "hook plate", "bed bracket", "rail", "post")
        b.aliases("bed rail bracket", "bed hook", "bed fitting", "bed rail connector", "interlocking bracket", "keyhole plate")
        b.hardwareKind(.screw)
        b.material("Finish Material", .matteBlack)
        b.length("Plate Height", ComponentKit.mm(100))
        b.length("Plate Width", ComponentKit.mm(40))
        b.length("Thickness", ComponentKit.mm(3))
        b.length("Hook Depth", ComponentKit.mm(12))
        b.length("Screw Diameter", ComponentKit.mm(5), group: .manufacturing)
        b.length("Screw Length", ComponentKit.mm(30), group: .manufacturing)
        b.number("Load Rating", 400, unit: "lb", group: .data)
        b.host([.leg, .rail, .sidePanel], faces: [.inside, .any], align: .center)
        b.box("Post Plate", x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Height / 2", "Plate Height / 2"), z: (CX.zero, "Thickness"))
        b.box("Rail Plate", x: ("-Plate Width / 2 + 0.004 m", "Plate Width / 2 - 0.004 m"), y: ("-Plate Height / 2 + 0.01 m", "Plate Height / 2 - 0.01 m"),
              z: ("Thickness + Hook Depth - 0.003 m", "Thickness * 2 + Hook Depth - 0.003 m"))
        for (k, y) in ["Plate Height * 0.25", "-Plate Height * 0.15"].enumerated() {
            b.box("Hook \(k + 1)", x: ("-Plate Width / 2 + 0.006 m", "Plate Width / 2 - 0.006 m"), y: ("\(y) - 0.004 m", "\(y) + 0.004 m"), z: ("Thickness", "Thickness + Hook Depth"))
        }
        b.at(CBL.fine) { b in
            b.screwHeads("Screw", [("-Plate Width * 0.3", "Plate Height * 0.4"), ("Plate Width * 0.3", "-Plate Height * 0.4")], z: "Thickness", diameter: "Screw Diameter * 1.8")
        }
        b.boxSymbols(x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Height / 2", "Plate Height / 2"), z: (CX.zero, "Thickness * 2 + Hook Depth"))
        for (x, y) in [("-Plate Width * 0.3", "Plate Height * 0.4"), ("Plate Width * 0.3", "-Plate Height * 0.4")] {
            b.drill("Bed connector screw", x: x, y: y, diameter: "Screw Diameter * 0.6", depth: "Screw Length")
            b.drill("Bed connector screw", x: x, y: y, diameter: "Screw Diameter * 0.6", depth: "Screw Length", target: .counterpart)
        }
        let mm = ComponentKit.mm
        b.type("Bed Frame Connector - 100 mm", [:], cost: 2.40, model: "BFC-100", isDefault: true)
        b.type("Bed Frame Connector - 150 mm", ["Plate Height": mm(150), "Plate Width": mm(45), "Thickness": mm(4)], numbers: ["Load Rating": 600], cost: 3.60, model: "BFC-150")
        return b.build()
    }
}

extension ComponentFinish {
    /// COMPB: nickel-plated steel for shelf pins and supports.
    static let nickelPin = ComponentFinish("Nickel", .metal, RGBColor(hex: 0xBDBDB8))
}
