import Foundation

/// Stable identifiers for every user command. Menus, the Command Deck, command search, keyboard aliases and
/// context menus all route through these.
public enum CommandID: String, CaseIterable, Sendable, Codable {
    // Modify / select
    case modify, selectAll, selectAllInstancesInView, selectAllInstancesInProject, selectByCategory, filterSelection
    case move, copy, rotate, mirrorPickAxis, mirrorDrawAxis, array, align, offset, trimExtendCorner, trimExtendSingle, trimExtendMultiple
    case split, pin, unpin, delete, matchType, paint, removePaint, joinGeometry, unjoinGeometry
    case createGroup, ungroup, editGroup, finishEditGroup, flipFacing, flipHand, flipWall, attachTop, detachTop
    case editProfile, resetProfile, editBoundary, finishSketch, cancelSketch, pickHost, typeProperties
    // Build
    case wall, wallArc, wallRectangle, wallPickLines, door, window, component, column, structuralColumn, beam, floor, floorPickWalls, ceiling
    case roofFootprint, roofPickWalls, stairStraight, stairL, stairU, railing, room, roomSeparator, area, areaBoundary, modelLine
    case grid, level, referencePlane, propertyLine, toposurface, buildingPad
    // Annotate
    case alignedDimension, linearDimension, angularDimension, radialDimension, diameterDimension, arcLengthDimension
    case spotElevation, spotCoordinate, spotSlope, detailLine, filledRegion, maskingRegion, detailComponent, insulation
    case textNote, tagByCategory, tagAll, roomTag, symbol, revisionCloud, northArrow
    // Document / view
    case floorPlan, ceilingPlan, structuralPlan, section, elevation, callout, draftingView, legend, threeDView, schedule, materialTakeoff
    case sheetList, revisionSchedule, newSheet, placeView, duplicateView, duplicateViewWithDetailing, duplicateDependent, renameView
    case viewTemplateApply, visibilityGraphics, viewRange, cropView, toggleCropVisible, sectionBox, thinLines
    case temporaryHide, temporaryIsolate, temporaryHideCategory, temporaryIsolateCategory, resetTemporary, revealHidden, hideInView, unhideInView
    case zoomExtents, zoomRegion, zoomIn, zoomOut, zoomOutTwice, zoomSheetSize, previousPanZoom, nextPanZoom, previousView, closeHiddenViews, saveOrientation, detailCoarse, detailMedium, detailFine
    case visualStyleWireframe, visualStyleHidden, visualStyleShaded, visualStyleConsistent, visualStyleTransparent
    // Manage
    case snapSettings, snapsOff, snapEndpoint, snapMidpoint, snapIntersection, snapNearest, snapCenter, snapPerpendicular, snapTangent, snapQuadrant
    case projectInfo, projectUnits, projectParameters, sharedParameters, materials, lineStyles, phases, designOptions
    case revisions, locationSettings, familyEditor, newFamily, loadFamily, reloadFamily, typeCatalog, purgeUnused, modelHealth, diagnostics
    case linkDWG, importDWG, linkDXF, importDXF, manageLinks, reloadLink, unloadLink, convertLinkToDrafting, importIFC, linkPDF, linkImage
    case importRevit
    case exportIFC, exportPDF, exportDXF, exportScheduleCSV, importScheduleCSV, print
    // File
    case home, newProject, openProject, save, saveAs, duplicateDocument, revert, closeDocument, exportRecoveryCopy
    // App
    case commandSearch, preferences, workspaceBIMFamiliar, workspaceMacSpacious, resetWorkspace, toggleNavigator, toggleProperties
    case keyboardShortcuts, onboarding, about, undo, redo, cut, copyClipboard, paste, pasteAlignedSameLevel, pasteAlignedSelectedLevels, pasteAlignedCurrentView
    case selectPrevious, editWitnessLines
    case curtainWall, curtainGrid, mullion, curtainPanel, wallOpening, shaftOpening
    case ramp, roofExtrusion, editStair, modifySubElements, addShapePoint, resetShape, attachWallsToHost, joinSolids, unjoinSolids
    case createSimilar, measureBetween, measureAlong, demolish, arrayNumber, scale
    case selectionBox, overrideGraphicsElement, activateViewport, deactivateViewport, cameraView, scopeBox, gridPickLines
    case showProjectBasePoint, showSurveyPoint
    case placeRoomsAutomatically, placeAreasAutomatically, colorSchemes, colorFillLegend, areaPlan
    case saveAsTemplate
    // W2-CAM: 3D navigation and cameras
    case view3DFront, view3DBack, view3DLeft, view3DRight, view3DTop, view3DBottom, view3DToggleProjection, view3DFrameSelected, view3DFly
    case viewThroughCamera, alignCameraToView, lockCameraToView, createCameraFromView
    case loadStandardTypes // W2-TYPES
    case siteSettings, toposurfaceFromFile, toposurfaceFromImport, subregion, splitSurface, mergeSurfaces, gradedRegion, editSurface, labelContours // W2-DWG
    case siteComponent, parkingComponent, parkingLayout, wallSweep, slabEdge, roofSoffit // W2-DWG
    case componentLibrary, siteLibrary // W2-LIB
    case snapWorkPlaneGrid, snapPoints, snapRemote, snapClose, snapOverrideOff, repeatLastCommand, zoomAllToFit, viewProperties // BL-KEYS
    case findReferringViews, hideCategoryInView, hideByFilter, overrideByCategory, overrideByFilter // BL-KEYS
    case filtersDialog, viewTemplatesManage, viewTemplateCreate, viewTemplateApplyProperties, temporaryViewProperties, revealConstraints, userInterface, toggleStatusBar, toggleNavigationBar, objectStyles, warnings, selectByID, idsOfSelection, additionalSettings, lineWeights, linePatterns, fillPatterns, arrowheads, temporaryDimensionSettings, cutGeometry, uncutGeometry, switchJoinOrder, foundationIsolated, foundationWall, foundationSlab, structuralWall, structuralFloor // BL-VG
    case toposolid, toposolidFromFile, toposolidFromImport, generateToposolid, subdivideToposolid, simplifySurface, excavateToposolid // BL-SITE
    case repeatingDetailComponent, legendComponent, detailGroupPlace, detailGroupCreate, checkSpelling, findReplace, multiCategoryTag, materialTag, areaTag, viewReference, keynoteElement, keynoteMaterial, keynoteUser, treadNumber, beamAnnotations, scaleBar, spanDirection, stairPath, addTextLeader, removeTextLeader // W2-ANNOT
    case linkCAD, importCAD, exportImage, newTitleBlock, newAnnotationSymbol // BL-SCHED
    case scheduleProperties, scheduleInsertColumn, scheduleDeleteColumn, scheduleHideColumn, scheduleUnhideAllColumns, scheduleResizeColumn // BL-SCHED
    case scheduleInsertRow, scheduleDeleteRow, scheduleMergeHeaders, scheduleGroupHeaders, scheduleUngroupHeaders, scheduleAppearance // BL-SCHED
    case scheduleFormatUnit, scheduleCalculatedField, highlightInModel // BL-SCHED

    // RevitCraft port feature batches (Docs/RevitCraftPort.md §5): each adds its cases right after its marker.
    // F1 commands:
    case modelText, wallReveal, faceOpening, verticalOpening, dormerOpening, placeModelGroup, highlightBoundaries


    // F2 commands:
    case stackedWall, gridMultiSegment, workPlaneSet, workPlaneShow, workPlaneViewer, connectLevels, sketchBoundaryLine, slopeArrow, alignEaves, adjustHeight, adjustOverhang, verticalColumn, slantedColumn, columnsAtGrids, columnsAtColumns, multipleFinish, multipleCancel


    // F34 commands:
    case truss, brace, beamSystem, structuralSettings, rebar, areaReinforcement, pathReinforcement, fabricArea, fabricSheet, rebarCover, rebarCoupler, couplerOnBarEnd, couplerBetweenBars, beamSymbol, areaReinforcementSymbol, pathReinforcementSymbol, rebarSymbol, fabricSymbol, multiRebarAligned, multiRebarLinear

    // F5 commands:
    case space, spaceSeparator, spaceTag, showMass, inPlaceMass, curtainSystemByFace, roofByFace, wallByFace, floorByFace, modelInPlace


    // F67 commands:
    case linkModel, linkIFC, linkTopography, dwfMarkup, placeDecal, decalTypes, pointCloud, coordinationModel, importGbXML, importPDF, importImage, loadAsGroup, insertViewsFromFile, insert2DElementsFromFile, transferProjectStandards


    // F810 commands:
    case showHiddenLines, removeHiddenLines, cutProfile, framingElevation, calloutSketch, walkthrough, finishWalkthrough, walkthroughPreviousFrame, walkthroughNextFrame, walkthroughPlay, walkthroughExport, titleBlock, guideGrid, matchline, switchWindows, tabViews, tileViews, canvasTheme, navigationWheel, render, renderGallery, exportOBJ


    // F11 commands:
    case globalParameters, specifyCoordinates, reportCoordinates, relocateProject, rotateTrueNorth, rotateProjectNorth, mirrorProject // F11
    case addToSet, pickToEdit, startingView, saveSelection, loadSelection, editSelection, selectJoinedElements // F11
    case scheduleCombineParameters, scheduleInsertHeaderRow, scheduleInsertRowAbove, scheduleInsertRowBelow, scheduleResizeRow // F12
    case scheduleInsertImage, scheduleClearCell, scheduleFreezeHeader, scheduleShading, scheduleBorders, scheduleResetAppearance, scheduleFont // F12
    case scheduleAlignLeft, scheduleAlignCenter, scheduleAlignRight, scheduleAlignTop, scheduleAlignMiddle, scheduleAlignBottom, scheduleSplitAndPlace // F12
    case keynoteLegend, keynotingSettings // F12
    case exportDWFx, exportSTL, exportGbXML, exportRoomAreaReport, exportFamilyTypes, printPreview, printSetup // F13


    // F1415 commands:
    case feExtrusion, feBlend, feRevolve, feSweep, feSweptBlend, feVoidExtrusion, feVoidBlend, feVoidRevolve, feVoidSweep, feModelLine, feComponent, feModelText, feOpening, feControl, feReferenceLine, feReferencePlane, feDimension, feSymbolicLine, feFamilyTypes, feFamilyCategory, feLoadIntoProject, feLoadAndClose, feFinishSketch, feCancelSketch, feDefault3D, feControlSingleVertical, feControlDoubleVertical, feControlSingleHorizontal, feControlDoubleHorizontal, feFilledRegion, feMaskingRegion, feText, feWorkPlaneSet, feWorkPlaneShow, feLoadNestedFamily, fePurgeUnused, feFlexTest, feSaveFamilyAs // F1415

