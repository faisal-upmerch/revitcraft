import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusOutput

private func csv(_ s: String) -> Data { Data(s.utf8) }

private func table(_ headings: [String], _ rows: [[String]]) -> ScheduleTable {
    let cols = headings.map { ScheduleField(source: .parameter(ParameterID("comments")), heading: $0) }
    let rs = rows.map { r in
        ScheduleRow(kind: .data, cells: r.map { ScheduleCell(text: $0, value: nil, parameterID: nil, isEditable: false, background: nil, alignment: .left) },
                    elementIDs: [], title: "")
    }
    return ScheduleTable(title: "T", columns: cols, rows: rs, elementCount: rs.count)
}

@Suite("Schedule CSV")
struct ScheduleCSVTests {
    let f = Fixture.shared
    var schedule: Element { f.model[f.doorSchedule]! }

    // MARK: Export / parse

    @Test func exportParseRoundTripsAwkwardValues() throws {
        let values = [
            ["Mark", "Comments", "Size"],
            ["D-01", "Say \"hello\", then leave", "900 x 2100"],
            ["D-02", "Line one\nLine two\r\nLine three", ""],
            ["=SUM(A1:A2)", " padded ", "-12.5"],
            ["Ünïcødé ✓", "tab\there", "+44 20"],
        ]
        let t = table(values[0], Array(values.dropFirst()))
        let rows = try ScheduleCSV.parse(ScheduleCSV.export(t)).map { $0.map(ScheduleCSV.decodeCell) }
        // Line endings inside a value are preserved exactly.
        #expect(rows == values)
    }

    @Test func exportIsExcelFriendlyUTF8WithBOMAndCRLF() {
        let d = ScheduleCSV.export(table(["A", "B"], [["1", "2"]]))
        #expect(Array(d.prefix(3)) == [0xEF, 0xBB, 0xBF])
        let s = String(decoding: d.dropFirst(3), as: UTF8.self)
        #expect(s == "A,B\r\n1,2\r\n")
    }

    @Test func formulaInjectionIsNeutralizedOnExport() {
        let s = String(decoding: ScheduleCSV.export(table(["A", "B", "C", "D"], [["=HYPERLINK(\"x\")", "@cmd", "-5", "-x"]])).dropFirst(3), as: UTF8.self)
        #expect(s.contains("\"'=HYPERLINK(\"\"x\"\")\""))
        #expect(s.contains(",'@cmd,"))
        #expect(s.contains(",-5,"))         // plain numbers untouched
        #expect(s.contains(",'-x\r\n"))
    }

    @Test func exportIncludesGroupsTotalsAndOptionalElementIDs() throws {
        let t = ScheduleEngine.compute(schedule, f.model)
        let rows = try ScheduleCSV.parse(ScheduleCSV.export(t, includeElementIDs: true))
        #expect(rows[0].first == "Element ID")
        #expect(rows[0].dropFirst().first == "Mark")
        let d1 = rows.first { $0.count > 1 && $0[1] == "D-01" }
        #expect(d1?[0] == String(f.doors[0].raw))
        #expect(rows.contains { $0.contains { $0.hasPrefix("Grand total") } })
        #expect(Set(rows.map(\.count)).count == 1) // rectangular
    }

    @Test func parseHandlesLineEndingsBOMAndQuotes() throws {
        #expect(try ScheduleCSV.parse(csv("a,b\r\n1,2\r\n")) == [["a", "b"], ["1", "2"]])
        #expect(try ScheduleCSV.parse(csv("a,b\n1,2")) == [["a", "b"], ["1", "2"]])
        #expect(try ScheduleCSV.parse(csv("a,b\r1,2\r")) == [["a", "b"], ["1", "2"]])
        #expect(try ScheduleCSV.parse(Data([0xEF, 0xBB, 0xBF]) + csv("Mark\nD-01")) == [["Mark"], ["D-01"]])
        #expect(try ScheduleCSV.parse(csv("\"a,1\",\"b\"\"c\",\"multi\r\nline\"\n")) == [["a,1", "b\"c", "multi\r\nline"]])
        #expect(try ScheduleCSV.parse(csv("a,,c\n,,\n\n\nx,y,z\n")) == [["a", "", "c"], ["", "", ""], ["x", "y", "z"]])
    }

    @Test func parseAcceptsUTF16AndSemicolonFiles() throws {
        let utf16 = "Mark;Comments\r\nD-01;\"a;b\"\r\n".data(using: .utf16)!
        #expect(try ScheduleCSV.parse(utf16) == [["Mark", "Comments"], ["D-01", "a;b"]])
        #expect(try ScheduleCSV.parse(csv("Mark\tComments\nD-01\tx")) == [["Mark", "Comments"], ["D-01", "x"]])
    }

    @Test func parseKeepsRaggedRows() throws {
        #expect(try ScheduleCSV.parse(csv("a,b,c\n1\n1,2,3,4\n")) == [["a", "b", "c"], ["1"], ["1", "2", "3", "4"]])
    }

