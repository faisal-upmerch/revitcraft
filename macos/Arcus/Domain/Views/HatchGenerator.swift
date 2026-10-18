import Foundation
import Synchronization
import ArcusGeometry

// W4-HATCH: line-family hatch generation shared by every renderer (Metal, CoreGraphics/PDF, DXF line fallback).

/// Hatch lines of one fill, in view units, clipped to the region (even-odd, so holes stay empty).
public struct HatchLines: Hashable, Sendable {
    public var segments: [Segment2]
    /// Zero-length dashes: drawn as pen-width dots.
    public var dots: [Vec2]
    /// The smallest family spacing in view units (renderers switch to a tint when this is under ~2 device pixels).
    public var minSpacing: Double
    public var isEmpty: Bool { segments.isEmpty && dots.isEmpty }
}

/// Generates the lines of a `HatchPattern` inside polygons. Patterns are anchored at the view origin so they don't
/// swim when a region moves or the view pans; drafting patterns are sized on paper (scale-dependent in view units),
/// model patterns in model units.
public enum HatchGenerator {
    /// Segments + dots a single fill may produce before the renderer falls back to the procedural kind.
    public static let maxMarks = 60_000
    /// Parallel lines a single family may produce.
    static let maxLines = 20_000

    /// View units per pattern millimetre: drafting patterns are paper mm (× scale), model patterns model mm.
    public static func viewUnitsPerMM(isModel: Bool, scale: Int) -> Double {
        isModel ? 0.001 : Double(max(scale, 1)) / 1000
    }

    /// The hatch of `pattern` inside `polys` (view units), or nil when it would exceed `budget` marks.
    public static func generate(_ polys: [Polygon2], _ pattern: HatchPattern, scale: Int, budget: Int = maxMarks) -> HatchLines? {
        let loops = polys.filter { $0.points.count >= 3 && $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } }
        guard !loops.isEmpty else { return HatchLines(segments: [], dots: [], minSpacing: 1) }
        var bb = Rect2.empty
        for p in loops { bb.include(p.bounds) }
        guard !bb.isEmpty, bb.width > 0 || bb.height > 0 else { return HatchLines(segments: [], dots: [], minSpacing: 1) }
        let k = viewUnitsPerMM(isModel: pattern.isModel, scale: scale)
        var edges: [(Vec2, Vec2)] = []
        for p in loops {
            let n = p.points.count
            for i in 0..<n { edges.append((p.points[i], p.points[(i + 1) % n])) }
        }
        var segments: [Segment2] = []
        var dots: [Vec2] = []
        var minSpacing = Double.infinity
        let corners = bb.corners
        for f in pattern.families where f.isValid {
            let s = f.spacing * k
            minSpacing = min(minSpacing, s)
            let a = f.angle * .pi / 180
            let d = Vec2(cos(a), sin(a)), n = Vec2(-sin(a), cos(a))
            let o = Vec2(f.origin.x * k, f.origin.y * k)
            let shift = f.shift * k
            let offsets = corners.map { ($0 - o).dot(n) }
            let i0 = Int((offsets.min()! / s).rounded(.down)), i1 = Int((offsets.max()! / s).rounded(.up))
            guard i0 <= i1 else { continue }
            if i1 - i0 > maxLines { return nil }
            let dashes = f.dashes.map { $0 * k }
            let period = dashes.reduce(0) { $0 + abs($1) }
            for i in i0...i1 {
                let base = o + n * (Double(i) * s) + d * (Double(i) * shift)
                var ts: [Double] = []
                for (p, q) in edges {
                    let dp = (p - base).dot(n), dq = (q - base).dot(n)
                    guard (dp >= 0) != (dq >= 0) else { continue }
                    let x = p + (q - p) * (dp / (dp - dq))
                    ts.append((x - base).dot(d))
                }
                guard ts.count >= 2 else { continue }
                ts.sort()
                var j = 0
                while j + 1 < ts.count {
                    let t0 = ts[j], t1 = ts[j + 1]
                    j += 2
                    guard t1 - t0 > 1e-9 else { continue }
                    if dashes.isEmpty || period <= 1e-9 {
                        segments.append(Segment2(base + d * t0, base + d * t1))
                    } else {
                        var pos = (t0 / period).rounded(.down) * period
                        while pos < t1 {
                            for len in dashes {
                                if len > 0 {
                                    let a0 = max(pos, t0), a1 = min(pos + len, t1)
                                    if a1 - a0 > 1e-9 { segments.append(Segment2(base + d * a0, base + d * a1)) }
                                } else if len == 0 {
                                    if pos >= t0 && pos <= t1 { dots.append(base + d * pos) }
                                }
                                pos += abs(len)
                                if pos >= t1 { break }
                            }
                        }
                    }
                    if segments.count + dots.count > budget { return nil }
                }
            }
        }
        return HatchLines(segments: segments, dots: dots, minSpacing: minSpacing.isFinite ? minSpacing : 1)
    }
}

/// Process-wide memo of generated hatches keyed by (region, pattern, scale): a view rebuilt after an unrelated edit
/// reuses every hatch it already had.
public final class HatchCache: Sendable {
    public static let shared = HatchCache()

    struct Key: Hashable {
        var polys: [Polygon2]
        var pattern: HatchPattern
        var scale: Int
    }
    struct Entry { var lines: HatchLines?; var tick: UInt64 }
    struct State { var entries: [Key: Entry] = [:]; var tick: UInt64 = 0; var hits = 0; var misses = 0 }

    let state = Mutex(State())
    /// Entries kept before the least recently used half is dropped.
    public let capacity: Int

    public init(capacity: Int = 4096) { self.capacity = capacity }

    /// Generated (or remembered) hatch lines; nil means the pattern is over budget for this region.
    public func lines(_ polys: [Polygon2], _ pattern: HatchPattern, scale: Int) -> HatchLines? {
        let key = Key(polys: polys, pattern: pattern, scale: max(scale, 1))
        let hit: HatchLines?? = state.withLock { s in
            s.tick &+= 1
            guard var e = s.entries[key] else { s.misses += 1; return nil }
            e.tick = s.tick
            s.entries[key] = e
            s.hits += 1
            return .some(e.lines)
        }
        if let hit { return hit }
        let lines = HatchGenerator.generate(polys, pattern, scale: key.scale)
        state.withLock { s in
            if s.entries.count >= capacity {
                let cut = s.entries.values.map(\.tick).sorted()[s.entries.count / 2]
                s.entries = s.entries.filter { $0.value.tick > cut }
            }
            s.entries[key] = Entry(lines: lines, tick: s.tick)
        }
        return lines
    }

    public var statistics: (entries: Int, hits: Int, misses: Int) { state.withLock { ($0.entries.count, $0.hits, $0.misses) } }
    public func removeAll() { state.withLock { $0 = State() } }
}
