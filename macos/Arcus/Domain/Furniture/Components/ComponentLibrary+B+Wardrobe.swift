import Foundation
import ArcusGeometry

// COMPB: 09 Wardrobe & Closet Accessories. Most sit inside a wardrobe bay on the opening frame (origin at the bay's
// bottom-left-front corner, X across "Opening Width", Y into "Opening Depth", Z up; "Mount Height" above the bay's
// bottom): rods and rails run between the sides on end supports, pull-outs ride on slides fixed to a side or the top.
// Door items (mirrors, hooks) are face-based on the door's inside face. Lights carry electrical data (geometry only).

extension ComponentLibrary {
    static var groupBWardrobe: [ComponentDefinition] {
        [hangingRod(), ovalRail(), roundRail(), wardrobeLift(), trouserRack(), tieRack(), beltRack(), scarfRack(), shoeRack(), pullOutShoeShelf(),
         shoeDrawer(), jewelryTray(), watchTray(), wardrobeDivider(), pullOutBasket(), wireBasket(), laundryHamper(), foldingLaundryBasket(),
         wardrobeMirror(), slidingMirror(), wardrobeLight(), ledHangingRail(), valetRod(), wardrobeHook(), bagRack(), hatRack(), storageTower(),
         cornerWardrobe(), wardrobeCarousel(), wardrobeSafe()]
    }

    /// A bay item: opening frame, hosted in a bay between its sides (full width).
    static func bayBuilder(_ name: String, _ sub: String, _ description: String, _ finish: ComponentFinish, mount: Double = ComponentKit.inch(66),
                           depth: Double = ComponentKit.inch(22), width: Double = ComponentKit.inch(30)) -> ComponentBuilder {
        var b = ComponentBuilder(name, .wardrobe, sub, description, frame: .legacyOpening)
        b.material("Finish Material", finish)
        openingParams(&b, width: width, depth: depth, mount: mount)
        b.host([.bay], faces: [.inside], align: .full)
        return b
    }

    /// The two end supports (flanges or cups) a rod or rail sits in, screwed to the sides, centred at (y, z).
    static func endSupports(_ b: inout ComponentBuilder, y: String, z: String, size: String, thickness: String = CX.mm(3), round: Bool = true) {
        for (n, x) in [("Left", (CX.zero, thickness)), ("Right", ("Opening Width - (\(thickness))", "Opening Width"))] {
            if round { b.rod("\(n) Support", axis: .x, c: (y, z), r: "(\(size)) / 2", from: x.0, to: x.1) }
            else { b.box("\(n) Support", x: x, y: ("\(y) - (\(size)) / 2", "\(y) + (\(size)) / 2"), z: ("\(z) - (\(size)) * 0.7", "\(z) + (\(size)) * 0.3")) }
        }
        b.drill("Rod support screw", x: y, y: "\(z) + (\(size)) * 0.3", diameter: CX.mm(3.5), depth: CX.mm(13))
        b.drill("Rod support screw", x: y, y: "\(z) + (\(size)) * 0.3", diameter: CX.mm(3.5), depth: CX.mm(13), target: .counterpart)
    }

    /// Plan and side symbols of a rod at (y, z) across the bay.
    static func rodSymbols(_ b: inout ComponentBuilder, y: String, z: String, r: String) {
        b.symLine(.face, CBL.all, (CX.zero, y), ("Opening Width", y))
        b.symRect(.face, CBL.mediumFine, (CX.zero, "\(y) - (\(r))"), ("Opening Width", "\(y) + (\(r))"))
        b.symCircle(.side, CBL.all, c: (z, y), r: r)
    }

    /// A slide fixed under the bay's top (or on a side) carrying a pull-out, `length` long: its body and the screws.
    static func topSlide(_ b: inout ComponentBuilder, x: String, length: String, z: String, width: String = CX.mm(30)) {
        b.slot("Slide Material") { b in
            b.box("Slide", x: ("\(x) - (\(width)) / 2", "\(x) + (\(width)) / 2"), y: (CX.mm(20), "0.02 m + \(length)"), z: ("\(z) - 0.022 m", z))
        }
        for f in ["0.15", "0.85"] {
            b.drill("Slide screw", x: x, y: "0.02 m + (\(length)) * \(f)", diameter: CX.mm(4), depth: CX.mm(12))
        }
    }

    // MARK: Rods and rails

    static func hangingRod() -> ComponentDefinition {
        var b = bayBuilder("Clothes Hanging Rod", "Hanging Rods", "Round closet rod between the sides on flange sockets; cut to the bay's width.", .chrome)
        b.tags("closet rod", "hanging rod", "clothes rod", "round", "1 5/16\"", "wardrobe", "pole")
        b.aliases("closet pole", "clothes pole", "hanging bar", "garment rod", "wardrobe rod", "closet bar")
        b.length("Rod Diameter", ComponentKit.inch(1.3125))
        b.length("Flange Diameter", ComponentKit.inch(2.5))
        b.length("Rod Setback", ComponentKit.inch(11), instance: true, group: .placement)
        b.length("Wall Thickness", ComponentKit.inch(0.05))
        b.flag("Wood Rod", false, instance: false)
        b.flag("Metal Rod", true, formula: "not(Wood Rod)")
        b.material("Rod Material", .chrome)
        let y = "Rod Setback", z = "Mount Height"
        b.slot("Rod Material") { b in
            b.shown(by: "Metal Rod") { b in
                b.pipe("Rod", axis: .x, c: (y, z), outer: "Rod Diameter / 2", inner: "Rod Diameter / 2 - Wall Thickness", from: CX.mm(6), to: "Opening Width - 0.006 m")
            }
            b.shown(by: "Wood Rod") { b in b.rod("Rod", axis: .x, c: (y, z), r: "Rod Diameter / 2", from: CX.mm(6), to: "Opening Width - 0.006 m") }
        }
        endSupports(&b, y: y, z: z, size: "Flange Diameter", thickness: CX.mm(6))
        rodSymbols(&b, y: y, z: z, r: "Rod Diameter / 2")
        b.requires(.fitsWidth(CX.inch(6)))
        b.clearance(.box(name: "Hanger space", x0: CX.zero, x1: "Opening Width", y0: "Rod Setback - 0.25 m", y1: "Rod Setback + 0.25 m", z0: "Mount Height - 1 m", z1: "Mount Height + 0.05 m"))
        b.type("Closet Rod - 1 1/16\" Steel", ["Rod Diameter": ComponentKit.inch(1.0625), "Flange Diameter": ComponentKit.inch(2)], flags: ["Wood Rod": false], cost: 9.00, model: "CR-106S")
        b.type("Closet Rod - 1 5/16\" Steel", [:], flags: ["Wood Rod": false], cost: 12.00, model: "CR-131S", isDefault: true)
        b.type("Closet Rod - 1 5/16\" Wood", [:], flags: ["Wood Rod": true], cost: 14.00, model: "CR-131W")
        return b.build()
    }

    static func ovalRail() -> ComponentDefinition {
        var b = bayBuilder("Oval Wardrobe Rail", "Hanging Rods", "Oval wardrobe tube (30 x 15 mm) on two end supports; a centre support for wide bays.", .chrome)
        b.tags("wardrobe rail", "oval", "30 x 15", "30x15", "hanging rail", "tube", "closet")
        b.aliases("oval closet rod", "oval tube", "wardrobe tube", "hanging bar oval", "robe rail")
        b.length("Rail Width", ComponentKit.mm(30))
        b.length("Rail Height", ComponentKit.mm(15))
        b.length("Rail Setback", ComponentKit.inch(11), instance: true, group: .placement)
        b.flag("Center Support", false, instance: false)
        b.number("Load Rating", 66, unit: "lb", group: .data)
        let y = "Rail Setback", z = "Mount Height"
        b.ovalRod("Rail", axis: .x, c: (y, z), ru: "Rail Width / 2", rv: "Rail Height / 2", from: CX.mm(3), to: "Opening Width - 0.003 m")
        b.slot("Support Material") { b in
            for (n, x) in [("Left Support", (CX.zero, CX.mm(3))), ("Right Support", ("Opening Width - 0.003 m", "Opening Width"))] {
                b.box(n, x: x, y: ("\(y) - Rail Width * 0.7", "\(y) + Rail Width * 0.7"), z: ("\(z) - Rail Height", "\(z) + Rail Height * 1.4"))
            }
            b.shown(by: "Center Support") { b in
                b.box("Center Hanger", x: ("Opening Width / 2 - 0.006 m", "Opening Width / 2 + 0.006 m"), y: ("\(y) - 0.004 m", "\(y) + 0.004 m"), z: (z, "\(z) + 0.08 m"))
            }
        }
        b.material("Support Material", .greyPlastic)
        rodSymbols(&b, y: y, z: z, r: "Rail Width / 2")
        b.drill("Rail support screw", x: y, y: "\(z) + Rail Height", diameter: CX.mm(3.5), depth: CX.mm(13))
        b.drill("Rail support screw", x: y, y: "\(z) + Rail Height", diameter: CX.mm(3.5), depth: CX.mm(13), target: .counterpart)
        b.type("Oval Rail - 30 x 15 mm", [:], flags: ["Center Support": false], cost: 8.00, model: "OWR-3015", isDefault: true)
        b.type("Oval Rail - 30 x 15 mm with Center Support", [:], flags: ["Center Support": true], numbers: ["Load Rating": 110], cost: 11.00, model: "OWR-3015C")
        b.type("Oval Rail - 30 x 15 mm Black", [:], flags: ["Center Support": false], cost: 9.00, model: "OWR-3015K")
        return b.build()
    }

    static func roundRail() -> ComponentDefinition {
        var b = bayBuilder("Round Wardrobe Rail", "Hanging Rods", "Round steel wardrobe tube (19, 25 or 32 mm) in end sockets.", .chrome)
        b.tags("wardrobe rail", "round", "25 mm", "19 mm", "32 mm", "tube", "socket", "closet")
        b.aliases("round closet rail", "wardrobe tube round", "rail tube", "hanging tube", "rod 25 mm")
        b.length("Tube Diameter", ComponentKit.mm(25))
        b.length("Socket Diameter", ComponentKit.mm(40))
        b.length("Rail Setback", ComponentKit.inch(11), instance: true, group: .placement)
        let y = "Rail Setback", z = "Mount Height"
        b.pipe("Tube", axis: .x, c: (y, z), outer: "Tube Diameter / 2", inner: "Tube Diameter / 2 - 0.001 m", from: CX.mm(8), to: "Opening Width - 0.008 m")
        b.slot("Socket Material") { b in
            for (n, x) in [("Left Socket", (CX.zero, CX.mm(10))), ("Right Socket", ("Opening Width - 0.01 m", "Opening Width"))] {
                b.rod(n, axis: .x, c: (y, z), r: "Socket Diameter / 2", from: x.0, to: x.1)
            }
        }
        b.material("Socket Material", .chrome)
        rodSymbols(&b, y: y, z: z, r: "Tube Diameter / 2")
        b.drill("Socket screw", x: y, y: "\(z) + Socket Diameter * 0.3", diameter: CX.mm(3.5), depth: CX.mm(13))
        b.drill("Socket screw", x: y, y: "\(z) + Socket Diameter * 0.3", diameter: CX.mm(3.5), depth: CX.mm(13), target: .counterpart)
        b.type("Round Rail - 19 mm", ["Tube Diameter": ComponentKit.mm(19), "Socket Diameter": ComponentKit.mm(32)], cost: 7.00, model: "RWR-19")
        b.type("Round Rail - 25 mm", [:], cost: 8.50, model: "RWR-25", isDefault: true)
        b.type("Round Rail - 32 mm", ["Tube Diameter": ComponentKit.mm(32), "Socket Diameter": ComponentKit.mm(48)], cost: 11.00, model: "RWR-32")
        return b.build()
    }

