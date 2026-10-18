import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

/// W2-DWG: survey points from CAD contour drawings (Toposurface ▸ from Import).
@Suite("CAD site points")
struct CADSitePointsTests {
    /// Millimeter drawing with two contour polylines (LWPOLYLINE elevation 38) on C-TOPO, a spot height on C-SPOT and a
    /// flat title line on A-ANNO.
    static func contourDXF() -> Data {
        DXFText.minimal(units: 4) { t in
            t.seq([(0, "LWPOLYLINE"), (8, "C-TOPO"), (90, 3), (70, 0), (38, 1000), (10, 0), (20, 0), (10, 10000), (20, 0), (10, 20000), (20, 0)])
            t.seq([(0, "LWPOLYLINE"), (8, "C-TOPO"), (90, 3), (70, 0), (38, 2000), (10, 0), (20, 10000), (10, 10000), (20, 12000), (10, 20000), (20, 10000)])
            t.seq([(0, "POINT"), (8, "C-SPOT"), (10, 5000), (20, 5000), (30, 1500)])
            t.seq([(0, "LINE"), (8, "A-ANNO"), (10, 0), (20, -2000), (30, 0), (11, 20000), (21, -2000), (31, 0)])
        }.data
    }

    @Test func pointsAndLayerSummary() throws {
        let doc = try DXFReader.read(Self.contourDXF(), fileName: "site.dxf")
        let all = CADSitePoints.points(in: doc)
        #expect(all.count == 9)
        let topo = CADSitePoints.points(in: doc, layers: ["c-topo"])
        #expect(topo.count == 6 && Set(topo.map(\.z)) == [1000, 2000])
        let layers = CADSitePoints.layers(in: doc)
        #expect(layers.map(\.name) == ["C-SPOT", "C-TOPO", "A-ANNO"], "layers with elevations first")
        #expect(layers.first { $0.name == "A-ANNO" }?.elevations == 0)
        #expect(layers.first { $0.name == "C-TOPO" }?.points == 6)
    }

    @Test func linkedDrawingMapsToModelCoordinates() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arcus-sitepts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("site survey.dxf")
        try Self.contourDXF().write(to: url)
        let (m0, _) = templateModel()
        var o = CADImportOptions()
        o.isLink = true
        let tx = TransactionContext(model: m0, name: "Link")
        let (id, _) = try CADLinkService.place(url: url, bookmark: nil, options: o, projectSurveyOrigin: .zero, in: tx, progress: { _ in }, isCancelled: { false })
        let m = try tx.commit().model
        let ld = try #require(m[id]?.link)
        let doc = try CADSitePoints.readSource(url)
        let pts = CADSitePoints.modelPoints(for: ld, drawing: m.referenceDrawings[ld.contentKey], document: doc, layers: ["C-TOPO", "C-SPOT"])
        #expect(pts.count == 7)
        // Origin to origin: drawing (10000, 12000) mm → model (10, 12) m at elevation 2 m.
        #expect(pts.contains { $0.xy.distance(to: Vec2(10, 12)) < 1e-6 && abs($0.z - 2) < 1e-9 })
        #expect(pts.contains { $0.xy.distance(to: Vec2(5, 5)) < 1e-6 && abs($0.z - 1.5) < 1e-9 })

        // The points make a toposurface.
        let tx2 = TransactionContext(model: m, name: "Topo")
        let (topo, kept) = try SiteOperations.createToposurface(pts, in: tx2)
        let m2 = try tx2.commit().model
        #expect(kept == 7 && m2[topo]?.topography?.points.count == 7)
    }
}
