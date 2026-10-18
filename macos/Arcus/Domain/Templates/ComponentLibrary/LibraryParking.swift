import Foundation

// Parking stalls, pavement markings, parking signs and parking equipment. Markings are thin painted solids so they
// show in 3D and schedule as parking; their plan symbols are the striping.
extension LibraryContent {

    static func parking() -> [ComponentLibraryItem] {
        [stallStandard(), stallCompact(), stallAccessible(), stallAngled(), stallParallel(), stallEV(), stallMotorcycle(), wheelStop(),
         arrow(turn: false), arrow(turn: true), accessibleMarking(), crosswalk(),
         sign("Sign - Accessible Parking", .signBlue, shape: 0, keywords: ["handicap sign", "disabled parking", "accessible"]),
         sign("Sign - EV Charging", .signGreen, shape: 0, keywords: ["ev sign", "electric vehicle", "charging"]),
         sign("Sign - Reserved Parking", .signFace, shape: 0, keywords: ["reserved", "permit parking", "visitor"]),
         sign("Sign - No Parking", .signRed, shape: 1, keywords: ["no parking", "no stopping", "prohibition", "tow away"]),
         sign("Sign - Stop", .signRed, shape: 2, keywords: ["stop sign", "traffic sign", "octagon"]),
         sign("Sign - Parking", .signBlue, shape: 3, keywords: ["p sign", "car park", "parking sign"]),
         evPedestal(), boomBarrier(), speedHump(), payStation()]
    }

    /// A painted stripe from (x0, y0) to (x1, y1) (plan), `w` wide, as a thin solid and a plan outline.
    static func stripe(_ b: inout FB, _ name: String, _ a: (LX, LX), _ c: (LX, LX), w: Double, dx: Double, dy: Double, _ m: LM = .marking) {
        // (dx, dy) is the unit normal of the stripe direction.
        let pts: [(LX, LX)] = [(a.0 - dx * w / 2, a.1 - dy * w / 2), (a.0 + dx * w / 2, a.1 + dy * w / 2),
                               (c.0 + dx * w / 2, c.1 + dy * w / 2), (c.0 - dx * w / 2, c.1 - dy * w / 2)]
        b.prism(name, pts, K(0), T, m)
        b.poly(pts)
    }

    /// Side stripes of a 90° stall at the left and right edges, full depth.
    static func sideStripes(_ b: inout FB, w: Double = 0.1) {
        stripe(&b, "Stripe Left", (L, Fr), (L, Bk), w: w, dx: 1, dy: 0)
        stripe(&b, "Stripe Right", (R, Fr), (R, Bk), w: w, dx: 1, dy: 0)
        b.line(L, Fr, R, Fr, .hidden)
    }

    static let stallKeywords = ["parking", "parking space", "parking bay", "car park", "stall", "striping"]

    static func stallStandard() -> ComponentLibraryItem {
        var b = FB("Parking Stall - Standard", .parking, group: "Stalls", keywords: stallKeywords + ["90 degree"],
                   "90° parking stall striping; Width and Depth are the stall, measured to stripe centers.")
        sideStripes(&b)
        b.type("\(ft(9)) x \(ft(18))", .imperial, 2.743, 5.486, 0.003, regions: [.usa])
        b.type("8'-6\" x \(ft(18))", .imperial, 2.591, 5.486, 0.003, regions: [.usa])
        b.mm("2.5 x 5.0 m", 2500, 5000, 3, regions: [.europe, .india, .asia, .global])
        b.mm("2.4 x 4.8 m", 2400, 4800, 3, regions: [.uk, .europe])
        return b.item
    }

    static func stallCompact() -> ComponentLibraryItem {
        var b = FB("Parking Stall - Compact", .parking, group: "Stalls", keywords: stallKeywords + ["small car"], "Compact-car stall with a COMPACT bar at the head.")
        sideStripes(&b)
        stripe(&b, "Compact Bar", (W(-0.3), D(0.5, -0.4)), (W(0.3), D(0.5, -0.4)), w: 0.1, dx: 0, dy: 1)
        b.type("\(ft(8)) x \(ft(16))", .imperial, 2.438, 4.877, 0.003, regions: [.usa])
        b.mm("2.3 x 4.5 m", 2300, 4500, 3, regions: [.europe, .india, .asia])
        return b.item
    }

