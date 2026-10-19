import Foundation
import ArcusGeometry

// COMPA: 01 Handles, Knobs & Pulls (22). Screw-on handles use FM5's front frame (a along the handle, b across it, c out
// of the face) so fronts place them; FM5's Bar Pull, Knob, Cup Pull and Edge Pull are upgraded in place. Flush,
// recessed and profile handles (machined into or fixed along the front) are face-based components.

extension GroupA {
    static var handles: [ComponentDefinition] {
        [barPull(), tBarHandle(), bowHandle(), dPull(), edgePull(), recessedPull(), flushPull(), fingerPull(), cupPull(), ringPull(),
         dropHandle(), knob(), mushroomKnob(), squareKnob(), crystalKnob(), leatherPull(), woodenHandle(), integratedHandle(),
         jPull(), golaProfile(), pushToOpen(), touchLatch()]
    }

    /// A face-based (or plan) Group A component.
    static func faced(_ name: String, _ category: ComponentCategory, _ sub: String, _ description: String, frame: ComponentFrame = .face) -> ShapeA {
        ShapeA(ComponentBuilder(name, category, sub, description, frame: frame))
    }

    /// The aliases of handle centre-to-centre sizes ("128 mm", "128mm", "5\"", "128 mm cc").
    static func ccAliases(_ b: inout ComponentBuilder, _ ccs: [Double]) {
        for cc in ccs {
            for a in TradeA.sizeAliases(cc) + ["\(LX.num(cc)) mm cc", "\(LX.num(cc)) mm centers"] where !b.definition.aliases.contains(a) { b.definition.aliases.append(a) }
        }
    }

    // MARK: Bar Pull (FM5 upgrade)

    static func barPull() -> ComponentDefinition {
        var g = handle(F.barPull, "Bar Handles", "Round bar on two posts, screwed through the front.", finish: .satinNickel, upgrading: F.barPull)
        g.b.tags("bar", "rail", "modern")
        g.b.aliases("bar handle", "bar pull", "rail handle", "cabinet handle", "kitchen handle", "tube handle")
        ccAliases(&g.b, [96, 128, 160, 192])
        postHoles(&g.b)
        fingerSpace(&g.b)
        g.b.requires(.fitsWidth("Length + 0.0254 m"))
        let R = "Bar Diameter / 2", e = "Length / 2", cBar = "Projection - Bar Diameter / 2"
        g.revolve("Bar", along: 0, center: (CX.zero, cBar), profile: [
            (CX.zero, "-(\(e))"), ("(\(R)) * 0.6", "-(\(e))"), ("(\(R)) * 0.9", "-(\(e)) + (\(R)) * 0.15"), (R, "-(\(e)) + (\(R)) * 0.5"),
            (R, "\(e) - (\(R)) * 0.5"), ("(\(R)) * 0.9", "\(e) - (\(R)) * 0.15"), ("(\(R)) * 0.6", e), (CX.zero, e)])
        for s in ["-", ""] {
            let pr = "Post Diameter / 2"
            g.revolve("Post", along: 2, center: ("\(s)Hole Spacing / 2", CX.zero), profile: [
                (CX.zero, CX.zero), ("(\(pr)) * 1.3", CX.zero), ("(\(pr)) * 1.3", CX.mm(1.2)), (pr, CX.mm(3.5)), (pr, cBar), (CX.zero, cBar)])
        }
        g.screws("Screw Head", at: [("-Hole Spacing / 2", CX.zero), ("Hole Spacing / 2", CX.zero)], c: "-Front Thickness", diameter: CX.mm(7), outward: false)
        coarse(&g, length: "Length", height: "Bar Diameter", projection: "Projection")
        let renames: [String: String] = ["96 mm": "Bar Pull - 96 mm CC", "128 mm": "Bar Pull - 128 mm CC", "160 mm": "Bar Pull - 160 mm CC", "192 mm": "Bar Pull - 192 mm CC"]
        g.b.renames(renames)
        for (cc, cost) in [(96.0, 4.50), (128, 5.25), (160, 6.25), (192, 7.50)] {
            g.b.type("Bar Pull - \(Int(cc)) mm CC", ["Hole Spacing": mm(cc), "Length": mm(cc + 36), "Bar Diameter": mm(12), "Projection": mm(34), "Post Diameter": mm(10),
                                                     "Hole Diameter": mm(5)], flags: ["Vertical": false, "On Lid": false],
                     cost: cost, model: "BP-\(Int(cc))", description: "Bar pull, \(Int(cc)) mm (\(TradeA.inchWord(cc))) centers, 12 mm bar, satin nickel", isDefault: cc == 128)
        }
        return g.build()
    }

    // MARK: T-Bar Handle

    static func tBarHandle() -> ComponentDefinition {
        var g = handle("T-Bar Handle", "Bar Handles", "Solid bar on two flat T-shaped legs.", finish: .stainless)
        g.b.tags("t-bar", "bar", "modern", "stainless")
        g.b.aliases("t bar pull", "tbar handle", "t-bar pull", "euro bar pull")
        ccAliases(&g.b, [128, 160, 192, 256])
        g.b.length("Width", mm(188)); g.b.length("Height", mm(35)); g.b.length("Diameter", mm(12))
        g.b.length("Hole Spacing", mm(128), group: .manufacturing); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        g.b.length("Length", mm(188), formula: "Width")
        postHoles(&g.b)
        fingerSpace(&g.b, length: "Width", projection: "Height")
        g.b.requires(.fitsWidth("Width + 0.0254 m"))
        let R = "Diameter / 2", e = "Width / 2", cBar = "Height - Diameter / 2"
        g.revolve("Bar", along: 0, center: (CX.zero, cBar), profile: [
            (CX.zero, "-(\(e))"), ("(\(R)) * 0.92", "-(\(e))"), (R, "-(\(e)) + 0.0008 m"), (R, "\(e) - 0.0008 m"), ("(\(R)) * 0.92", e), (CX.zero, e)])
        for s in ["-", ""] {
            let x = "\(s)Hole Spacing / 2"
            g.prism("Leg", along: 2, profile: PtsA.rounded((x, CX.zero), CX.mm(6), "Diameter * 0.75", CX.mm(1.5)), range: (CX.mm(1.5), cBar))
            g.prism("Foot", along: 2, profile: PtsA.rounded((x, CX.zero), CX.mm(10), "Diameter", CX.mm(2.5)), range: (CX.zero, CX.mm(2)))
        }
        coarse(&g, length: "Width", height: "Diameter", projection: "Height")
        for (cc, cost) in [(128.0, 6.75), (160, 7.75), (192, 8.75), (256, 10.50)] {
            g.b.type("T-Bar Handle - \(Int(cc)) mm CC", ["Hole Spacing": mm(cc), "Width": mm(cc + 60)], flags: ["Vertical": false, "On Lid": false],
                     cost: cost, model: "TB-\(Int(cc))", description: "T-bar handle, \(Int(cc)) mm (\(TradeA.inchWord(cc))) centers, brushed stainless", isDefault: cc == 128)
        }
        return g.build()
    }

    // MARK: Bow Handle

