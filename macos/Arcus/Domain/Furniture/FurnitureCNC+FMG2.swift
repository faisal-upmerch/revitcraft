import Foundation
import ArcusGeometry

// FMG2: CNC programs for shaped parts and slats, and edge banding on its own layer (conventions in FurnitureCNC.swift).

extension FurnitureCNC {
    /// True when a model point lies in the frame's box (1 mm of air).
    static func inside(_ p: Vec3, _ f: Frame) -> Bool {
        let a = 0.001
        return p.x >= f.lo.x - a && p.x <= f.hi.x + a && p.y >= f.lo.y - a && p.y <= f.hi.y + a && p.z >= f.lo.z - a && p.z <= f.hi.z + a
    }

    /// A shaped part's outline as joined (trimmed, and stretched to its cut envelope where tongues run on) in face A
    /// coordinates.
    static func shapedOutline(_ e: Element, _ f: Frame, _ sol: JointSolution) -> [Vec2]? {
        guard let part = sol.parts[e.id], case .profile(let n, let raw, _) = part.shape, let final = sol.finalBoxes[e.id], let env = sol.envelopes[e.id] else { return nil }
        let (u, v, _) = FamilySketchPlane.normal(n).axes
        let outline = JointSolver.reshape(sol.finalOutlines[e.id] ?? raw, u: u, v: v, from: final.lo, final.hi, to: env)
        guard outline.count >= 3 else { return nil }
        return outline.map { f.local(point($0.u.value, $0.v.value, n, env.l(n))) }
    }

    /// A shaped part's openings in face A coordinates.
    static func shapedOpenings(_ e: Element, _ f: Frame, _ sol: JointSolution) -> [[Vec2]]? {
        guard let part = sol.parts[e.id], case .profile(let n, _, let openings) = part.shape, let env = sol.envelopes[e.id] else { return nil }
        return openings.map { $0.map { f.local(point($0.x, $0.y, n, env.l(n))) } }
    }

    /// The model point at (u, v) of the plane across `normal`, at `w` along it.
    static func point(_ u: Double, _ v: Double, _ normal: FamilyAxis, _ w: Double) -> Vec3 {
        let (a, b, _) = FamilySketchPlane.normal(normal).axes
        var c = [0.0, 0.0, 0.0]
        c[a.idx] = u; c[b.idx] = v; c[normal.idx] = w
        return Vec3(c[0], c[1], c[2])
    }

    // MARK: Edge banding

    /// The banded edges of a part as open polylines on BAND_<thickness>: L1 (−Y side), L2 (+Y), W1 (−X), W2 (+X) of
    /// face A; a shaped outline's edges go to the side they face.
    static func banding(_ p: CutPart, outline: [Vec2], _ m: BIMModel) -> [CNCDrawing.Path] {
        guard p.banding != .none, outline.count >= 3 else { return [] }
        var t = p.bandingThickness
        if t <= 0, let src = m[p.elementID] { t = FurniturePartTypes.values(of: src, m).edgeThickness }
        let layer = bandLayer(thickness: t)
        // Counterclockwise, so each edge's outward normal is its direction turned right.
        let pts = Polygon2(outline).signedArea < 0 ? Array(outline.reversed()) : outline
        func side(_ a: Vec2, _ b: Vec2) -> Int {
            let d = b - a
            let nx = d.y, ny = -d.x
            return abs(ny) >= abs(nx) ? (ny < 0 ? 0 : 1) : (nx < 0 ? 2 : 3) // L1, L2, W1, W2
        }
        let banded = [p.banding.l1, p.banding.l2, p.banding.w1, p.banding.w2]
        let n = pts.count
        let sides = (0..<n).map { side(pts[$0], pts[($0 + 1) % n]) }
        // Start at an edge whose side differs from the one before it, so a run doesn't wrap round the start.
        let start = (0..<n).first { sides[$0] != sides[($0 + n - 1) % n] } ?? 0
        var out: [CNCDrawing.Path] = []
        var run: [Vec2] = [], runSide = -1
        func flush() { if runSide >= 0, banded[runSide], run.count >= 2 { out.append(.init(layer: layer, points: run, closed: false)) } }
        for k in 0..<n {
            let i = (start + k) % n
            let a = pts[i], b = pts[(i + 1) % n]
            if sides[i] != runSide { flush(); run = [a]; runSide = sides[i] }
            run.append(b)
        }
        flush()
        return out
    }
}