    /// Simplified wheelchair symbol centered at (cx, cy), size s (plan lines only).
    static func wheelchairSymbol(_ b: inout FB, _ cx: LX, _ cy: LX, _ s: Double) {
        b.circle(cx + (-0.05 * s), cy - 0.12 * s, K(0.22 * s))
        b.circle(cx + 0.05 * s, cy + 0.32 * s, K(0.07 * s))
        b.poly([(cx + 0.03 * s, cy + 0.22 * s), (cx + (-0.02) * s, cy + (-0.02) * s), (cx + 0.2 * s, cy + (-0.02) * s), (cx + 0.3 * s, cy + (-0.3) * s)], closed: false)
        b.line(cx + 0.0 * s, cy + 0.12 * s, cx + 0.18 * s, cy + 0.12 * s)
    }

    static func stallAccessible() -> ComponentLibraryItem {
        var b = FB("Parking Stall - Accessible", .parking, group: "Stalls", keywords: stallKeywords + ["accessible", "handicap", "disabled", "ada", "van accessible"],
                   extra: ["Aisle Width"], "Accessible stall with a hatched access aisle on the right and the access symbol.")
        let a = P("Aisle Width")
        sideStripes(&b)
        stripe(&b, "Aisle Stripe", (R + a, Fr), (R + a, Bk), w: 0.1, dx: 1, dy: 0)
        for i in 0..<8 {
            let f = -0.5 + Double(i) * 0.11
            let pts: [(LX, LX)] = [(R, D(f)), (R, D(f, 0.1)), (R + a, D(f + 0.12, 0.1)), (R + a, D(f + 0.12))]
            b.prism("Hatch \(i + 1)", pts, K(0), T, .marking)
            b.line(R, D(f), R + a, D(f + 0.12))
        }
        b.box("Symbol Field", W(-0.2), W(0.2), D(0.05), D(0.05) + W(0.4), K(0), T, .markingBlue)
        b.rect(W(-0.2), D(0.05), W(0.2), D(0.05) + W(0.4))
        wheelchairSymbol(&b, K(0), D(0.05) + W(0.2), 0.8)
        b.line(R, Fr, R + a, Fr, .hidden)
        b.type("Car \(ft(8)) + \(ft(5)) Aisle", .imperial, 2.438, 5.486, 0.003, ["Aisle Width": 1.524], regions: [.usa])
        b.type("Van \(ft(8)) + \(ft(8)) Aisle", .imperial, 2.438, 5.486, 0.003, ["Aisle Width": 2.438], regions: [.usa])
        b.type("Van \(ft(11)) + \(ft(5)) Aisle", .imperial, 3.353, 5.486, 0.003, ["Aisle Width": 1.524], regions: [.usa])
        b.mm("2.5 m + 1.2 m Aisle", 2500, 5000, 3, ["Aisle Width": 1200], regions: [.uk, .europe])
        b.mm("2.5 m + 1.5 m Aisle", 2500, 5000, 3, ["Aisle Width": 1500], regions: [.europe, .india, .asia, .global])
        return b.item
    }

    static func stallAngled() -> ComponentLibraryItem {
        var b = FB("Parking Stall - Angled", .parking, group: "Stalls", keywords: stallKeywords + ["angled", "diagonal", "60 degree", "45 degree", "echelon"],
                   extra: ["Skew"], "Angled stall: Width is the spacing along the aisle, Depth the depth from the aisle, Skew the stripe's run along the aisle.")
        let sk = P("Skew")
        let hs = sk * 0.5
        for (n, x) in [("Left", L), ("Right", R)] {
            let pts: [(LX, LX)] = [(x - hs - 0.05, Fr), (x - hs + 0.05, Fr), (x + hs + 0.05, Bk), (x + hs - 0.05, Bk)]
            b.prism("Stripe \(n)", pts, K(0), T, .marking)
            b.poly(pts)
        }
        b.line(L - hs, Fr, R - hs, Fr, .hidden)
        func t(_ name: String, _ sz: SZ, stall: Double, len: Double, deg: Double, regions: [LibraryRegion]) {
            let r = deg * .pi / 180
            b.type(name, sz, stall / sin(r), len * sin(r), 0.003, ["Skew": len * cos(r)], regions: regions)
        }
        t("60° \(ft(9)) x \(ft(18))", .imperial, stall: 2.743, len: 5.486, deg: 60, regions: [.usa])
        t("45° \(ft(9)) x \(ft(18))", .imperial, stall: 2.743, len: 5.486, deg: 45, regions: [.usa])
        t("60° 2.5 x 5.0 m", .metric, stall: 2.5, len: 5.0, deg: 60, regions: [.europe, .india, .asia, .uk, .global])
        t("45° 2.5 x 5.0 m", .metric, stall: 2.5, len: 5.0, deg: 45, regions: [.europe, .india, .asia, .uk, .global])
        return b.item
    }

