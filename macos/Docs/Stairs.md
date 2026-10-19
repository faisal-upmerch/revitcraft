# Stairs

Owner's request, 2026-10-19: "your staircase system is totally broken, need huge improvement and need to match with
Revit". This document is the audit of the stairs before the STAIR batch (§1), the Revit-style design that replaces them
(§2), and what is done (§3).

## 1. Audit (before STAIR)

Built with the old tools (Stair – Straight / L-Shaped / U-Shaped, two clicks, hosted railings on both sides, Connect
Levels) and rendered offscreen: plans of Level 1 and Level 2, a section along a flight, a section across the flights, 3D
from two sides (`STAIRUITests.auditRenders`, `STAIR3DRenderTests.auditRenders`, PNGs in `/tmp/arcus-stair/audit-*`).
RevitCraft's Rust reference (`crates/rc-core/src/build3d.rs` `stair_layout`, `run_landing`, `stair_storeys`;
`plan.rs` `stairs_graphics`) was read for behaviour already worked out there: runs as centre lines with widths,
riser counts shared between runs, automatic landings one run width deep at a turn, single-zigzag cut mark, UP on the
base level and DN on the top level, multistory storeys.

### Creation and editing

| # | Wrong or missing vs Revit |
|---|---|
| A1 | No Create Stair sketch mode. Revit's single Stair tool (Architecture ▸ Circulation) opens "Modify \| Create Stair" with Components (Run, Landing, Support), Finish/Cancel Edit Mode. Arcus had three fixed shapes placed by two clicks. |
| A2 | No run tools: no Straight run drawn start→end, no Full-Step or Center-Ends Spiral, no L- or U-Shape Winder, no sketched run (Boundary, Riser, Stair Path). |
| A3 | No riser count readout while drawing ("8 RISERS CREATED, 10 REMAINING"); the run length was not snapped to whole treads; flights were split in half automatically. |
| A4 | No Options Bar of Revit: Location Line (Exterior Support Left, Run: Left/Center/Right, Exterior Support Right), Offset, Actual Run Width, Automatic Landing. |
| A5 | Landings were fixed (a square for L, a full-width slab with a 100 mm gap for U); no Pick Two Runs, no sketched landing, no landing editing. |
| A6 | No supports (Pick Edges) and no stringers/carriages at all. |
| A7 | Edit Stair only dragged four handles of the old shape; runs and landings were not components with their own grips (run ends, width arrows). |
| A8 | Flip (reverse the up direction) missing. |

### Properties and types

