import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain

/// POLISH: schedule columns on sheets fit their headings and contents; Part Tags on shop drawings stand clear of the
/// piece, the annotations and each other.
@Suite("POLISH schedules and tags")
struct POLISHTests {
    static func table(_ columns: [(String, Double)], rows: [[String]], footer: String? = nil) -> ScheduleTable {
        let fields = columns.map { ScheduleField(source: .parameter(ParameterID("polish.\($0.0)")), heading: $0.0, width: $0.1) }
        func cells(_ r: [String]) -> [ScheduleCell] {
            r.map { ScheduleCell(text: $0, value: nil, parameterID: nil, isEditable: false, background: nil, alignment: .left) }
        }
        var out = rows.map { ScheduleRow(kind: .data, cells: cells($0), elementIDs: [], title: "") }
        if let footer { out.append(ScheduleRow(kind: .grandTotal, cells: cells(["", "", "3"]), elementIDs: [], title: footer)) }
        return ScheduleTable(title: "Part List", columns: fields, rows: out, elementCount: rows.count)
    }

    @Test func aLongHeadingWrapsOntoTwoLinesInsteadOfRunningIntoTheNext() {
        let t = Self.table([("Mark", 0.014), ("Edge Banding", 0.018), ("Banding Length", 0.018)], rows: [["P1", "L1", "4'"]])
        let fit = ScheduleLayout.fit(t)
        #expect(fit.headings == ["Mark", "Edge\nBanding", "Banding\nLength"])
        #expect(fit.widths == [0.014, 0.018, 0.018]) // the set widths hold: the headings wrap
        #expect(fit.headingHeight > ScheduleLayout.rowHeight)
        // Every line of every heading fits its column.
        for (h, w) in zip(fit.headings, fit.widths) {
            for line in h.split(separator: "\n") { #expect(ScheduleLayout.cellWidth(line, height: t.appearance.headerTextHeight, bold: true) <= w + 1e-12) }
        }
        let g = ScheduleLayout.grid(t)
        #expect(g.rows.first { $0.kind == .headings }?.height == fit.headingHeight)
        #expect(Fx.approx(t.totalWidth, g.width, 1e-12))
    }

    @Test func aColumnWidensForContentThatDoesntFit() {
        let t = Self.table([("Model", 0.014), ("Count", 0.014)], rows: [["CH-35-FO110", "4"]])
        let fit = ScheduleLayout.fit(t)
        #expect(fit.widths[0] > 0.014 && fit.widths[0] >= ScheduleLayout.cellWidth("CH-35-FO110", height: t.appearance.bodyTextHeight, bold: false) - 1e-12)
        #expect(fit.widths[1] == 0.014)
        #expect(fit.headings == ["Model", "Count"])
        #expect(fit.headingHeight == ScheduleLayout.rowHeight)
        // Printed and drawn at the same width.
        #expect(Fx.approx(t.totalWidth, fit.widths.reduce(0, +), 1e-12))
    }

    @Test func aTotalsTitleRunsAcrossTheEmptyCellsAfterIt() {
        let t = Self.table([("Mark", 0.014), ("Part", 0.014), ("Qty", 0.014)], rows: [["P1", "Side", "2"]], footer: "Grand total: 25 parts")
        let g = ScheduleLayout.grid(t)
        let total = g.rows.last
        #expect(total?.cells.first?.span == 2)
        #expect(total?.cells.first?.text == "Grand total: 25 parts")
        #expect(total?.cells.map(\.column) == [0, 2])
        // The title doesn't widen the first column: it has the empty Part cell to run into.
        #expect(ScheduleLayout.fit(t).widths[0] == 0.014)
    }

    @Test func tagsStandBesideThePieceInTidyColumns() {
        let outline = Rect2(min: Vec2(-0.6, 0), max: Vec2(0.6, 0.9))
        let scale = 24
        // A dimension down the right side and a level label beyond it, as on a Front elevation.
        let dim = Rect2(min: Vec2(0.65, 0), max: Vec2(0.72, 0.9)), label = Rect2(min: Vec2(0.75, 0.40), max: Vec2(1.0, 0.50))
        let parts: [(id: ElementID, anchor: Vec2)] = [(ElementID(1), Vec2(-0.58, 0.45)), (ElementID(2), Vec2(0.58, 0.45)), (ElementID(3), Vec2(0, 0.88)),
                                                       (ElementID(4), Vec2(0, 0.02)), (ElementID(5), Vec2(-0.2, 0.45)), (ElementID(6), Vec2(0.2, 0.45)),
                                                       (ElementID(7), Vec2(0, 0.5))]
        let placed = FurnitureTagLayout.layout(parts, outline: outline, obstacles: [dim, label], scale: scale)
        #expect(placed.count == parts.count)
        let boxes = placed.map { FurnitureTagLayout.box($0.head, scale: scale) }
        for (i, b) in boxes.enumerated() {
            #expect(!b.intersects(outline), "tag \(i) covers the piece")
            #expect(!b.intersects(dim) && !b.intersects(label), "tag \(i) covers an annotation")
            for c in boxes[(i + 1)...] { #expect(!b.intersects(c), "tags overlap") }
        }
        // Two aligned columns, top to bottom in the order of their parts, every leader ending at its part.
        let xs = Set(placed.map { ($0.head.x * 1e6).rounded() })
        #expect(xs.count == 2)
        for side in [placed.filter { $0.head.x < 0 }, placed.filter { $0.head.x > 0 }] {
            #expect(side.map(\.head.y) == side.map(\.head.y).sorted(by: >))
        }
        #expect(Set(placed.map(\.anchor)) == Set(parts.map(\.anchor)))
        // The right column is pushed past the level label, not just the dimension.
        #expect(placed.filter { $0.head.x > 0 }.allSatisfy { $0.head.x - FurnitureTagLayout.boxHalf.x * Double(scale) >= label.max.x })
    }
}
