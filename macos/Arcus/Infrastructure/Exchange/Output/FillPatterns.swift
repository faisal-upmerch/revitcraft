import CoreGraphics
import Foundation
import ArcusDomain

/// Vector hatch generation for every `FillPatternKind`.
///
/// Patterns are generated in *pattern space* — paper millimeters for drafting patterns, model meters for model
/// patterns — anchored at the view origin so they neither swim when panning nor depend on the region. The caller clips
/// the context to the region (even-odd, so holes stay empty); only the visible part of the clip is generated.
/// Generation is deterministic (lattice hashing, no random numbers) and bounded: when lines would be closer than
/// ~2 device pixels, or a single fill would need more than `maxElements` marks, `draw` returns false and the caller
/// paints a light tint instead.
public enum FillPatterns {
    public static let maxElements = 40_000

    /// Base spacing of a pattern: (drafting paper mm, model meters).
    public static func spacing(_ k: FillPatternKind) -> (drafting: Double, model: Double) {
        switch k {
        case .solid: (1, 0.05)
        case .diagonalUp, .diagonalDown, .horizontal, .vertical: (1.6, 0.08)
        case .crosshatch, .diagonalCrosshatch: (2.0, 0.1)
        case .concrete: (1.5, 0.075)
        case .brick: (1.5, 0.075)          // course height (model: 65 mm brick + 10 mm joint)
        case .insulation: (4.0, 0.1)       // batt band height
        case .sand: (0.8, 0.04)
        case .wood: (1.2, 0.06)
        case .grid: (3.0, 0.6)             // model: 600 mm ceiling / paving grid
        case .earth: (4.0, 0.2)
        }
    }

    /// Draws `kind` into the current clip. `frame` maps pattern units to device space. Returns false when the pattern
    /// is too dense to draw meaningfully (caller tints instead).
    static func draw(_ kind: FillPatternKind, isModel: Bool, in ctx: CGContext, visible: CGRect, frame: CGAffineTransform,
                     devicePerUnit: Double, color: CGColor, lineWidth: CGFloat, devicePixel: CGFloat) -> Bool {
        guard devicePerUnit > 0, devicePerUnit.isFinite else { return false }
        let sp = spacing(kind)
        let s = isModel ? sp.model : sp.drafting
        if s * devicePerUnit < Double(devicePixel) * 2 { return false }
        let r = visible.applying(frame.inverted())
        guard r.width.isFinite, r.height.isFinite, r.width > 0, r.height > 0 else { return false }
        let w = Double(r.width), h = Double(r.height)
        let estimate: Double
        switch kind {
        case .solid: estimate = 1
        case .diagonalUp, .diagonalDown, .horizontal, .vertical: estimate = (w + h) / s
        case .crosshatch, .diagonalCrosshatch, .grid: estimate = 2 * (w + h) / s
        case .concrete: estimate = w * h / (s * s) * 1.2
        case .sand: estimate = w * h / (s * s)
        case .brick: estimate = w * h / (s * s * 3) + h / s
        case .insulation: estimate = w * h / (s * s / 3) * 2
        case .wood: estimate = (h / s) * (w / (s * 10 / 8))
        case .earth: estimate = w * h / (s * s) * 3
        }
        if estimate > Double(maxElements) { return false }

        let strokes = CGMutablePath()
        let dots = CGMutablePath()
        let rect = PRect(minX: Double(r.minX), minY: Double(r.minY), maxX: Double(r.maxX), maxY: Double(r.maxY))
        switch kind {
        case .solid: return false
        case .diagonalUp: lines(strokes, angle: .pi / 4, spacing: s, rect)
        case .diagonalDown: lines(strokes, angle: 3 * .pi / 4, spacing: s, rect)
        case .horizontal: lines(strokes, angle: 0, spacing: s, rect)
        case .vertical: lines(strokes, angle: .pi / 2, spacing: s, rect)
        case .crosshatch, .grid:
            lines(strokes, angle: 0, spacing: s, rect); lines(strokes, angle: .pi / 2, spacing: s, rect)
        case .diagonalCrosshatch:
            lines(strokes, angle: .pi / 4, spacing: s, rect); lines(strokes, angle: 3 * .pi / 4, spacing: s, rect)
        case .concrete: concrete(strokes, dots, spacing: s, rect)
        case .sand: stipple(dots, spacing: s, radius: 0.08, salt: 11, rect)
        case .brick: brick(strokes, course: s, length: s * 3, rect)
        case .insulation: insulation(strokes, band: s, rect)
        case .wood: wood(strokes, spacing: s, rect)
        case .earth: earth(strokes, cell: s, rect)
        }
        ctx.saveGState()
        ctx.concatenate(frame)
        ctx.setLineWidth(lineWidth / CGFloat(devicePerUnit))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        if !strokes.isEmpty { ctx.addPath(strokes); ctx.strokePath() }
        if !dots.isEmpty { ctx.addPath(dots); ctx.fillPath() }
        ctx.restoreGState()
        return true
    }

