import Foundation
import ArcusGeometry

// COMPA: 03 Hinges & Door Mechanisms (20). Front hinges use FM5's hinge frame and parameter names (a from the hinge
// edge into the front, b along the edge, c behind the front; the front is a ∈ [0, width], c ∈ [-Front Thickness, 0];
// the carcass side's inside face is at a = Side Offset, its front edge at c = Front Edge), so fronts place them in
// sets by height (2 up to 40", 3 up to 60", 4 up to 80", then 5) and bore their cups. FM5's frameless concealed hinge,
// butt and piano hinges are upgraded in place. Pivot and lift-up hinges are face-based.

extension GroupA {
    static var hinges: [ComponentDefinition] {
        [concealedHinge(), softCloseHinge(), clipOnHinge(), insetHinge(), fullOverlayHinge(), halfOverlayHinge(), buttHinge(), pianoHinge(), pivotHinge(),
         glassDoorHinge(), cornerCabinetHinge(), biFoldHinge(), liftUpHinge(), flapHinge(), hydraulicHinge(), selfClosingHinge(), continuousHinge(),
         detachableHinge(), decorativeHinge(), hiddenBarrelHinge()]
    }

    /// A front hinge in FM5's hinge frame, hosted on fronts' inside faces in sets by height.
    static func hingeStarter(_ name: String, _ sub: String, _ description: String, finish f: ComponentFinish = .steel, upgrading fm5: String? = nil,
                             count: Bool = true) -> ShapeA {
        var b = starter(name, .hinges, sub, description, frame: .legacyHinge, upgrading: fm5)
        setFinish(&b, f)
        ShapeA.hingeFlags(&b)
        b.length("Side Offset", mm(17.5), instance: true, group: .placement)
        b.length("Front Edge", 0, instance: true, group: .placement)
        b.length("Front Thickness", inch(0.75), instance: true, group: .placement)
        b.hardwareKind(.hinge)
        b.host([.door, .flap, .lid], faces: [.inside], align: .left, alignments: [.left, .right, .top, .bottom], count: count ? .hinges : nil)
        b.requires(.hostThickness(min: CX.inch(0.5), max: CX.inch(1.125)))
        b.tags("hinge", "door", "hardware")
        return ShapeA(b, frames: FrameA.hinge)
    }

    /// The cup, plate and screw parameters FM5's machining reads.
    static func cupParameters(_ b: inout ComponentBuilder, cup: Double = 35, depth: Double = 13, offset: Double = 22.5) {
        b.length("Cup Diameter", mm(cup), group: .manufacturing); b.length("Cup Depth", mm(depth), group: .manufacturing)
        b.length("Cup Offset", mm(offset), group: .manufacturing); b.length("Cup Screw Spacing", mm(45), group: .manufacturing)
        b.length("Plate Setback", mm(37), group: .manufacturing); b.length("Plate Hole Spacing", mm(32), group: .manufacturing)
        b.length("Screw Hole Diameter", mm(5), group: .manufacturing); b.length("Screw Hole Depth", mm(13), group: .manufacturing)
        b.length("Plate Thickness", mm(3), group: .manufacturing); b.length("Arm Thickness", mm(11), group: .manufacturing)
        b.length("Arm Width", mm(14), group: .manufacturing)
        b.angle("Opening Angle", 110)
        b.length("Overlay", mm(16))
    }

    /// The cup bore and its screws in the front, the plate's screws in the carcass side.
    static func cupMounting(_ b: inout ComponentBuilder, plate: Bool = true) {
        b.drill("Hinge cup", x: "Cup Offset", y: CX.zero, diameter: "Cup Diameter", depth: "Cup Depth")
        for s in ["-", ""] {
            b.drill("Cup screw", x: "Cup Offset + 0.0095 m", y: "\(s)Cup Screw Spacing / 2", diameter: CX.mm(2.5), depth: CX.mm(10))
            if plate { b.drill("Hinge plate screw", x: "Plate Setback", y: "\(s)Plate Hole Spacing / 2", diameter: "Screw Hole Diameter", depth: "Screw Hole Depth", target: .counterpart) }
        }
    }

    /// What a concealed hinge adds to the basic cup, arm and plate.
    struct ConcealedStyle {
        var damper = false, hydraulic = false, clip = false, spring = false, glass = false, wedge = false, straightArm = false
    }

