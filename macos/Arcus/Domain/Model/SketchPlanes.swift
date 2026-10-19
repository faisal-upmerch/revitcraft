import Foundation
import ArcusGeometry

// S3D2: elements drawn on a work plane other than their level's (Revit's sketch plane): model lines, model text,
// components and reference planes drawn in 3D on a reference plane, a picked face or a named plane. The element keeps
// its 2D data in the plane's own coordinates and the plane itself, so it stays where it was drawn.

/// The plane an element is drawn on, as it was when drawn, and what it came from.
public struct WorkPlaneHost: Hashable, Codable, Sendable {
    public var frame: WorkPlaneFrame
    /// The work plane chosen (Work Plane ▸ Set), for the element's Work Plane property; nil for a free plane.
    public var reference: WorkPlaneRef?
    public init(frame: WorkPlaneFrame, reference: WorkPlaneRef? = nil) { self.frame = frame; self.reference = reference }

    /// Plane coordinates → model point.
    public func point(_ p: Vec2) -> Vec3 { frame.point(p.x, p.y) }
    /// Model point → plane coordinates (projected along the normal).
    public func local(_ p: Vec3) -> Vec2 {
        let d = p - frame.origin
        return Vec2(d.dot(frame.u), d.dot(frame.v))
    }
    /// Plane coordinates (z along the normal) → model space.
    public var transform: Transform3 { .frame(origin: frame.origin, xAxis: frame.u, yAxis: frame.v) }
    /// Plane coordinates → their plan projection (degenerate for vertical planes, which plan sees edge-on).
    public var planProjection: Transform2 {
        let f = frame
        return Transform2(a: f.u.x, b: f.v.x, c: f.u.y, d: f.v.y, tx: f.origin.x, ty: f.origin.y)
    }
    /// Moves, turns or mirrors the plane with a plan transform (Move, Rotate, Mirror, Array, Copy).
    public mutating func transform(by t: Transform2) {
        let o = t.apply(frame.origin.xy)
        frame.origin = Vec3(o, z: frame.origin.z)
        frame.u = Vec3(t.applyVector(frame.u.xy), z: frame.u.z)
        frame.v = Vec3(t.applyVector(frame.v.xy), z: frame.v.z)
    }
}

/// A reference plane that isn't vertical: drawn on a vertical or sloped work plane, it contains the line drawn and the
/// work plane's normal (Revit).
public struct ReferencePlane3D: Hashable, Codable, Sendable {
    public var start: Vec3
    public var end: Vec3
    /// Unit direction the plane extends from the line (perpendicular to it).
    public var extrusion: Vec3
    public init(start: Vec3, end: Vec3, extrusion: Vec3) { self.start = start; self.end = end; self.extrusion = extrusion }
}

extension ReferencePlaneData {
    /// The plane in model space: vertical through `line` (u along it, v up), or as drawn on another work plane.
    public var frame: WorkPlaneFrame? {
        if let p = plane3D {
            let d = p.end - p.start
            guard d.length > Tolerance.length else { return nil }
            let u = d.normalized
            let v = (p.extrusion - u * p.extrusion.dot(u))
            guard v.length > 1e-9 else { return nil }
            return WorkPlaneFrame(origin: p.start, u: u, v: v.normalized)
        }
        guard line.length > Tolerance.length else { return nil }
        let d = line.direction
        return WorkPlaneFrame(origin: Vec3(line.start, z: 0), u: Vec3(d.x, d.y, 0), v: Vec3(0, 0, 1))
    }

    /// The reference plane through the line `a`–`b` drawn on `host` (plane coordinates), perpendicular to it. Planes
    /// that come out vertical are ordinary vertical reference planes; others keep their 3D definition.
    public static func drawn(on host: WorkPlaneHost, from a: Vec2, to b: Vec2) -> ReferencePlaneData? {
        let pa = host.point(a), pb = host.point(b)
        let d = pb - pa
        guard d.length > Tolerance.shortCurve else { return nil }
        let n = host.frame.normal
        let normal = d.cross(n)
        guard normal.length > 1e-9 else { return nil }
        if abs(normal.normalized.z) < 1e-6 {
            // Vertical: its plan trace runs along the line's plan direction, or along the work plane's normal for a
            // line drawn straight up.
            if d.xy.length > Tolerance.shortCurve { return ReferencePlaneData(line: Segment2(pa.xy, pb.xy)) }
            let t = n.xy.normalized * max(d.length, 1)
            return ReferencePlaneData(line: Segment2(pa.xy - t / 2, pa.xy + t / 2))
        }
        var r = ReferencePlaneData(line: Segment2(pa.xy, pb.xy))
        r.plane3D = ReferencePlane3D(start: pa, end: pb, extrusion: n)
        return r
    }
}

