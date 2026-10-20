import Foundation

// MCP: the Arcus tool set as listed by tools/list (Docs/MCP.md §5). Descriptions are written for Claude: what the tool
// does, the units, and what comes back.

/// JSON Schema fragments.
enum S {
    static func desc(_ base: [String: JSONValue], _ d: String) -> JSONValue {
        var o = base
        if !d.isEmpty { o["description"] = .string(d) }
        return .object(o)
    }
    static func str(_ d: String = "") -> JSONValue { desc(["type": "string"], d) }
    static func num(_ d: String = "") -> JSONValue { desc(["type": "number"], d) }
    static func int(_ d: String = "") -> JSONValue { desc(["type": "integer"], d) }
    static func bool(_ d: String = "") -> JSONValue { desc(["type": "boolean"], d) }
    /// A length: a number in document units or text like 12'-6".
    static func len(_ d: String = "") -> JSONValue { desc(["type": ["number", "string"]], d) }
    static func ref(_ d: String = "") -> JSONValue { desc(["type": ["string", "integer"]], d) }
    static func oneOf(_ values: [String], _ d: String = "") -> JSONValue { desc(["type": "string", "enum": .array(values.map { .string($0) })], d) }
    static func point(_ d: String = "") -> JSONValue {
        desc(["type": "array", "items": ["type": ["number", "string"]], "minItems": 2, "maxItems": 2], d.isEmpty ? "[x, y] in plan" : d)
    }
    static func points(_ d: String = "") -> JSONValue { desc(["type": "array", "items": point()], d) }
    static func ids(_ d: String = "") -> JSONValue { desc(["type": "array", "items": ["type": "integer"]], d) }
    static func array(_ items: JSONValue, _ d: String = "") -> JSONValue { desc(["type": "array", "items": items], d) }
    static func object(_ props: [String: JSONValue], required: [String] = [], _ d: String = "") -> JSONValue {
        var o: [String: JSONValue] = ["type": "object", "properties": .object(props)]
        if !required.isEmpty { o["required"] = .array(required.map { .string($0) }) }
        return desc(o, d)
    }
    static let anyValue: JSONValue = ["type": ["string", "number", "boolean", "integer"]]
}

public enum ArcusToolCatalog {
    static let lengthNote = "Lengths: numbers are in the document unit (ft in Imperial projects, mm in Metric, in in Furniture) or text like 12'-6\"."

    /// Every tool, grouped (AITOOLS: the original tools with their group, risk and modes, then the batch's tools).
    public static let all: [ToolSpec] = core.map(annotated) + contextTools + architectureTools + annotationTools + viewTools + scheduleTools
        + exportTools + familyTools + furnitureTools + editTools + selectionTools + navigationTools + checkTools + commandTools

    /// Group, risk and document kinds of the original tools.
    static let coreMeta: [String: (ToolGroup, ToolRisk, Set<DocumentMode>)] = [
        "arcus_status": (.document, .read, []), "create_project": (.document, .file, []), "create_furniture": (.document, .file, []),
        "open_document": (.document, .file, []), "save": (.document, .file, .open), "set_project_info": (.document, .projectWide, .project),
        "undo": (.document, .destructive, .open), "redo": (.document, .edit, .open),
        "add_level": (.architecture, .edit, .project), "add_grid": (.architecture, .edit, .project), "create_walls": (.architecture, .edit, .project),
        "place_doors": (.architecture, .edit, .project), "place_windows": (.architecture, .edit, .project), "create_floor": (.architecture, .edit, .project),
        "create_ceiling": (.architecture, .edit, .project), "create_roof": (.architecture, .edit, .project), "add_stair": (.architecture, .edit, .project),
        "add_railing": (.architecture, .edit, .project), "place_rooms": (.architecture, .edit, .project), "place_components": (.architecture, .edit, .project),
        "set_parameters": (.edit, .edit, .model), "move_elements": (.edit, .edit, .model), "delete_elements": (.edit, .destructive, .model),
        "create_views": (.views, .edit, .model), "create_sheet": (.views, .edit, .model), "create_schedule": (.schedules, .edit, .model),
        "add_dimensions": (.annotation, .edit, .model), "add_tags": (.annotation, .edit, .model),
        "query_model": (.query, .read, .model), "list_types": (.query, .read, .model), "list_families": (.query, .read, .project),
        "render_view": (.exports, .read, .model), "export_pdf": (.exports, .file, .model), "export_dwg": (.exports, .file, .model),
        "set_furniture_size": (.furniture, .edit, .furniture), "add_furniture_parts": (.furniture, .edit, .furniture),
    ]

