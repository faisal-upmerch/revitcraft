import Foundation

// Plumbing fixtures, bath accessories and toilet partitions.
extension LibraryContent {

    // MARK: Plumbing fixtures

    static func plumbing() -> [ComponentLibraryItem] {
        [wcFloor(), wcWallHung(), wcSquat(), wcAccessible(), urinal(), lavWall(), lavPedestal(), lavVanity(double: false), lavVanity(double: true), lavVessel(),
         tubAlcove(), tubFreestanding(), tubCorner(), showerTray(), showerEnclosure(), showerScreen(), bidet(wall: false), bidet(wall: true), floorDrain(),
         kitchenSink(bowls: 1), kitchenSink(bowls: 2), sinkDrainer(), mopSink(), laundryTub(), drinkingFountain()]
    }

    /// Toilet bowl (an elliptical pan in front of the back `back` meters), seat and lid, from z0 to the rim at `rim`.
    static func wcBowl(_ b: inout FB, back: Double, z0: LX, rim: LX) {
        let cy = D(0, -back / 2), ry = D(0.5, -back / 2), rx = W(0.5)
        b.prism("Pan", ellipse(K(0), cy, rx * 0.85, ry * 0.92, 20), z0, rim - 0.05, .porcelain)
        b.prism("Rim", ellipse(K(0), cy, rx, ry, 24), rim - 0.05, rim, .porcelain)
        b.prism("Seat", ellipse(K(0), cy, rx * 0.98, ry * 0.97, 24), rim, rim + 0.02, .plastic, plan: false)
        b.poly(ellipse(K(0), cy, rx, ry, 24))
        b.poly(ellipse(K(0), cy + 0.03, rx * 0.62, ry * 0.7, 20))
    }

    static func wcFloor() -> ComponentLibraryItem {
        var b = FB("WC - Floor Mounted", .plumbingFixture, group: "Toilets", keywords: ["toilet", "water closet", "commode", "close coupled", "wc"],
                   "Close-coupled floor-mounted toilet with a cistern; the back of the family sits against the wall.")
        wcBowl(&b, back: 0.2, z0: K(0), rim: H(0.52))
        b.box("Cistern", W(-0.46), W(0.46), D(0.5, -0.2), Bk, H(0.5), T, .porcelain)
        b.box("Lid", W(-0.48), W(0.48), D(0.5, -0.21), Bk, T, H(1, 0.02), .porcelain, plan: false)
        b.rrect(W(-0.48), D(0.5, -0.21), W(0.48), Bk, K(0.02))
        b.inch("Elongated \(inch(30))", 20, 30, 30); b.inch("Round \(inch(28))", 20, 28, 30)
        b.mm("Close Coupled 650", 370, 650, 780); b.mm("Close Coupled 700", 380, 700, 800)
        return b.item
    }

    static func wcWallHung() -> ComponentLibraryItem {
        var b = FB("WC - Wall Hung", .plumbingFixture, group: "Toilets", keywords: ["toilet", "wall hung", "concealed cistern", "commode", "wc"],
                   "Wall-hung toilet pan for a concealed cistern; Height is the seat.")
        wcBowl(&b, back: 0.04, z0: H(0.45), rim: H(1, -0.02))
        b.box("Flush Plate", W(-0.4), W(0.4), D(0.5, -0.01), Bk, H(1, 0.5), H(1, 0.66), .chrome)
        b.line(W(-0.5), Bk, W(0.5), Bk)
        b.mm("520", 360, 520, 420); b.mm("560", 370, 560, 420); b.inch(inch(21), 14.5, 21, 16)
        return b.item
    }

    static func wcSquat() -> ComponentLibraryItem {
        var b = FB("WC - Squat Pan", .plumbingFixture, group: "Toilets", regions: [.india, .asia], keywords: ["indian toilet", "squat toilet", "orissa pan", "pan"],
                   "Floor-set squatting pan with footrests.")
        b.box("Pan", L, R, Fr, Bk, K(0), T, .porcelain)
        b.voidPrism("Bowl", ellipse(K(0), D(0.1), W(0.3), D(0.3), 20), H(0.2), H(1, 0.01))
        b.box("Footrest Left", W(-0.5, 0.02), W(-0.5, 0.12), D(-0.5, 0.05), D(-0.5, 0.3), T, H(1, 0.015), .porcelain)
        b.box("Footrest Right", W(0.5, -0.12), W(0.5, -0.02), D(-0.5, 0.05), D(-0.5, 0.3), T, H(1, 0.015), .porcelain)
        b.rrect(L, Fr, R, Bk, K(0.08)); b.poly(ellipse(K(0), D(0.1), W(0.3), D(0.3), 20))
        b.rect(W(-0.5, 0.02), D(-0.5, 0.05), W(-0.5, 0.12), D(-0.5, 0.3))
        b.rect(W(0.5, -0.12), D(-0.5, 0.05), W(0.5, -0.02), D(-0.5, 0.3))
        b.mm("Squat Pan 580", 440, 580, 60); b.mm("Squat Pan 640", 470, 640, 70)
        return b.item
    }

