  | Revit models and families via the Arcus Bridge add-in (`.arcusx`) | ✓ (native, editable elements and families; re-import updates in place) | | |
  | RVT / RFA directly | only with a licensed ODA BimRv SDK build; otherwise Arcus shows the file's release and preview and explains the two routes that work | | |
# Arcus

Arcus is a native macOS app for architectural BIM authoring. You model levels, grids, walls, doors, windows, floors, roofs, ceilings, rooms, stairs, railings, columns, beams and components, and Arcus keeps plans, reflected ceiling plans, sections, elevations, 3D views, schedules and sheets coordinated with every change. It targets the everyday scope of a small-practice BIM tool. It is not a clone of any other product. People coming from Revit will find the conventions they know (ribbon tabs, contextual "Modify | Place" tabs, the Options Bar, the Properties palette with Type Selector and Edit Type, the Project Browser, two-letter shortcuts, temporary dimensions). Arcus does not open RVT or RFA files directly: models and families come in through an open exchange format written by a companion add-in, or through IFC (see [Revit interop](Docs/RevitInterop.md)).

Everything runs locally. Arcus makes no network connections, collects no analytics, needs no account and asks for no privacy permissions.

- **Platform:** macOS 26 or later on Apple silicon. It was built and verified on macOS 27 with Xcode 27 (Swift 6.4).
- **Version:** see `VERSION` and `BUILD_NUMBER`. Development builds are stamped `1.<yyMMddHHmm>`.
- **Status:** see [Docs/VerificationReport.md](Docs/VerificationReport.md) for what was built, tested and verified, and what is still limited.

## Quick start

```bash
script/bootstrap.sh          # checks the toolchain (installs nothing)
script/build_and_run.sh      # builds, signs and validates Arcus.app, installs it to /Applications and launches it
```

Other entry points:

| Command | What it does |
|---|---|
| `script/build_and_run.sh --verify` | Runs the full test suite, builds, validates the bundle, launches the app and checks that a window appears |
| `script/build_and_run.sh --debug` | Debug build |
| `script/build_and_run.sh --no-launch` | Build and validate only |
| `swift test` | All unit and integration tests (Geometry, Calc, Domain, IFC, CAD, Output, Persistence) |
| `swift run -c release arcus-bench [--quick] [--out file.json]` | Engine benchmarks on the generated fixtures (see [Docs/Performance.md](Docs/Performance.md)) |
| `script/qa_capture.sh all <dir>` | Scripted end-to-end QA workflow plus light/dark screenshots at minimum and spacious window sizes |
| `script/release_local.sh patch\|minor\|major` | Bumps `VERSION`/`BUILD_NUMBER`, writes release notes and builds and verifies the release. Local only: no signing identity, notarization or upload |

The app bundle is staged at `build/Arcus.app`, signed with the first "Apple Development" certificate in the keychain (or `ARCUS_SIGN_IDENTITY`; ad hoc when there is none), installed to `/Applications/Arcus.app` and launched from there. A stable certificate keeps macOS privacy grants across rebuilds. Pass `--no-install` to keep it in `build/` only.

## What you can do

- **Model:** levels and grids (with scope boxes); basic and compound (layered) walls with joins, wrapping, flip, attach top/base and edit profile; curtain walls with grids, mullions and swappable panels; hosted doors and windows; wall and shaft openings; floors, ceilings and roofs (footprint, pick walls or extrusion; slope arrows, shape editing, attach walls afterwards); join geometry between walls, floors, roofs and ceilings; rooms and areas (placed automatically if you like), area plans and schemes; straight, L- and U-shaped stairs with Edit Stair; ramps; railings; architectural and structural columns; beams; loadable components; model groups; toposurfaces and building pads.
- **Modify:** align, offset (carrying hosted doors and windows), mirror, move and copy (with Disjoin), rotate, scale, linear and radial arrays (associative, editable count), trim/extend, split (with gap or delete inner segment), pin, demolish, Create Similar, Measure, match type, paste aligned and paste between projects. Temporary dimensions on the selection can be clicked and typed into; flip arrows, Tab chain-selection, Select Previous, snap overrides and Shift-constrained drawing work as BIM users expect.
- **Parameters:** instance and type parameters, project parameters, formulas with units, type catalogs, and editing in the Properties inspector or directly in schedules.
- **Families:** a Family Editor for doors, windows, furniture, casework, generic models, columns, framing, tags, annotations, title blocks and profiles. It supports reference planes with strength, labelled, locked and EQ dimensions, formulas, extrusions, sweeps, blends and revolves (void extrusions cut), nested families, visibility settings by view and detail level, symbolic lines, labels, the Family Types dialog and flex testing, and saves `.arcusfamily` packages. Projects can be saved as templates.
- **Views:** floor plans, RCPs, structural plans, area plans, sections, elevations, callouts, drafting views, 3D views and perspective cameras. They have view ranges, crop regions, visibility/graphics overrides and per-element graphic overrides, filters, view templates, colour fill schemes with legends, phases, design options, underlays, section and selection boxes, and temporary hide and isolate. 2D views are drawn on the GPU with Metal 4 (CoreGraphics fallback); 3D views use Metal 4 with shadows, ambient occlusion, silhouette edges, a Realistic style and MetalFX upscaling.
- **Documentation:** dimensions (including entire-wall, baseline and ordinate strings), spot elevations, tags (including the Tag All dialog), text, revision clouds, detail components and filled regions; live schedules and quantities with sorting, grouping, totals, calculated fields and CSV export; sheets with title blocks, viewports (drag a view from the Project Browser; double-click to activate), revisions and sheet lists; vector PDF export and printing.
- **Exchange:**

  | Format | Import | Link | Export |
  |---|---|---|---|
  | IFC2x3 CV 2.0 / IFC4 RV | ✓ (native elements where possible, otherwise reference geometry; GUIDs preserved) | | ✓ |
  | DXF (R12–2018, ASCII and binary) | ✓ | ✓ (reload keeps the source untouched) | ✓ |
  | DWG | only with a licensed ODA Drawings SDK build; otherwise Arcus says plainly that it is unavailable | same | |
  | PDF / PNG / JPEG / TIFF underlays | | ✓ | |
  | PDF (vector) | | | ✓ |
  | CSV (schedules) | ✓ (update parameters) | | ✓ |