    static func wardrobeLift() -> ComponentDefinition {
        var b = bayBuilder("Pull-Down Wardrobe Lift", "Wardrobe Lifts", "Pull-down wardrobe lift: a hanging rail on two gas-sprung arms from the sides; pull the handle to lower it.", .aluminum,
                           mount: ComponentKit.inch(84))
        b.tags("wardrobe lift", "pull-down", "closet lift", "gas spring", "high rail", "accessible")
        b.aliases("pull down closet rod", "wardrobe pull down rail", "drop down rail", "closet lift", "lift rail", "reachable rail")
        b.material("Rail Material", .chrome)
        b.length("Arm Length", ComponentKit.inch(30))
        b.length("Rail Diameter", ComponentKit.mm(25))
        b.length("Housing Height", ComponentKit.inch(6))
        b.length("Housing Depth", ComponentKit.inch(3))
        b.length("Minimum Width", ComponentKit.mm(830))
        b.length("Maximum Width", ComponentKit.mm(1150))
        b.number("Load Rating", 26, unit: "lb", group: .data)
        b.flag("Lowered", false, instance: true)
        b.flag("Raised", true, formula: "not(Lowered)")
        b.requires(.hostWidth(min: "Minimum Width", max: "Maximum Width"))
        let pivot = ("Opening Depth - 0.06 m", "Mount Height")
        for (n, x) in [("Left", (CX.zero, CX.mm(20))), ("Right", ("Opening Width - 0.02 m", "Opening Width"))] {
            b.box("\(n) Housing", x: x, y: ("\(pivot.0) - Housing Depth / 2", "\(pivot.0) + Housing Depth / 2"), z: ("Mount Height - Housing Height / 2", "Mount Height + Housing Height / 2"))
            b.shown(by: "Raised") { b in
                b.box("\(n) Arm", x: ("\(x.0) + 0.004 m", "\(x.1) - 0.004 m"), y: ("\(pivot.0) - Arm Length", pivot.0), z: ("Mount Height - 0.012 m", "Mount Height + 0.012 m"))
            }
            b.shown(by: "Lowered") { b in
                b.box("\(n) Arm", x: ("\(x.0) + 0.004 m", "\(x.1) - 0.004 m"), y: ("\(pivot.0) - 0.012 m", "\(pivot.0) + 0.012 m"), z: ("Mount Height - Arm Length", "Mount Height"))
            }
        }
        b.slot("Rail Material") { b in
            b.shown(by: "Raised") { b in
                b.rod("Rail", axis: .x, c: ("\(pivot.0) - Arm Length", "Mount Height"), r: "Rail Diameter / 2", from: CX.mm(20), to: "Opening Width - 0.02 m")
                b.rod("Handle", axis: .z, c: ("Opening Width / 2", "\(pivot.0) - Arm Length - 0.02 m"), r: CX.mm(8), from: "Mount Height - 0.2 m", to: "Mount Height")
            }
            b.shown(by: "Lowered") { b in
                b.rod("Rail", axis: .x, c: (pivot.0, "Mount Height - Arm Length"), r: "Rail Diameter / 2", from: CX.mm(20), to: "Opening Width - 0.02 m")
            }
        }
        b.symRect(.face, CBL.all, (CX.zero, "\(pivot.0) - Arm Length"), ("Opening Width", "\(pivot.0) + Housing Depth / 2"))
        b.symLine(.face, CBL.coarse, (CX.zero, "\(pivot.0) - Arm Length"), ("Opening Width", "\(pivot.0) - Arm Length"))
        b.symbol(.side, CBL.mediumFine, dashed: true, .arc(center: FamilyPoint("Mount Height", pivot.0), radius: "Arm Length", startDegrees: "180", sweepDegrees: "90"))
        b.symRect(.side, CBL.coarse, ("Mount Height - Housing Height / 2", "\(pivot.0) - Housing Depth / 2"), ("Mount Height + Housing Height / 2", "\(pivot.0) + Housing Depth / 2"))
        for x in ["0 m", "Opening Width"] {
            for dz in ["-0.05 m", "0.05 m"] { b.drill("Lift housing screw", x: pivot.0, y: "Mount Height + \(dz)", diameter: CX.mm(4), depth: CX.mm(13), target: x == "0 m" ? .host : .counterpart) }
        }
        b.type("Wardrobe Lift - 830-1150 mm", [:], cost: 85.00, model: "WL-8301150", isDefault: true)
        b.type("Wardrobe Lift - 600-830 mm", ["Minimum Width": ComponentKit.mm(600), "Maximum Width": ComponentKit.mm(830), "Opening Width": ComponentKit.inch(28)], cost: 78.00, model: "WL-600830")
        b.type("Wardrobe Lift - 1150-1500 mm Heavy", ["Minimum Width": ComponentKit.mm(1150), "Maximum Width": ComponentKit.mm(1500), "Opening Width": ComponentKit.inch(48)],
               numbers: ["Load Rating": 33], cost: 110.00, model: "WL-11501500")
        return b.build()
    }

    // MARK: Pull-out racks

    /// A pull-out rack hung from a top slide at the side of the bay: the slide, a frame and `body` for its bars or hooks.
    static func pullOutRack(_ name: String, _ sub: String, _ description: String, depth: Double, _ body: (inout ComponentBuilder) -> Void) -> ComponentBuilder {
        var b = bayBuilder(name, sub, description, .aluminum, mount: ComponentKit.inch(72), width: ComponentKit.inch(18))
        b.material("Slide Material", .zinc)
        b.length("Rack Depth", depth)
        b.length("Rack Width", ComponentKit.inch(4))
        b.length("Rack Height", ComponentKit.inch(4))
        b.flag("Extended", false, instance: true)
        b.length("Rack Offset", 0, formula: "if(Extended, -Rack Depth * 0.9, 0 m)")
        topSlide(&b, x: "Rack Width / 2 + 0.01 m", length: "Rack Depth", z: "Mount Height")
        body(&b)
        b.symRect(.face, CBL.all, (CX.mm(10), CX.mm(20)), ("Rack Width + 0.01 m", "0.02 m + Rack Depth"))
        b.symLine(.face, CBL.coarse, (CX.mm(10), CX.mm(20)), ("Rack Width + 0.01 m", "0.02 m + Rack Depth"))
        b.symRect(.side, CBL.coarse, ("Mount Height - Rack Height", CX.mm(20)), ("Mount Height", "0.02 m + Rack Depth"))
        b.symRect(.face, CBL.mediumFine, (CX.mm(10), "0.02 m - Rack Depth * 0.9"), ("Rack Width + 0.01 m", "0.02 m + Rack Depth * 0.1"), dashed: true)
        b.requires(.fitsDepth("Rack Depth + 0.03 m"))
        return b
    }

    static func trouserRack() -> ComponentDefinition {
        var b = pullOutRack("Pull-Out Trouser Rack", "Pull-Out Racks", "Pull-out trouser rack: a frame of bars on a side slide; trousers hang folded over each bar.", depth: ComponentKit.inch(18)) { b in
            b.integer("Bar Count", 8)
            b.length("Bar Diameter", ComponentKit.mm(10))
            b.length("Frame Width", ComponentKit.inch(14))
            let y0 = "0.02 m + Rack Offset", z = "Mount Height - 0.03 m"
            b.box("Front Rail", x: (CX.mm(10), "0.01 m + Frame Width"), y: (y0, "\(y0) + 0.015 m"), z: ("\(z) - 0.01 m", z))
            b.box("Back Rail", x: (CX.mm(10), "0.01 m + Frame Width"), y: ("\(y0) + Rack Depth - 0.015 m", "\(y0) + Rack Depth"), z: ("\(z) - 0.01 m", z))
            for k in 0..<10 {
                let x = "0.02 m + (Frame Width - 0.02 m) * \(LX.num(Double(k) / 9))"
                let add: (inout ComponentBuilder) -> Void = { b in b.rod("Bar \(k + 1)", axis: .y, c: (x, "\(z) - 0.005 m"), r: "Bar Diameter / 2", from: y0, to: "\(y0) + Rack Depth", sides: 16) }
                if k >= 8 { b.shown(by: "Ten Bars", add) } else { add(&b) }
            }
            b.flag("Ten Bars", false, formula: "Bar Count > 9")
        }
        b.tags("trouser rack", "pants rack", "pull-out", "bars", "closet", "450 mm")
        b.aliases("pants rack", "pull out trouser hanger", "slack rack", "trouser hanger", "pants organizer")
        b.type("Trouser Rack - 8 Bar 450 mm", [:], numbers: ["Bar Count": 8], cost: 45.00, model: "TR-8450", isDefault: true)
        b.type("Trouser Rack - 10 Bar 500 mm", ["Rack Depth": ComponentKit.mm(500), "Frame Width": ComponentKit.inch(17)], numbers: ["Bar Count": 10], cost: 55.00, model: "TR-10500")
        return b.build()
    }

    /// Hooks along a pull-out rack's bar: `n` hooks (`flag` shows the extra ones), J-shaped.
    static func hooks(_ b: inout ComponentBuilder, n: Int, extraFlag: String?, extraFrom: Int, spacing: String, z: String, drop: String, wire: String) {
        for k in 0..<n {
            let y = "0.02 m + Rack Offset + \(spacing) * \(LX.num(Double(k) + 0.5))"
            let add: (inout ComponentBuilder) -> Void = { b in
                b.rod("Hook \(k + 1) Stem", axis: .z, c: ("Rack Width / 2 + 0.01 m", y), r: wire, from: "\(z) - \(drop)", to: z, sides: 10)
                b.rod("Hook \(k + 1) Tip", axis: .x, c: (y, "\(z) - \(drop)"), r: wire, from: "Rack Width / 2 + 0.01 m - 0.02 m", to: "Rack Width / 2 + 0.01 m + 0.02 m", sides: 10)
            }
            if let extraFlag, k >= extraFrom { b.shown(by: extraFlag, add) } else { add(&b) }
        }
    }

    static func tieRack() -> ComponentDefinition {
        var b = pullOutRack("Pull-Out Tie Rack", "Pull-Out Racks", "Pull-out tie rack: a slide-out bar with short pegs on both sides for ties.", depth: ComponentKit.inch(14)) { b in
            b.integer("Peg Count", 12)
            b.length("Peg Length", ComponentKit.inch(1.5))
            let y0 = "0.02 m + Rack Offset", z = "Mount Height - 0.03 m", x = "Rack Width / 2 + 0.01 m"
            b.box("Bar", x: ("\(x) - 0.006 m", "\(x) + 0.006 m"), y: (y0, "\(y0) + Rack Depth"), z: ("\(z) - 0.02 m", z))
            for k in 0..<16 {
                let y = "\(y0) + Rack Depth * \(LX.num((Double(k / 2) + 0.5) / 8))"
                let side = k % 2 == 0 ? ("\(x) - 0.006 m - Peg Length", "\(x) - 0.006 m") : ("\(x) + 0.006 m", "\(x) + 0.006 m + Peg Length")
                let add: (inout ComponentBuilder) -> Void = { b in b.rod("Peg \(k + 1)", axis: .x, c: (y, "\(z) - 0.01 m"), r: CX.mm(3), from: side.0, to: side.1, sides: 10) }
                if k >= 12 { b.shown(by: "Sixteen Pegs", add) } else { add(&b) }
            }
            b.flag("Sixteen Pegs", false, formula: "Peg Count > 12")
        }
        b.tags("tie rack", "pull-out", "pegs", "ties", "closet", "accessories")
        b.aliases("tie organizer", "pull out tie hanger", "tie holder", "necktie rack")
        b.type("Tie Rack - 12 Peg 350 mm", [:], numbers: ["Peg Count": 12], cost: 28.00, model: "TIE-12", isDefault: true)
        b.type("Tie Rack - 16 Peg 450 mm", ["Rack Depth": ComponentKit.mm(450)], numbers: ["Peg Count": 16], cost: 34.00, model: "TIE-16")
        return b.build()
    }

