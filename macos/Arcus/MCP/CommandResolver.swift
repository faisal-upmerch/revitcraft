import Foundation
import ArcusApplication

// AITOOLS: commands by name for run_command: id, title or alias, each with its risk, and the commands file mode runs
// headless.

public enum CommandResolver {
    /// A command by raw id ("tagAll"), title ("Tag All", case-insensitive, "…" ignored) or typed alias ("TG").
    public static func resolve(_ s: String) -> CommandID? {
        if let id = CommandID(rawValue: s) { return id }
        let k = s.lowercased().replacingOccurrences(of: "…", with: "").trimmingCharacters(in: .whitespaces)
        if let i = CommandCatalog.all.first(where: { $0.title.lowercased().replacingOccurrences(of: "…", with: "") == k }) { return i.id }
        if let i = CommandCatalog.all.first(where: { $0.aliases.contains { $0.lowercased() == k } }) { return i.id }
        return CommandID.allCases.first { $0.rawValue.lowercased() == k.replacingOccurrences(of: " ", with: "") }
    }

    /// What running the command can change.
    public static func risk(_ id: CommandID) -> ToolRisk {
        let file: Set<CommandID> = [.save, .saveAs, .newProject, .openProject, .closeDocument, .revert, .exportIFC, .exportPDF, .exportDXF, .exportDWG,
                                    .exportScheduleCSV, .exportImage, .print, .duplicateDocument, .saveAsTemplate, .exportRecoveryCopy, .importIFC, .importDWG,
                                    .linkDWG, .importRevit, .exportSTL, .exportGbXML, .exportOBJ, .furnitureCNCExport, .saveAsFurnitureTemplate]
        let destructive: Set<CommandID> = [.delete, .undo, .cut, .purgeUnused, .fePurgeUnused, .ungroup, .demolish]
        let projectWide: Set<CommandID> = [.projectUnits, .projectInfo, .projectParameters, .sharedParameters, .phases, .locationSettings, .objectStyles,
                                           .lineStyles, .lineWeights, .linePatterns, .fillPatterns, .materials, .globalParameters, .structuralSettings,
                                           .viewTemplatesManage, .relocateProject, .rotateTrueNorth, .rotateProjectNorth, .mirrorProject, .transferProjectStandards,
                                           .loadStandardTypes, .furnitureJointRules, .furnitureStockSheets, .componentUpdate]
        if file.contains(id) { return .file }
        if destructive.contains(id) { return .destructive }
        if projectWide.contains(id) { return .projectWide }
        return CommandCatalog.info(id).group == .file ? .file : .edit
    }

    /// Commands file mode runs without a window (run_command's headless set).
    public static let headless: Set<CommandID> = [.delete, .pin, .unpin, .flipFacing, .flipHand, .flipWall, .selectAll, .zoomExtents, .detachTop,
                                                  .ungroup, .placeRoomsAutomatically, .tagAll, .modelHealth, .purgeUnused, .undo, .redo, .joinSolids, .unjoinSolids]
}
