# Revit interoperability

Arcus brings Revit projects (`.rvt`) and families (`.rfa`) in as **native, editable Arcus elements**: walls with
layered types, floors, roofs, doors and windows hosted in walls, rooms, and parametric loadable families. This document
covers where Arcus stands legally, the three import routes, the user workflow, the **Arcus Exchange** schema
(`.arcusx`) and the current limitations.

Code: `Arcus/Infrastructure/Exchange/Revit` (module `ArcusRevit`), tests: `Arcus/Tests/RevitTests`, Revit add-in and
JSON Schema: `Tools/RevitBridge`.

## Legal stance (plain language)

- Revit's file format is **Autodesk's proprietary format**, and it has no public specification. Arcus **does not
  reverse-engineer it**. Arcus has no code that decodes Revit's model data (elements, parameters, geometry) from
  `.rvt`/`.rfa` files. It contains **no Autodesk binaries, headers, SDK files or Autodesk documentation text**.
- Revit files are stored inside a *compound file* container, a generic Microsoft format with an open, published
  specification ([MS-CFB]). Arcus reads that container **only** to:
  1. list the names of the streams inside it;
  2. extract the embedded **preview image**, a standard PNG stored in the `RevitPreview4.0` stream. Arcus finds it by
     its PNG signature;
  3. show the Revit **release** and **file kind**. It scans the `BasicFileInfo` stream for readable text (for example
     `Format: 2024` or a saved file name ending in `.rfa`) and decodes no other structure in it.

  This is comparable to showing a file's thumbnail and version stamp in a file browser.
- The **Arcus Bridge** add-in uses Autodesk's **public Revit API**, which Autodesk publishes for add-in developers. It
  runs inside the user's own licensed copy of Revit and writes an open format. Users must follow their Autodesk license
  terms. The add-in references `RevitAPI.dll`/`RevitAPIUI.dll` from the local Revit installation and never ships them.
- **Direct** `.rvt`/`.rfa` import is possible only through a **licensed** third-party SDK: the Open Design Alliance
  **BimRv** SDK. Arcus never bundles, redistributes or downloads it. Each build machine needs its own license. Check the
  ODA membership terms for your use. Builds without the SDK say plainly that direct import is unavailable.
- **IFC** is an open ISO standard (ISO 16739), and Arcus reads it natively.

This section explains the engineering boundaries. It is not legal advice.

## The three routes

| Route | Works in | What arrives in Arcus | Fidelity |
| --- | --- | --- | --- |
| **1. Arcus Bridge add-in → `.arcusx`** (recommended) | Every Arcus build; needs Revit on Windows | Native levels, grids, materials, compound types, walls, floors, ceilings, roofs, doors, windows, rooms, columns, beams, stairs, railings, **parametric families**; reference meshes for the rest | Highest: types, layers, hosting, parameters and formulas carry over |
| **2. IFC export from Revit** | Every Arcus build | Native walls, slabs, columns, beams, spaces, doors/windows; reference geometry for the rest (see Docs/IFCMapping.md) | Good for geometry; families are not parametric |
| **3. Direct `.rvt`/`.rfa` via ODA BimRv** | Only builds made with the licensed SDK (`ARCUS_HAS_ODA_BIMRV`) | Same as route 1 (the SDK bridge writes Arcus Exchange internally) | **Unverified**, see below |

Without the SDK, opening an `.rvt`/`.rfa` file shows what Arcus can tell about the file (kind, Revit release,
preview) and the message from `UnavailableRevitProvider`. That message explains routes 1 and 2 and names the SDK
that route 3 needs.

## User workflow

### Route 1: Arcus Bridge

