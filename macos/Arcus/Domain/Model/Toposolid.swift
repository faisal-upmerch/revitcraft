import Foundation
import ArcusGeometry

// BL-SITE: toposolids — the primary site element. A toposolid is a topography element (category Topography) whose
// `TopographyData.solid` is set: its survey points define the top surface, `outline` its plan extent, and its type's
// compound structure the layers below the surface. A sub-division is a thin layered solid on a host toposolid
// (`hostID`), bounded by `TopographyData.boundary`, that follows the host's top surface.

/// Solid definition of a toposolid or of a toposolid sub-division.
public struct ToposolidData: Hashable, Codable, Sendable {
    /// Plan outline, counter-clockwise. Nil = the convex hull of the survey points (toposolids created from points).
    public var outline: [Vec2]?
    /// Sub-divisions only: thickness above (positive) or into (negative) the host's top surface.
    public var subdivisionHeight: Double?
    /// Earthwork recorded by Excavate (m³), accumulated over excavations; shown in Properties and schedules.
    public var cutVolume: Double?
    public var fillVolume: Double?
    public init(outline: [Vec2]? = nil, subdivisionHeight: Double? = nil) {
        self.outline = outline; self.subdivisionHeight = subdivisionHeight
    }
}

extension Element {
    /// A toposolid (not a sub-division).
    public var isToposolid: Bool { topography?.solid != nil && topography?.boundary == nil }
    /// A sub-division of a toposolid.
    public var isToposolidSubdivision: Bool { topography?.solid != nil && topography?.boundary != nil }
    /// A legacy toposurface (not a sub-region, not a toposolid).
    public var isLegacyToposurface: Bool { topography != nil && topography?.solid == nil && topography?.boundary == nil }
}

/// Toposolid types: compound structures (top → bottom) whose first layer marked variable absorbs the terrain's relief.
public enum ToposolidTypes {
    /// Type parameter marking sub-division types (value "subdivision").
    public static let kindKey = ParameterID("toposolid.kind")

    /// The toposolid types in the model; sub-division types when `subdivision`.
    public static func types(_ model: BIMModel, subdivision: Bool) -> [Element] {
        model.types(for: .topography).filter {
            $0.typeData?.systemFamily == .toposolid && ($0.typeData?.params[kindKey]?.textValue == "subdivision") == subdivision
        }
    }

    /// Returns the default toposolid and sub-division types, creating them (and their materials) on first use.
    /// Metric: "Toposolid 1500mm" (300 mm topsoil over 1200 mm variable earth) and "Sub-Division - Paving 100mm".
    /// Imperial: "Toposolid 5'-0\"" and "Sub-Division - Paving 4\"".
    @discardableResult
    public static func ensureDefaults(in tx: TransactionContext) -> (solid: ElementID, subdivision: ElementID) {
        let imperial = tx.model.units.system == .imperial
        func material(_ name: String, _ cls: MaterialClass, _ hex: UInt32) -> ElementID {
            if let m = tx.model.elements(.materials).first(where: { $0.name == name }) { return m.id }
            return tx.create(.materials, name: name, data: .material(MaterialData(materialClass: cls, color: RGBColor(hex: hex))))
        }
        let solid: ElementID
        if let t = types(tx.model, subdivision: false).first { solid = t.id } else {
            let topsoil = material("Topsoil", .earth, 0x6E5B3E), earth = material("Earth", .earth, 0x8A7556)
            var fixed = AssemblyLayer(function: .finish1, materialID: topsoil, thickness: imperial ? 0.3048 : 0.3)
            fixed.isVariable = false
            var variable = AssemblyLayer(function: .structure, materialID: earth, thickness: imperial ? 4 * 0.3048 : 1.2)
            variable.isVariable = true
            let td = TypeData(instanceCategory: .topography, systemFamily: .toposolid, familyName: "Toposolid",
                              assembly: CompoundAssembly(layers: [fixed, variable]))
            solid = tx.create(.elementTypes, name: imperial ? "Toposolid 5'-0\"" : "Toposolid 1500mm", data: .type(td))
        }
        let sub: ElementID
        if let t = types(tx.model, subdivision: true).first { sub = t.id } else {
            let paving = material("Stone Paving", .stone, 0xB3ABA0), gravel = material("Gravel", .stone, 0x9C968C)
            var td = TypeData(instanceCategory: .topography, systemFamily: .toposolid, familyName: "Toposolid",
                              assembly: CompoundAssembly(layers: [AssemblyLayer(function: .finish1, materialID: paving, thickness: imperial ? 0.0508 : 0.05),
                                                                  AssemblyLayer(function: .structure, materialID: gravel, thickness: imperial ? 0.0508 : 0.05)]))
            td.params[kindKey] = .text("subdivision")
            sub = tx.create(.elementTypes, name: imperial ? "Sub-Division - Paving 4\"" : "Sub-Division - Paving 100mm", data: .type(td))
        }
        return (solid, sub)
    }

    /// The layers of a toposolid's type (a single 1 m earth layer when the type is missing or has none).
    public static func assembly(of e: Element, _ model: BIMModel) -> CompoundAssembly {
        if let a = model.typeData(of: e)?.assembly, !a.layers.isEmpty, a.totalThickness > Tolerance.length { return a }
        return CompoundAssembly(layers: [AssemblyLayer(function: .structure, materialID: nil, thickness: 1)])
    }
}
