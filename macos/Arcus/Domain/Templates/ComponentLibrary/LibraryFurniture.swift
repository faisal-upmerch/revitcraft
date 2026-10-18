import Foundation

// Living, dining, bedroom, kids and storage furniture.
extension LibraryContent {

    // MARK: Living

    static func living() -> [ComponentLibraryItem] {
        [sofa(2), sofa(3), sofa(4), sectional(), armchair(), recliner(), loungeChair(), ottoman(), pouf(),
         coffeeTableRect(), coffeeTableRound(), sideTable(), consoleTable(), tvUnit(), rug(), diwan(), floorTable(), floorCushion(),
         pianoUpright(), pianoGrand(), beanBag(), swingJhoola(), entryBench(), foldingScreen()]
    }

    static func sofa(_ n: Int) -> ComponentLibraryItem {
        var b = FB("Sofa - \(n) Seat", .furniture, group: "Living", keywords: ["couch", "settee", "lounge", "loveseat"],
                   "Upholstered \(n)-seat sofa with loose seat and back cushions.")
        let arm = 0.16, back = 0.2
        roundLegs(&b, inset: 0.06, r: 0.02, K(0), K(0.1), .woodDark)
        b.box("Base", L, R, Fr, Bk, K(0.1), H(0.45), .fabric)
        b.box("Back", L, R, D(0.5, -back), Bk, H(0.45), T, .fabric)
        b.box("Arm Left", L, W(-0.5, arm), Fr, D(0.5, -back), H(0.45), H(0.72), .fabric)
        b.box("Arm Right", W(0.5, -arm), R, Fr, D(0.5, -back), H(0.45), H(0.72), .fabric)
        let div = divisions(n, arm: arm)
        for i in 0..<n {
            b.box("Seat Cushion \(i + 1)", div[i] + 0.005, div[i + 1] - 0.005, D(-0.5, 0.02), D(0.5, -back), H(0.45), H(0.57), .fabric)
            b.box("Back Cushion \(i + 1)", div[i] + 0.005, div[i + 1] - 0.005, D(0.5, -back - 0.15), D(0.5, -back), H(0.57), H(0.93), .fabric, plan: false)
        }
        b.rrect(L, Fr, R, Bk, K(0.04))
        b.line(W(-0.5, arm), D(0.5, -back), W(0.5, -arm), D(0.5, -back))
        b.line(W(-0.5, arm), Fr, W(-0.5, arm), D(0.5, -back))
        b.line(W(0.5, -arm), Fr, W(0.5, -arm), D(0.5, -back))
        b.line(W(-0.5, arm), D(0.5, -back - 0.15), W(0.5, -arm), D(0.5, -back - 0.15))
        for i in 1..<n { b.line(div[i], D(-0.5, 0.02), div[i], D(0.5, -back)) }
        switch n {
        case 2:
            b.inch("2 Seat \(inch(60))", 60, 36, 34); b.inch("2 Seat \(inch(72))", 72, 36, 34)
            b.mm("2 Seat 1500", 1500, 900, 850); b.mm("2 Seat 1800", 1800, 900, 850)
        case 3:
            b.inch("3 Seat \(inch(84))", 84, 38, 34); b.inch("3 Seat \(inch(90))", 90, 38, 34)
            b.mm("3 Seat 2100", 2100, 950, 850); b.mm("3 Seat 2300", 2300, 950, 850)
        default:
            b.inch("4 Seat \(inch(96))", 96, 38, 34); b.inch("4 Seat \(inch(108))", 108, 38, 34)
            b.mm("4 Seat 2600", 2600, 950, 850); b.mm("4 Seat 2800", 2800, 950, 850)
        }
        return b.item
    }

    static func sectional() -> ComponentLibraryItem {
        var b = FB("Sofa - L-Shaped Sectional", .furniture, group: "Living", keywords: ["couch", "corner sofa", "chaise"],
                   extra: ["Seat Depth"], "Corner sectional sofa with the return on the left.")
        let sd = P("Seat Depth"), back = 0.2
        b.box("Main Base", L, R, Bk - sd, Bk, K(0.1), H(0.45), .fabric)
        b.box("Return Base", L, L + sd, Fr, Bk - sd, K(0.1), H(0.45), .fabric)
        b.box("Back", L, R, D(0.5, -back), Bk, K(0.1), T, .fabric)
        b.box("Return Back", L, W(-0.5, back), Fr, D(0.5, -back), K(0.1), T, .fabric)
        b.box("Arm", W(0.5, -0.16), R, Bk - sd, D(0.5, -back), K(0.1), H(0.72), .fabric)
        b.box("Main Cushion", W(-0.5, back), W(0.5, -0.16), Bk - sd + 0.02, D(0.5, -back), H(0.45), H(0.57), .fabric)
        b.box("Return Cushion", W(-0.5, back), L + sd - 0.02, Fr + 0.02, Bk - sd, H(0.45), H(0.57), .fabric)
        b.cyl("Foot 1", R - 0.06, Bk - sd + 0.06, K(0.02), K(0), K(0.1), .woodDark, plan: false)
        b.cyl("Foot 2", L + 0.06, Fr + 0.06, K(0.02), K(0), K(0.1), .woodDark, plan: false)
        b.poly([(L, Fr), (L + sd, Fr), (L + sd, Bk - sd), (R, Bk - sd), (R, Bk), (L, Bk)])
        b.line(W(-0.5, back), Fr, W(-0.5, back), D(0.5, -back))
        b.line(W(-0.5, back), D(0.5, -back), W(0.5, -0.16), D(0.5, -back))
        b.line(W(0.5, -0.16), Bk - sd, W(0.5, -0.16), D(0.5, -back))
        b.line(W(-0.5, back), Bk - sd, L + sd, Bk - sd)
        b.inch("\(inch(108)) x \(inch(84))", 108, 84, 34, ["Seat Depth": 38]); b.inch("\(inch(120)) x \(inch(96))", 120, 96, 34, ["Seat Depth": 38])
        b.mm("2700 x 2100", 2700, 2100, 850, ["Seat Depth": 950]); b.mm("3000 x 2400", 3000, 2400, 850, ["Seat Depth": 950])
        return b.item
    }

    static func armchair() -> ComponentLibraryItem {
        var b = FB("Armchair - Upholstered", .furniture, group: "Living", keywords: ["club chair", "easy chair", "accent chair"],
                   "Upholstered armchair with a loose seat cushion.")
        roundLegs(&b, inset: 0.05, r: 0.018, K(0), K(0.1), .woodDark)
        b.box("Base", L, R, Fr, Bk, K(0.1), H(0.47), .fabric)
        b.box("Back", L, R, D(0.5, -0.18), Bk, H(0.47), T, .fabric)
        b.box("Arm Left", L, W(-0.5, 0.15), Fr, D(0.5, -0.18), H(0.47), H(0.75), .fabric)
        b.box("Arm Right", W(0.5, -0.15), R, Fr, D(0.5, -0.18), H(0.47), H(0.75), .fabric)
        b.box("Cushion", W(-0.5, 0.15), W(0.5, -0.15), D(-0.5, 0.02), D(0.5, -0.18), H(0.47), H(0.58), .fabric)
        b.rrect(L, Fr, R, Bk, K(0.04))
        b.line(W(-0.5, 0.15), D(0.5, -0.18), W(0.5, -0.15), D(0.5, -0.18))
        b.line(W(-0.5, 0.15), Fr, W(-0.5, 0.15), D(0.5, -0.18)); b.line(W(0.5, -0.15), Fr, W(0.5, -0.15), D(0.5, -0.18))
        b.inch(inch(32), 32, 34, 33); b.inch(inch(36), 36, 36, 34)
        b.mm("800", 800, 850, 820); b.mm("900", 900, 900, 850)
        return b.item
    }

    static func recliner() -> ComponentLibraryItem {
        var b = FB("Recliner", .furniture, group: "Living", keywords: ["reclining chair", "armchair"],
                   "Recliner shown upright; the dashed footprint shows the extended footrest.")
        b.box("Base", L, R, Fr, Bk, K(0.05), H(0.47), .leather)
        b.box("Back", L, R, D(0.5, -0.25), Bk, H(0.47), T, .leather)
        b.box("Arm Left", L, W(-0.5, 0.18), Fr, D(0.5, -0.25), H(0.47), H(0.68), .leather)
        b.box("Arm Right", W(0.5, -0.18), R, Fr, D(0.5, -0.25), H(0.47), H(0.68), .leather)
        b.box("Cushion", W(-0.5, 0.18), W(0.5, -0.18), Fr, D(0.5, -0.25), H(0.47), H(0.58), .leather)
        b.rrect(L, Fr, R, Bk, K(0.05))
        b.line(W(-0.5, 0.18), D(0.5, -0.25), W(0.5, -0.18), D(0.5, -0.25))
        b.line(W(-0.5, 0.18), Fr, W(-0.5, 0.18), D(0.5, -0.25)); b.line(W(0.5, -0.18), Fr, W(0.5, -0.18), D(0.5, -0.25))
        b.rect(W(-0.5, 0.2), D(-0.5, -0.5), W(0.5, -0.2), Fr, .hidden)
        b.inch(inch(36), 36, 40, 40); b.mm("900", 900, 1000, 1020)
        return b.item
    }

