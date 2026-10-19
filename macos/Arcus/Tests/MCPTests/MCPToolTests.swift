import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
@testable import ArcusMCP

// MCP: the tool layer end to end in file mode (Docs/MCP.md §5): project → walls → doors → windows → floor → roof →
// rooms → views → sheet → tags and dimensions → PDF/PNG → save and reopen; undo; Furniture parts; validation errors.

@MainActor
final class ToolDriver {
    let host = FileDocumentHost()
    let box: ArcusToolbox
    init() { box = ArcusToolbox(host: host) }

    /// Calls a tool and returns its JSON result; fails the test when the tool reports an error.
    @discardableResult
    func call(_ name: String, _ args: JSONValue = [:], sourceLocation: SourceLocation = #_sourceLocation) async throws -> JSONValue {
        let r = await box.callTool(name, arguments: args.objectValue ?? [:])
        #expect(!r.isError, "\(name): \(r.text)", sourceLocation: sourceLocation)
        if r.isError { throw ToolError(r.text) }
        return try JSONValue.parse(r.text)
    }

    /// Calls a tool that should fail; returns the error text.
    func fail(_ name: String, _ args: JSONValue, sourceLocation: SourceLocation = #_sourceLocation) async -> String {
        let r = await box.callTool(name, arguments: args.objectValue ?? [:])
        #expect(r.isError, "\(name) should have failed: \(r.text)", sourceLocation: sourceLocation)
        return r.text
    }

    var model: BIMModel { host.session!.model }
}

func ids(_ v: JSONValue?, _ key: String = "id") -> [Int] { v?.arrayValue?.compactMap { $0[key]?.intValue } ?? [] }

func tempDir() throws -> URL {
    let d = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-mcp-tests-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
}

