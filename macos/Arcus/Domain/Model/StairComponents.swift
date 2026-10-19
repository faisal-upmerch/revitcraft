import Foundation
import ArcusGeometry

// STAIR: Revit-style stair components (Stair by Component): runs, landings and supports, plus sketched runs (Boundary,
// Riser, Stair Path). A stair with `StairData.runs` is a component stair; an older stair (shape, origin, direction only)
// is read as the component stair its shape describes (`StairComponents.legacy`), so older files open unchanged.

/// The kind of a stair run, as the Create Stair Run tools draw it.
public enum StairRunShape: String, Codable, Sendable, CaseIterable {
    case straight = "Straight"
    /// Full-Step and Center-Ends spirals: a run around a centre (the walk line is its centre arc).
    case spiral = "Spiral"
    /// L-Shape Winder: two straight legs and winder treads in the corner.
    case lWinder = "L-Shape Winder"
    /// U-Shape Winder: three legs and two winder corners.
    case uWinder = "U-Shape Winder"
    /// A run sketched with Boundary, Riser and Stair Path lines.
    case sketch = "Sketch"
}

/// Where the drawn path sits relative to the run (Create Stair Options Bar "Location Line").
public enum StairLocationLine: String, Codable, Sendable, CaseIterable {
    case exteriorSupportLeft = "Exterior Support: Left"
    case runLeft = "Run: Left"
    case runCenter = "Run: Center"
    case runRight = "Run: Right"
    case exteriorSupportRight = "Exterior Support: Right"

    /// Offset from the drawn path to the run's centre line, toward the run's left (travel direction), for a run of
    /// `width` with supports `supportWidth` wide on the outside.
    public func centerOffset(width: Double, supportWidth: Double) -> Double {
        switch self {
        case .exteriorSupportLeft: -(width / 2 + supportWidth)
        case .runLeft: -width / 2
        case .runCenter: 0
        case .runRight: width / 2
        case .exteriorSupportRight: width / 2 + supportWidth
        }
    }
}

/// A sketched run (Create Sketch): its boundaries, riser lines and the stair path, in plan.
public struct StairRunSketch: Hashable, Codable, Sendable {
    /// Boundary lines (usually a left and a right chain).
    public var boundaries: [Curve2]
    /// Riser lines, in any order (they are sorted along the stair path).
    public var risers: [Curve2]
    /// The stair path from the bottom to the top (sets the up direction).
    public var path: [Curve2]
    public init(boundaries: [Curve2] = [], risers: [Curve2] = [], path: [Curve2] = []) {
        self.boundaries = boundaries; self.risers = risers; self.path = path
    }
}

/// One run of a component stair.
public struct StairRun: Hashable, Codable, Sendable {
    public var shape: StairRunShape
    /// Centre line point at the run's start edge (the first riser, or the start of a starting tread).
    /// Spirals: the start of the centre arc.
    public var start: Vec2
    /// Direction of travel at the start (radians).
    public var direction: Double
    /// Risers in this run. Sketched runs: the number of riser lines.
    public var risers: Int
    /// Actual Run Width (clear width between the run's boundaries).
    public var width: Double
    /// Spirals: centre of the centre arc. Optional, so only spirals carry it.
    public var center: Vec2?
    /// Spirals and winders: the run turns left (counter-clockwise seen from above).
    public var turnsLeft: Bool?
    /// Winders: straight treads in each leg before the last (L: [first leg]; U: [first leg, middle leg]); the last
    /// leg takes the remaining treads.
    public var legTreads: [Int]?
    /// Winders: winder treads in each corner (3 when nil).
    public var windersPerCorner: Int?
    /// Sketched runs: boundary, riser and path lines.
    public var sketch: StairRunSketch?
    /// The Location Line the run was drawn with (kept so Edit Stairs offers it again).
    public var locationLine: StairLocationLine?

    public init(shape: StairRunShape = .straight, start: Vec2, direction: Double, risers: Int, width: Double) {
        self.shape = shape; self.start = start; self.direction = direction; self.risers = risers; self.width = width
    }

    public var directionVector: Vec2 { Vec2.fromAngle(direction) }
    public var corners: Int { shape == .lWinder ? 1 : shape == .uWinder ? 2 : 0 }
    public var winders: Int { max(1, windersPerCorner ?? 3) }
}

/// A landing between two runs or sketched by its boundary.
public struct StairLanding: Hashable, Codable, Sendable {
    /// Joins run `afterRun` to run `afterRun + 1` (nil: a free landing sketched on its own).
    public var afterRun: Int?
    /// Sketched boundary (Create Sketch); nil: shaped automatically from the two runs.
    public var boundary: [Vec2]?
    public init(afterRun: Int?, boundary: [Vec2]? = nil) { self.afterRun = afterRun; self.boundary = boundary }
    public var isAutomatic: Bool { boundary == nil }
}

/// A support added with Support ▸ Pick Edges (on top of the type's left, right and middle supports).
public struct StairSupport: Hashable, Codable, Sendable {
    public enum Side: String, Codable, Sendable { case left, right }
    /// The run whose edge carries the support (nil: a landing edge).
    public var run: Int?
    /// The landing whose edge carries the support, and the edge (index of the landing boundary's edge).
    public var landing: Int?
    public var edge: Int?
    public var side: Side
    /// Support type (nil: the stair type's right or left support type).
    public var typeID: ElementID?
    public init(run: Int?, side: Side, landing: Int? = nil, edge: Int? = nil, typeID: ElementID? = nil) {
        self.run = run; self.side = side; self.landing = landing; self.edge = edge; self.typeID = typeID
    }
}

