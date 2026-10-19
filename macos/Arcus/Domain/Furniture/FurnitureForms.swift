import Foundation
import ArcusGeometry

// FM4: Create ▸ Forms in Furniture documents: Extrusion, Blend, Revolve, Sweep, Swept Blend, their voids, and Cushion.
// A form keeps its sketch in numbers (`FurnitureFormData`) and is written as the Family Editor's `FamilySolid`, so the
// display (FamilyEvaluator → meshes) and Load into Project use the family form code unchanged.

public enum FurnitureForms {
    static func n(_ v: Double) -> String { PartSolidContext.number(v) }
    static func pts(_ p: [Vec2]) -> [FamilyPoint] { p.map { FamilyPoint(n($0.x), n($0.y)) } }

    /// The form's solids (numbers; forms don't follow planes).
    public static func solids(_ e: Element, _ f: FurnitureFormData, _ m: BIMModel, _ ctx: PartSolidContext) -> PartSolids {
        var out = PartSolids()
        let name = e.mark.isEmpty ? f.kind.rawValue : e.mark
        var list: [FamilySolid] = []
        switch f.kind {
        case .extrusion:
            guard f.profile.count >= 3, abs(f.w1 - f.w0) > Tolerance.length else { return out }
            var s = FamilySolid(name: name, profile: .polygon(pts(Polygon2(f.profile).counterClockwise.points)), zMin: .expr(n(min(f.w0, f.w1))),
                                zMax: .expr(n(max(f.w0, f.w1))), isVoid: f.isVoid)
            if f.plane != .xy { s.workPlane = f.plane }
            list.append(s)
            for (k, h) in f.holes.enumerated() where h.count >= 3 {
                var v = FamilySolid(name: "\(name) Hole \(k + 1)", profile: .polygon(pts(Polygon2(h).counterClockwise.points)),
                                    zMin: .expr(n(min(f.w0, f.w1) - 0.001)), zMax: .expr(n(max(f.w0, f.w1) + 0.001)), isVoid: true)
                if f.plane != .xy { v.workPlane = f.plane }
                list.append(v)
            }
        case .blend:
            guard f.profile.count >= 3, let top = f.topProfile, top.count >= 3, f.w1 - f.w0 > Tolerance.length else { return out }
            list.append(FamilySolid(name: name, profile: .blend(FamilyBlend(bottom: pts(Polygon2(f.profile).counterClockwise.points), top: pts(Polygon2(top).counterClockwise.points))),
                                    zMin: .expr(n(f.w0)), zMax: .expr(n(f.w1)), isVoid: f.isVoid))
        case .revolve:
            guard f.profile.count >= 3 else { return out }
            let axis = f.axis ?? .zero
            list.append(FamilySolid(name: name, profile: .revolve(FamilyRevolve(profile: pts(f.profile), axis: FamilyPoint(n(axis.x), n(axis.y)),
                                                                                startDegrees: n(f.startAngle * 180 / .pi), endDegrees: n(f.endAngle * 180 / .pi))),
                                    zMin: .expr(n(f.w0)), zMax: .expr(n(f.w0)), isVoid: f.isVoid))
        case .sweep, .sweptBlend:
            guard let path = f.path, path.count >= 2, f.profile.count >= 3 else { return out }
            let end = f.kind == .sweptBlend ? f.endProfile.map(pts) : nil
            list.append(FamilySolid(name: name, profile: .sweep(FamilySweep(path: pts(path), profile: pts(f.profile), endProfile: end)),
                                    zMin: .expr(n(f.w0)), zMax: .expr(n(f.w0)), isVoid: f.isVoid))
        case .cushion:
            guard let c = f.cushion else { return out }
            list = cushion(name, c, z0: f.w0)
        }
        for var s in list {
            s.visibleAt = f.visibleAt
            out.solids.append(s)
            if !s.isVoid { out.materials[s.id] = f.materialID }
        }
        return out
    }

    /// A rounded rectangle (counterclockwise) of `w` × `d` with corner radius `r`, turned by `rotation` about `c`.
    public static func roundedRect(_ c: Vec2, _ w: Double, _ d: Double, _ r: Double, rotation: Double = 0, steps: Int = 6) -> [Vec2] {
        let rr = max(0, min(r, min(w, d) / 2 - 1e-5))
        let hw = w / 2, hd = d / 2
        var out: [Vec2] = []
        let corners = [(Vec2(hw - rr, -hd + rr), -Double.pi / 2), (Vec2(hw - rr, hd - rr), 0), (Vec2(-hw + rr, hd - rr), Double.pi / 2), (Vec2(-hw + rr, -hd + rr), Double.pi)]
        for (cc, a0) in corners {
            if rr <= 1e-6 { out.append(cc); continue }
            for k in 0...steps { let a = a0 + Double.pi / 2 * Double(k) / Double(steps); out.append(cc + Vec2(cos(a), sin(a)) * rr) }
        }
        let t = Transform2.translation(c) * Transform2.rotation(rotation)
        return out.map(t.apply)
    }

    /// Cushion: a body with rounded corners, a crowned top and piping round the seams.
    static func cushion(_ name: String, _ c: CushionSpec, z0: Double) -> [FamilySolid] {
        let crown = max(0, min(c.crown, c.height * 0.45))
        let loop = roundedRect(c.center, c.width, c.depth, c.cornerRadius, rotation: c.rotation)
        let inset = min(c.width, c.depth) * 0.08 + crown
        let topLoop = roundedRect(c.center, max(0.01, c.width - 2 * inset), max(0.01, c.depth - 2 * inset), max(0, c.cornerRadius - inset / 2), rotation: c.rotation)
        let seam = z0 + c.height - crown
        var out = [FamilySolid(name: "\(name) Body", profile: .polygon(pts(loop)), zMin: .expr(n(z0)), zMax: .expr(n(seam)))]
        if crown > Tolerance.length {
            out.append(FamilySolid(name: "\(name) Crown", profile: .blend(FamilyBlend(bottom: pts(loop), top: pts(topLoop))), zMin: .expr(n(seam)), zMax: .expr(n(seam + crown))))
        }
        let r = c.pipingDiameter / 2
        if r > Tolerance.length {
            let circle = (0..<12).map { k -> Vec2 in let a = 2 * Double.pi * Double(k) / 12; return Vec2(r * cos(a), r * sin(a)) }
            // The path runs clockwise so the piping profile's "left" points out of the cushion (it sits on the seam).
            let path = loop + [loop[0]]
            for (on, z, label) in [(c.topPiping, seam, "Top Piping"), (c.bottomPiping, z0 + r, "Bottom Piping")] where on {
                out.append(FamilySolid(name: "\(name) \(label)", profile: .sweep(FamilySweep(path: pts(path), profile: pts(circle.map { Vec2($0.x, $0.y) }))),
                                       zMin: .expr(n(z)), zMax: .expr(n(z))))
            }
        }
        return out
    }
}
