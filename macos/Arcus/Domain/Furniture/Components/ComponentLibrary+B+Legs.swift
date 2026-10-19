import Foundation
import ArcusGeometry

// COMPB: 07 Legs, Feet & Bases. Plan frame (ComponentKit): the origin is the leg's top centre on the underside of the
// part it carries, Z up, so the leg hangs from Z = 0 down to Z = -Height and its foot is on the floor. Legs, feet and
// bases carry the Leg Type role: they are offered in the Leg tool's Type Selector (its Height follows the leg), and
// as components under bottoms, tops and shelves (at the corners, inset from the edges).

extension ComponentLibrary {
    static var groupBLegs: [ComponentDefinition] {
        [roundLeg(), squareLeg(), taperedLeg(), angledLeg(), hairpinLeg(), turnedLeg(), tubeLeg(), adjustableCabinetLeg(), glideUpgrade(),
         hiddenLevelingFoot(), plasticCabinetFoot(), stainlessLeg(), sofaLeg(), tableLeg(), deskLegFrame(), pedestalBase(), crossBase(), tBase(),
         uBase(), sledBase(), cantileverBase(), plinthBase(), toeKick(), decorativeFoot(), foldingLeg(), telescopicLeg(), lockableLeg(),
         heightAdjustableDeskFrame()]
    }

    static let legMaterial = "Leg Material"

