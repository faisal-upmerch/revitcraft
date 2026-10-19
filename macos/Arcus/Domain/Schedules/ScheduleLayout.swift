import Foundation
import ArcusGeometry

// BL-SCHED: schedules as vector primitives on sheets and in PDF. F12: laid out as a grid of cells (RevitCraft rc-core
// schedule.rs `layout`) so header rows, merged cells, cell Shading/Font/Borders/alignment, images and Split & Place
// segments print as they show.

/// The rows of a schedule a sheet viewport shows (Split & Place), as indices into the computed table's rows.
public struct ScheduleRowRange: Hashable, Codable, Sendable {
    public var first: Int
    public var last: Int
    public init(first: Int, last: Int) { self.first = min(first, last); self.last = max(first, last) }
    public func contains(_ i: Int) -> Bool { i >= first && i <= last }
}

/// One cell of a laid-out schedule.
public struct ScheduleGridCell: Sendable {
    public var key: ScheduleCellKey?
    public var text: String
    /// First column and number of columns and rows covered.
    public var column: Int
    public var span: Int
    public var rowSpan: Int
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    /// Text height on paper (meters).
    public var size: Double
    public var color: RGBColor
    public var shading: RGBColor?
    /// Edge borders: top, right, bottom, left.
    public var edges: [ScheduleBorder]
    public var horizontal: HorizontalAlign
    public var vertical: ScheduleVerticalAlign
    public var image: ScheduleImage?
}

/// One row of a laid-out schedule.
public struct ScheduleGridRow: Sendable {
    public enum Kind: Sendable, Equatable { case title, headerRow(Int), groups, headings, blank, body(Int) }
    public var kind: Kind
    public var height: Double
    public var cells: [ScheduleGridCell]
}

/// A schedule laid out on paper: column widths and rows of cells (meters).
public struct ScheduleGrid: Sendable {
    public var widths: [Double]
    public var rows: [ScheduleGridRow]
    public var width: Double { widths.reduce(0, +) }
    public var height: Double { rows.reduce(0) { $0 + $1.height } }
}

/// Lays out schedule tables as vector primitives (paper meters) for sheets and PDF.
public enum ScheduleLayout {
    public static let rowHeight = 0.0055
    public static let titleHeight = 0.008
    public static let textHeight = 0.0022

    /// Height on paper of a laid-out table: title band, header rows, header group row, header row, optional blank row
    /// and rows (of `rows` when the viewport shows a segment). // BL-SCHED, F12
    public static func height(_ t: ScheduleTable, rows: ScheduleRowRange? = nil) -> Double { grid(t, rows: rows).height }

