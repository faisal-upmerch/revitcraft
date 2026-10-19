import Foundation
import ArcusGeometry

// COMPA: 04 Drawer Systems (24). Slides are pairs in FM5's opening frame (origin at the bay's left side, front and
// bottom; a across the opening, b into its depth, c up) with FM5's slide parameters, so drawers pick the longest that
// fits their bay (lengths 250–600 mm in 50 mm steps) and machining drills both sides. FM5's side-mount and undermount
// slides are upgraded in place. Boxes, sides and synchronisation parts use the same frame; organisers sit on the
// drawer bottom (plan frame); fittings on a face are face-based.

extension GroupA {
    static var drawers: [ComponentDefinition] {
        [standardSlide(), ballBearingSlide(), softCloseSlide(), pushToOpenSlide(), undermountSlide(), sideMountSlide(), centerMountSlide(), fullExtensionSlide(),
         threeQuarterSlide(), heavyDutySlide(), concealedRunner(), drawerSideProfile(), metalDrawerBox(), woodenDrawerBox(), bottomSupport(), frontConnector(),
         drawerDivider(), drawerOrganizer(), cutleryTray(), drawerPushLock(), drawerDamper(), drawerStop(), syncRod(), drawerStabilizer()]
    }

    /// Standard slide lengths: 250–600 mm in 50 mm steps.
    static let slideLengthsMM: [Double] = [250, 300, 350, 400, 450, 500, 550, 600]

    static func off(_ x: String, _ s: Double, _ d: String) -> String { s > 0 ? "\(x) + (\(d))" : "\(x) - (\(d))" }

    /// A C channel on the (a, c) plane: its web at `x`, opening toward `s` (+1: +a), `depth` deep, `height` tall,
    /// centred at height `z`.
    static func channel(_ x: String, _ s: Double, depth d: String, height h: String, t: String, z: String) -> [(String, String)] {
        let lo = "\(z) - (\(h)) / 2", hi = "\(z) + (\(h)) / 2"
        let pts = [(x, lo), (off(x, s, d), lo), (off(x, s, d), "\(lo) + \(t)"), (off(x, s, t), "\(lo) + \(t)"), (off(x, s, t), "\(hi) - \(t)"),
                   (off(x, s, d), "\(hi) - \(t)"), (off(x, s, d), hi), (x, hi)]
        return s > 0 ? pts : pts.reversed()
    }

    /// The opening's two sides: (+1 at the left side's face, -1 at the right's).
    static let sides: [(Double, String, String)] = [(1, "Slide Inset", "Left"), (-1, "Opening Width - Slide Inset", "Right")]

    /// A slide pair in the opening frame with FM5's slide parameters and the owner's drawer properties.
    static func slideStarter(_ name: String, _ sub: String, _ description: String, upgrading fm5: String? = nil, height: Double, thickness: Double, inset: Double = 0,
                             side: Double, bottom: Double, top: Double, setback: Double, holeSpacing: Double, ext: String, ratio: Double, load: Double,
                             soft: Bool = false, push: Bool = false, under: Bool = false, finish f: ComponentFinish = .zinc) -> ShapeA {
        var b = starter(name, .drawers, sub, description, frame: .legacyOpening, upgrading: fm5)
        setFinish(&b, f)
        b.hardwareKind(.slide)
        for (p, v) in [("Slide Length", 450.0), ("Slide Height", height), ("Slide Thickness", thickness), ("Slide Inset", inset), ("Side Clearance", side),
                       ("Bottom Clearance", bottom), ("Top Clearance", top), ("Rear Clearance", 12.7), ("Front Setback", setback), ("First Hole", 37),
                       ("Hole Spacing", holeSpacing), ("Screw Hole Diameter", 4), ("Screw Hole Depth", 12)] {
            b.length(p, mm(v), group: p == "Slide Length" ? .dimensions : .manufacturing)
        }
        b.length("Opening Width", inch(15), instance: true, group: .dimensions)
        b.length("Mount Height", inch(1.5), instance: true, group: .placement)
        b.length("Drawer Width", 0, formula: "Opening Width - 2 * Side Clearance")
        b.length("Drawer Depth", 0, formula: "Slide Length")
        b.length("Drawer Height", inch(4), instance: true)
        b.length("Extension Distance", mm(450 * ratio))
        b.choice("Extension", ["3/4", "Full", "Over-Travel", "Partial"], ext)
        b.number("Load Capacity", load, unit: "lb", group: .data)
        b.flag("Soft Close", soft, instance: false, group: .data)
        b.flag("Push to Open", push, instance: false, group: .data)
        b.flag("Undermount", under, instance: false, group: .manufacturing)
        b.host([.bay], faces: [.inside], align: .bottom, alignments: [.bottom], mirroredPair: true)
        b.requires(.fitsDepth("Slide Length + Rear Clearance"))
        b.requires(.maxHostWeight("Load Capacity"))
        b.clearance(.side("Side Clearance")); b.clearance(.rear("Rear Clearance")); b.clearance(.bottom("Bottom Clearance")); b.clearance(.top("Top Clearance"))
        for k in 0..<4 {
            b.drill("Slide screw", x: "Front Setback + First Hole + Hole Spacing * \(k)", y: "Mount Height", diameter: "Screw Hole Diameter", depth: "Screw Hole Depth", target: .host)
        }
        b.tags("slide", "drawer", "runner", "hardware")
        b.aliases("drawer runner", "drawer glide", "drawer slide")
        for l in slideLengthsMM { for a in TradeA.sizeAliases(l) where !b.definition.aliases.contains(a) { b.definition.aliases.append(a) } }
        return ShapeA(b)
    }

    /// The slide lengths as types ("Drawer Slide - 450 mm"), costed from `base` up by `step` per 50 mm.
    static func slideTypes(_ g: inout ShapeA, base: Double, step: Double, model: String, ratio: Double, _ what: String, extra: [String: Double] = [:]) {
        for (k, l) in slideLengthsMM.enumerated() {
            var v = extra
            v["Slide Length"] = mm(l); v["Extension Distance"] = mm(l * ratio)
            g.b.type("Drawer Slide - \(Int(l)) mm", v, cost: (base + step * Double(k) * 100).rounded() / 100, model: "\(model)-\(Int(l))",
                     description: "\(what), \(Int(l)) mm (\(TradeA.inchWord(l))) pair", isDefault: l == 450)
        }
    }

    /// A ball-bearing slide pair: the cabinet member, a middle member (three-section) and the drawer member.
    static func ballBearingPair(_ g: inout ShapeA, members: Int = 3) {
        let z = "Mount Height", H = "Slide Height", T = "Slide Thickness", t = CX.mm(1.2)
        let y = ("Front Setback", "Front Setback + Slide Length")
        for (s, x, n) in sides {
            g.prism("\(n) Cabinet Member", along: 1, profile: channel(x, s, depth: "(\(T)) * 0.6", height: H, t: t, z: z), range: y)
            if members > 2 {
                g.prism("\(n) Middle Member", along: 1, profile: channel(off(x, s, "0.0012 m"), s, depth: "(\(T)) * 0.5", height: "(\(H)) * 0.8", t: t, z: z),
                        range: ("Front Setback + 0.004 m", "Front Setback + Slide Length - 0.004 m"))
            }
            g.prism("\(n) Drawer Member", along: 1, profile: channel(off(x, s, T), -s, depth: "(\(T)) * 0.45", height: "(\(H)) * 0.55", t: t, z: z),
                    range: ("Front Setback + 0.008 m", "Front Setback + Slide Length - 0.008 m"))
            let saved = g.levels
            g.levels = [.fine]
            for k in 0..<3 {
                g.box("\(n) Ball Cage \(k + 1)", a: (off(x, s, "(\(T)) * 0.42"), off(x, s, "(\(T)) * 0.58")), b: ("Front Setback + Slide Length * \(LX.num(0.15 + 0.3 * Double(k)))",
                                                                                                              "Front Setback + Slide Length * \(LX.num(0.27 + 0.3 * Double(k)))"),
                      c: ("\(z) - (\(H)) * 0.36", "\(z) + (\(H)) * 0.36"))
            }
            g.levels = saved
        }
        slideSymbols(&g)
    }

