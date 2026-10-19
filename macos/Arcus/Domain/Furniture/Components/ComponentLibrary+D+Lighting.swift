import Foundation
import ArcusGeometry

// COMPD: 16 Lighting & Electrical. Geometry and data only: LED profiles (aluminium channel, strip and diffuser), lights,
// sensors, power and USB modules, drivers, switches and connectors, with their cutouts, grooves and cable holes in the
// host and their power data (W, V, supply, cable) for the power summary (ComponentLibrary+D+Power.swift).

extension ComponentLibrary {
    static var groupDLighting: [ComponentDefinition] {
        [ledStripProfile(), recessedLEDProfile(), surfaceLEDProfile(), cornerLEDProfile(), wardrobeSensorLight(), puckLight(),
         underCabinetLight(), drawerLight(), shelfLight(), motionSensor(), doorSensor(), touchSensor(), ledDiffuser(), ledEndCap(),
         routedCableChannel(), cabinetGrommet(), powerOutlet(), usbPort(), wirelessCharger(), powerDistribution(), ledDriver(),
         lightSwitch(), dimmer(), cableConnector()]
    }

    /// The LED strip and lens inside a channel: the strip on the floor of the channel, the diffuser near its top.
    fileprivate static func stripAndLens(_ b: inout ComponentBuilder, floor: String, top: String, inner: String) {
        b.using("LED Material")
        b.runBox("LED Strip", y: ("-(\(inner)) / 2 + 0.0005 m", "(\(inner)) / 2 - 0.0005 m"), z: (floor, "\(floor) + 0.0015 m"))
        b.using("Diffuser Material")
        b.runBox("Diffuser", y: ("-(\(inner)) / 2", "(\(inner)) / 2"), z: ("\(top) - 0.0015 m", top))
        b.using(nil)
    }

    fileprivate static func ledMaterials(_ b: inout ComponentBuilder, profile: ComponentFinish = .anodized) {
        b.material("Profile Material", profile)
        b.material("Diffuser Material", .diffuser)
        b.material("LED Material", .ledEmitter)
    }

    // MARK: LED profiles

    static func ledStripProfile() -> ComponentDefinition {
        var b = ComponentBuilder("LED Strip Profile", .lighting, "LED Profiles", "Aluminium U-channel with an LED strip and a clip-in diffuser, screwed or clipped to the surface.")
        b.tags("led", "profile", "strip", "channel", "aluminium", "light", "16 x 8 mm")
        b.aliases("led channel", "led extrusion", "aluminum led profile", "led tape channel", "strip light profile", "5/8\" x 5/16\" led channel")
        ledMaterials(&b)
        b.runLength(DK.mm(1000))
        b.length("Profile Width", DK.mm(16)); b.length("Profile Height", DK.mm(8)); b.length("Wall", DK.mm(1.2))
        b.choice("Diffuser", ["Opal", "Frosted", "Clear"], "Opal")
        b.electrical(watts: 2.9, volts: 12, perFoot: true, supply: "DC 12 V", cable: "2 x 22 AWG", connector: "2-pin 8 mm clip")
        b.hostRun([.shelf, .top, .bottom, .sidePanel, .divider, .back], faces: [.bottom, .inside, .frontEdge], offsetY: DK.inch(1))
        b.track("Channel", from: DK.lo, to: DK.hi, width: "Profile Width", height: "Profile Height", wall: "Wall")
        stripAndLens(&b, floor: "Wall", top: "Profile Height - 0.0005 m", inner: "Profile Width - 2 * Wall")
        b.runScrews("LED clip screw", diameter: 2.5, depth: 8)
        b.drill("LED cable hole", x: "-Length / 2 + 0.01 m", y: CX.zero, diameter: CX.mm(6), depth: "Host Thickness", through: true)
        b.runOutlines(y: ("-Profile Width / 2", "Profile Width / 2"), z: (DK.z, "Profile Height"))
        b.requires(.fitsWidth("Length"))
        b.type("LED Strip Profile - 16 x 8 mm, 12 V", cost: 9.50, model: "LSP-1608-12")
        b.type("LED Strip Profile - 16 x 8 mm, 24 V", numbers: ["Power": 4.4, "Voltage": 24], cost: 11.00, model: "LSP-1608-24")
        b.type("LED Strip Profile - 23 x 10 mm, 24 V", ["Profile Width": DK.mm(23), "Profile Height": DK.mm(10), "Wall": DK.mm(1.5)],
               numbers: ["Power": 5.5, "Voltage": 24], cost: 14.50, model: "LSP-2310-24")
        return b.build()
    }

