import Foundation

// Lighting fixtures, and visible electrical and mechanical items (AC units, fans, heaters, boards, chargers).
//
// Ceiling fixtures keep their insertion point on the level and hang from "Mounting Height" (the ceiling), so they show
// in floor plans where they are placed and in reflected ceiling plans.
extension LibraryContent {

    // MARK: Lighting

    static func lighting() -> [ComponentLibraryItem] {
        [downlightRound(), downlightSquare(), troffer(), panelSurface(), flushMount(), pendantDome(), pendantCylinder(), pendantLinear(), pendantLantern(),
         chandelierTiered(), chandelierRing(), sconce(shade: false), sconce(shade: true), batten(), slotLinear(), trackLight(), floorLamp(), floorLampArc(),
         tableLamp(), deskLamp(), bollardLight(), poleLight(), streetLight(double: false), streetLight(double: true), gardenLight(), stepLight(), floodLight(), exitSign()]
    }

    static let ceilingMetric: [String: Double] = ["Mounting Height": 2700]
    static let ceilingImperial: [String: Double] = ["Mounting Height": 108]

    static func downlightRound() -> ComponentLibraryItem {
        var b = FB("Downlight - Recessed Round", .lightingFixture, group: "Recessed", keywords: ["downlight", "can light", "pot light", "spot", "recessed"],
                   instance: ["Mounting Height"], "Round recessed downlight; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.cyl("Housing", K(0), K(0), W(0.42), z, z + H(1), .metal, plan: false)
        b.cyl("Trim", K(0), K(0), W(0.5), z - 0.008, z, .lens)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.3))
        b.line(W(-0.5), K(0), W(0.5), K(0)); b.line(K(0), W(-0.5), K(0), W(0.5))
        b.inch(inch(4), 4.75, 4.75, 5, ceilingImperial); b.inch(inch(6), 7, 7, 6, ceilingImperial)
        b.mm("100", 110, 110, 100, ceilingMetric); b.mm("150", 170, 170, 120, ceilingMetric); b.mm("200", 225, 225, 140, ceilingMetric)
        return b.item
    }

    static func downlightSquare() -> ComponentLibraryItem {
        var b = FB("Downlight - Recessed Square", .lightingFixture, group: "Recessed", keywords: ["downlight", "square downlight", "recessed"],
                   instance: ["Mounting Height"], "Square recessed downlight; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.box("Housing", W(-0.4), W(0.4), D(-0.4), D(0.4), z, z + H(1), .metal, plan: false)
        b.box("Trim", L, R, Fr, Bk, z - 0.008, z, .lens)
        b.outline(); b.rect(W(-0.3), D(-0.3), W(0.3), D(0.3)); b.line(L, Fr, R, Bk); b.line(L, Bk, R, Fr)
        b.mm("100", 110, 110, 100, ceilingMetric); b.mm("150", 170, 170, 120, ceilingMetric); b.inch(inch(4), 4.75, 4.75, 5, ceilingImperial)
        return b.item
    }

    static func troffer() -> ComponentLibraryItem {
        var b = FB("Troffer - Recessed", .lightingFixture, group: "Recessed", keywords: ["troffer", "grid light", "lay-in", "fluorescent", "led panel", "ceiling tile light"],
                   instance: ["Mounting Height"], "Lay-in troffer for suspended grid ceilings; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.box("Housing", W(-0.48), W(0.48), D(-0.48), D(0.48), z, z + H(1), .metal, plan: false)
        b.box("Diffuser", L, R, Fr, Bk, z - 0.01, z, .lens)
        b.outline(); b.line(L, Fr, R, Bk); b.line(L, Bk, R, Fr)
        b.type("\(ft(2)) x \(ft(2))", .imperial, 0.6096, 0.6096, 0.09, ["Mounting Height": 2.7432])
        b.type("\(ft(2)) x \(ft(4))", .imperial, 0.6096, 1.2192, 0.09, ["Mounting Height": 2.7432])
        b.type("\(ft(1)) x \(ft(4))", .imperial, 0.3048, 1.2192, 0.09, ["Mounting Height": 2.7432])
        b.mm("600 x 600", 597, 597, 80, ceilingMetric); b.mm("1200 x 300", 1197, 297, 80, ceilingMetric); b.mm("1200 x 600", 1197, 597, 80, ceilingMetric)
        return b.item
    }

    static func panelSurface() -> ComponentLibraryItem {
        var b = FB("Panel Light - Surface", .lightingFixture, group: "Ceiling", keywords: ["led panel", "surface panel", "flat panel"],
                   instance: ["Mounting Height"], "Surface-mounted LED panel; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.box("Frame", L, R, Fr, Bk, z - H(1), z, .metal)
        b.box("Diffuser", W(-0.5, 0.01), W(0.5, -0.01), D(-0.5, 0.01), D(0.5, -0.01), z - H(1) - 0.002, z - H(1), .lens, plan: false)
        b.outline(); b.rect(W(-0.5, 0.01), D(-0.5, 0.01), W(0.5, -0.01), D(0.5, -0.01))
        b.mm("300 x 300", 300, 300, 40, ceilingMetric); b.mm("600 x 600", 600, 600, 40, ceilingMetric); b.mm("1200 x 300", 1200, 300, 40, ceilingMetric)
        b.type("\(ft(2)) x \(ft(2))", .imperial, 0.6096, 0.6096, 0.04, ["Mounting Height": 2.7432])
        return b.item
    }

    static func flushMount() -> ComponentLibraryItem {
        var b = FB("Ceiling Light - Flush Mount", .lightingFixture, group: "Ceiling", keywords: ["ceiling light", "dome light", "oyster", "close to ceiling"],
                   instance: ["Mounting Height"], "Round flush-mount ceiling light; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.revolve("Dome", [(K(0), K(0)), (W(0.35), K(0)), (W(0.5), H(0.7)), (W(0.5), T), (K(0), T)], K(0), K(0), z - H(1), .lens)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.35))
        b.mm("300", 300, 300, 100, ceilingMetric); b.mm("400", 400, 400, 110, ceilingMetric); b.inch(inch(13), 13, 13, 5, ceilingImperial)
        return b.item
    }

    /// Cord from the ceiling to the top of a pendant whose shade is `shade` tall; Height is the overall drop.
    static func pendantCord(_ b: inout FB, shade: LX) {
        let z = P("Mounting Height")
        b.cyl("Canopy", K(0), K(0), K(0.05), z - 0.02, z, .metal, plan: false)
        b.cyl("Cord", K(0), K(0), K(0.006), z - H(1) + shade, z - 0.02, .rope, plan: false)
    }

    static func pendantDome() -> ComponentLibraryItem {
        var b = FB("Pendant - Dome", .lightingFixture, group: "Pendants", keywords: ["pendant", "hanging light", "dome", "bell"],
                   instance: ["Mounting Height"], "Dome pendant on a cord; Height is the drop from the ceiling.")
        let z0 = P("Mounting Height") - H(1)
        pendantCord(&b, shade: W(0.45))
        b.revolve("Shade", [(W(0.5), K(0)), (W(0.46), K(0)), (W(0.1), W(0.43)), (K(0), W(0.43)), (K(0), W(0.45)), (W(0.12), W(0.45))], K(0), K(0), z0, .steelDark)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.12)); b.line(W(-0.5), K(0), W(0.5), K(0)); b.line(K(0), W(-0.5), K(0), W(0.5))
        b.mm("300", 300, 300, 900, ceilingMetric); b.mm("450", 450, 450, 1000, ceilingMetric)
        b.inch(inch(12), 12, 12, 36, ceilingImperial); b.inch(inch(18), 18, 18, 40, ceilingImperial)
        return b.item
    }

    static func pendantCylinder() -> ComponentLibraryItem {
        var b = FB("Pendant - Cylinder", .lightingFixture, group: "Pendants", keywords: ["pendant", "hanging light", "cylinder", "tube"],
                   instance: ["Mounting Height"], "Cylinder pendant on a cord; Height is the drop from the ceiling.")
        let z0 = P("Mounting Height") - H(1)
        pendantCord(&b, shade: W(1.4))
        b.cyl("Body", K(0), K(0), W(0.5), z0, z0 + W(1.4), .brass)
        b.circle(K(0), K(0), W(0.5)); b.line(W(-0.5), K(0), W(0.5), K(0)); b.line(K(0), W(-0.5), K(0), W(0.5))
        b.mm("150", 150, 150, 800, ceilingMetric); b.mm("250", 250, 250, 900, ceilingMetric)
        b.inch(inch(6), 6, 6, 32, ceilingImperial); b.inch(inch(10), 10, 10, 36, ceilingImperial)
        return b.item
    }

    static func pendantLinear() -> ComponentLibraryItem {
        var b = FB("Pendant - Linear", .lightingFixture, group: "Pendants", keywords: ["linear pendant", "suspended linear", "office light", "bar light"],
                   instance: ["Mounting Height"], "Suspended linear fixture on two cables; Height is the drop from the ceiling.")
        let z = P("Mounting Height"), z0 = z - H(1)
        b.box("Body", L, R, Fr, Bk, z0, z0 + 0.07, .steelDark)
        b.box("Diffuser", W(-0.5, 0.01), W(0.5, -0.01), D(-0.5, 0.005), D(0.5, -0.005), z0 - 0.003, z0, .lens, plan: false)
        for (i, x) in [W(-0.4), W(0.4)].enumerated() { b.cyl("Cable \(i + 1)", x, K(0), K(0.006), z0 + 0.07, z, .metal, plan: false) }
        b.outline(); b.line(L, K(0), R, K(0))
        b.mm("1200", 1200, 70, 800, ceilingMetric); b.mm("2400", 2400, 70, 800, ceilingMetric)
        b.type(ft(4), .imperial, 1.2192, 0.07, 0.8, ["Mounting Height": 2.7432]); b.type(ft(8), .imperial, 2.4384, 0.07, 0.8, ["Mounting Height": 2.7432])
        return b.item
    }

    static func pendantLantern() -> ComponentLibraryItem {
        var b = FB("Pendant - Paper Lantern", .lightingFixture, group: "Pendants", regions: [.asia], keywords: ["lantern", "paper shade", "globe pendant", "chochin"],
                   instance: ["Mounting Height"], "Round paper lantern pendant; Height is the drop from the ceiling.")
        let z0 = P("Mounting Height") - H(1)
        pendantCord(&b, shade: W(1))
        b.ball("Lantern", K(0), K(0), z0 + W(0.5), W(0.5), .paperShade, steps: 10)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.35))
        b.mm("400", 400, 400, 900, ceilingMetric); b.mm("600", 600, 600, 1000, ceilingMetric)
        return b.item
    }

    static func chandelierTiered() -> ComponentLibraryItem {
        var b = FB("Chandelier - Classic", .lightingFixture, group: "Pendants", keywords: ["chandelier", "candelabra", "dining light"],
                   instance: ["Mounting Height"], "Chandelier with a ring of candle lights; Height is the drop from the ceiling.")
        let z = P("Mounting Height"), z0 = z - H(1)
        b.cyl("Stem", K(0), K(0), K(0.012), z0 + 0.1, z, .brass, plan: false)
        b.revolve("Body", [(K(0), K(0)), (K(0.08), K(0.05)), (K(0.05), K(0.2)), (K(0), K(0.2))], K(0), K(0), z0, .brass)
        let ring = ngon(K(0), K(0), W(0.45), 8, start: 0)
        b.bar("Ring", ring + [ring[0]], z: z0 + 0.12, r: K(0.012), .brass, sides: 6, plan: false)
        for (i, p) in ngon(K(0), K(0), W(0.45), 8, start: 0).enumerated() {
            b.cyl("Candle \(i + 1)", p.0, p.1, K(0.015), z0 + 0.13, z0 + 0.25, .lens, plan: false)
            b.circle(p.0, p.1, K(0.03))
        }
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.45)); b.circle(K(0), K(0), K(0.08))
        b.mm("600", 600, 600, 900, ceilingMetric); b.mm("900", 900, 900, 1100, ceilingMetric)
        b.inch(inch(24), 24, 24, 36, ceilingImperial); b.inch(inch(36), 36, 36, 44, ceilingImperial)
        return b.item
    }

    static func chandelierRing() -> ComponentLibraryItem {
        var b = FB("Chandelier - Ring", .lightingFixture, group: "Pendants", keywords: ["ring light", "halo", "circular pendant", "modern chandelier"],
                   instance: ["Mounting Height"], "Suspended LED ring on three cables; Height is the drop from the ceiling.")
        let z = P("Mounting Height"), z0 = z - H(1)
        let ring = ngon(K(0), K(0), W(0.48), 24, start: 0)
        b.bar("Ring", ring + [ring[0]], z: z0 + 0.02, r: K(0.02), .lens)
        for (i, p) in ngon(K(0), K(0), W(0.48), 3).enumerated() { b.cyl("Cable \(i + 1)", p.0, p.1, K(0.006), z0 + 0.04, z, .metal, plan: false) }
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.46))
        b.mm("600", 600, 600, 800, ceilingMetric); b.mm("1000", 1000, 1000, 900, ceilingMetric)
        b.inch(inch(24), 24, 24, 32, ceilingImperial); b.inch(inch(40), 40, 40, 36, ceilingImperial)
        return b.item
    }

    static func sconce(shade: Bool) -> ComponentLibraryItem {
        var b = FB(shade ? "Wall Sconce - Shade" : "Wall Sconce - Up and Down", .lightingFixture, group: "Wall", keywords: ["wall light", "sconce", "bracket light"],
                   instance: ["Mounting Height"], "Wall light; Mounting Height is its center. The back of the family is on the wall.")
        let z = P("Mounting Height")
        b.box("Back Plate", W(-0.2), W(0.2), D(0.5, -0.01), Bk, z - 0.06, z + 0.06, .metal, plan: false)
        if shade {
            b.bar("Arm", [(K(0), Bk), (K(0), K(0))], z: z, r: K(0.008), .brass, sides: 6, plan: false)
            b.revolve("Shade", [(W(0.3), K(0)), (W(0.5), K(0)), (W(0.3), H(1)), (W(0.2), H(1))], K(0), K(0), z - H(0.4), .paperShade)
            b.circle(K(0), K(0), W(0.5))
        } else {
            b.cyl("Body", K(0), K(0), W(0.5), z - H(0.5), z + H(0.5), .steelDark)
            b.circle(K(0), K(0), W(0.5))
        }
        b.line(W(-0.2), Bk, W(0.2), Bk)
        if shade { b.any("Standard", 0.2, 0.22, 0.2, ["Mounting Height": 1.7]) } else { b.any("Standard", 0.08, 0.1, 0.2, ["Mounting Height": 1.8]) }
        return b.item
    }

    static func batten() -> ComponentLibraryItem {
        var b = FB("Batten - LED Linear", .lightingFixture, group: "Linear & Track", keywords: ["tube light", "batten", "linear", "strip light", "fluorescent"],
                   instance: ["Mounting Height"], "Surface LED batten; Mounting Height is the ceiling or the wall height.")
        let z = P("Mounting Height")
        b.box("Body", L, R, Fr, Bk, z - H(1), z, .lens)
        b.outline(); b.line(L, K(0), R, K(0))
        b.mm("600", 600, 40, 40, ceilingMetric); b.mm("1200", 1200, 40, 40, ceilingMetric); b.mm("1500", 1500, 40, 40, ceilingMetric)
        b.type(ft(2), .imperial, 0.6096, 0.04, 0.04, ["Mounting Height": 2.7432]); b.type(ft(4), .imperial, 1.2192, 0.04, 0.04, ["Mounting Height": 2.7432])
        return b.item
    }

    static func slotLinear() -> ComponentLibraryItem {
        var b = FB("Linear - Recessed Slot", .lightingFixture, group: "Linear & Track", keywords: ["slot light", "linear", "recessed linear", "architectural"],
                   instance: ["Mounting Height"], "Recessed linear slot; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.box("Housing", L, R, Fr, Bk, z, z + H(1), .metal, plan: false)
        b.box("Diffuser", L, R, Fr, Bk, z - 0.005, z, .lens)
        b.outline(); b.line(L, K(0), R, K(0))
        b.mm("1200", 1200, 75, 90, ceilingMetric); b.mm("2400", 2400, 75, 90, ceilingMetric)
        b.type(ft(4), .imperial, 1.2192, 0.076, 0.09, ["Mounting Height": 2.7432]); b.type(ft(8), .imperial, 2.4384, 0.076, 0.09, ["Mounting Height": 2.7432])
        return b.item
    }

    static func trackLight() -> ComponentLibraryItem {
        var b = FB("Track Light - 3 Heads", .lightingFixture, group: "Linear & Track", keywords: ["track", "spot", "gallery", "retail"],
                   instance: ["Mounting Height"], "Ceiling track with three adjustable heads; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.box("Track", L, R, K(-0.018), K(0.018), z - 0.035, z, .steelDark)
        for (i, f) in [-0.33, 0.0, 0.33].enumerated() {
            b.cyl("Stem \(i + 1)", W(f), K(0), K(0.008), z - 0.09, z - 0.035, .steelDark, plan: false)
            b.bar("Head \(i + 1)", [(W(f), D(-0.5)), (W(f), D(0.5))], z: z - 0.12, r: K(0.035), .steelDark, sides: 10)
            b.rect(W(f, -0.035), D(-0.5), W(f, 0.035), D(0.5))
        }
        b.rect(L, K(-0.018), R, K(0.018))
        b.mm("1000", 1000, 160, 160, ceilingMetric); b.mm("2000", 2000, 160, 160, ceilingMetric)
        b.type(ft(4), .imperial, 1.2192, 0.16, 0.16, ["Mounting Height": 2.7432]); b.type(ft(8), .imperial, 2.4384, 0.16, 0.16, ["Mounting Height": 2.7432])
        return b.item
    }

    static func floorLamp() -> ComponentLibraryItem {
        var b = FB("Floor Lamp - Standard", .lightingFixture, group: "Lamps", keywords: ["floor lamp", "standard lamp", "reading lamp"], "Floor lamp with a drum shade.")
        b.cyl("Base", K(0), K(0), W(0.4), K(0), K(0.03), .steelDark)
        b.cyl("Stem", K(0), K(0), K(0.012), K(0.03), H(1, -0.25), .steelDark, plan: false)
        b.revolve("Shade", [(W(0.4), K(0)), (W(0.5), K(0)), (W(0.42), K(0.3)), (W(0.34), K(0.3))], K(0), K(0), H(1, -0.3), .paperShade)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.4))
        b.any("Standard", 0.45, 0.45, 1.6)
        return b.item
    }

    static func floorLampArc() -> ComponentLibraryItem {
        var b = FB("Floor Lamp - Arc", .lightingFixture, group: "Lamps", keywords: ["arc lamp", "overhanging lamp", "floor lamp"],
                   "Arching floor lamp; the base is at the back and the shade reaches forward.")
        b.box("Base", W(-0.15), W(0.15), D(0.5, -0.3), Bk, K(0), K(0.06), .stone)
        let pts: [(LX, LX)] = [(K(0), D(0.5, -0.15)), (K(0), D(0.1)), (K(0), D(-0.3)), (K(0), D(-0.5, 0.2))]
        b.cyl("Upright", K(0), D(0.5, -0.15), K(0.012), K(0.06), H(0.85), .chrome, plan: false)
        b.bar("Arc", Array(pts[0...2]), z: H(0.95), r: K(0.012), .chrome, sides: 6, plan: false)
        b.cyl("Drop", K(0), D(-0.3), K(0.008), H(0.75), H(0.95), .chrome, plan: false)
        b.revolve("Shade", [(K(0.02), K(0)), (W(0.5), K(0)), (K(0.03), K(0.2))], K(0), D(-0.3), H(0.6), .steelDark)
        b.rect(W(-0.15), D(0.5, -0.3), W(0.15), Bk); b.line(K(0), D(0.5, -0.15), K(0), D(-0.3)); b.circle(K(0), D(-0.3), W(0.5))
        b.any("Standard", 0.4, 1.8, 2.0)
        return b.item
    }

    static func tableLamp() -> ComponentLibraryItem {
        var b = FB("Table Lamp", .lightingFixture, group: "Lamps", keywords: ["lamp", "bedside lamp", "desk lamp"],
                   instance: ["Mounting Height"], "Table lamp with a shade; Mounting Height is the table top it stands on.")
        let z = P("Mounting Height")
        b.revolve("Body", [(K(0), K(0)), (W(0.28), K(0)), (W(0.32), H(0.25)), (W(0.12), H(0.5)), (K(0), H(0.5))], K(0), K(0), z, .terracotta)
        b.revolve("Shade", [(W(0.4), K(0)), (W(0.5), K(0)), (W(0.38), H(0.45)), (W(0.3), H(0.45))], K(0), K(0), z + H(0.55), .paperShade)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.28))
        b.any("Small", 0.3, 0.3, 0.45, ["Mounting Height": 0.55]); b.any("Large", 0.42, 0.42, 0.7, ["Mounting Height": 0.55])
        return b.item
    }

    static func deskLamp() -> ComponentLibraryItem {
        var b = FB("Desk Lamp - Task", .lightingFixture, group: "Lamps", keywords: ["task lamp", "reading light", "architect lamp"],
                   instance: ["Mounting Height"], "Adjustable task lamp; Mounting Height is the desk top.")
        let z = P("Mounting Height")
        b.cyl("Base", K(0), D(0.3), K(0.08), z, z + 0.03, .steelDark)
        b.cyl("Arm", K(0), D(0.3), K(0.008), z + 0.03, z + H(1), .steelDark, plan: false)
        b.bar("Reach", [(K(0), D(0.3)), (K(0), D(-0.35))], z: z + H(1), r: K(0.008), .steelDark, sides: 6, plan: false)
        b.revolve("Head", [(K(0.01), K(0)), (K(0.07), K(0)), (K(0.02), K(0.1))], K(0), D(-0.35), z + H(1, -0.1), .steelDark)
        b.circle(K(0), D(0.3), K(0.08)); b.line(K(0), D(0.3), K(0), D(-0.35)); b.circle(K(0), D(-0.35), K(0.07))
        b.any("Standard", 0.16, 0.6, 0.5, ["Mounting Height": 0.74])
        return b.item
    }

    static func bollardLight() -> ComponentLibraryItem {
        var b = FB("Bollard Light", .lightingFixture, group: "Exterior", keywords: ["bollard", "path light", "landscape light", "exterior"],
                   "Round exterior bollard light with a louvred head.")
        b.cyl("Post", K(0), K(0), W(0.5), K(0), H(1, -0.15), .steelDark)
        b.cyl("Lens", K(0), K(0), W(0.45), H(1, -0.15), H(1, -0.03), .lens, plan: false)
        b.cyl("Cap", K(0), K(0), W(0.5), H(1, -0.03), T, .steelDark, plan: false)
        b.circle(K(0), K(0), W(0.5)); b.arc(K(0), K(0), W(1.5), 0, 360, .hidden)
        b.inch("\(inch(36)) High", 8, 8, 36); b.inch("\(inch(42)) High", 8, 8, 42); b.mm("900 High", 200, 200, 900); b.mm("1000 High", 200, 200, 1000)
        return b.item
    }

    static func poleLight() -> ComponentLibraryItem {
        var b = FB("Pole Light - Site", .lightingFixture, group: "Exterior", keywords: ["area light", "parking lot light", "pole", "site lighting"],
                   "Site pole with a shoebox area luminaire on a short arm.")
        b.box("Base Plate", W(-0.1), W(0.1), D(-0.1), D(0.1), K(0), K(0.02), .steelDark, plan: false)
        b.cyl("Pole", K(0), K(0), K(0.06), K(0), H(1), .steelDark)
        b.bar("Arm", [(K(0), K(0)), (K(0), D(-0.5, 0.3))], z: H(1, -0.05), r: K(0.03), .steelDark, sides: 6, plan: false)
        b.box("Luminaire", W(-0.5), W(0.5), Fr, D(-0.5, 0.45), H(1, -0.12), H(1, -0.02), .steelDark)
        b.circle(K(0), K(0), K(0.06)); b.rect(W(-0.5), Fr, W(0.5), D(-0.5, 0.45)); b.line(K(0), K(0), K(0), D(-0.5, 0.45))
        for (n, h) in [(12.0, 12.0), (16, 16), (20, 20)] { b.type(ft(n), .imperial, 0.45, 0.9, h * 0.3048) }
        b.mm("4 m", 450, 900, 4000); b.mm("6 m", 450, 900, 6000)
        return b.item
    }

    static func streetLight(double: Bool) -> ComponentLibraryItem {
        var b = FB(double ? "Street Light - Double Arm" : "Street Light - Single Arm", .lightingFixture, group: "Exterior",
                   keywords: ["street lamp", "road light", "lamp post", "highway"], "Tapered street-light pole with outreach arm and luminaire; Depth is the arm reach.")
        b.taper("Pole", K(0), K(0), bottom: (K(0.09), K(0.09)), top: (K(0.045), K(0.045)), K(0), H(1), .metal)
        let arms: [Double] = double ? [-1, 1] : [-1]
        for s in arms {
            b.bar("Arm \(s < 0 ? "Front" : "Back")", [(K(0), K(0)), (K(0), D(0.5 * s, -0.25 * s))], z: H(1, -0.03), r: K(0.035), .metal, sides: 8, plan: false)
            b.box("Luminaire \(s < 0 ? "Front" : "Back")", W(-0.5), W(0.5), s < 0 ? Fr : D(0.5, -0.6), s < 0 ? D(-0.5, 0.6) : Bk, H(1, -0.12), H(1, -0.02), .metal)
            b.rect(W(-0.5), s < 0 ? Fr : D(0.5, -0.6), W(0.5), s < 0 ? D(-0.5, 0.6) : Bk)
            b.line(K(0), K(0), K(0), D(0.5 * s, -0.6 * s))
        }
        b.rect(K(-0.09), K(-0.09), K(0.09), K(0.09))
        if double {
            b.mm("10 m", 300, 4000, 10000); b.type(ft(30), .imperial, 0.3, 3.66, 9.144)
        } else {
            b.mm("8 m", 300, 3000, 8000); b.mm("10 m", 300, 3500, 10000); b.mm("12 m", 300, 3500, 12000)
            b.type(ft(25), .imperial, 0.3, 2.44, 7.62); b.type(ft(30), .imperial, 0.3, 3.05, 9.144)
        }
        return b.item
    }

    static func gardenLight() -> ComponentLibraryItem {
        var b = FB("Garden Light - Post Top", .lightingFixture, group: "Exterior", keywords: ["garden lamp", "lantern", "post top", "landscape"],
                   "Post-top lantern for gardens and paths.")
        b.cyl("Post", K(0), K(0), K(0.04), K(0), H(1, -0.3), .steelDark)
        b.taper("Lantern", K(0), K(0), bottom: (W(0.35), D(0.35)), top: (W(0.5), D(0.5)), H(1, -0.3), H(1, -0.06), .glass)
        b.taper("Roof", K(0), K(0), bottom: (W(0.55), D(0.55)), top: (K(0.02), K(0.02)), H(1, -0.06), T, .steelDark)
        b.rect(W(-0.55), D(-0.55), W(0.55), D(0.55)); b.circle(K(0), K(0), K(0.04))
        b.mm("1000", 250, 250, 1000); b.mm("2000", 300, 300, 2000); b.type(ft(3), .imperial, 0.25, 0.25, 0.9144); b.type(ft(6), .imperial, 0.3, 0.3, 1.8288)
        return b.item
    }

    static func stepLight() -> ComponentLibraryItem {
        var b = FB("Step Light - Recessed", .lightingFixture, group: "Wall", keywords: ["stair light", "step light", "marker light", "brick light"],
                   instance: ["Mounting Height"], "Recessed wall step light with a louvred face; Mounting Height is its center.")
        let z = P("Mounting Height")
        b.box("Faceplate", L, R, Fr, Bk, z - H(0.5), z + H(0.5), .steelDark)
        b.rect(L, Fr, R, Bk)
        b.any("Standard", 0.12, 0.02, 0.08, ["Mounting Height": 0.3])
        return b.item
    }

    static func floodLight() -> ComponentLibraryItem {
        var b = FB("Flood Light - Wall Mounted", .lightingFixture, group: "Exterior", keywords: ["flood light", "security light", "wall pack", "floodlight"],
                   instance: ["Mounting Height"], "Wall-mounted flood light on a bracket; Mounting Height is its center.")
        let z = P("Mounting Height")
        b.box("Bracket", W(-0.1), W(0.1), D(0.5, -0.03), Bk, z - 0.05, z + 0.05, .steelDark, plan: false)
        b.box("Body", L, R, Fr, D(0.5, -0.05), z - H(0.5), z + H(0.5), .steelDark)
        b.box("Lens", W(-0.5, 0.02), W(0.5, -0.02), D(-0.5, -0.003), Fr, z - H(0.5, -0.02), z + H(0.5, -0.02), .lens, plan: false)
        b.rect(L, Fr, R, D(0.5, -0.05)); b.line(W(-0.1), Bk, W(0.1), Bk)
        b.any("Standard", 0.3, 0.12, 0.25, ["Mounting Height": 3.0])
        return b.item
    }

    static func exitSign() -> ComponentLibraryItem {
        var b = FB("Exit Sign - Illuminated", .lightingFixture, group: "Wall", keywords: ["exit", "emergency", "egress sign", "fire exit"],
                   instance: ["Mounting Height"], "Illuminated exit sign; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Body", L, R, Fr, Bk, z, z + H(1), .signGreen)
        b.rect(L, Fr, R, Bk); b.line(L, Fr, R, Bk)
        b.any("Standard", 0.35, 0.05, 0.18, ["Mounting Height": 2.3])
        return b.item
    }

    // MARK: Electrical and mechanical

    static func mep() -> [ComponentLibraryItem] {
        [splitIndoor(), splitOutdoor(), cassette(), windowAC(), ceilingFan(), exhaustWall(), exhaustCeiling(), pedestalFan(), wallFan(), radiator(), towelRail(),
         waterHeaterTank(), waterHeaterTankless(), geyser(), distributionBoard(), evWallCharger()]
    }

    static func splitIndoor() -> ComponentLibraryItem {
        var b = FB("Split AC - Indoor Wall Unit", .mechanicalEquipment, group: "Air Conditioning", regions: [.global],
                   keywords: ["air conditioner", "split ac", "mini split", "ductless", "hvac", "indoor unit"],
                   instance: ["Mounting Height"], "High-wall split air-conditioner indoor unit; Mounting Height is its top.")
        let z = P("Mounting Height")
        b.box("Body", L, R, D(-0.5, 0.03), Bk, z - H(1), z, .plastic)
        b.box("Front Panel", L, R, Fr, D(-0.5, 0.03), z - H(0.75), z, .plastic, plan: false)
        b.box("Louvre", W(-0.5, 0.03), W(0.5, -0.03), Fr, D(-0.5, 0.03), z - H(1), z - H(0.8), .plasticDark, plan: false)
        b.rect(L, Fr, R, Bk, .hidden); b.line(L, D(-0.5, 0.03), R, D(-0.5, 0.03), .hidden)
        b.mm("1.0 TR 850", 850, 220, 290, ["Mounting Height": 2400], regions: [.india, .asia])
        b.mm("1.5 TR 950", 950, 230, 300, ["Mounting Height": 2400], regions: [.india, .asia])
        b.mm("2.0 TR 1100", 1100, 250, 320, ["Mounting Height": 2400], regions: [.india, .asia])
        b.mm("3.5 kW 850", 850, 220, 290, ["Mounting Height": 2400], regions: [.europe, .uk])
        b.inch("12k BTU \(inch(32))", 32, 9, 11.5, ["Mounting Height": 90], regions: [.usa])
        b.inch("18k BTU \(inch(38))", 38, 9.5, 12, ["Mounting Height": 90], regions: [.usa])
        return b.item
    }

    static func splitOutdoor() -> ComponentLibraryItem {
        var b = FB("Split AC - Outdoor Unit", .mechanicalEquipment, group: "Air Conditioning", keywords: ["condenser", "outdoor unit", "compressor", "odu", "hvac"],
                   "Split air-conditioner outdoor unit with a front fan grille.")
        b.box("Feet", W(-0.45), W(0.45), D(-0.5), D(0.5), K(0), K(0.05), .steelDark, plan: false)
        b.box("Casing", L, R, D(-0.5, 0.01), Bk, K(0.05), T, .plastic)
        b.vDisc("Grille", W(-0.12), Fr, H(0.52), H(0.36), thickness: 0.02, .steelDark, sides: 20)
        b.outline(); b.line(W(-0.12, -0.25), Fr, W(-0.12, 0.25), Fr)
        b.mm("1.5 TR 800", 800, 300, 550, regions: [.india, .asia]); b.mm("2.0 TR 900", 900, 330, 700, regions: [.india, .asia, .europe])
        b.inch("24k BTU \(inch(34))", 34, 13, 28, regions: [.usa])
        return b.item
    }

    static func cassette() -> ComponentLibraryItem {
        var b = FB("AC - Ceiling Cassette", .mechanicalEquipment, group: "Air Conditioning", keywords: ["cassette", "4 way", "ceiling ac", "fan coil", "hvac"],
                   instance: ["Mounting Height"], "Four-way ceiling cassette; Mounting Height is the ceiling. Width is the fascia panel.")
        let z = P("Mounting Height")
        b.box("Unit", W(-0.44), W(0.44), D(-0.44), D(0.44), z, z + H(1), .metal, plan: false)
        b.box("Panel", L, R, Fr, Bk, z - 0.03, z, .plastic)
        b.outline(); b.rect(W(-0.25), D(-0.25), W(0.25), D(0.25))
        for (x0, y0, x1, y1) in [(W(-0.4), D(-0.4), W(0.4), D(-0.33)), (W(-0.4), D(0.33), W(0.4), D(0.4)), (W(-0.4), D(-0.33), W(-0.33), D(0.33)), (W(0.33), D(-0.33), W(0.4), D(0.33))] {
            b.rect(x0, y0, x1, y1)
        }
        b.mm("4-Way 650", 650, 650, 260, ceilingMetric); b.mm("4-Way 950", 950, 950, 250, ceilingMetric)
        b.type("\(ft(2)) x \(ft(2))", .imperial, 0.6096, 0.6096, 0.26, ["Mounting Height": 2.7432])
        return b.item
    }

    static func windowAC() -> ComponentLibraryItem {
        var b = FB("AC - Window Unit", .mechanicalEquipment, group: "Air Conditioning", keywords: ["window ac", "room air conditioner", "through wall"],
                   instance: ["Mounting Height"], "Window or through-wall air conditioner; Mounting Height is its underside. The room side faces front.")
        let z = P("Mounting Height")
        b.box("Body", L, R, Fr, Bk, z, z + H(1), .plastic)
        b.box("Grille", W(-0.5, 0.03), W(0.5, -0.03), D(-0.5, -0.005), Fr, z + 0.03, z + H(1, -0.03), .plasticDark, plan: false)
        b.outline()
        b.mm("1.5 TR 660", 660, 700, 430, ["Mounting Height": 1200], regions: [.india])
        b.inch(inch(24), 24, 26, 17, ["Mounting Height": 48], regions: [.usa])
        return b.item
    }

    static func ceilingFan() -> ComponentLibraryItem {
        var b = FB("Ceiling Fan", .mechanicalEquipment, group: "Fans", keywords: ["fan", "ceiling fan", "sweep", "paddle fan"],
                   instance: ["Mounting Height"], "Three-blade ceiling fan; Width is the sweep, Mounting Height the ceiling, Height the drop.")
        let z = P("Mounting Height"), zb = z - H(1)
        b.cyl("Canopy", K(0), K(0), K(0.06), z - 0.05, z, .metal, plan: false)
        b.cyl("Downrod", K(0), K(0), K(0.01), zb + 0.08, z - 0.05, .metal, plan: false)
        b.cyl("Motor", K(0), K(0), K(0.1), zb, zb + 0.1, .metal)
        for i in 0..<3 {
            let a = Double(i) * 120 * .pi / 180
            let c = cos(a), s = sin(a)
            func p(_ r: LX, _ t: Double) -> (LX, LX) { (r * c - K(t * s), r * s + K(t * c)) }
            let blade = [p(K(0.1), -0.03), p(W(0.5), -0.06), p(W(0.5), 0.06), p(K(0.1), 0.03)]
            b.prism("Blade \(i + 1)", blade, zb + 0.03, zb + 0.04, .woodDark)
            b.poly(blade)
        }
        b.circle(K(0), K(0), W(0.5), .hidden); b.circle(K(0), K(0), K(0.1))
        b.mm("900", 900, 900, 400, ceilingMetric); b.mm("1200", 1200, 1200, 400, ceilingMetric); b.mm("1400", 1400, 1400, 400, ceilingMetric)
        b.inch(inch(42), 42, 42, 14, ceilingImperial); b.inch(inch(52), 52, 52, 14, ceilingImperial); b.inch(inch(60), 60, 60, 14, ceilingImperial)
        return b.item
    }

    static func exhaustWall() -> ComponentLibraryItem {
        var b = FB("Exhaust Fan - Wall", .mechanicalEquipment, group: "Fans", keywords: ["exhaust fan", "extractor fan", "ventilation", "bathroom fan"],
                   instance: ["Mounting Height"], "Wall-mounted exhaust fan; Mounting Height is its center.")
        let z = P("Mounting Height")
        b.box("Frame", L, R, Fr, Bk, z - H(0.5), z + H(0.5), .plastic)
        b.vDisc("Grille", K(0), D(-0.5, -0.005), z, W(0.38), thickness: 0.01, .plasticDark, sides: 16)
        b.outline(); b.line(W(-0.38), Fr, W(0.38), Fr)
        b.mm("150", 180, 60, 180, ["Mounting Height": 2100]); b.mm("200", 240, 60, 240, ["Mounting Height": 2100]); b.mm("250", 300, 70, 300, ["Mounting Height": 2100])
        b.inch(inch(6), 7, 2.5, 7, ["Mounting Height": 84]); b.inch(inch(8), 9.5, 2.5, 9.5, ["Mounting Height": 84])
        return b.item
    }

    static func exhaustCeiling() -> ComponentLibraryItem {
        var b = FB("Exhaust Fan - Ceiling", .mechanicalEquipment, group: "Fans", keywords: ["exhaust fan", "bath fan", "ventilation", "extract"],
                   instance: ["Mounting Height"], "Ceiling exhaust fan with grille; Mounting Height is the ceiling.")
        let z = P("Mounting Height")
        b.box("Housing", W(-0.42), W(0.42), D(-0.42), D(0.42), z, z + H(1), .metal, plan: false)
        b.box("Grille", L, R, Fr, Bk, z - 0.01, z, .plastic)
        b.outline(); for f in [-0.25, 0.0, 0.25] { b.line(W(-0.4), D(f), W(0.4), D(f)) }
        b.mm("200", 250, 250, 150, ceilingMetric); b.inch(inch(8), 10, 10, 6, ceilingImperial)
        return b.item
    }

    static func pedestalFan() -> ComponentLibraryItem {
        var b = FB("Fan - Pedestal", .mechanicalEquipment, group: "Fans", keywords: ["stand fan", "table fan", "floor fan"], "Pedestal fan.")
        b.cyl("Base", K(0), K(0), W(0.45), K(0), K(0.04), .plastic)
        b.cyl("Stand", K(0), K(0), K(0.015), K(0.04), H(1, -0.25), .plastic, plan: false)
        b.vDisc("Guard", K(0), D(-0.1), H(1, -0.22), W(0.5), thickness: 0.12, .plastic, sides: 20)
        b.circle(K(0), K(0), W(0.45)); b.rect(W(-0.5), D(-0.2), W(0.5), D(0.0))
        b.any("Standard", 0.45, 0.45, 1.3)
        return b.item
    }

    static func wallFan() -> ComponentLibraryItem {
        var b = FB("Fan - Wall Mounted", .mechanicalEquipment, group: "Fans", regions: [.india, .asia], keywords: ["wall fan", "bracket fan", "oscillating fan"],
                   instance: ["Mounting Height"], "Oscillating wall fan; Mounting Height is its center.")
        let z = P("Mounting Height")
        b.box("Bracket", W(-0.1), W(0.1), D(0.5, -0.05), Bk, z - 0.1, z + 0.05, .plastic, plan: false)
        b.vDisc("Guard", K(0), D(-0.1), z, W(0.5), thickness: 0.12, .plastic, sides: 20)
        b.rect(W(-0.5), D(-0.2), W(0.5), D(0.0)); b.line(W(-0.1), Bk, W(0.1), Bk)
        b.any("Standard", 0.45, 0.35, 0.45, ["Mounting Height": 2.2])
        return b.item
    }

    static func radiator() -> ComponentLibraryItem {
        var b = FB("Radiator - Panel", .mechanicalEquipment, group: "Heating & Hot Water", regions: [.europe, .uk], keywords: ["radiator", "heater", "central heating", "convector"],
                   instance: ["Mounting Height"], "Double panel radiator; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Panels", L, R, D(-0.5, 0.01), D(0.5, -0.02), z, z + H(1), .lacquer)
        b.box("Brackets", W(-0.4), W(0.4), D(0.5, -0.02), Bk, z + H(0.2), z + H(0.8), .metal, plan: false)
        b.rect(L, D(-0.5, 0.01), R, D(0.5, -0.02))
        for (w, h) in [(600.0, 600.0), (1000, 600), (1400, 600), (800, 450)] { b.mm("\(Int(w)) x \(Int(h))", w, 100, h, ["Mounting Height": 150]) }
        return b.item
    }

    static func towelRail() -> ComponentLibraryItem {
        var b = FB("Towel Rail - Heated", .mechanicalEquipment, group: "Heating & Hot Water", regions: [.europe, .uk], keywords: ["heated towel rail", "towel radiator", "ladder rail"],
                   instance: ["Mounting Height"], "Ladder-style heated towel rail; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Stile Left", L, W(-0.5, 0.03), D(-0.5, 0.02), D(0.5, -0.05), z, z + H(1), .chrome)
        b.box("Stile Right", W(0.5, -0.03), R, D(-0.5, 0.02), D(0.5, -0.05), z, z + H(1), .chrome)
        for i in 0..<8 {
            b.bar("Rung \(i + 1)", [(W(-0.5, 0.03), K(0)), (W(0.5, -0.03), K(0))], z: z + H(0.06 + 0.12 * Double(i)), r: K(0.011), .chrome, sides: 6, plan: false)
        }
        b.rect(L, D(-0.5, 0.02), R, D(0.5, -0.05)); b.line(W(-0.4), Bk, W(0.4), Bk)
        b.mm("500 x 800", 500, 100, 800, ["Mounting Height": 200]); b.mm("500 x 1200", 500, 100, 1200, ["Mounting Height": 200])
        return b.item
    }

    static func waterHeaterTank() -> ComponentLibraryItem {
        var b = FB("Water Heater - Tank", .mechanicalEquipment, group: "Heating & Hot Water", keywords: ["water heater", "hot water cylinder", "boiler", "calorifier"],
                   "Floor-standing storage water heater.")
        b.cyl("Tank", K(0), K(0), W(0.5), K(0.03), H(1, -0.05), .lacquer)
        b.revolve("Top", [(K(0), K(0)), (W(0.5), K(0)), (W(0.45), K(0.05)), (K(0), K(0.05))], K(0), K(0), H(1, -0.05), .lacquer)
        b.cyl("Flue", K(0), K(0), K(0.05), H(1, -0.02), H(1, 0.15), .metal, plan: false)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), K(0.05))
        b.inch("40 Gal \(inch(20))", 20, 20, 60, regions: [.usa]); b.inch("50 Gal \(inch(22))", 22, 22, 62, regions: [.usa])
        b.mm("150 L", 560, 560, 1250, regions: [.europe, .uk, .asia]); b.mm("200 L", 600, 600, 1500, regions: [.europe, .uk, .asia])
        return b.item
    }

    static func waterHeaterTankless() -> ComponentLibraryItem {
        var b = FB("Water Heater - Tankless", .mechanicalEquipment, group: "Heating & Hot Water", keywords: ["instant water heater", "on demand", "combi"],
                   instance: ["Mounting Height"], "Wall-mounted tankless water heater; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Body", L, R, Fr, Bk, z, z + H(1), .plastic)
        b.rect(L, Fr, R, Bk); b.line(L, Fr, R, Bk)
        b.any("Standard", 0.35, 0.22, 0.6, ["Mounting Height": 1.2])
        return b.item
    }

    static func geyser() -> ComponentLibraryItem {
        var b = FB("Geyser - Wall Mounted", .mechanicalEquipment, group: "Heating & Hot Water", regions: [.india], keywords: ["geyser", "water heater", "storage heater"],
                   instance: ["Mounting Height"], "Wall-hung storage geyser, cylinder horizontal; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.bar("Tank", [(L, K(0)), (R, K(0))], z: z + H(0.5), r: H(0.5), .lacquer, sides: 16)
        b.box("Bracket", W(-0.3), W(0.3), D(0.5, -0.02), Bk, z + H(0.2), z + H(0.8), .metal, plan: false)
        b.outline(); b.line(L, K(0), R, K(0), .hidden)
        b.mm("15 L", 480, 330, 330, ["Mounting Height": 1800]); b.mm("25 L", 560, 380, 380, ["Mounting Height": 1800])
        return b.item
    }

    static func distributionBoard() -> ComponentLibraryItem {
        var b = FB("Distribution Board", .electricalFixture, group: "Power & Charging", keywords: ["panel board", "consumer unit", "breaker panel", "db", "load center"],
                   instance: ["Mounting Height"], "Surface-mounted distribution board; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Enclosure", L, R, Fr, Bk, z, z + H(1), .lacquer)
        b.outline(); b.line(L, D(-0.5, 0.01), R, D(-0.5, 0.01)); b.arc(L, Fr, W(1), 270, 90, .hidden)
        b.mm("450 x 600", 450, 120, 600, ["Mounting Height": 1200]); b.inch("\(inch(20)) x \(inch(30))", 20, 4, 30, ["Mounting Height": 48])
        return b.item
    }

    static func evWallCharger() -> ComponentLibraryItem {
        var b = FB("EV Charger - Wall", .electricalFixture, group: "Power & Charging", keywords: ["ev charger", "electric vehicle", "charging point"],
                   instance: ["Mounting Height"], "Wall-mounted electric vehicle charger with a holstered cable; Mounting Height is its underside.")
        let z = P("Mounting Height")
        b.box("Body", L, R, Fr, Bk, z, z + H(1), .plastic)
        b.box("Holster", W(-0.2), W(0.2), D(-0.5, -0.05), Fr, z + H(0.3), z + H(0.5), .plasticDark, plan: false)
        b.rect(L, Fr, R, Bk); b.line(L, Fr, R, Bk)
        b.any("7 kW", 0.2, 0.12, 0.35, ["Mounting Height": 1.0]); b.any("22 kW", 0.25, 0.15, 0.4, ["Mounting Height": 1.0])
        return b.item
    }
}
