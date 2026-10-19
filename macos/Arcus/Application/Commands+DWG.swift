import Foundation

// DWG: export views and sheets as DWG through the engine bundled in Arcus.app (Infrastructure/Exchange/CAD/DWGExporter.swift).

extension CommandCatalog {
    /// RevitCraft exports CAD through one "DWG/DXF" command (`Cmd::ExportDxf`, no alias); Arcus keeps DXF and adds DWG.
    static let dwgCommands: [CommandInfo] = [
        CommandInfo(.exportDWG, "Export DWG…", .file, "arrow.up.doc", help: "Exports views and sheets as 2D DWG drawings (AutoCAD 2000 to 2018 formats), one file each.", keywords: ["dwg", "cad", "autocad", "export"]),
    ]
}
