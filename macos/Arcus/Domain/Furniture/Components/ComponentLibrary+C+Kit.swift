import Foundation
import ArcusGeometry

// COMPC: Group C of the Furniture Component Library (Docs/FurnitureMode.md, owner's list): 10 Kitchen Cabinet
// Accessories, 11 Table & Desk Hardware, 12 Bed & Bedroom Hardware, 13 Sofa & Upholstery Hardware, 14 Chair Hardware.
// Every item is a parametric `ComponentDefinition` written with the ComponentKit builder; this file holds the list and
// the helpers the five category files share (rods, struts, trays, wire baskets, casters, outline symbols).
//
// Frames (see ComponentKit.swift):
// - Kitchen accessories that sit inside a bay use `.legacyOpening`: origin at the opening's bottom-left-front corner,
//   X across, Y into the depth, Z up. Their "Opening Width / Depth / Height" instance parameters take the bay's size,
//   so a pull-out fits the bay it's dropped in (frame width = Opening Width less the side clearances).
// - Items under or on a top, under a seat, on the floor or on a bed frame use `.plan` (X/Y in plan, Z up; under a part
//   they hang below the origin at negative Z). In plan, -Y is the front of the piece.
// - Items on a vertical face (door organizers, bed rail brackets, gas-lift plates) use `.face` (X along the face, Y up
//   it, Z out of it).

/// Group C's component definitions, in browser order.
public enum ComponentsC {
    /// Every Group C definition (categories 10–14).
    public static var all: [ComponentDefinition] { (kitchen + tables + beds + sofas + chairs).map(finished) }

    /// Host cutouts (voids named "… Cutout": grommet bores, sink and module cutouts) cut the host part, never the
    /// component's own solids, so their Cut Geometry is empty.
    static func finished(_ d: ComponentDefinition) -> ComponentDefinition {
        var d = d
        for k in d.family.solids.indices where d.family.solids[k].isVoid && d.family.solids[k].name.hasSuffix("Cutout") && d.family.solids[k].cuts == nil {
            d.family.solids[k].cuts = []
        }
        if let type = d.defaultType?.name {
            for (name, values) in presets[d.name] ?? [] where !d.presets.contains(where: { $0.name == name }) {
                d.presets.append(ComponentPreset(name: name, definitionID: d.id, typeName: type, values: values))
            }
        }
        return d
    }

    /// Built-in presets on the default type: mechanisms opened, desks raised, the other hand (Components panel ▸
    /// Presets). Values are instance parameters (angles in radians).
    static let presets: [String: [(String, [String: ParamValue])]] = {
        let deg = { (v: Double) in ParamValue.double(v * .pi / 180) }
        let on = ParamValue.bool(true), off = ParamValue.bool(false)
        return [
            "Magic Corner Unit": [("Pulled Out", ["Pulled Out": on])],
            "Blind-Corner Swing-Out": [("Left Hand", ["Left Hand": on])],
            "Corner Storage Basket": [("Right Corner", ["Left Corner": off])],
            "Appliance Lift Mechanism": [("Raised", ["Raised": on])],
            "Mixer Lift Mechanism": [("Raised", ["Lift Angle": deg(80)])],
            "Pull-Out Worktop": [("Pulled Out", ["Pull Out": .double(CC.mm(350))])],
            "Fold-Down Worktop": [("Folded", ["Folded": on])],
            "Utensil Tray": [("Top Tray Back", ["Upper Tray Position": .double(CC.mm(220))])],
            "Electric Standing Desk Frame": [("Standing 44\"", ["Desk Height": .double(CC.inch(44))])],
            "Manual Crank Desk Frame": [("Standing 42\"", ["Desk Height": .double(CC.inch(42))])],
            "Height-Adjustable Desk Mechanism": [("Standing 42\"", ["Desk Height": .double(CC.inch(42))])],
            "Folding Table Hinge": [("Folded", ["Folded": on])],
            "Drop-Leaf Support": [("Closed", ["Open": off])],
            "Table Extension Slide": [("Extended 20\"", ["Extension": .double(CC.inch(20))])],
            "Butterfly Leaf Mechanism": [("Unfolded", ["Unfolded": on])],
            "Keyboard Tray": [("Stowed", ["Pull Out": .double(0)])],
            "Under-Desk Drawer": [("Open", ["Pull Out": .double(CC.inch(10))])],
            "Desk Task Light": [("Low Arm", ["Arm Angle": deg(35)])],
            "Gas Lift Bed Mechanism": [("Open 40°", ["Open Angle": deg(40)])],
            "Hydraulic Storage Bed Lift": [("Raised", ["Lift Angle": deg(60)])],
            "Bed Storage Hinge": [("Open 70°", ["Open Angle": deg(70)])],
            "Folding Bed Mechanism": [("Folded", ["Folded": on])],
            "Murphy Bed Mechanism": [("Open", ["Open Angle": deg(90)])],
            "Recliner Mechanism": [("Reclined", ["Reclined": on])],
            "Manual Recliner Mechanism": [("Reclined", ["Reclined": on])],
            "Electric Recliner Mechanism": [("Reclined", ["Reclined": on])],
            "Sofa Bed Mechanism": [("Open", ["Open": on])],
            "Pull-Out Sofa Bed Frame": [("Pulled Out", ["Pull Out": .double(CC.inch(30))])],
            "Armrest Hinge": [("Raised 45°", ["Arm Angle": deg(45)])],
            "Adjustable Headrest Mechanism": [("Tilted 30°", ["Tilt Angle": deg(30)])],
            "Gas Lift Cylinder": [("Fully Raised", ["Extension": .double(CC.mm(120))])],
            "Tilt Mechanism": [("Tilted 12°", ["Tilt Angle": deg(12)])],
            "Chair Recline Mechanism": [("Reclined 20°", ["Recline Angle": deg(20)])],
            "Adjustable Armrest": [("Raised 10\"", ["Arm Height": .double(CC.inch(10))])],
            "Lumbar Support Mechanism": [("Low", ["Lumbar Height": .double(CC.mm(-40))])],
            "Chair Headrest Mechanism": [("Raised and Tilted", ["Headrest Height": .double(CC.mm(120)), "Tilt Angle": deg(15)])],
            "Folding Chair Hinge": [("Folded", ["Folded": on])],
            "Seat Height Adjuster": [("Left Side", ["Right Side": off])],
            "Armrest Support": [("Left Arm", ["Right Arm": off])],
        ]
    }()
}

