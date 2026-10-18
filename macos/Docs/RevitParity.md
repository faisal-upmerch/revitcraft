# Revit parity

This document tracks how well Arcus serves architects who switch from Autodesk Revit. It covers the habits they bring, the features they rely on, and a build plan for closing the gaps.

"Revit" and "Autodesk" are trademarks of Autodesk, Inc. We name them here only to describe what users expect. Arcus is not affiliated with Autodesk.

## Status after the first implementation wave (2026-09-25)

All seven work packages below were built, merged and tested (1,062 tests pass; the in-app QA suite passes 65/65). Sections 2–4 describe the plan as it was written before the wave, so some items marked Missing there are now done. What was delivered, and what is still open:

| Package | Delivered | Still open |
|---|---|---|
| WP1 Canvas | Clickable, typeable temporary dimensions on the selection (walls, inserts, datums, columns) with make-permanent; typed values while dragging; flip arrows; Tab chain-select; Select Previous (⌥⌘←); EQ/lock toggles; witness-line grips and Edit Witness Lines; bubble boxes; Tab snap cycling; middle-button double-click zoom to fit | Grid/level elbows and 3D/2D extent toggles; temporary dimensions measure to centrelines only |
| WP2 Snaps & keys | Shift constraint, one-shot snap overrides, Snaps dialog, alias fixes (`SE`/`ST` for snaps, `SX` Section, `SR` Stair, `EL` Spot Elevation, `EV` Elevation, `RT` Room Tag, `CS`, `BX`), customizable toolbar | — |
| WP3 Walls | Curtain walls (grid rules, mullions, panels, swap, schedules, IFC), wall Options Bar fields, circle/polygon/tangent/fillet modes, Space flip, wrapping (plan), wall and shaft openings | Stacked walls, sweeps/reveals; doors as curtain panels; wrapping in 3D; editing shaft sketches |
| WP4 Floors/roofs/stairs | Ramps (plan/3D/section, railings, IFC), roof by extrusion, Edit Stair, shape editing, attach walls afterwards, join/unjoin geometry, schema 3 | Split lines; join-order switching; slope arrows on floors; soffit/fascia/gutter |
| WP5 Modify | Create Similar, Measure, Disjoin, radial/associative arrays with Array Number, offset with inserts, split with gap / delete inner segment, Demolish, Scale, paste between projects | Tab-picking a wall chain for Offset |
| WP6a Views & sheets | Selection Box, Override Graphics in View by Element, drag views onto sheets, activate viewport, level-rename cascade, grid Pick Lines, scope boxes, cameras, base/survey point display | Moving base/survey points on the canvas; scope-box grips; arc/multi-segment grids |
| WP6b Rooms & annotation | Place Rooms/Areas Automatically, Tag All dialog, colour schemes and legends, entire-wall dimensions, area plans and schemes, baseline/ordinate dimensions | Keynotes, multi-category tags, repeating details; area tags |
| WP7 Families | Labelled/locked/EQ dimensions, sweep/blend/revolve, void cuts for extrusions, nested families, visibility settings and Preview Visibility, reload choice, Family Types dialog, Save as Template | Void sweeps/blends/revolves (no mesh booleans); swept blends |

Also done in this wave: the Revit-style shell (ribbon, contextual tabs, Options Bar, Properties, Project Browser), Revit model and family import through the Arcus Bridge (`.arcusx`), Metal 4 rendering for 2D and 3D views. See the decision log (D24–D30).

### Visual checks still owed

These were verified by unit tests and the standard QA scenarios, but not yet inspected screen by screen:

- Temporary dimension and flip-arrow placement on doors, windows and grids at several zoom levels; EQ/padlock glyphs; witness grips.
- Curtain walls in plan (each detail level), elevation, section and 3D, including curved ones; curtain tool previews.
- Ramps in plan (landings, walk line, cut break), 3D and section; roof by extrusion from an elevation; Edit Stair handles.
- Shape-edit points and labels; join geometry in sections (no doubled cut fill).
- Colour fill in plans, sections and area plans; legend layout at 1:100, 1:50 and on sheets; area plan boundary lines.
- Override Graphics dialog results in plan and 3D; activated viewports staying aligned while zooming; scope boxes in cropped plans and elevations; camera views.
- Family Editor tabs, blend/revolve/sweep previews, visibility settings with Preview Visibility, the nested-family tab and the reload prompt.
- 3D Realistic style, shadows with sun presets, ambient shadows and silhouettes, in light and dark mode; MetalFX on a slower Mac.

## 1. What "parity" means here

- **Familiar workflows and vocabulary.** A switcher should find a tool where they expect it. Examples: Wall under Architecture ▸ Build, and a "Modify | Walls" tab after selecting a wall. They should get the same modifier keys, the same two-stage Esc and the same two-letter shortcuts, and they should never have to relearn the underlying concepts (type vs. instance, host vs. hosted, view range, phases).
- **Original implementation.** Everything is written from scratch in Swift. We copy behaviour, never code, file formats, icons, artwork, dialog text or help text. Where a Revit widget has a trademarked name (ViewCube, SteeringWheels), Arcus ships its own control under a neutral name.
- **No proprietary formats.** Arcus does not read or write RVT or RFA and makes no compatibility claim. Models cross over through IFC (see §5).
- **Mac-native where that is better.** Parity never overrides macOS conventions that switchers do not miss, such as native Open/Save panels, autosave, or ⌘ in place of Ctrl.

Status values used below:

- **Present:** the feature ships. It was confirmed in source (file cited) and is reachable from the UI.
- **Partial:** some of it exists, but part of the expected behaviour is missing or exists only in the data model.
- **Missing:** no implementation was found.

The research notes behind this document contained several wrong statuses. Each claim was re-checked against the code on 2026-09-25, and the corrections are in the appendix.

## 2. Switcher muscle memory

These are UI conventions and behaviours, not features. Most of them are cheap to build, and switchers notice every one of them in their first session. Priority is marked **P0** where a switcher hits the gap in the first hour.

