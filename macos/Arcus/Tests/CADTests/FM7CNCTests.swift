import Foundation
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

/// FM7: CNC Export of the sample base cabinet: DXF per part (inches, layers OUTLINE, DRILL_<dia>_<depth>, GRAIN, LABEL,
/// face B separate or on B_ layers), per nested sheet (SHEET plus every part), and the CSV part list.
@Suite("FM7 CNC export")
struct FM7CNCTests {
    static let inch = 0.0254
    static let cabinet = FurnitureSamples.baseCabinetModel()!

    static func layer(_ e: CADEntity) -> String {
        switch e {
        case .line(_, _, let p), .polyline(_, let p), .circle(_, _, let p), .text(_, let p), .mtext(_, let p), .arc(_, _, _, _, let p): return p.layer
        default: return ""
        }
    }

    @Test func partDXFIsInInchesWithCNCLayersAndPartCoordinates() throws {
        let m = Self.cabinet
        let p = try #require(FurnitureCNC.programs(m).first { $0.part.mark == "P1" })
        let doc = try DXFReader.read(CNCExport.dxf(p.faceA), fileName: "P1.dxf")
        #expect(doc.units == .inches)
        let names = Set(doc.layers.map(\.name))
        #expect(names.isSuperset(of: ["OUTLINE", "GRAIN", "LABEL"]))
        #expect(names.contains { $0.hasPrefix("DRILL_") || $0.hasPrefix("HDRILL_") })
        // The outline is the cut size, from the origin.
        let outline = try #require(doc.modelSpace.compactMap { e -> CADPolyline? in if case .polyline(let pl, let pr) = e, pr.layer == "OUTLINE" { return pl }; return nil }.first)
        #expect(outline.closed)
        let xs = outline.points.map(\.x), ys = outline.points.map(\.y)
        #expect(abs((xs.min() ?? 1)) < 1e-4 && abs((ys.min() ?? 1)) < 1e-4)
        #expect(abs((xs.max() ?? 0) - p.part.length / Self.inch) < 1e-3 && abs((ys.max() ?? 0) - p.part.width / Self.inch) < 1e-3)
        // Holes on DRILL layers, inside the part, with the layer's diameter.
        for e in doc.modelSpace {
            guard case .circle(let c, let r, let pr) = e else { continue }
            #expect(pr.layer.hasPrefix("DRILL_"))
            let dia = Double(pr.layer.split(separator: "_")[1]) ?? 0
            #expect(abs(2 * r - dia) < 0.002)
            #expect(c.x >= -1e-4 && c.x <= p.part.length / Self.inch + 1e-4 && c.y >= -1e-4 && c.y <= p.part.width / Self.inch + 1e-4)
        }
        #expect(doc.modelSpace.contains { if case .text(let t, let pr) = $0 { return pr.layer == "LABEL" && t.text == "P1" }; return false })
    }

    @Test func faceBGoesToItsOwnFileOrFlipLayers() throws {
        let m = Self.cabinet
        let withB = FurnitureCNC.programs(m).filter { $0.faceB != nil }
        #expect(!withB.isEmpty)
        let separate = CNCExport.files(m, .init(layout: .perPart, faceB: .separateFile))
        #expect(separate.count == FurnitureCNC.programs(m).count + withB.count)
        #expect(separate.contains { $0.name == withB[0].name + "_B" })
        let flip = CNCExport.files(m, .init(layout: .perPart, faceB: .flipLayers))
        #expect(flip.count == FurnitureCNC.programs(m).count)
        let f = try #require(flip.first { $0.name == withB[0].name })
        #expect(f.drawing.layers.contains { $0.hasPrefix("B_") })
    }

    @Test func exportWritesFilesAndCSV() throws {
        let m = Self.cabinet
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fm7-cnc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try CNCExport.write(m, to: dir, options: .init(layout: .perSheet))
        let sheets = FurnitureFabrication.nesting(m).reduce(0) { $0 + $1.result.sheets.count }
        #expect(urls.filter { $0.pathExtension == "dxf" }.count == sheets)
        let csv = try String(contentsOf: try #require(urls.first { $0.pathExtension == "csv" }), encoding: .utf8)
        #expect(csv.hasPrefix("Mark,Part,Material,Thickness (in)"))
        // A nested sheet: the stock outline and an OUTLINE per part on it.
        let first = try #require(urls.first { $0.pathExtension == "dxf" })
        let doc = try DXFReader.read(try Data(contentsOf: first), fileName: first.lastPathComponent)
        let outlines = doc.modelSpace.filter { Self.layer($0) == "OUTLINE" }.count
        #expect(doc.modelSpace.contains { Self.layer($0) == "SHEET" })
        #expect(outlines > 0)
        // DWG without the bundled engine is refused with a reason.
        if DWGExporter.unavailableReason() != nil {
            #expect(throws: (any Error).self) { try CNCExport.write(m, to: dir, options: .init(layout: .perSheet, format: .dwg, includeCSV: false), dwgHelper: nil) }
        }
    }
}
