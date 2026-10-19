import AppKit
import simd
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusOutput

/// COMPC: every Group C component drawn for checking by eye: its default type shaded at Fine (three-quarter view, the
/// finishes' colours) beside its Coarse 2D symbols (plan on top, elevation below), on contact sheets of twelve in
/// /tmp/arcus-compc/sheet-N.png. The test checks each one draws.
@MainActor
@Suite("COMPC component renders")
struct COMPCRenderTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-compc")

    /// The family's solids for the type, at a detail level.
    static func evaluated(_ d: ComponentDefinition, _ type: String, detail: DetailLevel) -> EvaluatedFamily {
        var ev = FamilyEvaluator.evaluate(d.family, typeName: type)
        ev.solids = ev.solids.filter { !$0.isVoid && $0.visibleAt.contains(detail) }
        // Face-based items stand on their host face: Z (out of the face) toward the viewer, Y up.
        if d.frame == .face {
            let t = Transform3(simd_double4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, -1, 0, 0), SIMD4(0, 0, 0, 1))))
            for k in ev.solids.indices { ev.solids[k].mesh = ev.solids[k].familyMesh.transformed(t) }
        }
        return ev
    }

    /// A symbol's shapes as plan lines of a scratch family, so the evaluator resolves their expressions.
    static func symbolLines(_ d: ComponentDefinition, _ type: String, _ view: ComponentSymbolView, _ level: DetailLevel) -> [(Curve2, Bool)] {
        var f = d.family
        f.planLines = []
        var dashed: [Bool] = []
        for s in d.symbols where s.view == view && s.levels.contains(level) {
            for sh in s.shapes {
                var lines: [FamilyLine.Shape] = []
                switch sh {
                case .line(let a, let b): lines = [.line(a, b)]
                case .polyline(let p, let closed):
                    for k in 0..<(closed ? p.count : p.count - 1) { lines.append(.line(p[k], p[(k + 1) % p.count])) }
                case .rectangle(let a, let b):
                    let c = [a, FamilyPoint(b.x, a.y), b, FamilyPoint(a.x, b.y)]
                    for k in 0..<4 { lines.append(.line(c[k], c[(k + 1) % 4])) }
                case .circle(let c, let r): lines = [.arc(center: c, radius: r, startDegrees: "0", sweepDegrees: "360")]
                case .arc(let c, let r, let s0, let sw): lines = [.arc(center: c, radius: r, startDegrees: s0, sweepDegrees: sw)]
                }
                for l in lines { f.planLines.append(FamilyLine(shape: l)); dashed.append(s.dashed) }
            }
        }
        let ev = FamilyEvaluator.evaluate(f, typeName: type)
        return zip(ev.planLines.map(\.curve), dashed).map { ($0, $1) }
    }

    static func drawSymbols(_ lines: [(Curve2, Bool)], in rect: CGRect, _ ctx: CGContext) {
        var b = Rect2.empty
        let pts = lines.map { $0.0.tessellate(chordTolerance: 0.00005) }
        for p in pts { for q in p { b.include(q) } }
        guard b.max.x >= b.min.x else { return }
        let w = max(b.max.x - b.min.x, 1e-3), h = max(b.max.y - b.min.y, 1e-3)
        let s = min((rect.width - 16) / w, (rect.height - 16) / h)
        let ox = rect.midX - (b.min.x + w / 2) * s, oy = rect.midY - (b.min.y + h / 2) * s
        for (k, p) in pts.enumerated() where p.count > 1 {
            ctx.setStrokeColor(lines[k].1 ? NSColor.systemBlue.cgColor : NSColor.black.cgColor)
            ctx.setLineWidth(1.2)
            ctx.setLineDash(phase: 0, lengths: lines[k].1 ? [4, 3] : [])
            ctx.move(to: CGPoint(x: ox + p[0].x * s, y: oy + p[0].y * s))
            for q in p.dropFirst() { ctx.addLine(to: CGPoint(x: ox + q.x * s, y: oy + q.y * s)) }
            ctx.strokePath()
        }
        ctx.setLineDash(phase: 0, lengths: [])
    }

    @Test func everyComponentDrawsWithItsSymbols() throws {
        try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        let defs = ComponentsC.all
        let (tw, th, label, sym) = (360, 300, 24, 170)
        let cols = 3, rows = 4
        for (page, start) in stride(from: 0, to: defs.count, by: cols * rows).enumerated() {
            let list = Array(defs[start..<min(defs.count, start + cols * rows)])
            let cw = tw + sym, ch = th + label
            let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cols * cw, pixelsHigh: rows * ch, bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            NSGraphicsContext.saveGraphicsState()
            let g = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current = g
            let ctx = try #require(g?.cgContext)
            NSColor(white: 0.97, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: cols * cw, height: rows * ch).fill()
            for (i, d) in list.enumerated() {
                let c = i % cols, r = i / cols
                let x0 = CGFloat(c * cw), y0 = CGFloat((rows - 1 - r) * ch)
                let type = try #require(d.defaultType?.name)
                let ev = Self.evaluated(d, type, detail: .fine)
                #expect(!ev.solids.isEmpty, "\(d.name) draws")
                var colors: [String: ArcusDomain.RGBColor] = [:]
                for m in d.materials { colors[m.name] = m.finish.color }
                ctx.saveGState()
                ctx.translateBy(x: x0, y: y0)
                ShadedFamilyRenderer.draw(ev, colors: colors, fallback: ArcusDomain.RGBColor(hex: 0x9EA3A8), ctx, width: tw, height: th)
                ctx.restoreGState()
                let planView: ComponentSymbolView = .face
                Self.drawSymbols(Self.symbolLines(d, type, planView, .coarse), in: CGRect(x: x0 + CGFloat(tw), y: y0 + CGFloat(th / 2), width: CGFloat(sym), height: CGFloat(th / 2)), ctx)
                var elev = Self.symbolLines(d, type, .top, .coarse)
                if elev.isEmpty { elev = Self.symbolLines(d, type, .side, .coarse) }
                Self.drawSymbols(elev, in: CGRect(x: x0 + CGFloat(tw), y: y0, width: CGFloat(sym), height: CGFloat(th / 2)), ctx)
                NSColor(white: 0.8, alpha: 1).setStroke()
                NSRect(x: x0, y: y0, width: CGFloat(cw), height: CGFloat(ch)).frame()
                NSRect(x: x0 + CGFloat(tw), y: y0, width: CGFloat(sym), height: CGFloat(th)).frame()
                ("\(d.category.code) \(d.name) · \(type)" as NSString).draw(at: NSPoint(x: x0 + 6, y: y0 + CGFloat(th) + 4),
                                                                           withAttributes: [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black])
            }
            NSGraphicsContext.restoreGraphicsState()
            let png = try #require(rep.representation(using: .png, properties: [:]))
            try png.write(to: Self.dir.appendingPathComponent("sheet-\(page + 1).png"))
        }
    }
}