    // DWG commands:
    case exportDWG // DWG

    // HOME commands:

    // FES commands:

    // FM3 commands:
    case furnitureFamilyTypes, furnitureCategory, furnitureFlex, furnitureLoadIntoProject, furnitureLoadAndClose, newFurniture // FM3

    // FM4 commands:
    case furniturePanel, furnitureShelf, furnitureTop, furnitureBack, furnitureDivider, furnitureLeg, furnitureLegsAtCorners, furnitureRail, furnitureSlats, furniturePlinth, furnitureEdgeProfile, furnitureGroove, furnitureEditProfile, furnitureResetProfile, furnitureAttach, furnitureDetach, furniturePanelOpening, furnitureFlipPanel, furnitureExtrusion, furnitureBlend, furnitureRevolve, furnitureSweep, furnitureSweptBlend, furnitureCushion, furnitureVoidExtrusion, furnitureVoidBlend, furnitureVoidRevolve, furnitureVoidSweep, furnitureVoidSweptBlend // FM4

    // FM5 commands:
    case furnitureBay, furnitureBaySeparator, furnitureBayDivide, furnitureBayTag, furnitureDoor, furnitureDrawer, furnitureFlap, furnitureHardware, furnitureFlipHinge, furniturePickNewHost, furnitureSelectHardware, furnitureRemoveDivide // FM5

    // FM6 commands:
    case furnitureJoint, furnitureJointRules, furnitureAllowJoin, furnitureDisallowJoin // FM6

    // FM7 commands:
    case furniturePartList, furnitureHardwareSchedule, furnitureMaterialTakeoff, furnitureEdgeBanding, furnitureCost, furnitureStockSheets, furnitureHardwareCatalog, furnitureNesting, furnitureCNCExport, furnitureCheckParts, furnitureShopDrawings // FM7

    // FM8 commands:
    case loadFurniture, saveAsFurnitureTemplate // FM8

    // FM9 commands:

    // STAIR commands:
    case stair, stairComponentRun, stairComponentLanding, stairComponentSupport, stairRunStraight, stairRunFullStepSpiral
    case stairRunCenterEndsSpiral, stairRunLWinder, stairRunUWinder, stairRunSketch, stairLandingPickRuns, stairLandingSketch
    case stairSupportPickEdges, stairSketchBoundary, stairSketchRiser, stairSketchPath, stairRailingSettings, stairFlip
    case stairRailingEditPath, stairRailingReset, shaftPickStair

    // POLISH commands:

    // FMG1 commands:
    case furnitureBlendEditTop, furnitureBlendEditBase

    // FMG2 commands:

    // FMG3 commands:

}

public enum CommandGroup: String, CaseIterable, Sendable {
    case modify = "Modify", build = "Architecture", structure = "Structure", insert = "Insert", annotate = "Annotate"
    case view = "View", manage = "Manage", file = "File", app = "Arcus"
}

/// Static description of a command.
public struct CommandInfo: Sendable, Hashable, Identifiable {
    public var id: CommandID
    public var title: String
    public var group: CommandGroup
    public var symbol: String
    /// Keyboard equivalent shown in menus (e.g. "⌘S").
    public var shortcut: String?
    /// Two/three letter typed aliases (default set; users can remap).
    public var aliases: [String]
    public var help: String
    public var keywords: [String]

    public init(_ id: CommandID, _ title: String, _ group: CommandGroup, _ symbol: String, shortcut: String? = nil, aliases: [String] = [], help: String, keywords: [String] = []) {
        self.id = id; self.title = title; self.group = group; self.symbol = symbol; self.shortcut = shortcut
        self.aliases = aliases; self.help = help; self.keywords = keywords
    }
}

