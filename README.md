# RevitCraft

> **macOS:** the Mac app lives in [`macos/`](macos/). It is built on the Arcus codebase (Swift, AppKit/SwiftUI, Metal)
> and adopts RevitCraft's Revit behaviour. Build it with `macos/script/build_and_run.sh`. The Rust app in `crates/`
> (Windows) is frozen as the behaviour reference.

A BIM (building information modelling) desktop app in Rust, built with **egui** and **wgpu**.
It runs natively on Windows today and is kept portable to macOS (Metal) and Linux from one codebase.

It follows Revit's publicly documented workflow and interface conventions (ribbon with contextual
"Modify | ..." tabs, Options Bar, Properties palette, Project Browser, View Control Bar, ViewCube,
two-letter shortcuts, sketch mode, temporary dimensions). It is an independent implementation with
its own icons and file formats, and is not affiliated with Autodesk. `.rvt` files are not supported;
exchange models through IFC and drawings through DXF.

## Run

```bash
cargo run --release -p revitcraft
```

The Home screen offers a metric or imperial project, recent files and a sample house. Command-line
options: a `.rcx`, `.ifc`, `.dxf` or `.rcfa` path, `--sample`, `--imperial`, `--view NAME`,
`--tool XX` (a shortcut such as `WA`), `--tile`.

## Features

**Architecture**: walls (basic, stacked and curtain types; location lines; straight, rectangle,
polygon, circle, arc, tangent-arc, fillet and pick-lines modes; chain and offset; height or depth;
top constraints; attach top/base; joins and flip), doors and windows hosted in walls (tag on
placement, flip facing/hand, pick new host), components, architectural columns, roofs by footprint
(per-edge slopes, overhang, pick walls) and by extrusion, automatic and sketched ceilings, floors,
curtain grids, railings, stairs (sketched runs with landings), model lines, model groups, rooms,
room separators, areas and area boundaries, shafts, wall openings, levels, grids and reference planes.

**Structure**: beams, structural walls, columns (grid intersections), structural floors, isolated
and wall foundations.

**Drafting UX**: object snaps (endpoint, midpoint, intersection, centre, quadrant, perpendicular,
tangent, nearest), alignment and extension tracking lines, angle and length increments that adapt to
zoom, Shift for orthogonal, typed lengths ("listening dimensions"), snap overrides (`SE`, `SM`,
`SI`, `SC`, `SP`, `ST`, `SQ`, `SN`, `SO`, `SZ`), editable temporary dimensions, grips and flip
controls, Tab to cycle overlapping elements, window and crossing selection, drag-to-move, selection
filter, Create Similar, Select All Instances.

**Modify**: align, offset, mirror (pick or draw axis), move, copy, rotate, array (linear/radial),
scale, trim/extend (corner, single, multiple), split (with gap), pin/unpin, match type, demolish,
clipboard cut/copy/paste, hide or override in view, temporary hide/isolate, reveal hidden elements.

**Documentation**: aligned, linear, angular, radial, diameter and arc-length dimensions with locks
and EQ; spot elevations; detail lines, filled and masking regions, revision clouds, text, tags and
Tag All, symbols; floor, ceiling and area plans, sections, callouts, elevations, drafting views,
legends, 3D views with all visual styles (wireframe, hidden line, shaded, consistent colours,
realistic), sun shadows and section boxes; schedules and material takeoffs (fields, filters,
sorting/grouping, totals, calculated values, in-place editing); sheets with drag-and-drop viewports
and revisions; view templates, view range, Visibility/Graphics overrides, object styles.

**Families**: a family editor with reference planes, labelled and EQ dimensions driving the
geometry, extrusions, blends, revolves, sweeps and voids whose sketch points lock to planes,
symbolic lines, family types with formulas, and a 3D preview; save as `.rcfa` and load into projects.
A broad starter library (doors, windows, furniture, casework, fixtures, columns, beams, footings).

**Project**: phases and phase filters, design options, model groups (edit in place), project units
(metric and imperial), project information, materials, purge unused, sun settings, keyboard shortcut
customisation, light and dark themes, tiled and tabbed views.

**Exchange**: IFC4 import/export, DXF (R12) export of views and sheets and DXF import as a linked
underlay, PDF export of sheets and views, PNG image export, schedule CSV export.

## Layout

- `crates/rc-core`: the model, geometry, joins, roofs (weighted straight skeleton), CSG, sections and
  hidden-line elevations, parametric families, parameters and formulas, schedules, sheets, IFC, DXF,
  PDF and PNG. No UI code; `cargo test -p rc-core`.
- `crates/rc-app`: the egui/wgpu desktop app (ribbon, canvas, snapping, tools, renderer, dialogs,
  family editor); `cargo test -p revitcraft` covers snapping, draw modes and shortcuts.

## Building on macOS

1. Install Rust with rustup.
2. Run `cargo build --release -p revitcraft`. wgpu uses Metal automatically and native dialogs come from `rfd`.

To make a `.app` bundle, use a tool such as `cargo-bundle`.
