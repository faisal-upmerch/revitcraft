import Foundation
import ArcusGeometry
import ArcusCalc
import ArcusDomain

// F2: roof footprint sketches gain slope arrows and the eave tools (RevitCraft: the Draw panel's Boundary Line / Slope
// Arrow, the roof Tools panel's Align Eaves with Adjust Height and Adjust Overhang).

/// How Align Eaves brings a picked eave to the reference eave's height.
public enum EaveAdjustment: String, Sendable, CaseIterable {
    /// The eave line stays; its height changes (the roof plane rises or drops with it).
    case height = "Adjust Height"
    /// The roof plane stays; the eave line moves in or out (the overhang changes) until it reaches the height.
    case overhang = "Adjust Overhang"
}

/// The F2 part of a sketch's state.
struct SketchF2State {
    /// Roof slope arrows drawn in this sketch.
    var roofArrows: [SlopeArrow] = []
    /// Eave heights above the roof base, by footprint line (lines without one sit at the base).
    var eaveOffsets: [Curve2: Double] = [:]
    var aligningEaves = false
    var adjustment = EaveAdjustment.height
    /// Align Eaves: the line picked as the height to match.
    var reference: Curve2?

    mutating func load(_ r: RoofData) {
        roofArrows = r.slopeArrows ?? []
        for (k, c) in (r.footprint.loops.first ?? []).enumerated() {
            let o = RoofSlopeArrows.eaveOffset(r, curve: k)
            if o != 0 { eaveOffsets[c] = o }
        }
    }
}

extension SketchTool {
    /// The Draw panel's Slope Arrow is on.
    public var isDrawingSlopeArrow: Bool { arrowMode }
    /// The roof Tools panel's Align Eaves is on.
    public var isAligningEaves: Bool { f2.aligningEaves }
    public var eaveAdjustment: EaveAdjustment { f2.adjustment }
    public var roofSlopeArrows: [SlopeArrow] { f2.roofArrows }
    /// Eave height above the roof base of a sketch line (0 unless aligned).
    public func eaveOffset(of c: Curve2) -> Double { f2.eaveOffsets[c] ?? f2.eaveOffsets[c.reversed] ?? 0 }

    /// Boundary Line: draws boundary lines again (leaves Slope Arrow and Align Eaves).
    public func drawBoundaryLines() {
        arrowMode = false; f2.aligningEaves = false; f2.reference = nil; start = nil
        rebuild()
    }

    /// Slope Arrow: the next two clicks are the arrow's tail (on the edge that slopes) and head.
    public func drawSlopeArrow() {
        guard [.floor, .ceiling, .roof].contains(target) else { return }
        arrowMode = true; f2.aligningEaves = false; f2.reference = nil; start = nil
        rebuild()
    }

    /// Align Eaves (roofs): pick the eave to match, then the eaves to align with it.
    public func alignEaves() {
        guard target == .roof else { return }
        f2.aligningEaves.toggle()
        f2.reference = nil; arrowMode = false; start = nil
        rebuild()
    }

    /// Adjust Height / Adjust Overhang: how the eaves picked next are aligned. Available in Align Eaves mode.
    public func setEaveAdjustment(_ a: EaveAdjustment) {
        guard f2.aligningEaves else { message("Click Align Eaves first."); return }
        f2.adjustment = a
        rebuild()
    }

    var f2Prompt: String? {
        guard f2.aligningEaves else { return nil }
        return f2.reference == nil ? "Align Eaves: pick the eave whose height the others should match."
            : "\(f2.adjustment.rawValue): pick the eaves to align with the highlighted one. Boundary Line ends Align Eaves."
    }

    func f2AddRoofArrow(tail: Vec2, head: Vec2) {
        f2.roofArrows.append(SlopeArrow(tail: tail, head: head, slope: tan(defaultSlope)))
        if RoofSlopeArrows.edgeSlope(for: nearestCurve(tail) ?? .line(Segment2(tail, head)), f2.roofArrows) == nil {
            message("Start a slope arrow on a footprint line that doesn't define slope; the roof rises from that line toward the head.")
        }
        start = nil
        arrowMode = false
    }

    func nearestCurve(_ p: Vec2) -> Curve2? {
        curves.min { $0.distance(to: p) < $1.distance(to: p) }
    }

    /// Align Eaves clicks: the first picks the reference eave, later ones align eaves with it. True when handled.
    func f2PointerDown(_ p: Vec2) -> Bool {
        // Slope Arrow: a first click on an existing roof arrow removes it.
        if arrowMode, start == nil, target == .roof,
           let k = f2.roofArrows.firstIndex(where: { Segment2($0.tail, $0.head).distance(to: p) <= ctx.pixel * 6 }) {
            f2.roofArrows.remove(at: k)
            arrowMode = false
            message("Slope arrow removed.")
            return true
        }
        guard f2.aligningEaves else { return false }
        guard let k = curves.indices.min(by: { curves[$0].distance(to: p) < curves[$1].distance(to: p) }),
              curves[k].distance(to: p) <= ctx.pixel * 12 else { message("Pick a footprint line."); return true }
        guard let ref = f2.reference else { f2.reference = curves[k]; return true }
        guard curves[k] != ref else { return true }
        if let err = alignEave(k, to: eaveOffset(of: ref)) { message(err) }
        return true
    }

