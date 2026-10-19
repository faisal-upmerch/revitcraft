import Foundation
import ArcusGeometry

// COMPD: shared shorthands for group D (16 Lighting & Electrical · 17 Glass & Panels · 18 Edges & Profiles · 19 Motion ·
// 20 Decorative). Conventions used by every group D definition:
// - Face frame (the kit's default): origin at the mounting point on the host face, X along the face, Y up it, Z out of
//   it (host material at Z < 0). Edge items use the edge face: X along the edge, Y across the panel's thickness.
// - Items that run the whole host face (LED profiles, moldings, edge profiles, trims, channels) have an instance
//   parameter Length and are centred on the origin (X from -Length / 2 to Length / 2); their alignment is Full Length.
// - Mount operations whose size is 0 for a type (an if() on a Yes/No) are not machined for that type.

/// Group D's default finishes (found by name in the document, else created).
extension ComponentFinish {
    static let anodized = ComponentFinish("Anodized Aluminum", .metal, RGBColor(hex: 0xC5C9CD))
    static let blackAnodized = ComponentFinish("Anodized Aluminum - Black", .metal, RGBColor(hex: 0x2E3033))
    static let clearPlastic = ComponentFinish("Polycarbonate - Clear", .plastic, RGBColor(hex: 0xDDEBF0), transparency: 0.6)
    static let clearPVC = ComponentFinish("PVC - Clear", .plastic, RGBColor(hex: 0xE4EEF0), transparency: 0.5)
    static let silicone = ComponentFinish("Silicone - Clear", .plastic, RGBColor(hex: 0xE9EFEF), transparency: 0.4)
    static let greyRubber = ComponentFinish("Rubber - Grey", .plastic, RGBColor(hex: 0x6B6E72))
    static let pvcWhite = ComponentFinish("PVC Edge Band - White", .plastic, RGBColor(hex: 0xF4F2EE))
    static let absGrey = ComponentFinish("ABS Edge Band - Grey", .plastic, RGBColor(hex: 0x9A9DA1))
    static let veneerOak = ComponentFinish("Veneer - White Oak", .wood, RGBColor(hex: 0xC9A16E))
    static let hotMelt = ComponentFinish("Edge Banding", .wood, RGBColor(hex: 0xE0C595))
    static let primedMDF = ComponentFinish("MDF - Primed", .paint, RGBColor(hex: 0xF0EEE8))
    static let poplar = ComponentFinish("Solid Poplar", .wood, RGBColor(hex: 0xD6C9A0))
    static let petFelt = ComponentFinish("PET Felt - Charcoal", .generic, RGBColor(hex: 0x4A4C50))
    static let brassMesh = ComponentFinish("Woven Brass Mesh", .metal, RGBColor(hex: 0xC2A563))
    static let vinyl = ComponentFinish("Vinyl - Black", .plastic, RGBColor(hex: 0x262728))
    static let pcb = ComponentFinish("Circuit Board", .plastic, RGBColor(hex: 0x2F5D3A))
    static let antiqueBrass = ComponentFinish("Antique Brass", .metal, RGBColor(hex: 0x8E7442))
}

/// Group D's expression and geometry shorthands.
enum DK {
    static func mm(_ v: Double) -> Double { ComponentKit.mm(v) }
    static func inch(_ v: Double) -> Double { ComponentKit.inch(v) }
    static func feet(_ v: Double) -> Double { ComponentKit.feet(v) }
    static let z = CX.zero
    static let lo = "-Length / 2", hi = "Length / 2"

    /// A point from two expressions.
    static func p(_ u: String, _ v: String) -> FamilyPoint { FamilyPoint(u, v) }
    /// Points from expression pairs.
    static func pts(_ list: [(String, String)]) -> [FamilyPoint] { list.map { FamilyPoint($0.0, $0.1) } }

    /// "a + k * b" style helpers that keep the formulas readable.
    static func half(_ e: String) -> String { "(\(e)) / 2" }
    static func neg(_ e: String) -> String { "-(\(e))" }

    /// A bar section flat at v = 0 with its top corners rounded (light housings, trims), centred on u.
    static func topRounded(width w: String, height h: String, radius r: String) -> [FamilyPoint] {
        [p("-(\(w)) / 2", z), p("(\(w)) / 2", z)] + arc("(\(w)) / 2 - (\(r))", "(\(h)) - (\(r))", r, 0, 90, steps: 6)
            + arc("-(\(w)) / 2 + (\(r))", "(\(h)) - (\(r))", r, 90, 180, steps: 6)
    }

    /// A quarter (or any) arc of expression points about (cu, cv) with radius `r` from `a0` to `a1` degrees.
    static func arc(_ cu: String, _ cv: String, _ r: String, _ a0: Double, _ a1: Double, steps: Int = 8) -> [FamilyPoint] {
        (0...steps).map { k in
            let a = (a0 + (a1 - a0) * Double(k) / Double(steps)) * .pi / 180
            return FamilyPoint("\(cu) + (\(r)) * \(LX.num(cos(a)))", "\(cv) + (\(r)) * \(LX.num(sin(a)))")
        }
    }
}

