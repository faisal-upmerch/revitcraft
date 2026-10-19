import SwiftUI

// HOME: the Start cards' illustrations, drawn (no image assets) so they stay crisp at any size and follow the
// appearance: a building elevation with a level datum, a sideboard front with a dimension, and a door in plan between
// reference planes.

/// A card's illustration on its tinted tile.
struct HomeIllustration: View {
    let card: HomeCard
    var size: CGFloat = 64
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tint = card.tint
        let dark = scheme == .dark
        let shape = RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
        Canvas { ctx, s in
            let p = Palette(tint: tint, dark: dark)
            switch card {
            case .architectural: Self.building(ctx, s, p)
            case .furniture: Self.sideboard(ctx, s, p)
            case .family: Self.doorPlan(ctx, s, p)
            }
        }
        .frame(width: size, height: size)
        .background(shape.fill(LinearGradient(colors: [tint.opacity(dark ? 0.34 : 0.20), tint.opacity(dark ? 0.16 : 0.08)], startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(tint.opacity(dark ? 0.35 : 0.22), lineWidth: 1))
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    /// Colours shared by the drawings.
    struct Palette {
        let tint: Color
        let dark: Bool
        /// Line work.
        var ink: Color { dark ? Color(white: 0.92) : Color(red: 0.16, green: 0.18, blue: 0.22) }
        /// Paper-white faces.
        var face: Color { dark ? Color(white: 0.30) : .white }
        /// A second, quieter face.
        var faceShade: Color { dark ? Color(white: 0.22) : Color(white: 0.93) }
        var accent: Color { tint }
    }

    private static func r(_ s: CGSize, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect {
        CGRect(x: s.width * x, y: s.height * y, width: s.width * w, height: s.height * h)
    }
    private static func pt(_ s: CGSize, _ x: Double, _ y: Double) -> CGPoint { CGPoint(x: s.width * x, y: s.height * y) }

    // MARK: Architectural

    static func building(_ ctx: GraphicsContext, _ s: CGSize, _ p: Palette) {
        let lw = max(1, s.width * 0.018)
        // Ground.
        var ground = Path(); ground.move(to: pt(s, 0.10, 0.80)); ground.addLine(to: pt(s, 0.90, 0.80))
        ctx.stroke(ground, with: .color(p.ink.opacity(0.55)), lineWidth: lw)
        // Low wing, then the main block.
        let wing = Path(roundedRect: r(s, 0.62, 0.50, 0.24, 0.30), cornerRadius: s.width * 0.015)
        ctx.fill(wing, with: .color(p.faceShade))
        ctx.stroke(wing, with: .color(p.ink.opacity(0.7)), lineWidth: lw)
        let block = Path(roundedRect: r(s, 0.18, 0.30, 0.46, 0.50), cornerRadius: s.width * 0.015)
        ctx.fill(block, with: .color(p.face))
        ctx.stroke(block, with: .color(p.ink.opacity(0.85)), lineWidth: lw)
        // Windows: three floors of three.
        for row in 0..<3 {
            for col in 0..<3 {
                let w = Path(roundedRect: r(s, 0.245 + Double(col) * 0.125, 0.37 + Double(row) * 0.125, 0.08, 0.075), cornerRadius: s.width * 0.008)
                ctx.fill(w, with: .color(p.accent.opacity(row == 2 && col == 1 ? 0 : 0.75)))
            }
        }
        // Entrance.
        ctx.fill(Path(roundedRect: r(s, 0.37, 0.62, 0.08, 0.18), cornerRadius: s.width * 0.008), with: .color(p.accent))
        // Wing window band.
        ctx.fill(Path(roundedRect: r(s, 0.67, 0.58, 0.14, 0.07), cornerRadius: s.width * 0.008), with: .color(p.accent.opacity(0.55)))
        // Level datum: dashed line with a level head.
        var datum = Path(); datum.move(to: pt(s, 0.08, 0.30)); datum.addLine(to: pt(s, 0.80, 0.30))
        ctx.stroke(datum, with: .color(p.accent), style: StrokeStyle(lineWidth: lw, dash: [s.width * 0.05, s.width * 0.03]))
        let c = pt(s, 0.86, 0.30), rad = s.width * 0.055
        let head = Path(ellipseIn: CGRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2))
        ctx.fill(head, with: .color(p.face))
        ctx.stroke(head, with: .color(p.accent), lineWidth: lw)
        var q = Path()
        q.move(to: c); q.addArc(center: c, radius: rad, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false); q.closeSubpath()
        q.move(to: c); q.addArc(center: c, radius: rad, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false); q.closeSubpath()
        ctx.fill(q, with: .color(p.accent))
    }

    // MARK: Furniture

    static func sideboard(_ ctx: GraphicsContext, _ s: CGSize, _ p: Palette) {
        let lw = max(1, s.width * 0.018)
        let wood = p.accent
        // Overall width dimension with ticks.
        var dim = Path(); dim.move(to: pt(s, 0.13, 0.17)); dim.addLine(to: pt(s, 0.87, 0.17))
        for x in [0.13, 0.87] {
            dim.move(to: pt(s, x - 0.03, 0.20)); dim.addLine(to: pt(s, x + 0.03, 0.14))
            dim.move(to: pt(s, x, 0.15)); dim.addLine(to: pt(s, x, 0.25))
        }
        ctx.stroke(dim, with: .color(p.ink.opacity(0.5)), lineWidth: max(1, lw * 0.7))
        // Top board.
        let top = Path(roundedRect: r(s, 0.12, 0.28, 0.76, 0.06), cornerRadius: s.width * 0.012)
        ctx.fill(top, with: .color(wood))
        // Carcass with a drawer row over two doors.
        let carcass = r(s, 0.16, 0.34, 0.68, 0.36)
        ctx.fill(Path(carcass), with: .color(p.face))
        var lines = Path()
        lines.move(to: pt(s, 0.16, 0.45)); lines.addLine(to: pt(s, 0.84, 0.45))
        lines.move(to: pt(s, 0.50, 0.34)); lines.addLine(to: pt(s, 0.50, 0.70))
        ctx.stroke(lines, with: .color(p.ink.opacity(0.6)), lineWidth: lw * 0.8)
        ctx.stroke(Path(carcass), with: .color(p.ink.opacity(0.85)), lineWidth: lw)
        // Handles: drawer pulls and door knobs.
        for x in [0.30, 0.64] { ctx.fill(Path(roundedRect: r(s, x, 0.385, 0.06, 0.022), cornerRadius: s.width * 0.011), with: .color(p.ink.opacity(0.75))) }
        for x in [0.455, 0.525] { ctx.fill(Path(roundedRect: r(s, x, 0.53, 0.02, 0.08), cornerRadius: s.width * 0.01), with: .color(p.ink.opacity(0.75))) }
        // Grain hint on the doors.
        var grain = Path()
        for (x0, x1) in [(0.21, 0.42), (0.58, 0.79)] {
            for (i, y) in [0.52, 0.58, 0.64].enumerated() {
                grain.move(to: pt(s, x0 + Double(i) * 0.02, y)); grain.addQuadCurve(to: pt(s, x1 - Double(i) * 0.02, y), control: pt(s, (x0 + x1) / 2, y - 0.025))
            }
        }
        ctx.stroke(grain, with: .color(wood.opacity(0.45)), lineWidth: max(0.75, lw * 0.6))
        // Tapered legs.
        for x in [0.21, 0.79] {
            var leg = Path()
            leg.move(to: pt(s, x - 0.025, 0.70)); leg.addLine(to: pt(s, x + 0.025, 0.70))
            leg.addLine(to: pt(s, x + 0.012, 0.83)); leg.addLine(to: pt(s, x - 0.012, 0.83)); leg.closeSubpath()
            ctx.fill(leg, with: .color(wood))
        }
    }

    // MARK: Family

    static func doorPlan(_ ctx: GraphicsContext, _ s: CGSize, _ p: Palette) {
        let lw = max(1, s.width * 0.018)
        // Reference planes.
        var planes = Path()
        planes.move(to: pt(s, 0.50, 0.08)); planes.addLine(to: pt(s, 0.50, 0.92))
        planes.move(to: pt(s, 0.08, 0.68)); planes.addLine(to: pt(s, 0.92, 0.68))
        ctx.stroke(planes, with: .color(p.accent.opacity(0.9)), style: StrokeStyle(lineWidth: max(0.75, lw * 0.7), dash: [s.width * 0.05, s.width * 0.025, s.width * 0.012, s.width * 0.025]))
        // Wall either side of the opening.
        for x in [0.08, 0.72] {
            let wall = Path(r(s, x, 0.62, 0.20, 0.12))
            ctx.fill(wall, with: .color(p.faceShade))
            ctx.stroke(wall, with: .color(p.ink.opacity(0.85)), lineWidth: lw)
            var hatch = Path()
            for i in 0..<4 {
                let x0 = x + 0.02 + Double(i) * 0.05
                hatch.move(to: pt(s, x0, 0.74)); hatch.addLine(to: pt(s, x0 + 0.05, 0.62))
            }
            var clipped = ctx
            clipped.clip(to: wall)
            clipped.stroke(hatch, with: .color(p.ink.opacity(0.35)), lineWidth: max(0.75, lw * 0.6))
        }
        // Swing arc, then the leaf.
        let hinge = pt(s, 0.28, 0.62), radius = s.width * 0.44
        var arc = Path()
        arc.addArc(center: hinge, radius: radius, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        ctx.stroke(arc, with: .color(p.ink.opacity(0.55)), style: StrokeStyle(lineWidth: max(0.75, lw * 0.7), dash: [s.width * 0.03, s.width * 0.02]))
        let leaf = Path(roundedRect: CGRect(x: hinge.x - s.width * 0.035, y: hinge.y - radius, width: s.width * 0.035, height: radius), cornerRadius: s.width * 0.008)
        ctx.fill(leaf, with: .color(p.face))
        ctx.stroke(leaf, with: .color(p.ink.opacity(0.9)), lineWidth: lw)
        // Labelled width dimension.
        var dim = Path()
        dim.move(to: pt(s, 0.28, 0.84)); dim.addLine(to: pt(s, 0.72, 0.84))
        for x in [0.28, 0.72] { dim.move(to: pt(s, x - 0.025, 0.865)); dim.addLine(to: pt(s, x + 0.025, 0.815)) }
        ctx.stroke(dim, with: .color(p.accent), lineWidth: max(1, lw * 0.8))
    }
}