    static func annotated(_ t: ToolSpec) -> ToolSpec {
        var t = t
        guard let (g, r, m) = coreMeta[t.name] else { return t }
        t.group = g; t.risk = r; t.modes = m
        t.changesDocument = ["create_project", "create_furniture", "open_document", "save"].contains(t.name)
        return t
    }

    static let core: [ToolSpec] = [
        // MARK: Document
        ToolSpec("arcus_status", "Status", "Where tools run (file mode or the live Arcus app), the open document, its units and element counts, and what to do next. Call first.",
                 readOnly: true),
        ToolSpec("create_project", "Create Project",
                 "Start a new building project from a template and make it the current document. Architectural has wall/floor/roof/door/window types, Level 1, Level 2 and Roof with plans, 4 elevations, {3D}, schedules and a sheet. Optionally replace the template levels and save to a path (.arcus).",
                 properties: [
                    "name": S.str("Project name"),
                    "template": S.oneOf(["architectural", "empty"], "Default architectural"),
                    "units": S.oneOf(["imperial", "metric"], "Default imperial (feet and inches)"),
                    "levels": S.array(S.object(["name": S.str(), "elevation": S.len()], required: ["name", "elevation"]),
                                      "Replace the template levels, lowest first, e.g. [{name:'Ground Floor',elevation:0},{name:'Upper Floor',elevation:10},{name:'Roof',elevation:20}]"),
                    "path": S.str("Optional .arcus path to save to now, e.g. ~/Documents/Arcus/House.arcus"),
                 ], required: ["name"]),
        ToolSpec("create_furniture", "Create Furniture",
                 "Start a new Furniture or Casework document (.arcusfurniture) at a size, then add parts with add_furniture_parts. Furniture lengths are in inches. Reference planes: Left, Right, Front, Back, Bottom, Top (x across, y depth with front at -y, z up).",
                 properties: [
                    "name": S.str(), "category": S.oneOf(["furniture", "casework"], "Default furniture"),
                    "width": S.len("Default 36 in"), "depth": S.len("Default 18 in"), "height": S.len("Default 30 in"),
                    "path": S.str("Optional .arcusfurniture path to save to now"),
                 ], required: ["name"]),
        ToolSpec("open_document", "Open Document", "Open an .arcus or .arcusfurniture file and make it the current document.",
                 properties: ["path": S.str("File path; ~ is expanded")], required: ["path"]),
        ToolSpec("save", "Save", "Save the current document, optionally to a new path (the extension follows the document kind). Returns the path.",
                 properties: ["path": S.str("Optional path; required the first time in file mode")]),
        ToolSpec("set_project_info", "Set Project Information", "Set the project information shown in title blocks.",
                 properties: ["name": S.str(), "number": S.str(), "client": S.str(), "address": S.str(), "status": S.str(),
                              "issue_date": S.str(), "building_name": S.str(), "author": S.str(), "organization": S.str()]),

        // MARK: Datums
        ToolSpec("add_level", "Add Levels", "Add levels at elevations, each with a floor plan (and a ceiling plan if asked). Rename or move existing levels with set_parameters (Name, Elevation). " + lengthNote,
                 properties: ["levels": S.array(S.object(["name": S.str(), "elevation": S.len(), "ceiling_plan": S.bool("Default false")], required: ["name", "elevation"]))],
                 required: ["levels"]),
        ToolSpec("add_grid", "Add Grids", "Add structural grid lines: explicit lines, or vertical lines at x positions (named 1, 2, 3…) and horizontal lines at y positions (named A, B, C…) spanning the given extents. " + lengthNote,
                 properties: ["lines": S.array(S.object(["name": S.str(), "start": S.point(), "end": S.point()], required: ["start", "end"])),
                              "x": S.array(S.len(), "x positions of north–south grids"), "y": S.array(S.len(), "y positions of east–west grids"),
                              "extent": S.array(S.len(), "[min, max] the grid lines span (default 5 units past the outermost grids)")]),

        // MARK: Model
        ToolSpec("create_walls", "Create Walls",
                 "Create walls along a polyline (points, optionally closed) or a list of separate segments. Draw exterior loops clockwise so the exterior face is outside. Walls join automatically. Height: top_level (+ top_offset) or height (unconnected). " + lengthNote,
                 properties: [
                    "level": S.ref("Base level name or id (default lowest)"),
                    "type": S.ref("Wall type name, e.g. 'Generic - 8\"' (list_types category walls)"),
                    "points": S.points("Polyline vertices [[x,y],…]"), "closed": S.bool("Close the polyline back to the first point"),
                    "segments": S.array(S.points(), "Separate walls [[[x1,y1],[x2,y2]], …]"),
                    "top_level": S.ref("Top constraint level (default: the level above)"), "top_offset": S.len(), "height": S.len("Unconnected height when no level is above"),
                    "base_offset": S.len(), "location_line": S.oneOf(["centerline", "core_centerline", "exterior_face", "interior_face", "core_exterior", "core_interior"], "Default centerline"),
                    "structural": S.bool(), "room_bounding": S.bool("Default true"),
                 ]),
        ToolSpec("place_doors", "Place Doors",
                 "Place doors in walls. Give each door its host wall id and either offset (distance of the door centre from the wall's start) or point (snapped to the wall). " + lengthNote,
                 properties: ["doors": S.array(S.object([
                    "wall": S.int("Host wall id"), "offset": S.len("Centre distance from the wall start"), "point": S.point("Or a plan point on the wall"),
                    "type": S.ref("e.g. 'Single Panel 36x80' (list_types category doors)"), "mark": S.str(),
                    "flip_facing": S.bool("Swing to the other side"), "flip_hand": S.bool("Hinge on the other side"),
                 ], required: ["wall"]))], required: ["doors"]),
        ToolSpec("place_windows", "Place Windows", "Place windows in walls like place_doors, with sill height above the wall's base. " + lengthNote,
                 properties: ["windows": S.array(S.object([
                    "wall": S.int(), "offset": S.len(), "point": S.point(), "type": S.ref(), "sill_height": S.len("Default from the type, or 3' / 900 mm"), "mark": S.str(),
                    "flip_facing": S.bool(),
                 ], required: ["wall"]))], required: ["windows"]),
        ToolSpec("create_floor", "Create Floor", "Create a floor slab from a boundary, or from the walls of its level (interior faces by default; exterior for a slab under the walls). " + lengthNote,
                 properties: ["level": S.ref(), "type": S.ref(), "boundary": S.points("Closed loop [[x,y],…]"),
                              "from_walls": S.bool("Use the outline of the level's walls"), "edge": S.oneOf(["interior", "exterior"], "Wall face for from_walls (default interior)"),
                              "offset": S.len("Height offset from the level"), "structural": S.bool(), "name": S.str()]),
        ToolSpec("create_ceiling", "Create Ceiling", "Create ceilings at a height above the level: one from a boundary, or one per room (rooms ids, or all rooms of the level). " + lengthNote,
                 properties: ["level": S.ref(), "type": S.ref(), "boundary": S.points(), "rooms": S.ids("Room ids"), "all_rooms": S.bool("A ceiling in every room of the level"),
                              "height": S.len("Default 8' / 2700 mm")]),
        ToolSpec("create_roof", "Create Roof",
                 "Create a footprint roof on a level from a boundary or the level's walls (outer faces + overhang). Shapes: flat, shed (slopes up from the first edge), gable (slopes on the two long sides), hip (all sides slope). " + lengthNote,
                 properties: ["level": S.ref("Roof base level (usually the top level)"), "type": S.ref(), "boundary": S.points(), "from_walls_of": S.ref("Level whose walls give the footprint"),
                              "shape": S.oneOf(["flat", "shed", "gable", "hip"], "Default flat"), "slope": S.num("Degrees, default 22.6 (5:12)"),
                              "overhang": S.len("Eave overhang past the wall faces (default 0 flat, 1'-6\" / 450 mm sloped)"), "base_offset": S.len()]),
        ToolSpec("add_stair", "Add Stair",
                 "Add a stair from base_level to top_level. start is the centre of the first riser; direction is the direction of travel. Straight, L-shaped or U-shaped (turn left or right). Handrails on both sides unless railings is false. " + lengthNote,
                 properties: ["base_level": S.ref(), "top_level": S.ref(), "start": S.point(), "direction": S.ref("Degrees CCW from east or north/south/east/west"),
                              "shape": S.oneOf(["straight", "l_shaped", "u_shaped"]), "width": S.len("Run width, default 3' / 1000 mm"), "risers": S.int("Riser count (default from the max riser height)"),
                              "first_run_risers": S.int("Risers before the landing (L/U)"), "turn": S.oneOf(["left", "right"]), "type": S.ref(), "railings": S.bool("Default true"),
                              "railing_type": S.ref()],
                 required: ["start", "direction"]),
        ToolSpec("add_railing", "Add Railing", "Add a railing along a path on a level, or on both sides of a stair. " + lengthNote,
                 properties: ["level": S.ref(), "path": S.points(), "stair": S.int("Stair id: rails on both sides"), "type": S.ref("e.g. 'Guard - 42\"' or 'Handrail - 36\"'"),
                              "base_offset": S.len()]),
        ToolSpec("place_rooms", "Place Rooms",
                 "Place rooms. auto: one room in every enclosed region of the level that has none. Or rooms at points with names (and numbers). Tags them in the level's plan. Returns each room's area and whether it is bounded.",
                 properties: ["level": S.ref(), "auto": S.bool(), "rooms": S.array(S.object(["name": S.str(), "point": S.point(), "number": S.str(), "department": S.str(), "floor_finish": S.str()], required: ["point"])),
                              "tag": S.bool("Default true")]),
        ToolSpec("place_components", "Place Components",
                 "Place furniture, fixtures, casework, appliances, planting, cars… from the built-in library (loaded on first use; list_families to browse). facing: the direction the front faces (default south). " + lengthNote,
                 properties: ["components": S.array(S.object([
                    "family": S.str("Library item, e.g. 'Sofa - 3 Seat', 'Bed - US Standard', 'WC - Floor Mounted'"), "type": S.str("Size, e.g. 'Queen 60\" x 80\"'"),
                    "point": S.point(), "level": S.ref(), "facing": S.ref("north/south/east/west or degrees"), "rotation": S.num("Degrees, instead of facing"), "offset": S.len("Height above the level"),
                 ], required: ["family", "point"]))], required: ["components"]),
        ToolSpec("set_parameters", "Set Parameters",
                 "Set parameters by their Properties name on elements, e.g. {\"Name\":\"Kitchen\"}, {\"Mark\":\"D1\"}, {\"Top Offset\":\"-6\\\"\"}, {\"Sill Height\":\"3'\"}. Values are parsed like typed input. type:true sets type parameters (affects every instance).",
                 properties: ["elements": S.ids(), "parameters": S.object([:], "{parameter name: value}"), "type": S.bool()], required: ["elements", "parameters"]),
        ToolSpec("move_elements", "Move Elements", "Move elements by a plan vector (hosted doors and windows follow their walls). " + lengthNote,
                 properties: ["elements": S.ids(), "by": S.point("[dx, dy]")], required: ["elements", "by"]),
        ToolSpec("delete_elements", "Delete Elements", "Delete elements (and what depends on them, such as their doors and tags).", destructive: true,
                 properties: ["elements": S.ids()], required: ["elements"]),
        ToolSpec("undo", "Undo", "Undo the last tool calls (each editing call is one step, like ⌘Z).", destructive: true, properties: ["steps": S.int("Default 1")]),
        ToolSpec("redo", "Redo", "Redo steps undone with undo (each step is one tool call).", properties: ["steps": S.int("Default 1")]),

        // MARK: Documentation
        ToolSpec("create_views", "Create Views",
                 "Create views: floor_plan / ceiling_plan (level), three_d (optional section box of a level), section (start + end points; looks to the left of start→end unless flipped), elevation (point + facing direction it looks). " + lengthNote,
                 properties: ["views": S.array(S.object([
                    "kind": S.oneOf(["floor_plan", "ceiling_plan", "three_d", "section", "elevation"]), "name": S.str(), "level": S.ref(), "scale": S.int("1:scale, e.g. 48 for 1/4\" = 1'-0\", 96 for 1/8\""),
                    "start": S.point(), "end": S.point(), "flip": S.bool(), "depth": S.len("Section/elevation far clip"), "point": S.point(), "facing": S.ref("Direction the elevation looks"),
                    "cut_to_level": S.ref("3D: section box cutting above this level"),
                 ], required: ["kind"]))], required: ["views"]),
        ToolSpec("create_sheet", "Create Sheet",
                 "Create a sheet with a title block and place views and schedules on it. Without positions, they are laid out in a grid. position is [u, v] as fractions of the paper (0–1, origin bottom-left).",
                 properties: ["number": S.str("e.g. A101"), "name": S.str(), "paper": S.oneOf(["ARCH D", "ARCH E", "ARCH C", "ANSI B", "Letter", "A0", "A1", "A2", "A3", "A4"], "Default ARCH D (Imperial) or A1"),
                              "title_block": S.ref(), "views": S.array(S.object(["view": S.ref("View or schedule name/id"), "position": S.array(S.num())], required: ["view"])),
                              "schedules": S.array(S.ref(), "Schedule names to place")],
                 required: ["number", "name"]),
        ToolSpec("create_schedule", "Create Schedule", "Create a standard schedule: doors, windows, rooms, walls or sheets.",
                 properties: ["kind": S.oneOf(["doors", "windows", "rooms", "walls", "sheets"]), "name": S.str()], required: ["kind"]),
        ToolSpec("add_dimensions", "Add Dimensions",
                 "Dimension a plan view. auto: overall and wall-by-wall chains on all four sides of the building (orthogonal walls). Or one dimension between walls (faces or centre lines) through a point.",
                 properties: ["view": S.ref("Plan view"), "auto": S.bool(), "walls": S.ids("Walls to dimension between"),
                              "reference": S.oneOf(["centerline", "exterior_face", "interior_face"], "Default centerline"), "at": S.point("A point the dimension line passes through"),
                              "offset": S.len("Auto: distance of the first string from the outside wall faces (default 4' / 1200 mm)")],
                 required: ["view"]),
        ToolSpec("add_tags", "Add Tags", "Tag every untagged element of the given categories visible in a view (Tag All). Default doors, windows and rooms.",
                 properties: ["view": S.ref(), "categories": S.array(S.str(), "e.g. ['doors','windows','rooms','walls','furniture']")], required: ["view"]),

        // MARK: Query
        ToolSpec("query_model", "Query Model",
                 "Read the model. what: summary (levels, counts, units), levels, elements (by category, with key parameters), rooms (areas, bounded or not), views, sheets, schedules, warnings (model health), element (all parameters of ids).",
                 readOnly: true,
                 properties: ["what": S.oneOf(["summary", "levels", "elements", "rooms", "views", "sheets", "schedules", "warnings", "element"]),
                              "category": S.str("For elements: walls, doors, windows, floors, roofs, ceilings, stairs, railings, furniture, … or furniture parts (furniturePanels…)"),
                              "level": S.ref(), "ids": S.ids("For element"), "limit": S.int("Default 200")],
                 required: ["what"]),
        ToolSpec("list_types", "List Types", "List the types loaded in the document for a category (walls, floors, roofs, ceilings, doors, windows, stairs, railings, furniturePanels, …) or all categories.",
                 readOnly: true, properties: ["category": S.str()]),
        ToolSpec("list_families", "List Library Families", "Browse the built-in component library (furniture, casework, plumbing fixtures, appliances, planting, parking, lighting…) with each family's sizes. Doors and windows are already loaded: use list_types.",
                 readOnly: true, properties: ["category": S.str(), "search": S.str("Words that must all match, e.g. 'bed queen'")]),

        // MARK: Output
        ToolSpec("render_view", "Render View",
                 "Render a view or sheet to a PNG file and return it as an image so you can check the design. Default path: next to the saved document (or the temporary folder).",
                 readOnly: true,
                 properties: ["view": S.ref("View name/id or sheet number"), "path": S.str(".png path"), "width": S.int("Pixels, default 1600"),
                              "inline": S.bool("Return the image in the result (default true)")],
                 required: ["view"]),
        ToolSpec("export_pdf", "Export PDF", "Export sheets (default all) to one vector PDF.", readOnly: true,
                 properties: ["sheets": S.array(S.ref(), "Sheet numbers or names"), "path": S.str(".pdf path")], required: ["path"]),
        ToolSpec("export_dwg", "Export DWG/DXF", "Export views or sheets to DWG (needs Arcus's bundled DWG engine) or DXF, one file per view, into a folder.", readOnly: true,
                 properties: ["views": S.array(S.ref(), "View names/ids or sheet numbers"), "folder": S.str(), "format": S.oneOf(["dwg", "dxf"], "Default dwg (falls back to dxf when the engine is missing)")],
                 required: ["views", "folder"]),

        // MARK: Furniture
        ToolSpec("set_furniture_size", "Set Furniture Size", "Set the piece's Width, Depth and Height (inches or text). Bound parts follow the reference planes.",
                 properties: ["width": S.len(), "depth": S.len(), "height": S.len()]),
        ToolSpec("add_furniture_parts", "Add Furniture Parts",
                 """
                 Add parts to the Furniture document, in order (later parts can pick earlier ones by their "ref"). Coordinates in inches, plan x across (Left −W/2 … Right +W/2), y depth (Front −D/2 … Back +D/2), z up from Bottom (0) to Top (H). Kinds:
                 panel {start,end, base?, top?, type?} vertical panel along a plan line (outside face to the left);
                 sides {thickness?} left and right full-height sides;
                 shelf/top/bottom {boundary? (default inside the sides), z (top face, from Bottom) or at:'top', adjustable?, type?};
                 back {at? [x,z] point on the front of the bay, fit: inside|full_overlay, type?};
                 divider {at? [x,z], vertical: true, count?};
                 leg {point, base?, top?, type?}; legs_at_corners {host (ref or id of a top/shelf), inset?, type?};
                 rail {start,end, z (top of rail), type?}; slats {rect [[x0,y0],[x1,y1]], z, along: x|y, spacing? | number?, type?};
                 plinth {host (bottom ref/id), setback?, height?}; edge_profile/groove {host, edge: front_top|back_top|left_top|right_top|front_bottom…, type?}.
                 """,
                 properties: ["parts": S.array(S.object(["kind": S.str(), "ref": S.str("Your name for this part")], required: ["kind"]))], required: ["parts"]),
    ]
}