    static func loungeChair() -> ComponentLibraryItem {
        var b = FB("Chair - Lounge", .furniture, group: "Living", keywords: ["easy chair", "reading chair"],
                   "Low lounge chair with a reclined shell on a timber frame.")
        roundLegs(&b, inset: 0.06, r: 0.018, K(0), K(0.22), .wood)
        b.blend("Seat", [(L, Fr), (R, Fr), (R, D(0.5, -0.15)), (L, D(0.5, -0.15))],
                [(W(-0.5, 0.02), D(-0.5, 0.05)), (W(0.5, -0.02), D(-0.5, 0.05)), (W(0.5, -0.02), D(0.5, -0.12)), (W(-0.5, 0.02), D(0.5, -0.12))],
                K(0.22), H(0.45), .leather)
        b.blend("Back", [(L, D(0.5, -0.2)), (R, D(0.5, -0.2)), (R, D(0.5, -0.1)), (L, D(0.5, -0.1))],
                [(L, D(0.5, -0.08)), (R, D(0.5, -0.08)), (R, Bk), (L, Bk)], H(0.45), T, .leather)
        b.rrect(L, Fr, R, Bk, K(0.08))
        b.line(L, D(0.5, -0.18), R, D(0.5, -0.18))
        b.inch(inch(30), 30, 32, 32); b.mm("760", 760, 820, 800)
        return b.item
    }

    static func ottoman() -> ComponentLibraryItem {
        var b = FB("Ottoman - Square", .furniture, group: "Living", keywords: ["footstool", "pouf", "footrest"], "Upholstered square ottoman.")
        roundLegs(&b, inset: 0.04, r: 0.015, K(0), K(0.08), .woodDark)
        b.box("Body", L, R, Fr, Bk, K(0.08), T, .fabric)
        b.rrect(L, Fr, R, Bk, K(0.03))
        b.inch(inch(24), 24, 24, 17); b.mm("600", 600, 600, 420)
        return b.item
    }

