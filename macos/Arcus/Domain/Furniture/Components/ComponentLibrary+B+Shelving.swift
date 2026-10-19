import Foundation
import ArcusGeometry

// COMPB: 08 Shelving Hardware. Two frames:
//   - face-based (side panels, backs and walls): origin on the inside face where the shelf's underside meets it, X along
//     the face, Y up, Z out of the face into the bay (the host's material is at negative Z);
//   - the opening frame (pull-outs and turntables inside a bay, like FM5's slide pairs): origin at the bay's
//     bottom-left-front corner, X across the bay ("Opening Width"), Y into its depth ("Opening Depth"), Z up
//     ("Mount Height" above the bay's bottom).

extension ComponentLibrary {
    static var groupBShelving: [ComponentDefinition] {
        [shelfPinUpgrade(), shelfBracket(), floatingShelfBracket(), concealedShelfSupport(), adjustableShelfRail(), shelfStandard(),
         glassShelfSupport(), shelfClip(), shelfDivider(), shelfStop(), shelfRetainer(), pullOutShelf(), slidingShelf(), rotatingShelf(),
         cornerShelfSystem(), heavyDutyShelfBracket(), foldDownShelfBracket()]
    }

    /// The opening-frame parameters every bay item has: the bay's width and depth and the height it's mounted at.
    static func openingParams(_ b: inout ComponentBuilder, width: Double = ComponentKit.inch(22.5), depth: Double = ComponentKit.inch(22), mount: Double = 0) {
        // Placed in a bay on its left inside face: mounting x runs into the depth and y up from the bay's bottom.
        b.host([.bay], faces: [.left], align: .full)
        b.length("Opening Width", width, instance: true, group: .placement, min: ComponentKit.inch(6), max: ComponentKit.inch(60))
        b.length("Opening Depth", depth, instance: true, group: .placement, min: ComponentKit.inch(6), max: ComponentKit.inch(30))
        b.length("Mount Height", mount, instance: true, group: .placement)
    }

    /// A drawer slide pair at both sides of the opening, `length` long, from the front setback, on the opening frame.
    static func slidePair(_ b: inout ComponentBuilder, length: String, z: (String, String), setback: String = CX.mm(3)) {
        b.slot("Slide Material") { b in
            b.box("Left Slide", x: (CX.zero, CX.mm(12.7)), y: (setback, "\(setback) + \(length)"), z: z)
            b.box("Right Slide", x: ("Opening Width - 0.0127 m", "Opening Width"), y: (setback, "\(setback) + \(length)"), z: z)
        }
    }

    /// Slide screws in the sides at 32 mm-system positions from 37 mm (the left side's; the right side's are mirrored,
    /// ComponentLibrary+B+Machining.swift).
    static func slideScrews(_ b: inout ComponentBuilder, z: String, n: Int = 3) {
        for k in 0..<n {
            let y = "0.037 m + \(LX.num(Double(k) * 0.128)) m"
            b.drill("Slide screw", x: y, y: z, diameter: CX.mm(4), depth: CX.mm(12), target: .counterpart)
        }
    }

    /// Bay-item symbols: the outline in plan (X–Y on the opening frame's face view) and its front.
    static func bayItemSymbols(_ b: inout ComponentBuilder, x: (String, String), y: (String, String), z: (String, String)) {
        b.symRect(.face, CBL.all, (x.0, y.0), (x.1, y.1))
        b.symLine(.face, CBL.coarse, (x.0, y.0), (x.1, y.1))
        b.symRect(.side, CBL.coarse, (z.0, y.0), (z.1, y.1))
    }

    // MARK: Pins, supports, clips

    /// FM5's Shelf Pin, upgraded: plain, sleeve and plate types on the 32 mm system, smooth pins, symbols, the hole.
    static func shelfPinUpgrade() -> ComponentDefinition {
        guard var b = ComponentBuilder(upgrading: FurnitureHardware.shelfPin) else { return shelfRetainer() }
        b.smoothCircles()
        b.tags("shelf pin", "shelf peg", "5 mm", "1/4\"", "32 mm system", "spoon", "sleeve", "plug-in")
        b.aliases("shelf peg", "shelf support pin", "shelf rest", "spoon pin", "paddle pin", "sleeve pin", "1/4 inch shelf pin")
        b.length("Hole Pitch", ComponentKit.mm(32), group: .manufacturing)
        b.at(CBL.fine) { b in
            b.rod("Collar", axis: .x, r: "Diameter / 2 + 0.0006 m", from: CX.mm(-0.8), to: CX.zero, sides: 20)
        }
        b.symCircle(.face, CBL.all, r: "Diameter / 2")
        b.symRect(.face, CBL.mediumFine, (CX.zero, "-Diameter * 0.7"), ("Spoon Length", "Diameter * 0.7"))
        b.symLine(.side, CBL.coarse, ("-Length", CX.zero), ("Spoon Length", CX.zero))
        b.drill("Shelf pin", x: CX.zero, y: CX.zero, diameter: "Diameter", depth: "Length + 0.0015 m")
        b.type("5 mm Plain", ["Diameter": ComponentKit.mm(5), "Length": ComponentKit.mm(8), "Spoon Length": ComponentKit.mm(5)], cost: 0.05, model: "SP-5P",
               description: "Plain steel shelf pin, 5 mm")
        b.type("5 mm Plate", ["Diameter": ComponentKit.mm(5), "Length": ComponentKit.mm(8), "Spoon Length": ComponentKit.mm(16)], cost: 0.12, model: "SP-5PL",
               description: "Shelf pin with a flat plate rest, 5 mm")
        return b.build()
    }

