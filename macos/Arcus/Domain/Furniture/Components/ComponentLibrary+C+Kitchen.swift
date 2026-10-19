import Foundation
import ArcusGeometry

// COMPC: 10 Kitchen Cabinet Accessories. Pull-outs, corner systems, inserts and lifts sit inside a bay
// (`.legacyOpening` frame: origin at the opening's bottom-left-front corner, X across, Y into the depth, Z up) and take
// the bay's size from their Opening Width / Depth / Height instance parameters; their frames and baskets follow it.
// Door organizers mount on a door's inside face, glass holders, mug hooks and paper towel holders under a shelf or the
// top. Widths in type names are the nominal cabinet widths the trade sells them by (150–600 mm).

extension ComponentsC {
    static var kitchen: [ComponentDefinition] {
        [pantry(tall: false), pantry(tall: true), cornerCarousel(), lazySusan(), magicCorner(), blindCornerSwingOut(), spiceRack(), bottlePullOut(),
         plateOrganizer(), dishRack(), cutleryOrganizer(), utensilTray(), potPanOrganizer(), underSinkOrganizer(), trashPullOut(), recyclingSystem(),
         sinkTipOutTray(), sinkCutout(), applianceLift(), mixerLift(), pullOutWorktop(), foldDownWorktop(), doorOrganizer(), wineRack(), glassHolder(),
         mugHook(), towelRail(), paperTowelHolder(), cornerBasket()]
    }

    /// Opening width of a frameless cabinet of nominal width `w` mm (two 18 mm sides).
    static func openingFor(_ w: Double) -> Double { CC.mm(w - 36) }

    // MARK: Pull-outs

