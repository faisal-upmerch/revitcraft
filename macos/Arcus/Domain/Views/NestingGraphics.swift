import Foundation
import ArcusGeometry

// FM7: the graphics of a Nesting view (Docs/FurnitureMode.md §3 "Nesting"): every stock sheet its material and
// thickness needs, drawn at full size side by side, each part outlined and labelled with its Mark and size, grain
// arrows on parts with grain, offcuts hatched and the yield under each sheet. Parts are selectable (they select the
// part, or the front a derived piece belongs to). The view's element carries the group it shows
// (`FurnitureNestingViews.groupParam`).

/// Where a nesting group's sheets go in its view.
public struct NestingLayout: Sendable {
    /// Lower-left corner of each sheet.
    public var origins: [Vec2]
    /// The whole drawing (sheets, titles and labels).
    public var bounds: Rect2

    static let inch = 0.0254
    /// Sheets per row.
    public static let columns = 3

    /// The layout of `group`'s sheets: rows of up to three, 8" apart, with room for titles at `scale`.
    public init(_ group: NestingGroup?, scale: Int) {
        let size = group.map { Vec2($0.size.length, $0.size.width) } ?? Vec2(96 * Self.inch, 48 * Self.inch)
        let n = max(1, group?.result.sheets.count ?? 0)
        let gapX = 8 * Self.inch, gapY = 0.012 * Double(scale) + 4 * Self.inch
        origins = (0..<n).map { i in
            let r = i / Self.columns, c = i % Self.columns
            return Vec2(Double(c) * (size.x + gapX), -Double(r) * (size.y + gapY))
        }
        let cols = min(n, Self.columns), rows = (n + Self.columns - 1) / Self.columns
        let w = Double(cols) * size.x + Double(cols - 1) * gapX
        let bottom = -Double(rows - 1) * (size.y + gapY) - 0.009 * Double(scale)
        bounds = Rect2(min: Vec2(0, bottom), max: Vec2(w, size.y + 0.014 * Double(scale)))
    }
}

