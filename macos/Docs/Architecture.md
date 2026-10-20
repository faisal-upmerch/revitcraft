# Architecture

Arcus is a single SwiftPM package that builds one executable (`Arcus`, staged into `build/Arcus.app` by `script/build_and_run.sh`), a benchmark executable (`arcus-bench`), the local MCP server (`arcus-mcp`) and fourteen test targets. It uses Swift 6 language mode with strict concurrency. UI targets default to `MainActor` isolation, and the engine targets are `Sendable` value types that can be used from any thread.

```
                ┌──────────────────────────────────────────────────────────────┐
  Arcus (exe)  │ ArcusUI: AppKit shell, SwiftUI panels, Canvas2D, dialogs,   │
                │ Family Editor, QA harness                                    │
                └───────┬───────────────────────┬──────────────────────────────┘
                        │                       │
          ┌─────────────▼─────────────┐   ┌─────▼──────────────┐
          │ ArcusApplication         │   │ ArcusViewport3D   │  Metal renderer, camera, picking,
          │ DocumentSession, commands,│   │ (UI/Canvas3D)      │  section box, orientation widget
          │ tools, snapping, selection│   └─────┬──────────────┘
          └─────────────┬─────────────┘         │
                        │                       │
          ┌─────────────▼───────────────────────▼────────────────────────────┐
          │ ArcusDomain: element model, parameters, transactions,           │
          │ regeneration, views/graphics, sheets, schedules, templates       │
          └───────┬───────────────────────────────┬──────────────────────────┘
                  │                               │
      ┌───────────▼──────────┐        ┌───────────▼──────────┐
      │ ArcusGeometry       │        │ ArcusCalc           │
      │ curves, polygons,    │        │ units, quantity      │
      │ booleans, meshes,    │        │ parsing/formatting,  │
      │ HLR, roofs, spatial  │        │ formulas             │
      └──────────────────────┘        └──────────────────────┘

  Infrastructure (each depends on Domain, never on UI):
    ArcusPersistence  .arcus / .arcusfamily packages (SQLite + manifest + checksums)
    ArcusServices     recovery journal, external-change detection, diagnostics log, signposts, versioning
    ArcusIFC          STEP reader/writer, IFC2x3 CV2.0 / IFC4 RV export & import
    ArcusCAD          DXF reader/writer, CAD → reference drawing conversion, link service, DWG engines (bundled helpers) and provider seam
    ArcusOutput       vector renderer for view/sheet graphics, PDF export, schedule CSV
```

The dependency direction is strict. Geometry and Calc import only Foundation and simd. Domain never imports AppKit. Infrastructure modules never import UI. The build enforces these rules because each layer is its own module.

## The model

- **`BIMModel`** (`Domain/Model/BIMModel.swift`) is a value-type snapshot: an `[ElementID: Element]` dictionary plus project-wide data. It keeps incremental indexes by category, host, owner view, level, type, tag target and viewport. It also keeps a sparse **plan grid** (8 m cells) over linear elements, so neighbour queries such as wall-join candidates are local rather than O(n). Every element mutation gives the snapshot a fresh process-unique `contentStamp`, which derived-data caches use as a cheap first-level key.
- **`Element`** has an id, a category, optional level, host, type, owner view and phase, an IFC GUID, a free parameter bag, and a typed `ElementData` payload with about 44 cases (wall, insert, slab, roof, stair, room, view, sheet, schedule, tag, dimension and so on). Types are elements too (`TypeData` holds type parameters, compound assemblies and the family reference).
- **Parameters** (`Domain/Parameters`) form one catalog of built-in parameters, each with a getter, an optional setter and an optional "locked" reason. Family parameters are evaluated through `FamilyEvaluator` with formulas, and project parameters are bound to categories. The inspector, schedules, tags, filters, IFC property sets and CSV all go through `Parameters`. Hot paths such as schedule cells and tag labels use `descriptor(named:)`, `value(_:of:)` and `isEditable`, which evaluate one parameter rather than building every entry. A test checks that the two paths agree.