| # | Wrong or missing vs Revit |
|---|---|
| P1 | Instance: no Actual Tread Depth (it was the type's minimum, not editable), no Begin with Riser / End with Riser, no Up/Down text and label/arrow switches. "Shape" and "Turns Left" are not Revit properties. |
| P2 | Type: only Maximum Riser Height, Minimum Tread Depth, Tread Thickness, Structural Depth, Material. Missing Calculation Rules (2R+T target/min/max), Minimum Run Width, Run Type, Landing Type, Right/Left/Middle Support (Stringer (Closed) / Carriage (Open), type, lateral offset), Function, Cut Mark Type. |
| P3 | No stair families: Assembled Stair, Cast-In-Place Stair, Precast Stair; no run types (Monolithic, tread/riser thickness, nosing length and profile, Apply Nosing Profile, Riser to Tread Connection, Structural Depth), landing types or support types. The template's "Monolithic - 175 max riser" type was in the Assembled Stair family. |
| P4 | Warnings: the 2R+T check used a fixed 550–700 mm band instead of the type's rule; no warning for tread depth below the minimum, run width below the minimum, or too few risers to reach the top. |

### Plan display (CD set)

| # | Wrong or missing vs Revit |
|---|---|
| D1 | Cut mark was one short zigzag segment, not the cut line across the run at the view's cut plane drawn by the type's Cut Mark Type (double zigzag by default). Treads were not clipped at it. |
| D2 | Treads above the cut were dropped (shown dashed only at Fine); landings and outlines above the cut stayed solid. |
| D3 | The walk line ran end to end with "UP" on every level; the upper plan labelled the arriving stair "UP" instead of "DN" (port/HOUSE e01e5b7 had a quick fix). No start symbol, no arrow stopping at the cut mark. |
| D4 | On the upper level the stair showed with its own riser lines but no notion of "seen from above": no DN arrow from the top, and a multistory stair drew both storeys' treads over each other with a cut mark. |
| D5 | No stringer/support lines, no nosing lines; railings drew as two lines on the stair edge (over the outline), never dashed above the cut. |
| D6 | U-stair rails cut diagonally across the landing (plan and 3D); L-stair rails cut the landing corner. |

### Section, elevation, 3D

| # | Wrong or missing vs Revit |
|---|---|
| S1 | One monolithic profile for every type: no assembled treads and risers, no nosings, no stringers or carriages. |
| S2 | Sections through a stair showed no cut poché (the merged mesh did not section into closed loops). |
| S3 | Landings were plain slabs of the "Structural Depth"; no landing type thickness. |

### Railings

| # | Wrong or missing vs Revit |
|---|---|
| R1 | Diagonals over landings (D6); no continuous path around the landing edge. |
| R2 | No handrail extensions at the top and bottom; the rail started and stopped at the first and last nosing. |
| R3 | Balusters at a fixed spacing along the slope, not per tread. |
| R4 | No "Place on: Treads / Stringer" position; rails sat on the very edge of the run. No Railing settings in Create Stair. |
| R5 | No Edit Path for a stair's railing. |

### Multistory, openings, annotation, exchange

| # | Wrong or missing vs Revit |
|---|---|
| M1 | Connect Levels repeated the stair on every level up to the top, also where the storey height differs; Revit repeats identical storeys as one group and gives a different height its own riser layout. A stair with a Desired Number of Risers kept that count on every storey. |
| M2 | The Shaft tool had no way to take the stair outline (only endpoint snaps on drawn lines; nothing for the run/landing outline as one loop). |
| M3 | No Stair Tag; Tread Number and Stair Path annotations assumed straight runs. |
| M4 | IFC: one IfcStair body; no IfcStairFlight per run, no IfcSlab (LANDING) per landing. |
| M5 | Ribbon: a "Stair – Straight" split button with three shapes instead of one Stair button entering Create Stair. |

## 2. Design (Revit-style Stair by Component)

### Model
- `StairData` keeps its old fields and gains optional ones (older files decode unchanged): `runs` (`StairRun`: shape
  Straight / Spiral / L-Shape Winder / U-Shape Winder / Sketch, start on the centre line, direction, risers, width,
  spiral centre and turn, winder leg treads and winders per corner, sketched Boundary/Riser/Stair Path lines, the
  Location Line it was drawn with), `landings` (nil = automatic between every two runs; `StairLanding` joins run *k*
  to *k*+1 automatically or by a sketched boundary), `supports` (Pick Edges), `treadDepth` (Actual Tread Depth),
  Begin/End with Riser, Up/Down Text and label/arrow switches, Show Up Arrow in All Views, Tread/Riser Start Number.
- A stair without runs reads as the runs and landings its old shape describes (`StairComponents.legacy`: the same
  flights, the L's square landing, the U's 100 mm well); Edit Stairs turns it into a component stair on Finish.
- Railings on stairs: `RailingData.stairPosition` (Treads / Stringer), `offsetFromPath`, `editedHostPath` (Edit Path).
- Types: stair types (families Assembled Stair, Cast-In-Place Stair, Precast Stair) with Calculation Rules (Maximum
  Riser Height, Minimum Tread Depth, Minimum Run Width, Use Stair Calculator 2R + T target/min/max), Run Type, Landing
  Type, Right/Left Support (None / Stringer (Closed) / Carriage (Open)) with type and Lateral Offset, Middle Support
  (type, number), Function, Cut Mark Type (Double Zigzag / Single Zigzag / Straight Line). Run types (categories
  `stairRuns`; families Monolithic Run, Non-Monolithic Run): Structural Depth, Monolithic Material, Tread, Tread
  Thickness, Nosing Length, Nosing Profile, Apply Nosing Profile, Riser, Riser Thickness, Riser Type, Riser to Tread
  Connection, visible materials. Landing types (`stairLandings`): Thickness, tread finish. Support types
  (`stairSupports`): Width, Structural Depth on Run / on Landing, Top Offset, Material. Older stair types without a Run
  Type read as one monolithic run and landing of their Structural Depth, as they drew before.

### Geometry (`Domain/Regeneration/Stair*.swift`)
- `StairRunGeometry`: tread cells in walking order per run shape (straight, spiral sectors on the centre arc,
  single-point winders radiating from the inner corner, sketched risers trimmed to the boundaries).
- `StairGeometry.layout`: heights (Actual Riser Height = height ÷ Desired Number of Risers; runs keep the risers they
  were drawn with, as in Revit), treads and riser lines with numbers, run boundaries with the nosing-line height,
  automatic landings (one run width deep beyond a turn), supports, and the calculation-rule warnings (riser above the
  maximum, tread below the minimum, 2R + T outside the range, run narrower than the minimum, risers missing or too many).
- `sidePath`: one side of the stair as a continuous path up the runs and round the landing edges (never across a
  landing); used by railings and closed stringers.
- `StairMeshes`: monolithic runs (stepped profile with a sloped soffit; stepped under winders and spirals), assembled
  treads with nosings and risers, landings, stringers and carriages; each piece a closed solid (`StairPiece` for IFC).
- `StairRailings`: base line on treads or stringer, landing-to-run eases, top rail extensions (plus tread depth at the
  bottom; Floor / Wall / Post / None), balusters per tread, posts at ends and landing corners, optional handrail.
- Multistory: every storey repeats the stair; a storey of another height gets its own riser layout.

### Plan (`Domain/Views/PlanGraphics+STAIR.swift`)
- Base plan: below the cut plane solid; the cut mark where the nosing line reaches the cut plane, slanted 30° off the
  risers, double zigzag by default; beyond it the `<Above>` subcategories (dashed). Runs after the cut, landings above
  it and the rest of a winder or spiral (by walk distance) draw as above. Stair path: start circle at the first riser,
  through the landings, arrowhead at the cut mark, Up Text by the start.
- Arrival plan: the stair below in full, path from the top to the arrow at the bottom, Down Text by the top. Where a
  stair (or a multistory storey) rises from this plan over it, only the part beyond the rising stair's cut mark shows.
- Supports as their two face lines; nosing lines offset by the Nosing Length; railings split at the cut mark like the
  stair, balusters at Fine. Subcategories in Visibility/Graphics: Outlines, Nosing Lines, Cut Marks, Stair Path,
  Supports and their `<Above>` versions; railings: Top Rails, Balusters and `<Above>` versions.
- A Stair Path annotation placed in the view replaces the automatic path; Tread Number numbers every tread of every
  run shape from the Tread/Riser Start Number.

### Tools and commands
- Architecture ▸ Circulation ▸ **Stair** (`.stair`) opens **Modify | Create Stair**: Components (Run, Landing,
  Support), Draw (Straight, Full-Step Spiral, Center-Ends Spiral, L-Shape Winder, U-Shape Winder, Create Sketch /
  Pick Two Runs, Create Sketch / Pick Edges; Boundary, Riser, Stair Path while sketching a run), Tools (Railing, Flip),
  Mode (Finish/Cancel Edit Mode), Multistory Stairs (Connect Levels), Work Plane. Options Bar: Location Line, Offset,
  Actual Run Width, Automatic Landing. The older Stair – Straight / L-Shaped / U-Shaped commands open the same tool.
- Drawing a run: the readout beside it says "*n* RISERS CREATED, *m* REMAINING"; the end snaps to whole treads;
  typed lengths work. The next run's start snaps where it continues straight on, turns left or right (L) or comes
  back beside the run with a 100 mm well clear of the stringers (U); the automatic landing joins them.
- Esc leaves the drawing tool to select the sketch's runs and landings: drag a run's end arrows (risers), side arrows
  (width, from that side) or the run; edit Width and Risers or Delete in the Options Bar.
- Edit Stairs (double-click a stair, or Modify | Stairs ▸ Edit Stairs) opens the same mode on the stair.
- Railing (Tools): railing type or None, Position Treads / Stringer. A selected stair railing has Edit Path and
  Reset Railing. Shaft ▸ Pick Stair adds a stair's outline to the shaft sketch (Revit doesn't cut floors for stairs).

