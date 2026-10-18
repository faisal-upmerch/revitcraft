import Foundation

// Kitchen casework (US and metric module sizes), appliances, laundry and electronics.
extension LibraryContent {

    // MARK: Casework

    static func kitchen() -> [ComponentLibraryItem] {
        [baseUS(), drawerBaseUS(), sinkBaseUS(), wallUS(), pantryUS(), ovenTallUS(), cornerBase(),
         baseMetric(), drawerBaseMetric(), sinkBaseMetric(), wallMetric(), tallMetric(),
         island(seating: false), island(seating: true), countertop(), modularKitchenStraight(), modularKitchenL()]
    }

    /// Base cabinet body: toe kick, carcass, door/drawer fronts and a countertop with a front overhang.
    static func baseBody(_ b: inout FB, counter: Double, overhang: Double, kick: Double = 0.1, kickSetback: Double = 0.075) {
        b.box("Toe Kick", L, R, D(-0.5, overhang + kickSetback), Bk, K(0), K(kick), .laminate, plan: false)
        b.box("Carcass", L, R, D(-0.5, overhang + 0.02), Bk, K(kick), H(1, -counter), .laminate)
        b.box("Fronts", W(-0.5, 0.002), W(0.5, -0.002), D(-0.5, overhang), D(-0.5, overhang + 0.02), K(kick + 0.003), H(1, -counter - 0.003), .lacquer, plan: false)
        b.box("Countertop", L, R, Fr, Bk, H(1, -counter), T, .stone)
        b.outline()
        b.line(L, D(-0.5, overhang + 0.02), R, D(-0.5, overhang + 0.02), .hidden)
    }

    static func baseUS() -> ComponentLibraryItem {
        var b = FB("Base Cabinet - US", .casework, group: "Kitchen", regions: [.usa], keywords: ["kitchen cabinet", "base unit", "cupboard", "counter"],
                   "Base cabinet with countertop; 24\" deep carcass, 36\" to the counter top.")
        baseBody(&b, counter: 0.038, overhang: 0.025)
        for w in [9.0, 12, 15, 18, 21, 24, 27, 30, 33, 36] { b.inch(inch(w), w, 25, 36) }
        return b.item
    }

    static func drawerBaseUS() -> ComponentLibraryItem {
        var b = FB("Base Cabinet - Drawers US", .casework, group: "Kitchen", regions: [.usa], keywords: ["drawer base", "kitchen drawers", "base unit"],
                   "Three-drawer base cabinet with countertop.")
        baseBody(&b, counter: 0.038, overhang: 0.025)
        for w in [15.0, 18, 24, 30] { b.inch(inch(w), w, 25, 36) }
        return b.item
    }

