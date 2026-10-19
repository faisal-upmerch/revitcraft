import Foundation
import ArcusGeometry

// COMPA: 05 Sliding Door Systems (18). Tracks and systems are plan-based (a along the track, b toward the back, c up),
// centred on the opening: top tracks hang under the carcass top (c ≤ 0), bottom tracks sit on the bottom (c ≥ 0), and
// their Length follows the host. Door hardware fixed to a face (barn door rail, lock, handle, frame profile) is
// face-based.

extension GroupA {
    static var slidingDoors: [ComponentDefinition] {
        [topTrack(), bottomTrack(), singleDoorKit(), doubleDoorKit(), bypassTrack(), pocketDoorHardware(), barnDoorTrack(), slidingRoller(), bottomGuide(),
         slidingStop(), softCloseSliding(), slidingDamper(), slidingDoorLockHook(), slidingDoorHandle(), slidingFrameProfile(), wardrobeSystem(), glassSlidingSystem(),
         foldingSlidingSystem()]
    }

    /// A plan-based sliding-door item with a Length that follows its host.
    static func sliding(_ name: String, _ sub: String, _ description: String, finish f: ComponentFinish = .aluminum, top: Bool = true, full: Bool = true) -> ShapeA {
        var g = faced(name, .slidingDoors, sub, description, frame: .plan)
        g.levels = [.medium, .fine]
        g.b.material(finish, f)
        if full {
            g.b.length("Length", inch(36), instance: true)
            g.b.host(top ? [.top, .shelf] : [.bottom, .shelf, .floor], faces: [top ? .bottom : .top], align: .full)
        } else {
            g.b.host(top ? [.top, .shelf] : [.bottom, .shelf, .floor], faces: [top ? .bottom : .top], align: .left, alignments: [.left, .right, .center])
        }
        g.b.tags("sliding door", "slider", "hardware")
        return g
    }

    /// Track screws along its centreline (every third of the length).
    static func trackScrews(_ b: inout ComponentBuilder) {
        for x in ["-Length / 2 + 0.05 m", "-Length / 6", "Length / 6", "Length / 2 - 0.05 m"] { b.drill("Track screw", x: x, y: CX.zero, diameter: CX.mm(4), depth: CX.mm(12)) }
    }

    /// A top track: `n` channels open downward, each Channel Width wide, Track Height deep (b across, c down).
    static func topChannels(_ g: inout ShapeA, count n: Int, prefix: String = "", fascia: Bool = false) {
        let W = "(\(n) * Channel Width + Wall)", r = ("-Length / 2", "Length / 2")
        g.prism("\(prefix)Track Top", along: 0, profile: PtsA.box(("-\(W) / 2", "\(W) / 2"), ("-Wall", CX.zero)), range: r)
        for k in 0...n {
            let y = "-\(W) / 2 + \(k) * Channel Width"
            g.prism("\(prefix)Track Wall \(k + 1)", along: 0, profile: PtsA.box((y, "\(y) + Wall"), ("-Track Height", "-Wall")), range: r)
            // Inward lips at the bottom of each wall keep the rollers in.
            if k > 0 { g.prism("\(prefix)Lip \(k)L", along: 0, profile: PtsA.box(("\(y) - 0.002 m", y), ("-Track Height", "-Track Height + Wall")), range: r) }
            if k < n { g.prism("\(prefix)Lip \(k + 1)R", along: 0, profile: PtsA.box(("\(y) + Wall", "\(y) + Wall + 0.002 m"), ("-Track Height", "-Track Height + Wall")), range: r) }
        }
        if fascia {
            g.prism("\(prefix)Fascia", along: 0, profile: PtsA.box(("-\(W) / 2 - Wall", "-\(W) / 2"), ("-Track Height - 0.012 m", CX.zero)), range: r)
        }
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Length / 2", "-\(W) / 2"), ("Length / 2", "\(W) / 2")))
        g.b.symbol(.top, [.coarse], .rect(("-Length / 2", "-Track Height"), ("Length / 2", CX.zero)))
    }

    /// A bottom track: a base with a guide fin per channel.
    static func bottomChannels(_ g: inout ShapeA, count n: Int, at z: String = CX.zero, prefix: String = "") {
        let W = "(\(n) * Channel Width + Wall)", r = ("-Length / 2", "Length / 2")
        g.prism("\(prefix)Base", along: 0, profile: PtsA.box(("-\(W) / 2", "\(W) / 2"), (z, "\(z) + Wall")), range: r)
        for k in 0..<n {
            let y = "-\(W) / 2 + Wall / 2 + (\(k) + 0.5) * Channel Width"
            g.prism("\(prefix)Guide Fin \(k + 1)", along: 0, profile: [("\(y) - Wall", "\(z) + Wall"), ("\(y) + Wall", "\(z) + Wall"), ("\(y) + Wall * 0.6", "\(z) + Bottom Height"),
                                                                       ("\(y) - Wall * 0.6", "\(z) + Bottom Height")], range: r)
        }
        for (k, y) in ["-\(W) / 2", "\(W) / 2 - Wall"].enumerated() {
            g.prism("\(prefix)Edge \(k + 1)", along: 0, profile: PtsA.box((y, "\(y) + Wall"), ("\(z) + Wall", "\(z) + Bottom Height * 0.6")), range: r)
        }
    }

    /// A top-hung roller carriage in a channel at (a, b): two wheels turning about b, the body and the hanger bolt.
    static func carriage(_ g: inout ShapeA, _ n: String, x: String, y: String) {
        g.using("Roller Material")
        for (k, dx) in ["-0.012 m", "0.012 m"].enumerated() {
            g.revolve("\(n) Wheel \(k + 1)", along: 1, center: ("\(x) + \(dx)", "-Track Height * 0.45"),
                      profile: [("0.0015 m", "\(y) - 0.004 m"), ("Track Height * 0.28", "\(y) - 0.004 m"), ("Track Height * 0.3", "\(y) - 0.002 m"), ("Track Height * 0.3", "\(y) + 0.002 m"),
                                ("Track Height * 0.28", "\(y) + 0.004 m"), ("0.0015 m", "\(y) + 0.004 m")])
        }
        g.using(finish)
        g.box("\(n) Body", a: ("\(x) - 0.02 m", "\(x) + 0.02 m"), b: ("\(y) - 0.005 m", "\(y) + 0.005 m"), c: ("-Track Height * 0.62", "-Track Height * 0.3"))
        g.cylinder("\(n) Hanger Bolt", along: 2, center: (x, y), radius: CX.mm(4), range: ("-Track Height - 0.012 m", "-Track Height * 0.6"), segments: 12)
        g.box("\(n) Door Plate", a: ("\(x) - 0.03 m", "\(x) + 0.03 m"), b: ("\(y) - Door Thickness / 2", "\(y) + Door Thickness / 2"), c: ("-Track Height - 0.015 m", "-Track Height - 0.012 m"))
    }

    // MARK: Tracks

