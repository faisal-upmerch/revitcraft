import Foundation
import Testing
import ArcusGeometry
import ArcusCalc
@testable import ArcusDomain
@testable import ArcusPersistence

@Suite("Standard content persistence")
struct StandardContentPersistenceTests {
    /// An imperial project with library materials and hollow and I-section columns placed round-trips exactly.
    @Test func imperialProjectWithLibraryContentRoundTrips() throws {
        let tmp = TempDir()
        let (m0, ids) = ProjectTemplates.make(.architectural, units: .imperial, projectName: "Imperial")
        let tx = TransactionContext(model: m0, name: "Build")
        StandardContent.addMaterials(["Kota Stone", "Shoji Paper", "Copper, Patina"], to: tx)
        for (i, key) in ["Steel Column - HSS Rectangular: HSS8x8x1/2", "Steel Column - Wide Flange: W14x90", "Steel Column - Pipe: Pipe 6 Std.",
                         "Column - Round with Base and Capital: 16\" Diameter"].enumerated() {
            let type = try #require(ids.familyTypes[key], "\(key)")
            let cat: ArcusDomain.Category = key.hasPrefix("Column") ? .columns : .structuralColumns
            tx.create(cat, data: .column(ColumnData(location: Vec2(Double(i) * 3, 0), topLevelID: ids.levels[1])), typeID: type, levelID: ids.levels[0])
        }
        let model = try tx.commit().model
        let url = tmp.file("Imperial.arcus")
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let (read, _) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        #expect(read.units.system == .imperial)
        #expect(read.material(named: "Shoji Paper")?.material?.transparency == 0.35)
        let hss = try #require(read.elements(.structuralColumns).first { read.type(of: $0)?.name == "HSS8x8x1/2" })
        #expect(ComponentGeometry.planLoops(hss, read).count == 2)
    }

    /// Library column families save as `.arcusfamily` files readable by format-1 readers (voids and polygons only).
    @Test func columnFamiliesSaveAsFormatOneFamilies() throws {
        let tmp = TempDir()
        for entry in ColumnLibrary.families(.metric) where !entry.family.solids.contains(where: { !$0.profile.isExtrusion }) {
            let url = tmp.file("\(entry.family.name).arcusfamily")
            try FamilyPackage.write(entry.family, thumbnailPNG: nil, to: url, appVersion: "1", build: "1")
            let (read, _, manifest) = try FamilyPackage.read(from: url)
            #expect(read == entry.family)
            #expect(manifest.minimumReaderVersion == 1, "\(entry.family.name)")
        }
    }
}
