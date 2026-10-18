import Foundation

// Planting, entourage (people and vehicles) and site furniture. Geometry is simple massing; plan symbols follow the
// usual drafting conventions (canopy circles with branches, star-edged conifers, frond stars for palms).
extension LibraryContent {

    // MARK: Helpers

    /// Ellipsoid of revolution from `z0` up: horizontal radius rx, vertical radius rz.
    static func blob(_ b: inout FB, _ name: String, _ cx: LX, _ cy: LX, _ z0: LX, rx: LX, rz: LX, _ m: LM, plan: Bool = true, steps: Int = 8) {
        var prof: [(LX, LX)] = [(K(0), K(0))]
        for i in 1..<steps {
            let a = Double(i) / Double(steps) * .pi
            prof.append((rx * sin(a), rz - rz * cos(a)))
        }
        prof.append((K(0), rz * 2))
        b.revolve(name, prof, cx, cy, z0, m, plan: plan)
    }

    /// Plan tree: canopy outline (optionally scalloped), trunk and branch strokes.
    static func treeSymbol(_ b: inout FB, _ cx: LX, _ cy: LX, r: LX, trunk: LX, branches: Int = 7, scalloped: Bool = true) {
        if scalloped {
            b.poly((0..<28).map { i -> (LX, LX) in
                let a = Double(i) / 28 * 2 * .pi
                let k = i % 2 == 0 ? 1.0 : 0.93
                return (cx + r * (k * cos(a)), cy + r * (k * sin(a)))
            })
        } else {
            b.circle(cx, cy, r)
        }
        b.circle(cx, cy, trunk)
        for i in 0..<branches {
            let a = (Double(i) / Double(branches) * 360 + 15) * .pi / 180
            b.line(cx + trunk * cos(a), cy + trunk * sin(a), cx + r * (0.72 * cos(a)), cy + r * (0.72 * sin(a)))
        }
    }

    // MARK: Planting

    static func planting() -> [ComponentLibraryItem] {
        [treeRound(), treeOval(), treeConifer(), treePalm(), treeCoconut(), treeWeeping(), treeFlowering(), bamboo(), shrub(), hedge(), grass(), pottedPlant()]
    }

    static func treeRound() -> ComponentLibraryItem {
        var b = FB("Tree - Deciduous Round", .planting, group: "Trees", keywords: ["tree", "shade tree", "oak", "maple", "neem", "canopy"],
                   "Broadleaf tree with a round canopy; Width is the canopy spread.")
        b.cyl("Trunk", K(0), K(0), W(0.03), K(0), H(0.45), .bark)
        blob(&b, "Canopy", K(0), K(0), H(0.3), rx: W(0.5), rz: H(0.35), .foliage)
        treeSymbol(&b, K(0), K(0), r: W(0.5), trunk: W(0.03))
        b.mm("5 m", 4000, 4000, 5000); b.mm("8 m", 6000, 6000, 8000); b.mm("12 m", 8000, 8000, 12000)
        b.type(ft(15), .imperial, 3.66, 3.66, 4.572); b.type(ft(25), .imperial, 6.1, 6.1, 7.62); b.type(ft(40), .imperial, 8.53, 8.53, 12.19)
        return b.item
    }

    static func treeOval() -> ComponentLibraryItem {
        var b = FB("Tree - Deciduous Upright", .planting, group: "Trees", keywords: ["tree", "street tree", "columnar", "ash", "linden"],
                   "Street tree with an upright oval canopy.")
        b.cyl("Trunk", K(0), K(0), W(0.05), K(0), H(0.4), .bark)
        blob(&b, "Canopy", K(0), K(0), H(0.25), rx: W(0.5), rz: H(0.375), .foliage)
        treeSymbol(&b, K(0), K(0), r: W(0.5), trunk: W(0.05), branches: 5)
        b.mm("6 m", 3000, 3000, 6000); b.mm("10 m", 5000, 5000, 10000)
        b.type(ft(20), .imperial, 3.05, 3.05, 6.1); b.type(ft(30), .imperial, 4.57, 4.57, 9.14)
        return b.item
    }

    static func treeConifer() -> ComponentLibraryItem {
        var b = FB("Tree - Conifer", .planting, group: "Trees", keywords: ["tree", "pine", "spruce", "fir", "evergreen", "deodar"],
                   "Conical evergreen conifer.")
        b.cyl("Trunk", K(0), K(0), W(0.04), K(0), H(0.25), .bark)
        b.revolve("Lower Tier", [(K(0), K(0)), (W(0.5), K(0)), (K(0), H(0.6))], K(0), K(0), H(0.12), .foliageDark)
        b.revolve("Upper Tier", [(K(0), K(0)), (W(0.36), K(0)), (K(0), H(0.5))], K(0), K(0), H(0.5), .foliageDark)
        b.poly((0..<24).map { i -> (LX, LX) in
            let a = Double(i) / 24 * 2 * .pi
            let k = i % 2 == 0 ? 0.5 : 0.36
            return (W(k * cos(a)), W(k * sin(a)))
        })
        b.circle(K(0), K(0), W(0.04))
        for i in 0..<6 { let a = Double(i) * 60 * .pi / 180; b.line(K(0), K(0), W(0.36 * cos(a)), W(0.36 * sin(a))) }
        b.mm("4 m", 2000, 2000, 4000); b.mm("8 m", 3500, 3500, 8000); b.mm("15 m", 6000, 6000, 15000)
        b.type(ft(12), .imperial, 1.83, 1.83, 3.66); b.type(ft(25), .imperial, 3.35, 3.35, 7.62); b.type(ft(50), .imperial, 6.1, 6.1, 15.24)
        return b.item
    }

    /// Palm crown of `n` flat fronds radiating from (cx, cy) at height z.
    static func fronds(_ b: inout FB, _ cx: LX, _ cy: LX, _ z: LX, n: Int = 9) {
        for i in 0..<n {
            let a = Double(i) / Double(n) * 2 * .pi
            let c = cos(a), s = sin(a)
            func p(_ r: Double, _ t: Double) -> (LX, LX) { (cx + W(r * c) - W(t * s), cy + W(r * s) + W(t * c)) }
            let leaf = [p(0.02, 0), p(0.2, -0.06), p(0.5, 0), p(0.2, 0.06)]
            b.prism("Frond \(i + 1)", leaf, z - 0.04 - Double(i % 3) * 0.1, z - Double(i % 3) * 0.1, .foliage)
            b.poly(leaf)
            b.line(leaf[0].0, leaf[0].1, leaf[2].0, leaf[2].1)
        }
    }