    static func beltRack() -> ComponentDefinition {
        var b = pullOutRack("Belt Organizer", "Pull-Out Racks", "Pull-out belt rack: J hooks under a slide-out bar, one belt on each.", depth: ComponentKit.inch(14)) { b in
            b.integer("Hook Count", 8)
            b.length("Hook Drop", ComponentKit.inch(2))
            let y0 = "0.02 m + Rack Offset", z = "Mount Height - 0.03 m", x = "Rack Width / 2 + 0.01 m"
            b.box("Bar", x: ("\(x) - 0.008 m", "\(x) + 0.008 m"), y: (y0, "\(y0) + Rack Depth"), z: ("\(z) - 0.012 m", z))
            hooks(&b, n: 10, extraFlag: "Ten Hooks", extraFrom: 8, spacing: "Rack Depth / 10", z: "\(z) - 0.012 m", drop: "Hook Drop", wire: CX.mm(2.5))
            b.flag("Ten Hooks", false, formula: "Hook Count > 8")
        }
        b.tags("belt rack", "belt organizer", "pull-out", "hooks", "closet")
        b.aliases("belt hanger", "belt holder", "pull out belt rack", "belt rail")
        b.type("Belt Rack - 8 Hook 350 mm", [:], numbers: ["Hook Count": 8], cost: 26.00, model: "BLT-8", isDefault: true)
        b.type("Belt Rack - 10 Hook 450 mm", ["Rack Depth": ComponentKit.mm(450)], numbers: ["Hook Count": 10], cost: 31.00, model: "BLT-10")
        return b.build()
    }

    static func scarfRack() -> ComponentDefinition {
        var b = pullOutRack("Scarf Organizer", "Pull-Out Racks", "Pull-out scarf rack: rings under a slide-out bar, a scarf pulled through each.", depth: ComponentKit.inch(14)) { b in
            b.integer("Ring Count", 6)
            b.length("Ring Diameter", ComponentKit.inch(2))
            let y0 = "0.02 m + Rack Offset", z = "Mount Height - 0.03 m", x = "Rack Width / 2 + 0.01 m"
            b.box("Bar", x: ("\(x) - 0.008 m", "\(x) + 0.008 m"), y: (y0, "\(y0) + Rack Depth"), z: ("\(z) - 0.012 m", z))
            for k in 0..<8 {
                let y = "\(y0) + Rack Depth * \(LX.num((Double(k) + 0.5) / 8))"
                let add: (inout ComponentBuilder) -> Void = { b in
                    b.pipe("Ring \(k + 1)", axis: .x, c: (y, "\(z) - 0.012 m - Ring Diameter / 2"), outer: "Ring Diameter / 2", inner: "Ring Diameter / 2 - 0.004 m",
                           from: "\(x) - 0.003 m", to: "\(x) + 0.003 m")
                }
                if k >= 6 { b.shown(by: "Eight Rings", add) } else { add(&b) }
            }
            b.flag("Eight Rings", false, formula: "Ring Count > 6")
        }
        b.type("Scarf Rack - 6 Ring", [:], numbers: ["Ring Count": 6], cost: 27.00, model: "SCF-6", isDefault: true)
        b.type("Scarf Rack - 8 Ring", ["Rack Depth": ComponentKit.mm(450)], numbers: ["Ring Count": 8], cost: 32.00, model: "SCF-8")
        var d = b.build()
        d.tags = ["scarf rack", "scarf organizer", "rings", "pull-out", "closet"]
        d.aliases = ["scarf holder", "scarf hanger", "ring rack", "shawl organizer"]
        return d
    }

    static func bagRack() -> ComponentDefinition {
        var b = pullOutRack("Bag Organizer", "Pull-Out Racks", "Pull-out bag rack: big hooks under a slide-out bar for handbags and totes.", depth: ComponentKit.inch(18)) { b in
            b.integer("Hook Count", 4)
            b.length("Hook Drop", ComponentKit.inch(3))
            let y0 = "0.02 m + Rack Offset", z = "Mount Height - 0.03 m", x = "Rack Width / 2 + 0.01 m"
            b.box("Bar", x: ("\(x) - 0.01 m", "\(x) + 0.01 m"), y: (y0, "\(y0) + Rack Depth"), z: ("\(z) - 0.02 m", z))
            hooks(&b, n: 6, extraFlag: "Six Hooks", extraFrom: 4, spacing: "Rack Depth / 6", z: "\(z) - 0.02 m", drop: "Hook Drop", wire: CX.mm(4))
            b.flag("Six Hooks", false, formula: "Hook Count > 4")
        }
        b.type("Bag Rack - 4 Hook", [:], numbers: ["Hook Count": 4], cost: 32.00, model: "BAG-4", isDefault: true)
        b.type("Bag Rack - 6 Hook", ["Rack Depth": ComponentKit.inch(22)], numbers: ["Hook Count": 6], cost: 38.00, model: "BAG-6")
        var d = b.build()
        d.tags = ["bag rack", "bag organizer", "handbag", "purse", "hooks", "pull-out"]
        d.aliases = ["purse organizer", "handbag hanger", "bag holder", "tote rack"]
        return d
    }

    static func valetRod() -> ComponentDefinition {
        var b = ComponentBuilder("Valet Rod", .wardrobe, "Valet Rods", "Valet rod: a telescoping bar mounted on a side or under a shelf; pull it out to hang tomorrow's outfit.")
        b.tags("valet rod", "valet", "telescoping", "pull-out", "closet", "hanger bar")
        b.aliases("valet bar", "pull-out valet", "closet valet", "extending hook", "telescopic valet")
        b.material("Finish Material", .chrome)
        b.length("Closed Length", ComponentKit.inch(12))
        b.length("Extension", ComponentKit.inch(10))
        b.length("Body Diameter", ComponentKit.inch(0.75))
        b.flag("Extended", false, instance: true)
        b.host([.sidePanel, .divider, .shelf], faces: [.inside, .bottom], align: .top)
        // On the face: the body along X from the front edge back, the bar sliding out toward -X.
        b.box("Mounting Plate", x: ("Closed Length * 0.2", "Closed Length"), y: ("-Body Diameter / 2 - 0.004 m", "Body Diameter / 2 + 0.004 m"), z: (CX.zero, CX.mm(3)))
        b.rod("Body", axis: .x, c: (CX.zero, "Body Diameter / 2 + 0.003 m"), r: "Body Diameter / 2", from: CX.zero, to: "Closed Length")
        b.rod("Bar", axis: .x, c: (CX.zero, "Body Diameter / 2 + 0.003 m"), r: "Body Diameter / 2 - 0.002 m", from: "-if(Extended, Extension, 0.01 m)", to: CX.zero)
        b.rod("Hook", axis: .z, c: ("-if(Extended, Extension, 0.01 m)", CX.zero), r: CX.mm(3), from: "Body Diameter / 2 + 0.003 m", to: "Body Diameter + 0.02 m", sides: 12)
        b.symRect(.face, CBL.all, (CX.zero, "-Body Diameter / 2"), ("Closed Length", "Body Diameter / 2"))
        b.symRect(.top, CBL.all, (CX.zero, CX.zero), ("Closed Length", "Body Diameter + 0.003 m"))
        b.symLine(.top, CBL.mediumFine, ("-Extension", "Body Diameter / 2"), (CX.zero, "Body Diameter / 2"), dashed: true)
        for x in ["Closed Length * 0.35", "Closed Length * 0.85"] { b.drill("Valet screw", x: x, y: CX.zero, diameter: CX.mm(3.5), depth: CX.mm(13)) }
        b.type("Valet Rod - 12\"", [:], cost: 14.00, model: "VR-12", isDefault: true)
        b.type("Valet Rod - 14\"", ["Closed Length": ComponentKit.inch(14), "Extension": ComponentKit.inch(12)], cost: 16.00, model: "VR-14")
        return b.build()
    }

    // MARK: Shoes

    static func shoeRack() -> ComponentDefinition {
        var b = bayBuilder("Shoe Rack", "Shoe Storage", "Fixed shoe rack: pairs of bars sloping to the front, toes on the high bar, heels hooked on the low bar.", .chrome,
                           mount: ComponentKit.inch(4), depth: ComponentKit.inch(14))
        b.tags("shoe rack", "shoe bars", "slanted", "closet", "shoes", "fixed")
        b.aliases("shoe shelf", "shoe holder", "slanted shoe rack", "shoe bar", "shoe organizer")
        b.length("Bar Diameter", ComponentKit.mm(12))
        b.length("Rise", ComponentKit.inch(4))
        b.length("Tier Spacing", ComponentKit.inch(8))
        b.flag("Two Tiers", false, instance: false)
        for t in 0..<2 {
            let z = "Mount Height + Tier Spacing * \(t)"
            let add: (inout ComponentBuilder) -> Void = { b in
                b.rod("Front Bar \(t + 1)", axis: .x, c: (CX.inch(2), z), r: "Bar Diameter / 2", from: CX.zero, to: "Opening Width", sides: 16)
                b.rod("Back Bar \(t + 1)", axis: .x, c: ("Opening Depth - 0.04 m", "\(z) + Rise"), r: "Bar Diameter / 2", from: CX.zero, to: "Opening Width", sides: 16)
            }
            if t == 1 { b.shown(by: "Two Tiers", add) } else { add(&b) }
        }
        for t in 0..<2 {
            let z = "Mount Height + Tier Spacing * \(t)"
            let add: (inout ComponentBuilder) -> Void = { b in
                for (n, x) in [("Left", (CX.zero, CX.mm(3))), ("Right", ("Opening Width - 0.003 m", "Opening Width"))] {
                    b.extrusion("\(n) Bracket \(t + 1)", profile: ComponentKit.points([(CX.inch(1), "\(z) - 0.015 m"), ("Opening Depth - 0.02 m", "\(z) + Rise - 0.015 m"),
                                                                                 ("Opening Depth - 0.02 m", "\(z) + Rise + 0.015 m"), (CX.inch(1), "\(z) + 0.015 m")]),
                                plane: .yz, from: x.0, to: x.1)
                }
            }
            if t == 1 { b.shown(by: "Two Tiers", add) } else { add(&b) }
        }
        b.symLine(.face, CBL.all, (CX.zero, CX.inch(2)), ("Opening Width", CX.inch(2)))
        b.symLine(.face, CBL.all, (CX.zero, "Opening Depth - 0.04 m"), ("Opening Width", "Opening Depth - 0.04 m"))
        b.symLine(.side, CBL.all, ("Mount Height", CX.inch(2)), ("Mount Height + Rise", "Opening Depth - 0.04 m"))
        for y in [CX.inch(2), "Opening Depth - 0.04 m"] {
            b.drill("Shoe rack screw", x: y, y: "Mount Height", diameter: CX.mm(3.5), depth: CX.mm(13))
            b.drill("Shoe rack screw", x: y, y: "Mount Height", diameter: CX.mm(3.5), depth: CX.mm(13), target: .counterpart)
        }
        b.type("Shoe Rack - 1 Tier", [:], flags: ["Two Tiers": false], cost: 18.00, model: "SHR-1", isDefault: true)
        b.type("Shoe Rack - 2 Tier", [:], flags: ["Two Tiers": true], cost: 30.00, model: "SHR-2")
        return b.build()
    }

