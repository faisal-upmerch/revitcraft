import Foundation
import ArcusGeometry

// COMPD: group D's edge treatments in the existing Furniture tools.
// - Every type of a component with the Edge Profile role is an Edge Profile type (category Edge Profiles, family "Edge
//   Profile"): its Profile Shape, Size and Depth, so the Edge Profile tool (EP) cuts it and the Type Selector lists it.
// - Every type of a component with the Edge Banding role is an edge band material (cost per linear foot) with its
//   thickness; `applyEdgeBand` sets a part type's Edge Band Material and Edge Band Thickness from one.
// Both are created where missing when a Furniture document's standard types are (FurniturePartTypes.ensureStandard).

/// An edge band choice: a group D edge banding type as the material and thickness a part type's banding uses.
public struct EdgeBandSpec: Hashable, Sendable {
    /// The material's name: the component type's name ("PVC Edge Banding - 1 mm x 22 mm").
    public var name: String
    public var definitionID: String
    public var thickness: Double
    public var width: Double
    /// USD per linear foot.
    public var costPerFoot: Double
    public var finish: ComponentFinish
}

/// An Edge Profile type made from a group D cut profile.
public struct EdgeProfileTypeSpec: Hashable, Sendable {
    public var name: String
    public var definitionID: String
    public var shape: EdgeProfileShape
    public var size: Double
    public var depth: Double
    public var cost: Double
}

extension ComponentLibrary {
    /// The edge band choices from group D's edge banding components, in browser order.
    public static var edgeBands: [EdgeBandSpec] {
        groupD.filter { $0.roles.contains(.edgeBanding) }.flatMap { d in
            d.types.map { t in
                EdgeBandSpec(name: t.name, definitionID: d.id, thickness: t.values["Thickness"]?.doubleValue ?? 0, width: t.values["Band Width"]?.doubleValue ?? 0,
                             costPerFoot: t.cost, finish: d.materials.first?.finish ?? .hotMelt)
            }
        }
    }

    /// The Edge Profile types from group D's cut profiles.
    public static var edgeProfileTypes: [EdgeProfileTypeSpec] {
        groupD.filter { $0.roles.contains(.edgeProfile) }.flatMap { d in
            d.types.compactMap { t -> EdgeProfileTypeSpec? in
                guard let s = t.values["Profile Shape"]?.textValue.flatMap(EdgeProfileShape.init(rawValue:)) else { return nil }
                return EdgeProfileTypeSpec(name: t.name, definitionID: d.id, shape: s, size: t.values["Size"]?.doubleValue ?? 0,
                                           depth: t.values["Depth"]?.doubleValue ?? 0, cost: t.cost)
            }
        }
    }

    /// Creates group D's Edge Profile types and edge band materials where missing (idempotent).
    public static func ensureGroupDEdgeTypes(in tx: TransactionContext) {
        guard tx.model.isFurniture else { return }
        var materials = Set(tx.model.elements(.materials).map(\.name))
        let patterns = MaterialPatternDefaults.patternIndex(tx.model)
        for band in edgeBands where !materials.contains(band.name) {
            var m = band.finish.data
            m.description = "\(band.name), per linear foot"
            MaterialPatternDefaults.apply(to: &m, name: band.name, patterns: patterns)
            m.cost = band.costPerFoot
            m.costUnit = .linearFoot
            tx.create(.materials, name: band.name, data: .material(m))
            materials.insert(band.name)
        }
        let existing = Set(tx.model.types(for: .furnitureEdgeProfiles).map(\.name))
        for p in edgeProfileTypes where !existing.contains(p.name) {
            let params: [ParameterID: ParamValue] = [
                FurniturePartTypes.profileShape: .text(p.shape.rawValue), FurniturePartTypes.size: .double(p.size),
                FurniturePartTypes.grooveDepth: .double(p.depth), ComponentKit.definitionParam: .text(p.definitionID),
                ParameterID("type.cost"): .double(p.cost), ParameterID("type.manufacturer"): .text("Generic"),
            ]
            tx.create(.elementTypes, name: p.name, data: .type(TypeData(instanceCategory: .furnitureEdgeProfiles, familyName: "Edge Profile", params: params)))
        }
    }

    /// Sets a panel, shelf or front type's Edge Band Material and Edge Band Thickness to an edge band choice (creating
    /// its material if needed). Returns false when the band or the type isn't found.
    @discardableResult
    public static func applyEdgeBand(_ name: String, toType typeID: ElementID, in tx: TransactionContext) -> Bool {
        guard let band = edgeBands.first(where: { $0.name == name }), tx.model[typeID]?.typeData != nil else { return false }
        if !tx.model.elements(.materials).contains(where: { $0.name == band.name }) { ensureGroupDEdgeTypes(in: tx) }
        guard let mat = tx.model.elements(.materials).first(where: { $0.name == band.name })?.id else { return false }
        tx.update(typeID) { e in
            e.typeData?.params[FurniturePartTypes.edgeMaterial] = .ref(mat)
            e.typeData?.params[FurniturePartTypes.edgeThickness] = .double(band.thickness)
        }
        return true
    }
}
