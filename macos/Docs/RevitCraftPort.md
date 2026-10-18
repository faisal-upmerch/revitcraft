# RevitCraft port roadmap

Decisions (2026-10-18): the Mac app is the Arcus codebase. It keeps Arcus's look (chrome, spacing, colours, light/dark)
and adopts RevitCraft's Revit-exact behaviour, then every RevitCraft feature it lacks. Behaviour comes first. The Rust
app in `../crates` is frozen and serves as the reference; `rc-app` file and function names below point into it.
macOS 26+ on Apple silicon. Native formats stay `.arcus` and `.arcusfamily`.

Milestone status lives in §5; tick each one off as it lands.


I checked the Swift code under `macos/Arcus` directly, because `Docs/RevitParity.md` is out of date. It still lists Tab wall chains, Create Similar, ramps and colour schemes as missing, and they all exist in the code now. "grep=0" below means no match in `macos/Arcus/{App,Application,Domain,Infrastructure,UI}`, excluding Tests and QA.

## 1. Naming and shell

**Ribbon tabs.** Arcus tabs are defined in `Arcus/UI/CommandDeck/Ribbon.swift:9-13` and their panels in `Ribbon.swift:107-180`. RevitCraft's are in `crates/rc-app/src/ribbon.rs:30` (`Tab::ALL`).

| # | RevitCraft | Arcus | Change |
|---|---|---|---|
| 1 | Architecture | Architecture | — |
| 2 | Structure | Structure | — |
| 3 | Insert | Insert | — |
| 4 | Annotate | Annotate | — |
| 5 | **Analyze** | (none; grep `Analyze`=0) | Add the tab |
| 6 | Massing & Site | Massing & Site | — |
| 7 | View | View | — |
| 8 | Manage | Manage | Remove the extra **Output** panel (Export PDF/IFC/DXF, Print). It belongs in the File menu |
| 9 | Modify | Modify | — |

**Panels.**

| Tab | RevitCraft (`ribbon.rs`) | Arcus (`Ribbon.swift`) | Change |
|---|---|---|---|
| Every tab | Starts with a **Select** panel (`architecture()` :80 and the others) | Select panel only on Modify (:108) | Add Select to every tab |
| Architecture | Build (with Curtain Grid and Mullion inside it), Circulation (Railing, **Ramp, Stair**), Model (Model Text, Model Line, Model Group), Room & Area, Opening, Datum, Work Plane (Set, Show, Ref Plane, Viewer) | Separate "Curtain Wall" panel; Opening comes before Circulation; Stair before Ramp; Work Plane has only Reference Plane (:111-122) | Merge Curtain Wall into Build, reorder, finish Model and Work Plane |
| Structure | Structure (+Truss, Brace, Beam System), Foundation, **Reinforcement**, Model, Opening, Datum, Work Plane (:117) | Structure, Foundation, Datum, Work Plane (:124-128) | Add the missing panels |
| Insert | Manage, Link (10 items), Import (5), Load from Library (Load Autodesk Family, Load Family, Load as Group, Insert from File) (:141) | Link, Import, Load from Library (:129-132) | Add a Manage panel and the missing items |
| View | Graphics, **Presentation**, Create, Sheet Composition (Title Block, Guide Grid, Matchline, View Reference), Windows (Switch, Close Inactive, Tab, Tile, User Interface, Canvas Theme) (:238) | No Presentation panel; Windows has Previous View and Zoom to Fit (:160-171) | Align with RevitCraft |
| Manage | Settings, **Project Location**, Design Options (+Add to Set, Pick to Edit, option combo), Manage Project (Links, Decal Types, Starting View), Phasing, **Selection**, Inquiry (:299) | Settings, Phasing, Design Options, Manage Project, Inquiry, Output (:172-179) | Reorder and add the missing panels |
| Modify | …Modify, **View, Measure**, Create (:322) | …Modify, **Measure, View**, Create (`Ribbon.swift:99-100`) | Swap Measure and View |