    /// Brings footprint line `k` to the eave height `h`: by its height (Adjust Height) or by moving it in or out along
    /// its roof plane (Adjust Overhang). Returns why it can't, or nil.
    func alignEave(_ k: Int, to h: Double) -> String? {
        let c = curves[k]
        let current = eaveOffset(of: c)
        switch f2.adjustment {
        case .height:
            setEaveOffset(c, h)
        case .overhang:
            guard k < slopes.count, let s = slopes[k], s > Tolerance.angle else { return "Adjust Overhang moves slope-defining eaves; this line doesn't define slope." }
            guard let seg = c.asSegment else { return "Adjust Overhang moves straight eaves." }
            // Moving the eave out by d along the plane lowers it by d·tan(slope).
            let d = (current - h) / tan(s)
            guard abs(d) > Tolerance.length else { setEaveOffset(c, h); return nil }
            let out = outwardNormal(seg)
            let moved = Segment2(seg.start + out * d, seg.end + out * d)
            replaceLine(k, with: moved)
            setEaveOffset(curves[k], h)
        }
        return nil
    }

    func setEaveOffset(_ c: Curve2, _ h: Double) {
        f2.eaveOffsets[c] = nil; f2.eaveOffsets[c.reversed] = nil
        if abs(h) > Tolerance.length { f2.eaveOffsets[c] = h }
    }

    /// The normal of a footprint line pointing away from the sketch (from the centre of the lines' ends).
    func outwardNormal(_ seg: Segment2) -> Vec2 {
        let ends = curves.flatMap { [$0.start, $0.end] }
        let centre = ends.reduce(Vec2.zero, +) * (1 / Double(max(1, ends.count)))
        let n = seg.normal
        return n.dot(seg.midpoint - centre) >= 0 ? n : n * -1
    }

    /// Replaces sketch line `k` by `moved`, extending or trimming the lines joined to its ends to meet it.
    func replaceLine(_ k: Int, with moved: Segment2) {
        let old = curves[k]
        let tol = Tolerance.length * 10
        for j in curves.indices where j != k {
            guard let s = curves[j].asSegment else { continue }
            for (end, oldEnd) in [(true, old.start), (true, old.end), (false, old.start), (false, old.end)] {
                let q = end ? s.end : s.start
                guard q.isAlmostEqual(oldEnd, tolerance: tol), let hit = s.lineIntersection(moved) else { continue }
                let off = f2.eaveOffsets[curves[j]]
                let updated: Curve2 = .line(end ? Segment2(s.start, hit.point) : Segment2(hit.point, s.end))
                f2.eaveOffsets[curves[j]] = nil
                curves[j] = updated
                if let off { f2.eaveOffsets[updated] = off }
                break
            }
        }
        f2.eaveOffsets[old] = nil
        curves[k] = .line(moved)
        if f2.reference == old { f2.reference = curves[k] }
    }

    /// The arrows to keep and the eave offsets of the outer loop's curves, in its order (nil when all are 0).
    func f2RoofEaves(_ outer: [Curve2]) -> (arrows: [SlopeArrow]?, offsets: [Double]?) {
        let offsets = outer.map { eaveOffset(of: $0) }
        return (f2.roofArrows.isEmpty ? nil : f2.roofArrows, offsets.contains { $0 != 0 } ? offsets : nil)
    }

    /// Roof slope arrows (heavy, with a head) and, in Align Eaves, the reference eave and the eave heights.
    func f2RebuildArrows() {
        for a in f2.roofArrows {
            preview.primitives.append(ctx.line(a.tail, a.head, heavy: true))
            let d = (a.head - a.tail).normalized
            let h = ctx.paper(0.003)
            preview.primitives.append(.polyline([a.head - d * h + d.perpendicular * h * 0.4, a.head, a.head - d * h - d.perpendicular * h * 0.4], closed: false, ctx.previewHeavy))
        }
        guard f2.aligningEaves else { return }
        if let r = f2.reference {
            preview.primitives.append(.polyline(r.tessellate(chordTolerance: 0.01), closed: false, GStroke(weight: 5, color: RGBColor(0.10, 0.45, 0.95))))
        }
        for c in curves {
            let o = eaveOffset(of: c)
            preview.primitives.append(.text(GText(position: c.midpoint, height: 0.0022, string: o == 0 ? "±0" : ctx.format(o), alignment: .center, verticalAnchor: 0)))
        }
    }
}
