# CAD test fixtures

All files in this folder were authored for Arcus's test suite (hand-designed DXF content written by a small
generator script; no third-party drawings). They are dedicated to the public domain under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/).

| File | Purpose |
| --- | --- |
| `r12_plan.dxf` | R12 (AC1009), no `$INSUNITS` (unitless → mm), CRLF line ends, layer states, POLYLINE/VERTEX (bulge, 3D, polyface), mirrored OCS arc, SOLID/TRACE/3DFACE, block insert, paper-space entities |
| `ac1015_imperial_layouts.dxf` | AutoCAD 2000, inches, true colors, lineweights, plot flags, LAYOUT objects with paper-space blocks, IMAGE/IMAGEDEF |
| `ac1027_blocks_annotation.dxf` | AutoCAD 2013, mm, nested/scaled/rotated blocks with attributes, MINSERT array, ellipses, splines, hatches with arc/bulge edges, dimensions with `*D` block, LEADER, MULTILEADER, proxy/custom/ACIS entities |
| `ac1032_unicode_survey.dxf` | AutoCAD 2018, meters, UTF-8 names and text, MTEXT format codes and `\U+` escapes, survey-scale coordinates (500 km easting) |
| `xref_project/` | Parent drawing with a found xref (`xrefs/site_plan.dxf`), a missing xref, path-traversal and absolute xref paths, found/missing images, a circular xref pair |
| `malformed/` | Truncated file, invalid group code, invalid/hostile values, block reference cycles and an exponential block "bomb" |

No DWG files are included; DWG verification requires your own licensed or self-produced files (see `Docs/DWGSDKSetup.md`).
