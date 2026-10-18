import Foundation
import ArcusGeometry

// F1: RevitCraft's hosted openings (Opening panel: By Face, Vertical, Dormer). They are shaft-opening elements
// (`ShaftOpeningData.hosted` set) whose `hostID` is the one floor, ceiling or roof they cut through its whole depth,
// as in `crates/rc-core/src/edit.rs` (`add_vertical_opening`, `add_face_opening`) and `build3d.rs` (`face_prism`).
// Vertical and Dormer openings remove their plan boundary straight down (ShaftCuts); By Face openings in a roof lean
// with the roof face, so their sides are square to it.

/// Hosted openings: hosts, extents and the roof mesh with By Face cuts.
public enum HostedOpenings {
    /// Whether `e` can host an opening of `kind`: dormers cut footprint roofs; the others also floors and ceilings.
    public static func canHost(_ e: Element, kind: HostedOpeningKind) -> Bool {
        let roof = e.roof != nil && e.roof?.extrusion == nil
        switch kind {
        case .dormer: return roof
        case .vertical, .byFace: return roof || (e.slab != nil && (e.category == .floors || e.category == .ceilings))
        }
    }

    /// Absolute bottom and top of a hosted opening: its host's extent.
    static func range(_ opening: Element, _ model: BIMModel) -> (bottom: Double, top: Double)? {
        guard let host = model[opening.hostID], let x = ShaftCuts.hostExtent(host, model) else { return nil }
        return (x.z0, x.z1)
    }

    /// Plan bounds of a host's solid (conservative for roofs).
    public static func hostBounds(_ host: Element, _ model: BIMModel) -> Rect2? { ShaftCuts.hostExtent(host, model)?.bounds }

    /// Hosted openings of an element, sorted by id.
    public static func openings(in host: Element, _ model: BIMModel) -> [Element] {
        model.hosted(by: host.id).filter { $0.category == .shaftOpenings && $0.opening?.shaft?.hosted != nil }
    }

    /// Plan boundaries (outer loops) of the By Face openings in a roof.
    public static func faceCuts(_ roof: Element, _ model: BIMModel) -> [Polygon2] {
        guard roof.roof != nil else { return [] }
        return openings(in: roof, model).filter { $0.opening?.shaft?.hosted == .byFace }.compactMap { ShaftCuts.profile($0)?.outer }
    }

    /// Plan offset of a By Face cut's bottom outline from its top outline: a cut square to the plane `top` leans uphill
    /// by the roof's vertical thickness times the slope (RevitCraft `face_prism`).
    public static func faceShift(top: PlaneZ, bottom: PlaneZ) -> Vec2 {
        Vec2(top.a, top.b) * (top.c - bottom.c)
    }

    /// One planar roof piece (between `bottom` and `top`, vertical holes already removed) with the By Face cuts that
    /// lie wholly inside it cut square to the face; cuts that cross the piece's edges are cut vertically instead.
    public static func roofPiece(_ piece: Profile2, bottom: PlaneZ, top: PlaneZ, faceCuts: [Polygon2]) -> Mesh {
        let near = faceCuts.filter { $0.bounds.intersects(piece.bounds) }
        guard !near.isEmpty else { return MeshBuilder.slab(piece, bottom: bottom, top: top) }
        let shift = faceShift(top: top, bottom: bottom)
        var leaning: [(top: Polygon2, bottom: Polygon2)] = []
        var straight: [Profile2] = []
        for c in near {
            let upper = c.clockwise
            let lower = upper.transformed(.translation(shift))
            let fits = inside(upper, piece) && inside(lower, piece)
                && !leaning.contains { overlaps($0.top, upper) || overlaps($0.bottom, lower) }
            if fits { leaning.append((upper, lower)) } else if overlaps(c, piece) { straight.append(Profile2(outer: c)) }
        }
        guard !leaning.isEmpty else {
            let pieces = PolygonBoolean.difference([piece], straight)
            return pieces.reduce(into: Mesh()) { $0.append(MeshBuilder.slab($1, bottom: bottom, top: top)) }
        }
        guard !straight.isEmpty else { return leaningSlab(piece, bottom: bottom, top: top, cuts: leaning) }
        // Vertical cuts first; each leaning cut goes with the remaining piece that still holds it.
        var mesh = Mesh()
        for p in PolygonBoolean.difference([piece], straight) {
            let mine = leaning.filter { inside($0.top, p) && inside($0.bottom, p) }
            mesh.append(mine.isEmpty ? MeshBuilder.slab(p, bottom: bottom, top: top) : leaningSlab(p, bottom: bottom, top: top, cuts: mine))
        }
        return mesh
    }

    /// True when `poly` lies within the material of `piece` (outside its holes).
    static func inside(_ poly: Polygon2, _ piece: Profile2) -> Bool {
        let outside = PolygonBoolean.difference([Profile2(outer: poly)], [piece]).reduce(0) { $0 + $1.area }
        return outside < max(1e-8, poly.area * 1e-6)
    }

    static func overlaps(_ a: Polygon2, _ b: Polygon2) -> Bool {
        overlaps(a, Profile2(outer: b))
    }