**Command and term renames** (all in `Application/Commands.swift` unless noted):

| Arcus term (line) | RevitCraft / Revit term |
|---|---|
| "Tag All Not Tagged" (:181) | Tag All |
| "Room Tag" (:182), "Area Tag" (:458) | Tag Room, Tag Area |
| "Allow / Disallow Wall Joins" (:116-117) | Allow/Disallow Join (Geometry panel toggle) |
| "Hide / Isolate Element (Temporary)" (:213-214) | Hide Element, Isolate Element |
| "Place View on Sheet" (:201) | Place View |
| "Close Inactive Views" (:230) | Close Inactive (ribbon caption) |
| "Finish Group" (:121) | Finish |
| "Column" (:141) | Column: Architectural. Structural Column becomes the split's default |
| "Shaft Opening" (:341) | Shaft |
| "PDF Underlay…" (:282), "Image…" (:283) | Link PDF, Link Image |
| "Component Library…" (:443) | Load Autodesk Family |
| "Location & Coordinates" (:261) | Location, plus a Coordinates and Position split |
| "Convert to Arcus Lines…" (:279) | Remove the "Arcus" branding (for example Explode) |
| "Wall – Arc / Rectangle / Pick Lines / Curtain Wall", "Floor/Roof – Pick Walls", "Stair – Straight/L/U" | Revit has only Wall: Architectural / Structural / by Face / Sweep / Reveal and Stair. The shapes move to the Draw panel |
| Menu-bar groups "Build" and "Document" (`UI/Shell/MainMenu.swift:17,26`, `CommandGroup` :66-67) | Architecture and View |
| Hub start screen (`UI/Onboarding/HubAndOnboarding.swift`) | Home |
| macOS File menu (`MainMenu.swift:11`) | RevitCraft's File menu (big entries; Export grouped as CAD Formats, PDF, IFC, DWF, Family Types, gbXML, Images and Animations, Reports). Can live inside the ribbon or a File tab |

"Project Browser" is already correct everywhere users see it (`UI/Navigator/NavigatorView.swift:17`, `Commands.swift:321`); grep `Project Navigator`=0. Only internal names (`toggleNavigator`, `.navigator`) and the accessibility labels "Sidebar" and "Inspector" (`UI/Shell/FloatingDock.swift:92`) still use the old naming.

## 2. Interaction behaviour