    /// A leg or base: plan frame, Leg Type role, the leg material, Height (instance unless the trade sells fixed
    /// heights), hosted under bottoms, tops and shelves at the corners.
    static func legBuilder(_ name: String, _ sub: String, _ description: String, _ finish: ComponentFinish, height: Double, heightInstance: Bool = true,
                           legType: Bool = true, inset: Double = ComponentKit.inch(1)) -> ComponentBuilder {
        var b = ComponentBuilder(name, .legs, sub, description, frame: .plan)
        b.material(legMaterial, finish)
        b.length("Height", height, instance: heightInstance, group: .dimensions, min: ComponentKit.inch(0.25), max: ComponentKit.inch(48))
        if legType { b.role(.legType) }
        b.host([.bottom, .top, .shelf], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight, .center],
               offsetX: inset, offsetY: inset)
        b.snap("Center", x: CX.zero, y: CX.zero)
        return b
    }

    /// Four screws through a square mounting plate of `size` into the part above.
    static func plateScrews(_ b: inout ComponentBuilder, size: String, label: String = "Leg plate screw") {
        for (sx, sy) in [("-", "-"), ("", "-"), ("-", ""), ("", "")] {
            b.drill(label, x: "\(sx)(\(size)) * 0.35", y: "\(sy)(\(size)) * 0.35", diameter: CX.mm(3), depth: CX.mm(13))
        }
    }

    /// A mounting plate under the part: square, `size` wide, `t` thick, screws at Fine.
    static func mountingPlate(_ b: inout ComponentBuilder, size: String, t: String = CX.mm(3), slot: String? = nil) {
        b.slot(slot ?? legMaterial) { b in
            b.plate("Mounting Plate", w: size, h: size, r: "(\(size)) * 0.08", z: ("-(\(t))", CX.zero))
            b.at(CBL.fine) { b in
                b.screwHeads("Plate Screw", [("-(\(size)) * 0.35", "-(\(size)) * 0.35"), ("(\(size)) * 0.35", "-(\(size)) * 0.35"),
                                             ("-(\(size)) * 0.35", "(\(size)) * 0.35"), ("(\(size)) * 0.35", "(\(size)) * 0.35")],
                             z: "-(\(t)) - 0.0012 m", diameter: CX.mm(6), height: CX.mm(1.2))
            }
        }
    }

    /// The hanger bolt hole a wooden leg screws into (5/16" insert or pilot).
    static func hangerBolt(_ b: inout ComponentBuilder) {
        b.length("Hanger Bolt Diameter", ComponentKit.inch(5.0 / 16), group: .manufacturing)
        b.drill("Hanger bolt", x: CX.zero, y: CX.zero, diameter: "Hanger Bolt Diameter", depth: CX.inch(0.75))
    }

    /// Plan outline and side outline for a round leg of diameter `d`.
    static func roundLegSymbols(_ b: inout ComponentBuilder, d: String, foot: String? = nil) {
        b.symCircle(.face, CBL.all, r: "(\(d)) / 2")
        if let foot { b.symCircle(.face, CBL.mediumFine, r: "(\(foot)) / 2", dashed: true) }
        b.symCross(.face, CBL.coarse, s: "(\(d)) * 0.25")
        b.symRect(.side, CBL.coarse, ("-Height", "-(\(d)) / 2"), (CX.zero, "(\(d)) / 2"))
    }

    static func squareLegSymbols(_ b: inout ComponentBuilder, w: String, d: String? = nil) {
        let dd = d ?? w
        b.symRect(.face, CBL.all, ("-(\(w)) / 2", "-(\(dd)) / 2"), ("(\(w)) / 2", "(\(dd)) / 2"))
        b.symRect(.side, CBL.coarse, ("-Height", "-(\(dd)) / 2"), (CX.zero, "(\(dd)) / 2"))
    }

    // MARK: Wooden and metal legs

    static func roundLeg() -> ComponentDefinition {
        var b = legBuilder("Round Leg", "Furniture Legs", "Straight round leg with a small round-over at the foot, on a hanger bolt or a mounting plate.", .oak, height: ComponentKit.inch(28))
        b.tags("leg", "round", "straight", "wood", "table leg", "cylinder")
        b.aliases("round furniture leg", "dowel leg", "cylinder leg", "post leg", "round table leg")
        b.length("Diameter", ComponentKit.inch(1.5))
        b.length("Foot Round-Over", ComponentKit.inch(0.125))
        b.flag("Mounting Plate", false, instance: false)
        b.length("Plate Size", ComponentKit.inch(2.5))
        b.turn("Leg", base: "-Height", [(CX.zero, CX.zero), ("Diameter / 2 - Foot Round-Over", CX.zero), ("Diameter / 2 - Foot Round-Over * 0.3", "Foot Round-Over * 0.3"),
                                         ("Diameter / 2", "Foot Round-Over"), ("Diameter / 2", "Height"), (CX.zero, "Height")])
        b.shown(by: "Mounting Plate") { b in mountingPlate(&b, size: "Plate Size") }
        roundLegSymbols(&b, d: "Diameter")
        hangerBolt(&b)
        b.type("Round Leg - 1 1/2\"", [:], flags: ["Mounting Plate": false], cost: 9.50, model: "RL-150")
        b.type("Round Leg - 2\"", ["Diameter": ComponentKit.inch(2)], flags: ["Mounting Plate": false], cost: 12.50, model: "RL-200", isDefault: true)
        b.type("Round Leg - 2 1/2\" with Plate", ["Diameter": ComponentKit.inch(2.5), "Plate Size": ComponentKit.inch(3)], flags: ["Mounting Plate": true], cost: 17.00, model: "RL-250P")
        return b.build()
    }

    static func squareLeg() -> ComponentDefinition {
        var b = legBuilder("Square Leg", "Furniture Legs", "Straight square leg with chamfered corners.", .oak, height: ComponentKit.inch(28))
        b.tags("leg", "square", "straight", "wood", "table leg", "post")
        b.aliases("square furniture leg", "post leg", "square table leg", "block leg", "parsons leg")
        b.length("Width", ComponentKit.inch(1.75))
        b.length("Corner Chamfer", ComponentKit.inch(0.0625))
        let w = "Width / 2", c = "Width / 2 - Corner Chamfer"
        b.extrusion("Leg", profile: ComponentKit.points([("-\(c)", "-\(w)"), (c, "-\(w)"), (w, "-\(c)"), (w, c), (c, w), ("-\(c)", w), ("-\(w)", c), ("-\(w)", "-\(c)")]),
                    from: "-Height", to: CX.zero)
        squareLegSymbols(&b, w: "Width")
        hangerBolt(&b)
        b.type("Square Leg - 1 1/2\"", ["Width": ComponentKit.inch(1.5)], cost: 8.50, model: "SL-150")
        b.type("Square Leg - 1 3/4\"", [:], cost: 10.50, model: "SL-175", isDefault: true)
        b.type("Square Leg - 2 1/2\"", ["Width": ComponentKit.inch(2.5), "Corner Chamfer": ComponentKit.inch(0.125)], cost: 15.00, model: "SL-250")
        return b.build()
    }

    static func taperedLeg() -> ComponentDefinition {
        var b = legBuilder("Tapered Leg", "Furniture Legs", "Leg that tapers from the top size to a smaller foot below a straight top block (square or round).", .walnut, height: ComponentKit.inch(28))
        b.tags("leg", "tapered", "taper", "mid-century", "wood", "table leg")
        b.aliases("tapered furniture leg", "taper leg", "mid century leg", "danish leg", "tapering leg")
        b.length("Top Size", ComponentKit.inch(1.75))
        b.length("Foot Size", ComponentKit.inch(1))
        b.length("Taper Start", ComponentKit.inch(4), min: 0)
        b.flag("Round Section", false, instance: false)
        b.flag("Square Section", true, formula: "not(Round Section)")
        b.shown(by: "Square Section") { b in
            b.box("Top Block", x: ("-Top Size / 2", "Top Size / 2"), y: ("-Top Size / 2", "Top Size / 2"), z: ("-Taper Start", CX.zero))
            b.taperedBox("Taper", w0: "Foot Size", w1: "Top Size", z: ("-Height", "-Taper Start"))
        }
        b.shown(by: "Round Section") { b in
            b.turn("Leg", base: "-Height", [(CX.zero, CX.zero), ("Foot Size / 2", CX.zero), ("Top Size / 2", "Height - Taper Start"), ("Top Size / 2", "Height"), (CX.zero, "Height")])
        }
        b.symRect(.face, CBL.all, ("-Top Size / 2", "-Top Size / 2"), ("Top Size / 2", "Top Size / 2"))
        b.symRect(.face, CBL.mediumFine, ("-Foot Size / 2", "-Foot Size / 2"), ("Foot Size / 2", "Foot Size / 2"), dashed: true)
        b.symbol(.side, CBL.coarse, .polyline(ComponentKit.points([("-Height", "-Foot Size / 2"), ("-Taper Start", "-Top Size / 2"), (CX.zero, "-Top Size / 2"),
                                                                    (CX.zero, "Top Size / 2"), ("-Taper Start", "Top Size / 2"), ("-Height", "Foot Size / 2")]), closed: true))
        hangerBolt(&b)
        b.type("Tapered Leg - Square 1 3/4\"", [:], flags: ["Round Section": false], cost: 12.00, model: "TL-S175", isDefault: true)
        b.type("Tapered Leg - Round 2\"", ["Top Size": ComponentKit.inch(2), "Foot Size": ComponentKit.inch(1.125), "Taper Start": 0], flags: ["Round Section": true],
               cost: 13.50, model: "TL-R200")
        b.type("Tapered Leg - Square 2 1/2\"", ["Top Size": ComponentKit.inch(2.5), "Foot Size": ComponentKit.inch(1.5), "Taper Start": ComponentKit.inch(5)],
               flags: ["Round Section": false], cost: 17.50, model: "TL-S250")
        return b.build()
    }

    static func angledLeg() -> ComponentDefinition {
        var b = legBuilder("Angled Leg", "Furniture Legs", "Splayed round leg on an angled mounting plate; the foot leans out from the corner by the splay angle.", .walnut,
                           height: ComponentKit.inch(16))
        b.tags("leg", "angled", "splayed", "mid-century", "tapered", "wood", "sofa", "coffee table")
        b.aliases("splayed leg", "angle leg", "slanted leg", "raked leg", "mid century modern leg", "angled plate leg")
        b.length("Top Diameter", ComponentKit.inch(1.75))
        b.length("Foot Diameter", ComponentKit.inch(1))
        b.angle("Splay Angle", 15)
        b.length("Plate Size", ComponentKit.inch(3))
        b.length("Splay Offset", 0, formula: "Height * tan(Splay Angle) * 0.7071")
        b.strut("Leg", bottom: ("-Splay Offset", "-Splay Offset"), top: (CX.zero, CX.zero), r0: "Foot Diameter / 2", r1: "Top Diameter / 2", z: ("-Height", CX.mm(-6)), sides: 24)
        b.slot(legMaterial) { b in
            b.slot("Plate Material") { b in
                b.plate("Angled Plate", w: "Plate Size", h: "Plate Size", r: "Plate Size * 0.1", z: (CX.mm(-6), CX.zero))
            }
        }
        b.material("Plate Material", .zinc)
        b.symCircle(.face, CBL.all, r: "Top Diameter / 2")
        b.symCircle(.face, CBL.all, c: ("-Splay Offset", "-Splay Offset"), r: "Foot Diameter / 2", dashed: true)
        b.symRect(.face, CBL.coarse, ("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2"))
        b.symbol(.side, CBL.coarse, .line(("-Height", "-Splay Offset"), (CX.zero, CX.zero)))
        plateScrews(&b, size: "Plate Size")
        b.type("Angled Leg - 10° 6\"", ["Height": ComponentKit.inch(6), "Top Diameter": ComponentKit.inch(1.5), "Foot Diameter": ComponentKit.inch(0.875)],
               numbers: ["Splay Angle": 10 * .pi / 180], cost: 9.00, model: "AL-1006")
        b.type("Angled Leg - 15° 16\"", ["Height": ComponentKit.inch(16)], numbers: ["Splay Angle": 15 * .pi / 180], cost: 14.00, model: "AL-1516", isDefault: true)
        b.type("Angled Leg - 10° 28\"", ["Height": ComponentKit.inch(28), "Top Diameter": ComponentKit.inch(2)], numbers: ["Splay Angle": 10 * .pi / 180], cost: 19.00, model: "AL-1028")
        return b.build()
    }

    static func hairpinLeg() -> ComponentDefinition {
        var b = legBuilder("Hairpin Leg", "Metal Legs", "Steel hairpin leg: rods bent into a U at the foot, welded to a top plate.", .matteBlack, height: ComponentKit.inch(28))
        b.tags("leg", "hairpin", "metal", "steel", "rod", "mid-century", "industrial")
        b.aliases("hair pin leg", "rod leg", "wire leg", "v leg", "steel hairpin")
        b.length("Rod Diameter", ComponentKit.inch(0.375))
        b.length("Spread", ComponentKit.inch(4))
        b.length("Plate Length", ComponentKit.inch(4.5))
        b.length("Plate Width", ComponentKit.inch(1.5))
        b.length("Plate Thickness", ComponentKit.inch(0.1875))
        b.flag("Third Rod", false, instance: false)
        let r = "Rod Diameter / 2", z = ("-Height + Rod Diameter", "-Plate Thickness")
        for (k, s) in ["-", ""].enumerated() {
            b.strut("Rod \(k + 1)", bottom: ("\(s)Rod Diameter * 0.7", CX.zero), top: ("\(s)(Spread / 2 - Rod Diameter)", CX.zero), r0: r, r1: r, z: z, sides: 16)
        }
        b.rod("Foot Bend", axis: .x, c: (CX.zero, "-Height + Rod Diameter"), r: r, from: "-Rod Diameter * 1.2", to: "Rod Diameter * 1.2", sides: 16)
        b.rod("Foot", r: "Rod Diameter * 0.75", from: "-Height", to: "-Height + Rod Diameter", sides: 16)
        b.shown(by: "Third Rod") { b in
            b.strut("Rod 3", bottom: (CX.zero, "Rod Diameter * 0.7"), top: (CX.zero, "Plate Width / 2 - Rod Diameter"), r0: r, r1: r, z: z, sides: 16)
        }
        b.box("Top Plate", x: ("-Plate Length / 2", "Plate Length / 2"), y: ("-Plate Width / 2", "Plate Width / 2"), z: ("-Plate Thickness", CX.zero))
        b.symRect(.face, CBL.all, ("-Plate Length / 2", "-Plate Width / 2"), ("Plate Length / 2", "Plate Width / 2"))
        b.symCircle(.face, CBL.mediumFine, r: "Rod Diameter", dashed: true)
        b.symbol(.side, CBL.coarse, .line(("-Height", CX.zero), (CX.zero, CX.zero)))
        for x in ["-Plate Length * 0.4", "Plate Length * 0.4"] {
            b.drill("Hairpin plate screw", x: x, y: CX.zero, diameter: CX.mm(3), depth: CX.mm(16))
        }
        b.type("Hairpin Leg - 2 Rod 3/8\"", [:], flags: ["Third Rod": false], cost: 14.00, model: "HP-2R38", isDefault: true)
        b.type("Hairpin Leg - 2 Rod 1/2\"", ["Rod Diameter": ComponentKit.inch(0.5), "Spread": ComponentKit.inch(5)], flags: ["Third Rod": false], cost: 18.00, model: "HP-2R12")
        b.type("Hairpin Leg - 3 Rod 1/2\"", ["Rod Diameter": ComponentKit.inch(0.5), "Spread": ComponentKit.inch(5), "Plate Width": ComponentKit.inch(4.5)],
               flags: ["Third Rod": true], cost: 24.00, model: "HP-3R12")
        return b.build()
    }

    static func turnedLeg() -> ComponentDefinition {
        var b = legBuilder("Turned Leg", "Furniture Legs", "Classic turned leg: square pommel where the aprons join, then vase, bead and cove down to a turned foot.", .maple,
                           height: ComponentKit.inch(28.5))
        b.tags("leg", "turned", "lathe", "traditional", "wood", "table leg", "vase")
        b.aliases("turned wooden leg", "spindle leg", "lathe turned leg", "colonial leg", "farmhouse leg", "baluster leg")
        b.length("Diameter", ComponentKit.inch(2.5))
        b.length("Pommel Length", ComponentKit.inch(5))
        b.length("Body Length", 0, formula: "Height - Pommel Length")
        b.box("Pommel", x: ("-Diameter / 2", "Diameter / 2"), y: ("-Diameter / 2", "Diameter / 2"), z: ("-Pommel Length", CX.zero))
        // Radii as shares of the size, heights as shares of the turned body.
        let prof: [(Double, Double)] = [(0, 0), (0.30, 0), (0.32, 0.02), (0.38, 0.05), (0.30, 0.08), (0.21, 0.18), (0.27, 0.42), (0.35, 0.58),
                                        (0.27, 0.68), (0.42, 0.74), (0.42, 0.79), (0.32, 0.83), (0.38, 0.93), (0.30, 0.97), (0.36, 1), (0, 1)]
        b.turn("Turned Body", base: "-Height", prof.map { ("Diameter * \(LX.num($0.0))", "Body Length * \(LX.num($0.1))") })
        roundLegSymbols(&b, d: "Diameter")
        b.symRect(.face, CBL.mediumFine, ("-Diameter / 2", "-Diameter / 2"), ("Diameter / 2", "Diameter / 2"))
        hangerBolt(&b)
        b.type("Turned Leg - 2 1/2\"", [:], cost: 22.00, model: "TU-250", isDefault: true)
        b.type("Turned Leg - 3\"", ["Diameter": ComponentKit.inch(3), "Pommel Length": ComponentKit.inch(5.5)], cost: 28.00, model: "TU-300")
        b.type("Turned Leg - 3 1/2\" Island", ["Diameter": ComponentKit.inch(3.5), "Pommel Length": ComponentKit.inch(6), "Height": ComponentKit.inch(34.5)], cost: 42.00, model: "TU-350I")
        return b.build()
    }

    static func tubeLeg() -> ComponentDefinition {
        var b = legBuilder("Tube Leg", "Metal Legs", "Round steel tube leg with a welded mounting plate and a plastic end cap.", .matteBlack, height: ComponentKit.inch(28))
        b.tags("leg", "tube", "metal", "steel", "round tube", "industrial", "modern")
        b.aliases("metal tube leg", "steel tube leg", "pipe leg", "round metal leg", "tubular leg")
        b.material("Cap Material", .blackPlastic)
        b.length("Tube Diameter", ComponentKit.inch(1.5))
        b.length("Wall Thickness", ComponentKit.inch(0.0625))
        b.length("Plate Size", ComponentKit.inch(3))
        b.length("Cap Height", ComponentKit.inch(0.25))
        b.pipe("Tube", outer: "Tube Diameter / 2", inner: "Tube Diameter / 2 - Wall Thickness", from: "-Height + Cap Height", to: "-0.003 m")
        mountingPlate(&b, size: "Plate Size")
        b.slot("Cap Material") { b in
            b.turn("End Cap", base: "-Height", [(CX.zero, CX.zero), ("Tube Diameter / 2 - 0.001 m", CX.zero), ("Tube Diameter / 2", "0.001 m"), ("Tube Diameter / 2", "Cap Height"), (CX.zero, "Cap Height")])
        }
        roundLegSymbols(&b, d: "Tube Diameter")
        b.symRect(.face, CBL.mediumFine, ("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2"), dashed: true)
        plateScrews(&b, size: "Plate Size")
        b.type("Tube Leg - 1\"", ["Tube Diameter": ComponentKit.inch(1), "Plate Size": ComponentKit.inch(2.5)], cost: 11.00, model: "TB-100")
        b.type("Tube Leg - 1 1/2\"", [:], cost: 14.00, model: "TB-150", isDefault: true)
        b.type("Tube Leg - 2\"", ["Tube Diameter": ComponentKit.inch(2), "Plate Size": ComponentKit.inch(3.5), "Wall Thickness": ComponentKit.inch(0.08)], cost: 18.00, model: "TB-200")
        return b.build()
    }

    static func stainlessLeg() -> ComponentDefinition {
        var b = legBuilder("Stainless Steel Leg", "Metal Legs", "Brushed stainless round leg with a screw-adjustable foot and a round mounting flange (islands, counters, benches).", .stainless,
                           height: ComponentKit.mm(870))
        b.tags("leg", "stainless", "steel", "metal", "kitchen island", "counter", "adjustable", "60 mm")
        b.aliases("stainless steel leg", "island leg", "counter leg", "breakfast bar leg", "worktop leg", "chrome leg")
        b.length("Diameter", ComponentKit.mm(60))
        b.length("Flange Diameter", ComponentKit.mm(100))
        b.length("Foot Diameter", ComponentKit.mm(50))
        b.length("Adjustment", ComponentKit.mm(20), min: 0, max: ComponentKit.mm(30))
        b.rod("Flange", r: "Flange Diameter / 2", from: CX.mm(-4), to: CX.zero)
        b.rod("Tube", r: "Diameter / 2", from: "-Height + Adjustment + 0.012 m", to: CX.mm(-4))
        b.rod("Foot Thread", r: CX.mm(5), from: "-Height + 0.01 m", to: "-Height + Adjustment + 0.012 m")
        b.turn("Foot", base: "-Height", [(CX.zero, CX.zero), ("Foot Diameter / 2", CX.zero), ("Foot Diameter / 2", "0.006 m"), ("Foot Diameter / 2 - 0.006 m", "0.012 m"), (CX.zero, "0.012 m")])
        roundLegSymbols(&b, d: "Diameter", foot: "Flange Diameter")
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            b.drill("Flange screw", x: "Flange Diameter * \(LX.num(0.38 * cos(a)))", y: "Flange Diameter * \(LX.num(0.38 * sin(a)))", diameter: CX.mm(3), depth: CX.mm(13))
        }
        b.type("Stainless Leg - 30 mm", ["Diameter": ComponentKit.mm(30), "Flange Diameter": ComponentKit.mm(60), "Foot Diameter": ComponentKit.mm(30), "Height": ComponentKit.mm(710)],
               cost: 14.00, model: "SSL-30")
        b.type("Stainless Leg - 50 mm", ["Diameter": ComponentKit.mm(50), "Flange Diameter": ComponentKit.mm(85), "Foot Diameter": ComponentKit.mm(45)], cost: 21.00, model: "SSL-50")
        b.type("Stainless Leg - 60 mm", [:], cost: 26.00, model: "SSL-60", isDefault: true)
        return b.build()
    }

    // MARK: Cabinet feet

    static func adjustableCabinetLeg() -> ComponentDefinition {
        var b = legBuilder("Adjustable Cabinet Leg", "Cabinet Legs", "Plastic cabinet leg screwed under the bottom: a column on a threaded base, adjustable from the front, with a clip for the plinth.",
                           .blackPlastic, height: ComponentKit.mm(100), inset: ComponentKit.inch(2))
        b.tags("cabinet leg", "adjustable", "leveler", "plinth", "kitchen", "base cabinet", "100 mm", "150 mm")
        b.aliases("adjustable cabinet leg", "cabinet leveler", "kitchen leg", "plinth leg", "base unit leg", "leveling leg")
        b.length("Minimum Height", ComponentKit.mm(100))
        b.length("Maximum Height", ComponentKit.mm(125))
        b.length("Plate Diameter", ComponentKit.mm(65))
        b.length("Column Diameter", ComponentKit.mm(30))
        b.length("Base Diameter", ComponentKit.mm(55))
        b.flag("Plinth Clip", true, instance: false)
        b.requires(.note("Height between the type's Minimum and Maximum Height."))
        b.rod("Mounting Plate", r: "Plate Diameter / 2", from: CX.mm(-4), to: CX.zero)
        b.rod("Column", r: "Column Diameter / 2", from: "-Height + 0.02 m", to: CX.mm(-4))
        b.at(CBL.fine) { b in
            for k in 0..<4 {
                let a = Double(k) * .pi / 2
                b.box("Rib \(k + 1)", x: ("Column Diameter * \(LX.num(0.5 * cos(a))) - 0.0015 m", "Column Diameter * \(LX.num(0.5 * cos(a))) + 0.0015 m"),
                      y: ("Column Diameter * \(LX.num(0.5 * sin(a))) - 0.0015 m", "Column Diameter * \(LX.num(0.5 * sin(a))) + 0.0015 m"), z: (CX.mm(-30), CX.mm(-4)))
            }
        }
        b.rod("Thread", r: "Column Diameter * 0.35", from: "-Height + 0.012 m", to: "-Height + 0.02 m")
        b.turn("Base", base: "-Height", [(CX.zero, CX.zero), ("Base Diameter / 2", CX.zero), ("Base Diameter / 2", "0.007 m"), ("Column Diameter * 0.45", "0.012 m"), (CX.zero, "0.012 m")])
        b.shown(by: "Plinth Clip") { b in
            b.box("Plinth Clip", x: ("-Column Diameter * 0.35", "Column Diameter * 0.35"), y: ("-Column Diameter / 2 - 0.012 m", "-Column Diameter / 2"), z: (CX.mm(-60), CX.mm(-25)))
        }
        roundLegSymbols(&b, d: "Base Diameter", foot: "Plate Diameter")
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            b.drill("Cabinet leg screw", x: "Plate Diameter * \(LX.num(0.36 * cos(a)))", y: "Plate Diameter * \(LX.num(0.36 * sin(a)))", diameter: CX.mm(3.5), depth: CX.mm(13))
        }
        let mm = ComponentKit.mm
        b.type("Cabinet Leg - 100 mm", ["Minimum Height": mm(100), "Maximum Height": mm(125)], flags: ["Plinth Clip": true], cost: 1.10, model: "ACL-100", isDefault: true)
        b.type("Cabinet Leg - 120 mm", ["Height": mm(120), "Minimum Height": mm(120), "Maximum Height": mm(150)], flags: ["Plinth Clip": true], cost: 1.25, model: "ACL-120")
        b.type("Cabinet Leg - 150 mm", ["Height": mm(150), "Minimum Height": mm(150), "Maximum Height": mm(180), "Column Diameter": mm(35)], flags: ["Plinth Clip": true],
               cost: 1.45, model: "ACL-150")
        return b.build()
    }

    /// FM5's Adjustable Glide is the trade's leveling foot: upgraded with a hex nut and a swivel ball at Fine and a 2" heavy type.
    static func glideUpgrade() -> ComponentDefinition {
        guard var b = ComponentBuilder(upgrading: FurnitureHardware.glide) else { return plasticCabinetFoot() }
        b.smoothCircles()
        b.tags("leveling foot", "leveling feet", "leveler", "glide", "foot", "adjustable", "5/16", "3/8", "m8", "m10")
        b.aliases("levelling foot", "adjustable foot", "screw foot", "swivel leveler", "furniture leveler", "machine foot")
        b.length("Nut Size", ComponentKit.mm(13), group: .dimensions)
        b.at(CBL.fine) { b in
            b.rod("Hex Nut", r: "Nut Size / 2", from: "-Height + 0.005 m", to: "-Height + 0.009 m", sides: 6)
            b.rod("Ball", r: "Diameter * 0.18", from: "-Height + 0.005 m", to: "-Height + 0.008 m")
        }
        roundLegSymbolsNoSide(&b, d: "Diameter")
        b.symRect(.side, CBL.coarse, ("-Height", "-Diameter / 2"), (CX.zero, "Diameter / 2"))
        b.drill("Leveler insert", x: CX.zero, y: CX.zero, diameter: "Hole Diameter", depth: "Hole Depth")
        b.type("2\" Heavy Leveler", ["Diameter": ComponentKit.inch(2), "Height": ComponentKit.inch(1.25), "Insert Diameter": ComponentKit.mm(14), "Hole Diameter": ComponentKit.mm(14),
                                      "Hole Depth": ComponentKit.mm(19), "Nut Size": ComponentKit.mm(17)],
               cost: 2.60, model: "GL-200", description: "Heavy leveling foot, 2\" swivel pad, 1/2\" thread")
        return b.build()
    }

    static func roundLegSymbolsNoSide(_ b: inout ComponentBuilder, d: String) {
        b.symCircle(.face, CBL.all, r: "(\(d)) / 2")
        b.symCross(.face, CBL.coarse, s: "(\(d)) * 0.25")
    }

    static func hiddenLevelingFoot() -> ComponentDefinition {
        var b = legBuilder("Hidden Leveling Foot", "Leveling Feet", "Concealed leveler in a bore through the bottom: adjusted from inside the cabinet with a screwdriver; only the pad shows.",
                           .blackPlastic, height: ComponentKit.mm(10), heightInstance: true, legType: false, inset: ComponentKit.inch(1.5))
        b.tags("hidden leveling foot", "concealed leveler", "inside adjust", "leveler", "foot", "30 mm")
        b.aliases("concealed leveling foot", "hidden leveler", "inside adjustable glide", "recessed leveler", "furniture adjuster")
        b.length("Bore Diameter", ComponentKit.mm(30))
        b.length("Pad Diameter", ComponentKit.mm(28))
        b.length("Housing Depth", ComponentKit.mm(16))
        b.length("Adjustment", ComponentKit.mm(15))
        b.rod("Housing", r: "Bore Diameter / 2", from: CX.zero, to: "Housing Depth")
        b.rod("Flange", r: "Bore Diameter / 2 + 0.003 m", from: "Housing Depth", to: "Housing Depth + 0.0015 m")
        b.rod("Screw", r: CX.mm(4), from: "-Height + 0.004 m", to: "Housing Depth")
        b.turn("Pad", base: "-Height", [(CX.zero, CX.zero), ("Pad Diameter / 2", CX.zero), ("Pad Diameter / 2", "0.003 m"), ("Pad Diameter / 2 - 0.002 m", "0.005 m"), (CX.zero, "0.005 m")])
        b.at(CBL.fine) { b in b.box("Screwdriver Slot", x: ("-Bore Diameter * 0.2", "Bore Diameter * 0.2"), y: (CX.mm(-0.7), CX.mm(0.7)), z: ("Housing Depth - 0.002 m", "Housing Depth + 0.002 m"), void: true) }
        b.symCircle(.face, CBL.all, r: "Pad Diameter / 2")
        b.symCircle(.face, CBL.mediumFine, r: "Bore Diameter / 2 + 0.003 m", dashed: true)
        b.symRect(.side, CBL.coarse, ("-Height", "-Pad Diameter / 2"), ("Housing Depth", "Pad Diameter / 2"))
        b.drill("Hidden leveler bore", x: CX.zero, y: CX.zero, diameter: "Bore Diameter", depth: "Host Thickness", through: true)
        b.requires(.hostThickness(min: "Housing Depth", max: nil))
        let mm = ComponentKit.mm
        b.type("Hidden Leveler - 30 mm", [:], cost: 1.90, model: "HLF-30", isDefault: true)
        b.type("Hidden Leveler - 40 mm", ["Bore Diameter": mm(40), "Pad Diameter": mm(38), "Housing Depth": mm(18), "Adjustment": mm(20)], cost: 2.60, model: "HLF-40")
        return b.build()
    }

    static func plasticCabinetFoot() -> ComponentDefinition {
        var b = legBuilder("Plastic Cabinet Foot", "Cabinet Legs", "Fixed moulded foot screwed under a cabinet or box: round, or square for cubes and bookcases.", .blackPlastic,
                           height: ComponentKit.mm(25), heightInstance: false, inset: ComponentKit.inch(1))
        b.tags("cabinet foot", "plastic foot", "fixed foot", "box foot", "bookcase foot", "25 mm", "50 mm")
        b.aliases("plastic furniture foot", "cabinet feet", "screw-on foot", "riser foot", "furniture riser")
        b.length("Diameter", ComponentKit.mm(38))
        b.flag("Square", false, instance: false)
        b.flag("Round", true, formula: "not(Square)")
        b.shown(by: "Round") { b in
            b.turn("Foot", base: "-Height", [(CX.zero, CX.zero), ("Diameter / 2 - 0.002 m", CX.zero), ("Diameter / 2", "0.002 m"), ("Diameter / 2", "Height"), (CX.zero, "Height")])
        }
        b.shown(by: "Square") { b in b.plate("Foot", w: "Diameter", h: "Diameter", r: "Diameter * 0.12", z: ("-Height", CX.zero)) }
        b.at(CBL.fine) { b in b.rod("Screw Recess", r: CX.mm(4), from: "-Height - 0.0005 m", to: "-Height + 0.004 m", void: true, sides: 16) }
        roundLegSymbolsNoSide(&b, d: "Diameter")
        b.symRect(.side, CBL.coarse, ("-Height", "-Diameter / 2"), (CX.zero, "Diameter / 2"))
        b.drill("Foot screw", x: CX.zero, y: CX.zero, diameter: CX.mm(3), depth: CX.mm(13))
        let mm = ComponentKit.mm
        b.type("Cabinet Foot - 25 mm", [:], flags: ["Square": false], cost: 0.45, model: "PCF-25", isDefault: true)
        b.type("Cabinet Foot - 40 mm", ["Height": mm(40), "Diameter": mm(45)], flags: ["Square": false], cost: 0.65, model: "PCF-40")
        b.type("Cabinet Foot - 50 mm Square", ["Height": mm(50), "Diameter": mm(40)], flags: ["Square": true], cost: 0.85, model: "PCF-50S")
        return b.build()
    }

    static func sofaLeg() -> ComponentDefinition {
        var b = legBuilder("Sofa Leg", "Sofa Legs", "Short sofa or chair leg on a hanger bolt: tapered round, or a bun.", .walnut, height: ComponentKit.inch(4), heightInstance: false,
                           inset: ComponentKit.inch(2))
        b.tags("sofa leg", "couch leg", "short leg", "tapered", "bun", "upholstery", "4 inch", "6 inch")
        b.aliases("couch leg", "sofa foot", "settee leg", "ottoman leg", "chair leg short", "bun foot")
        b.length("Top Diameter", ComponentKit.inch(2))
        b.length("Foot Diameter", ComponentKit.inch(1.25))
        b.flag("Bun", false, instance: false)
        b.flag("Tapered", true, formula: "not(Bun)")
        b.material("Ferrule Material", .brass)
        b.flag("Ferrule", false, instance: false)
        b.shown(by: "Tapered") { b in
            b.turn("Leg", base: "-Height", [(CX.zero, CX.zero), ("Foot Diameter / 2", CX.zero), ("Top Diameter / 2", "Height"), (CX.zero, "Height")])
        }
        b.shown(by: "Bun") { b in
            let pts = (0...12).map { k -> (String, String) in
                let t = Double(k) / 12, a = -Double.pi / 2 + .pi * t
                return ("Top Diameter / 2 * \(LX.num(0.55 + 0.45 * cos(a)))", "Height * \(LX.num(0.5 + 0.5 * sin(a)))")
            }
            b.turn("Bun", base: "-Height", [(CX.zero, CX.zero)] + pts + [(CX.zero, "Height")])
        }
        b.shown(by: "Ferrule") { b in
            b.slot("Ferrule Material") { b in b.rod("Ferrule", r: "Foot Diameter / 2 + 0.0005 m", from: "-Height", to: "-Height + 0.012 m") }
        }
        roundLegSymbols(&b, d: "Top Diameter", foot: "Foot Diameter")
        hangerBolt(&b)
        b.type("Sofa Leg - 4\" Tapered", [:], flags: ["Bun": false, "Ferrule": false], cost: 6.50, model: "SOL-4T", isDefault: true)
        b.type("Sofa Leg - 6\" Tapered Brass Tip", ["Height": ComponentKit.inch(6)], flags: ["Bun": false, "Ferrule": true], cost: 9.50, model: "SOL-6TB")
        b.type("Sofa Leg - 3\" Bun", ["Height": ComponentKit.inch(3), "Top Diameter": ComponentKit.inch(3)], flags: ["Bun": true, "Ferrule": false], cost: 7.50, model: "SOL-3B")
        return b.build()
    }

    static func tableLeg() -> ComponentDefinition {
        var b = legBuilder("Table Leg", "Table Legs", "Square table leg tapered on its two inside faces below the apron (Shaker style), with a straight block where the apron joins.",
                           .oak, height: ComponentKit.inch(29.25))
        b.tags("table leg", "dining table", "square", "tapered", "shaker", "apron", "wood")
        b.aliases("dining table leg", "shaker leg", "inside taper leg", "apron leg", "kitchen table leg")
        b.length("Width", ComponentKit.inch(2.25))
        b.length("Foot Size", ComponentKit.inch(1.375))
        b.length("Apron Height", ComponentKit.inch(4.5))
        // The outside faces (−X, −Y at the front-left corner) stay plumb; the inside faces taper.
        b.box("Apron Block", x: ("-Width / 2", "Width / 2"), y: ("-Width / 2", "Width / 2"), z: ("-Apron Height", CX.zero))
        b.blend("Taper", bottom: ComponentKit.points([("-Width / 2", "-Width / 2"), ("-Width / 2 + Foot Size", "-Width / 2"), ("-Width / 2 + Foot Size", "-Width / 2 + Foot Size"),
                                                      ("-Width / 2", "-Width / 2 + Foot Size")]),
                top: ComponentKit.rect(width: "Width", height: "Width"), from: "-Height", to: "-Apron Height")
        squareLegSymbols(&b, w: "Width")
        b.symRect(.face, CBL.mediumFine, ("-Width / 2", "-Width / 2"), ("-Width / 2 + Foot Size", "-Width / 2 + Foot Size"), dashed: true)
        hangerBolt(&b)
        b.type("Table Leg - 2 1/4\" x 29 1/4\"", [:], cost: 18.00, model: "TBL-225", isDefault: true)
        b.type("Table Leg - 3\" x 29 1/4\"", ["Width": ComponentKit.inch(3), "Foot Size": ComponentKit.inch(1.75), "Apron Height": ComponentKit.inch(5)], cost: 24.00, model: "TBL-300")
        b.type("Table Leg - 1 3/4\" x 17\" Coffee", ["Width": ComponentKit.inch(1.75), "Foot Size": ComponentKit.inch(1.125), "Apron Height": ComponentKit.inch(3), "Height": ComponentKit.inch(17)],
               cost: 13.00, model: "TBL-175C")
        return b.build()
    }

    // MARK: Frames and bases

    static func deskLegFrame() -> ComponentDefinition {
        var b = legBuilder("Desk Leg Frame", "Desk Legs", "Welded steel end frame for a desk or table: square tube rectangle with feet at front and back.", .matteBlack,
                           height: ComponentKit.inch(28.5), inset: ComponentKit.inch(2))
        b.tags("desk leg", "desk frame", "end frame", "steel", "square tube", "industrial", "office")
        b.aliases("desk legs", "table frame leg", "metal desk leg", "office desk leg", "box leg", "o-leg")
        b.material("Glide Material", .blackPlastic)
        b.length("Frame Depth", ComponentKit.inch(24))
        b.length("Tube Size", ComponentKit.inch(2))
        b.length("Wall Thickness", ComponentKit.inch(0.0625))
        let y = ("-Frame Depth / 2", "Frame Depth / 2"), x = ("-Tube Size / 2", "Tube Size / 2")
        b.box("Top Bar", x: x, y: y, z: ("-Tube Size", CX.zero))
        b.box("Foot Bar", x: x, y: y, z: ("-Height + 0.006 m", "-Height + 0.006 m + Tube Size"))
        b.box("Front Post", x: x, y: ("-Frame Depth / 2", "-Frame Depth / 2 + Tube Size"), z: ("-Height + 0.006 m + Tube Size", "-Tube Size"))
        b.box("Back Post", x: x, y: ("Frame Depth / 2 - Tube Size", "Frame Depth / 2"), z: ("-Height + 0.006 m + Tube Size", "-Tube Size"))
        b.slot("Glide Material") { b in
            for (k, yy) in ["-Frame Depth / 2 + Tube Size / 2", "Frame Depth / 2 - Tube Size / 2"].enumerated() {
                b.rod("Glide \(k + 1)", c: (CX.zero, yy), r: "Tube Size * 0.4", from: "-Height", to: "-Height + 0.006 m")
            }
        }
        b.symRect(.face, CBL.all, ("-Tube Size / 2", "-Frame Depth / 2"), ("Tube Size / 2", "Frame Depth / 2"))
        b.symRect(.side, CBL.coarse, ("-Height", "-Frame Depth / 2"), (CX.zero, "Frame Depth / 2"))
        for yy in ["-Frame Depth * 0.4", "Frame Depth * 0.4", CX.zero] { b.drill("Frame screw", x: CX.zero, y: yy, diameter: CX.mm(4), depth: CX.mm(16)) }
        b.type("Desk Leg Frame - 20\"", ["Frame Depth": ComponentKit.inch(20)], cost: 38.00, model: "DLF-20")
        b.type("Desk Leg Frame - 24\"", [:], cost: 42.00, model: "DLF-24", isDefault: true)
        b.type("Desk Leg Frame - 28\"", ["Frame Depth": ComponentKit.inch(28), "Tube Size": ComponentKit.inch(2.5)], cost: 48.00, model: "DLF-28")
        return b.build()
    }

    static func pedestalBase() -> ComponentDefinition {
        var b = legBuilder("Pedestal Base", "Table Bases", "Single-column table base: a round foot disc, a column and a top plate.", .matteBlack, height: ComponentKit.inch(28.25),
                           inset: 0)
        b.tags("pedestal base", "table base", "column", "round base", "bistro", "cafe table", "single leg")
        b.aliases("pedestal table base", "tulip base", "bistro base", "column base", "disc base", "cafe base")
        b.host([.top], faces: [.bottom], align: .center)
        b.length("Base Diameter", ComponentKit.inch(22))
        b.length("Base Thickness", ComponentKit.inch(0.75))
        b.length("Column Diameter", ComponentKit.inch(3))
        b.length("Top Plate Size", ComponentKit.inch(12))
        b.turn("Foot Disc", base: "-Height", [(CX.zero, CX.zero), ("Base Diameter / 2 - 0.004 m", CX.zero), ("Base Diameter / 2", "0.004 m"),
                                               ("Base Diameter / 2", "Base Thickness * 0.6"), ("Column Diameter", "Base Thickness"), (CX.zero, "Base Thickness")])
        b.rod("Column", r: "Column Diameter / 2", from: "-Height + Base Thickness", to: CX.mm(-6))
        b.box("Top Plate", x: ("-Top Plate Size / 2", "Top Plate Size / 2"), y: ("-Top Plate Size / 2", "Top Plate Size / 2"), z: (CX.mm(-6), CX.zero))
        b.symCircle(.face, CBL.all, r: "Base Diameter / 2")
        b.symCircle(.face, CBL.all, r: "Column Diameter / 2")
        b.symRect(.face, CBL.mediumFine, ("-Top Plate Size / 2", "-Top Plate Size / 2"), ("Top Plate Size / 2", "Top Plate Size / 2"), dashed: true)
        b.symRect(.side, CBL.coarse, ("-Height", "-Base Diameter / 2"), ("-Height + Base Thickness", "Base Diameter / 2"))
        plateScrews(&b, size: "Top Plate Size")
        b.type("Pedestal Base - 18\"", ["Base Diameter": ComponentKit.inch(18), "Top Plate Size": ComponentKit.inch(10)], cost: 65.00, model: "PB-18")
        b.type("Pedestal Base - 22\"", [:], cost: 85.00, model: "PB-22", isDefault: true)
        b.type("Pedestal Base - 28\"", ["Base Diameter": ComponentKit.inch(28), "Column Diameter": ComponentKit.inch(4), "Top Plate Size": ComponentKit.inch(16), "Base Thickness": ComponentKit.inch(1)],
               cost: 120.00, model: "PB-28")
        return b.build()
    }

    static func crossBase() -> ComponentDefinition {
        var b = legBuilder("Cross Base", "Table Bases", "X-shaped table base: two crossed flat bars at the floor, a column and a cross top plate.", .matteBlack, height: ComponentKit.inch(28.25), inset: 0)
        b.tags("cross base", "x base", "table base", "four star", "column", "cafe table")
        b.aliases("x-base", "cross table base", "4-prong base", "spider base", "star base")
        b.host([.top], faces: [.bottom], align: .center)
        b.length("Span", ComponentKit.inch(22))
        b.length("Arm Width", ComponentKit.inch(2.5))
        b.length("Arm Thickness", ComponentKit.inch(0.5))
        b.length("Column Diameter", ComponentKit.inch(3))
        b.length("Top Span", ComponentKit.inch(14))
        b.material("Glide Material", .blackPlastic)
        let fz = ("-Height + 0.005 m", "-Height + 0.005 m + Arm Thickness")
        b.box("Arm A", x: ("-Span / 2", "Span / 2"), y: ("-Arm Width / 2", "Arm Width / 2"), z: fz)
        b.box("Arm B", x: ("-Arm Width / 2", "Arm Width / 2"), y: ("-Span / 2", "Span / 2"), z: fz)
        b.rod("Column", r: "Column Diameter / 2", from: "-Height + 0.005 m + Arm Thickness", to: CX.mm(-6))
        b.box("Top Bar A", x: ("-Top Span / 2", "Top Span / 2"), y: ("-Arm Width / 2", "Arm Width / 2"), z: (CX.mm(-6), CX.zero))
        b.box("Top Bar B", x: ("-Arm Width / 2", "Arm Width / 2"), y: ("-Top Span / 2", "Top Span / 2"), z: (CX.mm(-6), CX.zero))
        b.slot("Glide Material") { b in
            for (k, c) in [("-Span / 2 + 0.02 m", CX.zero), ("Span / 2 - 0.02 m", CX.zero), (CX.zero, "-Span / 2 + 0.02 m"), (CX.zero, "Span / 2 - 0.02 m")].enumerated() {
                b.rod("Glide \(k + 1)", c: c, r: CX.mm(12), from: "-Height", to: "-Height + 0.005 m")
            }
        }
        b.symRect(.face, CBL.all, ("-Span / 2", "-Arm Width / 2"), ("Span / 2", "Arm Width / 2"))
        b.symRect(.face, CBL.all, ("-Arm Width / 2", "-Span / 2"), ("Arm Width / 2", "Span / 2"))
        b.symCircle(.face, CBL.mediumFine, r: "Column Diameter / 2")
        b.symRect(.side, CBL.coarse, ("-Height", "-Span / 2"), ("-Height + Arm Thickness", "Span / 2"))
        for (x, y) in [("-Top Span * 0.4", CX.zero), ("Top Span * 0.4", CX.zero), (CX.zero, "-Top Span * 0.4"), (CX.zero, "Top Span * 0.4")] {
            b.drill("Base screw", x: x, y: y, diameter: CX.mm(4), depth: CX.mm(16))
        }
        b.type("Cross Base - 22\"", [:], cost: 70.00, model: "XB-22", isDefault: true)
        b.type("Cross Base - 28\"", ["Span": ComponentKit.inch(28), "Arm Width": ComponentKit.inch(3), "Top Span": ComponentKit.inch(18)], cost: 90.00, model: "XB-28")
        b.type("Cross Base - 22\" Bar Height", ["Height": ComponentKit.inch(40.5), "Column Diameter": ComponentKit.inch(3.5)], cost: 95.00, model: "XB-22B")
        return b.build()
    }

    static func tBase() -> ComponentDefinition {
        var b = legBuilder("T-Base", "Table Bases", "T-shaped base: a foot bar on the floor, a rectangular column and a top arm, for bench tables and booths.", .matteBlack,
                           height: ComponentKit.inch(28.25), inset: ComponentKit.inch(6))
        b.tags("t-base", "t base", "table base", "foot bar", "booth", "bench table")
        b.aliases("t-shaped base", "t-leg", "end base", "booth table base", "trestle foot")
        b.host([.top], faces: [.bottom], align: .left, alignments: [.left, .right, .center], offsetX: ComponentKit.inch(6))
        b.length("Foot Length", ComponentKit.inch(22))
        b.length("Foot Width", ComponentKit.inch(3))
        b.length("Column Width", ComponentKit.inch(3))
        b.length("Column Depth", ComponentKit.inch(1.5))
        b.length("Top Arm Length", ComponentKit.inch(18))
        b.box("Foot", x: ("-Foot Width / 2", "Foot Width / 2"), y: ("-Foot Length / 2", "Foot Length / 2"), z: ("-Height", "-Height + 0.025 m"))
        b.box("Column", x: ("-Column Depth / 2", "Column Depth / 2"), y: ("-Column Width / 2", "Column Width / 2"), z: ("-Height + 0.025 m", "-0.025 m"))
        b.box("Top Arm", x: ("-Foot Width / 2", "Foot Width / 2"), y: ("-Top Arm Length / 2", "Top Arm Length / 2"), z: ("-0.025 m", CX.zero))
        b.symRect(.face, CBL.all, ("-Foot Width / 2", "-Foot Length / 2"), ("Foot Width / 2", "Foot Length / 2"))
        b.symRect(.face, CBL.mediumFine, ("-Column Depth / 2", "-Column Width / 2"), ("Column Depth / 2", "Column Width / 2"), dashed: true)
        b.symbol(.side, CBL.coarse, .polyline(ComponentKit.points([("-Height", "-Foot Length / 2"), ("-Height", "Foot Length / 2"), ("-Height + 0.025 m", "Foot Length / 2"),
                                                                    ("-Height + 0.025 m", "-Foot Length / 2")]), closed: true))
        for y in ["-Top Arm Length * 0.4", "Top Arm Length * 0.4"] { b.drill("Base screw", x: CX.zero, y: y, diameter: CX.mm(4), depth: CX.mm(16)) }
        b.type("T-Base - 22\"", [:], cost: 60.00, model: "TBS-22", isDefault: true)
        b.type("T-Base - 26\"", ["Foot Length": ComponentKit.inch(26), "Top Arm Length": ComponentKit.inch(22)], cost: 70.00, model: "TBS-26")
        return b.build()
    }

    static func uBase() -> ComponentDefinition {
        var b = legBuilder("U-Base", "Table Bases", "U-shaped leg (inverted U): two flat-bar posts joined by a top bar under the top, for coffee tables and benches.", .matteBlack,
                           height: ComponentKit.inch(16), inset: ComponentKit.inch(2))
        b.tags("u-base", "u leg", "u-shaped", "flat bar", "coffee table", "bench", "steel")
        b.aliases("u-shaped leg", "u frame leg", "square leg frame", "bench leg", "flat bar leg")
        b.host([.top, .bottom], faces: [.bottom], align: .left, alignments: [.left, .right], offsetX: ComponentKit.inch(2))
        b.length("Base Width", ComponentKit.inch(16))
        b.length("Bar Width", ComponentKit.inch(2))
        b.length("Bar Thickness", ComponentKit.inch(0.375))
        let x = ("-Bar Thickness / 2", "Bar Thickness / 2")
        b.box("Top Bar", x: x, y: ("-Base Width / 2", "Base Width / 2"), z: ("-Bar Width", CX.zero))
        b.box("Post A", x: x, y: ("-Base Width / 2", "-Base Width / 2 + Bar Width"), z: ("-Height", "-Bar Width"))
        b.box("Post B", x: x, y: ("Base Width / 2 - Bar Width", "Base Width / 2"), z: ("-Height", "-Bar Width"))
        b.symRect(.face, CBL.all, ("-Bar Thickness / 2", "-Base Width / 2"), ("Bar Thickness / 2", "Base Width / 2"))
        b.symbol(.side, CBL.coarse, .polyline(ComponentKit.points([("-Height", "-Base Width / 2"), (CX.zero, "-Base Width / 2"), (CX.zero, "Base Width / 2"), ("-Height", "Base Width / 2")]),
                                               closed: false))
        for y in ["-Base Width * 0.35", "Base Width * 0.35", CX.zero] { b.drill("Base screw", x: CX.zero, y: y, diameter: CX.mm(4), depth: CX.mm(16)) }
        b.type("U-Base - 12\"", ["Base Width": ComponentKit.inch(12)], cost: 28.00, model: "UB-12")
        b.type("U-Base - 16\"", [:], cost: 34.00, model: "UB-16", isDefault: true)
        b.type("U-Base - 20\" x 28\"", ["Base Width": ComponentKit.inch(20), "Height": ComponentKit.inch(28), "Bar Width": ComponentKit.inch(2.5)], cost: 46.00, model: "UB-2028")
        return b.build()
    }

    static func sledBase() -> ComponentDefinition {
        var b = legBuilder("Sled Base", "Table Bases", "Sled base: a closed tube loop with a floor runner, two posts and a top bar.", .matteBlack, height: ComponentKit.inch(28.25),
                           inset: ComponentKit.inch(2))
        b.tags("sled base", "sled leg", "loop", "tube", "steel", "chair", "table base")
        b.aliases("sled leg", "loop leg", "runner base", "closed frame leg", "skid base")
        b.host([.top, .bottom], faces: [.bottom], align: .left, alignments: [.left, .right], offsetX: ComponentKit.inch(2))
        b.length("Base Depth", ComponentKit.inch(20))
        b.length("Tube Size", ComponentKit.inch(1))
        b.length("Corner Radius", ComponentKit.inch(1))
        let x = ("-Tube Size / 2", "Tube Size / 2")
        b.box("Runner", x: x, y: ("-Base Depth / 2 + Corner Radius", "Base Depth / 2 - Corner Radius"), z: ("-Height", "-Height + Tube Size"))
        b.box("Top Bar", x: x, y: ("-Base Depth / 2 + Corner Radius", "Base Depth / 2 - Corner Radius"), z: ("-Tube Size", CX.zero))
        for (n, y) in [("Post A", ("-Base Depth / 2", "-Base Depth / 2 + Tube Size")), ("Post B", ("Base Depth / 2 - Tube Size", "Base Depth / 2"))] {
            b.box(n, x: x, y: y, z: ("-Height + Corner Radius", "-Corner Radius"))
        }
        // Rounded corners: quarter bends on the side plane.
        for (k, (cy, cz, a0)) in [("-Base Depth / 2 + Corner Radius", "-Height + Corner Radius", 180.0), ("Base Depth / 2 - Corner Radius", "-Height + Corner Radius", 270.0),
                                   ("Base Depth / 2 - Corner Radius", "-Corner Radius", 0.0), ("-Base Depth / 2 + Corner Radius", "-Corner Radius", 90.0)].enumerated() {
            var pts: [(String, String)] = []
            for i in 0...6 { let a = (a0 + 15 * Double(i)) * .pi / 180; pts.append(("\(cy) + Corner Radius * \(LX.num(cos(a)))", "\(cz) + Corner Radius * \(LX.num(sin(a)))")) }
            for i in (0...6).reversed() {
                let a = (a0 + 15 * Double(i)) * .pi / 180
                pts.append(("\(cy) + (Corner Radius - Tube Size) * \(LX.num(cos(a)))", "\(cz) + (Corner Radius - Tube Size) * \(LX.num(sin(a)))"))
            }
            b.extrusion("Bend \(k + 1)", profile: ComponentKit.points(pts), plane: .yz, from: "-Tube Size / 2", to: "Tube Size / 2")
        }
        b.symRect(.face, CBL.all, ("-Tube Size / 2", "-Base Depth / 2"), ("Tube Size / 2", "Base Depth / 2"))
        b.symRect(.side, CBL.coarse, ("-Height", "-Base Depth / 2"), (CX.zero, "Base Depth / 2"))
        for y in ["-Base Depth * 0.3", "Base Depth * 0.3"] { b.drill("Base screw", x: CX.zero, y: y, diameter: CX.mm(4), depth: CX.mm(16)) }
        b.type("Sled Base - 16\" x 17\"", ["Base Depth": ComponentKit.inch(16), "Height": ComponentKit.inch(17)], cost: 32.00, model: "SB-1617")
        b.type("Sled Base - 20\" x 28\"", [:], cost: 40.00, model: "SB-2028", isDefault: true)
        b.type("Sled Base - 24\" x 28\" Wide Tube", ["Base Depth": ComponentKit.inch(24), "Tube Size": ComponentKit.inch(1.5), "Corner Radius": ComponentKit.inch(1.5)], cost: 52.00, model: "SB-2428")
        return b.build()
    }

    static func cantileverBase() -> ComponentDefinition {
        var b = legBuilder("Cantilever Base", "Table Bases", "Cantilever (C) base: a floor runner, a post at the back and an arm reaching forward under the top.", .chrome,
                           height: ComponentKit.inch(28.25), inset: ComponentKit.inch(2))
        b.tags("cantilever base", "c base", "c-frame", "tube", "chrome", "side table", "chair")
        b.aliases("c-shaped base", "cantilever frame", "c leg", "overbed table base", "sofa table base")
        b.host([.top], faces: [.bottom], align: .left, alignments: [.left, .right], offsetX: ComponentKit.inch(2))
        b.length("Arm Reach", ComponentKit.inch(16))
        b.length("Runner Length", ComponentKit.inch(18))
        b.length("Tube Diameter", ComponentKit.inch(1))
        let r = "Tube Diameter / 2"
        b.rod("Runner", axis: .y, c: (CX.zero, "-Height + Tube Diameter / 2"), r: r, from: "-Runner Length + Tube Diameter", to: "Tube Diameter / 2")
        b.rod("Post", c: (CX.zero, CX.zero), r: r, from: "-Height + Tube Diameter / 2", to: "-Tube Diameter / 2")
        b.rod("Arm", axis: .y, c: (CX.zero, "-Tube Diameter / 2"), r: r, from: "-Arm Reach", to: "Tube Diameter / 2")
        b.symLine(.face, CBL.all, (CX.zero, "-Runner Length + Tube Diameter"), (CX.zero, "Tube Diameter / 2"))
        b.symCircle(.face, CBL.all, r: r)
        b.symbol(.side, CBL.coarse, .polyline(ComponentKit.points([("-Height", "-Runner Length + Tube Diameter"), ("-Height", CX.zero), (CX.zero, CX.zero), (CX.zero, "-Arm Reach")]), closed: false))
        for y in ["-Arm Reach * 0.8", "-Arm Reach * 0.3"] { b.drill("Arm screw", x: CX.zero, y: y, diameter: CX.mm(4), depth: CX.mm(16)) }
        b.type("Cantilever Base - 16\"", [:], cost: 45.00, model: "CTB-16", isDefault: true)
        b.type("Cantilever Base - 20\" Overbed", ["Arm Reach": ComponentKit.inch(20), "Runner Length": ComponentKit.inch(22), "Height": ComponentKit.inch(30), "Tube Diameter": ComponentKit.inch(1.25)],
               cost: 58.00, model: "CTB-20")
        return b.build()
    }

    static func plinthBase() -> ComponentDefinition {
        var b = legBuilder("Plinth Base", "Plinths", "Plinth (base frame) under a carcass: front, back and sides set back from the front and ends, as a separate box.", .oak,
                           height: ComponentKit.inch(4), heightInstance: false, legType: false, inset: 0)
        b.tags("plinth", "base frame", "kick", "toe kick", "box base", "cabinet base")
        b.aliases("plinth frame", "kick base", "cabinet plinth", "base box", "sub base")
        b.host([.bottom], faces: [.bottom], align: .full)
        b.length("Width", ComponentKit.inch(36), instance: true, group: .dimensions)
        b.length("Depth", ComponentKit.inch(22), instance: true, group: .dimensions)
        b.length("Board Thickness", ComponentKit.inch(0.75))
        b.length("Front Setback", ComponentKit.inch(3))
        b.length("Side Setback", ComponentKit.inch(0.5))
        let x0 = "-Width / 2 + Side Setback", x1 = "Width / 2 - Side Setback", y0 = "-Depth / 2 + Front Setback", y1 = "Depth / 2"
        let z = ("-Height", CX.zero)
        b.box("Front", x: (x0, x1), y: (y0, "\(y0) + Board Thickness"), z: z)
        b.box("Back", x: (x0, x1), y: ("\(y1) - Board Thickness", y1), z: z)
        b.box("Left", x: (x0, "\(x0) + Board Thickness"), y: ("\(y0) + Board Thickness", "\(y1) - Board Thickness"), z: z)
        b.box("Right", x: ("\(x1) - Board Thickness", x1), y: ("\(y0) + Board Thickness", "\(y1) - Board Thickness"), z: z)
        b.symRect(.face, CBL.all, (x0, y0), (x1, y1))
        b.symRect(.face, CBL.mediumFine, ("\(x0) + Board Thickness", "\(y0) + Board Thickness"), ("\(x1) - Board Thickness", "\(y1) - Board Thickness"), dashed: true)
        b.symRect(.side, CBL.coarse, ("-Height", y0), (CX.zero, y1))
        for (x, y) in [(x0, y0), (x1, y0), (x0, y1), (x1, y1)] {
            b.drill("Plinth screw", x: "\(x) * 0.95", y: "\(y) * 0.95", diameter: CX.mm(4), depth: CX.mm(16))
        }
        b.type("Plinth - 3\"", ["Height": ComponentKit.inch(3), "Front Setback": ComponentKit.inch(2)], cost: 14.00, model: "PLB-3")
        b.type("Plinth - 4\"", [:], cost: 16.00, model: "PLB-4", isDefault: true)
        b.type("Plinth - 6\"", ["Height": ComponentKit.inch(6)], cost: 20.00, model: "PLB-6")
        return b.build()
    }

    static func toeKick() -> ComponentDefinition {
        var b = legBuilder("Toe Kick", "Plinths", "Toe kick board: a recessed board under the carcass's front, on cabinet legs or blocks.", .blackPlastic,
                           height: ComponentKit.inch(4.5), heightInstance: false, legType: false, inset: 0)
        b.tags("toe kick", "kick board", "plinth", "kitchen", "recess", "cabinet")
        b.aliases("kickboard", "plinth board", "toe board", "kick plate", "cabinet kick")
        b.host([.bottom], faces: [.bottom], align: .full)
        b.material("Board Material", .oak)
        b.length("Length", ComponentKit.inch(36), instance: true, group: .dimensions)
        b.length("Recess", ComponentKit.inch(3))
        b.length("Board Thickness", ComponentKit.inch(0.75))
        b.flag("Vent Grille", false, instance: true)
        b.slot("Board Material") { b in
            b.box("Kick Board", x: ("-Length / 2", "Length / 2"), y: ("Recess", "Recess + Board Thickness"), z: ("-Height", CX.zero))
        }
        b.at(CBL.fine) { b in
            b.box("Seal", x: ("-Length / 2", "Length / 2"), y: ("Recess - 0.001 m", "Recess + Board Thickness"), z: ("-Height", "-Height + 0.004 m"))
        }
        b.shown(by: "Vent Grille") { b in
            b.box("Vent Grille", x: ("-Length * 0.2", "Length * 0.2"), y: ("Recess - 0.002 m", "Recess"), z: ("-Height * 0.75", "-Height * 0.25"))
        }
        b.symRect(.face, CBL.all, ("-Length / 2", "Recess"), ("Length / 2", "Recess + Board Thickness"))
        b.symRect(.side, CBL.coarse, ("-Height", "Recess"), (CX.zero, "Recess + Board Thickness"))
        b.type("Toe Kick - 4\"", ["Height": ComponentKit.inch(4)], flags: ["Vent Grille": false], cost: 9.00, model: "TK-4")
        b.type("Toe Kick - 4 1/2\"", [:], flags: ["Vent Grille": false], cost: 10.00, model: "TK-45", isDefault: true)
        b.type("Toe Kick - 6\"", ["Height": ComponentKit.inch(6), "Recess": ComponentKit.inch(2.5)], flags: ["Vent Grille": false], cost: 12.00, model: "TK-6")
        return b.build()
    }

    static func decorativeFoot() -> ComponentDefinition {
        var b = legBuilder("Decorative Foot", "Decorative Feet", "Decorative foot for chests, dressers and cabinets: bun, ball and claw-less bracket styles.", .walnut,
                           height: ComponentKit.inch(3), heightInstance: false, inset: ComponentKit.inch(1))
        b.tags("decorative foot", "bun foot", "ball foot", "bracket foot", "dresser", "chest", "traditional")
        b.aliases("bun feet", "ball feet", "bracket feet", "onion foot", "turned foot", "cabinet foot decorative")
        b.length("Size", ComponentKit.inch(3.5))
        b.choice("Style", ["Bun", "Ball", "Bracket"], "Bun", group: .dimensions)
        b.flag("Bun", true, instance: false)
        b.flag("Ball", false, instance: false)
        b.flag("Bracket", false, formula: "and(not(Bun), not(Ball))")
        b.shown(by: "Bun") { b in
            let pts = (0...14).map { k -> (String, String) in
                let t = Double(k) / 14, a = -Double.pi / 2 + .pi * t
                return ("Size / 2 * \(LX.num(0.45 + 0.55 * cos(a)))", "Height * 0.85 * \(LX.num(0.5 + 0.5 * sin(a)))")
            }
            b.turn("Bun", base: "-Height", [(CX.zero, CX.zero)] + pts + [("Size * 0.32", "Height * 0.85"), ("Size * 0.32", "Height"), (CX.zero, "Height")])
        }
        b.shown(by: "Ball") { b in
            let pts = (0...14).map { k -> (String, String) in
                let t = Double(k) / 16, a = -Double.pi / 2 + .pi * t
                return ("Size / 2 * \(LX.num(cos(a)))", "Height * 0.8 * \(LX.num(0.5 + 0.5 * sin(a)))")
            }
            b.turn("Ball", base: "-Height", [(CX.zero, CX.zero)] + pts.dropFirst() + [("Size * 0.25", "Height * 0.8"), ("Size * 0.25", "Height"), (CX.zero, "Height")])
        }
        b.shown(by: "Bracket") { b in
            // Two boards meeting at the corner (outside faces at −X and −Y), with an ogee-cut inner edge.
            let prof: [(String, String)] = [(CX.zero, "-Height"), (CX.zero, CX.zero), ("Size", CX.zero), ("Size", "-Height * 0.35"), ("Size * 0.7", "-Height * 0.45"),
                                            ("Size * 0.45", "-Height * 0.7"), ("Size * 0.3", "-Height")]
            b.extrusion("Bracket Front", profile: ComponentKit.points(prof.map { ("\($0.0) - Size / 2", $0.1) }), plane: .xz, from: "-Size / 2", to: "-Size / 2 + 0.019 m")
            b.extrusion("Bracket Side", profile: ComponentKit.points(prof.map { ("\($0.0) - Size / 2", $0.1) }), plane: .yz, from: "-Size / 2", to: "-Size / 2 + 0.019 m")
        }
        b.symCircle(.face, CBL.all, r: "Size / 2")
        b.symRect(.side, CBL.coarse, ("-Height", "-Size / 2"), (CX.zero, "Size / 2"))
        hangerBolt(&b)
        b.type("Bun Foot - 3\"", [:], flags: ["Bun": true, "Ball": false], texts: ["Style": "Bun"], cost: 7.00, model: "DF-B3", isDefault: true)
        b.type("Ball Foot - 2 1/2\"", ["Height": ComponentKit.inch(2.5), "Size": ComponentKit.inch(2.75)], flags: ["Bun": false, "Ball": true], texts: ["Style": "Ball"], cost: 6.50, model: "DF-BL25")
        b.type("Bracket Foot - 4\"", ["Height": ComponentKit.inch(4), "Size": ComponentKit.inch(4.5)], flags: ["Bun": false, "Ball": false], texts: ["Style": "Bracket"], cost: 11.00, model: "DF-BR4")
        return b.build()
    }

    // MARK: Moving legs

    static func foldingLeg() -> ComponentDefinition {
        var b = legBuilder("Folding Leg", "Folding Legs", "Folding table leg: a tube leg on a pivot bracket with a locking brace; Folded shows it flat under the top.", .matteBlack,
                           height: ComponentKit.inch(28), inset: ComponentKit.inch(2))
        b.tags("folding leg", "fold", "foldable", "table", "brace", "lock", "tube")
        b.aliases("folding table leg", "fold-down leg", "collapsible leg", "foldaway leg", "banquet leg")
        b.length("Tube Diameter", ComponentKit.inch(1))
        b.length("Bracket Length", ComponentKit.inch(5))
        b.length("Bracket Width", ComponentKit.inch(2))
        b.length("Brace Length", ComponentKit.inch(10))
        b.flag("Folded", false, instance: true)
        b.flag("Open", true, formula: "not(Folded)")
        b.box("Pivot Bracket", x: ("-Bracket Width / 2", "Bracket Width / 2"), y: ("-Bracket Length / 2", "Bracket Length / 2"), z: (CX.mm(-25), CX.zero))
        let r = "Tube Diameter / 2"
        b.shown(by: "Open") { b in
            b.rod("Leg", c: (CX.zero, CX.zero), r: r, from: "-Height + 0.01 m", to: CX.mm(-25))
            b.rod("Foot Cap", r: "Tube Diameter / 2 + 0.001 m", from: "-Height", to: "-Height + 0.01 m")
            b.strut("Brace", bottom: (CX.zero, CX.zero), top: (CX.zero, "Brace Length * 0.7"), r0: "Tube Diameter * 0.25", r1: "Tube Diameter * 0.25", z: ("-Brace Length * 0.7", CX.mm(-6)), sides: 12)
        }
        b.shown(by: "Folded") { b in
            b.rod("Leg", axis: .y, c: (CX.zero, "-Tube Diameter / 2 - 0.025 m"), r: r, from: CX.zero, to: "Height - 0.025 m")
        }
        b.symRect(.face, CBL.all, ("-Bracket Width / 2", "-Bracket Length / 2"), ("Bracket Width / 2", "Bracket Length / 2"))
        b.symCircle(.face, CBL.mediumFine, r: r)
        b.symLine(.face, CBL.mediumFine, (CX.zero, CX.zero), (CX.zero, "Height"), dashed: true)
        b.symRect(.side, CBL.coarse, ("-Height", "-Tube Diameter / 2"), (CX.zero, "Tube Diameter / 2"))
        plateScrews(&b, size: "Bracket Width")
        b.type("Folding Leg - 28\"", [:], cost: 16.00, model: "FL-28", isDefault: true)
        b.type("Folding Leg - 16\" Coffee", ["Height": ComponentKit.inch(16), "Brace Length": ComponentKit.inch(7)], cost: 13.00, model: "FL-16")
        return b.build()
    }

    static func telescopicLeg() -> ComponentDefinition {
        var b = legBuilder("Telescopic Leg", "Adjustable Legs", "Telescopic leg: an inner tube slides in the outer tube; Height sets how far it's drawn out, between the type's limits.", .aluminum,
                           height: ComponentKit.inch(28), inset: ComponentKit.inch(2))
        b.tags("telescopic leg", "telescoping", "adjustable height", "extendable", "tube", "sliding")
        b.aliases("telescoping leg", "extendable leg", "adjustable height leg", "sliding leg", "extension leg")
        b.material("Foot Material", .rubber)
        b.length("Outer Diameter", ComponentKit.inch(1.5))
        b.length("Inner Diameter", ComponentKit.inch(1.25))
        b.length("Outer Length", ComponentKit.inch(18))
        b.length("Minimum Height", ComponentKit.inch(20))
        b.length("Maximum Height", ComponentKit.inch(34))
        b.length("Plate Size", ComponentKit.inch(3))
        b.requires(.note("Height between the type's Minimum and Maximum Height."))
        mountingPlate(&b, size: "Plate Size")
        b.pipe("Outer Tube", outer: "Outer Diameter / 2", inner: "Outer Diameter / 2 - 0.0015 m", from: "-Outer Length", to: CX.mm(-3))
        b.rod("Collar", r: "Outer Diameter / 2 + 0.002 m", from: "-Outer Length", to: "-Outer Length + 0.015 m")
        b.rod("Inner Tube", r: "Inner Diameter / 2", from: "-Height + 0.012 m", to: "-Outer Length")
        b.slot("Foot Material") { b in b.rod("Foot", r: "Inner Diameter / 2 + 0.002 m", from: "-Height", to: "-Height + 0.012 m") }
        roundLegSymbols(&b, d: "Outer Diameter")
        plateScrews(&b, size: "Plate Size")
        b.type("Telescopic Leg - 20-34\"", [:], cost: 22.00, model: "TEL-2034", isDefault: true)
        b.type("Telescopic Leg - 14-22\"", ["Height": ComponentKit.inch(18), "Outer Length": ComponentKit.inch(12), "Minimum Height": ComponentKit.inch(14), "Maximum Height": ComponentKit.inch(22)],
               cost: 18.00, model: "TEL-1422")
        return b.build()
    }

    static func lockableLeg() -> ComponentDefinition {
        var b = legBuilder("Lockable Leg", "Adjustable Legs", "Adjustable leg with a lock: a twist or lever collar clamps the inner tube at any height; Pin locks at fixed steps.", .aluminum,
                           height: ComponentKit.inch(28), inset: ComponentKit.inch(2))
        b.tags("lockable leg", "locking leg", "lock", "adjustable", "twist lock", "lever lock", "pin lock")
        b.aliases("locking leg", "leg with lock", "clamp leg", "twist-lock leg", "lever leg", "pin-lock leg")
        b.material("Lock Material", .blackPlastic)
        b.choice("Lock Type", ["Twist", "Lever", "Pin"], "Twist", group: .data)
        b.length("Outer Diameter", ComponentKit.inch(1.5))
        b.length("Inner Diameter", ComponentKit.inch(1.25))
        b.length("Outer Length", ComponentKit.inch(18))
        b.length("Lock Step", ComponentKit.inch(1), group: .dimensions)
        b.length("Plate Size", ComponentKit.inch(3))
        b.flag("Lever", false, instance: false)
        b.flag("Twist Collar", true, formula: "not(Lever)")
        mountingPlate(&b, size: "Plate Size")
        b.rod("Outer Tube", r: "Outer Diameter / 2", from: "-Outer Length", to: CX.mm(-3))
        b.rod("Inner Tube", r: "Inner Diameter / 2", from: "-Height + 0.012 m", to: "-Outer Length")
        b.slot("Lock Material") { b in
            b.shown(by: "Twist Collar") { b in
                b.turn("Twist Collar", base: "-Outer Length - 0.01 m", [(CX.zero, CX.zero), ("Outer Diameter / 2 + 0.003 m", CX.zero), ("Outer Diameter / 2 + 0.005 m", "0.012 m"),
                                                                      ("Outer Diameter / 2 + 0.005 m", "0.028 m"), (CX.zero, "0.028 m")])
            }
            b.shown(by: "Lever") { b in
                b.rod("Lever Collar", r: "Outer Diameter / 2 + 0.003 m", from: "-Outer Length", to: "-Outer Length + 0.02 m")
                b.box("Lever", x: ("Outer Diameter / 2", "Outer Diameter / 2 + 0.045 m"), y: (CX.mm(-6), CX.mm(6)), z: ("-Outer Length + 0.004 m", "-Outer Length + 0.012 m"))
            }
            b.rod("Foot", r: "Inner Diameter / 2 + 0.002 m", from: "-Height", to: "-Height + 0.012 m")
        }
        roundLegSymbols(&b, d: "Outer Diameter")
        plateScrews(&b, size: "Plate Size")
        b.type("Lockable Leg - Twist Lock", [:], flags: ["Lever": false], texts: ["Lock Type": "Twist"], cost: 26.00, model: "LKL-TW", isDefault: true)
        b.type("Lockable Leg - Lever Lock", [:], flags: ["Lever": true], texts: ["Lock Type": "Lever"], cost: 29.00, model: "LKL-LV")
        b.type("Lockable Leg - Pin Lock", ["Lock Step": ComponentKit.inch(1)], flags: ["Lever": false], texts: ["Lock Type": "Pin"], cost: 21.00, model: "LKL-PN")
        return b.build()
    }

    static func heightAdjustableDeskFrame() -> ComponentDefinition {
        var b = legBuilder("Height-Adjustable Desk Frame", "Desk Frames", "Sit-stand desk frame: two lifting columns on feet, joined by a crossbar and top rails; Height sets the working height.",
                           .matteBlack, height: ComponentKit.inch(29), legType: false, inset: 0)
        b.tags("height adjustable desk", "standing desk", "sit stand", "desk frame", "lifting column", "electric", "crank")
        b.aliases("sit-stand frame", "standing desk frame", "adjustable desk base", "lift desk frame", "ergonomic desk frame", "electric desk frame")
        b.host([.top], faces: [.bottom], align: .center)
        b.text("Drive", "Electric, dual motor")
        b.length("Frame Width", ComponentKit.inch(47), instance: true, group: .dimensions, min: ComponentKit.inch(39), max: ComponentKit.inch(71))
        b.length("Foot Length", ComponentKit.inch(27))
        b.length("Column Width", ComponentKit.mm(70))
        b.length("Column Depth", ComponentKit.mm(50))
        b.length("Minimum Height", ComponentKit.inch(25))
        b.length("Maximum Height", ComponentKit.inch(50))
        b.number("Load Capacity", 260, unit: "lb", group: .data)
        b.requires(.note("Height between the type's Minimum and Maximum Height."))
        b.material("Foot Material", .matteBlack)
        let xs = ["-Frame Width / 2 + Column Width", "Frame Width / 2 - Column Width"]
        for (k, x) in xs.enumerated() {
            b.box("Foot \(k + 1)", x: ("\(x) - 0.03 m", "\(x) + 0.03 m"), y: ("-Foot Length / 2", "Foot Length / 2"), z: ("-Height", "-Height + 0.04 m"))
            b.box("Lower Column \(k + 1)", x: ("\(x) - Column Width / 2", "\(x) + Column Width / 2"), y: ("-Column Depth / 2", "Column Depth / 2"), z: ("-Height + 0.04 m", "-Height * 0.45"))
            b.box("Upper Column \(k + 1)", x: ("\(x) - Column Width / 2 + 0.004 m", "\(x) + Column Width / 2 - 0.004 m"), y: ("-Column Depth / 2 + 0.004 m", "Column Depth / 2 - 0.004 m"),
                  z: ("-Height * 0.45", "-0.03 m"))
            b.box("Side Rail \(k + 1)", x: ("\(x) - 0.02 m", "\(x) + 0.02 m"), y: ("-Foot Length / 2 + 0.03 m", "Foot Length / 2 - 0.03 m"), z: ("-0.03 m", CX.zero))
        }
        b.box("Crossbar", x: ("-Frame Width / 2 + Column Width", "Frame Width / 2 - Column Width"), y: (CX.mm(-25), CX.mm(25)), z: (CX.mm(-60), CX.mm(-20)))
        b.at(CBL.fine) { b in b.box("Control Box", x: (CX.mm(-90), CX.mm(90)), y: (CX.mm(30), CX.mm(110)), z: (CX.mm(-50), CX.mm(-20))) }
        b.symRect(.face, CBL.all, ("-Frame Width / 2", "-Foot Length / 2"), ("Frame Width / 2", "Foot Length / 2"))
        b.symRect(.side, CBL.coarse, ("-Height", "-Foot Length / 2"), (CX.zero, "Foot Length / 2"))
        for x in xs { for y in ["-Foot Length * 0.4", "Foot Length * 0.4"] { b.drill("Frame screw", x: x, y: y, diameter: CX.mm(4), depth: CX.mm(16)) } }
        b.type("Desk Frame - Dual Motor 25-50\"", [:], texts: ["Drive": "Electric, dual motor"], cost: 320.00, model: "HAD-2M", isDefault: true)
        b.type("Desk Frame - Single Motor 28-47\"", ["Minimum Height": ComponentKit.inch(28), "Maximum Height": ComponentKit.inch(47), "Foot Length": ComponentKit.inch(24)],
               texts: ["Drive": "Electric, single motor"], numbers: ["Load Capacity": 155], cost: 210.00, model: "HAD-1M")
        b.type("Desk Frame - Crank 28-45\"", ["Minimum Height": ComponentKit.inch(28), "Maximum Height": ComponentKit.inch(45), "Foot Length": ComponentKit.inch(24)],
               texts: ["Drive": "Manual crank"], numbers: ["Load Capacity": 175], cost: 160.00, model: "HAD-CR")
        return b.build()
    }
}
