import Foundation
import ArcusGeometry

// COMPB: 15 Wheels, Casters & Mobility. Plan frame: the origin is the mounting point on the underside of the bottom
// or leg, Z up, the caster hanging from Z = 0 to the floor at Z = -Height. Wheels turn about X (revolves on the YZ
// work plane), so they're round at any size. Glides, pads and cups sit under a leg's foot.

extension ComponentLibrary {
    static var groupBMobility: [ComponentDefinition] {
        [fixedCaster(), casterUpgrade(), lockingCaster(), twinWheelCaster(), heavyDutyCaster(), concealedCaster(), furnitureRoller(), rubberWheel(),
         polyurethaneWheel(), ballCaster(), retractableCaster(), levelingCaster(), slidingGlide(), feltPad(), nylonGlide(), floorProtector()]
    }

    static let wheelMaterial = "Wheel Material"

    /// A caster: plan frame under bottoms and legs, at the corners.
    static func casterBuilder(_ name: String, _ sub: String, _ description: String, _ finish: ComponentFinish, wheel: ComponentFinish = .rubber) -> ComponentBuilder {
        var b = ComponentBuilder(name, .mobility, sub, description, frame: .plan)
        b.hardwareKind(.caster)
        b.material("Finish Material", finish)
        b.material(wheelMaterial, wheel)
        b.host([.bottom, .leg, .plinth], faces: [.bottom], align: .bottomLeft, alignments: [.bottomLeft, .bottomRight, .topLeft, .topRight, .center],
               offsetX: ComponentKit.inch(1.5), offsetY: ComponentKit.inch(1.5))
        return b
    }

    /// A wheel turning about X at (y, z): tread with rounded shoulders, `width` wide, and a hub of the frame material.
    static func wheel(_ b: inout ComponentBuilder, _ name: String = "Wheel", y: String, z: String, d: String, w: String, hub: String? = nil, x: String = CX.zero) {
        let r = "(\(d)) / 2", ch = "(\(w)) * 0.18"
        b.slot(wheelMaterial) { b in
            b.turn(name, axis: .x, c: (y, z), base: "\(x) - (\(w)) / 2", [(CX.zero, CX.zero), ("\(r) - \(ch)", CX.zero), (r, ch), (r, "(\(w)) - \(ch)"), ("\(r) - \(ch)", w), (CX.zero, w)])
        }
        if let hub {
            b.slot("Finish Material") { b in
                b.rod("\(name) Hub", axis: .x, c: (y, z), r: "(\(hub)) / 2", from: "\(x) - (\(w)) / 2 - 0.001 m", to: "\(x) + (\(w)) / 2 + 0.001 m")
            }
        }
    }

    /// A fork straddling a wheel at (y, z): two side plates and a top bridge under the swivel.
    static func fork(_ b: inout ComponentBuilder, y: String, z: String, d: String, w: String, top: String = CX.mm(-6), t: String = CX.mm(3)) {
        let gap = "(\(w)) / 2 + 0.001 m"
        b.box("Fork Left", x: ("-(\(gap)) - \(t)", "-(\(gap))"), y: ("\(y) - (\(d)) * 0.28", "\(y) + (\(d)) * 0.28"), z: (z, top))
        b.box("Fork Right", x: (gap, "\(gap) + \(t)"), y: ("\(y) - (\(d)) * 0.28", "\(y) + (\(d)) * 0.28"), z: (z, top))
        b.box("Fork Bridge", x: ("-(\(gap)) - \(t)", "\(gap) + \(t)"), y: ("-(\(d)) * 0.28", "(\(d)) * 0.28"), z: ("\(top) - \(t)", top))
        b.rod("Axle", axis: .x, c: (y, z), r: CX.mm(3), from: "-(\(gap)) - \(t) - 0.001 m", to: "\(gap) + \(t) + 0.001 m", sides: 12)
    }

    /// A square top plate (`size`) with four screw holes at `spacing`, and its drill pattern.
    static func topPlate(_ b: inout ComponentBuilder, size: String, spacing: String, t: String = CX.mm(3), hole: String = CX.mm(4.5)) {
        b.plate("Top Plate", w: size, h: size, r: "(\(size)) * 0.06", z: ("-(\(t))", CX.zero))
        b.at(CBL.fine) { b in
            for (sx, sy) in [("-", "-"), ("", "-"), ("-", ""), ("", "")] {
                b.rod("Plate Hole \(sx)\(sy)", c: ("\(sx)(\(spacing)) / 2", "\(sy)(\(spacing)) / 2"), r: "(\(hole)) / 2", from: "-(\(t)) - 0.001 m", to: CX.mm(1), void: true, sides: 12)
            }
        }
        for (sx, sy) in [("-", "-"), ("", "-"), ("-", ""), ("", "")] {
            b.drill("Caster screw", x: "\(sx)(\(spacing)) / 2", y: "\(sy)(\(spacing)) / 2", diameter: "(\(hole)) * 0.7", depth: CX.mm(16))
        }
    }

    /// Plan outline (plate and swivel circle) and side outline (wheel) of a caster.
    static func casterSymbols(_ b: inout ComponentBuilder, plate: String, d: String, y: String = CX.zero, swivel: Bool = true) {
        b.symRect(.face, CBL.all, ("-(\(plate)) / 2", "-(\(plate)) / 2"), ("(\(plate)) / 2", "(\(plate)) / 2"))
        if swivel { b.symCircle(.face, CBL.mediumFine, r: "(\(d)) * 0.5 + abs(\(y))", dashed: true) }
        b.symCross(.face, CBL.coarse, s: "(\(plate)) * 0.3")
        b.symCircle(.side, CBL.all, c: ("-Height + (\(d)) / 2", y), r: "(\(d)) / 2")
        b.symLine(.side, CBL.coarse, (CX.zero, "-(\(plate)) / 2"), (CX.zero, "(\(plate)) / 2"))
    }

    // MARK: Casters