| Area | RevitCraft (rc-app) | Arcus | Gap |
|---|---|---|---|
| Snap kinds | Endpoint, Midpoint, Center, Intersection, Perpendicular, Tangent, Quadrant, Nearest, Alignment, Extension, Angle (`snap.rs` `SnapKind::label`, `snap()` :231) | The same, plus Grid Intersection, Middle of Two Points and Parallel (`Application/Snapping.swift:6-20`) | Arcus has more. Keep them |
| Snap tooltip | Drawn immediately at pointer +(8,12) in a flat grey box (`style.rs` `canvas_tooltip` :270). Text: "Horizontal", "Vertical", "Horizontal and Extension", "Vertical and Extension", or the kind name (`canvas.rs` `paint_snap` :968, `axis_label` :953) | Builds the same strings (`SnapEngine.swift` :97-102, 139), but shows them only after a rest delay and filtered by Tooltip Assistance (`Canvas2DView.swift` `pointerMovedForTooltip`, `Canvas2DView+Feedback.swift` :145) | Show the snap label at once, with no delay |
| Tracking lines | Light-blue (120,170,230) dash-dot lines. Horizontal/vertical tracking runs across the whole view (`canvas.rs` `track_line`, `paint_snap`) | Selection blue at 70% alpha, dash 6/4, segments from the anchor only (`Canvas2DView.swift` `drawGuides` :603) | Change colour, dash and span |
| Snap glyphs | Hollow double-line H/V arrow; an X marker for alignment/extension (`paint_snap`) | Single-line double arrow; no marker for extension (`Canvas2DView.swift` `drawSnap` :615) | Restyle |
| Angle increment | Adapts to rubber-band length: 45/15/5/1° (`snap.rs` `angle_increment` :182) | Fixed setting, 15° by default (`SnapEngine.swift:90`) | Make it adaptive |
| Cursors | Grey crosshair with a centre gap while drawing and dragging ends; arrow plus move glyph in Move/Copy; four-way move arrow over a selected element (`canvas.rs` `paint_cursor` :895, `paint_crosshair`) | Full-length system crosshair, openHand on grips, pointingHand on controls, dragCopy for Copy (`Canvas2DView.swift` `updateCursor` :1082) | Replace with RevitCraft's cursors |
| Selection highlight | SELECT (24,84,216), preselect (20,50,150). Selected cut walls get an even fill that reads as (125,146,202) between openings; outlines get heavier, pattern lines stay thin (`canvas.rs` `SELECT_FILL` :429, `paint_selected_wall_fills` :433). 3D uses the same translucent tint plus thick edges (`render3d.rs:84`) | 0x0050D0 / 0x4F95F2 (`UI/Shell/CanvasSettings.swift:21-22`). The shader recolours whole items with the highlight colour (`UI/CanvasMetal/CanvasShaders.swift:155,593`); 3D mixes at 72% (`UI/Canvas3D/Shaders.swift:233`) | Use the RevitCraft palette and the wall-fill rule |
| Window / crossing | Thin dark-grey (40) rectangle with no fill; dashed when crossing (`canvas.rs` :1689; `window_select` :1876) | 8% blue fill and a blue stroke (`Canvas2DView.swift` `drawSelectionRect`) | Remove the fill, use grey |
| Grips | White circles with a blue stroke (light-blue on hover); thin double-arrow flip control. Grid ends: hollow means 3D extents, filled means 2D, plus a 3D/2D label, Add Elbow, alignment lock and bubble checkbox. Section depth triangle and flip (`grips.rs` `paint` :254, `GripKind`) | Selection-tinted filled circles (`Canvas2DView.swift` ~:595). Grids get only start/end and bubble grips (`GripService.swift:44`). `GridData` has no 2D extents or elbow (`Domain/Model/ModelElements.swift:29`); grep `addElbow|gridElbow`=0. No section depth grip | Missing: grid 2D/3D extents, elbow, lock, section depth. Restyle the grips |
| Drag feedback | A wall-end drag leaves the wall in place and shows its new location as a thick orange dashed line, snapping Horizontal/Vertical from the fixed end. Move shows a dashed box, a thin blue rubber band, length and angle, and dashed angle arcs (`grips.rs` `preview` :428) | Live model preview plus a heavy blue line (`SelectTool.swift:50-62`); Move shows ghost outlines, a line and a temporary dimension (`ModifyTools.swift` `MoveCopyTool` :42-49) | Switch to RevitCraft's style |
| Temporary dimensions | Light-blue witness lines, blue text along the line, make-permanent glyph, hosted-opening dims (`canvas.rs` `temp_dim_ex`, `tempdims.rs` `compute` :172). Selecting an element lets you edit its **permanent** dimensions in place (`tempdims.rs` `permanent_dims` :247, `editor` :287) | Rich temporary dims and make-permanent (`SelectionDimensions.swift`, `SelectTool.makePermanent` :232). Editing permanent dims in place is **missing** (grep `permanent` finds only make-permanent) | Add in-place editing of permanent dims |
| Tab | Cycles hover candidates (`canvas.rs` :1572); Tab in Pick Walls picks the chain (`canvas_tools.rs:1545`) | Cycles candidates, then the joined-wall chain (`SelectionModel.swift:18-22`), and also cycles snaps while drawing (`SnapCycling.swift`) | Arcus has more. Keep it |
| Align / Offset | Align: Multiple Alignment, Lock, Prefer in the ribbon. Offset: Graphical or Numerical | AlignTool has Lock only (`ModifyTools.swift:470-473`); grep `Multiple Alignment`=0. Offset has Distance and Copy only (`ModifyTools.swift:510`) | Add Multiple and Prefer to Align; add Graphical to Offset |
| Shortcuts | `commands.rs` `Cmd::info` | Aliases in `Commands.swift` | Arcus lacks SB, BR, BS, FT, RB, RR, SU, JG, PT, EG, UG, TW, WT. **SA** differs: RevitCraft uses Visible in View, Arcus uses In Project (:95) |

