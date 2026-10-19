import Foundation
import ArcusGeometry

// FM4: local families for the part shapes that aren't plane-bounded boxes: legs (square tapered, round, turned,
// hairpin, sled, plinth block, caster) and edge profile voids (round-over, chamfer, bullnose, ogee, cove, finger pull,
// groove). Their sizes are numbers from the type; their length follows the "Height" or "Length" parameter, which the
// compiled family binds to the planes the part spans.

/// Leg shapes as local families: the leg's centre at the origin, its foot at z = 0 and its top at z = Height.
public enum FurnitureLegShapes {
    static func n(_ v: Double) -> String { PartSolidContext.number(v) }
    static func p(_ x: Double, _ y: Double) -> FamilyPoint { FamilyPoint(n(x), n(y)) }

    /// A regular polygon of `sides` round a centre (counterclockwise).
    static func ngon(_ c: Vec2, _ r: Double, sides: Int = 24, phase: Double = 0) -> [FamilyPoint] {
        (0..<sides).map { k in
            let a = phase + 2 * .pi * Double(k) / Double(sides)
            return p(c.x + r * cos(a), c.y + r * sin(a))
        }
    }

    static func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> FamilySolid.Profile {
        .rectangle(xMin: .expr(n(x0)), xMax: .expr(n(x1)), yMin: .expr(n(y0)), yMax: .expr(n(y1)))
    }

    static func solid(_ name: String, _ profile: FamilySolid.Profile, _ z0: String, _ z1: String) -> FamilySolid {
        FamilySolid(name: name, profile: profile, zMin: .expr(z0), zMax: .expr(z1), materialParameter: "Material")
    }

    /// The leg's local family for its type at `height`.
    public static func family(_ tv: FurniturePartTypes.Values, height: Double) -> FamilyDefinition {
        var f = FamilyDefinition(name: "\(tv.legShape.rawValue) Leg \(n(tv.width))x\(n(tv.depth))x\(n(tv.taper))x\(n(tv.rod))", template: .furniture)
        f.parameters = [FamilyParameter(name: "Height", type: .length), FamilyParameter(name: "Material", type: .elementRef(.materials), group: .materials)]
        var values: [String: ParamValue] = ["Height": .double(height)]
        if let mat = tv.material { values["Material"] = .ref(mat) }
        f.types = [FamilyTypeDefinition(name: "Leg", values: values)]
        let w = tv.width, d = tv.depth, rod = max(tv.rod, 0.003)
        // FM9: offsets from Height are written as lengths ("Height - 0.003 m"), so the leg evaluates in compiled families.
        switch tv.legShape {
        case .square:
            if tv.taper > Tolerance.length {
                let b = tv.taper
                f.solids = [solid("Leg", .blend(FamilyBlend(bottom: [p(-b / 2, -b / 2), p(b / 2, -b / 2), p(b / 2, b / 2), p(-b / 2, b / 2)],
                                                            top: [p(-w / 2, -d / 2), p(w / 2, -d / 2), p(w / 2, d / 2), p(-w / 2, d / 2)])), "0", "Height")]
            } else {
                f.solids = [solid("Leg", rect(-w / 2, -d / 2, w / 2, d / 2), "0", "Height")]
            }
        case .plinthBlock:
            f.solids = [solid("Block", rect(-w / 2, -d / 2, w / 2, d / 2), "0", "Height")]
        case .round:
            if tv.taper > Tolerance.length {
                f.solids = [solid("Leg", .blend(FamilyBlend(bottom: ngon(.zero, tv.taper / 2), top: ngon(.zero, w / 2))), "0", "Height")]
            } else {
                f.solids = [solid("Leg", .circle(center: p(0, 0), radius: n(w / 2)), "0", "Height")]
            }
        case .turned:
            // A classic turned leg (radius as a fraction of the size, height as a fraction of Height): foot, vase, bead
            // and cove, and a full-size top block for the apron.
            let prof: [(Double, Double)] = [(0, 0), (0.30, 0), (0.30, 0.03), (0.38, 0.05), (0.30, 0.08), (0.22, 0.16), (0.26, 0.40),
                                           (0.34, 0.54), (0.26, 0.62), (0.40, 0.66), (0.40, 0.70), (0.30, 0.72), (0.50, 0.75), (0.50, 1), (0, 1)]
            let pts = prof.map { FamilyPoint(.expr(n($0.0 * w)), .expr("Height * \(n($0.1))")) }
            f.solids = [solid("Leg", .revolve(FamilyRevolve(profile: pts)), "0", "Height")]
        case .hairpin:
            // Two rods from the foot to the top plate, splayed across the leg's width; a 3/16" plate on top.
            let plate = 0.1875 * 0.0254
            let spread = max(w / 2 - rod, rod)
            f.solids = [solid("Plate", rect(-w / 2, -rod * 2, w / 2, rod * 2), "Height - \(n(plate)) m", "Height")]
            for (k, sx) in [-1.0, 1.0].enumerated() {
                f.solids.append(solid("Rod \(k + 1)", .blend(FamilyBlend(bottom: ngon(Vec2(sx * rod * 0.6, 0), rod / 2, sides: 8),
                                                                         top: ngon(Vec2(sx * spread, 0), rod / 2, sides: 8))), "0", "Height - \(n(plate)) m"))
            }
        case .sled:
            // A tube frame across the depth: runner, two posts and a top bar.
            let t = rod, half = max(d / 2, t)
            f.solids = [solid("Runner", rect(-w / 2, -half, w / 2, half), "0", n(t)),
                        solid("Top Bar", rect(-w / 2, -half, w / 2, half), "Height - \(n(t)) m", "Height"),
                        solid("Post 1", rect(-w / 2, -half, w / 2, -half + t), n(t), "Height - \(n(t)) m"),
                        solid("Post 2", rect(-w / 2, half - t, w / 2, half), n(t), "Height - \(n(t)) m")]
        case .caster:
            // Mounting plate, fork and wheel; the wheel fills most of the height. (FM9B: offsets from Height carry their
            // unit, so the compiled family evaluates.)
            let plate = 0.125 * 0.0254
            f.solids = [solid("Plate", rect(-w / 2, -w / 2, w / 2, w / 2), "Height - \(n(plate)) m", "Height"),
                        solid("Fork", rect(-w * 0.18, -w * 0.3, w * 0.18, w * 0.3), "Height * 0.45", "Height - \(n(plate)) m")]
            var wheel = FamilySolid(name: "Wheel", profile: .circle(center: FamilyPoint(.expr("0"), .expr("Height * 0.3")), radius: "Height * 0.3"),
                                    zMin: .expr(n(-w * 0.12)), zMax: .expr(n(w * 0.12)), materialParameter: "Material")
            wheel.workPlane = .xz
            f.solids.append(wheel)
        }
        return f
    }
}

