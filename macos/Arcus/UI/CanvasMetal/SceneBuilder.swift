import CoreText
import Foundation
import ArcusGeometry
import ArcusDomain
import ArcusOutput

/// A contiguous run of records in painter's order with conservative bounds, used for per-frame CPU culling.
nonisolated struct SceneChunk: Sendable {
    var start: Int
    var count: Int
    /// View-space bounds of the geometry (absolute view coordinates).
    var bounds: Rect2
    /// Extra reach on paper (meters): half the widest pen and the text extents anchored inside `bounds`.
    var paperMargin: Double
}

/// CPU-side result of converting a display list: everything that is uploaded to the GPU once.
nonisolated struct SceneData: Sendable {
    var origin = Vec2.zero
    var records: [GPURecord] = []
    var strokes: [GPUStrokeStyle] = []
    var fills: [GPUFill] = []
    var texts: [GPUText] = []
    var glyphs: [GPUGlyph] = []
    /// Raw colours; index 0 is a placeholder for the canvas colour.
    var colors: [RGBColor] = [.white]
    var itemElementIDs: [ElementID?] = []
    var itemFlags: [UInt32] = []
    var chunks: [SceneChunk] = []
    var atlasPage: GlyphAtlasPage?
    var triangleCount = 0
    var segmentCount = 0
    var arcCount = 0
    var glyphCount = 0
}