    /// Coarse plan and side symbols of a slide pair.
    static func slideSymbols(_ g: inout ShapeA) {
        g.b.symbol(.top, [.coarse], .rect(("Slide Inset", "Front Setback"), ("Slide Inset + Slide Thickness", "Front Setback + Slide Length")),
                   .rect(("Opening Width - Slide Inset - Slide Thickness", "Front Setback"), ("Opening Width - Slide Inset", "Front Setback + Slide Length")))
        g.b.symbol(.side, [.coarse], .rect(("Front Setback", "Mount Height - Slide Height / 2"), ("Front Setback + Slide Length", "Mount Height + Slide Height / 2")))
    }

    // MARK: Slides

    static func sideMountSlide() -> ComponentDefinition {
        var g = slideStarter(F.sideMountSlide, "Drawer Slides", "Ball-bearing side-mount slide pair, three sections, full extension.", upgrading: F.sideMountSlide,
                             height: 45, thickness: 12.7, side: 12.7, bottom: 9.5, top: 12.7, setback: 2, holeSpacing: 128, ext: "Full", ratio: 1, load: 100)
        g.b.tags("side mount", "ball bearing", "full extension", "45 mm")
        g.b.aliases("side-mount slides", "side mount slide", "ball bearing slide", "full extension slide", "45 mm slide", "telescopic slide")
        ballBearingPair(&g)
        g.b.renames(["12\"": "Drawer Slide - 300 mm", "14\"": "Drawer Slide - 350 mm", "16\"": "Drawer Slide - 400 mm", "18\"": "Drawer Slide - 450 mm",
                     "20\"": "Drawer Slide - 500 mm", "22\"": "Drawer Slide - 550 mm", "24\"": "Drawer Slide - 600 mm"])
        slideTypes(&g, base: 7.50, step: 1.25, model: "SMS", ratio: 1, "Side-mount ball-bearing slides, full extension, 100 lb")
        return g.build()
    }