    static func pullOutShoeShelf() -> ComponentDefinition {
        var b = bayBuilder("Pull-Out Shoe Shelf", "Shoe Storage", "Pull-out shoe shelf: a shelf tilted down to the front with a heel fence, on full-extension slides.", .whitePlastic,
                           mount: ComponentKit.inch(6))
        b.tags("shoe shelf", "pull-out", "slanted", "heel fence", "closet", "shoes")
        b.aliases("pull out shoe rack", "slide out shoe shelf", "angled shoe shelf", "shoe tray")
        b.material("Slide Material", .zinc)
        b.length("Slide Length", ComponentKit.mm(450))
        b.length("Tilt Rise", ComponentKit.inch(2.5))
        b.length("Shelf Thickness", ComponentKit.inch(0.625))
        b.length("Fence Height", ComponentKit.inch(1.25))
        let z0 = "Mount Height"
        slidePair(&b, length: "Slide Length", z: (z0, "\(z0) + 0.035 m"))
        b.extrusion("Shelf", profile: ComponentKit.points([(CX.mm(3), "\(z0) + 0.035 m"), ("0.003 m + Slide Length", "\(z0) + 0.035 m + Tilt Rise"),
                                                          ("0.003 m + Slide Length", "\(z0) + 0.035 m + Tilt Rise + Shelf Thickness"), (CX.mm(3), "\(z0) + 0.035 m + Shelf Thickness")]),
                    plane: .yz, from: CX.mm(13), to: "Opening Width - 0.013 m")
        b.box("Heel Fence", x: (CX.mm(13), "Opening Width - 0.013 m"), y: (CX.mm(3), CX.mm(15)), z: ("\(z0) + 0.035 m", "\(z0) + 0.035 m + Shelf Thickness + Fence Height"))
        bayItemSymbols(&b, x: (CX.mm(13), "Opening Width - 0.013 m"), y: (CX.mm(3), "0.003 m + Slide Length"), z: (z0, "\(z0) + 0.035 m + Tilt Rise"))
        slideScrews(&b, z: "\(z0) + 0.018 m")
        b.requires(.fitsDepth("Slide Length + 0.0127 m"))
        b.type("Shoe Shelf - 450 mm", [:], cost: 42.00, model: "PSS-450", isDefault: true)
        b.type("Shoe Shelf - 500 mm", ["Slide Length": ComponentKit.mm(500)], cost: 46.00, model: "PSS-500")
        return b.build()
    }

    static func shoeDrawer() -> ComponentDefinition {
        var b = bayBuilder("Shoe Drawer", "Shoe Storage", "Shoe drawer: a deep drawer box on slides with a removable divider rail, shoes stored heel to toe.", .maple,
                           mount: ComponentKit.inch(1))
        b.tags("shoe drawer", "drawer", "shoes", "closet", "pull-out", "bottom drawer")
        b.aliases("shoe storage drawer", "boot drawer", "shoe box drawer", "closet shoe drawer")
        b.material("Slide Material", .zinc)
        b.length("Slide Length", ComponentKit.mm(500))
        b.length("Box Height", ComponentKit.inch(7))
        b.length("Side Thickness", ComponentKit.inch(0.5))
        b.flag("Divider Rail", true, instance: false)
        let x0 = "0.0127 m + 0.0002 m", x1 = "Opening Width - 0.0127 m - 0.0002 m", y = (CX.mm(3), "0.003 m + Slide Length"), z0 = "Mount Height"
        slidePair(&b, length: "Slide Length", z: ("\(z0) + 0.02 m", "\(z0) + 0.065 m"))
        b.box("Box Bottom", x: (x0, x1), y: y, z: (z0, "\(z0) + 0.012 m"))
        b.box("Box Front", x: (x0, x1), y: (CX.mm(3), "0.003 m + Side Thickness"), z: (z0, "\(z0) + Box Height"))
        b.box("Box Back", x: (x0, x1), y: ("0.003 m + Slide Length - Side Thickness", "0.003 m + Slide Length"), z: (z0, "\(z0) + Box Height"))
        b.box("Box Left", x: (x0, "\(x0) + Side Thickness"), y: y, z: (z0, "\(z0) + Box Height"))
        b.box("Box Right", x: ("\(x1) - Side Thickness", x1), y: y, z: (z0, "\(z0) + Box Height"))
        b.shown(by: "Divider Rail") { b in
            b.rod("Divider Rail", axis: .x, c: ("0.003 m + Slide Length / 2", "\(z0) + Box Height * 0.6"), r: CX.mm(6), from: x0, to: x1, sides: 16)
        }
        bayItemSymbols(&b, x: (x0, x1), y: y, z: (z0, "\(z0) + Box Height"))
        slideScrews(&b, z: "\(z0) + 0.042 m")
        b.requires(.fitsDepth("Slide Length + 0.0127 m"))
        b.type("Shoe Drawer - 500 mm", [:], flags: ["Divider Rail": true], cost: 58.00, model: "SDR-500", isDefault: true)
        b.type("Shoe Drawer - 450 mm Boot", ["Slide Length": ComponentKit.mm(450), "Box Height": ComponentKit.inch(12)], flags: ["Divider Rail": false], cost: 64.00, model: "SDR-450B")
        return b.build()
    }

    // MARK: Trays and inserts

    /// A tray with a grid of compartments inside a drawer: outer walls and `cols` × `rows` dividers (flags show extras).
    static func compartmentTray(_ b: inout ComponentBuilder, cols: Int, rows: Int) {
        let w = ("Tray Inset", "Opening Width - Tray Inset"), d = ("Tray Inset", "Opening Depth - Tray Inset"), z0 = "Mount Height", t = "Wall Thickness"
        b.box("Tray Base", x: w, y: d, z: (z0, "\(z0) + \(t)"))
        b.box("Front Wall", x: w, y: (d.0, "\(d.0) + \(t)"), z: (z0, "\(z0) + Tray Height"))
        b.box("Back Wall", x: w, y: ("\(d.1) - \(t)", d.1), z: (z0, "\(z0) + Tray Height"))
        b.box("Left Wall", x: (w.0, "\(w.0) + \(t)"), y: d, z: (z0, "\(z0) + Tray Height"))
        b.box("Right Wall", x: ("\(w.1) - \(t)", w.1), y: d, z: (z0, "\(z0) + Tray Height"))
        for k in 1..<cols {
            let x = "Tray Inset + (Opening Width - 2 * Tray Inset) * \(LX.num(Double(k) / Double(cols)))"
            b.box("Divider X \(k)", x: ("\(x) - \(t) / 2", "\(x) + \(t) / 2"), y: d, z: (z0, "\(z0) + Tray Height * 0.85"))
        }
        for k in 1..<rows {
            let y = "Tray Inset + (Opening Depth - 2 * Tray Inset) * \(LX.num(Double(k) / Double(rows)))"
            b.box("Divider Y \(k)", x: w, y: ("\(y) - \(t) / 2", "\(y) + \(t) / 2"), z: (z0, "\(z0) + Tray Height * 0.85"))
        }
        b.symRect(.face, CBL.all, (w.0, d.0), (w.1, d.1))
        b.symRect(.side, CBL.coarse, (z0, d.0), ("\(z0) + Tray Height", d.1))
    }

    static func trayBuilder(_ name: String, _ description: String) -> ComponentBuilder {
        var b = bayBuilder(name, "Trays and Inserts", description, .fabric, mount: ComponentKit.inch(0.5), depth: ComponentKit.inch(18), width: ComponentKit.inch(20))
        b.host([.bay, .shelf], faces: [.inside, .top], align: .full)
        b.length("Tray Height", ComponentKit.inch(2))
        b.length("Tray Inset", ComponentKit.inch(0.25))
        b.length("Wall Thickness", ComponentKit.inch(0.25))
        return b
    }

    static func jewelryTray() -> ComponentDefinition {
        var b = trayBuilder("Jewelry Tray", "Jewelry tray insert: a velvet-lined tray with a grid of compartments for a drawer or a shelf.")
        b.tags("jewelry tray", "jewellery", "insert", "drawer insert", "compartments", "velvet")
        b.aliases("jewellery tray", "jewelry organizer", "ring tray", "drawer jewelry insert", "accessory tray")
        b.flag("Ring Rolls", false, instance: false)
        compartmentTray(&b, cols: 4, rows: 2)
        b.shown(by: "Ring Rolls") { b in
            for k in 0..<5 {
                let y = "Tray Inset + (Opening Depth - 2 * Tray Inset) * \(LX.num(0.55 + 0.08 * Double(k)))"
                b.rod("Ring Roll \(k + 1)", axis: .x, c: (y, "Mount Height + Wall Thickness + 0.008 m"), r: CX.mm(8), from: "Tray Inset + Wall Thickness",
                      to: "Opening Width / 4", sides: 16)
            }
        }
        b.type("Jewelry Tray - 8 Compartment", [:], flags: ["Ring Rolls": false], cost: 24.00, model: "JT-8", isDefault: true)
        b.type("Jewelry Tray - Ring Rolls", [:], flags: ["Ring Rolls": true], cost: 28.00, model: "JT-RR")
        return b.build()
    }

    static func watchTray() -> ComponentDefinition {
        var b = trayBuilder("Watch Organizer", "Watch tray insert: a lined tray of cushions (pillows) that hold a watch each.")
        b.tags("watch tray", "watch organizer", "watch box", "pillows", "drawer insert", "cushion")
        b.aliases("watch holder", "watch drawer insert", "watch cushion tray", "watch display tray")
        b.integer("Watch Count", 6)
        b.material("Pillow Material", .leather)
        compartmentTray(&b, cols: 3, rows: 1)
        b.slot("Pillow Material") { b in
            for k in 0..<6 {
                let x = "Tray Inset + (Opening Width - 2 * Tray Inset) * \(LX.num((Double(k % 3) + 0.5) / 3))"
                let y = "Tray Inset + (Opening Depth - 2 * Tray Inset) * \(LX.num(k < 3 ? 0.3 : 0.7))"
                b.ovalRod("Pillow \(k + 1)", axis: .x, c: (y, "Mount Height + Tray Height * 0.55"), ru: "(Opening Depth - 2 * Tray Inset) * 0.15", rv: "Tray Height * 0.35",
                          from: "\(x) - (Opening Width - 2 * Tray Inset) * 0.14", to: "\(x) + (Opening Width - 2 * Tray Inset) * 0.14")
            }
        }
        b.type("Watch Tray - 6 Watch", [:], numbers: ["Watch Count": 6], cost: 32.00, model: "WT-6", isDefault: true)
        b.type("Watch Tray - 6 Watch Deep", ["Tray Height": ComponentKit.inch(3)], numbers: ["Watch Count": 6], cost: 36.00, model: "WT-6D")
        return b.build()
    }

