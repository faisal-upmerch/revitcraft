import Foundation
import ArcusGeometry

// COMPD: 17 Glass, Mirrors & Panel Accessories. Glass hardware is hosted on glass fronts, glass shelves and glass panels
// (host Glass) or on the carcass beside them; clamp fittings need no holes in the glass, through-bolted fittings drill it.

extension ComponentLibrary {
    static var groupDGlass: [ComponentDefinition] {
        [glassClamp(), glassClampHinge(), glassShelfSupport(), glassPanelConnector(), mirrorClip(), mirrorBracket(), mirrorPad(), glassDoorLock(),
         glassDoorHandle(), glassRetainingProfile(), glassSeal(), rubberGasket(), panelRetainer(), backPanelClip(), panelInsert(), aluminumFrame(),
         glassFrame()]
    }

    /// A clamp body straddling a glass edge in the face frame: the glass fills X ≥ 0 and Z from -Glass Thickness to 0.
    fileprivate static func edgeClamp(_ b: inout ComponentBuilder, _ name: String, reach: String, height: String, jaw: String) {
        let body = b.box(name, x: (CX.mm(-6), reach), y: ("-(\(height)) / 2", "(\(height)) / 2"), z: ("-Glass Thickness - \(jaw)", jaw))
        let slot = b.box("\(name) Glass Slot", x: (DK.z, "\(reach) + 0.001 m"), y: ("-(\(height)) / 2 - 0.001 m", "(\(height)) / 2 + 0.001 m"), z: ("-Glass Thickness", DK.z), void: true)
        if let k = b.definition.family.solids.firstIndex(where: { $0.id == slot }) { b.definition.family.solids[k].cuts = [body] }
    }

