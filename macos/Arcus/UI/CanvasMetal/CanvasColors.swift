import ArcusDomain
import ArcusOutput

/// Canvas colour and ink mapping for a set of `RenderOptions` — a line-for-line port of `RenderPass.canvas` /
/// `RenderPass.darkMap` in GraphicsRenderer.swift (verified against it by `ColorParityTests`).
///
/// Only the option-dependent part (dark mapping of every scene colour) is evaluated on the CPU, once per option change,
/// into a small colour table; halftone blending and highlight tinting happen in the shader so that they can change per
/// item without touching geometry.
nonisolated struct CanvasColors: Sendable, Equatable {
    let dark: Bool
    /// Paper/canvas colour used for the background clear, masks, halftone and pattern tints.
    let canvas: RGBColor

    init(options: RenderOptions) {
        dark = options.darkCanvas && !options.printing
        if dark {
            if let b = options.background ?? options.canvasColor, b.luminance < 0.5 { canvas = b } else { canvas = RGBColor(0.13, 0.13, 0.14) }
        } else {
            canvas = options.background ?? options.canvasColor ?? .white
        }
    }

    /// Dark-canvas mapping: near-white → canvas, grays invert their lightness toward the canvas, dark colours are lifted.
    func darkMap(_ c: RGBColor) -> RGBColor {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b)
        let sat = mx - mn
        let lum = c.luminance
        if lum > 0.92 && sat < 0.08 { return RGBColor(canvas.r, canvas.g, canvas.b, c.a) }
        if sat < 0.12 {
            let cl = canvas.luminance
            let v = cl + (0.9 - cl) * (1 - lum)
            return RGBColor(v, v, min(1, v + 0.01), c.a)
        }
        if lum < 0.5 {
            let m = c.mixed(with: .white, amount: 0.5 - lum)
            return RGBColor(m.r, m.g, m.b, c.a)
        }
        return c
    }

    /// Ink before halftone/highlight (GraphicsRenderer `ink` with halftone false and no highlight).
    func resolve(_ c: RGBColor) -> RGBColor { dark ? darkMap(c) : c }

    /// Colour table for the GPU: index 0 is the canvas, the rest are the scene's raw colours resolved.
    func table(_ raw: [RGBColor]) -> [SIMD4<Float>] {
        var out = [SIMD4<Float>](repeating: .zero, count: max(raw.count, 1))
        out[0] = canvas.simd
        if raw.count > 1 { for i in 1..<raw.count { out[i] = resolve(raw[i]).simd } }
        return out
    }
}

nonisolated extension RGBColor {
    var simd: SIMD4<Float> { SIMD4(Float(r), Float(g), Float(b), Float(a)) }
}
