import Foundation

// Office, hospitality, education and healthcare furniture and equipment.
extension LibraryContent {

    // MARK: Office

    static func office() -> [ComponentLibraryItem] {
        [deskRect(), deskL(), deskSitStand(), cluster(1), cluster(2), cluster(3), taskChair(), conferenceChair(), visitorChair(),
         conferenceTableRect(), conferenceTableRound(), filingVertical(), filingLateral(), mobilePedestal(), receptionDesk(), receptionDeskL(),
         credenza(), whiteboard(), printer(), waterDispenser(), phoneBooth()]
    }

    static func deskRect() -> ComponentLibraryItem {
        var b = FB("Desk - Rectangular", .furniture, group: "Office", keywords: ["desk", "writing table", "office table", "workstation"],
                   "Office desk with panel ends and a modesty panel.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.025), T, .laminate)
        b.box("End Left", W(-0.5, 0.02), W(-0.5, 0.045), D(-0.5, 0.03), D(0.5, -0.03), K(0), H(1, -0.025), .laminate, plan: false)
        b.box("End Right", W(0.5, -0.045), W(0.5, -0.02), D(-0.5, 0.03), D(0.5, -0.03), K(0), H(1, -0.025), .laminate, plan: false)
        b.box("Modesty Panel", W(-0.5, 0.045), W(0.5, -0.045), D(0.5, -0.12), D(0.5, -0.1), H(0.35), H(1, -0.025), .laminate, plan: false)
        b.outline()
        b.inch("\(inch(48)) x \(inch(24))", 48, 24, 29); b.inch("\(inch(60)) x \(inch(30))", 60, 30, 29); b.inch("\(inch(72)) x \(inch(30))", 72, 30, 29)
        b.mm("1200 x 600", 1200, 600, 740); b.mm("1400 x 700", 1400, 700, 740); b.mm("1600 x 800", 1600, 800, 740); b.mm("1800 x 800", 1800, 800, 740)
        return b.item
    }

    static func deskL() -> ComponentLibraryItem {
        var b = FB("Desk - L-Shaped", .furniture, group: "Office", keywords: ["corner desk", "return desk", "workstation"],
                   extra: ["Top Depth", "Return Depth"], "L-shaped desk with the return on the right (mirror for a left return).")
        let td = P("Top Depth"), rd = P("Return Depth")
        b.box("Main Top", L, R, Bk - td, Bk, H(1, -0.025), T, .laminate)
        b.box("Return Top", R - rd, R, Fr, Bk - td, H(1, -0.025), T, .laminate)
        b.box("End Left", W(-0.5, 0.02), W(-0.5, 0.045), Bk - td + 0.03, D(0.5, -0.03), K(0), H(1, -0.025), .laminate, plan: false)
        b.box("End Return", R - rd + 0.03, R - 0.03, D(-0.5, 0.02), D(-0.5, 0.045), K(0), H(1, -0.025), .laminate, plan: false)
        b.box("Corner Leg", W(0.5, -0.07), W(0.5, -0.02), D(0.5, -0.07), D(0.5, -0.02), K(0), H(1, -0.025), .metal, plan: false)
        b.poly([(L, Bk - td), (R - rd, Bk - td), (R - rd, Fr), (R, Fr), (R, Bk), (L, Bk)])
        b.line(R - rd, Bk - td, R, Bk - td, .hidden)
        b.inch("\(inch(60)) x \(inch(60))", 60, 60, 29, ["Top Depth": 30, "Return Depth": 24]); b.inch("\(inch(72)) x \(inch(72))", 72, 72, 29, ["Top Depth": 30, "Return Depth": 24])
        b.mm("1500 x 1500", 1500, 1500, 740, ["Top Depth": 750, "Return Depth": 600]); b.mm("1800 x 1800", 1800, 1800, 740, ["Top Depth": 800, "Return Depth": 600])
        return b.item
    }

    static func deskSitStand() -> ComponentLibraryItem {
        var b = FB("Desk - Height Adjustable", .furniture, group: "Office", keywords: ["sit stand", "standing desk", "electric desk"],
                   "Sit-stand desk on two telescopic columns (shown at sitting height).")
        b.box("Top", L, R, Fr, Bk, H(1, -0.025), T, .woodLight)
        for (i, x) in [W(-0.5, 0.12), W(0.5, -0.12)].enumerated() {
            b.box("Column \(i + 1)", x - 0.04, x + 0.04, D(-0.03), D(0.05), K(0.03), H(1, -0.05), .steelDark, plan: false)
            b.box("Foot \(i + 1)", x - 0.035, x + 0.035, D(-0.5, 0.04), D(0.5, -0.04), K(0), K(0.03), .steelDark, plan: false)
        }
        b.box("Frame", W(-0.5, 0.12), W(0.5, -0.12), D(0), D(0.08), H(1, -0.05), H(1, -0.025), .steelDark, plan: false)
        b.outline()
        b.inch("\(inch(60)) x \(inch(30))", 60, 30, 29); b.mm("1600 x 800", 1600, 800, 740)
        return b.item
    }

    /// Back-to-back desk cluster, `n` desks per side; Width is the cluster, Depth both desks.
    static func cluster(_ n: Int) -> ComponentLibraryItem {
        let people = n * 2
        var b = FB("Workstation Cluster - \(people) Person", .furniture, group: "Office", keywords: ["bench desk", "open plan", "workstations", "pod", "hot desk"],
                   "Back-to-back desks with a central screen and task chairs; Width x Depth is the desking.")
        b.box("Top Front", L, R, Fr, D(0, -0.015), H(1, -0.025), T, .laminate)
        b.box("Top Back", L, R, D(0, 0.015), Bk, H(1, -0.025), T, .laminate)
        b.box("Screen", L, R, D(0, -0.015), D(0, 0.015), K(0.45), H(1, 0.45), .fabricAccent)
        for i in 0...n {
            let x = W(Double(i) / Double(n) - 0.5)
            b.box("Leg \(i + 1)", x - 0.03, x + 0.03, D(-0.5, 0.05), D(0.5, -0.05), K(0), H(1, -0.025), .metal, plan: false)
        }
        b.outline(); b.line(L, K(0), R, K(0))
        for i in 0..<n {
            let x = W((Double(i) + 0.5) / Double(n) - 0.5)
            if i > 0 { b.line(W(Double(i) / Double(n) - 0.5), Fr, W(Double(i) / Double(n) - 0.5), Bk) }
            chairSolid(&b, "Chair Front \(i + 1)", x, D(-0.5, -0.3), w: 0.5, d: 0.5, angle: 180)
            chairSymbol(&b, x, D(-0.5, -0.3), w: 0.5, d: 0.5, angle: 180)
            chairSolid(&b, "Chair Back \(i + 1)", x, D(0.5, 0.3), w: 0.5, d: 0.5)
            chairSymbol(&b, x, D(0.5, 0.3), w: 0.5, d: 0.5)
        }
        let perDeskIn = [60.0, 60.0], perDeskMM = [1400.0, 1600.0]
        b.inch("\(inch(perDeskIn[0] * Double(n))) x \(inch(60))", perDeskIn[0] * Double(n), 60, 29)
        for w in perDeskMM { b.mm("\(Int(w * Double(n))) x \(Int(w))", w * Double(n), w, 740) }
        return b.item
    }

    static func taskChair() -> ComponentLibraryItem {
        var b = FB("Chair - Task", .furniture, group: "Office", keywords: ["office chair", "swivel chair", "desk chair", "ergonomic"],
                   "Swivel task chair with arms on a five-star base.")
        for i in 0..<5 {
            let a = (90 + 72 * Double(i)) * .pi / 180
            b.bar("Base Arm \(i + 1)", [(K(0), K(0)), (W(0.46 * cos(a)), D(0.46 * sin(a)))], z: K(0.07), r: K(0.018), .plasticDark, sides: 6, plan: false)
            b.ball("Caster \(i + 1)", W(0.46 * cos(a)), D(0.46 * sin(a)), K(0.025), K(0.025), .plasticDark, plan: false, steps: 4)
        }
        b.cyl("Column", K(0), K(0), K(0.025), K(0.08), H(0.42), .chrome, plan: false)
        b.box("Seat", W(-0.37), W(0.37), D(-0.4), D(0.28), H(0.42), H(0.49), .fabric)
        b.box("Back", W(-0.33), W(0.33), D(0.3), D(0.36), H(0.55), T, .fabric)
        b.box("Arm Left", W(-0.4), W(-0.35), D(-0.2), D(0.2), H(0.62), H(0.65), .plasticDark)
        b.box("Arm Right", W(0.35), W(0.4), D(-0.2), D(0.2), H(0.62), H(0.65), .plasticDark)
        b.circle(K(0), K(0), W(0.46), .hidden)
        b.rrect(W(-0.37), D(-0.4), W(0.37), D(0.28), K(0.04)); b.rect(W(-0.33), D(0.3), W(0.33), D(0.36))
        b.rect(W(-0.4), D(-0.2), W(-0.35), D(0.2)); b.rect(W(0.35), D(-0.2), W(0.4), D(0.2))
        b.any("Standard", 0.66, 0.66, 1.0); b.any("High Back", 0.66, 0.66, 1.2)
        return b.item
    }

    static func conferenceChair() -> ComponentLibraryItem {
        var b = FB("Chair - Conference", .furniture, group: "Office", keywords: ["meeting chair", "boardroom chair", "cantilever"],
                   "Conference chair on a sled base.")
        b.bar("Sled Left", [(W(-0.42), D(-0.45)), (W(-0.42), D(0.4))], z: K(0.015), r: K(0.012), .chrome, sides: 6, plan: false)
        b.bar("Sled Right", [(W(0.42), D(-0.45)), (W(0.42), D(0.4))], z: K(0.015), r: K(0.012), .chrome, sides: 6, plan: false)
        b.box("Post Left", W(-0.44), W(-0.4), D(0.3), D(0.34), K(0), H(0.5), .chrome, plan: false)
        b.box("Post Right", W(0.4), W(0.44), D(0.3), D(0.34), K(0), H(0.5), .chrome, plan: false)
        b.box("Seat", W(-0.42), W(0.42), D(-0.45), D(0.35), H(0.48), H(0.53), .leather)
        b.box("Back", W(-0.42), W(0.42), D(0.35), D(0.45), H(0.55), T, .leather)
        b.rrect(W(-0.42), D(-0.45), W(0.42), D(0.35), K(0.03)); b.rect(W(-0.42), D(0.35), W(0.42), D(0.45))
        b.any("Standard", 0.56, 0.6, 0.9); b.any("High Back", 0.56, 0.62, 1.1)
        return b.item
    }

    static func visitorChair() -> ComponentLibraryItem {
        var b = FB("Chair - Visitor", .furniture, group: "Office", keywords: ["guest chair", "side chair", "waiting chair"], "Four-legged visitor chair with arms.")
        legs(&b, inset: 0.02, size: 0.03, K(0), H(0.53), .metal)
        b.box("Seat", L, R, Fr, D(0.5, -0.05), H(0.51), H(0.57), .fabricAccent)
        b.box("Back", L, R, D(0.5, -0.05), Bk, H(0.57), T, .fabricAccent)
        b.box("Arm Left", L, W(-0.5, 0.04), Fr, D(0.5, -0.05), H(0.71), H(0.75), .metal)
        b.box("Arm Right", W(0.5, -0.04), R, Fr, D(0.5, -0.05), H(0.71), H(0.75), .metal)
        b.outline(); b.line(L, D(0.5, -0.05), R, D(0.5, -0.05))
        b.any("Standard", 0.58, 0.56, 0.84)
        return b.item
    }

    static func conferenceTableRect() -> ComponentLibraryItem {
        var b = FB("Table - Conference Rectangular", .furniture, group: "Office", keywords: ["meeting table", "boardroom table", "seats"],
                   "Conference table on panel bases; type names give the seating.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.03), T, .woodDark)
        for (i, f) in [-0.3, 0.3].enumerated() {
            b.box("Base \(i + 1)", W(f, -0.25), W(f, 0.25), D(-0.18), D(0.18), K(0), H(1, -0.03), .steelDark, plan: false)
        }
        b.outline(); b.rect(W(-0.3, -0.25), D(-0.18), W(-0.3, 0.25), D(0.18), .hidden); b.rect(W(0.3, -0.25), D(-0.18), W(0.3, 0.25), D(0.18), .hidden)
        for (s, w, d) in [(6, 72.0, 42.0), (8, 96, 42), (10, 120, 48), (12, 144, 48), (14, 168, 54), (16, 192, 54), (20, 240, 60)] {
            b.inch("\(s) Seat \(inch(w)) x \(inch(d))", w, d, 29)
        }
        for (s, w, d) in [(4, 1400.0, 900.0), (6, 1800, 1000), (8, 2400, 1200), (10, 3000, 1200), (12, 3600, 1400), (16, 4800, 1400), (20, 6000, 1600)] {
            b.mm("\(s) Seat \(Int(w)) x \(Int(d))", w, d, 740)
        }
        return b.item
    }

    static func conferenceTableRound() -> ComponentLibraryItem {
        var b = FB("Table - Conference Round", .furniture, group: "Office", keywords: ["meeting table", "round table"], "Round meeting table on a disc base.")
        b.cyl("Top", K(0), K(0), W(0.5), H(1, -0.03), T, .woodDark)
        b.cyl("Column", K(0), K(0), K(0.06), K(0.02), H(1, -0.03), .steelDark, plan: false)
        b.cyl("Base", K(0), K(0), W(0.25), K(0), K(0.02), .steelDark, plan: false)
        b.circle(K(0), K(0), W(0.5))
        b.inch("4 Seat \(inch(42))", 42, 42, 29); b.inch("5 Seat \(inch(48))", 48, 48, 29)
        b.mm("4 Seat 1050", 1050, 1050, 740); b.mm("5 Seat 1200", 1200, 1200, 740)
        return b.item
    }

    static func filingVertical() -> ComponentLibraryItem {
        var b = FB("Filing Cabinet - Vertical", .furniture, group: "Office", keywords: ["file cabinet", "filing", "drawers", "records"],
                   "Vertical filing cabinet; drawers pull out to the front.")
        b.box("Body", L, R, Fr, Bk, K(0), T, .steelDark)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02)); b.rect(W(-0.5, 0.02), D(-0.5, -0.5), W(0.5, -0.02), Fr, .hidden)
        b.inch("2 Drawer \(inch(15))", 15, 28, 28); b.inch("4 Drawer \(inch(15))", 15, 28, 52)
        b.mm("2 Drawer 470", 470, 620, 710); b.mm("4 Drawer 470", 470, 620, 1320)
        return b.item
    }

