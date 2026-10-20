import Foundation
import ArcusGeometry

// COMPD: 20 Decorative & Finishing Accessories. Moldings and cornices are real profiles swept along the carcass top,
// bottom or a front (Full Length); grilles, perforated panels, mesh, cane and rattan are panels sized to a frame's
// opening (instance Width × Height) with patterned voids or strands; inlays route their groove.

extension ComponentLibrary {
    static var groupDDecorative: [ComponentDefinition] {
        [decorativeMolding(), crownMolding(), baseMolding(), cornice(), rosette(), metalInlay(), woodInlay(), cabinetGrille(), ventGrille(), perforatedPanel(),
         decorativeMesh(), caneWebbing(), rattanPanel(), feltPanel(), decorativeEndCap(), nameplate(), cornerGuard(), decorativeRivet(), nailhead(), bumper()]
    }

    /// An S-curve (ogee) from (u0, v0) to (u1, v1) in expression coordinates, `steps` segments.
    fileprivate static func ogee(_ u0: String, _ v0: String, _ u1: String, _ v1: String, steps: Int = 12) -> [FamilyPoint] {
        (0...steps).map { k in
            let t = Double(k) / Double(steps), s = 0.5 - 0.5 * cos(.pi * t)
            return DK.p("\(u0) + (\(u1) - (\(u0))) * \(LX.num(t))", "\(v0) + (\(v1) - (\(v0))) * \(LX.num(s))")
        }
    }

    // MARK: Moldings

