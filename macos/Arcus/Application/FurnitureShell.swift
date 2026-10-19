import Foundation
import ArcusDomain

// FM3: what the shell offers in each mode (Docs/FurnitureMode.md §3, "Mode in the shell"). Pure values, shared by
// the ribbon, the menus, command routing and their tests.

public enum FurnitureShell {
    /// The ribbon tabs of a mode, in order (titles match the UI's `RibbonTab` raw values).
    public static func ribbonTabs(_ kind: DocumentKind) -> [String] {
        switch kind {
        case .project: ["Architecture", "Structure", "Insert", "Annotate", "Analyze", "Massing & Site", "View", "Manage", "Modify"]
        case .furniture: ["Create", "Insert", "Annotate", "Fabricate", "View", "Manage", "Modify"]
        }
    }

    /// The tab a new window of the mode opens on.
    public static func defaultTab(_ kind: DocumentKind) -> String { ribbonTabs(kind)[0] }

    /// Commands that only make sense in Furniture documents (File ▸ New ▸ Furniture works everywhere).
    public static let furnitureOnly: Set<CommandID> = [.furnitureFamilyTypes, .furnitureCategory, .furnitureFlex, .furnitureLoadIntoProject, .furnitureLoadAndClose]

    /// Building, structure, site and analysis commands that a furniture piece has no use for. Furniture has one level
    /// (Ref. Level), as a family does.
    public static let architectureOnly: Set<CommandID> = [
        .wall, .wallArc, .wallRectangle, .wallPickLines, .door, .window, .column, .structuralColumn, .beam, .floor, .floorPickWalls, .ceiling,
        .roofFootprint, .roofPickWalls, .roofExtrusion, .roofSoffit, .stairStraight, .stairL, .stairU, .editStair, .railing, .ramp,
        .room, .roomSeparator, .roomTag, .area, .areaBoundary, .areaTag, .areaPlan, .placeRoomsAutomatically, .placeAreasAutomatically,
        .colorSchemes, .colorFillLegend, .highlightBoundaries, .grid, .gridPickLines, .gridMultiSegment, .level, .connectLevels,
        .propertyLine, .toposurface, .toposurfaceFromFile, .toposurfaceFromImport, .buildingPad, .subregion, .splitSurface, .mergeSurfaces,
        .gradedRegion, .editSurface, .labelContours, .siteSettings, .siteComponent, .parkingComponent, .parkingLayout, .siteLibrary,
        .toposolid, .toposolidFromFile, .toposolidFromImport, .generateToposolid, .subdivideToposolid, .simplifySurface, .excavateToposolid,
        .curtainWall, .curtainGrid, .mullion, .curtainPanel, .wallOpening, .shaftOpening, .faceOpening, .verticalOpening, .dormerOpening,
        .wallSweep, .wallReveal, .slabEdge, .stackedWall, .structuralWall, .structuralFloor, .foundationIsolated, .foundationWall, .foundationSlab,
        .slopeArrow, .alignEaves, .adjustHeight, .adjustOverhang, .verticalColumn, .slantedColumn, .columnsAtGrids, .columnsAtColumns,
        .truss, .brace, .beamSystem, .structuralSettings, .rebar, .areaReinforcement, .pathReinforcement, .fabricArea, .fabricSheet, .rebarCover,
        .rebarCoupler, .couplerOnBarEnd, .couplerBetweenBars, .beamSymbol, .areaReinforcementSymbol, .pathReinforcementSymbol, .rebarSymbol,
        .fabricSymbol, .multiRebarAligned, .multiRebarLinear, .beamAnnotations, .treadNumber, .stairPath, .spanDirection,
        .space, .spaceSeparator, .spaceTag, .showMass, .inPlaceMass, .curtainSystemByFace, .roofByFace, .wallByFace, .floorByFace,
        .locationSettings, .specifyCoordinates, .reportCoordinates, .relocateProject, .rotateTrueNorth, .rotateProjectNorth, .mirrorProject,
        .importGbXML, .exportGbXML, .exportRoomAreaReport, .matchline, .framingElevation,
    ]

    /// Why a command doesn't run in a document of `kind`, or nil.
    public static func disabledReason(_ id: CommandID, kind: DocumentKind) -> String? {
        switch kind {
        case .project where furnitureOnly.contains(id): "Only in Furniture documents."
        case .furniture where architectureOnly.contains(id): id == .level ? "A furniture piece has one level, Ref. Level." : "Only in Architectural projects."
        default: nil
        }
    }

    /// The window subtitle prefix: "Furniture · Casework" (nil for projects).
    public static func modeTitle(_ m: BIMModel) -> String? {
        guard let s = m.furnitureSetup else { return nil }
        return s.category == .casework ? "Furniture · Casework" : "Furniture"
    }
}