@MainActor
@Suite("MCP tools (file mode)")
struct MCPToolTests {
    @Test func buildsAHouseEndToEnd() async throws {
        let t = ToolDriver()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let p = try await t.call("create_project", ["name": "Test House", "levels": [["name": "Ground", "elevation": 0], ["name": "Upper", "elevation": "10'"], ["name": "Roof", "elevation": 20]]])
        #expect(p["unit"]?.stringValue == "ft")
        #expect(p["levels"]?.arrayValue?.map { $0["name"]?.stringValue } == ["Ground", "Upper", "Roof"])
        #expect(t.model.level(named: "Upper")?.level?.elevation ?? 0 == 10 * 0.3048)

        // A 30' x 20' box (clockwise) and a partition at x = 12'.
        let ext = try await t.call("create_walls", ["level": "Ground", "points": [[0, 0], [0, 20], [30, 20], [30, 0]], "closed": true])
        let walls = ids(ext["walls"])
        #expect(walls.count == 4)
        #expect(ext["top"]?.stringValue == "Upper")
        let part = try await t.call("create_walls", ["level": "Ground", "type": "Generic - 6\"", "segments": [[[12, 0], [12, 20]]]])
        let partition = try #require(ids(part["walls"]).first)
        let south = walls[3] // (30,0) → (0,0)

        let d = try await t.call("place_doors", ["doors": [["wall": .int(south), "offset": 22, "type": "Single Panel 36x80", "mark": "101"],
                                                           ["wall": .int(partition), "point": [12, 10], "type": "Door - Single Flush: 32\" x 80\""]]])
        #expect(ids(d["doors"]).count == 2)
        #expect(d["doors"]?.arrayValue?.first?["type"]?.stringValue?.contains("Single Panel") == true)
        let w = try await t.call("place_windows", ["windows": [["wall": .int(walls[0]), "offset": 10, "type": "Casement 36x60", "sill_height": "2'-6\""],
                                                               ["wall": .int(walls[2]), "offset": "10'"]]])
        #expect(ids(w["windows"]).count == 2)
        #expect(t.model.elements(.windows).contains { abs(($0.insert?.sillHeight ?? 0) - 2.5 * 0.3048) < 1e-6 })

        let f = try await t.call("create_floor", ["level": "Ground", "from_walls": true])
        #expect(f["floor"]?.intValue != nil)
        #expect(f["area"]?.stringValue?.contains("SF") == true)
        let roof = try await t.call("create_roof", ["level": "Upper", "from_walls_of": "Ground", "shape": "gable", "slope": 30])
        #expect(roof["roof"]?.intValue != nil)

        let rooms = try await t.call("place_rooms", ["level": "Ground", "auto": true])
        let placed = rooms["rooms"]?.arrayValue ?? []
        #expect(placed.count == 2)
        #expect(placed.allSatisfy { $0["bounded"]?.boolValue == true })
        let total = placed.compactMap { $0["area"]?.doubleValue }.reduce(0, +)
        #expect(total > 520 && total < 560, "29' x 19' inside less the 6\" partition: \(total) SF")
        let roomIDs = ids(rooms["rooms"])
        try await t.call("set_parameters", ["elements": .array(roomIDs.prefix(1).map { .int($0) }), "parameters": ["Name": "Living"]])
        #expect(t.model.elements(.rooms).contains { $0.name == "Living" })

        // Views, documentation and a sheet.
        let v = try await t.call("create_views", ["views": [["kind": "section", "start": [-5, 10], "end": [35, 10], "name": "Section A"],
                                                           ["kind": "three_d", "name": "Cutaway", "cut_to_level": "Ground"]]])
        #expect(v["views"]?.arrayValue?.count == 2)
        let dims = try await t.call("add_dimensions", ["view": "Ground", "auto": true])
        #expect((dims["dimensions"]?.arrayValue?.count ?? 0) >= 4)
        #expect(dims["strings"]?.arrayValue?.contains { $0.stringValue == "31' - 0\"" } == true, "overall 31' (outside faces): \(dims)")
        let tags = try await t.call("add_tags", ["view": "Ground"])
        #expect((tags["tagged"]?.intValue ?? 0) >= 4, "\(tags)")
        let sheet = try await t.call("create_sheet", ["number": "A101", "name": "Ground Floor Plan", "views": [["view": "Ground"], ["view": "Section A"]], "schedules": ["Room Schedule"]])
        #expect(sheet["placed"]?.arrayValue?.count == 3)
        #expect(sheet["paper"]?.stringValue == "ARCH D")
        let again = await t.fail("create_sheet", ["number": "A102", "name": "Again", "views": [["view": "Ground"]]])
        #expect(again.contains("already on sheet A101"))

        // Checks Claude would run.
        let q = try await t.call("query_model", ["what": "rooms"])
        #expect(q["rooms"]?.arrayValue?.count == 2)
        let warnings = try await t.call("query_model", ["what": "warnings"])
        #expect(warnings["count"]?.intValue != nil)
        let walls2 = try await t.call("query_model", ["what": "elements", "category": "walls"])
        #expect(walls2["count"]?.intValue == 5)

        // Outputs.
        let png = dir.appendingPathComponent("plan.png")
        let r = await t.box.callTool("render_view", arguments: ["view": "Ground", "path": .string(png.path), "width": 800])
        #expect(!r.isError, "\(r.text)")
        #expect(r.content.contains { $0["type"]?.stringValue == "image" })
        #expect(FileManager.default.fileExists(atPath: png.path))
        let pdf = try await t.call("export_pdf", ["path": .string(dir.appendingPathComponent("set.pdf").path)])
        #expect(pdf["pages"]?.intValue == 1)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("set.pdf").path))
        let dxf = try await t.call("export_dwg", ["views": ["Ground"], "folder": .string(dir.path), "format": "dxf"])
        #expect(dxf["files"]?.arrayValue?.count == 1)

        // Save, reopen, compare.
        let saved = try await t.call("save", ["path": .string(dir.appendingPathComponent("House").path)])
        let url = URL(fileURLWithPath: try #require(saved["path"]?.stringValue))
        #expect(url.pathExtension == "arcus")
        let reread = try ArcusPackage.read(from: url).model
        #expect(reread.count == t.model.count)
        #expect(reread.elements(.rooms).count == 2)
        let t2 = ToolDriver()
        let st = try await t2.call("open_document", ["path": .string(url.path)])
        #expect(st["counts"]?["walls"]?.intValue == 5)
    }

    @Test func undoRevertsOneToolCallAtATime() async throws {
        let t = ToolDriver()
        try await t.call("create_project", ["name": "Undo", "units": "metric"])
        try await t.call("create_walls", ["points": [[0, 0], [0, 4000], [6000, 4000], [6000, 0]], "closed": true])
        try await t.call("place_rooms", ["auto": true])
        #expect(t.model.elements(.rooms).count == 1)
        // A failed call adds no undo step.
        _ = await t.fail("place_doors", ["doors": [["wall": 999_999]]])
        let u = try await t.call("undo")
        #expect(u["undone"]?.arrayValue?.first?.stringValue == "Place Rooms")
        #expect(t.model.elements(.rooms).isEmpty)
        #expect(t.model.elements(.walls).count == 4)
        try await t.call("undo")
        #expect(t.model.elements(.walls).isEmpty)
        try await t.call("redo", ["steps": 2])
        #expect(t.model.elements(.rooms).count == 1)
    }

    @Test func validationErrorsSayWhatToChange() async throws {
        let t = ToolDriver()
        try await t.call("create_project", ["name": "Errors"])
        let ws = try await t.call("create_walls", ["points": [[0, 0], [20, 0]]])
        let wall = try #require(ids(ws["walls"]).first)
        #expect(await t.fail("create_walls", ["points": [[0, 0], [0.01, 0]]]).contains("too short"))
        #expect(await t.fail("create_walls", ["level": "Basement", "points": [[0, 0], [5, 0]]]).contains("Levels: Level 1"))
        #expect(await t.fail("create_walls", ["type": "Rammed Earth Unicorn", "points": [[0, 0], [5, 0]]]).contains("Closest:"))
        #expect(await t.fail("place_doors", ["doors": [["wall": .int(wall), "offset": 40]]]).contains("outside wall"))
        #expect(await t.fail("create_walls", ["points": [[0, 0], ["x", 0]]]).contains("length"))
        #expect(await t.fail("set_parameters", ["elements": [.int(wall)], "parameters": ["Colour Of Mood": "blue"]]).contains("Editable:"))
        #expect(await t.fail("create_floor", ["boundary": [[0, 0], [1, 1]]]).contains("at least 3 points"))
        #expect(await t.fail("add_furniture_parts", ["parts": [["kind": "sides"]]]).contains("create_furniture"))
    }

    @Test func buildsFurnitureParts() async throws {
        let t = ToolDriver()
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = try await t.call("create_furniture", ["name": "Bookcase", "category": "casework", "width": 36, "depth": 12, "height": "6'"])
        #expect(f["unit"]?.stringValue == "in")
        #expect(abs((f["planes"]?["Top"]?.doubleValue ?? 0) - 72) < 0.01)
        let parts = try await t.call("add_furniture_parts", ["parts": [
            ["kind": "sides", "type": "3/4\" Plywood"],
            ["kind": "top"],
            ["kind": "bottom", "z": 4.25, "ref": "bottom"],
            ["kind": "shelf", "z": 24, "adjustable": true],
            ["kind": "shelf", "z": 48, "adjustable": true],
            ["kind": "plinth", "host": "bottom", "setback": 0.5],
            ["kind": "back", "at": [0, 30]],
        ]])
        #expect(parts["parts"]?.arrayValue?.count == 7)
        #expect(t.model.elements(.furniturePanels).count == 4, "two sides, a plinth and a back")
        #expect(t.model.elements(.furnitureShelves).count == 4)
        let o = (parts["overall"]?.arrayValue ?? []).compactMap { $0.doubleValue }
        #expect(o.count == 3 && abs(o[0] - 36) < 0.1 && abs(o[2] - 72) < 0.1, "overall \(o)")
        try await t.call("set_furniture_size", ["width": 30])
        #expect(abs((FurniturePlanes.positionsByName(t.model)["Right"] ?? 0) - 15 * 0.0254) < 1e-6)
        let table = ToolDriver()
        try await table.call("create_furniture", ["name": "Table", "width": 60, "depth": 36, "height": 30])
        try await table.call("add_furniture_parts", ["parts": [["kind": "top", "boundary": [[-30, -18], [30, -18], [30, 18], [-30, 18]], "type": "Butcher Block", "ref": "top"],
                                                              ["kind": "legs_at_corners", "host": "top", "inset": 2],
                                                              ["kind": "edge_profile", "host": "top", "edge": "front_top"]]])
        #expect(table.model.elements(.furnitureLegs).count == 4)
        let saved = try await t.call("save", ["path": .string(dir.appendingPathComponent("Bookcase.arcus").path)])
        #expect(saved["path"]?.stringValue?.hasSuffix(".arcusfurniture") == true)
    }
}
