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
2. **N2 Ribbon structure:** ✅ done (2026-10-18). Every tab starts with a Select panel (Modify keeps its fuller one). There is a new Analyze tab (Color Fill, and Reports & Schedules; Spaces & Zones comes with F5). Panels and their order follow RevitCraft: Curtain Grid and Mullion are in Build; Circulation is Railing, Ramp, Stair; Opening comes after Room & Area. Structure gains Model and Opening, Insert gains Manage, and Manage gains Project Location, with Purge in Settings and Inquiry as small buttons. In View, Plan Views include Area Plan, Schedules come before Scope Box, Sheet Composition has View Reference and a Viewports dropdown, and Windows starts with Close Inactive. In Modify, View comes before Measure (which gains Aligned), Properties has the Properties toggle, Geometry has the Allow/Disallow Join dropdown (the Modify | Walls "Wall Joins" panel is gone), and the Modify grid reads in RevitCraft's rows. The dropdowns hold element variants only: Wall (Structural, Sweep, Curtain Wall), Column (Structural first, then Architectural), Floor (Structural, Slab Edge) and Roof (Extrusion, Soffit). The rectangle, arc and pick shapes are the tools' own draw modes. The Output panel is gone; Export and Print are in the File menu. The QA screenshots scenario now captures every tab (`ribbon-<tab>-<appearance>`).
3. **I1 Canvas look:** ✅ done (2026-10-18). Selection colours are RevitCraft's on light canvases: (24, 84, 216), with preselection (20, 50, 150). Highlighted fills take RevitCraft's blue overlay, `RenderOptions.highlightFill`, which reads as (125, 146, 202) over white; both renderers apply it, with a parity test. Selected outlines get heavier (+1.2 pt, min 2 pt) while hatch lines stay thin. Selected walls cut by a floor plan fill evenly blue between openings. In 3D, selected faces take a flat 80 % tint and thick edges, and preselection shows only on edges. Cursors are RevitCraft's: a small grey crosshair for drawing and dragging ends, the arrow plus a move glyph in Move and Copy, the arrow in the other Modify tools, and a four-way arrow over a selected element. The window/crossing rectangle is plain thin grey, dashed for crossing. Grips are solid blue dots, and controls use the preselection colour when hot. QA captures `wall-selected-zoom`.
4. **I2 Snapping feedback:** ✅ done (2026-10-18). Snap markers are RevitCraft's magenta shapes; Arcus previously didn't draw the hourglass, tangent, H/V double arrow or alignment X. The snap label shows at once beside the snap in RevitCraft's flat grey box: the kind, "Horizontal"/"Vertical", or "Horizontal and Extension"; other angles have no label. Tracking lines are light-blue dash-dot, and axis tracking runs across the whole view. The angle increment is adaptive by default (45°/15°/5°/1° by rubber-band length on screen); Snaps still offers fixed increments.
5. **I3 Editing feedback:** ✅ done (2026-10-18). Wall-end drags leave the wall in place and show its new location line as RevitCraft's thick orange dashes, with a tracking line beyond the pointer. Move/Copy show a dashed box around what moves, a thin blue rubber band, and the length plus a dashed angle arc. Temporary dimensions use light-blue lines with 45° ticks and blue values, and the angle arc uses a grey reference line and a dashed arc. With an element selected, the segments of permanent dimensions to it edit in place (locked, EQ, baseline and ordinate strings are left alone). Align has Multiple Alignment and Prefer (wall centerlines, faces, core centre, core faces). Offset has Graphical (two picks) and Numerical. Shortcuts: SA is Select All Instances: Visible in View; SB, FT, PT, EG, UG and JG are added. BR, BS, RB, RR, SU, TW and WT arrive with their commands (F3, F4, F10, F11, F9).
6. **I4 Datum grips:** ✅ done (2026-10-18). Grids get per-view 2D extents (`GridData.viewExtents`): end grips are hollow for 3D and filled for 2D, with a 3D/2D switch beside each end. Add Elbow jogs the bubble aside, and the elbow's grip drags it across the grid. A padlock appears where ends align, and locked ends move together. Sections in plan get end grips, a far-clip triangle and a flip control that keeps the line in place. Grid bubbles hang beyond the grid's end, as in RevitCraft, so the end grip and its controls stay clear of the number. New fields are optional, so older files open unchanged. QA captures `grid-selected-zoom`.