    static func fixedCaster() -> ComponentDefinition {
        var b = casterBuilder("Fixed Caster", "Plate Casters", "Rigid plate caster: the wheel runs straight, for the back corners of a cart or a long piece.", .zinc)
        b.tags("fixed caster", "rigid caster", "caster", "wheel", "plate", "50 mm", "75 mm", "100 mm")
        b.aliases("rigid castor", "fixed castor", "straight caster", "non-swivel caster", "plate caster")
        b.length("Wheel Diameter", ComponentKit.mm(75), min: ComponentKit.mm(40), max: ComponentKit.mm(125))
        b.length("Wheel Width", ComponentKit.mm(25))
        b.length("Plate Size", ComponentKit.mm(60))
        b.length("Screw Spacing", ComponentKit.mm(45), group: .manufacturing)
        b.length("Height", ComponentKit.mm(98))
        b.number("Load Rating", 110, unit: "lb", group: .data)
        let z = "-Height + Wheel Diameter / 2"
        topPlate(&b, size: "Plate Size", spacing: "Screw Spacing")
        fork(&b, y: CX.zero, z: z, d: "Wheel Diameter", w: "Wheel Width", top: CX.mm(-3))
        wheel(&b, y: CX.zero, z: z, d: "Wheel Diameter", w: "Wheel Width", hub: "Wheel Diameter * 0.45")
        casterSymbols(&b, plate: "Plate Size", d: "Wheel Diameter", swivel: false)
        b.type("Fixed Caster - 50 mm", ["Wheel Diameter": ComponentKit.mm(50), "Wheel Width": ComponentKit.mm(20), "Plate Size": ComponentKit.mm(50), "Screw Spacing": ComponentKit.mm(38),
                                        "Height": ComponentKit.mm(70)], numbers: ["Load Rating": 66], cost: 4.50, model: "FC-50")
        b.type("Fixed Caster - 75 mm", [:], cost: 6.50, model: "FC-75", isDefault: true)
        b.type("Fixed Caster - 100 mm", ["Wheel Diameter": ComponentKit.mm(100), "Wheel Width": ComponentKit.mm(30), "Plate Size": ComponentKit.mm(75), "Screw Spacing": ComponentKit.mm(55),
                                         "Height": ComponentKit.mm(128)], numbers: ["Load Rating": 176], cost: 9.00, model: "FC-100")
        return b.build()
    }

    /// FM5's Caster (swivel plate caster), upgraded: 40 and 100 mm wheels, a round wheel, the swivel race and axle at
    /// Fine, symbols and the plate's screws.
    static func casterUpgrade() -> ComponentDefinition {
        guard var b = ComponentBuilder(upgrading: FurnitureHardware.caster) else { return fixedCaster() }
        b.smoothCircles()
        b.tags("swivel caster", "caster", "wheel", "plate", "2\"", "3\"", "40 mm", "100 mm", "swivel")
        b.aliases("swivel castor", "castor", "furniture wheel", "plate caster", "swivel wheel", "rolling caster")
        b.at(CBL.fine) { b in
            b.rod("Swivel Race", r: "Plate Size * 0.32", from: CX.mm(-8), to: CX.mm(-4))
            b.rod("Axle", axis: .x, c: (CX.zero, "-Height + Wheel Diameter / 2"), r: CX.mm(3), from: "-Wheel Width / 2 - 0.004 m", to: "Wheel Width / 2 + 0.004 m", sides: 12)
        }
        b.symRect(.face, CBL.all, ("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2"))
        b.symCircle(.face, CBL.mediumFine, r: "Wheel Diameter * 0.5", dashed: true)
        b.symCross(.face, CBL.coarse, s: "Plate Size * 0.3")
        b.symCircle(.side, CBL.all, c: ("-Height + Wheel Diameter / 2", CX.zero), r: "Wheel Diameter / 2")
        for (sx, sy) in [("-", "-"), ("", "-"), ("-", ""), ("", "")] {
            b.drill("Caster screw", x: "\(sx)Screw Spacing / 2", y: "\(sy)Screw Spacing / 2", diameter: "Screw Hole Diameter", depth: CX.mm(16))
        }
        b.type("1 5/8\" Swivel", ["Wheel Diameter": ComponentKit.mm(40), "Wheel Width": ComponentKit.mm(18), "Plate Size": ComponentKit.inch(1.5), "Height": ComponentKit.mm(55),
                                  "Screw Hole Diameter": ComponentKit.mm(4), "Screw Spacing": ComponentKit.inch(1.125)],
               cost: 3.80, model: "CS-40S", description: "Swivel plate caster, 40 mm (1 5/8\") wheel")
        b.type("4\" Swivel", ["Wheel Diameter": ComponentKit.mm(100), "Wheel Width": ComponentKit.inch(1.25), "Plate Size": ComponentKit.inch(3.5), "Height": ComponentKit.inch(5),
                              "Screw Hole Diameter": ComponentKit.mm(6), "Screw Spacing": ComponentKit.inch(2.625)],
               cost: 11.50, model: "CS-4S", description: "Swivel plate caster, 4\" (100 mm) wheel")
        return b.build()
    }

    /// A swivel caster's body: top plate, swivel race, offset fork and wheel.
    static func swivelBody(_ b: inout ComponentBuilder, offset: String = "Wheel Diameter * 0.3") {
        let z = "-Height + Wheel Diameter / 2"
        topPlate(&b, size: "Plate Size", spacing: "Screw Spacing")
        b.rod("Swivel Race", r: "Plate Size * 0.35", from: CX.mm(-9), to: CX.mm(-3))
        fork(&b, y: offset, z: z, d: "Wheel Diameter", w: "Wheel Width", top: CX.mm(-9))
        wheel(&b, y: offset, z: z, d: "Wheel Diameter", w: "Wheel Width", hub: "Wheel Diameter * 0.45")
    }

    static func swivelParams(_ b: inout ComponentBuilder, wheel: Double, width: Double, plate: Double, spacing: Double, height: Double, load: Double) {
        b.length("Wheel Diameter", wheel, min: ComponentKit.mm(40), max: ComponentKit.mm(200))
        b.length("Wheel Width", width)
        b.length("Plate Size", plate)
        b.length("Screw Spacing", spacing, group: .manufacturing)
        b.length("Height", height)
        b.number("Load Rating", load, unit: "lb", group: .data)
    }

