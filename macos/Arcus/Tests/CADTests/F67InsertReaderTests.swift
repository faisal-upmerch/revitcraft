import Foundation
import Compression
import Testing
import ArcusGeometry
import ArcusDomain
@testable import ArcusCAD

/// F67: the Insert tab's readers: point files, ASCII PLY, OBJ, gbXML and DWFx (zip + XPS fixed pages).
@Suite("F67 Insert readers")
struct F67InsertReaderTests {
    @Test func pointFilesSkipCountLinesAndThin() throws {
        let s = try PointFileReader.read("3\n1 2 3\n4,5,6,255,0,0\n7;8;9\n", maxPoints: 2)
        #expect(s.sourceCount == 3 && s.points.count == 2 && s.hasColor && s.unitScale == 1)
        #expect(s.points[0].0 == Vec3(1, 2, 3) && s.points[1].0 == Vec3(7, 8, 9))
        // Evidently millimetres.
        let mm = try PointFileReader.read("10000 2000 300\n10500 2000 310\n")
        #expect(mm.unitScale == 0.001 && abs(mm.points[0].0.x - 10) < 1e-12)
        let ft = try PointFileReader.read("10 0 0\n0 10 0\n", units: .feet)
        #expect(abs(ft.points[0].0.x - 3.048) < 1e-12)
        #expect(throws: InsertReadError.self) { try PointFileReader.read("hello\n") }
    }

    @Test func asciiPLYReadsPositionsAndColours() throws {
        let ply = """
        ply
        format ascii 1.0
        element vertex 2
        property float x
        property float y
        property float z
        property uchar red
        property uchar green
        property uchar blue
        end_header
        0 0 0 255 0 0
        1 2 3 0 0 255
        """
        let s = try PointFileReader.read(ply)
        #expect(s.points.count == 2 && s.hasColor && s.points[1].0 == Vec3(1, 2, 3) && s.points[1].1.2 == 255)
        #expect(throws: InsertReadError.self) { try PointFileReader.read("ply\nformat binary_little_endian 1.0\nelement vertex 1\nproperty float x\nend_header\n") }
    }

    @Test func objGroupsTurnZUp() throws {
        let groups = try OBJReader.read("o Tower\nv 0 0 0\nv 1 0 0\nv 0 3 0\nv 0 0 1\nf 1 2 3 4\ng Base\nf -4 -3 -2\n")
        #expect(groups.map(\.name) == ["Tower", "Base"])
        #expect(groups[0].mesh.triangleCount == 2 && groups[1].mesh.triangleCount == 1)
        #expect(abs(groups[0].mesh.bounds.max.z - 3) < 1e-12, "OBJ +Y is up")
        #expect(throws: InsertReadError.self) { try OBJReader.read("v 0 0 0\n") }
    }

    @Test func gbXMLSpacesFromTheirLowestLoop() throws {
        let xml = """
        <gbXML lengthUnit="Meters"><Campus><Building><Space id="sp1"><Name>Office &amp; Lab</Name><ShellGeometry><ClosedShell>
        <PolyLoop><CartesianPoint><Coordinate>0</Coordinate><Coordinate>0</Coordinate><Coordinate>0</Coordinate></CartesianPoint>
        <CartesianPoint><Coordinate>4</Coordinate><Coordinate>0</Coordinate><Coordinate>0</Coordinate></CartesianPoint>
        <CartesianPoint><Coordinate>4</Coordinate><Coordinate>3</Coordinate><Coordinate>0</Coordinate></CartesianPoint></PolyLoop>
        <PolyLoop><CartesianPoint><Coordinate>0</Coordinate><Coordinate>0</Coordinate><Coordinate>2.7</Coordinate></CartesianPoint>
        <CartesianPoint><Coordinate>4</Coordinate><Coordinate>0</Coordinate><Coordinate>2.7</Coordinate></CartesianPoint>
        <CartesianPoint><Coordinate>4</Coordinate><Coordinate>3</Coordinate><Coordinate>2.7</Coordinate></CartesianPoint></PolyLoop>
        </ClosedShell></ShellGeometry></Space><SpaceBoundary/></Building></Campus></gbXML>
        """
        let s = try GbXMLReader.read(xml)
        #expect(s.count == 1 && s[0].name == "Office & Lab" && s[0].number == "sp1" && s[0].floor.count == 3 && s[0].top == 2.7)
        let mm = try GbXMLReader.read(xml.replacingOccurrences(of: "Meters", with: "Millimeters"))
        #expect(abs(mm[0].top - 0.0027) < 1e-12)
        #expect(throws: InsertReadError.self) { try GbXMLReader.read("<xml/>") }
    }