    static func wardrobeDivider() -> ComponentDefinition {
        var b = bayBuilder("Wardrobe Divider", "Dividers", "Wardrobe divider: a thin vertical partition fixed between a shelf and the bottom, splitting a hanging bay.", .whiteMelamine,
                           mount: 0)
        b.tags("wardrobe divider", "closet divider", "partition", "upright", "separator")
        b.aliases("closet partition", "wardrobe partition", "section divider", "hanging divider", "vertical divider")
        b.material("Bracket Material", .zinc)
        b.length("Divider Height", ComponentKit.inch(40))
        b.length("Panel Thickness", ComponentKit.inch(0.5))
        b.length("Front Setback", ComponentKit.inch(1))
        b.length("Divider Position", ComponentKit.inch(15), instance: true, group: .placement)
        let x = ("Divider Position - Panel Thickness / 2", "Divider Position + Panel Thickness / 2")
        b.box("Panel", x: x, y: ("Front Setback", "Opening Depth"), z: ("Mount Height", "Mount Height + Divider Height"))
        b.slot("Bracket Material") { b in
            for (n, z) in [("Bottom", "Mount Height"), ("Top", "Mount Height + Divider Height - 0.02 m")] {
                for (k, y) in ["Opening Depth * 0.25", "Opening Depth * 0.75"].enumerated() {
                    b.box("\(n) Bracket \(k + 1)", x: ("\(x.0) - 0.002 m", "\(x.1) + 0.02 m"), y: ("\(y) - 0.01 m", "\(y) + 0.01 m"), z: (z, "\(z) + 0.02 m"))
                }
            }
        }
        b.symRect(.face, CBL.all, (x.0, "Front Setback"), (x.1, "Opening Depth"))
        b.symRect(.side, CBL.coarse, ("Mount Height", "Front Setback"), ("Mount Height + Divider Height", "Opening Depth"))
        for y in ["Opening Depth * 0.25", "Opening Depth * 0.75"] { b.drill("Divider bracket screw", x: "Divider Position", y: y, diameter: CX.mm(3.5), depth: CX.mm(13)) }
        b.type("Wardrobe Divider - 40\"", [:], cost: 22.00, model: "WD-40", isDefault: true)
        b.type("Wardrobe Divider - 60\"", ["Divider Height": ComponentKit.inch(60)], cost: 30.00, model: "WD-60")
        return b.build()
    }

    // MARK: Baskets and hampers

    /// A wire basket body (base grid and side wires) from z0 up `height`, between x and y ranges.
    static func wireBody(_ b: inout ComponentBuilder, x: (String, String), y: (String, String), z0: String, height: String, wire: String = CX.mm(3)) {
        let r = "\(wire) / 2"
        for (n, yy) in [("Front Rim", y.0), ("Back Rim", y.1)] { b.rod(n, axis: .x, c: (yy, "\(z0) + \(height)"), r: wire, from: x.0, to: x.1, sides: 10) }
        for (n, xx) in [("Left Rim", x.0), ("Right Rim", x.1)] { b.rod(n, axis: .y, c: (xx, "\(z0) + \(height)"), r: wire, from: y.0, to: y.1, sides: 10) }
        for k in 0..<7 {
            let xx = "\(x.0) + (\(x.1) - (\(x.0))) * \(LX.num(Double(k) / 6))"
            b.rod("Base Wire \(k + 1)", axis: .y, c: (xx, z0), r: r, from: y.0, to: y.1, sides: 8)
            b.rod("Front Wire \(k + 1)", axis: .z, c: (xx, y.0), r: r, from: z0, to: "\(z0) + \(height)", sides: 8)
            b.rod("Back Wire \(k + 1)", axis: .z, c: (xx, y.1), r: r, from: z0, to: "\(z0) + \(height)", sides: 8)
        }
        for k in 0..<5 {
            let yy = "\(y.0) + (\(y.1) - (\(y.0))) * \(LX.num(Double(k) / 4))"
            b.rod("Cross Wire \(k + 1)", axis: .x, c: (yy, z0), r: r, from: x.0, to: x.1, sides: 8)
            b.rod("Left Wire \(k + 1)", axis: .z, c: (x.0, yy), r: r, from: z0, to: "\(z0) + \(height)", sides: 8)
            b.rod("Right Wire \(k + 1)", axis: .z, c: (x.1, yy), r: r, from: z0, to: "\(z0) + \(height)", sides: 8)
        }
        b.rod("Middle Band", axis: .x, c: (y.0, "\(z0) + \(height) / 2"), r: r, from: x.0, to: x.1, sides: 8)
    }

    static func pullOutBasket() -> ComponentDefinition {
        var b = bayBuilder("Pull-Out Basket", "Baskets", "Pull-out wire basket on side runners, for a wardrobe or a base cabinet.", .chrome, mount: ComponentKit.inch(2), width: ComponentKit.inch(18))
        b.tags("pull-out basket", "wire basket", "closet basket", "runner", "slide-out", "storage")
        b.aliases("closet basket", "slide out basket", "gliding basket", "wardrobe basket", "pull out wire basket")
        b.material("Slide Material", .greyPlastic)
        b.length("Basket Height", ComponentKit.inch(6))
        b.length("Basket Depth", ComponentKit.inch(20))
        b.length("Side Gap", ComponentKit.inch(0.75))
        let z0 = "Mount Height"
        b.slot("Slide Material") { b in
            b.box("Left Runner", x: (CX.zero, "Side Gap"), y: (CX.mm(5), "0.005 m + Basket Depth"), z: ("\(z0) + Basket Height - 0.015 m", "\(z0) + Basket Height + 0.005 m"))
            b.box("Right Runner", x: ("Opening Width - Side Gap", "Opening Width"), y: (CX.mm(5), "0.005 m + Basket Depth"),
                  z: ("\(z0) + Basket Height - 0.015 m", "\(z0) + Basket Height + 0.005 m"))
        }
        wireBody(&b, x: ("Side Gap", "Opening Width - Side Gap"), y: (CX.mm(10), "Basket Depth"), z0: z0, height: "Basket Height")
        bayItemSymbols(&b, x: ("Side Gap", "Opening Width - Side Gap"), y: (CX.mm(10), "Basket Depth"), z: (z0, "\(z0) + Basket Height"))
        slideScrews(&b, z: "\(z0) + Basket Height - 0.005 m", n: 2)
        b.requires(.fitsDepth("Basket Depth + 0.01 m"))
        b.type("Pull-Out Basket - 6\"", [:], cost: 36.00, model: "POB-6", isDefault: true)
        b.type("Pull-Out Basket - 11\" Deep", ["Basket Height": ComponentKit.inch(11)], cost: 44.00, model: "POB-11")
        return b.build()
    }

    static func wireBasket() -> ComponentDefinition {
        var b = bayBuilder("Wire Basket", "Baskets", "Wire basket with a rolled rim, to sit on a shelf or slide on basket runners.", .chrome, mount: 0, depth: ComponentKit.inch(14),
                           width: ComponentKit.inch(16))
        b.host([.shelf, .bay, .bottom], faces: [.top, .inside], align: .center)
        b.tags("wire basket", "basket", "storage basket", "mesh", "closet", "shelf basket")
        b.aliases("mesh basket", "storage bin wire", "shelf basket", "chrome basket", "wire bin")
        b.length("Basket Height", ComponentKit.inch(8))
        wireBody(&b, x: (CX.mm(5), "Opening Width - 0.005 m"), y: (CX.mm(5), "Opening Depth - 0.005 m"), z0: "Mount Height", height: "Basket Height")
        bayItemSymbols(&b, x: (CX.mm(5), "Opening Width - 0.005 m"), y: (CX.mm(5), "Opening Depth - 0.005 m"), z: ("Mount Height", "Mount Height + Basket Height"))
        b.type("Wire Basket - 16 x 14 x 8\"", [:], cost: 18.00, model: "WB-16148", isDefault: true)
        b.type("Wire Basket - 20 x 14 x 6\"", ["Opening Width": ComponentKit.inch(20), "Basket Height": ComponentKit.inch(6)], cost: 21.00, model: "WB-20146")
        return b.build()
    }

    static func laundryHamper() -> ComponentDefinition {
        var b = bayBuilder("Pull-Out Laundry Hamper", "Baskets", "Pull-out hamper: a frame with one or two removable fabric bags on full-extension slides.", .chrome, mount: ComponentKit.inch(1),
                           width: ComponentKit.inch(16))
        b.tags("laundry hamper", "hamper", "pull-out", "laundry bag", "closet", "clothes basket")
        b.aliases("pull out hamper", "laundry basket pull-out", "hamper drawer", "clothes hamper", "laundry pull out")
        b.material("Bag Material", .fabric)
        b.material("Slide Material", .zinc)
        b.length("Slide Length", ComponentKit.mm(450))
        b.length("Hamper Height", ComponentKit.inch(22))
        b.flag("Two Bags", false, instance: false)
        let z0 = "Mount Height", x0 = "0.0127 m + 0.005 m", x1 = "Opening Width - 0.0127 m - 0.005 m", y = (CX.mm(10), "0.003 m + Slide Length - 0.01 m")
        slidePair(&b, length: "Slide Length", z: ("\(z0) + 0.02 m", "\(z0) + 0.065 m"))
        b.box("Frame Base", x: (x0, x1), y: y, z: (z0, "\(z0) + 0.01 m"))
        b.box("Frame Rim", x: (x0, x1), y: y, z: ("\(z0) + Hamper Height - 0.012 m", "\(z0) + Hamper Height"))
        b.box("Rim Opening", x: ("\(x0) + 0.01 m", "\(x1) - 0.01 m"), y: ("0.01 m + 0.01 m", "0.003 m + Slide Length - 0.02 m"), z: ("\(z0) + Hamper Height - 0.013 m", "\(z0) + Hamper Height + 0.001 m"), void: true)
        for (k, xy) in [(x0, y.0), (x1, y.0), (x0, y.1), (x1, y.1)].enumerated() {
            b.rod("Post \(k + 1)", c: xy, r: CX.mm(4), from: z0, to: "\(z0) + Hamper Height", sides: 12)
        }
        b.slot("Bag Material") { b in
            b.shown(by: "One Bag") { b in
                b.blend("Bag", bottom: ComponentKit.rect(center: ("Opening Width / 2", "(0.01 m + Slide Length) / 2"), width: "Opening Width - 0.06 m", height: "Slide Length - 0.06 m"),
                        top: ComponentKit.rect(center: ("Opening Width / 2", "(0.01 m + Slide Length) / 2"), width: "Opening Width - 0.045 m", height: "Slide Length - 0.045 m"),
                        from: "\(z0) + 0.03 m", to: "\(z0) + Hamper Height - 0.015 m")
            }
            b.shown(by: "Two Bags") { b in
                for (k, cx) in ["Opening Width * 0.27", "Opening Width * 0.73"].enumerated() {
                    b.blend("Bag \(k + 1)", bottom: ComponentKit.rect(center: (cx, "(0.01 m + Slide Length) / 2"), width: "Opening Width * 0.42", height: "Slide Length - 0.06 m"),
                            top: ComponentKit.rect(center: (cx, "(0.01 m + Slide Length) / 2"), width: "Opening Width * 0.44", height: "Slide Length - 0.045 m"),
                            from: "\(z0) + 0.03 m", to: "\(z0) + Hamper Height - 0.015 m")
                }
            }
        }
        b.flag("One Bag", true, formula: "not(Two Bags)")
        bayItemSymbols(&b, x: (x0, x1), y: y, z: (z0, "\(z0) + Hamper Height"))
        slideScrews(&b, z: "\(z0) + 0.042 m")
        b.requires(.fitsDepth("Slide Length + 0.0127 m"))
        b.type("Laundry Hamper - Single", [:], flags: ["Two Bags": false], cost: 68.00, model: "LH-1", isDefault: true)
        b.type("Laundry Hamper - Double", ["Opening Width": ComponentKit.inch(24)], flags: ["Two Bags": true], cost: 92.00, model: "LH-2")
        return b.build()
    }