1. Install the add-in once (Tools/RevitBridge/README.md: build, then copy `ArcusBridge.dll` and `ArcusBridge.addin`
   to `%AppData%\Autodesk\Revit\Addins\<version>\`).
2. In Revit, open the project and choose **Add-Ins ▸ Arcus ▸ Export to Arcus**. Choose where to save the `.arcusx`.
   The add-in opens each loadable family used by exported doors, windows and components to export its definition,
   then closes it without saving.
3. For a single family, open it in the Family Editor and choose **Add-Ins ▸ Arcus ▸ Export Family to Arcus**.
4. In Arcus, import the `.arcusx` file. A project file adds its elements to the open project (or to a new one). A
   family file loads the family. `ExchangeImportReport.familyDefinitions` lets the UI save it as a `.arcusfamily`.
5. Read the import report. It gives counts per kind, what was approximated or turned into reference geometry, and why.
6. After changes in Revit, export again and import into the same Arcus project. Elements are matched by their Revit
   `UniqueId` and **updated in place**, keeping their Arcus ids. The other policies are `keep` (leave existing elements
   untouched) and `duplicate` (import a second copy).

### Route 2: IFC

In Revit choose **File ▸ Export ▸ IFC** (IFC4 Reference View or IFC2x3 Coordination View), then import the `.ifc` in
Arcus.

## Arcus API

```swift
import ArcusRevit

// Container facts: works in every build and never decodes Revit model data.
let info = try RevitFileInspector.inspect(url)          // RevitFileInfo
info.kind            // .project / .family / .template / .unknown
info.revitRelease    // "2024"
info.previewPNG      // Data? (standard PNG)
info.streamNames     // ["BasicFileInfo", "RevitPreview4.0", …]

// Arcus Exchange import (route 1).
let tx = TransactionContext(model: model, name: "Import Revit")
let report = try ArcusExchangeImporter.import(data: data, into: tx, options: .init())
let result = try tx.commit()
report.created["walls"]; report.warnings; report.familyDefinitions

// Families without a project (for example to save as .arcusfamily).
let families = try ArcusExchangeImporter.familyDefinitions(data: data)

// Direct import seam (route 3).
let provider = RevitProviders.current      // UnavailableRevitProvider unless built with the ODA BimRv SDK
provider.isAvailable; provider.unavailableReason
try provider.import(url, into: tx, options: .init())   // throws .unavailable(message) without the SDK
```

`CompoundFile` is a general, defensive [MS-CFB] reader (versions 3 and 4, FAT/DIFAT/mini FAT). It bounds-checks every
offset, detects cycles in sector chains and in the directory tree, walks the tree iteratively, and caps sizes with
`CompoundFileLimits`.

The importer never crashes on hostile input. Size limits (`maxInputBytes`, `maxObjects`, per-mesh and total triangle
caps, `maxCurvesPerSketch`, `maxCoordinate`) apply before any element is created. Lists are decoded item by item, so
one malformed object is skipped and reported instead of failing the file. Unknown keys and sections are ignored.
Broken references, invalid sketches and impossible heights become warnings. After creating elements, the importer
commits a scratch copy and removes anything Arcus's validation would reject, so the caller's commit does not fail
because of the import.

## Arcus Exchange schema 1.0 (`.arcusx`)

The machine-readable schema is `Tools/RevitBridge/arcus-exchange.schema.json` (JSON Schema 2020-12). The Swift types
are in `Arcus/Infrastructure/Exchange/Revit/Exchange/ExchangeSchema.swift`. The add-in's C# classes are generated from
the JSON Schema. `SchemaConsistencyTests` checks that the Swift types, the JSON Schema and the test fixtures agree.

### Conventions

- **Units:** lengths in meters, areas m², volumes m³, angles radians, slopes rise/run. Model coordinates are the source
  model's internal coordinates (Z up), converted to meters. `units.system` (`metric`/`imperial`) is only a display
  preference.
- **Identity:** every object has an `id` that is unique within the file and used for references (`typeId`, `levelId`,
  `hostId`, `materialId`, …), and optionally a `uniqueId`, the source's stable identity (Revit `UniqueId`). Arcus sets
  each element's GlobalId to `IFCGUID.deterministic("revit-uniqueid:" + uniqueId)`, so the same Revit element gets the
  same GlobalId in every import and every project. For objects without a `uniqueId`, the seed is `source.documentId`
  plus the kind and `id`.
- **Versioning:** `schemaVersion` is `"MAJOR.MINOR"`. A file with a newer **major** version is rejected with a clear
  error (`ExchangeImportError.unsupportedSchemaVersion`). A newer **minor** version imports, with a warning that unknown
  content was ignored. Writers must keep minor versions backward compatible and only add optional properties.
- **Robustness:** enumerations are strings. Unknown values fall back to the default listed below and produce a warning.

### Top level

| Key | Type | Notes |
| --- | --- | --- |
| `format` | `"arcus-exchange"` | Required |
| `schemaVersion` | `"1.0"` | Required |
| `generator` | `{name, version, host, exportedAt}` | Informational |
| `documentKind` | `"project"` \| `"family"` | Default `project` |
| `source` | `{fileName, path, documentId, application}` | `documentId`: stable document identity (Revit: ProjectInformation `UniqueId`; family: owner family `UniqueId`) |
| `units` | `{system, length}` | |
| `projectInfo` | `{name, number, clientName, address, status, issueDate, author, organization, buildingName, siteName, latitude°, longitude°, elevation, trueNorthAngle, projectBasePoint, surveyPoint}` | Applied when `applyProjectInfo` |
| `materials`, `levels`, `grids`, `types`, `families`, `walls`, `floors`, `ceilings`, `roofs`, `inserts`, `rooms`, `columns`, `beams`, `stairs`, `railings`, `components`, `meshes` | arrays | See below |

### Shared value shapes

- **Curve (plan):** `{"type": "line", "start": [x, y], "end": [x, y]}`,
  `{"type": "arc", "start", "mid", "end"}` (three points on the arc, so there are no angle conventions to get wrong), or
  `{"type": "circle", "center", "radius"}`. Other source curves (ellipses, splines) are written as line segments.
- **Transform:** `{origin: [x,y,z], basisX, basisY, basisZ}`, the family's axes in model coordinates. Arcus derives
  rotation, mirroring and door/window flips from it.
- **Mesh:** `{positions: [x,y,z, …], indices: [i,j,k, …]}`.
- **Value** (parameters): number (SI), boolean, text, `{"materialId": "…"}`, `{"elementId": "…"}` or `null`.
- **Scalar** (family coordinates): number (meters), an Arcus formula string (constants need units:
  `"-Width / 2 - 0.05 m"`), or `{"plane": "Left"}` (bound to a reference plane).

### Objects

| Array | Object | Key fields | Arcus result |
| --- | --- | --- | --- |
| `materials` | material | `name, materialClass, color "#RRGGBB", transparency 0–1, description, manufacturer, model, mark, keynote, cost` | Material (reused by name when one already exists) |
| `levels` | level | `name, elevation, isBuildingStorey, isStructural` | Level plus a floor plan view. An existing level with the same name and elevation is reused; a clashing name is renamed "… (Revit)" |
| `grids` | grid | `name, curve, bottomElevation, topElevation` | Grid (clashing names are renamed) |
| `types` | type | `category` (walls, floors, ceilings, roofs, buildingPads, columns, structuralColumns, structuralFraming, stairs, railings), `kind` (basic/curtain/stacked), `layers[]` `{function, materialId, thickness, wraps, isVariable, isCore}`, `coreStart/coreEnd`, `wrappingAtInserts/AtEnds`, `thickness`, `function`, `typeMark`, `description`, `fireRating`, `materialId`, `section {shape, width, depth, diameter}`, `stair {maxRiserHeight, minTreadDepth, treadThickness, waist}`, `railing {height, balusterSpacing, balusterSize, railSize}` | Compound types (layer order: exterior→interior for walls, top→bottom otherwise; layer functions structure/substrate/thermal/membrane/finish1/finish2, `structuralDeck` → structure). Column/beam/stair/railing types |
| `walls` | wall | `typeId, levelId, curve, locationLine` (wallCenterline, coreCenterline, finishFaceExterior, finishFaceInterior, coreFaceExterior, coreFaceInterior), `baseOffset, topLevelId, topOffset, unconnectedHeight, flipped` (**true when the exterior is to the right of the curve**), `structural, roomBounding, joinAtStart, joinAtEnd, mark, comments, mesh` | Native wall; curtain/stacked types → reference mesh |
| `floors`, `ceilings` | slab | `typeId, levelId, boundary` (loops; the largest is the outer boundary), `offset` (floors: top; ceilings: bottom), `slopeArrow {tail, head, tailOffset, slope}`, `structural, roomBounding` | Native floor/ceiling |
| `roofs` | roof | `kind` (`footprint`, anything else → mesh), `footprint` loops whose curves carry `definesSlope, slopeAngle, overhang`, `baseOffset, overhang` | Native footprint roof (the largest loop is the eave) |
| `inserts` | insert | `category` (doors/windows), `typeId` (a family type), `hostId` (a wall), `location [x,y,z]` (z = bottom of the opening), `sillHeight` (above the level, used when there is no z), `transform` (preferred), `facingFlipped/handFlipped` (Arcus convention, used without a transform), `parameters` | Native door/window hosted in the wall |
| `rooms` | room | `name, number, levelId, point, upperLimitLevelId, limitOffset, baseOffset, department` | Room (boundaries are recomputed by Arcus) |
| `columns` | column | `category, typeId, levelId, location, rotation, transform, baseOffset, topLevelId, topOffset, unconnectedHeight, slanted` | Native column (slanted → mesh) |
| `beams` | beam | `typeId, levelId, curve` (straight), `startOffset, endOffset, zJustification` (top/center/bottom) | Native beam (curved → mesh) |
| `stairs` | stair | `shape` (straight, lShaped, uShaped; others → mesh), `origin, direction, width, riserCount, firstRunRisers, turnsLeft, baseOffset, topLevelId, topOffset, unconnectedHeight, riserHeight, treadDepth, mesh` | Native stair when Arcus can lay it out, else mesh |
| `railings` | railing | `typeId, levelId, hostId` (a stair), `path` curves, `baseOffset` | Native railing |
| `components` | component | `category, revitCategory, typeId, levelId, transform` (or `location/rotation/mirrored`), `parameters, mesh` | Native component when its family has geometry, else the mesh |
| `meshes` | meshElement | `category, revitCategory, name, levelId, positions, indices, materialId, reason, parameters` | **Reference geometry** (read-only), named "… (reference)", labelled `Revit: <category>`, with the reason and parameters as properties |

### Families

`families[]`: `{id, uniqueId, name, category, revitCategory, description, manufacturer, hostKind, definitionIncluded,
parameters, types, referencePlanes, dimensions, geometry, planLines, opening}`.

- **Coordinates:** origin at the insertion point, X along the host (width), Y toward the facing/exterior side, Z up.
- **parameters:** `{name, dataType, isInstance, group, formula, isBuiltIn, isShared, isReporting, builtIn}`. `dataType`
  is one of length, area, volume, angle, slope, number, integer, percentage, currency, text, multilineText, yesNo, url
  or material. Other types (for example family types) are skipped with a warning. `builtIn: "width"|"height"` marks the
  built-in Width/Height (useful when the display name is localized). Formulas use Arcus's formula language, which
  accepts common Revit formulas (`if`, `and`, `or`, `not`, units such as `mm` and `'`). An unreadable formula is dropped
  (with a warning) and the parameter keeps its type values.
- **types:** `{id, uniqueId, name, values, typeMark, description, fireRating}`. Values of formula parameters are
  ignored. Material values (`{"materialId"}`) go to the project type, because family definitions stay project-independent.
- **referencePlanes:** `{name, axis: x|y|z, offset: scalar, strength, definesOrigin}`.
  `strength` is one of notAReference, weak, strong, left, centerLeftRight, right, front, centerFrontBack, back, bottom,
  centerElevation or top.
- **dimensions:** `{planeA, planeB, label}`.
- **geometry:**
  - `{"kind": "extrusion", extrusionAxis, extent: [scalar, scalar], loops: [[profileCurve]], isVoid, materialParameter
    | materialId, subcategory, visibilityParameter, visibleAt: [coarse, medium, fine], visibleInPlan}`.
    For axis `z` the profile is (x, y), for `y` it is (x, z) and for `x` it is (y, z). A profile curve is
    `{type: line|arc|circle, start, end, mid, center, radius}` with scalar coordinates.
  - `{"kind": "mesh", positions, indices, sourceKind}` for blends, revolves, sweeps, nested families and extrusions
    not aligned with the family axes.
- **planLines:** `{curve: profileCurve (x, y), subcategory, visibleAt}`.
- **opening:** `{xMin, xMax, zMin, zMax}` scalars. If it is missing, Arcus derives the opening from the Left/Right/
  Bottom/Top reference planes, then from Width/Height, then from the solids' extents.

**Mapping to Arcus families.** An Arcus family solid is an extrusion of an XY profile between two Z bounds.

- Axis-`z` extrusions map **exactly**. Parametric vertices, plane-bound coordinates and circles (a single `circle`
  curve, or arcs that close a full turn with a shared center) all stay parametric.
- Axis-`x`/`y` extrusions map exactly when their profile is an axis-aligned rectangle. That covers panels, frames and
  heads, the usual door and window parts.
- Other vertical profiles and `mesh` geometry are replaced by a box of the same extents. The report counts these as
  approximated. With `unsupportedFamilyGeometry = .skip` they are left out instead. Approximated voids are always
  skipped.
- Holes in profiles are filled, with a warning.
- A solid with a fixed material (no material parameter) gets a synthesized type material parameter
  `Material: <name>`.
- Doors and windows exported without geometry get a simple parametric panel driven by Width/Height, so they stay
  native and resizable.

## Direct RVT/RFA import with the ODA BimRv SDK

> **Status: unverified.** `ODABimRvProvider` (Swift, compiled only under `#if ARCUS_HAS_ODA_BIMRV`) and the C API
> `Tools/RevitBridge/BimRvBridge/include/ArcusBimRvBridge.h` have been type-checked and compiled against a stub on
> the development machine. The C++ implementation (`ArcusBimRvBridge.cpp`) is a **sketch**. Its SDK calls are
> described in comments, and it returns "not completed" until someone with a licensed SDK implements them. No SDK
> headers or documentation are in this repository.

Design: the bridge opens the Revit file read-only with the SDK and writes an Arcus Exchange translation to a private
temporary file. `ArcusExchangeImporter` then imports it. Both routes share one mapping, one set of limits and one
report.

### Package.swift changes (for the lead)

Mirror the DWG gating. Add next to the ODA DWG section:

```swift
// Revit: direct .rvt/.rfa import needs the licensed ODA BimRv SDK (see Docs/RevitInterop.md). Without it Revit files can
// still be inspected (preview, release) and imported through the Arcus Bridge add-in (.arcusx) or IFC.
let bimRvDir = env["ARCUS_ODA_BIMRV_SDK_DIR"].flatMap { $0.isEmpty ? nil : $0 }
let requireRevit = env["ARCUS_REQUIRE_REVIT"] == "1"

if requireRevit && bimRvDir == nil {
    fatalError("""

    ─────────────────────────────────────────────────────────────────────────
    Arcus: ARCUS_REQUIRE_REVIT=1 but ARCUS_ODA_BIMRV_SDK_DIR is not set.
    Direct .rvt/.rfa import requires a licensed ODA BimRv SDK build for macOS arm64.
    See Docs/RevitInterop.md for setup. Arcus never compiles fake Revit support.
    ─────────────────────────────────────────────────────────────────────────
    """)
}
if let bimRvDir, !FileManager.default.fileExists(atPath: bimRvDir + "/Kernel/Include") {
    fatalError("""

    Arcus: ARCUS_ODA_BIMRV_SDK_DIR=\(bimRvDir) does not look like an ODA SDK
    (missing Kernel/Include). See Docs/RevitInterop.md.
    """)
}

var revitDependencies: [Target.Dependency] = ["ArcusGeometry", "ArcusCalc", "ArcusDomain"]
var revitSwiftSettings = strictNoImports
if let bimRvDir {
    // UNVERIFIED layout; adjust to your SDK release. Set ARCUS_ODA_BIMRV_LIB_DIR to the folder holding the SDK libraries.
    let libDirs = env["ARCUS_ODA_BIMRV_LIB_DIR"].map { [$0] }
        ?? ["\(bimRvDir)/lib/macOsX_arm64_15.0dll", "\(bimRvDir)/lib/macOsX_arm64_15.0"]
    revitDependencies.append("ArcusBimRvBridge")
    revitSwiftSettings.append(.define("ARCUS_HAS_ODA_BIMRV"))
    extraTargets.append(
        .target(
            name: "ArcusBimRvBridge",
            path: "Tools/RevitBridge/BimRvBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-I\(bimRvDir)/Kernel/Include",
                    "-I\(bimRvDir)/Kernel/Extensions/ExServices",
                    "-I\(bimRvDir)/BimRv/Include",
                    "-I\(bimRvDir)/BimRv/Extensions/ExServices",
                    "-std=c++17",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags(libDirs.map { "-L\($0)" }),
                // Add the libraries your SDK's BimRv samples link (names differ between releases).
                .linkedLibrary("c++"), .linkedFramework("CoreFoundation"),
            ]
        )
    )
}
```

Then change the `ArcusRevit` target to use them:

```swift
.target(
    name: "ArcusRevit",
    dependencies: revitDependencies,
    path: "Arcus/Infrastructure/Exchange/Revit",
    swiftSettings: revitSwiftSettings
),
```

If the DWG and BimRv SDKs share one ODA Kernel installation, link the Kernel libraries (`TD_Root`, `TD_Alloc`, …)
only once. Put a local, **uncommitted** `ArcusBimRvSDKIncludes.h` next to `ArcusBimRvBridge.cpp` that includes the
SDK headers your release needs. The bridge detects it with `__has_include`.

### Verifying a BimRv-enabled build

1. Build with `ARCUS_ODA_BIMRV_SDK_DIR` (and `ARCUS_REQUIRE_REVIT=1` for release builds). Run
   `swift test --filter RevitTests`. All tests must still pass; `currentProviderIsTruthful` checks that an SDK
   provider that fails to initialize reports itself as unavailable, with the working routes in its message.
2. Implement the `BimRv:` sections of `ArcusBimRvBridge.cpp` against the SDK documentation.
3. With your **own** Revit files (never commit them), compare a direct import with the Arcus Bridge export of the
   same model: element counts per kind, wall types and layers, door/window positions, family parameters.
4. Only after that, remove the "unverified" notes here and in the sources.

## Limitations

- **Add-in unverified.** The Arcus Bridge C# source has never been compiled or run (no Revit or .NET on the
  development machine). The spots most likely to need fixes are marked `UNVERIFIED` in the source: the roof slope
  units, the reference-plane "Is Reference" mapping, stair shape detection, true-north sign, beam z-justification
  values, and parameter group/data type APIs on older Revit versions.