    static func treePalm() -> ComponentLibraryItem {
        var b = FB("Tree - Palm", .planting, group: "Palms", keywords: ["palm", "date palm", "royal palm", "tropical"],
                   "Palm with a straight trunk and a crown of fronds; Width is the crown spread.")
        b.taper("Trunk", K(0), K(0), bottom: (K(0.2), K(0.2)), top: (K(0.13), K(0.13)), K(0), H(0.92), .bark)
        b.blend("Crown Shaft", ngon(K(0), K(0), K(0.14), 8), ngon(K(0), K(0), K(0.1), 8), H(0.9), T, .foliageDark)
        fronds(&b, K(0), K(0), T)
        b.circle(K(0), K(0), K(0.2))
        b.mm("5 m", 4000, 4000, 5000); b.mm("9 m", 5000, 5000, 9000)
        b.type(ft(16), .imperial, 3.66, 3.66, 4.88); b.type(ft(30), .imperial, 4.88, 4.88, 9.14)
        return b.item
    }

    static func treeCoconut() -> ComponentLibraryItem {
        var b = FB("Tree - Coconut Palm", .planting, group: "Palms", regions: [.india, .asia], keywords: ["coconut", "palm", "tropical", "coastal"],
                   "Coconut palm with a leaning trunk; the crown leans toward the back.")
        let segs = 5
        for i in 0..<segs {
            let f0 = Double(i) / Double(segs), f1 = Double(i + 1) / Double(segs)
            let off = f0 * f0 * 0.18
            b.cyl("Trunk \(i + 1)", K(0), W(off), K(0.14 - 0.01 * Double(i)), H(f0 * 0.95), H(f1 * 0.95), .bark, plan: i == 0)
        }
        fronds(&b, K(0), W(0.8 * 0.8 * 0.18), T)
        b.circle(K(0), K(0), K(0.14))
        b.mm("8 m", 6000, 6000, 8000); b.mm("12 m", 7000, 7000, 12000)
        return b.item
    }

    static func treeWeeping() -> ComponentLibraryItem {
        var b = FB("Tree - Weeping", .planting, group: "Trees", keywords: ["willow", "weeping tree", "cascade"], "Weeping tree with a bell-shaped canopy.")
        b.cyl("Trunk", K(0), K(0), W(0.03), K(0), H(0.55), .bark)
        b.revolve("Canopy", [(K(0), H(0.25)), (W(0.46), K(0)), (W(0.5), H(0.35)), (W(0.34), H(0.62)), (K(0), H(0.75))], K(0), K(0), H(0.25), .foliage)
        treeSymbol(&b, K(0), K(0), r: W(0.5), trunk: W(0.03), branches: 10)
        b.mm("8 m", 7000, 7000, 8000); b.type(ft(25), .imperial, 6.1, 6.1, 7.62)
        return b.item
    }

    static func treeFlowering() -> ComponentLibraryItem {
        var b = FB("Tree - Flowering Small", .planting, group: "Trees", keywords: ["ornamental tree", "cherry", "magnolia", "gulmohar", "small tree"],
                   "Small multi-stem ornamental tree.")
        for (i, (dx, dy)) in [(-0.05, -0.03), (0.05, -0.03), (0.0, 0.05)].enumerated() {
            b.cyl("Stem \(i + 1)", W(dx), W(dy), W(0.02), K(0), H(0.45), .bark, plan: false)
        }
        blob(&b, "Canopy", K(0), K(0), H(0.3), rx: W(0.5), rz: H(0.35), .foliage)
        treeSymbol(&b, K(0), K(0), r: W(0.5), trunk: W(0.06), branches: 6)
        b.mm("3 m", 2500, 2500, 3000); b.mm("4 m", 3500, 3500, 4000)
        b.type(ft(10), .imperial, 2.44, 2.44, 3.05); b.type(ft(14), .imperial, 3.35, 3.35, 4.27)
        return b.item
    }

    static func bamboo() -> ComponentLibraryItem {
        var b = FB("Bamboo - Clump", .planting, group: "Shrubs & Grasses", regions: [.asia, .india], keywords: ["bamboo", "screen planting", "grove"],
                   "Clump of bamboo culms with foliage at the top.")
        let spots: [(Double, Double, Double)] = [(-0.2, -0.1, 0.95), (0.15, -0.2, 1.0), (0.05, 0.15, 0.9), (-0.1, 0.25, 0.85), (0.25, 0.1, 0.92), (-0.25, 0.1, 0.8), (0, -0.02, 0.97)]
        for (i, (x, y, h)) in spots.enumerated() {
            b.cyl("Culm \(i + 1)", W(x), W(y), K(0.03), K(0), H(h), .woodLight, plan: false)
            b.circle(W(x), W(y), K(0.03))
        }
        blob(&b, "Foliage", K(0), K(0), H(0.55), rx: W(0.5), rz: H(0.22), .foliage, plan: false)
        b.circle(K(0), K(0), W(0.5), .hidden)
        b.mm("4 m", 1500, 1500, 4000); b.mm("6 m", 2000, 2000, 6000)
        return b.item
    }

    static func shrub() -> ComponentLibraryItem {
        var b = FB("Shrub - Round", .planting, group: "Shrubs & Grasses", keywords: ["shrub", "bush", "boxwood", "hibiscus"], "Rounded shrub.")
        blob(&b, "Shrub", K(0), K(0), K(0), rx: W(0.5), rz: H(0.5), .foliageDark)
        b.poly((0..<20).map { i -> (LX, LX) in
            let a = Double(i) / 20 * 2 * .pi
            let k = i % 2 == 0 ? 0.5 : 0.44
            return (W(k * cos(a)), W(k * sin(a)))
        })
        b.circle(K(0), K(0), W(0.2))
        b.mm("600", 700, 700, 600); b.mm("1000", 1100, 1100, 1000); b.mm("1500", 1600, 1600, 1500)
        b.type(ft(2), .imperial, 0.7, 0.7, 0.61); b.type(ft(3), .imperial, 1.0, 1.0, 0.91); b.type(ft(5), .imperial, 1.6, 1.6, 1.52)
        return b.item
    }

    static func hedge() -> ComponentLibraryItem {
        var b = FB("Hedge - Clipped", .planting, group: "Shrubs & Grasses", keywords: ["hedge", "hedgerow", "screen", "boundary planting"],
                   "Clipped hedge section; set Width to the run.")
        b.box("Hedge", L, R, Fr, Bk, K(0), H(0.9), .foliageDark)
        b.taper("Top", K(0), K(0), bottom: (W(0.5), D(0.5)), top: (W(0.5, -0.05), D(0.5, -0.08)), H(0.9), T, .foliageDark)
        b.outline(); b.line(L, K(0), R, K(0), .hidden)
        b.mm("2000 x 600 x 1200", 2000, 600, 1200); b.mm("3000 x 800 x 1800", 3000, 800, 1800)
        b.type("\(ft(6)) x \(ft(2)) x \(ft(4))", .imperial, 1.83, 0.61, 1.22); b.type("\(ft(10)) x \(ft(3)) x \(ft(6))", .imperial, 3.05, 0.91, 1.83)
        return b.item
    }