/// Type value constants (meters).
enum CC {
    static func mm(_ v: Double) -> Double { v / 1000 }
    static func inch(_ v: Double) -> Double { v * 0.0254 }
}

/// Expression helpers.
extension CX {
    /// "(a) + (b)".
    static func add(_ a: String, _ b: String) -> String { "(\(a)) + (\(b))" }
    /// "(a) - (b)".
    static func sub(_ a: String, _ b: String) -> String { "(\(a)) - (\(b))" }
    /// "(a) * k".
    static func mul(_ a: String, _ k: Double) -> String { "(\(a)) * \(LX.num(k))" }
    /// "(a) / 2".
    static func half(_ a: String) -> String { "(\(a)) / 2" }
    /// "-(a)".
    static func neg(_ a: String) -> String { "-(\(a))" }
    /// a + (b - a) * t: a point a fraction of the way from a to b.
    static func lerp(_ a: String, _ b: String, _ t: Double) -> String { "(\(a)) + ((\(b)) - (\(a))) * \(LX.num(t))" }
}

extension ComponentBuilder {
    // MARK: Rods and struts

    /// A smooth cylinder along a family axis, as a polygon (`segments` sides) so small radii build too (a circle
    /// profile is tessellated at a 2 mm chord, too coarse under ~3 mm radius): `center` as in `cylinder`.
    @discardableResult
    mutating func cyl(_ n: String, axis: FamilyAxis, center: (String, String), radius: String, from: String, to: String, segments: Int = 24, void: Bool = false) -> String {
        let plane: FamilySketchPlane = axis == .z ? .xy : (axis == .y ? .xz : .yz)
        return extrusion(n, profile: ComponentKit.circle(center: center, radius: radius, segments: segments), plane: plane, from: from, to: to, void: void)
    }

    /// A round rod along X, centred at (y, z), `d` its diameter.
    mutating func rodX(_ n: String, y: String, z: String, d: String, from: String, to: String) {
        cyl(n, axis: .x, center: (y, z), radius: CX.half(d), from: from, to: to, segments: 20)
    }
    /// A round rod along Y, centred at (x, z).
    mutating func rodY(_ n: String, x: String, z: String, d: String, from: String, to: String) {
        cyl(n, axis: .y, center: (x, z), radius: CX.half(d), from: from, to: to, segments: 20)
    }
    /// A round rod along Z, centred at (x, y).
    mutating func rodZ(_ n: String, x: String, y: String, d: String, from: String, to: String) {
        cyl(n, axis: .z, center: (x, y), radius: CX.half(d), from: from, to: to, segments: 20)
    }

