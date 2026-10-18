import Foundation
import ArcusGeometry

/// BL-SITE: toposolid and sub-division parameters and quantities (appended by `HostedProfileParameters.extra`).
enum ToposolidParameters {
    typealias P = BuiltInParameter

    static let subdivisionHeight = P("toposolid.subdivisionHeight", "Height", .length, .dimensions,
                                     tooltip: "Thickness of the sub-division above the host's surface; negative values go into the host.",
                                     get: { e, _ in e.topography?.solid?.subdivisionHeight.map { .double($0) } },
                                     set: { e, v, _ in
                                         guard let d = v.doubleValue, d.isFinite else { throw ParameterError("“Height” needs a number.") }
                                         guard abs(d) >= 0.001 else { throw ParameterError("“Height” must be at least 1 mm up or down.") }
                                         e.topography?.solid?.subdivisionHeight = d
                                     })
    static let cutVolume = P("toposolid.cut", "Cut", .volume, .dimensions, tooltip: "Earth removed by Excavate.",
                             get: { e, _ in e.topography?.solid.map { .double($0.cutVolume ?? 0) } })
    static let fillVolume = P("toposolid.fill", "Fill", .volume, .dimensions, tooltip: "Earth added by Excavate.",
                              get: { e, _ in e.topography?.solid.map { .double($0.fillVolume ?? 0) } })
    static let netCutFill = P("toposolid.net", "Net Cut/Fill", .volume, .dimensions, tooltip: "Cut minus fill.",
                              get: { e, _ in e.topography?.solid.map { .double(($0.cutVolume ?? 0) - ($0.fillVolume ?? 0)) } })

    /// Type selector, volume, thickness and earthwork for toposolids; the sub-division height for sub-divisions.
    static func extra(for e: Element) -> [P] {
        guard e.topography?.solid != nil else { return [] }
        var list = [BuiltInCatalog.familyName, BuiltInCatalog.typeName, BuiltInCatalog.familyAndType,
                    BuiltInCatalog.quantityVolume, BuiltInCatalog.quantityThickness]
        if e.isToposolidSubdivision { list.append(subdivisionHeight) } else { list += [cutVolume, fillVolume, netCutFill] }
        return list
    }

    /// Volume, thickness, bottom elevation and per-layer material volumes of a toposolid or sub-division.
    static func quantities(_ e: Element, _ model: BIMModel, _ q: inout ElementQuantities) {
        let parts = ToposolidGeometry.meshParts(e, model)
        guard !parts.isEmpty else { return }
        q.volume = parts.reduce(0) { $0 + abs($1.mesh.signedVolume) }
        q.thickness = ToposolidGeometry.thickness(e, model)
        let b = parts.reduce(Box3.empty) { $0.union($1.mesh.bounds) }
        if !b.isEmpty { q.elevationBottom = b.min.z; q.elevationTop = b.max.z }
        var byMaterial: [ElementID?: Double] = [:]
        var order: [ElementID?] = []
        for p in parts {
            if byMaterial[p.materialID] == nil { order.append(p.materialID) }
            byMaterial[p.materialID, default: 0] += abs(p.mesh.signedVolume)
        }
        let area = q.area ?? 0
        q.materials = order.map { MaterialQuantity(materialID: $0, area: area, volume: byMaterial[$0] ?? 0) }
    }
}
