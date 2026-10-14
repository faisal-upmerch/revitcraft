# RevitCraft roadmap: Revit-parity analysis

Scope agreed with the owner (2026-10-14):

- **Disciplines:** Architecture and Structure. No MEP.
- **Units:** metric and imperial. New Project asks which template to use.
- **Interface:** Revit's behaviour and layout, drawn with our own icons and naming.
- **3D:** all visual styles.
- **Formats:** IFC, PDF, DXF export and import, PNG export.
- **Project features:** phases, design options, area plans, groups and arrays. No worksharing.
- **Content:** a broad family library.
- **Platform:** Windows first, macOS later from the same code.
- **Revit files:** `.rvt` is closed and undocumented, so we exchange with Revit through IFC and DXF.

Status key: `[x]` done, `[~]` partial, `[ ]` to do.

## 1. Interface shell

How Revit behaves, and what we build to match:

- `[ ]` **Ribbon.** Tabs Architecture, Structure, Insert, Annotate, Analyze, Massing&Site (omitted), Collaborate (omitted), View, Manage, Modify. A contextual tab "Modify | Walls" (or "Modify | Place Wall") appears when an element is selected or a tool is active, with panels Properties, Clipboard, Geometry, Modify, View, Measure, Create, Mode.
- `[ ]` **Options bar.** Per tool, e.g. walls: Height/Depth, top constraint, Location Line, Chain, Offset, Radius, Join Status.
- `[x]` **Properties palette.** Type selector, instance parameters grouped, Edit Type.
- `[~]` **Project Browser.** Views by type, legends, schedules, sheets, families, groups. Needs groups, legends and a search filter.
- `[ ]` **Docking.** Palettes dock, float and tab. Views open as tabs or tiled windows (egui_dock).
- `[ ]` **View control bar.** Scale, detail level, visual style, sun path, shadows, crop and crop visibility, temporary hide/isolate, reveal hidden elements.
- `[ ]` **Status bar.** Prompt, selection filter (links, underlays, pinned, by face, drag elements), selected count with a Filter dialog.
- `[ ]` **ViewCube** (faces, edges, corners, home, compass) and **navigation bar** (zoom/pan/orbit, zoom-to-fit).
- `[ ]` **Selection.** Tab cycles overlapping elements and selects wall chains; Ctrl adds, Shift removes; left-to-right window selects enclosed elements, right-to-left selects crossing ones.
- `[ ]` **Keyboard shortcuts:** the full Revit default set, editable in a Keyboard Shortcuts dialog.
- `[ ]` **Context menu:** Repeat last, Select All Instances (visible / in project), Hide in view, Override graphics, Find referring views, Zoom.

## 2. Drafting UX

- `[~]` **Snapping.** Endpoints, midpoints, intersections, nearest, angle increments.
  - To add: dashed alignment lines (horizontal/vertical tracking from nearby endpoints and edges), extension lines, perpendicular, tangent, centre, quadrant, work-plane grid, parallel.
  - Also: a snap settings dialog with length and angle increments, and Shift+right-click snap overrides (SE, SM, SI, SC, SP, SN, SO).
- `[~]` **Temporary dimensions.** Shown while drawing and when selected. To add: click the value to type a new one (moves the element), drag witness-line grips to other references, make permanent.
- `[ ]` **Permanent dimensions.** Aligned, linear, angular, radial, diameter and arc length. Includes witness lines, EQ toggle, locks (constraints), dimension styles, and text overrides with prefix/suffix.
- `[ ]` **Modify tools.**
  - Align (AL) with lock; Trim/Extend to corner (TR), single element and multiple elements.
  - Split element (SL) and split with gap; Offset (OF) by graphic or numerical entry.
  - Array (AR), linear and radial, with group-and-associate.
  - Scale for lines; Pin/Unpin (PN/UP); Match Type Properties (MA).
  - Copy/paste aligned to selected levels, same place, or current view; Delete (DE).
- `[ ]` **Walls.**
  - Location line (wall centreline, core centreline, finish face exterior/interior, core face exterior/interior) and flip arrows.
  - Line, rectangle, polygon, circle, arc (start-end-radius, centre-ends, tangent end, fillet), pick lines/faces.
  - Join control (allow/disallow join, join type butt/miter/square), attach top/base to roof or floor.
  - Edit profile, wall openings, wall sweeps/reveals.
- `[ ]` **Work planes and reference planes** in project views.

## 3. Building elements

