# DWG fixtures (third party, MIT)

These DWG files are unmodified copies of sample drawings from **ACadSharp** (https://github.com/DomCR/ACadSharp,
`samples/` folder, commit ed5ff1cf4731c0296bb8931a387bd9d7c634122f), © 2021 Albert Domenech, used under the MIT
License in `LICENSE-ACadSharp.txt`. They are test inputs only and are not shipped in Arcus.app.

| File | ACadSharp path | Content |
| --- | --- | --- |
| `acadsharp_export_sample.dwg` | `samples/svg/export_sample.dwg` | AutoCAD 2018; 22 model-space entities on 4 layers, 32 blocks |
| `acadsharp_block_visibility.dwg` | `samples/dynamic-blocks/BLOCKVISIBILITYPARAMETER.dwg` | AutoCAD 2018; dynamic block with a visibility parameter |
| `acadsharp_empty.dwg` | `samples/sample_base/empty.dwg` | AutoCAD 2018; an empty drawing |

DWG files in other versions are made at test time by Arcus's own DWG export (`BundledDWGEngineTests`).
