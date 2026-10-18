# Verification report

Date: 2026-09-25. Machine: MacBook Pro (Mac17,8, Apple M5 Pro, 48 GB), macOS 27.0 (26A428), Xcode 27 toolchain (Swift 6.4).
Build verified: Arcus 1.0.0, development build `1.2609251653` (the `VERSION` file is 1.0.0 and `BUILD_NUMBER` is 1; release builds stamp that number).

This report records what was actually run and seen. Anything not verified is listed under **Limitations**.

## RevitCraft port pass (2026-10-18)

The Arcus codebase was brought into the `revitcraft` repository (`macos/`) and given RevitCraft's behaviour and features. [RevitCraftPort.md](RevitCraftPort.md) §5 lists each milestone and its known limits.

| Check | Result |
|---|---|
| `swift test` | 1,618 tests in all suites pass, including Metal ↔ CoreGraphics parity (35) and 871 Domain tests |
| Release build | 0 warnings; signed with the Apple Development certificate; installed to `/Applications/Arcus.app` by `script/build_and_run.sh` |
| QA harness (`script/qa_capture.sh all`) | 99 of 99 checks pass, including the dialog audit (every dialog closes with Escape; this failed in the original Arcus) |
| Ribbon | Each tab captured (`ribbon-<tab>-<appearance>`) and checked against RevitCraft's panel order |

Limits of this pass: the feature batches were tested at model level and by the QA harness, and the new dialogs and tools were not walked through by hand. Known partial features are listed per milestone in RevitCraftPort.md.

## 0. This pass: Revit familiarity, Revit interop, Metal, UI polish (2026-09-25)

What was done, and how it was checked:

| Area | What changed | Verified by |
|---|---|---|
| Research | Two Revit textbooks and a six-hour course were read into notes; every gap was checked against the code; the result is [RevitParity.md](RevitParity.md) with seven work packages | Document review |
| Shell | Ribbon with contextual tabs, Options Bar, Properties with Type Selector / instance bar / Edit Type, Project Browser with coloured symbols, view name in the window subtitle, floating navigation bar, status-bar selection toggles, customizable toolbar, Settings for selection modifiers, ribbon behaviour and navigation bar (D24–D26) | Screenshots (light and dark, minimum and spacious windows); QA harness |
| Canvas manipulation | Temporary dimensions you can click and type into, make-permanent button, typed values while dragging, flip arrows, Tab chain-select, Select Previous, EQ/lock and witness-line handles, datum bubble boxes, Tab snap cycling, snap overrides, Shift constraint, BIM selection modifiers, pan/zoom history, Zoom Sheet Size | Unit tests (SelectToolTests, ApplicationTests); canvas interaction QA |
| Modelling | Curtain walls (grids, mullions, panels), wall options and draw modes, wrapping, wall and shaft openings, ramps, roof by extrusion, Edit Stair, shape editing, attach walls afterwards, join geometry | 100+ new unit tests; IFC export of curtain walls and ramps |
| Modify | Create Similar, Measure, Disjoin, radial/associative arrays, offset with inserts, split options, Demolish, Scale, paste between projects | ModifyToolsTests |
| Documentation | Selection Box, per-element graphic overrides, drag views onto sheets, viewport activation, scope boxes, cameras, base/survey points, Place Rooms Automatically, Tag All dialog, colour fill schemes and legends, entire-wall and baseline/ordinate dimensions, area plans | ViewsAndSheetsTests, RoomAreaAnnotationTests |
| Families and templates | EQ/labelled/locked dimensions, sweep/blend/revolve, void cuts, nested families, visibility settings, reload choice, Family Types dialog, Save as Template | FamilyEditorTests, TemplateAndFamilyFormatTests |
| Revit interop | `.arcusx` importer (native elements and families, stable identities), RVT/RFA container inspection (release, preview), Insert ▸ Import Revit Model, BimRv SDK gating in Package.swift, Arcus Bridge add-in source (D29) | 53 RevitTests including 600 corrupted containers; `ARCUS_REQUIRE_REVIT=1` fails the build with instructions |
| Metal 2D | GPU canvas for plans, sections, elevations and sheets; CoreGraphics kept for PDF/print (D27) | 32 CanvasMetalTests incl. pixel parity against CoreGraphics (0.000% mismatch on Courtyard House plans); all QA runs on the GPU path; QA reads back the composited frame |
| Metal 3D | Metal 4 path with classic fallback, residency sets, memoryless targets, pipeline archive, shadows, ambient shadows, silhouettes, Realistic style, MetalFX while orbiting (D28) | 17 Viewport3DTests with Metal API and shader validation |
| File format | Project schema 3 (D30), `.arcusfamily` schema 2 | A real schema-2 document opens with defaults |

