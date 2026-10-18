Hand-authored Arcus Exchange fixtures for tests (CC0). They were written by hand from the schema in
Docs/RevitInterop.md; they are not exports of any Autodesk file and contain no Autodesk content.

- `small-project.arcusx` — a project: 2 levels, 2 grids, wall/floor/roof/column types, 4 walls plus a curtain wall
  (mesh fallback), a floor, a hip roof, a door, a window, a room, a column, a table, a parameters-only family instance
  (mesh fallback) and a reference mesh.
- `parametric-door.arcusx` — a family: parametric door with Width/Height, formulas, two types, reference planes,
  extrusions along Z and Y, a void, a visibility-controlled solid, a circle, a tessellated form and a wall opening.

Revit container (.rvt/.rfa) test files are generated in code by `CFBWriter` (synthetic, no Revit content).
