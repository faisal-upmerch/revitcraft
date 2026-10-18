import CoreGraphics
import CoreText
import Foundation
import Metal

/// Identifies a glyph of a concrete font (fallback fonts included).
nonisolated struct GlyphKey: Hashable, Sendable, Comparable {
    let font: String
    let glyph: UInt16
    static func < (a: GlyphKey, b: GlyphKey) -> Bool { (a.font, a.glyph) < (b.font, b.glyph) }
}

/// Where a glyph lives in an atlas page.
nonisolated struct AtlasEntry: Sendable {
    /// Quad relative to the glyph origin in em units of the glyph's font.
    var planeMin: SIMD2<Float>
    var planeMax: SIMD2<Float>
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
}

/// Signed distance field of one glyph, `CanvasShaders.atlasEm` pixels per em, positive inside.
nonisolated struct GlyphBitmap: Sendable {
    let width: Int
    let height: Int
    /// Bottom-left corner of the bitmap relative to the glyph origin (atlas pixels, y up).
    let originX: Int
    let originY: Int
    /// Row-major, row 0 = top. Signed distance in atlas pixels, clamped to ±spread.
    let values: [Float16]
}

/// One 2048² R16Float atlas texture with a shelf packer. Pages are only appended to (new glyphs go into untouched
/// texels), so scenes that reference a page never see their glyphs move.
nonisolated final class GlyphAtlasPage: @unchecked Sendable {
    let texture: any MTLTexture
    let size: Int
    // Packer state and entries are guarded by `GlyphAtlas.lock`.
    fileprivate var cursorX = 1
    fileprivate var shelfY = 1
    fileprivate var shelfHeight = 0
    fileprivate var entries: [GlyphKey: AtlasEntry] = [:]

    init?(device: any MTLDevice, size: Int) {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r16Float, width: size, height: size, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        d.hazardTrackingMode = .untracked
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        t.label = "Arcus glyph atlas"
        // Everything outside glyph cells reads as "far outside" so bilinear taps at cell borders stay transparent.
        let row = [Float16](repeating: Float16(-CanvasShaders.atlasSpread), count: size)
        row.withUnsafeBytes { raw in
            for y in 0..<size {
                t.replace(region: MTLRegionMake2D(0, y, size, 1), mipmapLevel: 0, withBytes: raw.baseAddress!, bytesPerRow: size * 2)
            }
        }
        texture = t
        self.size = size
    }

    /// Allocates a cell; nil when the page is full.
    fileprivate func allocate(_ w: Int, _ h: Int) -> (x: Int, y: Int)? {
        let gap = 1
        if w + 2 * gap > size || h + 2 * gap > size { return nil }
        if cursorX + w + gap > size {
            shelfY += shelfHeight + gap
            cursorX = 1
            shelfHeight = 0
        }
        if shelfY + h + gap > size { return nil }
        let p = (cursorX, shelfY)
        cursorX += w + gap
        shelfHeight = max(shelfHeight, h)
        return p
    }
}