    static func filingLateral() -> ComponentLibraryItem {
        var b = FB("Filing Cabinet - Lateral", .furniture, group: "Office", keywords: ["file cabinet", "lateral file", "drawers"], "Lateral filing cabinet.")
        b.box("Body", L, R, Fr, Bk, K(0), T, .steelDark)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch("2 Drawer \(inch(30))", 30, 18, 28); b.inch("2 Drawer \(inch(36))", 36, 18, 28)
        b.mm("2 Drawer 800", 800, 460, 720); b.mm("2 Drawer 900", 900, 460, 720)
        return b.item
    }

    static func mobilePedestal() -> ComponentLibraryItem {
        var b = FB("Pedestal - Mobile", .furniture, group: "Office", keywords: ["drawer unit", "under desk", "caddy"], "Three-drawer mobile pedestal on casters.")
        b.box("Body", L, R, Fr, Bk, K(0.05), T, .laminate)
        for (i, (x, y)) in [(W(-0.5, 0.05), D(-0.5, 0.05)), (W(0.5, -0.05), D(-0.5, 0.05)), (W(0.5, -0.05), D(0.5, -0.05)), (W(-0.5, 0.05), D(0.5, -0.05))].enumerated() {
            b.ball("Caster \(i + 1)", x, y, K(0.025), K(0.025), .plasticDark, plan: false, steps: 4)
        }
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch(inch(16), 16, 22, 24); b.mm("400", 400, 550, 600)
        return b.item
    }

