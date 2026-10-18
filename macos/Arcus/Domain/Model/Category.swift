import Foundation

/// Discipline grouping for categories, used by object styles and view discipline filters.
public enum CategoryClass: String, Codable, Sendable, CaseIterable {
    case model, datum, annotation, view, internal_
}

/// Element categories. Industry-standard BIM categories; Arcus names and groupings are its own.
public enum Category: String, Codable, Sendable, CaseIterable, Comparable {
    // Model
    case walls, doors, windows, floors, ceilings, roofs, rooms, areas, stairs, railings
    case columns, structuralColumns, structuralFraming, furniture, casework, genericModels
    case plumbingFixtures, specialtyEquipment
    case topography, buildingPads, parking
    case importedCAD, ifcReference, modelGroups
    // Datums
    case levels, grids, referencePlanes
    // Annotation
    case dimensions, textNotes, tags, spotElevations, spotCoordinates, spotSlopes
    case detailLines, filledRegions, maskingRegions, detailComponents, genericAnnotations
    case revisionClouds, sectionMarks, elevationMarks, callouts, roomSeparationLines
    case areaBoundaryLines, propertyLines, insulation, northArrows, detailGroups
    // Views & documentation
    case views, sheets, viewports, schedules, titleBlocks, scheduleGraphics
    // Internal / non-graphical
    case materials, phases, designOptions, revisions, families, elementTypes, projectInfo
    case constraints, lineStyles, fillPatterns, viewTemplates, filters, links, areaSchemes
    case curtainPanels, wallOpenings, shaftOpenings
    case ramps
    case scopeBoxes, projectBasePoint, surveyPoint, cameras
    case colorSchemes, colorFillLegends
    case lightingFixtures, electricalFixtures, mechanicalEquipment, planting, entourage, site // W2-LIB

    // RevitCraft port feature batches (Docs/RevitCraftPort.md §5): each adds its cases right after its marker.
    // F1 categories:
    case reveals


    // F2 categories:


    // F34 categories:


    // F5 categories:


    // F67 categories:


    // F810 categories:


    // F11 categories:


    // F1415 categories:



    public static func < (a: Category, b: Category) -> Bool { a.sortIndex < b.sortIndex }
    private var sortIndex: Int { Category.allCases.firstIndex(of: self) ?? 0 }

    public var categoryClass: CategoryClass {
        switch self {
        case .walls, .doors, .windows, .floors, .ceilings, .roofs, .rooms, .areas, .stairs, .railings,
             .columns, .structuralColumns, .structuralFraming, .furniture, .casework, .genericModels,
             .plumbingFixtures, .specialtyEquipment, .topography, .buildingPads, .parking, .importedCAD,
             .ifcReference, .modelGroups, .ramps:
            return .model
        case .curtainPanels, .wallOpenings, .shaftOpenings: // WP3
            return .model
        case .levels, .grids, .referencePlanes:
            return .datum
        case .dimensions, .textNotes, .tags, .spotElevations, .spotCoordinates, .spotSlopes, .detailLines,
             .filledRegions, .maskingRegions, .detailComponents, .genericAnnotations, .revisionClouds,
             .sectionMarks, .elevationMarks, .callouts, .roomSeparationLines, .areaBoundaryLines,
             .propertyLines, .insulation, .northArrows, .detailGroups, .colorFillLegends:
            return .annotation
        case .views, .sheets, .viewports, .schedules, .titleBlocks, .scheduleGraphics:
            return .view
        case .materials, .phases, .designOptions, .revisions, .families, .elementTypes, .projectInfo,
             .constraints, .lineStyles, .fillPatterns, .viewTemplates, .filters, .links, .areaSchemes, .colorSchemes:
            return .internal_
        case .scopeBoxes, .projectBasePoint, .surveyPoint: return .datum // WP6a
        case .cameras: return .annotation // WP6a
        case .lightingFixtures, .electricalFixtures, .mechanicalEquipment, .planting, .entourage, .site: return .model // W2-LIB
        case .reveals: return .model // F1
        }
    }

    public var isModel: Bool { categoryClass == .model }
    public var isAnnotation: Bool { categoryClass == .annotation }
    /// View-specific elements belong to exactly one view (annotations, detail items).
    public var isViewSpecific: Bool { categoryClass == .annotation && self != .propertyLines && self != .roomSeparationLines && self != .areaBoundaryLines }

