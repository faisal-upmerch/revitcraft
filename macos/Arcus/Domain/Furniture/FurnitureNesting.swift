import Foundation
import ArcusGeometry

// FM7: the nesting engine (Docs/FurnitureMode.md §3 "Fabrication outputs"). Pure and deterministic: rectangular parts
// are laid out on stock sheets with guillotine or maxrects packing and a best-fit rule, the kerf between parts and the
// edge trim round the sheet respected. Grain-locked parts keep their grain along the sheet's grain (they don't rotate);
// parts without grain rotate when the stock allows it. Parts larger than the stock are reported, not placed.
// `FurnitureNestingModel` builds the inputs from the Part List and the document's Stock Sheets.

/// How the engine packs parts.
public enum NestingMethod: String, Codable, Sendable, CaseIterable {
    /// Tries every method and part order and keeps the layout with the fewest sheets (then the emptiest last sheet).
    case best = "Best"
    /// Guillotine cuts only (every cut runs edge to edge, as on a panel saw).
    case guillotine = "Guillotine"
    /// Maximal rectangles (tighter; for CNC routers).
    case maxRects = "MaxRects"
}

/// One piece to nest (a part with quantity 3 is three items).
public struct NestItem: Hashable, Sendable {
    /// Unique within one run.
    public var key: String
    /// What the layout shows on the piece (its Mark).
    public var label: String
    /// Along the part's length.
    public var length: Double
    public var width: Double
    /// The part's grain: along its length, its width, or none.
    public var grain: GrainDirection
    public init(key: String, label: String, length: Double, width: Double, grain: GrainDirection) {
        self.key = key; self.label = label; self.length = length; self.width = width; self.grain = grain
    }
    public var area: Double { length * width }
}

/// The stock the items are cut from. The sheet's length runs along x, its width along y.
public struct NestStock: Hashable, Sendable {
    public var length: Double
    public var width: Double
    /// The sheet's grain: along its length (x), its width (y), or none.
    public var grain: GrainDirection
    /// Saw or bit width between parts.
    public var kerf: Double
    /// Trimmed off every edge of the sheet before cutting.
    public var trim: Double
    /// Parts without grain may turn 90°.
    public var allowRotation: Bool
    public init(length: Double, width: Double, grain: GrainDirection = .length, kerf: Double = 0.125 * 0.0254, trim: Double = 0.25 * 0.0254,
                allowRotation: Bool = true) {
        self.length = length; self.width = width; self.grain = grain; self.kerf = kerf; self.trim = trim; self.allowRotation = allowRotation
    }
    public var area: Double { length * width }
}

/// A piece on a sheet: its rectangle in sheet coordinates (origin at the sheet's lower-left corner).
public struct NestPlacement: Hashable, Sendable {
    public var key: String
    public var label: String
    public var rect: Rect2
    /// The part's length runs along the sheet's width (y).
    public var rotated: Bool
    public var grain: GrainDirection
}

/// One stock sheet with its pieces and what's left.
public struct NestSheet: Hashable, Sendable {
    public var stock: NestStock
    public var placements: [NestPlacement]
    /// Disjoint leftover rectangles inside the trim (offcuts), largest first.
    public var offcuts: [Rect2]
    /// Area of the pieces over the sheet's area (0…1).
    public var yield: Double { stock.area > 0 ? placements.reduce(0) { $0 + $1.rect.width * $1.rect.height } / stock.area : 0 }
}

/// A nesting run's result.
public struct NestResult: Hashable, Sendable {
    public var sheets: [NestSheet]
    /// Pieces that don't fit the stock in any allowed orientation.
    public var oversize: [NestItem]
    /// The method that produced the layout (never `.best`).
    public var method: NestingMethod
    /// All pieces over all sheets (0…1).
    public var yield: Double {
        let a = sheets.reduce(0) { $0 + $1.stock.area }
        return a > 0 ? sheets.reduce(0) { $0 + $1.yield * $1.stock.area } / a : 0
    }
}