    static func foldingLaundryBasket() -> ComponentDefinition {
        var b = ComponentBuilder("Folding Laundry Basket", .wardrobe, "Baskets", "Collapsible laundry basket: fabric walls on a spring frame, with handles; Folded shows it flat.", frame: .plan)
        b.tags("folding laundry basket", "collapsible", "pop-up", "laundry", "hamper", "basket")
        b.aliases("collapsible hamper", "pop up laundry basket", "foldable basket", "fold flat hamper")
        b.material("Fabric Material", .fabric)
        b.material("Rim Material", .greyPlastic)
        b.length("Basket Width", ComponentKit.inch(16))
        b.length("Basket Depth", ComponentKit.inch(12))
        b.length("Basket Height", ComponentKit.inch(20))
        b.flag("Folded", false, instance: true)
        b.flag("Open", true, formula: "not(Folded)")
        b.host([.floor, .bottom, .shelf], faces: [.top], align: .center)
        b.slot("Fabric Material") { b in
            b.shown(by: "Open") { b in
                b.blend("Walls", bottom: ComponentKit.roundedRect(width: "Basket Width * 0.85", height: "Basket Depth * 0.85", radius: "Basket Depth * 0.15"),
                        top: ComponentKit.roundedRect(width: "Basket Width", height: "Basket Depth", radius: "Basket Depth * 0.18"), from: CX.zero, to: "Basket Height - 0.01 m")
            }
            b.shown(by: "Folded") { b in b.roundedBar("Folded", width: "Basket Width", height: "Basket Depth", radius: "Basket Depth * 0.18", from: CX.zero, to: CX.inch(1.5)) }
        }
        b.slot("Rim Material") { b in
            b.shown(by: "Open") { b in
                b.roundedBar("Rim", width: "Basket Width + 0.006 m", height: "Basket Depth + 0.006 m", radius: "Basket Depth * 0.18", from: "Basket Height - 0.012 m", to: "Basket Height")
            }
        }
        b.symbol(.face, CBL.all, .polyline(ComponentKit.roundedRect(width: "Basket Width", height: "Basket Depth", radius: "Basket Depth * 0.18"), closed: true))
        b.symRect(.side, CBL.coarse, (CX.zero, "-Basket Depth / 2"), ("Basket Height", "Basket Depth / 2"))
        b.type("Folding Basket - 16 x 12 x 20\"", [:], cost: 15.00, model: "FLB-16", isDefault: true)
        b.type("Folding Basket - 20 x 14 x 24\"", ["Basket Width": ComponentKit.inch(20), "Basket Depth": ComponentKit.inch(14), "Basket Height": ComponentKit.inch(24)], cost: 19.00, model: "FLB-20")
        return b.build()
    }

    // MARK: Mirrors and lights

    static func wardrobeMirror() -> ComponentDefinition {
        var b = ComponentBuilder("Wardrobe Mirror", .wardrobe, "Mirrors", "Door mirror: a mirror held on the door's inside face by four clips (or a frame).")
        b.tags("wardrobe mirror", "door mirror", "mirror", "full length", "clips", "closet")
        b.aliases("closet mirror", "door-mounted mirror", "full length mirror", "inside door mirror", "dressing mirror")
        b.material("Mirror Material", .mirror)
        b.material("Clip Material", .chrome)
        b.length("Mirror Width", ComponentKit.inch(14))
        b.length("Mirror Height", ComponentKit.inch(48))
        b.length("Mirror Thickness", ComponentKit.mm(4))
        b.flag("Framed", false, instance: false)
        b.host([.door, .back, .sidePanel], faces: [.inside, .front], align: .center)
        b.slot("Mirror Material") { b in
            b.box("Mirror", x: ("-Mirror Width / 2", "Mirror Width / 2"), y: ("-Mirror Height / 2", "Mirror Height / 2"), z: (CX.mm(1), "0.001 m + Mirror Thickness"))
        }
        b.slot("Clip Material") { b in
            b.shown(by: "Clips") { b in
                for (k, (x, y)) in [("-Mirror Width / 2", "-Mirror Height * 0.4"), ("Mirror Width / 2", "-Mirror Height * 0.4"),
                                    ("-Mirror Width / 2", "Mirror Height * 0.4"), ("Mirror Width / 2", "Mirror Height * 0.4")].enumerated() {
                    b.rod("Clip \(k + 1)", c: (x, y), r: CX.mm(9), from: CX.zero, to: "Mirror Thickness + 0.003 m", sides: 16)
                }
            }
            b.shown(by: "Framed") { b in
                let t = CX.mm(15)
                for (n, x, y) in [("Frame Left", ("-Mirror Width / 2 - \(t)", "-Mirror Width / 2"), ("-Mirror Height / 2 - \(t)", "Mirror Height / 2 + \(t)")),
                                  ("Frame Right", ("Mirror Width / 2", "Mirror Width / 2 + \(t)"), ("-Mirror Height / 2 - \(t)", "Mirror Height / 2 + \(t)")),
                                  ("Frame Top", ("-Mirror Width / 2", "Mirror Width / 2"), ("Mirror Height / 2", "Mirror Height / 2 + \(t)")),
                                  ("Frame Bottom", ("-Mirror Width / 2", "Mirror Width / 2"), ("-Mirror Height / 2 - \(t)", "-Mirror Height / 2"))] {
                    b.box(n, x: x, y: y, z: (CX.zero, "Mirror Thickness + 0.008 m"))
                }
            }
        }
        b.flag("Clips", true, formula: "not(Framed)")
        b.symRect(.face, CBL.all, ("-Mirror Width / 2", "-Mirror Height / 2"), ("Mirror Width / 2", "Mirror Height / 2"))
        b.symLine(.face, CBL.coarse, ("-Mirror Width / 2", "-Mirror Height / 2"), ("Mirror Width / 2", "Mirror Height / 2"))
        b.symRect(.top, CBL.all, ("-Mirror Width / 2", CX.zero), ("Mirror Width / 2", "Mirror Thickness + 0.003 m"))
        for (x, y) in [("-Mirror Width / 2 - 0.004 m", "-Mirror Height * 0.4"), ("Mirror Width / 2 + 0.004 m", "-Mirror Height * 0.4"),
                       ("-Mirror Width / 2 - 0.004 m", "Mirror Height * 0.4"), ("Mirror Width / 2 + 0.004 m", "Mirror Height * 0.4")] {
            b.drill("Mirror clip screw", x: x, y: y, diameter: CX.mm(3), depth: CX.mm(10))
        }
        b.requires(.fitsWidth("Mirror Width + 0.05 m"))
        b.requires(.fitsHeight("Mirror Height + 0.05 m"))
        b.type("Door Mirror - 12 x 36\"", ["Mirror Width": ComponentKit.inch(12), "Mirror Height": ComponentKit.inch(36)], flags: ["Framed": false], cost: 28.00, model: "WM-1236")
        b.type("Door Mirror - 14 x 48\"", [:], flags: ["Framed": false], cost: 36.00, model: "WM-1448", isDefault: true)
        b.type("Door Mirror - 16 x 60\" Framed", ["Mirror Width": ComponentKit.inch(16), "Mirror Height": ComponentKit.inch(60)], flags: ["Framed": true], cost: 58.00, model: "WM-1660F")
        return b.build()
    }

    static func slidingMirror() -> ComponentDefinition {
        var b = ComponentBuilder("Sliding Mirror", .wardrobe, "Mirrors", "Pull-out mirror: a tall narrow mirror on a slide fixed to the side, pulled out and swung to face you.")
        b.tags("sliding mirror", "pull-out mirror", "slide-out", "full length", "closet", "swivel")
        b.aliases("pull out mirror", "slide out mirror", "wardrobe pull-out mirror", "hidden mirror", "telescopic mirror")
        b.material("Mirror Material", .mirror)
        b.material("Frame Material", .aluminum)
        b.length("Mirror Width", ComponentKit.inch(4))
        b.length("Mirror Height", ComponentKit.inch(40))
        b.length("Slide Length", ComponentKit.mm(450))
        b.flag("Extended", false, instance: true)
        b.host([.sidePanel, .divider], faces: [.inside], align: .center)
        // On the side's inside face: X runs from the front edge (0) back, Y up, Z into the bay.
        let off = "if(Extended, -Slide Length * 0.9, 0 m)"
        b.slot("Frame Material") { b in
            b.box("Slide", x: (CX.mm(10), "0.01 m + Slide Length"), y: ("Mirror Height / 2 - 0.02 m", "Mirror Height / 2 + 0.02 m"), z: (CX.zero, CX.mm(12)))
            b.box("Frame", x: ("\(off) + 0.01 m", "\(off) + 0.01 m + Mirror Width + 0.01 m"), y: (CX.zero, "Mirror Height"), z: (CX.mm(12), CX.mm(30)))
        }
        b.slot("Mirror Material") { b in
            b.box("Mirror", x: ("\(off) + 0.015 m", "\(off) + 0.015 m + Mirror Width"), y: (CX.mm(5), "Mirror Height - 0.005 m"), z: (CX.mm(30), CX.mm(34)))
        }
        b.symRect(.face, CBL.all, (CX.mm(10), CX.zero), ("0.02 m + Mirror Width", "Mirror Height"))
        b.symRect(.top, CBL.all, (CX.mm(10), CX.zero), ("0.01 m + Slide Length", CX.mm(34)))
        b.symRect(.top, CBL.mediumFine, ("-Slide Length * 0.9", CX.zero), (CX.zero, CX.mm(34)), dashed: true)
        for x in ["0.01 m + Slide Length * 0.2", "0.01 m + Slide Length * 0.8"] { b.drill("Mirror slide screw", x: x, y: "Mirror Height / 2", diameter: CX.mm(4), depth: CX.mm(12)) }
        b.type("Sliding Mirror - 40\"", [:], cost: 95.00, model: "SLM-40", isDefault: true)
        b.type("Sliding Mirror - 48\"", ["Mirror Height": ComponentKit.inch(48), "Mirror Width": ComponentKit.inch(5)], cost: 115.00, model: "SLM-48")
        return b.build()
    }

    static func wardrobeLight() -> ComponentDefinition {
        var b = ComponentBuilder("Wardrobe Light", .wardrobe, "Lighting", "Wardrobe light bar: a surface LED bar with a door or motion sensor, under a shelf or the top (geometry and power data only).")
        b.tags("wardrobe light", "closet light", "led bar", "sensor", "motion", "battery", "12 v")
        b.aliases("closet light", "led closet light", "sensor light", "wardrobe led", "cabinet light bar", "motion sensor light")
        b.material("Finish Material", .aluminum)
        b.material("Diffuser Material", .diffuser)
        b.length("Length", ComponentKit.inch(16))
        b.length("Bar Width", ComponentKit.mm(24))
        b.length("Bar Depth", ComponentKit.mm(10))
        b.choice("Sensor", ["Motion", "Door", "Switch"], "Motion")
        b.electrical(watts: 2.5, volts: 12, supply: "DC 12 V", cable: "2-core 0.5 mm², 2 m", connector: "Mini plug")
        b.host([.top, .shelf, .rail], faces: [.bottom], align: .center)
        // Under the face: the bar hangs from Z = 0 (face frame on the shelf's underside).
        b.box("Body", x: ("-Length / 2", "Length / 2"), y: ("-Bar Width / 2", "Bar Width / 2"), z: (CX.zero, "Bar Depth"))
        b.slot("Diffuser Material") { b in
            b.box("Diffuser", x: ("-Length / 2 + 0.005 m", "Length / 2 - 0.005 m"), y: ("-Bar Width / 2 + 0.003 m", "Bar Width / 2 - 0.003 m"), z: ("Bar Depth", "Bar Depth + 0.0015 m"))
        }
        b.at(CBL.fine) { b in b.rod("Sensor Eye", c: ("Length / 2 - 0.015 m", CX.zero), r: CX.mm(4), from: "Bar Depth", to: "Bar Depth + 0.003 m", sides: 16) }
        b.symRect(.face, CBL.all, ("-Length / 2", "-Bar Width / 2"), ("Length / 2", "Bar Width / 2"))
        b.symLine(.face, CBL.coarse, ("-Length / 2", CX.zero), ("Length / 2", CX.zero))
        b.symRect(.top, CBL.all, ("-Length / 2", CX.zero), ("Length / 2", "Bar Depth"))
        for x in ["-Length * 0.4", "Length * 0.4"] { b.drill("Light clip screw", x: x, y: CX.zero, diameter: CX.mm(2.5), depth: CX.mm(10)) }
        b.drill("Cable hole", x: "-Length / 2 - 0.01 m", y: CX.zero, diameter: CX.mm(8), depth: "Host Thickness", through: true)
        b.type("Wardrobe Light - 12\"", ["Length": ComponentKit.inch(12)], numbers: ["Power": 2], cost: 18.00, model: "WLT-12")
        b.type("Wardrobe Light - 16\"", [:], cost: 22.00, model: "WLT-16", isDefault: true)
        b.type("Wardrobe Light - 24\"", ["Length": ComponentKit.inch(24)], numbers: ["Power": 3.6], cost: 29.00, model: "WLT-24")
        return b.build()
    }

