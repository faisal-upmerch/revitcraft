import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
import ArcusApplication
import ArcusPersistence
@testable import ArcusMCP

// AITOOLS: every tool in the catalog is callable in its document kind with a minimal valid input, fails with an
// actionable message on a bad one, declares its risk, is filtered by mode, nests in the assistant's undo group, and
// four scripted flows work end to end (house plan to PDF, a cabinet with fronts and hardware to shop drawings, editing
// the selected walls, fixing a drawing whose dimensions overlap).

/// A document ready for a tool: a small project, a cabinet, or a family (with its project).
@MainActor
final class Fixture {
    let t = ToolDriver()
    let dir: URL
    var walls: [Int] = []
    var partition = 0
    var doors: [Int] = []
    var windows: [Int] = []
    var rooms: [Int] = []
    var parts: [String: Int] = [:]

    init() throws { dir = try tempDir() }
    deinit { try? FileManager.default.removeItem(at: dir) }

    func path(_ name: String) -> JSONValue { .string(dir.appendingPathComponent(name).path) }

    /// A 30' × 20' box with a partition at x = 12', a door and a window, a floor and two rooms; Level 1's plan active.
    static func project() async throws -> Fixture {
        let f = try Fixture()
        let t = f.t
        try await t.call("create_project", ["name": "Fixture"])
        f.walls = ids(try await t.call("create_walls", ["level": "Level 1", "points": [[0, 0], [0, 20], [30, 20], [30, 0]], "closed": true])["walls"])
        f.partition = ids(try await t.call("create_walls", ["level": "Level 1", "type": "Generic - 6\"", "segments": [[[12, 0], [12, 20]]]])["walls"])[0]
        f.doors = ids(try await t.call("place_doors", ["doors": [["wall": .int(f.walls[3]), "offset": 20], ["wall": .int(f.partition), "offset": 10]]])["doors"])
        f.windows = ids(try await t.call("place_windows", ["windows": [["wall": .int(f.walls[1]), "offset": 15]]])["windows"])
        try await t.call("create_floor", ["level": "Level 1"])
        f.rooms = ids(try await t.call("place_rooms", ["level": "Level 1", "auto": true])["rooms"])
        try await t.call("open_view", ["view": "Level 1"])
        return f
    }

    /// A 36" × 24" × 34" base cabinet: sides, top, bottom on a plinth, a shelf and a back.
    static func furniture() async throws -> Fixture {
        let f = try Fixture()
        try await f.t.call("create_furniture", ["name": "Cabinet", "category": "casework", "width": 36, "depth": 24, "height": 34])
        let r = try await f.t.call("add_furniture_parts", ["parts": [
            ["kind": "sides", "ref": "sides"], ["kind": "top", "ref": "top"], ["kind": "bottom", "z": 4, "ref": "bottom"],
            ["kind": "shelf", "z": 18, "ref": "shelf"], ["kind": "back", "at": [0, 18]], ["kind": "plinth", "host": "bottom"],
        ]])
        for p in r["parts"]?.arrayValue ?? [] { if let ref = p["ref"]?.stringValue, let id = p["ids"]?.arrayValue?.first?.intValue { f.parts[ref] = id } }
        return f
    }

    /// A project with a family open in file mode's Family Editor.
    static func family() async throws -> Fixture {
        let f = try Fixture()
        try await f.t.call("create_project", ["name": "Host"])
        try await f.t.call("create_family", ["name": "Box", "template": "generic_model"])
        return f
    }
}

typealias Setup = @MainActor (Fixture) async throws -> JSONValue