    @Test func xpsPathGeometry() {
        let f = DWFxReader.figures("M 10,10 L 20,10 20,20 Z M0 0 l 5 0 h 5 v 5")
        #expect(f.count == 2)
        #expect(f[0] == [Vec2(10, 10), Vec2(20, 10), Vec2(20, 20), Vec2(10, 10)])
        #expect(f[1].last == Vec2(10, 5))
        #expect(DWFxReader.figures("M0,0 C 1,1 2,1 3,0").count == 1)
    }

    /// A zip archive of `files` (deflated when `deflate`).
    static func zip(_ files: [(String, Data)], deflate: Bool) -> Data {
        var out = Data(), central = Data()
        func u16(_ v: Int, _ d: inout Data) { d.append(UInt8(v & 0xff)); d.append(UInt8(v >> 8 & 0xff)) }
        func u32(_ v: Int, _ d: inout Data) { u16(v & 0xffff, &d); u16(v >> 16 & 0xffff, &d) }
        for (name, body) in files {
            var stored = body
            if deflate {
                var buf = [UInt8](repeating: 0, count: body.count + 1024)
                let n = body.withUnsafeBytes { src in compression_encode_buffer(&buf, buf.count, src.bindMemory(to: UInt8.self).baseAddress!, body.count, nil, COMPRESSION_ZLIB) }
                stored = Data(buf[0..<n])
            }
            let offset = out.count
            u32(0x04034b50, &out); u16(20, &out); u16(0, &out); u16(deflate ? 8 : 0, &out); u16(0, &out); u16(0, &out)
            u32(0, &out); u32(stored.count, &out); u32(body.count, &out); u16(name.utf8.count, &out); u16(0, &out)
            out.append(Data(name.utf8)); out.append(stored)
            u32(0x02014b50, &central); u16(20, &central); u16(20, &central); u16(0, &central); u16(deflate ? 8 : 0, &central); u16(0, &central); u16(0, &central)
            u32(0, &central); u32(stored.count, &central); u32(body.count, &central); u16(name.utf8.count, &central); u16(0, &central); u16(0, &central)
            u16(0, &central); u16(0, &central); u32(0, &central); u32(offset, &central)
            central.append(Data(name.utf8))
        }
        let cdOffset = out.count
        out.append(central)
        u32(0x06054b50, &out); u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out); u32(central.count, &out); u32(cdOffset, &out); u16(0, &out)
        return out
    }

    @Test(arguments: [false, true]) func dwfxPagesReadPathsGlyphsAndImages(deflate: Bool) throws {
        let page = """
        <FixedPage xmlns="http://schemas.microsoft.com/xps/2005/06" Width="960" Height="480" xml:lang="en-US">
        <Canvas Name="ArcusSheet"><Path Data="M 0,0 L 960,480" Stroke="#FF000000"/></Canvas>
        <Path Data="M 96,96 L 192,96 192,192" Stroke="#FFFF0000" StrokeThickness="2"/>
        <Glyphs OriginX="96" OriginY="384" FontRenderingEmSize="16" UnicodeString="Revise &amp; check" Fill="#FF0000FF"/>
        <Canvas RenderTransform="1,0,0,1,96,0"><Path Data="M 0,0 L 96,0 96,96 0,96 Z"><Path.Fill><ImageBrush ImageSource="/Resources/pic.png" Viewbox="0,0,10,10"/></Path.Fill></Path></Canvas>
        </FixedPage>
        """
        let png = Data([0x89, 0x50, 0x4e, 0x47, 1, 2, 3])
        let data = Self.zip([("Documents/1/Pages/A101.fpage", Data(page.utf8)), ("Resources/pic.png", png)], deflate: deflate)
        let pages = try DWFxReader.read(data)
        let p = try #require(pages.first)
        let u = 0.0254 / 96
        #expect(p.name == "A101" && abs(p.size.x - 960 * u) < 1e-12 && abs(p.size.y - 480 * u) < 1e-12)
        #expect(p.polylines.count == 1, "the sheet's own drawing is left out")
        #expect(abs(p.polylines[0].points[0].x - 96 * u) < 1e-12 && abs(p.polylines[0].points[0].y - (480 - 96) * u) < 1e-12)
        #expect(p.polylines[0].color == RGBColor(1, 0, 0))
        #expect(p.texts.first?.string == "Revise & check" && p.texts.first?.color == RGBColor(0, 0, 1))
        let pic = try #require(p.pictures.first)
        #expect(pic.image == png && abs(pic.bounds.min.x - 96 * u) < 1e-12 && abs(pic.bounds.max.x - 192 * u) < 1e-12)
        #expect(throws: InsertReadError.self) { try DWFxReader.read(Data("not a zip".utf8)) }
    }
}