    static func pouf() -> ComponentLibraryItem {
        var b = FB("Pouf - Round", .furniture, group: "Living", keywords: ["ottoman", "footstool", "puff"], "Round upholstered pouf.")
        b.revolve("Body", [(K(0), K(0)), (W(0.46), K(0)), (W(0.5), H(0.5)), (W(0.46), T), (K(0), T)], K(0), K(0), K(0), .fabricAccent)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.3))
        b.inch(inch(18), 18, 18, 16); b.mm("450", 450, 450, 400)
        return b.item
    }

    static func coffeeTableRect() -> ComponentLibraryItem {
        var b = FB("Coffee Table - Rectangular", .furniture, group: "Living", keywords: ["center table", "cocktail table"],
                   "Timber coffee table with a lower shelf.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.03), T, .wood)
        legs(&b, inset: 0.03, size: 0.045, K(0), H(1, -0.03), .wood)
        b.box("Shelf", W(-0.5, 0.075), W(0.5, -0.075), D(-0.5, 0.075), D(0.5, -0.075), K(0.1), K(0.12), .wood, plan: false)
        b.outline(); b.rect(W(-0.5, 0.03), D(-0.5, 0.03), W(0.5, -0.03), D(0.5, -0.03), .hidden)
        b.inch("\(inch(48)) x \(inch(24))", 48, 24, 16); b.inch("\(inch(54)) x \(inch(30))", 54, 30, 16)
        b.mm("1200 x 600", 1200, 600, 400); b.mm("1400 x 700", 1400, 700, 400)
        return b.item
    }

    static func coffeeTableRound() -> ComponentLibraryItem {
        var b = FB("Coffee Table - Round", .furniture, group: "Living", keywords: ["center table", "cocktail table", "drum table"],
                   "Round coffee table on a drum base.")
        b.cyl("Top", K(0), K(0), W(0.5), H(1, -0.03), T, .stone)
        b.cyl("Drum", K(0), K(0), W(0.35), K(0), H(1, -0.03), .woodDark, plan: false)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.35), .hidden)
        b.inch(inch(36), 36, 36, 16); b.inch(inch(42), 42, 42, 16)
        b.mm("900", 900, 900, 400); b.mm("1000", 1000, 1000, 400)
        return b.item
    }

    static func sideTable() -> ComponentLibraryItem {
        var b = FB("Side Table", .furniture, group: "Living", keywords: ["end table", "lamp table"], "Square side table.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.025), T, .wood)
        legs(&b, inset: 0.02, size: 0.035, K(0), H(1, -0.025), .wood)
        b.outline()
        b.inch("\(inch(20)) x \(inch(20))", 20, 20, 22); b.mm("500 x 500", 500, 500, 550)
        return b.item
    }

    static func consoleTable() -> ComponentLibraryItem {
        var b = FB("Console Table", .furniture, group: "Living", keywords: ["hall table", "sofa table"], "Narrow console table.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.03), T, .woodDark)
        legs(&b, inset: 0.02, size: 0.04, K(0), H(1, -0.03), .woodDark)
        b.box("Shelf", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.04), D(0.5, -0.04), K(0.15), K(0.17), .woodDark, plan: false)
        b.outline()
        b.inch("\(inch(48)) x \(inch(14))", 48, 14, 30); b.mm("1200 x 350", 1200, 350, 760)
        return b.item
    }

    static func tvUnit() -> ComponentLibraryItem {
        var b = FB("TV Unit - Low", .furniture, group: "Living", keywords: ["media console", "entertainment unit", "tv stand", "lowboard"],
                   "Low media unit with doors and an open shelf.")
        b.box("Plinth", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.03), Bk, K(0), K(0.08), .woodDark, plan: false)
        b.box("Carcass", L, R, D(-0.5, 0.02), Bk, K(0.08), T, .lacquer)
        b.box("Fronts", W(-0.5, 0.005), W(0.5, -0.005), Fr, D(-0.5, 0.02), K(0.09), H(1, -0.01), .wood, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch(inch(60), 60, 18, 20); b.inch(inch(72), 72, 18, 20); b.inch(inch(84), 84, 18, 20)
        b.mm("1500", 1500, 450, 500); b.mm("1800", 1800, 450, 500); b.mm("2100", 2100, 450, 500)
        return b.item
    }

    static func rug() -> ComponentLibraryItem {
        var b = FB("Rug - Rectangular", .furniture, group: "Living", keywords: ["carpet", "dhurrie", "mat"], "Area rug with a border.")
        b.box("Rug", L, R, Fr, Bk, K(0), T, .fabricAccent)
        b.outline(); b.rect(W(-0.5, 0.08), D(-0.5, 0.08), W(0.5, -0.08), D(0.5, -0.08))
        b.type("\(ft(5)) x \(ft(8))", .imperial, 1.524, 2.438, 0.01); b.type("\(ft(8)) x \(ft(10))", .imperial, 2.438, 3.048, 0.01)
        b.mm("1600 x 2300", 1600, 2300, 10); b.mm("2000 x 3000", 2000, 3000, 10)
        return b.item
    }

    static func diwan() -> ComponentLibraryItem {
        var b = FB("Diwan - Low Seating", .furniture, group: "Living", regions: [.india], keywords: ["divan", "day bed", "baithak", "floor seating"],
                   "Low timber seating platform with a mattress and round bolsters.")
        b.box("Platform", L, R, Fr, Bk, K(0), H(0.72), .wood)
        b.box("Mattress", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.02), D(0.5, -0.02), H(0.72), T, .cushion)
        b.bar("Bolster Left", [(W(-0.5, 0.14), D(-0.5, 0.05)), (W(-0.5, 0.14), D(0.5, -0.05))], z: H(1, 0.1), r: K(0.1), .fabricAccent)
        b.bar("Bolster Right", [(W(0.5, -0.14), D(-0.5, 0.05)), (W(0.5, -0.14), D(0.5, -0.05))], z: H(1, 0.1), r: K(0.1), .fabricAccent)
        b.outline()
        b.rect(W(-0.5, 0.04), D(-0.5, 0.05), W(-0.5, 0.24), D(0.5, -0.05)); b.rect(W(0.5, -0.24), D(-0.5, 0.05), W(0.5, -0.04), D(0.5, -0.05))
        b.mm("1800 x 750", 1800, 750, 400); b.mm("2100 x 900", 2100, 900, 400)
        return b.item
    }

    static func floorTable() -> ComponentLibraryItem {
        var b = FB("Table - Low Floor", .furniture, group: "Living", regions: [.asia], keywords: ["chabudai", "low table", "tea table", "floor seating"],
                   "Low table for floor seating.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.035), T, .wood)
        legs(&b, inset: 0.05, size: 0.05, K(0), H(1, -0.035), .wood)
        b.outline()
        b.mm("900 x 900", 900, 900, 350); b.mm("1200 x 750", 1200, 750, 350)
        return b.item
    }

    static func floorCushion() -> ComponentLibraryItem {
        var b = FB("Floor Cushion", .furniture, group: "Living", regions: [.asia, .india], keywords: ["zabuton", "gaddi", "seat cushion"],
                   "Square floor cushion.")
        b.box("Cushion", L, R, Fr, Bk, K(0), T, .cushion)
        b.rrect(L, Fr, R, Bk, K(0.04))
        b.mm("550 x 600", 550, 600, 80); b.mm("700 x 700", 700, 700, 100)
        return b.item
    }

    static func pianoUpright() -> ComponentLibraryItem {
        var b = FB("Piano - Upright", .furniture, group: "Living", keywords: ["piano", "music", "instrument"], "Upright piano with keyboard.")
        b.box("Case", L, R, D(-0.5, 0.2), Bk, K(0), T, .woodDark)
        b.box("Keybed", W(-0.5, 0.05), W(0.5, -0.05), Fr, D(-0.5, 0.2), K(0.65), K(0.75), .woodDark)
        b.box("Keys", W(-0.5, 0.08), W(0.5, -0.08), D(-0.5, 0.02), D(-0.5, 0.18), K(0.75), K(0.77), .plastic, plan: false)
        b.box("Toe Block Left", W(-0.5, 0.05), W(-0.5, 0.1), Fr, D(-0.5, 0.2), K(0), K(0.65), .woodDark, plan: false)
        b.box("Toe Block Right", W(0.5, -0.1), W(0.5, -0.05), Fr, D(-0.5, 0.2), K(0), K(0.65), .woodDark, plan: false)
        b.rect(L, D(-0.5, 0.2), R, Bk); b.rect(W(-0.5, 0.05), Fr, W(0.5, -0.05), D(-0.5, 0.2))
        b.line(W(-0.5, 0.08), D(-0.5, 0.18), W(0.5, -0.08), D(-0.5, 0.18))
        b.any("Standard", 1.5, 0.62, 1.25)
        return b.item
    }

    static func pianoGrand() -> ComponentLibraryItem {
        var b = FB("Piano - Grand", .furniture, group: "Living", keywords: ["piano", "music", "instrument", "baby grand"], "Grand piano with its lid closed.")
        let outline: [(LX, LX)] = [(L, Fr), (R, Fr), (R, D(-0.2)), (W(0.42), D(0.05)), (W(0.2), D(0.2)), (W(0.05), D(0.45)), (W(-0.1), Bk),
                                   (W(-0.3), Bk), (W(-0.45), D(0.35)), (L, D(0.1))]
        b.prism("Case", outline, K(0.62), K(0.95), .woodDark)
        b.box("Keybed", L, R, D(-0.5, -0.12), Fr, K(0.62), K(0.74), .woodDark)
        for (i, (x, y)) in [(W(-0.4), D(-0.4)), (W(0.4), D(-0.4)), (W(-0.2), D(0.4))].enumerated() {
            b.cyl("Leg \(i + 1)", x, y, K(0.045), K(0), K(0.62), .woodDark, plan: false)
        }
        b.poly(outline); b.rect(L, D(-0.5, -0.12), R, Fr)
        b.any("Baby Grand", 1.5, 1.55, 1.0); b.any("Parlor Grand", 1.5, 1.85, 1.0)
        return b.item
    }

    static func beanBag() -> ComponentLibraryItem {
        var b = FB("Chair - Bean Bag", .furniture, group: "Living", keywords: ["beanbag", "lounger", "floor chair"], "Bean bag lounger.")
        b.revolve("Body", [(K(0), K(0)), (W(0.45), K(0)), (W(0.5), H(0.3)), (W(0.38), H(0.8)), (K(0), T)], K(0), K(0), K(0), .fabricAccent)
        b.circle(K(0), K(0), W(0.5)); b.arc(K(0), K(0), W(0.3), 20, 140)
        b.any("Standard", 0.9, 0.9, 0.7)
        return b.item
    }

    static func swingJhoola() -> ComponentLibraryItem {
        var b = FB("Swing - Jhoola", .furniture, group: "Living", regions: [.india, .asia], keywords: ["jhula", "swing", "hanging seat"],
                   "Freestanding frame with a hanging timber swing seat.")
        b.box("Post Left", L, W(-0.5, 0.08), D(-0.04), D(0.04), K(0), T, .woodDark)
        b.box("Post Right", W(0.5, -0.08), R, D(-0.04), D(0.04), K(0), T, .woodDark)
        b.box("Beam", L, R, D(-0.04), D(0.04), H(1, -0.1), T, .woodDark)
        b.box("Foot Left", L, W(-0.5, 0.08), Fr, Bk, K(0), K(0.08), .woodDark)
        b.box("Foot Right", W(0.5, -0.08), R, Fr, Bk, K(0), K(0.08), .woodDark)
        b.box("Seat", W(-0.5, 0.2), W(0.5, -0.2), D(-0.25), D(0.25), K(0.42), K(0.47), .wood)
        for (i, x) in [W(-0.5, 0.25), W(0.5, -0.25)].enumerated() {
            b.cyl("Chain \(i + 1)", x, K(0), K(0.008), K(0.47), H(1, -0.1), .metal, plan: false)
        }
        b.rect(L, Fr, W(-0.5, 0.08), Bk); b.rect(W(0.5, -0.08), Fr, R, Bk); b.rect(W(-0.5, 0.2), D(-0.25), W(0.5, -0.2), D(0.25))
        b.line(W(-0.5, 0.08), K(0), W(0.5, -0.08), K(0), .hidden)
        b.mm("Frame 1800", 1800, 900, 2100); b.mm("Frame 2100", 2100, 1000, 2200)
        return b.item
    }

    static func entryBench() -> ComponentLibraryItem {
        var b = FB("Bench - Entry", .furniture, group: "Living", keywords: ["hall bench", "bed end bench", "foyer"], "Upholstered bench on timber legs.")
        legs(&b, inset: 0.02, size: 0.04, K(0), H(1, -0.1), .wood)
        b.box("Seat", L, R, Fr, Bk, H(1, -0.1), T, .fabric)
        b.rrect(L, Fr, R, Bk, K(0.02))
        b.inch(inch(48), 48, 16, 18); b.mm("1200", 1200, 400, 450)
        return b.item
    }

    static func foldingScreen() -> ComponentLibraryItem {
        var b = FB("Screen - Folding", .furniture, group: "Living", keywords: ["room divider", "partition", "privacy screen"],
                   "Three-panel folding screen, set in a shallow zigzag.")
        let pts: [(LX, LX)] = [(L, Fr), (W(-1.0 / 6), Bk), (W(1.0 / 6), Fr), (R, Bk)]
        for i in 0..<3 {
            b.blend("Panel \(i + 1)", [pts[i], pts[i + 1], (pts[i + 1].0, pts[i + 1].1 + 0.02), (pts[i].0, pts[i].1 + 0.02)],
                    [pts[i], pts[i + 1], (pts[i + 1].0, pts[i + 1].1 + 0.02), (pts[i].0, pts[i].1 + 0.02)], K(0.02), T, .woodLight)
        }
        b.poly(pts, closed: false)
        b.inch(inch(60), 60, 12, 68); b.mm("1500", 1500, 300, 1700)
        return b.item
    }

    // MARK: Dining

    static func dining() -> [ComponentLibraryItem] {
        [diningTableRect(), diningTableRound(), diningTableSquare(), diningSet(4), diningSet(6), diningSet(8), diningSetRound(),
         lazySusanTable(), diningChair(armchair: false), diningChair(armchair: true), barStool(), diningBench(), sideboard(), crockeryUnit()]
    }

    static func diningTableRect() -> ComponentLibraryItem {
        var b = FB("Table - Dining Rectangular", .furniture, group: "Dining", keywords: ["dining table", "kitchen table"], "Four-legged dining table.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.035), T, .wood)
        b.box("Apron", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.06), D(0.5, -0.06), H(1, -0.12), H(1, -0.035), .wood, plan: false)
        legs(&b, inset: 0.05, size: 0.07, K(0), H(1, -0.035), .wood)
        b.outline()
        b.inch("4 Seat \(inch(48)) x \(inch(30))", 48, 30, 30); b.inch("6 Seat \(inch(72)) x \(inch(36))", 72, 36, 30)
        b.inch("8 Seat \(inch(96)) x \(inch(42))", 96, 42, 30)
        b.mm("4 Seat 1200 x 800", 1200, 800, 750); b.mm("6 Seat 1600 x 900", 1600, 900, 750)
        b.mm("8 Seat 2000 x 1000", 2000, 1000, 750); b.mm("10 Seat 2400 x 1000", 2400, 1000, 750)
        return b.item
    }

    static func diningTableRound() -> ComponentLibraryItem {
        var b = FB("Table - Dining Round", .furniture, group: "Dining", keywords: ["dining table", "pedestal table", "breakfast table"],
                   "Round pedestal dining table.")
        b.cyl("Top", K(0), K(0), W(0.5), H(1, -0.035), T, .wood)
        b.cyl("Pedestal", K(0), K(0), K(0.07), K(0.04), H(1, -0.035), .wood, plan: false)
        b.cyl("Base", K(0), K(0), W(0.22), K(0), K(0.04), .wood, plan: false)
        b.circle(K(0), K(0), W(0.5))
        b.inch(inch(42), 42, 42, 30); b.inch(inch(48), 48, 48, 30); b.inch(inch(60), 60, 60, 30)
        b.mm("900", 900, 900, 750); b.mm("1200", 1200, 1200, 750); b.mm("1500", 1500, 1500, 750)
        return b.item
    }

    static func diningTableSquare() -> ComponentLibraryItem {
        var b = FB("Table - Dining Square", .furniture, group: "Dining", keywords: ["dining table", "cafe table", "bistro"], "Square four-seat table.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.035), T, .wood)
        legs(&b, inset: 0.04, size: 0.06, K(0), H(1, -0.035), .wood)
        b.outline()
        b.inch(inch(36), 36, 36, 30); b.inch(inch(42), 42, 42, 30); b.mm("900", 900, 900, 750); b.mm("1000", 1000, 1000, 750)
        return b.item
    }

    static func diningSet(_ seats: Int) -> ComponentLibraryItem {
        var b = FB("Dining Set - \(seats) Seat", .furniture, group: "Dining", keywords: ["dining table", "table and chairs", "dinette"],
                   "Rectangular table with \(seats) chairs; Width and Depth are the table's.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.035), T, .wood)
        legs(&b, inset: 0.05, size: 0.06, K(0), H(1, -0.035), .wood)
        b.outline()
        let perSide = seats == 8 ? 3 : seats / 2
        for i in 0..<perSide {
            let x = W((Double(i) + 0.5) / Double(perSide) - 0.5)
            chairSolid(&b, "Front Chair \(i + 1)", x, D(-0.5, -0.12), angle: 180)
            chairSymbol(&b, x, D(-0.5, -0.12), angle: 180)
            chairSolid(&b, "Back Chair \(i + 1)", x, D(0.5, 0.12))
            chairSymbol(&b, x, D(0.5, 0.12))
        }
        if seats == 8 {
            chairSolid(&b, "End Chair Left", W(-0.5, -0.12), K(0), angle: 90); chairSymbol(&b, W(-0.5, -0.12), K(0), angle: 90)
            chairSolid(&b, "End Chair Right", W(0.5, 0.12), K(0), angle: -90); chairSymbol(&b, W(0.5, 0.12), K(0), angle: -90)
        }
        switch seats {
        case 4: b.inch("\(inch(48)) x \(inch(30))", 48, 30, 30); b.mm("1200 x 800", 1200, 800, 750)
        case 6: b.inch("\(inch(72)) x \(inch(36))", 72, 36, 30); b.mm("1800 x 900", 1800, 900, 750)
        default: b.inch("\(inch(96)) x \(inch(42))", 96, 42, 30); b.mm("2200 x 1000", 2200, 1000, 750)
        }
        return b.item
    }

    static func diningSetRound() -> ComponentLibraryItem {
        var b = FB("Dining Set - Round 4 Seat", .furniture, group: "Dining", keywords: ["dining table", "table and chairs", "breakfast"],
                   "Round table with four chairs; Width is the table diameter.")
        b.cyl("Top", K(0), K(0), W(0.5), H(1, -0.035), T, .wood)
        b.cyl("Pedestal", K(0), K(0), K(0.06), K(0), H(1, -0.035), .wood, plan: false)
        b.circle(K(0), K(0), W(0.5))
        for (i, a) in [0.0, 90, 180, 270].enumerated() {
            let r = a * .pi / 180
            let cx = W(0.5 * sin(r), 0.12 * sin(r)), cy = W(-0.5 * cos(r), -0.12 * cos(r))
            chairSolid(&b, "Chair \(i + 1)", cx, cy, angle: 180 + a)
            chairSymbol(&b, cx, cy, angle: 180 + a)
        }
        b.inch(inch(42), 42, 42, 30); b.mm("1050", 1050, 1050, 750)
        return b.item
    }

    static func lazySusanTable() -> ComponentLibraryItem {
        var b = FB("Table - Round with Lazy Susan", .furniture, group: "Dining", regions: [.asia, .india], keywords: ["turntable", "banquet", "family table"],
                   "Round family dining table with a glass turntable.")
        b.cyl("Top", K(0), K(0), W(0.5), H(1, -0.035), T, .woodDark)
        b.cyl("Turntable", K(0), K(0), W(0.3), T, H(1, 0.02), .glass)
        b.cyl("Pedestal", K(0), K(0), K(0.09), K(0.04), H(1, -0.035), .woodDark, plan: false)
        b.cyl("Base", K(0), K(0), W(0.25), K(0), K(0.04), .woodDark, plan: false)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.3))
        b.mm("1200 - 6 Seat", 1200, 1200, 760); b.mm("1500 - 8 Seat", 1500, 1500, 760); b.mm("1800 - 10 Seat", 1800, 1800, 760)
        return b.item
    }

    static func diningChair(armchair: Bool) -> ComponentLibraryItem {
        var b = FB(armchair ? "Chair - Dining Armchair" : "Chair - Dining", .furniture, group: "Dining", keywords: ["chair", "side chair", "seat"],
                   armchair ? "Dining armchair with an upholstered seat." : "Dining side chair with an upholstered seat.")
        legs(&b, inset: 0.02, size: 0.035, K(0), H(0.51), .wood)
        b.box("Seat", L, R, Fr, D(0.5, -0.04), H(0.49), H(0.55), .fabric)
        b.box("Back", L, R, D(0.5, -0.04), Bk, H(0.51), T, .wood)
        if armchair {
            b.box("Arm Left", L, W(-0.5, 0.04), Fr, D(0.5, -0.04), H(0.55), H(0.77), .wood)
            b.box("Arm Right", W(0.5, -0.04), R, Fr, D(0.5, -0.04), H(0.55), H(0.77), .wood)
        }
        b.outline(); b.line(L, D(0.5, -0.04), R, D(0.5, -0.04))
        if armchair {
            b.line(W(-0.5, 0.04), Fr, W(-0.5, 0.04), D(0.5, -0.04)); b.line(W(0.5, -0.04), Fr, W(0.5, -0.04), D(0.5, -0.04))
            b.inch(inch(22), 22, 22, 34); b.mm("560", 560, 560, 860)
        } else {
            b.inch(inch(18), 18, 21, 34); b.mm("450", 450, 520, 860)
        }
        return b.item
    }

    static func barStool() -> ComponentLibraryItem {
        var b = FB("Stool - Bar", .furniture, group: "Dining", keywords: ["counter stool", "high stool", "kitchen stool"],
                   "Pedestal stool; Height is the seat height.")
        b.cyl("Seat", K(0), K(0), W(0.5), H(1, -0.05), T, .leather)
        b.cyl("Column", K(0), K(0), K(0.03), K(0.02), H(1, -0.05), .chrome, plan: false)
        b.cyl("Base", K(0), K(0), W(0.45), K(0), K(0.02), .chrome, plan: false)
        b.cyl("Foot Ring", K(0), K(0), W(0.4), H(0.35), H(0.35, 0.02), .chrome, plan: false)
        b.circle(K(0), K(0), W(0.5))
        b.inch("Counter \(inch(24))", 16, 16, 24); b.inch("Bar \(inch(30))", 16, 16, 30)
        b.mm("Counter 650", 400, 400, 650); b.mm("Bar 750", 400, 400, 750)
        return b.item
    }

    static func diningBench() -> ComponentLibraryItem {
        var b = FB("Bench - Dining", .furniture, group: "Dining", keywords: ["bench", "seat"], "Backless timber dining bench.")
        b.box("Seat", L, R, Fr, Bk, H(1, -0.04), T, .wood)
        b.box("Leg Left", W(-0.5, 0.06), W(-0.5, 0.1), D(-0.5, 0.03), D(0.5, -0.03), K(0), H(1, -0.04), .wood, plan: false)
        b.box("Leg Right", W(0.5, -0.1), W(0.5, -0.06), D(-0.5, 0.03), D(0.5, -0.03), K(0), H(1, -0.04), .wood, plan: false)
        b.outline()
        b.inch(inch(48), 48, 14, 18); b.inch(inch(60), 60, 14, 18); b.mm("1200", 1200, 350, 450); b.mm("1500", 1500, 350, 450)
        return b.item
    }

    static func sideboard() -> ComponentLibraryItem {
        var b = FB("Sideboard", .furniture, group: "Dining", keywords: ["buffet", "credenza", "server"], "Sideboard with four doors on legs.")
        legs(&b, inset: 0.03, size: 0.035, K(0), K(0.15), .woodDark)
        b.box("Body", L, R, Fr, Bk, K(0.15), T, .woodDark)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch(inch(60), 60, 18, 32); b.inch(inch(72), 72, 18, 32); b.mm("1600", 1600, 450, 800); b.mm("1800", 1800, 450, 800)
        return b.item
    }

    static func crockeryUnit() -> ComponentLibraryItem {
        var b = FB("Crockery Unit", .furniture, group: "Dining", regions: [.india], keywords: ["crockery cabinet", "display", "hutch"],
                   "Tall crockery unit: closed base cabinet with glazed shelves above.")
        b.box("Base Cabinet", L, R, Fr, Bk, K(0), K(0.85), .woodDark)
        b.box("Upper Frame", L, R, D(-0.5, 0.1), Bk, K(0.85), T, .woodDark)
        b.box("Glazing", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.09), D(-0.5, 0.1), K(0.9), H(1, -0.05), .glass, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.1), R, D(-0.5, 0.1), .hidden)
        b.mm("1200", 1200, 450, 2100); b.mm("1500", 1500, 450, 2100)
        return b.item
    }

    // MARK: Bedroom

    static func bedroom() -> [ComponentLibraryItem] {
        [bedUS(), bedUK(), bedEurope(), bedIndia(), bedPlatform(), bedUpholstered(), bedStorage(), bedFourPoster(), dayBed(),
         nightstand(), dresser(), chestOfDrawers(), dressingTable(), wardrobeHinged(), wardrobeSliding(), wardrobeLoft(), bedEndBench()]
    }

    /// A bed whose Width x Depth is the overall frame. Pillows switch between one and two with the width.
    static func bedBody(_ b: inout FB, headboard: LM = .wood, frame: LM = .wood, legsOn: Bool = true) {
        let hb = 0.06
        if legsOn { roundLegs(&b, inset: 0.05, r: 0.025, K(0), H(0.2), frame) }
        b.box("Frame", L, R, Fr, D(0.5, -hb), legsOn ? H(0.2) : K(0), H(0.6), frame)
        b.box("Mattress", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.02), D(0.5, -hb - 0.01), H(0.6), T, .mattress)
        b.box("Headboard", L, R, D(0.5, -hb), Bk, K(0), P("Headboard Height"), headboard)
        b.box("Blanket", W(-0.5, 0.01), W(0.5, -0.01), D(-0.5, 0.01), D(0.5, -0.78), T, H(1, 0.03), .bedding, plan: false)
        b.visibility = "Two Pillows"
        b.box("Pillow Left", W(-0.5, 0.1), W(0, -0.03), D(0.5, -0.55), D(0.5, -0.15), T, H(1, 0.12), .bedding, plan: false)
        b.box("Pillow Right", W(0, 0.03), W(0.5, -0.1), D(0.5, -0.55), D(0.5, -0.15), T, H(1, 0.12), .bedding, plan: false)
        b.rrect(W(-0.5, 0.1), D(0.5, -0.55), W(0, -0.03), D(0.5, -0.15), K(0.05))
        b.rrect(W(0, 0.03), D(0.5, -0.55), W(0.5, -0.1), D(0.5, -0.15), K(0.05))
        b.visibility = "One Pillow"
        b.box("Pillow", W(-0.5, 0.1), W(0.5, -0.1), D(0.5, -0.55), D(0.5, -0.15), T, H(1, 0.12), .bedding, plan: false)
        b.rrect(W(-0.5, 0.1), D(0.5, -0.55), W(0.5, -0.1), D(0.5, -0.15), K(0.05))
        b.visibility = nil
        b.outline()
        b.line(L, D(0.5, -hb), R, D(0.5, -hb))
        b.line(L, D(0.5, -0.78), R, D(0.5, -0.78))
        b.line(W(0.5, -0.4), D(0.5, -0.78), R, D(0.5, -1.18))
    }

    static func finishBed(_ b: inout FB) {
        b.flag("Two Pillows") { $0 >= 1.15 }
        b.flag("One Pillow") { $0 < 1.15 }
    }

    /// Adds a bed type from mattress size (overall frame = mattress + allowances).
    static func bedType(_ b: inout FB, _ name: String, inches mw: Double, _ ml: Double, h: Double = 24) {
        b.inch(name, mw + 3, ml + 5, h, ["Headboard Height": 44])
    }
    static func bedType(_ b: inout FB, _ name: String, mm mw: Double, _ ml: Double, h: Double = 550) {
        b.mm(name, mw + 80, ml + 120, h, ["Headboard Height": 1100])
    }

    static func bedUS() -> ComponentLibraryItem {
        var b = FB("Bed - US Standard", .furniture, group: "Bedroom", regions: [.usa], keywords: ["bed", "twin", "full", "queen", "king", "california king"],
                   extra: ["Headboard Height"], "Bed frame with headboard for US mattress sizes (type names give the mattress size).")
        bedBody(&b)
        for (n, w, l) in [("Twin", 38.0, 75.0), ("Twin XL", 38, 80), ("Full", 54, 75), ("Queen", 60, 80), ("King", 76, 80), ("California King", 72, 84)] {
            bedType(&b, "\(n) \(inch(w)) x \(inch(l))", inches: w, l)
        }
        finishBed(&b)
        return b.item
    }

    static func bedUK() -> ComponentLibraryItem {
        var b = FB("Bed - UK", .furniture, group: "Bedroom", regions: [.uk], keywords: ["bed", "single", "double", "king", "super king"],
                   extra: ["Headboard Height"], "Bed frame with headboard for UK mattress sizes.")
        bedBody(&b)
        for (n, w, l) in [("Single", 900.0, 1900.0), ("Small Double", 1200, 1900), ("Double", 1350, 1900), ("King", 1500, 2000), ("Super King", 1800, 2000)] {
            bedType(&b, "\(n) \(Int(w)) x \(Int(l))", mm: w, l)
        }
        finishBed(&b)
        return b.item
    }

    static func bedEurope() -> ComponentLibraryItem {
        var b = FB("Bed - European", .furniture, group: "Bedroom", regions: [.europe], keywords: ["bed", "single", "double", "90", "140", "160", "180"],
                   extra: ["Headboard Height"], "Bed frame with headboard for continental European mattress sizes.")
        bedBody(&b, headboard: .fabric)
        for w in [900.0, 1400, 1600, 1800, 2000] { bedType(&b, "\(Int(w)) x 2000", mm: w, 2000, h: 500) }
        finishBed(&b)
        return b.item
    }

    static func bedIndia() -> ComponentLibraryItem {
        var b = FB("Bed - India", .furniture, group: "Bedroom", regions: [.india], keywords: ["bed", "single", "double", "queen", "king", "palang"],
                   extra: ["Headboard Height"], "Bed frame with headboard for Indian mattress sizes.")
        bedBody(&b, headboard: .woodDark, frame: .woodDark)
        for (n, w, l) in [("Single", 36.0, 72.0), ("Double", 48, 72), ("Queen", 60, 78), ("King", 72, 78)] {
            bedType(&b, "\(n) \(inch(w)) x \(inch(l))", inches: w, l, h: 20)
        }
        bedType(&b, "Queen 1525 x 1980", mm: 1525, 1980, h: 500); bedType(&b, "King 1830 x 1980", mm: 1830, 1980, h: 500)
        finishBed(&b)
        return b.item
    }

    static func bedPlatform() -> ComponentLibraryItem {
        var b = FB("Bed - Low Platform", .furniture, group: "Bedroom", regions: [.asia], keywords: ["bed", "futon", "tatami", "low bed", "semi-double"],
                   "Low timber platform bed with the mattress set in from the edge.")
        b.box("Platform", L, R, Fr, Bk, K(0), H(1, -0.14), .woodLight)
        b.box("Mattress", W(-0.5, 0.1), W(0.5, -0.1), D(-0.5, 0.1), D(0.5, -0.1), H(1, -0.14), T, .mattress)
        b.box("Pillow", W(-0.2), W(0.2), D(0.5, -0.5), D(0.5, -0.15), T, H(1, 0.1), .bedding, plan: false)
        b.outline(); b.rect(W(-0.5, 0.1), D(-0.5, 0.1), W(0.5, -0.1), D(0.5, -0.1)); b.rrect(W(-0.2), D(0.5, -0.5), W(0.2), D(0.5, -0.15), K(0.05))
        for (n, w) in [("Single", 1000.0), ("Semi-Double", 1200), ("Double", 1400), ("Queen", 1600)] {
            b.mm("\(n) \(Int(w)) x 2000", w + 200, 2200, 320)
        }
        return b.item
    }

    static func bedUpholstered() -> ComponentLibraryItem {
        var b = FB("Bed - Upholstered", .furniture, group: "Bedroom", keywords: ["bed", "padded headboard", "queen", "king"],
                   extra: ["Headboard Height"], "Upholstered bed with a tall padded headboard.")
        bedBody(&b, headboard: .fabric, frame: .fabric, legsOn: false)
        bedType(&b, "Queen \(inch(60)) x \(inch(80))", inches: 60, 80); bedType(&b, "King \(inch(76)) x \(inch(80))", inches: 76, 80)
        bedType(&b, "1600 x 2000", mm: 1600, 2000); bedType(&b, "1800 x 2000", mm: 1800, 2000)
        for i in b.f.types.indices { b.f.types[i].values["Headboard Height"] = .double(1.3) }
        finishBed(&b)
        return b.item
    }

    static func bedStorage() -> ComponentLibraryItem {
        var b = FB("Bed - Box Storage", .furniture, group: "Bedroom", regions: [.india], keywords: ["bed", "hydraulic", "storage bed", "box bed"],
                   extra: ["Headboard Height"], "Box bed with storage below the mattress.")
        bedBody(&b, headboard: .laminate, frame: .woodDark, legsOn: false)
        bedType(&b, "Queen 1525 x 1980", mm: 1525, 1980, h: 480); bedType(&b, "King 1830 x 1980", mm: 1830, 1980, h: 480)
        bedType(&b, "Queen \(inch(60)) x \(inch(78))", inches: 60, 78, h: 19)
        finishBed(&b)
        return b.item
    }

    static func bedFourPoster() -> ComponentLibraryItem {
        var b = FB("Bed - Four Poster", .furniture, group: "Bedroom", keywords: ["bed", "canopy bed", "poster bed"],
                   extra: ["Headboard Height"], "Four-poster bed with canopy rails.")
        bedBody(&b, headboard: .woodDark, frame: .woodDark, legsOn: false)
        for (i, (x, y)) in [(W(-0.5, 0.04), D(-0.5, 0.04)), (W(0.5, -0.04), D(-0.5, 0.04)), (W(0.5, -0.04), D(0.5, -0.04)), (W(-0.5, 0.04), D(0.5, -0.04))].enumerated() {
            b.cyl("Post \(i + 1)", x, y, K(0.04), K(0), K(2.1), .woodDark)
        }
        b.bar("Canopy Rail", [(W(-0.5, 0.04), D(-0.5, 0.04)), (W(0.5, -0.04), D(-0.5, 0.04)), (W(0.5, -0.04), D(0.5, -0.04)),
                              (W(-0.5, 0.04), D(0.5, -0.04)), (W(-0.5, 0.04), D(-0.5, 0.04))], z: K(2.07), r: K(0.025), .woodDark, plan: false)
        bedType(&b, "Queen \(inch(60)) x \(inch(80))", inches: 60, 80); bedType(&b, "King \(inch(76)) x \(inch(80))", inches: 76, 80)
        bedType(&b, "1600 x 2000", mm: 1600, 2000); bedType(&b, "1800 x 2000", mm: 1800, 2000)
        finishBed(&b)
        return b.item
    }

    static func dayBed() -> ComponentLibraryItem {
        var b = FB("Day Bed", .furniture, group: "Bedroom", keywords: ["daybed", "guest bed", "settee"], "Day bed with back and side rails.")
        legs(&b, inset: 0.03, size: 0.05, K(0), K(0.15), .wood)
        b.box("Frame", L, R, Fr, Bk, K(0.15), H(0.45), .wood)
        b.box("Mattress", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.02), D(0.5, -0.05), H(0.45), H(0.62), .mattress)
        b.box("Back", L, R, D(0.5, -0.05), Bk, H(0.45), T, .wood)
        b.box("End Left", L, W(-0.5, 0.05), Fr, D(0.5, -0.05), H(0.45), H(0.9), .wood)
        b.box("End Right", W(0.5, -0.05), R, Fr, D(0.5, -0.05), H(0.45), H(0.9), .wood)
        b.outline(); b.line(L, D(0.5, -0.05), R, D(0.5, -0.05))
        b.line(W(-0.5, 0.05), Fr, W(-0.5, 0.05), D(0.5, -0.05)); b.line(W(0.5, -0.05), Fr, W(0.5, -0.05), D(0.5, -0.05))
        b.inch("Twin \(inch(80)) x \(inch(42))", 80, 42, 36); b.mm("2000 x 1000", 2000, 1000, 900)
        return b.item
    }

    static func nightstand() -> ComponentLibraryItem {
        var b = FB("Nightstand", .furniture, group: "Bedroom", keywords: ["bedside table", "night table", "side table"], "Two-drawer bedside table.")
        legs(&b, inset: 0.02, size: 0.03, K(0), K(0.12), .wood)
        b.box("Body", L, R, Fr, Bk, K(0.12), T, .wood)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch("\(inch(20)) x \(inch(16))", 20, 16, 24); b.inch("\(inch(24)) x \(inch(18))", 24, 18, 26)
        b.mm("450 x 400", 450, 400, 550); b.mm("550 x 450", 550, 450, 600)
        return b.item
    }

    static func dresser() -> ComponentLibraryItem {
        var b = FB("Dresser", .furniture, group: "Bedroom", keywords: ["chest of drawers", "bureau", "drawers"], "Wide low dresser.")
        b.box("Plinth", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.02), Bk, K(0), K(0.08), .woodDark, plan: false)
        b.box("Body", L, R, Fr, Bk, K(0.08), T, .wood)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch("\(inch(60)) x \(inch(20))", 60, 20, 32); b.inch("\(inch(72)) x \(inch(20))", 72, 20, 32)
        b.mm("1200 x 500", 1200, 500, 800); b.mm("1500 x 500", 1500, 500, 800)
        return b.item
    }

    static func chestOfDrawers() -> ComponentLibraryItem {
        var b = FB("Chest of Drawers - Tall", .furniture, group: "Bedroom", keywords: ["tallboy", "highboy", "drawers"], "Tall five-drawer chest.")
        legs(&b, inset: 0.02, size: 0.04, K(0), K(0.1), .wood)
        b.box("Body", L, R, Fr, Bk, K(0.1), T, .wood)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch(inch(36), 36, 20, 50); b.mm("900", 900, 500, 1250)
        return b.item
    }

    static func dressingTable() -> ComponentLibraryItem {
        var b = FB("Dressing Table", .furniture, group: "Bedroom", keywords: ["vanity table", "makeup table", "mirror"], "Dressing table with a wall mirror above.")
        legs(&b, inset: 0.02, size: 0.04, K(0), K(0.72), .wood)
        b.box("Top", L, R, Fr, Bk, K(0.72), K(0.76), .wood)
        b.box("Drawer", W(-0.5, 0.04), W(0.5, -0.04), D(-0.5, 0.02), D(0.5, -0.02), K(0.6), K(0.72), .wood, plan: false)
        b.box("Mirror", W(-0.35), W(0.35), D(0.5, -0.02), Bk, K(0.85), T, .mirror)
        b.outline(); b.line(W(-0.35), D(0.5, -0.02), W(0.35), D(0.5, -0.02))
        b.inch(inch(42), 42, 18, 72); b.mm("1000", 1000, 450, 1800)
        return b.item
    }

    static func wardrobeHinged() -> ComponentLibraryItem {
        var b = FB("Wardrobe - Hinged Doors", .furniture, group: "Bedroom", keywords: ["closet", "almirah", "armoire", "cupboard"],
                   "Freestanding wardrobe with hinged doors and a hanging rail.")
        b.box("Plinth", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.03), Bk, K(0), K(0.08), .laminate, plan: false)
        b.box("Carcass", L, R, D(-0.5, 0.02), Bk, K(0.08), T, .laminate)
        b.box("Doors", L, R, Fr, D(-0.5, 0.02), K(0.08), T, .lacquer)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.line(W(-0.5, 0.03), K(0), W(0.5, -0.03), K(0), .hidden)
        b.line(L, D(-0.5, 0.02), R, Bk, .hidden)
        b.inch("\(inch(36)) x \(inch(24))", 36, 24, 84); b.inch("\(inch(48)) x \(inch(24))", 48, 24, 84); b.inch("\(inch(72)) x \(inch(24))", 72, 24, 84)
        b.mm("900 x 600", 900, 600, 2100); b.mm("1200 x 600", 1200, 600, 2100); b.mm("1800 x 600", 1800, 600, 2100); b.mm("2400 x 600", 2400, 600, 2200)
        return b.item
    }

    static func wardrobeSliding() -> ComponentLibraryItem {
        var b = FB("Wardrobe - Sliding Doors", .furniture, group: "Bedroom", keywords: ["closet", "almirah", "sliding wardrobe", "cupboard"],
                   "Wardrobe with two sliding doors on a double track.")
        b.box("Carcass", L, R, D(-0.5, 0.08), Bk, K(0), T, .laminate)
        b.box("Door Back", L, W(0.02), D(-0.5, 0.04), D(-0.5, 0.07), K(0.02), H(1, -0.02), .mirror, plan: false)
        b.box("Door Front", W(-0.02), R, Fr, D(-0.5, 0.03), K(0.02), H(1, -0.02), .lacquer, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.08), R, D(-0.5, 0.08))
        b.line(L, D(-0.5, 0.055), W(0.02), D(-0.5, 0.055)); b.line(W(-0.02), D(-0.5, 0.015), R, D(-0.5, 0.015))
        b.line(W(-0.5, 0.03), D(0.1), W(0.5, -0.03), D(0.1), .hidden)
        b.inch(inch(72), 72, 26, 84); b.inch(inch(96), 96, 26, 84); b.mm("1800", 1800, 650, 2200); b.mm("2400", 2400, 650, 2200)
        return b.item
    }

    static func wardrobeLoft() -> ComponentLibraryItem {
        var b = FB("Wardrobe - With Loft", .furniture, group: "Bedroom", regions: [.india], keywords: ["almirah", "cupboard", "loft", "closet"],
                   extra: ["Loft Height"], "Floor-to-ceiling wardrobe with a loft cabinet above.")
        b.box("Carcass", L, R, D(-0.5, 0.02), Bk, K(0), H(1) - P("Loft Height"), .laminate)
        b.box("Loft", L, R, D(-0.5, 0.02), Bk, H(1) - P("Loft Height"), T, .laminate)
        b.box("Doors", L, R, Fr, D(-0.5, 0.02), K(0.05), H(1, -0.01), .lacquer, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02)); b.line(L, D(-0.5, 0.02), R, Bk, .hidden)
        b.mm("1200 + Loft", 1200, 600, 2700, ["Loft Height": 600]); b.mm("1800 + Loft", 1800, 600, 2700, ["Loft Height": 600])
        return b.item
    }

    static func bedEndBench() -> ComponentLibraryItem {
        var b = FB("Bench - Bed End", .furniture, group: "Bedroom", keywords: ["ottoman bench", "blanket box", "trunk"], "Upholstered storage bench for the foot of a bed.")
        b.box("Body", L, R, Fr, Bk, K(0.05), H(1, -0.08), .woodDark)
        b.box("Cushion", L, R, Fr, Bk, H(1, -0.08), T, .fabric)
        b.box("Plinth", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.03), D(0.5, -0.03), K(0), K(0.05), .woodDark, plan: false)
        b.rrect(L, Fr, R, Bk, K(0.02))
        b.inch(inch(48), 48, 18, 18); b.mm("1200", 1200, 450, 450)
        return b.item
    }

    // MARK: Kids

    static func kids() -> [ComponentLibraryItem] { [bunkBed(), crib(), toddlerBed(), kidsDesk(), toyStorage(), changingTable()] }

    static func bunkBed() -> ComponentLibraryItem {
        var b = FB("Bunk Bed", .furniture, group: "Kids", keywords: ["bunk", "double decker", "kids bed"], "Twin-over-twin bunk bed with ladder and guard rail.")
        for (i, (x, y)) in [(W(-0.5, 0.03), D(-0.5, 0.03)), (W(0.5, -0.03), D(-0.5, 0.03)), (W(0.5, -0.03), D(0.5, -0.03)), (W(-0.5, 0.03), D(0.5, -0.03))].enumerated() {
            b.box("Post \(i + 1)", x - 0.03, x + 0.03, y - 0.03, y + 0.03, K(0), T, .wood)
        }
        b.box("Lower Frame", L, R, Fr, Bk, K(0.2), K(0.3), .wood)
        b.box("Lower Mattress", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.06), D(0.5, -0.06), K(0.3), K(0.45), .mattress, plan: false)
        b.box("Upper Frame", L, R, Fr, Bk, K(1.1), K(1.2), .wood)
        b.box("Upper Mattress", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.06), D(0.5, -0.06), K(1.2), K(1.35), .mattress)
        b.box("Guard Rail", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.01), D(-0.5, 0.04), K(1.4), K(1.5), .wood)
        b.box("Ladder", W(0.5, -0.45), W(0.5, -0.06), D(-0.5, -0.06), D(-0.5, 0.0), K(0), K(1.5), .wood)
        b.outline(); b.rect(W(-0.5, 0.06), D(-0.5, 0.06), W(0.5, -0.06), D(0.5, -0.06)); b.rect(W(0.5, -0.45), D(-0.5, -0.06), W(0.5, -0.06), Fr)
        b.inch("Twin \(inch(38)) x \(inch(75))", 42, 80, 65); b.mm("900 x 2000", 980, 2080, 1650)
        return b.item
    }

    static func crib() -> ComponentLibraryItem {
        var b = FB("Crib", .furniture, group: "Kids", keywords: ["cot", "baby bed", "nursery"], "Baby crib with slatted sides.")
        for (i, (x, y)) in [(W(-0.5, 0.025), D(-0.5, 0.025)), (W(0.5, -0.025), D(-0.5, 0.025)), (W(0.5, -0.025), D(0.5, -0.025)), (W(-0.5, 0.025), D(0.5, -0.025))].enumerated() {
            b.box("Post \(i + 1)", x - 0.025, x + 0.025, y - 0.025, y + 0.025, K(0), T, .woodLight)
        }
        b.box("Mattress", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.03), D(0.5, -0.03), K(0.3), K(0.42), .mattress)
        b.box("Side Front", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.01), D(-0.5, 0.03), K(0.25), H(1, -0.05), .woodLight, plan: false)
        b.box("Side Back", W(-0.5, 0.05), W(0.5, -0.05), D(0.5, -0.03), D(0.5, -0.01), K(0.25), H(1, -0.05), .woodLight, plan: false)
        b.box("End Left", W(-0.5, 0.01), W(-0.5, 0.03), D(-0.5, 0.05), D(0.5, -0.05), K(0.25), T, .woodLight, plan: false)
        b.box("End Right", W(0.5, -0.03), W(0.5, -0.01), D(-0.5, 0.05), D(0.5, -0.05), K(0.25), T, .woodLight, plan: false)
        b.outline(); b.rect(W(-0.5, 0.03), D(-0.5, 0.03), W(0.5, -0.03), D(0.5, -0.03))
        b.inch("\(inch(28)) x \(inch(52))", 55, 31, 40); b.mm("600 x 1200", 1260, 660, 950); b.mm("700 x 1400", 1460, 760, 950)
        return b.item
    }

    static func toddlerBed() -> ComponentLibraryItem {
        var b = FB("Bed - Toddler", .furniture, group: "Kids", keywords: ["kids bed", "junior bed", "child"], extra: ["Headboard Height"],
                   "Low toddler bed with side guards.")
        bedBody(&b, headboard: .woodLight, frame: .woodLight)
        b.box("Guard", W(-0.5, 0.02), W(-0.5, 0.05), D(-0.1), D(0.5, -0.1), H(1, -0.05), H(1, 0.15), .woodLight)
        b.inch("\(inch(28)) x \(inch(52))", 31, 57, 16, ["Headboard Height": 26]); b.mm("700 x 1400", 780, 1500, 400, ["Headboard Height": 650])
        finishBed(&b)
        return b.item
    }

    static func kidsDesk() -> ComponentLibraryItem {
        var b = FB("Desk - Kids Study", .furniture, group: "Kids", keywords: ["study table", "homework desk", "child desk"], "Child-height study desk with a shelf.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.025), T, .woodLight)
        b.box("Side Left", L, W(-0.5, 0.02), D(-0.5, 0.02), Bk, K(0), H(1, -0.025), .laminate, plan: false)
        b.box("Side Right", W(0.5, -0.02), R, D(-0.5, 0.02), Bk, K(0), H(1, -0.025), .laminate, plan: false)
        b.box("Hutch", L, R, D(0.5, -0.2), Bk, T, H(1, 0.35), .laminate)
        b.outline(); b.line(L, D(0.5, -0.2), R, D(0.5, -0.2))
        b.inch(inch(36), 36, 20, 24); b.mm("900", 900, 500, 600)
        return b.item
    }

    static func toyStorage() -> ComponentLibraryItem {
        var b = FB("Toy Storage Unit", .furniture, group: "Kids", keywords: ["toy box", "bins", "cubby"], "Low cubby unit with bins.")
        b.box("Body", L, R, Fr, Bk, K(0), T, .woodLight)
        b.outline(); b.line(W(-1.0 / 6), Fr, W(-1.0 / 6), Bk, .hidden); b.line(W(1.0 / 6), Fr, W(1.0 / 6), Bk, .hidden)
        b.inch(inch(36), 36, 12, 30); b.mm("900", 900, 300, 760)
        return b.item
    }

    static func changingTable() -> ComponentLibraryItem {
        var b = FB("Changing Table", .furniture, group: "Kids", keywords: ["baby changer", "nursery", "diaper"], "Changing table with a padded top.")
        b.box("Body", L, R, Fr, Bk, K(0), H(1, -0.1), .woodLight)
        b.box("Pad", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.03), D(0.5, -0.03), H(1, -0.1), T, .cushion)
        b.outline(); b.rrect(W(-0.5, 0.03), D(-0.5, 0.03), W(0.5, -0.03), D(0.5, -0.03), K(0.04))
        b.inch(inch(36), 36, 20, 40); b.mm("900", 900, 500, 1000)
        return b.item
    }

    // MARK: Storage

    static func storage() -> [ComponentLibraryItem] {
        [bookshelf(), bookcaseLow(), shoeCabinet(), displayCabinet(), steelCabinet(), coatStand(), prayerUnit(), cubeStorage(), wallShelf()]
    }

    static func bookshelf() -> ComponentLibraryItem {
        var b = FB("Bookshelf - Tall", .furniture, group: "Storage", keywords: ["bookcase", "shelving", "library"], "Open bookshelf with fixed shelves.")
        b.box("Side Left", L, W(-0.5, 0.018), Fr, Bk, K(0), T, .wood)
        b.box("Side Right", W(0.5, -0.018), R, Fr, Bk, K(0), T, .wood)
        b.box("Back", W(-0.5, 0.018), W(0.5, -0.018), D(0.5, -0.008), Bk, K(0), T, .wood, plan: false)
        for (i, f) in [0.0, 0.2, 0.4, 0.6, 0.8].enumerated() {
            b.box("Shelf \(i + 1)", W(-0.5, 0.018), W(0.5, -0.018), Fr, D(0.5, -0.008), H(f), H(f, 0.018), .wood, plan: false)
        }
        b.box("Top", L, R, Fr, Bk, H(1, -0.018), T, .wood, plan: false)
        b.outline(); b.line(L, D(0.5, -0.008), R, D(0.5, -0.008))
        b.inch("\(inch(30)) x \(inch(12)) x \(inch(72))", 30, 12, 72); b.inch("\(inch(36)) x \(inch(12)) x \(inch(84))", 36, 12, 84)
        b.mm("800 x 300 x 1800", 800, 300, 1800); b.mm("900 x 350 x 2100", 900, 350, 2100)
        return b.item
    }

    static func bookcaseLow() -> ComponentLibraryItem {
        var b = FB("Bookcase - Low", .furniture, group: "Storage", keywords: ["bookshelf", "low shelf"], "Waist-high open bookcase.")
        b.box("Sides", L, R, Fr, Bk, K(0), K(0.018), .wood, plan: false)
        b.box("Side Left", L, W(-0.5, 0.018), Fr, Bk, K(0), T, .wood)
        b.box("Side Right", W(0.5, -0.018), R, Fr, Bk, K(0), T, .wood)
        b.box("Shelf", W(-0.5, 0.018), W(0.5, -0.018), Fr, Bk, H(0.5), H(0.5, 0.018), .wood, plan: false)
        b.box("Top", L, R, Fr, Bk, H(1, -0.018), T, .wood)
        b.box("Back", W(-0.5, 0.018), W(0.5, -0.018), D(0.5, -0.008), Bk, K(0), T, .wood, plan: false)
        b.outline()
        b.inch("\(inch(36)) x \(inch(30))", 36, 12, 30); b.mm("900 x 750", 900, 300, 750)
        return b.item
    }

    static func shoeCabinet() -> ComponentLibraryItem {
        var b = FB("Shoe Cabinet", .furniture, group: "Storage", keywords: ["shoe rack", "shoe storage", "entry"], "Slim shoe cabinet with tilt-out fronts.")
        b.box("Body", L, R, Fr, Bk, K(0.05), T, .laminate)
        b.box("Plinth", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.02), Bk, K(0), K(0.05), .laminate, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch(inch(36), 36, 12, 40); b.mm("900", 900, 300, 1000)
        return b.item
    }

    static func displayCabinet() -> ComponentLibraryItem {
        var b = FB("Display Cabinet - Glass", .furniture, group: "Storage", keywords: ["vitrine", "curio", "showcase"], "Tall glass-fronted display cabinet.")
        b.box("Frame", L, R, D(-0.5, 0.02), Bk, K(0), T, .woodDark)
        b.box("Glass Front", W(-0.5, 0.02), W(0.5, -0.02), Fr, D(-0.5, 0.02), K(0.1), H(1, -0.05), .glass, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch(inch(36), 36, 16, 72); b.mm("900", 900, 400, 1800)
        return b.item
    }

    static func steelCabinet() -> ComponentLibraryItem {
        var b = FB("Storage Cabinet - Steel", .furniture, group: "Storage", keywords: ["utility cabinet", "almirah", "steel cupboard", "stationery"],
                   "Two-door steel storage cabinet.")
        b.box("Body", L, R, Fr, Bk, K(0), T, .steelDark)
        b.outline(); b.line(K(0), Fr, K(0), D(-0.5, 0.03))
        b.inch("\(inch(36)) x \(inch(18)) x \(inch(72))", 36, 18, 72); b.mm("900 x 450 x 1800", 900, 450, 1800)
        return b.item
    }

    static func coatStand() -> ComponentLibraryItem {
        var b = FB("Coat Stand", .furniture, group: "Storage", keywords: ["hat stand", "coat rack", "hall stand"], "Freestanding coat stand.")
        b.cyl("Pole", K(0), K(0), K(0.02), K(0), T, .woodDark)
        b.cyl("Base", K(0), K(0), W(0.5), K(0), K(0.03), .woodDark)
        for (i, a) in [45.0, 135, 225, 315].enumerated() {
            let r = a * .pi / 180
            b.bar("Hook \(i + 1)", [(K(0), K(0)), (W(0.35 * cos(r)), W(0.35 * sin(r)))], z: H(1, -0.12), r: K(0.01), .woodDark, sides: 6, plan: false)
        }
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), K(0.02))
        b.any("Standard", 0.45, 0.45, 1.8)
        return b.item
    }

    static func prayerUnit() -> ComponentLibraryItem {
        var b = FB("Prayer Unit", .furniture, group: "Storage", regions: [.india], keywords: ["pooja unit", "mandir", "altar", "shrine"],
                   "Cabinet with an open alcove and storage below.")
        b.box("Base", L, R, Fr, Bk, K(0), H(0.45), .wood)
        b.box("Back Panel", L, R, D(0.5, -0.05), Bk, H(0.45), T, .wood)
        b.box("Canopy", L, R, Fr, Bk, H(1, -0.12), T, .wood)
        b.box("Side Left", L, W(-0.5, 0.04), Fr, Bk, H(0.45), T, .wood, plan: false)
        b.box("Side Right", W(0.5, -0.04), R, Fr, Bk, H(0.45), T, .wood, plan: false)
        b.outline(); b.line(L, D(0.5, -0.05), R, D(0.5, -0.05), .hidden)
        b.mm("Floor 900", 900, 450, 1800); b.mm("Floor 1200", 1200, 500, 2000)
        return b.item
    }

    static func cubeStorage() -> ComponentLibraryItem {
        var b = FB("Cube Storage - 3 x 3", .furniture, group: "Storage", keywords: ["cubby", "shelving", "room divider"], "Nine-cube open shelving.")
        b.box("Outer Left", L, W(-0.5, 0.02), Fr, Bk, K(0), T, .laminate)
        b.box("Outer Right", W(0.5, -0.02), R, Fr, Bk, K(0), T, .laminate)
        for (i, f) in [0.0, 1.0 / 3, 2.0 / 3].enumerated() {
            b.box("Shelf \(i + 1)", W(-0.5, 0.02), W(0.5, -0.02), Fr, Bk, H(f), H(f, 0.02), .laminate, plan: false)
        }
        b.box("Top", L, R, Fr, Bk, H(1, -0.02), T, .laminate, plan: false)
        b.box("Divider 1", W(-1.0 / 6, -0.01), W(-1.0 / 6, 0.01), Fr, Bk, K(0), T, .laminate, plan: false)
        b.box("Divider 2", W(1.0 / 6, -0.01), W(1.0 / 6, 0.01), Fr, Bk, K(0), T, .laminate, plan: false)
        b.outline(); b.line(W(-1.0 / 6), Fr, W(-1.0 / 6), Bk, .hidden); b.line(W(1.0 / 6), Fr, W(1.0 / 6), Bk, .hidden)
        b.inch(inch(44), 44, 15, 44); b.mm("1120", 1120, 390, 1120)
        return b.item
    }

    static func wallShelf() -> ComponentLibraryItem {
        var b = FB("Shelf - Wall Mounted", .furniture, group: "Storage", keywords: ["floating shelf", "ledge", "wall shelf"],
                   instance: ["Mounting Height"], "Floating wall shelf; Mounting Height is the shelf top above the level.")
        b.box("Shelf", L, R, Fr, Bk, P("Mounting Height") - H(1), P("Mounting Height"), .wood)
        b.rect(L, Fr, R, Bk, .hidden)
        b.inch(inch(36), 36, 10, 1.5, ["Mounting Height": 54]); b.mm("900", 900, 250, 40, ["Mounting Height": 1400])
        return b.item
    }
}
