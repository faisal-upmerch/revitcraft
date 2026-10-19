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
  with its views. About 30 tools cover a house end to end.

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

| Tool | What it does |
|---|---|
| `arcus_status` | Backend (file/live), app reachable, open document, units, element counts, next steps |
| `create_project` | New project from the Architectural or Empty template (Imperial by default), optional levels and save path |
| `create_furniture` | New Furniture or Casework document (`.arcusfurniture`) at a width × depth × height |
| `open_document` | Opens an `.arcus` / `.arcusfurniture` package |
| `save` | Saves (optionally to a new path; the extension follows the document kind) |
| `set_project_info` | Project name, number, client, address, status, issue date, building name, author |
| `add_level` | Levels at elevations, with floor plans (and ceiling plans) |
| `add_grid` | Grid lines from explicit lines, or from x / y positions |
| `create_walls` | Walls along a polyline (or list of segments) with type, level, height or top level, location line |
| `place_doors` | Doors hosted in walls at an offset from the wall start or a point; mark, flip |
| `place_windows` | Windows likewise, with sill height |
| `create_floor` | Floor from a boundary or from the walls of a level (interior or exterior faces) |
| `create_ceiling` | Ceiling from a boundary, a room, or every room of a level, at a height |
| `create_roof` | Flat, shed, gable or hip roof from a boundary or the walls, with overhang and slope |
| `add_stair` | Straight, L or U stair between two levels with width, riser count, turn; optional handrails |
| `add_railing` | Railing along a path, or both sides of a stair |
| `place_rooms` | Rooms automatically in every enclosed region, or at points with names and numbers; tags |
| `place_components` | Furniture, fixtures, casework, planting… from the built-in library (loaded on demand) at points |
| `create_views` | Floor/ceiling plans, 3D views, sections (two points) and elevations (point + facing) |
| `create_sheet` | Sheet with title block and paper; places views and schedules (auto layout or positions) |
| `create_schedule` | Door, window, room, wall or sheet schedule (the standard field sets) |
| `add_dimensions` | Auto dimensions for a plan (overall + wall chains each side), or one dimension between walls |
| `add_tags` | Tags every untagged door, window, room… visible in a view |
| `query_model` | Summary, levels, elements by category with key parameters, rooms with areas, views, sheets, warnings |
| `list_types` | Types loaded in the document, by category |
| `list_families` | Library families and their types (doors, windows, components) |
| `set_parameters` | Sets parameters by name on elements (or their types) using the same parser as Properties |
| `move_elements` | Moves elements by a vector |
| `delete_elements` | Deletes elements (pinned ones are reported, not deleted) |
| `undo` / `redo` | Undo or redo the last N tool calls |
| `render_view` | Renders a view or sheet to PNG (file + inline image so Claude can look at it) |
| `export_pdf` | Vector PDF of sheets (one combined file) |
| `export_dwg` | DWG (bundled acadrust engine) or DXF of views and sheets |
| `set_furniture_size` | Width, depth and height of a furniture piece (the reference planes move; bound parts follow) |
| `add_furniture_parts` | Panels, sides, shelves, tops, bottoms, backs, dividers, legs (or legs at corners), rails, slats, plinths, edge profiles and grooves |

**Automatic view fitting.** `create_walls` crops the plans (not yet on a sheet) to the building plus room for the
dimension strings, and re-aims the template's North/South/East/West elevations just outside the building, so sheets and
renders frame the design without extra calls. `create_sheet` lays out unpositioned views in a grid and reports views that
overflow their cell (`fit`) with the fix (smaller scale, bigger paper, another sheet).

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
* Auto dimensions cover orthogonal walls (overall + chain per side); angled walls get no automatic dimensions.
* Components come from the built-in library; `.arcusfamily` files and loading from disk aren't exposed.
* Furniture: doors, drawers, hardware, joints and Forms aren't exposed yet (their operations are UI-driven on main).
* DWG export needs the bundled `arcus-dwg` helper (in the app, or `ARCUS_DWG_HELPERS_DIR`); otherwise DXF is written.
* One document at a time in file mode.