public enum NestingEngine {
    static let eps = 1e-9

    /// Lays `items` out on as many `stock` sheets as needed.
    public static func nest(_ items: [NestItem], on stock: NestStock, method: NestingMethod = .best) -> NestResult {
        let binW = stock.length - 2 * stock.trim + stock.kerf, binH = stock.width - 2 * stock.trim + stock.kerf
        var fits: [NestItem] = [], oversize: [NestItem] = []
        for it in items {
            let o = orientations(it, stock)
            if o.contains(where: { $0.w + stock.kerf <= binW + eps && $0.h + stock.kerf <= binH + eps }) { fits.append(it) } else { oversize.append(it) }
        }
        let variants: [(NestingMethod, Heuristic, Order)]
        switch method {
        case .guillotine: variants = Order.allCases.map { (.guillotine, .shortSide, $0) }
        case .maxRects: variants = Order.allCases.flatMap { o in [(NestingMethod.maxRects, Heuristic.shortSide, o), (.maxRects, .area, o)] }
        case .best: variants = Order.allCases.flatMap { o in [(NestingMethod.maxRects, Heuristic.shortSide, o), (.maxRects, .area, o), (.guillotine, .shortSide, o)] }
        }
        var best: NestResult?
        var bestKey = (Int.max, Double.infinity)
        for (m, h, o) in variants {
            let sheets = run(sorted(fits, o), stock, m, h, binW: binW, binH: binH)
            let key = (sheets.count, sheets.last.map { s in s.placements.reduce(0) { $0 + $1.rect.width * $1.rect.height } } ?? 0)
            if key.0 < bestKey.0 || (key.0 == bestKey.0 && key.1 < bestKey.1 - eps) {
                bestKey = key
                best = NestResult(sheets: sheets, oversize: oversize, method: m)
            }
        }
        return best ?? NestResult(sheets: [], oversize: oversize, method: method == .best ? .maxRects : method)
    }

    /// The orientations a piece may take on the stock: (w along x, h along y, rotated).
    static func orientations(_ it: NestItem, _ s: NestStock) -> [(w: Double, h: Double, rotated: Bool)] {
        let flat = (w: it.length, h: it.width, rotated: false), turned = (w: it.width, h: it.length, rotated: true)
        if it.grain != .none, s.grain != .none {
            // The part's grain must run along the sheet's grain.
            let partAlongX = it.grain == .length, sheetAlongX = s.grain == .length
            return [partAlongX == sheetAlongX ? flat : turned]
        }
        if s.allowRotation, abs(it.length - it.width) > eps { return [flat, turned] }
        return [flat]
    }

    enum Heuristic { case shortSide, area }
    enum Order: CaseIterable { case area, longSide, perimeter }