| # | Convention | Arcus status | Evidence (code) | Fix if not Present |
|---|---|---|---|---|
| 1 | Task ribbon: Modify, Architecture, Structure, Insert, Annotate, Massing & Site, View, Manage, each with titled panels and split buttons | Present | `UI/CommandDeck/Ribbon.swift` `RibbonTab`, `RibbonContent.panels` | — |
| 2 | Contextual "Modify \| Place X" / "Modify \| Walls" tab that appears on tool start or selection, with a Draw panel and Finish/Cancel Mode panel in sketch mode | Present | `RibbonView.contextualPanels`, `RibbonContent.selectionPanel`, `DrawPanel`, `ModePanel` | — |
| 3 | Ribbon minimise states | Partial | Tabs-only collapse via chevron or tab double-click (`state.ribbonCollapsed`) | Low priority: add a "panel titles only" state if users ask |
| 4 | Quick Access Toolbar (customisable, "Add to Quick Access") | Partial | Fixed window toolbar (`DocumentWindowController`: Previous View, workspace menu) | Make the `NSToolbar` customisable, and add "Add to Toolbar" to the ribbon button context menu |
| 5 | Options Bar under the ribbon, with fields that change per tool | Present | `OptionsBarView`, `OptionControl` (Ribbon.swift) | Individual wall fields are missing; see backlog W3 |
| 6 | Properties palette shows the selection, or the active view when nothing is selected; collapsible groups; Edit Type button | Present | `UI/Inspector/PropertiesView.swift` (`targets`, `groups`, "Edit Type") | — |
| 7 | Type Selector re-types the selection or the next placement | Present | `PropertiesView.typeSelector` | — |
| 8 | Duplicate / Rename in Type Properties (duplicate-before-edit habit) | Present | `TypePropertiesDialog` (`UI/Shell/Dialogs/ManageDialogs.swift`) | Load… button and live preview are P2 |
| 9 | Project Browser tree with live search, double-click to open, right-click Rename / Duplicate / Delete, F2 | Present | `UI/Navigator/NavigatorView.swift` (Filter field, `onTapGesture(count: 2)`, `contextMenu`) | — |
| 10 | Drag a view or schedule from the browser onto a sheet | Partial | Rows are `.draggable` but nothing accepts the drop | Add a drop target on sheet canvases that runs the Place View flow at the drop point (backlog S1) |
| 11 | Window title names the active view ("Floor Plan: Level 1") | Present | `DocumentState.updateWindowSubtitle` | — |
| 12 | View Control Bar: scale, detail level, visual style, crop, show crop, temporary hide/isolate (glasses icon), reveal hidden | Present | `ViewControlStrip` (`UI/Shell/ContentArea.swift`) | Sun/shadows toggle and 3D view lock are backlog V9/V10 |
| 13 | Temporary Hide/Isolate draws a coloured frame; Reveal Hidden uses a second colour | Present | `Canvas2DView.drawTemporaryVisibilityFrame` (teal / pink) | — |
| 14 | Status bar: tool prompt, hovered "Category : Family : Type", selection count with filter, Select Links / Underlay / Pinned toggles | Present | `StatusBarView`, `Canvas2DView.describe`, `DocumentState.prompt` | "Select elements by face" and "Drag elements on selection" toggles are P2 |
| 15 | Two-letter typed shortcuts, no Return, editable | Present | `Canvas2DView.keyDown` alias buffer (1.2 s), `KeyboardAliases`, `KeyboardShortcutsDialog` | — |
| 16 | **P0** Alias gaps and clashes | Partial | Missing: `CS` Create Similar, `BX` Selection Box, `RT` Room Tag, `SO` Snaps Off, snap-override codes. Clashes: Arcus binds `SE` to Section and `ST` to Stair, but switchers use these as endpoint and tangent snap overrides. Arcus binds `EL` to Elevation view, but switchers use it for Spot Elevation | Add the missing aliases as their features land. Free `SE`/`ST`/`EL` for their Revit meanings and keep Section/Stair/Elevation on the ribbon, ⌘K and user aliases. Record the decision in `Docs/DecisionLog.md` |
| 17 | Esc once cancels the step; Esc twice returns to Modify and clears the selection | Present | `DocumentState.escape`, per-tool `escape()` | — |
| 18 | Return finishes a chain or sketch | Present | `Canvas2DView.keyDown` (36/76), `ModePanel` ⌘↩ | — |
| 19 | Ctrl-click adds and Shift-click removes (BIM convention) | Present, mapped to ⌘ | `SelectionModel.ModifierStyle.bim` is the default (`AppDelegate`), with a Settings toggle | — |
| 20 | Window selection (left→right) vs. crossing selection (right→left) | Present | `Canvas2DView.windowSelect` (`crossing = b.x < a.x`) | — |
| 21 | Tab cycles overlapping elements under the cursor | Present | `SelectionModel.cycle`, `Canvas2DView` keyCode 48 | — |
| 22 | Tab over a joined wall selects the whole chain | Missing | `cycle()` only steps through hit candidates | Add chained candidates (walls joined end to end, via `WallGeometry` joins) as the last Tab entry (backlog M13) |
| 23 | Select Previous (Ctrl+← / right-click) | Missing | Not in `SelectionModel` or the context menu | Keep the last non-empty selection and add a `selectPrevious` command with ⌃← |
| 24 | Live temporary dimensions and typed length while drawing | Present | `ToolPreview.tempDims`, `beginNumericEntry` (accepts units and formulas) | — |
| 25 | **P0** Select a placed element and it shows temporary dimensions to nearby references; click the number, type, Enter to move it | Missing | `SelectTool` makes `tempDims` only while dragging (`AnnotationTools.swift`) | Backlog M1 |
| 26 | **P0** Type an exact value while dragging a grip or selection | Missing | Numeric entry only opens when `activeTool?.numericLabel != nil` | Give `SelectTool` a `numericLabel` while dragging (backlog M1) |
| 27 | Promote a temporary dimension to a permanent one (small icon) | Missing | — | Backlog M1 |
| 28 | **P0** Flip arrows drawn on a selected wall, door or window, clickable | Missing | `GripService` kinds are start, end, point, crop, dimension, tag, text, section and vertex only. Flips work through commands, the context menu, and Space while placing | Add `Grip.Kind.flipFacing`, `.flipHand` and `.flipWall` and draw arrow glyphs (backlog M2) |
| 29 | Endpoint drag handles | Present | `GripService.grips`, `Canvas2DView.drawGrips` | — |
| 30 | Space while placing flips a door or window, rotates a component, flips a section | Present | `InsertTool.spaceBar`, `ComponentTool.spaceBar`, `SectionTool.spaceBar` | Space while drawing a wall should flip the exterior side; `WallTool` has no `spaceBar` (backlog W4) |
| 31 | **P0** Hold Shift to constrain drawing and dragging to horizontal or vertical | Missing | `ToolInput.shift` is set but no tool reads it. The default 15° angle snap is automatic | Backlog M3 |
| 32 | Object snaps with a distinct glyph per kind and the snap name in the status bar | Present | `SnapKind` (endpoint, midpoint, intersection, center, quadrant, perpendicular, tangent, nearest, grid intersection), `drawSnap`, `snapDescription` | — |
| 33 | Snaps dialog (per-kind on/off, Snaps Off, length and angle increments) | Missing | `SnapSettings.enabled`/`snapsOn` exist but have no UI. Settings has only snap distance | Backlog M4 |
| 34 | One-shot snap overrides (typed code or right-click ▸ Snap Overrides) | Missing | `SnapKind.midBetweenPoints` is declared but never produced | Backlog M4 |
| 35 | Tab cycles snap candidates at the cursor while a tool runs | Missing | Tab always cycles element hits | Backlog M4 |
| 36 | Right-click context menu on an element | Present | `ContextMenuBuilder` (`UI/Shell/Actions.swift`): Select All Instances, Edit Type, flips, Move, Copy, Pin, Hide, Isolate, Group, Delete, V/G | Add Create Similar, Select Previous, Snap Overrides, Override Graphics in View, and Go to View on view markers |
| 37 | Double-click editing (sketch, group, text, type) and double-click a marker to open its view | Present | `CommandRouter.doubleClick`, `Canvas2DView.doubleClick` | Double-clicking a viewport opens the view in a tab instead of activating it on the sheet (backlog S2) |
| 38 | Mouse and trackpad: middle-drag pans, wheel zooms at the pointer, pinch, two-finger pan | Present | `Canvas2DView.otherMouseDragged`, `scrollWheel`, `magnify` | BL-SITE: middle-button double-click zooms to fit; one wheel notch is the same ratio (×1.18) as in 3D views |
| 39 | 3D: Shift+middle-drag orbits, drag orbits, section box with face handles | Present | `Viewport3DView` (drag modes, `handleDirections`) | — |
| 40 | 3D orientation cube: faces, edges, corners, home, compass, hover highlight, right-click "orient to…" | Partial | `OrientationWidget.swift`: faces, top corners, home, compass and hover. No edges, no bottom corners, no context menu | Add edge and bottom-corner hotspots, and a menu with orient to direction, orient to view, and toggle perspective (backlog V8) |
| 41 | Zoom family: Region, Out 2×, To Fit, Sheet Size, Previous/Next Pan-Zoom, navigation bar | Present | New in this tree: `NavigationBarView` (ContentArea.swift), `zoomOutTwice`, `zoomSheetSize`, `previousPanZoom`/`nextPanZoom` (Commands.swift, CommandRouter.swift) | — |
| 42 | Closing view tabs and Close Inactive Views | Present | `ViewTabBar`, `closeHiddenViews` | — |
| 43 | Renaming a level asks whether to rename its views | Missing | No such prompt in `NavigatorView.commitRename` or the parameter setters | Backlog V6 |
| 44 | "Stay on the Modify tab after finishing a tool" preference | Present | `ribbon.stayOnModify` (Settings, Ribbon.swift) | — |
| 45 | Copy in one project, paste in another | Missing | `clipboard` is per-document (`DocumentState.clipboard`) | Backlog M11 |
| 46 | Ribbon tooltips show the shortcut | Present | `RibbonButton.tooltip` (shortcut and aliases) | — |