    static func stallParallel() -> ComponentLibraryItem {
        var b = FB("Parking Stall - Parallel", .parking, group: "Stalls", keywords: stallKeywords + ["parallel", "on-street", "kerbside", "curbside"],
                   "Parallel stall: Width along the curb (at the back), Depth across; T-marks at the ends.")
        stripe(&b, "Edge Line", (L, Fr), (R, Fr), w: 0.1, dx: 0, dy: 1)
        stripe(&b, "End Left", (L, Fr), (L, D(-0.5, 0.6)), w: 0.1, dx: 1, dy: 0)
        stripe(&b, "End Right", (R, Fr), (R, D(-0.5, 0.6)), w: 0.1, dx: 1, dy: 0)
        b.line(L, Bk, R, Bk, .hidden)
        b.type("\(ft(22)) x \(ft(8))", .imperial, 6.706, 2.438, 0.003, regions: [.usa])
        b.mm("6.0 x 2.5 m", 6000, 2500, 3, regions: [.europe, .india, .asia, .global]); b.mm("6.0 x 2.0 m", 6000, 2000, 3, regions: [.uk, .europe])
        return b.item
    }

    static func boltPoints(_ cx: LX, _ cy: LX, _ s: Double) -> [(LX, LX)] {
        [(0.1, 0.5), (-0.25, -0.05), (0.0, -0.05), (-0.1, -0.5), (0.25, 0.08), (0.0, 0.08)].map { (cx + $0.0 * s, cy + $0.1 * s) }
    }