    /// A concealed (cup) hinge: the cup bored in the front, its flange, the link boss, the arm along the carcass side
    /// and the mounting plate, with screws and adjusters at Fine.
    static func concealed(_ g: inout ShapeA, _ st: ConcealedStyle = ConcealedStyle()) {
        let R = "Cup Diameter / 2", co = "Cup Offset"
        let a0 = "Side Offset + Plate Thickness", a1 = "Side Offset + Plate Thickness + Arm Thickness"
        let pc = "Front Edge + Plate Setback", tail = "Front Edge + Plate Setback + 0.022 m", aw = "Arm Width / 2"
        if st.glass {
            // A glass hinge clamps through a bore: a cap on the glass's outer face, a sleeve in the bore.
            g.revolve("Glass Cap", along: 2, center: (co, CX.zero), profile: PtsA.turned("\(R) + 0.004 m", CX.mm(3.5), base: "-Front Thickness - 0.0035 m",
                                                                                         [(0, 0), (0.92, 0), (1, 0.3), (1, 1), (0, 1)]))
            g.cylinder("Sleeve", along: 2, center: (co, CX.zero), radius: R, range: ("-Front Thickness", CX.zero))
        } else {
            g.revolve("Cup", along: 2, center: (co, CX.zero), profile: [(CX.zero, "-Cup Depth"), ("\(R) - 0.0012 m", "-Cup Depth"), (R, "-Cup Depth + 0.0012 m"), (R, CX.zero), (CX.zero, CX.zero)])
        }
        // The cup's rim and the two screw ears either side of it.
        g.cylinder("Flange", along: 2, center: (co, CX.zero), radius: "\(R) + 0.0015 m", range: (CX.zero, CX.mm(1.2)), segments: 32)
        g.prism("Flange Ears", along: 2, profile: PtsA.rounded(("\(co) + 0.0095 m", CX.zero), CX.mm(13), "Cup Screw Spacing + 0.012 m", CX.mm(6)), range: (CX.zero, CX.mm(1.2)))
        // The link boss over the cup, stepping out to the arm.
        g.prism("Link Boss", along: 1, profile: PtsA.rounded(("(min(\(a0), \(co) - 0.012 m) + \(co) + 0.004 m) / 2", CX.mm(4.6)),
                                                             "\(co) + 0.004 m - min(\(a0), \(co) - 0.012 m)", CX.mm(6.8), CX.mm(2.5)), range: ("-(\(aw)) - 0.002 m", "\(aw) + 0.002 m"))
        if st.straightArm {
            g.prism("Arm", along: 1, profile: PtsA.rounded(("(\(a0) + \(a1)) / 2", "(0.004 m + \(tail)) / 2"), "Arm Thickness * 0.6", "\(tail) - 0.004 m", CX.mm(2)),
                    range: ("-(\(aw))", aw))
        } else {
            g.prism("Arm", along: 1, profile: PtsA.rounded(("(\(a0) + \(a1)) / 2", "(0.004 m + \(tail)) / 2"), "Arm Thickness", "\(tail) - 0.004 m", CX.mm(3)), range: ("-(\(aw))", aw))
        }
        if st.wedge {
            g.prism("Angle Wedge", along: 1, profile: [("Side Offset", "\(pc) - 0.022 m"), ("Side Offset", "\(pc) + 0.022 m"), ("Side Offset + Wedge Thickness", "\(pc) + 0.022 m"),
                                                       ("Side Offset + 0.002 m", "\(pc) - 0.022 m")], range: ("-(\(aw)) - 0.004 m", "\(aw) + 0.004 m"))
        }
        // The plate: a cross of a screw bar and the arm's seat.
        g.prism("Plate", along: 0, profile: PtsA.rounded((CX.zero, pc), "Plate Hole Spacing + 0.012 m", CX.mm(14), CX.mm(5)), range: ("Side Offset", "Side Offset + Plate Thickness"))
        g.prism("Plate Seat", along: 0, profile: PtsA.rounded((CX.zero, pc), "Arm Width + 0.006 m", CX.mm(40), CX.mm(3)), range: ("Side Offset", "Side Offset + Plate Thickness"))
        if st.damper || st.hydraulic {
            let r = st.hydraulic ? CX.mm(5.5) : CX.mm(4.5)
            g.cylinder(st.hydraulic ? "Hydraulic Damper" : "Damper", along: 2, center: ("\(a1) + \(r)", CX.zero), radius: r, range: (CX.mm(6), st.hydraulic ? "0.042 m" : "0.034 m"), segments: 18)
            if st.hydraulic { g.cylinder("Damper Cap", along: 2, center: ("\(a1) + \(r)", CX.zero), radius: "\(r) + 0.0008 m", range: (CX.mm(36), CX.mm(42)), segments: 18) }
        }
        if st.spring { g.cylinder("Spring Housing", along: 1, center: ("\(co) - 0.006 m", CX.mm(7)), radius: CX.mm(4.5), range: ("-(\(aw)) - 0.002 m", "\(aw) + 0.002 m"), segments: 16) }
        if st.clip {
            g.prism("Clip Lever", along: 1, profile: [(a1, "\(tail) - 0.014 m"), (a1, tail), ("\(a1) + 0.0035 m", tail), ("\(a1) + 0.0015 m", "\(tail) - 0.014 m")], range: ("-(\(aw))", aw))
        }
        let saved = g.levels
        g.levels = [.fine]
        for s in ["-", ""] {
            g.cylinder("Cup Screw", along: 2, center: ("\(co) + 0.0095 m", "\(s)Cup Screw Spacing / 2"), radius: CX.mm(3.5), range: (CX.mm(1.2), CX.mm(2.2)), segments: 12)
            g.cylinder("Plate Screw", along: 0, center: ("\(s)Plate Hole Spacing / 2", pc), radius: CX.mm(4), range: ("Side Offset + Plate Thickness", "Side Offset + Plate Thickness + 0.001 m"), segments: 12)
        }
        g.cylinder("Depth Adjuster", along: 0, center: (CX.zero, "\(pc) - 0.008 m"), radius: CX.mm(3), range: (a1, "\(a1) + 0.001 m"), segments: 12)
        g.cylinder("Side Adjuster", along: 0, center: (CX.zero, CX.mm(12)), radius: CX.mm(2.5), range: (a1, "\(a1) + 0.001 m"), segments: 12)
        g.levels = saved
        g.b.symbol(.top, [.coarse], .rect(("\(co) - \(R)", "-Cup Depth"), ("\(co) + \(R)", CX.zero)), .rect(("Side Offset", CX.zero), (a1, tail)))
        g.b.symbol(.face, [.coarse], .circle((co, CX.zero), R))
    }

    /// The common concealed-hinge data: cup parameters, mounting, rules and tags.
    static func concealedStarter(_ name: String, _ sub: String, _ description: String, upgrading fm5: String? = nil, cup: Double = 35, depth: Double = 13) -> ShapeA {
        var g = hingeStarter(name, sub, description, finish: .steel, upgrading: fm5)
        cupParameters(&g.b, cup: cup, depth: depth)
        cupMounting(&g.b)
        g.b.tags("concealed", "cup", "euro", "35 mm")
        g.b.requires(.maxHostWeight("26 * 2.2 / 2"))
        return g
    }

    static let edgeFlags: [String: Bool] = ["Top Edge": false, "Bottom Edge": false, "Back Edge": false]

    // MARK: Concealed hinges

    static func concealedHinge() -> ComponentDefinition {
        var g = concealedStarter(F.concealedHinge, "Concealed Hinges", "35 mm concealed cup hinge with a clip-on plate for frameless cabinets.", upgrading: F.concealedHinge)
        g.b.aliases("concealed hinge", "euro hinge", "cup hinge", "hidden hinge", "cabinet hinge", "35mm hinge", "1 3/8\" cup hinge", "frameless hinge")
        g.b.requires(.overlay(["Full Overlay", "Half Overlay", "Inset"]))
        concealed(&g, ConcealedStyle(clip: true))
        for (n, ov, cost, model, d, deg) in [("Full Overlay 110°", 16.0, 3.50, "CH-35-FO110", "full overlay, 110°, soft close", 110.0),
                                             ("Half Overlay 110°", 8, 3.50, "CH-35-HO110", "half overlay (cranked), 110°", 110),
                                             ("Inset 110°", 0, 3.75, "CH-35-IN110", "inset (cranked), 110°", 110),
                                             ("Full Overlay 170°", 16, 6.25, "CH-35-FO170", "full overlay, 170° wide angle", 170)] {
            g.b.type(n, ["Overlay": mm(ov), "Opening Angle": deg * .pi / 180], flags: edgeFlags, cost: cost, model: model, description: "Frameless hinge, \(d)", isDefault: n.hasPrefix("Full Overlay 110"))
        }
        return g.build()
    }

    static func softCloseHinge() -> ComponentDefinition {
        var g = concealedStarter("Soft-Close Hinge", "Concealed Hinges", "Concealed hinge with a built-in damper that closes the door gently.")
        g.b.tags("soft close", "damper", "quiet", "blum style")
        g.b.aliases("soft close hinge", "slow close hinge", "damped hinge", "silent hinge", "self-closing soft hinge")
        g.b.choice("Closing Behavior", ["Soft Close", "Soft Close, Adjustable"], "Soft Close")
        concealed(&g, ConcealedStyle(damper: true, clip: true))
        g.b.type("Soft-Close Hinge - Full Overlay 110°", [:], flags: edgeFlags, cost: 4.75, model: "SCH-FO110", description: "Soft-close concealed hinge, full overlay, 110°", isDefault: true)
        g.b.type("Soft-Close Hinge - Half Overlay 110°", ["Overlay": mm(8)], flags: edgeFlags, cost: 4.75, model: "SCH-HO110", description: "Soft-close concealed hinge, half overlay, 110°")
        g.b.type("Soft-Close Hinge - Full Overlay 155°", ["Opening Angle": 155 * .pi / 180], flags: edgeFlags, texts: ["Closing Behavior": "Soft Close, Adjustable"], cost: 7.95,
                 model: "SCH-FO155", description: "Soft-close concealed hinge, full overlay, 155°, adjustable damping")
        return g.build()
    }