## 3. Feature backlog

Priority:

- **P0:** a switcher hits it in the first hour.
- **P1:** common in a typical project.
- **P2:** advanced.

Each area starts with a line listing the features verified as present, so they are not rebuilt. Rows cover Partial and Missing items. Sketches name the files each item likely touches (paths are relative to `Arcus/`).

### Walls and curtain walls

Present: basic and compound walls with 6 location lines, chain, unconnected or level-to-level height, joins (corner, tee, multi-way), allow/disallow joins, flip, attach/detach top and base, edit/reset profile, slanted walls (`slantAngle`), room bounding, a wall Function type parameter (`type.function`), and the layer editor with Insert/Delete/Up/Down (`AssemblyEditor`).

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| W1 | Curtain walls: grids, panels, mullions | Missing | P1 | Add a `CurtainSpec` to `TypeData` (vertical and horizontal layout as none, fixed distance, max spacing or count; panel type; interior and border mullion types). Add per-instance grid and segment overrides to `WallData`. New `Domain/Regeneration/CurtainWallGeometry.swift` builds panel and mullion meshes plus plan graphics. Curtain Grid and Mullion tools go in a new `Application/Tools/CurtainTools.swift`; export as `IfcCurtainWall` in `Infrastructure/Exchange/IFC/IFCFileBuilder.swift` |
| W2 | Curtain panel swap (glazed, empty, solid, door) | Missing | P1 | Panels become addressable sub-elements (by grid cell index) with a Type Selector override map on the wall. Tab-select a panel in `Canvas2DView` hit testing |
| W3 | Wall Options Bar: Height/Depth toggle, Radius, Join Status | Partial | P1 | Extend `WallTool.options` (`Application/Tools/DrawingTools.swift`). A negative-direction height writes `baseOffset`; Join Status writes `allowJoinAtStart/End` when the wall is created |
| W4 | More wall draw modes (circle, inscribed/circumscribed polygon, tangent-end arc, fillet arc) and Space to flip the side while drawing | Partial | P1 | Add `Mode` cases in `WallTool`. Fillet trims both host walls through `ElementOperations`. Add `spaceBar()` to toggle `flipped` on the preview |
| W5 | Wrapping at inserts and at ends | Partial | P1 | Data exists (`CompoundAssembly.wrappingAtInserts/AtEnds`) but `WallGeometry` never reads it and `AssemblyEditor` has no control. Add two pickers, then return layers around inserts in `WallGeometry` (insert jambs) and at free ends |
| W6 | Stacked walls | Missing | P2 | Add a `StackedSpec` on `TypeData` (rows of basic type, height, offset; exactly one row with variable height). Regeneration splits into sub-solids |
| W7 | Wall sweeps and reveals (instance and type-level) | Partial (W2-DWG: instance sweep with height, projection, depth, side and material; no reveals, no profile families, no type-level sweeps) | P2 | Profile families already exist (`FamilyTemplate.profile`). Add a `WallSweepData` hosted element and a sweep mesh along the wall station in `ElementMeshes.swift` |
| W8 | Tapered walls, Cut Profile, full structural-usage enum | Missing / Partial | P2 | `WallData.structural` is a Bool: widen it to an enum. Taper needs per-face angles in `WallGeometry` |
| W9 | Core boundary as a range in the layer editor | Partial | P2 | `coreStart`/`coreEnd` are derived. Expose the range in `AssemblyEditor` |

### Floors, roofs and ceilings

Present: floor sketch and Pick Walls with Extend into Wall, slope arrow (`SlopeArrow`), roof by footprint with per-edge Defines Slope and overhang, Roof – Pick Walls (hip), ceiling sketch or pick-room fill, openings as inner sketch loops, sketch validation with specific messages (`SketchValidationError`).

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| F1 | Shape editing: Modify Sub Elements, Add Point, Add Split Line, Reset Shape (drainage falls) | Missing | P1 | Add `SlabData.shapePoints: [SlabPoint]` and `splitLines`. Triangulate the top face in `Domain/Regeneration/SlabRoofGeometry.swift`. Add a new `ShapeEditTool` and commands `modifySubElements`, `addPoint`, `addSplitLine` and `resetShape` in the floor/roof contextual panel |
| F2 | Roof by extrusion (open profile on a work plane) | Missing | P1 | Add `RoofData.kind` (`.footprint` / `.extrusion(profile, start, end)`). Add a `SketchTool` target that needs an open chain and runs from elevations and sections. Mesh in `SlabRoofGeometry` |
| F3 | Join Geometry / Cut Geometry between solids (floor↔wall, wall-in-wall) | Missing | P1 | Arcus's `joinGeometry`/`unjoinGeometry` commands only allow or disallow wall-end joins. Keep those IDs (they are persisted in alias storage) and add `joinSolids`/`cutSolids` with `ConstraintData(kind: .join)`. Subtract the overlap in `ElementMeshes` and `Quantities` |
| F4 | On finishing a roof or floor, offer to attach the walls below | Missing | P1 | After a `SketchTool` commit, find walls whose tops fall under the new footprint and ask; reuse the `AttachTool` logic |
| F5 | Span direction, slab edge, structural floor flag in UI | Partial (W2-DWG: rectangular thickened slab edge along the outer boundary, width/depth parameters) | P2 | `SlabData.structural` exists. Slab edge is a sweep along a picked slab edge using a profile family |
| F6 | Roof fascia, gutter and soffit as real profiles | Partial (W2-DWG: flat soffit ring under the eaves, depth parameter) | P2 | `RoofData.fascia`/`gutter` are Bools. Replace them with per-edge profile sweeps |

### Openings

Present: door and window openings cut and patched automatically (`WallGeometry.openings`, `FamilyOpening`); floor, roof and ceiling holes drawn as inner sketch loops.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| O1 | Rectangular wall opening (two corners, from an elevation or section) | Missing | P1 | New `OpeningData` (kind `.wall(hostID, s0, s1, z0, z1)`). Feed it into `WallGeometry.openings` next to inserts. Add a tool in a new `Application/Tools/OpeningTools.swift` that is only enabled in vertical views |
| O2 | Shaft opening (one sketch cuts every slab, roof and ceiling between base and top constraints) | Missing | P1 | `OpeningData` kind `.shaft(sketch, baseLevel, topLevel, offsets)`. `SlabRoofGeometry` subtracts shafts that cross each host's elevation. Draw symbolic lines on intermediate plans |
| O3 | By-face and vertical openings on a picked host (incl. beams and columns) | Partial | P2 | Inner loops cover the vertical case for slabs and roofs. By-face needs a work-plane pick |
| O4 | Dormer opening, passage/cased opening family template, "Specify Types" on load | Missing | P2 | Add a template in `StarterLibrary.swift` and a type picker sheet in `FamilyLoader` |

### Stairs, ramps and railings

Present: straight, L and U stairs with landings, automatic railings, run width, top level, desired riser count, stair type rules (`stair.maxRiser`, `stair.minTread`), railings along a path with host following (`RailingData.followsHost`), and railing type height and baluster spacing.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| R1 | Ramp (width, base/top level, max slope, max run before a landing, solid or thin shape) | Missing | P1 | Add `RampData` (run path, width, levels) and `RampGeometry` next to `StairGeometry.swift`. The tool shows the required length while drawing and warns rather than blocking when the length does not match (Model Health) |
| R2 | Edit an existing stair (drag run width, move risers between flights, reshape the landing) | Missing | P1 | Grips for `StairData` in `GripService` plus an "Edit Stair" mode |
| R3 | Spiral stairs, winders, sketch-based stairs (boundary, riser, path), multistorey Connect Levels | Missing | P2 | Add cases to `StairShape`. For sketch stairs, `StairData` holds explicit riser curves |
| R4 | Rail structure and baluster pattern editors, Place on Host, Reset Railing | Partial | P2 | Replace the scalar type parameters with a `RailStructure` table on `TypeData` |