@MainActor
@Suite("MCP tools coverage", .serialized)
struct MCPToolsCoverageTests {
    /// Minimal valid input per tool, with the document kind it runs in.
    static let minimal: [String: (DocumentMode, Setup)] = [
        // Document
        "arcus_status": (.project, { _ in [:] }),
        "context_summary": (.project, { _ in [:] }),
        "create_project": (.none, { _ in ["name": "New"] }),
        "create_furniture": (.none, { _ in ["name": "Piece"] }),
        "create_family": (.none, { _ in ["name": "Fam"] }),
        "open_document": (.project, { f in let p = f.path("Open.arcus"); try await f.t.call("save", ["path": p]); return ["path": p] }),
        "save": (.project, { f in ["path": f.path("Saved")] }),
        "set_project_info": (.project, { _ in ["name": "Renamed", "number": "P-1"] }),
        "undo": (.project, { _ in [:] }),
        "redo": (.project, { f in try await f.t.call("undo"); return [:] }),
        // Architecture
        "add_level": (.project, { _ in ["levels": [["name": "Level 3", "elevation": 30]]] }),
        "add_grid": (.project, { _ in ["x": [0, 12, 30], "y": [0, 20]] }),
        "create_walls": (.project, { _ in ["points": [[40, 0], [50, 0]]] }),
        "place_doors": (.project, { f in ["doors": [["wall": .int(f.walls[0])]]] }),
        "place_windows": (.project, { f in ["windows": [["wall": .int(f.walls[2])]]] }),
        "create_floor": (.project, { _ in ["level": "Level 2", "boundary": [[0, 0], [30, 0], [30, 20], [0, 20]]] }),
        "create_ceiling": (.project, { _ in ["level": "Level 1", "all_rooms": true] }),
        "create_roof": (.project, { _ in ["level": "Level 2", "from_walls_of": "Level 1", "shape": "gable"] }),
        "add_stair": (.project, { _ in ["start": [3, 3], "direction": "north"] }),
        "add_railing": (.project, { _ in ["path": [[0, 25], [10, 25]]] }),
        "place_rooms": (.project, { _ in ["rooms": [["name": "Porch", "point": [5, 25]]], "tag": false] }),
        "place_components": (.project, { _ in ["components": [["family": "Desk", "point": [5, 5]]]] }),
        "create_curtain_wall": (.project, { _ in ["points": [[40, 0], [55, 0]], "vertical_spacing": 5] }),
        "add_curtain_grids": (.project, { f in
            let w = ids(try await f.t.call("create_curtain_wall", ["points": [[40, 0], [55, 0]]])["walls"])[0]
            return ["wall": .int(w), "vertical": [3, 6]]
        }),
        "place_columns": (.project, { _ in ["points": [[0, 0], [30, 0]]] }),
        "create_beams": (.project, { _ in ["level": "Level 2", "segments": [[[0, 0], [30, 0]]]] }),
        "create_stair": (.project, { _ in ["runs": [["start": [3, 3], "direction": "north"], ["start": [7, 12], "direction": "south"]]] }),
        "create_ramp": (.project, { _ in ["path": [[40, 0], [40, 40]]] }),
        "create_opening": (.project, { f in ["kind": "wall", "wall": .int(f.walls[2]), "offset": 5, "width": 3] }),
        "place_areas": (.project, { _ in [:] }),
        "add_room_separators": (.project, { _ in ["segments": [[[20, 0], [20, 20]]]] }),
        "add_model_lines": (.project, { _ in ["segments": [[[0, -5], [30, -5]]]] }),
        "create_toposolid": (.project, { _ in ["outline": [[-20, -20], [60, -20], [60, 50], [-20, 50]], "elevation": -1] }),
        "create_building_pad": (.project, { _ in ["boundary": [[0, 0], [30, 0], [30, 20], [0, 20]]] }),
        "create_mass": (.project, { _ in ["boundary": [[40, 0], [60, 0], [60, 20], [40, 20]], "height": 30] }),
        // Annotation
        "add_dimensions": (.project, { _ in ["view": "Level 1", "auto": true] }),
        "add_tags": (.project, { _ in ["view": "Level 1"] }),
        "add_text": (.project, { _ in ["notes": [["text": "NOTE", "point": [5, 5]]]] }),
        "add_detail_lines": (.project, { _ in ["segments": [[[0, -3], [10, -3]]]] }),
        "add_region": (.project, { _ in ["boundary": [[1, 1], [4, 1], [4, 4], [1, 4]]] }),
        "place_detail_components": (.project, { f in
            let types = try await f.t.call("list_types", ["category": "detailComponents"])
            return ["points": [[2, 2]], "type": types["types"]?.arrayValue?.first?["id"] ?? .null]
        }),
        "add_spot_dimensions": (.project, { _ in ["points": [[5, 5]]] }),
        "add_keynotes": (.project, { f in ["elements": [.int(f.walls[0])], "kind": "element"] }),
        "create_legend": (.project, { _ in ["category": "doors"] }),
        "add_revision_cloud": (.project, { f in try await f.t.call("add_revision", ["description": "Issued"]); return ["boundary": [[1, 1], [6, 1], [6, 6], [1, 6]]] }),
        "arrange_dimensions": (.project, { f in try await f.t.call("add_dimensions", ["view": "Level 1", "auto": true]); return ["view": "Level 1"] }),
        // Views & sheets
        "create_views": (.project, { _ in ["views": [["kind": "section", "start": [-5, 10], "end": [35, 10]], ["kind": "drafting"], ["kind": "callout", "parent": "Level 1", "rect": [[0, 0], [12, 10]]]]] }),
        "create_sheet": (.project, { _ in ["number": "A101", "name": "Plan", "views": [["view": "Level 1"]]] }),
        "duplicate_view": (.project, { _ in ["view": "Level 1", "mode": "with_detailing"] }),
        "set_view_properties": (.project, { _ in ["view": "Level 1", "scale": 96, "detail_level": "fine", "cut_plane": 5] }),
        "apply_view_template": (.project, { _ in ["create_from": "Level 1", "name": "Plan Template", "views": ["Level 2"]] }),
        "set_visibility_graphics": (.project, { f in ["categories": ["furniture": ["halftone": true], "rooms": ["visible": false]], "elements": [.int(f.walls[0])], "element_override": ["color": "red"]] }),
        "add_view_filter": (.project, { _ in ["name": "Thin Walls", "categories": ["walls"], "rules": [["parameter": "Comments", "op": "has_value"]], "override": ["color": "#FF0000"]] }),
        "place_on_sheet": (.project, { f in try await f.t.call("create_sheet", ["number": "A101", "name": "Plans"]); return ["sheet": "A101", "views": [["view": "Level 2"]]] }),
        "set_sheet_info": (.project, { f in try await f.t.call("create_sheet", ["number": "A101", "name": "Plans"]); return ["drawn_by": "AI", "issue_date": "2026-10-20"] }),
        "add_revision": (.project, { f in try await f.t.call("create_sheet", ["number": "A101", "name": "Plans"]); return ["description": "Issued for review", "sheets": ["A101"]] }),
        "duplicate_sheet": (.project, { f in try await f.t.call("create_sheet", ["number": "A101", "name": "Plans", "views": [["view": "Level 1"]]]); return ["sheet": "A101", "with_detailing": true] }),
        "create_sheet_set": (.project, { f in try await f.t.call("create_sheet", ["number": "A101", "name": "Plans"]); return ["name": "Issue"] }),
        // Schedules
        "create_schedule": (.project, { _ in ["kind": "category", "category": "walls", "fields": ["Type", "Length", "Count"], "name": "Walls"] }),
        "get_schedule": (.project, { f in try await f.t.call("create_schedule", ["kind": "doors"]); return ["schedule": "Door Schedule"] }),
        "edit_schedule": (.project, { f in try await f.t.call("create_schedule", ["kind": "doors"]); return ["schedule": "Door Schedule", "add_fields": ["Count"], "sort_by": ["Mark"]] }),
        // Exports
        "render_view": (.project, { f in ["view": "Level 1", "path": f.path("plan.png"), "width": 400] }),
        "export_pdf": (.project, { f in try await f.t.call("create_sheet", ["number": "A101", "name": "Plan", "views": [["view": "Level 1"]]]); return ["path": f.path("set.pdf")] }),
        "export_dwg": (.project, { f in ["views": ["Level 1"], "folder": f.path("cad"), "format": "dxf"] }),
        "export_image": (.project, { f in ["folder": f.path("img"), "width": 400] }),
        "export_ifc": (.project, { f in ["path": f.path("model.ifc")] }),
        "export_schedule_csv": (.project, { f in try await f.t.call("create_schedule", ["kind": "doors"]); return ["schedule": "Door Schedule", "path": f.path("doors.csv")] }),
        "export_cnc": (.furniture, { f in ["folder": f.path("cnc")] }),
        // Family Editor
        "family_info": (.family, { _ in [:] }),
        "add_family_parameter": (.family, { _ in ["parameters": [["name": "Lip", "type": "length", "value": "2\""], ["name": "Show Lip", "type": "yes_no"]]] }),
        "set_family_type": (.family, { _ in ["new": "Large"] }),
        "add_reference_plane": (.family, { _ in ["planes": [["name": "Inset", "axis": "x", "offset": "3\""]]] }),
        "add_form": (.family, { _ in ["kind": "extrusion", "z_max": "1'"] }),
        "edit_form": (.family, { f in try await f.t.call("add_form", ["name": "Block"]); return ["forms": ["Block"], "visible_at": ["medium", "fine"], "visibility_parameter": "Show Block"] }),
        "add_family_dimension": (.family, { f in
            try await f.t.call("add_reference_plane", ["planes": [["name": "A", "axis": "x", "offset": 0.5], ["name": "B", "axis": "x", "offset": 1.5]]])
            return ["plane_a": "A", "plane_b": "B", "label": "Gap"]
        }),
        "add_nested_family": (.family, { _ in ["family": "Desk", "point": [0, 0]] }),
        "delete_family_item": (.family, { f in try await f.t.call("add_form", ["name": "Temp"]); return ["forms": ["Temp"]] }),
        "flex_family": (.family, { _ in [:] }),
        "load_family_into_project": (.family, { _ in ["force": true] }),
        // Furniture
        "set_furniture_size": (.furniture, { _ in ["width": 30] }),
        "add_furniture_parts": (.furniture, { _ in ["parts": [["kind": "shelf", "z": 26]]] }),
        "add_furniture_form": (.furniture, { _ in ["kind": "extrusion", "profile": [[-6, -6], [6, -6], [6, 6], [-6, 6]], "w0": 34, "w1": 36] }),
        "edit_furniture_part": (.furniture, { f in ["action": "opening", "parts": [.int(f.parts["sides"] ?? 0)], "s0": 4, "s1": 8, "t0": 10, "t1": 14] }),
        "add_bays": (.furniture, { _ in ["auto": true] }),
        "add_fronts": (.furniture, { f in try await f.t.call("add_bays", ["auto": true]); return ["kind": "door"] }),
        "add_hardware": (.furniture, { f in try await f.t.call("add_bays", ["auto": true]); try await f.t.call("add_fronts", ["kind": "door"]); return ["action": "handle"] }),
        "set_joint": (.furniture, { _ in ["list": true] }),
        "set_joint_rules": (.furniture, { _ in ["rules": [["pair": "side_top", "type": "dado"]]] }),
        "search_components": (.furniture, { _ in ["query": "hinge"] }),
        "place_library_component": (.furniture, { f in
            try await f.t.call("add_bays", ["auto": true])
            let fr = ids(try await f.t.call("add_fronts", ["kind": "door"])["fronts"])
            return ["component": "knob", "host": .int(fr[0])]
        }),
        "replace_components": (.furniture, { f in
            try await f.t.call("add_bays", ["auto": true]); try await f.t.call("add_fronts", ["kind": "door"]); try await f.t.call("add_hardware", ["action": "handle"])
            let hw = f.t.model.elements(.furnitureHardware).filter { !$0.isType }.prefix(1).map { JSONValue.int(Int($0.id.raw)) }
            return ["elements": .array(hw), "component": "knob"]
        }),
        "insert_assembly": (.furniture, { _ in ["list": true] }),
        "set_stock_sheets": (.furniture, { _ in ["sizes": [["name": "4x8", "length": 96, "width": 48]], "kerf": 0.125] }),
        "fabrication_report": (.furniture, { _ in [:] }),
        "create_shop_drawings": (.furniture, { _ in [:] }),
        "set_furniture_parameter": (.furniture, { _ in ["name": "Toe Kick", "value": 4] }),
        "flex_furniture": (.furniture, { _ in [:] }),
        "list_furniture_library": (.project, { _ in ["search": "table"] }),
        "load_furniture_piece": (.project, { _ in ["piece": "Side Table", "into": "project", "point": [5, 5]] }),
        // Edit
        "set_parameters": (.project, { f in ["elements": [.int(f.walls[0])], "parameters": ["Comments": "Checked"]] }),
        "move_elements": (.project, { f in ["elements": [.int(f.partition)], "by": [1, 0]] }),
        "delete_elements": (.project, { f in ["elements": [.int(f.windows[0])]] }),
        "copy_elements": (.project, { f in ["elements": [.int(f.partition)], "by": [4, 0], "count": 2] }),
        "rotate_elements": (.project, { f in ["elements": [.int(f.rooms[0])], "angle": 15] }),
        "mirror_elements": (.project, { f in ["elements": [.int(f.partition)], "axis": [[15, 0], [15, 20]]] }),
        "array_elements": (.project, { f in ["elements": [.int(f.partition)], "count": 3, "by": [4, 0]] }),
        "align_elements": (.project, { f in
            let w = ids(try await f.t.call("create_walls", ["segments": [[[5, 30], [5, 40]]]])["walls"])[0]
            return ["reference": .int(f.walls[0]), "elements": [.int(w)]]
        }),
        "offset_elements": (.project, { f in ["elements": [.int(f.partition)], "distance": 2] }),
        "trim_extend": (.project, { f in
            let a = ids(try await f.t.call("create_walls", ["segments": [[[40, 0], [48, 0]], [[50, 2], [50, 10]]]])["walls"])
            return ["elements": .array(a.map { .int($0) })]
        }),
        "split_element": (.project, { f in ["element": .int(f.walls[2]), "offset": 5] }),
        "join_geometry": (.project, { f in ["elements": [.int(f.walls[0]), .int(f.walls[1])], "unjoin": true] }),
        "change_type": (.project, { f in ["elements": [.int(f.partition)], "type": "Generic - 8\""] }),
        "pin_elements": (.project, { f in ["elements": [.int(f.walls[0])]] }),
        "flip_elements": (.project, { f in ["elements": [.int(f.doors[0])]] }),
        "attach_walls": (.project, { f in
            let r = try await f.t.call("create_roof", ["level": "Level 2", "from_walls_of": "Level 1", "shape": "gable"])
            return ["elements": .array(f.walls.map { .int($0) }), "to": r["roof"] ?? .null]
        }),
        "group_elements": (.project, { f in ["elements": [.int(f.partition)], "name": "Partition"] }),
        // Selection & navigation
        "get_selection": (.project, { f in try await f.t.call("select_elements", ["category": "doors"]); return [:] }),
        "select_elements": (.project, { _ in ["category": "walls", "level": "Level 1"] }),
        "hide_isolate": (.project, { f in ["action": "isolate", "elements": [.int(f.walls[0])]] }),
        "open_view": (.project, { _ in ["view": "Level 2"] }),
        "zoom_to": (.project, { _ in [:] }),
        "set_3d_view": (.project, { _ in ["orientation": "iso_ne", "section_box": "level", "level": "Level 1"] }),
        // Query & checks
        "query_model": (.project, { _ in ["what": "here"] }),
        "list_types": (.project, { _ in [:] }),
        "list_families": (.project, { _ in ["search": "bed"] }),
        "model_health": (.project, { _ in [:] }),
        "check_clashes": (.project, { _ in [:] }),
        "check_rooms": (.project, { _ in [:] }),
        "check_parts": (.furniture, { _ in [:] }),
        "verify_drawing": (.project, { _ in ["view": "Level 1", "image": true, "width": 400] }),
        // Commands
        "list_commands": (.project, { _ in ["search": "wall"] }),
        "find_tools": (.project, { _ in ["search": "curtain grid"] }),
        "run_command": (.project, { _ in ["command": "Select All"] }),
    ]