    static func lockingCaster() -> ComponentDefinition {
        var b = casterBuilder("Locking Caster", "Plate Casters", "Swivel caster with a foot brake: the pedal locks the wheel (Total Lock also stops the swivel).", .zinc, wheel: .rubber)
        b.tags("locking caster", "brake", "braked caster", "total lock", "swivel", "caster", "wheel")
        b.aliases("braked castor", "caster with brake", "lockable caster", "brake caster", "total lock caster")
        swivelParams(&b, wheel: ComponentKit.mm(75), width: ComponentKit.mm(25), plate: ComponentKit.mm(60), spacing: ComponentKit.mm(45), height: ComponentKit.mm(105), load: 110)
        b.flag("Total Lock", false, instance: false)
        b.flag("Locked", false, instance: true)
        swivelBody(&b)
        b.box("Brake Pedal", x: ("Wheel Width / 2 + 0.004 m", "Wheel Width / 2 + 0.03 m"), y: ("Wheel Diameter * 0.3 + Wheel Diameter * 0.25", "Wheel Diameter * 0.3 + Wheel Diameter * 0.45"),
              z: ("-Height + Wheel Diameter * if(Locked, 0.55, 0.7)", "-Height + Wheel Diameter * if(Locked, 0.62, 0.77)"))
        b.shown(by: "Total Lock") { b in
            b.rod("Swivel Lock Ring", r: "Plate Size * 0.38", from: CX.mm(-12), to: CX.mm(-9))
        }
        casterSymbols(&b, plate: "Plate Size", d: "Wheel Diameter", y: "Wheel Diameter * 0.3")
        b.type("Locking Caster - 50 mm", ["Wheel Diameter": ComponentKit.mm(50), "Wheel Width": ComponentKit.mm(20), "Plate Size": ComponentKit.mm(50), "Screw Spacing": ComponentKit.mm(38),
                                          "Height": ComponentKit.mm(75)], flags: ["Total Lock": false], numbers: ["Load Rating": 66], cost: 6.50, model: "LC-50")
        b.type("Locking Caster - 75 mm", [:], flags: ["Total Lock": false], cost: 8.50, model: "LC-75", isDefault: true)
        b.type("Locking Caster - 100 mm Total Lock", ["Wheel Diameter": ComponentKit.mm(100), "Wheel Width": ComponentKit.mm(30), "Plate Size": ComponentKit.mm(75),
                                                      "Screw Spacing": ComponentKit.mm(55), "Height": ComponentKit.mm(130)], flags: ["Total Lock": true], numbers: ["Load Rating": 176],
               cost: 13.00, model: "LC-100T")
        return b.build()
    }

    static func twinWheelCaster() -> ComponentDefinition {
        var b = casterBuilder("Twin-Wheel Caster", "Stem Casters", "Twin-wheel (dual) caster: two wheels under a hood on a threaded stem, for chairs and light furniture.", .blackPlastic, wheel: .blackPlastic)
        b.tags("twin wheel caster", "dual wheel", "hooded", "stem caster", "chair caster", "40 mm", "50 mm", "m8", "m10")
        b.aliases("double wheel castor", "twin castor", "chair wheel", "hooded caster", "office chair caster", "stem castor")
        b.text("Stem Thread", "M8")
        b.length("Wheel Diameter", ComponentKit.mm(50), min: ComponentKit.mm(40), max: ComponentKit.mm(75))
        b.length("Wheel Width", ComponentKit.mm(12))
        b.length("Stem Diameter", ComponentKit.mm(8))
        b.length("Stem Length", ComponentKit.mm(15))
        b.length("Height", ComponentKit.mm(62))
        b.number("Load Rating", 88, unit: "lb", group: .data)
        b.flag("Brake", false, instance: false)
        let z = "-Height + Wheel Diameter / 2", y = "Wheel Diameter * 0.2"
        b.rod("Stem", r: "Stem Diameter / 2", from: CX.zero, to: "Stem Length", sides: 16)
        b.rod("Stem Collar", r: "Stem Diameter", from: CX.mm(-4), to: CX.zero)
        b.box("Hood", x: ("-Wheel Width - 0.005 m", "Wheel Width + 0.005 m"), y: ("\(y) - Wheel Diameter * 0.45", "\(y) + Wheel Diameter * 0.45"), z: ("\(z) + Wheel Diameter * 0.05", CX.mm(-4)))
        wheel(&b, "Wheel A", y: y, z: z, d: "Wheel Diameter", w: "Wheel Width", x: "-Wheel Width / 2 - 0.006 m")
        wheel(&b, "Wheel B", y: y, z: z, d: "Wheel Diameter", w: "Wheel Width", x: "Wheel Width / 2 + 0.006 m")
        b.shown(by: "Brake") { b in
            b.box("Brake Tab", x: ("-Wheel Width", "Wheel Width"), y: ("\(y) + Wheel Diameter * 0.45", "\(y) + Wheel Diameter * 0.6"), z: ("\(z)", "\(z) + 0.006 m"))
        }
        b.symRect(.face, CBL.all, ("-Wheel Width - 0.005 m", "\(y) - Wheel Diameter * 0.5"), ("Wheel Width + 0.005 m", "\(y) + Wheel Diameter * 0.5"))
        b.symCircle(.face, CBL.mediumFine, r: "Wheel Diameter * 0.7", dashed: true)
        b.symCircle(.side, CBL.all, c: (z, y), r: "Wheel Diameter / 2")
        b.drill("Stem socket", x: CX.zero, y: CX.zero, diameter: "Stem Diameter + 0.003 m", depth: "Stem Length + 0.002 m")
        b.type("Twin-Wheel Caster - 40 mm M8", ["Wheel Diameter": ComponentKit.mm(40), "Height": ComponentKit.mm(52), "Wheel Width": ComponentKit.mm(10)], flags: ["Brake": false],
               numbers: ["Load Rating": 66], cost: 2.20, model: "TWC-40M8")
        b.type("Twin-Wheel Caster - 50 mm M8", [:], flags: ["Brake": false], cost: 2.80, model: "TWC-50M8", isDefault: true)
        b.type("Twin-Wheel Caster - 50 mm M10 Brake", ["Stem Diameter": ComponentKit.mm(10)], flags: ["Brake": true], texts: ["Stem Thread": "M10"], cost: 3.60, model: "TWC-50M10B")
        return b.build()
    }