### Components, families and the Family Editor

Present: component, door and window placement with Tag on Placement; Load Family, Reload Family and Type Catalog CSV; the Family Editor (`UI/FamilyEditor/FamilyEditor.swift`) with parameters, formulas (units, `if`, `and`, trig, cycle detection), reference planes with formula offsets, extrusions and voids, symbolic lines, fills, labels, types, and Flex Test as a save/load gate; project-level shared parameters (Import/Export Shared… in `ProjectParametersDialog`).

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| C1 | **Create Similar** (right-click, `CS`): starts the element's placement tool with its type preselected | Missing | **P0** | A `CommandRouter` map from category to tool command, then set `ToolContext.currentTypes[category]`. Add a `createSimilar` CommandID, a context-menu item and a ribbon button in the selection panel |
| C2 | EQ constraint and a dimension list in the Family Editor | Present | P1 | Planes & Dimensions tab (`UI/FamilyEditor/FamilyConstraintsPane.swift`): planes A/B/C, label parameter, EQ, lock, conflict marker. Solved in `FamilyConstraintSolver` (`Domain/Model/FamilyFormGeometry.swift`), drawn in the preview |
| C3 | Sweep form (path plus closed profile or profile family) | Present | P1 | `FamilySolid.Profile.sweep` (sketched profile or embedded profile family), meshed in `FamilyEvaluator`; Forms tab. Blend and revolve also added (C8). Void extrusions cut extrusions; void sweeps/blends/revolves are not offered |
| C4 | Nested families (hardware, 2D swing symbols) with associated parameters | Present | P1 | `FamilyDefinition.nestedFamilies`/`nestedInstances` with bindings (host formulas), rotation, mirror, visibility; cycle and depth guards. Shared nested families load into the project as their own families; nested copies are not scheduled separately. Nested tab |
| C5 | Reload choice: keep project values vs. overwrite values | Present | P1 | `FamilyProjectLoader.load(_:replacing:mode:in:)`; Keep Project Values / Use Family Values prompt on Load, Reload and Load into Project |
| C6 | Visibility settings per element (plan / cut / detail level, Yes-No parameter) | Present | P1 | Forms: 3D, Plan, Front/Back, Left/Right, detail levels, Yes/No parameter; Lines and nested instances: detail levels and parameter. `MeshPart.views` filters 3D and elevations; Preview Visibility toggle in the editor |
| C7 | Rotate after placement, Moves With Nearby Elements | Missing | P2 | Add a `ComponentTool` option that chains into `RotateTool` |
| C8 | Blend, revolve, swept blend; family category change; Always Vertical / work-plane-based flags; reference-plane strength column | Partial | P2 | Blend, revolve and the reference-plane strength column are Present (WP7). Swept blend, category change and placement flags are Missing |
| C9 | Canvas-based family authoring (sketch planes in views, dimension then Label) | Missing (table UI today) | P2 | Large. Reuse `Canvas2DView` for family views after C2 lands |
| C10 | In-place (project-only) families, family thumbnails | Missing | P2 | `FamilyPackage.write` already accepts `thumbnailPNG` |

### Rooms and areas

Present: Room tool with Tag on Placement, room separators, upper limit and offsets, room tags (plain and with area), room schedules, area and area boundary tools, `AreaSchemeData`, `ViewKind.areaPlan` rendering.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| A1 | Color schemes (by value or by range) and a Color Fill Legend | Missing | P1 | Add a `ColorSchemeData` element (category, parameter, rows of value/range → colour and pattern) and `ViewData.colorSchemeID`. Fill regions in `Domain/Views/PlanGraphics.swift`. The legend is an annotation element that lays out rows automatically |
| A2 | Area plans and schemes: create dialog, Gross/Rentable defaults, automatic boundary from walls | Partial | P1 | The view kind renders, but no command creates one. Add `areaPlan` to `NewViewDialog` and seed default schemes in `ProjectTemplates.swift` |
| A3 | Place Rooms Automatically | Missing | P1 | Iterate over the enclosed regions from `RoomGeometry`; add a button in the Room tool's contextual panel |
| A4 | Area/volume computation settings (boundary at finish, center or core; volumes on) | Missing | P2 | A project setting read by `RoomGeometry` |
| A5 | Room tag with volume; room tag "move back into room" prompt | Partial / Missing | P2 | Add a template in `StarterLibrary.swift` |

### Views and visibility

Present: floor, ceiling, structural and area plans; sections (with a flip on Space); elevations; callouts; drafting and legend views; 3D; view range; crop and annotation crop; far clip; underlay level; V/G with Model, Annotation, Filters, Links and Template tabs (halftone, weight, transparency); filters; view templates (apply, create from view); temporary and permanent hide/isolate; reveal hidden; detail level; five visual styles; section box; Save 3D Orientation; duplicate, with detailing, and as dependent.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| V1 | Camera (perspective) view: two clicks in a plan, eye then target, with eye height as an offset from the level | Missing | P1 | `ViewData.camera.isPerspective` and `Viewport3DView.setPerspective` already exist. Add a `cameraView` command and tool, and draw a camera glyph in plans (Show Camera) |
| V2 | Scope boxes that limit where levels, grids and reference planes appear | Missing | P1 | Add `ScopeBoxData` (plan rect, height, name) and a `scopeBoxID` on level, grid and reference-plane data, checked in `Domain/Views/DatumGraphics.swift` |
| V3 | Selection Box (`BX`): 3D view cropped to the selection | Missing | P1 | Build a `Box3` from the selection bounds and set it on the active or default 3D view's section box |
| V4 | Override Graphics in View ▸ By Element (halftone, lines, patterns, transparency) | Partial | P1 | `VGData.elementOverrides` is applied in `Visibility.swift` but nothing sets it. Add a dialog reachable from the context menu |
| V5 | Level and grid controls on the canvas: bubble per end, elbow, 2D/3D extents, alignment lock | Partial | P1 | Data exists (`showBubbleStart/End`, `bubbleAtStart/End`, `extentStart/End`). Add grips and toggles in `GripService` and draw them in `DatumGraphics.swift` |
| V6 | Renaming a level asks to rename its plan views | Missing | P1 | Hook the level-name set path in `NavigatorView.commitRename` and in the parameter setter |
| V7 | Grid: Pick Lines, arc and multi-segment modes | Missing | P1 (pick) / P2 | Extend `LineTool` (kind `.grid`) in `DrawingTools.swift` |
| V8 | Orientation cube completeness and "orient to view" | Partial | P2 | `OrientationWidget.swift` |
| V9 | Lock a 3D view (needed before tagging in 3D) | Missing | P2 | A `ViewData.orientationLocked` flag that disables orbit |
| V10 | Sun, shadows and solar studies | Missing | P2 | `ProjectInfoData` already has latitude, longitude and true north. Add a shadow map to `UI/Canvas3D/Shaders.swift` |
| V11 | Plan regions, segmented sections, reference-other-view sections and callouts, Find Referring Views / Go to View, Apply Hide/Isolate to View, view discipline, depth cueing, work plane Set/Show, walkthroughs | Missing | P2 | — |

### Annotation and detailing