    static func fixture(_ mode: DocumentMode) async throws -> Fixture {
        switch mode {
        case .project: try await Fixture.project()
        case .furniture: try await Fixture.furniture()
        case .family: try await Fixture.family()
        case .none: try Fixture()
        }
    }

    @Test func everyToolHasAMinimalCaseAndRunsInItsMode() async throws {
        let names = ArcusToolCatalog.all.map(\.name)
        #expect(Set(names).count == names.count, "tool names are unique")
        for n in names { #expect(Self.minimal[n] != nil, "no minimal case for \(n)") }
        for n in Self.minimal.keys { #expect(names.contains(n), "minimal case for a tool that doesn't exist: \(n)") }
        var failures: [String] = []
        for spec in ArcusToolCatalog.all {
            guard let (mode, setup) = Self.minimal[spec.name] else { continue }
            let f = try await Self.fixture(mode)
            #expect(spec.modes.isEmpty || spec.modes.contains(mode), "\(spec.name) runs in \(mode) but declares \(spec.modes)")
            let args: JSONValue
            do { args = try await setup(f) } catch { failures.append("\(spec.name) setup: \(error)"); continue }
            let r = await f.t.box.callTool(spec.name, arguments: args.objectValue ?? [:])
            if r.isError { failures.append("\(spec.name): \(r.text)"); continue }
            let json = try JSONValue.parse(r.text)
            if ProcessInfo.processInfo.environment["ARCUS_TOOL_DUMP"] != nil { print("TOOLDUMP \(spec.name): \(r.text.prefix(700))") }
            if spec.risk == .edit && json["confirm_required"] == nil && args["list"]?.boolValue != true, !["set_3d_view", "hide_isolate", "run_command"].contains(spec.name) {
                #expect(json["verification"]?["ok"]?.boolValue != nil, "\(spec.name) has no verification block: \(r.text.prefix(300))")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) tools failed:\n\(failures.joined(separator: "\n"))")
    }

    @Test func missingRequiredArgumentsSayWhatToGive() async throws {
        var silent: [String] = []
        for spec in ArcusToolCatalog.all where !spec.requiredNames.isEmpty {
            guard let (mode, _) = Self.minimal[spec.name] else { continue }
            let f = try await Self.fixture(mode)
            let r = await f.t.box.callTool(spec.name, arguments: [:])
            if !r.isError { silent.append("\(spec.name) accepted {}"); continue }
            if !spec.requiredNames.contains(where: { r.text.contains($0) }) { silent.append("\(spec.name): “\(r.text)” names none of \(spec.requiredNames)") }
        }
        #expect(silent.isEmpty, "\(silent.joined(separator: "\n"))")
    }

    @Test func badInputsGiveActionableErrors() async throws {
        let f = try await Fixture.project()
        let t = f.t
        #expect(await t.fail("change_type", ["elements": [.int(f.partition)], "type": "Unobtanium"]).contains("Closest:"))
        #expect(await t.fail("open_view", ["view": "Level 9"]).contains("Views:"))
        #expect(await t.fail("run_command", ["command": "Teleport"]).contains("list_commands"))
        #expect(await t.fail("run_command", ["command": "purgeUnused"]).contains("confirm: true"))
        #expect(await t.fail("select_elements", ["category": "unicorns"]).contains("Unknown category"))
        #expect(await t.fail("place_on_sheet", ["sheet": "Z999", "views": [["view": "Level 1"]]]).contains("No sheet"))
        #expect(await t.fail("set_view_properties", ["view": "Level 1", "cut_plane": 50, "top": 4]).contains("top ≥ cut plane"))
        #expect(await t.fail("add_view_filter", ["name": "X", "categories": ["walls"], "rules": [["parameter": "Moodiness"]]]).contains("Parameters:"))
        #expect(await t.fail("add_furniture_parts", ["parts": [["kind": "shelf"]]]).contains("Furniture documents"))
        #expect(await t.fail("family_info", [:]).contains("family"))
        #expect(await t.fail("split_element", ["element": .int(f.walls[0]), "offset": 500]).contains("between 0 and the length"))
        #expect(await t.fail("array_elements", ["elements": [.int(f.partition)], "count": 1]).contains("count must be"))
        // Deleting a lot asks first and changes nothing.
        let before = t.model.count
        let preview = try await t.call("delete_elements", ["elements": .array(f.walls.map { .int($0) })])
        #expect(preview["confirm_required"]?.boolValue == true)
        #expect(t.model.count == before)
        let done = try await t.call("delete_elements", ["elements": .array(f.walls.map { .int($0) }), "confirm": true])
        #expect((done["removed_total"]?.intValue ?? 0) > 5)
    }

    @Test func everyToolDeclaresARiskAndFlagsAgree() {
        for t in ArcusToolCatalog.all {
            #expect(ToolRisk.allCases.contains(t.risk))
            #expect(t.readOnly == (t.risk == .read || (t.risk == .file && !t.changesDocument)), "\(t.name)")
            #expect(t.destructive == (t.risk == .destructive), "\(t.name)")
            #expect(t.description.count > 30, "\(t.name) needs a description")
            #expect(t.listing["annotations"]?["readOnlyHint"]?.boolValue == t.readOnly)
        }
        #expect(ArcusToolCatalog.spec("delete_elements")?.risk == .destructive)
        #expect(ArcusToolCatalog.spec("save")?.risk == .file)
        #expect(ArcusToolCatalog.spec("export_pdf")?.risk == .file)
        #expect(ArcusToolCatalog.spec("set_project_info")?.risk == .projectWide)
        #expect(ArcusToolCatalog.spec("query_model")?.risk == .read)
        #expect(ArcusToolbox.risk(of: "set_parameters", arguments: ["type": true]) == .projectWide)
        #expect(ArcusToolbox.risk(of: "run_command", arguments: ["command": "save"]) == .file)
        #expect(ArcusToolbox.risk(of: "run_command", arguments: ["command": "Delete"]) == .destructive)
        #expect(ArcusToolbox.risk(of: "run_command", arguments: ["command": "tagAll"]) == .edit)
    }

    @Test func toolsAreFilteredByDocumentKind() async throws {
        let project = Set(ArcusToolCatalog.tools(for: .project).map(\.name))
        let furniture = Set(ArcusToolCatalog.tools(for: .furniture).map(\.name))
        let family = Set(ArcusToolCatalog.tools(for: .family).map(\.name))
        let none = Set(ArcusToolCatalog.tools(for: .none).map(\.name))
        #expect(project.contains("create_walls") && !furniture.contains("create_walls") && !family.contains("create_walls"))
        #expect(furniture.contains("add_fronts") && !project.contains("add_fronts"))
        #expect(family.contains("add_form") && !project.contains("add_form") && !furniture.contains("add_form"))
        #expect(none.contains("create_project") && !none.contains("create_walls"))
        #expect(project.count < ArcusToolCatalog.all.count && family.count < 30)
        let core = ArcusToolCatalog.tools(for: .project, coreOnly: true)
        #expect(core.count < 50 && core.contains { $0.name == "find_tools" } && core.contains { $0.name == "create_walls" })
        #expect(ArcusToolCatalog.tools(for: .family, coreOnly: true).contains { $0.name == "add_form" })
        // Tools that need a selection only appear with one.
        let noSel = ArcusToolCatalog.tools(for: .project, context: ToolCatalogContext(viewKind: .floorPlan))
        #expect(noSel.allSatisfy { !$0.needsSelection })
        // The toolbox reports the front document's kind, and refuses tools of another kind with what to do instead.
        let f = try await Fixture.furniture()
        #expect(f.t.box.mode == .furniture)
        #expect(f.t.box.availableTools().contains { $0.name == "add_bays" })
        #expect(await f.t.fail("create_walls", ["points": [[0, 0], [1, 0]]]).contains("Furniture"))
        let fam = try await Fixture.family()
        #expect(fam.t.box.mode == .family)
        // Group counts are what Docs/MCP.md lists.
        let counts = Dictionary(uniqueKeysWithValues: ArcusToolCatalog.countsByGroup)
        #expect(counts.values.reduce(0, +) == ArcusToolCatalog.all.count)
        #expect(ArcusToolCatalog.all.count >= 120)
    }

    /// ARCUS_TOOL_DUMP=1 writes the tool table for Docs/MCP.md to /tmp/arcus-aitools/tools.md.
    @Test func toolTableForTheDocs() throws {
        guard ProcessInfo.processInfo.environment["ARCUS_TOOL_DUMP"] != nil else { return }
        var md = ""
        for (g, n) in ArcusToolCatalog.countsByGroup {
            md += "\n**\(g.rawValue)** (\(n))\n\n| Tool | Risk | Documents | What it does |\n|---|---|---|---|\n"
            for t in ArcusToolCatalog.all where t.group == g {
                let modes = t.modes.isEmpty ? "any" : t.modes.map(\.rawValue).sorted().joined(separator: ", ")
                let first = t.description.components(separatedBy: ". ").first ?? t.description
                md += "| `\(t.name)` | \(t.risk.rawValue) | \(modes) | \(first.replacingOccurrences(of: "|", with: "/")). |\n"
            }
        }
        md += "\nTotal: \(ArcusToolCatalog.all.count)\n"
        for mode in [DocumentMode.none, .project, .furniture, .family] {
            let list = ArcusToolCatalog.tools(for: mode)
            let core = ArcusToolCatalog.tools(for: mode, coreOnly: true)
            md += "\n\(mode.rawValue): \(list.count) tools, \(JSONValue.array(list.map(\.listing)).jsonText.count) characters; core \(core.count) tools, \(JSONValue.array(core.map(\.listing)).jsonText.count) characters"
        }
        try FileManager.default.createDirectory(atPath: "/tmp/arcus-aitools", withIntermediateDirectories: true)
        try md.write(toFile: "/tmp/arcus-aitools/tools.md", atomically: true, encoding: .utf8)
    }

    @Test func toolUndoStepsNestInsideThePromptGroup() async throws {
        let f = try await Fixture.project()
        let um = f.t.host.session!.undoManager
        let walls = f.t.model.elements(.walls).count
        um.beginUndoGrouping()
        try await f.t.call("create_walls", ["points": [[40, 0], [50, 0], [50, 10]]])
        try await f.t.call("place_columns", ["points": [[40, 0]]])
        try await f.t.call("add_text", ["notes": [["text": "A", "point": [45, 5]]]])
        um.setActionName("AI: add an annex")
        um.endUndoGrouping()
        #expect(f.t.model.elements(.walls).count == walls + 2)
        #expect(um.undoActionName == "AI: add an annex")
        um.undo()
        #expect(f.t.model.elements(.walls).count == walls, "one undo reverts the whole prompt")
        #expect(f.t.model.elements(.columns).isEmpty)
        um.redo()
        #expect(f.t.model.elements(.columns).count == 1)
    }

    @Test func contextSummaryIsShortAndUseful() async throws {
        let f = try await Fixture.project()
        try await f.t.call("select_elements", ["category": "doors"])
        let s = try await f.t.call("context_summary")
        let text = try #require(s["text"]?.stringValue)
        #expect(text.contains("Level 1") && text.contains("Selected 2") && text.contains("Active view"))
        #expect(text.count < 3000, "about 1–2k tokens at most: \(text.count) characters")
        #expect(f.t.box.contextSummaryText() == text)
        let fam = try await Fixture.family()
        #expect(fam.t.box.contextSummaryText().contains("Family Editor"))
    }

    // MARK: Scripted flows

    @Test func housePlanSheetDimensionsAndPDF() async throws {
        let f = try Fixture()
        let t = f.t
        try await t.call("create_project", ["name": "Cottage"])
        try await t.call("create_walls", ["points": [[0, 0], [0, 28], [36, 28], [36, 0]], "closed": true])
        let part = ids(try await t.call("create_walls", ["segments": [[[16, 0], [16, 28]]], "type": "Generic - 6\""])["walls"])[0]
        let ext = t.model.elements(.walls).filter { $0.id.raw != UInt64(part) }.map { Int($0.id.raw) }
        try await t.call("place_doors", ["doors": [["wall": .int(ext[3]), "offset": 8], ["wall": .int(part), "offset": 14]]])
        try await t.call("place_windows", ["windows": [["wall": .int(ext[1]), "offset": 9], ["wall": .int(ext[1]), "offset": 27]]])
        try await t.call("create_floor", [:])
        try await t.call("create_roof", ["level": "Level 2", "from_walls_of": "Level 1", "shape": "hip"])
        let rooms = try await t.call("place_rooms", ["auto": true])
        #expect(rooms["rooms"]?.arrayValue?.count == 2)
        let dims = try await t.call("add_dimensions", ["view": "Level 1", "auto": true])
        #expect(dims["verification"]?["ok"]?.boolValue == true, "\(dims)")
        try await t.call("add_tags", ["view": "Level 1"])
        try await t.call("create_views", ["views": [["kind": "section", "start": [-5, 14], "end": [41, 14], "name": "Section A"]]])
        try await t.call("add_dimensions", ["view": "Section A", "auto": true])
        try await t.call("set_project_info", ["name": "Cottage", "number": "24-01", "issue_date": "2026-10-20"])
        try await t.call("create_sheet", ["number": "A101", "name": "Plan and Section", "views": [["view": "Level 1"], ["view": "Section A"]]])
        try await t.call("set_sheet_info", ["sheets": ["A101"], "drawn_by": "Arcus AI"])
        let check = try await t.call("verify_drawing", ["view": "A101"])
        #expect(check["ok"]?.boolValue == true, "\(check)")
        try await t.call("create_sheet_set", ["name": "Permit"])
        let pdf = try await t.call("export_pdf", ["sheet_set": "Permit", "path": f.path("Cottage.pdf"), "colors": "black_lines"])
        #expect(pdf["pages"]?.intValue == 1)
        #expect(FileManager.default.fileExists(atPath: pdf["path"]?.stringValue ?? ""))
        // A second export doesn't overwrite the first.
        let again = try await t.call("export_pdf", ["sheet_set": "Permit", "path": f.path("Cottage.pdf")])
        #expect(again["path"]?.stringValue != pdf["path"]?.stringValue)
    }

    @Test func cabinetWithFrontsHardwareAndShopDrawings() async throws {
        let f = try await Fixture.furniture()
        let t = f.t
        let bays = try await t.call("add_bays", ["auto": true])
        let bayIDs = ids(bays["bays"])
        #expect(bayIDs.count == 2, "upper and lower opening: \(bays)")
        try await t.call("add_fronts", ["kind": "drawer", "bays": [.int(bayIDs[0])], "count": 2])
        try await t.call("add_fronts", ["kind": "door", "bays": [.int(bayIDs[1])]])
        #expect(t.model.elements(.furnitureFronts).count == 3)
        let hw = try await t.call("add_hardware", ["action": "handle"])
        #expect((hw["placed"]?.arrayValue?.count ?? 0) == 3, "a handle on each front: \(hw)")
        try await t.call("add_hardware", ["action": "hinges"])
        try await t.call("set_joint_rules", ["rules": [["pair": "side_top", "type": "dowel"]]])
        let report = try await t.call("fabrication_report", ["what": "parts"])
        #expect((report["part_count"]?.intValue ?? 0) >= 6)
        let shop = try await t.call("create_shop_drawings")
        #expect((shop["sheets"]?.arrayValue?.count ?? 0) >= 4, "\(shop)")
        let flex = try await t.call("flex_furniture")
        #expect(flex["ok"]?.boolValue == true, "\(flex)")
        let pdf = try await t.call("export_pdf", ["path": f.path("Cabinet.pdf")])
        #expect((pdf["pages"]?.intValue ?? 0) >= 4)
    }

    @Test func editTheSelectedWalls() async throws {
        let f = try await Fixture.project()
        let t = f.t
        try await t.call("select_elements", ["category": "walls", "level": "Level 1"])
        let sel = try await t.call("select_elements", ["ids": [.int(f.partition)], "mode": "remove"])
        #expect(sel["count"]?.intValue == 4, "the exterior walls: \(sel)")
        let got = try await t.call("get_selection")
        #expect(got["categories"]?["walls"]?.intValue == 4)
        try await t.call("change_type", ["type": "Exterior - Brick on CMU"])
        #expect(t.model.elements(.walls).filter { t.model.type(of: $0)?.name.contains("Brick") == true }.count == 4)
        try await t.call("set_parameters", ["parameters": ["Comments": "Brick veneer"]])
        #expect(t.model.elements(.walls).filter { $0.params[ParameterID("comments")]?.textValue == "Brick veneer" }.count == 4)
        let health = try await t.call("model_health")
        #expect(health["ok"]?.boolValue == true, "\(health)")
        try await t.call("pin_elements")
        #expect(t.model.elements(.walls).filter(\.pinned).count == 4)
    }

    @Test func fixADrawingWithOverlappingDimensions() async throws {
        let f = try await Fixture.project()
        let t = f.t
        try await t.call("add_dimensions", ["view": "Level 1", "auto": true])
        let second = try await t.call("add_dimensions", ["view": "Level 1", "auto": true, "offset": 4.2])
        #expect(second["verification"]?["ok"]?.boolValue == false, "the second set lands on the first")
        let before = try await t.call("verify_drawing", ["view": "Level 1"])
        let codes = Set((before["problems"]?.arrayValue ?? []).compactMap { $0["code"]?.stringValue })
        #expect(codes.contains("dimension.duplicate") || codes.contains("dimension.overlap"), "\(before)")
        #expect((before["problems"]?.arrayValue ?? []).contains { $0["fix_with"]?.stringValue == "arrange_dimensions" })
        let fixed = try await t.call("arrange_dimensions", ["view": "Level 1"])
        #expect(fixed["verification"]?["ok"]?.boolValue == true, "\(fixed)")
        let after = try await t.call("verify_drawing", ["view": "Level 1"])
        #expect(!(after["problems"]?.arrayValue ?? []).contains { ($0["code"]?.stringValue ?? "").hasPrefix("dimension.") }, "\(after)")
    }
}