    static func wcAccessible() -> ComponentLibraryItem {
        var b = FB("WC - Accessible", .plumbingFixture, group: "Toilets", keywords: ["accessible toilet", "ada", "disabled", "comfort height", "wc"],
                   "Comfort-height toilet with a rear grab rail for accessible toilet rooms.")
        wcBowl(&b, back: 0.2, z0: K(0), rim: H(0.55))
        b.box("Cistern", W(-0.46), W(0.46), D(0.5, -0.2), Bk, H(0.53), T, .porcelain)
        b.bar("Rear Grab Bar", [(W(-1.2), D(0.5, -0.04)), (W(0.8), D(0.5, -0.04))], z: K(0.84), r: K(0.019), .metal, plan: false)
        b.rrect(W(-0.46), D(0.5, -0.2), W(0.46), Bk, K(0.02))
        b.line(W(-1.2), D(0.5, -0.04), W(0.8), D(0.5, -0.04), .hidden)
        b.inch("Accessible \(inch(30))", 20, 30, 32); b.mm("Accessible 700", 380, 700, 830)
        return b.item
    }

    static func urinal() -> ComponentLibraryItem {
        var b = FB("Urinal - Wall Hung", .plumbingFixture, group: "Urinals", keywords: ["urinal", "mens room", "washroom"],
                   instance: ["Rim Height"], "Wall-hung urinal; Rim Height is the front lip above the floor.")
        let rim = P("Rim Height")
        b.taper("Body", K(0), D(0.05), bottom: (W(0.35), D(0.35)), top: (W(0.5), D(0.45)), rim - 0.35, rim, .porcelain)
        b.box("Back", W(-0.5), W(0.5), D(0.5, -0.06), Bk, rim, rim + H(1, -0.35), .porcelain)
        b.rrect(W(-0.5), D(-0.4), W(0.5), Bk, K(0.05)); b.arc(K(0), D(0.3), W(0.35), 180, 180)
        b.mm("360", 360, 350, 650, ["Rim Height": 600]); b.inch(inch(14), 14, 14, 26, ["Rim Height": 24])
        return b.item
    }

    /// Basin with a bowl cut into its top: the slab from z-depth to z, the bowl void inside, a mixer at the back.
    static func basinTop(_ b: inout FB, _ z: LX, depth: Double, bowlRx: LX, bowlRy: LX, cy: LX, tap: Bool = true, _ m: LM = .porcelain) {
        b.voidPrism("Bowl", ellipse(K(0), cy, bowlRx, bowlRy, 20), z - depth + 0.03, z + 0.01)
        b.poly(ellipse(K(0), cy, bowlRx, bowlRy, 20))
        if tap {
            b.cyl("Mixer", K(0), D(0.5, -0.06), K(0.022), z, z + 0.16, .chrome, plan: false)
            b.bar("Spout", [(K(0), D(0.5, -0.06)), (K(0), D(0.5, -0.17))], z: z + 0.14, r: K(0.012), .chrome, sides: 8, plan: false)
            b.circle(K(0), D(0.5, -0.06), K(0.022))
        }
    }

    static func lavWall() -> ComponentLibraryItem {
        var b = FB("Lavatory - Wall Hung", .plumbingFixture, group: "Lavatories", keywords: ["wash basin", "hand basin", "sink", "lavatory"],
                   instance: ["Rim Height"], "Wall-hung wash basin with a single-lever mixer; Rim Height is the top.")
        let z = P("Rim Height")
        b.box("Basin", L, R, Fr, Bk, z - H(1), z, .porcelain)
        basinTop(&b, z, depth: 0.14, bowlRx: W(0.38), bowlRy: D(0.33), cy: D(-0.05))
        b.rrect(L, Fr, R, Bk, K(0.04))
        b.inch("\(inch(20)) x \(inch(18))", 20, 18, 7, ["Rim Height": 34]); b.inch("\(inch(24)) x \(inch(20))", 24, 20, 7, ["Rim Height": 34])
        b.mm("500 x 400", 500, 400, 170, ["Rim Height": 850]); b.mm("600 x 450", 600, 450, 180, ["Rim Height": 850])
        return b.item
    }

    static func lavPedestal() -> ComponentLibraryItem {
        var b = FB("Lavatory - Pedestal", .plumbingFixture, group: "Lavatories", keywords: ["pedestal basin", "wash basin", "sink"],
                   "Pedestal wash basin; Height is the rim.")
        b.box("Basin", L, R, Fr, Bk, H(1, -0.17), T, .porcelain)
        b.taper("Pedestal", K(0), D(0.15), bottom: (K(0.1), K(0.09)), top: (K(0.08), K(0.08)), K(0), H(1, -0.17), .porcelain, plan: false)
        basinTop(&b, H(1), depth: 0.15, bowlRx: W(0.38), bowlRy: D(0.33), cy: D(-0.05))
        b.rrect(L, Fr, R, Bk, K(0.05))
        b.inch(inch(24), 24, 19, 34); b.mm("550", 550, 450, 850)
        return b.item
    }