    /// The grid of a table. A segment after the first repeats the headings but not the title or the header rows.
    public static func grid(_ t: ScheduleTable, rows segment: ScheduleRowRange? = nil) -> ScheduleGrid {
        let ap = t.appearance, fm = t.formatting
        let n = max(1, t.columns.count)
        let fitted = fit(t) // POLISH: columns as wide as their headings (on up to two lines) and their contents
        let widths = t.columns.isEmpty ? [0.04] : fitted.widths
        let thin: ScheduleBorder = ap.gridLines ? .thin : .none
        let heavy: ScheduleBorder = ap.outline ? .wide : thin
        func cell(_ key: ScheduleCellKey?, _ text: String, column: Int, span: Int = 1, bold: Bool, size: Double, align: HorizontalAlign,
                  edges: [ScheduleBorder]? = nil, shading: RGBColor? = nil) -> ScheduleGridCell {
            let st = key.map { fm.style($0) } ?? ScheduleCellStyle()
            let e = st.edges ?? st.border.map { [$0, $0, $0, $0] } ?? edges ?? [thin, thin, thin, thin]
            return ScheduleGridCell(key: key, text: text, column: column, span: span, rowSpan: 1, bold: st.font?.bold ?? bold, italic: st.font?.italic ?? false,
                                    underline: st.font?.underline ?? false, size: st.font?.size ?? size, color: st.font?.color ?? .black,
                                    shading: st.shading ?? shading, edges: e, horizontal: st.horizontal ?? align, vertical: st.vertical ?? .middle, image: nil)
        }
        let first = segment.map { $0.first <= 0 } ?? true
        var rows: [ScheduleGridRow] = []
        if t.showTitle && first {
            var c = cell(.title, fm.titleImage == nil ? t.title.uppercased() : "", column: 0, span: n, bold: ap.boldTitle, size: ap.titleTextHeight, align: .center,
                         edges: [.none, .none, heavy, .none])
            c.image = fm.titleImage
            rows.append(ScheduleGridRow(kind: .title, height: fm.titleHeight ?? titleHeight, cells: [c]))
        }
        if first {
            for (r, hr) in fm.headerRows.enumerated() {
                var cells: [ScheduleGridCell] = []
                var ci = 0
                while ci < n {
                    let span = hr.span(at: ci, columns: n)
                    var c = cell(.headerRow(r, ci), hr.text(ci), column: ci, span: span, bold: false, size: ap.bodyTextHeight, align: .center)
                    c.image = hr.images[ci]
                    if c.image != nil { c.text = "" }
                    cells.append(c)
                    ci += span
                }
                rows.append(ScheduleGridRow(kind: .headerRow(r), height: hr.height ?? rowHeight, cells: cells))
            }
        }
        if t.showHeaders {
            let spans = t.headerSpans
            let bottom: [ScheduleBorder] = [thin, thin, heavy, thin]
            if !spans.isEmpty {
                var cells: [ScheduleGridCell] = []
                var ci = 0
                while ci < n {
                    if let sp = spans.first(where: { $0.columns.lowerBound == ci }) {
                        cells.append(cell(.group(sp.groupID), sp.title, column: ci, span: sp.columns.count, bold: ap.boldHeaders, size: ap.headerTextHeight,
                                          align: .center, shading: ap.headerShading))
                        ci = sp.columns.upperBound
                    } else {
                        // Outside a group the heading spans both header rows, as in RevitCraft.
                        let f = ci < t.columns.count ? t.columns[ci] : nil
                        var c = cell(f.map { .heading($0.id) }, ci < fitted.headings.count ? fitted.headings[ci] : "", column: ci, bold: ap.boldHeaders, size: ap.headerTextHeight, align: .center,
                                     edges: bottom, shading: ap.headerShading)
                        c.rowSpan = 2
                        cells.append(c)
                        ci += 1
                    }
                }
                rows.append(ScheduleGridRow(kind: .groups, height: rowHeight, cells: cells))
            }
            var cells: [ScheduleGridCell] = []
            for (i, f) in t.columns.enumerated() where spans.isEmpty || spans.contains(where: { $0.columns.contains(i) }) {
                cells.append(cell(.heading(f.id), fitted.headings[i], column: i, bold: ap.boldHeaders, size: ap.headerTextHeight, align: .center, edges: bottom, shading: ap.headerShading))
            }
            rows.append(ScheduleGridRow(kind: .headings, height: fitted.headingHeight, cells: cells))
        }
        if ap.blankRowBeforeData { rows.append(ScheduleGridRow(kind: .blank, height: rowHeight, cells: [])) }
        for (ri, r) in t.rows.enumerated() where segment.map({ $0.contains(ri) }) ?? true {
            switch r.kind {
            case .blank:
                rows.append(ScheduleGridRow(kind: .body(ri), height: rowHeight, cells: []))
            case .groupHeader:
                rows.append(ScheduleGridRow(kind: .body(ri), height: rowHeight,
                                            cells: [cell(nil, r.title, column: 0, span: n, bold: true, size: ap.bodyTextHeight, align: .left)]))
            default:
                let strong = r.kind != .data
                let edges: [ScheduleBorder] = r.kind == .grandTotal ? [thin, thin, heavy, thin] : [thin, thin, thin, thin]
                var cells: [ScheduleGridCell] = []
                // POLISH: a total's title ("Plywood 3/4\": 12", "Grand total: 25") runs across the empty cells after it.
                let titleSpan = strong && !r.title.isEmpty ? Self.titleSpan(r, columns: t.columns.count) : 1
                for (i, f) in t.columns.enumerated() where i == 0 || i >= titleSpan {
                    var text = i < r.cells.count ? r.cells[i].text : ""
                    if i == 0, strong, !r.title.isEmpty { text = r.title }
                    let align = i < r.cells.count ? r.cells[i].alignment : f.alignment
                    var c = cell(.body(f.id), text, column: i, span: i == 0 ? titleSpan : 1, bold: strong, size: ap.bodyTextHeight,
                                 align: strong && i == 0 && !r.title.isEmpty ? .left : align, edges: edges)
                    if i < r.cells.count, let bg = r.cells[i].background { c.shading = bg }
                    cells.append(c)
                }
                rows.append(ScheduleGridRow(kind: .body(ri), height: rowHeight, cells: cells))
            }
        }
        return ScheduleGrid(widths: widths, rows: rows)
    }