Bugs found during this pass and fixed: the GPU layers weren't refreshed on redraw requests (sheets showed only paper); an occluded window kept its display link ticking at 120 Hz; a wall's length value sat under its flip arrow; the contextual ribbon overflowed with a wall selected; the wall-attach prompt after drawing a roof blocked scripted input (the harness now answers it); stale "RVT/RFA not supported" texts; a UTF-8 double-encoding introduced by an editing script (repaired and scanned for).

Measured on this Mac in this pass: Courtyard House opens in 0.21 s (1,973 elements); the 20,172-element stress plan shows 0.58 s after opening; its 3D view renders at 0.38 ms GPU median. Memory is **higher** than in the previous pass because GPU scenes are kept per view: 388 MB with the Courtyard House open, 993 MB with the stress model, 740 MB after closing everything. This has not been tuned for 8 GB Macs yet.

## 1. Build and launch

| Check | Result |
|---|---|
| `script/bootstrap.sh` | Toolchain OK (Swift 6.4, macOS 27.0). DWG SDK not configured (reported, as expected) |
| `script/build_and_run.sh --verify` | ✓ tests passed · ✓ release build succeeded with **0 warnings** · ✓ bundle valid (Info.plist, arm64, ad-hoc signature, no privacy usage descriptions) · ✓ app running · ✓ foreground GUI app with a window on screen |
| App bundle | `build/Arcus.app` (19 MB), bundle id `com.local.Arcus`, `.arcus` and `.arcusfamily` document types |
| Launch command | `open build/Arcus.app` or `script/build_and_run.sh` |
| `ARCUS_REQUIRE_DWG=1` without SDK | Build fails with setup instructions (manifest `fatalError`, see `Package.swift`) |

## 2. Automated tests (`swift test`)

| Suite | Test functions | Result |
|---|---:|---|
| GeometryTests | 110 | ✓ pass |
| CalcTests (units, parsing, formulas) | 118 | ✓ pass |
| DomainTests (model, transactions, joins, rooms, parameters, families, schedules, views, sheets, health, templates, application layer, tools, parity features) | 413 | ✓ pass |
| IFCTests (STEP, export/import, goldens, hostile input, curtain walls, ramps) | 63 | ✓ pass |
| CADTests (DXF read/write, links, DWG provider) | 102 | ✓ pass |
| OutputTests (renderer, PDF, CSV) | 66 | ✓ pass |
| PersistenceTests (package, migration incl. schema 2 → 3, corruption, recovery journal, diagnostics, templates) | 88 | ✓ pass |
| RevitTests (compound-file reader, inspector, .arcusx import, families, hostile input) | 53 | ✓ pass |
| CanvasMetalTests (GPU canvas parity with CoreGraphics, scene, view, performance) | 32 | ✓ pass |
| Viewport3DTests (Metal 4 and classic backends, effects, layouts, decoding) | 17 | ✓ pass |
| **Total** | **1,062** (more counting parameterized cases) | **all pass, 0 known issues** |

No test uses the network, the user's files or Autodesk software. Fixtures are generated in code or checked in under CC0.

