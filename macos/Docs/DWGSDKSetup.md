# DWG import: ODA Drawings SDK setup

Arcus reads **DXF** natively (ASCII and binary, R12 through AutoCAD 2018). **DWG** is a proprietary format, and Arcus
contains **no DWG reader of its own**. There are two ways to get DWG files in:

1. **An external converter the user installs** (every build, no licence needed by Arcus): ODA File Converter or LibreDWG's
   `dwg2dxf`, run as a separate program that converts the DWG to DXF on the user's Mac. See
   [DWG without the SDK: external converters](#dwg-without-the-sdk-external-converters).
2. **The licensed ODA Drawings SDK** compiled into a build (the rest of this document).

When neither is available Arcus says so when a user tries to link a DWG file (`UnavailableDWGProvider`), explains both
options, and suggests saving the drawing as DXF instead. It never pretends to read DWG.

## DWG without the SDK: external converters

`Arcus/Infrastructure/Exchange/CAD/ExternalDWGConverter.swift` (`ExternalConverterDWGProvider`). This mirrors the Revit
route in Docs/RevitInterop.md: an openly documented intermediate format (DXF) produced by a separate tool, never a
reverse-engineered reader.

**Supported converters and where Arcus looks for them** (nothing else on disk is searched, and nothing is downloaded):

| Converter | Licence | Detected at | Command line Arcus runs |
| --- | --- | --- | --- |
| **ODA File Converter** (free app, Open Design Alliance) | ODA's own terms, accepted by the user when installing | `/Applications/ODAFileConverter.app`, `~/Applications/ODAFileConverter.app`, and any `ODA…Converter….app` in those folders; the executable is the bundle's `CFBundleExecutable` (normally `Contents/MacOS/ODAFileConverter`) | `ODAFileConverter <in> <out> ACAD2018 DXF 0 1 drawing.dwg` (input folder, output folder, output version, output type, recurse off, audit on, input filter) |
| **LibreDWG `dwg2dxf`** | GNU GPL v3; run as a separate process only, never linked or bundled | `/opt/homebrew/bin/dwg2dxf`, `/usr/local/bin/dwg2dxf`, `/opt/local/bin/dwg2dxf` | `dwg2dxf -y -o <out>/drawing.dxf <in>/drawing.dwg` |

A user can also pick the app bundle, the executable inside it, or `dwg2dxf` in **Arcus ▸ Settings ▸ DWG Converter**
(`Choose…`, `Detect`, `Clear`, a status line, and a switch for automatic use of a detected converter). The choice is stored
in user defaults (`dwg.converterPath`, `dwg.converterAutoDetect`). A chosen path that no longer exists is reported
instead of silently falling back.

**How a conversion runs** (`ExternalDWGConversion.convert`):

1. A private folder `$TMPDIR/Arcus-DWG-<uuid>/` (mode 0700) is created with `in/`, `out/` and `logs/`.
2. The source DWG is **copied** to `in/drawing.dwg`. The user's file is only read, and paths with spaces, non-Latin
   characters or wildcard characters never reach the converter's own argument or filter parsing. The copy is made while
   the security-scoped bookmark of the chosen file is active.
3. The converter runs through `Process` with an argument array (no shell), stdin from `/dev/null`, stdout/stderr to
   files, a timeout (600 s by default) and cancellation. Cancel or timeout sends SIGTERM, then SIGKILL after 2 s.
4. The output folder is searched (recursively, case-insensitive) for a `.dxf`, preferring `drawing.dxf`. No output, an empty
   file or a file that isn't DXF is an error that quotes the converter's exit status, stderr and any `*.err`/`*.log` file it
   wrote (ODA File Converter writes `.err` files for failed audits).
5. The DXF goes through `DXFReader` like any DXF: layers, units, blocks, text and linetypes carry over. The document is
   marked `format == "DWG"`, its version comes from the DWG header (`sniffVersion`), and the import report notes that the
   conversion was done by the named third-party program.
6. The temporary folder is removed. The last two conversions are cached in memory (keyed by path, size, modification date
   and converter), so opening the Link/Import dialog and then placing the drawing runs the converter once.

A **link** records the original `.dwg` (path and security-scoped bookmark), not the temporary DXF. **Reload** converts the
DWG again, so edits made in the CAD application arrive. Progress and cancellation use the normal background-task UI.

**What was verified, and what wasn't.** `Arcus/Tests/CADTests/ExternalDWGConverterTests.swift` drives fake converter
scripts that behave like both command lines: argument building, staging of a source whose path has spaces and non-ASCII
characters, output discovery (case, subfolders), non-zero exit, `.err` logs, empty/non-DXF output, timeout, cancellation,
detection of app bundles and Homebrew tools, Settings resolution, and the link → reload hand-off through `CADLinkService`.
The real ODA File Converter and LibreDWG were **not** available on the development machine, so the exact behaviour of
current releases (exit codes, whether ODA File Converter shows a window when run with arguments, output file naming) is
verified only against their documented command lines. Before relying on it, link a few of your own DWG files with each
tool and compare with the same drawing saved as DXF.

**Known limits.** Fidelity is whatever the converter writes into DXF; LibreDWG in particular does not convert every
object type. ODA File Converter is a GUI application that also accepts command-line arguments; macOS may ask the user to
confirm it the first time it runs (Gatekeeper), which is why the instructions ask users to open it once from Finder.

The rest of this document covers how to build Arcus with the licensed SDK on your own machine.

> **Status: unverified.** The DWG bridge (`Arcus/Infrastructure/Exchange/DWGBridge/`) and the `ODADWGProvider`
> (`Arcus/Infrastructure/Exchange/CAD/DWGProvider.swift`, inside `#if ARCUS_HAS_ODA`) were written against the documented
> ODA Drawings (Teigha) API. They have **not** been compiled against the SDK or run, because the SDK is licensed and was not
> available on the development machine. The Swift half has been type-checked and exercised against a stub of the bridge's
> C API; the C++ half has not been compiled at all. Treat DWG import as unverified until you complete
> [Verifying a DWG-enabled build](#verifying-a-dwg-enabled-build).

## Why the ODA Drawings SDK

- **ODA Drawings SDK** (from the Open Design Alliance, formerly "Teigha Drawings") is a C++ SDK for reading and writing DWG. ODA
  ships builds for macOS, including Apple silicon (arm64). Using it requires an **ODA membership and license**. Check the
  current ODA membership terms for your use (for example, commercial distribution of an app that embeds the SDK).
- **Autodesk RealDWG** is Windows-only according to Autodesk's official system requirements, so it cannot be used for a
  native macOS app.
- Arcus **does not bundle, redistribute or download** the SDK. Every developer or build machine that produces DWG-enabled
  builds needs its own licensed copy. Do not commit SDK files, license keys or activation headers to this repository.

## What the bridge does

`Arcus/Infrastructure/Exchange/DWGBridge/` is a small C++ target with a pure C API (`include/ArcusDWGBridge.h`):

| Function | Purpose |
| --- | --- |
| `arcus_dwg_initialize` | Initializes the SDK once per process (`odInitialize` with `ExSystemServices`/`ExHostAppServices`, plus `odActivate` if your SDK's activation header is on the include path) |
| `arcus_dwg_open` | Opens a DWG read-only (`ExHostAppServices::readFile`) and records the file's version code (e.g. `AC1032`) |
| `arcus_dwg_write_dxf` | Writes an ASCII DXF (AutoCAD 2010, `AC1024`) translation to a private temporary file with `OdDbDatabase::writeFile(…, OdDb::kDxf, …)`. Dimensions without a graphics block are recomputed in memory first. **The source DWG is never written.** |
| `arcus_dwg_enumerate_objects` | Walks every block table record (model space, layouts, blocks) and reports proxy entities (`OdDbProxyEntity`, with the original class name), custom objects and solid-modeling entities, each with its handle and `getGeomExtents` bounds |
| `arcus_dwg_close` / `arcus_dwg_terminate` | Releases the database and the SDK |

`ODADWGProvider.read` then parses the DXF translation with Arcus's own `DXFReader`. That way DWG and DXF go through the same
conversion (layers, blocks and inserts, xrefs, layouts, hatches, dimensions via their `*D` blocks, MTEXT, images). It also
attaches the enumerated extents to proxy and unsupported entities by handle, so they are kept as reference boxes instead of
being dropped. Parsing and conversion run off the main actor, and the call is cancellable between stages.

## Installing the SDK

1. Download the **ODA Drawings SDK for macOS arm64** from the ODA member area. The package name encodes the SDK release,
   platform and toolchain.
2. Extract it **outside this repository**, for example to `~/SDKs/ODA/Drawings-<version>`.
3. Build or locate the SDK's example services (`ExSystemServices` / `ExHostAppServices`). These live in the SDK's
   `Kernel/Extensions/ExServices` and `Drawing/Extensions/ExServices` sources. Depending on the release, they are shipped
   prebuilt in a library (often `TD_ExamplesCommon`) or have to be built with the SDK's CMake project.
4. If your SDK release requires license activation, place the activation header that ODA gives you (`OdActivationInfo`)
   on an include path. The bridge detects it with `__has_include` and calls `odActivate`. **Never commit it.**

## Building Arcus with DWG support

The ODA-specific section of `Package.swift` is active only when `ARCUS_ODA_SDK_DIR` is set:

```sh
export ARCUS_ODA_SDK_DIR=~/SDKs/ODA/Drawings-<version>      # folder that contains Kernel/Include and Drawing/Include
export ARCUS_ODA_LIB_DIR=$ARCUS_ODA_SDK_DIR/lib/<platform folder>   # optional; see below
export ARCUS_REQUIRE_DWG=1                                   # release gate: fail the build if the SDK is missing
swift build -c release
```

- With `ARCUS_REQUIRE_DWG=1` and no `ARCUS_ODA_SDK_DIR`, manifest evaluation stops with an error. It never falls back
  silently, so a release pipeline can't ship a build that claims DWG support but lacks it.
- If `ARCUS_ODA_SDK_DIR` does not contain `Kernel/Include`, the build also stops with an error.
- When the SDK is found, `Package.swift` adds the `ArcusDWGBridge` target, makes `ArcusCAD` depend on it and defines
  `ARCUS_HAS_ODA`, which compiles `ODADWGProvider` and makes `DWGProviders.current` return it.

### Adjusting paths and libraries

Folder and library names differ between SDK releases and toolchains. Rather than trusting the defaults, look at your SDK
and edit **only the ODA section** of `Package.swift`:

- **Headers:** the section adds `Kernel/Include`, `Kernel/Extensions/ExServices`, `Drawing/Include` and
  `Drawing/Extensions/ExServices` under `ARCUS_ODA_SDK_DIR`. If the compiler reports a missing header (for example
  `OdaCommon.h`, `DbDatabase.h`, `ExSystemServices.h`), find it in your SDK and add its folder to the `-I` flags.
- **Libraries:** the section searches `ARCUS_ODA_LIB_DIR` if set. Otherwise it tries two guesses:
  `lib/macOsX_arm64_15.0dll` and `lib/macOsX_arm64_15.0`. Point `ARCUS_ODA_LIB_DIR` at the folder that actually holds
  `libTD_Db.*` in your SDK.
- **Linked library names:** the defaults are `TD_ExamplesCommon`, `TD_Db`, `TD_DbRoot`, `TD_Root`, `TD_Gi`, `TD_Ge`,
  `TD_Alloc` and `c++`. Newer releases split `TD_Db` into several libraries (for example `TD_DbCore`, `TD_DbEntities`,
  `TD_DbIO`). If the linker reports undefined `OdDb…` symbols, add the libraries your SDK's own examples link. The
  `OdaFileConverter` / `OdReadEx` sample build files are the best reference.
- Static SDK builds may also need system frameworks (the section links `CoreFoundation`). If the SDK uses dynamic
  libraries (`…dll` folders), the app bundle must embed them and set an rpath. Follow ODA's redistribution terms.

## Verifying a DWG-enabled build

No DWG files are committed to this repository. Use **your own** DWG files: drawings you produced yourself or have the right
to use for testing, saved in several versions (R14/2000, 2004, 2007, 2010, 2013, 2018).

1. Build with the SDK (above) and run the CAD tests: `swift test --filter CADTests`. The existing DXF tests must still pass.
   `DWGProviderTests.currentProviderWithoutSDKIsUnavailable` checks that the ODA provider is active.
2. Add a local, **uncommitted** test or a small command-line harness that calls
   `DWGProviders.current.read(url, options: .init(), progress: { _ in }, isCancelled: { false })` on each DWG and checks:
   - `doc.version` matches the file (e.g. `AC1032`) and `doc.format == "DWG"`;
   - layer names, colors and on/frozen/locked states match the CAD application;
   - blocks with nested inserts, attributes, MINSERT arrays and xrefs come through, and xref paths are listed in `doc.xrefs`;
   - dimensions appear, including those whose graphics block the bridge had to recompute;
   - hatches with arc and spline edges, MTEXT with formatting, and multileaders render correctly after `CADConverter`;
   - proxy and custom objects are counted in `unsupportedCounts` and, where the SDK reports extents, kept as proxy boxes;
   - layouts (paper space) are listed and importable by name;
   - cancellation (`isCancelled` returning true) stops the read and throws `CancellationError`.
3. Compare the same drawing saved as DXF from the CAD application: `CADConverter.referenceDrawing` results (entity counts
   by type, extents, layer table) should match closely.
4. Link a DWG in the app, reload it after editing it in the CAD application, and check that per-layer visibility and
   placement survive the reload.

Only after these checks pass should the "unverified" notes in the bridge sources and in this document be removed.

## Supported DWG versions

The versions that can be read are determined by the SDK. ODA documents support for DWG files from early AutoCAD releases
through the current **AutoCAD 2018 format (`AC1032`)**, which AutoCAD releases since 2018 still write. Check the release
notes of your SDK version for the exact list. Arcus maps these version codes to names for its import report:
`AC1009` (R11/R12), `AC1012` (R13), `AC1014` (R14), `AC1015` (2000), `AC1018` (2004), `AC1021` (2007), `AC1024` (2010),
`AC1027` (2013) and `AC1032` (2018). `ODADWGProvider.supportedVersions` returns this list, and `sdkVersion` reports the
SDK's own version string at run time.

## Troubleshooting

| Symptom | Likely cause / fix |
| --- | --- |
| "DWG import is not available: Arcus has no DWG reader of its own, and no DWG converter was found…" | Built without `ARCUS_ODA_SDK_DIR` and no external converter installed. Install ODA File Converter or LibreDWG (above), rebuild with the SDK, or save the drawing as DXF. |
| "ODA File Converter did not produce a DXF file…" | The converter rejected the file (message quoted). Open the DWG in its CAD application, audit/recover it, and try again, or save it as DXF. |
| "The DWG converter did not finish within 600 seconds…" | Very large or damaged drawing. Try again, or save as DXF. |
| Build stops: "ARCUS_REQUIRE_DWG=1 but ARCUS_ODA_SDK_DIR is not set" | This is intended. Set `ARCUS_ODA_SDK_DIR`, or unset `ARCUS_REQUIRE_DWG` for a DXF-only build. |
| Build stops: "does not look like an ODA Drawings SDK (missing Kernel/Include)" | `ARCUS_ODA_SDK_DIR` points to the wrong folder; it must contain `Kernel/Include`. |
| `'OdaCommon.h' file not found` or similar | Add the header folder from your SDK to the `-I` flags in the ODA section of `Package.swift`. |
| `ld: library not found for -lTD_…` | Set `ARCUS_ODA_LIB_DIR` or fix the `-L` paths; adjust library names to your SDK release. |
| Undefined symbols `OdDb…`, `odrx…`, `ExSystemServices…` | Missing libraries (split `TD_Db*` libraries, or the ExServices library). Mirror the SDK's sample link lines. |
| "The ODA Drawings SDK could not be initialized: …" at run time | License activation missing or invalid (activation header), or SDK dynamic libraries not found at run time (rpath/bundle). |
| "The DWG file could not be opened: …" | Damaged or password-protected file, or a version newer than the SDK supports. The message comes from the SDK. |
| DWG imports but some objects are boxes | These are proxy or custom objects (e.g. from vertical products) that have no generic geometry. They are listed under "Not converted" in the import report. |
