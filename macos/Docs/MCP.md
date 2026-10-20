# Arcus MCP server (`arcus-mcp`)

Lets Claude (Claude Desktop, Claude Code) create and edit Arcus designs from a description, through the Model Context
Protocol. Local only: stdio to the MCP client, a Unix domain socket to the app. No network, no accounts, no third-party
code. Owner's request, 2026-10-19.

## 1. Shape

```
Claude Desktop / Claude Code
        │  stdio, JSON-RPC 2.0, one message per line (MCP 2025-06-18; 2024-11-05 and 2025-03-26 accepted)
        ▼
arcus-mcp  (Arcus.app/Contents/Helpers/arcus-mcp, or .build/…/arcus-mcp)
        │
        ├── File mode: ArcusToolbox on its own DocumentSession, read/written with ArcusPackage
        │
        └── Live mode: the same tool call, forwarded over
            ~/Library/Application Support/Arcus/MCP/arcus.sock  ─►  Arcus.app (MCPLiveService)
                                                                     └── ArcusToolbox on the front document's DocumentSession
```

* **One tool layer.** `ArcusMCP` (library target, `Arcus/MCP/`) holds the tool catalog and every handler
  (`ArcusToolbox`). It depends on Domain, Application, Persistence, Output and CAD, never on UI. `arcus-mcp` (the
  executable, `Arcus/MCPServer/`) and the app's live listener (`ArcusUI/Shell/MCPLiveService.swift`) both run it, so a
  tool behaves the same in both modes.
* **Edits are transactions.** Every editing tool runs its work through `DocumentSession.perform` (one or two
  transactions), inside one undo group named after the tool ("Create Walls"). In the app that means the edit is
  validated, regenerated, journaled for recovery, shown at once, and undone with ⌘Z like any other edit.
* **Coarse tools.** One call creates a whole polyline of walls, every door of a floor, all rooms of a level, a sheet
  with its views. 133 tools cover projects, Furniture documents and the Family Editor (§5).

## 2. Backends

| | File mode | Live mode |
|---|---|---|
| When | Arcus isn't running, its MCP setting is off, or `ARCUS_MCP_MODE=file` | Arcus is running with **Settings ▸ Claude (MCP) ▸ Allow Claude to edit open documents** on, or `ARCUS_MCP_MODE=live` |
| Document | Created with `create_project` / `create_furniture` or loaded with `open_document`; held in the server process | The front document window (or the one named by `document`); `create_project` opens a new window, `open_document` opens the file in the app |
| Save | `save` writes the package (atomic: ArcusPackage writes a temporary package and moves it in) | `save` saves the document (NSDocument safe-save); untitled documents need `path` |
| Undo | `undo` / `redo` on the server's session | Same undo stack as ⌘Z |

`auto` mode (the default) picks per call: a document opened in file mode stays in file mode; otherwise, if the app
answers on its socket, the call goes live; otherwise file mode. `arcus_status` says which backend answered.

## 3. Live-mode socket protocol

* **Where:** `~/Library/Application Support/Arcus/MCP/arcus.sock`. The folder is created `0700`, the socket is
  `chmod 0600` right after `bind`. Unix domain socket only (`AF_UNIX`, `SOCK_STREAM`), never TCP.
* **Who:** the listener checks every connection with `getpeereid` and drops any peer whose uid isn't the app's own
  (`getuid()`). With the folder and socket modes, that keeps the socket to the logged-in user.
* **When:** off by default. The listener runs only while the setting is on; turning it off closes the socket and
  removes the file. A stale socket file from a crash is replaced on start (only if nothing answers on it).
* **Framing:** newline-delimited UTF-8 JSON, one request then one response per line, any number per connection.
  Requests larger than 8 MB are refused and the connection closed.

```json
→ {"v":1,"id":7,"op":"hello"}
← {"v":1,"id":7,"ok":true,"result":{"app":"Arcus","version":"1.0.0","documents":[{"name":"House","path":"/…/House.arcus","furniture":false,"front":true}]}}
→ {"v":1,"id":8,"op":"call","tool":"create_walls","arguments":{"level":"Level 1","points":[[0,0],[30,0]]},"document":"House"}
← {"v":1,"id":8,"ok":true,"result":{"content":[{"type":"text","text":"{…}"}],"isError":false}}
← {"v":1,"id":9,"ok":false,"error":"No document is open in Arcus. Call create_project or open_document."}
```

`op` is `hello` or `call`. `result` for `call` is exactly an MCP `tools/call` result, so `arcus-mcp` passes it through.
Each call is run on the main actor against the target document; a call that takes longer than 120 s is reported as a
timeout to Claude (the app keeps the edit if it completes).

