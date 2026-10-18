import Foundation
import ArcusGeometry
import ArcusDomain

extension IFCFileBuilder {
    /// Curtain walls export as IfcCurtainWall (axis only) aggregating one IfcPlate per non-empty panel and one IfcMember
    /// per mullion segment, each with its own body and material.
    func exportCurtainWall(_ e: Element, storey k: Int) {
        guard let w = e.wall, let f = WallGeometry.frame(e, model) else { return }
        let S = storeyTransform(k)
        let W = frame(origin: Vec3(w.location.start, z: f.baseZ), xDir: w.location.tangent(at: 0))
        let placement = localPlacement(relativeTo: storeyPlacement[k], S.inverse * W)
        let toLocal = W.inverse * Transform3.translation(-base)

        let axisPts = w.location.tessellate(chordTolerance: 0.01).map { toLocal.apply(Vec3($0, z: f.baseZ)).xy }
        let polyline = writer.add("IfcPolyline", [.refs(axisPts.map(point2))])
        let axisRep = writer.add("IfcShapeRepresentation", [.r(axisContext), .s("Axis"), .s("Curve2D"), .refs([polyline])])
        let ent = product(e, "IfcCurtainWall", placement: placement, shape: shape([axisRep]), tail: is4 ? [.e("NOTDEFINED")] : [])
        register(e, ent, storey: k)

        let g = e.ifcGUID.value
        var parts: [Int] = []
        func part(_ cls: String, _ seed: String, name: String, objectType: String?, mesh: Mesh, material: ElementID?, category: ArcusDomain.Category, predefined: String) {
            guard let body = meshItems([MeshPart(mesh: mesh, materialID: material)], toLocal: toLocal, category: category) else { return }
            let rep = writer.add("IfcShapeRepresentation", [.r(bodyContext), .s("Body"), .s(body.type), .refs(body.items)])
            let shp = writer.add("IfcProductDefinitionShape", [.null, .null, .refs([rep])])
            let pl = localPlacement(relativeTo: placement, .identity)
            let ent = writer.add(cls, [guid("\(g)/\(seed)"), .r(ownerHistory), .s(name), .null, .sOpt(objectType), .r(pl), .r(shp), .null]
                                 + (is4 ? [.e(predefined)] : []))
            if let material { associateMaterials([material], object: ent) }
            parts.append(ent)
        }
        for (p, mesh) in CurtainWallGeometry.panelSolids(e, model) {
            let typeName = model[p.typeID].map { t in t.typeData.map { "\($0.familyName): \(t.name)" } ?? t.name }
            part("IfcPlate", "panel/\(p.column)/\(p.row)", name: "Curtain Panel", objectType: typeName, mesh: mesh, material: p.materialID,
                 category: .curtainPanels, predefined: "CURTAIN_PANEL")
        }
        let mullionMaterial = CurtainWallGeometry.spec(e, model)?.mullionMaterialID
        for (m, mesh) in CurtainWallGeometry.mullionSolids(e, model) {
            let seed = "mullion/\(m.isVertical ? "v" : "h")/\(STEPFormat.real(m.position))/\(STEPFormat.real(m.from))"
            let profile = "Rectangular Mullion \(Int((m.profile.width * 1000).rounded())) x \(Int((m.profile.depth * 1000).rounded()))"
            part("IfcMember", seed, name: "Mullion", objectType: profile, mesh: mesh, material: mullionMaterial, category: .walls, predefined: "MULLION")
        }
        if !parts.isEmpty {
            writer.add("IfcRelAggregates", [guid("\(g)/aggregates/parts"), .r(ownerHistory), .null, .null, .r(ent), .refs(parts)])
        }

        if options.includePropertySets {
            var common: [(String, STEPValue)] = []
            if let typeName = model.type(of: e)?.name { common.append(("Reference", .identifier(typeName))) }
            if let ext = isExteriorWall(e) { common.append(("IsExternal", .boolean(ext))) }
            writePset(owner: g, name: "Pset_CurtainWallCommon", objects: [ent], props: common)
            writePset(owner: g, name: "Arcus_Parameters", objects: [ent], props: formattedParameters(Parameters.instanceEntries(e, model)))
        }
        if options.includeBaseQuantities {
            let q = QuantityEngine.quantities(for: e, in: model)
            var qs: [Int] = []
            for (n, t, v) in [("Length", "L", q.length), ("Height", "L", q.height), ("GrossSideArea", "A", q.area)] as [(String, String, Double?)] {
                guard let v, v.isFinite, v >= 0 else { continue }
                qs.append(writer.add(t == "L" ? "IfcQuantityLength" : "IfcQuantityArea", [.s(n), .null, .null, .d(v)] + (is4 ? [.null] : [])))
            }
            if !qs.isEmpty {
                let qto = writer.add("IfcElementQuantity", [guid("\(g)/qto"), .r(ownerHistory), .s(is4 ? "Qto_CurtainWallQuantities" : "BaseQuantities"), .null, .null, .refs(qs)])
                writer.add("IfcRelDefinesByProperties", [guid("\(g)/qto/rel"), .r(ownerHistory), .null, .null, .refs([ent]), .r(qto)])
            }
        }
        classify(e, entity: ent)
    }
}