    static func clipOnHinge() -> ComponentDefinition {
        var g = concealedStarter("Clip-On Hinge", "Concealed Hinges", "Concealed hinge that clips onto its plate without tools.")
        g.b.tags("clip on", "tool free", "quick release")
        g.b.aliases("clip hinge", "clip-top hinge", "quick release hinge", "tool-free hinge", "26 mm hinge", "40 mm hinge")
        concealed(&g, ConcealedStyle(clip: true))
        g.b.type("Clip-On Hinge - 35 mm Cup", [:], flags: edgeFlags, cost: 3.25, model: "COH-35", description: "Clip-on concealed hinge, 35 mm (1 3/8\") cup", isDefault: true)
        g.b.type("Clip-On Hinge - 26 mm Cup", ["Cup Diameter": mm(26), "Cup Depth": mm(11), "Cup Offset": mm(18), "Cup Screw Spacing": mm(36), "Overlay": mm(13), "Arm Thickness": mm(9),
                                               "Arm Width": mm(12)], flags: edgeFlags, cost: 3.10, model: "COH-26", description: "Clip-on concealed hinge, 26 mm (1\") cup, for thin doors")
        g.b.type("Clip-On Hinge - 40 mm Cup", ["Cup Diameter": mm(40), "Cup Depth": mm(13.5), "Cup Offset": mm(25), "Cup Screw Spacing": mm(52), "Overlay": mm(18)], flags: edgeFlags,
                 cost: 4.25, model: "COH-40", description: "Clip-on concealed hinge, 40 mm (1 9/16\") cup, for thick doors")
        return g.build()
    }

    static func insetHinge() -> ComponentDefinition {
        var g = concealedStarter("Inset Hinge", "Concealed Hinges", "Cranked concealed hinge for doors set inside the carcass.")
        g.b.tags("inset", "cranked", "flush door")
        g.b.aliases("inset hinge", "flush hinge", "cranked hinge", "inset cup hinge", "inside hinge")
        g.b.length("Offset", mm(2))
        g.b.requires(.overlay(["Inset"]))
        g.b.preset("Inset door", type: "Inset Hinge - 110°", values: ["Side Offset": .double(-mm(2)), "Front Edge": .double(-inch(0.75))])
        concealed(&g, ConcealedStyle(clip: true))
        g.b.type("Inset Hinge - 110°", ["Overlay": 0], flags: edgeFlags, cost: 3.75, model: "IH-110", description: "Inset concealed hinge, 110°", isDefault: true)
        g.b.type("Inset Hinge - 95° Thick Door", ["Overlay": 0, "Opening Angle": 95 * .pi / 180, "Cup Depth": mm(14)], flags: edgeFlags, cost: 4.95, model: "IH-95T",
                 description: "Inset concealed hinge, 95°, for doors to 1 1/8\"")
        return g.build()
    }

    static func fullOverlayHinge() -> ComponentDefinition {
        var g = concealedStarter("Full Overlay Hinge", "Concealed Hinges", "Straight-arm concealed hinge: the door covers the carcass side.")
        g.b.tags("full overlay", "straight arm")
        g.b.aliases("full overlay hinge", "straight arm hinge", "overlay hinge", "0 crank hinge")
        g.b.requires(.overlay(["Full Overlay"]))
        concealed(&g, ConcealedStyle(clip: true))
        g.b.type("Full Overlay Hinge - 16 mm", ["Overlay": mm(16)], flags: edgeFlags, cost: 3.25, model: "FOH-16", description: "Full overlay hinge, 16 mm (5/8\") overlay", isDefault: true)
        g.b.type("Full Overlay Hinge - 19 mm", ["Overlay": mm(19)], flags: edgeFlags, cost: 3.25, model: "FOH-19", description: "Full overlay hinge, 19 mm (3/4\") overlay")
        return g.build()
    }

    static func halfOverlayHinge() -> ComponentDefinition {
        var g = concealedStarter("Half Overlay Hinge", "Concealed Hinges", "Cranked concealed hinge: two doors share one partition.")
        g.b.tags("half overlay", "cranked", "partition")
        g.b.aliases("half overlay hinge", "half crank hinge", "partition hinge", "9.5 mm crank")
        g.b.requires(.overlay(["Half Overlay"]))
        concealed(&g, ConcealedStyle(clip: true))
        g.b.type("Half Overlay Hinge - 8 mm", ["Overlay": mm(8)], flags: edgeFlags, cost: 3.40, model: "HOH-8", description: "Half overlay hinge, 8 mm (5/16\") overlay", isDefault: true)
        g.b.type("Half Overlay Hinge - 9.5 mm", ["Overlay": mm(9.5)], flags: edgeFlags, cost: 3.40, model: "HOH-95", description: "Half overlay hinge, 9.5 mm (3/8\") overlay")
        return g.build()
    }

    static func hydraulicHinge() -> ComponentDefinition {
        var g = concealedStarter("Hydraulic Hinge", "Concealed Hinges", "Concealed hinge with an external hydraulic cylinder; the damping is adjustable.")
        g.b.tags("hydraulic", "damper", "soft close", "adjustable")
        g.b.aliases("hydraulic soft close hinge", "damper hinge", "hydraulic damping hinge", "adjustable soft close")
        g.b.choice("Damping Strength", ["Light", "Medium", "Strong"], "Medium", instance: true, group: .data)
        concealed(&g, ConcealedStyle(hydraulic: true, clip: true))
        g.b.type("Hydraulic Hinge - Full Overlay", [:], flags: edgeFlags, cost: 5.50, model: "HYH-FO", description: "Hydraulic concealed hinge, full overlay, adjustable damping", isDefault: true)
        g.b.type("Hydraulic Hinge - Inset", ["Overlay": 0], flags: edgeFlags, cost: 5.95, model: "HYH-IN", description: "Hydraulic concealed hinge, inset")
        return g.build()
    }

    static func selfClosingHinge() -> ComponentDefinition {
        var g = concealedStarter("Self-Closing Hinge", "Concealed Hinges", "Spring concealed hinge that pulls the door shut over the last 30°.")
        g.b.tags("self closing", "spring", "auto close")
        g.b.aliases("self close hinge", "spring hinge", "auto closing hinge", "sprung hinge")
        g.b.number("Closing Force", 8, unit: "N", group: .data)
        concealed(&g, ConcealedStyle(clip: true, spring: true))
        g.b.type("Self-Closing Hinge - Full Overlay", [:], flags: edgeFlags, cost: 2.95, model: "SLH-FO", description: "Self-closing concealed hinge, full overlay", isDefault: true)
        g.b.type("Self-Closing Hinge - Half Overlay", ["Overlay": mm(8)], flags: edgeFlags, cost: 2.95, model: "SLH-HO", description: "Self-closing concealed hinge, half overlay")
        return g.build()
    }