Present: aligned, linear, angular, radial, diameter and arc-length dimensions with a Prefer option (wall centerlines, faces, core faces); EQ display (`AnnotationGraphics`); lock, prefix, suffix and override; spot elevation, coordinate and slope; text with leaders; tag by category; Tag All Not Tagged (one pass); detail lines, filled and masking regions, detail components, insulation, revision clouds tied to revisions; symbols and north arrow.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| N1 | Dimension "Entire Walls" pick with openings (centres or widths) and intersecting walls | Missing | P1 | Add a `DimensionTool` option `pick: individual/entireWalls` that collects references from `WallGeometry` faces and `openings` |
| N2 | Witness-line editing (drag to another reference, add, remove) | Missing | P1 | `DimensionData.references` is editable; add per-witness grips in `GripService` and an `editWitnessLines` mode |
| N3 | Click the EQ glyph or padlock on a dimension to toggle it | Partial | P1 | The flags exist and are only editable in Properties. Add hit targets for the canvas grips |
| N4 | Tag All dialog (category list, selected only, leader and length, orientation) | Partial | P1 | Replace the one-shot `CommandRouter.tagAll()` with a `TagAllDialog` in `ViewDialogs.swift` |
| N5 | Baseline/ordinate strings, alternate units, keynotes (element, material, user) and keynote legend, multi-host tags, material tag, rich text formatting, Model Text, repeating detail, legend component | Partial | P2 | Wave 2 (D36): keynotes, material/area/multi-category tags, repeating details, legend components, per-note bold/italic/underline, line styles, tread numbers, view references, span direction, stair paths, scale bars, Find/Replace and Check Spelling. Still missing: keynote legend, alternate units, multi-host tags, per-character formatting, Model Text; MEP legends and space tags are left out on purpose |

### Schedules

Present: category, multi-category, material takeoff, key schedule, sheet list, view list, revision schedule and note block (`ScheduleKind`); formula, percentage and room-parameter fields; filters; sorting and grouping with header, footer and blank line; grand totals with a title; itemize; per-field heading, alignment, hidden and totals; conditional formatting; editing in cells writes to the model; clicking a row selects elements; phase filter; CSV export and import.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| H1 | Appearance: stripe rows, freeze header, grid and outline styles, grouped column headers | Missing | P2 | Add appearance fields on `ScheduleDefinition`; render in `ScheduleTableView.swift` and `SheetGraphics` |
| H2 | Combined parameters, images, splitting a schedule across sheets | Missing | P2 | — |

### Sheets and output

Present: New Sheet with a title block, Place View on Sheet, one view per sheet enforced (`Regenerator`), title on sheet, guide grid spacing (`SheetData.guideGridSpacing`), sheet list, revisions, vector PDF export, print.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| S1 | Drag a view or schedule from the Project Browser onto a sheet | Partial | P1 | Add a drop destination on the sheet canvas (`arcus-element:` payload) that reuses the `PlaceViewDialog` commit path |
| S2 | Activate and deactivate a view on the sheet (edit in place, other viewports dimmed) | Partial | P1 | Double-clicking a viewport opens the view today. Add `DocumentState.activeViewportID`; the sheet canvas routes input into the viewport's view transform |
| S3 | Named reusable guide grids, viewport types (title on/off), rotation on sheet, sheet duplicate variants, saved print and export sets | Partial / Missing | P2 | — |

### Modify tools

