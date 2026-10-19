# Third-party notices

## Bundled third-party code

The Arcus application, benchmark and tests are original code built with the Swift toolchain and Apple system frameworks.
The Swift package declares no SwiftPM dependencies (`Package.swift` has no `.package(...)` entries) and the `Arcus`
executable links no third-party code. **Two separate helper programs** for DWG ship inside the app bundle
(`Arcus.app/Contents/Helpers/`); Arcus runs them as their own processes and never links them:

### acadrust (in `arcus-dwg`) — MPL-2.0

`arcus-dwg` is Arcus's own small Rust program (`Tools/DWGHelper`) built on **acadrust 0.6.5** by Hakan AK
(https://github.com/hakanaktt/acadrust, https://crates.io/crates/acadrust), used **unmodified** under the
**Mozilla Public License 2.0**. acadrust's source is available from those addresses; Arcus makes no changes to it.
`arcus-dwg` also compiles in acadrust's dependencies (anyhow, bitflags, byteorder, encoding_rs, flate2, indexmap, libc,
memmap2, miniz_oxide, nom, oem_cp, rayon, thiserror and others) under MIT, Apache-2.0, BSD-3-Clause, Zlib, 0BSD,
Unlicense, BSL-1.0 or Unicode-3.0 terms. The full list with every licence text is
`Tools/DWGHelper/THIRD_PARTY_LICENSES.txt`, shipped as `Contents/Resources/ThirdParty/acadrust/THIRD_PARTY_LICENSES.txt`.

### GNU LibreDWG (`dwg2dxf`) — GPLv3 or later

`dwg2dxf` from **GNU LibreDWG 0.14** (https://www.gnu.org/software/libredwg/), © Free Software Foundation, Inc., built
**unmodified** from `libredwg-0.14.tar.xz` (SHA-256 in `Tools/LibreDWG/libredwg.version`) and distributed under the
**GNU General Public License version 3 or later**. It is a separate program that Arcus only executes, to read DWG files
acadrust can't; Arcus does not link it, and no Arcus code is part of it. The licence (`COPYING`) and the **complete
corresponding source** (the exact release tarball) ship next to it in `Contents/Resources/ThirdParty/LibreDWG/`, and the
source is also available from https://ftp.gnu.org/gnu/libredwg/. You may copy, modify and redistribute `dwg2dxf` under the
GPL; the GPL does not extend to Arcus, which is a separate work distributed alongside it. *A legal review of this GPL
aggregation is advisable before Arcus is sold.*

The app uses these system components at run time. They ship with macOS, are covered by Apple's macOS licence, and are not redistributed by Arcus:

- AppKit, SwiftUI, Foundation, CoreGraphics, CoreText, ImageIO, Metal, MetalKit, QuartzCore, CryptoKit, CoreTransferable, Observation (PDF output uses CoreGraphics PDF contexts)
- `libsqlite3` (SQLite is in the public domain) and `libcompression`
- SF Symbols, used for UI icons through `NSImage(systemSymbolName:)` and `Image(systemName:)`, under Apple's SF Symbols terms for apps on Apple platforms. No symbol artwork is copied into the repository.

## Optional, not bundled: ODA Drawings SDK (DWG)

DWG import and linking can be compiled in against the **ODA Drawings SDK** from the Open Design Alliance, and only when a licensed copy is supplied through `ARCUS_ODA_SDK_DIR` (see [Docs/DWGSDKSetup.md](Docs/DWGSDKSetup.md)). The SDK's headers, libraries and activation data are proprietary to the Open Design Alliance and are **not** part of this repository or of the default build. Anyone building a DWG-enabled Arcus needs their own ODA membership and licence and must follow its redistribution terms. Those terms may require notices in this file and in the app's About window.

## Optional, not bundled: external DWG converters

When the bundled engines can't read a drawing, Arcus can also run a converter that **the user installs separately**:
**ODA File Converter** (a free application from the Open Design Alliance, distributed under ODA's own licence terms) or
**LibreDWG's `dwg2dxf`** (free software under the GNU GPL v3). Arcus only detects such a program in the usual install
locations (or at a path the user chooses in Settings) and runs it as a separate process to write a DXF into a private
temporary folder. Nothing from ODA File Converter is bundled; a LibreDWG the user installs is used as is (Arcus's own
LibreDWG copy is described above). The repository contains no binaries of either. Users must accept and follow the respective licence terms
when they install these tools. See [Docs/DWGSDKSetup.md](Docs/DWGSDKSetup.md).

## Formats and trademarks

- IFC (Industry Foundation Classes) is an open standard published by buildingSMART International (ISO 16739). Arcus implements it from the public specification.
- DXF and DWG are file formats associated with Autodesk, Inc. Arcus's DXF reader and writer are original implementations based on the publicly documented DXF reference; DWG is read and written by the open-source engines above. "AutoCAD", "Revit", "RVT" and "RFA" are trademarks of Autodesk, Inc. Arcus is not affiliated with or endorsed by Autodesk, does not read or write RVT or RFA files, and uses no Autodesk code, assets or documentation text.
- Apple, macOS, Metal and SF Symbols are trademarks of Apple Inc.

## Test fixtures and generated content

- IFC and DXF test fixtures were written for this project and are dedicated to the public domain under CC0 1.0 (see the README in each `Fixtures` folder).
- Three DWG test fixtures (`Arcus/Tests/CADTests/Fixtures/dwg/`) are unmodified samples from ACadSharp (https://github.com/DomCR/ACadSharp), © 2021 Albert Domenech, MIT License (`LICENSE-ACadSharp.txt` next to them). They are not shipped in the app.
- The Courtyard House reference project and the stress fixture are generated in code (`Arcus/Domain/Templates/CourtyardHouse.swift`).
- The app icon is original artwork generated by `script/make_icon.swift`.
