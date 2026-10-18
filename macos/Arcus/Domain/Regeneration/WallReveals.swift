import Foundation
import ArcusGeometry

// F1: Wall: Reveal (RevitCraft `crates/rc-core/src/edit.rs` `add_wall_sweep` with `reveal`, `wall_sweep_box`): a groove
// cut into one face of a straight wall, running the wall's whole length (horizontal) or its whole height (vertical).
// The reveal is its own element hosted by the wall; the wall's solid is built with the groove removed.

/// A reveal cut into a wall face.
public struct WallRevealData: Hashable, Codable, Sendable {
    public enum Orientation: String, Codable, Sendable, CaseIterable { case horizontal = "Horizontal", vertical = "Vertical" }
    public var orientation: Orientation
    /// Horizontal: height of the reveal's centre above the wall's base. Vertical: distance of its centre along the wall
    /// from the wall's start.
    public var offset: Double
    public var side: WallSweep.Side
    /// Size of the groove across its run (RevitCraft: 50 mm).
    public var width: Double
    /// How deep the groove cuts into the face (RevitCraft: 20 mm).
    public var depth: Double

    public init(orientation: Orientation = .horizontal, offset: Double, side: WallSweep.Side = .exterior, width: Double = 0.05, depth: Double = 0.02) {
        self.orientation = orientation; self.offset = offset; self.side = side; self.width = width; self.depth = depth
    }
}

extension Element {
    /// F1: the Wall: Reveal payload.
    public var wallReveal: WallRevealData? {
        get { if case .wallReveal(let d) = data { return d }; return nil }
        set { if let v = newValue { data = .wallReveal(v) } }
    }
}

/// Where a reveal removes material from its wall.
public struct WallRevealCut: Sendable, Hashable {
    public var revealID: ElementID
    /// The groove in the wall's elevation plane: station along the wall (x) by absolute elevation (y).
    public var rect: Rect2
    /// Signed offsets (left of the location line positive) of the face the groove opens on and of its bottom.
    public var face: Double
    public var bottom: Double
    /// Offset range of the removed material.
    public var range: ClosedRange<Double> { min(face, bottom)...max(face, bottom) }
}

public enum WallReveals {
    /// Whether a wall can take reveals: straight, basic (not curtain) walls, as in RevitCraft.
    public static func canHost(_ w: Element, _ model: BIMModel) -> Bool {
        w.wall != nil && w.wall?.location.asSegment != nil && !CurtainWallGeometry.isCurtain(w, model)
    }

    /// Reveals hosted by a wall, sorted by id.
    public static func reveals(of wall: Element, _ model: BIMModel) -> [Element] {
        model.hosted(by: wall.id).filter { $0.wallReveal != nil }
    }

    /// The material a reveal removes, clamped to the wall like RevitCraft's `wall_sweep_box` (horizontal grooves run past
    /// both ends; vertical ones the whole height).
    public static func cut(_ r: Element, _ f: WallFrame) -> WallRevealCut? {
        guard let d = r.wallReveal, d.width > Tolerance.length, d.depth > Tolerance.length, f.isStraight else { return nil }
        let half = d.width / 2
        let rect: Rect2
        switch d.orientation {
        case .horizontal:
            let z = min(max(f.baseZ + d.offset, f.baseZ + half), max(f.topZ - half, f.baseZ + half))
            rect = Rect2(min: Vec2(-0.005, z - half), max: Vec2(f.length + 0.005, z + half))
        case .vertical:
            let s = min(max(d.offset, half), max(f.length - half, half))
            rect = Rect2(min: Vec2(s - half, f.baseZ - 0.005), max: Vec2(s + half, f.topZ + 0.005))
        }
        let face = d.side == .exterior ? f.exteriorOffset : f.interiorOffset
        let other = d.side == .exterior ? f.interiorOffset : f.exteriorOffset
        let depth = min(d.depth, abs(face - other) - Tolerance.length * 20)
        guard depth > Tolerance.length else { return nil }
        let bottom = face + (other > face ? depth : -depth)
        return WallRevealCut(revealID: r.id, rect: rect, face: face, bottom: bottom)
    }