Present: move and copy (Constrain, Multiple), rotate (copy, movable centre), mirror by picked or drawn axis, linear array (number, Move To Last), align with lock, offset with copy, the three trim/extend tools, split, pin and unpin (blocks delete), match type, paint and remove paint (whole element), groups (create, edit, finish, ungroup), and paste aligned to the same place, selected levels or current view.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| M1 | **Temporary dimensions on selection**: dimensions to the nearest parallel references, click to type, typed value during grip or selection drags, promote to permanent | Missing | **P0** | In `SelectTool`, compute `tempDims` for a single selected wall, insert, component or grid (nearest parallel wall faces, grids, openings) using `SnapIndex.nearestSegment`. `Canvas2DView` hit-tests the dimension text and opens `beginNumericEntry` to move the element by the difference. Set `numericLabel` while dragging |
| M2 | **On-canvas flip controls** | Missing | **P0** | Add `Grip.Kind.flipWall`, `.flipFacing` and `.flipHand` in `GripService`. Clicking one runs the existing flip commands. Draw arrows in `Canvas2DView.drawGrips` |
| M3 | **Shift constrains to orthogonal** while drawing or dragging | Missing | **P0** | `Canvas2DView.input(for:)` passes Shift to `ToolContext.snap(orthoOnly:)`. Project onto the nearest axis before the object snap, so snaps slide along the constrained line |
| M4 | Snaps dialog, Snaps Off (`SO`), one-shot overrides (typed codes and a context submenu), Tab through snap candidates | Missing | P1 | A new `SnapsDialog`; save `SnapSettings` in project settings. `ToolContext.pendingOverride: SnapKind?` is cleared after one pick. Produce `midBetweenPoints` from two picks |
| M5 | Measure between two references (chain total) and along an element | Missing | P1 | A new `MeasureTool` that draws temporary dimensions only and commits nothing |
| M6 | Disjoin on Move and Rotate | Missing | P1 | A `MoveCopyTool`/`RotateTool` option. When set, `ElementOperations.transform` skips join-following and allows re-hosting inserts |
| M7 | Radial array, Group and Associate, count editable afterwards, Constrain | Partial | P1 | Store an `ArraySpec` on `GroupData`; regenerate members when the count changes; add a radial mode to `ArrayTool` |
| M8 | Offset carries hosted doors and windows; Tab picks the wall chain | Partial | P1 | Copy hosted inserts with the new host ID in `OffsetTool` |
| M9 | Split: Delete Inner Segment; Split with Gap | Missing | P1 / P2 | `SplitTool` options |
| M10 | Demolish tool (sets Phase Demolished to the view's phase, cascades to hosted inserts) | Missing | P1 | The phase data and demolished graphics exist (`Visibility.swift`). Add a pick tool in `MiscTools.swift` |
| M11 | Copy/paste between open projects | Missing | P1 | Move `ClipboardPayload` to an app-level `ClipboardStore`; map types and materials by name on paste, with a "duplicate types" report |
| M12 | Select Previous; Select by ID and IDs of Selection | Missing | P1 / P2 | `SelectionModel.previous` |
| M13 | Tab chain-select of joined walls | Missing | P1 | Walk joins from `WallGeometry` in `SelectionModel` |
| M14 | Scale; group exclude/restore and attached detail groups; save and load groups; paste aligned to picked level or selected views; Align with multiple targets or preferring faces; Split Face and paint per face | Missing / Partial | P2 | — |

### Massing and site

Present: toposurface from points, from a CSV/TXT/XYZ point file and from the contour layers of a DXF/DWG link or import; contours from Site Settings (interval, primary every N, on/off); Sub-Region (own material), Split Surface, Merge Surfaces, Graded Region (existing demolished in the view's phase, copy opens in Edit Surface), Edit Surface (add, delete, re-level points), Label Contours; Parking Layout (90°/60°/45° stalls, aisle, optional wheel stops, stall count); Site Component and Parking Component commands (fall back to the Component tool until the component library browser lands); building pad, property lines (sketch), project base point and survey point data (`ProjectInfoData`), Location & Coordinates dialog. (W2-DWG: `Domain/Regeneration/SiteEditing.swift`, `SiteOperations.swift`, `Application/Tools/SiteTools.swift`.)
BL-SITE: **Toposolid** is the primary site element — sketched (Line, Rectangle, Pick Lines), from point files or CAD imports, layered by its type's compound structure (variable layer to a flat base), shape-edited with Edit Surface (add/set/delete points, Split Line), Sub-Divide (thin layered solids following the host), Split, Merge, Simplify Surface, Excavate (by floors/pads, cut/fill recorded), contours in plan, per-layer section cuts, schedules and IFC (IfcGeographicElement). Toposurface and Building Pad creation moved to a Legacy panel; Generate Toposolid converts toposurfaces. Gaps: floors and pads don't cut toposolids automatically (use Excavate); shape-edit copy/paste; 50k-point surfaces (points are thinned to 2,500).

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| G1 | Show and move the project base point and survey point in views (for aligning CAD links) | Partial | P1 | Draw the points in `PlanGraphics` behind a V/G "Site" category, with grips that edit `ProjectInfoData` |
| G2 | Topography editing (add, move and delete points; split; sub-divide), from CSV or DXF points, contour display settings, label contours | Present (W2-DWG) | P2 | Moving points by drag is not offered (re-level or delete and add) |
| G3 | Property line from distances and bearings; site and parking components on terrain; graded regions with cut/fill | Partial | P2 | Graded regions and parking layouts exist; no cut/fill volumes, no bearing table, components are not hosted on the terrain |
| G4 | Conceptual massing (in-place or placed masses, mass floors, by-face walls, floors, roofs and curtain systems) | Missing | P2 | Large; after W1 and C3 |

### Visualization and rendering

Present: Metal 3D views with Wireframe, Hidden Line, Shaded, Consistent Colours and Transparent styles; material colour, transparency, and surface and cut patterns (`MaterialData`); Materials dialog (list, new, duplicate, edit).

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| Z1 | Realistic style with textures, material appearance assets | Missing | P2 | Add texture slots to `MaterialData`; add a textured pass in `Shaders.swift` |
| Z2 | Offline renderer (local Metal ray tracing), exposure, render regions, saved renderings | Missing | P2 | Only local, on-device rendering fits the privacy stance |
| Z3 | Walkthroughs and animation export; decals | Missing | P2 | — |

### Collaboration and management

Present: phases (add, rename, delete) with per-view phase and phase filter (6 presets); design options (sets, options, primary, add the selection, show an option in a view); purge unused; Model Health; project parameters; line styles; revisions; built-in project templates.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| P1a | Save a project as a template; pick a user template in New Project | Present | P1 | File ▸ Save as Template (`ArcusPackage.writeTemplate`, manifest `isTemplate`, model elements removed); My Templates and Choose Template File… in the hub picker (`HubAndOnboarding.swift`) |
| P1b | Phases: insert before or after, combine; the Show Previous + Demo filter; custom phase filters with graphic overrides | Partial | P2 | `PhasesDialog`, `PhaseFilter` |
| P1c | Design options: an editing mode for the active option (new elements go into it), active option in the status bar | Partial | P2 | Today, options are assigned from the current selection |
| P1d | Transfer project standards; Project Browser organisation | Missing | P2 | — |

### Interop

Present: IFC2x3/IFC4 import and export; DXF link, import and export; DWG through a user-installed converter (ODA File Converter or LibreDWG dwg2dxf, W2-DWG) or a licensed SDK; PDF and image underlays; schedule CSV; Manage Links; CAD positioning by origin, centre or shared coordinates, with a current-view-only option.

| ID | Item | Status | Pri | Sketch |
|---|---|---|---|---|
| I1 | CAD import colour mode (preserve, black & white, invert) | Missing | P2 | `ImportCADDialog`, `CADConverter` |
| I2 | Query, hide and delete layers on a placed import; DXF export setups (layer maps, named sets) | Partial | P2 | Layer choice is available only at import time (`CADImportOptions.includedLayers`) |
| I3 | Arcus Exchange (`.arcusx`) import in the UI | Partial | P2 | `Infrastructure/Exchange/Revit` (`ArcusExchangeImporter`, `RevitFileInspector`) exists and is tested but has no command. `Docs/RevitInterop.md` is referenced and missing. Any UI copy must say that this reads an open JSON export from an add-in, not RVT files |
| I4 | Linking one `.arcus` project into another | Missing | P2 | — |

## 4. Work packages

This plan covers every P0 and P1 item that is Missing or Partial. The seven packages can proceed in parallel. Each package owns its files outright. Files that several packages touch are listed per package and summarised in the conflict table.

Zoom and navigation (Zoom Out 2×, Sheet Size, Previous/Next Pan-Zoom, navigation bar) are being built in the current tree and are left out.

**Ground rules for shared files:**

1. **Append-only edits.** Each package adds its `CommandID` cases on its own `// WPn` line in `Arcus/Application/Commands.swift` and its `CommandInfo` entries in a matching block. The same rule applies to the router `switch` in `Arcus/UI/Shell/CommandRouter.swift`, to ribbon panels in `Arcus/UI/CommandDeck/Ribbon.swift`, and to new `ElementData` and `Category` cases in `Arcus/Domain/Model/Element.swift` and `Category.swift`.
2. **Never rename persisted IDs.** `CommandID` raw values are stored in user alias preferences, so existing raw values must not change (see F3).
3. **One schema bump.** A single owner (WP4) merges the document schema version bump for all new element data. New fields decode with defaults so older files still open.
4. **Regenerate the shortcut docs once.** Run `arcus-bench --commands-markdown` at the end to regenerate `Docs/KeyboardShortcuts.md`.
5. **Mechanical extractions first.** Four file splits go in before feature work starts (a day-one PR, no behaviour change):
   - `SelectTool` from `AnnotationTools.swift` to `Application/Tools/SelectTool.swift` (WP1)
   - `GripService` from `ElementOperations.swift` to `Application/GripService.swift` (WP1)
   - `WallTool` from `DrawingTools.swift` to `Application/Tools/WallTool.swift` (WP3)
   - `StairTool` from `PlacementTools.swift` to `Application/Tools/StairRampTools.swift` (WP4)
   - `SettingsView` from `HubAndOnboarding.swift` to `UI/Shell/Dialogs/SettingsView.swift` (WP2)
   - `AssemblyEditor` from `ManageDialogs.swift` to `UI/Shell/Dialogs/AssemblyEditor.swift` (WP3)

### WP1: Canvas direct manipulation and selection (most of the P0s)

**Items:**

- M1: temporary dimensions on selection, click to type, typing during drags, promote to permanent (P0)
- M2: flip controls (P0)
- M13: Tab chain-select (P1)
- M12: Select Previous (P1)
- N3: canvas EQ and padlock hotspots (P1)
- N2: witness-line grips (P1)
- V5: level and grid bubble, elbow and extent grips (P1)
- Middle-button double-click zooms to fit

**Owns:** `UI/Canvas2D/Canvas2DView.swift`, `Application/Tools/SelectTool.swift` (extracted), `Application/GripService.swift` (extracted), `Application/SelectionModel.swift`, `Domain/Views/DatumGraphics.swift`.

**Shared:** `Application/Commands.swift` (`selectPrevious`, `editWitnessLines`), `UI/Shell/CommandRouter.swift`, `UI/Shell/Actions.swift` (context menu: Select Previous), `Application/Tools/AnnotationTools.swift` (N2 witness mode is shared with WP6's N1).

**Tests** (`Tests/DomainTests/ApplicationTests.swift`, new `SelectToolTests.swift`):

- A selected wall between two parallel walls reports two temporary dimensions with the right values.
- A typed value moves the wall by the exact difference, and the result is identical to dragging to the same point.
- A flip grip toggles `WallData.flipped` and `InsertData.facingFlipped`/`handFlipped` independently.
- Tab over one wall of a closed four-wall loop yields all four.
- Select Previous restores the prior set after Esc.
- A witness drag re-references the dimension without changing its element IDs.

### WP2: Snapping, keyboard and app conventions

**Items:**

- M3: Shift orthogonal constraint (P0)
- §2 #16: alias gaps and clashes (P0). Adds `CS` (wired once WP5 lands C1), `BX` (once WP6 lands V3), `RT`, `SO`, the snap codes, and freeing `SE`/`ST`/`EL`, recorded in `Docs/DecisionLog.md`.
- M4: Snaps dialog, Snaps Off, one-shot overrides with a context submenu, Tab through snap candidates inside tools (P1)
- §2 #4: customisable toolbar (P1)

**Owns:** `Application/Snapping.swift`, `Application/ToolFramework.swift`, `UI/Shell/KeyboardAliases.swift`, new `UI/Shell/Dialogs/SnapsDialog.swift`, `UI/Shell/Dialogs/SettingsView.swift` (extracted), `UI/Shell/DocumentWindowController.swift` (toolbar).

**Shared:**

- `UI/Canvas2D/Canvas2DView.swift` (WP1 owns it): two hooks, Shift into `input(for:)` and Tab routing while a tool runs. WP1 reviews both.
- `UI/Shell/Actions.swift`: the Snap Overrides submenu.
- `Application/Commands.swift`: `snapsDialog`, `snapsOff` and the override IDs.
- `Docs/KeyboardShortcuts.md`.

**Tests** (new `Tests/GeometryTests/SnapTests.swift`, `ApplicationTests`):

- Shift turns a 3° line into a 0° line and still snaps to an endpoint lying on that axis.
- Disabled snap kinds are never returned.
- An override applies to exactly one pick.
- The default alias table has no duplicates, and every alias resolves to an existing `CommandID`.

### WP3: Walls, curtain walls and openings

**Items:**

- W1, W2: curtain walls and panel swap
- W3: wall Options Bar fields
- W4: wall draw modes and Space flip
- W5: wrapping (UI and geometry)
- O1: wall opening
- O2: shaft opening

**Owns:** `Application/Tools/WallTool.swift` (extracted), new `Application/Tools/CurtainTools.swift` and `Application/Tools/OpeningTools.swift`, `Domain/Regeneration/WallGeometry.swift`, new `Domain/Regeneration/CurtainWallGeometry.swift`, `UI/Shell/Dialogs/AssemblyEditor.swift` (extracted).

**Shared:**

- `Domain/Model/TypesAndMaterials.swift` (`CurtainSpec`)
- `Domain/Model/ModelElements.swift` and `Element.swift` (`OpeningData`, curtain overrides)
- `Domain/Regeneration/SlabRoofGeometry.swift` (shaft cuts; WP4 owns this file, so WP3 adds only one `externalCuts(for:)` call)
- `Domain/Regeneration/ElementMeshes.swift`
- `Domain/Views/PlanGraphics.swift` and `VerticalGraphics.swift`
- `Domain/Parameters/BuiltInCatalog.swift`
- `Infrastructure/Exchange/IFC/IFCFileBuilder.swift`
- Commands, Router, Ribbon (Build panel: Curtain Grid, Mullion, Opening split button)

**Tests** (`WallGeometryTests`, `WallSolidTests`, `IFCTests/ExportTests`):

- A curtain wall with fixed 1.5 m spacing on a 6 m wall has 4 panels and 3 interior mullions.
- Changing the spacing regenerates both counts.
- Wrapping at inserts adds return faces at the jambs.
- A wall opening reduces `Quantities` area by w × h.
- A shaft spanning three levels cuts each slab in range and nothing outside it.
- A curtain wall exports as `IfcCurtainWall`.

### WP4: Floors, roofs, stairs and ramps

**Items:**

- F1: shape editing
- F2: roof by extrusion
- F3: solid join and cut geometry
- F4: attach walls after a roof or floor
- R1: ramp
- R2: edit stair

WP4 also holds the single schema-version bump.

**Owns:** `Domain/Regeneration/SlabRoofGeometry.swift`, `Domain/Geometry/RoofSolver.swift`, `Domain/Regeneration/StairGeometry.swift` (plus the new ramp geometry), `Application/Tools/SketchTool.swift`, `Application/Tools/StairRampTools.swift` (extracted), a new `ShapeEditTool`, `Infrastructure/Versioning` and the schema constants.

**Shared:**

- `Domain/Model/ModelElements.swift` and `Element.swift` (`SlabData.shapePoints`, `RoofData.kind`, `RampData`)
- `ElementMeshes.swift`, `Quantities.swift` (join and cut volumes)
- `BuiltInCatalog.swift`
- `Application/GripService.swift` (WP1 owns it; WP4 adds stair and sub-element grips as a new extension file)
- Commands, Router, Ribbon

**Tests** (`SlabRoofTests`, `ApplicationTests`, `PersistenceTests`):

- A point at −20 mm makes the top face non-planar, keeps the plan area and reduces the volume.
- Reset Shape restores the original.
- An extrusion roof rejects a closed profile with a specific message.
- A ramp length mismatch creates a Model Health warning and still commits.
- A floor/wall join removes the overlap volume exactly once.
- A file saved at the old schema opens with defaults.

### WP5: Modify tools and clipboard

**Items:**

- C1: Create Similar (P0)
- M5: Measure
- M6: Disjoin
- M7: radial and associative array
- M8: offset with hosted inserts
- M9: delete inner segment
- M10: Demolish
- M11: cross-project paste

**Owns:** `Application/Tools/ModifyTools.swift`, `Application/Tools/MiscTools.swift`, new `Application/Tools/MeasureTool.swift`, and a new app-level `UI/Shell/Clipboard.swift`.

**Shared:**

- `Application/ElementOperations.swift` (Disjoin in `transform`; WP1 extracts `GripService` from this file first)
- `UI/Shell/DocumentState.swift` (the clipboard property moves out)
- `UI/Shell/Actions.swift` (copy and paste, plus the Create Similar menu item)
- `Domain/Model/ModelElements.swift` (`GroupData.arraySpec`)
- Commands, Router, Ribbon (Modify panel)

**Tests** (`ApplicationTests`, `MoveJoinTests`):

- Create Similar on a door starts the Door tool with that type.
- A radial array of 6 over 360° places members 60° apart.
- Editing the array count to 8 regenerates the members.
- Offsetting a wall with a door creates a door hosted on the new wall.
- Disjoin moves a wall without stretching its joined neighbour.
- Demolish sets `phaseDemolished` on the wall and its door.
- A paste between two `DocumentSession`s maps types by name and reports duplicates.

### WP6: Documentation (views, sheets, rooms, annotation)

This is the largest package. It can be split across two engineers along the dashed line: 6a is views and sheets, 6b is rooms and annotation.

**Items:**

- 6a: V1 camera; V2 scope boxes; V3 Selection Box; V4 element graphic overrides dialog; V6 level-rename cascade; V7 grid Pick Lines; S1 drag onto sheet; S2 activate viewport; G1 base point and survey point display
- 6b: N1 entire-wall dimensions; N4 Tag All dialog; A1 colour schemes and legend; A2 area plans and schemes; A3 Place Rooms Automatically

**Owns:**

- `Application/Tools/AnnotationTools.swift` (`DimensionTool`, `SectionTool`)
- The room, tag, spot and elevation tools in `Application/Tools/PlacementTools.swift` (after WP4's stair extraction)
- `UI/Shell/Dialogs/ViewDialogs.swift`, `UI/Navigator/NavigatorView.swift`
- `Domain/Sheets/SheetGraphics.swift`, `Domain/Regeneration/RoomGeometry.swift`
- New `Domain/Views/ColorScheme.swift` and `Domain/Model/ScopeBox.swift`

**Shared:**

- `UI/Canvas2D/Canvas2DView.swift` (WP1 owns it): the sheet drop target and viewport activation input routing
- `Domain/Views/PlanGraphics.swift` (WP3 also edits it; keep colour-fill code in its own function)
- `Domain/Views/DatumGraphics.swift` (WP1 owns it): scope-box filter
- `Domain/Views/ViewData.swift`, `Element.swift`, `ModelElements.swift`
- `Application/Tools/DrawingTools.swift` (`LineTool` grid modes; WP3 has already extracted `WallTool`)
- `UI/Shell/Viewport3DHost.swift` (camera)
- `UI/Shell/Actions.swift` (Override Graphics menu item)
- Commands, Router, Ribbon

**Tests** (`ViewGraphicsTests`, `SheetTests`, `RoomTests`, `ApplicationTests`):

- A grid outside a scope box is not drawn in a plan whose crop lies elsewhere.
- A colour scheme by Department yields one fill colour per value and a legend row per value in use.
- Dropping a view on a sheet creates a viewport; dropping it again raises the one-sheet error.
- Place Rooms Automatically on the courtyard template creates one room per enclosed region.
- Tag All with "only selected" tags only the selected elements.
- An entire-wall dimension on a wall with two windows has 6 references (with widths).

### WP7: Family Editor, content and templates

**Items:**

- C2: EQ and dimensions tab
- C3: sweep
- C4: nested families
- C5: reload choice
- C6: visibility settings UI
- P1a: save as template and user templates

**Owns:** `UI/FamilyEditor/FamilyEditor.swift`, `Domain/Model/FamilyDefinition.swift`, `Domain/Model/FamilyEvaluator.swift`, `Domain/Regeneration/InstanceGeometry.swift`, `Domain/Templates/StarterLibrary.swift`, `Domain/Templates/ProjectTemplates.swift`, `UI/Onboarding/HubAndOnboarding.swift` (template picker; WP2 has already extracted `SettingsView`).

**Shared:** `Infrastructure/Persistence/ArcusPackage.swift` (template flag; `.arcusfamily` schema, coordinated with WP4's schema bump), `Application/Commands.swift` (`saveAsTemplate`), `UI/Shell/MainMenu.swift`.

**Tests** (`DomainTests` family tests, `PersistenceTests`):

- Flexing Width from 900 to 1200 keeps an EQ-constrained centre plane at the midpoint.
- A sweep of a 20 mm square along a 1 m path has a volume of about 0.0004 m³.
- A nested family instance follows the associated host parameter through a formula.
- Reload with overwrite updates existing type values; reload with keep leaves them.
- A project saved as a template and then used for a new project has the same types and views and no model elements.

### Shared-file conflict summary

| File | Touched by | Rule |
|---|---|---|
| `Application/Commands.swift` | All | Append-only per-package blocks; do not rename raw values |
| `UI/Shell/CommandRouter.swift` | All | Append-only `case` routes; one package per `disabledReason` clause |
| `UI/CommandDeck/Ribbon.swift` | WP1–WP6 | Add items to panels only; WP3 owns the Build panel, WP5 the Modify panel, WP6 the View and Annotate panels |
| `Domain/Model/Element.swift`, `Category.swift`, `ModelElements.swift` | WP3, WP4, WP5, WP6 | Append new `ElementData` and `Category` cases; new structs go in new files where possible; WP4 merges the schema bump |
| `Domain/Parameters/BuiltInCatalog.swift` | WP3, WP4, WP6 | New parameter blocks at the end of the file, grouped per package |
| `UI/Canvas2D/Canvas2DView.swift` | WP1 (owner), WP2, WP6 | WP2 and WP6 get small reviewed hooks: Shift/Tab routing; sheet drop and viewport activation |
| `UI/Shell/Actions.swift` | WP1, WP2, WP5, WP6 | Context-menu items added in labelled sections; WP5 owns the clipboard code until it moves to `Clipboard.swift` |
| `Domain/Regeneration/SlabRoofGeometry.swift` | WP4 (owner), WP3 | WP3 adds one call (`externalCuts(for:)`) for shafts |
| `Domain/Views/PlanGraphics.swift` | WP3, WP6 | Separate functions per feature; no reordering of existing passes |
| `Application/ElementOperations.swift` | WP1 (extraction), WP5 | WP1's extraction lands first |
| `Docs/KeyboardShortcuts.md` | Generated | Regenerate once after merge |

## 5. Out of scope

| Item | Why |
|---|---|
| Worksharing: worksets, central/local files, synchronise, borrowing, ownership display | Arcus is single-user and local-only (README; `Docs/VerificationReport.md` limitations). A file-based merge would be a separate product decision |
| Cloud features: cloud rendering, shared views, online family library, construction-cloud integration | Arcus makes no network connections (`Docs/PrivacyAndPermissions.md`) |
| Native RVT/RFA read or write, and any claim of RVT compatibility | Proprietary and undocumented formats. The supported path is IFC. `ArcusRevit` only reads container metadata (`RevitFileInspector`) and an open JSON export (`.arcusx`); neither is RVT support, and UI copy must not suggest it is |
| Autodesk branding, icons, artwork, dialog or help text, and the names ViewCube and SteeringWheels | Legal and brand: behaviour is replicated with original UI and neutral names |
| SteeringWheels-style tracking navigation menu | Replaced by direct trackpad, mouse and keyboard navigation plus the orientation cube and navigation bar. Few experienced users rely on it |
| MEP, structural analysis (analytical models, loads, rebar) and structural detailing | Arcus's scope is architectural authoring (README) |
| Copy/Monitor, Coordination Review, interference check across linked models | These need multi-model linking and a multi-discipline workflow that Arcus does not have |
| Macros, a scripting API, visual programming | Not in scope (`Docs/VerificationReport.md`). Revisit only with a sandboxed design |
| Licensed entourage content formats (RPC) | Proprietary content format; Arcus ships its own placeholder components |
| Point clouds, DWF, NWC, gbXML, FBX, SKP, DGN, SAT export or import | Proprietary or niche formats outside the IFC/DXF/PDF exchange strategy. SKP and DGN may be reconsidered on request |
| Route analysis and people-flow tooling | Specialised analysis. Deferred and not rejected; it would build on rooms and doors once A1–A4 land |

## Appendix: corrections to the research notes

The notes were a starting point. These claims disagreed with the code:

| Note claim | Actual (code) |
|---|---|
| Status bar, Project Browser search, and the window title naming the view are all "Unknown" (ch01-02) | All Present: `StatusBarView`, the `NavigatorView` Filter field, `updateWindowSubtitle` |
| Contextual tab and options bar live in `CommandDeckView.swift` (ch01-02) | They live in `UI/CommandDeck/Ribbon.swift` (`RibbonView`, `OptionsBarView`) |
| Zoom Out 2×, Zoom Sheet Size and Next Pan/Zoom are Missing (ch01-02) | Present in the current tree (Commands.swift, CommandRouter.swift, `NavigationBarView`) |
| Temporary dimensions with a draggable witness reference, and snap overrides including Mid-Between-Two-Points, are Present (b2-part1) | Temporary dimensions appear only while drawing or dragging. Witness editing is Missing. `midBetweenPoints` is declared but never produced, so overrides are Missing |
| Move has Disjoin (b2-part1) | No Disjoin option (`MoveCopyTool`) |
| Layer wrapping is "a single bool" (b2-part1) | Full `WrappingPreference` enums exist for ends and inserts; they have no UI and no geometry effect (W5) |
| A standalone Wall Opening tool is Present (ch04 #37) | `WallOpening` is derived from hosted inserts only; there is no tool or element (O1) |
| There is no wall function or structural concept (ch16) | `type.function` (Exterior/Interior/Retaining/Foundation/Soffit/Core-shaft) and `WallData.structural` exist; only the bearing/shear enum is missing |
| Shared parameters are Missing (ch09-10) | Project-level import and export are Present (`ProjectParametersDialog`). Family-level shared parameters are Missing |
| Conditional formatting, material takeoff and key schedules are Missing (b2-part3) | All Present (`ScheduleKind`, `ConditionalFormat`) |
| The Materials browser is Missing (ch15) | `MaterialsDialog` exists (list, new, duplicate, edit). Appearance assets and textures are Missing |
| Curtain walls are Present "as a wall type" (video.md) | Missing: the only mentions are in IFC and exchange schema comments |
| `SA` selects project-wide in Revit but in-view in Arcus (ch05) | Arcus's `SA` is Select All Instances in View; the project-wide variant has no alias. Left as is; flagged for the alias review in WP2 |

## Open items (wave 4 audit)

Found during the UI audit and Revit-feel sweep (Docs/UIAudit.md); too large to land safely in that wave.

- **Options Bar under ~1100 pt** wraps its labels and overflows the canvas. The reference tool keeps a single-line bar
  and clips; Arcus should collapse rarely used fields (Radius, Join Status) into an overflow menu at narrow widths.
- **Ribbon tabs at 980 pt** disappear into the toolbar's overflow. Show a compact tab popup (as the reference's minimised
  ribbon does) instead of hiding them.
- **Properties inspector column split**: labels take a fixed share, so pickers truncate at every width in Mac Spacious.
  Let the value column win when the label fits on one line.
- **Schedule Properties** uses one height for every tab; Sorting/Grouping and Appearance are mostly empty. Size per tab.
- **Family Editor header** truncates the family name and the Load button at 1280 pt; the "Instance" toggle wraps.
- **Listening dimensions** appear as a floating field beside the cursor; the reference draws the value inside the
  temporary dimension itself. Consider editing the temp-dimension text in place while drawing (the selection already
  supports it).
- **Crossing selection feedback**: the crossing rectangle is dashed (matches), but the reference also tints window and
  crossing rectangles differently; add a light fill.