    static func stallEV() -> ComponentLibraryItem {
        var b = FB("Parking Stall - EV Charging", .parking, group: "Stalls", keywords: stallKeywords + ["ev", "electric vehicle", "charging bay", "charger"],
                   "EV charging stall: green bay surface with a charging symbol.")
        sideStripes(&b)
        b.box("Bay Surface", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.06), D(0.5, -0.06), K(0), H(0.5), .signGreen, plan: false)
        b.prism("Symbol", boltPoints(K(0), D(0.25), 0.9), H(0.5), T, .marking)
        b.poly(boltPoints(K(0), D(0.25), 0.9))
        b.type("\(ft(9)) x \(ft(18))", .imperial, 2.743, 5.486, 0.004, regions: [.usa])
        b.mm("2.5 x 5.0 m", 2500, 5000, 4, regions: [.europe, .india, .asia, .uk, .global])
        return b.item
    }

    static func stallMotorcycle() -> ComponentLibraryItem {
        var b = FB("Parking Stall - Motorcycle", .parking, group: "Stalls", keywords: stallKeywords + ["motorcycle", "two wheeler", "scooter", "bike parking"],
                   "Two-wheeler stall.")
        sideStripes(&b, w: 0.08)
        b.type("\(ft(4)) x \(ft(8))", .imperial, 1.219, 2.438, 0.003, regions: [.usa])
        b.mm("1.0 x 2.0 m", 1000, 2000, 3, regions: [.india, .asia, .europe, .uk, .global])
        return b.item
    }

    static func wheelStop() -> ComponentLibraryItem {
        var b = FB("Wheel Stop", .parking, group: "Equipment", keywords: ["parking block", "car stop", "kerb stop", "wheel stopper", "tyre stop"],
                   "Precast wheel stop with chamfered edges.")
        b.taper("Block", K(0), K(0), bottom: (W(0.5), D(0.5)), top: (W(0.5, -0.03), D(0.5, -0.04)), K(0), T, .concrete)
        b.outline(); b.rect(W(-0.5, 0.03), D(-0.5, 0.04), W(0.5, -0.03), D(0.5, -0.04))
        b.type(ft(6), .imperial, 1.829, 0.152, 0.102); b.mm("1800", 1800, 150, 100)
        return b.item
    }

    static func arrow(turn: Bool) -> ComponentLibraryItem {
        var b = FB(turn ? "Pavement Arrow - Turn" : "Pavement Arrow - Straight", .parking, group: "Markings",
                   keywords: ["arrow", "road marking", "direction", "one way", "traffic flow"],
                   turn ? "Painted turn arrow (right turn; mirror for left)." : "Painted straight-ahead arrow pointing to the front.")
        let uv: [(Double, Double)] = turn
            ? [(0.1, 0), (0.35, 0), (0.35, 0.55), (0.6, 0.55), (0.6, 0.4), (1.0, 0.7), (0.6, 1.0), (0.6, 0.85), (0.1, 0.85)]
            : [(0.38, 0), (0.62, 0), (0.62, 0.62), (1.0, 0.62), (0.5, 1.0), (0.0, 0.62), (0.38, 0.62)]
        let pts = uv.map { (W($0.0 - 0.5), D(0.5 - $0.1)) }
        b.prism("Arrow", pts, K(0), T, .marking)
        b.poly(pts)
        if turn {
            b.type(ft(8), .imperial, 1.524, 2.438, 0.003); b.mm("5.0 m", 1800, 5000, 3)
        } else {
            b.type(ft(8), .imperial, 0.914, 2.438, 0.003); b.mm("5.0 m", 1200, 5000, 3)
        }
        return b.item
    }

    static func accessibleMarking() -> ComponentLibraryItem {
        var b = FB("Pavement Marking - Accessible Symbol", .parking, group: "Markings", keywords: ["accessible symbol", "wheelchair symbol", "isa", "handicap"],
                   "Painted access symbol on a blue field.")
        b.box("Field", L, R, Fr, Bk, K(0), T, .markingBlue)
        b.outline(); wheelchairSymbol(&b, K(0), K(0), 1.0)
        b.inch(inch(42), 42, 42, 0.12); b.mm("1000", 1000, 1000, 3)
        return b.item
    }

    static func crosswalk() -> ComponentLibraryItem {
        var b = FB("Crosswalk - Zebra", .parking, group: "Markings", keywords: ["pedestrian crossing", "zebra crossing", "crosswalk", "road marking"],
                   "Zebra crossing: Width across the road, Depth the crossing width; eight bars.")
        for i in 0..<8 {
            let x0 = W((2 * Double(i) + 0.5) / 16 - 0.5), x1 = W((2 * Double(i) + 1.5) / 16 - 0.5)
            b.box("Bar \(i + 1)", x0, x1, Fr, Bk, K(0), T, .marking)
            b.rect(x0, Fr, x1, Bk)
        }
        b.line(L, Fr, R, Fr, .hidden); b.line(L, Bk, R, Bk, .hidden)
        b.mm("6000 x 3000", 6000, 3000, 3); b.mm("8000 x 4000", 8000, 4000, 3); b.type("\(ft(20)) x \(ft(10))", .imperial, 6.096, 3.048, 0.003)
        return b.item
    }

    /// Post-mounted sign: `shape` 0 = rectangle, 1 = disc, 2 = octagon, 3 = square. Width is the panel, Height the top.
    static func sign(_ name: String, _ face: LM, shape: Int, keywords: [String]) -> ComponentLibraryItem {
        var b = FB(name, .parking, group: "Signs", keywords: keywords + ["sign", "signage", "parking sign"], extra: ["Panel Height"],
                   "Sign panel on a steel post; Width is the panel and Height its top edge.")
        let ph = P("Panel Height")
        b.cyl("Post", K(0), D(0.5, -0.03), K(0.03), K(0), H(1), .metal)
        switch shape {
        case 0, 3:
            b.box("Panel", L, R, K(-0.005), K(0.005), H(1) - ph, T, face)
            b.box("Border", W(-0.5, -0.005), W(0.5, 0.005), K(0.005), K(0.008), H(1) - ph - 0.005, H(1, 0.005), .signFace, plan: false)
        case 1:
            b.vDisc("Panel", K(0), K(0), H(1) - ph * 0.5, W(0.5), thickness: 0.01, face, sides: 24)
            b.vDisc("Ring Back", K(0), K(0.008), H(1) - ph * 0.5, W(0.5, 0.01), thickness: 0.004, .signFace, sides: 24)
        default:
            let r = 0.5 / cos(22.5 * .pi / 180)
            b.vShape("Panel", ngon(K(0), K(0), W(r), 8, start: 22.5), K(0), K(0), H(1) - ph * 0.5, thickness: 0.01, face)
        }
        b.rect(L, K(-0.01), R, K(0.01)); b.circle(K(0), D(0.5, -0.03), K(0.03))
        switch shape {
        case 0:
            b.inch("\(inch(12)) x \(inch(18))", 12, 3, 84, ["Panel Height": 18]); b.mm("300 x 450", 300, 80, 2100, ["Panel Height": 450])
        case 3:
            b.inch("\(inch(24)) x \(inch(24))", 24, 3, 96, ["Panel Height": 24]); b.mm("600 x 600", 600, 80, 2400, ["Panel Height": 600])
        default:
            b.inch(inch(shape == 2 ? 30 : 24), shape == 2 ? 30 : 24, 3, 96, ["Panel Height": shape == 2 ? 30 : 24])
            b.mm(shape == 2 ? "750" : "600", shape == 2 ? 750 : 600, 80, 2400, ["Panel Height": shape == 2 ? 750 : 600])
        }
        return b.item
    }

    static func evPedestal() -> ComponentLibraryItem {
        var b = FB("EV Charger - Pedestal", .parking, group: "Equipment", keywords: ["ev charger", "charging station", "electric vehicle", "charge point"],
                   "Pedestal electric-vehicle charger; the dual type charges two stalls.")
        b.box("Plinth", W(-0.5, -0.05), W(0.5, 0.05), D(-0.5, -0.05), D(0.5, 0.05), K(0), K(0.1), .concrete)
        b.box("Body", L, R, Fr, Bk, K(0.1), T, .plastic)
        b.box("Screen", W(-0.3), W(0.3), D(-0.5, -0.005), Fr, H(0.7), H(0.88), .screen, plan: false)
        b.box("Holster", W(-0.35), W(-0.05), D(-0.5, -0.06), Fr, H(0.45), H(0.6), .plasticDark, plan: false)
        b.outline(); b.rect(W(-0.5, -0.05), D(-0.5, -0.05), W(0.5, 0.05), D(0.5, 0.05), .hidden)
        b.any("Single", 0.3, 0.25, 1.4); b.any("Dual", 0.45, 0.3, 1.6)
        return b.item
    }

    static func boomBarrier() -> ComponentLibraryItem {
        var b = FB("Boom Barrier", .parking, group: "Equipment", keywords: ["barrier gate", "boom gate", "car park barrier", "arm barrier"],
                   "Barrier cabinet with a lowered boom arm; Width is the whole assembly.")
        b.box("Cabinet", L, W(-0.5, 0.35), Fr, Bk, K(0), K(1.0), .signFace)
        b.box("Boom", W(-0.5, 0.3), R, K(-0.04), K(0.04), K(0.85), K(0.95), .signRed)
        b.rect(L, Fr, W(-0.5, 0.35), Bk); b.rect(W(-0.5, 0.35), K(-0.04), R, K(0.04))
        b.mm("3000", 3350, 300, 1000); b.mm("4500", 4850, 300, 1000); b.type(ft(10), .imperial, 3.4, 0.3, 1.0); b.type(ft(15), .imperial, 4.9, 0.3, 1.0)
        return b.item
    }

    static func speedHump() -> ComponentLibraryItem {
        var b = FB("Speed Hump", .parking, group: "Equipment", keywords: ["speed bump", "road hump", "traffic calming", "speed breaker"],
                   "Round-top speed hump across the road; Width across the road, Depth along travel.")
        let prof: [(LX, LX)] = [(-0.5, 0.0), (-0.3, 0.64), (-0.1, 0.96), (0.1, 0.96), (0.3, 0.64), (0.5, 0.0)].map { (D($0.0), H($0.1)) }
        b.sweep("Hump", [(L, K(0)), (R, K(0))], prof, K(0), .concrete)
        b.outline()
        for f in [-0.3, 0.0, 0.3] { b.poly([(W(f, -0.25), D(0.3)), (W(f), D(-0.3)), (W(f, 0.25), D(0.3))], closed: false) }
        b.mm("3600 x 900", 3600, 900, 75); b.type("\(ft(12)) x \(ft(3))", .imperial, 3.658, 0.914, 0.076)
        return b.item
    }

    static func payStation() -> ComponentLibraryItem {
        var b = FB("Pay Station", .parking, group: "Equipment", keywords: ["parking meter", "ticket machine", "pay and display", "kiosk"], "Parking pay station.")
        b.box("Body", L, R, Fr, Bk, K(0), T, .steelDark)
        b.box("Screen", W(-0.3), W(0.3), D(-0.5, -0.005), Fr, H(0.7), H(0.85), .screen, plan: false)
        b.outline()
        b.any("Standard", 0.45, 0.35, 1.7)
        return b.item
    }
}