    static func topTrack() -> ComponentDefinition {
        var g = sliding("Top Sliding Track", "Tracks", "Extruded aluminium top track with one, two or three channels for top-hung doors.")
        g.b.tags("top track", "aluminium", "channel", "overhead track")
        g.b.aliases("top sliding tracks", "top track", "upper track", "overhead track", "head track", "top rail")
        g.b.integer("Track Count", 2); g.b.length("Channel Width", mm(20)); g.b.length("Track Height", mm(30)); g.b.length("Wall", mm(1.6), group: .manufacturing)
        g.b.flag("Single", false, formula: "Track Count = 1"); g.b.flag("Double", false, formula: "Track Count = 2"); g.b.flag("Triple", false, formula: "Track Count >= 3")
        trackScrews(&g.b)
        for (k, f) in ["Single", "Double", "Triple"].enumerated() { g.variant(f) { g in topChannels(&g, count: k + 1, prefix: "") } }
        g.b.type("Top Sliding Track - Single", [:], numbers: ["Track Count": 1], cost: 9.00, model: "TST-1", description: "Single top track, aluminium, per 36\" (914 mm)")
        g.b.type("Top Sliding Track - Double", [:], numbers: ["Track Count": 2], cost: 14.00, model: "TST-2", description: "Double top track, aluminium, per 36\"", isDefault: true)
        g.b.type("Top Sliding Track - Triple", [:], numbers: ["Track Count": 3], cost: 19.00, model: "TST-3", description: "Triple top track, aluminium, per 36\"")
        return g.build()
    }

    static func bottomTrack() -> ComponentDefinition {
        var g = sliding("Bottom Sliding Track", "Tracks", "Low bottom track with a guide fin per door, for bottom-rolling doors.", top: false)
        g.b.tags("bottom track", "floor track", "guide", "aluminium")
        g.b.aliases("bottom sliding tracks", "bottom track", "floor track", "lower track", "bottom rail", "sill track")
        g.b.integer("Track Count", 2); g.b.length("Channel Width", mm(20)); g.b.length("Bottom Height", mm(8)); g.b.length("Wall", mm(1.6), group: .manufacturing)
        g.b.flag("Single", false, formula: "Track Count = 1"); g.b.flag("Double", false, formula: "Track Count >= 2")
        trackScrews(&g.b)
        g.variant("Single") { g in bottomChannels(&g, count: 1) }
        g.variant("Double") { g in bottomChannels(&g, count: 2) }
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", "-(Track Count * Channel Width + Wall) / 2"), ("Length / 2", "(Track Count * Channel Width + Wall) / 2")))
        g.b.type("Bottom Sliding Track - Single", [:], numbers: ["Track Count": 1], cost: 6.50, model: "BST-1", description: "Single bottom track, per 36\" (914 mm)")
        g.b.type("Bottom Sliding Track - Double", [:], numbers: ["Track Count": 2], cost: 9.50, model: "BST-2", description: "Double bottom track, per 36\"", isDefault: true)
        return g.build()
    }

    static func bypassTrack() -> ComponentDefinition {
        var g = sliding("Bypass Door Track", "Tracks", "Double bypass track with a front fascia, for closet doors that pass each other.", finish: .aluminum)
        g.b.material("Roller Material", .nylon)
        g.b.tags("bypass", "closet", "double track", "fascia")
        g.b.aliases("bypass door tracks", "bypass track", "closet track", "by-pass door hardware", "sliding closet track")
        g.b.length("Channel Width", mm(25)); g.b.length("Track Height", mm(35)); g.b.length("Wall", mm(1.8), group: .manufacturing); g.b.length("Door Thickness", inch(0.75))
        trackScrews(&g.b)
        topChannels(&g, count: 2, fascia: true)
        g.levels = [.fine]
        carriage(&g, "Front Roller", x: "-Length / 4", y: "-Channel Width / 2")
        carriage(&g, "Back Roller", x: "Length / 4", y: "Channel Width / 2")
        g.b.type("Bypass Door Track - 48\"", ["Length": inch(48)], cost: 32.00, model: "BPT-48", description: "Bypass track kit with fascia, 48\" (1219 mm)", isDefault: true)
        g.b.type("Bypass Door Track - 72\"", ["Length": inch(72)], cost: 44.00, model: "BPT-72", description: "Bypass track kit with fascia, 72\" (1829 mm)")
        return g.build()
    }

    // MARK: Kits and systems

    static func singleDoorKit() -> ComponentDefinition {
        var g = sliding("Single Sliding Door Kit", "Door Kits", "Top-hung kit for one door: track, two roller hangers, a bottom guide and end stops.")
        g.b.material("Roller Material", .nylon)
        g.b.material("Stop Material", .greyPlastic)
        g.b.tags("kit", "single door", "top hung", "complete")
        g.b.aliases("single sliding door kits", "single door kit", "one door slider kit", "sliding door hardware set")
        g.b.length("Door Width", inch(24), instance: true); g.b.length("Door Thickness", inch(0.75)); g.b.length("Door Height", inch(30), instance: true)
        g.b.length("Channel Width", mm(22)); g.b.length("Track Height", mm(30)); g.b.length("Wall", mm(1.6), group: .manufacturing)
        g.b.number("Door Weight Capacity", 55, unit: "lb")
        g.b.requires(.fitsWidth("Door Width * 2"))
        trackScrews(&g.b)
        topChannels(&g, count: 1)
        let x0 = "-Length / 2 + Door Width"
        carriage(&g, "Left Hanger", x: "-Length / 2 + 0.06 m", y: CX.zero)
        carriage(&g, "Right Hanger", x: "\(x0) - 0.06 m", y: CX.zero)
        g.using("Stop Material")
        g.box("Left Stop", a: ("-Length / 2", "-Length / 2 + 0.02 m"), b: ("-Channel Width / 2 + Wall", "Channel Width / 2 - Wall"), c: ("-Track Height + 0.004 m", "-Wall"))
        g.box("Right Stop", a: ("Length / 2 - 0.02 m", "Length / 2"), b: ("-Channel Width / 2 + Wall", "Channel Width / 2 - Wall"), c: ("-Track Height + 0.004 m", "-Wall"))
        g.box("Bottom Guide", a: ("-Length / 2 + Door Width / 2 - 0.02 m", "-Length / 2 + Door Width / 2 + 0.02 m"), b: ("-Door Thickness / 2 - 0.006 m", "Door Thickness / 2 + 0.006 m"),
              c: ("-Track Height - 0.015 m - Door Height", "-Track Height - 0.015 m - Door Height + 0.012 m"))
        g.using(nil)
        g.b.type("Single Sliding Door Kit - 55 lb", [:], cost: 48.00, model: "SDK-1-25", description: "Single sliding door kit, 25 kg (55 lb) door, 36\" track", isDefault: true)
        g.b.type("Single Sliding Door Kit - 110 lb", ["Track Height": mm(40), "Channel Width": mm(28)], numbers: ["Door Weight Capacity": 110], cost: 74.00, model: "SDK-1-50",
                 description: "Heavy single sliding door kit, 50 kg (110 lb) door")
        return g.build()
    }

