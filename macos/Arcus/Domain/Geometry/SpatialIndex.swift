import Foundation

/// Integer cell coordinate of a uniform 2D grid.
struct GridCell: Hashable, Sendable {
    var x: Int32
    var y: Int32
}

/// A uniform-grid spatial index over axis-aligned 2D bounds.
///
/// Items are bucketed into every cell their bounds overlap. Items whose bounds
/// would cover more than `maxCellsPerItem` cells (or that are unbounded) go to an
/// overflow list that every query scans, so a few huge items never blow up memory.
/// Query results are deduplicated and returned in insertion order, which keeps
/// every consumer deterministic even though `ID` is only `Hashable`.
public struct SpatialGrid<ID: Hashable & Sendable>: Sendable {
    /// Edge length of a grid cell in model units.
    public let cellSize: Double
    private let inverseCell: Double
    private var cells: [GridCell: [ID]] = [:]
    private var items: [ID: Entry] = [:]
    private var overflow: [ID] = []
    private var nextSequence = 0

    /// Items covering more cells than this live in the overflow list.
    static var maxCellsPerItem: Int { 4096 }
    /// Cell coordinates beyond this magnitude are treated as unbounded.
    private static var maxCellCoordinate: Double { 1.0e9 }

    private struct Entry: Sendable {
        var bounds: Rect2
        var sequence: Int
        var inOverflow: Bool
    }

    /// Creates an empty grid. `cellSize` should be of the order of a typical item size.
    public init(cellSize: Double) {
        let c = cellSize.isFinite && cellSize > Tolerance.length ? cellSize : 1.0
        self.cellSize = c
        self.inverseCell = 1.0 / c
    }

    /// Number of items stored.
    public var count: Int { items.count }

    /// Inserts (or replaces) an item with the given bounds.
    public mutating func insert(_ id: ID, bounds: Rect2) {
        if items[id] != nil { remove(id) }
        let seq = nextSequence
        nextSequence += 1
        guard let range = cellRange(bounds), range.count <= Self.maxCellsPerItem else {
            items[id] = Entry(bounds: bounds, sequence: seq, inOverflow: true)
            overflow.append(id)
            return
        }
        items[id] = Entry(bounds: bounds, sequence: seq, inOverflow: false)
        for cy in range.y0...range.y1 {
            for cx in range.x0...range.x1 {
                cells[GridCell(x: cx, y: cy), default: []].append(id)
            }
        }
    }

    /// Removes an item if present.
    public mutating func remove(_ id: ID) {
        guard let e = items.removeValue(forKey: id) else { return }
        if e.inOverflow {
            if let i = overflow.firstIndex(of: id) { overflow.remove(at: i) }
            return
        }
        guard let range = cellRange(e.bounds) else { return }
        for cy in range.y0...range.y1 {
            for cx in range.x0...range.x1 {
                let key = GridCell(x: cx, y: cy)
                guard var list = cells[key], let i = list.firstIndex(of: id) else { continue }
                list.remove(at: i)
                cells[key] = list.isEmpty ? nil : list
            }
        }
    }

    /// Bounds an item was inserted with.
    public func bounds(of id: ID) -> Rect2? { items[id]?.bounds }

    /// All items whose bounds intersect `rect` (closed intervals), deduplicated, in insertion order.
    public func query(_ rect: Rect2) -> [ID] {
        guard !rect.isEmpty else { return [] }
        var found: [(Int, ID)] = []
        var seen = Set<ID>()
        func consider(_ id: ID) {
            guard let e = items[id], e.bounds.intersects(rect), seen.insert(id).inserted else { return }
            found.append((e.sequence, id))
        }
        if let range = cellRange(rect), range.count <= max(cells.count, 16) {
            for cy in range.y0...range.y1 {
                for cx in range.x0...range.x1 {
                    if let list = cells[GridCell(x: cx, y: cy)] { for id in list { consider(id) } }
                }
            }
            for id in overflow { consider(id) }
        } else {
            // Query larger than the populated grid: a linear scan is cheaper.
            for (id, e) in items where e.bounds.intersects(rect) {
                found.append((e.sequence, id))
            }
        }
        found.sort { $0.0 < $1.0 }
        return found.map(\.1)
    }

    /// All items whose bounds come within `radius` of `point`, deduplicated, in insertion order.
    public func query(point: Vec2, radius: Double) -> [ID] {
        let r = max(radius, 0)
        let candidates = query(Rect2(center: point, halfSize: Vec2(r, r)))
        return candidates.filter { id in
            guard let b = items[id]?.bounds else { return false }
            let dx = max(b.min.x - point.x, 0, point.x - b.max.x)
            let dy = max(b.min.y - point.y, 0, point.y - b.max.y)
            return dx * dx + dy * dy <= r * r
        }
    }

