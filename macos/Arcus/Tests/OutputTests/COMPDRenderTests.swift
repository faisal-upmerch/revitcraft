import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// COMPD: every group D component rendered shaded (three-quarter view, its default finishes) to contact sheets in
/// /tmp/arcus-compd/ (one sheet per category, 20 to a sheet, every type of each family), for checking them by eye; the test
/// checks each type draws.
@Suite("COMPD renders")
struct COMPDRenderTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-compd")
    static let (w, h, label) = (300, 225, 34)

    /// Full-length items are drawn 8" long so their section reads.
    static func preview(_ d: ComponentDefinition, _ t: ComponentType) -> CGImage? {
        var inst: [String: ParamValue] = [:]
        if d.parameter(named: "Length")?.isInstance == true { inst["Length"] = .double(0.2) }
        if d.parameter(named: "Panel Height")?.isInstance == true { inst["Panel Height"] = .double(0.12) }
        let ev = FamilyEvaluator.evaluate(d.family, typeName: t.name, instance: inst)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var colors: [String: RGBColor] = [:]
        for s in d.materials { colors[s.name] = s.finish.color }
        ShadedFamilyRenderer.draw(ev, colors: colors, fallback: RGBColor(hex: 0x9EA3A8), ctx, width: w, height: h)
        return ctx.makeImage()
    }

    static func text(_ s: String, _ ctx: CGContext, x: Double, y: Double, size: Double, bold: Bool = false) {
        let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
        let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                              NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.1, alpha: 1)])
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(attr), ctx)
    }

    static func sheet(_ items: [(String, String, CGImage)], cols: Int, url: URL) throws {
        let rows = (items.count + cols - 1) / cols
        let W = cols * w, H = rows * (h + label)
        let ctx = try #require(CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        for (i, (title, sub, img)) in items.enumerated() {
            let c = i % cols, r = i / cols
            let y = H - (r + 1) * (h + label)
            ctx.draw(img, in: CGRect(x: c * w, y: y, width: w, height: h))
            ctx.setStrokeColor(CGColor(gray: 0.82, alpha: 1)); ctx.stroke(CGRect(x: c * w, y: y, width: w, height: h + label))
            text(title, ctx, x: Double(c * w + 6), y: Double(y + h + 18), size: 12, bold: true)
            text(sub, ctx, x: Double(c * w + 6), y: Double(y + h + 5), size: 10)
        }
        let img = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, img, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    @Test func everyTypeDrawsOnItsCategorySheet() throws {
        try FileManager.default.createDirectory(at: Self.dir, withIntermediateDirectories: true)
        let defs = ComponentLibrary.groupD
        // COMPD_CATS=17,18 limits the run to some categories (for quick checks).
        let only = ProcessInfo.processInfo.environment["COMPD_CATS"].map { Set($0.split(separator: ",").compactMap { Int($0) }) }
        for cat in [ComponentCategory.lighting, .glass, .edges, .motion, .decorative] where only?.contains(cat.rawValue) ?? true {
            var items: [(String, String, CGImage)] = []
            for d in defs where d.category == cat {
                for t in d.types {
                    let img = try #require(Self.preview(d, t), "\(d.name) / \(t.name) draws")
                    items.append((d.name, t.name, img))
                }
            }
            for (k, start) in stride(from: 0, to: items.count, by: 20).enumerated() {
                try Self.sheet(Array(items[start..<min(items.count, start + 20)]), cols: 5, url: Self.dir.appendingPathComponent("\(cat.code)-\(k + 1).png"))
            }
        }
    }
}