    static func doubleDoorKit() -> ComponentDefinition {
        var g = sliding("Double Sliding Door Kit", "Door Kits", "Top-hung kit for two passing doors: double track, four hangers, guides and stops.")
        g.b.material("Roller Material", .nylon)
        g.b.material("Stop Material", .greyPlastic)
        g.b.tags("kit", "double door", "bypass", "top hung", "complete")
        g.b.aliases("double sliding door kits", "two door kit", "bypass kit", "pair sliding door kit", "2 door slider kit")
        g.b.length("Door Width", inch(19), instance: true); g.b.length("Door Thickness", inch(0.75)); g.b.length("Door Height", inch(30), instance: true)
        g.b.length("Channel Width", mm(22)); g.b.length("Track Height", mm(30)); g.b.length("Wall", mm(1.6), group: .manufacturing)
        g.b.number("Door Weight Capacity", 55, unit: "lb")
        trackScrews(&g.b)
        topChannels(&g, count: 2)
        let yF = "-Channel Width / 2", yB = "Channel Width / 2"
        carriage(&g, "Front Door Left Hanger", x: "-Length / 2 + 0.06 m", y: yF)
        carriage(&g, "Front Door Right Hanger", x: "-Length / 2 + Door Width - 0.06 m", y: yF)
        carriage(&g, "Back Door Left Hanger", x: "Length / 2 - Door Width + 0.06 m", y: yB)
        carriage(&g, "Back Door Right Hanger", x: "Length / 2 - 0.06 m", y: yB)
        g.using("Stop Material")
        g.box("Bottom Guide", a: (CX.mm(-25), CX.mm(25)), b: ("-Channel Width - 0.004 m", "Channel Width + 0.004 m"),
              c: ("-Track Height - 0.015 m - Door Height", "-Track Height - 0.015 m - Door Height + 0.012 m"))
        g.using(nil)
        g.b.type("Double Sliding Door Kit - 55 lb", [:], cost: 79.00, model: "SDK-2-25", description: "Double sliding door kit, two 25 kg (55 lb) doors, 36\" track", isDefault: true)
        g.b.type("Double Sliding Door Kit - 110 lb", ["Track Height": mm(40), "Channel Width": mm(28)], numbers: ["Door Weight Capacity": 110], cost: 119.00, model: "SDK-2-50",
                 description: "Heavy double sliding door kit, two 50 kg (110 lb) doors")
        return g.build()
    }

    /// Two framed door panels (front and back channels) hung under a track, overlapping at the middle.
    static func framedPanels(_ g: inout ShapeA, height: String, depthOffset: String = "Channel Width / 2", glass: Bool = false) {
        let w = "(Length + Overlap) / 2", t = "Door Thickness", z1 = "-Track Height - 0.012 m", z0 = "\(z1) - \(height)"
        for (n, x0, y) in [("Front Door", "-Length / 2", "-(\(depthOffset))"), ("Back Door", "Length / 2 - \(w)", depthOffset)] {
            g.using(glass ? "Glass Material" : "Panel Material")
            g.box("\(n) Panel", a: (x0, "\(x0) + \(w)"), b: ("\(y) - \(t) / 2", "\(y) + \(t) / 2"), c: (z0, z1))
            g.using(finish)
            if !glass {
                g.box("\(n) Left Stile", a: (x0, "\(x0) + Stile Width"), b: ("\(y) - \(t) / 2 - 0.002 m", "\(y) + \(t) / 2 + 0.002 m"), c: (z0, z1))
                g.box("\(n) Right Stile", a: ("\(x0) + \(w) - Stile Width", "\(x0) + \(w)"), b: ("\(y) - \(t) / 2 - 0.002 m", "\(y) + \(t) / 2 + 0.002 m"), c: (z0, z1))
                g.box("\(n) Top Rail", a: (x0, "\(x0) + \(w)"), b: ("\(y) - \(t) / 2 - 0.001 m", "\(y) + \(t) / 2 + 0.001 m"), c: ("\(z1) - 0.03 m", z1))
                g.box("\(n) Bottom Rail", a: (x0, "\(x0) + \(w)"), b: ("\(y) - \(t) / 2 - 0.001 m", "\(y) + \(t) / 2 + 0.001 m"), c: (z0, "\(z0) + 0.03 m"))
            }
        }
        g.using(nil)
    }

    static func wardrobeSystem() -> ComponentDefinition {
        var g = sliding("Wardrobe Sliding System", "Door Systems", "Two-door wardrobe system: double top and bottom tracks and framed doors that overlap at the middle.")
        g.b.material("Panel Material", melamine)
        g.b.material("Roller Material", .nylon)
        g.b.tags("wardrobe", "closet", "system", "framed doors", "complete")
        g.b.aliases("wardrobe sliding systems", "wardrobe slider", "closet door system", "sliding wardrobe doors", "armoire sliding system")
        g.b.length("Opening Height", inch(84), instance: true); g.b.length("Door Thickness", mm(18)); g.b.length("Overlap", mm(40)); g.b.length("Stile Width", mm(40))
        g.b.length("Channel Width", mm(28)); g.b.length("Track Height", mm(40)); g.b.length("Bottom Height", mm(10)); g.b.length("Wall", mm(1.8), group: .manufacturing)
        g.b.number("Door Weight Capacity", 88, unit: "lb")
        g.b.requires(.fitsHeight("Opening Height"))
        trackScrews(&g.b)
        g.levels = [.coarse, .medium, .fine]
        framedPanels(&g, height: "Opening Height - Track Height - 0.012 m - Bottom Height - 0.004 m")
        g.levels = [.medium, .fine]
        topChannels(&g, count: 2)
        bottomChannels(&g, count: 2, at: "-Opening Height", prefix: "Bottom ")
        g.b.type("Wardrobe Sliding System - 2 Doors 72\"", ["Length": inch(72)], cost: 189.00, model: "WSS-2-72",
                 description: "Two-door wardrobe system, 72\" (1829 mm) opening, 84\" tall", isDefault: true)
        g.b.type("Wardrobe Sliding System - 2 Doors 96\"", ["Length": inch(96)], cost: 239.00, model: "WSS-2-96", description: "Two-door wardrobe system, 96\" (2438 mm) opening")
        return g.build()
    }

