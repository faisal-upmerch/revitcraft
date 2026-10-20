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
        if let f = ComponentLegTypes.family(tv, height: height) { return f } // COMPB: Leg types from the Component Library
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
            // FMG1: a classic turned leg as a turner leaves it: a square pommel (the top quarter) where the aprons join, and
            // the turned body below it (foot, vase, bead and cove; radius as a fraction of the size). The body is a nested
            // family, so joint cuts (mortises, which FM6 cuts in the leg's own solids) reach only the pommel, a box cut
            // exactly, never the revolve (a mesh Boolean on a revolve made a piece with turned legs take over a minute).
            f.solids = [solid("Pommel", rect(-w / 2, -w / 2, w / 2, w / 2), "Height * \(n(Self.pommelStart))", "Height")]
            let body = turnedBody(tv, height: height * Self.pommelStart)
            f.nestedFamilies = [body]
            var inst = NestedFamilyInstance(familyName: body.name, typeName: body.types.first?.name, bindings: ["Height": "Height * \(n(Self.pommelStart))"])
            inst.id = "turned-body"
            if tv.material != nil { inst.bindings["Material"] = "Material" }
            f.nestedInstances = [inst]
        case .hairpin:
            // Two rods from the foot to the top plate, splayed across the leg's width; a 3/16" plate on top.
            let plate = 0.1875 * 0.0254
            let spread = max(w / 2 - rod, rod)
            f.solids = [solid("Plate", rect(-w / 2, -rod * 2, w / 2, rod * 2), "Height - \(n(plate)) m", "Height")]
            for (k, sx) in [-1.0, 1.0].enumerated() {
                f.solids.append(solid("Rod \(k + 1)", .blend(FamilyBlend(bottom: ngon(Vec2(sx * rod * 0.6, 0), rod / 2), // VIS: round rods
                                                                         top: ngon(Vec2(sx * spread, 0), rod / 2))), "0", "Height - \(n(plate)) m"))
            }
        case .sled:
            // A tube frame across the depth: runner, two posts and a top bar.
            let t = rod, half = max(d / 2, t)
            f.solids = [solid("Runner", rect(-w / 2, -half, w / 2, half), "0", n(t)),
                        solid("Top Bar", rect(-w / 2, -half, w / 2, half), "Height - \(n(t)) m", "Height"),
                        solid("Post 1", rect(-w / 2, -half, w / 2, -half + t), n(t), "Height - \(n(t)) m"),
                        solid("Post 2", rect(-w / 2, half - t, w / 2, half), n(t), "Height - \(n(t)) m")]
        case .caster:
            // VIS: a swivel caster as it's made: mounting plate, a round swivel, a fork whose two cheeks hold the wheel
            // on its axle, and the wheel filling most of the height. (FM9C: offsets from Height are lengths.)
            let plate = 0.125 * 0.0254
            let tw = w * 0.12, cheek = w * 0.035, gap = w * 0.015
            f.solids = [solid("Plate", rect(-w / 2, -w / 2, w / 2, w / 2), "Height - \(n(plate)) m", "Height"),
                        solid("Swivel", .circle(center: p(0, 0), radius: n(w * 0.3)), "Height * 0.84", "Height - \(n(plate)) m"),
                        solid("Fork Bridge", rect(-w * 0.16, -(tw + gap + cheek), w * 0.16, tw + gap + cheek), "Height * 0.76", "Height * 0.84")]
            for (k, side) in [-1.0, 1.0].enumerated() {
                let y0 = side * (tw + gap), y1 = side * (tw + gap + cheek)
                f.solids.append(solid("Fork Cheek \(k + 1)", rect(-w * 0.16, min(y0, y1), w * 0.16, max(y0, y1)), "Height * 0.18", "Height * 0.76"))
            }
            var wheel = FamilySolid(name: "Wheel", profile: .circle(center: FamilyPoint(.expr("0"), .expr("Height * 0.3")), radius: "Height * 0.3"),
                                    zMin: .expr(n(-tw)), zMax: .expr(n(tw)), materialParameter: "Material")
            wheel.workPlane = .xz
            var axle = FamilySolid(name: "Axle", profile: .circle(center: FamilyPoint(.expr("0"), .expr("Height * 0.3")), radius: n(w * 0.06)),
                                   zMin: .expr(n(-(tw + gap + cheek * 1.4))), zMax: .expr(n(tw + gap + cheek * 1.4)), materialParameter: "Material")
            axle.workPlane = .xz
            f.solids += [wheel, axle]
        }
        return f
    }

    /// FMG1: where a turned leg's square pommel starts, as a share of its height.
    static let pommelStart = 0.75

    /// FMG1: the turned body of a turned leg (below its pommel) as a local family: a revolve whose radii are shares of the
    /// leg's size and whose heights are shares of the body's Height.
    static func turnedBody(_ tv: FurniturePartTypes.Values, height: Double) -> FamilyDefinition {
        let w = tv.width
        var f = FamilyDefinition(name: "Turned Leg Body \(n(w))", template: .furniture)
        f.parameters = [FamilyParameter(name: "Height", type: .length), FamilyParameter(name: "Material", type: .elementRef(.materials), group: .materials)]
        var values: [String: ParamValue] = ["Height": .double(height)]
        if let mat = tv.material { values["Material"] = .ref(mat) }
        f.types = [FamilyTypeDefinition(name: "Body", values: values)]
        let pts = turnedProfile(width: w, height: height / pommelStart).map { r, f, d in
            FamilyPoint(.expr(n(r)), .expr("Height * \(n(f / pommelStart))" + (abs(d) < 1e-6 ? "" : (d > 0 ? " + " : " - ") + String(format: "%.6f m", abs(d)))))
        }
        f.solids = [solid("Turned Body", .revolve(FamilyRevolve(profile: pts)), "0", "Height")]
        return f
    }
}

