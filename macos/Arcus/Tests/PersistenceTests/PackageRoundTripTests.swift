import Foundation
import Testing
@testable import ArcusDomain
@testable import ArcusPersistence

@Suite("Package round trips")
struct PackageRoundTripTests {
    @Test func richModelRoundTripsExactly() throws {
        let tmp = TempDir()
        let model = try Sample.richModel()
        let url = tmp.file("House.arcus")
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let (read, manifest) = try ArcusPackage.read(from: url)
        Sample.expectEqual(model, read)
        #expect(manifest.elementCount == model.count)
        #expect(read.referenceDrawings.count == 2)
        #expect(read.projectParameters.count == 2)
        #expect(read.viewSheetSets.first?.name == "Issue 1")
        #expect(!read.schedules.isEmpty)
        #expect(!read.sheets.isEmpty)
        #expect(read.elements(.rooms).count == 1)
        #expect(read.elements(.doors).first?.mark == "D-101")
        // Non-finite parameter values survive.
        #expect(read.elements(.doors).first?[param: .user("abc")] == .double(.infinity))
    }

    @Test func manifestFieldsAreWritten() throws {
        let tmp = TempDir()
        let model = try Sample.richModel()
        let url = tmp.file("M.arcus")
        let before = Date()
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let m = try ArcusPackage.readManifest(url)
        #expect(m.format == "com.local.arcus.project")
        #expect(m.schemaVersion == ArcusPackage.currentSchemaVersion)
        #expect(m.schemaVersion == 3)
        #expect(m.minimumReaderVersion <= ArcusPackage.readerVersion)
        #expect(m.writerAppVersion == "1.2.3")
        #expect(m.writerBuild == "456")
        #expect(m.documentID == Sample.info.documentID)
        #expect(abs(m.created.timeIntervalSince(Sample.info.created!)) < 0.002)
        #expect(m.modified >= before.addingTimeInterval(-0.01))
        #expect(m.elementCount == model.count)
        #expect(m.checksums.keys.contains("model.sqlite"))
        #expect(m.checksums.keys.filter { $0.hasPrefix("assets/") }.count == 2)
        for (_, v) in m.checksums { #expect(v.count == 64) }
        #expect(ArcusPackage.readThumbnail(url) == Sample.info.thumbnailPNG)
    }

    @Test func packageLayoutOnDisk() throws {
        let tmp = TempDir()
        let url = tmp.file("L.arcus")
        try ArcusPackage.write(try Sample.richModel(), to: url, info: Sample.info)
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: url.appending(path: "manifest.json").path))
        #expect(fm.fileExists(atPath: url.appending(path: "model.sqlite").path))
        #expect(fm.fileExists(atPath: url.appending(path: "thumbnails/preview.png").path))
        let assets = try fm.contentsOfDirectory(atPath: url.appending(path: "assets").path)
        #expect(assets.count == 2)
        #expect(assets.allSatisfy { $0.hasSuffix(".lzfse") && $0.count == 64 + 6 })
        // No journal/WAL side files and no staging leftovers next to the package.
        let top = try fm.contentsOfDirectory(atPath: url.path).sorted()
        #expect(top == ["assets", "manifest.json", "model.sqlite", "thumbnails"])
        #expect(try fm.contentsOfDirectory(atPath: tmp.url.path) == ["L.arcus"])
        // SQLite header: rollback journal (bytes 18/19 == 1), not WAL.
        let header = try Data(contentsOf: url.appending(path: "model.sqlite")).prefix(20)
        #expect(Array(header.prefix(15)) == Array("SQLite format 3".utf8))
        #expect(header[18] == 1 && header[19] == 1)
    }

    @Test func fileWrapperRoundTrip() throws {
        let model = try Sample.richModel()
        let fw = try ArcusPackage.fileWrapper(model, info: Sample.info)
        #expect(fw.isDirectory)
        #expect(fw.fileWrappers?["manifest.json"] != nil)
        #expect(fw.fileWrappers?["assets"]?.isDirectory == true)
        let (read, manifest) = try ArcusPackage.read(fileWrapper: fw)
        Sample.expectEqual(model, read)
        #expect(manifest.documentID == Sample.info.documentID)
        // A wrapper written to disk reads identically through the URL path.
        let tmp = TempDir()
        let url = tmp.file("W.arcus")
        try fw.write(to: url, options: [], originalContentsURL: nil)
        Sample.expectEqual(model, try ArcusPackage.read(from: url).model)
    }

    @Test func overwritingExistingPackageReplacesItAtomically() throws {
        let tmp = TempDir()
        let url = tmp.file("R.arcus")
        let big = try Sample.richModel()
        try ArcusPackage.write(big, to: url, info: Sample.info)
        let small = BIMModel()
        var info = Sample.info
        info.thumbnailPNG = nil
        try ArcusPackage.write(small, to: url, info: info)
        let (read, m) = try ArcusPackage.read(from: url)
        #expect(read.count == 0)
        #expect(m.elementCount == 0)
        // Stale assets and thumbnail from the previous save are gone.
        #expect(!FileManager.default.fileExists(atPath: url.appending(path: "thumbnails/preview.png").path))
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: url.appending(path: "assets").path)) ?? []).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: tmp.url.path) == ["R.arcus"])
    }

    @Test func emptyModelRoundTrips() throws {
        let tmp = TempDir()
        let url = tmp.file("E.arcus")
        try ArcusPackage.write(BIMModel(), to: url, info: Sample.info)
        let (m, man) = try ArcusPackage.read(from: url)
        #expect(m.count == 0 && man.elementCount == 0)
        #expect(ArcusPackage.verify(url).isHealthy)
    }

    @Test func writeIsDeterministicForElementRows() throws {
        // Identical models produce identical element blobs (sorted keys) → stable diffs and checksums of content.
        let model = try Sample.richModel()
        let a = try ElementCodec.encode(model.allElements)
        let b = try ElementCodec.encode(model.allElements)
        #expect(a == b)
    }

    @Test func freshPackageVerifiesHealthy() throws {
        let tmp = TempDir()
        let url = tmp.file("V.arcus")
        try ArcusPackage.write(try Sample.richModel(), to: url, info: Sample.info)
        let r = ArcusPackage.verify(url)
        #expect(r.problems == [])
        #expect(r.isHealthy)
        #expect(r.lostElements == 0)
        #expect(r.recoveredElements > 100)
    }

    @Test func relationsTableCoversReferences() throws {
        let tmp = TempDir()
        let url = tmp.file("Rel.arcus")
        let model = try Sample.richModel()
        try ArcusPackage.write(model, to: url, info: Sample.info)
        let db = try SQLiteDatabase.openReadOnly(path: url.appending(path: "model.sqlite").path)
        let roles = Set(try db.strings("SELECT DISTINCT role FROM relations"))
        for r in ["type", "level", "host", "phaseCreated", "phaseDemolished", "designOption", "group"] { #expect(roles.contains(r), "missing role \(r)") }
        #expect(try db.scalarInt("PRAGMA user_version") == 2)
        #expect(try db.scalarInt("PRAGMA application_id") == Int64(ModelStore.applicationID))
        let hosted = try db.scalarInt("SELECT COUNT(*) FROM relations WHERE role = 'host'")
        #expect(hosted == 2)
        #expect(try db.strings("PRAGMA journal_mode") == ["delete"])
    }

    @Test func unusualFileNamesWork() throws {
        let tmp = TempDir()
        let dir = tmp.url.appending(path: "Projets été #2 ? (copie)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: "Maison 100% #1?.arcus", directoryHint: .isDirectory)
        let model = try Sample.richModel()
        try ArcusPackage.write(model, to: url, info: Sample.info)
        Sample.expectEqual(model, try ArcusPackage.read(from: url).model)
        #expect(ArcusPackage.verify(url).isHealthy)
    }
}