    struct PRect { var minX, minY, maxX, maxY: Double }

    // MARK: Deterministic hashing

    static func hash(_ i: Int, _ j: Int, _ salt: UInt64) -> UInt64 {
        var x = UInt64(bitPattern: Int64(i)) &* 0x9E37_79B9_7F4A_7C15
        x ^= UInt64(bitPattern: Int64(j)) &* 0xC2B2_AE3D_27D4_EB4F
        x ^= salt &* 0x1656_67B1_9E37_79F9
        x ^= x >> 33; x &*= 0xFF51_AFD7_ED55_8CCD
        x ^= x >> 33; x &*= 0xC4CE_B9FE_1A85_EC53
        x ^= x >> 33
        return x
    }
    static func unit(_ h: UInt64) -> Double { Double(h >> 11) / Double(UInt64(1) << 53) }

    // MARK: Generators (pattern space)

    /// Parallel lines through the pattern origin at `angle`, `spacing` apart, spanning `r`.
    static func lines(_ path: CGMutablePath, angle: Double, spacing s: Double, _ r: PRect, offset: Double = 0) {
        let d = (cos(angle), sin(angle)), n = (-sin(angle), cos(angle))
        let corners = [(r.minX, r.minY), (r.maxX, r.minY), (r.maxX, r.maxY), (r.minX, r.maxY)]
        let pn = corners.map { $0.0 * n.0 + $0.1 * n.1 }, pd = corners.map { $0.0 * d.0 + $0.1 * d.1 }
        let nmin = pn.min()!, nmax = pn.max()!, dmin = pd.min()!, dmax = pd.max()!
        let k0 = Int(((nmin - offset) / s).rounded(.up)), k1 = Int(((nmax - offset) / s).rounded(.down))
        guard k0 <= k1 else { return }
        for k in k0...k1 {
            let o = Double(k) * s + offset
            let bx = n.0 * o, by = n.1 * o
            path.move(to: CGPoint(x: bx + d.0 * dmin, y: by + d.1 * dmin))
            path.addLine(to: CGPoint(x: bx + d.0 * dmax, y: by + d.1 * dmax))
        }
    }

    static func cells(_ r: PRect, _ cell: Double) -> (ClosedRange<Int>, ClosedRange<Int>)? {
        let i0 = Int((r.minX / cell).rounded(.down)) - 1, i1 = Int((r.maxX / cell).rounded(.up))
        let j0 = Int((r.minY / cell).rounded(.down)) - 1, j1 = Int((r.maxY / cell).rounded(.up))
        guard i0 <= i1, j0 <= j1 else { return nil }
        return (i0...i1, j0...j1)
    }

    /// Jittered dots on a lattice (sand, concrete stipple). `radius` is a fraction of the spacing.
    static func stipple(_ dots: CGMutablePath, spacing s: Double, radius: Double, salt: UInt64, _ r: PRect) {
        guard let (ii, jj) = cells(r, s) else { return }
        for j in jj {
            for i in ii {
                let h = hash(i, j, salt)
                let x = (Double(i) + unit(h)) * s
                let y = (Double(j) + unit(hash(i, j, salt &+ 1))) * s
                let rad = s * radius * (0.6 + 0.8 * unit(hash(i, j, salt &+ 2)))
                dots.addEllipse(in: CGRect(x: x - rad, y: y - rad, width: 2 * rad, height: 2 * rad))
            }
        }
    }

    /// Concrete: stipple plus scattered aggregate triangles.
    static func concrete(_ strokes: CGMutablePath, _ dots: CGMutablePath, spacing s: Double, _ r: PRect) {
        stipple(dots, spacing: s, radius: 0.07, salt: 3, r)
        let cell = s * 3
        guard let (ii, jj) = cells(r, cell) else { return }
        for j in jj {
            for i in ii where unit(hash(i, j, 7)) < 0.55 {
                let cx = (Double(i) + 0.2 + 0.6 * unit(hash(i, j, 8))) * cell
                let cy = (Double(j) + 0.2 + 0.6 * unit(hash(i, j, 9))) * cell
                let rot = unit(hash(i, j, 10)) * 2 * .pi
                let rad = s * (0.35 + 0.3 * unit(hash(i, j, 12)))
                for k in 0..<3 {
                    let a = rot + Double(k) * 2 * .pi / 3
                    let p = CGPoint(x: cx + rad * cos(a), y: cy + rad * sin(a))
                    if k == 0 { strokes.move(to: p) } else { strokes.addLine(to: p) }
                }
                strokes.closeSubpath()
            }
        }
    }

