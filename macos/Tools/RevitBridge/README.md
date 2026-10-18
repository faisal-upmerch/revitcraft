# Arcus Bridge (Revit add-in)

Arcus Bridge is a Revit add-in that exports a Revit project or family to **Arcus Exchange** (`.arcusx`), an open JSON
format. Arcus imports `.arcusx` files as native, editable elements: walls, floors, roofs, doors, windows, rooms,
families and so on. The add-in uses only Autodesk's **public Revit API** and runs inside your own licensed copy of Revit.
It does not read or write Revit files outside Revit.

> **Status: UNVERIFIED.** This source was written without access to Revit or the .NET SDK and has **never been
> compiled or run**. It follows the public Revit API as documented for Revit 2023–2026, but expect to fix compile
> errors and check the results against real models before you rely on it. See [Verifying](#verifying) below.
> The Arcus side (the importer, the schema and its tests) is verified. Only the add-in is not.

## What it exports

| Revit | Arcus Exchange | In Arcus |
| --- | --- | --- |
| Levels, grids | `levels`, `grids` | Levels (with floor plans), grids |
| Materials | `materials` (class, color, transparency, identity data) | Materials |
| Basic wall, floor, roof and ceiling types | `types` with compound layers (function, material, thickness, core, wrapping) | Compound types |
| Basic walls | `walls`: location line and curve, base/top constraints and offsets, flip, joins, structural, room bounding | Native walls |
| Curtain and stacked walls | `walls` with `mesh` (curtain panels and mullions go to `meshes`) | Reference geometry |
| Floors, ceilings | `floors`, `ceilings`: sketch boundary loops, level and offset | Native floors and ceilings |
| Footprint roofs | `roofs`: footprint loops with per-edge slope and overhang | Native roofs |
| Extrusion and other roofs | `roofs` with `mesh` | Reference geometry |
| Doors and windows in basic walls | `inserts`: host, type, instance transform, instance parameters | Native hosted inserts |
| Furniture, casework, generic models, plumbing fixtures, specialty equipment, parking | `components`: type and transform | Native components |
| Columns, structural columns, beams | `columns`, `beams`, with section sizes on `types` | Native columns and beams |
| Component stairs (1 run, or 2 runs as L/U shapes), railings | `stairs`, `railings` (plus a `mesh`) | Native stairs and railings, or reference geometry |
| Rooms (placed and enclosed) | `rooms`: name, number, level, point, upper limit | Rooms |
| Loadable families used above | `families`: parameters, formulas, types, reference planes, labelled dimensions, extrusions/voids, plan symbols | Loadable families |
| Everything else with 3D geometry (MEP, site, in-place families, masses…) | `meshes`, labelled with the Revit category | Reference geometry |

Families are opened with `Document.EditFamily`. The add-in exports their parameters (with formulas), types, reference
planes and geometry, then closes them without saving. It makes coordinates parametric by **flexing**. It measures every
exported coordinate, changes each length parameter slightly inside a transaction that is always rolled back, measures
again, and writes linear expressions such as `-Width / 2 - Frame Width`. Extrusions whose sketch plane is aligned with
the family axes are exported exactly. Blends, revolves, sweeps, nested families and non-aligned extrusions are exported
as meshes, and Arcus approximates them (see Docs/RevitInterop.md).

## Requirements

- Windows with Autodesk Revit **2025 or later** (.NET 8), or Revit **2023/2024** (.NET Framework 4.8, see below).
- .NET SDK 8 or later (`dotnet --version`).
- Your Revit installation provides `RevitAPI.dll` and `RevitAPIUI.dll`. They are referenced from the install folder,
  **never copied into this repository**, and never shipped with the add-in.

## Build

From `Tools/RevitBridge`:

```bat
REM Revit 2025 (default). Uses C:\Program Files\Autodesk\Revit 2025\RevitAPI.dll
dotnet build -c Release

REM Another Revit 2025+ version, or a non-default install location
dotnet build -c Release -p:RevitVersion=2026
dotnet build -c Release -p:RevitInstallDir="D:\Autodesk\Revit 2025"
```

### Revit 2024 and earlier (.NET Framework 4.8)

Revit 2024 and earlier run add-ins on .NET Framework 4.8:

```bat
dotnet build -c Release -p:TargetFramework=net48 -p:RevitVersion=2024
dotnet build -c Release -p:TargetFramework=net48 -p:RevitVersion=2023
```

- `net48` builds reference the `System.Text.Json` NuGet package. Copy `System.Text.Json.dll` and its dependencies
  (`System.Memory`, `System.Buffers`, `System.Text.Encodings.Web`, `Microsoft.Bcl.AsyncInterfaces`,
  `System.Runtime.CompilerServices.Unsafe`, `System.Threading.Tasks.Extensions`, `System.Numerics.Vectors`) from the
  build output next to `ArcusBridge.dll`.
- `RevitVersion=2023` defines `REVIT2023_OR_EARLIER`. The code then uses `ElementId.IntegerValue` and
  `Definition.ParameterGroup` instead of `ElementId.Value` and `GetGroupTypeId()`.
- Revit 2022 and earlier are not supported. They lack APIs the exporter uses (`ForgeTypeId` data types and
  `BasePoint.GetProjectBasePoint`).

## Install

1. Copy `bin\Release\<framework>\ArcusBridge.dll` (and, for `net48`, the `System.Text.Json` DLLs) to a folder, e.g.
   `%AppData%\Autodesk\Revit\Addins\2025\ArcusBridge\`.
2. Copy `ArcusBridge.addin` to `%AppData%\Autodesk\Revit\Addins\2025\`. Set `<Assembly>` to the full path of
   `ArcusBridge.dll` if it is not next to the manifest.
3. Start Revit. Accept the add-in security prompt ("Always Load" to stop it asking again).

## Use

- **Project:** open the project and choose **Add-Ins ▸ Arcus ▸ Export to Arcus**. Pick where to save the `.arcusx`
  file. A summary lists what was exported, with notes on anything simplified.
- **Family:** open the family in the Family Editor and choose **Add-Ins ▸ Arcus ▸ Export Family to Arcus**.
- In Arcus, import the `.arcusx` file. A project export adds its elements to the open Arcus project. A family export
  loads the family, which can then be saved as a `.arcusfamily`.

Re-exporting the same Revit model and importing again **updates** the elements imported before instead of duplicating
them. Arcus derives each element's identity from the Revit `UniqueId`.

## Verifying

Nothing in this folder has been compiled. Before relying on it:

1. Build it for your Revit version and fix any compile errors against your Revit API version.
2. Export a small test project (two levels, a few basic walls, a door, a window, a floor, a footprint roof, a room) and
   a door family. Validate the output against `arcus-exchange.schema.json` with any JSON Schema validator.
3. Import both into Arcus and compare:
   - wall location lines and exterior sides (`flipped`), wall heights and top constraints;
   - door and window positions, sill heights and facing/hand orientation;
   - roof slopes. `FootPrintRoof.get_SlopeAngle` is treated as rise/run, which is unverified;
   - family parameter expressions produced by flexing, and the "Is Reference" mapping of reference planes (`ELEM_REFERENCE_NAME`);
   - stair shape detection and origin (the run path is assumed to be the run centerline).
4. Items marked `UNVERIFIED` in the source are the first places to check.

## Files

| Path | Purpose |
| --- | --- |
| `ArcusBridge.csproj` | Project file (`net8.0-windows` by default, `net48` optional) |
| `ArcusBridge.addin` | Revit add-in manifest |
| `src/ArcusBridgeApp.cs` | `IExternalApplication`: ribbon panel and command availability |
| `src/Commands.cs` | `Export to Arcus` / `Export Family to Arcus` commands and the save dialog |
| `src/Export/ProjectExporter.cs` | Project export |
| `src/Export/FamilyExporter.cs` | Family export, including flexing |
| `src/Export/Support.cs` | Units, curves, meshes, materials, parameters, JSON output |
| `src/Schema/ExchangeModel.cs` | Data classes **generated** from the JSON Schema (`python3 tools/generate_dtos.py`) |
| `arcus-exchange.schema.json` | JSON Schema of Arcus Exchange 1.0, shared with Arcus |
| `BimRvBridge/` | Unverified C++ sketch for the optional ODA BimRv provider in Arcus (not part of the add-in) |

The schema is the contract. When it changes, regenerate `ExchangeModel.cs` and update
`Arcus/Infrastructure/Exchange/Revit/Exchange/ExchangeSchema.swift` and Docs/RevitInterop.md. The Arcus test
`SchemaConsistencyTests` fails when the Swift types and the JSON Schema disagree.