    static func glassSlidingSystem() -> ComponentDefinition {
        var g = sliding("Glass Sliding Door System", "Door Systems", "Frameless glass sliding doors: top track, patch clamps on the glass, a bottom guide and finger cups.",
                        finish: .stainless)
        g.b.material("Glass Material", .glass)
        g.b.material("Roller Material", .nylon)
        g.b.tags("glass", "frameless", "showcase", "display cabinet", "system")
        g.b.aliases("glass sliding door systems", "glass slider", "frameless glass sliding", "showcase sliding doors", "glass cabinet sliders")
        g.b.length("Opening Height", inch(24), instance: true); g.b.length("Door Thickness", mm(6)); g.b.length("Overlap", mm(25))
        g.b.length("Channel Width", mm(16)); g.b.length("Track Height", mm(25)); g.b.length("Bottom Height", mm(8)); g.b.length("Wall", mm(1.5), group: .manufacturing)
        g.b.length("Stile Width", 0, group: .manufacturing)
        g.b.requires(.note("Glass is toughened and edge-polished; finger cups are drilled by the glass supplier."))
        trackScrews(&g.b)
        g.levels = [.coarse, .medium, .fine]
        framedPanels(&g, height: "Opening Height - Track Height - 0.012 m - Bottom Height - 0.004 m", glass: true)
        g.levels = [.medium, .fine]
        topChannels(&g, count: 2)
        bottomChannels(&g, count: 2, at: "-Opening Height", prefix: "Bottom ")
        let w = "(Length + Overlap) / 2", z1 = "-Track Height - 0.012 m"
        for (n, x0, y) in [("Front", "-Length / 2", "-Channel Width / 2"), ("Back", "Length / 2 - \(w)", "Channel Width / 2")] {
            for (k, dx) in ["0.06 m", "\(w) - 0.06 m"].enumerated() {
                g.box("\(n) Clamp \(k + 1)", a: ("\(x0) + \(dx) - 0.025 m", "\(x0) + \(dx) + 0.025 m"), b: ("\(y) - Door Thickness / 2 - 0.004 m", "\(y) + Door Thickness / 2 + 0.004 m"),
                      c: ("\(z1) - 0.04 m", "\(z1) + 0.008 m"))
            }
            g.cylinder("\(n) Finger Cup", along: 1, center: ("\(x0) + \(n == "Front" ? "\(w) - 0.04 m" : "0.04 m")", "-Opening Height / 2"), radius: CX.mm(14),
                       range: ("\(y) - Door Thickness / 2 - 0.001 m", "\(y) + Door Thickness / 2 + 0.001 m"), segments: 24)
        }
        g.b.type("Glass Sliding Door System - 36\"", [:], cost: 129.00, model: "GSS-36", description: "Glass sliding door system, 36\" (914 mm), for 6 mm (1/4\") glass", isDefault: true)
        g.b.type("Glass Sliding Door System - 48\"", ["Length": inch(48)], cost: 159.00, model: "GSS-48", description: "Glass sliding door system, 48\" (1219 mm)")
        return g.build()
    }

    static func foldingSlidingSystem() -> ComponentDefinition {
        var g = sliding("Folding Sliding Door System", "Door Systems", "Folding (bi-fold) sliding doors: four hinged panels hung from a top track, shown closed.")
        g.b.material("Panel Material", .oak)
        g.b.material("Roller Material", .nylon)
        g.b.tags("folding", "bi-fold", "concertina", "multi panel", "system")
        g.b.aliases("folding sliding door systems", "bifold doors", "bi-fold door kit", "concertina doors", "folding door track", "accordion doors")
        g.b.length("Opening Height", inch(80), instance: true); g.b.length("Door Thickness", mm(22))
        g.b.length("Channel Width", mm(25)); g.b.length("Track Height", mm(35)); g.b.length("Wall", mm(1.8), group: .manufacturing)
        g.b.integer("Panel Count", 4)
        trackScrews(&g.b)
        topChannels(&g, count: 1)
        let pw = "(Length - 0.006 m) / 4", z1 = "-Track Height - 0.01 m", z0 = "-Opening Height + 0.01 m"
        g.levels = [.coarse, .medium, .fine]
        g.using("Panel Material")
        for k in 0..<4 {
            let x0 = "-Length / 2 + 0.001 m + \(k) * ((\(pw)) + 0.0013 m)"
            g.box("Panel \(k + 1)", a: (x0, "\(x0) + \(pw)"), b: ("-Door Thickness / 2", "Door Thickness / 2"), c: (z0, z1))
        }
        g.levels = [.medium, .fine]
        g.using(finish)
        for k in 1..<4 {
            let x = "-Length / 2 + \(k) * ((\(pw)) + 0.0013 m)"
            for (j, z) in ["\(z0) + 0.15 m", "(\(z0) + \(z1)) / 2", "\(z1) - 0.15 m"].enumerated() {
                g.cylinder("Hinge \(k).\(j + 1)", along: 2, center: (x, "Door Thickness / 2 + 0.003 m"), radius: CX.mm(4), range: ("\(z) - 0.035 m", "\(z) + 0.035 m"), segments: 12)
            }
        }
        g.cylinder("Pivot Pin", along: 2, center: ("-Length / 2 + 0.02 m", CX.zero), radius: CX.mm(5), range: (z1, "-Track Height * 0.4"), segments: 14)
        carriage(&g, "Guide Carrier", x: "-Length / 2 + 2 * ((\(pw)) + 0.0013 m)", y: CX.zero)
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", "-Door Thickness / 2"), ("Length / 2", "Door Thickness / 2")))
        g.b.type("Folding Sliding Door System - 4 Panels 48\"", ["Length": inch(48)], cost: 149.00, model: "FSD-4-48", description: "Four-panel folding door system, 48\" (1219 mm) opening",
                 isDefault: true)
        g.b.type("Folding Sliding Door System - 4 Panels 72\"", ["Length": inch(72)], cost: 199.00, model: "FSD-4-72", description: "Four-panel folding door system, 72\" (1829 mm) opening")
        return g.build()
    }

    static func pocketDoorHardware() -> ComponentDefinition {
        var g = ShapeA(ComponentBuilder("Pocket Door Hardware", .slidingDoors, "Pocket Doors", "Retractable (flipper) door slides: the open door slides back into a pocket beside the carcass side.",
                                        frame: .legacyOpening))
        g.b.material(finish, .zinc)
        g.b.material("Carrier Material", .greyPlastic)
        g.b.tags("pocket door", "flipper door", "retractable", "tv cabinet", "slides")
        g.b.aliases("pocket door slides", "flipper door hardware", "retractable door slide", "pocket door system", "media cabinet pocket door")
        g.b.length("Opening Width", inch(30), instance: true); g.b.length("Opening Height", inch(36), instance: true)
        g.b.length("Slide Length", mm(450)); g.b.length("Slide Height", mm(35)); g.b.length("Slide Thickness", mm(12.7)); g.b.length("Pocket Width", mm(32))
        g.b.number("Door Weight Capacity", 40, unit: "lb")
        g.b.host([.bay], faces: [.inside], align: .bottom, mirroredPair: true)
        g.b.requires(.fitsDepth("Slide Length + 0.025 m"))
        for (s, x, n) in [(1.0, CX.zero, "Left"), (-1.0, "Opening Width", "Right")] {
            for (k, z) in ["0.06 m", "Opening Height - 0.06 m"].enumerated() {
                g.prism("\(n) Slide \(k + 1)", along: 1, profile: channel(x, s, depth: "Slide Thickness", height: "Slide Height", t: CX.mm(1.2), z: z), range: (CX.mm(20), "Slide Length + 0.02 m"))
            }
            g.using("Carrier Material")
            g.box("\(n) Carrier", a: pairRange((off(x, s, "Slide Thickness"), off(x, s, "Slide Thickness + 0.004 m")), s), b: (CX.mm(20), CX.mm(70)), c: (CX.mm(40), "Opening Height - 0.04 m"))
            g.using(nil)
            g.cylinder("\(n) Cable Pulley", along: 0, center: ("Slide Length", "Opening Height / 2"), radius: CX.mm(14), range: pairRange((off(x, s, "0.002 m"), off(x, s, "0.008 m")), s), segments: 18)
        }
        g.b.symbol(.top, [.coarse], .rect((CX.zero, CX.mm(20)), ("Slide Thickness", "Slide Length + 0.02 m")),
                   .rect(("Opening Width - Slide Thickness", CX.mm(20)), ("Opening Width", "Slide Length + 0.02 m")))
        g.b.type("Pocket Door Hardware - 450 mm", [:], cost: 89.00, model: "PDH-450", description: "Pocket (flipper) door slides, 450 mm (17 3/4\") travel, per door", isDefault: true)
        g.b.type("Pocket Door Hardware - 550 mm", ["Slide Length": mm(550)], cost: 99.00, model: "PDH-550", description: "Pocket (flipper) door slides, 550 mm (21 5/8\") travel")
        return g.build()
    }

