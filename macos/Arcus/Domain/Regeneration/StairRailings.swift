import Foundation
import ArcusGeometry

// STAIR: railings, and Revit-style railings on stairs: the path follows one side of the stair continuously up the runs
// and round the landings' edges (never across a landing), on the treads (inset by the Offset from Path) or on the
// stringer; the top rail rises with the nosing line, eases into each run from the landing before it, and extends at the
// bottom (plus one tread depth) and the top; balusters stand on every tread (Balusters per Tread) and at the type's
// spacing on landings; posts at the ends and the landing corners.

/// Parameter ids of railing types.
public enum RailingTypeParam {
    public static let height = ParameterID("railing.height")
    public static let balusterSpacing = ParameterID("railing.balusterSpacing")
    public static let balusterSize = ParameterID("railing.balusterSize")
    public static let railSize = ParameterID("railing.railSize")
    public static let balustersPerTread = ParameterID("railing.balustersPerTread")
    public static let treadOffset = ParameterID("railing.treadOffset")
    public static let topRailShape = ParameterID("railing.topRailShape")
    public static let extensionStyle = ParameterID("railing.extensionStyle")
    public static let extensionLength = ParameterID("railing.extensionLength")
    public static let plusTreadDepth = ParameterID("railing.plusTreadDepth")
    public static let postSize = ParameterID("railing.postSize")
    public static let handrailHeight = ParameterID("railing.handrailHeight")
    public static let handrailSize = ParameterID("railing.handrailSize")
}

/// Extension Style of a top rail's ends on a stair.
public enum RailingExtensionStyle: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case floor = "Floor"
    case wall = "Wall"
    case post = "Post"
}

/// Railing type values.
public struct RailingTypeInfo: Sendable {
    public var height = 1.0
    public var balusterSpacing = 0.12
    public var balusterSize = 0.02
    public var railSize = 0.05
    public var balustersPerTread = 2
    public var treadOffset = 0.05
    public var circularRail = false
    public var extensionStyle = RailingExtensionStyle.floor
    public var extensionLength = 0.3
    public var plusTreadDepth = true
    public var postSize = 0.05
    public var handrailHeight = 0.0
    public var handrailSize = 0.04
    public var material: ElementID?

    public static func of(_ e: Element, _ model: BIMModel) -> RailingTypeInfo {
        var t = RailingTypeInfo()
        guard let p = model.typeData(of: e)?.params else { return t }
        func len(_ id: ParameterID, _ d: Double) -> Double { p[id]?.doubleValue ?? d }
        t.height = len(RailingTypeParam.height, t.height)
        t.balusterSpacing = max(0.03, len(RailingTypeParam.balusterSpacing, t.balusterSpacing))
        t.balusterSize = len(RailingTypeParam.balusterSize, t.balusterSize)
        t.railSize = len(RailingTypeParam.railSize, t.railSize)
        t.balustersPerTread = max(0, p[RailingTypeParam.balustersPerTread]?.intValue ?? t.balustersPerTread)
        t.treadOffset = len(RailingTypeParam.treadOffset, t.treadOffset)
        t.circularRail = (p[RailingTypeParam.topRailShape]?.textValue ?? "Rectangular") == "Circular"
        t.extensionStyle = p[RailingTypeParam.extensionStyle]?.textValue.flatMap(RailingExtensionStyle.init(rawValue:)) ?? t.extensionStyle
        t.extensionLength = len(RailingTypeParam.extensionLength, t.extensionLength)
        t.plusTreadDepth = p[RailingTypeParam.plusTreadDepth]?.boolValue ?? t.plusTreadDepth
        t.postSize = len(RailingTypeParam.postSize, max(t.balusterSize * 2, 0.04))
        t.handrailHeight = len(RailingTypeParam.handrailHeight, 0)
        t.handrailSize = len(RailingTypeParam.handrailSize, t.handrailSize)
        t.material = p[ParameterID("type.material")]?.refValue
        return t
    }
}

/// A railing on a stair, ready to draw and mesh.
public struct StairRailLayout: Sendable {
    /// The railing's base line along the stair side: nosing line on runs, landing height on landings.
    public var base: [Vec3]
    /// Top rail centre line, with the extensions at both ends.
    public var top: [Vec3]
    /// Baluster stations: plan point, bottom (tread or landing surface) and top (under the top rail).
    public var balusters: [(point: Vec2, z0: Double, z1: Double)]
    /// Posts at the ends and the landing corners.
    public var posts: [(point: Vec2, z0: Double, z1: Double)]
    /// Optional handrail (the type's Handrail Height), without extensions beyond the top rail's.
    public var handrail: [Vec3]
}