    static func sorted(_ items: [NestItem], _ o: Order) -> [NestItem] {
        func k(_ i: NestItem) -> (Double, Double) {
            switch o {
            case .area: (i.area, max(i.length, i.width))
            case .longSide: (max(i.length, i.width), min(i.length, i.width))
            case .perimeter: (i.length + i.width, i.area)
            }
        }
        return items.enumerated().sorted { a, b in
            let ka = k(a.element), kb = k(b.element)
            if abs(ka.0 - kb.0) > eps { return ka.0 > kb.0 }
            if abs(ka.1 - kb.1) > eps { return ka.1 > kb.1 }
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Packing

    struct R: Hashable { var x, y, w, h: Double
        var maxX: Double { x + w }
        var maxY: Double { y + h }
        func contains(_ o: R) -> Bool { o.x >= x - NestingEngine.eps && o.y >= y - NestingEngine.eps && o.maxX <= maxX + NestingEngine.eps && o.maxY <= maxY + NestingEngine.eps }
        func intersects(_ o: R) -> Bool { o.x < maxX - NestingEngine.eps && o.maxX > x + NestingEngine.eps && o.y < maxY - NestingEngine.eps && o.maxY > y + NestingEngine.eps }
    }

    /// One bin being filled: its free rectangles (overlapping for maxrects, disjoint for guillotine) and pieces.
    struct Bin {
        var free: [R]
        var placed: [(item: NestItem, r: R, rotated: Bool)] = []
    }

    /// A candidate position: lower scores are better.
    struct Fit { var s1: Double; var s2: Double; var freeIndex: Int; var r: R; var rotated: Bool }

    static func run(_ items: [NestItem], _ stock: NestStock, _ method: NestingMethod, _ h: Heuristic, binW: Double, binH: Double) -> [NestSheet] {
        var bins: [Bin] = []
        for it in items {
            let sizes = orientations(it, stock).map { (w: $0.w + stock.kerf, h: $0.h + stock.kerf, rotated: $0.rotated) }
            var bestFit: (bin: Int, fit: Fit)?
            for (bi, bin) in bins.enumerated() {
                guard let f = fit(bin, sizes, h) else { continue }
                if bestFit == nil || better(f, bestFit!.fit) { bestFit = (bi, f) }
            }
            if bestFit == nil {
                let fresh = Bin(free: [R(x: 0, y: 0, w: binW, h: binH)])
                guard let f = fit(fresh, sizes, h) else { continue }
                bins.append(fresh)
                bestFit = (bins.count - 1, f)
            }
            guard let (bi, f) = bestFit else { continue }
            if method == .guillotine { placeGuillotine(&bins[bi], f) } else { placeMaxRects(&bins[bi], f.r) }
            bins[bi].placed.append((it, f.r, f.rotated))
        }
        return bins.map { b in
            let placements = b.placed.map { p in
                NestPlacement(key: p.item.key, label: p.item.label,
                              rect: Rect2(min: Vec2(stock.trim + p.r.x, stock.trim + p.r.y),
                                          max: Vec2(stock.trim + p.r.x + p.r.w - stock.kerf, stock.trim + p.r.y + p.r.h - stock.kerf)),
                              rotated: p.rotated, grain: p.item.grain)
            }
            return NestSheet(stock: stock, placements: placements, offcuts: offcuts(b, method, stock, binW: binW, binH: binH))
        }
    }

    static func better(_ a: Fit, _ b: Fit) -> Bool { a.s1 < b.s1 - eps || (abs(a.s1 - b.s1) <= eps && a.s2 < b.s2 - eps) }

    /// The best position for one of `sizes` in the bin's free rectangles (best short side fit or best area fit).
    static func fit(_ bin: Bin, _ sizes: [(w: Double, h: Double, rotated: Bool)], _ h: Heuristic) -> Fit? {
        var best: Fit?
        for (i, f) in bin.free.enumerated() {
            for s in sizes where s.w <= f.w + eps && s.h <= f.h + eps {
                let dw = f.w - s.w, dh = f.h - s.h
                let c: Fit
                switch h {
                case .shortSide: c = Fit(s1: min(dw, dh), s2: max(dw, dh), freeIndex: i, r: R(x: f.x, y: f.y, w: s.w, h: s.h), rotated: s.rotated)
                case .area: c = Fit(s1: f.w * f.h - s.w * s.h, s2: min(dw, dh), freeIndex: i, r: R(x: f.x, y: f.y, w: s.w, h: s.h), rotated: s.rotated)
                }
                if best == nil || better(c, best!) || (!better(best!, c) && (c.r.y < best!.r.y - eps || (abs(c.r.y - best!.r.y) <= eps && c.r.x < best!.r.x - eps))) {
                    best = c
                }
            }
        }
        return best
    }

    /// Maxrects: every free rectangle the piece overlaps splits into up to four maximal ones; contained ones go.
    static func placeMaxRects(_ bin: inout Bin, _ r: R) {
        var out: [R] = []
        out.reserveCapacity(bin.free.count + 4)
        for f in bin.free {
            guard f.intersects(r) else { out.append(f); continue }
            if r.x > f.x + eps { out.append(R(x: f.x, y: f.y, w: r.x - f.x, h: f.h)) }
            if r.maxX < f.maxX - eps { out.append(R(x: r.maxX, y: f.y, w: f.maxX - r.maxX, h: f.h)) }
            if r.y > f.y + eps { out.append(R(x: f.x, y: f.y, w: f.w, h: r.y - f.y)) }
            if r.maxY < f.maxY - eps { out.append(R(x: f.x, y: r.maxY, w: f.w, h: f.maxY - r.maxY)) }
        }
        // Prune rectangles inside others (keep the first of equal ones).
        var keep = [Bool](repeating: true, count: out.count)
        for i in out.indices where keep[i] {
            for j in out.indices where j != i && keep[j] {
                if out[j].contains(out[i]) && (out[i] != out[j] || j < i) { keep[i] = false; break }
            }
        }
        bin.free = out.indices.filter { keep[$0] }.map { out[$0] }
    }

    /// Guillotine: the free rectangle splits in two along its shorter leftover axis.
    static func placeGuillotine(_ bin: inout Bin, _ f: Fit) {
        let fr = bin.free.remove(at: f.freeIndex)
        let dw = fr.w - f.r.w, dh = fr.h - f.r.h
        // Shorter axis split: cut across the shorter leftover so the longer leftover stays whole.
        let horizontal = dw <= dh
        let right = R(x: fr.x + f.r.w, y: fr.y, w: dw, h: horizontal ? f.r.h : fr.h)
        let top = R(x: fr.x, y: fr.y + f.r.h, w: horizontal ? fr.w : f.r.w, h: dh)
        for n in [right, top] where n.w > eps && n.h > eps { bin.free.append(n) }
    }

    /// Disjoint leftovers of the bin, back in sheet coordinates (kerf removed from their far sides), largest first.
    static func offcuts(_ b: Bin, _ method: NestingMethod, _ stock: NestStock, binW: Double, binH: Double) -> [Rect2] {
        var rects = b.free
        if method != .guillotine {
            // Maxrects free rectangles overlap: take the largest, subtract it from the rest, repeat.
            var pool = rects.sorted { $0.w * $0.h > $1.w * $1.h }
            rects = []
            while let first = pool.first {
                pool.removeFirst()
                rects.append(first)
                pool = pool.flatMap { subtract($0, first) }.filter { $0.w > 1e-4 && $0.h > 1e-4 }.sorted { $0.w * $0.h > $1.w * $1.h }
            }
        }
        let limitX = stock.length - stock.trim, limitY = stock.width - stock.trim
        return rects.compactMap { r -> Rect2? in
            let x0 = stock.trim + r.x, y0 = stock.trim + r.y
            let x1 = min(limitX, stock.trim + r.maxX), y1 = min(limitY, stock.trim + r.maxY)
            guard x1 - x0 > 1e-4, y1 - y0 > 1e-4 else { return nil }
            return Rect2(min: Vec2(x0, y0), max: Vec2(x1, y1))
        }.sorted { $0.width * $0.height > $1.width * $1.height }
    }

    /// `a` minus `b`, as up to four disjoint rectangles.
    static func subtract(_ a: R, _ b: R) -> [R] {
        guard a.intersects(b) else { return [a] }
        var out: [R] = []
        let iy0 = max(a.y, b.y), iy1 = min(a.maxY, b.maxY)
        if b.y > a.y + eps { out.append(R(x: a.x, y: a.y, w: a.w, h: b.y - a.y)) }
        if b.maxY < a.maxY - eps { out.append(R(x: a.x, y: b.maxY, w: a.w, h: a.maxY - b.maxY)) }
        if b.x > a.x + eps { out.append(R(x: a.x, y: iy0, w: b.x - a.x, h: iy1 - iy0)) }
        if b.maxX < a.maxX - eps { out.append(R(x: b.maxX, y: iy0, w: a.maxX - b.maxX, h: iy1 - iy0)) }
        return out
    }
}