    static func ledHangingRail() -> ComponentDefinition {
        var b = bayBuilder("LED Hanging Rail", "Hanging Rods", "Oval aluminium hanging rail with an LED strip under it, lighting the clothes below (geometry and power data only).", .aluminum)
        b.tags("led rail", "lit rail", "wardrobe rail", "led", "oval", "lighting", "closet")
        b.aliases("led wardrobe rail", "lighted closet rod", "illuminated rail", "led closet rod", "light rail")
        b.material("Diffuser Material", .diffuser)
        b.length("Rail Width", ComponentKit.mm(30))
        b.length("Rail Height", ComponentKit.mm(15))
        b.length("Rail Setback", ComponentKit.inch(11), instance: true, group: .placement)
        b.electrical(watts: 1.5, volts: 12, perFoot: true, supply: "DC 12 V", cable: "2-core 0.5 mm², 2 m", connector: "Clip connector")
        let y = "Rail Setback", z = "Mount Height"
        b.ovalRod("Rail", axis: .x, c: (y, z), ru: "Rail Width / 2", rv: "Rail Height / 2", from: CX.mm(3), to: "Opening Width - 0.003 m")
        b.slot("Diffuser Material") { b in
            b.box("LED Strip", x: (CX.mm(8), "Opening Width - 0.008 m"), y: ("\(y) - Rail Width * 0.3", "\(y) + Rail Width * 0.3"), z: ("\(z) - Rail Height / 2 - 0.002 m", "\(z) - Rail Height * 0.3"))
        }
        for (n, x) in [("Left Support", (CX.zero, CX.mm(3))), ("Right Support", ("Opening Width - 0.003 m", "Opening Width"))] {
            b.box(n, x: x, y: ("\(y) - Rail Width * 0.7", "\(y) + Rail Width * 0.7"), z: ("\(z) - Rail Height", "\(z) + Rail Height * 1.4"))
        }
        rodSymbols(&b, y: y, z: z, r: "Rail Width / 2")
        b.drill("Rail support screw", x: y, y: "\(z) + Rail Height", diameter: CX.mm(3.5), depth: CX.mm(13))
        b.drill("Cable hole", x: y, y: "\(z) + Rail Height * 2", diameter: CX.mm(8), depth: "Host Thickness", through: true)
        b.type("LED Rail - 30 x 15 mm", [:], cost: 34.00, model: "LHR-3015", isDefault: true)
        b.type("LED Rail - 30 x 15 mm Warm", [:], numbers: ["Power": 1.8], cost: 36.00, model: "LHR-3015W")
        return b.build()
    }

    // MARK: Hooks and racks

    static func wardrobeHook() -> ComponentDefinition {
        var b = ComponentBuilder("Wardrobe Hook", .wardrobe, "Hooks", "Coat or robe hook on a round rose: single, or double with an upper and a lower prong.")
        b.tags("wardrobe hook", "coat hook", "robe hook", "double hook", "closet", "door hook")
        b.aliases("coat hook", "robe hook", "clothes hook", "hat and coat hook", "garment hook")
        b.material("Finish Material", .matteBlack)
        b.length("Rose Diameter", ComponentKit.inch(1.25))
        b.length("Projection", ComponentKit.inch(2.5))
        b.length("Wire Diameter", ComponentKit.inch(0.3125))
        b.flag("Double", false, instance: false)
        b.host([.door, .sidePanel, .back, .wall], faces: [.inside, .front], align: .center)
        b.turn("Rose", base: CX.zero, [(CX.zero, CX.zero), ("Rose Diameter / 2", CX.zero), ("Rose Diameter / 2", CX.mm(3)), ("Rose Diameter * 0.35", CX.mm(6)), (CX.zero, CX.mm(6))])
        b.strut("Lower Prong", bottom: (CX.zero, CX.zero), top: (CX.zero, "Projection * 0.25"), r0: "Wire Diameter / 2", r1: "Wire Diameter / 2", z: (CX.mm(5), "Projection * 0.7"), sides: 16)
        b.rod("Lower Tip", axis: .y, c: (CX.zero, "Projection * 0.7"), r: "Wire Diameter / 2 + 0.001 m", from: "Projection * 0.25", to: "Projection * 0.25 + 0.012 m", sides: 16)
        b.shown(by: "Double") { b in
            b.strut("Upper Prong", bottom: (CX.zero, CX.zero), top: (CX.zero, "Projection * 0.6"), r0: "Wire Diameter / 2", r1: "Wire Diameter / 2", z: (CX.mm(5), "Projection"), sides: 16)
        }
        b.symCircle(.face, CBL.all, r: "Rose Diameter / 2")
        b.symRect(.top, CBL.all, ("-Rose Diameter / 2", CX.zero), ("Rose Diameter / 2", "Projection"))
        b.drill("Hook screw", x: CX.zero, y: CX.zero, diameter: CX.mm(3.5), depth: CX.mm(16))
        b.type("Wardrobe Hook - Single", [:], flags: ["Double": false], cost: 4.50, model: "WH-1", isDefault: true)
        b.type("Wardrobe Hook - Double", ["Projection": ComponentKit.inch(3.25)], flags: ["Double": true], cost: 6.00, model: "WH-2")
        return b.build()
    }

    static func hatRack() -> ComponentDefinition {
        var b = ComponentBuilder("Hat Organizer", .wardrobe, "Hooks", "Hat rack: a rail with long pegs angled up, for caps and hats, on a wall, a back or a door.")
        b.tags("hat rack", "hat organizer", "cap rack", "pegs", "rail", "closet")
        b.aliases("cap organizer", "hat holder", "baseball cap rack", "hat peg rail", "hat hanger")
        b.material("Finish Material", .oak)
        b.material("Peg Material", .walnut)
        b.length("Rail Length", ComponentKit.inch(24))
        b.length("Rail Height", ComponentKit.inch(3))
        b.length("Peg Length", ComponentKit.inch(4))
        b.length("Peg Diameter", ComponentKit.inch(0.75))
        b.integer("Peg Count", 5)
        b.flag("Five Pegs", true, formula: "Peg Count > 3")
        b.host([.back, .wall, .door], faces: [.inside, .front], align: .center)
        b.box("Rail", x: ("-Rail Length / 2", "Rail Length / 2"), y: ("-Rail Height / 2", "Rail Height / 2"), z: (CX.zero, CX.inch(0.75)))
        b.slot("Peg Material") { b in
            for k in 0..<5 {
                let x = "Rail Length * \(LX.num(-0.4 + 0.2 * Double(k)))"
                let add: (inout ComponentBuilder) -> Void = { b in
                    b.strut("Peg \(k + 1)", bottom: (x, CX.zero), top: (x, "Peg Length * 0.3"), r0: "Peg Diameter / 2", r1: "Peg Diameter * 0.45", z: (CX.inch(0.75), "Peg Length"), sides: 16)
                }
                if k == 1 || k == 3 { b.shown(by: "Five Pegs", add) } else { add(&b) }
            }
        }
        b.symRect(.face, CBL.all, ("-Rail Length / 2", "-Rail Height / 2"), ("Rail Length / 2", "Rail Height / 2"))
        b.symRect(.top, CBL.all, ("-Rail Length / 2", CX.zero), ("Rail Length / 2", "Peg Length"))
        for x in ["-Rail Length * 0.45", "Rail Length * 0.45"] { b.drill("Rail screw", x: x, y: CX.zero, diameter: CX.mm(4), depth: CX.mm(30)) }
        b.type("Hat Rack - 3 Peg", ["Rail Length": ComponentKit.inch(18)], numbers: ["Peg Count": 3], cost: 16.00, model: "HR-3")
        b.type("Hat Rack - 5 Peg", [:], cost: 22.00, model: "HR-5", isDefault: true)
        return b.build()
    }

    // MARK: Systems

    static func storageTower() -> ComponentDefinition {
        var b = bayBuilder("Pull-Out Storage Tower", "Pull-Out Towers", "Tall pull-out tower: a frame with wire shelves on a heavy bottom slide and a top guide, for a narrow wardrobe bay.",
                           .aluminum, mount: ComponentKit.inch(1), width: ComponentKit.inch(8))
        b.tags("storage tower", "pull-out tower", "tall pull-out", "larder", "narrow", "wardrobe", "shelves")
        b.aliases("pull out tower", "tall pull out", "wardrobe pull out", "narrow pull out", "pantry tower")
        b.material("Slide Material", .zinc)
        b.length("Tower Height", ComponentKit.inch(60))
        b.length("Tower Depth", ComponentKit.mm(500))
        b.integer("Shelf Count", 5)
        let z0 = "Mount Height", x = (CX.mm(10), "Opening Width - 0.01 m"), y = (CX.mm(20), "0.02 m + Tower Depth")
        b.slot("Slide Material") { b in
            b.box("Bottom Slide", x: ("Opening Width / 2 - 0.02 m", "Opening Width / 2 + 0.02 m"), y: (CX.mm(5), "0.02 m + Tower Depth"), z: (z0, "\(z0) + 0.03 m"))
            b.box("Top Guide", x: ("Opening Width / 2 - 0.015 m", "Opening Width / 2 + 0.015 m"), y: (CX.mm(5), "0.02 m + Tower Depth"),
                  z: ("\(z0) + Tower Height + 0.03 m", "\(z0) + Tower Height + 0.05 m"))
        }
        for (k, (xx, yy)) in [(x.0, y.0), (x.1, y.0), (x.0, y.1), (x.1, y.1)].enumerated() {
            b.rod("Post \(k + 1)", c: (xx, yy), r: CX.mm(8), from: "\(z0) + 0.03 m", to: "\(z0) + 0.03 m + Tower Height", sides: 16)
        }
        for k in 0..<5 {
            let z = "\(z0) + 0.03 m + Tower Height * \(LX.num(0.04 + 0.22 * Double(k)))"
            b.box("Shelf \(k + 1)", x: x, y: y, z: (z, "\(z) + 0.012 m"))
            b.box("Shelf \(k + 1) Rail", x: x, y: ("\(y.1) - 0.006 m", y.1), z: (z, "\(z) + 0.06 m"))
        }
        bayItemSymbols(&b, x: x, y: y, z: (z0, "\(z0) + Tower Height + 0.05 m"))
        for f in ["0.2", "0.8"] {
            b.drill("Tower slide screw", x: "Opening Width / 2", y: "0.02 m + Tower Depth * \(f)", diameter: CX.mm(4), depth: CX.mm(12))
        }
        b.requires(.fitsDepth("Tower Depth + 0.03 m"))
        b.requires(.fitsHeight("Tower Height + 0.08 m"))
        b.type("Storage Tower - 150 x 500 mm", ["Opening Width": ComponentKit.mm(150)], cost: 140.00, model: "ST-150")
        b.type("Storage Tower - 200 x 500 mm", [:], cost: 155.00, model: "ST-200", isDefault: true)
        b.type("Storage Tower - 300 x 500 mm", ["Opening Width": ComponentKit.mm(300), "Tower Height": ComponentKit.inch(72)], cost: 185.00, model: "ST-300")
        return b.build()
    }