### Bugs found by testing and fixed during this pass

An expanded Domain/Application suite (236 new tests) found 16 genuine bugs. All are fixed, and the tests now assert the correct behaviour:

1. Room areas were stale after undo followed by a different edit (cache keyed on reused revision numbers). Fixed with process-unique revision stamps (Decision Log D17).
2. The same issue made door and window sizes stale after a type edit, undo and a different edit.
3. Ten starter families used bare numbers in length expressions (`Width / 2 - 0.05`), which dropped their legs and parts. Units were added. Four families also degenerated when their Height was flexed to 50%; their fixed heights are now proportional.
4. Mirroring flipped door and window hands the wrong way.
5. Mirrored components came out rotated 180°.
6. Paste to another level was rejected for walls (the top constraint wasn't remapped).
7. Levels and views could be renamed to an empty name through `Parameters.set`.
8. Non-itemized schedules added up minimum/maximum fields.
9. "Minimum and maximum" totals were computed as sums.
10. Percent-of-group fields used the grand total.
11. Grids never appeared in elevations.
12. Eight command ids had no catalog entry (the unused ids were removed).
13. Typed aliases could lose to title matches in Command Search (`DR` opened Drafting View instead of Door).
14. Tab cycling skipped a candidate after pointer moves.
15. Courtyard House GUIDs were not fully deterministic.
16. The residential template's timber-frame wall lost its membrane layer. Schedule viewports on sheets were one row too tall.

Other defects found and fixed in this pass:

- Wall solids with openings touching the base were not watertight. They are now closed, IFC exports them as `Closed = .T.`, and the golden file was updated.
- An invalid IFC GUID in a package made the element unreadable instead of reported and repaired.
- Performance problems: see §5.
- Closed documents could stay in memory. See §6.

## 3. End-to-end QA in the running app (`script/qa_capture.sh all`)

**26 of 26 steps passed** (plus the 39-step interaction scenario in §3a; 66/66 in total (a snapping and corner-join step was added), re-run on build 1.2609252234 with the GPU canvas). Each step checks the model or rendered output, not just that code ran:

| # | Step | Evidence |
|---:|---|---|
| 1 | New project from the Architectural template | 176 template elements |
| 2 | Draw walls in plan | 4 walls, corners joined |
| 3 | Hosted door and window | host cuts and tags present |
| 4 | Floor by picking walls (sketch mode) | area 88.54 m² |
| 5 | Room, column, component, stair with railings | room area 88.38 m² |
| 6 | Beam and grid | created |
| 7 | Hip roof by footprint; ceiling in RCP | created |
| 8 | New level from an elevation | Level 4 at 11.5 m with plan and RCP |
| 9 | Instance and type parameters with undo/redo | width 1.60 → 1.10 → undo 1.60 → redo 1.10 |
| 10 | Dimension, Tag All, text, revision cloud | dimension measures 12.380 m; 9 tags |
| 11 | Keyboard element stepping and VoiceOver actions | `]` / `[` step and return; 5 custom actions |
| 12 | Section from model | 25 display items, cut walls present |
| 13 | Live schedules | door and room rows update |
| 14 | Sheet with plan and schedule viewports | A101 |
| 15 | Vector PDF export | every page vector, 0 raster pages |
| 16 | IFC4 and IFC2x3 export and round trip | exported 16 elements; re-imported 13 as native |
| 17 | Schedule CSV and view DXF export | files written |
| 18 | DXF link, reload, convert to detail lines | 186 entities linked, 162 converted, source bytes unchanged |
| 19 | DWG without SDK | truthful "not available in this build" message, DXF offered |
| 20 | Save, close, reopen | 380 elements, schema 3 |
| 21 | File ▸ Open Recent lists projects | built from `NSDocumentController.recentDocumentURLs` using public API only (a private AppKit call was removed) |
| 22 | 3D coordination view | 1,936 triangles |
| 23–24 | Open the Courtyard House (light, dark) | 1,967 elements in 0.16–0.17 s |
| 25 | 20,000-element stress model in the app | plan on screen 0.37–0.45 s after open; 3D 240k triangles at 0.37 ms GPU median |
| 26 | Closed documents are released | 3 closed, 3 freed |

## 3a. Canvas interaction QA (`script/qa_capture.sh interact`)

This follows a report that "things vanish" in the view canvas. The new interaction scenario drives the real canvas with window-routed mouse, scroll and keyboard events (39 steps, 119 canvas checks). After every action it checks that the display list is current and complete and that every element in view actually has ink on screen. See `Arcus/UITests/README.md`. Result: **39/39 steps, 119/119 canvas checks pass** (re-run in this pass on the Metal canvas; ink is checked on the composited GPU frame).

Bugs it found, all fixed:
- **The view vanished while a tool or drag was active in dark mode.** The preview pass painted the dark canvas colour over the entire visible area during wall drawing, door and window placement, sketching and drag-moves. This was the reported symptom. It is fixed in `GraphicsRenderer`, with a regression test (D20).
- **Dragged elements snapped to their own original geometry**, so short drags hardly moved. Moving one wall also opened the corners of the walls joined to it. Both are fixed: dragged elements are excluded from snapping, and joined walls now follow (D21).
- **Temporary hide/isolate had no visible indicator** on the canvas (typing `HH` or `HI` hid elements silently). It is now framed and labelled (D22).
- The Courtyard House's Sections 2 and 4 ran exactly along partition walls, so their cut fill hid everything behind. They were moved to mid-room. Plan crop boundaries are now visible.
- New-project elevation markers moved from ±41 m to ±21 m, so "zoom to fit" shows a usable working area.

## 4. Visual QA

Screenshots were captured from the real windows at the minimum (980 × 640) and a spacious size, in light and dark appearance. A curated set is in [Docs/Screenshots](Screenshots):

onboarding, hub, plan (min and spacious), selected wall with Properties, sketch mode, wall tool with temporary dimensions, schedule, sheet, section, elevation, 3D, the IFC export, DWG unavailable, Model Health, Visibility/Graphics and Schedule Properties dialogs, Command Search, error toast, and the crash-recovery prompt.

Defects found by inspecting screenshots and fixed:

- The Command Deck tab strip and labels were clipped. The deck moved to a split-item accessory with a fixed height.
- Document windows merged into window tabs. Tabbing is now disallowed.
- The type selector showed only the family name. It now shows family, type and swatch.
- Courtyard House sheets overflowed A1. Views are now cropped at 1:200.
- Zoom-to-fit didn't follow window resizes, and clipped level heads outside the crop.
- Floors protruded past the exterior wall faces.
- The wall tool's length and angle readouts overlapped.
- Dialogs were narrower than their content (IFC export, Visibility/Graphics, Schedule Properties) and clipped their titles.
- Model Health's empty state was blank.

Verified live: the app launched by `--verify` shows the hub, and the recovery prompt appears after a forced quit with unsaved changes (screenshot included).

## 5. Performance

See [Performance.md](Performance.md) for the full tables and method: `arcus-bench`, in-app measurements, and Instruments signposts recorded with `xctrace`. Highlights, release build:

- Courtyard House: plan display list 7 ms, all 10 schedules 20 ms, edit plus regeneration 0.3 ms, undo 0.2 ms, 16-sheet vector PDF 1.1 s.
- 20,000 elements: plan display list 128 ms, all meshes 77 ms, moving all 10,000 walls in one transaction 99 ms, undo 1.1 ms.
- Fixes made after measuring: the stress plan went from 13.7 s to 0.13 s, all meshes from 13.9 s to 0.08 s, moving all walls from 37.8 s to 0.10 s, and Courtyard schedules from 603 ms to 20 ms.

## 6. Memory and resource release

- Footprint with the Courtyard House open is about 120–325 MB, depending on session history. With the 20k stress model open at the end of a full QA session it was 739–824 MB. After closing all documents it was 361–563 MB (freed memory is kept by the allocator for reuse).
- Heap analysis (`heap`, `leaks --traceTree`) found SwiftUI's focus and sheet bookkeeping keeping the last closed window alive. Closing a document now explicitly releases its model, undo history, display lists and tasks, and purges derived caches when the last document closes. QA step 26 checks this on every run.

## 7. Privacy and permissions

- There are no network, telemetry, analytics or account APIs in the source (audited with `grep`). `otool -L` shows only Apple system frameworks and system libraries.
- `Info.plist` contains no usage-description keys, and the build script fails if one appears. No privacy permission is ever requested.
- Updates: none. The app states that it never checks the internet.
- Details: [PrivacyAndPermissions.md](PrivacyAndPermissions.md).

## 8. Accessibility

- VoiceOver labels, values and hints on custom controls, and canvas custom actions. `]` / `[` element stepping with announcements. Toasts are announced. Reduce Motion, Reduce Transparency and Increase Contrast are honoured, and the canvas responds to Increase Contrast live.
- Verified by code review and by the automated QA step. A manual pass with a screen-reader user was **not** done.
- Details: [Accessibility.md](Accessibility.md).

## Limitations (honest list)

- **DWG:** support compiles only against a licensed ODA Drawings SDK, which was not available. The ODA bridge (`Arcus/Infrastructure/Exchange/DWGBridge`) has **never been compiled or run**, and its library layout guesses are unverified. Without the SDK, Arcus truthfully reports that DWG is unavailable and offers DXF.
- **RVT/RFA:** not read directly and not claimed. The Arcus Bridge add-in (C#, `Tools/RevitBridge`) has **never been compiled or run**: this Mac has no .NET SDK and no Revit. Its importer side is tested with hand-written `.arcusx` fixtures only. The ODA BimRv bridge is an unverified sketch whose SDK calls are TODOs. See [RevitInterop.md](RevitInterop.md) for the parts marked UNVERIFIED.
- **IFC:** architectural subset (IFC2x3 CV 2.0 and IFC4 RV). Unsupported entities import as reference geometry. Round trips are exact for Arcus-authored models; files from other tools were tested only with the hand-written fixtures in `Arcus/Tests/IFCTests/Fixtures`.
- **Geometry:** roofs on non-convex footprints use a documented approximation. Hidden-line views do not compute intersection lines between separate solids. Family forms are extrusions, sweeps, blends and revolves; only void extrusions cut solids (no general mesh booleans).
- **Scope:** no worksharing or multi-user editing, rendering or materials beyond flat colours and patterns, MEP, structural analysis, scripting, or cloud features.
- **Platforms:** measured on one M5 Pro Mac. Not run on an 8 GB Mac or on Intel. Memory with GPU scenes is higher than before (see §0) and low-memory behaviour (smaller shadow maps, dropping 3D extras under memory pressure) is unit-tested only.
- **Parity features:** the new canvas controls, curtain walls, ramps, colour schemes and other additions of this pass are covered by unit tests and the standard QA scenarios, but several of their visual details (for example ramp plan symbols, curtain wall elevations, colour fill legends, Family Editor sweep previews) were not inspected screen by screen. They are listed under "Visual checks still owed" in [RevitParity.md](RevitParity.md), which also lists what remains open per package.
- **Distribution:** ad-hoc signed, not sandboxed, not notarized (by request). Release numbering is local (`script/release_local.sh`).
- **UI automation:** end-to-end checks run through the in-app harness (model-level assertions plus screenshots), not XCUITest. Pointer-driven interactions (drags, grips, snapping under the cursor) are exercised through the tool APIs with synthetic inputs, not through real mouse events, and no scripted mouse session was recorded.