/// Edge profile voids as local families: the corner at the origin, the edge along `edgeAxis` from 0 to Length.
public enum EdgeProfileShapes {
    static let margin = 0.0008

    /// The removed region next to a box edge, in inward coordinates: a along the first cross axis into the material,
    /// b along the second (the material is at a, b ≥ 0). It reaches a little outside the faces, so the cut is clean.
    public static func voidProfile(_ shape: EdgeProfileShape, size s: Double, depth: Double, offset: Double, inSecondFace: Bool,
                                   thickness1 t1: Double, thickness2 t2: Double) -> [Vec2] {
        let m = margin
        func arc(_ c: Vec2, _ r: Double, from a0: Double, to a1: Double, steps: Int = 10) -> [Vec2] {
            (0...steps).map { k in let a = a0 + (a1 - a0) * Double(k) / Double(steps); return c + Vec2(cos(a), sin(a)) * r }
        }
        switch shape {
        case .chamfer:
            return [Vec2(-m, -m), Vec2(s, -m), Vec2(s, 0), Vec2(0, s), Vec2(-m, s)]
        case .roundOver:
            return [Vec2(-m, -m), Vec2(s, -m)] + arc(Vec2(s, s), s, from: -.pi / 2, to: -.pi) + [Vec2(-m, s)]
        case .cove:
            return [Vec2(-m, -m), Vec2(s, -m)] + arc(.zero, s, from: 0, to: .pi / 2) + [Vec2(-m, s)]
        case .fingerPull:
            // A long cove into the first face.
            let ra = s * 0.6, rb = s
            let pts = (0...12).map { k -> Vec2 in let a = Double.pi / 2 * Double(k) / 12; return Vec2(ra * cos(a), rb * sin(a)) }
            return [Vec2(-m, -m), Vec2(ra, -m)] + pts + [Vec2(-m, rb)]
        case .ogee:
            // An S-curve from (s, 0) to (0, s): cove at the top, round-over below.
            let pts = (0...16).map { k -> Vec2 in
                let t = Double(k) / 16
                return Vec2(s * (1 - t), s * (0.5 - 0.5 * cos(.pi * t)))
            }
            return [Vec2(-m, -m), Vec2(s, -m)] + pts + [Vec2(-m, s)]
        case .bullnose:
            // A half round across the thinner side.
            if t2 <= t1 {
                let r = min(s, t2) / 2
                return [Vec2(-m, -m), Vec2(r, -m)] + arc(Vec2(r, r), r, from: -.pi / 2, to: -3 * .pi / 2, steps: 16) + [Vec2(r, 2 * r + m), Vec2(-m, 2 * r + m)]
            }
            let r = min(s, t1) / 2
            return [Vec2(-m, -m), Vec2(2 * r + m, -m), Vec2(2 * r + m, r)] + arc(Vec2(r, r), r, from: 0, to: -.pi, steps: 16) + [Vec2(-m, r)]
        case .groove:
            let w = s, dd = max(depth, Tolerance.length)
            if inSecondFace { return [Vec2(offset, -m), Vec2(offset + w, -m), Vec2(offset + w, dd), Vec2(offset, dd)] }
            return [Vec2(-m, offset), Vec2(dd, offset), Vec2(dd, offset + w), Vec2(-m, offset + w)]
        }
    }

    /// The void's local family: the inward profile turned to the corner's sides (`signs`: +1 when the material lies
    /// toward +axis), on the plane across the edge, from 0 to Length along it.
    public static func family(name: String, edgeAxis: FamilyAxis, signs: (Double, Double), profile: [Vec2], length: Double) -> FamilyDefinition {
        var f = FamilyDefinition(name: "\(name) \(edgeAxis.rawValue)\(signs.0 > 0 ? "+" : "-")\(signs.1 > 0 ? "+" : "-") \(profile.count)", template: .genericModel)
        f.parameters = [FamilyParameter(name: "Length", type: .length)]
        f.types = [FamilyTypeDefinition(name: "Edge", values: ["Length": .double(length)])]
        let plane = FamilySketchPlane.normal(edgeAxis)
        let pts = Polygon2(profile.map { Vec2(signs.0 * $0.x, signs.1 * $0.y) }).counterClockwise.points
        var s = FamilySolid(name: name, profile: .polygon(pts.map { FamilyPoint(PartSolidContext.number($0.x), PartSolidContext.number($0.y)) }),
                            zMin: .expr("0"), zMax: .expr("Length"), isVoid: true)
        if plane != .xy { s.workPlane = plane }
        f.solids = [s]
        return f
    }
}