## 3. Feature gaps (RevitCraft has them; Arcus is Missing or Partial)

| Tab | Feature | Status | grep evidence (Arcus) |
|---|---|---|---|
| Architecture | Model Text | Missing | `modelText\|Model Text`=0 |
| | Wall: Reveal | Missing | `wallReveal\|Wall: Reveal`=0 (Wall: Sweep exists) |
| | Wall by Face, Curtain System, Roof/Floor by Face | Missing | `byFace`=0, `curtainSystem`=0 |
| | Stacked walls | Missing | `stackedWall\|Stacked Wall`=0 |
| | Model In-Place | Missing | `Model In-?Place`=0 |
| | Place Model Group | Missing | `placeGroup`=0 |
| | Openings: By Face, Vertical, Dormer | Missing | `faceOpening`, `verticalOpening`, `Dormer` each =0 |
| | Grid Multi-Segment | Missing | `multiSegment`=0 |
| | Work Plane Set / Show / Viewer | Partial | 3D level picker only (`WorkPlaneOption3D.swift`); `workPlaneShow\|workPlaneViewer`=0 |
| | Spline, Ellipse, Partial Ellipse draw modes | Missing | `ellipse\|spline` in Tools=0 |
| | Multistory stairs (Connect Levels) | Missing | `connectLevels\|Multistory`=0 |
| | Roof tools: Align Eaves, Adjust Height/Overhang; roof slope arrow | Missing / Partial | `Align Eaves`=0; slope arrow only on slabs (`SketchTool.swift:42,58`) |
| | Highlight Boundaries | Missing | =0 |
| | Slanted columns; At Grids / At Columns | Missing | `slantedColumn`=0 (only an exchange fallback), `atGrid`=0 |
| Structure | Truss, Brace, Beam System | Missing | `Brace`=0, `beamSystem`=0, Truss only in a floor type name |
| | Rebar, Area, Path, Fabric Area, Fabric Sheet, Cover, Rebar Coupler | Missing | `rebar\|Rebar`=0, `reinforcement`=0, `coupler`=0 |
| | Structural Settings | Missing | =0 |
| Insert | Link Revit (link a project) | Missing | `linkRevit`=0 |
| | Link IFC | Partial | `LinkFormat.ifc` exists (`ModelElements.swift:401`) but there is no command |
| | Link Topography, DWF Markup, Decal (+ Decal Types), Point Cloud, Coordination Model | Missing | each =0 |
| | Import gbXML, Import PDF, Import Image | Missing | each =0 (only the PDF/Image link exists) |
| | Load as Group, Insert Views / 2D Elements from File | Missing | each =0 |
| Annotate | Space Tag, Multi-Rebar | Missing | =0 |
| | Beam, Area, Path, Rebar and Fabric symbols | Missing | `rebar`=0 |
| | Keynote Legend, Keynoting Settings | Missing | =0 |
| Analyze | Spaces & Zones (Space, Space Separator, Tag Space) | Missing | `spaceTag\|SpaceData`=0 |
| Massing & Site | Show Mass, In-Place Mass | Missing | `Mass\b` only "Related to Mass" placeholders |
| | Link Topography | Missing | =0 |
| View | Show / Remove Hidden Lines | Missing | =0 |
| | Cut Profile (view tool) | Missing | `cutProfile` hits only shaft geometry |
| | Render, Cloud Rendering, Render Gallery, Twinmotion (OBJ) | Missing | `Twinmotion`=0, `Render Gallery`=0 |
| | Walkthrough | Missing | =0 (only a Fly mode exists) |
| | Framing Elevation, sketched Callout | Missing | each =0 |
| | Title Block command, Matchline, Duplicate Sheet | Missing | `Matchline` only a keyword; `duplicateSheet`=0 |
| | Guide Grid | Partial | Data and drawing exist (`SheetData.swift:40`); no tool |
| | Switch Windows, Tab/Tile Views, Canvas Theme | Missing | each =0 |
| | Navigation wheels (2D and Full) | Missing | `Rewind\|Navigation Wheel`=0 |
| Manage | Global Parameters | Missing | =0 |
| | Transfer Project Standards | Missing | =0 |
| | Specify / Report Coordinates; Relocate Project; Rotate True/Project North; Mirror Project | Missing | each =0 |
| | Design Options: Add to Set, Pick to Edit, active option combo | Missing | each =0 (dialog only) |
| | Saved selections (Save / Load / Edit) | Missing | =0 |
| | Starting View | Missing | =0 |
| | Save reminder | Missing | `reminder`=0 |
| Modify | Select Joined Elements | Missing | =0 |
| | Edit permanent dims in place; Graphical offset; Multiple Alignment | Missing | see §2 |
| Schedules | Combine Parameters, Freeze Header, Borders/Font, header Insert Above/Below, Insert Image, Clear Cell, Split & Place | Missing | each =0 (`Ribbon+BLSched.swift:19-27` has a reduced tab) |
| File / Export | DWF/DWFx, STL, gbXML, Room/Area Report, Family Types export, Walkthrough frames | Missing | `DWF` only a DXF entity name; `gbXML`=0; `roomReport`=0 |
| | Print Preview, Print Setup; PDF settings (hide ref planes / scope boxes); AIA DWG layers | Missing | each =0 |
| Family Editor | Runs in the main window with Create, Insert, Annotate, View and Manage tabs | Different | Separate window with Create and Modify only (`UI/FamilyEditor/FamilyRibbon.swift:8`) |
| | Back and Left elevations; Default 3D with orbit | Partial | Plan/Front/Right/3D (`FamilyPreview.swift:8`) |
| | Swept Blend; Void Blend / Revolve / Sweep | Missing | `sweptBlend` only in the exchange schema; voids other than extrusion don't cut (FamilyEditor.md) |
| | Control (flip arrows), Reference Line, Model Line, Model Text, Opening | Missing | each =0 in Domain and FamilyEditor |
| | Filled / Masking Region editing | Partial | Evaluated but edited only in files (FamilyEditor.md) |
| | Work Plane Set on named planes | Missing | =0 |
| | Sketch Path, Edit Profile, Go To View for sweeps | Partial | Sweeps are not sketched on the canvas |

