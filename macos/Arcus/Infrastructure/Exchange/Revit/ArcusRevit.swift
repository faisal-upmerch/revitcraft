// ArcusRevit: Revit interoperability without reverse engineering. See Docs/RevitInterop.md.
//
// - CFB/CompoundFile.swift          Defensive reader for the open [MS-CFB] container format (stream listing and reading).
// - Inspector/RevitFileInspector    Container facts about .rvt/.rfa/.rte/.rft files: kind, Revit release, PNG preview,
//                                   stream names. Never decodes Revit's proprietary model streams.
// - Exchange/                       Arcus Exchange (.arcusx), an open JSON schema written by the Arcus Bridge Revit
//                                   add-in (Tools/RevitBridge), and its importer that creates native, editable elements,
//                                   types, materials and loadable families.
// - Providers/                      `RevitImportProvider` seam: `UnavailableRevitProvider` (default; explains the working
//                                   routes) and `ODABimRvProvider` (compiled only with the licensed ODA BimRv SDK,
//                                   `ARCUS_HAS_ODA_BIMRV`; unverified).
import Foundation
