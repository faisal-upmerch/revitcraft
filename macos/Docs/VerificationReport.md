# Verification report

Date: 2026-09-25. Machine: MacBook Pro (Mac17,8, Apple M5 Pro, 48 GB), macOS 27.0 (26A428), Xcode 27 toolchain (Swift 6.4).
Build verified: Arcus 1.0.0, development build `1.2609251653` (the `VERSION` file is 1.0.0 and `BUILD_NUMBER` is 1; release builds stamp that number).

This report records what was actually run and seen. Anything not verified is listed under **Limitations**.

## DWG engines (2026-10-19)

DWG import, link, open and export through the engines bundled in Arcus.app ([DWGSDKSetup.md](DWGSDKSetup.md)):
`arcus-dwg` (acadrust 0.6.5) and GNU LibreDWG 0.14 `dwg2dxf`, both built on this Mac (arm64, macOS 26 SDK; only
`libSystem`/`libiconv` linked). Not yet checked in the running app: the build was not installed or launched in this pass.

| Check | Result |
|---|---|
| `swift test --filter CADTests` | 145 tests pass, including 14 in `BundledDWGEngineTests` (real engines) |
| `swift test --filter DomainTests` | 901 tests pass |
| Arcus's own export, every version | The Courtyard House ground-floor plan and first sheet, written by `DXFWriter` with AIA layers and exported as DWG 2018, 2013, 2010, 2007, 2004 and 2000, read back with the same entity count, entity types and layer table in every version; a small plan also reads back in LibreDWG |
| Hostile input | 20 kB of random bytes behind an `AC1032` header and a sample cut to a third fail with a plain message; the helper never crashed |
| Corpus | 163 DWG files: ACadSharp `samples/` (22, MIT) and LibreDWG 0.14 `test/test-data` (141), read as untrusted input |
| Build script (dry run of the DWG steps) | Helpers built or reused, copied to `Contents/Helpers`, licences and the LibreDWG source tarball to `Contents/Resources/ThirdParty`, signed inside-out with the Apple Development identity; `codesign --verify --deep --strict` passes and both helpers run from the bundle |

**Corpus by DWG version** (entity counts are model-space entities after Arcus's DXF reader; the round-trip columns
export what acadrust read to each DWG version and read it back with acadrust, counting a pass when no entity is lost):

| DWG version | Files (ACadSharp + LibreDWG) | acadrust read | LibreDWG read | Entities acadrust / LibreDWG | → 2018 | → 2013 | → 2010 | → 2007 | → 2004 | → 2000 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AC1.40, AC2.10 (R1.4, R2.10) | 3 (0 + 3) | 0/3 | 3/3 | 0 / 28 | – | – | – | – | – | – |
| AC1003 (2.6) | 2 (0 + 2) | 0/2 | 2/2 | 0 / 24 | – | – | – | – | – | – |
| AC1004 (R9) | 1 (0 + 1) | 0/1 | 1/1 | 0 / 17 | – | – | – | – | – | – |
| AC1006 (R10) | 2 (0 + 2) | 0/2 | 2/2 | 0 / 18 | – | – | – | – | – | – |
| AC1009 (R11/R12) | 3 (0 + 3) | 2/3 | 3/3 | 27 / 27 | 2/2 | 2/2 | 2/2 | 2/2 | 2/2 | 2/2 |
| AC1012 (R13) | 1 (0 + 1) | 1/1 | 1/1 | 68 / 63 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 | 1/1 |
| AC1014 (R14) | 5 (1 + 4) | 5/5 | 5/5 | 260 / 232 | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 | 5/5 |
| AC1015 (2000) | 25 (1 + 24) | 25/25 | 25/25 | 325 / 319 | 25/25 | 25/25 | 25/25 | 25/25 | 25/25 | 25/25 |
| AC1018 (2004) | 23 (1 + 22) | 23/23 | 23/23 | 283 / 254 | 23/23 | 23/23 | 23/23 | 23/23 | 23/23 | 22/23 |
| AC1021 (2007) | 20 (1 + 19) | 20/20 | 20/20 | 318 / 313 | 20/20 | 20/20 | 20/20 | 20/20 | 20/20 | 19/20 |
| AC1024 (2010) | 20 (1 + 19) | 20/20 | 20/20 | 267 / 262 | 20/20 | 20/20 | 20/20 | 20/20 | 20/20 | 19/20 |
| AC1027 (2013) | 21 (1 + 20) | 21/21 | 21/21 | 478 / 473 | 21/21 | 21/21 | 21/21 | 21/21 | 21/21 | 20/21 |
| AC1032 (2018) | 37 (16 + 21) | 37/37 | 37/37 | 596 / 589 | 37/37 | 37/37 | 37/37 | 37/37 | 37/37 | 35/37 |
| **All** | **163** | **154** | **163** | | **154/154** | **154/154** | **154/154** | **154/154** | **154/154** | **148/154** |