    static func bowHandle() -> ComponentDefinition {
        var g = handle("Bow Handle", "Bow Handles", "Arched (bow) handle on two feet.", finish: .bronze)
        g.b.tags("bow", "arch", "curved", "traditional")
        g.b.aliases("arch handle", "bow pull", "curved handle", "arched pull", "bridge pull")
        ccAliases(&g.b, [96, 128, 160])
        g.b.length("Length", mm(106)); g.b.length("Projection", mm(30)); g.b.length("Diameter", mm(9))
        g.b.number("Curvature", 0.7, group: .dimensions)
        g.b.length("Hole Spacing", mm(96), group: .manufacturing); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        postHoles(&g.b)
        fingerSpace(&g.b)
        // The arch: a blend of a round arch (Curvature 1) and a flat-topped one (0), on the a–c plane.
        let n = 18
        let path: [(String, String)] = (0...n).map { k in
            let t = -1 + 2 * Double(k) / Double(n)
            let round = sin((t + 1) / 2 * .pi), flat = 1 - pow(abs(t), 6)
            return ("Hole Spacing / 2 * \(LX.num(t))", "(Projection - Diameter / 2) * (\(LX.num(flat)) + Curvature * \(LX.num(round - flat)))")
        }
        g.rod("Bow", plane: 0, 2, path: path, radius: "Diameter / 2")
        for s in ["-", ""] {
            g.revolve("Foot", along: 2, center: ("\(s)Hole Spacing / 2", CX.zero), profile: PtsA.turned("Diameter * 0.75", CX.mm(4), [(0, 0), (1, 0), (1, 0.35), (0.8, 0.8), (0.55, 1), (0, 1)]))
        }
        coarse(&g, length: "Length", height: "Diameter", projection: "Projection")
        for (cc, cost) in [(96.0, 5.50), (128, 6.50), (160, 7.75)] {
            g.b.type("Bow Handle - \(Int(cc)) mm CC", ["Hole Spacing": mm(cc), "Length": mm(cc + 10), "Projection": mm(cc > 100 ? 32 : 28)],
                     flags: ["Vertical": false, "On Lid": false], cost: cost, model: "BW-\(Int(cc))",
                     description: "Bow handle, \(Int(cc)) mm (\(TradeA.inchWord(cc))) centers, oil-rubbed bronze", isDefault: cc == 96)
        }
        return g.build()
    }

    // MARK: D-Pull Handle

    static func dPull() -> ComponentDefinition {
        var g = handle("D-Pull Handle", "Wire Pulls", "Round wire pull bent into a D.", finish: .matteBlack)
        g.b.tags("d pull", "wire", "d handle", "loop")
        g.b.aliases("d-handle", "wire pull", "d pull", "loop handle", "wire handle")
        ccAliases(&g.b, [96, 128, 160])
        g.b.length("Hole Spacing", mm(128), group: .dimensions); g.b.length("Height", mm(32)); g.b.length("Thickness", mm(10))
        g.b.length("Length", mm(138), formula: "Hole Spacing + Thickness")
        g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        postHoles(&g.b)
        fingerSpace(&g.b, length: "Hole Spacing", projection: "Height")
        let x = "Hole Spacing / 2", top = "Height - Thickness / 2", rc = "Height * 0.38"
        var path: [(String, String)] = [("-(\(x))", CX.zero)]
        path += PtsA.arc(("-(\(x)) + \(rc)", "\(top) - \(rc)"), rc, from: 180, sweep: -90, segments: 8)
        path += PtsA.arc(("\(x) - \(rc)", "\(top) - \(rc)"), rc, from: 90, sweep: -90, segments: 8)
        path.append((x, CX.zero))
        g.rod("Wire", plane: 0, 2, path: path, radius: "Thickness / 2")
        coarse(&g, length: "Hole Spacing + Thickness", height: "Thickness", projection: "Height")
        for (cc, cost) in [(96.0, 3.75), (128, 4.25), (160, 4.95)] {
            g.b.type("D-Pull Handle - \(Int(cc)) mm CC", ["Hole Spacing": mm(cc), "Height": mm(cc > 100 ? 32 : 28)], flags: ["Vertical": false, "On Lid": false],
                     cost: cost, model: "DP-\(Int(cc))", description: "D-pull, \(Int(cc)) mm (\(TradeA.inchWord(cc))) centers, 10 mm wire, matte black", isDefault: cc == 128)
        }
        return g.build()
    }

    // MARK: Edge Pull (FM5 upgrade)

    static func edgePull() -> ComponentDefinition {
        var g = handle(F.edgePull, "Edge Pulls", "Tab pull screwed to the front's top edge, its lip over the face.", finish: .satinNickel, upgrading: F.edgePull, edge: true)
        g.b.tags("edge", "tab", "lip", "minimal")
        g.b.aliases("tab pull", "edge handle", "lip pull", "edge pull")
        g.b.length("Depth", mm(16)); g.b.length("Projection", mm(10))
        g.b.choice("Mounting Position", ["Top Edge", "Bottom Edge", "Side Edge"], "Top Edge", instance: true, group: .placement)
        for s in ["-", ""] { g.b.drill("Edge pull screw", x: "\(s)Hole Spacing / 2", y: CX.zero, diameter: "Hole Diameter", depth: CX.mm(12)) }
        g.b.requires(.fitsWidth("Length"))
        // Origin: the front's top edge at its face. The plate sits on the edge, the lip hangs in front of the face.
        g.prism("Top Plate", along: 1, profile: PtsA.rounded((CX.zero, "(Projection - Depth) / 2"), "Length", "Projection + Depth", CX.mm(2)), range: (CX.zero, CX.mm(2)))
        g.prism("Lip", along: 0, profile: [(CX.mm(2), "Projection - 0.0025 m"), (CX.mm(2), "Projection"), ("-Lip + 0.002 m", "Projection"), ("-Lip", "Projection - 0.0008 m"),
                                         ("-Lip", "Projection - 0.0018 m"), ("-Lip + 0.0015 m", "Projection - 0.0025 m")], range: ("-Length / 2", "Length / 2"))
        g.screws("Screw Head", at: [("-Hole Spacing / 2", "-Depth / 2"), ("Hole Spacing / 2", "-Depth / 2")], c: CX.zero, diameter: CX.mm(5))
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", "-Lip"), ("Length / 2", CX.mm(2))))
        g.b.symbol(.top, [.coarse], .rect(("-Length / 2", "-Depth"), ("Length / 2", "Projection")))
        g.b.renames(["2\"": "Edge Pull - 2\"", "4\"": "Edge Pull - 4\""])
        for (l, cost) in [(2.0, 6.00), (4.0, 8.50), (6.0, 11.00)] {
            g.b.type("Edge Pull - \(Int(l))\"", ["Length": inch(l), "Lip": inch(0.75), "Hole Spacing": inch(l) * 0.6, "Hole Diameter": mm(3)],
                     flags: ["Vertical": false, "On Lid": false, "Edge Mounted": true], cost: cost, model: "EP-\(Int(l))",
                     description: "Edge pull, \(Int(l))\" (\(Int(l * 25.4)) mm), screwed to the top edge", isDefault: l == 2)
        }
        return g.build()
    }

    // MARK: Recessed Pull

