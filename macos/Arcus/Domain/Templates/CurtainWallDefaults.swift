import Foundation
import ArcusGeometry

/// Starter curtain panel and curtain wall types (original Arcus content).
public enum CurtainWallDefaults {
    public static let wallFamily = "Curtain Wall"
    public static let panelFamily = "System Panel"

    /// Creates the starter curtain panel types and curtain wall types unless the model already has curtain wall types.
    /// Returns the created ids keyed "Family: Type".
    @discardableResult
    public static func populate(_ tx: TransactionContext) -> [String: ElementID] {
        let m = tx.model
        guard !m.types(for: .walls).contains(where: { $0.typeData?.curtain != nil }) else { return [:] }
        var ids: [String: ElementID] = [:]
        let glass = m.material(named: "Glass")?.id
        let aluminum = m.material(named: "Aluminum")?.id

        // Panel types (reuse existing ones by name, e.g. after the wall types were deleted).
        func panel(_ name: String, _ kind: CurtainPanelKind, _ thickness: Double, _ material: ElementID?) -> ElementID {
            if let t = m.type(category: .curtainPanels, family: panelFamily, name: name) { return t.id }
            var td = TypeData(instanceCategory: .curtainPanels, systemFamily: .curtainPanel, familyName: panelFamily)
            td.params[.curtainPanelKind] = .text(kind.rawValue)
            td.params[.curtainPanelThickness] = .double(thickness)
            if let material { td.params[.curtainPanelMaterial] = .ref(material) }
            let id = tx.create(.elementTypes, name: name, data: .type(td))
            ids["\(panelFamily): \(name)"] = id
            return id
        }
        let glazed = panel("Glazed", .glazed, 0.025, glass)
        _ = panel("Solid", .solid, 0.05, aluminum)
        _ = panel("Empty", .empty, 0.025, nil)

        func wall(_ name: String, _ spec: CurtainSpec, mark: String) {
            var td = TypeData(instanceCategory: .walls, systemFamily: .curtainWall, familyName: wallFamily)
            td.curtain = spec
            td.params[ParameterID("type.function")] = .text("Exterior")
            td.params[ParameterID("type.mark")] = .text(mark)
            ids["\(wallFamily): \(name)"] = tx.create(.elementTypes, name: name, data: .type(td))
        }
        let profile = MullionProfile(width: 0.05, depth: 0.15)
        wall("Curtain Wall", CurtainSpec(panelTypeID: glazed, mullion: profile, mullionMaterialID: aluminum), mark: "CW1")
        wall("Exterior Glazing", CurtainSpec(vertical: CurtainGridRule(layout: .fixedDistance, spacing: 1.5),
                                             horizontal: CurtainGridRule(layout: .fixedDistance, spacing: 3.0),
                                             panelTypeID: glazed, mullion: profile, mullionMaterialID: aluminum), mark: "CW2")
        wall("Storefront", CurtainSpec(vertical: CurtainGridRule(layout: .maximumSpacing, spacing: 1.8),
                                       horizontal: CurtainGridRule(layout: .fixedDistance, spacing: 2.4),
                                       panelTypeID: glazed, verticalMullions: true, horizontalMullions: true, borderMullions: true,
                                       mullion: profile, mullionMaterialID: aluminum), mark: "CW3")
        return ids
    }
}