public enum StairRailings {
    /// The layout of a railing hosted on a stair storey.
    public static func layout(_ rail: Element, stair: Element, _ model: BIMModel) -> StairRailLayout? {
        guard let rd = rail.railing, let l = StairGeometry.layout(stair, model) else { return nil }
        let t = RailingTypeInfo.of(rail, model)
        let left = rd.hostSideLeft
        let position = rd.stairPosition ?? .treads
        let support = left ? l.type.left : l.type.right
        var lift = 0.0
        let inset: Double
        if position == .stringer, support.kind == .stringerClosed {
            inset = -(support.lateralOffset + support.width / 2)
            lift = support.topOffset
        } else {
            inset = rd.offsetFromPath ?? t.treadOffset
        }
        var side = StairGeometry.sidePath(l, left: left, inset: inset)
        if let edited = rd.editedHostPath, edited.count >= 2 { side = follow(edited, side) }
        guard side.count >= 2 else { return nil }
        side = smoothed(side, tread: l.treadDepth)
        let base = side.map { Vec3($0.point, z: $0.z + lift + rd.baseOffset) }
        // Top rail with extensions.
        var top = base.map { $0 + Vec3(0, 0, t.height - t.railSize / 2) }
        var startExt: [Vec3] = [], endExt: [Vec3] = []
        if t.extensionStyle != .none, t.extensionLength > 1e-6, let a = top.first, top.count >= 2 {
            let b = top[1]
            let d = (b.xy - a.xy).normalized
            var p = a
            if t.plusTreadDepth, side.first?.onLanding == false {
                p = Vec3(a.xy - d * l.treadDepth, z: a.z - l.riserHeight)
                startExt.append(p)
            }
            p = Vec3(p.xy - d * t.extensionLength, z: p.z)
            startExt.append(p)
            if t.extensionStyle == .floor { startExt.append(Vec3(p.xy, z: p.z - (t.height - t.railSize / 2) + 0.0)) }
            if t.extensionStyle == .wall { startExt.append(Vec3(p.xy + d.perpendicular * (left ? 1 : -1) * 0.08, z: p.z)) }
        }
        if t.extensionStyle != .none, t.extensionLength > 1e-6, let a = top.last, top.count >= 2 {
            let b = top[top.count - 2]
            let d = (a.xy - b.xy).normalized
            let p = Vec3(a.xy + d * t.extensionLength, z: a.z)
            endExt.append(p)
            if t.extensionStyle == .floor { endExt.append(Vec3(p.xy, z: p.z - (t.height - t.railSize / 2))) }
            if t.extensionStyle == .wall { endExt.append(Vec3(p.xy + d.perpendicular * (left ? 1 : -1) * 0.08, z: p.z)) }
        }
        top = startExt.reversed() + top + endExt
        // Balusters: per tread on runs, at the spacing on landings.
        var balusters: [(Vec2, Double, Double)] = []
        let railBottom = t.height - t.railSize
        func railZ(at p: Vec2) -> Double { heightAlong(base, at: p) + railBottom }
        for r in l.runs where t.balustersPerTread > 0 {
            let edgePoints = left ? r.left : r.right
            for tr in r.treads {
                let a = left ? tr.front.start : tr.front.end, b = left ? tr.back.start : tr.back.end
                let inward = (left ? tr.front.direction : -tr.front.direction) * inset
                for j in 0..<t.balustersPerTread {
                    let f = (Double(j) + 0.5) / Double(t.balustersPerTread)
                    let p = a.lerp(to: b, t: f) + inward
                    if position == .stringer, support.kind == .stringerClosed {
                        balusters.append((p, StairGeometry.edgeHeight(edgePoints, at: p) + lift, railZ(at: p)))
                    } else {
                        balusters.append((p, tr.z, railZ(at: p)))
                    }
                }
            }
        }
        // Landing segments (every segment when balusters aren't per tread) at the type's spacing.
        var carry = t.balusterSpacing / 2
        for (p, q) in zip(side, side.dropFirst()) where (p.onLanding && q.onLanding) || t.balustersPerTread == 0 {
            let len = p.point.distance(to: q.point)
            guard len > 1e-6 else { continue }
            var s = carry
            while s < len {
                let x = p.point.lerp(to: q.point, t: s / len)
                balusters.append((x, p.z + (q.z - p.z) * s / len + lift, railZ(at: x)))
                s += t.balusterSpacing
            }
            carry = s - len
        }
        // Posts: start, end, and the corners where the path turns on a landing.
        var posts: [(Vec2, Double, Double)] = []
        let postTop = t.height
        if let f = side.first { posts.append((f.point, f.z + lift, f.z + lift + postTop)) }
        for i in 1..<max(1, side.count - 1) where side[i].onLanding {
            let d0 = (side[i].point - side[i - 1].point), d1 = (side[i + 1].point - side[i].point)
            guard d0.length > 1e-6, d1.length > 1e-6, abs(d0.normalized.cross(d1.normalized)) > 0.3 else { continue }
            posts.append((side[i].point, side[i].z + lift, side[i].z + lift + postTop))
        }
        if let e = side.last { posts.append((e.point, e.z + lift, e.z + lift + postTop)) }
        let hand = t.handrailHeight > 0 ? base.map { $0 + Vec3(0, 0, t.handrailHeight - t.handrailSize / 2) } : []
        return StairRailLayout(base: base, top: top, balusters: balusters.map { (point: $0.0, z0: $0.1, z1: $0.2) },
                               posts: posts.map { (point: $0.0, z0: $0.1, z1: $0.2) }, handrail: hand)
    }

