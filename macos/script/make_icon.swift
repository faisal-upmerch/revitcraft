// Renders Arcus's original app icon — a stone arch (Latin "arcus") with a golden keystone on a blueprint-blue
// drafting field — into an .icns and a 1024 px PNG.
// Usage: swift script/make_icon.swift <output-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Arcus/Resources/Icon")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let cs = CGColorSpace(name: CGColorSpace.displayP3)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: cs, components: [r, g, b, a])! }
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: colors as CFArray, locations: locations)!
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    let small = px <= 32 // 16/32 px: drop the fine detail that would turn to mush

    // macOS icon grid: an 824/1024 body with a continuous-corner squircle.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.2237
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.034, color: CGColor(gray: 0, alpha: 0.38))
    ctx.addPath(squircle); ctx.setFillColor(rgb(0.08, 0.13, 0.28)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(squircle); ctx.clip()

    // Blueprint field: deep indigo-blue, lighter at the top, with a soft glow behind the arch.
    ctx.drawLinearGradient(gradient([rgb(0.20, 0.36, 0.78), rgb(0.10, 0.18, 0.46), rgb(0.05, 0.09, 0.25)], [0, 0.55, 1]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    let glowCenter = CGPoint(x: body.midX, y: body.minY + body.height * 0.52)
    ctx.drawRadialGradient(gradient([rgb(0.45, 0.66, 1.0, 0.38), rgb(0.45, 0.66, 1.0, 0)]),
                           startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: body.width * 0.55, options: [])

    // Drafting grid.
    if !small {
        let step = body.width / 12
        ctx.setLineWidth(max(1, s / 700))
        for i in 1..<12 {
            let major = i % 3 == 0
            ctx.setStrokeColor(rgb(0.75, 0.86, 1, major ? 0.10 : 0.05))
            let x = body.minX + CGFloat(i) * step, y = body.minY + CGFloat(i) * step
            ctx.move(to: CGPoint(x: x, y: body.minY)); ctx.addLine(to: CGPoint(x: x, y: body.maxY))
            ctx.move(to: CGPoint(x: body.minX, y: y)); ctx.addLine(to: CGPoint(x: body.maxX, y: y))
            ctx.strokePath()
        }
    }

    // Arch geometry: a semicircular arch springing from two piers, standing on a base line.
    let c = CGPoint(x: body.midX, y: body.minY + body.height * 0.46)     // centre of the arch = springing line
    let rIn = body.width * 0.205, rOut = body.width * 0.335
    let pierW = rOut - rIn, baseY = body.minY + body.height * 0.20

    // Construction circle continuing the intrados below the springing line (dashed, like a setting-out line).
    if !small {
        ctx.saveGState()
        ctx.setStrokeColor(rgb(0.72, 0.85, 1, 0.45))
        ctx.setLineWidth(max(1, s / 340))
        ctx.setLineDash(phase: 0, lengths: [s / 70, s / 110])
        ctx.addArc(center: c, radius: rIn - s * 0.004, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        ctx.strokePath()
        // Centre mark.
        ctx.setLineDash(phase: 0, lengths: [])
        let m = s * 0.018
        ctx.move(to: CGPoint(x: c.x - m, y: c.y)); ctx.addLine(to: CGPoint(x: c.x + m, y: c.y))
        ctx.move(to: CGPoint(x: c.x, y: c.y - m)); ctx.addLine(to: CGPoint(x: c.x, y: c.y + m))
        ctx.strokePath()
        ctx.restoreGState()
    }

    let stone = gradient([rgb(1, 1, 1), rgb(0.86, 0.89, 0.95)])
    let key = gradient([rgb(1.0, 0.84, 0.42), rgb(0.95, 0.60, 0.20)])
    let gap = small ? 0 : s * 0.006

    // Shadow cast by the arch onto the field.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.014), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)

    // Voussoirs: nine blocks across the half circle; the middle one is the keystone, a little taller.
    let count = 9
    for i in 0..<count {
        let a0 = CGFloat.pi - CGFloat(i) * .pi / CGFloat(count)
        let a1 = CGFloat.pi - CGFloat(i + 1) * .pi / CGFloat(count)
        let isKey = i == count / 2
        let outer = isKey ? rOut + body.width * 0.035 : rOut
        let dA = gap / rIn
        let path = CGMutablePath()
        path.addArc(center: c, radius: outer, startAngle: a0 - dA, endAngle: a1 + dA, clockwise: true)
        path.addArc(center: c, radius: rIn, startAngle: a1 + dA, endAngle: a0 - dA, clockwise: false)
        path.closeSubpath()
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let bb = path.boundingBoxOfPath
        ctx.drawLinearGradient(isKey ? key : stone, start: CGPoint(x: bb.minX, y: bb.maxY), end: CGPoint(x: bb.maxX, y: bb.minY), options: [])
        ctx.restoreGState()
    }

    // Piers from the springing line down to the base.
    for x0 in [c.x - rOut, c.x + rIn] {
        let pier = CGRect(x: x0, y: baseY, width: pierW, height: c.y - baseY - gap)
        ctx.saveGState()
        ctx.addRect(pier); ctx.clip()
        ctx.drawLinearGradient(stone, start: CGPoint(x: pier.minX, y: pier.maxY), end: CGPoint(x: pier.maxX, y: pier.minY), options: [])
        ctx.restoreGState()
    }
    // Impost blocks where the arch springs, slightly wider than the piers.
    if !small {
        for x0 in [c.x - rOut, c.x + rIn] {
            let impost = CGRect(x: x0 - s * 0.012, y: c.y - gap - s * 0.035, width: pierW + s * 0.024, height: s * 0.035)
            ctx.setFillColor(rgb(0.93, 0.95, 0.99)); ctx.fill(impost)
        }
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // Ground line the piers stand on.
    let ground = CGRect(x: c.x - rOut - s * 0.05, y: baseY - s * 0.022, width: 2 * rOut + s * 0.10, height: s * 0.022)
    ctx.setFillColor(rgb(0.78, 0.86, 1, 0.9)); ctx.fill(ground)

    // Glass: a soft highlight across the top of the tile.
    ctx.drawLinearGradient(gradient([rgb(1, 1, 1, 0.16), rgb(1, 1, 1, 0)]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.maxY - body.height * 0.42), options: [])
    ctx.restoreGState()

    // Specular rim.
    ctx.addPath(squircle); ctx.setStrokeColor(rgb(1, 1, 1, 0.16)); ctx.setLineWidth(max(1, s / 256)); ctx.strokePath()

    let img = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
}

let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
try render(1024).write(to: out.appendingPathComponent("AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try p.run(); p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("Icon written to \(out.path)")