**Feature batches**
7. **F1 Architecture A:** ✅ done (2026-10-18, port/F1). Model Text (CoreText outlines, extruded in 3D, IFC proxy). Wall: Reveal (grooves cut into straight basic walls; plan cut doesn't show the notch yet). By Face, Vertical and Dormer openings, which cut only their host. Place Model Group. Spline, Ellipse and Partial Ellipse draw modes for lines and sketches; they can't be trimmed, split or offset yet. Highlight Boundaries. Panel order matches RevitCraft.
8. **F2 Architecture B:** ✅ done (2026-10-18, port/F2). Stacked walls (stack edited in Type Properties; Wall: Stacked adds a starter type), Grid Multi-Segment, Work Plane Set/Show/Viewer, Connect Levels (multistory stairs with railings), roof slope arrows, Align Eaves, Adjust Height and Adjust Overhang, Vertical/Slanted Column, At Grids and At Columns. Limits: drawing tools only follow level work planes; the Viewer is a flat drawing, not a live 3D view; bent grids have no 2D extents or elbows; fascia ignores eave heights.
9. **F3 Structure:** ✅ done (2026-10-18, branch port/F34). Truss (a flat Warren truss of framing members), Brace (BR, from the level up to the next), Beam System (BS: sketch a bay, beams at a spacing, rebuilt when the system changes), and Structural Settings (symbolic cutbacks shorten beams in plan; load cases and combinations). Brace plan symbol settings are stored but not drawn, as in RevitCraft.
10. **F4 Reinforcement:** ✅ done (2026-10-18, branch port/F34). Rebar (RB), Area, Path, Fabric Area, Fabric Sheet, Cover and Rebar Coupler, hosted in floors and foundation slabs (in plan) and in walls (from a facing section or elevation). They draw in plan, cut in sections and show as steel in 3D, with Properties and schedules (Quantity, Total Bar Length). Beam, Area, Path, Rebar and Fabric symbols; Aligned and Linear Multi-Rebar annotation; IFC export as IfcReinforcingBar and IfcReinforcingMesh. Limits: wall-hosted reinforcement has no Edit Boundary, and Move/Rotate on it isn't face-aware; cross-project paste skips reinforcement.
11. **F5 Analyze and Massing:** ✅ done (2026-10-18, port/F5). Space, Space Separator and Space Tag (in schedules, gbXML, reports, IFC and DXF), Show Mass, In-Place Mass (extrusion and blend), Model by Face (curtain system, roof, wall, floor) and Model In-place. Limits: elements made by face don't update when the mass changes; curtain systems are refused on tapered faces; masses don't export to IFC; there's no revolve mass.
12. **F6 Insert:** ✅ done (2026-10-18, port/F67). Link Model (another Arcus project, read-only, origin to origin, re-read on open; Arcus doesn't read .rvt). Link IFC, Import gbXML (real rooms), Import PDF and Import Image, Load as Group, Insert Views and Insert 2D Elements from File, and Transfer Project Standards (Manage ▸ Settings).
13. **F7 Insert extras:** ✅ done (2026-10-18, port/F67). Link Topography, DWF Markup (DWFx pages onto sheets), Point Cloud (ASCII XYZ/PTS/CSV/PLY; binary PLY refused), Coordination Model (OBJ, 3D only), and Decal with Decal Types. Decals are partial: placed in plan, section and elevation but not by clicking in 3D, and in Realistic view the image shows as a colour grid rather than a texture. Luminance and bump are stored but not rendered.
14. **F8 View A:** ✅ done (2026-10-18, port/F810). Show/Remove Hidden Lines, Cut Profile (a hole entirely inside a wall doesn't show yet), Framing Elevation, sketched Callout (views clip to the shape everywhere), and Walkthrough (frames, playback, PNG or H.264 .mov export).
15. **F9 View B and sheets:** ✅ done (2026-10-18, port/F810). Title Block, Guide Grid (viewports snap to it), Matchline (shown in every plan, as RevitCraft), Duplicate Sheet, Switch Windows, Tab Views (TW) and Tile Views (WT), Canvas Theme (Black applies to 2D only), and 2D and Full navigation wheels.
16. **F10 Presentation:** ✅ done (2026-10-18, port/F810). Render (RR: offscreen Metal Realistic render at screen or print resolution; save to the project or export PNG), Render Gallery (can't place images in drafting views yet), and Export OBJ. Cloud Rendering and third-party app hand-off are omitted: Arcus is offline and names no other products.
17. **F11 Manage:** ✅ done (2026-10-18, port/F11). Global Parameters (with formulas and associations), Coordinates and Position (Specify/Report, Relocate, Rotate True/Project North, Mirror Project), Design Options Add to Set / Pick to Edit and the active option combo, Starting View, saved selections, Select Joined Elements, and a save reminder.
18. **F12 Schedules and keynotes:** ✅ done (2026-10-18, port/F11). Combine Parameters, header rows, Insert Image, Clear Cell, Freeze Header, Shading, Borders, Font, Reset, Align and Split & Place; Keynote Legend and Keynoting Settings. Partial: Freeze Header keeps only the column headings in view; inserted images don't draw on the sheet canvas (PDF and DWFx have them); the font family shows on screen only.
19. **F13 Export and print:** ✅ done (2026-10-18, port/F11). DWF/DWFx, STL, gbXML, Room/Area Report, Family Types, Print Setup, Print Preview, PDF options and AIA DXF layer names. File ▸ Export is grouped as in RevitCraft.
20. **F14 Family Editor A:** ✅ done, with one partial (2026-10-18, port/F1415). The editor stays a separate window rather than moving into the main window, but has RevitCraft's six tabs in Arcus's ribbon style, view tabs, browser and Properties. Plan, Front, Back, Left, Right and Default 3D with orbit; Reference Line, Model Line and Control flip arrows (placed components flip with them). Update (FM2, port/FES, 2026-10-19): the Family Editor now uses the main window's shell: glass ribbon with visible tabs, docks, Options Bar, view tabs and bottom pill. Its minimum size is 1200 × 700.
21. **F15 Family Editor B:** ✅ done (2026-10-18, port/F1415). Swept Blend; void blend, revolve and sweep that cut (mesh Boolean); Model Text and Opening in families; region editing; Work Plane Set/Show; Sketch Path, Edit Profile and Go To View; Family Types Cancel; Load into Project and Close. Gaps: arcs and circles aren't drawn in sketch mode, and revolve and sweep profiles don't keep plane locks.
22. **Snapping everywhere** (owner's request, 2026-10-19). In 2D views and on sheets, the sketch or path in progress snaps like drawn lines, and so do the halftone underlay, title blocks, point clouds, links and imports; annotation doesn't snap, as in Revit (✅). The Family Editor's plan and elevation views snap like project views, using the same engine, markers, Tab cycling and typed overrides, and keep plane locking; its 3D view has no picking (✅, port/SFE). 3D views snap to model geometry (✅, port/S3D): corners, edge midpoints, centres of curved edges, real 3D intersections and edges piercing the work plane, perpendicular, nearest on an edge, and faces for face-hosted tools. Only visible geometry snaps (glass and masses don't hide). Tab cycles, and linked models, imports and point clouds are included; it takes about 6 ms per query on the 20,000-element model. Follow-up (✅, port/S3D2): 3D views draw and snap grids, levels, reference planes, model lines and 2D CAD links and imports, following Visibility/Graphics. As in Revit, reference planes stay hidden in 3D views until Visibility/Graphics turns them on, and drawing one there says it isn't visible; quadrant, tangent and apparent-intersection snaps work in 3D. Model lines, model text, reference planes and components draw on any work plane (reference plane, named plane or picked face) and keep it as their sketch plane; walls and floors stay level-based, as in Revit. Remaining gaps: datums have no heads or names in 3D; scope boxes don't clip them there; elements on a non-level plane have no grips, trim or split; open elliptical arcs and splines get no centre or quadrants; apparent intersection has no separate switch.
23. **Stairs rebuilt like Revit** (owner's request, 2026-10-19, port/STAIR): Modify | Create Stair with run, landing and support tools (straight, spirals, L/U winders, sketch), the riser readout, automatic landings, Edit Stairs grips, Revit's properties, calculation rules and Assembled / Cast-In-Place / Precast types, plan cut marks with UP/DN, assembled and monolithic sections and 3D, continuous railings with extensions, multistory stairs, Shaft ▸ Pick Stair, Stair Tag, IFC flights and landings. Audit, details and what remains: Docs/Stairs.md.
