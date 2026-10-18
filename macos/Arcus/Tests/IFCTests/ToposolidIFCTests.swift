import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusIFC

/// BL-SITE (ARCUS-070): toposolids export as terrain (IfcGeographicElement in the site) with a closed body per layer.
@Suite("Toposolid IFC export")
struct ToposolidIFCTests {
    @Test func toposolidExportsAsGeographicElementInTheSite() throws {
        let (m0, _) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: m0, name: "Site")
        let solid = try ToposolidOperations.create(outline: .rectangle(Rect2(min: Vec2(-10, -10), max: Vec2(20, 15))), elevation: -0.3, in: tx)
        let sub = try ToposolidOperations.subdivide(solid, boundary: .rectangle(Rect2(min: .zero, max: Vec2(5, 5))), in: tx)
        let m = try TestModel.fixGUIDs(try tx.commit().model)
        let (d, _) = try TestModel.export(m, TestModel.options(.ifc4))
        let f = try TestModel.parse(d)
        func entity(_ id: ElementID) -> STEPEntity? {
            let g = m[id]!.ifcGUID.value
            return f.order.lazy.compactMap { f[$0] }.first { $0[0].stringValue == g }
        }
        let e = try #require(entity(solid))
        #expect(e.type == "IFCGEOGRAPHICELEMENT")
        #expect(entity(sub)?.type == "IFCGEOGRAPHICELEMENT")
        let site = try #require(f.all("IFCSITE").first)
        let rel = try #require(f.all("IFCRELCONTAINEDINSPATIALSTRUCTURE").first { $0[5].refValue == site.id })
        #expect(Set(rel[4].listValue ?? []).isSuperset(of: [.ref(e.id), .ref(entity(sub)!.id)]))
    }
}