## Transactions, regeneration and undo

Every model change is a transaction:

1. `TransactionContext` stages creates, updates and deletes against a working copy. Deletes cascade to hosted inserts, tags, dimensions referencing the element, and group membership.
2. `commit()` runs the `Regenerator`. It re-projects hosted inserts onto edited hosts and removes inserts that no longer fit (with a warning). It repairs dangling references such as a deleted top level, runs the constraint solver (locked dimensions and alignments) and validates the result (sketches, levels, types).
3. The result is a new `BIMModel` and an immutable `TransactionRecord` that holds a before/after pair for every touched element plus project-state changes. A failed validation throws `TransactionError`, and the document's model stays untouched.

`DocumentSession` (`Application/DocumentSession.swift`) installs the new model, registers undo with `UndoManager` (grouped by event), and notifies listeners with a `ModelChange`. That change lists the changed ids and the affected set that `DependencyGraph` computes. Undo applies `record.inverse`, which is exact because records store full before/after elements. Undo and redo are therefore O(changed elements), not a replay.

## Derived data and caching

Geometry is derived, never stored:

- `WallGeometry`: frames, joins (corner/tee/multi-way with kinked end caps), union-boundary footprints, plan cuts, openings, and solids. Solids are extruded elevation profiles in two halves when joined, with remapped end caps. Openings that touch the outline or overlap each other are subtracted with a polygon boolean, so the solid stays closed and manifold.
- `SlabGeometry`/`RoofGeometry` (footprint and slope roof solver, with exact results for convex footprints), `StairGeometry`, `InstanceGeometry` (family evaluation with `FamilyEvalCache`), `TopographyGeometry` (Delaunay plus contours), `RoomGeometry` (planar arrangement of room-bounding segments per level).
- Caches (`GeometryCache`, `RoomBoundaryCache`, `FamilyEvalCache`) key on the revisions of each element's actual inputs (`DependencyGraph.inputs`), so an edit only invalidates what it can affect. `RoomBoundaryCache` also memoizes by `(contentStamp, level)`.

## Views and graphics

`ViewGraphicsBuilder` turns a view into a display list (`ViewGraphics`: `GItem`s of `GPrimitive`s on layers underlay, link, fills, model, cut, annotation, masking and overlay). It works as follows:

- `VisibilityResolver` applies category visibility and overrides, view templates, filters, the phase filter, design options, temporary hide/isolate and the crop region.
- Plans and RCPs cut model solids at the view range cut plane and draw projection below it. Wall cuts use union-boundary cleanup, so joined walls read as one poché.
- Sections, elevations and roof plans use `HiddenLineRenderer` on tessellated solids and add section cuts with material hatches.
- Annotations (dimensions, tags, text, spots, markers and revision clouds) are drawn at paper size, scaled by the view scale.
- `SheetGraphicsBuilder` composes title blocks and viewports, clipping each viewport to its view's crop region.

`ArcusUI.GraphicsStore` builds display lists off the main actor with generation numbers, so it never publishes a stale result. It rebuilds only views that have an open canvas. `Canvas2DView` draws the cached list with CoreGraphics, uses a spatial grid for hit testing and snapping, and routes pointer and keyboard input to tools. `ArcusOutput.GraphicsRenderer` draws the same display lists into PDF contexts, so printed output matches the screen, as vectors.

The 3D view (`ArcusViewport3D`) builds per-element meshes (`ElementMeshes.parts`) into instanced Metal buffers, with section box, visual styles, picking, and an orientation widget.

Curves are tessellated by the view's detail level (`TessellationQuality`: Coarse 24, Medium 36, Fine 72 segments a circle at least, with a 2 / 0.5 / 0.2 mm chord tolerance and a cap). `FamilyEvaluator.evaluate(quality:)` cuts circles and revolves by it and `CurveRefinement` rounds curves stored as points (sketched arcs, rounded corners, turned profiles). `GeometryCache` keeps one entry per element and detail level; the 3D view uses `shadedParts`, the meshes welded with smooth normals across faces that meet at under 35° (`MeshSmoothing`) and silhouette candidates that the GPU draws only where the surface turns away from the eye. Boolean results drop feature edges inside smooth surfaces and close their T-junctions.