    /// Replaces vertical steps of the path (a run starting where a landing ends, an inner winder corner) with a slope:
    /// from one tread depth back along a flat landing when there is room, else from the step's foot to one tread depth
    /// into the run, as a top rail eases from a landing into a run.
    static func smoothed(_ pts: [StairPathPoint], tread: Double) -> [StairPathPoint] {
        var out = pts
        var i = 0
        while i + 1 < out.count {
            let low = out[i], high = out[i + 1]
            guard low.point.isAlmostEqual(high.point, tolerance: 1e-6), high.z > low.z + 1e-6 else { i += 1; continue }
            // Flat length behind the step.
            var flat = 0.0, j = i
            while j > 0, abs(out[j - 1].z - low.z) < 1e-6 {
                flat += out[j].point.distance(to: out[j - 1].point)
                j -= 1
                if flat >= tread { break }
            }
            if flat >= tread - 1e-9 {
                // Start the slope `tread` back: drop the flat points within that distance.
                var remaining = tread, k = i
                var start = low.point
                while k > 0 {
                    let seg = out[k].point.distance(to: out[k - 1].point)
                    if seg >= remaining - 1e-9 { start = out[k].point.lerp(to: out[k - 1].point, t: remaining / max(seg, 1e-9)); break }
                    remaining -= seg
                    k -= 1
                }
                out.replaceSubrange(k...i, with: [StairPathPoint(point: start, z: low.z, onLanding: true)])
                i = k + 1
            } else if i + 2 < out.count {
                // Slope from the foot of the step to one tread depth along the run.
                let next = out[i + 2]
                let seg = high.point.distance(to: next.point)
                let f = seg > tread ? tread / seg : 1
                let q = StairPathPoint(point: high.point.lerp(to: next.point, t: f), z: high.z + (next.z - high.z) * f, onLanding: false)
                out.replaceSubrange((i + 1)...(i + 1), with: f < 1 ? [q] : [])
                i += 1
            } else {
                i += 1
            }
        }
        return out
    }

    /// An edited (sketched) plan path given the heights of the stair side it replaces: each point takes the height of
    /// the nearest point of the side path.
    static func follow(_ edited: [Vec2], _ side: [StairPathPoint]) -> [StairPathPoint] {
        edited.map { p in
            var best = (Double.infinity, 0.0, false)
            for (a, b) in zip(side, side.dropFirst()) {
                let seg = Segment2(a.point, b.point)
                let t = seg.isDegenerate ? 0 : max(0, min(1, seg.parameter(of: p)))
                let d = seg.point(at: t).distance(to: p)
                if d < best.0 { best = (d, a.z + (b.z - a.z) * t, a.onLanding && b.onLanding) }
            }
            return StairPathPoint(point: p, z: best.1, onLanding: best.2)
        }
    }

    /// Height of a 3D polyline at the plan point nearest `p`.
    static func heightAlong(_ line: [Vec3], at p: Vec2) -> Double {
        var best = (Double.infinity, line.first?.z ?? 0)
        for (a, b) in zip(line, line.dropFirst()) {
            let seg = Segment2(a.xy, b.xy)
            let t = seg.isDegenerate ? 0 : max(0, min(1, seg.parameter(of: p)))
            let d = seg.point(at: t).distance(to: p)
            if d < best.0 - 1e-9 { best = (d, a.z + (b.z - a.z) * t) }
        }
        return best.1
    }
}

extension StairGeometry {
    /// Height of a run edge at the plan point nearest `p`.
    static func edgeHeight(_ edge: [StairPathPoint], at p: Vec2) -> Double {
        StairRailings.heightAlong(edge.map { Vec3($0.point, z: $0.z) }, at: p)
    }

    /// The railing base line along one side of a stair (legacy name).
    public static func railingPath(_ e: Element, _ model: BIMModel, leftSide: Bool) -> [Vec3] {
        guard let l = layout(e, model) else { return [] }
        return StairRailings.smoothed(sidePath(l, left: leftSide, inset: 0.05), tread: l.treadDepth).map { Vec3($0.point, z: $0.z) }
    }
}