- **Flexing** captures linear relationships only. Coordinates that depend on parameters through non-linear formulas,
  `if()` or constraints that only hold for some values are exported as numbers for the current type. Arcs whose points
  move with parameters are placed parametrically only through their center/radius (plan lines) or fixed at their
  exported size (profiles). Parameters that cannot be flexed (locked, over-constrained) are reported.
- **Walls:** curtain and stacked walls, and walls with edited elevation profiles, have no native equivalent. Curtain
  and stacked walls become reference meshes (with their panels and mullions). Edited profiles import as rectangular
  walls. Wall attachments to roofs/floors, wall sweeps/reveals and in-place wall joins are not exported.
- **Floors/roofs:** slope arrows are in the schema but the add-in does not yet read them (sloped floors import flat).
  Shape-edited slabs import flat. Extrusion roofs and other roof kinds become meshes.
- **Doors/windows** in curtain walls become meshes. Revit's family origin conventions are kept as exported: Arcus
  derives facing/hand flips from the instance transform, so geometry lands where it was in Revit.
- **Families:** only extrusions map to native solids. Blends, revolves, sweeps and nested families become boxes (or are
  skipped). Voids are kept in the definition, but Arcus does not yet subtract family voids from family solids.
  Family-type parameters, reporting parameters and shared-parameter GUIDs are not carried over. Parameter names stay as
  in Revit, so non-English Width/Height names are kept (the `builtIn` hint lets Arcus synthesize geometry and
  openings).