    /// The cuts of every reveal of a wall.
    public static func cuts(_ wall: Element, _ f: WallFrame, _ model: BIMModel) -> [WallRevealCut] {
        reveals(of: wall, model).compactMap { cut($0, f) }
    }

    /// Thickness slices between `right` and `left` (offsets, right < left): split at `breaks` and wherever a reveal's
    /// groove bottom lies, each with the reveal cuts that remove that slice.
    static func slices(right: Double, left: Double, breaks: [Double], cuts: [WallRevealCut]) -> [(t0: Double, t1: Double, cuts: [WallRevealCut])] {
        let eps = Tolerance.length * 10
        var ts = [right, left] + breaks + cuts.map(\.bottom)
        ts = ts.filter { $0 >= right - eps && $0 <= left + eps }.sorted()
        var unique: [Double] = []
        for t in ts where unique.last.map({ t - $0 > eps }) ?? true { unique.append(t) }
        var out: [(Double, Double, [WallRevealCut])] = []
        for k in 0..<(unique.count - 1) {
            let a = unique[k], b = unique[k + 1]
            let mid = (a + b) / 2
            out.append((a, b, cuts.filter { $0.range.contains(mid) }))
        }
        return out
    }

    /// The wall's elevation profiles with the grooves of `cuts` removed.
    static func profiles(_ base: [Profile2], minus cuts: [WallRevealCut]) -> [Profile2] {
        guard !cuts.isEmpty else { return base }
        let r = PolygonBoolean.difference(base, cuts.map { Profile2(outer: .rectangle($0.rect)) })
        return r
    }

    /// Faces exposed on the plane between two slices: where one side has material and the other is grooved.
    /// Returns (region in elevation coordinates, true when the exposed face looks toward +t).
    static func exposedFaces(_ base: [Profile2], lower: [WallRevealCut], upper: [WallRevealCut]) -> [(Profile2, Bool)] {
        let lowerIDs = Set(lower.map(\.revealID)), upperIDs = Set(upper.map(\.revealID))
        guard lowerIDs != upperIDs else { return [] }
        let lowerMaterial = profiles(base, minus: lower), upperMaterial = profiles(base, minus: upper)
        let towardUpper = PolygonBoolean.difference(lowerMaterial, upperMaterial).map { ($0, true) }
        let towardLower = PolygonBoolean.difference(upperMaterial, lowerMaterial).map { ($0, false) }
        return (towardUpper + towardLower).filter { $0.0.area > Tolerance.area }
    }

    /// A planar face at offset `t` across a straight wall (elevation region `p`), facing +t when `positive`.
    static func face(_ p: Profile2, t: Double, seg: Segment2, positive: Bool) -> Mesh {
        let tri = Triangulator.triangulate(p)
        guard !tri.triangles.isEmpty else { return .empty }
        let nrm = seg.normal, dir = seg.direction
        func world(_ q: Vec2) -> Vec3 { let w = seg.start + dir * q.x + nrm * t; return Vec3(w.x, w.y, q.y) }
        let want = Vec3(nrm.x, nrm.y, 0) * (positive ? 1 : -1)
        var m = Mesh()
        m.positions = tri.points.map(world)
        m.normals = Array(repeating: want, count: tri.points.count)
        for k in stride(from: 0, to: tri.triangles.count, by: 3) {
            let a = UInt32(tri.triangles[k]), b = UInt32(tri.triangles[k + 1]), c = UInt32(tri.triangles[k + 2])
            let n = (m.positions[Int(b)] - m.positions[Int(a)]).cross(m.positions[Int(c)] - m.positions[Int(a)])
            m.indices += n.dot(want) >= 0 ? [a, b, c] : [a, c, b]
        }
        for loop in p.loops {
            let base = UInt32(m.positions.count)
            let pts = loop.points.map(world)
            m.positions += pts
            m.normals += Array(repeating: want, count: pts.count)
            for i in pts.indices { m.featureEdges += [base + UInt32(i), base + UInt32((i + 1) % pts.count)] }
        }
        return m
    }
}
