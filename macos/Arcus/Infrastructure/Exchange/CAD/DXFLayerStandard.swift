import Foundation
import ArcusDomain

// F13: DXF export layer naming (RevitCraft rc-core dxf.rs `LayerStandard`, `aia_layer`): the American Institute of
// Architects CAD layer guidelines (A-WALL, A-DOOR, A-GLAZ, S-GRID, A-ANNO-DIMS…) or one layer per category.

public enum DXFLayerStandard: String, CaseIterable, Sendable {
    case aia = "American Institute of Architects Standard (AIA)"
    case category = "Category names"

    /// The layer an item's graphics go on.
    public func layer(for item: GItem, _ model: BIMModel) -> String {
        switch self {
        case .category: return item.category.displayName
        case .aia: return Self.aiaLayer(item, model)
        }
    }

    /// AIA layer of an item: tags take their host's "-IDEN" layer, curtain walls "A-GLAZ-CWMG".
    static func aiaLayer(_ item: GItem, _ model: BIMModel) -> String {
        let e = model[item.elementID]
        switch item.category {
        case .walls: return e?.wall?.curtain != nil ? "A-GLAZ-CWMG" : "A-WALL"
        case .doors: return "A-DOOR"
        case .windows: return "A-GLAZ"
        case .curtainPanels: return "A-GLAZ-CWMG"
        case .floors: return "A-FLOR"
        case .ceilings: return "A-CLNG"
        case .roofs: return "A-ROOF"
        case .stairs: return "A-FLOR-STRS"
        case .ramps: return "A-FLOR-LEVL"
        case .railings: return "A-FLOR-HRAL"
        case .columns: return "A-COLS"
        case .structuralColumns: return "S-COLS"
        case .structuralFraming: return "S-BEAM"
        case .shaftOpenings, .wallOpenings: return "A-FLOR-OTLN"
        case .furniture: return "A-FURN"
        case .casework: return "A-FLOR-CASE"
        case .plumbingFixtures: return "P-SANR-FIXT"
        case .specialtyEquipment: return "A-FLOR-SPCL"
        case .genericModels, .modelGroups: return "A-GENM"
        case .lightingFixtures: return "E-LITE"
        case .electricalFixtures: return "E-POWR"
        case .mechanicalEquipment: return "M-EQPM"
        case .rooms: return "A-AREA-IDEN"
        case .areas, .areaBoundaryLines: return "A-AREA"
        case .roomSeparationLines: return "A-AREA-BNDY"
        case .grids: return "S-GRID"
        case .levels: return "S-GRID-IDEN"
        case .referencePlanes: return "A-ANNO-REFR"
        case .detailLines, .detailComponents, .insulation, .detailGroups: return "A-DETL"
        case .dimensions, .spotElevations, .spotCoordinates, .spotSlopes: return "A-ANNO-DIMS"
        case .textNotes: return "A-ANNO-TEXT"
        case .tags:
            switch model[e?.tag?.taggedID]?.category {
            case .doors?: return "A-DOOR-IDEN"
            case .windows?: return "A-GLAZ-IDEN"
            case .rooms?, .areas?: return "A-AREA-IDEN"
            case .walls?: return "A-WALL-IDEN"
            case .structuralColumns?, .structuralFraming?: return "S-ANNO-IDEN"
            default: return "A-ANNO-IDEN"
            }
        case .filledRegions, .maskingRegions: return "A-DETL-PATT"
        case .genericAnnotations, .northArrows: return "A-ANNO-SYMB"
        case .sectionMarks, .elevationMarks, .callouts: return "A-ANNO-SYMB"
        case .revisionClouds: return "A-ANNO-REVS"
        case .topography, .buildingPads: return "C-TOPO"
        case .site, .entourage: return "C-SITE"
        case .parking: return "C-PRKG"
        case .planting: return "L-PLNT"
        case .propertyLines: return "C-PROP-LINE"
        case .colorFillLegends: return "A-ANNO-LEGN"
        case .titleBlocks: return "G-ANNO-TTLB"
        case .viewports: return "G-ANNO-VPRT"
        case .importedCAD, .links: return "G-XREF"
        default: return item.category.displayName.replacingOccurrences(of: " ", with: "-").uppercased()
        }
    }
}