    /// Pull-out pantry (base, 2–3 baskets) or tall pantry (4–6 baskets): a front post (the door mounts to it) and a rear
    /// post on full-extension floor runners, baskets hung between them at equal spacing.
    static func pantry(tall: Bool) -> ComponentDefinition {
        let name = tall ? "Tall Pantry Pull-Out" : "Pull-Out Pantry"
        var b = ComponentBuilder(name, .kitchen, "Pull-Outs",
                                 tall ? "Tall larder pull-out: door-mounted frame with up to six baskets on heavy-duty floor runners."
                                      : "Base cabinet pull-out pantry: door-mounted frame with two or three baskets on full-extension runners.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "pantry", "pull-out", "larder", "basket", tall ? "tall" : "base")
        b.aliases(tall ? "larder unit" : "pull out pantry", tall ? "tall larder pull-out" : "base pull-out", "pantry pull-out", "pullout basket frame",
                  "150 mm", "200 mm", "300 mm", "450 mm", "6 in", "8 in", "12 in", "18 in")
        b.role(.module)
        b.material("Frame Material", .matteBlack)
        b.material("Basket Material", .chrome)
        b.openingParameters(width: openingFor(300), depth: CC.mm(540), height: CC.mm(tall ? 1880 : 700), minWidth: CC.mm(110), maxWidth: CC.mm(570))
        b.length("Side Clearance", CC.mm(13), group: .manufacturing)
        b.length("Top Clearance", CC.mm(tall ? 25 : 20), group: .manufacturing)
        b.length("Slide Length", CC.mm(500), group: .manufacturing)
        b.length("Basket Height", CC.mm(tall ? 110 : 120))
        b.length("Basket Depth", CC.mm(tall ? 470 : 460))
        b.length("Wire Diameter", CC.mm(5))
        b.number("Basket Count", tall ? 5 : 2, group: .dimensions)
        b.number("Load Capacity", tall ? 100 : 60, unit: "lb", group: .data)
        b.flag("Soft Close", true, instance: false, group: .data)
        b.length("Frame Width", 0, formula: "Opening Width - 2 * Side Clearance")
        b.length("Frame Height", 0, formula: "Opening Height - Top Clearance")
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.fitsDepth("Slide Length + 0.01 m"))
        b.requires(.hostWidth(min: "0.11 m", max: "0.57 m"))
        b.requires(.note("Door mounts to the front post with 4 screws; use a door the full bay height."))
        b.clearance(.box(name: "Pull-out travel", x0: "Side Clearance", x1: "Opening Width - Side Clearance", y0: "-Slide Length", y1: "0 m", z0: "0 m", z1: "Frame Height"))
        b.clearance(.rear("0.01 m"))
        let x0 = "Side Clearance", x1 = "Opening Width - Side Clearance", mid = "Opening Width / 2"
        // Runners and frame.
        b.using("Frame Material")
        b.floorRunners("Runner", x: ("Side Clearance + 0.012 m", "Opening Width - Side Clearance - 0.012 m"), y: ("0.002 m", "Slide Length"), width: CX.mm(22), height: CX.mm(18))
        b.box("Bottom Rail", x: (x0, x1), y: ("0.01 m", "Slide Length"), z: ("0.018 m", "0.038 m"))
        b.box("Front Post", x: ("\(mid) - 0.012 m", "\(mid) + 0.012 m"), y: ("0 m", "0.025 m"), z: ("0.038 m", "Frame Height"))
        b.box("Rear Post", x: ("\(mid) - 0.012 m", "\(mid) + 0.012 m"), y: ("Slide Length - 0.025 m", "Slide Length"), z: ("0.038 m", "Frame Height"))
        b.box("Top Rail", x: ("\(mid) - 0.01 m", "\(mid) + 0.01 m"), y: ("0.025 m", "Slide Length - 0.025 m"), z: ("Frame Height - 0.02 m", "Frame Height"))
        b.box("Door Bracket", x: ("\(mid) - 0.03 m", "\(mid) + 0.03 m"), y: ("-0.003 m", "0 m"), z: ("Frame Height * 0.2", "Frame Height * 0.8"))
        // Baskets at equal pitch.
        b.using("Basket Material")
        let maxBaskets = tall ? 6 : 3
        let by0 = "(Slide Length - Basket Depth) / 2", by1 = "(Slide Length + Basket Depth) / 2"
        for k in 1...maxBaskets {
            let z0 = "0.05 m + (Frame Height - 0.07 m - Basket Height) * \(k - 1) / max(1, Basket Count - 1)"
            let v: String? = k <= 1 ? nil : "Show Basket \(k)"
            if let v { b.countFlag(v, "Basket Count >= \(k)") }
            b.shown(v) { $0.basket("Basket \(k)", x: ("\(x0) + 0.004 m", "\(x1) - 0.004 m"), y: (by0, by1), z: (z0, "\(z0) + Basket Height"), wire: "Wire Diameter") }
        }
        b.using(nil)
        for (k, y) in ["0.037 m", "0.165 m", "0.293 m"].enumerated() {
            b.drill("Runner screw", x: "Side Clearance + 0.012 m", y: y, diameter: CX.mm(4), depth: CX.mm(12))
            b.drill("Runner screw", x: "Opening Width - Side Clearance - 0.012 m", y: y, diameter: CX.mm(4), depth: CX.mm(12))
            _ = k
        }
        b.outlines(x: (x0, x1), y: ("0 m", "Slide Length"), z: ("0 m", "Frame Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect((x0, "-Slide Length"), (x1, "0 m")))
        if tall {
            for (w, n, c, cost) in [(300.0, 5.0, true, 389.0), (400, 5, false, 429), (450, 6, false, 469), (600, 6, false, 619)] {
                b.type("\(name) - \(Int(w)) mm", ["Opening Width": openingFor(w), "Opening Height": CC.mm(1880)], numbers: ["Basket Count": n],
                       cost: cost, model: "TPP-\(Int(w))", description: "Tall pantry pull-out for a \(Int(w)) mm cabinet, \(Int(n)) baskets", isDefault: c)
            }
        } else {
            for (w, n, cost) in [(150.0, 2.0, 119.0), (200, 2, 129), (300, 2, 149), (450, 3, 189)] {
                b.type("\(name) - \(Int(w)) mm", ["Opening Width": openingFor(w)], numbers: ["Basket Count": n],
                       cost: cost, model: "PP-\(Int(w))", description: "Base pull-out pantry for a \(Int(w)) mm cabinet, \(Int(n)) baskets")
            }
        }
        return b.build()
    }

    /// A narrow pull-out spice rack: a tall frame with three or four shallow shelves and gallery rails.
    static func spiceRack() -> ComponentDefinition {
        var b = ComponentBuilder("Pull-Out Spice Rack", .kitchen, "Pull-Outs", "Narrow pull-out with shallow spice shelves and gallery rails, for filler and 100–200 mm cabinets.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "spice", "pull-out", "rack", "narrow", "filler")
        b.aliases("spice pull-out", "spice pullout", "filler pull-out", "100 mm", "150 mm", "200 mm", "4 in", "6 in", "8 in")
        b.material("Finish Material", .chrome)
        b.material("Shelf Material", .whitePlastic)
        b.openingParameters(width: openingFor(150), depth: CC.mm(540), height: CC.mm(700), minWidth: CC.mm(60), maxWidth: CC.mm(200))
        b.length("Side Clearance", CC.mm(8), group: .manufacturing)
        b.length("Slide Length", CC.mm(500), group: .manufacturing)
        b.number("Shelf Count", 4, group: .dimensions)
        b.length("Rail Height", CC.mm(50))
        b.length("Frame Width", 0, formula: "Opening Width - 2 * Side Clearance")
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.fitsDepth("Slide Length + 0.01 m"))
        b.requires(.hostWidth(min: "0.06 m", max: "0.2 m"))
        b.clearance(.box(name: "Pull-out travel", x0: "Side Clearance", x1: "Opening Width - Side Clearance", y0: "-Slide Length", y1: "0 m", z0: "0 m", z1: "Opening Height"))
        let x0 = "Side Clearance", x1 = "Opening Width - Side Clearance"
        b.floorRunners("Runner", x: ("Opening Width / 2 - 0.012 m", "Opening Width / 2 + 0.012 m"), y: ("0 m", "Slide Length"), width: CX.mm(16), height: CX.mm(16))
        b.box("Front Post", x: (x0, x1), y: ("0 m", "0.02 m"), z: ("0.016 m", "Opening Height - 0.02 m"))
        b.box("Rear Post", x: ("Opening Width / 2 - 0.01 m", "Opening Width / 2 + 0.01 m"), y: ("Slide Length - 0.02 m", "Slide Length"), z: ("0.016 m", "Opening Height - 0.02 m"))
        for k in 1...5 {
            let z = "0.04 m + (Opening Height - 0.12 m) * \(k - 1) / max(1, Shelf Count - 1)"
            let v: String? = k <= 2 ? nil : "Show Shelf \(k)"
            if let v { b.countFlag(v, "Shelf Count >= \(k)") }
            b.shown(v) { b in
                b.using("Shelf Material")
                b.box("Shelf \(k)", x: (x0, x1), y: ("0.02 m", "Slide Length - 0.02 m"), z: (z, "\(z) + 0.004 m"))
                b.using("Finish Material")
                b.rodY("Rail \(k) Left", x: "\(x0) + 0.003 m", z: "\(z) + Rail Height", d: CX.mm(5), from: "0.02 m", to: "Slide Length - 0.02 m")
                b.rodY("Rail \(k) Right", x: "\(x1) - 0.003 m", z: "\(z) + Rail Height", d: CX.mm(5), from: "0.02 m", to: "Slide Length - 0.02 m")
            }
        }
        b.using(nil)
        b.drill("Runner screw", x: "Opening Width / 2", y: "0.037 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.drill("Runner screw", x: "Opening Width / 2", y: "0.293 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.outlines(x: (x0, x1), y: ("0 m", "Slide Length"), z: ("0 m", "Opening Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect((x0, "-Slide Length"), (x1, "0 m")))
        for (w, n, cost) in [(100.0, 4.0, 69.0), (150, 4, 79), (200, 3, 89)] {
            b.type("Pull-Out Spice Rack - \(Int(w)) mm", ["Opening Width": openingFor(w)], numbers: ["Shelf Count": n], cost: cost, model: "SPR-\(Int(w))",
                   description: "Spice pull-out for a \(Int(w)) mm cabinet, \(Int(n)) shelves")
        }
        return b.build()
    }

    /// A bottle pull-out: two wire baskets with bottle dividers on a door-mounted frame.
    static func bottlePullOut() -> ComponentDefinition {
        var b = ComponentBuilder("Bottle Pull-Out", .kitchen, "Pull-Outs", "Base pull-out with two deep bottle baskets and a divider rail, for 150–300 mm cabinets.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "bottle", "pull-out", "basket", "oil", "condiment")
        b.aliases("bottle pullout", "bottle rack pull-out", "oil and vinegar pull-out", "150 mm", "200 mm", "300 mm", "6 in", "8 in", "12 in")
        b.role(.module)
        b.material("Frame Material", .stainless)
        b.material("Basket Material", .chrome)
        b.openingParameters(width: openingFor(200), depth: CC.mm(540), height: CC.mm(700), minWidth: CC.mm(110), maxWidth: CC.mm(270))
        b.length("Side Clearance", CC.mm(10), group: .manufacturing)
        b.length("Slide Length", CC.mm(500), group: .manufacturing)
        b.length("Basket Height", CC.mm(150))
        b.length("Lower Basket Height", CC.mm(80), instance: true, group: .placement)
        b.length("Upper Basket Height", CC.mm(400), instance: true, group: .placement)
        b.length("Wire Diameter", CC.mm(5))
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.fitsDepth("Slide Length + 0.01 m"))
        b.requires(.fitsHeight("Upper Basket Height + Basket Height + 0.03 m"))
        b.clearance(.box(name: "Pull-out travel", x0: "Side Clearance", x1: "Opening Width - Side Clearance", y0: "-Slide Length", y1: "0 m", z0: "0 m", z1: "Opening Height"))
        let x0 = "Side Clearance", x1 = "Opening Width - Side Clearance"
        b.using("Frame Material")
        b.floorRunners("Runner", x: ("Opening Width / 2 - 0.02 m", "Opening Width / 2 + 0.02 m"), y: ("0 m", "Slide Length"), width: CX.mm(18), height: CX.mm(18))
        b.box("Front Post", x: ("Opening Width / 2 - 0.012 m", "Opening Width / 2 + 0.012 m"), y: ("0 m", "0.025 m"), z: ("0.018 m", "Opening Height - 0.02 m"))
        b.box("Rear Post", x: ("Opening Width / 2 - 0.012 m", "Opening Width / 2 + 0.012 m"), y: ("Slide Length - 0.025 m", "Slide Length"), z: ("0.018 m", "Opening Height - 0.02 m"))
        b.using("Basket Material")
        for (n, z) in [("Lower", "Lower Basket Height"), ("Upper", "Upper Basket Height")] {
            b.basket("\(n) Basket", x: (x0, x1), y: ("0.03 m", "Slide Length - 0.03 m"), z: (z, "\(z) + Basket Height"), wire: "Wire Diameter")
            b.rodY("\(n) Divider", x: "Opening Width / 2", z: "\(z) + Basket Height * 0.7", d: "Wire Diameter", from: "0.03 m", to: "Slide Length - 0.03 m")
        }
        b.using(nil)
        b.drill("Runner screw", x: "Opening Width / 2 - 0.02 m", y: "0.037 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.drill("Runner screw", x: "Opening Width / 2 + 0.02 m", y: "0.037 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.outlines(x: (x0, x1), y: ("0 m", "Slide Length"), z: ("0 m", "Opening Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect((x0, "-Slide Length"), (x1, "0 m")))
        for (w, cost) in [(150.0, 89.0), (200, 99), (300, 119)] {
            b.type("Bottle Pull-Out - \(Int(w)) mm", ["Opening Width": openingFor(w)], cost: cost, model: "BPO-\(Int(w))", description: "Bottle pull-out for a \(Int(w)) mm cabinet")
        }
        return b.build()
    }

    // MARK: Corner systems

    /// Pie-cut (three-quarter) carousel shelves on a centre pole for a corner base; the doors fix to the cut-out faces.
    static func cornerCarousel() -> ComponentDefinition {
        var b = ComponentBuilder("Corner Carousel", .kitchen, "Corner Systems", "Pie-cut corner carousel: two or three 270° shelves on a centre pole, doors fixed to the shelves.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "corner", "carousel", "pie-cut", "rotating", "lazy susan")
        b.aliases("pie cut lazy susan", "corner carousel system", "rotating corner shelves", "28 in", "32 in", "710 mm", "810 mm")
        b.material("Shelf Material", .whitePlastic)
        b.material("Pole Material", .chrome)
        b.openingParameters(width: CC.mm(864), depth: CC.mm(864), height: CC.mm(700), minWidth: CC.mm(700))
        b.length("Shelf Diameter", CC.inch(28))
        b.length("Shelf Rim", CC.mm(30))
        b.length("Pole Diameter", CC.mm(25))
        b.number("Shelf Count", 2, group: .dimensions)
        b.number("Cut Angle", 90, unit: "°", group: .dimensions)
        b.number("Load per Shelf", 25, unit: "lb", group: .data)
        b.length("Pole X", 0, formula: "Opening Width / 2")
        b.length("Pole Y", 0, formula: "Opening Depth / 2")
        b.host([.bay], faces: [.bottom], align: .center)
        b.requires(.fitsWidth("Shelf Diameter + 0.02 m"))
        b.requires(.fitsDepth("Shelf Diameter + 0.02 m"))
        b.requires(.note("For a 900 mm (36\") L-corner base with a bi-fold door fixed to the shelves."))
        b.using("Pole Material")
        b.rodZ("Pole", x: "Pole X", y: "Pole Y", d: "Pole Diameter", from: "0 m", to: "Opening Height")
        b.cyl("Bottom Pivot", axis: .z, center: ("Pole X", "Pole Y"), radius: "0.04 m", from: "0 m", to: "0.008 m")
        b.cyl("Top Pivot", axis: .z, center: ("Pole X", "Pole Y"), radius: "0.035 m", from: "Opening Height - 0.006 m", to: "Opening Height")
        b.using("Shelf Material")
        for k in 1...3 {
            let z = "0.06 m + (Opening Height - 0.2 m) * \(k - 1) / max(1, Shelf Count - 1)"
            let v: String? = k <= 2 ? nil : "Show Shelf \(k)"
            if let v { b.countFlag(v, "Shelf Count >= \(k)") }
            let prof = ComponentKit.points([("Pole Diameter / 2", "0 m"), ("Shelf Diameter / 2", "0 m"), ("Shelf Diameter / 2", "Shelf Rim"),
                                            ("Shelf Diameter / 2 - 0.006 m", "Shelf Rim"), ("Shelf Diameter / 2 - 0.006 m", "0.006 m"), ("Pole Diameter / 2", "0.006 m")])
            b.shown(v) { $0.revolve("Shelf \(k)", profile: prof, axis: ("Pole X", "Pole Y"), base: z, startDegrees: "Cut Angle", endDegrees: "360") }
        }
        b.using(nil)
        b.drill("Pivot screw", x: "Pole X - 0.025 m", y: "Pole Y", diameter: CX.mm(4), depth: CX.mm(12))
        b.drill("Pivot screw", x: "Pole X + 0.025 m", y: "Pole Y", diameter: CX.mm(4), depth: CX.mm(12))
        b.symbol(.face, [.coarse], .arc(center: FamilyPoint("Pole X", "Pole Y"), radius: "Shelf Diameter / 2", startDegrees: "Cut Angle", sweepDegrees: "360 - Cut Angle"),
                 .line(("Pole X", "Pole Y"), ("Pole X + Shelf Diameter / 2", "Pole Y")), .line(("Pole X", "Pole Y"), ("Pole X", "Pole Y + Shelf Diameter / 2")))
        b.symbol(.top, [.coarse], .rect(("Pole X - Shelf Diameter / 2", "0 m"), ("Pole X + Shelf Diameter / 2", "Opening Height")))
        for (d, n, cost) in [(28.0, 2.0, 139.0), (32, 2, 159), (32, 3, 209)] {
            b.type("Corner Carousel - \(Int(d))\" \(Int(n))-Shelf", ["Shelf Diameter": CC.inch(d)], numbers: ["Shelf Count": n], cost: cost, model: "CC-\(Int(d))-\(Int(n))",
                   description: "Pie-cut carousel, \(Int(d))\" shelves, \(Int(n)) shelves")
        }
        return b.build()
    }

    /// A full-round or kidney two-shelf lazy susan on a bearing pole, for a 900 mm corner base or wall corner.
    static func lazySusan() -> ComponentDefinition {
        var b = ComponentBuilder("Lazy Susan", .kitchen, "Corner Systems", "Two-shelf lazy susan on an adjustable pole with ball-bearing hubs.", frame: .legacyOpening)
        b.tags("kitchen", "corner", "lazy susan", "turntable", "rotating", "shelf")
        b.aliases("lazy susan mechanism", "full round lazy susan", "kidney lazy susan", "turntable shelves", "24 in", "28 in", "610 mm", "710 mm")
        b.material("Shelf Material", .whitePlastic)
        b.material("Mechanism Material", .steel)
        b.openingParameters(width: CC.mm(864), depth: CC.mm(864), height: CC.mm(700), minWidth: CC.mm(600))
        b.length("Shelf Diameter", CC.inch(28))
        b.length("Shelf Rim", CC.mm(28))
        b.length("Pole Diameter", CC.mm(25))
        b.length("Shelf Spacing", CC.mm(330), instance: true, group: .placement)
        b.number("Load per Shelf", 30, unit: "lb", group: .data)
        b.length("Pole X", 0, formula: "Opening Width / 2")
        b.length("Pole Y", 0, formula: "Opening Depth / 2")
        b.host([.bay], faces: [.bottom], align: .center)
        b.requires(.fitsWidth("Shelf Diameter + 0.02 m"))
        b.requires(.fitsDepth("Shelf Diameter + 0.02 m"))
        b.using("Mechanism Material")
        b.rodZ("Pole", x: "Pole X", y: "Pole Y", d: "Pole Diameter", from: "0 m", to: "Opening Height")
        b.cyl("Base Plate", axis: .z, center: ("Pole X", "Pole Y"), radius: "0.05 m", from: "0 m", to: "0.006 m")
        b.cyl("Top Plate", axis: .z, center: ("Pole X", "Pole Y"), radius: "0.04 m", from: "Opening Height - 0.006 m", to: "Opening Height")
        for (k, z) in ["0.05 m", "0.05 m + Shelf Spacing"].enumerated() {
            b.using("Mechanism Material")
            b.cyl("Hub \(k + 1)", axis: .z, center: ("Pole X", "Pole Y"), radius: "0.045 m", from: "\(z) - 0.02 m", to: z)
            b.using("Shelf Material")
            let prof = ComponentKit.points([("Pole Diameter / 2", "0 m"), ("Shelf Diameter / 2", "0 m"), ("Shelf Diameter / 2", "Shelf Rim"),
                                            ("Shelf Diameter / 2 - 0.006 m", "Shelf Rim"), ("Shelf Diameter / 2 - 0.006 m", "0.006 m"), ("Pole Diameter / 2", "0.006 m")])
            b.revolve("Shelf \(k + 1)", profile: prof, axis: ("Pole X", "Pole Y"), base: z)
        }
        b.using(nil)
        b.drill("Base plate screw", x: "Pole X - 0.035 m", y: "Pole Y", diameter: CX.mm(4), depth: CX.mm(12))
        b.drill("Base plate screw", x: "Pole X + 0.035 m", y: "Pole Y", diameter: CX.mm(4), depth: CX.mm(12))
        b.symbol(.face, [.coarse], .circle(("Pole X", "Pole Y"), "Shelf Diameter / 2"), .circle(("Pole X", "Pole Y"), "Pole Diameter / 2"))
        b.symbol(.top, [.coarse], .rect(("Pole X - Shelf Diameter / 2", "0 m"), ("Pole X + Shelf Diameter / 2", "Opening Height")))
        for (d, cost) in [(24.0, 79.0), (28, 99), (32, 119)] {
            b.type("Lazy Susan - \(Int(d))\" 2-Shelf", ["Shelf Diameter": CC.inch(d)], cost: cost, model: "LS-\(Int(d))", description: "Full-round lazy susan, two \(Int(d))\" shelves",
                   isDefault: d == 28)
        }
        return b.build()
    }

    /// Blind-corner pull-out: a front pair of baskets on the door frame that pulls out and swings aside, and a rear pair
    /// that glides forward on a track into the opening.
    static func magicCorner() -> ComponentDefinition {
        var b = ComponentBuilder("Magic Corner Unit", .kitchen, "Corner Systems",
                                 "Blind-corner pull-out: two front baskets on the door frame and two rear baskets that follow them out of the blind corner.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "corner", "blind corner", "magic corner", "pull-out", "basket")
        b.aliases("blind corner pull-out", "corner pull out", "magic corner", "blind corner organizer", "900 mm", "1000 mm", "36 in", "39 in")
        b.role(.module)
        b.material("Frame Material", .steel)
        b.material("Basket Material", .chrome)
        b.openingParameters(width: CC.mm(864), depth: CC.mm(520), height: CC.mm(700), minWidth: CC.mm(800))
        b.length("Door Opening Width", CC.mm(450))
        b.length("Basket Width", CC.mm(380))
        b.length("Basket Depth", CC.mm(470))
        b.length("Basket Height", CC.mm(110))
        b.flag("Left Hand", false, group: .placement)
        b.flag("Right Hand", false, formula: "not(Left Hand)")
        b.flag("Pulled Out", false, group: .placement)
        b.host([.bay], faces: [.bottom], align: .left, alignments: [.left, .right])
        b.requires(.hostWidth(min: "Door Opening Width + Basket Width", max: nil))
        b.requires(.note("Opening hand follows the blind side: the door opening sits on the open side."))
        for hand in ["Right Hand", "Left Hand"] {
            // Right hand: door opening on the left, blind corner on the right.
            let left = hand == "Left Hand"
            let fx0 = left ? "Opening Width - Door Opening Width + 0.02 m" : "0.02 m"
            let rx0 = left ? "0.02 m" : "Opening Width - Basket Width - 0.02 m"
            let pull = "if(Pulled Out, -Basket Depth * 0.9, 0 m)"
            b.shown(hand) { b in
                b.using("Frame Material")
                b.box("Track (\(hand))", x: ("0.01 m", "Opening Width - 0.01 m"), y: ("Opening Depth - 0.06 m", "Opening Depth - 0.02 m"), z: ("0 m", "0.02 m"))
                b.box("Front Frame (\(hand))", x: (fx0, "\(fx0) + 0.025 m"), y: ("\(pull)", "\(pull) + 0.025 m"), z: ("0.02 m", "Opening Height - 0.03 m"))
                for px in [rx0, "\(rx0) + Basket Width - 0.02 m"] {
                    b.box("Rear Post (\(hand))", x: (px, "\(px) + 0.02 m"), y: ("Opening Depth - 0.08 m", "Opening Depth - 0.06 m"), z: ("0.02 m", "Opening Height - 0.03 m"))
                }
                b.using("Basket Material")
                for (k, z) in ["0.06 m", "Opening Height * 0.5"].enumerated() {
                    b.basket("Front Basket \(k + 1) (\(hand))", x: ("\(fx0) + 0.03 m", "\(fx0) + 0.03 m + Basket Width"), y: ("\(pull) + 0.03 m", "\(pull) + 0.03 m + Basket Depth * 0.8"),
                             z: (z, "\(z) + Basket Height"), wire: CX.mm(5))
                    b.basket("Rear Basket \(k + 1) (\(hand))", x: (rx0, "\(rx0) + Basket Width"), y: ("Opening Depth - 0.08 m - Basket Depth * 0.8", "Opening Depth - 0.08 m"),
                             z: (z, "\(z) + Basket Height"), wire: CX.mm(5))
                }
            }
        }
        b.using(nil)
        b.drill("Track screw", x: "0.05 m", y: "Opening Depth - 0.04 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.drill("Track screw", x: "Opening Width - 0.05 m", y: "Opening Depth - 0.04 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Opening Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .line(("0.1 m", "Opening Depth / 2"), ("0.1 m", "-Basket Depth * 0.8")))
        for (w, cost) in [(900.0, 489.0), (1000, 529)] {
            b.type("Magic Corner Unit - \(Int(w)) mm", ["Opening Width": CC.mm(w - 36), "Door Opening Width": CC.mm(w == 900 ? 450 : 500)], cost: cost, model: "MCU-\(Int(w))",
                   description: "Blind-corner pull-out for a \(Int(w)) mm blind-corner base")
        }
        return b.build()
    }

    /// Blind-corner swing-out: two kidney shelves on a pivoting post that swing out of the blind corner (generic for the
    /// kidney swing-out style).
    static func blindCornerSwingOut() -> ComponentDefinition {
        var b = ComponentBuilder("Blind-Corner Swing-Out", .kitchen, "Corner Systems",
                                 "Two kidney-shaped shelves on a pivot post that swing out of a blind corner base through the door opening.", frame: .legacyOpening)
        b.tags("kitchen", "corner", "blind corner", "swing-out", "kidney", "pivot")
        b.aliases("kidney swing out", "blind corner swing out", "corner swing shelves", "15 in", "18 in", "380 mm", "450 mm")
        b.material("Shelf Material", .greyPlastic)
        b.material("Mechanism Material", .chrome)
        b.openingParameters(width: CC.mm(864), depth: CC.mm(520), height: CC.mm(700), minWidth: CC.mm(780))
        b.length("Door Opening Width", CC.inch(15))
        b.length("Shelf Length", CC.mm(780))
        b.length("Shelf Width", CC.mm(380))
        b.length("Shelf Rim", CC.mm(55))
        b.length("Shelf Spacing", CC.mm(320))
        b.number("Load per Shelf", 26, unit: "lb", group: .data)
        b.flag("Left Hand", false, group: .placement)
        b.flag("Right Hand", false, formula: "not(Left Hand)")
        b.host([.bay], faces: [.bottom], align: .left, alignments: [.left, .right])
        b.requires(.hostWidth(min: "Shelf Length + 0.03 m", max: nil))
        b.requires(.hostWidth(min: "Door Opening Width", max: nil))
        for hand in ["Right Hand", "Left Hand"] {
            let px = hand == "Left Hand" ? "Opening Width - 0.04 m" : "0.04 m"
            let x0 = hand == "Left Hand" ? "Opening Width - 0.02 m - Shelf Length" : "0.02 m"
            b.shown(hand) { b in
                b.using("Mechanism Material")
                b.rodZ("Pivot Post (\(hand))", x: px, y: "0.06 m", d: CX.mm(30), from: "0 m", to: "Opening Height - 0.02 m")
                b.box("Base Bracket (\(hand))", x: ("\(px) - 0.04 m", "\(px) + 0.04 m"), y: ("0.02 m", "0.1 m"), z: ("0 m", "0.006 m"))
                for (k, z) in ["0.08 m", "0.08 m + Shelf Spacing"].enumerated() {
                    b.using("Mechanism Material")
                    b.box("Arm \(k + 1) (\(hand))", x: (x0, "\(x0) + Shelf Length"), y: ("0.05 m", "0.07 m"), z: ("\(z) - 0.02 m", z))
                    b.using("Shelf Material")
                    // Kidney: a rounded bar with a shallow front recess.
                    b.roundedBar("Shelf \(k + 1) (\(hand))", center: ("\(x0) + Shelf Length / 2", "0.07 m + Shelf Width / 2"), width: "Shelf Length", height: "Shelf Width",
                                 radius: "Shelf Width / 2 - 0.001 m", from: z, to: "\(z) + 0.008 m")
                    b.roundedBar("Shelf \(k + 1) Rim (\(hand))", center: ("\(x0) + Shelf Length / 2", "Shelf Width + 0.06 m"), width: "Shelf Length * 0.85", height: "0.012 m",
                                 radius: "0.005 m", from: z, to: "\(z) + Shelf Rim")
                }
            }
        }
        b.using(nil)
        b.drill("Base bracket screw", x: "0.04 m", y: "0.04 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.drill("Base bracket screw", x: "0.04 m", y: "0.09 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.outlines(x: ("0.02 m", "0.02 m + Shelf Length"), y: ("0.07 m", "0.07 m + Shelf Width"), z: ("0 m", "Opening Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("0.04 m", "0.06 m"), radius: "Shelf Length", startDegrees: "-90", sweepDegrees: "90"))
        for (w, cost) in [(15.0, 349.0), (18, 389)] {
            b.type("Blind-Corner Swing-Out - \(Int(w))\" Door", ["Door Opening Width": CC.inch(w), "Shelf Length": CC.mm(w == 15 ? 780 : 860)], cost: cost, model: "BCS-\(Int(w))",
                   description: "Kidney swing-out for a blind corner with a \(Int(w))\" door opening")
        }
        return b.build()
    }

    /// Corner wire basket for an upper or base corner: a quarter-round tray in the bay's back corner.
    static func cornerBasket() -> ComponentDefinition {
        var b = ComponentBuilder("Corner Storage Basket", .kitchen, "Corner Systems", "Quarter-round wire basket that fills the back corner of a bay.", frame: .legacyOpening)
        b.tags("kitchen", "corner", "basket", "wire", "storage", "quarter round")
        b.aliases("corner wire basket", "corner shelf basket", "quarter round basket", "12 in", "15 in", "300 mm", "380 mm")
        b.material("Finish Material", .chrome)
        b.openingParameters(width: CC.mm(564), depth: CC.mm(300), height: CC.mm(700))
        b.length("Basket Size", CC.inch(12))
        b.length("Basket Height", CC.mm(140))
        b.length("Mount Height", CC.mm(20), instance: true, group: .placement)
        b.flag("Left Corner", true, group: .placement)
        b.flag("Right Corner", false, formula: "not(Left Corner)")
        b.host([.bay], faces: [.bottom, .back], align: .left, alignments: [.left, .right])
        b.requires(.fitsDepth("Basket Size"))
        for (side, cx, sweep) in [("Left Corner", "0 m", ("-90", "0")), ("Right Corner", "Opening Width", ("180", "270"))] {
            let c = (cx, "Opening Depth")
            b.shown(side) { b in
                b.revolve("Basket Floor (\(side))", profile: ComponentKit.points([("0 m", "0 m"), ("Basket Size", "0 m"), ("Basket Size", "0.003 m"), ("0 m", "0.003 m")]),
                          axis: c, base: "Mount Height", startDegrees: sweep.0, endDegrees: sweep.1)
                for (k, h) in ["Basket Height * 0.5", "Basket Height"].enumerated() {
                    b.revolve("Basket Rim \(k + 1) (\(side))", profile: ComponentKit.circle(center: ("Basket Size - 0.003 m", "-0.003 m"), radius: "0.003 m", segments: 8),
                              axis: c, base: "Mount Height + \(h)", startDegrees: sweep.0, endDegrees: sweep.1)
                }
                let dx = side == "Left Corner" ? "" : "-"
                b.rodZ("Post (\(side))", x: "\(cx) + \(dx)(Basket Size - 0.003 m)", y: "Opening Depth - 0.003 m", d: CX.mm(6), from: "Mount Height", to: "Mount Height + Basket Height")
            }
        }
        b.drill("Mounting screw", x: "0.02 m", y: "Opening Depth - 0.02 m", diameter: CX.mm(4), depth: CX.mm(12))
        b.symbol(.face, [.coarse], .arc(center: FamilyPoint("0 m", "Opening Depth"), radius: "Basket Size", startDegrees: "-90", sweepDegrees: "90"),
                 .line(("0 m", "Opening Depth - Basket Size"), ("0 m", "Opening Depth")), .line(("0 m", "Opening Depth"), ("Basket Size", "Opening Depth")))
        b.symbol(.top, [.coarse], .rect(("0 m", "Mount Height"), ("Basket Size", "Mount Height + Basket Height")))
        for (s, cost) in [(12.0, 29.0), (15, 35)] {
            b.type("Corner Storage Basket - \(Int(s))\"", ["Basket Size": CC.inch(s)], cost: cost, model: "CSB-\(Int(s))", description: "Quarter-round corner basket, \(Int(s))\" radius")
        }
        return b.build()
    }

    // MARK: Drawer inserts

    /// Peg-board plate organizer for a deep drawer: a base board with two rows of movable pegs.
    static func plateOrganizer() -> ComponentDefinition {
        var b = ComponentBuilder("Plate Organizer", .kitchen, "Drawer Inserts", "Peg board for a deep drawer: movable pegs hold plates and bowls upright.", frame: .legacyOpening)
        b.tags("kitchen", "plate", "peg", "drawer", "insert", "dish")
        b.aliases("peg board", "dish peg organizer", "drawer peg system", "plate rack drawer")
        b.material("Board Material", .beech)
        b.material("Peg Material", .beech)
        b.openingParameters(width: CC.mm(564), depth: CC.mm(480), height: CC.mm(250))
        b.length("Board Thickness", CC.mm(12))
        b.length("Peg Diameter", CC.mm(20))
        b.length("Peg Height", CC.mm(120))
        b.length("Peg Spacing", CC.mm(96), instance: true, group: .placement)
        b.length("Row Spacing", CC.mm(220), instance: true, group: .placement)
        b.length("Edge Clearance", CC.mm(5), group: .manufacturing)
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.note("Place it in the drawer's bay; it sits in the drawer box."))
        b.requires(.fitsHeight("Board Thickness + Peg Height + 0.01 m"))
        b.using("Board Material")
        b.box("Board", x: ("Edge Clearance", "Opening Width - Edge Clearance"), y: ("Edge Clearance", "Opening Depth - Edge Clearance"), z: ("0 m", "Board Thickness"))
        b.using("Peg Material")
        for row in 0..<2 {
            let y = row == 0 ? "Opening Depth / 2 - Row Spacing / 2" : "Opening Depth / 2 + Row Spacing / 2"
            for k in 0..<7 {
                let x = "0.05 m + Peg Spacing * \(k)"
                let v = "Show Peg \(k + 1)"
                if row == 0 { b.countFlag(v, "0.05 m + Peg Spacing * \(k) < Opening Width - 0.04 m") }
                b.shown(v) { $0.rodZ("Peg \(row + 1)-\(k + 1)", x: x, y: y, d: "Peg Diameter", from: "Board Thickness", to: "Board Thickness + Peg Height") }
            }
        }
        b.using(nil)
        b.outlines(x: ("Edge Clearance", "Opening Width - Edge Clearance"), y: ("Edge Clearance", "Opening Depth - Edge Clearance"), z: ("0 m", "Board Thickness + Peg Height"))
        for (w, cost) in [(600.0, 59.0), (800, 69), (900, 79)] {
            b.type("Plate Organizer - \(Int(w)) mm", ["Opening Width": CC.mm(w - 36 - 26)], cost: cost, model: "PO-\(Int(w))", description: "Peg board for a \(Int(w)) mm drawer cabinet")
        }
        return b.build()
    }

    /// Wire dish rack for an upper cabinet (over-sink drying cabinet): plate wires on a lower tier, cups above, drip tray.
    static func dishRack() -> ComponentDefinition {
        var b = ComponentBuilder("Dish Rack", .kitchen, "Racks & Holders", "Two-tier wire dish rack for a wall cabinet: plate tier, cup tier and drip tray.", frame: .legacyOpening)
        b.tags("kitchen", "dish", "rack", "drying", "plate", "wall cabinet")
        b.aliases("dish drainer", "plate rack", "drying rack", "over sink dish rack", "600 mm", "800 mm", "900 mm", "24 in", "30 in", "36 in")
        b.material("Rack Material", .stainless)
        b.material("Tray Material", .greyPlastic)
        b.openingParameters(width: CC.mm(764), depth: CC.mm(280), height: CC.mm(700))
        b.length("Wire Diameter", CC.mm(4))
        b.length("Plate Tier Height", CC.mm(60), instance: true, group: .placement)
        b.length("Cup Tier Height", CC.mm(380), instance: true, group: .placement)
        b.length("Plate Wire Height", CC.mm(160))
        b.length("Wire Pitch", CC.mm(30))
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.fitsHeight("Cup Tier Height + 0.12 m"))
        b.using("Tray Material")
        b.tray("Drip Tray", x: ("0.005 m", "Opening Width - 0.005 m"), y: ("0.01 m", "Opening Depth - 0.005 m"), z: ("0 m", "0.025 m"), wall: CX.mm(2), floor: CX.mm(2))
        b.using("Rack Material")
        for (n, z) in [("Plate", "Plate Tier Height"), ("Cup", "Cup Tier Height")] {
            b.rodX("\(n) Tier Front", y: "0.03 m", z: z, d: "Wire Diameter", from: "0.01 m", to: "Opening Width - 0.01 m")
            b.rodX("\(n) Tier Back", y: "Opening Depth - 0.03 m", z: z, d: "Wire Diameter", from: "0.01 m", to: "Opening Width - 0.01 m")
            for k in 0..<5 {
                let y = CX.lerp("0.03 m", "Opening Depth - 0.03 m", Double(k) / 4)
                b.rodX("\(n) Tier Wire \(k + 1)", y: y, z: z, d: "Wire Diameter * 0.8", from: "0.01 m", to: "Opening Width - 0.01 m")
            }
            b.rodY("\(n) Tier Left", x: "0.01 m", z: z, d: "Wire Diameter", from: "0.03 m", to: "Opening Depth - 0.03 m")
            b.rodY("\(n) Tier Right", x: "Opening Width - 0.01 m", z: z, d: "Wire Diameter", from: "0.03 m", to: "Opening Depth - 0.03 m")
        }
        // Plate wires: a row of upright wires across the plate tier, at the pitch, up to the width.
        for k in 0..<30 {
            let v = "Show Plate Wire \(k + 1)"
            b.countFlag(v, "0.03 m + Wire Pitch * \(k) < Opening Width - 0.03 m")
            b.shown(v) { $0.rodZ("Plate Wire \(k + 1)", x: "0.03 m + Wire Pitch * \(k)", y: "Opening Depth * 0.4", d: "Wire Diameter * 0.8", from: "Plate Tier Height", to: "Plate Tier Height + Plate Wire Height") }
        }
        b.using(nil)
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Cup Tier Height + 0.08 m"))
        for (w, cost) in [(600.0, 89.0), (800, 109), (900, 119)] {
            b.type("Dish Rack - \(Int(w)) mm", ["Opening Width": openingFor(w)], cost: cost, model: "DR-\(Int(w))", description: "Two-tier dish rack for a \(Int(w)) mm wall cabinet")
        }
        return b.build()
    }

    /// Cutlery organizer: a moulded tray with five compartments sized to the drawer box.
    static func cutleryOrganizer() -> ComponentDefinition {
        var b = ComponentBuilder("Cutlery Organizer", .kitchen, "Drawer Inserts", "Moulded cutlery insert with compartments, trimmed to the drawer box.", frame: .legacyOpening)
        b.tags("kitchen", "cutlery", "silverware", "drawer", "insert", "tray")
        b.aliases("cutlery tray", "silverware organizer", "cutlery insert", "flatware tray", "400 mm", "450 mm", "600 mm", "15 in", "18 in", "24 in")
        b.material("Finish Material", .greyPlastic)
        b.openingParameters(width: CC.mm(400), depth: CC.mm(470), height: CC.mm(70))
        b.length("Tray Height", CC.mm(55))
        b.length("Wall Thickness", CC.mm(3))
        b.number("Compartments", 5, group: .dimensions)
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.note("Place it in the drawer's bay; it sits in the drawer box."))
        b.requires(.fitsHeight("Tray Height + 0.005 m"))
        b.requires(.note("Sized to the drawer box inside; trim to fit."))
        b.tray("Tray", x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Tray Height"), wall: "Wall Thickness", floor: "Wall Thickness")
        b.box("Cross Wall", x: ("Wall Thickness", "Opening Width - Wall Thickness"), y: ("Opening Depth * 0.3", "Opening Depth * 0.3 + Wall Thickness"), z: ("0 m", "Tray Height * 0.8"))
        for k in 1...5 {
            let v = "Show Divider \(k)"
            b.countFlag(v, "Compartments > \(k)")
            let x = "Opening Width * \(k) / Compartments"
            b.shown(v) { $0.box("Divider \(k)", x: ("\(x) - Wall Thickness / 2", "\(x) + Wall Thickness / 2"), y: ("Opening Depth * 0.3", "Opening Depth - Wall Thickness"), z: ("0 m", "Tray Height * 0.9")) }
        }
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Tray Height"))
        for (w, n, cost) in [(400.0, 4.0, 24.0), (450, 5, 27), (600, 6, 34)] {
            b.type("Cutlery Organizer - \(Int(w)) mm", ["Opening Width": CC.mm(w - 36 - 26 - 30)], numbers: ["Compartments": n], cost: cost, model: "CO-\(Int(w))",
                   description: "Cutlery insert for a \(Int(w)) mm drawer, \(Int(n)) compartments")
        }
        return b.build()
    }

    /// Utensil tray: a shallow sliding top tray over a full-depth lower tray (two tiers).
    static func utensilTray() -> ComponentDefinition {
        var b = ComponentBuilder("Utensil Tray", .kitchen, "Drawer Inserts", "Two-tier utensil insert: a half-depth top tray slides over a long-compartment lower tray.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "utensil", "tray", "drawer", "insert", "two-tier")
        b.aliases("two tier cutlery tray", "sliding utensil tray", "double cutlery", "utensil organizer")
        b.material("Finish Material", .walnut)
        b.openingParameters(width: CC.mm(500), depth: CC.mm(470), height: CC.mm(110))
        b.length("Lower Tray Height", CC.mm(50))
        b.length("Upper Tray Height", CC.mm(40))
        b.length("Wall Thickness", CC.mm(6))
        b.length("Upper Tray Position", CC.mm(0), instance: true, group: .placement, min: 0)
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.note("Place it in the drawer's bay; it sits in the drawer box."))
        b.requires(.fitsHeight("Lower Tray Height + Upper Tray Height + 0.008 m"))
        b.tray("Lower Tray", x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Lower Tray Height"), wall: "Wall Thickness", floor: "Wall Thickness")
        for k in 1...3 {
            let x = "Opening Width * \(k) / 4"
            b.box("Lower Divider \(k)", x: ("\(x) - Wall Thickness / 2", "\(x) + Wall Thickness / 2"), y: ("Wall Thickness", "Opening Depth - Wall Thickness"), z: ("0 m", "Lower Tray Height"))
        }
        let y0 = "Upper Tray Position", y1 = "Upper Tray Position + Opening Depth / 2"
        b.tray("Upper Tray", x: ("Wall Thickness", "Opening Width - Wall Thickness"), y: (y0, y1), z: ("Lower Tray Height", "Lower Tray Height + Upper Tray Height"),
               wall: "Wall Thickness", floor: "Wall Thickness")
        b.box("Upper Divider", x: ("Opening Width / 2 - Wall Thickness / 2", "Opening Width / 2 + Wall Thickness / 2"), y: (y0, y1),
              z: ("Lower Tray Height", "Lower Tray Height + Upper Tray Height"))
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Lower Tray Height + Upper Tray Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("Wall Thickness", "Opening Depth / 2"), ("Opening Width - Wall Thickness", "Opening Depth")))
        for (w, cost) in [(450.0, 49.0), (600, 59)] {
            b.type("Utensil Tray - \(Int(w)) mm", ["Opening Width": CC.mm(w - 36 - 26 - 30)], cost: cost, model: "UT-\(Int(w))", description: "Two-tier utensil tray for a \(Int(w)) mm drawer")
        }
        return b.build()
    }

    /// Pot and pan organizer: a rail across a deep drawer with adjustable upright dividers.
    static func potPanOrganizer() -> ComponentDefinition {
        var b = ComponentBuilder("Pot and Pan Organizer", .kitchen, "Drawer Inserts", "Deep-drawer rail with adjustable upright dividers for pans, lids and trays.", frame: .legacyOpening)
        b.tags("kitchen", "pot", "pan", "lid", "divider", "drawer")
        b.aliases("pan organizer", "lid organizer", "tray divider", "pot lid rack", "pan rack drawer")
        b.material("Rail Material", .aluminum)
        b.material("Divider Material", .stainless)
        b.openingParameters(width: CC.mm(764), depth: CC.mm(470), height: CC.mm(250))
        b.length("Divider Height", CC.mm(180))
        b.length("Divider Depth", CC.mm(300))
        b.number("Divider Count", 4, group: .dimensions)
        b.length("Divider Spacing", CC.mm(100), instance: true, group: .placement)
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.note("Place it in the drawer's bay; it sits in the drawer box."))
        b.requires(.fitsHeight("Divider Height + 0.01 m"))
        b.using("Rail Material")
        for (k, y) in ["0.03 m", "Opening Depth - 0.05 m"].enumerated() {
            b.box("Base Rail \(k + 1)", x: ("0.005 m", "Opening Width - 0.005 m"), y: (y, "\(y) + 0.02 m"), z: ("0 m", "0.012 m"))
        }
        b.using("Divider Material")
        for k in 1...8 {
            let v: String? = k == 1 ? nil : "Show Divider \(k)"
            if let v { b.countFlag(v, "Divider Count >= \(k)") }
            let x = "0.05 m + Divider Spacing * \(k - 1)"
            b.shown(v) { b in
                b.wire("Divider \(k)", plane: .yz, [("0.04 m", "0.012 m"), ("0.04 m", "Divider Height"), ("0.04 m + Divider Depth", "Divider Height"), ("0.04 m + Divider Depth", "0.012 m")],
                       at: x, d: CX.mm(6))
            }
        }
        b.using(nil)
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Divider Height"))
        for (w, n, cost) in [(600.0, 4.0, 45.0), (800, 6, 59), (900, 7, 65)] {
            b.type("Pot and Pan Organizer - \(Int(w)) mm", ["Opening Width": CC.mm(w - 36 - 26)], numbers: ["Divider Count": n], cost: cost, model: "PPO-\(Int(w))",
                   description: "Pan divider rail for a \(Int(w)) mm drawer cabinet, \(Int(n)) dividers")
        }
        return b.build()
    }

    /// Under-sink organizer: a U-shaped two-tier pull-out that clears the drain and supply pipes.
    static func underSinkOrganizer() -> ComponentDefinition {
        var b = ComponentBuilder("Under-Sink Organizer", .kitchen, "Pull-Outs", "U-shaped two-tier pull-out for a sink base, leaving room for the drain and supply pipes.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "sink", "under sink", "pull-out", "organizer", "cleaning")
        b.aliases("sink base organizer", "under sink pull out", "u-shape sink organizer", "600 mm", "800 mm", "900 mm", "24 in", "30 in", "36 in")
        b.role(.module)
        b.material("Frame Material", .stainless)
        b.material("Tray Material", .greyPlastic)
        b.openingParameters(width: CC.mm(764), depth: CC.mm(520), height: CC.mm(700))
        b.length("Pipe Gap Width", CC.mm(260))
        b.length("Tray Depth", CC.mm(420))
        b.length("Upper Tier Height", CC.mm(260), instance: true, group: .placement)
        b.length("Slide Length", CC.mm(450), group: .manufacturing)
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.fitsDepth("Slide Length + 0.01 m"))
        b.requires(.note("Keep the pipe gap over the drain."))
        b.clearance(.box(name: "Pipe space", x0: "(Opening Width - Pipe Gap Width) / 2", x1: "(Opening Width + Pipe Gap Width) / 2", y0: "0 m", y1: "Opening Depth", z0: "0.06 m", z1: "Opening Height"))
        b.using("Frame Material")
        b.sideRunners("Slide", width: "Opening Width", y: ("0 m", "Slide Length"), z: "0.03 m", height: CX.mm(35), thickness: CX.mm(13))
        let gx0 = "(Opening Width - Pipe Gap Width) / 2", gx1 = "(Opening Width + Pipe Gap Width) / 2"
        b.using("Tray Material")
        b.tray("Lower Tray", x: ("0.015 m", "Opening Width - 0.015 m"), y: ("0.01 m", "Tray Depth"), z: ("0.015 m", "0.075 m"), wall: CX.mm(3), floor: CX.mm(3))
        for (n, x) in [("Left", ("0.015 m", gx0)), ("Right", (gx1, "Opening Width - 0.015 m"))] {
            b.using("Tray Material")
            b.tray("Upper \(n) Tray", x: x, y: ("0.01 m", "Tray Depth"), z: ("Upper Tier Height", "Upper Tier Height + 0.07 m"), wall: CX.mm(3), floor: CX.mm(3))
            b.using("Frame Material")
            let px = n == "Left" ? "0.025 m" : "Opening Width - 0.025 m"
            b.rodZ("\(n) Front Post", x: px, y: "0.02 m", d: CX.mm(10), from: "0.075 m", to: "Upper Tier Height")
            b.rodZ("\(n) Rear Post", x: px, y: "Tray Depth - 0.01 m", d: CX.mm(10), from: "0.075 m", to: "Upper Tier Height")
        }
        b.using(nil)
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Tray Depth"), z: ("0 m", "Upper Tier Height + 0.07 m"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect((gx0, "0 m"), (gx1, "Opening Depth")))
        for (w, cost) in [(600.0, 89.0), (800, 109), (900, 119)] {
            b.type("Under-Sink Organizer - \(Int(w)) mm", ["Opening Width": openingFor(w), "Pipe Gap Width": CC.mm(w == 600 ? 200 : 260)], cost: cost, model: "USO-\(Int(w))",
                   description: "U-shaped sink base pull-out for a \(Int(w)) mm cabinet")
        }
        return b.build()
    }

    // MARK: Waste and recycling

    /// Pull-out waste bin: a bottom-mount frame on full-extension runners holding one to three tapered bins with lids.
    static func trashPullOut() -> ComponentDefinition {
        var b = ComponentBuilder("Pull-Out Trash Bin", .kitchen, "Waste & Recycling", "Door-mounted waste pull-out with one, two or three bins and lids on full-extension runners.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "trash", "waste", "bin", "pull-out", "garbage")
        b.aliases("waste bin pull out", "garbage pull-out", "trash can pull out", "bin pull-out", "single 35 l", "double 2 x 35 l", "35 qt", "300 mm", "450 mm", "600 mm")
        b.role(.module)
        b.material("Frame Material", .steel)
        b.material("Bin Material", .whitePlastic)
        b.material("Lid Material", .greyPlastic)
        b.openingParameters(width: openingFor(450), depth: CC.mm(540), height: CC.mm(700), minWidth: CC.mm(260))
        b.number("Bin Count", 2, group: .dimensions)
        b.number("Bin Volume", 35, unit: "L", group: .dimensions)
        b.length("Bin Height", CC.mm(480))
        b.length("Bin Depth", CC.mm(400))
        b.length("Bin Gap", CC.mm(10), group: .manufacturing)
        b.length("Slide Length", CC.mm(500), group: .manufacturing)
        b.flag("Lids", true, group: .constraints)
        b.length("Bin Width", 0, formula: "(Opening Width - 0.03 m - Bin Gap * (Bin Count - 1)) / Bin Count")
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.fitsDepth("Slide Length + 0.01 m"))
        b.requires(.fitsHeight("Bin Height + 0.06 m"))
        b.requires(.hostWidth(min: "0.26 m", max: "0.57 m"))
        b.clearance(.box(name: "Pull-out travel", x0: "0 m", x1: "Opening Width", y0: "-Slide Length", y1: "0 m", z0: "0 m", z1: "Bin Height + 0.06 m"))
        b.using("Frame Material")
        b.floorRunners("Runner", x: ("0.03 m", "Opening Width - 0.03 m"), y: ("0 m", "Slide Length"), width: CX.mm(25), height: CX.mm(20))
        b.box("Frame Tray", x: ("0.01 m", "Opening Width - 0.01 m"), y: ("0.01 m", "Slide Length"), z: ("0.02 m", "0.03 m"))
        b.box("Door Bracket", x: ("Opening Width / 2 - 0.1 m", "Opening Width / 2 + 0.1 m"), y: ("0 m", "0.02 m"), z: ("0.03 m", "0.28 m"))
        let y0 = "(Slide Length - Bin Depth) / 2 + 0.01 m", y1 = "(Slide Length + Bin Depth) / 2 + 0.01 m"
        for k in 1...3 {
            let v: String? = k == 1 ? nil : "Show Bin \(k)"
            if let v { b.countFlag(v, "Bin Count >= \(k)") }
            let x0 = "0.015 m + (Bin Width + Bin Gap) * \(k - 1)", x1 = "0.015 m + (Bin Width + Bin Gap) * \(k - 1) + Bin Width"
            let cx = "\(x0) + Bin Width / 2", cy = "(Slide Length / 2 + 0.01 m)"
            b.shown(v) { b in
                b.using("Bin Material")
                b.blend("Bin \(k)", bottom: ComponentKit.roundedRect(center: (cx, cy), width: "Bin Width * 0.86", height: "Bin Depth * 0.88", radius: "0.02 m"),
                        top: ComponentKit.roundedRect(center: (cx, cy), width: "Bin Width", height: "Bin Depth", radius: "0.025 m"), from: "0.03 m", to: "0.03 m + Bin Height")
                b.box("Bin \(k) Rim", x: ("\(x0) - 0.004 m", "\(x1) + 0.004 m"), y: ("\(y0) - 0.004 m", "\(y0) + 0.01 m"), z: ("0.03 m + Bin Height - 0.025 m", "0.03 m + Bin Height"))
            }
            let lid = v == nil ? "Lids" : "Show Lid \(k)"
            if v != nil { b.countFlag(lid, "and(Lids, Bin Count >= \(k))") }
            b.shown(lid) { b in
                b.using("Lid Material")
                b.roundedBar("Lid \(k)", center: (cx, cy), width: "Bin Width + 0.006 m", height: "Bin Depth + 0.006 m", radius: "0.025 m", from: "0.03 m + Bin Height", to: "0.03 m + Bin Height + 0.012 m")
            }
            _ = y1
        }
        b.using(nil)
        for x in ["0.03 m", "Opening Width - 0.03 m"] {
            for y in ["0.037 m", "0.293 m"] { b.drill("Runner screw", x: x, y: y, diameter: CX.mm(4), depth: CX.mm(12)) }
        }
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Slide Length"), z: ("0 m", "Bin Height + 0.04 m"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("0 m", "-Slide Length"), ("Opening Width", "0 m")))
        b.type("Pull-Out Trash Bin - Single 35 L - 300 mm", ["Opening Width": openingFor(300)], numbers: ["Bin Count": 1, "Bin Volume": 35], cost: 139, model: "TPO-1-35",
               description: "Waste pull-out for a 300 mm base, one 35 L bin")
        b.type("Pull-Out Trash Bin - Double 2 x 35 L - 450 mm", ["Opening Width": openingFor(450)], numbers: ["Bin Count": 2, "Bin Volume": 35], cost: 189, model: "TPO-2-35",
               description: "Waste pull-out for a 450 mm base, two 35 L bins", isDefault: true)
        b.type("Pull-Out Trash Bin - Double 2 x 50 L - 600 mm", ["Opening Width": openingFor(600), "Bin Depth": CC.mm(440)], numbers: ["Bin Count": 2, "Bin Volume": 50], cost: 229,
               model: "TPO-2-50", description: "Waste pull-out for a 600 mm base, two 50 L bins")
        b.type("Pull-Out Trash Bin - Triple 3 x 18 L - 600 mm", ["Opening Width": openingFor(600), "Bin Height": CC.mm(400)], numbers: ["Bin Count": 3, "Bin Volume": 18], cost: 249,
               model: "TPO-3-18", description: "Waste pull-out for a 600 mm base, three 18 L bins")
        return b.build()
    }

    /// Recycling centre for a drawer or sink base: a frame of up to four colour-coded bins, two across and two deep.
    static func recyclingSystem() -> ComponentDefinition {
        var b = ComponentBuilder("Recycling Bin System", .kitchen, "Waste & Recycling", "Drawer-mounted recycling set: two to four colour-coded bins, two across and up to two deep.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "recycling", "waste", "bin", "sorting", "drawer")
        b.aliases("recycling centre", "waste sorting system", "recycle bins drawer", "4-bin recycling", "600 mm", "800 mm", "24 in", "30 in")
        b.material("Frame Material", .greyPlastic)
        b.material("Bin 1 Material", .greyPlastic)
        b.material("Bin 2 Material", ComponentFinish("Plastic - Blue", .plastic, RGBColor(hex: 0x3F6FB5)))
        b.material("Bin 3 Material", ComponentFinish("Plastic - Green", .plastic, RGBColor(hex: 0x4E9A5B)))
        b.material("Bin 4 Material", ComponentFinish("Plastic - Yellow", .plastic, RGBColor(hex: 0xE2B53A)))
        b.openingParameters(width: CC.mm(528), depth: CC.mm(470), height: CC.mm(300))
        b.number("Bin Count", 4, group: .dimensions)
        b.length("Bin Height", CC.mm(260))
        b.length("Bin Width", 0, formula: "(Opening Width - 0.03 m) / 2")
        b.length("Bin Depth", 0, formula: "(Opening Depth - 0.03 m) / 2")
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.note("Place it in the drawer's bay; it sits in the drawer box."))
        b.requires(.fitsHeight("Bin Height + 0.02 m"))
        b.using("Frame Material")
        b.box("Base Frame", x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "0.008 m"))
        let cells: [(String, String)] = [("0.01 m", "0.01 m"), ("0.02 m + Bin Width", "0.01 m"), ("0.01 m", "0.02 m + Bin Depth"), ("0.02 m + Bin Width", "0.02 m + Bin Depth")]
        for (k, c) in cells.enumerated() {
            let v: String? = k < 2 ? nil : "Show Bin \(k + 1)"
            if let v { b.countFlag(v, "Bin Count >= \(k + 1)") }
            b.shown(v) { b in
                b.using("Bin \(k + 1) Material")
                let cx = "\(c.0) + Bin Width / 2", cy = "\(c.1) + Bin Depth / 2"
                b.blend("Bin \(k + 1)", bottom: ComponentKit.roundedRect(center: (cx, cy), width: "Bin Width * 0.9", height: "Bin Depth * 0.9", radius: "0.015 m"),
                        top: ComponentKit.roundedRect(center: (cx, cy), width: "Bin Width", height: "Bin Depth", radius: "0.018 m"), from: "0.008 m", to: "0.008 m + Bin Height")
                b.box("Bin \(k + 1) Handle", x: ("\(cx) - 0.04 m", "\(cx) + 0.04 m"), y: ("\(c.1) - 0.004 m", "\(c.1) + 0.006 m"), z: ("Bin Height - 0.02 m", "Bin Height"))
            }
        }
        b.using(nil)
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Opening Depth"), z: ("0 m", "Bin Height"))
        for (w, n, cost) in [(600.0, 2.0, 119.0), (600, 4, 169), (800, 4, 189)] {
            b.type("Recycling Bin System - \(Int(n)) Bin - \(Int(w)) mm", ["Opening Width": CC.mm(w - 36 - 36)], numbers: ["Bin Count": n], cost: cost, model: "RBS-\(Int(n))-\(Int(w))",
                   description: "\(Int(n))-bin recycling set for a \(Int(w)) mm drawer cabinet")
        }
        return b.build()
    }

    // MARK: Sink

    /// Tip-out tray behind a sink base's false front: a shallow tray on a pair of tilt hinges.
    static func sinkTipOutTray() -> ComponentDefinition {
        var b = ComponentBuilder("Sink Tip-Out Tray", .kitchen, "Sink", "Tip-out tray behind a sink base's false front, on spring tilt hinges.", frame: .face)
        b.tags("kitchen", "sink", "tip-out", "tray", "false front", "sponge")
        b.aliases("sink cabinet accessory", "tip out tray", "false front tray", "sink front tray", "11 in", "14 in", "28 in")
        b.material("Tray Material", .whitePlastic)
        b.material("Hinge Material", .stainless)
        b.length("Tray Length", CC.inch(14))
        b.length("Tray Height", CC.mm(70))
        b.length("Tray Depth", CC.mm(60))
        b.angle("Tilt Angle", 0, instance: true, group: .placement)
        b.host([.door, .drawerFront], faces: [.inside], align: .center)
        b.requires(.hostWidth(min: "Tray Length + 0.02 m", max: nil))
        b.requires(.hostHeight(min: "Tray Height + 0.02 m", max: nil))
        b.clearance(.box(name: "Tilt swing", x0: "-Tray Length / 2", x1: "Tray Length / 2", y0: "-Tray Height / 2", y1: "Tray Height / 2", z0: "0 m", z1: "Tray Depth + 0.06 m"))
        b.using("Tray Material")
        // Open at the top: floor at the bottom, walls against the front and toward the sink.
        b.box("Tray Floor", x: ("-Tray Length / 2", "Tray Length / 2"), y: ("-Tray Height / 2", "-Tray Height / 2 + 0.002 m"), z: ("0 m", "Tray Depth"))
        b.box("Tray Front", x: ("-Tray Length / 2", "Tray Length / 2"), y: ("-Tray Height / 2", "Tray Height / 2"), z: ("0 m", "0.002 m"))
        b.box("Tray Back", x: ("-Tray Length / 2", "Tray Length / 2"), y: ("-Tray Height / 2", "Tray Height / 4"), z: ("Tray Depth - 0.002 m", "Tray Depth"))
        for s in ["-", ""] {
            b.box("Tray End", x: ("\(s)(Tray Length / 2) - 0.001 m", "\(s)(Tray Length / 2) + 0.001 m"), y: ("-Tray Height / 2", "Tray Height / 4"), z: ("0 m", "Tray Depth"))
        }
        b.using("Hinge Material")
        for s in ["-", ""] {
            b.box("Tilt Hinge", x: ("\(s)(Tray Length / 2) - 0.012 m", "\(s)(Tray Length / 2) + 0.012 m"), y: ("-Tray Height / 2 - 0.02 m", "-Tray Height / 2"), z: ("0 m", "0.04 m"))
        }
        b.using(nil)
        b.drill("Tray screw", x: "-Tray Length / 4", y: "0 m", diameter: CX.mm(3), depth: CX.mm(10))
        b.drill("Tray screw", x: "Tray Length / 4", y: "0 m", diameter: CX.mm(3), depth: CX.mm(10))
        b.outlines(plan: .top, elevation: .face, x: ("-Tray Length / 2", "Tray Length / 2"), y: ("-Tray Height / 2", "Tray Height / 2"), z: ("0 m", "Tray Depth"))
        for (l, cost) in [(11.0, 18.0), (14, 21), (28, 39)] {
            b.type("Sink Tip-Out Tray - \(Int(l))\"", ["Tray Length": CC.inch(l)], cost: cost, model: "STO-\(Int(l))", description: "Tip-out tray, \(Int(l))\" long, with hinges")
        }
        return b.build()
    }

    /// An undermount or drop-in sink's cutout in the top, as a void: the cut size, corner radius and faucet hole.
    static func sinkCutout() -> ComponentDefinition {
        var b = ComponentBuilder("Sink Cutout", .kitchen, "Sink", "Sink cutout template for the countertop: cut size, corner radius and faucet hole (a void in the top).",
                                 frame: .plan)
        b.tags("kitchen", "sink", "cutout", "countertop", "template", "void")
        b.aliases("sink cut-out", "sink template", "undermount sink cutout", "drop-in sink cutout", "single bowl", "double bowl", "30 in", "33 in")
        b.material("Rim Material", .stainless)
        b.length("Cutout Width", CC.inch(28.5))
        b.length("Cutout Depth", CC.inch(16.5))
        b.length("Corner Radius", CC.inch(1))
        b.length("Bowl Depth", CC.inch(9))
        b.length("Faucet Hole Diameter", CC.mm(35))
        b.length("Faucet Setback", CC.inch(1.5))
        b.length("Host Thickness", CC.inch(1.5), instance: true, group: .placement)
        b.flag("Drop-In", false, instance: false, group: .data)
        b.flag("Undermount", false, formula: "not(Drop-In)")
        b.host([.top], faces: [.top], align: .center)
        b.requires(.hostWidth(min: "Cutout Width + 0.1 m", max: nil))
        b.requires(.note("Leave 2\" (50 mm) of top in front of the cutout and 3\" behind it for the faucet."))
        b.pocket("Sink cutout", width: "Cutout Width", height: "Cutout Depth", depth: "Host Thickness", through: true)
        b.drill("Faucet hole", x: "0 m", y: "Cutout Depth / 2 + Faucet Setback", diameter: "Faucet Hole Diameter", depth: "Host Thickness", through: true)
        // The cut itself (a void through the top) and the bowl below for clearance checks.
        b.extrusion("Host Cutout", profile: ComponentKit.roundedRect(width: "Cutout Width", height: "Cutout Depth", radius: "Corner Radius"), from: "-Host Thickness", to: "0 m", void: true)
        b.cyl("Faucet Hole Cutout", axis: .z, center: ("0 m", "Cutout Depth / 2 + Faucet Setback"), radius: "Faucet Hole Diameter / 2", from: "-Host Thickness", to: "0 m", void: true)
        b.shown("Undermount") { b in
            b.tray("Bowl", x: ("-Cutout Width / 2 - 0.01 m", "Cutout Width / 2 + 0.01 m"), y: ("-Cutout Depth / 2 - 0.01 m", "Cutout Depth / 2 + 0.01 m"),
                   z: ("-Host Thickness - Bowl Depth", "-Host Thickness"), wall: CX.mm(1.2), floor: CX.mm(1.2))
        }
        b.shown("Drop-In") { b in
            b.tray("Bowl", x: ("-Cutout Width / 2 + 0.002 m", "Cutout Width / 2 - 0.002 m"), y: ("-Cutout Depth / 2 + 0.002 m", "Cutout Depth / 2 - 0.002 m"),
                   z: ("-Bowl Depth", "0 m"), wall: CX.mm(1.2), floor: CX.mm(1.2))
            b.box("Rim Front", x: ("-Cutout Width / 2 - 0.02 m", "Cutout Width / 2 + 0.02 m"), y: ("-Cutout Depth / 2 - 0.02 m", "-Cutout Depth / 2 + 0.002 m"), z: ("0 m", "0.002 m"))
            b.box("Rim Back", x: ("-Cutout Width / 2 - 0.02 m", "Cutout Width / 2 + 0.02 m"), y: ("Cutout Depth / 2 - 0.002 m", "Cutout Depth / 2 + 0.02 m"), z: ("0 m", "0.002 m"))
        }
        b.symbol(.face, [.coarse, .medium, .fine], .rect(("-Cutout Width / 2", "-Cutout Depth / 2"), ("Cutout Width / 2", "Cutout Depth / 2")),
                 .circle(("0 m", "Cutout Depth / 2 + Faucet Setback"), "Faucet Hole Diameter / 2"))
        b.symbol(.face, [.medium, .fine], dashed: true, .line(("-Cutout Width / 2", "-Cutout Depth / 2"), ("Cutout Width / 2", "Cutout Depth / 2")),
                 .line(("-Cutout Width / 2", "Cutout Depth / 2"), ("Cutout Width / 2", "-Cutout Depth / 2")))
        b.symbol(.top, [.coarse], dashed: true, .rect(("-Cutout Width / 2", "-Host Thickness - Bowl Depth"), ("Cutout Width / 2", "0 m")))
        b.type("Sink Cutout - Single Bowl 30\" Base", ["Cutout Width": CC.inch(28.5), "Cutout Depth": CC.inch(16.5)], cost: 0, model: "SC-SB30", description: "Undermount single bowl, 30\" base")
        b.type("Sink Cutout - Single Bowl 33\" Base", ["Cutout Width": CC.inch(31.5), "Cutout Depth": CC.inch(17.5)], cost: 0, model: "SC-SB33", description: "Undermount single bowl, 33\" base")
        b.type("Sink Cutout - Double Bowl 36\" Base", ["Cutout Width": CC.inch(32.5), "Cutout Depth": CC.inch(18)], cost: 0, model: "SC-DB36", description: "Undermount double bowl, 36\" base")
        b.type("Sink Cutout - Drop-In 33\" Base", ["Cutout Width": CC.inch(32), "Cutout Depth": CC.inch(21), "Corner Radius": CC.inch(1.5)], flags: ["Drop-In": true], cost: 0,
               model: "SC-DI33", description: "Drop-in single bowl, 33\" base")
        return b.build()
    }

    // MARK: Lifts and worktops

    /// Appliance lift: a scissor-lift platform that raises a countertop appliance (or a TV) to worktop height.
    static func applianceLift() -> ComponentDefinition {
        var b = ComponentBuilder("Appliance Lift Mechanism", .kitchen, "Lifts & Worktops",
                                 "Scissor-lift platform that raises an appliance from inside the base to worktop height; electric or gas-spring assisted.", frame: .legacyOpening)
        b.tags("kitchen", "appliance", "lift", "scissor", "pop-up", "platform")
        b.aliases("appliance pop-up", "scissor lift platform", "pop up appliance lift", "tv lift", "electric lift", "600 mm", "24 in")
        b.material("Frame Material", .steel)
        b.material("Platform Material", ComponentFinish("Melamine - White", .generic, RGBColor(hex: 0xF2F1EE)))
        b.openingParameters(width: openingFor(600), depth: CC.mm(520), height: CC.mm(700))
        b.length("Platform Width", 0, formula: "Opening Width - 0.03 m")
        b.length("Platform Depth", CC.mm(450))
        b.length("Lowered Height", CC.mm(200))
        b.length("Lift Height", CC.mm(450))
        b.number("Load Capacity", 66, unit: "lb", group: .data)
        b.flag("Raised", false, group: .placement)
        b.length("Platform Z", 0, formula: "if(Raised, Lowered Height + Lift Height, Lowered Height)")
        b.host([.bay], faces: [.bottom], align: .center)
        b.requires(.fitsDepth("Platform Depth + 0.02 m"))
        b.requires(.fitsHeight("Lowered Height + 0.25 m"))
        b.electrical(watts: 60, volts: 24, supply: "AC 120 V to DC 24 V", cable: "6 ft cord to outlet in the cabinet", connector: "NEMA 5-15")
        b.using("Frame Material")
        let x0 = "(Opening Width - Platform Width) / 2", x1 = "(Opening Width + Platform Width) / 2"
        let y0 = "0.03 m", y1 = "0.03 m + Platform Depth"
        b.box("Base Frame", x: (x0, x1), y: (y0, y1), z: ("0 m", "0.03 m"))
        b.box("Motor Housing", x: ("Opening Width / 2 - 0.08 m", "Opening Width / 2 + 0.08 m"), y: (y1, "\(y1) + 0.04 m"), z: ("0.03 m", "0.12 m"))
        for (n, x) in [("Left", "\(x0) + 0.02 m"), ("Right", "\(x1) - 0.02 m")] {
            b.link("\(n) Scissor A", plane: .yz, ("\(y0) + 0.02 m", "0.03 m"), ("\(y1) - 0.02 m", "Platform Z - 0.02 m"), at: x, width: CX.mm(30), thickness: CX.mm(6))
            b.link("\(n) Scissor B", plane: .yz, ("\(y1) - 0.02 m", "0.03 m"), ("\(y0) + 0.02 m", "Platform Z - 0.02 m"), at: x, width: CX.mm(30), thickness: CX.mm(6))
        }
        b.box("Platform Frame", x: (x0, x1), y: (y0, y1), z: ("Platform Z - 0.03 m", "Platform Z - 0.018 m"))
        b.using("Platform Material")
        b.box("Platform", x: (x0, x1), y: (y0, y1), z: ("Platform Z - 0.018 m", "Platform Z"))
        b.using(nil)
        b.drill("Base screw", x: "\(x0) + 0.03 m", y: "0.08 m", diameter: CX.mm(5), depth: CX.mm(13))
        b.drill("Base screw", x: "\(x1) - 0.03 m", y: "0.08 m", diameter: CX.mm(5), depth: CX.mm(13))
        b.outlines(x: (x0, x1), y: (y0, y1), z: ("0 m", "Platform Z"))
        b.symbol(.top, [.medium, .fine], dashed: true, .rect((x0, "Lowered Height + Lift Height - 0.03 m"), (x1, "Lowered Height + Lift Height")))
        b.type("Appliance Lift Mechanism - 600 mm Electric", [:], cost: 649, model: "ALM-600E", description: "Electric scissor lift for a 600 mm base, 66 lb")
        b.type("Appliance Lift Mechanism - 900 mm Electric", ["Opening Width": openingFor(900)], numbers: ["Load Capacity": 88], cost: 789, model: "ALM-900E",
               description: "Electric scissor lift for a 900 mm base, 88 lb")
        return b.build()
    }

    /// Mixer lift: a pair of spring-assisted swing-up arms on the bay's sides carrying a shelf from inside the base up and
    /// out to worktop height.
    static func mixerLift() -> ComponentDefinition {
        var b = ComponentBuilder("Mixer Lift Mechanism", .kitchen, "Lifts & Worktops", "Spring-assisted swing-up arms that lift a stand mixer's shelf out of a base to worktop height.",
                                 frame: .legacyOpening)
        b.tags("kitchen", "mixer", "lift", "swing-up", "appliance", "spring")
        b.aliases("mixer lift", "swing up shelf", "appliance swing lift", "stand mixer lift", "15 in", "18 in", "24 in")
        b.material("Mechanism Material", .steel)
        b.material("Shelf Material", ComponentFinish("Melamine - White", .generic, RGBColor(hex: 0xF2F1EE)))
        b.openingParameters(width: CC.inch(15.5), depth: CC.mm(520), height: CC.mm(700), minWidth: CC.inch(14))
        b.length("Arm Length", CC.mm(400))
        b.length("Shelf Depth", CC.mm(400))
        b.length("Mechanism Thickness", CC.mm(13))
        b.angle("Lift Angle", 0, instance: true, group: .placement)
        b.number("Load Capacity", 60, unit: "lb", group: .data)
        b.length("Pivot Y", 0, formula: "Opening Depth - 0.15 m")
        b.length("Pivot Z", CC.mm(300))
        b.length("Shelf Y", 0, formula: "Pivot Y - Arm Length * cos(Lift Angle)")
        b.length("Shelf Z", 0, formula: "Pivot Z - 0.2 m + Arm Length * sin(Lift Angle)")
        b.host([.bay], faces: [.left, .right], align: .full, mirroredPair: true)
        b.requires(.hostWidth(min: "0.356 m", max: "0.61 m"))
        b.requires(.fitsDepth("Arm Length + 0.1 m"))
        b.clearance(.side("Mechanism Thickness"))
        b.using("Mechanism Material")
        for (n, x) in [("Left", "Mechanism Thickness / 2"), ("Right", "Opening Width - Mechanism Thickness / 2")] {
            b.link("\(n) Base Plate", plane: .yz, ("Pivot Y - 0.1 m", "Pivot Z - 0.05 m"), ("Pivot Y + 0.1 m", "Pivot Z - 0.05 m"), at: x, width: CX.mm(120), thickness: "Mechanism Thickness")
            b.link("\(n) Arm", plane: .yz, ("Pivot Y", "Pivot Z"), ("Shelf Y", "Shelf Z + 0.2 m"), at: x, width: CX.mm(35), thickness: CX.mm(5))
            b.link("\(n) Shelf Bracket", plane: .yz, ("Shelf Y", "Shelf Z + 0.2 m"), ("Shelf Y", "Shelf Z"), at: x, width: CX.mm(30), thickness: CX.mm(5))
            b.cyl("\(n) Spring Housing", axis: .x, center: ("Pivot Y + 0.05 m", "Pivot Z - 0.12 m"), radius: "0.02 m", from: "\(x) - Mechanism Thickness / 2", to: "\(x) + Mechanism Thickness / 2")
        }
        b.using("Shelf Material")
        b.box("Shelf", x: ("Mechanism Thickness", "Opening Width - Mechanism Thickness"), y: ("Shelf Y - Shelf Depth / 2", "Shelf Y + Shelf Depth / 2"), z: ("Shelf Z - 0.019 m", "Shelf Z"))
        b.using(nil)
        b.outlines(x: ("0 m", "Opening Width"), y: ("Pivot Y - Shelf Depth / 2", "Pivot Y + 0.1 m"), z: ("0 m", "Pivot Z + 0.1 m"))
        b.symbol(.side, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("Pivot Z", "Pivot Y"), radius: "Arm Length", startDegrees: "180", sweepDegrees: "-90"))
        b.type("Mixer Lift Mechanism - Standard", [:], cost: 129, model: "MXL-STD", description: "Mixer lift arms for 15–24\" bases, 60 lb")
        b.type("Mixer Lift Mechanism - Heavy Duty", ["Arm Length": CC.mm(430)], numbers: ["Load Capacity": 90], cost: 169, model: "MXL-HD", description: "Heavy-duty mixer lift arms, 90 lb")
        return b.build()
    }

    /// Pull-out worktop (bread board): a board on a pair of slides just under the top.
    static func pullOutWorktop() -> ComponentDefinition {
        var b = ComponentBuilder("Pull-Out Worktop", .kitchen, "Lifts & Worktops", "Pull-out cutting board or worktop on concealed slides under the countertop.", frame: .legacyOpening)
        b.tags("kitchen", "worktop", "pull-out", "cutting board", "bread board", "slide")
        b.aliases("bread board", "pull out cutting board", "slide out worktop", "pull-out table", "450 mm", "600 mm", "18 in", "24 in")
        b.material("Board Material", .maple)
        b.material("Slide Material", .steel)
        b.openingParameters(width: openingFor(600), depth: CC.mm(540), height: CC.mm(40))
        b.length("Board Thickness", CC.mm(19))
        b.length("Board Depth", CC.mm(480))
        b.length("Slide Length", CC.mm(450), group: .manufacturing)
        b.length("Pull Out", CC.mm(0), instance: true, group: .placement, min: 0)
        b.host([.bay], faces: [.top], align: .full)
        b.requires(.fitsDepth("Slide Length + 0.01 m"))
        b.requires(.fitsHeight("Board Thickness + 0.01 m"))
        b.clearance(.box(name: "Pull-out travel", x0: "0 m", x1: "Opening Width", y0: "-Slide Length", y1: "0 m", z0: "Opening Height - Board Thickness", z1: "Opening Height"))
        b.using("Slide Material")
        let bz = "Opening Height - Board Thickness - 0.003 m"
        b.sideRunners("Slide", width: "Opening Width", y: ("0 m", "Slide Length"), z: "\(bz) + Board Thickness / 2", height: CX.mm(17), thickness: CX.mm(12.7))
        b.using("Board Material")
        b.box("Board", x: ("0.013 m", "Opening Width - 0.013 m"), y: ("-Pull Out", "Board Depth - Pull Out"), z: (bz, "\(bz) + Board Thickness"))
        b.box("Pull Lip", x: ("0.013 m", "Opening Width - 0.013 m"), y: ("-Pull Out - 0.02 m", "-Pull Out"), z: ("\(bz) + Board Thickness - 0.012 m", "\(bz) + Board Thickness + 0.003 m"))
        b.using(nil)
        b.outlines(x: ("0 m", "Opening Width"), y: ("0 m", "Board Depth"), z: ("Opening Height - Board Thickness - 0.003 m", "Opening Height"))
        b.symbol(.face, [.medium, .fine], dashed: true, .rect(("0.013 m", "-Slide Length"), ("Opening Width - 0.013 m", "0 m")))
        for (w, cost) in [(450.0, 69.0), (600, 79)] {
            b.type("Pull-Out Worktop - \(Int(w)) mm", ["Opening Width": openingFor(w)], cost: cost, model: "POW-\(Int(w))", description: "Pull-out worktop for a \(Int(w)) mm cabinet")
        }
        return b.build()
    }

    /// Fold-down worktop: a hinged leaf on two locking fold-down brackets, on a wall, a side panel or a cabinet end.
    static func foldDownWorktop() -> ComponentDefinition {
        var b = ComponentBuilder("Fold-Down Worktop", .kitchen, "Lifts & Worktops", "Hinged fold-down worktop or breakfast leaf on two locking fold-down brackets.", frame: .face)
        b.tags("kitchen", "worktop", "fold-down", "drop leaf", "bracket", "breakfast bar")
        b.aliases("folding worktop", "drop-down table", "wall mounted folding table", "folding bracket table", "24 in", "30 in", "36 in")
        b.material("Top Material", .oak)
        b.material("Bracket Material", .matteBlack)
        b.length("Top Width", CC.inch(30))
        b.length("Top Depth", CC.inch(16))
        b.length("Host Thickness", CC.mm(25))
        b.length("Mount Height", CC.inch(36), instance: true, group: .placement)
        b.flag("Folded", false, group: .placement)
        b.flag("Open", false, formula: "not(Folded)")
        b.number("Load Capacity", 100, unit: "lb", group: .data)
        b.host([.sidePanel, .back, .wall], faces: [.outside, .front], align: .center)
        b.requires(.hostWidth(min: "Top Width", max: nil))
        b.clearance(.box(name: "Fold swing", x0: "-Top Width / 2", x1: "Top Width / 2", y0: "-Top Depth", y1: "0 m", z0: "0 m", z1: "Top Depth"))
        b.shown("Open") { b in
            b.using("Top Material")
            b.box("Top", x: ("-Top Width / 2", "Top Width / 2"), y: ("-Host Thickness", "0 m"), z: ("0 m", "Top Depth"))
            b.using("Bracket Material")
            for s in ["-", ""] {
                let x = "\(s)(Top Width / 2 - 0.08 m)"
                b.box("Bracket Plate", x: ("\(x) - 0.012 m", "\(x) + 0.012 m"), y: ("-0.3 m", "-Host Thickness"), z: ("0 m", "0.004 m"))
                b.box("Bracket Arm", x: ("\(x) - 0.012 m", "\(x) + 0.012 m"), y: ("-Host Thickness - 0.004 m", "-Host Thickness"), z: ("0 m", "Top Depth * 0.85"))
                b.link("Bracket Brace", plane: .yz, ("-0.28 m", "0.004 m"), ("-Host Thickness - 0.004 m", "Top Depth * 0.7"), at: x, width: CX.mm(16), thickness: CX.mm(20))
            }
        }
        b.shown("Folded") { b in
            b.using("Top Material")
            b.box("Top (Folded)", x: ("-Top Width / 2", "Top Width / 2"), y: ("-Top Depth", "0 m"), z: ("0.03 m", "0.03 m + Host Thickness"))
            b.using("Bracket Material")
            for s in ["-", ""] {
                let x = "\(s)(Top Width / 2 - 0.08 m)"
                b.box("Bracket (Folded)", x: ("\(x) - 0.012 m", "\(x) + 0.012 m"), y: ("-0.3 m", "0 m"), z: ("0 m", "0.03 m"))
            }
        }
        b.using(nil)
        for s in ["-", ""] {
            b.drill("Bracket screw", x: "\(s)(Top Width / 2 - 0.08 m)", y: "-0.05 m", diameter: CX.mm(5), depth: CX.mm(16))
            b.drill("Bracket screw", x: "\(s)(Top Width / 2 - 0.08 m)", y: "-0.25 m", diameter: CX.mm(5), depth: CX.mm(16))
        }
        b.symbol(.top, [.coarse], .rect(("-Top Width / 2", "0 m"), ("Top Width / 2", "Top Depth")))
        b.symbol(.top, [.medium, .fine], dashed: true, .arc(center: FamilyPoint("-Top Width / 2", "0 m"), radius: "Top Depth", startDegrees: "0", sweepDegrees: "90"))
        b.symbol(.face, [.coarse], .rect(("-Top Width / 2", "-0.3 m"), ("Top Width / 2", "0 m")))
        for (w, d, cost) in [(24.0, 12.0, 119.0), (30, 16, 149), (36, 20, 179)] {
            b.type("Fold-Down Worktop - \(Int(w))\" x \(Int(d))\"", ["Top Width": CC.inch(w), "Top Depth": CC.inch(d)], cost: cost, model: "FDW-\(Int(w))\(Int(d))",
                   description: "Fold-down worktop \(Int(w))\" x \(Int(d))\" with locking brackets")
        }
        return b.build()
    }

    // MARK: Door and shelf accessories

    /// Door-mounted rack: shallow shelves with retaining rails on a door's inside face.
    static func doorOrganizer() -> ComponentDefinition {
        var b = ComponentBuilder("Cabinet Door Organizer", .kitchen, "Racks & Holders", "Door-mounted rack: shallow shelves with retaining rails on the inside of a door.", frame: .face)
        b.tags("kitchen", "door", "rack", "organizer", "spice", "inside door")
        b.aliases("door rack", "door mounted spice rack", "door storage", "back of door organizer", "12 in", "15 in", "18 in")
        b.material("Finish Material", .chrome)
        b.material("Shelf Material", .whitePlastic)
        b.length("Rack Width", CC.inch(12))
        b.length("Rack Height", CC.mm(500))
        b.length("Shelf Depth", CC.mm(75))
        b.number("Shelf Count", 3, group: .dimensions)
        b.host([.door], faces: [.inside], align: .center)
        b.requires(.hostWidth(min: "Rack Width + 0.075 m", max: nil))
        b.requires(.note("Check the shelves inside the cabinet clear the rack (Shelf Depth + 25 mm)."))
        b.clearance(.box(name: "Rack space", x0: "-Rack Width / 2", x1: "Rack Width / 2", y0: "-Rack Height / 2", y1: "Rack Height / 2", z0: "0 m", z1: "Shelf Depth + 0.025 m"))
        for s in ["-", ""] {
            b.box("Upright", x: ("\(s)(Rack Width / 2) - 0.004 m", "\(s)(Rack Width / 2) + 0.004 m"), y: ("-Rack Height / 2", "Rack Height / 2"), z: ("0 m", "Shelf Depth"))
        }
        for k in 1...4 {
            let v: String? = k <= 2 ? nil : "Show Shelf \(k)"
            if let v { b.countFlag(v, "Shelf Count >= \(k)") }
            let y = "-Rack Height / 2 + 0.01 m + (Rack Height - 0.1 m) * \(k - 1) / max(1, Shelf Count - 1)"
            b.shown(v) { b in
                b.using("Shelf Material")
                b.box("Shelf \(k)", x: ("-Rack Width / 2", "Rack Width / 2"), y: (y, "\(y) + 0.004 m"), z: ("0 m", "Shelf Depth"))
                b.using("Finish Material")
                b.rodX("Rail \(k)", y: "\(y) + 0.05 m", z: "Shelf Depth - 0.003 m", d: CX.mm(5), from: "-Rack Width / 2", to: "Rack Width / 2")
            }
        }
        b.using(nil)
        for y in ["-Rack Height / 2 + 0.02 m", "Rack Height / 2 - 0.02 m"] {
            for s in ["-", ""] { b.drill("Rack screw", x: "\(s)(Rack Width / 2)", y: y, diameter: CX.mm(3), depth: CX.mm(10)) }
        }
        b.outlines(plan: .top, elevation: .face, x: ("-Rack Width / 2", "Rack Width / 2"), y: ("-Rack Height / 2", "Rack Height / 2"), z: ("0 m", "Shelf Depth"))
        for (w, cost) in [(12.0, 39.0), (15, 45), (18, 49)] {
            b.type("Cabinet Door Organizer - \(Int(w))\"", ["Rack Width": CC.inch(w)], cost: cost, model: "CDO-\(Int(w))", description: "Door rack \(Int(w))\" wide, for \(Int(w + 3))\" doors")
        }
        return b.build()
    }

    /// Wine rack insert: rows of scalloped bottle rails filling the bay, at a bottle pitch.
    static func wineRack() -> ComponentDefinition {
        var b = ComponentBuilder("Wine Rack Insert", .kitchen, "Racks & Holders", "Bottle rack insert: scalloped rails hold bottles on their side, rows to fill the bay.", frame: .legacyOpening)
        b.tags("kitchen", "wine", "bottle", "rack", "insert", "cubby")
        b.aliases("wine rack", "bottle rack", "wine storage insert", "bottle rail rack", "12 bottle", "16 bottle", "300 mm", "450 mm")
        b.material("Rail Material", .oak)
        b.openingParameters(width: openingFor(300), depth: CC.mm(300), height: CC.mm(700))
        b.length("Bottle Pitch", CC.mm(95))
        b.length("Row Pitch", CC.mm(105))
        b.length("Rail Thickness", CC.mm(19))
        b.number("Rows", 6, group: .dimensions)
        b.number("Bottles", 0, group: .data)
        b.host([.bay], faces: [.bottom], align: .full)
        b.requires(.fitsDepth("0.28 m"))
        for k in 1...8 {
            let v: String? = k == 1 ? nil : "Show Row \(k)"
            if let v { b.countFlag(v, "Rows >= \(k)") }
            let z = "0.02 m + Row Pitch * \(k - 1)"
            b.shown(v) { b in
                for (n, y) in [("Front", "0.04 m"), ("Back", "Opening Depth - 0.06 m")] {
                    b.box("Row \(k) \(n) Rail", x: ("0 m", "Opening Width"), y: (y, "\(y) + Rail Thickness"), z: (z, "\(z) + 0.035 m"))
                }
            }
        }
        b.box("Left Side", x: ("0 m", "0.006 m"), y: ("0.04 m", "Opening Depth - 0.04 m"), z: ("0 m", "0.02 m + Row Pitch * (Rows - 1) + 0.035 m"))
        b.box("Right Side", x: ("Opening Width - 0.006 m", "Opening Width"), y: ("0.04 m", "Opening Depth - 0.04 m"), z: ("0 m", "0.02 m + Row Pitch * (Rows - 1) + 0.035 m"))
        b.outlines(x: ("0 m", "Opening Width"), y: ("0.04 m", "Opening Depth - 0.04 m"), z: ("0 m", "Row Pitch * Rows"))
        b.symbol(.top, [.medium, .fine], .circle(("Opening Width / 2", "0.02 m + Row Pitch * 0.6"), "0.038 m"))
        for (w, rows, cost) in [(300.0, 6.0, 79.0), (450, 6, 99), (600, 7, 129)] {
            b.type("Wine Rack Insert - \(Int(w)) mm", ["Opening Width": openingFor(w)], numbers: ["Rows": rows, "Bottles": rows * (w / 100).rounded(.down)], cost: cost,
                   model: "WRI-\(Int(w))", description: "Wine rack insert for a \(Int(w)) mm cabinet, \(Int(rows)) rows")
        }
        return b.build()
    }

    /// Stemware rack: T-rails screwed under a shelf or the top, along the depth.
    static func glassHolder() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Holder", .kitchen, "Racks & Holders", "Stemware rack: T-rails under a shelf or wall cabinet bottom hold glasses by their foot.", frame: .plan)
        b.tags("kitchen", "glass", "stemware", "wine glass", "rack", "under shelf")
        b.aliases("stemware rack", "wine glass holder", "under cabinet glass rack", "glass rail", "11 in", "14 in", "17 in")
        b.material("Finish Material", .chrome)
        b.length("Rail Length", CC.inch(11))
        b.number("Rail Count", 4, group: .dimensions)
        b.length("Rail Spacing", CC.inch(4))
        b.length("Rail Drop", CC.mm(16))
        b.host([.shelf, .bottom, .top], faces: [.bottom], align: .center)
        b.requires(.fitsDepth("Rail Length"))
        for k in 1...5 {
            let v: String? = k <= 2 ? nil : "Show Rail \(k)"
            if let v { b.countFlag(v, "Rail Count >= \(k)") }
            let x = "-Rail Spacing * (Rail Count - 1) / 2 + Rail Spacing * \(k - 1)"
            b.shown(v) { b in
                b.box("Rail \(k) Web", x: ("\(x) - 0.002 m", "\(x) + 0.002 m"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("-Rail Drop", "0 m"))
                b.box("Rail \(k) Flange", x: ("\(x) - 0.012 m", "\(x) + 0.012 m"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("-Rail Drop - 0.002 m", "-Rail Drop"))
                b.box("Rail \(k) Base", x: ("\(x) - 0.008 m", "\(x) + 0.008 m"), y: ("-Rail Length / 2", "Rail Length / 2"), z: ("-0.002 m", "0 m"))
            }
        }
        b.drill("Rail screw", x: "0 m", y: "-Rail Length / 2 + 0.02 m", diameter: CX.mm(3), depth: CX.mm(10))
        b.drill("Rail screw", x: "0 m", y: "Rail Length / 2 - 0.02 m", diameter: CX.mm(3), depth: CX.mm(10))
        b.outlines(x: ("-Rail Spacing * (Rail Count - 1) / 2 - 0.012 m", "Rail Spacing * (Rail Count - 1) / 2 + 0.012 m"), y: ("-Rail Length / 2", "Rail Length / 2"),
                   z: ("-Rail Drop - 0.002 m", "0 m"))
        for (l, n, cost) in [(11.0, 3.0, 22.0), (14, 4, 29), (17, 4, 34)] {
            b.type("Glass Holder - \(Int(l))\" \(Int(n)) Rails", ["Rail Length": CC.inch(l)], numbers: ["Rail Count": n], cost: cost, model: "GH-\(Int(l))\(Int(n))",
                   description: "Stemware rack, \(Int(n)) rails \(Int(l))\" long")
        }
        return b.build()
    }

    /// Screw-in cup hook under a shelf or wall cabinet.
    static func mugHook() -> ComponentDefinition {
        var b = ComponentBuilder("Mug Hook", .kitchen, "Racks & Holders", "Screw-in cup hook under a shelf or wall cabinet.", frame: .plan)
        b.tags("kitchen", "mug", "cup", "hook", "under shelf")
        b.aliases("cup hook", "screw hook", "mug hanger", "1 in", "1 1/2 in", "2 in")
        b.material("Finish Material", .brass)
        b.length("Hook Length", CC.inch(1.5))
        b.length("Wire Diameter", CC.mm(3.5))
        b.length("Thread Length", CC.mm(10))
        b.host([.shelf, .bottom, .top, .rail], faces: [.bottom], align: .center)
        b.requires(.hostThickness(min: "Thread Length + 0.003 m", max: nil))
        b.rodZ("Thread", x: "0 m", y: "0 m", d: "Wire Diameter", from: "0 m", to: "Thread Length")
        b.cyl("Collar", axis: .z, center: ("0 m", "0 m"), radius: "Wire Diameter * 1.4", from: "-0.002 m", to: "0 m")
        b.wire("Hook", plane: .yz, [("0 m", "-0.002 m"), ("0 m", "-Hook Length * 0.7"), ("Hook Length * 0.15", "-Hook Length"), ("Hook Length * 0.4", "-Hook Length * 0.85"),
                                     ("Hook Length * 0.45", "-Hook Length * 0.55")], at: "0 m", d: "Wire Diameter")
        b.drill("Pilot hole", x: "0 m", y: "0 m", diameter: CX.mm(2), depth: "Thread Length")
        b.symbol(.face, [.coarse, .medium, .fine], .circle(("0 m", "0 m"), "Wire Diameter"))
        b.symbol(.top, [.coarse], .line(("0 m", "0 m"), ("0 m", "-Hook Length")))
        for (l, cost) in [(1.0, 0.6), (1.5, 0.8), (2, 1.1)] {
            b.type("Mug Hook - \(FurnitureSizeText.inches(CC.inch(l)))", ["Hook Length": CC.inch(l)], cost: cost, model: "MH-\(Int(l * 10))", description: "Cup hook \(FurnitureSizeText.inches(CC.inch(l)))")
        }
        return b.build()
    }

    /// Towel rail: one to three bars on end posts, on a door's inside face or a side panel (or a pull-out towel bar).
    static func towelRail() -> ComponentDefinition {
        var b = ComponentBuilder("Towel Rail", .kitchen, "Racks & Holders", "Towel rail with one to three bars on end posts, for a door's inside or a cabinet end.", frame: .face)
        b.tags("kitchen", "towel", "rail", "bar", "tea towel", "door")
        b.aliases("towel bar", "tea towel rail", "dish towel holder", "towel rack", "12 in", "14 in", "18 in")
        b.material("Finish Material", .stainless)
        b.length("Rail Length", CC.inch(14))
        b.length("Projection", CC.mm(60))
        b.length("Bar Diameter", CC.mm(10))
        b.number("Bar Count", 2, group: .dimensions)
        b.length("Bar Spacing", CC.mm(35))
        b.host([.door, .sidePanel], faces: [.inside, .outside], align: .center)
        b.requires(.hostWidth(min: "Rail Length + 0.02 m", max: nil))
        for s in ["-", ""] {
            b.box("End Post", x: ("\(s)(Rail Length / 2) - 0.008 m", "\(s)(Rail Length / 2) + 0.008 m"), y: ("-0.015 m", "Bar Spacing * (Bar Count - 1) + 0.015 m"), z: ("0 m", "Projection"))
        }
        for k in 1...3 {
            let v: String? = k == 1 ? nil : "Show Bar \(k)"
            if let v { b.countFlag(v, "Bar Count >= \(k)") }
            b.shown(v) { $0.rodX("Bar \(k)", y: "Bar Spacing * \(k - 1)", z: "Projection - Bar Diameter / 2 - 0.004 m", d: "Bar Diameter", from: "-Rail Length / 2", to: "Rail Length / 2") }
        }
        for s in ["-", ""] { b.drill("Post screw", x: "\(s)(Rail Length / 2)", y: "0 m", diameter: CX.mm(3), depth: CX.mm(10)) }
        b.outlines(plan: .top, elevation: .face, x: ("-Rail Length / 2", "Rail Length / 2"), y: ("-0.015 m", "Bar Spacing * (Bar Count - 1) + 0.015 m"), z: ("0 m", "Projection"))
        for (l, n, cost) in [(12.0, 1.0, 14.0), (14, 2, 19), (18, 3, 27)] {
            b.type("Towel Rail - \(Int(l))\" \(Int(n)) Bar", ["Rail Length": CC.inch(l)], numbers: ["Bar Count": n], cost: cost, model: "TR-\(Int(l))\(Int(n))",
                   description: "Towel rail \(Int(l))\", \(Int(n)) bar\(n > 1 ? "s" : "")")
        }
        return b.build()
    }

    /// Paper towel holder under a wall cabinet: two arms and the roll.
    static func paperTowelHolder() -> ComponentDefinition {
        var b = ComponentBuilder("Paper Towel Holder", .kitchen, "Racks & Holders", "Under-cabinet paper towel holder: two arms and a spindle, shown with a roll.", frame: .plan)
        b.tags("kitchen", "paper towel", "kitchen roll", "holder", "under cabinet")
        b.aliases("kitchen roll holder", "under cabinet paper towel holder", "paper towel rack", "11 in roll", "280 mm")
        b.material("Finish Material", .stainless)
        b.material("Roll Material", ComponentFinish("Paper - White", .generic, RGBColor(hex: 0xF7F6F2)))
        b.length("Roll Length", CC.inch(11))
        b.length("Roll Diameter", CC.mm(130))
        b.length("Drop", CC.mm(85))
        b.flag("Show Roll", true, group: .constraints)
        b.host([.bottom, .shelf, .top], faces: [.bottom], align: .center)
        b.requires(.hostWidth(min: "Roll Length + 0.04 m", max: nil))
        for s in ["-", ""] {
            let x = "\(s)(Roll Length / 2 + 0.008 m)"
            b.box("Mount Plate", x: ("\(x) - 0.01 m", "\(x) + 0.01 m"), y: ("-0.03 m", "0.03 m"), z: ("-0.003 m", "0 m"))
            b.box("Arm", x: ("\(x) - 0.003 m", "\(x) + 0.003 m"), y: ("-0.012 m", "0.012 m"), z: ("-Drop - 0.012 m", "-0.003 m"))
        }
        b.rodX("Spindle", y: "0 m", z: "-Drop", d: CX.mm(16), from: "-Roll Length / 2 - 0.005 m", to: "Roll Length / 2 + 0.005 m")
        b.using("Roll Material")
        b.shown("Show Roll") { $0.cyl("Roll", axis: .x, center: ("0 m", "-Drop"), radius: "Roll Diameter / 2", from: "-Roll Length / 2", to: "Roll Length / 2", segments: 40) }
        b.using(nil)
        for s in ["-", ""] { b.drill("Plate screw", x: "\(s)(Roll Length / 2 + 0.008 m)", y: "0 m", diameter: CX.mm(3), depth: CX.mm(10)) }
        b.outlines(x: ("-Roll Length / 2 - 0.02 m", "Roll Length / 2 + 0.02 m"), y: ("-Roll Diameter / 2", "Roll Diameter / 2"), z: ("-Drop - Roll Diameter / 2", "0 m"))
        b.type("Paper Towel Holder - 11\" Roll", [:], cost: 24, model: "PTH-11", description: "Under-cabinet holder for 11\" rolls")
        b.type("Paper Towel Holder - 12\" Roll", ["Roll Length": CC.inch(12), "Roll Diameter": CC.mm(150), "Drop": CC.mm(95)], cost: 26, model: "PTH-12",
               description: "Under-cabinet holder for 12\" jumbo rolls")
        return b.build()
    }
}