    static func cornerWardrobe() -> ComponentDefinition {
        var b = bayBuilder("Corner Wardrobe System", "Corner Systems", "Corner wardrobe rail: two oval rails meeting at a corner piece, hanging clothes round an L-shaped corner.", .chrome,
                           depth: ComponentKit.inch(36), width: ComponentKit.inch(36))
        b.tags("corner wardrobe", "corner rail", "l-shaped", "walk-in", "closet corner", "oval rail")
        b.aliases("corner closet rod", "l-shaped rail", "corner hanging system", "corner wardrobe rail", "angle rail")
        b.length("Rail Setback", ComponentKit.inch(11), instance: true, group: .placement)
        b.length("Rail Width", ComponentKit.mm(30))
        b.length("Rail Height", ComponentKit.mm(15))
        let s = "Rail Setback", z = "Mount Height"
        // The corner at the back-left: one rail along the back (across X) and one along the left side (along Y).
        b.ovalRod("Back Rail", axis: .x, c: ("Opening Depth - \(s)", z), ru: "Rail Width / 2", rv: "Rail Height / 2", from: s, to: "Opening Width")
        b.ovalRod("Side Rail", axis: .y, c: (s, z), ru: "Rail Width / 2", rv: "Rail Height / 2", from: CX.zero, to: "Opening Depth - \(s)")
        b.slot("Support Material") { b in
            b.rod("Corner Piece", c: (s, "Opening Depth - \(s)"), r: "Rail Width * 0.8", from: "\(z) - Rail Height", to: "\(z) + Rail Height * 1.4")
            b.rod("Corner Hanger", c: (s, "Opening Depth - \(s)"), r: CX.mm(6), from: z, to: "\(z) + 0.15 m")
            b.box("Back End Support", x: ("Opening Width - 0.003 m", "Opening Width"), y: ("Opening Depth - \(s) - Rail Width * 0.7", "Opening Depth - \(s) + Rail Width * 0.7"),
                  z: ("\(z) - Rail Height", "\(z) + Rail Height * 1.4"))
            b.box("Side End Support", x: ("\(s) - Rail Width * 0.7", "\(s) + Rail Width * 0.7"), y: (CX.zero, CX.mm(3)), z: ("\(z) - Rail Height", "\(z) + Rail Height * 1.4"))
        }
        b.material("Support Material", .greyPlastic)
        b.symbol(.face, CBL.all, .polyline(ComponentKit.points([(s, CX.zero), (s, "Opening Depth - \(s)"), ("Opening Width", "Opening Depth - \(s)")]), closed: false))
        b.symCircle(.face, CBL.mediumFine, c: (s, "Opening Depth - \(s)"), r: "Rail Width * 0.8")
        b.symCircle(.side, CBL.coarse, c: (z, s), r: "Rail Width / 2")
        b.drill("Corner hanger screw", x: s, y: "Opening Depth - \(s)", diameter: CX.mm(4), depth: CX.mm(13))
        b.type("Corner Rail - 36 x 36\"", [:], cost: 38.00, model: "CWR-3636", isDefault: true)
        b.type("Corner Rail - 48 x 36\"", ["Opening Width": ComponentKit.inch(48)], cost: 44.00, model: "CWR-4836")
        return b.build()
    }

    static func wardrobeCarousel() -> ComponentDefinition {
        var b = bayBuilder("Rotating Wardrobe Carousel", "Corner Systems", "Rotating clothes carousel: a floor-to-top pole with round hanging rails that turn, for a deep corner.", .chrome,
                           mount: ComponentKit.inch(60), depth: ComponentKit.inch(40), width: ComponentKit.inch(40))
        b.tags("rotating wardrobe", "carousel", "revolving", "corner", "pole", "closet carousel")
        b.aliases("revolving closet", "rotating closet rod", "clothes carousel", "spinning wardrobe", "rotating rack")
        b.length("Carousel Diameter", ComponentKit.inch(36))
        b.length("Pole Height", ComponentKit.inch(84))
        b.length("Pole Diameter", ComponentKit.mm(32))
        b.length("Tier Spacing", ComponentKit.inch(36))
        b.flag("Two Tiers", true, instance: false)
        let c = ("Opening Width / 2", "Opening Depth / 2")
        b.rod("Pole", c: c, r: "Pole Diameter / 2", from: CX.zero, to: "Pole Height", sides: 24)
        b.rod("Floor Flange", c: c, r: "Pole Diameter * 1.5", from: CX.zero, to: CX.mm(8), sides: 24)
        for t in 0..<2 {
            let z = "Mount Height - Tier Spacing * \(t)"
            let add: (inout ComponentBuilder) -> Void = { b in
                b.pipe("Ring \(t + 1)", c: c, outer: "Carousel Diameter / 2", inner: "Carousel Diameter / 2 - 0.02 m", from: "\(z) - 0.01 m", to: z)
                for k in 0..<4 {
                    let a = Double(k) * .pi / 2
                    b.box("Spoke \(t + 1).\(k + 1)", x: ("Opening Width / 2 + Carousel Diameter * \(LX.num(0.25 * cos(a))) - Carousel Diameter * \(LX.num(abs(0.25 * cos(a)) + 0.006))",
                                                     "Opening Width / 2 + Carousel Diameter * \(LX.num(0.25 * cos(a))) + Carousel Diameter * \(LX.num(abs(0.25 * cos(a)) + 0.006))"),
                          y: ("Opening Depth / 2 + Carousel Diameter * \(LX.num(0.25 * sin(a))) - Carousel Diameter * \(LX.num(abs(0.25 * sin(a)) + 0.006))",
                              "Opening Depth / 2 + Carousel Diameter * \(LX.num(0.25 * sin(a))) + Carousel Diameter * \(LX.num(abs(0.25 * sin(a)) + 0.006))"),
                          z: ("\(z) - 0.01 m", z))
                }
            }
            if t == 1 { b.shown(by: "Two Tiers", add) } else { add(&b) }
        }
        b.symCircle(.face, CBL.all, c: c, r: "Carousel Diameter / 2")
        b.symCircle(.face, CBL.all, c: c, r: "Pole Diameter / 2")
        b.symbol(.face, CBL.mediumFine, dashed: true, .arc(center: FamilyPoint(c.0, c.1), radius: "Carousel Diameter / 2 + 0.05 m", startDegrees: "20", sweepDegrees: "60"))
        b.symRect(.side, CBL.coarse, (CX.zero, "Opening Depth / 2 - Carousel Diameter / 2"), ("Pole Height", "Opening Depth / 2 + Carousel Diameter / 2"))
        b.drill("Pole flange screw", x: c.0, y: c.1, diameter: CX.mm(5), depth: CX.mm(20))
        b.requires(.fitsWidth("Carousel Diameter + 0.05 m"))
        b.requires(.fitsDepth("Carousel Diameter + 0.05 m"))
        b.type("Carousel - 36\" Two Tier", [:], flags: ["Two Tiers": true], cost: 160.00, model: "RWC-36-2", isDefault: true)
        b.type("Carousel - 30\" One Tier", ["Carousel Diameter": ComponentKit.inch(30)], flags: ["Two Tiers": false], cost: 120.00, model: "RWC-30-1")
        return b.build()
    }

    static func wardrobeSafe() -> ComponentDefinition {
        var b = ComponentBuilder("Wardrobe Safe", .wardrobe, "Safes", "In-wardrobe safe: a steel box bolted to a shelf and the back, with a keypad door (geometry and battery data only).", frame: .plan)
        b.tags("wardrobe safe", "closet safe", "keypad", "steel", "security", "valuables", "electronic")
        b.aliases("closet safe", "furniture safe", "hidden safe", "digital safe", "electronic safe", "in-cabinet safe")
        b.material("Body Material", .matteBlack)
        b.material("Keypad Material", .blackPlastic)
        b.length("Safe Width", ComponentKit.inch(14))
        b.length("Safe Depth", ComponentKit.inch(12))
        b.length("Safe Height", ComponentKit.inch(10))
        b.choice("Lock", ["Keypad", "Key", "Fingerprint"], "Keypad")
        b.electrical(watts: 0.1, volts: 6, supply: "4 x AA battery", cable: "none")
        b.host([.shelf, .bottom], faces: [.top], align: .center)
        b.box("Body", x: ("-Safe Width / 2", "Safe Width / 2"), y: ("-Safe Depth / 2", "Safe Depth / 2"), z: (CX.zero, "Safe Height"))
        b.box("Door Gap", x: ("-Safe Width / 2 + 0.008 m", "Safe Width / 2 - 0.008 m"), y: ("-Safe Depth / 2 - 0.001 m", "-Safe Depth / 2 + 0.002 m"),
              z: (CX.mm(8), "Safe Height - 0.008 m"), void: true)
        b.slot("Keypad Material") { b in
            b.box("Keypad", x: ("-Safe Width * 0.3", "-Safe Width * 0.05"), y: ("-Safe Depth / 2 - 0.006 m", "-Safe Depth / 2"), z: ("Safe Height * 0.45", "Safe Height * 0.8"))
            b.rod("Knob", axis: .y, c: ("Safe Width * 0.2", "Safe Height * 0.55"), r: CX.mm(14), from: "-Safe Depth / 2 - 0.018 m", to: "-Safe Depth / 2", sides: 24)
        }
        b.symRect(.face, CBL.all, ("-Safe Width / 2", "-Safe Depth / 2"), ("Safe Width / 2", "Safe Depth / 2"))
        b.symLine(.face, CBL.coarse, ("-Safe Width / 2", "-Safe Depth / 2"), ("Safe Width / 2", "Safe Depth / 2"))
        b.symLine(.face, CBL.coarse, ("-Safe Width / 2", "Safe Depth / 2"), ("Safe Width / 2", "-Safe Depth / 2"))
        b.symRect(.side, CBL.coarse, (CX.zero, "-Safe Depth / 2"), ("Safe Height", "Safe Depth / 2"))
        for (x, y) in [("-Safe Width * 0.3", "-Safe Depth * 0.2"), ("Safe Width * 0.3", "-Safe Depth * 0.2"), ("-Safe Width * 0.3", "Safe Depth * 0.25"), ("Safe Width * 0.3", "Safe Depth * 0.25")] {
            b.drill("Safe anchor bolt", x: x, y: y, diameter: CX.mm(8), depth: "Host Thickness", through: true)
        }
        b.type("Wardrobe Safe - 14 x 12 x 10\"", [:], texts: ["Lock": "Keypad"], cost: 120.00, model: "WS-141210", isDefault: true)
        b.type("Wardrobe Safe - 17 x 14 x 8\" Laptop", ["Safe Width": ComponentKit.inch(17), "Safe Depth": ComponentKit.inch(14), "Safe Height": ComponentKit.inch(8)],
               texts: ["Lock": "Keypad"], cost: 150.00, model: "WS-17148")
        b.type("Wardrobe Safe - 12 x 10 x 8\" Key", ["Safe Width": ComponentKit.inch(12), "Safe Depth": ComponentKit.inch(10), "Safe Height": ComponentKit.inch(8)],
               texts: ["Lock": "Key"], numbers: ["Power": 0], cost: 85.00, model: "WS-12108K")
        return b.build()
    }
}

extension ComponentFinish {
    /// COMPB: white melamine for partitions and panels.
    static let whiteMelamine = ComponentFinish("Melamine - White", .plastic, RGBColor(hex: 0xF2F1EC))
}