    static func heavyDutyCaster() -> ComponentDefinition {
        var b = casterBuilder("Heavy-Duty Caster", "Plate Casters", "Heavy-duty swivel caster: a thick steel plate, a double ball race and a polyurethane wheel on an aluminium core.", .steel,
                              wheel: .polyurethaneRed)
        b.tags("heavy duty caster", "industrial", "swivel", "polyurethane", "workbench", "100 mm", "125 mm", "150 mm")
        b.aliases("heavy castor", "industrial caster", "workbench caster", "load caster", "pu caster", "heavy wheel")
        swivelParams(&b, wheel: ComponentKit.mm(125), width: ComponentKit.mm(38), plate: ComponentKit.mm(100), spacing: ComponentKit.mm(75), height: ComponentKit.mm(165), load: 550)
        b.length("Plate Thickness", ComponentKit.mm(5))
        let z = "-Height + Wheel Diameter / 2", off = "Wheel Diameter * 0.3"
        topPlate(&b, size: "Plate Size", spacing: "Screw Spacing", t: "Plate Thickness", hole: CX.mm(9))
        b.rod("Swivel Race", r: "Plate Size * 0.4", from: "-Plate Thickness - 0.01 m", to: "-Plate Thickness")
        fork(&b, y: off, z: z, d: "Wheel Diameter", w: "Wheel Width", top: "-Plate Thickness - 0.01 m", t: CX.mm(5))
        wheel(&b, y: off, z: z, d: "Wheel Diameter", w: "Wheel Width", hub: "Wheel Diameter * 0.6")
        casterSymbols(&b, plate: "Plate Size", d: "Wheel Diameter", y: off)
        b.type("Heavy-Duty Caster - 100 mm", ["Wheel Diameter": ComponentKit.mm(100), "Wheel Width": ComponentKit.mm(32), "Plate Size": ComponentKit.mm(90), "Screw Spacing": ComponentKit.mm(65),
                                              "Height": ComponentKit.mm(135)], numbers: ["Load Rating": 440], cost: 16.00, model: "HDC-100")
        b.type("Heavy-Duty Caster - 125 mm", [:], cost: 21.00, model: "HDC-125", isDefault: true)
        b.type("Heavy-Duty Caster - 150 mm", ["Wheel Diameter": ComponentKit.mm(150), "Wheel Width": ComponentKit.mm(45), "Plate Size": ComponentKit.mm(115), "Screw Spacing": ComponentKit.mm(85),
                                              "Height": ComponentKit.mm(195)], numbers: ["Load Rating": 770], cost: 28.00, model: "HDC-150")
        return b.build()
    }

    static func concealedCaster() -> ComponentDefinition {
        var b = casterBuilder("Concealed Caster", "Concealed Casters", "Low-profile concealed caster: the wheel turns inside a domed housing, so only its bottom shows under the piece.", .blackPlastic,
                              wheel: .greyPlastic)
        b.tags("concealed caster", "hidden caster", "low profile", "furniture caster", "hooded", "sofa", "bed")
        b.aliases("hidden castor", "low profile caster", "domed caster", "sofa caster", "invisible wheel", "covered caster")
        b.length("Housing Diameter", ComponentKit.mm(55))
        b.length("Wheel Diameter", ComponentKit.mm(32))
        b.length("Wheel Width", ComponentKit.mm(14))
        b.length("Height", ComponentKit.mm(32))
        b.number("Load Rating", 88, unit: "lb", group: .data)
        b.turn("Housing", base: "-Height + 0.004 m", [(CX.zero, CX.zero), ("Housing Diameter / 2", CX.zero), ("Housing Diameter / 2", "Height * 0.35"),
                                                       ("Housing Diameter * 0.4", "Height - 0.004 m"), (CX.zero, "Height - 0.004 m")])
        b.rod("Wheel Opening", r: "Wheel Diameter * 0.55", from: "-Height", to: "-Height + Wheel Diameter * 0.7", void: true)
        wheel(&b, y: CX.zero, z: "-Height + Wheel Diameter / 2", d: "Wheel Diameter", w: "Wheel Width")
        b.symCircle(.face, CBL.all, r: "Housing Diameter / 2")
        b.symCross(.face, CBL.coarse, s: "Housing Diameter * 0.2")
        b.symRect(.side, CBL.coarse, ("-Height", "-Housing Diameter / 2"), (CX.zero, "Housing Diameter / 2"))
        b.symCircle(.side, CBL.mediumFine, c: ("-Height + Wheel Diameter / 2", CX.zero), r: "Wheel Diameter / 2", dashed: true)
        for k in 0..<3 {
            let a = Double(k) * 2 * .pi / 3
            b.drill("Housing screw", x: "Housing Diameter * \(LX.num(0.36 * cos(a)))", y: "Housing Diameter * \(LX.num(0.36 * sin(a)))", diameter: CX.mm(3), depth: CX.mm(13))
        }
        b.type("Concealed Caster - 40 mm", ["Housing Diameter": ComponentKit.mm(40), "Wheel Diameter": ComponentKit.mm(24), "Height": ComponentKit.mm(25)], numbers: ["Load Rating": 55],
               cost: 2.40, model: "CCS-40")
        b.type("Concealed Caster - 55 mm", [:], cost: 3.20, model: "CCS-55", isDefault: true)
        return b.build()
    }

    static func furnitureRoller() -> ComponentDefinition {
        var b = casterBuilder("Furniture Roller", "Rollers", "Furniture roller: a low steel frame with two wide rollers, for heavy pieces that move straight (beds, cabinets, plinths).", .zinc,
                              wheel: .nylon)
        b.tags("furniture roller", "roller", "low profile", "heavy", "straight", "bed roller", "plinth roller")
        b.aliases("roller wheel", "cabinet roller", "bed roller", "skate roller", "track roller", "flat roller")
        b.length("Frame Length", ComponentKit.mm(80))
        b.length("Frame Width", ComponentKit.mm(40))
        b.length("Roller Diameter", ComponentKit.mm(22))
        b.length("Roller Width", ComponentKit.mm(30))
        b.length("Height", ComponentKit.mm(28))
        b.number("Load Rating", 220, unit: "lb", group: .data)
        b.box("Frame", x: ("-Frame Width / 2", "Frame Width / 2"), y: ("-Frame Length / 2", "Frame Length / 2"), z: ("-Height + Roller Diameter * 0.6", CX.zero))
        for (k, y) in ["-Frame Length * 0.25", "Frame Length * 0.25"].enumerated() {
            wheel(&b, "Roller \(k + 1)", y: y, z: "-Height + Roller Diameter / 2", d: "Roller Diameter", w: "Roller Width")
        }
        b.symRect(.face, CBL.all, ("-Frame Width / 2", "-Frame Length / 2"), ("Frame Width / 2", "Frame Length / 2"))
        b.symLine(.face, CBL.coarse, (CX.zero, "-Frame Length / 2"), (CX.zero, "Frame Length / 2"))
        b.symCircle(.side, CBL.all, c: ("-Height + Roller Diameter / 2", "-Frame Length * 0.25"), r: "Roller Diameter / 2")
        b.symCircle(.side, CBL.all, c: ("-Height + Roller Diameter / 2", "Frame Length * 0.25"), r: "Roller Diameter / 2")
        for y in ["-Frame Length * 0.42", "Frame Length * 0.42"] { b.drill("Roller screw", x: CX.zero, y: y, diameter: CX.mm(3.5), depth: CX.mm(13)) }
        b.type("Furniture Roller - 80 mm", [:], cost: 4.20, model: "FR-80", isDefault: true)
        b.type("Furniture Roller - 120 mm Heavy", ["Frame Length": ComponentKit.mm(120), "Frame Width": ComponentKit.mm(50), "Roller Diameter": ComponentKit.mm(30),
                                                    "Roller Width": ComponentKit.mm(40), "Height": ComponentKit.mm(36)], numbers: ["Load Rating": 440], cost: 6.80, model: "FR-120H")
        return b.build()
    }

