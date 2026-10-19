import AppKit
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// COMPB: contact sheets of group B's components, rendered offscreen to `/tmp/arcus-compb/` to check each by eye: one
/// row per component with every type shaded at Fine, the default type at Medium and Coarse, and its 2D symbols (face
/// or plan view, and the top or side view) at Coarse and Fine.
@Suite("COMPB contact sheets", .serialized)
struct COMPBRenderTests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-compb")
    static let cell = 200

    /// The evaluated family with only the solids shown at `level`.
    static func evaluated(_ d: ComponentDefinition, _ type: String, _ level: DetailLevel) -> EvaluatedFamily {
        var ev = FamilyEvaluator.evaluate(d.family, typeName: type)
        ev.solids = ev.solids.filter { $0.visibleAt.contains(level) && !$0.isVoid }
        return ev
    }

    /// The component's symbols for one view at one level, evaluated as plan lines of a copy of its family.
    static func symbolLines(_ d: ComponentDefinition, _ type: String, _ view: ComponentSymbolView, _ level: DetailLevel) -> [(Curve2, Bool)] {
        var f = d.family
        f.solids = []
        f.planLines = []
        var dashed: [Bool] = []
        for s in d.symbols where s.view == view && s.levels.contains(level) {
            for shape in s.shapes {
                var ls: [FamilyLine.Shape] = []
                switch shape {
                case .line(let a, let b): ls = [.line(a, b)]
                case .polyline(let pts, let closed):
                    for i in 0..<(closed ? pts.count : pts.count - 1) { ls.append(.line(pts[i], pts[(i + 1) % pts.count])) }
                case .rectangle(let a, let b):
                    let c = [a, FamilyPoint(b.x, a.y), b, FamilyPoint(a.x, b.y)]
                    for i in 0..<4 { ls.append(.line(c[i], c[(i + 1) % 4])) }
                case .circle(let c, let r): ls = [.arc(center: c, radius: r, startDegrees: "0", sweepDegrees: "360")]
                case .arc(let c, let r, let a0, let sw): ls = [.arc(center: c, radius: r, startDegrees: a0, sweepDegrees: sw)]
                }
                for l in ls { f.planLines.append(FamilyLine(shape: l)); dashed.append(s.dashed) }
            }
        }
        let ev = FamilyEvaluator.evaluate(f, typeName: type)
        return zip(ev.planLines.map(\.curve), dashed).map { ($0, $1) }
    }

    static func colors(_ d: ComponentDefinition) -> [String: ArcusDomain.RGBColor] {
        Dictionary(d.materials.map { ($0.name, $0.finish.color) }, uniquingKeysWith: { a, _ in a })
    }

    static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func shaded(_ d: ComponentDefinition, _ type: String, _ level: DetailLevel) -> CGImage? {
        guard let ctx = context(cell, cell) else { return nil }
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: cell, height: cell))
        let fallback = ArcusDomain.RGBColor(hex: 0x8C8F93)
        ShadedFamilyRenderer.draw(evaluated(d, type, level), colors: colors(d), fallback: fallback, ctx, width: cell, height: cell)
        return ctx.makeImage()
    }

    static func symbols(_ d: ComponentDefinition, _ type: String, _ view: ComponentSymbolView, _ level: DetailLevel) -> CGImage? {
        guard let ctx = context(cell, cell) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: cell, height: cell))
        let lines = symbolLines(d, type, view, level)
        var r = Rect2.empty
        for (c, _) in lines { r.include(c.bounds) }
        guard !lines.isEmpty, r.width.isFinite, r.width + r.height > 1e-7 else { return ctx.makeImage() }
        let scale = min(Double(cell) * 0.8 / max(r.width, 1e-4), Double(cell) * 0.8 / max(r.height, 1e-4))
        let ox = Double(cell) / 2 - (r.min.x + r.width / 2) * scale, oy = Double(cell) / 2 - (r.min.y + r.height / 2) * scale
        func p(_ v: Vec2) -> CGPoint { CGPoint(x: v.x * scale + ox, y: v.y * scale + oy) }
        ctx.setLineWidth(1.5)
        for (c, dashed) in lines {
            ctx.setStrokeColor(dashed ? CGColor(srgbRed: 0.2, green: 0.3, blue: 0.7, alpha: 0.8) : CGColor(gray: 0.1, alpha: 1))
            ctx.setLineDash(phase: 0, lengths: dashed ? [5, 3] : [])
            switch c {
            case .line(let s): ctx.move(to: p(s.start)); ctx.addLine(to: p(s.end))
            case .arc(let a):
                let pts = a.tessellate(chordTolerance: max(1e-6, 0.5 / scale))
                if let f = pts.first { ctx.move(to: p(f)); for q in pts.dropFirst() { ctx.addLine(to: p(q)) } }
            }
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    static func label(_ ctx: CGContext, _ text: String, x: Int, y: Int, size: CGFloat = 13, bold: Bool = false) {
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                                                                          .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Writes contact sheets of `defs`, `perPage` rows each, as "<name> <page>.png".
    static func sheets(_ name: String, _ defs: [ComponentDefinition], perPage: Int = 7) throws {
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let cols = 9, rowH = cell + 36, w = cols * cell
        for (page, start) in stride(from: 0, to: defs.count, by: perPage).enumerated() {
            let slice = Array(defs[start..<min(defs.count, start + perPage)])
            let h = slice.count * rowH
            let ctx = try #require(context(w, h))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            for (i, d) in slice.enumerated() {
                let y = h - (i + 1) * rowH
                let def = d.defaultType?.name ?? ""
                var images: [(String, CGImage?)] = d.types.prefix(4).map { ($0.name, shaded(d, $0.name, .fine)) }
                while images.count < 4 { images.append(("", nil)) }
                images.append(("Medium", shaded(d, def, .medium)))
                images.append(("Coarse", shaded(d, def, .coarse)))
                let main: ComponentSymbolView = d.frame == .plan ? .face : .face
                let second: ComponentSymbolView = d.frame == .plan ? .side : .top
                images.append(("\(main.rawValue) coarse", symbols(d, def, main, .coarse)))
                images.append(("\(main.rawValue) fine", symbols(d, def, main, .fine)))
                images.append(("\(second.rawValue) coarse", symbols(d, def, second, .coarse)))
                for (k, (t, img)) in images.enumerated() {
                    if let img { ctx.draw(img, in: CGRect(x: k * cell, y: y + 18, width: cell, height: cell)) }
                    label(ctx, String(t.prefix(28)), x: k * cell + 4, y: y + 2, size: 10)
                }
                ctx.setStrokeColor(CGColor(gray: 0.8, alpha: 1)); ctx.stroke(CGRect(x: 0, y: y, width: w, height: rowH))
                label(ctx, "\(d.name)  ·  \(d.subcategory)  ·  \(d.types.count) types", x: 6, y: y + rowH - 17, size: 13, bold: true)
            }
            let img = try #require(ctx.makeImage())
            try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent("\(name) \(page + 1).png"))
        }
    }

    @Test func connectorsSheet() throws { try Self.sheets("06 Connectors", ComponentLibrary.groupBConnectors) }
    @Test func legsSheet() throws { try Self.sheets("07 Legs", ComponentLibrary.groupBLegs) }
    @Test func wardrobeSheet() throws { try Self.sheets("09 Wardrobe", ComponentLibrary.groupBWardrobe) }
    @Test func mobilitySheet() throws { try Self.sheets("15 Mobility", ComponentLibrary.groupBMobility) }
    @Test func shelvingSheet() throws { try Self.sheets("08 Shelving", ComponentLibrary.groupBShelving) }
}