/// Process-wide cache of glyph distance fields and the atlas pages holding them. Thread-safe: scene builds on any
/// thread call `resolve`.
nonisolated final class GlyphAtlas: @unchecked Sendable {
    private let lock = NSLock()
    private let device: any MTLDevice
    private let pageSize: Int
    private var current: GlyphAtlasPage?
    /// nil value = glyph without outline (space).
    private var bitmaps: [GlyphKey: GlyphBitmap?] = [:]

    init(device: any MTLDevice, pageSize: Int = 2048) {
        self.device = device
        self.pageSize = pageSize
    }

    /// Returns one page that contains every drawable glyph of `fonts` (keys → font of the run that uses them).
    /// Glyphs are rasterised outside the lock; placement happens under it.
    func resolve(_ fonts: [GlyphKey: CTFont]) -> (page: GlyphAtlasPage, entries: [GlyphKey: AtlasEntry])? {
        let keys = fonts.keys.sorted()
        lock.lock()
        let missing = keys.filter { bitmaps[$0] == nil }
        lock.unlock()
        if !missing.isEmpty {
            var made: [GlyphKey: GlyphBitmap?] = [:]
            var atlasFonts: [String: CTFont] = [:]
            for k in missing {
                guard let f = fonts[k] else { continue }
                let af = atlasFonts[k.font] ?? CTFontCreateCopyWithAttributes(f, CGFloat(CanvasShaders.atlasEm), nil, nil)
                atlasFonts[k.font] = af
                made[k] = SDFRasterizer.rasterize(font: af, glyph: CGGlyph(k.glyph), spread: CanvasShaders.atlasSpread)
            }
            lock.lock()
            for (k, v) in made where bitmaps[k] == nil { bitmaps[k] = .some(v) }
            lock.unlock()
        }
        lock.lock()
        defer { lock.unlock() }
        if current == nil { current = GlyphAtlasPage(device: device, size: pageSize) }
        guard let page = current else { return nil }
        if let entries = place(keys, in: page) { return (page, entries) }
        // Page full: start a fresh page holding everything this scene needs.
        guard let fresh = GlyphAtlasPage(device: device, size: pageSize) else { return nil }
        current = fresh
        return (fresh, place(keys, in: fresh, allowPartial: true) ?? [:])
    }

    private func place(_ keys: [GlyphKey], in page: GlyphAtlasPage, allowPartial: Bool = false) -> [GlyphKey: AtlasEntry]? {
        var out: [GlyphKey: AtlasEntry] = [:]
        let inv = 1 / Float(page.size)
        let em = CanvasShaders.atlasEm
        for k in keys {
            if let e = page.entries[k] { out[k] = e; continue }
            guard case .some(.some(let bm)) = bitmaps[k] else { continue }
            guard let (x, y) = page.allocate(bm.width, bm.height) else {
                if allowPartial { continue }
                return nil
            }
            bm.values.withUnsafeBytes { raw in
                page.texture.replace(region: MTLRegionMake2D(x, y, bm.width, bm.height), mipmapLevel: 0,
                                     withBytes: raw.baseAddress!, bytesPerRow: bm.width * 2)
            }
            let e = AtlasEntry(
                planeMin: SIMD2(Float(bm.originX) / em, Float(bm.originY) / em),
                planeMax: SIMD2(Float(bm.originX + bm.width) / em, Float(bm.originY + bm.height) / em),
                uvMin: SIMD2(Float(x) * inv, Float(y + bm.height) * inv),
                uvMax: SIMD2(Float(x + bm.width) * inv, Float(y) * inv))
            page.entries[k] = e
            out[k] = e
        }
        return out
    }
}