    /// A loose wheel (wheel only, with its axle bore): rubber or polyurethane tread on a core.
    static func looseWheel(_ name: String, _ description: String, tread: ComponentFinish, core: ComponentFinish, tags: [String], aliases: [String]) -> ComponentBuilder {
        var b = ComponentBuilder(name, .mobility, "Wheels", description, frame: .plan)
        b.hardwareKind(.caster)
        b.material(wheelMaterial, tread)
        b.material("Finish Material", core)
        for t in tags { b.tags(t) }
        for a in aliases { b.aliases(a) }
        b.length("Wheel Diameter", ComponentKit.mm(75), min: ComponentKit.mm(40), max: ComponentKit.mm(200))
        b.length("Wheel Width", ComponentKit.mm(25))
        b.length("Core Diameter", ComponentKit.mm(50))
        b.length("Bore Diameter", ComponentKit.mm(8))
        b.length("Hub Length", ComponentKit.mm(30))
        b.length("Height", 0, formula: "Wheel Diameter")
        b.number("Load Rating", 110, unit: "lb", group: .data)
        b.host([.leg, .bottom, .floor], faces: [.bottom], align: .center)
        let z = "-Wheel Diameter / 2"
        b.slot(wheelMaterial) { b in
            b.turn("Tread", axis: .x, c: (CX.zero, z), base: "-Wheel Width / 2", [("Core Diameter / 2", CX.zero), ("Wheel Diameter / 2 - Wheel Width * 0.18", CX.zero),
                                                                            ("Wheel Diameter / 2", "Wheel Width * 0.18"), ("Wheel Diameter / 2", "Wheel Width * 0.82"),
                                                                            ("Wheel Diameter / 2 - Wheel Width * 0.18", "Wheel Width"), ("Core Diameter / 2", "Wheel Width")])
        }
        b.slot("Finish Material") { b in
            b.turn("Core", axis: .x, c: (CX.zero, z), base: "-Hub Length / 2", [("Bore Diameter / 2", CX.zero), ("Bore Diameter", CX.zero), ("Bore Diameter", "(Hub Length - Wheel Width) / 2"),
                                                                           ("Core Diameter / 2", "(Hub Length - Wheel Width) / 2"), ("Core Diameter / 2", "(Hub Length + Wheel Width) / 2"),
                                                                           ("Bore Diameter", "(Hub Length + Wheel Width) / 2"), ("Bore Diameter", "Hub Length"), ("Bore Diameter / 2", "Hub Length")])
        }
        b.symRect(.face, CBL.all, ("-Wheel Width / 2", "-Wheel Diameter / 2"), ("Wheel Width / 2", "Wheel Diameter / 2"))
        b.symCircle(.side, CBL.all, c: (z, CX.zero), r: "Wheel Diameter / 2")
        b.symCircle(.side, CBL.mediumFine, c: (z, CX.zero), r: "Core Diameter / 2")
        b.symCircle(.side, CBL.coarse, c: (z, CX.zero), r: "Bore Diameter / 2")
        return b
    }

    static func rubberWheel() -> ComponentDefinition {
        var b = looseWheel("Rubber Wheel", "Replacement wheel: a soft rubber tread on a plastic core, with a plain axle bore.", tread: .rubber, core: .greyPlastic,
                           tags: ["rubber wheel", "wheel", "replacement", "soft tread", "quiet", "50 mm", "75 mm", "100 mm"],
                           aliases: ["caster wheel", "replacement wheel", "soft wheel", "rubber tyre wheel", "trolley wheel"])
        b.type("Rubber Wheel - 50 mm", ["Wheel Diameter": ComponentKit.mm(50), "Wheel Width": ComponentKit.mm(20), "Core Diameter": ComponentKit.mm(32), "Hub Length": ComponentKit.mm(24),
                                        "Bore Diameter": ComponentKit.mm(6)], numbers: ["Load Rating": 66], cost: 1.80, model: "RW-50")
        b.type("Rubber Wheel - 75 mm", [:], cost: 2.40, model: "RW-75", isDefault: true)
        b.type("Rubber Wheel - 100 mm", ["Wheel Diameter": ComponentKit.mm(100), "Wheel Width": ComponentKit.mm(30), "Core Diameter": ComponentKit.mm(65), "Hub Length": ComponentKit.mm(36),
                                         "Bore Diameter": ComponentKit.mm(10)], numbers: ["Load Rating": 176], cost: 3.60, model: "RW-100")
        return b.build()
    }

    static func polyurethaneWheel() -> ComponentDefinition {
        var b = looseWheel("Polyurethane Wheel", "Replacement wheel: a polyurethane tread bonded to a nylon or aluminium core, with a ball bearing in the bore.", tread: .polyurethaneRed,
                           core: .aluminum, tags: ["polyurethane wheel", "pu wheel", "wheel", "non-marking", "ball bearing", "75 mm", "100 mm", "125 mm"],
                           aliases: ["pu wheel", "urethane wheel", "non marking wheel", "industrial wheel", "bearing wheel"])
        b.flag("Ball Bearing", true, instance: false)
        b.shown(by: "Ball Bearing") { b in
            b.at(CBL.fine) { b in
                b.slot("Finish Material") { b in
                    b.rod("Bearing Race", axis: .x, c: (CX.zero, "-Wheel Diameter / 2"), r: "Bore Diameter * 0.9", from: "-Hub Length / 2 - 0.0005 m", to: "-Hub Length / 2 + 0.002 m")
                }
            }
        }
        b.type("PU Wheel - 75 mm", ["Core Diameter": ComponentKit.mm(55)], flags: ["Ball Bearing": true], numbers: ["Load Rating": 220], cost: 4.20, model: "PUW-75")
        b.type("PU Wheel - 100 mm", ["Wheel Diameter": ComponentKit.mm(100), "Wheel Width": ComponentKit.mm(32), "Core Diameter": ComponentKit.mm(75), "Hub Length": ComponentKit.mm(40),
                                     "Bore Diameter": ComponentKit.mm(12)], flags: ["Ball Bearing": true], numbers: ["Load Rating": 330], cost: 6.00, model: "PUW-100", isDefault: true)
        b.type("PU Wheel - 125 mm", ["Wheel Diameter": ComponentKit.mm(125), "Wheel Width": ComponentKit.mm(38), "Core Diameter": ComponentKit.mm(95), "Hub Length": ComponentKit.mm(45),
                                     "Bore Diameter": ComponentKit.mm(15)], flags: ["Ball Bearing": true], numbers: ["Load Rating": 550], cost: 8.50, model: "PUW-125")
        return b.build()
    }