    private struct CellRange {
        var x0: Int32, y0: Int32, x1: Int32, y1: Int32
        var count: Int { (Int(x1) - Int(x0) + 1) * (Int(y1) - Int(y0) + 1) }
    }

    private func cellRange(_ r: Rect2) -> CellRange? {
        guard !r.isEmpty else { return nil }
        let fx0 = (r.min.x * inverseCell).rounded(.down), fy0 = (r.min.y * inverseCell).rounded(.down)
        let fx1 = (r.max.x * inverseCell).rounded(.down), fy1 = (r.max.y * inverseCell).rounded(.down)
        let lim = Self.maxCellCoordinate
        guard fx0.isFinite, fy0.isFinite, fx1.isFinite, fy1.isFinite,
              abs(fx0) < lim, abs(fy0) < lim, abs(fx1) < lim, abs(fy1) < lim,
              fx1 - fx0 < lim, fy1 - fy0 < lim else { return nil }
        let range = CellRange(x0: Int32(fx0), y0: Int32(fy0), x1: Int32(fx1), y1: Int32(fy1))
        return (fx1 - fx0 + 1) * (fy1 - fy0 + 1) > Double(Int32.max) ? nil : range
    }
}

extension SpatialGrid {
    /// A cell size heuristic for `n` items spread over `extent`, given their mean size.
    static func suggestedCellSize(extent: Rect2, count n: Int, meanItemSize: Double) -> Double {
        let span = max(extent.width, extent.height, Tolerance.length)
        let byCount = span / max(1, Double(n).squareRoot())
        let c = max(meanItemSize, byCount * 0.5, span / 4096, Tolerance.length * 100)
        return c.isFinite ? c : 1
    }
}

/// Welds nearly coincident 3D points to shared ids using a hashed grid.
/// Ids are assigned in first-seen order, so results are deterministic.
struct PointWelder3 {
    let tolerance: Double
    private let inverseCell: Double
    private var buckets: [SIMD3<Int64>: [Int]] = [:]
    private(set) var points: [Vec3] = []

    init(tolerance: Double) {
        self.tolerance = max(tolerance, Double.leastNormalMagnitude)
        inverseCell = 1 / self.tolerance
    }

    private func key(_ p: Vec3) -> SIMD3<Int64> {
        func c(_ v: Double) -> Int64 {
            let f = (v * inverseCell).rounded(.down)
            return f.isFinite ? Int64(max(-9.0e17, min(9.0e17, f))) : 0
        }
        return SIMD3(c(p.x), c(p.y), c(p.z))
    }

    /// Returns the id of an existing point within tolerance, or registers `p`.
    mutating func id(for p: Vec3) -> Int {
        let k = key(p)
        let t2 = tolerance * tolerance
        var best = -1
        var bestD = Double.infinity
        for dz in -1...1 {
            for dy in -1...1 {
                for dx in -1...1 {
                    guard let list = buckets[k &+ SIMD3(Int64(dx), Int64(dy), Int64(dz))] else { continue }
                    for i in list {
                        let d = (points[i] - p).lengthSquared
                        if d <= t2 && (d < bestD || (d == bestD && i < best)) { best = i; bestD = d }
                    }
                }
            }
        }
        if best >= 0 { return best }
        let id = points.count
        points.append(p)
        buckets[k, default: []].append(id)
        return id
    }
}

/// Welds nearly coincident 2D points to shared ids using a hashed grid.
struct PointWelder2 {
    let tolerance: Double
    private let inverseCell: Double
    private var buckets: [SIMD2<Int64>: [Int]] = [:]
    private(set) var points: [Vec2] = []

    init(tolerance: Double) {
        self.tolerance = max(tolerance, Double.leastNormalMagnitude)
        inverseCell = 1 / self.tolerance
    }

    private func key(_ p: Vec2) -> SIMD2<Int64> {
        func c(_ v: Double) -> Int64 {
            let f = (v * inverseCell).rounded(.down)
            return f.isFinite ? Int64(max(-9.0e17, min(9.0e17, f))) : 0
        }
        return SIMD2(c(p.x), c(p.y))
    }

    /// Nearest existing point id within tolerance, if any.
    func find(_ p: Vec2) -> Int? {
        let k = key(p)
        let t2 = tolerance * tolerance
        var best = -1
        var bestD = Double.infinity
        for dy in -1...1 {
            for dx in -1...1 {
                guard let list = buckets[k &+ SIMD2(Int64(dx), Int64(dy))] else { continue }
                for i in list {
                    let d = points[i].distanceSquared(to: p)
                    if d <= t2 && (d < bestD || (d == bestD && i < best)) { best = i; bestD = d }
                }
            }
        }
        return best >= 0 ? best : nil
    }

    /// Returns the id of an existing point within tolerance, or registers `p`.
    mutating func id(for p: Vec2) -> Int {
        if let f = find(p) { return f }
        let id = points.count
        points.append(p)
        buckets[key(p), default: []].append(id)
        return id
    }
}