extension ComponentBuilder {
    /// The Length instance parameter of a full-length item (it follows the host face when placed Full Length).
    mutating func runLength(_ v: Double, min: Double = 0.02, max: Double = 3.0) {
        length("Length", v, instance: true, group: .dimensions, min: min, max: max)
    }

    /// A (Y, Z) profile extruded along the whole Length.
    @discardableResult
    mutating func run(_ name: String, _ profile: [FamilyPoint]) -> String {
        profileAlongX(name, profile: profile, from: DK.lo, to: DK.hi)
    }

    /// A box run along the whole Length.
    @discardableResult
    mutating func runBox(_ name: String, y: (String, String), z: (String, String)) -> String {
        box(name, x: (DK.lo, DK.hi), y: y, z: z)
    }

    /// A smooth cylinder (a 32-sided polygon extruded along `axis`): the kit's circle profile is tessellated coarsely,
    /// so small hardware (pins, LEDs, knobs) would come out faceted or not at all.
    @discardableResult
    mutating func rod(_ name: String, axis: FamilyAxis, center: (String, String), radius: String, from: String, to: String, void: Bool = false,
                      segments: Int = 32) -> String {
        extrusion(name, profile: ComponentKit.circle(center: center, radius: radius, segments: segments), plane: Self.plane(normal: axis), from: from, to: to, void: void)
    }

    /// A smooth tube: two half rings (no void to cut, so it evaluates fast on any plane).
    mutating func pipe(_ name: String, axis: FamilyAxis, center: (String, String), outer: String, inner: String, from: String, to: String, segments: Int = 16) {
        for (k, a0) in [0.0, 180.0].enumerated() {
            func arc(_ r: String, _ from: Double, _ to: Double) -> [FamilyPoint] {
                (0...segments).map { i in
                    let a = (from + (to - from) * Double(i) / Double(segments)) * .pi / 180
                    return FamilyPoint("\(center.0) + (\(r)) * \(LX.num(cos(a)))", "\(center.1) + (\(r)) * \(LX.num(sin(a)))")
                }
            }
            extrusion(k == 0 ? name : "\(name) (2)", profile: arc(outer, a0, a0 + 180) + arc(inner, a0 + 180, a0), plane: Self.plane(normal: axis), from: from, to: to)
        }
    }

    /// Face, top and side outline symbols of a box in the mount frame (Coarse shows the face outline only).
    mutating func outlines(x: (String, String), y: (String, String), z: (String, String), coarse: Bool = true) {
        let all: Set<DetailLevel> = coarse ? [.coarse, .medium, .fine] : [.medium, .fine]
        symbol(.face, all, .rect((x.0, y.0), (x.1, y.1)))
        symbol(.top, [.medium, .fine], .rect((x.0, z.0), (x.1, z.1)))
        symbol(.side, [.medium, .fine], .rect((z.0, y.0), (z.1, y.1)))
    }

    /// Outline symbols of a full-length run of the given cross-section box.
    mutating func runOutlines(y: (String, String), z: (String, String)) {
        outlines(x: (DK.lo, DK.hi), y: y, z: z)
        symbol(.top, [.coarse], .line((DK.lo, z.1), (DK.hi, z.1)))
    }

    /// Round outline symbols (pucks, grommets, rosettes): a circle on the face, the profile box from above and the side.
    mutating func roundOutlines(radius r: String, z: (String, String)) {
        symbol(.face, [.coarse, .medium, .fine], .circle((DK.z, DK.z), r))
        symbol(.top, [.medium, .fine], .rect(("-(\(r))", z.0), (r, z.1)))
        symbol(.side, [.medium, .fine], .rect((z.0, "-(\(r))"), (z.1, r)))
    }

    /// Hosts a full-length item (LED profiles, trims, moldings) on parts' faces or edges.
    mutating func hostRun(_ hosts: [ComponentHostKind], faces: [ComponentFace], offsetY: Double = 0) {
        host(hosts, faces: faces, align: .full, alignments: [.full, .center, .left, .right], offsetY: offsetY)
    }

    /// Two screw pilot holes near the ends of a run (clips, mounting tabs), 2" in from each end.
    mutating func runScrews(_ label: String, diameter: Double = 3, depth: Double = 10, y: String = CX.zero) {
        drill(label, x: "-Length / 2 + 0.0508 m", y: y, diameter: CX.mm(diameter), depth: CX.mm(depth))
        drill(label, x: "Length / 2 - 0.0508 m", y: y, diameter: CX.mm(diameter), depth: CX.mm(depth))
    }

    /// A pair of screw pilot holes `spacing` apart across X at height `y`.
    /// `when` names a Yes/No parameter: the holes are drilled only for types where it's Yes.
    mutating func screwPair(_ label: String, spacing: String, y: String = CX.zero, diameter: Double = 3, depth: Double = 12,
                            target: ComponentMountTarget = .host, when: String? = nil) {
        let d = when.map { "if(\($0), \(CX.mm(diameter)), 0 m)" } ?? CX.mm(diameter)
        drill(label, x: "-(\(spacing)) / 2", y: y, diameter: d, depth: CX.mm(depth), target: target)
        drill(label, x: "(\(spacing)) / 2", y: y, diameter: d, depth: CX.mm(depth), target: target)
    }
}
