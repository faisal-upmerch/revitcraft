import AppKit
import ArcusDomain
import ArcusApplication

// F12: the schedule's title and header rows above the column headings (RevitCraft rc-app schedule_ui.rs): cells you
// click to select (⇧-click extends along a row) for Merge Unmerge, Insert Image, Clear Cell, Shading, Borders, Font
// and alignment, and double-click to type in.

/// Title band and inserted header rows, scrolled with the table.
final class ScheduleTitleStrip: NSView {
    weak var owner: ScheduleTableView?
    var table: ScheduleTable?
    var widths: [CGFloat] = []
    var offset: CGFloat = 0
    /// Selected title/header-row cells.
    var selection: [ScheduleCellKey] = []
    static let titleHeight: CGFloat = 26
    static let rowHeight: CGFloat = 20
    override var isFlipped: Bool { true }

    /// Height the strip needs for the table (0 when it shows nothing).
    static func height(_ t: ScheduleTable?) -> CGFloat {
        guard let t else { return 0 }
        let rows = t.formatting.headerRows.reduce(CGFloat(0)) { $0 + rowHeight * max(1, CGFloat(($1.height ?? ScheduleLayout.rowHeight) / ScheduleLayout.rowHeight)) }
        return (t.showTitle ? titleHeight : 0) + rows
    }

    /// Rows as laid out on screen: (key per cell, rect per cell).
    func layout() -> [[(key: ScheduleCellKey, rect: NSRect, text: String, image: ScheduleImage?)]] {
        guard let t = table else { return [] }
        let xs = widths.reduce(into: [CGFloat(0)]) { $0.append($0.last! + $1) }
        let total = xs.last ?? 0
        var y: CGFloat = 0
        var out: [[(ScheduleCellKey, NSRect, String, ScheduleImage?)]] = []
        if t.showTitle {
            let img = t.formatting.titleImage
            out.append([(.title, NSRect(x: -offset, y: y, width: max(total, bounds.width), height: Self.titleHeight), img == nil ? t.title : "", img)])
            y += Self.titleHeight
        }
        let n = max(1, widths.count)
        for (r, hr) in t.formatting.headerRows.enumerated() {
            let h = Self.rowHeight * max(1, CGFloat((hr.height ?? ScheduleLayout.rowHeight) / ScheduleLayout.rowHeight))
            var cells: [(ScheduleCellKey, NSRect, String, ScheduleImage?)] = []
            var c = 0
            while c < n {
                let span = hr.span(at: c, columns: n)
                let x0 = xs[min(c, xs.count - 1)], x1 = xs[min(c + span, xs.count - 1)]
                cells.append((.headerRow(r, c), NSRect(x: x0 - offset, y: y, width: x1 - x0, height: h), hr.text(c), hr.images[c]))
                c += span
            }
            out.append(cells)
            y += h
        }
        return out
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()
        guard let t = table else { return }
        for row in layout() {
            for cell in row {
                let style = t.formatting.style(cell.key)
                if let s = style.shading { s.nsColor.setFill(); cell.rect.fill() }
                if selection.contains(cell.key) { NSColor.controlAccentColor.withAlphaComponent(0.18).setFill(); cell.rect.fill() }
                NSColor.separatorColor.setStroke()
                NSBezierPath(rect: cell.rect.insetBy(dx: 0.5, dy: 0.5)).stroke()
                if let img = cell.image, let ns = NSImage(data: img.png) {
                    let inner = cell.rect.insetBy(dx: 3, dy: 3)
                    let s = min(inner.width / max(ns.size.width, 1), inner.height / max(ns.size.height, 1))
                    let size = NSSize(width: ns.size.width * s, height: ns.size.height * s)
                    ns.draw(in: NSRect(x: inner.midX - size.width / 2, y: inner.midY - size.height / 2, width: size.width, height: size.height),
                            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
                guard !cell.text.isEmpty else { continue }
                let isTitle = cell.key == .title
                let font = Self.font(style.font, bold: isTitle && t.appearance.boldTitle, size: isTitle ? 14 : 11)
                var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: style.font?.color.nsColor ?? NSColor.labelColor]
                if style.font?.underline == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                let str = cell.text as NSString
                let size = str.size(withAttributes: attrs)
                let x: CGFloat
                switch style.horizontal ?? .center {
                case .left: x = cell.rect.minX + 4
                case .center: x = cell.rect.midX - size.width / 2
                case .right: x = cell.rect.maxX - 4 - size.width
                }
                let y: CGFloat
                switch style.vertical ?? .middle {
                case .top: y = cell.rect.minY + 2
                case .middle: y = cell.rect.midY - size.height / 2
                case .bottom: y = cell.rect.maxY - 2 - size.height
                }
                str.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            }
        }
    }

    /// A screen font for a cell's Font setting (sizes follow the paper height: 2.2 mm reads as 11 pt).
    static func font(_ f: ScheduleFont?, bold: Bool, size: CGFloat) -> NSFont {
        let pt = f.map { CGFloat(max(7, min(28, $0.size / 0.0022 * 11))) } ?? size
        var font = NSFont(name: f?.family ?? "", size: pt) ?? NSFont.systemFont(ofSize: pt)
        let wantsBold = f?.bold ?? bold
        if wantsBold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if f?.italic == true { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    func key(at p: NSPoint) -> ScheduleCellKey? {
        for row in layout() { for c in row where c.rect.contains(p) { return c.key } }
        return nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard let k = key(at: p) else { return }
        if event.clickCount >= 2 { owner.editHeaderCell(k); return }
        if event.modifierFlags.contains(.shift), case .headerRow(let r, let c) = k, case .headerRow(let r0, let c0)? = selection.first, r == r0 {
            let starts = layout().flatMap { $0 }.compactMap { cell -> Int? in if case .headerRow(let rr, let cc) = cell.key, rr == r { return cc }; return nil }
            selection = starts.filter { $0 >= min(c, c0) && $0 <= max(c, c0) }.map { .headerRow(r, $0) }
        } else {
            selection = [k]
        }
        owner.headerSelectionChanged()
        needsDisplay = true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let owner else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        if let k = key(at: p), !selection.contains(k) { selection = [k]; owner.headerSelectionChanged(); needsDisplay = true }
        return ScheduleCommands.contextMenu(owner.state)
    }
}