extension ModelLineData {
    /// The line as a model-space polyline (arcs and freeform curves flattened); `baseZ` places level-hosted lines.
    public func worldPolyline(baseZ: Double) -> [Vec3] {
        let pts: [Vec2]
        if let f = freeform, f.points.count >= 2 {
            pts = f.points
        } else {
            switch curve {
            case .line(let s): pts = [s.start, s.end]
            case .arc(let a): pts = a.tessellate(chordTolerance: 0.003)
            }
        }
        if let sp = sketchPlane { return pts.map(sp.point) }
        return pts.map { Vec3($0, z: baseZ) }
    }
}

extension ComponentGeometry {
    /// S3D2: placement of a component on a sketch plane: its plan transform acts in the plane's coordinates, lifted
    /// `offset` along the normal; `plan` is the projection of that on the plan.
    static func sketchPlacement(_ e: Element) -> (plan: Transform2, world: Transform3)? {
        guard case .component(let c) = e.data, let sp = c.sketchPlane else { return nil }
        var local = Transform2.translation(c.location) * Transform2.rotation(c.rotation)
        if c.mirrored { local = local * Transform2.scale(-1, 1) }
        if c.facingFlipped == true { local = local * Transform2.scale(1, -1) }
        let world = sp.transform * Transform3(local, z: c.offset)
        let m = world.matrix
        let plan = Transform2(a: m.columns.0.x, b: m.columns.1.x, c: m.columns.0.y, d: m.columns.1.y, tx: m.columns.3.x, ty: m.columns.3.y)
        return (plan, world)
    }
}

extension ModelTextGeometry {
    /// S3D2: text on a sketch plane: lying on it (extruded along its normal) or upright on it.
    static func sketchMeshParts(_ t: ModelTextData, _ sp: WorkPlaneHost) -> [MeshPart] {
        let depth = max(t.depth, 0.0001)
        var mesh = Mesh()
        if t.upright {
            let (d, _) = t.frame
            let frame = sp.transform * Transform3.frame(origin: Vec3(t.position, z: t.offset), xAxis: Vec3(d.x, d.y, 0), yAxis: .unitZ)
            for p in shapes(localContours(t)) { mesh.append(MeshBuilder.extrude(p, frame: frame, depth: depth)) }
        } else {
            let frame = sp.transform * Transform3.translation(Vec3(0, 0, t.offset))
            for p in shapes(planContours(t).map(\.points)) { mesh.append(MeshBuilder.extrude(p, frame: frame, depth: depth)) }
        }
        return mesh.isEmpty ? [] : [MeshPart(mesh: mesh, materialID: t.materialID)]
    }
}

/// S3D2: the plane of an element's face at a point (Work Plane ▸ Set ▸ Pick a plane in a 3D view).
public enum FacePlanes {
    /// The face of `e` through `p` (the nearest of its triangles), as a work plane with `u` level and `v` up the face
    /// (plan X and Y for a level face). nil when `p` is not on the element.
    public static func frame(of e: Element, at p: Vec3, _ model: BIMModel, tolerance: Double = 0.02) -> WorkPlaneFrame? {
        var best: (d: Double, n: Vec3)?
        for part in GeometryCache.shared.parts(e, model, detail: .medium) where part.isVisibleIn3D {
            let m = part.mesh
            var t = 0
            while t + 2 < m.indices.count {
                let a = m.positions[Int(m.indices[t])], b = m.positions[Int(m.indices[t + 1])], c = m.positions[Int(m.indices[t + 2])]
                t += 3
                let n = (b - a).cross(c - a)
                guard n.length > 1e-12 else { continue }
                let nn = n.normalized
                let d = abs((p - a).dot(nn))
                guard d <= tolerance, d < (best?.d ?? .infinity) else { continue }
                // Inside the triangle (projected), with a little slack at its edges.
                let q = p - nn * (p - a).dot(nn)
                func side(_ x: Vec3, _ y: Vec3) -> Double { (y - x).cross(q - x).dot(nn) }
                let slack = -tolerance * max((b - a).length, (c - b).length, (a - c).length)
                guard side(a, b) >= slack, side(b, c) >= slack, side(c, a) >= slack else { continue }
                best = (d, nn)
            }
        }
        guard let n = best?.n else { return nil }
        return frame(normal: n, origin: p)
    }

    /// A work plane through `origin` facing `n`: `u` level (plan X on a level face), `v` up the plane, `u × v = n`.
    public static func frame(normal n: Vec3, origin: Vec3) -> WorkPlaneFrame {
        let n = n.normalized
        var u = abs(n.z) > 0.9 ? Vec3.unitX - n * n.x : Vec3.unitZ.cross(n)
        u = u.normalized
        let v = n.cross(u).normalized
        return WorkPlaneFrame(origin: origin, u: u, v: v)
    }
}
