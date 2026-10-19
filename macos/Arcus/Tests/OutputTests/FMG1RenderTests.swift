import Foundation
import Testing
import CoreGraphics
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// FMG1: the library pieces that now flex fully, rendered as compiled families at each type and flexed (Width × 1.25,
/// Depth × 0.85, Height × 1.25), and their side elevations, to /tmp/arcus-fmg1/, for checking by eye that angled parts,
/// slats and revolves follow the planes. The test checks they draw.
@Suite("FMG1 renders")
struct FMG1RenderTests {
    static let dir = URL(fileURLWithPath: "/tmp/arcus-fmg1")

    static func shaded(_ f: FamilyDefinition, _ type: String, _ m: BIMModel, width: Int = 420, height: Int = 340) -> CGImage? {
        var ev = FamilyEvaluator.evaluate(f, typeName: type, units: .imperial)
        var colors: [String: RGBColor] = [:]
        ev.solids = ev.solids.filter { !$0.isVoid && $0.visibleIn3D && $0.visibleAt.contains(.medium) }.map { s in
            var s = s
            var id = s.resolvedMaterial
            if id == nil, let p = s.materialParameter, case .quantity(let raw, _)? = ev.values[p], raw >= 1 { id = ElementID(UInt64(raw)) }
            if let id, let mat = m[id]?.material { colors["#\(id.raw)"] = mat.color; s.materialParameter = "#\(id.raw)" } else { s.materialParameter = nil }
            return s
        }
        guard !ev.solids.isEmpty, let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ShadedFamilyRenderer.draw(ev, colors: colors, fallback: RGBColor(0.7, 0.6, 0.5, 1), ctx, width: width, height: height)
        return ctx.makeImage()
    }

    /// Images side by side in one PNG.
    static func strip(_ images: [CGImage], _ name: String) {
        let w = images.map(\.width).reduce(0, +), h = images.map(\.height).max() ?? 0
        guard w > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        var x = 0
        for i in images { ctx.draw(i, in: CGRect(x: x, y: 0, width: i.width, height: i.height)); x += i.width }
        guard let img = ctx.makeImage(), let png = FurniturePreview.pngData(img) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }

    static let pieces = ["Sun Lounger", "Hammock", "Hanging Chair", "Picnic Table", "Folding Chair", "Swing Bench", "Adirondack Chair",
                         "Folding Screen", "Ladder Shelf", "Decorative Console", "Decorative Bench"]

    @Test func flexedPiecesRender() throws {
        for name in Self.pieces {
            let m = try #require(SimpleB.pieces.first { $0.name == name }).make()
            let f = FurnitureCompiler.family(from: m)
            var images: [CGImage] = []
            for t in f.types { if let i = Self.shaded(f, t.name, m) { images.append(i) } }
            let t = f.types[0].name
            for (param, k) in [("Width", 1.25), ("Depth", 0.85), ("Height", 1.25)] {
                var g = f
                g.types[0].values[param] = .double((g.types[0].values[param]?.doubleValue ?? 0) * k)
                if let i = Self.shaded(g, t, m) { images.append(i) }
            }
            #expect(images.count == f.types.count + 3, "\(name) draws")
            Self.strip(images, "flex-\(name.replacingOccurrences(of: " ", with: "-"))")
            // The side (Right) elevation of the document, for the angled parts' 2D graphics.
            if let v = m.views.first(where: { $0.name == "Right" }) {
                let g = ViewGraphicsBuilder(model: m, view: v).build()
                if let img = RasterExporter.render(g, pixelWidth: 700), let png = RasterExporter.encode(img, as: .png) {
                    try? png.write(to: Self.dir.appendingPathComponent("right-\(name.replacingOccurrences(of: " ", with: "-")).png"))
                }
            }
        }
    }
}