    /// Categories users can schedule.
    public static let schedulable: [Category] = [
        .walls, .doors, .windows, .floors, .ceilings, .roofs, .rooms, .areas, .stairs, .railings, .columns,
        .structuralColumns, .structuralFraming, .furniture, .casework, .genericModels, .plumbingFixtures,
        .specialtyEquipment, .topography, .parking, .sheets, .views, .revisions, .ramps,
        .lightingFixtures, .electricalFixtures, .mechanicalEquipment, .planting, .entourage, .site, // W2-LIB
    ]
    /// Categories whose instances can be tagged.
    public static let taggable: [Category] = [
        .walls, .doors, .windows, .floors, .ceilings, .roofs, .rooms, .areas, .stairs, .railings, .columns,
        .structuralColumns, .structuralFraming, .furniture, .casework, .genericModels, .plumbingFixtures, .specialtyEquipment, .ramps,
        .lightingFixtures, .electricalFixtures, .mechanicalEquipment, .planting, .entourage, .site, .parking, // W2-LIB
    ]

    public var displayName: String {
        switch self {
        case .walls: "Walls"
        case .doors: "Doors"
        case .windows: "Windows"
        case .floors: "Floors"
        case .ceilings: "Ceilings"
        case .roofs: "Roofs"
        case .rooms: "Rooms"
        case .areas: "Areas"
        case .stairs: "Stairs"
        case .railings: "Railings"
        case .columns: "Columns"
        case .structuralColumns: "Structural Columns"
        case .structuralFraming: "Structural Framing"
        case .furniture: "Furniture"
        case .casework: "Casework"
        case .genericModels: "Generic Models"
        case .plumbingFixtures: "Plumbing Fixtures"
        case .specialtyEquipment: "Specialty Equipment"
        case .topography: "Topography"
        case .buildingPads: "Building Pads"
        case .parking: "Parking"
        case .importedCAD: "Imported CAD"
        case .ifcReference: "IFC Reference"
        case .modelGroups: "Model Groups"
        case .levels: "Levels"
        case .grids: "Grids"
        case .referencePlanes: "Reference Planes"
        case .dimensions: "Dimensions"
        case .textNotes: "Text Notes"
        case .tags: "Tags"
        case .spotElevations: "Spot Elevations"
        case .spotCoordinates: "Spot Coordinates"
        case .spotSlopes: "Spot Slopes"
        case .detailLines: "Detail Lines"
        case .filledRegions: "Filled Regions"
        case .maskingRegions: "Masking Regions"
        case .detailComponents: "Detail Components"
        case .genericAnnotations: "Generic Annotations"
        case .revisionClouds: "Revision Clouds"
        case .sectionMarks: "Sections"
        case .elevationMarks: "Elevations"
        case .callouts: "Callouts"
        case .roomSeparationLines: "Room Separation Lines"
        case .areaBoundaryLines: "Area Boundary Lines"
        case .propertyLines: "Property Lines"
        case .insulation: "Insulation"
        case .northArrows: "North Arrows"
        case .detailGroups: "Detail Groups"
        case .views: "Views"
        case .sheets: "Sheets"
        case .viewports: "Viewports"
        case .schedules: "Schedules"
        case .titleBlocks: "Title Blocks"
        case .scheduleGraphics: "Schedule Graphics"
        case .materials: "Materials"
        case .phases: "Phases"
        case .designOptions: "Design Options"
        case .revisions: "Revisions"
        case .families: "Families"
        case .elementTypes: "Types"
        case .projectInfo: "Project Information"
        case .constraints: "Constraints"
        case .lineStyles: "Line Styles"
        case .fillPatterns: "Fill Patterns"
        case .viewTemplates: "View Templates"
        case .filters: "Filters"
        case .links: "Links"
        case .areaSchemes: "Area Schemes"
        case .scopeBoxes: "Scope Boxes" // WP6a
        case .projectBasePoint: "Project Base Point"
        case .surveyPoint: "Survey Point"
        case .cameras: "Cameras"
        case .colorSchemes: "Color Schemes"
        case .colorFillLegends: "Color Fill Legends"
        case .ramps: "Ramps"
        case .curtainPanels: "Curtain Panels"
        case .wallOpenings: "Wall Openings"
        case .shaftOpenings: "Shaft Openings"
        case .lightingFixtures: "Lighting Fixtures" // W2-LIB
        case .electricalFixtures: "Electrical Fixtures"
        case .mechanicalEquipment: "Mechanical Equipment"
        case .planting: "Planting"
        case .entourage: "Entourage"
        case .site: "Site"
        case .reveals: "Reveals" // F1
        }
    }

