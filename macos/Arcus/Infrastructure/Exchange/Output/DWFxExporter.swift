import Foundation
import ArcusGeometry
import ArcusDomain

// F13: File ▸ Export ▸ DWF/DWFx (port of RevitCraft rc-core dwfx.rs): sheets and views as a DWFx package — an OPC
// ZIP of XPS fixed pages. Lines and fills are paths, hatches their lines, text Glyphs in Arial (embedded from this
// Mac's system fonts; text is left out, with a warning, when they're missing). Written locally; no SDK.

/// One page of a DWFx package: a display list in its own coordinates and the transform onto paper (meters).
public struct DWFxPage: Sendable {
    public var name: String
    /// Paper size (meters).
    public var paper: Vec2
    public var graphics: ViewGraphics
    /// Display-list coordinates → paper meters (origin at the lower-left corner).
    public var toPaper: Transform2
    /// Pictures on the page (schedule title and header images), with their paper boxes.
    public var images: [(box: Rect2, image: ScheduleImage)] = []
    public init(name: String, paper: Vec2, graphics: ViewGraphics, toPaper: Transform2) {
        self.name = name; self.paper = paper; self.graphics = graphics; self.toPaper = toPaper
    }
}

public enum DWFxExporter {
    /// XPS units (1/96 inch) per paper meter.
    static let px = 96.0 / 0.0254
    /// Cap height of Arial as a fraction of its em size.
    static let capRatio = 0.716

    /// A sheet at its paper size.
    public static func sheetPage(_ sheet: Element, model: BIMModel, viewGraphics: (@Sendable (Element) -> ViewGraphics?)? = nil) -> DWFxPage {
        let b = SheetGraphicsBuilder(model: model, sheet: sheet, includeGuides: false, viewGraphics: viewGraphics)
        let name = sheet.sheet.map { "\($0.number) - \(sheet.name)" } ?? sheet.name
        var page = DWFxPage(name: name, paper: b.paperSize, graphics: b.build(), toPaper: .identity)
        for (l, g) in b.layouts() where g == nil {
            guard let s = model[l.viewID], s.schedule != nil else { continue }
            page.images += ScheduleLayout.images(ScheduleEngine.compute(s, model), topLeft: Vec2(l.box.min.x, l.box.max.y), rows: model[l.viewportID]?.viewport?.scheduleRows)
        }
        return page
    }

    /// A view on a page sized to its content at its scale, plus a 10 mm margin (RevitCraft prints views this way).
    public static func viewPage(_ view: Element, graphics g: ViewGraphics) -> DWFxPage {
        let n = Double(max(g.scale, 1))
        let region = SheetGraphicsBuilder.viewRegion(g).expanded(by: 0.01 * n)
        let m = PDFExporter.viewMargin
        let paper = Vec2(region.width / n + 2 * m, region.height / n + 2 * m)
        let t = Transform2.translation(Vec2(m, m)) * Transform2.scale(1 / n, 1 / n) * Transform2.translation(-region.min)
        return DWFxPage(name: ViewTitles.qualified(view), paper: paper, graphics: g, toPaper: t)
    }

    /// A schedule (its whole table) on a page sized to it.
    public static func schedulePage(_ schedule: Element, model: BIMModel) -> DWFxPage {
        let t = ScheduleEngine.compute(schedule, model)
        let m = PDFExporter.viewMargin
        let size = Vec2(t.totalWidth + 2 * m, ScheduleLayout.height(t) + 2 * m)
        let prims = ScheduleLayout.primitives(t, topLeft: Vec2(m, size.y - m))
        let g = ViewGraphics(viewID: schedule.id, scale: 1, items: [GItem(elementID: schedule.id, category: .schedules, layer: .annotation, primitives: prims)],
                             extents: Rect2(min: .zero, max: size), crop: nil, modelRevision: model.revision)
        var page = DWFxPage(name: schedule.name, paper: size, graphics: g, toPaper: .identity)
        page.images = ScheduleLayout.images(t, topLeft: Vec2(m, size.y - m))
        return page
    }