extension ViewGraphicsBuilder {
    /// The Nesting view's sheets, parts, offcuts and titles.
    func nestingGraphics() -> [GItem] {
        guard model.isFurniture else { return [] }
        let key = view.params[FurnitureNestingViews.groupParam]?.textValue
        let groups = FurnitureFabrication.nesting(model)
        guard let group = groups.first(where: { $0.key == key }) else {
            return [GItem(elementID: nil, category: .views, layer: .annotation,
                          primitives: [.text(GText(position: .zero, height: 0.0025, string: "No parts of this material and thickness.", color: RGBColor(0.4, 0.4, 0.4)))],
                          selectable: false)]
        }
        let parts = Dictionary(FurnitureFabrication.parts(model).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let layout = NestingLayout(group, scale: scale)
        let ink = RGBColor(0.15, 0.15, 0.15), muted = RGBColor(0.42, 0.42, 0.42)
        let hatch = GFill(pattern: .diagonalUp, color: RGBColor(0.55, 0.55, 0.55), background: RGBColor(0.96, 0.96, 0.96))
        let partFill = GFill(pattern: .solid, color: RGBColor(0.98, 0.94, 0.86))
        var items: [GItem] = []
        let total = group.result.sheets.count
        // The group's title over the first row.
        let partCount = group.result.sheets.reduce(0) { $0 + $1.placements.count }
        let title = "\(group.title)  ·  \(total) \(total == 1 ? "sheet" : "sheets") of \(group.size.name)  ·  \(partCount) parts  ·  Yield \(Self.percent(group.result.yield))"
        items.append(GItem(elementID: nil, category: .views, layer: .annotation,
                           primitives: [.text(GText(position: Vec2(0, group.size.width + paper(0.006)), height: 0.0032, string: title, bold: true, color: ink))],
                           selectable: false))
        for (i, sheet) in group.result.sheets.enumerated() {
            let o = layout.origins[i]
            let s = sheet.stock
            func rect(_ r: Rect2) -> [Vec2] { r.corners.map { $0 + o } }
            let outline = Rect2(min: .zero, max: Vec2(s.length, s.width))
            // Offcuts first, then the trim line, the parts and the sheet outline.
            let off = sheet.offcuts.map { Polygon2(rect($0)) }
            if !off.isEmpty { items.append(GItem(elementID: nil, category: .views, layer: .fills, primitives: [.fill(off, hatch)], selectable: false)) }
            var deco: [GPrimitive] = [.polyline(rect(outline), closed: true, GStroke(weight: 4, color: ink))]
            if s.trim > 1e-6 {
                deco.append(.polyline(rect(outline.expanded(by: -s.trim)), closed: true, GStroke(weight: 1, color: muted, pattern: .dash)))
            }
            if s.grain != .none {
                // The sheet's grain, at its lower-left corner.
                let a = o + Vec2(paper(0.004), paper(0.004))
                let d = s.grain == .length ? Vec2(1, 0) : Vec2(0, 1)
                deco += arrow(a, a + d * paper(0.012), GStroke(weight: 1, color: muted))
            }
            items.append(GItem(elementID: nil, category: .views, layer: .model, primitives: deco, selectable: false))
            for p in sheet.placements {
                let part = group.partKeys[p.key].flatMap { parts[$0] }
                let r = rect(p.rect)
                var prims: [GPrimitive] = [.fill([Polygon2(r)], partFill), .polyline(r, closed: true, GStroke(weight: 2, color: ink))]
                let c = p.rect.center + o
                let upright = p.rect.height > p.rect.width * 1.4
                let rot = upright ? Double.pi / 2 : 0
                let size = part.map { "\(FurnitureSizeText.inches($0.length)) x \(FurnitureSizeText.inches($0.width))" } ?? ""
                let n = upright ? Vec2(1, 0) : Vec2(0, 1)
                prims.append(.text(GText(position: c + n * paper(0.0006), height: 0.0022, string: p.label, rotation: rot, alignment: .center, verticalAnchor: 0, bold: true, color: ink)))
                prims.append(.text(GText(position: c - n * paper(0.0006), height: 0.0016, string: size, rotation: rot, alignment: .center, verticalAnchor: 1, color: muted)))
                if p.grain != .none {
                    let alongX = (p.grain == .length) != p.rotated
                    let d = alongX ? Vec2(1, 0) : Vec2(0, 1)
                    let half = (alongX ? p.rect.width : p.rect.height) * 0.3
                    let at = c - (upright ? Vec2(1, 0) : Vec2(0, 1)) * paper(0.0045)
                    prims += arrow(at - d * half, at + d * half, GStroke(weight: 1, color: muted))
                }
                items.append(GItem(elementID: part?.elementID, category: part.flatMap { model[$0.elementID]?.category } ?? .views, layer: .model,
                                   primitives: prims, hitPolygons: [Polygon2(r)]))
            }
            let caption = "Sheet \(i + 1) of \(total)  ·  \(FurnitureSizeText.inches(s.length)) x \(FurnitureSizeText.inches(s.width))  ·  Yield \(Self.percent(sheet.yield))"
            items.append(GItem(elementID: nil, category: .views, layer: .annotation,
                               primitives: [.text(GText(position: o + Vec2(0, -paper(0.004)), height: 0.0025, string: caption, verticalAnchor: 1, color: ink))],
                               selectable: false))
        }
        if !group.result.oversize.isEmpty {
            let list = group.result.oversize.map { "\($0.label) (\(FurnitureSizeText.inches($0.length)) x \(FurnitureSizeText.inches($0.width)))" }
            let text = "Too large for \(group.size.name): " + list.joined(separator: ", ")
            items.append(GItem(elementID: nil, category: .views, layer: .annotation,
                               primitives: [.text(GText(position: Vec2(0, layout.bounds.min.y - paper(0.004)), height: 0.0025, string: text, verticalAnchor: 1,
                                                        color: RGBColor(0.75, 0.1, 0.1)))],
                               selectable: false))
        }
        return items
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
}