What this shows:

- **Every file was read by at least one engine.** acadrust read all 154 files from R13 to 2018 and 2 of 3 R12 files; it
  rejects R1.4–R10 (`Unsupported CAD version`) and one R12 file, and LibreDWG read all of those, so the fallback order
  matters for old drawings.
- **acadrust usually finds more entities than LibreDWG** (e.g. 163 vs 141–161 in ACadSharp's sample; HELIX and some
  surfaces are missing from LibreDWG's DXF), which supports acadrust as the primary reader.
- **Export: 2018, 2013, 2010, 2007 and 2004 round-tripped every file.** The DWGs Arcus wrote were also read by LibreDWG,
  an independent reader, with the same entity counts LibreDWG gets from the originals.
- **AutoCAD 2000 refused 6 drawings** (ACadSharp's 2004–2018 samples): acadrust can't write *named (colour-book)
  colours* in the 2000 format ("Not implemented: Named color … requires DWG 2004"). The helper then saves nothing and
  Arcus shows the reason. Arcus's own DXF writer never writes named colours (only ACI and true colour), so every DWG that
  File ▸ Export produces writes in 2000 too, as the export test above shows. All six versions are therefore offered,
  with 2018 as the default.

Command used:

```sh
ARCUS_DWG_CORPUS=<ACadSharp>/samples:<libredwg-0.14>/test/test-data ARCUS_DWG_CORPUS_REPORT=/tmp/dwg-corpus.md \
  swift test --filter BundledDWGEngineTests/corpus      # 421 s
```

<details><summary>Per-file results (163 files)</summary>

| File | Version | acadrust | LibreDWG | 2018 DWG | 2013 DWG | 2010 DWG | 2007 DWG | 2004 DWG | 2000 DWG |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| samples/aec_objects/AecObjects.dwg | AC1032 (AutoCAD 2018) | ✓ 0 ent, 7 lay | ✓ 0 ent, 7 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKALIGNMENTPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKBASEPOINTPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKFLIPPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKLINEARPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKLOOKUPPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 4 ent, 1 lay | ✓ 4 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKPOINTPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 3 ent, 1 lay | ✓ 3 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKPOLARPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKROTATIONPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 4 ent, 1 lay | ✓ 4 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKVISIBILITYPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 4 ent, 1 lay | ✓ 4 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/dynamic-blocks/BLOCKXYPARAMETER.dwg | AC1032 (AutoCAD 2018) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/geolocation/geoloc.dwg | AC1032 (AutoCAD 2018) | ✓ 0 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/sample_AC1014.dwg | AC1014 (AutoCAD R14) | ✓ 163 ent, 21 lay | ✓ 142 ent, 21 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 |
| samples/sample_AC1015.dwg | AC1015 (AutoCAD 2000) | ✓ 163 ent, 21 lay | ✓ 161 ent, 21 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 |
| samples/sample_AC1018.dwg | AC1018 (AutoCAD 2004) | ✓ 163 ent, 21 lay | ✓ 141 ent, 21 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✗ The drawing could not be written: Not implemented: Named color on entity 0x99F requires DW |
| samples/sample_AC1021.dwg | AC1021 (AutoCAD 2007) | ✓ 163 ent, 21 lay | ✓ 161 ent, 21 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✗ The drawing could not be written: Not implemented: Named color on entity 0x99F requires DW |
| samples/sample_AC1024.dwg | AC1024 (AutoCAD 2010) | ✓ 163 ent, 19 lay | ✓ 161 ent, 19 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✗ The drawing could not be written: Not implemented: Named color on entity 0x99F requires DW |
| samples/sample_AC1027.dwg | AC1027 (AutoCAD 2013) | ✓ 163 ent, 19 lay | ✓ 161 ent, 19 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✗ The drawing could not be written: Not implemented: Named color on entity 0x99F requires DW |
| samples/sample_AC1032.dwg | AC1032 (AutoCAD 2018) | ✓ 163 ent, 19 lay | ✓ 161 ent, 19 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✗ The drawing could not be written: Not implemented: Named color on entity 0x99F requires DW |
| samples/sample_base/empty.dwg | AC1032 (AutoCAD 2018) | ✓ 0 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| samples/sample_base/sample_base.dwg | AC1032 (AutoCAD 2018) | ✓ 163 ent, 19 lay | ✓ 161 ent, 19 lay | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✓ L161 | ✗ The drawing could not be written: Not implemented: Named color on entity 0x99F requires DW |
| samples/svg/export_sample.dwg | AC1032 (AutoCAD 2018) | ✓ 22 ent, 4 lay | ✓ 22 ent, 4 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Arc.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Cone.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Constraints.dwg | AC1015 (AutoCAD 2000) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/ConstructionLine.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Donut.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Ellipse.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Helix.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 |
| test-data/2000/Leader.dwg | AC1015 (AutoCAD 2000) | ✓ 10 ent, 1 lay | ✓ 10 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Line.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Multiline.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Point.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/PolyLine2D.dwg | AC1015 (AutoCAD 2000) | ✓ 0 ent, 2 lay | ✓ 0 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/PolyLine3D.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Polygon.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Polyline.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/RAY.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/Spline.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/TS1.dwg | AC1015 (AutoCAD 2000) | ✓ 33 ent, 3 lay | ✓ 32 ent, 3 lay | ✓ L32 | ✓ L32 | ✓ L32 | ✓ L32 | ✓ L32 | ✓ L32 |
| test-data/2000/Text.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/circle.dwg | AC1015 (AutoCAD 2000) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/entities-2d.dwg | AC1015 (AutoCAD 2000) | ✓ 13 ent, 2 lay | ✓ 13 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2000/entities-3d.dwg | AC1015 (AutoCAD 2000) | ✓ 14 ent, 2 lay | ✓ 14 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Arc.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Constraints.dwg | AC1018 (AutoCAD 2004) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/ConstructionLine.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Donut.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Ellipse.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/HatchG.dwg | AC1018 (AutoCAD 2004) | ✓ 4 ent, 1 lay | ✓ 4 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Helix.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 |
| test-data/2004/Leader.dwg | AC1018 (AutoCAD 2004) | ✓ 10 ent, 1 lay | ✓ 10 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Line.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Multiline.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Point.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/PolyLine3D.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Polygon.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Polyline.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/RAY.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Spline.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Surface.dwg | AC1018 (AutoCAD 2004) | ✓ 17 ent, 1 lay | ✓ 13 ent, 1 lay | ✓ L13 | ✓ L13 | ✓ L13 | ✓ L13 | ✓ L13 | ✓ L13 |
| test-data/2004/Text.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/Underlay.dwg | AC1018 (AutoCAD 2004) | ✓ 3 ent, 1 lay | ✓ 3 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/circle.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2004/material.dwg | AC1018 (AutoCAD 2004) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/ATMOS-DC22S.dwg | AC1021 (AutoCAD 2007) | ✓ 60 ent, 2 lay | ✓ 60 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Arc.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Constraints.dwg | AC1021 (AutoCAD 2007) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/ConstructionLine.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Donut.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Ellipse.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Helix.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 |
| test-data/2007/Leader.dwg | AC1021 (AutoCAD 2007) | ✓ 10 ent, 1 lay | ✓ 10 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Line.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Multiline.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Point.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/PolyLine3D.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Polygon.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Polyline.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/RAY.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Spline.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/Text.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2007/circle.dwg | AC1021 (AutoCAD 2007) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Arc.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Constraints.dwg | AC1024 (AutoCAD 2010) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/ConstructionLine.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Donut.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Ellipse.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Helix.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 |
| test-data/2010/Leader.dwg | AC1024 (AutoCAD 2010) | ✓ 12 ent, 1 lay | ✓ 12 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Line.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Multiline.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Point.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/PolyLine3D.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Polygon.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Polyline.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/RAY.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Spline.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/Text.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/circle.dwg | AC1024 (AutoCAD 2010) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2010/gh209_1.dwg | AC1024 (AutoCAD 2010) | ✓ 7 ent, 5 lay | ✓ 7 ent, 5 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Arc.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Constraints.dwg | AC1027 (AutoCAD 2013) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/ConstructionLine.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Donut.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Ellipse.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Helix.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 |
| test-data/2013/Leader.dwg | AC1027 (AutoCAD 2013) | ✓ 10 ent, 1 lay | ✓ 10 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Line.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Multiline.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Point.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/PolyLine3D.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Polygon.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Polyline.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/RAY.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Spline.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/Text.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/circle.dwg | AC1027 (AutoCAD 2013) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/gh109_1.dwg | AC1027 (AutoCAD 2013) | ✓ 24 ent, 27 lay | ✓ 24 ent, 27 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2013/gh44-error.dwg | AC1027 (AutoCAD 2013) | ✓ 196 ent, 93 lay | ✓ 196 ent, 93 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Arc.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Constraints.dwg | AC1032 (AutoCAD 2018) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/ConstructionLine.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Donut.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Dynblocks.dwg | AC1032 (AutoCAD 2018) | ✓ 117 ent, 69 lay | ✓ 117 ent, 69 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Ellipse.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Helix.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 0 ent, 1 lay | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 | ✓ L0 |
| test-data/2018/Leader.dwg | AC1032 (AutoCAD 2018) | ✓ 10 ent, 1 lay | ✓ 10 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Line.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/LiveSection1.dwg | AC1032 (AutoCAD 2018) | ✓ 5 ent, 2 lay | ✓ 5 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Multiline.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Point.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/PolyLine3D.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Polygon.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Polyline.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/RAY.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Spline.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/Text.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/2018/circle.dwg | AC1032 (AutoCAD 2018) | ✓ 1 ent, 1 lay | ✓ 1 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/example_2000.dwg | AC1015 (AutoCAD 2000) | ✓ 68 ent, 5 lay | ✓ 66 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/example_2004.dwg | AC1018 (AutoCAD 2004) | ✓ 68 ent, 5 lay | ✓ 66 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/example_2007.dwg | AC1021 (AutoCAD 2007) | ✓ 68 ent, 5 lay | ✓ 66 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/example_2010.dwg | AC1024 (AutoCAD 2010) | ✓ 68 ent, 5 lay | ✓ 66 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/example_2013.dwg | AC1027 (AutoCAD 2013) | ✓ 68 ent, 5 lay | ✓ 66 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/example_2018.dwg | AC1032 (AutoCAD 2018) | ✓ 68 ent, 5 lay | ✓ 66 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/example_r13.dwg | AC1012 (AutoCAD R13) | ✓ 68 ent, 5 lay | ✓ 63 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/example_r14.dwg | AC1014 (AutoCAD R14) | ✓ 68 ent, 5 lay | ✓ 62 ent, 5 lay | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 | ✓ L66 |
| test-data/r1.4/entities.dwg | AC1.40 (Unknown (AC1.40)) | ✗ acadrust could not read this DWG (AC1.40: Unsupported CAD version: "AC1.40"). | ✓ 13 ent, 1 lay | – | – | – | – | – | – |
| test-data/r10/entities.dwg | AC1006 (AutoCAD R10) | ✗ acadrust could not read this DWG (AC1006: Unsupported CAD version: "AC1006"). | ✓ 17 ent, 2 lay | – | – | – | – | – | – |
| test-data/r10/tmp_line.dwg | AC1006 (AutoCAD R10) | ✗ acadrust could not read this DWG (AC1006: Unsupported CAD version: "AC1006"). | ✓ 1 ent, 1 lay | – | – | – | – | – | – |
| test-data/r11/ACEB10.dwg | AC1009 (AutoCAD R11/R12) | ✗ acadrust could not read this DWG (AC1009: Invalid file format: AC1009 SEQEND at 0xa5e9 nam | ✓ 0 ent, 13 lay | – | – | – | – | – | – |
| test-data/r11/entities-2d.dwg | AC1009 (AutoCAD R11/R12) | ✓ 13 ent, 2 lay | ✓ 13 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/r11/entities-3d.dwg | AC1009 (AutoCAD R11/R12) | ✓ 14 ent, 2 lay | ✓ 14 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/r14/Constraints.dwg | AC1014 (AutoCAD R14) | ✓ 2 ent, 1 lay | ✓ 2 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/r14/Leader.dwg | AC1014 (AutoCAD R14) | ✓ 10 ent, 1 lay | ✓ 9 ent, 1 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/r14/v.dwg | AC1014 (AutoCAD R14) | ✓ 17 ent, 5 lay | ✓ 17 ent, 5 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/r2.10/block.dwg | AC2.10 (Unknown (AC2.10)) | ✗ acadrust could not read this DWG (AC2.10: Unsupported CAD version: "AC2.10"). | ✓ 0 ent, 1 lay | – | – | – | – | – | – |
| test-data/r2.10/entities.dwg | AC2.10 (Unknown (AC2.10)) | ✗ acadrust could not read this DWG (AC2.10: Unsupported CAD version: "AC2.10"). | ✓ 15 ent, 1 lay | – | – | – | – | – | – |
| test-data/r2.6/dim.dwg | AC1003 (AutoCAD 2.6) | ✗ acadrust could not read this DWG (AC1003: Unsupported CAD version: "AC1003"). | ✓ 9 ent, 2 lay | – | – | – | – | – | – |
| test-data/r2.6/entities.dwg | AC1003 (AutoCAD 2.6) | ✗ acadrust could not read this DWG (AC1003: Unsupported CAD version: "AC1003"). | ✓ 15 ent, 2 lay | – | – | – | – | – | – |
| test-data/r9/entities.dwg | AC1004 (AutoCAD R9) | ✗ acadrust could not read this DWG (AC1004: Unsupported CAD version: "AC1004"). | ✓ 17 ent, 2 lay | – | – | – | – | – | – |
| test-data/sample_2000.dwg | AC1015 (AutoCAD 2000) | ✓ 6 ent, 2 lay | ✓ 6 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| test-data/sample_2018.dwg | AC1032 (AutoCAD 2018) | ✓ 6 ent, 2 lay | ✓ 6 ent, 2 lay | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

</details>

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

- **DWG:** read and written by the bundled acadrust and LibreDWG engines (see the DWG section above; not yet exercised in the running app). AutoCAD 2000 export refuses drawings with named colours, which Arcus's own writer never produces. LibreDWG has a time limit but no memory cap. The optional ODA SDK bridge (`Arcus/Infrastructure/Exchange/DWGBridge`) has still **never been compiled or run**.
- **RVT/RFA:** not read directly and not claimed. The Arcus Bridge add-in (C#, `Tools/RevitBridge`) has **never been compiled or run**: this Mac has no .NET SDK and no Revit. Its importer side is tested with hand-written `.arcusx` fixtures only. The ODA BimRv bridge is an unverified sketch whose SDK calls are TODOs. See [RevitInterop.md](RevitInterop.md) for the parts marked UNVERIFIED.
- **IFC:** architectural subset (IFC2x3 CV 2.0 and IFC4 RV). Unsupported entities import as reference geometry. Round trips are exact for Arcus-authored models; files from other tools were tested only with the hand-written fixtures in `Arcus/Tests/IFCTests/Fixtures`.
- **Geometry:** roofs on non-convex footprints use a documented approximation. Hidden-line views do not compute intersection lines between separate solids. Family forms are extrusions, sweeps, blends and revolves; only void extrusions cut solids (no general mesh booleans).
- **Scope:** no worksharing or multi-user editing, rendering or materials beyond flat colours and patterns, MEP, structural analysis, scripting, or cloud features.
- **Platforms:** measured on one M5 Pro Mac. Not run on an 8 GB Mac or on Intel. Memory with GPU scenes is higher than before (see §0) and low-memory behaviour (smaller shadow maps, dropping 3D extras under memory pressure) is unit-tested only.
- **Parity features:** the new canvas controls, curtain walls, ramps, colour schemes and other additions of this pass are covered by unit tests and the standard QA scenarios, but several of their visual details (for example ramp plan symbols, curtain wall elevations, colour fill legends, Family Editor sweep previews) were not inspected screen by screen. They are listed under "Visual checks still owed" in [RevitParity.md](RevitParity.md), which also lists what remains open per package.
- **Distribution:** ad-hoc signed, not sandboxed, not notarized (by request). Release numbering is local (`script/release_local.sh`).
- **UI automation:** end-to-end checks run through the in-app harness (model-level assertions plus screenshots), not XCUITest. Pointer-driven interactions (drags, grips, snapping under the cursor) are exercised through the tool APIs with synthetic inputs, not through real mouse events, and no scripted mouse session was recorded.