    // MARK: Parts

    static func slidingRoller() -> ComponentDefinition {
        var g = sliding("Sliding Door Roller", "Rollers & Guides", "Roller carriage for a sliding door: top-hung in the track or set into the door's bottom.", full: false)
        g.b.material("Roller Material", .nylon)
        g.b.tags("roller", "wheel", "carriage", "hanger", "trolley")
        g.b.aliases("sliding door rollers", "door roller", "top roller", "bottom roller", "sliding wheel", "door trolley")
        g.b.length("Wheel Diameter", mm(24)); g.b.length("Track Height", mm(30)); g.b.length("Door Thickness", inch(0.75)); g.b.number("Load Rating", 55, unit: "lb")
        g.b.flag("Bottom Roller", false, instance: false, group: .dimensions)
        g.b.drill("Roller screw", x: CX.mm(-20), y: CX.zero, diameter: CX.mm(4), depth: CX.mm(14))
        g.b.drill("Roller screw", x: CX.mm(20), y: CX.zero, diameter: CX.mm(4), depth: CX.mm(14))
        g.variant("Bottom Roller", when: false) { g in carriage(&g, "Top", x: CX.zero, y: CX.zero) }
        g.variant("Bottom Roller") { g in
            // Set into the door's bottom edge (origin there, c up into the door): the housing and a wheel below it.
            g.box("Housing", a: (CX.mm(-35), CX.mm(35)), b: ("-Door Thickness / 2 + 0.003 m", "Door Thickness / 2 - 0.003 m"), c: (CX.mm(-2), CX.mm(22)))
            g.using("Roller Material")
            g.revolve("Wheel", along: 1, center: (CX.zero, "-Wheel Diameter / 2 + 0.006 m"),
                      profile: [(CX.mm(2), CX.mm(-4)), ("Wheel Diameter / 2", CX.mm(-4)), ("Wheel Diameter / 2", CX.mm(4)), (CX.mm(2), CX.mm(4))])
            g.using(nil)
        }
        g.b.symbol(.face, [.coarse], .rect((CX.mm(-35), "-Door Thickness / 2"), (CX.mm(35), "Door Thickness / 2")))
        g.b.type("Sliding Door Roller - Top Hung", [:], flags: ["Bottom Roller": false], cost: 6.50, model: "SDR-T", description: "Top-hung roller carriage, 25 kg (55 lb)", isDefault: true)
        g.b.type("Sliding Door Roller - Bottom", ["Wheel Diameter": mm(30)], flags: ["Bottom Roller": true], numbers: ["Load Rating": 88], cost: 7.25, model: "SDR-B",
                 description: "Bottom roller set into the door, 40 kg (88 lb)")
        return g.build()
    }