    static func grass() -> ComponentLibraryItem {
        var b = FB("Grass - Ornamental Clump", .planting, group: "Shrubs & Grasses", keywords: ["grass", "tussock", "fountain grass", "sedge"], "Clump of ornamental grass.")
        b.revolve("Clump", [(K(0), K(0)), (W(0.15), K(0)), (W(0.5), T), (W(0.2), H(0.85)), (K(0), H(0.9))], K(0), K(0), K(0), .foliage)
        for i in 0..<12 { let a = Double(i) * 30 * .pi / 180; b.line(W(0.05 * cos(a)), W(0.05 * sin(a)), W(0.5 * cos(a)), W(0.5 * sin(a))) }
        b.mm("600", 600, 600, 700); b.inch(inch(24), 24, 24, 28)
        return b.item
    }

    static func pottedPlant() -> ComponentLibraryItem {
        var b = FB("Potted Plant - Indoor", .planting, group: "Indoor Plants", keywords: ["plant", "pot", "indoor plant", "fiddle leaf", "areca", "houseplant"],
                   "Indoor plant in a round pot.")
        b.revolve("Pot", [(K(0), K(0)), (W(0.3), K(0)), (W(0.36), H(0.28)), (K(0), H(0.28))], K(0), K(0), K(0), .terracotta)
        b.cyl("Stem", K(0), K(0), K(0.015), H(0.28), H(0.5), .bark, plan: false)
        blob(&b, "Foliage", K(0), K(0), H(0.4), rx: W(0.5), rz: H(0.3), .foliage)
        treeSymbol(&b, K(0), K(0), r: W(0.5), trunk: W(0.36), branches: 6)
        b.any("Small", 0.35, 0.35, 0.8); b.any("Medium", 0.5, 0.5, 1.2); b.any("Large", 0.75, 0.75, 1.8)
        return b.item
    }

    // MARK: Entourage

    static func entourage() -> [ComponentLibraryItem] {
        [personStanding(), personWalking(), personSeated(),
         car("Car - Sedan", cabin: (-0.22, 0.28), types: [("Compact", 1.75, 4.5, 1.45), ("Mid-Size", 1.83, 4.85, 1.45), ("Full-Size", 1.9, 5.1, 1.48)]),
         car("Car - Hatchback", cabin: (-0.18, 0.44), types: [("Small", 1.65, 3.8, 1.5), ("Standard", 1.75, 4.1, 1.48)], regions: [.global]),
         car("Car - SUV", cabin: (-0.2, 0.46), roof: 0.08, types: [("Compact", 1.82, 4.4, 1.65), ("Full-Size", 2.0, 5.2, 1.9)]),
         car("Van - Minivan", cabin: (-0.3, 0.47), roof: 0.06, types: [("Standard", 1.95, 5.1, 1.8)]),
         pickup(), autoRickshaw(), motorcycle(), scooter(), bicycle(), bus(), boxTruck(), semiTruck()]
    }

    /// Standing or walking figure; `stride` spreads the legs front to back.
    static func figure(_ b: inout FB, stride: Double) {
        b.box("Leg Left", W(-0.3), W(-0.04), D(-0.25 - stride), D(0.25 - stride), K(0), H(0.47), .clothingDark)
        b.box("Leg Right", W(0.04), W(0.3), D(-0.25 + stride), D(0.25 + stride), K(0), H(0.47), .clothingDark)
        b.taper("Torso", K(0), K(0), bottom: (W(0.32), D(0.4)), top: (W(0.46), D(0.45)), H(0.47), H(0.82), .clothing)
        b.box("Arm Left", W(-0.5), W(-0.38), D(-0.2 + stride), D(0.2 + stride), H(0.46), H(0.8), .clothing)
        b.box("Arm Right", W(0.38), W(0.5), D(-0.2 - stride), D(0.2 - stride), H(0.46), H(0.8), .clothing)
        b.cyl("Neck", K(0), K(0), W(0.08), H(0.82), H(0.87), .skin, plan: false)
        b.ball("Head", K(0), K(0), H(0.935), H(0.065), .skin)
        b.poly(ellipse(K(0), K(0), W(0.5), D(0.5), 20))
        b.circle(K(0), K(0), H(0.065))
    }

    static func personStanding() -> ComponentLibraryItem {
        var b = FB("Person - Standing", .entourage, group: "People", keywords: ["person", "people", "human", "figure", "scale figure", "man", "woman", "child"],
                   "Simple standing figure for scale.")
        figure(&b, stride: 0)
        b.any("Adult Male", 0.48, 0.28, 1.78); b.any("Adult Female", 0.42, 0.26, 1.65); b.any("Child", 0.32, 0.2, 1.2)
        return b.item
    }

    static func personWalking() -> ComponentLibraryItem {
        var b = FB("Person - Walking", .entourage, group: "People", keywords: ["person", "people", "pedestrian", "figure", "walking"],
                   "Simple walking figure for scale; facing front.")
        figure(&b, stride: 0.35)
        b.line(W(-0.17), D(-0.85), W(-0.17), D(-0.6)); b.line(W(0.17), D(0.6), W(0.17), D(0.85))
        b.any("Adult Male", 0.48, 0.3, 1.78); b.any("Adult Female", 0.42, 0.28, 1.65)
        return b.item
    }

    static func personSeated() -> ComponentLibraryItem {
        var b = FB("Person - Seated", .entourage, group: "People", keywords: ["person", "people", "seated", "sitting", "figure"],
                   "Seated figure (chair not included); Height is to the top of the head.")
        b.box("Shins", W(-0.3), W(0.3), D(-0.5), D(-0.3), K(0), H(0.34), .clothingDark)
        b.box("Thighs", W(-0.3), W(0.3), D(-0.5), D(0.15), H(0.3), H(0.4), .clothingDark)
        b.taper("Torso", K(0), D(0.25), bottom: (W(0.32), D(0.2)), top: (W(0.46), D(0.22)), H(0.35), H(0.76), .clothing)
        b.box("Arm Left", W(-0.5), W(-0.38), D(0.0), D(0.35), H(0.4), H(0.74), .clothing)
        b.box("Arm Right", W(0.38), W(0.5), D(0.0), D(0.35), H(0.4), H(0.74), .clothing)
        b.ball("Head", K(0), D(0.25), H(0.88), H(0.085), .skin)
        b.rect(W(-0.3), D(-0.5), W(0.3), D(0.05)); b.poly(ellipse(K(0), D(0.25), W(0.5), D(0.22), 20)); b.circle(K(0), D(0.25), H(0.085))
        b.any("Adult", 0.46, 0.75, 1.3); b.any("Adult Small", 0.42, 0.7, 1.22)
        return b.item
    }

    /// A road wheel on a transverse axle at plan (x0…x1, y) with its bottom on the ground.
    static func wheel(_ b: inout FB, _ name: String, x0: LX, x1: LX, y: LX, dia: LX, plan: Bool = false) {
        let prof = (0..<14).map { i -> (LX, LX) in
            let a = Double(i) / 14 * 2 * .pi
            return (dia * (0.5 * cos(a)), dia * (0.5 + 0.5 * sin(a)))
        }
        b.sweep(name, [(x0, y), (x1, y)], prof, K(0), .rubber, plan: plan)
    }