## Documents, persistence and recovery

- `ArcusDocument` (an NSDocument subclass) saves `.arcus` packages atomically through safe-save and autosaves in place. Writes happen on a background queue from a `Sendable` snapshot.
- The package holds `model.sqlite` (one row per element as versioned JSON, plus reference drawings and project data), `manifest.json` (schema version, minimum reader version, counts and SHA-256 checksums) and a thumbnail. See [FileFormat.md](FileFormat.md). Reading verifies the checksums and the schema version. A damaged package can be rescued with "save a recovery copy", which keeps every readable element and reports what was repaired or lost.
- `RecoveryJournal` (an actor) writes a base snapshot and an append-only journal of transaction records to `~/Library/Application Support/Arcus/Recovery/<document>`. A clean close discards it. After a crash, the next launch offers Recover (replaying the journal onto the base), Discard, or Decide Later.

## Commands and tools

`CommandCatalog` describes about 200 commands with a title, group, SF Symbol, shortcut, typed aliases, help and keywords. The same catalog feeds the menus, the Command Deck (grouped tabs plus a contextual Modify | … tab), command search (⌘K) and [KeyboardShortcuts.md](KeyboardShortcuts.md). `CommandRouter` enables and disables commands and gives a reason when one is disabled. Tools (`Application/Tools`) are small state machines driven by `ToolInput` (point, snapped point, hit element, modifiers), with temporary dimensions, numeric entry, chaining and sketch mode.

## Exchange

- **IFC**: native Swift STEP reader and writer. Export maps elements to IFC entities, spatial structure, types, materials, property sets, base quantities and classification, with stable GUIDs. Import creates native elements where the mapping is exact and keeps everything else as immutable reference geometry. See [IFCMapping.md](IFCMapping.md) and [EngineDecision.md](EngineDecision.md).
- **CAD**: a native DXF reader and writer. Links convert CAD content into a content-addressed `ReferenceDrawing`. Reload re-reads the source and never writes to it. DWG goes through `DWGImportProvider`: `DWGEngineChain` tries the bundled acadrust helper, the bundled LibreDWG, an installed converter and the ODA SDK build in turn, each turning the DWG into DXF for the same DXF path; `DWGExporter` writes DXF from `DXFWriter` to DWG with the acadrust helper. The helpers are separate processes in `Contents/Helpers`. See [DWGSDKSetup.md](DWGSDKSetup.md).

## Concurrency

- UI state (`DocumentState`, tools, `DocumentSession`) is `@MainActor`.
- Engine types are `Sendable` values. Background work receives model snapshots: view builds, PDF and IFC export, IFC and CAD import parsing, schedules for export, save serialization and thumbnails.
- Cancellation uses cooperative `isCancelled` closures and `Task` cancellation. Long operations appear as background tasks in the status bar with progress and a Cancel button.
- Shared caches are lock-protected `final class`es marked `@unchecked Sendable` with bounded size.

## Testing

- Unit and integration tests live per module (`Arcus/Tests/*`). `LibraryTests` holds the slow Furniture Library suites (FM9, FM9B, FM9C and the shop drawing check), so `DomainTests` stays under a minute; run it with `swift test --filter "LibraryTests\."`. They use generated fixtures (Courtyard House, the stress grid and the template projects) and checked-in golden files (IFC goldens, DXF samples, damaged packages). No test touches the network or user paths.
- `QAHarness` (`--qa workflow|screenshots|all`) drives the real app end to end and writes `results.json` plus screenshots. `script/qa_capture.sh` wraps it. See [Arcus/UITests/README.md](../Arcus/UITests/README.md).
- `arcus-bench` measures engine performance. See [Performance.md](Performance.md).