public enum CommandCatalog {
    public static let all: [CommandInfo] = coreCommands + portCommands
    /// Commands of the RevitCraft port feature batches (Commands+F*.swift).
    static let portCommands: [CommandInfo] = f1Commands + f2Commands + f34Commands + f5Commands + f67Commands + f810Commands + f11Commands + f1415Commands + dwgCommands + homeCommands + fesCommands + fm3Commands + fm4Commands + fm5Commands + fm6Commands + fm7Commands + fm8Commands + fm9Commands + stairCommands + polishCommands + fmg1Commands + fmg2Commands + fmg3Commands
    static let coreCommands: [CommandInfo] = [
        // Modify
        CommandInfo(.modify, "Modify", .modify, "cursorarrow", shortcut: "⎋⎋", aliases: ["MD"], help: "Return to selection mode."),
        CommandInfo(.selectAll, "Select All", .modify, "checklist", shortcut: "⌘A", help: "Select the model elements visible in the view (in drafting views and sheets: their detail elements). View markers and datums are left out. An Arcus extension."), // BL-KEYS
        CommandInfo(.selectAllInstancesInView, "Select All Instances: Visible in View", .modify, "square.stack.3d.up", aliases: ["SA"], help: "Select every instance of the selected type visible in the view."), // I3: SA is Visible in View, as in RevitCraft
        CommandInfo(.selectAllInstancesInProject, "Select All Instances: In Entire Project", .modify, "square.stack.3d.up.fill", help: "Select every instance of the selected type in the project."), // BL-KEYS
        CommandInfo(.selectByCategory, "Select by Category…", .modify, "line.3.horizontal.decrease.circle", help: "Select all visible elements of chosen categories."),
        CommandInfo(.filterSelection, "Filter Selection…", .modify, "line.3.horizontal.decrease", help: "Keep only chosen categories in the selection."),
        CommandInfo(.move, "Move", .modify, "arrow.up.and.down.and.arrow.left.and.right", aliases: ["MV"], help: "Move selected elements by picking two points or typing a distance."),
        CommandInfo(.copy, "Copy", .modify, "plus.square.on.square", aliases: ["CO", "CC"], help: "Copy selected elements by picking two points."),
        CommandInfo(.rotate, "Rotate", .modify, "rotate.right", aliases: ["RO"], help: "Rotate selected elements about a center."),
        CommandInfo(.mirrorPickAxis, "Mirror - Pick Axis", .modify, "arrow.left.and.right.righttriangle.left.righttriangle.right", aliases: ["MM"], help: "Mirror selected elements about a picked line."),
        CommandInfo(.mirrorDrawAxis, "Mirror - Draw Axis", .modify, "arrow.left.and.right.righttriangle.left.righttriangle.right.fill", aliases: ["DM"], help: "Mirror selected elements about a drawn line."),
        CommandInfo(.array, "Array", .modify, "square.grid.3x1.below.line.grid.1x2", aliases: ["AR"], help: "Create a linear array of the selection."),
        CommandInfo(.align, "Align", .modify, "align.horizontal.left", aliases: ["AL"], help: "Align elements to a reference; optionally lock the alignment."),
        CommandInfo(.offset, "Offset", .modify, "arrow.right.to.line", aliases: ["OF"], help: "Offset walls or lines by a distance."),
        CommandInfo(.trimExtendCorner, "Trim/Extend to Corner", .modify, "arrow.turn.down.right", aliases: ["TR"], help: "Trim or extend two elements to form a corner."),
        CommandInfo(.trimExtendSingle, "Trim/Extend Single Element", .modify, "arrow.forward.to.line", help: "Trim or extend one element to a boundary."),
        CommandInfo(.trimExtendMultiple, "Trim/Extend Multiple Elements", .modify, "arrow.forward.to.line.compact", help: "Trim or extend several elements to one boundary."),
        CommandInfo(.split, "Split Element", .modify, "scissors", aliases: ["SL"], help: "Split a wall or line at a picked point."),
        CommandInfo(.pin, "Pin", .modify, "pin", aliases: ["PN"], help: "Prevent selected elements from moving."),
        CommandInfo(.unpin, "Unpin", .modify, "pin.slash", aliases: ["UP"], help: "Allow selected elements to move."),
        CommandInfo(.delete, "Delete", .modify, "trash", shortcut: "⌫", aliases: ["DE"], help: "Delete the selection and dependent elements."),
        CommandInfo(.matchType, "Match Type Properties", .modify, "paintbrush.pointed", aliases: ["MA"], help: "Apply the type of a source element to other elements."),
        CommandInfo(.paint, "Paint", .modify, "paintbrush", aliases: ["PT"], help: "Apply a material to an element's surfaces (stored as an element material override)."),
        CommandInfo(.removePaint, "Remove Paint", .modify, "paintbrush.fill", help: "Remove painted material overrides."),
        CommandInfo(.joinGeometry, "Allow Join", .modify, "link", help: "Allow the selected walls to join at their ends."),
        CommandInfo(.unjoinGeometry, "Disallow Join", .modify, "link.badge.plus", help: "Stop the selected walls joining at their ends."),
        CommandInfo(.createGroup, "Create Group", .modify, "square.on.square.dashed", aliases: ["GP"], help: "Group the selected elements."),
        CommandInfo(.ungroup, "Ungroup", .modify, "square.on.square.intersection.dashed", aliases: ["UG"], help: "Dissolve the selected group."),
        CommandInfo(.editGroup, "Edit Group", .modify, "pencil.and.outline", aliases: ["EG"], help: "Edit the members of a group; changes apply to every instance of the group type."),
        CommandInfo(.finishEditGroup, "Finish Group", .modify, "checkmark.circle", help: "Finish editing the group."),
        CommandInfo(.flipFacing, "Flip Facing", .modify, "arrow.up.arrow.down", help: "Flip the facing of doors and windows."),
        CommandInfo(.flipHand, "Flip Hand", .modify, "arrow.left.arrow.right", help: "Flip the hand (hinge side) of doors and windows."),
        CommandInfo(.flipWall, "Flip Wall", .modify, "arrow.left.arrow.right.square", help: "Swap the exterior and interior sides of walls."),
        CommandInfo(.attachTop, "Attach Top/Base", .modify, "arrow.up.to.line", help: "Attach wall tops to a roof or floor."),
        CommandInfo(.detachTop, "Detach Top/Base", .modify, "arrow.up.to.line.compact", help: "Detach wall tops from roofs and floors."),
        CommandInfo(.editProfile, "Edit Profile", .modify, "skew", help: "Edit the elevation profile of a wall."),
        CommandInfo(.resetProfile, "Reset Profile", .modify, "arrow.counterclockwise", help: "Restore a wall's rectangular profile."),
        CommandInfo(.editBoundary, "Edit Boundary", .modify, "square.dashed", help: "Edit the sketch of a floor, ceiling, roof or region."),
        CommandInfo(.finishSketch, "Finish Edit Mode", .modify, "checkmark", shortcut: "↩", help: "Validate and commit the sketch."),
        CommandInfo(.cancelSketch, "Cancel Edit Mode", .modify, "xmark", help: "Discard the sketch and restore the previous state."),
        CommandInfo(.pickHost, "Pick New Host", .modify, "hand.point.up.left", help: "Move a door or window to another wall."),
        // Build
        CommandInfo(.wall, "Wall", .build, "rectangle.split.1x2", aliases: ["WA"], help: "Draw walls with lines; chain by default.", keywords: ["partition"]),
        CommandInfo(.wallArc, "Wall – Arc", .build, "circle.bottomhalf.filled", help: "Draw a curved wall through three points."),
        CommandInfo(.wallRectangle, "Wall – Rectangle", .build, "rectangle", help: "Draw four walls from two corners."),
        CommandInfo(.wallPickLines, "Wall – Pick Lines", .build, "hand.point.up.left.and.text", help: "Create walls on picked lines, grids or CAD geometry."),
        CommandInfo(.door, "Door", .build, "door.left.hand.open", aliases: ["DR"], help: "Place a door in a wall."),
        CommandInfo(.window, "Window", .build, "window.casement", aliases: ["WN"], help: "Place a window in a wall."),
        CommandInfo(.component, "Component", .build, "chair.lounge", aliases: ["CM"], help: "Place furniture, casework, fixtures and generic models."),
        CommandInfo(.column, "Column: Architectural", .build, "square.grid.3x3.middle.filled", help: "Place architectural columns."),
        CommandInfo(.structuralColumn, "Structural Column", .structure, "square.grid.3x3.square", aliases: ["CL"], help: "Place structural columns."),
        CommandInfo(.beam, "Beam", .structure, "line.diagonal", aliases: ["BM"], help: "Draw beams between points or supports."),
        CommandInfo(.floor, "Floor", .build, "square.3.layers.3d.bottom.filled", aliases: ["FL"], help: "Sketch a floor boundary."),
        CommandInfo(.floorPickWalls, "Floor – Pick Walls", .build, "square.3.layers.3d.down.right", help: "Create a floor from the walls enclosing a picked area."),
        CommandInfo(.ceiling, "Ceiling", .build, "square.3.layers.3d.top.filled", help: "Sketch a ceiling or pick a room to fill."),
        CommandInfo(.roofFootprint, "Roof by Footprint", .build, "house", aliases: ["RF"], help: "Sketch a roof footprint with slope-defining edges."),
        CommandInfo(.roofPickWalls, "Roof – Pick Walls", .build, "house.lodge", help: "Create a hip roof over the walls enclosing a picked area."),
        CommandInfo(.stairStraight, "Stair – Straight", .build, "stairs", help: "Place a straight stair by picking start and direction."), // BL-KEYS
        CommandInfo(.stairL, "Stair – L-Shaped", .build, "arrow.turn.up.right", help: "Place an L-shaped stair with a landing."),
        CommandInfo(.stairU, "Stair – U-Shaped", .build, "arrow.uturn.up", help: "Place a U-shaped stair with a landing."),
        CommandInfo(.railing, "Railing", .build, "fence", aliases: ["RA"], help: "Sketch a railing path."),
        CommandInfo(.room, "Room", .build, "square.dashed.inset.filled", aliases: ["RM"], help: "Place rooms in enclosed regions."),
        CommandInfo(.roomSeparator, "Room Separator", .build, "line.diagonal.arrow", aliases: ["RS"], help: "Draw lines that divide rooms without walls."),
        CommandInfo(.area, "Area", .build, "square.dashed", help: "Place areas in an area plan."),
        CommandInfo(.areaBoundary, "Area Boundary", .build, "square.on.square.dashed", help: "Draw area boundary lines."),
        CommandInfo(.modelLine, "Model Line", .build, "line.diagonal", aliases: ["LI"], help: "Draw 3D model lines on the level."),
        CommandInfo(.grid, "Grid", .build, "number", aliases: ["GR"], help: "Draw grid lines; names increment automatically."),
        CommandInfo(.level, "Level", .build, "arrow.up.and.line.horizontal.and.arrow.down", aliases: ["LL"], help: "Add a level (in an elevation or section) with plan views."),
        CommandInfo(.referencePlane, "Reference Plane", .build, "line.diagonal.arrow", aliases: ["RP"], help: "Draw a reference plane."),
        CommandInfo(.propertyLine, "Property Line", .build, "map", help: "Sketch site property lines."),
        CommandInfo(.toposurface, "Toposurface", .build, "mountain.2", help: "Create terrain from picked points and elevations."),
        CommandInfo(.buildingPad, "Building Pad", .build, "rectangle.inset.filled", help: "Sketch a building pad."),
        // Annotate
        CommandInfo(.alignedDimension, "Aligned Dimension", .annotate, "ruler", aliases: ["DI"], help: "Dimension between parallel references or points."),
        CommandInfo(.linearDimension, "Linear Dimension", .annotate, "ruler.fill", help: "Horizontal or vertical dimension between points."),
        CommandInfo(.angularDimension, "Angular Dimension", .annotate, "angle", help: "Measure the angle between two lines."),
        CommandInfo(.radialDimension, "Radial Dimension", .annotate, "circle.dashed", help: "Measure the radius of an arc."),
        CommandInfo(.diameterDimension, "Diameter Dimension", .annotate, "circle.circle", help: "Measure the diameter of an arc or circle."),
        CommandInfo(.arcLengthDimension, "Arc Length Dimension", .annotate, "circle.bottomrighthalf.pattern.checkered", help: "Measure the length of an arc."),
        CommandInfo(.spotElevation, "Spot Elevation", .annotate, "triangle", aliases: ["EL"], help: "Label the elevation of a point."),
        CommandInfo(.spotCoordinate, "Spot Coordinate", .annotate, "location", help: "Label the N/E coordinates of a point."),
        CommandInfo(.spotSlope, "Spot Slope", .annotate, "arrow.down.right", help: "Label the slope of a surface."),
        CommandInfo(.detailLine, "Detail Line", .annotate, "pencil.line", aliases: ["DL"], help: "Draw view-specific lines."),
        CommandInfo(.filledRegion, "Filled Region", .annotate, "square.fill.on.square", help: "Sketch a hatched or filled region."),
        CommandInfo(.maskingRegion, "Masking Region", .annotate, "square.on.square", help: "Sketch a region that hides elements behind it."),
        CommandInfo(.detailComponent, "Detail Component", .annotate, "puzzlepiece", help: "Place 2D detail components."),
        CommandInfo(.insulation, "Insulation", .annotate, "scribble", help: "Draw batt insulation."),
        CommandInfo(.textNote, "Text", .annotate, "textformat", aliases: ["TX"], help: "Place a text note with optional leaders."),
        CommandInfo(.tagByCategory, "Tag by Category", .annotate, "tag", aliases: ["TG"], help: "Tag elements by clicking them."),
        CommandInfo(.tagAll, "Tag All", .annotate, "tag.fill", help: "Tag every untagged element of chosen categories in the view."),
        CommandInfo(.roomTag, "Tag Room", .annotate, "tag.square", aliases: ["RT"], help: "Tag rooms."),
        CommandInfo(.symbol, "Symbol", .annotate, "star.square", help: "Place annotation symbols."),
        CommandInfo(.revisionCloud, "Revision Cloud", .annotate, "cloud", help: "Sketch a revision cloud assigned to a revision."),
        CommandInfo(.northArrow, "North Arrow", .annotate, "location.north.line", help: "Place a north arrow symbol."),
        // Document / View
        CommandInfo(.floorPlan, "Floor Plan", .view, "square.grid.3x3.topleft.filled", help: "Create floor plans for levels."),
        CommandInfo(.ceilingPlan, "Reflected Ceiling Plan", .view, "rectangle.split.3x3", help: "Create reflected ceiling plans."),
        CommandInfo(.structuralPlan, "Structural Plan", .view, "square.grid.3x3.square", help: "Create structural plans."),
        CommandInfo(.section, "Section", .view, "rectangle.split.2x1", help: "Draw a section line; a section view is created."), // BL-KEYS: SX is Snap to Points
        CommandInfo(.elevation, "Elevation", .view, "building.2", aliases: ["EV"], help: "Place an elevation marker; an elevation view is created."),
        CommandInfo(.callout, "Callout", .view, "plus.magnifyingglass", help: "Sketch a callout; an enlarged plan view is created."),
        CommandInfo(.draftingView, "Drafting View", .view, "pencil.and.ruler", help: "Create a view for 2D drafting."),
        CommandInfo(.legend, "Legend", .view, "list.bullet.rectangle", help: "Create a legend view."),
        CommandInfo(.threeDView, "Default 3D View", .view, "cube", aliases: ["3D"], help: "Open the 3D coordination view."),
        CommandInfo(.schedule, "Schedule/Quantities", .view, "tablecells", help: "Create a live schedule of a category."),
        CommandInfo(.materialTakeoff, "Material Takeoff", .view, "tablecells.badge.ellipsis", help: "Schedule material quantities."),
        CommandInfo(.sheetList, "Sheet List", .view, "list.number", help: "Create a sheet list."),
        CommandInfo(.revisionSchedule, "Revision Schedule", .view, "clock.arrow.circlepath", help: "Create a revision schedule."),
        CommandInfo(.newSheet, "Sheet", .view, "doc.richtext", help: "Create a sheet from a title block."),
        CommandInfo(.placeView, "Place View", .view, "rectangle.on.rectangle.angled", help: "Place a view or schedule on the active sheet."),
        CommandInfo(.duplicateView, "Duplicate View", .view, "doc.on.doc", help: "Duplicate the view without annotations."),
        CommandInfo(.duplicateViewWithDetailing, "Duplicate with Detailing", .view, "doc.on.doc.fill", help: "Duplicate the view with its annotations."),
        CommandInfo(.duplicateDependent, "Duplicate as Dependent", .view, "doc.badge.gearshape", help: "Duplicate with a separate crop that follows the parent's settings."),
        CommandInfo(.renameView, "Rename…", .view, "character.cursor.ibeam", shortcut: "F2", help: "Rename the selected view, sheet or schedule."),
        CommandInfo(.viewTemplateApply, "Apply View Template…", .view, "doc.text.below.ecg", help: "Apply a view template's settings."),
        CommandInfo(.visibilityGraphics, "Visibility/Graphics", .view, "eye", aliases: ["VG", "VV"], help: "Category visibility, filters and overrides for the view."),
        CommandInfo(.viewRange, "View Range…", .view, "arrow.up.and.down.text.horizontal", help: "Set the cut plane and view depth."),
        CommandInfo(.cropView, "Crop View", .view, "crop", help: "Toggle cropping."),
        CommandInfo(.toggleCropVisible, "Show Crop Region", .view, "crop.rotate", help: "Toggle crop region visibility."),
        CommandInfo(.sectionBox, "Section Box", .view, "cube.transparent", help: "Toggle the 3D section box."),
        CommandInfo(.thinLines, "Thin Lines", .view, "line.3.horizontal", aliases: ["TL"], help: "Show all lines at one pixel on screen (printing unaffected)."),
        CommandInfo(.temporaryHide, "Hide Element", .view, "eye.slash", aliases: ["HH"], help: "Temporarily hide selected elements."),
        CommandInfo(.temporaryIsolate, "Isolate Element", .view, "scope", aliases: ["HI"], help: "Temporarily show only the selection."),
        CommandInfo(.temporaryHideCategory, "Hide Category", .view, "eye.slash.circle", aliases: ["HC"], help: "Temporarily hide the selection's categories."),
        CommandInfo(.temporaryIsolateCategory, "Isolate Category", .view, "scope", aliases: ["IC"], help: "Temporarily show only the selection's categories."),
        CommandInfo(.resetTemporary, "Reset Temporary Hide/Isolate", .view, "arrow.uturn.backward.circle", aliases: ["HR"], help: "Restore the view after temporary hide/isolate."),
        CommandInfo(.revealHidden, "Reveal Hidden Elements", .view, "lightbulb", aliases: ["RH"], help: "Show elements hidden in the view; unhide them from here."),
        CommandInfo(.hideInView, "Hide in View", .view, "eye.slash.fill", aliases: ["EH"], help: "Permanently hide selected elements in this view."),
        CommandInfo(.unhideInView, "Unhide in View", .view, "eye.fill", aliases: ["EU"], help: "Unhide selected elements in this view."),
        CommandInfo(.zoomExtents, "Zoom to Fit", .view, "arrow.up.left.and.arrow.down.right", shortcut: "⌘0", aliases: ["ZE", "ZF", "ZX"], help: "Zoom to show the whole view."), // BL-KEYS: ZA is Zoom All to Fit
        CommandInfo(.zoomRegion, "Zoom in Region", .view, "rectangle.and.hand.point.up.left", aliases: ["ZR", "ZZ"], help: "Drag a rectangle to zoom into."),
        CommandInfo(.zoomIn, "Zoom In", .view, "plus.magnifyingglass", shortcut: "⌘+", help: "Zoom in."),
        CommandInfo(.zoomOut, "Zoom Out", .view, "minus.magnifyingglass", shortcut: "⌘−", help: "Zoom out."),
        CommandInfo(.zoomOutTwice, "Zoom Out (2x)", .view, "minus.magnifyingglass", aliases: ["ZO", "ZV"], help: "Halve the magnification around the centre of the view."),
        CommandInfo(.zoomSheetSize, "Zoom Sheet Size", .view, "doc.viewfinder", aliases: ["ZS"], help: "Zoom so the drawing appears at its printed size."),
        CommandInfo(.previousPanZoom, "Previous Pan/Zoom", .view, "arrow.uturn.backward.circle", aliases: ["ZP", "ZC"], help: "Step back to the previous pan and zoom of this view."),
        CommandInfo(.nextPanZoom, "Next Pan/Zoom", .view, "arrow.uturn.forward.circle", help: "Step forward again after Previous Pan/Zoom."),
        CommandInfo(.previousView, "Previous View", .view, "chevron.backward", shortcut: "⌘[", help: "Return to the previously active view."),
        CommandInfo(.closeHiddenViews, "Close Inactive Views", .view, "xmark.rectangle", help: "Close every view tab except the active one."),
        CommandInfo(.saveOrientation, "Save 3D Orientation", .view, "camera.viewfinder", help: "Save the current 3D camera as a new 3D view."),
        CommandInfo(.detailCoarse, "Coarse", .view, "circle.dotted", help: "Coarse detail level."),
        CommandInfo(.detailMedium, "Medium", .view, "circle.lefthalf.filled", help: "Medium detail level."),
        CommandInfo(.detailFine, "Fine", .view, "circle.fill", help: "Fine detail level."),
        CommandInfo(.visualStyleWireframe, "Wireframe", .view, "cube.transparent", aliases: ["WF"], help: "Wireframe visual style."),
        CommandInfo(.visualStyleHidden, "Hidden Line", .view, "cube", aliases: ["HL"], help: "Hidden line visual style."),
        CommandInfo(.visualStyleShaded, "Shaded", .view, "cube.fill", aliases: ["SD"], help: "Shaded visual style."),
        CommandInfo(.visualStyleConsistent, "Consistent Colors", .view, "paintpalette", help: "Unlit material colors."),
        CommandInfo(.visualStyleTransparent, "Transparent", .view, "cube.transparent.fill", help: "Transparent visual style."),
        // Manage
        CommandInfo(.typeProperties, "Type Properties", .modify, "list.bullet.rectangle", help: "Edit the type of the selection or of the element being placed (shared by every instance)."),
        CommandInfo(.projectInfo, "Project Information", .manage, "info.circle", help: "Edit project name, number, client and address."),
        CommandInfo(.projectUnits, "Project Units", .manage, "ruler", aliases: ["UN"], help: "Set length, area, volume, angle and slope units."),
        CommandInfo(.projectParameters, "Project Parameters", .manage, "slider.horizontal.3", help: "Add parameters to categories."),
        CommandInfo(.sharedParameters, "Shared Parameters", .manage, "square.and.arrow.up.on.square", help: "Import/export shared parameter definitions."),
        CommandInfo(.materials, "Materials", .manage, "circle.hexagongrid", help: "Browse and edit materials."),
        CommandInfo(.lineStyles, "Line Styles", .manage, "line.3.horizontal.decrease", help: "Detail line styles."),
        CommandInfo(.snapSettings, "Snaps…", .manage, "scope", help: "Choose object snaps, the angle increment and whether snapping is on."),
        CommandInfo(.snapsOff, "Snaps Off (Next Pick)", .modify, "scope", aliases: ["SO"], help: "Turn snapping off for the next pick of the current tool."),
        CommandInfo(.snapEndpoint, "Snap to Endpoint (Next Pick)", .modify, "square", aliases: ["SE"], help: "Snap only to endpoints for the next pick."),
        CommandInfo(.snapMidpoint, "Snap to Midpoint (Next Pick)", .modify, "triangle", aliases: ["SM"], help: "Snap only to midpoints for the next pick."),
        CommandInfo(.snapIntersection, "Snap to Intersection (Next Pick)", .modify, "xmark", aliases: ["SI"], help: "Snap only to intersections for the next pick."),
        CommandInfo(.snapNearest, "Snap to Nearest (Next Pick)", .modify, "hourglass", aliases: ["SN"], help: "Snap only to the nearest point on a line for the next pick."),
        CommandInfo(.snapCenter, "Snap to Center (Next Pick)", .modify, "circle", aliases: ["SC"], help: "Snap only to arc and circle centres for the next pick."),
        CommandInfo(.snapPerpendicular, "Snap to Perpendicular (Next Pick)", .modify, "angle", aliases: ["SP"], help: "Snap only perpendicular to a line for the next pick."),
        CommandInfo(.snapTangent, "Snap to Tangent (Next Pick)", .modify, "circle.dashed", aliases: ["ST"], help: "Snap only tangent to an arc for the next pick."),
        CommandInfo(.snapQuadrant, "Snap to Quadrant (Next Pick)", .modify, "diamond", aliases: ["SQ"], help: "Snap only to arc quadrant points for the next pick."),
        CommandInfo(.phases, "Phases", .manage, "calendar", help: "Project phases and phase filters."),
        CommandInfo(.designOptions, "Design Options", .manage, "square.stack", help: "Option sets and options."),
        CommandInfo(.revisions, "Sheet Issues/Revisions", .manage, "clock.arrow.circlepath", help: "Revision sequence, dates and issue status."),
        CommandInfo(.locationSettings, "Location", .manage, "location.circle", help: "Site location, true north, project base point and survey point."),
        CommandInfo(.familyEditor, "Edit Family", .manage, "cube.box", help: "Open the selected family in the Family Editor."),
        CommandInfo(.newFamily, "New Family…", .manage, "cube.box.fill", help: "Create a family from a category template."),
        CommandInfo(.loadFamily, "Load Family…", .insert, "square.and.arrow.down", help: "Load .arcusfamily files into the project."),
        CommandInfo(.reloadFamily, "Reload Family", .insert, "arrow.clockwise", help: "Reload a family from its file."),
        CommandInfo(.typeCatalog, "Load Type Catalog…", .insert, "tablecells.badge.ellipsis", help: "Load family types from a CSV type catalog."),
        CommandInfo(.purgeUnused, "Purge Unused", .manage, "trash.slash", help: "Remove unused types, families and materials."),
        CommandInfo(.modelHealth, "Model Health", .manage, "stethoscope", help: "Warnings and model checks with navigation to elements."),
        CommandInfo(.diagnostics, "Diagnostics", .manage, "gauge.with.dots.needle.bottom.50percent", help: "Version, performance timings and a redacted local log."),
        CommandInfo(.linkDWG, "Link DWG…", .insert, "link.badge.plus", help: "Link a DWG drawing (requires the licensed DWG SDK)."),
        CommandInfo(.importDWG, "Import DWG…", .insert, "square.and.arrow.down.on.square", help: "Import a DWG drawing snapshot (requires the licensed DWG SDK)."),
        CommandInfo(.linkDXF, "Link DXF…", .insert, "link", help: "Link a DXF drawing."),
        CommandInfo(.importDXF, "Import DXF…", .insert, "square.and.arrow.down", help: "Import a DXF drawing snapshot."),
        CommandInfo(.linkCAD, "Link CAD…", .insert, "link.badge.plus", help: "Link a CAD drawing (DXF, or DWG through the DWG converter or SDK); choose the format in the file dialog.", keywords: ["dwg", "dxf", "cad", "link"]), // BL-SCHED
        CommandInfo(.importCAD, "Import CAD…", .insert, "square.and.arrow.down.on.square", help: "Import a snapshot of a CAD drawing (DXF, or DWG through the DWG converter or SDK); choose the format in the file dialog.", keywords: ["dwg", "dxf", "cad", "import"]), // BL-SCHED
        CommandInfo(.manageLinks, "Manage Links", .insert, "link.circle", help: "Reload, relocate, unload or remove links."),
        CommandInfo(.reloadLink, "Reload Link", .insert, "arrow.clockwise.circle", help: "Reload the selected link from its source."),
        CommandInfo(.unloadLink, "Unload Link", .insert, "eject", help: "Unload the selected link."),
        CommandInfo(.convertLinkToDrafting, "Explode…", .insert, "arrow.triangle.2.circlepath", help: "Convert CAD geometry to detail or model lines.", keywords: ["convert", "explode", "cad", "lines"]),
        CommandInfo(.importIFC, "Import IFC…", .insert, "cube.transparent", help: "Import an IFC model; unsupported items stay as reference geometry."),
        CommandInfo(.importRevit, "Import Revit Model…", .insert, "building.2", help: "Import a .arcusx export from the Arcus Bridge add-in as native, editable elements and families, or inspect a .rvt/.rfa file."),
        CommandInfo(.linkPDF, "Link PDF…", .insert, "doc.richtext", help: "Place a PDF page as a scaled underlay."),
        CommandInfo(.linkImage, "Link Image…", .insert, "photo", help: "Place a PNG, JPEG or TIFF image."),
        CommandInfo(.exportIFC, "Export IFC…", .file, "square.and.arrow.up", help: "Export the architectural model to IFC2x3 or IFC4."),
        CommandInfo(.exportPDF, "Export PDF…", .file, "doc.badge.arrow.up", shortcut: "⌥⌘P", help: "Export sheets and views to vector PDF."),
        CommandInfo(.exportDXF, "Export DXF…", .file, "arrow.up.doc", help: "Export the current view's 2D linework to DXF."),
        CommandInfo(.exportScheduleCSV, "Export Schedule CSV…", .file, "tablecells", help: "Export the active schedule to CSV."),
        CommandInfo(.importScheduleCSV, "Import Schedule CSV…", .file, "tablecells.badge.ellipsis", help: "Update writable schedule columns from a CSV file."),
        CommandInfo(.exportImage, "Export Image…", .file, "photo", help: "Save the active view or sheet as a PNG or JPEG image, rendered on this Mac.", keywords: ["png", "jpeg", "jpg", "image", "picture"]), // BL-SCHED
        CommandInfo(.newTitleBlock, "New Title Block…", .file, "doc.text", help: "Open the Family Editor on a new title block family.", keywords: ["title block", "family"]), // BL-SCHED
        CommandInfo(.newAnnotationSymbol, "New Annotation Symbol…", .file, "seal", help: "Open the Family Editor on a new generic annotation family.", keywords: ["symbol", "annotation", "family"]), // BL-SCHED
        CommandInfo(.scheduleProperties, "Schedule Properties", .view, "slider.horizontal.3", help: "Fields, filter, sorting/grouping, formatting and appearance of the active schedule."), // BL-SCHED
        CommandInfo(.scheduleInsertColumn, "Insert Column", .view, "rectangle.badge.plus", help: "Add fields to the schedule (opens Schedule Properties, Fields)."), // BL-SCHED
        CommandInfo(.scheduleDeleteColumn, "Delete Column", .view, "rectangle.badge.minus", help: "Remove the fields of the selected columns from the schedule."), // BL-SCHED
        CommandInfo(.scheduleHideColumn, "Hide Column", .view, "eye.slash", help: "Hide the selected columns (they still filter and sort)."), // BL-SCHED
        CommandInfo(.scheduleUnhideAllColumns, "Unhide All", .view, "eye", help: "Show every hidden column."), // BL-SCHED
        CommandInfo(.scheduleResizeColumn, "Resize Column…", .view, "arrow.left.and.right", help: "Set the width of the selected columns on paper."), // BL-SCHED
        CommandInfo(.scheduleInsertRow, "Insert Data Row", .view, "plus.square", help: "Add a row where rows are records created here (sheet lists: a new sheet)."), // BL-SCHED
        CommandInfo(.scheduleDeleteRow, "Delete Row", .view, "minus.square", help: "Delete the elements of the selected rows from the model."), // BL-SCHED
        CommandInfo(.scheduleMergeHeaders, "Merge Unmerge", .view, "rectangle.split.2x1", help: "Merge the selected column headers under one heading, or unmerge them."), // BL-SCHED
        CommandInfo(.scheduleGroupHeaders, "Group", .view, "rectangle.3.group", help: "Group the selected column headers under a new heading."), // BL-SCHED
        CommandInfo(.scheduleUngroupHeaders, "Ungroup", .view, "rectangle.3.group.bubble", help: "Remove the heading group of the selected columns."), // BL-SCHED
        CommandInfo(.scheduleAppearance, "Appearance", .view, "paintpalette", help: "Grid lines, outline, text sizes and header shading of the schedule."), // BL-SCHED
        CommandInfo(.scheduleFormatUnit, "Format Unit", .view, "ruler", help: "Heading, alignment, decimals and totals of the selected column."), // BL-SCHED
        CommandInfo(.scheduleCalculatedField, "Calculated", .view, "function", help: "Add a calculated value (formula) field."), // BL-SCHED
        CommandInfo(.highlightInModel, "Highlight in Model", .view, "scope", help: "Select the elements of the selected schedule rows in a model view and zoom to them (also Option-double-click a row)."), // BL-SCHED
        CommandInfo(.print, "Print…", .file, "printer", shortcut: "⌘P", help: "Print sheets or views."),
        CommandInfo(.home, "Home", .file, "house", help: "Show the Home screen: start a project, open one, or pick a recent project.", keywords: ["start", "recent", "hub"]),
        CommandInfo(.newProject, "New Project…", .file, "doc.badge.plus", shortcut: "⌘N", help: "Start a project, furniture or family from Home."),
        CommandInfo(.openProject, "Open…", .file, "folder", shortcut: "⌘O", help: "Open a project, furniture or family."),
        CommandInfo(.save, "Save", .file, "square.and.arrow.down", shortcut: "⌘S", help: "Save the project."),
        CommandInfo(.saveAs, "Save As…", .file, "square.and.arrow.down.on.square", shortcut: "⇧⌘S", help: "Save a copy under a new name."),
        CommandInfo(.duplicateDocument, "Duplicate", .file, "plus.rectangle.on.rectangle", help: "Duplicate the project document."),
        CommandInfo(.revert, "Revert To Saved", .file, "arrow.uturn.backward", help: "Discard changes since the last save."),
        CommandInfo(.closeDocument, "Close", .file, "xmark", shortcut: "⌘W", help: "Close the project window."),
        CommandInfo(.exportRecoveryCopy, "Save Recovery Copy…", .file, "cross.case", help: "Write every readable element into a new project file."),
        CommandInfo(.commandSearch, "Command Search", .app, "magnifyingglass", shortcut: "⌘K", help: "Find any command by name, alias or keyword."),
        CommandInfo(.preferences, "Settings…", .app, "gearshape", shortcut: "⌘,", help: "Arcus settings."),
        CommandInfo(.workspaceBIMFamiliar, "BIM Familiar Workspace", .app, "rectangle.leftthird.inset.filled", help: "Properties above the Project Browser on the left."),
        CommandInfo(.workspaceMacSpacious, "Mac Spacious Workspace", .app, "rectangle.righthalf.inset.filled", help: "Project Browser on the left, Properties inspector on the right."),
        CommandInfo(.resetWorkspace, "Reset Workspace", .app, "arrow.counterclockwise.circle", help: "Restore the default panel layout."),
        CommandInfo(.toggleNavigator, "Project Browser", .app, "sidebar.left", shortcut: "⌥⌘1", help: "Show or hide the Project Browser."),
        CommandInfo(.toggleProperties, "Properties", .app, "sidebar.right", shortcut: "⌥⌘2", aliases: ["PP"], help: "Show or hide the Properties inspector."),
        CommandInfo(.keyboardShortcuts, "Keyboard Shortcuts…", .app, "keyboard", aliases: ["KS"], help: "View, edit, import and export command aliases."), // BL-KEYS
        CommandInfo(.onboarding, "Welcome to Arcus", .app, "sparkles", help: "Show the welcome guide."),
        CommandInfo(.about, "About Arcus", .app, "info.circle", help: "Version and build information."),
        CommandInfo(.undo, "Undo", .app, "arrow.uturn.backward", shortcut: "⌘Z", help: "Undo the last change."),
        CommandInfo(.redo, "Redo", .app, "arrow.uturn.forward", shortcut: "⇧⌘Z", help: "Redo."),
        CommandInfo(.cut, "Cut", .app, "scissors", shortcut: "⌘X", help: "Cut to the clipboard."),
        CommandInfo(.copyClipboard, "Copy", .app, "doc.on.doc", shortcut: "⌘C", help: "Copy to the clipboard."),
        CommandInfo(.paste, "Paste", .app, "doc.on.clipboard", shortcut: "⌘V", help: "Paste and place with the cursor."),
        CommandInfo(.pasteAlignedSameLevel, "Paste Aligned to Same Place", .app, "doc.on.clipboard.fill", help: "Paste at the original location."),
        CommandInfo(.pasteAlignedSelectedLevels, "Paste Aligned to Selected Levels…", .app, "square.stack.3d.up", help: "Paste to the same plan position on chosen levels."),
        CommandInfo(.pasteAlignedCurrentView, "Paste Aligned to Current View", .app, "square.and.arrow.down.on.square", help: "Paste view-specific items into the current view at the same place."),
        CommandInfo(.selectPrevious, "Select Previous", .modify, "clock.arrow.circlepath", shortcut: "⌥⌘←", help: "Select again the elements that were selected last.", keywords: ["reselect", "last selection"]),
        CommandInfo(.editWitnessLines, "Edit Witness Lines", .modify, "ruler", help: "Add or remove references of the selected dimension by clicking them.", keywords: ["dimension", "reference"]),
        CommandInfo(.curtainWall, "Wall – Curtain Wall", .build, "rectangle.split.3x3", help: "Draw curtain walls: glazed panels on a grid with mullions.", keywords: ["glazing", "storefront", "facade"]),
        CommandInfo(.curtainGrid, "Curtain Grid", .build, "squareshape.split.3x3", aliases: ["CG"], help: "Add grid lines to a curtain wall, or remove grid lines you added.", keywords: ["curtain wall"]),
        CommandInfo(.mullion, "Mullion", .build, "square.split.2x1", aliases: ["MU"], help: "Add mullions to curtain grid lines, or remove them.", keywords: ["curtain wall", "transom"]),
        CommandInfo(.curtainPanel, "Curtain Panel", .build, "square.grid.2x2", help: "Swap curtain wall panels to the panel type chosen in the type selector.", keywords: ["curtain wall", "glazing", "spandrel"]),
        CommandInfo(.wallOpening, "Wall Opening", .build, "rectangle.dashed", help: "Cut a rectangular opening in a wall from an elevation or section.", keywords: ["hole", "opening"]),
        CommandInfo(.shaftOpening, "Shaft", .build, "square.stack.3d.down.dottedline", help: "Sketch a shaft that cuts every floor, ceiling and roof between its base and top.", keywords: ["hole", "opening", "lift", "riser"]),
        CommandInfo(.ramp, "Ramp", .build, "figure.roll", help: "Draw a ramp run from its bottom to its top; clicks between turn at landings. Railings are added on both sides.", keywords: ["accessible", "incline", "slope"]),
        CommandInfo(.roofExtrusion, "Roof by Extrusion", .build, "triangle", help: "Sketch an open roof profile in an elevation or section and extrude it perpendicular to the work plane.", keywords: ["gable", "barrel", "profile"]),
        CommandInfo(.editStair, "Edit Stair", .modify, "pencil.and.ruler", help: "Edit a placed stair: drag its start, direction, run width or landing, or change its shape and riser counts."),
        CommandInfo(.modifySubElements, "Modify Sub Elements", .modify, "point.3.connected.trianglepath.dotted", help: "Select points and vertices of a floor or flat roof and type their elevation offsets.", keywords: ["shape editing", "drainage", "falls"]),
        CommandInfo(.addShapePoint, "Add Point", .modify, "plus.viewfinder", help: "Add shape-editing points to a floor or flat roof at an elevation offset.", keywords: ["shape editing", "drainage", "falls"]),
        CommandInfo(.resetShape, "Reset Shape", .modify, "arrow.counterclockwise.circle", help: "Remove shape editing from the selected floors and roofs."),
        CommandInfo(.attachWallsToHost, "Attach Walls", .modify, "rectangle.connected.to.line.below", help: "Attach the walls below the selected roof or floor to its underside."),
        CommandInfo(.joinSolids, "Join Geometry", .modify, "square.fill.on.square.fill", aliases: ["JG"], help: "Join overlapping walls, floors, roofs and ceilings so the overlap is cut from one of them and counted once. Walls cut floors, roofs and ceilings; roofs cut floors; floors cut ceilings.", keywords: ["cut", "overlap", "quantities"]),
        CommandInfo(.unjoinSolids, "Unjoin Geometry", .modify, "square.and.line.vertical.and.square", help: "Remove geometry joins between the selected elements."),
        // BL-VG: graphics control, project settings, geometry and structure
        CommandInfo(.filtersDialog, "Filters…", .view, "line.3.horizontal.decrease.circle", help: "Create and edit rule-based view filters: several categories, rules joined by AND or OR, and nested rule sets.", keywords: ["view filter", "rules"]),
        CommandInfo(.viewTemplatesManage, "Manage View Templates…", .view, "doc.text.below.ecg", help: "Create, rename, duplicate and edit view templates and choose which settings each controls.", keywords: ["template"]),
        CommandInfo(.viewTemplateCreate, "Create Template from Current View…", .view, "doc.badge.plus", help: "Save the current view's scale, detail level, visual style, view range, phase filter and V/G overrides as a view template.", keywords: ["template"]),
        CommandInfo(.viewTemplateApplyProperties, "Apply Template Properties to Current View…", .view, "doc.on.doc", help: "Copy a view template's settings into the current view once, without assigning the template.", keywords: ["template"]),
        CommandInfo(.temporaryViewProperties, "Temporary View Properties", .view, "clock.badge", help: "Apply a view template to this view until you restore it; nothing is saved.", keywords: ["template", "temporary"]),
        CommandInfo(.revealConstraints, "Reveal Constraints", .view, "lock.rectangle", help: "Show locked dimensions, alignments and EQ constraints in this view.", keywords: ["locks", "constraints"]),
        CommandInfo(.userInterface, "User Interface…", .view, "macwindow", help: "Show or hide the Properties palette, Project Browser, status bar and navigation bar.", keywords: ["palettes", "panels"]),
        CommandInfo(.toggleStatusBar, "Status Bar", .app, "rectangle.bottomthird.inset.filled", help: "Show or hide the status bar under the canvas."),
        CommandInfo(.toggleNavigationBar, "Navigation Bar", .app, "arrow.up.left.and.arrow.down.right", help: "Show or hide the navigation bar on views."),
        CommandInfo(.objectStyles, "Object Styles…", .manage, "paintpalette", help: "Line weights, colours, patterns and materials of every category and subcategory, for all views.", keywords: ["line weight", "category graphics"]),
        CommandInfo(.warnings, "Warnings…", .manage, "exclamationmark.triangle", help: "Review warnings: expand to the elements, show or delete them, and export a report.", keywords: ["errors", "review warnings"]),
        CommandInfo(.selectByID, "Select by ID…", .manage, "number.circle", help: "Select elements by their ids.", keywords: ["element id"]),
        CommandInfo(.idsOfSelection, "IDs of Selection", .manage, "number", help: "Show the ids of the selected elements, ready to copy.", keywords: ["element id"]),
        CommandInfo(.additionalSettings, "Additional Settings…", .manage, "gearshape.2", help: "Line weights, line patterns, fill patterns, arrowheads and temporary dimensions.", keywords: ["settings"]),
        CommandInfo(.lineWeights, "Line Weights…", .manage, "line.3.horizontal", help: "Pen widths of the line weights at each view scale."),
        CommandInfo(.linePatterns, "Line Patterns…", .manage, "line.horizontal.3.decrease", help: "The dash patterns lines can use."),
        CommandInfo(.fillPatterns, "Fill Patterns…", .manage, "square.grid.3x3.fill", help: "Drafting and model fill patterns used by materials, regions and overrides."),
        CommandInfo(.arrowheads, "Arrowheads…", .manage, "arrow.up.right", help: "Dimension terminators and annotation arrowheads."),
        CommandInfo(.temporaryDimensionSettings, "Temporary Dimensions…", .manage, "ruler", help: "Measure temporary dimensions of walls from their centerlines or faces."),
        CommandInfo(.cutGeometry, "Cut Geometry", .modify, "scissors.badge.ellipsis", help: "Cut one floor, ceiling or roof with another element: pick the element to cut first, then the cutting element.", keywords: ["void", "cut"]),
        CommandInfo(.uncutGeometry, "Uncut Geometry", .modify, "arrow.uturn.backward.square", help: "Remove cuts between the selected elements."),
        CommandInfo(.switchJoinOrder, "Switch Join Order", .modify, "arrow.left.arrow.right.square", help: "Make the element that was cut by a join cut the other one instead."),
        CommandInfo(.foundationIsolated, "Isolated Foundation", .structure, "square.bottomhalf.filled", help: "Add a pad footing under each selected structural column.", keywords: ["footing", "pad", "foundation"]),
        CommandInfo(.foundationWall, "Wall Foundation", .structure, "rectangle.bottomhalf.filled", aliases: ["FT"], help: "Add a strip footing under each selected wall.", keywords: ["footing", "strip", "foundation"]),
        CommandInfo(.foundationSlab, "Foundation Slab", .structure, "square.3.layers.3d.bottom.filled", help: "Sketch a structural foundation slab.", keywords: ["raft", "mat", "foundation"]),
        CommandInfo(.structuralWall, "Structural Wall", .structure, "rectangle.split.1x2.fill", help: "Draw load-bearing walls (Structural is on).", keywords: ["bearing wall", "shear wall"]),
        CommandInfo(.structuralFloor, "Structural Floor", .structure, "square.3.layers.3d.middle.filled", aliases: ["SB"], help: "Sketch a structural floor (Structural is on).", keywords: ["slab", "deck"]),
        CommandInfo(.createSimilar, "Create Similar", .modify, "rectangle.badge.plus", aliases: ["CS"], help: "Start placing a new element of the selected element's type.", keywords: ["same type", "place like"]),
        CommandInfo(.measureBetween, "Measure Between Two References", .modify, "lines.measurement.horizontal", aliases: ["ME"], help: "Measure the distance between picked points; nothing is added to the model.", keywords: ["distance", "tape"]),
        CommandInfo(.measureAlong, "Measure Along an Element", .modify, "lines.measurement.vertical", help: "Measure the length of a wall or line, or the perimeter of a floor, roof or region.", keywords: ["length", "perimeter"]),
        CommandInfo(.demolish, "Demolish", .modify, "hammer", help: "Mark picked elements (and their doors and windows) as demolished in the view's phase.", keywords: ["phase", "existing"]),
        CommandInfo(.arrayNumber, "Array Number…", .modify, "number.square", help: "Change the number of members of the selected array group; the copies are regenerated.", keywords: ["array count"]),
        CommandInfo(.scale, "Scale", .modify, "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", aliases: ["RE"], help: "Resize lines, walls, regions and images about a base point, graphically or by a factor."),
        CommandInfo(.selectionBox, "Selection Box", .view, "cube.transparent", aliases: ["BX"], help: "Open a 3D view with its section box fitted around the selected elements.", keywords: ["section box", "crop 3d"]),
        CommandInfo(.overrideGraphicsElement, "Override Graphics in View…", .view, "paintbrush", aliases: ["EOD"], help: "Change line colour, weight and pattern, fills, halftone and transparency of the selected elements in this view only.", keywords: ["override", "by element", "graphics"]), // BL-KEYS
        CommandInfo(.activateViewport, "Activate View", .view, "rectangle.inset.filled.and.cursorarrow", help: "Edit the selected viewport's view in place on the sheet; other viewports dim."),
        CommandInfo(.deactivateViewport, "Deactivate View", .view, "rectangle.dashed", help: "Return to editing the sheet after working in a viewport."),
        CommandInfo(.cameraView, "Camera", .view, "camera", help: "Place a camera in a plan (eye, then target) to create a perspective 3D view.", keywords: ["perspective", "3d view"]),
        CommandInfo(.scopeBox, "Scope Box", .view, "square.dashed", help: "Draw a scope box that limits where levels, grids and reference planes appear and can crop plan views.", keywords: ["datum extents"]),
        CommandInfo(.gridPickLines, "Grid – Pick Lines", .build, "cursorarrow.rays", help: "Create grid lines on picked lines, walls or CAD lines."),
        CommandInfo(.showProjectBasePoint, "Show Project Base Point", .view, "circle.circle", help: "Show or hide the project base point in this view.", keywords: ["coordinates", "origin", "site"]),
        CommandInfo(.showSurveyPoint, "Show Survey Point", .view, "triangle", help: "Show or hide the survey point in this view.", keywords: ["coordinates", "shared", "site"]),
        CommandInfo(.placeRoomsAutomatically, "Place Rooms Automatically", .build, "square.grid.2x2", help: "Place a tagged room in every enclosed region of the level that has none.", keywords: ["auto room"]),
        CommandInfo(.placeAreasAutomatically, "Place Areas Automatically", .build, "square.grid.2x2.fill", help: "Place a tagged area in every region enclosed by area boundaries that has none.", keywords: ["auto area"]),
        CommandInfo(.colorSchemes, "Color Schemes…", .build, "paintpalette", help: "Colour rooms or areas by a parameter value or range, and choose the view's scheme.", keywords: ["color fill", "colour fill", "department"]),
        CommandInfo(.colorFillLegend, "Color Fill Legend", .annotate, "list.bullet.rectangle.portrait", help: "Place a legend listing the colour fill values used in the view.", keywords: ["colour legend"]),
        CommandInfo(.areaPlan, "Area Plan", .view, "square.split.bottomrightquarter", help: "Create area plans for a gross or rentable area scheme, with boundary lines from exterior walls.", keywords: ["gross area", "rentable"]),
        CommandInfo(.saveAsTemplate, "Save as Template…", .file, "doc.badge.gearshape", help: "Save this project's types, families, views, sheets and settings, without model elements, as a template for new projects."),
        // W2-CAM: 3D navigation (numeric keypad equivalents in the 3D view: 1 3 7, ⌃ for the opposite side, 5, 0, .)
        CommandInfo(.view3DFront, "Front View", .view, "arrow.up.square", shortcut: "⌃⌥1", help: "Look at the model from the front (south). Keypad 1 in a 3D view.", keywords: ["orient", "3d", "south"]),
        CommandInfo(.view3DBack, "Back View", .view, "arrow.down.square", shortcut: "⌃⌥⌘1", help: "Look at the model from the back (north). ⌃ keypad 1 in a 3D view.", keywords: ["orient", "3d", "north"]),
        CommandInfo(.view3DRight, "Right View", .view, "arrow.left.square", shortcut: "⌃⌥3", help: "Look at the model from the right (east). Keypad 3 in a 3D view.", keywords: ["orient", "3d", "east"]),
        CommandInfo(.view3DLeft, "Left View", .view, "arrow.right.square", shortcut: "⌃⌥⌘3", help: "Look at the model from the left (west). ⌃ keypad 3 in a 3D view.", keywords: ["orient", "3d", "west"]),
        CommandInfo(.view3DTop, "Top View", .view, "arrow.down.to.line", shortcut: "⌃⌥7", help: "Look straight down at the model. Keypad 7 in a 3D view.", keywords: ["orient", "3d", "plan"]),
        CommandInfo(.view3DBottom, "Bottom View", .view, "arrow.up.to.line", shortcut: "⌃⌥⌘7", help: "Look straight up at the model. ⌃ keypad 7 in a 3D view.", keywords: ["orient", "3d"]),
        CommandInfo(.view3DToggleProjection, "Perspective/Orthographic", .view, "perspective", shortcut: "⌃⌥5", help: "Switch the 3D view between perspective and orthographic projection. Keypad 5 in a 3D view.", keywords: ["projection", "isometric"]),
        CommandInfo(.view3DFrameSelected, "Frame Selected", .view, "scope", shortcut: "⌃⌥.", help: "Zoom the 3D view to the selected elements. Keypad . in a 3D view.", keywords: ["zoom selected", "focus"]),
        CommandInfo(.view3DFly, "Fly Navigation", .view, "airplane", shortcut: "⌃⌥F", help: "Fly through the 3D view: move the mouse to look, W A S D to move, Q/E down/up, scroll for speed; Return keeps, Esc cancels. ⇧F in a 3D view.", keywords: ["walk", "walkthrough", "first person"]),
        CommandInfo(.viewThroughCamera, "View Through Camera", .view, "camera.aperture", shortcut: "⌃⌥0", help: "Look through the active camera in this 3D view (again to go back). Keypad 0 in a 3D view.", keywords: ["camera view", "look through"]),
        CommandInfo(.alignCameraToView, "Align Camera to View", .view, "camera.viewfinder", shortcut: "⌃⌥⌘0", help: "Move the active camera (or this camera view's camera) to the current 3D view. ⌃⌥ keypad 0 in a 3D view.", keywords: ["camera to view", "set camera"]),
        CommandInfo(.lockCameraToView, "Lock Camera to View", .view, "lock", shortcut: "⌃⌥L", help: "When on, navigating a camera view (or looking through a camera) moves the camera; when off, navigating leaves the saved camera alone.", keywords: ["camera"]),
        CommandInfo(.createCameraFromView, "Create Camera from View", .view, "camera.badge.ellipsis", help: "Save the current 3D view as a new camera.", keywords: ["new camera", "perspective"]),
        // W2-TYPES
        CommandInfo(.loadStandardTypes, "Load Standard Types", .manage, "square.stack.3d.down.forward",
                    help: "Add the standard wall, floor, roof, ceiling, door, window and column types for the project's units that the project doesn't have yet.",
                    keywords: ["imperial types", "metric types", "library", "door types", "window types", "column types"]),
        // W2-DWG: Massing & Site, hosted profiles.
        CommandInfo(.siteSettings, "Site Settings…", .manage, "slider.horizontal.3", help: "Contour interval, primary contours and contour display for toposurfaces.", keywords: ["contour", "topography", "site"]),
        CommandInfo(.toposurfaceFromFile, "Toposurface from Point File…", .build, "list.number", help: "Create a toposurface from a CSV, TXT or XYZ file of x, y, z survey points.", keywords: ["survey", "csv", "xyz", "points", "terrain"]),
        CommandInfo(.toposurfaceFromImport, "Toposurface from Import…", .build, "square.stack.3d.down.right", help: "Create a toposurface from the contour lines and points on chosen layers of a linked or imported DXF/DWG.", keywords: ["contours", "cad", "dwg", "dxf", "terrain"]),
        CommandInfo(.subregion, "Sub-Region", .build, "square.dashed.inset.filled", help: "Sketch an area of a toposurface with its own material (paving, lawn, planting beds).", keywords: ["subregion", "paving", "material", "site"]),
        CommandInfo(.splitSurface, "Split Surface", .build, "scissors", help: "Split a toposurface in two along a sketched line.", keywords: ["toposurface", "site"]),
        CommandInfo(.mergeSurfaces, "Merge Surfaces", .build, "plus.rectangle.on.rectangle", help: "Join the selected toposurfaces into one.", keywords: ["toposurface", "site"]),
        CommandInfo(.gradedRegion, "Graded Region", .build, "mountain.2.fill", help: "Copy a toposurface as the proposed (graded) ground: the existing surface is demolished in the view's phase and the copy opens for editing.", keywords: ["grading", "cut", "fill", "earthwork"]),
        CommandInfo(.editSurface, "Edit Surface", .modify, "point.3.filled.connected.trianglepath.dotted", help: "Add, delete or re-level the points of the selected toposurface.", keywords: ["toposurface", "points", "grading"]),
        CommandInfo(.labelContours, "Label Contours", .annotate, "textformat.123", help: "Draw a line across contours to label their elevations.", keywords: ["contour", "elevation", "site"]),
        CommandInfo(.siteComponent, "Site Component", .build, "tree", help: "Place trees, planting, entourage and site furniture.", keywords: ["planting", "tree", "entourage", "bench"]),
        CommandInfo(.parkingComponent, "Parking Component", .build, "car", help: "Place parking stalls, signs and other parking components.", keywords: ["parking", "stall", "car"]),
        CommandInfo(.parkingLayout, "Parking Layout", .build, "parkingsign", help: "Fill a sketched or picked area with painted parking stalls at 90°, 60° or 45°, with optional wheel stops, and report the stall count.", keywords: ["parking", "stalls", "car park", "striping"]),
        CommandInfo(.wallSweep, "Wall: Sweep", .build, "rectangle.split.1x2", help: "Add a horizontal sweep (base course, string course, cornice) to the selected walls; set its height, size and side in Properties.", keywords: ["cornice", "baseboard", "skirting", "molding"]),
        CommandInfo(.slabEdge, "Floor: Slab Edge", .build, "square.bottomthird.inset.filled", help: "Add a thickened slab edge under the selected floors; set its width and depth in Properties.", keywords: ["downstand", "edge beam", "thickened"]),
        CommandInfo(.roofSoffit, "Roof: Soffit", .build, "house", help: "Add a flat soffit under the eaves of the selected roofs; set its depth in Properties.", keywords: ["eave", "fascia", "overhang"]),
        // BL-SITE: toposolids
        CommandInfo(.toposolid, "Toposolid", .build, "mountain.2.fill", help: "Sketch the boundary of a layered site solid; shape it afterwards with Edit Surface.", keywords: ["terrain", "site", "topography", "ground", "toposurface"]),
        CommandInfo(.toposolidFromFile, "Toposolid from Point File…", .build, "list.number", help: "Create a toposolid from a CSV, TXT or XYZ file of x, y, z survey points.", keywords: ["survey", "csv", "xyz", "points", "terrain"]),
        CommandInfo(.toposolidFromImport, "Toposolid from Import…", .build, "square.stack.3d.down.right", help: "Create a toposolid from the contour lines and points on chosen layers of a linked or imported DXF/DWG.", keywords: ["contours", "cad", "dwg", "dxf", "terrain"]),
        CommandInfo(.generateToposolid, "Generate Toposolid", .build, "arrow.up.and.down.square", help: "Replace the selected legacy toposurface with a toposolid; its sub-regions become sub-divisions.", keywords: ["convert", "toposurface", "legacy"]),
        CommandInfo(.subdivideToposolid, "Sub-Divide", .build, "square.dashed.inset.filled", help: "Sketch an area of a toposolid as a thin layered solid (paving, lawn, planting beds) that follows its surface.", keywords: ["subdivision", "subregion", "paving", "site"]),
        CommandInfo(.simplifySurface, "Simplify Surface…", .modify, "wand.and.rays", help: "Remove survey points that barely change the selected toposolid or toposurface.", keywords: ["reduce", "points", "decimate", "topography"]),
        CommandInfo(.excavateToposolid, "Excavate", .modify, "square.and.arrow.down.on.square", help: "Lower or raise the selected toposolid to the underside of the selected floors and building pads, and record the cut and fill.", keywords: ["cut", "fill", "earthwork", "pad", "excavation"]),
        // W2-LIB: built-in component library
        CommandInfo(.componentLibrary, "Component Library…", .insert, "books.vertical", aliases: ["LB"],
                    help: "Browse the built-in library of furniture, casework, fixtures, lighting, equipment, planting, entourage and parking, and place any item; a family is loaded when first placed.",
                    keywords: ["furniture", "fixture", "lighting", "library", "sofa", "bed", "kitchen", "toilet", "tree", "car", "people", "load family"]),
        CommandInfo(.siteLibrary, "Site & Parking Library…", .insert, "tree",
                    help: "Open the component library on planting, entourage, site furniture and parking content.",
                    keywords: ["site component", "parking component", "planting", "trees", "entourage", "vehicles", "parking", "signage"]),
        // W2-ANNOT: Annotate tab additions.
        CommandInfo(.repeatingDetailComponent, "Repeating Detail Component", .annotate, "rectangle.split.3x1", help: "Draw a path along which a detail component repeats (brick coursing, blocking).", keywords: ["repeating detail", "brick"]),
        CommandInfo(.legendComponent, "Legend Component", .annotate, "list.bullet.rectangle", help: "Place the plan symbol of a door, window, furniture, wall or floor type in a legend view.", keywords: ["legend"]),
        CommandInfo(.detailGroupPlace, "Place Detail Group", .annotate, "square.on.square.dashed", help: "Place a copy of a detail group in this view.", keywords: ["detail group", "group"]),
        CommandInfo(.detailGroupCreate, "Create Detail Group", .annotate, "plus.square.on.square", help: "Group the selected detail lines, regions, components and text of this view.", keywords: ["detail group", "group"]),
        CommandInfo(.checkSpelling, "Check Spelling", .annotate, "textformat.abc.dottedunderline", help: "Check the spelling of text notes in this view (or the selected notes) with the system dictionary, on this Mac.", keywords: ["spell", "spelling"]),
        CommandInfo(.findReplace, "Find/Replace", .annotate, "text.magnifyingglass", help: "Find and replace text in text notes and in the values tags show, with a preview of every change.", keywords: ["search", "replace", "text"]),
        CommandInfo(.multiCategoryTag, "Multi-Category Tag", .annotate, "tag.circle", help: "Tag elements of any category with one tag showing their mark."),
        CommandInfo(.materialTag, "Material Tag", .annotate, "square.3.layers.3d", help: "Tag the material of the element or wall layer under the pointer.", keywords: ["material"]),
        CommandInfo(.areaTag, "Tag Area", .annotate, "tag.square", help: "Tag areas with their name and area.", keywords: ["area"]),
        CommandInfo(.viewReference, "View Reference", .annotate, "arrow.up.right.square", help: "Place a reference to another view: its detail and sheet number. Double-click it to open the view.", keywords: ["matchline", "reference"]),
        CommandInfo(.keynoteElement, "Element Keynote", .annotate, "key", help: "Keynote an element with its type's Keynote.", keywords: ["keynote"]),
        CommandInfo(.keynoteMaterial, "Material Keynote", .annotate, "key.horizontal", help: "Keynote the material under the pointer with the material's Keynote.", keywords: ["keynote"]),
        CommandInfo(.keynoteUser, "User Keynote", .annotate, "key.fill", help: "Keynote an element with a key chosen from the keynote table.", keywords: ["keynote"]),
        CommandInfo(.treadNumber, "Tread Number", .annotate, "number", help: "Number the treads of a stair, on the side of the run you click.", keywords: ["stair", "riser number"]),
        CommandInfo(.beamAnnotations, "Beam Annotations", .annotate, "rectangle.and.pencil.and.ellipsis", help: "Tag every untagged beam in the view at its midpoint.", keywords: ["beam", "framing tag"]),
        CommandInfo(.scaleBar, "Scale Bar", .annotate, "chart.bar.xaxis", help: "Place a graphic scale for this view's scale.", keywords: ["graphic scale"]),
        CommandInfo(.spanDirection, "Span Direction", .annotate, "arrow.left.and.right", help: "Show the span direction of a floor with a symbol.", keywords: ["one-way", "slab"]),
        CommandInfo(.stairPath, "Stair Path", .annotate, "figure.stairs", help: "Draw the walk line of a stair with its direction arrow and UP label.", keywords: ["stair", "walk line", "up arrow"]),
        CommandInfo(.addTextLeader, "Add Leader", .annotate, "arrow.up.left", help: "Add a leader to the selected text notes, toward the nearest free side.", keywords: ["text", "leader"]),
        CommandInfo(.removeTextLeader, "Remove Leader", .annotate, "arrow.uturn.backward", help: "Remove the last leader of the selected text notes.", keywords: ["text", "leader"]),
        // BL-KEYS: snap overrides, Repeat, Zoom All to Fit, View Properties and context-menu commands.
        CommandInfo(.snapWorkPlaneGrid, "Snap to Work Plane Grid (Next Pick)", .modify, "grid", aliases: ["SW"], help: "Snap only to grid intersections for the next pick (Arcus has no separate work plane grid in 2D views)."),
        CommandInfo(.snapPoints, "Snap to Points (Next Pick)", .modify, "smallcircle.filled.circle", aliases: ["SX"], help: "Snap only to points (element end and centre points) for the next pick."),
        CommandInfo(.snapRemote, "Snap to Remote Objects (Next Pick)", .modify, "scope", aliases: ["SR"], help: "Snap to objects farther from the pointer than usual for the next pick."),
        CommandInfo(.snapClose, "Snap Close (Next Pick)", .modify, "arrow.triangle.capsulepath", aliases: ["SZ"], help: "Snap only to endpoints for the next pick, to close a chain on its start point."),
        CommandInfo(.snapOverrideOff, "Turn Override Off", .modify, "xmark.circle", aliases: ["SS"], help: "Cancel a snap override typed for the next pick; the normal snaps apply again."),
        CommandInfo(.repeatLastCommand, "Repeat Last Command", .modify, "repeat", aliases: ["RC"], help: "Run the last creation or modify command again. Return in Modify does the same.", keywords: ["repeat", "again", "recent"]),
        CommandInfo(.zoomAllToFit, "Zoom All to Fit", .view, "rectangle.3.group", aliases: ["ZA"], help: "Zoom every open view to show its whole contents."),
        CommandInfo(.viewProperties, "View Properties", .view, "info.circle", aliases: ["VP"], help: "Clear the selection and show the active view's properties."),
        CommandInfo(.findReferringViews, "Find Referring Views…", .view, "rectangle.stack.badge.person.crop", help: "List the views that show the selected element and open one.", keywords: ["which views", "shown in"]),
        CommandInfo(.hideCategoryInView, "Hide Category in View", .view, "eye.slash.circle.fill", aliases: ["VH"], help: "Hide every element of the selected elements' categories in this view (Visibility/Graphics)."),
        CommandInfo(.hideByFilter, "Hide by Filter…", .view, "line.3.horizontal.decrease.circle", help: "Open Visibility/Graphics on its Filters to hide elements by a filter in this view."),
        CommandInfo(.overrideByCategory, "Override Graphics by Category…", .view, "paintbrush.pointed", help: "Open Visibility/Graphics to override the graphics of a whole category in this view."),
        CommandInfo(.overrideByFilter, "Override Graphics by Filter…", .view, "paintbrush.pointed.fill", help: "Open Visibility/Graphics on its Filters to override graphics by a filter in this view."),
    ]