    static func ballCaster() -> ComponentDefinition {
        var b = casterBuilder("Ball Caster", "Ball Casters", "Ball caster: a steel ball turning on small balls in a flanged socket, moving any way (light carts, drawers, flaps).", .chrome, wheel: .chrome)
        b.tags("ball caster", "ball transfer", "omnidirectional", "steel ball", "flange", "low profile")
        b.aliases("ball transfer unit", "ball castor", "omni wheel", "ball roller", "spherical caster")
        b.length("Ball Diameter", ComponentKit.mm(25))
        b.length("Flange Diameter", ComponentKit.mm(40))
        b.length("Body Diameter", ComponentKit.mm(32))
        b.length("Body Depth", ComponentKit.mm(14))
        b.length("Height", ComponentKit.mm(20))
        b.number("Load Rating", 66, unit: "lb", group: .data)
        b.rod("Flange", r: "Flange Diameter / 2", from: CX.mm(-3), to: CX.zero)
        b.rod("Body", r: "Body Diameter / 2", from: "-Height + Ball Diameter * 0.5", to: CX.mm(-3))
        b.rod("Insert", r: "Body Diameter / 2 - 0.002 m", from: CX.zero, to: "Body Depth")
        let ball = (0...16).map { k -> (String, String) in
            let a = -Double.pi / 2 + Double.pi * Double(k) / 16
            return ("Ball Diameter / 2 * \(LX.num(cos(a)))", "Ball Diameter / 2 * \(LX.num(1 + sin(a)))")
        }
        b.slot(wheelMaterial) { b in b.turn("Ball", base: "-Height", [(CX.zero, CX.zero)] + ball.dropFirst().dropLast() + [(CX.zero, "Ball Diameter")]) }
        b.symCircle(.face, CBL.all, r: "Flange Diameter / 2")
        b.symCircle(.face, CBL.mediumFine, r: "Ball Diameter / 2", dashed: true)
        b.symCross(.face, CBL.coarse, s: "Ball Diameter * 0.3")
        b.symCircle(.side, CBL.all, c: ("-Height + Ball Diameter / 2", CX.zero), r: "Ball Diameter / 2")
        b.drill("Ball caster socket", x: CX.zero, y: CX.zero, diameter: "Body Diameter", depth: "Body Depth")
        b.type("Ball Caster - 16 mm", ["Ball Diameter": ComponentKit.mm(16), "Flange Diameter": ComponentKit.mm(28), "Body Diameter": ComponentKit.mm(22), "Body Depth": ComponentKit.mm(10),
                                       "Height": ComponentKit.mm(13)], numbers: ["Load Rating": 33], cost: 2.20, model: "BC-16")
        b.type("Ball Caster - 25 mm", [:], cost: 3.40, model: "BC-25", isDefault: true)
        return b.build()
    }

    static func retractableCaster() -> ComponentDefinition {
        var b = casterBuilder("Retractable Caster", "Retractable Casters", "Retractable caster: a lever lowers the wheel to roll the piece and lifts it so the piece stands on its feet.", .zinc)
        b.tags("retractable caster", "lever caster", "lift caster", "workbench caster", "retracting", "foot lever")
        b.aliases("retracting castor", "lever caster", "drop down caster", "workbench wheel", "lift wheel", "spring caster")
        swivelParams(&b, wheel: ComponentKit.mm(50), width: ComponentKit.mm(20), plate: ComponentKit.mm(70), spacing: ComponentKit.mm(55), height: ComponentKit.mm(75), load: 220)
        b.flag("Retracted", false, instance: true)
        b.length("Lift", ComponentKit.mm(15))
        let z = "-Height + Wheel Diameter / 2 + if(Retracted, Lift, 0 m)"
        topPlate(&b, size: "Plate Size", spacing: "Screw Spacing")
        b.box("Housing", x: ("-Plate Size / 2", "Plate Size / 2"), y: ("-Plate Size * 0.3", "Plate Size * 0.3"), z: ("-Height * 0.45", CX.mm(-3)))
        fork(&b, y: CX.zero, z: z, d: "Wheel Diameter", w: "Wheel Width", top: "-Height * 0.45")
        wheel(&b, y: CX.zero, z: z, d: "Wheel Diameter", w: "Wheel Width", hub: "Wheel Diameter * 0.45")
        b.box("Lever", x: ("Plate Size / 2", "Plate Size / 2 + 0.06 m"), y: (CX.mm(-6), CX.mm(6)),
              z: ("-Height * 0.3 - if(Retracted, 0.012 m, 0 m)", "-Height * 0.3 + 0.006 m - if(Retracted, 0.012 m, 0 m)"))
        casterSymbols(&b, plate: "Plate Size", d: "Wheel Diameter", swivel: false)
        b.symLine(.face, CBL.mediumFine, ("Plate Size / 2", CX.zero), ("Plate Size / 2 + 0.06 m", CX.zero))
        b.type("Retractable Caster - 50 mm", [:], cost: 12.00, model: "RC-50", isDefault: true)
        b.type("Retractable Caster - 75 mm", ["Wheel Diameter": ComponentKit.mm(75), "Wheel Width": ComponentKit.mm(25), "Plate Size": ComponentKit.mm(85), "Screw Spacing": ComponentKit.mm(65),
                                              "Height": ComponentKit.mm(102), "Lift": ComponentKit.mm(20)], numbers: ["Load Rating": 330], cost: 16.00, model: "RC-75")
        return b.build()
    }