/// Kinds of stringers in Type Properties (Right Support / Left Support).
public enum StairSupportKind: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case stringerClosed = "Stringer (Closed)"
    case carriageOpen = "Carriage (Open)"
}

/// Cut Mark Type of a stair type (the break line drawn where the plan's cut plane crosses the stair).
public enum StairCutMarkType: String, Codable, Sendable, CaseIterable {
    case doubleZigzag = "Double Zigzag"
    case singleZigzag = "Single Zigzag"
    case straight = "Straight Line"
}

/// Nosing Profile of a run type.
public enum StairNosingProfile: String, Codable, Sendable, CaseIterable {
    case none = "None"
    case square = "Nosing - Square"
    case rounded = "Nosing - Rounded"
}

/// Apply Nosing Profile of a run type: which tread edges get the nosing.
public enum StairNosingApply: String, Codable, Sendable, CaseIterable {
    case front = "Front Only"
    case frontLeft = "Front and Left"
    case frontRight = "Front and Right"
    case frontLeftRight = "Front, Left and Right"
}

/// Riser to Tread Connection of a run type.
public enum StairRiserConnection: String, Codable, Sendable, CaseIterable {
    case riserBehindTread = "Extend Riser Behind Tread"
    case treadUnderRiser = "Extend Tread Under Riser"
}

/// Railing Position on a stair (the Railing dialog of Create Stair, and a hosted railing's placement).
public enum StairRailingPosition: String, Codable, Sendable, CaseIterable {
    case treads = "Treads"
    case stringer = "Stringer"
}

extension StairData {
    /// True for a stair made of components (drawn with the Create Stair tools); older stairs carry only a shape.
    public var isComponentStair: Bool { runs?.isEmpty == false }

    /// The stair with its plan geometry moved by `t` (Move, Rotate, Mirror, Copy). A reflection reverses turns and
    /// swaps left and right.
    public func transformed(_ t: Transform2) -> StairData {
        var s = self
        let mirror = t.isMirroring
        s.origin = t.apply(s.origin)
        s.direction = t.applyVector(Vec2.fromAngle(s.direction)).angle
        if mirror { s.turnsLeft.toggle() }
        s.runs = runs?.map { r in
            var r = r
            r.start = t.apply(r.start)
            r.direction = t.applyVector(r.directionVector).angle
            r.center = r.center.map(t.apply)
            if mirror { r.turnsLeft = r.turnsLeft.map { !$0 } }
            if var k = r.sketch {
                k.boundaries = k.boundaries.map { $0.transformed(t) }
                k.risers = k.risers.map { $0.transformed(t) }
                k.path = k.path.map { $0.transformed(t) }
                r.sketch = k
            }
            if mirror, let l = r.locationLine {
                switch l {
                case .exteriorSupportLeft: r.locationLine = .exteriorSupportRight
                case .exteriorSupportRight: r.locationLine = .exteriorSupportLeft
                case .runLeft: r.locationLine = .runRight
                case .runRight: r.locationLine = .runLeft
                case .runCenter: break
                }
            }
            return r
        }
        s.landings = landings?.map { var l = $0; l.boundary = l.boundary.map { $0.map(t.apply) }; return l }
        if mirror { s.supports = supports?.map { var x = $0; x.side = x.side == .left ? .right : .left; return x } }
        return s
    }
}

/// Building and reading component stairs.
public enum StairComponents {
    /// The components an older (shape-only) stair stands for, with `risers` risers and tread depth `tread`: the same
    /// straight, L- or U-shaped flights and landings the old stairs drew.
    public static func legacy(_ s: StairData, risers n: Int, tread: Double) -> (runs: [StairRun], landings: [StairLanding]) {
        let dir = Vec2.fromAngle(s.direction)
        let w = s.width
        switch s.shape {
        case .straight:
            return ([StairRun(start: s.origin, direction: s.direction, risers: n, width: w)], [])
        case .lShaped, .uShaped:
            let n1 = max(2, min(n - 2, s.firstRunRisers ?? n / 2))
            let n2 = n - n1
            let run1End = s.origin + dir * (Double(n1 - 1) * tread)
            let side = dir.perpendicular * (s.turnsLeft ? 1 : -1)
            let r1 = StairRun(start: s.origin, direction: s.direction, risers: n1, width: w)
            if s.shape == .lShaped {
                let start2 = run1End + dir * (w / 2) + side * (w / 2)
                return ([r1, StairRun(start: start2, direction: side.angle, risers: n2, width: w)], [StairLanding(afterRun: 0)])
            }
            let start2 = run1End + side * (w + 0.1)
            return ([r1, StairRun(start: start2, direction: (-dir).angle, risers: n2, width: w)], [StairLanding(afterRun: 0)])
        }
    }

    /// Shares `total` risers between runs in proportion to their current counts (a multistory storey of a different
    /// height, a changed Desired Number of Risers on a stair drawn before). Sketched runs keep their riser lines.
    public static func redistribute(_ runs: [StairRun], to total: Int) -> [StairRun] {
        let current = runs.reduce(0) { $0 + $1.risers }
        guard current > 0, total != current else { return runs }
        var out = runs
        var left = total
        for i in out.indices {
            let remaining = out.count - i - 1
            if out[i].shape == .sketch { left -= out[i].risers; continue }
            let share = i == out.count - 1 ? left : Int((Double(total) * Double(runs[i].risers) / Double(current)).rounded())
            let n = max(2, min(share, left - 2 * remaining))
            out[i].risers = n
            left -= n
        }
        return out
    }
}
