import Foundation
import ArcusGeometry

/// A problem with the lines of a closed-loop sketch, naming the lines involved (indices into the sketch's curves)
/// so sketch mode can highlight them (BL-CANVAS, ARCUS-050).
public struct SketchIssue: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case empty, openLoop, intersecting, overlapping, degenerate, profile }
    public var kind: Kind
    public var curves: [Int]
    public var message: String
    public init(_ kind: Kind, curves: [Int], _ message: String) { self.kind = kind; self.curves = curves.sorted(); self.message = message }
}

/// Checks the lines of a boundary sketch before Finish: ends that don't meet exactly one other line, lines that
/// cross or overlap, and loops the profile builder rejects (holes outside the boundary, loops that touch).
public enum SketchValidation {
    static let tolerance = Tolerance.length * 10

    /// Issues in order of importance (open ends first, then crossings); empty when the sketch is valid.
    public static func issues(_ curves: [Curve2]) -> [SketchIssue] {
        guard !curves.isEmpty else { return [SketchIssue(.empty, curves: [], "The sketch has no lines. Draw at least one closed loop.")] }
        var out: [SketchIssue] = []
        let tiny = curves.indices.filter { curves[$0].length <= Tolerance.shortCurve }
        if !tiny.isEmpty { out.append(SketchIssue(.degenerate, curves: tiny, "The highlighted lines are too short to use.")) }
        // Duplicates: the same line drawn twice.
        var duplicates = Set<Int>()
        for i in curves.indices { for j in curves.indices where j > i && same(curves[i], curves[j]) { duplicates.formUnion([i, j]) } }
        if !duplicates.isEmpty { out.append(SketchIssue(.overlapping, curves: Array(duplicates), "The highlighted lines overlap. Delete one of each pair.")) }
        // Every end must meet exactly one other line end.
        var open = Set<Int>()
        for i in curves.indices where !duplicates.contains(i) {
            for p in [curves[i].start, curves[i].end] {
                var meets = 0
                for j in curves.indices where j != i && !duplicates.contains(j) {
                    if curves[j].start.isAlmostEqual(p, tolerance: tolerance) { meets += 1 }
                    if curves[j].end.isAlmostEqual(p, tolerance: tolerance) { meets += 1 }
                }
                if meets != 1 { open.insert(i) }
            }
        }
        if !open.isEmpty {
            out.append(SketchIssue(.openLoop, curves: Array(open),
                                   "Lines must form closed loops. The highlighted lines are open at one end or meet more than one other line."))
        }
        // Lines may touch only at shared ends.
        var crossing = Set<Int>()
        for i in curves.indices where !duplicates.contains(i) {
            for j in curves.indices where j > i && !duplicates.contains(j) {
                guard curves[i].bounds.expanded(by: tolerance).intersects(curves[j].bounds) else { continue }
                let shared = [curves[i].start, curves[i].end].filter { p in curves[j].start.isAlmostEqual(p, tolerance: tolerance) || curves[j].end.isAlmostEqual(p, tolerance: tolerance) }
                for p in curves[i].intersections(with: curves[j]) where !shared.contains(where: { $0.isAlmostEqual(p, tolerance: tolerance) }) {
                    crossing.formUnion([i, j])
                }
            }
        }
        if !crossing.isEmpty { out.append(SketchIssue(.intersecting, curves: Array(crossing), "Lines must not cross or overlap. The highlighted lines intersect.")) }
        return out
    }

    /// Full check for closed-loop sketches: line issues first, then the loops as a profile.
    public static func validate(_ curves: [Curve2], loops: [[Curve2]]) -> SketchIssue? {
        if let first = issues(curves).first { return first }
        if case .failure(let err) = Sketch(loops: loops).profile() {
            let involved: [Int]
            switch err {
            case .openLoop(let k), .degenerateLoop(let k), .selfIntersecting(let k):
                involved = k < loops.count ? curves.indices.filter { i in loops[k].contains(curves[i]) } : []
            default: involved = Array(curves.indices)
            }
            return SketchIssue(.profile, curves: involved, err.description)
        }
        return nil
    }

    static func same(_ a: Curve2, _ b: Curve2) -> Bool {
        let t = tolerance
        let ends = (a.start.isAlmostEqual(b.start, tolerance: t) && a.end.isAlmostEqual(b.end, tolerance: t))
            || (a.start.isAlmostEqual(b.end, tolerance: t) && a.end.isAlmostEqual(b.start, tolerance: t))
        guard ends else { return false }
        return a.midpoint.isAlmostEqual(b.midpoint, tolerance: t)
    }
}