    static func recessedLEDProfile() -> ComponentDefinition {
        var b = ComponentBuilder("Recessed LED Profile", .lighting, "LED Profiles", "Flanged aluminium profile set flush into a routed groove, with an LED strip and an opal diffuser.")
        b.tags("led", "profile", "recessed", "flush", "groove", "light", "17 x 7 mm")
        b.aliases("recessed led channel", "flush led profile", "inlay led profile", "routed led channel", "11/16\" led channel")
        ledMaterials(&b)
        b.runLength(DK.mm(1000))
        b.length("Flange Width", DK.mm(17)); b.length("Body Width", DK.mm(12.2)); b.length("Profile Height", DK.mm(7)); b.length("Wall", DK.mm(1))
        b.length("Groove Allowance", DK.mm(0.5), group: .manufacturing)
        b.electrical(watts: 2.9, volts: 12, perFoot: true, supply: "DC 12 V", cable: "2 x 22 AWG", connector: "2-pin 8 mm clip")
        b.hostRun([.shelf, .top, .bottom, .sidePanel, .divider], faces: [.bottom, .inside, .frontEdge], offsetY: DK.inch(1))
        // The body sits in the groove (below the face), the flange covers the groove's edges.
        b.using("Profile Material")
        b.run("Body", DK.pts([("-Body Width / 2", "-Profile Height"), ("Body Width / 2", "-Profile Height"), ("Body Width / 2", "-0.0012 m"),
                              ("Body Width / 2 - Wall", "-0.0012 m"), ("Body Width / 2 - Wall", "-Profile Height + Wall"),
                              ("-Body Width / 2 + Wall", "-Profile Height + Wall"), ("-Body Width / 2 + Wall", "-0.0012 m"), ("-Body Width / 2", "-0.0012 m")]))
        b.run("Flange", DK.pts([("-Flange Width / 2", "-0.0012 m"), ("-Body Width / 2 + Wall", "-0.0012 m"), ("-Body Width / 2 + Wall", "-0.0002 m"),
                                ("Body Width / 2 - Wall", "-0.0002 m"), ("Body Width / 2 - Wall", "-0.0012 m"), ("Flange Width / 2", "-0.0012 m"),
                                ("Flange Width / 2 - 0.0008 m", CX.zero), ("-Flange Width / 2 + 0.0008 m", CX.zero)]))
        stripAndLens(&b, floor: "-Profile Height + Wall", top: "-0.0002 m", inner: "Body Width - 2 * Wall")
        b.groove("LED groove", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Body Width + Groove Allowance", depth: "Profile Height")
        b.groove("Flange rebate", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Flange Width + Groove Allowance", depth: CX.mm(1.2))
        b.drill("LED cable hole", x: "-Length / 2 + 0.01 m", y: CX.zero, diameter: CX.mm(6), depth: "Host Thickness", through: true)
        b.runOutlines(y: ("-Flange Width / 2", "Flange Width / 2"), z: ("-Profile Height", DK.z))
        b.requires(.hostThickness(min: "Profile Height + 0.008 m", max: nil))
        b.type("Recessed LED Profile - 17 x 7 mm, 12 V", cost: 12.00, model: "RLP-1707-12")
        b.type("Recessed LED Profile - 17 x 7 mm, 24 V", numbers: ["Power": 4.4, "Voltage": 24], cost: 13.50, model: "RLP-1707-24")
        b.type("Recessed LED Profile - 24 x 7 mm, 24 V", ["Flange Width": DK.mm(24), "Body Width": DK.mm(18)], numbers: ["Power": 5.5, "Voltage": 24],
               cost: 16.00, model: "RLP-2407-24")
        return b.build()
    }

    static func surfaceLEDProfile() -> ComponentDefinition {
        var b = ComponentBuilder("Surface LED Profile", .lighting, "LED Profiles", "Surface-mounted aluminium profile with a domed opal diffuser for an even line of light.")
        b.tags("led", "profile", "surface", "dome", "light", "17 x 15 mm")
        b.aliases("surface mounted led profile", "dome led channel", "round lens led profile", "surface led channel")
        ledMaterials(&b)
        b.runLength(DK.mm(1000))
        b.length("Profile Width", DK.mm(17)); b.length("Base Height", DK.mm(8)); b.length("Dome Height", DK.mm(7)); b.length("Wall", DK.mm(1.2))
        b.electrical(watts: 2.9, volts: 12, perFoot: true, supply: "DC 12 V", cable: "2 x 22 AWG", connector: "2-pin 8 mm clip")
        b.hostRun([.shelf, .top, .bottom, .sidePanel, .back], faces: [.bottom, .inside], offsetY: DK.inch(1))
        b.track("Channel", from: DK.lo, to: DK.hi, width: "Profile Width", height: "Base Height", wall: "Wall")
        b.using("LED Material")
        b.runBox("LED Strip", y: ("-Profile Width / 2 + Wall + 0.0005 m", "Profile Width / 2 - Wall - 0.0005 m"), z: ("Wall", "Wall + 0.0015 m"))
        b.using("Diffuser Material")
        // The dome: a half ellipse over the channel's opening.
        let dome = (0...12).map { k -> FamilyPoint in
            let a = Double.pi * Double(k) / 12
            return DK.p("(Profile Width / 2 - Wall) * \(LX.num(cos(a)))", "Base Height + Dome Height * \(LX.num(sin(a)))")
        }
        b.run("Dome Diffuser", dome)
        b.using(nil)
        b.runScrews("LED clip screw", diameter: 2.5, depth: 8)
        b.drill("LED cable hole", x: "-Length / 2 + 0.01 m", y: CX.zero, diameter: CX.mm(6), depth: "Host Thickness", through: true)
        b.runOutlines(y: ("-Profile Width / 2", "Profile Width / 2"), z: (DK.z, "Base Height + Dome Height"))
        b.type("Surface LED Profile - 17 x 15 mm, 12 V", cost: 12.50, model: "SLP-1715-12")
        b.type("Surface LED Profile - 17 x 15 mm, 24 V", numbers: ["Power": 4.4, "Voltage": 24], cost: 14.00, model: "SLP-1715-24")
        b.type("Surface LED Profile - 30 x 20 mm, 24 V", ["Profile Width": DK.mm(30), "Base Height": DK.mm(10), "Dome Height": DK.mm(10), "Wall": DK.mm(1.5)],
               numbers: ["Power": 7.3, "Voltage": 24], cost: 19.00, model: "SLP-3020-24")
        return b.build()
    }

    static func cornerLEDProfile() -> ComponentDefinition {
        var b = ComponentBuilder("Corner LED Profile", .lighting, "LED Profiles", "45° aluminium profile for an inside corner (shelf to side, top to back), lighting across the corner.")
        b.tags("led", "profile", "corner", "45", "angle", "light", "16 x 16 mm")
        b.aliases("corner led channel", "angle led profile", "45 degree led profile", "v led profile")
        ledMaterials(&b)
        b.runLength(DK.mm(1000))
        b.length("Leg", DK.mm(16)); b.length("Wall", DK.mm(1.2))
        b.electrical(watts: 2.9, volts: 12, perFoot: true, supply: "DC 12 V", cable: "2 x 22 AWG", connector: "2-pin 8 mm clip")
        // On the face (Y = 0 is the inside corner's other face): legs along +Y and +Z, the diffuser on the hypotenuse.
        b.hostRun([.shelf, .top, .bottom, .sidePanel, .back], faces: [.bottom, .inside])
        b.using("Profile Material")
        b.run("Body", DK.pts([(DK.z, DK.z), ("Leg", DK.z), ("Leg", "Wall"), ("Wall", "Wall"), ("Wall", "Leg"), (DK.z, "Leg")]))
        b.using("LED Material")
        b.run("LED Strip", DK.pts([("Wall + 0.002 m", "Wall + 0.004 m"), ("Wall + 0.004 m", "Wall + 0.002 m"), ("Wall + 0.009 m", "Wall + 0.007 m"),
                                  ("Wall + 0.007 m", "Wall + 0.009 m")]))
        b.using("Diffuser Material")
        b.run("Diffuser", DK.pts([("Leg", "Wall"), ("Leg", "Wall + 0.0015 m"), ("Wall + 0.0015 m", "Leg"), ("Wall", "Leg")]))
        b.using(nil)
        b.runScrews("LED clip screw", diameter: 2.5, depth: 8, y: "Leg / 2")
        b.runOutlines(y: (DK.z, "Leg"), z: (DK.z, "Leg"))
        b.type("Corner LED Profile - 16 x 16 mm, 12 V", cost: 11.00, model: "CLP-1616-12")
        b.type("Corner LED Profile - 16 x 16 mm, 24 V", numbers: ["Power": 4.4, "Voltage": 24], cost: 12.50, model: "CLP-1616-24")
        b.type("Corner LED Profile - 20 x 20 mm, 24 V", ["Leg": DK.mm(20), "Wall": DK.mm(1.5)], numbers: ["Power": 4.4, "Voltage": 24], cost: 14.00, model: "CLP-2020-24")
        return b.build()
    }

    // MARK: Lights

    static func wardrobeSensorLight() -> ComponentDefinition {
        var b = ComponentBuilder("Wardrobe Sensor Light", .lighting, "Cabinet Lights", "Slim LED bar with a motion sensor, under a wardrobe top or shelf; lights when the doors open.")
        b.tags("wardrobe", "closet", "led", "light", "sensor", "motion", "bar")
        b.aliases("wardrobe led light", "closet light", "pir closet light", "motion wardrobe light", "wardrobe lighting")
        ledMaterials(&b)
        b.length("Length", DK.mm(450)); b.length("Body Width", DK.mm(24)); b.length("Body Height", DK.mm(10))
        b.electrical(watts: 3, volts: 12, supply: "DC 12 V", cable: "2 x 22 AWG, 2 m", connector: "DC 5.5 x 2.1 mm")
        b.host([.top, .shelf, .bottom], faces: [.bottom], align: .center, alignments: [.center, .left, .right], offsetY: DK.inch(2))
        b.using("Profile Material")
        b.profileAlongX("Body", profile: DK.topRounded(width: "Body Width", height: "Body Height", radius: "Body Height * 0.9"), from: "-Length / 2", to: "Length / 2")
        b.using("Diffuser Material")
        b.box("Lens", x: ("-Length / 2 + 0.01 m", "Length / 2 - 0.035 m"), y: ("-Body Width / 2 + 0.004 m", "Body Width / 2 - 0.004 m"), z: ("Body Height - 0.0015 m", "Body Height + 0.0005 m"))
        b.using("LED Material")
        b.rod("Sensor", axis: .z, center: ("Length / 2 - 0.018 m", CX.zero), radius: CX.mm(5), from: "Body Height - 0.002 m", to: "Body Height + 0.002 m")
        b.using(nil)
        b.screwPair("Light screw", spacing: "Length - 0.04 m", diameter: 2.5, depth: 10)
        b.outlines(x: ("-Length / 2", "Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.symbol(.face, [.fine], .circle(("Length / 2 - 0.018 m", DK.z), CX.mm(5)))
        b.type("Wardrobe Sensor Light - 300 mm", ["Length": DK.mm(300)], numbers: ["Power": 2], cost: 18.00, model: "WSL-300")
        b.type("Wardrobe Sensor Light - 450 mm", cost: 22.00, model: "WSL-450", isDefault: true)
        b.type("Wardrobe Sensor Light - 600 mm", ["Length": DK.mm(600)], numbers: ["Power": 4], cost: 26.00, model: "WSL-600")
        b.type("Wardrobe Sensor Light - 900 mm", ["Length": DK.mm(900)], numbers: ["Power": 6], cost: 34.00, model: "WSL-900")
        return b.build()
    }

    static func puckLight() -> ComponentDefinition {
        var b = ComponentBuilder("Cabinet Puck Light", .lighting, "Cabinet Lights", "Round LED puck light under a shelf or wall cabinet, surface-mounted or recessed in a bored hole.")
        b.tags("puck", "light", "led", "round", "downlight", "cabinet", "65 mm")
        b.aliases("puck light", "cabinet downlight", "round under cabinet light", "recessed puck", "2 1/2\" puck light", "mini downlight")
        b.material("Housing Material", .satinNickel)
        b.material("Lens Material", .diffuser)
        b.length("Diameter", DK.mm(65)); b.length("Thickness", DK.mm(9)); b.length("Cutout Diameter", DK.mm(58)); b.length("Recess Depth", DK.mm(8))
        b.flag("Recessed", false, instance: false, group: .manufacturing)
        b.electrical(watts: 2.5, volts: 12, supply: "DC 12 V", cable: "2 x 22 AWG, 2 m", connector: "Mini 2-pin plug")
        b.host([.shelf, .top, .bottom], faces: [.bottom], align: .center, alignments: [.center, .left, .right], offsetY: DK.inch(3))
        // Recessed: the can sits in the hole, the rim on the face; surface: the whole puck below the face.
        b.rod("Rim", axis: .z, center: (DK.z, DK.z), radius: "Diameter / 2", from: CX.zero, to: "if(Recessed, 0.0015 m, Thickness - 0.002 m)")
        b.visibility = "Recessed"
        b.rod("Can", axis: .z, center: (DK.z, DK.z), radius: "Cutout Diameter / 2 - 0.0005 m", from: "-Recess Depth", to: CX.zero)
        b.visibility = nil
        b.using("Lens Material")
        b.revolve("Lens", profile: DK.pts([(DK.z, DK.z), ("Diameter / 2 - 0.006 m", DK.z), ("Diameter / 2 - 0.007 m", CX.mm(2)), (DK.z, CX.mm(2.6))]),
                  base: "if(Recessed, 0.0015 m, Thickness - 0.002 m)")
        b.using(nil)
        b.drill("Puck cutout", x: CX.zero, y: CX.zero, diameter: "if(Recessed, Cutout Diameter, 0 m)", depth: "Recess Depth")
        b.drill("Puck cable hole", x: "Diameter / 2 + 0.01 m", y: CX.zero, diameter: CX.mm(8), depth: "Host Thickness", through: true)
        b.roundOutlines(radius: "Diameter / 2", z: (DK.z, "Thickness"))
        b.symbol(.face, [.fine], .line(("-Diameter / 4", DK.z), ("Diameter / 4", DK.z)), .line((DK.z, "-Diameter / 4"), (DK.z, "Diameter / 4")))
        b.requires(.hostThickness(min: "if(Recessed, Recess Depth + 0.006 m, 0 m)", max: nil))
        b.type("Puck Light - 65 mm Surface", cost: 12.00, model: "PL-65S")
        b.type("Puck Light - 65 mm Recessed, 58 mm Cutout", flags: ["Recessed": true], cost: 14.00, model: "PL-65R")
        b.type("Puck Light - 70 mm Recessed, 60 mm Cutout", ["Diameter": DK.mm(70), "Cutout Diameter": DK.mm(60), "Thickness": DK.mm(10)], flags: ["Recessed": true],
               numbers: ["Power": 3], cost: 16.00, model: "PL-70R")
        b.type("Puck Light - 60 mm Surface, Battery", ["Diameter": DK.mm(60), "Thickness": DK.mm(14)], numbers: ["Power": 1, "Voltage": 4.5], cost: 9.00, model: "PL-60B")
        return b.build()
    }

    static func underCabinetLight() -> ComponentDefinition {
        var b = ComponentBuilder("Under-Cabinet Light", .lighting, "Cabinet Lights", "Slim linear LED fixture under a wall cabinet, with an on/off switch and linkable ends.")
        b.tags("under cabinet", "light", "led", "linear", "task light", "kitchen")
        b.aliases("under cabinet lighting", "undercabinet light", "task light bar", "linkable led bar", "light bar")
        b.material("Housing Material", .anodized)
        b.material("Lens Material", .diffuser)
        b.length("Length", DK.inch(18)); b.length("Body Width", DK.mm(36)); b.length("Body Height", DK.mm(12))
        b.electrical(watts: 6, volts: 120, supply: "AC 120 V", cable: "18 AWG cord, 6 ft", connector: "Link plug")
        b.host([.bottom, .shelf, .top], faces: [.bottom], align: .center, alignments: [.center, .left, .right, .full], offsetY: DK.inch(1.5))
        b.profileAlongX("Housing", profile: DK.topRounded(width: "Body Width", height: "Body Height", radius: CX.mm(6)), from: "-Length / 2", to: "Length / 2")
        b.using("Lens Material")
        b.box("Lens", x: ("-Length / 2 + 0.012 m", "Length / 2 - 0.012 m"), y: ("-Body Width / 2 + 0.005 m", "Body Width / 2 - 0.005 m"), z: ("Body Height - 0.001 m", "Body Height + 0.0006 m"))
        b.using(nil)
        b.box("Switch", x: ("Length / 2 - 0.009 m", "Length / 2 - 0.003 m"), y: (CX.mm(-4), CX.mm(4)), z: (CX.mm(4), CX.mm(8)))
        b.screwPair("Fixture screw", spacing: "Length - 0.06 m", diameter: 3, depth: 10)
        b.outlines(x: ("-Length / 2", "Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.type("Under-Cabinet Light - 12\"", ["Length": DK.inch(12)], numbers: ["Power": 4], cost: 24.00, model: "UCL-12")
        b.type("Under-Cabinet Light - 18\"", cost: 29.00, model: "UCL-18", isDefault: true)
        b.type("Under-Cabinet Light - 24\"", ["Length": DK.inch(24)], numbers: ["Power": 8], cost: 34.00, model: "UCL-24")
        b.type("Under-Cabinet Light - 36\"", ["Length": DK.inch(36)], numbers: ["Power": 12], cost: 44.00, model: "UCL-36")
        return b.build()
    }

    static func drawerLight() -> ComponentDefinition {
        var b = ComponentBuilder("Drawer Light", .lighting, "Cabinet Lights", "LED strip under the drawer's top edge, behind the front, switched by the drawer opening.")
        b.tags("drawer", "light", "led", "strip", "switch", "interior")
        b.aliases("drawer lighting", "drawer led", "inside drawer light", "drawer strip light")
        ledMaterials(&b)
        b.length("Length", DK.mm(450)); b.length("Profile Width", DK.mm(12)); b.length("Profile Height", DK.mm(7))
        b.electrical(watts: 2.2, volts: 12, supply: "DC 12 V", cable: "2 x 22 AWG with slide contacts", connector: "Drawer contact")
        b.host([.drawerFront], faces: [.inside], align: .top, alignments: [.top], offsetY: DK.mm(15))
        b.using("Profile Material")
        b.box("Profile", x: ("-Length / 2", "Length / 2"), y: ("-Profile Width / 2", "Profile Width / 2"), z: (DK.z, "Profile Height"))
        b.using("Diffuser Material")
        b.box("Lens", x: ("-Length / 2 + 0.002 m", "Length / 2 - 0.002 m"), y: ("-Profile Width / 2 - 0.0012 m", "-Profile Width / 2"), z: (CX.mm(1), "Profile Height - 0.001 m"))
        b.using(nil)
        b.screwPair("Drawer light screw", spacing: "Length - 0.03 m", diameter: 2.5, depth: 8)
        b.outlines(x: ("-Length / 2", "Length / 2"), y: ("-Profile Width / 2", "Profile Width / 2"), z: (DK.z, "Profile Height"))
        b.type("Drawer Light - 300 mm", ["Length": DK.mm(300)], numbers: ["Power": 1.5], cost: 16.00, model: "DL-300")
        b.type("Drawer Light - 450 mm", cost: 19.00, model: "DL-450", isDefault: true)
        b.type("Drawer Light - 600 mm", ["Length": DK.mm(600)], numbers: ["Power": 3], cost: 22.00, model: "DL-600")
        b.type("Drawer Light - 800 mm", ["Length": DK.mm(800)], numbers: ["Power": 4], cost: 26.00, model: "DL-800")
        return b.build()
    }

    static func shelfLight() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Light", .lighting, "Cabinet Lights", "Slim LED profile in a groove under the shelf's front edge, lighting the shelf below.")
        b.tags("shelf", "light", "led", "groove", "display")
        b.aliases("shelf lighting", "shelf led", "display shelf light", "glass shelf light")
        ledMaterials(&b)
        b.runLength(DK.mm(800))
        b.length("Profile Width", DK.mm(10)); b.length("Profile Height", DK.mm(6))
        b.electrical(watts: 2.2, volts: 12, perFoot: true, supply: "DC 12 V", cable: "2 x 22 AWG", connector: "2-pin 8 mm clip")
        b.hostRun([.shelf], faces: [.bottom], offsetY: DK.mm(20))
        b.using("Profile Material")
        b.runBox("Profile", y: ("-Profile Width / 2", "Profile Width / 2"), z: ("-Profile Height", "-0.0015 m"))
        b.using("Diffuser Material")
        b.runBox("Lens", y: ("-Profile Width / 2 + 0.001 m", "Profile Width / 2 - 0.001 m"), z: ("-0.0015 m", CX.zero))
        b.using(nil)
        b.groove("Shelf light groove", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Profile Width + 0.0005 m", depth: "Profile Height")
        b.runOutlines(y: ("-Profile Width / 2", "Profile Width / 2"), z: ("-Profile Height", DK.z))
        b.requires(.hostThickness(min: "Profile Height + 0.008 m", max: nil))
        b.type("Shelf Light - 10 x 6 mm, 12 V", cost: 10.00, model: "SHL-1006-12")
        b.type("Shelf Light - 10 x 6 mm, 24 V", numbers: ["Power": 3.3, "Voltage": 24], cost: 11.50, model: "SHL-1006-24")
        return b.build()
    }

    // MARK: Sensors

    static func motionSensor() -> ComponentDefinition {
        var b = ComponentBuilder("Motion Sensor", .lighting, "Sensors & Switches", "PIR motion sensor for cabinet and wardrobe lights, surface-mounted or recessed in a 13 mm hole.")
        b.tags("sensor", "motion", "pir", "switch", "led", "automatic")
        b.aliases("pir sensor", "motion detector", "occupancy sensor", "cabinet motion switch")
        b.material("Body Material", .whitePlastic)
        b.material("Lens Material", .diffuser)
        b.length("Body Diameter", DK.mm(18)); b.length("Body Length", DK.mm(20)); b.length("Hole Diameter", DK.mm(13)); b.length("Lens Height", DK.mm(5))
        b.flag("Recessed", true, instance: false, group: .manufacturing)
        b.electrical(watts: 0.3, volts: 12, supply: "DC 12 V, 3 A max load", cable: "2 x 22 AWG in / out", connector: "DC 5.5 x 2.1 mm")
        b.host([.top, .bottom, .shelf, .sidePanel], faces: [.bottom, .inside, .frontEdge], align: .center, offsetY: DK.inch(1))
        b.rod("Bezel", axis: .z, center: (DK.z, DK.z), radius: "Body Diameter / 2", from: CX.zero, to: CX.mm(1.5))
        b.rod("Body", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 - 0.0003 m", from: "if(Recessed, -Body Length, 0.0015 m)", to: "if(Recessed, 0 m, Body Length)")
        b.using("Lens Material")
        let dome = [DK.p(DK.z, DK.z)] + (0...8).map { k -> FamilyPoint in
            let a = Double.pi / 2 * Double(k) / 8
            return DK.p("(Hole Diameter / 2 - 0.0015 m) * \(LX.num(cos(a)))", "Lens Height * \(LX.num(sin(a)))")
        }
        b.revolve("Dome", profile: dome, base: "if(Recessed, 0.0015 m, Body Length)")
        b.using(nil)
        b.drill("Sensor hole", x: CX.zero, y: CX.zero, diameter: "if(Recessed, Hole Diameter, 0 m)", depth: "Body Length")
        b.roundOutlines(radius: "Body Diameter / 2", z: (DK.z, "Lens Height"))
        b.type("Motion Sensor - 13 mm Recessed", cost: 14.00, model: "MS-13R")
        b.type("Motion Sensor - Surface", ["Body Diameter": DK.mm(24), "Hole Diameter": DK.mm(18), "Body Length": DK.mm(12)], flags: ["Recessed": false],
               cost: 13.00, model: "MS-24S")
        return b.build()
    }

    static func doorSensor() -> ComponentDefinition {
        var b = ComponentBuilder("Door Sensor", .lighting, "Sensors & Switches", "Infrared or reed door switch in the carcass edge: lights come on when the door or drawer opens.")
        b.tags("sensor", "door", "switch", "ir", "reed", "door-activated", "led")
        b.aliases("door switch", "door-activated sensor", "cabinet door switch", "ir door sensor", "reed switch", "magnetic door switch")
        b.material("Body Material", .whitePlastic)
        b.material("Magnet Material", .greyPlastic)
        b.length("Head Diameter", DK.mm(14)); b.length("Hole Diameter", DK.mm(10)); b.length("Body Length", DK.mm(25))
        b.flag("Reed Pair", false, instance: false, group: .manufacturing)
        b.electrical(watts: 0.2, volts: 12, supply: "DC 12 V, 3 A max load", cable: "2 x 22 AWG", connector: "DC 5.5 x 2.1 mm")
        b.host([.sidePanel, .top, .bottom, .divider], faces: [.frontEdge], align: .top, alignments: [.top, .bottom, .center], offsetY: DK.inch(2))
        b.rod("Head", axis: .z, center: (DK.z, DK.z), radius: "Head Diameter / 2", from: CX.zero, to: CX.mm(1.5))
        b.rod("Body", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 - 0.0003 m", from: "-Body Length", to: CX.zero)
        b.using("Magnet Material")
        b.visibility = "Reed Pair"
        b.box("Magnet", x: (CX.mm(-6), CX.mm(6)), y: (CX.mm(-4), CX.mm(4)), z: (CX.mm(3), CX.mm(7)))
        b.visibility = nil
        b.using(nil)
        b.drill("Door sensor hole", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Body Length + 0.002 m")
        b.drill("Door sensor cable", x: CX.zero, y: CX.zero, diameter: CX.mm(6), depth: "Body Length + 0.02 m")
        b.roundOutlines(radius: "Head Diameter / 2", z: ("-Body Length", CX.mm(1.5)))
        b.type("Door Sensor - IR, 10 mm Bore", cost: 9.50, model: "DS-IR10")
        b.type("Door Sensor - Reed Pair, 10 mm Bore", flags: ["Reed Pair": true], cost: 8.00, model: "DS-RD10")
        return b.build()
    }

    static func touchSensor() -> ComponentDefinition {
        var b = ComponentBuilder("Touch Sensor", .lighting, "Sensors & Switches", "Capacitive touch switch or dimmer for LED lights, recessed in a 13 mm hole or behind a thin panel.")
        b.tags("sensor", "touch", "switch", "dimmer", "led", "capacitive")
        b.aliases("touch switch", "touch dimmer", "capacitive switch", "hidden touch sensor")
        b.material("Body Material", .blackPlastic)
        b.material("Ring Material", .ledEmitter)
        b.length("Head Diameter", DK.mm(17)); b.length("Hole Diameter", DK.mm(13)); b.length("Body Length", DK.mm(18))
        b.electrical(watts: 0.3, volts: 12, supply: "DC 12 V, 3 A max load", cable: "2 x 22 AWG in / out", connector: "DC 5.5 x 2.1 mm")
        b.host([.sidePanel, .top, .bottom, .shelf, .divider], faces: [.inside, .bottom, .frontEdge], align: .center)
        b.rod("Head", axis: .z, center: (DK.z, DK.z), radius: "Head Diameter / 2", from: CX.zero, to: CX.mm(1.8))
        b.rod("Body", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 - 0.0003 m", from: "-Body Length", to: CX.zero)
        b.using("Ring Material")
        b.pipe("Ring", axis: .z, center: (DK.z, DK.z), outer: "Head Diameter / 2 - 0.001 m", inner: "Head Diameter / 2 - 0.002 m", from: CX.mm(1.8), to: CX.mm(2.1))
        b.using(nil)
        b.drill("Touch sensor hole", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Body Length")
        b.roundOutlines(radius: "Head Diameter / 2", z: ("-Body Length", CX.mm(2)))
        b.type("Touch Sensor - 13 mm Recessed", cost: 12.00, model: "TS-13")
        b.type("Touch Dimmer - 13 mm Recessed", cost: 15.00, model: "TD-13")
        b.type("Touch Sensor - 17 mm Recessed", ["Head Diameter": DK.mm(22), "Hole Diameter": DK.mm(17)], cost: 13.00, model: "TS-17")
        return b.build()
    }

    // MARK: Profile accessories

    static func ledDiffuser() -> ComponentDefinition {
        var b = ComponentBuilder("LED Diffuser", .lighting, "LED Profiles", "Clip-in diffuser cover for LED profiles, cut to length.")
        b.tags("led", "diffuser", "lens", "cover", "opal", "profile")
        b.aliases("led lens", "profile cover", "led cover strip", "opal diffuser")
        b.material("Diffuser Material", .diffuser)
        b.runLength(DK.mm(1000))
        b.length("Width", DK.mm(14)); b.length("Thickness", DK.mm(1.2)); b.length("Dome Height", 0)
        b.hostRun([.shelf, .top, .bottom, .sidePanel, .anyPart], faces: [.bottom, .inside, .frontEdge])
        b.runBox("Cover", y: ("-Width / 2", "Width / 2"), z: (DK.z, "Thickness"))
        let dome = (0...10).map { k -> FamilyPoint in
            let a = Double.pi * Double(k) / 10
            return DK.p("(Width / 2) * \(LX.num(cos(a)))", "Thickness + max(Dome Height, 0.0002 m) * \(LX.num(sin(a)))")
        }
        b.run("Dome", dome)
        b.runOutlines(y: ("-Width / 2", "Width / 2"), z: (DK.z, "Thickness + Dome Height"))
        b.type("LED Diffuser - Opal Flat, 16 mm Profile", cost: 3.00, model: "LDF-16O")
        b.type("LED Diffuser - Opal Dome, 16 mm Profile", ["Dome Height": DK.mm(4)], cost: 3.50, model: "LDD-16O")
        b.type("LED Diffuser - Clear Flat, 16 mm Profile", cost: 3.00, model: "LDF-16C")
        b.type("LED Diffuser - Opal Flat, 23 mm Profile", ["Width": DK.mm(21)], cost: 4.00, model: "LDF-23O")
        return b.build()
    }

    static func ledEndCap() -> ComponentDefinition {
        var b = ComponentBuilder("LED End Cap", .lighting, "LED Profiles", "Plastic end cap for an LED profile, closed or with a cable hole.")
        b.tags("led", "end cap", "cap", "profile", "plug")
        b.aliases("profile end cap", "led channel end cap", "end plug")
        b.material("Cap Material", .greyPlastic)
        b.length("Profile Width", DK.mm(16)); b.length("Profile Height", DK.mm(8)); b.length("Cap Thickness", DK.mm(2.5))
        b.flag("Cable Hole", false, instance: false, group: .manufacturing)
        b.host([.anyPart], faces: [.bottom, .inside, .frontEdge], align: .left, alignments: [.left, .right])
        b.box("Cap", x: ("-Cap Thickness", DK.z), y: ("-Profile Width / 2", "Profile Width / 2"), z: (DK.z, "Profile Height"))
        b.box("Plug", x: (DK.z, CX.mm(4)), y: ("-Profile Width / 2 + 0.0015 m", "Profile Width / 2 - 0.0015 m"), z: (CX.mm(1.5), "Profile Height - 0.0015 m"))
        b.visibility = "Cable Hole"
        b.rod("Cable Hole", axis: .x, center: (DK.z, "Profile Height / 2"), radius: CX.mm(2.2), from: "-Cap Thickness - 0.001 m", to: CX.mm(5), void: true)
        b.visibility = nil
        b.outlines(x: ("-Cap Thickness", DK.z), y: ("-Profile Width / 2", "Profile Width / 2"), z: (DK.z, "Profile Height"))
        b.type("LED End Cap - 16 x 8 mm, Closed", cost: 0.40, model: "LEC-1608")
        b.type("LED End Cap - 16 x 8 mm, Cable Hole", flags: ["Cable Hole": true], cost: 0.45, model: "LEC-1608H")
        b.type("LED End Cap - 17 x 7 mm Recessed", ["Profile Width": DK.mm(17), "Profile Height": DK.mm(7)], cost: 0.45, model: "LEC-1707")
        b.type("LED End Cap - 23 x 10 mm", ["Profile Width": DK.mm(23), "Profile Height": DK.mm(10)], cost: 0.50, model: "LEC-2310")
        return b.build()
    }

    // MARK: Cables and power

    static func routedCableChannel() -> ComponentDefinition {
        var b = ComponentBuilder("Routed Cable Channel", .lighting, "Cables & Power", "Channel routed in a back or side panel for LED and power cables, closed by a clip-in cover strip.")
        b.tags("cable", "channel", "routed", "wire", "groove", "cover")
        b.aliases("cable channel", "wire channel", "cable groove", "cable raceway", "wire chase")
        b.material("Cover Material", .greyPlastic)
        b.runLength(DK.mm(600))
        b.length("Channel Width", DK.mm(10)); b.length("Channel Depth", DK.mm(6)); b.length("Cover Thickness", DK.mm(1.5))
        b.hostRun([.back, .sidePanel, .divider, .bottom, .top], faces: [.inside, .back, .bottom])
        b.runBox("Cover", y: ("-Channel Width / 2 - 0.0015 m", "Channel Width / 2 + 0.0015 m"), z: ("-Cover Thickness", "0.0003 m"))
        b.runBox("Cover Legs", y: ("-Channel Width / 2", "Channel Width / 2"), z: ("-Cover Thickness - 0.002 m", "-Cover Thickness"))
        b.groove("Cable channel", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Channel Width", depth: "Channel Depth")
        b.groove("Cover rebate", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Channel Width + 0.003 m", depth: "Cover Thickness")
        b.runOutlines(y: ("-Channel Width / 2 - 0.0015 m", "Channel Width / 2 + 0.0015 m"), z: ("-Channel Depth", DK.z))
        b.requires(.hostThickness(min: "Channel Depth + 0.006 m", max: nil))
        b.type("Routed Cable Channel - 10 x 6 mm", cost: 1.20, model: "RCC-1006")
        b.type("Routed Cable Channel - 16 x 8 mm", ["Channel Width": DK.mm(16), "Channel Depth": DK.mm(8)], cost: 1.60, model: "RCC-1608")
        return b.build()
    }

    static func cabinetGrommet() -> ComponentDefinition {
        var b = ComponentBuilder("Cabinet Cable Grommet", .lighting, "Cables & Power", "Round cable grommet with a cap, in a bored hole through a back, shelf or top.")
        b.tags("grommet", "cable", "hole", "round", "wire", "cap")
        b.aliases("cable grommet", "wire grommet", "cable bushing", "cord hole cover", "1 3/8\" grommet", "2 3/8\" grommet")
        b.material("Grommet Material", .blackPlastic)
        b.length("Hole Diameter", DK.mm(35)); b.length("Flange Diameter", DK.mm(42)); b.length("Sleeve Length", DK.mm(16))
        b.host([.back, .shelf, .top, .bottom, .sidePanel, .divider], faces: [.inside, .top, .back], align: .center, alignments: [.center, .topLeft, .topRight])
        b.pipe("Sleeve", axis: .z, center: (DK.z, DK.z), outer: "Hole Diameter / 2", inner: "Hole Diameter / 2 - 0.0015 m", from: "-Sleeve Length", to: CX.zero)
        b.pipe("Flange", axis: .z, center: (DK.z, DK.z), outer: "Flange Diameter / 2", inner: "Hole Diameter / 2 - 0.0015 m", from: CX.zero, to: CX.mm(2))
        b.box("Cap", x: ("-Hole Diameter / 2 + 0.002 m", "Hole Diameter / 2 - 0.002 m"), y: ("-Hole Diameter * 0.15", "Hole Diameter / 2 - 0.003 m"), z: (CX.mm(1), CX.mm(2.5)))
        b.drill("Grommet hole", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        b.roundOutlines(radius: "Flange Diameter / 2", z: ("-Sleeve Length", CX.mm(2.5)))
        b.symbol(.face, [.medium, .fine], .circle((DK.z, DK.z), "Hole Diameter / 2"))
        b.type("Cable Grommet - 25 mm", ["Hole Diameter": DK.mm(25), "Flange Diameter": DK.mm(31)], cost: 1.20, model: "CG-25")
        b.type("Cable Grommet - 35 mm", cost: 1.50, model: "CG-35", isDefault: true)
        b.type("Cable Grommet - 60 mm", ["Hole Diameter": DK.mm(60), "Flange Diameter": DK.mm(70), "Sleeve Length": DK.mm(20)], cost: 2.50, model: "CG-60")
        return b.build()
    }

    static func powerOutlet() -> ComponentDefinition {
        var b = ComponentBuilder("Furniture Power Outlet", .lighting, "Cables & Power", "Recessed furniture power module: outlets with USB charging in a round or rectangular cutout.")
        b.tags("power", "outlet", "socket", "receptacle", "120 v", "usb", "desk", "furniture")
        b.aliases("power outlets", "furniture outlet", "recessed outlet", "desk power module", "power grommet", "3 1/8\" power grommet")
        b.material("Housing Material", .blackPlastic)
        b.material("Trim Material", .satinNickel)
        b.length("Cutout Diameter", DK.mm(80)); b.length("Cutout Width", 0); b.length("Cutout Height", 0)
        b.length("Trim Diameter", DK.mm(88)); b.length("Body Depth", DK.mm(60))
        b.flag("Rectangular", false, instance: false, group: .manufacturing)
        b.length("Faceplate Width", 0, formula: "min(Cutout Diameter, 0.07 m) * 0.8 + if(Rectangular, Cutout Width * 0.85 - 0.045 m, 0 m)")
        b.number("Outlets", 2); b.number("USB Ports", 2)
        b.number("Rating", 15, unit: "A", group: .data)
        b.electrical(watts: 0, volts: 120, supply: "AC 120 V, 15 A", cable: "14/3 cord, 6 ft with plug", connector: "NEMA 5-15")
        b.host([.top, .shelf, .back, .sidePanel, .divider], faces: [.top, .inside, .back], align: .center, alignments: [.center, .topLeft, .topRight])
        b.material("Faceplate Material", .whitePlastic)
        b.visibility = "Round"
        b.flag("Round", true, formula: "not(Rectangular)")
        b.using("Trim Material")
        b.rod("Round Trim", axis: .z, center: (DK.z, DK.z), radius: "Trim Diameter / 2", from: CX.zero, to: CX.mm(3))
        b.using("Housing Material")
        b.rod("Round Body", axis: .z, center: (DK.z, DK.z), radius: "Cutout Diameter / 2 - 0.0005 m", from: "-Body Depth", to: CX.zero)
        b.using(nil)
        b.visibility = "Rectangular"
        b.using("Trim Material")
        b.roundedBar("Rect Trim", width: "Cutout Width + 0.008 m", height: "Cutout Height + 0.008 m", radius: CX.mm(4), from: CX.zero, to: CX.mm(3))
        b.using("Housing Material")
        b.box("Rect Body", x: ("-Cutout Width / 2 + 0.0005 m", "Cutout Width / 2 - 0.0005 m"), y: ("-Cutout Height / 2 + 0.0005 m", "Cutout Height / 2 - 0.0005 m"), z: ("-Body Depth", CX.zero))
        b.visibility = nil
        b.using("Faceplate Material")
        b.roundedBar("Faceplate", width: "Faceplate Width", height: "min(Cutout Diameter, 0.07 m) * 0.55",
                     radius: CX.mm(3), from: CX.mm(3), to: CX.mm(4))
        b.using("Housing Material")
        for (k, x) in ["-0.25", "0.25"].enumerated() {
            b.box("Receptacle \(k + 1) Slot L", x: ("Faceplate Width * \(x) - 0.004 m", "Faceplate Width * \(x) - 0.0025 m"), y: (CX.mm(-3), CX.mm(4)), z: (CX.mm(4), CX.mm(4.3)))
            b.box("Receptacle \(k + 1) Slot R", x: ("Faceplate Width * \(x) + 0.0025 m", "Faceplate Width * \(x) + 0.004 m"), y: (CX.mm(-3), CX.mm(4)), z: (CX.mm(4), CX.mm(4.3)))
        }
        b.using(nil)
        b.drill("Outlet cutout", x: CX.zero, y: CX.zero, diameter: "if(Rectangular, 0 m, Cutout Diameter)", depth: "Host Thickness", through: true)
        b.pocket("Outlet cutout", width: "if(Rectangular, Cutout Width, 0 m)", height: "if(Rectangular, Cutout Height, 0 m)", depth: "Host Thickness", through: true)
        b.roundOutlines(radius: "Trim Diameter / 2", z: ("-Body Depth", CX.mm(3.6)))
        b.clearance(.box(name: "Plug space", x0: "-0.05 m", x1: "0.05 m", y0: "-0.05 m", y1: "0.05 m", z0: "-Body Depth - 0.05 m", z1: "-Body Depth"))
        b.type("Power Outlet - Round 80 mm, 2 Outlets + 2 USB", cost: 39.00, model: "PO-80R")
        b.type("Power Outlet - Round 60 mm, 1 Outlet + 1 USB", ["Cutout Diameter": DK.mm(60), "Trim Diameter": DK.mm(68)],
               numbers: ["Outlets": 1, "USB Ports": 1], cost: 29.00, model: "PO-60R")
        b.type("Power Outlet - Rectangular 6 x 2 1/2\", 3 Outlets", ["Cutout Width": DK.inch(6), "Cutout Height": DK.inch(2.5), "Trim Diameter": DK.inch(3)],
               flags: ["Rectangular": true], numbers: ["Outlets": 3, "USB Ports": 0], cost: 49.00, model: "PO-6X25")
        return b.build()
    }

    static func usbPort() -> ComponentDefinition {
        var b = ComponentBuilder("USB Charging Port", .lighting, "Cables & Power", "Recessed USB-A and USB-C charging module in a round bored hole.")
        b.tags("usb", "charging", "port", "charger", "usb-c", "power")
        b.aliases("usb charger", "usb outlet", "usb socket", "furniture usb", "usb-c pd port")
        b.material("Housing Material", .blackPlastic)
        b.length("Hole Diameter", DK.mm(30)); b.length("Bezel Diameter", DK.mm(36)); b.length("Body Depth", DK.mm(45))
        b.number("USB-A Ports", 1); b.number("USB-C Ports", 1)
        b.electrical(watts: 18, volts: 5, supply: "AC 120 V in, USB 5 V out", cable: "18 AWG cord, 6 ft", connector: "USB-A / USB-C")
        b.host([.top, .shelf, .sidePanel, .back, .divider, .rail], faces: [.top, .inside, .back, .frontEdge], align: .center)
        b.rod("Bezel", axis: .z, center: (DK.z, DK.z), radius: "Bezel Diameter / 2", from: CX.zero, to: CX.mm(2.5))
        b.rod("Body", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 - 0.0004 m", from: "-Body Depth", to: CX.zero)
        b.box("USB-A Port", x: (CX.mm(-6), CX.mm(6)), y: (CX.mm(2), CX.mm(6.5)), z: (CX.mm(-6), CX.mm(2.6)), void: true)
        b.roundedBar("USB-C Port", center: (DK.z, CX.mm(-4.5)), width: CX.mm(9), height: CX.mm(3.4), radius: CX.mm(1.6), from: CX.mm(2.5), to: CX.mm(2.7))
        b.drill("USB port hole", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        b.roundOutlines(radius: "Bezel Diameter / 2", z: ("-Body Depth", CX.mm(2.5)))
        b.type("USB Charging Port - A + C, 30 mm", cost: 19.00, model: "USB-AC30")
        b.type("USB Charging Port - C PD 20 W, 25 mm", ["Hole Diameter": DK.mm(25), "Bezel Diameter": DK.mm(31)], numbers: ["Power": 20, "USB-A Ports": 0, "USB-C Ports": 1],
               cost: 22.00, model: "USB-C25")
        b.type("USB Charging Port - 2 x A, 35 mm", ["Hole Diameter": DK.mm(35), "Bezel Diameter": DK.mm(41)], numbers: ["Power": 12, "USB-A Ports": 2, "USB-C Ports": 0],
               cost: 17.00, model: "USB-AA35")
        return b.build()
    }

    static func wirelessCharger() -> ComponentDefinition {
        var b = ComponentBuilder("Wireless Charger", .lighting, "Cables & Power", "Qi wireless charging pad: flush in a bored top, or hidden in a pocket under it.")
        b.tags("wireless", "charger", "qi", "charging", "pad", "phone")
        b.aliases("wireless charging module", "qi charger", "inductive charger", "hidden wireless charger", "under desk charger")
        b.material("Housing Material", .blackPlastic)
        b.material("Pad Material", .greyPlastic)
        b.length("Pad Diameter", DK.mm(80)); b.length("Body Depth", DK.mm(16)); b.length("Skin", DK.mm(6))
        b.flag("Under Top", false, instance: false, group: .manufacturing)
        b.electrical(watts: 15, volts: 12, supply: "DC 12 V adapter", cable: "USB-C cable, 1.5 m", connector: "USB-C")
        b.host([.top, .shelf], faces: [.top, .bottom], align: .center)
        // Flush: the pad's face level with the top. Under Top: the pad in a pocket from below, leaving Skin.
        b.rod("Pad", axis: .z, center: (DK.z, DK.z), radius: "Pad Diameter / 2", from: "-Body Depth", to: "if(Under Top, -Body Depth + 0.002 m, 0 m)")
        b.using("Pad Material")
        b.rod("Charging Face", axis: .z, center: (DK.z, DK.z), radius: "Pad Diameter / 2 - 0.004 m", from: "if(Under Top, -Body Depth + 0.0021 m, 0 m)", to: "if(Under Top, -Body Depth + 0.0025 m, 0.0004 m)")
        b.using(nil)
        b.box("Cable Tail", x: ("Pad Diameter / 2 - 0.004 m", "Pad Diameter / 2 + 0.03 m"), y: (CX.mm(-3), CX.mm(3)), z: ("-Body Depth", "-Body Depth + 0.006 m"))
        b.drill("Charger cutout", x: CX.zero, y: CX.zero, diameter: "Pad Diameter", depth: "if(Under Top, 0 m, Body Depth)")
        b.drill("Charger pocket", x: CX.zero, y: CX.zero, diameter: "if(Under Top, Pad Diameter, 0 m)", depth: "Host Thickness - Skin")
        b.roundOutlines(radius: "Pad Diameter / 2", z: ("-Body Depth", DK.z))
        b.requires(.note("Under Top: the top over the pad must be 1/4\" (6 mm) or thinner and not metal."))
        b.type("Wireless Charger - Flush, 80 mm", cost: 32.00, model: "WC-80F")
        b.type("Wireless Charger - Flush, 60 mm", ["Pad Diameter": DK.mm(60)], numbers: ["Power": 10], cost: 28.00, model: "WC-60F")
        b.type("Wireless Charger - Hidden Under Top", ["Pad Diameter": DK.mm(70), "Body Depth": DK.mm(10)], flags: ["Under Top": true], cost: 36.00, model: "WC-70H")
        return b.build()
    }

    static func powerDistribution() -> ComponentDefinition {
        var b = ComponentBuilder("Power Distribution Module", .lighting, "Cables & Power", "Low-voltage distribution box: one driver feeds several LED lights through plug-in outlets.")
        b.tags("power", "distribution", "splitter", "junction", "led", "12 v", "24 v")
        b.aliases("led distributor", "power splitter box", "junction box", "led hub", "distribution block")
        b.material("Housing Material", .whitePlastic)
        b.length("Body Length", DK.mm(80)); b.length("Body Width", DK.mm(40)); b.length("Body Height", DK.mm(15))
        b.number("Outputs", 6)
        b.number("Max Load", 72, unit: "W", group: .data)
        b.electrical(watts: 0, volts: 12, supply: "DC 12 V in", cable: "2 x 18 AWG in", connector: "Mini 2-pin outputs")
        b.host([.back, .sidePanel, .top, .bottom, .divider], faces: [.inside, .bottom, .back], align: .center)
        b.roundedBar("Housing", width: "Body Length", height: "Body Width", radius: CX.mm(4), from: CX.zero, to: "Body Height")
        for k in 0..<3 {
            let x = "-Body Length / 2 + Body Length * \(LX.num(0.25 + 0.25 * Double(k)))"
            b.box("Output \(k + 1)", x: ("\(x) - 0.004 m", "\(x) + 0.004 m"), y: ("Body Width / 2 - 0.001 m", "Body Width / 2 + 0.002 m"), z: (CX.mm(4), CX.mm(9)))
        }
        b.screwPair("Module screw", spacing: "Body Length + 0.012 m", diameter: 3, depth: 10)
        b.box("Tab", x: ("-Body Length / 2 - 0.01 m", "Body Length / 2 + 0.01 m"), y: (CX.mm(-5), CX.mm(5)), z: (DK.z, CX.mm(2)))
        b.outlines(x: ("-Body Length / 2 - 0.01 m", "Body Length / 2 + 0.01 m"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.type("Power Distribution Module - 6-Way, 12 V", cost: 14.00, model: "PDM-6-12")
        b.type("Power Distribution Module - 9-Way, 24 V", ["Body Length": DK.mm(110)], numbers: ["Outputs": 9, "Max Load": 144, "Voltage": 24], cost: 19.00, model: "PDM-9-24")
        return b.build()
    }

    static func ledDriver() -> ComponentDefinition {
        var b = ComponentBuilder("LED Driver", .lighting, "Cables & Power", "Constant-voltage LED driver (power supply) mounted inside the cabinet; size it 20% above the load.")
        b.tags("driver", "power supply", "transformer", "led", "12 v", "24 v", "constant voltage")
        b.aliases("led power supply", "led transformer", "psu", "led adapter", "dc power supply")
        b.material("Housing Material", .whitePlastic)
        b.length("Body Length", DK.mm(150)); b.length("Body Width", DK.mm(42)); b.length("Body Height", DK.mm(22))
        b.number("Output Power", 30, unit: "W", group: .data)
        b.electrical(watts: 0, volts: 12, supply: "AC 120 V in, DC 12 V out", cable: "18 AWG cord with plug in, 2 x 18 AWG out", connector: "Mini 2-pin outputs")
        b.host([.back, .sidePanel, .top, .bottom, .divider], faces: [.inside, .bottom, .back], align: .center)
        b.box("Housing", x: ("-Body Length / 2", "Body Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.box("Tabs", x: ("-Body Length / 2 - 0.009 m", "Body Length / 2 + 0.009 m"), y: (CX.mm(-6), CX.mm(6)), z: (DK.z, CX.mm(2)))
        b.rod("Cord In", axis: .x, center: (DK.z, "Body Height / 2"), radius: CX.mm(3), from: "-Body Length / 2 - 0.03 m", to: "-Body Length / 2")
        b.rod("Cable Out", axis: .x, center: (DK.z, "Body Height / 2"), radius: CX.mm(2), from: "Body Length / 2", to: "Body Length / 2 + 0.03 m")
        b.screwPair("Driver screw", spacing: "Body Length + 0.012 m", diameter: 3.5, depth: 12)
        b.outlines(x: ("-Body Length / 2 - 0.009 m", "Body Length / 2 + 0.009 m"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.symbol(.face, [.fine], .line(("-Body Length / 2", "-Body Width / 2"), ("Body Length / 2", "Body Width / 2")))
        b.clearance(.box(name: "Ventilation", x0: "-Body Length / 2", x1: "Body Length / 2", y0: "-Body Width / 2", y1: "Body Width / 2", z0: "Body Height", z1: "Body Height + 0.025 m"))
        b.type("LED Driver - 30 W, 12 V", cost: 18.00, model: "LDR-30-12")
        b.type("LED Driver - 60 W, 12 V", ["Body Length": DK.mm(170), "Body Width": DK.mm(48), "Body Height": DK.mm(30)], numbers: ["Output Power": 60], cost: 26.00, model: "LDR-60-12")
        b.type("LED Driver - 60 W, 24 V", ["Body Length": DK.mm(170), "Body Width": DK.mm(48), "Body Height": DK.mm(30)], numbers: ["Output Power": 60, "Voltage": 24],
               cost: 27.00, model: "LDR-60-24")
        b.type("LED Driver - 100 W, 24 V", ["Body Length": DK.mm(200), "Body Width": DK.mm(60), "Body Height": DK.mm(36)], numbers: ["Output Power": 100, "Voltage": 24],
               cost: 38.00, model: "LDR-100-24")
        return b.build()
    }

    static func lightSwitch() -> ComponentDefinition {
        var b = ComponentBuilder("Cabinet Switch", .lighting, "Sensors & Switches", "Low-voltage switch for cabinet lights: a rocker in a rectangular cutout or a push button in a 16 mm hole.")
        b.tags("switch", "rocker", "push button", "led", "on off")
        b.aliases("switches", "rocker switch", "push switch", "light switch", "cabinet light switch")
        b.material("Body Material", .blackPlastic)
        b.length("Cutout Width", DK.mm(21)); b.length("Cutout Height", DK.mm(15)); b.length("Hole Diameter", 0); b.length("Body Depth", DK.mm(20))
        b.flag("Push Button", false, instance: false, group: .manufacturing)
        b.electrical(watts: 0, volts: 12, supply: "DC 12 V, 5 A max load", cable: "2 x 22 AWG", connector: "Spade 4.8 mm")
        b.host([.sidePanel, .divider, .rail, .shelf, .top], faces: [.inside, .frontEdge, .bottom], align: .center)
        b.flag("Rocker", true, formula: "not(Push Button)")
        b.visibility = "Rocker"
        b.box("Rocker Bezel", x: ("-Cutout Width / 2 - 0.0015 m", "Cutout Width / 2 + 0.0015 m"), y: ("-Cutout Height / 2 - 0.0015 m", "Cutout Height / 2 + 0.0015 m"), z: (DK.z, CX.mm(2)))
        b.box("Rocker Body", x: ("-Cutout Width / 2", "Cutout Width / 2"), y: ("-Cutout Height / 2", "Cutout Height / 2"), z: ("-Body Depth", DK.z))
        b.box("Rocker Paddle", x: ("-Cutout Width / 2 + 0.002 m", "Cutout Width / 2 - 0.002 m"), y: ("-Cutout Height / 2 + 0.002 m", "Cutout Height / 2 - 0.002 m"), z: (CX.mm(2), CX.mm(4)))
        b.visibility = "Push Button"
        b.rod("Button Bezel", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 + 0.002 m", from: CX.zero, to: CX.mm(1.5))
        b.rod("Button Body", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2", from: "-Body Depth", to: CX.zero)
        b.rod("Button", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 - 0.002 m", from: CX.mm(1.5), to: CX.mm(3))
        b.visibility = nil
        b.pocket("Switch cutout", width: "if(Push Button, 0 m, Cutout Width)", height: "if(Push Button, 0 m, Cutout Height)", depth: "Body Depth")
        b.drill("Switch hole", x: CX.zero, y: CX.zero, diameter: "if(Push Button, Hole Diameter, 0 m)", depth: "Body Depth")
        b.outlines(x: ("-Cutout Width / 2", "Cutout Width / 2"), y: ("-Cutout Height / 2", "Cutout Height / 2"), z: ("-Body Depth", CX.mm(4)))
        b.type("Rocker Switch - 21 x 15 mm", cost: 3.50, model: "SW-RK2115")
        b.type("Push Switch - 16 mm", ["Hole Diameter": DK.mm(16), "Cutout Width": DK.mm(16), "Cutout Height": DK.mm(16)], flags: ["Push Button": true], cost: 4.50, model: "SW-PB16")
        b.type("Push Switch - 12 mm", ["Hole Diameter": DK.mm(12), "Cutout Width": DK.mm(12), "Cutout Height": DK.mm(12)], flags: ["Push Button": true], cost: 4.00, model: "SW-PB12")
        return b.build()
    }

    static func dimmer() -> ComponentDefinition {
        var b = ComponentBuilder("LED Dimmer", .lighting, "Sensors & Switches", "Low-voltage LED dimmer: a rotary knob in a bored hole or an inline dimmer on the cable.")
        b.tags("dimmer", "rotary", "inline", "led", "brightness", "pwm")
        b.aliases("dimmers", "led dimmer", "rotary dimmer", "inline dimmer", "dimmer switch")
        b.material("Body Material", .blackPlastic)
        b.material("Knob Material", .satinNickel)
        b.length("Knob Diameter", DK.mm(22)); b.length("Hole Diameter", DK.mm(10)); b.length("Body Length", DK.mm(40)); b.length("Body Width", DK.mm(22))
        b.flag("Inline", false, instance: false, group: .manufacturing)
        b.number("Max Load", 60, unit: "W", group: .data)
        b.electrical(watts: 0, volts: 12, supply: "DC 12–24 V, 5 A", cable: "2 x 22 AWG in / out", connector: "DC 5.5 x 2.1 mm")
        b.host([.sidePanel, .divider, .rail, .top, .bottom], faces: [.inside, .frontEdge, .bottom], align: .center)
        b.flag("Rotary", true, formula: "not(Inline)")
        b.visibility = "Rotary"
        b.box("Rotary Body", x: ("-Body Width / 2", "Body Width / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: ("-Body Length / 2", "-0.003 m"))
        b.rod("Shaft", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 - 0.001 m", from: "-0.003 m", to: CX.mm(4))
        b.using("Knob Material")
        b.revolve("Knob", profile: DK.pts([(DK.z, DK.z), ("Knob Diameter / 2", DK.z), ("Knob Diameter / 2", CX.mm(10)), ("Knob Diameter / 2 - 0.0015 m", CX.mm(12)), (DK.z, CX.mm(12))]),
                  base: CX.mm(1))
        b.using(nil)
        b.visibility = "Inline"
        b.roundedBar("Inline Body", width: "Body Length", height: "Body Width", radius: CX.mm(6), from: CX.zero, to: CX.mm(14))
        b.rod("Inline Wheel", axis: .x, center: (DK.z, CX.mm(14)), radius: CX.mm(7), from: CX.mm(-2), to: CX.mm(2))
        b.visibility = nil
        b.drill("Dimmer shaft hole", x: CX.zero, y: CX.zero, diameter: "if(Inline, 0 m, Hole Diameter)", depth: "Host Thickness", through: true)
        b.roundOutlines(radius: "Knob Diameter / 2", z: (DK.z, CX.mm(13)))
        b.type("Rotary Dimmer - 10 mm Shaft Hole", cost: 9.00, model: "DM-RT10")
        b.type("Inline Dimmer - 12/24 V", flags: ["Inline": true], cost: 7.00, model: "DM-IN")
        return b.build()
    }

    static func cableConnector() -> ComponentDefinition {
        var b = ComponentBuilder("LED Cable Connector", .lighting, "Cables & Power", "Connector for LED strips and low-voltage cables: strip clip, strip-to-wire, DC barrel or Y splitter.")
        b.tags("connector", "cable", "led", "clip", "splitter", "dc", "barrel")
        b.aliases("cable connectors", "led connector", "strip connector", "dc jack", "y splitter", "solderless connector")
        b.material("Body Material", .greyPlastic)
        b.length("Body Length", DK.mm(20)); b.length("Body Width", DK.mm(10)); b.length("Body Height", DK.mm(4))
        b.length("Lead Length", 0)
        b.host([.anyPart], faces: [.any], align: .center)
        b.box("Body", x: ("-Body Length / 2", "Body Length / 2"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.rod("Lead", axis: .x, center: (DK.z, "Body Height / 2"), radius: CX.mm(1.5), from: "Body Length / 2", to: "Body Length / 2 + max(Lead Length, 0.001 m)")
        b.outlines(x: ("-Body Length / 2", "Body Length / 2 + Lead Length"), y: ("-Body Width / 2", "Body Width / 2"), z: (DK.z, "Body Height"))
        b.type("Strip Clip - 8 mm, 2-Pin", cost: 0.60, model: "CC-8-2")
        b.type("Strip to Wire - 10 mm, 2-Pin", ["Body Width": DK.mm(12), "Lead Length": DK.mm(150)], cost: 0.80, model: "CC-10-W")
        b.type("DC Barrel Jack - 5.5 x 2.1 mm", ["Body Length": DK.mm(30), "Body Width": DK.mm(11), "Body Height": DK.mm(11), "Lead Length": DK.mm(100)], cost: 0.90, model: "CC-DC55")
        b.type("Y Splitter - DC 5.5 x 2.1 mm", ["Body Length": DK.mm(28), "Body Width": DK.mm(18), "Body Height": DK.mm(9), "Lead Length": DK.mm(200)], cost: 1.80, model: "CC-Y55")
        return b.build()
    }
}
