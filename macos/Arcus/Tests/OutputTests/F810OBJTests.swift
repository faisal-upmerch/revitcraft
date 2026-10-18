import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusOutput

/// F810: View ▸ Presentation ▸ Export OBJ.
@Suite("F810 OBJ export")
struct F810OBJTests {
    @Test func exportsModelGeometryWithMaterials() throws {
        let (base, ids) = ProjectTemplates.make(.architectural, units: .metric)
        let tx = TransactionContext(model: base, name: "Walls")
        let level = ids.levels[0]
        let type = ids.wallTypes["Generic - 200mm"]
        let wall = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(0, 0), Vec2(4, 0))), topLevelID: ids.levels[1])), typeID: type, levelID: level)
        _ = tx.create(.walls, data: .wall(WallData(location: .line(Segment2(Vec2(4, 0), Vec2(4, 3))), topLevelID: ids.levels[1])), typeID: type, levelID: level)
        let m = try tx.commit().model
        #expect(OBJExporter.elements(m).map(\.id).contains(wall))
        let out = OBJExporter.export(m, mtlName: "Model.mtl")
        #expect(out.elementCount == 2 && out.triangleCount > 0)
        #expect(out.obj.hasPrefix("# Arcus OBJ export") && out.obj.contains("mtllib Model.mtl"))
        let usemtl = out.obj.split(separator: "\n").filter { $0.hasPrefix("usemtl ") }.map { String($0.dropFirst(7)) }
        #expect(!usemtl.isEmpty)
        for name in Set(usemtl) { #expect(out.mtl.contains("newmtl \(name)\n")) }
        // Y up: wall heights become y; plan y becomes −z.
        let verts = out.obj.split(separator: "\n").filter { $0.hasPrefix("v ") }.map { $0.split(separator: " ").dropFirst().compactMap { Double($0) } }
        let top = m.elevation(ofLevel: ids.levels[1]) - m.elevation(ofLevel: level)
        #expect(verts.allSatisfy { $0.count == 3 })
        #expect(abs((verts.map { $0[1] }.max() ?? 0) - (m.elevation(ofLevel: level) + top)) < 1e-3)
        #expect((verts.map { $0[2] }.min() ?? 0) < -2.9)
        // Faces index existing vertices.
        let faces = out.obj.split(separator: "\n").filter { $0.hasPrefix("f ") }
        #expect(faces.count == out.triangleCount)
        let maxIndex = faces.flatMap { $0.split(separator: " ").dropFirst().compactMap { Int($0.split(separator: "/").first ?? "") } }.max() ?? 0
        #expect(maxIndex == verts.count)
        // Writing puts the .mtl beside the .obj.
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("F810OBJ-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try OBJExporter.write(m, to: dir.appendingPathComponent("House.obj"))
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("House.mtl").path))
        #expect(try String(contentsOf: dir.appendingPathComponent("House.obj"), encoding: .utf8).contains("mtllib House.mtl"))
    }
}