## 4. Arcus-only features (keep these)

- **Interop and safety:** Revit Bridge `.arcusx` import and RVT inspection, the DWG converter/SDK route, Import Schedule CSV, the recovery journal, Model Health, Diagnostics.
- **Shell:** Command Search, the BIM Familiar and Mac Spacious workspaces, Tooltip Assistance, temporary dimension settings.
- **Content:** Component Library and Site & Parking Library, Parking Layout, legacy toposurface tools (Split/Merge Surface, Graded Region, Excavate, Simplify, Label Contours).
- **Modelling:** Curtain Panel, Slab Edge, Roof Soffit, Stair L/U, Cut/Uncut Geometry, Switch Join Order, Attach Walls, Measure Along.
- **Views and documentation:** Revision Schedule, Duplicate as Dependent, Structural Plan, Selection Box, Fly navigation and camera tools, 3D orient views, Transparent style, Colour Schemes, Scale Bar, North Arrow, New Title Block and Annotation Symbol, Array Number.
- **Settings dialogs:** Line Weights, Line Patterns, Fill Patterns and Arrowheads.
- **Interaction:** Grid Intersection, Middle of Two Points and Parallel snaps; Tab snap cycling; Tab wall-chain selection; Flex Test.

## 5. Milestones

**Behaviour first**
1. **N1 Names:** ✅ done (2026-10-18). Command titles now use RevitCraft's names (Tag All, Tag Room/Area, Allow/Disallow Join, Hide/Isolate Element, Place View, Column: Architectural, Shaft, Link PDF/Image, Location, Explode, Mirror - Pick/Draw Axis, Select All Instances: Visible in View / In Entire Project, Zoom in Region; the ribbon caption for Finish Group is Finish). The menu bar follows the tabs (Architecture, Structure, Insert, Annotate, Manage; the View menu gains Create and Sheet Composition submenus), and command groups merged Document into View. File ▸ Home reopens the Home window (titled Home), and the docks are labelled by the palettes they hold. Command IDs are unchanged, so saved shortcuts and documents still load. Moved to N2 because they change structure: the Allow/Disallow Join toggle in the Geometry panel, the Location / Coordinates / Position split, and the Column split. Not adopted: "Load Autodesk Family", because Arcus's library is its own content and not Autodesk's.
2. **N2 Ribbon structure:** Select panel on every tab, empty Analyze tab, panel order and splits as in RevitCraft (Wall dropdown, draw modes into the Draw panel), Output panel moved into a File menu.
3. **I1 Canvas look:** cursors, selection colours and the cut-wall fill rule, 3D tint and edges, window rectangle, grip styling.
4. **I2 Snapping feedback:** tooltip shown at once, tracking line colour and full-view span, glyphs, adaptive angle increment.
5. **I3 Editing feedback:** wall-end and Move drag previews, in-place editing of permanent dims, Align Multiple/Prefer, Graphical offset, shortcut fixes (SA and the 13 missing aliases).
6. **I4 Datum grips:** grid 3D/2D extents, Add Elbow, alignment lock, section depth and flip.