    /// A car: lower body, glazed cabin between `cabin` fractions of the length (front negative), roof and four wheels.
    static func car(_ name: String, cabin: (Double, Double), roof: Double = 0.1, types: [(String, Double, Double, Double)],
                    regions: [LibraryRegion] = [.global]) -> ComponentLibraryItem {
        var b = FB(name, .entourage, group: "Vehicles", regions: regions, keywords: ["car", "vehicle", "automobile", "parking", "auto"],
                   extra: ["Wheel Diameter"], "Vehicle massing for site plans and parking layouts; the front faces -Y.")
        let wd = P("Wheel Diameter")
        b.box("Body", L, R, D(-0.5), D(0.5), wd * 0.35, H(0.5), .paint)
        b.blend("Cabin", [(W(-0.5, 0.04), D(cabin.0 - 0.08)), (W(0.5, -0.04), D(cabin.0 - 0.08)), (W(0.5, -0.04), D(cabin.1 + 0.04)), (W(-0.5, 0.04), D(cabin.1 + 0.04))],
                [(W(-0.5, 0.12), D(cabin.0 + 0.05)), (W(0.5, -0.12), D(cabin.0 + 0.05)), (W(0.5, -0.12), D(cabin.1 - 0.03)), (W(-0.5, 0.12), D(cabin.1 - 0.03))],
                H(0.5), H(1, -0.02), .glass)
        b.box("Roof", W(-0.5, 0.13), W(0.5, -0.13), D(cabin.0 + 0.06 + roof * 0.2), D(cabin.1 - 0.04), H(1, -0.03), T, .paint, plan: false)
        for (n, y) in [("Front", D(-0.32)), ("Rear", D(0.32))] {
            wheel(&b, "\(n) Wheel Left", x0: W(-0.5, 0.01), x1: W(-0.5, 0.23), y: y, dia: wd)
            wheel(&b, "\(n) Wheel Right", x0: W(0.5, -0.23), x1: W(0.5, -0.01), y: y, dia: wd)
            b.rect(W(-0.5, 0.01), y - wd * 0.5, W(-0.5, 0.23), y + wd * 0.5, .hidden)
            b.rect(W(0.5, -0.23), y - wd * 0.5, W(0.5, -0.01), y + wd * 0.5, .hidden)
        }
        b.rrect(L, Fr, R, Bk, W(0.12))
        b.rect(W(-0.5, 0.12), D(cabin.0 + 0.05), W(0.5, -0.12), D(cabin.1 - 0.03))
        b.line(W(-0.5, 0.04), D(cabin.0 - 0.08), W(-0.5, 0.12), D(cabin.0 + 0.05)); b.line(W(0.5, -0.04), D(cabin.0 - 0.08), W(0.5, -0.12), D(cabin.0 + 0.05))
        b.line(W(-0.5, 0.04), D(cabin.0 - 0.08), W(0.5, -0.04), D(cabin.0 - 0.08))
        for t in types { b.any(t.0, t.1, t.2, t.3, ["Wheel Diameter": t.3 > 1.7 ? 0.75 : 0.64]) }
        return b.item
    }

    static func pickup() -> ComponentLibraryItem {
        var b = FB("Pickup Truck", .entourage, group: "Vehicles", regions: [.usa, .global], keywords: ["pickup", "truck", "ute", "vehicle"],
                   extra: ["Wheel Diameter"], "Pickup truck massing with an open bed; the front faces -Y.")
        let wd = P("Wheel Diameter")
        b.box("Body", L, R, Fr, D(-0.05), wd * 0.4, H(0.55), .paint)
        b.box("Cab", W(-0.5, 0.05), W(0.5, -0.05), D(-0.3), D(-0.02), H(0.55), T, .glass)
        b.box("Bed Floor", L, R, D(0.02), Bk, wd * 0.4, wd * 0.8, .paint)
        b.box("Bed Side Left", L, W(-0.5, 0.05), D(0.02), Bk, wd * 0.8, H(0.55), .paint)
        b.box("Bed Side Right", W(0.5, -0.05), R, D(0.02), Bk, wd * 0.8, H(0.55), .paint)
        b.box("Tailgate", L, R, D(0.5, -0.05), Bk, wd * 0.8, H(0.55), .paint)
        for (n, y) in [("Front", D(-0.33)), ("Rear", D(0.3))] {
            wheel(&b, "\(n) Wheel Left", x0: W(-0.5, 0.01), x1: W(-0.5, 0.25), y: y, dia: wd)
            wheel(&b, "\(n) Wheel Right", x0: W(0.5, -0.25), x1: W(0.5, -0.01), y: y, dia: wd)
        }
        b.rrect(L, Fr, R, Bk, K(0.15)); b.rect(W(-0.5, 0.05), D(-0.3), W(0.5, -0.05), D(-0.02)); b.rect(W(-0.5, 0.05), D(0.02), W(0.5, -0.05), D(0.5, -0.05))
        b.any("Mid-Size", 1.9, 5.4, 1.8, ["Wheel Diameter": 0.78]); b.any("Full-Size", 2.05, 5.9, 1.95, ["Wheel Diameter": 0.82])
        return b.item
    }

    static func autoRickshaw() -> ComponentLibraryItem {
        var b = FB("Auto-Rickshaw", .entourage, group: "Vehicles", regions: [.india, .asia], keywords: ["auto", "rickshaw", "tuk tuk", "three wheeler", "taxi"],
                   "Three-wheeled auto-rickshaw with a canopy; the front faces -Y.")
        b.box("Floor", W(-0.5, 0.05), W(0.5, -0.05), D(-0.4), Bk, K(0.2), K(0.35), .paintAccent)
        b.taper("Nose", K(0), D(-0.42), bottom: (W(0.12), D(0.08)), top: (W(0.25), D(0.06)), K(0.2), H(0.55), .signGreen)
        b.box("Seat", W(-0.5, 0.08), W(0.5, -0.08), D(0.15), D(0.45), K(0.35), H(0.3), .leather)
        b.taper("Canopy", K(0), D(0.08), bottom: (W(0.5), D(0.42)), top: (W(0.48), D(0.38)), H(0.92), T, .signGreen)
        b.box("Windshield", W(-0.42), W(0.42), D(-0.36), D(-0.33), H(0.5), H(0.92), .glass, plan: false)
        for (i, (x, y)) in [(W(-0.42), D(-0.32)), (W(0.42), D(-0.32)), (W(-0.42), D(0.35)), (W(0.42), D(0.35))].enumerated() {
            b.cyl("Pillar \(i + 1)", x, y, K(0.015), K(0.35), H(0.92), .steelDark, plan: false)
        }
        wheel(&b, "Front Wheel", x0: K(-0.05), x1: K(0.05), y: D(-0.42), dia: K(0.42))
        wheel(&b, "Rear Wheel Left", x0: W(-0.5), x1: W(-0.5, 0.1), y: D(0.3), dia: K(0.42))
        wheel(&b, "Rear Wheel Right", x0: W(0.5, -0.1), x1: W(0.5), y: D(0.3), dia: K(0.42))
        b.poly([(W(-0.12), Fr), (W(0.12), Fr), (W(0.5, -0.02), D(-0.3)), (R, Bk), (L, Bk), (W(-0.5, 0.02), D(-0.3))])
        b.rect(W(-0.48), D(-0.3), W(0.48), D(0.46), .hidden)
        b.any("Standard", 1.4, 2.65, 1.7)
        return b.item
    }