### Exchange
- IFC: IfcStair (shape type from the runs) aggregating an IfcStairFlight per run (risers, treads, riser height, tread
  length; IFC4 STRAIGHT / SPIRAL / WINDER / FREEFORM) and an IfcSlab LANDING per landing; supports in the IfcStair body.
- DXF: stairs A-FLOR-STRS, railings A-FLOR-HRAL (unchanged).
- Stair Tag ("23 R @ 174 mm" over "22 T @ 280 mm", from the stair's Riser Count and Height and Tread Count and Depth).

## 3. Status (STAIR batch)

| Area | State | Notes |
|---|---|---|
| Create Stair sketch mode, Components, Draw gallery, Options Bar, readout, Finish/Cancel | Done | |
| Straight, Full-Step and Center-Ends spirals, L- and U-Shape winders, sketched runs | Done | Winders single-point, 3 per corner; U winder without a well |
| Automatic landings, Pick Two Runs, sketched landings | Done | |
| Supports: type Left/Right/Middle, Pick Edges | Done | Closed stringers go round landings; carriages under runs only |
| Grips: run ends, width arrows, move; delete from the Options Bar | Done | No Delete key inside the sketch (Options Bar button) |
| Properties and Type Properties as Revit | Done | Begin/End with Riser are stair-wide (Revit has them per run) |
| Calculation rules and warnings | Done | |
| Plan: cut mark, solid/dashed, path, UP/DN, arrival plan, stacked storeys, supports, nosings | Done | |
| Section / elevation / 3D: monolithic, assembled, precast, supports, landings | Done | Monolithic winders/spirals have a stepped underside (Revit's "Stepped") |
| Railings: continuous round landings, extensions, balusters per tread, Treads/Stringer, Edit Path | Done | Transitions are simple slopes (no goosenecks) |
| Multistory (Connect Levels), storeys of another height | Done | Storeys aren't editable one by one |
| Stair Tag, Tread Number, Stair Path, schedules (built-in fields) | Done | |
| IFC IfcStair / IfcStairFlight / IfcSlab LANDING | Done | |
| Shaft ▸ Pick Stair | Done | |
| Convert (component → sketch), Underside of Winder Smooth, per-run Begin/End with Riser, landing supports for carriages | Omitted | Not needed for the owner's drawings; candidates for later |