- `[x]` Walls (straight), doors, windows, floors, roofs (rectangular slopes), rooms, components, grids, levels.
- `[ ]` Curved walls.
- `[ ]` Stacked walls.
- `[ ]` **Curtain walls.** Curtain grids, mullions, panels (glazed/solid/door), and automatic spacing (fixed distance or fixed number).
- `[ ]` **Floors.** Holes, slab edges, sloped by arrow, structural floors.
- `[ ]` **Roofs.** Footprint roofs with per-edge "defines slope" on any polygon (straight-skeleton solver), extrusion roofs, fascia and gutters, cutting the walls below.
- `[ ]` **Ceilings.** Automatic from the room boundary or sketched, plus reflected ceiling plans.
- `[ ]` **Stairs.** By component (straight, L, U, spiral runs and landings), with riser/tread rules and automatic railings.
- `[ ]` **Railings.** Sketched path, balusters, top rail, hosted on stairs and floors.
- `[ ]` **Openings.** Shaft (multi-level), by face, wall opening, dormer.
- `[ ]` **Ramps.**
- `[ ]` **Architectural and structural columns.**
- `[ ]` **Structure.**
  - Beams and framing (by grid, chain), beam systems, braces.
  - Structural walls and floors.
  - Foundations: isolated, wall footing, slab.
  - Column-to-grid placement ("At Grids").
- `[ ]` Model lines, model text.
- `[ ]` Room separation lines, area boundaries.

## 4. Documentation

- `[~]` Floor plans. To add: view range (top, cut, bottom, view depth), underlay, phase filter, crop, and detail levels coarse/medium/fine (walls show their layers at fine).
- `[ ]` Reflected ceiling plans.
- `[~]` **Elevations** (fixed four). To add: elevation markers, new elevations at any angle, crop, far clip, vector hidden-line output.
- `[ ]` **Sections.** Section line, flip, far clip, cut poché, segmented sections.
- `[ ]` **Callouts.** Rectangular, with their own scale.
- `[ ]` **Drafting views** and **detail components:** detail lines, filled and masking regions, insulation, repeating details.
- `[ ]` **Annotation.**
  - Text notes with leaders.
  - Tags by category and Tag All (doors, windows, rooms, walls, areas).
  - Spot elevations and coordinates, keynotes.
  - Symbols: north arrow, section heads, level heads.
- `[ ]` **Legends.** Legend components and colour fill legends.
- `[ ]` **View templates.** Apply or assign scale, detail, visibility/graphics and filters.
- `[ ]` **Visibility/Graphics.** Category visibility (done) plus line and pattern overrides, halftone, transparency, filters.
- `[~]` **Schedules.** To add: material takeoffs, key schedules, conditional formatting, headers and grouping with headers/footers, calculated values.
- `[~]` **Sheets.** To add: title block families, sheet lists, revisions (clouds, schedule), guide grids, view titles with detail numbers.

## 5. Family editor

The Revit model:

- **Reference planes** with labelled dimensions (parameters), EQ constraints and locked sketch lines.
- **Solid and void forms:** extrusion, blend, revolve, sweep, swept blend.
- **Symbolic lines,** visibility per detail level and view direction.
- **Type catalogue,** formulas, nested families, shared parameters.
- **Host** (wall, floor, ceiling, face) and **category.**
- **Flex dialog:** "Family Types", to test that the family behaves.

Our approach:

- `[ ]` A constraint tree solver.
  - Each reference plane is placed by a parameter or fixed offset from another plane.
  - EQ groups split the spans between planes equally.
  - Sketch vertices lock to plane intersections.
- `[ ]` Forms are generated as meshes. Voids are subtracted with BSP CSG.
- `[ ]` The family editor gets its own plan and elevation views, a sketch mode and the Family Types dialog.
- `[ ]` Families save to and load from `.rcfa` files (Load Family).

## 6. Visuals

- `[ ]` **Visual styles:** wireframe, hidden line, shaded, consistent colours, realistic, ray-trace (omitted).
- `[ ]` **Sun and shadows:** shadow mapping, sun settings (date, time, location), ambient shadows.
- `[ ]` **Section box,** with drag handles.
- `[ ]` **Graphic display options:** silhouettes, smooth edges.
- `[ ]` **Cameras:** perspective camera placement from plan.

## 7. Project

- `[ ]` **Units:** metric and imperial formatting and parsing (feet-inches, fractions), Project Units dialog, templates.
- `[ ]` **Phases:** created and demolished phases, phase filters (new, existing, demolished, temporary), phase graphics.
- `[ ]` **Design options:** option sets, primary and secondary options, view visibility per option.
- `[ ]` **Area plans:** gross and rentable schemes, area boundaries, areas and area schedules.
- `[ ]` **Groups:** model and detail groups, edit group, arrays, copy to levels.
- `[ ]` **Location:** project base point and survey point, true north.

## 8. Exchange

- `[x]` IFC4 import and export, PDF, CSV.
- `[ ]` DXF export (plans, sections, sheets) and import as an underlay (Link CAD).
- `[ ]` PNG image export.

## Engineering notes

- **Model.** `rc-core` stays UI-free and tested. Elements stay an enum, extended with new kinds. Every new field gets a serde default so older `.rcx` files keep loading.
- **Geometry.**
  - BSP CSG (csg.js style) for voids and cuts: shafts, roofs cutting walls, family voids.
  - 2D polygon booleans with `geo`.
  - Straight skeleton for hip roofs on any footprint.
- **Plan graphics.**
  - A generic mesh-plane cut gives cut outlines and fills.
  - Feature edges below the cut are projected, with symbolic lines for families.
  - Vector hidden-line output for elevations and sections comes from depth-buffer visibility sampling of feature edges.