/// Converts a `ViewGraphics` into `SceneData`. Pure CPU work, safe on any thread; the only shared state touched is
/// the (locked) glyph atlas.
nonisolated struct SceneBuilder {
    static let chunkSize = 1024
    /// Arcs are split into sub-arcs of at most this sweep; each is drawn analytically (exact at any zoom).
    static let maxSubArcSweep = Double.pi / 8

    private let g: ViewGraphics
    private let atlas: GlyphAtlas?
    private var data = SceneData()
    private var colorIndex: [RGBColor: UInt32] = [:]
    private var strokeIndex: [GPUStrokeStyle: UInt32] = [:]
    private var shaper = TextShaper()
    private var glyphIndex: [GlyphKey: UInt32] = [:]
    private var glyphKeys: [GlyphKey] = []
    private var chunkBounds = Rect2.empty
    private var chunkMargin = 0.0
    private var chunkStart = 0

    init(_ g: ViewGraphics, atlas: GlyphAtlas?) {
        self.g = g
        self.atlas = atlas
    }

    static func build(_ g: ViewGraphics, atlas: GlyphAtlas?, isCancelled: () -> Bool = { false }) -> SceneData? {
        var b = SceneBuilder(g, atlas: atlas)
        return b.run(isCancelled: isCancelled)
    }

    private mutating func run(isCancelled: () -> Bool) -> SceneData? {
        var extent = Rect2.empty
        for item in g.items where !item.bounds.isEmpty { extent.include(item.bounds) }
        data.origin = extent.isEmpty ? .zero : extent.center
        data.records.reserveCapacity(g.items.count * 8)
        data.itemElementIDs.reserveCapacity(g.items.count)
        data.itemFlags.reserveCapacity(g.items.count)
        for (n, item) in g.items.enumerated() {
            if n & 1023 == 0 && isCancelled() { return nil }
            let itemIndex = UInt32(data.itemElementIDs.count)
            data.itemElementIDs.append(item.elementID)
            data.itemFlags.append(item.layer == .overlay ? GPUItem.overlayLayer : 0)
            let scale = max(item.lineScale ?? g.scale, 1)
            for p in item.primitives {
                switch p {
                case .polyline(let pts, let closed, let st): addPolyline(pts, closed: closed, st, scale: scale, item: itemIndex)
                case .arc(let a, let st): addArc(a, st, scale: scale, item: itemIndex)
                case .fill(let polys, let f): addFill(polys, f, scale: scale, masking: item.layer == .masking, item: itemIndex)
                case .text(let t): addText(t, item: itemIndex)
                }
            }
        }
        closeChunk()
        resolveGlyphs()
        return data
    }

    // MARK: Helpers

    private func split(_ v: Vec2) -> (SIMD2<Float>, SIMD2<Float>) {
        let rx = v.x - data.origin.x, ry = v.y - data.origin.y
        let hx = Float(rx), hy = Float(ry)
        return (SIMD2(hx, hy), SIMD2(Float(rx - Double(hx)), Float(ry - Double(hy))))
    }

    private mutating func color(_ c: RGBColor) -> UInt32 {
        if let i = colorIndex[c] { return i }
        let i = UInt32(data.colors.count)
        data.colors.append(c)
        colorIndex[c] = i
        return i
    }

    private mutating func strokeStyle(_ st: GStroke, scale: Int) -> (index: UInt32, marginPaper: Double) {
        let mm = LineWeights.paperWidth(st.weight, scale: scale)
        let s = GPUStrokeStyle(paperWidthMM: Float(mm), color: color(st.color), dash: CanvasShaders.dashIndex(st.pattern),
                               flags: st.halftone ? 1 : 0)
        let margin = mm / 2000
        if let i = strokeIndex[s] { return (i, margin) }
        let i = UInt32(data.strokes.count)
        data.strokes.append(s)
        strokeIndex[s] = i
        return (i, margin)
    }

    private mutating func emit(_ r: GPURecord, bounds: Rect2, paperMargin: Double) {
        data.records.append(r)
        chunkBounds.include(bounds)
        chunkMargin = max(chunkMargin, paperMargin)
        if data.records.count - chunkStart >= Self.chunkSize { closeChunk() }
    }

    private mutating func closeChunk() {
        let n = data.records.count - chunkStart
        if n > 0 {
            data.chunks.append(SceneChunk(start: chunkStart, count: n, bounds: chunkBounds, paperMargin: chunkMargin))
        }
        chunkStart = data.records.count
        chunkBounds = .empty
        chunkMargin = 0
    }

    // MARK: Strokes

    private mutating func addPolyline(_ pts: [Vec2], closed: Bool, _ st: GStroke, scale: Int, item: UInt32) {
        guard pts.count >= 2 else { return }
        // Zero-length pieces add nothing to a CoreGraphics stroke; a subpath of zero length draws nothing at all.
        var segs: [(Vec2, Vec2)] = []
        segs.reserveCapacity(pts.count)
        let n = closed ? pts.count : pts.count - 1
        for i in 0..<n {
            let a = pts[i], b = pts[(i + 1) % pts.count]
            if a != b && a.x.isFinite && a.y.isFinite && b.x.isFinite && b.y.isFinite { segs.append((a, b)) }
        }
        guard !segs.isEmpty else { return }
        let (style, margin) = strokeStyle(st, scale: scale)
        var dist = 0.0
        let count = segs.count
        for (k, (a, b)) in segs.enumerated() {
            let (ah, al) = split(a), (bh, bl) = split(b)
            var r = GPURecord()
            r.p0h = ah; r.p0l = al; r.p1h = bh; r.p1l = bl
            // Neighbours as small deltas (precise at any distance from the origin): next end − b, previous start − a.
            var flags: UInt32 = 0
            if k > 0 || (closed && count > 1) {
                let pv = segs[k > 0 ? k - 1 : count - 1]
                r.p2l = SIMD2(Float(pv.0.x - a.x), Float(pv.0.y - a.y))
                flags |= 1
            }
            if k < count - 1 || (closed && count > 1) {
                let nx = segs[k < count - 1 ? k + 1 : 0]
                r.p2h = SIMD2(Float(nx.1.x - b.x), Float(nx.1.y - b.y))
                flags |= 2
            }
            r.dist0 = Float(dist)
            r.kind = RecordKind.segment.rawValue | (flags << 3)
            r.style = style
            r.item = item
            var bb = Rect2.empty
            bb.include(a); bb.include(b)
            emit(r, bounds: bb, paperMargin: margin)
            dist += a.distance(to: b)
            data.segmentCount += 1
        }
    }

    private mutating func addArc(_ a: Arc2, _ st: GStroke, scale: Int, item: UInt32) {
        guard a.radius > 0, a.radius.isFinite, a.sweep != 0, a.sweep.isFinite else { return }
        let (style, margin) = strokeStyle(st, scale: scale)
        let sweep = max(-2 * Double.pi, min(2 * Double.pi, a.sweep))
        let n = max(1, Int((abs(sweep) / Self.maxSubArcSweep).rounded(.up)))
        let sub = sweep / Double(n)
        let theta = abs(sub) / 2
        for k in 0..<n {
            let s0 = a.startAngle + Double(k) * sub
            let mid = s0 + sub / 2
            let m = a.center + Vec2(cos(mid), sin(mid)) * a.radius
            let (mh, ml) = split(m)
            var r = GPURecord()
            r.p0h = mh; r.p0l = ml
            r.p1h = SIMD2(Float(a.radius), Float(mid))
            r.p2h = SIMD2(Float(theta), sweep > 0 ? 1 : -1)
            r.dist0 = Float(Double(k) * abs(sub) * a.radius)
            // Caps only at the ends of the whole arc; sub-arc boundaries continue on the same circle.
            r.kind = RecordKind.arc.rawValue | ((k == 0 ? 1 : 0) | (k == n - 1 ? 2 : 0)) << 3
            r.style = style
            r.item = item
            let p0 = a.center + Vec2(cos(s0), sin(s0)) * a.radius
            let p1 = a.center + Vec2(cos(s0 + sub), sin(s0 + sub)) * a.radius
            var bb = Rect2(points: [p0, p1, m])
            bb = bb.expanded(by: a.radius * (1 - cos(theta)))
            emit(r, bounds: bb, paperMargin: margin)
            data.arcCount += 1
        }
    }

    // MARK: Fills

    private mutating func addFill(_ polys: [Polygon2], _ f: GFill, scale: Int, masking: Bool, item: UInt32) {
        let mask = f == GFill.mask || (masking && f.pattern == .solid && f.color == .white)
        let alpha = max(0, min(1, 1 - f.transparency))
        if !mask && !(alpha > 0.001) { return }
        if !mask, f.pattern != .solid, let h = f.hatch, !h.isEmpty, addHatch(polys, h, f, alpha: alpha, scale: scale, item: item) { return } // W4-HATCH
        let tris = FillTessellator.triangulate(polys)
        if tris.isEmpty { return }
        var bb = Rect2.empty
        for p in polys where p.points.count >= 3 { bb.include(p.bounds) }
        let lo = SIMD2<Float>(Float(bb.min.x - data.origin.x), Float(bb.min.y - data.origin.y))
        let hi = SIMD2<Float>(Float(bb.max.x - data.origin.x), Float(bb.max.y - data.origin.y))
        var flags = CanvasShaders.fillIndex(f.pattern)
        if f.isModelPattern { flags |= 32 }
        if f.halftone { flags |= 64 }
        if mask { flags |= 128 }
        let sp = FillPatterns.spacing(f.pattern)
        let fill = GPUFill(color: mask ? 0 : color(f.color),
                           background: mask ? GPUFill.noBackground : (f.background.map { color($0) } ?? GPUFill.noBackground),
                           alpha: Float(alpha), flags: flags, scale: Float(scale),
                           pen1MM: Float(LineWeights.paperWidth(1, scale: scale)),
                           spacing: Float(f.isModelPattern ? sp.model : sp.drafting),
                           bbox: SIMD4(lo.x, lo.y, hi.x, hi.y))
        let fi = UInt32(data.fills.count)
        data.fills.append(fill)
        for t in tris {
            let (ah, al) = split(t.a), (bh, bl) = split(t.b), (ch, cl) = split(t.c)
            var r = GPURecord()
            r.p0h = ah; r.p0l = al; r.p1h = bh; r.p1l = bl; r.p2h = ch; r.p2l = cl
            r.kind = RecordKind.triangle.rawValue | (t.boundary << 3)
            r.style = fi
            r.item = item
            emit(r, bounds: Rect2(points: [t.a, t.b, t.c]), paperMargin: 0)
            data.triangleCount += 1
        }
    }

    /// W4-HATCH: a project fill pattern as real stroke segments (pen 1, clipped to the region by `HatchGenerator`, cached
    /// per region/pattern/scale) over an optional solid background. Hatch strokes carry their spacing (bit 1 of the
    /// style flags, spacing in `dash`) so the shader fades them to a tint when they get denser than a few pixels.
    /// Returns false when the hatch is over budget; the caller then draws the procedural kind.
    private mutating func addHatch(_ polys: [Polygon2], _ h: HatchPattern, _ f: GFill, alpha: Double, scale: Int, item: UInt32) -> Bool {
        guard let lines = HatchCache.shared.lines(polys, h, scale: scale) else { return false }
        if let bg = f.background {
            var solid = GFill(pattern: .solid, color: bg, transparency: f.transparency)
            solid.hatch = nil
            addFill(polys, solid, scale: scale, masking: false, item: item)
        }
        let inkColor = RGBColor(f.color.r, f.color.g, f.color.b, f.color.a * alpha)
        let mm = LineWeights.paperWidth(1, scale: scale)
        let style = GPUStrokeStyle(paperWidthMM: Float(mm), color: color(inkColor), dash: Float(lines.minSpacing).bitPattern,
                                   flags: (f.halftone ? 1 : 0) | 2)
        let si: UInt32
        if let i = strokeIndex[style] { si = i } else {
            si = UInt32(data.strokes.count)
            data.strokes.append(style)
            strokeIndex[style] = si
        }
        let margin = mm / 2000
        func emitSegment(_ a: Vec2, _ b: Vec2) {
            let (ah, al) = split(a), (bh, bl) = split(b)
            var r = GPURecord()
            r.p0h = ah; r.p0l = al; r.p1h = bh; r.p1l = bl
            r.kind = RecordKind.segment.rawValue
            r.style = si
            r.item = item
            var bb = Rect2.empty
            bb.include(a); bb.include(b)
            emit(r, bounds: bb, paperMargin: margin)
            data.segmentCount += 1
        }
        for seg in lines.segments where seg.start != seg.end { emitSegment(seg.start, seg.end) }
        // Dots: a segment as long as the pen is wide (round caps make it a dot).
        let dotLen = max(mm * 0.001 * Double(scale) * 0.5, 1e-6)
        for d in lines.dots { emitSegment(d - Vec2(dotLen / 2, 0), d + Vec2(dotLen / 2, 0)) }
        return true
    }

    // MARK: Text

    private mutating func addText(_ t: GText, item: UInt32) {
        guard let shaped = shaper.shape(t), !shaped.glyphs.isEmpty else { return }
        // Text-space (em) → view units: em × (cap/em) × cap height on paper × view units per paper meter.
        let emToView = Double(shaped.emPerCap) * t.height * Double(max(g.scale, 1))
        let u = Vec2(cos(t.rotation), sin(t.rotation)), v = Vec2(-sin(t.rotation), cos(t.rotation))
        func place(_ x: Double, _ y: Double) -> Vec2 { t.position + u * (x * emToView) + v * (y * emToView) }
        if t.opaque {
            // Mirrors GraphicsRenderer: the block plus a margin (and room for descenders), painted as a mask.
            let capEm = 1 / Double(shaped.emPerCap)
            let m = capEm * GText.backgroundMargin
            let b = shaped.block
            let x0 = Double(b.x) - m, x1 = Double(b.z) + m, y0 = Double(b.y) - m - capEm * 0.25, y1 = Double(b.w) + m
            addFill([Polygon2([place(x0, y0), place(x1, y0), place(x1, y1), place(x0, y1)])], .mask, scale: g.scale, masking: true, item: item)
        }
        defer {
            if t.underline {
                let capEm = 1 / Double(shaped.emPerCap)
                let off = capEm * GText.underlineOffset, th = capEm * GText.underlineThickness / 2
                for l in shaped.lines where l.z > 0 {
                    let x0 = Double(l.x), x1 = Double(l.x + l.z), y = Double(l.y) - off
                    addFill([Polygon2([place(x0, y - th), place(x1, y - th), place(x1, y + th), place(x0, y + th)])],
                            GFill(pattern: .solid, color: t.color, halftone: t.halftone), scale: g.scale, masking: false, item: item)
                }
            }
        }
        let (ah, al) = split(t.position)
        let ti = UInt32(data.texts.count)
        data.texts.append(GPUText(anchorH: ah, anchorL: al, rot: SIMD2(Float(cos(t.rotation)), Float(sin(t.rotation))),
                                  height: Float(t.height), emPerCap: shaped.emPerCap, color: color(t.color),
                                  flags: t.halftone ? 1 : 0))
        let reachPaper = Double(shaped.reachEm * shaped.emPerCap) * t.height
        let bb = Rect2(min: t.position, max: t.position)
        for gl in shaped.glyphs {
            let gi: UInt32
            if let i = glyphIndex[gl.key] { gi = i } else {
                gi = UInt32(glyphKeys.count)
                glyphIndex[gl.key] = gi
                glyphKeys.append(gl.key)
            }
            var r = GPURecord()
            r.p0h = gl.pen
            r.p1h = SIMD2(gl.planeScale, 0)
            r.kind = RecordKind.glyph.rawValue | (gi << 8)
            r.style = ti
            r.item = item
            emit(r, bounds: bb, paperMargin: reachPaper)
            data.glyphCount += 1
        }
    }

    private mutating func resolveGlyphs() {
        guard !glyphKeys.isEmpty else { return }
        var fonts: [GlyphKey: CTFont] = [:]
        for k in glyphKeys { if let f = shaper.runFonts[k] { fonts[k] = f } }
        let resolved = atlas?.resolve(fonts)
        data.atlasPage = resolved?.page
        data.glyphs = glyphKeys.map { k in
            guard let e = resolved?.entries[k] else { return GPUGlyph(planeMin: .zero, planeMax: .zero, uvMin: .zero, uvMax: .zero) }
            return GPUGlyph(planeMin: e.planeMin, planeMax: e.planeMax, uvMin: e.uvMin, uvMax: e.uvMax)
        }
    }
}