    static func levelingCaster() -> ComponentDefinition {
        var b = casterBuilder("Leveling Caster", "Leveling Casters", "Leveling caster: a swivel caster with a screw-down leveling pad beside the wheel, to roll the piece and then fix it level.", .steel,
                              wheel: .nylon)
        b.tags("leveling caster", "leveler caster", "machine caster", "pad", "adjustable", "swivel", "fixed")
        b.aliases("levelling castor", "leveling castor", "caster with leveler", "machine leveling caster", "foot master caster")
        swivelParams(&b, wheel: ComponentKit.mm(60), width: ComponentKit.mm(30), plate: ComponentKit.mm(80), spacing: ComponentKit.mm(60), height: ComponentKit.mm(90), load: 440)
        b.length("Pad Diameter", ComponentKit.mm(60))
        b.length("Pad Down", 0, instance: true, group: .placement, min: 0, max: ComponentKit.mm(15))
        b.material("Pad Material", .rubber)
        topPlate(&b, size: "Plate Size", spacing: "Screw Spacing")
        b.box("Body", x: ("-Plate Size / 2", "Plate Size / 2"), y: ("-Plate Size / 2", "Plate Size / 2"), z: ("-Height * 0.35", CX.mm(-3)))
        wheel(&b, "Wheel A", y: CX.zero, z: "-Height + Wheel Diameter / 2", d: "Wheel Diameter", w: "Wheel Width / 2", x: "-Plate Size * 0.3")
        wheel(&b, "Wheel B", y: CX.zero, z: "-Height + Wheel Diameter / 2", d: "Wheel Diameter", w: "Wheel Width / 2", x: "Plate Size * 0.3")
        b.rod("Pad Screw", r: CX.mm(6), from: "-Height + 0.01 m - Pad Down", to: "-Height * 0.35", sides: 12)
        b.slot("Pad Material") { b in b.rod("Pad", r: "Pad Diameter / 2", from: "-Height + 0.004 m - Pad Down", to: "-Height + 0.012 m - Pad Down") }
        b.symRect(.face, CBL.all, ("-Plate Size / 2", "-Plate Size / 2"), ("Plate Size / 2", "Plate Size / 2"))
        b.symCircle(.face, CBL.mediumFine, r: "Pad Diameter / 2", dashed: true)
        b.symCross(.face, CBL.coarse, s: "Plate Size * 0.3")
        b.symCircle(.side, CBL.all, c: ("-Height + Wheel Diameter / 2", CX.zero), r: "Wheel Diameter / 2")
        b.type("Leveling Caster - 60 mm", [:], cost: 18.00, model: "LVC-60", isDefault: true)
        b.type("Leveling Caster - 80 mm", ["Wheel Diameter": ComponentKit.mm(80), "Plate Size": ComponentKit.mm(100), "Screw Spacing": ComponentKit.mm(76), "Height": ComponentKit.mm(115),
                                           "Pad Diameter": ComponentKit.mm(80)], numbers: ["Load Rating": 880], cost: 26.00, model: "LVC-80")
        return b.build()
    }

    // MARK: Glides, pads and protectors

    /// A foot item under a leg or a bottom: plan frame, under the leg's foot.
    static func footBuilder(_ name: String, _ sub: String, _ description: String, _ finish: ComponentFinish) -> ComponentBuilder {
        var b = ComponentBuilder(name, .mobility, sub, description, frame: .plan)
        b.hardwareKind(.glide)
        b.material("Finish Material", finish)
        b.host([.leg, .bottom, .plinth], faces: [.bottom], align: .center, alignments: [.center, .bottomLeft, .bottomRight, .topLeft, .topRight])
        return b
    }

    static func slidingGlide() -> ComponentDefinition {
        var b = footBuilder("Sliding Furniture Glide", "Glides", "Sliding glide: a PTFE (low-friction) pad on a cushioned base, screwed or nailed under a leg so heavy pieces slide on carpet or hard floors.",
                            .whitePlastic)
        b.tags("sliding glide", "ptfe", "teflon", "slider", "furniture slider", "carpet", "screw-on")
        b.aliases("furniture slider", "ptfe glide", "slide glide", "easy glide", "furniture mover pad", "screw-on glide")
        b.material("Base Material", .greyPlastic)
        b.length("Diameter", ComponentKit.mm(30))
        b.length("Thickness", ComponentKit.mm(6))
        b.flag("Square", false, instance: false)
        b.flag("Round", true, formula: "not(Square)")
        b.slot("Base Material") { b in
            b.shown(by: "Round") { b in b.rod("Base", r: "Diameter / 2", from: "-Thickness * 0.6", to: CX.zero) }
            b.shown(by: "Square") { b in b.plate("Base", w: "Diameter", h: "Diameter", r: "Diameter * 0.1", z: ("-Thickness * 0.6", CX.zero)) }
        }
        b.shown(by: "Round") { b in
            b.turn("Glide Pad", base: "-Thickness", [(CX.zero, CX.zero), ("Diameter / 2 - 0.002 m", CX.zero), ("Diameter / 2", "Thickness * 0.2"), ("Diameter / 2", "Thickness * 0.4"),
                                                     (CX.zero, "Thickness * 0.4")])
        }
        b.shown(by: "Square") { b in b.plate("Glide Pad", w: "Diameter", h: "Diameter", r: "Diameter * 0.12", z: ("-Thickness", "-Thickness * 0.6")) }
        b.at(CBL.fine) { b in b.rod("Screw Recess", r: CX.mm(4), from: "-Thickness - 0.0005 m", to: "-Thickness * 0.5", void: true, sides: 16) }
        b.symCircle(.face, CBL.all, r: "Diameter / 2")
        b.symCross(.face, CBL.coarse, s: "Diameter * 0.2")
        b.symRect(.side, CBL.coarse, ("-Thickness", "-Diameter / 2"), (CX.zero, "Diameter / 2"))
        b.drill("Glide screw", x: CX.zero, y: CX.zero, diameter: CX.mm(3), depth: CX.mm(13))
        b.type("Sliding Glide - 25 mm", ["Diameter": ComponentKit.mm(25), "Thickness": ComponentKit.mm(5)], flags: ["Square": false], cost: 0.40, model: "SG-25")
        b.type("Sliding Glide - 30 mm", [:], flags: ["Square": false], cost: 0.50, model: "SG-30", isDefault: true)
        b.type("Sliding Glide - 40 mm Square", ["Diameter": ComponentKit.mm(40), "Thickness": ComponentKit.mm(7)], flags: ["Square": true], cost: 0.70, model: "SG-40S")
        return b.build()
    }