**What the app needs (live mode):** `MCPLiveService` (start/stop with the setting, accept loop on a background queue,
hop to the main actor per request), `AppDocumentHost` (find/open/create/save `ArcusDocument`s), and the Settings toggle.
All three are in `Arcus/UI/Shell/MCPLiveService.swift` and `SettingsView.swift`.

## 4. Units and references

* **Lengths:** plain numbers are in the document's length unit: **feet** for Imperial projects, **millimeters** for
  Metric projects, **inches** in Furniture documents. Strings are parsed like typed input: `12'-6"`, `4' 3 1/2"`,
  `3600 mm`, `30"`. Every result says the unit (`"unit":"ft"`).
* **Points:** `[x, y]` in plan (y = north). **Angles:** degrees, counter-clockwise from east (+x), or `"north"`,
  `"south"`, `"east"`, `"west"`.
* **Elements:** integer ids from earlier results. **Levels, views, sheets, types, families:** name or id. Type names
  match exactly first, then "Family: Type", then a unique case-insensitive substring; otherwise the error lists the
  closest names.

## 5. Tools

133 tools in 14 groups (AITOOLS, 2026-10-20). Every tool declares (`ToolSpec`):

* **risk** (`ToolRisk`): `read` (changes nothing), `edit` (adds or changes elements; one undo step), `destructive`
  (deletes or undoes), `project_wide` (project information, type parameters, view templates, Joint Rules, stock sheets,
  loading families), `file` (writes, opens or replaces files or documents). `readOnly` / `destructiveHint` follow it.
  `ArcusToolbox.risk(of:arguments:)` gives one call's risk, which can be higher than the tool's (`set_parameters` with
  `type: true` is project-wide; `run_command` takes the command's risk). The in-app assistant asks the user before
  destructive, project-wide and file calls. `delete_elements` previews and asks for `confirm: true` above 5 elements;
  `run_command` refuses file, delete and project-wide commands without `confirm: true`; exports never overwrite a file
  unless `overwrite: true` (they write `Name (2).pdf`).
* **group** (`ToolGroup`) and **modes** (`DocumentMode`: none, project, furniture, family): the document kinds it
  applies to. `ArcusToolCatalog.tools(for: mode, context:)` returns only the tools for the front document (and, with a
  `ToolCatalogContext`, its active view kind and selection); `coreOnly: true` gives about 45 tools a small model starts
  with, and `find_tools` returns the others' schemas on demand. Listing sizes: project 105 tools (core 47), Furniture 93
  (core 43), Family Editor 25. A tool called in the wrong kind of document fails with what to use instead.

**Results.** Editing results are compact JSON with the new ids, key values, `health`, `warnings` for the touched
elements, the unit, and a **verification** block: `{"ok", "problems", "changed": {created, modified, deleted},
"health_delta"}`. `problems` lists new model-health warnings plus the tool's own checks: dimensions that overlap or
duplicate (add_dimensions), untagged elements (add_tags), unbounded rooms (add_room_separators), flex and Check Parts
findings (every Furniture tool), flex problems (every Family Editor tool), sheets that run off the paper. Required
arguments are checked first and named; lookups that miss list the closest names. Lengths take numbers in the document
unit or text (`12'-6"`, `750 mm`); tools default to the selection (`elements`) and the active view (`view`).

**For the assistant.** `context_summary` (and `ArcusToolbox.contextSummaryText()`) is the system prompt's document
section, under 3,000 characters: kind, units, active view, levels, selection, counts, sheets, health. `query_model
{what: "here"}` says what the active view shows. `verify_drawing` checks a view or sheet (dimensions present and apart,
tags, title block fields, viewports on the paper and apart, clipping) and returns each problem with the tool that fixes
it, plus a PNG with `image: true`; `render_view` returns a PNG for vision. `list_commands` / `run_command` reach every
`CommandID` (in the app through the document's `CommandRouter`; commands that wait for clicks start their tool for the
user; file mode runs a headless subset).

**Undo.** Each editing call is one undo group, opened at its first edit, so a call that changes nothing adds no step.
The groups nest: the in-app assistant opens one outer group per prompt (groupsByEvent off) and ⌘Z undoes the whole
prompt. Family Editor tools are one step each on the family's own undo stack.

**Hosts.** `DocumentHost` (document, open, save) plus `DocumentUIHost` (active view, open a view, zoom, command
availability, run a command, the Family Editor's family). File mode implements both headless (the active view is the
last one a tool opened). The app's `AppDocumentHost` implements `DocumentUIHost` in `MCPLiveService+AITOOLS.swift`.
Family Editor windows have no DocumentSession: the tools run on `FamilyEditingHost` (the current `FamilyDefinition`,
its current type and units, `apply(name:edit:)` as one undo step, `flexTest()`, `loadIntoProject()`); file mode has
`FileFamilyHost` (create_family, `.arcusfamily` save), and the in-app assistant sets `ArcusToolbox.familyHostProvider`
to an adapter over the front `FamilyEditorModel`.

**Document** (10)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `arcus_status` | read | any | Where tools run (file mode or the live Arcus app), the open document, its units and element counts, and what to do next. |
| `create_project` | file | any | Start a new building project from a template and make it the current document. |
| `create_furniture` | file | any | Start a new Furniture or Casework document (.arcusfurniture) at a size, then add parts with add_furniture_parts. |
| `open_document` | file | any | Open an .arcus or .arcusfurniture file and make it the current document.. |
| `save` | file | family, furniture, project | Save the current document, optionally to a new path (the extension follows the document kind). |
| `set_project_info` | project_wide | project | Set the project information shown in title blocks.. |
| `undo` | destructive | family, furniture, project | Undo the last tool calls (each editing call is one step, like ⌘Z).. |
| `redo` | edit | family, furniture, project | Redo steps undone with undo (each step is one tool call).. |
| `context_summary` | read | any | Compact summary of the front document: kind, units, active view, levels, selection (ids, categories, types), element counts, sheets and model health. |
| `create_family` | file | any | Start a new family in the Family Editor (file mode: a .arcusfamily document). |

**Architecture** (25)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `add_level` | edit | project | Add levels at elevations, each with a floor plan (and a ceiling plan if asked). |
| `add_grid` | edit | project | Add structural grid lines: explicit lines, or vertical lines at x positions (named 1, 2, 3…) and horizontal lines at y positions (named A, B, C…) spanning the given extents. |
| `create_walls` | edit | project | Create walls along a polyline (points, optionally closed) or a list of separate segments. |
| `place_doors` | edit | project | Place doors in walls. |
| `place_windows` | edit | project | Place windows in walls like place_doors, with sill height above the wall's base. |
| `create_floor` | edit | project | Create a floor slab from a boundary, or from the walls of its level (interior faces by default; exterior for a slab under the walls). |
| `create_ceiling` | edit | project | Create ceilings at a height above the level: one from a boundary, or one per room (rooms ids, or all rooms of the level). |
| `create_roof` | edit | project | Create a footprint roof on a level from a boundary or the level's walls (outer faces + overhang). |
| `add_stair` | edit | project | Add a stair from base_level to top_level. |
| `add_railing` | edit | project | Add a railing along a path on a level, or on both sides of a stair. |
| `place_rooms` | edit | project | Place rooms. |
| `place_components` | edit | project | Place furniture, fixtures, casework, appliances, planting, cars… from the built-in library (loaded on first use; list_families to browse). |
| `create_curtain_wall` | edit | project | Curtain walls along a polyline like create_walls, with the type's grid layout or explicit grid spacing (vertical every x, horizontal every z) and mullions. |
| `add_curtain_grids` | edit | project | Add curtain grid lines to a curtain wall: vertical at distances from its start, horizontal at heights above its base (mullions follow the type). |
| `place_columns` | edit | project | Place architectural or structural columns at points, or at every grid intersection (at_grids), from a base level to a top level. |
| `create_beams` | edit | project | Structural beams along segments at a level (top of beam at the level plus offset). |
| `create_stair` | edit | project | Component stair: one or more runs, each from its first-riser centre in a direction with a riser count (straight, spiral, l_winder, u_winder); landings join consecutive runs automatically. |
| `create_ramp` | edit | project | A ramp along a run path (points) between levels, with width and railings. |
| `create_opening` | edit | project | Openings: wall (a rectangular cut in a wall: center offset from its start, width, sill and head heights), shaft (a boundary cut through every floor, roof and ceiling between levels) or vertical (a boundary cut through one floor, ceiling or roof). |
| `place_areas` | edit | project | Make an area plan for a level (Gross Building or Rentable scheme) with its automatic boundary and place an area in each region. |
| `add_room_separators` | edit | project | Room separation lines (or area boundary lines in an area plan) along segments, to split open spaces into rooms. |
| `add_model_lines` | edit | furniture, project | Model lines on a level, or project reference planes (named), along segments. |
| `create_toposolid` | edit | project | Site terrain: a toposolid from an outline at an elevation, or from survey points [[x, y, z], …]. |
| `create_building_pad` | edit | project | A building pad (a slab that cuts the terrain) from a boundary on a level. |
| `create_mass` | edit | project | A conceptual mass extruded from a plan boundary to a height (optionally tapering by top_inset); floors, walls and roofs can be made by face later. |

**Annotation** (11)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `add_dimensions` | edit | furniture, project | Dimension any view (default the active one). |
| `add_tags` | edit | furniture, project | Tag every untagged element of the given categories visible in a view (Tag All; default the active view), or only the given elements. |
| `add_text` | edit | furniture, project | Text notes in a view, optionally with a leader to a point. |
| `add_detail_lines` | edit | furniture, project | View-specific detail lines along segments, with a line style (Thin Lines, Medium Lines, Wide Lines, Hidden, …). |
| `add_region` | edit | furniture, project | A filled region (hatch: type name such as 'Solid Black', 'Diagonal Crosshatch') or a masking region from a boundary. |
| `place_detail_components` | edit | furniture, project | Detail components (2D families such as wood blocking, studs, break lines) at points in a view. |
| `add_spot_dimensions` | edit | furniture, project | Spot elevations (plans: the surface below the point; sections/elevations: the point's height) or spot coordinates (plans) at points. |
| `add_keynotes` | edit | furniture, project | Keynote tags on elements in a view: element keynote (from the type), material keynote, or a user keynote with a key from the keynote table. |
| `create_legend` | edit | furniture, project | A legend view with a component of each named type in rows (doors, windows, wall/floor types…), and a label for each. |
| `add_revision_cloud` | edit | furniture, project | A revision cloud around a boundary in a view, tagged with a revision (default the latest; add_revision makes one). |
| `arrange_dimensions` | edit | furniture, project | Fix overlapping dimensions in a view: delete duplicates and respace parallel strings that lie on top of each other to a clean paper spacing, moving outward. |

**Views & Sheets** (12)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `create_views` | edit | furniture, project | Create views: floor_plan / ceiling_plan (level), three_d (optional section box of a level), section (start + end points; looks to the left of start→end unless flipped), elevation (point + facing direction it looks), callout (parent view + rect, at twice the scale), drafting, legend. |
| `create_sheet` | edit | furniture, project | Create a sheet with a title block and place views and schedules on it. |
| `duplicate_view` | edit | furniture, project | Duplicate a view: duplicate (model only), with_detailing (copies its dimensions, tags, text), or dependent (follows the parent, with its own crop).. |
| `set_view_properties` | edit | furniture, project | Change a view's Properties: name, scale (1:n, e.g. |
| `apply_view_template` | project_wide | furniture, project | Apply a view template to views (or remove it with template 'none'), or create one from a view (create_from) to apply to others.. |
| `set_visibility_graphics` | edit | furniture, project | Visibility/Graphics Overrides for a view: show/hide categories and override their color, line weight, halftone, transparency or surface fill; or override elements (Override Graphics in View by Element). |
| `add_view_filter` | edit | furniture, project | Create a rule-based filter (categories + parameter rules) and add it to views with visibility and graphic override, e.g. |
| `place_on_sheet` | edit | furniture, project | Place views, legends or schedules on an existing sheet (position [u, v] as fractions of the paper, else the next free spot), or move a view that's already on the sheet.. |
| `set_sheet_info` | edit | furniture, project | Title block fields and properties of sheets: number, name, drawn/checked/designed/approved by, issue date, title block type, appears in sheet list. |
| `add_revision` | edit | furniture, project | Add a revision (sequence, date, description, issued to/by) and show it on sheets (their revision schedules list it).. |
| `duplicate_sheet` | edit | furniture, project | Duplicate a sheet with its title block (and with_detailing: its views duplicated with their annotations, placed the same way).. |
| `create_sheet_set` | edit | furniture, project | Save a named set of sheets (and views) for printing and PDF export (export_pdf {sheet_set}).. |

**Schedules** (3)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `create_schedule` | edit | furniture, project | Create a schedule: standard doors, windows, rooms, walls or sheets; Furniture part_list, hardware, edge_banding, cost, material_takeoff, component_bom; or category with fields (parameter names, 'Count'). |
| `get_schedule` | read | furniture, project | The rows of a schedule as a table (headings + cells), with totals. |
| `edit_schedule` | edit | furniture, project | Change a schedule: add fields (parameter names, e.g. |

**Exports** (7)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `render_view` | read | furniture, project | Render a view or sheet to a PNG file and return it as an image so you can check the design. |
| `export_pdf` | file | furniture, project | Export sheets (default all, or a sheet set) or views to vector PDF: one combined file (path) or one file per sheet into path's folder, named by sheet number and name or a pattern; color, black lines or grayscale; views on a paper size. |
| `export_dwg` | file | furniture, project | Export views or sheets to DWG (needs Arcus's bundled DWG engine) or DXF, one file per view, into a folder.. |
| `export_image` | file | furniture, project | Export views or sheets to PNG or JPEG files in a folder (one per view), at a pixel width.. |
| `export_ifc` | file | project | Export the model to IFC (IFC4 Reference View or IFC2x3 Coordination View), optionally only what a view shows.. |
| `export_schedule_csv` | file | furniture, project | Export a schedule's rows to a CSV file (opens in Numbers or Excel).. |
| `export_cnc` | file | furniture | Furniture: write CNC files (DXF, or DWG with the bundled engine) per part or per nested sheet, with layers OUTLINE/INNER/DRILL/GROOVE…, plus a CSV cut list.. |

**Family Editor** (11)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `family_info` | read | family | Read the family: template, types with values, parameters (type/instance, formulas), reference planes with positions, forms (kind, bounds, visibility), dimensions and labels, nested families.. |
| `add_family_parameter` | edit | family | Add (or change) family parameters, like Family Types ▸ New Parameter: name, type (length, area, angle, number, integer, text, yes_no, material), instance or type, group, formula, and the value for the current type (or every type). |
| `set_family_type` | edit | family | Family Types: make a new type (copying the current one), rename or delete one, switch the current type, and set parameter values in a type, e.g. |
| `add_reference_plane` | edit | family | Add reference planes on an axis: x (left/right planes, vertical in plan), y (front/back), z (levels of height). |
| `add_form` | edit | family | Create a solid or void form: extrusion (rect bounds, or polygon points, or circle), blend (bottom and top polygons), revolve (profile + axis point, degrees) or sweep (path + profile). |
| `edit_form` | edit | family | Change forms by name: bounds (lock to planes), material parameter, visibility (detail levels, plan/3D/front-back/left-right, a Yes/No visibility parameter), solid/void, rename. |
| `add_family_dimension` | edit | family | Dimension two parallel reference planes and label it with a parameter (created as a length parameter with today's distance when missing), or EQ three planes (equality), or lock it. |
| `add_nested_family` | edit | family | Nest a family from the built-in component library (search words) at a point, with its type, rotation and optional parameter bindings {nested parameter: host parameter or formula}. |
| `delete_family_item` | destructive | family | Delete family items by name: forms, reference planes (with their dimensions; locked bounds keep their position), parameters, nested instances or labels.. |
| `flex_family` | read | family | Flex test: evaluate every type (and lengths at 50% / 150%) and report problems: formula errors, planes that cross, forms that collapse. |
| `load_family_into_project` | project_wide | family | Load (or reload, keeping project type values) the family into its project, after a flex test. |

**Furniture** (20)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `set_furniture_size` | edit | furniture | Set the piece's Width, Depth and Height (inches or text). |
| `add_furniture_parts` | edit | furniture | Add parts to the Furniture document, in order (later parts can pick earlier ones by their "ref"). |
| `add_furniture_form` | edit | furniture | A free form (or void) in a Furniture document: extrusion or blend of a profile, revolve about an axis, sweep along a path, or a cushion. |
| `edit_furniture_part` | edit | furniture | Change parts: opening (a rectangular cut-out in a panel: s0–s1 along it, t0–t1 up from its base), profile (a new face outline, or reset), attach (panels/legs run to a shelf or top) or detach. |
| `add_bays` | edit | furniture | Place bays (front openings bounded by parts, like rooms) at front points [x, z], or auto: one in every opening of the front; optionally divide each into rows (drawer stack) or columns. |
| `add_fronts` | edit | furniture | Put doors, drawers (count: a drawer stack) or flaps in bays (ids, or all bays without a front). |
| `add_hardware` | edit | furniture | Add hardware to fronts or bays in one step: handle, hinges, lock, soft_close, push_to_open, slides, organizer, hanging_rod, shoe_rack, lighting, sliding_system. |
| `set_joint` | edit | furniture | Set the joint between two touching parts (butt, miter, dado, rabbet, groove, dowel, cam_lock, pocket_screw, mortise_tenon, confirmat, biscuit), which part runs through, or reset to the rule. |
| `set_joint_rules` | project_wide | furniture | Change Joint Rules (which joint each pair kind gets): pairs side_top, side_bottom, side_side, side_back, shelf_side, shelf_back, divider_shelf, plinth_carcass, rail_leg, rail_panel, rail_top, top_leg, slat_frame, other.. |
| `search_components` | read | furniture, project | Search the Component Library (435 hardware, legs, kitchen, lighting, mechanism… families) by words, sizes or synonyms; filter by host kind.. |
| `place_library_component` | edit | furniture, project | Place a Component Library component (name or id) with a type on a host part/front (placed where it belongs) or at a point. |
| `replace_components` | edit | furniture, project | Replace placed components with another component (keeps placement and host). |
| `insert_assembly` | edit | furniture | Insert an assembly preset into a bay: e.g. |
| `set_stock_sheets` | project_wide | furniture | Stock sheet sizes for nesting (default 4'×8'), kerf and edge trim, rotation. |
| `fabrication_report` | read | furniture | Read the piece's fabrication data: parts (cut list with sizes, material, grain, banding), hardware (with counts), banding, nesting (sheets and yield), cost (total and by line).. |
| `create_shop_drawings` | edit | furniture | Set up the shop drawings: fabrication schedules and sheets F101–F104 (plan, elevations, section, 3D, part list, exploded view) and the nesting sheets. |
| `set_furniture_parameter` | edit | furniture | Add or change a parameter of the piece (Family Types in Furniture mode): value in the current type, a formula, a new type copied from the current, or switch type. |
| `flex_furniture` | read | furniture | Flex the piece: every type, and lengths at 50%/150%; reports planes that cross, formula errors and parts that don't follow.. |
| `list_furniture_library` | read | any | Browse the Furniture Library (Sofa, Wardrobe, Kitchen Cabinet… 190+ pieces) by words or room.. |
| `load_furniture_piece` | file | any | Load a Furniture Library piece: into: project places it in the open project at a point (as a family); into: new opens it as a new Furniture document to edit.. |

**Edit** (17)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `set_parameters` | edit | furniture, project | Set parameters by their Properties name on elements, e.g. |
| `move_elements` | edit | furniture, project | Move elements by a plan vector (hosted doors and windows follow their walls). |
| `delete_elements` | destructive | furniture, project | Delete elements (and what depends on them, such as their doors and tags). |
| `copy_elements` | edit | furniture, project | Copy elements by a plan vector (count > 1 makes a row of copies, like Copy ▸ Multiple), or to another level. |
| `rotate_elements` | edit | furniture, project | Rotate elements by an angle (degrees, counter-clockwise) about a point (default their centre). |
| `mirror_elements` | edit | furniture, project | Mirror elements about an axis line through two points (or a wall/grid/line id), keeping the originals unless copy is false (Mirror ▸ Draw Axis / Pick Axis). |
| `array_elements` | edit | furniture, project | Linear array (count members spaced by `by`, or spread to `last` with Move To Last) or radial array (count members over `angle` degrees about `center`). |
| `align_elements` | edit | furniture, project | Align elements to a reference: walls/lines/grids parallel to the reference line move onto it (face or centre line); points (columns, components) move onto it. |
| `offset_elements` | edit | furniture, project | Offset walls, lines, beams, grids or reference planes sideways by a distance (positive: to the left of start→end). |
| `trim_extend` | edit | furniture, project | corner: trim or extend two walls/lines to meet at a corner (keeps each element's longer side). |
| `split_element` | edit | furniture, project | Split a wall, line or beam at a point or at a distance from its start; gap leaves an opening between the pieces (Split with Gap). |
| `join_geometry` | edit | furniture, project | Join (or unjoin) the solids of walls, floors, roofs, columns and beams so the one cuts the other. |
| `change_type` | edit | furniture, project | Change elements to another type of their category (Type Selector), e.g. |
| `pin_elements` | edit | furniture, project | Pin (or unpin) elements so they can't move or be deleted by accident. |
| `flip_elements` | edit | furniture, project | Flip doors/windows (facing: swing side; hand: hinge side) or walls (exterior side), like the flip arrows. |
| `attach_walls` | edit | project | Attach the tops of walls to a roof, floor or ceiling (they follow its underside), or detach them. |
| `group_elements` | edit | furniture, project | Group elements (model or detail group) with a name, or ungroup a group (its members stay). |

**Selection** (3)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `get_selection` | read | furniture, project | The selected elements with a short summary each (category, type, level, key sizes), and counts by category. |
| `select_elements` | read | furniture, project | Select elements (the app highlights them; later tools default to the selection): by ids, or by category plus optional type, level, view (visible in it) and parameter filters, e.g. |
| `hide_isolate` | edit | furniture, project | Temporary Hide/Isolate (the glasses icon; not saved): hide or isolate elements or categories in a view, or reset. |

**Navigation** (3)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `open_view` | read | furniture, project | Open (activate) a view, sheet or schedule by name, number or id, so the user sees it and later tools default to it.. |
| `zoom_to` | read | furniture, project | Zoom the active view to elements (Zoom to selection) or to fit everything.. |
| `set_3d_view` | edit | furniture, project | Orient a 3D view: iso_sw/iso_se/iso_ne/iso_nw, top, front, back, left, right; optionally a section box around elements or a level (or off). |

**Query** (3)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `query_model` | read | furniture, project | Read the model. |
| `list_types` | read | furniture, project | List the types loaded in the document for a category (walls, floors, roofs, ceilings, doors, windows, stairs, railings, furniturePanels, …) or all categories.. |
| `list_families` | read | project | Browse the built-in component library (furniture, casework, plumbing fixtures, appliances, planting, parking, lighting…) with each family's sizes. |

**Model Checks** (5)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `model_health` | read | furniture, project | Every warning (Revit's Review Warnings): severity, message, elements, and what to do; plus Furniture Check Parts and component collisions. |
| `check_clashes` | read | furniture, project | Find elements that occupy the same space (columns in walls, furniture through walls, beams through ducts…): by category pairs, or everything. |
| `check_rooms` | read | project | Rooms (or areas) with their area and whether they are enclosed, redundant or not placed, and the regions bounded by walls that have no room yet.. |
| `check_parts` | read | furniture | Furniture: parts without material, too thin or too long for stock, grain against the long side, unbanded visible edges, fronts that collide, missing hardware.. |
| `verify_drawing` | read | furniture, project | Check a view or sheet like a reviewer: dimensions present, not overlapping and not duplicated; tags on doors, windows and rooms; title block fields filled; viewports on the paper and apart; annotations not clipped. |

**Commands** (3)

| Tool | Risk | Documents | What it does |
|---|---|---|---|
| `find_tools` | read | any | Find more Arcus tools by words or group (Architecture, Annotation, Views & Sheets, Schedules, Exports, Furniture, Edit, Model Checks…) with their input schemas, e.g. |
| `list_commands` | read | any | Every Arcus command (ribbon, menus) with whether it can run now and why not. |
| `run_command` | edit | any | Run any command like its menu item, by id or title (list_commands). |

Total: 133


Tests: `swift test --filter MCPToolsCoverageTests` runs every tool with a minimal input in its document kind, checks
missing arguments are named, bad inputs get actionable errors, risk flags agree, mode filtering, undo nesting in a
prompt group and the context summary, and four flows: a house plan with sheet, dimensions and PDF; a cabinet with
drawers, a door, handles and hinges to shop drawings; editing the selected walls; fixing a plan whose dimensions overlap
(`ARCUS_TOOL_DUMP=1` prints each result and writes this table to `/tmp/arcus-aitools/tools.md`).

**Automatic view fitting.** `create_walls` crops the plans (not yet on a sheet) to the building plus room for the
dimension strings, and re-aims the template's North/South/East/West elevations just outside the building, so sheets and
renders frame the design without extra calls. `create_sheet` lays out unpositioned views in a grid; a view too big for its
cell gets the next standard scale that fits (`rescaled`; `fit: false` keeps the scale), and a view that still overflows is
reported (`fit`) with the fix (bigger paper, another sheet).

**Defaults.** Imperial projects get levels at 0', 10' and 20' unless `levels` is given. Wall type: Generic; door:
Single Flush 36"; window: Casement 36"; sill heights from the window type.

Every editing result is compact JSON: the new ids, key values (areas, lengths), and **model health** for the elements it
touched (`warnings`) plus the document's overall health count, so Claude can check its work and fix problems. Errors
are `isError: true` with a sentence saying what to change ("No wall type matches “Brick”. Close: Exterior - Brick on
CMU, …").

## 6. Install and Design with Claude

**In the app** (the usual way): *Design with Claude* sets everything up. It is on Home (a card under the Start cards
with its status: Not set up / Ready / Claude connected), Help ▸ Design with Claude…, Manage ▸ Add-Ins ▸ Claude (projects
and Furniture documents), Settings ▸ Claude (MCP), command search (claude, mcp, ai), an onboarding step, and a hint on
Home ▸ Furniture and in Load Furniture's empty library. The sheet has:

* what it is and that it stays on the Mac;
* **Claude Desktop**: *Add to Claude Desktop…* (after a confirmation, backs up `claude_desktop_config.json` beside it as
  `claude_desktop_config.backup-<date>.json` and merges an `arcus` server, keeping every other key and server; a file
  that isn't valid JSON is left alone) or *Copy Configuration*;
* **Claude Code**: *Copy Command* (`claude mcp add --scope user arcus -- "<path>"`);
* the live-mode switch (*Allow Claude to edit open documents*);
* *Test Connection*: starts the bundled server, lists its tools, and asks the app's socket for hello when live mode is on;
* five example prompts with Copy buttons.

The status comes from reading the two configs (`ClaudeClientConfig`) and from live-mode activity. While live mode
listens, document windows show a **Claude pill** in the bottom bar (Claude / Claude connected / Claude is editing…);
it opens the recent Claude actions (tool, document, time, errors) with *Undo <last change>* when that change is the
document's next undo step.

**From the command line**: `arcus-mcp --install-claude-desktop` and `arcus-mcp --install-claude-code` print (never
write) the configuration for the binary's own location:

```json
{ "mcpServers": { "arcus": { "command": "/Applications/Arcus.app/Contents/Helpers/arcus-mcp" } } }
```

```
claude mcp add --scope user arcus -- /Applications/Arcus.app/Contents/Helpers/arcus-mcp
```

`arcus-mcp --help` lists the options (`--mode auto|file|live`).

**Bundling**: `script/build_and_run.sh` builds `arcus-mcp` after the DWG helpers and copies it to
`Arcus.app/Contents/Helpers/`; the helper loop signs it, the validation loop checks it is arm64, links only system
libraries and runs (`--version`). The setup sheet points at the running app's own copy (else
`/Applications/Arcus.app/Contents/Helpers/arcus-mcp`).

## 7. Demo and tests

* `Tools/MCP/demo_house.py <arcus-mcp> <folder>` drives the server over stdio like Claude does: a 36' × 28'
  two-bedroom cottage (walls, 5 doors, 9 windows, floor, gable roof, 4 named rooms, ceilings, 12 furniture and fixture
  components, 2 sections, a 3D cutaway, auto dimensions, tags, 4 sheets), then saves `MCP Demo.arcus`, renders the plan,
  3D and A101 to PNG and exports the sheet set to PDF. 45 calls, model health 0.
* `swift test --filter MCPTests`: protocol (initialize, tools/list, tools/call, JSON-RPC errors, batches), the tool
  layer end to end in file mode (project → walls → doors → windows → floor → roof → rooms → views → dimensions → tags →
  sheet → PNG/PDF/DXF → save → reopen), undo per call, validation messages, Furniture parts, and the live socket
  (0600/0700 permissions, hello, forwarded calls editing the served document, refusing a second server), and the
  Claude Desktop config merge (other servers kept, backup written, invalid JSON left alone).
* `swift test --filter MCPUITests`: renders Home with the card, the Set Up sheet, the pill (ready, connected, editing),
  the activity popover and the onboarding step, light and dark, to `/tmp/arcus-mcp-ui/`; checks Help, Manage ▸ Add-Ins
  and command search reach the feature. In-app captures: `QAHarness.mcpScreenshots` (`mcp-*.png`).

## 8. Limits

* Live mode needs the setting turned on in Arcus once; the server never launches Arcus.
* Roofs are footprint roofs (flat, shed, gable, hip by edge slopes); no extrusion roofs, dormers or roof joins.
* Auto dimensions: plans cover orthogonal walls (overall + chain per side); sections and elevations dimension the
  levels; Furniture views give overall width, depth and height. Angled walls get no automatic dimensions.
* PDF export is always vector (the exporter never rasterizes); there is no raster option.
* Clash checks compare element boxes (walls by footprint); curved and sloped elements can report near misses.
* Component library families load into projects; `.arcusfamily` files from disk load through the app (Insert ▸ Load
  Family) or the Family Editor tools (`load_family_into_project`).
* Joints are solved from touching parts: `set_joint` changes a joint the solver found; it can't join parts that don't
  touch.
* File mode: one document at a time (a family created with create_family loads into it); commands that need a window
  (most of `list_commands`) run only in the app.

## In-app AI Assistant

The AI button (top right, ⇧⌘A; also View ▸ AI Assistant and Manage ▸ Add-Ins) opens a right-hand chat in projects,
Furniture documents and the Family Editor. It uses the same tool layer in-process (`ArcusAssistant` target).

- Opt-in (Settings ▸ AI Assistant, off by default); only the assistant goes online. The user's Anthropic API key lives in
  the Keychain. First use explains what is sent: the prompt, a compact model summary, tool results, and view images only
  for drawing checks or attached pictures.
- Models: `claude-haiku-5-5` works through the tools; a step that fails verification twice runs once on
  `claude-sonnet-5-5`, then back to Haiku. Drawing tasks run `verify_drawing` before finishing.
- Each prompt is one undo step ("AI: …") with a change summary and Undo; risky calls (files, deletes over 5 elements,
  project-wide settings) ask in the chat first.
- Prompt caching: breakpoints on the last tool, the system prompt and the per-prompt context block, plus automatic
  caching for the tool loop; system and tools are identical across requests and models.
- Cost per reply, chat and month; monthly budget cap; editable price table (checked 2026-10-20).
- Chats are saved in the document (`assistant/history.json`, FileFormat.md §1.7); Family Editor chats last for the session.