    static func bottomGuide() -> ComponentDefinition {
        var g = sliding("Bottom Guide", "Rollers & Guides", "Floor guide that keeps a top-hung door in line: a T fin in the door's groove, or a U channel around its edge.",
                        finish: .greyPlastic, top: false, full: false)
        g.b.tags("guide", "floor guide", "bottom guide", "t guide", "u channel")
        g.b.aliases("bottom guides", "floor guide", "door guide", "t-guide", "u guide", "sliding door guide")
        g.b.length("Length", mm(50)); g.b.length("Door Thickness", inch(0.75)); g.b.length("Guide Height", mm(14))
        g.b.flag("U Channel", false, instance: false, group: .dimensions)
        g.b.drill("Guide screw", x: "-Length / 3", y: CX.zero, diameter: CX.mm(4), depth: CX.mm(12))
        g.b.drill("Guide screw", x: "Length / 3", y: CX.zero, diameter: CX.mm(4), depth: CX.mm(12))
        g.variant("U Channel", when: false) { g in
            g.prism("Base", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Length", CX.mm(24), CX.mm(4)), range: (CX.zero, CX.mm(3)))
            g.box("Fin", a: ("-Length / 2 + 0.006 m", "Length / 2 - 0.006 m"), b: (CX.mm(-2), CX.mm(2)), c: (CX.mm(3), "Guide Height"))
        }
        g.variant("U Channel") { g in
            g.prism("Base", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Length", "Door Thickness + 0.012 m", CX.mm(3)), range: (CX.zero, CX.mm(3)))
            for (n, y) in [("Front Wall", "-Door Thickness / 2 - 0.004 m"), ("Back Wall", "Door Thickness / 2 + 0.001 m")] {
                g.box(n, a: ("-Length / 2", "Length / 2"), b: (y, "\(y) + 0.003 m"), c: (CX.mm(3), "Guide Height"))
            }
        }
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", "-Door Thickness / 2 - 0.006 m"), ("Length / 2", "Door Thickness / 2 + 0.006 m")))
        g.b.type("Bottom Guide - T Fin", [:], flags: ["U Channel": false], cost: 1.75, model: "BG-T", description: "T-fin floor guide for doors with a bottom groove", isDefault: true)
        g.b.type("Bottom Guide - U Channel", [:], flags: ["U Channel": true], cost: 2.25, model: "BG-U", description: "U-channel floor guide for 3/4\" (19 mm) doors")
        return g.build()
    }

    static func slidingStop() -> ComponentDefinition {
        var g = sliding("Sliding Door Stop", "Stops & Dampers", "Stop clamped in the track, with a rubber buffer, that sets where a door stops.", finish: .greyPlastic, full: false)
        g.b.material("Bumper Material", .rubber)
        g.b.tags("stop", "track stop", "buffer", "end stop")
        g.b.aliases("sliding door stops", "track stop", "door stop", "end stop", "sliding buffer stop")
        g.b.length("Channel Width", mm(20)); g.b.length("Track Height", mm(30)); g.b.length("Stop Length", mm(30))
        g.box("Block", a: (CX.zero, "Stop Length"), b: ("-Channel Width / 2 + 0.002 m", "Channel Width / 2 - 0.002 m"), c: ("-Track Height * 0.8", "-0.002 m"))
        g.using("Bumper Material")
        g.revolve("Buffer", along: 0, center: (CX.zero, "-Track Height * 0.45"), profile: [(CX.zero, CX.mm(-6)), (CX.mm(5), CX.mm(-6)), (CX.mm(6), CX.mm(-3)), (CX.mm(6), CX.zero), (CX.zero, CX.zero)])
        g.using(nil)
        let saved = g.levels
        g.levels = [.fine]
        g.cylinder("Clamp Screw", along: 2, center: ("Stop Length / 2", CX.zero), radius: CX.mm(3), range: ("-Track Height * 0.8 - 0.001 m", "-Track Height * 0.8"), segments: 12)
        g.levels = saved
        g.b.symbol(.face, [.coarse], .rect((CX.mm(-6), "-Channel Width / 2"), ("Stop Length", "Channel Width / 2")))
        g.b.type("Sliding Door Stop - Standard", [:], cost: 1.95, model: "SDS-20", description: "Track stop with rubber buffer, 20 mm channel", isDefault: true)
        g.b.type("Sliding Door Stop - Heavy", ["Channel Width": mm(28), "Track Height": mm(40), "Stop Length": mm(40)], cost: 2.95, model: "SDS-28", description: "Track stop for 28 mm channels")
        return g.build()
    }

    static func softCloseSliding() -> ComponentDefinition {
        var g = sliding("Soft-Close Sliding Mechanism", "Stops & Dampers", "Damper unit in the top track that catches the door's activator and closes it gently.", finish: .greyPlastic, full: false)
        g.b.material("Activator Material", .steel)
        g.b.tags("soft close", "damper", "sliding", "quiet", "self close")
        g.b.aliases("soft-close sliding mechanisms", "sliding soft close", "door damper unit", "soft stop", "self closing sliding")
        g.b.length("Channel Width", mm(20)); g.b.length("Track Height", mm(30)); g.b.length("Unit Length", mm(200)); g.b.number("Door Weight Capacity", 88, unit: "lb")
        g.b.length("Stroke", mm(60))
        g.box("Housing", a: (CX.zero, "Unit Length"), b: ("-Channel Width / 2 + 0.002 m", "Channel Width / 2 - 0.002 m"), c: ("-Track Height * 0.7", "-0.002 m"))
        g.cylinder("Damper", along: 0, center: (CX.zero, "-Track Height * 0.35"), radius: "Channel Width * 0.22", range: ("Unit Length * 0.3", "Unit Length * 0.95"), segments: 16)
        g.box("Catch", a: (CX.mm(4), CX.mm(16)), b: ("-Channel Width / 2 + 0.003 m", "Channel Width / 2 - 0.003 m"), c: ("-Track Height * 0.85", "-Track Height * 0.7"))
        g.using("Activator Material")
        g.cylinder("Activator Pin", along: 2, center: ("-Stroke", CX.zero), radius: CX.mm(3), range: ("-Track Height - 0.012 m", "-Track Height * 0.75"), segments: 12)
        g.using(nil)
        g.b.symbol(.face, [.coarse], .rect((CX.zero, "-Channel Width / 2"), ("Unit Length", "Channel Width / 2")))
        g.b.type("Soft-Close Sliding Mechanism - 88 lb", [:], cost: 24.00, model: "SCM-40", description: "Soft-close unit for sliding doors to 40 kg (88 lb)", isDefault: true)
        g.b.type("Soft-Close Sliding Mechanism - 176 lb", ["Unit Length": mm(260), "Channel Width": mm(28), "Track Height": mm(40)], numbers: ["Door Weight Capacity": 176], cost: 34.00,
                 model: "SCM-80", description: "Soft-close unit for sliding doors to 80 kg (176 lb)")
        return g.build()
    }

    static func slidingDamper() -> ComponentDefinition {
        var g = sliding("Sliding Door Damper", "Stops & Dampers", "Compact spring buffer damper at the end of a track; cushions the door without pulling it shut.", finish: .greyPlastic, full: false)
        g.b.material("Piston Material", .stainless)
        g.b.tags("damper", "buffer", "cushion", "sliding")
        g.b.aliases("sliding door dampers", "door buffer", "track damper", "cushion stop", "end damper")
        g.b.length("Body Length", mm(60)); g.b.length("Body Diameter", mm(12)); g.b.length("Stroke", mm(15)); g.b.length("Track Height", mm(30))
        g.cylinder("Body", along: 0, center: (CX.zero, "-Track Height / 2"), radius: "Body Diameter / 2", range: (CX.zero, "Body Length"), segments: 18)
        g.box("Clip", a: ("Body Length * 0.6", "Body Length"), b: ("-Body Diameter * 0.7", "Body Diameter * 0.7"), c: ("-Track Height / 2", "-0.002 m"))
        g.using("Piston Material")
        g.cylinder("Piston", along: 0, center: (CX.zero, "-Track Height / 2"), radius: "Body Diameter * 0.2", range: ("-Stroke", CX.zero), segments: 12)
        g.revolve("Tip", along: 0, center: (CX.zero, "-Track Height / 2"), profile: [(CX.zero, "-Stroke - 0.004 m"), ("Body Diameter * 0.35", "-Stroke - 0.003 m"), ("Body Diameter * 0.38", "-Stroke"), (CX.zero, "-Stroke")])
        g.using(nil)
        g.b.symbol(.face, [.coarse], .rect(("-Stroke", "-Body Diameter / 2"), ("Body Length", "Body Diameter / 2")))
        g.b.type("Sliding Door Damper - Standard", [:], cost: 6.50, model: "SDD-60", description: "Sliding door buffer damper, 15 mm stroke", isDefault: true)
        g.b.type("Sliding Door Damper - Long Stroke", ["Body Length": mm(80), "Stroke": mm(25)], cost: 7.95, model: "SDD-80", description: "Sliding door buffer damper, 25 mm (1\") stroke")
        return g.build()
    }

    static func slidingDoorLockHook() -> ComponentDefinition {
        var g = lock("Sliding Door Lock - Hook", "Sliding Door Locks", "Mortise hook lock for wooden sliding doors: a hook from the door's edge catches a keeper on the carcass.",
                     category: .slidingDoors)
        g.b.material("Body Material", .zinc)
        g.b.tags("sliding door lock", "hook lock", "mortise", "keyed", "pocket door")
        g.b.aliases("sliding door locks", "hook lock", "sliding door hook bolt", "pocket door lock", "slider lock")
        g.b.length("Diameter", mm(16)); g.b.length("Head Diameter", mm(20)); g.b.length("Cylinder Length", mm(20), formula: "Front Thickness + 0.002 m")
        g.b.length("Backset", mm(25)); g.b.length("Body Height", mm(60)); g.b.length("Hook Throw", mm(12))
        g.b.host([.door], faces: [.front], align: .inside, alignments: [.inside], offsetX: mm(25))
        g.b.requires(.hostThickness(min: CX.mm(18), max: CX.mm(25)))
        cylinderHole(&g)
        keyCylinder(&g)
        g.b.pocket("Lock mortise", x: "Backset / 2", y: CX.zero, width: "Backset + 0.005 m", height: "Body Height", depth: "Front Thickness - 0.006 m")
        let back = "-Front Thickness"
        g.using("Body Material")
        g.box("Lock Case", a: (CX.mm(-10), "Backset - 0.003 m"), b: ("-Body Height / 2", "Body Height / 2"), c: ("\(back) + 0.003 m", CX.mm(-3)))
        g.using(finish)
        g.box("Forend", a: ("Backset - 0.003 m", "Backset"), b: ("-Body Height / 2 - 0.01 m", "Body Height / 2 + 0.01 m"), c: ("\(back) + 0.002 m", CX.mm(-2)))
        g.prism("Hook", along: 2, profile: [("Backset", CX.mm(-4)), ("Backset + Hook Throw", CX.mm(-4)), ("Backset + Hook Throw", CX.mm(6)), ("Backset + Hook Throw - 0.004 m", CX.mm(6)),
                                            ("Backset + Hook Throw - 0.004 m", CX.zero), ("Backset", CX.zero)], range: ("\(back) / 2 - 0.002 m", "\(back) / 2 + 0.002 m"))
        g.b.symbol(.face, [.coarse], dashed: true, .rect((CX.mm(-10), "-Body Height / 2"), ("Backset", "Body Height / 2")))
        g.b.type("Sliding Door Lock - Hook 25 mm Backset", [:], cost: 16.50, model: "SDL-H25", description: "Mortise hook lock for sliding doors, 25 mm (1\") backset", isDefault: true)
        g.b.type("Sliding Door Lock - Hook 40 mm Backset", ["Backset": mm(40), "Body Height": mm(75)], cost: 18.75, model: "SDL-H40", description: "Mortise hook lock, 40 mm (1 9/16\") backset")
        return g.build()
    }

    static func slidingDoorHandle() -> ComponentDefinition {
        var g = faced("Sliding Door Handle", .slidingDoors, "Sliding Door Handles", "Long oval flush pull let into a sliding door, so the doors can pass each other.")
        g.b.material(finish, .satinNickel)
        g.b.tags("sliding door handle", "flush pull", "oval", "recessed", "vertical")
        g.b.aliases("sliding door handles", "sliding door pull", "oval flush pull", "long flush pull", "slider handle", "closet door pull")
        g.b.length("Length", mm(150)); g.b.length("Width", mm(30)); g.b.length("Depth", mm(10)); g.b.length("Rim", mm(3)); g.b.length("Wall", mm(0.8), group: .manufacturing)
        g.b.host([.door, .glass], faces: [.front, .back], align: .inside, alignments: [.inside, .center], offsetX: inch(1.25), vertical: true)
        g.b.pocket("Pull recess", width: "Width - 2 * Rim", height: "Length - 2 * Rim", depth: "Depth")
        // A stadium along b: straight walls and rims, half-round ends (partial revolves about c).
        let R = "Width / 2", Ri = "Width / 2 - Rim", s = "Length / 2 - Width / 2"
        let section: [(String, String)] = [("\(Ri) - Wall", "-Depth"), (Ri, "-Depth"), (Ri, CX.zero), (R, CX.zero), (R, CX.mm(0.6)), ("\(R) - 0.0008 m", CX.mm(1)), ("\(Ri) - Wall", CX.mm(1))]
        g.revolve("Top End", along: 2, center: (CX.zero, s), profile: section, from: 0, to: 180)
        g.revolve("Bottom End", along: 2, center: (CX.zero, "-(\(s))"), profile: section, from: 180, to: 360)
        for (n, x) in [("Left", "-(\(R))"), ("Right", Ri)] {
            g.box("\(n) Rim", a: (x, n == "Left" ? "-(\(Ri))" : R), b: ("-(\(s))", s), c: (CX.zero, CX.mm(1)))
            g.box("\(n) Wall", a: n == "Left" ? ("-(\(Ri))", "-(\(Ri)) + Wall") : ("\(Ri) - Wall", Ri), b: ("-(\(s))", s), c: ("-Depth", CX.zero))
        }
        g.box("Bottom", a: ("-(\(Ri))", Ri), b: ("-(\(s))", s), c: ("-Depth", "-Depth + Wall"))
        g.revolve("Bottom Top End", along: 2, center: (CX.zero, s), profile: [(CX.zero, "-Depth"), (Ri, "-Depth"), (Ri, "-Depth + Wall"), (CX.zero, "-Depth + Wall")], from: 0, to: 180)
        g.revolve("Bottom Bottom End", along: 2, center: (CX.zero, "-(\(s))"), profile: [(CX.zero, "-Depth"), (Ri, "-Depth"), (Ri, "-Depth + Wall"), (CX.zero, "-Depth + Wall")], from: 180, to: 360)
        g.b.symbol(.face, [.coarse], .rect(("-(\(R))", "-Length / 2"), (R, "Length / 2")))
        for (l, cost) in [(150.0, 8.50), (200, 10.25), (300, 13.50)] {
            g.b.type("Sliding Door Handle - \(Int(l)) mm", ["Length": mm(l), "Width": mm(l > 250 ? 35 : 30)], cost: cost, model: "SDH-\(Int(l))",
                     description: "Oval flush pull, \(Int(l)) mm (\(TradeA.inchWord(l))) long, satin nickel", isDefault: l == 150)
        }
        return g.build()
    }

    static func slidingFrameProfile() -> ComponentDefinition {
        var g = faced("Sliding Door Frame Profile", .slidingDoors, "Frame Profiles", "Aluminium frame for a sliding door panel: handle stiles, top and bottom rails with a panel groove.")
        g.b.material(finish, .aluminum)
        g.b.material("Panel Material", melamine)
        g.b.tags("frame profile", "aluminium frame", "wardrobe door", "handle profile", "sliding door")
        g.b.aliases("sliding door frame profiles", "door frame profile", "aluminum door frame", "wardrobe frame profile", "handle stile")
        g.b.length("Door Width", inch(36), instance: true); g.b.length("Door Height", inch(84), instance: true)
        g.b.length("Stile Width", mm(45)); g.b.length("Rail Height", mm(40)); g.b.length("Profile Depth", mm(30)); g.b.length("Panel Thickness", mm(10))
        g.b.flag("With Panel", true, instance: true, group: .constraints)
        g.b.host([.door], faces: [.front], align: .center)
        // Origin: the door's centre at its face; the frame sits behind it (c negative), the stiles rounded at the front.
        let w = "Door Width / 2", h = "Door Height / 2", d = "-Profile Depth"
        for (n, x0, x1) in [("Left Stile", "-(\(w))", "-(\(w)) + Stile Width"), ("Right Stile", "\(w) - Stile Width", w)] {
            g.prism(n, along: 1, profile: PtsA.rounded(("(\(x0) + \(x1)) / 2", "-Profile Depth / 2"), "Stile Width", "Profile Depth", "Stile Width * 0.2"), range: ("-(\(h))", h))
        }
        g.box("Top Rail", a: ("-(\(w)) + Stile Width", "\(w) - Stile Width"), b: ("\(h) - Rail Height", h), c: ("\(d) * 0.8", "\(d) * 0.2"))
        g.box("Bottom Rail", a: ("-(\(w)) + Stile Width", "\(w) - Stile Width"), b: ("-(\(h))", "-(\(h)) + Rail Height"), c: ("\(d) * 0.8", "\(d) * 0.2"))
        g.using("Panel Material")
        g.visibility = "With Panel"
        g.box("Panel", a: ("-(\(w)) + Stile Width - 0.006 m", "\(w) - Stile Width + 0.006 m"), b: ("-(\(h)) + Rail Height - 0.006 m", "\(h) - Rail Height + 0.006 m"),
              c: ("\(d) / 2 - Panel Thickness / 2", "\(d) / 2 + Panel Thickness / 2"))
        g.visibility = nil
        g.using(nil)
        g.b.symbol(.face, [.coarse], .rect(("-(\(w))", "-(\(h))"), (w, h)), .rect(("-(\(w)) + Stile Width", "-(\(h)) + Rail Height"), ("\(w) - Stile Width", "\(h) - Rail Height")))
        g.b.type("Sliding Door Frame Profile - Slim 20 mm", ["Stile Width": mm(20), "Rail Height": mm(30), "Profile Depth": mm(20), "Panel Thickness": mm(6)], cost: 64.00, model: "SFP-20",
                 description: "Slim aluminium door frame, 20 mm (13/16\") stiles, 6 mm panel, per door")
        g.b.type("Sliding Door Frame Profile - Wide 45 mm", [:], cost: 84.00, model: "SFP-45", description: "Aluminium door frame, 45 mm (1 3/4\") handle stiles, 10 mm panel, per door",
                 isDefault: true)
        return g.build()
    }

    // MARK: Barn door

    static func barnDoorTrack() -> ComponentDefinition {
        var g = faced("Barn Door Track", .slidingDoors, "Barn Door Hardware", "Exposed flat-bar rail on standoffs with two strap hangers and wheels, for barn-style doors.")
        g.b.material(finish, .matteBlack)
        g.b.material("Wheel Material", .matteBlack)
        g.b.tags("barn door", "rail", "exposed", "rustic", "flat track")
        g.b.aliases("barn door tracks", "barn door hardware", "mini barn door track", "cabinet barn door", "sliding barn door kit", "flat track")
        g.b.length("Length", inch(48), instance: true); g.b.length("Rail Height", mm(40)); g.b.length("Rail Thickness", mm(6)); g.b.length("Standoff", mm(30))
        g.b.length("Wheel Diameter", mm(60)); g.b.length("Strap Drop", mm(120)); g.b.length("Door Width", inch(24), instance: true); g.b.length("Door Thickness", inch(0.75))
        g.b.host([.sidePanel, .top, .back, .wall], faces: [.front, .outside], align: .full)
        for x in ["-Length / 2 + 0.05 m", "-Length / 6", "Length / 6", "Length / 2 - 0.05 m"] { g.b.drill("Standoff bolt", x: x, y: "Rail Height / 2", diameter: CX.mm(8), depth: CX.mm(40)) }
        // Origin: the face at the rail's bottom edge, the rail Standoff out from it (c), the door hanging in front.
        let rc = ("Standoff", "Standoff + Rail Thickness")
        g.box("Rail", a: ("-Length / 2", "Length / 2"), b: (CX.zero, "Rail Height"), c: rc)
        for (k, f) in [-0.47, -0.16, 0.16, 0.47].enumerated() {
            g.cylinder("Standoff \(k + 1)", along: 2, center: ("Length * \(LX.num(f))", "Rail Height / 2"), radius: CX.mm(10), range: (CX.zero, "Standoff"), segments: 18)
            let saved = g.levels
            g.levels = [.fine]
            g.cylinder("Bolt Head \(k + 1)", along: 2, center: ("Length * \(LX.num(f))", "Rail Height / 2"), radius: CX.mm(7), range: ("Standoff + Rail Thickness", "Standoff + Rail Thickness + 0.004 m"), segments: 6)
            g.levels = saved
        }
        for (k, f) in ["-Length / 2 + 0.006 m", "Length / 2 - 0.026 m"].enumerated() {
            g.box("Stop \(k + 1)", a: (f, "\(f) + 0.02 m"), b: ("Rail Height", "Rail Height + 0.018 m"), c: rc)
        }
        let wc = "Rail Height + Wheel Diameter / 2", sc = "Standoff + Rail Thickness + 0.004 m"
        for (n, x) in [("Left", "-Length / 2 + 0.08 m"), ("Right", "-Length / 2 + Door Width - 0.08 m")] {
            g.using("Wheel Material")
            g.revolve("\(n) Wheel", along: 2, center: (x, wc), profile: [(CX.mm(4), "Standoff - 0.004 m"), ("Wheel Diameter / 2", "Standoff - 0.004 m"), ("Wheel Diameter / 2 - 0.003 m", "Standoff + Rail Thickness / 2"),
                                                                       ("Wheel Diameter / 2", "Standoff + Rail Thickness + 0.004 m"), (CX.mm(4), "Standoff + Rail Thickness + 0.004 m")])
            g.using(finish)
            g.box("\(n) Strap", a: ("\(x) - 0.02 m", "\(x) + 0.02 m"), b: ("-Strap Drop", wc), c: (sc, "\(sc) + 0.005 m"))
            g.cylinder("\(n) Axle", along: 2, center: (x, wc), radius: CX.mm(6), range: ("Standoff - 0.006 m", "\(sc) + 0.007 m"), segments: 16)
            g.cylinder("\(n) Door Bolt", along: 2, center: (x, "-Strap Drop + 0.02 m"), radius: CX.mm(5), range: (sc, "\(sc) + Door Thickness + 0.012 m"), segments: 12)
        }
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", CX.zero), ("Length / 2", "Rail Height")))
        g.b.symbol(.top, [.coarse], .rect(("-Length / 2", "Standoff"), ("Length / 2", "Standoff + Rail Thickness")))
        g.b.type("Barn Door Track - 48\"", [:], cost: 69.00, model: "BDT-48", description: "Mini barn door kit, 48\" (1219 mm) rail, two hangers, black", isDefault: true)
        g.b.type("Barn Door Track - 72\"", ["Length": inch(72), "Door Width": inch(36), "Wheel Diameter": mm(75), "Strap Drop": mm(150)], cost: 99.00, model: "BDT-72",
                 description: "Barn door kit, 72\" (1829 mm) rail, two hangers, black")
        return g.build()
    }
}