    /// Running-bond brick: bed joints every course, head joints staggered by half a brick.
    static func brick(_ path: CGMutablePath, course h: Double, length l: Double, _ r: PRect) {
        lines(path, angle: 0, spacing: h, r)
        let j0 = Int((r.minY / h).rounded(.down)), j1 = Int((r.maxY / h).rounded(.up))
        guard j0 <= j1 else { return }
        for j in j0...j1 {
            let y = Double(j) * h
            let shift = (j & 1) == 0 ? 0 : l / 2
            let i0 = Int(((r.minX - shift) / l).rounded(.down)), i1 = Int(((r.maxX - shift) / l).rounded(.up))
            guard i0 <= i1 else { continue }
            for i in i0...i1 {
                let x = Double(i) * l + shift
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x, y: y + h))
            }
        }
    }

    /// Batt insulation: a continuous meander of loops filling bands of height `band`.
    static func insulation(_ path: CGMutablePath, band: Double, _ r: PRect) {
        let w = band / 3, rad = w / 2, period = 2 * w
        let j0 = Int((r.minY / band).rounded(.down)), j1 = Int((r.maxY / band).rounded(.up))
        let k0 = Int((r.minX / period).rounded(.down)) - 1, k1 = Int((r.maxX / period).rounded(.up))
        guard j0 <= j1, k0 <= k1 else { return }
        for j in j0...j1 {
            let y0 = Double(j) * band
            path.move(to: CGPoint(x: Double(k0) * period, y: y0 + rad))
            for k in k0...k1 {
                let x = Double(k) * period
                path.addLine(to: CGPoint(x: x, y: y0 + band - rad))
                path.addArc(center: CGPoint(x: x + rad, y: y0 + band - rad), radius: rad, startAngle: .pi, endAngle: 0, clockwise: true)
                path.addLine(to: CGPoint(x: x + w, y: y0 + rad))
                path.addArc(center: CGPoint(x: x + w + rad, y: y0 + rad), radius: rad, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
            }
        }
    }

    /// Wood grain: gently waving lines with per-line phase and amplitude.
    static func wood(_ path: CGMutablePath, spacing s: Double, _ r: PRect) {
        let lambda = s * 10, dx = lambda / 8
        let j0 = Int((r.minY / s).rounded(.down)) - 1, j1 = Int((r.maxY / s).rounded(.up)) + 1
        let i0 = Int((r.minX / dx).rounded(.down)), i1 = Int((r.maxX / dx).rounded(.up))
        guard j0 <= j1, i0 < i1 else { return }
        for j in j0...j1 {
            let phase = unit(hash(j, 0, 21)) * 2 * .pi
            let amp = s * 0.22 * (0.6 + 0.8 * unit(hash(j, 1, 22)))
            let y0 = Double(j) * s
            for i in i0...i1 {
                let x = Double(i) * dx
                let p = CGPoint(x: x, y: y0 + amp * sin(2 * .pi * x / lambda + phase))
                if i == i0 { path.move(to: p) } else { path.addLine(to: p) }
            }
        }
    }

    /// Earth: staggered groups of three short diagonal strokes.
    static func earth(_ path: CGMutablePath, cell g: Double, _ r: PRect) {
        guard let (ii, jj) = cells(r, g) else { return }
        let len = g * 0.45, gap = g * 0.12
        let d = (cos(Double.pi / 4), sin(Double.pi / 4)), n = (-d.1, d.0)
        for j in jj {
            let shift = (j & 1) == 0 ? 0 : g / 2
            for i in ii {
                let cx = Double(i) * g + shift + g / 2, cy = Double(j) * g + g / 2
                for k in -1...1 {
                    let ox = cx + n.0 * gap * Double(k), oy = cy + n.1 * gap * Double(k)
                    path.move(to: CGPoint(x: ox - d.0 * len / 2, y: oy - d.1 * len / 2))
                    path.addLine(to: CGPoint(x: ox + d.0 * len / 2, y: oy + d.1 * len / 2))
                }
            }
        }
    }
}