    static func glassDoorHinge() -> ComponentDefinition {
        var g = concealedStarter("Glass Door Hinge", "Glass Door Hinges", "Concealed hinge for frameless glass doors: a cap clamps it through a 26 mm hole in the glass.", cup: 26, depth: 5)
        g.b.material("Cap Material", .chrome)
        g.b.tags("glass", "glass door", "showcase", "frameless glass")
        g.b.aliases("glass hinge", "glass door hinge", "showcase hinge", "glass cabinet hinge", "26 mm glass hinge")
        g.b.length("Glass Thickness", mm(5))
        g.b.host([.glass, .door], faces: [.inside], align: .left, alignments: [.left, .right], count: .hinges)
        g.b.requires(.hostThickness(min: CX.mm(4), max: CX.mm(6)))
        g.b.requires(.note("The glass is drilled 26 mm (1\") by the glass supplier."))
        concealed(&g, ConcealedStyle(clip: true, glass: true))
        g.b.type("Glass Door Hinge - 4-6 mm Glass", ["Cup Offset": mm(19), "Cup Screw Spacing": mm(32)], flags: edgeFlags, cost: 8.50, model: "GDH-5",
                 description: "Glass door hinge, 26 mm hole, 4-6 mm (3/16\"-1/4\") glass, full overlay", isDefault: true)
        g.b.type("Glass Door Hinge - Inset", ["Cup Offset": mm(19), "Cup Screw Spacing": mm(32), "Overlay": 0], flags: edgeFlags, cost: 9.25, model: "GDH-5I",
                 description: "Glass door hinge, inset")
        return g.build()
    }

    static func cornerCabinetHinge() -> ComponentDefinition {
        var g = concealedStarter("Corner Cabinet Hinge", "Concealed Hinges", "Concealed hinge on an angled plate for diagonal and blind-corner cabinets.")
        g.b.tags("corner", "angled", "diagonal", "blind corner")
        g.b.aliases("angle hinge", "corner hinge", "+30 hinge", "+45 hinge", "diagonal corner hinge", "angled plate hinge")
        g.b.length("Wedge Thickness", mm(12))
        concealed(&g, ConcealedStyle(clip: true, wedge: true))
        g.b.type("Corner Cabinet Hinge - +30°", ["Opening Angle": 110 * .pi / 180, "Wedge Thickness": mm(12)], flags: edgeFlags, cost: 6.50, model: "CCH-30",
                 description: "Corner hinge for +30° (1/12 turn) cabinets", isDefault: true)
        g.b.type("Corner Cabinet Hinge - +45°", ["Opening Angle": 110 * .pi / 180, "Wedge Thickness": mm(20)], flags: edgeFlags, cost: 6.95, model: "CCH-45",
                 description: "Corner hinge for +45° (diagonal) cabinets")
        return g.build()
    }

    static func flapHinge() -> ComponentDefinition {
        var g = concealedStarter("Flap Hinge", "Flap Hinges", "Straight concealed hinge for drop-down and lift-up flaps that open flush to 180°.")
        g.b.tags("flap", "drop down", "desk flap", "180")
        g.b.aliases("drop flap hinge", "desk flap hinge", "bar flap hinge", "180 degree hinge", "fall flap hinge")
        g.b.choice("Orientation", ["Drop Down", "Lift Up"], "Drop Down", instance: true, group: .placement)
        g.b.host([.flap], faces: [.inside], align: .bottom, alignments: [.bottom, .top], count: ComponentCountRule(steps: [.init(upTo: inch(24), count: 2)], maximumCount: 3, inset: inch(3)))
        concealed(&g, ConcealedStyle(straightArm: true))
        g.b.type("Flap Hinge - 180°", ["Opening Angle": .pi], flags: ["Top Edge": false, "Bottom Edge": true, "Back Edge": false], cost: 5.25, model: "FLH-180",
                 description: "Flap hinge, 35 mm cup, opens to 180° flush", isDefault: true)
        g.b.type("Flap Hinge - 270° Bar Flap", ["Opening Angle": 270 * .pi / 180], flags: ["Top Edge": false, "Bottom Edge": true, "Back Edge": false], cost: 6.75, model: "FLH-270",
                 description: "Bar flap hinge, opens to 270° under the carcass")
        return g.build()
    }

    static func biFoldHinge() -> ComponentDefinition {
        var g = hingeStarter("Bi-Fold Hinge", "Concealed Hinges", "Cup-to-cup hinge joining two door leaves that fold together.", count: true)
        cupParameters(&g.b)
        g.b.drill("Hinge cup", x: "Cup Offset", y: CX.zero, diameter: "Cup Diameter", depth: "Cup Depth")
        g.b.drill("Second cup", x: "-Cup Offset", y: CX.zero, diameter: "Cup Diameter", depth: "Cup Depth", target: .counterpart)
        g.b.tags("bi-fold", "folding door", "cup to cup", "concealed")
        g.b.aliases("bifold hinge", "folding door hinge", "door to door hinge", "leaf to leaf hinge", "concertina hinge")
        g.b.choice("Panel Relationship", ["Inline (180°)", "Folding (0°)"], "Folding (0°)")
        g.b.host([.door], faces: [.inside], align: .right, alignments: [.right, .left], count: .hinges)
        // Two cups, one in each leaf (either side of the joint at a = 0), and the link across it.
        let R = "Cup Diameter / 2"
        for (n, x) in [("Cup", "Cup Offset"), ("Second Cup", "-Cup Offset")] {
            g.revolve(n, along: 2, center: (x, CX.zero), profile: [(CX.zero, "-Cup Depth"), ("\(R) - 0.0012 m", "-Cup Depth"), (R, "-Cup Depth + 0.0012 m"), (R, CX.zero), (CX.zero, CX.zero)])
            g.prism("\(n) Flange", along: 2, profile: PtsA.rounded((x, CX.zero), "Cup Diameter + 0.006 m", "Cup Screw Spacing + 0.012 m", CX.mm(8)), range: (CX.zero, CX.mm(1.2)))
        }
        g.prism("Link", along: 1, profile: PtsA.rounded((CX.zero, CX.mm(5)), "2 * Cup Offset - 0.01 m", CX.mm(8), CX.mm(3)), range: ("-Arm Width / 2", "Arm Width / 2"))
        g.cylinder("Pivot", along: 1, center: (CX.zero, CX.mm(9)), radius: CX.mm(3.5), range: ("-Arm Width / 2 - 0.002 m", "Arm Width / 2 + 0.002 m"), segments: 16)
        g.b.symbol(.top, [.coarse], .rect(("-Cup Offset - \(R)", "-Cup Depth"), ("Cup Offset + \(R)", CX.mm(9))))
        g.b.type("Bi-Fold Hinge - 35 mm", [:], flags: edgeFlags, cost: 5.75, model: "BFH-35", description: "Bi-fold door hinge, 35 mm cups both leaves", isDefault: true)
        g.b.type("Bi-Fold Hinge - Inline 180°", ["Opening Angle": .pi], flags: edgeFlags, texts: ["Panel Relationship": "Inline (180°)"], cost: 6.25, model: "BFH-180",
                 description: "Bi-fold hinge for leaves that open inline (180°)")
        return g.build()
    }