    @Test func parseRejectsHostileInput() throws {
        #expect(throws: ScheduleCSVError.self) { try ScheduleCSV.parse(Data([0x4D, 0x61, 0xFF, 0xFE, 0x0A, 0xC3])) }    // invalid UTF-8
        #expect(throws: ScheduleCSVError.self) { try ScheduleCSV.parse(csv("a,\"never closed\n1,2\n")) }
        #expect(throws: ScheduleCSVError.self) { try ScheduleCSV.parse(Data(count: ScheduleCSV.maxBytes + 1)) }
        #expect(throws: ScheduleCSVError.self) { try ScheduleCSV.parse(csv(String(repeating: "x,", count: ScheduleCSV.maxColumns + 5))) }
        #expect(throws: ScheduleCSVError.self) { try ScheduleCSV.parse(csv("\"" + String(repeating: "y", count: ScheduleCSV.maxFieldBytes + 1) + "\"")) }
        #expect(throws: ScheduleCSVError.self) { try ScheduleCSV.parse(csv("a\u{0}b,c")) }
    }

    @Test func parseLargeButValidFileQuickly() throws {
        var s = "Mark,Comments\r\n"
        for i in 0..<50_000 { s += "D-\(i),\"Comment, number \(i)\"\r\n" }
        let clock = ContinuousClock()
        var rows: [[String]] = []
        let d = try clock.measure { rows = try ScheduleCSV.parse(csv(s)) }
        #expect(rows.count == 50_001)
        #expect(rows[50_000] == ["D-49999", "Comment, number 49999"])
        #expect(d < .seconds(5))
    }

    // MARK: Import preview

    @Test func previewMatchesByMarkAndChangesOnlySelectedColumns() throws {
        let data = csv("Mark,Comments,Fire Rating\nD-01,Keep closed,60 min\nD-02,,30 min\nD-99,Ghost,\n")
        let p = try ScheduleCSV.preview(data, schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["Comments"])
        #expect(p.errors.isEmpty)
        #expect(p.unmatchedKeys == ["D-99"])
        #expect(p.changes.count == 1)
        let c = try #require(p.changes.first)
        #expect(c.elementID == f.doors[0])
        #expect(c.parameterID == ParameterID("comments"))
        #expect(c.oldText == "" && c.newText == "Keep closed" && c.newValue == .text("Keep closed"))
    }

    @Test func previewMatchesByElementID() throws {
        let t = ScheduleEngine.compute(schedule, f.model)
        var rows = try ScheduleCSV.parse(ScheduleCSV.export(t, includeElementIDs: true))
        let ci = rows[0].firstIndex(of: "Comments")!
        let r = rows.firstIndex { $0[0] == String(f.doors[1].raw) }!
        rows[r][ci] = "Via id"
        let data = csv(rows.map { $0.map(ScheduleCSV.encodeField).joined(separator: ",") }.joined(separator: "\n"))
        let p = try ScheduleCSV.preview(data, schedule: schedule, model: f.model, keyColumn: "Element ID", columns: ["Comments"])
        #expect(p.errors.isEmpty)
        #expect(p.changes.map(\.elementID) == [f.doors[1]])
        // Totals rows have no element id; they are simply not matched.
        #expect(p.unmatchedKeys.isEmpty)
        let bad = try ScheduleCSV.preview(csv("Element ID,Comments\n#\(f.walls[0].raw),x\n\(f.doors[0].raw),y\n"), schedule: schedule, model: f.model,
                                          keyColumn: "element id", columns: ["Comments"])
        #expect(bad.unmatchedKeys == ["#\(f.walls[0].raw)"])   // a wall isn't in the door schedule
        #expect(bad.changes.map(\.elementID) == [f.doors[0]])
    }

    @Test func previewRejectsReadOnlyAndUnknownColumns() throws {
        let data = csv("Mark,From Room,Nonsense,Comments\nD-01,Lobby,1,ok\n")
        let p = try ScheduleCSV.preview(data, schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["From Room", "Nonsense", "Missing", "Comments", "Mark"])
        #expect(p.changes.map(\.parameterID) == [ParameterID("comments")])
        let byColumn = Dictionary(grouping: p.errors, by: \.column)
        #expect(byColumn["From Room"]?.first?.message.contains("read-only") == true)
        #expect(byColumn["Nonsense"]?.first?.row == 1)
        #expect(byColumn["Missing"]?.first?.message.contains("no “Missing” column") == true)
        #expect(byColumn["Mark"]?.first?.message.contains("key column") == true)
    }

    @Test func previewReportsInvalidValuesWithRowAndColumn() throws {
        let data = csv("Mark,Width,Comments\nD-01,wide,fine\nD-02,1000,\n")
        let p = try ScheduleCSV.preview(data, schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["Width", "Comments"])
        let e = try #require(p.errors.first)
        #expect(p.errors.count == 1)
        #expect(e.row == 2 && e.column == "Width")
        #expect(e.message.contains("wide"))
        // Width is a type parameter shared by both doors: D-02's value still applies once, to the type.
        #expect(p.changes.contains { $0.elementID == f.doors[1] && $0.parameterName == "Width" && $0.newValue.doubleValue.map { abs($0 - 1.0) < 1e-9 } == true })
        #expect(p.changes.contains { $0.elementID == f.doors[0] && $0.parameterID == ParameterID("comments") })
    }