    /// Two-wheeler: wheels at the ends of the length, a frame, seat and handlebar.
    static func twoWheeler(_ b: inout FB, wheel dia: LX, seat: LX, frame: LM) {
        wheel(&b, "Front Wheel", x0: K(-0.04), x1: K(0.04), y: D(-0.5) + dia * 0.5, dia: dia, plan: false)
        wheel(&b, "Rear Wheel", x0: K(-0.05), x1: K(0.05), y: D(0.5) - dia * 0.5, dia: dia, plan: false)
        b.bar("Frame", [(K(0), D(-0.5) + dia * 0.5), (K(0), D(0.5) - dia * 0.5)], z: dia * 0.9, r: K(0.035), frame, sides: 6, plan: false)
        b.box("Seat", W(-0.18), W(0.18), D(0.02), D(0.3), seat - 0.06, seat, .leather)
        b.cyl("Fork", K(0), D(-0.5) + dia * 0.55, K(0.02), dia * 0.5, H(0.88), .chrome, plan: false)
        b.bar("Handlebar", [(W(-0.5), D(-0.5) + dia * 0.6), (W(0.5), D(-0.5) + dia * 0.6)], z: H(0.9), r: K(0.012), .chrome, sides: 6)
        b.rect(K(-0.05), Fr, K(0.05), Bk); b.line(L, D(-0.5) + dia * 0.6, R, D(-0.5) + dia * 0.6); b.rect(W(-0.18), D(0.02), W(0.18), D(0.3))
    }

    static func motorcycle() -> ComponentLibraryItem {
        var b = FB("Motorcycle", .entourage, group: "Vehicles", keywords: ["motorbike", "bike", "two wheeler", "motorcycle"], "Motorcycle massing; the front faces -Y.")
        twoWheeler(&b, wheel: K(0.62), seat: K(0.8), frame: .paint)
        b.box("Tank and Engine", W(-0.25), W(0.25), D(-0.2), D(0.05), K(0.3), K(0.85), .paint)
        b.any("Standard", 0.8, 2.1, 1.15); b.any("Cruiser", 0.95, 2.4, 1.1)
        return b.item
    }

    static func scooter() -> ComponentLibraryItem {
        var b = FB("Scooter", .entourage, group: "Vehicles", regions: [.india, .asia, .europe], keywords: ["scooter", "moped", "two wheeler"],
                   "Step-through scooter massing; the front faces -Y.")
        twoWheeler(&b, wheel: K(0.45), seat: K(0.78), frame: .paint)
        b.box("Floorboard", W(-0.2), W(0.2), D(-0.25), D(0.05), K(0.2), K(0.28), .paint)
        b.box("Leg Shield", W(-0.25), W(0.25), D(-0.33), D(-0.25), K(0.2), K(0.95), .paint)
        b.box("Body", W(-0.22), W(0.22), D(0.02), D(0.4), K(0.3), K(0.72), .paint)
        b.any("Standard", 0.7, 1.85, 1.15)
        return b.item
    }

    static func bicycle() -> ComponentLibraryItem {
        var b = FB("Bicycle", .entourage, group: "Bicycles", keywords: ["bike", "cycle", "bicycle", "pushbike"], "Bicycle; the front faces -Y.")
        twoWheeler(&b, wheel: H(0.66), seat: H(0.92), frame: .steelDark)
        b.bar("Down Tube", [(K(0), D(-0.25)), (K(0), D(0.1))], z: H(0.35), r: K(0.015), .steelDark, sides: 6, plan: false)
        b.any("Adult", 0.6, 1.75, 1.05); b.any("Child", 0.5, 1.3, 0.8)
        return b.item
    }

    static func bus() -> ComponentLibraryItem {
        var b = FB("Bus", .entourage, group: "Vehicles", keywords: ["bus", "coach", "school bus", "transit", "public transport"],
                   extra: ["Wheel Diameter"], "Bus massing with a window band; the front faces -Y.")
        let wd = P("Wheel Diameter")
        b.box("Body", L, R, Fr, Bk, wd * 0.45, H(0.55), .paint)
        b.box("Windows", L, R, Fr, Bk, H(0.55), H(0.88), .glass)
        b.box("Roof", L, R, Fr, Bk, H(0.88), T, .paint, plan: false)
        for (n, y) in [("Front", D(-0.5, 2.6)), ("Rear", D(0.5, -3.2))] {
            wheel(&b, "\(n) Wheel Left", x0: W(-0.5, 0.02), x1: W(-0.5, 0.32), y: y, dia: wd)
            wheel(&b, "\(n) Wheel Right", x0: W(0.5, -0.32), x1: W(0.5, -0.02), y: y, dia: wd)
        }
        b.rrect(L, Fr, R, Bk, K(0.2)); b.line(L, D(-0.5, 1.2), R, D(-0.5, 1.2))
        b.any("City", 2.55, 12.0, 3.2, ["Wheel Diameter": 1.0]); b.any("Coach", 2.55, 13.0, 3.6, ["Wheel Diameter": 1.05])
        b.any("School", 2.4, 11.0, 3.2, ["Wheel Diameter": 1.0], regions: [.usa])
        return b.item
    }