    public static let byID: [CommandID: CommandInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    public static func info(_ id: CommandID) -> CommandInfo { byID[id] ?? CommandInfo(id, id.rawValue, .app, "questionmark", help: "") }

    /// Default alias table (user overrides are stored by the UI and merged on top).
    public static var defaultAliases: [String: CommandID] {
        var d: [String: CommandID] = [:]
        for c in all { for a in c.aliases { d[a] = c.id } }
        return d
    }

    /// Search by title, alias, keyword and help text. Recent commands get a boost.
    public static func search(_ query: String, aliases: [String: CommandID], recent: [CommandID], available: (CommandID) -> Bool) -> [CommandInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return recent.compactMap { byID[$0] } + all.filter { !recent.contains($0.id) && [.build, .annotate, .view].contains($0.group) }.prefix(20)
        }
        var scored: [(CommandInfo, Int)] = []
        for c in all where available(c.id) {
            var s = 0
            let title = c.title.lowercased()
            // An exact typed alias always wins: its bonus exceeds the largest possible sum of the other terms.
            if aliases.contains(where: { $0.value == c.id && $0.key.lowercased() == q }) { s += 10_000 }
            if title == q { s += 900 }
            if title.hasPrefix(q) { s += 500 }
            if title.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { s += 300 }
            if title.contains(q) { s += 200 }
            if c.keywords.contains(where: { $0.contains(q) }) { s += 150 }
            if c.help.lowercased().contains(q) { s += 50 }
            if s > 0, let r = recent.firstIndex(of: c.id) { s += 100 - r }
            if s > 0 { scored.append((c, s)) }
        }
        return scored.sorted { ($0.1, $1.0.title) > ($1.1, $0.0.title) }.map(\.0)
    }
}
