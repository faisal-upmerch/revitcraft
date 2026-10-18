import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusIFC

/// F67: Link IFC reads an IFC model as display geometry for a read-only link.
@Suite("F67 Link IFC")
struct F67IFCLinkTests {
    @Test func linkedIFCKeepsExactGeometryWithHostCategories() throws {
        let data = try TestModel.fixture("small-ifc2x3.ifc")
        let (parts, count, report) = try IFCLink.content(data, fileName: "small-ifc2x3.ifc")
        #expect(count > 0 && !parts.isEmpty)
        #expect(report.nativeCounts["walls"] == nil, "nothing becomes a native element")
        #expect(parts.contains { $0.category == .walls }, "IfcWall reference geometry draws with the host's wall styles")
        #expect(parts.allSatisfy { !$0.mesh.mesh.isEmpty })
    }

    @Test func exportedProjectsLinkBack() throws {
        let built = try TestModel.build()
        let ifc = try #require(try IFCExporter.export(built.model, options: IFCExportOptions()).files.first?.data)
        let (parts, count, _) = try IFCLink.content(ifc, fileName: "golden.ifc")
        #expect(count >= 7 && parts.contains { $0.category == .walls } && parts.contains { $0.category == .roofs })
        // The linked walls sit where the source walls were (internal origin to internal origin).
        let b = parts.filter { $0.category == .walls }.reduce(Box3.empty) { $0.union($1.mesh.mesh.bounds) }
        #expect(abs(b.min.x - built.model.elements(.walls).flatMap { ElementMeshes.parts($0, built.model) }.reduce(Box3.empty) { $0.union($1.mesh.bounds) }.min.x) < 0.01)
    }
}