    static func feltPad() -> ComponentDefinition {
        var b = footBuilder("Felt Pad", "Pads", "Self-adhesive felt pad under a leg or a foot, protecting floors and quieting pieces that move.", .felt)
        b.tags("felt pad", "felt", "adhesive", "floor protector", "pad", "self-adhesive", "chair pad")
        b.aliases("felt glide", "felt foot", "furniture pad", "chair leg pad", "sticky felt", "floor saver")
        b.length("Diameter", ComponentKit.inch(1))
        b.length("Thickness", ComponentKit.mm(5))
        b.flag("Square", false, instance: false)
        b.flag("Round", true, formula: "not(Square)")
        b.shown(by: "Round") { b in b.rod("Pad", r: "Diameter / 2", from: "-Thickness", to: CX.zero) }
        b.shown(by: "Square") { b in b.plate("Pad", w: "Diameter", h: "Diameter", r: "Diameter * 0.08", z: ("-Thickness", CX.zero)) }
        b.symCircle(.face, CBL.all, r: "Diameter / 2")
        b.symRect(.side, CBL.coarse, ("-Thickness", "-Diameter / 2"), (CX.zero, "Diameter / 2"))
        b.type("Felt Pad - 3/4\"", ["Diameter": ComponentKit.inch(0.75)], flags: ["Square": false], cost: 0.08, model: "FP-34")
        b.type("Felt Pad - 1\"", [:], flags: ["Square": false], cost: 0.10, model: "FP-1", isDefault: true)
        b.type("Felt Pad - 1 1/2\" Square", ["Diameter": ComponentKit.inch(1.5)], flags: ["Square": true], cost: 0.15, model: "FP-15S")
        return b.build()
    }

    static func nylonGlide() -> ComponentDefinition {
        var b = footBuilder("Nylon Glide", "Glides", "Nail-in nylon glide: a domed nylon button with a steel nail (or a screw), under chair and table legs.", .nylon)
        b.tags("nylon glide", "nail-in glide", "button glide", "dome", "chair glide", "table glide")
        b.aliases("nail glide", "chair glide", "dome glide", "furniture button", "tack glide", "nail-on glide")
        b.material("Nail Material", .steel)
        b.length("Diameter", ComponentKit.mm(20))
        b.length("Height", ComponentKit.mm(6))
        b.length("Nail Length", ComponentKit.mm(12))
        b.flag("Screw", false, instance: false)
        b.turn("Glide", base: "-Height", [(CX.zero, CX.zero), ("Diameter * 0.3", CX.zero), ("Diameter * 0.45", "Height * 0.35"), ("Diameter / 2", "Height * 0.8"),
                                           ("Diameter / 2", "Height"), (CX.zero, "Height")])
        b.slot("Nail Material") { b in b.rod("Nail", r: CX.mm(1.2), from: CX.zero, to: "Nail Length", sides: 10) }
        b.symCircle(.face, CBL.all, r: "Diameter / 2")
        b.symCircle(.face, CBL.mediumFine, r: "Diameter * 0.3", dashed: true)
        b.symRect(.side, CBL.coarse, ("-Height", "-Diameter / 2"), (CX.zero, "Diameter / 2"))
        b.drill("Glide nail pilot", x: CX.zero, y: CX.zero, diameter: CX.mm(2), depth: "Nail Length")
        b.type("Nylon Glide - 16 mm", ["Diameter": ComponentKit.mm(16), "Height": ComponentKit.mm(5)], flags: ["Screw": false], cost: 0.06, model: "NG-16")
        b.type("Nylon Glide - 20 mm", [:], flags: ["Screw": false], cost: 0.08, model: "NG-20", isDefault: true)
        b.type("Nylon Glide - 25 mm Screw-In", ["Diameter": ComponentKit.mm(25), "Height": ComponentKit.mm(7), "Nail Length": ComponentKit.mm(16)], flags: ["Screw": true], cost: 0.12, model: "NG-25S")
        return b.build()
    }

    static func floorProtector() -> ComponentDefinition {
        var b = footBuilder("Floor Protector", "Pads", "Floor protector cup: a rubber cup the leg or a caster stands in, so it doesn't mark or slide.", .rubber)
        b.tags("floor protector", "caster cup", "furniture cup", "rubber", "anti-slip", "piano cup")
        b.aliases("caster cup", "furniture coaster", "leg cup", "anti slip cup", "bed riser cup", "piano coaster")
        b.length("Outer Diameter", ComponentKit.inch(2.5))
        b.length("Inner Diameter", ComponentKit.inch(1.875))
        b.length("Height", ComponentKit.inch(0.5))
        b.length("Base Thickness", ComponentKit.inch(0.1875))
        b.host([.leg, .bottom, .floor], faces: [.bottom], align: .center)
        b.turn("Cup", base: "-Base Thickness", [(CX.zero, CX.zero), ("Outer Diameter / 2", CX.zero), ("Outer Diameter / 2", "Height * 0.7"), ("Outer Diameter / 2 - 0.003 m", "Height"),
                                                  ("Inner Diameter / 2", "Height"), ("Inner Diameter / 2", "Base Thickness"), (CX.zero, "Base Thickness")])
        b.symCircle(.face, CBL.all, r: "Outer Diameter / 2")
        b.symCircle(.face, CBL.all, r: "Inner Diameter / 2")
        b.symRect(.side, CBL.coarse, ("-Base Thickness", "-Outer Diameter / 2"), ("Height - Base Thickness", "Outer Diameter / 2"))
        b.type("Floor Protector - 2\"", ["Outer Diameter": ComponentKit.inch(2), "Inner Diameter": ComponentKit.inch(1.5)], cost: 1.20, model: "FPC-2")
        b.type("Floor Protector - 2 1/2\"", [:], cost: 1.50, model: "FPC-25", isDefault: true)
        b.type("Floor Protector - 3 1/2\"", ["Outer Diameter": ComponentKit.inch(3.5), "Inner Diameter": ComponentKit.inch(2.75)], cost: 2.20, model: "FPC-35")
        return b.build()
    }
}

extension ComponentFinish {
    /// COMPB: red polyurethane tread.
    static let polyurethaneRed = ComponentFinish("Polyurethane - Red", .plastic, RGBColor(hex: 0xB33A2E))
}