    /// Singular noun for status messages ("1 Wall selected").
    public var singularName: String {
        switch self {
        case .walls: "Wall"
        case .doors: "Door"
        case .windows: "Window"
        case .floors: "Floor"
        case .ceilings: "Ceiling"
        case .roofs: "Roof"
        case .rooms: "Room"
        case .areas: "Area"
        case .stairs: "Stair"
        case .railings: "Railing"
        case .columns: "Column"
        case .structuralColumns: "Structural Column"
        case .structuralFraming: "Beam"
        case .furniture: "Furniture"
        case .casework: "Casework"
        case .genericModels: "Generic Model"
        case .plumbingFixtures: "Plumbing Fixture"
        case .specialtyEquipment: "Specialty Equipment"
        case .topography: "Toposurface"
        case .buildingPads: "Building Pad"
        case .parking: "Parking"
        case .importedCAD: "CAD Import"
        case .ifcReference: "IFC Reference"
        case .modelGroups: "Model Group"
        case .levels: "Level"
        case .grids: "Grid"
        case .referencePlanes: "Reference Plane"
        case .dimensions: "Dimension"
        case .textNotes: "Text Note"
        case .tags: "Tag"
        case .spotElevations: "Spot Elevation"
        case .spotCoordinates: "Spot Coordinate"
        case .spotSlopes: "Spot Slope"
        case .detailLines: "Detail Line"
        case .filledRegions: "Filled Region"
        case .maskingRegions: "Masking Region"
        case .detailComponents: "Detail Component"
        case .genericAnnotations: "Symbol"
        case .revisionClouds: "Revision Cloud"
        case .sectionMarks: "Section"
        case .elevationMarks: "Elevation"
        case .callouts: "Callout"
        case .roomSeparationLines: "Room Separation Line"
        case .areaBoundaryLines: "Area Boundary Line"
        case .propertyLines: "Property Line"
        case .insulation: "Insulation"
        case .northArrows: "North Arrow"
        case .detailGroups: "Detail Group"
        case .views: "View"
        case .sheets: "Sheet"
        case .viewports: "Viewport"
        case .schedules: "Schedule"
        case .titleBlocks: "Title Block"
        case .scheduleGraphics: "Schedule Graphic"
        case .materials: "Material"
        case .phases: "Phase"
        case .designOptions: "Design Option"
        case .revisions: "Revision"
        case .families: "Family"
        case .elementTypes: "Type"
        case .projectInfo: "Project Information"
        case .constraints: "Constraint"
        case .lineStyles: "Line Style"
        case .fillPatterns: "Fill Pattern"
        case .viewTemplates: "View Template"
        case .filters: "Filter"
        case .links: "Link"
        case .areaSchemes: "Area Scheme"
        case .scopeBoxes: "Scope Box" // WP6a
        case .projectBasePoint: "Project Base Point"
        case .surveyPoint: "Survey Point"
        case .cameras: "Camera"
        case .colorSchemes: "Color Scheme"
        case .colorFillLegends: "Color Fill Legend"
        case .ramps: "Ramp"
        case .curtainPanels: "Curtain Panel"
        case .wallOpenings: "Wall Opening"
        case .shaftOpenings: "Shaft Opening"
        case .lightingFixtures: "Lighting Fixture" // W2-LIB
        case .electricalFixtures: "Electrical Fixture"
        case .mechanicalEquipment: "Mechanical Equipment"
        case .planting: "Planting"
        case .entourage: "Entourage"
        case .site: "Site Component"
        case .reveals: "Reveal" // F1
        }
    }

    /// Whether elements of this category bound rooms by default.
    public var defaultRoomBounding: Bool {
        switch self {
        case .walls, .floors, .ceilings, .roofs, .columns, .structuralColumns, .roomSeparationLines: true
        default: false
        }
    }

    /// Whether this category is cut in plan views (versus shown in projection only).
    public var isCuttable: Bool {
        switch self {
        case .walls, .floors, .ceilings, .roofs, .stairs, .railings, .columns, .structuralColumns, .structuralFraming,
             .doors, .windows, .topography, .buildingPads, .genericModels, .casework, .ramps:
            true
        default: false
        }
    }
}

extension Category: Identifiable {
    public var id: String { rawValue }
}

// W2-LIB: loadable-component categories (placed with the Component tool and shown in the Component Library).
extension Category {
    /// Categories whose family instances the Component tool places; the type selector lists all of them.
    public static let componentCategories: [Category] = [
        .furniture, .casework, .plumbingFixtures, .genericModels, .specialtyEquipment,
        .lightingFixtures, .electricalFixtures, .mechanicalEquipment, .planting, .entourage, .site, .parking,
    ]
    public var isComponentCategory: Bool { Category.componentCategories.contains(self) }
}