    @Test func previewDetectsConflictingTypeValues() throws {
        let data = csv("Mark,Width\nD-01,950\nD-02,1000\n")
        let p = try ScheduleCSV.preview(data, schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["Width"])
        #expect(p.changes.count == 1)
        #expect(p.errors.first?.row == 3)
        #expect(p.errors.first?.message.contains("row 2") == true)
    }

    @Test func previewReportsRaggedRowsMissingKeysAndAmbiguousKeys() throws {
        let tx = TransactionContext(model: f.model, name: "Dup")
        tx.update(f.doors[1]) { $0.mark = "D-01" }
        let dup = try tx.commit().model
        let data = csv("Mark,Comments\nD-01,x\n,y\nD-02\n")
        let p = try ScheduleCSV.preview(data, schedule: dup[f.doorSchedule]!, model: dup, keyColumn: "Mark", columns: ["Comments"])
        #expect(p.changes.isEmpty)
        #expect(p.errors.contains { $0.row == 2 && $0.message.contains("matches 2 rows") })
        #expect(p.errors.contains { $0.row == 3 && $0.column == "Mark" })
        #expect(p.unmatchedKeys == ["D-02"])

        let ragged = try ScheduleCSV.preview(csv("Mark,Comments\nD-01\n"), schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["Comments"])
        #expect(ragged.errors.first?.row == 2 && ragged.errors.first?.column == "Comments")
    }

    @Test func previewThrowsWithoutAUsableKeyColumn() throws {
        #expect(throws: ScheduleCSVError.self) {
            try ScheduleCSV.preview(csv("Comments\nx\n"), schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["Comments"])
        }
        #expect(throws: ScheduleCSVError.self) {
            try ScheduleCSV.preview(csv("Colour,Comments\nred,x\n"), schedule: schedule, model: f.model, keyColumn: "Colour", columns: ["Comments"])
        }
        #expect(throws: ScheduleCSVError.self) {
            try ScheduleCSV.preview(Data(), schedule: schedule, model: f.model, keyColumn: "Mark", columns: [])
        }
        #expect(throws: ScheduleCSVError.self) {
            try ScheduleCSV.preview(csv("Mark\n"), schedule: f.model[f.plan]!, model: f.model, keyColumn: "Mark", columns: [])
        }
    }

    @Test func unchangedValuesProduceNoChanges() throws {
        let data = ScheduleCSV.export(ScheduleEngine.compute(schedule, f.model))
        let p = try ScheduleCSV.preview(data, schedule: schedule, model: f.model, keyColumn: "Mark",
                                        columns: ["Type", "Width", "Height", "Fire Rating", "Comments"])
        #expect(p.changes.isEmpty)
        #expect(p.errors.isEmpty)
    }

    // MARK: Apply

    @Test func applyWritesInsideATransactionAndCommits() throws {
        let data = csv("Mark,Comments,Fire Rating,Width\r\nD-01,\"Hold open, magnetic\",60 min,1000\r\nD-02,Staff only,60 min,1000\r\n")
        let p = try ScheduleCSV.preview(data, schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["Comments", "Fire Rating", "Width"])
        #expect(p.errors.isEmpty)
        let tx = TransactionContext(model: f.model, name: "Import CSV")
        let n = try ScheduleCSV.apply(p, in: tx)
        #expect(n == 4) // two comments + one type fire rating + one type width
        let m = try tx.commit().model
        #expect(m[f.doors[0]]!.comments == "Hold open, magnetic")
        #expect(m[f.doors[1]]!.comments == "Staff only")
        #expect(Parameters.value(ParameterID("type.fireRating"), of: m[f.doors[1]]!, m)?.textValue == "60 min")
        #expect(abs((Parameters.value(Parameters.familyParamID("Width"), of: m[f.doors[0]]!, m)?.doubleValue ?? 0) - 1.0) < 1e-9)
        // The schedule reflects the new values.
        let t = ScheduleEngine.compute(m[f.doorSchedule]!, m)
        #expect(t.rows.contains { $0.cells.contains { $0.text == "Staff only" } })
    }

    @Test func applyRefusesStalePreviews() throws {
        let p = try ScheduleCSV.preview(csv("Mark,Comments\nD-01,New\n"), schedule: schedule, model: f.model, keyColumn: "Mark", columns: ["Comments"])
        let tx0 = TransactionContext(model: f.model, name: "Edit")
        tx0.update(f.doors[0]) { $0.comments = "Changed meanwhile" }
        let edited = try tx0.commit().model
        let tx = TransactionContext(model: edited, name: "Import")
        #expect(throws: ScheduleCSVError.self) { _ = try ScheduleCSV.apply(p, in: tx) }
        let tx2 = TransactionContext(model: f.model, name: "Import")
        #expect(try ScheduleCSV.apply(p, in: tx2) == 1)
    }
}