extension FurnitureLegShapes {
    /// VIS: a turned leg's body profile as a turner shapes it, from the foot to the pommel's neck: a foot with a bead, a
    /// taper to the ankle, a vase that swells and narrows, a collar bead and a flare into the pommel. Each point is
    /// (radius in m, height as a share of the whole leg, height offset in m), so beads stay round whatever the leg's height.
    static func turnedProfile(width w: Double, height h: Double) -> [(Double, Double, Double)] {
        let b1 = min(0.05 * w, 0.03 * h), b2 = min(0.07 * w, 0.025 * h) // bead radii (kept clear of the next shape on short legs)
        var out: [(Double, Double, Double)] = [(0, 0, 0), (0.32 * w, 0, 0)]
        /// A bead (half round bulging out) of radius `b` on the face at radius `r`, starting at height share `f`.
        func bead(_ r: Double, _ f: Double, _ b: Double, steps: Int = 8) {
            for k in 0...steps {
                let a = -Double.pi / 2 + Double.pi * Double(k) / Double(steps)
                out.append((r + b * cos(a), f, b + b * sin(a)))
            }
        }
        out.append((0.32 * w, 0.02, 0))
        bead(0.32 * w, 0.02, b1)
        out.append((0.32 * w, 0.02, 2 * b1))
        // Taper to the ankle, then the vase: swelling to its belly and narrowing to the neck (a smooth curve).
        let f0 = 0.10, f1 = 0.62
        for k in 0...8 { // the view refines the curve at Fine (CurveRefinement)
            let t = Double(k) / 8
            let r = (0.22 + 0.02 * t) * w + 0.11 * w * sin(.pi * pow(t, 0.85))
            out.append((r, f0 + (f1 - f0) * t, 0))
        }
        // Collar bead, a short neck, then a flare into the pommel.
        bead(0.24 * w, f1, b2)
        out.append((0.24 * w, f1, 2 * b2))
        out.append((0.26 * w, 0.68, 0))
        for k in 1...4 {
            let t = Double(k) / 4
            out.append(((0.26 + 0.12 * (1 - cos(.pi / 2 * t))) * w, 0.68 + 0.07 * sin(.pi / 2 * t), 0))
        }
        out.append((0, 0.75, 0))
        return out
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
        case .bevel: // COMPD: an unequal chamfer, Size by Depth
            let d = depth > Tolerance.length ? depth : s
            return [Vec2(-m, -m), Vec2(s, -m), Vec2(s, 0), Vec2(0, d), Vec2(-m, d)]
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