    // MARK: Column fit (POLISH)

    /// Space between a cell's text and its borders (paper meters).
    static let cellPad = 0.0015
    /// Text widths are estimates (`TextMetrics`); this margin keeps estimated text clear of the borders.
    static let fitMargin = 1.08

    /// Columns cells a total row's title covers: the first column and the empty cells right after it.
    static func titleSpan(_ r: ScheduleRow, columns: Int) -> Int {
        var span = 1
        while span < columns, span >= r.cells.count || r.cells[span].text.isEmpty { span += 1 }
        return span
    }

    /// Paper width of one line of text in a cell, with the cell's padding.
    static func cellWidth<S: StringProtocol>(_ s: S, height: Double, bold: Bool) -> Double {
        TextMetrics.lineWidth(s, height: height, bold: bold) * fitMargin + 2 * cellPad
    }

    /// The columns of a table as laid out on paper, as Revit sheets show them: a column keeps its set width, a heading
    /// too long for it wraps onto two lines at a space, and a column widens only when its contents, its longest heading
    /// word or a heading that needs more than two lines don't fit. Returns the widths, the headings with their line
    /// breaks and the height of the headings row.
    public static func fit(_ t: ScheduleTable) -> (widths: [Double], headings: [String], headingHeight: Double) {
        let ap = t.appearance
        var widths = t.columns.map(\.width), headings = t.columns.map(\.heading)
        // Contents: every data cell, and the totals' cells (a title only where it can't run into the next cells).
        for r in t.rows where r.kind != .groupHeader && r.kind != .blank {
            let strong = r.kind != .data
            let titled = strong && !r.title.isEmpty
            for i in widths.indices {
                var text = i < r.cells.count ? r.cells[i].text : ""
                if i == 0, titled {
                    guard titleSpan(r, columns: widths.count) == 1 else { continue }
                    text = r.title
                }
                guard !text.isEmpty else { continue }
                for line in text.split(separator: "\n") { widths[i] = max(widths[i], cellWidth(line, height: ap.bodyTextHeight, bold: strong)) }
            }
        }
        // Headings: one line when it fits, else two lines split at the space that keeps the longer line shortest.
        var lines = 1
        let h = ap.headerTextHeight, bold = ap.boldHeaders
        for (i, heading) in headings.enumerated() where !heading.isEmpty {
            if cellWidth(heading, height: h, bold: bold) <= widths[i] { continue }
            let words = heading.split(separator: " ").map(String.init)
            guard words.count > 1 else { widths[i] = cellWidth(heading, height: h, bold: bold); continue }
            let splits = (1..<words.count).map { k in (words[..<k].joined(separator: " "), words[k...].joined(separator: " ")) }
            let best = splits.min { max(cellWidth($0.0, height: h, bold: bold), cellWidth($0.1, height: h, bold: bold))
                < max(cellWidth($1.0, height: h, bold: bold), cellWidth($1.1, height: h, bold: bold)) }!
            widths[i] = max(widths[i], cellWidth(best.0, height: h, bold: bold), cellWidth(best.1, height: h, bold: bold))
            headings[i] = best.0 + "\n" + best.1
            lines = 2
        }
        return (widths, headings, rowHeight + Double(lines - 1) * h * 1.7)
    }

    /// Paper rectangles of the cells, row by row (rows covered by a cell above are part of its rectangle).
    public static func cellRects(_ g: ScheduleGrid, topLeft: Vec2) -> [[Rect2]] {
        let xs = g.widths.reduce(into: [topLeft.x]) { $0.append($0.last! + $1) }
        var y = topLeft.y
        var out: [[Rect2]] = []
        for (ri, row) in g.rows.enumerated() {
            var rects: [Rect2] = []
            for c in row.cells {
                let x0 = xs[min(c.column, xs.count - 1)], x1 = xs[min(c.column + c.span, xs.count - 1)]
                let h = (ri..<min(g.rows.count, ri + c.rowSpan)).reduce(0) { $0 + g.rows[$1].height }
                rects.append(Rect2(min: Vec2(x0, y - h), max: Vec2(x1, y)))
            }
            out.append(rects)
            y -= row.height
        }
        return out
    }