    static func receptionDesk() -> ComponentLibraryItem {
        var b = FB("Reception Desk", .furniture, group: "Office", keywords: ["front desk", "reception counter", "concierge", "lobby"],
                   "Reception desk: worktop behind a raised transaction counter at the front.")
        b.box("Front Panel", L, R, Fr, D(-0.5, 0.05), K(0), H(1, -0.03), .woodDark)
        b.box("Transaction Top", L, R, D(-0.5, -0.05), D(-0.5, 0.35), H(1, -0.03), T, .stone)
        b.box("End Left", L, W(-0.5, 0.05), D(-0.5, 0.05), Bk, K(0), K(0.74), .woodDark)
        b.box("End Right", W(0.5, -0.05), R, D(-0.5, 0.05), Bk, K(0), K(0.74), .woodDark)
        b.box("Worktop", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.05), Bk, K(0.71), K(0.74), .laminate)
        b.outline(); b.line(L, D(-0.5, 0.35), R, D(-0.5, 0.35)); b.line(L, D(-0.5, -0.05), R, D(-0.5, -0.05))
        b.line(W(-0.5, 0.05), D(-0.5, 0.05), W(-0.5, 0.05), Bk, .hidden); b.line(W(0.5, -0.05), D(-0.5, 0.05), W(0.5, -0.05), Bk, .hidden)
        b.inch(inch(72), 72, 30, 42); b.inch(inch(96), 96, 30, 42); b.mm("1800", 1800, 800, 1070); b.mm("2400", 2400, 800, 1070)
        return b.item
    }

    static func receptionDeskL() -> ComponentLibraryItem {
        var b = FB("Reception Desk - L-Shaped", .furniture, group: "Office", keywords: ["front desk", "reception counter", "corner"],
                   extra: ["Counter Depth"], "L-shaped reception desk with a raised counter along the front and the left side.")
        let cd = P("Counter Depth")
        b.box("Front", L, R, Fr, Fr + cd, K(0), T, .woodDark)
        b.box("Side", L, L + cd, Fr + cd, Bk, K(0), T, .woodDark)
        b.box("Worktop", L + cd, R, Fr + cd, Bk, K(0.71), K(0.74), .laminate)
        b.poly([(L, Fr), (R, Fr), (R, Bk), (L, Bk)])
        b.line(L + cd, Fr + cd, R, Fr + cd); b.line(L + cd, Fr + cd, L + cd, Bk)
        b.inch("\(inch(96)) x \(inch(72))", 96, 72, 42, ["Counter Depth": 16]); b.mm("2400 x 1800", 2400, 1800, 1070, ["Counter Depth": 400])
        return b.item
    }

    static func credenza() -> ComponentLibraryItem {
        var b = FB("Credenza", .furniture, group: "Office", keywords: ["storage", "sideboard", "office cabinet"], "Low office storage credenza.")
        b.box("Body", L, R, Fr, Bk, K(0.05), T, .woodDark)
        b.box("Plinth", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.02), Bk, K(0), K(0.05), .steelDark, plan: false)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch(inch(72), 72, 20, 29); b.mm("1800", 1800, 500, 740)
        return b.item
    }

    static func whiteboard() -> ComponentLibraryItem {
        var b = FB("Whiteboard - Wall Mounted", .specialtyEquipment, group: "Office", keywords: ["marker board", "writing board", "dry erase"],
                   instance: ["Mounting Height"], "Wall-mounted whiteboard with a pen tray; Mounting Height is the bottom edge.")
        b.box("Board", L, R, D(0.5, -0.02), Bk, P("Mounting Height"), P("Mounting Height") + H(1), .laminate)
        b.box("Tray", L, R, D(0.5, -0.07), D(0.5, -0.02), P("Mounting Height") - 0.03, P("Mounting Height"), .metal)
        b.rect(L, D(0.5, -0.07), R, Bk)
        b.inch("\(inch(72)) x \(inch(48))", 72, 3, 48, ["Mounting Height": 36]); b.inch("\(inch(96)) x \(inch(48))", 96, 3, 48, ["Mounting Height": 36])
        b.mm("1800 x 1200", 1800, 80, 1200, ["Mounting Height": 900]); b.mm("2400 x 1200", 2400, 80, 1200, ["Mounting Height": 900])
        return b.item
    }

    static func printer() -> ComponentLibraryItem {
        var b = FB("Printer - Multifunction", .specialtyEquipment, group: "Office", keywords: ["copier", "photocopier", "scanner", "mfd"],
                   "Office multifunction printer.")
        b.box("Body", L, R, Fr, Bk, H(0.05), H(0.8), .plastic)
        b.box("Base", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, 0.02), D(0.5, -0.02), K(0), H(0.05), .plasticDark, plan: false)
        b.box("Scanner", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.05), D(0.5, -0.05), H(0.8), T, .plasticDark)
        b.outline(); b.rect(W(-0.5, 0.03), D(-0.5, 0.05), W(0.5, -0.03), D(0.5, -0.05))
        b.any("Floor Standing", 0.6, 0.66, 1.15); b.any("Desktop", 0.45, 0.4, 0.4)
        return b.item
    }

    static func waterDispenser() -> ComponentLibraryItem {
        var b = FB("Water Dispenser", .specialtyEquipment, group: "Office", keywords: ["water cooler", "bottle dispenser", "drinking water"],
                   "Floor-standing bottled water dispenser.")
        b.box("Cabinet", L, R, Fr, Bk, K(0), H(0.72), .plastic)
        b.cyl("Bottle", K(0), K(0), W(0.45), H(0.72), T, .water)
        b.outline(); b.circle(K(0), K(0), W(0.45))
        b.any("Standard", 0.32, 0.34, 1.4)
        return b.item
    }

    static func phoneBooth() -> ComponentLibraryItem {
        var b = FB("Phone Booth - Acoustic", .furniture, group: "Office", keywords: ["pod", "focus room", "call booth", "privacy"],
                   "Freestanding acoustic booth with a glazed front.")
        b.box("Back", L, R, D(0.5, -0.06), Bk, K(0), T, .fabricAccent)
        b.box("Side Left", L, W(-0.5, 0.06), Fr, D(0.5, -0.06), K(0), T, .fabricAccent)
        b.box("Side Right", W(0.5, -0.06), R, Fr, D(0.5, -0.06), K(0), T, .fabricAccent)
        b.box("Roof", W(-0.5, 0.06), W(0.5, -0.06), Fr, D(0.5, -0.06), H(1, -0.08), T, .fabricAccent, plan: false)
        b.box("Glazed Front", W(-0.5, 0.06), W(0.5, -0.06), Fr, D(-0.5, 0.02), K(0.02), H(1, -0.08), .glass, plan: false)
        b.box("Shelf", W(-0.5, 0.06), W(0.5, -0.06), D(0.5, -0.4), D(0.5, -0.06), K(1.0), K(1.03), .woodLight)
        b.outline(); b.rect(W(-0.5, 0.06), D(-0.5, 0.02), W(0.5, -0.06), D(0.5, -0.06))
        b.any("Single", 1.0, 1.0, 2.2); b.any("Double", 2.0, 1.3, 2.2)
        return b.item
    }

    // MARK: Hospitality, education, healthcare

    static func institutional() -> [ComponentLibraryItem] {
        [lockers(tiers: 1), lockers(tiers: 2), studentDesk(double: false), studentDesk(double: true), stackingChair(), trainingTable(), lectern(),
         cafeteriaTable(), boothSeating(), luggageRack(), hospitalBed(), examTable(), bedsideCabinet(), overbedTable(), wheelchair(), ivStand()]
    }

    static func lockers(tiers: Int) -> ComponentLibraryItem {
        var b = FB("Lockers - \(tiers == 1 ? "Single" : "Double") Tier 3 Wide", .specialtyEquipment, group: "Education",
                   keywords: ["locker", "lockers", "changing room", "gym", "staff"], "Bank of three steel lockers on a arcus; Width is the bank.")
        b.box("Plinth", L, R, D(-0.5, 0.05), Bk, K(0), K(0.1), .steelDark, plan: false)
        b.box("Body", L, R, Fr, Bk, K(0.1), T, .metal)
        b.outline()
        for f in [-1.0 / 6, 1.0 / 6] { b.line(W(f), Fr, W(f), D(-0.5, 0.05)) }
        b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.inch("3 x \(inch(12))", 36, 18, 72); b.inch("3 x \(inch(15))", 45, 18, 72)
        b.mm("3 x 300", 900, 450, 1800); b.mm("3 x 400", 1200, 500, 1800)
        return b.item
    }

    static func studentDesk(double: Bool) -> ComponentLibraryItem {
        var b = FB(double ? "Desk - Student Double" : "Desk - Student", .furniture, group: "Education",
                   keywords: ["school desk", "classroom desk", "student table", "bench desk"], "Classroom desk on a steel frame with a book tray.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.02), T, .woodLight)
        legs(&b, inset: 0.02, size: 0.025, K(0), H(1, -0.02), .steelDark)
        b.box("Book Tray", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.05), D(0.5, -0.03), H(1, -0.14), H(1, -0.12), .steelDark, plan: false)
        b.outline()
        if double {
            b.line(K(0), Fr, K(0), Bk, .hidden)
            b.inch("\(inch(48)) x \(inch(18))", 48, 18, 29); b.mm("1200 x 450", 1200, 450, 760)
        } else {
            b.inch("\(inch(24)) x \(inch(18))", 24, 18, 29); b.mm("600 x 450", 600, 450, 760); b.mm("Junior 600 x 450", 600, 450, 640)
        }
        return b.item
    }

    static func stackingChair() -> ComponentLibraryItem {
        var b = FB("Chair - Stacking", .furniture, group: "Education", keywords: ["classroom chair", "student chair", "event chair", "shell chair"],
                   "Stacking shell chair on steel legs.")
        legs(&b, inset: 0.03, size: 0.02, K(0), H(0.49), .steelDark)
        b.box("Seat", L, R, Fr, D(0.5, -0.04), H(0.48), H(0.52), .plastic)
        b.blend("Back", [(L, D(0.5, -0.05)), (R, D(0.5, -0.05)), (R, D(0.5, -0.02)), (L, D(0.5, -0.02))],
                [(L, D(0.5, -0.03)), (R, D(0.5, -0.03)), (R, Bk), (L, Bk)], H(0.52), T, .plastic)
        b.outline(); b.line(L, D(0.5, -0.05), R, D(0.5, -0.05))
        b.any("Adult", 0.47, 0.52, 0.8); b.any("Junior", 0.4, 0.44, 0.66)
        return b.item
    }

    static func trainingTable() -> ComponentLibraryItem {
        var b = FB("Table - Training", .furniture, group: "Education", keywords: ["seminar table", "flip top", "classroom table"], "Flip-top training table on casters.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.025), T, .laminate)
        for (i, x) in [W(-0.5, 0.1), W(0.5, -0.1)].enumerated() {
            b.box("Upright \(i + 1)", x - 0.025, x + 0.025, D(-0.02), D(0.02), K(0.06), H(1, -0.025), .metal, plan: false)
            b.box("Foot \(i + 1)", x - 0.02, x + 0.02, D(-0.5, 0.04), D(0.5, -0.04), K(0.03), K(0.06), .metal, plan: false)
        }
        b.box("Modesty", W(-0.5, 0.1), W(0.5, -0.1), D(0.5, -0.05), D(0.5, -0.04), H(0.45), H(1, -0.025), .metal, plan: false)
        b.outline()
        b.inch("\(inch(60)) x \(inch(24))", 60, 24, 29); b.inch("\(inch(72)) x \(inch(24))", 72, 24, 29)
        b.mm("1500 x 600", 1500, 600, 740); b.mm("1800 x 600", 1800, 600, 740)
        return b.item
    }

    static func lectern() -> ComponentLibraryItem {
        var b = FB("Lectern", .furniture, group: "Education", keywords: ["podium", "speaker stand", "rostrum"], "Lectern with a sloped reading desk.")
        b.box("Base", L, R, Fr, Bk, K(0), K(0.05), .woodDark)
        b.box("Body", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.05), D(0.5, -0.05), K(0.05), H(1, -0.1), .woodDark)
        b.blend("Desk", [(L, Fr), (R, Fr), (R, Bk), (L, Bk)], [(L, Fr), (R, Fr), (R, D(-0.5, 0.04)), (L, D(-0.5, 0.04))], H(1, -0.1), T, .woodDark)
        b.outline(); b.rect(W(-0.5, 0.05), D(-0.5, 0.05), W(0.5, -0.05), D(0.5, -0.05), .hidden)
        b.any("Standard", 0.6, 0.5, 1.2)
        return b.item
    }

    static func cafeteriaTable() -> ComponentLibraryItem {
        var b = FB("Table - Cafeteria with Benches", .furniture, group: "Education", keywords: ["canteen", "mess hall", "lunch table", "refectory"],
                   "Table with two attached benches; Depth includes the benches.")
        b.box("Top", L, R, D(-0.2), D(0.2), H(1, -0.03), T, .laminate)
        b.box("Bench Front", L, R, Fr, D(-0.5, 0.28), K(0.42), K(0.45), .laminate)
        b.box("Bench Back", L, R, D(0.5, -0.28), Bk, K(0.42), K(0.45), .laminate)
        for (i, x) in [W(-0.5, 0.2), W(0.5, -0.2)].enumerated() {
            b.box("Frame \(i + 1)", x - 0.03, x + 0.03, D(-0.5, 0.05), D(0.5, -0.05), K(0), K(0.42), .metal, plan: false)
            b.box("Support \(i + 1)", x - 0.03, x + 0.03, D(-0.05), D(0.05), K(0.42), H(1, -0.03), .metal, plan: false)
        }
        b.rect(L, D(-0.2), R, D(0.2)); b.rect(L, Fr, R, D(-0.5, 0.28)); b.rect(L, D(0.5, -0.28), R, Bk)
        b.type(ft(8), .imperial, 2.438, 1.52, 0.76); b.mm("2400", 2400, 1500, 760)
        return b.item
    }

    static func boothSeating() -> ComponentLibraryItem {
        var b = FB("Booth Seating - Double", .furniture, group: "Hospitality", keywords: ["restaurant booth", "banquette", "diner", "cafe"],
                   "Two facing booth benches with a table between; Depth is the whole booth.")
        for (n, s) in [("Front", -1.0), ("Back", 1.0)] {
            let outer = D(0.5 * s), inner = D(0.5 * s, -0.55 * s), backIn = D(0.5 * s, -0.12 * s)
            b.box("\(n) Seat", L, R, s < 0 ? outer : inner, s < 0 ? inner : outer, K(0), K(0.45), .leather)
            b.box("\(n) Back", L, R, s < 0 ? outer : backIn, s < 0 ? backIn : outer, K(0.45), T, .leather)
            b.rect(L, outer, R, inner); b.line(L, backIn, R, backIn)
        }
        b.box("Table Top", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.55), D(0.5, -0.55), K(0.72), K(0.75), .woodDark)
        b.box("Table Column", W(-0.06), W(0.06), D(-0.06), D(0.06), K(0), K(0.72), .steelDark, plan: false)
        b.rect(W(-0.5, 0.05), D(-0.5, 0.55), W(0.5, -0.05), D(0.5, -0.55))
        b.inch("\(inch(48)) Table", 48, 70, 42); b.mm("1200 Table", 1200, 1800, 1070)
        return b.item
    }

    static func luggageRack() -> ComponentLibraryItem {
        var b = FB("Luggage Rack", .furniture, group: "Hospitality", keywords: ["suitcase stand", "hotel", "guest room"], "Folding luggage rack with straps.")
        b.box("Top Strap", L, R, Fr, Bk, H(1, -0.02), T, .leather)
        for (i, x) in [W(-0.5, 0.03), W(0.5, -0.03)].enumerated() {
            b.box("Leg Front \(i + 1)", x - 0.015, x + 0.015, D(-0.5, 0.02), D(-0.5, 0.05), K(0), H(1, -0.02), .wood, plan: false)
            b.box("Leg Back \(i + 1)", x - 0.015, x + 0.015, D(0.5, -0.05), D(0.5, -0.02), K(0), H(1, -0.02), .wood, plan: false)
        }
        b.outline()
        b.any("Standard", 0.66, 0.44, 0.52)
        return b.item
    }

    static func hospitalBed() -> ComponentLibraryItem {
        var b = FB("Bed - Hospital", .furniture, group: "Healthcare", keywords: ["patient bed", "ward", "icu", "medical bed"],
                   "Adjustable patient bed with side rails and casters, head section raised.")
        for (i, (x, y)) in [(W(-0.5, 0.06), D(-0.5, 0.06)), (W(0.5, -0.06), D(-0.5, 0.06)), (W(0.5, -0.06), D(0.5, -0.06)), (W(-0.5, 0.06), D(0.5, -0.06))].enumerated() {
            b.ball("Caster \(i + 1)", x, y, K(0.05), K(0.05), .plasticDark, plan: false, steps: 5)
        }
        b.box("Chassis", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.05), D(0.5, -0.05), K(0.12), K(0.35), .metal)
        b.box("Foot Mattress", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.08), D(0.15), K(0.35), H(1), .mattress)
        b.blend("Head Section", [(W(-0.5, 0.06), D(0.15)), (W(0.5, -0.06), D(0.15)), (W(0.5, -0.06), D(0.5, -0.1)), (W(-0.5, 0.06), D(0.5, -0.1))],
                [(W(-0.5, 0.06), D(0.2)), (W(0.5, -0.06), D(0.2)), (W(0.5, -0.06), D(0.35)), (W(-0.5, 0.06), D(0.35))], K(0.35), H(1, 0.45), .mattress)
        b.box("Headboard", L, R, D(0.5, -0.06), Bk, K(0.35), K(1.05), .plastic)
        b.box("Footboard", L, R, Fr, D(-0.5, 0.06), K(0.35), K(0.9), .plastic)
        b.box("Rail Left", L, W(-0.5, 0.03), D(-0.1), D(0.4), H(1, 0.05), H(1, 0.35), .plastic, plan: false)
        b.box("Rail Right", W(0.5, -0.03), R, D(-0.1), D(0.4), H(1, 0.05), H(1, 0.35), .plastic, plan: false)
        b.outline(); b.line(L, D(0.5, -0.06), R, D(0.5, -0.06)); b.line(L, D(-0.5, 0.06), R, D(-0.5, 0.06))
        b.line(W(-0.5, 0.06), D(0.15), W(0.5, -0.06), D(0.15))
        b.rect(L, D(-0.1), W(-0.5, 0.03), D(0.4)); b.rect(W(0.5, -0.03), D(-0.1), R, D(0.4))
        b.any("Standard", 1.0, 2.2, 0.62)
        return b.item
    }

    static func examTable() -> ComponentLibraryItem {
        var b = FB("Table - Examination", .furniture, group: "Healthcare", keywords: ["exam couch", "treatment table", "clinic", "doctor"],
                   "Examination couch with a raised head section.")
        b.box("Base", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, 0.1), D(0.5, -0.1), K(0), H(1, -0.08), .laminate)
        b.box("Pad", L, R, Fr, D(0.2), H(1, -0.08), T, .leather)
        b.blend("Head", [(L, D(0.2)), (R, D(0.2)), (R, Bk), (L, Bk)], [(L, D(0.3)), (R, D(0.3)), (R, D(0.4)), (L, D(0.4))], H(1, -0.08), H(1, 0.3), .leather)
        b.outline(); b.line(L, D(0.2), R, D(0.2))
        b.any("Standard", 0.7, 1.9, 0.75)
        return b.item
    }

    static func bedsideCabinet() -> ComponentLibraryItem {
        var b = FB("Bedside Cabinet - Patient", .furniture, group: "Healthcare", keywords: ["locker", "patient locker", "ward"], "Patient bedside cabinet on casters.")
        b.box("Body", L, R, Fr, Bk, K(0.06), T, .laminate)
        b.outline(); b.line(L, D(-0.5, 0.02), R, D(-0.5, 0.02))
        b.any("Standard", 0.45, 0.45, 0.85)
        return b.item
    }

    static func overbedTable() -> ComponentLibraryItem {
        var b = FB("Overbed Table", .furniture, group: "Healthcare", keywords: ["bed table", "patient table", "tray table"], "C-base overbed table.")
        b.box("Top", L, R, Fr, Bk, H(1, -0.025), T, .laminate)
        b.box("Column", W(-0.5, 0.03), W(-0.5, 0.08), D(-0.03), D(0.03), K(0.05), H(1, -0.025), .metal, plan: false)
        b.box("Base", W(-0.5, 0.02), W(-0.5, 0.09), D(-0.5, -0.05), D(0.5, 0.05), K(0), K(0.05), .metal)
        b.outline(); b.rect(W(-0.5, 0.02), D(-0.5, -0.05), W(-0.5, 0.09), D(0.5, 0.05), .hidden)
        b.any("Standard", 0.8, 0.4, 0.9)
        return b.item
    }

    static func wheelchair() -> ComponentLibraryItem {
        var b = FB("Wheelchair", .specialtyEquipment, group: "Healthcare", keywords: ["accessible", "mobility", "clearance"],
                   "Manual wheelchair for clearance studies.")
        b.box("Seat", W(-0.35), W(0.35), D(-0.3), D(0.25), K(0.46), K(0.5), .fabricAccent)
        b.box("Back", W(-0.35), W(0.35), D(0.25), D(0.3), K(0.5), T, .fabricAccent)
        for (n, x) in [("Left", -0.47), ("Right", 0.47)] {
            b.sweep("Wheel \(n)", [(W(x, -0.015), D(0.12)), (W(x, 0.015), D(0.12))],
                    ellipse(K(0), K(0.3), K(0.3), K(0.3), 16).map { ($0.1 - 0.3 + 0.0, $0.0 + 0.3) }, K(0), .rubber, plan: false)
            b.cyl("Caster \(n)", W(x * 0.7), D(-0.4), K(0.05), K(0), K(0.1), .rubber, plan: false)
        }
        b.box("Footrest", W(-0.25), W(0.25), D(-0.5), D(-0.38), K(0.12), K(0.15), .steelDark)
        b.rect(W(-0.5), D(-0.5), W(0.5), D(0.3)); b.rect(W(-0.35), D(-0.3), W(0.35), D(0.3))
        b.line(W(-0.47), D(-0.18), W(-0.47), D(0.42)); b.line(W(0.47), D(-0.18), W(0.47), D(0.42))
        b.any("Standard", 0.66, 1.07, 0.92)
        return b.item
    }

    static func ivStand() -> ComponentLibraryItem {
        var b = FB("IV Stand", .specialtyEquipment, group: "Healthcare", keywords: ["drip stand", "infusion pole", "medical"], "Mobile IV pole with a five-leg base.")
        b.cyl("Pole", K(0), K(0), K(0.012), K(0.05), T, .chrome)
        for i in 0..<5 {
            let a = (90 + 72 * Double(i)) * .pi / 180
            b.bar("Leg \(i + 1)", [(K(0), K(0)), (W(0.5 * cos(a)), D(0.5 * sin(a)))], z: K(0.06), r: K(0.012), .chrome, sides: 6, plan: false)
        }
        b.bar("Hooks", [(W(-0.2), K(0)), (W(0.2), K(0))], z: H(1, -0.02), r: K(0.008), .chrome, sides: 6, plan: false)
        b.circle(K(0), K(0), W(0.5), .hidden); b.circle(K(0), K(0), K(0.02))
        b.any("Standard", 0.55, 0.55, 2.0)
        return b.item
    }
}