    static func decorativeMolding() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Molding", .decorative, "Moldings", "Applied panel molding (ogee) on a door, side or drawer front, run straight or as a frame.")
        b.tags("molding", "moulding", "panel molding", "applied", "trim", "ogee")
        b.aliases("decorative moldings", "panel moulding", "applied molding", "bolection", "picture frame molding")
        b.material("Molding Material", .primedMDF)
        b.runLength(DK.inch(24))
        b.length("Molding Width", DK.inch(0.75)); b.length("Projection", DK.inch(0.375))
        b.hostRun(ComponentHostKind.fronts + [.sidePanel, .back, .rail], faces: [.front, .outside])
        b.run("Molding", [DK.p("-Molding Width / 2", DK.z), DK.p("Molding Width / 2", DK.z), DK.p("Molding Width / 2", "Projection * 0.25")]
              + ogee("Molding Width / 2 - Molding Width * 0.1", "Projection * 0.3", "-Molding Width / 2 + Molding Width * 0.2", "Projection")
              + [DK.p("-Molding Width / 2", "Projection")])
        b.runScrews("Molding brad", diameter: 1.2, depth: 12)
        b.runOutlines(y: ("-Molding Width / 2", "Molding Width / 2"), z: (DK.z, "Projection"))
        b.type("Panel Molding - 3/4\"", cost: 1.20, model: "DM-PM34")
        b.type("Bolection Molding - 1 1/4\"", ["Molding Width": DK.inch(1.25), "Projection": DK.inch(0.625)], cost: 2.40, model: "DM-BM114")
        b.type("Panel Molding - 1/2\"", ["Molding Width": DK.inch(0.5), "Projection": DK.inch(0.25)], cost: 0.90, model: "DM-PM12")
        return b.build()
    }

    static func crownMolding() -> ComponentDefinition {
        var b = ComponentBuilder("Crown Molding", .decorative, "Moldings", "Sprung crown molding along the top of the carcass front and sides, with an ogee face.")
        b.tags("crown", "molding", "moulding", "top", "cornice", "ogee", "sprung")
        b.aliases("crown moldings", "crown moulding", "cabinet crown", "top molding", "cove crown")
        b.material("Molding Material", .primedMDF)
        b.runLength(DK.inch(36))
        b.length("Molding Height", DK.inch(3.5)); b.length("Projection", DK.inch(2.5))
        // On the front face just under the top: Y up the face from the crown's bottom, Z out.
        b.host([.top, .sidePanel, .rail], faces: [.front, .outside], align: .full, alignments: [.full], offsetY: 0)
        let h = "Molding Height", p = "Projection"
        b.run("Crown", [DK.p(DK.z, DK.z), DK.p(DK.z, "\(p) * 0.06"), DK.p("\(h) * 0.06", "\(p) * 0.06")]
              + ogee("\(h) * 0.06", "\(p) * 0.1", "\(h) * 0.86", "\(p) * 0.9", steps: 14)
              + [DK.p("\(h) * 0.86", p), DK.p(h, p), DK.p(h, DK.z)])
        b.runScrews("Crown nail", diameter: 1.5, depth: 16, y: "Molding Height * 0.3")
        b.runOutlines(y: (DK.z, "Molding Height"), z: (DK.z, "Projection"))
        b.symbol(.side, [.medium, .fine], .polyline([DK.p(DK.z, DK.z), DK.p("Projection", "Molding Height")], closed: false))
        b.requires(.note("Miter outside corners at 45°; cope inside corners."))
        b.type("Crown Molding - 2 1/4\"", ["Molding Height": DK.inch(2.25), "Projection": DK.inch(1.5)], cost: 2.20, model: "CM-214")
        b.type("Crown Molding - 3 1/2\"", cost: 3.10, model: "CM-312", isDefault: true)
        b.type("Crown Molding - 4 1/2\"", ["Molding Height": DK.inch(4.5), "Projection": DK.inch(3.25)], cost: 4.20, model: "CM-412")
        return b.build()
    }

    static func baseMolding() -> ComponentDefinition {
        var b = ComponentBuilder("Base Molding", .decorative, "Moldings", "Base molding along the bottom of the carcass or plinth, with an ogee top.")
        b.tags("base", "baseboard", "skirting", "molding", "plinth", "bottom")
        b.aliases("base moldings", "base moulding", "baseboard", "skirting board", "cabinet base trim")
        b.material("Molding Material", .primedMDF)
        b.runLength(DK.inch(36))
        b.length("Molding Height", DK.inch(4.25)); b.length("Thickness", DK.inch(0.625))
        b.host([.plinth, .bottom, .sidePanel, .floor], faces: [.front, .outside], align: .full, alignments: [.full], offsetY: 0)
        let h = "Molding Height", t = "Thickness"
        b.run("Base", [DK.p(DK.z, DK.z), DK.p(DK.z, t), DK.p("\(h) * 0.7", t)] + ogee("\(h) * 0.72", "\(t) * 0.95", h, "\(t) * 0.3", steps: 10) + [DK.p(h, DK.z)])
        b.runScrews("Base nail", diameter: 1.5, depth: 16, y: "Molding Height * 0.4")
        b.runOutlines(y: (DK.z, "Molding Height"), z: (DK.z, "Thickness"))
        b.type("Base Molding - 3\"", ["Molding Height": DK.inch(3), "Thickness": DK.inch(0.5)], cost: 1.40, model: "BM-3")
        b.type("Base Molding - 4 1/4\"", cost: 1.90, model: "BM-414", isDefault: true)
        b.type("Base Molding - 5 1/4\"", ["Molding Height": DK.inch(5.25), "Thickness": DK.inch(0.75)], cost: 2.50, model: "BM-514")
        return b.build()
    }

    static func cornice() -> ComponentDefinition {
        var b = ComponentBuilder("Furniture Cornice", .decorative, "Moldings", "Built-up cornice capping a tall cabinet: fascia, cove and an overhanging cap.")
        b.tags("cornice", "cap", "top", "cove", "fascia", "wardrobe", "armoire")
        b.aliases("furniture cornices", "cabinet cornice", "top cap molding", "cornice molding", "armoire top")
        b.material("Cornice Material", .oak)
        b.runLength(DK.inch(36))
        b.length("Cornice Height", DK.inch(3)); b.length("Projection", DK.inch(2))
        b.host([.top, .sidePanel], faces: [.front, .outside], align: .full, alignments: [.full], offsetY: 0)
        let h = "Cornice Height", p = "Projection"
        b.run("Cornice", [DK.p(DK.z, DK.z), DK.p(DK.z, "\(p) * 0.3"), DK.p("\(h) * 0.4", "\(p) * 0.3")]
              + DK.arc("\(h) * 0.8", "\(p) * 0.3", "\(h) * 0.4", 180, 90, steps: 8).dropFirst().map { $0 }
              + [DK.p("\(h) * 0.8", p), DK.p(h, p), DK.p(h, DK.z)])
        b.runScrews("Cornice screw", diameter: 3, depth: 16, y: "Cornice Height * 0.2")
        b.runOutlines(y: (DK.z, "Cornice Height"), z: (DK.z, "Projection"))
        b.type("Cornice - 3\"", cost: 6.50, model: "FC-3")
        b.type("Cornice - 5\"", ["Cornice Height": DK.inch(5), "Projection": DK.inch(3)], cost: 9.50, model: "FC-5")
        return b.build()
    }

    // MARK: Ornaments and inlays

    static func rosette() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Rosette", .decorative, "Ornaments", "Turned rosette (round or in a square block) glued on a face: corners of door frames, pilasters, headboards.")
        b.tags("rosette", "ornament", "applique", "turned", "corner block", "decorative")
        b.aliases("decorative rosettes", "rosette block", "corner rosette", "wood applique", "bullseye rosette")
        b.material("Ornament Material", .maple)
        b.length("Diameter", DK.inch(3)); b.length("Thickness", DK.inch(0.625))
        b.flag("Square Block", false, instance: false, group: .dimensions)
        b.host(ComponentHostKind.fronts + [.sidePanel, .rail, .leg], faces: [.front, .outside], align: .center, alignments: [.center, .topLeft, .topRight, .bottomLeft, .bottomRight])
        let r = "Diameter / 2", t = "Thickness"
        b.visibility = "Square Block"
        b.box("Block", x: ("-\(r)", r), y: ("-\(r)", r), z: (DK.z, "\(t) * 0.45"))
        b.visibility = nil
        b.revolve("Rosette", profile: DK.pts([(DK.z, DK.z), ("\(r) * if(Square Block, 0.85, 1)", DK.z), ("\(r) * if(Square Block, 0.85, 1)", "\(t) * 0.5"),
                                              ("\(r) * 0.78", "\(t) * 0.62"), ("\(r) * 0.66", "\(t) * 0.5"), ("\(r) * 0.55", "\(t) * 0.7"), ("\(r) * 0.42", "\(t) * 0.8"),
                                              ("\(r) * 0.3", "\(t) * 0.62"), ("\(r) * 0.18", "\(t) * 0.85"), (DK.z, t)]))
        b.roundOutlines(radius: r, z: (DK.z, t))
        b.symbol(.face, [.fine], .circle((DK.z, DK.z), "\(r) * 0.66"), .circle((DK.z, DK.z), "\(r) * 0.3"))
        b.type("Rosette - 2\"", ["Diameter": DK.inch(2), "Thickness": DK.inch(0.5)], cost: 3.50, model: "DR-2")
        b.type("Rosette - 3\"", cost: 4.50, model: "DR-3", isDefault: true)
        b.type("Rosette Block - 3 1/2\"", ["Diameter": DK.inch(3.5), "Thickness": DK.inch(0.875)], flags: ["Square Block": true], cost: 6.00, model: "DRB-312")
        return b.build()
    }

    /// An inlay strip set flush in a routed groove (Inlay Width × Inlay Thickness).
    fileprivate static func inlay(_ b: inout ComponentBuilder, checker: Bool) {
        b.runLength(DK.inch(24))
        b.length("Inlay Width", DK.inch(0.125)); b.length("Inlay Thickness", DK.inch(0.0625))
        b.hostRun(ComponentHostKind.fronts + [.top, .sidePanel, .shelf, .rail, .leg], faces: [.front, .top, .outside])
        if checker {
            b.flag("Checker", false, instance: false, group: .dimensions)
            b.flag("Plain", true, formula: "not(Checker)")
            b.visibility = "Plain"
            b.runBox("Inlay", y: ("-Inlay Width / 2", "Inlay Width / 2"), z: ("-Inlay Thickness", CX.mm(0.1)))
            b.visibility = "Checker"
            let n = 24
            for k in 0..<n {
                let x0 = "-Length / 2 + Length * \(LX.num(Double(k) / Double(n)))", x1 = "-Length / 2 + Length * \(LX.num(Double(k + 1) / Double(n)))"
                for (row, y) in [("A", ("-Inlay Width / 2", CX.zero)), ("B", (CX.zero, "Inlay Width / 2"))] {
                    b.using((k % 2 == 0) == (row == "A") ? "Inlay Material" : "Contrast Material")
                    b.box("Checker \(k + 1)\(row)", x: (x0, x1), y: y, z: ("-Inlay Thickness", CX.mm(0.1)))
                }
            }
            b.using(nil)
            b.visibility = nil
        } else {
            b.runBox("Inlay", y: ("-Inlay Width / 2", "Inlay Width / 2"), z: ("-Inlay Thickness", CX.mm(0.1)))
        }
        b.groove("Inlay groove", from: (DK.lo, CX.zero), to: (DK.hi, CX.zero), width: "Inlay Width", depth: "Inlay Thickness")
        b.runOutlines(y: ("-Inlay Width / 2", "Inlay Width / 2"), z: ("-Inlay Thickness", DK.z))
    }

    static func metalInlay() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Metal Inlay", .decorative, "Inlays", "Brass or stainless strip inlaid flush in a routed groove (tops, drawer fronts, legs).")
        b.tags("inlay", "metal", "brass", "stainless", "strip", "insert", "groove")
        b.aliases("decorative metal inserts", "brass inlay", "metal strip inlay", "brass insert", "metal accent strip")
        b.material("Inlay Material", .brass)
        inlay(&b, checker: false)
        b.type("Brass Inlay - 1/8\"", cost: 2.80, model: "MI-B18")
        b.type("Brass Inlay - 1/4\"", ["Inlay Width": DK.inch(0.25)], cost: 4.20, model: "MI-B14")
        b.type("Flat Bar Inlay - 10 mm", ["Inlay Width": DK.mm(10), "Inlay Thickness": DK.mm(1.5)], cost: 4.50, model: "MI-S10")
        return b.build()
    }

    static func woodInlay() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Wood Inlay", .decorative, "Inlays", "Contrasting wood stringing or checker banding inlaid flush in a routed groove.")
        b.tags("inlay", "wood", "stringing", "banding", "marquetry", "insert", "groove")
        b.aliases("decorative wood inserts", "wood inlay", "stringing", "inlay banding", "checker banding", "marquetry banding")
        b.material("Inlay Material", .walnut)
        b.material("Contrast Material", .maple)
        inlay(&b, checker: true)
        b.type("Wood Stringing - 1/8\"", cost: 1.20, model: "WI-W18")
        b.type("Wood Stringing - 1/4\"", ["Inlay Width": DK.inch(0.25)], cost: 1.60, model: "WI-M14")
        b.type("Checker Banding - 3/8\"", ["Inlay Width": DK.inch(0.375)], flags: ["Checker": true], cost: 3.80, model: "WI-CB38")
        return b.build()
    }

    // MARK: Panels with patterns

    /// Frame bars round an opening (Width × Height), `bar` wide and `depth` out of the face.
    fileprivate static func border(_ b: inout ComponentBuilder, bar: String, depth: String, from z0: String = CX.zero) {
        let w = "Width / 2", h = "Height / 2"
        b.box("Frame L", x: ("-\(w)", "-\(w) + \(bar)"), y: ("-\(h)", h), z: (z0, depth))
        b.box("Frame R", x: ("\(w) - \(bar)", w), y: ("-\(h)", h), z: (z0, depth))
        b.box("Frame T", x: ("-\(w) + \(bar)", "\(w) - \(bar)"), y: ("\(h) - \(bar)", h), z: (z0, depth))
        b.box("Frame B", x: ("-\(w) + \(bar)", "\(w) - \(bar)"), y: ("-\(h)", "-\(h) + \(bar)"), z: (z0, depth))
    }

    /// Opening-sized panels: instance Width and Height, hosted in a door's frame opening or on a back or side.
    fileprivate static func openingPanel(_ b: inout ComponentBuilder, width: Double, height: Double) {
        b.length("Width", width, instance: true); b.length("Height", height, instance: true)
        b.host([.door, .back, .sidePanel, .rail, .glass], faces: [.front, .inside], align: .center)
        b.outlines(x: ("-Width / 2", "Width / 2"), y: ("-Height / 2", "Height / 2"), z: (DK.z, CX.mm(6)))
    }

    static func cabinetGrille() -> ComponentDefinition {
        var b = ComponentBuilder("Cabinet Grille", .decorative, "Grilles & Mesh", "Brass lattice grille set in a door's opening in place of glass: square or diamond pattern.")
        b.tags("grille", "lattice", "brass", "door insert", "diamond", "square", "wire")
        b.aliases("cabinet grilles", "door grille", "brass grille", "lattice insert", "grille panel", "decorative grille")
        b.material("Grille Material", .antiqueBrass)
        openingPanel(&b, width: DK.inch(12), height: DK.inch(20))
        b.length("Bar", DK.mm(3)); b.length("Grille Depth", DK.mm(3))
        b.flag("Diamond", false, instance: false, group: .dimensions)
        b.flag("Square", true, formula: "not(Diamond)")
        border(&b, bar: CX.mm(8), depth: "Grille Depth")
        b.visibility = "Square"
        for k in 1..<6 {
            let x = "-Width / 2 + Width * \(LX.num(Double(k) / 6))"
            b.box("Wire V\(k)", x: ("\(x) - Bar / 2", "\(x) + Bar / 2"), y: ("-Height / 2", "Height / 2"), z: (CX.mm(0.5), "Grille Depth - 0.0005 m"))
        }
        for k in 1..<9 {
            let y = "-Height / 2 + Height * \(LX.num(Double(k) / 9))"
            b.box("Wire H\(k)", x: ("-Width / 2", "Width / 2"), y: ("\(y) - Bar / 2", "\(y) + Bar / 2"), z: (CX.mm(0.5), "Grille Depth - 0.0005 m"))
        }
        b.visibility = "Diamond"
        // Lines u + v = c and u - v = c across the opening (u, v from 0 to 1), as slanted bars.
        let n = 8
        for k in 0..<n {
            let c = (Double(k) + 0.5) * 2 / Double(n)
            for (dir, name) in [(1.0, "A"), (-1.0, "B")] {
                let u0 = max(0, c - 1), u1 = min(1, c)
                func pt(_ u: Double, _ dx: String) -> FamilyPoint {
                    let v = dir > 0 ? c - u : 1 - (c - u)
                    return DK.p("-Width / 2 + Width * \(LX.num(u)) \(dx)", "-Height / 2 + Height * \(LX.num(v))")
                }
                b.extrusion("Diamond \(name)\(k + 1)", profile: [pt(u0, "- Bar / 2"), pt(u1, "- Bar / 2"), pt(u1, "+ Bar / 2"), pt(u0, "+ Bar / 2")],
                            from: CX.mm(0.5), to: "Grille Depth - 0.0005 m")
            }
        }
        b.visibility = nil
        b.requires(.note("Sized to the door's glass opening plus the rebate (1/4\" a side)."))
        b.type("Cabinet Grille - Square Lattice", cost: 38.00, model: "CGR-SQ")
        b.type("Cabinet Grille - Diamond Lattice", flags: ["Diamond": true], cost: 42.00, model: "CGR-DM")
        return b.build()
    }

    static func ventGrille() -> ComponentDefinition {
        var b = ComponentBuilder("Ventilation Grille", .decorative, "Grilles & Mesh", "Vent for cabinets with electronics or appliances: a round louvred vent in a bored hole or a slot vent in a cutout.")
        b.tags("vent", "ventilation", "grille", "louver", "air", "electronics", "round")
        b.aliases("ventilation grilles", "air vent", "cabinet vent", "round vent", "slot vent", "louvre vent", "2\" vent")
        b.material("Vent Material", .blackPlastic)
        b.length("Diameter", DK.inch(2)); b.length("Vent Width", 0); b.length("Vent Height", 0); b.length("Rim", DK.mm(4)); b.length("Sleeve", DK.mm(12))
        b.flag("Slot", false, instance: false, group: .dimensions)
        b.flag("Round", true, formula: "not(Slot)")
        b.host([.back, .sidePanel, .bottom, .top, .plinth, .door], faces: [.inside, .back, .front, .bottom], align: .center)
        b.visibility = "Round"
        b.pipe("Rim", axis: .z, center: (DK.z, DK.z), outer: "Diameter / 2 + Rim", inner: "Diameter / 2 - 0.002 m", from: CX.zero, to: CX.mm(2.5))
        b.pipe("Sleeve", axis: .z, center: (DK.z, DK.z), outer: "Diameter / 2", inner: "Diameter / 2 - 0.0015 m", from: "-Sleeve", to: CX.zero)
        for k in 1...3 {
            let r = "Diameter / 2 * \(LX.num(Double(k) / 3.5))"
            b.pipe("Ring \(k)", axis: .z, center: (DK.z, DK.z), outer: "\(r) + 0.0008 m", inner: "\(r) - 0.0008 m", from: "-0.002 m", to: CX.mm(1.5))
        }
        b.box("Spoke H", x: ("-Diameter / 2", "Diameter / 2"), y: (CX.mm(-0.8), CX.mm(0.8)), z: (CX.mm(-2), CX.mm(1.5)))
        b.box("Spoke V", x: (CX.mm(-0.8), CX.mm(0.8)), y: ("-Diameter / 2", "Diameter / 2"), z: (CX.mm(-2), CX.mm(1.5)))
        b.visibility = "Slot"
        let rim = b.roundedBar("Slot Rim", width: "Vent Width + 2 * Rim", height: "Vent Height + 2 * Rim", radius: CX.mm(3), from: CX.zero, to: CX.mm(2.5))
        let opening = b.box("Slot Opening", x: ("-Vent Width / 2", "Vent Width / 2"), y: ("-Vent Height / 2", "Vent Height / 2"), z: (CX.mm(-1), CX.mm(3)), void: true)
        if let k = b.definition.family.solids.firstIndex(where: { $0.id == opening }) { b.definition.family.solids[k].cuts = [rim] }
        for k in 0..<6 {
            let y = "-Vent Height / 2 + Vent Height * \(LX.num((Double(k) + 0.5) / 6))"
            b.extrusion("Louver \(k + 1)", profile: DK.pts([("\(y) - 0.004 m", CX.mm(-6)), ("\(y) - 0.0025 m", CX.mm(-6)), ("\(y) + 0.004 m", CX.mm(1.5)), ("\(y) + 0.0025 m", CX.mm(1.5))]),
                        plane: .yz, from: "-Vent Width / 2", to: "Vent Width / 2")
        }
        b.visibility = nil
        b.drill("Vent hole", x: CX.zero, y: CX.zero, diameter: "if(Slot, 0 m, Diameter)", depth: "Host Thickness", through: true)
        b.pocket("Vent cutout", width: "if(Slot, Vent Width, 0 m)", height: "if(Slot, Vent Height, 0 m)", depth: "Host Thickness", through: true)
        b.roundOutlines(radius: "Diameter / 2 + Rim", z: ("-Sleeve", CX.mm(2.5)))
        b.type("Round Vent - 2\"", cost: 1.80, model: "VG-R2")
        b.type("Round Vent - 3\"", ["Diameter": DK.inch(3)], cost: 2.40, model: "VG-R3")
        b.type("Slot Vent - 10\" x 3\"", ["Vent Width": DK.inch(10), "Vent Height": DK.inch(3), "Diameter": DK.inch(3)], flags: ["Slot": true], cost: 6.50, model: "VG-S103")
        return b.build()
    }

    static func perforatedPanel() -> ComponentDefinition {
        var b = ComponentBuilder("Perforated Panel", .decorative, "Grilles & Mesh", "Perforated metal or MDF panel with a grid of round holes, set in a frame or over a vent.")
        b.tags("perforated", "panel", "holes", "metal", "speaker", "vent", "screen")
        b.aliases("perforated panels", "perforated metal", "perforated sheet", "speaker grille panel", "pegboard look", "punched metal")
        b.material("Panel Material", .matteBlack)
        openingPanel(&b, width: DK.inch(12), height: DK.inch(18))
        b.length("Thickness", DK.mm(1.5)); b.length("Hole Diameter", DK.inch(0.25))
        // The sheet as strips between hole rows, each edge notched with the holes' halves: real round holes without voids
        // (a grid of void cuts is far too slow to evaluate).
        let cols = 8, rows = 12, r = "Hole Diameter / 2"
        func xs(_ i: Int) -> String { "-Width / 2 + Width * \(LX.num((Double(i) + 0.5) / Double(cols)))" }
        func ys(_ j: Int) -> String { "-Height / 2 + Height * \(LX.num((Double(j) + 0.5) / Double(rows)))" }
        func notches(_ y: String, up: Bool) -> [FamilyPoint] {
            let order = up ? Array(0..<cols) : Array((0..<cols).reversed())
            return order.flatMap { i in
                (0...6).map { k -> FamilyPoint in
                    let a = up ? Double.pi * (1 - Double(k) / 6) : -Double.pi * Double(k) / 6
                    return DK.p("\(xs(i)) + \(r) * \(LX.num(cos(a)))", "\(y) + \(r) * \(LX.num(sin(a)))")
                }
            }
        }
        for j in 0...rows {
            let y0 = j == 0 ? "-Height / 2" : ys(j - 1), y1 = j == rows ? "Height / 2" : ys(j)
            var pts = [DK.p("-Width / 2", y0)]
            if j > 0 { pts += notches(y0, up: true) }
            pts += [DK.p("Width / 2", y0), DK.p("Width / 2", y1)]
            if j < rows { pts += notches(y1, up: false) }
            pts.append(DK.p("-Width / 2", y1))
            b.extrusion("Sheet Strip \(j + 1)", profile: pts, from: CX.zero, to: "Thickness")
        }
        b.symbol(.face, [.fine], .circle(("-Width / 2 + Width / 16", "-Height / 2 + Height / 24"), "Hole Diameter / 2"))
        b.type("Perforated Panel - 1/4\" Holes, Steel", cost: 22.00, model: "PP-14S")
        b.type("Perforated Panel - 3/8\" Holes, MDF", ["Thickness": DK.inch(0.25), "Hole Diameter": DK.inch(0.375)], cost: 16.00, model: "PP-38M")
        b.type("Perforated Panel - 1/8\" Holes, Speaker", ["Hole Diameter": DK.inch(0.125), "Thickness": DK.mm(1)], cost: 18.00, model: "PP-18S")
        return b.build()
    }

    static func decorativeMesh() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Mesh", .decorative, "Grilles & Mesh", "Woven wire mesh set in a door's opening: open, airy fronts for media and pantry cabinets.")
        b.tags("mesh", "wire", "woven", "brass", "door insert", "screen")
        b.aliases("decorative mesh", "woven wire mesh", "brass mesh", "wire mesh insert", "cabinet mesh", "grille mesh")
        b.material("Mesh Material", .brassMesh)
        openingPanel(&b, width: DK.inch(12), height: DK.inch(20))
        b.length("Wire Diameter", DK.mm(2))
        // Over-under weave: alternate wires sit a wire diameter apart.
        for k in 0..<16 {
            let x = "-Width / 2 + Width * \(LX.num((Double(k) + 0.5) / 16))", z = k % 2 == 0 ? "Wire Diameter / 2" : "Wire Diameter * 1.5"
            b.rod("Warp \(k + 1)", axis: .y, center: (x, z), radius: "Wire Diameter / 2", from: "-Height / 2", to: "Height / 2", segments: 12)
        }
        for k in 0..<24 {
            let y = "-Height / 2 + Height * \(LX.num((Double(k) + 0.5) / 24))", z = k % 2 == 0 ? "Wire Diameter * 1.5" : "Wire Diameter / 2"
            b.rod("Weft \(k + 1)", axis: .x, center: (y, z), radius: "Wire Diameter / 2", from: "-Width / 2", to: "Width / 2", segments: 12)
        }
        b.type("Decorative Mesh - Woven Brass", cost: 28.00, model: "DMS-WB")
        b.type("Decorative Mesh - Fine Woven Brass", ["Wire Diameter": DK.mm(1.5)], cost: 32.00, model: "DMS-FB")
        return b.build()
    }

    static func caneWebbing() -> ComponentDefinition {
        var b = ComponentBuilder("Cane Webbing", .decorative, "Cane & Rattan", "Pre-woven cane webbing pressed into a spline groove round a frame's opening.")
        b.tags("cane", "webbing", "rattan", "woven", "spline", "door insert", "natural")
        b.aliases("cane webbing", "rattan cane", "radio weave", "cane panel", "wicker webbing", "pressed cane")
        b.material("Cane Material", .cane)
        b.material("Spline Material", .rattan)
        openingPanel(&b, width: DK.inch(12), height: DK.inch(20))
        b.length("Strand", DK.mm(2.5)); b.length("Spline Width", DK.inch(0.1875)); b.length("Spline Depth", DK.inch(0.25)); b.length("Spline Inset", DK.inch(0.375))
        // The octagon weave: vertical, horizontal and both diagonal strands.
        for k in 0..<12 {
            let x = "-Width / 2 + Width * \(LX.num((Double(k) + 0.5) / 12))"
            b.box("Strand V\(k + 1)", x: ("\(x) - Strand / 2", "\(x) + Strand / 2"), y: ("-Height / 2", "Height / 2"), z: (DK.z, CX.mm(0.6)))
        }
        for k in 0..<18 {
            let y = "-Height / 2 + Height * \(LX.num((Double(k) + 0.5) / 18))"
            b.box("Strand H\(k + 1)", x: ("-Width / 2", "Width / 2"), y: ("\(y) - Strand / 2", "\(y) + Strand / 2"), z: (CX.mm(0.6), CX.mm(1.2)))
        }
        let n = 10
        for k in 0..<n {
            let c = (Double(k) + 0.5) * 2 / Double(n)
            for (dir, name) in [(1.0, "A"), (-1.0, "B")] {
                let u0 = max(0, c - 1), u1 = min(1, c)
                func pt(_ u: Double, _ dx: String) -> FamilyPoint {
                    let v = dir > 0 ? c - u : 1 - (c - u)
                    return DK.p("-Width / 2 + Width * \(LX.num(u)) \(dx)", "-Height / 2 + Height * \(LX.num(v))")
                }
                b.extrusion("Strand \(name)\(k + 1)", profile: [pt(u0, "- Strand * 0.6"), pt(u1, "- Strand * 0.6"), pt(u1, "+ Strand * 0.6"), pt(u0, "+ Strand * 0.6")],
                            from: dir > 0 ? CX.mm(1.2) : CX.mm(1.8), to: dir > 0 ? CX.mm(1.8) : CX.mm(2.4))
            }
        }
        b.using("Spline Material")
        border(&b, bar: "Spline Width", depth: CX.mm(2.6), from: CX.mm(0.2))
        b.using(nil)
        // The spline groove round the opening, Spline Inset in from the panel's edge.
        let w = "Width / 2 - Spline Inset", h = "Height / 2 - Spline Inset"
        for (n0, a, z) in [("Spline groove", ("-(\(w))", "-(\(h))"), ("\(w)", "-(\(h))")), ("Spline groove", ("\(w)", "-(\(h))"), ("\(w)", "\(h)")),
                           ("Spline groove", ("\(w)", "\(h)"), ("-(\(w))", "\(h)")), ("Spline groove", ("-(\(w))", "\(h)"), ("-(\(w))", "-(\(h))"))] {
            b.groove(n0, from: a, to: z, width: "Spline Width", depth: "Spline Depth", target: .counterpart)
        }
        b.requires(.note("Soak the cane, press it into the groove with the spline and trim; cut the panel 1\" larger than the groove all round."))
        b.type("Cane Webbing - Fine Open Weave", cost: 24.00, model: "CW-FO")
        b.type("Cane Webbing - Medium Weave", ["Strand": DK.mm(3.5)], cost: 26.00, model: "CW-MD")
        return b.build()
    }

    static func rattanPanel() -> ComponentDefinition {
        var b = ComponentBuilder("Rattan Panel", .decorative, "Cane & Rattan", "Woven rattan panel of round strands in a frame opening (doors, headboards, screens).")
        b.tags("rattan", "woven", "wicker", "panel", "natural", "door insert")
        b.aliases("rattan panels", "wicker panel", "woven rattan", "rattan sheet", "basket weave panel")
        b.material("Rattan Material", .rattan)
        openingPanel(&b, width: DK.inch(14), height: DK.inch(22))
        b.length("Strand Diameter", DK.mm(5))
        for k in 0..<10 {
            let x = "-Width / 2 + Width * \(LX.num((Double(k) + 0.5) / 10))", z = k % 2 == 0 ? "Strand Diameter / 2" : "Strand Diameter * 1.4"
            b.rod("Stake \(k + 1)", axis: .y, center: (x, z), radius: "Strand Diameter / 2", from: "-Height / 2", to: "Height / 2", segments: 12)
        }
        for k in 0..<16 {
            let y = "-Height / 2 + Height * \(LX.num((Double(k) + 0.5) / 16))", z = k % 2 == 0 ? "Strand Diameter * 1.4" : "Strand Diameter / 2"
            b.rod("Weaver \(k + 1)", axis: .x, center: (y, z), radius: "Strand Diameter / 2", from: "-Width / 2", to: "Width / 2", segments: 12)
        }
        b.type("Rattan Panel - Open Weave", cost: 34.00, model: "RP-OW")
        b.type("Rattan Panel - Heavy Strand", ["Strand Diameter": DK.mm(8)], cost: 42.00, model: "RP-HS")
        return b.build()
    }

    static func feltPanel() -> ComponentDefinition {
        var b = ComponentBuilder("Acoustic Felt Panel", .decorative, "Panels", "PET acoustic felt panel glued on a back or door: flat with eased edges, or grooved.")
        b.tags("acoustic", "felt", "panel", "pet", "sound", "grooved", "wall panel")
        b.aliases("acoustic felt panels", "felt panel", "pet felt", "acoustic panel", "sound absorbing panel", "slat felt panel")
        b.material("Felt Material", .petFelt)
        openingPanel(&b, width: DK.inch(24), height: DK.inch(24))
        b.length("Thickness", DK.mm(12)); b.length("Groove Width", DK.mm(6))
        b.flag("Grooved", false, instance: false, group: .dimensions)
        b.flag("Flat", true, formula: "not(Grooved)")
        b.visibility = "Flat"
        b.blend("Felt", bottom: ComponentKit.rect(width: "Width", height: "Height"), top: ComponentKit.rect(width: "Width - 0.006 m", height: "Height - 0.006 m"), from: CX.zero, to: "Thickness")
        b.visibility = "Grooved"
        // Strips between V grooves (chamfered edges meeting in a groove).
        let n = 8
        for k in 0..<n {
            let x0 = "-Width / 2 + Width * \(LX.num(Double(k) / Double(n)))", x1 = "-Width / 2 + Width * \(LX.num(Double(k + 1) / Double(n)))"
            b.extrusion("Felt Strip \(k + 1)", profile: DK.pts([(x0, DK.z), (x1, DK.z), (x1, "Thickness * 0.4"), ("\(x1) - Groove Width / 2", "Thickness"),
                                                                ("\(x0) + Groove Width / 2", "Thickness"), (x0, "Thickness * 0.4")]),
                        plane: .xz, from: "-Height / 2", to: "Height / 2")
        }
        b.visibility = nil
        b.type("Acoustic Felt Panel - 12 mm, 24\" x 24\"", cost: 28.00, model: "AFP-12-2424")
        b.type("Acoustic Felt Panel - 12 mm, 24\" x 48\"", ["Height": DK.inch(48)], cost: 48.00, model: "AFP-12-2448")
        b.type("Acoustic Felt Panel - Grooved, 24\" x 48\"", ["Height": DK.inch(48), "Thickness": DK.mm(20)], flags: ["Grooved": true], cost: 62.00, model: "AFP-G20-2448")
        return b.build()
    }

    // MARK: Small finishing parts

    static func decorativeEndCap() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative End Cap", .decorative, "Finials & Caps", "Turned end cap for a rod, rail or tube end: domed or a ball finial.")
        b.tags("end cap", "finial", "rod end", "cap", "ball", "dome", "turned")
        b.aliases("decorative end caps", "rod end cap", "finial", "tube cap", "rail end cap", "ball finial")
        b.material("Cap Material", .brass)
        b.length("Diameter", DK.inch(1)); b.length("Cap Length", DK.inch(0.75)); b.length("Socket Depth", DK.inch(0.5))
        b.flag("Ball", false, instance: false, group: .dimensions)
        b.flag("Dome", true, formula: "not(Ball)")
        b.host([.rail, .leg, .anyPart], faces: [.leftEdge, .rightEdge, .frontEdge, .any], align: .center)
        let r = "Diameter / 2"
        b.rod("Collar", axis: .z, center: (DK.z, DK.z), radius: "\(r) + 0.0015 m", from: CX.zero, to: "Cap Length * 0.3")
        b.visibility = "Dome"
        b.revolve("Dome", profile: [DK.p(DK.z, DK.z)] + (0...8).map { k -> FamilyPoint in
            let a = Double.pi / 2 * Double(k) / 8
            return DK.p("(\(r) + 0.0015 m) * \(LX.num(cos(a)))", "Cap Length * 0.7 * \(LX.num(sin(a)))")
        }, base: "Cap Length * 0.3")
        b.visibility = "Ball"
        b.rod("Neck", axis: .z, center: (DK.z, DK.z), radius: "\(r) * 0.45", from: "Cap Length * 0.3", to: "Cap Length * 0.5")
        b.revolve("Ball", profile: [DK.p(DK.z, DK.z)] + (1...11).map { k -> FamilyPoint in
            let a = -Double.pi / 2 + Double.pi * Double(k) / 12
            return DK.p("\(r) * 1.1 * \(LX.num(cos(a)))", "\(r) * 1.1 * \(LX.num(1 + sin(a)))")
        } + [DK.p(DK.z, "\(r) * 2.2")], base: "Cap Length * 0.45")
        b.visibility = nil
        b.roundOutlines(radius: "\(r) + 0.0015 m", z: (DK.z, "Cap Length"))
        b.type("End Cap - Dome 3/4\"", ["Diameter": DK.inch(0.75), "Cap Length": DK.inch(0.625)], cost: 3.50, model: "EC-D34")
        b.type("End Cap - Dome 1\"", cost: 4.00, model: "EC-D1", isDefault: true)
        b.type("End Cap - Ball Finial 1\"", flags: ["Ball": true], cost: 6.50, model: "EC-B1")
        return b.build()
    }

    static func nameplate() -> ComponentDefinition {
        var b = ComponentBuilder("Furniture Nameplate", .decorative, "Plates & Labels", "Engraved maker's or label plate pinned to a face: oval or rectangular.")
        b.tags("nameplate", "plate", "label", "maker's mark", "badge", "engraved")
        b.aliases("furniture nameplates", "maker plate", "name plate", "label holder", "brass plaque", "badge plate")
        b.material("Plate Material", .brass)
        b.length("Plate Width", DK.inch(2)); b.length("Plate Height", DK.inch(1)); b.length("Thickness", DK.mm(1.5))
        b.flag("Oval", true, instance: false, group: .dimensions)
        b.flag("Rectangle", false, formula: "not(Oval)")
        b.host(ComponentHostKind.fronts + [.sidePanel, .back, .rail, .top], faces: [.front, .inside, .outside, .back], align: .center)
        b.visibility = "Oval"
        b.extrusion("Oval Plate", profile: (0..<32).map { k in
            let a = Double(k) / 32 * 2 * .pi
            return DK.p("Plate Width / 2 * \(LX.num(cos(a)))", "Plate Height / 2 * \(LX.num(sin(a)))")
        }, from: CX.zero, to: "Thickness")
        b.visibility = "Rectangle"
        b.blend("Rect Plate", bottom: ComponentKit.rect(width: "Plate Width", height: "Plate Height"),
                top: ComponentKit.rect(width: "Plate Width - 0.002 m", height: "Plate Height - 0.002 m"), from: CX.zero, to: "Thickness")
        b.visibility = nil
        for s in ["-", ""] {
            b.rod("Pin \(s.isEmpty ? "R" : "L")", axis: .z, center: ("\(s)Plate Width * 0.4", CX.zero), radius: CX.mm(1.2), from: "Thickness", to: "Thickness + 0.0005 m", segments: 12)
        }
        b.screwPair("Nameplate pin", spacing: "Plate Width * 0.8", diameter: 1.5, depth: 8)
        b.outlines(x: ("-Plate Width / 2", "Plate Width / 2"), y: ("-Plate Height / 2", "Plate Height / 2"), z: (DK.z, "Thickness"))
        b.type("Nameplate - Oval 2\" x 1\"", cost: 6.00, model: "NP-O21")
        b.type("Nameplate - Rectangle 3\" x 1\"", ["Plate Width": DK.inch(3)], flags: ["Oval": false], cost: 7.50, model: "NP-R31")
        return b.build()
    }

    static func cornerGuard() -> ComponentDefinition {
        var b = ComponentBuilder("Corner Guard - Metal", .decorative, "Plates & Labels", "Decorative metal corner over three faces of a chest or trunk corner, with dome rivets.")
        b.tags("corner guard", "corner", "metal", "brass", "chest", "trunk", "campaign")
        b.aliases("corner guards", "box corner", "trunk corner", "chest corner", "campaign corner", "brass corner protector")
        b.material("Finish Material", .antiqueBrass)
        b.length("Leg", DK.inch(1.25)); b.length("Metal", DK.mm(1.2))
        // At the top-left corner of the front face: the front leaf (x ≥ 0, y ≤ 0), the top leaf and the side leaf.
        b.host([.top, .sidePanel, .lid, .door] + [.anyPart], faces: [.front], align: .topLeft, alignments: [.topLeft, .topRight, .bottomLeft, .bottomRight])
        b.extrusion("Front Leaf", profile: DK.pts([(DK.z, DK.z), ("Leg", DK.z), (DK.z, "-Leg")]), from: CX.zero, to: "Metal")
        b.extrusion("Top Leaf", profile: DK.pts([(DK.z, DK.z), (DK.z, "-Leg"), ("Leg", DK.z)]), plane: .xz, from: CX.zero, to: "Metal")
        b.extrusion("Side Leaf", profile: DK.pts([(DK.z, DK.z), ("-Leg", DK.z), (DK.z, "-Leg")]), plane: .yz, from: "-Metal", to: CX.zero)
        for (k, p) in [("Leg * 0.28", "-Leg * 0.28")].enumerated() {
            b.revolve("Rivet \(k + 1)", profile: DK.pts([(DK.z, DK.z), (CX.mm(2.5), DK.z), (CX.mm(2), CX.mm(1.2)), (DK.z, CX.mm(1.6))]), axis: (p.0, p.1), base: "Metal")
        }
        b.drill("Corner pin", x: "Leg * 0.28", y: "-Leg * 0.28", diameter: CX.mm(1.5), depth: CX.mm(10))
        b.outlines(x: (DK.z, "Leg"), y: ("-Leg", DK.z), z: ("-Leg", "Metal"))
        b.type("Corner Guard - 1 1/4\" Brass", cost: 4.50, model: "CGM-114")
        b.type("Corner Guard - 2\" Brass", ["Leg": DK.inch(2)], cost: 6.50, model: "CGM-2")
        return b.build()
    }

    static func decorativeRivet() -> ComponentDefinition {
        var b = ComponentBuilder("Decorative Rivet", .decorative, "Studs & Nails", "Dome or square-head decorative rivet (stud) set in a pilot hole: leather, straps and metal trims.")
        b.tags("rivet", "stud", "dome", "decorative", "leather", "strap")
        b.aliases("decorative rivets", "stud", "dome stud", "decorative stud", "leather rivet", "square stud")
        b.material("Finish Material", .antiqueBrass)
        b.length("Head Diameter", DK.inch(0.25)); b.length("Head Height", DK.inch(0.125)); b.length("Shank Diameter", DK.mm(2)); b.length("Shank Length", DK.mm(8))
        b.flag("Square Head", false, instance: false, group: .dimensions)
        b.flag("Dome Head", true, formula: "not(Square Head)")
        b.host([.anyPart, .form, .rail, .leg] + ComponentHostKind.fronts, faces: [.front, .any], align: .center)
        b.rod("Shank", axis: .z, center: (DK.z, DK.z), radius: "Shank Diameter / 2", from: "-Shank Length", to: CX.zero, segments: 12)
        b.visibility = "Dome Head"
        b.revolve("Dome", profile: [DK.p(DK.z, DK.z)] + (0...8).map { k -> FamilyPoint in
            let a = Double.pi / 2 * Double(k) / 8
            return DK.p("Head Diameter / 2 * \(LX.num(cos(a)))", "Head Height * \(LX.num(sin(a)))")
        })
        b.visibility = "Square Head"
        b.blend("Pyramid", bottom: ComponentKit.rect(width: "Head Diameter", height: "Head Diameter"), top: ComponentKit.rect(width: "Head Diameter * 0.35", height: "Head Diameter * 0.35"),
                from: CX.zero, to: "Head Height")
        b.visibility = nil
        b.drill("Rivet pilot", x: CX.zero, y: CX.zero, diameter: "Shank Diameter", depth: "Shank Length")
        b.roundOutlines(radius: "Head Diameter / 2", z: (DK.z, "Head Height"))
        b.type("Rivet - 1/4\" Dome", cost: 0.20, model: "DRV-D14")
        b.type("Rivet - 3/8\" Dome", ["Head Diameter": DK.inch(0.375), "Head Height": DK.inch(0.16)], cost: 0.25, model: "DRV-D38")
        b.type("Rivet - 1/4\" Square", flags: ["Square Head": true], cost: 0.25, model: "DRV-S14")
        return b.build()
    }

    static func nailhead() -> ComponentDefinition {
        var b = ComponentBuilder("Upholstery Nailhead", .decorative, "Studs & Nails", "Upholstery nailhead trim: single domed nails, or nail strip with a head every 5th hole.")
        b.tags("nailhead", "upholstery", "nail", "trim", "tack", "decorative")
        b.aliases("upholstery nailheads", "nail head trim", "decorative tack", "upholstery tack", "nail strip", "7/16\" nailhead")
        b.material("Finish Material", .antiqueBrass)
        b.length("Head Diameter", DK.inch(0.4375)); b.length("Head Height", DK.inch(0.19)); b.length("Pin Length", DK.inch(0.5))
        b.length("Spacing", DK.inch(0.5))
        b.flag("Strip", false, instance: false, group: .dimensions)
        b.host([.form, .rail, .anyPart, .sidePanel], faces: [.front, .outside, .any], align: .center)
        func head(_ name: String, _ x: String) {
            b.revolve(name, profile: [DK.p(DK.z, DK.z)] + (0...8).map { k -> FamilyPoint in
                let a = Double.pi / 2 * Double(k) / 8
                return DK.p("Head Diameter / 2 * \(LX.num(cos(a)))", "Head Height * \(LX.num(sin(a)))")
            }, axis: (x, CX.zero))
        }
        head("Head", CX.zero)
        b.rod("Pin", axis: .z, center: (DK.z, DK.z), radius: CX.mm(0.8), from: "-Pin Length", to: CX.zero, segments: 10)
        b.visibility = "Strip"
        for k in 1...4 { head("Strip Head \(k)", "Spacing * \(k)") }
        b.box("Strip Band", x: ("-Head Diameter / 2", "Spacing * 4 + Head Diameter / 2"), y: ("-Head Diameter * 0.3", "Head Diameter * 0.3"), z: (DK.z, "Head Height * 0.3"))
        b.visibility = nil
        b.roundOutlines(radius: "Head Diameter / 2", z: (DK.z, "Head Height"))
        b.type("Nailhead - 7/16\" Antique Brass", cost: 0.06, model: "UN-716")
        b.type("Nailhead - 1/2\" Large", ["Head Diameter": DK.inch(0.5), "Head Height": DK.inch(0.22)], cost: 0.08, model: "UN-12")
        b.type("Nail Strip - 7/16\", 5 Heads", flags: ["Strip": true], cost: 0.45, model: "UNS-716-5")
        return b.build()
    }

    static func bumper() -> ComponentDefinition {
        var b = ComponentBuilder("Furniture Bumper", .decorative, "Studs & Nails", "Self-adhesive bumper (dome or square) on a door back, drawer front or glass top.")
        b.tags("bumper", "pad", "self-adhesive", "dome", "clear", "silencer", "glass top")
        b.aliases("furniture bumpers", "bumper pad", "clear bumper", "rubber feet", "glass top bumper", "door bumper", "bump dot")
        b.material("Bumper Material", .silicone)
        b.length("Bumper Diameter", DK.mm(8)); b.length("Bumper Height", DK.mm(2.5))
        b.flag("Square", false, instance: false, group: .dimensions)
        b.flag("Dome", true, formula: "not(Square)")
        b.host(ComponentHostKind.fronts + [.top, .shelf, .glass, .sidePanel, .anyPart], faces: [.inside, .back, .top, .frontEdge], align: .topLeft,
               alignments: [.topLeft, .topRight, .bottomLeft, .bottomRight, .center], offsetX: DK.inch(1), offsetY: DK.inch(1))
        b.visibility = "Dome"
        b.revolve("Dome", profile: [DK.p(DK.z, DK.z)] + (0...8).map { k -> FamilyPoint in
            let a = Double.pi / 2 * Double(k) / 8
            return DK.p("Bumper Diameter / 2 * \(LX.num(cos(a)))", "Bumper Height * \(LX.num(sin(a)))")
        })
        b.visibility = "Square"
        b.roundedBar("Square Pad", width: "Bumper Diameter", height: "Bumper Diameter", radius: CX.mm(1.5), from: CX.zero, to: "Bumper Height")
        b.visibility = nil
        b.roundOutlines(radius: "Bumper Diameter / 2", z: (DK.z, "Bumper Height"))
        b.type("Bumper - 8 mm Clear Dome", cost: 0.05, model: "FB-8D")
        b.type("Bumper - 12 mm Clear Dome", ["Bumper Diameter": DK.mm(12), "Bumper Height": DK.mm(3.5)], cost: 0.07, model: "FB-12D")
        b.type("Bumper - 1/2\" Square", ["Bumper Diameter": DK.inch(0.5), "Bumper Height": DK.mm(3)], flags: ["Square": true], cost: 0.08, model: "FB-12S")
        return b.build()
    }
}