    static func recessedPull() -> ComponentDefinition {
        var g = faced("Recessed Pull", .handles, "Flush & Recessed Pulls", "Rectangular pull set into a pocket in the front, flush with its face.")
        g.b.material(finish, .satinNickel)
        g.b.tags("recessed", "flush", "inset", "pocket", "pull")
        g.b.aliases("inset pull", "mortise pull", "recessed handle", "flush recessed pull", "sliding door pull")
        g.b.length("Width", mm(90)); g.b.length("Height", mm(40)); g.b.length("Depth", mm(12)); g.b.length("Flange", mm(3))
        g.b.choice("Shape", ["Rectangular", "Square"], "Rectangular")
        g.b.length("Wall", mm(1), group: .manufacturing)
        g.b.host(ComponentHostKind.fronts, faces: [.front], align: .center, alignments: [.center, .inside, .top], offsetX: inch(2.5), offsetY: inch(2.5))
        g.b.pocket("Recess", width: "Width - 2 * Flange", height: "Height - 2 * Flange", depth: "Depth")
        g.b.requires(.hostThickness(min: "Depth + 0.004 m", max: nil))
        let w = "Width / 2", h = "Height / 2", wi = "Width / 2 - Flange", hi = "Height / 2 - Flange", fl = CX.mm(0.8)
        // Flange frame proud of the face, the cup's walls and bottom behind it.
        g.box("Flange Top", a: ("-(\(w))", w), b: (hi, h), c: (CX.zero, fl))
        g.box("Flange Bottom", a: ("-(\(w))", w), b: ("-(\(h))", "-(\(hi))"), c: (CX.zero, fl))
        g.box("Flange Left", a: ("-(\(w))", "-(\(wi))"), b: ("-(\(hi))", hi), c: (CX.zero, fl))
        g.box("Flange Right", a: (wi, w), b: ("-(\(hi))", hi), c: (CX.zero, fl))
        g.box("Wall Top", a: ("-(\(wi))", wi), b: ("\(hi) - Wall", hi), c: ("-Depth", CX.zero))
        g.box("Wall Bottom", a: ("-(\(wi))", wi), b: ("-(\(hi))", "-(\(hi)) + Wall"), c: ("-Depth", CX.zero))
        g.box("Wall Left", a: ("-(\(wi))", "-(\(wi)) + Wall"), b: ("-(\(hi))", hi), c: ("-Depth", CX.zero))
        g.box("Wall Right", a: ("\(wi) - Wall", wi), b: ("-(\(hi))", hi), c: ("-Depth", CX.zero))
        g.box("Bottom", a: ("-(\(wi))", wi), b: ("-(\(hi))", hi), c: ("-Depth", "-Depth + Wall"))
        // The grip: a lip along the top inside edge.
        g.box("Grip Lip", a: ("-(\(wi)) + Wall", "\(wi) - Wall"), b: ("\(hi) - Wall - 0.003 m", "\(hi) - Wall"), c: ("-Depth * 0.4", CX.zero))
        g.screws("Screw", at: [("-(\(w)) + Flange / 2", CX.zero), ("\(w) - Flange / 2", CX.zero)], c: fl, diameter: CX.mm(2.5))
        g.b.symbol(.face, [.coarse], .rect(("-(\(w))", "-(\(h))"), (w, h)), .rect(("-(\(wi))", "-(\(hi))"), (wi, hi)))
        g.b.symbol(.top, [.coarse], dashed: true, .rect(("-(\(wi))", "-Depth"), (wi, CX.zero)))
        g.b.type("Recessed Pull - 90 x 40 mm", ["Width": mm(90), "Height": mm(40)], cost: 9.50, model: "RP-9040", description: "Recessed pull, 90 x 40 mm (3 1/2\" x 1 9/16\"), satin nickel")
        g.b.type("Recessed Pull - 120 x 45 mm", ["Width": mm(120), "Height": mm(45), "Depth": mm(13)], cost: 11.75, model: "RP-12045",
                 description: "Recessed pull, 120 x 45 mm (4 3/4\" x 1 3/4\"), satin nickel")
        g.b.type("Recessed Pull - 50 x 50 mm Square", ["Width": mm(50), "Height": mm(50)], texts: ["Shape": "Square"], cost: 8.25, model: "RP-5050",
                 description: "Square recessed pull, 50 mm (2\")")
        return g.build()
    }

    // MARK: Flush Pull

    static func flushPull() -> ComponentDefinition {
        var g = faced("Flush Pull", .handles, "Flush & Recessed Pulls", "Press-fit finger cup in a bored hole, for sliding and flush doors.")
        g.b.material(finish, .satinNickel)
        g.b.tags("flush", "cup", "finger cup", "sliding door", "round")
        g.b.aliases("finger cup", "flush ring", "round flush pull", "sliding door cup", "press-in pull", "35 mm flush pull")
        g.b.length("Size", mm(35)); g.b.length("Depth", mm(10)); g.b.length("Rim", mm(3)); g.b.length("Wall", mm(0.8), group: .manufacturing)
        g.b.choice("Shape", ["Round", "Square"], "Round")
        g.b.flag("Square Shape", false, instance: false, group: .dimensions)
        g.b.host(ComponentHostKind.fronts + [.glass], faces: [.front, .back], align: .inside, alignments: [.inside, .center], offsetX: inch(1.5))
        g.b.drill("Flush pull bore", x: CX.zero, y: CX.zero, diameter: "Size - 2 * Rim", depth: "Depth")
        let R = "Size / 2", Ri = "Size / 2 - Rim"
        g.variant("Square Shape", when: false) { g in
            // A turned cup: rim proud of the face, wall and bottom in the bore.
            g.revolve("Cup", along: 2, profile: [(CX.zero, "-Depth"), ("\(Ri) + Wall", "-Depth"), ("\(Ri) + Wall", CX.zero), (R, CX.zero), (R, CX.mm(0.6)),
                                                 ("(\(R)) - 0.0008 m", CX.mm(1)), (Ri, CX.mm(1)), (Ri, "-Depth + Wall"), (CX.zero, "-Depth + Wall")])
        }
        g.variant("Square Shape") { g in
            let s = R, si = Ri
            g.box("Rim Top", a: ("-(\(s))", s), b: (si, s), c: (CX.zero, CX.mm(1)))
            g.box("Rim Bottom", a: ("-(\(s))", s), b: ("-(\(s))", "-(\(si))"), c: (CX.zero, CX.mm(1)))
            g.box("Rim Left", a: ("-(\(s))", "-(\(si))"), b: ("-(\(si))", si), c: (CX.zero, CX.mm(1)))
            g.box("Rim Right", a: (si, s), b: ("-(\(si))", si), c: (CX.zero, CX.mm(1)))
            g.box("Cup Bottom", a: ("-(\(si))", si), b: ("-(\(si))", si), c: ("-Depth", "-Depth + Wall"))
            for (n, a, bb) in [("Wall Left", ("-(\(si))", "-(\(si)) + Wall"), ("-(\(si))", si)), ("Wall Right", ("\(si) - Wall", si), ("-(\(si))", si)),
                               ("Wall Top", ("-(\(si))", si), ("\(si) - Wall", si)), ("Wall Bottom", ("-(\(si))", si), ("-(\(si))", "-(\(si)) + Wall"))] {
                g.box(n, a: a, b: bb, c: ("-Depth", CX.zero))
            }
        }
        coarseRound(&g, diameter: "Size", projection: CX.mm(1))
        g.b.type("Flush Pull - Round 35 mm", ["Size": mm(35)], cost: 3.25, model: "FP-35R", description: "Round flush pull, 35 mm bore (1 3/8\")")
        g.b.type("Flush Pull - Round 50 mm", ["Size": mm(50), "Depth": mm(12)], cost: 4.50, model: "FP-50R", description: "Round flush pull, 50 mm (2\")")
        g.b.type("Flush Pull - Square 40 mm", ["Size": mm(40)], flags: ["Square Shape": true], texts: ["Shape": "Square"], cost: 4.95, model: "FP-40S",
                 description: "Square flush pull, 40 mm (1 9/16\")")
        return g.build()
    }

    // MARK: Finger Pull

    static func fingerPull() -> ComponentDefinition {
        var g = faced("Finger Pull", .handles, "Profile Handles", "Aluminium finger-pull profile along a front's edge, its lip standing off the face.")
        g.b.material(finish, .aluminum)
        g.b.tags("finger pull", "profile", "aluminium", "handleless", "lip")
        g.b.aliases("finger pull profile", "lip pull", "aluminum pull profile", "continuous pull", "edge profile pull")
        g.b.length("Width", inch(18), instance: true); g.b.length("Radius", mm(10)); g.b.length("Lip Height", mm(20))
        g.b.length("Front Thickness", inch(0.75), instance: true, group: .placement); g.b.length("Wall", mm(1.6), group: .manufacturing)
        g.b.choice("Position", ["Top Edge", "Bottom Edge"], "Top Edge", instance: true, group: .placement)
        g.b.host(ComponentHostKind.fronts, faces: [.topEdge, .bottomEdge], align: .full)
        g.b.drill("Profile screw", x: "-Width / 2 + 0.05 m", y: CX.zero, diameter: CX.mm(3), depth: CX.mm(12))
        g.b.drill("Profile screw", x: "Width / 2 - 0.05 m", y: CX.zero, diameter: CX.mm(3), depth: CX.mm(12))
        // Origin: the edge at the front face (b up, c out). A plate on the edge and a rounded lip out in front.
        g.prism("Edge Plate", along: 0, profile: PtsA.box((CX.zero, "Wall"), ("-Front Thickness", "Radius")), range: ("-Width / 2", "Width / 2"))
        let lip: [(String, String)] = [("Wall", "Radius - Wall"), ("Wall", "Radius"), ("-Lip Height + Wall", "Radius"), ("-Lip Height", "Radius - Wall / 2"), ("-Lip Height + Wall", "Radius - Wall")]
        g.prism("Lip", along: 0, profile: lip, range: ("-Width / 2", "Width / 2"))
        g.b.symbol(.face, [.coarse], .rect(("-Width / 2", "-Lip Height"), ("Width / 2", "Wall")))
        g.b.symbol(.top, [.coarse], .rect(("-Width / 2", "-Front Thickness"), ("Width / 2", "Radius")))
        g.b.type("Finger Pull - 10 mm", [:], cost: 14.00, model: "FPR-10", description: "Finger pull profile, 10 mm (3/8\") finger gap, cut to the front's width")
        g.b.type("Finger Pull - 15 mm", ["Radius": mm(15), "Lip Height": mm(25)], cost: 16.50, model: "FPR-15", description: "Finger pull profile, 15 mm (5/8\") finger gap")
        return g.build()
    }