/// Exact signed distance fields from glyph outlines (flattened Béziers; nonzero winding for the sign).
nonisolated enum SDFRasterizer {
    static func rasterize(font: CTFont, glyph: CGGlyph, spread: Float) -> GlyphBitmap? {
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let bb = path.boundingBoxOfPath
        guard !bb.isNull, !bb.isInfinite, bb.width > 0 || bb.height > 0 else { return nil }
        let pad = Int(spread.rounded(.up)) + 1
        let x0 = Int(bb.minX.rounded(.down)) - pad, y0 = Int(bb.minY.rounded(.down)) - pad
        let x1 = Int(bb.maxX.rounded(.up)) + pad, y1 = Int(bb.maxY.rounded(.up)) + pad
        let w = x1 - x0, h = y1 - y0
        guard w > 0, h > 0, w < 4096, h < 4096 else { return nil }
        let segs = flatten(path, dx: Double(x0), dy: Double(y0))
        if segs.isEmpty { return nil }

        // Unsigned distance within `spread` of each segment (pixel centres at i + 0.5).
        var dist = [Float](repeating: spread, count: w * h)
        for s in segs {
            let minX = max(0, Int((min(s.x, s.z) - spread).rounded(.down)))
            let maxX = min(w - 1, Int((max(s.x, s.z) + spread).rounded(.up)))
            let minY = max(0, Int((min(s.y, s.w) - spread).rounded(.down)))
            let maxY = min(h - 1, Int((max(s.y, s.w) + spread).rounded(.up)))
            if minX > maxX || minY > maxY { continue }
            let ax = s.x, ay = s.y, bx = s.z - s.x, by = s.w - s.y
            let l2 = bx * bx + by * by
            for iy in minY...maxY {
                let py = Float(iy) + 0.5 - ay
                for ix in minX...maxX {
                    let px = Float(ix) + 0.5 - ax
                    var t: Float = l2 > 0 ? (px * bx + py * by) / l2 : 0
                    t = min(max(t, 0), 1)
                    let dx = px - bx * t, dy = py - by * t
                    let d = (dx * dx + dy * dy).squareRoot()
                    let k = iy * w + ix
                    if d < dist[k] { dist[k] = d }
                }
            }
        }
        // Sign by nonzero winding along each row.
        var values = [Float16](repeating: Float16(-spread), count: w * h)
        var crossings: [(x: Float, dir: Int)] = []
        for iy in 0..<h {
            let y = Float(iy) + 0.5
            crossings.removeAll(keepingCapacity: true)
            for s in segs where (s.y <= y && s.w > y) || (s.w <= y && s.y > y) {
                let x = s.x + (y - s.y) * (s.z - s.x) / (s.w - s.y)
                crossings.append((x, s.w > s.y ? 1 : -1))
            }
            crossings.sort { $0.x < $1.x }
            var winding = 0, ci = 0
            let row = (h - 1 - iy) * w
            for ix in 0..<w {
                let x = Float(ix) + 0.5
                while ci < crossings.count && crossings[ci].x < x { winding += crossings[ci].dir; ci += 1 }
                let d = dist[iy * w + ix]
                values[row + ix] = Float16(winding != 0 ? d : -d)
            }
        }
        return GlyphBitmap(width: w, height: h, originX: x0, originY: y0, values: values)
    }

    /// Line segments (ax, ay, bx, by) in bitmap space; subpaths are closed implicitly.
    static func flatten(_ path: CGPath, dx: Double, dy: Double) -> [SIMD4<Float>] {
        final class Acc {
            var segs: [SIMD4<Float>] = []
            var cur = CGPoint.zero
            var start = CGPoint.zero
            var open = false
            let dx: Double, dy: Double
            init(dx: Double, dy: Double) { self.dx = dx; self.dy = dy }
            func line(_ a: CGPoint, _ b: CGPoint) {
                if a == b { return }
                segs.append(SIMD4(Float(a.x - dx), Float(a.y - dy), Float(b.x - dx), Float(b.y - dy)))
            }
            func close() { if open { line(cur, start) }; open = false }
            func steps(_ pts: [CGPoint]) -> Int {
                var len = 0.0
                for i in 1..<pts.count { len += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y) }
                return max(2, min(64, Int((len / 1.5).rounded(.up))))
            }
        }
        let acc = Acc(dx: dx, dy: dy)
        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint:
                acc.close()
                acc.cur = e.points[0]; acc.start = e.points[0]; acc.open = true
            case .addLineToPoint:
                acc.line(acc.cur, e.points[0]); acc.cur = e.points[0]
            case .addQuadCurveToPoint:
                let p0 = acc.cur, c = e.points[0], p1 = e.points[1]
                let n = acc.steps([p0, c, p1])
                var prev = p0
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    let q = CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
                    acc.line(prev, q); prev = q
                }
                acc.cur = p1
            case .addCurveToPoint:
                let p0 = acc.cur, c1 = e.points[0], c2 = e.points[1], p1 = e.points[2]
                let n = acc.steps([p0, c1, c2, p1])
                var prev = p0
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
                    let q = CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p1.x, y: a * p0.y + b * c1.y + c * c2.y + d * p1.y)
                    acc.line(prev, q); prev = q
                }
                acc.cur = p1
            case .closeSubpath:
                acc.close()
                acc.cur = acc.start
            @unknown default:
                break
            }
        }
        acc.close()
        return acc.segs
    }
}
