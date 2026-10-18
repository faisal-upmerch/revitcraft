import simd

// Swift mirrors of the structures declared in `CanvasShaders.source`. Field order, types and strides must match the
// MSL declarations exactly (checked by `GPULayoutTests`). All positions are view units unless noted; "px" means
// pixels of the render target.

/// Kind of a `GPURecord` (low 3 bits of `GPURecord.kind`).
nonisolated enum RecordKind: UInt32, Sendable {
    /// A straight stroke segment (capsule) — `p0`/`p1` are the endpoints.
    case segment = 0
    /// A sub-arc of at most 22.5° drawn analytically — `p0` is the arc midpoint, `p1` = (radius, mid angle),
    /// `p2` = (half sweep, direction sign).
    case arc = 1
    /// A fill triangle — `p0`, `p1`, `p2` are the vertices; bits 3…5 of `kind` flag polygon-boundary edges.
    case triangle = 2
    /// A text glyph — `p0.hi` is the pen position (em units of the text's primary font), `p1.hi.x` the glyph's
    /// run-font / primary-font size ratio; bits 8… of `kind` index the scene glyph table.
    case glyph = 3
}

/// One drawable primitive. Every record expands to 6 vertices (two triangles) in the vertex shader; triangles use
/// the first three. Positions are stored as float hi/lo pairs relative to the scene origin so that the camera-relative
/// subtraction on the GPU keeps near-double precision at deep zoom.
nonisolated struct GPURecord: Sendable {
    var p0h: SIMD2<Float> = .zero
    var p0l: SIMD2<Float> = .zero
    var p1h: SIMD2<Float> = .zero
    var p1l: SIMD2<Float> = .zero
    var p2h: SIMD2<Float> = .zero
    var p2l: SIMD2<Float> = .zero
    /// Path distance (view units) at the start of a stroke record (dash phase).
    var dist0: Float = 0
    var kind: UInt32 = 0
    /// Index into the stroke-style, fill or text table (by kind).
    var style: UInt32 = 0
    /// Index into the per-item state table.
    var item: UInt32 = 0
}

nonisolated struct GPUStrokeStyle: Sendable, Hashable {
    /// Pen width on paper (mm), already resolved for the item's line scale.
    var paperWidthMM: Float
    var color: UInt32
    /// Dash pattern index (0 = solid), see `DashTable`.
    var dash: UInt32
    /// Bit 0: halftone.
    var flags: UInt32
}

nonisolated struct GPUFill: Sendable {
    var color: UInt32
    /// Background colour index, or `GPUFill.noBackground`.
    var background: UInt32
    /// 1 − transparency.
    var alpha: Float
    /// Bits 0…4 pattern (`FillPatternIndex`), bit 5 model pattern, bit 6 halftone, bit 7 mask (paint canvas).
    var flags: UInt32
    /// Item line scale (model patterns: device-per-unit = ppm / scale).
    var scale: Float
    /// Paper width (mm) of pen 1 at `scale` (pattern line width).
    var pen1MM: Float
    /// Pattern base spacing (paper mm or model m), from `FillPatterns.spacing`.
    var spacing: Float
    var pad: Float = 0
    /// Bounds of the whole fill relative to the scene origin (min x, min y, max x, max y) — pattern budget estimate.
    var bbox: SIMD4<Float>

    static let noBackground: UInt32 = .max
}

nonisolated struct GPUText: Sendable {
    var anchorH: SIMD2<Float>
    var anchorL: SIMD2<Float>
    /// Text direction (cos, sin of the rotation) in view space.
    var rot: SIMD2<Float>
    /// Cap height on paper (meters).
    var height: Float
    /// Primary font size / cap height.
    var emPerCap: Float
    var color: UInt32
    /// Bit 0: halftone.
    var flags: UInt32
}

nonisolated struct GPUGlyph: Sendable {
    /// Quad corners relative to the glyph origin, in em units of the glyph's font.
    var planeMin: SIMD2<Float>
    var planeMax: SIMD2<Float>
    /// Atlas coordinates of the plane-min (bottom-left) and plane-max (top-right) corners.
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
}

/// Dynamic per-item state (highlight, visibility).
nonisolated struct GPUItem: Sendable {
    var highlight: SIMD4<Float> = .zero
    var flags: UInt32 = 0
    var pad0: UInt32 = 0
    var pad1: UInt32 = 0
    var pad2: UInt32 = 0

    static let hidden: UInt32 = 1 << 0
    static let highlighted: UInt32 = 1 << 1
    static let overlayLayer: UInt32 = 1 << 2
    static let forceHalftone: UInt32 = 1 << 3
    /// Flags owned by the scene (not changed by options).
    static let staticMask: UInt32 = overlayLayer
}

/// Per-pass uniforms.
nonisolated struct GPUFrame: Sendable {
    /// View units → target pixels (a, b, c, d of the linear part; y up).
    var linear: SIMD4<Float> = .zero
    /// Camera (the view point drawn at `centerPx`) relative to the scene origin, as a hi/lo pair.
    var camHi: SIMD2<Float> = .zero
    var camLo: SIMD2<Float> = .zero
    var centerPx: SIMD2<Float> = .zero
    var viewport: SIMD2<Float> = .zero
    /// Camera in absolute view coordinates (fill pattern anchoring at the view origin).
    var camView: SIMD2<Float> = .zero
    var ppmPx: Float = 0
    var viewUnitPx: Float = 0
    var minWidthPx: Float = 0
    var halftoneAmount: Float = 0
    var flags: UInt32 = 0
    var pixelsPerPoint: Float = 1
    var canvas: SIMD4<Float> = .zero
    var clipPx: SIMD4<Float> = .zero

    static let thinLines: UInt32 = 1 << 0
    static let printing: UInt32 = 1 << 1
    static let showOverlays: UInt32 = 1 << 2
    static let patternBudget: UInt32 = 1 << 3
}

/// Stable shader indices for `FillPatternKind`.
nonisolated enum FillPatternIndex: UInt32, Sendable {
    case solid = 0, diagonalUp, diagonalDown, crosshatch, diagonalCrosshatch, horizontal, vertical, concrete, brick,
         insulation, sand, wood, grid, earth
}
