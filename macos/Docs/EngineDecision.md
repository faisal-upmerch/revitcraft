# IFC engine decision

Status: **decided**. Arcus reads and writes IFC with a native Swift STEP reader/writer
(`ArcusIFC`) that covers the architectural subset. There is no third-party IFC or geometry
library in the app.

## What Arcus needs from an IFC engine

- IFC2X3 Coordination View 2.0 and IFC4 Reference View exchange for architectural elements:
  walls, slabs, roofs, coverings, doors, windows, spaces, columns, beams, stairs, railings,
  furniture and generic elements. It also needs spatial structure, types, materials, property
  sets, quantities, classification and GUIDs.
- Import of files from other tools with robust handling of broken and hostile input. Anything
  Arcus cannot convert to a native element has to be kept as reference geometry.
- macOS arm64, Swift 6 strict concurrency, sandboxed App Store–style distribution, and
  reproducible builds with SwiftPM only (no Python, no CMake, no prebuilt blobs that we can't
  rebuild).
- Deterministic output, so golden tests and re-exports are stable.
- A licence that fits a closed-source commercial Mac app shipped as a single bundle.

## Candidates

The licence and project facts below come from the projects' public repositories as we know
them (mid 2026). Entries marked "verify" need checking against the current licence file before
anyone makes a decision that depends on them.

| | IfcOpenShell | web-ifc (That Open Engine) | IFC++ (ifcplusplus) | xBIM Toolkit | GeometryGym IFC | Native Swift (chosen) |
|---|---|---|---|---|---|---|
| Language / runtime | C++ core, OpenCASCADE geometry kernel, Python tooling | C++ core, built mainly for WebAssembly / Node | C++, own geometry code plus a CSG library | .NET (C#); geometry engine in C++/CLI + OpenCASCADE | .NET (C#) | Swift 6, Foundation + simd only |
| Licence | LGPL-3.0 (engine). OpenCASCADE is LGPL-2.1 with an exception. The Bonsai/BlenderBIM tooling is GPL. | MPL-2.0 | Permissive, believed to be MIT for the core, but the bundled CSG dependency's licence has changed over time (**verify** both) | CDDL-1.0 (**verify** per package) | Permissive, believed to be MIT (**verify**) | Our own code |
| Commercial Mac app fit | LGPL means dynamic linking plus relinking rights for users. That is workable but awkward inside a sandboxed, signed bundle. | MPL-2.0 is file-level copyleft and fine, but a native macOS build is a secondary target | Probably fine, once the CSG dependency's licence is confirmed | Needs a .NET runtime inside the app, which is not realistic for a native Swift app | Same .NET runtime problem | No licence constraints |
| Binary size (approx.) | Large: tens of MB for OpenCASCADE plus the IFC schema code for all schemas | Medium: several MB of native code, larger with all schemas | Medium | Large (.NET runtime + OCC) | Medium (.NET runtime) | Small: the ArcusIFC module is a few hundred KB |
| Deterministic, reproducible build | Hard: CMake, OCC, Boost, per-schema code generation | Moderate: Emscripten/CMake toolchain | Moderate: CMake | Hard on macOS | Hard on macOS | Yes: plain SwiftPM, no generated code |
| IFC2x3 / IFC4 | Both, plus IFC4x3, full schemas | Both, plus IFC4x3 (schema code generated) | Both, plus IFC4x3 | Both, plus IFC4x3 | Both, plus IFC4x3 | IFC2X3 CV2.0 and IFC4 RV architectural subset (IFC4x3 files are read with the IFC4 subset) |
| Geometry coverage | Most complete: B-rep, NURBS, booleans, sweeps through OpenCASCADE | Good: extrusions, B-reps, booleans (own CSG), tessellated sets | Good: CSG through the bundled library | Good (OCC) | Limited (mainly authoring) | Extrusions, faceted B-reps, tessellated face sets, surface models, mapped items, CSG blocks. Boolean results use their first operand. No NURBS, sweeps or revolutions. |
| Writing IFC | Yes | Yes (less mature than reading) | Yes | Yes | Yes (a strength) | Yes, deterministic |
| Maintenance | Very active, large community | Active, company-backed | Small team, slower | Active but .NET-focused | Single maintainer, active | Maintained by us, sized to our subset |
| Concurrency / Swift integration | C++ bridging, global state in places | C++ bridging or JS | C++ bridging | Not practical | Not practical | Value types, `Sendable`, runs off the main actor |

## Decision

We use a **native Swift STEP Part 21 reader and writer with an explicit mapping for the
architectural subset**.

Reasons:

1. **Licensing and distribution.** No LGPL relinking obligations inside a signed, sandboxed
   bundle, and no .NET runtime.
2. **Size and build.** SwiftPM builds everything from source with no external toolchain, and
   builds are reproducible.
3. **Determinism.** Arcus controls entity numbering, real formatting and GUID derivation, so
   golden files and re-exports are byte-stable.
4. **Fit.** Arcus already has a geometry kernel (triangulation, meshes, extrusions) and a value
   model. The exporter uses the meshes the viewer shows, so what users see is what they export.
5. **Honesty about scope.** The subset is small and fully tested (59 test functions: goldens for both
   schemas, round trips, units, placement chains, mapped items and hostile input). Anything
   outside the subset is kept as reference geometry and counted in the import report, never
   silently dropped.

## Tradeoffs we accept

- **No general B-rep/CSG kernel.** `IfcBooleanResult` and `IfcBooleanClippingResult` use the
  first operand only (the import report warns). Openings in *reference* geometry are therefore
  not subtracted unless the source tessellation already contains them. Openings in walls that
  become native walls are recreated by native doors and windows. Openings without a filling are
  counted as unsupported.
- **Unsupported geometry**: NURBS/B-spline surfaces (`IfcAdvancedBrep`), swept disk solids,
  revolved and tapered solids, and most parametric profile types (T, U, C, Z, L, ellipse). These
  are counted per class in `IFCImportReport.unsupported`, and the product is kept as a reference
  element, without geometry if nothing could be evaluated.
- **Export geometry is tessellated.** IFC4 bodies are `IfcTriangulatedFaceSet` (as the
  Reference View expects). IFC2X3 uses swept solids only for straight standard-case walls, flat
  slabs, spaces and openings, and faceted B-reps for everything else. Other tools can't edit these
  bodies parametrically.
- **Schema coverage** is limited to the classes we map. Adding a class means adding a mapping
  and a test, not regenerating an entire schema.

## When to revisit

We should look again at IfcOpenShell (as a separately distributed, dynamically linked helper) or
web-ifc if Arcus needs any of the following:

- a real boolean kernel for foreign geometry, or advanced B-reps
- IFC4x3 infrastructure entities
- round-trip editing of parametric geometry from other authoring tools

Before that happens, licensing and bundle-size costs need a fresh review.