public enum RailingGeometry {
    /// 3D path of the railing's base line.
    public static func path(_ e: Element, _ model: BIMModel) -> [Vec3] {
        guard let r = e.railing else { return [] }
        if r.followsHost, let host = model[e.hostID], host.stair != nil {
            return StairRailings.layout(e, stair: host, model)?.base ?? []
        }
        if r.followsHost, let host = model[e.hostID], host.ramp != nil {
            return RampGeometry.railingPath(host, model, leftSide: r.hostSideLeft)
        }
        let z = model.baseElevation(of: e)
        var pts: [Vec3] = []
        for c in r.path {
            let t = c.tessellate(chordTolerance: 0.01)
            for (i, p) in t.enumerated() where !(i == 0 && pts.last.map { $0.xy.isAlmostEqual(p) } == true) {
                pts.append(Vec3(p, z: z))
            }
        }
        return pts
    }

    public static func meshParts(_ e: Element, _ model: BIMModel) -> [MeshPart] {
        if let r = e.railing, r.followsHost, let host = model[e.hostID], host.stair != nil {
            let storeys = MultistoryStairs.storeys(of: host, model) ?? [host] // F2: on every storey
            return storeys.flatMap { s in StairRailings.layout(e, stair: s, model).map { stairMeshParts(e, model, $0) } ?? [] }
        }
        return meshParts(e, model, along: path(e, model))
    }

    /// A stair railing: top rail (with its extensions), handrail, balusters and posts.
    static func stairMeshParts(_ e: Element, _ model: BIMModel, _ l: StairRailLayout) -> [MeshPart] {
        let t = RailingTypeInfo.of(e, model)
        var mesh = Mesh()
        mesh.append(MeshBuilder.sweep(profile: railProfile(t.railSize, circular: t.circularRail), along: l.top))
        if l.handrail.count >= 2 { mesh.append(MeshBuilder.sweep(profile: railProfile(t.handrailSize, circular: true), along: l.handrail)) }
        let bs = t.balusterSize
        for b in l.balusters where b.z1 > b.z0 + 1e-3 {
            mesh.append(Mesh.box(Box3(min: Vec3(b.point.x - bs / 2, b.point.y - bs / 2, b.z0), max: Vec3(b.point.x + bs / 2, b.point.y + bs / 2, b.z1))))
        }
        let ps = t.postSize
        for p in l.posts where p.z1 > p.z0 + 1e-3 {
            mesh.append(Mesh.box(Box3(min: Vec3(p.point.x - ps / 2, p.point.y - ps / 2, p.z0), max: Vec3(p.point.x + ps / 2, p.point.y + ps / 2, p.z1))))
        }
        return [MeshPart(mesh: mesh, materialID: t.material)]
    }

    static func railProfile(_ size: Double, circular: Bool) -> Polygon2 {
        let r = size / 2
        if circular { // VIS: round rails smooth (10° facets or finer: no lines along them, smooth shading)
            let n = TessellationQuality.medium.fullCircleSegments(radius: r)
            return Polygon2((0..<n).map { Vec2.fromAngle(Double($0) / Double(n) * 2 * .pi, length: r) })
        }
        return Polygon2([Vec2(-r, -r), Vec2(r, -r), Vec2(r, r), Vec2(-r, r)])
    }

    static func meshParts(_ e: Element, _ model: BIMModel, along pts: [Vec3]) -> [MeshPart] {
        guard pts.count >= 2 else { return [] }
        let t = RailingTypeInfo.of(e, model)
        let h = t.height, spacing = t.balusterSpacing, bs = t.balusterSize, rs = t.railSize
        var mesh = Mesh()
        // Top rail swept along the path raised by the railing height.
        let top = pts.map { $0 + Vec3(0, 0, h - rs / 2) }
        mesh.append(MeshBuilder.sweep(profile: railProfile(rs, circular: t.circularRail), along: top))
        // Balusters at spacing along each segment.
        var carry = 0.0
        for i in 0..<(pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            let len = a.xy.distance(to: b.xy)
            guard len > Tolerance.length else { continue }
            var s = carry
            while s <= len {
                let p = a.lerp(to: b, t: s / len)
                mesh.append(Mesh.box(Box3(min: Vec3(p.x - bs / 2, p.y - bs / 2, p.z), max: Vec3(p.x + bs / 2, p.y + bs / 2, p.z + h - rs))))
                s += spacing
            }
            carry = s - len
        }
        return [MeshPart(mesh: mesh, materialID: t.material)]
    }

    public static func length(_ e: Element, _ model: BIMModel) -> Double {
        let p = path(e, model)
        guard p.count >= 2 else { return 0 }
        return (0..<(p.count - 1)).reduce(0) { $0 + p[$1].distance(to: p[$1 + 1]) }
    }
}