    static func overlaps(_ a: Polygon2, _ b: Profile2) -> Bool {
        guard a.bounds.intersects(b.bounds) else { return false }
        return PolygonBoolean.intersection([Profile2(outer: a)], [b]).reduce(0) { $0 + $1.area } > 1e-8
    }

    /// Closed solid of a planar slab piece with leaning holes: each hole's outline is `top` on the upper face and
    /// `bottom` on the lower one (both clockwise, vertex for vertex), joined by planar quads.
    static func leaningSlab(_ piece: Profile2, bottom: PlaneZ, top: PlaneZ, cuts: [(top: Polygon2, bottom: Polygon2)]) -> Mesh {
        var m = Mesh()
        cap(Profile2(outer: piece.outer, holes: piece.holes + cuts.map(\.top)), plane: top, upward: true, into: &m)
        cap(Profile2(outer: piece.outer, holes: piece.holes + cuts.map(\.bottom)), plane: bottom, upward: false, into: &m)
        // The piece's own sides stay vertical (outer counter-clockwise, holes clockwise: the right side is outside).
        for loop in piece.loops {
            let pts = loop.points
            for i in pts.indices {
                let p = pts[i], q = pts[(i + 1) % pts.count]
                let prev = pts[(i + pts.count - 1) % pts.count]
                let corner = (p - prev).normalized.dot((q - p).normalized) < cos(Double.pi / 8)
                side([p.at(z: bottom.z(at: p)), q.at(z: bottom.z(at: q)), q.at(z: top.z(at: q)), p.at(z: top.z(at: p))], edge: corner, into: &m)
            }
        }
        // Each leaning side joins an upper edge to the matching lower edge.
        for c in cuts {
            let u = c.top.points, l = c.bottom.points
            guard u.count == l.count else { continue }
            for i in u.indices {
                let j = (i + 1) % u.count
                side([l[i].at(z: bottom.z(at: l[i])), l[j].at(z: bottom.z(at: l[j])), u[j].at(z: top.z(at: u[j])), u[i].at(z: top.z(at: u[i]))], edge: true, into: &m)
            }
        }
        return m
    }

    /// A triangulated planar cap with its outline as feature edges.
    static func cap(_ profile: Profile2, plane: PlaneZ, upward: Bool, into m: inout Mesh) {
        let tri = Triangulator.triangulate(profile)
        guard !tri.triangles.isEmpty else { return }
        let normal = upward ? plane.upNormal : -plane.upNormal
        let base = UInt32(m.positions.count)
        m.positions += tri.points.map { $0.at(z: plane.z(at: $0)) }
        m.normals += Array(repeating: normal, count: tri.points.count)
        for t in stride(from: 0, to: tri.triangles.count, by: 3) {
            let a = base + UInt32(tri.triangles[t]), b = base + UInt32(tri.triangles[t + 1]), c = base + UInt32(tri.triangles[t + 2])
            m.indices += upward ? [a, b, c] : [a, c, b]
        }
        for loop in profile.loops {
            let pts = loop.points.map { $0.at(z: plane.z(at: $0)) }
            let lb = UInt32(m.positions.count)
            m.positions += pts
            m.normals += Array(repeating: normal, count: pts.count)
            for i in pts.indices { m.featureEdges += [lb + UInt32(i), lb + UInt32((i + 1) % pts.count)] }
        }
    }

    /// A planar quad (bottom start, bottom end, top end, top start) facing to the right of its bottom edge; `edge`
    /// draws its start edge (a corner) as a feature line.
    static func side(_ q: [Vec3], edge: Bool, into m: inout Mesh) {
        var n = (q[1] - q[0]).cross(q[3] - q[0])
        guard n.lengthSquared > 1e-18 else { return }
        n = n.normalized
        let base = UInt32(m.positions.count)
        m.positions += q
        m.normals += Array(repeating: n, count: 4)
        m.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        if edge { m.featureEdges += [base, base + 3] }
    }
}

extension RoomGeometry {
    /// F1: Highlight Boundaries (RevitCraft `Cmd::HighlightBoundaries`): the room-bounding elements of a level — walls
    /// set to Room Bounding that stand at the level's computation height, room-bounding columns on the level, and its
    /// room separation lines. Sorted by id.
    public static func boundingElements(level: ElementID, _ model: BIMModel) -> [ElementID] {
        let lv = model.elevation(ofLevel: level)
        let z = lv + max(model[level]?.level?.computationHeight ?? 0, 0.3)
        var out: [ElementID] = []
        for w in model.elements(.walls) where w.wall?.roomBounding == true && w.phaseDemolished == nil {
            guard let f = WallGeometry.frame(w, model), f.baseZ <= z + Tolerance.length, f.topZ >= z - Tolerance.length else { continue }
            out.append(w.id)
        }
        for c in model.elements(.columns) + model.elements(.structuralColumns) where c.column?.roomBounding == true && c.levelID == level {
            out.append(c.id)
        }
        for l in model.elements(.roomSeparationLines) where l.levelID == level { out.append(l.id) }
        return out.sorted()
    }
}