    static func ballBearingSlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - Ball Bearing", "Drawer Slides", "Compact 35 mm ball-bearing slide pair, full extension, for light drawers.",
                             height: 35, thickness: 10, side: 10, bottom: 8, top: 10, setback: 2, holeSpacing: 96, ext: "Full", ratio: 1, load: 66)
        g.b.tags("ball bearing", "35 mm", "compact", "light duty")
        g.b.aliases("ball-bearing slides", "ball bearing runner", "35 mm slide", "compact slide", "light duty slide")
        ballBearingPair(&g)
        slideTypes(&g, base: 6.25, step: 1.00, model: "BBS35", ratio: 1, "Compact ball-bearing slides, 35 mm, full extension, 66 lb")
        return g.build()
    }

    static func fullExtensionSlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - Full Extension", "Drawer Slides", "53 mm three-section slide pair with 1\" over-travel: the drawer clears the front.",
                             height: 53, thickness: 12.7, side: 12.7, bottom: 9.5, top: 12.7, setback: 2, holeSpacing: 128, ext: "Over-Travel", ratio: 1.06, load: 150)
        g.b.tags("full extension", "over travel", "53 mm", "file drawer")
        g.b.aliases("full-extension slides", "over travel slide", "file drawer slide", "full ext slide")
        ballBearingPair(&g)
        slideTypes(&g, base: 11.50, step: 1.50, model: "FES53", ratio: 1.06, "Full-extension slides with over-travel, 53 mm, 150 lb")
        return g.build()
    }

    static func threeQuarterSlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - 3/4 Extension", "Drawer Slides", "Two-section 35 mm slide pair: the drawer opens three quarters of its length.",
                             height: 35, thickness: 9.5, side: 9.5, bottom: 8, top: 10, setback: 2, holeSpacing: 96, ext: "3/4", ratio: 0.75, load: 50)
        g.b.tags("three quarter", "3/4 extension", "two section", "economy")
        g.b.aliases("three-quarter extension slides", "3/4 extension slide", "partial extension slide", "two section slide")
        ballBearingPair(&g, members: 2)
        slideTypes(&g, base: 4.25, step: 0.75, model: "TQS35", ratio: 0.75, "3/4-extension slides, 35 mm, 50 lb")
        return g.build()
    }

    static func heavyDutySlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - Heavy Duty", "Drawer Slides", "76 mm heavy-duty slide pair with lock-out, for tool and pantry drawers.",
                             height: 76, thickness: 19, side: 19, bottom: 12.7, top: 12.7, setback: 3, holeSpacing: 128, ext: "Full", ratio: 1, load: 500, finish: .matteBlack)
        g.b.tags("heavy duty", "76 mm", "lock out", "industrial", "500 lb")
        g.b.aliases("heavy-duty slides", "heavy duty runner", "locking slide", "industrial slide", "3\" slide")
        ballBearingPair(&g)
        for (s, x, n) in sides {
            g.box("\(n) Lock Lever", a: (off(x, s, "Slide Thickness * 0.5"), off(x, s, "Slide Thickness + 0.002 m")), b: ("Front Setback + 0.01 m", "Front Setback + 0.05 m"),
                  c: ("Mount Height - 0.006 m", "Mount Height + 0.006 m"))
        }
        slideTypes(&g, base: 42.00, step: 4.50, model: "HDS76", ratio: 1, "Heavy-duty slides with lock-out, 76 mm, 500 lb")
        return g.build()
    }

    static func softCloseSlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - Soft Close", "Drawer Slides", "Ball-bearing slide pair with a damper that pulls the drawer shut gently.",
                             height: 45, thickness: 12.7, side: 12.7, bottom: 9.5, top: 12.7, setback: 2, holeSpacing: 128, ext: "Full", ratio: 1, load: 100, soft: true)
        g.b.material("Damper Material", .greyPlastic)
        g.b.tags("soft close", "damper", "self close", "quiet")
        g.b.aliases("soft-close slides", "soft close runner", "self closing slide", "damped slide")
        ballBearingPair(&g)
        g.using("Damper Material")
        for (s, x, n) in sides {
            g.cylinder("\(n) Damper", along: 1, center: (off(x, s, "Slide Thickness * 0.3"), "Mount Height"), radius: "Slide Height * 0.13",
                       range: ("Front Setback + Slide Length - 0.09 m", "Front Setback + Slide Length - 0.01 m"), segments: 16)
        }
        g.using(nil)
        slideTypes(&g, base: 13.50, step: 1.50, model: "SCS", ratio: 1, "Soft-close ball-bearing slides, full extension, 100 lb")
        return g.build()
    }

    static func pushToOpenSlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - Push to Open", "Drawer Slides", "Ball-bearing slide pair with a push latch at the back: push the front and the drawer opens.",
                             height: 45, thickness: 12.7, side: 12.7, bottom: 9.5, top: 12.7, setback: 2, holeSpacing: 128, ext: "Full", ratio: 1, load: 77, push: true)
        g.b.material("Latch Material", .greyPlastic)
        g.b.tags("push to open", "touch", "handleless", "push latch")
        g.b.aliases("push-to-open slides", "touch release slide", "push open runner", "handleless slide", "tip-on slide")
        ballBearingPair(&g)
        g.using("Latch Material")
        for (s, x, n) in sides {
            g.box("\(n) Push Unit", a: (off(x, s, "0.0012 m"), off(x, s, "Slide Thickness * 0.55")), b: ("Front Setback + Slide Length - 0.07 m", "Front Setback + Slide Length"),
                  c: ("Mount Height - Slide Height * 0.4", "Mount Height + Slide Height * 0.4"))
        }
        g.using(nil)
        g.b.requires(.note("Fronts on push-to-open slides need no handle and a 1/8\" gap all round."))
        slideTypes(&g, base: 15.50, step: 1.50, model: "PTO", ratio: 1, "Push-to-open ball-bearing slides, full extension, 77 lb")
        return g.build()
    }

    static func standardSlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - Standard", "Drawer Slides", "Epoxy-coated bottom-mount roller slide pair, three-quarter extension.",
                             height: 32, thickness: 12.7, side: 12.7, bottom: 3, top: 12.7, setback: 3, holeSpacing: 96, ext: "3/4", ratio: 0.75, load: 55, finish: .whitePlastic)
        g.b.material("Roller Material", .nylon)
        g.b.tags("standard", "roller", "epoxy", "bottom mount", "economy")
        g.b.aliases("standard drawer slides", "roller slide", "epoxy slide", "euro slide", "bottom mount slide", "white slide")
        g.b.preset("Bottom mounted", type: "Drawer Slide - 450 mm", values: ["Mount Height": .double(mm(16))])
        let z = "Mount Height - Slide Height / 2", t = CX.mm(1.5), y = ("Front Setback", "Front Setback + Slide Length")
        for (s, x, n) in sides {
            // The cabinet member: an L along the side with a lip; the drawer member: an L under the drawer's bottom edge.
            g.prism("\(n) Cabinet Member", along: 1, profile: s > 0 ? [(x, z), (off(x, s, "Slide Thickness"), z), (off(x, s, "Slide Thickness"), "\(z) + 0.004 m"), (off(x, s, t), "\(z) + \(t)"),
                                                                     (off(x, s, t), "\(z) + Slide Height"), (x, "\(z) + Slide Height")]
                                                                  : [(x, z), (x, "\(z) + Slide Height"), (off(x, s, t), "\(z) + Slide Height"), (off(x, s, t), "\(z) + \(t)"),
                                                                     (off(x, s, "Slide Thickness"), "\(z) + 0.004 m"), (off(x, s, "Slide Thickness"), z)], range: y)
            g.prism("\(n) Drawer Member", along: 1, profile: s > 0 ? [(off(x, s, "Slide Thickness"), "\(z) + Slide Height * 0.45"), (off(x, s, "Slide Thickness + 0.012 m"), "\(z) + Slide Height * 0.45"),
                                                                    (off(x, s, "Slide Thickness + 0.012 m"), "\(z) + Slide Height * 0.45 + \(t)"), (off(x, s, "Slide Thickness + \(t)"), "\(z) + Slide Height * 0.45 + \(t)"),
                                                                    (off(x, s, "Slide Thickness + \(t)"), "\(z) + Slide Height"), (off(x, s, "Slide Thickness"), "\(z) + Slide Height")]
                                                                 : [(off(x, s, "Slide Thickness"), "\(z) + Slide Height * 0.45"), (off(x, s, "Slide Thickness"), "\(z) + Slide Height"),
                                                                    (off(x, s, "Slide Thickness + \(t)"), "\(z) + Slide Height"), (off(x, s, "Slide Thickness + \(t)"), "\(z) + Slide Height * 0.45 + \(t)"),
                                                                    (off(x, s, "Slide Thickness + 0.012 m"), "\(z) + Slide Height * 0.45 + \(t)"), (off(x, s, "Slide Thickness + 0.012 m"), "\(z) + Slide Height * 0.45")],
                    range: ("Front Setback + 0.01 m", "Front Setback + Slide Length - 0.002 m"))
            g.using("Roller Material")
            g.cylinder("\(n) Front Roller", along: 0, center: ("Front Setback + 0.018 m", "\(z) + 0.012 m"), radius: CX.mm(10), range: pairRange((off(x, s, "0.002 m"), off(x, s, "0.009 m")), s), segments: 18)
            g.cylinder("\(n) Rear Roller", along: 0, center: ("Front Setback + Slide Length - 0.014 m", "\(z) + Slide Height * 0.45 + 0.01 m"), radius: CX.mm(9),
                       range: pairRange((off(x, s, "Slide Thickness + 0.002 m"), off(x, s, "Slide Thickness + 0.008 m")), s), segments: 18)
            g.using(nil)
        }
        slideSymbols(&g)
        slideTypes(&g, base: 3.25, step: 0.50, model: "STD", ratio: 0.75, "Epoxy roller slides, bottom mount, 3/4 extension, 55 lb")
        return g.build()
    }

    static func undermountSlide() -> ComponentDefinition {
        var g = slideStarter(F.undermountSlide, "Drawer Slides", "Concealed undermount slide pair under the drawer bottom, full extension, soft close.", upgrading: F.undermountSlide,
                             height: 19, thickness: 25.4, inset: 8, side: 8, bottom: 14.3, top: 6.4, setback: 6.4, holeSpacing: 224, ext: "Full", ratio: 1, load: 100,
                             soft: true, under: true)
        g.b.material("Locking Device Material", .greyPlastic)
        g.b.tags("undermount", "concealed", "soft close", "hidden", "full extension")
        g.b.aliases("undermount slides", "under mount slide", "concealed slide", "hidden runner", "undermount runner", "tandem style")
        underRunner(&g, partial: false)
        g.b.renames(["12\"": "Drawer Slide - 300 mm", "14\"": "Drawer Slide - 350 mm", "16\"": "Drawer Slide - 400 mm", "18\"": "Drawer Slide - 450 mm",
                     "20\"": "Drawer Slide - 500 mm", "22\"": "Drawer Slide - 550 mm", "24\"": "Drawer Slide - 600 mm"])
        slideTypes(&g, base: 22.00, step: 2.50, model: "UMS", ratio: 1, "Undermount slides, full extension, soft close, 100 lb")
        return g.build()
    }

    static func concealedRunner() -> ComponentDefinition {
        var g = slideStarter("Drawer Runner - Concealed", "Drawer Slides", "Concealed runner pair for wooden drawers, partial extension, with front locking clips.",
                             height: 16, thickness: 22, inset: 6, side: 6, bottom: 12, top: 6.4, setback: 6.4, holeSpacing: 192, ext: "Partial", ratio: 0.8, load: 66, under: true)
        g.b.material("Locking Device Material", .greyPlastic)
        g.b.tags("concealed runner", "undermount", "wooden drawer", "partial extension")
        g.b.aliases("concealed drawer runners", "hidden runner", "wood drawer runner", "concealed slide partial")
        underRunner(&g, partial: true)
        slideTypes(&g, base: 12.00, step: 1.50, model: "CDR", ratio: 0.8, "Concealed runners, partial extension, 66 lb")
        return g.build()
    }

    /// An undermount runner pair: the cabinet member on the side's face at the bottom, the runner under the drawer's
    /// bottom with its locking device at the front and its hook at the back.
    static func underRunner(_ g: inout ShapeA, partial: Bool) {
        let z = "Mount Height - Slide Height / 2", T = "Slide Thickness", y = ("Front Setback", "Front Setback + Slide Length")
        for (s, x0, n) in sides {
            let x = s > 0 ? "0 m" : "Opening Width"
            // The cabinet member: a flat angle screwed to the side, the runner on it.
            let cab: [(String, String)] = [(x, z), (off(x, s, "Slide Inset + \(T)"), z), (off(x, s, "Slide Inset + \(T)"), "\(z) + 0.0015 m"), (off(x, s, "0.0015 m"), "\(z) + 0.0015 m"),
                                           (off(x, s, "0.0015 m"), "\(z) + Slide Height + 0.006 m"), (x, "\(z) + Slide Height + 0.006 m")]
            g.prism("\(n) Cabinet Member", along: 1, profile: s > 0 ? cab : cab.reversed(), range: y)
            g.prism("\(n) Runner", along: 1, profile: channel(off(x0, s, T), -s, depth: "(\(T)) * 0.85", height: "Slide Height - 0.002 m", t: CX.mm(1.3), z: "Mount Height + 0.0015 m"),
                    range: ("Front Setback + 0.004 m", partial ? "Front Setback + Slide Length * 0.92" : "Front Setback + Slide Length - 0.004 m"))
            g.using("Locking Device Material")
            g.box("\(n) Locking Device", a: pairRange((off(x0, s, "0 m"), off(x0, s, T)), s), b: ("Front Setback + 0.006 m", "Front Setback + 0.05 m"),
                  c: ("Mount Height + Slide Height / 2 + 0.0015 m", "Mount Height + Slide Height / 2 + 0.008 m"))
            g.using(nil)
            g.box("\(n) Rear Hook", a: pairRange((off(x0, s, "\(T) * 0.3"), off(x0, s, "\(T) * 0.7")), s), b: ("Front Setback + Slide Length - 0.012 m", "Front Setback + Slide Length - 0.006 m"),
                  c: ("Mount Height + Slide Height / 2", "Mount Height + Slide Height / 2 + 0.01 m"))
        }
        slideSymbols(&g)
    }

    static func centerMountSlide() -> ComponentDefinition {
        var g = slideStarter("Drawer Slide - Center Mount", "Drawer Slides", "Single monorail under the middle of the drawer, with a rear bracket; for face-frame cabinets.",
                             height: 22, thickness: 28, side: 3, bottom: 25, top: 6, setback: 0, holeSpacing: 96, ext: "3/4", ratio: 0.75, load: 35)
        g.b.material("Guide Material", .nylon)
        g.b.tags("center mount", "monorail", "face frame", "single rail", "wood drawer")
        g.b.aliases("center-mount slides", "centre mount slide", "monorail slide", "single drawer slide", "under drawer center slide")
        g.b.definition.placement.mirroredPair = false
        let cx = "Opening Width / 2", z = "Mount Height", y = ("Front Setback", "Front Setback + Slide Length")
        g.prism("Rail", along: 1, profile: [("\(cx) - Slide Thickness / 2", "\(z) - Slide Height / 2"), ("\(cx) - Slide Thickness / 2 + 0.0015 m", "\(z) - Slide Height / 2"),
                                            ("\(cx) - Slide Thickness * 0.3", "\(z) + Slide Height / 2 - 0.0015 m"), ("\(cx) + Slide Thickness * 0.3", "\(z) + Slide Height / 2 - 0.0015 m"),
                                            ("\(cx) + Slide Thickness / 2 - 0.0015 m", "\(z) - Slide Height / 2"), ("\(cx) + Slide Thickness / 2", "\(z) - Slide Height / 2"),
                                            ("\(cx) + Slide Thickness * 0.3 + 0.0015 m", "\(z) + Slide Height / 2"), ("\(cx) - Slide Thickness * 0.3 - 0.0015 m", "\(z) + Slide Height / 2")], range: y)
        g.box("Rear Bracket", a: ("\(cx) - 0.035 m", "\(cx) + 0.035 m"), b: ("Front Setback + Slide Length", "Front Setback + Slide Length + 0.0015 m"), c: ("\(z) - 0.03 m", "\(z) + Slide Height / 2"))
        g.using("Guide Material")
        g.box("Drawer Guide", a: ("\(cx) - Slide Thickness * 0.4", "\(cx) + Slide Thickness * 0.4"), b: ("Front Setback + Slide Length - 0.06 m", "Front Setback + Slide Length - 0.01 m"),
              c: ("\(z) + Slide Height / 2", "\(z) + Slide Height / 2 + 0.006 m"))
        g.using(nil)
        g.b.symbol(.top, [.coarse], .rect(("\(cx) - Slide Thickness / 2", "Front Setback"), ("\(cx) + Slide Thickness / 2", "Front Setback + Slide Length")))
        slideTypes(&g, base: 5.50, step: 0.75, model: "CMS", ratio: 0.75, "Center-mount monorail slide, 3/4 extension, 35 lb", extra: ["Mount Height": mm(30)])
        return g.build()
    }

    // MARK: Drawer boxes and sides

    static let melamine = ComponentFinish("Melamine - White", .generic, RGBColor(hex: 0xF1F1EE))
    static let birchPly = ComponentFinish("Birch Plywood", .wood, RGBColor(hex: 0xD9BF90))

    /// A double-wall metal drawer side on the (a, c) plane: `x` its outer face, toward `s`, rounded on top.
    static func doubleWall(_ x: String, _ s: Double, height h: String) -> [(String, String)] {
        var pts: [(String, String)] = [(x, CX.zero), (off(x, s, "Side Width"), CX.zero)]
        for k in 0...6 {
            let a = Double(k) / 6 * .pi
            pts.append((off(x, s, "Side Width / 2 + Side Width / 2 * \(LX.num(cos(a)))"), "\(h) - Side Width / 2 + Side Width / 2 * \(LX.num(sin(a)))"))
        }
        return s > 0 ? pts : pts.reversed()
    }

    static func drawerSideProfile() -> ComponentDefinition {
        var g = ShapeA(ComponentBuilder("Drawer Side Profile", .drawers, "Drawer Boxes", "Double-wall steel drawer side with its runner, front fixing and back bracket, as a pair.",
                                        frame: .legacyOpening))
        g.b.material(finish, .stainless)
        g.b.tags("drawer side", "metal drawer", "double wall", "box system", "steel side")
        g.b.aliases("drawer side profiles", "metal drawer side", "double wall side", "drawer box side", "tandembox style", "legrabox style")
        g.b.length("Nominal Length", mm(500), instance: true); g.b.length("Side Height", mm(86)); g.b.length("Side Width", mm(16))
        g.b.length("Opening Width", inch(15), instance: true); g.b.length("Side Clearance", mm(5), group: .manufacturing)
        g.b.number("Load Capacity", 66, unit: "lb")
        g.b.host([.bay], faces: [.inside], align: .bottom, mirroredPair: true)
        g.b.requires(.fitsDepth("Nominal Length + 0.01 m"))
        for (s, x, n) in [(1.0, "Side Clearance", "Left"), (-1.0, "Opening Width - Side Clearance", "Right")] {
            g.prism("\(n) Side", along: 1, profile: doubleWall(x, s, height: "Side Height"), range: (CX.mm(10), "Nominal Length - 0.01 m"))
            g.box("\(n) Front Fixing", a: pairRange((off(x, s, "0.002 m"), off(x, s, "Side Width - 0.002 m")), s), b: (CX.zero, CX.mm(10)), c: (CX.mm(8), "Side Height - 0.012 m"))
            g.box("\(n) Back Bracket", a: pairRange((off(x, s, "Side Width"), off(x, s, "Side Width + 0.012 m")), s), b: ("Nominal Length - 0.022 m", "Nominal Length - 0.01 m"),
                  c: (CX.mm(10), "Side Height - 0.01 m"))
        }
        g.b.symbol(.top, [.coarse], .rect(("Side Clearance", CX.zero), ("Side Clearance + Side Width", "Nominal Length")),
                   .rect(("Opening Width - Side Clearance - Side Width", CX.zero), ("Opening Width - Side Clearance", "Nominal Length")))
        for (h, n, cost) in [(86.0, "Low", 28.00), (118, "Medium", 33.00), (167, "High", 41.00)] {
            g.b.type("Drawer Side Profile - \(Int(h)) mm \(n)", ["Side Height": mm(h)], cost: cost, model: "DSP-\(Int(h))",
                     description: "Double-wall drawer side pair, \(Int(h)) mm (\(TradeA.inchWord(h))) tall", isDefault: h == 86)
        }
        return g.build()
    }

    static func metalDrawerBox() -> ComponentDefinition {
        var g = ShapeA(ComponentBuilder("Metal Drawer Box", .drawers, "Drawer Boxes", "Complete metal drawer box: double-wall sides, steel back and a melamine bottom.",
                                        frame: .legacyOpening))
        g.b.material(finish, .stainless)
        g.b.material("Bottom Material", melamine)
        g.b.tags("drawer box", "metal drawer", "box system", "steel", "kitchen drawer")
        g.b.aliases("metal drawer boxes", "steel drawer box", "drawer system", "box system drawer", "metal box drawer")
        g.b.length("Nominal Length", mm(500), instance: true); g.b.length("Side Height", mm(86)); g.b.length("Side Width", mm(16)); g.b.length("Back Height", mm(70))
        g.b.length("Bottom Thickness", mm(16), group: .manufacturing); g.b.length("Opening Width", inch(15), instance: true); g.b.length("Side Clearance", mm(5), group: .manufacturing)
        g.b.length("Box Width", 0, formula: "Opening Width - 2 * Side Clearance")
        g.b.number("Load Capacity", 88, unit: "lb")
        g.b.host([.bay], faces: [.inside], align: .bottom)
        g.b.requires(.fitsDepth("Nominal Length + 0.01 m"))
        let xl = "Side Clearance", xr = "Opening Width - Side Clearance", L = "Nominal Length"
        g.prism("Left Side", along: 1, profile: doubleWall(xl, 1, height: "Side Height"), range: (CX.mm(10), "\(L) - 0.01 m"))
        g.prism("Right Side", along: 1, profile: doubleWall(xr, -1, height: "Side Height"), range: (CX.mm(10), "\(L) - 0.01 m"))
        g.box("Back", a: ("\(xl) + Side Width", "\(xr) - Side Width"), b: ("\(L) - 0.025 m", "\(L) - 0.023 m"), c: (CX.mm(4), "Back Height"))
        g.using("Bottom Material")
        g.box("Bottom", a: ("\(xl) + Side Width", "\(xr) - Side Width"), b: (CX.mm(10), "\(L) - 0.025 m"), c: (CX.mm(4), "0.004 m + Bottom Thickness"))
        g.using(nil)
        g.b.symbol(.top, [.coarse], .rect((xl, CX.zero), (xr, L)))
        g.b.symbol(.side, [.coarse], .rect((CX.zero, CX.zero), (L, "Side Height")))
        for (h, n, cost) in [(86.0, "Low", 58.00), (118, "Medium", 66.00), (167, "High", 79.00)] {
            g.b.type("Metal Drawer Box - \(Int(h)) mm \(n)", ["Side Height": mm(h), "Back Height": mm(h - 16)], cost: cost, model: "MDB-\(Int(h))",
                     description: "Metal drawer box, \(Int(h)) mm (\(TradeA.inchWord(h))) sides, cut to the bay's width", isDefault: h == 86)
        }
        return g.build()
    }

    static func woodenDrawerBox() -> ComponentDefinition {
        var g = ShapeA(ComponentBuilder("Wooden Drawer Box", .drawers, "Drawer Boxes", "Dovetailed solid wood drawer box with a plywood bottom in a groove.", frame: .legacyOpening))
        g.b.material("Box Material", .maple)
        g.b.material("Bottom Material", birchPly)
        g.b.tags("drawer box", "wooden", "dovetail", "solid wood", "maple")
        g.b.aliases("wooden drawer boxes", "wood drawer box", "dovetail drawer", "solid wood drawer", "drawer carcass")
        g.b.length("Box Width", inch(14), instance: true); g.b.length("Box Depth", inch(18), instance: true); g.b.length("Box Height", inch(4))
        g.b.length("Side Thickness", inch(0.5)); g.b.length("Bottom Thickness", inch(0.25)); g.b.length("Bottom Inset", inch(0.5), group: .manufacturing)
        g.b.length("Opening Width", inch(15), instance: true); g.b.length("Side Clearance", inch(0.5), group: .manufacturing)
        g.b.host([.bay], faces: [.inside], align: .bottom)
        g.b.requires(.fitsDepth("Box Depth + 0.0127 m"))
        // The box sits Side Clearance in from the left side (where the slides go).
        let x0 = "Side Clearance", x1 = "Side Clearance + Box Width", t = "Side Thickness", d = "Box Depth", h = "Box Height"
        g.box("Left Side", a: (x0, "\(x0) + \(t)"), b: (CX.zero, d), c: (CX.zero, h))
        g.box("Right Side", a: ("\(x1) - \(t)", x1), b: (CX.zero, d), c: (CX.zero, h))
        g.box("Front", a: ("\(x0) + \(t)", "\(x1) - \(t)"), b: (CX.zero, t), c: (CX.zero, h))
        g.box("Back", a: ("\(x0) + \(t)", "\(x1) - \(t)"), b: ("\(d) - \(t)", d), c: ("Bottom Inset + Bottom Thickness", h))
        g.using("Bottom Material")
        g.box("Bottom", a: ("\(x0) + \(t) * 0.5", "\(x1) - \(t) * 0.5"), b: ("\(t) * 0.5", "\(d) - \(t) * 0.5"), c: ("Bottom Inset", "Bottom Inset + Bottom Thickness"))
        g.using(nil)
        // Fine: dovetail pins showing on the sides at the front corners.
        let saved = g.levels
        g.levels = [.fine]
        for k in 0..<3 {
            let z0 = 0.12 + 0.3 * Double(k), z1 = z0 + 0.16
            for (n, a) in [("Left", ("\(x0) - 0.0003 m", x0)), ("Right", (x1, "\(x1) + 0.0003 m"))] {
                g.box("\(n) Dovetail \(k + 1)", a: a, b: (CX.zero, "\(t) * 0.9"), c: ("\(h) * \(LX.num(z0))", "\(h) * \(LX.num(z1))"))
            }
        }
        g.levels = saved
        g.b.symbol(.top, [.coarse], .rect((x0, CX.zero), (x1, d)))
        g.b.symbol(.side, [.coarse], .rect((CX.zero, CX.zero), (d, h)))
        for (hh, cost) in [(4.0, 38.00), (6.0, 46.00), (8.0, 54.00)] {
            g.b.type("Wooden Drawer Box - \(Int(hh))\"", ["Box Height": inch(hh)], cost: cost, model: "WDB-\(Int(hh))",
                     description: "Dovetailed maple drawer box, \(Int(hh))\" (\(Int(hh * 25.4)) mm) tall, 1/2\" sides, 1/4\" bottom", isDefault: hh == 4)
        }
        return g.build()
    }

    // MARK: Small drawer fittings

    static func bottomSupport() -> ComponentDefinition {
        var g = faced("Drawer Bottom Support", .drawers, "Drawer Fittings", "Corner bracket under a drawer's bottom, screwed to the box side.", frame: .plan)
        g.b.material(finish, .greyPlastic)
        g.b.tags("bottom support", "drawer bottom", "corner bracket", "clip")
        g.b.aliases("drawer bottom supports", "bottom clip", "drawer bottom bracket", "bottom panel support", "drawer base clip")
        g.b.length("Length", mm(30)); g.b.length("Width", mm(20)); g.b.length("Leg Height", mm(20)); g.b.length("Thickness", mm(2.5))
        g.b.host([.bottom, .shelf], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .center])
        g.b.drill("Support screw", x: "Length * 0.6", y: "Width / 2", diameter: CX.mm(3), depth: CX.mm(8))
        // Under the bottom (negative Z): a plate along the box side (at x = 0) and a leg up it.
        g.prism("Plate", along: 2, profile: [(CX.zero, CX.zero), ("Length", CX.zero), ("Length", "Width * 0.4"), ("Width * 0.4", "Width"), (CX.zero, "Width")], range: ("-Thickness", CX.zero))
        g.box("Leg", a: ("-Thickness", CX.zero), b: (CX.zero, "Width"), c: ("-Thickness", "Leg Height"))
        g.prism("Gusset", along: 1, profile: [("-Thickness", "-Thickness"), ("Length * 0.6", "-Thickness"), ("-Thickness", "Leg Height * 0.7")], range: ("Width / 2 - 0.001 m", "Width / 2 + 0.001 m"))
        g.b.symbol(.face, [.coarse], .rect((CX.zero, CX.zero), ("Length", "Width")))
        g.b.type("Drawer Bottom Support - Plastic", [:], cost: 0.20, model: "DBS-P", description: "Plastic drawer bottom support", isDefault: true)
        g.b.type("Drawer Bottom Support - Metal", ["Thickness": mm(1.5), "Length": mm(35)], cost: 0.35, model: "DBS-M", description: "Steel drawer bottom support")
        return g.build()
    }

    static func frontConnector() -> ComponentDefinition {
        var g = faced("Drawer Front Connector", .drawers, "Drawer Fittings", "Front fixing bracket: clips a drawer front to its box and adjusts it up, down and sideways.")
        g.b.material(finish, .zinc)
        g.b.material("Cam Material", .greyPlastic)
        g.b.tags("front connector", "front fixing", "drawer front", "adjuster", "front bracket")
        g.b.aliases("drawer front connectors", "front fixing bracket", "front adjuster", "drawer front bracket", "front clip")
        g.b.length("Plate Width", mm(30)); g.b.length("Plate Height", mm(50)); g.b.length("Bore Diameter", mm(20)); g.b.length("Bore Depth", mm(11))
        g.b.host([.drawerFront], faces: [.inside], align: .left, alignments: [.left, .right], offsetX: mm(45), offsetY: mm(40), mirroredPair: true)
        g.b.drill("Front connector bore", x: CX.zero, y: CX.zero, diameter: "Bore Diameter", depth: "Bore Depth")
        // Origin: the bore in the front's back face; the bracket stands out behind it (c into the box).
        g.cylinder("Dowel", along: 2, radius: "Bore Diameter / 2 - 0.0005 m", range: ("-Bore Depth + 0.001 m", CX.zero), segments: 20)
        g.prism("Plate", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Plate Width", "Plate Height", CX.mm(4)), range: (CX.zero, CX.mm(2)))
        g.box("Tongue", a: ("-Plate Width / 2 + 0.004 m", "Plate Width / 2 - 0.004 m"), b: ("-Plate Height / 2 + 0.006 m", "Plate Height / 2 - 0.006 m"), c: (CX.mm(2), CX.mm(14)))
        g.using("Cam Material")
        g.revolve("Height Adjuster", along: 2, center: (CX.zero, "Plate Height * 0.25"), profile: PtsA.turned(CX.mm(6), CX.mm(3), base: CX.mm(14), [(0, 0), (1, 0), (1, 0.7), (0.8, 1), (0, 1)]))
        g.revolve("Side Adjuster", along: 2, center: (CX.zero, "-Plate Height * 0.25"), profile: PtsA.turned(CX.mm(5), CX.mm(3), base: CX.mm(14), [(0, 0), (1, 0), (1, 0.7), (0.8, 1), (0, 1)]))
        g.using(nil)
        g.b.symbol(.face, [.coarse], .rect(("-Plate Width / 2", "-Plate Height / 2"), ("Plate Width / 2", "Plate Height / 2")))
        g.b.type("Drawer Front Connector - Bore 20 mm", [:], cost: 1.10, model: "DFC-20", description: "Front fixing bracket, 20 mm bore, 2-way adjustment", isDefault: true)
        g.b.type("Drawer Front Connector - Screw-On", ["Bore Depth": mm(3), "Bore Diameter": mm(8)], cost: 0.85, model: "DFC-S", description: "Screw-on front fixing bracket, no bore")
        return g.build()
    }

    static func drawerDivider() -> ComponentDefinition {
        var g = ShapeA(ComponentBuilder("Drawer Divider", .drawers, "Drawer Inserts", "Aluminium divider rail across or along a drawer, clipped to its sides.", frame: .legacyOpening))
        g.b.material(finish, .aluminum)
        g.b.material("Clip Material", .greyPlastic)
        g.b.tags("divider", "drawer divider", "rail", "partition", "organizer")
        g.b.aliases("drawer dividers", "drawer partition", "divider rail", "cross divider", "longitudinal divider", "drawer separator")
        g.b.length("Length", mm(450), instance: true); g.b.length("Height", mm(75)); g.b.length("Thickness", mm(10))
        g.b.length("Divider Position", mm(150), instance: true, group: .placement)
        g.b.flag("Cross Divider", false, instance: false, group: .dimensions)
        g.b.host([.bay], faces: [.bottom], align: .center)
        // Along the drawer (b) at Divider Position, or across it (a) at that depth.
        g.variant("Cross Divider", when: false) { g in
            g.prism("Divider", along: 1, profile: PtsA.rounded(("Divider Position", "Height / 2"), "Thickness", "Height", "Thickness * 0.45"), range: (CX.mm(10), "Length - 0.01 m"))
            g.using("Clip Material")
            for (n, r) in [("Front Clip", (CX.zero, CX.mm(10))), ("Back Clip", ("Length - 0.01 m", "Length"))] {
                g.box(n, a: ("Divider Position - Thickness", "Divider Position + Thickness"), b: r, c: (CX.zero, "Height * 0.6"))
            }
            g.using(nil)
        }
        g.variant("Cross Divider") { g in
            g.prism("Divider", along: 0, profile: PtsA.rounded(("Divider Position", "Height / 2"), "Thickness", "Height", "Thickness * 0.45"), range: (CX.mm(10), "Length - 0.01 m"))
            g.using("Clip Material")
            for (n, r) in [("Left Clip", (CX.zero, CX.mm(10))), ("Right Clip", ("Length - 0.01 m", "Length"))] {
                g.box(n, a: r, b: ("Divider Position - Thickness", "Divider Position + Thickness"), c: (CX.zero, "Height * 0.6"))
            }
            g.using(nil)
        }
        g.b.symbol(.top, [.coarse], .rect(("Divider Position - Thickness / 2", CX.zero), ("Divider Position + Thickness / 2", "Length")))
        g.b.type("Drawer Divider - Longitudinal 75 mm", [:], cost: 9.50, model: "DDV-L75", description: "Longitudinal drawer divider, 75 mm (3\") tall, cut to length", isDefault: true)
        g.b.type("Drawer Divider - Cross 75 mm", ["Length": inch(14)], flags: ["Cross Divider": true], cost: 9.50, model: "DDV-C75",
                 description: "Cross drawer divider, 75 mm (3\") tall, cut to the drawer's width")
        return g.build()
    }

    /// A tray on the drawer bottom (plan frame: origin at its front-left corner): its base, rim and inner walls.
    static func tray(_ g: inout ShapeA, walls: [(String, (String, String), (String, String))]) {
        g.box("Base", a: (CX.zero, "Width"), b: (CX.zero, "Depth"), c: (CX.zero, "Wall"))
        g.box("Front Rim", a: (CX.zero, "Width"), b: (CX.zero, "Wall"), c: (CX.zero, "Height"))
        g.box("Back Rim", a: (CX.zero, "Width"), b: ("Depth - Wall", "Depth"), c: (CX.zero, "Height"))
        g.box("Left Rim", a: (CX.zero, "Wall"), b: (CX.zero, "Depth"), c: (CX.zero, "Height"))
        g.box("Right Rim", a: ("Width - Wall", "Width"), b: (CX.zero, "Depth"), c: (CX.zero, "Height"))
        for (n, a, b) in walls { g.box(n, a: a, b: b, c: (CX.zero, "Height * 0.85")) }
        g.b.symbol(.face, [.coarse], .rect((CX.zero, CX.zero), ("Width", "Depth")))
    }

    static func drawerOrganizer() -> ComponentDefinition {
        var g = faced("Drawer Organizer", .drawers, "Drawer Inserts", "Moulded insert with a grid of compartments on the drawer's bottom.", frame: .plan)
        g.b.material(finish, .greyPlastic)
        g.b.tags("organizer", "insert", "compartments", "tray", "storage")
        g.b.aliases("drawer organizers", "drawer insert", "drawer tray", "compartment tray", "junk drawer organizer", "drawer organiser")
        g.b.length("Width", inch(14), instance: true); g.b.length("Depth", inch(18), instance: true); g.b.length("Height", mm(50)); g.b.length("Wall", mm(3), group: .manufacturing)
        g.b.host([.bay, .shelf, .bottom], faces: [.top], align: .center)
        tray(&g, walls: [("Divider 1", ("Width / 3 - Wall / 2", "Width / 3 + Wall / 2"), ("Wall", "Depth - Wall")),
                         ("Divider 2", ("Width * 2 / 3 - Wall / 2", "Width * 2 / 3 + Wall / 2"), ("Wall", "Depth - Wall")),
                         ("Cross Divider", ("Wall", "Width - Wall"), ("Depth / 2 - Wall / 2", "Depth / 2 + Wall / 2"))])
        g.b.type("Drawer Organizer - 50 mm", [:], cost: 18.00, model: "DOR-50", description: "Drawer organizer, 6 compartments, 50 mm (2\") deep, cut to the drawer", isDefault: true)
        g.b.type("Drawer Organizer - 75 mm", ["Height": mm(75)], cost: 22.00, model: "DOR-75", description: "Drawer organizer, 6 compartments, 75 mm (3\") deep")
        return g.build()
    }

    static func cutleryTray() -> ComponentDefinition {
        var g = faced("Cutlery Tray", .drawers, "Drawer Inserts", "Cutlery insert: four long compartments and a cross tray at the back.", frame: .plan)
        g.b.material(finish, .beech)
        g.b.tags("cutlery", "silverware", "flatware", "kitchen", "insert")
        g.b.aliases("cutlery trays", "cutlery insert", "silverware tray", "flatware organizer", "utensil tray", "cutlery divider")
        g.b.length("Width", mm(400)); g.b.length("Depth", mm(450), instance: true); g.b.length("Height", mm(50)); g.b.length("Wall", mm(6), group: .manufacturing)
        g.b.host([.bay, .bottom], faces: [.top], align: .center)
        var walls: [(String, (String, String), (String, String))] = []
        for k in 1...3 { walls.append(("Divider \(k)", ("Width * \(k) / 4 - Wall / 2", "Width * \(k) / 4 + Wall / 2"), ("Wall", "Depth * 0.72"))) }
        walls.append(("Back Divider", ("Wall", "Width - Wall"), ("Depth * 0.72", "Depth * 0.72 + Wall")))
        tray(&g, walls: walls)
        for (w, cost) in [(400.0, 34.00), (500, 39.00), (600, 44.00)] {
            g.b.type("Cutlery Tray - \(Int(w)) mm", ["Width": mm(w - 50)], cost: cost, model: "CTL-\(Int(w))",
                     description: "Cutlery tray for a \(Int(w)) mm (\(TradeA.inchWord(w))) cabinet, beech", isDefault: w == 400)
        }
        return g.build()
    }

    static func drawerPushLock() -> ComponentDefinition {
        var g = faced("Drawer Push Lock", .drawers, "Drawer Fittings", "Push-button plunger lock through a drawer front: press to lock, key to release.")
        g.b.material(finish, .chrome)
        g.b.material("Cylinder Material", .brass)
        g.b.tags("drawer lock", "push lock", "plunger lock", "keyed", "push button")
        g.b.aliases("drawer locks", "push button lock", "plunger lock", "push-in drawer lock", "drawer plunger lock")
        g.b.length("Diameter", mm(19)); g.b.length("Head Diameter", mm(24)); g.b.length("Cylinder Length", mm(22)); g.b.length("Plunger Throw", mm(10))
        g.b.length("Front Thickness", inch(0.75), instance: true, group: .placement)
        g.b.host([.drawerFront], faces: [.front], align: .top, alignments: [.top, .center], offsetY: inch(1))
        g.b.drill("Lock cylinder", x: CX.zero, y: CX.zero, diameter: "Diameter", depth: "Host Thickness", through: true)
        g.b.requires(.hostThickness(min: nil, max: "Cylinder Length - 0.002 m"))
        keyCylinder(&g)
        g.box("Plunger Housing", a: (CX.mm(-7), CX.mm(7)), b: (CX.mm(-10), CX.mm(10)), c: ("-Cylinder Length - 0.014 m", "-Cylinder Length"))
        g.cylinder("Plunger", along: 1, center: (CX.zero, "-Cylinder Length - 0.007 m"), radius: CX.mm(4), range: (CX.mm(10), "0.01 m + Plunger Throw"), segments: 16)
        g.b.symbol(.face, [.coarse], .circle((CX.zero, CX.zero), "Head Diameter / 2"))
        g.b.type("Drawer Push Lock - 19 mm", [:], cost: 7.25, model: "DPL-19", description: "Push-button drawer lock, 19 mm (3/4\") body, chrome", isDefault: true)
        g.b.type("Drawer Push Lock - 16 mm", ["Diameter": mm(16), "Head Diameter": mm(20), "Cylinder Length": mm(20)], cost: 6.50, model: "DPL-16",
                 description: "Push-button drawer lock, 16 mm (5/8\") body")
        return g.build()
    }

    static func drawerDamper() -> ComponentDefinition {
        var g = faced("Drawer Damper", .drawers, "Drawer Fittings", "Add-on soft-close damper at the back of the carcass side; the drawer's back meets its piston.")
        g.b.material(finish, .greyPlastic)
        g.b.material("Piston Material", .stainless)
        g.b.tags("damper", "soft close", "add on", "buffer", "retrofit")
        g.b.aliases("drawer dampers", "soft close adapter", "drawer buffer", "add-on damper", "retrofit soft close")
        g.b.length("Body Length", mm(80)); g.b.length("Body Diameter", mm(14)); g.b.length("Stroke", mm(25)); g.b.number("Damping Force", 40, unit: "N")
        g.b.host([.sidePanel, .back], faces: [.inside], align: .bottom, alignments: [.bottom, .center], offsetY: mm(30))
        g.b.drill("Damper screw", x: "Body Length * 0.2", y: CX.zero, diameter: CX.mm(3.5), depth: CX.mm(12))
        g.b.drill("Damper screw", x: "Body Length * 0.8", y: CX.zero, diameter: CX.mm(3.5), depth: CX.mm(12))
        // Origin: the side's inside face at the damper's front end; the piston points to the front (-a).
        g.box("Mounting Plate", a: (CX.zero, "Body Length"), b: ("-Body Diameter * 0.8", "Body Diameter * 0.8"), c: (CX.zero, CX.mm(2.5)))
        g.cylinder("Body", along: 0, center: (CX.zero, "Body Diameter / 2 + 0.0025 m"), radius: "Body Diameter / 2", range: (CX.mm(5), "Body Length"), segments: 20)
        g.using("Piston Material")
        g.cylinder("Piston", along: 0, center: (CX.zero, "Body Diameter / 2 + 0.0025 m"), radius: "Body Diameter * 0.18", range: ("-Stroke", CX.mm(5)), segments: 14)
        g.revolve("Bumper", along: 0, center: (CX.zero, "Body Diameter / 2 + 0.0025 m"), profile: [(CX.zero, "-Stroke - 0.005 m"), ("Body Diameter * 0.35", "-Stroke - 0.004 m"),
                                                                                                    ("Body Diameter * 0.38", "-Stroke"), (CX.zero, "-Stroke")])
        g.using(nil)
        g.b.symbol(.face, [.coarse], .rect(("-Stroke", "-Body Diameter / 2"), ("Body Length", "Body Diameter / 2")))
        g.b.type("Drawer Damper - Standard", [:], cost: 5.50, model: "DDM-80", description: "Add-on drawer damper, 25 mm (1\") stroke", isDefault: true)
        g.b.type("Drawer Damper - Heavy Drawer", ["Body Length": mm(100), "Body Diameter": mm(16), "Stroke": mm(30)], numbers: ["Damping Force": 70], cost: 7.25, model: "DDM-100",
                 description: "Add-on damper for heavy drawers, 30 mm stroke")
        return g.build()
    }

    static func drawerStop() -> ComponentDefinition {
        var g = faced("Drawer Stop", .drawers, "Drawer Fittings", "Stop block with a rubber bumper that sets how far a drawer closes.")
        g.b.material(finish, .greyPlastic)
        g.b.material("Bumper Material", .rubber)
        g.b.tags("stop", "drawer stop", "bumper", "buffer", "end stop")
        g.b.aliases("drawer stops", "drawer bumper", "end stop", "drawer buffer", "closing stop")
        g.b.length("Width", mm(25)); g.b.length("Height", mm(20)); g.b.length("Depth", mm(12)); g.b.length("Bumper Diameter", mm(10))
        g.b.host([.back, .sidePanel, .bottom], faces: [.inside, .top], align: .bottom, alignments: [.bottom, .center])
        g.b.drill("Stop screw", x: CX.zero, y: CX.zero, diameter: CX.mm(3.5), depth: CX.mm(12))
        g.prism("Block", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Width", "Height", CX.mm(3)), range: (CX.zero, "Depth"))
        g.using("Bumper Material")
        g.revolve("Bumper", along: 2, profile: PtsA.turned("Bumper Diameter / 2", CX.mm(4), base: "Depth", [(0, 0), (1, 0), (1, 0.4), (0.7, 0.9), (0, 1)]))
        g.using(nil)
        g.b.symbol(.face, [.coarse], .rect(("-Width / 2", "-Height / 2"), ("Width / 2", "Height / 2")))
        g.b.type("Drawer Stop - Standard", [:], cost: 0.65, model: "DST-25", description: "Drawer stop block with rubber bumper", isDefault: true)
        g.b.type("Drawer Stop - Adjustable", ["Depth": mm(18)], cost: 1.25, model: "DST-ADJ", description: "Adjustable drawer stop, 6 mm (1/4\") travel")
        return g.build()
    }

    static func syncRod() -> ComponentDefinition {
        var g = ShapeA(ComponentBuilder("Drawer Synchronization Rod", .drawers, "Drawer Fittings", "Rod across a wide drawer joining both runners, so it runs square.", frame: .legacyOpening))
        g.b.material(finish, .zinc)
        g.b.material("Gear Material", .blackPlastic)
        g.b.tags("synchronization", "sync rod", "wide drawer", "anti rack", "undermount")
        g.b.aliases("drawer synchronization rods", "sync rod", "synchronisation bar", "anti-racking rod", "wide drawer stabilizer")
        g.b.length("Opening Width", inch(30), instance: true); g.b.length("Rod Diameter", mm(10)); g.b.length("Mount Height", mm(25), instance: true, group: .placement)
        g.b.length("Setback", mm(60), group: .placement); g.b.length("Rod Length", 0, formula: "Opening Width - 0.042 m")
        g.b.host([.bay], faces: [.inside], align: .bottom)
        g.b.requires(.hostWidth(min: CX.inch(24), max: nil))
        g.prism("Rod", along: 0, profile: PtsA.polygon(("Setback", "Mount Height"), "Rod Diameter / 2", sides: 6, start: 30), range: (CX.mm(21), "Opening Width - 0.021 m"))
        g.using("Gear Material")
        for (n, r) in [("Left Pinion", (CX.mm(9), CX.mm(21))), ("Right Pinion", ("Opening Width - 0.021 m", "Opening Width - 0.009 m"))] {
            g.cylinder(n, along: 0, center: ("Setback", "Mount Height"), radius: CX.mm(11), range: r, segments: 20)
        }
        g.using(nil)
        g.b.symbol(.top, [.coarse], .line((CX.zero, "Setback"), ("Opening Width", "Setback")))
        g.b.type("Drawer Synchronization Rod - Cut to Width", [:], cost: 12.00, model: "SYN-1200", description: "Synchronization rod, cut to the opening up to 1200 mm (47\")", isDefault: true)
        return g.build()
    }

    static func drawerStabilizer() -> ComponentDefinition {
        var g = ShapeA(ComponentBuilder("Drawer Stabilizer", .drawers, "Drawer Fittings", "Lateral stabilizer: a bar across the back and a gear rack on each side keep a wide drawer from swaying.",
                                        frame: .legacyOpening))
        g.b.material(finish, .zinc)
        g.b.material("Rack Material", .blackPlastic)
        g.b.tags("stabilizer", "lateral", "gallery", "wide drawer", "anti sway")
        g.b.aliases("drawer stabilizers", "lateral stabiliser", "anti-sway kit", "drawer stabilizer bar", "gallery rail")
        g.b.length("Opening Width", inch(30), instance: true); g.b.length("Rack Length", mm(450)); g.b.length("Bar Diameter", mm(10)); g.b.length("Mount Height", mm(60), instance: true, group: .placement)
        g.b.host([.bay], faces: [.inside], align: .bottom)
        g.b.requires(.hostWidth(min: CX.inch(30), max: nil))
        g.cylinder("Bar", along: 0, center: ("Rack Length - 0.03 m", "Mount Height"), radius: "Bar Diameter / 2", range: (CX.mm(14), "Opening Width - 0.014 m"), segments: 18)
        g.using("Rack Material")
        for (n, a) in [("Left Rack", (CX.zero, CX.mm(10))), ("Right Rack", ("Opening Width - 0.01 m", "Opening Width"))] {
            g.box(n, a: a, b: (CX.mm(20), "Rack Length"), c: ("Mount Height - 0.008 m", "Mount Height + 0.008 m"))
            let saved = g.levels
            g.levels = [.fine]
            for k in 0..<8 {
                let y = 0.1 + 0.1 * Double(k)
                g.box("\(n) Tooth \(k + 1)", a: a, b: ("Rack Length * \(LX.num(y))", "Rack Length * \(LX.num(y)) + 0.004 m"), c: ("Mount Height + 0.008 m", "Mount Height + 0.0105 m"))
            }
            g.levels = saved
        }
        g.using(nil)
        g.b.symbol(.top, [.coarse], .line((CX.zero, "Rack Length - 0.03 m"), ("Opening Width", "Rack Length - 0.03 m")))
        g.b.type("Drawer Stabilizer - 450 mm", [:], cost: 16.00, model: "DSB-450", description: "Lateral drawer stabilizer, 450 mm (17 3/4\") racks", isDefault: true)
        g.b.type("Drawer Stabilizer - 550 mm", ["Rack Length": mm(550)], cost: 18.00, model: "DSB-550", description: "Lateral drawer stabilizer, 550 mm (21 5/8\") racks")
        return g.build()
    }
}

extension GroupA {
    /// A range's ends in increasing order for a side that runs `s` (+1: as given, -1: swapped).
    static func pairRange(_ r: (String, String), _ s: Double) -> (String, String) { s > 0 ? r : (r.1, r.0) }
}
