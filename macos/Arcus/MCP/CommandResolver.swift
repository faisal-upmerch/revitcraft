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
                                                  .ungroup, .placeRoomsAutomatically, .tagAll, .modelHealth, .undo, .redo, .joinSolids, .unjoinSolids]

    /// The dedicated tool to prefer over a command (list_commands says so; small models get it right first time).
    public static let toolFor: [CommandID: String] = [
        .wall: "create_walls", .wallRectangle: "create_walls", .door: "place_doors", .window: "place_windows", .floor: "create_floor", .floorPickWalls: "create_floor",
        .ceiling: "create_ceiling", .roofFootprint: "create_roof", .roofPickWalls: "create_roof", .stair: "create_stair", .stairStraight: "add_stair",
        .railing: "add_railing", .room: "place_rooms", .placeRoomsAutomatically: "place_rooms", .component: "place_components", .column: "place_columns",
        .structuralColumn: "place_columns", .beam: "create_beams", .grid: "add_grid", .level: "add_level", .curtainWall: "create_curtain_wall",
        .curtainGrid: "add_curtain_grids", .ramp: "create_ramp", .wallOpening: "create_opening", .shaftOpening: "create_opening", .area: "place_areas",
        .roomSeparator: "add_room_separators", .modelLine: "add_model_lines", .referencePlane: "add_model_lines", .toposolid: "create_toposolid",
        .alignedDimension: "add_dimensions", .linearDimension: "add_dimensions", .tagAll: "add_tags", .tagByCategory: "add_tags", .textNote: "add_text",
        .detailLine: "add_detail_lines", .filledRegion: "add_region", .maskingRegion: "add_region", .detailComponent: "place_detail_components",
        .spotElevation: "add_spot_dimensions", .keynoteElement: "add_keynotes", .revisionCloud: "add_revision_cloud", .legend: "create_legend",
        .floorPlan: "create_views", .section: "create_views", .elevation: "create_views", .callout: "create_views", .threeDView: "set_3d_view",
        .draftingView: "create_views", .duplicateView: "duplicate_view", .newSheet: "create_sheet", .placeView: "place_on_sheet",
        .viewTemplateApply: "apply_view_template", .visibilityGraphics: "set_visibility_graphics", .filtersDialog: "add_view_filter",
        .cropView: "set_view_properties", .viewRange: "set_view_properties", .revisions: "add_revision", .schedule: "create_schedule",
        .exportPDF: "export_pdf", .exportDWG: "export_dwg", .exportDXF: "export_dwg", .exportIFC: "export_ifc", .exportImage: "export_image",
        .exportScheduleCSV: "export_schedule_csv", .move: "move_elements", .copy: "copy_elements", .rotate: "rotate_elements",
        .mirrorPickAxis: "mirror_elements", .mirrorDrawAxis: "mirror_elements", .array: "array_elements", .align: "align_elements",
        .offset: "offset_elements", .trimExtendCorner: "trim_extend", .trimExtendSingle: "trim_extend", .split: "split_element",
        .joinSolids: "join_geometry", .matchType: "change_type", .pin: "pin_elements", .delete: "delete_elements", .createGroup: "group_elements",
        .attachTop: "attach_walls", .flipFacing: "flip_elements", .temporaryHide: "hide_isolate", .temporaryIsolate: "hide_isolate",
        .modelHealth: "model_health", .warnings: "model_health", .projectInfo: "set_project_info",
        .furniturePanel: "add_furniture_parts", .furnitureShelf: "add_furniture_parts", .furnitureBay: "add_bays", .furnitureDoor: "add_fronts",
        .furnitureDrawer: "add_fronts", .furnitureHardware: "add_hardware", .furnitureJoint: "set_joint", .furnitureJointRules: "set_joint_rules",
        .furnitureCheckParts: "check_parts", .furnitureShopDrawings: "create_shop_drawings", .furniturePartList: "fabrication_report",
        .furnitureCNCExport: "export_cnc", .furnitureStockSheets: "set_stock_sheets", .componentPlace: "place_library_component",
        .componentReplace: "replace_components", .componentAssembly: "insert_assembly", .loadFurniture: "load_furniture_piece",
        .feReferencePlane: "add_reference_plane", .feExtrusion: "add_form", .feBlend: "add_form", .feRevolve: "add_form", .feSweep: "add_form",
        .feFamilyTypes: "set_family_type", .feDimension: "add_family_dimension", .feLoadIntoProject: "load_family_into_project", .feFlexTest: "flex_family",
    ]
}