- **Safety:** undo and redo for every model change; autosave in place; a crash-recovery journal that offers to recover unsaved changes at next launch; a transactional SQLite `.arcus` package with checksums, integrity verification and "save a recovery copy" for damaged files; a Model Health panel.

## Repository layout

```
Package.swift                SwiftPM manifest (all targets; ODA SDK gating)
Arcus/App                   executable entry point
Arcus/UI                    AppKit/SwiftUI shell, 2D canvas, 3D viewport host, inspectors, dialogs, Family Editor, QA harness
Arcus/Application           commands, tools, snapping, selection, DocumentSession (undo/redo)
Arcus/Domain                geometry, units and formulas, element model, parameters, regeneration, views, sheets, schedules, templates
Arcus/Infrastructure        persistence (.arcus), recovery journal, diagnostics, versioning, IFC, CAD (DXF/DWG), PDF/CSV output
Arcus/Resources             Info.plist, app icon
Tools/RevitBridge            Arcus Bridge add-in source (C#, public Revit API) and the .arcusx schema
Arcus/Bench                 arcus-bench performance harness
Arcus/Tests                 unit/integration tests and fixtures
Arcus/UITests               in-app QA scenarios (see its README)
Docs/                        architecture, file format, IFC mapping, DWG setup, shortcuts, performance, accessibility, privacy, verification, decisions
script/                      bootstrap, build/run/verify, QA capture, local release, icon generation
```

## Documentation

- [Architecture](Docs/Architecture.md): layers, data flow, transactions, regeneration and rendering
- [Engine decision](Docs/EngineDecision.md): why IFC and geometry are native Swift
- [File format](Docs/FileFormat.md): the `.arcus` and `.arcusfamily` packages
- [IFC mapping](Docs/IFCMapping.md)
- [DWG SDK setup](Docs/DWGSDKSetup.md)
- [Keyboard shortcuts](Docs/KeyboardShortcuts.md)
- [Revit parity](Docs/RevitParity.md): the conventions and features Revit users expect, and their status
- [Revit interop](Docs/RevitInterop.md): the Arcus Bridge add-in, the `.arcusx` format and direct-import licensing
- [Metal 2D canvas](Arcus/UI/CanvasMetal/README.md): GPU renderer architecture, parity and performance
- [Performance](Docs/Performance.md)
- [Accessibility](Docs/Accessibility.md)
- [Privacy and permissions](Docs/PrivacyAndPermissions.md)
- [Verification report](Docs/VerificationReport.md)
- [Decision log](Docs/DecisionLog.md)
- [Third-party notices](THIRD_PARTY_NOTICES.md)

## DWG

Arcus never pretends to read DWG. DWG support compiles in only when `ARCUS_ODA_SDK_DIR` points at a licensed ODA Drawings SDK. Set `ARCUS_REQUIRE_DWG=1` to make the build fail with setup instructions when the SDK is missing. Without the SDK, opening a DWG shows an explanation and offers DXF instead. See [Docs/DWGSDKSetup.md](Docs/DWGSDKSetup.md). Vendor headers, binaries and activation keys stay out of this repository.

## Proprietary formats

Arcus does not read or write RVT or RFA files, does not reverse-engineer them, and never renames another format to `.rvt` or `.rfa`. Three honest routes exist: (1) the Arcus Bridge add-in (in `Tools/RevitBridge`, built by you against Revit's public API) exports models and families to the open `.arcusx` format, which Arcus imports as native, editable elements; (2) IFC export from the authoring tool; (3) a direct-import provider that compiles only against a licensed ODA BimRv SDK (`ARCUS_ODA_BIMRV_SDK_DIR`; `ARCUS_REQUIRE_REVIT=1` fails the build without it). Without the SDK, Arcus can still show an RVT/RFA file's release and embedded preview image.
