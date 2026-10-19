import AppKit
import Testing
import ArcusGeometry
@testable import ArcusDomain
import ArcusOutput

/// COMPA: every Group A component rendered offscreen (a shaded three-quarter view and a view of its mounting face, at
/// Fine, in its finishes' colours) to `/tmp/arcus-compa/`, one file per component and contact sheets of twelve, to check
/// by eye that each looks like the real item.
@Suite("COMPA component renders", .serialized)
struct COMPARenderTests {
    static let out = URL(fileURLWithPath: "/tmp/arcus-compa")

    /// One view of a definition's type.
    static func render(_ d: ComponentDefinition, type: String, yaw: Double, pitch: Double, width: Int, height: Int) -> CGImage? {
        var ev = FamilyEvaluator.evaluate(d.family, typeName: type)
        ev.solids = ev.solids.filter { !$0.isVoid && $0.visibleIn3D && $0.visibleAt.contains(.fine) }
        var colors: [String: ArcusDomain.RGBColor] = [:]
        for m in d.materials { colors[m.name] = m.finish.color }
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ShadedFamilyRenderer.draw(ev, colors: colors, fallback: ArcusDomain.RGBColor(hex: 0x9EA3A8), ctx, width: width, height: height, yaw: yaw, pitch: pitch)
        return ctx.makeImage()
    }

    /// The view that looks at the mounting face: front handles face -Y, face-based items +Z, plan items from the front.
    static func faceView(_ d: ComponentDefinition) -> (Double, Double) {
        switch d.frame {
        case .face: (0, Double.pi / 2 - 0.0001)
        default: (0, 0)
        }
    }

    static func write(_ img: CGImage, _ name: String) throws {
        try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    @Test func everyGroupAComponentRenders() throws {
        try? FileManager.default.createDirectory(at: Self.out, withIntermediateDirectories: true)
        let defs = GroupA.all
        let cw = 760, ch = 330
        var cells: [(String, CGImage)] = []
        for d in defs {
            let t = try #require(d.defaultType).name
            let (fy, fp) = Self.faceView(d)
            let a = try #require(Self.render(d, type: t, yaw: ShadedFamilyRenderer.yaw, pitch: ShadedFamilyRenderer.pitch, width: 380, height: 300), "\(d.name)")
            let b = try #require(Self.render(d, type: t, yaw: fy, pitch: fp, width: 380, height: 300), "\(d.name)")
            let ctx = try #require(CGContext(data: nil, width: cw, height: ch, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: cw, height: ch))
            ctx.draw(a, in: CGRect(x: 0, y: 26, width: 380, height: 300))
            ctx.draw(b, in: CGRect(x: 380, y: 26, width: 380, height: 300))
            ctx.setStrokeColor(CGColor(gray: 0.85, alpha: 1)); ctx.stroke(CGRect(x: 0.5, y: 0.5, width: CGFloat(cw - 1), height: CGFloat(ch - 1)))
            let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
            ("\(d.category.code) \(d.name) — \(t)" as NSString).draw(at: NSPoint(x: 8, y: 4), withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: NSColor.black])
            NSGraphicsContext.restoreGraphicsState()
            let cell = try #require(ctx.makeImage())
            try Self.write(cell, "\(d.category.code) \(d.name)".replacingOccurrences(of: "/", with: "-"))
            cells.append((d.name, cell))
        }
        // Contact sheets: 2 x 6 cells.
        let cols = 2, rows = 6
        for (page, start) in stride(from: 0, to: cells.count, by: cols * rows).enumerated() {
            let ctx = try #require(CGContext(data: nil, width: cols * cw, height: rows * ch, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: cols * cw, height: rows * ch))
            for (i, (_, img)) in cells[start..<min(cells.count, start + cols * rows)].enumerated() {
                ctx.draw(img, in: CGRect(x: CGFloat((i % cols) * cw), y: CGFloat((rows - 1 - i / cols) * ch), width: CGFloat(cw), height: CGFloat(ch)))
            }
            try Self.write(try #require(ctx.makeImage()), "_sheet \(String(format: "%02d", page + 1))")
        }
        #expect(cells.count == defs.count)
    }
}