    /// Sink bowl cut into the countertop of a base body.
    static func sinkCut(_ b: inout FB, double: Bool = false) {
        if double {
            b.voidBox("Bowl Left", W(-0.5, 0.06), W(0, -0.02), D(-0.5, 0.08), D(0.5, -0.1), H(1, -0.2), H(1, 0.01))
            b.voidBox("Bowl Right", W(0, 0.02), W(0.5, -0.06), D(-0.5, 0.08), D(0.5, -0.1), H(1, -0.2), H(1, 0.01))
            b.rrect(W(-0.5, 0.06), D(-0.5, 0.08), W(0, -0.02), D(0.5, -0.1), K(0.03)); b.rrect(W(0, 0.02), D(-0.5, 0.08), W(0.5, -0.06), D(0.5, -0.1), K(0.03))
        } else {
            b.voidBox("Bowl", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.08), D(0.5, -0.1), H(1, -0.2), H(1, 0.01))
            b.rrect(W(-0.5, 0.06), D(-0.5, 0.08), W(0.5, -0.06), D(0.5, -0.1), K(0.03))
        }
        b.box("Basin", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.07), D(0.5, -0.09), H(1, -0.21), H(1, -0.2), .metal, plan: false)
        b.cyl("Faucet", K(0), D(0.5, -0.05), K(0.02), T, H(1, 0.3), .chrome, plan: false)
        b.bar("Spout", [(K(0), D(0.5, -0.05)), (K(0), D(0.5, -0.22))], z: H(1, 0.28), r: K(0.012), .chrome, sides: 8, plan: false)
        b.circle(K(0), D(0.5, -0.05), K(0.025))
    }

    static func sinkBaseUS() -> ComponentLibraryItem {
        var b = FB("Sink Base Cabinet - US", .casework, group: "Kitchen", regions: [.usa], keywords: ["kitchen sink", "sink unit", "base unit"],
                   "Sink base cabinet with countertop, stainless bowl and faucet.")
        baseBody(&b, counter: 0.038, overhang: 0.025)
        sinkCut(&b)
        for w in [30.0, 33, 36] { b.inch(inch(w), w, 25, 36) }
        return b.item
    }

    /// Wall cabinet hung with its bottom at Mounting Height.
    static func wallBody(_ b: inout FB) {
        let mh = P("Mounting Height")
        b.box("Carcass", L, R, D(-0.5, 0.02), Bk, mh, mh + H(1), .laminate)
        b.box("Doors", W(-0.5, 0.002), W(0.5, -0.002), Fr, D(-0.5, 0.02), mh + 0.003, mh + H(1, -0.003), .lacquer, plan: false)
        b.rect(L, Fr, R, Bk, .hidden)
        b.line(L, Fr, R, Bk, .hidden)
    }

    static func wallUS() -> ComponentLibraryItem {
        var b = FB("Wall Cabinet - US", .casework, group: "Kitchen", regions: [.usa], keywords: ["upper cabinet", "wall unit", "kitchen cabinet"],
                   instance: ["Mounting Height"], "Wall cabinet 12\" deep; Mounting Height is its underside (54\" standard).")
        wallBody(&b)
        for w in [12.0, 15, 18, 24, 30, 36] { b.inch("\(inch(w)) x \(inch(30))", w, 12, 30, ["Mounting Height": 54]) }
        for w in [30.0, 36] { b.inch("\(inch(w)) x \(inch(36))", w, 12, 36, ["Mounting Height": 54]) }
        b.inch("\(inch(36)) x \(inch(42))", 36, 12, 42, ["Mounting Height": 54])
        return b.item
    }

    static func pantryUS() -> ComponentLibraryItem {
        var b = FB("Tall Cabinet - Pantry US", .casework, group: "Kitchen", regions: [.usa], keywords: ["pantry", "tall unit", "larder", "utility cabinet"],
                   "Full-height pantry cabinet.")
        b.box("Toe Kick", L, R, D(-0.5, 0.075), Bk, K(0), K(0.1), .laminate, plan: false)
        b.box("Carcass", L, R, D(-0.5, 0.02), Bk, K(0.1), T, .laminate)
        b.box("Doors", W(-0.5, 0.002), W(0.5, -0.002), Fr, D(-0.5, 0.02), K(0.103), H(1, -0.003), .lacquer, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, Bk)
        b.inch("\(inch(18)) x \(inch(84))", 18, 24, 84); b.inch("\(inch(24)) x \(inch(84))", 24, 24, 84)
        b.inch("\(inch(24)) x \(inch(96))", 24, 24, 96); b.inch("\(inch(30)) x \(inch(84))", 30, 24, 84)
        return b.item
    }

    static func ovenTallUS() -> ComponentLibraryItem {
        var b = FB("Tall Cabinet - Oven US", .casework, group: "Kitchen", regions: [.usa], keywords: ["oven cabinet", "wall oven", "tall unit"],
                   "Tall cabinet housing a wall oven.")
        b.box("Toe Kick", L, R, D(-0.5, 0.075), Bk, K(0), K(0.1), .laminate, plan: false)
        b.box("Carcass", L, R, D(-0.5, 0.02), Bk, K(0.1), T, .laminate)
        b.box("Oven Door", W(-0.5, 0.04), W(0.5, -0.04), Fr, D(-0.5, 0.02), H(0.42), H(0.72), .applianceDark, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch("\(inch(30)) x \(inch(84))", 30, 25, 84); b.inch("\(inch(33)) x \(inch(96))", 33, 25, 96)
        return b.item
    }

    static func cornerBase() -> ComponentLibraryItem {
        var b = FB("Base Cabinet - Corner", .casework, group: "Kitchen", keywords: ["corner unit", "lazy susan", "carousel", "L corner"],
                   extra: ["Run Depth"], "L-shaped corner base cabinet with countertop; the corner is at the back left.")
        let rd = P("Run Depth")
        let poly: [(LX, LX)] = [(L, Fr), (L + rd, Fr), (L + rd, Bk - rd), (R, Bk - rd), (R, Bk), (L, Bk)]
        b.prism("Carcass", [(L, Fr), (L + rd - 0.045, Fr), (L + rd - 0.045, Bk - rd + 0.045), (R, Bk - rd + 0.045), (R, Bk), (L, Bk)], K(0.1), H(1, -0.038), .laminate)
        b.prism("Countertop", poly, H(1, -0.038), T, .stone)
        b.prism("Toe Kick", [(L, Fr), (L + rd - 0.1, Fr), (L + rd - 0.1, Bk - rd + 0.1), (R, Bk - rd + 0.1), (R, Bk), (L, Bk)], K(0), K(0.1), .laminate, plan: false)
        b.poly(poly)
        b.inch("\(inch(36)) x \(inch(36))", 36, 36, 36, ["Run Depth": 25]); b.mm("900 x 900", 900, 900, 900, ["Run Depth": 600])
        return b.item
    }

    static let metricKitchen: [LibraryRegion] = [.europe, .uk, .india, .asia]

    static func baseMetric() -> ComponentLibraryItem {
        var b = FB("Base Cabinet - Metric", .casework, group: "Kitchen", regions: metricKitchen, keywords: ["kitchen cabinet", "base unit", "modular kitchen", "counter"],
                   "Base unit on a 100 mm arcus with a 30 mm worktop, 600 deep.")
        baseBody(&b, counter: 0.03, overhang: 0.02, kick: 0.1, kickSetback: 0.05)
        for w in [300.0, 400, 450, 500, 600, 800, 900, 1000, 1200] { b.mm("\(Int(w))", w, 600, 900) }
        return b.item
    }

    static func drawerBaseMetric() -> ComponentLibraryItem {
        var b = FB("Base Cabinet - Drawers Metric", .casework, group: "Kitchen", regions: metricKitchen, keywords: ["drawer unit", "pan drawers", "modular kitchen"],
                   "Pan-drawer base unit with worktop.")
        baseBody(&b, counter: 0.03, overhang: 0.02, kick: 0.1, kickSetback: 0.05)
        for w in [400.0, 600, 800, 900] { b.mm("\(Int(w))", w, 600, 900) }
        return b.item
    }

    static func sinkBaseMetric() -> ComponentLibraryItem {
        var b = FB("Sink Base Cabinet - Metric", .casework, group: "Kitchen", regions: metricKitchen, keywords: ["sink unit", "modular kitchen", "kitchen sink"],
                   "Sink base unit with worktop, bowl and mixer tap.")
        baseBody(&b, counter: 0.03, overhang: 0.02, kick: 0.1, kickSetback: 0.05)
        sinkCut(&b)
        for w in [600.0, 800, 900, 1000] { b.mm("\(Int(w))", w, 600, 900) }
        return b.item
    }

    static func wallMetric() -> ComponentLibraryItem {
        var b = FB("Wall Cabinet - Metric", .casework, group: "Kitchen", regions: metricKitchen, keywords: ["wall unit", "upper cabinet", "modular kitchen"],
                   instance: ["Mounting Height"], "Wall unit 350 deep; Mounting Height is its underside.")
        wallBody(&b)
        for w in [300.0, 400, 450, 500, 600, 800, 900, 1000] { b.mm("\(Int(w)) x 720", w, 350, 720, ["Mounting Height": 1450]) }
        b.mm("600 x 900", 600, 350, 900, ["Mounting Height": 1400])
        return b.item
    }

    static func tallMetric() -> ComponentLibraryItem {
        var b = FB("Tall Cabinet - Metric", .casework, group: "Kitchen", regions: metricKitchen, keywords: ["tall unit", "larder", "pantry", "oven housing"],
                   "Full-height larder unit on a arcus.")
        b.box("Plinth", L, R, D(-0.5, 0.05), Bk, K(0), K(0.1), .laminate, plan: false)
        b.box("Carcass", L, R, D(-0.5, 0.02), Bk, K(0.1), T, .laminate)
        b.box("Doors", W(-0.5, 0.002), W(0.5, -0.002), Fr, D(-0.5, 0.02), K(0.103), H(1, -0.003), .lacquer, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, Bk)
        for (w, h) in [(450.0, 2100.0), (600, 2100), (600, 2200), (600, 2350)] { b.mm("\(Int(w)) x \(Int(h))", w, 600, h) }
        return b.item
    }

    static func island(seating: Bool) -> ComponentLibraryItem {
        var b = FB(seating ? "Kitchen Island - With Seating" : "Kitchen Island", .casework, group: "Kitchen", keywords: ["island", "kitchen island", "breakfast bar"],
                   seating ? "Kitchen island with cabinets on the back and a seating overhang with stools at the front."
                           : "Freestanding kitchen island with cabinets on both sides.")
        let front = seating ? D(-0.5, 0.3) : D(-0.5, 0.03)
        b.box("Plinth", W(-0.5, 0.05), W(0.5, -0.05), front + 0.05, D(0.5, -0.05), K(0), K(0.1), .laminate, plan: false)
        b.box("Cabinets", L + 0.02, R - 0.02, front, D(0.5, -0.02), K(0.1), H(1, -0.04), .lacquer)
        b.box("Top", L, R, Fr, Bk, H(1, -0.04), T, .stone)
        b.outline(); b.rect(L + 0.02, front, R - 0.02, D(0.5, -0.02), .hidden)
        if seating {
            for (i, f) in [-0.3, 0.0, 0.3].enumerated() {
                b.cyl("Stool \(i + 1)", W(f), D(-0.5, -0.05), K(0.2), K(0.62), K(0.66), .leather)
                b.cyl("Stool Column \(i + 1)", W(f), D(-0.5, -0.05), K(0.025), K(0), K(0.62), .chrome, plan: false)
                b.circle(W(f), D(-0.5, -0.05), K(0.2))
            }
            b.inch("\(inch(84)) x \(inch(48))", 84, 48, 36); b.mm("2100 x 1200", 2100, 1200, 900)
        } else {
            b.inch("\(inch(72)) x \(inch(36))", 72, 36, 36); b.inch("\(inch(96)) x \(inch(42))", 96, 42, 36)
            b.mm("1800 x 900", 1800, 900, 900); b.mm("2400 x 1000", 2400, 1000, 900)
        }
        return b.item
    }

    static func countertop() -> ComponentLibraryItem {
        var b = FB("Countertop - Straight", .casework, group: "Kitchen", keywords: ["worktop", "counter", "benchtop", "slab"],
                   instance: ["Mounting Height"], "Countertop slab; Mounting Height is its top.")
        b.box("Top", L, R, Fr, Bk, P("Mounting Height") - H(1), P("Mounting Height"), .stone)
        b.outline()
        b.inch("\(inch(96)) x \(inch(25))", 96, 25, 1.5, ["Mounting Height": 36])
        b.mm("2400 x 600", 2400, 600, 30, ["Mounting Height": 900]); b.mm("3000 x 600", 3000, 600, 30, ["Mounting Height": 900])
        return b.item
    }

    /// Hob and sink plan marks on a worktop run.
    static func hobSymbol(_ b: inout FB, _ cx: LX, _ cy: LX) {
        for (dx, dy) in [(-0.15, -0.12), (0.15, -0.12), (-0.15, 0.12), (0.15, 0.12)] { b.circle(cx + dx, cy + dy, K(0.08)) }
        b.rect(cx - 0.3, cy - 0.25, cx + 0.3, cy + 0.25)
    }

    static func modularKitchenStraight() -> ComponentLibraryItem {
        var b = FB("Modular Kitchen - Straight", .casework, group: "Kitchen", regions: [.india, .asia, .europe],
                   keywords: ["modular kitchen", "kitchen run", "one wall kitchen", "platform"], instance: ["Wall Cabinet Height"],
                   "Straight kitchen run: base units with worktop, hob and sink, and wall units above.")
        baseBody(&b, counter: 0.03, overhang: 0.02, kick: 0.1, kickSetback: 0.05)
        b.voidBox("Sink Bowl", W(0.25, -0.25), W(0.25, 0.25), D(-0.5, 0.08), D(0.5, -0.1), H(1, -0.2), H(1, 0.01))
        b.rrect(W(0.25, -0.25), D(-0.5, 0.08), W(0.25, 0.25), D(0.5, -0.1), K(0.03))
        b.box("Hob", W(-0.25, -0.3), W(-0.25, 0.3), D(-0.25), D(0.25), T, H(1, 0.01), .applianceDark, plan: false)
        hobSymbol(&b, W(-0.25), K(0))
        let wz = P("Wall Cabinet Height")
        b.box("Wall Units", L, R, D(0.5, -0.35), Bk, wz, wz + 0.72, .lacquer, plan: false)
        b.line(L, D(0.5, -0.35), R, D(0.5, -0.35), .hidden)
        b.mm("2400", 2400, 600, 900, ["Wall Cabinet Height": 1500]); b.mm("3000", 3000, 600, 900, ["Wall Cabinet Height": 1500])
        return b.item
    }

    static func modularKitchenL() -> ComponentLibraryItem {
        var b = FB("Modular Kitchen - L-Shaped", .casework, group: "Kitchen", regions: [.india, .asia, .europe],
                   keywords: ["modular kitchen", "L kitchen", "corner kitchen", "platform"], extra: ["Run Depth"],
                   "L-shaped kitchen: base units and worktop along the back and left, with hob and sink.")
        let rd = P("Run Depth")
        let poly: [(LX, LX)] = [(L, Fr), (L + rd, Fr), (L + rd, Bk - rd), (R, Bk - rd), (R, Bk), (L, Bk)]
        b.prism("Base Units", [(L, Fr), (L + rd - 0.02, Fr), (L + rd - 0.02, Bk - rd + 0.02), (R, Bk - rd + 0.02), (R, Bk), (L, Bk)], K(0.1), H(1, -0.03), .lacquer)
        b.prism("Worktop", poly, H(1, -0.03), T, .stone)
        b.voidBox("Sink Bowl", W(0.25, -0.25), W(0.25, 0.25), Bk - rd + 0.08, D(0.5, -0.1), H(1, -0.2), H(1, 0.01))
        b.rrect(W(0.25, -0.25), Bk - rd + 0.08, W(0.25, 0.25), D(0.5, -0.1), K(0.03))
        b.box("Hob", L + 0.03, L + rd - 0.03, D(-0.2, -0.3), D(-0.2, 0.3), T, H(1, 0.01), .applianceDark, plan: false)
        b.poly(poly)
        for dy in [-0.15, 0.15] { for dx in [0.2, 0.4] { b.circle(L + dx, D(-0.2, dy), K(0.07)) } }
        b.mm("2400 x 1800", 2400, 1800, 900, ["Run Depth": 600]); b.mm("3000 x 2400", 3000, 2400, 900, ["Run Depth": 600])
        return b.item
    }

    // MARK: Appliances

    static func appliances() -> [ComponentLibraryItem] {
        [fridgeSingle(), fridgeTopFreezer(), fridgeFrench(), fridgeSideBySide(), fridgeUnder(), range(), hobGas(), hobInduction(), wallOven(), dishwasher(),
         microwave(overRange: false), microwave(overRange: true), hoodChimney(), hoodUnder(), washerFront(), washerTop(), dryer(), washerDryerStack(),
         waterPurifier(), wineCooler(), chestFreezer(), tvWall(), computer()]
    }

    /// Fridge body with handles; `doors` 1 = single hinged door, 2 = two doors side by side.
    static func fridgeBody(_ b: inout FB, doors: Int, split: Double? = nil) {
        b.box("Cabinet", L, R, D(-0.5, 0.05), Bk, K(0.02), T, .appliance)
        b.box("Feet", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.08), D(0.5, -0.03), K(0), K(0.02), .plasticDark, plan: false)
        if doors == 1 {
            b.box("Door", L, R, Fr, D(-0.5, 0.05), K(0.03), T, .appliance, plan: false)
            b.box("Handle", W(0.5, -0.07), W(0.5, -0.05), D(-0.5, -0.03), Fr, H(0.4), H(0.8), .chrome, plan: false)
            b.arc(R, D(-0.5, 0.05), W(1), 180, 90, .hidden)
            b.line(R, D(-0.5, 0.05), R, D(-0.5, 0.05) - W(1), .hidden)
        } else {
            b.box("Door Left", L, W(0, -0.003), Fr, D(-0.5, 0.05), K(0.03), T, .appliance, plan: false)
            b.box("Door Right", W(0, 0.003), R, Fr, D(-0.5, 0.05), K(0.03), T, .appliance, plan: false)
            b.box("Handle Left", W(0, -0.05), W(0, -0.035), D(-0.5, -0.03), Fr, H(0.45), H(0.85), .chrome, plan: false)
            b.box("Handle Right", W(0, 0.035), W(0, 0.05), D(-0.5, -0.03), Fr, H(0.45), H(0.85), .chrome, plan: false)
            b.arc(L, D(-0.5, 0.05), W(0.5), 270, 90, .hidden); b.arc(R, D(-0.5, 0.05), W(0.5), 180, 90, .hidden)
        }
        if let split { b.box("Freezer Line", L, R, D(-0.5, -0.001), Fr, H(split), H(split, 0.006), .applianceDark, plan: false) }
        b.outline(); b.line(L, D(-0.5, 0.05), R, D(-0.5, 0.05))
    }

    static func fridgeSingle() -> ComponentLibraryItem {
        var b = FB("Refrigerator - Single Door", .specialtyEquipment, group: "Appliances", regions: [.india, .asia], keywords: ["fridge", "refrigerator", "direct cool"],
                   "Compact single-door refrigerator.")
        fridgeBody(&b, doors: 1)
        b.mm("190 L", 550, 650, 1250); b.mm("250 L", 600, 700, 1450)
        return b.item
    }

    static func fridgeTopFreezer() -> ComponentLibraryItem {
        var b = FB("Refrigerator - Top Freezer", .specialtyEquipment, group: "Appliances", keywords: ["fridge", "refrigerator", "fridge freezer", "double door"],
                   "Refrigerator with the freezer compartment on top.")
        fridgeBody(&b, doors: 1, split: 0.7)
        b.inch(inch(30), 30, 31, 66); b.inch(inch(33), 33, 32, 67); b.mm("600", 600, 650, 1750); b.mm("700", 700, 700, 1800)
        return b.item
    }

    static func fridgeFrench() -> ComponentLibraryItem {
        var b = FB("Refrigerator - French Door", .specialtyEquipment, group: "Appliances", keywords: ["fridge", "refrigerator", "bottom freezer"],
                   "French-door refrigerator with a bottom freezer drawer.")
        fridgeBody(&b, doors: 2, split: 0.32)
        b.inch(inch(36), 36, 34, 70); b.mm("910", 910, 750, 1780)
        return b.item
    }

    static func fridgeSideBySide() -> ComponentLibraryItem {
        var b = FB("Refrigerator - Side by Side", .specialtyEquipment, group: "Appliances", keywords: ["fridge", "refrigerator", "american fridge"],
                   "Side-by-side refrigerator-freezer.")
        fridgeBody(&b, doors: 2)
        b.inch(inch(36), 36, 34, 70); b.mm("910", 910, 720, 1790)
        return b.item
    }

    static func fridgeUnder() -> ComponentLibraryItem {
        var b = FB("Refrigerator - Undercounter", .specialtyEquipment, group: "Appliances", keywords: ["bar fridge", "undercounter", "beverage"],
                   "Undercounter refrigerator.")
        fridgeBody(&b, doors: 1)
        b.inch(inch(24), 24, 24, 34); b.mm("600", 600, 600, 820)
        return b.item
    }

    static func burner(_ b: inout FB, _ n: String, _ x: LX, _ y: LX, _ z: LX, r: Double) {
        b.cyl(n, x, y, K(r), z, z + 0.02, .steelDark, plan: false)
        b.circle(x, y, K(r)); b.circle(x, y, K(r * 0.45))
    }

    static func range() -> ComponentLibraryItem {
        var b = FB("Range - Freestanding", .specialtyEquipment, group: "Appliances", keywords: ["cooker", "stove", "oven range", "gas range"],
                   "Freestanding range with oven and cooktop; wider types have six burners.")
        b.box("Body", L, R, D(-0.5, 0.02), D(0.5, -0.05), K(0), H(1, -0.02), .appliance)
        b.box("Oven Door", W(-0.5, 0.03), W(0.5, -0.03), Fr, D(-0.5, 0.02), K(0.15), H(0.8), .applianceDark, plan: false)
        b.box("Cooktop", L, R, D(-0.5, 0.02), D(0.5, -0.05), H(1, -0.02), T, .applianceDark)
        b.box("Backguard", L, R, D(0.5, -0.05), Bk, K(0), H(1, 0.15), .appliance)
        for (i, (x, y)) in [(W(-0.25), D(-0.18)), (W(0.25), D(-0.18)), (W(-0.25), D(0.18)), (W(0.25), D(0.18))].enumerated() {
            burner(&b, "Burner \(i + 1)", x, y, T, r: 0.07)
        }
        b.visibility = "Six Burners"
        burner(&b, "Burner 5", K(0), D(-0.18), T, r: 0.05); burner(&b, "Burner 6", K(0), D(0.18), T, r: 0.05)
        b.visibility = nil
        b.outline(); b.line(L, D(0.5, -0.05), R, D(0.5, -0.05))
        b.inch(inch(30), 30, 27, 36); b.inch(inch(36), 36, 27, 36); b.mm("600", 600, 600, 900); b.mm("900", 900, 600, 900)
        b.flag("Six Burners") { $0 >= 0.85 }
        return b.item
    }

    static func hobGas() -> ComponentLibraryItem {
        var b = FB("Hob - Gas", .specialtyEquipment, group: "Appliances", regions: [.global], keywords: ["cooktop", "gas stove", "burner", "chulha"],
                   instance: ["Mounting Height"], "Built-in gas hob; Mounting Height is the worktop.")
        let z = P("Mounting Height")
        b.box("Glass Top", L, R, Fr, Bk, z, z + 0.01, .applianceDark)
        b.box("Body", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.03), D(0.5, -0.03), z - 0.06, z, .appliance, plan: false)
        for (i, (x, y)) in [(W(-0.3), D(-0.22)), (W(0.3), D(-0.22)), (W(-0.3), D(0.22)), (W(0.3), D(0.22))].enumerated() {
            burner(&b, "Burner \(i + 1)", x, y, z + 0.01, r: 0.055)
        }
        b.visibility = "Center Burner"
        burner(&b, "Burner 5", K(0), K(0), z + 0.01, r: 0.07)
        b.visibility = nil
        b.outline()
        b.mm("4 Burner 600", 600, 510, 50, ["Mounting Height": 900]); b.mm("5 Burner 750", 750, 510, 50, ["Mounting Height": 900])
        b.mm("5 Burner 900", 900, 510, 50, ["Mounting Height": 900])
        b.inch("4 Burner \(inch(30))", 30, 21, 2, ["Mounting Height": 36]); b.inch("5 Burner \(inch(36))", 36, 21, 2, ["Mounting Height": 36])
        b.flag("Center Burner") { $0 >= 0.7 }
        return b.item
    }

    static func hobInduction() -> ComponentLibraryItem {
        var b = FB("Hob - Induction", .specialtyEquipment, group: "Appliances", keywords: ["cooktop", "induction", "electric hob", "ceramic"],
                   instance: ["Mounting Height"], "Built-in induction hob; Mounting Height is the worktop.")
        let z = P("Mounting Height")
        b.box("Glass Top", L, R, Fr, Bk, z, z + 0.006, .applianceDark)
        b.box("Body", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.03), D(0.5, -0.03), z - 0.05, z, .plasticDark, plan: false)
        b.outline()
        for (x, y, r) in [(W(-0.25), D(-0.2), 0.09), (W(0.25), D(-0.2), 0.08), (W(-0.25), D(0.2), 0.08), (W(0.25), D(0.2), 0.1)] { b.circle(x, y, K(r)) }
        b.mm("600", 600, 520, 50, ["Mounting Height": 900]); b.mm("900", 900, 520, 50, ["Mounting Height": 900])
        b.inch(inch(30), 30, 21, 2, ["Mounting Height": 36]); b.inch(inch(36), 36, 21, 2, ["Mounting Height": 36])
        return b.item
    }

    static func wallOven() -> ComponentLibraryItem {
        var b = FB("Oven - Built-In", .specialtyEquipment, group: "Appliances", keywords: ["wall oven", "oven", "microwave oven"],
                   instance: ["Mounting Height"], "Built-in oven; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Body", L, R, D(-0.5, 0.03), Bk, z, z + H(1), .appliance)
        b.box("Door", W(-0.5, 0.005), W(0.5, -0.005), Fr, D(-0.5, 0.03), z + 0.01, z + H(0.8), .applianceDark, plan: false)
        b.bar("Handle", [(W(-0.4), D(-0.5, -0.02)), (W(0.4), D(-0.5, -0.02))], z: z + H(0.85), r: K(0.01), .chrome, sides: 6, plan: false)
        b.rect(L, Fr, R, Bk, .hidden); b.line(L, D(-0.5, 0.03), R, D(-0.5, 0.03), .hidden)
        b.inch(inch(27), 27, 24, 29, ["Mounting Height": 30]); b.inch(inch(30), 30, 24, 29, ["Mounting Height": 30])
        b.mm("600", 595, 560, 595, ["Mounting Height": 800])
        return b.item
    }

    static func dishwasher() -> ComponentLibraryItem {
        var b = FB("Dishwasher", .specialtyEquipment, group: "Appliances", keywords: ["dish washer", "undercounter"], "Undercounter dishwasher.")
        b.box("Body", L, R, D(-0.5, 0.03), Bk, K(0), T, .appliance)
        b.box("Door", L, R, Fr, D(-0.5, 0.03), K(0.08), T, .appliance, plan: false)
        b.outline(); b.rect(L, D(-0.5, -0.6), R, Fr, .hidden)
        b.inch(inch(24), 24, 24, 34); b.mm("450", 450, 570, 820); b.mm("600", 600, 570, 820)
        return b.item
    }

    static func microwave(overRange: Bool) -> ComponentLibraryItem {
        var b = FB(overRange ? "Microwave - Over the Range" : "Microwave - Countertop", .specialtyEquipment, group: "Appliances",
                   regions: overRange ? [.usa] : [.global], keywords: ["microwave", "oven", "otr"], instance: ["Mounting Height"],
                   overRange ? "Over-the-range microwave with a built-in vent; Mounting Height is its underside."
                             : "Countertop microwave; Mounting Height is the counter it sits on.")
        let z = P("Mounting Height")
        b.box("Body", L, R, D(-0.5, 0.02), Bk, z, z + H(1), .appliance)
        b.box("Door", W(-0.5, 0.01), W(0.3), Fr, D(-0.5, 0.02), z + 0.02, z + H(1, -0.02), .applianceDark, plan: false)
        b.rect(L, Fr, R, Bk, overRange ? .hidden : .general)
        if overRange {
            b.inch(inch(30), 30, 16, 17, ["Mounting Height": 54])
        } else {
            b.inch("Countertop \(inch(20))", 20, 16, 12, ["Mounting Height": 36]); b.mm("Countertop 500", 500, 400, 300, ["Mounting Height": 900])
        }
        return b.item
    }

    static func hoodChimney() -> ComponentLibraryItem {
        var b = FB("Range Hood - Chimney", .specialtyEquipment, group: "Appliances", keywords: ["kitchen chimney", "cooker hood", "extractor", "exhaust"],
                   instance: ["Mounting Height"], "Wall chimney hood; Mounting Height is the canopy underside, Height runs to the top of the flue cover.")
        let z = P("Mounting Height")
        b.box("Canopy", L, R, Fr, Bk, z, z + 0.06, .appliance)
        b.taper("Hood", K(0), D(0.1), bottom: (W(0.5), D(0.4)), top: (K(0.14), D(0.4, -0.1)), z + 0.06, z + 0.3, .appliance)
        b.box("Flue Cover", K(-0.14), K(0.14), D(0.5, -0.25), Bk, z + 0.3, z + H(1), .appliance)
        b.rect(L, Fr, R, Bk, .hidden); b.line(L, Fr, R, Bk, .hidden); b.line(R, Fr, L, Bk, .hidden)
        b.inch(inch(30), 30, 20, 36, ["Mounting Height": 60]); b.inch(inch(36), 36, 20, 36, ["Mounting Height": 60])
        b.mm("600", 600, 500, 900, ["Mounting Height": 1600]); b.mm("900", 900, 500, 900, ["Mounting Height": 1600])
        return b.item
    }

    static func hoodUnder() -> ComponentLibraryItem {
        var b = FB("Range Hood - Under Cabinet", .specialtyEquipment, group: "Appliances", keywords: ["cooker hood", "extractor", "slim hood"],
                   instance: ["Mounting Height"], "Slim hood fitted under a wall cabinet; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Body", L, R, Fr, Bk, z, z + H(1), .appliance)
        b.rect(L, Fr, R, Bk, .hidden); b.line(L, Fr, R, Bk, .hidden)
        b.inch(inch(30), 30, 20, 6, ["Mounting Height": 58]); b.mm("600", 600, 500, 150, ["Mounting Height": 1500])
        return b.item
    }

    /// Front-loading laundry body with a porthole door.
    static func laundryBody(_ b: inout FB, porthole: Bool) {
        b.box("Body", L, R, D(-0.5, 0.01), Bk, K(0), T, .appliance)
        b.box("Control Panel", W(-0.5, 0.01), W(0.5, -0.01), Fr, D(-0.5, 0.01), H(1, -0.12), H(1, -0.02), .applianceDark, plan: false)
        if porthole {
            b.vDisc("Door", K(0), D(-0.5, -0.02), H(0.45), W(0.3), thickness: 0.05, .applianceDark, sides: 20)
            b.arc(W(-0.32), Fr, W(0.64), 270, 90, .hidden)
        } else {
            b.box("Lid", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.03), D(0.5, -0.15), H(1, -0.005), T, .applianceDark, plan: false)
            b.rect(W(-0.5, 0.03), D(-0.5, 0.03), W(0.5, -0.03), D(0.5, -0.15))
        }
        b.outline()
    }

    static func washerFront() -> ComponentLibraryItem {
        var b = FB("Washing Machine - Front Load", .specialtyEquipment, group: "Laundry", keywords: ["washer", "laundry", "front loader"], "Front-loading washing machine.")
        laundryBody(&b, porthole: true)
        b.inch(inch(27), 27, 31, 39); b.mm("600", 600, 600, 850)
        return b.item
    }

    static func washerTop() -> ComponentLibraryItem {
        var b = FB("Washing Machine - Top Load", .specialtyEquipment, group: "Laundry", keywords: ["washer", "laundry", "top loader"], "Top-loading washing machine.")
        laundryBody(&b, porthole: false)
        b.inch(inch(27), 27, 27, 42); b.mm("540", 540, 560, 950)
        return b.item
    }

    static func dryer() -> ComponentLibraryItem {
        var b = FB("Dryer", .specialtyEquipment, group: "Laundry", keywords: ["tumble dryer", "clothes dryer", "laundry"], "Front-loading clothes dryer.")
        laundryBody(&b, porthole: true)
        b.inch(inch(27), 27, 31, 39); b.mm("600", 600, 600, 850)
        return b.item
    }

    static func washerDryerStack() -> ComponentLibraryItem {
        var b = FB("Washer and Dryer - Stacked", .specialtyEquipment, group: "Laundry", keywords: ["stacked laundry", "laundry tower", "washer dryer"],
                   "Dryer stacked on a front-loading washer.")
        b.box("Washer", L, R, D(-0.5, 0.01), Bk, K(0), H(0.5), .appliance)
        b.box("Dryer", L, R, D(-0.5, 0.01), Bk, H(0.5), T, .appliance)
        b.vDisc("Washer Door", K(0), D(-0.5, -0.02), H(0.22), W(0.3), thickness: 0.05, .applianceDark, sides: 20)
        b.vDisc("Dryer Door", K(0), D(-0.5, -0.02), H(0.72), W(0.3), thickness: 0.05, .applianceDark, sides: 20)
        b.outline(); b.arc(W(-0.32), Fr, W(0.64), 270, 90, .hidden)
        b.inch(inch(27), 27, 31, 77); b.mm("600", 600, 600, 1700)
        return b.item
    }

    static func waterPurifier() -> ComponentLibraryItem {
        var b = FB("Water Purifier - Wall Mounted", .specialtyEquipment, group: "Appliances", regions: [.india, .asia], keywords: ["ro purifier", "water filter"],
                   instance: ["Mounting Height"], "Wall-mounted drinking-water purifier; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Body", L, R, Fr, Bk, z, z + H(1), .plastic)
        b.box("Tap", W(-0.05), W(0.05), D(-0.5, -0.04), Fr, z + H(0.25), z + H(0.3), .plasticDark, plan: false)
        b.rect(L, Fr, R, Bk, .hidden)
        b.any("Standard", 0.3, 0.2, 0.45, ["Mounting Height": 1.2])
        return b.item
    }

    static func wineCooler() -> ComponentLibraryItem {
        var b = FB("Wine Cooler - Undercounter", .specialtyEquipment, group: "Appliances", keywords: ["wine fridge", "beverage centre", "bar"],
                   "Undercounter wine cooler with a glass door.")
        b.box("Body", L, R, D(-0.5, 0.04), Bk, K(0), T, .appliance)
        b.box("Glass Door", W(-0.5, 0.01), W(0.5, -0.01), Fr, D(-0.5, 0.04), K(0.1), H(1, -0.02), .glass, plan: false)
        b.outline(); b.arc(R, D(-0.5, 0.04), W(1), 180, 90, .hidden)
        b.inch(inch(24), 24, 24, 34); b.mm("600", 600, 570, 820)
        return b.item
    }

    static func chestFreezer() -> ComponentLibraryItem {
        var b = FB("Freezer - Chest", .specialtyEquipment, group: "Appliances", keywords: ["deep freezer", "chest freezer", "freezer"], "Chest freezer with a lift-up lid.")
        b.box("Body", L, R, Fr, Bk, K(0), H(1, -0.05), .plastic)
        b.box("Lid", L, R, Fr, Bk, H(1, -0.05), T, .plastic)
        b.outline(); b.rect(W(-0.5, 0.05), D(-0.5, 0.05), W(0.5, -0.05), D(0.5, -0.05))
        b.inch(inch(48), 48, 26, 34); b.mm("1100", 1100, 650, 850)
        return b.item
    }

    static func tvWall() -> ComponentLibraryItem {
        var b = FB("Television - Wall Mounted", .specialtyEquipment, group: "Electronics", keywords: ["tv", "television", "screen", "display", "led"],
                   instance: ["Mounting Height"], "Flat-panel television on a wall bracket; Mounting Height is the screen center (type names are the diagonal).")
        let z = P("Mounting Height")
        b.box("Panel", L, R, D(0.5, -0.06), D(0.5, -0.02), z - H(0.5), z + H(0.5), .screen)
        b.box("Bracket", W(-0.1), W(0.1), D(0.5, -0.02), Bk, z - 0.1, z + 0.1, .steelDark, plan: false)
        b.rect(L, D(0.5, -0.06), R, D(0.5, -0.02))
        for (d, w, h) in [(43.0, 38.0, 22.0), (55, 48.5, 28), (65, 57, 33), (75, 66, 38), (85, 75, 43)] {
            b.inch(inch(d), w, 3, h, ["Mounting Height": 48])
        }
        return b.item
    }

    static func computer() -> ComponentLibraryItem {
        var b = FB("Computer - Monitor and Keyboard", .specialtyEquipment, group: "Electronics", keywords: ["pc", "monitor", "workstation", "desktop computer"],
                   instance: ["Mounting Height"], "Desktop monitor on a stand with keyboard; Mounting Height is the desk top.")
        let z = P("Mounting Height")
        b.box("Stand", W(-0.08), W(0.08), D(0.2), D(0.45), z, z + 0.02, .steelDark, plan: false)
        b.box("Neck", W(-0.02), W(0.02), D(0.35), D(0.4), z, z + 0.15, .steelDark, plan: false)
        b.box("Screen", L, R, D(0.4), Bk, z + 0.1, z + H(1), .screen)
        b.box("Keyboard", W(-0.35), W(0.35), D(-0.5), D(-0.15), z, z + 0.02, .plasticDark)
        b.rect(L, D(0.4), R, Bk); b.rect(W(-0.35), D(-0.5), W(0.35), D(-0.15)); b.rect(W(-0.08), D(0.2), W(0.08), D(0.4), .hidden)
        b.any("Standard Monitor", 0.55, 0.5, 0.45, ["Mounting Height": 0.74]); b.any("Large Monitor", 0.62, 0.5, 0.5, ["Mounting Height": 0.74])
        return b.item
    }
}