    /// A round rod from a to b in any direction on a sketch plane (a sweep of a circle), at depth `at` along the
    /// plane's normal: struts, gas springs, wire bends.
    mutating func strut(_ n: String, plane: FamilySketchPlane, _ a: (String, String), _ b: (String, String), at: String, d: String, segments: Int = 12) {
        sweep(n, path: [FamilyPoint(a.0, a.1), FamilyPoint(b.0, b.1)], profile: ComponentKit.circle(radius: CX.half(d), segments: segments), plane: plane, at: at)
    }
    /// A bent rod through several points on a sketch plane.
    mutating func wire(_ n: String, plane: FamilySketchPlane, _ pts: [(String, String)], at: String, d: String, segments: Int = 10) {
        sweep(n, path: ComponentKit.points(pts), profile: ComponentKit.circle(radius: CX.half(d), segments: segments), plane: plane, at: at)
    }
    /// A flat link (linkage arm, bracket strap) from a to b on a sketch plane: `width` in the plane, `thickness` along its
    /// normal, centred at depth `at`.
    mutating func link(_ n: String, plane: FamilySketchPlane, _ a: (String, String), _ b: (String, String), at: String, width: String, thickness: String) {
        sweep(n, path: [FamilyPoint(a.0, a.1), FamilyPoint(b.0, b.1)], profile: ComponentKit.rect(width: width, height: thickness), plane: plane, at: at)
    }

    // MARK: Plates, trays, baskets

    /// A plate with rounded corners in plan between z0 and z1.
    mutating func plate(_ n: String, center: (String, String) = (CX.zero, CX.zero), width: String, depth: String, radius: String, z: (String, String)) {
        roundedBar(n, plane: .xy, center: center, width: width, height: depth, radius: radius, from: z.0, to: z.1)
    }

    /// An open tray: a floor `floor` thick and four walls `wall` thick, inside the box x × y × z.
    mutating func tray(_ n: String, x: (String, String), y: (String, String), z: (String, String), wall: String, floor: String) {
        box("\(n) Floor", x: x, y: y, z: (z.0, CX.add(z.0, floor)))
        box("\(n) Left Wall", x: (x.0, CX.add(x.0, wall)), y: y, z: z)
        box("\(n) Right Wall", x: (CX.sub(x.1, wall), x.1), y: y, z: z)
        box("\(n) Front Wall", x: (CX.add(x.0, wall), CX.sub(x.1, wall)), y: (y.0, CX.add(y.0, wall)), z: z)
        box("\(n) Back Wall", x: (CX.add(x.0, wall), CX.sub(x.1, wall)), y: (CX.sub(y.1, wall), y.1), z: z)
    }

    /// A wire basket: a thin perforated floor, a rim rod all round at the top and a gallery rod halfway up, corner posts.
    mutating func basket(_ n: String, x: (String, String), y: (String, String), z: (String, String), wire: String) {
        let r = CX.half(wire)
        box("\(n) Floor", x: x, y: y, z: (z.0, CX.add(z.0, CX.mm(1.5))))
        for (k, zz) in [CX.sub(z.1, r), CX.lerp(z.0, z.1, 0.5)].enumerated() {
            let tag = k == 0 ? "Rim" : "Gallery"
            rodX("\(n) \(tag) Front", y: CX.add(y.0, r), z: zz, d: wire, from: x.0, to: x.1)
            rodX("\(n) \(tag) Back", y: CX.sub(y.1, r), z: zz, d: wire, from: x.0, to: x.1)
            rodY("\(n) \(tag) Left", x: CX.add(x.0, r), z: zz, d: wire, from: y.0, to: y.1)
            rodY("\(n) \(tag) Right", x: CX.sub(x.1, r), z: zz, d: wire, from: y.0, to: y.1)
        }
        for (cx, cy) in [(CX.add(x.0, r), CX.add(y.0, r)), (CX.sub(x.1, r), CX.add(y.0, r)), (CX.add(x.0, r), CX.sub(y.1, r)), (CX.sub(x.1, r), CX.sub(y.1, r))] {
            rodZ("\(n) Post", x: cx, y: cy, d: wire, from: z.0, to: z.1)
        }
    }