- **Stairs:** only one-run (straight) and two-run (L/U) stairs map natively, with Arcus's own stair layout. Other
  stairs and legacy sketch stairs become meshes.
- **Rooms:** Arcus recomputes boundaries from its walls. Unplaced or unenclosed rooms are skipped.
- **Reference meshes** are read-only and use the `IFC Reference` category (see Domain gaps). Their size is capped.
- Views, sheets, annotations, schedules, phases, design options, worksets, groups and links are not exported.

### Domain gaps (worked around)

These would improve fidelity. Arcus/Domain was not changed:

1. **Reference geometry category:** meshes use `Category.ifcReference` (displayed "IFC Reference") with
   `ReferenceGeometryData.ifcType = "Revit: <category>"`. A neutral "Imported Geometry" category would label them better.
2. **Family solids:** `FamilySolid` supports only XY-profile extrusions along Z. Arbitrary extrusion directions, profile
   holes and mesh (B-rep) solids would allow exact blends, revolves, sweeps and vertical non-rectangular profiles.
3. **Family voids** are stored but not subtracted in `FamilyInstanceGeometry`.
4. **Fixed materials in families:** `FamilySolid` has only `materialParameter`. The importer synthesizes a type material
   parameter per fixed material.
5. **Walls:** no edited elevation profile import path (`WallData.profile` exists, but the exchange does not fill it
   yet), and no curtain wall or stacked wall system.
6. **Family types as parameter values** (nested family swapping) have no Arcus equivalent.