    static func boxTruck() -> ComponentLibraryItem {
        var b = FB("Truck - Box", .entourage, group: "Vehicles", keywords: ["lorry", "delivery truck", "box truck", "van", "service vehicle"],
                   extra: ["Wheel Diameter"], "Rigid box truck; the front faces -Y.")
        let wd = P("Wheel Diameter")
        b.box("Cab", W(-0.5, 0.05), W(0.5, -0.05), Fr, D(-0.5, 1.9), wd * 0.45, H(0.75), .signFace)
        b.box("Cab Glass", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.1), D(-0.5, 1.2), H(0.5), H(0.72), .glass, plan: false)
        b.box("Chassis", W(-0.4), W(0.4), D(-0.5, 1.9), Bk, wd * 0.45, wd, .steelDark, plan: false)
        b.box("Box", L, R, D(-0.5, 2.0), Bk, wd, T, .signFace)
        for (n, y) in [("Front", D(-0.5, 1.1)), ("Rear", D(0.5, -1.5))] {
            wheel(&b, "\(n) Wheel Left", x0: W(-0.5, 0.03), x1: W(-0.5, 0.3), y: y, dia: wd)
            wheel(&b, "\(n) Wheel Right", x0: W(0.5, -0.3), x1: W(0.5, -0.03), y: y, dia: wd)
        }
        b.rect(W(-0.5, 0.05), Fr, W(0.5, -0.05), D(-0.5, 1.9)); b.rect(L, D(-0.5, 2.0), R, Bk)
        b.any("Light", 2.2, 7.0, 3.2, ["Wheel Diameter": 0.8]); b.any("Medium", 2.5, 9.0, 3.6, ["Wheel Diameter": 0.95])
        return b.item
    }

    static func semiTruck() -> ComponentLibraryItem {
        var b = FB("Truck - Articulated", .entourage, group: "Vehicles", keywords: ["semi", "tractor trailer", "18 wheeler", "lorry", "hgv"],
                   extra: ["Wheel Diameter"], "Tractor unit with a box trailer; the front faces -Y.")
        let wd = P("Wheel Diameter")
        b.box("Tractor", W(-0.5, 0.05), W(0.5, -0.05), Fr, D(-0.5, 2.3), wd * 0.45, H(0.8), .paint)
        b.box("Tractor Glass", W(-0.5, 0.06), W(0.5, -0.06), D(-0.5, 0.1), D(-0.5, 1.2), H(0.55), H(0.75), .glass, plan: false)
        b.box("Trailer", L, R, D(-0.5, 3.2), Bk, wd * 1.3, T, .signFace)
        for (n, y) in [("Steer", D(-0.5, 1.2)), ("Drive", D(-0.5, 4.2)), ("Trailer 1", D(0.5, -2.2)), ("Trailer 2", D(0.5, -1.0))] {
            wheel(&b, "\(n) Left", x0: W(-0.5, 0.03), x1: W(-0.5, 0.33), y: y, dia: wd)
            wheel(&b, "\(n) Right", x0: W(0.5, -0.33), x1: W(0.5, -0.03), y: y, dia: wd)
        }
        b.rect(W(-0.5, 0.05), Fr, W(0.5, -0.05), D(-0.5, 2.3)); b.rect(L, D(-0.5, 3.2), R, Bk)
        b.any("Articulated", 2.55, 16.5, 4.0, ["Wheel Diameter": 1.0])
        return b.item
    }

    // MARK: Site furniture

    static func siteFurniture() -> [ComponentLibraryItem] {
        [parkBench(backed: true), parkBench(backed: false), picnicTable(), litterBin(), bollard(removable: false), bollard(removable: true), fireHydrant(),
         bikeRackU(), bikeRack5(), monumentSign(), pylonSign(), flagpole(), mailbox(), outdoorFountain(), busShelter(), patioUmbrella(), manhole(),
         planterRound(), planterRect(), treeGrate()]
    }

    static func parkBench(backed: Bool) -> ComponentLibraryItem {
        var b = FB(backed ? "Bench - Park" : "Bench - Backless", .site, group: "Site Furniture", keywords: ["bench", "seat", "park bench", "street furniture"],
                   backed ? "Slatted park bench with a back and cast end frames." : "Backless slatted bench.")
        let back = backed ? 0.12 : 0.0
        for i in 0..<4 {
            let y0 = D(-0.5, 0.02 + Double(i) * 0.1)
            b.box("Seat Slat \(i + 1)", L, R, y0, y0 + 0.08, H(backed ? 0.5 : 0.95, -0.04), H(backed ? 0.5 : 0.95), .wood)
        }
        if backed {
            for i in 0..<3 {
                b.box("Back Slat \(i + 1)", L, R, D(0.5, -back), D(0.5, -back + 0.04), H(0.6 + 0.13 * Double(i)), H(0.6 + 0.13 * Double(i), 0.08), .wood, plan: false)
            }
        }
        for (i, x) in [W(-0.5, 0.12), W(0.5, -0.12)].enumerated() {
            b.box("Frame \(i + 1)", x - 0.03, x + 0.03, D(-0.5, 0.04), D(0.5, -0.02), K(0), backed ? H(1) : H(0.95, -0.04), .steelDark, plan: false)
        }
        b.outline()
        for i in 1..<4 { b.line(L, D(-0.5, 0.01 + Double(i) * 0.1), R, D(-0.5, 0.01 + Double(i) * 0.1)) }
        if backed {
            b.line(L, D(0.5, -back), R, D(0.5, -back))
            b.mm("1500", 1500, 650, 800); b.mm("1800", 1800, 650, 800); b.type(ft(5), .imperial, 1.524, 0.66, 0.81); b.type(ft(6), .imperial, 1.829, 0.66, 0.81)
        } else {
            b.mm("1800", 1800, 450, 450); b.type(ft(6), .imperial, 1.829, 0.46, 0.46)
        }
        return b.item
    }

    static func picnicTable() -> ComponentLibraryItem {
        var b = FB("Picnic Table", .site, group: "Site Furniture", keywords: ["picnic bench", "outdoor table", "park table"], "Timber picnic table with attached benches.")
        b.box("Top", L, R, D(-0.2), D(0.2), H(1, -0.04), T, .wood)
        b.box("Bench Front", L, R, Fr, D(-0.5, 0.26), K(0.42), K(0.46), .wood)
        b.box("Bench Back", L, R, D(0.5, -0.26), Bk, K(0.42), K(0.46), .wood)
        for (i, x) in [W(-0.5, 0.25), W(0.5, -0.25)].enumerated() {
            b.box("Frame \(i + 1)", x - 0.04, x + 0.04, D(-0.5, 0.05), D(0.5, -0.05), K(0.38), K(0.42), .wood, plan: false)
            b.taper("Legs \(i + 1)", x, K(0), bottom: (K(0.04), D(0.38)), top: (K(0.04), K(0.12)), K(0), H(1, -0.04), .wood, plan: false)
        }
        b.rect(L, D(-0.2), R, D(0.2)); b.rect(L, Fr, R, D(-0.5, 0.26)); b.rect(L, D(0.5, -0.26), R, Bk)
        b.mm("1800", 1800, 1600, 760); b.type(ft(6), .imperial, 1.829, 1.6, 0.76); b.type(ft(8), .imperial, 2.438, 1.6, 0.76)
        return b.item
    }

    static func litterBin() -> ComponentLibraryItem {
        var b = FB("Litter Bin", .site, group: "Site Furniture", keywords: ["trash can", "waste bin", "rubbish bin", "dustbin", "recycling"],
                   "Outdoor litter bin; the recycling type has two bins.")
        b.visibility = "Single Bin"
        b.cyl("Bin", K(0), K(0), W(0.5), K(0), T, .steelDark)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.3))
        b.visibility = "Recycling Pair"
        b.cyl("Bin Left", W(-0.25), K(0), D(0.5), K(0), T, .steelDark); b.cyl("Bin Right", W(0.25), K(0), D(0.5), K(0), T, .signGreen)
        b.circle(W(-0.25), K(0), D(0.5)); b.circle(W(0.25), K(0), D(0.5))
        b.visibility = nil
        b.any("Round", 0.5, 0.5, 0.9); b.any("Recycling Pair", 1.0, 0.48, 0.9)
        b.flag("Single Bin") { $0 < 0.8 }; b.flag("Recycling Pair") { $0 >= 0.8 }
        return b.item
    }

    static func bollard(removable: Bool) -> ComponentLibraryItem {
        var b = FB(removable ? "Bollard - Removable" : "Bollard - Fixed", .site, group: "Site Furniture",
                   keywords: ["bollard", "vehicle barrier", "post", "security"], removable ? "Removable steel bollard in a ground sleeve." : "Fixed steel bollard.")
        b.cyl("Post", K(0), K(0), W(0.5), K(0), H(1, -0.03), removable ? .metal : .steelDark)
        b.revolve("Cap", [(K(0), K(0)), (W(0.5), K(0)), (W(0.3), K(0.03)), (K(0), K(0.03))], K(0), K(0), H(1, -0.03), removable ? .metal : .steelDark)
        if removable { b.box("Sleeve Plate", W(-0.8), W(0.8), W(-0.8), W(0.8), K(0), K(0.01), .metal) ; b.rect(W(-0.8), W(-0.8), W(0.8), W(0.8)) }
        b.circle(K(0), K(0), W(0.5))
        b.mm("150 Dia x 900", 150, 150, 900); b.inch("\(inch(6)) Dia x \(inch(36))", 6, 6, 36)
        return b.item
    }

    static func fireHydrant() -> ComponentLibraryItem {
        var b = FB("Fire Hydrant", .site, group: "Utilities", keywords: ["hydrant", "fire plug", "fire service", "standpipe"], "Pillar fire hydrant with side outlets.")
        b.cyl("Base", K(0), K(0), W(0.4), K(0), K(0.08), .signRed)
        b.cyl("Barrel", K(0), K(0), W(0.28), K(0.08), H(0.85), .signRed)
        b.revolve("Bonnet", [(K(0), K(0)), (W(0.32), K(0)), (W(0.2), H(0.1)), (K(0.02), H(0.15)), (K(0), H(0.15))], K(0), K(0), H(0.85), .signRed)
        b.bar("Outlets", [(W(-0.5), K(0)), (W(0.5), K(0))], z: H(0.62), r: W(0.12), .signRed, sides: 8)
        b.circle(K(0), K(0), W(0.4)); b.rect(W(-0.5), W(-0.12), W(0.5), W(0.12))
        b.any("Two Outlet", 0.45, 0.45, 0.8); b.any("Three Outlet", 0.5, 0.5, 0.9)
        return b.item
    }

    /// Inverted-U hoop between (x0, y) and (x1, y).
    static func hoop(_ b: inout FB, _ n: String, _ x0: LX, _ x1: LX, _ y: LX) {
        b.cyl("\(n) Leg A", x0, y, K(0.025), K(0), H(1, -0.1), .metal, plan: false)
        b.cyl("\(n) Leg B", x1, y, K(0.025), K(0), H(1, -0.1), .metal, plan: false)
        b.bar("\(n) Top", [(x0, y), (x1, y)], z: H(1, -0.1), r: K(0.025), .metal, sides: 8, plan: false)
        b.line(x0, y, x1, y); b.circle(x0, y, K(0.025)); b.circle(x1, y, K(0.025))
    }

    static func bikeRackU() -> ComponentLibraryItem {
        var b = FB("Bike Rack - Inverted U", .site, group: "Bicycles", keywords: ["cycle stand", "bike stand", "sheffield stand", "bicycle parking"],
                   "Inverted-U cycle stand for two bicycles; the dashed outline shows the parked bikes.")
        hoop(&b, "Hoop", W(-0.5), W(0.5), K(0))
        b.rect(W(-0.5, -0.1), K(-0.9), W(0.5, 0.1), K(-0.3), .hidden); b.rect(W(-0.5, -0.1), K(0.3), W(0.5, 0.1), K(0.9), .hidden)
        b.any("Single Stand", 0.75, 0.1, 0.85)
        return b.item
    }

    static func bikeRack5() -> ComponentLibraryItem {
        var b = FB("Bike Rack - 5 Bay", .site, group: "Bicycles", keywords: ["cycle rack", "bike rack", "bicycle parking", "wave rack"],
                   "Row of five cycle hoops on a rail; Width is the row, Depth the bike length.")
        for i in 0..<5 {
            let x = W(-0.4 + 0.2 * Double(i))
            b.cyl("Post \(i + 1)", x, D(-0.2), K(0.025), K(0), H(1, -0.1), .metal, plan: false)
            b.cyl("Post \(i + 1)b", x, D(0.2), K(0.025), K(0), H(1, -0.1), .metal, plan: false)
            b.bar("Hoop \(i + 1)", [(x, D(-0.2)), (x, D(0.2))], z: H(1, -0.1), r: K(0.025), .metal, sides: 8, plan: false)
            b.line(x, D(-0.2), x, D(0.2)); b.line(x, Fr, x, Bk, .hidden)
        }
        b.box("Rail", L, R, K(-0.03), K(0.03), K(0), K(0.05), .metal)
        b.rect(L, K(-0.03), R, K(0.03))
        b.any("Standard", 3.0, 1.8, 0.85)
        return b.item
    }

    static func monumentSign() -> ComponentLibraryItem {
        var b = FB("Signage - Monument Sign", .site, group: "Signage", keywords: ["entry sign", "monument", "site sign", "building sign"],
                   "Freestanding monument sign on a masonry base.")
        b.box("Base", W(-0.5, -0.1), W(0.5, 0.1), D(-0.5, -0.1), D(0.5, 0.1), K(0), H(0.2), .concrete)
        b.box("Panel", L, R, Fr, Bk, H(0.2), T, .stone)
        b.outline(); b.rect(W(-0.5, -0.1), D(-0.5, -0.1), W(0.5, 0.1), D(0.5, 0.1))
        b.mm("1800 x 900", 1800, 300, 900); b.type("\(ft(6)) x \(ft(3))", .imperial, 1.829, 0.3, 0.914)
        return b.item
    }

    static func pylonSign() -> ComponentLibraryItem {
        var b = FB("Signage - Wayfinding Pylon", .site, group: "Signage", keywords: ["wayfinding", "directory", "totem", "pylon"], "Freestanding wayfinding pylon.")
        b.box("Pylon", L, R, Fr, Bk, K(0), T, .steelDark)
        b.box("Face", W(-0.5, 0.04), W(0.5, -0.04), D(-0.5, -0.005), Fr, H(0.3), H(0.95), .signFace, plan: false)
        b.outline()
        b.any("Standard", 0.6, 0.2, 2.2)
        return b.item
    }

    static func flagpole() -> ComponentLibraryItem {
        var b = FB("Flagpole", .site, group: "Site Furniture", keywords: ["flag pole", "mast", "flag"], "Tapered flagpole with a flag.")
        b.taper("Pole", K(0), K(0), bottom: (K(0.06), K(0.06)), top: (K(0.03), K(0.03)), K(0), T, .metal)
        b.box("Flag", K(0.03), W(0.5), K(-0.005), K(0.005), H(0.8), H(0.98), .signBlue, plan: false)
        b.circle(K(0), K(0), K(0.06)); b.line(K(0.03), K(0), W(0.5), K(0), .hidden)
        b.mm("6 m", 1500, 150, 6000); b.mm("9 m", 2000, 150, 9000); b.type(ft(20), .imperial, 1.5, 0.15, 6.1); b.type(ft(30), .imperial, 2.0, 0.15, 9.14)
        return b.item
    }

    static func mailbox() -> ComponentLibraryItem {
        var b = FB("Mailbox - Pedestal", .site, group: "Utilities", regions: [.usa], keywords: ["mailbox", "letter box", "post box"], "Curbside mailbox on a post.")
        b.box("Post", W(-0.2), W(0.2), D(0.2), D(0.4), K(0), H(0.78), .wood)
        b.box("Box", L, R, Fr, Bk, H(0.78), H(0.95), .steelDark)
        b.bar("Top", [(K(0), Fr), (K(0), Bk)], z: H(0.95), r: W(0.5), .steelDark, sides: 12, plan: false)
        b.outline()
        b.any("Standard", 0.18, 0.5, 1.15)
        return b.item
    }

    static func outdoorFountain() -> ComponentLibraryItem {
        var b = FB("Drinking Fountain - Outdoor", .site, group: "Site Furniture", keywords: ["water fountain", "bubbler", "drinking water", "park"],
                   "Pedestal drinking fountain.")
        b.cyl("Pedestal", K(0), K(0), W(0.25), K(0), H(0.85), .concrete)
        b.cyl("Bowl", K(0), K(0), W(0.5), H(0.85), T, .metal)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.25), .hidden)
        b.any("Standard", 0.45, 0.45, 0.95)
        return b.item
    }

    static func busShelter() -> ComponentLibraryItem {
        var b = FB("Bus Shelter", .site, group: "Site Furniture", keywords: ["bus stop", "transit shelter", "canopy"], "Glazed bus shelter with a bench.")
        b.box("Roof", L, R, Fr, Bk, H(1, -0.1), T, .metal)
        b.box("Back Glass", L, R, D(0.5, -0.02), Bk, K(0.1), H(1, -0.1), .glass)
        b.box("End Glass", L, W(-0.5, 0.02), D(-0.1), Bk, K(0.1), H(1, -0.1), .glass)
        for (i, x) in [W(-0.5, 0.03), W(0.5, -0.03)].enumerated() { b.box("Post \(i + 1)", x - 0.03, x + 0.03, D(0.5, -0.06), Bk, K(0), H(1, -0.1), .metal, plan: false) }
        b.box("Bench", W(-0.3), W(0.3), D(0.5, -0.4), D(0.5, -0.05), K(0.42), K(0.47), .wood)
        b.rect(L, Fr, R, Bk, .hidden); b.line(L, D(0.5, -0.02), R, D(0.5, -0.02)); b.line(W(-0.5, 0.02), D(-0.1), W(-0.5, 0.02), Bk)
        b.rect(W(-0.3), D(0.5, -0.4), W(0.3), D(0.5, -0.05))
        b.any("Standard", 3.6, 1.5, 2.5)
        return b.item
    }

    static func patioUmbrella() -> ComponentLibraryItem {
        var b = FB("Umbrella - Patio", .site, group: "Site Furniture", keywords: ["parasol", "sun umbrella", "shade", "cafe umbrella"], "Patio umbrella on a weighted base.")
        b.cyl("Base", K(0), K(0), K(0.25), K(0), K(0.08), .concrete, plan: false)
        b.cyl("Pole", K(0), K(0), K(0.02), K(0.08), T, .metal, plan: false)
        b.blend("Canopy", ngon(K(0), K(0), W(0.5), 8), ngon(K(0), K(0), K(0.05), 8), H(0.8), H(0.97), .fabricAccent)
        b.poly(ngon(K(0), K(0), W(0.5), 8)); for p in ngon(K(0), K(0), W(0.5), 8) { b.line(K(0), K(0), p.0, p.1) }
        b.mm("2700", 2700, 2700, 2400); b.type(ft(9), .imperial, 2.74, 2.74, 2.4)
        return b.item
    }

    static func manhole() -> ComponentLibraryItem {
        var b = FB("Manhole Cover", .site, group: "Utilities", keywords: ["access cover", "inspection chamber", "sewer", "drain"], "Round manhole cover and frame.")
        b.cyl("Frame", K(0), K(0), W(0.5), K(0), T, .steelDark)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.44))
        for f in [-0.2, 0.0, 0.2] { b.line(W(-0.35), W(f), W(0.35), W(f)) }
        b.mm("600", 700, 700, 20); b.inch(inch(24), 28, 28, 1)
        return b.item
    }

    static func planterRound() -> ComponentLibraryItem {
        var b = FB("Planter - Round", .site, group: "Planters", keywords: ["planter", "plant pot", "container", "tub"], "Round planter filled with soil.")
        b.revolve("Planter", [(K(0), K(0)), (W(0.42), K(0)), (W(0.5), T), (W(0.46), T), (W(0.4), H(0.1)), (K(0), H(0.1))], K(0), K(0), K(0), .concrete)
        b.cyl("Soil", K(0), K(0), W(0.45), H(0.1), H(1, -0.05), .soil, plan: false)
        b.circle(K(0), K(0), W(0.5)); b.circle(K(0), K(0), W(0.46))
        b.mm("600", 600, 600, 500); b.mm("900", 900, 900, 600); b.mm("1200", 1200, 1200, 700); b.inch(inch(24), 24, 24, 20); b.inch(inch(36), 36, 36, 24)
        return b.item
    }

    static func planterRect() -> ComponentLibraryItem {
        var b = FB("Planter - Rectangular", .site, group: "Planters", keywords: ["planter box", "trough", "raised bed"], "Rectangular planter box with soil.")
        b.box("Planter", L, R, Fr, Bk, K(0), T, .concrete)
        b.voidBox("Well", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.05), D(0.5, -0.05), K(0.1), H(1, 0.01))
        b.box("Soil", W(-0.5, 0.05), W(0.5, -0.05), D(-0.5, 0.05), D(0.5, -0.05), K(0.1), H(1, -0.05), .soil, plan: false)
        b.outline(); b.rect(W(-0.5, 0.05), D(-0.5, 0.05), W(0.5, -0.05), D(0.5, -0.05))
        b.mm("1200 x 500", 1200, 500, 500); b.mm("1800 x 600", 1800, 600, 600); b.inch("\(inch(48)) x \(inch(18))", 48, 18, 20)
        return b.item
    }

    static func treeGrate() -> ComponentLibraryItem {
        var b = FB("Tree Grate", .site, group: "Planters", keywords: ["tree grille", "tree pit", "street tree"], "Square tree grate with a central opening.")
        b.box("Grate", L, R, Fr, Bk, K(0), T, .steelDark)
        b.voidPrism("Opening", ngon(K(0), K(0), W(0.18), 16), K(-0.01), H(1, 0.01))
        b.outline(); b.circle(K(0), K(0), W(0.18))
        for i in 0..<8 { let a = Double(i) * 45 * .pi / 180; b.line(W(0.22 * cos(a)), W(0.22 * sin(a)), W(0.45 * cos(a)), W(0.45 * sin(a))) }
        b.mm("1200", 1200, 1200, 30); b.type(ft(4), .imperial, 1.219, 1.219, 0.03)
        return b.item
    }
}