**Feature batches**
7. **F1 Architecture A:** Model Text, Wall Reveal, Openings (By Face, Vertical, Dormer), Place Model Group, Spline and Ellipse modes.
8. **F2 Architecture B:** stacked walls, multi-segment grids, Work Plane Set/Show/Viewer, multistory stairs, roof slope arrows and roof tools, slanted columns, At Grids, Highlight Boundaries.
9. **F3 Structure:** Truss, Brace, Beam System, Structural Settings.
10. **F4 Reinforcement:** Rebar, Area, Path, Fabric, Cover and Couplers, with their symbols, tags and Multi-Rebar.
11. **F5 Analyze and Massing:** Spaces and Space Tag, Show Mass and In-Place Mass, Model by Face (wall, floor, roof, curtain system), Model In-Place.
12. **F6 Insert:** Link project, Link IFC, Import PDF/Image/gbXML, Load as Group, Insert Views and 2D Elements, Transfer Project Standards.
13. **F7 Insert extras:** Decal and Decal Types, Point Cloud, Coordination Model, Link Topography, DWF Markup.
14. **F8 View A:** Show/Remove Hidden Lines, Cut Profile, Framing Elevation, sketched Callout, Walkthrough.
15. **F9 View B and sheets:** Title Block, Guide Grid tool, Matchline, Duplicate Sheet, Switch/Tab/Tile Views, Canvas Theme, navigation wheels.
16. **F10 Presentation:** Render dialog, Render Gallery, OBJ/Twinmotion export.
17. **F11 Manage:** Global Parameters, Coordinates and Position tools, Design Option Add to Set/Pick to Edit/combo, saved selections, Starting View, save reminder, Select Joined Elements.
18. **F12 Schedules and keynotes:** the §3 schedule tools, Keynote Legend, Keynoting Settings.
19. **F13 Export and print:** DWFx, STL, gbXML, Room/Area Report, Family Types export, Print Preview and Setup, PDF options, AIA layers.
20. **F14 Family Editor A:** move it into the main window with its five tabs, Back/Left views, Reference Line, Model Line, Control.
21. **F15 Family Editor B:** Swept Blend, void blend/revolve/sweep cutting, Model Text, Opening, region editing, Work Plane Set, sketched sweep path and profile.