    static func lavVanity(double: Bool) -> ComponentLibraryItem {
        var b = FB(double ? "Lavatory - Double Vanity" : "Lavatory - Vanity", .plumbingFixture, group: "Lavatories",
                   keywords: ["vanity", "bathroom cabinet", "wash basin", "sink", "vanity unit"],
                   double ? "Vanity cabinet with countertop and two undermount basins." : "Vanity cabinet with countertop and an undermount basin.")
        b.box("Plinth", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.06), Bk, K(0), K(0.1), .woodDark, plan: false)
        b.box("Cabinet", L, R, D(-0.5, 0.02), Bk, K(0.1), H(1, -0.03), .woodDark)
        b.box("Countertop", L, R, Fr, Bk, H(1, -0.03), T, .stone)
        if double {
            for (i, x) in [W(-0.25), W(0.25)].enumerated() {
                b.voidPrism("Bowl \(i + 1)", ellipse(x, D(-0.05), K(0.2), D(0.3), 20), H(1, -0.14), H(1, 0.01))
                b.poly(ellipse(x, D(-0.05), K(0.2), D(0.3), 20))
                b.cyl("Mixer \(i + 1)", x, D(0.5, -0.06), K(0.022), T, H(1, 0.16), .chrome, plan: false)
                b.circle(x, D(0.5, -0.06), K(0.022))
            }
            b.inch(inch(60), 60, 22, 34); b.inch(inch(72), 72, 22, 34); b.mm("1500", 1500, 520, 850); b.mm("1800", 1800, 520, 850)
        } else {
            basinTop(&b, H(1), depth: 0.14, bowlRx: K(0.2), bowlRy: D(0.3), cy: D(-0.05))
            b.inch(inch(24), 24, 22, 34); b.inch(inch(30), 30, 22, 34); b.inch(inch(36), 36, 22, 34); b.inch(inch(48), 48, 22, 34)
            b.mm("600", 600, 500, 850); b.mm("800", 800, 500, 850); b.mm("1000", 1000, 500, 850); b.mm("1200", 1200, 500, 850)
        }
        b.outline()
        return b.item
    }

    static func lavVessel() -> ComponentLibraryItem {
        var b = FB("Lavatory - Countertop Vessel", .plumbingFixture, group: "Lavatories", keywords: ["vessel sink", "bowl basin", "table top basin"],
                   instance: ["Counter Height"], "Round vessel basin sitting on a counter; Counter Height is the surface it sits on.")
        let z = P("Counter Height")
        b.revolve("Bowl", [(K(0), K(0)), (W(0.3), K(0)), (W(0.5), H(1)), (W(0.46), H(1)), (W(0.28), K(0.02)), (K(0), K(0.02))], K(0), K(0), z, .porcelain)
        b.cyl("Mixer", K(0), D(0.5, 0.06), K(0.022), z, z + 0.3, .chrome, plan: false)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.44)); b.circle(K(0), D(0.5, 0.06), K(0.022))
        b.mm("420 Round", 420, 420, 140, ["Counter Height": 850]); b.inch("\(inch(16)) Round", 16, 16, 5.5, ["Counter Height": 32])
        return b.item
    }

    /// Bathtub: shell with the basin cut into it (rectangular or elliptical).
    static func tubShell(_ b: inout FB, oval: Bool) {
        if oval {
            b.prism("Shell", ellipse(K(0), K(0), W(0.5), D(0.5), 28), K(0), T, .porcelain)
            b.voidPrism("Basin", ellipse(K(0), K(0), W(0.5, -0.06), D(0.5, -0.06), 28), K(0.08), H(1, 0.01))
            b.poly(ellipse(K(0), K(0), W(0.5), D(0.5), 28)); b.poly(ellipse(K(0), K(0), W(0.5, -0.06), D(0.5, -0.06), 28))
        } else {
            b.box("Shell", L, R, Fr, Bk, K(0), T, .porcelain)
            b.voidBox("Basin", W(-0.5, 0.08), W(0.5, -0.08), D(-0.5, 0.08), D(0.5, -0.08), K(0.08), H(1, 0.01))
            b.outline(); b.rrect(W(-0.5, 0.08), D(-0.5, 0.08), W(0.5, -0.08), D(0.5, -0.08), D(0.3))
            b.circle(W(-0.5, 0.2), K(0), K(0.03))
        }
    }

    static func tubAlcove() -> ComponentLibraryItem {
        var b = FB("Bathtub - Alcove", .plumbingFixture, group: "Baths & Showers", keywords: ["bath", "tub", "bathtub", "built-in bath"],
                   "Built-in bathtub for a three-wall alcove.")
        tubShell(&b, oval: false)
        b.inch("\(inch(60)) x \(inch(30))", 60, 30, 20); b.inch("\(inch(60)) x \(inch(32))", 60, 32, 20); b.inch("\(inch(66)) x \(inch(32))", 66, 32, 20)
        b.mm("1500 x 700", 1500, 700, 550); b.mm("1700 x 700", 1700, 700, 550); b.mm("1700 x 750", 1700, 750, 550); b.mm("1800 x 800", 1800, 800, 550)
        return b.item
    }

    static func tubFreestanding() -> ComponentLibraryItem {
        var b = FB("Bathtub - Freestanding", .plumbingFixture, group: "Baths & Showers", keywords: ["bath", "tub", "soaking tub", "oval bath"],
                   "Freestanding oval bathtub.")
        tubShell(&b, oval: true)
        b.inch("\(inch(60)) x \(inch(30))", 60, 30, 23); b.inch("\(inch(67)) x \(inch(31))", 67, 31, 23)
        b.mm("1600 x 750", 1600, 750, 600); b.mm("1700 x 800", 1700, 800, 600)
        return b.item
    }

    static func tubCorner() -> ComponentLibraryItem {
        var b = FB("Bathtub - Corner", .plumbingFixture, group: "Baths & Showers", keywords: ["corner bath", "tub", "quadrant bath"],
                   "Corner bathtub with a curved front; the corner is at the back left.")
        let outline: [(LX, LX)] = [(L, Bk)] + ellipse(L, Bk, W(1), D(1), 12, from: 270, to: 360)
        let inner: [(LX, LX)] = [(L + 0.08, Bk - 0.08)] + ellipse(L + 0.08, Bk - 0.08, W(1, -0.2), D(1, -0.2), 12, from: 270, to: 360)
        b.prism("Shell", outline, K(0), T, .porcelain)
        b.voidPrism("Basin", inner, K(0.08), H(1, 0.01))
        b.poly(outline); b.poly(inner)
        b.mm("1400 x 1400", 1400, 1400, 550); b.mm("1500 x 1500", 1500, 1500, 550); b.inch("\(inch(60)) x \(inch(60))", 60, 60, 21)
        return b.item
    }

    static func showerTray() -> ComponentLibraryItem {
        var b = FB("Shower Tray", .plumbingFixture, group: "Baths & Showers", keywords: ["shower base", "shower pan", "shower"], "Low-profile shower tray with a drain.")
        b.box("Tray", L, R, Fr, Bk, K(0), T, .porcelain)
        b.outline(); b.line(L, Fr, R, Bk); b.line(L, Bk, R, Fr); b.circle(K(0), K(0), K(0.05))
        b.inch("\(inch(36)) x \(inch(36))", 36, 36, 2); b.inch("\(inch(48)) x \(inch(36))", 48, 36, 2); b.inch("\(inch(60)) x \(inch(32))", 60, 32, 2)
        b.mm("800 x 800", 800, 800, 40); b.mm("900 x 900", 900, 900, 40); b.mm("1200 x 800", 1200, 800, 40); b.mm("1400 x 900", 1400, 900, 40)
        return b.item
    }

    static func showerEnclosure() -> ComponentLibraryItem {
        var b = FB("Shower Enclosure - Glass", .plumbingFixture, group: "Baths & Showers", keywords: ["shower cubicle", "shower", "glass enclosure"],
                   "Shower tray with a framed glass return and hinged door; Height is the glass top.")
        b.box("Tray", L, R, Fr, Bk, K(0), K(0.04), .porcelain)
        b.box("Return Panel", L, W(-0.5, 0.01), Fr, Bk, K(0.04), T, .glass)
        b.box("Fixed Panel", W(-0.5, 0.01), W(0.5, -0.6), Fr, D(-0.5, 0.01), K(0.04), T, .glass)
        b.box("Door", W(0.5, -0.6), R, Fr, D(-0.5, 0.01), K(0.04), T, .glass, plan: false)
        b.cyl("Shower Head", W(0.2), D(0.5, -0.2), K(0.1), K(2.05), K(2.07), .chrome, plan: false)
        b.outline(); b.line(L, Fr, R, Bk); b.line(L, Bk, R, Fr)
        b.arc(R, Fr, K(0.6), 180, 90, .swing); b.line(R, Fr, R, D(-0.5, -0.6), .swing)
        b.mm("900 x 900", 900, 900, 2000); b.mm("1200 x 900", 1200, 900, 2000)
        b.inch("\(inch(36)) x \(inch(36))", 36, 36, 78); b.inch("\(inch(48)) x \(inch(36))", 48, 36, 78)
        return b.item
    }

    static func showerScreen() -> ComponentLibraryItem {
        var b = FB("Shower Screen - Walk-In", .plumbingFixture, group: "Baths & Showers", keywords: ["wet room", "walk-in shower", "glass screen"],
                   "Fixed glass walk-in shower screen on a floor channel with a wall-to-ceiling stay bar.")
        b.box("Glass", L, R, D(-0.005), D(0.005), K(0.02), T, .glass)
        b.box("Channel", L, R, D(-0.02), D(0.02), K(0), K(0.02), .chrome)
        b.bar("Stay Bar", [(R, K(0)), (R, D(0.5, 0.2))], z: H(1, -0.1), r: K(0.01), .chrome, sides: 6, plan: false)
        b.rect(L, D(-0.02), R, D(0.02))
        b.mm("1200", 1200, 40, 2000); b.inch(inch(48), 48, 1.5, 78)
        return b.item
    }

    static func bidet(wall: Bool) -> ComponentLibraryItem {
        var b = FB(wall ? "Bidet - Wall Hung" : "Bidet - Floor Mounted", .plumbingFixture, group: "Toilets", regions: [.europe, .asia],
                   keywords: ["bidet", "douche"], wall ? "Wall-hung bidet with a tap." : "Floor-mounted bidet with a tap.")
        if wall { wcBowl(&b, back: 0.04, z0: H(0.4), rim: T) } else { wcBowl(&b, back: 0.05, z0: K(0), rim: T) }
        b.cyl("Tap", K(0), D(0.5, -0.05), K(0.02), T, H(1, 0.12), .chrome, plan: false)
        b.line(W(-0.5), Bk, W(0.5), Bk)
        if wall { b.mm("520", 360, 520, 400) } else { b.mm("560", 370, 560, 400); b.inch(inch(22), 15, 22, 16) }
        return b.item
    }

    static func floorDrain() -> ComponentLibraryItem {
        var b = FB("Floor Drain", .plumbingFixture, group: "Drains", keywords: ["floor trap", "gully", "nahani trap", "grating"], "Square floor drain grate.")
        b.box("Grate", L, R, Fr, Bk, K(0), T, .chrome)
        b.outline()
        for f in [-0.25, 0.0, 0.25] { b.line(W(f), D(-0.4), W(f), D(0.4)) }
        b.mm("100", 100, 100, 5); b.mm("150", 150, 150, 5); b.inch(inch(4), 4, 4, 0.25); b.inch(inch(6), 6, 6, 0.25)
        return b.item
    }

    static func kitchenSink(bowls: Int) -> ComponentLibraryItem {
        var b = FB(bowls == 1 ? "Kitchen Sink - Single Bowl" : "Kitchen Sink - Double Bowl", .plumbingFixture, group: "Sinks",
                   keywords: ["kitchen sink", "sink", "bowl", "stainless"], instance: ["Counter Height"],
                   "Drop-in stainless kitchen sink with a mixer; Counter Height is the worktop.")
        let z = P("Counter Height")
        b.box("Deck", L, R, Fr, Bk, z, z + 0.01, .metal)
        if bowls == 1 {
            b.voidBox("Bowl", W(-0.5, 0.04), W(0.5, -0.04), D(-0.5, 0.04), D(0.5, -0.08), z - 0.01, z + 0.02)
            b.box("Basin", W(-0.5, 0.04), W(0.5, -0.04), D(-0.5, 0.04), D(0.5, -0.08), z - 0.2, z - 0.19, .metal, plan: false)
            b.rrect(W(-0.5, 0.04), D(-0.5, 0.04), W(0.5, -0.04), D(0.5, -0.08), K(0.03)); b.circle(K(0), D(-0.02), K(0.04))
        } else {
            for (n, x0, x1) in [("Left", W(-0.5, 0.04), W(0, -0.02)), ("Right", W(0, 0.02), W(0.5, -0.04))] {
                b.voidBox("Bowl \(n)", x0, x1, D(-0.5, 0.04), D(0.5, -0.08), z - 0.01, z + 0.02)
                b.box("Basin \(n)", x0, x1, D(-0.5, 0.04), D(0.5, -0.08), z - 0.2, z - 0.19, .metal, plan: false)
                b.rrect(x0, D(-0.5, 0.04), x1, D(0.5, -0.08), K(0.03))
            }
        }
        b.cyl("Mixer", K(0), D(0.5, -0.04), K(0.022), z, z + 0.3, .chrome, plan: false)
        b.outline(); b.circle(K(0), D(0.5, -0.04), K(0.022))
        if bowls == 1 {
            b.inch("\(inch(25)) x \(inch(22))", 25, 22, 8, ["Counter Height": 36]); b.inch("\(inch(30)) x \(inch(22))", 30, 22, 8, ["Counter Height": 36])
            b.mm("500 x 500", 500, 500, 200, ["Counter Height": 900]); b.mm("600 x 500", 600, 500, 200, ["Counter Height": 900])
        } else {
            b.inch("\(inch(33)) x \(inch(22))", 33, 22, 8, ["Counter Height": 36]); b.inch("\(inch(36)) x \(inch(22))", 36, 22, 8, ["Counter Height": 36])
            b.mm("800 x 500", 800, 500, 200, ["Counter Height": 900]); b.mm("1160 x 500", 1160, 500, 200, ["Counter Height": 900])
        }
        return b.item
    }

    static func sinkDrainer() -> ComponentLibraryItem {
        var b = FB("Kitchen Sink - With Drainer", .plumbingFixture, group: "Sinks", regions: [.europe, .uk, .india, .asia],
                   keywords: ["kitchen sink", "drainboard", "draining board", "sink"], instance: ["Counter Height"],
                   "Inset sink with a ribbed draining board on the right; Counter Height is the worktop.")
        let z = P("Counter Height")
        b.box("Deck", L, R, Fr, Bk, z, z + 0.01, .metal)
        b.voidBox("Bowl", W(-0.5, 0.04), W(-0.5, 0.44), D(-0.5, 0.05), D(0.5, -0.09), z - 0.01, z + 0.02)
        b.box("Basin", W(-0.5, 0.04), W(-0.5, 0.44), D(-0.5, 0.05), D(0.5, -0.09), z - 0.2, z - 0.19, .metal, plan: false)
        b.cyl("Mixer", W(-0.5, 0.24), D(0.5, -0.045), K(0.022), z, z + 0.3, .chrome, plan: false)
        b.outline(); b.rrect(W(-0.5, 0.04), D(-0.5, 0.05), W(-0.5, 0.44), D(0.5, -0.09), K(0.03))
        for i in 0..<6 { b.line(W(-0.5, 0.52 + 0.04 * Double(i)), D(-0.5, 0.08), W(-0.5, 0.52 + 0.04 * Double(i)), D(0.5, -0.12)) }
        b.circle(W(-0.5, 0.24), D(0.5, -0.045), K(0.022))
        b.mm("860 x 500", 860, 500, 200, ["Counter Height": 900]); b.mm("1000 x 500", 1000, 500, 200, ["Counter Height": 900])
        b.mm("1160 x 500", 1160, 500, 200, ["Counter Height": 900])
        return b.item
    }

    static func mopSink() -> ComponentLibraryItem {
        var b = FB("Mop Sink", .plumbingFixture, group: "Sinks", keywords: ["janitor sink", "service sink", "utility sink", "mop basin"],
                   "Floor-mounted mop basin with a wall faucet.")
        b.box("Basin", L, R, Fr, Bk, K(0), T, .stone)
        b.voidBox("Well", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.05), D(0.5, -0.05), K(0.05), H(1, 0.01))
        b.cyl("Faucet", K(0), D(0.5, 0.02), K(0.03), K(0.8), K(0.9), .chrome, plan: false)
        b.outline(); b.rect(W(-0.5, 0.05), D(-0.5, 0.05), W(0.5, -0.05), D(0.5, -0.05)); b.circle(K(0), K(0), K(0.04))
        b.inch("\(inch(24)) x \(inch(24))", 24, 24, 10); b.mm("600 x 600", 600, 600, 250)
        return b.item
    }

    static func laundryTub() -> ComponentLibraryItem {
        var b = FB("Laundry Tub", .plumbingFixture, group: "Sinks", keywords: ["utility tub", "laundry sink", "wash tub"], "Freestanding laundry tub on legs.")
        legs(&b, inset: 0.03, size: 0.04, K(0), H(1, -0.3), .plastic)
        b.box("Tub", L, R, Fr, Bk, H(1, -0.3), T, .plastic)
        b.voidBox("Well", W(-0.5, 0.04), W(0.5, -0.04), D(-0.5, 0.04), D(0.5, -0.08), H(1, -0.27), H(1, 0.01))
        b.outline(); b.rect(W(-0.5, 0.04), D(-0.5, 0.04), W(0.5, -0.04), D(0.5, -0.08))
        b.inch(inch(24), 24, 22, 34); b.mm("600", 600, 550, 880)
        return b.item
    }

    static func drinkingFountain() -> ComponentLibraryItem {
        var b = FB("Drinking Fountain - Wall", .plumbingFixture, group: "Sinks", keywords: ["water fountain", "bubbler", "drinking water"],
                   instance: ["Rim Height"], "Wall-mounted drinking fountain; Rim Height is the spout.")
        let z = P("Rim Height")
        b.box("Body", L, R, Fr, Bk, z - H(1), z, .metal)
        b.voidBox("Basin", W(-0.5, 0.04), W(0.5, -0.04), D(-0.5, 0.04), D(0.5, -0.06), z - 0.06, z + 0.01)
        b.rrect(L, Fr, R, Bk, K(0.04)); b.rect(W(-0.5, 0.04), D(-0.5, 0.04), W(0.5, -0.04), D(0.5, -0.06))
        b.inch(inch(18), 18, 18, 8, ["Rim Height": 36]); b.mm("450", 450, 450, 200, ["Rim Height": 900])
        return b.item
    }

    // MARK: Bath accessories

    static func bathAccessories() -> [ComponentLibraryItem] {
        [mirrorRect(), mirrorRound(), grabBar(), grabBarL(), grabBarFold(), towelBar(), paperHolder(), soapDispenser(), handDryer(), towelDispenser(),
         babyChanger(), toiletPartition(accessible: false), toiletPartition(accessible: true), urinalScreen()]
    }

    /// Wall-mounted item facing -Y with its back on the family's back face (+Y), bottom at Mounting Height.
    static func wallItem(_ b: inout FB, _ name: String, _ m: LM) {
        let z = P("Mounting Height")
        b.box(name, L, R, Fr, Bk, z, z + H(1), m)
        b.rect(L, Fr, R, Bk)
    }

    static func mirrorRect() -> ComponentLibraryItem {
        var b = FB("Mirror - Rectangular", .specialtyEquipment, group: "Bath Accessories", keywords: ["mirror", "bathroom mirror", "vanity mirror"],
                   instance: ["Mounting Height"], "Wall mirror; Mounting Height is the bottom edge.")
        wallItem(&b, "Mirror", .mirror)
        b.inch("\(inch(24)) x \(inch(36))", 24, 1, 36, ["Mounting Height": 40]); b.inch("\(inch(36)) x \(inch(30))", 36, 1, 30, ["Mounting Height": 40])
        b.mm("600 x 800", 600, 25, 800, ["Mounting Height": 1000]); b.mm("900 x 700", 900, 25, 700, ["Mounting Height": 1100])
        b.mm("1200 x 800", 1200, 25, 800, ["Mounting Height": 1050])
        return b.item
    }

    static func mirrorRound() -> ComponentLibraryItem {
        var b = FB("Mirror - Round", .specialtyEquipment, group: "Bath Accessories", keywords: ["mirror", "round mirror"],
                   instance: ["Mounting Height"], "Round wall mirror; Mounting Height is the center.")
        b.vDisc("Mirror", K(0), K(0), P("Mounting Height"), W(0.5), thickness: 0.02, .mirror, sides: 32)
        b.outline()
        b.inch(inch(24), 24, 1, 24, ["Mounting Height": 60]); b.mm("600", 600, 25, 600, ["Mounting Height": 1500])
        return b.item
    }

    static func grabBar() -> ComponentLibraryItem {
        var b = FB("Grab Bar - Straight", .specialtyEquipment, group: "Bath Accessories", keywords: ["grab rail", "support rail", "accessible", "ada"],
                   instance: ["Mounting Height"], "Straight grab bar; Mounting Height is the bar center line.")
        let z = P("Mounting Height")
        b.bar("Bar", [(W(-0.5, 0.03), D(-0.5, 0.02)), (W(0.5, -0.03), D(-0.5, 0.02))], z: z, r: H(0.5), .metal)
        b.cyl("Flange Left", W(-0.5, 0.035), D(0.5, -0.01), K(0.035), z - 0.035, z + 0.035, .metal, plan: false)
        b.box("Post Left", W(-0.5, 0.025), W(-0.5, 0.045), D(-0.5, 0.02), Bk, z - 0.01, z + 0.01, .metal, plan: false)
        b.box("Post Right", W(0.5, -0.045), W(0.5, -0.025), D(-0.5, 0.02), Bk, z - 0.01, z + 0.01, .metal, plan: false)
        b.rect(W(-0.5, 0.03), D(-0.5, 0.005), W(0.5, -0.03), D(-0.5, 0.035)); b.line(W(-0.5, 0.035), D(-0.5, 0.035), W(-0.5, 0.035), Bk)
        b.line(W(0.5, -0.035), D(-0.5, 0.035), W(0.5, -0.035), Bk)
        for (n, w) in [(18.0, 18.0), (24, 24), (36, 36), (42, 42)] { b.inch(inch(n), w, 3, 1.5, ["Mounting Height": 34]) }
        for w in [300.0, 450, 600, 900] { b.mm("\(Int(w))", w, 75, 35, ["Mounting Height": 800]) }
        return b.item
    }

    static func grabBarL() -> ComponentLibraryItem {
        var b = FB("Grab Bar - L-Shaped", .specialtyEquipment, group: "Bath Accessories", keywords: ["grab rail", "L rail", "shower rail", "accessible"],
                   instance: ["Mounting Height"], "L-shaped grab bar: horizontal run with a vertical leg on the right; Mounting Height is the horizontal bar.")
        let z = P("Mounting Height")
        b.bar("Horizontal", [(W(-0.5), D(-0.5, 0.02)), (W(0.5, -0.02), D(-0.5, 0.02))], z: z, r: K(0.017), .metal)
        b.cyl("Vertical", W(0.5, -0.02), D(-0.5, 0.02), K(0.017), z, z + H(1), .metal)
        b.rect(W(-0.5), D(-0.5, 0.005), R, D(-0.5, 0.035)); b.line(W(-0.5, 0.02), D(-0.5, 0.035), W(-0.5, 0.02), Bk)
        b.mm("600 x 600", 600, 75, 600, ["Mounting Height": 800]); b.inch("\(inch(24)) x \(inch(24))", 24, 3, 24, ["Mounting Height": 34])
        return b.item
    }

    static func grabBarFold() -> ComponentLibraryItem {
        var b = FB("Grab Bar - Fold-Down", .specialtyEquipment, group: "Bath Accessories", keywords: ["hinged rail", "drop-down rail", "accessible", "toilet"],
                   instance: ["Mounting Height"], "Hinged support rail projecting from the wall (Depth is the projection); shown down.")
        let z = P("Mounting Height")
        b.box("Wall Plate", L, R, D(0.5, -0.02), Bk, z - 0.1, z + 0.1, .metal)
        b.bar("Rail", [(K(0), D(0.5, -0.02)), (K(0), D(-0.5, 0.02))], z: z, r: K(0.017), .metal)
        b.rect(L, D(0.5, -0.02), R, Bk); b.rect(K(-0.017), Fr, K(0.017), D(0.5, -0.02))
        b.mm("750", 100, 750, 200, ["Mounting Height": 780]); b.mm("900", 100, 900, 200, ["Mounting Height": 780])
        b.inch(inch(30), 4, 30, 8, ["Mounting Height": 31])
        return b.item
    }

    static func towelBar() -> ComponentLibraryItem {
        var b = FB("Towel Bar", .specialtyEquipment, group: "Bath Accessories", keywords: ["towel rail", "towel rod", "hanger"],
                   instance: ["Mounting Height"], "Wall towel bar; Mounting Height is the bar.")
        let z = P("Mounting Height")
        b.bar("Bar", [(L, D(-0.5, 0.012)), (R, D(-0.5, 0.012))], z: z, r: K(0.01), .chrome)
        b.box("Bracket Left", W(-0.5, 0.02), W(-0.5, 0.035), D(-0.5, 0.01), Bk, z - 0.01, z + 0.01, .chrome, plan: false)
        b.box("Bracket Right", W(0.5, -0.035), W(0.5, -0.02), D(-0.5, 0.01), Bk, z - 0.01, z + 0.01, .chrome, plan: false)
        b.rect(L, Fr, R, D(-0.5, 0.025)); b.line(W(-0.5, 0.03), D(-0.5, 0.025), W(-0.5, 0.03), Bk); b.line(W(0.5, -0.03), D(-0.5, 0.025), W(0.5, -0.03), Bk)
        b.inch(inch(18), 18, 3, 1, ["Mounting Height": 42]); b.inch(inch(24), 24, 3, 1, ["Mounting Height": 42])
        b.mm("450", 450, 75, 25, ["Mounting Height": 1100]); b.mm("600", 600, 75, 25, ["Mounting Height": 1100])
        return b.item
    }

    static func smallWallItem(_ name: String, _ keywords: [String], _ desc: String, _ m: LM, w: Double, d: Double, h: Double, mh: Double) -> ComponentLibraryItem {
        var b = FB(name, .specialtyEquipment, group: "Bath Accessories", keywords: keywords, instance: ["Mounting Height"], desc + " Mounting Height is its underside.")
        wallItem(&b, "Body", m)
        b.any("Standard", w, d, h, ["Mounting Height": mh])
        return b.item
    }

    static func paperHolder() -> ComponentLibraryItem {
        var b = FB("Toilet Paper Holder", .specialtyEquipment, group: "Bath Accessories", keywords: ["toilet roll holder", "tissue holder"],
                   instance: ["Mounting Height"], "Wall toilet-roll holder; Mounting Height is the roll center.")
        let z = P("Mounting Height")
        b.box("Plate", L, R, D(0.5, -0.01), Bk, z - 0.03, z + 0.03, .chrome)
        b.bar("Roll", [(W(-0.4), K(0)), (W(0.4), K(0))], z: z, r: K(0.055), .plastic)
        b.rect(W(-0.4), D(-0.5), W(0.4), D(0.5, -0.01)); b.line(L, Bk, R, Bk)
        b.any("Standard", 0.15, 0.12, 0.12, ["Mounting Height": 0.7])
        return b.item
    }

    static func soapDispenser() -> ComponentLibraryItem {
        smallWallItem("Soap Dispenser", ["soap", "sanitizer", "hand wash"], "Wall-mounted soap dispenser.", .plastic, w: 0.11, d: 0.1, h: 0.2, mh: 1.0)
    }
    static func handDryer() -> ComponentLibraryItem {
        smallWallItem("Hand Dryer", ["hand drier", "air dryer", "washroom"], "Wall-mounted hand dryer.", .appliance, w: 0.3, d: 0.2, h: 0.3, mh: 1.0)
    }
    static func towelDispenser() -> ComponentLibraryItem {
        smallWallItem("Paper Towel Dispenser", ["towel dispenser", "c-fold", "washroom"], "Surface-mounted paper towel dispenser.", .plastic, w: 0.3, d: 0.13, h: 0.4, mh: 1.2)
    }
    static func babyChanger() -> ComponentLibraryItem {
        var b = FB("Baby Changing Station", .specialtyEquipment, group: "Bath Accessories", keywords: ["baby changer", "diaper station", "nappy change"],
                   instance: ["Mounting Height"], "Fold-down baby changing station, shown open; Mounting Height is its top surface.")
        let z = P("Mounting Height")
        b.box("Housing", L, R, D(0.5, -0.1), Bk, z - 0.45, z + 0.05, .plastic)
        b.box("Table", L, R, Fr, D(0.5, -0.1), z - 0.04, z, .plastic)
        b.outline(); b.line(L, D(0.5, -0.1), R, D(0.5, -0.1))
        b.any("Standard", 0.9, 0.55, 0.5, ["Mounting Height": 0.86])
        return b.item
    }

    static func toiletPartition(accessible: Bool) -> ComponentLibraryItem {
        var b = FB(accessible ? "Toilet Partition - Accessible Stall" : "Toilet Partition - Standard Stall", .specialtyEquipment, group: "Toilet Partitions",
                   keywords: ["toilet cubicle", "stall", "washroom partition", "compartment"],
                   "Floor-mounted toilet compartment: side panels, front with an in-swinging door; Width x Depth is the stall.")
        let z0 = K(0.3), z1 = T
        b.box("Side Left", L, W(-0.5, 0.025), Fr, Bk, z0, z1, .laminate)
        b.box("Side Right", W(0.5, -0.025), R, Fr, Bk, z0, z1, .laminate)
        b.box("Front Pilaster", W(-0.5, 0.025), W(-0.5, 0.1), Fr, D(-0.5, 0.025), K(0), K(2.0), .laminate)
        b.box("Door", R - 0.025 - (accessible ? 0.9 : 0.6), W(0.5, -0.025), Fr, D(-0.5, 0.025), z0, z1, .lacquer, plan: false)
        b.box("Head Rail", L, R, D(-0.5, 0.005), D(-0.5, 0.02), K(1.95), K(2.0), .metal, plan: false)
        b.rect(L, Fr, W(-0.5, 0.025), Bk); b.rect(W(0.5, -0.025), Fr, R, Bk); b.rect(W(-0.5, 0.025), Fr, W(-0.5, 0.1), D(-0.5, 0.025))
        let dw = accessible ? 0.9 : 0.6
        b.line(W(0.5, -0.025), Fr, W(0.5, -0.025), Fr + dw, .swing)
        b.arc(W(0.5, -0.025), Fr, K(dw), 90, 90, .swing)
        if accessible {
            b.inch("\(inch(60)) x \(inch(60))", 60, 60, 70); b.mm("1500 x 1800", 1500, 1800, 1800)
        } else {
            b.inch("\(inch(36)) x \(inch(60))", 36, 60, 70); b.mm("900 x 1500", 900, 1500, 1800)
        }
        return b.item
    }

    static func urinalScreen() -> ComponentLibraryItem {
        var b = FB("Urinal Screen", .specialtyEquipment, group: "Toilet Partitions", keywords: ["privacy screen", "urinal divider", "modesty panel"],
                   "Wall-hung privacy screen between urinals (Depth is the projection).")
        b.box("Panel", W(-0.5), W(0.5), Fr, Bk, K(0.3), T, .laminate)
        b.outline()
        b.any("Standard", 0.025, 0.45, 1.5)
        return b.item
    }
}