    static func glassClamp() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Clamp", .glass, "Glass Fittings", "Square clamp screwed to a panel or wall, holding a glass shelf or panel in a gasketed slot.")
        b.tags("glass", "clamp", "bracket", "shelf", "panel", "holder")
        b.aliases("glass clamps", "glass holder", "glass bracket", "glass shelf clamp", "glass panel clamp")
        b.material("Finish Material", .chrome)
        b.material("Gasket Material", .silicone)
        b.length("Glass Thickness", DK.mm(8), min: DK.mm(4), max: DK.mm(12))
        b.length("Body Width", DK.mm(45)); b.length("Body Height", DK.mm(40)); b.length("Body Depth", DK.mm(28))
        b.host([.sidePanel, .back, .divider, .wall], faces: [.inside], align: .center, alignments: [.center, .left, .right])
        let body = b.box("Body", x: ("-Body Width / 2", "Body Width / 2"), y: ("-Body Height / 2", "Body Height / 2"), z: (DK.z, "Body Depth"))
        let slot = b.box("Slot", x: ("-Body Width / 2 - 0.001 m", "Body Width / 2 + 0.001 m"), y: ("-Glass Thickness / 2 - 0.001 m", "Glass Thickness / 2 + 0.001 m"),
                         z: ("Body Depth * 0.3", "Body Depth + 0.001 m"), void: true)
        if let k = b.definition.family.solids.firstIndex(where: { $0.id == slot }) { b.definition.family.solids[k].cuts = [body] }
        b.using("Gasket Material")
        b.box("Gasket", x: ("-Body Width / 2 + 0.002 m", "Body Width / 2 - 0.002 m"), y: ("-Glass Thickness / 2 - 0.001 m", "-Glass Thickness / 2"), z: ("Body Depth * 0.3", "Body Depth - 0.002 m"))
        b.using(nil)
        b.drill("Clamp screw", x: CX.zero, y: "Body Height / 4", diameter: CX.mm(4), depth: CX.mm(25))
        b.drill("Clamp screw", x: CX.zero, y: "-Body Height / 4", diameter: CX.mm(4), depth: CX.mm(25))
        b.outlines(x: ("-Body Width / 2", "Body Width / 2"), y: ("-Body Height / 2", "Body Height / 2"), z: (DK.z, "Body Depth"))
        b.requires(.note("Glass shelves: tempered glass, at least 8 mm for spans over 24\"."))
        b.type("Glass Clamp - 6 mm", ["Glass Thickness": DK.mm(6)], cost: 6.50, model: "GC-06")
        b.type("Glass Clamp - 8 mm", cost: 7.00, model: "GC-08", isDefault: true)
        b.type("Glass Clamp - 10 mm", ["Glass Thickness": DK.mm(10), "Body Width": DK.mm(50), "Body Height": DK.mm(45)], cost: 8.50, model: "GC-10")
        return b.build()
    }

    static func glassClampHinge() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Door Hinge - Clamp", .glass, "Glass Fittings", "Clamp-on hinge for frameless glass cabinet doors: no hole in the glass, the leaf screwed to the carcass side.")
        b.tags("glass", "hinge", "door", "clamp", "frameless", "pivot")
        b.aliases("glass door hinges", "glass hinge", "glass clamp hinge", "showcase hinge", "frameless glass hinge")
        b.material("Finish Material", .chrome)
        b.length("Glass Thickness", DK.mm(5), min: DK.mm(4), max: DK.mm(8))
        b.length("Clamp Reach", DK.mm(36)); b.length("Clamp Height", DK.mm(42)); b.length("Knuckle Diameter", DK.mm(12)); b.length("Leaf Length", DK.mm(30))
        b.angle("Opening Angle", 180)
        b.hardwareKind(.hinge)
        b.host([.glass, .door], faces: [.front], align: .left, alignments: [.left, .right], offsetY: DK.inch(3), count: .hinges)
        edgeClamp(&b, "Clamp", reach: "Clamp Reach", height: "Clamp Height", jaw: CX.mm(3))
        b.rod("Knuckle", axis: .y, center: ("-Knuckle Diameter / 2 - 0.006 m", "-Glass Thickness / 2"), radius: "Knuckle Diameter / 2", from: "-Clamp Height / 2", to: "Clamp Height / 2")
        b.box("Carcass Leaf", x: ("-Knuckle Diameter - 0.006 m - Leaf Length", "-Knuckle Diameter / 2 - 0.006 m"), y: ("-Clamp Height / 2", "Clamp Height / 2"),
              z: ("-Glass Thickness / 2 - 0.0015 m", "-Glass Thickness / 2 + 0.0015 m"))
        b.drill("Hinge leaf screw", x: "-Knuckle Diameter - 0.006 m - Leaf Length / 2", y: "Clamp Height / 4", diameter: CX.mm(4), depth: CX.mm(16), target: .counterpart)
        b.drill("Hinge leaf screw", x: "-Knuckle Diameter - 0.006 m - Leaf Length / 2", y: "-Clamp Height / 4", diameter: CX.mm(4), depth: CX.mm(16), target: .counterpart)
        b.outlines(x: ("-Knuckle Diameter - 0.006 m - Leaf Length", "Clamp Reach"), y: ("-Clamp Height / 2", "Clamp Height / 2"), z: ("-Glass Thickness - 0.003 m", CX.mm(3)))
        b.symbol(.top, [.medium, .fine], dashed: true, .arc(center: DK.p("-Knuckle Diameter / 2 - 0.006 m", "-Glass Thickness / 2"), radius: "Clamp Reach", startDegrees: "0", sweepDegrees: "90"))
        b.requires(.hostThickness(min: "Glass Thickness - 0.001 m", max: "Glass Thickness + 0.002 m"))
        b.requires(.maxHostWeight("12"))
        b.type("Glass Door Hinge - 4-6 mm Glass", cost: 11.00, model: "GDH-46")
        b.type("Glass Door Hinge - 6-8 mm Glass", ["Glass Thickness": DK.mm(8), "Clamp Height": DK.mm(48)], cost: 13.00, model: "GDH-68")
        return b.build()
    }

    static func glassShelfSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Shelf Support - Pin with Pad", .glass, "Glass Fittings", "Shelf pin with a clear non-slip pad for glass shelves, in the side's shelf-pin holes.")
        b.tags("glass", "shelf", "support", "pin", "pad", "5 mm", "clear")
        b.aliases("glass shelf supports", "glass shelf pin", "glass shelf peg", "shelf support with pad", "glass shelf rest")
        b.material("Finish Material", .chrome)
        b.material("Pad Material", .silicone)
        b.length("Pin Diameter", DK.mm(5)); b.length("Pin Length", DK.mm(8)); b.length("Body Width", DK.mm(10)); b.length("Body Depth", DK.mm(12))
        b.length("Glass Thickness", DK.mm(6))
        b.flag("Retaining Lip", false, instance: false, group: .dimensions)
        b.hardwareKind(.shelfPin)
        b.host([.sidePanel, .divider], faces: [.inside], align: .center, alignments: [.center])
        b.rod("Pin", axis: .z, center: (DK.z, CX.mm(-3)), radius: "Pin Diameter / 2", from: "-Pin Length", to: CX.zero)
        b.box("Body", x: ("-Body Width / 2", "Body Width / 2"), y: (CX.mm(-6), CX.mm(-1.5)), z: (DK.z, "Body Depth"))
        b.using("Pad Material")
        b.box("Pad", x: ("-Body Width / 2 + 0.0008 m", "Body Width / 2 - 0.0008 m"), y: (CX.mm(-1.5), DK.z), z: (CX.mm(0.8), "Body Depth - 0.0008 m"))
        b.using(nil)
        b.visibility = "Retaining Lip"
        b.box("Lip", x: ("-Body Width / 2", "Body Width / 2"), y: (DK.z, "Glass Thickness + 0.002 m"), z: (DK.z, CX.mm(2)))
        b.visibility = nil
        b.drill("Shelf pin hole", x: CX.zero, y: CX.mm(-3), diameter: "Pin Diameter", depth: "Pin Length + 0.001 m")
        b.outlines(x: ("-Body Width / 2", "Body Width / 2"), y: (CX.mm(-6), DK.z), z: (DK.z, "Body Depth"))
        b.type("Glass Shelf Support - 5 mm, Clear Pad", cost: 0.35, model: "GSS-5P")
        b.type("Glass Shelf Support - 1/4\", Clear Pad", ["Pin Diameter": DK.inch(0.25), "Pin Length": DK.inch(0.375)], cost: 0.38, model: "GSS-14P")
        b.type("Glass Shelf Support - 5 mm, Retaining Lip", flags: ["Retaining Lip": true], cost: 0.45, model: "GSS-5L")
        return b.build()
    }

    static func glassPanelConnector() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Panel Connector", .glass, "Glass Fittings", "Connector joining glass panels: through-bolted caps in drilled glass, or a 90° corner clamp.")
        b.tags("glass", "connector", "panel", "bolt", "corner", "cube", "display case")
        b.aliases("glass panel connectors", "glass connector", "glass to glass connector", "glass corner connector", "standoff connector")
        b.material("Finish Material", .chrome)
        b.length("Glass Thickness", DK.mm(6)); b.length("Cap Diameter", DK.mm(25)); b.length("Cap Height", DK.mm(8)); b.length("Hole Diameter", DK.mm(12))
        b.flag("Corner Clamp", false, instance: false, group: .dimensions)
        b.flag("Through Bolt", true, formula: "not(Corner Clamp)")
        b.host([.glass, .shelf, .door, .sidePanel], faces: [.front], align: .topLeft, alignments: [.topLeft, .topRight, .bottomLeft, .bottomRight], offsetX: DK.mm(30), offsetY: DK.mm(30))
        b.visibility = "Through Bolt"
        b.revolve("Front Cap", profile: DK.pts([(DK.z, DK.z), ("Cap Diameter / 2", DK.z), ("Cap Diameter / 2", "Cap Height * 0.6"), ("Cap Diameter / 2 - 0.003 m", "Cap Height"), (DK.z, "Cap Height")]))
        b.rod("Bolt", axis: .z, center: (DK.z, DK.z), radius: "Hole Diameter / 2 - 0.001 m", from: "-Glass Thickness", to: CX.zero)
        b.rod("Back Cap", axis: .z, center: (DK.z, DK.z), radius: "Cap Diameter / 2", from: "-Glass Thickness - Cap Height * 0.6", to: "-Glass Thickness")
        b.visibility = "Corner Clamp"
        let block = b.box("Corner Block", x: (CX.mm(-8), CX.mm(22)), y: (CX.mm(-15), CX.mm(15)), z: ("-Glass Thickness - 0.022 m", CX.mm(3)))
        for v in [b.box("Corner Slot A", x: (DK.z, CX.mm(23)), y: (CX.mm(-16), CX.mm(16)), z: ("-Glass Thickness", DK.z), void: true),
                  b.box("Corner Slot B", x: (CX.mm(-6), "-0.006 m + Glass Thickness"), y: (CX.mm(-16), CX.mm(16)), z: ("-Glass Thickness - 0.023 m", "-Glass Thickness - 0.002 m"), void: true)] {
            if let k = b.definition.family.solids.firstIndex(where: { $0.id == v }) { b.definition.family.solids[k].cuts = [block] }
        }
        b.visibility = nil
        b.drill("Glass bolt hole", x: CX.zero, y: CX.zero, diameter: "if(Corner Clamp, 0 m, Hole Diameter)", depth: "Glass Thickness", through: true)
        b.roundOutlines(radius: "Cap Diameter / 2", z: ("-Glass Thickness - Cap Height * 0.6", "Cap Height"))
        b.requires(.note("Drilled glass must be tempered after drilling; keep holes 2 x thickness from edges."))
        b.type("Glass Panel Connector - Through-Bolt, 6 mm Glass", cost: 9.00, model: "GPC-B06")
        b.type("Glass Panel Connector - Through-Bolt, 10 mm Glass", ["Glass Thickness": DK.mm(10), "Cap Diameter": DK.mm(30), "Hole Diameter": DK.mm(14)], cost: 11.00, model: "GPC-B10")
        b.type("Glass Panel Connector - 90° Corner, 8 mm Glass", ["Glass Thickness": DK.mm(8)], flags: ["Corner Clamp": true], cost: 12.50, model: "GPC-C08")
        return b.build()
    }

    static func mirrorClip() -> ComponentDefinition {
        var b = ComponentBuilder("Mirror Clip", .glass, "Mirror Fittings", "J-clip screwed to the backing, its lip holding the mirror's edge.")
        b.tags("mirror", "clip", "j-clip", "holder", "glass")
        b.aliases("mirror clips", "mirror holder", "mirror j clip", "glass clip")
        b.material("Finish Material", .chrome)
        b.length("Mirror Thickness", DK.inch(0.25)); b.length("Clip Width", DK.mm(20)); b.length("Lip", DK.mm(6)); b.length("Tab Length", DK.mm(16)); b.length("Metal", DK.mm(1.2))
        b.host([.back, .door, .sidePanel, .wall], faces: [.inside, .front], align: .bottom, alignments: [.bottom, .top, .left, .right])
        // The mirror sits on the face above Y = 0; the clip's tab is below it, the riser at its edge and the lip over its face.
        b.extrusion("Clip", profile: DK.pts([("-Tab Length", DK.z), (DK.z, DK.z), (DK.z, "Mirror Thickness"), ("Lip", "Mirror Thickness"), ("Lip", "Mirror Thickness + Metal"),
                                             ("-Metal", "Mirror Thickness + Metal"), ("-Metal", "Metal"), ("-Tab Length", "Metal")]),
                    plane: .yz, from: "-Clip Width / 2", to: "Clip Width / 2")
        b.drill("Mirror clip screw", x: CX.zero, y: "-Tab Length / 2", diameter: CX.mm(3), depth: CX.mm(12))
        b.outlines(x: ("-Clip Width / 2", "Clip Width / 2"), y: ("-Tab Length", "Lip"), z: (DK.z, "Mirror Thickness + Metal"))
        b.type("Mirror Clip - 1/8\" Mirror", ["Mirror Thickness": DK.inch(0.125)], cost: 0.60, model: "MC-18")
        b.type("Mirror Clip - 1/4\" Mirror", cost: 0.65, model: "MC-14", isDefault: true)
        return b.build()
    }

    static func mirrorBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Mirror Mounting Bracket", .glass, "Mirror Fittings", "Interlocking Z-clip pair (French cleat): one on the mirror's back, one on the wall or panel.")
        b.tags("mirror", "bracket", "z-clip", "cleat", "hanging", "panel")
        b.aliases("mirror mounting brackets", "z clip", "french cleat", "panel hanger", "mirror hanger", "interlocking clip")
        b.material("Finish Material", .aluminum)
        b.length("Clip Length", DK.inch(2)); b.length("Leg", DK.mm(18)); b.length("Offset", DK.mm(6)); b.length("Metal", DK.mm(1.6))
        b.host([.back, .sidePanel, .door, .wall], faces: [.inside, .back], align: .top, alignments: [.top, .center], offsetY: DK.inch(2))
        // Wall clip: flat on the face, hook up; mirror clip: hook down into it.
        b.extrusion("Wall Clip", profile: DK.pts([(DK.z, DK.z), ("Leg", DK.z), ("Leg", "Offset + Metal"), ("Leg - 0.004 m", "Offset + Metal"), ("Leg - 0.004 m", "Metal"),
                                                  (DK.z, "Metal")]), plane: .yz, from: "-Clip Length / 2", to: "Clip Length / 2")
        b.extrusion("Mirror Clip", profile: DK.pts([("Leg - 0.0055 m", "Metal + 0.0003 m"), ("Leg - 0.0042 m", "Metal + 0.0003 m"), ("Leg - 0.0042 m", "Offset + Metal + 0.0003 m"),
                                                    ("Leg * 2 - 0.006 m", "Offset + Metal + 0.0003 m"), ("Leg * 2 - 0.006 m", "Offset + 2 * Metal + 0.0003 m"),
                                                    ("Leg - 0.0055 m", "Offset + 2 * Metal + 0.0003 m")]), plane: .yz, from: "-Clip Length / 2", to: "Clip Length / 2")
        b.screwPair("Z-clip screw", spacing: "Clip Length * 0.6", y: "Leg / 3", diameter: 3.5, depth: 16)
        b.outlines(x: ("-Clip Length / 2", "Clip Length / 2"), y: (DK.z, "Leg * 2 - 0.006 m"), z: (DK.z, "Offset + 2 * Metal"))
        b.type("Z-Clip - 2\"", cost: 2.50, model: "ZC-2")
        b.type("Z-Clip - 4\"", ["Clip Length": DK.inch(4)], cost: 3.50, model: "ZC-4")
        b.type("Z-Clip Hanging Rail - 12\"", ["Clip Length": DK.inch(12), "Leg": DK.mm(25), "Metal": DK.mm(2)], cost: 7.50, model: "ZR-12")
        return b.build()
    }

    static func mirrorPad() -> ComponentDefinition {
        var b = ComponentBuilder("Mirror Adhesive Pad", .glass, "Mirror Fittings", "Double-sided foam mounting pad for mirrors and panels.")
        b.tags("mirror", "adhesive", "pad", "tape", "foam", "mounting")
        b.aliases("mirror adhesive pads", "mounting tape", "foam pad", "double sided pad", "mirror tape")
        b.material("Pad Material", .foam)
        b.length("Pad Width", DK.inch(1)); b.length("Pad Height", DK.inch(1)); b.length("Thickness", DK.mm(1.6)); b.length("Corner Radius", DK.mm(2))
        b.host([.back, .door, .sidePanel, .glass, .wall], faces: [.inside, .back, .front], align: .center)
        b.roundedBar("Pad", width: "Pad Width", height: "Pad Height", radius: "Corner Radius", from: CX.zero, to: "Thickness")
        b.outlines(x: ("-Pad Width / 2", "Pad Width / 2"), y: ("-Pad Height / 2", "Pad Height / 2"), z: (DK.z, "Thickness"))
        b.type("Mirror Pad - 1\" Square", cost: 0.20, model: "MP-1SQ")
        b.type("Mirror Pad - 3/4\" x 4\" Strip", ["Pad Width": DK.inch(4), "Pad Height": DK.inch(0.75)], cost: 0.35, model: "MP-34X4")
        b.type("Mirror Pad - 1/2\" Round", ["Pad Width": DK.inch(0.5), "Pad Height": DK.inch(0.5), "Corner Radius": DK.inch(0.25)], cost: 0.12, model: "MP-12R")
        return b.build()
    }

    static func glassDoorLock() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Door Lock", .glass, "Glass Fittings", "Keyed push lock clamped on a hinged glass door's edge, with a strike on the carcass.")
        b.tags("glass", "lock", "door", "showcase", "keyed", "clamp", "push lock")
        b.aliases("glass door locks", "showcase lock", "glass cabinet push lock", "display case lock")
        b.material("Finish Material", .chrome)
        b.material("Strike Material", .steel)
        b.length("Glass Thickness", DK.mm(5)); b.length("Body Width", DK.mm(30)); b.length("Body Height", DK.mm(40)); b.length("Cylinder Diameter", DK.mm(18))
        b.host([.glass, .door], faces: [.front], align: .right, alignments: [.right, .left, .center])
        edgeClamp(&b, "Lock Body", reach: "Body Width", height: "Body Height", jaw: CX.mm(5))
        b.rod("Cylinder", axis: .z, center: ("Body Width / 2", CX.zero), radius: "Cylinder Diameter / 2", from: CX.mm(5), to: CX.mm(9))
        b.box("Keyway", x: ("Body Width / 2 - 0.001 m", "Body Width / 2 + 0.001 m"), y: (CX.mm(-4), CX.mm(4)), z: (CX.mm(8.5), CX.mm(9.2)), void: true)
        b.using("Strike Material")
        b.box("Strike", x: (CX.mm(-22), CX.mm(-8)), y: (CX.mm(-18), CX.mm(18)), z: ("-Glass Thickness - 0.004 m", "-Glass Thickness + 0.004 m"))
        b.using(nil)
        b.drill("Strike screw", x: CX.mm(-15), y: CX.mm(10), diameter: CX.mm(3.5), depth: CX.mm(14), target: .counterpart)
        b.drill("Strike screw", x: CX.mm(-15), y: CX.mm(-10), diameter: CX.mm(3.5), depth: CX.mm(14), target: .counterpart)
        b.outlines(x: (CX.mm(-22), "Body Width"), y: ("-Body Height / 2", "Body Height / 2"), z: ("-Glass Thickness - 0.005 m", CX.mm(9)))
        b.requires(.hostThickness(min: "Glass Thickness - 0.001 m", max: "Glass Thickness + 0.002 m"))
        b.type("Glass Door Lock - 4-6 mm Glass", cost: 14.00, model: "GDL-46")
        b.type("Glass Door Lock - 6-8 mm Glass", ["Glass Thickness": DK.mm(8)], cost: 15.50, model: "GDL-68")
        return b.build()
    }

    static func glassDoorHandle() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Door Handle", .glass, "Glass Fittings", "Knob or bar handle bolted through a drilled glass door, with a rose on each side.")
        b.tags("glass", "handle", "knob", "pull", "door", "through bolt")
        b.aliases("glass door handles", "glass knob", "glass pull", "showcase handle", "back to back pull")
        b.material("Finish Material", .chrome)
        b.length("Glass Thickness", DK.mm(6)); b.length("Hole Spacing", 0); b.length("Hole Diameter", DK.mm(12))
        b.length("Projection", DK.mm(28)); b.length("Grip Diameter", DK.mm(25)); b.length("Bar Diameter", DK.mm(12))
        b.flag("Bar", false, instance: false, group: .dimensions)
        b.flag("Knob", true, formula: "not(Bar)")
        b.hardwareKind(.handle)
        b.host([.glass, .door], faces: [.front], align: .outside, alignments: [.outside, .center, .inside], offsetX: DK.inch(1.5))
        for (s, n) in [("-", "Left"), ("", "Right")] {
            b.rod("\(n) Rose", axis: .z, center: ("\(s)Hole Spacing / 2", CX.zero), radius: CX.mm(9), from: CX.zero, to: CX.mm(3))
            b.rod("\(n) Back Rose", axis: .z, center: ("\(s)Hole Spacing / 2", CX.zero), radius: CX.mm(9), from: "-Glass Thickness - 0.003 m", to: "-Glass Thickness")
        }
        b.visibility = "Knob"
        b.revolve("Knob", profile: DK.pts([(DK.z, DK.z), (CX.mm(6), DK.z), (CX.mm(5), "Projection * 0.45"), ("Grip Diameter / 2", "Projection * 0.75"),
                                           ("Grip Diameter / 2 - 0.001 m", "Projection"), (DK.z, "Projection")]), base: CX.mm(3))
        b.visibility = "Bar"
        for s in ["-", ""] {
            b.rod("Post \(s)", axis: .z, center: ("\(s)Hole Spacing / 2", CX.zero), radius: CX.mm(5), from: CX.mm(3), to: "Projection - Bar Diameter / 2")
        }
        b.rod("Bar", axis: .x, center: (CX.zero, "Projection - Bar Diameter / 2"), radius: "Bar Diameter / 2", from: "-Hole Spacing / 2 - 0.02 m", to: "Hole Spacing / 2 + 0.02 m")
        b.visibility = nil
        b.drill("Glass handle hole", x: "-Hole Spacing / 2", y: CX.zero, diameter: "Hole Diameter", depth: "Glass Thickness", through: true)
        b.drill("Glass handle hole", x: "Hole Spacing / 2", y: CX.zero, diameter: "if(Bar, Hole Diameter, 0 m)", depth: "Glass Thickness", through: true)
        b.outlines(x: ("-Hole Spacing / 2 - 0.02 m", "Hole Spacing / 2 + 0.02 m"), y: (CX.mm(-13), CX.mm(13)), z: ("-Glass Thickness - 0.003 m", "Projection"))
        b.clearance(.box(name: "Finger space", x0: "-0.03 m", x1: "0.03 m", y0: "-0.03 m", y1: "0.03 m", z0: "0 m", z1: "Projection"))
        b.type("Glass Knob - 12 mm Hole", cost: 8.50, model: "GKN-12")
        b.type("Glass Bar Handle - 96 mm CC", ["Hole Spacing": DK.mm(96)], flags: ["Bar": true], cost: 13.00, model: "GBH-96")
        b.type("Glass Bar Handle - 128 mm CC", ["Hole Spacing": DK.mm(128)], flags: ["Bar": true], cost: 15.00, model: "GBH-128")
        return b.build()
    }

    static func glassRetainingProfile() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Retaining Profile", .glass, "Glass Profiles", "Push-in PVC channel set in a routed groove that holds a glass panel or back by its edge.")
        b.tags("glass", "profile", "channel", "retaining", "groove", "glazing")
        b.aliases("glass retaining profiles", "glass channel", "glazing channel", "glass groove insert", "glass track")
        b.material("Profile Material", .clearPVC)
        b.runLength(DK.mm(600))
        b.length("Glass Thickness", DK.mm(4)); b.length("Wall", DK.mm(1.2)); b.length("Channel Depth", DK.mm(8))
        b.hostRun([.shelf, .top, .bottom, .sidePanel, .rail, .divider], faces: [.inside, .top, .bottom])
        b.run("Channel", DK.pts([("-Glass Thickness / 2 - Wall", "-Channel Depth"), ("Glass Thickness / 2 + Wall", "-Channel Depth"), ("Glass Thickness / 2 + Wall", DK.z),
                                 ("Glass Thickness / 2 + Wall + 0.0015 m", "0.0008 m"), ("Glass Thickness / 2", "0.0008 m"), ("Glass Thickness / 2", "-Channel Depth + Wall"),
                                 ("-Glass Thickness / 2", "-Channel Depth + Wall"), ("-Glass Thickness / 2", "0.0008 m"), ("-Glass Thickness / 2 - Wall - 0.0015 m", "0.0008 m"),
                                 ("-Glass Thickness / 2 - Wall", DK.z)]))
        b.groove("Glass channel groove", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Glass Thickness + 2 * Wall", depth: "Channel Depth")
        b.runOutlines(y: ("-Glass Thickness / 2 - Wall - 0.0015 m", "Glass Thickness / 2 + Wall + 0.0015 m"), z: ("-Channel Depth", CX.mm(0.8)))
        b.requires(.hostThickness(min: "Channel Depth + 0.006 m", max: nil))
        b.type("Glass Retaining Profile - 4 mm Glass", cost: 1.80, model: "GRP-04")
        b.type("Glass Retaining Profile - 6 mm Glass", ["Glass Thickness": DK.mm(6)], cost: 2.10, model: "GRP-06")
        return b.build()
    }

    static func glassSeal() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Seal", .glass, "Glass Profiles", "Clear seal clipped on a glass door's edge: a flexible fin closes the gap to the next door or the carcass.")
        b.tags("glass", "seal", "fin", "gap", "edge", "door")
        b.aliases("glass seals", "glass door seal", "glass edge seal", "fin seal", "h seal")
        b.material("Seal Material", .clearPVC)
        b.runLength(DK.mm(700))
        b.length("Glass Thickness", DK.mm(4)); b.length("Grip Depth", DK.mm(8)); b.length("Fin Length", DK.mm(8)); b.length("Wall", DK.mm(1))
        b.hostRun([.glass, .door], faces: [.leftEdge, .rightEdge, .topEdge, .bottomEdge])
        b.run("Clip", DK.pts([("-Glass Thickness / 2 - Wall", "-Grip Depth"), ("-Glass Thickness / 2", "-Grip Depth"), ("-Glass Thickness / 2", DK.z),
                              ("Glass Thickness / 2", DK.z), ("Glass Thickness / 2", "-Grip Depth"), ("Glass Thickness / 2 + Wall", "-Grip Depth"),
                              ("Glass Thickness / 2 + Wall", "Wall"), ("-Glass Thickness / 2 - Wall", "Wall")]))
        b.run("Fin", DK.pts([(CX.mm(-0.4), "Wall"), (CX.mm(0.4), "Wall"), ("0.0004 m + Fin Length * 0.25", "Wall + Fin Length"), ("-0.0004 m + Fin Length * 0.25", "Wall + Fin Length")]))
        b.runOutlines(y: ("-Glass Thickness / 2 - Wall", "Glass Thickness / 2 + Wall"), z: ("-Grip Depth", "Wall + Fin Length"))
        b.requires(.hostThickness(min: "Glass Thickness - 0.0005 m", max: "Glass Thickness + 0.0005 m"))
        b.type("Glass Seal - 4 mm Glass", cost: 2.20, model: "GS-04")
        b.type("Glass Seal - 6 mm Glass", ["Glass Thickness": DK.mm(6)], cost: 2.40, model: "GS-06")
        b.type("Glass Seal - 8 mm Glass, Long Fin", ["Glass Thickness": DK.mm(8), "Fin Length": DK.mm(14)], cost: 2.90, model: "GS-08L")
        return b.build()
    }

    static func rubberGasket() -> ComponentDefinition {
        var b = ComponentBuilder("Rubber Gasket", .glass, "Glass Profiles", "Ribbed wedge gasket pressed between glass and its frame to bed the glass and stop rattles.")
        b.tags("gasket", "rubber", "glazing", "wedge", "glass", "frame")
        b.aliases("rubber gaskets", "glazing gasket", "glass gasket", "wedge gasket", "glazing rubber", "epdm gasket")
        b.material("Gasket Material", .rubber)
        b.runLength(DK.mm(600))
        b.length("Gap", DK.mm(3)); b.length("Gasket Height", DK.mm(8))
        b.hostRun([.glass, .door, .rail], faces: [.leftEdge, .rightEdge, .topEdge, .bottomEdge, .inside])
        var prof: [(String, String)] = [("-Gap / 2", DK.z), ("Gap / 2", DK.z)]
        for k in 0..<3 {
            let z0 = "Gasket Height * \(LX.num(0.2 + 0.27 * Double(k)))", z1 = "Gasket Height * \(LX.num(0.32 + 0.27 * Double(k)))"
            prof += [("Gap / 2", z0), ("Gap / 2 + 0.0008 m", z1)]
        }
        prof += [("Gap / 2", "Gasket Height"), ("-Gap / 2 - 0.0012 m", "Gasket Height"), ("-Gap / 2 - 0.0012 m", "Gasket Height - 0.001 m"), ("-Gap / 2", "Gasket Height - 0.0015 m")]
        b.run("Gasket", DK.pts(prof))
        b.runOutlines(y: ("-Gap / 2 - 0.0012 m", "Gap / 2 + 0.0008 m"), z: (DK.z, "Gasket Height"))
        b.type("Rubber Gasket - 3 mm Gap", cost: 0.90, model: "RG-03")
        b.type("Rubber Gasket - 5 mm Gap", ["Gap": DK.mm(5), "Gasket Height": DK.mm(10)], cost: 1.10, model: "RG-05")
        return b.build()
    }

    static func panelRetainer() -> ComponentDefinition {
        var b = ComponentBuilder("Panel Retainer", .glass, "Panel Fittings", "Turn button screwed beside a rebate: turned over the edge it holds a back, mirror or glass panel in.")
        b.tags("retainer", "turn button", "panel", "back", "glass", "rebate")
        b.aliases("panel retainers", "turn button", "glass retainer", "back panel turn button", "mirror retainer")
        b.material("Finish Material", .brass)
        b.length("Button Length", DK.inch(1.25)); b.length("Button Width", DK.inch(0.5)); b.length("Thickness", DK.mm(2.5)); b.length("Step", 0)
        b.host([.sidePanel, .top, .bottom, .rail, .door], faces: [.back, .inside], align: .center, alignments: [.center, .left, .right, .top, .bottom])
        b.roundedBar("Button", center: ("Button Length * 0.2", CX.zero), width: "Button Length", height: "Button Width", radius: "Button Width / 2", from: "Step", to: "Step + Thickness")
        b.rod("Step Block", axis: .z, center: (DK.z, DK.z), radius: "Button Width / 2", from: CX.zero, to: "max(Step, 0.0003 m)")
        b.rod("Screw Head", axis: .z, center: (DK.z, DK.z), radius: CX.mm(3.5), from: "Step + Thickness", to: "Step + Thickness + 0.0015 m")
        b.drill("Turn button screw", x: CX.zero, y: CX.zero, diameter: CX.mm(2.5), depth: CX.mm(10))
        b.outlines(x: ("-Button Width / 2", "Button Length * 0.7"), y: ("-Button Width / 2", "Button Width / 2"), z: (DK.z, "Step + Thickness"))
        b.type("Turn Button - 1 1/4\"", cost: 0.40, model: "TB-125")
        b.type("Turn Button - 1 3/4\" Offset", ["Button Length": DK.inch(1.75), "Button Width": DK.inch(0.6), "Step": DK.inch(0.125)], cost: 0.55, model: "TB-175O")
        return b.build()
    }

    static func backPanelClip() -> ComponentDefinition {
        var b = ComponentBuilder("Back Panel Clip", .glass, "Panel Fittings", "Spring clip screwed inside the carcass that holds a removable back or access panel.")
        b.tags("clip", "panel", "back", "removable", "spring", "access")
        b.aliases("panel clips", "back panel clip", "access panel clip", "spring panel clip", "removable panel clip")
        b.material("Finish Material", .whitePlastic)
        b.length("Panel Thickness", DK.inch(0.25)); b.length("Clip Width", DK.mm(14)); b.length("Base Length", DK.mm(22)); b.length("Wall", DK.mm(1.5))
        b.host([.sidePanel, .top, .bottom, .divider], faces: [.inside], align: .center, alignments: [.center, .top, .bottom])
        b.extrusion("Clip", profile: DK.pts([(DK.z, DK.z), ("Base Length", DK.z), ("Base Length", "Wall"), ("Wall + Panel Thickness", "Wall"),
                                             ("Wall + Panel Thickness", "Wall + 0.004 m"), ("Wall + Panel Thickness - 0.0008 m", "Wall + 0.004 m"),
                                             ("Wall + Panel Thickness - 0.0008 m", "Wall + 0.0008 m"), ("Wall", "Wall + 0.0008 m"), ("Wall", "Wall + 0.006 m"), (DK.z, "Wall + 0.006 m")]),
                    plane: .yz, from: "-Clip Width / 2", to: "Clip Width / 2")
        b.drill("Panel clip screw", x: CX.zero, y: "Base Length - 0.006 m", diameter: CX.mm(3), depth: CX.mm(12))
        b.outlines(x: ("-Clip Width / 2", "Clip Width / 2"), y: (DK.z, "Base Length"), z: (DK.z, "Wall + 0.006 m"))
        b.type("Back Panel Clip - 1/8\" Panel", ["Panel Thickness": DK.inch(0.125)], cost: 0.25, model: "BPC-18")
        b.type("Back Panel Clip - 1/4\" Panel", cost: 0.25, model: "BPC-14", isDefault: true)
        return b.build()
    }

    static func panelInsert() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Panel Insert", .glass, "Panel Inserts", "Panel set in a frame door's opening: raised, reeded or grid, sized to the opening.")
        b.tags("panel", "insert", "raised", "reeded", "grid", "door", "decorative")
        b.aliases("decorative panel inserts", "door panel insert", "raised panel", "reeded panel", "fluted panel", "grid panel")
        b.material("Panel Material", .maple)
        b.length("Width", DK.inch(12), instance: true); b.length("Height", DK.inch(20), instance: true)
        b.length("Thickness", DK.inch(0.25)); b.length("Field Height", DK.inch(0.375)); b.length("Bevel", DK.inch(1.5))
        b.flag("Raised", false, instance: false, group: .dimensions)
        b.flag("Reeded", false, instance: false, group: .dimensions)
        b.flag("Grid", false, instance: false, group: .dimensions)
        b.host([.door, .back, .sidePanel], faces: [.front], align: .center)
        b.box("Panel", x: ("-Width / 2", "Width / 2"), y: ("-Height / 2", "Height / 2"), z: (DK.z, "Thickness"))
        b.visibility = "Raised"
        b.blend("Raised Field", bottom: ComponentKit.rect(width: "Width - 0.004 m", height: "Height - 0.004 m"),
                top: ComponentKit.rect(width: "Width - 2 * Bevel", height: "Height - 2 * Bevel"), from: "Thickness", to: "Field Height")
        b.visibility = "Reeded"
        let n = 12
        for k in 0..<n {
            let x = "-Width / 2 + Width * \(LX.num((Double(k) + 0.5) / Double(n)))"
            b.rod("Reed \(k + 1)", axis: .y, center: (x, "Thickness"), radius: "Width / \(2 * n) * 0.98", from: "-Height / 2", to: "Height / 2", segments: 20)
        }
        b.visibility = "Grid"
        for k in 1..<4 {
            let x = "-Width / 2 + Width * \(LX.num(Double(k) / 4))"
            b.box("Grid Stile \(k)", x: ("\(x) - 0.004 m", "\(x) + 0.004 m"), y: ("-Height / 2", "Height / 2"), z: ("Thickness", "Thickness + 0.005 m"))
        }
        for k in 1..<6 {
            let y = "-Height / 2 + Height * \(LX.num(Double(k) / 6))"
            b.box("Grid Rail \(k)", x: ("-Width / 2", "Width / 2"), y: ("\(y) - 0.004 m", "\(y) + 0.004 m"), z: ("Thickness", "Thickness + 0.005 m"))
        }
        b.box("Grid Border", x: ("-Width / 2", "-Width / 2 + 0.008 m"), y: ("-Height / 2", "Height / 2"), z: ("Thickness", "Thickness + 0.005 m"))
        b.box("Grid Border R", x: ("Width / 2 - 0.008 m", "Width / 2"), y: ("-Height / 2", "Height / 2"), z: ("Thickness", "Thickness + 0.005 m"))
        b.visibility = nil
        b.outlines(x: ("-Width / 2", "Width / 2"), y: ("-Height / 2", "Height / 2"), z: (DK.z, "Field Height"))
        b.requires(.note("Sized to the frame's opening plus the groove depth on each side (1/4\" per side by default)."))
        b.type("Panel Insert - Raised", flags: ["Raised": true], cost: 18.00, model: "PI-RA")
        b.type("Panel Insert - Reeded", ["Thickness": DK.inch(0.375)], flags: ["Reeded": true], cost: 28.00, model: "PI-RE")
        b.type("Panel Insert - Grid", flags: ["Grid": true], cost: 24.00, model: "PI-GR")
        b.type("Panel Insert - Flat", cost: 9.00, model: "PI-FL")
        return b.build()
    }

    /// A rectangular frame of four bars round a Width × Height opening (outer size), with a glass pane in it.
    fileprivate static func frame(_ b: inout ComponentBuilder, bar: String, depth: String, rebate: String) {
        let w = "Width / 2", h = "Height / 2"
        b.box("Left Stile", x: ("-\(w)", "-\(w) + \(bar)"), y: ("-\(h)", h), z: (DK.z, depth))
        b.box("Right Stile", x: ("\(w) - \(bar)", w), y: ("-\(h)", h), z: (DK.z, depth))
        b.box("Top Rail", x: ("-\(w) + \(bar)", "\(w) - \(bar)"), y: ("\(h) - \(bar)", h), z: (DK.z, depth))
        b.box("Bottom Rail", x: ("-\(w) + \(bar)", "\(w) - \(bar)"), y: ("-\(h)", "-\(h) + \(bar)"), z: (DK.z, depth))
        b.using("Glass Material")
        b.box("Glass", x: ("-\(w) + \(bar) - \(rebate)", "\(w) - \(bar) + \(rebate)"), y: ("-\(h) + \(bar) - \(rebate)", "\(h) - \(bar) + \(rebate)"),
              z: ("\(depth) / 2 - Glass Thickness / 2", "\(depth) / 2 + Glass Thickness / 2"))
        b.using(nil)
        b.outlines(x: ("-\(w)", w), y: ("-\(h)", h), z: (DK.z, depth))
        b.symbol(.face, [.medium, .fine], .rect(("-\(w) + \(bar)", "-\(h) + \(bar)"), ("\(w) - \(bar)", "\(h) - \(bar)")))
    }

    static func aluminumFrame() -> ComponentDefinition {
        var b = ComponentBuilder("Aluminum Frame Profile", .glass, "Glass Profiles", "Aluminium frame door profile with mitred corners and a glass or panel infill.")
        b.tags("aluminum", "frame", "profile", "door", "glass", "mitred")
        b.aliases("aluminum frame profiles", "aluminium frame door", "alu frame", "glass frame door profile", "metal frame door")
        b.material("Frame Material", .blackAnodized)
        b.material("Glass Material", .glass)
        b.length("Width", DK.inch(15), instance: true); b.length("Height", DK.inch(30), instance: true)
        b.length("Profile Width", DK.mm(20)); b.length("Profile Depth", DK.mm(20)); b.length("Glass Thickness", DK.mm(4)); b.length("Rebate", DK.mm(6))
        b.host([.door, .flap], faces: [.front], align: .center)
        frame(&b, bar: "Profile Width", depth: "Profile Depth", rebate: "Rebate")
        b.requires(.note("Hinges: frame hinges with 35 mm cups need a profile at least 20 mm wide; drill the hinge holes in the profile's channel."))
        b.type("Aluminum Frame - 20 mm Narrow", cost: 48.00, model: "AFP-20")
        b.type("Aluminum Frame - 45 mm Wide", ["Profile Width": DK.mm(45)], cost: 62.00, model: "AFP-45")
        return b.build()
    }

    static func glassFrame() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Frame Profile", .glass, "Glass Profiles", "Slim U-profile framing a glass panel's edges (frameless doors, glass sides and backs).")
        b.tags("glass", "frame", "profile", "u-profile", "edge", "aluminum")
        b.aliases("glass frame profiles", "glass edge frame", "glass edge profile", "u frame", "picture frame profile")
        b.material("Frame Material", .anodized)
        b.material("Glass Material", .glass)
        b.length("Width", DK.inch(15), instance: true); b.length("Height", DK.inch(30), instance: true)
        b.length("Glass Thickness", DK.mm(4)); b.length("Wall", DK.mm(1.5)); b.length("Lip", DK.mm(8))
        b.length("Profile Depth", DK.mm(7), formula: "Glass Thickness + 2 * Wall")
        b.host([.glass, .door, .shelf], faces: [.front], align: .center)
        frame(&b, bar: "Lip", depth: "Profile Depth", rebate: "Lip - Wall")
        b.requires(.hostThickness(min: "Glass Thickness - 0.0005 m", max: "Glass Thickness + 0.0005 m"))
        b.type("Glass Frame Profile - 4 mm Glass", cost: 22.00, model: "GFP-04")
        b.type("Glass Frame Profile - 6 mm Glass", ["Glass Thickness": DK.mm(6)], cost: 25.00, model: "GFP-06")
        b.type("Glass Frame Profile - 8 mm Glass", ["Glass Thickness": DK.mm(8), "Lip": DK.mm(10)], cost: 28.00, model: "GFP-08")
        return b.build()
    }
}