    // MARK: Cup Pull (FM5 upgrade)

    static func cupPull() -> ComponentDefinition {
        var g = handle(F.cupPull, "Cup Pulls", "Cup (bin) pull: a hood open at the bottom, on two screws.", finish: .bronze, upgrading: F.cupPull)
        g.b.tags("cup", "bin", "shell", "drawer", "traditional")
        g.b.aliases("bin pull", "shell pull", "cup handle", "cup pull", "apothecary pull")
        ccAliases(&g.b, [64, 76, 96])
        postHoles(&g.b)
        fingerSpace(&g.b, length: "Width")
        g.b.requires(.fitsWidth("Width + 0.0254 m"))
        g.prism("Plate", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Width", "Height", CX.mm(4)), range: (CX.zero, CX.mm(2.5)))
        // The hood: a quarter ellipse from the plate's top down to the front, open below; its ends closed.
        let b0 = "-Height / 2 + 0.005 m", rb = "Height - 0.009 m", rc = "Projection", t = CX.mm(2.5)
        var outer: [(String, String)] = [], inner: [(String, String)] = []
        for k in 0...10 {
            let th = Double(k) / 10 * .pi / 2
            outer.append(("\(b0) + (\(rb)) * \(LX.num(cos(th)))", "(\(rc)) * \(LX.num(sin(th)))"))
            inner.append(("\(b0) + (\(rb) - \(t)) * \(LX.num(cos(th)))", "(\(rc) - \(t)) * \(LX.num(sin(th)))"))
        }
        let hoodEnd = "Width / 2 - 0.004 m"
        g.prism("Hood", along: 0, profile: outer + inner.reversed(), range: ("-(\(hoodEnd)) + 0.0025 m", "\(hoodEnd) - 0.0025 m"))
        for (n, r) in [("Hood End Left", ("-(\(hoodEnd))", "-(\(hoodEnd)) + 0.0025 m")), ("Hood End Right", ("\(hoodEnd) - 0.0025 m", hoodEnd))] {
            g.prism(n, along: 0, profile: outer + [(b0, CX.zero)], range: r)
        }
        g.screws("Screw", at: [("-Hole Spacing / 2", "Height / 4"), ("Hole Spacing / 2", "Height / 4")], c: CX.mm(2.5), diameter: CX.mm(4))
        coarse(&g, length: "Width", height: "Height", projection: "Projection")
        g.b.renames(["64 mm": "Cup Pull - 64 mm CC", "96 mm": "Cup Pull - 96 mm CC"])
        for (cc, cost) in [(64.0, 5.50), (76, 6.00), (96, 6.50)] {
            g.b.type("Cup Pull - \(Int(cc)) mm CC", ["Hole Spacing": mm(cc), "Width": mm(cc + 22), "Height": mm(cc > 80 ? 40 : 36), "Projection": mm(18), "Hole Diameter": mm(4)],
                     flags: ["Vertical": false, "On Lid": false], cost: cost, model: "CP-\(Int(cc))",
                     description: "Cup pull, \(Int(cc)) mm (\(TradeA.inchWord(cc))) centers, oil-rubbed bronze", isDefault: cc == 64)
        }
        return g.build()
    }

    // MARK: Ring Pull

    static func ringPull() -> ComponentDefinition {
        var g = handle("Ring Pull", "Ring & Drop Pulls", "Round rose with a hanging ring, on one screw.", finish: .brass)
        g.b.tags("ring", "drop ring", "traditional", "brass")
        g.b.aliases("ring handle", "drop ring pull", "ring knob", "o-ring pull")
        g.b.length("Ring Diameter", mm(40)); g.b.length("Base Size", mm(22)); g.b.length("Ring Thickness", mm(4.5)); g.b.length("Projection", mm(16))
        g.b.length("Hole Spacing", 0, group: .manufacturing); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        g.b.length("Length", mm(22), formula: "Base Size")
        g.b.drill("Pull screw", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        fingerSpace(&g.b, length: "Ring Diameter")
        // The rose, a short stem and loop, and the ring hanging flat against the face below it.
        g.revolve("Rose", along: 2, profile: PtsA.turned("Base Size / 2", CX.mm(5), [(0, 0), (1, 0), (1, 0.2), (0.85, 0.6), (0.5, 1), (0, 1)]))
        g.cylinder("Stem", along: 2, radius: CX.mm(2.5), range: (CX.mm(4), "Projection - Ring Thickness"))
        g.cylinder("Loop", along: 0, center: (CX.zero, "Projection - Ring Thickness"), radius: "Ring Thickness * 0.7", range: ("-Ring Thickness", "Ring Thickness"))
        g.revolve("Ring", along: 2, center: (CX.zero, "-Ring Diameter / 2 + Ring Thickness / 2"),
                  profile: PtsA.ring("Ring Diameter / 2 - Ring Thickness / 2", "Ring Thickness / 2", at: "Projection - Ring Thickness"))
        g.b.symbol(.face, [.coarse], .circle((CX.zero, CX.zero), "Base Size / 2"), .circle((CX.zero, "-Ring Diameter / 2 + Ring Thickness / 2"), "Ring Diameter / 2"))
        g.b.symbol(.top, [.coarse], .rect(("-Ring Diameter / 2", CX.zero), ("Ring Diameter / 2", "Projection")))
        for (d, base, cost) in [(30.0, 18.0, 5.25), (40, 22, 6.50), (50, 26, 7.95)] {
            g.b.type("Ring Pull - \(Int(d)) mm", ["Ring Diameter": mm(d), "Base Size": mm(base), "Projection": mm(base * 0.7)], flags: ["Vertical": false, "On Lid": false],
                     cost: cost, model: "RG-\(Int(d))", description: "Ring pull, \(Int(d)) mm (\(TradeA.inchWord(d))) ring, solid brass", isDefault: d == 40)
        }
        return g.build()
    }

    // MARK: Drop Handle

    static func dropHandle() -> ComponentDefinition {
        var g = handle("Drop Handle", "Ring & Drop Pulls", "Bail (drop) handle: a swinging bail on two roses.", finish: .brass)
        g.b.tags("drop", "bail", "swing", "traditional", "campaign")
        g.b.aliases("bail pull", "drop pull", "swing handle", "hanging handle", "chest handle")
        ccAliases(&g.b, [64, 76, 96])
        g.b.length("Length", mm(76)); g.b.length("Pivot Position", mm(22)); g.b.length("Rose Diameter", mm(14)); g.b.length("Wire Diameter", mm(5))
        g.b.length("Projection", mm(9))
        g.b.length("Hole Spacing", mm(76), formula: "Length"); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        postHoles(&g.b)
        fingerSpace(&g.b)
        for s in ["-", ""] {
            g.revolve("Rose", along: 2, center: ("\(s)Length / 2", CX.zero), profile: PtsA.turned("Rose Diameter / 2", "Projection", [(0, 0), (1, 0), (1, 0.25), (0.7, 0.55), (0.45, 1), (0, 1)]))
            g.cylinder("Pivot", along: 0, center: (CX.zero, "Projection - Wire Diameter / 2"), radius: "Wire Diameter * 0.75",
                       range: ("\(s == "-" ? "-Length / 2" : "Length / 2 - 0.004 m")", "\(s == "-" ? "-Length / 2 + 0.004 m" : "Length / 2")"))
        }
        // The bail hangs down the face from the pivots.
        let x = "Length / 2 - 0.002 m", rc = "Pivot Position * 0.4", dn = "-Pivot Position"
        var path: [(String, String)] = [("-(\(x))", CX.zero)]
        path += PtsA.arc(("-(\(x)) + \(rc)", "\(dn) + \(rc)"), rc, from: 180, sweep: 90, segments: 6)
        path += PtsA.arc(("\(x) - \(rc)", "\(dn) + \(rc)"), rc, from: 270, sweep: 90, segments: 6)
        path.append((x, CX.zero))
        g.rod("Bail", plane: 0, 1, path: path, radius: "Wire Diameter / 2", at: "Projection - Wire Diameter / 2")
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", "-Pivot Position"), ("Length / 2", "Rose Diameter / 2")))
        g.b.symbol(.top, [.coarse], .rect(("-Length / 2", CX.zero), ("Length / 2", "Projection")))
        for (cc, cost) in [(64.0, 7.25), (76, 8.25), (96, 9.75)] {
            g.b.type("Drop Handle - \(Int(cc)) mm CC", ["Length": mm(cc), "Pivot Position": mm(cc * 0.3)], flags: ["Vertical": false, "On Lid": false],
                     cost: cost, model: "DH-\(Int(cc))", description: "Drop (bail) handle, \(Int(cc)) mm (\(TradeA.inchWord(cc))) centers, brass", isDefault: cc == 76)
        }
        return g.build()
    }

    // MARK: Knob (FM5 upgrade)

    /// A classic turned knob, as (r, h) fractions of the radius and projection.
    static let knobProfile: [(Double, Double)] = [(0, 0), (0.62, 0), (0.62, 0.05), (0.44, 0.12), (0.32, 0.28), (0.33, 0.42), (0.55, 0.53), (0.84, 0.64), (0.98, 0.76),
                                                  (0.97, 0.88), (0.84, 0.96), (0.55, 1), (0, 1)]
    static let discProfile: [(Double, Double)] = [(0, 0), (0.5, 0), (0.5, 0.05), (0.32, 0.12), (0.3, 0.55), (0.92, 0.6), (1, 0.68), (1, 0.9), (0.94, 1), (0, 1)]

    static func knob() -> ComponentDefinition {
        var g = handle(F.knob, "Knobs", "Turned round knob on one screw.", finish: .satinNickel, upgrading: F.knob)
        g.b.tags("knob", "round", "cabinet knob", "drawer knob")
        g.b.aliases("cabinet knob", "round knob", "pull knob", "door knob", "drawer knob", "32 mm knob", "1 1/4\" knob")
        g.b.text("Profile", "Round")
        g.b.flag("Disc Profile", false, instance: false, group: .dimensions)
        g.b.drill("Knob screw", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        g.b.clearance(.box(name: "Finger space", x0: "-Diameter", x1: "Diameter", y0: "-Diameter", y1: "Diameter", z0: CX.zero, z1: "Projection + 0.01 m"))
        g.variant("Disc Profile", when: false) { g in g.revolve("Knob", along: 2, profile: PtsA.turned("Diameter / 2", "Projection", knobProfile)) }
        g.variant("Disc Profile") { g in g.revolve("Disc Knob", along: 2, profile: PtsA.turned("Diameter / 2", "Projection", discProfile)) }
        g.screws("Screw Head", at: [(CX.zero, CX.zero)], c: "-Front Thickness", diameter: CX.mm(7), outward: false)
        coarseRound(&g, diameter: "Diameter", projection: "Projection")
        g.b.renames(["1 1/4\"": "Knob - 1 1/4\"", "1 1/2\" Brass": "Knob - 1 1/2\" Brass"])
        let off: [String: Bool] = ["Vertical": false, "On Lid": false, "Disc Profile": false]
        g.b.type("Knob - 1 1/4\"", ["Diameter": inch(1.25), "Projection": inch(1), "Hole Diameter": mm(5)], flags: off, cost: 3.00, model: "KN-125",
                 description: "Round knob, 1 1/4\" (32 mm), satin nickel", isDefault: true)
        g.b.type("Knob - 1 1/2\" Brass", ["Diameter": inch(1.5), "Projection": inch(1.125), "Hole Diameter": mm(5)], flags: off, cost: 4.75, model: "KN-150B",
                 description: "Round knob, 1 1/2\" (38 mm), brass")
        var disc = off; disc["Disc Profile"] = true
        g.b.type("Knob - 1 3/8\" Disc", ["Diameter": inch(1.375), "Projection": inch(0.875), "Hole Diameter": mm(5)], flags: disc, texts: ["Profile": "Disc"],
                 cost: 3.50, model: "KN-138D", description: "Disc knob, 1 3/8\" (35 mm), satin nickel")
        return g.build()
    }

    // MARK: Mushroom Knob

    static func mushroomKnob() -> ComponentDefinition {
        var g = handle("Mushroom Knob", "Knobs", "Domed (mushroom) knob on a slim stem.", finish: .chrome)
        g.b.tags("knob", "mushroom", "dome", "round")
        g.b.aliases("dome knob", "mushroom pull", "button knob", "round dome knob")
        g.b.length("Diameter", mm(32)); g.b.length("Projection", mm(26)); g.b.length("Stem Diameter", mm(12))
        g.b.number("Curvature", 0.55, group: .dimensions)
        g.b.length("Hole Spacing", 0, group: .manufacturing); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        g.b.length("Length", mm(32), formula: "Diameter")
        g.b.drill("Knob screw", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        let R = "Diameter / 2", sr = "Stem Diameter / 2", dome = "Diameter / 2 * Curvature", rim = "Projection - Diameter / 2 * Curvature"
        var prof: [(String, String)] = [(CX.zero, CX.zero), ("(\(sr)) * 1.35", CX.zero), ("(\(sr)) * 1.35", CX.mm(1.5)), (sr, CX.mm(4)), (sr, "\(rim) - 0.004 m"),
                                        ("(\(R)) * 0.85", "\(rim) - 0.0025 m"), (R, "\(rim) - 0.0005 m")]
        for k in 1...7 {
            let p = Double(k) / 7 * .pi / 2
            prof.append(("(\(R)) * \(LX.num(cos(p)))", "\(rim) + (\(dome)) * \(LX.num(sin(p)))"))
        }
        prof[prof.count - 1].0 = CX.zero
        g.revolve("Knob", along: 2, profile: prof)
        coarseRound(&g, diameter: "Diameter", projection: "Projection")
        for (d, p, cost) in [(25.0, 22.0, 3.25), (32, 26, 3.95), (38, 30, 4.75)] {
            g.b.type("Mushroom Knob - \(Int(d)) mm", ["Diameter": mm(d), "Projection": mm(p), "Stem Diameter": mm(d * 0.38)], flags: ["Vertical": false, "On Lid": false],
                     cost: cost, model: "MK-\(Int(d))", description: "Mushroom knob, \(Int(d)) mm (\(TradeA.inchWord(d))), polished chrome", isDefault: d == 32)
        }
        return g.build()
    }

    // MARK: Square Knob

    static func squareKnob() -> ComponentDefinition {
        var g = handle("Square Knob", "Knobs", "Square-headed knob on a round neck.", finish: .matteBlack)
        g.b.tags("knob", "square", "modern")
        g.b.aliases("square pull", "cube knob", "block knob")
        g.b.length("Width", mm(25)); g.b.length("Depth", mm(24)); g.b.length("Head Thickness", mm(8))
        g.b.length("Hole Spacing", 0, group: .manufacturing); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        g.b.length("Length", mm(25), formula: "Width")
        g.b.drill("Knob screw", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        g.revolve("Neck", along: 2, profile: PtsA.turned("Width / 2", "Depth - Head Thickness + 0.001 m", [(0, 0), (0.6, 0), (0.6, 0.06), (0.38, 0.25), (0.34, 1), (0, 1)]))
        g.prism("Head", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Width", "Width", "Width * 0.12"), range: ("Depth - Head Thickness", "Depth - 0.0012 m"))
        g.prism("Head Top", along: 2, profile: PtsA.rounded((CX.zero, CX.zero), "Width - 0.0016 m", "Width - 0.0016 m", "Width * 0.12"), range: ("Depth - 0.0012 m", "Depth"))
        g.b.symbol(.face, [.coarse], .rect(("-Width / 2", "-Width / 2"), ("Width / 2", "Width / 2")))
        g.b.symbol(.top, [.coarse], .rect(("-Width / 2", CX.zero), ("Width / 2", "Depth")))
        g.b.type("Square Knob - 25 mm", [:], flags: ["Vertical": false, "On Lid": false], cost: 3.75, model: "SK-25", description: "Square knob, 25 mm (1\"), matte black", isDefault: true)
        g.b.type("Square Knob - 30 mm", ["Width": mm(30), "Depth": mm(27), "Head Thickness": mm(9)], flags: ["Vertical": false, "On Lid": false], cost: 4.50, model: "SK-30",
                 description: "Square knob, 30 mm (1 3/16\"), matte black")
        return g.build()
    }

    // MARK: Crystal Knob

    static func crystalKnob() -> ComponentDefinition {
        var g = handle("Crystal Knob", "Knobs", "Faceted glass knob on a metal base.", finish: .chrome)
        g.b.material("Glass Material", .crystal)
        g.b.tags("knob", "crystal", "glass", "faceted", "diamond")
        g.b.aliases("glass knob", "diamond knob", "faceted knob", "acrylic knob", "cut glass knob")
        g.b.length("Size", mm(30)); g.b.length("Projection", mm(32))
        g.b.choice("Shape", ["Octagon", "Diamond"], "Octagon")
        g.b.flag("Diamond Cut", false, instance: false, group: .dimensions)
        g.b.length("Hole Spacing", 0, group: .manufacturing); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        g.b.length("Length", mm(30), formula: "Size")
        g.b.drill("Knob screw", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Host Thickness", through: true)
        g.revolve("Base", along: 2, profile: PtsA.turned("Size / 2", "Projection * 0.4", [(0, 0), (0.62, 0), (0.62, 0.1), (0.4, 0.3), (0.3, 0.7), (0.42, 0.9), (0.46, 1), (0, 1)]))
        g.using("Glass Material")
        let z0 = "Projection * 0.4", z1 = "Projection * 0.78"
        for (flag, on, sides, start) in [("Diamond Cut", false, 8, 22.5), ("Diamond Cut", true, 12, 15.0)] {
            g.variant(flag, when: on) { g in
                g.blend("Crown", along: 2, bottom: PtsA.polygon((CX.zero, CX.zero), "Size * 0.24", sides: sides, start: start),
                        top: PtsA.polygon((CX.zero, CX.zero), "Size / 2", sides: sides, start: start), range: (z0, z1))
                g.blend("Table", along: 2, bottom: PtsA.polygon((CX.zero, CX.zero), "Size / 2", sides: sides, start: start),
                        top: PtsA.polygon((CX.zero, CX.zero), "Size * 0.3", sides: sides, start: start + (on ? 15 : 22.5)), range: (z1, "Projection"))
            }
        }
        g.using(nil)
        coarseRound(&g, diameter: "Size", projection: "Projection")
        g.b.type("Crystal Knob - Octagon 30 mm", [:], flags: ["Vertical": false, "On Lid": false, "Diamond Cut": false], cost: 6.50, model: "CK-30O",
                 description: "Octagonal crystal knob, 30 mm (1 3/16\"), chrome base", isDefault: true)
        g.b.type("Crystal Knob - Diamond 35 mm", ["Size": mm(35), "Projection": mm(36)], flags: ["Vertical": false, "On Lid": false, "Diamond Cut": true],
                 texts: ["Shape": "Diamond"], cost: 7.95, model: "CK-35D", description: "Diamond-cut crystal knob, 35 mm (1 3/8\"), chrome base")
        return g.build()
    }

    // MARK: Leather Pull

    static func leatherPull() -> ComponentDefinition {
        var g = handle("Leather Pull", "Leather Pulls", "Leather strap loop held by two screw caps.", finish: .brass)
        g.b.material("Leather Material", .leather)
        g.b.tags("leather", "strap", "loop", "soft")
        g.b.aliases("leather handle", "strap pull", "leather strap handle", "loop pull")
        ccAliases(&g.b, [96, 128])
        g.b.length("Length", mm(96)); g.b.length("Width", mm(20)); g.b.length("Strap Thickness", mm(3)); g.b.length("Projection", mm(28))
        g.b.length("Hole Spacing", mm(96), formula: "Length"); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        g.b.choice("Color", ["Tan", "Brown", "Black"], "Tan")
        postHoles(&g.b)
        fingerSpace(&g.b)
        let x = "Length / 2", t = "Strap Thickness / 2", n = 14
        var path: [(String, String)] = [("-(\(x)) - 0.01 m", t)]
        for k in 0...n {
            let u = Double(k) / Double(n)
            let a = -1 + 2 * u
            path.append(("(\(x)) * \(LX.num(a * 0.82))", "\(t) + (Projection - Strap Thickness) * \(LX.num(sin(u * .pi)))"))
        }
        path.append(("\(x) + 0.01 m", t))
        g.using("Leather Material")
        g.sweep("Strap", plane: 0, 2, path: path, profile: PtsA.box(("-(\(t))", t), ("-Width / 2", "Width / 2")))
        g.using(finish)
        for s in ["-", ""] {
            g.revolve("Cap", along: 2, center: ("\(s)Length / 2", CX.zero), profile: PtsA.turned(CX.mm(6), CX.mm(4), [(0, 0), (1, 0), (1, 0.4), (0.7, 0.85), (0, 1)]).map { ($0.0, "\($0.1) + Strap Thickness") })
        }
        coarse(&g, length: "Length + 0.02 m", height: "Width", projection: "Projection")
        g.b.type("Leather Pull - 96 mm CC", [:], flags: ["Vertical": false, "On Lid": false], cost: 8.50, model: "LP-96", description: "Leather strap pull, 96 mm (3 3/4\") centers, tan", isDefault: true)
        g.b.type("Leather Pull - 128 mm CC", ["Length": mm(128), "Width": mm(25), "Projection": mm(32)], flags: ["Vertical": false, "On Lid": false], cost: 9.75, model: "LP-128",
                 description: "Leather strap pull, 128 mm (5\") centers, tan")
        return g.build()
    }

    // MARK: Wooden Handle

    static func woodenHandle() -> ComponentDefinition {
        var g = handle("Wooden Handle", "Wooden Handles", "Solid wood bridge handle with an arched grip.", finish: .oak)
        g.b.tags("wood", "wooden", "bridge", "natural", "timber")
        g.b.aliases("wood handle", "wood pull", "bridge handle", "timber handle", "oak handle", "walnut handle")
        ccAliases(&g.b, [96, 128, 192])
        g.b.length("Length", mm(140)); g.b.length("Height", mm(28)); g.b.length("Width", mm(16)); g.b.length("Foot Length", mm(18))
        g.b.text("Profile", "Bridge")
        g.b.length("Hole Spacing", mm(96), group: .manufacturing); g.b.length("Hole Diameter", mm(5), group: .manufacturing)
        postHoles(&g.b)
        fingerSpace(&g.b, projection: "Height")
        // The bridge in the a–c plane, extruded across: flat top with rounded ends, feet, and an arched underside.
        let L = "Length / 2", H = "Height", f = "Foot Length"
        var prof: [(String, String)] = [("-(\(L))", CX.zero), ("-(\(L)) + \(f)", CX.zero)]
        for k in 1..<10 {
            let u = Double(k) / 10
            prof.append(("-(\(L)) + \(f) + (2 * (\(L)) - 2 * \(f)) * \(LX.num(u))", "(\(H)) * 0.55 * \(LX.num(sin(u * .pi)))"))
        }
        prof += [("\(L) - \(f)", CX.zero), (L, CX.zero), (L, "\(H) * 0.75")]
        prof += PtsA.arc(("\(L) - \(H) * 0.25", "\(H) * 0.75"), "\(H) * 0.25", from: 0, sweep: 90, segments: 4).dropFirst()
        prof += PtsA.arc(("-(\(L)) + \(H) * 0.25", "\(H) * 0.75"), "\(H) * 0.25", from: 90, sweep: 90, segments: 4).dropFirst()
        g.prism("Handle", along: 1, profile: prof, range: ("-Width / 2", "Width / 2"))
        coarse(&g, length: "Length", height: "Width", projection: "Height")
        for (cc, cost) in [(96.0, 7.50), (128, 8.75), (192, 11.25)] {
            g.b.type("Wooden Handle - \(Int(cc)) mm CC", ["Hole Spacing": mm(cc), "Length": mm(cc + 44), "Height": mm(cc > 150 ? 32 : 28)], flags: ["Vertical": false, "On Lid": false],
                     cost: cost, model: "WH-\(Int(cc))", description: "Solid oak bridge handle, \(Int(cc)) mm (\(TradeA.inchWord(cc))) centers", isDefault: cc == 96)
        }
        return g.build()
    }

    // MARK: Integrated Handle

    static func integratedHandle() -> ComponentDefinition {
        var g = faced("Integrated Handle", .handles, "Profile Handles", "Grip routed into the front's top edge from behind, lined with an aluminium insert.")
        g.b.material(finish, .aluminum)
        g.b.tags("integrated", "handleless", "routed", "groove", "grip")
        g.b.aliases("routed handle", "handleless grip", "integral handle", "grip groove", "finger groove", "j groove")
        g.b.length("Length", inch(18), instance: true); g.b.length("Groove Depth", mm(30)); g.b.length("Groove Width", mm(12))
        g.b.length("Front Thickness", inch(0.75), instance: true, group: .placement); g.b.length("Lining", mm(1.2), group: .manufacturing)
        g.b.choice("Profile", ["J Groove", "Angled Groove"], "J Groove")
        g.b.host(ComponentHostKind.fronts, faces: [.topEdge], align: .full)
        g.b.groove("Grip groove", from: ("-Length / 2", CX.zero), to: ("Length / 2", CX.zero), width: "Groove Width", depth: "Groove Depth")
        g.b.requires(.hostThickness(min: "Groove Width + 0.006 m", max: nil))
        // Origin: the top edge at the front face (b up, c out). The lining fills the routed recess at the back.
        let back = "-Front Thickness", wall = "-Front Thickness + Groove Width"
        g.prism("Lining Back", along: 0, profile: PtsA.box(("-Groove Depth", CX.zero), (wall, "\(wall) + Lining")), range: ("-Length / 2", "Length / 2"))
        g.prism("Lining Bottom", along: 0, profile: PtsA.box(("-Groove Depth", "-Groove Depth + Lining"), (back, wall)), range: ("-Length / 2", "Length / 2"))
        g.prism("Lining Lip", along: 0, profile: PtsA.box((CX.zero, "Lining"), (wall, "\(wall) + 0.004 m")), range: ("-Length / 2", "Length / 2"))
        g.b.symbol(.face, [.coarse], dashed: true, .rect(("-Length / 2", "-Groove Depth"), ("Length / 2", CX.zero)))
        g.b.symbol(.side, [.coarse, .medium], .rect((back, "-Groove Depth"), (wall, CX.zero)))
        g.b.type("Integrated Handle - 30 mm Groove", [:], cost: 12.00, model: "IH-30", description: "Integrated grip, 30 mm (1 3/16\") deep, aluminium lining", isDefault: true)
        g.b.type("Integrated Handle - 40 mm Groove", ["Groove Depth": mm(40), "Groove Width": mm(14)], cost: 13.50, model: "IH-40",
                 description: "Integrated grip, 40 mm (1 9/16\") deep, aluminium lining")
        return g.build()
    }

    // MARK: J-Pull Profile

    static func jPull() -> ComponentDefinition {
        var g = faced("J-Pull Profile", .handles, "Profile Handles", "Aluminium J profile on a front's top edge, its hook rising above it.")
        g.b.material(finish, .aluminum)
        g.b.tags("j pull", "profile", "aluminium", "handleless", "edge")
        g.b.aliases("j-profile", "j handle", "j channel pull", "top mount profile", "aluminum j pull")
        g.b.length("Length", inch(18), instance: true); g.b.length("Depth", mm(12)); g.b.length("Height", mm(22)); g.b.length("Wall", mm(1.6), group: .manufacturing)
        g.b.length("Front Thickness", inch(0.75), instance: true, group: .placement)
        g.b.choice("Orientation", ["Top", "Bottom"], "Top", instance: true, group: .placement)
        g.b.host(ComponentHostKind.fronts, faces: [.topEdge, .bottomEdge], align: .full)
        for s in ["-", ""] { g.b.drill("Profile screw", x: "\(s)Length / 2 \(s == "-" ? "+" : "-") 0.05 m", y: CX.zero, diameter: CX.mm(3), depth: CX.mm(12)) }
        // Origin: the edge at the front face. A base on the edge, a face leg standing off the front, a hook back over it.
        let r = ("-Length / 2", "Length / 2")
        g.prism("Base", along: 0, profile: PtsA.box((CX.zero, "Wall"), ("-Front Thickness", "Depth")), range: r)
        g.prism("Face Leg", along: 0, profile: PtsA.box((CX.zero, "Height"), ("Depth - Wall", "Depth")), range: r)
        g.prism("Hook", along: 0, profile: [("Height - Wall", "Depth * 0.3"), ("Height - Wall", "Depth"), ("Height", "Depth"), ("Height", "Depth * 0.3 + 0.001 m"),
                                            ("Height - Wall * 0.4", "Depth * 0.3")], range: r)
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", CX.zero), ("Length / 2", "Height")))
        g.b.symbol(.side, [.coarse], .polyline([FamilyPoint("-Front Thickness", "0 m"), FamilyPoint("Depth", "0 m"), FamilyPoint("Depth", "Height"), FamilyPoint("Depth * 0.3", "Height")], closed: false))
        g.b.type("J-Pull Profile - 22 mm", [:], cost: 15.00, model: "JP-22", description: "J-pull profile, 22 mm (7/8\") tall, cut to length", isDefault: true)
        g.b.type("J-Pull Profile - 30 mm", ["Height": mm(30), "Depth": mm(14)], cost: 17.50, model: "JP-30", description: "J-pull profile, 30 mm (1 3/16\") tall, cut to length")
        return g.build()
    }

    // MARK: Gola Profile

    static func golaProfile() -> ComponentDefinition {
        var g = faced("Gola Profile", .handles, "Profile Handles", "Recessed handleless channel fixed to the carcass between fronts.")
        g.b.material(finish, .aluminum)
        g.b.tags("gola", "handleless", "channel", "recessed", "kitchen")
        g.b.aliases("handleless channel", "recessed rail", "c profile", "l profile", "true handleless", "gola channel")
        g.b.length("Length", inch(36), instance: true); g.b.length("Height", mm(37)); g.b.length("Depth", mm(27)); g.b.length("Wall", mm(1.8), group: .manufacturing)
        g.b.choice("Profile Type", ["L", "C", "Vertical"], "L")
        g.b.flag("C Profile", false, instance: false, group: .dimensions)
        g.b.flag("Vertical Profile", false, instance: false, group: .dimensions)
        g.b.flag("L Run", false, formula: "and(not(C Profile), not(Vertical Profile))")
        g.b.flag("C Run", false, formula: "and(C Profile, not(Vertical Profile))")
        g.b.host([.sidePanel, .divider, .rail, .top], faces: [.frontEdge, .front], align: .full)
        g.b.snap("Top of profile", x: CX.zero, y: "Height")
        g.b.requires(.note("Fronts below a Gola profile sit about 1 1/2\" lower than the carcass top (the channel is the handle)."))
        // Origin: the carcass front line at the profile's bottom. The channel opens to the front (c out).
        let r = ("-Length / 2", "Length / 2")
        g.variant("L Run") { g in
            g.prism("Bottom Flange", along: 0, profile: PtsA.box((CX.zero, "Wall"), ("-Depth", CX.zero)), range: r)
            g.prism("Back Wall", along: 0, profile: PtsA.box((CX.zero, "Height"), ("-Depth", "-Depth + Wall")), range: r)
            g.prism("Top Lip", along: 0, profile: [("Height - Wall", "-Depth"), ("Height - Wall", "-Depth + 0.012 m"), ("Height", "-Depth + 0.014 m"), ("Height", "-Depth")], range: r)
        }
        g.variant("C Run") { g in
            g.prism("Bottom Flange", along: 0, profile: PtsA.box((CX.zero, "Wall"), ("-Depth", CX.zero)), range: r)
            g.prism("Top Flange", along: 0, profile: PtsA.box(("Height - Wall", "Height"), ("-Depth", CX.zero)), range: r)
            g.prism("Back Wall", along: 0, profile: PtsA.box((CX.zero, "Height"), ("-Depth", "-Depth + Wall")), range: r)
            g.prism("Divider", along: 0, profile: PtsA.box(("Height / 2 - Wall / 2", "Height / 2 + Wall / 2"), ("-Depth", "-Depth * 0.6")), range: r)
        }
        g.variant("Vertical Profile") { g in
            // Runs up the face (b) beside a tall door: an L channel in plan.
            g.prism("Side Flange", along: 1, profile: PtsA.box((CX.zero, "Wall"), ("-Depth", CX.zero)), range: (CX.zero, "Length"))
            g.prism("Back Wall", along: 1, profile: PtsA.box((CX.zero, "Height"), ("-Depth", "-Depth + Wall")), range: (CX.zero, "Length"))
        }
        g.b.symbol(.face, [.coarse], .rect(("-Length / 2", CX.zero), ("Length / 2", "Height")))
        g.b.symbol(.side, [.coarse], .rect(("-Depth", CX.zero), (CX.zero, "Height")))
        g.b.type("Gola Profile - L 37 mm", [:], cost: 22.00, model: "GL-L37", description: "L handleless profile under the worktop, 37 mm (1 7/16\"), per length", isDefault: true)
        g.b.type("Gola Profile - C 73 mm", ["Height": mm(73), "Depth": mm(27)], flags: ["C Profile": true], texts: ["Profile Type": "C"], cost: 28.00, model: "GL-C73",
                 description: "C handleless profile between drawers, 73 mm (2 7/8\")")
        g.b.type("Gola Profile - Vertical", ["Height": mm(26), "Depth": mm(20), "Length": inch(84)], flags: ["Vertical Profile": true], texts: ["Profile Type": "Vertical"],
                 cost: 34.00, model: "GL-V26", description: "Vertical handleless profile for tall doors")
        return g.build()
    }

    // MARK: Push-to-Open Mechanism

    static func pushToOpen() -> ComponentDefinition {
        var g = faced("Push-to-Open Mechanism", .handles, "Push Openers", "Drill-in push latch in the carcass front edge: push the front and it springs open.")
        g.b.material(finish, .greyPlastic)
        g.b.material("Bumper Material", .rubber)
        g.b.tags("push to open", "push latch", "handleless", "touch", "tip")
        g.b.aliases("push latch", "push opener", "tip opener", "push-open", "touch opener", "drill-in push latch", "10 mm push latch")
        g.b.number("Force", 25, unit: "N", group: .data); g.b.length("Stroke", mm(10)); g.b.length("Position", inch(2), instance: true, group: .placement)
        g.b.length("Body Length", mm(36)); g.b.length("Hole Diameter", mm(10), group: .manufacturing)
        g.b.host([.sidePanel, .top, .bottom, .divider, .shelf], faces: [.frontEdge], align: .top, alignments: [.top, .bottom, .center], offsetY: inch(2))
        g.b.drill("Push latch bore", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Body Length + 0.002 m")
        g.b.requires(.hostThickness(min: "Hole Diameter + 0.004 m", max: nil))
        g.b.requires(.note("Fronts on push openers need no handle and a 1/8\" gap to the latch."))
        // Origin: the front edge at the bore (c points at the door).
        g.cylinder("Body", along: 2, radius: "Hole Diameter / 2", range: ("-Body Length", CX.zero))
        g.revolve("Collar", along: 2, profile: PtsA.turned("Hole Diameter * 0.65", CX.mm(1.5), [(0, 0), (1, 0), (1, 0.6), (0.85, 1), (0, 1)]))
        g.cylinder("Plunger", along: 2, radius: "Hole Diameter * 0.3", range: (CX.mm(1.5), "Stroke"))
        g.using("Bumper Material")
        g.revolve("Bumper", along: 2, profile: PtsA.turned("Hole Diameter * 0.36", CX.mm(3), [(0, 0), (1, 0), (1, 0.4), (0.7, 0.9), (0, 1)]).map { ($0.0, "Stroke + \($0.1)") })
        g.b.symbol(.face, [.coarse], .circle((CX.zero, CX.zero), "Hole Diameter * 0.65"))
        g.b.symbol(.top, [.coarse], .rect(("-Hole Diameter / 2", "-Body Length"), ("Hole Diameter / 2", "Stroke + 0.003 m")))
        g.b.type("Push-to-Open - Standard", [:], cost: 6.50, model: "PO-10S", description: "Drill-in push latch, 10 mm bore, 10 mm (3/8\") stroke", isDefault: true)
        g.b.type("Push-to-Open - Long Stroke", ["Stroke": mm(20), "Body Length": mm(50)], numbers: ["Force": 35], cost: 8.75, model: "PO-10L",
                 description: "Drill-in push latch, 10 mm bore, 20 mm (13/16\") stroke, for tall doors")
        return g.build()
    }

    // MARK: Touch Latch

    static func touchLatch() -> ComponentDefinition {
        var g = faced("Touch Latch", .handles, "Push Openers", "Magnetic touch latch screwed under a top or shelf, with a strike plate on the door.")
        g.b.material(finish, .whitePlastic)
        g.b.material("Strike Material", .steel)
        g.b.tags("touch latch", "magnetic", "push latch", "catch", "handleless")
        g.b.aliases("magnetic touch latch", "push catch", "touch catch", "press latch", "magnetic push latch")
        g.b.length("Length", mm(55)); g.b.length("Width", mm(16)); g.b.length("Height", mm(14)); g.b.length("Stroke", mm(8))
        g.b.length("Mounting Position", mm(2), instance: true, group: .placement)
        g.b.host([.top, .bottom, .shelf, .sidePanel], faces: [.bottom, .top, .inside], align: .center, alignments: [.center, .left, .right])
        g.b.drill("Latch screw", x: CX.zero, y: "Length * 0.3", diameter: CX.mm(3), depth: CX.mm(12))
        g.b.drill("Latch screw", x: CX.zero, y: "Length * 0.75", diameter: CX.mm(3), depth: CX.mm(12))
        // Origin: the latch's front end on the mounting face; the door is toward -b, the latch hangs out along c.
        g.prism("Body", along: 2, profile: PtsA.rounded((CX.zero, "Length / 2 + Mounting Position"), "Width", "Length", CX.mm(2.5)), range: (CX.zero, "Height"))
        g.cylinder("Plunger", along: 1, center: (CX.zero, "Height / 2"), radius: "Height * 0.28", range: ("Mounting Position - Stroke", "Mounting Position"))
        g.using("Strike Material")
        g.cylinder("Magnet", along: 1, center: (CX.zero, "Height / 2"), radius: "Height * 0.32", range: ("Mounting Position - Stroke - 0.002 m", "Mounting Position - Stroke"))
        g.b.symbol(.face, [.coarse], .rect(("-Width / 2", "Mounting Position"), ("Width / 2", "Mounting Position + Length")))
        g.b.symbol(.top, [.coarse], .rect(("-Width / 2", CX.zero), ("Width / 2", "Height")))
        g.b.type("Touch Latch - Standard", [:], cost: 3.95, model: "TL-55", description: "Magnetic touch latch, 55 mm (2 3/16\") body, white", isDefault: true)
        g.b.type("Touch Latch - Heavy Door", ["Length": mm(75), "Width": mm(20), "Height": mm(18), "Stroke": mm(12)], cost: 5.75, model: "TL-75",
                 description: "Magnetic touch latch for heavy doors, 75 mm (3\") body")
        return g.build()
    }
}
