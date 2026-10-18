import Foundation
import ArcusGeometry
import ArcusDomain

/// Create Similar: starts the placement tool that makes elements like the selected one, with its type preselected.
public enum CreateSimilar {
    public struct Plan: Sendable, Equatable {
        /// The placement command to run.
        public var command: CommandID
        /// Type-selector entries to set before the tool starts (category → type).
        public var types: [Category: ElementID]
    }

    /// Categories placed by the Component tool; its type selector is keyed by `.furniture` as well as the category.
    static let componentCategories: Set<Category> = Set(Category.componentCategories) // W2-LIB: library categories

    /// The placement command and type for an element, or nil when the element can't be placed again with a tool.
    public static func plan(for e: Element, _ model: BIMModel) -> Plan? {
        guard let command = command(for: e, model) else { return nil }
        var types: [Category: ElementID] = [:]
        if let t = e.typeID, model[t]?.typeData != nil {
            types[e.category] = t
            if componentCategories.contains(e.category) { types[.furniture] = t }
        }
        return Plan(command: command, types: types)
    }

    static func command(for e: Element, _ model: BIMModel) -> CommandID? {
        switch e.data {
        case .wall(let w): return w.location.asArc != nil ? .wallArc : .wall
        case .insert: return e.category == .doors ? .door : e.category == .windows ? .window : nil
        case .component: return componentCategories.contains(e.category) ? .component : nil
        case .column: return e.category == .structuralColumns ? .structuralColumn : .column
        case .beam: return .beam
        case .slab:
            switch e.category {
            case .floors: return .floor
            case .ceilings: return .ceiling
            case .buildingPads: return .buildingPad
            default: return nil
            }
        case .roof: return .roofFootprint
        case .stair(let s):
            switch s.shape {
            case .straight: return .stairStraight
            case .lShaped: return .stairL
            case .uShaped: return .stairU
            }
        case .railing: return .railing
        case .room: return e.category == .areas ? .area : e.category == .spaces ? .space : .room // F5: spaces
        case .modelLine:
            switch e.category {
            case .detailLines: return e.ownerViewID == nil ? .modelLine : .detailLine
            case .roomSeparationLines: return .roomSeparator
            case .spaceSeparationLines: return .spaceSeparator // F5
            case .areaBoundaryLines: return .areaBoundary
            case .propertyLines: return .propertyLine
            default: return nil
            }
        case .grid: return .grid
        case .level: return .level
        case .referencePlane: return .referencePlane
        case .topography(let t): return t.solid == nil ? .toposurface : (t.boundary == nil ? .toposolid : nil) // BL-SITE
        case .dimension(let d):
            switch d.kind {
            case .linear: return .linearDimension
            case .aligned: return .alignedDimension
            case .angular: return .angularDimension
            case .radial: return .radialDimension
            case .diameter: return .diameterDimension
            case .arcLength: return .arcLengthDimension
            }
        case .spot(let s):
            switch s.kind {
            case .elevation: return .spotElevation
            case .coordinate: return .spotCoordinate
            case .slope: return .spotSlope
            }
        case .tag(let t) where t.kind != nil: // W2-ANNOT: special tags start their own tool
            switch t.kind! {
            case .material: return .materialTag
            case .keynoteElement: return .keynoteElement
            case .keynoteMaterial: return .keynoteMaterial
            case .keynoteUser: return .keynoteUser
            case .treadNumber: return .treadNumber
            case .viewReference: return .viewReference
            case .spanDirection: return .spanDirection
            case .stairPath: return .stairPath
            case .scaleBar: return .scaleBar
            }
        case .tag(let t):
            switch model[t.taggedID]?.category {
            case .rooms?: return .roomTag
            case .areas?: return .areaTag
            case .spaces?: return .spaceTag // F5
            default: return .tagByCategory
            }
        case .textNote: return .textNote
        case .filledRegion(let f): return f.isMasking ? .maskingRegion : .filledRegion
        case .detailComponent(let d) where d.repeatEnd != nil: return .repeatingDetailComponent // W2-ANNOT
        case .detailComponent(let d) where d.legendTypeID != nil: return .legendComponent // W2-ANNOT
        case .detailComponent: return e.category == .detailComponents ? .detailComponent : .symbol
        case .revisionCloud: return .revisionCloud
        case .insulation: return .insulation
        default: return nil
        }
    }

    /// Carries settings of the source element that the new tool should repeat (line style, insulation width).
    @MainActor public static func configure(_ tool: any InteractiveTool, like e: Element) {
        if let t = tool as? LineTool {
            if let style = e.modelLine?.styleID { t.styleID = style }
            if let w = e.insulation?.width { t.insulationWidth = w }
        }
    }
}
