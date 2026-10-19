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
