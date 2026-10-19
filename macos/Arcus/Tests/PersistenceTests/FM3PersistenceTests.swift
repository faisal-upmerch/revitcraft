import Foundation
import Testing
import ArcusGeometry
@testable import ArcusDomain
@testable import ArcusPersistence

/// FM3: `.arcusfurniture` packages: the same package as `.arcus`, with the furniture format and kind in the manifest,
/// and the parametric planes, setup and material costs intact after a save and open. Compiled families keep their
/// Furniture source through `.arcusfamily`.
@Suite("FM3 Furniture packages")
struct FM3PersistenceTests {
    @Test func furnitureDocumentRoundTrips() throws {
        let tmp = TempDir()
        let m = FurnitureTemplates.blank(category: .casework, name: "Vanity")
        let url = tmp.file("Vanity.arcusfurniture")
        try ArcusPackage.write(m, to: url, info: Sample.info)
        let manifest = try ArcusPackage.readManifest(url)
        #expect(manifest.format == PackageManifest.furnitureFormat && manifest.kind == "furniture")
        let (back, readManifest) = try ArcusPackage.read(from: url)
        #expect(readManifest.format == PackageManifest.furnitureFormat)
        #expect(back.isFurniture && back.furnitureSetup == m.furnitureSetup)
        #expect(back.count == m.count)
        let planes = FurniturePlanes.all(back)
        #expect(planes.count == 8)
        #expect(planes.first { $0.name == "Right" }?.referencePlane?.furniture?.offsetFormula == "Width / 2")
        #expect(back.elements(.materials).first { $0.name == "Solid Oak" }?.material?.costUnit == .boardFoot)
        #expect(ArcusPackage.verify(url).isHealthy, "\(ArcusPackage.verify(url).problems)")
    }

    @Test func projectsStayProjects() throws {
        let tmp = TempDir()
        let url = tmp.file("P.arcus")
        try ArcusPackage.write(ProjectTemplates.make(.empty, units: .imperial).0, to: url, info: Sample.info)
        let manifest = try ArcusPackage.readManifest(url)
        #expect(manifest.format == PackageManifest.projectFormat && manifest.kind == nil)
        #expect(try ArcusPackage.read(from: url).model.isFurniture == false)
    }

    @Test func compiledFamilyKeepsItsSourceInAFamilyFile() throws {
        let tmp = TempDir()
        let m = FurnitureTemplates.blank(name: "Bench")
        let family = FurnitureCompiler.family(from: m)
        let url = tmp.file("Bench.arcusfamily")
        try FamilyPackage.write(family, thumbnailPNG: nil, to: url, appVersion: "1.0", build: "1")
        let (back, _, _) = try FamilyPackage.read(from: url)
        #expect(back.furnitureSource != nil)
        #expect(FurnitureCompiler.source(of: back)?.furnitureSetup?.name == "Bench")
    }
}