    // MARK: Leaf hinges

    /// Knuckles of a leaf hinge along b, centred at (a, c), split into `n` segments (alternating leaves).
    static func knuckles(_ g: inout ShapeA, n: Int, length: String, radius: String, at p: (String, String)) {
        for k in 0..<n {
            let t0 = -0.5 + Double(k) / Double(n), t1 = -0.5 + Double(k + 1) / Double(n)
            g.cylinder("Knuckle \(k + 1)", along: 1, center: p, radius: radius, range: ("(\(length)) * \(LX.num(t0)) + 0.0002 m", "(\(length)) * \(LX.num(t1)) - 0.0002 m"), segments: 16)
        }
    }

    static func buttHinge() -> ComponentDefinition {
        var g = hingeStarter(F.buttHinge, "Butt Hinges", "Butt hinge mortised into the front's edge and the carcass, five knuckles on a steel pin.", finish: .brass, upgrading: F.buttHinge)
        g.b.tags("butt", "leaf", "mortise", "traditional")
        g.b.aliases("butt hinge", "leaf hinge", "door hinge", "mortise hinge", "cabinet butt hinge", "brass butt hinge")
        g.b.length("Leaf Width", inch(0.75), group: .dimensions)
        g.b.drill("Leaf screw", x: "-Leaf Height * 0.3", y: CX.zero, diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        g.b.drill("Leaf screw", x: "Leaf Height * 0.3", y: CX.zero, diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        let p = (CX.zero, "-Front Thickness"), r = "Pin Diameter / 2 + Leaf Thickness"
        knuckles(&g, n: 5, length: "Leaf Height", radius: r, at: p)
        g.revolve("Top Finial", along: 1, center: p, profile: PtsA.turned("Pin Diameter / 2 + 0.0004 m", CX.mm(2), base: "Leaf Height / 2", [(0, 0), (1, 0), (0.85, 0.6), (0, 1)]))
        g.revolve("Bottom Finial", along: 1, center: p, profile: PtsA.turned("Pin Diameter / 2 + 0.0004 m", CX.mm(-2), base: "-Leaf Height / 2", [(0, 0), (1, 0), (0.85, 0.6), (0, 1)]))
        g.box("Front Leaf", a: (CX.zero, "Leaf Thickness"), b: ("-Leaf Height / 2", "Leaf Height / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        g.box("Carcass Leaf", a: ("-Leaf Thickness", CX.zero), b: ("-Leaf Height / 2", "Leaf Height / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        let saved = g.levels
        g.levels = [.fine]
        for (k, y) in ["-Leaf Height * 0.3", "0 m", "Leaf Height * 0.3"].enumerated() {
            g.cylinder("Screw \(k + 1)", along: 0, center: (y, "-Front Thickness + Leaf Width * 0.62"), radius: CX.mm(2.6), range: ("-Leaf Thickness - 0.0005 m", "-Leaf Thickness"), segments: 12)
        }
        g.levels = saved
        g.b.symbol(.top, [.coarse], .rect(("-Leaf Thickness", "-Front Thickness"), ("Leaf Thickness", "-Front Thickness + Leaf Width")),
                   .circle((CX.zero, "-Front Thickness"), r))
        g.b.renames(["2\"": "Butt Hinge - 2\"", "2 1/2\"": "Butt Hinge - 2 1/2\"", "3\"": "Butt Hinge - 3\""])
        for (h, cost) in [(2.0, 2.40), (2.5, 2.80), (3.0, 3.30)] {
            let name = "Butt Hinge - \(FurnitureSizeText.inches(h * 0.0254))"
            g.b.type(name, ["Leaf Height": inch(h), "Leaf Width": inch(0.75), "Leaf Thickness": inch(0.07), "Pin Diameter": inch(0.19), "Screw Hole Diameter": mm(3),
                            "Screw Hole Depth": mm(12)], flags: edgeFlags, cost: cost, model: "BH-\(Int(h * 10))",
                     description: "Brass butt hinge, \(FurnitureSizeText.inches(h * 0.0254)) (\(Int(h * 25.4)) mm) x 1 1/2\" open", isDefault: h == 2.5)
        }
        return g.build()
    }

    static func pianoHinge() -> ComponentDefinition {
        var g = hingeStarter(F.pianoHinge, "Continuous Hinges", "Continuous (piano) hinge along the whole edge.", finish: .stainless, upgrading: F.pianoHinge, count: false)
        g.b.tags("piano", "continuous", "lid", "chest", "strip")
        g.b.aliases("piano hinge", "continuous hinge", "strip hinge", "full length hinge", "lid hinge")
        g.b.flag("Continuous", true, instance: false, group: .manufacturing)
        g.b.host([.lid, .flap, .door], faces: [.inside], align: .full)
        g.b.drill("Leaf screw", x: CX.zero, y: CX.zero, diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        let p = (CX.zero, "-Front Thickness"), r = "Pin Diameter / 2 + Leaf Thickness"
        g.levels = [.medium]
        g.cylinder("Knuckle", along: 1, center: p, radius: r, range: ("-Length / 2", "Length / 2"), segments: 14)
        g.levels = [.fine]
        knuckles(&g, n: 16, length: "Length", radius: r, at: p)
        g.levels = [.medium, .fine]
        g.box("Front Leaf", a: (CX.zero, "Leaf Thickness"), b: ("-Length / 2", "Length / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        g.box("Carcass Leaf", a: ("-Leaf Thickness", CX.zero), b: ("-Length / 2", "Length / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        g.b.symbol(.top, [.coarse], .rect(("-Leaf Thickness", "-Front Thickness"), ("Leaf Thickness", "-Front Thickness + Leaf Width")))
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", CX.zero), ("Length / 2", "Leaf Width")))
        g.b.renames(["1 1/2\" Open": "Piano Hinge - 1 1/2\" Open"])
        g.b.type("Piano Hinge - 1 1/16\" Open", ["Leaf Width": inch(0.53), "Leaf Thickness": inch(0.032), "Pin Diameter": inch(0.09), "Screw Hole Diameter": mm(2.5),
                                                  "Screw Hole Depth": mm(8), "Screw Spacing": inch(2), "Length": inch(30)],
                 flags: edgeFlags, cost: 7.50, model: "PH-106", description: "Continuous hinge, 1 1/16\" (27 mm) open, cut to length")
        g.b.type("Piano Hinge - 1 1/2\" Open", ["Leaf Width": inch(0.75), "Leaf Thickness": inch(0.04), "Pin Diameter": inch(0.12), "Screw Hole Diameter": mm(3),
                                                 "Screw Hole Depth": mm(10), "Screw Spacing": inch(4), "Length": inch(30)],
                 flags: edgeFlags, cost: 9.00, model: "PH-150", description: "Continuous hinge, 1 1/2\" (38 mm) open, cut to length", isDefault: true)
        g.b.type("Piano Hinge - 2\" Open", ["Leaf Width": inch(1), "Leaf Thickness": inch(0.06), "Pin Diameter": inch(0.15), "Screw Hole Diameter": mm(3.5),
                                             "Screw Hole Depth": mm(12), "Screw Spacing": inch(4), "Length": inch(48)],
                 flags: edgeFlags, cost: 13.50, model: "PH-200", description: "Heavy continuous hinge, 2\" (51 mm) open, cut to length")
        return g.build()
    }

    static func continuousHinge() -> ComponentDefinition {
        var g = hingeStarter("Continuous Hinge", "Continuous Hinges", "Heavy geared continuous hinge in extruded aluminium, with a full-length cover cap.",
                             finish: .aluminum, count: false)
        g.b.tags("continuous", "geared", "heavy duty", "aluminium", "full length")
        g.b.aliases("geared continuous hinge", "full surface hinge", "aluminum continuous hinge", "heavy piano hinge", "commercial hinge")
        g.b.length("Length", inch(36), instance: true)
        g.b.length("Leaf Width", mm(25)); g.b.length("Leaf Thickness", mm(3)); g.b.length("Pin Diameter", mm(8))
        g.b.length("Screw Hole Diameter", mm(4), group: .manufacturing); g.b.length("Screw Hole Depth", mm(14), group: .manufacturing); g.b.length("Screw Spacing", mm(150), group: .manufacturing)
        g.b.choice("Material", ["Aluminum", "Stainless Steel"], "Aluminum")
        g.b.flag("Continuous", true, instance: false, group: .manufacturing)
        g.b.host([.door, .lid, .flap], faces: [.inside], align: .full)
        g.b.drill("Leaf screw", x: CX.zero, y: CX.zero, diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        let fc = "-Front Thickness"
        g.box("Front Leaf", a: (CX.zero, "Leaf Thickness"), b: ("-Length / 2", "Length / 2"), c: (fc, "\(fc) + Leaf Width"))
        g.box("Carcass Leaf", a: ("-Leaf Thickness", CX.zero), b: ("-Length / 2", "Length / 2"), c: (fc, "\(fc) + Leaf Width"))
        var cap: [(String, String)] = []
        for k in 0...10 {
            let t = Double(k) / 10 * .pi
            cap.append(("(Pin Diameter / 2 + Leaf Thickness) * \(LX.num(cos(t)))", "\(fc) - (Pin Diameter / 2 + Leaf Thickness) * \(LX.num(sin(t)))"))
        }
        g.prism("Cover Cap", along: 1, profile: cap + [("-(Pin Diameter / 2 + Leaf Thickness)", "\(fc) + 0.004 m"), ("Pin Diameter / 2 + Leaf Thickness", "\(fc) + 0.004 m")],
                range: ("-Length / 2", "Length / 2"))
        g.b.symbol(.top, [.coarse], .rect(("-Leaf Thickness", fc), ("Leaf Thickness", "\(fc) + Leaf Width")))
        g.b.type("Continuous Hinge - 36\"", [:], flags: edgeFlags, cost: 38.00, model: "GCH-36", description: "Geared continuous hinge, aluminium, 36\" (914 mm)", isDefault: true)
        g.b.type("Continuous Hinge - 72\"", ["Length": inch(72)], flags: edgeFlags, cost: 64.00, model: "GCH-72", description: "Geared continuous hinge, aluminium, 72\" (1829 mm)")
        return g.build()
    }

    static func detachableHinge() -> ComponentDefinition {
        var g = hingeStarter("Detachable Hinge", "Butt Hinges", "Lift-off (flag) hinge: the door lifts off its pin without unscrewing.", finish: .satinNickel)
        g.b.tags("lift off", "detachable", "flag hinge", "removable")
        g.b.aliases("lift off hinge", "lift-off hinge", "flag hinge", "removable hinge", "take apart hinge")
        g.b.length("Leaf Height", mm(60)); g.b.length("Leaf Width", mm(18)); g.b.length("Leaf Thickness", mm(2)); g.b.length("Pin Diameter", mm(5))
        g.b.length("Screw Hole Diameter", mm(3), group: .manufacturing); g.b.length("Screw Hole Depth", mm(12), group: .manufacturing)
        g.b.drill("Leaf screw", x: "-Leaf Height * 0.3", y: CX.zero, diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        g.b.drill("Leaf screw", x: "Leaf Height * 0.3", y: CX.zero, diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        let p = (CX.zero, "-Front Thickness"), r = "Pin Diameter / 2 + Leaf Thickness"
        g.cylinder("Lower Knuckle", along: 1, center: p, radius: r, range: ("-Leaf Height / 2", "-0.0003 m"), segments: 16)
        g.cylinder("Upper Knuckle", along: 1, center: p, radius: r, range: ("0.0003 m", "Leaf Height / 2"), segments: 16)
        g.cylinder("Pin", along: 1, center: p, radius: "Pin Diameter / 2", range: ("-Leaf Height / 2", "Leaf Height / 2 + 0.002 m"), segments: 12)
        g.box("Front Leaf", a: (CX.zero, "Leaf Thickness"), b: (CX.zero, "Leaf Height / 2"), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        g.box("Carcass Leaf", a: ("-Leaf Thickness", CX.zero), b: ("-Leaf Height / 2", CX.zero), c: ("-Front Thickness", "-Front Thickness + Leaf Width"))
        g.b.symbol(.top, [.coarse], .rect(("-Leaf Thickness", "-Front Thickness"), ("Leaf Thickness", "-Front Thickness + Leaf Width")))
        g.b.type("Detachable Hinge - 60 mm", [:], flags: edgeFlags, cost: 3.95, model: "DTH-60", description: "Lift-off hinge, 60 mm (2 3/8\") tall", isDefault: true)
        g.b.type("Detachable Hinge - 80 mm", ["Leaf Height": mm(80), "Leaf Width": mm(22), "Pin Diameter": mm(6)], flags: edgeFlags, cost: 4.75, model: "DTH-80",
                 description: "Lift-off hinge, 80 mm (3 1/8\") tall")
        return g.build()
    }

    static func decorativeHinge() -> ComponentDefinition {
        var g = hingeStarter("Decorative Hinge", "Decorative Hinges", "Surface-mounted decorative hinge on the face: butterfly, H or strap leaves.", finish: .bronze)
        g.b.tags("decorative", "butterfly", "strap", "h hinge", "surface mount", "rustic")
        g.b.aliases("butterfly hinge", "strap hinge", "h hinge", "surface hinge", "ornamental hinge", "rustic hinge")
        g.b.length("Leaf Height", inch(2.5)); g.b.length("Leaf Width", inch(1)); g.b.length("Leaf Thickness", mm(2)); g.b.length("Pin Diameter", mm(4))
        g.b.length("Strap Length", inch(4))
        g.b.length("Screw Hole Diameter", mm(3), group: .manufacturing); g.b.length("Screw Hole Depth", mm(12), group: .manufacturing)
        g.b.choice("Style", ["Butterfly", "H", "Strap"], "Butterfly")
        g.b.flag("Butterfly Style", true, instance: false, group: .dimensions)
        g.b.flag("Strap Style", false, instance: false, group: .dimensions)
        g.b.flag("H Style", false, formula: "and(not(Butterfly Style), not(Strap Style))")
        g.b.drill("Leaf screw", x: "Leaf Width * 0.6", y: "Leaf Height * 0.3", diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        g.b.drill("Leaf screw", x: "Leaf Width * 0.6", y: "-Leaf Height * 0.3", diameter: "Screw Hole Diameter", depth: "Screw Hole Depth")
        // On the front face (c = -Front Thickness), leaves in front of it; the knuckle at the joint.
        let f = "-Front Thickness", lt = "Leaf Thickness", h = "Leaf Height / 2", w = "Leaf Width"
        let r = ("-Front Thickness - Leaf Thickness", f)
        g.cylinder("Knuckle", along: 1, center: (CX.zero, "\(f) - Pin Diameter / 2 - \(lt)"), radius: "Pin Diameter / 2 + \(lt)", range: ("-(\(h))", h), segments: 16)
        g.variant("Butterfly Style") { g in
            g.prism("Front Leaf", along: 2, profile: [(CX.zero, "-(\(h)) * 0.55"), (w, "-(\(h))"), (w, h), (CX.zero, "\(h) * 0.55")], range: r)
            g.prism("Carcass Leaf", along: 2, profile: [(CX.zero, "-(\(h)) * 0.55"), (CX.zero, "\(h) * 0.55"), ("-(\(w))", h), ("-(\(w))", "-(\(h))")], range: r)
        }
        g.variant("H Style") { g in
            g.prism("Front Leaf", along: 2, profile: PtsA.box((CX.zero, "\(w) * 0.6"), ("-(\(h))", h)), range: r)
            g.prism("Carcass Leaf", along: 2, profile: PtsA.box(("-(\(w)) * 0.6", CX.zero), ("-(\(h))", h)), range: r)
        }
        g.variant("Strap Style") { g in
            g.prism("Strap", along: 2, profile: [(CX.zero, "-(\(h))"), ("Strap Length * 0.85", "-(\(h)) * 0.35"), ("Strap Length", CX.zero), ("Strap Length * 0.85", "\(h) * 0.35"), (CX.zero, h)], range: r)
            g.prism("Carcass Leaf", along: 2, profile: PtsA.box(("-(\(w)) * 0.7", CX.zero), ("-(\(h))", h)), range: r)
        }
        g.b.symbol(.face, [.coarse], .rect(("-(\(w))", "-(\(h))"), (w, h)))
        g.b.type("Decorative Hinge - Butterfly 2 1/2\"", [:], flags: ["Top Edge": false, "Bottom Edge": false, "Back Edge": false, "Butterfly Style": true, "Strap Style": false],
                 cost: 4.50, model: "DCH-B25", description: "Butterfly hinge, 2 1/2\" (64 mm), oil-rubbed bronze", isDefault: true)
        g.b.type("Decorative Hinge - H 3\"", ["Leaf Height": inch(3)], flags: ["Top Edge": false, "Bottom Edge": false, "Back Edge": false, "Butterfly Style": false, "Strap Style": false],
                 texts: ["Style": "H"], cost: 4.95, model: "DCH-H3", description: "H hinge, 3\" (76 mm)")
        g.b.type("Decorative Hinge - Strap 4\"", ["Leaf Height": inch(1.5), "Strap Length": inch(4)],
                 flags: ["Top Edge": false, "Bottom Edge": false, "Back Edge": false, "Butterfly Style": false, "Strap Style": true], texts: ["Style": "Strap"],
                 cost: 6.25, model: "DCH-S4", description: "Strap hinge, 4\" (102 mm) strap")
        return g.build()
    }

    static func hiddenBarrelHinge() -> ComponentDefinition {
        var g = hingeStarter("Hidden Barrel Hinge", "Barrel Hinges", "Barrel hinge pressed into bores in the two edges; nothing shows when closed.", finish: .brass)
        g.b.tags("barrel", "hidden", "invisible", "box hinge", "jewelry box")
        g.b.aliases("barrel hinge", "invisible hinge", "hidden hinge", "box hinge", "cylinder hinge", "dowel hinge")
        g.b.length("Diameter", mm(10)); g.b.length("Depth", mm(24))
        g.b.length("Screw Hole Diameter", mm(10), formula: "Diameter"); g.b.length("Screw Hole Depth", mm(12), formula: "Depth / 2")
        g.b.length("Leaf Height", 0, group: .manufacturing)
        g.b.host([.lid, .door, .flap], faces: [.leftEdge, .rightEdge, .topEdge], align: .left, count: .hinges)
        g.b.edgeDrill("Barrel bore", x: CX.zero, z: "-Front Thickness / 2", diameter: "Diameter", depth: "Depth / 2")
        g.b.edgeDrill("Barrel bore", x: CX.zero, z: "-Front Thickness / 2", diameter: "Diameter", depth: "Depth / 2", target: .counterpart)
        g.b.requires(.hostThickness(min: "Diameter + 0.004 m", max: nil))
        let c = "-Front Thickness / 2"
        g.cylinder("Front Barrel", along: 0, center: (CX.zero, c), radius: "Diameter / 2", range: (CX.mm(0.6), "Depth / 2"), segments: 18)
        g.cylinder("Carcass Barrel", along: 0, center: (CX.zero, c), radius: "Diameter / 2", range: ("-Depth / 2", CX.mm(-0.6)), segments: 18)
        g.box("Link", a: (CX.mm(-1.5), CX.mm(1.5)), b: ("-Diameter * 0.3", "Diameter * 0.3"), c: ("\(c) - Diameter * 0.2", "\(c) + Diameter * 0.2"))
        g.b.symbol(.top, [.coarse], .rect(("-Depth / 2", "\(c) - Diameter / 2"), ("Depth / 2", "\(c) + Diameter / 2")))
        g.b.type("Hidden Barrel Hinge - 10 mm", [:], flags: edgeFlags, cost: 2.25, model: "HBH-10", description: "Barrel hinge, 10 mm (3/8\") bore", isDefault: true)
        g.b.type("Hidden Barrel Hinge - 14 mm", ["Diameter": mm(14), "Depth": mm(34)], flags: edgeFlags, cost: 3.10, model: "HBH-14", description: "Barrel hinge, 14 mm (9/16\") bore")
        return g.build()
    }

    // MARK: Pivot and lift-up hinges (face-based)

    static func pivotHinge() -> ComponentDefinition {
        var g = faced("Pivot Hinge", .hinges, "Pivot Hinges", "Top and bottom pivot set: a plate let into the door's edge turns on a pin in the carcass.")
        g.b.material(finish, .satinNickel)
        g.b.tags("hinge", "pivot", "top and bottom", "tall door")
        g.b.aliases("pivot hinge", "top pivot", "bottom pivot", "pivot set", "center hung hinge", "offset pivot")
        g.b.length("Pivot Offset", mm(20)); g.b.number("Load Rating", 44, unit: "lb", group: .data)
        g.b.length("Plate Length", mm(60)); g.b.length("Plate Width", mm(14)); g.b.length("Pin Diameter", mm(9)); g.b.length("Pin Height", mm(10))
        g.b.host([.door], faces: [.topEdge, .bottomEdge], align: .left, alignments: [.left, .right], offsetX: mm(20))
        g.b.pocket("Pivot plate", x: "Plate Length / 2 - 0.015 m", y: CX.zero, width: "Plate Length", height: "Plate Width", depth: CX.mm(3))
        g.b.drill("Pivot pin", x: CX.zero, y: CX.zero, diameter: "Pin Diameter + 0.001 m", depth: CX.mm(12), target: .counterpart)
        g.b.requires(.maxHostWeight("Load Rating"))
        // Origin: the pin axis on the door's edge (c out of the edge toward the carcass).
        g.prism("Door Plate", along: 2, profile: PtsA.rounded(("Plate Length / 2 - 0.015 m", CX.zero), "Plate Length", "Plate Width", CX.mm(3)), range: (CX.mm(-3), CX.zero))
        g.cylinder("Pin", along: 2, radius: "Pin Diameter / 2", range: (CX.zero, "Pin Height"), segments: 18)
        g.revolve("Bushing", along: 2, profile: PtsA.turned("Pin Diameter * 0.9", CX.mm(3), base: "Pin Height - 0.003 m", [(0.56, 0), (1, 0), (1, 1), (0.56, 1)]))
        g.prism("Carcass Plate", along: 2, profile: PtsA.rounded(("Plate Length / 2 - 0.02 m", CX.zero), "Plate Length * 0.8", "Plate Width + 0.004 m", CX.mm(3)),
                range: ("Pin Height", "Pin Height + 0.003 m"))
        g.b.symbol(.face, [.coarse], .rect(("-0.015 m", "-Plate Width / 2"), ("Plate Length - 0.015 m", "Plate Width / 2")), .circle((CX.zero, CX.zero), "Pin Diameter / 2"))
        g.b.type("Pivot Hinge - 44 lb", [:], cost: 14.50, model: "PVH-20", description: "Pivot hinge set, 20 kg (44 lb) door", isDefault: true)
        g.b.type("Pivot Hinge - 88 lb", ["Plate Length": mm(80), "Plate Width": mm(18), "Pin Diameter": mm(12), "Pivot Offset": mm(30)], numbers: ["Load Rating": 88], cost: 24.00,
                 model: "PVH-40", description: "Heavy pivot hinge set, 40 kg (88 lb) door")
        return g.build()
    }

    static func liftUpHinge() -> ComponentDefinition {
        var g = faced("Lift-Up Hinge", .hinges, "Lift Mechanisms", "Lift-up flap fitting on the carcass side: a spring unit and arm that hold the flap open at any angle.")
        g.b.material(finish, .whitePlastic)
        g.b.material("Arm Material", .steel)
        g.b.tags("lift up", "flap", "wall cabinet", "stay", "spring")
        g.b.aliases("lift up hinge", "flap lift", "lift system", "aventos style", "up and over hinge", "bi-fold lift")
        g.b.angle("Opening Angle", 100); g.b.number("Load", 11, unit: "lb", group: .data)
        g.b.length("Body Length", mm(160)); g.b.length("Body Height", mm(110)); g.b.length("Body Width", mm(30)); g.b.length("Arm Length", mm(180)); g.b.length("Setback", mm(20))
        g.b.host([.sidePanel], faces: [.inside], align: .topLeft, alignments: [.topLeft, .topRight], mirroredPair: true)
        for (x, y) in [("Setback + 0.016 m", "-0.016 m"), ("Setback + 0.048 m", "-0.016 m"), ("Setback + Body Length - 0.02 m", "-Body Height + 0.02 m")] {
            g.b.drill("Body screw", x: x, y: y, diameter: CX.mm(5), depth: CX.mm(13))
        }
        g.b.requires(.note("Choose the type by the flap's weight × height (power factor)."))
        // Origin: the side panel's inside face at the opening's top front corner; +a toward the back.
        g.prism("Body", along: 2, profile: PtsA.rounded(("Setback + Body Length / 2", "-Body Height / 2"), "Body Length", "Body Height", CX.mm(10)), range: (CX.zero, "Body Width"))
        g.prism("Cover Cap", along: 2, profile: PtsA.rounded(("Setback + Body Length / 2", "-Body Height / 2"), "Body Length - 0.006 m", "Body Height - 0.006 m", CX.mm(8)),
                range: ("Body Width", "Body Width + 0.002 m"))
        g.using("Arm Material")
        g.prism("Arm", along: 2, profile: [("Setback + 0.02 m", "-Body Height * 0.35"), ("Setback + 0.03 m", "-Body Height * 0.35 + 0.012 m"),
                                           ("Setback - Arm Length * 0.25", "-Body Height * 0.35 + 0.04 m"), ("Setback - Arm Length * 0.28", "-Body Height * 0.35 + 0.028 m")],
                range: ("Body Width + 0.002 m", "Body Width + 0.007 m"))
        g.prism("Front Bracket", along: 2, profile: PtsA.rounded(("Setback - Arm Length * 0.27", "-Body Height * 0.35 + 0.034 m"), CX.mm(14), CX.mm(40), CX.mm(3)),
                range: ("Body Width", "Body Width + 0.01 m"))
        g.b.symbol(.face, [.coarse], .rect(("Setback", "-Body Height"), ("Setback + Body Length", CX.zero)))
        g.b.symbol(.top, [.coarse], .rect(("Setback", CX.zero), ("Setback + Body Length", "Body Width")))
        g.b.type("Lift-Up Hinge - Light", [:], numbers: ["Load": 11], cost: 38.00, model: "LUH-L", description: "Lift-up flap fitting pair, flaps to 11 lb (5 kg)", isDefault: true)
        g.b.type("Lift-Up Hinge - Medium", ["Body Length": mm(180), "Body Height": mm(120)], numbers: ["Load": 22], cost: 46.00, model: "LUH-M",
                 description: "Lift-up flap fitting pair, flaps to 22 lb (10 kg)")
        g.b.type("Lift-Up Hinge - Heavy", ["Body Length": mm(200), "Body Height": mm(130), "Body Width": mm(34)], numbers: ["Load": 33], cost: 58.00, model: "LUH-H",
                 description: "Lift-up flap fitting pair, flaps to 33 lb (15 kg)")
        return g.build()
    }
}