    /// A pair of slide runners on the inside faces of an opening `width` wide (legacyOpening frame), over y, centred at
    /// height z.
    mutating func sideRunners(_ n: String, width: String, y: (String, String), z: String, height: String, thickness: String) {
        let zr = (CX.sub(z, CX.half(height)), CX.add(z, CX.half(height)))
        box("\(n) Left", x: (CX.zero, thickness), y: y, z: zr)
        box("\(n) Right", x: (CX.sub(width, thickness), width), y: y, z: zr)
    }

    /// Two bottom-mount runners (a full-extension pull-out's floor slides) at x0 and x1, over y, from z 0 up `height`.
    mutating func floorRunners(_ n: String, x: (String, String), y: (String, String), width: String, height: String) {
        for (k, cx) in [x.0, x.1].enumerated() {
            box("\(n) \(k == 0 ? "Left" : "Right")", x: (CX.sub(cx, CX.half(width)), CX.add(cx, CX.half(width))), y: y, z: (CX.zero, height))
        }
    }

    /// A swivel plate caster hanging below `top` at (x, y): mounting plate, swivel housing, fork and wheel (plan frame).
    mutating func caster(_ n: String, x: String, y: String, top: String, wheel: String, wheelWidth: String, plateSize: String) {
        let h = CX.add(wheel, CX.mm(12))
        plate("\(n) Plate", center: (x, y), width: plateSize, depth: plateSize, radius: CX.mul(plateSize, 0.12), z: (CX.sub(top, CX.mm(3)), top))
        cyl("\(n) Swivel", axis: .z, center: (x, y), radius: CX.mul(wheel, 0.32), from: CX.sub(top, CX.mm(9)), to: CX.sub(top, CX.mm(3)))
        box("\(n) Fork", x: (CX.sub(x, CX.add(CX.half(wheelWidth), CX.mm(3))), CX.add(x, CX.add(CX.half(wheelWidth), CX.mm(3)))),
            y: (CX.sub(y, CX.mul(wheel, 0.2)), CX.add(y, CX.mul(wheel, 0.45))), z: (CX.sub(top, CX.mul(h, 0.55)), CX.sub(top, CX.mm(9))))
        cyl("\(n) Wheel", axis: .x, center: (CX.add(y, CX.mul(wheel, 0.15)), CX.sub(CX.sub(top, h), CX.neg(CX.half(wheel)))), radius: CX.half(wheel),
                 from: CX.sub(x, CX.half(wheelWidth)), to: CX.add(x, CX.half(wheelWidth)))
    }

    // MARK: Visibility

    /// Runs `body` with new solids shown by the Yes/No parameter `v` (nil: always).
    mutating func shown(_ v: String?, _ body: (inout ComponentBuilder) -> Void) {
        let old = visibility
        visibility = v
        body(&self)
        visibility = old
    }

    /// A formula Yes/No parameter (not editable) that shows repeated pieces: "Show Basket 3" = Basket Count >= 3.
    mutating func countFlag(_ name: String, _ formula: String) { flag(name, false, formula: formula) }

    // MARK: Symbols

    /// The usual symbol set: at Coarse an outline in plan (`plan` view) and in front elevation (`elevation` view);
    /// at Medium and Fine the 3D geometry shows (solids are Medium/Fine for face-mounted hardware).
    /// Face-based items pass plan: .top, elevation: .face (their family Y is up the host face). Each view's
    /// rectangle is in that view's own coordinates: face (x, y), top (x, z), side (z, y).
    mutating func outlines(plan: ComponentSymbolView = .face, elevation: ComponentSymbolView = .top, x: (String, String), y: (String, String), z: (String, String)) {
        func outline(_ v: ComponentSymbolView) -> ComponentSymbolShape {
            switch v {
            case .face: .rect((x.0, y.0), (x.1, y.1))
            case .top: .rect((x.0, z.0), (x.1, z.1))
            case .side: .rect((z.0, y.0), (z.1, y.1))
            }
        }
        symbol(plan, [.coarse], outline(plan))
        symbol(elevation, [.coarse], outline(elevation))
    }

    /// Kitchen / bay items: the opening parameters (instance, sized from the bay) and their requirements.
    mutating func openingParameters(width: Double, depth: Double, height: Double, minWidth: Double? = nil, maxWidth: Double? = nil) {
        length("Opening Width", width, instance: true, group: .placement, min: minWidth, max: maxWidth)
        length("Opening Depth", depth, instance: true, group: .placement)
        length("Opening Height", height, instance: true, group: .placement)
    }
}
