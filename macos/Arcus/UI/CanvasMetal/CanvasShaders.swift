import ArcusDomain

/// Metal Shading Language source for the canvas renderer, compiled at runtime (SwiftPM has no .metallib step).
///
/// One pipeline draws everything: every `GPURecord` expands to a 6-vertex quad (or a triangle) and the fragment shader
/// branches on the record kind. Keeping all primitives in one ordered stream is what preserves GraphicsRenderer's
/// painter's order exactly (the GPU blends primitives of a draw call in submission order) while needing only a handful
/// of draw calls per frame.
///
/// Semantics mirrored from `GraphicsRenderer` / `FillPatterns` (see README "Parity"):
/// - pen width px = thinLines ? 1 : max(paperMM/1000 · ppm, minimumDevicePixel); round caps and joins (capsules).
/// - dash patterns in paper mm, restarting per polyline/arc; drawn solid when the period is under 1.5 device pixels.
/// - fills: background then solid/pattern, both at (1 − transparency); masks paint the canvas colour.
/// - patterns: the exact generators of `FillPatterns` (same lattice hash) evaluated as distance fields; tint fallback
///   when lines would be closer than 2 device pixels or (optionally) when CoreGraphics would exceed its mark budget.
nonisolated enum CanvasShaders {
    /// Font size (atlas pixels per em) of the SDF glyph atlas.
    static let atlasEm: Float = 48
    /// Distance range (atlas pixels) stored around each glyph outline.
    static let atlasSpread: Float = 6

    static func dashIndex(_ k: LinePatternKind) -> UInt32 {
        switch k {
        case .solid: 0
        case .dash: 1
        case .hidden: 2
        case .center: 3
        case .dot: 4
        case .dashDot: 5
        case .overhead: 6
        case .longDash: 7
        case .doubleDash: 8
        case .dashDotDot: 9
        case .demolished: 10
        }
    }

    /// Rows of the `kDash` table (one per `LinePatternKind`, indexed by `dashIndex`).
    static let dashRows = 11

    static func fillIndex(_ k: FillPatternKind) -> UInt32 {
        let i: FillPatternIndex = switch k {
        case .solid: .solid
        case .diagonalUp: .diagonalUp
        case .diagonalDown: .diagonalDown
        case .crosshatch: .crosshatch
        case .diagonalCrosshatch: .diagonalCrosshatch
        case .horizontal: .horizontal
        case .vertical: .vertical
        case .concrete: .concrete
        case .brick: .brick
        case .insulation: .insulation
        case .sand: .sand
        case .wood: .wood
        case .grid: .grid
        case .earth: .earth
        }
        return i.rawValue
    }

    /// `kDash` initialiser generated from `LinePatternKind.dashPattern` (single source of truth for dash lengths): eight
    /// entries per pattern (on, off × up to four dashes), zero-padded; a zero "on" length is no dash.
    static var dashTable: String {
        var rows = [String](repeating: "{" + Array(repeating: "0.0", count: 8).joined(separator: ", ") + "}", count: dashRows)
        for k in LinePatternKind.allCases {
            var p = k.dashPattern
            if p.isEmpty { continue }
            precondition(p.count <= 8 && p.count % 2 == 0, "dash patterns have at most four on/off pairs")
            p += Array(repeating: 0, count: 8 - p.count)
            rows[Int(dashIndex(k))] = "{" + p.map { String(format: "%.6f", $0) }.joined(separator: ", ") + "}"
        }
        return rows.joined(separator: ",\n    ")
    }

    static var source: String {
        body
            .replacingOccurrences(of: "%ATLAS_EM%", with: String(format: "%.1f", atlasEm))
            .replacingOccurrences(of: "%DASHROWS%", with: String(dashRows))
            .replacingOccurrences(of: "%DASH%", with: dashTable)
    }

    private static let body = #"""
#include <metal_stdlib>
using namespace metal;

constant float kAtlasEm = %ATLAS_EM%;
constant float kPi = 3.14159265358979;
constant float kDash[%DASHROWS%][8] = {
    %DASH%
};

constant uint K_SEG = 0u, K_ARC = 1u, K_TRI = 2u, K_GLYPH = 3u;
constant uint I_HIDDEN = 1u, I_HL = 2u, I_OVERLAY = 4u, I_FORCE_HT = 8u;
constant uint F_THIN = 1u, F_PRINT = 2u, F_SHOW_OVERLAYS = 4u, F_BUDGET = 8u;

struct Frame {
    float4 linear;
    float2 camHi;
    float2 camLo;
    float2 centerPx;
    float2 viewport;
    float2 camView;
    float ppmPx;
    float viewUnitPx;
    float minWidthPx;
    float halftoneAmount;
    uint flags;
    float pixelsPerPoint;
    float4 canvas;
    float4 clipPx;
};
struct Rec { float2 p0h; float2 p0l; float2 p1h; float2 p1l; float2 p2h; float2 p2l; float dist0; uint kind; uint style; uint item; };
struct StrokeStyle { float widthMM; uint color; uint dash; uint flags; };
struct FillInst { uint color; uint background; float alpha; uint flags; float scale; float pen1MM; float spacing; float pad; float4 bbox; };
struct TextInst { float2 anchorH; float2 anchorL; float2 rot; float height; float emPerCap; uint color; uint flags; };
struct Glyph { float2 planeMin; float2 planeMax; float2 uvMin; float2 uvMax; };
struct Item { float4 highlight; uint flags; uint pad0; uint pad1; uint pad2; };

struct VOut {
    float4 pos [[position]];
    float4 color [[flat]];
    float4 color2 [[flat]];
    float4 f0 [[flat]];
    float4 f1 [[flat]];
    float4 f2 [[flat]];
    uint4 u0 [[flat]];
    float4 v0;
    float2 v1;
};

// MARK: Transform helpers

static inline float2 camRel(float2 h, float2 l, constant Frame& F) { return (h - F.camHi) + (l - F.camLo); }
static inline float2 linMap(float2 v, constant Frame& F) {
    return float2(F.linear.x * v.x + F.linear.z * v.y, F.linear.y * v.x + F.linear.w * v.y);
}
static inline float2 invLin(float2 v, constant Frame& F) {
    float det = F.linear.x * F.linear.w - F.linear.y * F.linear.z;
    if (abs(det) < 1e-30) return float2(0.0);
    return float2(F.linear.w * v.x - F.linear.z * v.y, -F.linear.y * v.x + F.linear.x * v.y) / det;
}
static inline float2 toPx(float2 r, constant Frame& F) { return linMap(r, F) + F.centerPx; }
static inline float4 clipPos(float2 px, constant Frame& F) { return float4(px / F.viewport * 2.0 - 1.0, 0.0, 1.0); }

static inline float strokeWidthPx(float mm, constant Frame& F) {
    if ((F.flags & F_THIN) != 0u) return 1.0;
    return max(mm * 0.001 * F.ppmPx, F.minWidthPx);
}
static inline float4 ink(float4 c, bool halftone, constant Frame& F) {
    if (halftone) c.rgb = mix(c.rgb, F.canvas.rgb, clamp(F.halftoneAmount, 0.0, 1.0));
    return c;
}
static inline float4 strokeInk(uint colorIndex, bool halftone, Item it, device const float4* colors, constant Frame& F) {
    float4 c = colors[colorIndex];
    if ((it.flags & I_HL) != 0u) return float4(it.highlight.rgb, it.highlight.a * c.a);
    return ink(c, halftone || (it.flags & I_FORCE_HT) != 0u, F);
}

// MARK: Coverage helpers

/// Box-filtered coverage of a band of width w at distance d from its centre line (exact for thin lines).
static inline float lineCov(float d, float w) {
    float h = 0.5 * w;
    return clamp(min(d + 0.5, h) - max(d - 0.5, -h), 0.0, 1.0);
}
/// Coverage of a filled dot of radius r px at distance d px, normalised so the integrated ink equals the dot area.
static inline float dotCov(float d, float r) {
    float re = max(r, 0.5);
    float k = min(1.0, r * r / (re * re + 1.0 / 12.0));
    return clamp(re + 0.5 - d, 0.0, 1.0) * k;
}
/// CDF of the pixel footprint (unit square) projected on a unit direction whose absolute components are (a, b),
/// a ≥ b: a trapezoid distribution. footCDF(d) is the exact coverage of a half-plane whose edge is at signed distance d
/// (positive inside) from the pixel centre — phase independent at any edge angle, like CoreGraphics' area coverage.
static inline float footCDF(float x, float a, float b) {
    float h = 0.5 * (a + b), p = 0.5 * (a - b);
    float ax = abs(x);
    float c;
    if (ax >= h) c = 0.5;
    else if (ax <= p) c = ax / a;
    else { float r = h - ax; c = 0.5 - r * r / (2.0 * a * b); }
    return x >= 0.0 ? 0.5 + c : 0.5 - c;
}
static inline float2 footprint(float2 n) {
    float l = length(n);
    if (!(l > 1e-12)) return float2(1.0, 0.0);
    n = abs(n) / l;
    return float2(max(n.x, n.y), min(n.x, n.y));
}
/// Coverage of a band of half-width hw whose centre line is at distance d ≥ 0 (normal footprint fp).
static inline float bandCov(float d, float hw, float2 fp) {
    return clamp(footCDF(hw - d, fp.x, fp.y) - footCDF(-hw - d, fp.x, fp.y), 0.0, 1.0);
}
/// Ratio between the ink of a true round half-disc cap of radius hw and the ink the band model puts around a line end
/// (the model over-inks sub-pixel caps by up to 2×; CoreGraphics' exact coverage does not).
static float capInkScale(float hw) {
    float a = abs(hw - 0.5), c = hw + 0.5;
    float ramp = kPi * (c * c * c / 6.0 - c * a * a / 2.0 + a * a * a / 3.0);
    float core = hw <= 0.5 ? kPi * hw * a * a : kPi * a * a * 0.5;
    float model = core + ramp;
    return model > 0.0 ? min(1.0, kPi * hw * hw * 0.5 / model) : 1.0;
}
static inline float gapSigned(float a, float b, float lo, float hi, float sp) {
    a = max(a, lo); b = min(b, hi);
    if (a > b) return 1e30;
    return sp < a ? sp - a : (sp > b ? sp - b : 0.0);
}
static inline float pickGap(float best, float g) { return abs(g) < abs(best) ? g : best; }
/// Signed distance along the path from parameter s (px from the record start) to the nearest "on" piece of the stroke
/// within [lo, hi] (record-relative; ±1e30 where the path continues on the same curve). dist0 = path distance at the
/// record start (px). Solid strokes and patterns whose period is under 1.5 device pixels are one piece.
/// Period of a dash pattern and the start and length of its (up to four) "on" pieces, in px.
struct DashInfo { float4 start; float4 len; float P; };
static DashInfo dashInfo(uint dash, float mmToPx) {
    DashInfo d;
    float acc = 0.0;
    for (int i = 0; i < 4; i++) {
        float on = kDash[dash][2 * i] * mmToPx, off = kDash[dash][2 * i + 1] * mmToPx;
        d.start[i] = acc;
        d.len[i] = on;
        acc += on + off;
    }
    d.P = acc;
    return d;
}
static float strokeGap(float s, float lo, float hi, float dist0, uint dash, float mmToPx) {
    float solid = s < lo ? s - lo : (s > hi ? s - hi : 0.0);
    if (dash == 0u) return solid;
    DashInfo d = dashInfo(dash, mmToPx);
    float P = d.P;
    if (!(P >= 1.5)) return solid;
    float sp = dist0 + s;
    float k = floor((dist0 + clamp(s, lo, hi)) / P);
    float best = 1e30;
    for (int dk = -1; dk <= 1; dk++) {
        float base = (k + float(dk)) * P;
        for (int i = 0; i < 4; i++) {
            if (!(d.len[i] > 0.0)) continue;
            float a = base + d.start[i];
            best = pickGap(best, gapSigned(a, a + d.len[i], dist0 + lo, dist0 + hi, sp));
        }
    }
    return best;
}

/// Equal-area length of a round cap; CoreGraphics strokes pens of at most one device pixel as butt-ended hairlines.
static inline float capLength(float hw) { return hw > 0.5005 ? 0.785398 * hw : 0.0; }

/// Thin-pen model along the path: the share of the pixel footprint (projected on the tangent) that falls on "on"
/// pieces, each extended by the equal-area round-cap length e at genuine ends (dash ends, path ends). At interior
/// joints (cont*) pieces are not clipped — the next record continues them.
static float alongCoverage(float s, float L, bool contLo, bool contHi, float dist0, uint dash, float mmToPx, float e, float2 fp) {
    DashInfo d = dashInfo(dash, mmToPx);
    float P = d.P;
    if (dash == 0u || !(P >= 1.5)) {
        float lo = contLo ? -1e30 : -e, hi = contHi ? 1e30 : L + e;
        return footCDF(hi - s, fp.x, fp.y) - footCDF(lo - s, fp.x, fp.y);
    }
    float k = floor((dist0 + clamp(s, 0.0, L)) / P);
    float sum = 0.0;
    for (int dk = -1; dk <= 1; dk++) {
        float base = (k + float(dk)) * P - dist0;
        for (int piece = 0; piece < 4; piece++) {
            float a = base + d.start[piece];
            float b = a + d.len[piece];
            if (b <= a) continue;
            if ((!contLo && b < 0.0) || (!contHi && a > L)) continue;
            float lo = (contLo ? a : max(a, 0.0)) - e;
            float hi = (contHi ? b : min(b, L)) + e;
            sum += footCDF(hi - s, fp.x, fp.y) - footCDF(lo - s, fp.x, fp.y);
        }
    }
    return clamp(sum, 0.0, 1.0);
}

// MARK: Fill patterns (pattern space: paper mm or model m, anchored at the view origin) — mirrors FillPatterns.swift

static inline ulong phash(int i, int j, ulong salt) {
    ulong x = ulong(long(i)) * 0x9E3779B97F4A7C15ul;
    x ^= ulong(long(j)) * 0xC2B2AE3D27D4EB4Ful;
    x ^= salt * 0x165667B19E3779F9ul;
    x ^= x >> 33; x *= 0xFF51AFD7ED558CCDul;
    x ^= x >> 33; x *= 0xC4CEB9FE1A85EC53ul;
    x ^= x >> 33;
    return x;
}
static inline float punit(ulong h) { return float(uint(h >> 40)) * (1.0 / 16777216.0); }

static inline float segDist(float2 p, float2 a, float2 b) {
    float2 ab = b - a, ap = p - a;
    float l2 = dot(ab, ab);
    float t = l2 > 0.0 ? clamp(dot(ap, ab) / l2, 0.0, 1.0) : 0.0;
    return length(ap - ab * t);
}
static inline float linesDist(float2 p, float2 n, float s) {
    float o = dot(p, n);
    return abs(o - s * floor(o / s + 0.5));
}
static float stippleCov(float2 p, float s, float radius, ulong salt, float dpu) {
    int ci = int(floor(p.x / s)), cj = int(floor(p.y / s));
    float best = 0.0;
    for (int dj = -1; dj <= 1; dj++) {
        for (int di = -1; di <= 1; di++) {
            int i = ci + di, j = cj + dj;
            float x = (float(i) + punit(phash(i, j, salt))) * s;
            float y = (float(j) + punit(phash(i, j, salt + 1ul))) * s;
            float rad = s * radius * (0.6 + 0.8 * punit(phash(i, j, salt + 2ul)));
            best = max(best, dotCov(length(p - float2(x, y)) * dpu, rad * dpu));
        }
    }
    return best;
}
static float concreteCov(float2 p, float s, float dpu, float lw) {
    float dots = stippleCov(p, s, 0.07, 3ul, dpu);
    float cell = s * 3.0;
    int ci = int(floor(p.x / cell)), cj = int(floor(p.y / cell));
    float d = 1e30;
    for (int dj = -1; dj <= 1; dj++) {
        for (int di = -1; di <= 1; di++) {
            int i = ci + di, j = cj + dj;
            if (punit(phash(i, j, 7ul)) >= 0.55) continue;
            float cx = (float(i) + 0.2 + 0.6 * punit(phash(i, j, 8ul))) * cell;
            float cy = (float(j) + 0.2 + 0.6 * punit(phash(i, j, 9ul))) * cell;
            float rot = punit(phash(i, j, 10ul)) * 2.0 * kPi;
            float rad = s * (0.35 + 0.3 * punit(phash(i, j, 12ul)));
            float2 c = float2(cx, cy);
            float2 a = c + rad * float2(cos(rot), sin(rot));
            float2 b = c + rad * float2(cos(rot + 2.0 * kPi / 3.0), sin(rot + 2.0 * kPi / 3.0));
            float2 e = c + rad * float2(cos(rot + 4.0 * kPi / 3.0), sin(rot + 4.0 * kPi / 3.0));
            d = min(d, min(segDist(p, a, b), min(segDist(p, b, e), segDist(p, e, a))));
        }
    }
    float strokes = lineCov(d * dpu, lw);
    return 1.0 - (1.0 - strokes) * (1.0 - dots);
}
static float brickCov(float2 p, float h, float dpu, float lw) {
    float l = h * 3.0;
    float d = abs(p.y - h * floor(p.y / h + 0.5));
    int jc = int(floor(p.y / h));
    for (int dj = -1; dj <= 1; dj++) {
        int j = jc + dj;
        float y0 = float(j) * h;
        float shift = (j & 1) == 0 ? 0.0 : l * 0.5;
        float xi = floor((p.x - shift) / l + 0.5) * l + shift;
        float dy = max(max(y0 - p.y, p.y - (y0 + h)), 0.0);
        d = min(d, length(float2(p.x - xi, dy)));
    }
    return lineCov(d * dpu, lw);
}
static float insulationCov(float2 p, float band, float dpu, float lw) {
    float w = band / 3.0, rad = w * 0.5;
    float d = 1e30;
    float jc = floor(p.y / band);
    float mc = floor(p.x / w);
    for (int dj = -1; dj <= 1; dj++) {
        float y0 = (jc + float(dj)) * band;
        float ylo = y0 + rad, yhi = y0 + band - rad;
        for (int dm = -1; dm <= 1; dm++) {
            float m = mc + float(dm);
            float x = m * w;
            d = min(d, segDist(p, float2(x, ylo), float2(x, yhi)));
            bool top = (int(m) & 1) == 0;
            float2 q = p - float2(x + rad, top ? yhi : ylo);
            if (top ? q.y >= 0.0 : q.y <= 0.0) d = min(d, abs(length(q) - rad));
        }
    }
    return lineCov(d * dpu, lw);
}
static float woodCov(float2 p, float s, float dpu, float lw) {
    float dx = s * 10.0 / 8.0;
    int jc = int(floor(p.y / s + 0.5));
    int ic = int(floor(p.x / dx));
    float d = 1e30;
    for (int dj = -2; dj <= 2; dj++) {
        int j = jc + dj;
        float phase = punit(phash(j, 0, 21ul)) * 2.0 * kPi;
        float amp = s * 0.22 * (0.6 + 0.8 * punit(phash(j, 1, 22ul)));
        float y0 = float(j) * s;
        for (int di = -1; di <= 1; di++) {
            int i = ic + di;
            float2 a = float2(float(i) * dx, y0 + amp * sin(0.25 * kPi * float(i) + phase));
            float2 b = float2(float(i + 1) * dx, y0 + amp * sin(0.25 * kPi * float(i + 1) + phase));
            d = min(d, segDist(p, a, b));
        }
    }
    return lineCov(d * dpu, lw);
}
static float earthCov(float2 p, float g, float dpu, float lw) {
    float len = g * 0.45, gap = g * 0.12;
    float2 dd = float2(0.70710678, 0.70710678), n = float2(-0.70710678, 0.70710678);
    int jc = int(floor(p.y / g));
    float d = 1e30, best = 0.0;
    for (int dj = -1; dj <= 1; dj++) {
        int j = jc + dj;
        float shift = (j & 1) == 0 ? 0.0 : g * 0.5;
        float ic = floor((p.x - shift) / g);
        float cy = float(j) * g + g * 0.5;
        for (int di = -1; di <= 1; di++) {
            float cx = (ic + float(di)) * g + shift + g * 0.5;
            for (int k = -1; k <= 1; k++) {
                float2 o = float2(cx, cy) + n * gap * float(k);
                if (lw > 1.001) {
                    d = min(d, segDist(p, o - dd * len * 0.5, o + dd * len * 0.5));
                } else {
                    // Hairline strokes have butt ends (separable coverage across × along the stroke, in px).
                    float2 q = (p - o) * dpu;
                    float s = dot(q, dd), t = dot(q, n), hl = 0.5 * len * dpu;
                    best = max(best, lineCov(abs(t), lw) * clamp(min(s + 0.5, hl) - max(s - 0.5, -hl), 0.0, 1.0));
                }
            }
        }
    }
    return max(best, lineCov(d * dpu, lw));
}

static float patternCoverage(uint k, float2 p, float s, float dpu, float lw) {
    const float2 nH = float2(0.0, 1.0);                      // angle 0
    const float2 nV = float2(-1.0, 0.0);                     // angle π/2
    const float2 nU = float2(-0.70710678, 0.70710678);       // angle π/4
    const float2 nD = float2(-0.70710678, -0.70710678);      // angle 3π/4
    switch (k) {
        case 1u: return lineCov(linesDist(p, nU, s) * dpu, lw);
        case 2u: return lineCov(linesDist(p, nD, s) * dpu, lw);
        case 3u: case 12u: return lineCov(min(linesDist(p, nH, s), linesDist(p, nV, s)) * dpu, lw);
        case 4u: return lineCov(min(linesDist(p, nU, s), linesDist(p, nD, s)) * dpu, lw);
        case 5u: return lineCov(linesDist(p, nH, s) * dpu, lw);
        case 6u: return lineCov(linesDist(p, nV, s) * dpu, lw);
        case 7u: return concreteCov(p, s, dpu, lw);
        case 8u: return brickCov(p, s, dpu, lw);
        case 9u: return insulationCov(p, s, dpu, lw);
        case 10u: return stippleCov(p, s, 0.08, 11ul, dpu);
        case 11u: return woodCov(p, s, dpu, lw);
        case 13u: return earthCov(p, s, dpu, lw);
        default: return 1.0;
    }
}

/// CoreGraphics' pattern mark estimate for the visible part of the fill (FillPatterns.draw).
static float patternEstimate(FillInst fi, uint k, float dpu, constant Frame& F) {
    float2 c0 = toPx((fi.bbox.xy - F.camHi) - F.camLo, F);
    float2 c1 = toPx((fi.bbox.zy - F.camHi) - F.camLo, F);
    float2 c2 = toPx((fi.bbox.zw - F.camHi) - F.camLo, F);
    float2 c3 = toPx((fi.bbox.xw - F.camHi) - F.camLo, F);
    float2 lo = max(min(min(c0, c1), min(c2, c3)), F.clipPx.xy);
    float2 hi = min(max(max(c0, c1), max(c2, c3)), F.clipPx.zw);
    if (hi.x <= lo.x || hi.y <= lo.y) return 0.0;
    float W = hi.x - lo.x, H = hi.y - lo.y;
    float vu = max(F.viewUnitPx, 1e-30);
    float4 r = abs(F.linear) / vu;
    float w = (r.x * W + r.y * H) / dpu, h = (r.z * W + r.w * H) / dpu;
    float s = fi.spacing;
    switch (k) {
        case 1u: case 2u: case 5u: case 6u: return (w + h) / s;
        case 3u: case 4u: case 12u: return 2.0 * (w + h) / s;
        case 7u: return w * h / (s * s) * 1.2;
        case 10u: return w * h / (s * s);
        case 8u: return w * h / (s * s * 3.0) + h / s;
        case 9u: return w * h / (s * s / 3.0) * 2.0;
        case 11u: return (h / s) * (w / (s * 10.0 / 8.0));
        case 13u: return w * h / (s * s) * 3.0;
        default: return 1.0;
    }
}

static inline float2 inwardNormal(float2 e, float orient) {
    float l = length(e);
    return l > 1e-12 ? float2(-e.y, e.x) * (orient / l) : float2(0.0);
}
/// Displacement moving a vertex so that boundary edges (o = 1) shift one pixel outward while interior edges stay put.
static float2 offsetVertex(float2 n1, float o1, float2 n2, float o2) {
    if (o1 == 0.0 && o2 == 0.0) return float2(0.0);
    float det = n1.x * n2.y - n1.y * n2.x;
    float2 d;
    if (abs(det) < 1e-3) {
        float2 m = n1 * o1 + n2 * o2;
        float l = length(m);
        d = l > 1e-6 ? -m / l : float2(0.0);
    } else {
        d = float2(-o1 * n2.y + o2 * n1.y, -n1.x * o2 + n2.x * o1) / det;
    }
    float l = length(d);
    if (l > 4.0) d *= 4.0 / l;
    return d;
}

// MARK: Vertex

vertex VOut canvas_vertex(uint vid [[vertex_id]],
                          constant Frame& F [[buffer(0)]],
                          device const Rec* recs [[buffer(1)]],
                          device const StrokeStyle* strokes [[buffer(2)]],
                          device const FillInst* fills [[buffer(3)]],
                          device const TextInst* texts [[buffer(4)]],
                          device const Glyph* glyphs [[buffer(5)]],
                          device const float4* colors [[buffer(6)]],
                          device const Item* items [[buffer(7)]]) {
    VOut o;
    o.pos = float4(2.0, 2.0, 0.0, 1.0);
    o.color = float4(0.0); o.color2 = float4(0.0); o.f0 = float4(0.0); o.f1 = float4(0.0);
    o.u0 = uint4(0u); o.v0 = float4(0.0); o.v1 = float2(0.0); o.f2 = float4(0.0);
    uint ri = vid / 6u, corner = vid - ri * 6u;
    Rec r = recs[ri];
    Item it = items[r.item];
    if ((it.flags & I_HIDDEN) != 0u || ((it.flags & I_OVERLAY) != 0u && (F.flags & F_SHOW_OVERLAYS) == 0u)) return o;
    uint kind = r.kind & 7u;
    uint q = corner < 3u ? corner : (corner == 3u ? 2u : (corner == 4u ? 1u : 3u));
    float2 cq = float2(float(q & 1u), float(q >> 1u));
    o.u0.x = kind;

    if (kind == K_SEG || kind == K_ARC) {
        StrokeStyle st = strokes[r.style];
        float w = strokeWidthPx(st.widthMM, F);
        float h = 0.5 * w + 1.0;
        o.color = strokeInk(st.color, (st.flags & 1u) != 0u, it, colors, F);
        o.u0.y = st.dash;
        if ((st.flags & 2u) != 0u) {
            // W4-HATCH: hatch line; `dash` holds the pattern spacing (view units). Dense hatches fade to a tint.
            float spPx = as_type<float>(st.dash) * F.viewUnitPx;
            o.u0.y = 0u;
            o.color.a *= clamp(spPx / 3.0, 0.12, 1.0);
        }
        float mmToPx = 0.001 * F.ppmPx;
        if (kind == K_SEG) {
            float2 a = toPx(camRel(r.p0h, r.p0l, F), F);
            float2 d = linMap((r.p1h - r.p0h) + (r.p1l - r.p0l), F);
            float L = length(d);
            float2 dir = L > 1e-9 ? d / L : float2(1.0, 0.0);
            float2 nrm = float2(-dir.y, dir.x);
            float s = mix(-h, L + h, cq.x), t = mix(-h, h, cq.y);
            o.pos = clipPos(a + dir * s + nrm * t, F);
            o.v0 = float4(s, t, 0.0, 0.0);
            o.f0 = float4(L, w, r.dist0 * F.viewUnitPx, mmToPx);
            // Neighbouring segments of the same polyline (local frame) decide who owns joint pixels.
            float2 nx = linMap(r.p2h, F), pv = linMap(r.p2l, F);
            o.f1 = float4(dot(nx, dir), dot(nx, nrm), dot(pv, dir), dot(pv, nrm));
            o.f2 = float4(dir, capInkScale(0.5 * w), 0.0);
            o.u0.z = (r.kind >> 3) & 3u;
        } else {
            float2 m0 = toPx(camRel(r.p0h, r.p0l, F), F);
            float R = r.p1h.x * F.viewUnitPx;
            float ma = r.p1h.y;
            float th = r.p2h.x;
            float det = F.linear.x * F.linear.w - F.linear.y * F.linear.z;
            float travel = r.p2h.y * (det < 0.0 ? -1.0 : 1.0);
            float2 m = normalize(linMap(float2(cos(ma), sin(ma)), F));
            float2 tdir = float2(-m.y, m.x) * travel;
            float sh = sin(0.5 * th);
            float xlo = -2.0 * R * sh * sh - h;
            float yext = R * sin(th) + h;
            float xp = mix(xlo, h, cq.x), yp = mix(-yext, yext, cq.y);
            o.pos = clipPos(m0 + m * xp + tdir * yp, F);
            o.v0 = float4(xp, yp, 0.0, 0.0);
            o.f0 = float4(R, th, r.dist0 * F.viewUnitPx, mmToPx);
            o.f1 = float4(w, 0.0, 0.0, 0.0);
            o.f2 = float4(m, travel, capInkScale(0.5 * w));
            o.u0.z = (r.kind >> 3) & 3u;
        }
        return o;
    }

    if (kind == K_TRI) {
        if (corner >= 3u) return o;
        FillInst fi = fills[r.style];
        float2 A = toPx(camRel(r.p0h, r.p0l, F), F);
        float2 B = toPx(camRel(r.p1h, r.p1l, F), F);
        float2 C = toPx(camRel(r.p2h, r.p2l, F), F);
        float2 AB = B - A, BC = C - B, CA = A - C;
        float area = AB.x * (-CA.y) - AB.y * (-CA.x);
        float orient = area >= 0.0 ? 1.0 : -1.0;
        float2 nAB = inwardNormal(AB, orient), nBC = inwardNormal(BC, orient), nCA = inwardNormal(CA, orient);
        uint ef = (r.kind >> 3) & 7u;
        float oAB = (ef & 1u) != 0u ? 1.0 : 0.0, oBC = (ef & 2u) != 0u ? 1.0 : 0.0, oCA = (ef & 4u) != 0u ? 1.0 : 0.0;
        float2 P;
        float2 delta;
        if (corner == 0u) { P = A; delta = offsetVertex(nCA, oCA, nAB, oAB); }
        else if (corner == 1u) { P = B; delta = offsetVertex(nAB, oAB, nBC, oBC); }
        else { P = C; delta = offsetVertex(nBC, oBC, nCA, oCA); }
        float2 V = P + delta;
        o.pos = clipPos(V, F);
        const float far = 1e4;
        o.v0 = float4(oAB > 0.0 ? dot(V - A, nAB) : far, oBC > 0.0 ? dot(V - B, nBC) : far,
                      oCA > 0.0 ? dot(V - C, nCA) : far, 0.0);
        o.v1 = invLin(V - F.centerPx, F);
        float2 fAB = footprint(nAB), fBC = footprint(nBC), fCA = footprint(nCA);
        o.f1 = float4(0.0, fAB, fBC.x);
        o.f2 = float4(fBC.y, fCA, 0.0);
        if ((fi.flags & 128u) != 0u) {           // mask: paint the canvas colour
            o.u0.z = 3u;
            o.color = F.canvas;
            return o;
        }
        float4 c = ink(colors[fi.color], (fi.flags & 64u) != 0u || (it.flags & I_FORCE_HT) != 0u, F);
        if ((it.flags & I_HL) != 0u) c.rgb = mix(c.rgb, it.highlight.rgb, 0.65);
        o.color = c;
        o.color2 = fi.background != 0xFFFFFFFFu ? colors[fi.background] : float4(0.0);
        uint pattern = fi.flags & 31u;
        bool model = (fi.flags & 32u) != 0u;
        float dpu = model ? F.ppmPx / max(fi.scale, 1.0) : F.ppmPx * 0.001;
        float lw = strokeWidthPx(fi.pen1MM, F);
        uint mode = 0u;
        if (pattern != 0u) {
            mode = 1u;
            if (!(fi.spacing * dpu >= 2.0)) mode = 2u;
            else if ((F.flags & F_BUDGET) != 0u && patternEstimate(fi, pattern, dpu, F) > 40000.0) mode = 2u;
        }
        o.u0.y = pattern;
        o.u0.z = mode;
        o.f0 = float4(fi.alpha, dpu, lw, F.viewUnitPx / max(dpu, 1e-30));
        o.f1.x = fi.spacing;
        return o;
    }

    // Glyph
    TextInst ti = texts[r.style];
    float capPx = ti.height * F.ppmPx;
    if ((F.flags & F_PRINT) == 0u && capPx < 0.75) return o;
    Glyph g = glyphs[r.kind >> 8];
    float fontPx = capPx * ti.emPerCap;
    float2 anchor = toPx(camRel(ti.anchorH, ti.anchorL, F), F);
    float2 u = normalize(linMap(ti.rot, F));
    float2 v = normalize(linMap(float2(-ti.rot.y, ti.rot.x), F));
    float ps = r.p1h.x;
    float2 e = r.p0h + mix(g.planeMin, g.planeMax, cq) * ps;
    o.pos = clipPos(anchor + (u * e.x + v * e.y) * fontPx, F);
    o.v0 = float4(mix(g.uvMin, g.uvMax, cq), 0.0, 0.0);
    o.f0 = float4(fontPx * ps / kAtlasEm, 0.0, 0.0, 0.0);
    o.color = strokeInk(ti.color, (ti.flags & 1u) != 0u, it, colors, F);
    return o;
}

// MARK: Fragment

fragment float4 canvas_fragment(VOut in [[stage_in]],
                                constant Frame& F [[buffer(0)]],
                                texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    uint kind = in.u0.x;
    float cov;
    float4 c = in.color;
    if (kind == K_SEG) {
        float s = in.v0.x, t = in.v0.y, L = in.f0.x;
        float2 P = float2(s, t);
        float dself = length(float2(s - clamp(s, 0.0, L), t));
        // Joint ownership: a pixel is drawn by the closest segment only (no double blending, exact round joins).
        // The tolerance makes both neighbours claim pixels whose distances tie within float rounding (a seam would
        // be visible; a doubly drawn pixel inside the pen is not).
        float eps = 1e-4 + 2e-6 * (abs(s) + abs(t) + L);
        if ((in.u0.z & 2u) != 0u && dself > segDist(P, float2(L, 0.0), float2(L, 0.0) + in.f1.xy) + eps) return float4(0.0);
        if ((in.u0.z & 1u) != 0u && dself > segDist(P, in.f1.zw, float2(0.0)) + eps) return float4(0.0);
        float hw = 0.5 * in.f0.y;
        float2 dir = in.f2.xy, nrm = float2(-dir.y, dir.x);
        bool contLo = (in.u0.z & 1u) != 0u, contHi = (in.u0.z & 2u) != 0u;
        // Radial model: distance to the nearest "on" piece (round caps and joins).
        float g = strokeGap(s, 0.0, L, in.f0.z, in.u0.y, in.f0.w);
        float radial = 0.0;
        if (abs(g) < 1e15) {
            float2 n = dir * g + nrm * t;
            radial = bandCov(length(float2(g, t)), hw, footprint(length(n) > 1e-6 ? n : nrm));
            if (g != 0.0) radial *= in.f2.z;
        }
        if ((s < 0.0 && contLo) || (s > L && contHi)) {
            cov = radial;                      // the joint wedge beyond an interior vertex
        } else {
            float2 fp = footprint(nrm);
            float thin = bandCov(abs(t), hw, fp) * alongCoverage(s, L, contLo, contHi, in.f0.z, in.u0.y, in.f0.w, capLength(hw), fp);
            cov = mix(thin, radial, clamp(hw - 0.5, 0.0, 1.0));
        }
    } else if (kind == K_ARC) {
        float xp = in.v0.x, y = in.v0.y, R = in.f0.x, th = in.f0.y;
        uint fl = in.u0.z;  // bit 0: cap at start, bit 1: cap at end (otherwise the next sub-arc continues)
        float X = R + xp;
        float ang = atan2(y, X);
        float L = 2.0 * R * th;
        float perp, s;
        float2 rh, th2;     // local radial / tangential unit vectors at the closest skeleton point
        const float epsA = 2e-6;   // both sub-arcs claim boundary pixels within rounding (no seam)
        if (ang >= -th - epsA && ang <= th + epsA) {
            float rad = sqrt(X * X + y * y);
            perp = (xp * (xp + 2.0 * R) + y * y) / max(rad + R, 1e-12);
            s = R * (ang + th);
            rh = float2(cos(ang), sin(ang));
            th2 = float2(-rh.y, rh.x);
        } else {
            float sg = ang >= th ? 1.0 : -1.0;
            if ((sg > 0.0 && (fl & 2u) == 0u) || (sg < 0.0 && (fl & 1u) == 0u)) return float4(0.0);
            float sh = sin(0.5 * th);
            float2 qE = float2(xp + 2.0 * R * sh * sh, y - sg * R * sin(th));
            th2 = float2(-sg * sin(th), cos(th));
            rh = float2(cos(th), sg * sin(th));
            float along = dot(qE, th2);
            perp = dot(qE, rh);
            s = sg > 0.0 ? L + along : along;
        }
        bool contLo = (fl & 1u) == 0u, contHi = (fl & 2u) == 0u;
        float hw = 0.5 * in.f1.x;
        float2 m = in.f2.xy, td = float2(-m.y, m.x) * in.f2.z;
        float g = strokeGap(s, contLo ? -1e30 : 0.0, contHi ? 1e30 : L, in.f0.z, in.u0.y, in.f0.w);
        float radial = 0.0;
        if (abs(g) < 1e15) {
            float2 nl = rh * perp + th2 * g;
            float2 n = m * nl.x + td * nl.y;
            radial = bandCov(length(float2(perp, g)), hw, footprint(length(n) > 1e-6 ? n : m * rh.x + td * rh.y));
            if (g != 0.0) radial *= in.f2.w;
        }
        float2 fp = footprint(m * rh.x + td * rh.y);
        float thin = bandCov(abs(perp), hw, fp) * alongCoverage(s, L, contLo, contHi, in.f0.z, in.u0.y, in.f0.w, capLength(hw), fp);
        cov = mix(thin, radial, clamp(hw - 0.5, 0.0, 1.0));
    } else if (kind == K_TRI) {
        float aa = footCDF(in.v0.x, in.f1.y, in.f1.z) * footCDF(in.v0.y, in.f1.w, in.f2.x) * footCDF(in.v0.z, in.f2.y, in.f2.z);
        uint mode = in.u0.z;
        if (mode == 3u) {
            float4 cv = clamp(F.canvas, 0.0, 1.0);
            return float4(cv.rgb * cv.a, cv.a) * aa;
        }
        float alpha = in.f0.x;
        float4 bg = clamp(in.color2, 0.0, 1.0);
        float a1 = alpha * bg.a;
        float4 pcol = c;
        float pc = 1.0;
        if (mode == 1u) {
            float k = in.f0.w;
            float2 pat = F.camView * k + in.v1 * k;
            pc = patternCoverage(in.u0.y, pat, in.f1.x, in.f0.y, in.f0.z);
        } else if (mode == 2u) {
            pcol = float4(mix(c.rgb, F.canvas.rgb, 0.8), c.a);
        }
        pcol = clamp(pcol, 0.0, 1.0);
        float a2 = alpha * pcol.a * pc;
        float3 rgb = pcol.rgb * a2 + bg.rgb * a1 * (1.0 - a2);
        float A = a2 + a1 * (1.0 - a2);
        return float4(rgb, A) * aa;
    } else {
        float d = atlas.sample(smp, in.v0.xy).r * in.f0.x;
        float2 fp = footprint(float2(dfdx(d), dfdy(d)));
        cov = footCDF(d, fp.x, fp.y);
    }
    c = clamp(c, 0.0, 1.0);
    return float4(c.rgb * (c.a * cov), c.a * cov);
}
"""#
}