    /// Images in title and header cells with their paper boxes (kept inside the cell, proportions kept).
    public static func images(_ t: ScheduleTable, topLeft: Vec2, rows: ScheduleRowRange? = nil) -> [(box: Rect2, image: ScheduleImage)] {
        let g = grid(t, rows: rows)
        var out: [(Rect2, ScheduleImage)] = []
        for (row, rects) in zip(g.rows, cellRects(g, topLeft: topLeft)) {
            for (c, r) in zip(row.cells, rects) {
                guard let img = c.image, img.pixelWidth > 0, img.pixelHeight > 0 else { continue }
                let inner = r.expanded(by: -0.0006)
                let s = min(inner.width / Double(img.pixelWidth), inner.height / Double(img.pixelHeight))
                let size = Vec2(Double(img.pixelWidth) * s, Double(img.pixelHeight) * s)
                out.append((Rect2(center: inner.center, halfSize: size * 0.5), img))
            }
        }
        return out
    }

    public static func primitives(_ t: ScheduleTable, topLeft: Vec2, rows: ScheduleRowRange? = nil) -> [GPrimitive] {
        let g = grid(t, rows: rows)
        var fills: [GPrimitive] = [], texts: [GPrimitive] = []
        // Edges keep the heaviest border drawn on them (neighbouring cells share edges).
        var edges: [EdgeKey: (Vec2, Vec2, ScheduleBorder)] = [:]
        func edge(_ a: Vec2, _ b: Vec2, _ w: ScheduleBorder) {
            guard w != .none else { return }
            let k = EdgeKey(a, b)
            if let e = edges[k], e.2 >= w { return }
            edges[k] = (a, b, w)
        }
        let pad = 0.0015
        for (row, rects) in zip(g.rows, cellRects(g, topLeft: topLeft)) {
            for (c, r) in zip(row.cells, rects) {
                if let s = c.shading { fills.append(.fill([Polygon2.rectangle(r)], GFill(pattern: .solid, color: s))) }
                edge(Vec2(r.min.x, r.max.y), r.max, c.edges[0])
                edge(Vec2(r.max.x, r.min.y), r.max, c.edges[1])
                edge(r.min, Vec2(r.max.x, r.min.y), c.edges[2])
                edge(r.min, Vec2(r.min.x, r.max.y), c.edges[3])
                guard !c.text.isEmpty else { continue }
                let x: Double, al: TextAlignment
                switch c.horizontal {
                case .left: x = r.min.x + pad; al = .left
                case .center: x = r.center.x; al = .center
                case .right: x = r.max.x - pad; al = .right
                }
                let y: Double, anchor: Double
                switch c.vertical {
                case .top: y = r.max.y - pad * 0.6; anchor = 1
                case .middle: y = r.center.y; anchor = 0.5
                case .bottom: y = r.min.y + pad * 0.6; anchor = 0
                }
                texts.append(.text(GText(position: Vec2(x, y), height: c.size, string: c.text, alignment: al, verticalAnchor: anchor, bold: c.bold,
                                         color: c.color, italic: c.italic, underline: c.underline)))
            }
        }
        // The frame around the headings and the rows (below the title band).
        let titleRows = g.rows.prefix { $0.kind == .title }
        let frameTop = topLeft.y - titleRows.reduce(0) { $0 + $1.height }
        let bottom = topLeft.y - g.height
        if frameTop > bottom + 1e-9 {
            let w: ScheduleBorder = t.appearance.outline ? .wide : .thin
            let x0 = topLeft.x, x1 = topLeft.x + g.width
            edge(Vec2(x0, frameTop), Vec2(x1, frameTop), w); edge(Vec2(x0, bottom), Vec2(x1, bottom), w)
            edge(Vec2(x0, bottom), Vec2(x0, frameTop), w); edge(Vec2(x1, bottom), Vec2(x1, frameTop), w)
        }
        let lines = edges.values.sorted { ($0.0.x, $0.0.y, $0.1.x, $0.1.y) < ($1.0.x, $1.0.y, $1.1.x, $1.1.y) }
            .map { GPrimitive.polyline([$0.0, $0.1], closed: false, GStroke(weight: $0.2.lineWeight)) }
        return fills + lines + texts
    }

    /// An edge independent of its direction, to millimetre-fraction precision.
    struct EdgeKey: Hashable {
        let a: SIMD4<Int64>
        init(_ p: Vec2, _ q: Vec2) {
            func r(_ v: Double) -> Int64 { Int64((v * 1e6).rounded()) }
            let (s, t) = (p.x, p.y) < (q.x, q.y) ? (p, q) : (q, p)
            a = SIMD4(r(s.x), r(s.y), r(t.x), r(t.y))
        }
    }
}