    /// Arial regular and bold from the system fonts (nil when missing).
    public static func systemFonts() -> (regular: Data?, bold: Data?) {
        let dir = URL(fileURLWithPath: "/System/Library/Fonts/Supplemental")
        return (try? Data(contentsOf: dir.appendingPathComponent("Arial.ttf")), try? Data(contentsOf: dir.appendingPathComponent("Arial Bold.ttf")))
    }

    /// The package and any warnings (text left out without fonts).
    public static func write(_ pages: [DWFxPage], fonts: (regular: Data?, bold: Data?)) -> (data: Data, warnings: [String]) {
        var files: [(name: String, data: Data)] = []
        var images: [(name: String, data: Data)] = []
        var warnings: [String] = []
        let boldURI = fonts.bold != nil ? "/Resources/arialbd.ttf" : "/Resources/arial.ttf"
        var doc = #"<FixedDocument xmlns="http://schemas.microsoft.com/xps/2005/06">"#
        var used = Set<String>()
        var droppedText = false
        for (k, page) in pages.enumerated() {
            var name = safe(page.name, k)
            while !used.insert(name).inserted { name += "_\(k + 1)" }
            let w = page.paper.x * px, h = page.paper.y * px
            var body = #"<FixedPage xmlns="http://schemas.microsoft.com/xps/2005/06" Width="\#(n(w))" Height="\#(n(h))" xml:lang="en-US">"#
            body += "<Canvas Name=\"Sheet\"><Path Fill=\"#FFFFFFFF\" Data=\"M 0,0 L \(n(w)),0 \(n(w)),\(n(h)) 0,\(n(h)) Z\" />"
            var resources: [String] = []
            let t = page.toPaper
            func at(_ q: Vec2) -> String { let p = t.apply(q); return "\(n(p.x * px)),\(n(h - p.y * px))" }
            let pageScale = t.uniformScale
            for item in page.graphics.items.sorted(by: { $0.layer < $1.layer }) {
                let lineScale = item.lineScale ?? page.graphics.scale
                for prim in item.primitives {
                    switch prim {
                    case .polyline(let pts, let closed, let s):
                        body += stroke(pts, closed: closed, s, scale: lineScale, at: at)
                    case .arc(let a, let s):
                        body += stroke(a.tessellate(chordTolerance: 0.0005 / max(pageScale, 1e-9)), closed: false, s, scale: lineScale, at: at)
                    case .fill(let polys, let f):
                        body += fill(polys, f, scale: page.graphics.scale, unitsPerPaper: pageScale, at: at)
                    case .text(let g):
                        guard fonts.regular != nil else { if !g.string.trimmingCharacters(in: .whitespaces).isEmpty { droppedText = true }; continue }
                        let uri = g.bold ? boldURI : "/Resources/arial.ttf"
                        let s = glyphs(g, t: t, h: h, uri: uri, simulateBold: g.bold && fonts.bold == nil)
                        if !s.isEmpty { body += s; if !resources.contains(uri) { resources.append(uri) } }
                    }
                }
            }
            for (box, img) in page.images {
                let file = "/Resources/image\(images.count + 1).png"
                images.append((String(file.dropFirst()), img.png))
                let x0 = box.min.x * px, y0 = h - box.max.y * px, x1 = box.max.x * px, y1 = h - box.min.y * px
                body += #"<Path Data="M \#(n(x0)),\#(n(y0)) L \#(n(x1)),\#(n(y0)) \#(n(x1)),\#(n(y1)) \#(n(x0)),\#(n(y1)) Z"><Path.Fill><ImageBrush ImageSource="\#(file)" Viewbox="0,0,\#(img.pixelWidth),\#(img.pixelHeight)" ViewboxUnits="Absolute" Viewport="\#(n(x0)),\#(n(y0)),\#(n(x1 - x0)),\#(n(y1 - y0))" ViewportUnits="Absolute" TileMode="None" /></Path.Fill></Path>"#
                resources.append(file)
            }
            body += "</Canvas></FixedPage>"
            files.append(("Documents/1/Pages/\(name).fpage", Data(body.utf8)))
            if !resources.isEmpty {
                var rels = #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
                for (i, r) in resources.enumerated() {
                    rels += #"<Relationship Id="R\#(i)" Type="http://schemas.microsoft.com/xps/2005/06/required-resource" Target="\#(r)" />"#
                }
                rels += "</Relationships>"
                files.append(("Documents/1/Pages/_rels/\(name).fpage.rels", Data(rels.utf8)))
            }
            doc += #"<PageContent Source="/Documents/1/Pages/\#(name).fpage" Width="\#(n(w))" Height="\#(n(h))" />"#
        }
        doc += "</FixedDocument>"
        if droppedText { warnings.append("Arial wasn't found in the system fonts, so the DWFx has no text.") }
        var out: [(name: String, data: Data)] = [
            ("[Content_Types].xml", Data(#"<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml" /><Default Extension="fdseq" ContentType="application/vnd.ms-package.xps-fixeddocumentsequence+xml" /><Default Extension="fdoc" ContentType="application/vnd.ms-package.xps-fixeddocument+xml" /><Default Extension="fpage" ContentType="application/vnd.ms-package.xps-fixedpage+xml" /><Default Extension="png" ContentType="image/png" /><Default Extension="ttf" ContentType="application/vnd.ms-opentype" /></Types>"#.utf8)),
            ("_rels/.rels", Data(#"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="R0" Type="http://schemas.microsoft.com/xps/2005/06/fixedrepresentation" Target="/FixedDocumentSequence.fdseq" /></Relationships>"#.utf8)),
            ("FixedDocumentSequence.fdseq", Data(#"<FixedDocumentSequence xmlns="http://schemas.microsoft.com/xps/2005/06"><DocumentReference Source="/Documents/1/FixedDocument.fdoc" /></FixedDocumentSequence>"#.utf8)),
            ("Documents/1/FixedDocument.fdoc", Data(doc.utf8)),
        ]
        out += files
        out += images
        if let r = fonts.regular { out.append(("Resources/arial.ttf", r)) }
        if let b = fonts.bold { out.append(("Resources/arialbd.ttf", b)) }
        return (ZipArchive.write(out), warnings)
    }

    // MARK: Primitives

    static func stroke(_ pts: [Vec2], closed: Bool, _ s: GStroke, scale: Int, at: (Vec2) -> String) -> String {
        guard pts.count >= 2 else { return "" }
        var d = "M " + at(pts[0]) + " L " + pts.dropFirst().map(at).joined(separator: " ")
        if closed { d += " Z" }
        let width = max(0.5, LineWeights.paperWidth(s.weight, scale: max(scale, 1)) / 1000 * px)
        let dashes = s.pattern.dashPattern.map { max(0.1, $0 / 1000 * px / width) }
        let dash = dashes.isEmpty ? "" : #" StrokeDashArray="\#(dashes.map(n).joined(separator: " "))""#
        let color = s.halftone ? s.color.mixed(with: .white, amount: 0.55) : s.color
        return #"<Path Stroke="\#(hex(color))" StrokeThickness="\#(n(width))"\#(dash) StrokeLineJoin="Round" Data="\#(d)" />"#
    }

    static func figures(_ polys: [Polygon2], at: (Vec2) -> String) -> String {
        polys.filter { $0.points.count >= 3 }.map { p in "M " + at(p.points[0]) + " L " + p.points.dropFirst().map(at).joined(separator: " ") + " Z" }.joined(separator: " ")
    }

    static func fill(_ polys: [Polygon2], _ f: GFill, scale: Int, unitsPerPaper: Double, at: (Vec2) -> String) -> String {
        let d = figures(polys, at: at)
        guard !d.isEmpty, f.transparency < 0.999 else { return "" }
        let alpha = max(0, min(1, 1 - f.transparency))
        var out = ""
        if let bg = f.background { out += #"<Path Fill="\#(hex(bg, alpha: alpha))" Data="F0 \#(d)" />"# }
        let color = f.halftone ? f.color.mixed(with: .white, amount: 0.55) : f.color
        if f.pattern == .solid { return out + #"<Path Fill="\#(hex(color, alpha: alpha))" Data="F0 \#(d)" />"# }
        if let h = f.hatch, let lines = HatchGenerator.generate(polys, h, scale: max(scale, 1), budget: 20_000), !lines.isEmpty {
            let segs = lines.segments.map { "M " + at($0.start) + " L " + at($0.end) }.joined(separator: " ")
            let width = max(0.4, LineWeights.paperWidth(1, scale: max(scale, 1)) / 1000 * px)
            return out + #"<Path Stroke="\#(hex(color, alpha: alpha))" StrokeThickness="\#(n(width))" Data="\#(segs)" />"#
        }
        // Procedural patterns print as a light tint of their colour.
        return out + #"<Path Fill="\#(hex(color.mixed(with: .white, amount: 0.8), alpha: alpha))" Data="F0 \#(d)" />"#
    }

    static func glyphs(_ g: GText, t: Transform2, h: Double, uri: String, simulateBold: Bool) -> String {
        let lines = g.string.components(separatedBy: "\n")
        guard lines.contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return "" }
        let s = t.uniformScale
        let cap = g.height * s
        let em = cap / capRatio
        let angle = g.rotation + t.rotationAngle
        let (c, sn) = (cos(angle), sin(angle))
        let lineGap = cap * 1.7
        let color = g.halftone ? g.color.mixed(with: .white, amount: 0.55) : g.color
        var out = ""
        let origin = t.apply(g.position)
        for (i, line) in lines.enumerated() where !line.isEmpty {
            let width = TextMetrics.lineWidth(line, height: cap, bold: g.bold)
            let dx: Double = g.alignment == .center ? -width / 2 : (g.alignment == .right ? -width : 0)
            // Baseline of the first line: the anchor is 0 at the baseline, 1 at the top of the block.
            let blockTop = cap + Double(lines.count - 1) * lineGap
            let dy = -g.verticalAnchor * blockTop + (blockTop - cap) - Double(i) * lineGap
            let p = Vec2(origin.x + c * dx - sn * dy, origin.y + sn * dx + c * dy)
            let ox = p.x * px, oy = h - p.y * px
            let rot = abs(angle) > 1e-6 ? #" RenderTransform="\#(n(c)),\#(n(-sn)),\#(n(sn)),\#(n(c)),\#(n(ox)),\#(n(oy))""# : ""
            let (x, y) = rot.isEmpty ? (ox, oy) : (0, 0)
            let text = line.hasPrefix("{") ? "{}" + esc(line) : esc(line)
            out += #"<Glyphs Fill="\#(hex(color))" FontUri="\#(uri)" FontRenderingEmSize="\#(n(em * px))" StyleSimulations="\#(simulateBold ? "BoldSimulation" : (g.italic ? "ItalicSimulation" : "None"))" OriginX="\#(n(x))" OriginY="\#(n(y))"\#(rot) UnicodeString="\#(text)" />"#
        }
        return out
    }

    // MARK: Helpers

    static func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func n(_ v: Double) -> String {
        guard v.isFinite else { return "0" }
        var s = String(format: "%.2f", v)
        while s.contains("."), s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s == "-0" ? "0" : s
    }

    static func hex(_ c: RGBColor, alpha: Double = 1) -> String {
        func b(_ v: Double) -> String { String(format: "%02X", Int((max(0, min(1, v)) * 255).rounded())) }
        return "#" + b(c.a * alpha) + b(c.r) + b(c.g) + b(c.b)
    }

    /// A page file name: letters, digits, '-' and '_' only.
    static func safe(_ name: String, _ k: Int) -> String {
        let s = String(name.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") ? $0 : "_" }).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return s.isEmpty ? "Page\(k + 1)" : s
    }
}