    /// A shelf retainer: a 5 mm pin with a spring clip that snaps into a hole under the shelf so it can't lift or slide.
    static func shelfRetainer() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Retainer", .shelving, "Shelf Pins", "Locking shelf pin: a 5 mm pin with a sprung barb that snaps into a hole under the shelf, so the shelf can't lift or slide out.")
        b.tags("shelf retainer", "locking shelf pin", "anti-tip", "5 mm", "shelf lock", "seismic")
        b.aliases("locking shelf support", "shelf lock pin", "anti-lift pin", "shelf latch", "earthquake shelf pin")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .whitePlastic)
        b.length("Pin Diameter", ComponentKit.mm(5))
        b.length("Pin Length", ComponentKit.mm(8))
        b.length("Body Width", ComponentKit.mm(10))
        b.length("Body Depth", ComponentKit.mm(14))
        b.length("Barb Height", ComponentKit.mm(6))
        b.length("Shelf Hole Diameter", ComponentKit.mm(5), group: .manufacturing)
        b.host([.sidePanel, .divider], faces: [.inside], align: .center)
        b.rod("Pin", r: "Pin Diameter / 2", from: "-Pin Length", to: CX.zero, sides: 20)
        b.box("Body", x: ("-Body Width / 2", "Body Width / 2"), y: (CX.mm(-4), CX.zero), z: (CX.zero, "Body Depth"))
        b.rod("Barb", axis: .y, c: (CX.zero, "Body Depth * 0.6"), r: "Shelf Hole Diameter / 2 - 0.0002 m", from: CX.zero, to: "Barb Height", sides: 16)
        b.symRect(.face, CBL.all, ("-Body Width / 2", CX.mm(-4)), ("Body Width / 2", CX.zero))
        b.symRect(.top, CBL.all, ("-Body Width / 2", CX.zero), ("Body Width / 2", "Body Depth"))
        b.symCircle(.top, CBL.mediumFine, c: (CX.zero, "Body Depth * 0.6"), r: "Shelf Hole Diameter / 2", dashed: true)
        b.drill("Shelf retainer pin", x: CX.zero, y: CX.zero, diameter: "Pin Diameter", depth: "Pin Length + 0.0015 m")
        b.drill("Shelf retainer hole", x: CX.zero, y: CX.zero, diameter: "Shelf Hole Diameter", depth: "Barb Height + 0.001 m", target: .counterpart)
        b.type("Shelf Retainer - 5 mm", [:], cost: 0.18, model: "SR-5", isDefault: true)
        b.type("Shelf Retainer - 1/4\"", ["Pin Diameter": ComponentKit.inch(0.25), "Pin Length": ComponentKit.inch(0.375), "Shelf Hole Diameter": ComponentKit.inch(0.25)],
               cost: 0.20, model: "SR-14")
        return b.build()
    }

    /// A concealed (tab) shelf support: a blade on a pin, pushed into a kerf in the shelf's end so it can't be seen.
    static func concealedShelfSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Concealed Shelf Support", .shelving, "Shelf Supports", "Concealed shelf support: a pin in the side carrying a flat blade that slides into a saw kerf in the shelf's end.")
        b.tags("concealed shelf support", "invisible", "blade", "kerf", "5 mm", "hidden shelf")
        b.aliases("invisible shelf support", "tab shelf support", "kerf support", "blade shelf pin", "hidden shelf clip")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .zinc)
        b.length("Pin Diameter", ComponentKit.mm(5))
        b.length("Pin Length", ComponentKit.mm(8))
        b.length("Blade Length", ComponentKit.mm(30))
        b.length("Blade Width", ComponentKit.mm(10))
        b.length("Blade Thickness", ComponentKit.mm(1.5))
        b.length("Shelf Thickness", ComponentKit.mm(19))
        b.host([.sidePanel, .divider], faces: [.inside], align: .center)
        let mid = "Shelf Thickness / 2"
        b.rod("Pin", r: "Pin Diameter / 2", from: "-Pin Length", to: CX.zero, sides: 20)
        b.box("Blade", x: ("-Blade Width / 2", "Blade Width / 2"), y: ("\(mid) - Blade Thickness / 2", "\(mid) + Blade Thickness / 2"), z: (CX.zero, "Blade Length"))
        b.box("Neck", x: ("-Pin Diameter / 2", "Pin Diameter / 2"), y: (CX.zero, mid), z: (CX.zero, CX.mm(2)))
        b.symCircle(.face, CBL.all, r: "Pin Diameter / 2")
        b.symRect(.top, CBL.all, ("-Blade Width / 2", CX.zero), ("Blade Width / 2", "Blade Length"), dashed: true)
        b.drill("Concealed support pin", x: CX.zero, y: CX.zero, diameter: "Pin Diameter", depth: "Pin Length + 0.0015 m")
        b.groove("Shelf end kerf", from: ("-Blade Width / 2 - 0.002 m", mid), to: ("Blade Width / 2 + 0.002 m", mid), width: "Blade Thickness + 0.0005 m",
                 depth: "Blade Length + 0.002 m", target: .counterpart)
        b.type("Concealed Support - 16 mm Shelf", ["Shelf Thickness": ComponentKit.mm(16)], cost: 0.30, model: "CSS-16")
        b.type("Concealed Support - 19 mm Shelf", [:], cost: 0.30, model: "CSS-19", isDefault: true)
        return b.build()
    }

    /// A glass shelf support: a pin with a clear cup (or a clamp) that grips the glass.
    static func glassShelfSupport() -> ComponentDefinition {
        var b = ComponentBuilder("Glass Shelf Support", .shelving, "Shelf Supports", "Glass shelf support: a 5 mm pin with a clear rubber cup, or a clamp that grips the glass from above and below.")
        b.tags("glass shelf support", "glass", "shelf pin", "clamp", "5 mm", "6 mm glass", "8 mm glass")
        b.aliases("glass shelf pin", "glass clamp", "glass shelf clip", "suction pin", "glass rest")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .chrome)
        b.material("Pad Material", .crystal)
        b.length("Pin Diameter", ComponentKit.mm(5))
        b.length("Pin Length", ComponentKit.mm(8))
        b.length("Glass Thickness", ComponentKit.mm(6), min: ComponentKit.mm(4), max: ComponentKit.mm(12))
        b.length("Body Diameter", ComponentKit.mm(10))
        b.length("Reach", ComponentKit.mm(14))
        b.flag("Clamp", false, instance: false)
        b.host([.sidePanel, .divider, .back], faces: [.inside], align: .center)
        b.rod("Pin", r: "Pin Diameter / 2", from: "-Pin Length", to: CX.zero, sides: 20)
        b.rod("Body", axis: .z, c: (CX.zero, "-Body Diameter / 2"), r: "Body Diameter / 2", from: CX.zero, to: "Reach * 0.4")
        b.slot("Pad Material") { b in
            b.rod("Pad", axis: .y, c: (CX.zero, "Reach * 0.65"), r: "Body Diameter / 2", from: CX.mm(-2), to: CX.zero)
        }
        b.box("Arm", x: ("-Body Diameter * 0.3", "Body Diameter * 0.3"), y: (CX.mm(-3), CX.zero), z: (CX.zero, "Reach"))
        b.shown(by: "Clamp") { b in
            b.box("Clamp Top", x: ("-Body Diameter * 0.3", "Body Diameter * 0.3"), y: ("Glass Thickness", "Glass Thickness + 0.003 m"), z: (CX.zero, "Reach"))
            b.box("Clamp Back", x: ("-Body Diameter * 0.3", "Body Diameter * 0.3"), y: (CX.zero, "Glass Thickness + 0.003 m"), z: (CX.zero, CX.mm(3)))
        }
        b.symCircle(.face, CBL.all, c: (CX.zero, "-Body Diameter / 2"), r: "Body Diameter / 2")
        b.symRect(.top, CBL.all, ("-Body Diameter / 2", CX.zero), ("Body Diameter / 2", "Reach"))
        b.drill("Glass support pin", x: CX.zero, y: CX.zero, diameter: "Pin Diameter", depth: "Pin Length + 0.0015 m")
        b.type("Glass Support - 5 mm for 6 mm Glass", [:], flags: ["Clamp": false], cost: 0.35, model: "GSS-56", isDefault: true)
        b.type("Glass Clamp - 8 mm Glass", ["Glass Thickness": ComponentKit.mm(8), "Body Diameter": ComponentKit.mm(12)], flags: ["Clamp": true], cost: 0.85, model: "GSC-8")
        b.type("Glass Clamp - 10 mm Glass", ["Glass Thickness": ComponentKit.mm(10), "Body Diameter": ComponentKit.mm(14), "Reach": ComponentKit.mm(18)], flags: ["Clamp": true],
               cost: 1.05, model: "GSC-10")
        return b.build()
    }

    /// A pilaster (standard) clip: a bent steel clip hooked into a shelf standard's slot.
    static func shelfClip() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Clip", .shelving, "Shelf Standards", "Pilaster clip: a bent steel clip hooked into a shelf standard's slot, with a ledge the shelf sits on.")
        b.tags("shelf clip", "pilaster clip", "standard clip", "shelf support", "1/2\" slot")
        b.aliases("pilaster clip", "shelf standard clip", "shelving clip", "supports for standards", "track clip")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .zinc)
        b.length("Clip Width", ComponentKit.inch(0.5))
        b.length("Clip Height", ComponentKit.inch(0.75))
        b.length("Ledge Depth", ComponentKit.inch(0.5))
        b.length("Thickness", ComponentKit.inch(0.04))
        b.flag("Locking Tab", false, instance: false)
        b.host([.sidePanel, .divider], faces: [.inside], align: .center)
        b.box("Back", x: ("-Clip Width / 2", "Clip Width / 2"), y: ("-Clip Height", CX.zero), z: (CX.zero, "Thickness"))
        b.box("Ledge", x: ("-Clip Width / 2", "Clip Width / 2"), y: ("-Thickness", CX.zero), z: (CX.zero, "Ledge Depth"))
        b.box("Hook", x: ("-Clip Width / 2", "Clip Width / 2"), y: ("-Clip Height", "-Clip Height + 0.004 m"), z: (CX.mm(-3), CX.zero))
        b.shown(by: "Locking Tab") { b in
            b.box("Locking Tab", x: ("-Clip Width / 2", "Clip Width / 2"), y: (CX.zero, CX.mm(5)), z: ("Ledge Depth - Thickness", "Ledge Depth"))
        }
        b.symRect(.face, CBL.all, ("-Clip Width / 2", "-Clip Height"), ("Clip Width / 2", CX.zero))
        b.symRect(.top, CBL.all, ("-Clip Width / 2", CX.zero), ("Clip Width / 2", "Ledge Depth"))
        b.type("Shelf Clip - Standard", [:], flags: ["Locking Tab": false], cost: 0.10, model: "SC-STD", isDefault: true)
        b.type("Shelf Clip - Locking", [:], flags: ["Locking Tab": true], cost: 0.15, model: "SC-LCK")
        return b.build()
    }

    /// A shelf stop: a strip or fence at the back (or front) of a shelf that keeps things from sliding off.
    static func shelfStop() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Stop", .shelving, "Shelf Accessories", "Shelf stop: a strip screwed on a shelf's back (or a fence at the front of a pull-out) that keeps things in place.")
        b.tags("shelf stop", "back stop", "fence", "rail", "gallery", "plate stop")
        b.aliases("plate rail", "shelf fence", "back fence", "stop strip", "shelf lip", "gallery rail")
        b.material("Finish Material", .aluminum)
        b.length("Length", ComponentKit.inch(22), instance: true, group: .dimensions)
        b.length("Stop Height", ComponentKit.inch(0.5))
        b.length("Stop Thickness", ComponentKit.inch(0.125))
        b.length("Base Width", ComponentKit.inch(0.5))
        b.host([.shelf, .bottom], faces: [.top], align: .full)
        b.box("Fence", x: ("-Length / 2", "Length / 2"), y: (CX.zero, "Stop Thickness"), z: (CX.zero, "Stop Height"))
        b.box("Foot", x: ("-Length / 2", "Length / 2"), y: (CX.zero, "Base Width"), z: (CX.zero, "Stop Thickness"))
        b.at(CBL.fine) { b in
            b.screwHeads("Screw", [("-Length * 0.4", "Base Width * 0.6"), (CX.zero, "Base Width * 0.6"), ("Length * 0.4", "Base Width * 0.6")], z: "Stop Thickness",
                         diameter: CX.mm(6), height: CX.mm(1))
        }
        b.symRect(.face, CBL.all, ("-Length / 2", CX.zero), ("Length / 2", "Base Width"))
        b.symRect(.top, CBL.all, ("-Length / 2", CX.zero), ("Length / 2", "Stop Height"))
        for x in ["-Length * 0.4", CX.zero, "Length * 0.4"] { b.drill("Shelf stop screw", x: x, y: "Base Width * 0.6", diameter: CX.mm(2.5), depth: CX.mm(10)) }
        b.type("Shelf Stop - 1/2\"", [:], cost: 2.20, model: "SST-12", isDefault: true)
        b.type("Shelf Stop - 1\" Plate Rail", ["Stop Height": ComponentKit.inch(1), "Base Width": ComponentKit.inch(0.625)], cost: 3.40, model: "SST-1")
        return b.build()
    }

    /// A clip-on shelf divider: a wire or acrylic upright that clips over a shelf to keep stacks apart.
    static func shelfDivider() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Divider", .shelving, "Shelf Accessories", "Clip-on shelf divider: a wire (or acrylic) upright that slides over a shelf's front edge to separate stacks.")
        b.tags("shelf divider", "divider", "clip-on", "wire", "acrylic", "closet", "separator")
        b.aliases("shelf separator", "closet divider", "wire divider", "acrylic divider", "sweater divider")
        b.material("Finish Material", .chrome)
        b.length("Divider Height", ComponentKit.inch(10))
        b.length("Divider Depth", ComponentKit.inch(12))
        b.length("Wire Diameter", ComponentKit.inch(0.19))
        b.length("Shelf Thickness", ComponentKit.inch(0.75))
        b.flag("Solid Panel", false, instance: false)
        b.flag("Wire", true, formula: "not(Solid Panel)")
        b.host([.shelf], faces: [.top], align: .center)
        // On the shelf's top face: X across, Y along the depth, Z up.
        let r = "Wire Diameter / 2"
        b.shown(by: "Wire") { b in
            b.rod("Front Post", c: (CX.zero, r), r: r, from: "-Shelf Thickness - Wire Diameter", to: "Divider Height", sides: 12)
            b.rod("Back Post", c: (CX.zero, "Divider Depth - Wire Diameter"), r: r, from: CX.zero, to: "Divider Height", sides: 12)
            b.rod("Top Wire", axis: .y, c: (CX.zero, "Divider Height - Wire Diameter / 2"), r: r, from: CX.zero, to: "Divider Depth", sides: 12)
            b.rod("Mid Wire", axis: .y, c: (CX.zero, "Divider Height / 2"), r: r, from: CX.zero, to: "Divider Depth", sides: 12)
            b.rod("Bottom Wire", axis: .y, c: (CX.zero, "Wire Diameter / 2"), r: r, from: CX.zero, to: "Divider Depth", sides: 12)
            b.rod("Clip", axis: .y, c: (CX.zero, "-Shelf Thickness - Wire Diameter / 2"), r: r, from: CX.zero, to: "Divider Depth * 0.6", sides: 12)
        }
        b.shown(by: "Solid Panel") { b in
            b.slot("Panel Material") { b in
                b.box("Panel", x: (CX.mm(-2.5), CX.mm(2.5)), y: (CX.zero, "Divider Depth"), z: (CX.zero, "Divider Height"))
            }
            b.box("Clip", x: (CX.mm(-6), CX.mm(6)), y: (CX.zero, "Divider Depth * 0.5"), z: ("-Shelf Thickness - 0.003 m", "-Shelf Thickness"))
        }
        b.material("Panel Material", .crystal)
        b.symLine(.face, CBL.all, (CX.zero, CX.zero), (CX.zero, "Divider Depth"))
        b.symRect(.side, CBL.all, (CX.zero, CX.zero), ("Divider Height", "Divider Depth"))
        b.type("Shelf Divider - 8\" Wire", ["Divider Height": ComponentKit.inch(8)], flags: ["Solid Panel": false], cost: 6.00, model: "SD-8W")
        b.type("Shelf Divider - 10\" Wire", [:], flags: ["Solid Panel": false], cost: 7.00, model: "SD-10W", isDefault: true)
        b.type("Shelf Divider - 12\" Acrylic", ["Divider Height": ComponentKit.inch(12)], flags: ["Solid Panel": true], cost: 11.00, model: "SD-12A")
        return b.build()
    }

    // MARK: Brackets

    /// A wall shelf bracket: an L with a diagonal brace, screwed to the wall or a standard.
    static func shelfBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Bracket", .shelving, "Shelf Brackets", "Shelf bracket: an L of flat steel with a diagonal brace, screwed to a wall, a back or a shelf standard.")
        b.tags("shelf bracket", "wall bracket", "l bracket", "brace", "steel", "6\"", "8\"", "10\"")
        b.aliases("wall shelf bracket", "shelf support bracket", "braced bracket", "shelf angle bracket", "wall bracket")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .matteBlack)
        b.length("Bracket Depth", ComponentKit.inch(8))
        b.length("Bracket Height", ComponentKit.inch(6))
        b.length("Bar Width", ComponentKit.inch(0.75))
        b.length("Bar Thickness", ComponentKit.inch(0.125))
        b.number("Load Rating", 60, unit: "lb", group: .data)
        b.host([.back, .wall, .sidePanel], faces: [.inside, .front], align: .center)
        // On the face: the upright runs down from the shelf's underside (Y = 0), the arm out of the face (Z) under the shelf.
        let x = ("-Bar Thickness / 2", "Bar Thickness / 2")
        b.box("Upright", x: ("-Bar Width / 2", "Bar Width / 2"), y: ("-Bracket Height", CX.zero), z: (CX.zero, "Bar Thickness"))
        b.box("Arm", x: x, y: ("-Bar Width", CX.zero), z: (CX.zero, "Bracket Depth"))
        b.extrusion("Brace", profile: ComponentKit.points([("-Bracket Height * 0.8", "Bar Thickness"), ("-Bracket Height * 0.8 + Bar Width", "Bar Thickness"),
                                                           ("-Bar Width", "Bracket Depth * 0.8"), ("-Bar Width", "Bracket Depth * 0.8 - Bar Width")]),
                    plane: .yz, from: "-Bar Thickness / 2", to: "Bar Thickness / 2")
        b.symRect(.face, CBL.all, ("-Bar Width / 2", "-Bracket Height"), ("Bar Width / 2", CX.zero))
        b.symbol(.side, CBL.all, .polyline(ComponentKit.points([(CX.zero, "-Bracket Height"), (CX.zero, CX.zero), ("Bracket Depth", CX.zero)]), closed: false),
                 .line(("Bar Thickness", "-Bracket Height * 0.8"), ("Bracket Depth * 0.8", "-Bar Width")))
        b.symRect(.top, CBL.coarse, ("-Bar Thickness / 2", CX.zero), ("Bar Thickness / 2", "Bracket Depth"))
        for y in ["-Bracket Height * 0.25", "-Bracket Height * 0.8"] { b.drill("Bracket screw", x: CX.zero, y: y, diameter: CX.mm(4), depth: CX.mm(25)) }
        b.type("Shelf Bracket - 6\"", ["Bracket Depth": ComponentKit.inch(6), "Bracket Height": ComponentKit.inch(5)], numbers: ["Load Rating": 45], cost: 3.50, model: "SBK-6")
        b.type("Shelf Bracket - 8\"", [:], cost: 4.25, model: "SBK-8", isDefault: true)
        b.type("Shelf Bracket - 10\"", ["Bracket Depth": ComponentKit.inch(10), "Bracket Height": ComponentKit.inch(8)], numbers: ["Load Rating": 75], cost: 5.25, model: "SBK-10")
        return b.build()
    }

    /// A gusseted steel bracket for heavy shelves and counters.
    static func heavyDutyShelfBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Heavy-Duty Shelf Bracket", .shelving, "Shelf Brackets", "Heavy-duty shelf (counter) bracket: a welded steel triangle with a solid gusset, for counters, bars and loaded shelves.")
        b.tags("heavy duty bracket", "counter bracket", "countertop support", "gusset", "steel", "triangle", "bar top")
        b.aliases("countertop bracket", "granite bracket", "corbel bracket", "workbench bracket", "triangle bracket", "load bracket")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .matteBlack)
        b.length("Bracket Depth", ComponentKit.inch(12))
        b.length("Bracket Height", ComponentKit.inch(12))
        b.length("Bar Width", ComponentKit.inch(1.5))
        b.length("Bar Thickness", ComponentKit.inch(0.25))
        b.number("Load Rating", 500, unit: "lb", group: .data)
        b.host([.back, .wall, .sidePanel], faces: [.inside, .front], align: .center)
        b.box("Upright", x: ("-Bar Width / 2", "Bar Width / 2"), y: ("-Bracket Height", CX.zero), z: (CX.zero, "Bar Thickness"))
        b.box("Arm", x: ("-Bar Width / 2", "Bar Width / 2"), y: ("-Bar Thickness", CX.zero), z: (CX.zero, "Bracket Depth"))
        b.extrusion("Gusset", profile: ComponentKit.points([("-Bracket Height", "Bar Thickness"), ("-Bar Thickness", "Bar Thickness"), ("-Bar Thickness", "Bracket Depth")]),
                    plane: .yz, from: "-Bar Thickness / 2", to: "Bar Thickness / 2")
        b.at(CBL.fine) { b in
            b.rod("Lightening Hole", axis: .x, c: ("-Bracket Height * 0.3", "Bracket Depth * 0.3"), r: "min(Bracket Height, Bracket Depth) * 0.12", from: "-Bar Thickness",
                  to: "Bar Thickness", void: true)
        }
        b.symRect(.face, CBL.all, ("-Bar Width / 2", "-Bracket Height"), ("Bar Width / 2", CX.zero))
        b.symbol(.side, CBL.all, .polyline(ComponentKit.points([(CX.zero, "-Bracket Height"), (CX.zero, CX.zero), ("Bracket Depth", CX.zero)]), closed: true))
        b.symRect(.top, CBL.coarse, ("-Bar Width / 2", CX.zero), ("Bar Width / 2", "Bracket Depth"))
        for y in ["-Bracket Height * 0.15", "-Bracket Height * 0.5", "-Bracket Height * 0.85"] { b.drill("Bracket screw", x: CX.zero, y: y, diameter: CX.mm(6), depth: CX.mm(50)) }
        b.drill("Arm screw", x: CX.zero, y: CX.zero, diameter: CX.mm(5), depth: CX.mm(16), target: .counterpart)
        b.type("Heavy-Duty Bracket - 8\"", ["Bracket Depth": ComponentKit.inch(8), "Bracket Height": ComponentKit.inch(8)], numbers: ["Load Rating": 350], cost: 12.00, model: "HDB-8")
        b.type("Heavy-Duty Bracket - 12\"", [:], cost: 16.00, model: "HDB-12", isDefault: true)
        b.type("Heavy-Duty Bracket - 18\" Counter", ["Bracket Depth": ComponentKit.inch(18), "Bracket Height": ComponentKit.inch(14), "Bar Width": ComponentKit.inch(2)],
               numbers: ["Load Rating": 700], cost: 24.00, model: "HDB-18")
        return b.build()
    }

    /// A floating shelf bracket: a wall plate with two long rods that go into holes drilled in the shelf's back edge.
    static func floatingShelfBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Floating Shelf Bracket", .shelving, "Shelf Brackets", "Floating shelf bracket: a steel wall plate with rods that go into holes drilled in the shelf's back edge, so no bracket shows.")
        b.tags("floating shelf bracket", "hidden bracket", "concealed", "rod", "wall plate", "invisible")
        b.aliases("floating shelf support", "hidden shelf bracket", "blind shelf support", "concealed shelf bracket", "invisible shelf bracket")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .steel)
        b.length("Plate Length", ComponentKit.inch(12))
        b.length("Plate Height", ComponentKit.inch(1.5))
        b.length("Plate Thickness", ComponentKit.inch(0.1875))
        b.length("Rod Length", ComponentKit.inch(6))
        b.length("Rod Diameter", ComponentKit.inch(0.375))
        b.length("Rod Spacing", ComponentKit.inch(8))
        b.length("Shelf Thickness", ComponentKit.inch(1.5))
        b.number("Load Rating", 40, unit: "lb", group: .data)
        b.host([.back, .wall], faces: [.inside, .front], align: .center)
        // The plate's top at the shelf's mid thickness (Y = 0 is the shelf's underside), rods out of the face.
        let yc = "Shelf Thickness / 2"
        b.box("Wall Plate", x: ("-Plate Length / 2", "Plate Length / 2"), y: ("\(yc) - Plate Height / 2", "\(yc) + Plate Height / 2"), z: (CX.zero, "Plate Thickness"))
        for (k, x) in ["-Rod Spacing / 2", "Rod Spacing / 2"].enumerated() {
            b.rod("Rod \(k + 1)", axis: .z, c: (x, yc), r: "Rod Diameter / 2", from: "Plate Thickness", to: "Plate Thickness + Rod Length", sides: 20)
        }
        b.at(CBL.fine) { b in
            b.screwHeads("Screw", [("-Plate Length * 0.42", yc), (CX.zero, yc), ("Plate Length * 0.42", yc)], z: "Plate Thickness", diameter: CX.mm(8), height: CX.mm(1.5))
        }
        b.symRect(.face, CBL.all, ("-Plate Length / 2", "\(yc) - Plate Height / 2"), ("Plate Length / 2", "\(yc) + Plate Height / 2"))
        b.symRect(.top, CBL.all, ("-Plate Length / 2", CX.zero), ("Plate Length / 2", "Plate Thickness"))
        b.symLine(.top, CBL.all, ("-Rod Spacing / 2", "Plate Thickness"), ("-Rod Spacing / 2", "Plate Thickness + Rod Length"), dashed: true)
        b.symLine(.top, CBL.all, ("Rod Spacing / 2", "Plate Thickness"), ("Rod Spacing / 2", "Plate Thickness + Rod Length"), dashed: true)
        for x in ["-Plate Length * 0.42", CX.zero, "Plate Length * 0.42"] { b.drill("Wall plate screw", x: x, y: yc, diameter: CX.mm(5), depth: CX.mm(50)) }
        for x in ["-Rod Spacing / 2", "Rod Spacing / 2"] {
            b.drill("Floating shelf rod hole", x: x, y: yc, diameter: "Rod Diameter + 0.0005 m", depth: "Rod Length + 0.003 m", target: .counterpart)
        }
        b.requires(.note("Shelf at least 1 1/4\" thick so the rods are hidden."))
        b.type("Floating Bracket - 6\" Rods", [:], cost: 9.00, model: "FSB-6", isDefault: true)
        b.type("Floating Bracket - 8\" Rods", ["Rod Length": ComponentKit.inch(8), "Rod Diameter": ComponentKit.inch(0.5), "Plate Length": ComponentKit.inch(16),
                                                "Rod Spacing": ComponentKit.inch(12), "Shelf Thickness": ComponentKit.inch(2)], numbers: ["Load Rating": 65], cost: 13.00, model: "FSB-8")
        return b.build()
    }

    /// A fold-down shelf bracket: a bracket that folds flat against the wall and locks open.
    static func foldDownShelfBracket() -> ComponentDefinition {
        var b = ComponentBuilder("Fold-Down Shelf Bracket", .shelving, "Shelf Brackets", "Folding shelf bracket: locks open at 90° to hold a shelf or work surface, and folds flat against the wall.")
        b.tags("fold-down bracket", "folding bracket", "collapsible", "drop leaf", "workbench", "lock")
        b.aliases("folding shelf bracket", "collapsible bracket", "fold down shelf support", "drop shelf bracket", "foldaway bracket")
        b.hardwareKind(.stay)
        b.material("Finish Material", .matteBlack)
        b.length("Bracket Depth", ComponentKit.inch(12))
        b.length("Bracket Height", ComponentKit.inch(10))
        b.length("Bar Width", ComponentKit.inch(1))
        b.length("Bar Thickness", ComponentKit.inch(0.125))
        b.number("Load Rating", 110, unit: "lb", group: .data)
        b.flag("Folded", false, instance: true)
        b.flag("Open", true, formula: "not(Folded)")
        b.host([.back, .wall, .sidePanel], faces: [.inside, .front], align: .center)
        b.box("Wall Leg", x: ("-Bar Width / 2", "Bar Width / 2"), y: ("-Bracket Height", CX.zero), z: (CX.zero, "Bar Thickness"))
        b.shown(by: "Open") { b in
            b.box("Arm", x: ("-Bar Thickness / 2", "Bar Thickness / 2"), y: ("-Bar Width", CX.zero), z: ("Bar Thickness", "Bracket Depth"))
            b.extrusion("Folding Brace", profile: ComponentKit.points([("-Bracket Height * 0.9", "Bar Thickness"), ("-Bracket Height * 0.9 + Bar Width * 0.6", "Bar Thickness"),
                                                                       ("-Bar Width", "Bracket Depth * 0.7"), ("-Bar Width", "Bracket Depth * 0.7 - Bar Width * 0.6")]),
                        plane: .yz, from: "-Bar Thickness / 2", to: "Bar Thickness / 2")
            b.rod("Lock Knob", axis: .x, c: ("-Bracket Height * 0.45", "Bracket Depth * 0.35"), r: CX.mm(5), from: "-Bar Thickness * 2", to: "Bar Thickness * 2", sides: 16)
        }
        b.shown(by: "Folded") { b in
            b.box("Arm", x: ("-Bar Thickness / 2", "Bar Thickness / 2"), y: ("-Bracket Depth", CX.zero), z: ("Bar Thickness", "Bar Thickness * 2 + 0.002 m"))
        }
        b.symRect(.face, CBL.all, ("-Bar Width / 2", "-Bracket Height"), ("Bar Width / 2", CX.zero))
        b.symbol(.side, CBL.all, .polyline(ComponentKit.points([(CX.zero, "-Bracket Height"), (CX.zero, CX.zero), ("Bracket Depth", CX.zero)]), closed: false))
        b.symbol(.side, CBL.mediumFine, dashed: true, .arc(center: FamilyPoint(CX.zero, CX.zero), radius: "Bracket Depth", startDegrees: "-90", sweepDegrees: "90"))
        b.symRect(.top, CBL.coarse, ("-Bar Thickness / 2", CX.zero), ("Bar Thickness / 2", "Bracket Depth"))
        for y in ["-Bracket Height * 0.2", "-Bracket Height * 0.85"] { b.drill("Bracket screw", x: CX.zero, y: y, diameter: CX.mm(5), depth: CX.mm(30)) }
        b.type("Fold-Down Bracket - 8\"", ["Bracket Depth": ComponentKit.inch(8), "Bracket Height": ComponentKit.inch(7)], numbers: ["Load Rating": 75], cost: 8.00, model: "FDB-8")
        b.type("Fold-Down Bracket - 12\"", [:], cost: 11.00, model: "FDB-12", isDefault: true)
        b.type("Fold-Down Bracket - 16\"", ["Bracket Depth": ComponentKit.inch(16), "Bracket Height": ComponentKit.inch(12), "Bar Width": ComponentKit.inch(1.25)],
               numbers: ["Load Rating": 150], cost: 15.00, model: "FDB-16")
        return b.build()
    }

    // MARK: Rails and standards

    /// The slots of a slotted upright on its face, spread over `length` (24 a column), as Fine voids.
    static func slots(_ b: inout ComponentBuilder, length: String, width: String, height: String, depth: (String, String), columns: [String]) {
        b.at(CBL.fine) { b in
            for c in columns {
                for k in 0..<24 {
                    let y = "-(\(length)) * \(LX.num((Double(k) + 0.5) / 24))"
                    b.box("Slot \(c) \(k + 1)", x: ("\(c) - (\(width)) / 2", "\(c) + (\(width)) / 2"), y: ("\(y) - (\(height)) / 2", "\(y) + (\(height)) / 2"), z: depth, void: true)
                }
            }
        }
    }

    /// A twin-slot wall upright: brackets hook into its slots at any height.
    static func adjustableShelfRail() -> ComponentDefinition {
        var b = ComponentBuilder("Adjustable Shelf Rail", .shelving, "Shelf Standards", "Twin-slot wall upright: shelf brackets hook into its slots at any height; screwed to a wall or a back.")
        b.tags("shelf rail", "twin slot", "upright", "wall standard", "track", "adjustable shelving")
        b.aliases("twin track", "slotted upright", "wall upright", "shelving track", "bracket rail", "double slot standard")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .whitePlastic)
        b.length("Length", ComponentKit.inch(48))
        b.length("Rail Width", ComponentKit.inch(1))
        b.length("Rail Depth", ComponentKit.inch(0.5))
        b.length("Slot Pitch", ComponentKit.inch(1))
        b.length("Screw Spacing", ComponentKit.inch(16), group: .manufacturing)
        b.host([.back, .wall], faces: [.inside, .front], align: .top)
        b.box("Rail", x: ("-Rail Width / 2", "Rail Width / 2"), y: ("-Length", CX.zero), z: (CX.zero, "Rail Depth"))
        slots(&b, length: "Length", width: "Rail Width * 0.18", height: "Slot Pitch * 0.55", depth: ("Rail Depth - 0.003 m", "Rail Depth + 0.001 m"),
              columns: ["-Rail Width * 0.22", "Rail Width * 0.22"])
        b.symRect(.face, CBL.all, ("-Rail Width / 2", "-Length"), ("Rail Width / 2", CX.zero))
        b.symLine(.face, CBL.coarse, (CX.zero, "-Length"), (CX.zero, CX.zero))
        b.symRect(.top, CBL.all, ("-Rail Width / 2", CX.zero), ("Rail Width / 2", "Rail Depth"))
        for f in ["0.05", "0.5", "0.95"] { b.drill("Rail screw", x: CX.zero, y: "-Length * \(f)", diameter: CX.mm(5), depth: CX.mm(40)) }
        b.type("Shelf Rail - 36\"", ["Length": ComponentKit.inch(36)], cost: 7.50, model: "ASR-36")
        b.type("Shelf Rail - 48\"", [:], cost: 9.50, model: "ASR-48", isDefault: true)
        b.type("Shelf Rail - 72\"", ["Length": ComponentKit.inch(72)], cost: 13.50, model: "ASR-72")
        return b.build()
    }

    /// A shelf standard (pilaster): a slotted strip set in (or on) a cabinet side; shelf clips hook into it.
    static func shelfStandard() -> ComponentDefinition {
        var b = ComponentBuilder("Shelf Standard", .shelving, "Shelf Standards", "Shelf standard (pilaster): a slotted steel strip on or set in a cabinet's side; shelf clips hook into it every 1/2\".")
        b.tags("shelf standard", "pilaster", "strip", "slotted", "1/2\" pitch", "bookcase", "recessed")
        b.aliases("pilaster strip", "shelf strip", "bookcase strip", "shelving standard", "recessed standard")
        b.hardwareKind(.shelfPin)
        b.material("Finish Material", .zinc)
        b.length("Length", ComponentKit.inch(48))
        b.length("Strip Width", ComponentKit.inch(0.625))
        b.length("Strip Depth", ComponentKit.inch(0.1875))
        b.length("Slot Pitch", ComponentKit.inch(0.5))
        b.flag("Recessed", true, instance: false)
        b.host([.sidePanel, .divider], faces: [.inside], align: .full)
        b.box("Strip", x: ("-Strip Width / 2", "Strip Width / 2"), y: (CX.zero, "Length"), z: ("if(Recessed, -Strip Depth, 0 m)", "if(Recessed, 0 m, Strip Depth)"))
        b.at(CBL.fine) { b in
            for k in 0..<24 {
                let y = "Length * \(LX.num((Double(k) + 0.5) / 24))"
                b.box("Slot \(k + 1)", x: ("-Strip Width * 0.18", "Strip Width * 0.18"), y: ("\(y) - Slot Pitch * 0.3", "\(y) + Slot Pitch * 0.3"),
                      z: ("if(Recessed, -0.002 m, Strip Depth - 0.002 m)", "if(Recessed, 0.001 m, Strip Depth + 0.001 m)"), void: true)
            }
        }
        b.symRect(.face, CBL.all, ("-Strip Width / 2", CX.zero), ("Strip Width / 2", "Length"))
        b.symRect(.top, CBL.all, ("-Strip Width / 2", "-Strip Depth"), ("Strip Width / 2", CX.zero))
        b.groove("Standard dado", from: (CX.zero, CX.zero), to: (CX.zero, "Length"), width: "Strip Width + 0.0005 m", depth: "Strip Depth")
        b.type("Shelf Standard - 36\"", ["Length": ComponentKit.inch(36)], flags: ["Recessed": true], cost: 3.20, model: "SST-36")
        b.type("Shelf Standard - 48\"", [:], flags: ["Recessed": true], cost: 4.00, model: "SST-48", isDefault: true)
        b.type("Shelf Standard - 72\" Surface", ["Length": ComponentKit.inch(72)], flags: ["Recessed": false], cost: 5.80, model: "SST-72S")
        return b.build()
    }

    // MARK: Pull-outs and turntables (opening frame)

    /// A pull-out shelf: a tray with low sides on a pair of full-extension slides.
    static func pullOutShelf() -> ComponentDefinition {
        var b = ComponentBuilder("Pull-Out Shelf Mechanism", .shelving, "Pull-Out Shelves", "Pull-out shelf: a tray with a low gallery on full-extension slides, inside a door cabinet.", frame: .legacyOpening)
        b.tags("pull-out shelf", "roll-out", "slide-out", "tray", "rollout shelf", "full extension", "450 mm", "500 mm")
        b.aliases("roll out shelf", "slide out shelf", "pull out tray", "rollout tray", "glide out shelf", "drawer shelf")
        b.hardwareKind(.slide)
        b.material("Finish Material", .maple)
        b.material("Slide Material", .zinc)
        openingParams(&b, mount: ComponentKit.inch(1))
        b.length("Slide Length", ComponentKit.mm(450))
        b.length("Side Clearance", ComponentKit.inch(0.5))
        b.length("Gallery Height", ComponentKit.inch(3))
        b.length("Tray Thickness", ComponentKit.inch(0.5))
        b.number("Load Rating", 100, unit: "lb", group: .data)
        let x0 = "Side Clearance", x1 = "Opening Width - Side Clearance", y = (CX.mm(3), "0.003 m + Slide Length"), z0 = "Mount Height"
        slidePair(&b, length: "Slide Length", z: ("\(z0) + 0.005 m", "\(z0) + 0.04 m"))
        b.box("Tray Bottom", x: (x0, x1), y: y, z: (z0, "\(z0) + Tray Thickness"))
        b.box("Front", x: (x0, x1), y: (CX.mm(3), "0.003 m + Tray Thickness"), z: (z0, "\(z0) + Gallery Height"))
        b.box("Back", x: (x0, x1), y: ("0.003 m + Slide Length - Tray Thickness", "0.003 m + Slide Length"), z: (z0, "\(z0) + Gallery Height"))
        b.box("Left Side", x: (x0, "\(x0) + Tray Thickness"), y: y, z: (z0, "\(z0) + Gallery Height"))
        b.box("Right Side", x: ("\(x1) - Tray Thickness", x1), y: y, z: (z0, "\(z0) + Gallery Height"))
        b.at(CBL.fine) { b in
            b.box("Finger Notch", x: ("Opening Width / 2 - 0.04 m", "Opening Width / 2 + 0.04 m"), y: (CX.mm(2), "0.004 m + Tray Thickness"),
                  z: ("\(z0) + Gallery Height - 0.02 m", "\(z0) + Gallery Height + 0.001 m"), void: true)
        }
        bayItemSymbols(&b, x: (x0, x1), y: y, z: (z0, "\(z0) + Gallery Height"))
        b.symLine(.face, CBL.mediumFine, (x0, CX.zero), (x0, "Slide Length * -0.6"), dashed: true)
        slideScrews(&b, z: "\(z0) + 0.022 m")
        b.requires(.fitsDepth("Slide Length + 0.0127 m"))
        b.clearance(.side("Side Clearance"))
        b.type("Pull-Out Shelf - 450 mm", [:], cost: 34.00, model: "POS-450", isDefault: true)
        b.type("Pull-Out Shelf - 500 mm", ["Slide Length": ComponentKit.mm(500)], cost: 38.00, model: "POS-500")
        b.type("Pull-Out Shelf - 550 mm Heavy", ["Slide Length": ComponentKit.mm(550), "Tray Thickness": ComponentKit.inch(0.75)], numbers: ["Load Rating": 150], cost: 52.00, model: "POS-550H")
        return b.build()
    }

    /// A sliding shelf: a plain shelf board on light side runners (no gallery), e.g. a keyboard or printer shelf in a bay.
    static func slidingShelf() -> ComponentDefinition {
        var b = ComponentBuilder("Sliding Shelf", .shelving, "Pull-Out Shelves", "Sliding shelf: a plain shelf board on side runners, for a printer, a keyboard or a pantry shelf that slides forward.", frame: .legacyOpening)
        b.tags("sliding shelf", "slide out", "runner", "printer shelf", "pull-out", "board")
        b.aliases("slide-out shelf", "pull out board", "sliding board", "printer pull-out", "pantry slide")
        b.hardwareKind(.slide)
        b.material("Finish Material", .oak)
        b.material("Slide Material", .whitePlastic)
        openingParams(&b, mount: ComponentKit.inch(8))
        b.length("Shelf Depth", ComponentKit.inch(18))
        b.length("Shelf Thickness", ComponentKit.inch(0.75))
        b.length("Runner Height", ComponentKit.mm(17))
        b.length("Lip Height", ComponentKit.inch(0.75))
        let z0 = "Mount Height"
        slidePair(&b, length: "Shelf Depth", z: (z0, "\(z0) + Runner Height"), setback: CX.mm(5))
        b.box("Shelf", x: ("0.0127 m", "Opening Width - 0.0127 m"), y: (CX.mm(5), "0.005 m + Shelf Depth"), z: (z0, "\(z0) + Shelf Thickness"))
        b.box("Front Lip", x: ("0.0127 m", "Opening Width - 0.0127 m"), y: (CX.mm(5), "0.005 m + 0.012 m"), z: ("\(z0) + Shelf Thickness", "\(z0) + Shelf Thickness + Lip Height"))
        bayItemSymbols(&b, x: ("0.0127 m", "Opening Width - 0.0127 m"), y: (CX.mm(5), "0.005 m + Shelf Depth"), z: (z0, "\(z0) + Shelf Thickness"))
        slideScrews(&b, z: "\(z0) + Runner Height / 2")
        b.requires(.fitsDepth("Shelf Depth + 0.01 m"))
        b.type("Sliding Shelf - 16\"", ["Shelf Depth": ComponentKit.inch(16)], cost: 26.00, model: "SLS-16")
        b.type("Sliding Shelf - 18\"", [:], cost: 29.00, model: "SLS-18", isDefault: true)
        b.type("Sliding Shelf - 20\"", ["Shelf Depth": ComponentKit.inch(20)], cost: 32.00, model: "SLS-20")
        return b.build()
    }

    /// A rotating shelf: a round shelf on a turntable bearing, centred in the bay.
    static func rotatingShelf() -> ComponentDefinition {
        var b = ComponentBuilder("Rotating Shelf", .shelving, "Rotating Shelves", "Rotating shelf: a round shelf with a low rim on a ball-bearing turntable, centred in a cabinet or on a shelf.", frame: .legacyOpening)
        b.tags("rotating shelf", "turntable", "lazy susan", "revolving", "round shelf", "bearing")
        b.aliases("revolving shelf", "turntable shelf", "spinning shelf", "rotating tray", "swivel shelf")
        b.material("Finish Material", .whitePlastic)
        b.material("Bearing Material", .steel)
        openingParams(&b)
        b.length("Shelf Diameter", ComponentKit.inch(18))
        b.length("Shelf Thickness", ComponentKit.inch(0.5))
        b.length("Rim Height", ComponentKit.inch(1))
        b.length("Bearing Diameter", ComponentKit.inch(6))
        b.length("Bearing Height", ComponentKit.inch(0.375))
        let c = ("Opening Width / 2", "Opening Depth / 2"), z0 = "Mount Height"
        b.slot("Bearing Material") { b in
            b.rod("Bearing", c: c, r: "Bearing Diameter / 2", from: z0, to: "\(z0) + Bearing Height", sides: 32)
        }
        b.turn("Shelf", c: c, base: "\(z0) + Bearing Height", [(CX.zero, CX.zero), ("Shelf Diameter / 2", CX.zero), ("Shelf Diameter / 2", "Shelf Thickness + Rim Height"),
                                                                ("Shelf Diameter / 2 - 0.004 m", "Shelf Thickness + Rim Height"), ("Shelf Diameter / 2 - 0.004 m", "Shelf Thickness"),
                                                                (CX.zero, "Shelf Thickness")])
        b.symCircle(.face, CBL.all, c: c, r: "Shelf Diameter / 2")
        b.symCross(.face, CBL.coarse, c: c, s: "Shelf Diameter * 0.1")
        b.symCircle(.face, CBL.mediumFine, c: c, r: "Bearing Diameter / 2", dashed: true)
        b.symRect(.side, CBL.coarse, (z0, "Opening Depth / 2 - Shelf Diameter / 2"), ("\(z0) + Bearing Height + Shelf Thickness + Rim Height", "Opening Depth / 2 + Shelf Diameter / 2"))
        b.requires(.fitsWidth("Shelf Diameter + 0.01 m"))
        b.requires(.fitsDepth("Shelf Diameter + 0.01 m"))
        b.type("Rotating Shelf - 16\"", ["Shelf Diameter": ComponentKit.inch(16)], cost: 22.00, model: "RS-16")
        b.type("Rotating Shelf - 18\"", [:], cost: 26.00, model: "RS-18", isDefault: true)
        b.type("Rotating Shelf - 22\"", ["Shelf Diameter": ComponentKit.inch(22), "Bearing Diameter": ComponentKit.inch(8)], cost: 32.00, model: "RS-22")
        return b.build()
    }

    /// A corner shelf system: quarter-round shelves on a corner post, for an open inside corner.
    static func cornerShelfSystem() -> ComponentDefinition {
        var b = ComponentBuilder("Corner Shelf System", .shelving, "Corner Shelving", "Corner shelving: quarter-round shelves at equal spacing on a corner post, for an open inside corner.", frame: .legacyOpening)
        b.tags("corner shelf", "quarter round", "corner unit", "radius shelf", "corner post", "open corner")
        b.aliases("corner shelving", "quarter circle shelves", "corner shelf unit", "radius shelves", "end shelf")
        b.material("Finish Material", .oak)
        b.material("Post Material", .chrome)
        openingParams(&b, width: ComponentKit.inch(12), depth: ComponentKit.inch(12))
        b.length("Shelf Radius", ComponentKit.inch(12))
        b.length("Shelf Thickness", ComponentKit.inch(0.75))
        b.length("Shelf Spacing", ComponentKit.inch(12))
        b.length("Post Diameter", ComponentKit.inch(1))
        b.flag("Fourth Shelf", false, instance: false)
        // The corner at the back-left (X = 0, Y = Opening Depth); shelves quarter-round toward the front-right.
        let corner = (CX.zero, "Opening Depth")
        var quarter: [(String, String)] = [corner]
        for k in 0...12 {
            let a = -Double.pi / 2 + Double.pi / 2 * Double(k) / 12
            quarter.append(("Shelf Radius * \(LX.num(cos(a)))", "Opening Depth + Shelf Radius * \(LX.num(sin(a)))"))
        }
        for k in 0..<4 {
            let z = "Mount Height + Shelf Spacing * \(k)"
            let add: (inout ComponentBuilder) -> Void = { b in b.extrusion("Shelf \(k + 1)", profile: ComponentKit.points(quarter), from: z, to: "\(z) + Shelf Thickness") }
            if k == 3 { b.shown(by: "Fourth Shelf", add) } else { add(&b) }
        }
        b.slot("Post Material") { b in
            b.rod("Post", c: ("Shelf Radius * 0.7071", "Opening Depth - Shelf Radius * 0.7071"), r: "Post Diameter / 2", from: "Mount Height",
                  to: "Mount Height + Shelf Spacing * if(Fourth Shelf, 3, 2) + Shelf Thickness")
        }
        b.symbol(.face, CBL.all, .polyline(ComponentKit.points(quarter), closed: true))
        b.symCircle(.face, CBL.mediumFine, c: ("Shelf Radius * 0.7071", "Opening Depth - Shelf Radius * 0.7071"), r: "Post Diameter / 2")
        b.symRect(.side, CBL.coarse, ("Mount Height", "Opening Depth - Shelf Radius"), ("Mount Height + Shelf Spacing * 2 + Shelf Thickness", "Opening Depth"))
        for k in 0..<3 { b.drill("Shelf cleat screw", x: "Opening Depth - 0.03 m", y: "Mount Height + Shelf Spacing * \(k) - 0.01 m", diameter: CX.mm(4), depth: CX.mm(25), target: .counterpart) }
        b.type("Corner Shelves - 10\" x 3", ["Shelf Radius": ComponentKit.inch(10), "Shelf Spacing": ComponentKit.inch(10)], flags: ["Fourth Shelf": false], cost: 28.00, model: "CSS-103")
        b.type("Corner Shelves - 12\" x 3", [:], flags: ["Fourth Shelf": false], cost: 34.00, model: "CSS-123", isDefault: true)
        b.type("Corner Shelves - 12\" x 4", [:], flags: ["Fourth Shelf": true], cost: 42.00, model: "CSS-124")
        return b.build()
    }
}
